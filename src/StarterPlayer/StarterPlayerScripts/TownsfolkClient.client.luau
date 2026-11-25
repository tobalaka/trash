--!strict
-- Client entry point for the ambient town crowd (cosmetic, client-only).
-- Logic lives in ReplicatedStorage.Client.Townsfolk.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Townsfolk = ReplicatedStorage:WaitForChild("Client"):WaitForChild("Townsfolk")
local TownsfolkController = require(Townsfolk:WaitForChild("TownsfolkController"))

TownsfolkController.start()
