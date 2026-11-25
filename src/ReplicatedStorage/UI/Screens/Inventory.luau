--!strict
--[[
	Inventory - Deepwoken's inventory and character sheet (inventory.webp), in TRASH terms.
	  left   collapsible sections of item cards (EXPED dark slots, silver frame tinted by rarity,
	         quantity badge, rarity line), category labels in small caps, a search box that filters by name
	  right  character sheet: level emblem, name, faction / Relic / rank pills, the bound Relic
	         in 3D with its Blacksmith upgrade ladder (Z, X, C, M1 Mastery), skill path circles,
	         survival meters and wallet
	Items, the Relic and skill paths come from the Profile snapshot (TRASH-Progression Sync).
	Clicking an item with a use (food, water, bandages, respirators) sends UseItem; the server
	checks it and the effect shows up in the survival meters.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Icons = require(UI:WaitForChild("Icons"))
local Models = require(UI:WaitForChild("Models"))
local State = require(UI:WaitForChild("State"))
local MockData = require(UI:WaitForChild("MockData"))
local Profile = require(UI:WaitForChild("Profile"))
local Exped = require(UI:WaitForChild("Exped"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Levels = require(Shared:WaitForChild("Config"):WaitForChild("Levels"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))

local C, F, A = Theme.Color, Theme.Font, Theme.Attr

local Inventory = {}

local CARD = Vector2.new(78, 90)

local function rarityColor(r: string?): Color3
	return (Theme.Rarity :: any)[r or ""] or Theme.Rarity.Common
end

-- Item card, EXPED slot (2026-10-25): near-black with the silver frame (tinted above Common), the
-- name in white, a thin rarity line along the bottom and a framed quantity badge. Returns the button.
local function itemCard(parent: Instance, order: number, item: MockData.Item, tooltip: any, _taped: boolean): any
	local rc = rarityColor(item.rarity)
	local common = (item.rarity or "Common") == "Common"
	local card = Kit.new("TextButton", {
		Name = item.id,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = Exped.Color.Panel,
		BackgroundTransparency = 0.12,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
	})
	Exped.frame(card, "Slot", 12, if common then nil else rc:Lerp(Color3.new(1, 1, 1), 0.35))
	local name = Exped.text(item.name, 12, {
		Position = UDim2.fromOffset(5, 6),
		Size = UDim2.new(1, -10, 1, -22),
		TextWrapped = true,
		Parent = card,
	})
	name.TextYAlignment = Enum.TextYAlignment.Center
	Kit.new("Frame", {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.new(1, -18, 0, 2),
		BackgroundColor3 = rc,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = card,
	})
	if item.qty and item.qty > 1 then
		local badge = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, -3, 1, 3),
			Size = UDim2.fromOffset(0, 16),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Exped.Color.PanelDeep,
			ZIndex = 5,
			Parent = card,
		}, { Kit.pad(0, 4, 0, 4) })
		Exped.frame(badge, "Slot", 5, nil, 2).ZIndex = 6
		Exped.text("x" .. item.qty, 12, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 16),
			ZIndex = 7,
			Parent = badge,
		})
	end
	Kit.hover(card, card, 1.06)
	local usable = (item :: any).usable == true
	card.MouseEnter:Connect(function()
		local footer = if item.qty then "Carrying " .. item.qty else nil
		if usable then
			footer = (footer or "") .. "  ·  Click to use"
		end
		tooltip.show({ name = item.name, rarity = item.rarity, desc = item.desc, model = item.model, footer = footer })
		if not State.live then
			tooltip.place(card.AbsolutePosition.X / Kit.scale + CARD.X, card.AbsolutePosition.Y / Kit.scale)
		end
	end)
	card.MouseLeave:Connect(function()
		tooltip.hide()
	end)
	local onUse = (item :: any).onUse
	if usable and onUse then
		card.Activated:Connect(function()
			Kit.pop(card, 0.12)
			onUse()
		end)
	end
	return card
end

-- One collapsible section: serif title, count, +/- box, divider, category groups.
local function section(list: Instance, order: number, data: MockData.Section, tooltip: any, cards: { any })
	local holder = Kit.new("Frame", {
		Name = data.title,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = list,
	}, { Kit.list("Y", 6) })
	local header = Kit.new("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 1,
		Parent = holder,
	})
	Kit.label(data.title, F.Title, 19, C.Text, {
		Size = UDim2.new(1, -60, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	local count = 0
	for _, g in data.groups do
		count += #g.items
	end
	Kit.label(tostring(count), F.BodyBold, 17, C.TextDim, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -30, 0, 0),
		Size = UDim2.fromOffset(30, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = header,
	})
	local toggle = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -2, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.3,
		Parent = header,
	}, { Kit.stroke(C.SlateLine, 1, 0.2) })
	local toggleText = Kit.label("-", F.Header, 14, C.Text, { Size = UDim2.fromScale(1, 1), Parent = toggle })
	Kit.divider(C.SlateLine, { LayoutOrder = 2, Parent = holder })
	local content = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = holder,
	}, { Kit.list("Y", 4), Kit.pad(2, 0, 8, 4) })
	for gi, g in data.groups do
		Kit.label(string.upper(g.label), F.BodyBold, 13, C.TextDim, {
			Size = UDim2.new(1, 0, 0, 16),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = gi * 2 - 1,
			Parent = content,
		})
		local grid = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = gi * 2,
			Parent = content,
		}, { Kit.grid(CARD, Vector2.new(10, 12)), Kit.pad(4, 4, 6, 4) })
		for ii, item in g.items do
			local card = itemCard(grid, ii, item, tooltip, data.title == "Relic")
			table.insert(cards, { card = card, name = string.lower(item.name), grid = grid })
		end
	end
	header.Activated:Connect(function()
		content.Visible = not content.Visible
		toggleText.Text = if content.Visible then "-" else "+"
	end)
end

-- Deepwoken "Origin: Voidwalker" pill.
local function pill(parent: Instance, order: number, key: string, value: string, accent: Color3?)
	local row = Kit.new("Frame", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.25,
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.stroke(C.Gold, 1, 0.2), Kit.list("X", 8, nil, Enum.VerticalAlignment.Center), Kit.pad(0, 10, 0, 0) })
	local keyBox = Kit.new("Frame", {
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = C.GoldDark,
		LayoutOrder = 1,
		Parent = row,
	}, { Kit.pad(0, 8, 0, 8) })
	Kit.label(key .. ":", F.BodyBold, 15, C.GoldHi, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		Parent = keyBox,
	})
	Kit.label(value, F.BodyBold, 16, accent or C.Text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		LayoutOrder = 2,
		Parent = row,
	})
end

local function sheetHeading(parent: Instance, order: number, text: string)
	local h = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.label(string.upper(text), F.Title, 14, C.GoldHi, {
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = h,
	})
	Kit.divider(C.Gold, { Position = UDim2.fromOffset(0, 22), Parent = h })
end

-- Round stat badge (Deepwoken STR / FTD circles).
local function statCircle(parent: Instance, order: number, value: string, caption: string, color: Color3, size: number)
	local cell = Kit.new("Frame", {
		Size = UDim2.fromOffset(96, size + 22),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local ring = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		Parent = cell,
	}, { Kit.round(), Kit.stroke(color, 2) })
	Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -8, 1, -8),
		BackgroundTransparency = 1,
		Parent = ring,
	}, { Kit.round(), Kit.stroke(color, 1, 0.6) })
	Kit.label(value, F.Title, size * 0.4, C.Text, { Size = UDim2.fromScale(1, 1), Parent = ring })
	Kit.label(caption, F.BodyBold, 14, C.TextDim, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = cell,
	})
end

-- Blacksmith upgrade ladder: Z, X, C, then M1 Mastery.
local function ladder(parent: Instance, tier: number)
	local steps = { { "Z", "Ability 1" }, { "X", "Ability 2" }, { "C", "Ability 3" }, { "M1", "Mastery" } }
	local holder = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local spacing = 1 / (#steps - 1)
	Kit.new("Frame", {
		Position = UDim2.new(0, 17, 0, 16),
		Size = UDim2.new(1, -34, 0, 2),
		BackgroundColor3 = C.SlateLine,
		BackgroundTransparency = 0.4,
		Parent = holder,
	})
	if tier > 1 then
		Kit.new("Frame", {
			Position = UDim2.new(0, 17, 0, 16),
			Size = UDim2.new(spacing * (math.min(tier, #steps) - 1), -34 * spacing * (math.min(tier, #steps) - 1), 0, 2),
			BackgroundColor3 = C.Gold,
			Parent = holder,
		})
	end
	for i, s in steps do
		local reached = i <= tier
		local x = (i - 1) * spacing
		local node = Kit.new("Frame", {
			AnchorPoint = Vector2.new(x, 0),
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromOffset(34, 34),
			BackgroundColor3 = if reached then C.Gold else C.Night,
			Parent = holder,
		}, { Kit.round(), Kit.stroke(if reached then C.GoldHi else C.SlateLine, 1.5) })
		Kit.label(s[1], F.Header, 13, if reached then C.Ink else C.TextDim, { Size = UDim2.fromScale(1, 1), Parent = node })
		Kit.label(s[2], F.BodyBold, 13, if reached then C.GoldHi else C.TextMute, {
			AnchorPoint = Vector2.new(x, 0),
			Position = UDim2.new(x, 0, 0, 38),
			Size = UDim2.fromOffset(70, 16),
			TextXAlignment = if i == 1 then Enum.TextXAlignment.Left elseif i == #steps then Enum.TextXAlignment.Right else Enum.TextXAlignment.Center,
			Parent = holder,
		})
	end
end

local function miniMeter(parent: Instance, order: number, icon: string, label: string, color: Color3, attr: string)
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local glyph = Icons.make(icon, 20, color, C.Slate)
	glyph.Position = UDim2.fromOffset(0, 2)
	glyph.Parent = row
	Kit.label(label, F.BodyBold, 16, C.Text, {
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.fromOffset(90, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local bar = Kit.bar({ size = UDim2.new(1, -184, 0, 10), color = color, radius = 2 })
	bar.root.Position = UDim2.new(0, 124, 0.5, -5)
	bar.root.Parent = row
	Kit.stroke(C.GoldDark, 1).Parent = bar.root
	local pct = Kit.label("", F.BodyBold, 16, C.TextDim, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(50, 24),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	State.observe(attr, function(v)
		local max = State.max(attr)
		local value = if typeof(v) == "number" then v else max
		bar:set(value, max, true)
		pct.Text = math.floor(value / max * 100 + 0.5) .. "%"
	end)
end

export type InventoryContext = { tooltip: any, use: (itemId: string) -> () }

-- Snapshot items as card sections: one per category, grouped by material.
local function liveSections(snap: any, use: (string) -> ()): { MockData.Section }
	local owned = if snap then snap.items or {} else {}
	local sections: { MockData.Section } = {}
	for _, category in Items.CATEGORY_ORDER do
		local groups: { MockData.Group } = {}
		local byGroup: { [string]: MockData.Group } = {}
		for _, item in Items.list do
			local qty = owned[item.id] or 0
			if item.category == category and qty > 0 then
				local g = byGroup[item.group]
				if not g then
					g = { label = item.group, items = {} }
					byGroup[item.group] = g
					table.insert(groups, g)
				end
				local id = item.id
				local card: any = { id = id, name = item.name, rarity = item.rarity, desc = item.desc, model = item.model, qty = qty }
				if item.use then
					card.usable = true
					card.onUse = function()
						use(id)
					end
				end
				table.insert((g :: MockData.Group).items, card)
			end
		end
		if #groups > 0 then
			table.insert(sections, { title = category, groups = groups })
		end
	end
	return sections
end

function Inventory.build(root: Instance, ctx: InventoryContext): any
	local win = Kit.window({ name = "Inventory", title = "Inventory", size = Vector2.new(1260, 720) })
	win.frame.Parent = root

	-- ── left: item list ──
	local left = Kit.new("Frame", {
		Name = "Items",
		Size = UDim2.new(0, 600, 1, 0),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.55,
		Parent = win.body,
	}, { Kit.stroke(C.SlateLine, 1, 0.55) })
	local scroll = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 1, -50),
		Parent = left,
	}, { Kit.list("Y", 10), Kit.pad(10, 14, 10, 14) })
	local cards: { any } = {}
	-- search box
	local search = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 10, 1, -10),
		Size = UDim2.new(1, -20, 0, 32),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		Parent = left,
	}, { Kit.stroke(C.SlateLine, 1, 0.4), Kit.corner(3) })
	local lens = Kit.new("Frame", {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(12, 12),
		BackgroundTransparency = 1,
		Parent = search,
	}, { Kit.round(), Kit.stroke(C.TextDim, 2) })
	Kit.new("Frame", {
		Position = UDim2.fromOffset(11, 11),
		Size = UDim2.fromOffset(2, 7),
		Rotation = -45,
		BackgroundColor3 = C.TextDim,
		Parent = lens,
	})
	local box = Kit.new("TextBox", {
		Position = UDim2.fromOffset(32, 0),
		Size = UDim2.new(1, -40, 1, 0),
		Text = "",
		PlaceholderText = "Search...",
		PlaceholderColor3 = C.TextMute,
		FontFace = F.BodyItalic,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = search,
	})
	local function filter()
		local q = string.lower(box.Text)
		for _, c in cards do
			c.card.Visible = q == "" or string.find(c.name, q, 1, true) ~= nil
		end
	end
	box:GetPropertyChangedSignal("Text"):Connect(filter)

	local function renderItems(snap: any)
		for _, c in scroll:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		table.clear(cards)
		local sections = liveSections(snap, ctx.use)
		for i, s in sections do
			section(scroll, i, s, ctx.tooltip, cards)
		end
		if #sections == 0 then
			Kit.label("Your pockets are empty. Hold E on junk piles to salvage.", F.BodyItalic, 18, C.TextDim, {
				Size = UDim2.new(1, 0, 0, 40),
				TextWrapped = true,
				Parent = scroll,
			})
		end
		filter()
	end

	-- ── right: character sheet ──
	local sheet = Kit.new("ScrollingFrame", {
		Name = "Sheet",
		Position = UDim2.fromOffset(624, 0),
		Size = UDim2.new(1, -624, 1, 0),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.7,
		Parent = win.body,
	}, { Kit.stroke(C.SlateLine, 1, 0.55), Kit.list("Y", 12), Kit.pad(14, 18, 14, 18) })
	-- the blocks that change with the profile live in here and are rebuilt
	local dynamic = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = sheet,
	}, { Kit.list("Y", 12) })

	local function renderSheet(snap: any)
		for _, c in dynamic:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		-- identity block
		local idBlock = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 104),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Parent = dynamic,
		})
		local emblem = Kit.new("Frame", {
			Size = UDim2.fromOffset(96, 96),
			BackgroundColor3 = C.Night,
			Parent = idBlock,
		}, { Kit.round(), Kit.stroke(C.Gold, 2.5) })
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -12, 1, -12),
			BackgroundTransparency = 1,
			Parent = emblem,
		}, { Kit.round(), Kit.stroke(C.GoldDark, 1.5) })
		Kit.label(tostring(State.number(A.Level, 1)), F.Title, 36, C.GoldHi, {
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 0, 40),
			Parent = emblem,
		})
		Kit.label("LEVEL", F.HeaderBold, 11, C.TextDim, {
			Position = UDim2.fromOffset(0, 60),
			Size = UDim2.new(1, 0, 0, 14),
			Parent = emblem,
		})
		Kit.label(State.displayName(), F.Title, 26, C.Text, {
			Position = UDim2.fromOffset(112, 2),
			Size = UDim2.new(1, -112, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = idBlock,
		})
		local pills = Kit.new("Frame", {
			Position = UDim2.fromOffset(112, 40),
			Size = UDim2.new(1, -112, 0, 60),
			BackgroundTransparency = 1,
			Parent = idBlock,
		}, { Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(190, 24), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
		local faction = State.string(A.Faction, "Unaligned")
		local owned = snap and snap.relic
		local relic = owned and Relics.get(owned.id)
		pill(pills, 1, "Faction", faction, (C :: any)[faction])
		pill(pills, 2, "Rank", State.string(A.Rank, "Drifter"))
		pill(pills, 3, "Relic", if relic then relic.name else "None")
		pill(pills, 4, "Upgrade", string.format("%d / %d", if owned then owned.tier else 0, Economy.MAX_TIER))

		-- Relic
		sheetHeading(dynamic, 2, "Relic")
		local jBlock = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 170),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
			Parent = dynamic,
		})
		if not relic then
			Kit.label("No Relic yet. Your first roll is free once you have picked a side.", F.BodyItalic, 18, C.TextDim, {
				Size = UDim2.new(1, 0, 0, 60),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = jBlock,
			})
		else
			local relicRarity = owned.rarity
			local stage = Kit.new("Frame", {
				Size = UDim2.fromOffset(160, 160),
				BackgroundColor3 = C.Ink,
				BackgroundTransparency = 0.1,
				Parent = jBlock,
			})
			Kit.sunburst(stage, UDim2.fromScale(0.5, 0.5), 8, 120, rarityColor(relicRarity), 0.22)
			stage.ClipsDescendants = true
			local vp = Kit.viewport(Models.make(relic.model), { size = UDim2.fromScale(1, 1), yaw = 30, pitch = 14 })
			vp.Parent = stage
			-- the stage clips (sunburst, viewport), so its silver frame rides on an unclipped twin
			local rim = Kit.new("Frame", {
				Size = UDim2.fromOffset(160, 160),
				BackgroundTransparency = 1,
				Parent = jBlock,
			})
			Exped.frame(rim, "Slot", 16, rarityColor(relicRarity):Lerp(Color3.new(1, 1, 1), 0.4))
			local info = Kit.new("Frame", {
				Position = UDim2.fromOffset(178, 0),
				Size = UDim2.new(1, -178, 1, 0),
				BackgroundTransparency = 1,
				Parent = jBlock,
			})
			Kit.label(relic.name, F.Title, 24, C.Text, {
				Size = UDim2.new(1, 0, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = info,
			})
			local chip = Kit.new("Frame", {
				Position = UDim2.fromOffset(0, 34),
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = rarityColor(relicRarity),
				Parent = info,
			}, { Kit.corner(3), Kit.pad(0, 8, 0, 8), Kit.stroke(C.Ink, 1.5) })
			Kit.label(string.upper(relicRarity), F.Header, 12, C.Ink, {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 20),
				Parent = chip,
			})
			Kit.label(relic.style, F.BodyItalic, 17, C.TextDim, {
				Position = UDim2.fromOffset(0, 60),
				Size = UDim2.new(1, 0, 0, 40),
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				Parent = info,
			})
			local ladderHolder = Kit.new("Frame", {
				Position = UDim2.fromOffset(0, 108),
				Size = UDim2.new(1, -8, 0, 58),
				BackgroundTransparency = 1,
				Parent = info,
			})
			ladder(ladderHolder, owned.tier)
		end

		-- skill paths
		sheetHeading(dynamic, 4, "Skill Paths")
		local paths = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 82),
			BackgroundTransparency = 1,
			LayoutOrder = 5,
			Parent = dynamic,
		}, { Kit.list("X", 18, Enum.HorizontalAlignment.Left) })
		local perks = if snap then snap.perks or {} else {}
		for i, p in Levels.PATHS do
			statCircle(paths, i, string.format("%d/%d", perks[p.id] or 0, #p.perks), p.title, (Theme.PathColor :: any)[p.id], 58)
		end
		statCircle(paths, 4, tostring(if snap then snap.points or 0 else 0), "Unspent", C.Gold, 58)
	end

	-- survival
	sheetHeading(sheet, 6, "Survival")
	local meters = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 84),
		BackgroundTransparency = 1,
		LayoutOrder = 7,
		Parent = sheet,
	}, { Kit.list("Y", 6) })
	miniMeter(meters, 1, "bowl", "Hunger", C.Hunger, A.Hunger)
	miniMeter(meters, 2, "drop", "Thirst", C.Thirst, A.Thirst)
	miniMeter(meters, 3, "heart", "Vitality", C.Vitality, A.Vitality)

	Profile.observe(function(snap)
		renderItems(snap)
		renderSheet(snap)
	end)
	if not Profile.data then
		renderItems(nil)
		renderSheet(nil)
	end
	return { window = win }
end

return Inventory
