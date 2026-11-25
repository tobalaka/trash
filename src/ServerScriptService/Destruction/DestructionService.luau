--!strict
--[[
	DestructionService - the breakable map (vault: Destructible-Walls, ADR-006).

	How a break works:
	  - blast(center, radius) finds the breakable parts near `center` (Config.Destruction.ROOTS).
	  - A block part is cut around the sphere: its box is halved again and again along its longest
	    side; boxes fully outside the sphere are kept, boxes inside are removed, and boxes on the
	    edge are halved until they are MIN_PIECE small. The kept boxes become anchored pieces (a
	    clone of the original part, resized), so the wall gets a ragged hole and the server's
	    collisions match what players see. No CSG, no unions.
	  - Wedges, meshes and other small shapes break whole.
	  - The removed volume goes to nearby clients as cosmetic debris (one small packed remote per
	    blast, see Client/Destruction/DebrisFx). The server never simulates debris.
	  - The original part is kept out of the world and comes back RESPAWN_TIME after its last hit,
	    once nobody is standing inside it; its pieces are removed then.

	What breaks things:
	  - impacts: a fighter (player or mob) knocked back or ragdolled into a breakable part at
	    IMPACT_MIN_SPEED or more. CombatService is not touched: this reads the "Knockback"
	    mover combat and MobStrike put on a root (its velocity too), and the Fighter's ragdollEnd.
	  - blast(): Relic moves (TRASH-Progression RelicService) and the Junk Ram (JunkRamBrain).

	onBreak(fn) tells other systems (TRASH-Progression Smash: Scrap rewards) who broke what.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local C = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Destruction"))
local Fighters = require(ServerScriptService:WaitForChild("Combat"):WaitForChild("Fighters"))

local REMOTE_FOLDER = "DestructionRemotes"
local KNOCKBACK_MOVER = "Knockback" -- the LinearVelocity CombatService and MobStrike put on a root
local RESTORE_TICK = 1

-- the part a chunk came from, as it was when it broke
type Source = { cf: CFrame, color: Color3, material: Enum.Material, transparency: number }
-- one removed box, in its source part's space
type Debris = { source: Source, center: Vector3, size: Vector3 }
type Box = { lo: Vector3, hi: Vector3 }
type Record = {
	original: BasePart,
	parent: Instance,
	template: BasePart,
	pieces: { [BasePart]: boolean },
	lastHit: number,
}

local DestructionService = {}

local roots: { Instance } = {}
local records: { [BasePart]: Record } = {}
local recordCount = 0
local pieceOf: { [BasePart]: Record } = {}
local pieceCount = 0
local breakable: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local breakFns: { (Player?, number, Vector3, { string }) -> () } = {}
local creditFn: ((Model) -> Player?)? = nil
local lastImpact: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local remote: RemoteEvent? = nil
local overlap: OverlapParams? = nil
local rayParams: RaycastParams? = nil
local budget = 0
local budgetSecond = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

-- ── what may break ──

local function isRoot(inst: Instance): boolean
	return table.find(roots, inst) ~= nil
end

function DestructionService.isBreakable(part: BasePart): boolean
	if pieceOf[part] then
		return true
	end
	local cached = breakable[part]
	if cached ~= nil then
		return cached
	end
	local ok = false
	if part.Anchored and not part:IsA("Terrain") then
		local a: Instance? = part.Parent
		while a and a ~= workspace do
			if C.EXCLUDE[a.Name] then
				break
			end
			if isRoot(a) then
				ok = true
				break
			end
			a = a.Parent
		end
	end
	breakable[part] = ok
	return ok
end

-- a plain box we can cut (no special mesh making it look like something else)
local function cuttable(part: BasePart): boolean
	return part:IsA("Part") and part.Shape == Enum.PartType.Block and part:FindFirstChildWhichIsA("DataModelMesh") == nil
end

-- ── cutting ──

-- Splits a box of `size` (centred on the origin) around a sphere at `lc` (same local space).
local function cut(size: Vector3, lc: Vector3, radius: number, minPiece: number): ({ Box }, { Box })
	local keep: { Box } = {}
	local gone: { Box } = {}
	local function visit(lo: Vector3, hi: Vector3)
		local closest = Vector3.new(math.clamp(lc.X, lo.X, hi.X), math.clamp(lc.Y, lo.Y, hi.Y), math.clamp(lc.Z, lo.Z, hi.Z))
		if (closest - lc).Magnitude > radius then
			table.insert(keep, { lo = lo, hi = hi })
			return
		end
		local mid = (lo + hi) / 2
		local far = Vector3.new(if lc.X < mid.X then hi.X else lo.X, if lc.Y < mid.Y then hi.Y else lo.Y, if lc.Z < mid.Z then hi.Z else lo.Z)
		if (far - lc).Magnitude <= radius then
			table.insert(gone, { lo = lo, hi = hi })
			return
		end
		local ext = hi - lo
		if math.max(ext.X, ext.Y, ext.Z) <= minPiece then
			table.insert(if (mid - lc).Magnitude <= radius then gone else keep, { lo = lo, hi = hi })
			return
		end
		if ext.X >= ext.Y and ext.X >= ext.Z then
			visit(lo, Vector3.new(mid.X, hi.Y, hi.Z))
			visit(Vector3.new(mid.X, lo.Y, lo.Z), hi)
		elseif ext.Y >= ext.Z then
			visit(lo, Vector3.new(hi.X, mid.Y, hi.Z))
			visit(Vector3.new(lo.X, mid.Y, lo.Z), hi)
		else
			visit(lo, Vector3.new(hi.X, hi.Y, mid.Z))
			visit(Vector3.new(lo.X, lo.Y, mid.Z), hi)
		end
	end
	visit(-size / 2, size / 2)
	return keep, gone
end

local function recordFor(part: BasePart): Record?
	local r = pieceOf[part] or records[part]
	if r then
		return r
	end
	local parent = part.Parent
	if not parent then
		return nil
	end
	local template = part:Clone()
	template:ClearAllChildren()
	for _, tag in CollectionService:GetTags(template) do
		CollectionService:RemoveTag(template, tag)
	end
	local record: Record = { original = part, parent = parent, template = template, pieces = {}, lastHit = now() }
	records[part] = record
	recordCount += 1
	return record
end

-- takes `part` out of the world: an original is kept for regrowth, a piece is destroyed
local function remove(part: BasePart, record: Record)
	if part == record.original then
		part.Parent = nil
	else
		pieceOf[part] = nil
		record.pieces[part] = nil
		pieceCount -= 1
		part:Destroy()
	end
end

local function sourceOf(part: BasePart): Source
	return { cf = part.CFrame, color = part.Color, material = part.Material, transparency = part.Transparency }
end

local function breakBlock(part: BasePart, center: Vector3, radius: number, debris: { Debris }): boolean
	local minPiece = math.max(C.MIN_PIECE, radius / C.CELLS_ACROSS)
	local lc = part.CFrame:PointToObjectSpace(center)
	local keep, gone = cut(part.Size, lc, radius, minPiece)
	for _ = 1, 3 do
		if #keep <= C.MAX_PIECES_PER_PART then
			break
		end
		minPiece *= 1.6
		keep, gone = cut(part.Size, lc, radius, minPiece)
	end
	if #gone == 0 then
		return false
	end
	local record = recordFor(part)
	if not record then
		return false
	end
	record.lastHit = now()
	local cf = part.CFrame
	for _, b in keep do
		local piece = record.template:Clone()
		piece.Size = b.hi - b.lo
		piece.CFrame = cf * CFrame.new((b.lo + b.hi) / 2)
		pieceOf[piece] = record
		record.pieces[piece] = true
		pieceCount += 1
		piece.Parent = record.parent
	end
	local source = sourceOf(part)
	for _, b in gone do
		table.insert(debris, { source = source, center = (b.lo + b.hi) / 2, size = b.hi - b.lo })
	end
	remove(part, record)
	return true
end

local function breakWhole(part: BasePart, debris: { Debris }): boolean
	local record = recordFor(part)
	if not record then
		return false
	end
	record.lastHit = now()
	-- eight chunks from its bounding box
	local half = part.Size / 2
	local source = sourceOf(part)
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				table.insert(debris, { source = source, center = Vector3.new(half.X * x / 2, half.Y * y / 2, half.Z * z / 2), size = half })
			end
		end
	end
	remove(part, record)
	return true
end

-- ── regrowth ──

local function restore(record: Record)
	for piece in record.pieces do
		pieceOf[piece] = nil
		pieceCount -= 1
		piece:Destroy()
	end
	table.clear(record.pieces)
	if records[record.original] then
		records[record.original] = nil
		recordCount -= 1
	end
	if record.parent.Parent then
		record.original.Parent = record.parent
	end
	record.template:Destroy()
end

local function occupied(part: BasePart): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local bodies: { Instance } = {}
	for model in Fighters.all() do
		table.insert(bodies, model)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(bodies, p.Character)
		end
	end
	params.FilterDescendantsInstances = bodies
	return #workspace:GetPartBoundsInBox(part.CFrame, part.Size, params) > 0
end

local function restoreTick()
	local t = now()
	for _, record in records do
		if t - record.lastHit >= C.RESPAWN_TIME then
			if occupied(record.original) then
				record.lastHit = t - C.RESPAWN_TIME + C.RESPAWN_RETRY
			else
				restore(record)
			end
		end
	end
	-- too many broken parts or pieces at once: the oldest grow back early
	while recordCount > C.MAX_BROKEN or pieceCount > C.MAX_PIECES do
		local oldest: Record? = nil
		for _, record in records do
			if not oldest or record.lastHit < oldest.lastHit then
				oldest = record
			end
		end
		if not oldest then
			break
		end
		restore(oldest)
	end
end

function DestructionService.restoreAll()
	for _, record in records do
		restore(record)
	end
end

-- ── blasts ──

-- a stud length as a whole number of 1/DEBRIS_QUANT steps, clamped to an i16 or a u16
local function quant(v: number, signed: boolean): number
	local q = math.floor(v * C.DEBRIS_QUANT + 0.5)
	return if signed then math.clamp(q, -32768, 32767) else math.clamp(q, 0, 65535)
end

--[[
	The debris payload, packed small because every nearby client gets one per blast:
	  { at, dir, power, groups = { { cf, color, material, transparency, boxes } } }
	One group per source part; `boxes` is a buffer of BOX_BYTES per chunk: its centre in the
	part's space (3 x i16) and its size (3 x u16), both in 1/DEBRIS_QUANT studs.
]]
local BOX_BYTES = 12

local function pack(debris: { Debris }): { any }
	local bySource: { [Source]: { Debris } } = {}
	local order: { Source } = {}
	for _, d in debris do
		local list = bySource[d.source]
		if not list then
			list = {}
			bySource[d.source] = list
			table.insert(order, d.source)
		end
		table.insert(list, d)
	end
	local groups = {}
	for _, s in order do
		local list = bySource[s]
		local b = buffer.create(#list * BOX_BYTES)
		for i, d in list do
			local o = (i - 1) * BOX_BYTES
			buffer.writei16(b, o, quant(d.center.X, true))
			buffer.writei16(b, o + 2, quant(d.center.Y, true))
			buffer.writei16(b, o + 4, quant(d.center.Z, true))
			buffer.writeu16(b, o + 6, quant(d.size.X, false))
			buffer.writeu16(b, o + 8, quant(d.size.Y, false))
			buffer.writeu16(b, o + 10, quant(d.size.Z, false))
		end
		table.insert(groups, { cf = s.cf, color = s.color, material = s.material, transparency = s.transparency, boxes = b })
	end
	return groups
end

local function sendDebris(center: Vector3, dir: Vector3, power: number, debris: { Debris })
	local r = remote
	if not r or #debris == 0 then
		return
	end
	-- a sample when there are too many
	while #debris > C.DEBRIS_PER_BLAST do
		local i = math.random(1, #debris)
		debris[i] = debris[#debris]
		debris[#debris] = nil
	end
	local payload = { at = center, dir = dir, power = power, groups = pack(debris) }
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - center).Magnitude <= C.DEBRIS_RANGE then
			r:FireClient(p, payload)
		end
	end
end

--[[
	Breaks what is within `radius` of `center`. `cause` is the player to credit (Scrap), `power`
	scales the debris speed (1 = normal), `dir` pushes the debris that way. Returns how many
	parts broke.
]]
function DestructionService.blast(center: Vector3, radius: number, cause: Player?, power: number?, dir: Vector3?): number
	local params = overlap
	if not params or radius <= 0 then
		return 0
	end
	local second = math.floor(os.clock())
	if second ~= budgetSecond then
		budgetSecond = second
		budget = 0
	end
	if budget >= C.BLASTS_PER_SECOND then
		return 0
	end
	budget += 1
	local found = workspace:GetPartBoundsInRadius(center, radius, params)
	local candidates: { BasePart } = {}
	for _, part in found do
		if DestructionService.isBreakable(part) then
			table.insert(candidates, part)
		end
	end
	table.sort(candidates, function(a, b)
		return (a.Position - center).Magnitude < (b.Position - center).Magnitude
	end)
	local debris: { Debris } = {}
	local broken = 0
	local materials: { string } = {}
	for i, part in candidates do
		if i > C.MAX_PARTS_PER_BLAST then
			break
		end
		if part.Parent then
			local ok
			local material = part.Material.Name
			if cuttable(part) then
				ok = breakBlock(part, center, radius, debris)
			elseif math.max(part.Size.X, part.Size.Y, part.Size.Z) <= C.WHOLE_BREAK_MAX then
				ok = breakWhole(part, debris)
			else
				ok = false
			end
			if ok then
				broken += 1
				table.insert(materials, material)
			end
		end
	end
	if broken > 0 then
		sendDebris(center, dir or Vector3.zero, power or 1, debris)
		for _, fn in breakFns do
			task.spawn(fn, cause, broken, center, materials)
		end
	end
	return broken
end

-- The first breakable part along a ray (a dash or a wave front about to hit a wall), or nil.
function DestructionService.probe(from: Vector3, direction: Vector3): RaycastResult?
	local params = rayParams
	if not params then
		return nil
	end
	local hit = workspace:Raycast(from, direction, params)
	if hit and hit.Instance:IsA("BasePart") and DestructionService.isBreakable(hit.Instance) then
		return hit
	end
	return nil
end

-- (cause or nil, parts broken, where, the broken parts' material names) after every blast
-- that broke something
function DestructionService.onBreak(fn: (Player?, number, Vector3, { string }) -> ())
	table.insert(breakFns, fn)
end

-- who to credit when a fighter is thrown through a wall (set by TRASH-Progression: the Ledger)
function DestructionService.setCredit(fn: (Model) -> Player?)
	creditFn = fn
end

-- ── impacts ──

type Track = { times: { number }, points: { Vector3 }, launchedUntil: number }
local tracks: { [Model]: Track } = setmetatable({}, { __mode = "k" }) :: any

-- the body's velocity from the server's own samples over the last VELOCITY_WINDOW
local function sample(tr: Track, clock: number, pos: Vector3): Vector3
	table.insert(tr.times, clock)
	table.insert(tr.points, pos)
	while #tr.times > 2 and clock - tr.times[2] >= C.VELOCITY_WINDOW do
		table.remove(tr.times, 1)
		table.remove(tr.points, 1)
	end
	local elapsed = clock - tr.times[1]
	return if elapsed > 1e-3 then (pos - tr.points[1]) / elapsed else Vector3.zero
end

local function watchImpacts(_dt: number)
	local params = rayParams
	if not params then
		return
	end
	local t = now()
	local clock = os.clock()
	for model, f in Fighters.all() do
		local root = f.root
		if root.Parent and f.humanoid.Health > 0 then
			local tr = tracks[model]
			if not tr then
				tr = { times = {}, points = {}, launchedUntil = 0 }
				tracks[model] = tr
			end
			local v = sample(tr, clock, root.Position)
			-- MobStrike.enlist marks the Junk Ram as downed forever (ragdollEnd = math.huge) so
			-- players can't knock it back; that is not a launch
			local ragdolled = f.ragdollEnd > t and f.ragdollEnd ~= math.huge
			local mover = root:FindFirstChild(KNOCKBACK_MOVER)
			if mover or ragdolled then
				tr.launchedUntil = clock + C.LAUNCH_GRACE
			end
			-- the samples need a moment to see a launch; the mover says at once where the body is
			-- going, so a body knocked into a wall breaks it before it stops against it
			if mover and mover:IsA("LinearVelocity") and mover.VectorVelocity.Magnitude > v.Magnitude then
				v = mover.VectorVelocity
			end
			local speed = v.Magnitude
			if clock < tr.launchedUntil and speed >= C.IMPACT_MIN_SPEED and clock - (lastImpact[model] or 0) >= C.IMPACT_COOLDOWN then
				local dir = v.Unit
				local hit = workspace:Raycast(root.Position, dir * (speed * C.LOOKAHEAD_TIME + C.IMPACT_LOOKAHEAD), params)
				if hit and hit.Instance:IsA("BasePart") and DestructionService.isBreakable(hit.Instance) then
					local radius = math.min(C.IMPACT_RADIUS_MAX, C.IMPACT_RADIUS_BASE + (speed - C.IMPACT_MIN_SPEED) * C.IMPACT_RADIUS_PER_SPEED)
					local credit = if creditFn then creditFn(model) else nil
					local n = DestructionService.blast(hit.Position + dir * radius * 0.3, radius, credit, speed / C.IMPACT_MIN_SPEED, dir)
					if n > 0 then
						lastImpact[model] = clock
						-- a server-owned (ragdolled) body loses some speed going through
						if ragdolled then
							root.AssemblyLinearVelocity *= C.IMPACT_SLOWDOWN
						end
					end
				end
			end
		end
	end
end

function DestructionService.start()
	for _, path in C.ROOTS do
		local node: Instance? = workspace
		for _, name in path do
			node = node and node:FindFirstChild(name)
		end
		if node then
			table.insert(roots, node)
		else
			warn("[Destruction] missing root " .. table.concat(path, "."))
		end
	end
	local o = OverlapParams.new()
	o.FilterType = Enum.RaycastFilterType.Include
	o.FilterDescendantsInstances = roots
	o.RespectCanCollide = false
	overlap = o
	local r = RaycastParams.new()
	r.FilterType = Enum.RaycastFilterType.Include
	r.FilterDescendantsInstances = roots
	r.RespectCanCollide = false
	rayParams = r

	local folder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = REMOTE_FOLDER
		folder.Parent = ReplicatedStorage
	end
	local debrisRemote = (folder :: Instance):FindFirstChild("Debris")
	if not debrisRemote then
		debrisRemote = Instance.new("RemoteEvent")
		debrisRemote.Name = "Debris"
		debrisRemote.Parent = folder
	end
	remote = debrisRemote :: RemoteEvent

	RunService.Heartbeat:Connect(watchImpacts)
	task.spawn(function()
		while true do
			task.wait(RESTORE_TICK)
			local ok, err = pcall(restoreTick)
			if not ok then
				warn("[Destruction] regrowth: " .. tostring(err))
			end
		end
	end)
end

return DestructionService
