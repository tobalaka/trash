--!strict
--[[
	NpcService - the people you talk to (vault: NPCs; content in Shared/Data/Npcs).

	The server places one invisible anchor per NPC (a solid collider so players don't walk through
	them, a Talk prompt and a name tag) in Workspace.NpcAnchors; every client builds and animates
	the body from Shared/Data/Npcs with the Townsfolk look kit.

	Talking: the prompt finishes any quest Talk step aimed at this NPC and turns in finished
	quests (QuestService.onTalk), then sends the dialogue: what they say and a list of choices
	(hand over quest items, new quests, quests locked by level, how a running quest is going,
	their stations, joining a faction, a ride, goodbye). Choices come back as
	DialogueChoice(npcId, optionId); the player must still be standing by the NPC.
	Rival-faction NPCs only tell you to leave.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))
local Npcs = require(Shared:WaitForChild("Data"):WaitForChild("Npcs"))
local Quests = require(Shared:WaitForChild("Data"):WaitForChild("Quests"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))
local FactionService = require(script.Parent:WaitForChild("FactionService"))
local Anchors = require(script.Parent:WaitForChild("Anchors"))
local Ground = require(script.Parent:WaitForChild("Ground"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Bounties = require(script.Parent:WaitForChild("Bounties"))
local TitleData = require(Shared:WaitForChild("Data"):WaitForChild("Titles"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local FOLDER = "NpcAnchors"
local TAG = "NpcAnchor"
local ANCHOR_SIZE = Vector3.new(2.4, 5.4, 1.6)
local NAME_OFFSET = 3.6
local NAME_DISTANCE = 70
local REACH = Npcs.TALK_DISTANCE * 1.8
local CHOICE_RATE = 6

local STATION_LABEL = {
	Store = "Buy supplies",
	Recycler = "Sort recyclables",
	Fence = "Sell items",
	Workbench = "Craft",
	Purifier = "Purify sludge",
	Smelter = "Smelt alloy",
	Blacksmith = "Upgrade my Relic",
	Bounties = "Check the Bounty Board",
}
local PLACE_NAME = { Town = "the Gate Market", MendersBase = "Menders Headquarters", ScrappersBase = "the Scrappers' Den" }
local RIVAL_LINES = {
	Menders = "Wrong side of the dome, Scrapper. Move along.",
	Scrappers = "Menders aren't welcome in the Den. Walk away while you can.",
}

local NpcService = {}

export type Option = { id: string, text: string, tag: string? }

-- ── placing anchors ──

-- things an NPC may stand in: players, other anchors, the crowd, spawns, dump piles, Smoglings
local function ignored(): { Instance }
	local list: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, name in { FOLDER, "Townsfolk", "ProgressionSpawns", "SkyDumpPiles", "Smoglings" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(list, f)
		end
	end
	return list
end

local function ground(x: number, z: number, _ignore: { Instance }): Vector3?
	return Ground.at(x, z)
end

local function roomAt(position: Vector3, ignore: { Instance }): boolean
	return Ground.clear(position, ANCHOR_SIZE * 0.9, ignore)
end

local function siteCFrame(npc: Npcs.Npc, params: { Instance }): CFrame?
	local site = npc.site
	if site.kind == "Plaza" then
		local c = Npcs.PLAZA_CENTER
		local base = ((site.slot or 1) - 0.5) / Npcs.PLAZA_SLOTS * 2 * math.pi
		for _, dr in { 0, -3, 3, -6 } do
			for _, da in { 0, 0.04, -0.04, 0.08 } do
				local a = base + da
				local r = Npcs.PLAZA_RADIUS + dr
				local at = ground(c.X + math.cos(a) * r, c.Z + math.sin(a) * r, params)
				if at and roomAt(at, params) then
					return CFrame.lookAt(at, Vector3.new(c.X, at.Y, c.Z))
				end
			end
		end
		return nil
	end
	local x, z = site.x :: number, site.z :: number
	local look = site.look or Vector3.new(0, 0, -1)
	for _, d in { Vector3.zero, Vector3.new(2, 0, 0), Vector3.new(-2, 0, 0), Vector3.new(0, 0, 2), Vector3.new(0, 0, -2), Vector3.new(4, 0, 0), Vector3.new(-4, 0, 0) } do
		local at = ground(x + d.X, z + d.Z, params)
		if at and roomAt(at, params) then
			return CFrame.lookAt(at, at + look)
		end
	end
	local at = ground(x, z, params)
	return if at then CFrame.lookAt(at, at + look) else nil
end

local function nameTag(anchor: BasePart, npc: Npcs.Npc)
	local gui = Instance.new("BillboardGui")
	gui.Name = "NameTag"
	gui.Size = UDim2.fromOffset(240, 46)
	gui.StudsOffset = Vector3.new(0, NAME_OFFSET, 0)
	gui.MaxDistance = NAME_DISTANCE
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local color = if npc.faction then Factions.INFO[npc.faction].color else Color3.fromRGB(238, 234, 224)
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0.58, 0)
	name.Text = npc.name
	name.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
	name.TextScaled = true
	name.TextColor3 = color
	name.TextStrokeTransparency = 0.4
	name.Parent = gui
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0, 0.58)
	title.Size = UDim2.new(1, 0, 0.42, 0)
	title.Text = npc.title
	title.FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(200, 196, 186)
	title.TextStrokeTransparency = 0.5
	title.Parent = gui
	gui.Parent = anchor
end

local function placeAll()
	local folder = workspace:FindFirstChild(FOLDER)
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = workspace
	local params = ignored()
	for _, npc in Npcs.list do
		local cf = siteCFrame(npc, params)
		if not cf then
			warn("[NpcService] no ground for " .. npc.id)
			continue
		end
		local anchor = Instance.new("Part")
		anchor.Name = npc.id
		anchor.Size = ANCHOR_SIZE
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = true
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.CFrame = cf + Vector3.new(0, ANCHOR_SIZE.Y / 2, 0)
		anchor:SetAttribute("NpcId", npc.id)
		anchor:SetAttribute("Ground", cf.Position.Y)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Talk"
		prompt.ActionText = "Talk"
		prompt.ObjectText = npc.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = Npcs.TALK_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = anchor
		nameTag(anchor, npc)
		anchor.Parent = folder
		CollectionService:AddTag(anchor, TAG)
		Anchors.set(npc.id, anchor)
		prompt.Triggered:Connect(function(player)
			NpcService.talk(player, npc.id)
		end)
	end
end

-- ── dialogue ──

local function send(player: Player, payload: { [string]: any }?)
	Remotes.get("Dialogue"):FireClient(player, payload)
end

local function pick(list: { string }): string
	return list[math.random(1, #list)]
end

local function rival(player: Player, npc: Npcs.Npc): boolean
	local mine = FactionService.factionOf(player)
	return npc.faction ~= nil and mine ~= nil and mine ~= npc.faction
end

local function menu(player: Player, npc: Npcs.Npc, lines: { string }): { [string]: any }
	local p = Profiles.get(player)
	local options: { Option } = {}
	if not p then
		return { npc = npc.id, lines = lines, options = { { id = "bye", text = "Goodbye" } } }
	end
	if rival(player, npc) then
		return {
			npc = npc.id,
			lines = { RIVAL_LINES[npc.faction :: string] or "Not you." },
			options = { { id = "bye", text = "Leave" } },
		}
	end
	for _, q in QuestService.deliverables(player, npc.id) do
		local state = p.quests.active[q.id]
		local step = state and q.steps[state.step]
		if step and step.target then
			local item = Items.get(step.target)
			table.insert(options, { id = "deliver:" .. q.id, text = string.format("Hand over %s x%d", if item then item.name else step.target, step.count or 1), tag = "Quest" })
		end
	end
	for _, q in QuestService.offersFrom(player, npc.id) do
		table.insert(options, { id = "offer:" .. q.id, text = q.title, tag = if q.kind == "Job" then "Job" elseif q.kind == "Side" then "Side" else "New" })
	end
	for _, q in Quests.list do
		if q.giver == npc.id and not q.autoStart then
			local level = QuestService.lockedByLevel(p, q)
			if level then
				table.insert(options, { id = "locked:" .. q.id, text = string.format("%s (reach level %d)", q.title, level), tag = "Locked" })
			end
		end
	end
	for _, q in QuestService.runningFrom(player, npc.id) do
		table.insert(options, { id = "progress:" .. q.id, text = "About \"" .. q.title .. "\"", tag = "Active" })
	end
	for _, kind in npc.stations or {} do
		table.insert(options, { id = "station:" .. kind, text = STATION_LABEL[kind] or kind, tag = "Trade" })
	end
	if npc.recruiter and not p.faction then
		table.insert(options, { id = "recruit", text = "Join the " .. npc.recruiter .. "...", tag = "Faction" })
	end
	if npc.transit and (npc.faction == nil or p.faction == nil or p.faction == npc.faction) then
		table.insert(options, { id = "travel", text = "Ride to " .. (PLACE_NAME[npc.transit] or npc.transit), tag = "Ride" })
	end
	table.insert(options, { id = "bye", text = "Goodbye" })
	return { npc = npc.id, lines = lines, options = options }
end

function NpcService.talk(player: Player, npcId: string)
	local npc = Npcs.byId[npcId]
	if not npc or not Profiles.get(player) then
		return
	end
	if not Anchors.near(player, npcId, REACH) then
		return
	end
	local lines: { string } = {}
	if not rival(player, npc) then
		for _, q in QuestService.onTalk(player, npcId) do
			for _, l in q.complete do
				table.insert(lines, l)
			end
		end
		Bus.emit(player, "Talk", { npc = npcId })
	end
	if #lines == 0 then
		local running = QuestService.runningFrom(player, npcId)
		local first = running[1]
		if first and first.progress and #first.progress > 0 then
			table.insert(lines, pick(first.progress))
		else
			table.insert(lines, pick(npc.greeting))
		end
	end
	send(player, menu(player, npc, lines))
end

local function choose(player: Player, npcId: string, optionId: string)
	local npc = Npcs.byId[npcId]
	if not npc or not Anchors.near(player, npcId, REACH) then
		send(player, nil)
		return
	end
	if rival(player, npc) then
		send(player, nil)
		return
	end
	local kind, arg = string.match(optionId, "^(%w+):?(.*)$")
	if kind == "bye" or not kind then
		send(player, nil)
	elseif kind == "offer" then
		local q = Quests.byId[arg]
		local p = Profiles.get(player)
		if not q or not p or q.giver ~= npcId or not QuestService.canTake(p, q) then
			send(player, menu(player, npc, { "Maybe another time." }))
			return
		end
		local rewards = {}
		local r = q.rewards
		if r.exp then
			table.insert(rewards, r.exp .. " EXP")
		end
		if r.dollars then
			table.insert(rewards, "$" .. r.dollars)
		end
		if r.scrap then
			table.insert(rewards, r.scrap .. " Scrap")
		end
		if r.residue then
			table.insert(rewards, r.residue .. " Residue")
		end
		if r.standing then
			table.insert(rewards, r.standing .. " standing")
		end
		for id, n in r.items or {} do
			local item = Items.get(id)
			table.insert(rewards, string.format("%s x%d", if item then item.name else id, n))
		end
		local title = r.title and TitleData.byId[r.title]
		if title then
			table.insert(rewards, "Title: " .. title.name)
		end
		send(player, {
			npc = npcId,
			lines = if #q.offer > 0 then q.offer else { q.summary },
			quest = { id = q.id, title = q.title, summary = q.summary, rewards = rewards, kind = q.kind },
			options = {
				{ id = "accept:" .. q.id, text = "I'll do it.", tag = "Accept" },
				{ id = "back", text = "Not now." },
			},
		})
	elseif kind == "accept" then
		local q = Quests.byId[arg]
		if not q or q.giver ~= npcId then
			send(player, nil)
			return
		end
		local err = QuestService.accept(player, arg)
		if err then
			Sync.notify(player, "Toast", { text = err, color = "Red" })
			send(player, menu(player, npc, { "Come back when you're ready." }))
		else
			send(player, menu(player, npc, { if q.progress and #q.progress > 0 then q.progress[1] else "Good luck." }))
		end
	elseif kind == "deliver" then
		local ok = QuestService.deliver(player, arg, npcId)
		local q = Quests.byId[arg]
		local lines = if ok and q then q.complete else { "You don't have it all yet." }
		send(player, menu(player, npc, lines))
	elseif kind == "progress" then
		local q = Quests.byId[arg]
		local p = Profiles.get(player)
		local state = p and p.quests.active[arg]
		local step = q and state and q.steps[state.step]
		local line = if q and q.progress and #q.progress > 0 then pick(q.progress) else "Keep at it."
		if step then
			line ..= "\n(" .. step.text .. ")"
		end
		send(player, menu(player, npc, { line }))
	elseif kind == "locked" then
		send(player, menu(player, npc, { "You're not ready for that yet. Get some more experience first." }))
	elseif kind == "station" then
		if not npc.stations or not table.find(npc.stations, arg) then
			send(player, nil)
			return
		end
		send(player, nil)
		if arg == "Bounties" then
			Bounties.open(player, npcId)
			return
		end
		local window = if arg == "Blacksmith" then "Blacksmith" else "Station"
		Remotes.get("OpenWindow"):FireClient(player, window, { npc = npcId, kind = arg, faction = npc.faction })
	elseif kind == "recruit" then
		local p = Profiles.get(player)
		if not npc.recruiter or not p or p.faction then
			send(player, nil)
			return
		end
		FactionService.armChoice(player)
		send(player, nil)
		Remotes.get("OpenWindow"):FireClient(player, "FactionSelect", { npc = npcId, suggested = npc.recruiter })
	elseif kind == "travel" then
		send(player, nil)
		if npc.transit then
			FactionService.travel(player, npc.transit)
		end
	elseif kind == "back" then
		send(player, menu(player, npc, { pick(npc.greeting) }))
	else
		send(player, nil)
	end
end

function NpcService.start()
	placeAll()
	Remotes.get("DialogueChoice").OnServerEvent:Connect(function(player, npcId, optionId)
		if typeof(npcId) ~= "string" or typeof(optionId) ~= "string" or not Guard.allow(player, "Dialogue", CHOICE_RATE) then
			return
		end
		choose(player, npcId, optionId)
	end)
	-- quest markers: which NPCs have something for this player (shown as ! and ? by the client)
	Sync.contribute(function(player, p, snap)
		local marks: { [string]: string } = {}
		for _, q in Quests.list do
			if not q.autoStart and QuestService.canTake(p, q) then
				marks[q.giver] = marks[q.giver] or "!"
			end
		end
		for id, state in p.quests.active do
			local q = Quests.byId[id]
			if q then
				local step = q.steps[state.step]
				local turnIn = q.turnIn or q.giver
				local talkTo = if step and step.type == "Talk" then QuestService.talkTarget(p, step) else nil
				if state.step > #q.steps and not q.auto then
					marks[turnIn] = "?"
				elseif talkTo then
					marks[talkTo] = "?"
				elseif step and step.type == "Deliver" then
					marks[turnIn] = marks[turnIn] or "…"
				end
			end
		end
		snap.marks = marks
	end)
end

return NpcService
