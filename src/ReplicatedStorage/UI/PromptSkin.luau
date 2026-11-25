--!strict
--[[
	PromptSkin - every ProximityPrompt drawn in the EXPED skin (2026-10-25). EXPED itself has no
	ProximityPrompts (its interact line just reads "[E] - Interact"), so this draws Roblox's prompts in
	the HUD's own look: a dark panel in the silver frame, the key in a framed slot, the action in
	white with the object above it dimmed. A hold prompt fills its key slot from the bottom; a
	finished prompt flashes the frame gold. On touch the panel is the button.
	Only this client switches the prompts to Style Custom; the server's prompts, ranges and hold
	times stay as they are (Progression/WorldFx still renames and retimes them on PromptShown).
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UI = script.Parent
local Exped = require(UI:WaitForChild("Exped"))
local Kit = require(UI:WaitForChild("Kit"))

local GOLD = Color3.fromRGB(255, 214, 128)
local KEY = 34 -- the key slot, px
local PAD = 10
local POP = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local PromptSkin = {}

local function keyLabel(prompt: ProximityPrompt, input: Enum.ProximityPromptInputType): string
	if input == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif input == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "^Button", ""))
	end
	local name = prompt.KeyboardKeyCode.Name
	return if #name > 3 then string.sub(name, 1, 3) else name
end

local function width(text: string, size: number, font: Font): number
	if text == "" then
		return 0
	end
	local params = Instance.new("GetTextBoundsParams")
	params.Text = text
	params.Font = font
	params.Size = size
	params.Width = 1000
	local ok, bounds = pcall(function()
		return TextService:GetTextBoundsAsync(params)
	end)
	return if ok then (bounds :: Vector2).X else #text * size * 0.6
end

local function adorneeOf(prompt: ProximityPrompt): Instance?
	local parent = prompt.Parent
	if parent and parent:IsA("Model") then
		return parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
	end
	return parent
end

local function build(prompt: ProximityPrompt, input: Enum.ProximityPromptInputType, gui: Instance): () -> ()
	local action = Exped.text(prompt.ActionText, 16, {
		Position = UDim2.fromOffset(KEY + PAD * 2, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	})
	local object = Exped.text(prompt.ObjectText, 12, {
		Position = UDim2.fromOffset(KEY + PAD * 2, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Exped.Color.TextDim,
		ZIndex = 3,
	}, false)
	local board = Kit.new("BillboardGui", {
		Name = "ExpedPrompt",
		Adornee = adorneeOf(prompt),
		AlwaysOnTop = true,
		LightInfluence = 0,
		StudsOffset = Vector3.new(0, 1.2, 0),
		ResetOnSpawn = false,
		Active = input == Enum.ProximityPromptInputType.Touch,
		ClipsDescendants = false,
		Parent = gui,
	})
	local panel = Kit.new(if input == Enum.ProximityPromptInputType.Touch then "TextButton" else "Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Exped.Color.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Parent = board,
	})
	if panel:IsA("TextButton") then
		panel.Text = ""
		panel.AutoButtonColor = false
		panel.InputBegan:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				prompt:InputHoldBegin()
			end
		end)
		panel.InputEnded:Connect(function(io)
			if io.UserInputType == Enum.UserInputType.Touch then
				prompt:InputHoldEnd()
			end
		end)
	end
	local frame = Exped.frame(panel, "Slot", 10)
	local scale = Kit.new("UIScale", { Scale = 0.75, Parent = panel })
	-- the key in its own framed slot
	local slot = Kit.new("Frame", {
		Position = UDim2.fromOffset(PAD - 2, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(KEY, KEY),
		BackgroundColor3 = Exped.Color.PanelDeep,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = panel,
	})
	local fill = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = slot,
	})
	local slotFrame = Exped.frame(slot, "Slot", 7)
	local key = Exped.text(keyLabel(prompt, input), if input == Enum.ProximityPromptInputType.Touch then 11 else 17, {
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = slot,
	})
	action.Parent = panel
	object.Parent = panel

	local function layout()
		action.Text = prompt.ActionText
		object.Text = prompt.ObjectText
		local textW = math.max(width(action.Text, 16, Exped.Font.Bold), width(object.Text, 12, Exped.Font.Regular))
		local w = math.floor(KEY + PAD * 3 + textW + 4)
		local h = if object.Text ~= "" then 52 else 46
		board.Size = UDim2.fromOffset(w, h)
		slot.Position = UDim2.new(0, PAD - 2, 0.5, 0)
		if object.Text ~= "" then
			object.Size = UDim2.new(1, -(KEY + PAD * 3), 0, 14)
			object.Position = UDim2.new(0, KEY + PAD * 2, 0.5, -16)
			action.Size = UDim2.new(1, -(KEY + PAD * 3), 0, 20)
			action.Position = UDim2.new(0, KEY + PAD * 2, 0.5, -1)
		else
			action.Size = UDim2.new(1, -(KEY + PAD * 3), 0, 20)
			action.Position = UDim2.new(0, KEY + PAD * 2, 0.5, -10)
		end
		local o = prompt.UIOffset
		board.SizeOffset = Vector2.new(o.X / math.max(w, 1), -o.Y / math.max(h, 1))
	end
	layout()
	TweenService:Create(scale, POP, { Scale = 1 }):Play()

	local holdTween: Tween? = nil
	local conns: { RBXScriptConnection } = {
		prompt:GetPropertyChangedSignal("ActionText"):Connect(layout),
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(layout),
		prompt.PromptButtonHoldBegan:Connect(function()
			if prompt.HoldDuration > 0 then
				fill.Size = UDim2.fromScale(1, 0)
				local tween = TweenService:Create(fill, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
				holdTween = tween
				tween:Play()
			end
		end),
		prompt.PromptButtonHoldEnded:Connect(function()
			if holdTween then
				holdTween:Cancel()
				holdTween = nil
			end
			TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(1, 0) }):Play()
		end),
		prompt.Triggered:Connect(function()
			-- done: the frames flash gold and the panel pops
			frame.ImageColor3 = GOLD
			slotFrame.ImageColor3 = GOLD
			TweenService:Create(frame, TweenInfo.new(0.35), { ImageColor3 = Color3.new(1, 1, 1) }):Play()
			TweenService:Create(slotFrame, TweenInfo.new(0.35), { ImageColor3 = Color3.new(1, 1, 1) }):Play()
			scale.Scale = 1.08
			TweenService:Create(scale, POP, { Scale = 1 }):Play()
			fill.Size = UDim2.fromScale(1, 0)
		end),
	}
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		board:Destroy()
	end
end

function PromptSkin.start()
	local player = Players.LocalPlayer
	local gui = Kit.new("ScreenGui", {
		Name = "ExpedPrompts",
		ResetOnSpawn = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local function claim(d: Instance)
		if d:IsA("ProximityPrompt") and d.Style == Enum.ProximityPromptStyle.Default then
			d.Style = Enum.ProximityPromptStyle.Custom
		end
	end
	for _, d in workspace:GetDescendants() do
		claim(d)
	end
	workspace.DescendantAdded:Connect(claim)

	local shown: { [ProximityPrompt]: () -> () } = {}
	-- bumped on every show and hide, so a build that finishes after its prompt hid throws itself away
	local generation: { [ProximityPrompt]: number } = setmetatable({}, { __mode = "k" }) :: any
	ProximityPromptService.PromptShown:Connect(function(prompt, input)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		local g = (generation[prompt] or 0) + 1
		generation[prompt] = g
		-- after the other PromptShown handlers (WorldFx may rename, retime or disable it)
		task.defer(function()
			if generation[prompt] ~= g or not prompt.Enabled or shown[prompt] then
				return
			end
			local clean = build(prompt, input, gui)
			if generation[prompt] ~= g or shown[prompt] then
				clean()
				return
			end
			shown[prompt] = clean
		end)
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		generation[prompt] = (generation[prompt] or 0) + 1
		local clean = shown[prompt]
		if clean then
			shown[prompt] = nil
			clean()
		end
	end)
end

return PromptSkin
