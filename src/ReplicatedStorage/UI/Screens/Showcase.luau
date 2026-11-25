--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = script.Parent.Parent
local Kit, Theme = require(UI.Kit), require(UI.Theme)
local Config = require(ReplicatedStorage.Shared.Config.Showcase)
local C, F = Theme.Color, Theme.Font
local Showcase = {}
local BUTTON_WIDTH, BUTTON_GAP, BUTTON_HEIGHT = 220, 14, 42

function Showcase.build(parent: Instance, ctx: any): any
	local clips = {}
	local function label(text: string, y: number, height: number): TextLabel
		return Kit.label(text, F.BodyItalic, 16, C.TextDim, {
			Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, height), TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, Parent = parent,
		})
	end
	label("Your dummy: preview player / Relic animations or use Training. The world board shows your actual combat timers.", 0, 46)
	local function button(text: string, column: number, y: number, action: string)
		local b = Kit.outlineButton(text, Vector2.new(BUTTON_WIDTH, BUTTON_HEIGHT), {
			Position = UDim2.fromOffset(column * (BUTTON_WIDTH + BUTTON_GAP), y), TextSize = 16, Parent = parent,
		})
		b.Activated:Connect(function() ctx.act({ action = action }) end)
	end
	button("Spawn / reset here", 0, 58, "ShowcaseSpawn")
	button("Training mode", 1, 58, "ShowcaseTraining")
	button("Remove dummy", 2, 58, "ShowcaseRemove")
	button("Auto-cycle all", 0, 112, "ShowcaseAuto")
	button("Next animation", 1, 112, "ShowcaseNext")
	button("Stop playback", 2, 112, "ShowcaseStop")
	local status = label("Spawn a dummy ahead of you. Clip previews do not trigger damage or player cooldowns.", 166, 48)
	local search = Kit.new("TextBox", {
		Name = "AnimationSearch", Position = UDim2.fromOffset(0, 224), Size = UDim2.new(1, -12, 0, 42),
		PlaceholderText = "Search animations, Relics or move names", Text = "", ClearTextOnFocus = false,
		BackgroundColor3 = C.Ink, TextColor3 = C.Text, PlaceholderColor3 = C.TextDim,
		FontFace = F.HeaderBold, TextSize = 17, Parent = parent,
	}, { Kit.stroke(C.SlateLine, 1), Kit.pad(0, 10, 0, 10) })
	local list = Kit.new("ScrollingFrame", {
		Name = "AnimationList", Position = UDim2.fromOffset(0, 280), Size = UDim2.new(1, 0, 1, -280),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.Gold, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = parent,
	}, { Kit.list("Y", 8), Kit.pad(2, 10, 4, 2) })
	local function render()
		for _, child in list:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
		local query = string.lower(search.Text)
		for _, clip in clips do
			if string.find(string.lower(clip.group .. " " .. clip.name), query, 1, true) then
				local text = clip.group .. " · " .. clip.name
				if not clip.available then text ..= " (missing clip)" end
				local b = Kit.outlineButton(text, Vector2.new(670, BUTTON_HEIGHT), {
					TextSize = 15, TextColor3 = if clip.available then C.Text else C.TextDim, Parent = list,
				})
				if clip.available then b.Activated:Connect(function() ctx.act({ action = "ShowcasePlay", clip = clip.id }) end) end
			end
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(render)
	if RunService:IsClient() then
		-- Relic poses use the existing runtime animator on every observing client.
		task.spawn(function()
			local folder = workspace:WaitForChild("AdminShowcases", 30)
			if not folder then return end
			local RelicAnimator = require(ReplicatedStorage.Client.Progression.RelicAnimator)
			local function watch(instance: Instance)
				if not instance:IsA("Model") or instance.Name ~= "ShowcaseDummy" then return end
				local function update()
					RelicAnimator.stop(instance)
					local relic = instance:GetAttribute("PreviewRelic")
					local key = instance:GetAttribute("PreviewKey")
					if typeof(relic) == "string" and relic ~= "" and typeof(key) == "string" then
						RelicAnimator.play(instance, relic, key, instance:GetAttribute("PreviewStart"))
					end
				end
				instance:GetAttributeChangedSignal("PreviewSerial"):Connect(update)
				task.defer(update)
			end
			folder.DescendantAdded:Connect(watch)
			for _, instance in folder:GetDescendants() do watch(instance) end
		end)
		local elapsed = 0
		RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < Config.UPDATE_GAP or not parent:IsA("GuiObject") or not parent.Visible then return end
			elapsed = 0
			local folder = workspace:FindFirstChild("AdminShowcases")
			local own = folder and folder:FindFirstChild(tostring(Players.LocalPlayer.UserId))
			local dummy = own and own:FindFirstChild("ShowcaseDummy")
			status.Text = if dummy then string.format("%s · %s\nThe world board shows cooldown seconds, state, combo, posture and last damage.",
				tostring(dummy:GetAttribute("ShowcaseMode") or "Preview"), tostring(dummy:GetAttribute("PreviewName") or "No animation"))
				else "Spawn a dummy ahead of you. Clip previews do not trigger damage or player cooldowns."
		end)
	end
	return { receive = function(info: any)
		if info and info.clips then clips = info.clips; render() end
	end }
end

return Showcase
