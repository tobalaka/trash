--!strict
--[[
	MapGen.Build - orchestrates a rebuild. Run stages from the command bar / MCP:

	  local B = require(game.ServerStorage.MapGen.Build)
	  B.job("prepare")              -- snapshot greybox, clear old generated content
	  B.job("ground")               -- part ground + water slabs + stairs (Workspace.Ground)
	  B.job("region", "Town")       -- populate one region (Town, Wasteland, Bases, Desert, Jungle, Winter)
	  B.job("validate")             -- grounding check over everything
	  B.job("zfight")               -- coplanar-face check over the ground and generated parts
	  B.job("atmosphere")           -- region volumes + lighting defaults

	Jobs run in a spawned thread so a long build never blocks Studio's MCP call; progress and
	errors are written as attributes on ServerStorage.MapGenData (Job, Progress, Error).
]]

local ServerStorage = game:GetService("ServerStorage")
local Config = require(script.Parent.Config)
local Layout = require(script.Parent.Layout)
local GroundBuilder = require(script.Parent.GroundBuilder)
local PlacementUtil = require(script.Parent.PlacementUtil)

local Regions = script.Parent.Regions

local Build = {}

local REGION_MODULES = { "Town", "Wasteland", "Desert", "Jungle", "Winter", "Bases" }

-- Fresh context: every region re-plans from the layout (plans are deterministic by seed).
function Build.context(): any
	local regions: { [string]: any } = {}
	for _, name in REGION_MODULES do
		local m = require(Regions:FindFirstChild(name) :: ModuleScript) :: any
		if m.reset then
			m.reset()
		end
		regions[name] = m
	end
	return { regions = regions, config = Config, layout = Layout.get() }
end

function Build.worldFolder(): Folder
	local w = workspace:FindFirstChild(Config.WORLD_FOLDER)
	if not w then
		w = Instance.new("Folder")
		w.Name = Config.WORLD_FOLDER
		w.Parent = workspace
	end
	PlacementUtil.setExcluded({ w })
	return w :: Folder
end

-- Folder for one region's generated content, cleared on rebuild.
function Build.regionFolder(name: string, clear: boolean?): Folder
	local w = Build.worldFolder()
	local f = w:FindFirstChild(name)
	if f and clear then
		f:Destroy()
		f = nil
	end
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = w
	end
	return f :: Folder
end

-- ─── stages ───────────────────────────────────────────────────────────────────

function Build.prepare()
	Layout.snapshot(false)
	local data = Layout.dataFolder()
	local map = workspace:FindFirstChild("Map")
	if map then
		-- the train system is gameplay, not greybox: keep it live, move it to its scaled spot
		local train = map:FindFirstChild("TrainSystem")
		if train then
			train.Parent = workspace
			local o = Layout.get().origin
			for _, p in train:GetDescendants() do
				if p:IsA("BasePart") then
					local s = Layout.scaleXZ(p.Position, o)
					p.CFrame = CFrame.new(s) * p.CFrame.Rotation
				end
			end
		end
		local old = data:FindFirstChild("GreyboxBackup")
		if old then
			old:Destroy()
		end
		map.Name = "GreyboxBackup"
		map.Parent = data
	end
	-- the previous dressing pass (and its floating-city slab) is replaced wholesale
	local oldWorld = workspace:FindFirstChild(Config.WORLD_FOLDER)
	if oldWorld then
		oldWorld:Destroy()
	end
	local spawn = workspace:FindFirstChild("SpawnLocation")
	if spawn and spawn:IsA("BasePart") and not spawn:GetAttribute("MapGenScaled") then
		local s = Layout.scaleXZ(spawn.Position, Layout.get().origin)
		spawn.Position = Vector3.new(s.X, spawn.Position.Y, s.Z)
		spawn:SetAttribute("MapGenScaled", true)
	end
	Build.worldFolder()
	print("[MapGen] prepare: greybox snapshotted and moved to ServerStorage.MapGenData.GreyboxBackup")
end

-- Every region registers its flat-topped ground features into a fresh shared map.
function Build.registerGround(ctx: any): number
	local fm = GroundBuilder.reset()
	for _, name in REGION_MODULES do
		local m = ctx.regions[name]
		if m.ground then
			m.ground(ctx, fm)
		end
	end
	fm:finalize()
	return fm.count
end

-- The ground: part columns and water slabs per chunk, then each region's ground structures
-- (stairs and the like) in Workspace.Ground.Structures.
function Build.ground(area: any?)
	local ctx = Build.context()
	local n = Build.registerGround(ctx)
	print(string.format("[MapGen] ground: %d features", n))
	GroundBuilder.build(ctx, area)
	local root = GroundBuilder.folder()
	local old = root:FindFirstChild("Structures")
	if old then
		old:Destroy()
	end
	local structures = Instance.new("Folder")
	structures.Name = "Structures"
	for _, name in REGION_MODULES do
		local m = ctx.regions[name]
		if m.groundParts then
			m.groundParts(ctx, structures)
		end
	end
	structures.Parent = root
end

function Build.region(name: string)
	local ctx = Build.context()
	Build.registerGround(ctx)
	local m = ctx.regions[name]
	assert(m and m.populate, "region has no populate(): " .. name)
	local folder = Build.regionFolder(name, true)
	local t = os.clock()
	m.populate(ctx, folder)
	PlacementUtil.validate(folder)
	print(string.format("[MapGen] region %s populated in %.1fs", name, os.clock() - t))
end

-- Decals and surface overrides (needs uploaded images; can be re-run on its own).
function Build.dress(name: string)
	local ctx = Build.context()
	local m = ctx.regions[name]
	assert(m and m.dress, "region has no dress(): " .. name)
	m.dress(ctx, Build.regionFolder(name, false))
end

function Build.surfaces()
	local Surfaces = require(script.Parent.Surfaces) :: any
	Surfaces.apply()
end

function Build.validate()
	return PlacementUtil.validate(Build.worldFolder())
end

-- Coplanar overlapping faces among the ground and every generated part (see ZFight).
function Build.zfight(): any
	local ZFight = require(script.Parent.ZFight) :: any
	return ZFight.scan({ GroundBuilder.folder(), Build.worldFolder() })
end

function Build.atmosphere()
	local Atmosphere = require(script.Parent.AtmosphereBuilder) :: any
	Atmosphere.apply(Build.context())
end

-- ─── job runner ───────────────────────────────────────────────────────────────

function Build.job(stage: string, ...: any)
	local data = Layout.dataFolder()
	local args = table.pack(...)
	data:SetAttribute("Job", stage .. " " .. tostring(args[1] or ""))
	data:SetAttribute("Progress", "started")
	data:SetAttribute("Error", "")
	data:SetAttribute("Done", false)
	task.spawn(function()
		local fn = (Build :: any)[stage]
		local ok, err = xpcall(function()
			fn(table.unpack(args, 1, args.n))
		end, debug.traceback)
		if not ok then
			data:SetAttribute("Error", tostring(err))
			warn("[MapGen] job " .. stage .. " failed: " .. tostring(err))
		end
		data:SetAttribute("Done", true)
	end)
	return "started " .. stage
end

function Build.status(): string
	local data = Layout.dataFolder()
	return string.format("job=%s done=%s progress=%s error=%s", tostring(data:GetAttribute("Job")), tostring(data:GetAttribute("Done")),
		tostring(data:GetAttribute("Progress")), tostring(data:GetAttribute("Error")))
end

return Build
