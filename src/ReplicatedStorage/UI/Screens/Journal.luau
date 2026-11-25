--!strict
--[[
	Journal (J) - quests and Field Notes, from the Profile snapshot (server: QuestService,
	Progress, Titles). Three tabs:
	  Quests       left: running quests by line (Prologue, faction line, Side, Job), quests on
	               offer and who gives them, completed count. right: the selected quest's
	               summary, steps with progress, rewards, and Track / Abandon.
	  Field Notes  the real-world facts the player has unlocked by sorting, selling, crafting and
	               questing, grouped by topic, each with its source and one thing to try in real
	               life. Locked notes show how to find them.
	  Titles       every title in the game: earned ones in colour with Wear / Take off, locked
	               ones with how to earn them. The worn one shows over your head (Nameplate).
	Track and Abandon send TrackQuest / AbandonQuest, Wear sends EquipTitle; the server decides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Profile = require(UI:WaitForChild("Profile"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared:WaitForChild("Data"):WaitForChild("Quests"))
local FieldNotes = require(Shared:WaitForChild("Data"):WaitForChild("FieldNotes"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Npcs = require(Shared:WaitForChild("Data"):WaitForChild("Npcs"))
local Titles = require(Shared:WaitForChild("Data"):WaitForChild("Titles"))

local C, F = Theme.Color, Theme.Font

local Journal = {}

local LIST_W = 380
local ROW_H = 44
local LINE_TITLE = {
	Prologue = "What the Barges Bring",
	Menders = "Clean Slate",
	Scrappers = "Take What's Left",
	Side = "Side Stories",
	Job = "Odd Jobs",
}

local function lineColor(line: string): Color3
	return (Theme.LineColor :: any)[line] or C.Gold
end

local function npcName(id: string?): string
	local npc = id and Npcs.byId[id]
	return if npc then npc.name else (id or "?")
end

-- "+120 EXP · $40 · 2x Copper Wire"
function Journal.rewardText(r: any): string
	local parts = {}
	if r.exp then
		table.insert(parts, string.format("+%d EXP", r.exp))
	end
	if r.dollars then
		table.insert(parts, string.format("$%d", r.dollars))
	end
	if r.scrap then
		table.insert(parts, string.format("%d Scrap", r.scrap))
	end
	if r.residue then
		table.insert(parts, string.format("%d Anima Residue", r.residue))
	end
	if r.standing then
		table.insert(parts, string.format("+%d Standing", r.standing))
	end
	for id, n in r.items or {} do
		local item = Items.get(id)
		table.insert(parts, string.format("%dx %s", n, if item then item.name else id))
	end
	local title = r.title and Titles.byId[r.title]
	if title then
		table.insert(parts, "Title: " .. title.name)
	end
	return table.concat(parts, "  ·  ")
end

-- the text of the step the player is on, with progress ("Sort 3 / 5 piles")
function Journal.stepText(q: any, state: any): string
	if state.step > #q.steps then
		return if q.auto then "Finishing up..." else "Return to " .. npcName(q.turnIn or q.giver)
	end
	local step = q.steps[state.step]
	if step.count and step.count > 1 and step.type ~= "Upgrade" then
		return string.format("%s  (%d / %d)", step.text, math.min(state.progress or 0, step.count), step.count)
	end
	return step.text
end

local function clearList(frame: Instance)
	for _, c in frame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function groupLabel(parent: Instance, order: number, text: string, color: Color3)
	local h = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.label(string.upper(text), F.HeaderBold, 13, color, {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = h,
	})
	Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.5,
		Parent = h,
	})
end

local function listRow(parent: Instance, order: number, title: string, sub: string, color: Color3, selected: boolean, onClick: () -> ()): any
	local row = Kit.new("TextButton", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = if selected then C.SlateHi else C.Ink,
		BackgroundTransparency = if selected then 0.2 else 0.5,
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.corner(3) })
	Kit.new("Frame", {
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = color,
		Parent = row,
	}, { Kit.corner(2) })
	Kit.label(title, F.Title, 15, C.Text, {
		Position = UDim2.fromOffset(14, 4),
		Size = UDim2.new(1, -20, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	Kit.label(sub, F.Body, 14, C.TextDim, {
		Position = UDim2.fromOffset(14, 23),
		Size = UDim2.new(1, -20, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	row.MouseEnter:Connect(function()
		if not selected then
			Kit.tween(row, Theme.Tween.Fast, { BackgroundTransparency = 0.3 })
		end
	end)
	row.MouseLeave:Connect(function()
		if not selected then
			Kit.tween(row, Theme.Tween.Fast, { BackgroundTransparency = 0.5 })
		end
	end)
	row.Activated:Connect(onClick)
	return row
end

local function para(parent: Instance, order: number, text: string, font: Font, size: number, color: Color3): any
	return Kit.label(text, font, size, color, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		LayoutOrder = order,
		Parent = parent,
	})
end

local function tabButton(parent: Instance, order: number, text: string): (any, (boolean) -> ())
	local b = Kit.new("TextButton", {
		Size = UDim2.fromOffset(170, 34),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.3,
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.corner(3) })
	local stroke = Kit.stroke(C.SlateLine, 1, 0.4)
	stroke.Parent = b
	local label = Kit.label(string.upper(text), F.HeaderBold, 16, C.TextDim, { Size = UDim2.fromScale(1, 1), Parent = b })
	local function set(on: boolean)
		b.BackgroundColor3 = if on then C.GoldDark else C.Ink
		label.TextColor3 = if on then C.GoldHi else C.TextDim
		stroke.Color = if on then C.Gold else C.SlateLine
	end
	return b, set
end

export type JournalContext = { track: (string) -> (), abandon: (string) -> (), equip: ((string) -> ())? }

function Journal.build(root: Instance, ctx: JournalContext): any
	local win = Kit.window({ name = "Journal", title = "Journal", size = Vector2.new(1180, 720) })
	win.frame.Parent = root

	local tabs = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = win.body,
	}, { Kit.list("X", 10) })
	local questTab, setQuestTab = tabButton(tabs, 1, "Quests")
	local noteTab, setNoteTab = tabButton(tabs, 2, "Field Notes")
	local titleTab, setTitleTab = tabButton(tabs, 3, "Titles")
	local counter = Kit.label("", F.BodyBold, 16, C.TextDim, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(300, 34),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = win.body,
	})

	local left = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(0, LIST_W, 1, -46),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.55,
		Parent = win.body,
	}, { Kit.list("Y", 6), Kit.pad(10, 12, 10, 12), Kit.stroke(C.SlateLine, 1, 0.55) })
	local right = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(LIST_W + 18, 46),
		Size = UDim2.new(1, -(LIST_W + 18), 1, -46),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.7,
		Parent = win.body,
	}, { Kit.list("Y", 10), Kit.pad(16, 22, 16, 22), Kit.stroke(C.SlateLine, 1, 0.55) })

	local tab = "Quests"
	local selected: string? = nil -- quest id or note id
	local snap: any = nil

	local render: () -> ()

	local function questDetail(q: any, state: any?)
		local lc = lineColor(q.line)
		local head = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = right,
		}, { Kit.list("X", 8, nil, Enum.VerticalAlignment.Center) })
		local chip = Kit.new("Frame", {
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = lc,
			LayoutOrder = 1,
			Parent = head,
		}, { Kit.corner(3), Kit.pad(0, 8, 0, 8), Kit.stroke(C.Ink, 1.5) })
		Kit.label(string.upper(LINE_TITLE[q.line] or q.line), F.Header, 12, C.Ink, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), Parent = chip })
		Kit.label(q.kind .. " quest  ·  from " .. npcName(q.giver), F.BodyItalic, 16, C.TextDim, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			LayoutOrder = 2,
			Parent = head,
		})
		para(right, 2, q.title, F.Title, 30, C.Text)
		para(right, 3, q.summary, F.Serif, 18, C.TextDim)
		Kit.divider(C.Gold, { LayoutOrder = 4, Parent = right })
		Kit.label("STEPS", F.HeaderBold, 14, lc, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 5, Parent = right })
		for i, step in q.steps do
			local done = state ~= nil and i < state.step
			local current = state ~= nil and i == state.step
			local text = if current then Journal.stepText(q, state) else step.text
			local mark = if done then "✓" elseif current then "›" else "·"
			para(right, 5 + i, mark .. "  " .. text, if current then F.BodyBold else F.Body, 18, if done then C.TextMute elseif current then C.Text else C.TextDim)
		end
		if state and state.step > #q.steps and not q.auto then
			para(right, 20, "›  Return to " .. npcName(q.turnIn or q.giver), F.BodyBold, 18, C.GoldHi)
		end
		Kit.divider(C.Gold, { LayoutOrder = 21, Parent = right })
		Kit.label("REWARDS", F.HeaderBold, 14, lc, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 22, Parent = right })
		para(right, 23, Journal.rewardText(q.rewards), F.BodyBold, 18, C.GoldHi)
		if q.note then
			local note = FieldNotes.byId[q.note]
			if note then
				para(right, 24, "Teaches the Field Note: " .. note.title, F.BodyItalic, 16, C.Anima)
			end
		end
		if q.repeatable then
			para(right, 25, string.format("Repeatable every %d minutes.", math.floor(q.repeatable / 60)), F.BodyItalic, 15, C.TextDim)
		end
		if state then
			local actions = Kit.new("Frame", {
				Size = UDim2.new(1, 0, 0, 56),
				BackgroundTransparency = 1,
				LayoutOrder = 30,
				Parent = right,
			}, { Kit.list("X", 14) })
			Kit.gloss({
				text = if state.tracked then "UNTRACK" else "TRACK",
				color = if state.tracked then C.Slate else C.Cyan,
				size = UDim2.fromOffset(200, 48),
				textSize = 22,
				layoutOrder = 1,
				parent = actions,
				onClick = function()
					ctx.track(q.id)
				end,
			})
			if q.kind ~= "Main" then
				Kit.gloss({
					text = "ABANDON",
					color = C.Red,
					size = UDim2.fromOffset(200, 48),
					textSize = 22,
					layoutOrder = 2,
					parent = actions,
					onClick = function()
						ctx.abandon(q.id)
					end,
				})
			end
		end
	end

	local function renderQuests()
		local active = if snap and snap.quests then snap.quests.active else {}
		local done = if snap and snap.quests then snap.quests.done else {}
		local order = 0
		local first: string? = nil
		local count = 0
		for _, line in Quests.LINE_ORDER do
			local rows = {}
			for _, q in Quests.list do
				if q.line == line and active[q.id] then
					table.insert(rows, q)
				end
			end
			if #rows > 0 then
				order += 1
				groupLabel(left, order, LINE_TITLE[line] or line, lineColor(line))
				for _, q in rows do
					count += 1
					first = first or q.id
					order += 1
					local state = active[q.id]
					listRow(left, order, q.title, Journal.stepText(q, state), lineColor(line), selected == q.id, function()
						selected = q.id
						render()
					end)
				end
			end
		end
		local available = if snap then snap.available or {} else {}
		if #available > 0 then
			order += 1
			groupLabel(left, order, "On offer", C.Yellow)
			for _, a in available do
				local q = Quests.byId[a.id]
				if q then
					order += 1
					listRow(left, order, q.title, "Talk to " .. a.giverName, C.Yellow, selected == q.id, function()
						selected = q.id
						render()
					end)
				end
			end
		end
		local finished = 0
		for _ in done do
			finished += 1
		end
		order += 1
		groupLabel(left, order, string.format("Completed: %d", finished), C.TextMute)
		counter.Text = string.format("%d running  ·  %d / %d active max", count, count, Quests.MAX_ACTIVE)
		if not selected or not Quests.byId[selected] then
			selected = first
		end
		local q = selected and Quests.byId[selected]
		if q then
			questDetail(q, active[q.id])
		else
			para(right, 1, "No quests running. Talk to the people of the Gate Market: a gold ! over someone means they have work for you.", F.Serif, 18, C.TextDim)
		end
	end

	local function renderNotes()
		local unlocked = if snap then snap.notes or {} else {}
		local have = 0
		local order = 0
		local first: string? = nil
		for _, topic in FieldNotes.TOPIC_ORDER do
			order += 1
			groupLabel(left, order, topic, C.Anima)
			for _, n in FieldNotes.list do
				if n.topic == topic then
					order += 1
					local open = unlocked[n.id] ~= nil
					if open then
						have += 1
						first = first or n.id
					end
					listRow(left, order, if open then n.title else "???", if open then n.source else "Not found yet", if open then C.Anima else C.TextMute, selected == n.id, function()
						selected = n.id
						render()
					end)
				end
			end
		end
		counter.Text = string.format("Field Notes  %d / %d", have, #FieldNotes.list)
		if not selected or not FieldNotes.byId[selected] then
			selected = first
		end
		local n = selected and FieldNotes.byId[selected]
		if not n then
			para(right, 1, "Field Notes are real facts about trash, water and air. You find them by sorting and selling materials, crafting, and finishing quests.", F.Serif, 18, C.TextDim)
			return
		end
		if not unlocked[n.id] then
			para(right, 1, "???", F.Title, 30, C.TextMute)
			para(right, 2, "Sort or sell new materials, craft, and finish quests to find this note.", F.Serif, 18, C.TextDim)
			return
		end
		-- a parchment page
		local page = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.Paper,
			LayoutOrder = 1,
			Parent = right,
		}, { Kit.vgrad(C.PaperHi, C.PaperDark), Kit.pad(20, 24, 20, 24), Kit.list("Y", 12), Kit.corner(3) })
		Kit.stroke(C.GoldDark, 1.5).Parent = page
		Kit.tape(page, UDim2.new(0, 30, 0, 2), -14, 60)
		Kit.tape(page, UDim2.new(1, -30, 0, 2), 12, 60)
		Kit.label(string.upper(n.topic), F.HeaderBold, 13, C.GoldDark, { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = page })
		para(page, 2, n.title, F.Title, 28, C.PaperInk)
		para(page, 3, n.text, F.Serif, 19, C.PaperInk)
		para(page, 4, "Source: " .. n.source, F.BodyItalic, 16, C.GoldDark)
		local tip = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = C.Lime,
			BackgroundTransparency = 0.75,
			LayoutOrder = 5,
			Parent = page,
		}, { Kit.pad(10, 12, 10, 12), Kit.list("Y", 4), Kit.corner(3) })
		Kit.label("TRY THIS", F.Header, 13, C.LimeDark, { Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = tip })
		para(tip, 2, n.tip, F.BodyBold, 18, C.PaperInk)
	end

	local function renderTitles()
		local owned = if snap then snap.titles or {} else {}
		local worn = if snap then snap.title else nil
		local have = 0
		local first: string? = nil
		for i, t in Titles.list do
			local open = owned[t.id] ~= nil
			if open then
				have += 1
				first = first or t.id
			end
			local rc = (Theme.Rarity :: any)[t.rarity] or C.Gold
			listRow(left, i, (if open then t.name else "???") .. (if worn == t.id then "  (worn)" else ""), if open then t.rarity else t.how, if open then rc else C.TextMute, selected == t.id, function()
				selected = t.id
				render()
			end)
		end
		counter.Text = string.format("Titles  %d / %d", have, #Titles.list)
		if not selected or not Titles.byId[selected] then
			selected = first or (Titles.list[1] and Titles.list[1].id)
		end
		local t = selected and Titles.byId[selected]
		if not t then
			return
		end
		local open = owned[t.id] ~= nil
		local rc = (Theme.Rarity :: any)[t.rarity] or C.Gold
		para(right, 1, string.upper(t.rarity), F.HeaderBold, 14, rc)
		para(right, 2, if open then "« " .. t.name .. " »" else "???", F.Title, 34, if open then (t.color or C.Text) else C.TextMute)
		para(right, 3, (if open then "Earned: " else "How to earn it: ") .. t.how, F.Serif, 19, C.TextDim)
		if open and ctx.equip then
			local wearing = worn == t.id
			local equip = ctx.equip :: (string) -> ()
			Kit.gloss({
				text = if wearing then "TAKE OFF" else "WEAR",
				color = if wearing then C.Slate else rc,
				size = UDim2.fromOffset(220, 52),
				textSize = 24,
				layoutOrder = 4,
				parent = right,
				onClick = function()
					equip(if wearing then "" else t.id)
				end,
			})
		elseif not open then
			para(right, 4, "Titles show over your head for everyone once you wear one.", F.BodyItalic, 16, C.TextMute)
		end
	end

	render = function()
		clearList(left)
		clearList(right)
		setQuestTab(tab == "Quests")
		setNoteTab(tab == "Notes")
		setTitleTab(tab == "Titles")
		if tab == "Quests" then
			renderQuests()
		elseif tab == "Titles" then
			renderTitles()
		else
			renderNotes()
		end
	end

	questTab.Activated:Connect(function()
		if tab ~= "Quests" then
			tab = "Quests"
			selected = nil
			render()
		end
	end)
	noteTab.Activated:Connect(function()
		if tab ~= "Notes" then
			tab = "Notes"
			selected = nil
			render()
		end
	end)
	titleTab.Activated:Connect(function()
		if tab ~= "Titles" then
			tab = "Titles"
			selected = nil
			render()
		end
	end)

	Profile.observe(function(data)
		snap = data
		if win.frame.Visible or not snap then
			render()
		end
	end)
	win.frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if win.frame.Visible then
			render()
		end
	end)
	render()

	local api = { window = win }
	-- open on a title (from a "new title" banner)
	function api.showTitle(id: string)
		tab = "Titles"
		selected = id
		render()
	end
	-- open on a note (from a "new Field Note" toast)
	function api.showNote(id: string)
		tab = "Notes"
		selected = id
		render()
	end
	return api
end

return Journal
