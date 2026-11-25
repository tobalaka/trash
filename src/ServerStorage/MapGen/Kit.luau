--!strict
--[[
	MapGen.Kit - turns uploaded Blender assets into ready-to-place templates.

	Each asset is loaded once (InsertService) into ServerStorage.MapGenData.Assets and prepared:
	  * every MeshPart is coloured/material'd from Data.Slots by its slot name (chunk prefix
	    "C3_" and split suffix "__2" stripped), decorative slots lose CanCollide/CanQuery/CanTouch,
	    glowing slots get a light;
	  * the pivot is set to the authored origin (ground centre) using the Blender bounding-box
	    centre from the manifest, so placement is exact even for asymmetric assets;
	  * assets with collision proxies (buildings, landmarks) get invisible Box parts and their
	    meshes become visual-only (Box parts are the cheapest, most predictable collision and
	    match the wall-run/vault movement better than mesh hulls); other assets collide with
	    their solid slots using Hull fidelity;
	  * pre-fractured assets have their chunks grouped into Chunk<i> models and are tagged
	    "Destructible" for the destruction system.
	Clones of a template share MeshIds, so Roblox can instance them on the GPU.
]]

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local Layout = require(script.Parent.Layout)
local Decor = require(script.Parent.Decor)
local AssetIds = require(script.Parent.Data.AssetIds) :: any
local Slots = require(script.Parent.Data.Slots) :: any

local Kit = {}

local LIGHTS: { [string]: { range: number, brightness: number, color: Color3 } } = {
	warm = { range = 18, brightness = 1.1, color = Color3.fromRGB(255, 196, 130) },
	lantern = { range = 16, brightness = 1.3, color = Color3.fromRGB(255, 150, 90) },
	fire = { range = 22, brightness = 2, color = Color3.fromRGB(255, 130, 60) },
}

function Kit.store(): Folder
	local data = Layout.dataFolder()
	local f = data:FindFirstChild("Assets")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Assets"
		f.Parent = data
	end
	return f :: Folder
end

function Kit.has(name: string): boolean
	return AssetIds[name] ~= nil
end

local function baseSlot(partName: string): (string, number?)
	local chunk = partName:match("^C(%d+)_")
	local slot = partName:gsub("^C%d+_", ""):gsub("__%d+$", ""):gsub("%.%d+$", "")
	return slot, chunk and tonumber(chunk) or nil
end

local function prepare(name: string, model: Model, info: any)
	local hasProxy = info.collision and #info.collision > 0
	local chunks: { [number]: Model } = {}
	for _, p in model:GetDescendants() do
		if not p:IsA("MeshPart") then
			continue
		end
		local slot, chunk = baseSlot(p.Name)
		local def = Slots[slot]
		p.Anchored = true
		p:SetAttribute("Slot", slot)
		if def then
			p.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
			local ok, mat = pcall(function()
				return (Enum.Material :: any)[def.material]
			end)
			if ok and mat then
				p.Material = mat
			end
			if def.transparency then
				p.Transparency = def.transparency
			end
			if def.light and LIGHTS[def.light] then
				local l = LIGHTS[def.light]
				local light = Instance.new("PointLight")
				light.Range = l.range
				light.Brightness = l.brightness
				light.Color = l.color
				light.Shadows = false
				light.Parent = p
				-- soft halo (reference-world flare stack); clones inherit it from the template
				Decor.glow(p, l.color, math.clamp(p.Size.Magnitude * 0.7, 2, 9))
			end
			if def.decal then
				p:SetAttribute("DecalKind", def.decal)
			end
		end
		local solid = def == nil or def.collide ~= false
		if hasProxy or not solid then
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
		else
			p.CanCollide = true
			p.CanQuery = true
			p.CanTouch = false
			p.CollisionFidelity = Enum.CollisionFidelity.Hull
		end
		if chunk then
			local cm = chunks[chunk]
			if not cm then
				cm = Instance.new("Model")
				cm.Name = "Chunk" .. chunk
				cm.Parent = model
				chunks[chunk] = cm
			end
			p.Parent = cm
		end
	end

	-- pivot at the authored origin (ground centre)
	local cf, size = model:GetBoundingBox()
	local origin: Vector3
	if info.center then
		local c = info.center
		origin = cf.Position - Vector3.new(c[1], c[2], c[3])
	else
		origin = Vector3.new(cf.X, cf.Y - size.Y / 2, cf.Z)
		if name:match("^HangingVine") then
			origin = Vector3.new(cf.X, cf.Y + size.Y / 2, cf.Z)
		end
	end
	model.WorldPivot = CFrame.new(origin)

	if hasProxy then
		local proxies = Instance.new("Folder")
		proxies.Name = "Collision"
		for i, b in info.collision do
			local part = Instance.new("Part")
			part.Name = "Proxy" .. i
			part.Anchored = true
			part.Transparency = 1
			part.CanCollide = true
			part.CanQuery = true
			part.CanTouch = false
			part.CastShadow = false
			part.Size = Vector3.new(math.max(b[4], 0.2), math.max(b[5], 0.2), math.max(b[6], 0.2))
			part.CFrame = CFrame.new(origin + Vector3.new(b[1], b[2], b[3])) * CFrame.fromEulerAnglesXYZ(b[7], b[8], b[9])
			part.Parent = proxies
		end
		proxies.Parent = model
	end
	if next(chunks) then
		CollectionService:AddTag(model, "Destructible")
		local n = 0
		for _ in chunks do
			n += 1
		end
		model:SetAttribute("ChunkCount", n)
	end
	model:SetAttribute("Asset", name)
	model:SetAttribute("AssetId", info.id)
	model:SetAttribute("NativeSize", size)
end

-- Load (or reuse) the prepared template for an asset.
function Kit.template(name: string): Model
	local info = AssetIds[name]
	assert(info, "unknown kit asset: " .. name)
	local store = Kit.store()
	local existing = store:FindFirstChild(name)
	if existing and existing:GetAttribute("AssetId") == info.id then
		return existing :: Model
	end
	if existing then
		existing:Destroy()
	end
	local loaded = InsertService:LoadAsset(info.id)
	local model = loaded:FindFirstChildWhichIsA("Model") or loaded
	model.Name = name
	model.Parent = store
	prepare(name, model :: Model, info)
	if loaded ~= model then
		loaded:Destroy()
	end
	return model :: Model
end

-- Preload many templates (yields between loads to keep Studio responsive).
function Kit.preload(names: { string })
	for i, n in names do
		if AssetIds[n] then
			Kit.template(n)
		end
		if i % 8 == 0 then
			task.wait()
		end
	end
end

function Kit.namesWithPrefix(prefix: string): { string }
	local out = {}
	for n in AssetIds do
		if n:sub(1, #prefix) == prefix then
			table.insert(out, n)
		end
	end
	table.sort(out)
	return out
end

function Kit.clone(name: string): Model
	return Kit.template(name):Clone()
end

-- Uniform scale about the pivot.
function Kit.scale(model: Model, factor: number)
	if math.abs(factor - 1) > 1e-3 then
		model:ScaleTo(model:GetScale() * factor)
	end
end

-- Non-uniform fit about the pivot, in the model's own axes. Works because every part of a kit
-- asset is axis-aligned with the asset (one mesh per slot, no rotation), and proxy boxes with a
-- single-axis tilt keep their orientation (their size is scaled in their own axes).
function Kit.fit(model: Model, sx: number, sy: number, sz: number)
	local pivot = model:GetPivot()
	local s = Vector3.new(sx, sy, sz)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(p.CFrame)
			local pos = rel.Position * s
			local localScale = (rel.Rotation:Inverse() * s):Abs()
			p.Size = p.Size * localScale
			p.CFrame = pivot * (CFrame.new(pos) * rel.Rotation)
		end
	end
end

-- Recolour one slot.
function Kit.paint(model: Instance, slot: string, color: Color3?, material: Enum.Material?)
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") and p:GetAttribute("Slot") == slot then
			if color then
				p.Color = color
			end
			if material then
				p.Material = material
			end
		end
	end
end

-- Small per-instance colour jitter on every slot (avoids copy-paste look).
function Kit.vary(model: Instance, rng: Random, amount: number)
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") and p.Material ~= Enum.Material.Neon then
			local h, s, v = p.Color:ToHSV()
			p.Color = Color3.fromHSV(h, math.clamp(s + rng:NextNumber(-amount, amount) * 0.5, 0, 1), math.clamp(v + rng:NextNumber(-amount, amount), 0, 1))
		end
	end
end

-- Parts of a slot (for decals/lights).
function Kit.slotParts(model: Instance, slot: string): { MeshPart }
	local out = {}
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") and p:GetAttribute("Slot") == slot then
			table.insert(out, p)
		end
	end
	return out
end

return Kit
