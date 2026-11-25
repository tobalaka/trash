--!strict
--[[
	MockData - placeholder content for the UI while the server systems (inventory, skill trees,
	shop, gacha) are not built yet, and for the edit-mode preview.

	None of this is game data: prices, odds and move names are display placeholders. Real values
	come from the server Config modules once the matching vault specs stop being OPEN. Windows
	that still show mock content carry a "preview" marker tag.
]]

local MockData = {}

-- The preview character (edit mode only; live play reads the player's attributes).
MockData.player = {
	DisplayName = "Tinker",
	Level = 12,
	Rank = "Scavenger",
	Faction = "Scrappers",
	Relic = "Umbrella",
	RelicRarity = "Rare",
	UpgradeTier = 2,
	Health = 82,
	MaxHealth = 100,
	Hunger = 72,
	Thirst = 46,
	Blood = 88,
	Posture = 34,
	Anima = 64,
	Dollars = 1240,
	Scrap = 386,
	AnimaResidue = 42,
}

export type Item = {
	id: string,
	name: string,
	qty: number?,
	rarity: string,
	desc: string,
	model: string?,
}

local items: { [string]: Item } = {
	Ration = { id = "Ration", name = "Ration Tin", rarity = "Common", desc = "Sealed beans from an export bale. Restores Hunger.", model = "Ration" },
	Water = { id = "Water", name = "Clean Water", rarity = "Common", desc = "Filtered, not just boiled. Restores Thirst.", model = "Water" },
	Canteen = { id = "Canteen", name = "Canteen", rarity = "Uncommon", desc = "Holds three drinks. Refill it at any clean pump.", model = "Canteen" },
	Bandage = { id = "Bandage", name = "Bandage Roll", rarity = "Common", desc = "Stops Vitality loss for a while.", model = "Bandage" },
	Filter = { id = "Filter", name = "Gas Filter", rarity = "Rare", desc = "Lets you breathe in the Wastezone for two minutes.", model = "Filter" },
	ScrapBundle = { id = "ScrapBundle", name = "Scrap Bundle", rarity = "Common", desc = "Tied-up junk. The Blacksmith turns it into upgrades.", model = "ScrapBundle" },
	Residue = { id = "Residue", name = "Anima Residue", rarity = "Rare", desc = "What a fight leaves in the air. Still warm.", model = "Residue" },
	Pill = { id = "Pill", name = "Stat Reset Pill", rarity = "Epic", desc = "Refunds every skill point you have spent.", model = "Pill" },
	Gloves = { id = "Gloves", name = "Work Gloves", rarity = "Common", desc = "Grip for climbing junk piles.", model = "Gloves" },
	Mask = { id = "Mask", name = "Gas Mask", rarity = "Uncommon", desc = "Needs a filter to work.", model = "Mask" },
	Tag = { id = "Tag", name = "Scrapper Tag", rarity = "Uncommon", desc = "A stamped scrap tag on a cord. Marks you as a Scrapper.", model = "Tag" },
	Umbrella = { id = "Umbrella", name = "Umbrella", rarity = "Rare", desc = "A Relic. Opens into a shield, closes into a spear.", model = "Umbrella" },
	Sandals = { id = "Sandals", name = "Sandals", rarity = "Uncommon", desc = "A Relic. Every step lands like a kick.", model = "Sandals" },
}
MockData.items = items

local function stack(id: string, qty: number): Item
	local base = items[id]
	return { id = base.id, name = base.name, rarity = base.rarity, desc = base.desc, model = base.model, qty = qty }
end

export type Group = { label: string, items: { Item } }
export type Section = { title: string, groups: { Group } }

MockData.inventory = {
	{
		title = "Supplies",
		groups = {
			{ label = "Food", items = { stack("Ration", 3) } },
			{ label = "Water", items = { stack("Water", 2), stack("Canteen", 1) } },
			{ label = "Medical", items = { stack("Bandage", 4), stack("Filter", 1) } },
		},
	},
	{
		title = "Materials",
		groups = {
			{ label = "Upcycling", items = { stack("ScrapBundle", 12), stack("Residue", 3) } },
			{ label = "Consumables", items = { stack("Pill", 1) } },
		},
	},
	{
		title = "Gear",
		groups = {
			{ label = "Outfit", items = { stack("Gloves", 1), stack("Mask", 1), stack("Tag", 1) } },
		},
	},
	{
		title = "Relic",
		groups = {
			{ label = "Bound", items = { stack("Umbrella", 1) } },
		},
	},
} :: { Section }

-- Hotbar preview (slot index -> item id). Live play mirrors the Backpack instead.
MockData.hotbar = { "Umbrella", "Ration", "Water", "Bandage", "Canteen", "Filter" }
MockData.equippedSlot = 1

-- Relic ability names per Relic, keyed by ability key. Placeholders until the Relic specs exist.
MockData.abilities = {
	Umbrella = { Z = "Canopy Guard", X = "Spoke Lunge", C = "Gale Spin", R = "Shelter", B = "Downpour" },
	Sandals = { Z = "Heel Snap", X = "Sole Dash", C = "Stomp Line", R = "Tread", B = "Ground Shaker" },
}
-- Preview cooldowns (seconds remaining).
MockData.cooldowns = { X = 4, Parry = 0.6, Uppercut = 3.4 }

export type Move = { name: string, learned: boolean, desc: string }
export type Path = { id: string, title: string, points: number, moves: { Move } }

local function moves(list: { string }, learned: number, desc: string): { Move }
	local out = {}
	for i, n in list do
		table.insert(out, { name = n, learned = i <= learned, desc = desc })
	end
	return out
end

MockData.paths = {
	{
		id = "MartialArts",
		title = "Martial Arts",
		points = 12,
		moves = moves({
			"Gutter Stomp", "Scrap Toss", "Shoulder Check", "Iron Grip", "Back Alley Throw", "Wall Smash",
			"Rebound Kick", "Bury Drop", "Chain Slam", "Pile Driver", "Junkyard Dog", "Last Stand",
		}, 5, "Close-quarters melee. Buffs grabs and throws."),
	},
	{
		id = "Bladework",
		title = "Bladework",
		points = 0,
		moves = moves({
			"Clean Cut", "Parry Riposte", "Edge Pressure", "Step Slash", "Rising Arc", "Posture Breaker",
			"Quick Draw", "Crosscut", "Steel Wall", "Counter Flow", "Long Reach", "Final Edge",
		}, 0, "Weapon mastery, parry and posture play."),
	},
	{
		id = "Supporter",
		title = "Supporter",
		points = 0,
		moves = moves({
			"Jack-in-the-Box", "Smoke Pop", "Rust Hex", "Patch Up", "Tin Can Alarm", "Static Shock",
			"Sticky Trap", "Wind-Up Toy", "Second Wind", "Lucky Draw", "Scatter Bomb", "Rally",
		}, 0, "A pool of random moves and debuffs, with some support."),
	},
} :: { Path }
MockData.pointsAvailable = 3

-- Shop placeholders. Odds: Common 25% and Legendary 1% are from the Gacha spec; the middle tiers
-- are OPEN there, so these numbers are display placeholders only.
MockData.rollPool = {
	{ name = "Sandals", rarity = "Common", chance = "25%", model = "Sandals" },
	{ name = "Umbrella", rarity = "Uncommon", chance = "40%", model = "Umbrella" },
	{ name = "???", rarity = "Rare", chance = "24%", model = "Mystery" },
	{ name = "???", rarity = "Epic", chance = "10%", model = "Mystery" },
	{ name = "???", rarity = "Legendary", chance = "1%", model = "Mystery" },
}
MockData.rollPrices = {
	{ label = "x1", price = 150 },
	{ label = "x3", price = 420 },
	{ label = "x10", price = 1300 },
}
MockData.supplies = {
	{ id = "Ration", price = 25 },
	{ id = "Water", price = 20 },
	{ id = "Canteen", price = 60 },
	{ id = "Bandage", price = 35 },
	{ id = "Filter", price = 80 },
	{ id = "Mask", price = 140 },
}
MockData.passes = {
	{ title = "x2 Scrap", line1 = "Walls drop", line2 = "x2 Scrap!", price = 399, style = "rainbow", model = "ScrapBundle" },
	{ title = "Reset Pill", line1 = "Respec your", line2 = "skill paths!", price = 99, style = "gold", model = "Pill" },
}

-- Progression snapshot for the edit-mode preview, in the server's ProfileSync shape
-- (TRASH-Progression Sync.luau). Live play uses the real snapshot.
MockData.profile = {
	faction = "Scrappers",
	relic = { id = "Hubcap", rarity = "Rare", tier = 2 },
	pending = nil,
	level = 12,
	exp = 340,
	points = 3,
	perks = { MartialArts = 2, Supporter = 1 },
	standing = 520,
	pity = { rare = 4, legendary = 31 },
	items = { Ration = 3, Water = 2, DirtyWater = 1, Bandage = 2, PlasticBottle = 6, TinCan = 4, ClothRag = 3, CopperWire = 2, ToxicSludge = 4, SmoglingCore = 1, SpinToken = 1 },
	quests = {
		active = {
			R4_PestControl = { step = 1, progress = 3, tracked = true },
			S2_BottleDrive = { step = 1, progress = 4, tracked = true },
		},
		done = { P0_Arrival = 1, P1_Stomach = 1, P2_Salvage = 1, P3_Sort = 1, P4_TwoRoads = 1, R1_FreshMeat = 1, R2_StripRun = 1, R3_FirstEdge = 1 },
	},
	notes = { Plastic = 1, Aluminum = 1, Smog = 1, Landfill = 1 },
	available = { { id = "S3_FilterBoil", giver = "Juno", giverName = "Juno" } },
	marks = {},
	smith = {
		tier = 3,
		unlocks = "C",
		reqs = {
			{ label = "Level 15", have = 12, need = 15, ok = false },
			{ label = "Rank: Runner", have = 3, need = 3, ok = true },
			{ label = "Scrap", have = 386, need = 600, ok = false },
			{ label = "Anima Residue", have = 42, need = 30, ok = true },
		},
		ready = false,
	},
	readOnly = false,
}

-- Player list preview.
MockData.players = {
	{ name = "Tinker", faction = "Scrappers", title = "Scavenger" },
	{ name = "Basil", faction = "Menders", title = "Vanguard" },
	{ name = "Marlo", faction = "Menders", title = "Vanguard" },
	{ name = "Juno", faction = "Menders", title = "Sweeper" },
	{ name = "Pip", faction = "Menders", title = "Sweeper" },
	{ name = "Dusty", faction = "Scrappers", title = "Enforcer" },
	{ name = "Cass", faction = "Scrappers", title = "Boss" },
	{ name = "Nova", faction = "Unaligned", title = "Drifter" },
}

return MockData
