--!strict
--[[
	Config.Townsfolk - ambient town crowd (client-only, cosmetic). Mirrors the Constants table in
	the vault note 03-Content/NPCs/Townsfolk.md; keep them in sync.

	Distances are studs, times seconds, angles degrees.
]]

local Townsfolk = {}

Townsfolk.SEED = 7341 -- population seed: every client builds the same crowd

-- population
Townsfolk.WALKERS = 320 -- walkers spread over the whole town graph
Townsfolk.PAIR_CHANCE = 0.25 -- a walker brings a companion who walks beside it
Townsfolk.KID_CHANCE = 0.12
Townsfolk.CARRY_CHANCE = 0.22 -- a walker carries a crate, a sack or a bucket
Townsfolk.VENDOR_SHARE = 0.6 -- share of Vendor spots that get a shopkeeper
Townsfolk.SHOPPER_SHARE = 0.7 -- share of Shopper spots (in front of stalls)
Townsfolk.LOITER_SHARE = 0.55 -- share of baked loiter spots that get a chatting group
Townsfolk.LOITER_MIN, Townsfolk.LOITER_MAX = 2, 3 -- group size
Townsfolk.LOITER_RING = 1.7 -- group members stand this far from the group centre

-- streaming: only the agents near the camera get a body
Townsfolk.SPAWN_RADIUS = 230
Townsfolk.DESPAWN_RADIUS = 260
Townsfolk.MAX_ACTIVE = 48
Townsfolk.SPAWNS_PER_FRAME = 3
Townsfolk.SCAN_INTERVAL = 0.5
Townsfolk.GRID_CELL = 64 -- spatial index for standing agents

-- level of detail: frames between pose updates by distance
Townsfolk.LOD_NEAR = 90 -- every frame inside this
Townsfolk.LOD_MID = 160 -- every LOD_MID_EVERY frames inside this, LOD_FAR_EVERY beyond
Townsfolk.LOD_MID_EVERY = 2
Townsfolk.LOD_FAR_EVERY = 4
Townsfolk.BEHIND_CAMERA_SKIP = 40 -- agents behind the camera and farther than this update at the far rate

-- walking (deterministic legs from the server clock: out, pause, back, idle at home)
Townsfolk.LEG_TIME = 120
Townsfolk.SPEED_MIN, Townsfolk.SPEED_MAX = 5.5, 8
Townsfolk.KID_SPEED = 9.5
Townsfolk.PAUSE_MIN, Townsfolk.PAUSE_MAX = 4, 14
Townsfolk.HOME_IDLE_MIN = 3
Townsfolk.LEG_MIN_FRACTION = 0.45 -- shortest leg as a share of the longest that fits LEG_TIME
Townsfolk.MAX_HOPS = 60
Townsfolk.STRAIGHT_BIAS = 3 -- how strongly a walker keeps its heading at a junction
Townsfolk.SIDE_MIN, Townsfolk.SIDE_MAX = 0.8, 4 -- keep-right offset from the street centre line
Townsfolk.PAIR_GAP = 2.2 -- companion walks this far toward the centre line
Townsfolk.PAIR_LAG = 0.35 -- companion trails by this much time
Townsfolk.HEADING_LOOK = 3 -- studs ahead/behind used to round corners
Townsfolk.TURN_RATE = 6 -- radians per second a body turns toward its heading

-- look and react (local to each client)
Townsfolk.LOOK_RADIUS = 14
Townsfolk.LOOK_LIMIT = 70
Townsfolk.WAVE_RADIUS = 22 -- a shopkeeper waves at a player this close
Townsfolk.WAVE_TIME = 2.2
Townsfolk.WAVE_COOLDOWN = 9
Townsfolk.GESTURE_SLOT = 5 -- standing agents pick a gesture per slot of this many seconds

-- animation
Townsfolk.STRIDE = 2.5 -- studs per step at scale 1
Townsfolk.LEG_SWING = 32
Townsfolk.ARM_SWING = 26
Townsfolk.BOB = 0.16
Townsfolk.KID_BOB = 0.3
Townsfolk.WALK_LEAN = 4
Townsfolk.BREATH = 0.04
Townsfolk.SMOOTHING = 12 -- per second; pose channels ease toward their goals
Townsfolk.KID_SCALE = 0.68
Townsfolk.ADULT_SCALE_MIN, Townsfolk.ADULT_SCALE_MAX = 0.92, 1.08

return Townsfolk
