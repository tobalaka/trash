--!strict
--[[
	Npcs - everyone a player can talk to (vault: 03-Content/NPCs). The server places an invisible
	anchor with a prompt and a name tag at each site; every client builds and animates the body
	itself with the Townsfolk look kit, from `look` (so all players see the same person).

	site.kind "Plaza": slot 1-12 around the Gate Market (Patchwork Town's south market plaza),
	          between its stalls, facing the middle.
	site.kind "Point": a fixed spot (x, z) facing `look`; the server finds the ground under it.
	stations   trade windows this NPC opens (Shared/Data/Stations)
	recruiter  this NPC can sign a player up to a faction
	transit    this NPC offers a ride to that place: Town | MendersBase | ScrappersBase
	Quest lines live with the quests (Shared/Data/Quests); `greeting` is said when there is
	nothing quest-related to say.
]]

export type Style = {
	shirt: Color3?,
	accent: Color3?,
	hat: string?, -- beanie | cap | wide | hood | none
	apron: boolean?,
	pin: boolean?,
	tag: boolean?,
	mask: boolean?,
	goggles: boolean?,
	kid: boolean?,
	scale: number?,
}
export type Site = { kind: string, slot: number?, x: number?, z: number?, look: Vector3? }
export type Npc = {
	id: string,
	name: string,
	title: string,
	faction: string?,
	role: string, -- Townsfolk look role: Vendor | Crier | Loiter | Shopper
	seed: number,
	style: Style?,
	site: Site,
	stations: { string }?,
	recruiter: string?,
	transit: string?,
	greeting: { string },
}

local rgb = Color3.fromRGB
local TEAL = rgb(96, 204, 188)
local TEAL_DARK = rgb(56, 120, 112)
local PURPLE = rgb(150, 96, 210)
local PURPLE_DARK = rgb(70, 44, 96)

local function plaza(slot: number): Site
	return { kind = "Plaza", slot = slot }
end
local function point(x: number, z: number, look: Vector3): Site
	return { kind = "Point", x = x, z = z, look = look }
end
local EAST, WEST, NORTH, SOUTH = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 0, 1)

local list: { Npc } = {
	-- ═══ Patchwork Town: the Gate Market ═══
	{
		id = "Mags",
		name = "Old Mags",
		title = "Gate Market Elder",
		role = "Crier",
		seed = 1101,
		style = { hat = "wide", accent = rgb(196, 140, 64) },
		site = plaza(1),
		greeting = {
			"Fifty years I've watched the barges unload. Fifty years we've been finding it all a use.",
			"Mind the piles. Everything in them was somebody's once.",
		},
	},
	{
		id = "Wren",
		name = "Wren",
		title = "Menders Recruiter",
		faction = "Menders",
		role = "Vendor",
		seed = 1102,
		style = { shirt = TEAL_DARK, accent = TEAL, hat = "cap", pin = true },
		site = plaza(2),
		recruiter = "Menders",
		transit = "MendersBase",
		greeting = {
			"The Menders keep this place standing. We sort what falls, we fix what breaks, and we look after each other.",
			"Need a lift to headquarters? The sweeper cart leaves whenever you're ready.",
		},
	},
	{
		id = "Knox",
		name = "Knox",
		title = "Scrappers Recruiter",
		faction = "Scrappers",
		role = "Vendor",
		seed = 1103,
		style = { shirt = PURPLE_DARK, accent = PURPLE, hat = "beanie", tag = true },
		site = plaza(3),
		recruiter = "Scrappers",
		transit = "ScrappersBase",
		greeting = {
			"Nobody up there cares what happens to us down here. So we take care of ourselves.",
			"Want to see the Den? The truck runs when I say it does. Today, I say it does.",
		},
	},
	{
		id = "Pell",
		name = "Pell",
		title = "Provisions",
		role = "Vendor",
		seed = 1104,
		style = { apron = true, hat = "cap" },
		site = plaza(4),
		stations = { "Store" },
		greeting = {
			"Clean water, sealed food, bandages. Prices are what the barges let them be.",
			"You look thirsty. Everyone down here looks thirsty.",
		},
	},
	{
		id = "Ada",
		name = "Ada",
		title = "Sorting Bins",
		role = "Vendor",
		seed = 1105,
		style = { apron = true, accent = rgb(150, 214, 110) },
		site = plaza(5),
		stations = { "Recycler" },
		greeting = {
			"Plastic here, metal there, glass on its own. Sort it right and it's worth Scrap. Mix it up and it's just trash again.",
		},
	},
	{
		id = "Juno",
		name = "Juno",
		title = "Tinkerer",
		role = "Vendor",
		seed = 1106,
		style = { goggles = true, accent = rgb(214, 180, 96) },
		site = plaza(6),
		stations = { "Workbench" },
		greeting = {
			"Bring me a bottle, a rag and a little patience and I'll show you how to make dirty water drinkable.",
		},
	},
	{
		id = "NanaRo",
		name = "Nana Ro",
		title = "Water Carrier",
		role = "Loiter",
		seed = 1107,
		style = { hat = "hood", accent = rgb(90, 140, 150) },
		site = plaza(7),
		greeting = {
			"The pump on our row has been dry since spring. We walk to the gate for every drop.",
		},
	},
	{
		id = "Sparks",
		name = "Sparks",
		title = "Wire Puller",
		role = "Vendor",
		seed = 1108,
		style = { goggles = true, hat = "beanie" },
		site = plaza(8),
		greeting = {
			"Every dead machine has copper in it. You just have to know where to pull.",
		},
	},
	{
		id = "Pike",
		name = "Old Pike",
		title = "Tyre Cobbler",
		role = "Vendor",
		seed = 1109,
		style = { apron = true, hat = "wide" },
		site = plaza(9),
		greeting = {
			"Half the Heap walks on soles I cut from dead tyres.",
		},
	},
	{
		id = "Tam",
		name = "Tam",
		title = "Bottle Collector",
		role = "Loiter",
		seed = 1110,
		style = { kid = true, accent = rgb(220, 150, 90) },
		site = plaza(10),
		greeting = {
			"I've got four hundred and twelve bottles! Okay, four hundred and eleven. One was a jar.",
		},
	},
	{
		id = "Odo",
		name = "Clerk Odo",
		title = "Job & Bounty Board",
		role = "Vendor",
		seed = 1111,
		style = { hat = "cap", accent = rgb(214, 204, 176) },
		site = plaza(11),
		stations = { "Bounties" },
		greeting = {
			"Work comes in every day. Pay comes in when the work's done.",
			"Somebody's always got a price on somebody. The board's right here.",
		},
	},
	{
		id = "Sal",
		name = "Sal",
		title = "Junk Trader",
		role = "Vendor",
		seed = 1112,
		style = { mask = true, hat = "beanie" },
		site = plaza(12),
		stations = { "Fence" },
		greeting = {
			"I buy what you carry. Don't ask where it goes; I don't ask where it came from.",
		},
	},

	-- ═══ Menders Headquarters ═══
	{
		id = "Iris",
		name = "Commander Iris",
		title = "Menders Commander",
		faction = "Menders",
		role = "Crier",
		seed = 2101,
		style = { shirt = TEAL_DARK, accent = TEAL, hat = "cap", pin = true, scale = 1.06 },
		site = point(-485, -32, NORTH),
		greeting = {
			"Every pile we sort is a little less poison in the air our kids breathe. That is the whole job.",
		},
	},
	{
		id = "Bram",
		name = "Bram",
		title = "Menders Blacksmith",
		faction = "Menders",
		role = "Vendor",
		seed = 2102,
		style = { apron = true, goggles = true, pin = true },
		site = point(-455, -60, WEST),
		stations = { "Blacksmith" },
		greeting = {
			"Bring me Scrap and the right parts and I'll wake up what's sleeping in that Relic of yours.",
		},
	},
	{
		id = "Hollis",
		name = "Hollis",
		title = "Quartermaster",
		faction = "Menders",
		role = "Vendor",
		seed = 2103,
		style = { shirt = TEAL_DARK, apron = true, pin = true },
		site = point(-515, -60, EAST),
		stations = { "Store" },
		transit = "Town",
		greeting = {
			"Members get a discount. And a ride back to the market, if you want one.",
		},
	},
	{
		id = "Moss",
		name = "Moss",
		title = "Sorting Hall",
		faction = "Menders",
		role = "Vendor",
		seed = 2104,
		style = { apron = true, accent = rgb(150, 214, 110), pin = true },
		site = point(-515, -110, EAST),
		stations = { "Recycler" },
		greeting = {
			"Sorted right, a bottle comes back as a bottle. Sorted wrong, it comes back as smog.",
		},
	},
	{
		id = "Lune",
		name = "Dr. Lune",
		title = "Purifier",
		faction = "Menders",
		role = "Vendor",
		seed = 2105,
		style = { mask = true, goggles = true, pin = true, accent = TEAL },
		site = point(-455, -110, WEST),
		stations = { "Purifier" },
		greeting = {
			"Sludge is only poison until someone bothers to clean it.",
		},
	},
	{
		id = "Kit",
		name = "Kit",
		title = "Workshop",
		faction = "Menders",
		role = "Vendor",
		seed = 2106,
		style = { apron = true, hat = "beanie", pin = true },
		site = point(-455, -150, WEST),
		stations = { "Workbench" },
		greeting = {
			"Bandages, filters, respirators. Nothing fancy. Everything useful.",
		},
	},

	-- ═══ The Scrappers' Den ═══
	{
		id = "Vex",
		name = "Boss Vex",
		title = "Scrappers Boss",
		faction = "Scrappers",
		role = "Crier",
		seed = 3101,
		style = { shirt = PURPLE_DARK, accent = PURPLE, hat = "wide", tag = true, scale = 1.08 },
		site = point(1587, -2640, SOUTH),
		greeting = {
			"They ship us their scraps and call us scavengers. Fine. Scavengers eat.",
		},
	},
	{
		id = "Grit",
		name = "Grit",
		title = "Scrappers Blacksmith",
		faction = "Scrappers",
		role = "Vendor",
		seed = 3102,
		style = { apron = true, mask = true, tag = true },
		site = point(1558, -2620, EAST),
		stations = { "Blacksmith" },
		greeting = {
			"Scrap and parts, kid. I don't do favours, I do upgrades.",
		},
	},
	{
		id = "Rook",
		name = "Rook",
		title = "Supply Runner",
		faction = "Scrappers",
		role = "Vendor",
		seed = 3103,
		style = { hat = "cap", tag = true, accent = PURPLE },
		site = point(1616, -2570, WEST),
		stations = { "Store" },
		transit = "Town",
		greeting = {
			"Crew price for crew. Need a ride back to the market? Hop in the back.",
		},
	},
	{
		id = "Dax",
		name = "Dax",
		title = "Fence",
		faction = "Scrappers",
		role = "Vendor",
		seed = 3104,
		style = { hat = "beanie", tag = true, goggles = true },
		site = point(1616, -2620, WEST),
		stations = { "Fence" },
		greeting = {
			"Copper, glass, boards. I move it all, and I pay crew better than anyone in the dome.",
		},
	},
	{
		id = "Cinder",
		name = "Cinder",
		title = "Furnace Keeper",
		faction = "Scrappers",
		role = "Vendor",
		seed = 3105,
		style = { apron = true, mask = true, tag = true, accent = rgb(222, 106, 46) },
		site = point(1558, -2570, EAST),
		stations = { "Smelter" },
		greeting = {
			"The furnace eats sludge and spits out alloy. And smoke. A lot of smoke.",
		},
	},
	{
		id = "Bolt",
		name = "Bolt",
		title = "Chop Shop",
		faction = "Scrappers",
		role = "Vendor",
		seed = 3106,
		style = { apron = true, hat = "cap", tag = true },
		site = point(1587, -2548, NORTH),
		stations = { "Workbench" },
		greeting = {
			"If it's broken I can make it useful. If it's useful I can make it mine.",
		},
	},

	-- ═══ the outer biomes (2026-10-26) ═══
	{
		id = "Sable",
		name = "Keeper Sable",
		title = "The Smog Spire",
		role = "Loiter",
		seed = 4101,
		style = { hat = "hood", accent = rgb(232, 210, 150), goggles = true },
		site = point(30, 2200, SOUTH), -- at the foot of the tower's rock cone, looking up at it
		greeting = {
			"Everyone who climbs out here thinks the Spire is a way out. It isn't. It's an old smokestack: from the top you can see how far the smog spreads.",
			"Sand gets into everything. So does the trash. Out here you can see how far the dumping reaches.",
		},
	},
	{
		id = "Fern",
		name = "Fern",
		title = "Ruin Picker",
		role = "Loiter",
		seed = 4102,
		style = { hat = "wide", accent = rgb(120, 180, 90), apron = true },
		site = point(1985, -1500, NORTH), -- in front of the Jungle gate
		greeting = {
			"The jungle eats what the barges drop. Give it time and even a dump turns green.",
			"Watch your step past the gate. The roots don't care who you fight for.",
		},
	},
	{
		id = "Hale",
		name = "Hale",
		title = "Ice Hauler",
		role = "Vendor",
		seed = 4103,
		style = { hat = "beanie", accent = rgb(150, 200, 230), mask = true },
		site = point(381, -3650, SOUTH), -- out on the Winter flats, south of the dome
		greeting = {
			"Cold keeps things. Food, water, grudges. That's why people bring their stores out here.",
			"If the wind takes your hat, let it go. It's somebody else's now.",
		},
	},
}

local Npcs = {}
Npcs.list = list
Npcs.byId = {} :: { [string]: Npc }
for _, n in list do
	Npcs.byId[n.id] = n
end

-- the Gate Market: Patchwork Town's south market plaza (MapGen Town.plan plazas, gate angle 90)
Npcs.PLAZA_CENTER = Vector3.new(551, -16, -607.5)
Npcs.PLAZA_RADIUS = 38
Npcs.PLAZA_SLOTS = 12
Npcs.TALK_DISTANCE = 10

-- where each place's spawn sits (and where transit rides drop you)
Npcs.SPAWNS = {
	Town = { x = 551, z = -583, look = NORTH },
	MendersBase = { x = -485, z = -270, look = SOUTH },
	ScrappersBase = { x = 1587, z = -2420, look = NORTH },
}

return Npcs
