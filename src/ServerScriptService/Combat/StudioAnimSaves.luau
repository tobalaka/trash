--!strict
-- Ships saved R6 clips for runtime playback; relay is cosmetic only.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Config = require(RS.Shared.Config.Animations)
local StudioAnimSaves = {}
function StudioAnimSaves.publish()
	local out = RS:FindFirstChild("StudioAnimSaves")
	if not out then
		out = Instance.new("Folder")
		out.Name = "StudioAnimSaves"
		for _, entry in {{"Rig", workspace:FindFirstChild("Rig")}, {"R6", RS:FindFirstChild("Anims r6")}} do
			local source = entry[2]
			local saves = source and source:FindFirstChild("AnimSaves")
			if saves then
				local folder = Instance.new("Folder")
				folder.Name = entry[1]
				for _, save in saves:GetChildren() do
					if save:IsA("KeyframeSequence") then save:Clone().Parent = folder end
				end
				folder.Parent = out
			end
		end
		out.Parent = RS
	end
	if RS:FindFirstChild("AnimationRelay") then return end
	local remote = Instance.new("RemoteEvent")
	remote.Name = "AnimationRelay"
	remote.Parent = RS
	local budgets: {[Player]: {at: number, count: number}} = {}
	remote.OnServerEvent:Connect(function(player, mode, name, fade, speed)
		if typeof(mode) ~= "string" or (mode ~= "Play" and mode ~= "Stop" and mode ~= "Speed") then return end
		if typeof(name) ~= "string" or not Config[name] then return end
		if typeof(fade) ~= "number" or fade ~= fade or math.abs(fade) == math.huge then return end
		if typeof(speed) ~= "number" or speed ~= speed or math.abs(speed) == math.huge then return end
		local model = player.Character
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if not model or not hum or hum.Health <= 0 then return end
		local at = os.clock()
		local b = budgets[player]
		if not b or at - b.at >= 1 then b = {at = at, count = 0}; budgets[player] = b end
		b.count += 1
		if b.count > 45 then return end
		remote:FireAllClients(model, mode, name, math.clamp(fade, 0.001, 0.5), math.clamp(speed, -4, 4))
	end)
	Players.PlayerRemoving:Connect(function(player) budgets[player] = nil end)
end
return StudioAnimSaves
