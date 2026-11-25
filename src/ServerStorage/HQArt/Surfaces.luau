--!strict
--[[
	HQArt.Surfaces - painted, low-noise MaterialVariants for every base material the map uses.

	Tiles come from trash-art/tools/tile_factory.py (procedural, seamless, structure-only normal maps,
	"little to no dot texture"). Roblox multiplies a variant's colour map by each part's Color, so the
	maps are light and lightly saturated: the part keeps its hue, the variant adds the painted surface.

	Applied as BASE-MATERIAL OVERRIDES, so every part using the base material (now and after any MapGen
	rebuild) gets the painted surface. TRASH_TrashGround keeps MapGen's own variant name, so the
	wasteland ground caps that GroundBuilder tags with it pick up the painted trash tile.

	  require(game.ServerStorage.HQArt.Surfaces).apply()   -- create/update + override
	  require(game.ServerStorage.HQArt.Surfaces).remove()  -- back to Roblox's stock materials
]]

local MaterialService = game:GetService("MaterialService")

local Surfaces = {}

type Def = { name: string, base: Enum.Material, color: number, normal: number, studs: number, organic: boolean?, override: boolean?, rough: number? }

local REGULAR, ORGANIC = Enum.MaterialPattern.Regular, Enum.MaterialPattern.Organic

-- constant roughness maps (8x8 grey PNGs, trash-art/blender/out/tex/rough_NN.png). Review 1: with no roughness map
-- the ground read wet and glossy in the low sun; every surface here is matte except bare metal.
local ROUGH = {
	[30] = 99009883534036, [55] = 88178363584810, [70] = 92338541465387, [75] = 77024863328541,
	[80] = 78763043811599, [85] = 94123504816899, [90] = 120670832804995, [95] = 87620538648768,
}
local function roughMap(r: number): string
	local best, bd = 90, math.huge
	for k in ROUGH do
		local d = math.abs(k - r * 100)
		if d < bd then
			best, bd = k, d
		end
	end
	return "rbxassetid://" .. ROUGH[best]
end

Surfaces.DEFS = {
	{ name = "HQ_Brick", base = Enum.Material.Brick, color = 76253286133439, normal = 85778848159247, studs = 10, rough = 0.92 },
	{ name = "HQ_WoodPlanks", base = Enum.Material.WoodPlanks, color = 132796302614326, normal = 82705044334799, studs = 8, rough = 0.9 },
	{ name = "HQ_CorrodedMetal", base = Enum.Material.CorrodedMetal, color = 105930149094615, normal = 134734721387913, studs = 14, rough = 0.8 },
	{ name = "HQ_Plaster", base = Enum.Material.Plaster, color = 130228895221260, normal = 94976621965106, studs = 16, rough = 0.95 },
	{ name = "HQ_Metal", base = Enum.Material.Metal, color = 126435455593308, normal = 92623022971062, studs = 10, rough = 0.6 },
	{ name = "HQ_Bark", base = Enum.Material.Wood, color = 111413325153971, normal = 81821804339755, studs = 10, rough = 0.92 },
	{ name = "HQ_Fabric", base = Enum.Material.Fabric, color = 78938809850175, normal = 126953574431172, studs = 10, rough = 0.95 },
	{ name = "HQ_Stone", base = Enum.Material.Slate, color = 110045422073088, normal = 112306795167801, studs = 30, rough = 0.92 },
	{ name = "HQ_Concrete", base = Enum.Material.Concrete, color = 139164132838153, normal = 96240766974384, studs = 16, rough = 0.92 },
	{ name = "HQ_Grass", base = Enum.Material.Grass, color = 81807931032917, normal = 122095263234946, studs = 20, organic = true, rough = 0.95 },
	{ name = "HQ_Sand", base = Enum.Material.Sand, color = 86501127799548, normal = 128671132813962, studs = 30, rough = 0.95 },
	{ name = "HQ_Sandstone", base = Enum.Material.Sandstone, color = 90949748588988, normal = 92399153006660, studs = 30, rough = 0.92 },
	{ name = "HQ_Snow", base = Enum.Material.Snow, color = 94497163249684, normal = 91074771134548, studs = 30, organic = true, rough = 0.9 },
	{ name = "HQ_Ground", base = Enum.Material.Ground, color = 98975243097077, normal = 100115390259507, studs = 24, organic = true, rough = 0.95 },
	{ name = "TRASH_TrashGround", base = Enum.Material.Ground, color = 78238981748023, normal = 77052800254320, studs = 26, override = false, rough = 0.92 },
	{ name = "HQ_Mud", base = Enum.Material.Mud, color = 73245384549948, normal = 93645739115445, studs = 20, organic = true, rough = 0.85 },
	{ name = "HQ_Pavement", base = Enum.Material.Pavement, color = 134791786626904, normal = 74656148406376, studs = 12, rough = 0.9 },
	{ name = "HQ_Cobblestone", base = Enum.Material.Cobblestone, color = 135989814287629, normal = 132193233592130, studs = 15, rough = 0.9 },
	{ name = "HQ_Asphalt", base = Enum.Material.Asphalt, color = 86066875244850, normal = 132765096506816, studs = 24, organic = true, rough = 0.9 },
	{ name = "HQ_Pebble", base = Enum.Material.Pebble, color = 82857886809961, normal = 126183396636077, studs = 16, rough = 0.95 },
	-- second versions of the big ground materials (same style, different layout), mixed in by HQArt.Dress so
	-- the ground never repeats one tile across a whole region
	{ name = "HQ_Sand2", base = Enum.Material.Sand, color = 126352088060065, normal = 76202776836777, studs = 34, override = false, rough = 0.95 },
	{ name = "HQ_Grass2", base = Enum.Material.Grass, color = 112198487136187, normal = 78020968278176, studs = 22, organic = true, override = false, rough = 0.95 },
	{ name = "HQ_Ground2", base = Enum.Material.Ground, color = 94588419778046, normal = 89151189735581, studs = 27, organic = true, override = false, rough = 0.95 },
	{ name = "HQ_Stone2", base = Enum.Material.Slate, color = 127460640149339, normal = 99720301449709, studs = 34, override = false, rough = 0.92 },
	{ name = "HQ_Snow2", base = Enum.Material.Snow, color = 98405332262313, normal = 114271617232114, studs = 34, organic = true, override = false, rough = 0.9 },
	{ name = "HQ_Sandstone2", base = Enum.Material.Sandstone, color = 99830161867388, normal = 98091743063257, studs = 34, override = false, rough = 0.92 },
	-- dressed timber for posts and beams: grain along the length (V for uprights, U for horizontals)
	{ name = "HQ_TimberV", base = Enum.Material.WoodPlanks, color = 112809646614128, normal = 131016999404450, studs = 7, override = false, rough = 0.9 },
	{ name = "HQ_TimberH", base = Enum.Material.WoodPlanks, color = 100256368468028, normal = 98515291437618, studs = 7, override = false, rough = 0.9 },
} :: { Def }

function Surfaces.apply(): number
	local n = 0
	for _, d in Surfaces.DEFS do
		local mv = MaterialService:FindFirstChild(d.name) :: MaterialVariant?
		if not mv or not mv:IsA("MaterialVariant") then
			mv = Instance.new("MaterialVariant")
		end
		local m = mv :: MaterialVariant
		m.Name = d.name
		m.BaseMaterial = d.base
		m.ColorMap = "rbxassetid://" .. d.color
		m.NormalMap = "rbxassetid://" .. d.normal
		m.StudsPerTile = d.studs
		m.RoughnessMap = roughMap(d.rough or 0.9)
		m.MaterialPattern = if d.organic then ORGANIC else REGULAR
		m:SetAttribute("HQArt", true)
		m.Parent = MaterialService
		if d.override ~= false then
			MaterialService:SetBaseMaterialOverride(d.base, d.name)
		end
		n += 1
	end
	return n
end

-- The patchwork dome hangs over the whole town sky: full-detail tiles there read as a quilt of texture swatches
-- (review 1). Its panels get their own subdued variants: no colour map (the panel keeps its flat colour), the
-- normal map at 3x the size, matte.
Surfaces.DOME = {
	{ name = "HQ_DomeMetal", base = Enum.Material.Metal, from = "HQ_Metal", rough = 0.8 },
	{ name = "HQ_DomeCorroded", base = Enum.Material.CorrodedMetal, from = "HQ_CorrodedMetal", rough = 0.85 },
	{ name = "HQ_DomeConcrete", base = Enum.Material.Concrete, from = "HQ_Concrete", rough = 0.92 },
	{ name = "HQ_DomeFabric", base = Enum.Material.Fabric, from = "HQ_Fabric", rough = 0.95 },
	{ name = "HQ_DomeWood", base = Enum.Material.WoodPlanks, from = "HQ_WoodPlanks", rough = 0.92 },
}

function Surfaces.dome(): number
	local dome = workspace:FindFirstChild("World") and workspace.World:FindFirstChild("PatchworkDome", true)
	if not dome then
		return 0
	end
	local byBase = {}
	for _, d in Surfaces.DOME do
		local src: Def? = nil
		for _, e in Surfaces.DEFS do
			if e.name == d.from then
				src = e
			end
		end
		assert(src, d.from)
		local mv = MaterialService:FindFirstChild(d.name) :: MaterialVariant? or Instance.new("MaterialVariant")
		local m = mv :: MaterialVariant
		m.Name = d.name
		m.BaseMaterial = d.base
		m.ColorMap = ""
		m.NormalMap = "rbxassetid://" .. src.normal
		m.RoughnessMap = roughMap(d.rough)
		m.StudsPerTile = src.studs * 3
		m:SetAttribute("HQArt", true)
		m.Parent = MaterialService
		byBase[d.base] = d.name
	end
	local n = 0
	for _, p in dome:GetDescendants() do
		if p:IsA("BasePart") and byBase[p.Material] then
			p.MaterialVariant = byBase[p.Material]
			n += 1
		end
	end
	return n
end

-- Review 5: on a 215-stud canyon wall the 34-stud sandstone tile repeats ~6 times and its layers read as ~40 even,
-- parallel bands (wood grain). Review 6: a bigger tile on the tall parts only made the bands step and jump in scale at
-- every join with a shorter neighbour (material textures start at each part's own corner). Now whole CLIFFS get
-- HQ_SandstoneCliff (tile_factory `sandstonecliff`: vertical desert varnish + soft joints, layering only hinted, so
-- a join has almost nothing horizontal to break): every sandstone part taller than TALL, and every sandstone part
-- taller than JOIN that touches one of those, transitively. Run after Dress.groundMix (it leaves these alone).
local TALL, JOIN = 80, 25
local CLIFF = { name = "HQ_SandstoneCliff", color = 95535799367006, normal = 123425159190511, studs = 60, rough = 0.92 }

local function heightOf(p: BasePart): number
	local cf, s = p.CFrame, p.Size
	return math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
end

function Surfaces.tall(): number
	local mv = MaterialService:FindFirstChild(CLIFF.name) :: MaterialVariant? or Instance.new("MaterialVariant")
	local m = mv :: MaterialVariant
	m.Name = CLIFF.name
	m.BaseMaterial = Enum.Material.Sandstone
	m.ColorMap = "rbxassetid://" .. CLIFF.color
	m.NormalMap = "rbxassetid://" .. CLIFF.normal
	m.RoughnessMap = roughMap(CLIFF.rough)
	m.StudsPerTile = CLIFF.studs
	m.MaterialPattern = REGULAR
	m:SetAttribute("HQArt", true)
	m.Parent = MaterialService
	for _, old in { "HQ_SandstoneTall", "HQ_Sandstone2Tall" } do -- review 5's per-part variants
		local o = MaterialService:FindFirstChild(old)
		if o then
			o:Destroy()
		end
	end
	local roots = {}
	for _, r in { workspace:FindFirstChild("Ground"), workspace:FindFirstChild("World") } do
		if r then
			table.insert(roots, r)
		end
	end
	local queue, done = {}, {}
	local function source(p: BasePart): string
		return (p:GetAttribute("HQTall") :: string?) or (if p.MaterialVariant == "" then "HQ_Sandstone" else p.MaterialVariant)
	end
	-- review 7: the cliff rule swept in the game's own staircase (Ground.Structures.AmoStairs): built things stay out
	local structures = workspace:FindFirstChild("Ground") and workspace.Ground:FindFirstChild("Structures")
	local function eligible(p: Instance): boolean
		return not (structures and p:IsDescendantOf(structures))
	end
	local function mark(p: BasePart)
		done[p] = true
		p:SetAttribute("HQTall", source(p))
		p:SetAttribute("HQMix", nil)
		p.MaterialVariant = CLIFF.name
		table.insert(queue, p)
	end
	for _, r in roots do
		for i, p in r:GetDescendants() do
			if p:IsA("BasePart") and p.Material == Enum.Material.Sandstone and heightOf(p) > TALL and eligible(p) then
				mark(p)
			end
			if i % 4000 == 0 then
				task.wait()
			end
		end
	end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = roots
	local k = 1
	while k <= #queue do
		local p = queue[k]
		k += 1
		for _, q in workspace:GetPartBoundsInBox(p.CFrame, p.Size + Vector3.new(1.2, 1.2, 1.2), op) do
			if not done[q] and q.Material == Enum.Material.Sandstone and heightOf(q) > JOIN and eligible(q) then
				mark(q)
			end
		end
		if k % 500 == 0 then
			task.wait()
		end
	end
	-- parts that were cliffs before but no longer qualify go back to their own variant
	for _, r in roots do
		for _, p in r:GetDescendants() do
			if p:IsA("BasePart") and not done[p] and p:GetAttribute("HQTall") then
				local src = p:GetAttribute("HQTall")
				p.MaterialVariant = if src == "HQ_Sandstone" then "" else src
				p:SetAttribute("HQTall", nil)
			end
		end
	end
	return #queue
end

function Surfaces.remove()
	for _, root in { workspace:FindFirstChild("Ground"), workspace:FindFirstChild("World") } do
		for _, p in (if root then root:GetDescendants() else {}) do
			local src = p:GetAttribute("HQTall")
			if src and p:IsA("BasePart") then
				p.MaterialVariant = if src == "HQ_Sandstone" then "" else src
				p:SetAttribute("HQTall", nil)
				p:SetAttribute("HQMix", if src == "HQ_Sandstone2" then true else nil)
			end
		end
	end
	local cliff = MaterialService:FindFirstChild(CLIFF.name)
	if cliff then
		cliff:Destroy()
	end
	local dome = workspace:FindFirstChild("World") and workspace.World:FindFirstChild("PatchworkDome", true)
	if dome then
		for _, p in dome:GetDescendants() do
			if p:IsA("BasePart") and string.sub(p.MaterialVariant, 1, 7) == "HQ_Dome" then
				p.MaterialVariant = ""
			end
		end
	end
	for _, d in Surfaces.DOME do
		local mv = MaterialService:FindFirstChild(d.name)
		if mv then
			mv:Destroy()
		end
	end
	for _, d in Surfaces.DEFS do
		if d.override ~= false and MaterialService:GetBaseMaterialOverride(d.base) == d.name then
			MaterialService:SetBaseMaterialOverride(d.base, "")
		end
		local mv = MaterialService:FindFirstChild(d.name)
		if mv and mv:GetAttribute("HQArt") then
			mv:Destroy()
		end
	end
end

return Surfaces
