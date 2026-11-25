--!strict
--[[
	DebrisFx - the flying chunks of a break, on this client only (server: DestructionService).
	Each chunk is an anchored, non-colliding Part moved by a tiny simulation (gravity, a raycast
	bounce off the map, friction, spin), all moved together with workspace:BulkMoveTo. Chunks
	never push players and cost the server nothing. After DEBRIS_LIFETIME they shrink away.
	A dust puff (built-in smoke texture) and the combat "Slam" sound play at the impact. The sound
	goes through TRASH-Combat's Client/Audio when the place has it (its mixer volume, voice cap
	and per-cue rate limit keep a chain of breaks from stacking), else a plain Sound.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared:WaitForChild("Config"):WaitForChild("Destruction"))

local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- ships with Roblox
local REST_SPEED = 2 -- below this on a floor a chunk settles
local FLOOR_NORMAL = 0.6
local DUST_TIME = 3
local SOUND_VOLUME = 0.7

type Chunk = {
	part: BasePart,
	pos: Vector3,
	vel: Vector3,
	rot: CFrame,
	spin: Vector3,
	size: Vector3,
	born: number,
	resting: boolean,
}

local DebrisFx = {}

local chunks: { Chunk } = {}
local folder: Folder? = nil
local rng = Random.new()

local function container(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local made = Instance.new("Folder")
	made.Name = "DestructionDebris"
	made.Parent = workspace
	folder = made
	return made
end

local function slamSound(): string?
	local ok, sounds = pcall(function()
		return require(Shared:WaitForChild("Config"):WaitForChild("Sounds", 2) :: ModuleScript) :: any
	end)
	if ok and typeof(sounds) == "table" and typeof(sounds.Slam) == "table" then
		return sounds.Slam[1]
	end
	return nil
end
local SLAM = slamSound()

-- TRASH-Combat's mixer, when present (optional: this package also runs alone)
local function mixer(): any
	local client = ReplicatedStorage:FindFirstChild("Client")
	local module = client and client:FindFirstChild("Audio")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, audio = pcall(require, module)
	return if ok and typeof(audio) == "table" and typeof(audio.play) == "function" then audio else nil
end
local Audio = mixer()

local function rayParams(): RaycastParams
	local exclude: { Instance } = { container() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

local function dust(at: Vector3, color: Color3, power: number)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.new(at)
	holder.Parent = container()
	local e = Instance.new("ParticleEmitter")
	e.Texture = DUST_TEXTURE
	e.Color = ColorSequence.new(color:Lerp(Color3.fromRGB(200, 190, 170), 0.5))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6 * math.min(power, 2)) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1, 1.8)
	e.Speed = NumberRange.new(4, 12)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Rotation = NumberRange.new(0, 360)
	e.LightInfluence = 1
	e.Enabled = false
	e.Parent = holder
	e:Emit(C.DUST_PARTICLES)
	if Audio then
		Audio.play("Slam", holder, SOUND_VOLUME * 0.6 * math.min(power, 1.5), rng:NextNumber(0.85, 1.05))
	elseif SLAM then
		local s = Instance.new("Sound")
		s.SoundId = SLAM
		s.Volume = SOUND_VOLUME
		s.RollOffMaxDistance = 220
		s.PlaybackSpeed = rng:NextNumber(0.85, 1.05)
		s.Parent = holder
		s:Play()
	end
	task.delay(DUST_TIME, function()
		holder:Destroy()
	end)
end

local BOX_BYTES = 12 -- per chunk in a group's `boxes` buffer (see DestructionService.pack)

-- `g` is the payload group the chunk belongs to (its source part's look)
local function spawnChunk(g: any, cf: CFrame, boxSize: Vector3, at: Vector3, dir: Vector3, power: number)
	local size = boxSize * C.DEBRIS_SHRINK
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = size.Magnitude > 2
	part.Size = size
	part.Color = g.color
	part.Material = g.material
	part.Transparency = g.transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cf
	part.Parent = container()
	local out = cf.Position - at
	local away = if out.Magnitude > 1e-3 then out.Unit else Vector3.yAxis
	local push = (away + dir * 1.5)
	push = if push.Magnitude > 1e-3 then push.Unit else away
	local speed = rng:NextNumber(C.DEBRIS_SPEED[1], C.DEBRIS_SPEED[2]) * math.clamp(power, 0.6, 2.5)
	local jitter = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0, 1), rng:NextNumber(-1, 1)) * speed * 0.35
	table.insert(chunks, {
		part = part,
		pos = cf.Position,
		vel = push * speed + jitter + Vector3.new(0, C.DEBRIS_UP * rng:NextNumber(0.4, 1), 0),
		rot = cf.Rotation,
		spin = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * C.DEBRIS_SPIN,
		size = size,
		born = os.clock(),
		resting = false,
	})
	while #chunks > C.MAX_DEBRIS do
		local old = table.remove(chunks, 1)
		if old then
			old.part:Destroy()
		end
	end
end

local function valid(g: any): boolean
	return typeof(g) == "table"
		and typeof(g.cf) == "CFrame"
		and typeof(g.boxes) == "buffer"
		and typeof(g.color) == "Color3"
		and typeof(g.material) == "EnumItem"
		and typeof(g.transparency) == "number"
end

function DebrisFx.play(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.at) ~= "Vector3" or typeof(payload.groups) ~= "table" then
		return
	end
	local dir = if typeof(payload.dir) == "Vector3" then payload.dir else Vector3.zero
	local power = if typeof(payload.power) == "number" then payload.power else 1
	local q = C.DEBRIS_QUANT
	local first = nil
	for _, g in payload.groups do
		if valid(g) then
			first = first or g
			local b: buffer = g.boxes
			for i = 0, buffer.len(b) // BOX_BYTES - 1 do
				local o = i * BOX_BYTES
				local center = Vector3.new(buffer.readi16(b, o), buffer.readi16(b, o + 2), buffer.readi16(b, o + 4)) / q
				local size = Vector3.new(buffer.readu16(b, o + 6), buffer.readu16(b, o + 8), buffer.readu16(b, o + 10)) / q
				spawnChunk(g, g.cf * CFrame.new(center), size, payload.at, dir, power)
			end
		end
	end
	if first then
		dust(payload.at, first.color, power)
	end
end

local function step(dt: number)
	if #chunks == 0 then
		return
	end
	local params = rayParams()
	local gravity = Vector3.new(0, -workspace.Gravity, 0)
	local t = os.clock()
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local i = 1
	while i <= #chunks do
		local c = chunks[i]
		local age = t - c.born
		if age > C.DEBRIS_LIFETIME + C.DEBRIS_FADE then
			c.part:Destroy()
			table.remove(chunks, i)
			continue
		end
		if not c.resting then
			c.vel += gravity * dt
			local move = c.vel * dt
			local reach = if move.Magnitude > 1e-4 then move + move.Unit * (c.size.Magnitude * 0.25) else Vector3.new(0, -0.1, 0)
			local hit = workspace:Raycast(c.pos, reach, params)
			if hit then
				local n = hit.Normal
				local into = c.vel:Dot(n)
				c.vel = (c.vel - n * into * (1 + C.DEBRIS_BOUNCE)) * C.DEBRIS_FRICTION
				c.pos = hit.Position + n * (c.size.Magnitude * 0.25)
				c.spin *= C.DEBRIS_FRICTION
				if n.Y > FLOOR_NORMAL and c.vel.Magnitude < REST_SPEED then
					c.resting = true
				end
			else
				c.pos += move
			end
			c.rot = c.rot * CFrame.Angles(c.spin.X * dt, c.spin.Y * dt, c.spin.Z * dt)
		end
		if age > C.DEBRIS_LIFETIME then
			local k = 1 - (age - C.DEBRIS_LIFETIME) / C.DEBRIS_FADE
			c.part.Size = c.size * math.max(0.05, k)
		end
		table.insert(parts, c.part)
		table.insert(cframes, CFrame.new(c.pos) * c.rot)
		i += 1
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function DebrisFx.start()
	local remotes = ReplicatedStorage:WaitForChild("DestructionRemotes", 60)
	if not remotes then
		return
	end
	local remote = remotes:WaitForChild("Debris") :: RemoteEvent
	remote.OnClientEvent:Connect(DebrisFx.play)
	RunService.Heartbeat:Connect(step)
end

return DebrisFx
