--!strict
--[[
	Config.Drops - loot that falls into the world as pickups (vault: Item-Drops). Currencies
	(Scrap, Residue, Dollars) still go straight to the wallet; items drop as little part-built
	bundles you walk up to and pick up (E). For OWNER_TIME only the players a drop belongs to can
	take it, then anyone can. Values are PROPOSALS (2026-10-26).
]]

export type Roll = { item: string, chance: number, min: number?, max: number? }

local Drops = {}

Drops.OWNER_TIME = 12 -- seconds only the owners can pick a drop up
Drops.LIFETIME = 90 -- seconds before an unclaimed drop crumbles
Drops.PICKUP_RANGE = 10 -- studs (checked on the server)
Drops.MAX = 80 -- drops in the world at once; the oldest go first
Drops.SCATTER = 4 -- studs drops spread from where they fell
Drops.PICKUP_RATE = 8 -- pickups per second per player (Guard)

-- a Smogling breaking apart (the top damager owns the drop)
Drops.SMOGLING = {
	{ item = "ToxicSludge", chance = 0.6 },
	{ item = "SmoglingCore", chance = 0.12 },
	{ item = "PlasticBottle", chance = 0.25 },
	{ item = "GlassShard", chance = 0.15 },
} :: { Roll }

-- an Apex Smogling (Wastezone)
Drops.APEX = {
	{ item = "ToxicSludge", chance = 0.85, min = 1, max = 2 },
	{ item = "SmoglingCore", chance = 0.6, min = 1, max = 2 },
	{ item = "ApexCore", chance = 0.3 },
	{ item = "CircuitBoard", chance = 0.35 },
	{ item = "SpinToken", chance = 0.02 },
} :: { Roll }

-- the Junk Ram bursts into a shower of junk: everyone who fought it owns it, then anyone
Drops.JUNKRAM_SHOWER = { 7, 11 } -- how many pickups
Drops.JUNKRAM_POOL = { "TinCan", "CopperWire", "CircuitBoard", "RubberScrap", "GlassShard", "PlasticBottle", "ApexCore" }

-- breaking the map (TRASH-Destruction): each broken part may shake loose what it was made of
Drops.SMASH_CHANCE = 0.05 -- per broken part, for the player who broke it
Drops.SMASH_MAX = 2 -- drops per blast at most
Drops.SMASH_MATERIAL = {
	Metal = "TinCan",
	DiamondPlate = "TinCan",
	CorrodedMetal = "CopperWire",
	Glass = "GlassShard",
	Neon = "GlassShard",
	Fabric = "ClothRag",
	Plastic = "PlasticBottle",
	SmoothPlastic = "PlasticBottle",
	Rubber = "RubberScrap",
	Foil = "TinCan",
} :: { [string]: string }

return Drops
