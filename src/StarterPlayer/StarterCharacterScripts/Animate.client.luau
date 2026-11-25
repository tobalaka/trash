--!strict
-- Animate - replaces Roblox's default Animate (same name, so the default is not added).
-- Logic lives in ReplicatedStorage.Client.Locomotion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Locomotion = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Locomotion"))

Locomotion.start(script.Parent :: Model)
