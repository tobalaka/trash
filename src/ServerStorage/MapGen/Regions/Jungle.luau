--!strict
--[[
	Regions.Jungle - an old-growth jungle under a near-closed canopy.

	References: jungle.jpg (dense palms, ferns, purple flowers, mossy rock), imag.jpg (dark
	swamp, tall trunks, waterfall, shafts of light), oo2ued (river with sand banks, rock cliffs).
	Style: the reference world's forest floor (dark green grass caps on slate, ledges everywhere).

	Ground (flat features, GroundBuilder): grass plain with mossy and muddy patches, stacked
	grass-capped plateaus, a river cut as a sandy bank shelf with a deep channel of water slabs
	starting at a plunge pool under the north cliff, swamp basins, and the greybox's thin jungle
	walls turned into a stacked rock cliff ridge with grass on every ledge.
]]

local Config = require(script.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.Layout)
local FeatureMap = require(script.Parent.Parent.FeatureMap)
local GroundBuilder = require(script.Parent.Parent.GroundBuilder)

local Jungle = {}
Jungle.NAME = "Jungle"

local S = Config.GROUND.SURFACE_Y
Jungle.BASE_Y = S + 2
Jungle.BASE_KEY = "JungleGrass"
Jungle.ROCK_KEY = "JungleRock"
Jungle.RIVER_WIDTH = 50
Jungle.RIVER_DEPTH = 12
Jungle.RIVER_LEVEL = Jungle.BASE_Y - 4.75 -- water surface (off the 0.5 grid)
Jungle.POOL_COUNT = 6
Jungle.PLATEAU_COUNT = 18
Jungle.HIGHLAND_COUNT = 11 -- forest hills: grass ledges climbing 25-65 studs

export type Plan = { river: { Vector3 }, falls: Vector3, pools: { { c: Vector3, r: number } } }
local plan: Plan? = nil

local function segDist(px: number, pz: number, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(px - a.X, pz - a.Z)
	local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (ap - ab * t).Magnitude
end

local function riverDistOn(river: { Vector3 }, x: number, z: number): number
	local best = math.huge
	for i = 1, #river - 1 do
		best = math.min(best, segDist(x, z, river[i], river[i + 1]))
	end
	return best
end

function Jungle.riverDist(ctx: any, x: number, z: number): number
	return riverDistOn(Jungle.plan(ctx).river, x, z)
end

function Jungle.plan(ctx: any): Plan
	if plan then
		return plan
	end
	local rect = Layout.rectsOf("Jungle")[1]
	local half = (rect.cf.Rotation * rect.size):Abs() / 2
	local north = rect.cf.Z + half.Z -- the cliff wall side (+Z)
	local south = rect.cf.Z - half.Z
	local x0 = rect.cf.X + half.X * 0.15
	local river = {}
	local n = 16
	for i = 0, n do
		local t = i / n
		local z = (north - 70) + (south - 40 - (north - 70)) * t
		local x = x0 + math.sin(t * math.pi * 2.6) * half.X * 0.32 + math.noise(t * 4, 9.1) * 90
		table.insert(river, Vector3.new(x, Jungle.BASE_Y, z))
	end
	local rng = Random.new(Config.SEED + 44)
	local pools = {}
	for _ = 1, Jungle.POOL_COUNT do
		for _ = 1, 50 do
			local x = rect.cf.X + rng:NextNumber(-0.42, 0.42) * rect.size.X
			local z = rect.cf.Z + rng:NextNumber(-0.42, 0.42) * rect.size.Z
			if riverDistOn(river, x, z) > 220 then
				table.insert(pools, { c = Vector3.new(x, Jungle.BASE_Y, z), r = rng:NextNumber(45, 95) })
				break
			end
		end
	end
	plan = { river = river, falls = river[1], pools = pools }
	return plan :: Plan
end

-- ─── ground interface (GroundBuilder) ─────────────────────────────────────────

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

function Jungle.ground(ctx: any, fm: FeatureMap.Map)
	local p = Jungle.plan(ctx)
	local rng = Random.new(Config.SEED + 45)
	local base = Jungle.BASE_Y
	-- cliff ridge from the thin greybox walls: thickened, stacked, grass on every ledge
	for _, b in Layout.blocksOf("JungleCliff") do
		local cx, cz, yaw, half, top = GroundBuilder.footprint(b.cf, b.size)
		half = Vector2.new(math.max(half.X, 60), math.max(half.Y, 60))
		GroundBuilder.rockTiers(fm, cx, cz, yaw, half, { base = base, top = top, key = "JungleMoss", tierHeight = 24, inset = 0.12, buttresses = 8, layer = 2, rng = rng })
	end
	-- plateaus: 1-4 grass ledges of 4-7 studs, kept off the river and the pools
	local rect = Layout.rectsOf("Jungle")[1]
	local half = (rect.cf.Rotation * rect.size):Abs() / 2
	local placed = 0
	for _ = 1, 400 do
		if placed >= Jungle.PLATEAU_COUNT then
			break
		end
		local x = rect.cf.X + rng:NextNumber(-0.9, 0.9) * half.X
		local z = rect.cf.Z + rng:NextNumber(-0.9, 0.9) * half.Z
		local hx, hz = rng:NextNumber(50, 170), rng:NextNumber(50, 170)
		local reach = math.max(hx, hz)
		local clear = Layout.regionAt(x, z) == "Jungle" and Jungle.riverDist(ctx, x, z) > reach + 70
		for _, pool in p.pools do
			if Vector2.new(x - pool.c.X, z - pool.c.Z).Magnitude < pool.r + reach + 30 then
				clear = false
			end
		end
		if clear then
			GroundBuilder.terrace(fm, x, z, hx, hz, base, rng:NextNumber(4, 7), rng:NextInteger(1, 4), rng:NextNumber() < 0.5 and "JungleGrass" or "JungleMoss", rng, 1)
			placed += 1
		end
	end
	-- forest hills, clear of the river course and the swamp pools
	local avoid = {}
	for _, pt in p.river do
		table.insert(avoid, { c = pt, r = Jungle.RIVER_WIDTH + 70 })
	end
	for _, pool in p.pools do
		table.insert(avoid, { c = pool.c, r = pool.r + 40 })
	end
	highlands(fm, "Jungle", Jungle.HIGHLAND_COUNT, base, 90, 200, 25, 65, { "JungleGrass", "JungleMoss" }, rng, avoid)
	-- river: sandy bank shelf, then the channel with water (layer 3, carve)
	local hw = Jungle.RIVER_WIDTH / 2
	for i = 1, #p.river - 1 do
		fm:segment("carve", 3, p.river[i], p.river[i + 1], hw + 16, base - 3, "RiverSand")
	end
	for i = 1, #p.river - 1 do
		fm:segment("carve", 3, p.river[i], p.river[i + 1], hw, base - Jungle.RIVER_DEPTH, "JungleMud", Jungle.RIVER_LEVEL)
	end
	-- plunge pool under the falls
	GroundBuilder.basin(fm, p.falls.X, p.falls.Z, 90, 70, base - 3, base - 16, Jungle.RIVER_LEVEL, "RiverSand", "JungleMud", rng)
	-- swamp pools
	for _, pool in p.pools do
		GroundBuilder.basin(fm, pool.c.X, pool.c.Z, pool.r, pool.r * rng:NextNumber(0.7, 1), base - 1.5, base - 7, base - 2.75, "JungleMud", "JungleMud", rng)
	end
end

-- Blocky moss and mud patches on the plain, sampled per 48-stud block.
function Jungle.patch(ctx: any, x: number, z: number, top: number, key: string): string
	if key ~= "JungleGrass" then
		return key
	end
	local n = math.noise(math.floor(x / 48) * 0.63, math.floor(z / 48) * 0.63, 2.4)
	if n > 0.4 then
		return "JungleMoss"
	elseif n < -0.5 then
		return "JungleMud"
	end
	return key
end

-- ─── populate ─────────────────────────────────────────────────────────────────
-- Enormous part-built trees (Structures.Nature, after the reference's redwoods), smaller trees
-- between them, light shafts falling through the canopy, undergrowth from the audited kit
-- props, and the old stone gate facing the town.

Jungle.GIANT_TREES = 42
Jungle.SMALL_TREES = 150
Jungle.SHAFTS = 36
Jungle.UNDERGROWTH = 520
local UNDERGROWTH = { "Fern1", "Fern2", "Fern3", "FlowerPatch", "Mushrooms", "MossRock1", "MossRock2", "MossRock3", "GiantRoot1", "GiantRoot2", "FallenLog1", "FallenLog2", "RuinColumn1", "RuinWall1" }

function Jungle.populate(ctx: any, folder: Folder)
	local Kit = require(script.Parent.Parent.Kit) :: any
	local PlacementUtil = require(script.Parent.Parent.PlacementUtil) :: any
	local Decor = require(script.Parent.Parent.Decor) :: any
	local Nature = require(script.Parent.Parent.Structures.Nature) :: any
	local data = Layout.dataFolder()
	local p = Jungle.plan(ctx)
	local rng = Random.new(Config.SEED + 46)
	local rect = Layout.rectsOf("Jungle")[1]
	local half = (rect.cf.Rotation * rect.size):Abs() / 2
	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
		return f
	end
	local fTrees, fShafts, fUnder, fRuins = sub("Trees"), sub("LightShafts"), sub("Undergrowth"), sub("Ruins")

	-- a dry spot inside the jungle: not in water, not on the river, not near a pool
	local taken: { { c: Vector3, r: number } } = {}
	local function spot(radius: number, gap: number): Vector3?
		for _ = 1, 40 do
			local x = rect.cf.X + rng:NextNumber(-0.95, 0.95) * half.X
			local z = rect.cf.Z + rng:NextNumber(-0.95, 0.95) * half.Z
			if Layout.regionAt(x, z) ~= "Jungle" or Jungle.riverDist(ctx, x, z) < Jungle.RIVER_WIDTH + radius then
				continue
			end
			local ok = true
			for _, t in taken do
				if Vector2.new(x - t.c.X, z - t.c.Z).Magnitude < t.r + radius + gap then
					ok = false
					break
				end
			end
			if not ok or PlacementUtil.isWater(x, z) then
				continue
			end
			-- trunks stand on the lowest ground under them (the trunk buries the higher side)
			local lowest = math.huge
			for _, o in { Vector2.zero, Vector2.new(radius, 0), Vector2.new(-radius, 0), Vector2.new(0, radius), Vector2.new(0, -radius) } do
				local g = PlacementUtil.ground(x + o.X, z + o.Y)
				if not g then
					ok = false
					break
				end
				lowest = math.min(lowest, g.position.Y)
			end
			if ok then
				return Vector3.new(x, lowest, z)
			end
		end
		return nil
	end

	-- lattice phase by position: trees in neighbouring 100-stud cells always differ (16 phases,
	-- 0.03 apart), so overlapping canopies never put two slabs in one plane
	local function phaseAt(v: Vector3): number
		local cx, cz = math.floor(v.X / 100), math.floor(v.Z / 100)
		return ((cx * 5 + cz * 3) % 16) * 0.03
	end
	data:SetAttribute("Progress", "jungle: giant trees")
	local giants: { Vector3 } = {}
	for i = 1, Jungle.GIANT_TREES do
		local trunk = rng:NextNumber(18, 30)
		local at = spot(trunk, 70)
		if at then
			local spec = { height = rng:NextNumber(150, 240), trunk = trunk, canopy = rng:NextNumber(130, 220), tiers = rng:NextInteger(3, 5), phase = phaseAt(at) }
			local tree = Nature.tree(fTrees, CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0), spec, rng)
			tree.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			table.insert(taken, { c = at, r = trunk })
			table.insert(giants, at + Vector3.new(0, spec.height * 0.55, 0))
		end
		if i % 6 == 0 then
			task.wait()
		end
	end
	data:SetAttribute("Progress", "jungle: trees")
	for i = 1, Jungle.SMALL_TREES do
		local at = spot(6, 22)
		if at then
			local tree = Nature.smallTree(fTrees, CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0), rng, phaseAt(at) + 0.015)
			tree.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
			table.insert(taken, { c = at, r = 6 })
		end
		if i % 20 == 0 then
			task.wait()
		end
	end

	-- light shafts: from just under a giant's canopy down to the floor beside it
	for i = 1, math.min(Jungle.SHAFTS, #giants) do
		local top = giants[i]
		local a = rng:NextNumber(0, 2 * math.pi)
		local foot = PlacementUtil.ground(top.X + math.cos(a) * 50, top.Z + math.sin(a) * 50)
		if foot then
			Decor.lightShaft(fShafts, top + Vector3.new(math.cos(a) * 20, 0, math.sin(a) * 20), foot.position, rng:NextNumber(18, 34), Color3.fromRGB(236, 255, 210), 0.84)
		end
	end

	-- undergrowth (kit props that passed the mesh Z-fighting audit)
	data:SetAttribute("Progress", "jungle: undergrowth")
	Kit.preload(UNDERGROWTH)
	local spacing = PlacementUtil.spacing()
	for _, t in taken do
		PlacementUtil.reserve(spacing, t.c.X, t.c.Z, t.r + 2)
	end
	for i = 1, Jungle.UNDERGROWTH do
		local x = rect.cf.X + rng:NextNumber(-0.95, 0.95) * half.X
		local z = rect.cf.Z + rng:NextNumber(-0.95, 0.95) * half.Z
		if Layout.regionAt(x, z) == "Jungle" and Jungle.riverDist(ctx, x, z) > Jungle.RIVER_WIDTH / 2 + 18 then
			local name = UNDERGROWTH[rng:NextInteger(1, #UNDERGROWTH)]
			local prop = Kit.clone(name)
			Kit.vary(prop, rng, 0.15)
			local big = name:match("Ruin") or name:match("Log") or name:match("Root")
			local _, size = prop:GetBoundingBox()
			local r = math.max(size.X, size.Z) / 2
			if not PlacementUtil.scatterOne(spacing, prop, x, z, r, { yaw = rng:NextNumber(0, 2 * math.pi), embed = 0.3, maxStep = big and 0.5 or 2, parent = big and fRuins or fUnder }) then
				prop:Destroy()
			end
		end
		if i % 60 == 0 then
			task.wait()
		end
	end

	-- the old stone gate at the jungle's edge, facing the town
	local gx, gz = rect.cf.X - half.X + 110, rect.cf.Z
	local g = PlacementUtil.ground(gx, gz)
	if g then
		local at = Vector3.new(gx, g.position.Y - 0.25, gz)
		Nature.ruinGate(fRuins, CFrame.lookAt(at, at + Vector3.new(-1, 0, 0)) * CFrame.Angles(0, math.rad(2), 0), rng)
	end
	data:SetAttribute("Progress", string.format("jungle: done (%d giant trees)", #giants))
	print(string.format("[MapGen] Jungle: %d giant trees, %d trees and props", #giants, #fTrees:GetChildren()))
end

function Jungle.reset()
	plan = nil
end

return Jungle
