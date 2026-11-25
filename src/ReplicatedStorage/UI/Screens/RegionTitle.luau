--!strict
--[[
	RegionTitle - Deepwoken's region card ("SONGSEEKER WILDS" in inventory.webp): the region name in
	serif capitals between two ornaments, a gold rule that draws outward, and a line of lore.
	Fades in, holds, fades out. Names and lore live in Theme.Regions.
]]

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))

local C, F = Theme.Color, Theme.Font

local RegionTitle = {}

local HOLD = 4

local function ornament(): any
	local o = Kit.new("Frame", {
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
	})
	for _, s in { 20, 10 } do
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(s, s),
			Rotation = 45,
			BackgroundColor3 = if s == 20 then C.Gold else C.Ink,
			Parent = o,
		}, { Kit.stroke(C.Ink, 1.5, 0.2) })
	end
	return o
end

function RegionTitle.build(root: Instance): any
	local card = Kit.new("Frame", {
		Name = "RegionTitle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 150),
		Size = UDim2.fromOffset(900, 140),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	local group = Kit.new("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Parent = card,
	})
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundTransparency = 1,
		Parent = group,
	}, { Kit.list("X", 16, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local left = ornament()
	left.LayoutOrder = 1
	left.Parent = row
	local title = Kit.label("", F.Title, 38, C.Text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 46),
		LayoutOrder = 2,
		Parent = row,
	})
	Kit.stroke(C.Ink, 2, 0.35).Parent = title
	local right = ornament()
	right.LayoutOrder = 3
	right.Parent = row
	local rule = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(0, 2),
		BackgroundColor3 = C.Gold,
		Parent = group,
	}, {
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local lore = Kit.label("", F.Serif, 20, C.Text, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 68),
		Size = UDim2.fromOffset(620, 60),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = group,
	})
	Kit.stroke(C.Ink, 1.5, 0.45).Parent = lore

	local token = 0
	local api = { frame = card }

	-- `static` shows the card fully (edit-mode preview) instead of animating it.
	function api.show(key: string, static: boolean?)
		local info = (Theme.Regions :: any)[key]
		if not info then
			return
		end
		token += 1
		local mine = token
		title.Text = string.upper(info.name)
		lore.Text = info.lore
		card.Visible = true
		if static then
			group.GroupTransparency = 0
			rule.Size = UDim2.fromOffset(520, 2)
			return
		end
		group.GroupTransparency = 1
		rule.Size = UDim2.fromOffset(0, 2)
		Kit.tween(group, Theme.Tween.Fade, { GroupTransparency = 0 })
		Kit.tween(rule, Theme.Tween.Fade, { Size = UDim2.fromOffset(520, 2) })
		task.delay(HOLD, function()
			if token ~= mine then
				return
			end
			Kit.tween(group, Theme.Tween.Fade, { GroupTransparency = 1 })
			task.delay(Theme.Tween.Fade.Time, function()
				if token == mine then
					card.Visible = false
				end
			end)
		end)
	end

	return api
end

return RegionTitle
