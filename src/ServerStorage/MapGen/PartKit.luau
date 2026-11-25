--!strict
--[[
	MapGen.PartKit - structures built from plain Parts, the way the reference world builds its
	village (plaster walls, dark timber posts and floor beams, plank or sheet roofs, warm
	lanterns), dressed as TRASH's scrap town: patchwork wall panels, rusted sheet roofs, shop
	signs, awnings.

	Why Parts instead of the Blender kit meshes: the kit meshes Z-fight internally
	(tools/zfight/mesh_report.md) and cannot be re-uploaded while the account is moderated.
	Parts need no upload, and every face position is under our control.

	Z-fighting discipline (MapGen.ZFight checks it after every build):
	  * every decorative layer has its own depth off the wall face: patches +0.08 per stacking
	    index (max 3), braces +0.28, posts +0.2, window/door boards +0.3, sills +0.5,
	    floor bands +0.3; roof patches +0.12 per index off the roof plate;
	  * pieces in one layer only touch edge to edge (walls are split into strips around
	    openings, never overlapped);
	  * stacked pieces sit flush (touching faces point at each other, so both are hidden);
	  * posts run 0.25 past their storey into the band/roof above and the base below, so their
	    end faces are buried, never level with a wall's end face.

	Local space for every builder: origin at the bottom centre (ground level), front = -Z (a
	CFrame.lookAt toward the street), so `cf` is simply the lot's CFrame.
]]

local Config = require(script.Parent.Config)
local Decor = require(script.Parent.Decor)

local PartKit = {}

local H = Config.HUMAN
PartKit.WALL = 0.8 -- wall thickness
PartKit.FOUNDATION = 1.6 -- height of the stone base (0.6 of it below ground)
PartKit.BAND = 0.8 -- floor band between storeys

-- ─── palette (reference-muted) ────────────────────────────────────────────────

local C = Color3.fromRGB
PartKit.PALETTE = {
	plaster = { C(196, 186, 168), C(182, 172, 152), C(166, 156, 140), C(176, 164, 136) },
	timber = { C(74, 58, 48), C(62, 50, 44), C(84, 66, 52) },
	brick = { C(128, 84, 68), C(116, 78, 64), C(138, 96, 74) },
	scrap = { C(122, 72, 50), C(78, 104, 100), C(150, 128, 96), C(110, 108, 104), C(156, 128, 64), C(96, 84, 110), C(138, 110, 90) },
	roof = { C(102, 62, 46), C(88, 70, 58), C(70, 68, 70), C(94, 84, 70), C(116, 80, 58) },
	stone = { C(98, 92, 86), C(86, 80, 76), C(110, 102, 92) },
	glass = C(42, 48, 52),
	lit = C(255, 190, 120),
	cloth = { C(150, 72, 54), C(196, 158, 72), C(72, 96, 120), C(90, 112, 76), C(176, 160, 128), C(120, 82, 110) },
}

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- ─── part helper ──────────────────────────────────────────────────────────────

export type PartOpts = { collide: boolean?, shadow: boolean?, shape: Enum.PartType?, class: string?, transparency: number? }

-- One anchored part at local CFrame `lcf` (relative to `cf`). Decorative pieces pass
-- collide = false so they cost no physics and are invisible to queries.
function PartKit.part(parent: Instance, cf: CFrame, lcf: CFrame, size: Vector3, material: Enum.Material, color: Color3, name: string?, opts: PartOpts?): BasePart
	local o = opts or {}
	local p: BasePart
	if o.class == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		if o.shape then
			part.Shape = o.shape
		end
		p = part
	end
	p.Name = name or "Part"
	p.Anchored = true
	p.CanTouch = false
	if o.collide == false then
		p.CanCollide = false
		p.CanQuery = false
	end
	if o.shadow == false then
		p.CastShadow = false
	end
	if o.transparency then
		p.Transparency = o.transparency
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material
	p.Color = color
	p.Size = size
	p.CFrame = cf * lcf
	p.Parent = parent
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Stacked decorations (patches) of layer k get extents on a 0.5 grid and centres on a 0.25
-- grid shifted by 0.05*k, so the edges of two different layers can never line up.
local function snap(v: number, k: number): number
	return math.floor(v * 4 + 0.5) / 4 + 0.05 * k
end
local function snapSize(v: number): number
	return math.max(0.5, math.floor(v * 2 + 0.5) / 2)
end

-- ─── walls with openings ──────────────────────────────────────────────────────

export type Opening = { a: number, b: number, y0: number, y1: number, kind: string }

-- A wall in the local frame `wf` (wall runs along wf's X from u0 to u1, its centre plane at
-- wf's Z = 0, outer face toward wf's -Z), from height y0 to y1. Openings are cut by splitting
-- the wall into non-overlapping strips, sills and headers.
function PartKit.wall(parent: Instance, wf: CFrame, u0: number, u1: number, y0: number, y1: number, openings: { Opening }, material: Enum.Material, color: Color3)
	local T = PartKit.WALL
	table.sort(openings, function(a, b)
		return a.a < b.a
	end)
	local u = u0
	local function piece(a: number, b: number, lo: number, hi: number)
		if b - a > 0.01 and hi - lo > 0.01 then
			PartKit.part(parent, wf, at((a + b) / 2, (lo + hi) / 2, 0), Vector3.new(b - a, hi - lo, T), material, color, "Wall")
		end
	end
	for _, o in openings do
		piece(u, o.a, y0, y1)
		piece(o.a, o.b, y0, o.y0) -- sill
		piece(o.a, o.b, o.y1, y1) -- header
		u = o.b
	end
	piece(u, u1, y0, y1)
end

-- Frame boards, pane or door leaf for one opening (on the outer face, -Z of wf). `plain`
-- windows (back and side walls) get only their pane: part budget goes to the street fronts.
local function dressOpening(parent: Instance, wf: CFrame, o: Opening, trim: Color3, rng: Random, lit: boolean, plain: boolean?)
	local T = PartKit.WALL
	local face = -T / 2 -- outer face plane
	local w, h = o.b - o.a, o.y1 - o.y0
	local cx = (o.a + o.b) / 2
	local deco = { collide = false, shadow = false }
	if not plain then
		-- head board across the top; windows also get a deeper sill (doors get jambs)
		PartKit.part(parent, wf, at(cx, o.y1 + 0.25, face - 0.15), Vector3.new(w + 0.8, 0.5, 0.3), Enum.Material.WoodPlanks, trim, "Head", deco)
		if o.kind == "door" then
			PartKit.part(parent, wf, at(o.a - 0.2, (o.y0 + o.y1) / 2, face - 0.15), Vector3.new(0.4, h, 0.3), Enum.Material.WoodPlanks, trim, "Jamb", deco)
			PartKit.part(parent, wf, at(o.b + 0.2, (o.y0 + o.y1) / 2, face - 0.15), Vector3.new(0.4, h, 0.3), Enum.Material.WoodPlanks, trim, "Jamb", deco)
		end
	end
	if o.kind == "window" then
		if not plain then
			PartKit.part(parent, wf, at(cx, o.y0 - 0.2, face - 0.25), Vector3.new(w + 1, 0.4, 0.5), Enum.Material.WoodPlanks, trim, "Sill", deco)
		end
		-- pane in the wall's middle plane (faces +-0.1, the wall's are +-0.4)
		local pane = PartKit.part(parent, wf, at(cx, (o.y0 + o.y1) / 2, 0), Vector3.new(w, h, 0.2), lit and Enum.Material.Neon or Enum.Material.Glass, lit and PartKit.PALETTE.lit or PartKit.PALETTE.glass, "Pane", { shadow = false })
		if lit then
			pane.Transparency = 0.15
		else
			pane.Reflectance = 0.15
		end
		if not plain and rng:NextNumber() < 0.3 then
			-- one shutter swung open against the wall (rotated: never parallel to anything)
			local side = rng:NextNumber() < 0.5 and -1 or 1
			local hinge = side < 0 and o.a - 0.4 or o.b + 0.4
			local ang = side * math.rad(rng:NextNumber(110, 150))
			local scf = wf * at(hinge, (o.y0 + o.y1) / 2, face - 0.35) * CFrame.Angles(0, ang, 0)
			-- 0.4 shorter than the opening so its ends are never level with the jambs'
			PartKit.part(parent, scf, at(side * -w / 4, 0, 0), Vector3.new(w / 2, h - 0.4, 0.2), Enum.Material.WoodPlanks, trim, "Shutter", deco)
		end
	elseif o.kind == "door" then
		-- door leaf standing ajar inward from its hinge (walk-in, never coplanar with the wall)
		-- 60-80 degrees: never square to the jamb, so the leaf never lies flush against it
		-- (negative yaw: the leaf's +X turns toward +Z, the inside; positive would swing it out)
		local leaf = wf * at(o.a + 0.1, (o.y0 + o.y1) / 2, 0) * CFrame.Angles(0, -math.rad(rng:NextNumber(60, 80)), 0)
		PartKit.part(parent, leaf, at((w - 0.2) / 2, 0, 0), Vector3.new(w - 0.2, h - 0.1, 0.3), Enum.Material.WoodPlanks, pick(rng, PartKit.PALETTE.timber), "Door", { shadow = false })
	end
end

-- Openings along a wall of length L: an optional door, then windows spread over what is left.
local function openingsFor(rng: Random, L: number, y0: number, door: boolean, shopFront: boolean, windowEvery: number): { Opening }
	local out: { Opening } = {}
	local margin = 2.2
	if shopFront then
		local w = math.max(H.DOOR_W, L - 6)
		table.insert(out, { a = -w / 2, b = w / 2, y0 = y0, y1 = y0 + H.DOOR_H + 0.5, kind = "shop" })
		return out
	end
	local doorA, doorB = math.huge, -math.huge
	if door then
		local c = rng:NextNumber(-L / 2 + margin + H.DOOR_W / 2, L / 2 - margin - H.DOOR_W / 2)
		doorA, doorB = c - H.DOOR_W / 2, c + H.DOOR_W / 2
		table.insert(out, { a = doorA, b = doorB, y0 = y0, y1 = y0 + H.DOOR_H, kind = "door" })
	end
	local n = math.max(0, math.floor(L / windowEvery))
	local ww, wh, sill = 3.6, 4.6, 4.2
	for i = 1, n do
		local c = -L / 2 + L * (i - 0.5) / n
		local a, b = c - ww / 2, c + ww / 2
		local clear = a > -L / 2 + margin and b < L / 2 - margin and (b < doorA - 1.6 or a > doorB + 1.6)
		if clear then
			table.insert(out, { a = a, b = b, y0 = y0 + sill, y1 = y0 + sill + wh, kind = "window" })
		end
	end
	return out
end

-- Scrap patches on the solid parts of a wall: up to 3, each at its own depth.
local function patches(parent: Instance, wf: CFrame, L: number, y0: number, y1: number, openings: { Opening }, rng: Random, count: number)
	local face = -PartKit.WALL / 2
	local placed = 0
	for _ = 1, 12 do
		if placed >= count then
			break
		end
		local k = placed + 1
		local w, h = snapSize(rng:NextNumber(2.5, 5.5)), snapSize(rng:NextNumber(2.5, 6))
		local c = snap(rng:NextNumber(-L / 2 + 1.7 + w / 2, L / 2 - 1.7 - w / 2), k)
		local yc = snap(rng:NextNumber(y0 + h / 2 + 0.4, math.max(y0 + h / 2 + 0.4, y1 - h / 2 - 0.4)), k)
		local hit = false
		for _, o in openings do
			if c + w / 2 > o.a - 0.9 and c - w / 2 < o.b + 0.9 and yc + h / 2 > o.y0 - 0.9 and yc - h / 2 < o.y1 + 0.9 then
				hit = true
				break
			end
			-- an edge level with a strip boundary (opening side) would share its plane
			for _, e in { c - w / 2, c + w / 2 } do
				if math.abs(e - o.a) < 0.15 or math.abs(e - o.b) < 0.15 then
					hit = true
				end
			end
		end
		if not hit and L > w + 3.2 then
			placed += 1
			-- front 0.08 per index off the wall, back 0.03 per index inside it: neither the
			-- fronts nor the hidden backs of stacked patches ever share a plane
			local front, back = face - 0.08 * placed, face + 0.03 * placed
			PartKit.part(parent, wf, at(c, yc, (front + back) / 2), Vector3.new(w, h, back - front), pick(rng, { Enum.Material.CorrodedMetal, Enum.Material.Metal, Enum.Material.WoodPlanks, Enum.Material.DiamondPlate }), pick(rng, PartKit.PALETTE.scrap), "Patch", { collide = false, shadow = false })
		end
	end
end

-- ─── roofs ────────────────────────────────────────────────────────────────────

-- Gable roof over a W x D footprint in frame rf (ridge along rf's X), eaves at height ye.
-- Plates lie on the wall tops; gable triangles are WedgeParts flush under the plates.
local function gableRoof(parent: Instance, rf: CFrame, W: number, D: number, ye: number, pitch: number, wallMat: Enum.Material, wallColor: Color3, roofMat: Enum.Material, roofColor: Color3, rng: Random)
	local T = PartKit.WALL
	local over = 1.6
	local t = 0.6
	local tanP = math.tan(pitch)
	local rise = (D / 2) * tanP
	local run = D / 2 + over
	local L = run / math.cos(pitch)
	for _, side in { -1, 1 } do
		-- plate underside passes through the wall's outer top edge (z = side*D/2, y = ye)
		local zMid = side * (D / 2 + over - run / 2)
		local yBottom = ye + (D / 2 - math.abs(zMid)) * tanP
		local rot = CFrame.Angles(side * pitch, 0, 0)
		local normal = rot.UpVector
		local centre = Vector3.new(0, yBottom, zMid) + normal * (t / 2)
		local plate = CFrame.new(centre) * rot
		PartKit.part(parent, rf, plate, Vector3.new(W + 2 * over, t, L), roofMat, roofColor, "Roof")
		-- patchwork on the roof: each patch one step further off the plate
		for k = 1, rng:NextInteger(0, 1) do
			local pw, pl = snapSize(rng:NextNumber(3, 7)), snapSize(rng:NextNumber(3, math.max(3.5, L * 0.6)))
			-- top 0.12 per index above the plate, bottom 0.04 per index sunk into it
			local top, bottom = t / 2 + 0.12 * k, t / 2 - 0.04 * k
			local px = snap(rng:NextNumber(-W / 2 + pw / 2, W / 2 - pw / 2), k)
			local pz = snap(rng:NextNumber(math.min(0, -L / 2 + pl / 2 + 0.5), math.max(0, L / 2 - pl / 2 - 0.5)), k)
			local pc = plate * at(px, (top + bottom) / 2, pz)
			PartKit.part(parent, rf, pc, Vector3.new(pw, top - bottom, pl), Enum.Material.CorrodedMetal, pick(rng, PartKit.PALETTE.scrap), "RoofPatch", { collide = false, shadow = false })
		end
	end
	-- ridge cap: a beam turned 45 degrees (pitch is kept away from 45, so never parallel to a plate)
	PartKit.part(parent, rf, at(0, ye + rise + t / math.cos(pitch) - 0.1, 0) * CFrame.Angles(math.rad(45), 0, 0), Vector3.new(W + 2 * over + 0.4, 0.9, 0.9), Enum.Material.WoodPlanks, pick(rng, PartKit.PALETTE.timber), "Ridge")
	-- gable triangles at both ends (x = +-W/2), two wedges each; their slope sits flush under
	-- the plates (opposite-facing, hidden)
	for _, ex in { -1, 1 } do
		local x = ex * (W / 2 - T / 2)
		for _, side in { -1, 1 } do
			local lcf = at(x, ye + rise / 2, side * D / 4) * CFrame.Angles(0, side > 0 and math.pi or 0, 0)
			PartKit.part(parent, rf, lcf, Vector3.new(T, rise, D / 2), wallMat, wallColor, "Gable", { class = "Wedge" })
		end
	end
end

-- ─── house ────────────────────────────────────────────────────────────────────

export type HouseSpec = {
	w: number,
	d: number,
	storeys: number,
	style: string?, -- "plaster" | "timber" | "brick" | "scrap"
	shop: boolean?,
	sign: string?, -- shop sign text
	ridgeAlongDepth: boolean?, -- gables face the street (reference village look)
	lantern: boolean?,
	interior: boolean?, -- furniture and maybe a ceiling lamp on the ground floor (default true)
	stairs: boolean?, -- a flight to every upper floor (default true)
}

PartKit.STAIR_RISER = 0.95 -- max riser (walkable for R6)
PartKit.STAIR_TREAD = 1.25
PartKit.STAIR_TREAD_MIN = 1 -- shortest tread a shallow house may use (still walkable)
PartKit.STAIR_W = 4
PartKit.STAIR_CLEAR = 4 -- studs kept free behind the front wall (the door swings there)

-- Floor band with a stairwell hole: up to four pieces that only touch edge to edge.
function PartKit.bandWithHole(parent: Instance, cf: CFrame, w: number, d: number, y: number, hole: { x0: number, x1: number, z0: number, z1: number }?, material: Enum.Material, color: Color3)
	local B = PartKit.BAND
	local X0, X1, Z0, Z1 = -w / 2 - 0.3, w / 2 + 0.3, -d / 2 - 0.3, d / 2 + 0.3
	local function piece(a: number, b: number, c: number, e: number)
		if b - a > 0.01 and e - c > 0.01 then
			PartKit.part(parent, cf, at((a + b) / 2, y + B / 2, (c + e) / 2), Vector3.new(b - a, B, e - c), material, color, "Band")
		end
	end
	if not hole then
		piece(X0, X1, Z0, Z1)
		return
	end
	local h = hole :: { x0: number, x1: number, z0: number, z1: number }
	piece(X0, X1, Z0, h.z0) -- front strip
	piece(X0, X1, h.z1, Z1) -- back strip
	piece(X0, h.x0, h.z0, h.z1) -- beside the hole
	piece(h.x1, X1, h.z0, h.z1)
end

-- A straight flight against one side wall, from floor height fy up to the floor at ty. Steps
-- run toward the back (+Z); the last riser steps onto the floor above. Returns the hole the
-- floor above needs (headroom over every step higher than 6 studs below it).
function PartKit.flight(parent: Instance, cf: CFrame, w: number, d: number, side: number, fy: number, ty: number, material: Enum.Material, color: Color3): { x0: number, x1: number, z0: number, z1: number }?
	local T = PartKit.WALL
	local rise = ty - fy
	local n = math.ceil(rise / PartKit.STAIR_RISER)
	local zs = -d / 2 + T + PartKit.STAIR_CLEAR
	-- shorten the treads (down to STAIR_TREAD_MIN) when the full-length flight would not leave a
	-- landing, so shallower houses still get their stairs
	local zMax = d / 2 - T - 3
	local riser, tread = rise / n, math.min(PartKit.STAIR_TREAD, (zMax - zs) / (n - 1))
	if tread < PartKit.STAIR_TREAD_MIN then
		return nil -- too shallow for a flight plus a landing
	end
	local zEnd = zs + (n - 1) * tread
	-- 0.2 off the wall's inner face: the flight never shares a plane with the wall
	local xin = w / 2 - T - 0.2
	local xc = side * (xin - PartKit.STAIR_W / 2)
	for k = 1, n - 1 do
		local top = fy + riser * k
		PartKit.part(parent, cf, at(xc, (fy + top) / 2, zs + (k - 0.5) * tread), Vector3.new(PartKit.STAIR_W, top - fy, tread), material, color, "Step")
	end
	-- hole: from the first step that would hit a head (6 below the floor above) to the end
	local kHead = math.max(1, math.floor((ty - 6 - fy) / riser))
	local hx0, hx1 = side > 0 and xin - PartKit.STAIR_W - 0.3 or -(w / 2 - T), side > 0 and (w / 2 - T) or -(xin - PartKit.STAIR_W - 0.3)
	return { x0 = hx0, x1 = hx1, z0 = zs + (kHead - 1) * tread, z1 = zEnd }
end

local STYLES = { "plaster", "timber", "brick", "scrap" }

-- A house on the lot `cf` (bottom centre at ground level, front = -Z). Returns the Model.
function PartKit.house(parent: Instance, cf: CFrame, spec: HouseSpec, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = spec.shop and "Shop" or "House"
	local w, d = spec.w, spec.d
	local T = PartKit.WALL
	local style = spec.style or pick(rng, STYLES)
	local P = PartKit.PALETTE
	local wallMat, wallColor
	if style == "brick" then
		wallMat, wallColor = Enum.Material.Brick, pick(rng, P.brick)
	elseif style == "scrap" then
		wallMat, wallColor = Enum.Material.CorrodedMetal, pick(rng, P.scrap)
	else
		wallMat, wallColor = Enum.Material.Plaster, pick(rng, P.plaster)
	end
	local timber = pick(rng, P.timber)
	local trim = style == "scrap" and pick(rng, P.timber) or timber
	-- foundation: 0.6 below ground, top at +1.0 (half a stud proud of the plinth step)
	local base = PartKit.FOUNDATION - 0.6
	PartKit.part(model, cf, at(0, base - PartKit.FOUNDATION / 2, 0), Vector3.new(w + 1, PartKit.FOUNDATION, d + 1), Enum.Material.Slate, pick(rng, P.stone), "Foundation")
	-- ground floor slab inside the walls (top 0.4 above the foundation)
	PartKit.part(model, cf, at(0, base + 0.2, 0), Vector3.new(w - 2 * T, 0.4, d - 2 * T), Enum.Material.WoodPlanks, pick(rng, P.timber), "Floor")
	local y = base
	local storeyH = H.STOREY - 1.5 -- 13.5 ceiling per storey
	local interior = spec.interior ~= false
	local front = at(0, 0, -d / 2 + T / 2) -- wall frames: X along the wall, -Z = outside
	local back = at(0, 0, d / 2 - T / 2) * CFrame.Angles(0, math.pi, 0)
	-- a wall frame's -Z must point outside: +90 degrees turns -Z to -X (left), -90 to +X (right)
	local left = at(-w / 2 + T / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	local right = at(w / 2 - T / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	for s = 1, spec.storeys do
		local y0, y1 = y, y + storeyH
		local ground = s == 1
		local walls = {
			{ f = front, L = w, door = ground and not spec.shop, shop = ground and spec.shop == true, every = 8 },
			{ f = back, L = w, door = false, shop = false, every = 16 },
			-- side walls run between the front and back walls (they never overlap them)
			{ f = left, L = d - 2 * T, door = false, shop = false, every = 15 },
			{ f = right, L = d - 2 * T, door = false, shop = false, every = 15 },
		}
		for i, wl in walls do
			local wf = cf * wl.f
			local ops = openingsFor(rng, wl.L, y0, wl.door, wl.shop, wl.every)
			if i >= 3 and rng:NextNumber() < 0.35 then
				ops = {} -- blank side walls are common in a packed town
			end
			PartKit.wall(model, wf, -wl.L / 2, wl.L / 2, y0, y1, ops, wallMat, wallColor)
			for _, o in ops do
				if o.kind ~= "shop" then
					dressOpening(model, wf, o, trim, rng, not ground and rng:NextNumber() < 0.18, i > 1)
				end
			end
			if i == 1 and (style == "scrap" or rng:NextNumber() < 0.45) then
				patches(model, wf, wl.L, y0, y1, ops, rng, rng:NextInteger(1, 2))
			end
			if style == "timber" and #ops < 3 then
				-- a diagonal brace in a solid bay (rotated: never parallel to the wall)
				local bx = rng:NextNumber(-wl.L / 2 + 2.5, wl.L / 2 - 2.5)
				local clear = true
				for _, o in ops do
					if bx > o.a - 3 and bx < o.b + 3 then
						clear = false
					end
				end
				if clear then
					local len = storeyH * 1.05
					PartKit.part(model, wf, at(bx, (y0 + y1) / 2, -T / 2 - 0.14) * CFrame.Angles(0, 0, math.rad(rng:NextNumber() < 0.5 and 22 or -22)), Vector3.new(0.6, len, 0.28), Enum.Material.WoodPlanks, timber, "Brace", { collide = false, shadow = false })
				end
			end
		end
		-- corner posts: 0.2 proud of both walls, buried 0.25 into the band/foundation and the
		-- band/roof above
		if style ~= "scrap" then
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					PartKit.part(model, cf, at(sx * (w / 2 - T / 2), (y0 + y1) / 2, sz * (d / 2 - T / 2)), Vector3.new(T + 0.4, storeyH + 0.5, T + 0.4), Enum.Material.WoodPlanks, timber, "Post", { shadow = false })
				end
			end
		end
		y = y1
		if s < spec.storeys then
			-- stairs up from this floor (alternating sides so flights never stack), then the
			-- floor band (also the upper floor; 0.3 proud of the walls) with a stairwell hole
			local hole = nil
			if spec.stairs ~= false and not (spec.shop and s == 1) then
				local fy = s == 1 and base + 0.4 or y0
				hole = PartKit.flight(model, cf, w, d, s % 2 == 1 and 1 or -1, fy, y1 + PartKit.BAND, Enum.Material.WoodPlanks, pick(rng, P.timber))
			end
			PartKit.bandWithHole(model, cf, w, d, y, hole, Enum.Material.WoodPlanks, timber)
			y += PartKit.BAND
		end
	end
	-- shop front: awning, counter, sign
	if spec.shop then
		local awnY = base + H.DOOR_H + 1.6
		local depth = 5
		local pitch = math.rad(rng:NextNumber(14, 22))
		local acf = cf * at(0, awnY, -d / 2 - depth / 2 * math.cos(pitch)) * CFrame.Angles(-pitch, 0, 0)
		PartKit.part(model, acf, CFrame.new(), Vector3.new(w - 1, 0.2, depth), Enum.Material.Fabric, pick(rng, P.cloth), "Awning", { shadow = true })
		PartKit.part(model, cf, at(0, base + 1.9, -d / 2 + T + 1.5), Vector3.new(w - 2 * T - 2, 3, 1.4), Enum.Material.WoodPlanks, pick(rng, P.timber), "Counter")
		if spec.sign then
			local board = PartKit.part(model, cf, at(0, awnY + 2.2, -d / 2 - 0.5), Vector3.new(math.min(w - 2, 16), 2.6, 0.4), Enum.Material.WoodPlanks, pick(rng, P.timber), "SignBoard", { collide = false })
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.PixelsPerStud = 40
			gui.LightInfluence = 1
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Text = spec.sign :: string
			label.TextScaled = true
			label.Font = Enum.Font.Bangers
			label.TextColor3 = C(236, 222, 190)
			label.TextStrokeTransparency = 0.4
			label.Parent = gui
			gui.Parent = board
		end
	end
	-- ground floor furniture and a ceiling lamp (away from the stairs, which hug the +X wall)
	if interior and not spec.shop then
		local fy = base + 0.4
		local crateZ = d / 2 - PartKit.WALL - 2.2
		-- the table stays clear of the crate row along the back wall
		local tx, tz = -w / 4, math.min(rng:NextNumber(-d / 8, d / 6), crateZ - 4.4)
		PartKit.part(model, cf, at(tx, fy + 1.3, tz) * CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0), Vector3.new(4.2, 2.6, 2.6), Enum.Material.WoodPlanks, pick(rng, P.timber), "Table")
		for i = 1, d >= 22 and rng:NextInteger(1, 2) or 0 do
			local cs = 1.6 + 0.35 * i -- different heights: crate tops never level with each other
			-- 3.6 apart: even turned 20 degrees, two crates never touch (their bottoms share the floor plane)
			PartKit.part(model, cf, at(tx - 4.5 + 3.6 * i, fy + cs / 2, crateZ) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), 0), Vector3.new(cs, cs, cs), Enum.Material.WoodPlanks, pick(rng, P.timber), "Crate", { shadow = false })
		end
		if rng:NextNumber() < 0.35 then
			local lamp = PartKit.part(model, cf, at(tx, base + storeyH - 1.2, 0), Vector3.new(0.9, 0.9, 0.9), Enum.Material.Neon, C(255, 186, 120), "CeilingLamp", { collide = false, shadow = false })
			local light = Instance.new("PointLight")
			light.Color = C(255, 171, 103)
			light.Brightness = 0.9
			light.Range = 20
			light.Shadows = false
			light.Parent = lamp
		end
	end
	-- roof
	local roofMat = rng:NextNumber() < 0.55 and Enum.Material.CorrodedMetal or Enum.Material.WoodPlanks
	local pitch = math.rad(rng:NextNumber(26, 38))
	if spec.ridgeAlongDepth then
		gableRoof(model, cf * CFrame.Angles(0, math.pi / 2, 0), d, w, y, pitch, wallMat, wallColor, roofMat, pick(rng, P.roof), rng)
	else
		gableRoof(model, cf, w, d, y, pitch, wallMat, wallColor, roofMat, pick(rng, P.roof), rng)
	end
	-- lantern by the door (warm point light + glow halo, the reference's lantern recipe)
	if spec.lantern then
		local lx = rng:NextNumber(-w / 2 + 2, w / 2 - 2)
		local lantern = PartKit.part(model, cf, at(lx, base + H.DOOR_H + 0.4, -d / 2 - 0.9), Vector3.new(0.9, 1.2, 0.9), Enum.Material.Neon, C(255, 176, 104), "Lantern", { collide = false, shadow = false })
		local light = Instance.new("PointLight")
		light.Color = C(255, 171, 103)
		light.Brightness = 1.5
		light.Range = 24
		light.Shadows = false
		light.Parent = lantern
		Decor.glow(lantern, C(255, 170, 100), 3)
	end
	model.Parent = parent
	return model
end

-- ─── market stall ─────────────────────────────────────────────────────────────

function PartKit.stall(parent: Instance, cf: CFrame, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "Stall"
	local w, d, h = rng:NextNumber(7, 10), rng:NextNumber(5, 6.5), 8.5
	local timber = pick(rng, PartKit.PALETTE.timber)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			PartKit.part(m, cf, at(sx * (w / 2 - 0.3), (h + (sz < 0 and 0.8 or 0)) / 2 - 0.3, sz * (d / 2 - 0.3)), Vector3.new(0.5, h + (sz < 0 and 0.8 or 0) + 0.6, 0.5), Enum.Material.WoodPlanks, timber, "Post")
		end
	end
	-- counter (front) and cloth roof sloping to the back
	PartKit.part(m, cf, at(0, 1.6, -d / 2 + 0.9), Vector3.new(w - 1.2, 3.2, 1.2), Enum.Material.WoodPlanks, pick(rng, PartKit.PALETTE.timber), "Counter")
	-- underside runs from the front post tops (h + 0.8) to the back post tops (h)
	local slope = math.atan2(0.8, d)
	PartKit.part(m, cf, at(0, h + 0.4 + 0.1 / math.cos(slope), 0) * CFrame.Angles(slope, 0, 0), Vector3.new(w + 1.2, 0.2, d / math.cos(slope) + 1), Enum.Material.Fabric, pick(rng, PartKit.PALETTE.cloth), "Cloth")
	-- goods on the counter: small blocks, each a different height so tops never line up
	local n = rng:NextInteger(3, 6)
	local slot = (w - 2.4) / n
	for i = 1, n do
		local gx = -w / 2 + 1.2 + slot * (i - 0.5)
		local gh = 0.6 + 0.13 * i
		PartKit.part(m, cf, at(gx, 3.2 + gh / 2, -d / 2 + 0.9), Vector3.new(math.min(0.9, slot - 0.2), gh, 0.8), pick(rng, { Enum.Material.Fabric, Enum.Material.WoodPlanks, Enum.Material.SmoothPlastic }), pick(rng, PartKit.PALETTE.cloth), "Goods", { collide = false, shadow = false })
	end
	m.Parent = parent
	return m
end

-- ─── crater gate: two block towers and a lintel ───────────────────────────────

function PartKit.gate(parent: Instance, cf: CFrame, width: number, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "TownGate"
	local stone = pick(rng, PartKit.PALETTE.stone)
	local h = 34
	for _, sx in { -1, 1 } do
		local x = sx * (width / 2 + 6)
		-- stacked tower: three blocks, each a little narrower (tops never level with each other)
		PartKit.part(m, cf, at(x, h * 0.25, 0), Vector3.new(12, h * 0.5, 14), Enum.Material.Slate, stone, "Tower")
		PartKit.part(m, cf, at(x, h * 0.5 + h * 0.175, 0), Vector3.new(10.5, h * 0.35, 12.5), Enum.Material.Slate, stone, "Tower")
		PartKit.part(m, cf, at(x, h * 0.85 + h * 0.1, 0), Vector3.new(12.6, h * 0.2, 14.6), Enum.Material.WoodPlanks, pick(rng, PartKit.PALETTE.timber), "Crown")
		local lamp = PartKit.part(m, cf, at(x, h + 1.2, -7.6), Vector3.new(1.4, 1.8, 1.4), Enum.Material.Neon, C(255, 176, 104), "Lantern", { collide = false, shadow = false })
		local light = Instance.new("PointLight")
		light.Color = C(255, 132, 70)
		light.Brightness = 2
		light.Range = 27
		light.Shadows = true -- hero light source (the reference's torch recipe)
		light.Parent = lamp
		Decor.glow(lamp, C(255, 160, 90), 5)
	end
	-- lintel spans the opening, buried 1 stud into each tower top block
	PartKit.part(m, cf, at(0, h * 0.86, 0), Vector3.new(width + 14, 3.4, 9), Enum.Material.WoodPlanks, pick(rng, PartKit.PALETTE.timber), "Lintel")
	-- hanging cloth banners under the lintel, each at its own depth
	for i, sx in { -1, 1 } do
		PartKit.part(m, cf, at(sx * width / 4, h * 0.86 - 6.5, -4.7 - 0.1 * i), Vector3.new(6, 10, 0.2), Enum.Material.Fabric, pick(rng, PartKit.PALETTE.cloth), "Banner", { collide = false, shadow = false })
	end
	m.Parent = parent
	return m
end

-- ─── patchwork dome ───────────────────────────────────────────────────────────

-- A squat dome of mismatched panels (Patchwork Town): rings of tangent panels from
-- the floor to an open oculus. Neighbouring panels differ in yaw or pitch, so no two are ever
-- parallel. `openings` are angles (radians) where the lowest rings leave an arch for a street.
function PartKit.dome(parent: Instance, centre: Vector3, R: number, Hgt: number, oculus: number, openings: { number }, openW: number, openH: number, rng: Random, panel: Vector2?, ribs: number?): Model
	local m = Instance.new("Model")
	m.Name = "PatchworkDome"
	local panelW, panelH = (panel or Vector2.new(34, 30)).X, (panel or Vector2.new(34, 30)).Y
	local t = math.clamp(panelW / 28, 0.4, 1.2)
	-- walk the meridian of the ellipse x = R cos(phi), y = H sin(phi) in panel-height steps
	local phi = 0
	local ring = 0
	local mats = { Enum.Material.CorrodedMetal, Enum.Material.Fabric, Enum.Material.WoodPlanks, Enum.Material.Metal, Enum.Material.Concrete }
	while true do
		local r = R * math.cos(phi)
		if r < oculus then
			break
		end
		-- arc-length step along the meridian
		local dx, dy = -R * math.sin(phi), Hgt * math.cos(phi)
		local speed = math.sqrt(dx * dx + dy * dy)
		local dphi = panelH / speed
		local mid = phi + dphi / 2
		local rm, ym = R * math.cos(mid), Hgt * math.sin(mid)
		-- surface normal of the ellipse at mid (in the meridian plane)
		local nr, ny = math.cos(mid) / R, math.sin(mid) / Hgt
		local nl = math.sqrt(nr * nr + ny * ny)
		nr, ny = nr / nl, ny / nl
		local count = math.max(8, math.ceil(2 * math.pi * rm / panelW))
		local offset = rng:NextNumber(0, 2 * math.pi / count)
		ring += 1
		for k = 0, count - 1 do
			local a = offset + k / count * 2 * math.pi
			local skip = false
			if ym < openH then
				for _, g in openings do
					local da = math.abs((a - g + math.pi) % (2 * math.pi) - math.pi)
					if da * rm < openW / 2 + panelW / 2 then
						skip = true
					end
				end
			end
			if not skip then
				local outward = Vector3.new(math.cos(a) * nr, ny, math.sin(a) * nr)
				-- depth by ring parity (0.12) and panel parity (0.04): near the flat top, panels of
				-- neighbouring rings are almost coplanar where they overlap, so they never share a depth
				local pos = centre + Vector3.new(math.cos(a) * rm, ym, math.sin(a) * rm) + outward * (t / 2 + 0.12 * (ring % 2) + 0.04 * (k % 2))
				local tangentA = Vector3.new(-math.sin(a), 0, math.cos(a))
				-- alternate rings roll +-1.5 degrees in their own plane: a panel's side faces lie in
				-- its meridian plane, so panels of neighbouring rings at the same angle would share it
				local pcf = CFrame.fromMatrix(pos, tangentA, outward) * CFrame.Angles(0, math.rad(ring % 2 == 0 and 1.5 or -1.5), 0)
				local wk = 2 * math.pi * rm / count * 1.04
				PartKit.part(m, pcf, CFrame.new(), Vector3.new(wk, t, panelH * 1.04), pick(rng, mats), pick(rng, PartKit.PALETTE.scrap), "Panel", { shadow = true })
			end
		end
		phi += dphi
		if phi > math.pi / 2 then
			break
		end
	end
	-- meridian ribs: beams standing clear of the shell (never parallel-and-level with a panel)
	local ribCount = ribs or 16
	for i = 0, ribCount - 1 do
		local a = i / ribCount * 2 * math.pi
		local steps = 26
		for s = 0, steps - 1 do
			local p0, p1 = s / steps * math.acos(oculus / R), (s + 1) / steps * math.acos(oculus / R)
			local function pt(ph: number): Vector3
				local nr0, ny0 = math.cos(ph) / R, math.sin(ph) / Hgt
				local nl0 = math.sqrt(nr0 * nr0 + ny0 * ny0)
				local outward = Vector3.new(math.cos(a) * nr0 / nl0, ny0 / nl0, math.sin(a) * nr0 / nl0)
				return centre + Vector3.new(math.cos(a) * R * math.cos(ph), Hgt * math.sin(ph), math.sin(a) * R * math.cos(ph)) + outward * 3
			end
			local q0, q1 = pt(p0), pt(p1)
			local skip = false
			if q0.Y - centre.Y < openH + 4 then
				for _, g in openings do
					local da = math.abs((a - g + math.pi) % (2 * math.pi) - math.pi)
					if da * R < openW / 2 + 4 then
						skip = true
					end
				end
			end
			if not skip then
				-- segments meet end to end (no overlap) and alternate their section, so
				-- neighbouring segments never share a side plane
				local len = (q1 - q0).Magnitude
				-- (ribs i and i + 8 lie in one meridian plane: give them different sections too)
				local sec = (s % 2 == 0 and 2.2 or 1.9) + (i >= ribCount / 2 and 0.1 or 0)
				PartKit.part(m, CFrame.lookAt((q0 + q1) / 2, q1), CFrame.new(), Vector3.new(sec, sec, len), Enum.Material.Metal, C(70, 66, 62), "Rib", { shadow = false })
			end
		end
	end
	m.Parent = parent
	return m
end

return PartKit
