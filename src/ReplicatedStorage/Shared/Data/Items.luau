--!strict
--[[
	Items - every item a player can carry (vault: 02-Systems/Economy/Items). Currencies (Dollars,
	Scrap, Anima Residue) are not items; they live in the profile's wallet.

	category  where the Inventory window files it: Supplies | Recyclables | Hazards | Parts | Tokens
	group     the small-caps label inside that section
	model     the part-built 3D icon (ReplicatedStorage/UI/Models)
	use       what consuming one does (server: ServerScriptService/Progression/Survival)
	sell      Dollars at a Fence; nil = a Fence will not buy it
	sort      Scrap at a Recycling Station; nil = not recyclable
	note      the Field Note unlocked the first time this item is sorted or sold
	quick     consumables that also appear on the hotbar as a Tool

	Values are PROPOSALS (2026-10-25) until tuned in play; keep the vault table in sync.
]]

export type Use = {
	hunger: number?,
	thirst: number?,
	blood: number?, -- negative for contaminated food or water
	heal: number?, -- health over `healTime` seconds
	healTime: number?,
	stopBleed: number?, -- seconds Vitality cannot drain
	gas: number?, -- seconds of Wastezone gas protection
}

export type Item = {
	id: string,
	name: string,
	category: string,
	group: string,
	rarity: string,
	desc: string,
	model: string,
	use: Use?,
	quick: boolean?,
	sell: number?,
	sort: number?,
	note: string?,
}

local list: { Item } = {
	-- ── supplies ──
	{
		id = "Ration",
		name = "Ration Tin",
		category = "Supplies",
		group = "Food",
		rarity = "Common",
		desc = "Sealed beans salvaged from an export bale. Restores 45 Hunger.",
		model = "Ration",
		use = { hunger = 45 },
		quick = true,
		sell = 6,
	},
	{
		id = "Skewer",
		name = "Street Skewer",
		category = "Supplies",
		group = "Food",
		rarity = "Common",
		desc = "Grilled at a market stall. Cheap and warm. Restores 25 Hunger.",
		model = "Skewer",
		use = { hunger = 25 },
		quick = true,
		sell = 3,
	},
	{
		id = "Water",
		name = "Clean Water",
		category = "Supplies",
		group = "Water",
		rarity = "Common",
		desc = "Filtered and boiled. Restores 45 Thirst.",
		model = "Water",
		use = { thirst = 45 },
		quick = true,
		sell = 5,
	},
	{
		id = "DirtyWater",
		name = "Murky Water",
		category = "Supplies",
		group = "Water",
		rarity = "Common",
		desc = "Scooped from a gutter. Restores 30 Thirst but costs 12 Vitality. Filter and boil it at a Workbench first.",
		model = "DirtyWater",
		use = { thirst = 30, blood = -12 },
		quick = true,
	},
	{
		id = "Bandage",
		name = "Bandage Roll",
		category = "Supplies",
		group = "Medical",
		rarity = "Common",
		desc = "Torn from clean rags. Heals 30 Health over 6 seconds and stops Vitality loss for 20 seconds.",
		model = "Bandage",
		use = { heal = 30, healTime = 6, stopBleed = 20 },
		quick = true,
		sell = 8,
	},
	{
		id = "GasFilter",
		name = "Bottle Respirator",
		category = "Supplies",
		group = "Medical",
		rarity = "Uncommon",
		desc = "A cut bottle packed with cloth and rubber. Lets you breathe the Wastezone's gas for 150 seconds.",
		model = "Filter",
		use = { gas = 150 },
		quick = true,
		sell = 18,
	},

	-- ── recyclables (sort at a Recycling Station, sell at a Fence) ──
	{
		id = "PlasticBottle",
		name = "Plastic Bottle",
		category = "Recyclables",
		group = "Plastic",
		rarity = "Common",
		desc = "Crushed and dusty. The barges dump thousands of these every week.",
		model = "Bottle",
		sell = 2,
		sort = 3,
		note = "Plastic",
	},
	{
		id = "TinCan",
		name = "Tin Can",
		category = "Recyclables",
		group = "Metal",
		rarity = "Common",
		desc = "Rinsed, flattened, ready to melt down.",
		model = "Can",
		sell = 2,
		sort = 3,
		note = "Aluminum",
	},
	{
		id = "ClothRag",
		name = "Cloth Rag",
		category = "Recyclables",
		group = "Textiles",
		rarity = "Common",
		desc = "Old shirts and sacking. Good for bandages, filters and patches.",
		model = "Rag",
		sell = 1,
		sort = 2,
		note = "Textiles",
	},
	{
		id = "GlassShard",
		name = "Glass Shards",
		category = "Recyclables",
		group = "Glass",
		rarity = "Uncommon",
		desc = "Bottle glass, wrapped so nobody gets cut.",
		model = "Glass",
		sell = 4,
		sort = 5,
		note = "Glass",
	},
	{
		id = "RubberScrap",
		name = "Rubber Scrap",
		category = "Recyclables",
		group = "Rubber",
		rarity = "Uncommon",
		desc = "Strips cut from a dead tyre.",
		model = "Rubber",
		sell = 4,
		sort = 5,
		note = "Tyres",
	},
	{
		id = "CopperWire",
		name = "Copper Wire",
		category = "Recyclables",
		group = "Metal",
		rarity = "Uncommon",
		desc = "Stripped from old cables and motors. Worth more than it looks.",
		model = "Wire",
		sell = 7,
		sort = 7,
		note = "Copper",
	},
	{
		id = "CircuitBoard",
		name = "Circuit Board",
		category = "Recyclables",
		group = "E-waste",
		rarity = "Rare",
		desc = "Pulled from a dead machine. Gold traces, copper and trouble.",
		model = "Circuit",
		sell = 15,
		sort = 14,
		note = "Ewaste",
	},

	-- ── hazards ──
	{
		id = "ToxicSludge",
		name = "Toxic Sludge",
		category = "Hazards",
		group = "Pollution",
		rarity = "Uncommon",
		desc = "Black goo from a Smogling. Nobody will buy it. Menders purify it; Scrappers smelt it down.",
		model = "Sludge",
		note = "Sludge",
	},

	-- ── parts (Blacksmith materials) ──
	{
		id = "SmoglingCore",
		name = "Smogling Core",
		category = "Parts",
		group = "Beast parts",
		rarity = "Rare",
		desc = "The knot of smoke that held a Smogling together. Blacksmiths need it for a third upgrade.",
		model = "Core",
		sell = 20,
	},
	{
		id = "BeastCore",
		name = "Ram Heart",
		category = "Parts",
		group = "Beast parts",
		rarity = "Legendary",
		desc = "Still humming. Torn from the Junk Ram in the Wastezone. The final upgrade needs one.",
		model = "BeastCore",
	},
	{
		id = "ApexCore",
		name = "Apex Core",
		category = "Parts",
		group = "Beast parts",
		rarity = "Epic",
		desc = "A Smogling core crushed so hard it glows. Only Apex Smoglings from the Wastezone carry them. Fences pay well.",
		model = "ApexCore",
		sell = 60,
	},
	{
		id = "MenderPin",
		name = "Mender's Pin",
		category = "Parts",
		group = "Trophies",
		rarity = "Uncommon",
		desc = "The teal bottle-cap pin of a defeated Mender. Scrapper quartermasters pay standing for them; a Fence pays cash.",
		model = "Pin",
		sell = 25,
	},
	{
		id = "ScrapperTag",
		name = "Scrapper's Tag",
		category = "Parts",
		group = "Trophies",
		rarity = "Uncommon",
		desc = "The stamped scrap tag of a defeated Scrapper. Mender quartermasters pay standing for them; a Fence pays cash.",
		model = "Tag",
		sell = 25,
	},
	{
		id = "PurifiedAnima",
		name = "Purified Anima",
		category = "Parts",
		group = "Faction work",
		rarity = "Epic",
		desc = "Sludge made clean at the Menders' Purifier. Mender Blacksmiths need it for M1 Mastery.",
		model = "PurifiedAnima",
	},
	{
		id = "HotAlloy",
		name = "Hot Alloy",
		category = "Parts",
		group = "Faction work",
		rarity = "Epic",
		desc = "Scrap and sludge melted in the Den's furnace. Scrapper Blacksmiths need it for M1 Mastery.",
		model = "HotAlloy",
	},

	-- ── tokens ──
	{
		id = "SpinToken",
		name = "Relic Spin",
		category = "Tokens",
		group = "Rolls",
		rarity = "Epic",
		desc = "One free roll on your faction's Relic pool. Your faction's Blacksmith rolls it.",
		model = "Spin",
	},
	{
		id = "ResetPill",
		name = "Stat Reset Pill",
		category = "Tokens",
		group = "Rolls",
		rarity = "Epic",
		desc = "Refunds every skill point you have spent. Use it in the Skills window.",
		model = "Pill",
	},
}

local Items = {}
Items.list = list
Items.byId = {} :: { [string]: Item }
for _, item in list do
	Items.byId[item.id] = item
end

Items.CATEGORY_ORDER = { "Supplies", "Recyclables", "Hazards", "Parts", "Tokens" }

function Items.get(id: string): Item?
	return Items.byId[id]
end

return Items
