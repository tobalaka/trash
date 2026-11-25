--!strict
--[[
	Dialogue - talking to an NPC (server: NpcService). A slate panel above the hotbar in the
	Deepwoken style: a serif name plate in the NPC's faction colour, their lines typed out, an
	optional quest card (summary and rewards), and a column of choices in big Type Soul text with
	small tags (New, Side, Job, Quest, Trade, Ride, Faction, Active, Locked). Choosing sends
	DialogueChoice(npcId, optionId); the server answers with the next payload or closes it.
	A Modal button frees the mouse from shiftlock while the panel is open.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))

local Npcs = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Npcs"))
local Factions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Factions"))

local C, F = Theme.Color, Theme.Font

local Dialogue = {}

local WIDTH = 780
local BOTTOM = 250 -- clears the combat essentials row above the health bar
local TYPE_SPEED = 90 -- characters per second
local TAG_COLOR: { [string]: Color3 } = {
	New = Theme.Color.Yellow,
	Side = Theme.Color.Rust,
	Job = Theme.Color.Cyan,
	Quest = Theme.Color.Lime,
	Accept = Theme.Color.Lime,
	Trade = Theme.Color.GoldHi,
	Ride = Theme.Color.Cyan,
	Faction = Theme.Color.Magenta,
	Active = Theme.Color.TextDim,
	Locked = Theme.Color.TextMute,
}

export type DialogueContext = { choose: (npcId: string, optionId: string) -> () }

function Dialogue.build(root: Instance, ctx: DialogueContext): any
	local panel = Kit.new("Frame", {
		Name = "Dialogue",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Night,
		BackgroundTransparency = 0.06,
		Visible = false,
		ZIndex = 80,
		Parent = root,
	}, { Kit.vgrad(Color3.new(1, 1, 1), Color3.new(0.78, 0.78, 0.78)) })
	Kit.ornate(panel, { line = C.SlateLine, corner = C.Gold })
	Kit.new("TextButton", { Name = "Modal", Size = UDim2.fromScale(0, 0), Modal = true, Parent = panel })
	local scale = Kit.new("UIScale", { Parent = panel })
	-- the stacked content lives in its own frame so the list layout leaves the ornaments alone
	local content = Kit.new("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 81,
		Parent = panel,
	}, { Kit.pad(30, 26, 18, 26), Kit.list("Y", 10) })

	-- name plate on the top edge
	local plate = Kit.new("Frame", {
		Name = "Plate",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(22, 0),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Ink,
		ZIndex = 85,
		Parent = panel,
	}, { Kit.pad(0, 16, 0, 16), Kit.list("X", 10, nil, Enum.VerticalAlignment.Center) })
	local plateStroke = Kit.stroke(C.Gold, 1.5)
	plateStroke.Parent = plate
	local nameLabel = Kit.label("", F.Title, 19, C.GoldHi, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		LayoutOrder = 1,
		ZIndex = 86,
		Parent = plate,
	})
	local titleLabel = Kit.label("", F.BodyItalic, 16, C.TextDim, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		LayoutOrder = 2,
		ZIndex = 86,
		Parent = plate,
	})

	local text = Kit.label("", F.Serif, 20, C.Text, {
		Name = "Lines",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = 1,
		ZIndex = 82,
		Parent = content,
	})

	-- quest card (offers)
	local card = Kit.new("Frame", {
		Name = "QuestCard",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Paper,
		Visible = false,
		LayoutOrder = 2,
		ZIndex = 82,
		Parent = content,
	}, { Kit.vgrad(C.PaperHi, C.PaperDark), Kit.pad(10, 14, 10, 14), Kit.list("Y", 4), Kit.corner(3) })
	Kit.stroke(C.GoldDark, 1.5).Parent = card
	local cardTitle = Kit.label("", F.Title, 19, C.PaperInk, { Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, ZIndex = 83, Parent = card })
	local cardSummary = Kit.label("", F.BodyItalic, 17, C.PaperInk, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		ZIndex = 83,
		Parent = card,
	})
	local cardRewards = Kit.label("", F.BodyBold, 16, C.GoldDark, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		ZIndex = 83,
		Parent = card,
	})
	Kit.tape(card, UDim2.new(1, -30, 0, 2), 8, 46)

	Kit.divider(C.Gold, { LayoutOrder = 3, ZIndex = 82, Parent = content })
	local options = Kit.new("Frame", {
		Name = "Options",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		ZIndex = 82,
		Parent = content,
	}, { Kit.list("Y", 2) })

	local api: any = { frame = panel, npc = nil :: string? }
	local typeToken = 0

	local function typeOut(full: string)
		typeToken += 1
		local mine = typeToken
		text.Text = full
		if Kit.reduceMotion then
			text.MaxVisibleGraphemes = -1
			return
		end
		text.MaxVisibleGraphemes = 0
		task.spawn(function()
			local shown = 0
			local total = utf8.len(full) or #full
			while shown < total and typeToken == mine do
				shown = math.min(total, shown + math.max(1, math.floor(TYPE_SPEED / 30)))
				text.MaxVisibleGraphemes = shown
				task.wait(1 / 30)
			end
			if typeToken == mine then
				text.MaxVisibleGraphemes = -1
			end
		end)
	end

	local function option(order: number, o: { id: string, text: string, tag: string? })
		local row = Kit.new("TextButton", {
			Name = o.id,
			Size = UDim2.new(1, 0, 0, 36),
			LayoutOrder = order,
			ZIndex = 83,
			Parent = options,
		})
		local tagColor = (o.tag and TAG_COLOR[o.tag]) or C.TextDim
		local x = 0
		if o.tag then
			local tag = Kit.new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 0, 0.5, 0),
				Size = UDim2.fromOffset(0, 22),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = C.Ink,
				ZIndex = 84,
				Parent = row,
			}, { Kit.pad(0, 7, 0, 7), Kit.corner(3) })
			Kit.stroke(tagColor, 1.5).Parent = tag
			Kit.label(string.upper(o.tag), F.HeaderBold, 12, tagColor, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), ZIndex = 85, Parent = tag })
			x = 86
		end
		local label = Kit.label(o.text, F.HeaderBold, 21, if o.tag == "Locked" then C.TextMute else C.Text, {
			Position = UDim2.fromOffset(x, 0),
			Size = UDim2.new(1, -x, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 84,
			Parent = row,
		})
		row.MouseEnter:Connect(function()
			Kit.tween(label, Theme.Tween.Fast, { TextColor3 = tagColor, Position = UDim2.fromOffset(x + 6, 0) })
		end)
		row.MouseLeave:Connect(function()
			Kit.tween(label, Theme.Tween.Fast, { TextColor3 = if o.tag == "Locked" then C.TextMute else C.Text, Position = UDim2.fromOffset(x, 0) })
		end)
		row.Activated:Connect(function()
			if api.npc then
				ctx.choose(api.npc, o.id)
			end
		end)
	end

	function api.open(payload: any)
		if typeof(payload) ~= "table" then
			api.close()
			return
		end
		local npc = Npcs.byId[payload.npc]
		api.npc = payload.npc
		nameLabel.Text = if npc then npc.name else tostring(payload.npc)
		titleLabel.Text = if npc then npc.title else ""
		local fc = if npc and npc.faction then Factions.INFO[npc.faction].color else C.Gold
		nameLabel.TextColor3 = fc
		plateStroke.Color = fc
		typeOut(table.concat(payload.lines or {}, "\n"))
		local q = payload.quest
		card.Visible = typeof(q) == "table"
		if typeof(q) == "table" then
			cardTitle.Text = q.title
			cardSummary.Text = q.summary
			cardRewards.Text = "Rewards: " .. table.concat(q.rewards or {}, "  ·  ")
		end
		for _, c in options:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for i, o in payload.options or {} do
			option(i, o)
		end
		if not panel.Visible then
			panel.Visible = true
			scale.Scale = if Kit.reduceMotion then 1 else 0.92
			Kit.tween(scale, Theme.Tween.Pop, { Scale = 1 })
		end
	end

	function api.close()
		typeToken += 1
		api.npc = nil
		panel.Visible = false
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not panel.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
			if api.npc then
				ctx.choose(api.npc, "bye")
			end
			api.close()
		end
	end)

	return api
end

return Dialogue
