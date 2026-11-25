--!strict
-- Server entry point for movement and combat. Logic lives in the sibling modules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

Remotes.init()
require(script.Parent:WaitForChild("StudioAnimSaves")).publish()
if workspace:GetAttribute("JoblessCombatTest") then
	require(script.Parent:WaitForChild("Service")).Start()
else
	require(script.Parent:WaitForChild("CombatService")).start()
	require(script.Parent:WaitForChild("TrainingDummies")).start()
	require(script.Parent:WaitForChild("MoveGear")).start()
end
