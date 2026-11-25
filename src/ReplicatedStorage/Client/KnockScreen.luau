--!strict
--[[
	KnockScreen - the local player's knocked and death screens (2026-10-25, EXPED's knocked state and
	DeathScreenUi), in the EXPED skin (UI/Exped, UI/Kit).

	  knocked   a dark red vignette, KNOCKED, and what is happening: getting up in N, carried by X,
	            being executed by X; the keys others can use on you
	  dead      the screen dims, YOU DIED or EXECUTED, by whom, respawning in N
	Driven by CombatResult (Knocked, Carry, Drop, GripStart, GripCancel, GetUp, Executed) and the
	Humanoid dying; a new character clears it. Started by Client/Feedback.
	Also keeps the local "GripReady" attribute: B grips (instead of the relic ultimate) while a knocked
	body is in reach. No hover prompt for grip / carry (user 2026-10-25).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")
local C = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Exped = require(UI:WaitForChild("Exped"))
local Kit = require(UI:WaitForChild("Kit"))
local Audio = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Audio"))

local KNOCK_RED = Color3.fromRGB(110, 8, 8)
local TITLE_RED = Color3.fromRGB(226, 70, 62)
local FADE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local KnockScreen = {}

local function nameOf(model: Model?): string
	if not model then
		return "someone"
	end
	local player = Players:GetPlayerFromCharacter(model)
	return if player then player.DisplayName else model.Name
end

-- four edge gradients make a vignette (no radial gradient in Roblox UI)
local function vignette(parent: Instance, color: Color3): { Frame }
	local edges = {}
	for _, e in {
		{ UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0), 90 },
		{ UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.68), -90 },
		{ UDim2.fromScale(0.26, 1), UDim2.fromScale(0, 0), 0 },
		{ UDim2.fromScale(0.26, 1), UDim2.fromScale(0.74, 0), 180 },
	} do
		local f = Kit.new("Frame", {
			Size = e[1],
			Position = e[2],
			BackgroundColor3 = color,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = parent,
		})
		Kit.new("UIGradient", {
			Rotation = e[3],
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) }),
			Parent = f,
		})
		table.insert(edges, f)
	end
	return edges
end

function KnockScreen.start()
	local player = Players.LocalPlayer
	local gui = Kit.new("ScreenGui", {
		Name = "KnockScreen",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 40,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local dim = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local edges = vignette(gui, KNOCK_RED)
	local title = Kit.chunky("KNOCKED", 58, TITLE_RED, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(640, 70),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
		Parent = gui,
	})
	local status = Exped.text("", 20, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 40),
		Size = UDim2.fromOffset(640, 26),
		ZIndex = 3,
		Parent = gui,
	})
	local divider = Kit.new("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 72),
		Size = UDim2.fromOffset(360, 18),
		BackgroundTransparency = 1,
		Image = Exped.IMG.ThinFrame,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 3,
		Parent = gui,
	})
	local hint = Exped.text("", 14, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.36, 96),
		Size = UDim2.fromOffset(640, 18),
		TextColor3 = Exped.Color.TextDim or Color3.fromRGB(180, 180, 180),
		ZIndex = 3,
		Parent = gui,
	}, false)

	local mode: string? = nil -- "Knocked" | "Dead"
	local knockEnds = 0
	local by: Model? = nil
	local situation = "down" -- down | carried | gripped
	local respawnAt = 0

	local function edgesTo(color: Color3, transparency: number)
		for _, e in edges do
			e.BackgroundColor3 = color
			TweenService:Create(e, FADE, { BackgroundTransparency = transparency }):Play()
		end
	end

	local function hide()
		mode = nil
		gui.Enabled = false
		dim.BackgroundTransparency = 1
		for _, e in edges do
			e.BackgroundTransparency = 1
		end
	end

	local function showKnocked()
		mode = "Knocked"
		situation = "down"
		knockEnds = os.clock() + C.KNOCK_DURATION
		gui.Enabled = true
		title.Text = "KNOCKED"
		title.TextColor3 = TITLE_RED
		divider.Visible = true
		hint.Text = "Enemies can execute you or carry you off. An ally can carry you to safety."
		edgesTo(KNOCK_RED, 0)
		TweenService:Create(dim, FADE, { BackgroundTransparency = 0.82 }):Play()
		Kit.pop(title, 0.2)
	end

	local function showDead(executedBy: Model?)
		if mode == "Dead" then
			return
		end
		mode = "Dead"
		gui.Enabled = true
		title.Text = if executedBy then "EXECUTED" else "YOU DIED"
		title.TextColor3 = if executedBy then TITLE_RED else Exped.Color.Text
		by = executedBy
		respawnAt = os.clock() + Players.RespawnTime
		divider.Visible = true
		hint.Text = ""
		edgesTo(Color3.new(0, 0, 0), 0)
		TweenService:Create(dim, TweenInfo.new(1.2), { BackgroundTransparency = 0.45 }):Play()
		Kit.pop(title, 0.25)
		Audio.play("Death")
	end

	Remotes.get("CombatResult").OnClientEvent:Connect(function(kind: string, attacker: Model?, target: Model?)
		local me = player.Character
		if not me or target ~= me then
			return
		end
		if kind == "Knocked" then
			showKnocked()
		elseif mode == "Knocked" then
			if kind == "Carry" then
				situation, by = "carried", attacker
			elseif kind == "GripStart" then
				situation, by = "gripped", attacker
			elseif kind == "Drop" or kind == "GripCancel" then
				situation, by = "down", nil
				knockEnds = math.max(knockEnds, os.clock() + 0.5)
			elseif kind == "GetUp" then
				hide()
			elseif kind == "Executed" then
				showDead(attacker)
			end
		elseif kind == "Executed" then
			showDead(attacker)
		end
	end)

	local function watch(character: Model)
		hide()
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if humanoid then
			humanoid.Died:Once(function()
				showDead(if mode == "Dead" then by else nil)
			end)
		end
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end

	-- B grips instead of casting the relic ultimate while a knocked body is in grip reach (or while
	-- gripping, to cancel): the local character attribute "GripReady" (no hover prompt, user)
	local nextScan = 0
	local function scan()
		local me = player.Character
		local root = me and me:FindFirstChild("HumanoidRootPart")
		local ready = false
		if me and root and root:IsA("BasePart") and mode == nil and me:GetAttribute("Knocked") ~= true
			and me:GetAttribute("Carrying") ~= true then
			ready = me:GetAttribute("Gripping") == true
			local function near(model: Instance?)
				if ready or not model or model == me or not model:IsA("Model") then
					return
				end
				if model:GetAttribute("Knocked") ~= true or model:GetAttribute("Carried") == true then
					return
				end
				local r = model:FindFirstChild("HumanoidRootPart")
				if r and r:IsA("BasePart") and (r.Position - root.Position).Magnitude <= C.GRIP_RANGE + 1 then
					ready = true
				end
			end
			for _, p in Players:GetPlayers() do
				near(p.Character)
			end
			for _, m in CollectionService:GetTagged("TrainingDummy") do
				near(m)
			end
		end
		if me and (me:GetAttribute("GripReady") == true) ~= ready then
			me:SetAttribute("GripReady", if ready then true else nil)
		end
	end

	RunService.Heartbeat:Connect(function()
		if os.clock() >= nextScan then
			nextScan = os.clock() + 0.1
			scan()
		end
		if mode == "Knocked" then
			local who = nameOf(by)
			status.Text = if situation == "carried" then "Carried by " .. who
				elseif situation == "gripped" then "Being executed by " .. who
				else string.format("Getting up in %d", math.max(0, math.ceil(knockEnds - os.clock())))
			-- the red edges breathe like a heartbeat
			local p = (os.clock() * 1.1) % 1
			local beat = math.max(0, math.sin(p * math.pi * 4)) * (if p < 0.5 then 1 else 0)
			for _, e in edges do
				e.BackgroundTransparency = 0.12 - 0.12 * beat
			end
		elseif mode == "Dead" then
			local left = math.max(0, math.ceil(respawnAt - os.clock()))
			status.Text = (if by then "by " .. nameOf(by) .. "   " else "") .. string.format("Respawning in %d", left)
		end
	end)
end

return KnockScreen
