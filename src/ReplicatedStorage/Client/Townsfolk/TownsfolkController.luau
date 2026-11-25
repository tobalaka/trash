--!strict
--[[
	TownsfolkController - the ambient town crowd, entirely on this client. It is cosmetic: no
	server cost, no networking, and nothing a player can hit, stand on or raycast against.

	The population comes from Config.SEED and the baked TownGraph, so it is identical on every
	client: walkers on deterministic legs (some in pairs, a parent with a kid, some carrying
	goods), shopkeepers in front of shops, shoppers at stalls, chatting groups beside the streets
	and the crier in front of the hill hall. Only agents near the player get a body (Looks), at
	most Config.MAX_ACTIVE, built a few per frame. Each frame Animate poses them (less often when
	far or behind the camera) and one workspace:BulkMoveTo moves every part.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Townsfolk"))
local Itinerary = require(script.Parent:WaitForChild("Itinerary"))
local Looks = require(script.Parent:WaitForChild("Looks"))
local Animate = require(script.Parent:WaitForChild("Animate"))

type Agent = {
	id: number,
	role: Looks.Role,
	seed: number,
	kid: boolean,
	carry: string?,
	scale: number,
	walker: Itinerary.Walker?, -- shared by a walker and its companion
	lag: number,
	side: number,
	leg: Itinerary.Leg?,
	position: Vector3,
	yaw: number,
	member: number,
	members: number,
	distance: number,
	wanted: boolean,
	body: Looks.Body?,
	state: Animate.State?,
	last: number, -- server time of the last pose
}

local ROLE_OF_KIND: { [number]: Looks.Role } = { "Vendor", "Shopper", "Crier", "Loiter" }
local SHARE_OF_KIND = { Config.VENDOR_SHARE, Config.SHOPPER_SHARE, 1, Config.LOITER_SHARE }
local CARRIES = { "Crate", "Sack", "Bucket" }
local KEEP_BONUS = 20 -- an agent with a body ranks this much closer, so bodies don't flicker at the edge
local MATE_KID_CHANCE = 0.3 -- a companion is a kid this often (a parent and child)
local LOITER_KID_CHANCE = 0.1
local MAX_DT = 0.5
local MAX_SEED = 1000000

local TownsfolkController = {}

local function populate(graph: Itinerary.Graph, stands: { number }): ({ Agent }, { Agent })
	local rng = Random.new(Config.SEED)
	local walkers: { Agent } = {}
	local standing: { Agent } = {}
	local count = 0
	local function agent(role: Looks.Role, seed: number, kid: boolean, position: Vector3, yaw: number): Agent
		count += 1
		return {
			id = count,
			role = role,
			seed = seed,
			kid = kid,
			carry = nil,
			scale = if kid then Config.KID_SCALE else rng:NextNumber(Config.ADULT_SCALE_MIN, Config.ADULT_SCALE_MAX),
			walker = nil,
			lag = 0,
			side = 0,
			leg = nil,
			position = position,
			yaw = yaw,
			member = 1,
			members = 1,
			distance = math.huge,
			wanted = false,
			body = nil,
			state = nil,
			last = 0,
		}
	end

	if #graph.homes > 0 then
		for _ = 1, Config.WALKERS do
			local kid = rng:NextNumber() < Config.KID_CHANCE
			local walker: Itinerary.Walker = {
				seed = rng:NextInteger(1, MAX_SEED),
				home = graph.homes[rng:NextInteger(1, #graph.homes)],
				speed = if kid then Config.KID_SPEED else rng:NextNumber(Config.SPEED_MIN, Config.SPEED_MAX),
				offset = rng:NextNumber(0, Config.LEG_TIME),
			}
			local a = agent("Walker", walker.seed, kid, graph.nodes[walker.home], 0)
			a.walker = walker
			a.side = rng:NextNumber(Config.SIDE_MIN, Config.SIDE_MAX)
			if not kid and rng:NextNumber() < Config.CARRY_CHANCE then
				a.carry = CARRIES[rng:NextInteger(1, #CARRIES)]
			end
			table.insert(walkers, a)
			if not kid and rng:NextNumber() < Config.PAIR_CHANCE then
				local mate = agent("Walker", rng:NextInteger(1, MAX_SEED), rng:NextNumber() < MATE_KID_CHANCE, a.position, 0)
				mate.walker = walker
				mate.lag = Config.PAIR_LAG
				mate.side = a.side - Config.PAIR_GAP
				table.insert(walkers, mate)
			end
		end
	end

	for i = 1, #stands, 5 do
		local position = Vector3.new(stands[i], stands[i + 1], stands[i + 2])
		local kind = stands[i + 4]
		local role = ROLE_OF_KIND[kind]
		if not role or rng:NextNumber() >= SHARE_OF_KIND[kind] then
			continue
		end
		if role == "Loiter" then
			local n = rng:NextInteger(Config.LOITER_MIN, Config.LOITER_MAX)
			local base = rng:NextNumber(0, 2 * math.pi)
			for m = 1, n do
				local a = base + (m - 1) / n * 2 * math.pi
				local at = position + Vector3.new(math.cos(a), 0, math.sin(a)) * Config.LOITER_RING
				local inward = position - at
				local member = agent("Loiter", rng:NextInteger(1, MAX_SEED), rng:NextNumber() < LOITER_KID_CHANCE, at, math.atan2(-inward.X, -inward.Z))
				member.member, member.members = m, n
				table.insert(standing, member)
			end
		else
			table.insert(standing, agent(role, rng:NextInteger(1, MAX_SEED), false, position, stands[i + 3]))
		end
	end
	return walkers, standing
end

function TownsfolkController.start()
	local data = require(script.Parent:WaitForChild("TownGraph")) :: any
	local graph = Itinerary.load(data)
	local walkers, standing = populate(graph, data.stands)

	-- standing agents never move: index them by cell
	local grid: { [number]: { Agent } } = {}
	local function cellKey(cx: number, cz: number): number
		return (cx + 4096) * 8192 + (cz + 4096)
	end
	for _, a in standing do
		local key = cellKey(math.floor(a.position.X / Config.GRID_CELL), math.floor(a.position.Z / Config.GRID_CELL))
		grid[key] = grid[key] or {}
		table.insert(grid[key], a)
	end

	local folder = Instance.new("Folder")
	folder.Name = "Townsfolk"
	folder.Parent = workspace

	local player = Players.LocalPlayer
	local active: { Agent } = {}
	local queue: { Agent } = {}
	local candidates: { Agent } = {}
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local frame = 0
	local lastScan = -math.huge

	local function focus(): Vector3?
		local character = player.Character
		local head = character and character:FindFirstChild("Head")
		return if head and head:IsA("BasePart") then head.Position else nil
	end

	local function origin(): Vector3
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.Position
		end
		local camera = workspace.CurrentCamera
		return if camera then camera.CFrame.Position else Vector3.zero
	end

	local function drive(a: Agent, now: number): Animate.Drive
		local walker = a.walker
		if walker then
			local sample, leg = Itinerary.sample(graph, walker, now, a.lag, a.side, a.leg)
			a.leg = leg
			a.position = sample.position
			return {
				position = sample.position,
				yaw = math.atan2(-sample.heading.X, -sample.heading.Z),
				moving = sample.moving,
				speed = walker.speed,
				travelled = sample.travelled,
				role = a.role,
				seed = a.seed,
				member = 1,
				members = 1,
			}
		end
		return {
			position = a.position,
			yaw = a.yaw,
			moving = false,
			speed = 0,
			travelled = 0,
			role = a.role,
			seed = a.seed,
			member = a.member,
			members = a.members,
		}
	end

	local function pose(a: Agent, now: number, dt: number, out: { BasePart }, outFrames: { CFrame })
		local body, state = a.body, a.state
		if body and state then
			Animate.step(body, state, drive(a, now), now, dt, focus(), out, outFrames)
		end
	end

	local function spawn(a: Agent, now: number)
		local d = drive(a, now)
		local body = Looks.build(a.seed, a.role, a.kid, a.carry, a.scale)
		a.body = body
		a.state = Animate.newState(d.yaw)
		a.last = now
		-- place it before it appears, so it never shows at the origin
		local first: { BasePart }, firstFrames: { CFrame } = {}, {}
		pose(a, now, 0, first, firstFrames)
		for i, part in first do
			part.CFrame = firstFrames[i]
		end
		body.model.Parent = folder
		table.insert(active, a)
	end

	local function despawn(a: Agent)
		local body = a.body
		if body then
			body.model:Destroy()
		end
		a.body, a.state, a.leg = nil, nil, nil
	end

	local function scan(now: number)
		local at = origin()
		table.clear(candidates)
		local reach = math.ceil(Config.DESPAWN_RADIUS / Config.GRID_CELL)
		local cx, cz = math.floor(at.X / Config.GRID_CELL), math.floor(at.Z / Config.GRID_CELL)
		for dx = -reach, reach do
			for dz = -reach, reach do
				for _, a in grid[cellKey(cx + dx, cz + dz)] or {} do
					a.distance = (a.position - at).Magnitude
					if a.distance < Config.DESPAWN_RADIUS then
						table.insert(candidates, a)
					end
				end
			end
		end
		for _, a in walkers do
			local walker = a.walker :: Itinerary.Walker
			local sample, leg = Itinerary.sample(graph, walker, now, a.lag, a.side, a.leg)
			a.leg = leg
			a.position = sample.position
			a.distance = (a.position - at).Magnitude
			if a.distance < Config.DESPAWN_RADIUS then
				table.insert(candidates, a)
			end
		end
		table.sort(candidates, function(p: Agent, q: Agent): boolean
			return p.distance - (if p.body then KEEP_BONUS else 0) < q.distance - (if q.body then KEEP_BONUS else 0)
		end)
		for _, a in active do
			a.wanted = false
		end
		table.clear(queue)
		local kept = 0
		for _, a in candidates do
			if kept >= Config.MAX_ACTIVE then
				break
			end
			if a.body or a.distance < Config.SPAWN_RADIUS then
				a.wanted = true
				kept += 1
				if not a.body then
					table.insert(queue, a)
				end
			end
		end
		for i = #active, 1, -1 do
			local a = active[i]
			if not a.wanted then
				despawn(a)
				table.remove(active, i)
			end
		end
	end

	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		frame += 1
		local clock = os.clock()
		if clock - lastScan >= Config.SCAN_INTERVAL then
			lastScan = clock
			scan(now)
		end
		for _ = 1, Config.SPAWNS_PER_FRAME do
			local a = table.remove(queue, 1)
			if not a then
				break
			end
			if a.wanted and not a.body then
				spawn(a, now)
			end
		end

		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye, look = camera.CFrame.Position, camera.CFrame.LookVector
		table.clear(parts)
		table.clear(cframes)
		for _, a in active do
			local offset = a.position - eye
			local d = offset.Magnitude
			local every = if d < Config.LOD_NEAR then 1 elseif d < Config.LOD_MID then Config.LOD_MID_EVERY else Config.LOD_FAR_EVERY
			if d > Config.BEHIND_CAMERA_SKIP and offset:Dot(look) < 0 then
				every = Config.LOD_FAR_EVERY
			end
			if (frame + a.id) % every == 0 then
				pose(a, now, math.clamp(now - a.last, 0, MAX_DT), parts, cframes)
				a.last = now
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return TownsfolkController
