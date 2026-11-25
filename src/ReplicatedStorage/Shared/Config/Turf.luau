--!strict
--[[
	Config.Turf - the Turf War, the GDD's Server Raid (vault: Turf-War; Glossary "Raid":
	server-wide King of the Hill every 45-60 minutes). A ring opens on Hill Hall, the hill in the
	middle of Patchwork Town (the neutral "Slums"). Each second the side with more living members
	inside gains control; a contested ring holds still. First to CAPTURE wins, or whoever leads
	when DURATION runs out. Winners in the ring get the GDD's endgame payout (materials and a
	chance at a Stat Reset Pill); everyone who took part gets something. Values are PROPOSALS
	(2026-10-26).
]]

local Turf = {}

Turf.INTERVAL = { 45 * 60, 60 * 60 } -- seconds between wars (GDD)
Turf.FIRST = 20 * 60 -- the first one on a fresh server
Turf.WARNING = 60 -- seconds of warning before the ring opens
Turf.DURATION = 300 -- seconds the ring stays open
Turf.CENTER = Vector3.new(461, 0, -1482) -- Hill Hall (y comes from the ground)
Turf.RADIUS = 44
Turf.HEIGHT = 30 -- studs above or below the ground that still count as inside
Turf.CAPTURE = 100
Turf.RATE = 2 -- control per second per extra member over the other side
Turf.MAX_RATE = 8
Turf.TICK = 1

Turf.WIN = { exp = 300, scrap = 60, residue = 10, standing = 60, pillChance = 0.35 }
Turf.JOIN = { exp = 80, scrap = 20, residue = 3, standing = 20 }
Turf.BUFF_TIME = 600 -- the winning side gets a Sky Dump's salvage buff (CONTEST_BUFF) this long

return Turf
