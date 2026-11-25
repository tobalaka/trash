--!strict
--[[
	Regions.Desert - sand flats, stepped dunes, block-built mesas and the Smog Spire.

	References: a dune sea with a slender spire cluster on the horizon, o_1g (red
	canyon, cacti, hazy sun), edea (mushroom rocks), holy.jpg (faceted orange mountains).

	Ground (flat features, GroundBuilder): a flat sand plain; dunes are long low terraces of
	stacked sand slabs running across the wind; the greybox canyon blocks become mesas of
	stacked sandstone tiers with buttresses (the reference's cliff stacks); a paved road toward
	the tower; an oasis basin with grass and water slabs.

	The Smog Spire: a slender pale column (an old smokestack) rising out of a
	huge ridged rock cone in the sand. Here the cone is ground: 24 flat ledges (irregular discs)
	with radial ridge spurs, and a canyon stairway cut straight up one side to the summit
	platform. The column is a 20-sided shaft of Parts (populate) climbing to ~1,180 studs, with
	a door at its foot, ring bands, window slits, a broken crown and a beacon.
]]

local Config = require(script.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.Layout)
local FeatureMap = require(script.Parent.Parent.FeatureMap)
local GroundBuilder = require(script.Parent.Parent.GroundBuilder)

local Desert = {}
Desert.NAME = "Desert"

local S = Config.GROUND.SURFACE_Y
Desert.BASE_Y = S + 3 -- a jump above the town plains: the desert is a raised sand plateau
Desert.BASE_KEY = "Sand"
Desert.ROCK_KEY = "DesertMesa"
Desert.DUNE_COUNT = 46 -- long stepped dune terraces
Desert.DUNE_STEP = 3.5 -- height of one dune slab
Desert.HIGHLAND_COUNT = 8 -- big stepped sand hills (the dune sea, in blocks)
Desert.MESA_TIER_H = 22
-- The Smog Spire
Desert.AMO_BASE_R = 470 -- cone footprint radius
Desert.AMO_CONE_H = 320 -- summit platform height above the sand
Desert.AMO_TIERS = 24
Desert.AMO_RIDGES = 14
Desert.AMO_SHAFT_R = 58 -- column circumradius
Desert.AMO_TOP = 1180 -- column top above the sand
Desert.AMO_STAIR_W = 26
Desert.AMO_SIDES = 20
Desert.TOWER_FOUNDATION = Desert.AMO_BASE_R -- kept clear of dunes and highlands
Desert.SCATTER = 320 -- cacti, hoodoos, arches
Desert.PATH_WIDTH = 30
Desert.OASIS_RADIUS = 70

export type Plan = { tower: Vector3, path: { Vector3 }, oasis: Vector3 }
local plan: Plan? = nil

local function segDist(px: number, pz: number, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(px - a.X, pz - a.Z)
	local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (ap - ab * t).Magnitude
end

local function pathDist(p: Plan, x: number, z: number): number
	local best = math.huge
	for i = 1, #p.path - 1 do
		best = math.min(best, segDist(x, z, p.path[i], p.path[i + 1]))
	end
	return best
end

function Desert.plan(ctx: any): Plan
	if plan then
		return plan
	end
	local data = Layout.get()
	local rect = Layout.rectsOf("Desert")[1]
	local towerPos = data.tower and Vector3.new(data.tower.cf.X, Desert.BASE_Y, data.tower.cf.Z) or Vector3.new(rect.cf.X, Desert.BASE_Y, rect.cf.Z)
	-- approach road: from the tower toward the desert centre, then on to the town-side edge
	local centre = Vector3.new(rect.cf.X, S, rect.cf.Z)
	local half = (rect.cf.Rotation * rect.size):Abs() / 2
	local exit = Vector3.new(centre.X + half.X * 0.2, S, rect.cf.Z - half.Z + 40) -- south edge, toward town
	local path = {}
	local steps = 10
	for i = 0, steps do
		local t = i / steps
		local a = towerPos:Lerp(centre, math.min(1, t * 1.6))
		local b = centre:Lerp(exit, math.max(0, t * 1.6 - 0.6))
		local p = t < 0.6 and a or b
		p += Vector3.new(math.noise(t * 3, 1.5) * 120, 0, math.noise(t * 3, 4.5) * 120)
		table.insert(path, Vector3.new(p.X, S, p.Z))
	end
	path[1] = towerPos
	plan = { tower = towerPos, path = path, oasis = path[5] + Vector3.new(110, 0, 60) }
	return plan :: Plan
end

-- ─── ground interface (GroundBuilder) ─────────────────────────────────────────

local amoCone: (p: any, fm: FeatureMap.Map, base: number, rng: Random) -> ()

-- Stepped highlands placed inside one region, clear of `avoid` discs.
local function highlands(fm: FeatureMap.Map, region: string, count: number, base: number, sizeMin: number, sizeMax: number, hMin: number, hMax: number, keys: { string }, rng: Random, avoid: { { c: Vector3, r: number } })
	local rects = Layout.rectsOf(region)
	local placed = 0
	for _ = 1, count * 30 do
		if placed >= count then
			break
		end
		local rect = rects[rng:NextInteger(1, #rects)]
		local half = (rect.cf.Rotation * rect.size):Abs() / 2
		local x = rect.cf.X + rng:NextNumber(-0.85, 0.85) * half.X
		local z = rect.cf.Z + rng:NextNumber(-0.85, 0.85) * half.Z
		local hx, hz = rng:NextNumber(sizeMin, sizeMax), rng:NextNumber(sizeMin, sizeMax)
		local clear = Layout.regionAt(x, z) == region
		for _, a in avoid do
			if Vector2.new(x - a.c.X, z - a.c.Z).Magnitude < a.r + math.max(hx, hz) then
				clear = false
				break
			end
		end
		if clear then
			GroundBuilder.highland(fm, x, z, hx, hz, base, rng:NextNumber(hMin, hMax), rng:NextNumber(4, 6), keys[rng:NextInteger(1, #keys)], rng, 1)
			placed += 1
		end
	end
end

function Desert.ground(ctx: any, fm: FeatureMap.Map)
	local p = Desert.plan(ctx)
	local rng = Random.new(Config.SEED + 33)
	local base = Desert.BASE_Y
	-- mesas from the greybox canyon blocks (layer 2, raise)
	for _, b in Layout.blocksOf("DesertRock") do
		local cx, cz, yaw, half, top = GroundBuilder.footprint(b.cf, b.size)
		GroundBuilder.rockTiers(fm, cx, cz, yaw, half, { base = base, top = top, key = "DesertMesa", tierHeight = Desert.MESA_TIER_H, inset = 0.14, buttresses = 4, layer = 2, rng = rng })
	end
	-- dunes: long slabs across the wind (axis-aligned; the long side runs along X), 1-3 tiers
	local rect = Layout.rectsOf("Desert")[1]
	local half = (rect.cf.Rotation * rect.size):Abs() / 2
	local placed = 0
	for _ = 1, 400 do
		if placed >= Desert.DUNE_COUNT then
			break
		end
		local x = rect.cf.X + rng:NextNumber(-0.92, 0.92) * half.X
		local z = rect.cf.Z + rng:NextNumber(-0.92, 0.92) * half.Z
		local hx, hz = rng:NextNumber(90, 260), rng:NextNumber(26, 70)
		local clear = Layout.regionAt(x, z) == "Desert"
			and pathDist(p, x, z) > hz + Desert.PATH_WIDTH + 20
			and Vector2.new(x - p.tower.X, z - p.tower.Z).Magnitude > Desert.TOWER_FOUNDATION + hx
			and Vector2.new(x - p.oasis.X, z - p.oasis.Z).Magnitude > Desert.OASIS_RADIUS * 2 + hx
		if clear then
			GroundBuilder.terrace(fm, x, z, hx, hz, base, Desert.DUNE_STEP, rng:NextInteger(1, 3), rng:NextNumber() < 0.4 and "SandDark" or "Sand", rng, 1)
			placed += 1
		end
	end
	-- big stepped sand hills, clear of the tower, the oasis and the road's start
	local avoid = { { c = p.tower, r = Desert.TOWER_FOUNDATION + 420 }, { c = p.oasis, r = Desert.OASIS_RADIUS * 2.5 } }
	for i = 1, #p.path, 2 do
		table.insert(avoid, { c = p.path[i], r = Desert.PATH_WIDTH + 30 })
	end
	highlands(fm, "Desert", Desert.HIGHLAND_COUNT, base, 120, 260, 24, 56, { "Sand", "SandDark" }, rng, avoid)
	-- the road: a paved strip at plain level, stopping at the foot of the tower cone
	for i = 1, #p.path - 1 do
		local a, b = p.path[i], p.path[i + 1]
		if Vector2.new(a.X - p.tower.X, a.Z - p.tower.Z).Magnitude > Desert.AMO_BASE_R + 40 then
			fm:segment("set", 4, a, b, Desert.PATH_WIDTH / 2, base, "DesertPath")
		end
	end
	-- oasis: a grass apron, then a stepped basin with clear water
	local o = p.oasis
	local r = Desert.OASIS_RADIUS
	fm:box("set", 4, o.X - r * 1.5, o.X + r * 1.5, o.Z - r * 1.2, o.Z + r * 1.2, base, "OasisGrass")
	GroundBuilder.basin(fm, o.X, o.Z, r, r * 0.8, base - 1, base - 6, base - 2.25, "OasisGrass", "RiverSand", rng, 5)
	amoCone(p, fm, base, rng)
end

-- ─── the Smog Spire ─────────────────────────────────────────────────────────────

-- Direction from the tower toward the open desert: the stairway climbs the cone from there.
-- Nudged off the axes so the flight is never parallel to the ground columns' faces.
function Desert.stairDir(p: Plan): Vector3
	local rect = Layout.rectsOf("Desert")[1]
	local d = Vector3.new(rect.cf.X - p.tower.X, 0, rect.cf.Z - p.tower.Z).Unit
	local a = math.atan2(d.Z, d.X)
	local snapped = math.floor(a / (math.pi / 2) + 0.5) * (math.pi / 2)
	if math.abs(a - snapped) < math.rad(3) then
		a = snapped + math.rad(4)
	end
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- Radius of ledge t (0 = foot, 1 = summit): narrows faster near the top.
local function coneRadius(t: number): number
	return Desert.AMO_BASE_R + (Desert.AMO_SHAFT_R + 34 - Desert.AMO_BASE_R) * t ^ 0.75
end

amoCone = function(p: Plan, fm: FeatureMap.Map, base: number, rng: Random)
	local t = p.tower
	local n = Desert.AMO_TIERS
	-- ledges: irregular discs (wobble) stacked to the summit; the lowest ones are sand-caked
	for i = 1, n do
		local r = coneRadius((i - 1) / (n - 1))
		fm:disc("raise", 2, t.X, t.Z, r, base + Desert.AMO_CONE_H * i / n, i <= 5 and "SandDark" or "DesertMesa", i < n and 0.13 or 0.04, 40 + i)
	end
	-- ridge spurs radiating down the flanks (the buttresses in the reference panel), standing
	-- proud of the ledges they cross; none on the stair side
	local up = Desert.stairDir(p)
	for k = 1, Desert.AMO_RIDGES do
		local a = (k + rng:NextNumber(-0.3, 0.3)) / Desert.AMO_RIDGES * 2 * math.pi
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		if dir:Dot(up) < 0.9 then
			local r0, r1 = Desert.AMO_SHAFT_R + 40, Desert.AMO_BASE_R * 1.16
			local segs = 6
			for j = 1, segs do
				local ra, rb = r0 + (r1 - r0) * (j - 1) / segs, r0 + (r1 - r0) * j / segs
				local rm = (ra + rb) / 2
				local tt = math.clamp(((Desert.AMO_BASE_R - rm) / (Desert.AMO_BASE_R - Desert.AMO_SHAFT_R - 34)), 0, 1) ^ (1 / 0.75)
				local top = base + Desert.AMO_CONE_H * tt + rng:NextNumber(10, 24)
				local c = t + dir * rm
				-- rect local X runs along the spur (yaw = -a)
				fm:rect("raise", 2, c.X, c.Z, (rb - ra) / 2 + 6, (34 - 2.5 * j) / 2 + rng:NextNumber(0, 6), top, "DesertMesa", -a)
			end
		end
	end
	-- summit platform for the column
	fm:disc("raise", 2, t.X, t.Z, Desert.AMO_SHAFT_R + 34, base + Desert.AMO_CONE_H, "DesertPath", 0, 0)
	-- canyon for the stairway: cut to sand level, 20 wider than the flight on each side (more
	-- than a coarse ground cell) so no step ever overlaps a ledge column (layer 4, set)
	local r0, r1 = Desert.AMO_SHAFT_R + 34, Desert.AMO_BASE_R * 1.2
	local mid = t + up * ((r0 + r1) / 2)
	fm:rect("set", 4, mid.X, mid.Z, (r1 - r0) / 2, Desert.AMO_STAIR_W / 2 + 20, base, "DesertPath", math.atan2(-up.Z, up.X))
end

-- The stairway: sand level at the canyon mouth up to the summit platform.
function Desert.groundParts(ctx: any, parent: Instance)
	local p = Desert.plan(ctx)
	local up = Desert.stairDir(p)
	local base = Desert.BASE_Y
	local outer = p.tower + up * (Desert.AMO_BASE_R * 1.2 - 4)
	local inner = Desert.AMO_SHAFT_R + 34
	local run = Desert.AMO_BASE_R * 1.2 - 4 - inner
	local folder = Instance.new("Folder")
	folder.Name = "SpireStairs"
	local s = GroundBuilder.SURFACES.DesertMesa
	-- the canyon cut's inner end snaps to coarse cells, so fit the run to the summit as built
	local foot = Vector3.new(outer.X, base, outer.Z)
	local landTo
	run, landTo = GroundBuilder.fitRun(ctx, foot, -up, run, Desert.AMO_CONE_H, Desert.AMO_STAIR_W)
	local n = GroundBuilder.stairs(folder, foot, -up, run, Desert.AMO_CONE_H, Desert.AMO_STAIR_W, s.material, s.color, landTo)
	folder.Parent = parent
	print(string.format("[MapGen] Smog Spire stairway: %d steps", n))
end

-- The column (a structure, so it lives in Workspace.World.Desert).
function Desert.populate(ctx: any, folder: Folder)
	local PartKit = require(script.Parent.Parent.PartKit) :: any
	local Decor = require(script.Parent.Parent.Decor) :: any
	local p = Desert.plan(ctx)
	local up = Desert.stairDir(p)
	local m = Instance.new("Model")
	m.Name = "SmogSpire"
	local C = Color3.fromRGB
	local PALE, BAND, DARK = C(222, 216, 202), C(186, 176, 160), C(52, 48, 46)
	local foot = Desert.BASE_Y + Desert.AMO_CONE_H -- summit platform top
	local top = Desert.BASE_Y + Desert.AMO_TOP
	local n = Desert.AMO_SIDES
	local R = Desert.AMO_SHAFT_R
	local apothem = R * math.cos(math.pi / n)
	local panelW = 2 * R * math.sin(math.pi / n) + 0.3
	local tcf = CFrame.new(p.tower.X, 0, p.tower.Z)
	local rng = Random.new(Config.SEED + 77)
	local door = 26
	for k = 0, n - 1 do
		-- half a step turned: no panel faces along X or Z (never parallel to ground columns)
		local a = (k + 0.5) / n * 2 * math.pi
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		-- neighbouring panels overlap at their inner corners: odd ones start and end 0.25 higher,
		-- so their end faces are never level with a neighbour's
		local odd = k % 2 * 0.25
		local y0 = dir:Dot(up) > 0.97 and foot + door + odd or foot - 0.5 + odd -- the doorway faces the stairs
		local y1 = top + odd
		local pos = dir * apothem + Vector3.new(0, (y0 + y1) / 2, 0)
		PartKit.part(m, tcf, CFrame.lookAt(pos, pos + dir), Vector3.new(panelW, y1 - y0, 5), Enum.Material.Concrete, PALE, "Shaft")
		-- broken crown: each panel ends in a block of its own height (thinner, so its side faces
		-- never continue the panel's)
		local h = rng:NextNumber(4, 46)
		local cpos = dir * apothem + Vector3.new(0, y1 + h / 2, 0)
		PartKit.part(m, tcf, CFrame.lookAt(cpos, cpos + dir), Vector3.new(panelW - 0.6, h, 4.4), Enum.Material.Concrete, PALE, "Crown")
		-- window slits every third panel, 0.3 proud of the face
		if k % 3 == 0 then
			for y = foot + 130, top - 60, 70 + k do
				if (y - foot) % 90 < 10 or (y - foot) % 90 > 80 then
					continue -- keep slits clear of the ring bands
				end
				local wpos = dir * (apothem + 2.5 + 0.15) + Vector3.new(0, y, 0)
				PartKit.part(m, tcf, CFrame.lookAt(wpos, wpos + dir), Vector3.new(2.4, 11, 0.3), Enum.Material.Slate, DARK, "Slit", { collide = false, shadow = false })
			end
		end
	end
	-- ring bands every 90 studs, 1.5 proud of the shaft
	for y = foot + 90, top - 30, 90 do
		for k = 0, n - 1 do
			local a = (k + 0.5) / n * 2 * math.pi
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local pos = dir * (apothem + 1.5) + Vector3.new(0, y, 0)
			-- alternate section height: overlapping neighbours never share a top or bottom plane
			PartKit.part(m, tcf, CFrame.lookAt(pos, pos + dir), Vector3.new(panelW + 0.6, k % 2 == 0 and 3 or 2.6, 5), Enum.Material.Concrete, BAND, "Ring", { shadow = false })
		end
	end
	-- a lit hall inside the doorway
	local hall = apothem * 1.3
	PartKit.part(m, tcf, CFrame.new(0, foot + 0.2, 0), Vector3.new(hall, 0.4, hall), Enum.Material.Slate, BAND, "HallFloor")
	for _, a in { 0, 2.1, 4.2 } do
		local l = PartKit.part(m, tcf, CFrame.new(math.cos(a) * 20, foot + 14, math.sin(a) * 20), Vector3.new(1.4, 1.4, 1.4), Enum.Material.Neon, C(255, 186, 120), "HallLamp", { collide = false, shadow = false })
		local light = Instance.new("PointLight")
		light.Color = C(255, 171, 103)
		light.Brightness = 1.6
		light.Range = 40
		light.Shadows = false
		light.Parent = l
	end
	-- beacon on the summit, visible across the desert
	local beacon = PartKit.part(m, tcf, CFrame.new(0, top + 8, 0), Vector3.new(6, 6, 6), Enum.Material.Neon, C(255, 214, 150), "Beacon", { collide = false, shadow = false })
	local light = Instance.new("PointLight")
	light.Color = C(255, 196, 130)
	light.Brightness = 3
	light.Range = 60
	light.Shadows = false
	light.Parent = beacon
	Decor.glow(beacon, C(255, 210, 140), 60)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- a landmark seen from everywhere
	m.Parent = folder
	print(string.format("[MapGen] Smog Spire: %.0f studs tall", top - Desert.BASE_Y))

	-- scatter: cacti, hoodoos and rock arches (kit props that passed the mesh audit), kept off
	-- the road, the oasis water and the tower cone
	local Kit = require(script.Parent.Parent.Kit) :: any
	local PlacementUtil = require(script.Parent.Parent.PlacementUtil) :: any
	local AssetIds = require(script.Parent.Parent.Data.AssetIds) :: any
	local names = {}
	for _, n in { "Cactus1", "Cactus2", "Cactus3", "HoodooRock1", "HoodooRock2", "RockArch" } do
		if AssetIds[n] then
			table.insert(names, n)
		end
	end
	Kit.preload(names)
	local fProps = Instance.new("Folder")
	fProps.Name = "Scatter"
	fProps.Parent = folder
	local spacing = PlacementUtil.spacing()
	PlacementUtil.reserve(spacing, p.tower.X, p.tower.Z, Desert.AMO_BASE_R * 1.25)
	local rect = Layout.rectsOf("Desert")[1]
	local half = (rect.cf.Rotation * rect.size):Abs() / 2
	for i = 1, Desert.SCATTER do
		local x = rect.cf.X + rng:NextNumber(-0.95, 0.95) * half.X
		local z = rect.cf.Z + rng:NextNumber(-0.95, 0.95) * half.Z
		if Layout.regionAt(x, z) == "Desert" and pathDist(p, x, z) > Desert.PATH_WIDTH and not PlacementUtil.isWater(x, z) then
			local prop = Kit.clone(names[rng:NextInteger(1, #names)])
			Kit.vary(prop, rng, 0.2)
			local _, size = prop:GetBoundingBox()
			if not PlacementUtil.scatterOne(spacing, prop, x, z, math.max(size.X, size.Z) / 2 + 1, { yaw = rng:NextNumber(0, 2 * math.pi), embed = 0.4, maxStep = 0.5, parent = fProps }) then
				prop:Destroy()
			end
		end
		if i % 50 == 0 then
			task.wait()
		end
	end
end

function Desert.reset()
	plan = nil
end

return Desert
