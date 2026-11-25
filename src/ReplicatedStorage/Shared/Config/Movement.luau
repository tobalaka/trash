--!strict
--[[
	Movement constants. Mirrors the Constants table in 02-Systems/Movement/Movement. Every value
	is a PROPOSAL until tuned in Studio. Durations follow the animation lengths so each move
	ends when its animation does.
]]

local Movement = {
	-- ground speeds (studs/s)
	WALK_SPEED = 16,
	RUN_SPEED = 26,
	CROUCH_SPEED = 8,
	SPRINT_DOUBLE_TAP = 0.3, -- s between W taps that start a sprint
	HARD_LAND_SPEED_CAP = 6, -- walk speed while recovering from a hard landing
	BASE_FOV = 70, -- the camera's field of view out of a sprint (Roblox's default; the intro's title camera
	-- uses 60 and is still active when the character spawns, so the live value can't be trusted then)
	SPRINT_FOV = 78, -- camera field of view while sprinting
	FOV_TWEEN = 0.25,
	-- sprint ramp (2026-10-25, EXPED Sprinting 26.5 -> FastSprint 45): keep running and it speeds up
	FAST_RUN_SPEED = 40,
	FAST_RUN_DELAY = 1.4, -- s of sprinting on the ground before the ramp starts
	FAST_RUN_RAMP = 1.0, -- s from run to fast run
	FAST_RUN_FOV = 86,

	-- jumping
	COYOTE_TIME = 0.12, -- a jump pressed this soon after walking off a ledge still counts
	DOUBLE_JUMPS = 1, -- per airtime; a wall jump or wall run refills it
	DOUBLE_JUMP_HEIGHT = 7, -- studs
	DOUBLE_JUMP_DELAY = 0.1, -- s after leaving the ground before the double jump is allowed
	DOUBLE_JUMP_DURATION = 0.4, -- the flip animation is 0.4 s

	-- roll / dash (Q). Roll animations are 0.52-0.53 s; air dashes 0.28 s.
	-- 2026-10-25 (EXPED feel): the dash snaps to full speed, holds it, then eases into a run
	-- instead of decaying from the first frame (~22 studs, was ~17).
	ROLL_COOLDOWN = 1.25, -- 2026-10-25: was 1.6; EXPED dashes every 1.25 s (air 1.2)
	ROLL_DURATION = 0.42,
	ROLL_SPEED = 66, -- peak
	ROLL_RAMP = 0.05, -- s to reach the peak from the current speed
	ROLL_HOLD = 0.22, -- s at the peak; after it an attack may cancel the slide-out
	ROLL_IFRAMES = 0.3,
	-- air dash: flies along the camera (pitch clamped) with gravity held off, then carries its
	-- momentum into a run (~29 studs, was ~9: it used to decay at once and gravity pulled it down)
	AIR_DASH_SPEED = 82,
	AIR_DASH_TIME = 0.22, -- s of the gravity-free burst
	AIR_DASH_CARRY = 0.3, -- s easing from 75% of the burst down to run speed, steerable
	AIR_DASH_PITCH = 0.45, -- most the camera's pitch may tilt the dash up or down (sine)
	AIR_ROLLS = 1, -- per airtime

	-- slide (Ctrl while sprinting)
	SLIDE_SPEED = 42,
	SLIDE_END_SPEED = 14,
	SLIDE_DURATION = 0.75,
	SLIDE_COOLDOWN = 0.8,

	-- vault (Space while moving into a low obstacle). The vault animation is 0.83 s.
	VAULT_PROBE_HEIGHT = 1.2, -- above the feet
	VAULT_REACH = 4,
	VAULT_MIN_HEIGHT = 1.5,
	VAULT_MAX_HEIGHT = 4.5,
	VAULT_CLEARANCE = 1.2,
	VAULT_FORWARD_SPEED = 18,
	VAULT_DURATION = 0.65,

	-- mantle (Space in the air facing a ledge, or reaching the top of a wall climb).
	-- Ledge animations are 0.40-0.47 s.
	LEDGE_CHECK_DIST = 2.5,
	LEDGE_REACH_UP = 3.5, -- above the head
	LEDGE_HIGH = 1.5, -- ledge this far above the root plays LedgeClimb, lower plays ClimbUp
	MANTLE_RISE_SPEED = 30,
	MANTLE_FORWARD_SPEED = 14,
	MANTLE_OVER_TIME = 0.15,
	MANTLE_MAX_TIME = 0.8,

	-- wall climb (2026-10-25, user: "pounces up in big boosts"): Space in the air facing a wall pounces up
	-- it, you cling for a moment, and Space again pounces again. Space with S held (or out of pounces)
	-- jumps off the wall, Ctrl lets go, reaching the top mantles onto it.
	WALLCLIMB_DIST = 3.2, -- reach to the wall ahead (was 2.2: you had to touch it, else Space double jumped)
	WALLCLIMB_POUNCES = 3, -- per airtime
	WALLCLIMB_POUNCE_SPEED = 62, -- upward speed at the start of a pounce, easing out (~10 studs a pounce)
	WALLCLIMB_POUNCE_TIME = 0.26,
	WALLCLIMB_CLING = 0.65, -- s holding on after a pounce, waiting for the next Space
	WALLCLIMB_SLIDE = 3, -- studs/s sliding down while clinging
	WALLCLIMB_STICK = 2, -- studs/s pressing into the wall

	-- wall jump (Space while wall climbing or wall running)
	WALLJUMP_OUT = 34,
	WALLJUMP_UP = 46,
	WALLJUMP_LOCK = 0.3, -- the wall jump animation is 0.37 s

	-- wall run (sprint into the air alongside a wall while holding W)
	WALLRUN_DIST = 2.6,
	WALLRUN_SPEED = 30,
	WALLRUN_LIFT = 10, -- upward speed at the start, easing to WALLRUN_SINK by the end
	WALLRUN_SINK = -6,
	WALLRUN_TIME = 1.2,
	WALLRUN_MIN_SPEED = 18, -- horizontal speed needed to start one
	WALLRUN_COOLDOWN = 0.35, -- before another wall run can start
	-- the easy start (2026-10-25): hold W + A or D at a wall you look at, no speed needed. In the air
	-- any wall ahead, diagonally ahead or beside you on that side; on the ground while sprinting, one
	-- ahead or diagonally ahead (a hop starts the run). The run heads toward the held side.
	WALLRUN_EASY_REACH = 4.2,
	WALLRUN_EASY_TIME = 1.6,
	WALLRUN_GROUND_HOP = 24, -- upward speed for a run started from the ground

	-- landing: downward speed at touchdown (studs/s)
	SOFT_LAND_SPEED = 35,
	HARD_LAND_SPEED = 80,
	HARD_LAND_SLOW = 0.35,
	DUST_LAND_SPEED = 60, -- landings this hard kick up dust

	DRIVE_FORCE = 100000,

	-- Tarp Glider (2026-10-25, EXPED Glider): equipped, hold Space while falling. Flies where the
	-- camera looks: looking down dives faster and sinks faster, looking up slows down.
	GLIDE_SPEED = 30,
	GLIDE_SINK = 5, -- studs/s down, level
	GLIDE_DIVE_SINK = 16, -- extra sink looking straight down
	GLIDE_MIN_FALL = 4, -- opens once falling faster than this
	GLIDE_CEILING = 2, -- never above where it opened + this
	GLIDE_EASE = 3.5, -- how fast the velocity follows the camera (1/s)

	-- Junk Board (EXPED Skateboard: camera-relative pushes 140 studs/s^2, friction 90, top 65)
	SKATE_ACCEL = 140,
	SKATE_FRICTION = 90,
	SKATE_MAX = 60,
	SKATE_HIP = 0.55, -- the board's height under the soles
	SKATE_OLLIE = 42, -- jump speed off the board
}

return Movement
