--!strict
-- Controls - movement and combat input for this character. Logic lives in ReplicatedStorage.Client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = ReplicatedStorage:WaitForChild("Client")
local Movement = require(Client:WaitForChild("Movement"))
local CombatController = require(Client:WaitForChild("CombatController"))
local MoveGear = require(Client:WaitForChild("MoveGear"))

local character = script.Parent :: Model
task.spawn(Movement.start, character)
task.spawn(MoveGear.start, character)
CombatController.start(character)
