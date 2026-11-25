--!strict
--[[
	Animate - procedural poses for a Looks body, written out as part CFrames for one
	workspace:BulkMoveTo per frame (no Humanoid, no Animator, no physics).

	A pose is a set of posture channels (degrees, and studs for bob) that ease toward goals, plus
	a gait cycle driven by the distance walked, blended in by how fast the person moves:
	  - walkers swing arms and legs, roll and bob; kids bounce more; a crate is held out front,
	    a bucket hangs from the right hand;
	  - standing roles pick a gesture every Config.GESTURE_SLOT seconds from (seed, slot), the
	    same on every client: shopkeepers fold their arms or beckon, shoppers lean in and reach,
	    groups take turns talking, the crier calls out with raised arms;
	  - anyone near the local player turns their head to look; a shopkeeper also turns and waves.
	Joint signs: +pitch swings a limb forward or lifts the nose, +roll raises the right arm
	sideways (the left arm uses -roll), +yaw turns left.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Townsfolk"))
local Looks = require(script.Parent:WaitForChild("Looks"))

local Animate = {}

export type Drive = {
	position: Vector3, -- feet on the ground
	yaw: number, -- facing to turn toward (radians, 0 faces -Z)
	moving: boolean,
	speed: number,
	travelled: number, -- distance walked, drives the gait phase
	role: Looks.Role,
	seed: number,
	member: number, -- index in a loiter group (1 otherwise)
	members: number,
}
export type State = {
	channels: { [string]: number },
	gait: number, -- 0 standing .. 1 walking
	yaw: number,
	slot: number,
	gesture: string,
	waveUntil: number,
	waveReady: number,
	near: boolean, -- the player was within WAVE_RADIUS last pose (one wave per approach)
	look: number, -- smoothed head yaw toward the player
	lookPitch: number,
}

local CHANNELS = { "bob", "lean", "roll", "twist", "headYaw", "headPitch", "headRoll", "lArmPitch", "lArmRoll", "rArmPitch", "rArmRoll", "lLegPitch", "rLegPitch" }
local GESTURES: { [string]: { string } } = {
	Vendor = { "Rest", "Rest", "Rest", "Beckon", "Beckon", "LookAround", "Adjust" },
	Shopper = { "Browse", "Browse", "Reach", "Reach", "LookAround", "TurnChat" },
	Loiter = { "Talk" },
	Crier = { "Call", "Call", "Point", "Rest" },
	Walker = { "LookAround" },
}

local rad = math.rad
local BONE = Looks.BONE

-- resting arms per pose: left pitch, left roll, right pitch, right roll (inward roll is + for the
-- left arm, - for the right)
local REST_ARMS: { [string]: { number } } = {
	Crossed = { 70, 38, 70, -38 },
	Behind = { -22, 6, -22, -6 },
	Hips = { -12, -32, -12, 32 },
	Down = { 2, -4, 2, 4 },
	Crate = { 78, 14, 78, -14 },
}

function Animate.newState(yaw: number): State
	local channels = {}
	for _, c in CHANNELS do
		channels[c] = 0
	end
	return { channels = channels, gait = 0, yaw = yaw, slot = -1, gesture = "Rest", waveUntil = 0, waveReady = 0, near = false, look = 0, lookPitch = 0 }
end

local function angleTo(from: number, to: number): number
	return (to - from + math.pi) % (2 * math.pi) - math.pi
end

-- posture goals for a standing (or paused) person
local function posture(body: Looks.Body, state: State, drive: Drive, now: number, goal: { [string]: number })
	local seed = drive.seed
	local slotTime = now + (seed % 97) / 97 * Config.GESTURE_SLOT
	local slot = math.floor(slotTime / Config.GESTURE_SLOT)
	local u = (slotTime % Config.GESTURE_SLOT) / Config.GESTURE_SLOT -- 0..1 through the slot
	if slot ~= state.slot then
		state.slot = slot
		local list = GESTURES[drive.role] or GESTURES.Walker
		state.gesture = list[Random.new(seed + slot * 131):NextInteger(1, #list)]
	end
	local arms = REST_ARMS[body.pose] or REST_ARMS.Down
	goal.lArmPitch, goal.lArmRoll, goal.rArmPitch, goal.rArmRoll = arms[1], arms[2], arms[3], arms[4]
	local wobble = math.sin(now * 1.3 + seed) -- slow personal sway
	goal.headYaw = wobble * 8
	goal.twist = wobble * 3
	local g = state.gesture
	local swell = math.sin(u * math.pi) -- 0 at the slot's ends, 1 in the middle
	if g == "LookAround" then
		goal.headYaw = math.sin(u * 2 * math.pi) * 45
		goal.twist = math.sin(u * 2 * math.pi) * 10
	elseif g == "Beckon" then
		goal.rArmPitch = 60 * swell + arms[3] * (1 - swell)
		goal.rArmRoll = 12
		goal.rArmPitch += math.sin(now * 9) * 14 * swell
		goal.headPitch = 4
	elseif g == "Adjust" then
		goal.lArmPitch, goal.rArmPitch = 38, 38
		goal.lArmRoll, goal.rArmRoll = 10, -10
		goal.lean = 6
		goal.headPitch = -16
	elseif g == "Browse" then
		goal.lean = 7
		goal.headPitch = -18
		goal.lArmPitch, goal.rArmPitch = 10, 10
	elseif g == "Reach" then
		goal.lean = 9
		goal.headPitch = -14
		goal.rArmPitch = 75 * swell
		goal.rArmRoll = 6
	elseif g == "TurnChat" then
		goal.twist = 35 * swell
		goal.headYaw = 30 * swell
	elseif g == "Talk" then
		-- members take turns: the speaker gestures, the rest nod along
		local speaker = (state.slot % math.max(drive.members, 1)) + 1
		if drive.member == speaker then
			goal.lArmPitch = 25 + math.sin(now * 5.3 + seed) * 18
			goal.rArmPitch = 35 + math.sin(now * 4.1) * 22
			goal.lArmRoll, goal.rArmRoll = -10, 14
			goal.headRoll = math.sin(now * 3) * 6
		else
			goal.headPitch = math.max(0, math.sin(now * 4 + drive.member)) * -8
			if seed % 3 == 0 then
				local crossed = REST_ARMS.Crossed
				goal.lArmPitch, goal.lArmRoll, goal.rArmPitch, goal.rArmRoll = crossed[1], crossed[2], crossed[3], crossed[4]
			end
		end
	elseif g == "Call" then
		local beat = math.sin(now * 2.2)
		goal.rArmRoll = 110 + beat * 35
		goal.lArmRoll = -(110 - beat * 35)
		goal.headPitch = 12
		goal.lean = -4
	elseif g == "Point" then
		goal.rArmPitch = 92
		goal.rArmRoll = 4
		goal.headPitch = 6
	end
	goal.bob = math.sin(now * 1.7 + seed) * Config.BREATH
end

--[[
	Updates `state` for `dt` seconds and appends the body's part CFrames to parts/cframes.
	focus: the local player's head, for looking and waving (nil when there is none).
]]
function Animate.step(body: Looks.Body, state: State, drive: Drive, now: number, dt: number, focus: Vector3?, parts: { BasePart }, cframes: { CFrame })
	local s = body.scale
	local goal: { [string]: number } = {}
	for _, c in CHANNELS do
		goal[c] = 0
	end

	-- facing; a shopkeeper turns toward a player who comes close, and waves
	local targetYaw = drive.yaw
	local toPlayer: Vector3? = nil
	local playerDist = math.huge
	if focus then
		local d = (focus - drive.position) * Vector3.new(1, 0, 1)
		playerDist = d.Magnitude
		if playerDist > 0.1 then
			toPlayer = d / playerDist
		end
	end
	local near = drive.role == "Vendor" and toPlayer ~= nil and playerDist < Config.WAVE_RADIUS
	if near and toPlayer then
		if not state.near and now >= state.waveReady then
			state.waveUntil = now + Config.WAVE_TIME
			state.waveReady = now + Config.WAVE_COOLDOWN
		end
		local yawToPlayer = math.atan2(-toPlayer.X, -toPlayer.Z)
		targetYaw = drive.yaw + math.clamp(angleTo(drive.yaw, yawToPlayer), -rad(60), rad(60))
	end
	state.near = near
	local turn = math.clamp(angleTo(state.yaw, targetYaw), -Config.TURN_RATE * dt, Config.TURN_RATE * dt)
	state.yaw += turn

	-- posture
	if drive.moving then
		local arms = if body.carry == "Crate" then REST_ARMS.Crate else REST_ARMS.Down
		goal.lArmPitch, goal.lArmRoll, goal.rArmPitch, goal.rArmRoll = arms[1], arms[2], arms[3], arms[4]
		goal.lean = Config.WALK_LEAN * (if body.kid then 1.5 else 1)
		goal.headYaw = math.sin(now * 0.7 + drive.seed) * 10
	else
		posture(body, state, drive, now, goal)
	end
	if now < state.waveUntil then
		local k = math.sin(math.clamp((state.waveUntil - now) / Config.WAVE_TIME, 0, 1) * math.pi)
		goal.rArmRoll = 150 * k + goal.rArmRoll * (1 - k) + math.sin(now * 11) * 18 * k
		goal.rArmPitch = 8 * k + goal.rArmPitch * (1 - k)
	end

	-- look at the player when close
	local look, lookPitch = 0, 0
	if toPlayer and focus and playerDist < Config.LOOK_RADIUS then
		local rel = angleTo(state.yaw, math.atan2(-toPlayer.X, -toPlayer.Z))
		if math.abs(rel) < rad(110) then
			look = math.clamp(math.deg(rel), -Config.LOOK_LIMIT, Config.LOOK_LIMIT)
			local headY = drive.position.Y + 4.75 * s
			lookPitch = math.clamp(math.deg(math.atan2(focus.Y - headY, math.max(playerDist, 1))), -25, 25)
		end
	end

	local alpha = 1 - math.exp(-Config.SMOOTHING * dt)
	local ch = state.channels
	for _, c in CHANNELS do
		ch[c] += (goal[c] - ch[c]) * alpha
	end
	state.gait += ((if drive.moving then 1 else 0) - state.gait) * alpha
	state.look += (look - state.look) * alpha
	state.lookPitch += (lookPitch - state.lookPitch) * alpha

	-- gait cycle, from the distance walked so every client strides in step
	local gw = state.gait
	local stride = Config.STRIDE * s * (if body.kid then 0.85 else 1)
	local phase = drive.travelled / stride * math.pi
	local swing = math.sin(phase)
	local legSwing = Config.LEG_SWING * (if body.kid then 1.2 else 1) * gw
	local armSwing = if body.carry == "Crate" then 3 elseif body.carry == "Bucket" then Config.ARM_SWING * 0.5 else Config.ARM_SWING * (if body.kid then 1.4 else 1)
	local lLeg = ch.lLegPitch + swing * legSwing
	local rLeg = ch.rLegPitch - swing * legSwing
	local drop = 2 * (1 - math.cos(rad(math.max(math.abs(lLeg), math.abs(rLeg))))) -- the lower foot stays on the ground
	local bounce = math.abs(math.sin(phase)) * (if body.kid then Config.KID_BOB else Config.BOB) * gw
	local bob = ch.bob + bounce - drop
	local roll = ch.roll + swing * 3 * gw
	local twist = ch.twist + swing * 5 * gw

	local root = CFrame.new(drive.position) * CFrame.Angles(0, state.yaw, 0)
	local torso = root * CFrame.new(0, (3 + bob) * s, 0) * CFrame.Angles(rad(-ch.lean), rad(twist), rad(roll))
	local neck = torso
		* CFrame.new(0, s, 0)
		* CFrame.Angles(0, rad(ch.headYaw + state.look - twist), 0)
		* CFrame.Angles(rad(ch.headPitch + state.lookPitch), 0, rad(ch.headRoll))
	local lArm = torso * CFrame.new(-1.53 * s, 0.75 * s, 0) * CFrame.Angles(rad(ch.lArmPitch - swing * armSwing * gw), 0, rad(ch.lArmRoll))
	local rArm = torso * CFrame.new(1.53 * s, 0.75 * s, 0) * CFrame.Angles(rad(ch.rArmPitch + swing * armSwing * gw), 0, rad(ch.rArmRoll))
	local lHip = torso * CFrame.new(-0.52 * s, -s, 0) * CFrame.Angles(rad(lLeg), 0, 0)
	local rHip = torso * CFrame.new(0.52 * s, -s, 0) * CFrame.Angles(rad(rLeg), 0, 0)
	local frames = { torso, neck, lArm, rArm, lHip, rHip }
	for i, part in body.parts do
		table.insert(parts, part)
		table.insert(cframes, frames[body.bones[i]] * body.offsets[i])
	end
end

Animate.BONE = BONE

return Animate
