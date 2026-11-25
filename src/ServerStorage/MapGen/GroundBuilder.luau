--!strict
--[[
	MapGen.GroundBuilder - the ground as stacked flat Parts, built the way the reference world
	(World_8248288152) builds its terrain: axis-aligned blocks with flat tops, a thin coloured cap
	(grass, sand, snow, trash) over a rock body, terraces stepping up in ledges, cliffs made of
	stacked blocks, and water as flat murky slabs (the reference's Sea folder). No smooth Terrain
	is used at all, not even for water; building the ground clears Terrain.

	Why parts: the user rejected smooth Terrain ("remove the curved hills", "stop using terrain")
	and wants the reference look; blocks also keep destruction and collision cheap (vault:
	World.md, "deliberately blocky").

	Method:
	  1. Every region registers flat-topped Features (FeatureMap) in Build.registerGround:
	     terraces, rock tiers, basins, pads.
	  2. The map is sampled on a CELL grid. Each cell takes its region's base height and surface
	     key (Layout.regionAt, with a noisy border so regions meet in a jagged blocky edge), folds
	     in every feature, lets the region re-key the surface (roads, patches), and rounds the
	     height to the 0.5-stud grid.
	  3. Per CHUNK, cells are greedy-merged into rectangles: caps by (top, surface key), bodies by
	     (top, body material), water by (level, kind). Each rectangle becomes one Part.

	No Z-fighting by construction: columns never overlap in X/Z, so two faces can only share a
	plane where columns touch, and those faces point at each other (both hidden). A cap and its
	body share side planes but not height ranges. Water sits 0.25 studs off the 0.5 grid that
	every top uses, so a water surface can never be coplanar with ground, and a water slab starts
	0.05 above the highest bed cell under it, so its sides never share a plane and a height range
	with the side of a bed cap.
]]

local Config = require(script.Parent.Config)
local Layout = require(script.Parent.Layout)
local FeatureMap = require(script.Parent.FeatureMap)

local GroundBuilder = {}

GroundBuilder.CELL = 8 -- studs per ground sample in the town (lots, stairs and roads need it)
GroundBuilder.CELL_COARSE = 16 -- elsewhere: half the columns, the same blocky look
GroundBuilder.CHUNK = 512 -- studs per merge chunk (one Folder each; max part size is 2048)
GroundBuilder.CAP = 1.2 -- cap thickness (the reference's grass caps are 0.8-3 thick). Not a
-- whole number on purpose: body tops (top - CAP) then never sit on the integer heights that
-- 1-stud stair risers step through.
GroundBuilder.BEDROCK = -60 -- bodies reach down to here
GroundBuilder.FOLDER = "Ground"
GroundBuilder.WATER_FOLDER = "Water" -- Workspace.Ground.Water (placement rays skip it)

-- ─── surfaces ─────────────────────────────────────────────────────────────────
-- Muted palette taken from the reference: dark green grass (51,61,54), slate (58,52,49),
-- brown slate (98,78,65), ground (99,88,83). Each region keeps its own identity (sand, trash,
-- snow) but at the reference's low saturation.

export type Body = { material: Enum.Material, color: Color3 }
export type Surface = { material: Enum.Material, color: Color3, body: string, variant: string? }

GroundBuilder.BODIES = {
	Slate = { material = Enum.Material.Slate, color = Color3.fromRGB(58, 52, 49) },
	SlateLight = { material = Enum.Material.Slate, color = Color3.fromRGB(81, 76, 74) },
	SlateBrown = { material = Enum.Material.Slate, color = Color3.fromRGB(98, 78, 65) },
	Sandstone = { material = Enum.Material.Sandstone, color = Color3.fromRGB(146, 104, 76) },
	Dirt = { material = Enum.Material.Ground, color = Color3.fromRGB(99, 88, 83) },
} :: { [string]: Body }

GroundBuilder.SURFACES = {
	-- Town (Patchwork Town crater)
	TownDust = { material = Enum.Material.Sand, color = Color3.fromRGB(160, 136, 104), body = "SlateBrown" },
	TownRock = { material = Enum.Material.Slate, color = Color3.fromRGB(122, 100, 82), body = "SlateBrown" },
	TownFloor = { material = Enum.Material.Ground, color = Color3.fromRGB(112, 98, 84), body = "Dirt" },
	Cobble = { material = Enum.Material.Cobblestone, color = Color3.fromRGB(120, 112, 104), body = "Dirt" },
	Pavement = { material = Enum.Material.Pavement, color = Color3.fromRGB(104, 100, 96), body = "Dirt" },
	CanalMud = { material = Enum.Material.Mud, color = Color3.fromRGB(70, 62, 50), body = "Dirt" },
	-- Wasteland
	WasteGround = { material = Enum.Material.Ground, color = Color3.fromRGB(80, 72, 62), body = "Slate", variant = "TRASH_TrashGround" },
	WasteAsphalt = { material = Enum.Material.Asphalt, color = Color3.fromRGB(60, 59, 58), body = "Slate" },
	WasteRubble = { material = Enum.Material.Pebble, color = Color3.fromRGB(92, 84, 76), body = "Slate" },
	WasteRock = { material = Enum.Material.Slate, color = Color3.fromRGB(66, 60, 56), body = "Slate" },
	Sludge = { material = Enum.Material.Mud, color = Color3.fromRGB(54, 52, 40), body = "Slate" },
	-- Desert
	Sand = { material = Enum.Material.Sand, color = Color3.fromRGB(190, 156, 112), body = "Sandstone" },
	SandDark = { material = Enum.Material.Sand, color = Color3.fromRGB(172, 136, 96), body = "Sandstone" },
	DesertMesa = { material = Enum.Material.Sandstone, color = Color3.fromRGB(170, 120, 84), body = "Sandstone" },
	DesertPath = { material = Enum.Material.Sandstone, color = Color3.fromRGB(178, 146, 108), body = "Sandstone" },
	OasisGrass = { material = Enum.Material.Grass, color = Color3.fromRGB(70, 88, 56), body = "Dirt" },
	-- Jungle
	JungleGrass = { material = Enum.Material.Grass, color = Color3.fromRGB(51, 61, 54), body = "Slate" },
	JungleMoss = { material = Enum.Material.Grass, color = Color3.fromRGB(48, 56, 48), body = "Slate" },
	JungleMud = { material = Enum.Material.Mud, color = Color3.fromRGB(64, 56, 46), body = "Slate" },
	RiverSand = { material = Enum.Material.Sand, color = Color3.fromRGB(132, 120, 98), body = "Slate" },
	JungleRock = { material = Enum.Material.Slate, color = Color3.fromRGB(58, 52, 49), body = "Slate" },
	-- Winter
	Snow = { material = Enum.Material.Snow, color = Color3.fromRGB(220, 226, 232), body = "SlateLight" },
	SnowShade = { material = Enum.Material.Snow, color = Color3.fromRGB(196, 204, 214), body = "SlateLight" },
	Ice = { material = Enum.Material.Ice, color = Color3.fromRGB(150, 188, 204), body = "SlateLight" },
	WinterRock = { material = Enum.Material.Slate, color = Color3.fromRGB(81, 76, 74), body = "SlateLight" },
	-- Bases
	BasePavement = { material = Enum.Material.Concrete, color = Color3.fromRGB(122, 118, 108), body = "SlateLight" },
	ScrapperYard = { material = Enum.Material.Ground, color = Color3.fromRGB(92, 72, 62), body = "SlateBrown" },
} :: { [string]: Surface }

-- Water slabs, by the surface key of the bed under them. Murky and nearly opaque, like the
-- reference's sea parts (Plastic (36,50,54), transparency 0.2), so slab seams never show.
export type Water = { material: Enum.Material, color: Color3, transparency: number, reflectance: number }
GroundBuilder.WATERS = {
	Sludge = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(62, 64, 40), transparency = 0.15, reflectance = 0.05 },
	CanalMud = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(58, 62, 44), transparency = 0.15, reflectance = 0.05 },
	Clear = { material = Enum.Material.SmoothPlastic, color = Color3.fromRGB(36, 50, 54), transparency = 0.2, reflectance = 0.12 },
} :: { [string]: Water }

-- ─── the shared feature map ───────────────────────────────────────────────────

local features: FeatureMap.Map = FeatureMap.new()

function GroundBuilder.reset(): FeatureMap.Map
	features = FeatureMap.new()
	return features
end

function GroundBuilder.features(): FeatureMap.Map
	return features
end

-- ─── rock tiers: cliffs, mesas and walls as stacked blocks ─────────────────────

-- Horizontal footprint of a (possibly rotated) greybox block: yaw, half extents, top Y.
-- The yaw snaps to the nearest right angle when it is within 6 degrees of one.
function GroundBuilder.footprint(cf: CFrame, size: Vector3): (number, number, number, Vector2, number)
	local axes = { cf.RightVector, cf.UpVector, cf.LookVector }
	local sizes = { size.X, size.Y, size.Z }
	local vi = 1
	for i = 2, 3 do
		if math.abs(axes[i].Y) > math.abs(axes[vi].Y) then
			vi = i
		end
	end
	local a, b = vi == 1 and 2 or 1, vi == 3 and 2 or 3
	local ax = axes[a]
	local yaw = math.atan2(-ax.Z, ax.X)
	local snapped = math.floor(yaw / (math.pi / 2) + 0.5) * (math.pi / 2)
	if math.abs(yaw - snapped) < math.rad(6) then
		yaw = snapped
	end
	local halfY = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
	return cf.X, cf.Z, yaw, Vector2.new(sizes[a] / 2, sizes[b] / 2), cf.Y + halfY
end

export type TierOpts = {
	base: number, -- ground height the stack rises from
	top: number, -- height of the highest tier
	key: string, -- surface key of every tier cap
	tierHeight: number?, -- target height per tier (default 18)
	inset: number?, -- fraction of the half extent each side may lose per tier (default 0.16)
	buttresses: number?, -- extra low blocks leaning on the sides (default 3)
	layer: number?,
	rng: Random,
}

-- Stacks of shrinking blocks with independently jittered sides, side shelves on some tiers and
-- low buttress blocks on the flanks: the irregular stepped cliff silhouette of the reference's
-- Map/Terrain folder (offset slabs, never a centred ziggurat).
function GroundBuilder.rockTiers(fm: FeatureMap.Map, cx: number, cz: number, yaw: number, half: Vector2, opts: TierOpts)
	local rng = opts.rng
	local layer = opts.layer or 2
	local rise = opts.top - opts.base
	if rise < 1 then
		return
	end
	local tierH = opts.tierHeight or 18
	local n = math.clamp(math.floor(rise / tierH + 0.5), 1, 12)
	local inset = opts.inset or 0.16
	local x0, x1, z0, z1 = -half.X, half.X, -half.Y, half.Y
	local cosY, sinY = math.cos(yaw), math.sin(yaw)
	local function toWorld(lx: number, lz: number): (number, number)
		-- CFrame.Angles(0, yaw, 0): local X -> (cos, -sin), local Z -> (sin, cos)
		return cx + lx * cosY + lz * sinY, cz - lx * sinY + lz * cosY
	end
	for i = 1, n do
		if i > 1 then
			-- uneven insets: one side may barely move while the opposite one jumps in
			x0 += half.X * inset * rng:NextNumber(0, 1.8)
			x1 -= half.X * inset * rng:NextNumber(0, 1.8)
			z0 += half.Y * inset * rng:NextNumber(0, 1.8)
			z1 -= half.Y * inset * rng:NextNumber(0, 1.8)
			if x1 - x0 < 16 or z1 - z0 < 16 then
				break
			end
		end
		local t = i / n
		local top = opts.base + rise * t + (i < n and rng:NextNumber(-0.2, 0.2) * rise / n or 0)
		local wx, wz = toWorld((x0 + x1) / 2, (z0 + z1) / 2)
		fm:rect("raise", layer, wx, wz, (x1 - x0) / 2, (z1 - z0) / 2, top, opts.key, yaw)
		if i > 1 and rng:NextNumber() < 0.4 then
			-- a shelf at the same height hanging off one side breaks the outline
			local sx, sz = (x1 - x0) * rng:NextNumber(0.25, 0.5), (z1 - z0) * rng:NextNumber(0.25, 0.5)
			local ox = (rng:NextNumber() < 0.5 and x0 or x1) + rng:NextNumber(-0.3, 0.3) * sx
			local oz = rng:NextNumber(z0 + sz / 2, math.max(z0 + sz / 2, z1 - sz / 2))
			local swx, swz = toWorld(ox, oz)
			fm:rect("raise", layer, swx, swz, sx / 2, sz / 2, top, opts.key, yaw)
		end
	end
	for _ = 1, opts.buttresses or 3 do
		-- a block leaning on one side, reaching 20-60% of the height
		local side = rng:NextInteger(1, 4)
		local along = rng:NextNumber(-0.7, 0.7)
		local depth = rng:NextNumber(0.12, 0.3)
		local lx, lz, hx, hz
		if side <= 2 then
			hx = half.X * rng:NextNumber(0.15, 0.35)
			hz = half.Y * depth
			lx = along * half.X
			lz = (side == 1 and 1 or -1) * (half.Y + hz * 0.4)
		else
			hx = half.X * depth
			hz = half.Y * rng:NextNumber(0.15, 0.35)
			lx = (side == 3 and 1 or -1) * (half.X + hx * 0.4)
			lz = along * half.Y
		end
		local wx, wz = toWorld(lx, lz)
		fm:rect("raise", layer, wx, wz, math.max(hx, 8), math.max(hz, 8), opts.base + rise * rng:NextNumber(0.2, 0.6), opts.key, yaw)
	end
end

-- Low stepped plateau: 1..tiers nested rectangles, each 'step' studs above the last.
function GroundBuilder.terrace(fm: FeatureMap.Map, cx: number, cz: number, hx: number, hz: number, base: number, step: number, tiers: number, key: string, rng: Random, layer: number?)
	local x0, x1, z0, z1 = cx - hx, cx + hx, cz - hz, cz + hz
	for i = 1, tiers do
		local top = base + step * i
		fm:box("raise", layer or 1, x0, x1, z0, z1, top, key)
		local w, d = x1 - x0, z1 - z0
		if rng:NextNumber() < 0.45 then
			-- an offset slab at the same height: the outline is never a plain rectangle
			local sw, sd = w * rng:NextNumber(0.3, 0.6), d * rng:NextNumber(0.3, 0.6)
			local sx = rng:NextNumber() < 0.5 and x0 - sw * 0.3 or x1 + sw * 0.3
			local sz = rng:NextNumber(z0, z1)
			fm:box("raise", layer or 1, sx - sw / 2, sx + sw / 2, sz - sd / 2, sz + sd / 2, top, key)
		end
		x0 += w * rng:NextNumber(0.02, 0.38)
		x1 -= w * rng:NextNumber(0.02, 0.38)
		z0 += d * rng:NextNumber(0.02, 0.38)
		z1 -= d * rng:NextNumber(0.02, 0.38)
		if x1 - x0 < 24 or z1 - z0 < 24 then
			break
		end
	end
end

-- Highland: a big stepped hill made of offset slabs (the reference's hills are exactly this:
-- flat ledges stacked up, never a slope). Ledges are `step` studs (4-7: jumpable), each tier is
-- a union of 1-3 jittered rectangles so the outline never reads as a centred pyramid.
function GroundBuilder.highland(fm: FeatureMap.Map, cx: number, cz: number, hx: number, hz: number, base: number, height: number, step: number, key: string, rng: Random, layer: number?)
	local tiers = math.max(1, math.floor(height / step + 0.5))
	local x0, x1, z0, z1 = cx - hx, cx + hx, cz - hz, cz + hz
	-- drift: the summit wanders off-centre, so one side climbs gently and the other drops
	local driftX, driftZ = rng:NextNumber(-0.35, 0.35), rng:NextNumber(-0.35, 0.35)
	for i = 1, tiers do
		local top = base + step * i
		fm:box("raise", layer or 1, x0, x1, z0, z1, top, key)
		local w, d = x1 - x0, z1 - z0
		for _ = 1, rng:NextInteger(0, 2) do
			local sw, sd = w * rng:NextNumber(0.25, 0.55), d * rng:NextNumber(0.25, 0.55)
			local sx = rng:NextNumber(x0, x1)
			local sz = rng:NextNumber(z0, z1)
			fm:box("raise", layer or 1, sx - sw / 2, sx + sw / 2, sz - sd / 2, sz + sd / 2, top, key)
		end
		-- shrink toward the drifted summit: ledges are 6-24 studs deep
		local shrink = (hx + hz) / tiers
		x0 += math.max(6, shrink * rng:NextNumber(0.3, 1.1) * (1 + driftX))
		x1 -= math.max(6, shrink * rng:NextNumber(0.3, 1.1) * (1 - driftX))
		z0 += math.max(6, shrink * rng:NextNumber(0.3, 1.1) * (1 + driftZ))
		z1 -= math.max(6, shrink * rng:NextNumber(0.3, 1.1) * (1 - driftZ))
		if x1 - x0 < 20 or z1 - z0 < 20 then
			break
		end
	end
end

-- Rectangular basin with a stepped shelf: shelf at shelfTop, bed at bedTop, water at `water`.
-- The shelf rim stays above the water so the water never shows a side wall.
function GroundBuilder.basin(fm: FeatureMap.Map, cx: number, cz: number, hx: number, hz: number, shelfTop: number, bedTop: number, water: number, shelfKey: string, bedKey: string, rng: Random, layer: number?)
	local l = layer or 3
	fm:box("carve", l, cx - hx, cx + hx, cz - hz, cz + hz, shelfTop, shelfKey)
	-- the wet part: one or two overlapping rectangles inside the shelf (blocky, not round)
	local ix, iz = hx * rng:NextNumber(0.62, 0.8), hz * rng:NextNumber(0.62, 0.8)
	fm:box("carve", l, cx - ix, cx + ix, cz - iz, cz + iz, bedTop, bedKey, water)
	if rng:NextNumber() < 0.7 then
		local ox, oz = rng:NextNumber(-0.3, 0.3) * hx, rng:NextNumber(-0.3, 0.3) * hz
		local jx, jz = ix * rng:NextNumber(0.5, 0.85), iz * rng:NextNumber(0.5, 0.85)
		fm:box("carve", l, cx + ox - jx, cx + ox + jx, cz + oz - jz, cz + oz + jz, bedTop - 2, bedKey, water)
	end
end

-- ─── column evaluation ────────────────────────────────────────────────────────

local RIM_STEP = 64 -- studs between rim ledges outside the playable map
local RIM_RISE = 46
local RIM_MAX = 420 -- the map is walled in by cliffs, like the reference world

-- Ground at (x, z): top, surface key, water level (nil = dry).
function GroundBuilder.column(ctx: any, x: number, z: number): (number, string, number?)
	local regionName = Layout.regionAt(x, z)
	local region = ctx.regions[regionName]
	local top: number = region.BASE_Y
	local surface: string = region.BASE_KEY
	local water: number?
	top, surface, water = features:query(x, z, top, surface)
	-- map edge: stepped cliffs enclose the world (the reference walls its map in with cliffs)
	local b = Layout.get().bounds
	local out = math.max(b.minX - x, x - b.maxX, b.minZ - z, z - b.maxZ)
	if out > -40 then
		local n = math.noise(math.floor(x / 64) * 0.37, math.floor(z / 64) * 0.37, 4.4)
		local ledge = math.floor((out + 40) / RIM_STEP + n * 0.8)
		if ledge >= 1 then
			local rimTop = math.min(RIM_MAX, region.BASE_Y + ledge * RIM_RISE + n * 10)
			if rimTop > top then
				top, surface, water = rimTop, region.ROCK_KEY, nil
			end
		end
	end
	if region.patch then
		surface = region.patch(ctx, x, z, top, surface)
	end
	top = FeatureMap.q(top)
	if water and top > (water :: number) - 0.25 then
		water = nil
	end
	return top, surface, water
end

-- Height only, for planners and placement checks before the ground exists.
function GroundBuilder.heightAt(ctx: any, x: number, z: number): number
	local top = GroundBuilder.column(ctx, x, z)
	return top
end

-- Forward declaration: cellFor is defined with the chunk builder below.
local cellFor: (x0: number, z0: number) -> number

-- Top of the ground as BUILT at (x, z): the column at the centre of the heightfield cell that
-- covers the point (cells are sampled at their centres, so feature edges snap to cell edges).
function GroundBuilder.builtTop(ctx: any, x: number, z: number): number
	local K = GroundBuilder.CHUNK
	local cell = cellFor(math.floor(x / K) * K, math.floor(z / K) * K)
	local top = GroundBuilder.column(ctx, (math.floor(x / cell) + 0.5) * cell, (math.floor(z / cell) + 0.5) * cell)
	return top
end

-- ─── building ─────────────────────────────────────────────────────────────────

local function setProgress(text: string)
	Layout.dataFolder():SetAttribute("Progress", text)
end

function GroundBuilder.bounds(): (number, number, number, number)
	local b = Layout.get().bounds
	local m = Config.GROUND.MARGIN
	local C = GroundBuilder.CHUNK
	return math.floor((b.minX - m) / C) * C, math.ceil((b.maxX + m) / C) * C, math.floor((b.minZ - m) / C) * C, math.ceil((b.maxZ + m) / C) * C
end

export type Rect = { i0: number, i1: number, k0: number, k1: number, key: string }

-- Greedy rectangle merge over an N x N grid of string keys ("" = skip).
local function greedy(keys: { { string } }, n: number): { Rect }
	local used: { { boolean } } = {}
	for i = 1, n do
		used[i] = table.create(n, false)
	end
	local out: { Rect } = {}
	for i = 1, n do
		for k = 1, n do
			local key = keys[i][k]
			if used[i][k] or key == "" then
				continue
			end
			local k1 = k
			while k1 < n and not used[i][k1 + 1] and keys[i][k1 + 1] == key do
				k1 += 1
			end
			local i1 = i
			while i1 < n do
				local ok = true
				for kk = k, k1 do
					if used[i1 + 1][kk] or keys[i1 + 1][kk] ~= key then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
				i1 += 1
			end
			for ii = i, i1 do
				for kk = k, k1 do
					used[ii][kk] = true
				end
			end
			table.insert(out, { i0 = i, i1 = i1, k0 = k, k1 = k1, key = key })
		end
	end
	return out
end

local function newPart(name: string, cf: CFrame, size: Vector3, material: Enum.Material, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material
	p.Color = color
	p.Size = size
	p.CFrame = cf
	return p
end

function GroundBuilder.folder(): Folder
	local f = workspace:FindFirstChild(GroundBuilder.FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = GroundBuilder.FOLDER
		f.Parent = workspace
	end
	return f :: Folder
end

function GroundBuilder.waterFolder(): Folder
	local root = GroundBuilder.folder()
	local f = root:FindFirstChild(GroundBuilder.WATER_FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = GroundBuilder.WATER_FOLDER
		f.Parent = root
	end
	return f :: Folder
end

-- Build one chunk: cells -> merged cap/body parts + water.
-- Chunks touching the Town rectangle (plus margin) use the fine cell.
cellFor = function(x0: number, z0: number): number
	local size = GroundBuilder.CHUNK
	for _, r in Layout.rectsOf("Town") do
		local half = (r.cf.Rotation * r.size):Abs() / 2
		if x0 + size > r.cf.X - half.X - 64 and x0 < r.cf.X + half.X + 64 and z0 + size > r.cf.Z - half.Z - 64 and z0 < r.cf.Z + half.Z + 64 then
			return GroundBuilder.CELL
		end
	end
	return GroundBuilder.CELL_COARSE
end

function GroundBuilder.buildChunk(ctx: any, x0: number, z0: number, parent: Instance, waterParent: Instance): (number, number)
	local C = cellFor(x0, z0)
	local N = GroundBuilder.CHUNK // C
	local tops: { { number } } = {}
	local capKeys: { { string } } = {}
	local bodyKeys: { { string } } = {}
	local waterKeys: { { string } } = {}
	local waters: { { number } } = {}
	for i = 1, N do
		tops[i], capKeys[i], bodyKeys[i], waterKeys[i], waters[i] = {}, {}, {}, {}, {}
		for k = 1, N do
			local x, z = x0 + (i - 0.5) * C, z0 + (k - 0.5) * C
			local top, surface, water = GroundBuilder.column(ctx, x, z)
			local s = GroundBuilder.SURFACES[surface]
			assert(s, "unknown surface key " .. tostring(surface))
			tops[i][k] = top
			capKeys[i][k] = top .. "|" .. surface
			bodyKeys[i][k] = top .. "|" .. s.body
			if water then
				waterKeys[i][k] = water .. "|" .. (GroundBuilder.WATERS[surface] and surface or "Clear")
				waters[i][k] = water
			else
				waterKeys[i][k] = ""
			end
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = string.format("%d_%d", x0, z0)
	local cap, bed = GroundBuilder.CAP, GroundBuilder.BEDROCK
	local parts = 0
	for _, r in greedy(capKeys, N) do
		local top = tops[r.i0][r.k0]
		local s = GroundBuilder.SURFACES[string.split(r.key, "|")[2]]
		local w, d = (r.i1 - r.i0 + 1) * C, (r.k1 - r.k0 + 1) * C
		local cx, cz = x0 + (r.i0 - 1) * C + w / 2, z0 + (r.k0 - 1) * C + d / 2
		local capPart = newPart("Cap", CFrame.new(cx, top - cap / 2, cz), Vector3.new(w, cap, d), s.material, s.color)
		if s.variant then
			capPart.MaterialVariant = s.variant :: string -- falls back to the base material until Surfaces.apply() runs
		end
		capPart.Parent = folder
		parts += 1
	end
	for _, r in greedy(bodyKeys, N) do
		local top = tops[r.i0][r.k0] - cap
		if top - bed < 0.05 then
			continue
		end
		local b = GroundBuilder.BODIES[string.split(r.key, "|")[2]]
		local w, d = (r.i1 - r.i0 + 1) * C, (r.k1 - r.k0 + 1) * C
		local cx, cz = x0 + (r.i0 - 1) * C + w / 2, z0 + (r.k0 - 1) * C + d / 2
		newPart("Body", CFrame.new(cx, (top + bed) / 2, cz), Vector3.new(w, top - bed, d), b.material, b.color).Parent = folder
		parts += 1
	end
	folder.Parent = parent
	-- water: one flat slab per merged rect, from just above its highest bed cell to the level
	local waterRects = 0
	local waterFolder: Folder? = nil
	for _, r in greedy(waterKeys, N) do
		local wl = waters[r.i0][r.k0]
		local highest = -math.huge
		for ii = r.i0, r.i1 do
			for kk = r.k0, r.k1 do
				highest = math.max(highest, tops[ii][kk])
			end
		end
		local look = GroundBuilder.WATERS[string.split(r.key, "|")[2]]
		local w, d = (r.i1 - r.i0 + 1) * C, (r.k1 - r.k0 + 1) * C
		local cx, cz = x0 + (r.i0 - 1) * C + w / 2, z0 + (r.k0 - 1) * C + d / 2
		local bottom = highest + 0.05
		local slab = newPart("Water", CFrame.new(cx, (bottom + wl) / 2, cz), Vector3.new(w, wl - bottom, d), look.material, look.color)
		slab.CanCollide = false
		slab.CastShadow = false
		slab.Transparency = look.transparency
		slab.Reflectance = look.reflectance
		if not waterFolder then
			local f = Instance.new("Folder")
			f.Name = folder.Name
			waterFolder = f
		end
		slab.Parent = waterFolder
		waterRects += 1
	end
	if waterFolder then
		waterFolder.Parent = waterParent
	end
	return parts, waterRects
end

-- Build the whole ground (or only chunks intersecting `area`).
function GroundBuilder.build(ctx: any, area: { minX: number, maxX: number, minZ: number, maxZ: number }?)
	local root = GroundBuilder.folder()
	local x0, x1, z0, z1 = GroundBuilder.bounds()
	local C = GroundBuilder.CHUNK
	local chunksFolder = root:FindFirstChild("Chunks") or Instance.new("Folder")
	chunksFolder.Name = "Chunks"
	chunksFolder.Parent = root
	local waterFolder = GroundBuilder.waterFolder()
	if area then
		x0 = math.max(x0, math.floor(area.minX / C) * C)
		x1 = math.min(x1, math.ceil(area.maxX / C) * C)
		z0 = math.max(z0, math.floor(area.minZ / C) * C)
		z1 = math.min(z1, math.ceil(area.maxZ / C) * C)
		for cx = x0, x1 - C, C do
			for cz = z0, z1 - C, C do
				for _, f in { chunksFolder, waterFolder } do
					local old = f:FindFirstChild(string.format("%d_%d", cx, cz))
					if old then
						old:Destroy()
					end
				end
			end
		end
	else
		chunksFolder:ClearAllChildren()
		waterFolder:ClearAllChildren()
		workspace.Terrain:Clear() -- no smooth Terrain anywhere (the old ground was Terrain)
	end
	features:finalize()
	local total = ((x1 - x0) // C) * ((z1 - z0) // C)
	local done, parts, water = 0, 0, 0
	local started = os.clock()
	for cx = x0, x1 - C, C do
		for cz = z0, z1 - C, C do
			local p, w = GroundBuilder.buildChunk(ctx, cx, cz, chunksFolder, waterFolder)
			parts += p
			water += w
			done += 1
			setProgress(string.format("ground %d/%d chunks, %d parts (%.0fs)", done, total, parts, os.clock() - started))
			task.wait()
		end
	end
	local msg = string.format("ground done: %d chunks, %d parts, %d water slabs in %.0fs", total, parts, water, os.clock() - started)
	setProgress(msg)
	print("[MapGen] " .. msg)
end

-- ─── stairs (separate parts on top of a flat corridor) ─────────────────────────

-- Fit a flight's run to the ground as built. The planned run assumes the upper ground starts
-- exactly at foot + dir * run, but feature edges snap to heightfield cells, so the real edge
-- can sit up to a cell either side (and a diagonal flight meets a staircase of cells). March
-- along the flight at its centre line and both edges and return the nearest and furthest
-- distances at which the upper ground begins: the treads end at the nearest (no step is ever
-- buried in a column, which would leave a wall mid-flight) and a landing block fills the rest
-- up to the furthest (no drop beside the last step). The third result is false (and the
-- planned run is returned twice) if, on any line, the ground within `slack` of the planned end
-- never reaches the top, or overshoots it (a second ledge right behind the first).
function GroundBuilder.fitRun(ctx: any, foot: Vector3, dir: Vector3, run: number, rise: number, width: number, slack: number?): (number, number, boolean)
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local side = Vector3.new(-flat.Z, 0, flat.X)
	local reach = slack or 2 * GroundBuilder.CELL_COARSE
	local target = foot.Y + rise - 0.25
	local near, far = math.huge, -math.huge
	for _, u in { -0.5, -0.375, -0.25, -0.125, 0, 0.125, 0.25, 0.375, 0.5 } do
		local start = foot + side * (u * (width - 1))
		local found: number? = nil
		local d = math.max(1, run - reach)
		while d <= run + reach do
			local q = start + flat * d
			local top = GroundBuilder.builtTop(ctx, q.X, q.Z)
			if top >= target then
				if top > target + 0.5 then
					return run, run, false
				end
				found = d
				break
			end
			d += 0.5
		end
		if not found then
			return run, run, false
		end
		near = math.min(near, found :: number)
		far = math.max(far, found :: number)
	end
	-- 0.13 into the upper ground: an end face sits inside a column, never in the plane of a
	-- cell edge (where the lower cap's side face is)
	return near + 0.13, far + 0.13, true
end

-- Straight flight from `foot` (on the lower ground, at its top) climbing along `dir` by `rise`
-- over `run` studs, `width` wide. Risers are <= 1 stud (walkable). The n - 1 treads fill the
-- whole run and the last riser steps onto the upper ground itself (which must start at
-- foot + dir * run: see fitRun), so no step top is ever level with either ground surface.
-- With `landTo` beyond `run`, a landing block 0.25 below the upper ground fills from the last
-- tread to there (where the built edge of the upper ground is ragged across the flight).
function GroundBuilder.stairs(parent: Instance, foot: Vector3, dir: Vector3, run: number, rise: number, width: number, material: Enum.Material, color: Color3, landTo: number?): number
	local n = math.max(2, math.ceil(rise - 1e-6))
	local riser, tread = rise / n, run / (n - 1)
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local count = 0
	for k = 1, n - 1 do
		local topY = foot.Y + riser * k
		-- 0.3 into the cap: off the 0.5 grid every cap and body face sits on
		local bottom = foot.Y - 0.3
		local centre = foot + flat * (tread * (k - 0.5))
		local cf = CFrame.lookAt(Vector3.new(centre.X, (topY + bottom) / 2, centre.Z), Vector3.new(centre.X, (topY + bottom) / 2, centre.Z) + flat)
		local p = newPart("Step", cf, Vector3.new(width, topY - bottom, tread), material, color)
		p.Parent = parent
		count += 1
	end
	if landTo and landTo > run + 0.05 then
		local topY, bottom = foot.Y + rise - 0.25, foot.Y - 0.3
		local centre = foot + flat * ((run + landTo) / 2)
		local cf = CFrame.lookAt(Vector3.new(centre.X, (topY + bottom) / 2, centre.Z), Vector3.new(centre.X, (topY + bottom) / 2, centre.Z) + flat)
		local p = newPart("Landing", cf, Vector3.new(width, topY - bottom, landTo - run), material, color)
		p.Parent = parent
		count += 1
	end
	return count
end

return GroundBuilder
