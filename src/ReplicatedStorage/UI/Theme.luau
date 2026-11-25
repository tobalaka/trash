--!strict
--[[
	UI Theme - the UI's Config. Every colour, font, size, tween, keybind and attribute name the
	interface uses lives here, so the look can be tuned in one place.

	The look fuses the references in the vault (Congress Game/References for Design and shi/):
	  - Deepwoken (deep.webp, inventory.webp, the settings and map shots): translucent slate panels,
	    thin double-line frames with small corner ornaments, parchment item cards, serif titles,
	    italic descriptions, vertical survival bars, a parchment world map.
	  - Type Soul (moveset, submoves): bold sans column headers in strong colours over near-black
	    panels, large white move lists, square ability tiles with the key underneath, an ornate
	    vertical meter with pips.
	  - Steal / egg shops (shop, money, passes): chunky stroked display text, glossy price buttons
	    with a diagonal sheen, "-- SECTION --" headings, sunburst cards and bouncy hovers.
	  - Junkyard scrapbook: rust and toxic-lime accents, masking-tape strips and marker-pen tags.
	Everything is built from Frames, strokes and gradients. No images are uploaded.
]]

local rgb = Color3.fromRGB

local Theme = {}

-- Design resolution: offsets are authored for a 1080p screen and scaled to the viewport.
Theme.DESIGN_HEIGHT = 1080
Theme.SCALE_MIN = 0.55
Theme.SCALE_MAX = 1.6

Theme.Color = {
	-- panels (Deepwoken slate)
	Ink = rgb(12, 13, 14),
	Night = rgb(22, 24, 26),
	Coal = rgb(32, 35, 37),
	Slate = rgb(48, 54, 56),
	SlateHi = rgb(70, 78, 80),
	SlateLine = rgb(132, 140, 134),
	-- parchment cards and the world map
	Paper = rgb(214, 202, 172),
	PaperHi = rgb(232, 222, 196),
	PaperDark = rgb(170, 154, 118),
	PaperInk = rgb(52, 42, 30),
	-- ornament metal
	Gold = rgb(212, 174, 96),
	GoldHi = rgb(252, 224, 150),
	GoldDark = rgb(116, 88, 40),
	-- text
	Text = rgb(238, 234, 224),
	TextDim = rgb(176, 176, 166),
	TextMute = rgb(118, 120, 116),
	-- loud accents (egg / Steal buttons and headings, junkyard rust and lime)
	Rust = rgb(222, 106, 46),
	RustDark = rgb(128, 52, 22),
	Lime = rgb(120, 222, 44),
	LimeDark = rgb(52, 128, 16),
	Yellow = rgb(255, 214, 58),
	Cyan = rgb(66, 206, 244),
	Red = rgb(222, 46, 40),
	Magenta = rgb(196, 64, 220),
	Purple = rgb(92, 38, 140),
	Tape = rgb(226, 214, 168),
	-- vitals
	Health = rgb(228, 100, 58),
	Posture = rgb(240, 200, 88),
	Hunger = rgb(236, 152, 56),
	Thirst = rgb(78, 182, 226),
	Vitality = rgb(204, 78, 112),
	Anima = rgb(118, 232, 196),
	-- factions
	Menders = rgb(96, 204, 188),
	Scrappers = rgb(160, 96, 220),
	Neutral = rgb(170, 170, 160),
}

-- Skill path colours (Type Soul header bars). Paths from 02-Systems/Player/Skill-Trees.
Theme.PathColor = {
	MartialArts = rgb(236, 96, 40),
	Bladework = rgb(214, 44, 58),
	Supporter = rgb(36, 206, 116),
	Fleetfoot = rgb(66, 176, 244),
}

Theme.Rarity = {
	Common = rgb(178, 178, 170),
	Uncommon = rgb(118, 206, 88),
	Rare = rgb(76, 152, 242),
	Epic = rgb(176, 92, 236),
	Legendary = rgb(255, 192, 48),
}
Theme.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

local function family(f: Enum.Font): string
	return Font.fromEnum(f).Family
end

Theme.Font = {
	-- chunky stroked display text (egg / Steal)
	Display = Font.new(family(Enum.Font.FredokaOne), Enum.FontWeight.Bold),
	-- bold sans headers and move lists (Type Soul)
	Header = Font.new(family(Enum.Font.GothamBlack), Enum.FontWeight.Heavy),
	HeaderBold = Font.new(family(Enum.Font.GothamBold), Enum.FontWeight.Bold),
	-- serif titles, names and map labels (Deepwoken)
	Title = Font.new(family(Enum.Font.Merriweather), Enum.FontWeight.Bold),
	TitleItalic = Font.new(family(Enum.Font.Merriweather), Enum.FontWeight.Bold, Enum.FontStyle.Italic),
	Serif = Font.new(family(Enum.Font.Merriweather), Enum.FontWeight.Regular),
	-- body and descriptions (Deepwoken)
	Body = Font.new(family(Enum.Font.SourceSans), Enum.FontWeight.Regular),
	BodyBold = Font.new(family(Enum.Font.SourceSans), Enum.FontWeight.Bold),
	BodyItalic = Font.new(family(Enum.Font.SourceSans), Enum.FontWeight.Regular, Enum.FontStyle.Italic),
	-- marker-pen tags (street graffiti)
	Tag = Font.new(family(Enum.Font.PermanentMarker), Enum.FontWeight.Regular),
}

Theme.Tween = {
	Fast = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Med = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Ghost = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Fade = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

-- Menu keys. Combat and movement own Mouse1, F, G, Q, Z, X, C, R, B, Space, Shift, Ctrl and Left Alt
-- (02-Systems/Input/Keybinds).
Theme.Keys = {
	Inventory = Enum.KeyCode.Tab,
	Journal = Enum.KeyCode.J,
	Skills = Enum.KeyCode.K,
	Map = Enum.KeyCode.M,
	Settings = Enum.KeyCode.O,
}
Theme.CinematicKey = Enum.KeyCode.H

-- Hotbar slot keys, left to right.
Theme.HotbarKeys = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five,
	Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight, Enum.KeyCode.Nine, Enum.KeyCode.Zero,
}
Theme.HOTBAR_SLOTS = 10

-- Relic ability keys and the upgrade tier that unlocks each (02-Systems/Economy/Blacksmith).
Theme.Abilities = {
	{ key = "Z", tier = 1 },
	{ key = "X", tier = 2 },
	{ key = "C", tier = 3 },
	{ key = "R", tier = 0 },
	{ key = "B", tier = 0, ultimate = true },
}

-- Combat cooldown chips under the health frame (EXPED's IndicatorFrame). Cooldowns come from
-- "CooldownEnd_<id>" like the abilities (set by ServerScriptService/Combat/CombatService). Key
-- labels match ReplicatedStorage/Shared/Config/Keys; icons are UI/Exped glyphs.
Theme.Essentials = {
	{ id = "Roll", key = "Q", icon = "Dash" },
	{ id = "Parry", key = "F", icon = "Parry" },
	{ id = "Uppercut", key = "CTRL M1", icon = "Uppercut" },
	{ id = "Grab", key = "G", icon = "Grab" },
	{ id = "Crit", key = "T", icon = "Crit" },
	{ id = "Aerial", key = "AIR M1", icon = "Heavy" },
}

--[[
	Player attributes the HUD reads. The server owns and replicates them (Client-Server-Split);
	the UI only displays. Max values are read from "<Name>Max" and fall back to DEFAULT_MAX while
	the survival constants are OPEN in the vault.
	Ability cooldowns: the server sets "CooldownEnd_<Key>" to a workspace:GetServerTimeNow() time.
]]
Theme.Attr = {
	Hunger = "Hunger",
	Thirst = "Thirst",
	Vitality = "Blood", -- shown as "Vitality" on screen (Roblox-safe wording)
	Posture = "Posture",
	Anima = "Anima",
	Dollars = "Dollars",
	Scrap = "Scrap",
	Residue = "AnimaResidue",
	Faction = "Faction",
	Relic = "Relic",
	RelicRarity = "RelicRarity",
	UpgradeTier = "UpgradeTier",
	Level = "Level",
	Rank = "Rank",
	CooldownPrefix = "CooldownEnd_",
	Exp = "Exp",
	ExpNext = "ExpNext",
	Standing = "Standing",
	StandingNext = "StandingNext",
	SkillPoints = "SkillPoints",
	Knocked = "Knocked",
	Toxic = "Toxic",
	GasUntil = "GasUntil",
	WellFed = "WellFed",
	Heat = "Heat",
	LevelMax = "LevelMax",
}

-- Quest line colours (Journal and tracker)
Theme.LineColor = {
	Prologue = rgb(214, 180, 96),
	Menders = rgb(96, 204, 188),
	Scrappers = rgb(160, 96, 220),
	Side = rgb(220, 150, 90),
	Job = rgb(150, 170, 186),
}

-- Air quality bar (Workspace attribute "Pollution", 0-100)
Theme.Air = {
	Clear = rgb(120, 222, 44),
	Hazy = rgb(214, 180, 96),
	Smog = rgb(150, 112, 60),
}
Theme.DEFAULT_MAX = 100

-- Region display names and lore lines for the title card and map (keys from MapRegionVolumes).
Theme.Regions = {
	TownDome = { name = "Patchwork Town", lore = "Under the patchwork dome, the Heap trades whatever the barges dump." },
	Town = { name = "The Outskirts", lore = "Stacked shacks and smog. Everything here was someone else's trash first." },
	Wasteland = { name = "The Wastezone", lore = "Gas rolls off the walls. The best scrap is buried deepest." },
	Desert = { name = "The Dunes", lore = "The Smog Spire watches the sand from a mountain of stone." },
	Jungle = { name = "The Overgrowth", lore = "Redwoods older than the dome. Light reaches the floor in pieces." },
	Winter = { name = "The Frostline", lore = "Cold walls, colder crates. Break them before the wind breaks you." },
	MendersBase = { name = "Menders Headquarters", lore = "Polished floors and a spiked tower. The Menders keep the Heap in order." },
	ScrappersBase = { name = "The Scrappers' Den", lore = "Containers, floodlights and a sign you can read from the dome." },
}
-- Map wash colour per region (watercolour tints on the parchment map).
Theme.RegionTint = {
	TownDome = rgb(176, 132, 92),
	Town = rgb(160, 140, 104),
	Wasteland = rgb(112, 120, 70),
	Desert = rgb(214, 170, 96),
	Jungle = rgb(74, 128, 70),
	Winter = rgb(150, 182, 200),
	MendersBase = rgb(96, 186, 172),
	ScrappersBase = rgb(150, 98, 200),
}

-- Extra map markers. Positions are where MapGen placed them on 2026-10-24; the map prefers the
-- live model's pivot (`path` under Workspace) when it has streamed in.
Theme.MapPOI = {
	{ name = "The Smog Spire", x = -37, z = 2717, path = { "World", "Desert", "SmogSpire" } },
}

return Theme
