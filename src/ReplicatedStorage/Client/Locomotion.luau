--!strict
--[[
	Locomotion - the always-on base animation for the local character: idle, walk, run,
	crouch, jump, fall, landing, climbing and swimming. Walk and run play backwards when moving
	backwards (shiftlock strafing). Moves from Movement and CombatController play on top at
	higher priorities.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Client = ReplicatedStorage:WaitForChild("Client")
local Anims = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Anims"))
local Action = require(Client:WaitForChild("Action"))
local M = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Movement"))

local State = Enum.HumanoidStateType

local Locomotion = {}

function Locomotion.start(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	local set = Anims.forAnimator(animator)
	set:preload()

	local base: string? = nil
	local minVy = 0

	local function setBase(name: string?, fade: number)
		if base == name then
			return
		end
		if base then
			set:stop(base, fade)
		end
		base = name
		if name then
			set:play(name, fade)
		end
	end

	humanoid.StateChanged:Connect(function(_, new)
		local busy = Action.get(character) ~= nil
		if new == State.Jumping then
			if not busy then
				set:play("Jump", 0.1)
			end
		elseif new == State.Landed then
			local impact = -minVy
			minVy = 0
			if busy then
				return
			end
			if impact >= M.HARD_LAND_SPEED then
				set:play("Land", 0.05)
			elseif impact >= M.SOFT_LAND_SPEED then
				set:play("SoftLand", 0.05)
			end
		end
	end)

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not character.Parent or humanoid.Health <= 0 then
			setBase(nil, 0.2)
			connection:Disconnect()
			return
		end
		local state = humanoid:GetState()
		local velocity = root.AssemblyLinearVelocity
		if state == State.Climbing then
			setBase("Climb", 0.15)
			local track = set:get("Climb")
			if track then
				track:AdjustSpeed(math.clamp(math.abs(velocity.Y) / 8, 0, 1.5))
			end
		elseif state == State.Swimming then
			setBase("SwimIdle", 0.2)
		elseif state == State.Freefall or state == State.Jumping then
			minVy = math.min(minVy, velocity.Y)
			local jump = set:get("Jump")
			setBase(if jump and jump.IsPlaying then nil else "Fall", 0.2)
		elseif state == State.Seated or state == State.Dead or state == State.Physics or state == State.PlatformStanding then
			-- seated, ragdolled (Physics) or held in a grab (PlatformStanding)
			setBase(nil, 0.2)
		else
			local planar = Vector3.new(velocity.X, 0, velocity.Z)
			local speed = planar.Magnitude
			local crouching = character:GetAttribute("Crouching") == true
			if speed > 0.75 and humanoid.MoveDirection.Magnitude > 0.05 then
				local sprinting = character:GetAttribute("Sprinting") == true
				local name = if crouching then "CrouchWalk" elseif sprinting then "Run" else "Walk"
				local reference = if crouching then M.CROUCH_SPEED elseif sprinting then M.RUN_SPEED else M.WALK_SPEED
				setBase(name, 0.15)
				local track = set:get(name)
				if track then
					local backwards = root.CFrame.LookVector:Dot(planar.Unit) < -0.3
					local rate = math.clamp(speed / reference, 0.4, 1.6)
					track:AdjustSpeed(if backwards then -rate else rate)
				end
			else
				setBase(if crouching then "CrouchIdle" else "Idle", 0.2)
			end
		end
	end)
end

return Locomotion
