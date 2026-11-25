--!strict
--[[
	MapGen.Decor - small shared dressing helpers.

	Cables, laundry lines and light shafts are Beams between Attachments: zero physics cost,
	native sag via CurveSize, and they stream with their anchors. Lantern glow uses the same
	trick as the reference world: a PointLight for the actual light plus a couple of slow,
	soft, LightEmission=1 flare particles stacked on it for the bloom-like halo.
]]

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")

local Decor = {}

local ok, ImageIds = pcall(function()
	return require(script.Parent.Data.ImageIds) :: any
end)
if not ok then
	ImageIds = {}
end

-- Decal asset id -> image content id (Open Cloud uploads give decal ids; textures need the image).
local imageCache: { [string]: string } = {}
function Decor.image(name: string): string?
	if imageCache[name] then
		return imageCache[name]
	end
	local decalId = ImageIds[name]
	if not decalId then
		return nil
	end
	local loaded = InsertService:LoadAsset(decalId)
	local d = loaded:FindFirstChildWhichIsA("Decal", true)
	local tex = d and d.Texture or ("rbxassetid://" .. decalId)
	loaded:Destroy()
	imageCache[name] = tex
	return tex
end

function Decor.imagesWithPrefix(prefix: string): { string }
	local out = {}
	for n in ImageIds do
		if n:sub(1, #prefix) == prefix then
			table.insert(out, n)
		end
	end
	table.sort(out)
	return out
end

-- Invisible anchor part carrying one Attachment.
function Decor.anchor(parent: Instance, pos: Vector3, name: string?): Attachment
	local p = Instance.new("Part")
	p.Name = name or "Anchor"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos)
	local a = Instance.new("Attachment")
	a.Parent = p
	p.Parent = parent
	return a
end

-- Sagging cable between two points. sag = studs of droop at the middle.
function Decor.cable(parent: Instance, p0: Vector3, p1: Vector3, sag: number, color: Color3?, width: number?): Beam
	local a0 = Decor.anchor(parent, p0, "CableEnd")
	local a1 = Decor.anchor(parent, p1, "CableEnd")
	-- Beam control points sit along each attachment's X axis (P1 = A0 + X*CurveSize0,
	-- P2 = A1 - X*CurveSize1), so point X straight down on both ends to make the cable sag.
	local flat = Vector3.new(p1.X - p0.X, 0, p1.Z - p0.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.xAxis
	end
	a0.WorldCFrame = CFrame.fromMatrix(p0, -Vector3.yAxis, flat.Unit)
	a1.WorldCFrame = CFrame.fromMatrix(p1, -Vector3.yAxis, flat.Unit)
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = width or 0.18
	b.Width1 = width or 0.18
	b.Color = ColorSequence.new(color or Color3.fromRGB(22, 20, 18))
	b.LightInfluence = 1
	b.Transparency = NumberSequence.new(0)
	b.Segments = 12
	b.FaceCamera = true
	-- a quadratic sag approximated by the cubic control points (4/3 of the droop)
	local len = (p1 - p0).Magnitude
	b.CurveSize0 = sag * 1.33
	b.CurveSize1 = -sag * 1.33
	b:SetAttribute("Length", len)
	b.Parent = a0.Parent
	return b
end

-- Soft glow halo on a light source (flare stack from the reference world).
function Decor.glow(part: BasePart, color: Color3, size: number?)
	local s = size or 4
	local att = Instance.new("Attachment")
	att.Name = "GlowAttachment"
	att.Parent = part
	local glowTex = Decor.image("fx_glow") or "rbxasset://textures/particles/sparkles_main.dds"
	for i, spec in { { s, 0.55 }, { s * 1.8, 0.8 } } do
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Glow" .. i
		pe.Texture = glowTex
		pe.Color = ColorSequence.new(color)
		pe.LightEmission = 1
		pe.LightInfluence = 0
		pe.Size = NumberSequence.new(spec[1])
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, spec[2]),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.Lifetime = NumberRange.new(1)
		pe.Rate = 2
		pe.Speed = NumberRange.new(0)
		pe.LockedToPart = true
		pe.ZOffset = 1
		pe.Parent = att
	end
end

-- Volumetric-looking light shaft (god ray) from top to bottom.
function Decor.lightShaft(parent: Instance, top: Vector3, bottom: Vector3, width: number, color: Color3, opacity: number?): Beam
	local a0 = Decor.anchor(parent, top, "ShaftTop")
	local a1 = Decor.anchor(parent, bottom, "ShaftBottom")
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = width * 0.7
	b.Width1 = width
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Texture = Decor.image("fx_shaft") or ""
	b.TextureMode = Enum.TextureMode.Stretch
	b.Color = ColorSequence.new(color)
	local o = opacity or 0.82
	b.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, o),
		NumberSequenceKeypoint.new(0.8, o + (1 - o) * 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	b.Segments = 2
	b.Parent = a0.Parent
	return b
end

-- Spawn marker for future NPC/crowd systems (invisible, non-colliding, tagged).
function Decor.npcSpot(parent: Instance, cf: CFrame, kind: string): BasePart
	local p = Instance.new("Part")
	p.Name = "NPCSpawn_" .. kind
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(2, 0.2, 2)
	p.CFrame = cf
	p:SetAttribute("Kind", kind)
	p.Parent = parent
	CollectionService:AddTag(p, "NPCSpawn")
	return p
end

-- Put an image decal on every part of a slot (Face defaults to Back = the +Z / front face).
function Decor.decalSlot(model: Instance, slot: string, image: string, face: Enum.NormalId?)
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") and p:GetAttribute("Slot") == slot then
			local d = Instance.new("Decal")
			d.Texture = image
			d.Face = face or Enum.NormalId.Back
			d.Parent = p
		end
	end
end

return Decor
