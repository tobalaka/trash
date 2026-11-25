--!strict
--[[
	MobService - spawns Pollution Beasts at their markers and respawns them after they die.

	A marker is any BasePart tagged "MobSpawn" with a "Mob" attribute naming an entry in
	Shared/Config/Mobs (Workspace.World.Wasteland.MobSpawns holds the Junk Ram's). One beast per
	marker. Live beasts sit in Workspace.Mobs and carry the "PollutionBeast" tag, which clients
	use to animate them and draw their effects.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MobsConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Mobs"))

local SPAWN_TAG = "MobSpawn"
local BEAST_TAG = "PollutionBeast"

type Brain = { start: (model: Model, home: Vector3, onDead: () -> ()) -> () -> () }

local BRAINS: { [string]: Brain } = {
	JunkRam = require(script.Parent:WaitForChild("JunkRamBrain")),
}

local MobService = {}

local folder: Folder

local function spawnAt(marker: BasePart)
	local key = marker:GetAttribute("Mob")
	local cfg = if typeof(key) == "string" then (MobsConfig :: any)[key] else nil
	local brain = if typeof(key) == "string" then BRAINS[key] else nil
	local template = if cfg then ServerStorage:WaitForChild("Mobs"):FindFirstChild(cfg.TEMPLATE) else nil
	if not cfg or not brain or not template or not template:IsA("Model") then
		warn("[MobService] marker " .. marker:GetFullName() .. " names an unknown mob: " .. tostring(key))
		return
	end

	local model = template:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model.PrimaryPart :: BasePart
	humanoid.MaxHealth = cfg.MAX_HEALTH
	humanoid.Health = cfg.MAX_HEALTH
	local standHeight = humanoid.HipHeight + root.Size.Y / 2
	local _, yaw, _ = marker.CFrame:ToOrientation()
	model:PivotTo(CFrame.new(marker.Position + Vector3.new(0, standHeight, 0)) * CFrame.Angles(0, yaw, 0))
	model.Name = cfg.TEMPLATE
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = folder
	root:SetNetworkOwner(nil)
	CollectionService:AddTag(model, BEAST_TAG)

	local stop: (() -> ())? = nil
	stop = brain.start(model, marker.Position, function()
		task.delay(cfg.CORPSE_TIME, function()
			if stop then
				stop()
			end
			model:Destroy()
		end)
		task.delay(cfg.RESPAWN_TIME, function()
			if marker.Parent then
				spawnAt(marker)
			end
		end)
	end)
end

function MobService.start()
	local existing = workspace:FindFirstChild("Mobs")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Mobs"
		folder.Parent = workspace
	end
	for _, marker in CollectionService:GetTagged(SPAWN_TAG) do
		if marker:IsA("BasePart") then
			task.spawn(spawnAt, marker)
		end
	end
	CollectionService:GetInstanceAddedSignal(SPAWN_TAG):Connect(function(marker)
		if marker:IsA("BasePart") then
			spawnAt(marker)
		end
	end)
end

return MobService
