--!strict
--[[
	Progress - EXP and levels, faction standing and ranks, skill-path perks, Field Notes, and the
	one place rewards are granted (so every reward toast looks the same).

	Perks (Config.Levels.PATHS) are bought in order along a path with skill points and stay
	locked in; a Stat Reset Pill refunds every point. Progress.effects(player) merges the bought
	perks into one Effect table that the other systems read; the two perks the client needs to
	know about are mirrored as player attributes (DashRange, SalvageSpeed, FieldRevive).

	Caps: at Levels.MAX, EXP fills Overflow bars (OVERFLOW_EXP each, kept in stats.overflow) that
	pay OVERFLOW_REWARD. Reaching level 40, a faction's top rank, or every Field Note gives a
	title (Titles).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Levels = require(Config:WaitForChild("Levels"))
local Factions = require(Config:WaitForChild("Factions"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local FieldNotes = require(Shared:WaitForChild("Data"):WaitForChild("FieldNotes"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Bus = require(script.Parent:WaitForChild("Bus"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Titles = require(script.Parent:WaitForChild("Titles"))

export type Rewards = {
	title: string?,
	exp: number?,
	dollars: number?,
	scrap: number?,
	residue: number?,
	standing: number?,
	items: { [string]: number }?,
}

local BASE_HEALTH = 100
local PERK_RATE = 4 -- InvestPerk / UseResetPill requests per second
local TOP_RANK_TITLE = { Menders = "Steward", Scrappers = "Boss" }

local Progress = {}

local effectCache: { [Player]: Levels.Effect } = {}

-- ── perks ──

function Progress.effects(player: Player): Levels.Effect
	local cached = effectCache[player]
	if cached then
		return cached
	end
	local merged: { [string]: any } = {}
	local p = Profiles.get(player)
	if p then
		for _, path in Levels.PATHS do
			local bought = p.perks[path.id] or 0
			for i = 1, math.min(bought, #path.perks) do
				for k, v in path.perks[i].effect :: { [string]: any } do
					if typeof(v) == "number" then
						merged[k] = (merged[k] or 0) + v
					else
						merged[k] = v
					end
				end
			end
		end
	end
	effectCache[player] = merged :: Levels.Effect
	return merged :: Levels.Effect
end

function Progress.applyMaxHealth(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local max = BASE_HEALTH + (Progress.effects(player).maxHealth or 0)
	if humanoid.MaxHealth ~= max then
		local ratio = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 1
		humanoid.MaxHealth = max
		humanoid.Health = math.min(max, max * ratio)
	end
end

-- the perks the client needs to know about (its own dash distance and salvage prompt time)
local function publishPerks(player: Player)
	local fx = Progress.effects(player)
	player:SetAttribute("DashRange", 1 + (fx.dashRange or 0))
	player:SetAttribute("SalvageSpeed", 1 - (fx.salvageSpeed or 0))
	player:SetAttribute("FieldRevive", if fx.revive then true else nil)
end

local function perksChanged(player: Player)
	effectCache[player] = nil
	Progress.applyMaxHealth(player)
	publishPerks(player)
	Sync.changed(player)
end

function Progress.investPerk(player: Player, pathId: string): (boolean, string?)
	local p = Profiles.get(player)
	local path = Levels.pathById[pathId]
	if not p or not path then
		return false, "Unknown path."
	end
	local bought = p.perks[pathId] or 0
	local perk = path.perks[bought + 1]
	if not perk then
		return false, "That path is complete."
	end
	if p.points < perk.cost then
		return false, string.format("%s needs %d skill point%s.", perk.name, perk.cost, if perk.cost == 1 then "" else "s")
	end
	p.points -= perk.cost
	p.perks[pathId] = bought + 1
	perksChanged(player)
	Sync.notify(player, "Perk", { path = path.title, name = perk.name, desc = perk.desc })
	return true, nil
end

function Progress.resetPerks(player: Player): (boolean, string?)
	local p = Profiles.get(player)
	if not p then
		return false, nil
	end
	local refunded = 0
	for _, path in Levels.PATHS do
		for i = 1, p.perks[path.id] or 0 do
			refunded += path.perks[i].cost
		end
	end
	if refunded == 0 then
		return false, "You have no skill points spent."
	end
	if not Inventory.take(player, "ResetPill", 1) then
		return false, "You need a Stat Reset Pill."
	end
	p.perks = {}
	p.points += refunded
	perksChanged(player)
	Sync.notify(player, "Toast", { text = string.format("Skill points refunded: %d", refunded), color = "Gold" })
	return true, nil
end

-- ── EXP and levels ──

-- past the cap: EXP fills Overflow bars, each paying OVERFLOW_REWARD
local function overflow(player: Player, p: Profiles.Profile, amount: number)
	local bar = (p.stats.overflow or 0) + math.floor(amount)
	while bar >= Levels.OVERFLOW_EXP do
		bar -= Levels.OVERFLOW_EXP
		local r = Levels.OVERFLOW_REWARD
		Inventory.earn(player, { residue = r.residue })
		local extras = { string.format("+%d Anima Residue", r.residue) }
		for id, n in r.items do
			Inventory.give(player, id, n)
			local item = Items.get(id)
			table.insert(extras, string.format("%s x%d", if item then item.name else id, n))
		end
		Sync.notify(player, "LevelUp", { level = p.level, points = 0, overflow = true, extras = extras })
	end
	p.stats.overflow = bar
	Sync.changed(player)
end

function Progress.addExp(player: Player, amount: number)
	local p = Profiles.get(player)
	if not p or amount <= 0 then
		return
	end
	if p.level >= Levels.MAX then
		overflow(player, p, amount)
		return
	end
	p.exp += math.floor(amount)
	local leveled = false
	while p.level < Levels.MAX and p.exp >= Levels.need(p.level) do
		p.exp -= Levels.need(p.level)
		p.level += 1
		p.points += Levels.POINTS_PER_LEVEL
		leveled = true
		local reward = Levels.REWARDS[p.level]
		local extras = {}
		if reward then
			for id, n in reward.items do
				Inventory.give(player, id, n)
				local item = Items.get(id)
				table.insert(extras, string.format("%s x%d", if item then item.name else id, n))
			end
		end
		Sync.notify(player, "LevelUp", { level = p.level, points = Levels.POINTS_PER_LEVEL, extras = extras })
		Bus.emit(player, "Level", { level = p.level })
		if reward and reward.title then
			Titles.grant(player, reward.title)
		end
	end
	if p.level >= Levels.MAX then
		-- whatever was left past the last level carries into the first Overflow bar
		local left = p.exp
		p.exp = 0
		if left > 0 then
			overflow(player, p, left)
		end
	end
	if leveled then
		Progress.applyMaxHealth(player)
	end
	Sync.changed(player)
end

-- ── faction standing and ranks ──

function Progress.addStanding(player: Player, amount: number)
	local p = Profiles.get(player)
	if not p or not p.faction or amount <= 0 then
		return
	end
	local before = Factions.rankIndex(p.faction, p.standing)
	p.standing += math.floor(amount)
	local after = Factions.rankIndex(p.faction, p.standing)
	for rank = before + 1, after do
		local reward = Factions.RANK_REWARDS[rank]
		local extras = {}
		if reward then
			if reward.dollars then
				Inventory.earn(player, { dollars = reward.dollars })
				table.insert(extras, string.format("$%d", reward.dollars))
			end
			for id, n in reward.items or {} do
				Inventory.give(player, id, n)
				local item = Items.get(id)
				table.insert(extras, string.format("%s x%d", if item then item.name else id, n))
			end
		end
		Sync.notify(player, "RankUp", { faction = p.faction, rank = Factions.INFO[p.faction :: string].ranks[rank].name, extras = extras })
		if rank == #Factions.INFO[p.faction :: string].ranks then
			Titles.grant(player, TOP_RANK_TITLE[p.faction :: string])
		end
	end
	Sync.changed(player)
end

-- ── Field Notes ──

function Progress.unlockNote(player: Player, id: string?)
	local p = Profiles.get(player)
	if not p or not id or p.notes[id] then
		return
	end
	local note = FieldNotes.byId[id]
	if not note then
		return
	end
	p.notes[id] = os.time()
	Sync.notify(player, "Note", { id = id, title = note.title })
	Sync.changed(player)
	local have = 0
	for _ in p.notes do
		have += 1
	end
	if have >= #FieldNotes.list then
		Titles.grant(player, "Archivist")
	end
end

-- ── rewards ──

-- Grants a reward bundle and shows one toast listing it. `title` heads the toast.
function Progress.grant(player: Player, r: Rewards, title: string?)
	local lines = {}
	if r.exp and r.exp > 0 then
		table.insert(lines, string.format("+%d EXP", r.exp))
	end
	if r.dollars and r.dollars > 0 then
		table.insert(lines, string.format("+$%d", r.dollars))
	end
	if r.scrap and r.scrap > 0 then
		table.insert(lines, string.format("+%d Scrap", r.scrap))
	end
	if r.residue and r.residue > 0 then
		table.insert(lines, string.format("+%d Anima Residue", r.residue))
	end
	if r.standing and r.standing > 0 then
		local p = Profiles.get(player)
		if p and p.faction then
			table.insert(lines, string.format("+%d %s standing", r.standing, p.faction))
		end
	end
	Inventory.earn(player, { dollars = r.dollars, scrap = r.scrap, residue = r.residue })
	for id, n in r.items or {} do
		Inventory.give(player, id, n)
		local item = Items.get(id)
		table.insert(lines, string.format("%s x%d", if item then item.name else id, n))
	end
	if r.standing then
		Progress.addStanding(player, r.standing)
	end
	if r.exp then
		Progress.addExp(player, r.exp)
	end
	if title and #lines > 0 then
		Sync.notify(player, "Reward", { title = title, lines = lines })
	end
	if r.title then
		Titles.grant(player, r.title)
	end
end

function Progress.start()
	Remotes.get("InvestPerk").OnServerEvent:Connect(function(player, pathId)
		if typeof(pathId) ~= "string" or not Guard.allow(player, "Perk", PERK_RATE) then
			return
		end
		local ok, why = Progress.investPerk(player, pathId)
		if not ok and why then
			Sync.notify(player, "Toast", { text = why, color = "Red" })
		end
	end)
	Remotes.get("UseResetPill").OnServerEvent:Connect(function(player)
		if not Guard.allow(player, "Perk", PERK_RATE) then
			return
		end
		local ok, why = Progress.resetPerks(player)
		if not ok and why then
			Sync.notify(player, "Toast", { text = why, color = "Red" })
		end
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			task.wait(0.2)
			Progress.applyMaxHealth(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		effectCache[player] = nil
	end)
	Profiles.onLoaded(function(player)
		Progress.applyMaxHealth(player)
		publishPerks(player)
	end)
end

return Progress
