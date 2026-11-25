--!strict
--[[
	MapGen.Layout - the original greybox, scaled.

	The hand-placed greybox (Workspace.Map) is snapshotted ONCE into
	ServerStorage.MapGenData.LayoutSource and never modified again. Everything the generator
	builds is derived from that snapshot through scaleXZ(), so MAP_SCALE can be changed and the
	map rebuilt without compounding (re-scaling an already scaled map would drift).

	Classification of greybox parts:
	  *_Floor / "Desert floor"           -> region rectangles (Town, Wasteland, Winter, Jungle, Desert)
	  yellow block                       -> Menders base placeholder
	  Scrappers_Base pad + red block       -> Scrappers base placeholder
	  Desert parts taller than 900 / roof -> the Smog Spire placeholder
	  other Desert Biome Parts           -> desert rock masses (canyon walls, plateaus)
	  thin root walls (<= 8 thick)       -> jungle boundary cliffs
	  other root blocks taller than 100  -> wasteland walls (kept as walls, dressed)
]]

local ServerStorage = game:GetService("ServerStorage")
local Config = require(script.Parent.Config)

export type Rect = { region: string, cf: CFrame, size: Vector3, top: number }
export type Block = { kind: string, cf: CFrame, size: Vector3, name: string }
export type Data = {
	origin: Vector2,
	rects: { Rect },
	blocks: { Block },
	menders: Block?,
	scrappers: Block?,
	raidersPad: Block?,
	tower: Block?,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	priority: { [string]: number },
}

local Layout = {}

local REGION_OF_FLOOR: { [string]: string } = {
	MainLand_Floor = "Town",
	PollutionZone_Floor = "Wasteland",
	ArcticZone_Floor = "Winter",
	ForestBiome_Floor = "Jungle",
	["Desert floor"] = "Desert",
}
Layout.REGIONS = { "Town", "Wasteland", "Winter", "Jungle", "Desert" }

-- ─── snapshot ─────────────────────────────────────────────────────────────────

function Layout.dataFolder(): Folder
	local f = ServerStorage:FindFirstChild("MapGenData")
	if not f then
		f = Instance.new("Folder")
		f.Name = "MapGenData"
		f.Parent = ServerStorage
	end
	return f :: Folder
end

-- Copy the greybox (minus scripts/train) into LayoutSource. Original colours are restored
-- from the OrigMaterial/OrigColor attributes left by the earlier dressing pass.
function Layout.snapshot(force: boolean?): Folder
	local data = Layout.dataFolder()
	local existing = data:FindFirstChild("LayoutSource")
	if existing and not force then
		return existing :: Folder
	end
	if existing then
		existing:Destroy()
	end
	local map = workspace:FindFirstChild("Map")
	assert(map, "Workspace.Map (greybox) not found and no LayoutSource snapshot exists")
	local src = Instance.new("Folder")
	src.Name = "LayoutSource"
	local train = map:FindFirstChild("TrainSystem")
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and not (train and d:IsDescendantOf(train)) then
			local c = d:Clone()
			c:ClearAllChildren()
			local origMat = d:GetAttribute("OrigMaterial")
			if typeof(origMat) == "string" then
				c.Material = (Enum.Material :: any)[origMat]
				c.Color = d:GetAttribute("OrigColor") :: Color3
			end
			c:SetAttribute("Group", d.Parent and d.Parent.Name or "")
			c.Parent = src
		end
	end
	src.Parent = data
	return src
end

-- ─── scaling helpers ──────────────────────────────────────────────────────────

local cached: Data? = nil

function Layout.scaleXZ(p: Vector3, origin: Vector2): Vector3
	local s = Config.MAP_SCALE
	return Vector3.new(origin.X + (p.X - origin.X) * s, p.Y, origin.Y + (p.Z - origin.Y) * s)
end

-- Scale a block: footprint x MAP_SCALE, height x heightScale keeping its bottom where it was.
local function scaleBlock(part: BasePart, origin: Vector2, heightScale: number): (CFrame, Vector3)
	local s = Config.MAP_SCALE
	local rot = part.CFrame.Rotation
	-- world-space vertical extent of the (possibly rotated) part
	local halfY = math.abs(rot.RightVector.Y) * part.Size.X / 2 + math.abs(rot.UpVector.Y) * part.Size.Y / 2 + math.abs(rot.LookVector.Y) * part.Size.Z / 2
	local bottom = part.Position.Y - halfY
	local size = Vector3.new(part.Size.X * s, part.Size.Y * heightScale, part.Size.Z * s)
	-- the local axis that is vertical keeps heightScale; the other two take the XZ scale
	if math.abs(rot.UpVector.Y) < 0.5 then
		-- rotated so a different axis is up: rescale per axis by its vertical component
		local function axisScale(v: Vector3): number
			return math.abs(v.Y) > 0.5 and heightScale or s
		end
		size = Vector3.new(part.Size.X * axisScale(rot.RightVector), part.Size.Y * axisScale(rot.UpVector), part.Size.Z * axisScale(rot.LookVector))
	end
	local newHalfY = halfY * heightScale
	local pos = Layout.scaleXZ(part.Position, origin)
	return CFrame.new(pos.X, bottom + newHalfY, pos.Z) * rot, size
end

function Layout.get(): Data
	if cached then
		return cached
	end
	local src = Layout.snapshot(false)
	local parts: { BasePart } = {}
	for _, p in src:GetChildren() do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end

	-- origin = centre of everything on X/Z (or the configured override)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in parts do
		local h = p.Size / 2
		minX = math.min(minX, p.Position.X - h.X)
		maxX = math.max(maxX, p.Position.X + h.X)
		minZ = math.min(minZ, p.Position.Z - h.Z)
		maxZ = math.max(maxZ, p.Position.Z + h.Z)
	end
	local origin = Config.ORIGIN or Vector2.new((minX + maxX) / 2, (minZ + maxZ) / 2)
	local hs = Config.LANDMARK_HEIGHT_SCALE

	local data: Data = {
		origin = origin,
		rects = {},
		blocks = {},
		menders = nil,
		scrappers = nil,
		raidersPad = nil,
		tower = nil,
		bounds = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge },
		priority = {},
	}

	local towerParts: { BasePart } = {}
	for _, p in parts do
		local group = p:GetAttribute("Group")
		local region = REGION_OF_FLOOR[p.Name]
		if region then
			local cf, size = scaleBlock(p, origin, 1)
			table.insert(data.rects, { region = region, cf = cf, size = size, top = p.Position.Y + p.Size.Y / 2 })
		elseif p.BrickColor == BrickColor.new("New Yeller") then
			local cf, size = scaleBlock(p, origin, hs)
			data.menders = { kind = "Menders", cf = cf, size = size, name = p.Name }
		elseif p.Name == "Scrappers_Base" then
			local cf, size = scaleBlock(p, origin, 1)
			data.raidersPad = { kind = "ScrappersPad", cf = cf, size = size, name = p.Name }
		elseif p.BrickColor == BrickColor.new("Really red") then
			local cf, size = scaleBlock(p, origin, hs)
			data.scrappers = { kind = "Scrappers", cf = cf, size = size, name = p.Name }
		elseif group == "Desert Biome Parts" and (p.Size.Y > 900 or p.Position.Y > 900) then
			table.insert(towerParts, p)
		elseif group == "Desert Biome Parts" then
			local cf, size = scaleBlock(p, origin, hs)
			table.insert(data.blocks, { kind = "DesertRock", cf = cf, size = size, name = p.Name })
		elseif math.min(p.Size.X, p.Size.Z) <= 8 and p.Size.Y > 60 then
			local cf, size = scaleBlock(p, origin, hs)
			table.insert(data.blocks, { kind = "JungleCliff", cf = cf, size = size, name = p.Name })
		elseif p.Size.Y > 100 then
			local cf, size = scaleBlock(p, origin, hs)
			table.insert(data.blocks, { kind = "WastelandWall", cf = cf, size = size, name = p.Name })
		end
	end

	-- the Smog Spire placeholder: bounding box of its walls + roof, scaled.
	if #towerParts > 0 then
		local tMinX, tMaxX, tMinZ, tMaxZ, tTop = math.huge, -math.huge, math.huge, -math.huge, -math.huge
		for _, p in towerParts do
			local cf, size = scaleBlock(p, origin, 1)
			local half = (cf.Rotation * size):Abs() / 2
			tMinX = math.min(tMinX, cf.X - half.X)
			tMaxX = math.max(tMaxX, cf.X + half.X)
			tMinZ = math.min(tMinZ, cf.Z - half.Z)
			tMaxZ = math.max(tMaxZ, cf.Z + half.Z)
			tTop = math.max(tTop, p.Position.Y + p.Size.Y / 2)
		end
		data.tower = {
			kind = "Tower",
			cf = CFrame.new((tMinX + tMaxX) / 2, tTop / 2, (tMinZ + tMaxZ) / 2),
			size = Vector3.new(tMaxX - tMinX, tTop, tMaxZ - tMinZ),
			name = "SmogSpirePlaceholder",
		}
	end

	-- Region priority = which floor was on top in the greybox (higher top wins overlaps).
	for _, r in data.rects do
		data.priority[r.region] = math.max(data.priority[r.region] or -math.huge, r.top)
		local half = (r.cf.Rotation * r.size):Abs() / 2
		data.bounds.minX = math.min(data.bounds.minX, r.cf.X - half.X)
		data.bounds.maxX = math.max(data.bounds.maxX, r.cf.X + half.X)
		data.bounds.minZ = math.min(data.bounds.minZ, r.cf.Z - half.Z)
		data.bounds.maxZ = math.max(data.bounds.maxZ, r.cf.Z + half.Z)
	end
	cached = data
	return data
end

-- ─── region queries ───────────────────────────────────────────────────────────

-- Signed distance from (x, z) to an oriented rectangle (negative inside).
local function rectDistance(r: Rect, x: number, z: number): number
	local lp = r.cf:PointToObjectSpace(Vector3.new(x, r.cf.Y, z))
	local dx = math.abs(lp.X) - r.size.X / 2
	local dz = math.abs(lp.Z) - r.size.Z / 2
	local outside = Vector2.new(math.max(dx, 0), math.max(dz, 0)).Magnitude
	return outside + math.min(math.max(dx, dz), 0)
end

-- Distance to each region (minimum over its rectangles), with a noisy border.
function Layout.regionDistances(x: number, z: number): { [string]: number }
	local data = Layout.get()
	local out: { [string]: number } = {}
	local n = math.noise(x / 520, z / 520, 7.3) * Config.GROUND.BORDER_NOISE
		+ math.noise(x / 170, z / 170, 2.1) * Config.GROUND.BORDER_NOISE * 0.35
	for _, r in data.rects do
		local d = rectDistance(r, x, z) + n
		local prev = out[r.region]
		if prev == nil or d < prev then
			out[r.region] = d
		end
	end
	return out
end

-- Blend weights per region (sum to 1). Higher-priority regions mask lower ones where they
-- overlap, exactly like the taller floor hid the lower one in the greybox.
local orderCache: { string }? = nil
function Layout.regionWeights(x: number, z: number): ({ [string]: number }, string)
	local data = Layout.get()
	if not orderCache then
		local order = table.clone(Layout.REGIONS)
		table.sort(order, function(a, b)
			return (data.priority[a] or 0) > (data.priority[b] or 0)
		end)
		orderCache = order
	end
	local dist = Layout.regionDistances(x, z)
	local blend = Config.GROUND.BLEND
	local weights: { [string]: number } = {}
	local covered = 0
	local total = 0
	for _, name in orderCache :: { string } do
		local d = dist[name]
		if d then
			local w = math.clamp(0.5 - d / blend, 0, 1)
			w = w * w * (3 - 2 * w) -- smoothstep
			w *= (1 - covered)
			covered = math.min(1, covered + w)
			weights[name] = w
			total += w
		end
	end
	-- outside every floor: belong fully to the nearest region (the outer margin)
	if total < 1e-3 then
		local best, bestD = "Wasteland", math.huge
		for name, d in dist do
			if d < bestD then
				best, bestD = name, d
			end
		end
		weights = { [best] = 1 }
		return weights, best
	end
	local dominant, dw = "Town", -1
	for name, w in weights do
		weights[name] = w / total
		if w > dw then
			dominant, dw = name, w
		end
	end
	return weights, dominant
end

function Layout.regionAt(x: number, z: number): string
	local _, dominant = Layout.regionWeights(x, z)
	return dominant
end

-- Union rectangle(s) of one region, for planners.
function Layout.rectsOf(region: string): { Rect }
	local out = {}
	for _, r in Layout.get().rects do
		if r.region == region then
			table.insert(out, r)
		end
	end
	return out
end

function Layout.blocksOf(kind: string): { Block }
	local out = {}
	for _, b in Layout.get().blocks do
		if b.kind == kind then
			table.insert(out, b)
		end
	end
	return out
end

return Layout
