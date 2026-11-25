--!strict
-- Server entry point for progression: profiles, factions, the economy, survival, salvage,
-- pollution and Sky Dumps, Smoglings, Relic moves, quests and NPCs, titles, item drops,
-- bounties and the Turf War. Logic lives in the sibling
-- modules; this only starts them, profiles last so every system is listening before anyone loads.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ProgressionRemotes")).init()

local PAUSED_TEST_SYSTEMS = { Survival=true, RelicService=true, Smoglings=true, Beasts=true }
local function start(name: string)
	if workspace:GetAttribute("JoblessCombatTest") and PAUSED_TEST_SYSTEMS[name] then return end
	local ok, err = pcall(function()
		require(script.Parent:WaitForChild(name) :: ModuleScript).start()
	end)
	if not ok then
		warn("[Progression] " .. name .. " failed to start: " .. tostring(err))
	end
end

for _, name in {
	"Sync",
	"Inventory",
	"Titles",
	"Nameplate",
	"Progress",
	"Regions",
	"Pollution",
	"Survival",
	"Gacha",
	"FactionService",
	"Arrival",
	"Blacksmith",
	"StationService",
	"Ledger",
	"Drops",
	"Bounties",
	"Smoglings",
	"Beasts",
	"QuestService",
	"NpcService",
	"RelicService",
	"Admin",
} do
	start(name)
end
-- salvage registers ~850 piles over a few frames; Sky Dumps need it running
task.spawn(function()
	start("Salvage")
	start("SkyDumps")
	start("TurfWar")
end)
-- Scrap for breaking the map; waits for TRASH-Destruction's service
task.spawn(start, "Smash")
start("Profiles")
