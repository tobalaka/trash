--!strict
--[[
	StationService - trades at NPC stations (vault: Stations). One remote, StationAction(npcId,
	action, id, qty), checked every time: the NPC runs that station, the player stands next to
	them, faction-only stations serve only that faction, and the player can pay.

	  Buy      Store       Dollars -> supplies (your own faction's quartermaster: discount)
	  Sort     Recycler    recyclables -> Scrap (+25% for Menders); unlocks the material's Field Note
	  Sell     Fence       items -> Dollars (+25% for Scrappers); unlocks the material's Field Note
	  Craft    Workbench   recipes (water filter, bandage, respirator)
	  Process  Purifier / Smelter   faction recipes that move the server's pollution
	  Upgrade  Blacksmith  next Relic tier
	`id` "*" with Sort or Sell means every eligible item.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Economy = require(Config:WaitForChild("Economy"))
local Levels = require(Config:WaitForChild("Levels"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Stations = require(Shared:WaitForChild("Data"):WaitForChild("Stations"))
local Npcs = require(Shared:WaitForChild("Data"):WaitForChild("Npcs"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Pollution = require(script.Parent:WaitForChild("Pollution"))
local Blacksmith = require(script.Parent:WaitForChild("Blacksmith"))
local Anchors = require(script.Parent:WaitForChild("Anchors"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local ACTION_RATE = 6
local REACH = Npcs.TALK_DISTANCE * 2
local MAX_CRAFT = 5

local ACTION_KIND = { Buy = "Store", Sort = "Recycler", Sell = "Fence", Craft = "Workbench", Upgrade = "Blacksmith" }

local StationService = {}

local function hasStation(npc: Npcs.Npc, kind: string): boolean
	return npc.stations ~= nil and table.find(npc.stations, kind) ~= nil
end

local function toast(player: Player, text: string, color: string?)
	Sync.notify(player, "Toast", { text = text, color = color or "Red" })
end

function StationService.price(player: Player, npc: Npcs.Npc, itemId: string): number?
	local base = Economy.STORE[itemId]
	if not base then
		return nil
	end
	local p = Profiles.get(player)
	local discount = if p and npc.faction and p.faction == npc.faction then Economy.FACTION_STORE_DISCOUNT else 0
	return math.max(1, math.floor(base * (1 - discount) + 0.5))
end

local function buy(player: Player, npc: Npcs.Npc, id: string, qty: number)
	local price = StationService.price(player, npc, id)
	local item = Items.get(id)
	if not price or not item then
		return toast(player, "Not sold here.")
	end
	local total = price * qty
	if not Inventory.spend(player, { dollars = total }) then
		return toast(player, string.format("You need $%d.", total))
	end
	Inventory.give(player, id, qty)
	toast(player, string.format("Bought %s x%d for $%d", item.name, qty, total), "Lime")
	Bus.emit(player, "Buy", { item = id, count = qty })
end

-- Sort (Recycler) and Sell (Fence) share the shape: items in, currency out
local function trade(player: Player, mode: string, id: string, qty: number)
	local p = Profiles.get(player) :: Profiles.Profile
	local list: { string } = {}
	if id == "*" then
		for _, item in Items.list do
			if (p.items[item.id] or 0) > 0 and ((mode == "Sort" and item.sort) or (mode == "Sell" and item.sell and item.category ~= "Supplies" and item.category ~= "Tokens")) then
				table.insert(list, item.id)
			end
		end
	else
		table.insert(list, id)
	end
	local bonus = if mode == "Sort" then (Economy.SORT_BONUS :: any)[p.faction or ""] or 0 else (Economy.SELL_BONUS :: any)[p.faction or ""] or 0
	local earned, moved = 0, 0
	for _, itemId in list do
		local item = Items.get(itemId)
		local unit = item and (if mode == "Sort" then item.sort else item.sell)
		local have = p.items[itemId] or 0
		local n = if id == "*" then have else math.min(qty, have)
		if item and unit and n > 0 and Inventory.take(player, itemId, n) then
			earned += unit * n
			moved += n
			Progress.unlockNote(player, item.note)
			Bus.emit(player, if mode == "Sort" then "Recycle" else "Sell", { item = itemId, count = n })
		end
	end
	if moved == 0 then
		return toast(player, if mode == "Sort" then "Nothing here to sort." else "Nothing here to sell.")
	end
	local total = math.floor(earned * (1 + bonus) + 0.5)
	if mode == "Sort" then
		Inventory.earn(player, { scrap = total })
		Progress.addExp(player, Levels.EXP.RECYCLE_ITEM * moved)
		toast(player, string.format("Sorted %d item%s: +%d Scrap", moved, if moved == 1 then "" else "s", total), "Lime")
	else
		Inventory.earn(player, { dollars = total })
		toast(player, string.format("Sold %d item%s: +$%d", moved, if moved == 1 then "" else "s", total), "Lime")
	end
end

local function craft(player: Player, npc: Npcs.Npc, recipeId: string, qty: number)
	local recipe = Stations.recipeById[recipeId]
	if not recipe then
		return toast(player, "Unknown recipe.")
	end
	-- the station kind this recipe needs, and the faction that station serves
	local needKind = if recipe.kind == "Craft" then "Workbench" elseif recipe.kind == "Purify" then "Purifier" else "Smelter"
	if not hasStation(npc, needKind) then
		return toast(player, "That can't be made here.")
	end
	local p = Profiles.get(player) :: Profiles.Profile
	local stationFaction = Stations.KINDS[needKind].faction
	if stationFaction and p.faction ~= stationFaction then
		return toast(player, "Only the " .. stationFaction .. " use this.")
	end
	local made = 0
	for _ = 1, math.clamp(qty, 1, MAX_CRAFT) do
		if not Inventory.has(player, recipe.needs) or not Inventory.canAfford(player, { scrap = recipe.scrap, residue = recipe.residue }) then
			break
		end
		Inventory.takeAll(player, recipe.needs)
		Inventory.spend(player, { scrap = recipe.scrap, residue = recipe.residue })
		for id, n in recipe.gives do
			Inventory.give(player, id, n)
		end
		if recipe.dollars then
			Inventory.earn(player, { dollars = recipe.dollars })
		end
		if recipe.pollution then
			Pollution.apply(recipe.pollution)
		end
		if recipe.standing then
			Progress.addStanding(player, recipe.standing)
		end
		made += 1
	end
	if made == 0 then
		return toast(player, "You're missing materials.")
	end
	Progress.addExp(player, (if recipe.kind == "Craft" then Levels.EXP.CRAFT else Levels.EXP.PROCESS) * made)
	Progress.unlockNote(player, recipe.note)
	toast(player, string.format("%s x%d", recipe.name, made), "Lime")
	if recipe.kind == "Craft" then
		Bus.emit(player, "Craft", { recipe = recipe.id, count = made })
	else
		for _ = 1, made do
			Bus.emit(player, "Process", { recipe = recipe.kind })
		end
	end
end

function StationService.act(player: Player, npcId: string, action: string, id: string, qty: number)
	local npc = Npcs.byId[npcId]
	if not npc then
		return
	end
	if not Anchors.near(player, npcId, REACH) then
		return toast(player, "You're too far away.")
	end
	if not Profiles.get(player) then
		return
	end
	-- buying and crafting come in small batches; sorting and selling may move a whole stack
	local cap = if action == "Sort" or action == "Sell" then Economy.MAX_STACK else Economy.MAX_BUY
	qty = math.clamp(math.floor(qty), 1, cap)
	if action == "Craft" or action == "Process" then
		return craft(player, npc, id, qty)
	end
	local kind = ACTION_KIND[action]
	if not kind or not hasStation(npc, kind) then
		return toast(player, "Not here.")
	end
	if action == "Buy" then
		buy(player, npc, id, qty)
	elseif action == "Sort" or action == "Sell" then
		trade(player, action, id, qty)
	elseif action == "Upgrade" then
		local err = Blacksmith.upgrade(player, npc.faction)
		if err then
			toast(player, err)
		end
	end
end

function StationService.start()
	Remotes.get("StationAction").OnServerEvent:Connect(function(player, npcId, action, id, qty)
		if not Guard.allow(player, "StationAction", ACTION_RATE) then
			return
		end
		if typeof(npcId) ~= "string" or typeof(action) ~= "string" or typeof(id) ~= "string" then
			return
		end
		local n = if typeof(qty) == "number" and qty == qty then qty else 1
		StationService.act(player, npcId, action, id, n)
	end)
end

return StationService
