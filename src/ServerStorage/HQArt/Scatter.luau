--!strict
--[[
	HQArt.Scatter - undergrowth density around the jungle trees (MapGen placed 192 giants on bare ground).

	Around every swapped jungle tree (HQ model with ReplacedAsset = "GiantTree") 3-5 ferns / bushes are dropped on
	a ring 0.6-1.6 trunk-spreads out, each:
	  * ray-cast onto Workspace.Ground and kept only if the first thing hit IS ground (not water, a road, a prop)
	    and the ground there is grass/ground/mud;
	  * random yaw, 0.8-1.25 size, a small colour drift (SurfaceAppearance.Color);
	  * at least 7 studs from every other scattered piece;
	  * only where the ground under the middle of its footprint varies by <= 1 stud (review 2: ferns hung over
	    ledges with up to 22 studs of drop under them);
	  * bushes tinted darker than ferns (review 2: lemon / lime against the dim jungle floor).
	Seeded from the tree's position, so re-running gives the same layout. Lives in Workspace.World.Jungle.HQ_Scatter.

	  require(game.ServerStorage.HQArt.Scatter).apply() -> count
]]

local Scatter = {}

local ITEMS = { "FernA", "FernB", "FernC", "BushA", "BushB", "BushC", "BushA", "BushC" } -- leaf-card bushes (Foliage1)
local OK_GROUND = { [Enum.Material.Grass] = true, [Enum.Material.Ground] = true, [Enum.Material.Mud] = true, [Enum.Material.LeafyGrass] = true }

local function folder(): Folder
	local j = workspace.World.Jungle
	local f = j:FindFirstChild("HQ_Scatter")
	if not f then
		f = Instance.new("Folder")
		f.Name = "HQ_Scatter"
		f.Parent = j
	end
	return f :: Folder
end

local function ground(pos: Vector3): (Vector3?, Enum.Material?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder() }
	local hit = workspace:Raycast(pos + Vector3.new(0, 80, 0), Vector3.new(0, -220, 0), params)
	if not hit or not hit.Instance:IsDescendantOf(workspace.Ground) or hit.Instance:IsDescendantOf(workspace.Ground.Water) then
		return nil, nil
	end
	return hit.Position, hit.Material
end

function Scatter.remove()
	local f = workspace.World.Jungle:FindFirstChild("HQ_Scatter")
	if f then
		f:Destroy()
	end
end

function Scatter.apply(): number
	Scatter.remove()
	local kit = game.ServerStorage.HQArt.Kit
	local out = folder()
	local placed: { Vector3 } = {}
	local n = 0
	for _, tree in workspace.World.Jungle:GetDescendants() do
		if not (tree:IsA("Model") and tree:GetAttribute("ReplacedAsset") == "GiantTree") then
			continue
		end
		local cf, size = tree:GetBoundingBox()
		local base = Vector3.new(cf.X, cf.Y - size.Y / 2, cf.Z)
		local spread = math.max(size.X, size.Z) * 0.5
		local rng = Random.new(math.floor(math.abs(base.X * 17 + base.Z * 29)) % 2147483647 + 1)
		for _ = 1, rng:NextInteger(3, 6) do
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = spread * rng:NextNumber(0.25, 0.75) + 6
			local p = base + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			local hit, mat = ground(p)
			if not hit or not OK_GROUND[mat :: Enum.Material] then
				continue
			end
			local close = false
			for _, q in placed do
				if (q - hit).Magnitude < 7 then
					close = true
					break
				end
			end
			if close then
				continue
			end
			local name = ITEMS[rng:NextInteger(1, #ITEMS)]
			local tmpl = kit:FindFirstChild(name) :: Model?
			if not tmpl then
				continue
			end
			local scale = rng:NextNumber(0.8, 1.25)
			local _, ts = tmpl:GetBoundingBox()
			-- two rings: the middle (0.3) and the very edge (0.55) of the footprint (review 3: 50 pieces still hung an
			-- edge over a 3+ stud drop with only the middle sampled)
			local lo, hi, ok = hit.Y, hit.Y, true
			for _, ring in { { 0.3, 6 }, { 0.55, 8 } } do
				local half = math.max(ts.X, ts.Z) * scale * ring[1]
				for k = 0, ring[2] - 1 do
					local a2 = k * 2 * math.pi / ring[2]
					local q = ground(hit + Vector3.new(math.cos(a2) * half, 0, math.sin(a2) * half))
					if not q then
						ok = false
						break
					end
					lo, hi = math.min(lo, q.Y), math.max(hi, q.Y)
				end
			end
			if not ok or hi - lo > 1 then
				continue
			end
			local m = tmpl:Clone()
			m:ScaleTo(scale)
			local bush = string.sub(name, 1, 4) == "Bush"
			-- bushes sink a little so the round leaf mass sits IN the ground, not on one point (read as hovering in a
			-- low sun)
			local sink = if bush then 0.15 + ts.Y * scale * 0.14 else 0.15
			m:PivotTo(CFrame.new(Vector3.new(hit.X, lo - sink, hit.Z)) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0))
			local v = if bush then rng:NextNumber(0.55, 0.7) else rng:NextNumber(0.62, 0.8)
			local c = Color3.fromHSV((0.25 + rng:NextNumber(-0.04, 0.04)) % 1, rng:NextNumber(0.02, 0.1), v)
			for _, d in m:GetDescendants() do
				if d:IsA("SurfaceAppearance") then
					d.Color = c
				elseif d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			m:SetAttribute("HQ", true)
			m:SetAttribute("Scatter", name)
			m.Parent = out
			table.insert(placed, hit)
			n += 1
		end
	end
	return n
end

return Scatter
