--!strict
-- Character movement and parkour; bindings live in Shared.Config.Keys.
-- Air-jump priority: wall jump, mantle, wall climb, then double jump.
-- MoveDrive uses Plane mode for horizontal moves and Vector mode for wall moves.
-- FaceLock prevents shiftlock from turning the character on walls.
-- The server validates roll cooldowns and invulnerability through DodgeRequest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = ReplicatedStorage:WaitForChild("Client")
local M = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local C = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local Keys = require(Shared:WaitForChild("Config"):WaitForChild("Keys"))
local Audio = require(script.Parent:WaitForChild("Audio"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Anims = require(Shared:WaitForChild("Anims"))
local Action = require(Client:WaitForChild("Action"))
local CombatFx = require(Client:WaitForChild("CombatFx"))

local DISABLED = { Stunned = true, Grabbed = true, Ragdolled = true }

local Movement = {}

-- an action that blocks other moves; a slide can be cancelled into a roll or an attack
local function blocking(action: string?): boolean
	return action ~= nil and action ~= "Slide"
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

function Movement.start(character: Model)
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	local leg = character:WaitForChild("Left Leg") :: BasePart
	local set = Anims.forAnimator(animator)
	local dodge = Remotes.get("DodgeRequest")

	local rootToFeet = root.Size.Y / 2 + leg.Size.Y + humanoid.HipHeight
	local baseFov = M.BASE_FOV

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	-- one mover for every move
	local attachment = Instance.new("Attachment")
	attachment.Name = "MoveDrive"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "MoveDrive"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.MaxForce = M.DRIVE_FORCE
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.Enabled = false
	mover.Parent = root

	local sprintHeld, tapSprint, lastW = false, false, 0
	local crouchHeld = false
	local airRolls, jumpsLeft = M.AIR_ROLLS, M.DOUBLE_JUMPS
	local pouncesLeft = M.WALLCLIMB_POUNCES
	local leftGroundAt, jumpedThisAir = 0, false
	local rollReadyAt = 0 -- predicted, server time
	local slideReadyAt = 0
	local slowUntil = 0
	local minVy = 0
	local wallNormal: Vector3? = nil
	local lastWallRunEnd, lastWallNormal = 0, Vector3.zero
	local savedAutoRotate = true
	local fovTarget = baseFov
	local fastFrom = 0 -- os.clock the current sprint started counting toward the ramp (0 = not)

	type Driver = (elapsed: number, dt: number) -> boolean
	local driver: Driver? = nil
	local driverEnd: (() -> ())? = nil
	local driverStart = 0

	local function stopDriver()
		local onEnd = driverEnd
		driver = nil
		driverEnd = nil
		mover.Enabled = false
		if onEnd then
			onEnd()
		end
	end

	local function startDriver(fn: Driver, onEnd: (() -> ())?)
		if driver then
			stopDriver()
		end
		driver = fn
		driverEnd = onEnd
		driverStart = os.clock()
	end

	local function pushPlane(velocity: Vector3)
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		mover.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
		mover.Enabled = true
	end

	local function pushVector(velocity: Vector3)
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		mover.VectorVelocity = velocity
		mover.Enabled = true
	end

	local function grounded(): boolean
		return humanoid.FloorMaterial ~= Enum.Material.Air
	end

	local function forward(): Vector3
		return flat(root.CFrame.LookVector)
	end

	local function face(direction: Vector3)
		if direction ~= Vector3.zero then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
		end
	end

	local function setFaceLock(on: boolean)
		if on then
			savedAutoRotate = humanoid.AutoRotate
			humanoid.AutoRotate = false
			character:SetAttribute("FaceLock", true)
		else
			character:SetAttribute("FaceLock", nil)
			humanoid.AutoRotate = savedAutoRotate
		end
	end

	local function free(): boolean
		local state = character:GetAttribute("CombatState")
		return humanoid.Health > 0 and not (typeof(state) == "string" and DISABLED[state]) and not blocking(Action.get(character))
			and character:GetAttribute("Knocked") ~= true and character:GetAttribute("Carrying") ~= true
	end

	local function sprinting(): boolean
		return (sprintHeld or tapSprint) and humanoid.MoveDirection.Magnitude > 0.05 and not crouchHeld
	end

	local function sound(name: string)
		Audio.play(name, root)
	end

	-- dust from the user's VFX.Dust emitter at the feet (local only)
	local function dust(count: number)
		local vfx = ReplicatedStorage:FindFirstChild("VFX")
		local source = vfx and vfx:FindFirstChild("Dust", true)
		local emitter = source and source:FindFirstChildWhichIsA("ParticleEmitter", true)
		if not emitter then
			return
		end
		local at = Instance.new("Attachment")
		at.WorldPosition = root.Position - Vector3.new(0, rootToFeet - 0.2, 0)
		at.Parent = workspace.Terrain
		local copy = (emitter :: ParticleEmitter):Clone()
		copy.Enabled = false
		copy.Parent = at
		copy:Emit(count)
		Debris:AddItem(at, 3)
	end

	local function endSlide()
		if Action.get(character) == "Slide" and driver then
			stopDriver()
		end
	end

	-- ── roll and air dash ─────────────────────────────────────────────────

	local function roll()
		if not free() then
			return
		end
		local now = workspace:GetServerTimeNow()
		local published = player:GetAttribute("CooldownEnd_Roll")
		if now < math.max(rollReadyAt, if typeof(published) == "number" then published else 0) then
			return
		end
		local onGround = grounded()
		if not onGround and airRolls <= 0 then
			return
		end
		local move = flat(humanoid.MoveDirection)
		local side, direction = "Forward", forward()
		if move ~= Vector3.zero then
			local rel = root.CFrame:VectorToObjectSpace(move)
			if math.abs(rel.Z) >= math.abs(rel.X) then
				side = if rel.Z < 0 then "Forward" else "Backward"
			else
				side = if rel.X > 0 then "Right" else "Left"
			end
			direction = move
		end
		endSlide()
		rollReadyAt = now + M.ROLL_COOLDOWN
		local animation = "Roll" .. side
		-- the dash's own path: on the ground flat; in the air a forward dash follows the camera's
		-- pitch (clamped), so it can climb onto a ledge or dive
		local path = direction
		if onGround then
			dust(8)
		else
			airRolls -= 1
			animation = if side == "Forward" then "AirRoll" else "AirDash" .. side
			if side == "Forward" then
				local pitch = math.clamp(camera.CFrame.LookVector.Y, -M.AIR_DASH_PITCH, M.AIR_DASH_PITCH)
				path = direction * math.sqrt(1 - pitch * pitch) + Vector3.new(0, pitch, 0)
			end
		end
		local duration = if onGround then M.ROLL_DURATION else M.AIR_DASH_TIME + M.AIR_DASH_CARRY
		local release = if onGround then M.ROLL_HOLD else M.AIR_DASH_TIME
		local token = Action.set(character, "Roll")
		set:playFor(animation, if onGround then duration else M.AIR_DASH_TIME + 0.08, 0.05)
		sound(if onGround then "Dash" else "AirDash")
		dodge:FireServer(if onGround then side else "Air", now)
		CombatFx.dash(character, path, not onGround)
		local v0 = root.AssemblyLinearVelocity
		local entry = math.max(0, Vector3.new(v0.X, 0, v0.Z):Dot(direction))
		local released, carrying = false, false
		startDriver(function(elapsed)
			if elapsed >= duration then
				return false
			end
			if released and Action.get(character) ~= nil then
				return false -- an attack or another move took over the slide-out
			end
			if not released and elapsed >= release then
				released = true
				Action.clear(character, token)
			end
			-- the speed every dash eases out to: a run while moving, a walk otherwise
			local exit = if sprinting() then M.RUN_SPEED elseif humanoid.MoveDirection.Magnitude > 0.1 then M.WALK_SPEED else 4
			if onGround then
				local s
				if elapsed < M.ROLL_RAMP then
					s = entry + (M.ROLL_SPEED - entry) * (elapsed / M.ROLL_RAMP)
				elseif elapsed < M.ROLL_HOLD then
					s = M.ROLL_SPEED
				else
					local k = (elapsed - M.ROLL_HOLD) / (duration - M.ROLL_HOLD)
					s = exit + (M.ROLL_SPEED - exit) * (1 - k) * (1 - k)
				end
				pushPlane(direction * s)
			elseif elapsed < M.AIR_DASH_TIME then
				pushVector(path * M.AIR_DASH_SPEED) -- gravity held off for the burst
			else
				-- carry: momentum eases into a run, gravity is back, the stick steers a little
				if not carrying then
					carrying = true
					local v = root.AssemblyLinearVelocity
					root.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, 14), v.Z)
				end
				local want = flat(humanoid.MoveDirection)
				if want ~= Vector3.zero then
					direction = flat(direction:Lerp(want, 0.1))
				end
				local k = (elapsed - M.AIR_DASH_TIME) / M.AIR_DASH_CARRY
				local s = math.max(exit, M.RUN_SPEED) + (M.AIR_DASH_SPEED * 0.75 - math.max(exit, M.RUN_SPEED)) * (1 - k) * (1 - k)
				pushPlane(direction * s)
			end
			return true
		end, function()
			if not released then
				Action.clear(character, token)
			end
		end)
	end

	-- ── slide ───────────────────────────────────────────────────────────────

	local function slide(): boolean
		if not free() or not grounded() or os.clock() < slideReadyAt then
			return false
		end
		local direction = flat(humanoid.MoveDirection)
		if direction == Vector3.zero then
			return false
		end
		slideReadyAt = os.clock() + M.SLIDE_COOLDOWN
		local token = Action.set(character, "Slide")
		set:play("Slide", 0.1)
		dust(10)
		local stopSpray = CombatFx.slide(character, direction)
		startDriver(function(elapsed)
			-- an attack or roll replaces the slide
			if elapsed >= M.SLIDE_DURATION or Action.get(character) ~= "Slide" then
				return false
			end
			local k = elapsed / M.SLIDE_DURATION
			pushPlane(direction * (M.SLIDE_SPEED + (M.SLIDE_END_SPEED - M.SLIDE_SPEED) * k))
			return true
		end, function()
			set:stop("Slide", 0.15)
			stopSpray()
			Action.clear(character, token)
		end)
		return true
	end

	-- ── vault and mantle ────────────────────────────────────────────────────

	local function tryVault(): boolean
		if not grounded() or not free() then
			return false
		end
		local fwd = forward()
		if flat(humanoid.MoveDirection):Dot(fwd) < 0.5 then
			return false
		end
		local feet = root.Position.Y - rootToFeet
		local low = Vector3.new(root.Position.X, feet + M.VAULT_PROBE_HEIGHT, root.Position.Z)
		local wallFace = workspace:Raycast(low, fwd * M.VAULT_REACH, params)
		if not wallFace or math.abs(wallFace.Normal.Y) > 0.3 then
			return false
		end
		-- too tall to vault if the path is blocked above the vault height too
		local highY = feet + M.VAULT_MAX_HEIGHT + 0.5
		if workspace:Raycast(Vector3.new(low.X, highY, low.Z), fwd * (wallFace.Distance + 1.5), params) then
			return false
		end
		local over = wallFace.Position + fwd * 0.75
		local top = workspace:Raycast(Vector3.new(over.X, highY, over.Z), Vector3.new(0, -(M.VAULT_MAX_HEIGHT + 0.5), 0), params)
		if not top or top.Normal.Y < 0.7 then
			return false
		end
		local height = top.Position.Y - feet
		if height < M.VAULT_MIN_HEIGHT or height > M.VAULT_MAX_HEIGHT then
			return false
		end
		endSlide()
		local token = Action.set(character, "Vault")
		set:playFor("Vault", M.VAULT_DURATION, 0.05)
		dust(6)
		local rise = math.sqrt(2 * workspace.Gravity * (height + M.VAULT_CLEARANCE))
		root.AssemblyLinearVelocity = fwd * M.VAULT_FORWARD_SPEED + Vector3.new(0, rise, 0)
		startDriver(function(elapsed)
			if elapsed >= M.VAULT_DURATION then
				return false
			end
			pushPlane(fwd * M.VAULT_FORWARD_SPEED)
			return true
		end, function()
			Action.clear(character, token)
		end)
		return true
	end

	local function tryMantle(): boolean
		if grounded() or not free() then
			return false
		end
		local chest = root.Position + Vector3.new(0, 0.5, 0)
		local wall = workspace:Raycast(chest, forward() * M.LEDGE_CHECK_DIST, params)
		if not wall or math.abs(wall.Normal.Y) > 0.3 then
			return false
		end
		local into = -flat(wall.Normal)
		local fromY = root.Position.Y + 1.5 + M.LEDGE_REACH_UP
		-- the wall must end below reach height, and there must be a floor on top of it
		if workspace:Raycast(Vector3.new(chest.X, fromY, chest.Z), into * (wall.Distance + 1), params) then
			return false
		end
		local over = wall.Position + into * 0.75
		local top = workspace:Raycast(Vector3.new(over.X, fromY, over.Z), Vector3.new(0, -(fromY - chest.Y + 2), 0), params)
		if not top or top.Normal.Y < 0.7 then
			return false
		end
		if workspace:Raycast(top.Position + Vector3.new(0, 0.1, 0), Vector3.new(0, 5, 0), params) then
			return false -- no headroom on the ledge
		end
		local targetY = top.Position.Y + rootToFeet + 0.2
		local name = if top.Position.Y - root.Position.Y > M.LEDGE_HIGH then "LedgeClimb" else "ClimbUp"
		local token = Action.set(character, "Mantle")
		set:playFor(name, M.MANTLE_MAX_TIME * 0.6, 0.05)
		local overAt: number? = nil
		startDriver(function(elapsed)
			if elapsed >= M.MANTLE_MAX_TIME then
				return false
			end
			face(into)
			if not overAt then
				if root.Position.Y >= targetY then
					overAt = elapsed
				end
				pushVector(Vector3.new(0, M.MANTLE_RISE_SPEED, 0) + into)
			elseif elapsed - overAt >= M.MANTLE_OVER_TIME then
				return false
			else
				pushVector(into * M.MANTLE_FORWARD_SPEED + Vector3.new(0, 2, 0))
			end
			return true
		end, function()
			Action.clear(character, token)
		end)
		return true
	end

	-- ── walls ───────────────────────────────────────────────────────────────

	local function wallJump()
		local normal = wallNormal or -forward()
		local along = flat(root.CFrame.LookVector - normal * root.CFrame.LookVector:Dot(normal))
		local running = Action.get(character) == "WallRun"
		stopDriver()
		jumpsLeft = M.DOUBLE_JUMPS
		local token = Action.set(character, "WallJump")
		set:playFor("WallJump", M.WALLJUMP_LOCK, 0.05)
		sound("Jump")
		CombatFx.jump(character, normal)
		local push = normal * M.WALLJUMP_OUT + (if running then along * M.WALLRUN_SPEED else Vector3.zero)
		root.AssemblyLinearVelocity = push + Vector3.new(0, M.WALLJUMP_UP, 0)
		startDriver(function(elapsed)
			if elapsed >= M.WALLJUMP_LOCK then
				return false
			end
			pushPlane(push)
			return true
		end, function()
			Action.clear(character, token)
		end)
	end

	local function wallAhead(): RaycastResult?
		local hit = workspace:Raycast(root.Position + Vector3.new(0, 0.5, 0), forward() * M.WALLCLIMB_DIST, params)
		return if hit and math.abs(hit.Normal.Y) < 0.3 then hit else nil
	end

	-- One pounce up the wall: a burst that eases out, then a cling that slides slowly. Space during the
	-- cling pounces again (airJump); out of pounces, or with S held, Space jumps off instead.
	local function startWallClimb(hit: RaycastResult): boolean
		if pouncesLeft <= 0 then
			return false
		end
		local again = Action.get(character) == "WallClimb"
		if not again and not free() then
			return false
		end
		pouncesLeft -= 1
		if again then
			stopDriver() -- the cling of the last pounce ends here
		end
		wallNormal = flat(hit.Normal)
		local token = Action.set(character, "WallClimb")
		setFaceLock(true)
		local track = set:play("WallClimb", 0.08)
		if track then
			track:AdjustSpeed(2.6)
		end
		local normal = wallNormal :: Vector3
		CombatFx.wallGrab(character, normal)
		CombatFx.wallStep(character, normal)
		sound("WallClimb")
		local topped, clinging = false, false
		startDriver(function(elapsed)
			local n = wallNormal
			if not n or UserInputService:IsKeyDown(Keys.Crouch) then
				return false -- let go
			end
			local into = -n
			local chest = workspace:Raycast(root.Position + Vector3.new(0, 0.5, 0), into * (M.WALLCLIMB_DIST + 0.6), params)
			if not chest or math.abs(chest.Normal.Y) > 0.3 then
				topped = not clinging -- the wall ended under us mid-pounce: over the top
				return false
			end
			wallNormal = flat(chest.Normal)
			face(into)
			if elapsed < M.WALLCLIMB_POUNCE_TIME then
				-- the pounce: fast at first, easing out, hugging the wall
				local k = elapsed / M.WALLCLIMB_POUNCE_TIME
				local head = workspace:Raycast(root.Position + Vector3.new(0, 2, 0), into * (M.WALLCLIMB_DIST + 0.6), params)
				if not head then
					topped = true -- the top is just above: mantle onto it
					return false
				end
				pushVector(Vector3.new(0, M.WALLCLIMB_POUNCE_SPEED * (1 - k * k), 0) + into * M.WALLCLIMB_STICK)
				return true
			end
			if not clinging then
				clinging = true
				if track then
					track:AdjustSpeed(0) -- hold the grip
				end
			end
			if elapsed >= M.WALLCLIMB_POUNCE_TIME + M.WALLCLIMB_CLING or grounded() then
				return false -- slipped off
			end
			pushVector(Vector3.new(0, -M.WALLCLIMB_SLIDE, 0) + into * M.WALLCLIMB_STICK)
			return true
		end, function()
			set:stop("WallClimb", 0.15)
			setFaceLock(false)
			wallNormal = nil
			Action.clear(character, token)
			if topped then
				tryMantle()
			end
		end)
		return true
	end

	-- +1 holding D, -1 holding A, 0 neither (or both)
	local function sideKey(): number
		local d = UserInputService:IsKeyDown(Enum.KeyCode.D)
		local a = UserInputService:IsKeyDown(Enum.KeyCode.A)
		return if d and not a then 1 elseif a and not d then -1 else 0
	end

	-- the easy start: a wall ahead, diagonally ahead toward the held side, or (in the air) beside you
	local function easyWall(side: number, airborne: boolean): RaycastResult?
		local look = forward()
		local right = flat(root.CFrame.RightVector)
		local probes = { look, flat(look + right * side) }
		if airborne then
			table.insert(probes, right * side)
		end
		for _, dir in probes do
			local hit = workspace:Raycast(root.Position, dir * M.WALLRUN_EASY_REACH, params)
			if hit and math.abs(hit.Normal.Y) < 0.3 then
				return hit
			end
		end
		return nil
	end

	-- The wall to run along and the direction to run, or nil. Holding W + A/D at a wall you look at
	-- runs toward that side with no speed needed; otherwise the classic start: a wall alongside
	-- while moving fast in the air.
	local function wallRunStart(onGround: boolean): (Vector3?, Vector3, boolean)
		local look = forward()
		local side = sideKey()
		if side ~= 0 and (not onGround or sprinting()) then
			local hit = easyWall(side, not onGround)
			local n = if hit then flat(hit.Normal) else Vector3.zero
			if hit and n:Dot(lastWallNormal) < 0.9 then
				-- the way W + A/D points, with the part into the wall taken out: looking at the wall
				-- that runs toward the held side, with the wall beside you it runs forward
				local wish = look + flat(root.CFrame.RightVector) * side
				local along = flat(wish - n * wish:Dot(n))
				if along == Vector3.zero then
					along = flat(n:Cross(Vector3.yAxis)) * side
				end
				return n, along, true
			end
		end
		if onGround then
			return nil, Vector3.zero, false
		end
		local velocity = root.AssemblyLinearVelocity
		if Vector3.new(velocity.X, 0, velocity.Z).Magnitude < M.WALLRUN_MIN_SPEED then
			return nil, Vector3.zero, false
		end
		for _, s in { -1, 1 } do
			local hit = workspace:Raycast(root.Position, flat(root.CFrame.RightVector) * s * M.WALLRUN_DIST, params)
			local n = if hit then flat(hit.Normal) else Vector3.zero
			if hit and math.abs(hit.Normal.Y) < 0.3 and math.abs(n:Dot(look)) < 0.5 and n:Dot(lastWallNormal) < 0.9 then
				return n, flat(look - n * look:Dot(n)), false
			end
		end
		return nil, Vector3.zero, false
	end

	local function tryWallRun()
		local onGround = grounded()
		if Action.get(character) ~= nil or not free() then
			return
		end
		if os.clock() - lastWallRunEnd < M.WALLRUN_COOLDOWN or not UserInputService:IsKeyDown(Enum.KeyCode.W) then
			return
		end
		local normal, along, easy = wallRunStart(onGround)
		if not normal or along == Vector3.zero then
			return
		end
		if onGround then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X, M.WALLRUN_GROUND_HOP, v.Z)
		end
		local runTime = if easy then M.WALLRUN_EASY_TIME else M.WALLRUN_TIME
		local reach = if easy then M.WALLRUN_EASY_REACH else M.WALLRUN_DIST
		-- the wall stands behind its normal, on the run's right or left
		local wallOnRight = (-normal):Dot(flat(along:Cross(Vector3.yAxis))) > 0
		wallNormal = normal
		jumpsLeft = M.DOUBLE_JUMPS
		local token = Action.set(character, "WallRun")
		setFaceLock(true)
		local animation = if wallOnRight then "WallRunRight" else "WallRunLeft"
		set:play(animation, 0.1)
		CombatFx.wallGrab(character, normal)
		sound("WallClimb")
		local stepAt = os.clock() + 0.1
		startDriver(function(elapsed)
			local n = wallNormal
			-- a run started from the ground gets a moment to leave it
			if not n or elapsed >= runTime or (grounded() and elapsed > 0.2) or not UserInputService:IsKeyDown(Enum.KeyCode.W) then
				return false
			end
			-- an easy start may begin a little further out: the same reach, and a quick pull to the wall
			local probe = workspace:Raycast(root.Position, -n * (reach + 0.6), params)
			if not probe or math.abs(probe.Normal.Y) > 0.3 then
				return false
			end
			n = flat(probe.Normal)
			wallNormal = n
			along = flat(along - n * along:Dot(n))
			local k = elapsed / runTime
			local vy = M.WALLRUN_LIFT + (M.WALLRUN_SINK - M.WALLRUN_LIFT) * k
			local stick = M.WALLCLIMB_STICK + math.max(0, probe.Distance - 1.8) * 8
			face(along)
			pushVector(along * M.WALLRUN_SPEED + Vector3.new(0, vy, 0) - n * stick)
			-- feet slapping the wall: a dust puff every couple of strides
			if os.clock() >= stepAt then
				stepAt = os.clock() + 0.12
				CombatFx.wallStep(character, n, true)
			end
			return true
		end, function()
			set:stop(animation, 0.15)
			setFaceLock(false)
			lastWallRunEnd = os.clock()
			lastWallNormal = wallNormal or Vector3.zero
			wallNormal = nil
			Action.clear(character, token)
		end)
	end

	-- ── jumps ───────────────────────────────────────────────────────────────

	local function coyoteJump(): boolean
		if jumpedThisAir or os.clock() - leftGroundAt > M.COYOTE_TIME or not free() then
			return false
		end
		jumpedThisAir = true
		local v = root.AssemblyLinearVelocity
		local power = if humanoid.UseJumpPower then humanoid.JumpPower else math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
		root.AssemblyLinearVelocity = Vector3.new(v.X, power, v.Z)
		set:play("Jump", 0.1)
		return true
	end

	local function doubleJump()
		if jumpsLeft <= 0 or not free() or os.clock() - leftGroundAt < M.DOUBLE_JUMP_DELAY then
			return
		end
		jumpsLeft -= 1
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, math.sqrt(2 * workspace.Gravity * M.DOUBLE_JUMP_HEIGHT), v.Z)
		Action.set(character, "DoubleJump", M.DOUBLE_JUMP_DURATION)
		set:playFor("DoubleJump", M.DOUBLE_JUMP_DURATION, 0.05)
		sound("Jump")
		CombatFx.jump(character)
	end

	local function airJump()
		local action = Action.get(character)
		if action == "WallClimb" then
			-- clinging: pounce on up the wall, or jump off it with S held / out of pounces
			local wall = wallAhead()
			if UserInputService:IsKeyDown(Enum.KeyCode.S) or not (wall and startWallClimb(wall)) then
				wallJump()
			end
		elseif action == "WallRun" then
			wallJump()
		elseif coyoteJump() or tryMantle() then
			return
		else
			local wall = wallAhead()
			if not (wall and startWallClimb(wall)) then
				doubleJump()
			end
		end
	end

	-- ── input ───────────────────────────────────────────────────────────────

	local connections: { RBXScriptConnection } = {}
	table.insert(connections, Remotes.get("CombatResult").OnClientEvent:Connect(function(kind, _, target)
		if kind == "PerfectDodge" and target == character then rollReadyAt = 0 end
	end))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Keys.Sprint then
			sprintHeld = true
		elseif key == Keys.SprintTap then
			if os.clock() - lastW < M.SPRINT_DOUBLE_TAP then
				tapSprint = true
			end
			lastW = os.clock()
		elseif key == Keys.Crouch then
			if sprinting() and grounded() then
				slide()
			end
			crouchHeld = true
		elseif key == Keys.Roll then
			roll()
		elseif key == Keys.Jump then
			if grounded() then
				tryVault()
			else
				airJump()
			end
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		local key = input.KeyCode
		if key == Keys.Sprint then
			sprintHeld = false
		elseif key == Keys.SprintTap then
			tapSprint = false
		elseif key == Keys.Crouch then
			crouchHeld = false
		end
	end))

	table.insert(connections, humanoid.StateChanged:Connect(function(old, new)
		if new == Enum.HumanoidStateType.Jumping then
			jumpedThisAir = true
			leftGroundAt = os.clock()
			endSlide() -- jumping out of a slide keeps its momentum
		elseif new == Enum.HumanoidStateType.Freefall and old ~= Enum.HumanoidStateType.Jumping then
			leftGroundAt = os.clock() -- walked off a ledge: coyote time starts
		elseif new == Enum.HumanoidStateType.Landed then
			airRolls = M.AIR_ROLLS
			jumpsLeft = M.DOUBLE_JUMPS
			pouncesLeft = M.WALLCLIMB_POUNCES
			jumpedThisAir = false
			lastWallNormal = Vector3.zero
			local impact = -minVy
			if impact >= M.HARD_LAND_SPEED then
				slowUntil = os.clock() + M.HARD_LAND_SLOW
			end
			if impact >= M.DUST_LAND_SPEED then
				dust(12)
				CombatFx.land(character, impact)
			end
			minVy = 0
		end
	end))

	-- a stun, grab or ragdoll ends whatever move was running
	table.insert(connections, character:GetAttributeChangedSignal("CombatState"):Connect(function()
		local state = character:GetAttribute("CombatState")
		if typeof(state) == "string" and DISABLED[state] and driver then
			stopDriver()
		end
	end))

	-- ── per frame: speeds, the active move, wall-run checks, FOV ───────────

	table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		local fn = driver
		if fn and not fn(os.clock() - driverStart, dt) and driver == fn then
			stopDriver()
		end
		local onGround = grounded()
		if not onGround then
			minVy = math.min(minVy, root.AssemblyLinearVelocity.Y)
			tryWallRun()
		elseif sprinting() and sideKey() ~= 0 then
			tryWallRun() -- W + A/D at a wall you look at, straight from a sprint
		end
		local action = Action.get(character)
		local crouching = crouchHeld and onGround and action ~= "Slide"
		local running = sprinting() and not crouching
		local speed = M.WALK_SPEED
		local state = character:GetAttribute("CombatState")
		local carrying = character:GetAttribute("Carrying") == true
		-- the sprint ramp: counts while sprinting with nothing else going on, starts on the ground
		local fast = 0
		if running and not carrying and (action == nil or action == "Slide") and state ~= "Stunned" then
			if fastFrom == 0 and onGround then
				fastFrom = os.clock()
			end
			if fastFrom > 0 then
				fast = math.clamp((os.clock() - fastFrom - M.FAST_RUN_DELAY) / M.FAST_RUN_RAMP, 0, 1)
			end
		elseif not running or (action ~= nil and action ~= "Roll") then
			fastFrom = 0
		end
		if state == "Stunned" then
			speed = C.STUN_WALK_SPEED
		elseif action == "Grip" then
			speed = 0
		elseif character:GetAttribute("Blocking") == true then
			speed = C.BLOCK_WALK_SPEED
		elseif action == "Attack" or action == "Uppercut" or action == "Grab" or action == "Relic" then
			speed = C.ATTACK_WALK_SPEED
		elseif carrying then
			speed = C.CARRY_WALK_SPEED
		elseif crouching then
			speed = M.CROUCH_SPEED
		elseif running then
			speed = M.RUN_SPEED + (M.FAST_RUN_SPEED - M.RUN_SPEED) * fast
		end
		if os.clock() < slowUntil then
			speed = math.min(speed, M.HARD_LAND_SPEED_CAP)
		end
		humanoid.WalkSpeed = speed
		if character:GetAttribute("Crouching") ~= crouching then
			character:SetAttribute("Crouching", crouching)
		end
		local sprintShown = running and speed >= M.RUN_SPEED
		if character:GetAttribute("Sprinting") ~= sprintShown then
			character:SetAttribute("Sprinting", sprintShown)
		end
		local fov = if sprintShown and onGround then M.SPRINT_FOV + (M.FAST_RUN_FOV - M.SPRINT_FOV) * fast else baseFov
		if math.abs(fov - fovTarget) >= 1 or (fov == baseFov and fovTarget ~= baseFov) then
			fovTarget = fov
			TweenService:Create(camera, TweenInfo.new(M.FOV_TWEEN), { FieldOfView = fov }):Play()
		end
	end))

	humanoid.Died:Once(function()
		if driver then
			stopDriver()
		end
		for _, c in connections do
			c:Disconnect()
		end
		camera.FieldOfView = baseFov
	end)
end

return Movement
