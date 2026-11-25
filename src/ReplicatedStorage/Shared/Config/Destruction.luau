--!strict
--[[
	Config.Destruction - breakable map (vault: 02-Systems/Destruction/Destructible-Walls).
	Values are PROPOSALS (2026-10-26) unless the note says otherwise.

	The server cuts block parts into smaller anchored boxes around an impact (the hole), and
	sends the removed volume to nearby clients as cosmetic debris. Broken parts grow back after
	RESPAWN_TIME.
]]

local Destruction = {}

-- What can break: everything under these folders (paths from Workspace), except EXCLUDE names.
-- Not listed on purpose: the ground, both faction bases (safe zones), the dome and overhead
-- cables, salvage props, market stalls, NPC markers, trees, the Smog Spire.
Destruction.ROOTS = {
	{ "World", "Town", "Buildings" },
	{ "World", "Town", "Outskirts" },
	{ "World", "Town", "Landmarks" },
	{ "World", "Winter", "DestructibleWalls" },
	{ "World", "Winter", "Crates" },
	{ "World", "Wasteland", "WallDressing" },
	{ "World", "Wasteland", "Camps" },
	{ "World", "Jungle", "Ruins" },
}
Destruction.EXCLUDE = { PatchworkDome = true } -- model or folder names inside the roots

-- ── what counts as an impact ──
-- A fighter (player or mob) that was knocked back (a "Knockback" mover on its root) or is
-- ragdolled, moving at IMPACT_MIN_SPEED or more, breaks the breakable part it is about to hit.
Destruction.IMPACT_MIN_SPEED = 22 -- studs/s; the M1 finisher knockback is 28
Destruction.IMPACT_LOOKAHEAD = 2.5 -- studs beyond the root's centre (half a body)
-- A player's own client moves their body, and the server sees it late (in testing the
-- replicated velocity read 0 while the knockback mover was still on). So speed is measured
-- from the server's own position samples, and a body counts as launched for LAUNCH_GRACE after
-- its mover was last seen.
Destruction.LAUNCH_GRACE = 0.6 -- seconds
Destruction.VELOCITY_WINDOW = 0.1 -- seconds of position samples behind each speed reading
Destruction.LOOKAHEAD_TIME = 0.12 -- seconds of travel the impact ray looks ahead (lag)
Destruction.IMPACT_RADIUS_BASE = 3.5 -- hole radius at IMPACT_MIN_SPEED...
Destruction.IMPACT_RADIUS_PER_SPEED = 0.07 -- ...plus this per stud/s above it
Destruction.IMPACT_RADIUS_MAX = 9
Destruction.IMPACT_COOLDOWN = 0.25 -- seconds between impacts by the same fighter
Destruction.IMPACT_SLOWDOWN = 0.75 -- a thrown body keeps this much speed after breaking through

-- ── cutting ──
Destruction.MIN_PIECE = 1.2 -- studs: the smallest box the cutter makes
Destruction.CELLS_ACROSS = 4 -- the hole is about this many boxes across
Destruction.MAX_PIECES_PER_PART = 80 -- coarser cuts beyond this
Destruction.MAX_PARTS_PER_BLAST = 14 -- nearest parts first
Destruction.WHOLE_BREAK_MAX = 14 -- studs: wedges, meshes and other shapes this small break whole
Destruction.BLASTS_PER_SECOND = 25 -- server-wide cap

-- ── debris (client only) ──
Destruction.DEBRIS_PER_BLAST = 36 -- pieces sent per blast
Destruction.DEBRIS_RANGE = 450 -- only players this close are sent the debris
Destruction.DEBRIS_LIFETIME = 6 -- seconds on the ground before fading
Destruction.DEBRIS_FADE = 1
Destruction.MAX_DEBRIS = 220 -- per client; the oldest go first
Destruction.DEBRIS_SPEED = { 14, 34 } -- studs/s at power 1
Destruction.DEBRIS_UP = 18 -- extra upward speed
Destruction.DEBRIS_SPIN = 9 -- rad/s
Destruction.DEBRIS_BOUNCE = 0.3 -- restitution
Destruction.DEBRIS_FRICTION = 0.6
Destruction.DEBRIS_SHRINK = 0.9 -- debris are drawn slightly smaller than the hole they came from
Destruction.DUST_PARTICLES = 18
Destruction.DEBRIS_QUANT = 20 -- debris boxes are sent in 1/20 stud steps (packed, see DestructionService)

-- ── regrowth ──
Destruction.RESPAWN_TIME = 45 -- seconds after the last hit on that part
Destruction.RESPAWN_RETRY = 3 -- if someone is standing inside it, try again after this
Destruction.MAX_BROKEN = 500 -- broken parts tracked at once; the oldest regrow early past this
Destruction.MAX_PIECES = 12000 -- cut pieces in the world at once; the oldest regrow early past this

-- ── Relic moves and mobs ──
Destruction.BLAST_SCALE = 0.55 -- a move's hit radius times this is its hole radius
Destruction.BLAST_MAX = 8
Destruction.PROJECTILE_RADIUS = 3 -- a thrown Relic hitting a wall
Destruction.DASH_RADIUS = 4 -- a dashing caster running into a wall
Destruction.BEAST_SCALE = 0.45 -- Junk Ram stomp / quake radius times this
Destruction.BEAST_CHARGE_RADIUS = 11 -- the Junk Ram charging through a wall

-- ── rewards (granted by TRASH-Progression's Smash service) ──
Destruction.SCRAP_PER_PART = 1 -- "destruction becomes upcycling"
Destruction.SCRAP_PER_BLAST_MAX = 4
Destruction.SCRAP_PER_MINUTE_MAX = 30 -- per player; stops wall farming

return Destruction
