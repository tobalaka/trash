--!strict
--[[
	Itinerary - the town walk graph (baked by tools/BakeTownGraph.luau into TownGraph) and the
	walkers' deterministic legs.

	A walker's day is a loop of legs, each Config.LEG_TIME long and keyed by its index k on the
	server clock: walk out from home along a seeded route, pause, walk the same route back, idle at
	home until the next leg. Walkers keep to the right of the street centre line, so the way back
	is on the other side. Everything follows from (seed, k), so every client sees each walker in
	the same place without any networking.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Townsfolk"))

local Itinerary = {}

export type Link = { to: number, edge: number }
export type Graph = {
	nodes: { Vector3 },
	adjacency: { { Link } },
	edgeA: { number },
	edgeB: { number },
	clear: { number },
	length: { number },
	profiles: { [number]: { number } },
	homes: { number }, -- nodes a walker can start from (at least one edge)
}
export type Walker = { seed: number, home: number, speed: number, offset: number }
export type Leg = {
	k: number,
	route: { number }, -- node indices, home first
	edges: { number }, -- the edge of each hop
	at: { number }, -- distance from home at each route node
	total: number,
	out: number, -- seconds walking out (and back)
	pause: number,
}
export type Sample = {
	position: Vector3, -- on the ground, keep-right offset applied
	heading: Vector3, -- unit, horizontal
	moving: boolean,
	travelled: number, -- distance walked this leg (drives the gait)
}

local XZ = Vector3.new(1, 0, 1)
local FORWARD = Vector3.new(0, 0, -1)

local function flatUnit(v: Vector3): Vector3?
	local f = v * XZ
	return if f.Magnitude > 1e-4 then f.Unit else nil
end

function Itinerary.load(data: any): Graph
	local nodes: { Vector3 } = {}
	local raw = data.nodes :: { number }
	for i = 1, #raw, 3 do
		table.insert(nodes, Vector3.new(raw[i], raw[i + 1], raw[i + 2]))
	end
	local adjacency: { { Link } } = {}
	for i = 1, #nodes do
		adjacency[i] = {}
	end
	local g: Graph = {
		nodes = nodes,
		adjacency = adjacency,
		edgeA = {},
		edgeB = {},
		clear = {},
		length = {},
		profiles = data.profiles or {},
		homes = {},
	}
	local raw2 = data.edges :: { number }
	for k = 1, #raw2, 3 do
		local a, b = raw2[k], raw2[k + 1]
		local e = #g.edgeA + 1
		g.edgeA[e], g.edgeB[e], g.clear[e] = a, b, raw2[k + 2]
		g.length[e] = ((nodes[b] - nodes[a]) * XZ).Magnitude
		table.insert(adjacency[a], { to = b, edge = e })
		table.insert(adjacency[b], { to = a, edge = e })
	end
	for i, links in adjacency do
		if #links > 0 then
			table.insert(g.homes, i)
		end
	end
	return g
end

-- ground height `d` studs along edge e, measured from node `from`
local function heightOn(g: Graph, e: number, from: number, d: number): number
	local a, b = g.edgeA[e], g.edgeB[e]
	local t = math.clamp(if g.length[e] > 0 then d / g.length[e] else 0, 0, 1)
	if from ~= a then
		t = 1 - t
	end
	local profile = g.profiles[e]
	if profile then
		local x = t * (#profile - 1)
		local i = math.floor(x)
		local h0 = profile[i + 1]
		local h1 = profile[math.min(i + 2, #profile)]
		return h0 + (h1 - h0) * (x - i)
	end
	return g.nodes[a].Y + (g.nodes[b].Y - g.nodes[a].Y) * t
end

function Itinerary.leg(g: Graph, w: Walker, k: number): Leg
	local rng = Random.new(w.seed + k * 7919)
	local pause = rng:NextNumber(Config.PAUSE_MIN, Config.PAUSE_MAX)
	local longest = (Config.LEG_TIME - pause - Config.HOME_IDLE_MIN) * w.speed / 2
	local target = longest * rng:NextNumber(Config.LEG_MIN_FRACTION, 1)
	local route, edges, at = { w.home }, {}, { 0 }
	local node, prev = w.home, 0
	local heading: Vector3? = nil
	local total = 0
	local weights: { number } = {}
	while total < target and #edges < Config.MAX_HOPS do
		local links = g.adjacency[node]
		local sum = 0
		for i, link in links do
			local weight = 1
			if link.to == prev and #links > 1 then
				weight = 0.05 -- turning back only at a dead end, nearly
			elseif heading then
				local d = flatUnit(g.nodes[link.to] - g.nodes[node]) or heading
				weight = 0.25 + math.max(0, heading:Dot(d)) ^ 2 * Config.STRAIGHT_BIAS
			end
			weights[i] = weight
			sum += weight
		end
		if sum <= 0 then
			break
		end
		local pick = rng:NextNumber(0, sum)
		local choice = links[#links]
		for i, link in links do
			pick -= weights[i]
			if pick <= 0 then
				choice = link
				break
			end
		end
		heading = flatUnit(g.nodes[choice.to] - g.nodes[node]) or heading
		total += g.length[choice.edge]
		table.insert(route, choice.to)
		table.insert(edges, choice.edge)
		table.insert(at, total)
		prev, node = node, choice.to
	end
	-- the whole leg must fit in LEG_TIME
	while #edges > 0 and 2 * total / w.speed + Config.PAUSE_MIN + Config.HOME_IDLE_MIN > Config.LEG_TIME do
		table.remove(route)
		table.remove(edges)
		table.remove(at)
		total = at[#at]
	end
	local out = total / w.speed
	return {
		k = k,
		route = route,
		edges = edges,
		at = at,
		total = total,
		out = out,
		pause = math.min(pause, Config.LEG_TIME - Config.HOME_IDLE_MIN - 2 * out),
	}
end

-- the point `s` studs from home along the leg, and the hop it lies on
local function pointAt(g: Graph, leg: Leg, s: number): (Vector3, number)
	local hops = #leg.edges
	if hops == 0 then
		return g.nodes[leg.route[1]], 0
	end
	s = math.clamp(s, 0, leg.total)
	local lo, hi = 1, hops
	while lo < hi do
		local mid = (lo + hi) // 2
		if leg.at[mid + 1] < s then
			lo = mid + 1
		else
			hi = mid
		end
	end
	local from, to = leg.route[lo], leg.route[lo + 1]
	local d = s - leg.at[lo]
	local span = leg.at[lo + 1] - leg.at[lo]
	local t = if span > 0 then d / span else 0
	local pa, pb = g.nodes[from], g.nodes[to]
	return Vector3.new(pa.X + (pb.X - pa.X) * t, heightOn(g, leg.edges[lo], from, d), pa.Z + (pb.Z - pa.Z) * t), lo
end

--[[
	Where walker `w` is at server time `now`, `lag` seconds behind its own schedule (a companion),
	`side` studs right of the centre line at most (clamped to each street's room). `cached` is the
	leg returned last time; pass it back to skip rebuilding the route.
]]
function Itinerary.sample(g: Graph, w: Walker, now: number, lag: number, side: number, cached: Leg?): (Sample, Leg)
	local tw = now + w.offset - lag
	local k = math.floor(tw / Config.LEG_TIME)
	local tau = tw - k * Config.LEG_TIME
	local leg = if cached and cached.k == k then cached else Itinerary.leg(g, w, k)

	local s, sign, moving, travelled
	if tau < leg.out then
		s, sign, moving, travelled = tau * w.speed, 1, true, tau * w.speed
	elseif tau < leg.out + leg.pause then
		s, sign, moving, travelled = leg.total, 1, false, leg.total
	elseif tau < 2 * leg.out + leg.pause then
		local back = (tau - leg.out - leg.pause) * w.speed
		s, sign, moving, travelled = leg.total - back, -1, true, leg.total + back
	else
		s, sign, moving, travelled = 0, -1, false, 2 * leg.total
	end

	local centre, hop = pointAt(g, leg, s)
	local ahead = pointAt(g, leg, s + Config.HEADING_LOOK * sign)
	local behind = pointAt(g, leg, s - Config.HEADING_LOOK * sign)
	local heading = flatUnit(ahead - behind)
	if not heading and hop > 0 then
		local a, b = g.nodes[leg.route[hop]], g.nodes[leg.route[hop + 1]]
		heading = flatUnit((b - a) * sign)
	end
	local dir = heading or FORWARD

	local position = centre
	if hop > 0 then
		local room = g.clear[leg.edges[hop]]
		local right = Vector3.new(-dir.Z, 0, dir.X)
		position += right * math.clamp(side, -room, room)
	end
	return { position = position, heading = dir, moving = moving, travelled = travelled }, leg
end

return Itinerary
