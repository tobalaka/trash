--!nonstrict
-- Editor-only helper used to dress Workspace.World from the design references.
-- Not required by any game code; safe to delete once the map is final.
local CollectionService = game:GetService("CollectionService")

local B = {}

B.PALETTE = {
	slumWalls = {
		Color3.fromRGB(122, 110, 92), Color3.fromRGB(96, 104, 98), Color3.fromRGB(140, 120, 96),
		Color3.fromRGB(88, 84, 80), Color3.fromRGB(118, 96, 82), Color3.fromRGB(104, 112, 120),
		Color3.fromRGB(150, 134, 108), Color3.fromRGB(80, 92, 86),
	},
	rust = {
		Color3.fromRGB(122, 74, 46), Color3.fromRGB(96, 64, 48), Color3.fromRGB(140, 96, 60),
		Color3.fromRGB(84, 90, 92), Color3.fromRGB(110, 100, 84),
	},
	graffiti = {
		Color3.fromRGB(214, 64, 52), Color3.fromRGB(240, 196, 40), Color3.fromRGB(64, 160, 210),
		Color3.fromRGB(120, 200, 90), Color3.fromRGB(200, 90, 180), Color3.fromRGB(240, 130, 40),
	},
	patchwork = {
		Color3.fromRGB(104, 128, 112), Color3.fromRGB(150, 140, 108), Color3.fromRGB(96, 110, 120),
		Color3.fromRGB(132, 104, 84), Color3.fromRGB(120, 140, 128), Color3.fromRGB(88, 96, 90),
		Color3.fromRGB(160, 150, 120), Color3.fromRGB(110, 88, 70),
	},
}

function B.folder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

function B.part(parent, size, cf, color, material, name, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Name = name or "Part"
	p.Parent = parent
	return p
end

function B.wedge(parent, size, cf, color, material, name)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Name = name or "Wedge"
	p.Parent = parent
	return p
end

-- Vertical cylinder centred at pos.
function B.cyl(parent, height, diameter, pos, color, material, name)
	return B.part(parent, Vector3.new(height, diameter, diameter),
		CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), color, material, name or "Cylinder", Enum.PartType.Cylinder)
end

function B.ball(parent, size, cf, color, material, name)
	return B.part(parent, size, cf, color, material, name or "Ball", Enum.PartType.Ball)
end

function B.pick(rng: Random, list)
	return list[rng:NextInteger(1, #list)]
end

function B.jitter(rng: Random, c: Color3, amount: number): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.clamp(s + rng:NextNumber(-amount, amount) * 0.5, 0, 1), math.clamp(v + rng:NextNumber(-amount, amount), 0, 1))
end

-- Ground height at (x, z), from the greybox floors only. Returns nil off-map.
B.floors = {}
function B.groundY(x: number, z: number): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = B.floors
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), params)
	return hit and hit.Position.Y or nil
end

-- A wall pre-fractured into cols x rows chunks (Destructible-Walls: no runtime fracturing).
-- DestructionService should treat each tagged model as one wall and each child as a chunk.
function B.destructibleWall(parent, cf: CFrame, width: number, height: number, thickness: number, color: Color3, material, cols: number, rows: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "DestructibleWall"
	local cw, rh = width / cols, height / rows
	for c = 1, cols do
		for r = 1, rows do
			local off = Vector3.new(-width / 2 + cw * (c - 0.5), -height / 2 + rh * (r - 0.5), 0)
			local chunk = B.part(model, Vector3.new(cw, rh, thickness), cf * CFrame.new(off),
				B.jitter(rng, color, 0.04), material, "Chunk")
			chunk:SetAttribute("Col", c)
			chunk:SetAttribute("Row", r)
		end
	end
	model:SetAttribute("Width", width)
	model:SetAttribute("Height", height)
	model.Parent = parent
	CollectionService:AddTag(model, "DestructibleWall")
	return model
end

-- Rectangular shack: four walls (door gap in front), slanted corrugated roof.
function B.shack(parent, base: CFrame, w: number, d: number, h: number, rng: Random, opts)
	opts = opts or {}
	local model = Instance.new("Model")
	model.Name = opts.name or "Shack"
	local wallColor = B.pick(rng, opts.wallColors or B.PALETTE.slumWalls)
	local mat = opts.material or B.pick(rng, { Enum.Material.Concrete, Enum.Material.WoodPlanks, Enum.Material.CorrodedMetal, Enum.Material.Brick })
	local t = 1
	-- back and sides
	B.part(model, Vector3.new(w, h, t), base * CFrame.new(0, h / 2, -d / 2 + t / 2), wallColor, mat, "Wall")
	B.part(model, Vector3.new(t, h, d), base * CFrame.new(-w / 2 + t / 2, h / 2, 0), B.jitter(rng, wallColor, 0.05), mat, "Wall")
	B.part(model, Vector3.new(t, h, d), base * CFrame.new(w / 2 - t / 2, h / 2, 0), B.jitter(rng, wallColor, 0.05), mat, "Wall")
	-- front with door gap
	local door = math.min(5, w * 0.35)
	local side = (w - door) / 2
	B.part(model, Vector3.new(side, h, t), base * CFrame.new(-w / 2 + side / 2, h / 2, d / 2 - t / 2), wallColor, mat, "Wall")
	B.part(model, Vector3.new(side, h, t), base * CFrame.new(w / 2 - side / 2, h / 2, d / 2 - t / 2), wallColor, mat, "Wall")
	B.part(model, Vector3.new(door, h - 8, t), base * CFrame.new(0, h - (h - 8) / 2, d / 2 - t / 2), wallColor, mat, "Wall")
	-- window holes faked with dark panes
	if h > 10 and rng:NextNumber() < 0.7 then
		B.part(model, Vector3.new(3, 3, 0.2), base * CFrame.new(-w / 4, h * 0.6, d / 2 + 0.1), Color3.fromRGB(30, 32, 34), Enum.Material.Glass, "Window")
	end
	-- slanted roof
	local roofColor = B.pick(rng, B.PALETTE.rust)
	local tilt = math.rad(rng:NextNumber(6, 14)) * (rng:NextNumber() < 0.5 and 1 or -1)
	B.part(model, Vector3.new(w + 2, 0.6, d + 2), base * CFrame.new(0, h + 0.8, 0) * CFrame.Angles(tilt, 0, 0), roofColor, Enum.Material.CorrodedMetal, "Roof")
	-- graffiti strip
	if opts.graffiti ~= false and rng:NextNumber() < 0.45 then
		B.part(model, Vector3.new(w * rng:NextNumber(0.4, 0.8), rng:NextNumber(2, 4), 0.2),
			base * CFrame.new(rng:NextNumber(-w / 6, w / 6), rng:NextNumber(2, 4), d / 2 + 0.12), B.pick(rng, B.PALETTE.graffiti), Enum.Material.SmoothPlastic, "Graffiti")
	end
	model.Parent = parent
	return model
end

function B.junkPile(parent, pos: Vector3, radius: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "JunkPile"
	local n = math.floor(radius * 0.9)
	for _ = 1, n do
		local a, r = rng:NextNumber(0, math.pi * 2), radius * math.sqrt(rng:NextNumber())
		local hgt = (1 - r / radius) * radius * 0.45
		local p = pos + Vector3.new(math.cos(a) * r, hgt, math.sin(a) * r)
		local kind = rng:NextInteger(1, 6)
		local rot = CFrame.Angles(rng:NextNumber(-0.6, 0.6), rng:NextNumber(0, 6.28), rng:NextNumber(-0.6, 0.6))
		if kind == 1 then -- tyre
			B.part(model, Vector3.new(2, 6, 6), CFrame.new(p) * rot, Color3.fromRGB(28, 28, 30), Enum.Material.Rubber, "Tyre", Enum.PartType.Cylinder)
		elseif kind == 2 then -- fridge / cabinet
			B.part(model, Vector3.new(4, 7, 4), CFrame.new(p) * rot, B.jitter(rng, Color3.fromRGB(196, 190, 176), 0.12), Enum.Material.CorrodedMetal, "Fridge")
		elseif kind == 3 then -- AC unit
			B.part(model, Vector3.new(5, 3.5, 3), CFrame.new(p) * rot, Color3.fromRGB(170, 172, 168), Enum.Material.DiamondPlate, "ACUnit")
		elseif kind == 4 then -- sheet metal
			B.part(model, Vector3.new(rng:NextNumber(5, 10), 0.4, rng:NextNumber(4, 8)), CFrame.new(p) * rot, B.pick(rng, B.PALETTE.rust), Enum.Material.CorrodedMetal, "Sheet")
		elseif kind == 5 then -- pipe
			B.part(model, Vector3.new(rng:NextNumber(8, 16), 1.4, 1.4), CFrame.new(p) * rot, B.pick(rng, B.PALETTE.rust), Enum.Material.Metal, "Pipe", Enum.PartType.Cylinder)
		else -- trash bag
			B.ball(model, Vector3.new(4, 3.4, 4), CFrame.new(p) * rot, Color3.fromRGB(36, 38, 40), Enum.Material.Plastic, "TrashBag")
		end
	end
	-- mound underneath so pieces read as one heap
	B.ball(model, Vector3.new(radius * 2.2, radius * 0.8, radius * 2.2), CFrame.new(pos), Color3.fromRGB(58, 56, 52), Enum.Material.Ground, "Mound")
	model.Parent = parent
	return model
end

function B.powerPole(parent, pos: Vector3, h: number, lean: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "PowerPole"
	local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.Angles(lean, 0, 0)
	local wood = Color3.fromRGB(72, 60, 50)
	B.part(model, Vector3.new(1.2, h, 1.2), cf * CFrame.new(0, h / 2, 0), wood, Enum.Material.Wood, "Pole")
	B.part(model, Vector3.new(10, 0.8, 0.8), cf * CFrame.new(0, h - 2, 0), wood, Enum.Material.Wood, "CrossArm")
	model.Parent = parent
	return model, (cf * CFrame.new(0, h - 2, 0)).Position
end

function B.wire(parent, a: Vector3, b: Vector3)
	local mid = (a + b) / 2 - Vector3.new(0, (a - b).Magnitude * 0.06, 0)
	for _, seg in { { a, mid }, { mid, b } } do
		local p0, p1 = seg[1], seg[2]
		B.part(parent, Vector3.new(0.2, 0.2, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2, p1), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic, "Wire").CanCollide = false
	end
end

function B.rockSpire(parent, pos: Vector3, h: number, w: number, rng: Random, color: Color3)
	local model = Instance.new("Model")
	model.Name = "RockSpire"
	local y, cw = 0, w
	while y < h do
		local seg = rng:NextNumber(h * 0.12, h * 0.25)
		local cf = CFrame.new(pos + Vector3.new(rng:NextNumber(-cw * 0.1, cw * 0.1), y + seg / 2, rng:NextNumber(-cw * 0.1, cw * 0.1)))
			* CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, 6.28), rng:NextNumber(-0.08, 0.08))
		B.part(model, Vector3.new(cw, seg, cw * rng:NextNumber(0.7, 1)), cf, B.jitter(rng, color, 0.05), Enum.Material.Slate, "Rock")
		y += seg * 0.92
		cw *= rng:NextNumber(0.72, 0.9)
	end
	model.Parent = parent
	return model
end

function B.pine(parent, pos: Vector3, h: number, rng: Random, snowy: boolean)
	local model = Instance.new("Model")
	model.Name = "Pine"
	B.cyl(model, h * 0.35, h * 0.06, pos + Vector3.new(0, h * 0.175, 0), Color3.fromRGB(70, 52, 40), Enum.Material.Wood, "Trunk")
	local tiers = 4
	for i = 1, tiers do
		local f = (i - 1) / tiers
		local size = h * 0.42 * (1 - f * 0.7)
		local y = h * 0.22 + h * 0.75 * f
		local c = B.jitter(rng, Color3.fromRGB(46, 78, 66), 0.04)
		local cf = CFrame.new(pos + Vector3.new(0, y + size * 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		B.part(model, Vector3.new(size, size * 0.6, size), cf * CFrame.Angles(0, math.rad(45), 0), c, Enum.Material.Grass, "Needles")
		if snowy then
			B.part(model, Vector3.new(size * 0.8, size * 0.15, size * 0.8), cf * CFrame.new(0, size * 0.33, 0), Color3.fromRGB(236, 242, 248), Enum.Material.Snow, "Snow")
		end
	end
	model.Parent = parent
	return model
end

function B.palm(parent, pos: Vector3, h: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Palm"
	local lean = CFrame.Angles(rng:NextNumber(-0.25, 0.25), 0, rng:NextNumber(-0.25, 0.25))
	local segs = 5
	local top = CFrame.new(pos)
	for i = 1, segs do
		local seg = h / segs
		local cf = top * lean * CFrame.new(0, seg / 2, 0)
		B.part(model, Vector3.new(1.6 - i * 0.12, seg + 0.4, 1.6 - i * 0.12), cf, Color3.fromRGB(110, 88, 64), Enum.Material.Wood, "Trunk")
		top = cf * CFrame.new(0, seg / 2, 0)
	end
	for i = 1, 7 do
		local yaw = math.rad(i * 360 / 7 + rng:NextNumber(-15, 15))
		local leaf = top * CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(rng:NextNumber(18, 34)), 0, 0) * CFrame.new(0, 0, -h * 0.22)
		B.part(model, Vector3.new(h * 0.14, 0.4, h * 0.45), leaf, B.jitter(rng, Color3.fromRGB(58, 120, 52), 0.06), Enum.Material.Grass, "Frond")
	end
	model.Parent = parent
	return model
end

function B.roundTree(parent, pos: Vector3, h: number, rng: Random, leafColor: Color3)
	local model = Instance.new("Model")
	model.Name = "Tree"
	B.cyl(model, h * 0.55, h * 0.08, pos + Vector3.new(0, h * 0.275, 0), Color3.fromRGB(88, 66, 50), Enum.Material.Wood, "Trunk")
	for _ = 1, 3 do
		local s = h * rng:NextNumber(0.35, 0.5)
		B.part(model, Vector3.new(s, s * 0.85, s),
			CFrame.new(pos + Vector3.new(rng:NextNumber(-h * 0.15, h * 0.15), h * rng:NextNumber(0.6, 0.85), rng:NextNumber(-h * 0.15, h * 0.15)))
				* CFrame.Angles(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)),
			B.jitter(rng, leafColor, 0.06), Enum.Material.Grass, "Leaves")
	end
	model.Parent = parent
	return model
end

function B.cactus(parent, pos: Vector3, h: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Cactus"
	local g = B.jitter(rng, Color3.fromRGB(78, 128, 70), 0.05)
	B.part(model, Vector3.new(h * 0.18, h, h * 0.18), CFrame.new(pos + Vector3.new(0, h / 2, 0)), g, Enum.Material.Grass, "Stem")
	for side = -1, 1, 2 do
		if rng:NextNumber() < 0.75 then
			local y = h * rng:NextNumber(0.35, 0.6)
			local arm = h * 0.3
			B.part(model, Vector3.new(arm * 0.6, h * 0.13, h * 0.13), CFrame.new(pos + Vector3.new(side * arm * 0.35, y, 0)), g, Enum.Material.Grass, "Arm")
			B.part(model, Vector3.new(h * 0.13, arm, h * 0.13), CFrame.new(pos + Vector3.new(side * arm * 0.6, y + arm / 2, 0)), g, Enum.Material.Grass, "Arm")
		end
	end
	model.Parent = parent
	return model
end

-- Mushroom mesa: tall column with a wider faceted cap (desert reference).
function B.mesa(parent, pos: Vector3, h: number, w: number, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Mesa"
	local base = B.jitter(rng, Color3.fromRGB(176, 110, 72), 0.05)
	local cap = B.jitter(rng, Color3.fromRGB(222, 180, 132), 0.04)
	local yaw = CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	B.part(model, Vector3.new(w, h, w * 0.9), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * yaw, base, Enum.Material.Sandstone, "Column")
	B.part(model, Vector3.new(w * 1.25, h * 0.2, w * 1.15), CFrame.new(pos + Vector3.new(0, h * 0.95, 0)) * yaw * CFrame.Angles(0, 0.4, 0), cap, Enum.Material.Sandstone, "Cap")
	B.part(model, Vector3.new(w * 1.05, h * 0.12, w * 1.0), CFrame.new(pos + Vector3.new(0, h * 1.08, 0)) * yaw * CFrame.Angles(0, -0.3, 0), cap, Enum.Material.Sandstone, "Cap")
	model.Parent = parent
	return model
end

-- Scatter n points inside a rectangle, at least minGap apart, skipping off-floor spots.
function B.scatter(rng: Random, minX, maxX, minZ, maxZ, n: number, minGap: number, avoid)
	local pts = {}
	local tries = 0
	while #pts < n and tries < n * 30 do
		tries += 1
		local x, z = rng:NextNumber(minX, maxX), rng:NextNumber(minZ, maxZ)
		local ok = true
		for _, p in pts do
			if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < minGap * minGap then ok = false break end
		end
		if ok and avoid then ok = not avoid(x, z) end
		if ok then
			local y = B.groundY(x, z)
			if y then table.insert(pts, Vector3.new(x, y, z)) end
		end
	end
	return pts
end

return B
