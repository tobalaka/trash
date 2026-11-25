local TweenService = game:GetService("TweenService")

local trainSystem = script.Parent
local trainHitbox = trainSystem:WaitForChild("Train"):WaitForChild("TrainHitbox")
local nodesFolder = trainSystem:WaitForChild("Nodes")

-- Speed configuration (Studs per second)
local trainSpeed = 75 

local function getNodes()
	local nodes = nodesFolder:GetChildren()
	-- Sort the nodes numerically (1, 2, 3, etc.)
	table.sort(nodes, function(a, b)
		return tonumber(a.Name) < tonumber(b.Name)
	end)
	return nodes
end

local function startTrain()
	local trackNodes = getNodes()

	while true do
		-- Teleport train to the starting node
		trainHitbox.CFrame = trackNodes[1].CFrame

		-- Move through each node in order
		for i = 2, #trackNodes do
			local targetNode = trackNodes[i]
			local distance = (trainHitbox.Position - targetNode.Position).Magnitude
			local timeToTravel = distance / trainSpeed

			local tweenInfo = TweenInfo.new(timeToTravel, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut)
			local moveTween = TweenService:Create(trainHitbox, tweenInfo, {CFrame = targetNode.CFrame})

			moveTween:Play()
			moveTween.Completed:Wait() -- Wait for the train to reach the node before continuing
		end

		-- Wait 2 seconds before respawning at the start and looping
		task.wait(2)
	end
end

-- Start the engine
startTrain()