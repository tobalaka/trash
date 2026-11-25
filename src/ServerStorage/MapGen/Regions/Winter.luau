--!strict
--[[
	Regions.Winter - barren, open, wind-scoured snowfield under a mountain wall.

	References: cold.jpg (faceted peaks, frozen lake, snowfall), winter.jpg / something.jpg
	(cold fog, blue-grey light). Per the brief the old pines and lake floes are gone: this is an
	open fighting ground with sparse destructible props.

	Ground (flat features, GroundBuilder): a flat snow plain with a few low snow ledges and rock
	outcrops; the frozen lake is one flat sheet of ice; the mountains along the back edge of
	each winter rectangle are stacked rock blocks (grey slate sides, snow on every ledge),
	rising in tiers like the reference's cliffs instead of noise peaks.
]]

local Config = require(script.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.Layout)
local FeatureMap = require(script.Parent.Parent.FeatureMap)
local GroundBuilder = require(script.Parent.Parent.GroundBuilder)

local Winter = {}
Winter.NAME = "Winter"

local S = Config.GROUND.SURFACE_Y
Winter.BASE_Y = S - 1
Winter.BASE_KEY = "Snow"
Winter.ROCK_KEY = "WinterRock"
Winter.MOUNTAIN_DEPTH = 760 -- studs from the back edge the mountain blocks reach into the field
Winter.MOUNTAIN_HEIGHT = 520
Winter.MOUNTAIN_TIER_H = 34
Winter.LAKE_RADIUS = 260
Winter.LEDGE_COUNT = 10 -- low snow ledges on the field
Winter.HIGHLAND_COUNT = 8 -- stepped snow hills in front of the mountain wall
Winter.OUTCROP_COUNT = 10

export type Plan = { backZ: number, lake: Vector3 }
local plan: Plan? = nil

function Winter.plan(ctx: any): Plan
	if plan then
		return plan
	end
	local backZ = math.huge
	for _, r in Layout.rectsOf("Winter") do
		local half = (r.cf.Rotation * r.size):Abs() / 2
		backZ = math.min(backZ, r.cf.Z - half.Z)
	end
	-- the old frozen lake sat at (300, -2300) in greybox space; keep that spot, scaled
	local o = Layout.get().origin
	local lake = Layout.scaleXZ(Vector3.new(300, S, -2300), o)
	plan = { backZ = backZ, lake = Vector3.new(lake.X, Winter.BASE_Y, lake.Z) }
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

function Winter.ground(ctx: any, fm: FeatureMap.Map)
	local p = Winter.plan(ctx)
	local rng = Random.new(Config.SEED + 55)
	local base = Winter.BASE_Y
	-- mountains: blocks along the back (-Z) edge of every winter rectangle, deeper and taller
	-- toward the back; each is a stack of snow-capped tiers
	for _, r in Layout.rectsOf("Winter") do
		local half = (r.cf.Rotation * r.size):Abs() / 2
		local back = r.cf.Z - half.Z
		local x = r.cf.X - half.X - 60
		while x < r.cf.X + half.X + 60 do
			local w = rng:NextNumber(140, 320)
			local depth = Winter.MOUNTAIN_DEPTH * rng:NextNumber(0.4, 1)
			local z0, z1 = back - 240, back + depth
			local height = Winter.MOUNTAIN_HEIGHT * rng:NextNumber(0.42, 1) * (0.6 + 0.4 * depth / Winter.MOUNTAIN_DEPTH)
			GroundBuilder.rockTiers(fm, x + w / 2, (z0 + z1) / 2, 0, Vector2.new(w / 2 + 30, (z1 - z0) / 2), {
				base = base,
				top = base + height,
				key = rng:NextNumber() < 0.75 and "Snow" or "WinterRock",
				tierHeight = Winter.MOUNTAIN_TIER_H,
				inset = 0.1,
				buttresses = 3,
				layer = 2,
				rng = rng,
			})
			x += w * rng:NextNumber(0.65, 0.95)
		end
	end
	-- low snow ledges and rock outcrops on the open field (kept off the lake)
	local function field(): (number?, number?)
		for _ = 1, 50 do
			local rects = Layout.rectsOf("Winter")
			local r = rects[rng:NextInteger(1, #rects)]
			local half = (r.cf.Rotation * r.size):Abs() / 2
			local x = r.cf.X + rng:NextNumber(-0.85, 0.85) * half.X
			local z = r.cf.Z + half.Z - rng:NextNumber(0.05, 0.55) * 2 * half.Z
			if Layout.regionAt(x, z) == "Winter" and Vector2.new(x - p.lake.X, z - p.lake.Z).Magnitude > Winter.LAKE_RADIUS * 1.6 then
				return x, z
			end
		end
		return nil, nil
	end
	for _ = 1, Winter.LEDGE_COUNT do
		local x, z = field()
		if x and z then
			GroundBuilder.terrace(fm, x, z, rng:NextNumber(50, 150), rng:NextNumber(40, 120), base, rng:NextNumber(2.5, 4), rng:NextInteger(1, 2), rng:NextNumber() < 0.5 and "Snow" or "SnowShade", rng, 1)
		end
	end
	for _ = 1, Winter.OUTCROP_COUNT do
		local x, z = field()
		if x and z then
			GroundBuilder.rockTiers(fm, x, z, 0, Vector2.new(rng:NextNumber(16, 40), rng:NextNumber(16, 40)), { base = base, top = base + rng:NextNumber(12, 40), key = "Snow", tierHeight = 8, inset = 0.2, buttresses = 2, layer = 2, rng = rng })
		end
	end
	-- snow hills on the open field (off the lake)
	highlands(fm, "Winter", Winter.HIGHLAND_COUNT, base, 80, 180, 20, 46, { "Snow", "SnowShade" }, rng, { { c = p.lake, r = Winter.LAKE_RADIUS * 1.8 } })
	-- frozen lake: one flat ice sheet, a step below the snow (two overlapping blocks, not a circle)
	local L = Winter.LAKE_RADIUS
	fm:box("set", 4, p.lake.X - L, p.lake.X + L * 0.8, p.lake.Z - L * 0.6, p.lake.Z + L * 0.7, base - 1.5, "Ice")
	fm:box("set", 4, p.lake.X - L * 0.6, p.lake.X + L * 0.5, p.lake.Z - L * 0.95, p.lake.Z + L, base - 1.5, "Ice")
end

-- Shaded snow drifts, sampled per 64-stud block.
function Winter.patch(ctx: any, x: number, z: number, top: number, key: string): string
	if key == "Snow" and math.noise(math.floor(x / 64) * 0.47, math.floor(z / 64) * 0.47, 8.8) > 0.45 then
		return "SnowShade"
	end
	return key
end

-- ─── populate ─────────────────────────────────────────────────────────────────
-- Barren on purpose (the brief): an open fighting ground. Destructible ruined walls (the
-- DestructibleWall convention the destruction system expects: a Model tagged
-- "DestructibleWall", Width/Height attributes, a grid of "Chunk" parts with Col/Row) and
-- breakable supply crates (tag "Destructible"), plus sparse audited rock and drift props.

Winter.WALLS = 40
Winter.CRATES = 110
Winter.SCENERY = 160
local SCENERY = { "SnowDrift1", "SnowDrift2", "WindRock1", "WindRock2", "WindRock3", "RockPinnacle1", "RockPinnacle2" }

function Winter.populate(ctx: any, folder: Folder)
	local CollectionService = game:GetService("CollectionService")
	local Kit = require(script.Parent.Parent.Kit) :: any
	local PlacementUtil = require(script.Parent.Parent.PlacementUtil) :: any
	local PartKit = require(script.Parent.Parent.PartKit) :: any
	local AssetIds = require(script.Parent.Parent.Data.AssetIds) :: any
	local data = Layout.dataFolder()
	local p = Winter.plan(ctx)
	local rng = Random.new(Config.SEED + 56)
	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
		return f
	end
	local fWalls, fCrates, fScenery = sub("DestructibleWalls"), sub("Crates"), sub("Scenery")
	local spacing = PlacementUtil.spacing()
	local rects = Layout.rectsOf("Winter")
	-- a free, flat spot on the open field (off the lake, in front of the mountains)
	local function fieldSpot(r: number): Vector3?
		for _ = 1, 30 do
			local rect = rects[rng:NextInteger(1, #rects)]
			local half = (rect.cf.Rotation * rect.size):Abs() / 2
			local x = rect.cf.X + rng:NextNumber(-0.9, 0.9) * half.X
			local z = rect.cf.Z + half.Z - rng:NextNumber(0.03, 0.5) * 2 * half.Z
			if Layout.regionAt(x, z) == "Winter" and Vector2.new(x - p.lake.X, z - p.lake.Z).Magnitude > Winter.LAKE_RADIUS * 1.2 and PlacementUtil.isFree(spacing, x, z, r) then
				local lo, hi = math.huge, -math.huge
				for _, o in { Vector2.zero, Vector2.new(r, 0), Vector2.new(-r, 0), Vector2.new(0, r), Vector2.new(0, -r) } do
					local g = PlacementUtil.ground(x + o.X, z + o.Y)
					if not g then
						lo = math.huge
						break
					end
					lo, hi = math.min(lo, g.position.Y), math.max(hi, g.position.Y)
				end
				if lo < math.huge and hi - lo <= 0.5 then
					PlacementUtil.reserve(spacing, x, z, r)
					return Vector3.new(x, hi, z)
				end
			end
		end
		return nil
	end

	-- ── destructible ruined walls: 3 x 3 chunks, edge to edge ──
	data:SetAttribute("Progress", "winter: walls")
	local stone = { Color3.fromRGB(118, 116, 112), Color3.fromRGB(98, 96, 94), Color3.fromRGB(134, 128, 120) }
	for _ = 1, Winter.WALLS do
		local width, height, thick = rng:NextNumber(14, 28), rng:NextNumber(9, 14), 2.6
		local at = fieldSpot(width / 2 + 2)
		if at then
			local m = Instance.new("Model")
			m.Name = "DestructibleWall"
			m:SetAttribute("Width", width)
			m:SetAttribute("Height", height)
			-- a little yaw keeps every wall off the ground columns' axes
			local cf = CFrame.new(at.X, at.Y - 0.25, at.Z) * CFrame.Angles(0, rng:NextNumber(0.1, math.pi - 0.1), 0)
			local color = stone[rng:NextInteger(1, #stone)]
			for col = 1, 3 do
				for row = 1, 3 do
					local cw, ch = width / 3, height / 3
					-- broken top: the top row loses a random chunk or two
					if not (row == 3 and rng:NextNumber() < 0.35) then
						local chunk = PartKit.part(m, cf, CFrame.new((col - 2) * cw, (row - 0.5) * ch, 0), Vector3.new(cw, ch, thick), Enum.Material.Slate, color, "Chunk")
						chunk:SetAttribute("Col", col)
						chunk:SetAttribute("Row", row)
					end
				end
			end
			CollectionService:AddTag(m, "DestructibleWall")
			m.Parent = fWalls
		end
	end

	-- ── breakable supply crates (part-built, so the destruction system can shatter them) ──
	data:SetAttribute("Progress", "winter: crates")
	for i = 1, Winter.CRATES do
		local s = rng:NextNumber(3, 5)
		local at = fieldSpot(s)
		if at then
			local crate = PartKit.part(fCrates, CFrame.new(at.X, at.Y - 0.25 + s / 2, at.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), CFrame.new(), Vector3.new(s, s, s), Enum.Material.WoodPlanks, Color3.fromRGB(110 + rng:NextInteger(-12, 12), 88, 66), "SupplyCrate")
			CollectionService:AddTag(crate, "Destructible")
		end
		if i % 40 == 0 then
			task.wait()
		end
	end

	-- ── sparse scenery: drifts, wind-carved rocks, pinnacles ──
	data:SetAttribute("Progress", "winter: scenery")
	local scenery = {}
	for _, n in SCENERY do
		if AssetIds[n] then
			table.insert(scenery, n)
		end
	end
	Kit.preload(scenery)
	for i = 1, Winter.SCENERY do
		local rect = rects[rng:NextInteger(1, #rects)]
		local half = (rect.cf.Rotation * rect.size):Abs() / 2
		local x = rect.cf.X + rng:NextNumber(-0.95, 0.95) * half.X
		local z = rect.cf.Z + rng:NextNumber(-0.95, 0.95) * half.Z
		if Layout.regionAt(x, z) == "Winter" and Vector2.new(x - p.lake.X, z - p.lake.Z).Magnitude > Winter.LAKE_RADIUS * 1.1 then
			local prop = Kit.clone(scenery[rng:NextInteger(1, #scenery)])
			Kit.vary(prop, rng, 0.2)
			local _, size = prop:GetBoundingBox()
			if not PlacementUtil.scatterOne(spacing, prop, x, z, math.max(size.X, size.Z) / 2 + 1, { yaw = rng:NextNumber(0, 2 * math.pi), embed = 0.4, maxStep = 0.5, parent = fScenery }) then
				prop:Destroy()
			end
		end
		if i % 40 == 0 then
			task.wait()
		end
	end
	data:SetAttribute("Progress", "winter: done")
	print(string.format("[MapGen] Winter: %d destructible walls, %d crates, %d scenery", #fWalls:GetChildren(), #fCrates:GetChildren(), #fScenery:GetChildren()))
end

function Winter.reset()
	plan = nil
end

return Winter
