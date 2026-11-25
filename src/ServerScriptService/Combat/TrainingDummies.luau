--!strict
-- TrainingDummies - keeps every model tagged "TrainingDummy" alive so combat can be tested on it
-- indefinitely. 2026-10-25: at 0 health a dummy is knocked like a player (Knock), so grip and
-- carry can be practised on it; it stands back up at full health (an executed one a moment later).

local CollectionService = game:GetService("CollectionService")

local Knock = require(script.Parent:WaitForChild("Knock"))

local TAG = "TrainingDummy"

local TrainingDummies = {}

local function watch(model: Instance)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or not model:IsA("Model") then
		return
	end
	humanoid.BreakJointsOnDeath = false
	Knock.watch(model)
end

function TrainingDummies.start()
	for _, model in CollectionService:GetTagged(TAG) do
		watch(model)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(watch)
end

return TrainingDummies
