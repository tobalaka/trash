--!strict
--[[
	Structures.Nature - trees and ruins built from plain Parts, after the reference world's
	redwoods (Map/Trees/RedwoodTree_*): a dark wood trunk carrying tiers of flat, stacked,
	dark-green slabs, ~200 studs tall. Here the jungle's "enormous trees" go further: trunks of
	stacked blocks 20-30 studs thick, buttress roots, canopies 120-220 studs across.

	Z-fighting discipline (MapGen.ZFight):
	  * every horizontal face of a tree (trunk segment ends, slab tops and bottoms) sits on the
	    tree's own height lattice: a 0.5 grid shifted by the tree's `phase`, each level used once.
	    Neighbouring trees get different phases, so overlapping canopies never share a plane;
	  * a trunk segment is two blocks, square and turned 45 degrees; the turned one is inset
	    0.13 at both ends (off every lattice) so its ends are never level with anything;
	  * every canopy slab has its own yaw;
	  * roots, branches and vines are tilted, never parallel to anything.

	Local space: origin at the ground under the trunk centre.
]]

local PartKit = require(script.Parent.Parent.PartKit)

local Nature = {}

local C = Color3.fromRGB
Nature.WOOD = { C(97, 83, 80), C(84, 70, 64), C(108, 92, 84) } -- reference trunk colours
Nature.LEAF = { C(48, 56, 48), C(51, 61, 54), C(46, 55, 49), C(58, 70, 52) } -- reference grass blocks

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

export type TreeSpec = { height: number, trunk: number, canopy: number, tiers: number, phase: number? }

-- An enormous tree. Returns the Model (anchored, collidable trunk; canopy collides too, so
-- players can stand on it like the reference's canopies).
function Nature.tree(parent: Instance, cf: CFrame, spec: TreeSpec, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "GiantTree"
	local wood = pick(rng, Nature.WOOD)
	local H, W = spec.height, spec.trunk
	local phase = spec.phase or 0
	local used: { [number]: boolean } = {}
	-- snap a height to this tree's lattice, taking the next free level if it is used
	local function lat(y: number): number
		local k = math.floor((y - phase) / 0.5 + 0.5)
		while used[k] do
			k += 1
		end
		used[k] = true
		return k * 0.5 + phase
	end
	-- trunk: tapering segments, each a square block plus a 45-degree block 0.3 shorter
	local segs = math.max(3, math.floor(H / 28))
	local y = lat(-0.4) -- sunk into the ground cap
	for i = 1, segs do
		local t = (i - 1) / segs
		local w = W * (1 - 0.45 * t)
		local y1 = lat(y + H / segs)
		local h = y1 - y
		local twist = CFrame.Angles(0, math.rad(rng:NextNumber(-6, 6)), 0) -- each segment turned a little
		PartKit.part(m, cf, CFrame.new(0, y + h / 2, 0) * twist, Vector3.new(w, h, w), Enum.Material.Wood, wood, "Trunk")
		-- the turned block is inset 0.13 at both ends: never level with a lattice face
		PartKit.part(m, cf, CFrame.new(0, y + h / 2, 0) * twist * CFrame.Angles(0, math.rad(45), 0), Vector3.new(w * 0.92, h - 0.26, w * 0.92), Enum.Material.Wood, wood, "Trunk")
		y = y1
	end
	-- buttress roots: long blocks leaning out from the base
	for k = 1, rng:NextInteger(4, 6) do
		local a = (k + rng:NextNumber(-0.3, 0.3)) / 6 * 2 * math.pi
		local len = W * rng:NextNumber(1.4, 2.2)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local foot = dir * (W * 0.5 + len * 0.45)
		local top = dir * (W * 0.3) + Vector3.new(0, W * rng:NextNumber(0.9, 1.4), 0)
		PartKit.part(m, cf, CFrame.lookAt((foot + top) / 2, top), Vector3.new(W * 0.28, W * 0.18 + 0.05 * k, (top - foot).Magnitude + 2), Enum.Material.Wood, wood, "Root")
	end
	-- canopy tiers: from about 55% of the height to the top, each tier narrower, 2-3 slabs each
	local leafCount = 0
	for tier = 1, spec.tiers do
		local t = (tier - 1) / math.max(1, spec.tiers - 1)
		local ty = H * (0.55 + 0.45 * t)
		local r = spec.canopy * (1 - 0.55 * t) / 2
		for s = 1, rng:NextInteger(2, 3) do
			leafCount += 1
			local thick = rng:NextNumber(5, 9)
			local off = Vector3.new(rng:NextNumber(-0.25, 0.25) * r, 0, rng:NextNumber(-0.25, 0.25) * r)
			-- bottom and top on the tree's lattice (unique levels), own yaw
			local yc = ty + 0.37 * leafCount
			local y0 = lat(yc - thick / 2)
			local y1 = lat(math.max(yc + thick / 2, y0 + 1))
			-- a few degrees of tilt as well: overlapping canopies of two trees can never lie flat
			-- in one plane (the reference's slabs sit a little askew too)
			local lcf = CFrame.new(off.X, (y0 + y1) / 2, off.Z) * CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-4, 4)))
			PartKit.part(m, cf, lcf, Vector3.new(r * rng:NextNumber(1.3, 2), y1 - y0, r * rng:NextNumber(1.3, 2)), Enum.Material.Grass, pick(rng, Nature.LEAF), "Leaves")
		end
		-- a branch reaching from the trunk into the tier
		local a = rng:NextNumber(0, 2 * math.pi)
		local from = Vector3.new(0, ty - H * 0.12, 0)
		local to = Vector3.new(math.cos(a) * r * 0.7, ty, math.sin(a) * r * 0.7)
		PartKit.part(m, cf, CFrame.lookAt((from + to) / 2, to), Vector3.new(W * 0.22 + 0.03 * tier, W * 0.22, (to - from).Magnitude), Enum.Material.Wood, wood, "Branch")
	end
	-- vines hanging from the lowest tier
	for k = 1, rng:NextInteger(3, 6) do
		local a = rng:NextNumber(0, 2 * math.pi)
		local r = spec.canopy * rng:NextNumber(0.15, 0.4)
		local top = Vector3.new(math.cos(a) * r, H * 0.55, math.sin(a) * r)
		local len = rng:NextNumber(H * 0.2, H * 0.45)
		PartKit.part(m, cf, CFrame.new(top - Vector3.new(0, len / 2, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, math.rad(rng:NextNumber(-4, 4))), Vector3.new(0.5 + 0.02 * k, len, 0.5 + 0.02 * k), Enum.Material.Grass, C(58, 78, 50), "Vine", { collide = false, shadow = false })
	end
	m.Parent = parent
	return m
end

-- A smaller jungle tree: same build, quicker to read from a distance.
function Nature.smallTree(parent: Instance, cf: CFrame, rng: Random, phase: number?): Model
	return Nature.tree(parent, cf, { height = rng:NextNumber(45, 80), trunk = rng:NextNumber(5, 8), canopy = rng:NextNumber(40, 70), tiers = 2, phase = phase }, rng)
end

-- Stone gateway with glyph pillars (a jungle gate).
function Nature.ruinGate(parent: Instance, cf: CFrame, rng: Random): Model
	local m = Instance.new("Model")
	m.Name = "JungleGate"
	local stone, dark = C(122, 120, 108), C(92, 92, 84)
	local w, h = 34, 32
	for _, sx in { -1, 1 } do
		-- pillar of three blocks, each a little narrower; carved glyph slabs on the front
		local x = sx * (w / 2 + 6)
		PartKit.part(m, cf, CFrame.new(x, 8, 0), Vector3.new(12, 16, 12), Enum.Material.Slate, stone, "Pillar")
		PartKit.part(m, cf, CFrame.new(x, 16 + 7, 0), Vector3.new(11, 14, 11), Enum.Material.Slate, stone, "Pillar")
		PartKit.part(m, cf, CFrame.new(x, 30 + 3, 0), Vector3.new(12.6, 6, 12.6), Enum.Material.Slate, dark, "Pillar")
		for g = 0, 3 do
			-- glyphs: small raised slabs, each 0.1 deeper than the last, two per block and kept
			-- inside their block's height (block 1: 0-16, block 2: 16-30)
			local gy = ({ 4.5, 11, 20, 26 })[g + 1]
			local depth = 0.3 + 0.1 * g
			-- tilted a little in the wall plane: its sides are never parallel to the pillar's
			PartKit.part(m, cf, CFrame.new(x + rng:NextNumber(-2, 2), gy, -(g < 2 and 6 or 5.5) - depth / 2) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(1.5, 4) * (g % 2 == 0 and 1 or -1))), Vector3.new(rng:NextNumber(3, 5), rng:NextNumber(2.5, 3.5), depth), Enum.Material.Slate, dark, "Glyph", { collide = false, shadow = false })
		end
	end
	PartKit.part(m, cf, CFrame.new(0, h + 2.5, 0), Vector3.new(w + 26, 5, 14), Enum.Material.Slate, stone, "Lintel")
	PartKit.part(m, cf, CFrame.new(0, h + 5 + 2, 0), Vector3.new(w + 16, 4, 11), Enum.Material.Slate, dark, "Lintel")
	-- moss over the top: tilted grass slabs
	for k = 1, 4 do
		PartKit.part(m, cf, CFrame.new(rng:NextNumber(-w / 2, w / 2), h + 9 + 0.6 * k, rng:NextNumber(-3, 3)) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), math.rad(rng:NextNumber(0, 90)), math.rad(rng:NextNumber(-8, 8))), Vector3.new(rng:NextNumber(8, 16), 1.2, rng:NextNumber(6, 10)), Enum.Material.Grass, pick(rng, Nature.LEAF), "Moss", { collide = false })
	end
	m.Parent = parent
	return m
end

return Nature
