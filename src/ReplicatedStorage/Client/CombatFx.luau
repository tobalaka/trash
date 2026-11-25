--!strict
--[[
	CombatFx - the particle side of movement and combat, built the way EXPED builds its hits:
	every effect is a stack of burst ParticleEmitters fired on the same frame from one invisible
	carrier (flash, wind rings, impact burst, rays, shards, dust), each layer doing one job.
	The sprites are our own (white on alpha, tinted here), made by trash-art/tools/fx_factory.py.

	Who sees what:
	  - the local player's moves call CombatFx directly from Movement (no lag);
	  - other players' dashes arrive as CombatResult "Dash" (CombatService);
	  - hits, blocks, parries, breaks, counters, wall splats and throws come from Feedback. Punch
	    effects play only when a hit lands (user 2026-10-25), never on a whiff;
	  - trails need no events: every character near the camera gets fist, body and leg trails
	    that switch on while that limb or body is moving fast (punches, dashes, wall jumps).
	EXPED pass (2026-10-25): craters (EXPED's two rings of ground-material slabs plus flung chunks)
	under crits, spikes, slams and executions; state flashes from EXPED's Highlights (hyper armor,
	i-frames, feint, crit warning, knocked, getting up); the gank aura; the crit's charge on the
	fist; corpses burning away to ash before they are cleaned up.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local CombatFx = {}
local IS_STUDIO = RunService:IsStudio()

local TEX = {
	Wind = "rbxassetid://129716424953002", -- 2x2 swirl wind rings
	Crescent = "rbxassetid://71208899671060", -- 2x2 crescent swishes
	Impact = "rbxassetid://99791436068850", -- 4x4 spiky burst that tears apart
	Rays = "rbxassetid://71283635830840", -- radial impact lines
	Speed = "rbxassetid://138082831052268", -- 2x2 speed-line bundles
	Shards = "rbxassetid://78673940695538", -- 2x2 chips / shards
	Ring = "rbxassetid://89065386229938", -- shockwave ring with a torn inner edge
	Glow = "rbxassetid://81051226888744",
	Trail = "rbxassetid://104671385808013",
	Dust = "rbxassetid://111822282284883", -- soft dust puff
	Smoke = "rbxassetid://71200049877074", -- 4x4 smoke flipbook
	Star = "rbxassetid://91379513585562", -- four-point flash star
}

local WHITE = Color3.new(1, 1, 1)
local COLOR = {
	Hit = Color3.fromRGB(255, 255, 255),
	Heavy = Color3.fromRGB(255, 236, 214),
	Blocked = Color3.fromRGB(150, 205, 255),
	Parry = Color3.fromRGB(255, 214, 90),
	Break = Color3.fromRGB(255, 120, 50),
	Counter = Color3.fromRGB(255, 190, 60),
	Dodge = Color3.fromRGB(150, 235, 255),
	Dust = Color3.fromRGB(196, 182, 156),
}

-- ── layer player ──────────────────────────────────────────────────────────────

-- the baked ease-out EXPED uses on almost every Size curve: snap big, then settle
local EASE = { { 0, 0 }, { 0.08, 0.45 }, { 0.17, 0.61 }, { 0.25, 0.70 }, { 0.33, 0.75 }, { 0.42, 0.80 }, { 0.5, 0.83 }, { 0.67, 0.90 }, { 0.83, 0.95 }, { 1, 1 } }

local function ease(from: number, to: number, env: number?): NumberSequence
	local k = {}
	for _, p in EASE do
		table.insert(k, NumberSequenceKeypoint.new(p[1], from + (to - from) * p[2], env or 0))
	end
	return NumberSequence.new(k)
end

local function seq(...: number): NumberSequence
	local a = { ... }
	local k = {}
	for i = 1, #a, 2 do
		table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(k)
end

-- rings: start solid, thin out fast (EXPED Shockwave / Wind transparency)
local RING_TR = seq(0, 0.15, 0.16, 0.5, 0.32, 0.78, 1, 1)
local WIND_TR = seq(0, 1, 0.12, 0.1, 0.28, 0.6, 0.6, 0.93, 1, 1)
local FLASH_TR = seq(0, 0, 0.6, 0.2, 1, 1)
local SPARK_TR = seq(0, 0, 0.55, 0, 0.6, 1, 1, 1) -- visible, then a hard blink-out
local SMOKE_TR = seq(0, 1, 0.09, 0.5, 0.3, 0.45, 0.72, 0.8, 1, 1)
local DUST_TR = seq(0, 0.35, 0.5, 0.7, 1, 1)

type Layer = { [string]: any }

local FLIP = {
	["2x2"] = Enum.ParticleFlipbookLayout.Grid2x2,
	["4x4"] = Enum.ParticleFlipbookLayout.Grid4x4,
}
local ORI = {
	face = Enum.ParticleOrientation.FacingCamera,
	par = Enum.ParticleOrientation.VelocityParallel,
	perp = Enum.ParticleOrientation.VelocityPerpendicular,
}

local fxFolder: Folder? = nil
local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = workspace:FindFirstChild("CombatFxLocal")
	if not f then
		f = Instance.new("Folder")
		f.Name = "CombatFxLocal"
		f.Parent = workspace
	end
	fxFolder = f :: Folder
	return f :: Folder
end

local function scaled(s: NumberSequence, m: number): NumberSequence
	if m == 1 then
		return s
	end
	local k = {}
	for _, p in s.Keypoints do
		table.insert(k, NumberSequenceKeypoint.new(p.Time, p.Value * m, p.Envelope * m))
	end
	return NumberSequence.new(k)
end

local function emitter(att: Attachment, s: Layer, scale: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.Rate = 0
	e.Texture = s.tex
	if s.flip then
		e.FlipbookLayout = FLIP[s.flip]
		if s.flip == "2x2" then
			-- one random frame per particle, held for its whole life
			e.FlipbookMode = Enum.ParticleFlipbookMode.Loop
			e.FlipbookFramerate = NumberRange.new(0)
			e.FlipbookStartRandom = true
		else
			e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		end
	end
	local c = s.color or WHITE
	e.Color = if typeof(c) == "ColorSequence" then c else ColorSequence.new(c)
	e.Size = scaled(s.size or NumberSequence.new(1), scale)
	e.Transparency = s.tr or NumberSequence.new(0)
	e.Lifetime = NumberRange.new(s.life[1], s.life[2])
	local sp = s.speed or { 0.01, 0.01 }
	e.Speed = NumberRange.new(sp[1] * scale, sp[2] * scale)
	e.SpreadAngle = s.spread or Vector2.zero
	e.EmissionDirection = s.dir or Enum.NormalId.Top
	e.Orientation = ORI[s.ori or "face"]
	local r = s.rot or { -180, 180 }
	e.Rotation = NumberRange.new(r[1], r[2])
	local rs = s.rotSpeed or { 0, 0 }
	e.RotSpeed = NumberRange.new(rs[1], rs[2])
	e.Drag = s.drag or 0
	e.Acceleration = (s.acc or Vector3.zero) * scale
	e.LightEmission = s.le or 0
	e.LightInfluence = s.li or 0
	e.Brightness = s.br or 1
	e.ZOffset = s.z or 0
	if s.squash then
		e.Squash = s.squash
	end
	e.TimeScale = s.timeScale or 1
	e.Parent = att
	return e
end

-- Fires a layer stack at `cf` (the attachment's +Y is the emission axis). Cleans itself up.
function CombatFx.play(cf: CFrame, layers: { Layer }, scale: number?)
	local m = scale or 1
	local host = Instance.new("Part")
	host.Name = "Fx"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.CastShadow = false
	host.Transparency = 1
	host.Size = Vector3.one * 0.2
	host.CFrame = cf
	local att = Instance.new("Attachment")
	att.Parent = host
	host.Parent = folder()
	local longest = 0
	for _, s in layers do
		local a = att
		if s.offset then
			a = Instance.new("Attachment")
			a.CFrame = s.offset
			a.Parent = host
		end
		local e = emitter(a, s, m)
		local delay = s.delay or 0
		longest = math.max(longest, delay + s.life[2] / (s.timeScale or 1))
		if delay > 0 then
			task.delay(delay, function()
				if e.Parent then
					e:Emit(s.n or 1)
				end
			end)
		else
			e:Emit(s.n or 1)
		end
	end
	task.delay(longest + 0.3, function()
		-- QA (Studio only): workspace attribute QAFreezeFx keeps effects alive for screenshots
		while IS_STUDIO and workspace:GetAttribute("QAFreezeFx") do
			task.wait(0.25)
		end
		host:Destroy()
	end)
end

-- a frame whose +Y points along `axis` (VelocityPerpendicular rings then face along it)
local function along(at: Vector3, axis: Vector3): CFrame
	if axis.Magnitude < 1e-3 then
		return CFrame.new(at)
	end
	local up = axis.Unit
	local ref = if math.abs(up.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local right = ref:Cross(up).Unit
	local back = right:Cross(up).Unit
	return CFrame.fromMatrix(at, right, up, back)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

local function ignoreList(): { Instance }
	local list: { Instance } = { folder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, name in { "Mobs", "NPCs", "Townsfolk", "RelicFxLocal", "TrainingDummies" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

-- the ground (position, colour) under a point, or nil if it's further than `reach`
local function groundBelow(p: Vector3, reach: number): (Vector3?, Color3?)
	rayParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(p + Vector3.new(0, 1, 0), Vector3.new(0, -(reach + 1), 0), rayParams)
	if not hit then
		return nil, nil
	end
	local color = if hit.Instance:IsA("BasePart") then hit.Instance.Color else COLOR.Dust
	if hit.Instance == workspace.Terrain then
		color = workspace.Terrain:GetMaterialColor(hit.Material)
	end
	return hit.Position, color
end

local function dustTint(c: Color3?): Color3
	-- dust is the ground's own colour, lifted toward a pale haze so it reads on dark floors too
	return (c or COLOR.Dust):Lerp(Color3.fromRGB(226, 218, 204), 0.45)
end

-- ── building blocks (EXPED numbers, scaled for 5-stud R6 bodies) ─────────────

local function windRings(n: number, size: number, life: number, color: Color3?, extra: Layer?): Layer
	local l: Layer = {
		tex = TEX.Wind, flip = "2x2", ori = "perp", spread = Vector2.new(32, 32),
		size = ease(0, size, size * 0.15), tr = WIND_TR, life = { life * 0.35, life },
		rotSpeed = { -260, 260 }, le = 1, br = 1.4, color = color, n = n, z = 1,
	}
	if extra then
		for k, v in extra do
			l[k] = v
		end
	end
	return l
end

local function flash(size: number, color: Color3?, br: number?): Layer
	return {
		tex = TEX.Impact, flip = "4x4", size = ease(size * 0.4, size), tr = FLASH_TR, life = { 0.16, 0.2 },
		le = 1, br = br or 1.6, color = color, z = 4, n = 1,
	}
end

local function star(size: number, color: Color3?): Layer
	return {
		tex = TEX.Star, size = seq(0, 0, 0.35, size, 1, 0), tr = seq(0, 0, 1, 0), life = { 0.07, 0.1 },
		le = 1, br = 3, color = color, z = 5, n = 1, rot = { 0, 90 },
	}
end

local function rays(size: number, color: Color3?): Layer
	return {
		tex = TEX.Rays, size = ease(size * 0.3, size, size * 0.1), tr = seq(0, 0.2, 0.3, 0.45, 1, 1),
		life = { 0.14, 0.24 }, le = 1, br = 1.3, color = color, z = 3, n = 1, timeScale = 0.8,
	}
end

local function shards(n: number, speed: number, color: Color3?, size: number?): Layer
	local s = size or 0.45
	return {
		tex = TEX.Shards, flip = "2x2", ori = "par", spread = Vector2.new(70, 70),
		size = seq(0, s, 0.3, s * 0.7, 1, 0), tr = SPARK_TR, life = { 0.25, 0.5 },
		speed = { speed * 0.4, speed }, drag = 6, acc = Vector3.new(0, -40, 0),
		rotSpeed = { -400, 400 }, le = 1, br = 3, color = color, z = 2, n = n,
	}
end

local function shock(size: number, life: number, color: Color3?, ori: string?): Layer
	return {
		tex = TEX.Ring, ori = ori or "perp", size = ease(0, size), tr = RING_TR, life = { life * 0.8, life },
		rotSpeed = { -120, 120 }, le = 1, li = 0.2, br = 1.2, color = color, z = 1, n = 1,
	}
end

local function puffs(n: number, size: number, speed: number, color: Color3?): Layer
	return {
		tex = TEX.Dust, size = ease(size * 0.4, size, size * 0.2), tr = DUST_TR, life = { 0.35, 0.7 },
		speed = { speed * 0.3, speed }, spread = Vector2.new(80, 80), drag = 7, acc = Vector3.new(0, 4, 0),
		li = 0.6, br = 1, color = color or COLOR.Dust, z = -0.3, n = n,
	}
end

local function smoke(n: number, size: number, color: Color3?): Layer
	return {
		tex = TEX.Smoke, flip = "4x4", size = ease(size * 0.4, size, size * 0.25), tr = SMOKE_TR,
		life = { 0.7, 1.2 }, speed = { 3, 10 }, spread = Vector2.new(90, 90), drag = 5, acc = Vector3.new(0, 3, 0),
		li = 0.5, br = 0.8, color = color or COLOR.Dust, z = -0.5, n = n, timeScale = 0.8,
	}
end

-- ── combat ────────────────────────────────────────────────────────────────────

local function rootOf(model: Model?): BasePart?
	local part = if model then model:FindFirstChild("HumanoidRootPart") else nil
	return if part and part:IsA("BasePart") then part else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.zero
end

-- EXPED "FistsM1": air-pressure rings around the punch axis at the contact, on a landed hit
local function punchRings(heavy: boolean): { Layer }
	return {
		windRings(if heavy then 5 else 3, if heavy then 5.5 else 4, 0.32),
		windRings(2, if heavy then 7.5 else 5.5, 0.14, nil, { rotSpeed = { 500, 900 }, br = 1 }),
		{
			tex = TEX.Crescent, flip = "2x2", ori = "perp", size = ease(1, if heavy then 5 else 3.8),
			tr = seq(0, 0, 0.5, 0.4, 1, 1), life = { 0.12, 0.16 }, rotSpeed = { 700, 1100 },
			le = 1, br = 2.2, z = 1.1, n = 1,
		},
	}
end

-- EXPED "Uppercut": a rising column of wind rings and streaks under a launched body
function CombatFx.launch(at: Vector3)
	CombatFx.play(along(at - Vector3.new(0, 2, 0), Vector3.yAxis), {
		windRings(5, 5.5, 0.5, nil, { speed = { 14, 30 }, drag = 4, spread = Vector2.new(8, 8) }),
		windRings(2, 9, 0.22, nil, { rotSpeed = { 600, 1000 } }),
		{
			tex = TEX.Speed, flip = "2x2", ori = "par", size = seq(0, 0, 0.1, 3.4, 1, 2),
			tr = seq(0, 0, 0.6, 0.3, 1, 1), life = { 0.12, 0.22 }, speed = { 30, 60 }, drag = 10,
			spread = Vector2.new(12, 12), rot = { 90, 90 }, le = 1, br = 2, n = 6, z = 1,
		},
	})
end

-- EXPED "Smash" at the ground under a slam (aerial slam, bury throw, heavy landings)
function CombatFx.slam(at: Vector3, scale: number?)
	local m = scale or 1
	local ground, color = groundBelow(at, 12)
	if not ground then
		return
	end
	local dust = dustTint(color)
	CombatFx.play(CFrame.new(ground + Vector3.new(0, 0.2, 0)), {
		star(9, WHITE),
		shock(16, 0.55, WHITE),
		shock(24, 0.3, Color3.fromRGB(210, 210, 210)),
		windRings(3, 18, 0.45, nil, { spread = Vector2.zero, rotSpeed = { 250, 500 }, br = 1 }),
		puffs(14, 4.5, 34, dust),
		smoke(6, 7, dust),
		shards(16, 70, color, 0.6),
	}, m)
end

-- Hits, blocks, parries, breaks and counters at a contact point. `dir` points from the
-- attacker into the target.
function CombatFx.impact(kind: string, at: Vector3, dir: Vector3, heavy: boolean?)
	local d = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.zAxis
	local cf = along(at, d)
	if kind == "Hit" then
		local c = if heavy then COLOR.Heavy else COLOR.Hit
		local m = if heavy then 1.45 else 1
		-- the punch's air-pressure rings face back along the blow, a little in front of the body
		CombatFx.play(along(at - d * 0.8, d), punchRings(heavy == true))
		CombatFx.play(cf, {
			flash(3.2, c),
			star(4, c),
			rays(5.5, c),
			shock(4, 0.2, c),
			windRings(3, 4.5, 0.24, nil, { spread = Vector2.new(360, 360), rotSpeed = { 100, 900 }, br = 1 }),
			windRings(1, 7, 0.09, nil, { spread = Vector2.new(30, 30), rotSpeed = { 1200, 2000 }, br = 0.8 }),
			shards(if heavy then 12 else 7, 40, c, 0.35),
		}, m)
	elseif kind == "Blocked" then
		CombatFx.play(cf, {
			flash(2.6, COLOR.Blocked, 1.4),
			shock(3.6, 0.2, COLOR.Blocked),
			{
				tex = TEX.Shards, flip = "2x2", ori = "par", spread = Vector2.new(65, 65), dir = Enum.NormalId.Bottom,
				size = seq(0, 0.35, 0.3, 0.2, 1, 0), tr = SPARK_TR, life = { 0.35, 0.65 },
				speed = { 10, 42 }, drag = 3, acc = Vector3.new(0, -38, 0), le = 1, br = 4,
				color = COLOR.Blocked, z = 2, n = 12,
			},
		})
	elseif kind == "Parry" then
		CombatFx.play(cf, {
			star(6, COLOR.Parry),
			flash(4, COLOR.Parry, 2),
			shock(5.5, 0.3, COLOR.Parry),
			windRings(3, 5.5, 0.3, COLOR.Parry, { spread = Vector2.new(360, 360) }),
			{
				tex = TEX.Shards, flip = "2x2", ori = "par", spread = Vector2.new(100, 100),
				size = seq(0, 0.4, 0.1, 0.3, 0.5, 0.08, 1, 0), tr = SPARK_TR, life = { 0.5, 0.9 },
				speed = { 20, 70 }, drag = 7, acc = Vector3.new(0, -60, 0), le = 1, br = 5,
				color = COLOR.Parry, z = 2, n = 22,
			},
			{
				tex = TEX.Glow, size = NumberSequence.new(5), tr = seq(0, 1, 0.1, 0.5, 1, 1), life = { 0.3, 0.4 },
				le = 1, br = 1.2, color = COLOR.Parry, z = -1, n = 1,
			},
		})
	elseif kind == "Break" then
		CombatFx.play(cf, {
			star(7, COLOR.Break),
			flash(5, COLOR.Break, 2),
			rays(7.5, COLOR.Break),
			shock(7, 0.35, COLOR.Break),
			shock(10, 0.16, WHITE),
			windRings(4, 6.5, 0.34, nil, { spread = Vector2.new(360, 360) }),
			shards(22, 55, COLOR.Break, 0.5),
			smoke(3, 4, Color3.fromRGB(120, 110, 104)),
		})
	elseif kind == "Counter" then
		CombatFx.play(cf, {
			star(5.5, COLOR.Counter),
			{
				tex = TEX.Crescent, flip = "2x2", ori = "perp", size = ease(1, 6),
				tr = seq(0, 0, 0.5, 0.35, 1, 1), life = { 0.2, 0.25 }, rotSpeed = { 850, 1300 },
				le = 1, br = 3, color = COLOR.Counter, z = 1, n = 2,
			},
			rays(7, COLOR.Counter),
			shards(12, 46, COLOR.Counter),
		})
	end
end

-- a perfect dodge: a cyan wind burst where the body was
function CombatFx.evade(at: Vector3)
	CombatFx.play(CFrame.new(at), {
		windRings(4, 7, 0.4, COLOR.Dodge, { spread = Vector2.new(360, 360) }),
		{
			tex = TEX.Glow, size = NumberSequence.new(6), tr = seq(0, 1, 0.1, 0.5, 1, 1), life = { 0.3, 0.4 },
			le = 1, br = 1.2, color = COLOR.Dodge, n = 1,
		},
	})
end

-- a body slammed into a wall: dust ring on the wall, rays, chips in the wall's colour
function CombatFx.wallSplat(at: Vector3, outward: Vector3)
	local n = if outward.Magnitude > 1e-3 then outward.Unit else Vector3.yAxis
	rayParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(at + n * 2, -n * 4, rayParams)
	local color = if hit and hit.Instance:IsA("BasePart") then hit.Instance.Color else COLOR.Dust
	CombatFx.play(along(at + n * 0.3, n), {
		star(8, WHITE),
		rays(10, WHITE),
		shock(9, 0.45, dustTint(color)),
		windRings(3, 10, 0.4, nil, { spread = Vector2.zero }),
		puffs(10, 3.5, 22, dustTint(color)),
		shards(14, 50, color, 0.55),
	})
end

-- ── movement ──────────────────────────────────────────────────────────────────

local function feetOf(character: Model): Vector3?
	local root = rootOf(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return nil
	end
	return root.Position - Vector3.new(0, root.Size.Y / 2 + hum.HipHeight + 2, 0)
end

-- EXPED "DodgeGround" + air dash: a wind ring left behind, speed lines, a dust kick on the ground
function CombatFx.dash(character: Model, direction: Vector3, air: boolean)
	local root = rootOf(character)
	if not root then
		return
	end
	local d = if direction.Magnitude > 1e-3 then direction.Unit else flat(root.CFrame.LookVector)
	local layers: { Layer } = {
		windRings(3, if air then 7 else 5, 0.35, nil, { offset = CFrame.new(0, -1.2, 0) }),
		windRings(1, if air then 11 else 8, 0.14, nil, { rotSpeed = { 900, 1400 }, br = 1 }),
		{
			-- speed lines streaming back past the body
			tex = TEX.Speed, flip = "2x2", ori = "par", dir = Enum.NormalId.Bottom, spread = Vector2.new(14, 14),
			size = seq(0, 0, 0.15, 2.6, 1, 1.6), tr = seq(0, 0, 0.5, 0.3, 1, 1), life = { 0.1, 0.18 },
			speed = { 40, 70 }, drag = 12, rot = { 90, 90 }, le = 1, br = 1.6, z = 1, n = 7,
			offset = CFrame.new(0, 2, 0),
		},
	}
	if air then
		table.insert(layers, flash(3, Color3.fromRGB(220, 240, 255), 1.5))
	end
	CombatFx.play(along(root.Position, d), layers)
	if not air then
		local feet = feetOf(character)
		local ground, color = if feet then groundBelow(feet + Vector3.new(0, 1, 0), 3) else nil, nil
		if ground then
			local dust = dustTint(color)
			-- dust kicked backwards, low and flat
			CombatFx.play(along(ground + Vector3.new(0, 0.6, 0), -d + Vector3.new(0, 0.35, 0)), {
				puffs(7, 2.6, 26, dust),
				smoke(2, 3.5, dust),
			})
		end
	end
end

-- a double jump / wall jump push: a ring under the feet (or on the wall)
function CombatFx.jump(character: Model, normal: Vector3?)
	local root = rootOf(character)
	if not root then
		return
	end
	if normal then
		CombatFx.play(along(root.Position + Vector3.new(0, -0.5, 0) - normal * 1.2, normal), {
			windRings(3, 6, 0.35),
			shock(5, 0.3, WHITE),
			puffs(5, 2.2, 14),
		})
		return
	end
	CombatFx.play(along(root.Position - Vector3.new(0, 3, 0), Vector3.yAxis), {
		windRings(3, 5.5, 0.35, nil, { spread = Vector2.new(6, 6) }),
		windRings(1, 8, 0.14, nil, { spread = Vector2.zero, rotSpeed = { 900, 1300 }, br = 1 }),
	})
end

-- a hard landing: a flat dust ring and puffs (scaled by how hard)
function CombatFx.land(character: Model, impact: number)
	local feet = feetOf(character)
	if not feet then
		return
	end
	local ground, color = groundBelow(feet + Vector3.new(0, 1, 0), 4)
	if not ground then
		return
	end
	local m = math.clamp(impact / 80, 0.6, 1.4)
	local dust = dustTint(color)
	CombatFx.play(CFrame.new(ground + Vector3.new(0, 0.2, 0)), {
		shock(9, 0.45, dust),
		windRings(2, 9, 0.3, nil, { spread = Vector2.zero, br = 0.8 }),
		puffs(9, 2.8, 22, dust),
	}, m)
end

-- the colour of the wall just behind `normal` from `at` (for wall dust and chips)
local function wallColor(at: Vector3, normal: Vector3): Color3
	rayParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(at + normal * 1.5, -normal * 4, rayParams)
	if hit and hit.Instance:IsA("BasePart") then
		return hit.Instance.Color
	end
	return COLOR.Dust
end

local function wallSpecks(n: number, color: Color3): Layer
	-- EXPED "Specs": tiny dark chips kicked off the surface, falling
	return {
		tex = TEX.Shards, flip = "2x2", size = seq(0, 0, 0.29, 0.22, 1, 0), life = { 0.25, 0.6 },
		speed = { 5, 34 }, spread = Vector2.new(70, 70), drag = 4.5, acc = Vector3.new(0, -30, 0),
		rotSpeed = { 30, 190 }, li = 1, br = 0.6, color = color:Lerp(Color3.new(0, 0, 0), 0.35), z = 1.5, n = n,
	}
end

-- grabbing a wall (wall climb start, wall run start): faint wind rings on the wall, a dust plume
-- and chips in the wall's colour (EXPED "WallClimb")
function CombatFx.wallGrab(character: Model, normal: Vector3)
	local root = rootOf(character)
	if not root or normal.Magnitude < 1e-3 then
		return
	end
	local n = normal.Unit
	local at = root.Position - n * 1.1
	local color = wallColor(at, n)
	local dust = dustTint(color)
	CombatFx.play(along(at, n), {
		windRings(2, 5, 0.4, nil, { tr = seq(0, 1, 0.12, 0.45, 0.5, 0.85, 1, 1), spread = Vector2.new(16, 16) }),
		puffs(5, 1.8, 14, dust),
		smoke(1, 2.4, dust),
		wallSpecks(10, color),
	})
end

-- a hand or foot on the wall while climbing / running along it: a small puff and a few chips
function CombatFx.wallStep(character: Model, normal: Vector3, low: boolean?)
	local root = rootOf(character)
	if not root or normal.Magnitude < 1e-3 then
		return
	end
	local n = normal.Unit
	local at = root.Position - n * 1.1 + Vector3.new(0, if low then -2.2 else 0.4, 0)
	local color = wallColor(at, n)
	CombatFx.play(along(at, n), {
		puffs(2, 1.8, 8, dustTint(color)),
		wallSpecks(4, color),
	})
end

-- a slide: a dust spray at the feet for as long as it lasts; returns the stop function
function CombatFx.slide(character: Model, direction: Vector3): () -> ()
	local root = rootOf(character)
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not root or not hum then
		return function() end
	end
	local feet = feetOf(character)
	local _, color = groundBelow((feet or root.Position) + Vector3.new(0, 1, 0), 4)
	local dust = dustTint(color)
	local a = Instance.new("Attachment")
	a.Name = "FxSlide"
	-- at the heels, the emission axis tilted back and up
	local back = -(if direction.Magnitude > 1e-3 then direction.Unit else flat(root.CFrame.LookVector))
	local axis = root.CFrame:VectorToObjectSpace((back + Vector3.new(0, 0.5, 0)).Unit)
	local up = axis
	local ref = if math.abs(up.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local right = ref:Cross(up).Unit
	a.CFrame = CFrame.fromMatrix(Vector3.new(0, -(root.Size.Y / 2 + hum.HipHeight + 1.6), 0), right, up, right:Cross(up).Unit)
	a.Parent = root
	local spray = emitter(a, puffs(1, 2.2, 14, dust), 1)
	spray.Rate = 34
	spray.Enabled = true
	local chips = emitter(a, wallSpecks(1, color or COLOR.Dust), 1)
	chips.Rate = 22
	chips.Enabled = true
	CombatFx.play(along((feet or root.Position) + Vector3.new(0, 0.4, 0), back + Vector3.new(0, 0.4, 0)), {
		puffs(6, 2.6, 22, dust),
	})
	local stopped = false
	return function()
		if stopped then
			return
		end
		stopped = true
		spray.Enabled = false
		chips.Enabled = false
		task.delay(0.9, function()
			a:Destroy()
		end)
	end
end

-- ── craters and debris (EXPED RockModule2.OnGround2 + FlyingRocksV2.FlyingDebris) ───────

local function surfaceAt(p: Vector3, reach: number): RaycastResult?
	rayParams.FilterDescendantsInstances = ignoreList()
	local hit = workspace:Raycast(p + Vector3.new(0, 3, 0), Vector3.new(0, -(reach + 3), 0), rayParams)
	if hit and hit.Normal.Y > 0.55 then
		return hit
	end
	return nil
end

-- the ground's own look on a chunk: material, painted variant and colour (terrain: its colour)
local function dressLike(part: BasePart, hit: RaycastResult)
	local src = hit.Instance
	if src == workspace.Terrain then
		part.Material = hit.Material
		part.Color = workspace.Terrain:GetMaterialColor(hit.Material)
	elseif src:IsA("BasePart") then
		part.Material = src.Material
		part.MaterialVariant = src.MaterialVariant
		part.Color = src.Color
	end
end

local function chunkPart(size: Vector3, hit: RaycastResult, wedge: boolean): Part
	local part = Instance.new("Part")
	part.Name = "FxRock"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Size = size
	part.Shape = if wedge then Enum.PartType.Wedge else Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	dressLike(part, hit)
	return part
end

-- one ring of `count` slabs `dist` (+ `offset`) out from `center`, each facing it and tipped back
-- 15-35 deg, popping out of the ground and sinking away after about `hold` seconds
local function rockRing(center: Vector3, count: number, dist: number, size: number, offset: number, hold: number)
	local angle = math.random() * 360
	for _ = 1, count do
		local cf = CFrame.new(center) * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(offset, 0, offset + dist)
		angle += 360 / count
		local hit = surfaceAt(cf.Position + Vector3.new(0, 2, 0), 6)
		if not hit then
			continue
		end
		local base = Vector3.new(cf.Position.X, hit.Position.Y, cf.Position.Z)
		local width = math.random(math.max(1, math.round(size * 0.7)), math.max(1, math.round(size * 1.5)))
		local depth = size * (0.5 + math.random())
		local height = 1 + size * 1.5
		local face = CFrame.lookAt(base, Vector3.new(center.X, base.Y, center.Z))
			* CFrame.Angles(math.rad(-math.random(15, 35)), 0, 0)
		-- half of it below the ground, the way EXPED seats them
		local final = face * CFrame.new(0, (1 - height) / 2 + 0.5, 0)
		local part = chunkPart(Vector3.new(width, height, depth), hit, false)
		part.CFrame = final * CFrame.new(0, -height * 0.6, 0)
		part.Parent = folder()
		TweenService:Create(part, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = final }):Play()
		task.delay(hold + math.random() * 2.5, function()
			while IS_STUDIO and workspace:GetAttribute("QAFreezeFx") do
				task.wait(0.25)
			end
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					CFrame = final * CFrame.new(0, -height - 0.5, 0),
				}):Play()
				task.delay(1.7, function()
					part:Destroy()
				end)
			end
		end)
	end
end

type Flying = { part: BasePart, vel: Vector3, spin: CFrame, born: number, life: number, size: Vector3 }
local flying: { Flying } = {}

-- chunks flung out of the impact: a tiny gravity / bounce simulation on anchored parts, so they
-- never push anyone and cost nothing on the server
local function fling(at: Vector3, hit: RaycastResult, count: number, size: Vector3, speed: number, rise: number)
	for _ = 1, count do
		local s = size * (0.7 + math.random() * 0.45)
		local part = chunkPart(s, hit, math.random() < 0.3)
		part.CFrame = CFrame.new(at + Vector3.new(0, 0.6, 0)) * CFrame.Angles(math.random() * 6.3, math.random() * 6.3, 0)
		part.Parent = folder()
		local dir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.xAxis
		table.insert(flying, {
			part = part,
			vel = dir * speed * (0.6 + math.random() * 0.4) + Vector3.new(0, rise * (0.7 + math.random() * 0.5), 0),
			spin = CFrame.Angles((math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.5, (math.random() - 0.5) * 0.5),
			born = os.clock(),
			life = 4 + math.random() * 2.5,
			size = s,
		})
	end
end

local function stepFlying(dt: number)
	if #flying == 0 then
		return
	end
	local now = os.clock()
	rayParams.FilterDescendantsInstances = ignoreList()
	local parts, cframes = {}, {}
	for i = #flying, 1, -1 do
		local f = flying[i]
		local part = f.part
		local age = now - f.born
		if not part.Parent or age > f.life + 1.2 then
			part:Destroy()
			table.remove(flying, i)
			continue
		end
		local cf = part.CFrame
		if f.vel.Magnitude > 0.5 then
			f.vel += Vector3.new(0, -workspace.Gravity * dt, 0)
			local move = f.vel * dt
			local hit = workspace:Raycast(cf.Position, move + move.Unit * (f.size.Y * 0.5), rayParams)
			if hit then
				-- bounce off what it struck, losing most of the speed
				f.vel = (f.vel - 2 * f.vel:Dot(hit.Normal) * hit.Normal) * 0.35
				if hit.Normal.Y > 0.6 and f.vel.Magnitude < 6 then
					f.vel = Vector3.zero
				end
				cf = CFrame.new(hit.Position + hit.Normal * (f.size.Y * 0.5)) * cf.Rotation
			else
				cf = (cf + move) * f.spin
			end
		end
		if age > f.life and part.Size.Y > 0.05 then
			-- shrink away (EXPED: 1.5 s to a tenth)
			local k = math.clamp(1 - (age - f.life) / 1.2, 0.05, 1)
			part.Size = f.size * k
		end
		table.insert(parts, part)
		table.insert(cframes, cf)
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

-- EXPED's crater: two rings of slabs (6 at ~6 studs, 4 bigger at ~8.6) plus flung cubes and plates.
-- `m` scales the whole thing (crit 1, spike 1.1, slams 0.85).
function CombatFx.crater(at: Vector3, m: number?)
	local k = m or 1
	local hit = surfaceAt(at, 14)
	if not hit then
		return
	end
	local center = hit.Position
	rockRing(center, 6, 4 * k, 3 * k, 1.7 * k, 2.5)
	rockRing(center, 4, 6 * k, 3.6 * k, 2.3 * k, 2.5)
	fling(center, hit, math.random(4, 7), Vector3.one * 0.9 * k, 26, 30)
	fling(center, hit, math.random(1, 2), Vector3.new(2.6, 0.45, 1.8) * k, 22, 26)
end

-- ── fighter states (EXPED's Highlights folder) ───────────────────────────────

type Look = { fill: Color3, fillT: number, outline: Color3, outlineT: number }
local LOOKS: { [string]: Look } = {
	HyperArmor = { fill = Color3.fromRGB(255, 0, 0), fillT = 0.55, outline = Color3.fromRGB(255, 0, 0), outlineT = 0.4 },
	IFrame = { fill = Color3.fromRGB(193, 226, 255), fillT = 0.5, outline = WHITE, outlineT = 0.7 },
	Feint = { fill = Color3.fromRGB(241, 241, 241), fillT = 0.2, outline = Color3.fromRGB(168, 168, 168), outlineT = 0.8 },
	Crit = { fill = Color3.fromRGB(255, 0, 0), fillT = 0.55, outline = Color3.fromRGB(255, 0, 0), outlineT = 0 },
	Knocked = { fill = Color3.fromRGB(162, 0, 0), fillT = 0.35, outline = Color3.fromRGB(80, 0, 0), outlineT = 0 },
	GetUp = { fill = Color3.fromRGB(45, 220, 14), fillT = 0.5, outline = Color3.fromRGB(10, 152, 0), outlineT = 0 },
	Gank = { fill = Color3.fromRGB(255, 170, 0), fillT = 0.75, outline = Color3.fromRGB(255, 170, 0), outlineT = 0.35 },
}

-- Tints `model` with one of the LOOKS. `hold` > 0 fades it out over that time; nil keeps it until
-- CombatFx.unmark. One highlight per look per model.
function CombatFx.mark(model: Model?, look: string, hold: number?)
	local l = LOOKS[look]
	if not model or not model.Parent or not l then
		return
	end
	local name = "FxState" .. look
	local h = model:FindFirstChild(name) :: Highlight?
	if not h then
		local made = Instance.new("Highlight")
		made.Name = name
		made.DepthMode = Enum.HighlightDepthMode.Occluded
		made.Adornee = model
		made.Parent = model
		h = made
	end
	local hl = h :: Highlight
	hl.FillColor = l.fill
	hl.OutlineColor = l.outline
	hl.FillTransparency = l.fillT
	hl.OutlineTransparency = l.outlineT
	if hold then
		local tween = TweenService:Create(hl, TweenInfo.new(hold, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			FillTransparency = 1,
			OutlineTransparency = 1,
		})
		tween:Play()
		tween.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed and hl.FillTransparency >= 0.999 then
				hl:Destroy()
			end
		end)
	end
end

function CombatFx.unmark(model: Model?, look: string)
	local h = model and model:FindFirstChild("FxState" .. look)
	if h then
		h:Destroy()
	end
end

-- EXPED "GankBuff": an orange glow and light around a fighter fighting two or more at once
local function gankAura(model: Model, on: boolean)
	local torso = model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local existing = torso:FindFirstChild("FxGank")
	if not on then
		if existing then
			for _, d in existing:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					d.Enabled = false
				elseif d:IsA("PointLight") then
					TweenService:Create(d, TweenInfo.new(0.4), { Brightness = 0 }):Play()
				end
			end
			task.delay(1, function()
				existing:Destroy()
			end)
		end
		CombatFx.unmark(model, "Gank")
		return
	end
	if existing then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "FxGank"
	a.Parent = torso
	local orange = Color3.fromRGB(255, 170, 0)
	local glow = emitter(a, {
		tex = TEX.Glow, size = seq(0, 2.2, 0.5, 3, 1, 0), tr = seq(0, 1, 0.3, 0.55, 1, 1), life = { 0.5, 1 },
		speed = { 0.5, 2 }, spread = Vector2.new(180, 180), le = 1, br = 1.2, color = orange, z = -0.5,
	}, 1)
	glow.Rate = 6
	glow.Enabled = true
	local sparks = emitter(a, {
		tex = TEX.Shards, flip = "2x2", ori = "par", size = seq(0, 0.25, 1, 0), tr = SPARK_TR, life = { 0.5, 1 },
		speed = { 3, 7 }, spread = Vector2.new(180, 180), acc = Vector3.new(0, 6, 0), le = 1, br = 3, color = orange,
	}, 1)
	sparks.Rate = 8
	sparks.Enabled = true
	local light = Instance.new("PointLight")
	light.Color = orange
	light.Range = 9
	light.Brightness = 1.4
	light.Parent = a
	CombatFx.mark(model, "Gank")
end

-- EXPED "FistCrit": the crit's charge on the striking fist, then a big blast on the hit
function CombatFx.critCharge(model: Model?, windup: number)
	local arm = model and model:FindFirstChild("Right Arm")
	if not arm or not arm:IsA("BasePart") then
		return
	end
	local a = Instance.new("Attachment")
	a.Name = "FxCritCharge"
	a.Position = Vector3.new(0, -1, 0)
	a.Parent = arm
	local red = Color3.fromRGB(255, 70, 50)
	local glow = emitter(a, {
		tex = TEX.Glow, size = seq(0, 0.6, 0.5, 2.6, 1, 0), tr = seq(0, 0.6, 0.4, 0.2, 1, 1), life = { 0.15, 0.25 },
		le = 1, br = 2, color = red, z = 2,
	}, 1)
	glow.Rate = 40
	glow.Enabled = true
	local suck = emitter(a, {
		tex = TEX.Speed, flip = "2x2", ori = "par", size = seq(0, 0.9, 1, 0.1), tr = seq(0, 0.3, 1, 1),
		life = { 0.12, 0.2 }, speed = { -22, -14 }, spread = Vector2.new(180, 180), le = 1, br = 2, color = red, z = 1,
	}, 1)
	suck.Rate = 30
	suck.Enabled = true
	task.delay(windup, function()
		glow.Enabled = false
		suck.Enabled = false
		task.delay(0.4, function()
			a:Destroy()
		end)
	end)
end

function CombatFx.critHit(at: Vector3, dir: Vector3)
	local d = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.zAxis
	local red = Color3.fromRGB(255, 90, 60)
	CombatFx.play(along(at - d * 0.8, d), punchRings(true), 1.5)
	CombatFx.play(along(at, d), {
		star(8, WHITE),
		flash(6, red, 2.2),
		rays(10, WHITE),
		shock(9, 0.32, WHITE),
		shock(10, 0.2, red),
		windRings(5, 8, 0.4, nil, { spread = Vector2.new(360, 360) }),
		shards(24, 70, red, 0.55),
	})
end

-- a body hitting the floor when it is knocked: a thud of dust and a few chips
function CombatFx.knocked(model: Model?)
	local root = rootOf(model)
	if not root then
		return
	end
	CombatFx.mark(model, "Knocked", 0.9)
	local ground, color = groundBelow(root.Position, 8)
	if ground then
		local dust = dustTint(color)
		CombatFx.play(CFrame.new(ground + Vector3.new(0, 0.2, 0)), {
			shock(9, 0.4, dust, "perp"),
			puffs(10, 3.5, 20, dust),
			smoke(3, 5, dust),
			shards(8, 30, color, 0.4),
		})
	end
end

-- an execution: one last heavy blow, a dark burst and embers rising off the body
function CombatFx.execute(model: Model?)
	local root = rootOf(model)
	if not root then
		return
	end
	local at = root.Position
	CombatFx.mark(model, "Knocked", 1.2)
	CombatFx.play(CFrame.new(at), {
		star(9, WHITE),
		flash(7, Color3.fromRGB(255, 80, 60), 2.4),
		shock(12, 0.35, WHITE, "face"),
		smoke(8, 6, Color3.fromRGB(40, 36, 38)),
		{
			tex = TEX.Glow, size = seq(0, 0.35, 1, 0), tr = seq(0, 0, 0.7, 0.2, 1, 1), life = { 0.8, 1.6 },
			speed = { 4, 12 }, spread = Vector2.new(60, 60), acc = Vector3.new(0, 8, 0), drag = 1.5,
			le = 1, br = 3, color = Color3.fromRGB(255, 140, 60), z = 1, n = 26,
		},
	})
	CombatFx.crater(at, 0.75)
end

-- a corpse (RagdollV3's copy) burns away to ash near the end of its life
local function dissolve(corpse: Model)
	local torso = corpse:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		CombatFx.play(torso.CFrame, {
			smoke(10, 6, Color3.fromRGB(44, 40, 42)),
			{
				tex = TEX.Glow, size = seq(0, 0.3, 1, 0), tr = seq(0, 0, 0.7, 0.3, 1, 1), life = { 1, 2 },
				speed = { 2, 7 }, spread = Vector2.new(70, 70), acc = Vector3.new(0, 6, 0),
				le = 1, br = 3, color = Color3.fromRGB(255, 120, 50), z = 1, n = 30,
			},
		})
	end
	for _, p in corpse:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			TweenService:Create(p, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
				Color = Color3.fromRGB(30, 28, 28),
			}):Play()
		elseif p:IsA("Decal") then
			TweenService:Create(p, TweenInfo.new(1.6), { Transparency = 1 }):Play()
		end
	end
end

local CORPSE_LIFE = 20 -- RagdollV3 cleanUpTime
local function watchCorpse(child: Instance)
	if child:IsA("Model") and child:FindFirstChild("RagdollHumanoid") then
		task.delay(CORPSE_LIFE - 2.2, function()
			if child.Parent then
				dissolve(child)
			end
		end)
	end
end

-- per fighter: the state flashes and the gank aura follow the server's attributes
local function watchStates(model: Model)
	if model:GetAttribute("FxStatesWatched") then
		return
	end
	model:SetAttribute("FxStatesWatched", true)
	model:GetAttributeChangedSignal("HyperArmor"):Connect(function()
		if model:GetAttribute("HyperArmor") == true then
			CombatFx.mark(model, "HyperArmor")
		else
			CombatFx.mark(model, "HyperArmor", 0.2)
		end
	end)
	model:GetAttributeChangedSignal("CombatState"):Connect(function()
		if model:GetAttribute("CombatState") == "Dodging" then
			CombatFx.mark(model, "IFrame", 0.35)
		end
	end)
	model:GetAttributeChangedSignal("Ganked"):Connect(function()
		gankAura(model, model:GetAttribute("Ganked") == true)
	end)
end

-- ── trails: on for fast limbs, nothing to network ────────────────────────────

type Rig = {
	model: Model,
	root: BasePart,
	body: Trail?,
	limbs: { { part: BasePart, trail: Trail, last: Vector3?, fist: boolean } },
}

local rigs: { [Model]: Rig } = {}

local function makeTrail(part: BasePart, a: Vector3, b: Vector3, life: number, width: number, transparency: number, name: string): Trail
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "A"
	a0.Position = a
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "B"
	a1.Position = b
	a1.Parent = part
	local t = Instance.new("Trail")
	t.Name = name
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Texture = TEX.Trail
	t.TextureMode = Enum.TextureMode.Stretch
	t.FaceCamera = true
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Brightness = 1.6
	t.Lifetime = life
	t.MinLength = 0.05
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, width) })
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, transparency), NumberSequenceKeypoint.new(1, 1) })
	t.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 222, 255))
	t.Enabled = false
	t.Parent = part
	return t
end

local function rig(model: Model): Rig?
	local root = rootOf(model)
	local torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
	if not root or not torso or not torso:IsA("BasePart") then
		return nil
	end
	local r: Rig = { model = model, root = root, body = nil, limbs = {} }
	r.body = makeTrail(torso, Vector3.new(0, 0.85, 0), Vector3.new(0, -0.85, 0), 0.22, 0.25, 0.45, "FxBodyTrail")
	for _, name in { "Right Arm", "Left Arm", "Right Leg", "Left Leg" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local fist = string.find(name, "Arm") ~= nil
			local trail = makeTrail(part, Vector3.new(0, -0.55, 0), Vector3.new(0, -0.95, 0),
				if fist then 0.14 else 0.18, 0, if fist then 0.25 else 0.45, "FxLimbTrail")
			table.insert(r.limbs, { part = part, trail = trail, last = nil, fist = fist })
		end
	end
	rigs[model] = r
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			rigs[model] = nil
		end
	end)
	return r
end

local BODY_SPEED = 29 -- horizontal studs/s: dashes, slides, wall runs (30), wall jumps (sprint is 26)
local RISE_SPEED = 42 -- upward: wall jumps, launches
local FIST_SPEED = 24 -- a fist moving this fast relative to the body is a punch
local TRAIL_RANGE = 220

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera or dt <= 0 then
		return
	end
	local eye = camera.CFrame.Position
	for model, r in rigs do
		local root = r.root
		if not root.Parent then
			rigs[model] = nil
			continue
		end
		local near = (root.Position - eye).Magnitude < TRAIL_RANGE
		local v = root.AssemblyLinearVelocity
		local fast = near and (Vector3.new(v.X, 0, v.Z).Magnitude > BODY_SPEED or v.Y > RISE_SPEED)
		if r.body and r.body.Enabled ~= fast then
			r.body.Enabled = fast
		end
		local rootCf = root.CFrame
		for _, limb in r.limbs do
			local p = rootCf:PointToObjectSpace(limb.part.CFrame * Vector3.new(0, -0.9, 0))
			local on = fast
			if limb.fist and near and limb.last then
				on = on or (p - limb.last).Magnitude / dt > FIST_SPEED
			end
			limb.last = p
			if limb.trail.Enabled ~= on then
				limb.trail.Enabled = on
			end
		end
	end
end

local function watchCharacter(model: Model)
	task.spawn(function()
		model:WaitForChild("HumanoidRootPart", 10)
		model:WaitForChild("Torso", 5)
		if model.Parent and not rigs[model] then
			rig(model)
		end
		if model.Parent then
			watchStates(model)
		end
	end)
end

local started = false
function CombatFx.start()
	if started then
		return
	end
	started = true
	local function watchPlayer(p: Player)
		p.CharacterAdded:Connect(watchCharacter)
		if p.Character then
			watchCharacter(p.Character)
		end
	end
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	-- training dummies get the state flashes too
	for _, m in CollectionService:GetTagged("TrainingDummy") do
		if m:IsA("Model") then
			watchStates(m)
		end
	end
	CollectionService:GetInstanceAddedSignal("TrainingDummy"):Connect(function(m)
		if m:IsA("Model") then
			watchStates(m)
		end
	end)
	workspace.ChildAdded:Connect(watchCorpse)
	RunService.Heartbeat:Connect(step)
	RunService.Heartbeat:Connect(stepFlying)
	task.spawn(function()
		local list = {}
		for _, id in TEX do
			local d = Instance.new("Decal")
			d.Texture = id
			table.insert(list, d)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

-- other players' dashes (CombatService broadcasts them; our own play on input)
function CombatFx.remote(kind: string, attacker: Model?, detail: any)
	local me = Players.LocalPlayer.Character
	if not attacker or attacker == me then
		return
	end
	if kind == "Dash" then
		local root = rootOf(attacker)
		if root then
			task.delay(0.03, function()
				CombatFx.dash(attacker, flat(root.AssemblyLinearVelocity), detail == "Air")
			end)
		end
	end
end

return CombatFx
