--!strict
--[[
	Gear - what a character wears for progression, built from Parts and welded to the R6 body:
	  - the faction mark the GDD gives each side: Menders a teal hoop round the waist, Scrappers a
	    purple leather patch on the chest (Menders.md, Scrappers.md);
	  - the equipped Relic: umbrella or broom in the right hand, mended gloves on both hands,
	    sandals on the feet, a hubcap on the forearm, or the Boss Coat.
	Parts are massless and never collide or block rays. Overlapping parallel faces stay at least
	0.05 studs apart (Map-Art-Direction rule 3).
	Relics use the painted meshes in ReplicatedStorage.RelicModels when they are there (trash-art
	blender/gen_relics.py; each template's pivot is the point it is welded at), else the parts below.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))

local MARK = "FactionMark"
local RELIC = "RelicGear"

local rgb = Color3.fromRGB
local M = Enum.Material

local Gear = {}

local function add(model: Model, body: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material or M.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = body.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = body
	weld.Part1 = p
	weld.C0 = offset
	weld.Parent = p
	p.Parent = model
	return p
end

local function bodyPart(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

local function clear(character: Model, name: string)
	local old = character:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

local function holder(character: Model, name: string): Model
	clear(character, name)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = character
	return model
end

-- ── faction marks ──

function Gear.mark(character: Model, faction: string?)
	clear(character, MARK)
	local torso = bodyPart(character, "Torso")
	if not torso or not faction then
		return
	end
	local model = holder(character, MARK)
	local info = Factions.INFO[faction]
	if faction == "Menders" then
		-- a hoop of 16 short segments on an ellipse round the waist (torso is 2 x 1)
		local rx, rz = 1.32, 0.82
		local n = 16
		for i = 0, n - 1 do
			local a0, a1 = i / n * 2 * math.pi, (i + 1) / n * 2 * math.pi
			local p0 = Vector3.new(math.cos(a0) * rx, 0, math.sin(a0) * rz)
			local p1 = Vector3.new(math.cos(a1) * rx, 0, math.sin(a1) * rz)
			local mid = (p0 + p1) / 2
			local len = (p1 - p0).Magnitude + 0.08
			add(model, torso, Vector3.new(len, 0.22, 0.22), CFrame.lookAt(mid, mid + (p1 - p0)) * CFrame.Angles(0, math.rad(90), 0) + Vector3.new(0, -0.78, 0), info.color, M.Metal)
		end
	elseif faction == "Scrappers" then
		add(model, torso, Vector3.new(0.72, 0.72, 0.1), CFrame.new(0.3, 0.4, -0.6), rgb(110, 60, 160), M.Leather)
		add(model, torso, Vector3.new(0.3, 0.3, 0.06), CFrame.new(0.3, 0.4, -0.67) * CFrame.Angles(0, 0, math.rad(45)), rgb(214, 170, 60), M.Fabric)
	end
end

-- ── Relic gear ──

-- clones a painted template, places its pivot at body * offset and welds every part to the body
local function mesh(model: Model, body: BasePart, name: string, offset: CFrame): boolean
	local folder = ReplicatedStorage:FindFirstChild("RelicModels")
	local template = folder and folder:FindFirstChild(name)
	if not (template and template:IsA("Model")) then
		return false
	end
	local copy = template:Clone()
	copy:PivotTo(body.CFrame * offset)
	for _, p in copy:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CastShadow = false
			local weld = Instance.new("Weld")
			weld.Part0 = body
			weld.Part1 = p
			weld.C0 = body.CFrame:ToObjectSpace(p.CFrame)
			weld.Parent = p
			p.Parent = model
		end
	end
	copy:Destroy()
	return true
end

local builders: { [string]: (Model, Model) -> () } = {
	Umbrella = function(model, character)
		local arm = bodyPart(character, "Right Arm")
		if not arm then
			return
		end
		-- held like a closed spear, pointing forward from the hand
		local grip = CFrame.new(0, -1.05, -0.2) * CFrame.Angles(math.rad(-90), 0, 0)
		if mesh(model, arm, "Umbrella", grip) then
			return
		end
		add(model, arm, Vector3.new(0.16, 4.6, 0.16), grip * CFrame.new(0, 1.6, 0), rgb(150, 150, 146), M.Metal, Enum.PartType.Block)
		add(model, arm, Vector3.new(0.62, 2.6, 0.62), grip * CFrame.new(0, 2.3, 0), rgb(48, 52, 60), M.Fabric)
		add(model, arm, Vector3.new(0.4, 0.5, 0.4), grip * CFrame.new(0, 3.85, 0), rgb(96, 204, 188), M.Metal)
		add(model, arm, Vector3.new(0.26, 0.8, 0.26), grip * CFrame.new(0, -0.2, 0), rgb(84, 56, 36), M.Wood)
	end,
	Broom = function(model, character)
		local arm = bodyPart(character, "Right Arm")
		if not arm then
			return
		end
		local grip = CFrame.new(0, -1.05, 0) * CFrame.Angles(math.rad(-60), 0, 0)
		if mesh(model, arm, "Broom", grip) then
			return
		end
		add(model, arm, Vector3.new(0.2, 5.2, 0.2), grip * CFrame.new(0, 1.4, 0), rgb(120, 90, 60), M.Wood)
		add(model, arm, Vector3.new(2.3, 0.5, 0.6), grip * CFrame.new(0, 4.05, 0), rgb(84, 64, 44), M.Wood)
		local colors = { rgb(120, 222, 44), rgb(96, 204, 188), rgb(236, 230, 214), rgb(255, 214, 58) }
		for i = 0, 5 do
			add(model, arm, Vector3.new(0.34, 0.9, 0.5), grip * CFrame.new(-0.95 + i * 0.38, 4.7, 0), colors[i % #colors + 1], M.SmoothPlastic)
		end
	end,
	Gloves = function(model, character)
		local colors = { rgb(150, 120, 80), rgb(96, 128, 176), rgb(214, 170, 60), rgb(120, 222, 44) }
		for side, name in { "Left Arm", "Right Arm" } do
			local arm = bodyPart(character, name)
			if arm and mesh(model, arm, if side == 1 then "GloveL" else "GloveR", CFrame.identity) then
				continue
			end
			if arm then
				add(model, arm, Vector3.new(1.1, 0.75, 1.1), CFrame.new(0, -0.68, 0), colors[side], M.Fabric)
				add(model, arm, Vector3.new(1.16, 0.2, 1.16), CFrame.new(0, -0.22, 0), colors[side + 2], M.Fabric)
				add(model, arm, Vector3.new(0.4, 0.4, 0.12), CFrame.new(0, -0.68, -0.6), colors[3 - side], M.Fabric)
			end
		end
	end,
	Sandals = function(model, character)
		for _, name in { "Left Leg", "Right Leg" } do
			local leg = bodyPart(character, name)
			if leg and mesh(model, leg, "Sandal", CFrame.identity) then
				continue
			end
			if leg then
				add(model, leg, Vector3.new(1.12, 0.22, 1.3), CFrame.new(0, -1.08, -0.08), rgb(60, 44, 32), M.Rubber)
				add(model, leg, Vector3.new(1.16, 0.3, 0.22), CFrame.new(0, -0.82, -0.35), rgb(222, 106, 46), M.Fabric)
				add(model, leg, Vector3.new(1.16, 0.3, 0.22), CFrame.new(0, -0.82, 0.3), rgb(110, 60, 160), M.Fabric)
			end
		end
	end,
	Hubcap = function(model, character)
		local arm = bodyPart(character, "Right Arm")
		if not arm then
			return
		end
		-- strapped to the outside of the forearm like a small shield
		if mesh(model, arm, "Hubcap", CFrame.identity) then
			return
		end
		add(model, arm, Vector3.new(0.16, 2.3, 2.3), CFrame.new(0.64, -0.5, 0), rgb(214, 220, 226), M.Metal, Enum.PartType.Cylinder)
		add(model, arm, Vector3.new(0.2, 0.9, 0.9), CFrame.new(0.68, -0.5, 0), rgb(40, 40, 44), M.Rubber, Enum.PartType.Cylinder)
	end,
	Coat = function(model, character)
		local torso = bodyPart(character, "Torso")
		if not torso then
			return
		end
		if mesh(model, torso, "Coat", CFrame.identity) then
			return
		end
		local cloth = rgb(70, 50, 90)
		-- a long back panel hanging past the hips (behind the arms and legs, clear of both)
		add(model, torso, Vector3.new(2.16, 3.4, 0.12), CFrame.new(0, -0.65, 0.62), cloth, M.Leather)
		-- collar and narrow front lapels (clear of the Scrappers patch)
		add(model, torso, Vector3.new(2.2, 0.35, 1.2), CFrame.new(0, 1.1, 0), rgb(40, 30, 54), M.Leather)
		add(model, torso, Vector3.new(0.3, 2, 0.1), CFrame.new(-0.85, 0.1, -0.6), cloth, M.Leather)
		add(model, torso, Vector3.new(0.3, 2, 0.1), CFrame.new(0.85, 0.1, -0.6), cloth, M.Leather)
		-- scrap plates on the back
		for i, y in { 0.3, -0.5, -1.3 } do
			add(model, torso, Vector3.new(0.9, 0.6, 0.1), CFrame.new(if i % 2 == 0 then 0.45 else -0.45, y, 0.72), rgb(150, 150, 146), M.Metal)
		end
	end,
}

function Gear.relic(character: Model, model: string?)
	clear(character, RELIC)
	local build = model and builders[model]
	if not build then
		return
	end
	local m = holder(character, RELIC)
	build(m, character)
end

return Gear
