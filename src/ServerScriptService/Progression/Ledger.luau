--!strict
--[[
	Ledger - who hurt whom. CombatService applies damage without saying who dealt it (and stays
	untouched), so the Ledger watches every fighting Humanoid and credits each loss of health:
	  1. to the player a Relic move named just before it landed (Ledger.expect), else
	  2. to the nearest player who is mid-swing (their Fighter's actionEnd) and facing the victim
	     within CREDIT_RANGE of its body (big models count from their edge, not their centre).
	Damage is kept per victim for the fight. On death the top damager is the killer and everyone
	with at least `minShare` of the damage took part.

	Uses: Anima gain (RelicService), Smogling and Junk Ram loot, quest "Defeat" steps, bounties.
	Watched: player characters, and models tagged PollutionBeast, Smogling or TrainingDummy.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RelicConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Relic"))
local Fighters = require(ServerScriptService:WaitForChild("Combat"):WaitForChild("Fighters"))

local TAGS = { "PollutionBeast", "Smogling", "TrainingDummy" }
local FIGHT_MEMORY = 30 -- seconds of damage history kept per victim
local EXPECT_WINDOW = 0.3
local FACING = 0.2

export type Record = { damage: { [Player]: number }, total: number, last: number }

local Ledger = {}

local records: { [Model]: Record } = {}
local expected: { [Model]: { player: Player, at: number } } = {}
local radii: { [Model]: number } = {}
local damageFns: { (Player?, Model, number) -> () } = {}
local deathFns: { (Model, Player?, { [Player]: number }) -> () } = {}
local watched: { [Humanoid]: boolean } = {}

-- A Relic move is about to damage `victim`; credit the next health loss to `player`.
function Ledger.expect(victim: Model, player: Player)
	expected[victim] = { player = player, at = os.clock() }
end

-- called with (attacker or nil, victim model, amount) for every credited loss of health
function Ledger.onDamage(fn: (Player?, Model, number) -> ())
	table.insert(damageFns, fn)
end

-- called with (victim, killer or nil, damage by player) when a watched model dies
function Ledger.onDeath(fn: (Model, Player?, { [Player]: number }) -> ())
	table.insert(deathFns, fn)
end

function Ledger.recordOf(victim: Model): Record?
	return records[victim]
end

local function radiusOf(model: Model): number
	local r = radii[model]
	if r then
		return r
	end
	local size = model:GetExtentsSize()
	r = math.max(size.X, size.Z) / 2
	radii[model] = r
	return r
end

local function swingCredit(victim: Model): Player?
	local root = victim:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local now = workspace:GetServerTimeNow()
	local reach = RelicConfig.CREDIT_RANGE + (if Players:GetPlayerFromCharacter(victim) then 0 else radiusOf(victim))
	local best, bestDist = nil, math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character ~= victim then
			local f = Fighters.get(character)
			if f and f.actionEnd + RelicConfig.CREDIT_WINDOW >= now then
				local offset = root.Position - f.root.Position
				local flat = Vector3.new(offset.X, 0, offset.Z)
				local dist = flat.Magnitude
				local look = f.root.CFrame.LookVector
				if dist <= reach and (dist < 2 or flat.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) >= FACING) and dist < bestDist then
					best, bestDist = player, dist
				end
			end
		end
	end
	return best
end

local function credit(victim: Model, amount: number)
	local attacker: Player? = nil
	local e = expected[victim]
	if e and os.clock() - e.at <= EXPECT_WINDOW then
		attacker = e.player
		expected[victim] = nil
	else
		attacker = swingCredit(victim)
	end
	local t = os.clock()
	local r = records[victim]
	if not r or t - r.last > FIGHT_MEMORY then
		r = { damage = {}, total = 0, last = t }
		records[victim] = r
	end
	r.last = t
	r.total += amount
	if attacker then
		r.damage[attacker] = (r.damage[attacker] or 0) + amount
	end
	for _, fn in damageFns do
		task.spawn(fn, attacker, victim, amount)
	end
end

local function onDied(victim: Model)
	local r = records[victim]
	records[victim] = nil
	expected[victim] = nil
	radii[victim] = nil
	local killer, most = nil, 0
	local damage = if r then r.damage else {}
	for player, d in damage do
		if d > most then
			killer, most = player, d
		end
	end
	for _, fn in deathFns do
		task.spawn(fn, victim, killer, damage)
	end
end

function Ledger.watch(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or watched[humanoid] then
		return
	end
	watched[humanoid] = true
	local last = humanoid.Health
	local diedFired = false
	humanoid.HealthChanged:Connect(function(health)
		local lost = last - health
		last = health
		if lost > 0 then
			credit(model, lost)
		end
	end)
	humanoid.Died:Connect(function()
		if not diedFired then
			diedFired = true
			onDied(model)
		end
	end)
	humanoid.Destroying:Connect(function()
		watched[humanoid] = nil
	end)
end

function Ledger.start()
	for _, tag in TAGS do
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(m)
			if m:IsA("Model") then
				task.defer(Ledger.watch, m)
			end
		end)
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") then
				Ledger.watch(m)
			end
		end
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			Ledger.watch(character)
		end)
		if player.Character then
			Ledger.watch(player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		for _, r in records do
			r.damage[player] = nil
		end
	end)
end

return Ledger
