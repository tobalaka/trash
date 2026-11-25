--!strict
--[[
	Sounds - free Creator Store sound effects for combat and movement feedback.
	ProSoundEffects (Roblox's licensed library), lorenzosaudiostash and Axellatic, all verified
	creators. Swap any id here; nothing else references them.
]]

local Sounds = {
	-- Combat and movement use EXPED's own sounds (the EXPEDCOPY place, ReplicatedStorage.Sounds; 2026-10-25,
	-- trash-art docs/exped). Only its older public uploads load in this game: Fists1-4, Heavy1-4, Blunt1/5/10,
	-- Dash, Evaded, DeflectSFX and the slide are private to EXPED's creator (PreloadAsync: Failure), so those
	-- cues use EXPED's public alternatives. The ids replaced here are kept in the comments.
	Swing = { "rbxassetid://254904312", "rbxassetid://101467914599270" }, -- EXPED FistSwing, swing_punch_m (was 93311226362113, 111254855668531)
	SwingWeapon = { "rbxassetid://6230942062" }, -- EXPED FistSwing1, played lower and grittier for the broom and umbrella
	Hit = { "rbxassetid://6356172155", "rbxassetid://6356172654", "rbxassetid://6356173417", "rbxassetid://6356174042" }, -- EXPED Blunt6-9, its fists' HitSound family (was 126976659766267, 9113520887)
	HeavyHit = { "rbxassetid://3763473874", "rbxassetid://3763474082", "rbxassetid://3763474273", "rbxassetid://3763474469", "rbxassetid://4306987778" }, -- EXPED HeavyPunch1-5 (was 132555084427990)
	Slam = { "rbxassetid://100457174196725" }, -- EXPED downslam (was 79476956608476)
	Block = { "rbxassetid://7029643469", "rbxassetid://4306994923", "rbxassetid://4056972363", "rbxassetid://4306995205" }, -- EXPED Block, BlockPunch1-3 (was 9116673944)
	Parry = { "rbxassetid://7850147408", "rbxassetid://7850131259", "rbxassetid://7850130409" }, -- EXPED Parry1-3 (was 9125672726)
	Break = { "rbxassetid://8595983255" }, -- EXPED GuardBreak (was 9120801590)
	Dash = { "rbxassetid://6002235044" }, -- EXPED Dash2 (its Dash is private; was 137322083927464)
	AirDash = { "rbxassetid://6002235044" }, -- EXPED Dash2, a little higher in the air
	Jump = { "rbxassetid://6002235044" }, -- double jump / wall jump: a short, high Dash2
	Counter = { "rbxassetid://3763473874", "rbxassetid://3763474273", "rbxassetid://4306987778" }, -- EXPED HeavyPunch (was 132555084427990)
	PerfectDodge = { "rbxassetid://92850813205222" }, -- EXPED EndFlashStep (its Evaded is private; was 9120972321)
	WallSplat = { "rbxassetid://100457174196725" }, -- EXPED downslam (was 79476956608476)
	Feint = { "rbxassetid://9119744642" }, -- EXPED Feint
	WallClimb = { "rbxassetid://180239559" }, -- EXPED RockStep (its wall climb plays it on each hold)
	-- EXPED pass (2026-10-25): crit, knocked / grip / carry, anti-gank. Load-checked in Play: EXPED's death
	-- screen sound, Heavy4, Knife1 and Reinforced are private, so these use its public recordings.
	CritWindup = { "rbxassetid://7060929022" }, -- EXPED GenericSpell (Astral at 1.45): the crit's charge
	CritHit = { "rbxassetid://4306987778", "rbxassetid://3763474273" }, -- EXPED HeavyPunch5 / 3
	GripPunch = { "rbxassetid://636494529" }, -- EXPED Smack
	Execute = { "rbxassetid://4306987778" }, -- EXPED HeavyPunch5
	Knocked = { "rbxassetid://355718070" }, -- EXPED Off
	GetUp = { "rbxassetid://3120909354" }, -- EXPED Powerup
	Carry = { "rbxassetid://636494529" }, -- EXPED Smack, low
	Drop = { "rbxassetid://100457174196725" }, -- EXPED downslam, quiet
	Gank = { "rbxassetid://7060929022" }, -- EXPED Astral (vol 0.1, speed 4)
	Death = { "rbxassetid://355718070" }, -- EXPED Off, slow: the death screen's sting
	RelicCast = { "rbxassetid://9120972444" },
	RelicImpact = { "rbxassetid://132555084427990" },
	RelicGuard = { "rbxassetid://9125672726" },
	RelicHeal = { "rbxassetid://9125672726" }, -- the short I-beam ring, played pitched up (a soft chime)
	-- Mobs (Client/Mobs/MobFx) keep the recordings their absolute volumes and pitches were tuned for
	Mob = {
		Swing = { "rbxassetid://93311226362113", "rbxassetid://111254855668531" },
		Hit = { "rbxassetid://126976659766267", "rbxassetid://9113520887" },
		HeavyHit = { "rbxassetid://132555084427990" },
		Slam = { "rbxassetid://79476956608476" },
		Parry = { "rbxassetid://9125672726" },
		Break = { "rbxassetid://9120801590" },
		Dash = { "rbxassetid://137322083927464" },
	} :: { [string]: { string } },
	UI = { "rbxassetid://111174530730534" }, -- EXPED skill tree Click (was rbxasset://sounds/volume_slider.ogg)
	UIHover = { "rbxassetid://6333717580" }, -- EXPED Hover

	-- Sound-group gains keep footsteps, combat and the background independently adjustable.
	-- Player volume sliders multiply these mix levels, so 1 is the intended full mix.
	Mix = {
		Master = 0.8,
		SFX = 0.75,
		Music = 0.65,
		Ambience = 0.7,
		LegacyCharacter = 0.48,
		Footsteps = 0.6,
		Landing = 0.5,
		Jumping = 0.5,
		MenuAmbience = 0.45,
		CombatMusic = 0.45,
		MusicWorld = 0.2, -- music levels per mode (Client/Audio music director)
		MusicMenu = 0.25,
		MusicCombat = 0.28,
		MusicBoss = 0.32,
		CombatMusicSeconds = 10, -- combat music keeps going this long after the last exchange
		Crossfade = 1.6,
		UpdateInterval = 0.5,
		RollOffMinDistance = 7,
		RollOffMaxDistance = 85,
		MaxVoices = 32,
		VoiceLifetime = 8,
		LoadTimeout = 0.35,
		MinCueInterval = 0.025,
		CombatDuckSeconds = 2.5,
		PitchMin = 0.96,
		PitchMax = 1.04,
	},
	-- EXPED's own relative levels (its HeavyPunch and Feint recordings are quiet: EXPED plays them at 10 and 4).
	-- Up to 10 like Sound.Volume; the Master/SFX groups scale everything after this.
	Volumes = {
		Swing = 0.45, SwingWeapon = 0.5, Hit = 0.62, HeavyHit = 7, Slam = 0.5,
		Block = 0.38, Parry = 0.75, Break = 1.1, Dash = 0.45, AirDash = 0.45, Jump = 0.28,
		Counter = 7, PerfectDodge = 0.45, WallSplat = 0.6, Feint = 2.5, WallClimb = 0.55,
		RelicCast = 0.28, RelicImpact = 0.4, RelicGuard = 0.3, RelicHeal = 0.14,
		UI = 0.3, UIHover = 0.1,
		CritWindup = 0.35, CritHit = 8, GripPunch = 0.6, Execute = 9, Knocked = 0.4, GetUp = 0.22,
		Carry = 0.4, Drop = 0.3, Gank = 0.25, Death = 0.5,
	},
	-- EXPED bakes a PlaybackSpeed into each recording (Dash2 1.35, Block 1.3, HeavyPunch2 1.45, EndFlashStep 2):
	-- per-id speed, then a per-cue multiplier when one recording serves two cues
	Tuning = {
		["rbxassetid://6002235044"] = { speed = 1.35 },
		["rbxassetid://7029643469"] = { speed = 1.3 },
		["rbxassetid://3763474082"] = { speed = 1.45 },
		["rbxassetid://92850813205222"] = { speed = 2 },
	} :: { [string]: { speed: number?, volume: number? } },
	Speeds = {
		SwingWeapon = 0.82, AirDash = 1.15, Jump = 1.3,
		CritWindup = 1.45, Knocked = 2, Carry = 0.8, Gank = 4, Death = 1, GetUp = 1.2,
	} :: { [string]: number },
	-- DistortionSoundEffect level per cue (EXPED thickens its blocks and weapon swings with 0.25)
	Distortion = { Block = 0.25, SwingWeapon = 0.2, CritHit = 0.3, Execute = 0.35 } :: { [string]: number },
	-- Optional per-cue fallback ids for when a remote cue cannot load.
	-- (2026-10-26: the Roblox jump/land sounds used here before were the "wrong sounds"; a cue
	-- whose asset fails to load now stays silent unless it names a fitting fallback.)
	Fallbacks = {} :: { [string]: string },
	-- Free Creator Store library recordings; checked against ProSoundEffects/APMOfficial
	-- listings on 2026-10-25. Their ids are centralized so a moderated asset is easy to replace.
	Background = {
		Wind = "rbxassetid://9114057128", -- ProSoundEffects: Desert Wind Whistley Light Gusts 2
		Industry = "rbxassetid://9112812234", -- ProSoundEffects: Landing Craft Interior 2 (loop)
		Forest = "rbxassetid://9116258071", -- ProSoundEffects: Leaves Rustle Wind Blowing Through Trees 1
	},
	-- Music tracks per mode (APMOfficial, Roblox-licensed). The zone lists are keyed by
	-- MusicZones; Combat plays after this player trades blows, Boss against the Junk Ram or
	-- during a Turf War, Menu on the intro and while a window is open.
	Music = {
		Menu = { "rbxassetid://9047833850", "rbxassetid://1846216152" }, -- Kept In Suspense (Ambient), Moving Slow B
		Town = { "rbxassetid://1840769906", "rbxassetid://1836393773" }, -- Groundwork (A), Step Forward
		Wild = { "rbxassetid://1843748008", "rbxassetid://1845746363", "rbxassetid://9047833850" }, -- Moving Drone 78, Slow Motion, Kept In Suspense
		Combat = { "rbxassetid://1840266155", "rbxassetid://1846129562" }, -- Conflict (A), Hitting Hard B
		Boss = { "rbxassetid://9045720406", "rbxassetid://9048541013" }, -- Path Of Destruction, Battleground
	},
	MusicZones = {
		Default = "Wild",
		TownDome = "Town",
		Town = "Town",
		MendersBase = "Town",
		ScrappersBase = "Town",
		Wasteland = "Wild",
		Desert = "Wild",
		Jungle = "Wild",
		Winter = "Wild",
	},
	-- {wind, industrial hum, leaves}; no competing foreground sound in safe towns.
	Regions = {
		Default = { 0.12, 0.025, 0 },
		TownDome = { 0.035, 0.07, 0 },
		Town = { 0.08, 0.08, 0 },
		Wasteland = { 0.17, 0.07, 0 },
		Desert = { 0.2, 0, 0 },
		Jungle = { 0.05, 0, 0.15 },
		Winter = { 0.21, 0.015, 0 },
		MendersBase = { 0.035, 0.08, 0 },
		ScrappersBase = { 0.06, 0.11, 0 },
	},
}

return Sounds
