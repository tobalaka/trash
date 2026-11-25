--!strict
--[[
	MapGen.AtmosphereBuilder - editor-side atmosphere setup.

	* Lighting: one Atmosphere, a named grade/bloom/sun-rays set (old ad-hoc effects removed),
	  sun visible (sun rays need it), terrain Clouds.
	* ReplicatedStorage.MapRegionVolumes: region volumes for the client switcher. They live in
	  ReplicatedStorage (not Workspace) so StreamingEnabled never hides them from a client that
	  is far away; the client only needs their CFrames/sizes/attributes for point tests.
	  Priorities: base compounds and the dome interior override the floor regions they sit in.
	* preview(name) applies a preset instantly in Studio (the client script does it in game).
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(script.Parent.Layout)
local Decor = require(script.Parent.Decor)

local AtmosphereBuilder = {}

local function presets(): any
	return require(ReplicatedStorage:WaitForChild("MapShared"):WaitForChild("RegionAtmosphere") :: ModuleScript) :: any
end

local function ensure(className: string, name: string, parent: Instance): Instance
	local inst = parent:FindFirstChild(name)
	if not inst or inst.ClassName ~= className then
		if inst then
			inst:Destroy()
		end
		inst = Instance.new(className)
		inst.Name = name
		inst.Parent = parent
	end
	return inst :: Instance
end

function AtmosphereBuilder.setupLighting()
	-- remove earlier ad-hoc effects; keep Sky and Atmosphere
	for _, c in Lighting:GetChildren() do
		if (c:IsA("ColorCorrectionEffect") and c.Name ~= "RegionGrade")
			or (c:IsA("BloomEffect") and c.Name ~= "RegionBloom")
			or (c:IsA("SunRaysEffect") and c.Name ~= "RegionSunRays") then
			c:Destroy()
		elseif c:IsA("DepthOfFieldEffect") then
			c.Enabled = false
		end
	end
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		Instance.new("Atmosphere").Parent = Lighting
	end
	ensure("ColorCorrectionEffect", "RegionGrade", Lighting)
	ensure("BloomEffect", "RegionBloom", Lighting)
	ensure("SunRaysEffect", "RegionSunRays", Lighting)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.CelestialBodiesShown = true
		sky.SunAngularSize = 14
		sky.StarCount = 1500
	end
	Lighting.GlobalShadows = true
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = workspace.Terrain -- Clouds live under Terrain; no voxels are used
	end
end

function AtmosphereBuilder.volumes(ctx: any): Folder
	local old = ReplicatedStorage:FindFirstChild("MapRegionVolumes")
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "MapRegionVolumes"
	local function vol(name: string, cf: CFrame, size: Vector3, region: string, priority: number): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Transparency = 1
		p.CFrame = cf
		p.Size = size
		p:SetAttribute("Region", region)
		p:SetAttribute("Priority", priority)
		p.Parent = f
		return p
	end
	local data = Layout.get()
	for i, r in data.rects do
		vol(r.region .. i, CFrame.new(r.cf.X, 400, r.cf.Z) * r.cf.Rotation, Vector3.new(r.size.X + 60, 1400, r.size.Z + 60), r.region, data.priority[r.region] or 0)
	end
	-- dome interior (cylinder) overrides the town
	local town = ctx.regions.Town.plan(ctx)
	local Town = ctx.regions.Town
	local dome = vol("TownDome", CFrame.new(town.center.X, town.floorY + Town.DOME_HEIGHT / 2, town.center.Z), Vector3.new(Town.DOME_RADIUS * 2, Town.DOME_HEIGHT, Town.DOME_RADIUS * 2), "TownDome", 100)
	dome:SetAttribute("Shape", "Cylinder")
	dome:SetAttribute("Radius", Town.DOME_RADIUS - 10)
	-- faction compounds (sites from the Town plan)
	for name, site in town.baseSites do
		vol(name .. "Base", CFrame.new(site.cf.X, 300, site.cf.Z) * site.cf.Rotation, Vector3.new(site.half.X * 2, 800, site.half.Y * 2), name .. "Base", 90)
	end
	-- FX sprite ids for the client (resolved image content ids)
	for attr, name in { FxGlow = "fx_glow", FxMote = "fx_mote", FxSmog = "fx_smog", FxShaft = "fx_shaft" } do
		local img = Decor.image(name)
		if img then
			f:SetAttribute(attr, img)
		end
	end
	f.Parent = ReplicatedStorage
	return f
end

-- Apply a preset instantly (Studio preview / default look in edit mode).
function AtmosphereBuilder.preview(name: string)
	local P = presets()
	local preset = P.PRESETS[name]
	assert(preset, "no preset " .. name)
	local function set(inst: Instance?, props: { [string]: any }?)
		if inst and props then
			for k, v in props do
				pcall(function()
					(inst :: any)[k] = v
				end)
			end
		end
	end
	set(Lighting, preset.lighting)
	set(Lighting:FindFirstChildOfClass("Atmosphere"), preset.atmosphere)
	set(Lighting:FindFirstChild("RegionGrade"), preset.grade)
	set(Lighting:FindFirstChild("RegionBloom"), preset.bloom)
	set(Lighting:FindFirstChild("RegionSunRays"), preset.sunRays)
	set(workspace.Terrain:FindFirstChildOfClass("Clouds"), preset.clouds)
end

function AtmosphereBuilder.apply(ctx: any)
	AtmosphereBuilder.setupLighting()
	AtmosphereBuilder.volumes(ctx)
	AtmosphereBuilder.preview(presets().DEFAULT)
	print("[MapGen] atmosphere: lighting set, region volumes generated")
end

return AtmosphereBuilder
