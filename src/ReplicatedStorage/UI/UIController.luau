--!strict
-- Mount the interface, intro, menus and hotbar from server-replicated state.
-- start() runs for players; preview() builds edit-mode screens with MockData.
-- Open menus release the mouse without changing combat or movement.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local State = require(UI:WaitForChild("State"))
local Tooltip = require(UI:WaitForChild("Tooltip"))
local Screens = UI:WaitForChild("Screens")
local Hud = require(Screens:WaitForChild("Hud"))
local Inventory = require(Screens:WaitForChild("Inventory"))
local Skills = require(Screens:WaitForChild("Skills"))
local Settings = require(Screens:WaitForChild("Settings"))
local WorldMap = require(Screens:WaitForChild("WorldMap"))
local RegionTitle = require(Screens:WaitForChild("RegionTitle"))
local PlayerList = require(Screens:WaitForChild("PlayerList"))
local Journal = require(Screens:WaitForChild("Journal"))
local Station = require(Screens:WaitForChild("Station"))
local Blacksmith = require(Screens:WaitForChild("Blacksmith"))
local Bounties = require(Screens:WaitForChild("Bounties"))
local Admin = require(Screens:WaitForChild("Admin"))
local FactionSelect = require(Screens:WaitForChild("FactionSelect"))
local Dialogue = require(Screens:WaitForChild("Dialogue"))
local RollReveal = require(Screens:WaitForChild("RollReveal"))
local QuestTracker = require(Screens:WaitForChild("QuestTracker"))
local AirQuality = require(Screens:WaitForChild("AirQuality"))
local Notices = require(Screens:WaitForChild("Notices"))
local Intro = require(Screens:WaitForChild("Intro"))
local Profile = require(UI:WaitForChild("Profile"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))

local C = Theme.Color

local UIController = {}

local DIM_TRANSPARENCY = 0.5
local BLUR_SIZE = 14
local TOAST_TIME = 2.6
local REGION_CHECK = 0.5

-- feed heading per salvage method (Notify "Salvage")
local SALVAGE_HEADING: { [string]: string } = {
	Sort = "Sorted",
	Strip = "Stripped",
	Salvage = "Salvaged",
	Smogling = "Smogling cleared",
	Apex = "Apex Smogling broken",
	Smash = "Smashed",
	Pickup = "Picked up",
}

-- Builds every screen into `root`. Shared by start() and preview().
function UIController.mount(root: any, settings: { [string]: any }, rescale: () -> ()): any
	local ui: any = {}
	ui.settings = settings
	ui.current = nil :: string?

	-- dim layer behind windows; its Modal button frees the mouse from shiftlock while open
	ui.dim = Kit.new("Frame", {
		Name = "Dim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 50,
		Parent = root,
	})
	local modal = Kit.new("TextButton", {
		Name = "Modal",
		Size = UDim2.fromScale(1, 1),
		Modal = true,
		ZIndex = 50,
		Parent = ui.dim,
	})

	ui.hud = Hud.build(root, {
		settings = settings,
		open = function(name: string)
			ui.toggle(name)
		end,
	})
	ui.players = PlayerList.build(root)
	ui.region = RegionTitle.build(root)
	ui.air = AirQuality.build(ui.hud.layer)
	ui.tracker = QuestTracker.build(ui.hud.layer, function()
		ui.toggle("Journal")
	end)

	-- windows sit above the dim layer
	local windowLayer = Kit.new("Frame", {
		Name = "Windows",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 60,
		Parent = root,
	})
	ui.tooltip = Tooltip.new(root)
	local toasts = Kit.new("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(800, 300),
		BackgroundTransparency = 1,
		ZIndex = 300,
		Parent = root,
	}, { Kit.list("Y", 8, Enum.HorizontalAlignment.Center) })

	function ui.toast(text: string, color: Color3?)
		local t = Kit.new("Frame", {
			Size = UDim2.fromOffset(0, 46),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Night,
			BackgroundTransparency = 0.05,
			ZIndex = 300,
			Parent = toasts,
		}, { Kit.pad(0, 22, 0, 22), Kit.vgrad(Color3.new(1, 1, 1), Color3.new(0.75, 0.75, 0.75)) })
		Kit.ornate(t, { line = C.SlateLine, corner = color or C.Gold, inset = 3, cornerSize = 8 })
		local label = Kit.chunky(text, 22, color or C.Text, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 46),
			ZIndex = 301,
			Parent = t,
		})
		Kit.pop(t, 0.25)
		task.delay(TOAST_TIME, function()
			Kit.tween(t, Theme.Tween.Med, { BackgroundTransparency = 1 })
			Kit.tween(label, Theme.Tween.Med, { TextTransparency = 1 })
			for _, s in t:GetDescendants() do
				if s:IsA("UIStroke") then
					Kit.tween(s, Theme.Tween.Med, { Transparency = 1 })
				elseif s:IsA("Frame") then
					Kit.tween(s, Theme.Tween.Med, { BackgroundTransparency = 1 })
				end
			end
			task.delay(Theme.Tween.Med.Time, function()
				t:Destroy()
			end)
		end)
	end

	-- window buttons -> server requests (the server validates and answers with Notify)
	function ui.action(name: string, ...: any)
		local arg = ...
		if name == "Roll" then
			Profile.fire("RollRelic")
		elseif name == "InvestPerk" then
			Profile.fire("InvestPerk", arg)
		elseif name == "ResetPill" then
			Profile.fire("UseResetPill")
		end
	end

	ui.windows = {
		Inventory = Inventory.build(windowLayer, {
			tooltip = ui.tooltip,
			use = function(id: string)
				Profile.fire("UseItem", id)
			end,
		}),
		Skills = Skills.build(windowLayer, { tooltip = ui.tooltip, action = ui.action }),
		Journal = Journal.build(windowLayer, {
			track = function(id: string)
				Profile.fire("TrackQuest", id)
			end,
			abandon = function(id: string)
				Profile.fire("AbandonQuest", id)
			end,
			equip = function(id: string)
				Profile.fire("EquipTitle", id)
			end,
		}),
		Station = Station.build(windowLayer, {
			act = function(npcId: string, action: string, id: string, qty: number)
				Profile.fire("StationAction", npcId, action, id, qty)
			end,
		}),
		Blacksmith = Blacksmith.build(windowLayer, {
			upgrade = function(npcId: string)
				Profile.fire("StationAction", npcId, "Upgrade", "", 1)
			end,
			roll = function()
				Profile.fire("RollRelic")
			end,
		}),
		Bounties = Bounties.build(windowLayer, {
			post = function(userId: number, amount: number)
				Profile.fire("PostBounty", userId, amount)
			end,
		}),
		FactionSelect = FactionSelect.build(windowLayer, {
			join = function(faction: string)
				Profile.fire("SelectFaction", faction)
			end,
		}),
		Map = WorldMap.build(windowLayer),
		Admin = Admin.build(windowLayer, {
			act = function(request: any) Profile.fire("AdminRequest", request) end,
			close = function() ui.close() end,
			open = function() ui.open("Admin") end,
			toast = function(text: string, color: Color3) ui.toast(text, color) end,
			cinematic = function() ui.apply("Cinematic", "On") end,
		}),
		Settings = Settings.build(windowLayer, {
			settings = settings,
			apply = function(key: string, value: any)
				ui.apply(key, value)
			end,
		}),
	} :: { [string]: any }

	-- ── settings ──
	local blur = Lighting:FindFirstChild("UIMenuBlur")
	local recording = false
	local savedBillboards: { [BillboardGui]: boolean } = {}
	local savedCoreGui: { [Enum.CoreGuiType]: boolean } = {}
	local billboardConnection: RBXScriptConnection? = nil
	local savedPrompts = true
	local savedTopbar = true
	local function setRecording(enabled: boolean)
		root.Visible = not enabled
		if recording == enabled or not State.live then return end
		recording = enabled
		local prompts = game:GetService("ProximityPromptService")
		if enabled then
			ui.close()
			ui.tooltip.hide()
			if blur then blur.Size = 0 end
			savedPrompts = prompts.Enabled
			prompts.Enabled = false
			for _, kind in Enum.CoreGuiType:GetEnumItems() do
				if kind ~= Enum.CoreGuiType.All then
					pcall(function()
						savedCoreGui[kind] = StarterGui:GetCoreGuiEnabled(kind)
						StarterGui:SetCoreGuiEnabled(kind, false)
					end)
				end
			end
			pcall(function() savedTopbar = StarterGui:GetCore("TopbarEnabled") end)
			pcall(function() StarterGui:SetCore("TopbarEnabled", false) end)
			local function hideBillboard(instance: Instance)
				if instance:IsA("BillboardGui") and savedBillboards[instance] == nil then
					savedBillboards[instance] = instance.Enabled
					instance.Enabled = false
				end
			end
			billboardConnection = workspace.DescendantAdded:Connect(hideBillboard)
			for _, instance in workspace:GetDescendants() do hideBillboard(instance) end
		else
			if billboardConnection then billboardConnection:Disconnect(); billboardConnection = nil end
			for billboard, wasEnabled in savedBillboards do
				if billboard.Parent then billboard.Enabled = wasEnabled end
			end
			table.clear(savedBillboards)
			for kind, wasEnabled in savedCoreGui do
				pcall(function() StarterGui:SetCoreGuiEnabled(kind, wasEnabled) end)
			end
			table.clear(savedCoreGui)
			prompts.Enabled = savedPrompts
			pcall(function() StarterGui:SetCore("TopbarEnabled", savedTopbar) end)
		end
	end
	function ui.apply(key: string, value: any)
		settings[key] = value
		if key == "Cinematic" or key == "PlayerList" or key == "SideMenu" then
			local cinematic = settings.Cinematic == "On"
			ui.hud.layer.Visible = not cinematic
			ui.players.frame.Visible = not cinematic and settings.PlayerList == "On"
			ui.hud.menu.Visible = settings.SideMenu == "On"
			if key == "Cinematic" then setRecording(cinematic) end
		elseif key == "StatValues" then
			ui.hud.refreshStatMode()
		elseif key == "UIScale" then
			rescale()
		elseif key == "MasterVolume" or key == "MusicVolume" or key == "SFXVolume" or key == "AmbienceVolume" then
			local audio = require(game:GetService("ReplicatedStorage").Client.Audio)
			audio.setVolume((key:gsub("Volume$", "")), value)
		elseif key == "ReduceMotion" then
			Kit.reduceMotion = value == "On"
		elseif key == "SolidPanels" then
			for _, w in ui.windows do
				local f = w.window.frame
				local base = f:GetAttribute("BaseTransparency")
				if base == nil then
					base = f.BackgroundTransparency
					f:SetAttribute("BaseTransparency", base)
				end
				f.BackgroundTransparency = if value == "On" then 0 else base
			end
		elseif key == "Bloom" and State.live then
			for _, e in Lighting:GetChildren() do
				if e:IsA("BloomEffect") then
					e.Enabled = value == "On"
				end
			end
		elseif key == "Weather" and State.live then
			local weather = workspace.CurrentCamera and workspace.CurrentCamera:FindFirstChild("LocalWeather")
			if weather then
				for _, e in weather:GetDescendants() do
					if e:IsA("ParticleEmitter") then
						e.Enabled = value == "On"
					end
				end
			end
		end
	end

	-- ── windows ──
	local function setBlur(on: boolean)
		if settings.MenuBlur ~= "On" and on then
			return
		end
		if not blur and State.live then
			blur = Kit.new("BlurEffect", { Name = "UIMenuBlur", Size = 0, Parent = Lighting })
		end
		if blur then
			Kit.tween(blur, Theme.Tween.Med, { Size = if on then BLUR_SIZE else 0 })
		end
	end

	function ui.close()
		local name = ui.current
		if not name then
			return
		end
		ui.current = nil
		local w = ui.windows[name].window
		ui.tooltip.hide()
		Kit.tween(w.scale, Theme.Tween.Fast, { Scale = 0.94 })
		task.delay(Theme.Tween.Fast.Time, function()
			if ui.current ~= name then
				w.frame.Visible = false
			end
		end)
		Kit.tween(ui.dim, Theme.Tween.Fast, { BackgroundTransparency = 1 })
		task.delay(Theme.Tween.Fast.Time, function()
			if ui.current == nil then
				ui.dim.Visible = false
			end
		end)
		setBlur(false)
	end

	function ui.open(name: string)
		if name == "Admin" and settings.Cinematic == "On" then ui.apply("Cinematic", "Off") end
		if ui.current == name then
			return
		end
		if ui.current then
			ui.windows[ui.current].window.frame.Visible = false
			ui.current = nil
		end
		local w = ui.windows[name]
		if not w then
			return
		end
		ui.current = name
		ui.dim.Visible = true
		Kit.tween(ui.dim, Theme.Tween.Med, { BackgroundTransparency = DIM_TRANSPARENCY })
		w.window.frame.Visible = true
		w.window.scale.Scale = if Kit.reduceMotion then 1 else 0.88
		Kit.tween(w.window.scale, Theme.Tween.Pop, { Scale = 1 })
		setBlur(true)
	end

	function ui.toggle(name: string)
		if ui.current == name then
			ui.close()
		else
			ui.open(name)
		end
	end

	for _, w in ui.windows do
		w.window.close.Activated:Connect(ui.close)
	end
	modal.Activated:Connect(ui.close)

	-- dialogue, roll reveal and notices sit above the windows
	ui.dialogue = Dialogue.build(root, {
		choose = function(npcId: string, optionId: string)
			Profile.fire("DialogueChoice", npcId, optionId)
		end,
	})
	ui.roll = RollReveal.build(root, {
		choose = function(keepNew: boolean)
			Profile.fire("RollChoice", keepNew)
		end,
	})
	ui.notices = Notices.build(root)

	for key, value in settings do
		ui.apply(key, value)
	end
	return ui
end

-- ── live play ───────────────────────────────────────────────────────────────

local function bindHotbar(ui: any)
	local player = Players.LocalPlayer :: Player
	local order: { Tool } = {}
	local conns: { RBXScriptConnection } = {}

	local function character(): Model?
		return player.Character
	end

	local function refresh()
		local char = character()
		local backpack = player:FindFirstChildOfClass("Backpack")
		-- drop tools that left both the backpack and the character
		for i = #order, 1, -1 do
			local t = order[i]
			if t.Parent ~= backpack and t.Parent ~= char then
				table.remove(order, i)
			end
		end
		local function add(container: Instance?)
			if not container then
				return
			end
			for _, t in container:GetChildren() do
				if t:IsA("Tool") and not table.find(order, t) and #order < Theme.HOTBAR_SLOTS then
					table.insert(order, t)
				end
			end
		end
		add(backpack)
		add(char)
		local items, equipped = {}, nil
		for i, t in order do
			local rarity = t:GetAttribute("Rarity")
			items[i] = { name = t.Name, rarity = if typeof(rarity) == "string" then rarity else "Common" }
			if t.Parent == char then
				equipped = i
			end
		end
		ui.hud.setHotbar(items, equipped)
	end

	local function use(i: number)
		local t = order[i]
		local char = character()
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if not t or not humanoid then
			return
		end
		if t.Parent == char then
			humanoid:UnequipTools()
		else
			humanoid:EquipTool(t)
		end
	end

	local function hook()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		local backpack = player:WaitForChild("Backpack", 10)
		local char = character()
		for _, container in { backpack, char } do
			if container then
				table.insert(conns, container.ChildAdded:Connect(refresh))
				table.insert(conns, container.ChildRemoved:Connect(refresh))
			end
		end
		refresh()
	end
	player.CharacterAdded:Connect(function()
		task.defer(hook)
	end)
	if player.Character then
		task.spawn(hook)
	end
	for i, button in ui.hud.slotButtons() do
		button.Activated:Connect(function()
			use(i)
		end)
	end
	return use
end

local function colorNamed(name: any): Color3?
	return if typeof(name) == "string" then (C :: any)[name] else nil
end

-- server notifications (Sync.notify kinds) -> toasts, banners and the feed
local function onNotify(ui: any, kind: string, data: any)
	if typeof(data) ~= "table" then
		data = {}
	end
	if kind == "Toast" then
		ui.toast(tostring(data.text or ""), colorNamed(data.color))
	elseif kind == "Reward" then
		ui.notices.feed(data.lines or {}, C.GoldHi, data.title)
	elseif kind == "Salvage" then
		ui.notices.feed(data.lines or {}, C.Lime, SALVAGE_HEADING[data.method] or "Salvaged")
	elseif kind == "LevelUp" and data.overflow then
		ui.notices.banner("Overflow", "Max level bonus", C.GoldHi, data.extras)
	elseif kind == "LevelUp" then
		ui.notices.banner("Level " .. tostring(data.level), string.format("+%d skill point  ·  spend it in Skills [K]", data.points or 1), C.GoldHi, data.extras)
	elseif kind == "RankUp" then
		local info = Factions.INFO[data.faction or ""]
		ui.notices.banner(tostring(data.rank), "New " .. tostring(data.faction) .. " rank", if info then info.color else C.GoldHi, data.extras)
	elseif kind == "QuestAccepted" then
		ui.toast("New quest: " .. tostring(data.title), C.Yellow)
	elseif kind == "QuestStep" then
		ui.toast(tostring(data.title) .. ": " .. tostring(data.text), C.Text)
	elseif kind == "QuestComplete" then
		ui.notices.banner("Quest Complete", tostring(data.title), C.Lime)
	elseif kind == "Note" then
		ui.notices.banner("New Field Note", tostring(data.title) .. "  ·  read it in your Journal [J]", C.Anima)
	elseif kind == "Upgrade" then
		ui.notices.banner(string.format("%s  Tier %s", tostring(data.relic), tostring(data.tier)), "Unlocked " .. tostring(data.unlocks) .. (if data.move then ": " .. tostring(data.move) else ""), C.Rust)
	elseif kind == "Joined" then
		local info = Factions.INFO[data.faction or ""]
		if ui.current == "FactionSelect" then
			ui.close()
		end
		ui.notices.banner("Welcome to the " .. tostring(data.faction), tostring(data.motto), if info then info.color else C.GoldHi)
	elseif kind == "Title" then
		ui.notices.banner("New Title", "« " .. tostring(data.name) .. " »  ·  wear it from your Journal [J]", C.GoldHi)
	elseif kind == "Perk" then
		ui.toast(string.format("%s: learned %s", tostring(data.path), tostring(data.name)), C.Magenta)
	end
end

local function bindProgression(ui: any)
	local folder = ReplicatedStorage:WaitForChild("ProgressionRemotes", 60)
	if not folder then
		return
	end
	local function on(name: string, fn: (...any) -> ())
		local remote = folder:WaitForChild(name) :: RemoteEvent
		remote.OnClientEvent:Connect(fn)
	end
	on("Notify", function(kind, data)
		onNotify(ui, kind, data)
	end)
	on("AdminResult", function(payload)
		ui.windows.Admin.receive(payload)
		if payload.close and ui.current == "Admin" then ui.close() end
		if payload.open then ui.open("Admin") end
		if payload.success == false and ui.current ~= "Admin" then ui.toast(payload.message, C.Magenta) end
	end)
	on("Dialogue", function(payload)
		if payload then
			if ui.current then
				ui.close()
			end
			ui.dialogue.open(payload)
		else
			ui.dialogue.close()
		end
	end)
	on("OpenWindow", function(name, data)
		if typeof(data) ~= "table" then
			data = {}
		end
		if name == "Station" or name == "Blacksmith" or name == "Bounties" then
			ui.windows[name].show(data)
		elseif name == "FactionSelect" then
			ui.windows.FactionSelect.setSuggested(data.suggested)
		else
			return
		end
		if ui.current ~= name then
			ui.open(name)
		end
	end)
	on("RollResult", function(result)
		if typeof(result) == "table" then
			if ui.current then
				ui.close()
			end
			local snap = Profile.data
			ui.roll.reveal(result, if snap and snap.relic then snap.relic.rarity else nil)
		end
	end)
	on("WorldEvent", function(kind, data)
		if typeof(data) ~= "table" then
			return
		end
		if kind == "TurfWarning" then
			ui.notices.banner("Turf War", string.format("%s opens in %d seconds  ·  hold the ring for your side", tostring(data.place), data.seconds or 60), C.Yellow)
		elseif kind == "TurfOpen" then
			ui.toast("The Turf War ring is open on " .. tostring(data.place) .. "!", C.Yellow)
		elseif kind == "TurfOver" then
			local info = Factions.INFO[data.winner or ""]
			if info then
				ui.notices.banner(info.name .. " hold " .. tostring(data.place), "Turf War won  ·  their salvage pays more for a while", info.color)
			else
				ui.toast("The Turf War ended in a draw.", C.TextDim)
			end
		elseif kind == "Wanted" then
			local info = Factions.INFO[data.faction or ""]
			ui.toast(string.format("%s is WANTED  ·  $%d", tostring(data.name), data.value or 0), if info then info.color else C.Rust)
		elseif kind == "BountyClaimed" then
			ui.toast(string.format("%s claimed $%d on %s", tostring(data.winner), data.value or 0, tostring(data.loser)), C.GoldHi)
		elseif kind == "DumpIncoming" then
			ui.notices.banner("Sky Dump Incoming", tostring(data.name) .. "  ·  get there before the other side", C.Rust)
		elseif kind == "DumpLanded" then
			ui.toast(string.format("The dump hit %s: %d piles to claim", tostring(data.name), data.piles or 0), C.Yellow)
		elseif kind == "DumpClaimed" then
			local info = Factions.INFO[data.winner or ""]
			if info then
				ui.notices.banner(info.name .. " claimed " .. tostring(data.name), "Their salvage pays more until the next dump", info.color)
			else
				ui.toast("Nobody claimed " .. tostring(data.name) .. ". The leftovers rot into the air.", C.Rust)
			end
		end
	end)
	-- a roll left undecided (after a rejoin) asks again
	Profile.observe(function(snap)
		if snap and snap.pending and not ui.roll.frame.Visible then
			ui.roll.choice(snap.pending.id, snap.pending.rarity, snap.relic and snap.relic.id, snap.relic and snap.relic.rarity)
		end
	end)
end

local function watchRegion(ui: any)
	local volumes = ReplicatedStorage:WaitForChild("MapRegionVolumes", 30)
	local shared = ReplicatedStorage:FindFirstChild("MapShared")
	local module = shared and shared:FindFirstChild("RegionAtmosphere")
	if not volumes or not module or not module:IsA("ModuleScript") then
		return
	end
	local RegionAtmosphere = require(module) :: any
	local player = Players.LocalPlayer :: Player
	local last: string? = nil
	task.spawn(function()
		while true do
			local char = player.Character
			local rootPart = char and char:FindFirstChild("HumanoidRootPart")
			if rootPart and rootPart:IsA("BasePart") then
				local key = RegionAtmosphere.regionAt(volumes, rootPart.Position)
				if key and key ~= last then
					last = key
					ui.hud.setRegion(key)
					if ui.settings.RegionTitles == "On" then
						ui.region.show(key)
					end
				end
			end
			task.wait(REGION_CHECK)
		end
	end)
end

function UIController.start()
	local player = Players.LocalPlayer
	local gui = Kit.new("ScreenGui", {
		Name = "TRASH_UI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})
	local settings = Settings.defaults()
	local root, rescale = Kit.scaledRoot(gui, function()
		return settings.UIScale or 1
	end)
	local ui = UIController.mount(root, settings, rescale)
	gui.Parent = player:WaitForChild("PlayerGui")

	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- the HUD replaces the core health bar, player list and backpack
	for _, t in { Enum.CoreGuiType.Health, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack } do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(t, false)
		end)
	end

	local useSlot = bindHotbar(ui)
	watchRegion(ui)
	Profile.start()
	task.spawn(bindProgression, ui)
	-- nobody has a body until they press PLAY on the intro (server: Arrival); the HUD waits
	if not player.Character then
		gui.Enabled = false
		task.spawn(Intro.run, function()
			gui.Enabled = true
		end)
	end
	-- a local-only flag so Relic keys (Z X C R B) don't fire while a menu has the keyboard
	RunService.Heartbeat:Connect(function()
		local open = settings.Cinematic ~= "On" and (ui.current ~= nil or ui.dialogue.frame.Visible or ui.roll.frame.Visible)
		if player:GetAttribute("MenuOpen") ~= open then
			player:SetAttribute("MenuOpen", open)
		end
	end)

	local menuKeys: { [Enum.KeyCode]: string } = {}
	for name, key in Theme.Keys :: { [string]: Enum.KeyCode } do
		menuKeys[key] = name
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Theme.CinematicKey then
			ui.apply("Cinematic", if settings.Cinematic == "On" then "Off" else "On")
			return
		end
		local menu = if settings.Cinematic ~= "On" then menuKeys[input.KeyCode] else nil
		if menu then
			ui.toggle(menu)
			return
		end
		local slot = table.find(Theme.HotbarKeys, input.KeyCode)
		if slot and not ui.current then
			useSlot(slot)
		end
	end)
end

-- ── edit-mode preview ───────────────────────────────────────────────────────

function UIController.preview(parent: Instance, window: string?, overrides: { [string]: any }?): any
	local old = parent:FindFirstChild("UIPreview")
	if old then
		old:Destroy()
	end
	local gui = Kit.new("ScreenGui", {
		Name = "UIPreview",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	Profile.start()
	local settings = Settings.defaults()
	if overrides then
		for k, v in overrides do
			settings[k] = v
		end
	end
	local root, rescale = Kit.scaledRoot(gui, function()
		return settings.UIScale or 1
	end)
	local ui = UIController.mount(root, settings, rescale)
	if window and ui.windows[window] then
		ui.current = window
		ui.dim.Visible = true
		ui.dim.BackgroundTransparency = DIM_TRANSPARENCY
		ui.windows[window].window.frame.Visible = true
	end
	gui.Parent = parent
	return ui
end

return UIController
