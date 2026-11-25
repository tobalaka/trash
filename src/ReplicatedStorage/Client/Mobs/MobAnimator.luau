--!strict
--[[
	MobAnimator - procedural animation for Pollution Beasts, on every client. No animation assets:
	each frame it writes the Motor6D.Transform of the root, neck and four hips from
	  - locomotion: a trot (diagonal legs together) that becomes a bound while charging, with leg
	    lift, body bob, sway and a lean into turns; idle breathing when still;
	  - the head tracking the beast's target (TargetName attribute);
	  - the move in progress (Action, ActionStart, ActionWindup, ActionPhase attributes), each a
	    set of keyframed channels timed from the server's start time, so every client shows the
	    swing landing when the server resolves it;
	  - MobState poses (Dazed, Staggered) and a flinch when it takes damage.
	All channels are smoothed so interrupted moves blend out instead of snapping.

	Joint axes (rig built by tools/build_template.luau, beast faces -Z): +pitch lifts the nose or
	swings a foot forward, +yaw turns the head to the beast's left.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MobsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Mobs"))

type Keys = { { number } } -- { time, value } pairs
type Channels = { [string]: number }

local CHANNELS = { "rp", "ry", "rr", "rh", "rz", "np", "ny", "nr", "fp", "bp", "flp", "gait" }
local SMOOTHING = 22 -- per second; higher follows the keyframes more tightly
local TROT_SWING = 26 -- degrees of leg swing at chase speed
local GALLOP_SWING = 40
local GALLOP_SPEED = 1.35 -- multiple of CHASE_SPEED above which the gait becomes a bound
local LEG_LIFT = 0.6
local BOB = 0.28
local BREATH = 0.12
local LOOK_LIMIT = 35
local NECK_YAW_LIMIT = 60 -- move plus look; the rig's neck core covers the seam up to this turn
local LEAN_LIMIT = 8
local FLINCH_DECAY = 7
local CRASH_TIME = 0.6 -- the crash recoil's length before the daze pose takes over

local MobAnimator = {}

local rad = math.rad

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function sample(keys: Keys, e: number): number
	if e <= keys[1][1] then
		return keys[1][2]
	end
	for i = 2, #keys do
		local k0, k1 = keys[i - 1], keys[i]
		if e <= k1[1] then
			local a = (e - k0[1]) / math.max(k1[1] - k0[1], 1e-3)
			return k0[2] + (k1[2] - k0[2]) * ease(a)
		end
	end
	return keys[#keys][2]
end

-- Keyframed moves: channel -> keys, built from the use's windup W (seconds since the move began).
type Move = (W: number, cfg: any) -> { [string]: Keys }

local MOVES: { [string]: Move } = {
	Sweep = function(W, _)
		local hit, done = W + 0.14, W + 0.95
		return {
			ny = { { 0, 0 }, { W * 0.8, 40 }, { W, 42 }, { hit, -55 }, { W + 0.45, -55 }, { done, 0 } },
			np = { { 0, 0 }, { W * 0.8, -6 }, { hit, -14 }, { done, 0 } },
			ry = { { 0, 0 }, { W * 0.8, 10 }, { hit, -14 }, { done, 0 } },
			rr = { { 0, 0 }, { W * 0.8, -4 }, { hit, 5 }, { done, 0 } },
			fp = { { 0, 0 }, { W * 0.8, -6 }, { hit, 8 }, { done, 0 } },
			gait = { { 0, 1 }, { 0.15, 0.2 }, { W + 0.9, 0.2 }, { W + 1.1, 1 } },
		}
	end,
	Headbutt = function(W, cfg)
		local g = cfg.ATTACKS.Headbutt.gap
		local done = W + g + 0.8
		return {
			np = { { 0, 0 }, { W * 0.85, 22 }, { W, 22 }, { W + 0.1, -24 }, { W + 0.25, -10 }, { W + g - 0.12, 18 }, { W + g, -28 }, { W + g + 0.3, -28 }, { done, 0 } },
			rz = { { 0, 0 }, { W * 0.85, 0.6 }, { W + 0.1, -1.4 }, { W + 0.3, -0.4 }, { W + g - 0.1, 0.5 }, { W + g, -2 }, { done, 0 } },
			rp = { { 0, 0 }, { W * 0.85, 6 }, { W + 0.1, -6 }, { W + g - 0.1, 5 }, { W + g, -8 }, { done, 0 } },
			fp = { { 0, 0 }, { W + 0.1, -10 }, { W + g, -14 }, { done, 0 } },
			gait = { { 0, 1 }, { 0.15, 0.2 }, { done - 0.2, 0.2 }, { done, 1 } },
		}
	end,
	RearKick = function(W, _)
		local done = W + 0.7
		return {
			rp = { { 0, 0 }, { W * 0.8, -10 }, { W, -16 }, { W + 0.1, -20 }, { done, 0 } },
			bp = { { 0, 0 }, { W * 0.8, 25 }, { W, 25 }, { W + 0.08, -60 }, { W + 0.3, -55 }, { done, 0 } },
			rh = { { 0, 0 }, { W * 0.8, -0.3 }, { W + 0.1, 0.6 }, { done, 0 } },
			np = { { 0, 0 }, { W * 0.8, -12 }, { done, 0 } },
			fp = { { 0, 0 }, { W * 0.8, -8 }, { done, 0 } },
			gait = { { 0, 1 }, { 0.12, 0.1 }, { done - 0.2, 0.1 }, { done, 1 } },
		}
	end,
	Stomp = function(W, _)
		local done = W + 1.0
		return {
			rp = { { 0, 0 }, { W * 0.75, 30 }, { W * 0.92, 32 }, { W, -6 }, { W + 0.25, -4 }, { done, 0 } },
			rh = { { 0, 0 }, { W * 0.75, 1.2 }, { W, -0.6 }, { W + 0.3, -0.4 }, { done, 0 } },
			rz = { { 0, 0 }, { W * 0.75, 1.0 }, { W, -0.8 }, { done, 0 } },
			fp = { { 0, 0 }, { W * 0.75, 45 }, { W * 0.92, 50 }, { W, -5 }, { W + 0.3, -5 }, { done, 0 } },
			bp = { { 0, 0 }, { W * 0.75, -14 }, { W, 4 }, { done, 0 } },
			np = { { 0, 0 }, { W * 0.75, 18 }, { W, -20 }, { W + 0.4, -14 }, { done, 0 } },
			gait = { { 0, 1 }, { 0.15, 0 }, { done - 0.2, 0 }, { done, 1 } },
		}
	end,
	Charge = function(W, _)
		return {
			np = { { 0, 0 }, { 0.25, -24 }, { W, -28 } },
			rp = { { 0, 0 }, { 0.25, -6 }, { W, -7 } },
			rz = { { 0, 0 }, { 0.25, 0.8 }, { W, 1.0 } },
			gait = { { 0, 1 }, { 0.15, 0 } },
		}
	end,
	Barrage = function(W, _)
		local done = W + 0.8
		return {
			rp = { { 0, 0 }, { W * 0.7, -5 }, { W, 6 }, { done, 0 } },
			np = { { 0, 0 }, { W * 0.7, -10 }, { W, 22 }, { done, 0 } },
			rh = { { 0, 0 }, { W * 0.7, -0.6 }, { W, 0.4 }, { done, 0 } },
			gait = { { 0, 1 }, { 0.15, 0 }, { done - 0.2, 0 }, { done, 1 } },
		}
	end,
	Quake = function(W, _)
		return {
			rh = { { 0, 0 }, { W, -1.4 } },
			rp = { { 0, 0 }, { W, -6 } },
			fp = { { 0, 0 }, { W, -12 } },
			bp = { { 0, 0 }, { W, 12 } },
			np = { { 0, 0 }, { W, -10 } },
			gait = { { 0, 1 }, { 0.15, 0 } },
		}
	end,
	Roar = function(W, cfg)
		local hold = W + cfg.ATTACKS.Roar.active
		return {
			np = { { 0, 0 }, { W, 28 }, { hold, 30 }, { hold + 0.4, 0 } },
			rp = { { 0, 0 }, { W, 8 }, { hold, 8 }, { hold + 0.4, 0 } },
			rh = { { 0, 0 }, { W, 0.3 }, { hold, 0.3 }, { hold + 0.4, 0 } },
			gait = { { 0, 1 }, { 0.15, 0 }, { hold + 0.2, 0 }, { hold + 0.5, 1 } },
		}
	end,
}

-- Later stages of a move, keyed by ActionPhase, timed from when the phase began.
local PHASES: { [string]: (cfg: any) -> { [string]: Keys } } = {
	Feint = function(_)
		return {
			np = { { 0, -28 }, { 0.15, 15 }, { 0.6, 0 } },
			rp = { { 0, -7 }, { 0.5, 0 } },
			rz = { { 0, 1 }, { 0.5, 0 } },
			gait = { { 0, 0 }, { 0.6, 1 } },
		}
	end,
	Dash = function(_)
		return { np = { { 0, -28 }, { 0.2, -32 } }, rp = { { 0, -7 }, { 0.2, -8 } }, gait = { { 0, 1 } } }
	end,
	Fire = function(cfg)
		local b = cfg.ATTACKS.Barrage
		local done = (b.shards - 1) * b.interval + 0.5
		return {
			np = { { 0, 22 }, { done, 18 }, { done + 0.5, 0 } },
			rp = { { 0, 6 }, { 0.1, 9 }, { done, 4 }, { done + 0.5, 0 } },
			gait = { { 0, 0 }, { done + 0.3, 0 }, { done + 0.6, 1 } },
		}
	end,
	Leap = function(cfg)
		local air = cfg.ATTACKS.Quake.air
		return {
			rh = { { 0, -1.4 }, { 0.15, 0.4 } },
			rp = { { 0, -6 }, { 0.2, 12 }, { air * 0.6, 4 }, { air, -10 } },
			fp = { { 0, -12 }, { 0.2, 35 }, { air * 0.8, 20 }, { air, -6 } },
			bp = { { 0, 12 }, { 0.2, -35 }, { air * 0.8, -20 }, { air, 6 } },
			np = { { 0, -10 }, { 0.3, 10 }, { air, -18 } },
			gait = { { 0, 0 } },
		}
	end,
	Land = function(cfg)
		local rec = cfg.ATTACKS.Quake.recovery
		return {
			rh = { { 0, -1.4 }, { 0.15, -1.2 }, { rec, 0 } },
			rp = { { 0, -10 }, { 0.2, -6 }, { rec, 0 } },
			np = { { 0, -22 }, { rec, 0 } },
			fp = { { 0, -8 }, { rec, 0 } },
			gait = { { 0, 0 }, { rec - 0.3, 0 }, { rec, 1 } },
		}
	end,
	Crash = function(_)
		return { np = { { 0, -28 }, { 0.1, 25 }, { 0.5, -10 } }, rp = { { 0, -8 }, { 0.1, 12 }, { 0.6, 0 } }, rz = { { 0, 0 }, { 0.1, 1.5 }, { 0.6, 0 } } }
	end,
}

--[[
	Animates `model` until the returned function is called. `onFoot(leg, position)` fires when a
	foot plants (for dust and sound).
]]
function MobAnimator.attach(model: Model, onFoot: (leg: string, position: Vector3, weight: number) -> ()): () -> ()
	local cfg = (MobsConfig :: any)[model:GetAttribute("Mob") or "JunkRam"]
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local body = model:WaitForChild("Body", 10) :: BasePart?
	if not cfg or not root or not body then
		return function() end
	end
	local S = cfg.SCALE or 1 -- stud-based channels (rh, rz, lift, bob) were authored at scale 1
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootJoint = root:WaitForChild("RootJoint", 10) :: Motor6D?
	local neck = body:WaitForChild("Neck", 10) :: Motor6D?
	local hips: { [string]: Motor6D } = {}
	for _, leg in { "FL", "FR", "BL", "BR" } do
		local m = body:WaitForChild("Hip" .. leg, 10)
		if m and m:IsA("Motor6D") then
			hips[leg] = m
		end
	end
	if not rootJoint or not neck then
		return function() end
	end
	local feet: { [string]: Attachment? } = {}
	for leg, m in hips do
		local part = m.Part1
		feet[leg] = if part then part:FindFirstChild("Foot") :: Attachment? else nil
	end

	local smoothed: Channels = {}
	for _, c in CHANNELS do
		smoothed[c] = if c == "gait" then 1 else 0
	end
	local phase = 0
	local lookYaw = 0
	local lastYaw = 0
	local lean = 0
	local flinch = 0
	local flinchSide = 1
	local lastHealth = if humanoid then humanoid.Health else 0
	local lastCos: { [string]: number } = {}

	local phaseName: string? = nil
	local phaseStart = 0
	local phaseKeys: { [string]: Keys }? = nil
	local moveKeys: { [string]: Keys }? = nil
	local moveStart = 0

	local function onAction()
		local action = model:GetAttribute("Action")
		local start = model:GetAttribute("ActionStart")
		local windup = model:GetAttribute("ActionWindup")
		local build = if typeof(action) == "string" then MOVES[action] else nil
		if build and typeof(start) == "number" and typeof(windup) == "number" then
			moveKeys = build(windup, cfg)
			moveStart = start
		else
			moveKeys = nil
		end
		phaseKeys = nil
		phaseName = nil
	end

	local function onPhase()
		local p = model:GetAttribute("ActionPhase")
		local build = if typeof(p) == "string" then PHASES[p] else nil
		if build then
			phaseName = p :: string
			phaseKeys = build(cfg)
			phaseStart = workspace:GetServerTimeNow()
		end
	end

	local connections: { RBXScriptConnection } = {}
	table.insert(connections, model:GetAttributeChangedSignal("ActionSerial"):Connect(onAction))
	table.insert(connections, model:GetAttributeChangedSignal("Action"):Connect(function()
		if model:GetAttribute("Action") == "" then
			moveKeys = nil
			if phaseName ~= "Crash" then -- the crash recoil plays out over the daze
				phaseKeys = nil
			end
		end
	end))
	table.insert(connections, model:GetAttributeChangedSignal("ActionPhase"):Connect(onPhase))
	if humanoid then
		table.insert(connections, humanoid.HealthChanged:Connect(function(health)
			if health < lastHealth then
				flinch = 1
				flinchSide = if math.random() < 0.5 then -1 else 1
			end
			lastHealth = health
		end))
	end
	onAction()

	local function targetPosition(): Vector3?
		local name = model:GetAttribute("TargetName")
		local player = if typeof(name) == "string" then Players:FindFirstChild(name) else nil
		local character = if player and player:IsA("Player") then player.Character else nil
		local r = if character then character:FindFirstChild("HumanoidRootPart") else nil
		return if r and r:IsA("BasePart") then r.Position else nil
	end

	local function step(dt: number)
		if not rootJoint.Parent or not neck.Parent or model:GetAttribute("MobState") == "Dead" then
			return
		end
		local t = workspace:GetServerTimeNow()
		local clock = os.clock()
		local state = model:GetAttribute("MobState")
		local velocity = root.AssemblyLinearVelocity
		local speed = Vector2.new(velocity.X, velocity.Z).Magnitude
		local gaitWeight = math.clamp(speed / cfg.CHASE_SPEED, 0, 1.6)
		phase = (phase + speed * dt / cfg.STRIDE * 2 * math.pi) % (2 * math.pi)

		-- targets from the move, its phase and the state
		local goal: Channels = {}
		for _, c in CHANNELS do
			goal[c] = if c == "gait" then 1 else 0
		end
		local keys = moveKeys
		if keys and not phaseKeys then
			local e = t - moveStart
			for c, k in keys do
				goal[c] = sample(k, e)
			end
			if model:GetAttribute("Action") == "Charge" then
				goal.flp = -25 + 35 * math.sin(e * 14) -- pawing the ground
			elseif model:GetAttribute("Action") == "Roar" then
				goal.nr = math.sin(clock * 33) * 4
				goal.ny = math.sin(clock * 41) * 3
			elseif model:GetAttribute("Action") == "Barrage" then
				goal.rr = math.sin(clock * 30) * 1.5
			end
		end
		if phaseName == "Crash" and t - phaseStart > CRASH_TIME then
			phaseKeys = nil
			phaseName = nil
		end
		local pk = phaseKeys
		if pk then
			local e = t - phaseStart
			for c, k in pk do
				goal[c] = sample(k, e)
			end
		end
		if state == "Staggered" then
			goal.rh, goal.fp, goal.bp, goal.np = -2.4, -35, 22, -30
			goal.rr = math.sin(clock * 1.5) * 4
			goal.ny = math.sin(clock * 1.1) * 12
			goal.gait = 0
		elseif state == "Dazed" and not pk then
			goal.rh, goal.np, goal.fp = -0.8, -18, -10
			goal.rr = math.sin(clock * 3) * 5
			goal.ny = math.sin(clock * 2) * 10
			goal.gait = 0.3
		end

		-- head tracks the target
		local look = 0
		local aim = targetPosition()
		local head = neck.Part1
		if aim and head and state ~= "Staggered" then
			local d = body.CFrame:VectorToObjectSpace(aim - head.Position)
			look = math.clamp(math.deg(math.atan2(-d.X, -d.Z)), -LOOK_LIMIT, LOOK_LIMIT)
		end
		lookYaw += (look - lookYaw) * math.min(1, dt * 5)

		-- lean into turns
		local yaw = math.atan2(-root.CFrame.LookVector.X, -root.CFrame.LookVector.Z)
		local yawRate = ((yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi) / math.max(dt, 1e-3)
		lastYaw = yaw
		lean += (math.clamp(-yawRate * 6, -LEAN_LIMIT, LEAN_LIMIT) * math.min(gaitWeight, 1) - lean) * math.min(1, dt * 6)

		flinch = math.max(0, flinch - dt * FLINCH_DECAY)

		local alpha = 1 - math.exp(-SMOOTHING * dt)
		for _, c in CHANNELS do
			smoothed[c] += (goal[c] - smoothed[c]) * alpha
		end
		local s = smoothed
		local gw = gaitWeight * math.clamp(s.gait, 0, 1)

		-- locomotion
		local gallop = speed > cfg.CHASE_SPEED * GALLOP_SPEED
		local swing = rad(if gallop then GALLOP_SWING else TROT_SWING) * math.min(gw, 1.2)
		local offsets = if gallop
			then { FL = 0, FR = 0.35, BL = math.pi, BR = math.pi + 0.35 }
			else { FL = 0, BR = 0, FR = math.pi, BL = math.pi }
		local breathing = math.sin(clock * 1.7) * BREATH * (1 - math.min(gw, 1))
		local bob = -math.abs(math.sin(phase)) * BOB * math.min(gw, 1.3)
		local roll = math.sin(phase) * 2.5 * math.min(gw, 1)
		local pitch = math.sin(phase * 2) * 1.5 * math.min(gw, 1)
		local fl = flinch * flinch

		rootJoint.Transform = CFrame.new(0, (s.rh + bob + breathing - 0.25 * fl) * S, s.rz * S)
			* CFrame.Angles(rad(s.rp + pitch - 3 * fl), rad(s.ry), rad(s.rr + roll + lean + 4 * fl * flinchSide))
		neck.Transform = CFrame.Angles(
			rad(s.np + math.sin(clock * 0.9) * 3 + math.sin(phase * 2) * 4 * math.min(gw, 1) - 6 * fl),
			rad(math.clamp(s.ny + lookYaw, -NECK_YAW_LIMIT, NECK_YAW_LIMIT)),
			rad(s.nr + 3 * fl * flinchSide)
		)
		for leg, motor in hips do
			local p = phase + (offsets :: any)[leg]
			local front = leg:sub(1, 1) == "F"
			local extra = (if front then s.fp else s.bp) + (if leg == "FL" then s.flp else 0)
			local lift = math.max(0, math.cos(p)) * LEG_LIFT * math.min(gw, 1)
			motor.Transform = CFrame.new(0, lift * S, 0) * CFrame.Angles(rad(extra) + swing * math.sin(p), 0, 0)
			-- a foot plants when it finishes swinging forward
			local c = math.cos(p)
			local before = lastCos[leg]
			if before and before > 0 and c <= 0 and gw > 0.15 then
				local foot = feet[leg]
				if foot then
					onFoot(leg, foot.WorldPosition, math.min(gw, 1.5))
				end
			end
			lastCos[leg] = c
		end
	end

	table.insert(connections, RunService.PreSimulation:Connect(step))
	return function()
		for _, c in connections do
			c:Disconnect()
		end
	end
end

return MobAnimator
