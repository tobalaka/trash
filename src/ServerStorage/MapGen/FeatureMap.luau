--!strict
--[[
	MapGen.FeatureMap - flat-topped ground features on a spatial hash.

	The ground is built the way the reference world builds it: flat terraces stacked on flat
	terraces, cut by flat basins, never a slope or a rolling hill. Every terrace, rock tier,
	basin, pad and road cut is one Feature with a flat top. A ground column's height is the
	region's base height folded through every feature that covers the column, in layer order
	(ties keep insertion order):

	  raise : top = max(top, f.top)   terraces, rock tiers, crater rims, mounds
	  carve : top = min(top, f.top)   basins, river beds, crater floors
	  set   : top = f.top             pads, plazas, stair corridors (exact height)

	A feature that changes the height also takes over the surface key (cap material), unless
	its key is nil. Carve features may carry a water level; GroundBuilder lays a water slab
	over any column whose final top is below it.

	Shapes: "rect" (a rectangle with a yaw) and "disc" (a circle whose radius can wobble with
	angle, so crater rims are irregular rather than compass-drawn).
]]

local FeatureMap = {}
FeatureMap.__index = FeatureMap

local GRID = 256

export type Feature = {
	shape: string,
	op: string,
	layer: number,
	top: number,
	key: string?,
	water: number?,
	-- rect
	cf: CFrame?,
	half: Vector2?,
	axisAligned: boolean?,
	-- disc
	c: Vector2?,
	r: number?,
	wobble: number?,
	seed: number?,
	-- bounds + stable order
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	order: number,
}

export type Map = typeof(setmetatable({} :: { cells: { [number]: { Feature } }, count: number, sorted: boolean, list: { Feature } }, FeatureMap))

function FeatureMap.new(): Map
	return setmetatable({ cells = {}, count = 0, sorted = true, list = {} }, FeatureMap)
end

local function key(gx: number, gz: number): number
	return gx * 65536 + gz
end

-- Round to the 0.5-stud height grid every surface uses (keeps neighbouring tops either equal
-- or at least 0.5 apart, never 0.01 apart).
function FeatureMap.q(y: number): number
	return math.floor(y * 2 + 0.5) / 2
end

function FeatureMap.add(self: Map, f: Feature): Feature
	self.count += 1
	f.order = self.count
	f.top = FeatureMap.q(f.top)
	table.insert(self.list, f)
	for gx = math.floor(f.minX / GRID), math.floor(f.maxX / GRID) do
		for gz = math.floor(f.minZ / GRID), math.floor(f.maxZ / GRID) do
			local k = key(gx, gz)
			local cell = self.cells[k]
			if not cell then
				cell = {}
				self.cells[k] = cell
			end
			table.insert(cell, f)
		end
	end
	self.sorted = false
	return f
end

-- Rectangle centred on (cx, cz) with half extents (hx, hz), rotated by yaw (radians).
function FeatureMap.rect(self: Map, op: string, layer: number, cx: number, cz: number, hx: number, hz: number, top: number, surfaceKey: string?, yaw: number?, water: number?): Feature
	local y = yaw or 0
	local cf = CFrame.new(cx, 0, cz) * CFrame.Angles(0, y, 0)
	local ext = Vector3.new(math.abs(math.cos(y)) * hx + math.abs(math.sin(y)) * hz, 0, math.abs(math.sin(y)) * hx + math.abs(math.cos(y)) * hz)
	return self:add({
		shape = "rect",
		op = op,
		layer = layer,
		top = top,
		key = surfaceKey,
		water = water,
		cf = cf,
		half = Vector2.new(hx, hz),
		axisAligned = math.abs(math.sin(y * 2)) < 1e-6,
		minX = cx - ext.X,
		maxX = cx + ext.X,
		minZ = cz - ext.Z,
		maxZ = cz + ext.Z,
		order = 0,
	})
end

-- Rectangle from world-space bounds.
function FeatureMap.box(self: Map, op: string, layer: number, x0: number, x1: number, z0: number, z1: number, top: number, surfaceKey: string?, water: number?): Feature
	return self:rect(op, layer, (x0 + x1) / 2, (z0 + z1) / 2, math.abs(x1 - x0) / 2, math.abs(z1 - z0) / 2, top, surfaceKey, 0, water)
end

-- Disc; wobble is the fraction of the radius the edge may wander (0 = perfect circle).
function FeatureMap.disc(self: Map, op: string, layer: number, cx: number, cz: number, r: number, top: number, surfaceKey: string?, wobble: number?, seed: number?, water: number?): Feature
	local reach = r * (1 + (wobble or 0))
	return self:add({
		shape = "disc",
		op = op,
		layer = layer,
		top = top,
		key = surfaceKey,
		water = water,
		c = Vector2.new(cx, cz),
		r = r,
		wobble = wobble or 0,
		seed = seed or 0,
		minX = cx - reach,
		maxX = cx + reach,
		minZ = cz - reach,
		maxZ = cz + reach,
		order = 0,
	})
end

-- Segment of a corridor (river, canal, road cut): a rect from a to b, `halfWidth` either side.
function FeatureMap.segment(self: Map, op: string, layer: number, a: Vector3, b: Vector3, halfWidth: number, top: number, surfaceKey: string?, water: number?): Feature
	local d = Vector2.new(b.X - a.X, b.Z - a.Z)
	local len = d.Magnitude
	local yaw = math.atan2(-d.Y, d.X) -- rect local X runs along the segment
	-- extend each segment by its half width so consecutive segments overlap at the joints
	return self:rect(op, layer, (a.X + b.X) / 2, (a.Z + b.Z) / 2, len / 2 + halfWidth, halfWidth, top, surfaceKey, yaw, water)
end

local function contains(f: Feature, x: number, z: number): boolean
	if x < f.minX or x > f.maxX or z < f.minZ or z > f.maxZ then
		return false
	end
	if f.shape == "rect" then
		local half = f.half :: Vector2
		if f.axisAligned then
			local cf = f.cf :: CFrame
			-- yaw 0 or 180: local X = world X; yaw 90/270: swapped (bounds already tested)
			if math.abs(cf.RightVector.X) > 0.5 then
				return math.abs(x - cf.X) <= half.X and math.abs(z - cf.Z) <= half.Y
			end
			return math.abs(x - cf.X) <= half.Y and math.abs(z - cf.Z) <= half.X
		end
		local lp = (f.cf :: CFrame):PointToObjectSpace(Vector3.new(x, 0, z))
		return math.abs(lp.X) <= half.X and math.abs(lp.Z) <= half.Y
	end
	local c = f.c :: Vector2
	local dx, dz = x - c.X, z - c.Y
	local d = math.sqrt(dx * dx + dz * dz)
	local r = f.r :: number
	local wob = f.wobble :: number
	if wob > 0 and d > 1e-3 then
		local ca, sa = dx / d, dz / d
		local s = f.seed :: number
		r *= 1 + wob * (math.noise(ca * 1.7 + s, sa * 1.7, s * 0.37) * 0.7 + math.noise(ca * 4.1, sa * 4.1 + s, s * 0.71) * 0.3)
	end
	return d <= r
end

local function sortCell(a: Feature, b: Feature): boolean
	if a.layer ~= b.layer then
		return a.layer < b.layer
	end
	return a.order < b.order
end

function FeatureMap.finalize(self: Map)
	if self.sorted then
		return
	end
	for _, cell in self.cells do
		table.sort(cell, sortCell)
	end
	self.sorted = true
end

-- Fold every feature covering (x, z) into (top, key). Returns top, key, water level (or nil).
function FeatureMap.query(self: Map, x: number, z: number, top: number, surfaceKey: string): (number, string, number?)
	if not self.sorted then
		self:finalize()
	end
	local cell = self.cells[key(math.floor(x / GRID), math.floor(z / GRID))]
	if not cell then
		return top, surfaceKey, nil
	end
	local water: number? = nil
	for _, f in cell do
		if not contains(f, x, z) then
			continue
		end
		local op = f.op
		local changed = false
		if op == "raise" then
			if f.top > top then
				top, changed = f.top, true
			end
		elseif op == "carve" then
			if f.top < top then
				top, changed = f.top, true
			end
			if f.water then
				water = math.max(water or -math.huge, f.water :: number)
			end
		else -- set
			top, changed = f.top, true
			water = f.water
		end
		if changed and f.key then
			surfaceKey = f.key :: string
		end
	end
	return top, surfaceKey, water
end

return FeatureMap
