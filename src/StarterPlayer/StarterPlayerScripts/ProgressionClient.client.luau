--!strict
-- Client entry point for progression gameplay: Relic moves and their effects, the NPC bodies,
-- Smogling animation and world effects. Windows and the HUD live in ReplicatedStorage.UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = ReplicatedStorage:WaitForChild("Client"):WaitForChild("Progression")

for _, name in { "RelicFx", "RelicController", "NpcRenderer", "SmoglingAnimator", "WorldFx" } do
	task.spawn(function()
		require(Progression:WaitForChild(name) :: ModuleScript).start()
	end)
end
