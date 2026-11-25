--!strict
--[[
	Exped - the EXPED skin (2026-10-25, user: "make it 1:1 to EXPED"). Studied from the EXPEDCOPY
	place file (vault: Lessons/UI, "EXPEDCOPY.rbxlx"): near-black panels (#121212 / #222222 at
	0.25), thin silver ornament frames 9-sliced over every panel and slot, white text with a soft
	black UIStroke (1.2 px at 0.5) and a faint metallic gradient on titles, white glyph icons,
	health #A33838 with a #F7787A lag trail, stamina cyan #00BEDD, posture yellow #E8D460.

	The art is ours (Codex image gen in the same style, trash-art/assets/ui_exped), uploaded by
	Abotboot. Nothing from EXPED itself is used.
]]

local Exped = {}

-- the HUD's current UI scale (Kit sets this so strokes match Kit.stroke's scaling)
Exped.getScale = function(): number
	return 1
end

Exped.IMG = {
	HealthFrame = "rbxassetid://93927384215393", -- 1024x170: chain socket + health / stamina rails
	PostureFrame = "rbxassetid://72211180427108", -- 1024x93
	ThinFrame = "rbxassetid://130444274471094", -- 1024x70
	SlotFrame = "rbxassetid://104961574187160", -- 512x493, 9-slice
	PanelFrame = "rbxassetid://124574629789235", -- 512x505, 9-slice
	CombatHeart = "rbxassetid://76209029016922",
	Menders = "rbxassetid://135344022709966",
	Scrappers = "rbxassetid://135555784430162",
	-- white glyphs
	Dash = "rbxassetid://95282497581926",
	Block = "rbxassetid://96535109537547",
	Parry = "rbxassetid://127854431696636",
	Feint = "rbxassetid://137585370463499",
	Heavy = "rbxassetid://119001412089833",
	Uppercut = "rbxassetid://115877410877416",
	Crit = "rbxassetid://128196101938676", -- the crit chip (T): a fist bursting with impact spikes
	Grab = "rbxassetid://138208861767899",
	Posture = "rbxassetid://75844108274422",
	Inventory = "rbxassetid://109449080186383",
	Journal = "rbxassetid://116593883564083",
	Skills = "rbxassetid://118124326629447",
	Map = "rbxassetid://139617995946501",
	Settings = "rbxassetid://104748150840473",
	-- survival bars and currency (bottom corners)
	VBarFrame = "rbxassetid://109592582503210", -- 123x1024 vertical meter frame
	Hunger = "rbxassetid://135249081260282",
	Thirst = "rbxassetid://118920697145407",
	Vitality = "rbxassetid://137969774643856",
	Dollars = "rbxassetid://129806301823093", -- painted banknote
	Scrap = "rbxassetid://71241965558285", -- painted nut and bolt
	Residue = "rbxassetid://95785173356105", -- painted teal crystal
}

-- art geometry in source pixels (tools/ui_process.py, assets/ui_exped/out/geometry.json)
Exped.GEO = {
	Health = { w = 1024, h = 170, hp = Rect.new(160, 51, 975, 88), sub = Rect.new(160, 100, 740, 127), socket = Rect.new(32, 32, 138, 137) },
	Posture = { w = 1024, h = 93, bar = Rect.new(54, 32, 969, 64) },
	Thin = { w = 1024, h = 70, bar = Rect.new(48, 25, 975, 43) },
	VBar = { w = 123, h = 1024, bar = Rect.new(29, 96, 93, 926) },
	Slot = { w = 512, h = 493, slice = Rect.new(128, 124, 384, 369), corner = 128 },
	Panel = { w = 512, h = 505, slice = Rect.new(126, 126, 386, 379), corner = 126 },
}

Exped.Color = {
	Panel = Color3.fromRGB(34, 34, 34), -- #222222
	PanelDeep = Color3.fromRGB(18, 18, 18), -- #121212 bar tracks
	Window = Color3.fromRGB(26, 26, 28),
	Health = Color3.fromRGB(163, 56, 56), -- #A33838
	HealthLag = Color3.fromRGB(247, 120, 122), -- #F7787A
	Stamina = Color3.fromRGB(0, 190, 221), -- #00BEDD
	Posture = Color3.fromRGB(232, 212, 96), -- #E8D460
	Silver = Color3.fromRGB(226, 226, 230),
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(190, 190, 194),
	Danger = Color3.fromRGB(255, 70, 64),
	Cooldown = Color3.fromRGB(103, 2, 4), -- #670204 cooldown pill
}

Exped.Font = {
	Regular = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	Bold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
	Heavy = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy),
}

local function new(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end
Exped.new = new

-- EXPED's house text stroke: 1.2 px black at 0.5 (163 uses in their UI)
function Exped.stroke(parent: Instance, thickness: number?, transparency: number?): UIStroke
	local s = new("UIStroke", {
		Color = Color3.new(0, 0, 0),
		Thickness = (thickness or 1.2) * Exped.getScale(),
		Transparency = transparency or 0.5,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Parent = parent,
	})
	s:SetAttribute("BaseThickness", thickness or 1.2) -- Kit.scaleStrokes keeps it crisp when the HUD scales
	return s
end

-- the faint vertical sheen on white titles (#D0D0D0 -> #ABABAB, rotation 90, offset 0.1)
function Exped.metal(parent: Instance): UIGradient
	return new("UIGradient", {
		Rotation = 90,
		Offset = Vector2.new(0, 0.1),
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 196, 198)),
		Parent = parent,
	})
end

function Exped.text(text: string, size: number, props: { [string]: any }?, bold: boolean?): TextLabel
	local p: { [string]: any } = {
		Text = text,
		FontFace = if bold == false then Exped.Font.Regular else Exped.Font.Bold,
		TextSize = size,
		TextColor3 = Exped.Color.Text,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, size + 4),
	}
	for k, v in props or {} do
		p[k] = v
	end
	local l = new("TextLabel", p)
	Exped.stroke(l)
	return l
end

-- A 9-sliced silver ornament frame laid over `target`. `corner` = on-screen corner size in px.
function Exped.frame(target: GuiObject, kind: string?, corner: number?, tint: Color3?, bleed: number?): ImageLabel
	local g = if kind == "Panel" then Exped.GEO.Panel else Exped.GEO.Slot
	local c = corner or 14
	local b = bleed or math.floor(c * 0.35)
	return new("ImageLabel", {
		Name = "ExpedFrame",
		Image = if kind == "Panel" then Exped.IMG.PanelFrame else Exped.IMG.SlotFrame,
		ImageColor3 = tint or Color3.new(1, 1, 1),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = g.slice,
		SliceScale = c / g.corner,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, b * 2, 1, b * 2),
		ZIndex = (target.ZIndex or 1) + 3,
		Parent = target,
	})
end

function Exped.icon(name: string, size: number, props: { [string]: any }?): ImageLabel
	local p: { [string]: any } = {
		Name = name,
		Image = (Exped.IMG :: any)[name] or "",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ScaleType = Enum.ScaleType.Fit,
	}
	for k, v in props or {} do
		p[k] = v
	end
	return new("ImageLabel", p)
end

-- Places a child rectangle given in art pixels (Rect) inside a frame drawn at `scale` px per art px.
function Exped.place(r: Rect, scale: number): (UDim2, UDim2)
	return UDim2.fromOffset(r.Min.X * scale, r.Min.Y * scale), UDim2.fromOffset((r.Max.X - r.Min.X) * scale, (r.Max.Y - r.Min.Y) * scale)
end

return Exped
