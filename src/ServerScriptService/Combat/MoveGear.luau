--!strict
--[[
	MoveGear - hands every player the Tarp Glider and the Junk Board (hotbar Tools; EXPED's Glider and
	Skateboard, 2026-10-25) and shows them on the body for everyone: the rolled glider on the back
	and the board under the feet while equipped, the open glider while gliding.
	Models: ReplicatedStorage.GearModels (trash-art blender/gen_gear.py, batch Gear1), each pivoted
	at its attach point: GliderOpen / GliderPack in the Torso's frame, JunkBoard at the deck's top.
	GearState (C -> S) "Glide", on: boolean sets the character attribute "Gliding" (glider equipped
	only). The riding itself is the client's (ReplicatedStorage.Client.MoveGear).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))

local GEAR = {
	{ id = "Glider", name = "Tarp Glider", tip = "Hold Space while falling to glide. Look down to dive, up to float." },
	{ id = "Board", name = "Junk Board", tip = "Equip on the ground to ride: W A S D push, Space ollies." },
}
local FEET = 3 -- R6: root centre to the soles

local MoveGear = {}

local function template(name: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("GearModels")
	local m = folder and folder:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end

local function attach(character: Model, name: string, partName: string, offset: CFrame): Model?
	local t = template(name)
	local body = character:FindFirstChild(partName)
	if not t or not body or not body:IsA("BasePart") then
		return nil
	end
	local m = t:Clone()
	m.Name = "Gear_" .. name
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
		end
	end
	m:PivotTo(body.CFrame * offset)
	local primary = m.PrimaryPart :: BasePart
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = body
	weld.Part1 = primary
	weld.Parent = primary
	m.Parent = character
	return m
end

local function show(model: Instance?, visible: boolean)
	if not model then
		return
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = if visible then 0 else 1
		end
	end
end

local function makeTool(def: { id: string, name: string, tip: string }): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = def.tip
	tool:SetAttribute("MoveGear", def.id)
	tool:SetAttribute("Rarity", "Uncommon")
	tool.Equipped:Connect(function()
		local character = tool.Parent
		if not character or not character:IsA("Model") then
			return
		end
		if def.id == "Glider" then
			attach(character, "GliderPack", "Torso", CFrame.identity)
			-- 0.6 lower than authored: the control bar sits in the raised hands of TRASH_Glide
			show(attach(character, "GliderOpen", "Torso", CFrame.new(0, -0.6, 0)), false)
		else
			attach(character, "JunkBoard", "HumanoidRootPart", CFrame.new(0, -FEET, 0))
		end
	end)
	tool.Unequipped:Connect(function()
		-- the tool has already moved back to the Backpack: clean the last character up
		local player = tool:FindFirstAncestorOfClass("Player")
		local character = player and player.Character
		if not character then
			return
		end
		for _, name in (if def.id == "Glider" then { "Gear_GliderPack", "Gear_GliderOpen" } else { "Gear_JunkBoard" }) do
			local m = character:FindFirstChild(name)
			if m then
				m:Destroy()
			end
		end
		if def.id == "Glider" then
			character:SetAttribute("Gliding", nil)
		end
	end)
	return tool
end

local function give(player: Player)
	local backpack = player:WaitForChild("Backpack", 10)
	if not backpack then
		return
	end
	for _, def in GEAR do
		local has = false
		for _, container in { backpack, player.Character } do
			for _, t in (if container then container:GetChildren() else {}) do
				if t:IsA("Tool") and t:GetAttribute("MoveGear") == def.id then
					has = true
				end
			end
		end
		if not has then
			makeTool(def).Parent = backpack
		end
	end
end

local function onGearState(player: Player, kind: any, on: any)
	if not RateLimit.allow(player, "Gear", 8) or kind ~= "Glide" or typeof(on) ~= "boolean" then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or tool:GetAttribute("MoveGear") ~= "Glider" then
		character:SetAttribute("Gliding", nil)
		return
	end
	character:SetAttribute("Gliding", if on then true else nil)
	show(character:FindFirstChild("Gear_GliderOpen"), on)
	show(character:FindFirstChild("Gear_GliderPack"), not on)
end

function MoveGear.start()
	Remotes.get("GearState").OnServerEvent:Connect(onGearState)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			give(player)
		end)
		if player.Character then
			task.spawn(give, player)
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return MoveGear
