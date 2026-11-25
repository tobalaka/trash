--!strict
--[[
	Sync - shows a player their progression. Two channels (Client-Server-Split: the UI only
	displays what the server sends):
	  - player attributes for the HUD's single values (Theme.Attr names): Dollars, Scrap,
	    AnimaResidue, Faction, Rank, Level, Relic, RelicRarity, UpgradeTier,
	    FinalUpgradeUnlocked (read by CombatService for the 5th M1 hit), Exp, ExpNext, Standing,
	    StandingNext, SkillPoints
	  - a ProfileSync snapshot for lists (inventory, quests, notes, perks, the pending roll),
	    batched to at most one send per SEND_GAP
	Other systems add their own part of the snapshot with Sync.contribute.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))
local Levels = require(Shared:WaitForChild("Config"):WaitForChild("Levels"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))

local SEND_GAP = 0.2

local Sync = {}

local contributors: { (Player, Profiles.Profile, { [string]: any }) -> () } = {}
local scheduled: { [Player]: boolean } = {}

function Sync.contribute(fn: (Player, Profiles.Profile, { [string]: any }) -> ())
	table.insert(contributors, fn)
end

local function set(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

-- HUD attributes
function Sync.publish(player: Player)
	local p = Profiles.get(player)
	if not p then
		return
	end
	set(player, "Dollars", p.dollars)
	set(player, "Scrap", p.scrap)
	set(player, "AnimaResidue", p.residue)
	set(player, "Faction", p.faction or Factions.UNALIGNED)
	set(player, "Rank", Factions.rankName(p.faction, p.standing))
	set(player, "RankIndex", Factions.rankIndex(p.faction, p.standing))
	set(player, "Standing", p.standing)
	local info = if p.faction then Factions.INFO[p.faction] else nil
	local nextRank = if info then info.ranks[Factions.rankIndex(p.faction, p.standing) + 1] else nil
	set(player, "StandingNext", if nextRank then nextRank.standing else nil)
	set(player, "Level", p.level)
	-- at the cap the bar shows Overflow progress instead (Progress pays a reward per bar)
	local capped = p.level >= Levels.MAX
	set(player, "Exp", if capped then p.stats.overflow or 0 else p.exp)
	set(player, "ExpNext", if capped then Levels.OVERFLOW_EXP else Levels.need(p.level))
	set(player, "LevelMax", Levels.MAX)
	set(player, "SkillPoints", p.points)
	local j = p.relic
	set(player, "Relic", if j then j.id else nil)
	set(player, "RelicRarity", if j then j.rarity else nil)
	set(player, "UpgradeTier", if j then j.tier else 0)
	set(player, "FinalUpgradeUnlocked", j ~= nil and j.tier >= Economy.MAX_TIER)
end

local function snapshot(player: Player, p: Profiles.Profile): { [string]: any }
	local active = {}
	for id, q in p.quests.active do
		active[id] = { step = q.step, progress = q.progress, tracked = q.tracked }
	end
	local snap: { [string]: any } = {
		faction = p.faction,
		relic = p.relic,
		pending = p.pending,
		level = p.level,
		exp = p.exp,
		points = p.points,
		perks = p.perks,
		standing = p.standing,
		pity = p.pity,
		items = p.items,
		quests = { active = active, done = p.quests.done },
		notes = p.notes,
		readOnly = Profiles.isReadOnly(player),
	}
	for _, fn in contributors do
		pcall(fn, player, p, snap)
	end
	return snap
end

-- Sends the snapshot soon (batched).
function Sync.push(player: Player)
	if scheduled[player] then
		return
	end
	scheduled[player] = true
	task.delay(SEND_GAP, function()
		scheduled[player] = nil
		local p = Profiles.get(player)
		if p and player.Parent then
			Remotes.get("ProfileSync"):FireClient(player, snapshot(player, p))
		end
	end)
end

-- After any change to a profile: save later, update the HUD, resend the lists.
function Sync.changed(player: Player)
	Profiles.markDirty(player)
	Sync.publish(player)
	Sync.push(player)
end

function Sync.notify(player: Player, kind: string, data: { [string]: any }?)
	Remotes.get("Notify"):FireClient(player, kind, data or {})
end

function Sync.start()
	Remotes.get("RequestSync").OnServerEvent:Connect(function(player)
		if Profiles.get(player) then
			Sync.publish(player)
			Sync.push(player)
		end
	end)
	Profiles.onLoaded(function(player)
		Sync.publish(player)
		Sync.push(player)
	end)
end

return Sync
