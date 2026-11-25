--!strict
--[[
	HQArt.Kit - stages a Blender batch (trash-art/blender/out/<Batch>.json + its uploaded FBX) as templates in
	ServerStorage.HQArt.Kit.<Asset>.

	The FBX holds every asset of the batch at the origin, one mesh per "<Asset>_<Role>". Per asset:
	  * a Model named <Asset> whose pivot is the authored origin (bottom centre, front -Z);
	  * painted roles get a SurfaceAppearance with the baked ColorMap + NormalMap (the MeshPart colour is
	    ignored then); flat roles get the spec's colour on SmoothPlastic;
	  * the first painted role ("Body") collides with a hull, everything else is decoration (no collide,
	    query, touch; thin parts cast no shadow).

	  local Kit = require(game.ServerStorage.HQArt.Kit)
	  Kit.stage(HttpService:JSONDecode(specJson))   -> { [asset]: Model }
]]

local Kit = {}

function Kit.folder(): Folder
	local root = game.ServerStorage:FindFirstChild("HQArt") :: Folder
	local f = root:FindFirstChild("Kit")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Kit"
		f.Parent = root
	end
	return f :: Folder
end

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local DECOR_NO_SHADOW = { Spines = true, Petals = true, FlowerCentre = true, Fruit = true }

function Kit.stage(spec: any, preloaded: Instance?): { [string]: Model }
	-- InsertService:LoadAsset only serves assets the PLACE owner owns; this team-create place belongs to another
	-- account, so load through the Studio user (plugin-level GetObjects) instead. Freshly uploaded models can
	-- refuse GetObjects for a while; then insert the package with Studio's insert tool and pass it as `preloaded`.
	local loaded = Instance.new("Folder")
	if preloaded then
		preloaded:Clone().Parent = loaded
	else
		for _, o in game:GetObjects("rbxassetid://" .. tostring(spec.modelId)) do
			o.Parent = loaded
		end
	end
	local meshes: { [string]: MeshPart } = {}
	for _, d in loaded:GetDescendants() do
		if d:IsA("MeshPart") then
			meshes[d.Name] = d
		end
	end
	local out = {}
	local store = Kit.folder()
	for asset, entry in spec.assets do
		local model = Instance.new("Model")
		model.Name = asset
		local first: BasePart? = nil
		for role, p in entry.parts do
			local mp = meshes[asset .. "_" .. role]
			if not mp then
				warn("[HQArt.Kit] missing mesh " .. asset .. "_" .. role)
				continue
			end
			local part = mp:Clone()
			part.Name = role
			part.Anchored = true
			part.CanTouch = false
			if p.tex then
				local sa = Instance.new("SurfaceAppearance")
				sa.ColorMap = p.ids.color
				if p.ids.normal then
					sa.NormalMap = p.ids.normal
				end
				if p.ids.rough then
					sa.RoughnessMap = p.ids.rough
				end
				if p.alpha then
					-- leaf cards: the atlas alpha cuts the leaves out of each card. They never collide or block
					-- queries, and cast no shadow (Roblox shadows ignore the alpha: every card would throw a square);
					-- the crown's solid core casts the canopy shadow instead
					sa.AlphaMode = Enum.AlphaMode.Transparency
				end
				sa.Parent = part
				part.Material = Enum.Material.Plastic
				part.Color = Color3.new(1, 1, 1)
				if p.alpha then
					part.CanCollide = false
					part.CanQuery = false
					part.CastShadow = false
				elseif not first then
					first = part
					part.CanCollide = true
					part.CanQuery = true
					part.CollisionFidelity = Enum.CollisionFidelity.Hull
				else
					part.CanCollide = false
					part.CanQuery = false
				end
			else
				part.Material = Enum.Material.SmoothPlastic
				part.Color = hex(p.flat)
				part.CanCollide = false
				part.CanQuery = false
				part.CastShadow = not DECOR_NO_SHADOW[role]
				if role == "Core" then
					-- foliage cores (shadow casters inside the leaf cards): SmoothPlastic showed a white specular spot
					-- = plastic balls through the gaps (review 4). LeafyGrass is matte and has no HQ override.
					part.Material = Enum.Material.LeafyGrass
				end
				if role == "Bulb" then -- lamp bulbs glow and light the street (MapGen's warm lamp light)
					part.Material = Enum.Material.Neon
					part.CastShadow = false
					local light = Instance.new("PointLight")
					light.Color = Color3.fromRGB(255, 190, 125)
					light.Range = 20
					light.Brightness = 1.2
					light.Shadows = false
					light.Parent = part
				end
			end
			part:SetAttribute("Role", role)
			part.Parent = model
		end
		-- pivot = authored origin: bottom centre of the asset's bounding box
		local cf, size = model:GetBoundingBox()
		model.WorldPivot = CFrame.new(cf.X, cf.Y - size.Y / 2, cf.Z)
		-- explicit colliders (trees): invisible boxes along trunk and limbs; the meshes themselves don't collide
		if entry.colliders then
			local folder = Instance.new("Folder")
			folder.Name = "Colliders"
			for _, p in model:GetChildren() do
				if p:IsA("BasePart") then
					p.CanCollide = false
					p.CanQuery = false
				end
			end
			for i, c in entry.colliders do
				local box = Instance.new("Part")
				box.Name = "Collider" .. i
				box.Anchored = true
				box.Transparency = 1
				box.CanCollide = true
				box.CanQuery = true
				box.CanTouch = false
				box.CastShadow = false
				box.Size = Vector3.new(c.size[1], c.size[2], c.size[3])
				local r = c.rot
				box.CFrame = model.WorldPivot * CFrame.new(c.p[1], c.p[2], c.p[3], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
				box.Parent = folder
			end
			folder.Parent = model
		end
		if first then
			model.PrimaryPart = first
		end
		model:SetAttribute("HQAsset", asset)
		if entry.origin then -- authored origin relative to the bbox centre (dressing pieces are placed by it)
			model:SetAttribute("Origin", Vector3.new(entry.origin[1], entry.origin[2], entry.origin[3]))
		end
		model:SetAttribute("Tris", entry.tris)
		local old = store:FindFirstChild(asset)
		if old then
			old:Destroy()
		end
		model.Parent = store
		out[asset] = model
	end
	loaded:Destroy()
	if preloaded then
		preloaded:Destroy()
	end
	return out
end

return Kit
