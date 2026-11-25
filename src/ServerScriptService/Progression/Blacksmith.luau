--!strict
--[[
	Blacksmith - upgrades the equipped Relic one tier at a time (vault: Blacksmith).
	  Tier 1 unlocks Z, 2 unlocks X, 3 unlocks C, 4 is M1 Mastery: the 5th M1 hit, hyper-armour
	  on grabs and maximum strength. CombatService already reads the FinalUpgradeUnlocked attribute
	  that Sync sets, so combat code is untouched.
	Each tier needs a character level, a faction rank, Scrap, Anima Residue and salvaged materials
	(Config.Economy.TIERS); tier 4 also needs the Junk Ram's heart and the faction's own processed
	material. Only your own faction's Blacksmith will work for you. Everything is checked, then
	everything is taken, in one step.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local Blacksmith = {}

export type Requirement = { label: string, have: number, need: number, ok: boolean }
export type Quote = { tier: number, unlocks: string, scrap: number, residue: number, items: { [string]: number }, reqs: { Requirement }, ready: boolean }

-- What the next tier costs this player, and whether they can pay it.
function Blacksmith.quote(player: Player): Quote?
	local p = Profiles.get(player)
	if not p or not p.relic then
		return nil
	end
	local nextTier = p.relic.tier + 1
	local def = Economy.TIERS[nextTier]
	if not def then
		return nil
	end
	local discount = Progress.effects(player).smithDiscount or 0
	local scrap = math.floor(def.scrap * (1 - discount) + 0.5)
	local items: { [string]: number } = {}
	for id, n in def.items do
		items[id] = n
	end
	if def.faction and p.faction then
		for id, n in def.faction[p.faction] or {} do
			items[id] = n
		end
	end
	local reqs: { Requirement } = {}
	local rank = Factions.rankIndex(p.faction, p.standing)
	local rankName = if p.faction then Factions.INFO[p.faction].ranks[math.min(def.rank, #Factions.INFO[p.faction].ranks)].name else "?"
	table.insert(reqs, { label = "Level " .. def.level, have = p.level, need = def.level, ok = p.level >= def.level })
	table.insert(reqs, { label = "Rank: " .. rankName, have = rank, need = def.rank, ok = rank >= def.rank })
	table.insert(reqs, { label = "Scrap", have = p.scrap, need = scrap, ok = p.scrap >= scrap })
	if def.residue > 0 then
		table.insert(reqs, { label = "Anima Residue", have = p.residue, need = def.residue, ok = p.residue >= def.residue })
	end
	for id, n in items do
		local item = Items.get(id)
		local have = p.items[id] or 0
		table.insert(reqs, { label = if item then item.name else id, have = have, need = n, ok = have >= n })
	end
	local ready = true
	for _, r in reqs do
		ready = ready and r.ok
	end
	return { tier = nextTier, unlocks = def.unlocks, scrap = scrap, residue = def.residue, items = items, reqs = reqs, ready = ready }
end

function Blacksmith.upgrade(player: Player, smithFaction: string?): string?
	local p = Profiles.get(player)
	if not p or not p.relic then
		return "You have no Relic to upgrade."
	end
	if smithFaction and p.faction ~= smithFaction then
		return "This Blacksmith only works for the " .. smithFaction .. "."
	end
	local q = Blacksmith.quote(player)
	if not q then
		return "Your Relic is fully upgraded."
	end
	if not q.ready then
		for _, r in q.reqs do
			if not r.ok then
				return string.format("Not yet: %s (%d / %d).", r.label, r.have, r.need)
			end
		end
	end
	if not Inventory.has(player, q.items) or not Inventory.canAfford(player, { scrap = q.scrap, residue = q.residue }) then
		return "You're missing materials."
	end
	Inventory.takeAll(player, q.items)
	Inventory.spend(player, { scrap = q.scrap, residue = q.residue })
	local relic = p.relic :: { id: string, rarity: string, tier: number }
	relic.tier = q.tier
	Sync.changed(player)
	local j = Relics.get(relic.id)
	local move = if j and j.abilities[q.unlocks] then j.abilities[q.unlocks].name else q.unlocks
	Sync.notify(player, "Upgrade", { tier = q.tier, unlocks = q.unlocks, move = move, relic = if j then j.name else relic.id })
	Bus.emit(player, "Upgrade", { tier = q.tier })
	return nil
end

function Blacksmith.start()
	Sync.contribute(function(player, _p, snap)
		local q = Blacksmith.quote(player)
		snap.smith = if q then { tier = q.tier, unlocks = q.unlocks, reqs = q.reqs, ready = q.ready } else nil
	end)
end

return Blacksmith
