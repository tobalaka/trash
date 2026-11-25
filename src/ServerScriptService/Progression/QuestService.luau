--!strict
--[[
	QuestService - questlines, side quests and jobs (vault: Quests; content in Shared/Data/Quests).

	Steps run in order. Most advance from Bus events (salvaging, sorting, selling, crafting,
	processing, eating, defeating, visiting, upgrading, Sky Dump contests, joining, rolling). Two
	are checked against the player's state instead: Collect (carry N of an item) and Upgrade
	(Relic at tier N); those are re-checked whenever the profile changes. Talk and Deliver steps
	finish in the NPC dialogue (NpcService calls onTalk / deliver).

	A quest with all steps done completes on its own if `auto`, or when the player next talks to
	its turn-in NPC. Rewards go through Progress.grant; the quest's Field Note unlocks.
	Availability: faction, level, earlier quests, and the repeat timer for Jobs. New characters
	get the autoStart quest; joining a faction accepts that line's first quest.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Quests = require(Shared:WaitForChild("Data"):WaitForChild("Quests"))
local Npcs = require(Shared:WaitForChild("Data"):WaitForChild("Npcs"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local MAX_TRACKED = 3
local FIRST_OF_LINE = { Menders = "C1_Report", Scrappers = "R1_FreshMeat" }
local RECRUITER = "Recruiter" -- a Talk target meaning "your own faction's recruiter"

type Quest = Quests.Quest

local QuestService = {}

local function stepOf(quest: Quest, index: number): Quests.Step?
	return quest.steps[index]
end

-- the NPC a Talk step points at for this player ("Recruiter": the one of their own faction)
function QuestService.talkTarget(p: Profiles.Profile, step: Quests.Step): string?
	if step.target == RECRUITER then
		for _, npc in Npcs.list do
			if npc.recruiter ~= nil and npc.recruiter == p.faction then
				return npc.id
			end
		end
		return nil
	end
	return step.target
end

function QuestService.isDone(p: Profiles.Profile, id: string): boolean
	return p.quests.done[id] ~= nil
end

-- can `player` take `quest` right now?
function QuestService.canTake(p: Profiles.Profile, quest: Quest): boolean
	if p.quests.active[quest.id] then
		return false
	end
	local done = p.quests.done[quest.id]
	if done then
		if not quest.repeatable or os.time() - done < quest.repeatable then
			return false
		end
	end
	if quest.faction then
		if quest.faction == "Unaligned" then
			if p.faction then
				return false
			end
		elseif p.faction ~= quest.faction then
			return false
		end
	end
	local r = quest.requires
	if r then
		if r.level and p.level < r.level then
			return false
		end
		if r.faction and not p.faction then
			return false
		end
		for _, id in r.quests or {} do
			if not p.quests.done[id] then
				return false
			end
		end
	end
	return true
end

-- is it blocked only by level? (shown as "come back at level N" in dialogue)
function QuestService.lockedByLevel(p: Profiles.Profile, quest: Quest): number?
	local r = quest.requires
	if not r or not r.level or p.level >= r.level then
		return nil
	end
	local saved = r.level
	;(r :: any).level = nil
	local ok = QuestService.canTake(p, quest)
	;(r :: any).level = saved
	return if ok then saved else nil
end

function QuestService.offersFrom(player: Player, npcId: string): { Quest }
	local p = Profiles.get(player)
	local out = {}
	if not p then
		return out
	end
	for _, q in Quests.list do
		if q.giver == npcId and not q.autoStart and QuestService.canTake(p, q) then
			table.insert(out, q)
		end
	end
	return out
end

local function trackedCount(p: Profiles.Profile): number
	local n = 0
	for _, s in p.quests.active do
		if s.tracked then
			n += 1
		end
	end
	return n
end

local function complete(player: Player, quest: Quest)
	local p = Profiles.get(player)
	if not p or not p.quests.active[quest.id] then
		return
	end
	p.quests.active[quest.id] = nil
	p.quests.done[quest.id] = os.time()
	Progress.grant(player, quest.rewards, "Quest complete: " .. quest.title)
	Progress.unlockNote(player, quest.note)
	Sync.notify(player, "QuestComplete", { id = quest.id, title = quest.title })
	Sync.changed(player)
end

local function finished(quest: Quest, state: Profiles.QuestState): boolean
	return state.step > #quest.steps
end

-- state-based steps (Collect, Upgrade, Level), checked whenever things change
local function stateMet(player: Player, p: Profiles.Profile, step: Quests.Step): boolean
	if step.type == "Collect" and step.target then
		return Inventory.count(player, step.target) >= (step.count or 1)
	elseif step.type == "Upgrade" then
		return p.relic ~= nil and p.relic.tier >= (step.count or 1)
	elseif step.type == "Faction" then
		return p.faction ~= nil
	elseif step.type == "Air" then
		return workspace:GetAttribute("AirState") == (step.target or "Clear")
	elseif step.type == "Notes" then
		local have = 0
		for _ in p.notes do
			have += 1
		end
		return have >= (step.count or 1)
	end
	return false
end

-- moves past every step already satisfied; completes auto quests
local function settle(player: Player, quest: Quest)
	local p = Profiles.get(player)
	if not p then
		return
	end
	local state = p.quests.active[quest.id]
	if not state then
		return
	end
	local moved = false
	while true do
		local step = stepOf(quest, state.step)
		if not step then
			break
		end
		local count = step.count or 1
		if state.progress >= count or stateMet(player, p, step) then
			state.step += 1
			state.progress = 0
			moved = true
		else
			break
		end
	end
	if moved then
		local step = stepOf(quest, state.step)
		if step then
			Sync.notify(player, "QuestStep", { id = quest.id, title = quest.title, text = step.text })
		end
		Sync.changed(player)
	end
	if finished(quest, state) and quest.auto then
		complete(player, quest)
	end
end

function QuestService.accept(player: Player, id: string): string?
	local p = Profiles.get(player)
	local quest = Quests.byId[id]
	if not p or not quest then
		return "Unknown quest."
	end
	if not QuestService.canTake(p, quest) then
		return "You can't take that right now."
	end
	local active = 0
	for _ in p.quests.active do
		active += 1
	end
	if active >= Quests.MAX_ACTIVE then
		return "Your journal is full. Finish or abandon a quest first."
	end
	p.quests.active[id] = { step = 1, progress = 0, tracked = trackedCount(p) < MAX_TRACKED, started = os.time() }
	Sync.notify(player, "QuestAccepted", { id = id, title = quest.title })
	Sync.changed(player)
	settle(player, quest)
	return nil
end

-- adds `amount` to the current step of every active quest whose step matches
local function advance(player: Player, kind: string, matches: (Quests.Step) -> boolean, amount: number)
	local p = Profiles.get(player)
	if not p then
		return
	end
	for id, state in p.quests.active do
		local quest = Quests.byId[id]
		local step = quest and stepOf(quest, state.step)
		if quest and step and step.type == kind and matches(step) then
			state.progress += amount
			Sync.changed(player)
			settle(player, quest)
		end
	end
end

-- ── dialogue hooks (NpcService) ──

-- The player talked to `npcId`: finishes Talk steps aimed at them and turns in finished quests.
-- Returns the quests completed, so the dialogue can say their closing lines.
function QuestService.onTalk(player: Player, npcId: string): { Quest }
	local p = Profiles.get(player)
	local completed = {}
	if not p then
		return completed
	end
	local before: { string } = {}
	for id in p.quests.active do
		table.insert(before, id)
	end
	for _, id in before do
		local quest = Quests.byId[id]
		local state = p.quests.active[id]
		if quest and state then
			local step = stepOf(quest, state.step)
			if step and step.type == "Talk" and QuestService.talkTarget(p, step) == npcId then
				state.progress = step.count or 1
				settle(player, quest)
			end
		end
	end
	for _, id in before do
		local quest = Quests.byId[id]
		local state = p.quests.active[id]
		if quest and state and finished(quest, state) and (quest.turnIn or quest.giver) == npcId then
			complete(player, quest)
		end
	end
	-- everything that was active before this talk and is done now (turned in, or auto via Talk)
	for _, id in before do
		if not p.quests.active[id] and p.quests.done[id] then
			table.insert(completed, Quests.byId[id])
		end
	end
	return completed
end

-- active quests whose current step is a Deliver to this NPC that the player can pay
function QuestService.deliverables(player: Player, npcId: string): { Quest }
	local p = Profiles.get(player)
	local out = {}
	if not p then
		return out
	end
	for id, state in p.quests.active do
		local quest = Quests.byId[id]
		local step = quest and stepOf(quest, state.step)
		if quest and step and step.type == "Deliver" and (quest.turnIn or quest.giver) == npcId and step.target then
			if Inventory.count(player, step.target) >= (step.count or 1) then
				table.insert(out, quest)
			end
		end
	end
	return out
end

function QuestService.deliver(player: Player, id: string, npcId: string): boolean
	local p = Profiles.get(player)
	local quest = Quests.byId[id]
	local state = p and p.quests.active[id]
	if not p or not quest or not state or (quest.turnIn or quest.giver) ~= npcId then
		return false
	end
	local step = stepOf(quest, state.step)
	if not step or step.type ~= "Deliver" or not step.target then
		return false
	end
	if not Inventory.take(player, step.target, step.count or 1) then
		return false
	end
	state.progress = step.count or 1
	settle(player, quest)
	if finished(quest, state) then
		complete(player, quest)
	end
	return true
end

-- quests this NPC gave that are still running (for "how's it going" lines)
function QuestService.runningFrom(player: Player, npcId: string): { Quest }
	local p = Profiles.get(player)
	local out = {}
	if not p then
		return out
	end
	for id in p.quests.active do
		local quest = Quests.byId[id]
		if quest and (quest.giver == npcId or quest.turnIn == npcId) then
			table.insert(out, quest)
		end
	end
	return out
end

function QuestService.start()
	-- Talk steps finish through onTalk (the dialogue), not the Bus
	Bus.on("Salvage", function(player, e)
		advance(player, "Salvage", function(s)
			return s.target == nil or s.target == e.region
		end, 1)
	end)
	Bus.on("Recycle", function(player, e)
		advance(player, "Recycle", function()
			return true
		end, e.count or 1)
	end)
	Bus.on("Sell", function(player, e)
		advance(player, "Sell", function()
			return true
		end, e.count or 1)
	end)
	Bus.on("Craft", function(player, e)
		advance(player, "Craft", function(s)
			return s.target == nil or s.target == e.recipe
		end, e.count or 1)
	end)
	Bus.on("Process", function(player, e)
		advance(player, "Process", function(s)
			return s.target == nil or s.target == e.recipe
		end, 1)
	end)
	Bus.on("Consume", function(player, e)
		advance(player, "Consume", function(s)
			return (s.target == "Food" and e.food) or (s.target == "Water" and e.water) or s.target == e.item
		end, 1)
	end)
	Bus.on("Defeat", function(player, e)
		advance(player, "Defeat", function(s)
			return s.target == e.kind
		end, 1)
	end)
	Bus.on("Visit", function(player, e)
		advance(player, "Visit", function(s)
			return s.target == e.region
		end, 1)
	end)
	Bus.on("Contest", function(player)
		advance(player, "Contest", function()
			return true
		end, 1)
	end)
	Bus.on("Smash", function(player, e)
		advance(player, "Smash", function()
			return true
		end, e.parts or 1)
	end)
	Bus.on("Turf", function(player, e)
		if e.won then
			advance(player, "Turf", function()
				return true
			end, 1)
		end
	end)
	Bus.on("Bounty", function(player, e)
		if e.wanted then
			advance(player, "Bounty", function()
				return true
			end, 1)
		end
	end)
	-- "Air" steps finish while the whole server's air is clear: re-check when it changes
	workspace:GetAttributeChangedSignal("AirState"):Connect(function()
		for _, player in game:GetService("Players"):GetPlayers() do
			local p = Profiles.get(player)
			if p then
				for id in p.quests.active do
					local quest = Quests.byId[id]
					if quest then
						task.defer(settle, player, quest)
					end
				end
			end
		end
	end)
	Bus.on("Roll", function(player)
		advance(player, "Roll", function()
			return true
		end, 1)
	end)
	Bus.on("Faction", function(player, e)
		local p = Profiles.get(player)
		if not p then
			return
		end
		-- joining finishes any "join a faction" step, even if earlier talk steps were skipped
		local ids = {}
		for id in p.quests.active do
			table.insert(ids, id)
		end
		for _, id in ids do
			local quest = Quests.byId[id]
			local state = p.quests.active[id]
			if quest and state then
				for index, step in quest.steps do
					if step.type == "Faction" and state.step <= index then
						state.step = index + 1
						state.progress = 0
					end
				end
				settle(player, quest)
				if finished(quest, state) and p.quests.active[id] then
					complete(player, quest)
				end
			end
		end
		local first = FIRST_OF_LINE[e.faction]
		if first then
			QuestService.accept(player, first)
		end
	end)
	-- state-based steps re-checked with every snapshot; also tells the client which quests are open
	Sync.contribute(function(player, p, snap)
		for id in p.quests.active do
			local quest = Quests.byId[id]
			if quest then
				task.defer(settle, player, quest)
			end
		end
		local available = {}
		for _, q in Quests.list do
			if not q.autoStart and QuestService.canTake(p, q) then
				local giver = Npcs.byId[q.giver]
				table.insert(available, { id = q.id, giver = q.giver, giverName = if giver then giver.name else q.giver })
			end
		end
		snap.available = available
	end)
	Profiles.onLoaded(function(player, p)
		for _, q in Quests.list do
			if q.autoStart and not p.quests.done[q.id] and not p.quests.active[q.id] then
				QuestService.accept(player, q.id)
			end
		end
	end)
	Remotes.get("TrackQuest").OnServerEvent:Connect(function(player, id)
		if typeof(id) ~= "string" or not Guard.allow(player, "TrackQuest", 5) then
			return
		end
		local p = Profiles.get(player)
		local state = p and p.quests.active[id]
		if p and state then
			if not state.tracked and trackedCount(p) >= MAX_TRACKED then
				for _, s in p.quests.active do
					s.tracked = false
				end
			end
			state.tracked = not state.tracked
			Sync.changed(player)
		end
	end)
	Remotes.get("AbandonQuest").OnServerEvent:Connect(function(player, id)
		if typeof(id) ~= "string" or not Guard.allow(player, "AbandonQuest", 2) then
			return
		end
		local p = Profiles.get(player)
		local quest = Quests.byId[id]
		if p and quest and p.quests.active[id] and not quest.autoStart then
			p.quests.active[id] = nil
			Sync.changed(player)
			Sync.notify(player, "Toast", { text = "Abandoned " .. quest.title, color = "Red" })
		end
	end)
end

return QuestService
