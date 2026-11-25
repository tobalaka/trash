--!strict
--[[
	Regions.Wasteland - the world's dumping ground.

	Ground (flat features, GroundBuilder): a flat compacted-trash plain with blocky asphalt
	patches, junk mounds built as stacked rubble blocks (the reference's stepped cliffs, in trash
	colours), low trash plateaus, and stepped sludge basins with sludge slabs. The greybox walls
	stay walls: each one becomes a tall stack of rock blocks with buttresses, dressed in populate.
]]

local Config = require(script.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.Layout)
local FeatureMap = require(script.Parent.Parent.FeatureMap)
local GroundBuilder = require(script.Parent.Parent.GroundBuilder)

local Wasteland = {}
Wasteland.NAME = "Wasteland"

local S = Config.GROUND.SURFACE_Y
Wasteland.BASE_Y = S - 4 -- the dumping ground lies a jump below the town plains
Wasteland.BASE_KEY = "WasteGround"
Wasteland.ROCK_KEY = "WasteRock"
Wasteland.POOL_COUNT = 11
Wasteland.HEAP_COUNT = 14 -- junk mounds (stacked rubble blocks)
Wasteland.HEAP_TIER_H = 9 -- one ledge of a junk mound
Wasteland.PLATEAU_COUNT = 18 -- low trash plateaus on the plain
Wasteland.HIGHLAND_COUNT = 9 -- stepped rubble hills between the junk mounds
Wasteland.POOL_LEVEL = Wasteland.BASE_Y - 2.75 -- sludge surface (off the 0.5 grid: never coplanar with ground)

export type Pool = { c: Vector3, r: number, depth: number }
export type Heap = { c: Vector3, r: number, h: number, yaw: number }
export type Plan = { pools: { Pool }, heaps: { Heap } }

local plan: Plan? = nil

local function nearWall(x: number, z: number, pad: number): boolean
	for _, b in Layout.blocksOf("WastelandWall") do
		local lp = b.cf:PointToObjectSpace(Vector3.new(x, b.cf.Y, z))
		if math.abs(lp.X) < b.size.X / 2 + pad and math.abs(lp.Z) < b.size.Z / 2 + pad then
			return true
		end
	end
	return false
end

-- random point inside one of the wasteland rectangles, away from walls and other features
local function pickPoint(rng: Random, taken: { { c: Vector3, r: number } }, r: number, wallPad: number): Vector3?
	local rects = Layout.rectsOf("Wasteland")
	for _ = 1, 200 do
		local rect = rects[rng:NextInteger(1, #rects)]
		local lx = rng:NextNumber(-0.5, 0.5) * (rect.size.X - 2 * r - 80)
		local lz = rng:NextNumber(-0.5, 0.5) * (rect.size.Z - 2 * r - 80)
		local p = rect.cf:PointToWorldSpace(Vector3.new(lx, 0, lz))
		p = Vector3.new(p.X, Wasteland.BASE_Y, p.Z)
		if Layout.regionAt(p.X, p.Z) ~= "Wasteland" or nearWall(p.X, p.Z, r + wallPad) then
			continue
		end
		local ok = true
		for _, t in taken do
			if (Vector2.new(t.c.X, t.c.Z) - Vector2.new(p.X, p.Z)).Magnitude < t.r + r + 60 then
				ok = false
				break
			end
		end
		if ok then
			return p
		end
	end
	return nil
end

function Wasteland.plan(ctx: any): Plan
	if plan then
		return plan
	end
	local rng = Random.new(Config.SEED + 22)
	local p: Plan = { pools = {}, heaps = {} }
	local taken: { { c: Vector3, r: number } } = {}

	-- the town's polluted canal empties into a big sludge lake
	local Town = ctx.regions.Town
	local canal = Town.plan(ctx).canal
	if #canal > 0 then
		local endP = canal[#canal]
		local lake = { c = Vector3.new(endP.X - 120, Wasteland.BASE_Y, endP.Z), r = 190, depth = 10 }
		table.insert(p.pools, lake)
		table.insert(taken, { c = lake.c, r = lake.r })
	end
	for _ = 1, Wasteland.HEAP_COUNT do
		local r = rng:NextNumber(110, 260)
		local c = pickPoint(rng, taken, r, 40)
		if c then
			table.insert(p.heaps, { c = c, r = r, h = r * rng:NextNumber(0.45, 0.7), yaw = rng:NextNumber(0, 2 * math.pi) })
			table.insert(taken, { c = c, r = r })
		end
	end
	for _ = 1, Wasteland.POOL_COUNT do
		local r = rng:NextNumber(45, 120)
		local c = pickPoint(rng, taken, r, 30)
		if c then
			table.insert(p.pools, { c = c, r = r, depth = rng:NextNumber(6, 10) })
			table.insert(taken, { c = c, r = r })
		end
	end
	plan = p
	return p
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

function Wasteland.ground(ctx: any, fm: FeatureMap.Map)
	local p = Wasteland.plan(ctx)
	local rng = Random.new(Config.SEED + 23)
	local base = Wasteland.BASE_Y
	-- the walls: tall stacked rock with buttresses (layer 2, raise)
	for _, b in Layout.blocksOf("WastelandWall") do
		local cx, cz, yaw, half, top = GroundBuilder.footprint(b.cf, b.size)
		GroundBuilder.rockTiers(fm, cx, cz, yaw, half, { base = base, top = top, key = "WasteRock", tierHeight = 45, inset = 0.07, buttresses = 4, layer = 2, rng = rng })
	end
	-- junk mounds: stacked rubble ledges, slightly elongated, axis-aligned like the reference
	for _, heap in p.heaps do
		local stretch = rng:NextNumber(0.7, 1)
		local half = rng:NextNumber() < 0.5 and Vector2.new(heap.r * 0.85, heap.r * 0.85 * stretch) or Vector2.new(heap.r * 0.85 * stretch, heap.r * 0.85)
		GroundBuilder.rockTiers(fm, heap.c.X, heap.c.Z, 0, half, {
			base = base,
			top = base + heap.h * 0.55,
			key = "WasteRubble",
			tierHeight = Wasteland.HEAP_TIER_H,
			inset = 0.2,
			buttresses = 5,
			layer = 2,
			rng = rng,
		})
	end
	-- low plateaus between the mounds
	local rects = Layout.rectsOf("Wasteland")
	local placed = 0
	for _ = 1, 300 do
		if placed >= Wasteland.PLATEAU_COUNT then
			break
		end
		local rect = rects[rng:NextInteger(1, #rects)]
		local lx = rng:NextNumber(-0.45, 0.45) * rect.size.X
		local lz = rng:NextNumber(-0.45, 0.45) * rect.size.Z
		local w = rect.cf:PointToWorldSpace(Vector3.new(lx, 0, lz))
		local hx, hz = rng:NextNumber(40, 140), rng:NextNumber(40, 140)
		local clear = Layout.regionAt(w.X, w.Z) == "Wasteland" and not nearWall(w.X, w.Z, math.max(hx, hz) + 30)
		for _, pool in p.pools do
			if Vector2.new(w.X - pool.c.X, w.Z - pool.c.Z).Magnitude < pool.r + math.max(hx, hz) + 30 then
				clear = false
			end
		end
		if clear then
			GroundBuilder.terrace(fm, w.X, w.Z, hx, hz, base, rng:NextNumber(2.5, 4.5), rng:NextInteger(1, 3), rng:NextNumber() < 0.5 and "WasteGround" or "WasteRubble", rng, 1)
			placed += 1
		end
	end
	-- rubble highlands, kept off the pools, the mounds and the walls
	local avoid = {}
	for _, pool in p.pools do
		table.insert(avoid, { c = pool.c, r = pool.r + 40 })
	end
	for _, heap in p.heaps do
		table.insert(avoid, { c = heap.c, r = heap.r + 20 })
	end
	for _, b in Layout.blocksOf("WastelandWall") do
		table.insert(avoid, { c = b.cf.Position, r = math.max(b.size.X, b.size.Z) / 2 + 40 })
	end
	highlands(fm, "Wasteland", Wasteland.HIGHLAND_COUNT, base, 70, 170, 18, 42, { "WasteRubble", "WasteGround" }, rng, avoid)
	-- sludge basins: a dry shelf, then the wet bed (layer 3, carve)
	for _, pool in p.pools do
		GroundBuilder.basin(fm, pool.c.X, pool.c.Z, pool.r, pool.r * rng:NextNumber(0.7, 1), base - 1.5, base - pool.depth, Wasteland.POOL_LEVEL, "Sludge", "Sludge", rng)
	end
end

-- Blocky asphalt patches (buried road surfaces), sampled per 64-stud block.
function Wasteland.patch(ctx: any, x: number, z: number, top: number, key: string): string
	if key == "WasteGround" and math.noise(math.floor(x / 64) * 0.57, math.floor(z / 64) * 0.57, 6.6) > 0.38 then
		return "WasteAsphalt"
	end
	return key
end

-- ─── populate ─────────────────────────────────────────────────────────────────
-- The walls get dressed (scrap plating, pipes, floodlights), the plain fills with junk from
-- the audited kit props, power lines stagger across it, sludge basins breathe toxic smog, and
-- scavengers camp between the mounds. Everything new is Parts or audited props.

Wasteland.JUNK = 700
Wasteland.CAMPS = 7
Wasteland.POWER_LINES = 4
local JUNK = { "TyreStack1", "TyreStack2", "ScrapPanelPile", "WallHeap1", "WallHeap2", "TrashBags", "WashingMachine", "ShoppingCart", "BusWreck", "BentSign", "BarrelRusty", "SackPile", "Sofa", "Antenna" }
local SCRAP = { Color3.fromRGB(122, 72, 50), Color3.fromRGB(96, 92, 86), Color3.fromRGB(78, 104, 100), Color3.fromRGB(138, 110, 90), Color3.fromRGB(110, 84, 64) }

function Wasteland.populate(ctx: any, folder: Folder)
	local Kit = require(script.Parent.Parent.Kit) :: any
	local PlacementUtil = require(script.Parent.Parent.PlacementUtil) :: any
	local Decor = require(script.Parent.Parent.Decor) :: any
	local PartKit = require(script.Parent.Parent.PartKit) :: any
	local AssetIds = require(script.Parent.Parent.Data.AssetIds) :: any
	local data = Layout.dataFolder()
	local p = Wasteland.plan(ctx)
	local rng = Random.new(Config.SEED + 24)
	local function sub(name: string): Folder
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
		return f
	end
	local fWalls, fJunk, fPower, fGas, fCamps = sub("WallDressing"), sub("Junk"), sub("PowerLines"), sub("ToxicGas"), sub("Camps")
	local spacing = PlacementUtil.spacing()

	-- ── walls: raycast each face of each wall block, plate it, run pipes, hang floodlights ──
	data:SetAttribute("Progress", "wasteland: walls")
	local wallParams = RaycastParams.new()
	wallParams.FilterType = Enum.RaycastFilterType.Include
	wallParams.FilterDescendantsInstances = { GroundBuilder.folder():FindFirstChild("Chunks") :: Instance }
	for _, b in Layout.blocksOf("WastelandWall") do
		local cx, cz, _, half, top = GroundBuilder.footprint(b.cf, b.size)
		local base = Wasteland.BASE_Y
		for _, dir in { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis } do
			local side = Vector3.new(dir.Z, 0, -dir.X)
			local reach = math.max(half.X, half.Y) + 60
			local layer = 0
			for k = 1, 7 do
				local along = rng:NextNumber(-0.8, 0.8) * math.max(half.X, half.Y)
				local y = base + rng:NextNumber(8, math.min(160, (top - base) * 0.6))
				local from = Vector3.new(cx, y, cz) + dir * reach + side * along
				local hit = workspace:Raycast(from, -dir * reach, wallParams)
				if hit and math.abs(hit.Normal:Dot(dir)) > 0.99 then
					layer += 1
					local n = hit.Normal
					local w, h = rng:NextNumber(10, 28), rng:NextNumber(8, 22)
					-- plate: front 0.25 + 0.12 per plate out from the wall, back 0.03 per plate into it,
					-- so neither the fronts nor the hidden backs of overlapping plates share a plane
					local front, back = 0.25 + 0.12 * layer, -0.03 * layer
					local pos = hit.Position + n * ((front + back) / 2)
					PartKit.part(fWalls, CFrame.lookAt(pos, pos + n), CFrame.new(), Vector3.new(w, h, front - back), Enum.Material.CorrodedMetal, SCRAP[rng:NextInteger(1, #SCRAP)], "Plating", { collide = false, shadow = false })
					if k % 3 == 0 then
						-- a pipe down the face (cylinder along Y, 1.5 off the wall), and a floodlight
						local pipeTop = hit.Position + n * 2.2
						local len = pipeTop.Y - base + 0.5
						PartKit.part(fWalls, CFrame.new(pipeTop - Vector3.new(0, len / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2), CFrame.new(), Vector3.new(len, 1.6 + 0.1 * layer, 1.6 + 0.1 * layer), Enum.Material.Metal, Color3.fromRGB(84, 80, 74), "Pipe", { shape = Enum.PartType.Cylinder, shadow = false })
						local lampPos = hit.Position + n * 1.4 + Vector3.new(0, h / 2 + 3, 0)
						local lamp = PartKit.part(fWalls, CFrame.lookAt(lampPos, lampPos + n - Vector3.new(0, 0.6, 0)), CFrame.new(), Vector3.new(2.2, 1.4, 2.6), Enum.Material.Neon, Color3.fromRGB(255, 214, 160), "Floodlight", { collide = false, shadow = false })
						local spot = Instance.new("SpotLight")
						spot.Face = Enum.NormalId.Front
						spot.Angle = 70
						spot.Range = 60
						spot.Brightness = 2
						spot.Color = Color3.fromRGB(255, 220, 170)
						spot.Shadows = k % 6 == 0
						spot.Parent = lamp
					end
				end
			end
		end
		task.wait()
	end

	-- ── junk across the plain and up the mounds ──
	data:SetAttribute("Progress", "wasteland: junk")
	local junk = {}
	for _, n in JUNK do
		if AssetIds[n] then
			table.insert(junk, n)
		end
	end
	Kit.preload(junk)
	local rects = Layout.rectsOf("Wasteland")
	for i = 1, Wasteland.JUNK do
		local rect = rects[rng:NextInteger(1, #rects)]
		local lp = Vector3.new(rng:NextNumber(-0.48, 0.48) * rect.size.X, 0, rng:NextNumber(-0.48, 0.48) * rect.size.Z)
		local w = rect.cf:PointToWorldSpace(lp)
		if Layout.regionAt(w.X, w.Z) == "Wasteland" then
			local prop = Kit.clone(junk[rng:NextInteger(1, #junk)])
			Kit.vary(prop, rng, 0.12)
			local _, size = prop:GetBoundingBox()
			if not PlacementUtil.scatterOne(spacing, prop, w.X, w.Z, math.max(size.X, size.Z) / 2 + 1, { yaw = rng:NextNumber(0, 2 * math.pi), embed = 0.4, maxStep = 0.5, parent = fJunk }) then
				prop:Destroy()
			end
		end
		if i % 60 == 0 then
			task.wait()
		end
	end

	-- ── power lines: leaning poles every ~70 studs, cables pole to pole ──
	data:SetAttribute("Progress", "wasteland: power lines")
	local poles = {}
	for _, n in { "PowerPoleLean1", "PowerPoleLean2" } do
		if AssetIds[n] then
			table.insert(poles, n)
		end
	end
	Kit.preload(poles)
	for _ = 1, #poles > 0 and Wasteland.POWER_LINES or 0 do
		local rect = rects[rng:NextInteger(1, #rects)]
		local a = rect.cf:PointToWorldSpace(Vector3.new(-0.45 * rect.size.X, 0, rng:NextNumber(-0.4, 0.4) * rect.size.Z))
		local b = rect.cf:PointToWorldSpace(Vector3.new(0.45 * rect.size.X, 0, rng:NextNumber(-0.4, 0.4) * rect.size.Z))
		local prevTop: Vector3? = nil
		local steps = math.floor((b - a).Magnitude / 70)
		for k = 0, steps do
			local pos = a:Lerp(b, k / math.max(1, steps))
			local pole = Kit.clone(poles[rng:NextInteger(1, #poles)])
			if PlacementUtil.scatterOne(spacing, pole, pos.X, pos.Z, 3, { yaw = math.atan2(b.X - a.X, b.Z - a.Z) + rng:NextNumber(-0.1, 0.1), embed = 0.5, parent = fPower }) then
				local cf, size = pole:GetBoundingBox()
				local topPt = Vector3.new(cf.X, cf.Y + size.Y / 2 - 1.5, cf.Z)
				if prevTop then
					Decor.cable(fPower, prevTop, topPt, (topPt - prevTop).Magnitude * 0.07, nil, 0.18)
				end
				prevTop = topPt
			else
				pole:Destroy()
			end
		end
		task.wait()
	end

	-- ── toxic smog rising off the sludge ──
	local smog = Decor.image("fx_smog")
	for _, pool in p.pools do
		for _ = 1, 2 do
			local x = pool.c.X + rng:NextNumber(-0.4, 0.4) * pool.r
			local z = pool.c.Z + rng:NextNumber(-0.4, 0.4) * pool.r
			local vent = Instance.new("Part")
			vent.Name = "GasVent"
			vent.Anchored = true
			vent.CanCollide = false
			vent.CanQuery = false
			vent.CanTouch = false
			vent.Transparency = 1
			vent.Size = Vector3.new(pool.r * 0.8, 1, pool.r * 0.8)
			vent.CFrame = CFrame.new(x, Wasteland.POOL_LEVEL + 1, z)
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = smog or "rbxasset://textures/particles/smoke_main.dds"
			pe.Color = ColorSequence.new(Color3.fromRGB(150, 176, 96), Color3.fromRGB(96, 110, 80))
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.6), NumberSequenceKeypoint.new(1, 1) })
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 8), NumberSequenceKeypoint.new(1, 30) })
			pe.Lifetime = NumberRange.new(8, 14)
			pe.Rate = 3
			pe.Speed = NumberRange.new(1, 3)
			pe.SpreadAngle = Vector2.new(20, 20)
			pe.Rotation = NumberRange.new(0, 360)
			pe.RotSpeed = NumberRange.new(-8, 8)
			pe.LightInfluence = 0.6
			pe.Parent = vent
			vent.Parent = fGas
		end
	end

	-- ── scavenger camps: tents around a fire ──
	data:SetAttribute("Progress", "wasteland: camps")
	-- up to ten tries per camp: level, dry spots are rarer than open ones
	local camps = 0
	for _ = 1, Wasteland.CAMPS * 10 do
		if camps >= Wasteland.CAMPS then
			break
		end
		local rect = rects[rng:NextInteger(1, #rects)]
		local w = rect.cf:PointToWorldSpace(Vector3.new(rng:NextNumber(-0.4, 0.4) * rect.size.X, 0, rng:NextNumber(-0.4, 0.4) * rect.size.Z))
		local g = PlacementUtil.ground(w.X, w.Z)
		-- the whole camp (tents reach ~20 from the fire) must stand on one dry, level ledge:
		-- no tent floating over a drop, buried in a heap or standing in sludge
		local level = g ~= nil
		if g then
			for _, rr in { 8, 14, 20 } do
				for k = 0, 11 do
					local a = k / 12 * 2 * math.pi
					local qx, qz = w.X + math.cos(a) * rr, w.Z + math.sin(a) * rr
					local q = PlacementUtil.ground(qx, qz)
					if not q or math.abs(q.position.Y - g.position.Y) > 0.5 or PlacementUtil.isWater(qx, qz) then
						level = false
						break
					end
				end
				if not level then
					break
				end
			end
		end
		if g and level and Layout.regionAt(w.X, w.Z) == "Wasteland" and PlacementUtil.isFree(spacing, w.X, w.Z, 30) and not PlacementUtil.isWater(w.X, w.Z) then
			PlacementUtil.reserve(spacing, w.X, w.Z, 30)
			local camp = Instance.new("Model")
			camp.Name = "ScavCamp"
			local origin = CFrame.new(w.X, g.position.Y, w.Z)
			-- fire: a ring of stones, a glowing core, a warm light
			for k = 0, 6 do
				local a = k / 7 * 2 * math.pi
				PartKit.part(camp, origin, CFrame.new(math.cos(a) * 2.6, 0.45 + 0.03 * k, math.sin(a) * 2.6) * CFrame.Angles(0, a, 0), Vector3.new(1.4, 0.9 + 0.06 * k, 1.1), Enum.Material.Slate, Color3.fromRGB(86, 82, 78), "Stone", { shadow = false })
			end
			local core = PartKit.part(camp, origin, CFrame.new(0, 0.7, 0) * CFrame.Angles(0, math.rad(17), 0), Vector3.new(1.8, 1.4, 1.8), Enum.Material.Neon, Color3.fromRGB(255, 140, 60), "FireCore", { collide = false, shadow = false })
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 132, 70)
			light.Brightness = 2
			light.Range = 27
			light.Shadows = true -- hero light (the reference's torch recipe)
			light.Parent = core
			Decor.glow(core, Color3.fromRGB(255, 150, 80), 5)
			-- tents: four posts and a sloped tarp each, around the fire
			for t = 1, rng:NextInteger(2, 4) do
				local a = (t + rng:NextNumber(-0.2, 0.2)) / 4 * 2 * math.pi
				local tcf = origin * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -14) * CFrame.Angles(0, math.rad(rng:NextNumber(-5, 5)), 0)
				local tw, td, th = rng:NextNumber(8, 12), rng:NextNumber(7, 10), 7.5
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local ph = sz < 0 and th + 1 or th
						PartKit.part(camp, tcf, CFrame.new(sx * (tw / 2 - 0.3), ph / 2 - 0.25, sz * (td / 2 - 0.3)), Vector3.new(0.45 + 0.02 * t, ph + 0.5, 0.45 + 0.02 * t), Enum.Material.WoodPlanks, Color3.fromRGB(84, 66, 52), "Pole")
					end
				end
				local slope = math.atan2(1, td)
				PartKit.part(camp, tcf, CFrame.new(0, th + 0.6 + 0.01 * t, 0) * CFrame.Angles(slope, 0, 0), Vector3.new(tw + 1.4, 0.2, td / math.cos(slope) + 1.2), Enum.Material.Fabric, SCRAP[rng:NextInteger(1, #SCRAP)], "Tarp")
			end
			camp.Parent = fCamps
			camps += 1
		end
	end
	data:SetAttribute("Progress", "wasteland: done")
	print(string.format("[MapGen] Wasteland: %d junk props, %d wall dressings, %d camps", #fJunk:GetChildren(), #fWalls:GetChildren(), camps))
end

function Wasteland.reset()
	plan = nil
end

return Wasteland
