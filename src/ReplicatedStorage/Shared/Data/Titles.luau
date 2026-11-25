--!strict
--[[
	Titles - names a player can earn and wear over their head (vault: Titles). Earned from quest
	finales, caps (max level, top rank), the Field Notes, bounties, the Turf War, the beasts and
	the team. One is worn at a time (Journal > Titles); the server keeps the list in the
	profile's flags and draws the worn one on the nameplate. Original to TRASH.

	how: the hint shown for a locked title. color: nil uses the wearer's faction colour.
]]

export type Title = { id: string, name: string, how: string, rarity: string, color: Color3? }

local rgb = Color3.fromRGB

local list: { Title } = {
	-- story
	{ id = "Grounded", name = "Grounded", how = "Finish the Prologue: check in with your side's recruiter.", rarity = "Common" },
	{ id = "CleanSlate", name = "Clean Slate", how = "Menders: master your Relic (Clean Slate).", rarity = "Rare" },
	{ id = "TakeWhatsLeft", name = "Take What's Left", how = "Scrappers: master your Relic (The Boss's Blessing).", rarity = "Rare" },
	{ id = "ClearSkies", name = "Keeper of Clear Skies", how = "Menders: finish the main story (Clear Skies).", rarity = "Legendary" },
	{ id = "CrownOfTheGround", name = "Crown of the Heap", how = "Scrappers: finish the main story (The Crown).", rarity = "Legendary" },
	{ id = "TowerPilgrim", name = "Tower Pilgrim", how = "Climb to the Smog Spire and meet its keeper.", rarity = "Uncommon", color = rgb(232, 210, 150) },
	-- caps
	{ id = "Legend", name = "Legend of the Heap", how = "Reach level 40.", rarity = "Legendary", color = rgb(255, 192, 48) },
	{ id = "Steward", name = "Steward", how = "Menders: reach the top rank.", rarity = "Epic" },
	{ id = "Boss", name = "Boss", how = "Scrappers: reach the top rank.", rarity = "Epic" },
	{ id = "Archivist", name = "Archivist", how = "Unlock every Field Note.", rarity = "Epic", color = rgb(118, 232, 196) },
	-- fighting
	{ id = "Headhunter", name = "Headhunter", how = "Claim 10 bounties.", rarity = "Rare", color = rgb(222, 106, 46) },
	{ id = "BountyKing", name = "Bounty King", how = "Claim 50 bounties.", rarity = "Legendary", color = rgb(222, 106, 46) },
	{ id = "MostWanted", name = "Most Wanted", how = "Reach full heat (5).", rarity = "Rare", color = rgb(222, 106, 46) },
	{ id = "HillKing", name = "King of the Hill", how = "Win 5 Turf Wars for your side.", rarity = "Epic" },
	{ id = "RamBreaker", name = "Ram Breaker", how = "Bring down the Junk Ram 10 times.", rarity = "Epic", color = rgb(236, 230, 214) },
	{ id = "ApexHunter", name = "Apex Hunter", how = "Break 25 Apex Smoglings.", rarity = "Rare", color = rgb(255, 176, 48) },
	-- the team and the trash
	{ id = "Lifeline", name = "Lifeline", how = "Help 10 knocked allies back up.", rarity = "Rare", color = rgb(120, 222, 44) },
	{ id = "Wrecker", name = "Wrecker", how = "Break 1,000 parts of the map.", rarity = "Uncommon", color = rgb(196, 140, 64) },
}

local Titles = {}
Titles.list = list
Titles.byId = {} :: { [string]: Title }
for _, t in list do
	Titles.byId[t.id] = t
end

-- stat thresholds that grant a title (profile.stats key -> { [count] = title id })
Titles.MILESTONES = {
	bounties = { [10] = "Headhunter", [50] = "BountyKing" },
	turfWins = { [5] = "HillKing" },
	junkRams = { [10] = "RamBreaker" },
	apex = { [25] = "ApexHunter" },
	revives = { [10] = "Lifeline" },
	smashed = { [1000] = "Wrecker" },
} :: { [string]: { [number]: string } }

return Titles
