--!strict
--[[
	Notices - how progression news reaches the screen (server: Sync.notify).
	  banner  big moments, centred under the top bar: level up, rank up, quest complete, joined a
	          faction, Relic upgraded, new Field Note. A chunky title in the event's colour, a
	          serif line under it, and up to a few reward lines. One at a time, queued.
	  feed    small stacked lines above the wallet: salvage hauls and quest rewards. Each line
	          slides in, holds, then fades.
]]

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))

local C, F = Theme.Color, Theme.Font

local Notices = {}

local BANNER_HOLD = 3.2
local FEED_HOLD = 3.5
local FEED_MAX = 8

function Notices.build(root: Instance): any
	-- ── banner ──
	local banner = Kit.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 230),
		Size = UDim2.fromOffset(900, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 150,
		Parent = root,
	}, { Kit.list("Y", 4, Enum.HorizontalAlignment.Center) })
	local group = Kit.new("CanvasGroup", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 150,
		Parent = banner,
	}, { Kit.list("Y", 4, Enum.HorizontalAlignment.Center) })
	local title = Kit.chunky("", 58, C.GoldHi, { Size = UDim2.new(1, 0, 0, 64), LayoutOrder = 1, ZIndex = 151, Parent = group })
	local rule = Kit.new("Frame", {
		Size = UDim2.fromOffset(460, 2),
		BackgroundColor3 = C.Gold,
		LayoutOrder = 2,
		ZIndex = 151,
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
	local sub = Kit.label("", F.TitleItalic, 22, C.Text, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 3, ZIndex = 151, Parent = group })
	Kit.stroke(C.Ink, 1.5, 0.35).Parent = sub
	local extra = Kit.label("", F.BodyBold, 19, C.TextDim, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		LayoutOrder = 4,
		ZIndex = 151,
		Parent = group,
	})
	Kit.stroke(C.Ink, 1.2, 0.45).Parent = extra

	local queue: { { title: string, sub: string, color: Color3, lines: { string }? } } = {}
	local showing = false

	local function nextBanner()
		local b = table.remove(queue, 1)
		if not b then
			showing = false
			banner.Visible = false
			return
		end
		showing = true
		title.Text = string.upper(b.title)
		title.TextColor3 = b.color
		rule.BackgroundColor3 = b.color
		sub.Text = b.sub
		extra.Text = if b.lines and #b.lines > 0 then table.concat(b.lines, "   ·   ") else ""
		extra.Visible = extra.Text ~= ""
		banner.Visible = true
		group.GroupTransparency = 1
		Kit.tween(group, Theme.Tween.Med, { GroupTransparency = 0 })
		Kit.pop(title, 0.3)
		task.delay(BANNER_HOLD, function()
			Kit.tween(group, Theme.Tween.Slow, { GroupTransparency = 1 })
			task.delay(Theme.Tween.Slow.Time, nextBanner)
		end)
	end

	-- ── feed ──
	local feed = Kit.new("Frame", {
		Name = "Feed",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -170),
		Size = UDim2.fromOffset(360, 300),
		BackgroundTransparency = 1,
		ZIndex = 140,
		Parent = root,
	}, { Kit.list("Y", 2, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom) })
	local feedOrder = 0

	local api = {}

	function api.banner(t: string, s: string, color: Color3?, lines: { string }?)
		table.insert(queue, { title = t, sub = s, color = color or C.GoldHi, lines = lines })
		if not showing then
			nextBanner()
		end
	end

	function api.feed(lines: { string }, color: Color3?, heading: string?)
		local all = table.clone(lines)
		if heading then
			table.insert(all, 1, heading)
		end
		for i, text in all do
			feedOrder += 1
			local isHead = heading ~= nil and i == 1
			local l = Kit.hudText(text, if isHead then F.Title else F.BodyBold, if isHead then 18 else 17, if isHead then (color or C.GoldHi) else C.Text, {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 22),
				TextXAlignment = Enum.TextXAlignment.Right,
				LayoutOrder = feedOrder,
				ZIndex = 141,
				Parent = feed,
			})
			Kit.pop(l, 0.15)
			local stroke = l:FindFirstChildOfClass("UIStroke")
			task.delay(FEED_HOLD + i * 0.15, function()
				Kit.tween(l, Theme.Tween.Med, { TextTransparency = 1 })
				if stroke then
					Kit.tween(stroke, Theme.Tween.Med, { Transparency = 1 })
				end
				task.delay(Theme.Tween.Med.Time, function()
					l:Destroy()
				end)
			end)
		end
		-- keep the stack short
		local labels = {}
		for _, c in feed:GetChildren() do
			if c:IsA("TextLabel") then
				table.insert(labels, c)
			end
		end
		table.sort(labels, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for i = 1, #labels - FEED_MAX do
			labels[i]:Destroy()
		end
	end

	return api
end

return Notices
