--!strict
--[[
	Arrival - nobody has a body until they press PLAY on the intro screen (vault: Intro;
	client: UI/Screens/Intro). Players.CharacterAutoLoads is off, so this module spawns and
	respawns everyone.

	  - Play (C -> S): refused while the save is loading or the player has no side yet (the
	    intro shows the side picker first; FactionService accepts SelectFaction while the player
	    has no body). Accepted once per session: later requests do nothing, so PLAY can't be used
	    to escape a fight or ride home.
	  - Where: a character who hasn't met Old Mags yet (ARRIVAL_QUEST) wakes up at the Gate Market,
	    where the Prologue starts; everyone else at their faction base (FactionService.homeSpawn).
	  - Respawns: Players.RespawnTime after a death. A slow check also puts back anyone who has
	    played but was left without a living body.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local FactionService = require(script.Parent:WaitForChild("FactionService"))

local ARRIVAL_QUEST = "P0_Arrival" -- talking to Old Mags; until then you wake up at the market
local PLAY_RATE = 1 -- Play requests per second
local SAFETY_CHECK = 2 -- seconds between checks for players left without a body

local Arrival = {}

local played: { [Player]: boolean } = {}
local loading: { [Player]: boolean } = {}
local deadSince: { [Player]: number } = {}

-- has `player` pressed PLAY (or otherwise been given a body) this session?
function Arrival.hasPlayed(player: Player): boolean
	return played[player] == true
end

local function spawnPoint(player: Player): SpawnLocation?
	local p = Profiles.get(player)
	if p and not p.quests.done[ARRIVAL_QUEST] then
		return FactionService.spawnOf("Town")
	end
	return FactionService.homeSpawn(player)
end

local function load(player: Player)
	if loading[player] or not player.Parent then
		return
	end
	loading[player] = true
	local spawn = spawnPoint(player)
	if spawn then
		player.RespawnLocation = spawn
	end
	local ok, err = pcall(function()
		player:LoadCharacter()
	end)
	loading[player] = nil
	if not ok then
		warn("[Arrival] couldn't spawn " .. player.Name .. ": " .. tostring(err))
	end
end

local function play(player: Player)
	if played[player] or not Guard.allow(player, "Play", PLAY_RATE) then
		return
	end
	local p = Profiles.get(player)
	if not p then
		Sync.notify(player, "Toast", { text = "Still loading your save. Try again in a moment.", color = "Red" })
		return
	end
	if not p.faction then
		Sync.notify(player, "Toast", { text = "Pick a side first.", color = "Red" })
		return
	end
	played[player] = true
	load(player)
end

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character.Parent and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		-- a body from anywhere (PLAY, a respawn, or one loaded before this module started)
		played[player] = true
		deadSince[player] = nil
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Once(function()
				deadSince[player] = os.clock()
				task.delay(Players.RespawnTime, function()
					if player.Parent and player.Character == character then
						load(player)
					end
				end)
			end)
		end
	end)
	if player.Character then
		played[player] = true
	end
end

function Arrival.start()
	Players.CharacterAutoLoads = false
	Remotes.get("Play").OnServerEvent:Connect(play)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		played[player] = nil
		loading[player] = nil
		deadSince[player] = nil
	end)
	-- safety net: someone who has played but has no living body gets one back
	task.spawn(function()
		while true do
			task.wait(SAFETY_CHECK)
			local t = os.clock()
			for player in played do
				if player.Parent and not loading[player] then
					if alive(player) then
						deadSince[player] = nil
					else
						local since = deadSince[player]
						if not since then
							deadSince[player] = t
						elseif t - since > Players.RespawnTime + SAFETY_CHECK then
							deadSince[player] = nil
							task.spawn(load, player)
						end
					end
				end
			end
		end
	end)
end

return Arrival
