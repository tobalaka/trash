--!strict
-- Authored R6 ability poses. Every viewer plays accepted server casts using server time.
-- Transform is local and deliberately never drives root physics or hit detection.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Relics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Relics"))
local Action = require(script.Parent.Parent:WaitForChild("Action"))

type Pose = { [string]: CFrame }
type Frame = { time: number, pose: Pose }
type Clip = { frames: { Frame }, duration: number }
type Joint = { motor: Motor6D, baseline: CFrame?, written: CFrame? }
type Playing = {
	character: Model, humanoid: Humanoid, joints: { [string]: Joint },
	clip: Clip, start: number, relic: string, key: string, lockEnd: number,
	actionToken: {}?, initialCombat: any, initialAction: any,
}

local RelicAnimator = {}
local active: { [Model]: Playing } = {}
local connections: { RBXScriptConnection } = {}
local IDENTITY = CFrame.new()
local rad = math.rad
local JOINTS = {
	root = "RootJoint", neck = "Neck", rs = "Right Shoulder", ls = "Left Shoulder",
	rh = "Right Hip", lh = "Left Hip",
}
local INTERRUPTED = { Stunned = true, Ragdolled = true, Grabbed = true }

-- R6 axes: root X pitches, root Z turns; right limb +Z and left limb -Z lift forward.
local function limb(forward: number, outward: number?, left: boolean?): CFrame
	return CFrame.Angles(0, 0, rad(forward) * (if left then -1 else 1))
		* CFrame.Angles(-rad(outward or 0), 0, 0)
end

local function pose(pitch: number, turn: number, right: number, left: number,
	rightLeg: number?, leftLeg: number?, rightOut: number?, leftOut: number?): Pose
	local p: Pose = {
		root = CFrame.Angles(rad(pitch), 0, rad(turn)),
		neck = CFrame.Angles(rad(-pitch * 0.45), 0, rad(-turn * 0.35)),
		rs = limb(right, rightOut), ls = limb(left, leftOut, true),
	}
	if rightLeg then p.rh = limb(rightLeg, 6) end
	if leftLeg then p.lh = limb(leftLeg, 6, true) end
	return p
end

local function upper(right: number, left: number, rightOut: number?, leftOut: number?): Pose
	return { rs = limb(right, rightOut), ls = limb(left, leftOut, true) }
end

local function frame(time: number, p: Pose): Frame
	return { time = time, pose = p }
end

local function clip(a: Relics.Ability, frames: { Frame }, duration: number?): Clip
	local last = frames[#frames].time
	return { frames = frames, duration = math.max(duration or a.windup + a.lock, last + 0.13) }
end

local function strike(a: Relics.Ability, ready: Pose, hit: Pose, follow: Pose?): Clip
	local w = math.max(a.windup, 0.06)
	return clip(a, { frame(0, ready), frame(w * 0.62, ready), frame(w, hit), frame(w + 0.1, follow or hit) })
end

-- Every entry is deliberately authored for its weapon rather than reusing an M1 track.
local builders: { [string]: (Relics.Ability) -> Clip } = {
	["Umbrella.Z"] = function(a) -- Snap the canopy forward, braced shoulders.
		return clip(a, { frame(0, upper(25, 30)), frame(0.06, upper(92, 55, 18, 12)),
			frame((a.window or 0.9) - 0.08, upper(88, 50, 18, 12)) }, a.window)
	end,
	["Umbrella.X"] = function(a) -- Two-handed spear draw and extension.
		return strike(a, pose(-12, -28, 35, 65, -20, 24), pose(24, 18, 105, 85, 20, -30), pose(17, 12, 92, 78, 10, -20))
	end,
	["Umbrella.C"] = function(a) -- Broad canopy sweep with a complete torso turn.
		return clip(a, { frame(0, pose(-5, -65, 70, 25, 12, -12, 40)),
			frame(a.windup * 0.5, pose(0, -130, 95, 55, -12, 12, 50)),
			frame(a.windup, pose(8, -230, 100, 80, 20, -20, 60, 30)),
			frame(a.windup + 0.15, pose(5, -345, 65, 40, 0, 0, 35)) })
	end,
	["Umbrella.R"] = function(a) -- Shelter stays overhead; legs remain free to walk.
		return clip(a, { frame(0, upper(40, 20)), frame(0.1, upper(165, 70, 12, 15)),
			frame((a.duration or 4) - 0.15, upper(160, 65, 12, 15)) }, a.duration)
	end,
	["Umbrella.B"] = function(a) -- Gather, raise the handle, open the sky.
		return clip(a, { frame(0, pose(14, -20, 45, 45, 12, 12)),
			frame(a.windup * 0.65, pose(-14, 0, 135, 110, -8, -8)),
			frame(a.windup, pose(-20, 0, 175, 145, -10, -10, 15, 35)),
			frame(a.windup + 0.3, pose(-8, 0, 150, 75, 0, 0, 20, 35)) })
	end,
	["PushBroom.Z"] = function(a)
		return strike(a, pose(12, -65, 55, 85, 20, -20, 20), pose(18, 65, 105, 40, -15, 25, 15, 20))
	end,
	["PushBroom.X"] = function(a)
		local w, d = a.windup, a.duration or 0.4
		return clip(a, { frame(0, pose(18, -40, 65, 65, 30, -20, 35, 25)),
			frame(w, pose(24, -120, 85, 85, -25, 30, 45, 35)),
			frame(w + d * 0.4, pose(16, -240, 95, 80, 30, -25, 45, 35)),
			frame(w + d * 0.8, pose(12, -355, 70, 65, -20, 25, 35, 25)) })
	end,
	["PushBroom.C"] = function(a) -- Hook, haul, then the second hit lands at follow.delay.
		local w, f = a.windup, if a.follow then a.follow.delay else 0.35
		return clip(a, { frame(0, pose(16, -25, 45, 75, 12, -15)),
			frame(w, pose(28, 15, 110, 90, 22, -20)),
			frame(w + f * 0.5, pose(-18, -15, 145, 120, -14, 14)),
			frame(w + f, pose(35, 20, 55, 45, 18, 18)) })
	end,
	["PushBroom.R"] = function(a)
		return strike(a, pose(8, -35, 70, 80, 12, -12), pose(35, 30, 35, 55, 20, 5), pose(22, 45, 65, 30, 8, 8))
	end,
	["PushBroom.B"] = function(a) -- Scoop the whirlwind and send it down the street.
		return clip(a, { frame(0, pose(22, -70, 35, 85, 20, -20)),
			frame(a.windup * 0.5, pose(8, -135, 110, 80, -15, 15, 30)),
			frame(a.windup, pose(-12, 25, 145, 110, -8, 15, 25)),
			frame(a.windup + 0.2, pose(22, 45, 100, 90, 15, -20)) })
	end,
	["MendersGloves.Z"] = function(a) -- Pull scrap up from the floor, then throw.
		return clip(a, { frame(0, pose(35, -20, 25, 40, 20, 20)),
			frame(a.windup * 0.55, pose(-12, -55, 145, 55, -15, 15)),
			frame(a.windup, pose(22, 45, 105, 25, 20, -20)),
			frame(a.windup + 0.1, pose(15, 60, 65, 30, 10, -10)) })
	end,
	["MendersGloves.X"] = function(a) -- Three distinct punches synchronized to all three hits.
		local w, d = a.windup, a.interval or 0.16
		return clip(a, { frame(0, pose(6, -25, 55, 60, 10, -10)),
			frame(w, pose(12, 30, 110, 45, 15, -15)),
			frame(w + d * 0.55, pose(6, 0, 50, 70, 0, 0)),
			frame(w + d, pose(12, -30, 45, 115, -15, 15)),
			frame(w + d * 1.55, pose(-12, -35, 145, 55, -10, 10)),
			frame(w + d * 2, pose(28, 35, 100, 50, 20, -20)) })
	end,
	["MendersGloves.C"] = function(a)
		return clip(a, { frame(0, pose(20, 0, 30, 30, 15, 15, 25, 25)),
			frame(a.windup * 0.65, pose(-10, 0, 95, 95, 0, 0, 20, 20)),
			frame(a.windup, pose(-15, 0, 100, 100, -10, -10, 85, 85)) })
	end,
	["MendersGloves.R"] = function(a) -- Stitching gesture, then palms outward; heal persists separately.
		return clip(a, { frame(0, upper(65, 65, -15, -15)),
			frame(a.windup, upper(95, 95, -5, -5)),
			frame(a.windup + 0.12, upper(85, 85, 45, 45)) })
	end,
	["MendersGloves.B"] = function(a)
		local frames = { frame(0, pose(-15, -15, 155, 135, -8, 10)) }
		for i = 0, #(a.offsets or { 8, 16, 24 }) - 1 do
			local t = a.windup + i * (a.interval or 0.35)
			if i > 0 then table.insert(frames, frame(t - 0.14, pose(-18, -12, 155, 135, -8, 10))) end
			table.insert(frames, frame(t, pose(38, 15, 45, 65, 18, 18)))
		end
		return clip(a, frames)
	end,
	["Sandals.Z"] = function(a)
		return strike(a, pose(15, -25, 65, 70, -40, 15), pose(-22, 30, 95, 40, 145, -12), pose(-12, 20, 75, 45, 100, 0))
	end,
	["Sandals.X"] = function(a)
		return clip(a, { frame(0, pose(35, -20, -20, 70, 55, -25)),
			frame(a.windup, pose(-20, 20, 85, 35, 105, -35)),
			frame(a.windup + (a.duration or 0.3) * 0.8, pose(-12, 15, 75, 40, 95, -25)) })
	end,
	["Sandals.C"] = function(a)
		return strike(a, pose(-12, -15, 60, 85, 95, -5), pose(28, 15, 35, 60, -15, 12), pose(16, 10, 45, 50, 0, 5))
	end,
	["Sandals.R"] = function(a)
		return clip(a, { frame(0, pose(15, 0, 45, 45, 30, 30)),
			frame(0.07, pose(-22, 0, 85, 85, 50, 40)),
			frame(a.duration or 0.25, pose(25, 0, 30, 35, 15, 15)) })
	end,
	["Sandals.B"] = function(a)
		local frames = { frame(0, pose(-12, -20, 85, 65, 90, 0)) }
		for i = 0, (a.pulses or 3) - 1 do
			local t = a.windup + i * (a.interval or 0.45)
			if i > 0 then table.insert(frames, frame(t - 0.2, pose(-12, if i % 2 == 0 then -20 else 20, 85, 80,
				if i % 2 == 0 then 100 else 0, if i % 2 == 0 then 0 else 100))) end
			table.insert(frames, frame(t, pose(25 + i * 5, 0, 40, 40, -8, -8, 20 + i * 10, 20 + i * 10)))
		end
		return clip(a, frames)
	end,
	["Hubcap.Z"] = function(a)
		return strike(a, pose(-8, -65, 70, 45, -12, 18, 20), pose(16, 55, 110, 30, 20, -15, 20))
	end,
	["Hubcap.X"] = function(a)
		return clip(a, { frame(0, pose(25, -45, 65, 35, 40, -20, 35)),
			frame(a.windup, pose(28, -95, 95, 40, 55, -35, 45)),
			frame(a.windup + (a.duration or 0.35) * 0.45, pose(20, -220, 100, 45, 55, -35, 45)),
			frame(a.windup + (a.duration or 0.35) * 0.85, pose(15, -350, 75, 35, 25, -15, 35)) })
	end,
	["Hubcap.C"] = function(a)
		return strike(a, pose(6, 65, 105, 45, 15, -15, -20), pose(14, -65, 90, 60, -15, 20, 65), pose(8, -40, 55, 50, -8, 10, 40))
	end,
	["Hubcap.R"] = function(a)
		return clip(a, { frame(0, upper(45, 55)), frame(0.05, upper(100, 65, -20, 15)),
			frame((a.window or 0.7) - 0.08, upper(95, 60, -20, 15)) }, a.window)
	end,
	["Hubcap.B"] = function(a)
		return clip(a, { frame(0, pose(-12, -70, 75, 75, -15, 15, 10, 10)),
			frame(a.windup * 0.65, pose(-18, -100, 100, 120, -20, 20, 35, 20)),
			frame(a.windup, pose(20, 70, 110, 95, 20, -20, 65, 65)),
			frame(a.windup + 0.15, pose(10, 35, 70, 65, 10, -10, 50, 50)) })
	end,
	["BossCoat.Z"] = function(a)
		return clip(a, { frame(0, pose(-12, -20, 40, 40, -10, 10, 50, 50)),
			frame(a.windup, pose(20, 15, 110, 105, 15, -15, 15, 15)),
			frame(a.windup + 0.14, pose(-15, -10, 45, 45, -10, 10, 25, 25)) })
	end,
	["BossCoat.X"] = function(a)
		return clip(a, { frame(0, pose(12, -25, 55, 70, 20, -25)),
			frame(a.windup, pose(35, -60, 65, 85, 40, -35, -15, 15)),
			frame(a.windup + (a.duration or 0.4) * 0.8, pose(30, -50, 60, 75, -25, 35, -15, 15)) })
	end,
	["BossCoat.C"] = function(a)
		return strike(a, pose(12, 0, 55, 55, 12, 12, -10, -10),
			pose(-22, 0, 25, 25, -12, -12, 60, 60), pose(-12, 0, 15, 15, 0, 0, 40, 40))
	end,
	["BossCoat.R"] = function(a) -- Button the lapels, then release arms; armor remains active.
		return clip(a, { frame(0, upper(45, 45, 10, 10)), frame(0.1, upper(80, 80, -30, -30)),
			frame(0.22, upper(35, 35, 20, 20)) }, 0.4)
	end,
	["BossCoat.B"] = function(a)
		local w, d = a.windup, a.duration or 0.55
		return clip(a, { frame(0, pose(30, 0, 45, 45, 25, 25)),
			frame(w, pose(-18, 0, 155, 145, 60, 45)),
			frame(w + d * 0.55, pose(-8, 0, 170, 160, 75, 65)),
			frame(w + d, pose(38, 0, 40, 40, 22, 22)),
			frame(w + d + 0.12, pose(20, 0, 30, 30, 12, 12, 40, 40)) })
	end,
}

local function restore(state: Playing)
	for _, joint in state.joints do
		if joint.motor.Parent and joint.written and joint.baseline and joint.motor.Transform == joint.written then
			joint.motor.Transform = joint.baseline
		end
		joint.written = nil
		joint.baseline = nil
	end
end

function RelicAnimator.stop(character: Model)
	local state = active[character]
	if not state then return end
	restore(state)
	active[character] = nil
	character:SetAttribute("RelicAnimating", nil)
	if state.actionToken then Action.clear(character, state.actionToken) end
end

local function sample(c: Clip, elapsed: number): Pose
	local frames = c.frames
	local before, after = frames[1], frames[#frames]
	for i = 2, #frames do
		if elapsed <= frames[i].time then
			before, after = frames[i - 1], frames[i]
			break
		end
		before = frames[i]
	end
	local alpha = math.clamp((elapsed - before.time) / math.max(0.0001, after.time - before.time), 0, 1)
	alpha = alpha * alpha * (3 - 2 * alpha)
	local p: Pose = {}
	for name in JOINTS do
		local a, b = before.pose[name], after.pose[name]
		if a or b then p[name] = (a or IDENTITY):Lerp(b or IDENTITY, alpha) end
	end
	return p
end

local function update()
	local time = workspace:GetServerTimeNow()
	for character, state in active do
		local elapsed = time - state.start
		local combat = character:GetAttribute("CombatState")
		local action = character:GetAttribute("Action")
		local superseded = time > state.lockEnd and
			((combat ~= state.initialCombat and (combat == "Attacking" or combat == "Dodging" or combat == "Blocking"))
			or (action ~= state.initialAction and action ~= nil and action ~= "Relic"))
		if not character.Parent or state.humanoid.Health <= 0 or elapsed >= state.clip.duration
			or INTERRUPTED[combat :: any] or character:GetAttribute("Ragdolled") or superseded then
			RelicAnimator.stop(character)
		else
			local p = sample(state.clip, math.max(0, elapsed))
			local weight = math.min(math.clamp(elapsed / 0.045, 0, 1), math.clamp((state.clip.duration - elapsed) / 0.13, 0, 1))
			for name, target in p do
				local joint = state.joints[name]
				if joint and joint.motor.Parent and joint.motor.Enabled then
					joint.baseline = joint.motor.Transform
					joint.written = joint.motor.Transform:Lerp(target, weight)
					joint.motor.Transform = joint.written :: CFrame
				end
			end
		end
	end
end

local function ensureStarted()
	if #connections > 0 then return end
	-- Undo only our previous write before the Animator evaluates the new frame. This avoids
	-- drift on joints that have no ordinary animation track and never changes rig C0/C1.
	table.insert(connections, RunService.PreAnimation:Connect(function()
		for _, state in active do restore(state) end
	end))
	table.insert(connections, RunService.PreSimulation:Connect(update))
end

function RelicAnimator.play(character: Model, relicId: string, key: string, startTime: number?): boolean
	local relic = Relics.get(relicId)
	local ability = relic and relic.abilities[key]
	local build = builders[relicId .. "." .. key]
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not ability or not build or not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 or humanoid.Health <= 0 then return false end
	local c = build(ability)
	local time = workspace:GetServerTimeNow()
	local start = if typeof(startTime) == "number" and startTime == startTime then math.min(time, startTime) else time
	if time - start >= c.duration then return false end
	RelicAnimator.stop(character)
	local joints: { [string]: Joint } = {}
	for name, motorName in JOINTS do
		local motor = character:FindFirstChild(motorName, true)
		if motor and motor:IsA("Motor6D") then joints[name] = { motor = motor } end
	end
	if not joints.root or not joints.rs or not joints.ls then return false end
	local lockEnd = start + ability.windup + ability.lock
	local token: {}? = nil
	local initialAction = character:GetAttribute("Action")
	if character == Players.LocalPlayer.Character and lockEnd > time then
		token = Action.set(character, "Relic", lockEnd - time)
	end
	active[character] = {
		character = character, humanoid = humanoid, joints = joints, clip = c,
		start = start, relic = relicId, key = key, lockEnd = lockEnd, actionToken = token,
		initialCombat = character:GetAttribute("CombatState"), initialAction = initialAction,
	}
	character:SetAttribute("RelicAnimating", true)
	ensureStarted()
	return true
end

function RelicAnimator.phase(character: Model, relicId: string, key: string, phase: string)
	local state = active[character]
	if not state or state.relic ~= relicId or state.key ~= key then return end
	if phase == "Counter" then
		-- Counter contact replaces the held stance with an actual shield/canopy bash.
		local held = sample(state.clip, workspace:GetServerTimeNow() - state.start)
		state.start = workspace:GetServerTimeNow()
		state.clip = { frames = { frame(0, held), frame(0.09, pose(20, 25, 115, 65, nil, nil, 20, 15)) }, duration = 0.32 }
	end
end

-- Inspectable coverage and timings for authoring/playtest checks; no game state mutation.
function RelicAnimator.describe(): { { id: string, key: string, name: string, duration: number, frames: number } }
	local result = {}
	for _, relic in Relics.list do
		for _, key in Relics.KEYS do
			local a = relic.abilities[key]
			local build = builders[relic.id .. "." .. key]
			assert(build, "Missing Relic animation: " .. relic.id .. "." .. key)
			local c = build(a)
			local last = -1
			for _, f in c.frames do assert(f.time >= last, "Unsorted Relic animation"); last = f.time end
			assert(c.duration > last, "Relic animation needs recovery")
			table.insert(result, { id = relic.id, key = key, name = a.name, duration = c.duration, frames = #c.frames })
		end
	end
	return result
end

return RelicAnimator
