--!strict
-- Predict combat animations and send timestamped input to CombatService.
-- Use Shared.Config.Keys for bindings and mirror server combo timing.
-- Apply CombatResult reactions and reset rejected actions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = ReplicatedStorage:WaitForChild("Client")
local C = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local Keys = require(Shared:WaitForChild("Config"):WaitForChild("Keys"))
local Sounds = require(Shared:WaitForChild("Config"):WaitForChild("Sounds"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Anims = require(Shared:WaitForChild("Anims"))
local Action = require(Client:WaitForChild("Action"))

local Audio = require(Client:WaitForChild("Audio"))
local CombatController = {}

-- movement actions that rule out attacking or blocking (a slide can be cancelled into either)
local MOVES = { Roll = true, Vault = true, Mantle = true, WallClimb = true, WallRun = true, WallJump = true, DoubleJump = true, Glide = true, Skate = true }
local ATTACKS = { Attack = true, Uppercut = true, Grab = true, Relic = true, Grip = true }
local DUMMY_TAG = "TrainingDummy"
local DISABLED = { Stunned = true, Grabbed = true, Ragdolled = true }
local THROW_ANIMS = { Up = "ThrowUp", Left = "ThrowLeft", Right = "ThrowRight", Down = "Bury" }
local GRAB_KEYS = { [Enum.KeyCode.W] = "Up", [Enum.KeyCode.A] = "Left", [Enum.KeyCode.S] = "Down", [Enum.KeyCode.D] = "Right" }

function CombatController.start(character: Model)
	local player = Players.LocalPlayer
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = humanoid:WaitForChild("Animator") :: Animator
	local set = Anims.forAnimator(animator)
	local remotes = {
		attack = Remotes.get("AttackRequest"),
		aerial = Remotes.get("AerialRequest"),
		uppercut = Remotes.get("UppercutRequest"),
		feint = Remotes.get("FeintRequest"),
		grab = Remotes.get("GrabRequest"),
		blockStart = Remotes.get("BlockStart"),
		blockEnd = Remotes.get("BlockEnd"),
		crit = Remotes.get("CritRequest"),
		grip = Remotes.get("GripRequest"),
		carry = Remotes.get("CarryRequest"),
		result = Remotes.get("CombatResult"),
	}

	local combo, chainUntil, nextAttackAt = 0, 0, 0
	local pendingHitAt = 0 -- when the local swing lands (feint window)
	local uppercutReadyAt, aerialReadyAt, feintReadyAt, grabReadyAt, critReadyAt = 0, 0, 0, 0, 0 -- predicted, server time
	local blocking, grabHeld = false, false
	local swing: any = nil
	local landedAt, landedCombo = 0, 0
	local bufferedUntil = 0
	local swingName: string? = nil
	local swingToken: {}? = nil -- the predicted swing's Action, cleared at once if the server refuses it

	local function serverNow(): number
		return workspace:GetServerTimeNow()
	end

	local function state(): string
		local s = character:GetAttribute("CombatState")
		return if typeof(s) == "string" then s else "Idle"
	end

	local function free(): boolean
		local action = Action.get(character)
		return humanoid.Health > 0 and not DISABLED[state()] and not (action and (MOVES[action] or ATTACKS[action]))
			and character:GetAttribute("Knocked") ~= true and character:GetAttribute("Carrying") ~= true
	end

	local function ready(key: string, predicted: number): boolean
		local published = player:GetAttribute("CooldownEnd_" .. key)
		return serverNow() >= math.max(predicted, if typeof(published) == "number" then published else 0)
	end

	local function sound(name: string)
		Audio.play(name, root)
	end

	local function startSwing(name: string, length: number, windup: number, action: string, cue: string?)
		swingToken = Action.set(character, action, length)
		if swing then
			swing:Stop(0.05)
		end
		swing = set:playFor(name, length, 0.05)
		swingName = name
		pendingHitAt = serverNow() + windup
		-- the broom and the umbrella swing heavier than fists (EXPED keeps a swing family per weapon)
		local relic = player:GetAttribute("Relic")
		sound(cue or if relic == "Umbrella" or relic == "PushBroom" then "SwingWeapon" else "Swing")
	end

	-- a short step forward (M1s, the crit's lunge, a slide uppercut); none into a wall
	local function lunge(speed: number, duration: number, along: Vector3?)
		local direction = (along or root.CFrame.LookVector) * Vector3.new(1, 0, 1)
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { character }
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		if direction.Magnitude <= 0.01 or workspace:Raycast(root.Position, direction.Unit * 2, params) then
			return
		end
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local step = Instance.new("LinearVelocity")
		step.Attachment0 = attachment
		step.MaxForce = C.KNOCKBACK_FORCE
		step.VectorVelocity = direction.Unit * speed + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		step.Parent = root
		Debris:AddItem(step, duration)
		Debris:AddItem(attachment, duration)
	end

	-- ── air combo: this fighter floats with its launched target ─────────────
	local airHold: LinearVelocity? = nil
	local airUntil, riseUntil = 0, 0 -- os.clock

	local function stopAirHold()
		airUntil, riseUntil = 0, 0
		if airHold then
			local att = airHold.Attachment0
			airHold:Destroy()
			if att then
				att:Destroy()
			end
			airHold = nil
		end
	end

	-- Y velocity only, so lunges and pushes still move us sideways
	local function holdAir(vy: number, rise: number, untilClock: number)
		if not airHold then
			local att = Instance.new("Attachment")
			att.Name = "AirHoldAtt"
			att.Parent = root
			local m = Instance.new("LinearVelocity")
			m.Name = "AirHold"
			m.Attachment0 = att
			m.RelativeTo = Enum.ActuatorRelativeTo.World
			m.ForceLimitMode = Enum.ForceLimitMode.PerAxis
			m.MaxAxesForce = Vector3.new(0, C.KNOCKBACK_FORCE, 0)
			m.Parent = root
			airHold = m
		end
		local held = airHold :: LinearVelocity
		held.VectorVelocity = Vector3.new(0, vy, 0)
		riseUntil = os.clock() + rise
		airUntil = math.max(airUntil, untilClock)
	end

	local function airCombo(): boolean
		return airHold ~= nil and os.clock() < airUntil
	end

	local function endBlock()
		if not blocking then
			return
		end
		blocking = false
		character:SetAttribute("Blocking", nil)
		set:stop("Block", 0.12)
		remotes.blockEnd:FireServer()
	end

	local function startBlock()
		if blocking or not free() then
			return
		end
		blocking = true
		character:SetAttribute("Blocking", true)
		set:play("Block", 0.08)
		remotes.blockStart:FireServer(serverNow())
	end

	-- ── attacks ─────────────────────────────────────────────────────────────

	local function aerial()
		local now = serverNow()
		if now < nextAttackAt or not ready("Aerial", aerialReadyAt) then
			return
		end
		aerialReadyAt = now + C.AERIAL_COOLDOWN
		combo, chainUntil, nextAttackAt = 0, 0, now + C.AERIAL_LENGTH
		startSwing("AerialSlam", C.AERIAL_LENGTH, C.AERIAL_WINDUP, "Attack")
		remotes.aerial:FireServer(now)
	end

	local function m1()
		local remaining = nextAttackAt - serverNow()
		if not blocking and Action.get(character) == "Attack" and remaining > 0 and remaining <= C.INPUT_BUFFER then
			bufferedUntil = serverNow() + C.INPUT_BUFFER
			return
		end
		if blocking or not free() then
			return
		end
		if humanoid.FloorMaterial == Enum.Material.Air and not airCombo() then
			aerial()
			return
		end
		local now = serverNow()
		if now < nextAttackAt then
			return
		end
		local maxCombo = if player:GetAttribute("FinalUpgradeUnlocked") == true then C.COMBO_LENGTH else C.COMBO_LENGTH - 1
		local index = if combo > 0 and now <= chainUntil + C.LATENCY_FORGIVENESS then combo + 1 else 1
		if index > maxCombo then
			index = 1
		end
		local hit = C.M1_HITS[index]
		if index >= maxCombo then
			combo, chainUntil, nextAttackAt = 0, 0, now + C.COMBO_RESET
		else
			combo, chainUntil, nextAttackAt = index, now + hit.length + C.COMBO_WINDOW, now + hit.length
		end
		startSwing("M1_" .. index, hit.length, hit.windup, "Attack")
		remotes.attack:FireServer(index, now)
		lunge(C.M1_LUNGE, C.M1_LUNGE_TIME)
	end

	local function uppercut()
		local now = serverNow()
		local cancel = landedCombo >= C.CANCEL_MIN_HIT and now - landedAt <= C.CANCEL_WINDOW
			and Action.get(character) == "Attack" and not DISABLED[state()] and humanoid.Health > 0
		if blocking or (not free() and not cancel) then return end
		if (now < nextAttackAt and not cancel) or not ready("Uppercut", uppercutReadyAt) then
			return
		end
		local length = C.UPPERCUT_WINDUP + C.UPPERCUT_RECOVERY
		-- out of a slide (Ctrl is already down): the slide's momentum carries into the uppercut
		local sliding = Action.get(character) == "Slide"
		local slideDir = root.AssemblyLinearVelocity
		landedCombo, bufferedUntil = 0, 0
		uppercutReadyAt = now + C.UPPERCUT_COOLDOWN
		combo, chainUntil, nextAttackAt = 0, 0, now + length
		startSwing("Uppercut", length, C.UPPERCUT_WINDUP, "Uppercut")
		remotes.uppercut:FireServer(now)
		if sliding then
			lunge(C.UPPERCUT_SLIDE_LUNGE, C.UPPERCUT_SLIDE_LUNGE_TIME, slideDir)
		end
	end

	local function crit()
		if blocking or not free() then
			return
		end
		local now = serverNow()
		if now < nextAttackAt or not ready("Crit", critReadyAt) then
			return
		end
		critReadyAt = now + C.CRIT_COOLDOWN
		combo, chainUntil, nextAttackAt = 0, 0, now + C.CRIT_LENGTH
		landedCombo, bufferedUntil = 0, 0
		startSwing("Crit", C.CRIT_LENGTH, C.CRIT_WINDUP, "Attack", "CritWindup")
		remotes.crit:FireServer(now)
		-- the lunge lands with the punch; a feint or an interrupt cancels it
		local token = swingToken
		task.delay(math.max(0, C.CRIT_WINDUP - C.CRIT_LUNGE_TIME - 0.02), function()
			if swingToken == token and pendingHitAt > 0 and Action.get(character) == "Attack" then
				lunge(C.CRIT_LUNGE, C.CRIT_LUNGE_TIME)
			end
		end)
	end

	-- ── knocked bodies: grip and carry ──────────────────────────────────────

	local function knockedNear(range: number): Model?
		local best: Model? = nil
		local bestDistance = range
		local function consider(model: Instance?)
			if not model or model == character or not model:IsA("Model") then
				return
			end
			if model:GetAttribute("Knocked") ~= true or model:GetAttribute("Carried") == true then
				return
			end
			local r = model:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				local d = (r.Position - root.Position).Magnitude
				if d < bestDistance then
					best, bestDistance = model, d
				end
			end
		end
		for _, p in Players:GetPlayers() do
			consider(p.Character)
		end
		for _, m in CollectionService:GetTagged(DUMMY_TAG) do
			consider(m)
		end
		return best
	end

	local function grip()
		if Action.get(character) == "Grip" then
			remotes.grip:FireServer(nil) -- B again: let go
			return
		end
		if not free() then
			return
		end
		local target = knockedNear(C.GRIP_RANGE + 1)
		if target then
			remotes.grip:FireServer(target)
		end
	end

	local function carry()
		if character:GetAttribute("Carrying") == true then
			remotes.carry:FireServer(nil)
			return
		end
		if not free() then
			return
		end
		local target = knockedNear(C.CARRY_RANGE + 1)
		if target then
			remotes.carry:FireServer(target)
		end
	end

	local function feint()
		local now = serverNow()
		if now >= pendingHitAt or now < feintReadyAt or not swing then
			return
		end
		feintReadyAt = now + C.FEINT_COOLDOWN
		pendingHitAt = 0
		combo, chainUntil, nextAttackAt = 0, 0, now + C.FEINT_RECOVERY
		swing:Stop(0.1)
		swing = nil
		Action.set(character, "Attack", C.FEINT_RECOVERY)
		sound("Feint")
		remotes.feint:FireServer()
	end

	local function grab(direction: string)
		if blocking or not free() then
			return
		end
		local now = serverNow()
		if now < nextAttackAt or not ready("Grab", grabReadyAt) then
			return
		end
		local release = (C.THROW_RELEASE :: { [string]: number })[direction]
		grabReadyAt = now + C.GRAB_COOLDOWN
		combo, chainUntil = 0, 0
		nextAttackAt = now + C.GRAB_STARTUP + release + C.THROW_RECOVERY
		startSwing("Grab", C.GRAB_STARTUP + release + C.THROW_RECOVERY, C.GRAB_STARTUP, "Grab")
		remotes.grab:FireServer(direction, now)
	end

	-- ── input ───────────────────────────────────────────────────────────────

	local connections: { RBXScriptConnection } = {}
	table.insert(connections, RunService.Heartbeat:Connect(function()
		if bufferedUntil > 0 and serverNow() >= nextAttackAt and free() then
			local valid = serverNow() <= bufferedUntil
			bufferedUntil = 0
			if valid then m1() end
		end
		if airHold then
			local clock = os.clock()
			if clock >= airUntil then
				stopAirHold()
			elseif clock >= riseUntil and airHold.VectorVelocity.Y ~= 0 then
				airHold.VectorVelocity = Vector3.zero
			end
		end
	end))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Keys.Attack then
			if UserInputService:IsKeyDown(Keys.Crouch) then
				uppercut()
			else
				m1()
			end
		elseif input.UserInputType == Keys.Feint then
			feint()
		elseif input.KeyCode == Keys.Crit then
			crit()
		elseif input.KeyCode == Keys.Grip then
			grip()
		elseif input.KeyCode == Keys.Carry then
			carry()
		elseif input.KeyCode == Keys.Block then
			startBlock()
		elseif input.KeyCode == Keys.Grab then
			grabHeld = true
		elseif grabHeld and GRAB_KEYS[input.KeyCode] then
			grab(GRAB_KEYS[input.KeyCode])
		end
	end))

	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Keys.Block then
			endBlock()
		elseif input.KeyCode == Keys.Grab then
			grabHeld = false
		end
	end))

	-- a roll or a wall move drops the guard; so does a stun, grab or ragdoll
	table.insert(connections, character:GetAttributeChangedSignal("Action"):Connect(function()
		local action = Action.get(character)
		if action and MOVES[action] then
			endBlock()
			stopAirHold()
		end
	end))
	table.insert(connections, character:GetAttributeChangedSignal("CombatState"):Connect(function()
		if DISABLED[state()] then
			endBlock()
			stopAirHold()
			pendingHitAt = 0
			landedCombo, bufferedUntil = 0, 0
			if swing then
				swing:Stop(0.1)
				swing = nil
			end
		end
	end))

	-- the server owns a ragdolled body; this keeps the local Humanoid from fighting it
	table.insert(connections, character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		if character:GetAttribute("Ragdolled") == true then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end))

	-- ── results: reactions on this character ───────────────────────────────

	local function hitstop(heavy: boolean)
		local track = swing
		if track and track.IsPlaying then
			local speed = track.Speed
			track:AdjustSpeed(0)
			task.delay(if heavy then C.HEAVY_HITSTOP else C.HITSTOP, function()
				if track.IsPlaying then
					track:AdjustSpeed(speed)
				end
			end)
		end
	end

	table.insert(connections, remotes.result.OnClientEvent:Connect(function(kind: string, attacker: Model?, target: Model?, detail: any)
		local index = if typeof(detail) == "number" then math.clamp(detail, 1, 5) else 1
		if attacker == character then
			if kind == "Reject" then
				combo, chainUntil, nextAttackAt, pendingHitAt = 0, 0, 0, 0
				uppercutReadyAt, aerialReadyAt, feintReadyAt, grabReadyAt, critReadyAt = 0, 0, 0, 0, 0
				landedCombo, bufferedUntil = 0, 0
				if swing then
					swing:Stop(0.1)
				end
				if swingToken then
					Action.clear(character, swingToken)
					swingToken = nil
				end
				-- the server may have refused a block this client is showing
				endBlock()
			elseif kind == "Hit" then
				landedAt = serverNow()
				landedCombo = tonumber(string.match(swingName or "", "^M1_(%d)$")) or 0
				hitstop(index == 5)
				if airCombo() then
					airUntil = math.max(airUntil, os.clock() + C.JUGGLE_HOLD + 0.1) -- keep floating with the target
				end
			elseif kind == "Launch" and typeof(detail) == "table" then
				-- go up with the launched target (EXPED air combo)
				local rise = tonumber(detail.rise) or C.LAUNCH_RISE
				local height = tonumber(detail.height) or C.LAUNCH_HEIGHT
				local hold = tonumber(detail.hold) or C.JUGGLE_HOLD
				holdAir(height / math.max(rise, 0.05), rise, os.clock() + rise + hold + 0.1)
			elseif kind == "Spike" then
				task.delay(0.08, stopAirHold)
			elseif kind == "GripStart" then
				local t = if target then target:FindFirstChild("HumanoidRootPart") else nil
				if t and t:IsA("BasePart") then
					local to = (t.Position - root.Position) * Vector3.new(1, 0, 1)
					if to.Magnitude > 0.1 then
						root.CFrame = CFrame.lookAt(root.Position, root.Position + to)
					end
				end
				if swing then
					swing:Stop(0.1)
				end
				swingToken = Action.set(character, "Grip", C.GRIP_TIME)
				swing = set:playFor("Grip", C.GRIP_TIME, 0.1)
				swingName = "Grip"
			elseif kind == "GripCancel" then
				set:stop("Grip", 0.15)
				if swingToken then
					Action.clear(character, swingToken)
					swingToken = nil
				end
			elseif kind == "Carry" then
				set:play("Carry", 0.2)
			elseif kind == "Drop" then
				set:stop("Carry", 0.2)
			elseif kind == "Counter" or kind == "WallSplat" then
				hitstop(true)
			elseif kind == "Parry" then
				set:playFor("Parried", C.PARRY_ATTACKER_STUN, 0.05)
			elseif kind == "GrabConnect" and typeof(detail) == "string" then
				if swing then
					swing:Stop(0.05)
				end
				swing = set:play(THROW_ANIMS[detail] or "ThrowUp", 0.05)
				swingName = "Throw"
			elseif kind == "GrabWhiff" then
				if swing then
					swing:Stop(0.15)
				end
				Action.set(character, "Grab", C.GRAB_WHIFF_RECOVERY)
				nextAttackAt = serverNow() + C.GRAB_WHIFF_RECOVERY
			end
		end
		if target == character then
			if kind == "Carry" then
				set:play("Carried", 0.2)
			elseif kind == "Drop" or kind == "GetUp" then
				set:stop("Carried", 0.2)
			elseif kind == "Knocked" then
				stopAirHold()
				if swing then
					swing:Stop(0.1)
					swing = nil
				end
			elseif kind == "WallSplat" then
				set:playFor("WallSplat", C.WALL_SPLAT_STUN, 0.04)
			elseif kind == "Hit" then
				-- the struck body freezes with the attacker's hitstop
				local reaction = set:play("HitReact" .. index, 0.05)
				if reaction then
					reaction:AdjustSpeed(0)
					task.delay(if index == 5 then C.HEAVY_HITSTOP else C.HITSTOP, function()
						if reaction.IsPlaying then
							reaction:AdjustSpeed(1)
						end
					end)
				end
			elseif kind == "Blocked" then
				set:play("BlockHit" .. ((index - 1) % 3 + 1), 0.05)
			elseif kind == "Parry" then
				set:play("Deflect", 0.05)
			elseif kind == "Break" then
				set:play("GuardBroken", 0.1)
				task.delay(C.POSTURE_BREAK_STUN, function()
					set:stop("GuardBroken", 0.2)
				end)
			elseif kind == "GrabConnect" then
				set:play("Grabbed", 0.1)
			elseif kind == "Throw" or kind == "GrabRelease" then
				set:stop("Grabbed", 0.1)
			end
		end
	end))

	humanoid.Died:Once(function()
		stopAirHold()
		for _, c in connections do
			c:Disconnect()
		end
	end)
end

return CombatController
