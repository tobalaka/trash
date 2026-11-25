--!nonstrict
-- Editor-only: replaces the part-built props in Workspace.World with the Blender mesh kit
-- (TRASH-Assets/gen_assets.py, uploaded via Open Cloud). Not used by game code.
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")

local S = {}
S.templates = {}

function S.folder()
	local f = ServerStorage:FindFirstChild("MapAssets")
	if not f then
		f = Instance.new("Folder")
		f.Name = "MapAssets"
		f.Parent = ServerStorage
	end
	return f
end

local function toColor(c) return Color3.fromRGB(c[1], c[2], c[3]) end

-- Load (or reuse) one uploaded asset, colour its slots, pivot at bottom centre.
function S.template(name: string, assetId: number, slots)
	local store = S.folder()
	local existing = store:FindFirstChild(name)
	if existing then S.templates[name] = existing return existing end
	local loaded = InsertService:LoadAsset(assetId)
	local model = loaded:FindFirstChildWhichIsA("Model") or loaded
	model.Name = name
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") then
			local slot = p.Name:gsub("%.%d+$", "")
			local def = slots[slot]
			p.Anchored = true
			if def then
				p.Color = toColor(def.color)
				p.Material = Enum.Material[def.material]
				if def.collide == false then p.CanCollide = false p.CanQuery = false p.CanTouch = false end
				if def.transparency then p.Transparency = def.transparency end
			end
			p.CollisionFidelity = (p.CanCollide and (slot == "Walls" or slot == "Walls2" or slot == "Stone")) and Enum.CollisionFidelity.Default or Enum.CollisionFidelity.Hull
			p:SetAttribute("Slot", slot)
			if slot == "Bulb" then
				local l = Instance.new("PointLight")
				l.Range = 22 l.Brightness = 1.2 l.Color = Color3.fromRGB(255, 200, 140) l.Shadows = false
				l.Parent = p
			end
		end
	end
	local cf, size = model:GetBoundingBox()
	model.WorldPivot = CFrame.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
	model:SetAttribute("AssetId", assetId)
	model:SetAttribute("NativeHeight", size.Y)
	model:SetAttribute("NativeWidth", math.max(size.X, size.Z))
	model.Parent = store
	if loaded ~= model then loaded:Destroy() end
	S.templates[name] = model
	return model
end

-- Place a clone: bottom centre at pos, yawed, uniformly scaled to a target height.
function S.place(name: string, parent: Instance, pos: Vector3, yaw: number, height: number?, width: number?)
	local t = S.templates[name]
	local c = t:Clone()
	local scale = 1
	if height then scale = height / t:GetAttribute("NativeHeight")
	elseif width then scale = width / t:GetAttribute("NativeWidth") end
	c:ScaleTo(math.clamp(scale, 0.05, 50))
	c:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
	c.Parent = parent
	return c
end

-- Recolour one slot on a placed clone.
function S.paint(model: Model, slot: string, color: Color3?, material: Enum.Material?)
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") and p:GetAttribute("Slot") == slot then
			if color then p.Color = color end
			if material then p.Material = material end
		end
	end
end

-- Bottom centre and height of an old part-built model/folder.
function S.footprint(inst: Instance)
	local cf, size
	if inst:IsA("Model") then
		cf, size = inst:GetBoundingBox()
	else
		cf, size = inst.CFrame, inst.Size
	end
	return Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z), size
end

function S.yawOf(cf: CFrame): number
	local look = cf.LookVector
	return math.atan2(-look.X, -look.Z)
end

return S
