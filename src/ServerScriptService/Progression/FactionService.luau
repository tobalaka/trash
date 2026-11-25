--!strict
--[[
	FactionService - Menders vs Scrappers (vault: Faction-Selection, Menders, Scrappers,
	Faction-Standing).

	  - Joining: chosen once, on the intro screen before the first spawn (Arrival: nobody has a
	    body until they press PLAY, and PLAY needs a side). SelectFaction is accepted while the
	    player has no character yet, or for a short time after a recruiter's dialogue opened the
	    choice window (characters from before the intro), so a bare remote call mid-game does
	    nothing. Joining marks your character, moves your respawn to your base and rolls your
	    first Relic for free once you are in the world.
	  - Spawns: new characters wake up at the Gate Market in Patchwork Town (Arrival); faction
	    members respawn at their base. Recruiters and quartermasters offer rides between the two.
	  - Marks: Menders wear a teal waist hoop, Scrappers a purple chest patch (Gear).
	  - Rivalry: defeating a rival-faction player outside the bases pays a bounty (Bounties).
	  - Safe zones: Relic moves can't hurt players inside either base (RelicService asks
	    FactionService.canHurt).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Factions = require(Config:WaitForChild("Factions"))
local Relic = require(Config:WaitForChild("Relic"))
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))
local Npcs = require(Shared:WaitForChild("Data"):WaitForChild("Npcs"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Gacha = require(script.Parent:WaitForChild("Gacha"))
local Gear = require(script.Parent:WaitForChild("Gear"))
local Regions = require(script.Parent:WaitForChild("Regions"))
local Ground = require(script.Parent:WaitForChild("Ground"))
local Bus = require(script.Parent:WaitForChild("Bus"))
local Guard = require(script.Parent:WaitForChild("Guard"))

local SELECT_RATE = 1 -- SelectFaction requests per second
local CHOICE_WINDOW = 180 -- seconds a recruiter's offer to choose stays valid
local SPAWN_FOLDER = "ProgressionSpawns"
local SPAWN_HEIGHT = 0.5
local FIRST_ROLL_DELAY = 1.2 -- seconds after arriving in the world before the free roll
local FIRST_ROLL_WAIT = 120 -- longest wait for the player to leave the intro; rolls anyway after

local FactionService = {}

local spawns: { [string]: SpawnLocation } = {}
local choiceArmed: { [Player]: number } = {}
local lastTransit: { [Player]: number } = {}

-- ── spawns ──

local function groundAt(x: number, z: number): number
	local hit = Ground.at(x, z)
	return if hit then hit.Y else 6
end

local function makeSpawns()
	local folder = workspace:FindFirstChild(SPAWN_FOLDER)
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = SPAWN_FOLDER
	folder.Parent = workspace
	for key, s in Npcs.SPAWNS do
		local y = groundAt(s.x, s.z)
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "Spawn_" .. key
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.Anchored = true
		spawn.CanCollide = false
		spawn.CanQuery = false
		spawn.CanTouch = false
		spawn.Transparency = 1
		spawn.Neutral = true
		spawn.Duration = 3
		local at = Vector3.new(s.x, y + SPAWN_HEIGHT, s.z)
		spawn.CFrame = CFrame.lookAt(at, at + s.look)
		spawn.Parent = folder
		spawns[key] = spawn
	end
end

local function homeOf(p: Profiles.Profile?): string
	if p and p.faction then
		return Factions.INFO[p.faction].region
	end
	return "Town"
end

function FactionService.spawnOf(key: string): SpawnLocation?
	return spawns[key]
end

-- where `player` respawns: their faction base, or the Gate Market when unaligned
function FactionService.homeSpawn(player: Player): SpawnLocation?
	return spawns[homeOf(Profiles.get(player))] or spawns.Town
end

-- Moves a player to a spawn (transit rides, quest skips).
function FactionService.travel(player: Player, key: string): boolean
	local spawn = spawns[key]
	local root = Regions.rootOf(player)
	if not spawn or not root then
		return false
	end
	local t = os.clock()
	local cooldown = Factions.TRANSIT_COOLDOWN * (1 - (Progress.effects(player).transit or 0))
	if lastTransit[player] and t - lastTransit[player] < cooldown then
		Sync.notify(player, "Toast", { text = "The ride isn't back yet.", color = "Red" })
		return false
	end
	lastTransit[player] = t
	local offset = Vector3.new(math.random(-3, 3), 3, math.random(-3, 3))
	local character = player.Character :: Model
	character:PivotTo(spawn.CFrame + offset)
	return true
end

-- ── marks and Relic gear on the character ──

function FactionService.dress(player: Player)
	local character = player.Character
	local p = Profiles.get(player)
	if not character or not p then
		return
	end
	Gear.mark(character, p.faction)
	local j = p.relic and Relics.get(p.relic.id)
	Gear.relic(character, if j then j.model else nil)
end

-- ── joining ──

function FactionService.armChoice(player: Player)
	choiceArmed[player] = os.clock()
end

function FactionService.join(player: Player, faction: string): string?
	local p = Profiles.get(player)
	if not p then
		return "Still loading."
	end
	if p.faction then
		return "You already belong to the " .. p.faction .. "."
	end
	if not Factions.INFO[faction] then
		return "Unknown faction."
	end
	-- still on the intro screen (no body yet), or a recruiter just offered the choice
	local onIntro = player.Character == nil
	local armed = choiceArmed[player]
	if not onIntro and (not armed or os.clock() - armed > CHOICE_WINDOW) then
		return "Talk to a recruiter at the Gate Market first."
	end
	choiceArmed[player] = nil
	p.faction = faction
	p.standing = 0
	player.RespawnLocation = spawns[Factions.INFO[faction].region]
	Sync.changed(player)
	FactionService.dress(player)
	Sync.notify(player, "Joined", { faction = faction, motto = Factions.INFO[faction].motto })
	Bus.emit(player, "Faction", { faction = faction })
	-- the free roll is revealed once the player is in the world, not behind the intro
	task.spawn(function()
		local waited = 0
		while not player.Character and player.Parent and waited < FIRST_ROLL_WAIT do
			waited += task.wait(0.25)
		end
		task.wait(FIRST_ROLL_DELAY)
		if not player.Parent then
			return
		end
		local err = Gacha.roll(player, true)
		if err then
			Sync.notify(player, "Toast", { text = err, color = "Red" })
		end
	end)
	return nil
end

-- ── rivalry ──

function FactionService.factionOf(player: Player): string?
	local p = Profiles.get(player)
	return if p then p.faction else nil
end

function FactionService.inSafeZone(player: Player): boolean
	local region = Regions.of(player)
	return region ~= nil and Factions.SAFE_REGIONS[region] == true
end

-- May `attacker`'s Relic moves hurt `victim`?
function FactionService.canHurt(attacker: Player, victim: Player): boolean
	if attacker == victim then
		return false
	end
	if FactionService.inSafeZone(attacker) or FactionService.inSafeZone(victim) then
		return false
	end
	local a, b = FactionService.factionOf(attacker), FactionService.factionOf(victim)
	if not Relic.PVP_SAME_FACTION and a ~= nil and a == b then
		return false
	end
	return true
end

function FactionService.start()
	makeSpawns()
	Remotes.get("SelectFaction").OnServerEvent:Connect(function(player, faction)
		if typeof(faction) ~= "string" or not Guard.allow(player, "SelectFaction", SELECT_RATE) then
			return
		end
		local err = FactionService.join(player, faction)
		if err then
			Sync.notify(player, "Toast", { text = err, color = "Red" })
		end
	end)
	Gacha.onEquip(function(player)
		FactionService.dress(player)
	end)
	local function watch(player: Player)
		-- set before the first spawn so new players land at the Gate Market
		player.RespawnLocation = spawns.Town
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Torso", 10)
			task.wait(0.3)
			FactionService.dress(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		choiceArmed[player] = nil
		lastTransit[player] = nil
	end)
	Profiles.onLoaded(function(player, p)
		player.RespawnLocation = spawns[homeOf(p)] or spawns.Town
		FactionService.dress(player)
	end)
end

return FactionService
