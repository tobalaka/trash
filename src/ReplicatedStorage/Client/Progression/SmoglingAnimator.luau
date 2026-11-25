--!strict
--[[
	SmoglingAnimator - makes Smoglings look alive on this client. Each one's body hangs off a
	Motor6D named "Wobble"; every frame it bobs and sways, leans back and springs forward through
	a lunge (the server's Action / ActionStart attributes), and squashes flat when it dies.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "Smogling"
local WINDUP = 0.45 -- matches Config.Environment.SMOGLING.WINDUP
local BOB = 0.25
local SWAY = 6

local SmoglingAnimator = {}

local motors: { [Model]: Motor6D } = {}

local function add(model: Instance)
	if not model:IsA("Model") then
		return
	end
	task.spawn(function()
		local root = model:WaitForChild("HumanoidRootPart", 10)
		local motor = root and root:WaitForChild("Wobble", 10)
		if motor and motor:IsA("Motor6D") and model.Parent then
			motors[model] = motor
		end
	end)
end

function SmoglingAnimator.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(m)
		motors[m :: Model] = nil
	end)
	for _, m in CollectionService:GetTagged(TAG) do
		add(m)
	end
	RunService.Stepped:Connect(function()
		local t = os.clock()
		local server = workspace:GetServerTimeNow()
		for model, motor in motors do
			if not model.Parent or not motor.Parent then
				motors[model] = nil
				continue
			end
			local seed = (model:GetFullName():len() % 7) * 0.9
			local action = model:GetAttribute("Action")
			local bob = math.sin(t * 5 + seed) * BOB
			local sway = math.sin(t * 3 + seed) * SWAY
			local lean = 0
			if action == "Lunge" then
				local e = server - ((model:GetAttribute("ActionStart") :: number?) or server)
				if e < WINDUP then
					lean = -18 * (e / WINDUP) -- rear back
				else
					lean = 28 * math.max(0, 1 - (e - WINDUP) / 0.3) -- spring forward
				end
			elseif action == "Dead" then
				motor.Transform = CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, math.rad(70))
				continue
			end
			motor.Transform = CFrame.new(0, bob, 0) * CFrame.Angles(math.rad(-lean), 0, math.rad(sway))
		end
	end)
end

return SmoglingAnimator
