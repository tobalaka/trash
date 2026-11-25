--!strict
--[[
	MoveGear - riding the Tarp Glider and the Junk Board (2026-10-25, EXPED's Glider and Skateboard).
	The Tools come from ServerScriptService/Combat/MoveGear, which also shows the models to everyone.

	  Tarp Glider  equipped: hold Space while falling to open it. It flies where the camera looks
	               (W/A/S/D steer relative to the camera), sinking slowly; look down to dive, up to
	               float. It never climbs above where it opened. Let go of Space or land to fold it.
	  Junk Board   equipped on the ground: ride. W/A/S/D push relative to the camera (EXPED: 140
	               studs/s^2 up to the top speed, 90 studs/s^2 friction), Space ollies. An attack or a
	               block steps off (unequips), so does a stun.
	The client owns its character's physics, so both run here: the glider with one LinearVelocity,
	the board with a horizontal-only LinearVelocity and an AlignOrientation (gravity stays).
	Action "Glide" / "Skate" keeps Movement's own moves and the combat input out of the way.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = ReplicatedStorage:WaitForChild("Client")
local M = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local Keys = require(Shared:WaitForChild("Config"):WaitForChild("Keys"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Anims = require(Shared:WaitForChild("Anims"))
local Action = require(Client:WaitForChild("Action"))
local Audio = require(Client:WaitForChild("Audio"))

local DISABLED = { Stunned = true, Grabbed = true, Ragdolled = true }
-- pressing one of these on the board steps off it
local STEP_OFF_KEYS = { [Keys.Block] = true, [Keys.Grab] = true, [Keys.Crit] = true }

local MoveGear = {}

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

function MoveGear.start(character: Model)
	local camera = workspace.CurrentCamera
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	local set = Anims.forAnimator(animator)
	local gearState = Remotes.get("GearState")
	local baseHip = humanoid.HipHeight

	local equipped: string? = nil -- "Glider" | "Board"
	local mode: string? = nil -- "Glide" | "Skate" while riding
	local token: {}? = nil
	local made: { Instance } = {}
	local mover: LinearVelocity? = nil
	local align: AlignOrientation? = nil
	local velocity = Vector3.zero
	local ceiling = 0

	local function free(): boolean
		local state = character:GetAttribute("CombatState")
		local action = Action.get(character)
		return humanoid.Health > 0 and not (typeof(state) == "string" and DISABLED[state])
			and (action == nil or action == mode)
			and character:GetAttribute("Knocked") ~= true and character:GetAttribute("Carrying") ~= true
	end

	local function grounded(): boolean
		return humanoid.FloorMaterial ~= Enum.Material.Air
	end

	-- W/A/S/D relative to the camera, flat
	local function wish(): Vector3
		local look = flat(camera.CFrame.LookVector)
		local right = flat(camera.CFrame.RightVector)
		local f = (if UserInputService:IsKeyDown(Enum.KeyCode.W) then 1 else 0) - (if UserInputService:IsKeyDown(Enum.KeyCode.S) then 1 else 0)
		local s = (if UserInputService:IsKeyDown(Enum.KeyCode.D) then 1 else 0) - (if UserInputService:IsKeyDown(Enum.KeyCode.A) then 1 else 0)
		return flat(look * f + right * s)
	end

	local function stop()
		local was = mode
		if not was then
			return
		end
		mode = nil
		for _, d in made do
			d:Destroy()
		end
		table.clear(made)
		mover, align = nil, nil
		if token then
			Action.clear(character, token)
			token = nil
		end
		if was == "Glide" then
			set:stop("Glide", 0.2)
			gearState:FireServer("Glide", false)
		else
			set:stop("Skate", 0.2)
			humanoid.HipHeight = baseHip
		end
	end

	local function newMover(perAxis: boolean): LinearVelocity
		local att = Instance.new("Attachment")
		att.Name = "MoveGearAtt"
		att.Parent = root
		table.insert(made, att)
		local m = Instance.new("LinearVelocity")
		m.Name = "MoveGear"
		m.Attachment0 = att
		m.RelativeTo = Enum.ActuatorRelativeTo.World
		if perAxis then
			m.ForceLimitMode = Enum.ForceLimitMode.PerAxis
			m.MaxAxesForce = Vector3.new(M.DRIVE_FORCE * 10, 0, M.DRIVE_FORCE * 10)
		else
			m.MaxForce = M.DRIVE_FORCE
		end
		m.Parent = root
		table.insert(made, m)
		return m
	end

	local function startGlide()
		mode = "Glide"
		token = Action.set(character, "Glide")
		ceiling = root.Position.Y + M.GLIDE_CEILING
		velocity = root.AssemblyLinearVelocity
		velocity = Vector3.new(velocity.X, math.max(velocity.Y, -M.GLIDE_SINK * 2), velocity.Z)
		mover = newMover(false)
		set:play("Glide", 0.15)
		Audio.play("AirDash", root)
		gearState:FireServer("Glide", true)
	end

	local function startSkate()
		mode = "Skate"
		token = Action.set(character, "Skate")
		humanoid.HipHeight = baseHip + M.SKATE_HIP
		local v = root.AssemblyLinearVelocity
		velocity = Vector3.new(v.X, 0, v.Z)
		mover = newMover(true)
		local att = (mover :: LinearVelocity).Attachment0
		local a = Instance.new("AlignOrientation")
		a.Name = "MoveGear"
		a.Mode = Enum.OrientationAlignmentMode.OneAttachment
		a.Attachment0 = att
		a.MaxTorque = math.huge
		a.Responsiveness = 14
		a.CFrame = CFrame.lookAt(Vector3.zero, flat(root.CFrame.LookVector))
		a.Parent = root
		table.insert(made, a)
		align = a
		set:play("Skate", 0.2)
	end

	local function stepGlide(dt: number)
		local m = mover :: LinearVelocity
		local look = camera.CFrame.LookVector
		local dir = wish()
		if dir == Vector3.zero then
			dir = flat(look)
		end
		local speed = M.GLIDE_SPEED * math.clamp(1 - look.Y * 2.4, 0.55, 1.9)
		local sink = M.GLIDE_SINK + math.max(0, -look.Y) * M.GLIDE_DIVE_SINK
		local target = dir * speed - Vector3.new(0, sink, 0)
		if root.Position.Y > ceiling then
			target = Vector3.new(target.X, math.min(target.Y, -M.GLIDE_SINK), target.Z)
		end
		velocity = velocity:Lerp(target, 1 - math.exp(-M.GLIDE_EASE * dt))
		m.VectorVelocity = velocity
	end

	local function stepSkate(dt: number)
		local m = mover :: LinearVelocity
		local dir = wish()
		if dir ~= Vector3.zero then
			velocity += dir * M.SKATE_ACCEL * dt
		else
			local drop = M.SKATE_FRICTION * dt
			velocity = if velocity.Magnitude <= drop then Vector3.zero else velocity - velocity.Unit * drop
		end
		if velocity.Magnitude > M.SKATE_MAX then
			velocity = velocity.Unit * M.SKATE_MAX
		end
		-- a wall ahead takes the speed going into it
		if velocity.Magnitude > 1 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			params.RespectCanCollide = true
			local hit = workspace:Raycast(root.Position, velocity.Unit * 2.2, params)
			if hit and math.abs(hit.Normal.Y) < 0.5 then
				local n = flat(hit.Normal)
				local into = velocity:Dot(n)
				if into < 0 then
					velocity -= n * into
				end
			end
			if align then
				align.CFrame = CFrame.lookAt(Vector3.zero, flat(velocity))
			end
		end
		m.VectorVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	end

	local connections: { RBXScriptConnection } = {}

	local function gearOf(child: Instance): string?
		local id = if child:IsA("Tool") then child:GetAttribute("MoveGear") else nil
		return if typeof(id) == "string" then id else nil
	end
	table.insert(connections, character.ChildAdded:Connect(function(child)
		local id = gearOf(child)
		if id then
			equipped = id
		end
	end))
	table.insert(connections, character.ChildRemoved:Connect(function(child)
		if gearOf(child) == equipped then
			equipped = nil
			stop()
		end
	end))
	for _, child in character:GetChildren() do
		equipped = gearOf(child) or equipped
	end

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or mode ~= "Skate" then
			return
		end
		if input.UserInputType == Keys.Attack or STEP_OFF_KEYS[input.KeyCode] then
			humanoid:UnequipTools() -- step off; the next press fights
		elseif input.KeyCode == Keys.Jump and grounded() then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, M.SKATE_OLLIE, v.Z)
			Audio.play("Jump", root)
		end
	end))

	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		if mode and not free() then
			stop()
			return
		end
		if mode == "Glide" then
			if grounded() or equipped ~= "Glider" or not UserInputService:IsKeyDown(Keys.Jump) then
				stop()
			else
				stepGlide(dt)
			end
		elseif mode == "Skate" then
			if equipped ~= "Board" then
				stop()
			else
				stepSkate(dt)
			end
		elseif equipped == "Glider" then
			if not grounded() and UserInputService:IsKeyDown(Keys.Jump) and root.AssemblyLinearVelocity.Y < -M.GLIDE_MIN_FALL
				and Action.get(character) == nil and free() then
				startGlide()
			end
		elseif equipped == "Board" then
			if grounded() and Action.get(character) == nil and free() then
				startSkate()
			end
		end
	end))

	humanoid.Died:Once(function()
		stop()
		for _, c in connections do
			c:Disconnect()
		end
	end)
end

return MoveGear
