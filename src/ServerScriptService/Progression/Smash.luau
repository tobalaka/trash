--!strict
--[[
	Smash - what breaking the map is worth, and what it costs (vault: Destructible-Walls,
	Pollution, Item-Drops). Destruction becomes upcycling: every part a player breaks gives a
	little Scrap, capped per blast and per minute so walls can't be farmed, and may shake loose
	what it was made of (a metal wall drops a can, glass drops shards: Config.Drops.SMASH_*).
	Thrown bodies are credited to whoever was hitting them (the Ledger). Wrecking also raises the
	server's smog: dust and ruined material, whoever or whatever broke it
	(Environment.DELTA.Smash), capped per minute server-wide. The first break teaches the
	Demolition Field Note; every part counts toward Smash quest steps and the Wrecker title.
	The breaking itself is TRASH-Destruction's DestructionService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local C = require(Config:WaitForChild("Destruction"))
local Environment = require(Config:WaitForChild("Environment"))
local DropConfig = require(Config:WaitForChild("Drops"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Ledger = require(script.Parent:WaitForChild("Ledger"))
local Pollution = require(script.Parent:WaitForChild("Pollution"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Titles = require(script.Parent:WaitForChild("Titles"))
local Drops = require(script.Parent:WaitForChild("Drops"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local CREDIT_WINDOW = 3 -- seconds: a thrown body still counts as the attacker's throw
local MINUTE = 60
local NOTE = "Demolition"

local Smash = {}

local earned: { [Player]: { at: number, scrap: number } } = {}
local dust = { at = -math.huge, amount = 0 } -- smog added by breaking this minute
local rng = Random.new()

local function topDamager(victim: Model): Player?
	local r = Ledger.recordOf(victim)
	if not r or os.clock() - r.last > CREDIT_WINDOW then
		return nil
	end
	local best: Player? = nil
	local most = 0
	for p, d in r.damage do
		if d > most and p.Parent then
			best, most = p, d
		end
	end
	return best
end

-- raises the smog for `parts` broken parts, within the per-minute cap; returns how much
local function pollute(parts: number): number
	local now = os.clock()
	if now - dust.at > MINUTE then
		dust.at = now
		dust.amount = 0
	end
	local add = math.min(parts * Environment.DELTA.Smash, Environment.SMASH_POLLUTION_PER_MINUTE - dust.amount)
	if add <= 0 then
		return 0
	end
	dust.amount += add
	Pollution.add(add)
	return add
end

-- what the broken parts shake loose (at most SMASH_MAX drops a blast)
local function salvage(materials: { string }?): { [string]: number }
	local out: { [string]: number } = {}
	local dropped = 0
	for _, m in materials or {} do
		local item = DropConfig.SMASH_MATERIAL[m]
		if item and dropped < DropConfig.SMASH_MAX and rng:NextNumber() < DropConfig.SMASH_CHANCE then
			out[item] = (out[item] or 0) + 1
			dropped += 1
		end
	end
	return out
end

local function reward(player: Player?, parts: number, smog: number, at: Vector3, materials: { string }?)
	if not player or not player.Parent then
		return
	end
	local now = os.clock()
	local e = earned[player]
	if not e or now - e.at > MINUTE then
		e = { at = now, scrap = 0 }
		earned[player] = e
	end
	local gain = math.min(parts * C.SCRAP_PER_PART, C.SCRAP_PER_BLAST_MAX, C.SCRAP_PER_MINUTE_MAX - e.scrap)
	local lines = {}
	if gain > 0 then
		e.scrap += gain
		Inventory.earn(player, { scrap = gain })
		table.insert(lines, string.format("+%d Scrap", gain))
	end
	if smog > 0 then
		table.insert(lines, string.format("Dust: smog +%.2f", smog))
	end
	if #lines > 0 then
		Sync.notify(player, "Salvage", { method = "Smash", lines = lines })
	end
	local loot = salvage(materials)
	if next(loot) then
		Drops.spawn(at, loot, { player })
	end
	Progress.unlockNote(player, NOTE)
	Titles.bump(player, "smashed", parts)
	Bus.emit(player, "Smash", { parts = parts })
end

function Smash.start()
	local folder = ServerScriptService:WaitForChild("Destruction", 10)
	local module = folder and folder:WaitForChild("DestructionService", 10)
	if not module or not module:IsA("ModuleScript") then
		warn("[Smash] DestructionService not found; breaking the map gives no Scrap")
		return
	end
	local Destruction = require(module) :: any
	Destruction.setCredit(topDamager)
	Destruction.onBreak(function(cause: Player?, parts: number, at: Vector3, materials: { string }?)
		reward(cause, parts, pollute(parts), at, materials)
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		earned[p] = nil
	end)
end

return Smash
