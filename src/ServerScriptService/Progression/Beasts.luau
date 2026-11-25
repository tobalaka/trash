--!strict
--[[
	Beasts - rewards for the big Pollution Beasts (the Junk Ram, ServerScriptService/Mobs). The
	Junk Ram is a team fight, so everyone who took part is paid: anyone the Ledger credits with at
	least `minDamageShare` of its damage, plus anyone within `radius` when it falls. Each gets
	Scrap, Anima Residue, EXP and a Ram Heart (the final Blacksmith tier needs one), and the air
	clears a little. Then it bursts into a shower of junk pickups (Drops) that its fighters own for
	a moment before anyone can grab them, and each fighter's Ram count moves toward the Ram
	Breaker title. Mobs code is untouched: this listens to the Ledger.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Environment = require(Config:WaitForChild("Environment"))
local Levels = require(Config:WaitForChild("Levels"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Pollution = require(script.Parent:WaitForChild("Pollution"))
local Titles = require(script.Parent:WaitForChild("Titles"))
local Drops = require(script.Parent:WaitForChild("Drops"))
local DropConfig = require(Config:WaitForChild("Drops"))
local Regions = require(script.Parent:WaitForChild("Regions"))
local Ledger = require(script.Parent:WaitForChild("Ledger"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local BEAST_TAG = "PollutionBeast"

local Beasts = {}

local rng = Random.new()

local function onDeath(victim: Model, _killer: Player?, damage: { [Player]: number })
	if not CollectionService:HasTag(victim, BEAST_TAG) or victim:GetAttribute("Mob") ~= "JunkRam" then
		return
	end
	local R = Environment.JUNKRAM_REWARD
	local total = 0
	for _, d in damage do
		total += d
	end
	local root = victim:FindFirstChild("HumanoidRootPart")
	local at = if root and root:IsA("BasePart") then root.Position else victim:GetPivot().Position
	local paid: { [Player]: boolean } = {}
	for player, d in damage do
		if total > 0 and d / total >= R.minDamageShare then
			paid[player] = true
		end
	end
	for _, player in Players:GetPlayers() do
		local r = Regions.rootOf(player)
		if r and (r.Position - at).Magnitude <= R.radius then
			paid[player] = true
		end
	end
	Pollution.apply("JunkRam")
	-- the shower of junk: everyone who fought it owns it for a moment
	local owners: { Player } = {}
	for player in paid do
		table.insert(owners, player)
	end
	local shower: { [string]: number } = {}
	for _ = 1, rng:NextInteger(DropConfig.JUNKRAM_SHOWER[1], DropConfig.JUNKRAM_SHOWER[2]) do
		local id = DropConfig.JUNKRAM_POOL[rng:NextInteger(1, #DropConfig.JUNKRAM_POOL)]
		shower[id] = (shower[id] or 0) + 1
	end
	Drops.spawn(at, shower, owners)
	for player in paid do
		if player.Parent and Profiles.get(player) then
			Progress.grant(player, {
				scrap = rng:NextInteger(R.scrap[1], R.scrap[2]),
				residue = rng:NextInteger(R.residue[1], R.residue[2]),
				exp = Levels.EXP.JUNKRAM,
				items = R.items,
			}, "The Junk Ram falls!")
			Bus.emit(player, "Defeat", { kind = "JunkRam" })
			Titles.bump(player, "junkRams", 1)
		end
	end
end

function Beasts.start()
	Ledger.onDeath(onDeath)
end

return Beasts
