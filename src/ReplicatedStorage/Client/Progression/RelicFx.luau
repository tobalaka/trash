--!strict
--[[
	RelicFx - what everyone sees when a Relic move goes off (vault: Relic-Abilities). The server
	fires RelicFx(caster, relic, key, data) with a phase:
	  Start   the cast (data.dir, data.origin, data.start = server time); timed effects begin
	          after the move's windup
	  Hit / Pulse / Follow / Land / Counter / Tidy / End   where something landed (data.at, radius)
	  Stop / Bounce   a thrown object stopped or bounced (data.index, data.at / data.to)
	Effects are local Parts and emitters in Workspace.RelicFxLocal, never collide or block rays,
	and clean themselves up. Nothing is uploaded; colours come from the move's `fx` table.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local RelicAnimator = require(script.Parent:WaitForChild("RelicAnimator"))
local Audio = require(script.Parent.Parent:WaitForChild("Audio"))

-- the cast sound by move kind (Shared/Config/Sounds cues; the mixer sets the volumes)
local CAST_SOUND: { [string]: string } = { Guard = "RelicGuard", Counter = "RelicGuard", Heal = "RelicHeal", Tidy = "RelicHeal" }
local HEAL_PITCH = 1.4

local FOLDER = "RelicFxLocal"
local WHITE = Color3.new(1, 1, 1)

local RelicFx = {}
local started = false

local folder: Folder? = nil
local projectiles: { [string]: { [number]: { part: BasePart, stop: boolean, to: Model?, returning: boolean } } } = {}

local function root(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = root()
	return p
end

local function tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function fadeOut(p: BasePart, time: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then
		goal.Size = grow
	end
	tween(p, time, goal)
	Debris:AddItem(p, time + 0.05)
end

-- flat expanding ring (a thin cylinder lying on the ground)
function RelicFx.ring(center: Vector3, radius: number, color: Color3, time: number?, height: number?)
	local t = time or 0.45
	local p = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height or 0.3, radius * 0.4, radius * 0.4),
		CFrame = CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.25,
	})
	fadeOut(p, t, Vector3.new(height or 0.3, radius * 2, radius * 2))
end

-- translucent sphere that swells and fades
function RelicFx.dome(center: Vector3, radius: number, color: Color3, time: number?)
	local t = time or 0.4
	local p = part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * radius * 0.6,
		CFrame = CFrame.new(center),
		Color = color,
		Transparency = 0.55,
		Material = Enum.Material.ForceField,
	})
	fadeOut(p, t, Vector3.one * radius * 2)
end

-- an arc of thin blades sweeping out in front (cones and sweeps)
function RelicFx.arc(origin: Vector3, dir: Vector3, radius: number, angle: number, color: Color3, time: number?)
	local base = CFrame.lookAt(origin, origin + dir)
	local blades = math.max(5, math.floor(angle / 15))
	for i = 0, blades - 1 do
		local a = math.rad(-angle / 2 + angle * i / (blades - 1))
		local cf = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.2, -radius * 0.55)
		local p = part({ Size = Vector3.new(0.25, 0.25, radius * 0.9), CFrame = cf, Color = color, Transparency = 0.2 })
		task.delay(i * 0.012, function()
			fadeOut(p, (time or 0.35), Vector3.new(0.05, 0.05, radius * 1.1))
		end)
	end
end

-- a straight streak between two points
function RelicFx.streak(a: Vector3, b: Vector3, color: Color3, width: number?, time: number?)
	local len = (b - a).Magnitude
	if len < 0.1 then
		return
	end
	local p = part({
		Size = Vector3.new(width or 0.6, width or 0.6, len),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color,
		Transparency = 0.3,
	})
	fadeOut(p, time or 0.3, Vector3.new(0.05, 0.05, len))
end

-- a one-shot puff of particles
function RelicFx.puff(center: Vector3, color: Color3, count: number, speed: number?, size: number?)
	local holder = part({ Size = Vector3.one * 0.2, CFrame = CFrame.new(center), Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.4
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size or 0.8), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new((speed or 14) * 0.5, speed or 14)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 4
	e.Rate = 0
	e.Parent = holder
	e:Emit(count)
	Debris:AddItem(holder, 1.2)
end

-- a short-lived glowing trail on a character's root
local function trail(character: Model, color: Color3, time: number)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0)
	a0.Parent = rootPart
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.2, 0)
	a1.Parent = rootPart
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(color)
	t.Transparency = NumberSequence.new(0.3, 1)
	t.Lifetime = 0.25
	t.LightEmission = 0.5
	t.FaceCamera = true
	t.Parent = rootPart
	Debris:AddItem(t, time + 0.3)
	Debris:AddItem(a0, time + 0.3)
	Debris:AddItem(a1, time + 0.3)
end

local function rootOf(character: Model): BasePart?
	local r = character:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- runs `fn(dt, elapsed)` every frame for `time` seconds, then `done()`
local function follow(time: number, fn: (number, number) -> (), done: (() -> ())?)
	local elapsed = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed >= time then
			conn:Disconnect()
			if done then
				done()
			end
			return
		end
		fn(dt, elapsed)
	end)
end

-- a shell over the caster for `time` (canopies, shields, plates)
local function shell(character: Model, color: Color3, accent: Color3, time: number, shape: string)
	local r = rootOf(character)
	if not r then
		return
	end
	local parts: { BasePart } = {}
	if shape == "plates" then
		for i = 0, 5 do
			table.insert(parts, part({ Size = Vector3.new(1.2, 1.6, 0.15), Color = accent, Material = Enum.Material.Metal, Transparency = 0.1 }))
		end
	elseif shape == "shield" then
		table.insert(parts, part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 4.2, 4.2), Color = color, Material = Enum.Material.Metal, Transparency = 0.15 }))
	else -- canopy: a dark dome of panels with a coloured rim
		for i = 0, 7 do
			table.insert(parts, part({ Size = Vector3.new(2.4, 0.15, 3), Color = if i % 2 == 0 then color else accent, Material = Enum.Material.Fabric, Transparency = 0.05 }))
		end
	end
	follow(time, function(_, elapsed)
		local base = r.CFrame
		for i, p in parts do
			if shape == "plates" then
				p.CFrame = base * CFrame.Angles(0, elapsed * 2 + i * math.pi / 3, 0) * CFrame.new(0, 0, -1.8)
			elseif shape == "shield" then
				p.CFrame = base * CFrame.new(0, 0.3, -2.2) * CFrame.Angles(0, math.rad(90), 0)
			else
				p.CFrame = base * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, (i - 1) * math.pi / 4, 0) * CFrame.new(0, 0, -1.25) * CFrame.Angles(math.rad(28), 0, 0)
			end
		end
	end, function()
		for _, p in parts do
			fadeOut(p, 0.2)
		end
	end)
end

-- ── projectiles (client-side copy of the server path) ──

local function projectileModel(shape: string, color: Color3, accent: Color3?): BasePart
	if shape == "hubcap" then
		return part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.4, 2.4), Color = color, Material = Enum.Material.Metal, Transparency = 0 })
	end
	return part({ Size = Vector3.new(1.6, 1.3, 1.5), Color = color, Material = Enum.Material.CorrodedMetal, Transparency = 0 })
end

local function launch(caster: Model, a: Relics.Ability, data: { [string]: any }, key: string)
	local r = rootOf(caster)
	if not r then
		return
	end
	local count = a.count or 1
	local spread = math.rad(a.spread or 0)
	local id = caster:GetFullName() .. key
	projectiles[id] = {}
	for i = 1, count do
		local angle = if count > 1 then -spread / 2 + spread * (i - 1) / (count - 1) else 0
		local dir = (CFrame.Angles(0, angle, 0) * CFrame.lookAt(Vector3.zero, data.dir)).LookVector
		local p = projectileModel(a.fx.shape, a.fx.color, a.fx.accent)
		local state = { part = p, stop = false, to = nil :: Model?, returning = false }
		projectiles[id][i] = state
		local pos = r.Position + Vector3.new(0, 0.5, 0) + dir * 2
		local heading = dir
		local travelled = 0
		local range = a.range or 40
		local speed = a.speed or 80
		local spin = 0
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function(dt)
			if state.stop or not p.Parent or travelled > range * 3 then
				conn:Disconnect()
				fadeOut(p, 0.15)
				RelicFx.puff(pos, a.fx.accent or a.fx.color, 6)
				return
			end
			local step = speed * dt
			if state.returning then
				local back = r.Position + Vector3.new(0, 0.5, 0) - pos
				if back.Magnitude <= step + 1 then
					state.stop = true
				end
				heading = if back.Magnitude > 0 then back.Unit else heading
			elseif state.to and state.to.Parent then
				local tr = rootOf(state.to)
				if tr then
					local to = tr.Position - pos
					heading = if to.Magnitude > 0 then to.Unit else heading
				end
			end
			pos += heading * step
			travelled += step
			if not state.returning and travelled >= range then
				if a.returns then
					state.returning = true
				else
					state.stop = true
				end
			end
			spin += dt * 20
			if a.fx.shape == "hubcap" then
				p.CFrame = CFrame.new(pos) * CFrame.Angles(0, spin, 0) * CFrame.Angles(0, 0, math.rad(90))
			else
				p.CFrame = CFrame.new(pos) * CFrame.Angles(spin * 0.3, spin, 0)
			end
		end)
	end
end

-- ── per kind ──

local function onStart(caster: Model, a: Relics.Ability, data: { [string]: any }, key: string)
	local color, accent = a.fx.color, a.fx.accent or a.fx.color
	local dir: Vector3 = data.dir
	local wait = math.max(0, (data.start or now()) + a.windup - now())
	local kind = a.kind
	if kind == "Counter" then
		shell(caster, color, accent, a.window or 0.8, a.fx.shape)
	elseif kind == "Guard" then
		shell(caster, color, accent, a.duration or 4, a.fx.shape)
	end
	task.delay(wait, function()
		if not caster.Parent then
			return
		end
		local r = rootOf(caster)
		local at = if r then r.Position else data.origin
		if kind == "Dash" then
			trail(caster, color, a.duration or 0.3)
			RelicFx.streak(at, at + dir * (a.distance or 15), color, 0.8, 0.35)
		elseif kind == "Cone" then
			RelicFx.arc(at, dir, a.radius or 10, a.angle or 90, color, 0.35)
			RelicFx.puff(at + dir * 3, accent, 10)
		elseif kind == "Strike" then
			RelicFx.arc(at, dir, a.range or 6, 50, color, 0.25)
		elseif kind == "Projectile" then
			launch(caster, a, data, key)
		elseif kind == "Wave" then
			local range = a.range or 20
			local segments = math.floor(range / 2.5)
			for i = 1, segments do
				task.delay(i * 2.5 / (a.speed or 60), function()
					local p = at + dir * (i * 2.5) - Vector3.new(0, 2.6, 0)
					local slab = part({
						Size = Vector3.new(a.width or 6, 0.6, 2.2),
						CFrame = CFrame.lookAt(p, p + dir) * CFrame.Angles(math.rad(math.random(-12, 12)), 0, 0),
						Color = color,
						Material = Enum.Material.Slate,
						Transparency = 0,
					})
					RelicFx.puff(p + Vector3.new(0, 1, 0), accent, 5, 10)
					task.delay(0.6, function()
						fadeOut(slab, 0.4)
					end)
				end)
			end
		elseif kind == "Leap" then
			trail(caster, color, a.duration or 0.5)
		elseif kind == "Heal" then
			local holder = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(at) })
			local e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(color, accent)
			e.LightEmission = 0.6
			e.Size = NumberSequence.new(0.5, 0)
			e.Lifetime = NumberRange.new(0.8, 1.2)
			e.Speed = NumberRange.new(3, 6)
			e.SpreadAngle = Vector2.new(30, 30)
			e.Rate = 30
			e.EmissionDirection = Enum.NormalId.Top
			e.Parent = holder
			follow(a.duration or 5, function()
				local rr = rootOf(caster)
				if rr then
					holder.CFrame = CFrame.new(rr.Position - Vector3.new(0, 2, 0))
				end
			end, function()
				e.Enabled = false
				Debris:AddItem(holder, 1.3)
			end)
			RelicFx.ring(at - Vector3.new(0, 2.6, 0), a.radius or 10, color, 0.6)
		elseif kind == "Aura" then
			-- a storm cloud over the caster with rain falling through the radius
			local radius = a.radius or 14
			local cloud = part({ Size = Vector3.new(radius * 1.6, 2.2, radius * 1.6), Color = Color3.fromRGB(70, 78, 88), Material = Enum.Material.SmoothPlastic, Transparency = 0.25 })
			local e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(color)
			e.LightEmission = 0.3
			e.Size = NumberSequence.new(0.18)
			e.Lifetime = NumberRange.new(0.6, 0.8)
			e.Speed = NumberRange.new(35, 45)
			e.EmissionDirection = Enum.NormalId.Bottom
			e.Rate = 140
			e.Parent = cloud
			follow(a.duration or 5, function()
				local rr = rootOf(caster)
				if rr then
					cloud.CFrame = CFrame.new(rr.Position + Vector3.new(0, 16, 0))
				end
			end, function()
				e.Enabled = false
				fadeOut(cloud, 0.6)
			end)
		elseif kind == "Storm" then
			local center = at + dir * 3
			local swirl = {}
			for i = 1, 6 do
				table.insert(swirl, part({ Size = Vector3.new(1.2, 1, a.radius or 8), Color = if i % 2 == 0 then color else accent, Material = Enum.Material.SmoothPlastic, Transparency = 0.35 }))
			end
			follow(a.duration or 3, function(dt, elapsed)
				center += dir * (a.speed or 12) * dt
				for i, p in swirl do
					p.CFrame = CFrame.new(center + Vector3.new(0, i * 1.6 - 2, 0)) * CFrame.Angles(0, elapsed * 9 + i, 0) * CFrame.new(0, 0, -(1.5 + i * 0.4))
				end
			end, function()
				for _, p in swirl do
					fadeOut(p, 0.3)
				end
			end)
		elseif kind == "Hop" then
			RelicFx.puff(at - Vector3.new(0, 2.5, 0), color, 14, 10)
		elseif kind == "Burst" and a.fx.shape == "junkring" then
			RelicFx.ring(at - Vector3.new(0, 2.6, 0), a.radius or 12, accent, 0.5)
		end
	end)
	-- the junk ring rises around the caster during its windup
	if kind == "Burst" and a.fx.shape == "junkring" then
		local r = rootOf(caster)
		if r then
			for i = 0, 7 do
				local angle = i * math.pi / 4
				local p = part({ Size = Vector3.new(1.2, 1.2, 1.2), Color = color, Material = Enum.Material.CorrodedMetal, Transparency = 0 })
				local base = r.Position + Vector3.new(math.cos(angle) * 3, -2.5, math.sin(angle) * 3)
				p.CFrame = CFrame.new(base)
				tween(p, a.windup, { CFrame = CFrame.new(base + Vector3.new(0, 3, 0)) * CFrame.Angles(angle, angle, 0) })
				task.delay(a.windup, function()
					tween(p, 0.3, { CFrame = CFrame.new(base + Vector3.new(math.cos(angle) * 9, 3, math.sin(angle) * 9)), Transparency = 1 })
					Debris:AddItem(p, 0.35)
				end)
			end
		end
	end
end

local function onPhase(caster: Model, a: Relics.Ability, data: { [string]: any }, key: string)
	local color, accent = a.fx.color, a.fx.accent or a.fx.color
	local phase = data.phase
	local at: Vector3? = data.at
	if phase == "Pulse" and at then
		local radius = data.radius or a.radius or 10
		RelicFx.ring(at - Vector3.new(0, 2.6, 0), radius, color, 0.45)
		RelicFx.puff(at, accent, 14, 18)
		if a.fx.shape == "bigfist" then
			local fist = part({ Size = Vector3.new(6, 4, 6), Color = color, Material = Enum.Material.CorrodedMetal, Transparency = 0, CFrame = CFrame.new(at + Vector3.new(0, 14, 0)) })
			tween(fist, 0.12, { CFrame = CFrame.new(at + Vector3.new(0, 1, 0)) }, Enum.EasingStyle.Quad)
			task.delay(0.35, function()
				fadeOut(fist, 0.4)
			end)
		elseif a.fx.shape == "roar" then
			RelicFx.dome(at, radius, color, 0.5)
		end
	elseif (phase == "Land" or phase == "Follow" or phase == "Counter") and at then
		local radius = data.radius or a.radius or 8
		RelicFx.ring(at - Vector3.new(0, 2.6, 0), radius, color, 0.5)
		RelicFx.dome(at, radius * 0.6, accent, 0.35)
		RelicFx.puff(at, accent, 18, 20)
		if phase == "Land" and a.suppress then
			RelicFx.ring(at - Vector3.new(0, 2.6, 0), radius, accent, a.suppress, 0.15)
		end
	elseif phase == "Hit" and at then
		RelicFx.puff(at, accent, 8, 12)
	elseif phase == "Tidy" and at then
		RelicFx.ring(at, 6, color, 0.5)
		RelicFx.puff(at + Vector3.new(0, 2, 0), accent, 24, 10, 0.5)
	elseif phase == "End" and at then
		RelicFx.puff(at, accent, 20, 24)
	elseif phase == "Stop" or phase == "Bounce" then
		local list = projectiles[caster:GetFullName() .. key]
		local state = list and list[data.index or 1]
		if state then
			if phase == "Stop" then
				state.stop = true
			elseif typeof(data.to) == "Instance" then
				state.to = data.to
			end
		end
	end
end

function RelicFx.start()
	if started then return end
	started = true
	Remotes.get("RelicFx").OnClientEvent:Connect(function(caster, relicId, key, data)
		if typeof(caster) ~= "Instance" or not caster:IsA("Model") or typeof(data) ~= "table" then
			return
		end
		local j = Relics.get(relicId)
		local a = j and j.abilities[key]
		if not a then
			return
		end
		local mine = caster == Players.LocalPlayer.Character
		if data.phase == "Start" then
			RelicAnimator.play(caster, relicId, key, data.start)
			local cue = CAST_SOUND[a.kind] or "RelicCast"
			Audio.play(cue, caster, nil, if cue == "RelicHeal" then HEAL_PITCH else nil)
			onStart(caster, a, data, key)
		else
			RelicAnimator.phase(caster, relicId, key, data.phase)
			local at: Vector3? = if typeof(data.at) == "Vector3" then data.at else nil
			local phase = data.phase
			if at and (phase == "Pulse" or phase == "Land" or phase == "Follow" or phase == "Counter" or phase == "End") then
				Audio.play(if phase == "Land" then "Slam" else "RelicImpact", at)
			elseif at and phase == "Hit" then
				Audio.play("Hit", at)
				if mine then
					Audio.engage(nil)
				end
			elseif at and phase == "Tidy" then
				Audio.play("RelicHeal", at, nil, HEAL_PITCH)
			end
			onPhase(caster, a, data, key)
		end
	end)
end

return RelicFx
