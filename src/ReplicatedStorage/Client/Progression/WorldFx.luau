--!strict
--[[
	WorldFx - the world reacting on this client:
	  - salvage prompts read "Sort" (Menders), "Strip" (Scrappers) or "Salvage", with that hold
	    time (the server checks the hold itself);
	  - before a Sky Dump lands, trash rains out of the sky over the site;
	  - Vitality below BLOOD_VISION fades and blurs your vision (Blood.md), worse while knocked;
	    Wastezone gas without a respirator tints everything sick green;
	  - the server's pollution grades the whole picture: browner and flatter under smog, a little
	    brighter under clear skies;
	  - holding a salvage or "Help up" prompt plays the Salvage / HelpUp animation (2026-10-26).
	Lighting effects are this script's own (names starting "Progression"), so the region
	atmosphere script that owns the sky and fog is untouched.
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Environment = require(Config:WaitForChild("Environment"))
local Survival = require(Config:WaitForChild("Survival"))
local Factions = require(Config:WaitForChild("Factions"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Anims = require(Shared:WaitForChild("Anims"))

local RAIN_PIECES = 46
local HOLD_ANIMS: { [string]: string } = { Salvage = "Salvage", HelpUp = "HelpUp" } -- prompt name -> Animations entry
local RAIN_HEIGHT = 260
local TRASH_COLORS = {
	Color3.fromRGB(40, 40, 44),
	Color3.fromRGB(120, 96, 64),
	Color3.fromRGB(150, 150, 146),
	Color3.fromRGB(196, 92, 52),
	Color3.fromRGB(90, 140, 150),
	Color3.fromRGB(214, 200, 160),
}

local WorldFx = {}

local function method(): string
	local faction = Players.LocalPlayer:GetAttribute("Faction")
	local info = if typeof(faction) == "string" then Factions.INFO[faction] else nil
	return if info then info.method else Factions.UNALIGNED_METHOD
end

local function effect(className: string, name: string): any
	local e = Lighting:FindFirstChild(name)
	if not e then
		e = Instance.new(className)
		e.Name = name
		e.Parent = Lighting
	end
	return e
end

local function rain(center: Vector3, delay: number)
	local holder = Instance.new("Folder")
	holder.Name = "SkyDumpRain"
	holder.Parent = workspace
	Debris:AddItem(holder, delay + 3)
	for i = 1, RAIN_PIECES do
		task.delay(math.random() * delay * 0.85, function()
			local p = Instance.new("Part")
			local s = 0.8 + math.random() * 1.8
			p.Size = Vector3.new(s, s * (0.5 + math.random() * 0.6), s * (0.6 + math.random() * 0.6))
			p.Color = TRASH_COLORS[math.random(1, #TRASH_COLORS)]
			p.Material = if i % 2 == 0 then Enum.Material.Fabric else Enum.Material.CorrodedMetal
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			local land = center + Vector3.new((math.random() - 0.5) * 2 * Environment.DUMP_RADIUS, 0, (math.random() - 0.5) * 2 * Environment.DUMP_RADIUS)
			local from = land + Vector3.new(0, RAIN_HEIGHT, 0)
			p.CFrame = CFrame.new(from)
			p.Parent = holder
			local fall = 1.2 + math.random() * 0.6
			local start = os.clock()
			local spin = Vector3.new(math.random() * 6, math.random() * 6, math.random() * 6)
			local conn: RBXScriptConnection
			conn = RunService.RenderStepped:Connect(function()
				local k = math.min(1, (os.clock() - start) / fall)
				p.CFrame = CFrame.new(from:Lerp(land, k * k)) * CFrame.Angles(spin.X * k, spin.Y * k, spin.Z * k)
				if k >= 1 then
					conn:Disconnect()
					p.Transparency = 0.4
					Debris:AddItem(p, 0.4)
				end
			end)
		end)
	end
end

function WorldFx.start()
	local player = Players.LocalPlayer

	-- salvage prompts: label and hold time by faction (shorter with Fleetfoot's Quick Hands);
	-- "Help up" on a knocked player only for allies who have Supporter's Field Revive
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if prompt.Name == "Salvage" then
			local m = method()
			local speed = player:GetAttribute("SalvageSpeed")
			prompt.ActionText = m
			prompt.HoldDuration = (Environment.HOLD[m] or Environment.HOLD.Salvage) * (if typeof(speed) == "number" then speed else 1)
		elseif prompt.Name == "HelpUp" then
			local mine = player.Character and prompt:IsDescendantOf(player.Character)
			local ally = prompt:GetAttribute("Faction") ~= nil and prompt:GetAttribute("Faction") == player:GetAttribute("Faction")
			if mine or not ally or player:GetAttribute("FieldRevive") ~= true then
				prompt.Enabled = false
			end
		end
	end)

	-- holding a salvage or help-up prompt plays its looped animation until the hold ends
	local holding: string? = nil
	local function holdSet(): any
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		return if animator then Anims.forAnimator(animator) else nil
	end
	local function endHold()
		if holding then
			local set = holdSet()
			if set then
				set:stop(holding, 0.2)
			end
			holding = nil
		end
	end
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local anim = HOLD_ANIMS[prompt.Name]
		local set = anim and holdSet()
		if anim and set then
			endHold()
			holding = anim
			set:play(anim, 0.2)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(endHold)
	ProximityPromptService.PromptTriggered:Connect(endHold)

	-- Sky Dumps
	Remotes.get("WorldEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "DumpIncoming" and typeof(data) == "table" and typeof(data.position) == "Vector3" then
			rain(data.position, data.delay or 8)
		end
	end)

	-- vision and air grading
	local vision = effect("ColorCorrectionEffect", "ProgressionVitality")
	local blur = effect("BlurEffect", "ProgressionVitalityBlur")
	local grade = effect("ColorCorrectionEffect", "ProgressionAir")
	blur.Size = 0
	RunService.RenderStepped:Connect(function()
		local blood = player:GetAttribute("Blood")
		local max = player:GetAttribute("BloodMax")
		local frac = if typeof(blood) == "number" and typeof(max) == "number" and max > 0 then blood / max else 1
		local threshold = Survival.BLOOD_VISION / 100
		local fade = math.clamp((threshold - frac) / threshold, 0, 1)
		if player:GetAttribute("Knocked") then
			fade = math.max(fade, 0.85)
		end
		local toxic = player:GetAttribute("Toxic") == true
		vision.Saturation = -0.8 * fade + (if toxic then -0.2 else 0)
		vision.Brightness = -0.18 * fade
		vision.Contrast = 0.1 * fade
		vision.TintColor = if toxic then Color3.fromRGB(196, 230, 150) else Color3.new(1, 1, 1):Lerp(Color3.fromRGB(220, 200, 200), fade)
		blur.Size = 10 * fade
		local pollution = workspace:GetAttribute("Pollution")
		local p = if typeof(pollution) == "number" then pollution else Environment.POLLUTION_START
		local smog = math.clamp((p - Environment.POLLUTION_START) / (Environment.POLLUTION_MAX - Environment.POLLUTION_START), 0, 1)
		local clear = math.clamp((Environment.POLLUTION_START - p) / Environment.POLLUTION_START, 0, 1)
		grade.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(232, 214, 176), smog)
		grade.Saturation = -0.25 * smog + 0.08 * clear
		grade.Brightness = -0.04 * smog + 0.03 * clear
	end)
end

return WorldFx
