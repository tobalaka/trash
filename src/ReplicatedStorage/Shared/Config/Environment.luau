--!strict
--[[
	Config.Environment - the server's pollution, salvage piles, Sky Dumps, Smoglings and the Junk
	Ram's rewards (vault: 02-Systems/Environment/Pollution, Salvage, Sky-Dumps). Values are
	PROPOSALS (2026-10-25).

	Pollution (0-100, one value per server) is the environmental heart of the loop. The export barges
	keep dumping, so it creeps up on its own and jumps with every Sky Dump. Salvaging junk brings
	it down; sorting brings it down most, stripping least; purifying sludge cleans the air while
	smelting it dirties it. High pollution means smog: Hunger and Thirst drain faster and more
	Smoglings crawl out of the junk. Low pollution means clear skies: every pile gives more.
]]

local Environment = {}

-- ── pollution ──
Environment.POLLUTION_START = 50
Environment.POLLUTION_MIN = 0
Environment.POLLUTION_MAX = 100
Environment.POLLUTION_DRIFT = 0.4 -- per minute: the barges never stop dumping
Environment.POLLUTION_HIGH = 70 -- smog at or above
Environment.POLLUTION_LOW = 30 -- clear skies at or below
Environment.CLEAR_SKIES_YIELD = 0.2 -- extra salvage under clear skies
Environment.DELTA = {
	Sort = -0.4,
	Salvage = -0.25,
	Strip = -0.12,
	Purify = -1.5,
	Smelt = 1.5,
	Smogling = -0.3,
	JunkRam = -3,
	Dump = 6,
	DumpLeftover = 0.03, -- per uncleared dump pile per minute
	Smash = 0.05, -- per part of the map broken (dust and wrecked material), any cause
}
Environment.SMASH_POLLUTION_PER_MINUTE = 2 -- server-wide cap on smog from breaking the map

-- ── salvage ──
Environment.HOLD = { Sort = 3.0, Salvage = 2.5, Strip = 1.8 } -- seconds to hold the prompt
Environment.PROMPT_DISTANCE = 9
Environment.PILE_RESPAWN = 240 -- a world pile comes back after this
Environment.WASTELAND_BONUS = 0.25 -- extra loot in the Wastezone (best materials, worst air)

-- How each method changes a pile's yield: item chances, Scrap, Dollars, standing.
Environment.METHOD = {
	Sort = { items = 1.0, scrap = 1.0, dollars = { 0, 0 } },
	Salvage = { items = 0.8, scrap = 1.0, dollars = { 0, 0 } },
	Strip = { items = 0.6, scrap = 1.3, dollars = { 3, 6 } },
}

export type Loot = { item: string, chance: number, min: number, max: number }
export type Pile = { scrap: { number }, residue: number?, loot: { Loot } }
local function l(item: string, chance: number, min: number?, max: number?): Loot
	return { item = item, chance = chance, min = min or 1, max = max or min or 1 }
end

-- loot by pile kind (prop names map to kinds in Environment.PROP_KINDS)
Environment.PILES = {
	Bags = { scrap = { 2, 5 }, loot = { l("PlasticBottle", 0.8, 1, 2), l("ClothRag", 0.6, 1, 2), l("TinCan", 0.4), l("DirtyWater", 0.15), l("Skewer", 0.08) } },
	Scrap = { scrap = { 6, 10 }, loot = { l("TinCan", 0.6, 1, 2), l("GlassShard", 0.35), l("CopperWire", 0.15) } },
	Tyre = { scrap = { 3, 5 }, loot = { l("RubberScrap", 0.9, 1, 2), l("GlassShard", 0.1) } },
	Washer = { scrap = { 6, 9 }, loot = { l("CopperWire", 0.6, 1, 2), l("CircuitBoard", 0.18), l("GlassShard", 0.3) } },
	Drum = { scrap = { 4, 7 }, loot = { l("TinCan", 0.4), l("ToxicSludge", 0.25), l("DirtyWater", 0.2) } },
	Antenna = { scrap = { 5, 8 }, loot = { l("CopperWire", 0.7, 1, 2), l("CircuitBoard", 0.25) } },
	Sign = { scrap = { 6, 9 }, loot = { l("TinCan", 0.5, 1, 2), l("CopperWire", 0.1) } },
	Sofa = { scrap = { 2, 4 }, loot = { l("ClothRag", 0.85, 1, 3), l("CopperWire", 0.1), l("PlasticBottle", 0.3) } },
	Dump = {
		scrap = { 8, 14 },
		residue = 0.3,
		loot = {
			l("PlasticBottle", 0.7, 1, 2),
			l("TinCan", 0.5),
			l("ClothRag", 0.4),
			l("GlassShard", 0.35),
			l("CopperWire", 0.3),
			l("RubberScrap", 0.25),
			l("CircuitBoard", 0.12),
			l("Ration", 0.08),
		},
	},
} :: { [string]: Pile }

-- world props that become piles: prop name -> pile kind. Folders searched: Environment.PILE_FOLDERS
Environment.PROP_KINDS = {
	BagsA = "Bags",
	BagsB = "Bags",
	SacksA = "Bags",
	SacksB = "Bags",
	ScrapA = "Scrap",
	ScrapB = "Scrap",
	TyreA = "Tyre",
	TyreB = "Tyre",
	TyreC = "Tyre",
	WasherA = "Washer",
	WasherB = "Washer",
	DrumA = "Drum",
	DrumB = "Drum",
	DrumC = "Drum",
	AntennaA = "Antenna",
	SignA = "Sign",
	SignB = "Sign",
	SofaA = "Sofa",
	SofaB = "Sofa",
}
Environment.PILE_FOLDERS = { { "World", "Town", "Props" }, { "World", "Wasteland", "Junk" } }

-- ── Sky Dumps: an export barge drops a load of foreign trash on a site; both factions race to claim it ──
Environment.DUMP_FIRST = 150 -- seconds after the server starts
Environment.DUMP_INTERVAL = 600
Environment.DUMP_PILES = 10
Environment.DUMP_RADIUS = 30 -- piles land within this of the site
Environment.DUMP_CONTEST = 300 -- seconds the claim is open
Environment.DUMP_WIN_MIN = 3 -- piles a faction must process to claim the site
Environment.DUMP_PILE_LIFETIME = 900 -- uncleared dump piles rot away after this
Environment.CONTEST_BUFF = 0.2 -- the winning faction's extra Scrap from salvage...
Environment.CONTEST_BUFF_TIME = 600 -- ...for this long
Environment.CONTEST_WIN = { standing = 40, residue = 6, pillChance = 0.08 }
Environment.CONTEST_JOIN = { standing = 12, residue = 2 }

-- ── Smoglings: small Pollution Beasts that crawl out of uncleared junk ──
Environment.SMOGLING = {
	MAX = 16, -- per server (raised 2026-10-26: the outer biomes spawn them too)
	SPAWN_INTERVAL = 20,
	PER_DUMP = 3, -- spawned with each Sky Dump
	HEALTH = 70,
	DAMAGE = 9,
	POSTURE = 10,
	SPEED = 13,
	AGGRO = 45,
	LEASH = 90,
	RANGE = 6,
	WINDUP = 0.45,
	COOLDOWN = 2.2,
	KNOCKBACK = 18,
	STUN = 0.4,
	DESPAWN = 120, -- seconds with no player within AGGRO * 3
	SCRAP = { 4, 8 },
	RESIDUE_CHANCE = 0.45,
	-- weight of ambient spawns when polluted; the outer biomes have no junk piles, so Smoglings
	-- there crawl out of the open ground near a player (GDD: standard variants in the middle
	-- region and the outer biomes)
	REGIONS = { TownDome = 0.6, Town = 0.4, Wasteland = 1, Desert = 0.3, Jungle = 0.35, Winter = 0.3 },
	OPEN_GROUND = { Desert = true, Jungle = true, Winter = true },
}

-- Apex Smoglings: the GDD's "scariest, high-level variants strictly confined to the Wastezone"
Environment.APEX = {
	CHANCE = 0.35, -- of a Wastezone spawn
	SCALE = 1.7,
	HEALTH = 240,
	DAMAGE = 16,
	POSTURE = 18,
	SPEED = 15,
	AGGRO = 60,
	KNOCKBACK = 30,
	COOLDOWN = 1.9,
	SCRAP = { 12, 20 },
	RESIDUE = { 2, 4 },
}

-- ── Junk Ram (ServerScriptService/Mobs): shared reward for everyone who fought it ──
Environment.JUNKRAM_REWARD = {
	radius = 220, -- players this close when it dies count as having fought
	minDamageShare = 0.02,
	scrap = { 60, 90 },
	residue = { 10, 16 },
	items = { BeastCore = 1 },
}

return Environment
