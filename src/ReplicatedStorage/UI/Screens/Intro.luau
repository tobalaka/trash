--!strict
--[[
	Intro - the title screen everyone sees on joining (vault: 02-Systems/UI/Intro). Nobody has a
	body until they press PLAY (server: Progression/Arrival), so the HUD stays hidden and the
	camera tours the Heap on its own.

	  1. New characters (who haven't met Old Mags yet) get a short story over four slow camera
	     shots: the Gate Market, the Wastezone, Menders Headquarters, the Scrappers' Den.
	     Skippable. Returning players go straight to the title.
	  2. The title: TRASH, the tagline and PLAY, over the Gate Market.
	  3. PLAY with no side yet opens the side picker (the FactionSelect cards, without a close
	     button). Joining is permanent; once the server confirms (the snapshot has a faction),
	     the intro asks to spawn.
	  4. When the body arrives: fade through black, hand the camera back, show the HUD.
	Server errors (Notify "Toast") show under the button, because the HUD toasts are hidden here.
	The map streams in around each shot (RequestStreamAroundAsync), since there is no body yet.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Profile = require(UI:WaitForChild("Profile"))
local FactionSelect = require(script.Parent:WaitForChild("FactionSelect"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Npcs = require(Shared:WaitForChild("Data"):WaitForChild("Npcs"))
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))

local C, F = Theme.Color, Theme.Font

local ARRIVAL_QUEST = "P0_Arrival" -- met Old Mags: a returning character, no story
local BIND = "TrashIntroCamera"
local PROFILE_WAIT = 6 -- seconds to wait for the save before deciding story or title
local STREAM_TIMEOUT = 4 -- seconds RequestStreamAroundAsync may take per shot
local SPAWN_TIMEOUT = 15 -- seconds to wait for the body after PLAY
local SHOT_TIME = 5 -- seconds each story line stays up
local FADE = 0.7
local CAPTION_FADE = 0.5
local LOOK_UP = 6 -- studs above the ground the camera looks at
local FOV = 60
local CAMERA_PAD = 2 -- studs the camera keeps from a wall between it and the subject
local BAR_HEIGHT = 110 -- letterbox bars during the story
local GROUND_TOP = 400 -- studs above the shot the ground probe starts

local TAGLINE = "Every scrap counts. So does the air."
local CREDIT = "Made for the Congressional App Challenge"

-- Camera tour stops: where to look (x, z), how far out and high to circle, how fast (rad/s).
local SHOTS: { [string]: { x: number, z: number, radius: number, height: number, spin: number } } = {
	Market = { x = Npcs.PLAZA_CENTER.X, z = Npcs.PLAZA_CENTER.Z, radius = 44, height = 20, spin = 0.06 },
	Wasteland = { x = -1365, z = 1348, radius = 80, height = 34, spin = 0.05 }, -- the Junk Ram's ground
	MendersBase = { x = Npcs.SPAWNS.MendersBase.x, z = Npcs.SPAWNS.MendersBase.z, radius = 60, height = 26, spin = 0.05 },
	ScrappersBase = { x = Npcs.SPAWNS.ScrappersBase.x, z = Npcs.SPAWNS.ScrappersBase.z, radius = 60, height = 26, spin = -0.05 },
}

local STORY = {
	{ shot = "Market", text = "Far away, rich cities pay to make their trash disappear." },
	{ shot = "Wasteland", text = "The barges drop it here, on the Heap, by the ton." },
	{ shot = "MendersBase", text = "The Menders sort it, mend it and fight for cleaner air." },
	{ shot = "ScrappersBase", text = "The Scrappers strip it for parts and take what's left." },
}

type Shot = { focus: Vector3, radius: number, height: number, spin: number, angle: number }

local Intro = {}

local function groundY(x: number, z: number, fallback: number): number
	local from = Vector3.new(x, fallback + GROUND_TOP, z)
	local down = Vector3.new(0, -GROUND_TOP * 2, 0)
	-- the map's ground chunks first, so the dome and roofs above the plaza don't count
	local ground = workspace:FindFirstChild("Ground")
	if ground then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { ground }
		local hit = workspace:Raycast(from, down, params)
		if hit then
			return hit.Position.Y
		end
	end
	return fallback
end

-- Runs the intro; `onDone` is called once the player has a body and the camera is theirs.
function Intro.run(onDone: () -> ())
	local player = Players.LocalPlayer :: Player
	local camera = workspace.CurrentCamera
	local startFov = if camera then camera.FieldOfView else 70

	local gui = Kit.new("ScreenGui", {
		Name = "TRASH_Intro",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 50,
	})
	local root, rescale = Kit.scaledRoot(gui, function()
		return 1
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	local conns: { RBXScriptConnection } = {}
	if camera then
		table.insert(conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
	end
	-- however the body arrives (PLAY, or the server's safety net), the intro ends; set below
	local finishWith: ((Model) -> ())? = nil
	table.insert(conns, player.CharacterAdded:Connect(function(character)
		local f = finishWith
		if f then
			task.spawn(f, character)
		end
	end))

	-- ── layers ──
	local black = Kit.new("Frame", {
		Name = "Black",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0,
		ZIndex = 200,
		Parent = root,
	})
	local function bar(top: boolean): any
		return Kit.new("Frame", {
			Name = if top then "BarTop" else "BarBottom",
			AnchorPoint = Vector2.new(0, if top then 0 else 1),
			Position = UDim2.fromScale(0, if top then 0 else 1),
			Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
			BackgroundColor3 = C.Ink,
			ZIndex = 10,
			Parent = root,
		})
	end
	local barTop, barBottom = bar(true), bar(false)
	local caption = Kit.hudText("", F.TitleItalic, 36, C.Text, {
		Name = "Caption",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BAR_HEIGHT + 40)),
		Size = UDim2.fromOffset(1400, 50),
		TextTransparency = 1,
		ZIndex = 20,
		Parent = root,
	})
	local skip = Kit.outlineButton("Skip", Vector2.new(130, 44), {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -32, 1, -32),
		ZIndex = 30,
		Visible = false,
		Parent = root,
	})

	-- title
	local title = Kit.new("Frame", {
		Name = "Title",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 40,
		Parent = root,
	})
	local logo = Kit.chunky("TRASH", 190, C.PaperHi, {
		Name = "Logo",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromOffset(900, 200),
		ZIndex = 41,
		Parent = title,
	})
	Kit.hudText(TAGLINE, F.TitleItalic, 30, C.Text, {
		Name = "Tagline",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.34, 108),
		Size = UDim2.fromOffset(900, 36),
		ZIndex = 41,
		Parent = title,
	})
	local playHolder, playButton = Kit.gloss({
		text = "PLAY",
		color = C.Rust,
		size = UDim2.fromOffset(340, 84),
		position = UDim2.new(0.5, 0, 0.62, 0),
		anchor = Vector2.new(0.5, 0.5),
		textSize = 44,
		name = "Play",
		parent = title,
	})
	playHolder.ZIndex = 41
	Kit.hudText(CREDIT, F.Body, 18, C.TextDim, {
		Name = "Credit",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 32, 1, -28),
		Size = UDim2.fromOffset(600, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 41,
		Parent = title,
	})
	local status = Kit.hudText("", F.BodyBold, 22, C.TextDim, {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 60),
		Size = UDim2.fromOffset(1000, 28),
		ZIndex = 210, -- above the black fade, so "Loading..." shows on a black screen
		Parent = root,
	})

	-- side picker: the FactionSelect cards over a dim layer, no way to close them
	local pickerLayer = Kit.new("Frame", {
		Name = "Picker",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 50,
		Parent = root,
	})
	local picking = false
	local picker = FactionSelect.build(pickerLayer, {
		join = function(faction: string)
			if not picking then
				return
			end
			local info = Factions.INFO[faction]
			status.Text = "Joining the " .. (if info then info.name else faction) .. "..."
			status.TextColor3 = if info then info.color else C.TextDim
			Profile.fire("SelectFaction", faction)
		end,
	})
	picker.window.close.Parent.Visible = false
	picker.window.frame.Visible = true

	local function setStatus(text: string, color: Color3?)
		status.Text = text
		status.TextColor3 = color or C.TextDim
	end

	-- server toasts (errors) land here while the HUD is hidden
	local folder = ReplicatedStorage:WaitForChild("ProgressionRemotes", 30)
	local notify = folder and folder:FindFirstChild("Notify")
	if notify and notify:IsA("RemoteEvent") then
		table.insert(conns, notify.OnClientEvent:Connect(function(kind, data)
			if kind == "Toast" and typeof(data) == "table" then
				local named = if typeof(data.color) == "string" then (C :: any)[data.color] else nil
				setStatus(tostring(data.text or ""), named)
			end
		end))
	end

	-- ── camera ──
	local shot: Shot? = nil
	local castParams = RaycastParams.new()
	castParams.FilterType = Enum.RaycastFilterType.Exclude
	castParams.RespectCanCollide = true
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local cam = workspace.CurrentCamera
		local s = shot
		if not cam or not s then
			return
		end
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = FOV
		-- a free mouse for PLAY; once the body exists, its own camera scripts decide
		if not player.Character then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
		s.angle += s.spin * dt
		local look = s.focus + Vector3.new(0, LOOK_UP, 0)
		local eye = s.focus + Vector3.new(math.cos(s.angle) * s.radius, s.height, math.sin(s.angle) * s.radius)
		-- don't film through a wall: pull in to the first thing between the subject and the lens
		local hit = workspace:Raycast(look, eye - look, castParams)
		if hit then
			eye = hit.Position + (look - eye).Unit * CAMERA_PAD
		end
		cam.CFrame = CFrame.lookAt(eye, look)
	end)

	local prepared: { [string]: Shot } = {}
	local function prepare(name: string): Shot
		local ready = prepared[name]
		if ready then
			return ready
		end
		local s = SHOTS[name]
		local fallback = if name == "Market" then Npcs.PLAZA_CENTER.Y else 6
		pcall(function()
			player:RequestStreamAroundAsync(Vector3.new(s.x, fallback, s.z), STREAM_TIMEOUT)
		end)
		local made: Shot = {
			focus = Vector3.new(s.x, groundY(s.x, s.z, fallback), s.z),
			radius = s.radius,
			height = s.height,
			spin = s.spin,
			angle = math.random() * 2 * math.pi,
		}
		prepared[name] = made
		return made
	end
	local function prefetch(name: string?)
		if name and not prepared[name] then
			task.spawn(prepare, name)
		end
	end

	local function fade(to: number, time: number)
		Kit.tween(black, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = to })
		task.wait(time)
	end

	-- ── 1. story (new characters only) ──
	local t0 = os.clock()
	while not Profile.data and os.clock() - t0 < PROFILE_WAIT do
		task.wait(0.1)
	end
	local snap = Profile.data
	local returning = snap ~= nil and snap.quests ~= nil and snap.quests.done ~= nil and snap.quests.done[ARRIVAL_QUEST] ~= nil
	local skipped = false
	table.insert(conns, skip.Activated:Connect(function()
		skipped = true
	end))
	setStatus("Loading the Heap...")
	prepare(if returning then "Market" else STORY[1].shot)
	setStatus("")
	if not returning then
		skip.Visible = true
		for i, line in STORY do
			if skipped or player.Character then
				break
			end
			shot = prepare(line.shot)
			prefetch(if STORY[i + 1] then STORY[i + 1].shot else "Market")
			caption.Text = line.text
			fade(1, FADE)
			Kit.tween(caption, TweenInfo.new(CAPTION_FADE), { TextTransparency = 0 })
			local shown = os.clock()
			while os.clock() - shown < SHOT_TIME and not skipped and not player.Character do
				task.wait(0.05)
			end
			Kit.tween(caption, TweenInfo.new(CAPTION_FADE), { TextTransparency = 1 })
			fade(0, FADE)
		end
		skip.Visible = false
	end

	-- ── 2. title ──
	shot = prepare("Market")
	caption.Visible = false
	Kit.tween(barTop, Theme.Tween.Slow, { Position = UDim2.fromOffset(0, -BAR_HEIGHT) })
	Kit.tween(barBottom, Theme.Tween.Slow, { Position = UDim2.new(0, 0, 1, BAR_HEIGHT) })
	title.Visible = true
	Kit.pop(logo, 0.12)
	fade(1, FADE)

	-- ── 3. PLAY, the side picker, spawning ──
	local done = false
	local busy = false
	local stopObserving: () -> () = function() end

	local function finish(character: Model)
		if done then
			return
		end
		done = true
		fade(0, 0.35)
		RunService:UnbindFromRenderStep(BIND)
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = startFov
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid and humanoid:IsA("Humanoid") then
				cam.CameraSubject = humanoid
			end
		end
		title.Visible = false
		pickerLayer.Visible = false
		status.Text = ""
		onDone()
		fade(1, FADE)
		stopObserving()
		for _, c in conns do
			c:Disconnect()
		end
		gui:Destroy()
	end

	finishWith = finish
	local early = player.Character
	if early then
		task.spawn(finish, early)
	end

	local function enter()
		busy = true
		setStatus("Waking up...")
		local existing = player.Character
		if existing then
			finish(existing)
			return
		end
		Profile.fire("Play")
		local waitStart = os.clock()
		while not done and os.clock() - waitStart < SPAWN_TIMEOUT do
			task.wait(0.1)
		end
		if not done then
			setStatus("Couldn't wake up. Press PLAY to try again.", C.Red)
			busy = false
		end
	end

	local function showPicker()
		picking = true
		title.Visible = false
		pickerLayer.Visible = true
		Kit.pop(picker.window.frame, 0.06)
		setStatus("")
		status.Position = UDim2.new(0.5, 0, 1, -48)
	end

	-- the server confirmed the side: leave the picker and spawn
	stopObserving = Profile.observe(function(s)
		if picking and not done and s and s.faction then
			picking = false
			task.spawn(enter)
		end
	end)

	local function onPlay()
		if busy or done or picking then
			return
		end
		busy = true
		setStatus("")
		local waitStart = os.clock()
		while not Profile.data and os.clock() - waitStart < PROFILE_WAIT do
			setStatus("Loading your save...")
			task.wait(0.1)
		end
		local data = Profile.data
		if not data then
			setStatus("Still loading your save. Try again in a moment.", C.Red)
			busy = false
			return
		end
		if not data.faction then
			busy = false
			showPicker()
			return
		end
		enter()
	end
	table.insert(conns, playButton.Activated:Connect(function()
		task.spawn(onPlay)
	end))
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and title.Visible and (input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter) then
			task.spawn(onPlay)
		end
	end))
end

return Intro
