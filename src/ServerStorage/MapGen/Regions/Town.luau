--!strict
--[[
	Regions.Town - Patchwork Town: a giant patchwork dome sunk in a crater, packed with a
	scrap-built district that climbs a central hill to an old hall.

	References: a dome of mismatched panels in a sandy crater with a dark oculus,
	claude.jpg (dense dark-roofed houses climbing to a hilltop hall, giant vents in the wall),
	bro.jpg (graffiti, corrugated rooftops, clutter).

	Layout (all derived from the Town rectangle so it follows MAP_SCALE):
	  crater floor (FLOOR_DROP below the plains) -> rim of stacked ledges with four gate
	  stairways -> dome on the floor -> ring roads + radial avenues -> building lots between them
	  -> a stepped hill of nested rectangular terraces (the reference village's ledges) with stairs
	  where the lanes cross a ledge -> hilltop plaza with the hall.

	Ground: flat features only (MapGen.FeatureMap / GroundBuilder): no slopes, no rolling hills.
	Lots read their height from the same features, so a building always matches the terrace it
	stands on; a lot that straddles a ledge gets a stone plinth up to its highest corner.
]]

local Config = require(script.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.Layout)
local FeatureMap = require(script.Parent.Parent.FeatureMap)
local GroundBuilder = require(script.Parent.Parent.GroundBuilder)

local Town = {}
Town.NAME = "Town"

-- ─── constants ───────────────────────────────────────────────────────────────
local S = Config.GROUND.SURFACE_Y
local H = Config.HUMAN
Town.BASE_Y = S -- plains around the crater
Town.BASE_KEY = "TownDust"
Town.ROCK_KEY = "TownRock"
Town.DOME_RADIUS = 820 -- the central town: ~7x the greybox dome (115 -> 230 at map scale 2)
Town.DOME_HEIGHT = 430 -- squat dome like the reference (height/radius ~ 0.52)
Town.DOME_OFFSET = Vector2.new(0, 0) -- centred in the Town rect; the faction bases take two corners
Town.FLOOR_DROP = 22 -- crater floor below the surrounding plains
Town.RIM_HEIGHT = 40
Town.RIM_LEDGES = 4 -- outer face of the rim: ledges stepping up to the crest
Town.RIM_INNER = Town.DOME_RADIUS + 50
Town.RIM_TOP = Town.DOME_RADIUS + 140
Town.RIM_OUTER = Town.DOME_RADIUS + 240
Town.GATE_ANGLES = { 0, 90, 180, 270 } -- degrees, 0 = +X (axis-aligned, so stair corridors follow the ground grid)
Town.GATE_WIDTH = 70
Town.GATE_STAIR_START = Town.RIM_INNER + 10 -- radius where the gate stairway leaves the crater floor
Town.GATE_TREAD = 8 -- studs per step on the gate stairways (riser <= 1 stud)
Town.HILL_OFFSET = Vector2.new(-90, -150) -- hill centre from dome centre
Town.HILL_RADIUS = 300
Town.HILL_TIERS = 12
Town.HILL_TIER_H = 6 -- one terrace ledge; HILL_HEIGHT = tiers x ledge
Town.HILL_HEIGHT = Town.HILL_TIERS * Town.HILL_TIER_H
Town.PLAZA_RADIUS = 72 -- hilltop plaza
Town.RINGS = { 400, 600 } -- ring road radii (centre lines)
Town.LANE_COUNT = 16 -- radial lanes (4 of them are the gate avenues)
Town.LOT_WIDTHS = { 26, 30, 34, 38, 44, 50 } -- frontage options (bigger houses, fewer of them)
Town.LOT_DEPTHS = { 28, 32, 36 }
Town.ROW_DEPTH = 38
Town.HIGHLANDS = 10 -- stepped hills on the plains around the crater
Town.BASE_HALF = { Menders = Vector2.new(250, 200), Scrappers = Vector2.new(250, 210) } -- faction yards
Town.CANAL_WIDTH = 34
Town.STAIR_TREAD = 2 -- studs of run per stud of rise on hill stairs

export type Lot = { cf: CFrame, w: number, d: number, y: number, base: number, facing: string, band: number, hill: boolean }
export type Plan = {
	center: Vector3,
	hill: Vector3,
	floorY: number,
	lots: { Lot },
	plazas: { { c: Vector3, r: number, kind: string } },
	canal: { Vector3 },
	npcSpots: { CFrame },
	gateAngles: { number },
	laneAngles: { { a: number, w: number, minR: number } },
	ground: FeatureMap.Map, -- the town's own features, for lot heights
	gateStairEnd: number,
	-- faction yards in two opposite corners of the Town rect (front = -Z of cf, facing town)
	baseSites: { [string]: { cf: CFrame, half: Vector2 } },
}

local plan: Plan? = nil

-- ─── geometry helpers ─────────────────────────────────────────────────────────

local function angDiff(a: number, b: number): number
	local d = (a - b + math.pi) % (2 * math.pi) - math.pi
	return math.abs(d)
end

local function segDist(px: number, pz: number, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(px - a.X, pz - a.Z)
	local t = math.clamp(ap:Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (ap - ab * t).Magnitude
end

local function polyDist(px: number, pz: number, pts: { Vector3 }): number
	local best = math.huge
	for i = 1, #pts - 1 do
		best = math.min(best, segDist(px, pz, pts[i], pts[i + 1]))
	end
	return best
end

-- ─── ground features ──────────────────────────────────────────────────────────
-- Registered twice with the same seed: into the plan's private map (lot heights) and into the
-- global map (GroundBuilder). Layers: 1 rim ledges, 2 crater cuts, 3 hill terraces, 4 corridors.

local function townFeatures(p: Plan, fm: FeatureMap.Map)
	local rng = Random.new(Config.SEED + 12)
	local c = p.center
	-- rim: ledges climbing from the plains to the crest (irregular, not compass-drawn)
	local crest = S + Town.RIM_HEIGHT
	for i = 1, Town.RIM_LEDGES do
		local r = Town.RIM_OUTER - (Town.RIM_OUTER - Town.RIM_TOP) * (i - 1) / Town.RIM_LEDGES
		fm:disc("raise", 1, c.X, c.Z, r, S + (crest - S) * i / Town.RIM_LEDGES, "TownDust", 0.08, 10 + i)
	end
	-- broken rock stacks along the crest so the rim reads as piled blocks, not drawn rings
	for _ = 1, 44 do
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = rng:NextNumber(Town.RIM_TOP - 10, Town.RIM_OUTER - 40)
		GroundBuilder.rockTiers(fm, c.X + math.cos(a) * r, c.Z + math.sin(a) * r, 0, Vector2.new(rng:NextNumber(18, 60), rng:NextNumber(18, 60)), {
			base = S,
			top = crest + rng:NextNumber(4, 30),
			key = "TownRock",
			tierHeight = 8,
			inset = 0.2,
			buttresses = 2,
			layer = 1,
			rng = rng,
		})
	end
	-- inner face: two broken ledges down to the crater floor
	fm:disc("carve", 2, c.X, c.Z, Town.RIM_TOP - 30, S + 20, "TownRock", 0.06, 21)
	fm:disc("carve", 2, c.X, c.Z, Town.RIM_TOP - 75, S + 4, "TownRock", 0.05, 22)
	fm:disc("carve", 2, c.X, c.Z, Town.RIM_INNER, p.floorY, "TownFloor", 0.02, 23)
	-- hill: nested rectangles, each side jittered, each tier inside the one below
	local h = p.hill
	local x0, x1, z0, z1 = h.X - Town.HILL_RADIUS, h.X + Town.HILL_RADIUS, h.Z - Town.HILL_RADIUS, h.Z + Town.HILL_RADIUS
	for i = 1, Town.HILL_TIERS do
		local t = (i - 1) / (Town.HILL_TIERS - 1)
		local r = Town.HILL_RADIUS + (Town.PLAZA_RADIUS + 6 - Town.HILL_RADIUS) * t
		local j = r * 0.2
		x0 = math.max(x0 + (i > 1 and 6 or 0), h.X - r + rng:NextNumber(-j, j))
		x1 = math.min(x1 - (i > 1 and 6 or 0), h.X + r + rng:NextNumber(-j, j))
		z0 = math.max(z0 + (i > 1 and 6 or 0), h.Z - r + rng:NextNumber(-j, j))
		z1 = math.min(z1 - (i > 1 and 6 or 0), h.Z + r + rng:NextNumber(-j, j))
		local top = p.floorY + Town.HILL_TIER_H * i
		local key = i == Town.HILL_TIERS and "Cobble" or "TownFloor"
		fm:box("raise", 3, x0, x1, z0, z1, top, key)
		if i < Town.HILL_TIERS - 1 then
			-- a terrace spur reaching out of one side, so the hill is not a centred ziggurat
			local w, d = x1 - x0, z1 - z0
			local sw, sd = w * rng:NextNumber(0.25, 0.45), d * rng:NextNumber(0.25, 0.45)
			local sx = rng:NextNumber() < 0.5 and x0 or x1
			local sz = rng:NextNumber(z0 + sd / 2, z1 - sd / 2)
			fm:box("raise", 3, sx - sw / 2, sx + sw / 2, sz - sd / 2, sz + sd / 2, top, key)
		end
	end
	-- gate corridors: crater floor up to the stairway, stairway footprint at floor level (the
	-- steps are separate parts), then a cut at plains level through the outer ledges
	for _, g in p.gateAngles do
		local dir = Vector3.new(math.cos(g), 0, math.sin(g))
		local yaw = math.atan2(-dir.Z, dir.X)
		local function corridor(r0: number, r1: number, top: number, key: string)
			local mid = c + dir * ((r0 + r1) / 2)
			fm:rect("set", 4, mid.X, mid.Z, (r1 - r0) / 2, Town.GATE_WIDTH / 2, top, key, yaw)
		end
		corridor(Town.RIM_INNER - 40, p.gateStairEnd, p.floorY, "Cobble")
		corridor(p.gateStairEnd, Town.RIM_OUTER + 30, S, "Cobble")
	end
	-- polluted canal: a bank cut and a deep channel with sludge water
	for i = 1, #p.canal - 1 do
		fm:segment("carve", 3, p.canal[i], p.canal[i + 1], Town.CANAL_WIDTH / 2 + 12, S - 2.5, "CanalMud")
	end
	for i = 1, #p.canal - 1 do
		fm:segment("carve", 3, p.canal[i], p.canal[i + 1], Town.CANAL_WIDTH / 2, S - 9, "CanalMud", S - 3.75)
	end
	-- plains: stepped highlands (the reference's hills: flat ledges, never slopes) between the
	-- crater, the canal and the faction yards
	local rect = Layout.rectsOf("Town")[1]
	local half = (rect.cf.Rotation * rect.size):Abs() / 2
	local placed = 0
	for _ = 1, 300 do
		if placed >= Town.HIGHLANDS then
			break
		end
		local x = rect.cf.X + rng:NextNumber(-1, 1) * (half.X - 60)
		local z = rect.cf.Z + rng:NextNumber(-1, 1) * (half.Z - 60)
		local hx, hz = rng:NextNumber(70, 190), rng:NextNumber(70, 190)
		local reach = math.max(hx, hz)
		local clear = Vector2.new(x - c.X, z - c.Z).Magnitude > Town.RIM_OUTER + 40 + reach
			and polyDist(x, z, p.canal) > reach + 60
		for _, site in p.baseSites do
			if math.abs(x - site.cf.X) < site.half.X + hx + 40 and math.abs(z - site.cf.Z) < site.half.Y + hz + 40 then
				clear = false
			end
		end
		if clear then
			GroundBuilder.highland(fm, x, z, hx, hz, S, rng:NextNumber(18, 48), rng:NextNumber(4, 5.5), rng:NextNumber() < 0.6 and "TownDust" or "TownRock", rng, 1)
			placed += 1
		end
	end
end

-- Height of the town's own ground (crater, hill, rim) at (x, z).
local function groundAt(p: Plan, x: number, z: number): number
	local top = p.ground:query(x, z, S, "TownDust")
	return top
end

-- ─── plan ─────────────────────────────────────────────────────────────────────

function Town.plan(ctx: any): Plan
	if plan then
		return plan
	end
	local rect = Layout.rectsOf("Town")[1]
	local c = Vector3.new(rect.cf.X + Town.DOME_OFFSET.X, S - Town.FLOOR_DROP, rect.cf.Z + Town.DOME_OFFSET.Y)
	local p: Plan = {
		center = c,
		hill = Vector3.new(c.X + Town.HILL_OFFSET.X, c.Y, c.Z + Town.HILL_OFFSET.Y),
		floorY = c.Y,
		lots = {},
		plazas = {},
		canal = {},
		npcSpots = {},
		gateAngles = {},
		laneAngles = {},
		ground = FeatureMap.new(),
		-- one step per stud of rise between the crater floor and the plains
		gateStairEnd = Town.GATE_STAIR_START + (S - c.Y) * Town.GATE_TREAD,
		baseSites = {},
	}
	for _, a in Town.GATE_ANGLES do
		table.insert(p.gateAngles, math.rad(a))
	end
	local rng = Random.new(Config.SEED + 11)

	-- polluted outflow canal: from outside the west gate across the plains to the town edge
	local west = math.rad(180)
	local start = Vector3.new(c.X + math.cos(west) * (Town.RIM_OUTER + 40), S, c.Z + math.sin(west) * (Town.RIM_OUTER + 40) + 90)
	local half = (rect.cf.Rotation * rect.size):Abs() / 2
	local edgeX = rect.cf.X - half.X - 120
	local steps = 8
	for i = 0, steps do
		local t = i / steps
		local x = start.X + (edgeX - start.X) * t
		local z = start.Z + math.sin(t * math.pi * 1.5) * 120 + t * 160
		table.insert(p.canal, Vector3.new(x, S, z))
	end

	-- faction yards: Menders in the -X/+Z corner (where the greybox's yellow block stood),
	-- Scrappers in the opposite +X/-Z corner; both axis-aligned, fronts toward the dome
	local rh = (rect.cf.Rotation * rect.size):Abs() / 2
	for name, sign in { Menders = Vector2.new(-1, 1), Scrappers = Vector2.new(1, -1) } do
		local bh = Town.BASE_HALF[name]
		local pos = Vector3.new(rect.cf.X + sign.X * (rh.X - bh.X - 40), S, rect.cf.Z + sign.Y * (rh.Z - bh.Y - 40))
		-- local -Z faces the town: toward -Z world for the +Z corner, +Z world for the -Z corner
		local look = Vector3.new(0, 0, -sign.Y)
		p.baseSites[name] = { cf = CFrame.lookAt(pos, pos + look), half = bh }
	end

	-- the ground lots will stand on
	townFeatures(p, p.ground)
	p.ground:finalize()

	-- radial lanes: 4 gate avenues run to the hill; the minor lanes start at the first ring road
	-- (otherwise they converge at the centre and leave no room for the inner rows)
	local laneAngles: { { a: number, w: number, minR: number } } = {}
	for i = 0, Town.LANE_COUNT - 1 do
		local a = i / Town.LANE_COUNT * 2 * math.pi
		local isGate = false
		for _, g in p.gateAngles do
			if angDiff(a, g) < 0.01 then
				isGate = true
			end
		end
		table.insert(laneAngles, { a = a, w = isGate and H.STREET_W or H.LANE_W, minR = isGate and 0 or Town.RINGS[1] - H.STREET_W / 2 })
	end
	p.laneAngles = laneAngles

	-- plazas: one market square inside each gate, hilltop plaza
	for _, g in p.gateAngles do
		local r = Town.DOME_RADIUS - 95
		table.insert(p.plazas, { c = Vector3.new(c.X + math.cos(g) * r, c.Y, c.Z + math.sin(g) * r), r = 62, kind = "Market" })
	end
	table.insert(p.plazas, { c = p.hill + Vector3.new(0, Town.HILL_HEIGHT, 0), r = Town.PLAZA_RADIUS, kind = "Hilltop" })

	local function inPlaza(x: number, z: number, pad: number): boolean
		for _, pl in p.plazas do
			if Vector2.new(x - pl.c.X, z - pl.c.Z).Magnitude < pl.r + pad then
				return true
			end
		end
		return false
	end
	local function onLane(x: number, z: number, halfW: number): boolean
		local a = math.atan2(z - c.Z, x - c.X)
		local r = Vector2.new(x - c.X, z - c.Z).Magnitude
		for _, l in laneAngles do
			if r + halfW >= l.minR and angDiff(a, l.a) * r < l.w / 2 + halfW then
				return true
			end
		end
		return false
	end

	-- lot overlap guard: oriented rectangles in a coarse hash, separating-axis test
	local lotGrid: { [number]: { { cf: CFrame, hx: number, hz: number } } } = {}
	local LOT_CELL = 96
	local function cells(cf: CFrame, hx: number, hz: number): { number }
		local r = math.sqrt(hx * hx + hz * hz)
		local out = {}
		for gx = math.floor((cf.X - r) / LOT_CELL), math.floor((cf.X + r) / LOT_CELL) do
			for gz = math.floor((cf.Z - r) / LOT_CELL), math.floor((cf.Z + r) / LOT_CELL) do
				table.insert(out, gx * 100000 + gz)
			end
		end
		return out
	end
	local function obbOverlap(a: CFrame, ahx: number, ahz: number, b: CFrame, bhx: number, bhz: number): boolean
		local d = b.Position - a.Position
		for _, axis in { a.RightVector, a.LookVector, b.RightVector, b.LookVector } do
			local ra = math.abs(a.RightVector:Dot(axis)) * ahx + math.abs(a.LookVector:Dot(axis)) * ahz
			local rb = math.abs(b.RightVector:Dot(axis)) * bhx + math.abs(b.LookVector:Dot(axis)) * bhz
			if math.abs(d:Dot(axis)) > ra + rb then
				return false
			end
		end
		return true
	end
	local function lotsClear(cf: CFrame, hx: number, hz: number): boolean
		for _, k in cells(cf, hx, hz) do
			for _, o in lotGrid[k] or {} do
				if obbOverlap(cf, hx, hz, o.cf, o.hx, o.hz) then
					return false
				end
			end
		end
		return true
	end
	local function addLot(cf: CFrame, hx: number, hz: number)
		for _, k in cells(cf, hx, hz) do
			lotGrid[k] = lotGrid[k] or {}
			table.insert(lotGrid[k], { cf = cf, hx = hx, hz = hz })
		end
	end

	-- bands between streets; each band holds an inner row (faces the inner street) and an
	-- outer row (faces the outer street) with an alley between when deep enough.
	local hillEdge = Town.PLAZA_RADIUS + 10
	local bands = {
		{ r0 = hillEdge, r1 = Town.RINGS[1] - H.STREET_W / 2 },
		{ r0 = Town.RINGS[1] + H.STREET_W / 2, r1 = Town.RINGS[2] - H.STREET_W / 2 },
		{ r0 = Town.RINGS[2] + H.STREET_W / 2, r1 = Town.DOME_RADIUS - 40 },
	}
	-- the hill is offset, so ring distances are measured from the dome centre; lots near the
	-- hilltop plaza are skipped by inPlaza.
	for bi, band in bands do
		-- pack rows across the band: pairs of back-to-back rows, an alley between pairs.
		-- The first row of a pair faces inward (onto the street/alley on its inner side), the
		-- second faces outward, so every building front opens onto a walkable way.
		local rows: { { r: number, depth: number, facingIn: boolean } } = {}
		local cursor = band.r0
		local rowDepth = Town.ROW_DEPTH
		local inPair = 0
		while cursor + rowDepth <= band.r1 + 2 do
			table.insert(rows, { r = cursor + rowDepth / 2, depth = rowDepth, facingIn = inPair == 0 })
			cursor += rowDepth
			if inPair == 0 then
				inPair = 1
			else
				inPair = 0
				cursor += H.ALLEY_W + rng:NextNumber(0, 4)
			end
		end
		for _, row in rows do
			-- step along the row's INNER edge: neighbouring rectangles are tangent to the ring,
			-- so spacing them on the centre line would make their inner corners collide
			local rIn = row.r - row.depth / 2
			local circumference = 2 * math.pi * rIn
			local s = rng:NextNumber(0, 20)
			while s < circumference do
				local w = Town.LOT_WIDTHS[rng:NextInteger(1, #Town.LOT_WIDTHS)]
				local a = (s + w / 2) / rIn
				local x, z = c.X + math.cos(a) * row.r, c.Z + math.sin(a) * row.r
				local depth = math.min(row.depth - 2, Town.LOT_DEPTHS[rng:NextInteger(1, #Town.LOT_DEPTHS)])
				if not onLane(x, z, w / 2 + 2) and not inPlaza(x, z, math.max(w, depth) / 2 + 6) and rng:NextNumber() > 0.06 then
					-- face the street: inner rows look toward the centre, outer rows outward
					local look = row.facingIn and Vector3.new(c.X - x, 0, c.Z - z).Unit or Vector3.new(x - c.X, 0, z - c.Z).Unit
					local flat = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(x, 0, z) + look)
					local lw, ld = w - 2, depth - 2
					-- terrace height under the footprint: centre + corners
					local hi, lo = -math.huge, math.huge
					for _, o in { Vector3.zero, Vector3.new(-lw / 2, 0, -ld / 2), Vector3.new(lw / 2, 0, -ld / 2), Vector3.new(-lw / 2, 0, ld / 2), Vector3.new(lw / 2, 0, ld / 2) } do
						local wp = flat:PointToWorldSpace(o)
						local gy = groundAt(p, wp.X, wp.Z)
						hi, lo = math.max(hi, gy), math.min(lo, gy)
					end
					-- straddling more than one ledge would need a plinth taller than a storey: skip;
					-- and never overlap a lot already placed (another row, band or the hill)
					if hi - lo <= Town.HILL_TIER_H + 0.5 and lotsClear(flat, lw / 2 + 1.5, ld / 2 + 1.5) then
						local cf = CFrame.lookAt(Vector3.new(x, hi, z), Vector3.new(x, hi, z) + look)
						local lot = { cf = cf, w = lw, d = ld, y = hi, base = lo, facing = row.facingIn and "in" or "out", band = bi, hill = hi > p.floorY + 0.25 }
						table.insert(p.lots, lot)
						addLot(flat, lw / 2 + 1.5, ld / 2 + 1.5)
					end
				end
				s += w + rng:NextNumber(1, 4)
			end
		end
	end

	-- NPC crowd spots: along avenues and around market squares
	for _, l in laneAngles do
		if l.w >= H.STREET_W then
			for r = 140, Town.DOME_RADIUS - 60, 36 do
				local x, z = c.X + math.cos(l.a) * r, c.Z + math.sin(l.a) * r
				table.insert(p.npcSpots, CFrame.new(x, groundAt(p, x, z), z))
			end
		end
	end
	for _, pl in p.plazas do
		for i = 0, 5 do
			local a = i / 6 * 2 * math.pi
			table.insert(p.npcSpots, CFrame.new(pl.c.X + math.cos(a) * pl.r * 0.6, pl.c.Y, pl.c.Z + math.sin(a) * pl.r * 0.6))
		end
	end
	plan = p
	return p
end

-- ─── ground interface (GroundBuilder) ─────────────────────────────────────────

function Town.ground(ctx: any, fm: FeatureMap.Map)
	townFeatures(Town.plan(ctx), fm)
end

-- Re-key the cap by location: paved rings, cobbled avenues, blocky dirt/cobble patches. Patch
-- noise is sampled per 48-stud block so patches are rectangles, like the reference's paths.
function Town.patch(ctx: any, x: number, z: number, top: number, key: string): string
	local p = Town.plan(ctx)
	local c = p.center
	local dx, dz = x - c.X, z - c.Z
	local r = math.sqrt(dx * dx + dz * dz)
	if r < Town.DOME_RADIUS and key == "TownFloor" then
		local a = math.atan2(dz, dx)
		for _, ring in Town.RINGS do
			if math.abs(r - ring) < H.STREET_W / 2 then
				return "Pavement"
			end
		end
		for _, l in p.laneAngles do
			if r >= l.minR and angDiff(a, l.a) * r < l.w / 2 then
				return l.w >= H.STREET_W and "Cobble" or "Pavement"
			end
		end
		for _, pl in p.plazas do
			if Vector2.new(x - pl.c.X, z - pl.c.Z).Magnitude < pl.r then
				return "Cobble"
			end
		end
		return math.noise(math.floor(x / 48) * 0.61, math.floor(z / 48) * 0.61, 4.4) > 0.3 and "Cobble" or key
	end
	if key == "TownDust" then
		return math.noise(math.floor(x / 64) * 0.53, math.floor(z / 64) * 0.53, 9.1) > 0.4 and "TownFloor" or key
	end
	return key
end

-- Parts that belong to the ground but are not columns: the gate stairways and the stairs where
-- lanes cross a hill ledge. They go in Workspace.Ground so placement rays treat them as ground.
function Town.groundParts(ctx: any, parent: Instance)
	local p = Town.plan(ctx)
	local c = p.center
	local surfaces = GroundBuilder.SURFACES
	local folder = Instance.new("Folder")
	folder.Name = "TownStairs"
	local steps = 0
	-- gate stairways: crater floor -> plains, risers of one stud
	for _, g in p.gateAngles do
		local dir = Vector3.new(math.cos(g), 0, math.sin(g))
		local foot = c + dir * Town.GATE_STAIR_START
		local s = surfaces.Cobble
		local foot3 = Vector3.new(foot.X, p.floorY, foot.Z)
		local width = Town.GATE_WIDTH - 2 * GroundBuilder.CELL
		local run, landTo = GroundBuilder.fitRun(ctx, foot3, dir, p.gateStairEnd - Town.GATE_STAIR_START, S - p.floorY, width)
		steps += GroundBuilder.stairs(folder, foot3, dir, run, S - p.floorY, width, s.material, s.color, landTo)
	end
	-- hill stairs: walk each lane outward; at every ledge, a flight on the low side
	local s = surfaces.Pavement
	for _, l in p.laneAngles do
		local dir = Vector3.new(math.cos(l.a), 0, math.sin(l.a))
		local r0 = math.max(l.minR, 4)
		-- heights as built (cell-snapped), so every flight matches the ledge it climbs
		local function built(x: number, z: number): number
			return GroundBuilder.builtTop(ctx, x, z)
		end
		local prev = built(c.X + dir.X * r0, c.Z + dir.Z * r0)
		local r = r0
		while r < Town.DOME_RADIUS - 10 do
			r += 2
			local pos = c + dir * r
			local h = built(pos.X, pos.Z)
			if h ~= prev then
				local rise = math.abs(h - prev)
				local run = rise * Town.STAIR_TREAD
				local up = h > prev and dir or -dir -- climb toward the higher side
				local edge = c + dir * (r - 1)
				local foot = edge - up * run
				-- the flight needs flat ground on the low side
				local low = math.min(h, prev)
				local flatOk = rise <= 12
				for t = 0, run, 2 do
					local q = foot + up * t
					if built(q.X, q.Z) ~= low then
						flatOk = false
						break
					end
				end
				if flatOk then
					local foot3 = Vector3.new(foot.X, low, foot.Z)
					local fitted, landTo, fits = GroundBuilder.fitRun(ctx, foot3, up, run, rise, l.w - 2, GroundBuilder.CELL)
					if fits then
						steps += GroundBuilder.stairs(folder, foot3, up, fitted, rise, l.w - 2, s.material, s.color, landTo)
					end
				end
				prev = h
			end
		end
	end
	folder.Parent = parent
	print(string.format("[MapGen] Town stairs: %d steps", steps))
end

-- ─── populate ─────────────────────────────────────────────────────────────────
-- Structures are PartKit builds (parts, no meshes): the kit meshes Z-fight internally and
-- cannot be re-uploaded right now. Only kit props that passed the mesh Z-fighting audit
-- (tools/zfight/mesh_report.md, "No qualifying pairs") are used as meshes.

local SMALL_PROPS = { "BarrelRusty", "SackPile", "TrashBags", "Bucket", "Handcart", "TableChairs", "WashingMachine", "TyreStack1", "ScrapPanelPile", "ShoppingCart" }
local CLOTHS = { Color3.fromRGB(150, 52, 44), Color3.fromRGB(214, 168, 52), Color3.fromRGB(64, 92, 122), Color3.fromRGB(82, 110, 70), Color3.fromRGB(176, 160, 128), Color3.fromRGB(120, 70, 110) }
local SHOP_SIGNS = { "SCRAP", "NOODLES", "TOOLS", "WATER", "PARTS", "CLOTH", "LAMPS", "TEA", "BREAD", "FIX-IT", "JUNK", "RAGS", "OIL", "SOUP", "BOOKS", "PIPES", "RICE", "GEARS", "SHOES", "MAPS" }
-- band 1 (hill) is old timber and plaster, band 3 (outer ring) is the scrap fringe
local STYLE_BY_BAND = { { "timber", "plaster", "plaster", "brick" }, { "plaster", "brick", "timber", "scrap" }, { "scrap", "scrap", "brick", "plaster" } }
local STOREYS_BY_BAND = { { 2, 3 }, { 2, 3 }, { 1, 2 } }

local function yawToward(dir: Vector3): number
	-- yaw that turns a kit mesh's front (+Z) toward dir
	return math.atan2(dir.X, dir.Z)
end

function Town.populate(ctx: any, folder: Folder)
	local Kit = require(script.Parent.Parent.Kit) :: any
	local PlacementUtil = require(script.Parent.Parent.PlacementUtil) :: any
	local Decor = require(script.Parent.Parent.Decor) :: any
	local PartKit = require(script.Parent.Parent.PartKit) :: any
	local data = Layout.dataFolder()
	local p = Town.plan(ctx)
	local c = p.center
	local rng = Random.new(Config.SEED + 101)

	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
		return f
	end
	local fLandmarks, fBuildings, fMarket, fProps, fOverhead, fLights, fNPC, fOutskirts =
		sub("Landmarks"), sub("Buildings"), sub("Market"), sub("Props"), sub("Overhead"), sub("Lights"), sub("NPCSpawns"), sub("Outskirts")

	-- flat spot check for part-built structures: ground samples under the footprint must agree
	local function flatGround(x: number, z: number, r: number): number?
		local lo, hi = math.huge, -math.huge
		for _, o in { Vector2.zero, Vector2.new(r, r), Vector2.new(-r, r), Vector2.new(r, -r), Vector2.new(-r, -r) } do
			if PlacementUtil.isWater(x + o.X, z + o.Y) then
				return nil
			end
			local g = PlacementUtil.ground(x + o.X, z + o.Y)
			if not g then
				return nil
			end
			lo, hi = math.min(lo, g.position.Y), math.max(hi, g.position.Y)
		end
		return hi - lo <= 0.5 and hi or nil
	end

	data:SetAttribute("Progress", "town: loading kit")
	local preload = { "StreetLampScrap", "LanternString", "WaterTank" }
	for _, n in SMALL_PROPS do
		table.insert(preload, n)
	end
	Kit.preload(preload)

	-- dome: patchwork panels on the crater floor, arches over the four avenues
	data:SetAttribute("Progress", "town: dome")
	local dome = PartKit.dome(fLandmarks, Vector3.new(c.X, p.floorY, c.Z), Town.DOME_RADIUS, Town.DOME_HEIGHT, 70, p.gateAngles, H.STREET_W + 34, 46, rng)
	dome.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- the skyline, always streamed

	-- interior lamps on a ring under the shell + a light shaft through the oculus
	local ringPhi = 0.48
	for i = 0, 23 do
		local a = i / 24 * 2 * math.pi
		local r = (Town.DOME_RADIUS - 8) * math.cos(ringPhi)
		local y = p.floorY + (Town.DOME_HEIGHT - 6) * math.sin(ringPhi) - 6
		local pos = Vector3.new(c.X + math.cos(a) * r, y, c.Z + math.sin(a) * r)
		local lamp = Instance.new("Part")
		lamp.Name = "DomeLamp"
		lamp.Anchored = true
		lamp.CanCollide = false
		lamp.CanQuery = false
		lamp.CanTouch = false
		lamp.Material = Enum.Material.Neon
		lamp.Color = Color3.fromRGB(255, 190, 120)
		lamp.Size = Vector3.new(4, 2, 4)
		lamp.CFrame = CFrame.lookAt(pos, Vector3.new(c.X, p.floorY, c.Z))
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = 60
		spot.Angle = 80
		spot.Brightness = 2.2
		spot.Color = Color3.fromRGB(255, 196, 140)
		spot.Shadows = false
		spot.Parent = lamp
		Decor.glow(lamp, Color3.fromRGB(255, 180, 110), 10)
		lamp.Parent = fLights
		Decor.cable(fLights, pos + Vector3.new(0, 1, 0), pos + Vector3.new(0, 14, 0), 0.01, nil, 0.3)
	end
	Decor.lightShaft(fLights, c + Vector3.new(0, Town.DOME_HEIGHT + 20, 0), p.hill + Vector3.new(0, Town.HILL_HEIGHT, 0), 150, Color3.fromRGB(255, 236, 200), 0.86)

	-- crater gates at the top of each gate stairway, facing out
	for _, g in p.gateAngles do
		local dir = Vector3.new(math.cos(g), 0, math.sin(g))
		local pos = c + dir * (p.gateStairEnd + 16)
		local at = Vector3.new(pos.X, S, pos.Z)
		PartKit.gate(fLandmarks, CFrame.lookAt(at, at + dir) * CFrame.Angles(0, math.rad(1.2), 0), Town.GATE_WIDTH, rng)
	end

	-- hilltop hall: the biggest house in town, gables to the dome centre
	local hallTop = groundAt(p, p.hill.X, p.hill.Z)
	local hallDir = Vector3.new(c.X - p.hill.X, 0, c.Z - p.hill.Z).Unit
	local hallAt = Vector3.new(p.hill.X, hallTop, p.hill.Z)
	local hall = PartKit.house(fLandmarks, CFrame.lookAt(hallAt, hallAt + hallDir), { w = 58, d = 42, storeys = 3, style = "brick", ridgeAlongDepth = true, lantern = true }, rng)
	hall.Name = "HillHall"
	hall.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	Decor.npcSpot(fNPC, CFrame.new(hallAt + hallDir * 30 + Vector3.new(0, 0.1, 0)), "Hall")

	-- ── buildings on lots (plinths first where a lot straddles a ledge) ──
	local placed: { { lot: Lot, model: Model, top: number } } = {}
	data:SetAttribute("Progress", "town: buildings")
	-- plinths: a lot that straddles a hill ledge stands on a stone base up to its highest corner.
	-- The plinth top is 0.5 above that corner, so it is never level with any ledge under it, and
	-- it lives in Workspace.Ground so later placement rays land on it.
	local GroundBuilder = require(script.Parent.Parent.GroundBuilder) :: any
	local ground = GroundBuilder.folder()
	local oldPlinths = ground:FindFirstChild("TownPlinths")
	if oldPlinths then
		oldPlinths:Destroy()
	end
	local fPlinths = Instance.new("Folder")
	fPlinths.Name = "TownPlinths"
	fPlinths.Parent = ground
	local plinthBody = GroundBuilder.BODIES.SlateBrown
	local shopChance = { [1] = 0.2, [2] = 0.38, [3] = 0.3 }
	for i, lot in p.lots do
		-- re-measure the footprint on the ground as built (plan() only has the analytic
		-- features; cells snap ledges up to a cell across): centre, corners and edge midpoints
		-- under the plinth. A lot that now straddles more than one ledge is skipped.
		local hi, lo = -math.huge, math.huge
		local ex, ez = (lot.w + 1.5) / 2 - 0.5, (lot.d + 1.5) / 2 - 0.5
		for _, o in { { 0, 0 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
			local wp = lot.cf:PointToWorldSpace(Vector3.new(o[1] * ex, 0, o[2] * ez))
			local gy = GroundBuilder.builtTop(ctx, wp.X, wp.Z)
			hi, lo = math.max(hi, gy), math.min(lo, gy)
		end
		if hi - lo > Town.HILL_TIER_H + 0.5 then
			continue
		end
		lot.y, lot.base = hi, lo
		lot.cf = lot.cf.Rotation + Vector3.new(lot.cf.X, hi, lot.cf.Z)
		local baseY = lot.y
		if lot.y - lot.base >= 0.5 then
			local bottom, top = lot.base - GroundBuilder.CAP / 2, lot.y + 0.5
			local plinth = Instance.new("Part")
			plinth.Name = "Plinth"
			plinth.Anchored = true
			plinth.CanTouch = false
			plinth.Material = plinthBody.material
			plinth.Color = plinthBody.color
			plinth.Size = Vector3.new(lot.w + 1.5, top - bottom, lot.d + 1.5)
			plinth.CFrame = lot.cf.Rotation + Vector3.new(lot.cf.X, (top + bottom) / 2, lot.cf.Z)
			plinth.Parent = fPlinths
			baseY = top
			-- a stoop up to the plinth across the street front (the door is on the front wall,
			-- local -Z, facing the street), from the street as built to the plinth top
			local look = lot.cf.LookVector
			local face = Vector3.new(lot.cf.X, 0, lot.cf.Z) + look * ((lot.d + 1.5) / 2)
			local probe = face + look * 2
			local streetY = GroundBuilder.builtTop(ctx, probe.X, probe.Z)
			local rise = top - streetY
			-- only on a flat street: the stoop's whole footprint must be at street level
			local flatStreet = true
			local side = lot.cf.RightVector
			for d = 1, math.ceil(rise) * 1.25 + 1, 2 do
				for _, u in { -0.45, 0, 0.45 } do
					local q = face + look * d + side * (u * lot.w)
					if GroundBuilder.builtTop(ctx, q.X, q.Z) ~= streetY then
						flatStreet = false
					end
				end
			end
			if rise > 0.6 and flatStreet then
				local run = (math.ceil(rise - 1e-6) - 1) * 1.25
				local foot = face + look * run
				GroundBuilder.stairs(fPlinths, Vector3.new(foot.X, streetY, foot.Z), -look, math.max(run, 1.25), rise, lot.w, plinthBody.material, plinthBody.color)
			end
		end
		local isShop = rng:NextNumber() < (shopChance[lot.band] or 0.3)
		local range = STOREYS_BY_BAND[lot.band] or { 1, 2 }
		local spec = {
			w = lot.w,
			d = lot.d,
			storeys = rng:NextInteger(range[1], range[2]),
			style = (STYLE_BY_BAND[lot.band] or STYLE_BY_BAND[2])[rng:NextInteger(1, 4)],
			shop = isShop,
			sign = isShop and SHOP_SIGNS[rng:NextInteger(1, #SHOP_SIGNS)] or nil,
			ridgeAlongDepth = rng:NextNumber() < 0.5,
			lantern = rng:NextNumber() < 0.3,
			stairs = rng:NextNumber() < 0.5,
		}
		local cf = lot.cf.Rotation + Vector3.new(lot.cf.X, baseY, lot.cf.Z)
		local model = PartKit.house(fBuildings, cf, spec, rng)
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- a house streams in whole
		local bcf, size = model:GetBoundingBox()
		table.insert(placed, { lot = lot, model = model, top = bcf.Y + size.Y / 2 })
		if isShop then
			Decor.npcSpot(fNPC, lot.cf * CFrame.new(0, 0, -(lot.d / 2 + 4)), "Vendor")
		end
		if i % 20 == 0 then
			data:SetAttribute("Progress", string.format("town: buildings %d/%d", i, #p.lots))
			task.wait()
		end
	end

	-- ── front-step clutter (audited kit props, never overlapping each other) ──
	data:SetAttribute("Progress", "town: clutter")
	local spacing = PlacementUtil.spacing()
	for i, rec in placed do
		local lot = rec.lot
		if rng:NextNumber() < 0.55 then
			for _ = 1, rng:NextInteger(1, 3) do
				local side = rng:NextNumber() < 0.5 and -1 or 1
				local w = lot.cf * CFrame.new(side * (lot.w / 2 - rng:NextNumber(1.5, 4)), 0, -(lot.d / 2 + rng:NextNumber(2, 4)))
				local prop = Kit.clone(SMALL_PROPS[rng:NextInteger(1, #SMALL_PROPS)])
				local _, size = prop:GetBoundingBox()
				if not PlacementUtil.scatterOne(spacing, prop, w.X, w.Z, math.max(size.X, size.Z) / 2 + 0.5, { yaw = rng:NextNumber(0, 2 * math.pi), embed = 0.2, parent = fProps, maxStep = 0.5 }) then
					prop:Destroy()
				end
			end
		end
		if i % 60 == 0 then
			task.wait()
		end
	end

	-- ── overhead: cables, laundry lines and lantern strings between facing buildings ──
	data:SetAttribute("Progress", "town: overhead lines")
	local function frontTop(rec: any, lateral: number, height: number): Vector3
		local w = rec.lot.cf * CFrame.new(lateral, 0, -(rec.lot.d / 2 + 0.6))
		return Vector3.new(w.X, math.min(rec.top - 2, rec.lot.y + height), w.Z)
	end
	local lines = 0
	for i, a in placed do
		local la = a.lot.cf.LookVector
		local bestB, bestD = nil, math.huge
		for _, b in placed do
			if b ~= a then
				local d = (Vector2.new(a.lot.cf.X, a.lot.cf.Z) - Vector2.new(b.lot.cf.X, b.lot.cf.Z)).Magnitude
				if d < 70 and d < bestD and la:Dot(b.lot.cf.LookVector) < -0.75 then
					-- b must be in front of a
					local rel = a.lot.cf:PointToObjectSpace(b.lot.cf.Position)
					if rel.Z < -10 and math.abs(rel.X) < a.lot.w / 2 + 4 then
						bestB, bestD = b, d
					end
				end
			end
		end
		if bestB and i % 2 == 0 then
			local roll = rng:NextNumber()
			local h = rng:NextNumber(12, 22)
			local lat = rng:NextNumber(-a.lot.w / 3, a.lot.w / 3)
			local p0 = frontTop(a, lat, h)
			local rel = bestB.lot.cf:PointToObjectSpace(p0)
			local p1 = frontTop(bestB, rel.X, h + rng:NextNumber(-2, 2))
			local span = (p1 - p0).Magnitude
			if span > 6 and span < 80 then
				if roll < 0.45 then
					Decor.cable(fOverhead, p0, p1, span * 0.06, nil, 0.16)
					if rng:NextNumber() < 0.5 then
						Decor.cable(fOverhead, p0 + Vector3.new(0, 1.2, 0), p1 + Vector3.new(0, 0.6, 0), span * 0.08, nil, 0.12)
					end
				elseif roll < 0.75 then
					-- laundry: line + cloths hanging along the sag (spaced, never overlapping)
					local sag = span * 0.05
					Decor.cable(fOverhead, p0, p1, sag, Color3.fromRGB(180, 170, 150), 0.08)
					local n = math.floor(span / 4)
					for k = 1, n - 1 do
						local t = k / n
						if rng:NextNumber() < 0.75 then
							local pos = p0:Lerp(p1, t) - Vector3.new(0, sag * 4 * t * (1 - t) + 1.3, 0)
							local cloth = Instance.new("Part")
							cloth.Name = "Laundry"
							cloth.Anchored = true
							cloth.CanCollide = false
							cloth.CanQuery = false
							cloth.CanTouch = false
							cloth.Material = Enum.Material.Fabric
							cloth.Color = CLOTHS[rng:NextInteger(1, #CLOTHS)]
							cloth.Size = Vector3.new(rng:NextNumber(1.6, 2.6), rng:NextNumber(2, 3.2), 0.1)
							cloth.CFrame = CFrame.lookAt(pos, pos + (p1 - p0):Cross(Vector3.yAxis)) * CFrame.Angles(0, 0, rng:NextNumber(-0.1, 0.1))
							cloth.Parent = fOverhead
						end
					end
				else
					local ls = Kit.clone("LanternString")
					Kit.fit(ls, span / 30, 1, 1)
					local mid = (p0 + p1) / 2
					local flat = Vector3.new(p1.X - p0.X, 0, p1.Z - p0.Z).Unit
					-- LanternString runs along its X axis
					ls:PivotTo(CFrame.fromMatrix(mid - Vector3.new(0, 3.3, 0), flat, Vector3.yAxis))
					ls.Parent = fOverhead
				end
				lines += 1
			end
		end
		if i % 80 == 0 then
			task.wait()
		end
	end

	-- ── street lamps along the ring roads ──
	data:SetAttribute("Progress", "town: lamps and markets")
	for _, ring in Town.RINGS do
		local circ = 2 * math.pi * ring
		local n = math.floor(circ / 46)
		for k = 0, n - 1 do
			local a = (k + 0.5) / n * 2 * math.pi
			for _, side in { -1, 1 } do
				if (k + (side > 0 and 1 or 0)) % 2 == 0 then
					local r = ring + side * (H.STREET_W / 2 - 2)
					local x, z = c.X + math.cos(a) * r, c.Z + math.sin(a) * r
					local lamp = Kit.clone("StreetLampScrap")
					local toRoad = Vector3.new(c.X + math.cos(a) * ring - x, 0, c.Z + math.sin(a) * ring - z)
					if not PlacementUtil.place(lamp, x, z, { yaw = yawToward(toRoad) + math.pi / 2, radius = 1, embed = 0.4, parent = fLights, maxStep = 0.5 }) then
						lamp:Destroy()
					end
				end
			end
		end
	end

	-- ── market: stalls lining the gate avenues + rings of stalls in the market squares ──
	local function nearPlaza(x: number, z: number, pad: number): boolean
		for _, pl in p.plazas do
			if Vector2.new(x - pl.c.X, z - pl.c.Z).Magnitude < pl.r + pad then
				return true
			end
		end
		return false
	end
	local function stallAt(x: number, z: number, facing: Vector3): boolean
		local y = flatGround(x, z, 5)
		if not y then
			return false
		end
		local at = Vector3.new(x, y, z)
		-- a little yaw: avenue stalls would otherwise be axis-aligned like the ground columns
		PartKit.stall(fMarket, CFrame.lookAt(at, at + Vector3.new(facing.X, 0, facing.Z).Unit) * CFrame.Angles(0, math.rad(rng:NextNumber(1.5, 4) * (rng:NextNumber() < 0.5 and -1 or 1)), 0), rng)
		return true
	end
	for _, l in p.laneAngles do
		if l.w >= H.STREET_W then
			local dir = Vector3.new(math.cos(l.a), 0, math.sin(l.a))
			local side = Vector3.new(-dir.Z, 0, dir.X)
			local r = Town.PLAZA_RADIUS + 60
			while r < Town.DOME_RADIUS - 40 do
				local nearRing = false
				for _, ring in Town.RINGS do
					if math.abs(r - ring) < H.STREET_W / 2 + 10 then
						nearRing = true
					end
				end
				for _, s in { -1, 1 } do
					local pos = c + dir * r + side * s * (l.w / 2 - 4.5)
					if not nearRing and not nearPlaza(pos.X, pos.Z, 6) and rng:NextNumber() < 0.8 then
						-- the counter faces the middle of the avenue
						if stallAt(pos.X, pos.Z, -side * s) then
							Decor.npcSpot(fNPC, CFrame.new(pos - side * s * 7), "Shopper")
						end
					end
				end
				r += rng:NextNumber(14, 22)
			end
		end
	end
	for _, pl in p.plazas do
		if pl.kind == "Market" then
			local n = 12
			for k = 0, n - 1 do
				local a = k / n * 2 * math.pi + rng:NextNumber(-0.08, 0.08)
				local pos = pl.c + Vector3.new(math.cos(a), 0, math.sin(a)) * pl.r * 0.72
				stallAt(pos.X, pos.Z, pl.c - pos)
			end
			local tank = Kit.clone("WaterTank")
			PlacementUtil.place(tank, pl.c.X, pl.c.Z, { radius = 2, parent = fMarket, maxStep = 0.5 })
			for k = 0, 5 do
				local a = k / 6 * 2 * math.pi
				local pos = pl.c + Vector3.new(math.cos(a), 0, math.sin(a)) * 18
				local prop = Kit.clone(({ "TableChairs", "SackPile", "BarrelRusty", "TrashBags" })[rng:NextInteger(1, 4)])
				local _, size = prop:GetBoundingBox()
				if not PlacementUtil.scatterOne(spacing, prop, pos.X, pos.Z, math.max(size.X, size.Z) / 2 + 0.5, { yaw = rng:NextNumber(0, 6.28), radius = 1.5, parent = fMarket, maxStep = 0.5 }) then
					prop:Destroy()
				end
			end
		end
	end
	for _, spot in p.npcSpots do
		local g = PlacementUtil.ground(spot.X, spot.Z)
		if g then
			Decor.npcSpot(fNPC, CFrame.new(g.position + Vector3.new(0, 0.1, 0)), "Street")
		end
	end

	-- ── outskirts: small scrap shacks outside each crater gate, facing the road ──
	data:SetAttribute("Progress", "town: outskirts")
	local shacks: { { c: Vector3, r: number } } = {}
	for _, g in p.gateAngles do
		local count = 0
		for _ = 1, 160 do
			if count >= 22 then
				break
			end
			local a = g + rng:NextNumber(-0.45, 0.45)
			local r = rng:NextNumber(Town.RIM_OUTER + 40, Town.RIM_OUTER + 320)
			local x, z = c.X + math.cos(a) * r, c.Z + math.sin(a) * r
			local lateral = angDiff(a, g) * r
			if lateral > Town.GATE_WIDTH / 2 + 24 and Layout.regionAt(x, z) == "Town" then
				local w, d = rng:NextNumber(14, 22), rng:NextNumber(14, 20)
				local reach = math.sqrt(w * w + d * d) / 2 + 3
				local free = true
				for _, o in shacks do
					if Vector2.new(x - o.c.X, z - o.c.Z).Magnitude < reach + o.r then
						free = false
						break
					end
				end
				local y = free and flatGround(x, z, math.max(w, d) / 2 + 1) or nil
				if y then
					table.insert(shacks, { c = Vector3.new(x, y, z), r = reach })
					local roadPoint = c + Vector3.new(math.cos(g), 0, math.sin(g)) * r
					local at = Vector3.new(x, y, z)
					local look = (Vector3.new(roadPoint.X, y, roadPoint.Z) - at).Unit
					local shack = PartKit.house(fOutskirts, CFrame.lookAt(at, at + look) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), { w = w, d = d, storeys = 1, style = "scrap", ridgeAlongDepth = rng:NextNumber() < 0.5, lantern = rng:NextNumber() < 0.25 }, rng)
					shack.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
					count += 1
				end
			end
		end
		task.wait()
	end

	data:SetAttribute("Progress", string.format("town: done (%d buildings, %d overhead lines)", #placed, lines))
	print(string.format("[MapGen] Town: %d buildings, %d overhead lines", #placed, lines))
end

function Town.reset()
	plan = nil
end

return Town
