--!strict
--[[
	MapGen.PlacementUtil - raycast grounding for every generated object.

	Why raycasts instead of "y = SURFACE_Y": the ground is stacked terraces of Parts
	(Workspace.Ground: columns, stairs, plinths) with many different ledge heights, so the only
	reliable source of truth for "where is the ground here" is the physics query against what was
	actually built. Rays EXCLUDE Workspace.World (all generated assets), so a tree never lands on
	top of another tree's canopy and props can't stack on half-built neighbours; they hit the
	ground parts only. Water slabs (Workspace.Ground.Water) are skipped by ground rays and have
	their own query, isWater().

	Models are expected to pivot at their bottom centre (MapGen.Kit sets that up). place() samples
	the centre plus a ring of points at the footprint radius and sits the model on the LOWEST hit,
	then sinks it by EMBED, so on a slope no side is left hanging in the air; the uphill side is
	simply buried a little. maxStep refuses spots where the footprint spans a ledge (the samples
	differ by more than maxStep), so a building never hangs half off a terrace. align > 0 tilts
	the model toward the surface normal (rocks, debris), capped by MAX_TILT.

	validate() is the safety net that runs after generation: anything whose lowest point is more
	than FLOAT_TOLERANCE above the highest ground sample under its footprint is dropped onto the
	ground; anything buried deeper than half its height is reported.
]]

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)
local GroundBuilder = require(script.Parent.GroundBuilder)

local PlacementUtil = {}

local P = Config.PLACEMENT
local GROUNDED_TAG = "MapGenGrounded"

local excluded: { Instance } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
local waterParams = RaycastParams.new()
waterParams.FilterType = Enum.RaycastFilterType.Include

local function refresh()
	local water = GroundBuilder.waterFolder()
	local list = table.clone(excluded)
	table.insert(list, water)
	params.FilterDescendantsInstances = list
	waterParams.FilterDescendantsInstances = { water }
end

-- Folders whose contents must never count as ground (all generated assets).
function PlacementUtil.setExcluded(list: { Instance })
	excluded = table.clone(list)
	refresh()
end

function PlacementUtil.addExcluded(inst: Instance)
	table.insert(excluded, inst)
	refresh()
end

export type GroundHit = { position: Vector3, normal: Vector3, material: Enum.Material }

-- Ground under (x, z), ignoring water slabs (props stand on the bed or the bank).
function PlacementUtil.ground(x: number, z: number): GroundHit?
	local r = workspace:Raycast(Vector3.new(x, P.RAY_TOP, z), Vector3.new(0, -P.RAY_LENGTH, 0), params)
	if not r then
		return nil
	end
	return { position = r.Position, normal = r.Normal, material = r.Material }
end

-- True when a water slab covers (x, z).
function PlacementUtil.isWater(x: number, z: number): boolean
	return workspace:Raycast(Vector3.new(x, P.RAY_TOP, z), Vector3.new(0, -P.RAY_LENGTH, 0), waterParams) ~= nil
end

-- Slope in degrees at (x, z) from the surface normal.
function PlacementUtil.slope(x: number, z: number): number?
	local g = PlacementUtil.ground(x, z)
	if not g then
		return nil
	end
	return math.deg(math.acos(math.clamp(g.normal.Y, -1, 1)))
end

export type PlaceOptions = {
	yaw: number?, -- radians around world Y
	align: number?, -- 0 = upright, 1 = fully aligned to the ground normal (capped by maxTilt)
	maxTilt: number?, -- degrees
	embed: number?, -- studs pushed below the lowest ground sample
	radius: number?, -- footprint sampling radius (defaults from the model's extents)
	maxSlope: number?, -- refuse to place where the ground is steeper than this (degrees)
	maxStep: number?, -- refuse to place where ground samples under the footprint differ by more (studs)
	allowWater: boolean?, -- allow placement where water covers the ground
	parent: Instance?,
}

-- Footprint radius used for sampling: a third of the smaller horizontal extent, so tall trees
-- sample around the trunk instead of the canopy edge. Stored on the model for validate().
local function footprintRadius(model: Model): number
	local fixed = model:GetAttribute("GroundRadius")
	if typeof(fixed) == "number" then
		return fixed
	end
	local _, size = model:GetBoundingBox()
	return math.max(0.5, math.min(size.X, size.Z) / 3)
end

local RING = 6
local function sampleRing(x: number, z: number, radius: number): ({ GroundHit }, GroundHit?)
	local centre = PlacementUtil.ground(x, z)
	local hits: { GroundHit } = {}
	if centre then
		table.insert(hits, centre)
	end
	for i = 0, RING - 1 do
		local a = i / RING * math.pi * 2
		local g = PlacementUtil.ground(x + math.cos(a) * radius, z + math.sin(a) * radius)
		if g then
			table.insert(hits, g)
		end
	end
	return hits, centre
end

-- Ground a model (pivot = bottom centre) at (x, z). Returns false if there is no valid ground.
function PlacementUtil.place(model: Model, x: number, z: number, opts: PlaceOptions?): boolean
	local o: PlaceOptions = opts or {}
	local radius = o.radius or footprintRadius(model)
	if not o.allowWater and PlacementUtil.isWater(x, z) then
		return false
	end
	local hits, centre = sampleRing(x, z, radius)
	if not centre or #hits < 3 then
		return false
	end
	if not o.allowWater then
		-- the footprint ring must be dry too, not just the centre
		for i = 0, RING - 1 do
			local a = i / RING * math.pi * 2
			if PlacementUtil.isWater(x + math.cos(a) * radius, z + math.sin(a) * radius) then
				return false
			end
		end
	end
	local slopeDeg = math.deg(math.acos(math.clamp(centre.normal.Y, -1, 1)))
	if o.maxSlope and slopeDeg > o.maxSlope then
		return false
	end
	local lowest, highest = math.huge, -math.huge
	for _, h in hits do
		lowest = math.min(lowest, h.position.Y)
		highest = math.max(highest, h.position.Y)
	end
	if o.maxStep and highest - lowest > o.maxStep then
		return false
	end
	local embed = o.embed or P.EMBED
	local pos = Vector3.new(x, lowest - embed, z)

	-- orientation: yaw, then optional tilt toward the ground normal
	local up = Vector3.yAxis
	local align = o.align or 0
	if align > 0 then
		-- average normal across the footprint is smoother than a single sample
		local n = Vector3.zero
		for _, h in hits do
			n += h.normal
		end
		n = n.Unit
		local target = Vector3.yAxis:Lerp(n, align).Unit
		local maxTilt = math.rad(o.maxTilt or P.MAX_TILT)
		local angle = math.acos(math.clamp(target.Y, -1, 1))
		if angle > maxTilt then
			local axis = Vector3.yAxis:Cross(target).Unit
			target = CFrame.fromAxisAngle(axis, maxTilt):VectorToWorldSpace(Vector3.yAxis)
		end
		up = target
		-- tilted bases need a deeper embed so the raised edge does not lift off
		pos -= Vector3.new(0, math.sin(math.acos(math.clamp(up.Y, -1, 1))) * radius, 0)
	end
	local yaw = CFrame.Angles(0, o.yaw or 0, 0)
	local tilt = CFrame.new()
	if up ~= Vector3.yAxis then
		local axis = Vector3.yAxis:Cross(up)
		if axis.Magnitude > 1e-4 then
			tilt = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(up.Y, -1, 1)))
		end
	end
	model:PivotTo(CFrame.new(pos) * tilt * yaw)
	model:SetAttribute("GroundRadius", radius)
	CollectionService:AddTag(model, GROUNDED_TAG)
	if o.parent then
		model.Parent = o.parent
	end
	return true
end

-- Ground an already-positioned model where it stands (keeps its yaw/tilt).
function PlacementUtil.dropToGround(model: Model, embed: number?): boolean
	local pivot = model:GetPivot()
	local low = PlacementUtil.lowestPoint(model)
	local radius = footprintRadius(model)
	local hits = sampleRing(pivot.X, pivot.Z, radius)
	if #hits == 0 then
		return false
	end
	local lowest = math.huge
	for _, h in hits do
		lowest = math.min(lowest, h.position.Y)
	end
	model:PivotTo(pivot - Vector3.new(0, low - (lowest - (embed or P.EMBED)), 0))
	model:SetAttribute("GroundRadius", radius)
	CollectionService:AddTag(model, GROUNDED_TAG)
	return true
end

-- Lowest world-space Y of any part in the model (exact for boxes, conservative for meshes).
function PlacementUtil.lowestPoint(model: Instance): number
	local low = math.huge
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf = p.CFrame
			local s = p.Size / 2
			local halfY = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
			low = math.min(low, cf.Y - halfY)
		end
	end
	return low
end

export type Report = { checked: number, fixed: number, buried: number, noGround: number, details: { string } }

-- Re-check every grounded model under root. Fix floaters, report buried/unsupported ones.
function PlacementUtil.validate(root: Instance, tolerance: number?): Report
	local tol = tolerance or P.FLOAT_TOLERANCE
	local report: Report = { checked = 0, fixed = 0, buried = 0, noGround = 0, details = {} }
	local n = 0
	for _, inst in CollectionService:GetTagged(GROUNDED_TAG) do
		if not inst:IsA("Model") or not inst:IsDescendantOf(root) then
			continue
		end
		local model = inst :: Model
		report.checked += 1
		local pivot = model:GetPivot()
		local radius = footprintRadius(model)
		local hits = sampleRing(pivot.X, pivot.Z, radius)
		if #hits == 0 then
			report.noGround += 1
			table.insert(report.details, "no ground under " .. model:GetFullName())
			continue
		end
		local gmin, gmax = math.huge, -math.huge
		for _, h in hits do
			gmin = math.min(gmin, h.position.Y)
			gmax = math.max(gmax, h.position.Y)
		end
		local low = PlacementUtil.lowestPoint(model)
		if low > gmax + tol then
			-- floating: its lowest point clears even the highest ground under it
			local drop = low - gmax + P.EMBED
			model:PivotTo(pivot - Vector3.new(0, drop, 0))
			report.fixed += 1
			if #report.details < 40 then
				table.insert(report.details, string.format("dropped %.1f: %s", drop, model:GetFullName()))
			end
		else
			local _, size = model:GetBoundingBox()
			if low < gmin - math.max(4, size.Y * 0.5) then
				report.buried += 1
				if #report.details < 40 then
					table.insert(report.details, string.format("buried %.1f: %s", gmin - low, model:GetFullName()))
				end
			end
		end
		n += 1
		if n % 400 == 0 then
			task.wait()
		end
	end
	print(string.format("[MapGen] grounding check: %d checked, %d floating fixed, %d buried, %d without ground",
		report.checked, report.fixed, report.buried, report.noGround))
	for _, line in report.details do
		print("   " .. line)
	end
	return report
end

-- ─── spacing: minimum-distance bookkeeping for scattered objects ────────────────
-- Scattered props must never overlap: two copies of one mesh overlapping would put identical
-- faces in the same plane (Z-fighting), and overlapping props read as a placement bug.

export type Spacing = { cell: number, grid: { [number]: { { x: number, z: number, r: number } } } }

function PlacementUtil.spacing(cell: number?): Spacing
	return { cell = cell or 64, grid = {} }
end

local function spacingKeys(s: Spacing, x: number, z: number, r: number): { number }
	local out = {}
	for gx = math.floor((x - r) / s.cell), math.floor((x + r) / s.cell) do
		for gz = math.floor((z - r) / s.cell), math.floor((z + r) / s.cell) do
			table.insert(out, gx * 100003 + gz)
		end
	end
	return out
end

-- True when a disc of radius r at (x, z) touches no reserved disc.
function PlacementUtil.isFree(s: Spacing, x: number, z: number, r: number): boolean
	for _, k in spacingKeys(s, x, z, r) do
		for _, o in s.grid[k] or {} do
			local dx, dz = x - o.x, z - o.z
			if dx * dx + dz * dz < (r + o.r) * (r + o.r) then
				return false
			end
		end
	end
	return true
end

function PlacementUtil.reserve(s: Spacing, x: number, z: number, r: number)
	for _, k in spacingKeys(s, x, z, r) do
		local list = s.grid[k]
		if not list then
			list = {}
			s.grid[k] = list
		end
		table.insert(list, { x = x, z = z, r = r })
	end
end

-- Place a kit prop at a free spot (reserving it on success). The reserved disc is at least the
-- prop's half-diagonal plus its bounding-box offset from the pivot, so a rectangular prop at
-- any yaw stays inside it and two props never overlap at their corners.
function PlacementUtil.scatterOne(s: Spacing, model: Model, x: number, z: number, r: number, opts: PlaceOptions?): boolean
	local bcf, size = model:GetBoundingBox()
	local pivot = model:GetPivot().Position
	local offset = Vector2.new(bcf.X - pivot.X, bcf.Z - pivot.Z).Magnitude
	r = math.max(r, offset + math.sqrt(size.X * size.X + size.Z * size.Z) / 2)
	if not PlacementUtil.isFree(s, x, z, r) then
		return false
	end
	if PlacementUtil.place(model, x, z, opts) then
		PlacementUtil.reserve(s, x, z, r)
		return true
	end
	return false
end

PlacementUtil.TAG = GROUNDED_TAG
return PlacementUtil
