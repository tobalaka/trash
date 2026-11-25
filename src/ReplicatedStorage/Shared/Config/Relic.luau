--!strict
--[[
	Config.Relic - rules for Relic moves (the abilities themselves are in Shared/Data/Relics) and
	the Anima meter that powers the B ultimate (Glossary: "fills in fights; max enables the B
	ultimate"). Mirrors the vault note Relic-Abilities. Values are PROPOSALS (2026-10-25).
]]

local Relic = {}

Relic.ANIMA_MAX = 100
Relic.ANIMA_PER_DAMAGE = 1.2 -- per point of damage you deal
Relic.ANIMA_PER_DAMAGE_TAKEN = 0.6 -- per point of damage you take
Relic.ANIMA_DECAY_DELAY = 12 -- seconds out of combat before it fades
Relic.ANIMA_DECAY = 3 -- per second once fading

Relic.MAX_STAMP_SKEW = 0.35 -- how far before the server received a press its timestamp may claim
Relic.MOVE_TOLERANCE = 1.6 -- a dash may cover this times its distance (lag), no more
Relic.MELEE_KINDS = { Strike = true, Cone = true, Dash = true, Burst = true } -- for Heavy Hands
Relic.PVP_SAME_FACTION = false -- Relic moves don't hurt your own faction
Relic.RATE = 6 -- ability requests per second per player

-- the M1 credit heuristic (CombatService does not report who hit whom): a hit on a model is
-- credited to the nearest player mid-swing and facing it within this range
Relic.CREDIT_RANGE = 11
Relic.CREDIT_WINDOW = 0.35 -- seconds after a swing ends that still count

return Relic
