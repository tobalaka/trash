--!strict
--[[
	Skills - the skill path board, after Type Soul's moveset screen (moveset.png): one column per
	path with a loud colour header ("MARTIAL ARTS  2 / 6"), a near-black list of perks in big bold
	white, bought perks in the path colour, and a footer with the unspent points and the Stat
	Reset Pill. Hovering a perk shows the Deepwoken tooltip card.

	Paths and perks are Config.Levels.PATHS (passive perks, bought in order along a path; one
	skill point per level). Four paths of seven perks; the seventh is the path's Mastery, drawn in
	gold. A path costs 16 points and level 40 gives 39, so a build masters two paths at most. Clicking the next perk sends InvestPerk(pathId); the pill sends
	UseResetPill. The server checks points and order, and refunds.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local State = require(UI:WaitForChild("State"))
local Profile = require(UI:WaitForChild("Profile"))

local Levels = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Levels"))
local Exped = require(UI:WaitForChild("Exped"))

local C, F, A = Theme.Color, Theme.Font, Theme.Attr

local Skills = {}

local COLUMN_W = 300
local GAP = 16

local function column(parent: Instance, order: number, path: Levels.Path, bought: number, points: number, ctx: any)
	local color = (Theme.PathColor :: any)[path.id] or C.Rust
	local col = Kit.new("Frame", {
		Name = path.id,
		Size = UDim2.new(0, COLUMN_W, 1, 0),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	-- header: an EXPED dark strip with the path colour as a fading underline (2026-10-25)
	local header = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Exped.Color.PanelDeep,
		BackgroundTransparency = 0.1,
		Parent = col,
	})
	Exped.frame(header, "Slot", 10)
	Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(1, -16, 0, 2),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = header,
	}, {
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0),
				NumberSequenceKeypoint.new(0.8, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local title = Exped.text(string.upper(path.title), 18, {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -90, 1, -2),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = header,
	})
	Exped.metal(title)
	Exped.text(string.format("%d / %d", bought, #path.perks), 18, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 0),
		Size = UDim2.new(0, 70, 1, -2),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = Kit.tint(color, 0.25),
		ZIndex = 2,
		Parent = header,
	})
	Kit.label(path.desc, F.BodyItalic, 16, C.TextDim, {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = col,
	})
	-- perk list
	local body = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -80),
		BackgroundColor3 = Exped.Color.PanelDeep,
		BackgroundTransparency = 0.15,
		Parent = col,
	})
	Exped.frame(body, "Slot", 14).ZIndex = 6
	local scroll = Kit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		ScrollBarImageColor3 = C.TextDim,
		Parent = body,
	}, { Kit.list("Y", 6, Enum.HorizontalAlignment.Center), Kit.pad(12, 10, 12, 10) })
	for i, perk in path.perks do
		local owned = i <= bought
		local isNext = i == bought + 1
		local affordable = isNext and points >= perk.cost
		local row = Kit.new("TextButton", {
			Name = perk.id,
			Size = UDim2.new(1, 0, 0, 52),
			BackgroundColor3 = if owned then color:Lerp(Color3.new(0, 0, 0), 0.7) else Exped.Color.Panel,
			BackgroundTransparency = if owned then 0.15 elseif isNext then 0.2 else 0.65,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = i,
			Parent = scroll,
		})
		if owned then
			Kit.new("Frame", {
				Name = "Accent",
				Size = UDim2.new(0, 3, 1, -8),
				Position = UDim2.fromOffset(2, 4),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				Parent = row,
			})
		end
		if isNext or perk.capstone then
			-- the next perk wears the silver frame (tinted by the path when affordable), masteries gold
			local tint = if perk.capstone then Color3.fromRGB(255, 214, 128) elseif affordable then Kit.tint(color, 0.45) else nil
			local frame = Exped.frame(row, "Slot", 10, tint)
			frame.ImageTransparency = if isNext or owned then 0 else 0.55
		end
		local nameLabel = Kit.label(perk.name, F.HeaderBold, 20, if perk.capstone and (owned or isNext) then C.GoldHi elseif owned then color elseif isNext then C.Text else C.TextMute, {
			Position = UDim2.fromOffset(12, 4),
			Size = UDim2.new(1, -90, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		Kit.label((if perk.capstone then "MASTERY · " else "") .. (if owned then "Learned" elseif isNext then (if affordable then "Click to learn" else "Not enough points") else "Learn the one above first"), F.Body, 14, if perk.capstone then C.Gold else C.TextDim, {
			Position = UDim2.fromOffset(12, 30),
			Size = UDim2.new(1, -90, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
		local chip = Kit.new("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(62, 26),
			BackgroundColor3 = if owned then color:Lerp(Color3.new(0, 0, 0), 0.35) else Exped.Color.PanelDeep,
			BackgroundTransparency = 0.05,
			Parent = row,
		})
		Exped.frame(chip, "Slot", 7)
		Exped.text(if owned then "LEARNED" else string.format("%d PT", perk.cost), if owned then 10 else 13, { Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = chip })
		row.MouseEnter:Connect(function()
			Kit.tween(nameLabel, Theme.Tween.Fast, { Position = UDim2.fromOffset(18, 4) })
			ctx.tooltip.show({
				name = perk.name,
				rarity = nil,
				desc = perk.desc,
				footer = if owned then "Learned" else string.format("%d skill point%s", perk.cost, if perk.cost == 1 then "" else "s"),
				accent = color,
			})
			if not State.live then
				ctx.tooltip.place(row.AbsolutePosition.X / Kit.scale + COLUMN_W - 30, row.AbsolutePosition.Y / Kit.scale)
			end
		end)
		row.MouseLeave:Connect(function()
			Kit.tween(nameLabel, Theme.Tween.Fast, { Position = UDim2.fromOffset(12, 4) })
			ctx.tooltip.hide()
		end)
		row.Activated:Connect(function()
			if isNext then
				ctx.action("InvestPerk", path.id)
			end
		end)
	end
end

export type SkillsContext = { tooltip: any, action: (string, ...any) -> () }

function Skills.build(root: Instance, ctx: SkillsContext): any
	local width = #Levels.PATHS * COLUMN_W + (#Levels.PATHS - 1) * GAP + 36
	local win = Kit.window({ name = "Skills", title = "Skill Paths", size = Vector2.new(width, 760), style = "dark" })
	win.frame.Parent = root

	-- "Name - Rank" title line (Type Soul shows the character and grade above the board)
	local heading = Kit.label("", F.HeaderBold, 22, C.Text, {
		Size = UDim2.new(1, 0, 0, 30),
		Parent = win.body,
	})
	local board = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -110),
		BackgroundTransparency = 1,
		Parent = win.body,
	}, { Kit.list("X", GAP, Enum.HorizontalAlignment.Center) })

	-- footer: unspent points, the reset pill
	local footer = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundColor3 = Exped.Color.PanelDeep,
		BackgroundTransparency = 0.15,
		Parent = win.body,
	})
	Exped.frame(footer, "Slot", 12)
	local unspent = Kit.label("", F.HeaderBold, 20, C.GoldHi, {
		Position = UDim2.fromOffset(18, 0),
		Size = UDim2.new(1, -260, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = footer,
	})
	local pill = Kit.outlineButton("[USE RESET PILL]", Vector2.new(220, 40), {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		TextSize = 15,
		Parent = footer,
	})
	pill.Activated:Connect(function()
		ctx.action("ResetPill")
	end)

	local function render(snap: any)
		for _, c in board:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local perks = if snap then snap.perks or {} else {}
		local points = if snap then snap.points or 0 else 0
		for i, path in Levels.PATHS do
			column(board, i, path, perks[path.id] or 0, points, ctx)
		end
		heading.Text = string.format("%s  -  Level %d  ·  %s", State.displayName(), State.number(A.Level, 1), State.string(A.Rank, "Drifter"))
		unspent.Text = string.format("Unspent points: %d    (+%d a level, %d at level %d; a path costs %d)", points, Levels.POINTS_PER_LEVEL, Levels.MAX_POINTS, Levels.MAX, Levels.pathCost(Levels.PATHS[1]))
		local pills = Profile.count("ResetPill")
		pill.Text = string.format("[USE RESET PILL] x%d", pills)
		pill.TextTransparency = if pills > 0 then 0 else 0.5
	end
	Profile.observe(render)
	return { window = win }
end

return Skills
