--!strict
--[[
	MobHud - the boss bar for Pollution Beasts, styled from UI/Theme (Deepwoken slate and gold, a
	serif name with an italic title). It shows the beast that targets this player, or else the
	nearest fighting beast within HUD_RANGE: health with a lagging damage chip, the stagger meter
	in the posture colour, and an ENRAGED tag.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MobsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Mobs"))
local Theme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Theme"))

local WIDTH, TOP = 640, 72 -- below the region and server labels at the top of the HUD
local BAR_HEIGHT, STAGGER_HEIGHT = 16, 5
local CHIP_DELAY, CHIP_SPEED = 0.45, 0.6 -- the damage chip waits, then drains this fraction per second
local CALM = { Idle = true, Roam = true, Return = true, Dead = true }
local PICK_INTERVAL = 0.25

local MobHud = {}

local function new(class: string, props: { [string]: any }, children: { Instance }?): Instance
	local i = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(i :: any)[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = i
	end
	if props.Parent then
		i.Parent = props.Parent
	end
	return i
end

local function stroke(color: Color3, thickness: number): Instance
	return new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function ornament(x: number): Instance
	return new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(x, 0, 0.5, 0),
		Size = UDim2.fromOffset(10, 10),
		Rotation = 45,
		BackgroundColor3 = Theme.Color.Gold,
		BorderSizePixel = 0,
		ZIndex = 4,
	}, { stroke(Theme.Color.GoldDark, 1) })
end

function MobHud.start(tag: string)
	local player = Players.LocalPlayer
	local gui = new("ScreenGui", {
		Name = "MobHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	}) :: ScreenGui
	local scale = new("UIScale", { Parent = gui }) :: UIScale
	local group = new("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP),
		Size = UDim2.fromOffset(WIDTH, 72),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		Parent = gui,
	}) :: CanvasGroup
	local header = new("Frame", {
		Position = UDim2.fromOffset(4, 0),
		Size = UDim2.new(1, -8, 0, 30),
		BackgroundTransparency = 1,
		Parent = group,
	}, {
		new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	local nameLabel = new("TextLabel", {
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundTransparency = 1,
		FontFace = Theme.Font.Title,
		TextSize = 26,
		TextColor3 = Theme.Color.Text,
		TextStrokeTransparency = 0.4,
		Parent = header,
	}) :: TextLabel
	local titleLabel = new("TextLabel", {
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24),
		BackgroundTransparency = 1,
		FontFace = Theme.Font.TitleItalic,
		TextSize = 16,
		TextColor3 = Theme.Color.TextDim,
		TextStrokeTransparency = 0.6,
		Parent = header,
	}) :: TextLabel
	local enragedLabel = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 2),
		Size = UDim2.fromOffset(160, 28),
		BackgroundTransparency = 1,
		FontFace = Theme.Font.Tag,
		Text = "ENRAGED",
		TextSize = 22,
		TextColor3 = Theme.Color.Rust,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.3,
		Visible = false,
		Parent = group,
	}) :: TextLabel
	local bar = new("Frame", {
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
		BackgroundColor3 = Theme.Color.Coal,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		Parent = group,
	}, { stroke(Theme.Color.Gold, 1.5), ornament(0), ornament(1) }) :: Frame
	local chip = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.PaperHi,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bar,
	}) :: Frame
	local fill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Color.Health,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = bar,
	}, {
		new("UIGradient", {
			Color = ColorSequence.new(Theme.Color.Health, Theme.Color.RustDark),
			Rotation = 90,
		}),
	}) :: Frame
	local hpLabel = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		FontFace = Theme.Font.BodyBold,
		TextSize = 14,
		TextColor3 = Theme.Color.Text,
		TextStrokeTransparency = 0.3,
		ZIndex = 5,
		Parent = bar,
	}) :: TextLabel
	local staggerBack = new("Frame", {
		Position = UDim2.fromOffset(24, 34 + BAR_HEIGHT + 4),
		Size = UDim2.new(1, -48, 0, STAGGER_HEIGHT),
		BackgroundColor3 = Theme.Color.Night,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Parent = group,
	}, { stroke(Theme.Color.GoldDark, 1) }) :: Frame
	local staggerFill = new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Theme.Color.Posture,
		BorderSizePixel = 0,
		Parent = staggerBack,
	}) :: Frame

	local shown: Model? = nil
	local chipValue, chipHeldUntil, lastFraction = 1, 0, 1
	local pickAt = 0
	local fade = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local function choose(): Model?
		local character = player.Character
		local me = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not me or not me:IsA("BasePart") then
			return nil
		end
		local best: Model? = nil
		local bestDistance = math.huge
		for _, m in CollectionService:GetTagged(tag) do
			if not m:IsA("Model") or not m.PrimaryPart then
				continue
			end
			local state = m:GetAttribute("MobState")
			local cfg = (MobsConfig :: any)[m:GetAttribute("Mob") or "JunkRam"]
			if not cfg or state == "Dead" then
				continue
			end
			if m:GetAttribute("TargetName") == player.Name then
				return m
			end
			local d = (m.PrimaryPart.Position - me.Position).Magnitude
			if not CALM[state] and d <= cfg.HUD_RANGE and d < bestDistance then
				best, bestDistance = m, d
			end
		end
		return best
	end

	local function show(m: Model?)
		if m == shown then
			return
		end
		shown = m
		if m then
			local cfg = (MobsConfig :: any)[m:GetAttribute("Mob") or "JunkRam"]
			nameLabel.Text = string.upper(cfg.DISPLAY_NAME)
			titleLabel.Text = cfg.TITLE
			local humanoid = m:FindFirstChildOfClass("Humanoid")
			lastFraction = if humanoid then humanoid.Health / humanoid.MaxHealth else 1
			chipValue = lastFraction
			group.Visible = true
			TweenService:Create(group, fade, { GroupTransparency = 0 }):Play()
		else
			local tween = TweenService:Create(group, fade, { GroupTransparency = 1 })
			tween.Completed:Once(function()
				if not shown then
					group.Visible = false
				end
			end)
			tween:Play()
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		if camera then
			scale.Scale = math.clamp(camera.ViewportSize.Y / Theme.DESIGN_HEIGHT, Theme.SCALE_MIN, Theme.SCALE_MAX)
		end
		local t = os.clock()
		if t >= pickAt then
			pickAt = t + PICK_INTERVAL
			show(choose())
		end
		local m = shown
		if not m then
			return
		end
		local humanoid = m:FindFirstChildOfClass("Humanoid")
		if not humanoid or not m.Parent then
			show(nil)
			return
		end
		local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
		if fraction < lastFraction then
			chipHeldUntil = t + CHIP_DELAY
		end
		lastFraction = fraction
		if fraction > chipValue then
			chipValue = fraction
		elseif t >= chipHeldUntil then
			chipValue = math.max(fraction, chipValue - CHIP_SPEED * dt)
		end
		fill.Size = UDim2.fromScale(fraction, 1)
		chip.Size = UDim2.fromScale(chipValue, 1)
		hpLabel.Text = string.format("%d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth)
		local stagger = m:GetAttribute("Stagger")
		staggerFill.Size = UDim2.fromScale(if typeof(stagger) == "number" then math.clamp(stagger, 0, 1) else 0, 1)
		staggerFill.BackgroundColor3 = if m:GetAttribute("MobState") == "Staggered" then Theme.Color.Rust else Theme.Color.Posture
		enragedLabel.Visible = m:GetAttribute("Enraged") == true
	end)
end

return MobHud
