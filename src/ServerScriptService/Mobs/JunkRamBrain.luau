--!strict
--[[
	JunkRamBrain - the Junk Ram's AI (03-Content/Mobs/Junk-Ram). The server decides everything:
	targets, movement and every hit (through MobStrike). Clients animate and draw effects from the
	attributes it keeps on the model:
	  Mob           config key ("JunkRam")
	  MobState      Idle | Roam | Chase | Circle | Attack | Dazed | Staggered | Return | Dead
	  Action        move in progress ("" when none); ActionSerial bumps on every new move
	  ActionStart   server time the move began; ActionWindup this use's windup (delays, enrage)
	  ActionPhase   a move's later stages: Feint | Dash | Crash | Fire | Leap | Land
	  ActionAim     Vector3 the move aims at (charge end, quake landing)
	  ActionPoints  "x,y,z;x,y,z" barrage landing points
	  Enraged, Stagger (0..1), TargetName

	How it fights:
	  - Threat: damage dealt to it and time spent close by. It keeps its target until another
	    player has clearly more threat, and drops targets that leave or die.
	  - Leash: dragged too far from home it resets, walking back untouchable and regenerating.
	  - Moves by range: horn sweep and headbutt close, a rear kick for anyone behind it, a stomp
	    when surrounded, a charge at mid range, crystal barrages at range, and an enraged leap
	    with shockwave rings.
	  - Reads the player: parry-happy targets get delayed swings and unblockables, turtles get
	    stomps and charges (posture damage), kiters get barrages, stunned targets get punished.
	    Charges sometimes feint to bait dodges. Melee moves track the target until just before
	    they land, so a late sidestep still works.
	  - Its posture: damage and parries fill a stagger meter; full, it collapses and takes extra
	    damage. Parries interrupt the move. A charge into a wall dazes it, unless the wall is
	    breakable (TRASH-Destruction): then it smashes through, and a target hiding behind
	    breakable walls still gets charged. Stomps and quake landings break the map around them.
]]

local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MobsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Mobs"))
local MobStrike = require(script.Parent:WaitForChild("MobStrike"))

type Fighter = MobStrike.Fighter
type Strike = MobStrike.Strike
type Outcome = MobStrike.Outcome

local CFG = MobsConfig.JunkRam
local A = CFG.ATTACKS
local MOVES = { "Sweep", "Headbutt", "RearKick", "Stomp", "Charge", "Barrage", "Quake" }
local GROUND_PROBE = 40 -- studs looked down for the floor under a point
local FALL_LIMIT = 120 -- studs below home before the beast is put back
local ROAM_GIVE_UP = 15 -- seconds before an unreachable roam goal is dropped

local JunkRamBrain = {}

-- the breakable map (TRASH-Destruction); optional, so the beast still works without it
local destruction: any = nil
local DC: any = nil
task.spawn(function()
	local folder = game:GetService("ServerScriptService"):WaitForChild("Destruction", 10)
	local module = folder and folder:WaitForChild("DestructionService", 10)
	local config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Destruction", 10)
	if module and module:IsA("ModuleScript") and config and config:IsA("ModuleScript") then
		DC = require(config)
		destruction = require(module)
	end
end)

local function smash(center: Vector3, radius: number, dir: Vector3?): number
	return if destruction then destruction.blast(center, radius, nil, 2, dir) else 0
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatUnit(v: Vector3): Vector3
	local f = flat(v)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

local function yawOf(direction: Vector3): number
	return math.atan2(-direction.X, -direction.Z)
end

local function angleDelta(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

local function strikeOf(a: any, finisher: boolean?): Strike
	return {
		damage = a.damage,
		posture = a.posture,
		parryable = a.parryable,
		blockable = a.blockable,
		stun = a.stun,
		knockback = if finisher then a.finisherKnockback else a.knockback,
		up = if finisher then a.finisherUp else a.up,
		ragdoll = if finisher then a.finisherRagdoll else a.ragdoll,
	}
end

--[[
	Runs the brain for `model` (a clone of the JunkRam template, already in Workspace) with its
	home at `home`. `onDead` is called once when it dies. Returns a function that stops it.
]]
function JunkRamBrain.start(model: Model, home: Vector3, onDead: () -> ()): () -> ()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	local fighter = MobStrike.enlist(model) :: Fighter
	local rootHeight = humanoid.HipHeight + root.Size.Y / 2

	local alive = true
	local running = true
	local connections: { RBXScriptConnection } = {}

	local state = ""
	local actionToken = 0
	local actionSerial = 0
	local busy = false
	local engaged = false
	local enraged = false
	local enrageRoared = false
	local returning = false
	local holdUntil = 0 -- dazed or staggered until

	local target: Fighter? = nil
	local threat: { [Model]: number } = {}
	local cooldowns: { [string]: number } = {}
	local parries: { [Model]: { number } } = {}
	local blockSince: { [Model]: number } = {}
	local behindSince: { [Model]: number } = {}
	local kiteSince: number? = nil

	local stagger = 0
	local staggerHitAt = 0
	local lastHealth = humanoid.Health

	local roamGoal: Vector3? = nil
	local roamSince = 0
	local roamWaitUntil = 0
	local circleUntil = 0
	local circleDirection = 1

	local path: { Vector3 }? = nil
	local pathIndex = 1
	local pathGoal = Vector3.zero
	local pathAt = 0
	local lastPosition = root.Position
	local lastProgressAt = now()
	local forcePath = false

	-- facing: the beast turns itself (AlignOrientation) while attacking or circling
	local turnAttachment = Instance.new("Attachment")
	turnAttachment.Name = "MobTurn"
	turnAttachment.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "MobTurn"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = turnAttachment
	align.MaxTorque = math.huge
	align.Responsiveness = 40
	align.Enabled = false
	align.Parent = root
	local yaw = yawOf(root.CFrame.LookVector)
	local desiredYaw = yaw

	model:SetAttribute("Mob", "JunkRam")
	model:SetAttribute("Action", "")
	model:SetAttribute("ActionSerial", 0)
	model:SetAttribute("Enraged", false)
	model:SetAttribute("Stagger", 0)

	local function setState(s: string)
		if state ~= s then
			state = s
			model:SetAttribute("MobState", s)
		end
	end
	setState("Idle")

	local function setFacing(on: boolean)
		if on and not align.Enabled then
			yaw = yawOf(root.CFrame.LookVector)
			desiredYaw = yaw
			align.CFrame = CFrame.Angles(0, yaw, 0)
		end
		align.Enabled = on
		humanoid.AutoRotate = not on
	end

	local function faceToward(point: Vector3)
		local d = flatUnit(point - root.Position)
		if d ~= Vector3.zero then
			desiredYaw = yawOf(d)
		end
	end

	local function speedOf(base: number): number
		return base * (if enraged then CFG.ENRAGE_SPEED else 1)
	end

	local function windupOf(base: number): number
		return base * (if enraged then CFG.ENRAGE_WINDUP else 1)
	end

	-- ── raycasts ───────────────────────────────────────────────────────────────

	local function worldParams(): RaycastParams
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { model }
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		params.FilterDescendantsInstances = ignore
		params.RespectCanCollide = true
		return params
	end

	local function clearLine(from: Vector3, to: Vector3): boolean
		local up = Vector3.new(0, 3, 0)
		return workspace:Raycast(from + up, (to + up) - (from + up), worldParams()) == nil
	end

	-- like clearLine, but breakable walls (TRASH-Destruction) don't count: a charge goes through
	local function chargeLine(from: Vector3, to: Vector3): boolean
		if not destruction then
			return false
		end
		local up = Vector3.new(0, 3, 0)
		local params = worldParams()
		local ignore = params.FilterDescendantsInstances
		for _ = 1, 4 do
			local hit = workspace:Raycast(from + up, (to + up) - (from + up), params)
			if not hit then
				return true
			end
			if not destruction.isBreakable(hit.Instance) then
				return false
			end
			table.insert(ignore, hit.Instance)
			params.FilterDescendantsInstances = ignore
		end
		return false
	end

	local function ground(point: Vector3): Vector3
		local hit = workspace:Raycast(point + Vector3.new(0, GROUND_PROBE / 2, 0), Vector3.new(0, -GROUND_PROBE * 2, 0), worldParams())
		return if hit then hit.Position else point
	end

	local function feet(): Vector3
		return root.Position - Vector3.new(0, rootHeight, 0)
	end

	-- A hitbox of `size` standing on the ground, its centre `forward` studs along the beast's
	-- facing (negative is in front).
	local function groundBox(size: Vector3, forward: number): CFrame
		return root.CFrame * CFrame.new(0, size.Y / 2 - rootHeight, forward)
	end

	-- ── movement ───────────────────────────────────────────────────────────────

	local function stopMoving()
		humanoid:MoveTo(root.Position)
	end

	local function waypointToward(goal: Vector3): Vector3
		local t = now()
		if not forcePath and clearLine(root.Position, goal) then
			path = nil
			return goal
		end
		local current = path
		if not current or (goal - pathGoal).Magnitude > 10 or t - pathAt > CFG.PATH_REFRESH then
			pathAt = t
			pathGoal = goal
			local p = PathfindingService:CreatePath({
				AgentRadius = CFG.PATH_AGENT_RADIUS,
				AgentHeight = CFG.PATH_AGENT_HEIGHT,
				AgentCanJump = false,
			})
			local ok = pcall(function()
				p:ComputeAsync(feet(), goal)
			end)
			if ok and p.Status == Enum.PathStatus.Success then
				local points: { Vector3 } = {}
				for _, w in p:GetWaypoints() do
					table.insert(points, w.Position)
				end
				path = points
				pathIndex = math.min(2, #points)
			else
				path = nil
				return goal
			end
		end
		local points = path :: { Vector3 }
		while pathIndex < #points and flatDistance(points[pathIndex], root.Position) < 4 do
			pathIndex += 1
		end
		return points[pathIndex]
	end

	local function walkTo(goal: Vector3, speed: number)
		humanoid.WalkSpeed = speedOf(speed)
		humanoid:MoveTo(waypointToward(goal))
	end

	local function trackProgress(t: number, moving: boolean)
		if not moving or (root.Position - lastPosition).Magnitude >= CFG.STUCK_DISTANCE then
			lastPosition = root.Position
			lastProgressAt = t
			forcePath = false
		elseif t - lastProgressAt > CFG.STUCK_TIME then
			forcePath = true
			path = nil
			lastProgressAt = t
		end
	end

	-- ── actions ────────────────────────────────────────────────────────────────

	local function beginAction(name: string, windup: number)
		actionSerial += 1
		model:SetAttribute("ActionPhase", nil)
		model:SetAttribute("ActionAim", nil)
		model:SetAttribute("ActionPoints", nil)
		model:SetAttribute("ActionWindup", windup)
		model:SetAttribute("ActionStart", now())
		model:SetAttribute("Action", name)
		model:SetAttribute("ActionSerial", actionSerial)
	end

	local function endAction()
		model:SetAttribute("Action", "")
	end

	local function current(token: number): boolean
		return token == actionToken and alive
	end

	-- Waits until server time `at`, turning toward the target until `trackUntil`. False when the
	-- move was interrupted.
	local function waitUntil(at: number, token: number, trackUntil: number?): boolean
		while now() < at do
			if not current(token) then
				return false
			end
			local t = target
			if t and trackUntil and now() < trackUntil then
				faceToward(t.root.Position)
			end
			RunService.Heartbeat:Wait()
		end
		return current(token)
	end

	-- Stops whatever the beast is doing.
	local function interrupt()
		actionToken += 1
		busy = false
		endAction()
		if humanoid.PlatformStand then
			humanoid.PlatformStand = false
		end
		stopMoving()
	end

	local function hold(duration: number, mobState: string)
		interrupt()
		holdUntil = math.max(holdUntil, now() + duration)
		setState(mobState)
		setFacing(false)
		task.delay(duration, function()
			if alive and now() >= holdUntil - 0.01 and state == mobState then
				if mobState == "Staggered" then
					stagger = 0
					model:SetAttribute("Stagger", 0)
				end
				setState("Chase")
			end
		end)
	end

	local function addStagger(amount: number)
		if state == "Staggered" or not alive then
			return
		end
		stagger += amount
		staggerHitAt = now()
		if stagger >= CFG.STAGGER_MAX then
			stagger = CFG.STAGGER_MAX
			model:SetAttribute("Stagger", 1)
			MobStrike.fire("Break", nil, model)
			hold(CFG.STAGGER_TIME, "Staggered")
		else
			model:SetAttribute("Stagger", stagger / CFG.STAGGER_MAX)
		end
	end

	local function remember(f: Fighter, outcome: Outcome)
		if outcome == "Parry" then
			local list = parries[f.model] or {}
			table.insert(list, now())
			parries[f.model] = list
		end
	end

	-- Resolves a strike on every victim; true when someone parried it (the move is then over).
	local function strikeAll(victims: { Fighter }, s: Strike, hitAt: number, from: Vector3?): boolean
		local parried = false
		for _, f in victims do
			local outcome = MobStrike.resolve(fighter, f, s, hitAt, from)
			remember(f, outcome)
			if outcome == "Parry" then
				parried = true
			end
		end
		if parried and alive then
			addStagger(CFG.STAGGER_PER_PARRY)
			if state ~= "Staggered" then
				hold(CFG.PARRY_FLINCH, "Dazed")
			end
		end
		return parried
	end

	local function grounded(victims: { Fighter }): { Fighter }
		local list: { Fighter } = {}
		for _, f in victims do
			if not MobStrike.airborne(f, CFG.AIRBORNE_HEIGHT) then
				table.insert(list, f)
			end
		end
		return list
	end

	local function predicted(f: Fighter, lead: number): Vector3
		return f.root.Position + flat(f.root.AssemblyLinearVelocity) * lead
	end

	local function recentParries(m: Model): number
		local list = parries[m]
		if not list then
			return 0
		end
		local t = now()
		local kept: { number } = {}
		for _, at in list do
			if t - at <= CFG.MEMORY then
				table.insert(kept, at)
			end
		end
		parries[m] = kept
		return #kept
	end

	local function wary(f: Fighter?): boolean
		return f ~= nil and recentParries(f.model) >= CFG.PARRY_WARY
	end

	local ACTIONS: { [string]: (token: number) -> () } = {}

	ACTIONS.Sweep = function(token)
		local a = A.Sweep
		local windup = windupOf(a.windup)
		if wary(target) and math.random() < CFG.DELAY_CHANCE then
			windup += CFG.DELAY_EXTRA
		end
		beginAction("Sweep", windup)
		local hitAt = now() + windup
		if not waitUntil(hitAt, token, hitAt - CFG.TRACK_LOCK) then
			return
		end
		if strikeAll(MobStrike.inBox(model, groundBox(a.box, -a.box.Z / 2), a.box), strikeOf(a), hitAt) then
			return
		end
		waitUntil(now() + a.recovery, token)
	end

	ACTIONS.Headbutt = function(token)
		local a = A.Headbutt
		local windup = windupOf(a.windup)
		beginAction("Headbutt", windup)
		local first = now() + windup
		if not waitUntil(first, token, first - CFG.TRACK_LOCK) then
			return
		end
		if strikeAll(MobStrike.inBox(model, groundBox(a.box, -a.box.Z / 2), a.box), strikeOf(a), first) then
			return
		end
		local second = first + a.gap
		if not waitUntil(second, token, second - CFG.TRACK_LOCK) then
			return
		end
		if strikeAll(MobStrike.inBox(model, groundBox(a.box, -a.box.Z / 2), a.box), strikeOf(a, true), second) then
			return
		end
		waitUntil(now() + a.recovery, token)
	end

	ACTIONS.RearKick = function(token)
		local a = A.RearKick
		local windup = windupOf(a.windup)
		beginAction("RearKick", windup)
		local hitAt = now() + windup
		if not waitUntil(hitAt, token) then
			return
		end
		if strikeAll(MobStrike.inBox(model, groundBox(a.box, a.box.Z / 2), a.box), strikeOf(a), hitAt) then
			return
		end
		waitUntil(now() + a.recovery, token)
	end

	ACTIONS.Stomp = function(token)
		local a = A.Stomp
		local windup = windupOf(a.windup)
		beginAction("Stomp", windup)
		local hitAt = now() + windup
		if not waitUntil(hitAt, token, hitAt - windup * 0.4) then
			return
		end
		local center = feet() + root.CFrame.LookVector * a.offset
		strikeAll(grounded(MobStrike.inRadius(model, center, a.radius, rootHeight + 2)), strikeOf(a), hitAt, center)
		if DC then
			smash(center, a.radius * DC.BEAST_SCALE, nil)
		end
		waitUntil(now() + a.recovery, token)
	end

	local function crash(duration: number)
		model:SetAttribute("ActionPhase", "Crash")
		addStagger(A.Charge.crashStagger)
		if state ~= "Staggered" then
			hold(duration, "Dazed")
		end
	end

	ACTIONS.Charge = function(token)
		local a = A.Charge
		local windup = windupOf(a.windup)
		beginAction("Charge", windup)
		local start = now()
		local feintChance = CFG.FEINT_CHANCE * (if wary(target) then 2 else 1)
		if math.random() < feintChance then
			if not waitUntil(start + windup * CFG.FEINT_AT, token, start + windup) then
				return
			end
			model:SetAttribute("ActionPhase", "Feint")
			cooldowns.Charge = now() + a.cooldown / 2
			waitUntil(now() + a.recovery, token)
			return
		end
		if not waitUntil(start + windup, token, start + windup) then
			return
		end
		local t = target
		local aim = if t then predicted(t, a.lead) else root.Position + root.CFrame.LookVector * 30
		local direction = flatUnit(aim - root.Position)
		if direction == Vector3.zero then
			direction = flatUnit(root.CFrame.LookVector)
		end
		local distance = math.min(flatDistance(aim, root.Position) + a.overshoot, a.speed * a.maxTime)
		local finish = root.Position + direction * distance
		yaw = yawOf(direction)
		desiredYaw = yaw
		align.CFrame = CFrame.Angles(0, yaw, 0)
		model:SetAttribute("ActionAim", finish)
		model:SetAttribute("ActionPhase", "Dash")
		humanoid.WalkSpeed = a.speed
		humanoid:MoveTo(finish)
		local s = strikeOf(a)
		local struck: { [Model]: boolean } = {}
		local params = worldParams()
		local dashEnd = now() + distance / a.speed + 0.2
		while now() < dashEnd do
			if not current(token) then
				return
			end
			for _, f in MobStrike.inBox(model, groundBox(a.box, -a.box.Z / 2), a.box) do
				if not struck[f.model] then
					struck[f.model] = true
					local outcome = MobStrike.resolve(fighter, f, s, now())
					remember(f, outcome)
					if outcome == "Parry" then
						addStagger(CFG.STAGGER_PER_PARRY)
						crash(a.crashStun)
						return
					end
				end
			end
			-- probe at knee height so low junk does not count as a wall
			local probe = workspace:Raycast(feet() + Vector3.new(0, rootHeight / 2, 0), direction * a.wallProbe, params)
			if probe and math.abs(probe.Normal.Y) < 0.5 then
				-- a breakable wall gives way; anything else stops the charge
				if not (DC and destruction.isBreakable(probe.Instance) and smash(probe.Position, DC.BEAST_CHARGE_RADIUS, direction) > 0) then
					crash(a.crashStun)
					return
				end
			end
			if flatDistance(root.Position, finish) < 3 then
				break
			end
			RunService.Heartbeat:Wait()
		end
		stopMoving()
		humanoid.WalkSpeed = speedOf(CFG.CHASE_SPEED)
		waitUntil(now() + a.recovery, token)
	end

	ACTIONS.Barrage = function(token)
		local a = A.Barrage
		local windup = windupOf(a.windup)
		beginAction("Barrage", windup)
		local start = now()
		if not waitUntil(start + windup, token, start + windup) then
			return
		end
		local t = target
		if not t then
			return
		end
		local first = ground(predicted(t, a.lead))
		local points = { first }
		for _ = 2, a.shards do
			local angle = math.random() * 2 * math.pi
			local r = a.spread * math.sqrt(math.random())
			table.insert(points, ground(first + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)))
		end
		local encoded = {}
		for _, p in points do
			table.insert(encoded, string.format("%.2f,%.2f,%.2f", p.X, p.Y, p.Z))
		end
		model:SetAttribute("ActionPoints", table.concat(encoded, ";"))
		model:SetAttribute("ActionPhase", "Fire")
		local launch = root.Position
		local s = strikeOf(a)
		for i, p in points do
			task.delay((i - 1) * a.interval + a.flight, function()
				if alive then
					strikeAll(MobStrike.inRadius(model, p, a.radius, rootHeight), s, now(), launch)
				end
			end)
		end
		waitUntil(now() + (a.shards - 1) * a.interval + a.recovery, token)
	end

	ACTIONS.Quake = function(token)
		local a = A.Quake
		local windup = windupOf(a.windup)
		beginAction("Quake", windup)
		local start = now()
		if not waitUntil(start + windup, token, start + windup) then
			return
		end
		local t = target
		local aim = if t then predicted(t, a.lead) else root.Position
		local offset = flat(aim - root.Position)
		if offset.Magnitude > a.maxLeap then
			aim = root.Position + offset.Unit * a.maxLeap
		end
		if flatDistance(aim, home) > CFG.LEASH_RADIUS then
			aim = home + flatUnit(aim - home) * CFG.LEASH_RADIUS
		end
		local landing = ground(aim)
		model:SetAttribute("ActionAim", landing)
		model:SetAttribute("ActionPhase", "Leap")
		faceToward(landing)
		local p0 = root.Position
		local delta = (landing + Vector3.new(0, rootHeight, 0)) - p0
		local g = workspace.Gravity
		local airTime: number = a.air
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = Vector3.new(delta.X / airTime, (delta.Y + 0.5 * g * airTime * airTime) / airTime, delta.Z / airTime)
		local lands = now() + airTime
		if not waitUntil(lands, token) then
			return
		end
		humanoid.PlatformStand = false
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		model:SetAttribute("ActionPhase", "Land")
		local landedAt = now()
		if DC then
			smash(landing, a.radius * DC.BEAST_SCALE, nil)
		end
		strikeAll(grounded(MobStrike.inRadius(model, landing, a.radius, rootHeight + 2)), strikeOf(a), landedAt, landing)
		local ring: Strike = {
			damage = a.ringDamage,
			posture = 0,
			parryable = false,
			blockable = false,
			stun = 0,
			knockback = a.ringKnockback,
			up = a.ringUp,
			ragdoll = 0,
		}
		for k = 0, a.rings - 1 do
			task.spawn(function()
				local begins = landedAt + k * a.ringInterval
				local struck: { [Model]: boolean } = {}
				while alive do
					local radius = (now() - begins) * a.ringSpeed
					if radius > a.ringReach then
						break
					end
					if radius > 0 then
						for _, f in grounded(MobStrike.inRadius(model, landing, radius + a.ringWidth / 2, rootHeight + 2)) do
							local d = flatDistance(f.root.Position, landing)
							if not struck[f.model] and d >= radius - a.ringWidth / 2 then
								struck[f.model] = true
								MobStrike.resolve(fighter, f, ring, now(), landing)
							end
						end
					end
					RunService.Heartbeat:Wait()
				end
			end)
		end
		waitUntil(landedAt + a.recovery, token)
	end

	ACTIONS.Roar = function(token)
		local a = A.Roar
		beginAction("Roar", a.windup)
		local hitAt = now() + a.windup
		if not waitUntil(hitAt, token) then
			return
		end
		for _, f in MobStrike.inRadius(model, root.Position, a.radius, rootHeight + 4) do
			MobStrike.shove(f, root.Position, a.knockback, a.up)
		end
		waitUntil(hitAt + a.active + a.recovery, token)
	end

	local function perform(name: string)
		local a = (A :: any)[name]
		cooldowns[name] = now() + a.cooldown
		busy = true
		actionToken += 1
		local token = actionToken
		setState("Attack")
		stopMoving()
		setFacing(true) -- holds the current heading; moves that aim turn through waitUntil
		task.spawn(function()
			local ok, err = pcall(ACTIONS[name], token)
			if not ok then
				warn("[JunkRam] " .. name .. " failed: " .. tostring(err))
			end
			if token == actionToken then
				busy = false
				endAction()
				humanoid.PlatformStand = false
				if alive and state == "Attack" then
					setState("Chase")
				end
			end
		end)
	end

	-- ── targeting ──────────────────────────────────────────────────────────────

	local function startReturn()
		returning = true
		engaged = false
		target = nil
		table.clear(threat)
		model:SetAttribute("TargetName", nil)
		fighter.iframeStart = now()
		fighter.iframeEnd = math.huge -- hits read as dodged while it resets
		setFacing(false)
		setState("Return")
	end

	local function finishReturn()
		returning = false
		fighter.iframeStart = 0
		fighter.iframeEnd = 0
		roamGoal = nil
		roamWaitUntil = now() + CFG.ROAM_PAUSE_MIN
		stopMoving()
		setState("Idle")
	end

	local function behind(f: Fighter): boolean
		local to = flatUnit(f.root.Position - root.Position)
		return to ~= Vector3.zero and flatUnit(root.CFrame.LookVector):Dot(to) < math.cos(math.rad(CFG.BEHIND_ANGLE))
	end

	local function refreshTargets(victims: { Fighter }, dt: number)
		local t = now()
		local present: { [Model]: Fighter } = {}
		for _, f in victims do
			present[f.model] = f
		end
		for m, value in threat do
			local f = present[m]
			if not f or flatDistance(f.root.Position, root.Position) > CFG.DEAGGRO_RADIUS then
				threat[m] = nil
			else
				threat[m] = value * (1 - CFG.THREAT_DECAY * dt)
			end
		end
		for _, f in victims do
			local d = flatDistance(f.root.Position, root.Position)
			if d <= CFG.CLOSE_RANGE + 4 then
				threat[f.model] = (threat[f.model] or 0) + CFG.THREAT_PROXIMITY * dt
			end
			if not threat[f.model] and d <= CFG.AGGRO_RADIUS and clearLine(root.Position, f.root.Position) then
				threat[f.model] = 1
			end
			-- habits
			if f.blocking then
				blockSince[f.model] = blockSince[f.model] or t
			else
				blockSince[f.model] = nil
			end
			if d <= A.RearKick.maxRange and behind(f) then
				behindSince[f.model] = behindSince[f.model] or t
			else
				behindSince[f.model] = nil
			end
		end
		local current = target
		if current and not threat[current.model] then
			current = nil
		end
		local best: Fighter? = nil
		local bestThreat = 0
		for m, value in threat do
			if value > bestThreat then
				best, bestThreat = present[m], value
			end
		end
		if best and (not current or bestThreat > (threat[current.model] or 0) * CFG.TARGET_SWITCH_MARGIN) then
			current = best
		end
		target = current
		model:SetAttribute("TargetName", if current then current.model.Name else nil)
		if current and flatDistance(current.root.Position, root.Position) > CFG.KITE_RANGE then
			kiteSince = kiteSince or t
		else
			kiteSince = nil
		end
	end

	-- Damage taken: credit attackers, build stagger, apply the stagger bonus, enrage.
	table.insert(connections, humanoid.HealthChanged:Connect(function(health: number)
		local delta = lastHealth - health
		lastHealth = health
		if delta <= 0 or not alive or health <= 0 then
			return
		end
		if state == "Staggered" and CFG.STAGGER_DAMAGE_BONUS > 0 then
			local bonus = delta * CFG.STAGGER_DAMAGE_BONUS
			lastHealth = math.max(0, health - bonus)
			humanoid.Health = lastHealth
		end
		if not returning then
			local credited: { Fighter } = {}
			local nearest: Fighter? = nil
			local nearestDistance = math.huge
			for _, f in MobStrike.victims() do
				local d = (f.root.Position - root.Position).Magnitude
				if d <= CFG.ATTRIBUTION_RADIUS and f.model:GetAttribute("CombatState") == "Attacking" then
					table.insert(credited, f)
				end
				if d < nearestDistance then
					nearest, nearestDistance = f, d
				end
			end
			if #credited == 0 and nearest and nearestDistance <= CFG.ATTRIBUTION_RADIUS * 2 then
				credited = { nearest }
			end
			for _, f in credited do
				threat[f.model] = (threat[f.model] or 0) + delta / #credited
			end
			addStagger(delta * CFG.STAGGER_PER_DAMAGE)
		end
		if not enraged and humanoid.Health <= humanoid.MaxHealth * CFG.ENRAGE_HEALTH then
			enraged = true
			model:SetAttribute("Enraged", true)
		end
	end))

	-- ── decisions ──────────────────────────────────────────────────────────────

	local function chooseMove(victims: { Fighter }): string?
		local t = now()
		local f = target :: Fighter
		local d = flatDistance(f.root.Position, root.Position)
		local sight = clearLine(root.Position, f.root.Position)
		local isWary = wary(f)
		local turtling = blockSince[f.model] ~= nil and t - blockSince[f.model] >= CFG.TURTLE_BLOCK_TIME
		local punishable = f.stunEnd > t or f.ragdollEnd > t
		local kiting = kiteSince ~= nil and t - kiteSince >= CFG.KITE_TIME
		local near = 0
		local kickTarget: Fighter? = nil
		for _, v in victims do
			local vd = flatDistance(v.root.Position, root.Position)
			if vd <= CFG.CLOSE_RANGE then
				near += 1
			end
			local since = behindSince[v.model]
			if since and t - since >= CFG.BEHIND_TIME and not kickTarget then
				kickTarget = v
			end
		end

		local options: { { name: string, score: number } } = {}
		local total = 0
		for _, name in MOVES do
			local a = (A :: any)[name]
			if (cooldowns[name] or 0) > t or (a.enragedOnly and not enraged) then
				continue
			end
			local score = a.weight
			if name == "RearKick" then
				if not kickTarget then
					continue
				end
			else
				if d < a.minRange or d > a.maxRange then
					continue
				end
				if (name == "Barrage" or name == "Quake") and not sight then
					continue
				end
				if name == "Charge" and not sight and not chargeLine(root.Position, f.root.Position) then
					continue
				end
			end
			if name == "Stomp" then
				score += (if near >= CFG.SURROUNDED then 4 else 0) + (if turtling then 3 else 0) + (if isWary then 2 else 0)
			elseif name == "Charge" then
				score += (if turtling then 2 else 0) + (if d > 30 then 1 else 0)
			elseif name == "Barrage" then
				score += if kiting then 3 else 0
			elseif name == "Sweep" or name == "Headbutt" then
				score += (if punishable then CFG.PUNISH_BONUS else 0) - (if isWary then 1 else 0) - (if turtling then 1 else 0)
			elseif name == "Quake" then
				score += (if near >= CFG.SURROUNDED then 2 else 0) + (if d > 25 then 2 else 0)
			end
			if score > 0 then
				table.insert(options, { name = name, score = score })
				total += score
			end
		end
		if total <= 0 then
			return nil
		end
		local pick = math.random() * total
		for _, o in options do
			pick -= o.score
			if pick <= 0 then
				return o.name
			end
		end
		return options[#options].name
	end

	local function position(t: number)
		local f = target :: Fighter
		local d = flatDistance(f.root.Position, root.Position)
		local meleeReady = (cooldowns.Sweep or 0) <= t or (cooldowns.Headbutt or 0) <= t
		if t < circleUntil or (d <= CFG.CIRCLE_RADIUS + 6 and not meleeReady) then
			if t >= circleUntil then
				circleUntil = t + CFG.CIRCLE_TIME_MIN + math.random() * (CFG.CIRCLE_TIME_MAX - CFG.CIRCLE_TIME_MIN)
				circleDirection = if math.random() < 0.5 then -1 else 1
			end
			local away = flatUnit(root.Position - f.root.Position)
			if away == Vector3.zero then
				away = Vector3.xAxis
			end
			local step = CFrame.Angles(0, math.rad(40) * circleDirection, 0):VectorToWorldSpace(away)
			setState("Circle")
			setFacing(true)
			faceToward(f.root.Position)
			walkTo(f.root.Position + step * CFG.CIRCLE_RADIUS, CFG.CIRCLE_SPEED)
		else
			setState("Chase")
			setFacing(false)
			walkTo(predicted(f, 0.3), CFG.CHASE_SPEED)
		end
	end

	local function roam(t: number)
		if roamGoal then
			local goal = roamGoal :: Vector3
			if flatDistance(goal, root.Position) < 4 or t - roamSince > ROAM_GIVE_UP then
				roamGoal = nil
				roamWaitUntil = t + CFG.ROAM_PAUSE_MIN + math.random() * (CFG.ROAM_PAUSE_MAX - CFG.ROAM_PAUSE_MIN)
				stopMoving()
				setState("Idle")
			else
				walkTo(goal, CFG.ROAM_SPEED)
			end
		elseif t >= roamWaitUntil then
			local angle = math.random() * 2 * math.pi
			local r = CFG.ROAM_RADIUS * math.sqrt(math.random())
			roamGoal = home + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
			roamSince = t
			setState("Roam")
		end
	end

	local function regenerate(dt: number)
		if humanoid.Health < humanoid.MaxHealth then
			lastHealth = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * CFG.RETURN_REGEN * dt)
			humanoid.Health = lastHealth
		end
	end

	local function think(dt: number)
		local t = now()
		if root.Position.Y < home.Y - FALL_LIMIT then
			interrupt()
			model:PivotTo(CFrame.new(home + Vector3.new(0, rootHeight, 0)))
			startReturn()
		end
		if stagger > 0 and state ~= "Staggered" and t - staggerHitAt >= CFG.STAGGER_REGEN_DELAY then
			stagger = math.max(0, stagger - CFG.STAGGER_REGEN * dt)
			model:SetAttribute("Stagger", stagger / CFG.STAGGER_MAX)
		end
		if t < holdUntil or busy then
			return
		end
		yaw = yawOf(root.CFrame.LookVector)

		if returning then
			trackProgress(t, true)
			regenerate(dt)
			if flatDistance(root.Position, home) <= CFG.HOME_TOLERANCE then
				finishReturn()
			else
				walkTo(home, CFG.RETURN_SPEED)
			end
			return
		end

		local victims = MobStrike.victims()
		refreshTargets(victims, dt)
		if not target then
			if engaged then
				startReturn()
				return
			end
			setFacing(false)
			trackProgress(t, roamGoal ~= nil)
			regenerate(dt)
			roam(t)
			return
		end
		if flatDistance(root.Position, home) > CFG.LEASH_RADIUS then
			startReturn()
			return
		end
		trackProgress(t, state == "Chase" or state == "Circle")

		if not engaged then
			engaged = true
			if (cooldowns.Roar or 0) <= t then
				perform("Roar")
				return
			end
		end
		if enraged and not enrageRoared then
			enrageRoared = true
			perform("Roar")
			return
		end
		local move = chooseMove(victims)
		if move then
			perform(move)
		else
			position(t)
		end
	end

	-- facing is applied every frame so turns stay smooth
	table.insert(connections, RunService.Heartbeat:Connect(function(dt: number)
		if align.Enabled then
			local step = math.rad(CFG.TURN_RATE) * dt
			local delta = angleDelta(yaw, desiredYaw)
			yaw += math.clamp(delta, -step, step)
			align.CFrame = CFrame.Angles(0, yaw, 0)
		end
	end))

	table.insert(connections, humanoid.Died:Connect(function()
		if not alive then
			return
		end
		alive = false
		actionToken += 1
		busy = false
		for _, c in connections do
			c:Disconnect()
		end
		endAction()
		setState("Dead")
		model:SetAttribute("TargetName", nil)
		align:Destroy()
		turnAttachment:Destroy()
		-- crumble: every chunk falls on its own
		for _, d in model:GetDescendants() do
			if d:IsA("Motor6D") then
				d:Destroy()
			end
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d ~= root then
				d.CanCollide = true
				d.Massless = false
				d.AssemblyLinearVelocity = flatUnit(d.Position - root.Position) * (8 + math.random() * 10) + Vector3.new(0, 12 + math.random() * 10, 0)
				d.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 6
			end
		end
		onDead()
	end))

	task.spawn(function()
		local last = now()
		while running and alive do
			local t = now()
			local ok, err = pcall(think, t - last)
			if not ok then
				warn("[JunkRam] think failed: " .. tostring(err))
			end
			last = t
			task.wait(CFG.THINK_INTERVAL)
		end
	end)

	return function()
		running = false
		alive = false
		actionToken += 1
		for _, c in connections do
			c:Disconnect()
		end
	end
end

return JunkRamBrain
