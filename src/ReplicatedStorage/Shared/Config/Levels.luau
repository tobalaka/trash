--!strict
--[[
	Config.Levels - character EXP and levels, and the four skill paths (vault: Skill-Trees,
	Progression). Every level after the first gives a skill point. Points buy perks in order along
	a path and stay locked in until a Stat Reset Pill refunds them all (RESET_REFUND 100%).
	Perks only touch systems this game owns outside combat and movement (Relic moves, health,
	survival, salvaging, rides, the Blacksmith), so CombatService and the movement scripts stay
	untouched. Values are PROPOSALS (2026-10-25, retuned 2026-10-26).

	Caps (2026-10-26, user: "set max levels"):
	  level 40, so 39 skill points; each path costs 16, so a build masters two paths and dips
	  into a third (64 points would buy everything). Past level 40, EXP fills Overflow bars that
	  each pay OVERFLOW_REWARD.
]]

local Levels = {}

Levels.MAX = 40
Levels.EXP_BASE = 60 -- EXP from level 1 to 2...
Levels.EXP_STEP = 70 -- ...and this much more for every level after: about 54,000 EXP to 40
Levels.POINTS_PER_LEVEL = 1
Levels.MAX_POINTS = (Levels.MAX - 1) * Levels.POINTS_PER_LEVEL
Levels.OVERFLOW_EXP = 3000 -- at max level: EXP per Overflow bar
Levels.OVERFLOW_REWARD = { residue = 15, items = { SpinToken = 1 } }

-- EXP needed to go from `level` to `level + 1`
function Levels.need(level: number): number
	return Levels.EXP_BASE + Levels.EXP_STEP * (level - 1)
end

-- rewards for reaching a level
Levels.REWARDS = {
	[5] = { items = { SpinToken = 1 } },
	[10] = { items = { SpinToken = 1, ResetPill = 1 } },
	[15] = { items = { SpinToken = 1 } },
	[20] = { items = { SpinToken = 2 } },
	[25] = { items = { SpinToken = 1, Bandage = 3 } },
	[30] = { items = { SpinToken = 2, ResetPill = 1 } },
	[35] = { items = { SpinToken = 2 } },
	[40] = { items = { SpinToken = 3, ResetPill = 1 }, title = "Legend" },
} :: { [number]: { items: { [string]: number }, title: string? } }

-- EXP per action (quests give their own)
Levels.EXP = {
	SALVAGE = 6,
	CRAFT = 4,
	RECYCLE_ITEM = 1,
	PROCESS = 10, -- purify or smelt
	SMOGLING = 18,
	APEX = 70, -- an Apex Smogling (Wastezone)
	JUNKRAM = 400,
	CONTEST_WIN = 120,
	CONTEST_JOIN = 40,
	BOUNTY = 30,
	WANTED_BOUNTY = 90, -- claiming a Wanted player
	TURF_WIN = 300,
	TURF_JOIN = 80,
	REVIVE = 25,
}

export type Effect = {
	maxHealth: number?,
	anima: number?,
	meleeDamage: number?,
	secondWind: boolean?,
	abilityArmor: number?,
	abilityDamage: number?,
	cooldown: number?,
	postureDamage: number?,
	ultCost: number?,
	reach: number?,
	smithDiscount: number?,
	drain: number?,
	yield: number?,
	itemPower: number?,
	cleanGut: boolean?,
	gasResist: number?,
	rally: number?,
	jack: number?,
	revive: boolean?,
	dashRange: number?,
	salvageSpeed: number?,
	iframes: number?,
	transit: number?,
	momentum: number?,
	animaKeep: number?,
	slipstream: number?,
}
export type Perk = { id: string, name: string, cost: number, desc: string, effect: Effect, capstone: boolean? }
export type Path = { id: string, title: string, desc: string, perks: { Perk } }

Levels.PATHS = {
	{
		id = "MartialArts",
		title = "Martial Arts",
		desc = "Toughness and close-range power.",
		perks = {
			{ id = "IronGut", name = "Iron Gut", cost = 1, desc = "+10 max Health.", effect = { maxHealth = 10 } },
			{ id = "Brawler", name = "Brawler's Anima", cost = 1, desc = "Build Anima 20% faster.", effect = { anima = 0.2 } },
			{ id = "HeavyHands", name = "Heavy Hands", cost = 2, desc = "Close-range Relic moves (strikes, cones, dashes and bursts) deal 10% more damage.", effect = { meleeDamage = 0.1 } },
			{ id = "SecondWind", name = "Second Wind", cost = 2, desc = "Dropping below 30% Health restores 2 Health a second for 6 seconds. Once a minute.", effect = { secondWind = true } },
			{ id = "Shoulders", name = "Broad Shoulders", cost = 3, desc = "+15 max Health.", effect = { maxHealth = 15 } },
			{ id = "LastStand", name = "Last Stand", cost = 3, desc = "Your Relic moves can't be interrupted for their first 0.3 seconds.", effect = { abilityArmor = 0.3 } },
			{ id = "Juggernaut", name = "Juggernaut", cost = 4, capstone = true, desc = "Mastery. +20 max Health, and your Relic moves can't be interrupted for their first 0.5 seconds.", effect = { maxHealth = 20, abilityArmor = 0.2 } },
		},
	},
	{
		id = "Bladework",
		title = "Bladework",
		desc = "Relic mastery: harder, faster, further.",
		perks = {
			{ id = "HonedEdge", name = "Honed Edge", cost = 1, desc = "Relic moves deal 8% more damage.", effect = { abilityDamage = 0.08 } },
			{ id = "QuickDraw", name = "Quick Draw", cost = 1, desc = "Relic cooldowns are 8% shorter.", effect = { cooldown = 0.08 } },
			{ id = "PostureBreaker", name = "Posture Breaker", cost = 2, desc = "Relic moves deal 25% more posture damage.", effect = { postureDamage = 0.25 } },
			{ id = "Finesse", name = "Finesse", cost = 2, desc = "Your ultimate needs 15% less Anima.", effect = { ultCost = 0.15 } },
			{ id = "LongReach", name = "Long Reach", cost = 3, desc = "Relic moves reach 12% further.", effect = { reach = 0.12 } },
			{ id = "MasterSmith", name = "Master Smith", cost = 3, desc = "Blacksmith upgrades cost 10% less Scrap.", effect = { smithDiscount = 0.1 } },
			{ id = "Masterwork", name = "Masterwork", cost = 4, capstone = true, desc = "Mastery. Relic moves deal 10% more damage and 15% more posture damage.", effect = { abilityDamage = 0.1, postureDamage = 0.15 } },
		},
	},
	{
		id = "Supporter",
		title = "Supporter",
		desc = "Survival, salvage and the team.",
		perks = {
			{ id = "IronStomach", name = "Iron Stomach", cost = 1, desc = "Hunger and Thirst drain 15% slower.", effect = { drain = 0.15 } },
			{ id = "ScavengerLuck", name = "Scavenger's Luck", cost = 1, desc = "Junk piles give 20% more.", effect = { yield = 0.2 } },
			{ id = "FieldMedic", name = "Field Medic", cost = 2, desc = "Food, water and bandages restore 30% more.", effect = { itemPower = 0.3 } },
			{ id = "Purifier", name = "Purifier", cost = 2, desc = "Murky water no longer costs Vitality, and Wastezone gas drains you half as fast.", effect = { cleanGut = true, gasResist = 0.5 } },
			{ id = "Rally", name = "Rally", cost = 3, desc = "Using your R move heals allies within 12 studs for 15.", effect = { rally = 15 } },
			{ id = "JackInTheBox", name = "Jack-in-the-Box", cost = 3, desc = "Relic hits have a 15% chance of a random extra: a short stagger or a posture drain. The server rolls it.", effect = { jack = 0.15 } },
			{ id = "FieldRevive", name = "Field Revive", cost = 4, capstone = true, desc = "Mastery. Hold E on a knocked ally of your side to get them back up with Vitality and a bite to eat.", effect = { revive = true } },
		},
	},
	{
		-- the GDD's fourth path ("Speed"). It never touches the movement scripts: it speeds up
		-- what this game owns (Relic dashes, salvaging, rides, cooldowns).
		id = "Fleetfoot",
		title = "Fleetfoot",
		desc = "Speed: quick feet, quick hands.",
		perks = {
			{ id = "LightFeet", name = "Light Feet", cost = 1, desc = "Relic dashes, leaps and hops carry you 15% further.", effect = { dashRange = 0.15 } },
			{ id = "QuickHands", name = "Quick Hands", cost = 1, desc = "Salvaging a junk pile takes 25% less time.", effect = { salvageSpeed = 0.25 } },
			{ id = "Afterimage", name = "Afterimage", cost = 2, desc = "Hops and counters dodge for 0.2 seconds longer.", effect = { iframes = 0.2 } },
			{ id = "Express", name = "Express", cost = 2, desc = "Rides between the Gate Market and the bases are ready three times as fast.", effect = { transit = 0.66 } },
			{ id = "Momentum", name = "Momentum", cost = 3, desc = "Every Relic hit you land takes 0.4 seconds off your other Relic cooldowns.", effect = { momentum = 0.4 } },
			{ id = "Tailwind", name = "Tailwind", cost = 3, desc = "Relic cooldowns are 10% shorter, and your Anima fades half as fast out of a fight.", effect = { cooldown = 0.1, animaKeep = 0.5 } },
			{ id = "Slipstream", name = "Slipstream", cost = 4, capstone = true, desc = "Mastery. For 2 seconds after a dash, leap or hop, your Relic hits deal 25% more damage.", effect = { slipstream = 0.25 } },
		},
	},
} :: { Path }

Levels.pathById = {} :: { [string]: Path }
for _, p in Levels.PATHS do
	Levels.pathById[p.id] = p
end

-- the most a single path costs (all its perks)
function Levels.pathCost(path: Path): number
	local total = 0
	for _, perk in path.perks do
		total += perk.cost
	end
	return total
end

return Levels
