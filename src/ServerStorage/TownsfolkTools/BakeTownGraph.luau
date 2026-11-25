--!strict
--[[
	BakeTownGraph - Edit-mode tool. Bakes the walk graph and the standing spots of the Townsfolk
	crowd from MapGen's Town plan and the ground as built, and returns the Source of the generated
	ReplicatedStorage.Client.Townsfolk.TownGraph module plus a stats line.

	Run in Edit (MCP execute_luau or the Command Bar) with tools/syncserver.js serving this folder:
	load this file into a ModuleScript, then `local source, stats = require(module)()`.
	Re-run it whenever the town is rebuilt.

	Graph: nodes every SPACING studs along the radial lanes, the ring roads and a loop in each
	plaza, linked along their chains and to any node of another chain within LINK_DIST. An edge is
	kept only if a person can walk it: the ground (Workspace.Ground, never water) never steps more
	than MAX_STEP between SAMPLE-stud samples, and a body-sized sphere swept along it at waist and
	shin height hits nothing that collides. Each edge stores how far a walker may stray from its
	centre line (clear) and, where the ground is not a straight ramp (stairs), its height profile.

	Standing spots: MapGen's NPCSpawn markers (Vendor in front of shops, Shopper in front of
	stalls, Hall at the hilltop) grounded, checked for room and turned to face the right way, plus
	loiter spots beside the streets for chatting groups.
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local SPACING = 12
local SAMPLE = 2
local MAX_STEP = 1.25 -- the hill stairs rise 1 stud per 2; terrace ledges are 4+
local LINK_DIST = 17
local BODY_LIFT, BODY_RADIUS = 2.7, 1.2 -- waist sweep
local SHIN_LIFT, SHIN_RADIUS = 1.0, 0.6 -- shin sweep, for crates and sacks
local CLEAR_MAX = 6
local CLEAR_MARGIN = 1.6 -- half a body plus a little air
local SIDE_DROP = 0.5 -- ground beside the line must stay this level for a walker to stray there
local PROFILE_TOLERANCE = 0.15
local MIN_COMPONENT = 8
local PLAZA_LOOP: { [string]: number } = { Market = 30, Hilltop = 52 }
local MARGIN_FROM_DOME = 50
local STAND_RADIUS = 0.9
local STAND_GAP = 4
local STALL_SEARCH = 12
local LOITER_EVERY = 5 -- try a loiter spot beside every Nth node
local LOITER_RADIUS = 2.6
local LOITER_GAP = 7
local WALKER_HALF_WIDTH = 0.8
local GROUND_TOP = 400

local KIND = { Vendor = 1, Shopper = 2, Hall = 3, Loiter = 4 }

local UP = Vector3.yAxis

return function(): (string, string)
	local Town = require(ServerStorage:WaitForChild("MapGen"):WaitForChild("Regions"):WaitForChild("Town")) :: any
	local plan = Town.plan({})
	local centre: Vector3 = plan.center
	local ground = workspace:WaitForChild("Ground")
	local town = workspace:WaitForChild("World"):WaitForChild("Town")
	local walkable = { ground:WaitForChild("Chunks"), ground:WaitForChild("Structures"), ground:WaitForChild("TownPlinths") }

	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Include
	groundParams.FilterDescendantsInstances = walkable
	local stoopParams = RaycastParams.new() -- shop fronts may stand on a building's stoop
	stoopParams.FilterType = Enum.RaycastFilterType.Include
	stoopParams.FilterDescendantsInstances = { walkable[1], walkable[2], walkable[3], town:WaitForChild("Buildings") }
	local waterParams = RaycastParams.new()
	waterParams.FilterType = Enum.RaycastFilterType.Include
	waterParams.FilterDescendantsInstances = { ground:WaitForChild("Water") }

	local probe = Instance.new("Part")
	probe.Name = "TownsfolkBakeProbe"
	probe.Shape = Enum.PartType.Ball
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanQuery = false
	probe.CanTouch = false
	probe.Transparency = 1
	probe.Parent = workspace

	local ignore: { Instance } = { ground, town:WaitForChild("NPCSpawns"), probe }
	for _, name in { "Player", "Rig", "TrainingDummy", "_RamPreview", "Townsfolk" } do
		local m = workspace:FindFirstChild(name)
		if m then
			table.insert(ignore, m)
		end
	end
	local camera = workspace.CurrentCamera
	if camera then
		table.insert(ignore, camera)
	end
	local blockParams = RaycastParams.new()
	blockParams.FilterType = Enum.RaycastFilterType.Exclude
	blockParams.FilterDescendantsInstances = ignore
	blockParams.RespectCanCollide = true
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = ignore
	overlapParams.RespectCanCollide = true
	local stallParams = OverlapParams.new()
	stallParams.FilterType = Enum.RaycastFilterType.Include
	stallParams.FilterDescendantsInstances = { town:WaitForChild("Market") }

	local function dry(x: number, z: number, top: number, y: number): boolean
		local w = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, y - top - 0.1, 0), waterParams)
		return w == nil
	end

	-- the walkable surface under (x, z): the top one, or the one nearest below `near`
	local function groundAt(x: number, z: number, near: number?, params: RaycastParams?): number?
		local top = if near then near + 6 else GROUND_TOP
		local reach = if near then 13 else GROUND_TOP * 2
		local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -reach, 0), params or groundParams)
		if not hit then
			return nil
		end
		local y = hit.Position.Y
		return if dry(x, z, top, y) then y else nil
	end

	local function free(at: Vector3, radius: number): boolean
		probe.Size = Vector3.one * radius * 2
		probe.CFrame = CFrame.new(at)
		return #workspace:GetPartsInPart(probe, overlapParams) == 0
	end

	-- ── nodes along chains ──
	type Chain = { points: { Vector3 }, closed: boolean }
	local chains: { Chain } = {}
	for _, lane in plan.laneAngles do
		local dir = Vector3.new(math.cos(lane.a), 0, math.sin(lane.a))
		local pts = {}
		local r = math.max(lane.minR, SPACING)
		while r <= Town.DOME_RADIUS - MARGIN_FROM_DOME do
			table.insert(pts, centre + dir * r)
			r += SPACING
		end
		table.insert(chains, { points = pts, closed = false })
	end
	for _, ring in Town.RINGS do
		local n = math.floor(2 * math.pi * ring / SPACING)
		local pts = {}
		for i = 0, n - 1 do
			local a = i / n * 2 * math.pi
			table.insert(pts, centre + Vector3.new(math.cos(a), 0, math.sin(a)) * ring)
		end
		table.insert(chains, { points = pts, closed = true })
	end
	for _, plaza in plan.plazas do
		local loopR = PLAZA_LOOP[plaza.kind]
		if loopR then
			local n = math.floor(2 * math.pi * loopR / (SPACING * 0.8))
			local pts = {}
			for i = 0, n - 1 do
				local a = i / n * 2 * math.pi
				table.insert(pts, Vector3.new(plaza.c.X + math.cos(a) * loopR, 0, plaza.c.Z + math.sin(a) * loopR))
			end
			table.insert(chains, { points = pts, closed = true })
		end
	end

	local nodes: { Vector3 } = {}
	local chainOf: { number } = {}
	local chainNodes: { { number | false } } = {}
	for ci, chain in chains do
		local list: { number | false } = {}
		for _, pt in chain.points do
			local y = groundAt(pt.X, pt.Z)
			local pos = if y then Vector3.new(pt.X, y, pt.Z) else nil
			if pos and free(pos + UP * BODY_LIFT, BODY_RADIUS) then
				table.insert(nodes, pos)
				table.insert(chainOf, ci)
				table.insert(list, #nodes)
			else
				table.insert(list, false)
			end
		end
		chainNodes[ci] = list
		task.wait()
	end

	-- ── edges ──
	local function walk(a: Vector3, b: Vector3): { number }?
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local n = math.max(1, math.ceil(flat.Magnitude / SAMPLE))
		local heights = { a.Y }
		local prev = a
		for i = 1, n do
			local t = i / n
			local x, z = a.X + flat.X * t, a.Z + flat.Z * t
			local y = groundAt(x, z, prev.Y)
			if not y or math.abs(y - prev.Y) > MAX_STEP then
				return nil
			end
			local pos = Vector3.new(x, y, z)
			local d = pos - prev
			if workspace:Spherecast(prev + UP * BODY_LIFT, BODY_RADIUS, d, blockParams) then
				return nil
			end
			if workspace:Spherecast(prev + UP * SHIN_LIFT, SHIN_RADIUS, d, blockParams) then
				return nil
			end
			table.insert(heights, y)
			prev = pos
		end
		if math.abs(prev.Y - b.Y) > 0.3 then
			return nil
		end
		return heights
	end

	local function clearance(a: Vector3, b: Vector3, heights: { number }): number
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
		local perp = Vector3.new(-flat.Z, 0, flat.X)
		local best = CLEAR_MAX
		for _, t in { 0.25, 0.5, 0.75 } do
			local h = heights[math.clamp(math.round(t * (#heights - 1)) + 1, 1, #heights)]
			local m = Vector3.new(a.X + (b.X - a.X) * t, h, a.Z + (b.Z - a.Z) * t)
			for _, s in { 1, -1 } do
				local hit = workspace:Raycast(m + UP * BODY_LIFT, perp * s * (CLEAR_MAX + CLEAR_MARGIN), blockParams)
				local o = math.floor(if hit then math.min(hit.Distance - CLEAR_MARGIN, CLEAR_MAX) else CLEAR_MAX)
				while o > 0 do
					local g = groundAt(m.X + perp.X * s * o, m.Z + perp.Z * s * o, m.Y)
					if g and math.abs(g - m.Y) <= SIDE_DROP then
						break
					end
					o -= 1
				end
				best = math.min(best, math.max(o, 0))
			end
		end
		return best
	end

	type Edge = { a: number, b: number, clear: number, profile: { number }? }
	local edges: { Edge } = {}
	local seen: { [string]: boolean } = {}
	local tried = 0
	local function link(i: number, j: number)
		local key = if i < j then i .. ":" .. j else j .. ":" .. i
		if seen[key] then
			return
		end
		seen[key] = true
		tried += 1
		if tried % 60 == 0 then
			task.wait()
		end
		local a, b = nodes[i], nodes[j]
		local heights = walk(a, b)
		if not heights then
			return
		end
		local profile: { number }? = nil
		local n = #heights - 1
		for k, h in heights do
			if math.abs(h - (a.Y + (b.Y - a.Y) * (k - 1) / n)) > PROFILE_TOLERANCE then
				profile = heights
				break
			end
		end
		table.insert(edges, { a = i, b = j, clear = clearance(a, b, heights), profile = profile })
	end

	for ci, list in chainNodes do
		local count = #list
		for k = 1, count do
			local nextK = if k < count then k + 1 elseif chains[ci].closed then 1 else nil
			local i, j = list[k], nextK and list[nextK]
			if i and j and i ~= j then
				link(i :: number, j :: number)
			end
		end
	end
	-- links between chains: lane x ring crossings, plaza loops to avenues
	local cells: { [string]: { number } } = {}
	local function cellKey(x: number, z: number): string
		return math.floor(x / LINK_DIST) .. "," .. math.floor(z / LINK_DIST)
	end
	for i, pos in nodes do
		local key = cellKey(pos.X, pos.Z)
		cells[key] = cells[key] or {}
		table.insert(cells[key], i)
	end
	for i, pos in nodes do
		local cx, cz = math.floor(pos.X / LINK_DIST), math.floor(pos.Z / LINK_DIST)
		for dx = -1, 1 do
			for dz = -1, 1 do
				for _, j in cells[(cx + dx) .. "," .. (cz + dz)] or {} do
					if j > i and chainOf[j] ~= chainOf[i] then
						local d = (nodes[j] - pos) * Vector3.new(1, 0, 1)
						if d.Magnitude > 0.5 and d.Magnitude <= LINK_DIST then
							link(i, j)
						end
					end
				end
			end
		end
	end

	-- ── keep the connected pieces big enough to wander ──
	local adjacency: { { number } } = {}
	for i = 1, #nodes do
		adjacency[i] = {}
	end
	for _, e in edges do
		table.insert(adjacency[e.a], e.b)
		table.insert(adjacency[e.b], e.a)
	end
	local keep: { boolean } = {}
	local visited: { boolean } = {}
	for start = 1, #nodes do
		if not visited[start] then
			local stack, members = { start }, {}
			visited[start] = true
			while #stack > 0 do
				local v = table.remove(stack) :: number
				table.insert(members, v)
				for _, w in adjacency[v] do
					if not visited[w] then
						visited[w] = true
						table.insert(stack, w)
					end
				end
			end
			if #members >= MIN_COMPONENT then
				for _, v in members do
					keep[v] = true
				end
			end
		end
	end
	local newIndex: { number } = {}
	local keptNodes: { Vector3 } = {}
	for i, pos in nodes do
		if keep[i] then
			table.insert(keptNodes, pos)
			newIndex[i] = #keptNodes
		end
	end
	local keptEdges: { Edge } = {}
	for _, e in edges do
		if keep[e.a] and keep[e.b] then
			table.insert(keptEdges, { a = newIndex[e.a], b = newIndex[e.b], clear = e.clear, profile = e.profile })
		end
	end

	-- ── standing spots ──
	type Stand = { pos: Vector3, yaw: number, kind: number }
	local stands: { Stand } = {}
	local function yawOf(look: Vector3): number
		return math.atan2(-look.X, -look.Z) -- CFrame.Angles(0, yaw, 0).LookVector == look
	end
	local function roomFor(pos: Vector3, gap: number): boolean
		for _, s in stands do
			if (s.pos - pos).Magnitude < gap then
				return false
			end
		end
		return true
	end
	local function addStand(pos: Vector3, look: Vector3, kind: number, gap: number): boolean
		if not roomFor(pos, gap) then
			return false
		end
		table.insert(stands, { pos = pos, yaw = yawOf(look), kind = kind })
		return true
	end
	local hall = town:FindFirstChild("Landmarks") and town.Landmarks:FindFirstChild("HillHall")
	local rejected = { Vendor = 0, Shopper = 0, Hall = 0 }
	for _, marker in CollectionService:GetTagged("NPCSpawn") do
		if not marker:IsA("BasePart") or not marker:IsDescendantOf(town) then
			continue
		end
		local kind = tostring(marker:GetAttribute("Kind"))
		local at = marker.Position
		local y = groundAt(at.X, at.Z, at.Y, stoopParams)
		local pos = if y then Vector3.new(at.X, y, at.Z) else nil
		if not pos or not free(pos + UP * BODY_LIFT, STAND_RADIUS) then
			if rejected[kind] then
				rejected[kind] += 1
			end
			continue
		end
		local look = Vector3.new(marker.CFrame.LookVector.X, 0, marker.CFrame.LookVector.Z)
		look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
		if kind == "Vendor" then
			-- stand in front of the shop with your back to it
			local behind = workspace:Raycast(pos + UP * BODY_LIFT, -look * 10, blockParams)
			local ahead = workspace:Raycast(pos + UP * BODY_LIFT, look * 6, blockParams)
			if not behind and ahead then
				look = -look
			end
			addStand(pos, look, KIND.Vendor, STAND_GAP)
		elseif kind == "Shopper" then
			local best, bestDist = nil, math.huge
			for _, part in workspace:GetPartBoundsInRadius(pos, STALL_SEARCH, stallParams) do
				local d = (part.Position - pos) * Vector3.new(1, 0, 1)
				if d.Magnitude < bestDist then
					best, bestDist = d, d.Magnitude
				end
			end
			if best and bestDist > 0.1 then
				look = best.Unit
			end
			addStand(pos, look, KIND.Shopper, STAND_GAP)
		elseif kind == "Hall" then
			if hall and hall:IsA("Model") then
				local away = (pos - hall:GetPivot().Position) * Vector3.new(1, 0, 1)
				if away.Magnitude > 0.1 then
					look = away.Unit
				end
			end
			addStand(pos, look, KIND.Hall, STAND_GAP)
		end
	end
	task.wait()

	-- loiter spots beside the streets, out of the walkers' band
	local loiters = 0
	for k, e in keptEdges do
		if k % LOITER_EVERY ~= 0 then
			continue
		end
		local a, b = keptNodes[e.a], keptNodes[e.b]
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
		local perp = Vector3.new(-flat.Z, 0, flat.X)
		local mid = a:Lerp(b, 0.5)
		for _, s in { 1, -1 } do
			local at = mid + perp * s * (e.clear + LOITER_RADIUS)
			local y = groundAt(at.X, at.Z, mid.Y)
			if not y or math.abs(y - mid.Y) > SIDE_DROP then
				continue
			end
			local pos = Vector3.new(at.X, y, at.Z)
			local level = true
			for q = 0, 3 do
				local o = Vector3.new(math.cos(q * math.pi / 2), 0, math.sin(q * math.pi / 2)) * LOITER_RADIUS
				local gy = groundAt(pos.X + o.X, pos.Z + o.Z, y)
				if not gy or math.abs(gy - y) > SIDE_DROP then
					level = false
					break
				end
			end
			if level and free(pos + UP * BODY_LIFT, LOITER_RADIUS) and addStand(pos, -perp * s, KIND.Loiter, LOITER_GAP) then
				loiters += 1
				break
			end
		end
		if k % 40 == 0 then
			task.wait()
		end
	end
	probe:Destroy()

	-- walkers keep out of anyone standing beside their street: narrow each edge's band
	local narrowed = 0
	for k, e in keptEdges do
		local a, b = keptNodes[e.a], keptNodes[e.b]
		local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local len = flat.Magnitude
		local dir = flat / len
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		for _, s in stands do
			local rel = (s.pos - a) * Vector3.new(1, 0, 1)
			local along = rel:Dot(dir)
			if along > -STAND_GAP and along < len + STAND_GAP and math.abs(s.pos.Y - a.Y) < BODY_LIFT * 2 then
				local reach = (if s.kind == KIND.Loiter then LOITER_RADIUS else STAND_RADIUS) + WALKER_HALF_WIDTH
				local room = math.floor((math.abs(rel:Dot(perp)) - reach) * 2) / 2
				if room < e.clear then
					e.clear = math.max(room, 0)
					narrowed += 1
				end
			end
		end
		if k % 200 == 0 then
			task.wait()
		end
	end

	-- ── source ──
	local function fmt(v: number, places: number): string
		local s = string.format("%." .. places .. "f", v)
		s = s:gsub("%.?0+$", "")
		return if s == "-0" or s == "" then "0" else s
	end
	local out = {
		"--!strict",
		"-- Generated by Townsfolk tools/BakeTownGraph.luau on " .. os.date("!%Y-%m-%d") .. ". Do not edit by hand:",
		"-- re-run the bake whenever the town is rebuilt.",
		"return {",
		"\tversion = 1,",
		"\tsample = " .. SAMPLE .. ", -- studs between profile heights",
		"\t-- x, y, z per node",
		"\tnodes = {",
	}
	local function block(values: { string }, per: number)
		for i = 1, #values, per do
			table.insert(out, "\t\t" .. table.concat(values, ", ", i, math.min(i + per - 1, #values)) .. ",")
		end
	end
	local nv = {}
	for _, pos in keptNodes do
		table.insert(nv, fmt(pos.X, 1))
		table.insert(nv, fmt(pos.Y, 2))
		table.insert(nv, fmt(pos.Z, 1))
	end
	block(nv, 24)
	table.insert(out, "\t},")
	table.insert(out, "\t-- node a, node b, clear (how far a walker may stray from the centre line) per edge")
	table.insert(out, "\tedges = {")
	local ev = {}
	local profiles = 0
	for _, e in keptEdges do
		table.insert(ev, tostring(e.a))
		table.insert(ev, tostring(e.b))
		table.insert(ev, fmt(e.clear, 1))
	end
	block(ev, 30)
	table.insert(out, "\t},")
	table.insert(out, "\t-- ground heights every `sample` studs from a to b, for edges that are not a straight ramp")
	table.insert(out, "\tprofiles = {")
	for k, e in keptEdges do
		local prof = e.profile
		if prof then
			profiles += 1
			local hv = {}
			for _, h in prof do
				table.insert(hv, fmt(h, 2))
			end
			table.insert(out, "\t\t[" .. k .. "] = { " .. table.concat(hv, ", ") .. " },")
		end
	end
	table.insert(out, "\t},")
	table.insert(out, "\t-- x, y, z, yaw (radians), kind (1 Vendor, 2 Shopper, 3 Hall, 4 Loiter) per standing spot")
	table.insert(out, "\tstands = {")
	local sv = {}
	local byKind = { 0, 0, 0, 0 }
	for _, s in stands do
		table.insert(sv, fmt(s.pos.X, 1))
		table.insert(sv, fmt(s.pos.Y, 2))
		table.insert(sv, fmt(s.pos.Z, 1))
		table.insert(sv, fmt(s.yaw, 3))
		table.insert(sv, tostring(s.kind))
		byKind[s.kind] += 1
	end
	block(sv, 25)
	table.insert(out, "\t},")
	table.insert(out, "}")
	table.insert(out, "")

	local stats = string.format(
		"nodes %d (of %d), edges %d (of %d tried, %d narrowed around stands), profiles %d, stands vendor %d shopper %d hall %d loiter %d, rejected markers vendor %d shopper %d hall %d",
		#keptNodes, #nodes, #keptEdges, tried, narrowed, profiles, byKind[1], byKind[2], byKind[3], byKind[4],
		rejected.Vendor, rejected.Shopper, rejected.Hall
	)
	return table.concat(out, "\n"), stats
end
