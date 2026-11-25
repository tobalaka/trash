--!strict
--[[
	Ragdoll - server-owned R6 ragdolls and grab holds (02-Systems/Combat/Ragdoll, Directional-Grab).

	While a fighter is ragdolled or held, the server owns its physics (network owner nil), so a
	throw lands the same for everyone (ADR-003). The shoulders and hips swap their Motor6Ds for
	BallSocketConstraints, with invisible colliders on the limbs so they rest on the floor; the
	neck stays rigid. Recovery restores the joints and hands physics back to the player.
	Clients watch the "Ragdolled" character attribute to switch their Humanoid state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Combat"))
local Fighters = require(script.Parent:WaitForChild("Fighters"))

type Fighter = Fighters.Fighter

local JOINTS = { ["Right Shoulder"] = true, ["Left Shoulder"] = true, ["Right Hip"] = true, ["Left Hip"] = true }
local TAG = "RagdollPart"
-- turns a limb joint's frame so the attachment's primary axis runs down the limb (the cone axis)
local DOWN_AXIS = CFrame.Angles(0, 0, -math.pi / 2)

local Ragdoll = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function takeOwnership(f: Fighter)
	pcall(function()
		f.root:SetNetworkOwner(nil)
	end)
end

local function returnOwnership(f: Fighter)
	pcall(function()
		if f.player and f.player.Parent then
			f.root:SetNetworkOwner(f.player)
		else
			f.root:SetNetworkOwnershipAuto()
		end
	end)
end

local function torsoMotors(f: Fighter): { Motor6D }
	local torso = f.model:FindFirstChild("Torso")
	local motors: { Motor6D } = {}
	if torso then
		for _, m in torso:GetChildren() do
			if m:IsA("Motor6D") and JOINTS[m.Name] and m.Part0 and m.Part1 then
				table.insert(motors, m)
			end
		end
	end
	return motors
end

function Ragdoll.active(f: Fighter): boolean
	return f.model:GetAttribute("Ragdolled") == true
end

function Ragdoll.stop(f: Fighter)
	f.ragdollEnd = 0
	if not f.model.Parent or not Ragdoll.active(f) then
		return
	end
	for _, d in f.model:GetDescendants() do
		if d.Name == TAG then
			d:Destroy()
		end
	end
	for _, m in torsoMotors(f) do
		m.Enabled = true
	end
	f.humanoid.PlatformStand = false
	f.model:SetAttribute("Ragdolled", nil)
	if not f.heldBy then
		returnOwnership(f)
	end
end

-- Ragdolls `f` for `duration` seconds (capped at RAGDOLL_MAX_DURATION unless `uncapped`, which
-- the knocked state uses). Calling it again while ragdolled extends the time.
function Ragdoll.start(f: Fighter, duration: number, uncapped: boolean?)
	if not uncapped then
		duration = math.min(duration, Config.RAGDOLL_MAX_DURATION)
	end
	f.ragdollEnd = math.max(f.ragdollEnd, now() + duration)
	takeOwnership(f)
	if not Ragdoll.active(f) then
		for _, m in torsoMotors(f) do
			local part0, part1 = m.Part0 :: BasePart, m.Part1 :: BasePart
			local a0 = Instance.new("Attachment")
			a0.Name = TAG
			a0.CFrame = m.C0 * DOWN_AXIS
			a0.Parent = part0
			local a1 = Instance.new("Attachment")
			a1.Name = TAG
			a1.CFrame = m.C1 * DOWN_AXIS
			a1.Parent = part1
			local socket = Instance.new("BallSocketConstraint")
			socket.Name = TAG
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = true
			socket.UpperAngle = 80
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -40
			socket.TwistUpperAngle = 40
			socket.Parent = part0
			local collider = Instance.new("Part")
			collider.Name = TAG
			collider.Size = Vector3.new(0.8, 1.6, 0.8)
			collider.Transparency = 1
			collider.Massless = true
			collider.CanQuery = false
			collider.CanTouch = false
			collider.CFrame = part1.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = collider
			weld.Part1 = part1
			weld.Parent = collider
			collider.Parent = part1
			m.Enabled = false
		end
		f.humanoid.PlatformStand = true
		f.model:SetAttribute("Ragdolled", true)
	end
	local ends = f.ragdollEnd
	task.delay(duration, function()
		if f.ragdollEnd == ends then
			Ragdoll.stop(f)
		end
	end)
end

-- Holds `victim` in front of `holder` (a grab). The server owns the victim until release.
function Ragdoll.hold(victim: Fighter, holder: Fighter)
	takeOwnership(victim)
	victim.humanoid.PlatformStand = true
	local front = Instance.new("Attachment")
	front.Name = "GrabFront"
	front.CFrame = CFrame.new(0, 0, -Config.GRAB_HOLD_DISTANCE) * CFrame.Angles(0, math.pi, 0)
	front.Parent = holder.root
	local own = Instance.new("Attachment")
	own.Name = "GrabHeld"
	own.Parent = victim.root
	local position = Instance.new("AlignPosition")
	position.Name = "GrabHeld"
	position.Attachment0 = own
	position.Attachment1 = front
	position.RigidityEnabled = true
	position.Parent = victim.root
	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "GrabHeld"
	orientation.Attachment0 = own
	orientation.Attachment1 = front
	orientation.RigidityEnabled = true
	orientation.Parent = victim.root
	victim.heldBy = holder
	victim.hold = { front, own, position, orientation }
end

-- Carries a knocked `victim` over `carrier`'s right shoulder: face down, head behind, legs in front.
-- The carrier's player simulates the victim (network owner) so the body never lags behind their own
-- character, the victim weighs nothing and never collides with the carrier. Returns the instances
-- to destroy on drop.
function Ragdoll.carry(victim: Fighter, carrier: Fighter): { Instance }
	local made: { Instance } = {}
	victim.humanoid.PlatformStand = true
	local shoulder = Instance.new("Attachment")
	shoulder.Name = "CarryShoulder"
	-- victim axes in the carrier's frame: right = -X, up (head) = +Z (behind), back = +Y (face down)
	shoulder.CFrame = CFrame.fromMatrix(Vector3.new(0.8, 1.55, 0.45), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
	shoulder.Parent = carrier.root
	table.insert(made, shoulder)
	local own = Instance.new("Attachment")
	own.Name = "CarryHeld"
	own.Parent = victim.root
	table.insert(made, own)
	local position = Instance.new("AlignPosition")
	position.Name = "CarryHeld"
	position.Attachment0 = own
	position.Attachment1 = shoulder
	position.RigidityEnabled = true
	position.Parent = victim.root
	table.insert(made, position)
	local orientation = Instance.new("AlignOrientation")
	orientation.Name = "CarryHeld"
	orientation.Attachment0 = own
	orientation.Attachment1 = shoulder
	orientation.RigidityEnabled = true
	orientation.Parent = victim.root
	table.insert(made, orientation)
	for _, a in victim.model:GetDescendants() do
		if a:IsA("BasePart") and not a.Massless then
			a.Massless = true
			a:SetAttribute("CarryMassless", true)
		end
	end
	-- body parts only (the Humanoid flips Torso / Head collisions with its state, so every pair)
	for _, a in victim.model:GetChildren() do
		if a:IsA("BasePart") then
			for _, b in carrier.model:GetChildren() do
				if b:IsA("BasePart") then
					local nc = Instance.new("NoCollisionConstraint")
					nc.Name = "CarryNoCollide"
					nc.Part0 = a
					nc.Part1 = b
					nc.Parent = a
					table.insert(made, nc)
				end
			end
		end
	end
	pcall(function()
		victim.root:SetNetworkOwner(carrier.player)
	end)
	return made
end

-- Undoes Ragdoll.carry. The victim is left to the caller (a ragdoll, or standing up).
function Ragdoll.uncarry(victim: Fighter, made: { Instance })
	for _, d in made do
		d:Destroy()
	end
	for _, a in victim.model:GetDescendants() do
		if a:IsA("BasePart") and a:GetAttribute("CarryMassless") then
			a.Massless = false
			a:SetAttribute("CarryMassless", nil)
		end
	end
end

-- Lets go of a held victim. `keepOwnership` when a ragdoll follows straight away.
function Ragdoll.release(victim: Fighter, keepOwnership: boolean)
	for _, part in victim.hold or {} do
		part:Destroy()
	end
	victim.hold = nil
	victim.heldBy = nil
	if not Ragdoll.active(victim) then
		victim.humanoid.PlatformStand = false
		if not keepOwnership then
			returnOwnership(victim)
		end
	end
end

return Ragdoll
