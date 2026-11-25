--!strict
--[[
	Mob constants: Pollution Beasts (03-Content/Mobs). Mirrors the Constants tables in each mob's
	vault note; change the note and this file together. Every value is a PROPOSAL until tuned in
	Studio. Times are seconds, distances studs, speeds studs/s, angles degrees.

	Attack fields:
	  windup     start of the move to its first hit (the telegraph players react to)
	  recovery   after the last hit, before the beast decides again
	  cooldown   before the move can be picked again
	  minRange / maxRange   root-to-root distance at which the move may be picked
	  damage     health damage on a clean hit
	  posture    posture damage to a blocking player
	  parryable  a timed block in front negates it and staggers the beast
	  blockable  holding block in front cuts the damage (unblockable moves ignore blocks)
	  stun       hitstun on a clean hit
	  knockback / up   push away from the beast and upward, studs/s
	  ragdoll    seconds of ragdoll on a clean hit (0 = none)
	  weight     base preference when several moves fit
	  box        hitbox width, height, depth; it stands on the ground in front of (or behind) the beast
]]

local Mobs = {}

Mobs.JunkRam = {
	DISPLAY_NAME = "Junk Ram",
	TITLE = "Apex Pollution Beast",
	TEMPLATE = "JunkRam", -- ServerStorage.Mobs.<TEMPLATE>
	SCALE = 3, -- the template is built at 3x (36 studs tall); client effects scale with it
	MAX_HEALTH = 4500,
	RESPAWN_TIME = 300,
	CORPSE_TIME = 8,

	-- senses and targeting
	AGGRO_RADIUS = 110,
	DEAGGRO_RADIUS = 220, -- a target farther than this from the beast is dropped
	LEASH_RADIUS = 280, -- from home: give up, walk back, regenerate
	RETURN_REGEN = 0.08, -- fraction of MaxHealth per second while returning or calm
	THINK_INTERVAL = 0.1,
	THREAT_PROXIMITY = 20, -- threat per second for a player inside CLOSE_RANGE
	THREAT_DECAY = 0.08, -- fraction of threat lost per second
	TARGET_SWITCH_MARGIN = 1.35, -- a new target needs this much more threat than the current one
	ATTRIBUTION_RADIUS = 40, -- damage taken is credited to attacking players this close
	MEMORY = 20, -- seconds a player's parries are remembered

	-- movement
	ROAM_SPEED = 12,
	CHASE_SPEED = 24,
	CIRCLE_SPEED = 15,
	RETURN_SPEED = 24,
	ROAM_RADIUS = 90,
	ROAM_PAUSE_MIN = 3,
	ROAM_PAUSE_MAX = 7,
	HOME_TOLERANCE = 16,
	CLOSE_RANGE = 30, -- melee distance, root to root
	CIRCLE_RADIUS = 46,
	CIRCLE_TIME_MIN = 0.8,
	CIRCLE_TIME_MAX = 1.8,
	TURN_RATE = 110, -- degrees per second while the beast turns itself; slow enough to flank
	TRACK_LOCK = 0.25, -- melee moves stop tracking the target this long before they land
	STUCK_TIME = 1.5, -- seconds without progress before it paths around
	STUCK_DISTANCE = 3,
	PATH_AGENT_RADIUS = 14,
	PATH_AGENT_HEIGHT = 36,
	PATH_REFRESH = 1,

	-- stagger (the beast's posture)
	STAGGER_MAX = 420,
	STAGGER_PER_DAMAGE = 1,
	STAGGER_PER_PARRY = 120,
	STAGGER_REGEN = 25, -- per second
	STAGGER_REGEN_DELAY = 3,
	STAGGER_TIME = 3.5,
	STAGGER_DAMAGE_BONUS = 0.3, -- extra damage taken while staggered, as a fraction of each hit
	PARRY_FLINCH = 0.9, -- a parry interrupts the move and holds the beast this long

	-- enrage
	ENRAGE_HEALTH = 0.45, -- fraction of MaxHealth
	ENRAGE_SPEED = 1.15,
	ENRAGE_WINDUP = 0.85, -- windups are multiplied by this

	-- reading the player
	PARRY_WARY = 2, -- after this many parries by the target within MEMORY: delayed swings, unblockables
	DELAY_EXTRA = 0.35, -- a delayed swing holds its windup this much longer
	DELAY_CHANCE = 0.5, -- chance a swing is delayed once the beast is wary of parries
	TURTLE_BLOCK_TIME = 1.2, -- a target blocking this long counts as turtling
	BEHIND_ANGLE = 115, -- a player more than this off the beast's nose is behind it
	BEHIND_TIME = 0.9, -- behind this long earns a rear kick
	SURROUNDED = 2, -- this many players within CLOSE_RANGE favour the stomp
	KITE_TIME = 3, -- the target staying beyond KITE_RANGE this long favours the barrage
	KITE_RANGE = 80,
	FEINT_CHANCE = 0.2, -- chance a charge windup is cancelled to bait a dodge
	FEINT_AT = 0.7, -- fraction of the charge windup where a feint cancels
	PUNISH_BONUS = 3, -- extra weight for fast melee when the target is stunned or downed
	AIRBORNE_HEIGHT = 2.5, -- a player this far above the ground clears stomps and shockwaves

	ATTACKS = {
		Sweep = {
			windup = 0.7, recovery = 0.8, cooldown = 2.4, minRange = 0, maxRange = 36,
			damage = 26, posture = 35, parryable = true, blockable = true,
			stun = 0.7, knockback = 60, up = 18, ragdoll = 0, weight = 3,
			box = Vector3.new(54, 24, 40),
		},
		Headbutt = {
			windup = 0.6, gap = 0.5, recovery = 0.7, cooldown = 3.5, minRange = 0, maxRange = 32,
			damage = 17, posture = 25, parryable = true, blockable = true,
			stun = 0.5, knockback = 26, up = 0, ragdoll = 0, weight = 2,
			finisherKnockback = 70, finisherUp = 30, finisherRagdoll = 1.2,
			box = Vector3.new(27, 24, 36),
		},
		RearKick = {
			windup = 0.55, recovery = 0.7, cooldown = 3, minRange = 0, maxRange = 36,
			damage = 22, posture = 30, parryable = true, blockable = true,
			stun = 0.6, knockback = 65, up = 20, ragdoll = 0, weight = 6,
			box = Vector3.new(36, 20, 33), -- behind the beast
		},
		Stomp = {
			windup = 1.05, recovery = 1.1, cooldown = 7, minRange = 0, maxRange = 34,
			damage = 36, posture = 0, parryable = false, blockable = false,
			stun = 0, knockback = 45, up = 55, ragdoll = 1.6, weight = 2,
			radius = 30, offset = 14, -- AoE centre this far in front of the beast
		},
		Charge = {
			windup = 1.2, recovery = 0.9, cooldown = 9, minRange = 45, maxRange = 150,
			damage = 34, posture = 80, parryable = true, blockable = true,
			stun = 0.9, knockback = 85, up = 30, ragdoll = 1.8, weight = 3,
			speed = 110, maxTime = 1.4, overshoot = 30, lead = 0.35,
			box = Vector3.new(27, 24, 24),
			crashStun = 2.4, crashStagger = 90, wallProbe = 22,
		},
		Barrage = {
			windup = 0.85, recovery = 1.0, cooldown = 10, minRange = 55, maxRange = 170,
			damage = 20, posture = 30, parryable = false, blockable = true,
			stun = 0.6, knockback = 30, up = 26, ragdoll = 0, weight = 2,
			shards = 5, interval = 0.12, flight = 1.2, spread = 20, radius = 11, lead = 0.9,
		},
		Quake = {
			windup = 0.8, air = 1.3, recovery = 1.5, cooldown = 15, minRange = 0, maxRange = 150,
			enragedOnly = true,
			damage = 42, posture = 0, parryable = false, blockable = false,
			stun = 0, knockback = 50, up = 65, ragdoll = 1.8, weight = 4,
			radius = 28, lead = 0.6, maxLeap = 130,
			rings = 3, ringInterval = 0.45, ringSpeed = 70, ringReach = 110, ringWidth = 7,
			ringDamage = 22, ringKnockback = 40, ringUp = 40,
		},
		Roar = {
			windup = 0.5, active = 1.3, recovery = 0.4, cooldown = 30, minRange = 0, maxRange = 1000,
			damage = 0, posture = 0, parryable = false, blockable = false,
			stun = 0, knockback = 60, up = 18, ragdoll = 0, weight = 0,
			radius = 45,
		},
	},

	-- client presentation (MobAnimator, MobFx, MobHud)
	STRIDE = 21, -- studs per full gait cycle
	HUD_RANGE = 220, -- the boss bar shows within this distance while the beast fights
	SHAKE_RANGE = 130,
}

return Mobs
