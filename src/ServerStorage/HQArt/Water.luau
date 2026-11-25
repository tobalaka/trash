--!strict
--[[
	HQArt.Water (v2) - turns MapGen's flat water slabs (Workspace.Ground.Water) into living water, still parts-only
	(MapGen's rule: no smooth Terrain).

	v2, after review 1 ("glass planks"): MapGen greedy-merges water cells into many strips, and v1 treated every
	strip on its own (own flow direction, own texture origin, grown into its neighbours). Now:
	  * BODIES: strips with the same surface that touch are one body (union-find). A body gets ONE level, ONE flow
	    direction and textures anchored to the world, so the pattern runs across strip seams without a break.
	  * LEVEL: a body never stands above its bank. Where MapGen's level is higher than the dry ground around it (the
	    town canal crossing the crater floor stood 1.75 above it = glass walls), the whole body drops to just under
	    its lowest bank, and to the level of any lower body it runs into (so the canal meets its pond flush).
	    Slabs keep their original footprint (v1 grew them into each other = doubled, banded glass).
	  * LOOK: soft painterly tone (swell) + long wavy crest strokes at two scales drifting at different speeds,
	    no cells and no dots. Shore foam is a soft band with a wavy edge and broken lapping lines, only on edges
	    whose outside is a real bank at or above the water.
	  * surface life: glints winking on clean water, rising bubbles on toxic pools.
	Everything new lives in Workspace.Ground.Water.HQ_WaterFx (no collide/query/touch), so remove() is clean.

	  require(game.ServerStorage.HQArt.Water).apply() -> slabs, bodies, foam strips
	  require(game.ServerStorage.HQArt.Water).remove()

	Texture placement on a slab's Top face (measured): the image is anchored at the face's max-X / max-Z corner,
	so OffsetStudsU = (-xmax) % tile, OffsetStudsV = (-zmax) % tile makes neighbouring strips continuous, and a
	growing offset moves the pattern toward +X / +Z.
]]

local CollectionService = game:GetService("CollectionService")

local Water = {}

local IMG = {
	swell = "rbxassetid://116273592021276", -- broad light/deep tone
	ripple = "rbxassetid://137100784580832", -- wavy crests running along V
	rippleR = "rbxassetid://115749662270108", -- the same crests rotated: along U
	-- review 6: foam4 = one smooth profile (+-12% drift along the shore) shared with the corner pieces; foam3's wavy
	-- edge scrolled against the corners' average profile and every corner showed as a straight-edged square
	foam = "rbxassetid://136142349412068", -- soft shore band; image row 0 (V = 0) = the strip's +Z edge = the shore
	foamConvex = "rbxassetid://128777900491191", -- outer shore corner (water_factory2.foam_corners2)
	foamConcave = "rbxassetid://133614501032237", -- inner shore corner
	sparkle = "rbxassetid://89760104307990",
	bubble = "rbxassetid://118195293490209",
}
Water.IMG = IMG

local CLEAN = { body = Color3.fromRGB(30, 84, 100), tone = Color3.fromRGB(205, 240, 246), crest = Color3.fromRGB(225, 248, 252), foam = Color3.fromRGB(236, 248, 250) }
local THIN = 0.2 -- water sheet thickness
local TOXIC = { body = Color3.fromRGB(70, 100, 32), tone = Color3.fromRGB(220, 250, 170), crest = Color3.fromRGB(226, 255, 170), foam = Color3.fromRGB(228, 246, 192) }

local FX = "HQ_WaterFx"
local FOAM_W = 4 -- studs from the shore into the water
local SAMPLE = 4 -- shore test spacing along an edge
local FOAM_TILE = 30

type Slab = { s: BasePart, x0: number, x1: number, z0: number, z1: number, top: number, bot: number }
type Body = { slabs: { Slab }, top: number, level: number, lower: number, area: number, toxic: boolean, flow: Vector3, speed: number }

local function fxFolder(): Folder
	local w = workspace.Ground.Water
	local f = w:FindFirstChild(FX)
	if not f then
		f = Instance.new("Folder")
		f.Name = FX
		f.Parent = w
	end
	return f :: Folder
end

local function slabs(): { BasePart }
	local out = {}
	local fx = workspace.Ground.Water:FindFirstChild(FX)
	for _, d in workspace.Ground.Water:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Water" and not (fx and d:IsDescendantOf(fx)) then
			table.insert(out, d)
		end
	end
	return out
end

local function isToxic(p: BasePart): boolean
	local orig = p:GetAttribute("HQOrigColor")
	local c: Color3 = if typeof(orig) == "Color3" then orig else p.Color
	return c.B < c.G * 0.8
end

-- a world-anchored, scrolling texture on a slab's top face
local function texture(p: BasePart, img: string, tile: number, transp: number, color: Color3, vel: Vector3, tag: string): Texture
	local t = Instance.new("Texture")
	t.Name = "HQWater"
	t.Face = Enum.NormalId.Top
	t.Texture = img
	t.StudsPerTileU = tile
	t.StudsPerTileV = tile
	t.Transparency = transp
	t.Color3 = color
	local bu = (-(p.Position.X + p.Size.X / 2)) % tile
	local bv = (-(p.Position.Z + p.Size.Z / 2)) % tile
	t.OffsetStudsU = bu
	t.OffsetStudsV = bv
	t:SetAttribute("BaseU", bu)
	t:SetAttribute("BaseV", bv)
	t:SetAttribute("SpeedU", vel.X)
	t:SetAttribute("SpeedV", vel.Z)
	CollectionService:AddTag(t, tag)
	t.Parent = p
	return t
end

local function carrier(name: string, cf: CFrame, size: Vector3): Part
	local c = Instance.new("Part")
	c.Name = name
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.CastShadow = false
	c.Transparency = 1
	c.Size = size
	c.CFrame = cf
	return c
end

-- Ground top under a point (water and generated props ignored), or nil.
local function groundTop(x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Ground.Chunks }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
	return hit and hit.Position.Y or nil
end

-- Can a body be drawn as ONE sheet over its bounding rectangle? Yes when every dry spot inside that rectangle is
-- ground standing above the water level (the ground then hides the sheet there). Review 3: Glass draws each part on
-- its own, so two strips of the same water showed a hard line where they meet (and differed in brightness).
local function sheetFits(b: Body, x0: number, x1: number, z0: number, z1: number): boolean
	local x = x0 + 1
	while x < x1 do
		local z = z0 + 1
		while z < z1 do
			local inside = false
			for _, r in b.slabs do
				if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
					inside = true
					break
				end
			end
			if not inside then
				local gt = groundTop(x, z)
				if not gt or gt < b.level + 0.05 then
					return false
				end
			end
			z += 2
		end
		x += 2
	end
	return true
end

local function inAny(list: { Slab }, x: number, z: number): Slab?
	for _, r in list do
		if x >= r.x0 - 0.05 and x <= r.x1 + 0.05 and z >= r.z0 - 0.05 and z <= r.z1 + 0.05 then
			return r
		end
	end
	return nil
end

-- every point 1 stud outside a slab's edges, every SAMPLE studs: fn(x, z, edgeIndex)
local function aroundEdges(r: Slab, fn: (number, number) -> ())
	local x = r.x0 + SAMPLE / 2
	while x < r.x1 do
		fn(x, r.z0 - 1)
		fn(x, r.z1 + 1)
		x += SAMPLE
	end
	local z = r.z0 + SAMPLE / 2
	while z < r.z1 do
		fn(r.x0 - 1, z)
		fn(r.x1 + 1, z)
		z += SAMPLE
	end
end

local function restore(s: BasePart)
	local os_ = s:GetAttribute("HQOrigSize")
	if typeof(os_) == "Vector3" then
		s.Size = os_
		s.CFrame = s:GetAttribute("HQOrigCFrame") :: CFrame
	end
	s:SetAttribute("HQOrigSize", nil)
	s:SetAttribute("HQOrigCFrame", nil)
	s:SetAttribute("HQSheeted", nil)
	if s:GetAttribute("HQHidden") then
		s.Transparency = 0
		s:SetAttribute("HQHidden", nil)
	end
end

function Water.remove()
	local f = workspace.Ground.Water:FindFirstChild(FX)
	if f then
		f:Destroy()
	end
	for _, s in slabs() do
		for _, c in s:GetChildren() do
			if c.Name == "HQWater" then
				c:Destroy()
			end
		end
		restore(s)
		local oc = s:GetAttribute("HQOrigColor")
		if typeof(oc) == "Color3" then
			s.Color = oc
			s.Material = Enum.Material[s:GetAttribute("HQOrigMaterial") :: string]
			s.Transparency = s:GetAttribute("HQOrigTransparency") :: number
			s.Reflectance = 0
		end
	end
end

-- strips with the same surface that touch -> bodies
local function findBodies(list: { Slab }): { Body }
	local parent = {}
	for i = 1, #list do
		parent[i] = i
	end
	local function find(i: number): number
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	local lower: { [number]: number } = {} -- slab index -> lowest touching level of a different body
	for i = 1, #list do
		local a = list[i]
		for j = i + 1, #list do
			local b = list[j]
			if a.x0 <= b.x1 + 0.1 and b.x0 <= a.x1 + 0.1 and a.z0 <= b.z1 + 0.1 and b.z0 <= a.z1 + 0.1 then
				if math.abs(a.top - b.top) < 0.05 then
					parent[find(i)] = find(j)
				elseif a.top > b.top then
					lower[i] = math.min(lower[i] or math.huge, b.top)
				else
					lower[j] = math.min(lower[j] or math.huge, a.top)
				end
			end
		end
	end
	local byRoot: { [number]: Body } = {}
	local out = {}
	for i, r in list do
		local k = find(i)
		local b = byRoot[k]
		if not b then
			b = { slabs = {}, top = r.top, level = r.top, lower = math.huge, area = 0, toxic = isToxic(r.s), flow = Vector3.xAxis, speed = 0 }
			byRoot[k] = b
			table.insert(out, b)
		end
		table.insert(b.slabs, r)
		b.area += (r.x1 - r.x0) * (r.z1 - r.z0)
		if lower[i] then
			b.lower = math.min(b.lower, lower[i])
		end
	end
	return out
end

-- the body's level: never above its lowest bank (0.25 under it, off the 0.5 grid like MapGen's own water). A body
-- that has to drop also drops to any lower body it runs into, so the two meet flush (no step, no glass wall).
-- Bodies that sit fine keep MapGen's level, steps included.
local function settle(b: Body, all: { Slab })
	local minBank = math.huge
	for _, r in b.slabs do
		aroundEdges(r, function(x, z)
			if not inAny(all, x, z) then
				local y = groundTop(x, z)
				if y and y < minBank then
					minBank = y
				end
			end
		end)
	end
	if minBank < b.top - 0.05 then
		b.level = math.min(minBank - 0.25, b.lower)
	end
end

-- flow along the body's long axis (area-weighted principal axis of its strips); pools only drift
local function flowOf(b: Body)
	local sx, sz, w = 0, 0, 0
	for _, r in b.slabs do
		local a = (r.x1 - r.x0) * (r.z1 - r.z0)
		sx += (r.x0 + r.x1) / 2 * a
		sz += (r.z0 + r.z1) / 2 * a
		w += a
	end
	local mx, mz = sx / w, sz / w
	local cxx, czz, cxz = 0, 0, 0
	for _, r in b.slabs do
		local a = (r.x1 - r.x0) * (r.z1 - r.z0)
		local hx, hz = (r.x1 - r.x0) / 2, (r.z1 - r.z0) / 2
		local dx, dz = (r.x0 + r.x1) / 2 - mx, (r.z0 + r.z1) / 2 - mz
		-- a strip's own spread counts too (a single long slab is a river)
		cxx += a * (dx * dx + hx * hx / 3)
		czz += a * (dz * dz + hz * hz / 3)
		cxz += a * dx * dz
	end
	local tr, det = cxx + czz, cxx * czz - cxz * cxz
	local l1 = tr / 2 + math.sqrt(math.max(0, tr * tr / 4 - det))
	local l2 = math.max(1e-6, tr - l1)
	local dir = if math.abs(cxz) > 1e-6 then Vector3.new(l1 - czz, 0, cxz).Unit elseif cxx >= czz then Vector3.xAxis else Vector3.zAxis
	local river = math.sqrt(l1 / l2) >= 2.4 and b.area > 3000
	b.flow = dir
	b.speed = if river then 2.0 else 0.45
end

-- A shore run: along X (alongX) or Z, on the slab edge `line`, the water on the `sgn` side; a..b along the edge.
type Foam = {
	alongX: boolean,
	line: number,
	sgn: number,
	a: number,
	b: number,
	level: number,
	pal: any,
	rate: number,
	joinA: boolean?,
	joinB: boolean?,
}

local TAPER = 4 -- studs over which an end that stops in open water fades out
local STEPS = 6
local BASE = 0.38 -- foam texture transparency
local CORNER_TILE = FOAM_W * 1.025 -- a hair over the piece, so the image never wraps at its far edges
-- review 7: foam pieces that only butt edge to edge left pixel cracks (water without foam = a thin darker line at
-- every band / corner join); each piece reaches LAP studs past its edges (the doubled sliver is sub-pixel)
local LAP = 0.003

local function across(f: Foam): (number, number)
	local o = f.line + f.sgn * FOAM_W
	return math.min(f.line, o), math.max(f.line, o)
end

local function foamTexture(strip: BasePart, img: string, pal: any, rate: number, transp: number): Texture
	local t = Instance.new("Texture")
	t.Name = "HQWater"
	t.Face = Enum.NormalId.Top
	t.Texture = img
	t.Transparency = transp
	t.Color3 = pal.foam
	t:SetAttribute("BaseV", 0)
	t:SetAttribute("SpeedV", 0)
	-- lapping rate per BODY: every strip and corner of one body pulses together, so the joins never flicker
	t:SetAttribute("Foam", rate)
	CollectionService:AddTag(t, "HQWaterFlow")
	t.Parent = strip
	return t
end

local function foamStrip(parent: Instance, f: Foam, a: number, b: number, transp: number)
	local len = b - a
	local mid = (a + b) / 2
	local centre = if f.alongX then Vector3.new(mid, f.level, f.line) else Vector3.new(f.line, f.level, mid)
	local inward = (if f.alongX then Vector3.zAxis else Vector3.xAxis) * f.sgn
	local c = centre + inward * (FOAM_W / 2) + Vector3.new(0, 0.04, 0)
	-- +Z must point at the shore (= -inward); X = Y x Z keeps the frame right-handed (X runs along the edge)
	local z = -inward
	local x = Vector3.yAxis:Cross(z)
	local cf = CFrame.fromMatrix(c, x, Vector3.yAxis, z)
	local strip = carrier("Foam", cf, Vector3.new(len + 2 * LAP, 0.05, FOAM_W + 2 * LAP))
	local t = foamTexture(strip, IMG.foam, f.pal, f.rate, transp)
	t.StudsPerTileU = FOAM_TILE
	-- review 5: one tile exactly FOAM_W deep put V = 1 on the strip's inner edge, and the lapping (+-0.35 studs of V
	-- offset in HQWaterFlow) wrapped it onto row 0 = the opaque shore row: a ruler-straight bright line 4 studs out.
	-- 1.25 tiles keeps the inner edge at V <= 0.87, inside the image's clear bottom quarter.
	t.StudsPerTileV = FOAM_W * 1.25
	-- continuous along a straight shore: anchor U to the world coordinate of the strip's +X end along the edge, so a
	-- strip cut into steps (a fading end) keeps one unbroken pattern
	local endCoord = (c + x * len / 2):Dot(x)
	local bu = (-endCoord) % FOAM_TILE
	t.OffsetStudsU = bu
	t:SetAttribute("BaseU", bu)
	t:SetAttribute("SpeedU", 0.3)
	strip.Parent = parent
end

-- A corner piece: the bank corner C sits at the image's (0, 0) = the part's max-X / max-Z corner on a Top face.
-- toA / toB: unit world axes pointing from the piece toward C. w, d: its extent along toA / toB.
local function foamCorner(parent: Instance, img: string, cx: number, cz: number, toA: Vector3, toB: Vector3, w: number, d: number, level: number, pal: any, rate: number)
	-- right x up = back for CFrame.fromMatrix: whichever of toA / toB satisfies it is X (both images are symmetric)
	local x, z, sx, sz = toA, toB, w, d
	if toA:Cross(Vector3.yAxis):Dot(toB) < 0 then
		x, z, sx, sz = toB, toA, d, w
	end
	local centre = Vector3.new(cx, level + 0.04, cz) - x * (sx / 2) - z * (sz / 2)
	local piece = carrier("FoamCorner", CFrame.fromMatrix(centre, x, Vector3.yAxis, z), Vector3.new(sx + 2 * LAP, 0.05, sz + 2 * LAP))
	local t = foamTexture(piece, img, pal, rate, BASE)
	t.StudsPerTileU = CORNER_TILE
	t.StudsPerTileV = CORNER_TILE
	t:SetAttribute("BaseU", 0)
	t:SetAttribute("SpeedU", 0)
	t:SetAttribute("Corner", true) -- HQWaterFlow pulses it but never slides it (that would move the corner)
	piece.Parent = parent
end

-- shore runs along every slab edge whose outside is a real bank (dry ground at or above the water)
local function shoreRuns(r: Slab, level: number, all: { Slab }, pal: any, rate: number, out: { Foam })
	local function isShore(x: number, z: number): boolean
		if inAny(all, x, z) then
			return false
		end
		local y = groundTop(x, z)
		return y ~= nil and y >= level - 0.05
	end
	local edges = {
		{ a0 = r.x0, a1 = r.x1, fixed = r.z0 - 1, alongX = true, line = r.z0, sgn = 1 },
		{ a0 = r.x0, a1 = r.x1, fixed = r.z1 + 1, alongX = true, line = r.z1, sgn = -1 },
		{ a0 = r.z0, a1 = r.z1, fixed = r.x0 - 1, alongX = false, line = r.x0, sgn = 1 },
		{ a0 = r.z0, a1 = r.z1, fixed = r.x1 + 1, alongX = false, line = r.x1, sgn = -1 },
	}
	for _, e in edges do
		local runStart: number? = nil
		local n = math.max(1, math.floor((e.a1 - e.a0) / SAMPLE + 0.5))
		local stepLen = (e.a1 - e.a0) / n
		local function flush(a: number, b: number)
			-- every run counts, the short risers of a stair-step shore too: the corner pieces join them up
			table.insert(out, { alongX = e.alongX, line = e.line, sgn = e.sgn, a = a, b = b, level = level, pal = pal, rate = rate })
		end
		for k = 0, n - 1 do
			local a = e.a0 + k * stepLen
			local m = a + stepLen / 2
			local shore = if e.alongX then isShore(m, e.fixed) else isShore(e.fixed, m)
			if shore and not runStart then
				runStart = a
			elseif not shore and runStart then
				flush(runStart, a)
				runStart = nil
			end
		end
		if runStart then
			flush(runStart, e.a1)
		end
	end
end

-- Review 5: strips that met at MapGen's stair-step corners overlapped (brighter squares) or ended square in open water.
-- Now the foam follows the shore round every corner:
--   * collinear overlaps: the shorter strip gives way;
--   * INNER corner (two bands overlap where both end): both are cut back and a square piece holds both shore rows;
--   * OUTER corner (two bands only touch at the bank's tip): a quarter-round piece fills the open square beyond;
--   * an end that butts into the bank stays as it is (hidden against the bank's face);
--   * only an end that stops in open water fades out, over TAPER studs in STEPS steps.
local function placeFoam(list: { Foam }, fx: Folder, all: { Slab }): number
	local count = 0
	local function collinear(p: Foam, q: Foam): boolean
		return p.alongX == q.alongX and p.sgn == q.sgn and math.abs(p.line - q.line) < 0.5
	end
	local function toWorld(f: Foam, along: number, acr: number): (number, number)
		if f.alongX then
			return along, acr
		end
		return acr, along
	end
	local function axisOf(f: Foam): Vector3
		return if f.alongX then Vector3.xAxis else Vector3.zAxis
	end
	local function acrossAxis(f: Foam): Vector3
		return if f.alongX then Vector3.zAxis else Vector3.xAxis
	end
	for i, p in list do
		for j = i + 1, #list do
			local q = list[j]
			if collinear(p, q) then
				local o0, o1 = math.max(p.a, q.a), math.min(p.b, q.b)
				if o1 - o0 > 0.5 then
					local pShort = p.b - p.a <= q.b - q.a
					local short, long = if pShort then p else q, if pShort then q else p
					if short.a >= long.a and short.b <= long.b then
						short.b = short.a -- inside the other one: drop
					elseif short.a < long.a then
						short.b = long.a
					else
						short.a = long.b
					end
				end
			end
		end
	end
	local function endOf(f: Foam, o0: number, o1: number): string?
		local nearA, nearB = o0 <= f.a + FOAM_W + 0.05, o1 >= f.b - FOAM_W - 0.05
		if nearA and nearB then
			return if o0 - f.a < f.b - o1 then "a" else "b"
		end
		return if nearA then "a" elseif nearB then "b" else nil
	end
	-- inner corners (and the rare T where a band pokes into another's middle: that one is just cut back)
	for _, A in list do
		if not A.alongX then
			continue
		end
		for _, B in list do
			if B.alongX or A.b - A.a < 0.05 or B.b - B.a < 0.05 then
				continue
			end
			local az0, az1 = across(A)
			local bx0, bx1 = across(B)
			local ox0, ox1 = math.max(A.a, bx0), math.min(A.b, bx1)
			local oz0, oz1 = math.max(az0, B.a), math.min(az1, B.b)
			if ox1 - ox0 > 0.05 and oz1 - oz0 > 0.05 then
				local ea, eb = endOf(A, ox0, ox1), endOf(B, oz0, oz1)
				if ea and eb then
					-- the corner of the two banks: B's line is an X, A's line a Z
					local cx, cz = B.line, A.line
					local toA = Vector3.zAxis * -A.sgn -- from the water toward A's bank
					local toB = Vector3.xAxis * -B.sgn
					foamCorner(fx, IMG.foamConcave, cx, cz, toB, toA, ox1 - ox0, oz1 - oz0, A.level, A.pal, A.rate)
					count += 1
					if ea == "a" then
						A.a, A.joinA = ox1, true
					else
						A.b, A.joinB = ox0, true
					end
					if eb == "a" then
						B.a, B.joinA = oz1, true
					else
						B.b, B.joinB = oz0, true
					end
				elseif eb then
					if eb == "a" then
						B.a, B.joinA = oz1, true
					else
						B.b, B.joinB = oz0, true
					end
				elseif ea then
					if ea == "a" then
						A.a, A.joinA = ox1, true
					else
						A.b, A.joinB = ox0, true
					end
				end
			end
		end
	end
	-- outer corners: f ends at the bank's tip where g starts, each band lying beyond the other's end. A strip cut to
	-- nothing by an inner corner still counts (a 4-stud riser: inner corner at one end, outer corner at the other).
	for _, f in list do
		for _, isB in { false, true } do
			if (isB and f.joinB) or (not isB and f.joinA) then
				continue
			end
			local e, out = if isB then f.b else f.a, if isB then 1 else -1
			for _, g in list do
				if g.alongX == f.alongX or math.abs(g.line - e) > 0.5 or g.sgn ~= out then
					continue
				end
				local gB = math.abs(g.b - f.line) < 0.5 and not g.joinB
				local gA = math.abs(g.a - f.line) < 0.5 and not g.joinA
				local gOut = if gB then 1 elseif gA then -1 else 0
				if gOut == 0 or f.sgn ~= gOut then
					continue
				end
				local sx, sz = toWorld(f, e + out * FOAM_W / 2, f.line + f.sgn * FOAM_W / 2)
				if not inAny(all, sx, sz) then
					continue -- not open water beyond the tip
				end
				local cx, cz = toWorld(f, e, f.line)
				local toF = axisOf(f) * -out -- from the square back toward the tip along f
				local toG = acrossAxis(f) * -f.sgn -- and along g
				foamCorner(fx, IMG.foamConvex, cx, cz, toF, toG, FOAM_W, FOAM_W, f.level, f.pal, f.rate)
				count += 1
				if isB then
					f.joinB = true
				else
					f.joinA = true
				end
				if gB then
					g.joinB = true
				else
					g.joinA = true
				end
				break
			end
		end
	end
	-- an end is continued when a collinear strip starts within a stud of it
	local function continued(f: Foam, e: number): boolean
		for _, g in list do
			if g ~= f and g.b - g.a >= 0.5 and collinear(f, g) and (math.abs(g.a - e) < 1 or math.abs(g.b - e) < 1) then
				return true
			end
		end
		return false
	end
	-- an end that butts into the bank (dry ground just past it, across the band) is hidden against the bank's face
	local function againstBank(f: Foam, e: number, out: number): boolean
		local dry = 0
		for _, d in { 1, 2, 3 } do
			local x, z = toWorld(f, e + out * 0.75, f.line + f.sgn * d)
			if not inAny(all, x, z) then
				local y = groundTop(x, z)
				if y and y >= f.level - 0.05 then
					dry += 1
				end
			end
		end
		return dry >= 2
	end
	for _, f in list do
		local len = f.b - f.a
		if len < 2 then
			continue
		end
		local fadeA = not f.joinA and not continued(f, f.a) and not againstBank(f, f.a, -1)
		local fadeB = not f.joinB and not continued(f, f.b) and not againstBank(f, f.b, 1)
		local ta = if fadeA then math.min(TAPER, len / 3) else 0
		local tb = if fadeB then math.min(TAPER, len / 3) else 0
		foamStrip(fx, f, f.a + ta, f.b - tb, BASE)
		count += 1
		-- step k = 1 sits next to the body, k = STEPS at the very end
		for k = 1, STEPS do
			local tr = BASE + (1 - BASE) * k / (STEPS + 1)
			if ta > 0 then
				local s1 = f.a + ta * (1 - (k - 1) / STEPS)
				foamStrip(fx, f, s1 - ta / STEPS, s1, tr)
				count += 1
			end
			if tb > 0 then
				local s0 = f.b - tb * (1 - (k - 1) / STEPS)
				foamStrip(fx, f, s0, s0 + tb / STEPS, tr)
				count += 1
			end
		end
	end
	return count
end

function Water.apply(): (number, number, number)
	Water.remove()
	local parts = slabs()
	local all: { Slab } = {}
	for _, s in parts do
		table.insert(all, {
			s = s,
			x0 = s.Position.X - s.Size.X / 2,
			x1 = s.Position.X + s.Size.X / 2,
			z0 = s.Position.Z - s.Size.Z / 2,
			z1 = s.Position.Z + s.Size.Z / 2,
			top = s.Position.Y + s.Size.Y / 2,
			bot = s.Position.Y - s.Size.Y / 2,
		})
	end
	local bodies = findBodies(all)
	for i, b in bodies do
		settle(b, all)
		flowOf(b)
		if i % 4 == 0 then
			task.wait()
		end
	end
	local fx = fxFolder()
	local strips = 0
	local sheets = 0
	for bi, b in bodies do
		local pal = if b.toxic then TOXIC else CLEAN
		local vel = b.flow * b.speed
		-- crests lie across the flow: crests along V when the flow is mostly along X (U), else the rotated image
		local crestImg = if math.abs(b.flow.X) >= math.abs(b.flow.Z) then IMG.ripple else IMG.rippleR
		local side = Vector3.new(-b.flow.Z, 0, b.flow.X)
		-- one sheet for the whole body where the ground around it can hide the rectangle's dry corners
		local bx0, bx1, bz0, bz1 = math.huge, -math.huge, math.huge, -math.huge
		for _, r in b.slabs do
			bx0, bx1 = math.min(bx0, r.x0), math.max(bx1, r.x1)
			bz0, bz1 = math.min(bz0, r.z0), math.max(bz1, r.z1)
		end
		local sheet: Part? = nil
		if #b.slabs > 1 and sheetFits(b, bx0, bx1, bz0, bz1) then
			local sh = Instance.new("Part")
			sh.Name = "WaterSheet"
			sh.Anchored = true
			sh.CanCollide = false
			sh.CanQuery = false
			sh.CanTouch = false
			sh.CastShadow = false
			sh.Size = Vector3.new(bx1 - bx0, THIN, bz1 - bz0)
			sh.CFrame = CFrame.new((bx0 + bx1) / 2, b.level - THIN / 2, (bz0 + bz1) / 2)
			-- review 6: Glass draws every part with its own refraction pass, so two touching strips of one river came out
			-- pale and dark with a straight line between them; at transparency 0.1 SmoothPlastic looks the same, evenly
			sh.Material = Enum.Material.SmoothPlastic
			sh.Color = pal.body
			-- review 3: at 0.28 the bed steps under the water showed as lines; review 6: even at 0.1 each strip let a
			-- different slice of MapGen's stepped bed through, a brightness step at every strip edge. Opaque water.
			sh.Transparency = 0
			sh.Reflectance = 0.16
			texture(sh, IMG.swell, 70, 0.15, pal.tone, vel * 0.3 + side * 0.08, "HQWaterFlow")
			texture(sh, crestImg, 24, 0.35, pal.crest, vel, "HQWaterFlow")
			texture(sh, crestImg, 37, 0.55, pal.crest, vel * 0.62 - side * 0.12, "HQWaterFlow")
			sh.Parent = fx
			sheet = sh
			sheets += 1
		end
		for _, r in b.slabs do
			local s = r.s
			if s:GetAttribute("HQOrigColor") == nil then
				s:SetAttribute("HQOrigColor", s.Color)
				s:SetAttribute("HQOrigMaterial", s.Material.Name)
				s:SetAttribute("HQOrigTransparency", s.Transparency)
			end
			s:SetAttribute("HQOrigSize", s.Size)
			s:SetAttribute("HQOrigCFrame", s.CFrame)
			if b.level - r.bot < 0.3 then
				-- the bed here is above the new level: no water on this strip
				s.Transparency = 1
				s:SetAttribute("HQHidden", true)
				continue
			end
			-- a thin sheet at the surface (review 2: 2-11 stud thick see-through strips showed the faces where two
			-- strips touch as lines inside the water); the slabs never collide, the bed is ground below
			s.Size = Vector3.new(s.Size.X, THIN, s.Size.Z)
			s.CFrame = CFrame.new(s.Position.X, b.level - THIN / 2, s.Position.Z)
			if sheet then
				-- the body's sheet draws this strip; the strip stays as MapGen's data, invisible
				s.Transparency = 1
				s:SetAttribute("HQSheeted", true)
				continue
			end
			s.Material = Enum.Material.SmoothPlastic -- not Glass (see the sheet above)
			s.Color = pal.body
			s.Transparency = 0 -- opaque (see the sheet above)
			s.Reflectance = 0.16
			texture(s, IMG.swell, 70, 0.15, pal.tone, vel * 0.3 + side * 0.08, "HQWaterFlow")
			texture(s, crestImg, 24, 0.35, pal.crest, vel, "HQWaterFlow")
			texture(s, crestImg, 37, 0.55, pal.crest, vel * 0.62 - side * 0.12, "HQWaterFlow")
		end
		local runs: { Foam } = {}
		local rate = 0.8 + (bi % 7) * 0.06 -- lapping rate, one per body
		for _, r in b.slabs do
			if not r.s:GetAttribute("HQHidden") then
				shoreRuns(r, b.level, all, pal, rate, runs)
			end
		end
		strips += placeFoam(runs, fx, all)
		-- surface life, per strip big enough to hold it
		for _, r in b.slabs do
			local s = r.s
			local area = s.Size.X * s.Size.Z
			if area >= 900 and not s:GetAttribute("HQHidden") then
				local top = CFrame.new(s.Position.X, b.level + 0.12, s.Position.Z)
				local c = carrier(if b.toxic then "Bubbles" else "Glints", top, Vector3.new(s.Size.X - 4, 0.1, s.Size.Z - 4))
				local pe = Instance.new("ParticleEmitter")
				pe.Shape = Enum.ParticleEmitterShape.Box
				pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
				pe.LockedToPart = true
				if b.toxic then
					pe.Texture = IMG.bubble
					-- review 2: many small bright bubbles read as white specks from mid distance -> few, big, soft
					pe.Rate = math.clamp(area / 1100, 0.6, 6)
					pe.Lifetime = NumberRange.new(2.2, 3.4)
					pe.Speed = NumberRange.new(0.1, 0.3)
					pe.EmissionDirection = Enum.NormalId.Top
					pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.8, 1.7, 0.4), NumberSequenceKeypoint.new(1, 2.3) })
					pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.5), NumberSequenceKeypoint.new(0.8, 0.55), NumberSequenceKeypoint.new(1, 1) })
					pe.Color = ColorSequence.new(Color3.fromRGB(176, 214, 112))
					pe.LightEmission = 0.1
				else
					pe.Texture = IMG.sparkle
					pe.Rate = math.clamp(area / 220, 2, 30)
					pe.Lifetime = NumberRange.new(0.35, 0.8)
					pe.Speed = NumberRange.new(0, 0)
					pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.8, 0.3), NumberSequenceKeypoint.new(1, 0) })
					pe.Transparency = NumberSequence.new(0.2)
					pe.Rotation = NumberRange.new(0, 45)
					pe.Color = ColorSequence.new(Color3.fromRGB(235, 252, 255))
					pe.LightEmission = 1
					pe.Brightness = 2
				end
				pe.Orientation = Enum.ParticleOrientation.FacingCamera
				pe.Parent = c
				c.Parent = fx
			end
		end
		if bi % 2 == 0 then
			task.wait()
		end
	end
	Water.lastSheets = sheets
	return #all, #bodies, strips
end

return Water
