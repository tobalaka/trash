--!strict
--[[
	Smoglings - small Pollution Beasts: smog that gathered in uncleared junk and started walking
	(vault: 03-Content/Mobs/Smogling). They are the pollution made visible: they crawl out more
	often the dirtier the air, gather at Sky Dumps, and leave Toxic Sludge when broken.

	A Smogling is a lumpy heap of trash bags and smoke with two glowing eyes (no teeth, no skull:
	Map-Art-Direction rule 6), built from Parts. It is a plain Humanoid, so CombatService's M1s,
	grabs and knockback work on it untouched; its own lunge lands through MobStrike, the Junk
	Ram's resolver, so blocks, parries and dodges count. Every client wobbles it (Action
	attributes) with ReplicatedStorage.Client.Progression.SmoglingAnimator.

	Loot and credit come from the Ledger: the top damager gets the Scrap and owns the item drops
	(Drops: pickups on the ground), everyone who helped gets quest credit and some EXP. Breaking
	one cleans the air a little.

	Where: near uncleared junk piles in polluted air (the dome and the Wastezone), and, in the
	outer biomes that have no piles (Desert, Jungle, Winter), out of the open ground near a player.
	In the Wastezone a share are Apex Smoglings (Environment.APEX): bigger, darker, with amber
	eyes and cracks, much tougher, with better drops. They count as Smoglings for quests too.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Environment = require(Config:WaitForChild("Environment"))
local Levels = require(Config:WaitForChild("Levels"))
local Factions = require(Config:WaitForChild("Factions"))
local Combat = ServerScriptService:WaitForChild("Combat")
local Fighters = require(Combat:WaitForChild("Fighters"))
local MobStrike = require(ServerScriptService:WaitForChild("Mobs"):WaitForChild("MobStrike"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Pollution = require(script.Parent:WaitForChild("Pollution"))
local Regions = require(script.Parent:WaitForChild("Regions"))
local Salvage = require(script.Parent:WaitForChild("Salvage"))
local Ledger = require(script.Parent:WaitForChild("Ledger"))
local Ground = require(script.Parent:WaitForChild("Ground"))
local Titles = require(script.Parent:WaitForChild("Titles"))
local Drops = require(script.Parent:WaitForChild("Drops"))
local DropConfig = require(Config:WaitForChild("Drops"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local C = Environment.SMOGLING
local A = Environment.APEX
local TAG = "Smogling"
local FOLDER = "Smoglings"
local THINK = 0.25
local HIP = 0.1 -- root bottom above the ground; keeps the body's base just off the floor
local ROOT_SIZE = Vector3.new(2.8, 2.6, 2.8)
local CORPSE_TIME = 3
local SPAWN_NEAR = 140 -- ambient spawns pick piles within this of a player...
local SPAWN_MIN = 35 -- ...but not this close
local PARTICIPANT_EXP = 0.5 -- share of the EXP for helpers
local OPEN_NEAR = { 35, 90 } -- open-ground spawns land this far from the player

-- what a Smogling fights with: the normal ones from Environment.SMOGLING, apex from APEX
type Stats = { health: number, damage: number, posture: number, speed: number, aggro: number, knockback: number, cooldown: number }
local NORMAL: Stats = { health = C.HEALTH, damage = C.DAMAGE, posture = C.POSTURE, speed = C.SPEED, aggro = C.AGGRO, knockback = C.KNOCKBACK, cooldown = C.COOLDOWN }
local APEX: Stats = { health = A.HEALTH, damage = A.DAMAGE, posture = A.POSTURE, speed = A.SPEED, aggro = A.AGGRO, knockback = A.KNOCKBACK, cooldown = A.COOLDOWN }

local Smoglings = {}

local live: { [Model]: boolean } = {}
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function count(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

local function folder(): Folder
	local f = workspace:FindFirstChild(FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = workspace
	end
	return f :: Folder
end

local function build(position: Vector3, apex: boolean): Model
	local stats = if apex then APEX else NORMAL
	local model = Instance.new("Model")
	model.Name = if apex then "ApexSmogling" else "Smogling"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = CFrame.new(position + Vector3.new(0, HIP + ROOT_SIZE.Y / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	root.Parent = model
	local core = Instance.new("Part")
	core.Name = "Body"
	core.Size = Vector3.new(2.6, 2.2, 2.6)
	core.Color = if apex then Color3.fromRGB(28, 28, 30) else Color3.fromRGB(46, 48, 50)
	core.Material = Enum.Material.Fabric
	core.CanCollide = true
	core.Massless = true
	core.CFrame = root.CFrame
	core.Parent = model
	local motor = Instance.new("Motor6D")
	motor.Name = "Wobble"
	motor.Part0 = root
	motor.Part1 = core
	motor.Parent = root
	-- lumps of bags and junk welded to the body, two glowing eyes in front
	local lumps = {
		{ Vector3.new(1.6, 1.4, 1.6), Vector3.new(0.9, 0.6, 0.6), Color3.fromRGB(60, 66, 62) },
		{ Vector3.new(1.4, 1.2, 1.5), Vector3.new(-1.0, 0.4, 0.5), Color3.fromRGB(40, 40, 44) },
		{ Vector3.new(1.2, 1.0, 1.2), Vector3.new(0.2, 1.1, 0.8), Color3.fromRGB(84, 74, 60) },
		{ Vector3.new(1.0, 0.8, 1.1), Vector3.new(-0.6, 0.9, -0.9), Color3.fromRGB(110, 120, 70) },
		{ Vector3.new(0.9, 0.7, 0.9), Vector3.new(1.1, -0.2, -0.8), Color3.fromRGB(150, 150, 146) },
	}
	for i, l in lumps do
		local p = Instance.new("Part")
		p.Name = "Lump" .. i
		p.Size = l[1]
		p.Color = l[3]
		p.Material = if i == 5 then Enum.Material.CorrodedMetal else Enum.Material.Fabric
		p.CanCollide = false
		p.CanQuery = true
		p.Massless = true
		p.CFrame = core.CFrame * CFrame.new(l[2]) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4))
		local w = Instance.new("WeldConstraint")
		w.Part0 = core
		w.Part1 = p
		w.Parent = p
		p.Parent = model
	end
	for _, x in { -0.45, 0.45 } do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.38, 0.38, 0.16)
		eye.Color = if apex then Color3.fromRGB(255, 176, 48) else Color3.fromRGB(200, 255, 90)
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.CanQuery = false
		eye.Massless = true
		eye.CFrame = core.CFrame * CFrame.new(x, 0.35, -1.36)
		local w = Instance.new("WeldConstraint")
		w.Part0 = core
		w.Part1 = eye
		w.Parent = eye
		eye.Parent = model
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Smog"
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 96, 80))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.2, 2)
	smoke.Rate = 6
	smoke.Speed = NumberRange.new(0.5, 1.5)
	smoke.SpreadAngle = Vector2.new(40, 40)
	smoke.Parent = core
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = HIP
	humanoid.MaxHealth = stats.health
	humanoid.Health = stats.health
	humanoid.WalkSpeed = stats.speed
	humanoid.DisplayName = if apex then "Apex Smogling" else "Smogling"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.Parent = model
	model.PrimaryPart = root
	model:SetAttribute("Mob", if apex then "ApexSmogling" else "Smogling")
	if apex then
		model:SetAttribute("Apex", true)
		-- glowing cracks across the heap
		for i = 1, 4 do
			local crack = Instance.new("Part")
			crack.Name = "Crack"
			crack.Size = Vector3.new(0.18, rng:NextNumber(0.9, 1.5), 0.18)
			crack.Color = Color3.fromRGB(255, 150, 40)
			crack.Material = Enum.Material.Neon
			crack.CanCollide = false
			crack.CanQuery = false
			crack.Massless = true
			crack.CFrame = core.CFrame * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0.1, -1.32) * CFrame.Angles(0, 0, rng:NextNumber(-0.6, 0.6))
			local w = Instance.new("WeldConstraint")
			w.Part0 = core
			w.Part1 = crack
			w.Parent = crack
			crack.Parent = model
		end
		smoke.Color = ColorSequence.new(Color3.fromRGB(56, 52, 46))
		smoke.Rate = 10
		model:ScaleTo(A.SCALE)
	end
	return model
end

local function victimsNear(position: Vector3, radius: number): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		local root = Regions.rootOf(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			local region = Regions.of(player)
			local safe = region ~= nil and Factions.SAFE_REGIONS[region] == true
			if not safe and (root.Position - position).Magnitude <= radius then
				table.insert(out, player)
			end
		end
	end
	return out
end

local function brain(model: Model, home: Vector3, stats: Stats)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local f = Fighters.get(model)
	local nextAttack = 0
	local lonely = 0
	local wanderAt = 0
	while model.Parent and humanoid.Health > 0 do
		local t = now()
		local pos = root.Position
		-- despawn when nobody is around for a while
		if #victimsNear(pos, C.AGGRO * 3) == 0 then
			lonely += THINK
			if lonely >= C.DESPAWN then
				model:Destroy()
				break
			end
		else
			lonely = 0
		end
		local stunned = f ~= nil and (f.stunEnd > t or f.ragdollEnd > t or f.heldBy ~= nil)
		if not stunned and model:GetAttribute("Action") == nil then
			-- nearest player in range, unless we've strayed too far from home
			local target: Player? = nil
			local targetDist = stats.aggro
			if (pos - home).Magnitude < C.LEASH then
				for _, player in victimsNear(pos, stats.aggro) do
					local d = ((Regions.rootOf(player) :: BasePart).Position - pos).Magnitude
					if d < targetDist then
						target, targetDist = player, d
					end
				end
			end
			if target then
				local troot = Regions.rootOf(target) :: BasePart
				local range = C.RANGE * (if model:GetAttribute("Apex") then A.SCALE * 0.7 else 1)
				if targetDist <= range and t >= nextAttack then
					nextAttack = t + stats.cooldown
					humanoid:MoveTo(pos)
					root.CFrame = CFrame.lookAt(pos, Vector3.new(troot.Position.X, pos.Y, troot.Position.Z))
					model:SetAttribute("Action", "Lunge")
					model:SetAttribute("ActionStart", t)
					task.delay(C.WINDUP, function()
						if not model.Parent or humanoid.Health <= 0 then
							return
						end
						local me = Fighters.get(model)
						local tf = target.Character and Fighters.get(target.Character)
						if me and tf and me.stunEnd <= now() then
							root.AssemblyLinearVelocity = root.CFrame.LookVector * 22 + Vector3.new(0, 6, 0)
							local offset = tf.root.Position - root.Position
							local ahead = offset.Magnitude > 0 and root.CFrame.LookVector:Dot(offset.Unit) > 0.2
							if offset.Magnitude <= range + 2 and ahead then
								MobStrike.resolve(me, tf, {
									damage = stats.damage,
									posture = stats.posture,
									parryable = true,
									blockable = true,
									stun = C.STUN,
									knockback = stats.knockback,
									up = 4,
									ragdoll = 0,
								}, now(), root.Position)
							end
						end
						task.delay(0.35, function()
							if model.Parent then
								model:SetAttribute("Action", nil)
							end
						end)
					end)
				elseif targetDist > range * 0.7 then
					humanoid:MoveTo(troot.Position)
				end
			elseif (pos - home).Magnitude > 6 then
				humanoid:MoveTo(home)
			elseif t >= wanderAt then
				wanderAt = t + rng:NextNumber(3, 6)
				humanoid:MoveTo(home + Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10)))
			end
		end
		task.wait(THINK)
	end
end

function Smoglings.spawn(position: Vector3, apex: boolean?): Model?
	if count() >= C.MAX then
		return nil
	end
	local model = build(position, apex == true)
	CollectionService:AddTag(model, TAG)
	model.Parent = folder()
	live[model] = true
	model.Destroying:Connect(function()
		live[model] = nil
	end)
	task.spawn(brain, model, position, if apex then APEX else NORMAL)
	return model
end

local function crumble(model: Model)
	live[model] = nil
	model:SetAttribute("Action", "Dead")
	for _, d in model:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("Motor6D") then
			d:Destroy()
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.CanCollide = true
			d.Massless = false
			d.AssemblyLinearVelocity = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(10, 20), rng:NextNumber(-12, 12))
		end
	end
	task.delay(CORPSE_TIME, function()
		model:Destroy()
	end)
end

local function onDeath(victim: Model, killer: Player?, damage: { [Player]: number })
	if not CollectionService:HasTag(victim, TAG) then
		return
	end
	local apex = victim:GetAttribute("Apex") == true
	local root = victim:FindFirstChild("HumanoidRootPart")
	local at = if root and root:IsA("BasePart") then root.Position else victim:GetPivot().Position
	crumble(victim)
	Pollution.apply("Smogling")
	if killer and Profiles.get(killer) then
		local range = if apex then A.SCRAP else C.SCRAP
		local scrap = rng:NextInteger(range[1], range[2])
		local residue = if apex then rng:NextInteger(A.RESIDUE[1], A.RESIDUE[2]) elseif rng:NextNumber() < C.RESIDUE_CHANCE then 1 else 0
		local lines = { string.format("+%d Scrap", scrap) }
		Inventory.earn(killer, { scrap = scrap, residue = residue })
		if residue > 0 then
			table.insert(lines, string.format("+%d Anima Residue", residue))
		end
		-- items fall as pickups the killer owns for a moment
		local loot = Drops.roll(if apex then DropConfig.APEX else DropConfig.SMOGLING)
		if next(loot) then
			Drops.spawn(at, loot, { killer })
		end
		Progress.addExp(killer, if apex then Levels.EXP.APEX else Levels.EXP.SMOGLING)
		Progress.addStanding(killer, if apex then Factions.STANDING.APEX else Factions.STANDING.SMOGLING)
		Sync.notify(killer, "Salvage", { method = if apex then "Apex" else "Smogling", lines = lines })
		if apex then
			Titles.bump(killer, "apex", 1)
		end
	end
	for player in damage do
		if player.Parent then
			if player ~= killer then
				Progress.addExp(player, math.floor((if apex then Levels.EXP.APEX else Levels.EXP.SMOGLING) * PARTICIPANT_EXP))
			end
			Bus.emit(player, "Defeat", { kind = "Smogling", region = Regions.of(player) })
			if apex then
				Bus.emit(player, "Defeat", { kind = "ApexSmogling", region = Regions.of(player) })
			end
		end
	end
end

-- open ground a little way from the player (outer biomes have no junk piles)
local function openGround(around: Vector3): Vector3?
	for _ = 1, 4 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(OPEN_NEAR[1], OPEN_NEAR[2])
		local at = Ground.at(around.X + math.cos(angle) * dist, around.Z + math.sin(angle) * dist)
		if at and math.abs(at.Y - around.Y) < 40 then
			return at
		end
	end
	return nil
end

-- ambient spawns: polluted air breeds Smoglings near uncleared junk around players, out of the
-- open ground in the outer biomes, and Apex Smoglings in the Wastezone
local function ambient()
	if count() >= C.MAX then
		return
	end
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end
	local player = players[rng:NextInteger(1, #players)]
	local root = Regions.rootOf(player)
	local region = Regions.of(player)
	if not root or not region then
		return
	end
	local weight = (C.REGIONS :: any)[region]
	if not weight then
		return
	end
	local air = math.clamp((Pollution.get() - 35) / 65, 0.1, 1)
	local chance = if region == "Wasteland" then weight else weight * air
	if rng:NextNumber() > chance then
		return
	end
	local apex = region == "Wasteland" and rng:NextNumber() < A.CHANCE
	if (C.OPEN_GROUND :: any)[region] then
		local at = openGround(root.Position)
		if at then
			Smoglings.spawn(at, false)
		end
		return
	end
	-- an active junk pile near them, but not on top of them
	for _ = 1, 6 do
		local offset = Vector3.new(rng:NextNumber(-SPAWN_NEAR, SPAWN_NEAR), 0, rng:NextNumber(-SPAWN_NEAR, SPAWN_NEAR))
		local pile = Salvage.nearest(root.Position + offset, 40)
		if pile then
			local at = pile.model:GetPivot().Position
			if (at - root.Position).Magnitude >= SPAWN_MIN then
				Smoglings.spawn(at + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)), apex)
				return
			end
		end
	end
end

function Smoglings.start()
	Ledger.onDeath(onDeath)
	task.spawn(function()
		while true do
			task.wait(C.SPAWN_INTERVAL)
			pcall(ambient)
		end
	end)
end

return Smoglings
