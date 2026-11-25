--!strict
--[[
	HQArt.Weathering - one-off damage decals scattered at random spots on random walls.

	The painted wall tiles (HQArt.Surfaces) are deliberately uniform: anything recognisable inside a
	tiling map repeats every few studs (user, 2026-10-24: "the rip thing for the walls is repeated
	everywhere ... just randomness at some places"). The recognisable features live here instead:
	plaster rips showing brick, cracks, water stains, rust runs, moss at the base, torn posters.

	Each decal sits on an invisible carrier Part 0.03 studs off the wall's OUTER face (the side facing away
	from the building's centre), always inside one wall strip so it never hangs over a window or a corner.
	Carriers cost no physics (no collide/query/touch/shadow) and live in a "HQ_Weathering" folder inside
	their building, so a MapGen rebuild removes them with the building. The RNG is seeded from each
	building's position, so a re-run puts the same marks in the same places.

	  require(game.ServerStorage.HQArt.Weathering).apply(workspace.World)  -> count
	  require(game.ServerStorage.HQArt.Weathering).remove(workspace.World)
]]

local Weathering = {}

local IDS = {
	rip = { 84667704580131, 116090330252919, 107466515428933 },
	crack = { 98128601410763, 95163857829263, 78163499247183 },
	stain = { 137625347771578, 139669523230022 },
	rust = { 122142403131186, 105975128422881 },
	soot = { 86956759053079 },
	moss = { 88007582280622 },
	poster = { 127494270184175, 95580735366414 },
}

-- kind weights per wall material, and decal sizes in studs (w range, aspect h/w, where on the wall)
local BY_MATERIAL: { [Enum.Material]: { { string | number } } } = {
	[Enum.Material.Plaster] = { { "rip", 34 }, { "crack", 24 }, { "stain", 20 }, { "poster", 14 }, { "moss", 8 } },
	[Enum.Material.Brick] = { { "crack", 30 }, { "stain", 36 }, { "poster", 22 }, { "moss", 12 } },
	[Enum.Material.CorrodedMetal] = { { "rust", 58 }, { "stain", 26 }, { "poster", 16 } },
	[Enum.Material.Concrete] = { { "crack", 35 }, { "stain", 45 }, { "moss", 20 } },
}

local SHAPE = {
	rip = { w = { 3.2, 6.0 }, aspect = 0.85, place = "any", spin = 12 },
	crack = { w = { 2.5, 4.5 }, aspect = 1.5, place = "any", spin = 20 },
	stain = { w = { 4.0, 7.0 }, aspect = 1.25, place = "top", spin = 0 },
	rust = { w = { 3.0, 5.5 }, aspect = 1.3, place = "top", spin = 0 },
	soot = { w = { 3.0, 4.5 }, aspect = 1.2, place = "any", spin = 0 },
	moss = { w = { 4.0, 7.5 }, aspect = 0.55, place = "bottom", spin = 0 },
	poster = { w = { 2.2, 3.2 }, aspect = 1.0, place = "eye", spin = 6 },
}

local FOLDER = "HQ_Weathering"
local WALL_NAMES = { Wall = true, TowerWall = true }

local function pickWeighted(rng: Random, list: { { string | number } }): string
	local total = 0
	for _, e in list do
		total += e[2] :: number
	end
	local r = rng:NextNumber() * total
	for _, e in list do
		r -= e[2] :: number
		if r <= 0 then
			return e[1] :: string
		end
	end
	return list[1][1] :: string
end

-- The wall's outer face: thin axis, signed away from the building centre. Returns the face frame
-- (right, up, outward) and the face's width/height, or nil for parts that aren't upright slabs.
local function outerFace(p: BasePart, centre: Vector3): (CFrame?, number, number)
	local cf, s = p.CFrame, p.Size
	local axes = { { cf.RightVector, s.X }, { cf.UpVector, s.Y }, { -cf.LookVector, s.Z } }
	table.sort(axes, function(a, b)
		return a[2] < b[2]
	end)
	local n, thick = axes[1][1] :: Vector3, axes[1][2] :: number
	if math.abs(n.Y) > 0.3 then
		return nil, 0, 0 -- floors, roofs, sills: not a wall face
	end
	local a1, a2 = axes[2], axes[3]
	local upA, sideA
	if math.abs((a1[1] :: Vector3).Y) > math.abs((a2[1] :: Vector3).Y) then
		upA, sideA = a1, a2
	else
		upA, sideA = a2, a1
	end
	local up = upA[1] :: Vector3
	if up.Y < 0 then
		up = -up
	end
	local out = n
	if (p.Position - centre):Dot(n) < 0 then
		out = -n
	end
	-- right-handed: right x up must equal the Z column (-out). up:Cross(out) built a MIRRORED frame (review 4: one
	-- carrier came out facing into its wall in Play; all 843 had Right x Up = +Look)
	local right = out:Cross(up)
	local facePos = p.Position + out * (thick / 2)
	return CFrame.fromMatrix(facePos, right, up, -out), sideA[2] :: number, upA[2] :: number
end

-- parts a mark must never cover (review 1: one poster sat over a window pane)
local KEEP_CLEAR = { Pane = true, Door = true, Shutter = true, Awning = true, Sign = true, Window = true }

local function blocked(model: Model, cf: CFrame, w: number, h: number): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { model }
	for _, p in workspace:GetPartBoundsInBox(cf, Vector3.new(w, h, 0.8), params) do
		if KEEP_CLEAR[p.Name] then
			return true
		end
	end
	return false
end

local function carrier(parent: Instance, face: CFrame, x: number, y: number, w: number, h: number, spin: number, image: number, depth: number, tint: Color3)
	local part = Instance.new("Part")
	part.Name = "Decal"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(w, h, 0.05)
	-- face frame: X right, Y up, -Z outward (so the carrier's Front face looks out from the wall)
	part.CFrame = face * CFrame.new(x, y, -(0.03 + 0.025 + depth)) * CFrame.Angles(0, 0, math.rad(spin))
	local d = Instance.new("Decal")
	d.Face = Enum.NormalId.Front
	d.Texture = "rbxassetid://" .. image
	d.Color3 = tint
	d.Parent = part
	part.Parent = parent
end

local function decorate(model: Model, rng: Random): number
	local cf, size = model:GetBoundingBox()
	local centre = cf.Position
	local groundY = cf.Y - size.Y / 2
	local walls: { { part: BasePart, face: CFrame, w: number, h: number } } = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and WALL_NAMES[p.Name] and BY_MATERIAL[p.Material] and p.Transparency < 0.5 then
			local face, w, h = outerFace(p, centre)
			if face and w >= 5 and h >= 5 then
				table.insert(walls, { part = p, face = face, w = w, h = h })
			end
		end
	end
	if #walls == 0 then
		return 0
	end
	-- 0-3 marks per building, most buildings get one or two
	local roll = rng:NextNumber()
	local count = if roll < 0.2 then 0 elseif roll < 0.6 then 1 elseif roll < 0.88 then 2 else 3
	local folder: Folder? = nil
	local used: { [BasePart]: number } = {}
	local usedImg: { [number]: boolean } = {} -- never the same mark twice on one building (review 1: 61 did)
	local placed = 0
	for _ = 1, count * 3 do
		if placed >= count then
			break
		end
		local wall = walls[rng:NextInteger(1, #walls)]
		local depth = 0.004 * (used[wall.part] or 0) -- a second mark on one strip sits a hair further out
		local kind = pickWeighted(rng, BY_MATERIAL[wall.part.Material])
		local sh = SHAPE[kind]
		local w = rng:NextNumber(sh.w[1], sh.w[2])
		local h = w * sh.aspect
		local margin = 0.35
		local spin = rng:NextNumber(-sh.spin, sh.spin)
		-- a tilted mark needs the room of its rotated box, or a corner hangs past the wall's edge
		local c, sn = math.abs(math.cos(math.rad(spin))), math.abs(math.sin(math.rad(spin)))
		local function ext(ww: number, hh: number): (number, number)
			return ww * c + hh * sn, ww * sn + hh * c
		end
		local ew, eh = ext(w, h)
		if ew > wall.w - 2 * margin or eh > wall.h - 2 * margin then
			local k = math.min((wall.w - 2 * margin) / ew, (wall.h - 2 * margin) / eh)
			w, h = w * k, h * k
			ew, eh = ext(w, h)
			if w < sh.w[1] * 0.7 then
				continue
			end
		end
		local faceBottom = (wall.face.Position.Y - wall.h / 2) - groundY
		if kind == "moss" and faceBottom > 2.5 then
			continue -- moss only grows on the ground floor
		end
		if kind == "poster" and faceBottom > 4 then
			continue -- posters are put up at street level
		end
		local x = rng:NextNumber(-wall.w / 2 + margin + ew / 2, wall.w / 2 - margin - ew / 2)
		local yLo, yHi = -wall.h / 2 + margin + eh / 2, wall.h / 2 - margin - eh / 2
		local y
		if sh.place == "top" then
			y = yHi - rng:NextNumber(0, 0.6)
		elseif sh.place == "bottom" then
			y = yLo
		elseif sh.place == "eye" then
			y = math.clamp(-wall.h / 2 + 5.5, yLo, yHi)
		else
			y = rng:NextNumber(yLo, yHi)
		end
		if not folder then
			local f = Instance.new("Folder")
			f.Name = FOLDER
			f.Parent = model
			folder = f
		end
		local list = IDS[kind]
		local free = {}
		for _, id in list do
			if not usedImg[id] then
				table.insert(free, id)
			end
		end
		if #free == 0 then
			continue
		end
		local img = free[rng:NextInteger(1, #free)]
		if blocked(model, wall.face * CFrame.new(x, y, 0), ew, eh) then
			continue
		end
		-- per-mark colour drift: no two copies of one decal read identical
		local tint = Color3.fromHSV(rng:NextNumber(0.05, 0.12), rng:NextNumber(0, 0.12), rng:NextNumber(0.82, 1.0))
		carrier(folder :: Folder, wall.face, x, y, w, h, spin, img, depth, tint)
		usedImg[img] = true
		used[wall.part] = (used[wall.part] or 0) + 1
		placed += 1
	end
	return placed
end

local function buildings(root: Instance): { Model }
	local out = {}
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and (m.Name == "House" or m.Name == "Shop" or m:FindFirstChild("Wall")) then
			-- only the outermost model that owns walls directly
			local owns = false
			for _, c in m:GetChildren() do
				if c:IsA("BasePart") and WALL_NAMES[c.Name] then
					owns = true
					break
				end
			end
			if owns then
				table.insert(out, m)
			end
		end
	end
	return out
end

function Weathering.remove(root: Instance)
	for _, f in root:GetDescendants() do
		if f:IsA("Folder") and f.Name == FOLDER then
			f:Destroy()
		end
	end
end

function Weathering.apply(root: Instance): number
	Weathering.remove(root)
	local total = 0
	for i, m in buildings(root) do
		local p = m:GetPivot().Position
		local rng = Random.new(math.floor(p.X * 7 + p.Z * 13 + p.Y * 3) % 2147483647)
		total += decorate(m, rng)
		if i % 60 == 0 then
			task.wait()
		end
	end
	return total
end

return Weathering
