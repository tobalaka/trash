--!strict
--[[
	Regions.Bases - the two faction compounds, both in the middle of the map beside the
	central dome town (the user: "add a scrappers and menders base somewhere in the middle").

	Sites come from Town.plan().baseSites (two opposite corners of the Town rectangle, fronts
	facing the dome), so the town's highlands keep clear of them.
	  Menders: Structures.MendersBase - the civic HQ: a long, symmetric, pale classical hall.
	  Scrappers:  Structures.ScrappersBase  - a crime base in a scrapyard (no weapons/gore: Roblox-safe).
	Each compound gets a flat yard: a "set" ground feature (layer 5) that overrides whatever the
	plains would have been, so the yard is one flat block surface.
]]

local Config = require(script.Parent.Parent.Config)
local Layout = require(script.Parent.Parent.Layout)
local FeatureMap = require(script.Parent.Parent.FeatureMap)

local Bases = {}
Bases.NAME = "Bases"

local S = Config.GROUND.SURFACE_Y
Bases.YARD_KEY = { Menders = "BasePavement", Scrappers = "ScrapperYard" }
Bases.SEED_OFFSET = { Menders = 301, Scrappers = 302 }

export type Site = { cf: CFrame, half: Vector2 }

local function sites(ctx: any): { [string]: Site }
	return ctx.regions.Town.plan(ctx).baseSites
end

-- Flat yards (axis-aligned, so they rasterise into clean rectangles).
function Bases.ground(ctx: any, fm: FeatureMap.Map)
	for name, site in sites(ctx) do
		fm:rect("set", 5, site.cf.X, site.cf.Z, site.half.X, site.half.Y, S, Bases.YARD_KEY[name])
	end
end

function Bases.populate(ctx: any, folder: Folder)
	local data = Layout.dataFolder()
	local Structures = script.Parent.Parent.Structures
	for name, site in sites(ctx) do
		local module = Structures:FindFirstChild(name .. "Base")
		if not module then
			warn("[MapGen] Bases: no builder for " .. name)
			continue
		end
		data:SetAttribute("Progress", "bases: " .. name)
		local builder = require(module :: ModuleScript) :: any
		-- builders work in yard-local space: origin at the yard surface, front = -Z
		local cf = CFrame.new(site.cf.X, S, site.cf.Z) * site.cf.Rotation
		builder.build(folder, cf, site.half, Random.new(Config.SEED + Bases.SEED_OFFSET[name]))
		task.wait()
	end
end

function Bases.reset() end

return Bases
