--!strict
--[[
	HQArt.LeafFall - leaves drifting down from the jungle canopies at some spots (user 2026-10-24: "vfx particle rain
	of little leaves at some spots").

	About a third of the swapped jungle trees (seeded per tree, bigger trees more likely) get an invisible carrier
	under their crown core with one ParticleEmitter: a painted leaf tumbling as a 4x4 flipbook (tools/leaf_factory.py
	leaf_fall.png: the leaf turns edge-on and back while it rolls), slow fall, a sideways drift that the drag keeps
	gentle, random spin, a short fade at the end. A few trees get a heavier fall so the forest isn't uniform.
	Carriers cost nothing physical (no collide / query / touch / shadow) and live in Workspace.World.Jungle.HQ_LeafFall.

	Review 2: a box inside the canopy (30-200 studs up) let the leaves fade long before they reached eye level. The box
	now spans 6..26 studs above the real ground under the crown (or up to the crown's underside when that is lower),
	and the lifetime is the fall time from the top of the box at ~1.5 studs/s, so leaves drift past the player and
	settle at the floor.

	Review 5: Roblox particle Drag is a HALF-LIFE (speed halves every 1/Drag s), so the decay rate is Drag * ln 2, not
	Drag: -0.7 gravity against 0.55 drag settles at 1.84 studs/s, not 1.27, and the leaves sank into the floor. The
	gravity is now FALL * Drag * ln 2, so a leaf launched at FALL keeps exactly FALL; the wind drift is a slow 0.25 studs/s
	and the floor test samples the ground where the drift carries the box, not only under it.

	  require(game.ServerStorage.HQArt.LeafFall).apply() -> emitters
	  require(game.ServerStorage.HQArt.LeafFall).remove()
]]

local LeafFall = {}

local LEAF = "rbxassetid://133474031226167"
local FOLDER = "HQ_LeafFall"

local function folder(): Folder
	local j = workspace.World.Jungle
	local f = j:FindFirstChild(FOLDER)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER
		f.Parent = j
	end
	return f :: Folder
end

function LeafFall.remove()
	local j = workspace:FindFirstChild("World") and workspace.World:FindFirstChild("Jungle")
	local f = j and j:FindFirstChild(FOLDER)
	if f then
		f:Destroy()
	end
end

local FALL = 1.27 -- studs/s, constant: launched at the terminal speed of the gravity below
local DRAG = 0.55
local K = DRAG * math.log(2) -- Drag is a half-life: velocity decays at Drag * ln 2 per second (review 5, measured)
local DRIFT = 0.25 -- studs/s sideways terminal speed (wind)
-- a leaf's centre ends this far above the highest floor under its cell; it shrinks to half as it fades, so its
-- lower edge comes down onto the floor instead of vanishing over it (review 7: 1.0 = knee height; review 8: 0.6
-- still left every leaf 0.42+ clear of the ground)
local MARGIN = 0.3
local CELL = 8 -- studs: the canopy footprint is tested in cells this size
local FLAT = 1.0 -- max floor variation under a cell / an emitter, launch to drift end (1.5 spread the landings)

-- sideways distance a leaf drifts in t seconds (starts at 0, eases up to DRIFT with time constant 1/K)
local function driftAfter(t: number): number
	return DRIFT * (t - (1 - math.exp(-K * t)) / K)
end

local function emitter(parent: BasePart, rng: Random, heavy: boolean, area: number, top: number, drift: number)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Leaves"
	pe.Texture = LEAF
	pe.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	pe.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	pe.FlipbookFramerate = NumberRange.new(5, 9)
	pe.FlipbookStartRandom = true
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.EmissionDirection = Enum.NormalId.Bottom
	-- per rectangle (a tree has up to 4): ~150 leaves/s over the whole jungle, a few dozen in view under a tree
	pe.Rate = math.clamp(area / 1200, 0.3, 1.6) * (if heavy then 2.5 else 1)
	-- constant fall at the terminal speed: the lifetime is the drop to just above the ground (review 4: launching
	-- slower than terminal and fading from 85% of life made them vanish over the players' heads)
	pe.Lifetime = NumberRange.new(math.max(top / FALL - 0.08, 1), top / FALL + 0.08)
	pe.Speed = NumberRange.new(FALL) -- launch AT the terminal speed, so the fall is a constant 1.27 studs/s
	pe.SpreadAngle = Vector2.new(0, 0) -- straight down at launch; the sideways drift comes from the acceleration
	-- gravity exactly balances the drag at FALL, sideways settles at DRIFT (Acceleration is in world space)
	pe.Acceleration = Vector3.new(math.cos(drift) * DRIFT * K, -FALL * K, math.sin(drift) * DRIFT * K)
	pe.Drag = DRAG
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-45, 45)
	local size = rng:NextNumber(1.2, 1.6)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(0.95, size),
		NumberSequenceKeypoint.new(1, size * 0.5),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.04, 0),
		NumberSequenceKeypoint.new(0.95, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- fresh green high up, a little yellower by the time it reaches the floor
	pe.Color = ColorSequence.new(Color3.fromRGB(205, 225, 160), Color3.fromRGB(235, 220, 150))
	pe.LightInfluence = 1
	pe.Orientation = Enum.ParticleOrientation.FacingCamera
	pe.Parent = parent
end

function LeafFall.apply(): number
	LeafFall.remove()
	local f = folder()
	local n = 0
	local trees = {}
	for _, m in workspace.World:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("HQ") and m:GetAttribute("ReplacedAsset") == "GiantTree" then
			table.insert(trees, m)
		end
	end
	-- ground under the canopy: MapGen's ground and water only (review 3: the old ray ignored the non-colliding
	-- water slabs and dropped leaves into two rivers)
	-- everything solid under the canopy counts as the floor: ground, water and props like logs / roots / ruins
	-- (review 4: five boxes dropped leaves through props); the trees themselves and the emitters don't
	local skip: { Instance } = { f }
	for _, t in trees do
		table.insert(skip, t)
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = skip
	rp.RespectCanCollide = false
	local water = workspace.Ground:FindFirstChild("Water")
	local function under(x: number, z: number, from: number): (number?, boolean)
		local hit = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -800, 0), rp)
		if not hit then
			return nil, false
		end
		return hit.Position.Y, (water ~= nil and hit.Instance:IsDescendantOf(water))
	end
	for _, m in trees do
		local p = m:GetPivot().Position
		local rng = Random.new(math.floor(math.abs(p.X * 23 + p.Z * 11)) % 2147483647 + 7)
		local core = m:FindFirstChild("Core") :: BasePart?
		local cf, size
		if core then
			cf, size = core.CFrame, core.Size
		else
			cf, size = m:GetBoundingBox()
		end
		local _, msize = m:GetBoundingBox()
		local chance = math.clamp(0.22 + msize.Y / 600, 0.25, 0.55)
		if rng:NextNumber() > chance then
			continue
		end
		-- review 6: one box per tree let a high spot under one corner set the lifetime for the whole box (leaves ended
		-- 3-6 studs up), its 3x3 floor samples (37 studs apart) missed a rock, and the box sat on the trunk (6% of
		-- the leaves passed through trunk / limb colliders). Now the canopy footprint is a grid of CELL-stud cells;
		-- a cell is kept only when the floor under it AND along the drift varies <= FLAT, no water, and nothing solid
		-- (tree colliders, rocks, logs, ruins) stands in its fall column. Kept cells merge into a few rectangles.
		local dir = rng:NextNumber(0, 2 * math.pi)
		local reach = driftAfter(26 / FALL + 0.3)
		local dx, dz = math.cos(dir) * reach, math.sin(dir) * reach
		local w, d = size.X * 0.7, size.Z * 0.7
		local nx, nz = math.max(1, math.ceil(w / CELL)), math.max(1, math.ceil(d / CELL))
		local cw, cd = w / nx, d / nz
		local x0, z0 = cf.X - w / 2, cf.Z - d / 2
		local cells = {}
		local treeMax = -math.huge
		for i = 1, nx do
			cells[i] = {}
			for j = 1, nz do
				local cx, cz = x0 + (i - 0.5) * cw, z0 + (j - 0.5) * cd
				local hi_, lo_, ok = -math.huge, math.huge, true
				for _, fr in { 0, 0.5, 1 } do
					for _, o in { { 0, 0 }, { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 } } do
						local y, isWater = under(cx + o[1] * cw + dx * fr, cz + o[2] * cd + dz * fr, cf.Y)
						if not y or isWater then
							ok = false
						else
							hi_, lo_ = math.max(hi_, y), math.min(lo_, y)
						end
					end
				end
				ok = ok and hi_ - lo_ <= FLAT
				cells[i][j] = if ok then { hi = hi_, lo = lo_ } else false
				if ok then
					treeMax = math.max(treeMax, hi_)
				end
			end
		end
		if treeMax == -math.huge then
			continue
		end
		local hi = math.min(treeMax + 26, cf.Y - size.Y * 0.5)
		if hi - treeMax < 10 then
			continue
		end
		-- nothing solid in a kept cell's fall column (from just above its floor to its launch slice, launch to drift
		-- end): tree colliders, rocks, logs, ruins and terrain blocks (an overhanging terrace). Water never collides.
		local op = OverlapParams.new()
		op.FilterType = Enum.RaycastFilterType.Exclude
		op.FilterDescendantsInstances = { f }
		op.RespectCanCollide = true
		for i = 1, nx do
			for j = 1, nz do
				local c = cells[i][j]
				if c then
					local cx, cz = x0 + (i - 0.5) * cw + dx / 2, z0 + (j - 0.5) * cd + dz / 2
					local bot = c.hi + 0.3
					local top = math.min(hi, c.hi + 26 + FLAT)
					local box = Vector3.new(cw + math.abs(dx) + 1.6, math.max(top - bot, 0.5), cd + math.abs(dz) + 1.6)
					if #workspace:GetPartBoundsInBox(CFrame.new(cx, (top + bot) / 2, cz), box, op) > 0 then
						cells[i][j] = false
					end
				end
			end
		end
		-- merge kept cells into rectangles: runs along z per column, then neighbouring columns with the same run
		local rects = {}
		local used = {}
		for i = 1, nx do
			used[i] = {}
		end
		for i = 1, nx do
			for j = 1, nz do
				if cells[i][j] and not used[i][j] then
					-- grow while the merged floor stays within FLAT
					local rhi, rlo = cells[i][j].hi, cells[i][j].lo
					local j1 = j
					while j1 + 1 <= nz do
						local c = cells[i][j1 + 1]
						if not c or used[i][j1 + 1] or math.max(rhi, c.hi) - math.min(rlo, c.lo) > FLAT then
							break
						end
						rhi, rlo = math.max(rhi, c.hi), math.min(rlo, c.lo)
						j1 += 1
					end
					local i1 = i
					local function colOk(ii: number): boolean
						local h, l = rhi, rlo
						for jj = j, j1 do
							local c = cells[ii][jj]
							if not c or used[ii][jj] then
								return false
							end
							h, l = math.max(h, c.hi), math.min(l, c.lo)
						end
						if h - l > FLAT then
							return false
						end
						rhi, rlo = h, l
						return true
					end
					while i1 + 1 <= nx and colOk(i1 + 1) do
						i1 += 1
					end
					for ii = i, i1 do
						for jj = j, j1 do
							used[ii][jj] = true
						end
					end
					table.insert(rects, { i0 = i, i1 = i1, j0 = j, j1 = j1, hi = rhi, lo = rlo })
				end
			end
		end
		table.sort(rects, function(a, b)
			return (a.i1 - a.i0 + 1) * (a.j1 - a.j0 + 1) > (b.i1 - b.i0 + 1) * (b.j1 - b.j0 + 1)
		end)
		local heavy = rng:NextNumber() < 0.15
		for k = 1, math.min(#rects, 4) do
			local r = rects[k]
			local rw, rd = (r.i1 - r.i0 + 1) * cw, (r.j1 - r.j0 + 1) * cd
			if rw * rd < 40 or r.hi - r.lo > FLAT then
				continue
			end
			local c = Instance.new("Part")
			c.Name = "LeafFall"
			c.Anchored = true
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			c.CastShadow = false
			c.Transparency = 1
			-- each rectangle launches at most 26 above its OWN floor (review 6: a rectangle over the lower step of a
			-- terrace inherited the tree's launch height, fell 48 studs and drifted past the sampled reach into the wall)
			-- a thin launch slice: a leaf born at the top of a 1-stud box ended a stud higher (review 8: median 1.1 up)
			local rhi = math.min(hi, r.hi + 26)
			local rlo = rhi - 0.2
			c.Size = Vector3.new(rw, 0.2, rd)
			c.CFrame = CFrame.new(x0 + (r.i0 - 1) * cw + rw / 2, rhi - 0.1, z0 + (r.j0 - 1) * cd + rd / 2)
			emitter(c, rng, heavy, rw * rd, rlo - r.hi - MARGIN, dir)
			c.Parent = f
			n += 1
		end
	end
	return n
end

return LeafFall
