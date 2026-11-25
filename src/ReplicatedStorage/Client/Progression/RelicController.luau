--!strict
--[[
	RelicController - Relic moves on Z X C R B for the local player (vault: Relic-Abilities,
	Keybinds). Checks what the HUD already shows (the tier unlocks the key, the cooldown is over,
	the ultimate's Anima is full, you aren't stunned, ragdolled, grabbed or knocked), then sends
	AbilityRequest and predicts dashes, leaps and hops because the player's client owns its
	character's physics. RelicFx/RelicAnimator play distinct weapon animations for everyone
	only after the server accepts the cast. The server decides every hit.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Action = require(script.Parent.Parent:WaitForChild("Action"))

local KEYS: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Z] = "Z",
	[Enum.KeyCode.X] = "X",
	[Enum.KeyCode.C] = "C",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.B] = "B",
}
local TIER_FOR = { Z = 1, X = 2, C = 3, R = 0, B = 0 }
local BLOCKED_STATES = { Stunned = true, Ragdolled = true, Grabbed = true }
local DASH_FORCE = 1e6

local RelicController = {}

local busyUntil = 0
local started = false

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- Fleetfoot's Light Feet: the server mirrors the perk as the DashRange attribute
local function range(): number
	local r = Players.LocalPlayer:GetAttribute("DashRange")
	return if typeof(r) == "number" then r else 1
end

-- pushes the root horizontally at `velocity` for `time`; gravity still applies
local function drive(rootPart: BasePart, velocity: Vector3, time: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "RelicMove"
	attachment.Parent = rootPart
	local mover = Instance.new("LinearVelocity")
	mover.Name = "RelicMove"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	mover.MaxAxesForce = Vector3.new(DASH_FORCE, 0, DASH_FORCE)
	mover.VectorVelocity = velocity
	mover.Parent = rootPart
	task.delay(time, function()
		mover:Destroy()
		attachment:Destroy()
	end)
end

local function cast(key: string)
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart:IsA("BasePart") then
		return
	end
	local j = Relics.get(player:GetAttribute("Relic") :: string?)
	local a = j and j.abilities[key]
	if not j or not a then
		return
	end
	local tier = player:GetAttribute("UpgradeTier")
	if typeof(tier) ~= "number" or tier < TIER_FOR[key] then
		return
	end
	local t = now()
	local ends = player:GetAttribute("CooldownEnd_" .. key)
	if typeof(ends) == "number" and ends > t + 0.05 then
		return
	end
	if t < busyUntil then
		return
	end
	if Action.get(character) then
		return
	end
	if BLOCKED_STATES[character:GetAttribute("CombatState") :: any] or player:GetAttribute("Knocked")
		or character:GetAttribute("Carrying") or character:GetAttribute("Gripping") then
		return
	end
	if a.ultimate then
		local anima = player:GetAttribute("Anima")
		local max = player:GetAttribute("AnimaMax")
		-- the server applies perks to the exact cost; this just skips obviously empty meters
		if typeof(anima) ~= "number" or typeof(max) ~= "number" or anima < max * 0.8 then
			return
		end
	end
	local camera = workspace.CurrentCamera
	local dir = flat(if camera then camera.CFrame.LookVector else rootPart.CFrame.LookVector)
	busyUntil = t + a.windup + a.lock
	Remotes.get("AbilityRequest"):FireServer(key, dir, t)

	-- the caster's own movement
	if a.kind == "Dash" then
		task.delay(a.windup, function()
			if rootPart.Parent then
				local duration = a.duration or 0.3
				drive(rootPart, dir * ((a.distance or 15) * range() / duration), duration)
			end
		end)
	elseif a.kind == "Leap" then
		task.delay(a.windup, function()
			if rootPart.Parent then
				local duration = a.duration or 0.5
				rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, workspace.Gravity * duration / 2, rootPart.AssemblyLinearVelocity.Z)
				drive(rootPart, dir * ((a.distance or 20) * range() / duration), duration)
			end
		end)
	elseif a.kind == "Hop" then
		local duration = a.duration or 0.25
		rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 18, rootPart.AssemblyLinearVelocity.Z)
		drive(rootPart, -dir * ((a.distance or 12) * range() / duration), duration)
	end
end

function RelicController.start()
	if started then return end
	started = true
	Players.LocalPlayer.CharacterAdded:Connect(function()
		busyUntil = 0
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		-- "MenuOpen" is a local attribute the UI sets while a window, dialogue or roll is open
		if processed or UserInputService:GetFocusedTextBox() or Players.LocalPlayer:GetAttribute("MenuOpen") then
			return
		end
		local key = KEYS[input.KeyCode]
		-- next to a knocked body B is the grip (Shared/Config/Keys), not the ultimate
		local character = Players.LocalPlayer.Character
		if key == "B" and character and character:GetAttribute("GripReady") == true then
			return
		end
		if key then
			cast(key)
		end
	end)
end

return RelicController
