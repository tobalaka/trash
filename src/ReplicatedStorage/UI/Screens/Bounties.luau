--!strict
--[[
	Bounties - the Bounty Board at Clerk Odo's (server: TRASH-Progression Bounties; vault:
	Bounties). Opened by OpenWindow("Bounties", { npc, board }), built from what the server
	sends; it decides everything.
	  top     your heat, your own price and how many bounties you have claimed
	  left    everyone with a price: name in their side's colour, heat pips, WANTED at 3+, the
	          purse, posted money, and the region they were last seen in
	  right   whoever beat you in the last few minutes: put a price on them (+$50 / +$100 / +$250).
	          Sends PostBounty(userId, amount); the server checks the board, the window and your
	          Dollars, then reopens the window with the new numbers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))

local C, F = Theme.Color, Theme.Font

local Bounties = {}

local W, H = 1060, 680
local ROW_H = 58
local WANTED_COLOR = Color3.fromRGB(255, 120, 60)

local function clear(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function factionColor(f: any): Color3
	local info = if typeof(f) == "string" then Factions.INFO[f] else nil
	return if info then info.color else C.TextDim
end

local function heading(parent: Instance, order: number, text: string, color: Color3)
	Kit.label(string.upper(text), F.HeaderBold, 15, color, {
		Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function pips(heat: number, max: number): string
	return string.rep("●", heat) .. string.rep("○", math.max(0, max - heat))
end

local function regionName(key: any): string
	local r = if typeof(key) == "string" then (Theme.Regions :: any)[key] else nil
	return if r then r.name elseif typeof(key) == "string" then key else "somewhere"
end

export type BountiesContext = { post: (userId: number, amount: number) -> () }

function Bounties.build(root: Instance, ctx: BountiesContext): any
	local win = Kit.window({ name = "Bounties", title = "Bounty Board", size = Vector2.new(W, H), style = "dark" })
	win.frame.Parent = root

	local mine = Kit.label("", F.HeaderBold, 19, C.GoldHi, {
		Size = UDim2.new(1, 0, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = win.body,
	})
	local function column(x: number, w: number): any
		return Kit.new("ScrollingFrame", {
			Position = UDim2.new(x, if x > 0 then 9 else 0, 0, 36),
			Size = UDim2.new(w, -9, 1, -86),
			BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.5,
			Parent = win.body,
		}, { Kit.list("Y", 6), Kit.pad(10, 12, 10, 12), Kit.stroke(C.SlateLine, 1, 0.55) })
	end
	local left = column(0, 0.56)
	local right = column(0.56, 0.44)
	Kit.label("Bounties pay out only outside the faction bases. Posted money goes to whoever claims it, or back to you if it expires while you're here.", F.BodyItalic, 15, C.TextDim, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = win.body,
	})

	local api = { window = win }

	function api.show(data: any)
		clear(left)
		clear(right)
		local board = if typeof(data) == "table" and typeof(data.board) == "table" then data.board else {}
		local me = board.mine or {}
		local wantedAt = me.wantedAt or Factions.WANTED_HEAT
		mine.Text = string.format("Your heat %s   ·   your price $%d   ·   bounties claimed %d", pips(me.heat or 0, Factions.HEAT_MAX), me.value or 0, me.claims or 0)
		mine.TextColor3 = if (me.heat or 0) >= wantedAt then WANTED_COLOR else C.GoldHi

		heading(left, 1, "Wanted and priced", WANTED_COLOR)
		local list = board.list or {}
		if #list == 0 then
			Kit.label("Nobody has a price on them right now. Win fights outside the bases and yours will rise.", F.Body, 17, C.TextDim, {
				Size = UDim2.new(1, 0, 0, 44),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
				Parent = left,
			})
		end
		for i, b in list do
			local wanted = b.wanted == true
			local row = Kit.new("Frame", {
				Size = UDim2.new(1, 0, 0, ROW_H),
				BackgroundColor3 = if b.me then C.SlateHi else C.Coal,
				BackgroundTransparency = 0.25,
				LayoutOrder = i + 1,
				Parent = left,
			}, { Kit.corner(3) })
			Kit.new("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = factionColor(b.faction), Parent = row }, { Kit.corner(2) })
			if wanted then
				Kit.stroke(WANTED_COLOR, 1.5, 0.1).Parent = row
			end
			Kit.label(tostring(b.name) .. (if b.me then "  (you)" else ""), F.HeaderBold, 19, factionColor(b.faction), {
				Position = UDim2.fromOffset(14, 5),
				Size = UDim2.new(1, -150, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			Kit.label(string.format("%s  %s  ·  last seen in %s%s", if wanted then "WANTED" else "heat", pips(b.heat or 0, Factions.HEAT_MAX), regionName(b.region), if (b.posted or 0) > 0 then string.format("  ·  $%d posted", b.posted) else ""), F.Body, 15, if wanted then WANTED_COLOR else C.TextDim, {
				Position = UDim2.fromOffset(14, 30),
				Size = UDim2.new(1, -150, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = row,
			})
			Kit.chunky(string.format("$%d", b.value or 0), 28, C.GoldHi, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(130, 34),
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = row,
			})
		end

		heading(right, 1, "Put a price on someone who beat you", C.Rust)
		local postable = board.postable or {}
		if #postable == 0 then
			Kit.label("When a rival beats you, you have a few minutes to come here and put Dollars on their head.", F.Body, 17, C.TextDim, {
				Size = UDim2.new(1, 0, 0, 66),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = 2,
				Parent = right,
			})
		end
		for i, t in postable do
			local row = Kit.new("Frame", {
				Size = UDim2.new(1, 0, 0, 96),
				BackgroundColor3 = C.Coal,
				BackgroundTransparency = 0.25,
				LayoutOrder = i + 1,
				Parent = right,
			}, { Kit.corner(3) })
			Kit.label(tostring(t.name), F.HeaderBold, 19, factionColor(t.faction), {
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -24, 0, 22),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			})
			Kit.label(string.format("You've posted $%d of $%d  ·  %d:%02d left to post", t.posted or 0, board.max or Factions.BOUNTY_POST_MAX, (t.left or 0) // 60, (t.left or 0) % 60), F.Body, 15, C.TextDim, {
				Position = UDim2.fromOffset(12, 30),
				Size = UDim2.new(1, -24, 0, 18),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			})
			local buttons = Kit.new("Frame", {
				Position = UDim2.fromOffset(12, 52),
				Size = UDim2.new(1, -24, 0, 36),
				BackgroundTransparency = 1,
				Parent = row,
			}, { Kit.list("X", 8) })
			for j, amount in board.amounts or Factions.BOUNTY_POST_AMOUNTS do
				local b = Kit.outlineButton(string.format("+$%d", amount), Vector2.new(96, 34), {
					LayoutOrder = j,
					TextSize = 16,
					Parent = buttons,
				})
				b.Activated:Connect(function()
					ctx.post(t.userId, amount)
				end)
			end
		end
	end

	return api
end

return Bounties
