--!strict
--[[
	Structures.MendersBase - the Menders' headquarters: a long, symmetric, pale classical façade (rows
	of tall windows between pilasters, a strong cornice), a round central tower wrapped by a
	thick spiral band and capped with a small dome and spikes, and a plaza lined with ornate
	street lamps. Organised, clinical, fortified: a walled yard with a gate under a MENDERS
	sign, faction-yellow banners on the pilasters.

	Everything is plain Parts (MapGen.PartKit), following the reference world's construction
	and PartKit's Z-fighting discipline:
	  * depths off the façade: window sills +0.5, pilasters +0.6, banners +0.7..0.9, floor
	    bands +0.3, cornice +1.2 (parapet inset 0.3 from the cornice edge);
	  * the 16-sided tower is turned 11.25 degrees, so none of its panels is ever parallel to
	    a façade wall; helix segments alternate their section where they overlap.
	Enterable: the ground floor is an open arcade and lobby; the tower door opens into it; a
	stair climbs to the first floor through a stairwell in the floor band.

	Local space: origin = yard centre at yard level, front = -Z (faces the town).
]]

local PartKit = require(script.Parent.Parent.PartKit)
local GroundBuilder = require(script.Parent.Parent.GroundBuilder)
local Decor = require(script.Parent.Parent.Decor)

local MendersBase = {}

local C = Color3.fromRGB
local STONE = C(214, 206, 188) -- pale façade
local STONE_DARK = C(176, 166, 148) -- bands, cornice, plinth
local CREAM = C(232, 224, 204) -- tower helix
local YELLOW = C(214, 168, 52) -- faction colour
local IRON = C(46, 44, 42)
local LAMP = C(255, 196, 128)

local STOREYS = 5
local STOREY_H = 13.5
local BAND = PartKit.BAND
local T = PartKit.WALL
local BAY = 18 -- pilaster spacing
local DEPTH = 56 -- façade block depth
local TOWER_R = 20 -- tower circumradius
local TOWER_H = 150
local TOWER_SIDES = 16

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- ─── ornate street lamp (base, fluted post, cross arm, two lanterns) ───────────

local function lamp(parent: Instance, cf: CFrame)
	PartKit.part(parent, cf, at(0, 0.6, 0), Vector3.new(1.8, 1.2, 1.8), Enum.Material.Metal, IRON, "LampBase")
	PartKit.part(parent, cf, at(0, 1.2 + 5.5, 0), Vector3.new(0.6, 11, 0.6), Enum.Material.Metal, IRON, "LampPost")
	PartKit.part(parent, cf, at(0, 12.4, 0), Vector3.new(3.4, 0.4, 0.45), Enum.Material.Metal, IRON, "LampArm")
	for _, sx in { -1, 1 } do
		local l = PartKit.part(parent, cf, at(sx * 1.5, 11.6, 0), Vector3.new(0.9, 1.2, 0.9), Enum.Material.Neon, LAMP, "Lantern", { collide = false, shadow = false })
		if sx > 0 then
			local light = Instance.new("PointLight")
			light.Color = C(255, 171, 103)
			light.Brightness = 1.5
			light.Range = 24
			light.Shadows = false
			light.Parent = l
		end
		Decor.glow(l, C(255, 180, 110), 3)
	end
end

-- ─── façade block ──────────────────────────────────────────────────────────────

local function facade(m: Model, bcf: CFrame, W: number, rng: Random): number
	local D = DEPTH
	local base = PartKit.FOUNDATION - 0.6
	PartKit.part(m, bcf, at(0, base - PartKit.FOUNDATION / 2, 0), Vector3.new(W + 1, PartKit.FOUNDATION, D + 1), Enum.Material.Slate, STONE_DARK, "Plinth")
	PartKit.part(m, bcf, at(0, base + 0.2, 0), Vector3.new(W - 2 * T, 0.4, D - 2 * T), Enum.Material.Marble, C(196, 190, 178), "LobbyFloor")
	local front = at(0, 0, -D / 2 + T / 2)
	local back = at(0, 0, D / 2 - T / 2) * CFrame.Angles(0, math.pi, 0)
	local left = at(-W / 2 + T / 2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
	local right = at(W / 2 - T / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	local nb = math.floor(W / BAY)
	local y = base
	local towerGap = TOWER_R + 1 -- the tower stands in the middle of the front wall
	for s = 1, STOREYS do
		local y0, y1 = y, y + STOREY_H
		-- front: arcade on the ground floor, windows above, the tower gap at the centre
		local ops: { PartKit.Opening } = { { a = -towerGap, b = towerGap, y0 = y0, y1 = y1, kind = "gap" } }
		for k = 1, nb do
			local cx = -W / 2 + BAY * (k - 0.5)
			if math.abs(cx) > towerGap + 6 then
				if s == 1 then
					table.insert(ops, { a = cx - 4.5, b = cx + 4.5, y0 = y0, y1 = y0 + 11, kind = "arch" })
				else
					table.insert(ops, { a = cx - 2.3, b = cx + 2.3, y0 = y0 + 3, y1 = y0 + 11, kind = "window" })
				end
			end
		end
		local walls = {
			{ f = front, L = W, ops = ops },
			{ f = back, L = W, ops = {} },
			{ f = left, L = D - 2 * T, ops = {} },
			{ f = right, L = D - 2 * T, ops = {} },
		}
		-- back and sides: windows every other bay / twice per side
		for k = 1, nb, 2 do
			local cx = -W / 2 + BAY * (k - 0.5)
			table.insert(walls[2].ops, { a = cx - 2.3, b = cx + 2.3, y0 = y0 + 3, y1 = y0 + 11, kind = "window" })
		end
		for _, sx in { -1, 1 } do
			table.insert(walls[3].ops, { a = sx * 12 - 2.3, b = sx * 12 + 2.3, y0 = y0 + 3, y1 = y0 + 11, kind = "window" })
			table.insert(walls[4].ops, { a = sx * 12 - 2.3, b = sx * 12 + 2.3, y0 = y0 + 3, y1 = y0 + 11, kind = "window" })
		end
		for _, wl in walls do
			local wf = bcf * wl.f
			PartKit.wall(m, wf, -wl.L / 2, wl.L / 2, y0, y1, wl.ops, Enum.Material.Plaster, STONE)
			for _, o in wl.ops do
				if o.kind == "window" then
					local lit = rng:NextNumber() < 0.22
					local pane = PartKit.part(m, wf, at((o.a + o.b) / 2, (o.y0 + o.y1) / 2, 0), Vector3.new(o.b - o.a, o.y1 - o.y0, 0.2), lit and Enum.Material.Neon or Enum.Material.Glass, lit and PartKit.PALETTE.lit or PartKit.PALETTE.glass, "Pane", { shadow = false })
					pane.Transparency = lit and 0.15 or 0
					PartKit.part(m, wf, at((o.a + o.b) / 2, o.y0 - 0.2, -T / 2 - 0.25), Vector3.new(o.b - o.a + 1, 0.4, 0.5), Enum.Material.Marble, STONE_DARK, "Sill", { collide = false, shadow = false })
				end
			end
		end
		y = y1
		if s < STOREYS then
			local hole = nil
			if s == 1 then
				-- the lobby's grand stair up to the first floor, against the +X end wall
				hole = PartKit.flight(m, bcf, W, D, 1, base + 0.4, y1 + BAND, Enum.Material.Marble, C(196, 190, 178))
			end
			PartKit.bandWithHole(m, bcf, W, D, y, hole, Enum.Material.Slate, STONE_DARK)
			y += BAND
		end
	end
	local top = y
	-- pilasters on the upper storeys at every bay line (buried 0.25 into the band below and the
	-- cornice above; their backs 0.2 inside the wall)
	local p0 = base + STOREY_H + BAND - 0.25
	for k = 1, nb - 1 do
		local x = -W / 2 + BAY * k
		if math.abs(x) > towerGap + 2 then
			PartKit.part(m, bcf, at(x, (p0 + top + 0.25) / 2, -D / 2 - 0.2), Vector3.new(2.4, top + 0.25 - p0, 0.8), Enum.Material.Plaster, STONE_DARK, "Pilaster")
		end
	end
	-- cornice and parapet
	PartKit.part(m, bcf, at(0, top + 1, 0), Vector3.new(W + 2.4, 2, D + 2.4), Enum.Material.Slate, STONE_DARK, "Cornice")
	local px, pz = W / 2 + 1.2 - 0.3, D / 2 + 1.2 - 0.3 -- parapet outer faces, inset 0.3
	local ph, pt = 4, 1.2
	PartKit.part(m, bcf, at(0, top + 2 + ph / 2, -pz + pt / 2), Vector3.new(2 * px, ph, pt), Enum.Material.Plaster, STONE, "Parapet")
	PartKit.part(m, bcf, at(0, top + 2 + ph / 2, pz - pt / 2), Vector3.new(2 * px, ph, pt), Enum.Material.Plaster, STONE, "Parapet")
	for _, sx in { -1, 1 } do
		PartKit.part(m, bcf, at(sx * (px - pt / 2), top + 2 + ph / 2, 0), Vector3.new(pt, ph, 2 * pz - 2 * pt), Enum.Material.Plaster, STONE, "Parapet")
	end
	-- yellow banners hung on every third pilaster across the two middle storeys
	for k = 3, nb - 1, 3 do
		local x = -W / 2 + BAY * k
		if math.abs(x) > towerGap + 2 then
			local yb = base + 2 * (STOREY_H + BAND) + STOREY_H
			PartKit.part(m, bcf, at(x, yb, -D / 2 - 0.6 - 0.2), Vector3.new(3.4, 18, 0.2), Enum.Material.Fabric, YELLOW, "Banner", { collide = false, shadow = false })
		end
	end
	-- lobby lights
	for _, lx in { -W / 4, 0, W / 4 } do
		local l = PartKit.part(m, bcf, at(lx, base + STOREY_H - 1.4, 4), Vector3.new(1.2, 1.2, 1.2), Enum.Material.Neon, LAMP, "LobbyLamp", { collide = false, shadow = false })
		local light = Instance.new("PointLight")
		light.Color = C(255, 196, 140)
		light.Brightness = 1.2
		light.Range = 30
		light.Shadows = false
		light.Parent = l
	end
	return top
end

-- ─── the spiral tower ──────────────────────────────────────────────────────────

local function tower(m: Model, tcf: CFrame, rng: Random)
	local n = TOWER_SIDES
	local apothem = TOWER_R * math.cos(math.pi / n)
	local panelW = 2 * TOWER_R * math.sin(math.pi / n) + 0.2
	local door = 15 -- the door gaps (plaza side and lobby side) stop this far up
	for k = 0, n - 1 do
		-- turned half a step: no panel faces exactly along X or Z (never parallel to the façade)
		local a = (k + 0.5) / n * 2 * math.pi
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local isDoor = math.abs(dir.Z) > 0.9 -- the two panels facing -Z (plaza) and +Z (lobby)
		-- neighbours overlap at their inner corners: odd panels start/end 0.25 higher
		local odd = k % 2 * 0.25
		local y0 = isDoor and door + odd or -0.5 + odd
		local y1 = TOWER_H + odd
		local pos = dir * apothem + Vector3.new(0, (y0 + y1) / 2, 0)
		local pcf = CFrame.lookAt(pos, pos + dir)
		PartKit.part(m, tcf, pcf, Vector3.new(panelW, y1 - y0, 2), Enum.Material.Plaster, STONE, "TowerWall")
	end
	-- floor of the tower's outer half (meets the lobby floor edge to edge) on its own plinth
	-- (the façade plinth stops 0.5 in front of the wall), and a step up from the plaza
	local base = PartKit.FOUNDATION - 0.6
	local fd = apothem * 0.68
	PartKit.part(m, tcf, at(0, base + 0.2, -fd / 2 + T / 2), Vector3.new(apothem * 1.36, 0.4, fd + T), Enum.Material.Marble, C(196, 190, 178), "TowerFloor")
	PartKit.part(m, tcf, at(0, base - PartKit.FOUNDATION / 2, (-fd - 0.5) / 2), Vector3.new(apothem * 1.36, PartKit.FOUNDATION, fd - 0.5), Enum.Material.Slate, STONE_DARK, "TowerPlinth")
	PartKit.part(m, tcf, at(0, 0.35, -apothem - 2.2), Vector3.new(14, 0.7, 2.4), Enum.Material.Slate, STONE_DARK, "DoorStep")
	-- ring bands every 30 studs, 1.2 proud of the panels
	for ry = 30, TOWER_H - 10, 30 do
		for k = 0, n - 1 do
			local a = (k + 0.5) / n * 2 * math.pi
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local pos = dir * (apothem + 1.2) + Vector3.new(0, ry, 0)
			-- below the roof line only the plaza half shows (the rest is inside the building)
			if pos.Z < -0.5 or ry > 80 then
				PartKit.part(m, tcf, CFrame.lookAt(pos, pos + dir), Vector3.new(panelW + 0.5, k % 2 == 0 and 1.6 or 1.3, 2), Enum.Material.Slate, STONE_DARK, "TowerRing", { shadow = false })
			end
		end
	end
	-- the spiral band: 3.25 turns of a thick cream ribbon standing off the wall
	local turns, y0, y1 = 3.25, 10, TOWER_H - 14
	local segs = math.floor(turns * 36)
	local RH = apothem + 3.4
	local total = turns * 2 * math.pi
	local function point(t: number): Vector3
		local th = t * total + math.rad(200)
		return Vector3.new(math.cos(th) * RH, y0 + (y1 - y0) * t, math.sin(th) * RH)
	end
	for i = 0, segs - 1 do
		local p0, p1 = point(i / segs), point((i + 1) / segs)
		local len = (p1 - p0).Magnitude
		-- consecutive segments overlap 0.6: alternate the section so side faces never align
		local sec = i % 2 == 0 and Vector2.new(3.6, 5) or Vector2.new(3.2, 4.6)
		local mid = (p0 + p1) / 2
		if mid.Z < -2 or mid.Y > 80 then -- skip the part of each turn hidden inside the building
			PartKit.part(m, tcf, CFrame.lookAt(mid, p1), Vector3.new(sec.X, sec.Y, len + 0.6), Enum.Material.Plaster, CREAM, "Helix", { shadow = true })
		end
	end
	-- crown ring, small patch dome, spikes and a spire
	for k = 0, n - 1 do
		local a = (k + 0.5) / n * 2 * math.pi
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local ch = k % 2 == 0 and 3 or 2.6
		local pos = dir * (apothem + 0.6) + Vector3.new(0, TOWER_H + 0.25 * (k % 2) + ch / 2, 0)
		PartKit.part(m, tcf, CFrame.lookAt(pos, pos + dir), Vector3.new(panelW + 0.3, ch, 3.2), Enum.Material.Slate, STONE_DARK, "Crown")
	end
	local cap = PartKit.dome(m, tcf.Position + Vector3.new(0, TOWER_H + 3, 0), apothem + 1, 16, 1.5, {}, 0, 0, rng, Vector2.new(6, 5), 0)
	cap.Name = "TowerCap"
	for k = 0, 7 do
		local a = (k + 0.25) / 8 * 2 * math.pi
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local foot = dir * (apothem - 2) + Vector3.new(0, TOWER_H + 6, 0)
		local tip = foot + dir * 7 + Vector3.new(0, 16, 0)
		PartKit.part(m, tcf, CFrame.lookAt((foot + tip) / 2, tip), Vector3.new(0.8 + 0.05 * k, 0.8 + 0.05 * k, (tip - foot).Magnitude), Enum.Material.Metal, IRON, "Spike", { shadow = false })
	end
	PartKit.part(m, tcf, at(0, TOWER_H + 3 + 16 + 12, 0), Vector3.new(1.4, 28, 1.4), Enum.Material.Metal, IRON, "Spire")
	local beacon = PartKit.part(m, tcf, at(0, TOWER_H + 3 + 16 + 27, 0), Vector3.new(2, 2, 2), Enum.Material.Neon, YELLOW, "Beacon", { collide = false, shadow = false })
	Decor.glow(beacon, C(255, 210, 120), 14)
end

-- ─── yard: wall, gate, sign, walkway, lamps ────────────────────────────────────

local function yard(m: Model, cf: CFrame, half: Vector2, walkTo: number, rng: Random)
	local wh, wt = 7, 1.6
	local gate = 22 -- half width of the gate opening
	local post = 4
	local zF, zB = -half.Y + wt / 2, half.Y - wt / 2
	local xL, xR = -half.X + wt / 2, half.X - wt / 2
	local stone = Enum.Material.Slate
	-- front wall in two pieces around the gate posts; back full width; sides between
	PartKit.part(m, cf, at((-half.X + (-gate - post)) / 2, wh / 2, zF), Vector3.new(half.X - gate - post, wh, wt), stone, STONE_DARK, "YardWall")
	PartKit.part(m, cf, at((half.X + gate + post) / 2, wh / 2, zF), Vector3.new(half.X - gate - post, wh, wt), stone, STONE_DARK, "YardWall")
	PartKit.part(m, cf, at(0, wh / 2, zB), Vector3.new(2 * half.X, wh, wt), stone, STONE_DARK, "YardWall")
	PartKit.part(m, cf, at(xL, wh / 2, 0), Vector3.new(wt, wh, 2 * half.Y - 2 * wt), stone, STONE_DARK, "YardWall")
	PartKit.part(m, cf, at(xR, wh / 2, 0), Vector3.new(wt, wh, 2 * half.Y - 2 * wt), stone, STONE_DARK, "YardWall")
	-- gate posts, lintel and sign
	local ph = 14
	for _, sx in { -1, 1 } do
		PartKit.part(m, cf, at(sx * (gate + post / 2), ph / 2, zF), Vector3.new(post, ph, post), stone, STONE, "GatePost")
		-- lantern sitting on the lintel above each post
		local l = PartKit.part(m, cf, at(sx * (gate + post / 2), ph + 3.4 + 0.7, zF - 0.9), Vector3.new(1, 1.4, 1), Enum.Material.Neon, LAMP, "GateLantern", { collide = false, shadow = false })
		local light = Instance.new("PointLight")
		light.Color = C(255, 132, 70)
		light.Brightness = 2
		light.Range = 27
		light.Shadows = true -- hero light (the reference's torch recipe)
		light.Parent = l
		Decor.glow(l, C(255, 170, 100), 4)
	end
	PartKit.part(m, cf, at(0, ph + 1.7, zF), Vector3.new(2 * (gate + post), 3.4, 5), stone, STONE_DARK, "Lintel")
	local board = PartKit.part(m, cf, at(0, ph + 1.7, zF - 2.5 - 0.2), Vector3.new(30, 2.8, 0.4), Enum.Material.WoodPlanks, C(60, 50, 40), "SignBoard", { collide = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "MENDERS"
	label.TextScaled = true
	label.Font = Enum.Font.Bangers
	label.TextColor3 = YELLOW
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	gui.Parent = board
	-- walkway from the gate to the tower door, lined with lamps
	local wz0, wz1 = -half.Y + wt, walkTo
	PartKit.part(m, cf, at(0, 0.2, (wz0 + wz1) / 2), Vector3.new(14, 0.4, wz1 - wz0), Enum.Material.Pavement, C(150, 146, 138), "Walkway")
	local z = wz0 + 16
	while z < wz1 - 8 do
		for _, sx in { -1, 1 } do
			lamp(m, cf * at(sx * 11, 0, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-1, 1)), 0))
		end
		z += 24
	end
end

-- ─── plaza dressing: planters, benches, flags, fountains ───────────────────────

local GREEN = { C(66, 84, 58), C(58, 76, 52), C(74, 92, 62) }

-- A stone planter with a bush of two turned blocks (tops at different heights).
local function planter(m: Model, cf: CFrame, rng: Random)
	PartKit.part(m, cf, at(0, 1.2, 0), Vector3.new(6, 2.4, 6), Enum.Material.Slate, STONE_DARK, "Planter")
	PartKit.part(m, cf, at(0, 2.4 + 1.6, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(10, 35)), 0), Vector3.new(4.6, 3.2, 4.6), Enum.Material.Grass, GREEN[rng:NextInteger(1, #GREEN)], "Bush")
	-- the second block starts 0.2 higher: the two bushes never share a bottom plane
	PartKit.part(m, cf, at(0, 2.6 + 2.15, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(50, 80)), 0), Vector3.new(3.4, 4.3, 3.4), Enum.Material.Grass, GREEN[rng:NextInteger(1, #GREEN)], "Bush")
end

local function bench(m: Model, cf: CFrame)
	for _, sx in { -1, 1 } do
		PartKit.part(m, cf, at(sx * 2.4, 0.9, 0), Vector3.new(0.6, 1.8, 1.6), Enum.Material.Slate, STONE_DARK, "BenchLeg")
	end
	PartKit.part(m, cf, at(0, 1.8 + 0.25, 0), Vector3.new(6.2, 0.5, 2), Enum.Material.WoodPlanks, C(98, 78, 60), "BenchSeat")
end

local function flag(m: Model, cf: CFrame, rng: Random)
	PartKit.part(m, cf, at(0, 0.5, 0), Vector3.new(2.2, 1, 2.2), Enum.Material.Slate, STONE_DARK, "FlagBase")
	PartKit.part(m, cf, at(0, 1 + 14, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(28, 0.6, 0.6), Enum.Material.Metal, IRON, "FlagPole", { shape = Enum.PartType.Cylinder })
	PartKit.part(m, cf, at(3.4, 25.5, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), math.rad(rng:NextNumber(-3, 3))), Vector3.new(6.4, 4, 0.2), Enum.Material.Fabric, YELLOW, "Flag", { collide = false, shadow = false })
end

-- A round-ish fountain: an octagon of rim blocks (each turned 45 degrees from the last;
-- neighbours alternate top and bottom so their overlapping corners never share a face), a basin floor
-- lifted 0.05 off the yard (its bottom never level with the rim's), a water slab under the rim,
-- a central column.
local function fountain(m: Model, cf: CFrame)
	PartKit.part(m, cf, at(0, 0.325, 0), Vector3.new(15, 0.55, 15), Enum.Material.Slate, STONE_DARK, "FountainFloor")
	for k = 0, 7 do
		local a = k / 8 * 2 * math.pi
		-- even rims: 0 to 2.4; odd rims sunk: -0.3 to 2.6
		local y0, y1 = 0, 2.4
		if k % 2 == 1 then
			y0, y1 = -0.3, 2.6
		end
		PartKit.part(m, cf, CFrame.Angles(0, -a, 0) * at(7.2, (y0 + y1) / 2, 0), Vector3.new(1.4, y1 - y0, 6.4), Enum.Material.Marble, STONE, "FountainRim")
	end
	local water = PartKit.part(m, cf, at(0, 0.6 + 0.8, 0), Vector3.new(12.6, 1.6, 12.6), Enum.Material.SmoothPlastic, C(70, 108, 118), "FountainWater", { collide = false, shadow = false })
	water.Transparency = 0.25
	water.Reflectance = 0.15
	-- the column is sunk 0.2 into the floor, so its bottom is not level with the water's
	PartKit.part(m, cf, at(0, 0.4 + 3.5, 0) * CFrame.Angles(0, math.rad(22.5), 0), Vector3.new(2.6, 7, 2.6), Enum.Material.Marble, STONE, "FountainColumn")
end

local function plaza(m: Model, cf: CFrame, half: Vector2, z0: number, z1: number, rng: Random)
	-- two fountains either side of the walkway, a third of the way in
	local fz = z0 + (z1 - z0) * 0.35
	for _, sx in { -1, 1 } do
		fountain(m, cf * at(sx * 46, 0, fz))
		-- yellow flags flanking the gate
		flag(m, cf * at(sx * 34, 0, z0 + 10) * CFrame.Angles(0, math.rad(sx * 3), 0), rng)
	end
	-- rows of planters and benches across the plaza, clear of the walkway, lamps and fountains
	local z = z0 + 30
	while z < z1 - 20 do
		for _, sx in { -1, 1 } do
			for _, x in { 70, 110, 150, 190 } do
				if x < half.X - 20 and math.abs(z - fz) > 16 then
					planter(m, cf * at(sx * x, 0, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-2, 2)), 0), rng)
					bench(m, cf * at(sx * x, 0, z + 9) * CFrame.Angles(0, math.rad(rng:NextNumber(-3, 3)), 0))
				end
			end
		end
		z += 44
	end
end

-- ─── entry point ──────────────────────────────────────────────────────────────

function MendersBase.build(parent: Instance, cf: CFrame, half: Vector2, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "MendersBase"
	local W = math.min(2 * half.X - 80, 360)
	W = math.floor(W / BAY) * BAY -- whole bays
	local zc = half.Y - DEPTH / 2 - 30 -- the façade stands toward the back of the yard
	local bcf = cf * at(0, 0, zc)
	facade(m, bcf, W, rng)
	local tcf = cf * at(0, 0, zc - DEPTH / 2) -- the tower straddles the façade's front plane
	tower(m, tcf, rng)
	-- the walkway stops short of the door step in front of the tower
	local walkTo = zc - DEPTH / 2 - TOWER_R - 3.6
	yard(m, cf, half, walkTo, rng)
	plaza(m, cf, half, -half.Y + 1.6, walkTo, rng)
	m.Parent = parent
	return m
end

return MendersBase
