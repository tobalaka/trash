--!strict
--[[
	MapGen.Config - every tunable for the map generator lives here.

	Two independent kinds of scale:
	  * MAP_SCALE scales the LAYOUT (where regions, walls and landmarks sit, and how big the
	    footprints are) around ORIGIN on X/Z. Change it and rebuild; every region re-plans from
	    the original greybox snapshot (MapGen.LayoutSource), so positions stay proportional.
	  * HUMAN sizes (doors, storeys, streets) never scale with the map. A bigger map should mean
	    more/larger districts, not 18-stud doors. Assets are authored at these sizes in Blender.
	LANDMARK_HEIGHT_SCALE grows walls/mountains/landmark heights more slowly than footprints
	(sqrt) so tall shapes keep their silhouette instead of turning into flat slabs or needles.
]]

local Config = {}

-- ─── layout scale ──────────────────────────────────────────────────────────────
Config.MAP_SCALE = 2
-- Centre of the original greybox on X/Z. nil = compute from LayoutSource bounds.
Config.ORIGIN = nil :: Vector2?
Config.LANDMARK_HEIGHT_SCALE = math.sqrt(Config.MAP_SCALE)

-- ─── human scale (studs) - keep in sync with blender/kitlib.py ───────────────
Config.HUMAN = {
	DOOR_H = 9,
	DOOR_W = 6,
	STOREY = 15,
	CEILING = 13.5,
	STREET_W = 30, -- market streets: room for crowds and combat movement
	LANE_W = 18, -- side lanes
	ALLEY_W = 12, -- narrowest walkable gap between buildings
}

-- ─── ground (Parts only: see GroundBuilder; no smooth Terrain anywhere) ───────
Config.GROUND = {
	SURFACE_Y = 6, -- plains height (matches the old floor tops); regions offset from it
	BLEND = 140, -- studs over which region weights blend (decides the dominant region)
	BORDER_NOISE = 90, -- how much region borders wander (blocky jagged edges, not ruler lines)
	MARGIN = 260, -- ground beyond the outermost region, stepping up into the rim cliffs
}

-- ─── placement ────────────────────────────────────────────────────────────────
Config.PLACEMENT = {
	RAY_TOP = 2600, -- rays start here and go down
	RAY_LENGTH = 3200,
	EMBED = 0.6, -- studs pushed into the ground so bases never show a seam
	FLOAT_TOLERANCE = 0.75, -- validation: max allowed gap under an object's lowest point
	MAX_TILT = 18, -- degrees; align-to-normal props never tilt more than this
}

-- ─── output ───────────────────────────────────────────────────────────────────
Config.WORLD_FOLDER = "World" -- Workspace.World: every generated asset (excluded from ground rays)
Config.SEED = 20261024

return Config
