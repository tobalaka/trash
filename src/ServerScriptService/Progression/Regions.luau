--!strict
--[[
	Regions - which map region a point or player is in, from the MapGen region volumes
	(ReplicatedStorage.MapRegionVolumes, the same lookup the region title cards use). Tracks each
	player's region once a second and emits a "Visit" event when it changes.
	Keys: TownDome, Town, Wasteland, Desert, Jungle, Winter, MendersBase, ScrappersBase.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bus = require(script.Parent:WaitForChild("Bus"))

local CHECK = 1

local Regions = {}

local volumes: Instance? = nil
local lookup: ((Instance?, Vector3) -> string?)? = nil
local current: { [Player]: string } = {}

local function resolve()
	if lookup then
		return
	end
	volumes = ReplicatedStorage:FindFirstChild("MapRegionVolumes")
	local shared = ReplicatedStorage:FindFirstChild("MapShared")
	local module = shared and shared:FindFirstChild("RegionAtmosphere")
	if module and module:IsA("ModuleScript") then
		lookup = (require(module) :: any).regionAt
	end
end

function Regions.at(position: Vector3): string?
	resolve()
	if not lookup then
		return nil
	end
	return (lookup :: any)(volumes, position)
end

function Regions.rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function Regions.of(player: Player): string?
	return current[player]
end

function Regions.start()
	Players.PlayerRemoving:Connect(function(player)
		current[player] = nil
	end)
	task.spawn(function()
		while true do
			for _, player in Players:GetPlayers() do
				local root = Regions.rootOf(player)
				if root then
					local key = Regions.at(root.Position)
					if key and key ~= current[player] then
						current[player] = key
						player:SetAttribute("Region", key)
						Bus.emit(player, "Visit", { region = key })
					end
				end
			end
			task.wait(CHECK)
		end
	end)
end

return Regions
