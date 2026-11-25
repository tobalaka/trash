--!strict
--[[
	Config.Economy - currencies, the Relic roll, the Blacksmith ladder, stores and trade rates.
	Mirrors the Constants tables in the vault notes Scrap-and-Anima, Gacha and Blacksmith.
	Every value is a PROPOSAL (2026-10-25) until tuned in play; change the note and this file
	together.
]]

local Economy = {}

-- what a new character starts with
Economy.START_DOLLARS = 60
Economy.START_ITEMS = { Ration = 2, Water = 2 }

-- ── Relic roll (Gacha) ──
-- The GDD gives 25% and 1%; with three Relics per faction those become Rare and Legendary and
-- Common takes the rest.
Economy.ROLL_ODDS = { Common = 74, Rare = 25, Legendary = 1 }
Economy.RARITY_ORDER = { "Common", "Rare", "Legendary" }
Economy.PITY_RARE = 10 -- the 10th roll in a row without Rare or better is at least Rare
Economy.PITY_LEGENDARY = 80 -- the 80th roll in a row without a Legendary is Legendary
Economy.SPIN_DOLLARS = 400 -- price of a roll in Dollars when you have no Relic Spin
Economy.FIRST_ROLL_FREE = true -- joining a faction rolls once for free

-- ── Blacksmith ladder: tier n unlocks `unlocks`; upgrades are sequential ──
export type Tier = {
	unlocks: string,
	level: number, -- character level needed
	rank: number, -- faction rank index needed (1 = first rank)
	scrap: number,
	residue: number,
	items: { [string]: number },
	faction: { [string]: { [string]: number } }?, -- extra items by faction
}
Economy.TIERS = {
	{ unlocks = "Z", level = 3, rank = 1, scrap = 60, residue = 0, items = { TinCan = 4, PlasticBottle = 4 } },
	{ unlocks = "X", level = 8, rank = 2, scrap = 180, residue = 5, items = { CopperWire = 5, RubberScrap = 4 } },
	{ unlocks = "C", level = 15, rank = 3, scrap = 420, residue = 15, items = { CircuitBoard = 3, GlassShard = 6, SmoglingCore = 2 } },
	{
		unlocks = "M1 Mastery",
		level = 22,
		rank = 4,
		scrap = 900,
		residue = 40,
		items = { CircuitBoard = 6, BeastCore = 1 },
		faction = { Menders = { PurifiedAnima = 2 }, Scrappers = { HotAlloy = 2 } },
	},
} :: { Tier }
Economy.MAX_TIER = 4
Economy.TIER_DAMAGE_BONUS = 0.04 -- Relic ability damage per upgrade tier (M1 damage belongs to combat)

-- ── stores (Dollars) ──
Economy.STORE = { Ration = 25, Skewer = 12, Water = 20, Bandage = 35, GasFilter = 80 }
Economy.FACTION_STORE_DISCOUNT = 0.1 -- your own faction's quartermaster
-- trade rates by faction: Menders sort better, Scrappers sell better
Economy.SORT_BONUS = { Menders = 0.25 }
Economy.SELL_BONUS = { Scrappers = 0.25 }

Economy.MAX_STACK = 999
Economy.MAX_BUY = 10 -- most of one thing per purchase

return Economy
