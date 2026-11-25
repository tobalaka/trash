--!strict
-- Client entry point for Pollution Beasts: animation, effects and the boss bar.
-- Logic lives in ReplicatedStorage.Client.Mobs.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mobs = ReplicatedStorage:WaitForChild("Client"):WaitForChild("Mobs")
local MobAnimator = require(Mobs:WaitForChild("MobAnimator"))
local MobFx = require(Mobs:WaitForChild("MobFx"))
local MobHud = require(Mobs:WaitForChild("MobHud"))

local TAG = "PollutionBeast"
local active: { [Instance]: () -> () } = {}

local function add(instance: Instance)
	if not instance:IsA("Model") or active[instance] then
		return
	end
	active[instance] = function() end -- reserved while the parts arrive
	local fx = MobFx.attach(instance)
	local stopAnimation = MobAnimator.attach(instance, fx.onFoot)
	if active[instance] then
		active[instance] = function()
			stopAnimation()
			fx.stop()
		end
	else
		stopAnimation()
		fx.stop()
	end
end

local function remove(instance: Instance)
	local stop = active[instance]
	active[instance] = nil
	if stop then
		stop()
	end
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(function(i)
	task.spawn(add, i)
end)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, i in CollectionService:GetTagged(TAG) do
	task.spawn(add, i)
end
MobHud.start(TAG)
