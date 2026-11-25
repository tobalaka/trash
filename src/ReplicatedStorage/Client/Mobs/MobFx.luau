--!strict
--[[
	MobFx - what every client sees and hears from a Pollution Beast, driven by the attributes its
	brain replicates (see JunkRamBrain). Effects are timed from the server's ActionStart, so the
	telegraph, the impact flash and the server's hit line up for everyone. Nothing is uploaded:
	particles use Roblox's built-in textures and sounds come from Shared/Config/Sounds.

	  ambient   toxic smog off the body, glowing spine crystals, grit falling as it walks,
	            footstep dust and thuds (from MobAnimator), amber embers once enraged
	  telegraph a gold glint on the horns before a parryable hit; an orange pulse and a ground ring
	            before unblockable ones (stomp, quake); landing markers for every crystal shard
	  moves     horn trails on swings, pawing and snorts before a charge, dust trails and wind
	            streaks during it, crystal shards on arcs, shockwaves, flying rubble, shaking camera
	  states    a ring of junk circling the head while dazed or staggered, a crumbling burst on death
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MobsConfig = require(Shared:WaitForChild("Config"):WaitForChild("Mobs"))
local Sounds = require(Shared:WaitForChild("Config"):WaitForChild("Sounds"))

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local rgb = Color3.fromRGB
local COLOR = {
	Smog = rgb(66, 70, 56),
	SmogEnraged = rgb(96, 74, 46),
	Dust = rgb(116, 100, 82),
	Crystal = rgb(232, 236, 246),
	CrystalEnraged = rgb(255, 168, 70),
	Glint = rgb(255, 226, 150),
	Danger = rgb(255, 124, 40),
	Shard = rgb(236, 230, 214),
	Rubble = rgb(58, 60, 66),
	Junk = rgb(92, 84, 72),
}
local PARRYABLE = { Sweep = true, Headbutt = true, RearKick = true, Charge = true }
local GLINT_LEAD = 0.3 -- the glint shows this long before a parryable hit
local SPINE_GLOW = 0.8
local SPINE_GLOW_ENRAGED = 2.2
local SPINE_GLOW_CHARGED = 4
local DIZZY_BITS = 4
local DIZZY_RADIUS = 2.4
local RING_SEGMENTS = 18
local FOOT_SHAKE_RANGE = 22

local MobFx = {}

local folder: Folder? = nil
local function fxFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "MobFx"
	made.Parent = workspace
	folder = made
	return made
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- ── building blocks ─────────────────────────────────────────────────────────

type Burst = {
	texture: string,
	color: Color3,
	count: number,
	size: { number }, -- start, end
	life: { number }, -- min, max
	speed: { number }, -- min, max
	spread: number?,
	drag: number?,
	light: number?,
	transparency: { number }?,
	acceleration: Vector3?,
	direction: Enum.NormalId?,
}

local function emitter(spec: Burst): ParticleEmitter
	local p = Instance.new("ParticleEmitter")
	p.Texture = spec.texture
	p.Color = ColorSequence.new(spec.color)
	p.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.size[1]), NumberSequenceKeypoint.new(1, spec.size[2]) })
	local tr = spec.transparency or { 0.2, 1 }
	p.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, tr[1]), NumberSequenceKeypoint.new(1, tr[2]) })
	p.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
	p.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
	p.SpreadAngle = Vector2.new(spec.spread or 180, spec.spread or 180)
	p.Drag = spec.drag or 2
	p.LightEmission = spec.light or 0
	p.Acceleration = spec.acceleration or Vector3.zero
	p.EmissionDirection = spec.direction or Enum.NormalId.Top
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-60, 60)
	p.Enabled = false
	return p
end

local function burst(at: Vector3, spec: Burst)
	local point = Instance.new("Attachment")
	point.WorldPosition = at
	point.Parent = workspace.Terrain
	local p = emitter(spec)
	p.Parent = point
	p:Emit(spec.count)
	Debris:AddItem(point, spec.life[2] + 0.5)
end

local DUST: Burst = { texture = SMOKE, color = COLOR.Dust, count = 8, size = { 2, 6 }, life = { 0.6, 1.1 }, speed = { 4, 9 }, transparency = { 0.35, 1 }, drag = 4, acceleration = Vector3.new(0, 2, 0) }
local BIG_DUST: Burst = { texture = SMOKE, color = COLOR.Dust, count = 34, size = { 4, 13 }, life = { 0.9, 1.8 }, speed = { 18, 34 }, transparency = { 0.3, 1 }, drag = 5, acceleration = Vector3.new(0, 3, 0) }
local SNORT: Burst = { texture = SMOKE, color = COLOR.Smog, count = 6, size = { 1, 3.5 }, life = { 0.5, 0.9 }, speed = { 6, 10 }, spread = 25, transparency = { 0.3, 1 }, direction = Enum.NormalId.Front }
local CRYSTAL_BITS: Burst = { texture = SPARKLE, color = COLOR.Shard, count = 18, size = { 0.9, 0 }, life = { 0.25, 0.6 }, speed = { 14, 28 }, light = 1, drag = 3, transparency = { 0, 1 } }
local GLINT: Burst = { texture = SPARKLE, color = COLOR.Glint, count = 3, size = { 4, 0 }, life = { 0.18, 0.25 }, speed = { 0, 0.5 }, light = 1, transparency = { 0, 1 } }

local function sound(name: string, at: Vector3, pitch: number, volume: number)
	local ids = Sounds.Mob[name] or Sounds[name]
	if not ids then
		return
	end
	local point = Instance.new("Attachment")
	point.WorldPosition = at
	point.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = ids[math.random(1, #ids)]
	s.PlaybackSpeed = pitch * (0.95 + math.random() * 0.1)
	s.Volume = volume
	s.RollOffMaxDistance = 180
	s.RollOffMinDistance = 12
	s.Parent = point
	s:Play()
	Debris:AddItem(point, 4)
end

-- camera shake, scaled by distance from the source
local shakeUntil, shakeStrength = 0, 0
local shakeConnection: RBXScriptConnection? = nil
local function shake(strength: number, from: Vector3, range: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local scaled = strength * (1 - math.clamp((camera.CFrame.Position - from).Magnitude / range, 0, 1))
	if scaled <= 0.02 then
		return
	end
	shakeStrength = math.max(shakeStrength, scaled)
	shakeUntil = os.clock() + 0.1 + scaled * 0.45
	if not shakeConnection then
		shakeConnection = RunService.RenderStepped:Connect(function()
			local left = shakeUntil - os.clock()
			if left <= 0 then
				shakeStrength = 0
				return
			end
			local s = shakeStrength * math.min(1, left * 4)
			local cam = workspace.CurrentCamera
			if cam then
				cam.CFrame *= CFrame.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
			end
		end)
	end
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = fxFolder()
	return p
end

-- A flat disc on the ground (a cylinder lying down).
local function disc(center: Vector3, radius: number, color: Color3, transparency: number): Part
	return part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = transparency,
	})
end

local function resizeDisc(d: Part, center: Vector3, radius: number)
	d.Size = Vector3.new(0.15, radius * 2, radius * 2)
	d.CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

local function shockwave(center: Vector3, radius: number, color: Color3, life: number)
	local d = disc(center, 0.5, color, 0.35)
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - started) / life, 0, 1)
		if a >= 1 then
			connection:Disconnect()
			d:Destroy()
			return
		end
		resizeDisc(d, center, 0.5 + (radius - 0.5) * (1 - (1 - a) ^ 3))
		d.Transparency = 0.35 + 0.65 * a
	end)
end

local function rubble(center: Vector3, count: number, speed: number, scale: number)
	for _ = 1, count do
		local size = (0.5 + math.random() * 1.1) * scale
		local p = Instance.new("Part")
		p.Size = Vector3.new(size, size * (0.6 + math.random() * 0.6), size)
		p.Material = Enum.Material.Slate
		p.Color = if math.random() < 0.7 then COLOR.Rubble else COLOR.Junk
		p.CFrame = CFrame.new(center + Vector3.new(math.random() - 0.5, 0.6, math.random() - 0.5) * 2 * scale) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = fxFolder()
		local angle = math.random() * 2 * math.pi
		p.AssemblyLinearVelocity = Vector3.new(math.cos(angle), 0, math.sin(angle)) * speed * (0.5 + math.random() * 0.5) + Vector3.new(0, speed * (0.8 + math.random() * 0.6), 0)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
		Debris:AddItem(p, 2 + math.random())
	end
end

local function pulse(model: Model, color: Color3, duration: number)
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.55
	h.OutlineTransparency = 0.1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = model
	TweenService:Create(h, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	Debris:AddItem(h, duration + 0.05)
end

local function trail(a0: Attachment, a1: Attachment, color: Color3, life: number, transparency: number): Trail
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(color)
	t.Transparency = NumberSequence.new(transparency, 1)
	t.Lifetime = life
	t.LightEmission = 0.7
	t.FaceCamera = true
	t.Enabled = false
	t.Parent = a0.Parent
	return t
end

-- ── one beast ───────────────────────────────────────────────────────────────

export type Handle = { onFoot: (leg: string, position: Vector3, weight: number) -> (), stop: () -> () }

function MobFx.attach(model: Model): Handle
	local cfg = (MobsConfig :: any)[model:GetAttribute("Mob") or "JunkRam"]
	local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local body = model:WaitForChild("Body", 10) :: BasePart?
	local head = model:WaitForChild("Head", 10) :: BasePart?
	if not cfg or not root or not body or not head then
		return { onFoot = function() end, stop = function() end }
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local rootHeight = (if humanoid then humanoid.HipHeight else 4.5) + root.Size.Y / 2
	local S = cfg.SCALE or 1 -- effect sizes were authored for a scale-1 beast
	local RUBBLE_SPEED = math.sqrt(S)
	-- a copy of a burst sized for this beast
	local function big(spec: Burst, k: number?): Burst
		local m = k or S
		local copy = table.clone(spec)
		copy.size = { spec.size[1] * m, spec.size[2] * m }
		copy.speed = { spec.speed[1] * m, spec.speed[2] * m }
		copy.acceleration = if spec.acceleration then spec.acceleration * m else nil
		return copy
	end
	local created: { Instance } = {}
	local connections: { RBXScriptConnection } = {}
	local loops: { [string]: RBXScriptConnection } = {}
	local function keep<T>(i: T): T
		table.insert(created, i :: any)
		return i
	end
	local function attachmentOf(part: BasePart, name: string): Attachment?
		return part:FindFirstChild(name) :: Attachment?
	end
	local function world(part: BasePart, name: string): Vector3
		local a = attachmentOf(part, name)
		return if a then a.WorldPosition else part.Position
	end
	local function ground(): Vector3
		return root.Position - Vector3.new(0, rootHeight, 0)
	end
	local function stopLoop(name: string)
		local c = loops[name]
		if c then
			c:Disconnect()
			loops[name] = nil
		end
	end

	-- ambient
	local core = attachmentOf(body, "Core")
	local spine = attachmentOf(body, "Spine")
	local belly = attachmentOf(body, "Belly")
	local face = attachmentOf(head, "Face")
	local smog = keep(emitter(big({ texture = SMOKE, color = COLOR.Smog, count = 0, size = { 3, 9 }, life = { 2.2, 3.4 }, speed = { 1, 3 }, transparency = { 0.55, 1 }, acceleration = Vector3.new(0, 1.5, 0) })))
	smog.Rate = 5
	smog.Enabled = true
	smog.Parent = core or body
	local motes = keep(emitter(big({ texture = SPARKLE, color = COLOR.Crystal, count = 0, size = { 0.35, 0 }, life = { 0.8, 1.4 }, speed = { 0.5, 1.5 }, light = 1, transparency = { 0.1, 1 } })))
	motes.Rate = 2
	motes.Enabled = true
	motes.Parent = spine or body
	local grit = keep(emitter(big({ texture = SMOKE, color = COLOR.Dust, count = 0, size = { 0.4, 0.9 }, life = { 0.6, 1 }, speed = { 0, 1 }, transparency = { 0.4, 1 }, acceleration = Vector3.new(0, -12, 0), direction = Enum.NormalId.Bottom })))
	grit.Rate = 0
	grit.Enabled = true
	grit.Parent = belly or body
	local embers = keep(emitter(big({ texture = SPARKLE, color = COLOR.CrystalEnraged, count = 0, size = { 0.3, 0 }, life = { 0.8, 1.4 }, speed = { 2, 5 }, light = 1, transparency = { 0, 1 }, acceleration = Vector3.new(0, 4, 0) })))
	embers.Rate = 0
	embers.Enabled = true
	embers.Parent = core or body
	local glow = keep(Instance.new("PointLight"))
	glow.Color = COLOR.Crystal
	glow.Brightness = SPINE_GLOW
	glow.Range = 12 * S
	glow.Shadows = false
	glow.Parent = spine or body
	local faceGlow = keep(Instance.new("PointLight"))
	faceGlow.Color = COLOR.CrystalEnraged
	faceGlow.Brightness = 0
	faceGlow.Range = 8 * S
	faceGlow.Parent = face or head

	-- swing trails on the horns, streaks along the flanks for the charge
	local horns: { Trail } = {}
	for _, side in { "L", "R" } do
		local a0, a1 = attachmentOf(head, "Horn" .. side .. "0"), attachmentOf(head, "Horn" .. side .. "1")
		if a0 and a1 then
			table.insert(horns, keep(trail(a0, a1, COLOR.Crystal, 0.22, 0.15)))
		end
	end
	local streaks: { Trail } = {}
	local feetDust: { ParticleEmitter } = {}
	do
		local half = body.Size.X / 2
		for _, x in { -half, half } do
			local a0 = keep(Instance.new("Attachment"))
			a0.Position = Vector3.new(x, 1.2 * S, 0)
			a0.Parent = body
			local a1 = keep(Instance.new("Attachment"))
			a1.Position = Vector3.new(x, -0.6 * S, 0)
			a1.Parent = body
			table.insert(streaks, keep(trail(a0, a1, rgb(255, 255, 255), 0.3, 0.6)))
		end
		for _, leg in { "LegFL", "LegFR", "LegBL", "LegBR" } do
			local p = model:FindFirstChild(leg)
			local foot = if p and p:IsA("BasePart") then attachmentOf(p, "Foot") else nil
			if foot then
				local e = keep(emitter(big({ texture = SMOKE, color = COLOR.Dust, count = 0, size = { 2, 5 }, life = { 0.5, 0.9 }, speed = { 2, 5 }, transparency = { 0.4, 1 }, acceleration = Vector3.new(0, 2, 0) })))
				e.Rate = 0
				e.Enabled = true
				e.Parent = foot
				table.insert(feetDust, e)
			end
		end
	end
	local function setTrails(list: { Trail }, on: boolean)
		for _, t in list do
			t.Enabled = on
		end
	end
	local function swingWindow(at: number, length: number)
		task.delay(math.max(0, at - now() - 0.05), function()
			setTrails(horns, true)
			task.wait(length)
			setTrails(horns, false)
		end)
	end

	-- schedules `fn` at server time `at` if the move it belongs to is still running
	local function at(serial: number, time: number, fn: () -> ())
		task.delay(math.max(0, time - now()), function()
			if model.Parent and model:GetAttribute("ActionSerial") == serial and model:GetAttribute("Action") ~= "" then
				fn()
			end
		end)
	end

	local function glint(serial: number, hitAt: number, spot: Vector3?)
		at(serial, hitAt - GLINT_LEAD, function()
			local where = spot or world(head, "HornR1")
			burst(where, big(GLINT))
			burst(world(head, "HornL1"), big(GLINT))
			pulse(model, COLOR.Glint, 0.25)
			sound("Parry", where, 1.7, 0.35)
		end)
	end

	local function danger(serial: number, from: number)
		at(serial, from, function()
			pulse(model, COLOR.Danger, 0.45)
		end)
	end

	-- ── moves ─────────────────────────────────────────────────────────────────

	local function onAction()
		local serial = model:GetAttribute("ActionSerial")
		local action = model:GetAttribute("Action")
		local start = model:GetAttribute("ActionStart")
		local windup = model:GetAttribute("ActionWindup")
		if typeof(serial) ~= "number" or typeof(action) ~= "string" or typeof(start) ~= "number" or typeof(windup) ~= "number" then
			return
		end
		local A = cfg.ATTACKS
		local hitAt = start + windup
		if PARRYABLE[action] then
			glint(serial, hitAt, if action == "RearKick" then world(body, "Belly") else nil)
		end

		if action == "Sweep" then
			swingWindow(hitAt, 0.25)
			at(serial, hitAt - 0.08, function()
				sound("Swing", world(head, "Face"), 0.65, 0.9)
			end)
		elseif action == "Headbutt" then
			for _, t in { hitAt, hitAt + A.Headbutt.gap } do
				swingWindow(t, 0.18)
				at(serial, t, function()
					sound("Swing", world(head, "Face"), 0.8, 0.8)
					burst(world(head, "Face"), big(DUST))
				end)
			end
		elseif action == "RearKick" then
			at(serial, hitAt, function()
				sound("Swing", world(body, "Belly"), 0.7, 0.9)
				for _, leg in { "LegBL", "LegBR" } do
					local p = model:FindFirstChild(leg)
					if p and p:IsA("BasePart") then
						burst(world(p, "Foot"), big(DUST))
					end
				end
			end)
		elseif action == "Stomp" then
			local a = A.Stomp
			danger(serial, start)
			local ring = disc(ground(), a.radius * 0.3, COLOR.Danger, 0.8)
			stopLoop("telegraph")
			loops.telegraph = RunService.RenderStepped:Connect(function()
				local t = now()
				if not model.Parent or model:GetAttribute("ActionSerial") ~= serial or model:GetAttribute("Action") == "" or t >= hitAt then
					stopLoop("telegraph")
					ring:Destroy()
					return
				end
				local k = math.clamp((t - start) / windup, 0, 1)
				local center = ground() + root.CFrame.LookVector * a.offset
				resizeDisc(ring, center, a.radius * (0.3 + 0.7 * k))
				ring.Transparency = 0.82 - 0.25 * k + math.sin(t * 18) * 0.05
			end)
			at(serial, hitAt, function()
				local center = ground() + root.CFrame.LookVector * a.offset
				shockwave(center, a.radius * 1.15, COLOR.Dust, 0.4)
				burst(center + Vector3.new(0, 1, 0), big(BIG_DUST))
				rubble(center, 14, 26 * RUBBLE_SPEED, S)
				sound("Slam", center, 0.5, 1)
				sound("HeavyHit", center, 0.45, 0.9)
				shake(1.6, center, cfg.SHAKE_RANGE)
			end)
		elseif action == "Charge" then
			for k = 0, 3 do
				at(serial, start + 0.15 + k * (windup / 4), function()
					local p = model:FindFirstChild("LegFL")
					if p and p:IsA("BasePart") then
						burst(world(p, "Foot"), big(DUST))
					end
				end)
			end
			for _, k in { 0.2, 0.6 } do
				at(serial, start + windup * k, function()
					if face then
						local point = keep(Instance.new("Attachment"))
						point.WorldCFrame = face.WorldCFrame * CFrame.Angles(0, math.pi, 0)
						point.Parent = workspace.Terrain
						local e = emitter(big(SNORT))
						e.Parent = point
						e:Emit(SNORT.count)
						Debris:AddItem(point, 1.2)
					end
					sound("Dash", world(head, "Face"), 0.55, 0.5)
				end)
			end
		elseif action == "Barrage" then
			at(serial, start, function()
				TweenService:Create(glow, TweenInfo.new(windup), { Brightness = SPINE_GLOW_CHARGED }):Play()
				motes.Rate = 25
			end)
		elseif action == "Quake" then
			danger(serial, start)
			at(serial, start + windup * 0.5, function()
				burst(ground(), big(DUST))
			end)
		elseif action == "Roar" then
			at(serial, hitAt, function()
				local where = world(head, "Face")
				local ball = part({
					Shape = Enum.PartType.Ball,
					Size = Vector3.one * 4 * S,
					CFrame = CFrame.new(where),
					Material = Enum.Material.ForceField,
					Color = COLOR.Smog,
					Transparency = 0.2,
				})
				TweenService:Create(ball, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * A.Roar.radius * 2.2, Transparency = 1 }):Play()
				Debris:AddItem(ball, 0.7)
				burst(where, big(BIG_DUST))
				sound("Break", where, 0.42, 1)
				sound("Slam", where, 0.45, 0.9)
				shake(1.4, where, cfg.SHAKE_RANGE)
			end)
		end
	end

	local function shards(serial: number)
		local raw = model:GetAttribute("ActionPoints")
		if typeof(raw) ~= "string" then
			return
		end
		local b = cfg.ATTACKS.Barrage
		local fired = now()
		TweenService:Create(glow, TweenInfo.new(0.6), { Brightness = if model:GetAttribute("Enraged") then SPINE_GLOW_ENRAGED else SPINE_GLOW }):Play()
		motes.Rate = 2
		local i = 0
		for chunk in string.gmatch(raw, "[^;]+") do
			local x, y, z = string.match(chunk, "([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
			if not x then
				continue
			end
			local target = Vector3.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number)
			local launch = fired + i * b.interval
			i += 1
			local marker = disc(target, b.radius, COLOR.Danger, 0.85)
			task.delay(math.max(0, launch - now()), function()
				local from = world(body, "Spine")
				local shard = part({
					Size = Vector3.new(0.8, 0.8, 2.6) * S * 0.8,
					Material = Enum.Material.Glass,
					Color = COLOR.Shard,
					Transparency = 0.1,
					CFrame = CFrame.new(from),
				})
				local light = Instance.new("PointLight")
				light.Color = COLOR.Crystal
				light.Brightness = 2
				light.Range = 8 * S
				light.Parent = shard
				local apex = math.max(8 * S, (target - from).Magnitude * 0.35)
				sound("Swing", from, 1.4, 0.5)
				local connection: RBXScriptConnection
				connection = RunService.RenderStepped:Connect(function()
					local s = math.clamp((now() - launch) / b.flight, 0, 1)
					local position = from:Lerp(target, s) + Vector3.new(0, 4 * apex * s * (1 - s), 0)
					local ahead = from:Lerp(target, math.min(1, s + 0.02)) + Vector3.new(0, 4 * apex * math.min(1, s + 0.02) * (1 - math.min(1, s + 0.02)), 0)
					if (ahead - position).Magnitude > 1e-3 then
						shard.CFrame = CFrame.lookAt(position, ahead)
					else
						shard.Position = position
					end
					marker.Transparency = 0.85 - 0.3 * s + math.sin(os.clock() * 20) * 0.04
					if s >= 1 then
						connection:Disconnect()
						shard:Destroy()
						marker:Destroy()
						burst(target + Vector3.new(0, 0.5, 0), big(CRYSTAL_BITS, RUBBLE_SPEED))
						burst(target, big(DUST))
						sound("Parry", target, 1.35, 0.6)
						shake(0.35, target, b.radius * 4)
					end
				end)
			end)
		end
	end

	local function quakeLeap()
		local aim = model:GetAttribute("ActionAim")
		if typeof(aim) ~= "Vector3" then
			return
		end
		local q = cfg.ATTACKS.Quake
		burst(ground(), big(BIG_DUST))
		sound("Slam", ground(), 0.7, 0.8)
		local marker = disc(aim, q.radius * 0.2, COLOR.Danger, 0.75)
		local began = os.clock()
		stopLoop("leap")
		loops.leap = RunService.RenderStepped:Connect(function()
			local k = math.clamp((os.clock() - began) / q.air, 0, 1)
			resizeDisc(marker, aim, q.radius * (0.2 + 0.8 * k))
			if k >= 1 or not model.Parent then
				stopLoop("leap")
				marker:Destroy()
			end
		end)
	end

	local function quakeLand()
		local aim = model:GetAttribute("ActionAim")
		local center = if typeof(aim) == "Vector3" then aim else ground()
		local q = cfg.ATTACKS.Quake
		shockwave(center, q.radius * 1.3, COLOR.Dust, 0.45)
		burst(center + Vector3.new(0, 1, 0), big(BIG_DUST))
		rubble(center, 22, 32 * RUBBLE_SPEED, S)
		sound("Slam", center, 0.4, 1)
		sound("HeavyHit", center, 0.35, 1)
		shake(2.2, center, cfg.SHAKE_RANGE * 1.4)
		local landed = os.clock()
		for k = 0, q.rings - 1 do
			local segments: { Part } = {}
			for _ = 1, RING_SEGMENTS do
				table.insert(segments, part({ Material = Enum.Material.Neon, Color = COLOR.Danger, Transparency = 0.25, Size = Vector3.new(1, 3, 1) }))
			end
			local begins = landed + k * q.ringInterval
			local connection: RBXScriptConnection
			connection = RunService.RenderStepped:Connect(function()
				local r = (os.clock() - begins) * q.ringSpeed
				if r > q.ringReach or not model.Parent then
					connection:Disconnect()
					for _, s in segments do
						s:Destroy()
					end
					return
				end
				local visible = r > 0.5
				local length = 2 * math.pi * math.max(r, 0.5) / RING_SEGMENTS * 1.08
				for i, s in segments do
					local angle = (i / RING_SEGMENTS) * 2 * math.pi
					local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * r
					s.Size = Vector3.new(1, 3, length)
					s.CFrame = CFrame.lookAt(center + offset + Vector3.new(0, 1.5, 0), center + offset + Vector3.new(-math.sin(angle), 0, math.cos(angle)) + Vector3.new(0, 1.5, 0))
					s.Transparency = if visible then 0.25 + 0.6 * (r / q.ringReach) else 1
				end
			end)
			task.delay(k * q.ringInterval, function()
				sound("Slam", center, 0.6 + k * 0.1, 0.5)
			end)
		end
	end

	local function onPhase()
		local serial = model:GetAttribute("ActionSerial")
		local p = model:GetAttribute("ActionPhase")
		if typeof(serial) ~= "number" then
			return
		end
		if p == "Dash" then
			setTrails(streaks, true)
			for _, e in feetDust do
				e.Rate = 40
			end
			sound("Dash", root.Position, 0.6, 0.9)
		elseif p == "Crash" then
			local where = world(head, "Face")
			burst(where, big(BIG_DUST))
			rubble(where, 14, 22 * RUBBLE_SPEED, S)
			sound("HeavyHit", where, 0.5, 1)
			sound("Break", where, 0.6, 0.9)
			shake(1.6, where, cfg.SHAKE_RANGE)
		elseif p == "Feint" then
			if face then
				burst(face.WorldPosition, big(SNORT))
			end
			sound("Dash", world(head, "Face"), 0.5, 0.5)
		elseif p == "Fire" then
			shards(serial)
		elseif p == "Leap" then
			quakeLeap()
		elseif p == "Land" then
			quakeLand()
		end
	end

	local function onActionEnded()
		if model:GetAttribute("Action") ~= "" then
			return
		end
		setTrails(horns, false)
		setTrails(streaks, false)
		for _, e in feetDust do
			e.Rate = 0
		end
		if motes.Rate > 2 then
			motes.Rate = 2
			TweenService:Create(glow, TweenInfo.new(0.5), { Brightness = if model:GetAttribute("Enraged") then SPINE_GLOW_ENRAGED else SPINE_GLOW }):Play()
		end
	end

	-- ── states ────────────────────────────────────────────────────────────────

	local bits: { Part } = {}
	local function dizzy(on: boolean)
		stopLoop("dizzy")
		for _, p in bits do
			p:Destroy()
		end
		table.clear(bits)
		if not on then
			return
		end
		for i = 1, DIZZY_BITS do
			table.insert(bits, part({ Size = Vector3.new(0.5, 0.35, 0.5) * S, Material = Enum.Material.Metal, Color = if i % 2 == 0 then COLOR.Junk else COLOR.Rubble }))
		end
		loops.dizzy = RunService.RenderStepped:Connect(function()
			if not head.Parent then
				return
			end
			local c = os.clock()
			for i, p in bits do
				local angle = c * 4 + i / DIZZY_BITS * 2 * math.pi
				p.CFrame = CFrame.new(head.Position + Vector3.new(math.cos(angle) * DIZZY_RADIUS, 3.2 + math.sin(c * 6 + i) * 0.3, math.sin(angle) * DIZZY_RADIUS) * S) * CFrame.Angles(c * 3, c * 2, 0)
			end
		end)
	end

	local function onState()
		local s = model:GetAttribute("MobState")
		dizzy(s == "Staggered" or s == "Dazed")
		if s == "Staggered" then
			TweenService:Create(glow, TweenInfo.new(0.3), { Brightness = 0.15 }):Play()
			sound("Break", head.Position, 0.55, 1)
			burst(body.Position, big(BIG_DUST))
		elseif s == "Dead" then
			smog.Enabled = false
			motes.Enabled = false
			embers.Enabled = false
			glow.Enabled = false
			faceGlow.Enabled = false
			burst(body.Position, big(BIG_DUST))
			burst(body.Position + Vector3.new(0, 2, 0), big(BIG_DUST))
			rubble(body.Position, 26, 24 * RUBBLE_SPEED, S)
			sound("Break", body.Position, 0.45, 1)
			sound("Slam", body.Position, 0.4, 1)
			shake(1.8, body.Position, cfg.SHAKE_RANGE)
		else
			TweenService:Create(glow, TweenInfo.new(0.4), { Brightness = if model:GetAttribute("Enraged") then SPINE_GLOW_ENRAGED else SPINE_GLOW }):Play()
		end
	end

	local function onEnraged()
		local on = model:GetAttribute("Enraged") == true
		glow.Color = if on then COLOR.CrystalEnraged else COLOR.Crystal
		glow.Brightness = if on then SPINE_GLOW_ENRAGED else SPINE_GLOW
		faceGlow.Brightness = if on then 2 else 0
		embers.Rate = if on then 10 else 0
		smog.Color = ColorSequence.new(if on then COLOR.SmogEnraged else COLOR.Smog)
		smog.Rate = if on then 9 else 5
		if on then
			pulse(model, COLOR.CrystalEnraged, 0.8)
		end
	end

	table.insert(connections, model:GetAttributeChangedSignal("ActionSerial"):Connect(onAction))
	table.insert(connections, model:GetAttributeChangedSignal("ActionPhase"):Connect(onPhase))
	table.insert(connections, model:GetAttributeChangedSignal("Action"):Connect(onActionEnded))
	table.insert(connections, model:GetAttributeChangedSignal("MobState"):Connect(onState))
	table.insert(connections, model:GetAttributeChangedSignal("Enraged"):Connect(onEnraged))
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local v = root.AssemblyLinearVelocity
		grit.Rate = math.clamp(Vector2.new(v.X, v.Z).Magnitude * 0.6, 0, 14)
	end))
	onEnraged()
	onState()

	local handle: Handle = {
		onFoot = function(_leg, position, weight)
			local camera = workspace.CurrentCamera
			if camera and (camera.CFrame.Position - position).Magnitude > cfg.HUD_RANGE * 2 then
				return
			end
			burst(position + Vector3.new(0, 0.3, 0), big({ texture = SMOKE, color = COLOR.Dust, count = 4 + math.floor(weight * 3), size = { 1.5, 4 }, life = { 0.5, 0.9 }, speed = { 3, 6 }, transparency = { 0.4, 1 }, drag = 4, acceleration = Vector3.new(0, 2, 0) }))
			sound("HeavyHit", position, 0.26, 0.3 + 0.15 * weight)
			if weight > 0.4 then
				shake(0.08 * weight * S, position, FOOT_SHAKE_RANGE * S)
			end
		end,
		stop = function()
			for _, c in connections do
				c:Disconnect()
			end
			for name in loops do
				stopLoop(name)
			end
			dizzy(false)
			for _, i in created do
				i:Destroy()
			end
		end,
	}
	return handle
end

return MobFx
