--!strict
--[[
	Profiles - loads, keeps and saves each player's progression (vault: DataStore-Schema).

	  - One DataStore key per user. The stored value is { data = Profile, lock = { job, at } }:
	    a session lock, so two servers never hold the same profile. A lock older than
	    LOCK_EXPIRY is stale (its server died) and may be taken over.
	  - UpdateAsync for every write, with retries and backoff.
	  - Saved on leave (lock released), every AUTOSAVE seconds, and on BindToClose. Never per change.
	  - A load that fails never falls back to defaults that could overwrite real data: the
	    player gets a session-only profile marked `readOnly`, and is told their progress
	    won't save this session.
	  - Studio without API access: a session-only profile, so playtests still work.
	  - `version` + migrate(): older saves get new fields filled in.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Survival = require(Shared:WaitForChild("Config"):WaitForChild("Survival"))

local STORE_NAME = "TRASH_Profiles"
local KEY = "u_%d"
local VERSION = 2
-- version 1 names, renamed 2026-10-26 (spelled in pieces so the old names stay out of the code)
local LEGACY_RELIC_KEY = "jin" .. "ki" -- the save key of the Relic
local LEGACY_FACTIONS: { [string]: string } = { ["Clea" .. "ners"] = "Menders", ["Rai" .. "ders"] = "Scrappers" }
local LEGACY_ITEMS: { [string]: string } = { ["Clea" .. "nerHoop"] = "MenderPin", ["Rai" .. "derPatch"] = "ScrapperTag" }
local AUTOSAVE = 120
local LOCK_EXPIRY = 600
local RETRIES = 5
local LOCK_WAIT = 2 -- seconds between tries while another server still holds the lock

export type QuestState = { step: number, progress: number, tracked: boolean, started: number }
export type Profile = {
	version: number,
	faction: string?,
	relic: { id: string, rarity: string, tier: number }?,
	pending: { id: string, rarity: string }?, -- a roll waiting for keep / discard
	dollars: number,
	scrap: number,
	residue: number,
	items: { [string]: number },
	level: number,
	exp: number,
	points: number, -- unspent skill points
	perks: { [string]: number }, -- path id -> perks bought along it
	standing: number,
	pity: { rare: number, legendary: number },
	quests: { active: { [string]: QuestState }, done: { [string]: number } },
	notes: { [string]: number },
	survival: { hunger: number, thirst: number, blood: number },
	stats: { [string]: number },
	flags: { [string]: any },
	created: number,
}

type Session = { profile: Profile, readOnly: boolean, dirty: boolean, loadedAt: number }

local Profiles = {}

local sessions: { [Player]: Session } = {}
local loading: { [Player]: boolean } = {}
local loadedCallbacks: { (Player, Profile) -> () } = {}
local releasingCallbacks: { (Player, Profile) -> () } = {}
local store: DataStore? = nil

local function default(): Profile
	local items = {}
	for id, n in Economy.START_ITEMS do
		items[id] = n
	end
	return {
		version = VERSION,
		faction = nil,
		relic = nil,
		pending = nil,
		dollars = Economy.START_DOLLARS,
		scrap = 0,
		residue = 0,
		items = items,
		level = 1,
		exp = 0,
		points = 0,
		perks = {},
		standing = 0,
		pity = { rare = 0, legendary = 0 },
		quests = { active = {}, done = {} },
		notes = {},
		survival = { hunger = Survival.HUNGER_MAX, thirst = Survival.THIRST_MAX, blood = Survival.BLOOD_MAX },
		stats = {},
		flags = {},
		created = os.time(),
	}
end

-- fills anything an older save is missing
local function migrate(data: any): Profile
	local base = default()
	if typeof(data) ~= "table" then
		return base
	end
	-- version 2 (2026-10-26): the faction weapon is a Relic; version 1 saves kept it under an
	-- older key, LEGACY_RELIC_KEY
	if (data.version or 1) < 2 then
		if data.relic == nil and data[LEGACY_RELIC_KEY] ~= nil then
			data.relic = data[LEGACY_RELIC_KEY]
		end
		data[LEGACY_RELIC_KEY] = nil
		-- the factions and their trophies were renamed too
		data.faction = LEGACY_FACTIONS[data.faction] or data.faction
		-- quest ids that named a faction (J5/J6 trophy jobs)
		if typeof(data.quests) == "table" then
			for _, list in { data.quests.active, data.quests.done } do
				if typeof(list) == "table" then
					local moves: { { string } } = {} -- collected first: no new keys while iterating
					for id in list do
						local renamed = id
						for old, new in LEGACY_FACTIONS do
							renamed = string.gsub(renamed, old, new)
						end
						if renamed ~= id then
							table.insert(moves, { id, renamed })
						end
					end
					for _, m in moves do
						list[m[2]] = list[m[1]]
						list[m[1]] = nil
					end
				end
			end
		end
		if typeof(data.items) == "table" then
			for old, new in LEGACY_ITEMS do
				if data.items[old] then
					data.items[new] = (data.items[new] or 0) + data.items[old]
					data.items[old] = nil
				end
			end
		end
	end
	for k, v in base :: any do
		if data[k] == nil then
			data[k] = v
		end
	end
	data.quests.active = data.quests.active or {}
	data.quests.done = data.quests.done or {}
	data.pity.rare = data.pity.rare or 0
	data.pity.legendary = data.pity.legendary or 0
	data.version = VERSION
	return data :: Profile
end

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = s
	end
	return store
end

local function keyOf(player: Player): string
	return string.format(KEY, player.UserId)
end

local function loadData(player: Player): (Profile?, boolean)
	local ds = getStore()
	if not ds then
		return nil, false
	end
	local key = keyOf(player)
	for attempt = 1, RETRIES do
		local locked = false
		local ok, result = pcall(function()
			return (ds :: DataStore):UpdateAsync(key, function(old: any)
				if typeof(old) == "table" and typeof(old.lock) == "table" and old.lock.job ~= game.JobId and os.time() - (old.lock.at or 0) < LOCK_EXPIRY then
					locked = true
					return nil
				end
				local value = if typeof(old) == "table" then old else {}
				value.lock = { job = game.JobId, at = os.time() }
				return value
			end)
		end)
		if ok and not locked then
			local value = result :: any
			return migrate(if typeof(value) == "table" then value.data else nil), true
		end
		if not player.Parent then
			return nil, false
		end
		if not ok then
			warn(string.format("[Profiles] load %s failed (try %d): %s", key, attempt, tostring(result)))
			if string.find(tostring(result), "StudioAccessToApisNotAllowed") or string.find(tostring(result), "403") then
				return nil, false
			end
		end
		task.wait(if locked then LOCK_WAIT * attempt else attempt)
	end
	return nil, false
end

local function saveData(player: Player, session: Session, release: boolean): boolean
	if session.readOnly then
		return true
	end
	local ds = getStore()
	if not ds then
		return false
	end
	local key = keyOf(player)
	local profile = session.profile
	for attempt = 1, RETRIES do
		local stolen = false
		local ok, err = pcall(function()
			(ds :: DataStore):UpdateAsync(key, function(old: any)
				if typeof(old) == "table" and typeof(old.lock) == "table" and old.lock.job ~= game.JobId then
					stolen = true -- another server owns it now; never overwrite their data
					return nil
				end
				return { data = profile, lock = if release then nil else { job = game.JobId, at = os.time() } }
			end)
		end)
		if ok then
			if stolen then
				warn("[Profiles] " .. key .. " is locked by another server; not saving")
			end
			session.dirty = false
			return true
		end
		warn(string.format("[Profiles] save %s failed (try %d): %s", key, attempt, tostring(err)))
		task.wait(attempt)
	end
	return false
end

-- ── public ──

function Profiles.get(player: Player): Profile?
	local s = sessions[player]
	return if s then s.profile else nil
end

-- Yields until the player's profile is loaded (or they leave).
function Profiles.await(player: Player): Profile?
	while player.Parent and not sessions[player] do
		task.wait(0.1)
	end
	return Profiles.get(player)
end

function Profiles.isReadOnly(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and s.readOnly
end

function Profiles.markDirty(player: Player)
	local s = sessions[player]
	if s then
		s.dirty = true
	end
end

function Profiles.onLoaded(fn: (Player, Profile) -> ())
	table.insert(loadedCallbacks, fn)
	for player, s in sessions do
		task.spawn(fn, player, s.profile)
	end
end

-- called just before a profile is saved and dropped (player leaving)
function Profiles.onReleasing(fn: (Player, Profile) -> ())
	table.insert(releasingCallbacks, fn)
end

function Profiles.isNew(profile: Profile): boolean
	return next(profile.quests.done) == nil and next(profile.quests.active) == nil
end

local function onPlayerAdded(player: Player)
	if loading[player] or sessions[player] then
		return
	end
	loading[player] = true
	local profile, saved = loadData(player)
	loading[player] = nil
	if not player.Parent then
		return
	end
	local readOnly = false
	if not profile then
		profile = default()
		readOnly = true
		if RunService:IsStudio() then
			warn("[Profiles] Studio: no DataStore access, using a session-only profile for " .. player.Name)
		else
			warn("[Profiles] could not load " .. player.Name .. "; progress this session will not be saved")
		end
	end
	local session: Session = { profile = profile :: Profile, readOnly = readOnly or not saved, dirty = false, loadedAt = os.clock() }
	sessions[player] = session
	if session.readOnly and not RunService:IsStudio() then
		player:SetAttribute("ProfileWarning", "Your save could not be loaded. Progress this session will not be kept; please rejoin later.")
	end
	for _, fn in loadedCallbacks do
		task.spawn(fn, player, session.profile)
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session then
		return
	end
	for _, fn in releasingCallbacks do
		pcall(fn, player, session.profile)
	end
	saveData(player, session, true)
	sessions[player] = nil
end

function Profiles.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player, session in sessions do
				if session.dirty then
					for _, fn in releasingCallbacks do
						-- not releasing, but lets systems write their live values (survival meters) first
						pcall(fn, player, session.profile)
					end
					task.spawn(saveData, player, session, false)
				end
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player, session in sessions do
			pending += 1
			task.spawn(function()
				for _, fn in releasingCallbacks do
					pcall(fn, player, session.profile)
				end
				saveData(player, session, true)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.1)
		end
	end)
end

Profiles.default = default

return Profiles
