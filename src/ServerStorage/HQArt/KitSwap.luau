--!strict
--[[
	HQArt.KitSwap - replaces MapGen's kit props in the world with the HQArt kit, with variety.

	Every placed MapGen kit model carries an "Asset" attribute (Cactus2, MossRock1, ...). MAP lists the HQArt
	variants that replace it. Per placement (RNG seeded from its position, so a re-run is identical):
	  * a variant is picked from the list (no more 46 copies of one cactus),
	  * it stands upright at the old spot with a random yaw and a 0.85-1.15 size,
	  * it is re-seated on the real ground (ray down onto Workspace.Ground, sunk EMBED studs),
	  * its painted parts get a small tint shift (SurfaceAppearance.Color), so neighbours never match exactly.
	The original model moves to ServerStorage.HQArt_Backup and is linked from the new one ("Original"
	ObjectValue), so undo() puts everything back exactly.

	  require(game.ServerStorage.HQArt.KitSwap).apply(workspace.World)   -> count
	  require(game.ServerStorage.HQArt.KitSwap).undo(workspace.World)
]]

local KitSwap = {}

KitSwap.MAP = {
	Cactus1 = { "SaguaroA", "SaguaroB" },
	Cactus2 = { "SaguaroA", "SaguaroC", "SaguaroB" },
	Cactus3 = { "BarrelA", "BarrelB", "PearA" },
	-- rocks v2 (Rocks2: dense faceted SDF rocks; review 1 rejected the hull boulders). Desert v3 (Rocks3, review 2:
	-- "arches = candy canes, hoodoos = lighthouses"): arches are fins with a worn opening, hoodoos bulge, soft strata
	-- Rocks5 (review 6): every capped spire still read as a striped column / knob from below, so MapGen's hoodoo
	-- spots get desert buttes: flat-topped cliff blocks on a rubble apron
	HoodooRock1 = { "Butte5A", "Butte5C", "Butte5B" },
	HoodooRock2 = { "Butte5B", "Butte5A", "Butte5C" },
	RockArch = { "Arch3A", "Arch3B", "Arch3C" },
	MossRock1 = { "Moss2A", "Moss2B" },
	MossRock2 = { "Moss2B", "Moss2C", "Moss2A" },
	MossRock3 = { "Moss2C", "Moss2D" },
	WindRock1 = { "Wind2A", "Wind2B" },
	WindRock2 = { "Wind2B", "Wind2C", "Wind2A" },
	WindRock3 = { "Wind2C", "Wind2D" },
	WashingMachine = { "WasherA", "WasherB", "WasherA" },
	BarrelRusty = { "DrumA", "DrumB", "DrumC" },
	TyreStack1 = { "TyreA", "TyreC" },
	TyreStack2 = { "TyreB", "TyreA" },
	TrashBags = { "BagsA", "BagsB" },
	SackPile = { "SacksA", "SacksB" },
	ScrapPanelPile = { "ScrapA", "ScrapB" },
	ShoppingCart = { "CartA" },
	Sofa = { "SofaA", "SofaB" },
	Bucket = { "BucketA" },
	TableChairs = { "TableA" },
	Handcart = { "HandcartA" },
	StreetLampScrap = { "LampA", "LampB" },
	BentSign = { "SignA", "SignB" },
	Antenna = { "AntennaA" },
	Fern1 = { "FernA", "FernB" },
	Fern2 = { "FernB", "FernC" },
	Fern3 = { "FernC", "FernA" },
	FlowerPatch = { "FlowersA" },
	Mushrooms = { "ShroomsA" },
	FallenLog1 = { "LogA" },
	FallenLog2 = { "LogB" },
	GiantRoot1 = { "RootA" },
	GiantRoot2 = { "RootB" },
	RuinColumn1 = { "ColumnA" },
	RuinWall1 = { "RuinWallA" },
	SnowDrift1 = { "DriftA" },
	SnowDrift2 = { "DriftB" },
} :: { [string]: { string } }

-- placements that face something (a street, a wall): keep the old rotation exactly, no random yaw, no resize
KitSwap.KEEP = { Stall = true, TownGate = true, StreetLampScrap = true, BentSign = true, TableChairs = true, FallenLog1 = true, FallenLog2 = true,
	GiantRoot1 = true, GiantRoot2 = true, RuinWall1 = true, SnowDrift1 = true, SnowDrift2 = true } :: { [string]: boolean }

-- per-placement colour drift on painted parts (SurfaceAppearance.Color): hue centre (nil = any hue), max
-- saturation, value range. Foliage drifts more (yellower / bluer greens), stone barely.
KitSwap.TINT = {
	default = { hue = nil, sat = 0.05, v = { 0.9, 1.0 } },
	GiantTree = { hue = 0.22, sat = 0.1, v = { 0.68, 0.86 } }, -- leaf-card crowns (Foliage1): the atlas carries its own greens
	Cactus1 = { hue = 0.2, sat = 0.1, v = { 0.88, 1.0 } },
	Cactus2 = { hue = 0.2, sat = 0.1, v = { 0.88, 1.0 } },
	Cactus3 = { hue = 0.2, sat = 0.1, v = { 0.88, 1.0 } },
	Fern1 = { hue = 0.24, sat = 0.12, v = { 0.75, 0.95 } },
	Fern2 = { hue = 0.24, sat = 0.12, v = { 0.75, 0.95 } },
	Fern3 = { hue = 0.24, sat = 0.12, v = { 0.75, 0.95 } },
	-- rocks v2: jungle boulders sit in deep shade (pale grey glowed), desert stone a touch warmer and dimmer
	MossRock1 = { hue = 0.28, sat = 0.1, v = { 0.6, 0.72 } },
	MossRock2 = { hue = 0.28, sat = 0.1, v = { 0.6, 0.72 } },
	MossRock3 = { hue = 0.28, sat = 0.1, v = { 0.6, 0.72 } },
	-- desert v3: the calmer strata read pale pink-white against the warm sand in Roblox's light -> warmer, dimmer
	HoodooRock1 = { hue = 0.07, hueJit = 0.02, satMin = 0.14, sat = 0.26, v = { 0.74, 0.86 } },
	HoodooRock2 = { hue = 0.07, hueJit = 0.02, satMin = 0.14, sat = 0.26, v = { 0.74, 0.86 } },
	RockArch = { hue = 0.07, hueJit = 0.02, satMin = 0.14, sat = 0.26, v = { 0.74, 0.86 } },
	-- jungle ruins sit in deep shade: pale stone glowed like a pile of white blocks. A cool tint multiplies the cream
	-- toward grey stone (a warm one turned it straw yellow)
	RuinWall1 = { hue = 0.53, sat = 0.16, v = { 0.56, 0.66 } },
	RuinColumn1 = { hue = 0.53, sat = 0.14, v = { 0.6, 0.7 } },
	-- moss on roots and logs read lime against the dim jungle floor
	GiantRoot1 = { hue = 0.2, sat = 0.1, v = { 0.55, 0.66 } },
	GiantRoot2 = { hue = 0.2, sat = 0.1, v = { 0.55, 0.66 } },
	FallenLog1 = { hue = 0.2, sat = 0.08, v = { 0.62, 0.74 } },
	FallenLog2 = { hue = 0.2, sat = 0.08, v = { 0.62, 0.74 } },
} :: { [string]: { hue: number?, hueJit: number?, satMin: number?, sat: number, v: { number } } }

-- Generated models that aren't kit assets, matched by Name. Variants are chosen by the old model's height and
-- scaled so the new one is as tall as the old one (x 0.93..1.07).
KitSwap.BYNAME = {
	Stall = { { minH = 0, list = { "StallFruit", "StallCloth", "StallScrap" } } },
	TownGate = { { minH = 0, list = { "GateA" } } },
	GiantTree = {
		{ minH = 125, list = { "JungleGiantA", "JungleGiantB", "JungleKapokE" } },
		{ minH = 75, list = { "JungleCrownC", "JungleCrownD", "JungleKapokE" } },
		{ minH = 0, list = { "JungleCrownC", "JungleFigF", "JungleCrownD", "JungleFigF" } },
	},
} :: { [string]: { { minH: number, list: { string } } } }

-- PartKit-built models have a world-aligned pivot: read their facing from a part built in the lot frame
KitSwap.FACING = { Stall = "Counter", TownGate = "Lintel" } :: { [string]: string }

-- per-asset size range (default 0.85..1.15)
KitSwap.SCALE = { RockArch = { 0.78, 0.98 } } :: { [string]: { number } } -- the arches are a little wider than MapGen's
KitSwap.EMBED = 0.45
-- rocks must sit on ground that is level enough (review 2: hoodoos over a 171-stud drop, winter rocks buried 6 studs
-- on one side): the ground across the middle 60% of the footprint may vary by at most SEAT_K x the rock's height.
-- Failing spots try nearby offsets, then a 25% smaller rock; with no spot left the rock is left out (an empty HQ
-- model keeps the link to the original so undo / reswap still work).
KitSwap.SEAT = { HoodooRock1 = true, HoodooRock2 = true, RockArch = true, MossRock1 = true, MossRock2 = true, MossRock3 = true,
	WindRock1 = true, WindRock2 = true, WindRock3 = true } :: { [string]: boolean }
KitSwap.SEAT_K = 0.25
KitSwap.UPRIGHT = { Cactus1 = true, Cactus2 = true, Cactus3 = true, GiantTree = true, HoodooRock1 = true, HoodooRock2 = true, RockArch = true,
	Mushrooms = true, RuinColumn1 = true } :: { [string]: boolean }

local function backupFolder(name: string): Folder
	local root = game.ServerStorage:FindFirstChild("HQArt_Backup")
	if not root then
		root = Instance.new("Folder")
		root.Name = "HQArt_Backup"
		root.Parent = game.ServerStorage
	end
	local f = root:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = root
	end
	return f :: Folder
end

local function groundY(pos: Vector3): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Ground") :: Instance }
	local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y or nil
end

local function groundHit(pos: Vector3): (number?, boolean)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Ground") :: Instance }
	-- start far above: a ray that starts inside a cliff block never sees that block (rocks at a cliff foot passed)
	local hit = workspace:Raycast(pos + Vector3.new(0, 500, 0), Vector3.new(0, -1000, 0), params)
	if not hit then
		return nil, false
	end
	local water = workspace.Ground:FindFirstChild("Water")
	return hit.Position.Y, (water ~= nil and hit.Instance:IsDescendantOf(water))
end

-- ground spread (max - min) across the middle 60% of a footprint of half-size (hx, hz) at p, turned by rot (the
-- placement's final rotation); nil = water or no ground under some sample
local function groundSpread(p: Vector3, hx: number, hz: number, rot: CFrame): (number?, number?)
	local lo, hi = math.huge, -math.huge
	local rx, rz = rot.RightVector, rot.LookVector
	local grid = {}
	for i = -2, 2 do
		for j = -2, 2 do
			table.insert(grid, { i / 2, j / 2 }) -- 5 x 5 incl. the corners (a mesa edge under one corner passed a ring)
		end
	end
	for _, o in grid do
		local q = p + rx * (o[1] * hx * 0.6) + rz * (o[2] * hz * 0.6)
		local y, wet = groundHit(Vector3.new(q.X, p.Y, q.Z))
		if not y or wet then
			return nil, nil
		end
		lo, hi = math.min(lo, y), math.max(hi, y)
	end
	return hi - lo, lo
end

-- share of the WHOLE footprint (7 x 7 to its edges) whose ground lies more than 2 studs below the ground under the
-- centre (review 3: rocks flat under their middle still hung an edge over a 35-170 stud drop at mesa rims)
local function overhang(p: Vector3, hx: number, hz: number, rot: CFrame): number
	local base = groundHit(p)
	if not base then
		return 1
	end
	local rx, rz = rot.RightVector, rot.LookVector
	local low, n = 0, 0
	for i = -3, 3 do
		for j = -3, 3 do
			local q = p + rx * (i / 3 * hx * 0.95) + rz * (j / 3 * hz * 0.95)
			local y, wet = groundHit(Vector3.new(q.X, p.Y, q.Z))
			n += 1
			if not y or wet or y < base - 2 then
				low += 1
			end
		end
	end
	return low / n
end

-- Fallen logs (review 7: 8 of 44 lay across terrace steps, sunk 6-12 studs at one end, floating 5-6 at the other).
-- Sample the ground at 13 points along the trunk on two lines across its width, in the FINAL rotation; accept when it
-- varies <= LOG_FLAT and no water. Try the original spot first, then turns and slides. (position, extra yaw) or nil.
KitSwap.LOGSEAT = { FallenLog1 = true, FallenLog2 = true }
local LOG_FLAT = 1.0
local function logSpread(p: Vector3, len: number, wid: number, rot: CFrame): (number?, number?)
	local ax, side = rot.RightVector, rot.LookVector
	local lo, hi = math.huge, -math.huge
	for i = 0, 12 do
		for _, s in { -0.35, 0.35 } do
			local q = p + ax * ((i / 12 - 0.5) * len * 0.96) + side * (s * wid)
			local y, wet = groundHit(Vector3.new(q.X, p.Y, q.Z))
			if not y or wet then
				return nil, nil
			end
			lo, hi = math.min(lo, y), math.max(hi, y)
		end
	end
	return hi - lo, (hi + lo) / 2
end

local function logSeat(new: Model, p: Vector3, rot: CFrame): (Vector3?, number, number?)
	local _, size = new:GetBoundingBox()
	local len, wid = math.max(size.X, size.Z), math.min(size.X, size.Z)
	local long = if size.X >= size.Z then 0 else math.pi / 2 -- the trunk runs along the template's X (or Z)
	for _, turn in { 0, 0.35, -0.35, 0.8, -0.8, 1.2, -1.2, math.pi / 2 } do
		local r = rot * CFrame.Angles(0, turn + long, 0)
		for _, slide in { 0, 0.25, -0.25, 0.5, -0.5 } do
			for _, across in { 0, 0.3, -0.3 } do
				local q = p + r.RightVector * (slide * len) + r.LookVector * (across * len)
				local spread, mid = logSpread(q, len, wid, r)
				if spread and spread <= LOG_FLAT then
					return q, turn, mid
				end
			end
		end
	end
	return nil, 0, nil
end

-- review 8: the box tests above sample a footprint grid; a butte's real base outline still hung 0.25-1.6 over a
-- terrace step (a dark gap under the rim). The outline is measured once per template with horizontal rays just over
-- its base, and every outline point must sit on ground no more than RIM_DROP below the centre's ground.
KitSwap.RIMSEAT = { HoodooRock1 = true, HoodooRock2 = true }
-- the outline is taken where the mesh meets the centre's ground (the pivot is the mesh bottom, sunk EMBED); the scree
-- runs on down ~0.15 past it, so a ground drop over 0.45 under the outline shows a gap (review 8: 0.25-1.6)
local RIM_DROP = 0.45
local RIM_N = 32
local rimCache: { [Model]: { number } } = {}

local function rimOutline(tmpl: Model): { number }
	if rimCache[tmpl] then
		return rimCache[tmpl]
	end
	local probe = tmpl:Clone()
	local at = CFrame.new(0, 20000, 0)
	probe:PivotTo(at)
	for _, d in probe:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanQuery = true
		end
	end
	probe.Parent = workspace
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { probe }
	local _, size = probe:GetBoundingBox()
	local far = math.max(size.X, size.Z)
	local radii = {}
	for k = 0, RIM_N - 1 do
		local a = k / RIM_N * 2 * math.pi
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local from = at.Position + Vector3.new(0, KitSwap.EMBED + 0.05, 0) + dir * far
		local hit = workspace:Raycast(from, -dir * far, params)
		radii[k + 1] = if hit then Vector3.new(hit.Position.X - at.X, 0, hit.Position.Z - at.Z).Magnitude else 0
	end
	probe:Destroy()
	-- a ray can slip through a gap in the collision hull at that height: take the larger neighbour there
	for k = 1, RIM_N do
		if radii[k] == 0 then
			local l, r = radii[(k - 2) % RIM_N + 1], radii[k % RIM_N + 1]
			radii[k] = math.max(l, r)
		end
	end
	rimCache[tmpl] = radii
	return radii
end
KitSwap.rimOutline = rimOutline

-- every point of the base outline (radii in the template's frame, times f) on ground no lower than RIM_DROP
local function rimOk(q: Vector3, rot: CFrame, rim: { number }, f: number): boolean
	local g0 = groundY(q) or groundHit(q)
	if not g0 then
		return false
	end
	for k, r in rim do
		local a = (k - 1) / #rim * 2 * math.pi
		local w = q + rot:VectorToWorldSpace(Vector3.new(math.cos(a), 0, math.sin(a))) * r * f * 0.97
		local y, wet = groundHit(w)
		if not y or wet or y < g0 - RIM_DROP then
			return false
		end
	end
	return true
end
KitSwap.rimOk = rimOk

-- find a seat for a rock of the template's footprint near p: (position, scale factor) or nil
local function seat(new: Model, p: Vector3, rot: CFrame, rim: { number }?, f: number?): (Vector3?, number)
	local _, size = new:GetBoundingBox()
	for _, shrink in { 1, 0.75 } do
		local hx, hz, h = size.X * shrink / 2, size.Z * shrink / 2, size.Y * shrink
		local reach = math.max(hx, hz)
		local tries = { Vector3.zero }
		for _, d in { 0.5, 1.0, 1.5 } do
			for k = 0, 7 do
				local a = k * math.pi / 4
				table.insert(tries, Vector3.new(math.cos(a), 0, math.sin(a)) * reach * d)
			end
		end
		for _, off in tries do
			local spread = groundSpread(p + off, hx, hz, rot)
			if spread and spread <= KitSwap.SEAT_K * h and overhang(p + off, hx, hz, rot) <= 0.08
				and (not rim or rimOk(p + off, rot, rim, (f or 1) * shrink)) then
				return p + off, shrink
			end
		end
	end
	return nil, 1
end

-- Trees whose crown runs into a cliff (review 3: a fig crown 48% inside a 92-stud wall, cut flat against it).
-- Share of sample points in each leaf part's own oriented box (5 x 5 x 5 at 80% of its half-size) that come within
-- 2 studs of a ground block. Review 4: an ellipsoid inside an AABB built from 4 of the 8 corners missed crowns
-- reaching 31 studs into a canyon wall on rotated trees.
local function crownInside(m: Model): (number, Vector3)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Ground:FindFirstChild("Chunks") or workspace.Ground }
	local inside, n, sum, centre = 0, 0, Vector3.zero, Vector3.zero
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and (string.sub(d.Name, 1, 6) == "Leaves" or d.Name == "Core" or d.Name == "Vines") then
			local cf, half = d.CFrame, d.Size / 2
			centre += cf.Position
			for i = -2, 2 do
				for j = -2, 2 do
					for k = -2, 2 do
						local q = cf * Vector3.new(i / 2 * 0.8 * half.X, j / 2 * 0.8 * half.Y, k / 2 * 0.8 * half.Z)
						n += 1
						if #workspace:GetPartBoundsInRadius(q, 2, params) > 0 then
							inside += 1
							sum += q
						end
					end
				end
			end
		end
	end
	if n == 0 then
		return 0, Vector3.zero
	end
	centre /= n / 125
	return inside / n, if inside > 0 then sum / inside - centre else Vector3.zero
end
KitSwap.crownInside = crownInside

-- review 5: up to 2% let a few samples sit INSIDE canyon walls (8-11 studs deep on two giants); now no sample of any
-- leaf box may come within 2 studs of the ground
local CROWN_OK = 0

-- push a tree straight away from the cliff its crown runs into, staying on its own terrace (base within 3 studs)
local function clearCrown(m: Model): boolean
	local frac, toWall = crownInside(m)
	if frac <= CROWN_OK then
		return false
	end
	local start = m:GetPivot()
	local y0 = groundY(start.Position) or start.Y
	local away = Vector3.new(-toWall.X, 0, -toWall.Z)
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
	local best, bestFrac = start, frac
	for step = 1, 20 do
		local pos = start.Position + away * step * 4
		local y, wet = groundHit(pos)
		if y and not wet and math.abs(y - y0) <= 3 then
			m:PivotTo(CFrame.new(pos.X, y - KitSwap.EMBED, pos.Z) * start.Rotation)
			local f = crownInside(m)
			if f <= CROWN_OK then
				return true
			end
			if f < bestFrac then
				best, bestFrac = m:GetPivot(), f
			end
		end
	end
	-- no clear spot on this terrace: the least-bad spot, then a smaller tree until the crown is clear
	m:PivotTo(best)
	for _ = 1, 5 do
		m:ScaleTo(m:GetScale() * 0.85)
		if crownInside(m) <= CROWN_OK then
			break
		end
	end
	return true
end
KitSwap.clearCrown = clearCrown

local function tint(model: Model, rng: Random, name: string)
	local t = KitSwap.TINT[name] or KitSwap.TINT.default
	local j = t.hueJit or 0.08
	local hue = if t.hue then (t.hue + rng:NextNumber(-j, j)) % 1 else rng:NextNumber()
	local c = Color3.fromHSV(hue, rng:NextNumber(t.satMin or 0, t.sat), rng:NextNumber(t.v[1], t.v[2]))
	for _, sa in model:GetDescendants() do
		if sa:IsA("SurfaceAppearance") then
			-- near-white tint: keeps the paint, but no two neighbours match exactly
			sa.Color = c
		end
	end
end

function KitSwap.apply(root: Instance): number
	local kit = game.ServerStorage:FindFirstChild("HQArt") and game.ServerStorage.HQArt:FindFirstChild("Kit")
	assert(kit, "HQArt.Kit not staged")
	local todo = {}
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and not m:GetAttribute("HQ") then
			local a = m:GetAttribute("Asset")
			if (typeof(a) == "string" and KitSwap.MAP[a]) or (a == nil and KitSwap.BYNAME[m.Name]) then
				table.insert(todo, m)
			end
		end
	end
	local n = 0
	for i, old in todo do
		local name = (old:GetAttribute("Asset") :: string?) or old.Name
		local pivot = old:GetPivot()
		local p = pivot.Position
		local rng = Random.new(math.floor(math.abs(p.X * 31 + p.Z * 17 + p.Y)) % 2147483647 + 1)
		local byName = KitSwap.BYNAME[name]
		local oldCf, oldSize = old:GetBoundingBox()
		local list
		if byName then
			for _, tier in byName do
				if oldSize.Y >= tier.minH then
					list = tier.list
					break
				end
			end
			p = Vector3.new(oldCf.X, oldCf.Y - oldSize.Y / 2, oldCf.Z) -- bottom centre of the old model
		else
			list = KitSwap.MAP[name]
		end
		local variant = list[rng:NextInteger(1, #list)]
		local tmpl = kit:FindFirstChild(variant) :: Model?
		if not tmpl then
			continue
		end
		local new = tmpl:Clone()
		if byName and KitSwap.KEEP[name] then
			local _, ts = tmpl:GetBoundingBox()
			new:ScaleTo(oldSize.Y / ts.Y)
		elseif byName then
			local _, ts = tmpl:GetBoundingBox()
			new:ScaleTo(oldSize.Y / ts.Y * rng:NextNumber(0.93, 1.07))
		elseif KitSwap.KEEP[name] then
			new:ScaleTo(old:GetScale())
		else
			local range = KitSwap.SCALE[name] or { 0.85, 1.15 }
			new:ScaleTo(rng:NextNumber(range[1], range[2]) * old:GetScale())
		end
		local yaw = if KitSwap.KEEP[name] then 0 else rng:NextNumber(0, 2 * math.pi)
		local rot = if KitSwap.UPRIGHT[name] then CFrame.new() else pivot.Rotation
		local facing = KitSwap.FACING[name] and old:FindFirstChild(KitSwap.FACING[name], true) :: BasePart?
		if facing then
			local look = facing.CFrame.LookVector
			rot = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z)) -- yaw only
		end
		if KitSwap.SEAT[name] then
			local rim = if KitSwap.RIMSEAT[name] then rimOutline(tmpl) else nil
			local at, shrink = seat(new, p, rot * CFrame.Angles(0, yaw, 0), rim, new:GetScale() / tmpl:GetScale())
			if not at then
				-- nowhere level enough: leave this rock out, keep the original linked for undo / reswap
				new:Destroy()
				new = Instance.new("Model")
				new.Name = variant
				new:SetAttribute("HQSkipped", true)
			else
				p = at
				if shrink ~= 1 then
					new:ScaleTo(new:GetScale() * shrink)
				end
			end
		end
		local logMid: number? = nil
		if KitSwap.LOGSEAT[name] then
			local at, turn, mid = logSeat(new, p, rot * CFrame.Angles(0, yaw, 0))
			if not at then
				new:Destroy()
				new = Instance.new("Model")
				new.Name = variant
				new:SetAttribute("HQSkipped", true)
			else
				p, yaw, logMid = at, yaw + turn, mid
			end
		end
		local y = logMid or groundY(p)
		local base = if y then Vector3.new(p.X, y - KitSwap.EMBED, p.Z) else p
		if not new:GetAttribute("HQSkipped") then
			new:PivotTo(CFrame.new(base) * rot * CFrame.Angles(0, yaw, 0))
			if name == "GiantTree" then
				clearCrown(new)
			end
		end
		tint(new, rng, name)
		new:SetAttribute("HQ", true)
		new:SetAttribute("Asset", variant)
		new:SetAttribute("ReplacedAsset", name)
		local link = Instance.new("ObjectValue")
		link.Name = "Original"
		link.Value = old
		link.Parent = new
		new.Parent = old.Parent
		old.Parent = backupFolder(name)
		n += 1
		if i % 40 == 0 then
			task.wait()
		end
	end
	return n
end

-- re-apply the per-family tint to every swapped model (same seeded colour as apply() would give)
function KitSwap.retint(root: Instance): number
	local n = 0
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("HQ") then
			local link = m:FindFirstChild("Original") :: ObjectValue?
			local name = m:GetAttribute("ReplacedAsset") :: string
			local src = if link and link.Value then (link.Value :: Model):GetPivot().Position else m:GetPivot().Position
			local rng = Random.new(math.floor(math.abs(src.X * 31 + src.Z * 17 + src.Y)) % 2147483647 + 1)
			rng:NextNumber() -- keep the same stream position as apply(): variant pick ...
			rng:NextNumber() -- ... and scale come first
			tint(m, rng, name)
			n += 1
		end
	end
	return n
end

-- Props whose core sits inside a house or shop (review 1: 109, 25 of them pushed in by the swap's bigger
-- footprint or random yaw, the rest placed that way by MapGen): push each one straight away from the wall it hits,
-- 1 stud at a time up to 5, re-seated on the ground; if it still won't clear, shrink it to 80% and try again.
local function buildingParts(root: Instance): { Instance }
	local out = {}
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and (m.Name == "House" or m.Name == "Shop") then
			table.insert(out, m)
		end
	end
	return out
end

local function coreHit(m: Model, params: OverlapParams): BasePart?
	local cf, size = m:GetBoundingBox()
	local core = Vector3.new(size.X * 0.6, size.Y * 0.5, size.Z * 0.6)
	for _, p in workspace:GetPartBoundsInBox(cf * CFrame.new(0, size.Y * 0.1, 0), core, params) do
		if p.CanCollide and p.Transparency < 1 then
			return p
		end
	end
	return nil
end

function KitSwap.unstick(root: Instance): (number, number)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = buildingParts(root)
	local fixed, left = 0, 0
	for i, m in root:GetDescendants() do
		if not (m:IsA("Model") and m:GetAttribute("HQ")) then
			continue
		end
		local fam = m:GetAttribute("ReplacedAsset") :: string
		if not KitSwap.MAP[fam] or KitSwap.UPRIGHT[fam] or m:GetAttribute("HQSkipped") then
			continue -- rocks, cacti and trees stand where MapGen's terrain features are; only loose props move
		end
		local hit = coreHit(m, params)
		if not hit then
			continue
		end
		local start = m:GetPivot()
		local s0 = m:GetScale()
		local done = false
		for _, scale in { 1, 0.8 } do
			if scale ~= 1 then
				m:ScaleTo(m:GetScale() * scale)
			end
			local away = start.Position - hit.Position
			away = Vector3.new(away.X, 0, away.Z)
			away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
			for step = 1, 5 do
				local pos = start.Position + away * step
				local y = groundY(pos)
				local base = if y then Vector3.new(pos.X, y - KitSwap.EMBED, pos.Z) else pos
				m:PivotTo(CFrame.new(base) * start.Rotation)
				if not coreHit(m, params) then
					done = true
					break
				end
			end
			if done then
				break
			end
		end
		if done then
			fixed += 1
		else
			m:ScaleTo(s0)
			m:PivotTo(start)
			left += 1
		end
		if i % 400 == 0 then
			task.wait()
		end
	end
	return fixed, left
end

-- re-run the swap for some families only (after their kit changed): put their originals back, then apply()
-- picks exactly those up again (every other family's originals are in the backup folder, out of the world)
function KitSwap.reswap(root: Instance, families: { string }): number
	local set = {}
	for _, f in families do
		set[f] = true
	end
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("HQ") and set[m:GetAttribute("ReplacedAsset") :: string] then
			local link = m:FindFirstChild("Original") :: ObjectValue?
			if link and link.Value then
				link.Value.Parent = m.Parent
				m:Destroy()
			end
		end
	end
	return KitSwap.apply(root)
end

function KitSwap.undo(root: Instance): number
	local n = 0
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("HQ") then
			local link = m:FindFirstChild("Original") :: ObjectValue?
			if link and link.Value then
				link.Value.Parent = m.Parent
				m:Destroy()
				n += 1
			end
		end
	end
	return n
end

return KitSwap
