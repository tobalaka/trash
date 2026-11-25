--!strict
--[[
	Looks - builds one stylized townsperson from a seed: a chunky blocky body (big cube head with
	block eyes, sleeves and hands, trousers and shoes) in a muted slum palette, plus seeded hair,
	hats, hoods, goggles, masks, scarves, aprons, packs and carried goods. Parts only: nothing is
	uploaded. Every part is anchored, non-colliding and invisible to raycasts; Animate moves them
	with workspace:BulkMoveTo.

	Bones (joint frames, built by Animate): 1 torso centre, 2 neck, 3 left shoulder, 4 right
	shoulder, 5 left hip, 6 right hip. Each part keeps a rest offset from its bone. Unscaled
	layout, feet on the ground at y 0, facing -Z: hips at y 2, torso centre y 3, neck y 4.
	Parallel faces that overlap are at least 0.05 apart (no Z-fighting, Map-Art-Direction rule 3).
]]

local Looks = {}

export type Role = "Walker" | "Vendor" | "Shopper" | "Loiter" | "Crier"
export type Body = {
	model: Model,
	parts: { BasePart },
	bones: { number },
	offsets: { CFrame },
	scale: number,
	kid: boolean,
	carry: string?, -- "Crate" | "Sack" | "Bucket"
	pose: string, -- resting arms: "Crossed" | "Behind" | "Hips" | "Down"
}

local BONE = { Torso = 1, Neck = 2, LeftArm = 3, RightArm = 4, LeftLeg = 5, RightLeg = 6 }
Looks.BONE = BONE

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local SKIN = { rgb(255, 219, 172), rgb(241, 194, 125), rgb(224, 172, 105), rgb(198, 134, 66), rgb(141, 85, 36), rgb(99, 63, 41) }
local SHIRT = {
	rgb(92, 107, 74), rgb(120, 96, 64), rgb(70, 82, 96), rgb(150, 120, 72), rgb(96, 72, 64), rgb(66, 70, 76), rgb(128, 132, 120),
	rgb(78, 104, 112), rgb(140, 92, 64), rgb(176, 160, 128), rgb(104, 84, 110), rgb(60, 90, 70), rgb(158, 146, 120), rgb(110, 118, 92),
}
local PANTS = { rgb(54, 58, 66), rgb(72, 62, 52), rgb(42, 50, 66), rgb(88, 80, 66), rgb(60, 66, 52), rgb(36, 38, 42), rgb(98, 90, 76) }
local ACCENT = {
	rgb(196, 140, 64), rgb(214, 180, 96), rgb(90, 140, 150), rgb(170, 104, 78), rgb(128, 152, 96), rgb(214, 204, 176), rgb(150, 112, 150),
	rgb(96, 128, 176), rgb(220, 150, 90),
}
local KID_SHIRT = { rgb(214, 170, 80), rgb(96, 150, 170), rgb(150, 176, 100), rgb(200, 130, 100), rgb(160, 130, 190), rgb(220, 200, 150) }
local HAIR = { rgb(40, 30, 24), rgb(70, 46, 30), rgb(120, 84, 48), rgb(30, 30, 32), rgb(170, 140, 90), rgb(150, 150, 150), rgb(140, 70, 40) }
local SHOES = { rgb(40, 36, 34), rgb(70, 52, 40), rgb(56, 60, 64), rgb(30, 30, 30) }
local EYES = rgb(24, 22, 24)
local LENS = rgb(60, 96, 104)
local CRATE = rgb(122, 92, 60)
local SACK = rgb(176, 150, 108)
local BUCKET = rgb(120, 126, 130)
local CRIER_COAT = rgb(150, 112, 56)

local HEAD = 1.4 -- head cube side (adult)
local KID_HEAD = 1.22 -- kids' heads are this much bigger relative to their body
local CHANCE = {
	hat = 0.35,
	hood = 0.14,
	hair = 0.65, -- when there is no hat or hood
	bandana = 0.12,
	goggles = 0.12,
	mask = 0.14,
	filter = 0.4, -- of masks: a gas-mask filter on the front
	scarf = 0.25,
	backpack = 0.15,
	vendorApron = 0.7,
	belt = 0.3,
	patch = 0.25,
	brows = 0.35,
}

type Spec = { bone: number, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, shadow: boolean? }

-- Fixed outfit pieces for named NPCs (Shared/Data/Npcs). Anything left nil stays seeded, and a
-- nil style draws exactly the same random numbers as before, so the crowd looks unchanged.
export type Style = {
	shirt: Color3?,
	accent: Color3?,
	hat: string?, -- beanie | cap | wide | hood | none
	apron: boolean?,
	pin: boolean?, -- the Menders' bottle-cap pin
	tag: boolean?, -- the Scrappers' stamped scrap tag
	mask: boolean?,
	goggles: boolean?,
	kid: boolean?,
	scale: number?,
}
local PIN = rgb(96, 204, 188)
local TAG = rgb(110, 60, 160)
local TAG_CORD = rgb(70, 52, 40)
local HAT_INDEX = { beanie = 1, cap = 2, wide = 3 }

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

--[[
	seed: the person's look. role: what they do (aprons for vendors, a coat for the crier).
	kid: small body, big head. carry: a walker's load or nil.
]]
function Looks.build(seed: number, role: Role, kid: boolean, carry: string?, scale: number, style: Style?): Body
	local rng = Random.new(seed)
	local specs: { Spec } = {}
	local function add(bone: number, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, shadow: boolean?)
		table.insert(specs, { bone = bone, size = size, at = at, color = color, material = material, shape = shape, shadow = shadow })
	end

	local skin = pick(rng, SKIN)
	local shirt = if role == "Crier" then CRIER_COAT elseif kid then pick(rng, KID_SHIRT) else pick(rng, SHIRT)
	local pants = pick(rng, PANTS)
	local accent = pick(rng, ACCENT)
	local hairColor = pick(rng, HAIR)
	local shoes = pick(rng, SHOES)
	if style then
		shirt = style.shirt or shirt
		accent = style.accent or accent
	end
	local H = if kid then HEAD * KID_HEAD else HEAD
	local headY = 0.05 + H / 2 -- head centre above the neck joint
	local top = headY + H / 2
	local front = -H / 2

	-- body
	add(BONE.Torso, Vector3.new(2, 2, 1), CFrame.identity, shirt, nil, nil, true)
	add(BONE.Neck, Vector3.new(H, H, H), CFrame.new(0, headY, 0), skin, nil, nil, true)
	for _, x in { -0.3, 0.3 } do
		add(BONE.Neck, Vector3.new(0.18, 0.34, 0.1), CFrame.new(x * H / HEAD, headY + 0.05, front - 0.03), EYES)
	end
	if rng:NextNumber() < CHANCE.brows then
		local tilt = rng:NextNumber(-12, 12)
		for _, x in { -0.3, 0.3 } do
			add(BONE.Neck, Vector3.new(0.3, 0.08, 0.1), CFrame.new(x * H / HEAD, headY + 0.36, front - 0.03) * CFrame.Angles(0, 0, math.rad(tilt * math.sign(x))), hairColor)
		end
	end
	for _, side in { -1, 1 } do
		local bone = if side < 0 then BONE.LeftArm else BONE.RightArm
		add(bone, Vector3.new(0.95, 1.55, 0.95), CFrame.new(0, -0.525, 0), shirt, nil, nil, true)
		add(bone, Vector3.new(0.8, 0.5, 0.8), CFrame.new(0, -1.5, 0), skin)
		local leg = if side < 0 then BONE.LeftLeg else BONE.RightLeg
		add(leg, Vector3.new(0.96, 1.75, 0.96), CFrame.new(0, -0.825, 0), pants, nil, nil, true)
		add(leg, Vector3.new(1.06, 0.45, 1.24), CFrame.new(0, -1.775, -0.12), shoes)
	end

	-- headwear: one hat or hood, else hair; bandana and goggles can go with hair
	local roll = rng:NextNumber()
	local hasHat = roll < CHANCE.hat
	local hasHood = not hasHat and roll < CHANCE.hat + CHANCE.hood
	if role == "Crier" then
		hasHat, hasHood = true, false
	end
	local styleHat = style and style.hat
	if styleHat then
		hasHat = HAT_INDEX[styleHat] ~= nil
		hasHood = styleHat == "hood"
	end
	if hasHat then
		local hat = if role == "Crier" then 3 else rng:NextInteger(1, 3)
		if styleHat and HAT_INDEX[styleHat] then
			hat = HAT_INDEX[styleHat]
		end
		local hatColor = if rng:NextNumber() < 0.5 then accent else pick(rng, PANTS)
		if hat == 1 then -- beanie
			add(BONE.Neck, Vector3.new(H + 0.1, 0.55, H + 0.1), CFrame.new(0, top + 0.12, 0), hatColor, Enum.Material.Fabric)
		elseif hat == 2 then -- cap with a brim
			add(BONE.Neck, Vector3.new(H + 0.08, 0.38, H + 0.08), CFrame.new(0, top + 0.09, 0), hatColor, Enum.Material.Fabric)
			add(BONE.Neck, Vector3.new(H * 0.8, 0.1, 0.6), CFrame.new(0, top - 0.07, front - 0.25), hatColor, Enum.Material.Fabric)
		else -- wide-brimmed hat
			local straw = rgb(196, 170, 112)
			add(BONE.Neck, Vector3.new(H * 1.75, 0.12, H * 1.75), CFrame.new(0, top + 0.02, 0), straw, Enum.Material.Fabric)
			add(BONE.Neck, Vector3.new(H * 1.05, 0.55, H * 1.05), CFrame.new(0, top + 0.3, 0), straw, Enum.Material.Fabric)
		end
	elseif hasHood then
		add(BONE.Neck, Vector3.new(H + 0.2, H + 0.2, H + 0.12), CFrame.new(0, headY + 0.04, 0.12), if rng:NextNumber() < 0.5 then shirt else pick(rng, PANTS), Enum.Material.Fabric)
	elseif rng:NextNumber() < CHANCE.hair then
		add(BONE.Neck, Vector3.new(H + 0.08, 0.3, H + 0.08), CFrame.new(0, top + 0.1, 0), hairColor)
		add(BONE.Neck, Vector3.new(H - 0.06, H * 0.7, 0.25), CFrame.new(0, top - H * 0.35 + 0.1, H / 2 + 0.08), hairColor)
	end
	local styleGoggles = style ~= nil and style.goggles == true
	if not hasHood and not styleGoggles and rng:NextNumber() < CHANCE.bandana then
		add(BONE.Neck, Vector3.new(H + 0.12, 0.22, H + 0.12), CFrame.new(0, top - 0.3, 0), accent, Enum.Material.Fabric)
	elseif not hasHood and (styleGoggles or rng:NextNumber() < CHANCE.goggles) then
		add(BONE.Neck, Vector3.new(H + 0.1, 0.18, H + 0.1), CFrame.new(0, headY + 0.32, 0), pick(rng, SHOES))
		for _, x in { -0.3, 0.3 } do
			add(BONE.Neck, Vector3.new(0.36, 0.3, 0.16), CFrame.new(x * H / HEAD, headY + 0.32, front - 0.1), LENS)
		end
	end
	if not kid and ((style ~= nil and style.mask == true) or rng:NextNumber() < CHANCE.mask) then
		local maskColor = if rng:NextNumber() < 0.5 then pick(rng, PANTS) else accent
		add(BONE.Neck, Vector3.new(H + 0.12, 0.5, H + 0.12), CFrame.new(0, headY - 0.38, 0), maskColor, Enum.Material.Fabric)
		if rng:NextNumber() < CHANCE.filter then
			add(BONE.Neck, Vector3.new(0.45, 0.5, 0.5), CFrame.new(0, headY - 0.4, front - 0.24) * CFrame.Angles(0, math.rad(90), 0), pick(rng, SHOES), Enum.Material.Metal, Enum.PartType.Cylinder)
		end
	end

	-- clothes and kit on the torso
	if role == "Crier" or rng:NextNumber() < CHANCE.scarf then
		add(BONE.Torso, Vector3.new(1.5, 0.32, 1.2), CFrame.new(0, 1.11, 0), accent, Enum.Material.Fabric)
	end
	local apron = role == "Vendor" and rng:NextNumber() < CHANCE.vendorApron
	if style and style.apron ~= nil then
		apron = style.apron
	end
	if apron then
		add(BONE.Torso, Vector3.new(1.7, 1.9, 0.1), CFrame.new(0, -0.5, -0.61), if rng:NextNumber() < 0.5 then rgb(214, 204, 176) else accent, Enum.Material.Fabric)
	else
		if rng:NextNumber() < CHANCE.belt then
			add(BONE.Torso, Vector3.new(2.12, 0.26, 1.12), CFrame.new(0, -0.8, 0), pick(rng, SHOES))
		end
		if rng:NextNumber() < CHANCE.patch then
			add(BONE.Torso, Vector3.new(0.5, 0.45, 0.08), CFrame.new(rng:NextNumber(-0.5, 0.5), rng:NextNumber(-0.4, 0.4), -0.53), accent, Enum.Material.Fabric)
		end
	end
	if carry == "Crate" then
		add(BONE.Torso, Vector3.new(1.5, 1.1, 1.1), CFrame.new(0, -0.25, -1.25), CRATE, Enum.Material.Wood, nil, true)
	elseif carry == "Sack" then
		add(BONE.Torso, Vector3.new(1.4, 1.6, 0.9), CFrame.new(0, 0.15, 0.9), SACK, Enum.Material.Fabric, nil, true)
		add(BONE.Torso, Vector3.new(0.5, 0.3, 0.5), CFrame.new(0, 1.07, 0.9), pick(rng, SHOES), Enum.Material.Fabric)
	elseif carry == "Bucket" then
		add(BONE.RightArm, Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, -2.2, 0) * CFrame.Angles(0, 0, math.rad(90)), BUCKET, Enum.Material.Metal, Enum.PartType.Cylinder)
	elseif rng:NextNumber() < CHANCE.backpack and role ~= "Vendor" then
		local pack = if rng:NextNumber() < 0.5 then pick(rng, PANTS) else accent
		add(BONE.Torso, Vector3.new(1.5, 1.5, 0.7), CFrame.new(0, 0.05, 0.8), pack, Enum.Material.Fabric, nil, true)
		add(BONE.Torso, Vector3.new(1.62, 0.4, 0.82), CFrame.new(0, 0.65, 0.8), pick(rng, SHOES), Enum.Material.Fabric)
	end

	-- faction marks (named NPCs): the Menders' bottle-cap pin on the chest, or the Scrappers'
	-- stamped scrap tag hanging on a cord (2026-10-26; they were a waist hoop and a chest patch)
	local front = if apron then -0.66 else -0.55 -- over an apron a mark sits on the apron
	if style and style.pin then
		add(BONE.Torso, Vector3.new(0.12, 0.5, 0.5), CFrame.new(-0.42, 0.5, front) * CFrame.Angles(0, math.rad(90), 0), PIN, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	if style and style.tag then
		add(BONE.Torso, Vector3.new(0.08, 0.7, 0.08), CFrame.new(0, 0.62, front) * CFrame.Angles(0, 0, math.rad(90)), TAG_CORD, Enum.Material.Fabric)
		add(BONE.Torso, Vector3.new(0.46, 0.6, 0.08), CFrame.new(0, 0.22, front), TAG, Enum.Material.Metal)
	end

	-- build
	local model = Instance.new("Model")
	model.Name = "Townsperson"
	local body: Body = {
		model = model,
		parts = {},
		bones = {},
		offsets = {},
		scale = scale,
		kid = kid,
		carry = carry,
		pose = if role == "Vendor" then pick(rng, { "Crossed", "Behind", "Hips" } :: { string }) else "Down",
	}
	for _, s in specs do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = s.shadow == true
		p.Material = s.material or Enum.Material.SmoothPlastic
		p.Color = s.color
		if s.shape then
			p.Shape = s.shape
		end
		p.Size = s.size * scale
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		table.insert(body.parts, p)
		table.insert(body.bones, s.bone)
		table.insert(body.offsets, CFrame.new(s.at.Position * scale) * s.at.Rotation)
	end
	return body
end

return Looks
