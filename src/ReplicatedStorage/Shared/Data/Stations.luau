--!strict
--[[
	Stations - what each kind of trade station does, and the recipes (vault: Stations). A station
	is always run by an NPC (Shared/Data/Npcs); talking to them opens its window.

	  Store       buy supplies for Dollars (your own faction's quartermaster gives a discount)
	  Recycler    sort recyclables into Scrap (Menders get a better rate) and learn what they are
	  Fence       sell recyclables and spare parts for Dollars (Scrappers get a better rate)
	  Workbench   craft from what you salvage: water filters, bandages, respirators
	  Purifier    Menders only: clean Toxic Sludge into Purified Anima (cleans the air)
	  Smelter     Scrappers only: melt sludge and Scrap into Hot Alloy (dirties the air)
	  Blacksmith  upgrade your Relic (its own window)
]]

export type Recipe = {
	id: string,
	name: string,
	desc: string,
	kind: string, -- Craft | Purify | Smelt
	needs: { [string]: number }, -- items
	scrap: number?,
	residue: number?,
	gives: { [string]: number },
	dollars: number?, -- paid out
	pollution: string?, -- Config.Environment.DELTA key
	standing: number?,
	note: string?,
}

local recipes: { Recipe } = {
	{
		id = "BoilWater",
		name = "Filter & Boil",
		desc = "Pour murky water through a cut bottle packed with cloth, then boil it. Filtering takes out the grit; boiling makes it safe.",
		kind = "Craft",
		needs = { DirtyWater = 1, PlasticBottle = 1, ClothRag = 1 },
		gives = { Water = 1 },
		note = "Filter",
	},
	{
		id = "Bandage",
		name = "Bandage Roll",
		desc = "Tear two clean rags into strips.",
		kind = "Craft",
		needs = { ClothRag = 2 },
		gives = { Bandage = 1 },
	},
	{
		id = "Respirator",
		name = "Bottle Respirator",
		desc = "A cut bottle, a cloth filter and a rubber seal: enough to breathe the Wastezone for a while.",
		kind = "Craft",
		needs = { PlasticBottle = 1, ClothRag = 1, RubberScrap = 1 },
		gives = { GasFilter = 1 },
		note = "Upcycling",
	},
	{
		id = "Purify",
		name = "Purify Sludge",
		desc = "Settle, filter and cleanse three loads of sludge with Anima. Clean output, cleaner air.",
		kind = "Purify",
		needs = { ToxicSludge = 3 },
		residue = 2,
		gives = { PurifiedAnima = 1 },
		pollution = "Purify",
		standing = 5,
		note = "Sludge",
	},
	{
		id = "Smelt",
		name = "Smelt Alloy",
		desc = "Burn three loads of sludge with Scrap in the furnace. Strong metal, black smoke.",
		kind = "Smelt",
		needs = { ToxicSludge = 3 },
		scrap = 40,
		gives = { HotAlloy = 1 },
		dollars = 15,
		pollution = "Smelt",
		standing = 5,
		note = "Smelting",
	},
}

local Stations = {}
Stations.recipes = recipes
Stations.recipeById = {} :: { [string]: Recipe }
for _, r in recipes do
	Stations.recipeById[r.id] = r
end

-- which recipe kinds a station kind offers
Stations.KINDS = {
	Store = { tab = "Buy" },
	Recycler = { tab = "Sort" },
	Fence = { tab = "Sell" },
	Workbench = { tab = "Craft", recipes = "Craft" },
	Purifier = { tab = "Process", recipes = "Purify", faction = "Menders" },
	Smelter = { tab = "Process", recipes = "Smelt", faction = "Scrappers" },
	Blacksmith = { tab = "Upgrade" },
} :: { [string]: { tab: string, recipes: string?, faction: string? } }

return Stations
