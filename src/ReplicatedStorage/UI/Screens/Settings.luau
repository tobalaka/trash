--!strict
--[[
	Settings - Deepwoken's settings panel (the "something like that" shot): a row of framed tabs
	with counts, two columns of entries, each with a bold title, a fading divider, an italic
	description and a segmented On/Off control or a slider with a value box.

	Every option here really applies (through ctx.apply in UIController). Values live for the
	session; saving them to the profile is OPEN (DataStore-Schema).
]]

local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))

local C, F = Theme.Color, Theme.Font

local Settings = {}

export type Option = {
	key: string,
	title: string,
	desc: string,
	options: { string }?,
	min: number?,
	max: number?,
	step: number?,
	default: any,
}

export type Tab = { id: string, items: { Option }?, keys: boolean? }

Settings.TABS = {
	{
		id = "Interface",
		items = {
			{ key = "Cinematic", title = "Cinematic Mode", desc = "Hides the interface for recording. H restores it.", options = { "On", "Off" }, default = "Off" },
			{ key = "StatValues", title = "Stat Bar Values", desc = "Sets when your bars show their numbers.", options = { "Always", "Hover", "Off" }, default = "Hover" },
			{ key = "PlayerList", title = "Show Player List", desc = "Toggles the player list in the top right.", options = { "On", "Off" }, default = "On" },
			{ key = "RegionTitles", title = "Region Titles", desc = "Shows the region's name and lore when you enter it.", options = { "On", "Off" }, default = "On" },
			{ key = "SideMenu", title = "Menu Buttons", desc = "Shows the menu buttons on the left edge.", options = { "On", "Off" }, default = "On" },
			{ key = "UIScale", title = "Interface Scale", desc = "Scales every menu, bar and button.", min = 0.8, max = 1.2, step = 0.05, default = 1 },
		},
	},
	{
		id = "Graphics",
		items = {
			{ key = "Weather", title = "Weather Particles", desc = "Snow, ash, dust and spores around the camera.", options = { "On", "Off" }, default = "On" },
			{ key = "MenuBlur", title = "Menu Blur", desc = "Blurs the world behind open menus.", options = { "On", "Off" }, default = "On" },
			{ key = "Bloom", title = "Bloom", desc = "Glow around lamps, neon and bright sky.", options = { "On", "Off" }, default = "On" },
		},
	},
	{
		id = "Audio",
		items = {
			{key = "MasterVolume", title = "Master Volume", desc = "Overall sound level.", min = 0, max = 1, step = 0.05, default = 1},
			{key = "MusicVolume", title = "Music", desc = "Background soundtrack.", min = 0, max = 1, step = 0.05, default = 1},
			{key = "SFXVolume", title = "Effects", desc = "Combat, movement and footsteps.", min = 0, max = 1, step = 0.05, default = 1},
			{key = "AmbienceVolume", title = "Ambience", desc = "Wind and regional atmosphere.", min = 0, max = 1, step = 0.05, default = 1},
		},
	},
	{ id = "Controls", keys = true },
	{
		id = "Accessibility",
		items = {
			{ key = "ReduceMotion", title = "Reduce Motion", desc = "Turns off bounces, wiggles and pops.", options = { "On", "Off" }, default = "Off" },
			{ key = "SolidPanels", title = "Solid Panels", desc = "Removes panel transparency for easier reading.", options = { "On", "Off" }, default = "Off" },
		},
	},
} :: { Tab }

-- Keybind reference (02-Systems/Input/Keybinds plus the menu keys in Theme.Keys).
local KEYS = {
	{ "Mouse1", "Basic attack (5-hit combo)" },
	{ "Space + Mouse1", "Aerial attack" },
	{ "F", "Block / Parry" },
	{ "Ctrl + Mouse1", "Uptilt / Downslam" },
	{ "G + W / A / S / D", "Directional grab" },
	{ "Z  X  C", "Relic abilities" },
	{ "R", "Utility" },
	{ "B", "Ultimate (full Anima)" },
	{ "1 - 0", "Hotbar slots" },
	{ "Tab", "Inventory" },
	{ "K", "Skill paths" },
	{ "M", "Map" },
	{ "O", "Settings" },
}

function Settings.defaults(): { [string]: any }
	local out = {}
	for _, tab in Settings.TABS do
		for _, o in tab.items or {} do
			out[o.key] = o.default
		end
	end
	return out
end

local ACTIVE_TAB = Color3.fromRGB(96, 124, 70)

local function segmented(parent: Instance, o: Option, settings: { [string]: any }, apply: (string, any) -> ())
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = parent,
	}, { Kit.list("X", 4) })
	local buttons: { [string]: any } = {}
	local function paint()
		for name, b in buttons do
			local on = settings[o.key] == name
			b.BackgroundColor3 = if on then C.SlateHi else C.Ink
			b.BackgroundTransparency = if on then 0 else 0.45
			b.TextColor3 = if on then C.Text else C.TextMute
		end
	end
	for i, name in o.options or {} do
		local b = Kit.new("TextButton", {
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = name,
			FontFace = F.BodyBold,
			TextSize = 17,
			LayoutOrder = i,
			Parent = row,
		}, { Kit.pad(0, 9, 0, 9), Kit.corner(2), Kit.stroke(C.SlateLine, 1, 0.3, true) })
		buttons[name] = b
		b.Activated:Connect(function()
			settings[o.key] = name
			paint()
			apply(o.key, name)
		end)
	end
	paint()
end

local function slider(parent: Instance, o: Option, settings: { [string]: any }, apply: (string, any) -> ())
	local min, max, step = o.min or 0, o.max or 1, o.step or 0.05
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = parent,
	})
	local track = Kit.new("TextButton", {
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.fromOffset(290, 6),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.1,
		Parent = row,
	}, { Kit.corner(3), Kit.stroke(C.SlateLine, 1, 0.5, true) })
	local fill = Kit.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Gold,
		Parent = track,
	}, { Kit.corner(3) })
	local knob = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = C.Text,
		ZIndex = 3,
		Parent = track,
	}, { Kit.round(), Kit.stroke(C.Ink, 1.5) })
	for i, v in { min, (min + max) / 2, max } do
		Kit.label(string.format("%g", v), F.Body, 14, C.TextDim, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0, 10 + 290 * (i - 1) / 2, 0, 20),
			Size = UDim2.fromOffset(40, 16),
			Parent = row,
		})
	end
	local valueBox = Kit.new("Frame", {
		Position = UDim2.fromOffset(318, 0),
		Size = UDim2.fromOffset(52, 24),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		Parent = row,
	}, { Kit.corner(3), Kit.stroke(C.SlateLine, 1, 0.3) })
	local valueText = Kit.label("", F.BodyBold, 16, C.Text, { Size = UDim2.fromScale(1, 1), Parent = valueBox })
	local function paint()
		local f = (settings[o.key] - min) / (max - min)
		fill.Size = UDim2.fromScale(f, 1)
		knob.Position = UDim2.fromScale(f, 0.5)
		valueText.Text = string.format("%.2f", settings[o.key])
	end
	local dragging = false
	local function setFromX(x: number)
		local f = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local v = math.clamp(min + math.floor(f * (max - min) / step + 0.5) * step, min, max)
		if v ~= settings[o.key] then
			settings[o.key] = v
			paint()
		end
	end
	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			apply(o.key, settings[o.key]) -- apply on release: rescaling the UI mid-drag moves the track
		end
	end)
	paint()
end

local function entry(parent: Instance, order: number, o: Option, settings: { [string]: any }, apply: (string, any) -> ())
	local e = Kit.new("Frame", {
		Name = o.key,
		Size = UDim2.new(0.5, -14, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.list("Y", 4) })
	Kit.label(o.title, F.BodyBold, 21, C.Text, {
		Size = UDim2.new(1, 0, 0, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = e,
	})
	Kit.divider(C.SlateLine, { LayoutOrder = 2, Parent = e })
	Kit.label(o.desc, F.BodyItalic, 16, C.TextDim, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 3,
		Parent = e,
	})
	if o.options then
		segmented(e, o, settings, apply)
	else
		slider(e, o, settings, apply)
	end
end

local function keysPage(parent: Instance)
	for i, k in KEYS do
		local row = Kit.new("Frame", {
			Size = UDim2.new(0.5, -14, 0, 34),
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = parent,
		})
		local chip = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(0, 26),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Ink,
			Parent = row,
		}, { Kit.corner(4), Kit.stroke(C.Text, 1, 0.35), Kit.pad(0, 9, 0, 9) })
		Kit.label(k[1], F.HeaderBold, 14, C.Text, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 26),
			Parent = chip,
		})
		Kit.label(k[2], F.Body, 19, C.TextDim, {
			Position = UDim2.fromOffset(180, 0),
			Size = UDim2.new(1, -180, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})
	end
end

export type SettingsContext = {
	settings: { [string]: any },
	apply: (string, any) -> (),
}

function Settings.build(root: Instance, ctx: SettingsContext): any
	local win = Kit.window({ name = "Settings", title = "Settings", size = Vector2.new(1120, 660) })
	win.frame.Parent = root

	local tabRow = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = win.body,
	}, { Kit.list("X", 6) })
	local pages = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(1, 0, 1, -46),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.6,
		Parent = win.body,
	}, { Kit.stroke(C.SlateLine, 1, 0.5) })

	local tabButtons: { [string]: any } = {}
	local pageFrames: { [string]: any } = {}
	local function select(id: string)
		for name, b in tabButtons do
			local on = name == id
			b.BackgroundColor3 = if on then ACTIVE_TAB else C.Night
			b.TextColor3 = if on then C.Text else C.TextDim
			pageFrames[name].Visible = on
		end
	end
	for i, tab in Settings.TABS do
		local count = if tab.keys then #KEYS else #(tab.items or {})
		local b = Kit.new("TextButton", {
			Name = tab.id,
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 0,
			Text = string.format("%s (%d)", tab.id, count),
			FontFace = F.BodyBold,
			TextSize = 18,
			LayoutOrder = i,
			Parent = tabRow,
		}, { Kit.pad(0, 14, 0, 14), Kit.stroke(C.SlateLine, 1, 0.15, true) })
		tabButtons[tab.id] = b
		local page = Kit.new("ScrollingFrame", {
			Name = tab.id,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Parent = pages,
		}, {
			Kit.new("UIGridLayout", {
				CellSize = UDim2.new(0.5, -14, 0, if tab.keys then 34 else 132),
				CellPadding = UDim2.fromOffset(28, if tab.keys then 6 else 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Kit.pad(16, 22, 16, 22),
		})
		pageFrames[tab.id] = page
		if tab.keys then
			keysPage(page)
		else
			for j, o in tab.items or {} do
				entry(page, j, o, ctx.settings, ctx.apply)
			end
		end
		b.Activated:Connect(function()
			select(tab.id)
		end)
	end
	select("Interface")
	return { window = win }
end

return Settings
