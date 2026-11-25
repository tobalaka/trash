--!strict
--[[
	Inventory - items and the wallet (Dollars, Scrap, Anima Residue). The server is the only
	writer; clients see the result through Sync. Every check-and-take is atomic within one call.

	Quick items (Items.quick: food, water, bandages, respirators) also sit on the hotbar as Tools
	named "<Item> x<count>". Activating one uses it (Survival.use) and puts it away again.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))

local TOOL_ATTR = "QuickItem"

export type Cost = { dollars: number?, scrap: number?, residue: number? }

local Inventory = {}

local useHandler: ((Player, string) -> ())? = nil
local toolSyncQueued: { [Player]: boolean } = {}

function Inventory.count(player: Player, id: string): number
	local p = Profiles.get(player)
	return if p then p.items[id] or 0 else 0
end

function Inventory.has(player: Player, needs: { [string]: number }): boolean
	local p = Profiles.get(player)
	if not p then
		return false
	end
	for id, n in needs do
		if (p.items[id] or 0) < n then
			return false
		end
	end
	return true
end

function Inventory.give(player: Player, id: string, n: number)
	local p = Profiles.get(player)
	if not p or n <= 0 or not Items.get(id) then
		return
	end
	p.items[id] = math.min(Economy.MAX_STACK, (p.items[id] or 0) + math.floor(n))
	Sync.changed(player)
	Inventory.syncTools(player)
end

function Inventory.take(player: Player, id: string, n: number): boolean
	local p = Profiles.get(player)
	if not p or n <= 0 or (p.items[id] or 0) < n then
		return false
	end
	p.items[id] -= n
	if p.items[id] <= 0 then
		p.items[id] = nil
	end
	Sync.changed(player)
	Inventory.syncTools(player)
	return true
end

-- takes every listed item, or nothing
function Inventory.takeAll(player: Player, needs: { [string]: number }): boolean
	if not Inventory.has(player, needs) then
		return false
	end
	local p = Profiles.get(player) :: Profiles.Profile
	for id, n in needs do
		p.items[id] -= n
		if p.items[id] <= 0 then
			p.items[id] = nil
		end
	end
	Sync.changed(player)
	Inventory.syncTools(player)
	return true
end

function Inventory.canAfford(player: Player, cost: Cost): boolean
	local p = Profiles.get(player)
	if not p then
		return false
	end
	return p.dollars >= (cost.dollars or 0) and p.scrap >= (cost.scrap or 0) and p.residue >= (cost.residue or 0)
end

-- pays the whole cost, or nothing
function Inventory.spend(player: Player, cost: Cost): boolean
	if not Inventory.canAfford(player, cost) then
		return false
	end
	local p = Profiles.get(player) :: Profiles.Profile
	p.dollars -= cost.dollars or 0
	p.scrap -= cost.scrap or 0
	p.residue -= cost.residue or 0
	Sync.changed(player)
	return true
end

function Inventory.earn(player: Player, gain: Cost)
	local p = Profiles.get(player)
	if not p then
		return
	end
	p.dollars += math.max(0, math.floor(gain.dollars or 0))
	p.scrap += math.max(0, math.floor(gain.scrap or 0))
	p.residue += math.max(0, math.floor(gain.residue or 0))
	Sync.changed(player)
end

-- ── hotbar Tools for quick items ──

local function makeTool(id: string): Tool
	local tool = Instance.new("Tool")
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ManualActivationOnly = false
	tool:SetAttribute(TOOL_ATTR, id)
	local item = Items.get(id)
	if item then
		tool:SetAttribute("Rarity", item.rarity)
		tool.ToolTip = item.desc
	end
	tool.Activated:Connect(function()
		local owner = Players:GetPlayerFromCharacter(tool.Parent)
		if owner and useHandler then
			useHandler(owner, id)
			local humanoid = (tool.Parent :: Instance):FindFirstChildOfClass("Humanoid")
			if humanoid and tool.Parent then
				humanoid:UnequipTools()
			end
		end
	end)
	return tool
end

-- Makes the player's Backpack hold one Tool per quick item they own, named with the count.
function Inventory.syncTools(player: Player)
	if toolSyncQueued[player] then
		return
	end
	toolSyncQueued[player] = true
	task.defer(function()
		toolSyncQueued[player] = nil
		local p = Profiles.get(player)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not p or not backpack then
			return
		end
		local existing: { [string]: Tool } = {}
		for _, container in { backpack, player.Character } do
			if container then
				for _, t in container:GetChildren() do
					local id = t:IsA("Tool") and t:GetAttribute(TOOL_ATTR)
					if typeof(id) == "string" then
						existing[id] = t :: Tool
					end
				end
			end
		end
		for _, item in Items.list do
			if item.quick then
				local n = p.items[item.id] or 0
				local tool = existing[item.id]
				if n > 0 then
					if not tool then
						tool = makeTool(item.id)
						tool.Parent = backpack
					end
					local name = string.format("%s x%d", item.name, n)
					if (tool :: Tool).Name ~= name then
						(tool :: Tool).Name = name
					end
				elseif tool then
					tool:Destroy()
				end
			end
		end
	end)
end

function Inventory.onUse(fn: (Player, string) -> ())
	useHandler = fn
end

function Inventory.start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			Inventory.syncTools(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Profiles.onLoaded(function(player)
		Inventory.syncTools(player)
	end)
end

return Inventory
