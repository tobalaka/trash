--!strict
--[[
	Titles - names a player has earned, and the one they wear (vault: Titles; list in
	Shared/Data/Titles). Earned titles live in the profile's flags (`titles`: id -> time,
	`title`: the worn id). Wearing one sets the player attributes Title and TitleColor, which
	Nameplate draws over their head.

	Grants come from quest rewards and level rewards (Progress.grant), caps (top rank, every
	Field Note) and stat milestones: Titles.bump(player, stat, n) counts profile.stats and grants
	whatever Titles.MILESTONES says that count earns. A newly earned title is worn at once if the
	player wears none.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local TitleData = require(Shared:WaitForChild("Data"):WaitForChild("Titles"))
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Guard = require(script.Parent:WaitForChild("Guard"))

local EQUIP_RATE = 2
local NEUTRAL = Color3.fromRGB(238, 234, 224)

local Titles = {}

local function owned(p: Profiles.Profile): { [string]: number }
	local t = p.flags.titles
	if typeof(t) ~= "table" then
		t = {}
		p.flags.titles = t
	end
	return t
end

function Titles.has(player: Player, id: string): boolean
	local p = Profiles.get(player)
	return p ~= nil and owned(p)[id] ~= nil
end

-- shows the worn title on the player (attributes read by Nameplate and the HUD)
local function publish(player: Player)
	local p = Profiles.get(player)
	local id = p and p.flags.title
	local t = if typeof(id) == "string" then TitleData.byId[id] else nil
	if t and p then
		local info = if p.faction then Factions.INFO[p.faction] else nil
		player:SetAttribute("Title", t.name)
		player:SetAttribute("TitleColor", t.color or (if info then info.color else NEUTRAL))
	else
		player:SetAttribute("Title", nil)
		player:SetAttribute("TitleColor", nil)
	end
end
Titles.publish = publish

-- Gives `player` the title `id` (once). Returns true if it was new.
function Titles.grant(player: Player, id: string?): boolean
	local p = Profiles.get(player)
	local t = if id then TitleData.byId[id] else nil
	if not p or not t then
		return false
	end
	local list = owned(p)
	if list[t.id] then
		return false
	end
	list[t.id] = os.time()
	if typeof(p.flags.title) ~= "string" then
		p.flags.title = t.id
		publish(player)
	end
	Sync.notify(player, "Title", { id = t.id, name = t.name, how = t.how })
	Sync.changed(player)
	return true
end

-- Adds `n` to a profile stat and grants any milestone title that count reaches.
function Titles.bump(player: Player, stat: string, n: number?)
	local p = Profiles.get(player)
	if not p then
		return
	end
	local before = p.stats[stat] or 0
	local after = before + (n or 1)
	p.stats[stat] = after
	Profiles.markDirty(player)
	local milestones = TitleData.MILESTONES[stat]
	if milestones then
		for count, id in milestones do
			if before < count and after >= count then
				Titles.grant(player, id)
			end
		end
	end
end

function Titles.equip(player: Player, id: string)
	local p = Profiles.get(player)
	if not p then
		return
	end
	if id == "" then
		p.flags.title = nil
	elseif owned(p)[id] and TitleData.byId[id] then
		p.flags.title = id
	else
		return
	end
	publish(player)
	Sync.changed(player)
end

function Titles.start()
	Remotes.get("EquipTitle").OnServerEvent:Connect(function(player, id)
		if typeof(id) == "string" and #id <= 40 and Guard.allow(player, "EquipTitle", EQUIP_RATE) then
			Titles.equip(player, id)
		end
	end)
	Sync.contribute(function(_player, p, snap)
		snap.titles = owned(p)
		snap.title = if typeof(p.flags.title) == "string" then p.flags.title else nil
	end)
	Profiles.onLoaded(function(player)
		publish(player)
	end)
	-- the colour follows the faction (joining changes it)
	local function watch(player: Player)
		player:GetAttributeChangedSignal("Faction"):Connect(function()
			publish(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return Titles
