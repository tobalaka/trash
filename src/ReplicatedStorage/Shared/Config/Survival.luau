--!strict
--[[
	Config.Survival - Hunger, Thirst and Blood ("Vitality" on screen), and the Wastezone gas.
	Mirrors the vault notes Hunger-Thirst and Blood. Values are PROPOSALS (2026-10-25) except
	where the designer set them (BLOOD_VISION 50%, knock 5 s / 5 s).
]]

local Survival = {}

Survival.HUNGER_MAX = 100
Survival.THIRST_MAX = 100
Survival.BLOOD_MAX = 100
Survival.TICK = 1 -- seconds per server survival step

-- drain per minute (a full meter lasts 50 min / about 36 min)
Survival.HUNGER_DRAIN = 2.0
Survival.THIRST_DRAIN = 2.8
Survival.LOW = 25 -- below this Blood stops recovering
Survival.SAFE_ZONE_DRAIN = 0.5 -- multiplier inside your faction base
Survival.SMOG_DRAIN = 1.25 -- multiplier while the server's pollution is high

-- Blood (Blood.md)
Survival.BLOOD_DRAIN = 0.4 -- per second while Hunger or Thirst is empty
Survival.BLOOD_REGEN = 0.15 -- per second while both are above LOW
Survival.BLOOD_VISION = 50 -- % where vision starts to fade (designer)
Survival.KNOCK_TIME = 5 -- seconds down (designer)
Survival.KNOCK_UP_TIME = 5 -- seconds up before falling again (designer)
Survival.KNOCK_HIT_LOSS = 6 -- Blood lost per hit taken while knocked
Survival.KNOCK_EXIT_BLOOD = 12 -- eating or drinking while knocked restores at least this much
Survival.RESPAWN_BLOOD = 40 -- a respawn never starts below this

-- Well Fed (answers the old OPEN "combat buffs from full meters", 2026-10-26): both meters at
-- or above WELL_FED_AT give Relic moves a little more bite and Anima a little faster
Survival.WELL_FED_AT = 80
Survival.WELL_FED_DAMAGE = 0.05 -- extra Relic move damage
Survival.WELL_FED_ANIMA = 0.1 -- extra Anima gain
Survival.WELL_FED_REGEN = 1.5 -- multiplier on BLOOD_REGEN

-- helping a knocked ally up (Supporter's Field Revive)
Survival.REVIVE_HOLD = 2 -- seconds holding the prompt
Survival.REVIVE_RANGE = 10
Survival.REVIVE_BLOOD = 40 -- Vitality they get up with
Survival.REVIVE_FOOD = 15 -- Hunger and Thirst shared with them

-- Wastezone gas (regions keyed Wasteland in ReplicatedStorage.MapRegionVolumes)
Survival.GAS_REGIONS = { Wasteland = true }
Survival.GAS_BLOOD_DRAIN = 1.0 -- per second without a respirator
Survival.GAS_HEALTH_DRAIN = 1.5 -- per second without a respirator

return Survival
