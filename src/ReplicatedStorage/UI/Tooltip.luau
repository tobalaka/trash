--!strict
--[[
	Tooltip - the Deepwoken item card that follows the mouse: a 3D model, the name in serif, a
	rarity line, a divider and an italic description. One shared instance per UI root.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Kit = require(script.Parent:WaitForChild("Kit"))
local Models = require(script.Parent:WaitForChild("Models"))

local C, F = Theme.Color, Theme.Font

export type TipData = {
	name: string,
	rarity: string?,
	desc: string?,
	model: string?,
	footer: string?,
	accent: Color3?,
}

export type Tooltip = {
	frame: any,
	show: (data: TipData) -> (),
	hide: () -> (),
	place: (x: number, y: number) -> (),
}

local WIDTH = 300

local Tooltip = {}

function Tooltip.new(root: Instance): Tooltip
	local frame = Kit.new("Frame", {
		Name = "Tooltip",
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Night,
		BackgroundTransparency = 0.04,
		Visible = false,
		ZIndex = 200,
		Parent = root,
	}, { Kit.vgrad(Color3.new(1, 1, 1), Color3.new(0.75, 0.75, 0.75)), Kit.pad(12, 14, 12, 14), Kit.list("Y", 6) })
	Kit.ornate(frame, { line = C.SlateLine, corner = C.Gold, inset = 3, cornerSize = 8 })

	local head = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 72),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		ZIndex = 200,
		Parent = frame,
	})
	local modelBox = Kit.new("Frame", {
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.3,
		ZIndex = 200,
		Parent = head,
	}, { Kit.corner(4) })
	local modelStroke = Kit.stroke(C.GoldDark, 1.5)
	modelStroke.Parent = modelBox
	local name = Kit.label("", F.Title, 20, C.Text, {
		Position = UDim2.fromOffset(84, 8),
		Size = UDim2.new(1, -84, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 201,
		Parent = head,
	})
	local rarity = Kit.label("", F.HeaderBold, 13, C.TextDim, {
		Position = UDim2.fromOffset(84, 38),
		Size = UDim2.new(1, -84, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 201,
		Parent = head,
	})
	local divider = Kit.divider(C.Gold, { LayoutOrder = 2, ZIndex = 201, Parent = frame })
	local desc = Kit.label("", F.BodyItalic, 17, C.TextDim, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		ZIndex = 201,
		Parent = frame,
	})
	local footer = Kit.label("", F.BodyBold, 15, C.GoldHi, {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 4,
		ZIndex = 201,
		Parent = frame,
	})

	local tip = {} :: Tooltip
	tip.frame = frame

	function tip.show(data: TipData)
		name.Text = data.name
		local rc = (Theme.Rarity :: any)[data.rarity or ""] or data.accent or C.TextDim
		rarity.Text = string.upper(data.rarity or "")
		rarity.TextColor3 = rc
		modelStroke.Color = rc
		divider.BackgroundColor3 = rc
		desc.Text = data.desc or ""
		footer.Text = data.footer or ""
		footer.Visible = data.footer ~= nil
		local old = modelBox:FindFirstChild("Viewport")
		if old then
			old:Destroy()
		end
		if data.model then
			local vp = Kit.viewport(Models.make(data.model), { size = UDim2.fromScale(1, 1) })
			vp.ZIndex = 201
			vp.Parent = modelBox
		end
		modelBox.Visible = data.model ~= nil
		name.Position = UDim2.fromOffset(if data.model then 84 else 0, 8)
		rarity.Position = UDim2.fromOffset(if data.model then 84 else 0, 38)
		head.Size = UDim2.new(1, 0, 0, if data.model then 72 else 56)
		frame.Visible = true
	end

	function tip.hide()
		frame.Visible = false
	end

	-- x, y in root (design) units; keeps the card on screen
	function tip.place(x: number, y: number)
		local parent = frame.Parent :: GuiObject
		local w = parent.AbsoluteSize.X / Kit.scale
		local h = parent.AbsoluteSize.Y / Kit.scale
		local fh = frame.AbsoluteSize.Y / Kit.scale
		local px = if x + 24 + WIDTH > w then x - WIDTH - 16 else x + 24
		local py = math.clamp(y + 16, 8, math.max(8, h - fh - 8))
		frame.Position = UDim2.fromOffset(px, py)
	end

	-- follow the mouse while visible (live play only)
	if RunService:IsRunning() then
		RunService.RenderStepped:Connect(function()
			if frame.Visible then
				local m = UserInputService:GetMouseLocation()
				tip.place(m.X / Kit.scale, m.Y / Kit.scale)
			end
		end)
	end

	return tip
end

return Tooltip
