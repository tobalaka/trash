--!strict
--[[
	FactionSelect - Menders or Scrappers (server: FactionService). Shown by the intro on the first
	PLAY (Screens/Intro, without its close button), or opened by a recruiter's dialogue
	(OpenWindow "FactionSelect") for characters from before the intro; the server only accepts
	SelectFaction before the first spawn, or for a short time after a recruiter offers it.
	Two cards side by side, each in the faction's colour: motto, ideology, how they salvage, their
	mark, what their work does to the Heap's air (from Config.Environment.DELTA), the ranks, and
	the three Relic in their roll pool with the odds. Joining is permanent for the character.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Models = require(UI:WaitForChild("Models"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))
local Environment = require(Shared:WaitForChild("Config"):WaitForChild("Environment"))
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))

local C, F = Theme.Color, Theme.Font

local FactionSelect = {}

local CARD_W = 560
local SWATCH = 92

-- what each side's work does to the server's air, worded for players
local function airLines(faction: string): { string }
	local d = Environment.DELTA :: { [string]: number }
	local function fmt(v: number): string
		return string.format("%s%.2g", if v > 0 then "+" else "", v)
	end
	if faction == "Menders" then
		return {
			string.format("Every pile you sort: smog %s", fmt(d.Sort)),
			string.format("Every batch of sludge you purify: smog %s", fmt(d.Purify)),
			"Clear skies mean more salvage for everyone on the server.",
		}
	end
	return {
		string.format("Every pile you strip: smog %s", fmt(d.Strip)),
		string.format("Every batch of sludge you smelt: smog %s", fmt(d.Smelt)),
		"Fast money now, thicker smog later. Somebody has to pay for it.",
	}
end

local function heading(parent: Instance, order: number, text: string, color: Color3)
	Kit.label(string.upper(text), F.HeaderBold, 14, color, {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function body(parent: Instance, order: number, text: string, color: Color3?, italic: boolean?)
	Kit.label(text, if italic then F.BodyItalic else F.Body, 17, color or C.Text, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function relicSwatch(parent: Instance, order: number, j: any)
	local rc = (Theme.Rarity :: any)[j.rarity] or Theme.Rarity.Common
	local cell = Kit.new("Frame", {
		Size = UDim2.fromOffset(SWATCH + 70, SWATCH + 46),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local stage = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(SWATCH, SWATCH),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.1,
		ClipsDescendants = true,
		Parent = cell,
	}, { Kit.corner(4), Kit.stroke(rc, 2) })
	Kit.sunburst(stage, UDim2.fromScale(0.5, 0.5), 8, 70, rc, 0.2)
	local vp = Kit.viewport(Models.make(j.model), { size = UDim2.fromScale(1, 1), yaw = 30, pitch = 14 })
	vp.Parent = stage
	Kit.label(j.name, F.Title, 14, C.Text, {
		Position = UDim2.fromOffset(0, SWATCH + 4),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = cell,
	})
	local odds = (Economy.ROLL_ODDS :: any)[j.rarity]
	Kit.label(string.format("%s · %s%%", j.rarity, tostring(odds or "?")), F.BodyBold, 13, rc, {
		Position = UDim2.fromOffset(0, SWATCH + 22),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = cell,
	})
end

local function card(parent: Instance, order: number, faction: string, join: (string) -> ()): any
	local info = Factions.INFO[faction]
	local fc = info.color
	local frame = Kit.new("Frame", {
		Name = faction,
		Size = UDim2.new(0, CARD_W, 1, 0),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.25,
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.corner(4) })
	local stroke = Kit.stroke(fc, 1.5, 0.3)
	stroke.Parent = frame
	-- colour band with the name
	local band = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 74),
		BackgroundColor3 = fc,
		Parent = frame,
	}, { Kit.corner(4), Kit.shade(0.55) })
	Kit.sheen(band, 4, 0.18)
	Kit.chunky(string.upper(info.name), 40, C.Text, {
		Position = UDim2.fromOffset(18, 4),
		Size = UDim2.new(1, -36, 0, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = band,
	})
	Kit.label(info.motto, F.TitleItalic, 16, C.Text, {
		Position = UDim2.fromOffset(20, 46),
		Size = UDim2.new(1, -40, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 2,
		Parent = band,
	})
	local scroll = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 80),
		Size = UDim2.new(1, 0, 1, -150),
		Parent = frame,
	}, { Kit.list("Y", 6), Kit.pad(6, 18, 10, 18) })
	body(scroll, 1, info.ideology, C.TextDim, true)
	heading(scroll, 2, "How you salvage: " .. info.method, fc)
	body(scroll, 3, info.methodDesc)
	heading(scroll, 4, "Your mark", fc)
	body(scroll, 5, info.identifierDesc)
	heading(scroll, 6, "What it does to the air", fc)
	for i, line in airLines(faction) do
		body(scroll, 6 + i, "•  " .. line, if i == 3 then C.TextDim else C.Text, i == 3)
	end
	heading(scroll, 10, "Ranks", fc)
	local names = {}
	for _, r in info.ranks do
		table.insert(names, r.name)
	end
	body(scroll, 11, table.concat(names, "  ›  "), C.TextDim)
	heading(scroll, 12, "Relic you can roll", fc)
	local pool = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, SWATCH + 50),
		BackgroundTransparency = 1,
		LayoutOrder = 13,
		Parent = scroll,
	}, { Kit.list("X", 10, Enum.HorizontalAlignment.Center) })
	local list = table.clone(Relics.byFaction[faction] or {})
	table.sort(list, function(a, b)
		return (table.find(Economy.RARITY_ORDER, a.rarity) or 0) < (table.find(Economy.RARITY_ORDER, b.rarity) or 0)
	end)
	for i, j in list do
		relicSwatch(pool, i, j)
	end
	-- join button
	local holder = Kit.gloss({
		text = "JOIN THE " .. string.upper(info.name),
		size = UDim2.new(1, -40, 0, 52),
		position = UDim2.new(0, 20, 1, -62),
		color = fc,
		textSize = 26,
		parent = frame,
		onClick = function()
			join(faction)
		end,
	})
	return { frame = frame, stroke = stroke, holder = holder }
end

export type FactionSelectContext = { join: (faction: string) -> () }

function FactionSelect.build(root: Instance, ctx: FactionSelectContext): any
	local win = Kit.window({ name = "FactionSelect", title = "Choose a Side", size = Vector2.new(CARD_W * 2 + 72, 760), style = "dark" })
	win.frame.Parent = root
	Kit.label("Joining is permanent for this character. Your first Relic roll is free.", F.BodyItalic, 16, C.TextDim, {
		Size = UDim2.new(1, 0, 0, 20),
		Parent = win.body,
	})
	local row = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 1, -28),
		BackgroundTransparency = 1,
		Parent = win.body,
	}, { Kit.list("X", 18, Enum.HorizontalAlignment.Center) })
	local cards: { [string]: any } = {}
	for i, f in Factions.LIST do
		cards[f] = card(row, i, f, ctx.join)
	end

	local api = { window = win }
	-- highlight the side whose recruiter opened the window
	function api.setSuggested(faction: string?)
		for f, c in cards do
			c.stroke.Transparency = if f == faction then 0 else 0.3
			c.stroke.Thickness = if f == faction then 3 else 1.5
		end
	end
	return api
end

return FactionSelect
