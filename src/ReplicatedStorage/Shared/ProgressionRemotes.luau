--!strict
--[[
	ProgressionRemotes - the progression RemoteEvents (vault: 04-Architecture/Remotes). The server
	creates them under ReplicatedStorage.ProgressionRemotes; clients wait for them. Every client
	request is validated and rate limited on the server; clients never send amounts.

	C -> S
	  RequestSync     ()                                   send me my profile snapshot
	  SelectFaction   faction: string                      first time only: on the intro, or after a recruiter
	  Play            ()                                   the intro's PLAY: spawn me (needs a side; once)
	  EquipTitle      titleId: string ("" = none)          wear an earned title
	  PostBounty      targetUserId, amount                 at the Bounty Board, on someone who beat you
	  RollRelic       ()                                   spend a Relic Spin (or Dollars) on a roll
	  RollChoice      keepNew: boolean                     keep the rolled Relic or the current one
	  UpgradeRelic    ()                                   at your faction's Blacksmith
	  UseItem         itemId: string                       eat, drink, bandage, respirator
	  StationAction   npcId, action, id, qty               Buy / Sort / Sell / Craft at an NPC's station
	  DialogueChoice  npcId, optionId                      a button in the dialogue window
	  TrackQuest      questId                              pin a quest on the tracker
	  AbandonQuest    questId
	  InvestPerk      pathId                               buy the next perk on a skill path
	  UseResetPill    ()                                   refund every skill point
	  AbilityRequest  key: string, direction: Vector3, stamp: number   Relic moves Z X C R B
	S -> C
	  ProfileSync     snapshot table                       inventory, quests, notes, perks, Relic...
	  Notify          kind: string, data: table            toasts, rewards, level and rank ups
	  Dialogue        payload table | nil                  open / update / close the dialogue
	  OpenWindow      name: string, data: table            station, blacksmith, faction select, bounty board
	  RollResult      data table                           a roll to reveal
	  RelicFx         caster: Model, relic: string, key: string, data: table   move effects for everyone
	  WorldEvent      kind: string, data: table            Sky Dumps, contest results, Turf War, Wanted players
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionRemotes = {}

ProgressionRemotes.NAMES = {
	"RequestSync",
	"SelectFaction",
	"RollRelic",
	"RollChoice",
	"UpgradeRelic",
	"UseItem",
	"StationAction",
	"DialogueChoice",
	"TrackQuest",
	"AbandonQuest",
	"InvestPerk",
	"UseResetPill",
	"AbilityRequest",
	"Play",
	"EquipTitle",
	"PostBounty",
	"AdminRequest",
	"AdminResult",
	"ProfileSync",
	"Notify",
	"Dialogue",
	"OpenWindow",
	"RollResult",
	"RelicFx",
	"WorldEvent",
}

local FOLDER = "ProgressionRemotes"

function ProgressionRemotes.init()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER
		folder.Parent = ReplicatedStorage
	end
	for _, name in ProgressionRemotes.NAMES do
		if not (folder :: Instance):FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function ProgressionRemotes.get(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(FOLDER):WaitForChild(name) :: RemoteEvent
end

return ProgressionRemotes
