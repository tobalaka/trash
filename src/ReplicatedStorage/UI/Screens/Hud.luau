--!strict
-- Display vitals, hotbar, cooldowns, menus, Relic abilities and currencies.
-- Read server-replicated values through State; never write gameplay state.
-- Skin and reference credits: UI/Exped.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Icons = require(UI:WaitForChild("Icons"))
local State = require(UI:WaitForChild("State"))
local MockData = require(UI:WaitForChild("MockData"))
local Exped = require(UI:WaitForChild("Exped"))

local Relics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Relics"))

local C, A = Theme.Color, Theme.Attr
local X = Exped.Color
local G = Exped.GEO
local GOLD_FRAME = Color3.fromRGB(255, 214, 128)

local Hud = {}

local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- A dark EXPED tile (#222 at 0.25) with the silver slot frame laid over it.
local function tile(className: string, props: { [string]: any }, corner: number?, tint: Color3?): (any, ImageLabel)
	local t = Kit.new(className, Kit.merge({
		BackgroundColor3 = X.Panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AutoButtonColor = if className == "TextButton" then false else nil,
		Text = if className == "TextButton" then "" else nil,
	}, props))
	local frame = Exped.frame(t, "Slot", corner or 12, tint)
	return t, frame
end

-- A meter inside a holder that does not clip (so a frame can sit around it).
local function meter(parent: Instance, position: UDim2, size: UDim2, color: Color3, opts: { [string]: any }?): any
	local o = opts or {}
	local bar = Kit.bar({
		size = size,
		color = color,
		vertical = o.vertical,
		centered = o.centered,
		trackColor = X.PanelDeep,
		trackTransparency = o.trackTransparency or 0.08,
		ghostColor = o.ghost,
		name = o.name,
	})
	bar.root.Position = position
	bar.root.ZIndex = 1
	bar.root.Parent = parent
	return bar
end

-- ── vitals ──────────────────────────────────────────────────────────────────

local VB_H = 170 -- on-screen height of the vertical frame
local VS = VB_H / G.VBar.h
local VB_W = math.floor(G.VBar.w * VS + 0.5)

local function vital(parent: Instance, order: number, icon: string, color: Color3, attr: string, statMode: () -> string): any
	local column = Kit.new("Frame", {
		Name = attr,
		Size = UDim2.fromOffset(30, VB_H + 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local holder = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(VB_W, VB_H),
		BackgroundTransparency = 1,
		Parent = column,
	})
	local pos, size = Exped.place(G.VBar.bar, VS)
	local bar = meter(holder, pos, size, color, { vertical = true, trackTransparency = 0.15 })
	Kit.new("ImageLabel", {
		Name = "Overlay",
		Image = Exped.IMG.VBarFrame,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = holder,
	})
	Exped.icon(icon, 20, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, VB_H + 22),
		Parent = column,
	})
	local label = Exped.text("", 12, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(44, 15),
		Visible = false,
		Parent = column,
	})
	local hovered = false
	local function refreshLabel()
		local mode = statMode()
		label.Visible = mode == "Always" or (mode == "Hover" and hovered)
	end
	column.MouseEnter:Connect(function()
		hovered = true
		refreshLabel()
	end)
	column.MouseLeave:Connect(function()
		hovered = false
		refreshLabel()
	end)
	State.observe(attr, function(v)
		local max = State.max(attr)
		local value = if typeof(v) == "number" then v else max
		bar:set(value, max, not State.live)
		label.Text = tostring(math.floor(value / max * 100 + 0.5)) .. "%"
	end)
	refreshLabel()
	return { refresh = refreshLabel }
end

-- ── the split bar (bottom-centre): health left, posture right ──────────────
-- User 2026-10-25: one long chain-framed bar, health in the left half (drains toward the left edge,
-- pink lag trail), posture in the right half (damage grows out from the centre ornament and warms
-- toward red near a break), the HP % on the health half.

local SB_W = 640
local SS = SB_W / G.Posture.w
local SB_H = math.floor(G.Posture.h * SS + 0.5)
local SPLIT_GAP = 0 -- the halves meet under the centre ornament (no gap)

local function splitBar(root: Instance, bottom: number, statMode: () -> string): (any, any)
	local frame = Kit.new("Frame", {
		Name = "VitalBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -bottom),
		Size = UDim2.fromOffset(SB_W, SB_H),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local r = G.Posture.bar
	local mid = G.Posture.w / 2
	local hpPos, hpSize = Exped.place(Rect.new(r.Min.X, r.Min.Y, mid - SPLIT_GAP, r.Max.Y), SS)
	local poPos, poSize = Exped.place(Rect.new(mid + SPLIT_GAP, r.Min.Y, r.Max.X, r.Max.Y), SS)
	local hp = meter(frame, hpPos, hpSize, X.Health, { ghost = X.HealthLag, name = "Health" })
	local post = meter(frame, poPos, poSize, X.Posture, { ghost = Color3.fromRGB(150, 128, 50), name = "Posture" })
	Kit.new("ImageLabel", {
		Name = "Overlay",
		Image = Exped.IMG.PostureFrame,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = frame,
	})
	local percent = Exped.text("", 14, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = hpPos + UDim2.fromOffset(hpSize.X.Offset / 2, hpSize.Y.Offset / 2),
		Size = UDim2.fromOffset(120, 16),
		ZIndex = 6,
		Parent = frame,
	})
	-- EXPED always shows the health percent; "Off" hides it, "Hover" only dims it until hovered
	local hovered = false
	local function refresh()
		local mode = statMode()
		percent.Visible = mode ~= "Off"
		percent.TextTransparency = if mode == "Hover" and not hovered then 0.35 else 0
	end
	frame.MouseEnter:Connect(function()
		hovered = true
		refresh()
	end)
	frame.MouseLeave:Connect(function()
		hovered = false
		refresh()
	end)
	State.observeHealth(function(h, m)
		hp:set(h, m, not State.live)
		percent.Text = string.format("%d%%", math.clamp(math.ceil(h / math.max(m, 1) * 100), 0, 100))
	end)
	State.observe(A.Posture, function(v)
		local max = State.max(A.Posture)
		local current = if typeof(v) == "number" then v else max
		local damage = math.clamp(1 - current / max, 0, 1)
		post:set(damage, 1, not State.live)
		post.fill.BackgroundColor3 = X.Posture:Lerp(C.Red, math.clamp((damage - 0.5) * 2, 0, 1))
	end)
	return frame, { refresh = refresh }
end

-- ── combat cooldown chips (under the health frame, EXPED IndicatorFrame) ────

local CHIP = 30

type Essential = { update: () -> () }

local function essentialChip(parent: Instance, order: number, def: { id: string, key: string, icon: string }): Essential
	local cell = Kit.new("Frame", {
		Name = def.id,
		Size = UDim2.fromOffset(CHIP, CHIP + 14),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local chip, frame = tile("Frame", {
		Size = UDim2.fromOffset(CHIP, CHIP),
		Parent = cell,
	}, 9)
	local glyph = Exped.icon(def.icon, 20, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
		Parent = chip,
	})
	local veil = Kit.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = X.Cooldown,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = chip,
	})
	local count = Exped.text("", 13, {
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Visible = false,
		Parent = chip,
	})
	Exped.text(def.key, 10, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, CHIP + 1),
		Size = UDim2.fromOffset(CHIP + 16, 12),
		TextColor3 = X.TextDim,
		Parent = cell,
	})
	local total, cooling = 0, false
	local function update()
		local left = State.cooldownLeft(def.id)
		if left > 0 then
			total = math.max(total, left)
			veil.Size = UDim2.fromScale(1, left / total)
			local text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
			if count.Text ~= text then
				count.Text = text
			end
			count.Visible = true
			glyph.ImageTransparency = 0.55
			cooling = true
		elseif cooling then
			cooling = false
			total = 0
			veil.Size = UDim2.fromScale(1, 0)
			count.Visible = false
			glyph.ImageTransparency = 0
			-- ready: the frame flashes gold and the chip pops
			frame.ImageColor3 = GOLD_FRAME
			Kit.tween(frame, Theme.Tween.Slow, { ImageColor3 = Color3.new(1, 1, 1) })
			Kit.pop(chip, 0.14)
		end
	end
	update()
	return { update = update }
end

-- ── hotbar ──────────────────────────────────────────────────────────────────

local SLOT = 56
local SLOT_GAP = 6
local HOTBAR_BOTTOM = 12

type Slot = { set: (item: { name: string, rarity: string }?, equipped: boolean) -> (), button: any }

local function slot(parent: Instance, index: number): Slot
	local cell = Kit.new("Frame", {
		Name = "Slot" .. index,
		Size = UDim2.fromOffset(SLOT, SLOT),
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Parent = parent,
	})
	local card, frame = tile("TextButton", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(SLOT, SLOT),
		Parent = cell,
	}, 12)
	local number = Exped.text(tostring(index % 10), 11, {
		Position = UDim2.fromOffset(5, 3),
		Size = UDim2.fromOffset(14, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = X.TextDim,
		ZIndex = 3,
		Parent = card,
	})
	local name = Exped.text("", 11, {
		Position = UDim2.fromOffset(4, 13),
		Size = UDim2.new(1, -8, 1, -20),
		TextWrapped = true,
		TextScaled = true,
		ZIndex = 3,
		Parent = card,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8, Parent = name })
	local rarity = Kit.new("Frame", {
		Name = "Rarity",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -16, 0, 2),
		BorderSizePixel = 0,
		BackgroundColor3 = Theme.Rarity.Common,
		ZIndex = 3,
		Visible = false,
		Parent = card,
	})
	local hovered, equipped = false, false
	local function lift()
		local up = if equipped then -6 elseif hovered then -3 else 0
		Kit.tween(card, Theme.Tween.Fast, { Position = UDim2.new(0.5, 0, 1, up) })
	end
	card.MouseEnter:Connect(function()
		hovered = true
		lift()
	end)
	card.MouseLeave:Connect(function()
		hovered = false
		lift()
	end)
	return {
		button = card,
		set = function(item, isEquipped)
			equipped = isEquipped and item ~= nil
			name.Text = if item then item.name else ""
			rarity.Visible = item ~= nil
			if item then
				rarity.BackgroundColor3 = (Theme.Rarity :: any)[item.rarity] or Theme.Rarity.Common
			end
			card.BackgroundTransparency = if item then 0.15 else 0.4
			frame.ImageColor3 = if equipped then GOLD_FRAME else Color3.new(1, 1, 1)
			frame.ImageTransparency = if item or equipped then 0 else 0.35
			number.TextColor3 = if equipped then GOLD_FRAME else X.TextDim
			card.Position = UDim2.new(0.5, 0, 1, if equipped then -6 else 0)
		end,
	}
end

-- ── abilities (right) ───────────────────────────────────────────────────────

local TILE = 68

type AbilityTile = { update: () -> (), setName: (string) -> () }

local function abilityTile(parent: Instance, order: number, def: { key: string, tier: number, ultimate: boolean? }, names: { [string]: string }): AbilityTile
	local t, frame = tile("Frame", {
		Name = def.key,
		Size = UDim2.fromOffset(TILE, TILE),
		LayoutOrder = order,
		Parent = parent,
	}, 13, if def.ultimate then GOLD_FRAME else nil)
	-- bands: name 4-31, "Upgrade N" 31-42, key 43-63 (lock icon in the bottom-right corner)
	local name = Exped.text(names[def.key] or "", 12, {
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, 27),
		TextWrapped = true,
		TextScaled = true,
		ZIndex = 3,
		Parent = t,
	})
	-- TextScaled works in on-screen pixels, so a small screen (UIScale ~0.5) needs room below 8 to fit
	Kit.new("UITextSizeConstraint", { MaxTextSize = 13, MinTextSize = 5, Parent = name })
	local key = Exped.text(def.key, 17, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -5),
		Size = UDim2.fromOffset(30, 20),
		ZIndex = 3,
		Parent = t,
	}, true)
	local lockNote = Exped.text("", 10, {
		Position = UDim2.fromOffset(0, 31),
		Size = UDim2.new(1, 0, 0, 11),
		TextColor3 = C.Rust,
		ZIndex = 3,
		Visible = false,
		Parent = t,
	})
	local lockIcon = Icons.make("lock", 12, X.TextDim, X.Panel)
	lockIcon.AnchorPoint = Vector2.new(1, 1)
	lockIcon.Position = UDim2.new(1, -5, 1, -6)
	lockIcon.ZIndex = 4
	lockIcon.Visible = false
	lockIcon.Parent = t
	local cool = Kit.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = X.Cooldown,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = t,
	})
	local coolText = Exped.text("", 22, {
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Visible = false,
		Parent = t,
	})
	local maxSeen = 0
	local function update()
		local tier = State.number(A.UpgradeTier, 0)
		local locked = def.tier > 0 and tier < def.tier
		name.TextColor3 = if locked then X.TextDim else X.Text
		key.TextColor3 = if locked then X.TextDim else X.Text
		lockIcon.Visible = locked
		lockNote.Visible = locked
		lockNote.Text = if locked then "Upgrade " .. def.tier else ""
		t.BackgroundTransparency = if locked then 0.45 else 0.25
		if def.ultimate then
			local full = State.number(A.Anima, 0) >= State.max(A.Anima)
			-- a full Anima rail: the gold frame breathes
			frame.ImageTransparency = if full then 0.25 * (0.5 + 0.5 * math.sin(os.clock() * 5)) else 0.35
			key.TextColor3 = if full then GOLD_FRAME else X.TextDim
			return
		end
		local left = if locked then 0 else State.cooldownLeft(def.key)
		if left > 0 then
			maxSeen = math.max(maxSeen, left)
			cool.Size = UDim2.fromScale(1, left / maxSeen)
			coolText.Visible = true
			coolText.Text = if left >= 1 then tostring(math.ceil(left)) else string.format("%.1f", left)
		elseif maxSeen > 0 then
			maxSeen = 0
			cool.Size = UDim2.fromScale(1, 0)
			coolText.Visible = false
			-- ready again (EXPED CooldownFX): the frame flashes gold and the tile pops
			frame.ImageColor3 = GOLD_FRAME
			Kit.tween(frame, Theme.Tween.Slow, { ImageColor3 = Color3.new(1, 1, 1) })
			Kit.pop(t, 0.12)
		end
	end
	update()
	return {
		update = update,
		setName = function(text: string)
			name.Text = text
			-- one long word shrinks to fit instead of breaking mid-word ("Downpo/ur")
			name.TextWrapped = string.find(text, " ") ~= nil
		end,
	}
end

-- ── currency ────────────────────────────────────────────────────────────────

local function currencyRow(parent: Instance, order: number, icon: string, attr: string)
	local row = Kit.new("Frame", {
		Name = attr,
		Size = UDim2.fromOffset(170, 30),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	-- no plate behind the number (user): icon + outlined white text, like EXPED's currency
	local pill = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(150, 26),
		BackgroundTransparency = 1,
		Parent = row,
	})
	local amount = Exped.text("0", 19, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -36, 0.5, 0),
		Size = UDim2.fromOffset(108, 20),
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
		Parent = pill,
	})
	Exped.icon(icon, 28, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -4, 0.5, 0),
		ZIndex = 5,
		Parent = pill,
	})
	local last: number? = nil
	State.observe(attr, function(v)
		local n = if typeof(v) == "number" then v else 0
		amount.Text = commas(n)
		if last and n ~= last then
			Kit.pop(amount, 0.12)
			local delta = n - last
			local float = Exped.text((if delta > 0 then "+" else "-") .. commas(math.abs(delta)), 15, {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -40, 0, 0),
				Size = UDim2.fromOffset(120, 18),
				TextXAlignment = Enum.TextXAlignment.Right,
				TextColor3 = if delta > 0 then C.Lime else X.Danger,
				ZIndex = 5,
				Parent = row,
			})
			local stroke = float:FindFirstChildOfClass("UIStroke")
			Kit.tween(float, Theme.Tween.Slow, { Position = float.Position - UDim2.fromOffset(0, 22), TextTransparency = 1 })
			if stroke then
				Kit.tween(stroke, Theme.Tween.Slow, { Transparency = 1 })
			end
			task.delay(0.7, function()
				float:Destroy()
			end)
		end
		last = n
	end)
end

-- ── side menu ───────────────────────────────────────────────────────────────

local MENU = { "Inventory", "Journal", "Skills", "Map", "Settings" }

local function keyName(k: Enum.KeyCode): string
	return if k == Enum.KeyCode.Tab then "TAB" else k.Name
end

local function menuTile(parent: Instance, order: number, id: string, onOpen: (string) -> ())
	local cell = Kit.new("Frame", {
		Name = id,
		Size = UDim2.fromOffset(64, 70),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local holder = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(48, 48),
		BackgroundTransparency = 1,
		Parent = cell,
	})
	local button = tile("TextButton", {
		Size = UDim2.fromScale(1, 1),
		Parent = holder,
	}, 12)
	Exped.icon(id, 30, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 2,
		Parent = button,
	})
	local key = (Theme.Keys :: any)[id]
	if key then
		local chip = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(1, -2, 0, 2),
			Size = UDim2.fromOffset(0, 15),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = X.PanelDeep,
			BackgroundTransparency = 0.1,
			ZIndex = 8,
			Parent = holder,
		}, { Kit.pad(0, 4, 0, 4) })
		Exped.frame(chip, "Slot", 5, nil, 2).ZIndex = 9
		Exped.text(keyName(key), 9, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 15),
			ZIndex = 10,
			Parent = chip,
		})
	end
	Exped.text(id, 12, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.fromOffset(70, 14),
		Parent = cell,
	})
	Kit.hover(button, holder, 1.06, 0)
	button.Activated:Connect(function()
		onOpen(id)
	end)
end

-- ── top info ────────────────────────────────────────────────────────────────

local function infoColumn(parent: Instance, order: number): (any, any)
	local col = Kit.new("Frame", {
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.list("Y", 0) })
	local top = Exped.text("", 16, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = col,
	})
	Exped.metal(top)
	local sub = Exped.text("", 13, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 17),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = X.TextDim,
		LayoutOrder = 2,
		Parent = col,
	}, false)
	return top, sub
end

local function uptime(seconds: number): string
	local d = math.floor(seconds / 86400)
	local h = math.floor(seconds % 86400 / 3600)
	local m = math.floor(seconds % 3600 / 60)
	return if d > 0 then string.format("%dd %dh %dm", d, h, m) else string.format("%dh %dm", h, m)
end

-- ── combat tag (EXPED "CombatTag": a chained heart while you're fighting) ───

local COMBAT_HOLD = 12 -- s after the last exchange the tag stays up
local COMBAT_KINDS = { Hit = true, Blocked = true, Parry = true, Break = true, Counter = true, WallSplat = true, Throw = true, GrabConnect = true }

local function combatTag(root: Instance): any
	local holder = Kit.new("Frame", {
		Name = "CombatTag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 142),
		Size = UDim2.fromOffset(160, 66),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = root,
	})
	local heart = Exped.icon("CombatHeart", 42, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Parent = holder,
	})
	local beat = Kit.new("UIScale", { Parent = heart })
	local label = Exped.text("IN DANGER", 13, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 44),
		Size = UDim2.fromOffset(160, 16),
		TextColor3 = Color3.fromRGB(255, 120, 110),
		Parent = holder,
	})
	local timer = Exped.text("", 13, {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 26, 0, 21),
		Size = UDim2.fromOffset(30, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = X.TextDim,
		Parent = holder,
	}, false)
	return { holder = holder, heart = heart, beat = beat, label = label, timer = timer }
end

-- ── build ───────────────────────────────────────────────────────────────────

export type HudContext = {
	settings: { [string]: any },
	open: (string) -> (),
}

function Hud.build(root: Instance, ctx: HudContext): any
	local layer = Kit.new("Frame", { Name = "Hud", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = root })
	local function statMode(): string
		return ctx.settings.StatValues or "Hover"
	end

	-- vitals (bottom-left)
	local vitals = Kit.new("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 22, 1, -14),
		Size = UDim2.fromOffset(3 * 30 + 2 * 10, VB_H + 44),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.list("X", 10) })
	local vitalRows = {
		vital(vitals, 1, "Hunger", C.Hunger, A.Hunger, statMode),
		vital(vitals, 2, "Thirst", C.Thirst, A.Thirst, statMode),
		vital(vitals, 3, "Vitality", C.Vitality, A.Vitality, statMode),
	}

	-- bottom-centre stack, bottom up: hotbar, the split bar (health | posture), the Anima thin bar,
	-- the combat cooldown chips
	local hotbarWidth = Theme.HOTBAR_SLOTS * (SLOT + SLOT_GAP) - SLOT_GAP
	local hotbar = Kit.new("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -HOTBAR_BOTTOM),
		Size = UDim2.fromOffset(hotbarWidth, SLOT),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.list("X", SLOT_GAP, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Bottom) })
	local slots: { Slot } = {}
	for i = 1, Theme.HOTBAR_SLOTS do
		slots[i] = slot(hotbar, i)
	end

	local splitBottom = HOTBAR_BOTTOM + SLOT + 6
	local _, health = splitBar(layer, splitBottom, statMode)

	-- Anima on the thin bar above it (EXPED's energy bar), cyan like their stamina
	local TF_W = 430
	local ts = TF_W / G.Thin.w
	local TF_H = math.floor(G.Thin.h * ts + 0.5)
	local thinBottom = splitBottom + SB_H + 1
	local thinFrame = Kit.new("Frame", {
		Name = "AnimaBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -thinBottom),
		Size = UDim2.fromOffset(TF_W, TF_H),
		BackgroundTransparency = 1,
		Parent = layer,
	})
	local tPos, tSize = Exped.place(G.Thin.bar, ts)
	local anima = meter(thinFrame, tPos, tSize, X.Stamina, { name = "Anima" })
	Kit.new("ImageLabel", {
		Name = "Overlay",
		Image = Exped.IMG.ThinFrame,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = thinFrame,
	})
	State.observe(A.Anima, function(v)
		anima:set(if typeof(v) == "number" then v else 0, State.max(A.Anima), not State.live)
	end)

	local chipsWidth = #Theme.Essentials * (CHIP + 10) - 10
	local chips = Kit.new("Frame", {
		Name = "Essentials",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(thinBottom + TF_H + 2)),
		Size = UDim2.fromOffset(chipsWidth, CHIP + 14),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.list("X", 10, Enum.HorizontalAlignment.Center) })
	local essentialChips: { Essential } = {}
	for i, def in Theme.Essentials do
		essentialChips[i] = essentialChip(chips, i, def)
	end

	-- abilities (right)
	local names: { [string]: string } = {}
	local abilityHeight = #Theme.Abilities * TILE + (#Theme.Abilities - 1) * 8
	local abilities = Kit.new("Frame", {
		Name = "Abilities",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -20, 0.5, 20),
		Size = UDim2.fromOffset(TILE, abilityHeight),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.list("Y", 8) })
	local tiles: { AbilityTile } = {}
	for i, def in Theme.Abilities do
		tiles[i] = abilityTile(abilities, i, def, names)
	end
	-- move names follow the wielded Relic
	State.observe(A.Relic, function(id)
		local j = Relics.get(if typeof(id) == "string" then id else nil)
		for i, def in Theme.Abilities do
			local ability = j and j.abilities[def.key]
			tiles[i].setName(if ability then ability.name else "")
		end
		abilities.Visible = j ~= nil
	end)

	-- currency (bottom-right)
	local wallet = Kit.new("Frame", {
		Name = "Wallet",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -22, 1, -14),
		Size = UDim2.fromOffset(170, 3 * 30 + 2 * 4),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.list("Y", 4, Enum.HorizontalAlignment.Right) })
	currencyRow(wallet, 1, "Dollars", A.Dollars)
	currencyRow(wallet, 2, "Scrap", A.Scrap)
	currencyRow(wallet, 3, "Residue", A.Residue)

	-- side menu (left)
	local menu = Kit.new("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, -30),
		Size = UDim2.fromOffset(64, #MENU * 76),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.list("Y", 6) })
	for i, id in MENU do
		menuTile(menu, i, id, ctx.open)
	end

	-- top info
	local info = Kit.new("Frame", {
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(700, 42),
		BackgroundTransparency = 1,
		Parent = layer,
	}, { Kit.list("X", 40, Enum.HorizontalAlignment.Center) })
	local regionName, regionSub = infoColumn(info, 1)
	local charName, charSub = infoColumn(info, 2)
	charName.Text = State.displayName()
	local function refreshChar()
		local faction = State.string(A.Faction, "Unaligned")
		local level = State.number(A.Level, 1)
		local need = State.get(A.ExpNext)
		local capped = level >= State.number(A.LevelMax, 40)
		local exp = if typeof(need) == "number" then string.format(if capped then "  ·  Overflow %d / %d" else "  ·  %d / %d EXP", State.number(A.Exp, 0), need) else ""
		charSub.Text = string.format("%s  ·  Lv.%d%s%s", faction, level, if capped then " MAX" else "", exp)
	end
	for _, attr in { A.Faction, A.Level, A.Exp, A.ExpNext, A.LevelMax } do
		State.observe(attr, refreshChar)
	end

	local tag = combatTag(layer)

	local hud = {}
	hud.layer = layer
	hud.menu = menu

	function hud.setRegion(key: string)
		local r = (Theme.Regions :: any)[key]
		regionName.Text = if r then r.name else key
	end
	hud.setRegion("Town")

	function hud.refreshStatMode()
		for _, v in vitalRows do
			(v :: any).refresh()
		end
		health.refresh()
	end

	-- hotbar contents: { {name, rarity} | false } per slot, plus the equipped slot index
	function hud.setHotbar(items: { any }, equipped: number?)
		for i, s in slots do
			local item = items[i]
			s.set(if item then item else nil, equipped == i)
		end
	end

	function hud.slotButtons(): { any }
		local out = {}
		for i, s in slots do
			out[i] = s.button
		end
		return out
	end

	-- preview contents
	if not State.live then
		local items = {}
		for i, id in MockData.hotbar do
			items[i] = (MockData.items :: any)[id]
		end
		hud.setHotbar(items, MockData.equippedSlot)
		regionSub.Text = "Server age 2h 14m"
		hud.setRegion("TownDome")
	else
		hud.setHotbar({}, nil)
		-- clock and cooldowns (10 Hz is plenty for numbers that change once a second)
		task.spawn(function()
			while layer.Parent do
				regionSub.Text = "Server age " .. uptime(workspace.DistributedGameTime)
				for _, t in tiles do
					t.update()
				end
				task.wait(0.1)
			end
		end)
		-- the combat tag: any exchange involving the local character keeps it up
		local combatUntil = 0
		local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
		local result = remotes and remotes:FindFirstChild("CombatResult")
		if result and result:IsA("RemoteEvent") then
			result.OnClientEvent:Connect(function(kind: string, attacker: Instance?, target: Instance?)
				local me = Players.LocalPlayer.Character
				if me and COMBAT_KINDS[kind] and (attacker == me or target == me) then
					if combatUntil <= os.clock() then
						tag.holder.Visible = true
						Kit.pop(tag.heart, 0.25)
					end
					combatUntil = os.clock() + COMBAT_HOLD
				end
			end)
		end
		-- essentials drain every frame: parry and roll cooldowns are about a second long
		local beat = RunService.Heartbeat:Connect(function()
			for _, t in essentialChips do
				t.update()
			end
			if tag.holder.Visible then
				local left = combatUntil - os.clock()
				if left <= 0 then
					tag.holder.Visible = false
				else
					tag.timer.Text = tostring(math.ceil(left))
					-- a heartbeat: two quick pulses per second
					local p = (os.clock() * 1.6) % 1
					tag.beat.Scale = 1 + 0.08 * math.max(0, math.sin(p * math.pi * 4)) * (if p < 0.5 then 1 else 0)
				end
			end
		end)
		layer.Destroying:Connect(function()
			beat:Disconnect()
		end)
	end
	hud.refreshStatMode()
	return hud
end

return Hud
