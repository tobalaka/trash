--!strict
--[[
	Combat constants. Mirrors the Constants tables in 02-Systems/Combat (M1-Combo, Block-Parry,
	Posture, Uppercut, Directional-Grab, Ragdoll). Every value is a PROPOSAL until tuned in
	Studio; change the vault note and this file together. Timings marked "marker" come from the
	animation's own KeyframeMarker, so the hit lands on the frame the animation shows it.
]]

local Combat = {
	-- M1 combo (M1-Combo). windup = the "Hit" marker of M1_n, length = its animation length.
	COMBO_LENGTH = 5, -- hit 5 needs the "FinalUpgradeUnlocked" player attribute, else the chain is 4
	M1_HITS = {
		{ windup = 0.22, length = 0.52 },
		{ windup = 0.28, length = 0.67 },
		{ windup = 0.27, length = 0.70 },
		{ windup = 0.18, length = 0.62 },
		{ windup = 0.15, length = 0.82 }, -- heavy flourish
	},
	M1_BASE_DAMAGE = 8,
	FINISHER_DAMAGE = 10, -- the last hit of a 4-hit chain
	HEAVY_DAMAGE = 13, -- hit 5, the heavy flourish
	-- true combos (2026-10-26): a hit stuns until the next hit of the chain lands, plus this pad.
	-- Pressing late still drops the chain.
	COMBO_STUN_PAD = 0.12,
	M1_PUSH = 7, -- each M1 nudges the target forward (studs/s) so the chain stays in range
	M1_LUNGE = 9, -- and steps the attacker in (client)
	M1_LUNGE_TIME = 0.1,
	COMBO_WINDOW = 0.45, -- after a hit's animation ends, the next press continues the chain
	COMBO_RESET = 1.2, -- after the final hit starts, the next chain may begin
	FLOURISH_POSTURE_DAMAGE = 25,
	M1_HITSTUN = 0.4,
	FINISHER_KNOCKBACK = 28, -- the last hit of a chain pushes the target away (studs/s)
	FINISHER_STUN = 0.7,
	ATTACK_WALK_SPEED = 14, -- 2026-10-25: was 10; EXPED keeps 20.5 while punching, so chases hold
	INPUT_BUFFER = 0.14, -- accepts an M1 press in the last 140 ms of recovery
	HITSTOP = 0.06, -- both fighters' animations freeze this long on a clean hit (client only)
	HEAVY_HITSTOP = 0.11, -- finishers, launches, slams, counters and wall splats

	-- counter hit (2026-10-26): hitting someone during their own windup
	COUNTER_DAMAGE_MULT = 1.3,
	COUNTER_STUN_BONUS = 0.25,

	-- perfect dodge (2026-10-26): a roll whose i-frames began this close before the hit
	PERFECT_DODGE_WINDOW = 0.15, -- refunds the roll cooldown

	-- launcher cancel (2026-10-26): after landing M1 hit 2 or later, the uppercut cancels the
	-- swing's recovery
	CANCEL_MIN_HIT = 2,
	CANCEL_WINDOW = 0.5, -- seconds after the hit landed

	-- wall splat (2026-10-26): a finisher or side throw into a wall that does not break
	WALL_SPLAT_RANGE = 7, -- studs the body may travel to the wall
	WALL_SPLAT_DAMAGE = 5,
	WALL_SPLAT_STUN = 0.8,

	-- feint (Mouse2 during a windup)
	FEINT_COOLDOWN = 2.0,
	FEINT_RECOVERY = 0.15,

	-- aerial (Mouse1 in the air): the DownSlam animation, "Hit" marker at 0.47 s of 0.83 s
	AERIAL_WINDUP = 0.47,
	AERIAL_LENGTH = 0.83,
	AERIAL_DAMAGE = 10,
	AERIAL_SLAM = 60, -- downward studs/s on the target
	AERIAL_STUN = 0.8,
	AERIAL_COOLDOWN = 2.5,

	-- hit detection: a box in front of the attacker, checked on the server
	HITBOX_RANGE = 6,
	HITBOX_WIDTH = 7, -- 2026-10-25: was 5 x 6; EXPED's fist box is 8 x 7 x 8, 4 studs ahead
	HITBOX_HEIGHT = 7,
	HITBOX_LAG_PAD = 1.5, -- extra reach for latency
	AERIAL_HITBOX_DROP = 3, -- the aerial box sits this much lower

	-- block and parry (Block-Parry)
	PARRY_WINDOW = 0.20,
	PARRY_COOLDOWN = 0.8,
	BLOCK_DAMAGE_REDUCTION = 0.70,
	BLOCK_POSTURE_DRAIN_MULT = 1.5,
	BLOCK_ANGLE = 120, -- degrees of frontal cone a block covers
	BLOCK_WALK_SPEED = 11, -- 2026-10-25: was 8; EXPED blocks at 11.5
	PARRY_ATTACKER_STUN = 1.5,
	LATENCY_FORGIVENESS = 0.10,
	MAX_TIMESTAMP_SKEW = 0.35, -- how far before the server received a press its timestamp may claim

	-- posture (Posture)
	POSTURE_MAX = 100,
	POSTURE_REGEN_RATE = 10,
	POSTURE_REGEN_DELAY = 2.0,
	POSTURE_BREAK_STUN = 2.0,
	STUN_WALK_SPEED = 4,

	-- uppercut (Ctrl + Mouse1). The animation's "HitWindow" marker is at 0.5 s of 0.88 s.
	UPPERCUT_COOLDOWN = 6,
	UPPERCUT_WINDUP = 0.5,
	UPPERCUT_RECOVERY = 0.4,
	UPPERCUT_DAMAGE = 12,
	UPPERCUT_POSTURE_DAMAGE = 20,
	UPPERCUT_LAUNCH = 45, -- upward studs/s on the target
	UPPERCUT_STUN = 1.0,
	PARRIED_UPPERCUT_KNOCKBACK = 30, -- both players, studs/s
	UPPERCUT_SLIDE_LUNGE = 30, -- out of a slide the uppercut carries the slide forward (studs/s, client)
	UPPERCUT_SLIDE_LUNGE_TIME = 0.28,

	-- air combo (2026-10-25, EXPED): a landed uppercut lifts BOTH fighters; M1s in the air keep the
	-- target floating, and the chain's last hit spikes it into the ground
	LAUNCH_HEIGHT = 13, -- studs both fighters rise
	LAUNCH_RISE = 0.3, -- seconds of that rise
	JUGGLE_HOLD = 0.9, -- a juggled body floats this long after the launch and after each air hit
	JUGGLE_PUSH = 3, -- air hits nudge the target forward (studs/s) so it stays in front
	-- the air finisher drives the target down AND away on a diagonal (user: "like the hypotenuse of a
	-- triangle"), about 45 degrees: the crater opens where that line meets the ground
	SPIKE_SPEED = 75, -- downward part (studs/s)
	SPIKE_FORWARD = 70, -- forward part, along the attacker's facing (studs/s)
	SPIKE_STUN = 1.1,
	SPIKE_DAMAGE = 12,

	-- critical (T, EXPED's per-weapon crit): a slow lunging heavy. Red flash at the start so it can
	-- be read; blockable (crushes posture), parryable and feintable.
	CRIT_WINDUP = 0.55,
	CRIT_LENGTH = 1.0,
	CRIT_DAMAGE = 18,
	CRIT_POSTURE_DAMAGE = 45, -- on top of the block drain
	CRIT_KNOCKBACK = 55,
	CRIT_STUN = 1.0,
	CRIT_COOLDOWN = 7,
	CRIT_LUNGE = 26, -- the attacker steps in during the windup (studs/s, client)
	CRIT_LUNGE_TIME = 0.22,

	-- knocked, grip and carry (2026-10-25, EXPED / Deepwoken): players and training dummies at 0
	-- health go down instead of dying. An enemy can grip them (V, an execution) or carry them (H);
	-- left alone they get back up.
	KNOCK_DURATION = 12,
	KNOCK_GETUP_HEALTH = 0.25, -- of MaxHealth
	KNOCK_GETUP_GRACE = 2.0, -- i-frames after getting up
	GRIP_RANGE = 7.5, -- a knocked ragdoll rolls; measured to its root
	GRIP_TIME = 1.6, -- the execution's length; a hit on the gripper stops it
	CARRY_RANGE = 7.5,
	CARRY_WALK_SPEED = 12,
	CARRY_COOLDOWN = 1.0,

	-- anti-gank (EXPED GankBuff): hit by GANK_ATTACKERS different fighters within GANK_WINDOW
	GANK_ATTACKERS = 2,
	GANK_WINDOW = 5,
	GANK_DURATION = 4, -- refreshed while the gank goes on
	GANK_DAMAGE_TAKEN = 0.7,
	GANK_POSTURE_TAKEN = 0.6,

	-- directional grab (G + W/A/S/D). Grabs go through blocks; hits during startup or a roll beat them.
	GRAB_RANGE = 5,
	GRAB_STARTUP = 0.3, -- the grab animation's reach
	GRAB_COOLDOWN = 5,
	GRAB_WHIFF_RECOVERY = 0.45,
	GRAB_HOLD_DISTANCE = 3, -- victim held this far in front
	THROW_RELEASE = { Up = 0.42, Left = 0.3, Right = 0.3, Down = 0.47 }, -- markers of each throw animation
	THROW_RECOVERY = 0.35,
	THROW_DAMAGE = 10,
	THROW_UP_VELOCITY = 55, -- 70 rose 26 studs in testing; 55 should rise about 16
	FLING_VELOCITY = 75,
	FLING_LIFT = 25,
	BURY_VELOCITY = 50,
	FLING_RAGDOLL_DURATION = 1.6,
	BURY_RAGDOLL_DURATION = 2.0,
	BURY_FREE_PARRY = 3.0, -- after getting up from a bury, the next hit within this is parried
	-- ragdoll (Ragdoll)
	RAGDOLL_MAX_DURATION = 4,

	KNOCKBACK_TIME = 0.2,
	KNOCKBACK_FORCE = 100000,

	-- requests per second per player
	RATE_ATTACK = 10,
	RATE_BLOCK = 12,
	RATE_DODGE = 6,
	RATE_KNOCK = 4, -- grip / carry requests
}

return Combat
