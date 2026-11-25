--!strict
--[[
	Station - an NPC's trade station (server: StationService), opened from their dialogue with
	OpenWindow("Station", { npc, kind, faction }).
	  Store       buy supplies (your own faction's quartermaster gives a discount)
	  Recycler    sort recyclables into Scrap; a first-time material teaches a Field Note
	  Fence       sell salvage for Dollars
	  Workbench   craft from salvage (filter water, bandages, respirators)
	  Purifier    Menders: clean Toxic Sludge into Purified Anima (cleans the air)
	  Smelter     Scrappers: smelt sludge into Hot Alloy and cash (dirties the air)
	Prices and rates shown are the server's Config values; every button only sends a request
	(StationAction) and the server checks and decides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Models = require(UI:WaitForChild("Models"))
local State = require(UI:WaitForChild("State"))
local Profile = require(UI:WaitForChild("Profile"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Environment = require(Shared:WaitForChild("Config"):WaitForChild("Environment"))
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Stations = require(Shared:WaitForChild("Data"):WaitForChild("Stations"))
local Npcs = require(Shared:WaitForChild("Data"):WaitForChild("Npcs"))

local C, F, A = Theme.Color, Theme.Font, Theme.Attr

local Station = {}

local ROW_H = 84
local ICON = 64
local BULK = 5

local TITLE: { [string]: string } = {
	Store = "Supply Store",
	Recycler = "Recycling Station",
	Fence = "Fence",
	Workbench = "Workbench",
	Purifier = "Purifier",
	Smelter = "Smelter",
}

local function blurb(kind: string, faction: string?): string
	local mine = State.string(A.Faction, Factions.UNALIGNED)
	if kind == "Store" then
		local discount = if faction and faction == mine then string.format(" Your faction's discount: %d%%.", math.floor(Economy.FACTION_STORE_DISCOUNT * 100 + 0.5)) else ""
		return "Food, water and medicine for Dollars." .. discount
	elseif kind == "Recycler" then
		local bonus = (Economy.SORT_BONUS :: any)[mine]
		return "Sort recyclables into Scrap for Relic upgrades. Each new material you sort teaches a Field Note."
			.. (if bonus then string.format(" %s get +%d%% Scrap.", mine, math.floor(bonus * 100 + 0.5)) else "")
	elseif kind == "Fence" then
		local bonus = (Economy.SELL_BONUS :: any)[mine]
		return "Sell salvage and spare parts for Dollars. No questions asked."
			.. (if bonus then string.format(" %s get +%d%% Dollars.", mine, math.floor(bonus * 100 + 0.5)) else "")
	elseif kind == "Workbench" then
		return "Turn salvage into survival: clean water, bandages and respirators for the Wastezone."
	elseif kind == "Purifier" then
		return "Menders only. Settle, filter and cleanse Toxic Sludge. Every batch makes the air cleaner for the whole server."
	elseif kind == "Smelter" then
		return "Scrappers only. Burn sludge and Scrap into Hot Alloy and cash. Every batch thickens the smog."
	end
	return ""
end

local function price(itemId: string, npcFaction: string?): number
	local base = (Economy.STORE :: any)[itemId] or 0
	local mine = State.get(A.Faction)
	local discount = if npcFaction and mine == npcFaction then Economy.FACTION_STORE_DISCOUNT else 0
	return math.max(1, math.floor(base * (1 - discount) + 0.5))
end

local function smallButton(parent: Instance, order: number, text: string, color: Color3, enabled: boolean, fn: () -> ())
	local _, button = Kit.gloss({
		text = text,
		color = if enabled then color else C.Slate,
		size = UDim2.fromOffset(110, 40),
		textSize = 18,
		layoutOrder = order,
		parent = parent,
		onClick = function()
			if enabled then
				fn()
			end
		end,
	})
	button.AutoButtonColor = false
end

-- one row: 3D icon, name and lines on the left, buttons on the right
local function row(parent: Instance, order: number, model: string, title: string, lines: { { text: string, color: Color3? } }): any
	local r = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.45,
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.corner(4), Kit.stroke(C.SlateLine, 1, 0.6) })
	local stage = Kit.new("Frame", {
		Position = UDim2.fromOffset(10, (ROW_H - ICON) / 2),
		Size = UDim2.fromOffset(ICON, ICON),
		BackgroundColor3 = C.Paper,
		Parent = r,
	}, { Kit.corner(3), Kit.vgrad(C.PaperHi, C.PaperDark), Kit.stroke(C.GoldDark, 1.5) })
	local vp = Kit.viewport(Models.make(model), { size = UDim2.fromScale(1, 1), yaw = 30, pitch = 16 })
	vp.Parent = stage
	local text = Kit.new("Frame", {
		Position = UDim2.fromOffset(ICON + 24, 8),
		Size = UDim2.new(1, -(ICON + 24 + 250), 1, -16),
		BackgroundTransparency = 1,
		Parent = r,
	}, { Kit.list("Y", 2) })
	Kit.label(title, F.Title, 17, C.Text, { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 0, Parent = text })
	for i, l in lines do
		Kit.label(l.text, F.Body, 15, l.color or C.TextDim, {
			Size = UDim2.new(1, 0, 0, 17),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = i,
			Parent = text,
		})
	end
	local buttons = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(240, 44),
		BackgroundTransparency = 1,
		Parent = r,
	}, { Kit.list("X", 10, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	return buttons
end

local function note(parent: Instance, order: number, text: string)
	Kit.label(text, F.BodyItalic, 17, C.TextDim, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	})
end

export type StationContext = { act: (npcId: string, action: string, id: string, qty: number) -> () }

function Station.build(root: Instance, ctx: StationContext): any
	local win = Kit.window({ name = "Station", title = "Station", size = Vector2.new(940, 660) })
	win.frame.Parent = root
	local title = win.frame:FindFirstChild("Title", true) :: TextLabel?
	local intro = Kit.label("", F.Serif, 17, C.Text, {
		Size = UDim2.new(1, 0, 0, 44),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = win.body,
	})
	local list = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 54),
		Size = UDim2.new(1, 0, 1, -54),
		Parent = win.body,
	}, { Kit.list("Y", 8), Kit.pad(4, 8, 8, 2) })

	local current: { npc: string, kind: string, faction: string? }? = nil

	local function clear()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end

	local function act(action: string, id: string, qty: number)
		if current then
			ctx.act(current.npc, action, id, qty)
		end
	end

	local function renderStore(npcFaction: string?)
		local dollars = State.number(A.Dollars, 0)
		local order = 0
		for _, item in Items.list do
			if (Economy.STORE :: any)[item.id] then
				order += 1
				local cost = price(item.id, npcFaction)
				local buttons = row(list, order, item.model, item.name, {
					{ text = item.desc },
					{ text = string.format("$%d each  ·  you have %d", cost, Profile.count(item.id)), color = C.Lime },
				})
				smallButton(buttons, 1, "x1  $" .. cost, C.Lime, dollars >= cost, function()
					act("Buy", item.id, 1)
				end)
				smallButton(buttons, 2, string.format("x%d", BULK), C.Lime, dollars >= cost * BULK, function()
					act("Buy", item.id, BULK)
				end)
			end
		end
	end

	-- Sort (Recycler) and Sell (Fence)
	local function renderTrade(mode: string)
		local mine = State.string(A.Faction, "")
		local bonus = if mode == "Sort" then (Economy.SORT_BONUS :: any)[mine] or 0 else (Economy.SELL_BONUS :: any)[mine] or 0
		local order = 1
		local total, any = 0, false
		for _, item in Items.list do
			local unit = if mode == "Sort" then item.sort else item.sell
			local eligible = unit ~= nil and (mode == "Sort" or (item.category ~= "Supplies" and item.category ~= "Tokens"))
			local have = Profile.count(item.id)
			if eligible and have > 0 then
				any = true
				order += 1
				local each = (unit :: number) * (1 + bonus)
				total += each * have
				local gain = if mode == "Sort" then string.format("%.3g Scrap each", each) else string.format("$%.3g each", each)
				local buttons = row(list, order, item.model, string.format("%s  x%d", item.name, have), {
					{ text = item.desc },
					{ text = gain, color = if mode == "Sort" then C.GoldHi else C.Lime },
				})
				smallButton(buttons, 1, "x1", C.Cyan, true, function()
					act(mode, item.id, 1)
				end)
				smallButton(buttons, 2, "ALL", C.Cyan, true, function()
					act(mode, item.id, have)
				end)
			end
		end
		if not any then
			note(list, 2, if mode == "Sort" then "You have nothing to sort. Salvage junk piles around the Heap for bottles, cans, rags, glass, rubber and wire." else "You have nothing worth selling. Salvage junk piles and beat Smoglings for parts.")
			return
		end
		local head = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 50),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = list,
		}, { Kit.list("X", 12, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
		Kit.label(string.format(if mode == "Sort" then "Everything: about %d Scrap" else "Everything: about $%d", math.floor(total + 0.5)), F.BodyBold, 18, C.TextDim, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 40),
			LayoutOrder = 1,
			Parent = head,
		})
		Kit.gloss({
			text = if mode == "Sort" then "SORT EVERYTHING" else "SELL EVERYTHING",
			color = if mode == "Sort" then C.Cyan else C.Lime,
			size = UDim2.fromOffset(240, 46),
			textSize = 22,
			layoutOrder = 2,
			parent = head,
			onClick = function()
				act(mode, "*", Economy.MAX_STACK)
			end,
		})
	end

	local function renderRecipes(kind: string)
		local recipeKind = Stations.KINDS[kind].recipes
		local scrap = State.number(A.Scrap, 0)
		local residue = State.number(A.Residue, 0)
		local action = if kind == "Workbench" then "Craft" else "Process"
		local order = 0
		for _, r in Stations.recipes do
			if r.kind == recipeKind then
				order += 1
				local parts, ready = {}, true
				for id, n in r.needs do
					local item = Items.get(id)
					local have = Profile.count(id)
					ready = ready and have >= n
					table.insert(parts, string.format("%s %d/%d", if item then item.name else id, have, n))
				end
				if r.scrap then
					ready = ready and scrap >= r.scrap
					table.insert(parts, string.format("Scrap %d/%d", scrap, r.scrap))
				end
				if r.residue then
					ready = ready and residue >= r.residue
					table.insert(parts, string.format("Residue %d/%d", residue, r.residue))
				end
				local gives = {}
				for id, n in r.gives do
					local item = Items.get(id)
					table.insert(gives, string.format("%dx %s", n, if item then item.name else id))
				end
				if r.dollars then
					table.insert(gives, "$" .. r.dollars)
				end
				local air = r.pollution and (Environment.DELTA :: any)[r.pollution]
				local lines = {
					{ text = r.desc },
					{ text = "Needs: " .. table.concat(parts, "  ·  "), color = if ready then C.Lime else C.Rust },
					{ text = "Makes: " .. table.concat(gives, ", ") .. (if air then string.format("   ·   Smog %s%.2g", if air > 0 then "+" else "", air) else ""), color = if air and air > 0 then C.Rust elseif air then C.Anima else C.GoldHi },
				}
				local first = next(r.gives)
				local model = if first then (Items.get(first) :: any).model else "Mystery"
				local buttons = row(list, order, model, r.name, lines)
				smallButton(buttons, 1, "MAKE", C.Lime, ready, function()
					act(action, r.id, 1)
				end)
				smallButton(buttons, 2, string.format("x%d", BULK), C.Lime, ready, function()
					act(action, r.id, BULK)
				end)
			end
		end
	end

	local function render()
		if not current then
			return
		end
		clear()
		local kind = current.kind
		local npc = Npcs.byId[current.npc]
		if title then
			title.Text = string.upper((TITLE[kind] or kind) .. (if npc then "  ·  " .. npc.name else ""))
		end
		intro.Text = blurb(kind, current.faction)
		if kind == "Store" then
			renderStore(current.faction)
		elseif kind == "Recycler" then
			renderTrade("Sort")
		elseif kind == "Fence" then
			renderTrade("Sell")
		elseif Stations.KINDS[kind] and Stations.KINDS[kind].recipes then
			renderRecipes(kind)
		end
	end

	Profile.observe(function()
		if win.frame.Visible then
			render()
		end
	end)
	for _, attr in { A.Dollars, A.Scrap, A.Residue } do
		State.observe(attr, function()
			if win.frame.Visible then
				render()
			end
		end)
	end

	local api = { window = win }
	function api.show(data: any)
		current = { npc = data.npc, kind = data.kind, faction = data.faction }
		render()
	end
	return api
end

return Station
