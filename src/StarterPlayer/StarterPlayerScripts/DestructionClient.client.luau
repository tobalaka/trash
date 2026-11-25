--!strict
-- Client entry point for the breakable map: draws the debris of every break nearby.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebrisFx = require(ReplicatedStorage:WaitForChild("Client"):WaitForChild("Destruction"):WaitForChild("DebrisFx"))
DebrisFx.start()
