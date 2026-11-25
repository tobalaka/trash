--!strict
--[[
	Feedback - what every client sees and hears for each combat result the server announces:
	a highlight flash on the fighter, a particle stack at the contact point (Client/CombatFx: flash,
	wind rings, impact burst, rays, shards, built like EXPED's hits), an impact sound there (through
	Client/Audio, so the mixer's volumes and limits apply), and a camera shake and FOV punch when
	the local player is one of the two fighters.
	2026-10-25: CombatFx replaces the built-in sparkles and the cylinder dust ring; other players'
	dashes ("Dash") are drawn by CombatFx too. Punch effects only play on a landed hit.

	2026-10-26: Counter (gold burst), PerfectDodge (cyan afterimage), WallSplat (dust ring and a
	heavy shake at the wall), FOV punches on heavy results, and the shake runs right after the
	camera scripts so it never fights them. Every exchange involving the local player tells the
	music director (Audio.engage).

	EXPED pass (2026-10-25): CritStart (red warning flash + the fist charging), CritHit (blast and a
	crater), Launch (wind under the attacker too), Spike (a crater where the body lands), Feint
	(EXPED's white feint flash), Knocked / GetUp, the grip's three punches, Executed, Carry / Drop.
	Craters also open under aerial slams and buries. The local fighter's gank buff chimes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local C = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local Audio = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Audio"))
local CombatFx = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("CombatFx"))

type Style = {
	color: Color3?,
	sound: string?,
	heavySound: string?,
	shake: number,
	punch: number?, -- FOV kick in degrees for the local fighters
}

local STYLES: { [string]: Style } = {
	Hit = { color = Color3.fromRGB(255, 255, 255), sound = "Hit", heavySound = "HeavyHit", shake = 0.25 },
	Blocked = { color = Color3.fromRGB(120, 190, 255), sound = "Block", shake = 0.12 },
	Parry = { color = Color3.fromRGB(255, 214, 90), sound = "Parry", shake = 0.35, punch = 4 },
	Break = { color = Color3.fromRGB(255, 140, 60), sound = "Break", shake = 0.45, punch = 5 },
	Dodged = { color = Color3.fromRGB(170, 255, 200), shake = 0 },
	PerfectDodge = { color = Color3.fromRGB(110, 230, 255), sound = "PerfectDodge", shake = 0.1 },
	Counter = { color = Color3.fromRGB(255, 196, 60), sound = "Counter", shake = 0.4, punch = 4 },
	WallSplat = { color = Color3.fromRGB(255, 170, 90), sound = "WallSplat", shake = 0.6, punch = 6 },
	GrabConnect = { sound = "Block", shake = 0.15 },
	Throw = { sound = "Slam", shake = 0.4 },
}
-- results that draw a contact effect (CombatFx.impact kinds)
local IMPACTS = { Hit = true, Blocked = true, Parry = true, Break = true, Counter = true }
local HEAVY_REACTION = 5
local HEAVY_PUNCH = 3 -- FOV kick for heavy hits

local FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PUNCH_IN, PUNCH_OUT = 0.05, 0.25

local Feedback = {}

local function rootOf(model: Model?): BasePart?
	local part = if model then model:FindFirstChild("HumanoidRootPart") else nil
	return if part and part:IsA("BasePart") then part else nil
end

local function flash(model: Model?, color: Color3)
	if not model or not model.Parent then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	TweenService:Create(highlight, FADE, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(highlight, FADE.Time + 0.05)
end

-- a fading copy of the body where it stood (perfect dodges)
local function afterimage(model: Model?, color: Color3)
	if not model then
		return
	end
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" and part.Transparency < 1 then
			local ghost = Instance.new("Part")
			ghost.Anchored = true
			ghost.CanCollide = false
			ghost.CanQuery = false
			ghost.CanTouch = false
			ghost.CastShadow = false
			ghost.Material = Enum.Material.Neon
			ghost.Color = color
			ghost.Transparency = 0.55
			ghost.Size = part.Size
			ghost.CFrame = part.CFrame
			ghost.Parent = workspace.Terrain
			TweenService:Create(ghost, FADE, { Transparency = 1 }):Play()
			Debris:AddItem(ghost, FADE.Time + 0.05)
		end
	end
end

local function burst(kind: string, at: Vector3, dir: Vector3, heavy: boolean, soundName: string?)
	if IMPACTS[kind] then
		CombatFx.impact(kind, at, dir, heavy)
	end
	if soundName then
		Audio.play(soundName, at)
	end
end

local shakeUntil, shakeStrength = 0, 0
local punchUntil, punchStart, punchAmount = 0, 0, 0

local function shake(strength: number)
	if strength <= 0 then
		return
	end
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = os.clock() + 0.08 + strength * 0.4
end

local function punch(degrees: number)
	if degrees <= 0 then
		return
	end
	local clock = os.clock()
	punchAmount = math.max(if clock < punchUntil then punchAmount else 0, degrees)
	punchStart = clock
	punchUntil = clock + PUNCH_IN + PUNCH_OUT
end

-- the EXPED pass's results; true when `kind` was one of them
local function exped(kind: string, attacker: Model?, target: Model?): boolean
	local me = Players.LocalPlayer.Character
	local mine = me ~= nil and (me == attacker or me == target)
	local tr, ar = rootOf(target), rootOf(attacker)
	if kind == "CritStart" then
		CombatFx.mark(attacker, "Crit", C.CRIT_WINDUP)
		CombatFx.critCharge(attacker, C.CRIT_WINDUP)
		if attacker ~= me and ar then
			Audio.play("CritWindup", ar) -- our own plays with the swing
		end
	elseif kind == "CritHit" then
		if tr then
			local dir = if ar then tr.Position - ar.Position else tr.CFrame.LookVector
			CombatFx.critHit(tr.Position, dir)
			CombatFx.crater(tr.Position, 1)
			Audio.play("CritHit", tr.Position)
		end
		if mine then
			shake(0.8)
			punch(7)
		end
	elseif kind == "Spike" then
		if tr then
			-- the body flies down a diagonal (forward along the attacker's facing, and down): the crater
			-- opens where that line meets the ground
			local forward = if ar then ar.CFrame.LookVector * Vector3.new(1, 0, 1) else Vector3.zero
			forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.zero
			local path = forward * C.SPIKE_FORWARD - Vector3.new(0, C.SPIKE_SPEED, 0)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { target :: Model, attacker or target :: Model }
			local hit = workspace:Raycast(tr.Position, path.Unit * 80, params)
			local at = if hit then hit.Position else tr.Position + path * 0.2
			local fall = if hit then hit.Distance else 3
			task.delay(math.clamp(fall / path.Magnitude, 0.03, 0.7), function()
				CombatFx.slam(at + Vector3.new(0, 1, 0))
				CombatFx.crater(at + Vector3.new(0, 1, 0), 1.1)
				Audio.play("Slam", at)
			end)
		end
		if mine then
			shake(0.7)
			punch(6)
		end
	elseif kind == "Launch" then
		if ar then
			CombatFx.launch(ar.Position) -- the attacker goes up too
		end
	elseif kind == "Feint" then
		CombatFx.mark(attacker, "Feint", 0.3)
	elseif kind == "Knocked" then
		CombatFx.knocked(target)
		if tr then
			Audio.play("Knocked", tr)
		end
		if target == me then
			shake(0.5)
		end
	elseif kind == "GetUp" then
		CombatFx.mark(target, "GetUp", 0.6)
		if tr then
			Audio.play("GetUp", tr)
		end
	elseif kind == "GripStart" then
		-- three punches down, on the Grip animation's blows
		for i, at in { 0.5, 0.93, 1.38 } do
			task.delay(at, function()
				local body = rootOf(target)
				if not body or not attacker or attacker:GetAttribute("Gripping") ~= true then
					return
				end
				CombatFx.impact("Hit", body.Position + Vector3.new(0, 0.6, 0), Vector3.new(0, -1, 0), i == 3)
				Audio.play("GripPunch", body.Position)
				if mine then
					shake(0.2 + 0.1 * i)
				end
			end)
		end
	elseif kind == "Executed" then
		CombatFx.execute(target)
		if tr then
			Audio.play("Execute", tr.Position)
		end
		if mine then
			shake(0.9)
			punch(6)
		end
	elseif kind == "Carry" then
		if tr then
			Audio.play("Carry", tr)
		end
	elseif kind == "Drop" then
		if tr then
			Audio.play("Drop", tr)
		end
	elseif kind ~= "GripCancel" then
		return false
	end
	return true
end

function Feedback.start()
	-- right after the camera scripts write the camera, so the offset is never overwritten
	-- and never accumulates
	local applied = 0
	RunService:BindToRenderStep("TRASH_CombatShake", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local clock = os.clock()
		local left = shakeUntil - clock
		if left > 0 then
			local s = shakeStrength * math.min(1, left * 5)
			camera.CFrame *= CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
		else
			shakeStrength = 0
		end
		-- the FOV kick: undo last frame's, then apply this frame's
		local kick = 0
		if clock < punchUntil then
			local t = clock - punchStart
			kick = if t < PUNCH_IN then punchAmount * (t / PUNCH_IN) else punchAmount * (1 - (t - PUNCH_IN) / PUNCH_OUT)
		end
		if kick ~= applied then
			camera.FieldOfView += kick - applied
			applied = kick
		end
	end)

	CombatFx.start()
	require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("KnockScreen")).start()
	-- the anti-gank buff: a chime when it switches on for us
	local function watchGank(character: Model)
		character:GetAttributeChangedSignal("Ganked"):Connect(function()
			if character:GetAttribute("Ganked") == true then
				Audio.play("Gank", rootOf(character))
			end
		end)
	end
	Players.LocalPlayer.CharacterAdded:Connect(watchGank)
	if Players.LocalPlayer.Character then
		watchGank(Players.LocalPlayer.Character)
	end
	Remotes.get("CombatResult").OnClientEvent:Connect(function(kind: string, attacker: Model?, target: Model?, detail: any)
		if kind == "Dash" then
			CombatFx.remote(kind, attacker, detail)
			return
		end
		if exped(kind, attacker, target) then
			return
		end
		local style = STYLES[kind]
		if not style then
			return
		end
		if style.color then
			flash(target, style.color)
			if kind == "Parry" then
				flash(attacker, STYLES.Break.color :: Color3) -- the parried attacker's posture breaks
			end
		end
		local targetRoot, attackerRoot = rootOf(target), rootOf(attacker)
		if kind == "PerfectDodge" then
			afterimage(target, style.color :: Color3)
			if targetRoot then
				CombatFx.evade(targetRoot.Position)
			end
		end
		local heavy = kind == "Hit" and detail == HEAVY_REACTION
		if kind == "WallSplat" and typeof(detail) == "Vector3" then
			local outward = if targetRoot then targetRoot.Position - detail else Vector3.yAxis
			CombatFx.wallSplat(detail, outward)
			burst(kind, detail, -outward, true, style.sound)
		elseif targetRoot then
			local at = targetRoot.Position + Vector3.new(0, 0.5, 0)
			local dir = targetRoot.CFrame.LookVector * -1
			if attackerRoot then
				local toward = attackerRoot.Position - targetRoot.Position
				if toward.Magnitude > 0.1 then
					at += toward.Unit
					dir = -toward
				end
			end
			if heavy and attackerRoot then
				if attackerRoot.Position.Y > targetRoot.Position.Y + 2.5 then
					CombatFx.slam(targetRoot.Position) -- an aerial slam drives them into the ground
					CombatFx.crater(targetRoot.Position, 0.85)
				else
					local launched = targetRoot
					task.delay(0.08, function()
						-- an uppercut: the knock has replicated by now and the body is rising
						if launched.Parent and launched.AssemblyLinearVelocity.Y > 20 then
							CombatFx.launch(launched.Position)
						end
					end)
				end
			end
			if kind == "Throw" then
				if detail == "Down" then
					CombatFx.slam(targetRoot.Position)
					CombatFx.crater(targetRoot.Position, 0.9)
				else
					CombatFx.impact("Hit", at, dir, true)
				end
			end
			burst(kind, at, dir, heavy, if heavy and style.heavySound then style.heavySound else style.sound)
		end
		local me = Players.LocalPlayer.Character
		if me and (me == attacker or me == target) then
			shake(if heavy then style.shake * 1.6 else style.shake)
			punch(if heavy then HEAVY_PUNCH else style.punch or 0)
			if kind ~= "Dodged" and kind ~= "PerfectDodge" then
				Audio.engage(if me == attacker then target else attacker)
			end
		end
	end)
end

return Feedback
