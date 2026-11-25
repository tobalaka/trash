-- Cloned to PlayerGui by TrainingSpec; verifies local motion before replication catches up.
local RunService=game:GetService("RunService")
local character=game.Players.LocalPlayer.Character
local root=character.HumanoidRootPart
local report=script:WaitForChild("Report")
local origin,elapsed
local connection
connection=RunService.Heartbeat:Connect(function(dt)
 if not origin then
  if character:GetAttribute("CombatState") ~= "Dodge" then return end
  origin=root.Position
  elapsed=0
 end
 elapsed+=dt
 if elapsed >= .10 then
  connection:Disconnect()
  report:FireServer((root.Position-origin).Magnitude)
 end
end)
