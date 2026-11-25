--!strict
--[[
	Gacha - the faction Relic roll (vault: Gacha). Server RNG only; odds and pity live in
	Config.Economy and are shown to players in the Blacksmith window before they roll.

	  - Joining a faction rolls once for free.
	  - Later rolls cost a Relic Spin (earned from quests, levels and ranks) or Dollars. No Robux:
	    paid spins stay out until Roblox's odds-disclosure rules have been checked (Gacha.md).
	  - Pity: the PITY_RARE-th roll in a row without Rare or better is Rare; the
	    PITY_LEGENDARY-th without a Legendary is Legendary.
	  - If you already have a Relic, the roll waits as `pending` and you choose: keep the new one
	    or keep yours. Blacksmith upgrades stay with you either way (the mastery is yours, not the
	    weapon's). Rolling the one you hold gives Anima Residue instead.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local DUPLICATE_RESIDUE = 10
local ROLL_RATE = 1

local Gacha = {}

local rng = Random.new()
local onEquip: ((Player) -> ())? = nil

local function pickRarity(p: Profiles.Profile): string
	local pity = p.pity
	if pity.legendary + 1 >= Economy.PITY_LEGENDARY then
		return "Legendary"
	end
	local r = rng:NextNumber(0, 100)
	local odds = Economy.ROLL_ODDS
	if r < odds.Legendary then
		return "Legendary"
	end
	if r < odds.Legendary + odds.Rare or pity.rare + 1 >= Economy.PITY_RARE then
		return "Rare"
	end
	return "Common"
end

local function poolPick(faction: string, rarity: string): Relics.Relic?
	local options = {}
	for _, j in Relics.byFaction[faction] or {} do
		if j.rarity == rarity then
			table.insert(options, j)
		end
	end
	if #options == 0 then
		return nil
	end
	return options[rng:NextInteger(1, #options)]
end

-- Rolls for `player`. `free` skips payment (the joining roll). Returns an error string on failure.
function Gacha.roll(player: Player, free: boolean): string?
	local p = Profiles.get(player)
	if not p or not p.faction then
		return "Join a faction first."
	end
	if p.pending then
		return "Decide on your last roll first."
	end
	if not free then
		if not Inventory.take(player, "SpinToken", 1) and not Inventory.spend(player, { dollars = Economy.SPIN_DOLLARS }) then
			return string.format("You need a Relic Spin or $%d.", Economy.SPIN_DOLLARS)
		end
	end
	local rarity = pickRarity(p)
	local relic = poolPick(p.faction :: string, rarity)
	if not relic then
		return "This faction's pool is empty."
	end
	-- pity counters
	if rarity == "Legendary" then
		p.pity.legendary = 0
		p.pity.rare = 0
	elseif rarity == "Rare" then
		p.pity.rare = 0
		p.pity.legendary += 1
	else
		p.pity.rare += 1
		p.pity.legendary += 1
	end
	local current = p.relic
	local result: { [string]: any } = { id = relic.id, rarity = rarity }
	if not current then
		p.relic = { id = relic.id, rarity = rarity, tier = 0 }
		result.equipped = true
	elseif current.id == relic.id then
		p.residue += DUPLICATE_RESIDUE
		result.duplicate = true
		result.residue = DUPLICATE_RESIDUE
	else
		p.pending = { id = relic.id, rarity = rarity }
		result.pending = true
		result.current = current.id
	end
	Sync.changed(player)
	Remotes.get("RollResult"):FireClient(player, result)
	Bus.emit(player, "Roll", { id = relic.id, rarity = rarity })
	if result.equipped and onEquip then
		onEquip(player)
	end
	return nil
end

function Gacha.choose(player: Player, keepNew: boolean)
	local p = Profiles.get(player)
	if not p or not p.pending then
		return
	end
	local pending = p.pending :: { id: string, rarity: string }
	if keepNew then
		local tier = if p.relic then p.relic.tier else 0
		p.relic = { id = pending.id, rarity = pending.rarity, tier = tier }
	end
	p.pending = nil
	Sync.changed(player)
	if keepNew and onEquip then
		onEquip(player)
	end
	local j = Relics.get(if keepNew then pending.id else (p.relic and p.relic.id))
	if j then
		Sync.notify(player, "Toast", { text = "Wielding " .. j.name, color = "Gold" })
	end
end

-- called whenever the equipped Relic changes (Gear and RelicService refresh)
function Gacha.onEquip(fn: (Player) -> ())
	onEquip = fn
end

function Gacha.start()
	Remotes.get("RollRelic").OnServerEvent:Connect(function(player)
		if not Guard.allow(player, "RollRelic", ROLL_RATE) then
			return
		end
		local err = Gacha.roll(player, false)
		if err then
			Sync.notify(player, "Toast", { text = err, color = "Red" })
		end
	end)
	Remotes.get("RollChoice").OnServerEvent:Connect(function(player, keepNew)
		if typeof(keepNew) == "boolean" then
			Gacha.choose(player, keepNew)
		end
	end)
end

return Gacha
