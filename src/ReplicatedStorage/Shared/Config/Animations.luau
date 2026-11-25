--!strict
--[[
	Animations - every animation the movement and combat code plays.

	id        Published asset id, "rbxassetid://<number>"; looked up in PUBLISHED by the studio
	          path. "" means not published yet.
	studio    "<Source>/<name>" of the KeyframeSequence in the Studio AnimSaves. Used only in
	          Studio playtests while id is "", so moves can be tested before publishing.
	          Sources: Rig = Workspace.Rig.AnimSaves, R6 = ReplicatedStorage["Anims r6"].AnimSaves.
	fallback  Another entry to play when this one has neither.
	priority / looped override whatever the KeyframeSequence was saved with.

	Where the saves come from (all in Workspace.Rig.AnimSaves):
	  *.rbxm, "Wall Ledge V3"  the user's set (2026-10-24)
	  Pack_*   free Creator Store pack "High Quality R6 Combat Animations" (asset 125909948357929)
	  TRASH_*  authored for this game by TRASH-Combat/tools/AuthorAnims.luau

	Unpublished entries play their saved R6 poses in both Studio and live servers.

	Publishing (2026-10-26): tools/ExportAnims.luau serializes the saves, tools/upload_anims.js
	writes .rbxmx files and uploads them as Animation assets under the user's account (ids logged
	in TRASH-Assets/anims/uploaded.jsonl). The Vault save is a CurveAnimation, so it was sampled
	at 30 fps into a KeyframeSequence (TRASH_VaultSampled) for upload. Re-export and re-upload an
	animation after editing its save: Roblox can't update an animation asset's content.
]]

export type Def = {
	id: string,
	studio: string?,
	fallback: string?,
	priority: Enum.AnimationPriority,
	looped: boolean,
}

local P = Enum.AnimationPriority

-- published Animation assets by save path (TRASH-Assets/anims/uploaded.jsonl)
local PUBLISHED: { [string]: string } = {
	["Rig/Climb.rbxm"] = "rbxassetid://72756863272565",
	["Rig/ClimbUp.rbxm"] = "rbxassetid://140357236955063",
	["Rig/CrouchIdle.rbxm"] = "rbxassetid://110656274301809",
	["Rig/CrouchWalk.rbxm"] = "rbxassetid://93778114203245",
	["Rig/Falling.rbxm"] = "rbxassetid://119649290346414",
	["Rig/Idle.rbxm"] = "rbxassetid://78427731555542",
	["Rig/Jumping.rbxm"] = "rbxassetid://75136583397874",
	["Rig/Landing.rbxm"] = "rbxassetid://117564557889368",
	["Rig/Pack_AirDashB"] = "rbxassetid://75792264514523",
	["Rig/Pack_AirDashF"] = "rbxassetid://113098229760518",
	["Rig/Pack_AirDashL"] = "rbxassetid://75513414769518",
	["Rig/Pack_AirDashR"] = "rbxassetid://88165932467990",
	["Rig/Pack_Block"] = "rbxassetid://127414799501934",
	["Rig/Pack_BlockHit1"] = "rbxassetid://113111745148391",
	["Rig/Pack_BlockHit2"] = "rbxassetid://88459164305217",
	["Rig/Pack_BlockHit3"] = "rbxassetid://107003643957238",
	["Rig/Pack_Deflect"] = "rbxassetid://93325612610596",
	["Rig/Pack_DownSlam"] = "rbxassetid://117371551067578",
	["Rig/Pack_GuardBroken"] = "rbxassetid://136424367333862",
	["Rig/Pack_HitReact1"] = "rbxassetid://115964798450914",
	["Rig/Pack_HitReact2"] = "rbxassetid://110651372117053",
	["Rig/Pack_HitReact3"] = "rbxassetid://71108447179322",
	["Rig/Pack_HitReact4"] = "rbxassetid://91567913801927",
	["Rig/Pack_HitReact5"] = "rbxassetid://136904866793899",
	["Rig/Pack_LedgeHang"] = "rbxassetid://81057495543858",
	["Rig/Pack_M1_1"] = "rbxassetid://112512387933559",
	["Rig/Pack_M1_2"] = "rbxassetid://131307367548157",
	["Rig/Pack_M1_3"] = "rbxassetid://94118803474667",
	["Rig/Pack_M1_4"] = "rbxassetid://70802593754802",
	["Rig/Pack_M1_5"] = "rbxassetid://98392406480935",
	["Rig/Pack_Parried"] = "rbxassetid://108528134058455",
	["Rig/Pack_Uptilt"] = "rbxassetid://111733471680719",
	["Rig/Pack_WallRunL"] = "rbxassetid://109423485387093",
	["Rig/Pack_WallRunR"] = "rbxassetid://80217764619226",
	["Rig/RollBackward.rbxm"] = "rbxassetid://71518338354065",
	["Rig/RollForward.rbxm"] = "rbxassetid://76228889633659",
	["Rig/RollLeft.rbxm"] = "rbxassetid://74209591597189",
	["Rig/RollRight.rbxm"] = "rbxassetid://126087587300668",
	["Rig/Running.rbxm"] = "rbxassetid://76741482220200",
	["Rig/Sliding.rbxm"] = "rbxassetid://139761725580009", -- re-uploaded with a second keyframe (one-frame clips have no length)
	["Rig/SoftLanding.rbxm"] = "rbxassetid://101619501903724",
	["Rig/SwimmingIdle.rbxm"] = "rbxassetid://104417120646683",
	["Rig/TRASH_Bandage"] = "rbxassetid://99914657584343",
	["Rig/TRASH_DoubleJump"] = "rbxassetid://77753000102654",
	["Rig/TRASH_Drink"] = "rbxassetid://127122803453025",
	["Rig/TRASH_Eat"] = "rbxassetid://105385502296552",
	["Rig/TRASH_Grab"] = "rbxassetid://116195369835759",
	["Rig/TRASH_Grabbed"] = "rbxassetid://137593174661625",
	["Rig/TRASH_HelpUp"] = "rbxassetid://98597759142663",
	["Rig/TRASH_Salvage"] = "rbxassetid://124299382478528",
	["Rig/TRASH_ThrowLeft"] = "rbxassetid://133483155850858",
	["Rig/TRASH_ThrowRight"] = "rbxassetid://77738982362179",
	["Rig/TRASH_WallSplat"] = "rbxassetid://105724183677122",
	["Rig/Uppercut.rbxm"] = "rbxassetid://117914148934012",
	["Rig/Vault.rbxm"] = "rbxassetid://135288490223768",
	["Rig/Walking.rbxm"] = "rbxassetid://93993163652800",
	["Rig/Wall Ledge V3"] = "rbxassetid://131684560262457",
	["Rig/WallBounce.rbxm"] = "rbxassetid://123699911465199",
}

local function def(studio: string?, priority: Enum.AnimationPriority, looped: boolean, fallback: string?): Def
	local id = if studio then PUBLISHED[studio] else nil
	return { id = id or "", studio = studio, priority = priority, looped = looped, fallback = fallback }
end

local Animations: { [string]: Def } = {
	-- locomotion
	Idle = def("Rig/Idle.rbxm", P.Idle, true),
	Walk = def("Rig/Walking.rbxm", P.Movement, true),
	Run = def("Rig/Running.rbxm", P.Movement, true),
	Jump = def("Rig/Jumping.rbxm", P.Movement, false),
	Fall = def("Rig/Falling.rbxm", P.Movement, true),
	SoftLand = def("Rig/SoftLanding.rbxm", P.Action, false),
	Land = def("Rig/Landing.rbxm", P.Action, false),
	CrouchIdle = def("Rig/CrouchIdle.rbxm", P.Movement, true),
	CrouchWalk = def("Rig/CrouchWalk.rbxm", P.Movement, true),
	Climb = def("Rig/Climb.rbxm", P.Movement, true), -- trusses and ladders (Humanoid climbing)
	SwimIdle = def("Rig/SwimmingIdle.rbxm", P.Movement, true),

	-- movement actions
	RollForward = def("Rig/RollForward.rbxm", P.Action2, false),
	RollBackward = def("Rig/RollBackward.rbxm", P.Action2, false),
	RollLeft = def("Rig/RollLeft.rbxm", P.Action2, false),
	RollRight = def("Rig/RollRight.rbxm", P.Action2, false),
	-- forward air dash: the user's AirRoll once its id is pasted, else the pack's dash
	-- the Animation in AnimSaves (rbxassetid://132146135472531) does not load for this place's
	-- owner (checked 2026-10-26), so the pack's air dash plays until the user re-publishes it
	AirRoll = def(nil, P.Action2, false, "AirDashForward"),
	AirDashForward = def("Rig/Pack_AirDashF", P.Action2, false),
	AirDashBackward = def("Rig/Pack_AirDashB", P.Action2, false),
	AirDashLeft = def("Rig/Pack_AirDashL", P.Action2, false),
	AirDashRight = def("Rig/Pack_AirDashR", P.Action2, false),
	DoubleJump = def("Rig/TRASH_DoubleJump", P.Action2, false),
	Slide = def("Rig/Sliding.rbxm", P.Action, true),
	Vault = def("Rig/Vault.rbxm", P.Action2, false, "LedgeClimb"),
	LedgeClimb = def("Rig/Wall Ledge V3", P.Action2, false),
	ClimbUp = def("Rig/ClimbUp.rbxm", P.Action2, false),
	WallClimb = def("Rig/Climb.rbxm", P.Action2, true),
	WallHang = def("Rig/Pack_LedgeHang", P.Action2, false),
	WallJump = def("Rig/WallBounce.rbxm", P.Action2, false),
	WallRunLeft = def("Rig/Pack_WallRunL", P.Action2, true),
	WallRunRight = def("Rig/Pack_WallRunR", P.Action2, true),

	-- attacks. Each M1 lands on its animation's "Hit" marker (Shared/Config/Combat M1_HITS).
	M1_1 = def("Rig/Pack_M1_1", P.Action3, false),
	M1_2 = def("Rig/Pack_M1_2", P.Action3, false),
	M1_3 = def("Rig/Pack_M1_3", P.Action3, false),
	M1_4 = def("Rig/Pack_M1_4", P.Action3, false),
	M1_5 = def("Rig/Pack_M1_5", P.Action3, false),
	Uppercut = def("Rig/Uppercut.rbxm", P.Action3, false),
	AerialSlam = def("Rig/Pack_DownSlam", P.Action3, false),
	Grab = def("Rig/TRASH_Grab", P.Action3, false),
	-- EXPED pass (2026-10-25), authored by trash-art src_mirror/_tools/author_anims.luau
	Crit = def("Rig/TRASH_Crit", P.Action3, false), -- coil, then a lunging straight (hit at 0.55 of 1.0)
	Grip = def("Rig/TRASH_Grip", P.Action3, false), -- three punches down on a knocked body (1.6 s)
	Carry = def("Rig/TRASH_Carry", P.Action2, true), -- right arm up holding the body (legs keep walking)
	Carried = def("Rig/TRASH_Carried", P.Action4, true), -- limp over the shoulder
	Glide = def("Rig/TRASH_Glide", P.Action2, true), -- hands on the glider's bar overhead
	Skate = def("Rig/TRASH_Skate", P.Action2, true), -- side stance on the board
	ThrowUp = def("Rig/Pack_Uptilt", P.Action3, false),
	ThrowLeft = def("Rig/TRASH_ThrowLeft", P.Action3, false),
	ThrowRight = def("Rig/TRASH_ThrowRight", P.Action3, false),
	Bury = def("Rig/Pack_DownSlam", P.Action3, false),

	-- defence and reactions (Action4 so they cut through a swing)
	Block = def("Rig/Pack_Block", P.Action2, true),
	BlockHit1 = def("Rig/Pack_BlockHit1", P.Action4, false),
	BlockHit2 = def("Rig/Pack_BlockHit2", P.Action4, false),
	BlockHit3 = def("Rig/Pack_BlockHit3", P.Action4, false),
	Deflect = def("Rig/Pack_Deflect", P.Action4, false),
	Parried = def("Rig/Pack_Parried", P.Action4, false),
	GuardBroken = def("Rig/Pack_GuardBroken", P.Action4, true),
	HitReact1 = def("Rig/Pack_HitReact1", P.Action4, false),
	HitReact2 = def("Rig/Pack_HitReact2", P.Action4, false),
	HitReact3 = def("Rig/Pack_HitReact3", P.Action4, false),
	HitReact4 = def("Rig/Pack_HitReact4", P.Action4, false),
	HitReact5 = def("Rig/Pack_HitReact5", P.Action4, false),
	Grabbed = def("Rig/TRASH_Grabbed", P.Action4, true),
	WallSplat = def("Rig/TRASH_WallSplat", P.Action4, false),

	-- everyday actions (2026-10-26): salvage piles and helping allies up loop while the prompt
	-- is held (Progression WorldFx); items play when used (UI Inventory)
	Salvage = def("Rig/TRASH_Salvage", P.Action, true),
	HelpUp = def("Rig/TRASH_HelpUp", P.Action, true),
	Eat = def("Rig/TRASH_Eat", P.Action, false),
	Drink = def("Rig/TRASH_Drink", P.Action, false),
	Bandage = def("Rig/TRASH_Bandage", P.Action, false),
}

return Animations
