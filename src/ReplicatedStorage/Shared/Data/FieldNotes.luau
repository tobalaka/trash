--!strict
--[[
	FieldNotes - the real-world environmental facts the game teaches (the Congressional App
	Challenge angle: environmental upcycling and social inequality). Each note unlocks the first
	time a player does the thing it is about: sorting a material, finishing a quest, reaching a
	place. The Journal window lists them.

	Facts are kept to widely published, conservative figures, and every note names where the
	figure comes from so a teacher or judge can check it. Keep any edit to that standard.
]]

export type Note = {
	id: string,
	title: string,
	topic: string, -- Journal grouping
	text: string,
	source: string,
	tip: string, -- one thing the player can do in real life
}

local list: { Note } = {
	{
		id = "Plastic",
		title = "The Bottle That Never Leaves",
		topic = "Materials",
		text = "Plastic does not rot away like food. It breaks into smaller and smaller pieces called microplastics, which can last for hundreds of years in soil and water.",
		source = "US EPA and UN Environment Programme (UNEP)",
		tip = "Carry a refillable bottle. The best plastic bottle is the one never made.",
	},
	{
		id = "Aluminum",
		title = "Cans Come Back",
		topic = "Materials",
		text = "Aluminum can be recycled again and again without losing quality, and making a can from recycled aluminum takes far less energy (over 90% less) than making one from raw ore.",
		source = "The Aluminum Association; US EPA",
		tip = "Rinse cans and put them in the recycling, not the trash.",
	},
	{
		id = "Textiles",
		title = "Rags to Riches",
		topic = "Materials",
		text = "Most thrown-away clothes end up in landfills or are burned. Repairing, swapping, donating or cutting old clothes into rags keeps them in use far longer.",
		source = "US EPA (textiles data); UNEP",
		tip = "Mend a torn shirt or turn it into cleaning rags before buying new ones.",
	},
	{
		id = "Glass",
		title = "Endless Glass",
		topic = "Materials",
		text = "Glass bottles and jars can be melted and remade endlessly without getting weaker. Broken glass in the trash is also a hazard for the people who sort it.",
		source = "Glass Packaging Institute; US EPA",
		tip = "Wrap broken glass before throwing it out, and recycle whole bottles and jars.",
	},
	{
		id = "Tyres",
		title = "Second Life for Tyres",
		topic = "Materials",
		text = "Old tyres are bulky and can trap water where mosquitoes breed. Shredded tyre rubber is reused in playgrounds, sports fields, road surfaces and even shoe soles.",
		source = "US EPA (scrap tires)",
		tip = "Return old tyres to a shop or collection point instead of dumping them.",
	},
	{
		id = "Copper",
		title = "Copper in the Walls",
		topic = "E-waste",
		text = "Copper can be recycled over and over. Recovering it from old wires and motors saves mining new ore, which uses lots of energy and water.",
		source = "International Copper Association; US EPA",
		tip = "Take old cables and chargers to an electronics recycling drop-off.",
	},
	{
		id = "Ewaste",
		title = "The E-waste Mountain",
		topic = "E-waste",
		text = "In 2022 the world threw away about 62 million tonnes of electronics. Less than a quarter of it was documented as properly collected and recycled, even though it holds valuable metals like copper and gold.",
		source = "UN Global E-waste Monitor 2024 (ITU and UNITAR)",
		tip = "Never put batteries or old phones in the trash. Use an e-waste collection point.",
	},
	{
		id = "Sludge",
		title = "What Runs Downhill",
		topic = "Pollution",
		text = "Wastewater treatment plants clean used water by letting solids settle and using tiny microbes to break down waste before the water goes back into rivers.",
		source = "US EPA (wastewater treatment)",
		tip = "Don't pour oil, paint or medicine down the drain.",
	},
	{
		id = "Smog",
		title = "The Air We Share",
		topic = "Pollution",
		text = "Air pollution is one of the biggest environmental risks to health. The World Health Organization links it to millions of early deaths every year.",
		source = "World Health Organization (WHO)",
		tip = "Walk, bike or share rides when you can, and never burn trash.",
	},
	{
		id = "Smelting",
		title = "Smoke from the Furnace",
		topic = "Pollution",
		text = "Melting scrap metal in open fires gives off toxic fumes. Proper recycling plants capture and filter their smoke so the metal can be reused safely.",
		source = "WHO (informal recycling and health)",
		tip = "Recycling should happen at real facilities, not by burning junk.",
	},
	{
		id = "FoodWaste",
		title = "A Third of the Food",
		topic = "Survival",
		text = "Roughly one third of the food produced for people is lost or wasted. Rotting food in landfills also gives off methane, a strong greenhouse gas.",
		source = "UN Food and Agriculture Organization (FAO); US EPA",
		tip = "Plan meals, eat leftovers, and compost scraps if you can.",
	},
	{
		id = "Water",
		title = "Not Everyone Has a Tap",
		topic = "Survival",
		text = "More than 2 billion people around the world still do not have safely managed drinking water at home.",
		source = "WHO / UNICEF Joint Monitoring Programme",
		tip = "Fix dripping taps and don't leave water running.",
	},
	{
		id = "Filter",
		title = "Filter, Then Boil",
		topic = "Survival",
		text = "A bottle filter made of cloth and sand can remove dirt and grit, but it does not kill germs. Water also has to be boiled or disinfected before it is safe to drink.",
		source = "WHO (household water treatment); US CDC",
		tip = "In an emergency, boiling water for one minute is one of the safest ways to treat it.",
	},
	{
		id = "Landfill",
		title = "Where Trash Goes to Wait",
		topic = "Pollution",
		text = "Most trash ends up in landfills, where it can stay for generations. Landfills give off methane and can leak polluted water into the ground if they are not built and managed well.",
		source = "US EPA (landfills)",
		tip = "Reduce first, reuse second, recycle third. Throwing away is the last option.",
	},
	{
		id = "WastePickers",
		title = "The People Who Sort",
		topic = "Inequality",
		text = "In many cities, informal waste pickers collect and sort a large share of what gets recycled, often without safety gear or fair pay.",
		source = "International Labour Organization (ILO); WIEGO",
		tip = "Rinse and sort your recycling: it makes the work safer for the people who handle it.",
	},
	{
		id = "Justice",
		title = "Downhill From Everyone",
		topic = "Inequality",
		text = "Dumps, landfills and polluting factories have often been placed near low-income communities and communities of color. Fighting this is called environmental justice.",
		source = "US EPA (environmental justice)",
		tip = "Learn where your own trash goes, and who lives next to it.",
	},
	{
		id = "Upcycling",
		title = "Trash With a Future",
		topic = "Upcycling",
		text = "Upcycling means turning waste into something of higher value, like a bag sewn from old banners or a lamp made from a bottle. It keeps materials in use and out of landfills.",
		source = "UN Environment Programme (circular economy)",
		tip = "Before you throw something away, ask what else it could be.",
	},
	{
		id = "Ocean",
		title = "All Drains Lead Somewhere",
		topic = "Pollution",
		text = "Millions of tonnes of plastic enter rivers, lakes and the ocean every year, harming fish, birds and other animals that mistake it for food.",
		source = "UN Environment Programme (UNEP)",
		tip = "Pick up litter near drains and rivers: it is the last stop before the water.",
	},
	-- added 2026-10-26 with the breakable map and the outer-biome side quests
	{
		id = "Demolition",
		title = "Rubble Counts Too",
		topic = "Materials",
		text = "Construction and demolition debris (concrete, wood, metal, drywall) is one of the biggest waste streams there is: in the United States it adds up to more than twice the weight of all household trash. Much of it can be reused or recycled instead of buried.",
		source = "US EPA (construction and demolition materials)",
		tip = "When something is torn down or remodelled, ask what can be saved: doors, bricks, metal and wood often find a second life.",
	},
	{
		id = "Compost",
		title = "Scraps to Soil",
		topic = "Upcycling",
		text = "Food scraps and yard waste make up more than 30% of what Americans throw away. Composted instead of landfilled, they turn back into soil and give off far less methane.",
		source = "US EPA (composting at home)",
		tip = "Start a compost bin or use a community drop-off for fruit and vegetable scraps.",
	},
	{
		id = "Repair",
		title = "Fix It First",
		topic = "Upcycling",
		text = "Repairing something instead of replacing it keeps its materials in use and its waste out of the bin. Many towns run free repair events where volunteers help mend clothes, electronics and furniture.",
		source = "US EPA (reducing and reusing basics); Repair Café Foundation",
		tip = "Before buying new, look up how to fix what broke, or find a local repair event.",
	},
}

local FieldNotes = {}
FieldNotes.list = list
FieldNotes.byId = {} :: { [string]: Note }
for _, n in list do
	FieldNotes.byId[n.id] = n
end
FieldNotes.TOPIC_ORDER = { "Materials", "E-waste", "Pollution", "Survival", "Inequality", "Upcycling" }

return FieldNotes
