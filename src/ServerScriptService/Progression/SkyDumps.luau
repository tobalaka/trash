--!strict
--[[
	SkyDumps - an export barge from a distant city empties its hold onto the dome (vault: Sky-Dumps). This is the
	Menders-vs-Scrappers flashpoint and the "raid" the GDD asks for, scaled to a 12-20 player
	server.

	Every DUMP_INTERVAL: a site is announced (clients see trash raining from the sky), then
	DUMP_PILES fresh piles land, pollution jumps, and a few Smoglings crawl out. For DUMP_CONTEST
	seconds the site is open: every pile processed there scores for the salvager's faction.
	When it closes, the faction with the most piles (at least DUMP_WIN_MIN) claims it:
	  - everyone of theirs who helped gets CONTEST_WIN rewards (and a small chance of a Stat Reset
	    Pill); everyone else who helped gets CONTEST_JOIN;
	  - the winning faction salvages CONTEST_BUFF more Scrap for CONTEST_BUFF_TIME.
	Piles left behind keep polluting the air until they rot away (DUMP_PILE_LIFETIME).
	State for the HUD: Workspace attributes DumpSite, DumpPos, DumpEnds, DumpScore_<Faction>.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Environment = require(Config:WaitForChild("Environment"))
local Factions = require(Config:WaitForChild("Factions"))
local Levels = require(Config:WaitForChild("Levels"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Pollution = require(script.Parent:WaitForChild("Pollution"))
local Salvage = require(script.Parent:WaitForChild("Salvage"))
local Smoglings = require(script.Parent:WaitForChild("Smoglings"))
local Ground = require(script.Parent:WaitForChild("Ground"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local WARNING = 8 -- seconds of falling trash before the piles land
local PLACE_TRIES = 12
local CLEARANCE = 3.5

-- Sites inside the dome (MapGen Town.plan: market plazas, the hilltop plaza, the outer ring road).
-- The Gate Market (south plaza) is the NPC hub and is left out.
local SITES = {
	{ id = "East", name = "the East Market", x = 1276, z = -1332.5 },
	{ id = "West", name = "the West Market", x = -174, z = -1332.5 },
	{ id = "North", name = "the North Market", x = 551, z = -2057.5 },
	{ id = "Hilltop", name = "the Hilltop Plaza", x = 461, z = -1482.5 },
	{ id = "RingNE", name = "the Northeast Ring", x = 975, z = -1757 },
	{ id = "RingNW", name = "the Northwest Ring", x = 127, z = -1757 },
	{ id = "RingSE", name = "the Southeast Ring", x = 975, z = -908 },
	{ id = "RingSW", name = "the Southwest Ring", x = 127, z = -908 },
}

type Contest = {
	site: string,
	name: string,
	position: Vector3,
	ends: number,
	scores: { [string]: number },
	helpers: { [Player]: string }, -- player -> the faction they scored for ("" = none)
	open: boolean,
}

local SkyDumps = {}

local rng = Random.new()
local current: Contest? = nil
local lastSite: string? = nil
local leftovers: { { model: Model, born: number } } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function fire(kind: string, data: { [string]: any })
	Remotes.get("WorldEvent"):FireAllClients(kind, data)
end

-- what a pile may land on top of: players, the crowd, NPC anchors, other piles, Smoglings
local function ignored(): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, name in { "SkyDumpPiles", "Smoglings", "Townsfolk", "NpcAnchors" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

-- a spot near the site with nothing standing on it
local function placeSpot(center: Vector3, ignore: { Instance }, taken: { Vector3 }): Vector3?
	for _ = 1, PLACE_TRIES do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(6, Environment.DUMP_RADIUS)
		local hit = Ground.at(center.X + math.cos(a) * r, center.Z + math.sin(a) * r, center.Y + 30)
		if hit and math.abs(hit.Y - center.Y) < 8 then
			local clear = Ground.clear(hit, Vector3.new(CLEARANCE * 2, 5, CLEARANCE * 2), ignore)
			local spaced = true
			for _, t in taken do
				if (t - hit).Magnitude < 7 then
					spaced = false
					break
				end
			end
			if clear and spaced then
				return hit
			end
		end
	end
	return nil
end

local function close()
	local c = current
	if not c or not c.open then
		return
	end
	c.open = false
	local winner: string? = nil
	local best = 0
	local tie = false
	for faction, score in c.scores do
		if score > best then
			winner, best, tie = faction, score, false
		elseif score == best then
			tie = true
		end
	end
	if tie or best < Environment.DUMP_WIN_MIN then
		winner = nil
	end
	for player, faction in c.helpers do
		if player.Parent and Profiles.get(player) then
			if winner and faction == winner then
				local W = Environment.CONTEST_WIN
				local items = if rng:NextNumber() < W.pillChance then { ResetPill = 1 } else nil
				Progress.grant(player, { standing = W.standing, residue = W.residue, exp = Levels.EXP.CONTEST_WIN, items = items }, "Claimed " .. c.name .. "!")
			else
				local J = Environment.CONTEST_JOIN
				Progress.grant(player, { standing = if faction ~= "" then J.standing else nil, residue = J.residue, exp = Levels.EXP.CONTEST_JOIN }, "Helped clear " .. c.name)
			end
		end
	end
	if winner then
		Salvage.setBuff(winner, Environment.CONTEST_BUFF_TIME)
	end
	workspace:SetAttribute("DumpEnds", nil)
	workspace:SetAttribute("DumpWinner", winner)
	fire("DumpClaimed", {
		site = c.site,
		name = c.name,
		winner = winner,
		scores = c.scores,
		buff = Environment.CONTEST_BUFF,
		buffTime = Environment.CONTEST_BUFF_TIME,
	})
end

local function drop()
	local options = {}
	for _, s in SITES do
		if s.id ~= lastSite then
			table.insert(options, s)
		end
	end
	local site = options[rng:NextInteger(1, #options)]
	lastSite = site.id
	local params = ignored()
	local center = Ground.at(site.x, site.z)
	if not center then
		return
	end
	workspace:SetAttribute("DumpSite", site.name)
	workspace:SetAttribute("DumpPos", center)
	workspace:SetAttribute("DumpWinner", nil)
	fire("DumpIncoming", { site = site.id, name = site.name, position = center, delay = WARNING })
	task.wait(WARNING)

	local contest: Contest = {
		site = site.id,
		name = site.name,
		position = center,
		ends = now() + Environment.DUMP_CONTEST,
		scores = {},
		helpers = {},
		open = true,
	}
	for _, f in Factions.LIST do
		contest.scores[f] = 0
		workspace:SetAttribute("DumpScore_" .. f, 0)
	end
	current = contest
	local taken: { Vector3 } = {}
	for i = 1, Environment.DUMP_PILES do
		local spot = placeSpot(center, params, taken)
		if spot then
			table.insert(taken, spot)
			local model = Salvage.buildHeap(spot, rng:NextInteger(1, 1e6))
			if Salvage.register(model, "Dump", site.id) then
				table.insert(leftovers, { model = model, born = os.clock() })
			end
		end
		if i % 3 == 0 then
			task.wait()
		end
	end
	Pollution.apply("Dump")
	workspace:SetAttribute("DumpEnds", contest.ends)
	fire("DumpLanded", { site = site.id, name = site.name, position = center, ends = contest.ends, piles = #taken })
	for i = 1, Environment.SMOGLING.PER_DUMP do
		local spot = taken[i * 2] or taken[i]
		if spot then
			Smoglings.spawn(spot + Vector3.new(2, 0, 2))
		end
	end
	task.delay(Environment.DUMP_CONTEST, function()
		if current == contest then
			close()
		end
	end)
end

function SkyDumps.current(): Contest?
	return current
end

function SkyDumps.start()
	Salvage.onSalvaged(function(player, pile, _method)
		local c = current
		if not c or not c.open or pile.site ~= c.site then
			return
		end
		local p = Profiles.get(player)
		local faction = if p and p.faction then p.faction else ""
		if faction ~= "" then
			c.scores[faction] = (c.scores[faction] or 0) + 1
			workspace:SetAttribute("DumpScore_" .. faction, c.scores[faction])
		end
		c.helpers[player] = faction
		Bus.emit(player, "Contest", { site = c.site, faction = faction })
		-- everything sorted early ends the claim early
		if #Salvage.pilesAt(c.site) == 0 then
			close()
		end
	end)
	-- leftover dump piles pollute until they rot away
	task.spawn(function()
		while true do
			task.wait(60)
			local t = os.clock()
			for i = #leftovers, 1, -1 do
				local l = leftovers[i]
				if not l.model.Parent then
					table.remove(leftovers, i)
				elseif t - l.born > Environment.DUMP_PILE_LIFETIME then
					l.model:Destroy()
					table.remove(leftovers, i)
				else
					Pollution.apply("DumpLeftover")
				end
			end
		end
	end)
	task.spawn(function()
		task.wait(Environment.DUMP_FIRST)
		while true do
			local ok, err = pcall(drop)
			if not ok then
				warn("[SkyDumps] " .. tostring(err))
			end
			workspace:SetAttribute("DumpNext", now() + Environment.DUMP_INTERVAL)
			task.wait(Environment.DUMP_INTERVAL)
		end
	end)
	workspace:SetAttribute("DumpNext", now() + Environment.DUMP_FIRST)
end

return SkyDumps
