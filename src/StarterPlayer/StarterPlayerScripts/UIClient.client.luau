--!strict
-- UIClient - entry point for the TRASH interface. All logic lives in ReplicatedStorage.UI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = ReplicatedStorage:WaitForChild("UI")
local UIController = require(UI:WaitForChild("UIController"))
UIController.start()
require(UI:WaitForChild("PromptSkin")).start() -- proximity prompts in the EXPED skin
