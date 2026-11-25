--!strict
--[[
	Bounties - hunting rivals in the neutral Slums (vault: Bounties; GDD Faction Systems:
	"Slums Bounty Hunting"). Tuning in Config.Factions.

	  - Claiming: defeating a rival-faction player outside both bases pays
	    BOUNTY_DOLLARS + their heat x BOUNTY_PER_HEAT + whatever other players posted on them, plus
	    EXP and standing. A claim on a Wanted player pays more EXP and standing. The loser drops
	    their faction mark as a trophy (Mender's Pin / Scrapper's Tag) for the winner.
	  - Heat: every claim adds 1 heat to the winner (max HEAT_MAX), losing it again over time.
	    Being taken down resets your heat. At WANTED_HEAT or more you are Wanted: everyone sees
	    "WANTED · $X" over your head and the server is told.
	  - Posting: someone who defeated you in the last BOUNTY_POST_WINDOW can be given a price at
	    the Bounty Board (Clerk Odo). The Dollars go into a pot the next claimer takes; unclaimed
	    pots go back to the posters after BOUNTY_POT_EXPIRY or when the target leaves (posters
	    who have left by then lose their share).
	  - Fair play: no payout for victims below BOUNTY_MIN_LEVEL, and the same winner and loser
	    pay out once per BOUNTY_FARM_COOLDOWN. Same-faction defeats never pay.
	Nameplate draws the price from the Wanted / WantedLevel attributes set here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local F = require(Config:WaitForChild("Factions"))
local Levels = require(Config:WaitForChild("Levels"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local FactionService = require(script.Parent:WaitForChild("FactionService"))
local Regions = require(script.Parent:WaitForChild("Regions"))
local Ledger = require(script.Parent:WaitForChild("Ledger"))
local Anchors = require(script.Parent:WaitForChild("Anchors"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Titles = require(script.Parent:WaitForChild("Titles"))
local Drops = require(script.Parent:WaitForChild("Drops"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local BOARD_NPC = "Odo"
local BOARD_REACH = 18
local POST_RATE = 2
local REFRESH = 2 -- seconds between heat / price updates

type Post = { amount: number, at: number }

local Bounties = {}

local heat: { [Player]: { value: number, at: number } } = {}
local pots: { [Player]: { [Player]: Post } } = {} -- target -> poster -> post
local beatenBy: { [Player]: { [Player]: number } } = {} -- loser -> winner -> time
local paidAt: { [Player]: { [Player]: number } } = {} -- winner -> loser -> time
local wasWanted: { [Player]: boolean } = {}

function Bounties.heatOf(player: Player): number
	local h = heat[player]
	if not h then
		return 0
	end
	return math.max(0, h.value - (os.clock() - h.at) / F.HEAT_DECAY)
end

local function potOf(target: Player): number
	local total = 0
	for _, post in pots[target] or {} do
		total += post.amount
	end
	return total
end

-- what claiming `target` would pay right now
function Bounties.valueOf(target: Player): number
	return F.BOUNTY_DOLLARS + math.floor(Bounties.heatOf(target)) * F.BOUNTY_PER_HEAT + potOf(target)
end

local function publish(player: Player)
	local h = Bounties.heatOf(player)
	local level = math.floor(h)
	local priced = level > 0 or potOf(player) > 0
	player:SetAttribute("Heat", level)
	player:SetAttribute("WantedLevel", if level > 0 then level else nil)
	player:SetAttribute("Wanted", if priced then Bounties.valueOf(player) else nil)
	local wanted = level >= F.WANTED_HEAT
	if wanted and not wasWanted[player] then
		Remotes.get("WorldEvent"):FireAllClients("Wanted", { name = player.DisplayName, faction = FactionService.factionOf(player), value = Bounties.valueOf(player) })
	end
	wasWanted[player] = wanted
end

local function refund(target: Player)
	local list = pots[target]
	pots[target] = nil
	for poster, post in list or {} do
		if poster.Parent then
			Inventory.earn(poster, { dollars = post.amount })
			Sync.notify(poster, "Toast", { text = string.format("Your $%d bounty on %s was returned.", post.amount, target.DisplayName), color = "Gold" })
		end
	end
end

local function claim(winner: Player, loser: Player)
	local wf, lf = FactionService.factionOf(winner), FactionService.factionOf(loser)
	beatenBy[loser] = beatenBy[loser] or {}
	;(beatenBy[loser] :: any)[winner] = os.clock()
	if not wf or not lf or wf == lf or FactionService.inSafeZone(loser) then
		return
	end
	local lp = Profiles.get(loser)
	if not lp or lp.level < F.BOUNTY_MIN_LEVEL then
		Sync.notify(winner, "Toast", { text = "No bounty on newcomers.", color = "TextDim" })
		return
	end
	local last = paidAt[winner] and (paidAt[winner] :: any)[loser]
	if last and os.clock() - last < F.BOUNTY_FARM_COOLDOWN then
		Sync.notify(winner, "Toast", { text = "You already collected on them. Find someone else.", color = "TextDim" })
		return
	end
	paidAt[winner] = paidAt[winner] or {}
	;(paidAt[winner] :: any)[loser] = os.clock()

	local loserHeat = Bounties.heatOf(loser)
	local wanted = loserHeat >= F.WANTED_HEAT
	local purse = Bounties.valueOf(loser)
	local pot = potOf(loser)
	pots[loser] = nil -- the claimer takes the posted money
	heat[loser] = nil
	Progress.grant(winner, {
		dollars = purse,
		standing = if wanted then F.STANDING.WANTED_BOUNTY else F.STANDING.BOUNTY,
		exp = if wanted then Levels.EXP.WANTED_BOUNTY else Levels.EXP.BOUNTY,
	}, (if wanted then "Wanted bounty: " else "Bounty: ") .. loser.DisplayName)
	heat[winner] = { value = math.min(F.HEAT_MAX, Bounties.heatOf(winner) + 1), at = os.clock() }
	if Bounties.heatOf(winner) >= F.HEAT_MAX - 0.01 then
		Titles.grant(winner, "MostWanted")
	end
	Titles.bump(winner, "bounties", 1)
	-- the loser's mark falls for the winner
	local trophy = F.TROPHY[lf]
	local root = Regions.rootOf(loser)
	if trophy and root then
		Drops.spawn(root.Position, { [trophy] = 1 }, { winner })
	end
	Sync.notify(loser, "Toast", { text = string.format("%s claimed $%d on you.", winner.DisplayName, purse), color = "Red" })
	if wanted or pot > 0 then
		Remotes.get("WorldEvent"):FireAllClients("BountyClaimed", { winner = winner.DisplayName, loser = loser.DisplayName, value = purse, faction = wf })
	end
	Bus.emit(winner, "Defeat", { kind = "Rival", victim = loser })
	if wanted then
		Bus.emit(winner, "Bounty", { wanted = true })
	end
	publish(winner)
	publish(loser)
end

-- the Bounty Board window's contents for `player`
local function board(player: Player): { [string]: any }
	local list = {}
	for _, other in Players:GetPlayers() do
		local h = math.floor(Bounties.heatOf(other))
		local pot = potOf(other)
		if h > 0 or pot > 0 then
			table.insert(list, {
				userId = other.UserId,
				name = other.DisplayName,
				faction = FactionService.factionOf(other),
				heat = h,
				wanted = h >= F.WANTED_HEAT,
				value = Bounties.valueOf(other),
				posted = pot,
				region = Regions.of(other),
				me = other == player,
			})
		end
	end
	table.sort(list, function(a, b)
		return a.value > b.value
	end)
	local postable = {}
	for winner, at in beatenBy[player] or {} do
		local left = F.BOUNTY_POST_WINDOW - (os.clock() - at)
		if winner.Parent and left > 0 then
			local mine = pots[winner] and (pots[winner] :: any)[player]
			table.insert(postable, {
				userId = winner.UserId,
				name = winner.DisplayName,
				faction = FactionService.factionOf(winner),
				posted = if mine then mine.amount else 0,
				left = math.floor(left),
			})
		end
	end
	local p = Profiles.get(player)
	return {
		list = list,
		postable = postable,
		amounts = F.BOUNTY_POST_AMOUNTS,
		max = F.BOUNTY_POST_MAX,
		mine = {
			heat = math.floor(Bounties.heatOf(player)),
			value = Bounties.valueOf(player),
			claims = if p then p.stats.bounties or 0 else 0,
			wantedAt = F.WANTED_HEAT,
		},
	}
end

function Bounties.open(player: Player, npcId: string?)
	Remotes.get("OpenWindow"):FireClient(player, "Bounties", { npc = npcId or BOARD_NPC, board = board(player) })
end

local function post(player: Player, targetId: number, amount: number)
	if not Anchors.near(player, BOARD_NPC, BOARD_REACH) then
		return "Post bounties at the Bounty Board (Clerk Odo)."
	end
	if not table.find(F.BOUNTY_POST_AMOUNTS, amount) then
		return "Pick one of the board's amounts."
	end
	local target = Players:GetPlayerByUserId(targetId)
	local beaten = target and beatenBy[player] and (beatenBy[player] :: any)[target]
	if not target or not beaten or os.clock() - beaten > F.BOUNTY_POST_WINDOW then
		return "You can only post on someone who beat you in the last few minutes."
	end
	pots[target] = pots[target] or {}
	local mine = (pots[target] :: any)[player] :: Post?
	local already = if mine then mine.amount else 0
	if already + amount > F.BOUNTY_POST_MAX then
		return string.format("You can post at most $%d on one player.", F.BOUNTY_POST_MAX)
	end
	if not Inventory.spend(player, { dollars = amount }) then
		return "You don't have that many Dollars."
	end
	;(pots[target] :: any)[player] = { amount = already + amount, at = os.clock() }
	Sync.changed(player)
	publish(target)
	Sync.notify(player, "Toast", { text = string.format("Posted $%d on %s.", amount, target.DisplayName), color = "Gold" })
	Sync.notify(target, "Toast", { text = string.format("%s put $%d on your head.", player.DisplayName, amount), color = "Red" })
	Bounties.open(player)
	return nil
end

function Bounties.start()
	-- a player character died: credit the top damager (Ledger)
	Ledger.onDeath(function(victim, killer)
		local loser = Players:GetPlayerFromCharacter(victim)
		if loser and killer and killer ~= loser then
			claim(killer, loser)
		end
	end)
	Remotes.get("PostBounty").OnServerEvent:Connect(function(player, targetId, amount)
		if typeof(targetId) ~= "number" or typeof(amount) ~= "number" or not Guard.allow(player, "PostBounty", POST_RATE) then
			return
		end
		local err = post(player, targetId, amount)
		if err then
			Sync.notify(player, "Toast", { text = err, color = "Red" })
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- a target who leaves: the posters get their money back. A poster who leaves keeps their
		-- post on the board (it still pays the claimer); if it then expires, it is gone.
		refund(player)
		heat[player] = nil
		beatenBy[player] = nil
		paidAt[player] = nil
		wasWanted[player] = nil
		for _, list in beatenBy do
			list[player] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(REFRESH)
			local t = os.clock()
			for target, list in pots do
				for poster, p in list do
					if t - p.at > F.BOUNTY_POT_EXPIRY then
						list[poster] = nil
						if poster.Parent then
							Inventory.earn(poster, { dollars = p.amount })
							Sync.notify(poster, "Toast", { text = string.format("Your $%d bounty on %s expired and was returned.", p.amount, target.DisplayName), color = "Gold" })
						end
					end
				end
			end
			for _, player in Players:GetPlayers() do
				publish(player)
			end
		end
	end)
end

return Bounties
