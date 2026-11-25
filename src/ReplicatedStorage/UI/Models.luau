--!strict
--[[
	Models - tiny part-built 3D items for ViewportFrame icons (Deepwoken's "3D icons"). Each
	builder returns a fresh Model that never enters the Workspace. Parallel faces that touch are
	offset by at least 0.05 studs so nothing Z-fights in the viewport.
]]

local Models = {}

local rgb = Color3.fromRGB
local M = Enum.Material

local function part(model: Model, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): any
	local p: any = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	p.Parent = model
	return p
end

local function wedge(model: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): any
	local w: any = Instance.new("WedgePart")
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = material or M.SmoothPlastic
	w.Anchored = true
	w.CanCollide = false
	w.CastShadow = false
	w.Parent = model
	return w
end

-- Cylinders in Roblox run along X; this stands them up along Y.
local UP = CFrame.Angles(0, 0, math.rad(90))

local B = Enum.PartType.Block
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball

local builders: { [string]: (Model) -> () } = {
	Ration = function(m)
		part(m, CYL, Vector3.new(1.4, 1.8, 1.8), UP, rgb(150, 150, 146), M.Metal)
		part(m, CYL, Vector3.new(0.8, 1.86, 1.86), UP, rgb(196, 92, 52))
		part(m, CYL, Vector3.new(0.1, 1.9, 1.9), CFrame.new(0, 0.72, 0) * UP, rgb(176, 176, 170), M.Metal)
		part(m, B, Vector3.new(0.5, 0.1, 0.16), CFrame.new(0.3, 0.8, 0) * CFrame.Angles(0, 0, math.rad(-20)), rgb(200, 200, 194), M.Metal)
	end,
	Water = function(m)
		part(m, CYL, Vector3.new(2.2, 1, 1), UP, rgb(150, 210, 236), M.Glass, { Transparency = 0.25 })
		part(m, CYL, Vector3.new(0.7, 1.06, 1.06), CFrame.new(0, -0.1, 0) * UP, rgb(70, 160, 210))
		part(m, CYL, Vector3.new(0.35, 0.5, 0.5), CFrame.new(0, 1.24, 0) * UP, rgb(232, 232, 226))
	end,
	Canteen = function(m)
		part(m, CYL, Vector3.new(0.8, 2, 2), CFrame.Angles(0, math.rad(90), 0), rgb(98, 112, 72), M.Fabric)
		part(m, CYL, Vector3.new(0.86, 1.2, 1.2), CFrame.Angles(0, math.rad(90), 0), rgb(124, 138, 92), M.Fabric)
		part(m, CYL, Vector3.new(0.45, 0.45, 0.45), CFrame.new(0, 1.12, 0) * UP, rgb(160, 160, 150), M.Metal)
		part(m, B, Vector3.new(0.18, 1.2, 0.3), CFrame.new(1.02, 0.2, 0), rgb(84, 64, 44), M.Leather)
	end,
	Bandage = function(m)
		part(m, CYL, Vector3.new(1.2, 1.6, 1.6), CFrame.Angles(0, math.rad(90), 0), rgb(236, 230, 214), M.Fabric)
		part(m, CYL, Vector3.new(1.26, 0.5, 0.5), CFrame.Angles(0, math.rad(90), 0), rgb(196, 188, 170), M.Fabric)
		part(m, B, Vector3.new(1.1, 0.06, 1.4), CFrame.new(0.2, -0.82, 0.6) * CFrame.Angles(math.rad(-12), 0, 0), rgb(236, 230, 214), M.Fabric)
	end,
	Filter = function(m)
		part(m, CYL, Vector3.new(1.2, 1.7, 1.7), CFrame.Angles(0, math.rad(90), 0), rgb(70, 74, 76), M.Metal)
		part(m, CYL, Vector3.new(1.26, 1.2, 1.2), CFrame.Angles(0, math.rad(90), 0), rgb(214, 170, 60))
		part(m, CYL, Vector3.new(0.5, 0.8, 0.8), CFrame.new(0, 0, -0.8) * CFrame.Angles(0, math.rad(90), 0), rgb(60, 62, 64), M.Metal)
	end,
	ScrapBundle = function(m)
		part(m, B, Vector3.new(2, 0.3, 0.9), CFrame.Angles(0, 0, math.rad(8)), rgb(120, 96, 76), M.CorrodedMetal)
		part(m, B, Vector3.new(1.6, 0.3, 0.7), CFrame.new(0.1, 0.32, 0.1) * CFrame.Angles(0, math.rad(20), math.rad(-6)), rgb(140, 140, 136), M.Metal)
		part(m, CYL, Vector3.new(1.8, 0.4, 0.4), CFrame.new(-0.2, 0.62, -0.1) * CFrame.Angles(0, math.rad(-30), 0), rgb(176, 110, 64), M.Metal)
		part(m, B, Vector3.new(0.2, 0.9, 1.1), CFrame.new(0.4, 0.2, 0), rgb(196, 72, 40), M.Fabric)
	end,
	Residue = function(m)
		part(m, B, Vector3.new(0.8, 1.6, 0.8), CFrame.Angles(math.rad(10), math.rad(45), math.rad(8)), rgb(118, 232, 196), M.Neon, { Transparency = 0.15 })
		part(m, B, Vector3.new(0.5, 1, 0.5), CFrame.new(0.6, -0.3, 0.2) * CFrame.Angles(0, math.rad(20), math.rad(-25)), rgb(90, 200, 170), M.Glass, { Transparency = 0.2 })
		part(m, B, Vector3.new(0.4, 0.8, 0.4), CFrame.new(-0.55, -0.4, 0.1) * CFrame.Angles(0, math.rad(60), math.rad(30)), rgb(90, 200, 170), M.Glass, { Transparency = 0.2 })
	end,
	Pill = function(m)
		part(m, CYL, Vector3.new(1.2, 0.8, 0.8), CFrame.new(-0.3, 0, 0), rgb(236, 236, 230))
		part(m, CYL, Vector3.new(1.2, 0.8, 0.8), CFrame.new(0.9, 0, 0), rgb(214, 170, 60))
		part(m, BALL, Vector3.new(0.8, 0.8, 0.8), CFrame.new(-0.9, 0, 0), rgb(236, 236, 230))
		part(m, BALL, Vector3.new(0.8, 0.8, 0.8), CFrame.new(1.5, 0, 0), rgb(214, 170, 60))
	end,
	-- Relic: Umbrella (MVP). Eight sloped panels make the canopy.
	Umbrella = function(m)
		local cloth = rgb(48, 52, 60)
		local trim = rgb(222, 106, 46)
		for i = 0, 7 do
			local yaw = CFrame.Angles(0, math.rad(i * 45), 0)
			wedge(m, Vector3.new(2.1, 1.1, 2.6), yaw * CFrame.new(0, 1.85, -1.3), if i % 2 == 0 then cloth else rgb(60, 66, 76), M.Fabric)
			part(m, B, Vector3.new(0.12, 0.12, 2.75), yaw * CFrame.new(0, 1.33, -1.4) * CFrame.Angles(math.rad(-22), 0, 0), trim, M.Metal)
		end
		part(m, CYL, Vector3.new(4.6, 0.16, 0.16), CFrame.new(0, 0.2, 0) * UP, rgb(150, 150, 146), M.Metal)
		part(m, CYL, Vector3.new(0.5, 0.24, 0.24), CFrame.new(0, 2.65, 0) * UP, trim, M.Metal)
		part(m, CYL, Vector3.new(0.9, 0.3, 0.3), CFrame.new(0, -1.9, 0) * UP, rgb(84, 56, 36), M.Wood)
		part(m, CYL, Vector3.new(0.3, 0.3, 0.3), CFrame.new(0.22, -2.4, 0) * CFrame.Angles(0, 0, math.rad(30)), rgb(84, 56, 36), M.Wood)
	end,
	-- Relic: Sandals (MVP).
	Sandals = function(m)
		for i, x in { -0.75, 0.75 } do
			local base = CFrame.new(x, 0, (i - 1.5) * 0.5) * CFrame.Angles(0, math.rad(x * 8), 0)
			part(m, B, Vector3.new(1.1, 0.3, 2.8), base, rgb(120, 82, 52), M.Wood)
			part(m, B, Vector3.new(1.16, 0.16, 2.86), base * CFrame.new(0, -0.24, 0), rgb(60, 44, 32), M.Rubber)
			part(m, B, Vector3.new(1.2, 0.35, 0.25), base * CFrame.new(0, 0.3, -0.5), rgb(222, 106, 46), M.Fabric)
			part(m, B, Vector3.new(1.2, 0.35, 0.25), base * CFrame.new(0, 0.3, 0.4), rgb(222, 106, 46), M.Fabric)
		end
	end,
	-- unknown Relic in the roll pool: a sealed crate
	Mystery = function(m)
		part(m, B, Vector3.new(2, 2, 2), CFrame.new(), rgb(96, 78, 58), M.WoodPlanks)
		for _, y in { -0.7, 0.7 } do
			part(m, B, Vector3.new(2.06, 0.3, 2.06), CFrame.new(0, y, 0), rgb(70, 70, 68), M.Metal)
		end
	end,
	-- Mender's Gloves (Legendary Relic): patchwork from many odd gloves
	Gloves = function(m)
		local patches = { rgb(150, 120, 80), rgb(96, 128, 176), rgb(214, 170, 60), rgb(120, 222, 44) }
		for i, x in { -0.65, 0.65 } do
			local tilt = CFrame.new(x, 0, 0) * CFrame.Angles(0, 0, math.rad(x * -10))
			part(m, B, Vector3.new(1, 1.3, 0.5), tilt, patches[i], M.Fabric)
			part(m, B, Vector3.new(1.06, 0.3, 0.56), tilt * CFrame.new(0, -0.6, 0), patches[i + 2], M.Fabric)
			part(m, B, Vector3.new(0.4, 0.4, 0.08), tilt * CFrame.new(0.15, 0.25, -0.28), patches[3 - i], M.Fabric)
		end
	end,
	-- Push Broom (Rare Relic): a rail handle and shredded-bottle bristles
	Broom = function(m)
		part(m, CYL, Vector3.new(4.6, 0.22, 0.22), CFrame.new(0, 0.9, 0) * UP, rgb(120, 90, 60), M.Wood)
		part(m, B, Vector3.new(2.6, 0.5, 0.6), CFrame.new(0, -1.5, 0), rgb(84, 64, 44), M.Wood)
		local colors = { rgb(120, 222, 44), rgb(96, 204, 188), rgb(236, 230, 214), rgb(255, 214, 58) }
		for i = 0, 6 do
			part(m, B, Vector3.new(0.3, 0.9, 0.5), CFrame.new(-1.08 + i * 0.36, -2.15, 0), colors[i % #colors + 1])
		end
	end,
	-- Hubcap (Rare Relic): chrome disc, rubber centre, filed edge
	Hubcap = function(m)
		local face = CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.rad(20), 0, 0)
		part(m, CYL, Vector3.new(0.25, 3, 3), face, rgb(214, 220, 226), M.Metal)
		part(m, CYL, Vector3.new(0.35, 1.1, 1.1), face, rgb(40, 40, 44), M.Rubber)
		for i = 0, 4 do
			part(m, B, Vector3.new(0.1, 0.9, 0.2), face * CFrame.new(-0.18, 0, 0) * CFrame.Angles(math.rad(i * 72), 0, 0) * CFrame.new(0, 0.95, 0), rgb(160, 166, 172), M.Metal)
		end
	end,
	-- Boss Coat (Legendary Relic): seatbelt leather with scrap plates
	Coat = function(m)
		local cloth = rgb(70, 50, 90)
		part(m, B, Vector3.new(2.4, 3.4, 0.4), CFrame.new(0, -0.3, 0), cloth, M.Leather)
		part(m, B, Vector3.new(2.6, 0.5, 0.6), CFrame.new(0, 1.55, 0), rgb(40, 30, 54), M.Leather)
		for i, y in { 0.6, -0.3, -1.2 } do
			part(m, B, Vector3.new(0.9, 0.6, 0.12), CFrame.new(if i % 2 == 0 then 0.5 else -0.5, y, -0.26), rgb(150, 150, 146), M.Metal)
		end
		part(m, B, Vector3.new(0.6, 0.6, 0.12), CFrame.new(-0.55, 0.9, -0.26), rgb(110, 60, 160), M.Leather)
	end,
	Skewer = function(m)
		part(m, CYL, Vector3.new(3.2, 0.12, 0.12), CFrame.Angles(0, 0, math.rad(60)), rgb(170, 140, 90), M.Wood)
		for i = -1, 1 do
			part(m, B, Vector3.new(0.7, 0.6, 0.6), CFrame.Angles(0, 0, math.rad(60)) * CFrame.new(i * 0.75, 0, 0), if i == 0 then rgb(150, 190, 80) else rgb(160, 84, 48))
		end
	end,
	DirtyWater = function(m)
		part(m, CYL, Vector3.new(2.2, 1, 1), UP, rgb(150, 170, 120), M.Glass, { Transparency = 0.3 })
		part(m, CYL, Vector3.new(0.9, 1.06, 1.06), CFrame.new(0, -0.1, 0) * UP, rgb(96, 104, 64))
		part(m, CYL, Vector3.new(0.35, 0.5, 0.5), CFrame.new(0, 1.24, 0) * UP, rgb(120, 110, 90))
	end,
	Bottle = function(m)
		part(m, CYL, Vector3.new(2, 0.9, 0.9), UP * CFrame.Angles(math.rad(15), 0, 0), rgb(160, 210, 220), M.Glass, { Transparency = 0.35 })
		part(m, CYL, Vector3.new(0.4, 0.45, 0.45), CFrame.new(0.3, 1.1, 0) * UP, rgb(60, 140, 200))
		part(m, CYL, Vector3.new(0.6, 0.96, 0.96), CFrame.new(0, -0.1, 0) * UP, rgb(222, 106, 46))
	end,
	Can = function(m)
		part(m, CYL, Vector3.new(1.6, 1.2, 1.2), UP * CFrame.Angles(0, 0, math.rad(8)), rgb(170, 176, 182), M.Metal)
		part(m, CYL, Vector3.new(0.9, 1.26, 1.26), UP * CFrame.Angles(0, 0, math.rad(8)), rgb(90, 140, 150))
	end,
	Rag = function(m)
		part(m, B, Vector3.new(2, 0.2, 1.4), CFrame.Angles(math.rad(8), math.rad(20), 0), rgb(196, 160, 120), M.Fabric)
		part(m, B, Vector3.new(1.6, 0.2, 1.2), CFrame.new(0.2, 0.25, 0.1) * CFrame.Angles(math.rad(-6), math.rad(-15), math.rad(6)), rgb(120, 140, 170), M.Fabric)
	end,
	Glass = function(m)
		for i = 0, 3 do
			part(m, B, Vector3.new(0.9, 0.15, 0.6), CFrame.Angles(math.rad(i * 30), math.rad(i * 70), math.rad(i * 20)) * CFrame.new(0, i * 0.2, 0), rgb(130, 190, 150), M.Glass, { Transparency = 0.3 })
		end
		part(m, B, Vector3.new(1.6, 0.06, 1.4), CFrame.new(0, -0.45, 0), rgb(196, 180, 140), M.Fabric)
	end,
	Rubber = function(m)
		part(m, B, Vector3.new(2.4, 0.3, 0.8), CFrame.Angles(0, math.rad(15), math.rad(10)), rgb(36, 36, 38), M.Rubber)
		part(m, B, Vector3.new(2.2, 0.3, 0.7), CFrame.new(0, 0.32, 0.1) * CFrame.Angles(0, math.rad(-20), math.rad(-8)), rgb(46, 46, 48), M.Rubber)
	end,
	Wire = function(m)
		for i = 0, 5 do
			part(m, CYL, Vector3.new(0.14, 1.6 - i * 0.12, 1.6 - i * 0.12), CFrame.Angles(0, math.rad(90), 0) * CFrame.new(i * 0.16, 0, 0), rgb(196, 112, 60), M.Metal)
		end
	end,
	Circuit = function(m)
		part(m, B, Vector3.new(2.4, 0.15, 1.6), CFrame.Angles(math.rad(-25), 0, 0), rgb(40, 120, 70))
		part(m, B, Vector3.new(0.6, 0.2, 0.6), CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(-0.5, 0.15, 0), rgb(30, 30, 32))
		part(m, B, Vector3.new(0.3, 0.25, 0.3), CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0.6, 0.18, 0.3), rgb(214, 170, 60), M.Metal)
		part(m, B, Vector3.new(1.8, 0.2, 0.06), CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0.12, -0.5), rgb(214, 170, 60), M.Metal)
	end,
	Sludge = function(m)
		part(m, CYL, Vector3.new(1.8, 1.6, 1.6), UP, rgb(70, 70, 66), M.Metal)
		part(m, CYL, Vector3.new(0.12, 1.4, 1.4), CFrame.new(0, 0.85, 0) * UP, rgb(60, 72, 30), M.Neon)
		part(m, BALL, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0.4, 0.95, 0.2), rgb(80, 96, 40))
	end,
	Core = function(m)
		part(m, BALL, Vector3.new(1.4, 1.4, 1.4), CFrame.new(), rgb(110, 130, 70), M.Neon, { Transparency = 0.2 })
		part(m, BALL, Vector3.new(2, 2, 2), CFrame.new(), rgb(90, 96, 80), M.Glass, { Transparency = 0.6 })
	end,
	ApexCore = function(m)
		part(m, BALL, Vector3.new(1.3, 1.3, 1.3), CFrame.new(), rgb(255, 176, 48), M.Neon, { Transparency = 0.1 })
		part(m, BALL, Vector3.new(2, 2, 2), CFrame.new(), rgb(60, 62, 56), M.Glass, { Transparency = 0.55 })
		for i = 0, 3 do
			part(m, B, Vector3.new(0.3, 1.2, 0.3), CFrame.Angles(math.rad(i * 45), math.rad(i * 90), 0) * CFrame.new(0, 1.05, 0), rgb(46, 48, 50), M.Slate)
		end
	end,
	BeastCore = function(m)
		part(m, B, Vector3.new(1.4, 1.8, 1.4), CFrame.Angles(math.rad(10), math.rad(45), 0), rgb(236, 230, 214), M.Marble)
		part(m, B, Vector3.new(0.9, 1.2, 0.9), CFrame.Angles(math.rad(10), math.rad(45), 0), rgb(118, 232, 196), M.Neon)
		for _, x in { -1, 1 } do
			part(m, CYL, Vector3.new(1.4, 0.3, 0.3), CFrame.new(x * 0.9, 0.7, 0) * CFrame.Angles(0, 0, math.rad(x * 40)), rgb(196, 180, 150), M.Marble)
		end
	end,
	PurifiedAnima = function(m)
		part(m, CYL, Vector3.new(2, 1.2, 1.2), UP, rgb(200, 236, 230), M.Glass, { Transparency = 0.35 })
		part(m, CYL, Vector3.new(1.3, 0.9, 0.9), CFrame.new(0, -0.2, 0) * UP, rgb(118, 232, 196), M.Neon)
		part(m, CYL, Vector3.new(0.35, 1.3, 1.3), CFrame.new(0, 1.15, 0) * UP, rgb(96, 204, 188), M.Metal)
	end,
	HotAlloy = function(m)
		part(m, B, Vector3.new(2.4, 0.7, 1.1), CFrame.new(), rgb(150, 110, 150), M.Metal)
		part(m, B, Vector3.new(2.2, 0.5, 0.9), CFrame.new(0, 0.6, 0), rgb(222, 106, 46), M.Neon)
	end,
	Spin = function(m)
		part(m, CYL, Vector3.new(0.3, 2.4, 2.4), CFrame.Angles(0, math.rad(90), 0), rgb(176, 92, 236), M.Metal)
		part(m, CYL, Vector3.new(0.36, 1.4, 1.4), CFrame.Angles(0, math.rad(90), 0), rgb(255, 214, 58), M.Neon)
	end,
	Mask = function(m)
		part(m, BALL, Vector3.new(1.8, 2, 1.2), CFrame.new(), rgb(70, 74, 70), M.Rubber)
		part(m, CYL, Vector3.new(0.7, 0.9, 0.9), CFrame.new(0, -0.35, -0.75) * CFrame.Angles(0, math.rad(90), 0), rgb(150, 150, 146), M.Metal)
		for _, x in { -0.45, 0.45 } do
			part(m, CYL, Vector3.new(0.2, 0.62, 0.62), CFrame.new(x, 0.3, -0.52) * CFrame.Angles(0, math.rad(90), 0), rgb(150, 200, 200), M.Glass)
		end
	end,
	-- the Scrappers' mark: a purple-painted scrap tag stamped with a crew number, on a cord
	Tag = function(m)
		part(m, B, Vector3.new(1.5, 2, 0.16), CFrame.new(0, -0.2, 0), rgb(110, 60, 160), M.Metal)
		part(m, B, Vector3.new(0.9, 0.5, 0.2), CFrame.new(0, -0.35, 0), rgb(196, 196, 190), M.Metal)
		part(m, CYL, Vector3.new(0.18, 0.4, 0.4), CFrame.new(0, 0.62, 0) * CFrame.Angles(0, math.rad(90), 0), rgb(150, 150, 146), M.Metal)
		for _, x in { -0.6, 0.6 } do
			part(m, B, Vector3.new(0.12, 1.1, 0.12), CFrame.new(x * 0.6, 1.2, 0) * CFrame.Angles(0, 0, math.rad(-x * 40)), rgb(70, 52, 40), M.Fabric)
		end
	end,
	-- the Menders' mark: a teal pin pressed from a bottle cap
	Pin = function(m)
		part(m, CYL, Vector3.new(0.3, 1.9, 1.9), CFrame.Angles(0, math.rad(90), 0), rgb(96, 204, 188), M.Metal)
		for i = 0, 11 do
			local a = math.rad(i * 30)
			part(m, B, Vector3.new(0.34, 0.24, 0.36), CFrame.Angles(0, 0, a) * CFrame.new(0, 1.0, 0), rgb(70, 160, 148), M.Metal)
		end
		part(m, CYL, Vector3.new(0.34, 1, 1), CFrame.new(0, 0, -0.04) * CFrame.Angles(0, math.rad(90), 0), rgb(240, 236, 220), M.SmoothPlastic)
	end,
}

-- Relics the character actually wears use their painted meshes (ReplicatedStorage.RelicModels, made by
-- trash-art blender/gen_relics.py), posed so the side worth seeing faces the icon camera (+Z)
local MESH_ICONS: { [string]: { { name: string, cf: CFrame } } } = {
	Umbrella = { { name = "Umbrella", cf = CFrame.Angles(0, 0, math.rad(-30)) * CFrame.Angles(0, math.rad(90), 0) } },
	Broom = { { name = "Broom", cf = CFrame.Angles(0, 0, math.rad(-30)) } },
	Gloves = {
		{ name = "GloveR", cf = CFrame.new(-0.72, 0, 0) * CFrame.Angles(0, math.pi, 0) },
		{ name = "GloveL", cf = CFrame.new(0.72, 0, 0) * CFrame.Angles(0, math.pi, 0) },
	},
	Sandals = {
		{ name = "Sandal", cf = CFrame.new(-0.7, 0, 0) * CFrame.Angles(math.rad(-25), math.pi, 0) },
		{ name = "Sandal", cf = CFrame.new(0.7, 0, 0.3) * CFrame.Angles(math.rad(-25), math.pi, 0) },
	},
	Hubcap = { { name = "Hubcap", cf = CFrame.Angles(0, math.rad(-90), 0) } },
	Coat = { { name = "Coat", cf = CFrame.new() } },
}

local function fromMeshes(m: Model, list: { { name: string, cf: CFrame } }): boolean
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("RelicModels")
	if not folder then
		return false
	end
	for _, item in list do
		local t = folder:FindFirstChild(item.name)
		if not (t and t:IsA("Model")) then
			return false
		end
	end
	for _, item in list do
		local copy = (folder:FindFirstChild(item.name) :: Model):Clone()
		copy:PivotTo(item.cf)
		for _, p in copy:GetDescendants() do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.CastShadow = false
				p.Parent = m
			end
		end
		copy:Destroy()
	end
	return true
end

function Models.make(id: string): Model
	local m = Instance.new("Model")
	m.Name = id
	local icon = MESH_ICONS[id]
	if icon and fromMeshes(m, icon) then
		return m
	end
	local b = builders[id] or builders.Mystery
	b(m)
	return m
end

function Models.has(id: string): boolean
	return builders[id] ~= nil
end

return Models
