--!strict
--[[
	RegionAtmosphere (client) - blends Lighting/Atmosphere/grade/bloom/sun rays/clouds to the
	preset of the region the camera is in, and runs a camera-following weather emitter
	(snow, ash + smog, dust, spores). Purely visual: never touches gameplay state.

	Region detection reads ReplicatedStorage.MapRegionVolumes (generated, not streamed, so it is
	always available on the client even when the region's geometry has not streamed in).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local RegionAtmosphere = require(ReplicatedStorage:WaitForChild("MapShared"):WaitForChild("RegionAtmosphere"))

local volumes = ReplicatedStorage:WaitForChild("MapRegionVolumes", 30)
local camera = workspace.CurrentCamera

local CHECK_INTERVAL = 0.4

local function findOrMake(className: string, name: string, parent: Instance): Instance
	local inst = parent:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst :: Instance
end

local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or findOrMake("Atmosphere", "Atmosphere", Lighting)
local grade = findOrMake("ColorCorrectionEffect", "RegionGrade", Lighting)
local bloom = findOrMake("BloomEffect", "RegionBloom", Lighting)
local sunRays = findOrMake("SunRaysEffect", "RegionSunRays", Lighting)
local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")

-- ── weather emitter (client-only part that follows the camera) ──
local weatherPart = Instance.new("Part")
weatherPart.Name = "LocalWeather"
weatherPart.Anchored = true
weatherPart.CanCollide = false
weatherPart.CanQuery = false
weatherPart.CanTouch = false
weatherPart.Transparency = 1
weatherPart.Size = Vector3.new(140, 1, 140)
weatherPart.Parent = camera

local function image(attr: string, fallback: string): string
	local v = volumes and volumes:GetAttribute(attr)
	return typeof(v) == "string" and v or fallback
end

local particles = Instance.new("ParticleEmitter")
particles.Name = "Particles"
particles.Rate = 0
particles.Parent = weatherPart
local smog = Instance.new("ParticleEmitter")
smog.Name = "Smog"
smog.Rate = 0
smog.Texture = image("FxSmog", "rbxasset://textures/particles/smoke_main.dds")
smog.Size = NumberSequence.new(40, 70)
smog.Lifetime = NumberRange.new(10, 14)
smog.Speed = NumberRange.new(1, 3)
smog.SpreadAngle = Vector2.new(180, 20)
smog.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.86), NumberSequenceKeypoint.new(1, 1) })
smog.LightInfluence = 1
smog.Parent = weatherPart

local weatherKind = "none"
local weatherOffset = Vector3.zero

local function setWeather(w: { kind: string, rate: number, color: Color3 }?)
	if not w then
		particles.Rate = 0
		smog.Rate = 0
		weatherKind = "none"
		return
	end
	weatherKind = w.kind
	particles.Texture = image("FxMote", "rbxasset://textures/particles/sparkles_main.dds")
	particles.Color = ColorSequence.new(w.color)
	particles.Rate = w.rate
	particles.LightInfluence = 1
	particles.LightEmission = 0
	particles.Rotation = NumberRange.new(0, 360)
	smog.Rate = 0
	if w.kind == "snow" then
		weatherOffset = Vector3.new(0, 40, 0)
		particles.Size = NumberSequence.new(0.3, 0.45)
		particles.Lifetime = NumberRange.new(5, 7)
		particles.Speed = NumberRange.new(14, 22)
		particles.EmissionDirection = Enum.NormalId.Bottom
		particles.SpreadAngle = Vector2.new(25, 25)
		particles.Acceleration = Vector3.new(7, 0, 3) -- wind
		particles.Transparency = NumberSequence.new(0.1)
		smog.Rate = 0.6
		smog.Color = ColorSequence.new(Color3.fromRGB(230, 238, 248))
	elseif w.kind == "ash" then
		weatherOffset = Vector3.new(0, 10, 0)
		particles.Size = NumberSequence.new(0.18, 0.3)
		particles.Lifetime = NumberRange.new(7, 10)
		particles.Speed = NumberRange.new(1, 3)
		particles.EmissionDirection = Enum.NormalId.Top
		particles.SpreadAngle = Vector2.new(180, 180)
		particles.Acceleration = Vector3.new(1.5, -0.8, 0.6)
		particles.Transparency = NumberSequence.new(0.2)
		smog.Rate = 1.4
		smog.Color = ColorSequence.new(w.color)
	elseif w.kind == "dust" then
		weatherOffset = Vector3.new(0, 4, 0)
		particles.Size = NumberSequence.new(0.12, 0.22)
		particles.Lifetime = NumberRange.new(6, 9)
		particles.Speed = NumberRange.new(2, 5)
		particles.EmissionDirection = Enum.NormalId.Top
		particles.SpreadAngle = Vector2.new(180, 30)
		particles.Acceleration = Vector3.new(3, 0, 1)
		particles.Transparency = NumberSequence.new(0.3)
		smog.Rate = 0.5
		smog.Color = ColorSequence.new(w.color)
	elseif w.kind == "spores" then
		weatherOffset = Vector3.new(0, 2, 0)
		particles.Size = NumberSequence.new(0.12, 0.2)
		particles.Lifetime = NumberRange.new(6, 9)
		particles.Speed = NumberRange.new(0.3, 1)
		particles.EmissionDirection = Enum.NormalId.Top
		particles.SpreadAngle = Vector2.new(180, 180)
		particles.Acceleration = Vector3.new(0, 0.35, 0)
		particles.LightEmission = 0.7
		particles.LightInfluence = 0.2
		particles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(1, 1) })
		smog.Rate = 0.4
		smog.Color = ColorSequence.new(Color3.fromRGB(190, 210, 180))
	end
end

-- ── preset blending ──
local current: string? = nil
local tweens: { Tween } = {}

local function tween(inst: Instance?, props: { [string]: any }?, info: TweenInfo)
	if not inst or not props then
		return
	end
	local ok, t = pcall(function()
		return TweenService:Create(inst, info, props)
	end)
	if ok and t then
		t:Play()
		table.insert(tweens, t)
	end
end

local function apply(regionName: string, instant: boolean?)
	local preset = RegionAtmosphere.PRESETS[regionName]
	if not preset then
		return
	end
	for _, t in tweens do
		t:Cancel()
	end
	table.clear(tweens)
	local info = TweenInfo.new(instant and 0 or RegionAtmosphere.TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	tween(Lighting, preset.lighting, info)
	tween(atmosphere, preset.atmosphere, info)
	tween(grade, preset.grade, info)
	tween(bloom, preset.bloom, info)
	tween(sunRays, preset.sunRays, info)
	tween(clouds, preset.clouds, info)
	setWeather(preset.weather)
end

apply(RegionAtmosphere.DEFAULT, true)
current = RegionAtmosphere.DEFAULT

local accumulator = 0
RunService.RenderStepped:Connect(function(dt: number)
	weatherPart.CFrame = CFrame.new(camera.CFrame.Position + weatherOffset)
	accumulator += dt
	if accumulator < CHECK_INTERVAL then
		return
	end
	accumulator = 0
	local region = RegionAtmosphere.regionAt(volumes, camera.Focus.Position)
	if region and region ~= current then
		current = region
		apply(region, false)
	end
end)
