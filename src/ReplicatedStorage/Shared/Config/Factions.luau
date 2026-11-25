--!strict
--[[
	Config.Factions - Menders and Scrappers: identity, ranks, how each one salvages, standing
	sources, bounties and safe zones. Mirrors the vault notes Menders, Scrappers, Faction-Selection
	and Faction-Standing. Values are PROPOSALS (2026-10-25).

	The dynamic: both factions live off the trash that richer cities export to the Heap, and both upcycle it.
	Menders SORT it (slow, every material recovered, the air gets cleaner, better recycling
	rates). Scrappers STRIP it (fast, more Scrap and cash, fewer materials, less of the mess cleaned,
	better Fence prices). Both race to claim each Sky Dump, and the server's pollution moves with
	how the Heap handles its waste.
]]

local rgb = Color3.fromRGB

export type Rank = { name: string, standing: number }
export type Info = {
	name: string,
	color: Color3,
	motto: string,
	ideology: string,
	method: string, -- the salvage verb: Sort | Strip
	methodDesc: string,
	identifier: string, -- Pin | Tag
	identifierDesc: string,
	region: string, -- MapRegionVolumes key of the base (a safe zone)
	ranks: { Rank },
}

local Factions = {}

Factions.LIST = { "Menders", "Scrappers" }
Factions.UNALIGNED = "Unaligned"
Factions.UNALIGNED_RANK = "Drifter"
Factions.UNALIGNED_METHOD = "Salvage"

Factions.INFO = {
	Menders = {
		name = "Menders",
		color = rgb(96, 204, 188),
		motto = "Sort it. Save it. Share it.",
		ideology = "Organise the Heap and protect it by repurposing waste. Every bottle sorted is one the barges can't bury us under.",
		method = "Sort",
		methodDesc = "You SORT junk piles: slower, but you recover every material, the air gets cleaner, and recycling stations pay you 25% more Scrap.",
		identifier = "Pin",
		identifierDesc = "A teal pin pressed from a bottle cap, worn on the chest.",
		region = "MendersBase",
		ranks = {
			{ name = "Recruit", standing = 0 },
			{ name = "Sweeper", standing = 150 },
			{ name = "Sorter", standing = 450 },
			{ name = "Warden", standing = 1000 },
			{ name = "Vanguard", standing = 2000 },
			{ name = "Steward", standing = 3500 },
		},
	},
	Scrappers = {
		name = "Scrappers",
		color = rgb(160, 96, 220),
		motto = "Take it before the smog does.",
		ideology = "Scarcity rules the Heap, so grab what you can and hold your turf. Nobody out there is coming to save you.",
		method = "Strip",
		methodDesc = "You STRIP junk piles: fast, with more Scrap and some cash, but fewer materials and less of the mess cleaned up. Fences pay you 25% more Dollars.",
		identifier = "Tag",
		identifierDesc = "A purple-painted scrap-metal tag stamped with a crew number, worn on a cord.",
		region = "ScrappersBase",
		ranks = {
			{ name = "Stray", standing = 0 },
			{ name = "Scavenger", standing = 150 },
			{ name = "Runner", standing = 450 },
			{ name = "Enforcer", standing = 1000 },
			{ name = "Lieutenant", standing = 2000 },
			{ name = "Boss", standing = 3500 },
		},
	},
} :: { [string]: Info }

-- rewards for reaching rank n (index into ranks)
Factions.RANK_REWARDS = {
	[2] = { dollars = 150 },
	[3] = { dollars = 250, items = { SpinToken = 1 } },
	[4] = { dollars = 400, items = { ResetPill = 1 } },
	[5] = { dollars = 600, items = { SpinToken = 1 } },
	[6] = { dollars = 1000, items = { SpinToken = 2 } },
} :: { [number]: { dollars: number?, items: { [string]: number }? } }

-- standing earned per action
Factions.STANDING = {
	SALVAGE = 1, -- each pile sorted or stripped
	PURIFY = 5,
	SMELT = 5,
	SMOGLING = 2,
	APEX = 6,
	CONTEST_WIN = 40,
	CONTEST_JOIN = 12,
	BOUNTY = 15,
	WANTED_BOUNTY = 40,
	TURF_WIN = 60,
	TURF_JOIN = 20,
	REVIVE = 5,
	TROPHY = 12, -- handing a rival's mark to your quartermaster
}

-- bounties (vault: Bounties): defeating a rival-faction player outside the safe zones pays
-- BOUNTY_DOLLARS + their heat x BOUNTY_PER_HEAT + whatever other players posted on them.
Factions.BOUNTY_DOLLARS = 40
Factions.BOUNTY_PER_HEAT = 30 -- extra Dollars per point of the victim's heat
Factions.HEAT_DECAY = 300 -- seconds per point of heat lost
Factions.HEAT_MAX = 5
Factions.WANTED_HEAT = 3 -- at or above: Wanted, marked over their head for everyone
Factions.BOUNTY_MIN_LEVEL = 5 -- defeating someone below this level pays nothing (protects newcomers)
Factions.BOUNTY_FARM_COOLDOWN = 300 -- the same winner and loser pay out once per this many seconds
Factions.BOUNTY_POST_AMOUNTS = { 50, 100, 250 } -- Dollars a player can add to a bounty at once
Factions.BOUNTY_POST_MAX = 1000 -- most one player can have posted on one target
Factions.BOUNTY_POST_WINDOW = 600 -- seconds after being defeated that you may post on the winner
Factions.BOUNTY_POT_EXPIRY = 1800 -- unclaimed posted Dollars go back to the posters after this
Factions.TROPHY = { Menders = "MenderPin", Scrappers = "ScrapperTag" } -- what a defeated rival drops

-- faction bases are safe zones: Relic moves don't hurt players there
Factions.SAFE_REGIONS = { MendersBase = true, ScrappersBase = true }
Factions.TRANSIT_COOLDOWN = 20 -- seconds between rides from a recruiter or quartermaster

function Factions.rankIndex(faction: string?, standing: number): number
	local info = if faction then Factions.INFO[faction] else nil
	if not info then
		return 0
	end
	local index = 1
	for i, r in info.ranks do
		if standing >= r.standing then
			index = i
		end
	end
	return index
end

function Factions.rankName(faction: string?, standing: number): string
	local info = if faction then Factions.INFO[faction] else nil
	if not info then
		return Factions.UNALIGNED_RANK
	end
	return info.ranks[Factions.rankIndex(faction, standing)].name
end

return Factions
