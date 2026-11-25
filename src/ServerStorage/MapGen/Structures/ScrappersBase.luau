--!strict
--[[
	MapGen.Structures.ScrappersBase - a scrapyard hideout assembled from plain Parts.
	Open circulation, repair bays and warm communal spaces sell the faction without
	weapons, violent dressing, external assets or additional sign text.

	All placement is in the yard frame: ground = 0, front = -Z. Buildings keep their
	human dimensions; only the perimeter follows the supplied half extents.
	Shells are split into touching strips, not overlapping boxes. Ribs stop short of
	shell edges, hardware has separate depths, and adjacent containers have air gaps.
	Stacked shells meet with opposite-facing faces only. Loose props use seeded yaw.
	The warehouse is 130 x 80, with a 34-stud roof and a walkable mezzanine.
	No Atomic streaming override: this deliberately remains an ordinary Model.
]]

local PartKit = require(script.Parent.Parent.PartKit)
local Decor = require(script.Parent.Parent.Decor)

local ScrappersBase = {}
local C = Color3.fromRGB
local RED = C(110, 34, 30)
local BLACK = C(39, 37, 35)
local YELLOW = C(151, 128, 65)
local WARM = C(255, 171, 103)
local STEEL = C(62, 61, 58)
local RUST = C(96, 60, 44)
local CONCRETE = C(99, 96, 87)
local METAL = Enum.Material.Metal
-- Big sheet surfaces are plain Metal in dark colours: CorrodedMetal's texture washes out to
-- pink under the reference lighting (bright ambient, +0.4 exposure). Rust stays on small props.
local SCRAP = Enum.Material.Metal
local RUSTY = Enum.Material.CorrodedMetal
-- container paint: dark, dirty versions of shipping colours
local PAINT = { C(92, 38, 34), C(48, 62, 60), C(84, 70, 52), C(58, 58, 56), C(98, 80, 40), C(64, 52, 62) }
local V = Vector3.new
local at = CFrame.new

-- ─── shared small assemblies ───

local function box(parent: Instance, frame: CFrame, name: string, pos: Vector3, size: Vector3,
	material: Enum.Material, color: Color3, rotation: CFrame?): BasePart
	return PartKit.part(parent, frame, at(pos) * (rotation or CFrame.identity), size, material, color, name)
end

local function rod(parent: Instance, frame: CFrame, name: string, a: Vector3, b: Vector3,
	width: number, color: Color3): BasePart
	return PartKit.part(parent, frame, CFrame.lookAt((a + b) / 2, b), V(width, width, (b - a).Magnitude), METAL, color, name)
end

local function lantern(parent: Instance, frame: CFrame, pos: Vector3, hero: boolean): BasePart
	local lamp = box(parent, frame, "Lantern", pos, V(0.8, 1.2, 0.8), Enum.Material.Neon, WARM)
	lamp.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = WARM
	light.Brightness = 1.5
	light.Range = 24
	light.Shadows = hero
	light.Parent = lamp
	Decor.glow(lamp, WARM, 3)
	return lamp
end

local function flood(parent: Instance, frame: CFrame, pos: Vector3, target: Vector3, hero: boolean)
	-- Front (-Z) of the lamp explicitly faces the illuminated approach.
	local lamp = PartKit.part(parent, frame, CFrame.lookAt(pos, target), V(2.4, 1.3, 0.7), METAL, BLACK, "Floodlight")
	local lens = PartKit.part(parent, lamp.CFrame, at(0, 0, -0.43), V(2, 0.9, 0.12), Enum.Material.Neon, WARM, "FloodLens", { collide = false })
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Angle = 85
	light.Brightness = 2.5
	light.Range = 90
	light.Color = WARM
	light.Shadows = hero
	light.Parent = lens
end

local function tableAt(parent: Instance, frame: CFrame)
	box(parent, frame, "Worktop", V(0, 3.75, 0), V(9, 0.5, 4), Enum.Material.WoodPlanks, PartKit.PALETTE.timber[1])
	for _, x in { -3.6, 3.6 } do
		for _, z in { -1.25, 1.25 } do
			box(parent, frame, "TableLeg", V(x, 1.75, z), V(0.6, 3.5, 0.6), METAL, BLACK)
		end
	end
end

local function crate(parent: Instance, frame: CFrame, rng: Random, y: number, size: number)
	local yaw = math.rad(rng:NextNumber(0.7, 2)) * (rng:NextInteger(0, 1) * 2 - 1)
	local f = frame * at(0, y, 0) * CFrame.Angles(0, yaw, 0)
	box(parent, f, "Crate", V(0, size / 2, 0), V(size, size, size), Enum.Material.WoodPlanks, PartKit.PALETTE.timber[2])
	-- Straps sit outside the front, with shortened ends: no shared top/bottom faces.
	for _, x in { -size * 0.3, size * 0.3 } do
		box(parent, f, "CrateStrap", V(x, size / 2, -size / 2 - 0.09), V(0.23, size - 0.4, 0.12), METAL, STEEL)
	end
end

local function drum(parent: Instance, frame: CFrame, rng: Random)
	local f = frame * CFrame.Angles(0, math.rad(rng:NextNumber(-2, 2)), math.pi / 2)
	-- Roblox cylinders use local X as their axis; rotate that axis upright.
	PartKit.part(parent, f, at(2.1, 0, 0), V(4.2, 2.8, 2.8), RUSTY, rng:NextInteger(0, 1) == 0 and RUST or BLACK, "OilDrum", { shape = Enum.PartType.Cylinder })
	for _, h in { 0.8, 3.3 } do
		PartKit.part(parent, f, at(h, 0, 0), V(0.16, 2.92, 2.92), METAL, STEEL, "DrumHoop", { shape = Enum.PartType.Cylinder })
	end
end

-- ─── shipping shells and perimeter infill ───

local function container(parent: Instance, frame: CFrame, length: number, height: number,
	depth: number, color: Color3, open: boolean)
	-- Walls occupy the space BETWEEN floor and roof. End panels fit BETWEEN sides.
	local t = 0.3
	box(parent, frame, "ContainerFloor", V(0, t / 2, 0), V(length, t, depth), METAL, STEEL)
	box(parent, frame, "ContainerRoof", V(0, height - t / 2, 0), V(length, t, depth), SCRAP, color)
	for _, side in { -1, 1 } do
		box(parent, frame, "ContainerSide", V(0, height / 2, side * (depth - t) / 2), V(length, height - 2 * t, t), SCRAP, color)
		-- Two ribs per long face keep the full compound below the Part budget.
		for i = 1, 2 do
			box(parent, frame, "ContainerRib", V(length * (i / 3 - 0.5), height / 2 + 0.07, side * (depth / 2 + 0.12)), V(0.22, height - 1.4, 0.18), METAL, color)
		end
	end
	box(parent, frame, "ContainerEnd", V((length - t) / 2, height / 2, 0), V(t, height - 2 * t, depth - 2 * t), SCRAP, color)
	if open then
		-- Entire end remains open; no door leaves project into the alley.
	else
		box(parent, frame, "ContainerDoors", V(-(length - t) / 2, height / 2, 0), V(t, height - 2 * t, depth - 2 * t), SCRAP, color)
		for _, z in { -depth * 0.27, depth * 0.27 } do
			box(parent, frame, "DoorBar", V(-length / 2 - 0.16, height / 2 + 0.04, z), V(0.18, height - 1.1, 0.22), METAL, YELLOW)
		end
	end
end

local function fence(parent: Instance, frame: CFrame, length: number)
	-- Eight-stud bays, each separated by a small visible gap.
	local n = math.max(1, math.ceil(length / 8))
	local bay = length / n
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * bay
		box(parent, frame, "FenceSheet", V(x, 5.8, 0), V(bay - 0.28, 11.1, 0.25), SCRAP, RUST)
		box(parent, frame, "FencePost", V(x, 6, 0.48), V(0.5, 12, 0.5), METAL, BLACK)
		rod(parent, frame, "WireRod", V(x, 12, 0.48), V(x, 14, -0.7), 0.16, STEEL)
		for k = 1, 2 do
			box(parent, frame, "FenceCorrugation", V(x + (k - 1.5) * bay / 3, 5.87, -0.22), V(0.14, 10.3, 0.12), METAL, STEEL)
		end
	end
	-- Barbed wire is a Beam, so intersections do not add coincident box faces.
	Decor.cable(parent, frame:PointToWorldSpace(V(-length / 2, 13.7, -0.52)), frame:PointToWorldSpace(V(length / 2, 13.7, -0.52)), 0.15, STEEL, 0.08)
end

local function perimeterRun(parent: Instance, frame: CFrame, length: number, rng: Random)
	local pitch = 40.3 -- 40-stud container plus 0.3 air between neighbors.
	local n = math.floor(length / pitch)
	local occupied = n * pitch
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * pitch
		for level = 0, 1 do
			local color = PAINT[rng:NextInteger(1, #PAINT)]
			container(parent, frame * at(x, level * 9.5, 0), 40, 9.5, 9, color, false)
		end
	end
	local remaining = length - occupied
	if remaining > 0.4 then
		fence(parent, frame * at(length / 2 - remaining / 2, 0, 0), remaining - 0.3)
	end
end

local function tower(parent: Instance, frame: CFrame)
	for _, x in { -5, 5 } do
		for _, z in { -5, 5 } do
			box(parent, frame, "ScaffoldPost", V(x, 10.3, z), V(0.7, 20.6, 0.7), METAL, STEEL)
		end
	end
	box(parent, frame, "WatchPlatform", V(0, 20.8, 0), V(11.6, 0.4, 11.6), Enum.Material.WoodPlanks, PartKit.PALETTE.timber[1])
	for _, x in { -5.3, 5.3 } do
		box(parent, frame, "WatchRail", V(x, 24.2, 0), V(0.28, 0.28, 11.1), METAL, YELLOW)
	end
	box(parent, frame, "WatchRail", V(0, 24.27, -5.3), V(10.3, 0.22, 0.22), METAL, YELLOW)
	for _, x in { -3.8, 3.8 } do
		box(parent, frame, "WatchRail", V(x, 24.27, 5.3), V(2.7, 0.22, 0.22), METAL, YELLOW)
	end
	for _, x in { -5, 5 } do
		for _, z in { -5, 5 } do
			box(parent, frame, "RailUpright", V(x, 22.6, z), V(0.24, 3.2, 0.24), METAL, BLACK)
		end
	end
	-- Access ladder on the yard side, beyond the platform; final rung reaches deck.
	for _, x in { -1.8, 1.8 } do
		box(parent, frame, "LadderStile", V(x, 10.6, 6.4), V(0.25, 21.2, 0.3), METAL, BLACK)
	end
	for i = 1, 21 do
		box(parent, frame, "LadderRung", V(0, i - 0.2, 6.4), V(3.35, 0.2, 0.22), METAL, STEEL)
	end
	flood(parent, frame, V(0, 25.5, -4.5), V(0, 0, 35), true)
end

-- ─── warehouse: split openings, accessible mezzanine, repair interior ───

local function warehouse(parent: Instance, frame: CFrame, rng: Random)
	local floor, roof = 0.5, 34
	box(parent, frame, "WarehouseSlab", V(0, 0.25, 0), V(130, floor, 80), Enum.Material.Concrete, CONCRETE)
	-- A 30 x 22 opening, split into two piers and a header; no hidden door leaf.
	for _, x in { -40, 40 } do
		box(parent, frame, "WarehouseFrontPier", V(x, 17.25, -39.6), V(50, 33.5, 0.8), SCRAP, RED)
	end
	box(parent, frame, "RollDoorHeader", V(0, 28.25, -39.6), V(30, 11.5, 0.8), SCRAP, RED)
	box(parent, frame, "WarehouseBack", V(0, 17.25, 39.6), V(130, 33.5, 0.8), SCRAP, RUST)
	for _, x in { -64.6, 64.6 } do
		box(parent, frame, "WarehouseSide", V(x, 17.25, 0), V(0.8, 33.5, 78.4), SCRAP, STEEL)
	end
	box(parent, frame, "WarehouseRoof", V(0, roof + 0.35, 0), V(132, 0.7, 82), SCRAP, BLACK)
	-- Columns stop at the roof underside and stand outside the mezzanine footprint.
	for _, x in { -58, 54 } do
		for _, z in { -33, 33 } do
			box(parent, frame, "SteelColumn", V(x, 17.25, z), V(0.9, 33.5, 1.1), METAL, STEEL)
		end
	end
	box(parent, frame, "Mezzanine", V(-49, 14.25, 0), V(26, 0.5, 60), METAL, STEEL)
	for _, z in { -27, -8, 12, 27 } do
		box(parent, frame, "MezzRailPost", V(-36.5, 16.2, z), V(0.24, 3.4, 0.24), METAL, YELLOW)
	end
	for _, span in { { -30, -23.1 }, { -16.9, 30 } } do
		box(parent, frame, "MezzRail", V(-36.5, 17.87, (span[1] + span[2]) / 2), V(0.32, 0.22, span[2] - span[1]), METAL, YELLOW)
	end
	for _, z in { -29.6, 29.6 } do
		box(parent, frame, "MezzEndRail", V(-49, 17.93, z), V(24.4, 0.18, 0.18), METAL, YELLOW)
		box(parent, frame, "MezzSupport", V(-40, 7.25, z), V(0.7, 13.5, 0.7), METAL, BLACK)
	end
	-- Fourteen touching treads; the last meets the mezzanine's +X edge at -36.
	for i = 1, 14 do
		box(parent, frame, "Stair", V(-15 - (i - 0.5) * 1.5, floor + i / 2, -20), V(1.5, i, 6), METAL, STEEL)
	end
	for _, z in { -23.35, -16.65 } do
		rod(parent, frame, "StairHandrail", V(-15.75, 4.9, z), V(-35.25, 17.9, z), 0.24, YELLOW)
	end
	tableAt(parent, frame * at(42, floor, 22))
	tableAt(parent, frame * at(-49, floor, 12))
	tableAt(parent, frame * at(-49, 14.5, 18))
	for i = 1, 5 do
		local f = frame * at(-15 + i * 11, floor, 32)
		crate(parent, f, rng, 0, 5)
		crate(parent, f, rng, 5, 3.5)
	end
	for _, pos in { V(20, 24, -30), V(34, 24, 22), V(-49, 25, 0), V(-49, 9, 0) } do
		lantern(parent, frame, pos, false)
	end
	local board = box(parent, frame, "ScrappersSign", V(0, 28.5, -40.45), V(44, 7, 0.4), Enum.Material.Neon, C(58, 16, 15))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "SCRAPPERS"
	label.Font = Enum.Font.Bangers
	label.TextScaled = true
	label.TextColor3 = RED
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
end

-- ─── open garage and communal yard ───

local function garage(parent: Instance, frame: CFrame, rng: Random)
	box(parent, frame, "GarageBack", V(0, 7.5, 12.6), V(72, 15, 0.8), SCRAP, RUST)
	for _, x in { -35.6, 35.6 } do
		box(parent, frame, "GarageSide", V(x, 7.5, 0), V(0.8, 15, 24.4), SCRAP, STEEL)
		box(parent, frame, "GarageFrontPost", V(x, 7.65, -12.8), V(0.6, 15.3, 0.6), METAL, YELLOW)
	end
	for _, x in { -12, 12 } do
		box(parent, frame, "BayPost", V(x, 7.5, -12.8), V(0.7, 15, 0.7), METAL, YELLOW)
	end
	box(parent, frame, "GarageRoof", V(0, 15.6, 0), V(74, 0.5, 28), SCRAP, BLACK, CFrame.Angles(math.rad(2), 0, 0))
	for _, x in { -24, 0, 24 } do
		local f = frame * at(x, 0, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(1, 2)), 0)
		box(parent, f, "CarChassis", V(0, 2.6, 0), V(7, 1.2, 13), SCRAP, STEEL)
		-- Open cabin frame: pillars, roof and hood, rather than an opaque solid cabin.
		for _, sx in { -2.8, 2.8 } do
			for _, z in { -2.5, 3 } do
				box(parent, f, "CabinPillar", V(sx, 4.65, z), V(0.3, 2.9, 0.35), METAL, RUST)
			end
		end
		box(parent, f, "CarCabinRoof", V(0, 6.25, 0.25), V(6.2, 0.3, 6.2), SCRAP, RED)
		box(parent, f, "CarHood", V(0, 3.45, -4.6), V(6.5, 0.5, 3), SCRAP, RUST)
		for _, sx in { -3.7, 3.7 } do
			for _, z in { -4.1, 4.1 } do
				PartKit.part(parent, f, at(sx, 1.6, z), V(1.1, 3.2, 3.2), Enum.Material.SmoothPlastic, BLACK, "CarWheel", { shape = Enum.PartType.Cylinder })
			end
		end
	end
	drum(parent, frame * at(-30, 0, 9), rng)
	drum(parent, frame * at(-18, 0, 9), rng)
	lantern(parent, frame, V(0, 12, 10), false)
end

-- ─── scaffold promenade and reserved prop pads ───

local function catwalk(parent: Instance, frame: CFrame, length: number)
	-- Posts end against the deck underside. Separate planks only touch at their ends.
	local n = math.ceil(length / 8)
	local pitch = length / n
	for i = 1, n do
		local x = -length / 2 + (i - 0.5) * pitch
		box(parent, frame, "CatwalkPlank", V(x, 20.8, 0), V(pitch, 0.4, 8), Enum.Material.WoodPlanks, PartKit.PALETTE.timber[i % 3 + 1])
		for _, z in { -3.4, 3.4 } do
			box(parent, frame, "CatwalkPost", V(x, 10.3, z), V(0.55, 20.6, 0.65), METAL, STEEL)
			box(parent, frame, "CatwalkRailPost", V(x, 22.6, z), V(0.22, 3.2, 0.22), METAL, BLACK)
		end
	end
	box(parent, frame, "CatwalkRail", V(0, 24.3, 3.4), V(length, 0.2, 0.3), METAL, YELLOW)
	for _, span in { { -length / 2, -28.4 }, { -23.6, 23.6 }, { 28.4, length / 2 } } do
		box(parent, frame, "CatwalkRail", V((span[1] + span[2]) / 2, 24.3, -3.4), V(span[2] - span[1], 0.2, 0.3), METAL, YELLOW)
	end
	for _, x in { -length / 2 + 8, length / 2 - 8 } do
		for _, dx in { -1.8, 1.8 } do
			box(parent, frame, "CatwalkLadderStile", V(x + dx, 10.6, 4.5), V(0.25, 21.2, 0.3), METAL, BLACK)
		end
		for i = 1, 21 do
			box(parent, frame, "CatwalkLadderRung", V(x, i - 0.1, 4.5), V(3.35, 0.2, 0.22), METAL, STEEL)
		end
	end
end

local function salvage(parent: Instance, frame: CFrame, rng: Random, kind: number)
	-- Each cluster owns an 18 x 14 pad, including every rotated extremity.
	local f = frame * CFrame.Angles(0, math.rad(rng:NextNumber(1, 5)), 0)
	if kind == 1 then
		crate(parent, f * at(-4, 0, 0), rng, 0, 5)
		crate(parent, f * at(-4, 0, 0), rng, 5, 3.5)
		drum(parent, f * at(4, 0, -3), rng)
		drum(parent, f * at(4.4, 0, 2), rng)
	elseif kind == 2 then
		for pile = 1, 2 do
			for level = 0, 3 do
				local yaw = math.rad(rng:NextNumber(1, 4))
				for i = 1, 8 do
					local angle = i * math.pi / 4 + yaw
					local pos = V((pile - 1.5) * 8 + math.cos(angle) * 1.5, level * 0.8 + 0.4, math.sin(angle) * 1.5)
					PartKit.part(parent, f, at(pos) * CFrame.Angles(0, angle, math.pi / 2), V(0.8, 1.05, 1.05), Enum.Material.SmoothPlastic, BLACK, "TyreSegment", { shape = Enum.PartType.Cylinder })
				end
			end
		end
	else
		for i = 1, 5 do
			local h = 1.2 + i * 0.37
			local yaw = math.rad(rng:NextNumber(-14, 14))
			box(parent, f, "ScrapBundle", V(-6 + (i - 1) * 3, h / 2, (i % 2) * 4 - 2), V(2.2, h, 3), RUSTY, PAINT[i], CFrame.Angles(0, yaw, 0))
		end
	end
end

function ScrappersBase.build(parent: Instance, cf: CFrame, half: Vector2, rng: Random): Model
	assert(half.X >= 180 and half.Y >= 150, "ScrappersBase requires half extents >= 180 x 150")
	local model = Instance.new("Model")
	model.Name = "ScrappersBase"
	-- Follow the supplied 500 x 420 yard, with a bounded maximum Part count.
	local hx, hz = math.min(half.X, 250) - 8, math.min(half.Y, 210) - 8
	local frontZ = -hz
	perimeterRun(model, cf * at(0, 0, hz), 2 * hx - 12, rng)
	for _, side in { -1, 1 } do
		perimeterRun(model, cf * at(side * hx, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 2 * hz - 12, rng)
		local length = hx - 26
		perimeterRun(model, cf * at(side * (26 + length / 2), 0, frontZ), length, rng)
		tower(model, cf * at(side * 26, 0, frontZ + 13))
	end

	-- AABB reservations contain roofs, ribs, lamps and jitter, not just nominal slabs.
	-- Reject overlap BEFORE constructing anything. Lanes are reservations too, so scatter
	-- cannot quietly consume circulation. Nested furniture belongs to its shell assembly.
	type Footprint = { x: number, z: number, w: number, d: number }
	local footprints: { Footprint } = {}
	local function reserve(x: number, z: number, w: number, d: number, gap: number): boolean
		if math.abs(x) + w / 2 > hx - 6 or math.abs(z) + d / 2 > hz - 6 then
			return false
		end
		for _, other in footprints do
			if math.abs(x - other.x) < (w + other.w) / 2 + gap
				and math.abs(z - other.z) < (d + other.d) / 2 + gap then
				return false
			end
		end
		table.insert(footprints, { x = x, z = z, w = w, d = d })
		return true
	end
	local wz = hz - 53
	assert(reserve(0, wz, 134, 84, 3), "Warehouse footprint out of bounds")
	warehouse(model, cf * at(0, 0, wz), rng)
	-- The 36-stud gate approach has two clear 14-stud branches around the fire circle.
	assert(reserve(0, frontZ + 43, 36, 8, 0), "Gate approach out of bounds")
	local fireZ = wz - 102
	assert(reserve(0, fireZ, 52, 52, 3), "Courtyard footprint out of bounds")
	local gx = hz >= 185 and 0 or -hx + 51
	local gz = frontZ + (hz >= 185 and 112 or 48)
	if reserve(gx, gz, 76, 30, 12) then
		garage(model, cf * at(gx, 0, gz), rng)
	end

	-- Five streets per side, two blocks per street, 16-stud cross alleys and
	-- 15-stud lengthwise lanes. Smaller supported yards retain full lane widths,
	-- dropping the outer column and the last two rows instead of squeezing buildings.
	local rows = hz >= 185 and 5 or 3
	local columns = hx >= 225 and 2 or 1
	for _, side in { -1, 1 } do
		for row = 1, rows do
			local z = frontZ + 72 + (row - 1) * 64
			for column = 1, columns do
				local x = side * (114.5 + (column - 1) * 86)
				if reserve(x, z, 70.8, 48.8, 12) then
					local f = cf * at(x, 0, z)
					-- Open ends face the central street; roof loads start EXACTLY at y=14.
					if side < 0 then f *= CFrame.Angles(0, math.pi, 0) end
					local levels = 1 + (row + column) % 3
					for level = 0, levels - 1 do
						local color = PAINT[rng:NextInteger(1, #PAINT)]
						container(model, f * at(0, level * 14, 0), 70, 14, 48, color, level == 0)
					end
					tableAt(model, f * at(-18, 0.3, 0))
					lantern(model, f, V(-20, 10, 6), false)
					crate(model, f * at(22, 0.3, -7), rng, 0, 5)
				end
			end
		end
	end

	-- Six occupied scrap homes, including foundation and roof overhang in each pad.
	-- PartKit's foundation normally starts at -0.6; +0.35 sinks its bottom to -0.25.
	local compact = hz < 185
	local homeSize, homePad = compact and 24 or 36, compact and 28 or 40
	local homeFront = frontZ + (compact and 59 or 53)
	local homeBackX = compact and hx - 34 or 200.5
	local homeMiddleX = compact and 50 or 44
	local homeMiddleZ = fireZ + (compact and 8 or -69)
	local homes = {
		V(-44, 0, homeFront), V(44, 0, homeFront),
		V(-homeMiddleX, 0, homeMiddleZ), V(homeMiddleX, 0, homeMiddleZ),
		V(-homeBackX, 0, hz - 26), V(homeBackX, 0, hz - 26),
	}
	for i, pos in homes do
		if reserve(pos.X, pos.Z, homePad, homePad, 3) then
			PartKit.house(model, cf * at(pos.X, 0.35, pos.Z), {
				w = homeSize, d = homeSize, storeys = 1, style = "scrap",
				ridgeAlongDepth = i % 2 == 0, lantern = true, stairs = false,
			}, rng)
		end
	end

	-- The promenade sits behind the wall, spanning over the clear gate approach.
	local walkZ = frontZ + 27
	assert(reserve(0, walkZ, 2 * hx - 28, 10, 0), "Catwalk footprint out of bounds")
	catwalk(model, cf * at(0, 0, walkZ), 2 * hx - 28)
	for _, side in { -1, 1 } do
		-- A short landing meets each tower's yard edge; only opposite end faces touch.
		local z0, z1 = frontZ + 18.8, walkZ - 4
		box(model, cf, "TowerLink", V(side * 26, 20.8, (z0 + z1) / 2), V(4, 0.4, z1 - z0), Enum.Material.WoodPlanks, PartKit.PALETTE.timber[1])
	end

	local fireFrame = cf * at(0, 0, fireZ)
	for i = 1, 10 do
		local angle = i * math.pi * 2 / 10
		box(model, fireFrame, "FireStone", V(math.cos(angle) * 4, 0.55, math.sin(angle) * 4), V(1.5, 1.1, 1.2), Enum.Material.Slate, PartKit.PALETTE.stone[i % 3 + 1], CFrame.Angles(0, angle + 0.13, 0))
	end
	local core = box(model, fireFrame, "CampfireCore", V(0, 0.9, 0), V(2.4, 1.8, 2.4), Enum.Material.Neon, C(255, 133, 41), CFrame.Angles(0, 0.19, 0))
	core.CanCollide = false
	local fireLight = Instance.new("PointLight")
	fireLight.Color, fireLight.Brightness, fireLight.Range = WARM, 1.5, 24
	fireLight.Shadows = true
	fireLight.Parent = core
	Decor.glow(core, WARM, 6)
	for _, side in { -1, 1 } do
		local f = fireFrame * at(side * 12, 0, 0) * CFrame.Angles(0, math.rad(rng:NextNumber(1, 3)), 0)
		box(model, f, "BenchSeat", V(0, 2.4, 0), V(3, 0.5, 12), Enum.Material.WoodPlanks, PartKit.PALETTE.timber[1])
		for _, z in { -4, 4 } do
			box(model, f, "BenchSupport", V(0, 1.075, z), V(2.4, 2.15, 0.8), METAL, STEEL)
		end
		crate(model, fireFrame * at(side * 9, 0, 15), rng, 0, 4)
	end
	for _, z in { -22, 22 } do
		for _, x in { -22, 22 } do
			box(model, fireFrame, "StringPole", V(x, 11, z), V(0.4, 22, 0.4), METAL, BLACK)
		end
		Decor.cable(model, fireFrame:PointToWorldSpace(V(-22, 22, z)), fireFrame:PointToWorldSpace(V(22, 22, z)), 3, BLACK, 0.12)
		for i = 1, 7 do
			local t = i / 8
			lantern(model, fireFrame, V(-22 + t * 44, 22 - 12 * t * (1 - t) - 0.8, z), false)
		end
	end
	Decor.cable(model, fireFrame:PointToWorldSpace(V(-22, 22, -22)), fireFrame:PointToWorldSpace(V(-22, 22, 22)), 2, BLACK, 0.12)
	Decor.cable(model, fireFrame:PointToWorldSpace(V(22, 22, -22)), fireFrame:PointToWorldSpace(V(22, 22, 22)), 2, BLACK, 0.12)

	-- Six yard poles plus the two retained tower fixtures: eight SpotLights, three shadows.
	for i, pos in { V(-70, 0, frontZ + 60), V(70, 0, frontZ + 60),
		V(-70, 0, -25), V(70, 0, -25), V(-75, 0, hz - 25), V(75, 0, hz - 25) } do
		if reserve(pos.X, pos.Z, 4, 4, 3) then
			box(model, cf, "FloodPole", pos + V(0, 15, 0), V(0.65, 30, 0.65), METAL, STEEL)
			flood(model, cf, pos + V(0, 31, 0), V(0, 0, fireZ), i == 3)
		end
	end

	-- Keep dedicated 14-stud front-to-back lanes in the central spine.
	reserve(-54, 0, 14, 2 * math.max(10, hz - 110), 0)
	reserve(54, 0, 14, 2 * math.max(10, hz - 110), 0)
	local pads = 0
	for _, x in { -32, 32 } do
		if reserve(x, fireZ - 105, 18, 14, 3) then
			pads += 1
			salvage(model, cf * at(x, 0, fireZ - 105), rng, pads)
		end
	end
	for _, x in { -194, -112, 112, 194, -42, 42 } do
		for _, z in { hz - 37, hz - 90, frontZ + 70, frontZ + 130, frontZ + 190 } do
			if reserve(x, z, 18, 14, 3) then
				pads += 1
				salvage(model, cf * at(x, 0, z), rng, (pads - 1) % 3 + 1)
			end
		end
	end
	-- Include houses and Decor's invisible cable anchors in the strict total budget.
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then count += 1 end
	end
	assert(count < 4000, "ScrappersBase exceeded its Part budget")
	model:SetAttribute("PartCount", count)
	model.Parent = parent
	return model
end

return ScrappersBase