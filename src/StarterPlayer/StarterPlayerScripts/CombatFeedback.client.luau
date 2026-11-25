--!strict
-- CombatFeedback - hit, block, parry and dodge flashes for every fighter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Feedback")).start()
