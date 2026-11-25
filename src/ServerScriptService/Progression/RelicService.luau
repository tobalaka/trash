--!strict
--[[
	RelicService - Relic moves on keys Z X C R B (vault: Relic-Abilities). CombatService is not
	touched (Map-Art-Direction rule 8): moves read and write the shared Fighter records and land
	through MobStrike.resolve, so i-frames dodge them, timed blocks parry them, blocks cut them,
	and players see the same hit reactions as in PvP.

	A request (AbilityRequest key, direction, stamp) is checked: the move exists on your Relic
	and its Blacksmith tier is unlocked (Z 1, X 2, C 3; R and B from the start), the cooldown is
	over, you are not stunned, ragdolled, held or knocked, and an ultimate needs a full Anima
	meter. Then the move runs on the server from its definition in Shared/Data/Relics, while
	every client draws it from RelicFx. Dashes, leaps and hops move the caster on their own
	client (they own their character); the server samples where they actually are.

	Who can be hit: rival-faction and unaligned players (never your own faction, never inside a
	faction base), Smoglings, Pollution Beasts and training dummies.

	Moves that land on the map break it (TRASH-Destruction): bursts and leaps blast where they
	hit, dashes and wave fronts smash the wall they run into, thrown Relics chip the wall they
	strike, storms chew through what they roll over.

	Numbers scale with your upgrade tier (Config.Economy.TIER_DAMAGE_BONUS) and perks (damage,
	posture, cooldown, reach, ultimate cost, Jack-in-the-Box; Fleetfoot: dash range, dodge time,
	Momentum, Tailwind, Slipstream). Being Well Fed (Survival) adds a little damage and Anima.
	Anima fills from damage dealt and taken (Ledger) and fades out of combat.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local JC = require(Config:WaitForChild("Relic"))
local Economy = require(Config:WaitForChild("Economy"))
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Combat = ServerScriptService:WaitForChild("Combat")
local Fighters = require(Combat:WaitForChild("Fighters"))
local MobStrike = require(ServerScriptService:WaitForChild("Mobs"):WaitForChild("MobStrike"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local FactionService = require(script.Parent:WaitForChild("FactionService"))
local Salvage = require(script.Parent:WaitForChild("Salvage"))
local Ledger = require(script.Parent:WaitForChild("Ledger"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Survival = require(script.Parent:WaitForChild("Survival"))
local SurvivalConfig = require(Config:WaitForChild("Survival"))

type Fighter = Fighters.Fighter
type Ability = Relics.Ability

local TIER_FOR = { Z = 1, X = 2, C = 3, R = 0, B = 0 }
local MOB_TAGS = { "Smogling", "PollutionBeast", "TrainingDummy" }
local HEIGHT = 7 -- vertical reach of shapes, studs above/below the caster's root
local STRIKE_HEIGHT = 6
local PROJECTILE_HEIGHT = 0.5
local SECOND_WIND_BELOW = 0.3
local SECOND_WIND_RATE = 2
local SECOND_WIND_TIME = 6
local SECOND_WIND_COOLDOWN = 60
local RALLY_RADIUS = 12
local JACK_STUN = 0.4
local JACK_POSTURE = 15
local TIDY_REFUND = 3 -- cooldown left when Tidy Up finds nothing
local SUPPRESS_DRAIN = 5 -- posture per second during Hostile Takeover's hold
local DASH_SMASH_GAP = 0.12 -- seconds between wall smashes during one dash
local SLIPSTREAM_TIME = 2 -- seconds after a dash, leap or hop that Slipstream boosts hits
local MOMENTUM_GAP = 0.2 -- Momentum cuts cooldowns at most once per this many seconds

type State = {
	busyUntil: number,
	cooldowns: { [string]: number },
	anima: number,
	lastCombat: number,
	guardUntil: number,
	guardReduction: number,
	secondWindReady: number,
	healthConn: RBXScriptConnection?,
	lastHealth: number,
}

local RelicService = {}

-- the breakable map (TRASH-Destruction); optional, so moves still work without it
local destruction: any = nil
local DC: any = nil
task.spawn(function()
	local folder = ServerScriptService:WaitForChild("Destruction", 10)
	local module = folder and folder:WaitForChild("DestructionService", 10)
	local config = Config:WaitForChild("Destruction", 10)
	if module and module:IsA("ModuleScript") and config and config:IsA("ModuleScript") then
		DC = require(config)
		destruction = require(module)
	end
end)

local states: { [Player]: State } = {}
local slipUntil: { [Player]: number } = {} -- Slipstream window after a dash, leap or hop
local momentumAt: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = {
			busyUntil = 0,
			cooldowns = {},
			anima = 0,
			lastCombat = 0,
			guardUntil = 0,
			guardReduction = 0,
			secondWindReady = 0,
			healthConn = nil,
			lastHealth = 0,
		}
		states[player] = s
	end
	return s
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, -1)
end

-- ── Anima ──

local function setAnima(player: Player, value: number)
	local s = stateOf(player)
	s.anima = math.clamp(value, 0, JC.ANIMA_MAX)
	player:SetAttribute("Anima", math.floor(s.anima + 0.5))
end

function RelicService.addAnima(player: Player, amount: number)
	local s = stateOf(player)
	s.lastCombat = os.clock()
	setAnima(player, s.anima + amount)
end

-- ── targets ──

type Ctx = {
	player: Player,
	character: Model,
	fighter: Fighter,
	root: BasePart,
	ability: Ability,
	relic: string,
	key: string,
	dir: Vector3,
	start: number,
	damage: number, -- multiplier
	posture: number, -- multiplier
	reach: number, -- multiplier
	jack: number,
	allies: boolean,
}

local function candidates(ctx: Ctx): { Fighter }
	local list: { Fighter } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other ~= ctx.player and character and FactionService.canHurt(ctx.player, other) then
			local f = Fighters.get(character)
			if f and f.humanoid.Health > 0 then
				table.insert(list, f)
			end
		end
	end
	for _, tag in MOB_TAGS do
		for _, model in CollectionService:GetTagged(tag) do
			if model:IsA("Model") and model.Parent then
				local f = Fighters.get(model)
				if f and f.humanoid.Health > 0 then
					table.insert(list, f)
				end
			end
		end
	end
	return list
end

local function allies(ctx: Ctx, center: Vector3, radius: number): { Player }
	local out = { ctx.player }
	local mine = FactionService.factionOf(ctx.player)
	if not mine then
		return out
	end
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if other ~= ctx.player and root and root:IsA("BasePart") and FactionService.factionOf(other) == mine then
			if (root.Position - center).Magnitude <= radius then
				table.insert(out, other)
			end
		end
	end
	return out
end

local function heal(player: Player, amount: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
	end
end

-- ── landing a hit ──

type Blow = { damage: number?, posture: number?, knockback: number?, up: number?, stun: number?, ragdoll: number? }

-- damage multipliers that depend on the moment of the hit, not the cast
local function liveBonus(player: Player): number
	local bonus = 1
	if Survival.wellFed(player) then
		bonus += SurvivalConfig.WELL_FED_DAMAGE
	end
	if (slipUntil[player] or 0) > now() then
		bonus += Progress.effects(player).slipstream or 0
	end
	return bonus
end

-- Momentum: a landed hit takes time off your other Relic cooldowns
local function momentum(ctx: Ctx)
	local cut = Progress.effects(ctx.player).momentum
	if not cut or os.clock() - (momentumAt[ctx.player] or 0) < MOMENTUM_GAP then
		return
	end
	momentumAt[ctx.player] = os.clock()
	local s = stateOf(ctx.player)
	local t = now()
	for key, ends in s.cooldowns do
		if key ~= ctx.key and ends > t then
			s.cooldowns[key] = math.max(t, ends - cut)
			ctx.player:SetAttribute("CooldownEnd_" .. key, s.cooldowns[key])
		end
	end
end

local function hit(ctx: Ctx, target: Fighter, blow: Blow, from: Vector3?): string
	local a = ctx.ability
	local strike = {
		damage = (blow.damage or 0) * ctx.damage * liveBonus(ctx.player),
		posture = (blow.posture or 0) * ctx.posture,
		parryable = a.parryable ~= false,
		blockable = a.blockable ~= false,
		stun = blow.stun or 0,
		knockback = blow.knockback or 0,
		up = blow.up or 0,
		ragdoll = blow.ragdoll or 0,
	}
	Ledger.expect(target.model, ctx.player)
	local outcome = MobStrike.resolve(ctx.fighter, target, strike, now(), from or ctx.root.Position)
	if outcome == "Hit" then
		momentum(ctx)
		if a.suppress then
			target.postureHitAt = math.max(target.postureHitAt, now() + a.suppress)
		end
		-- Jack-in-the-Box: the server rolls a random extra
		if ctx.jack > 0 and math.random() < ctx.jack then
			if math.random() < 0.5 then
				target.stunEnd = math.max(target.stunEnd, now() + JACK_STUN)
			else
				target.posture = math.max(0, target.posture - JACK_POSTURE)
				target.postureHitAt = now()
			end
		end
	end
	return outcome
end

-- a point behind the target, so MobStrike's "push away from `from`" pulls it toward `toward`
local function pullFrom(target: Fighter, toward: Vector3): Vector3
	return target.root.Position + flat(target.root.Position - toward)
end

local function blowOf(a: Ability): Blow
	return { damage = a.damage, posture = a.posture, knockback = a.knockback, up = a.up, stun = a.stun, ragdoll = a.ragdoll }
end

local function inRadius(ctx: Ctx, center: Vector3, radius: number): { Fighter }
	local out = {}
	for _, f in candidates(ctx) do
		local o = f.root.Position - center
		if Vector2.new(o.X, o.Z).Magnitude <= radius + 1.5 and math.abs(o.Y) <= HEIGHT then
			table.insert(out, f)
		end
	end
	return out
end

local function fx(ctx: Ctx, phase: string, data: { [string]: any }?)
	local payload: { [string]: any } = data or {}
	payload.phase = phase
	Remotes.get("RelicFx"):FireAllClients(ctx.character, ctx.relic, ctx.key, payload)
end

-- breaks the map around `center` (radius already scaled), credited to the caster
local function smash(ctx: Ctx, center: Vector3, radius: number, dir: Vector3?)
	if destruction and radius > 0 then
		destruction.blast(center, math.min(DC.BLAST_MAX, radius), ctx.player, 1, dir)
	end
end

-- a breakable wall straight ahead of `from` within `length`, or nil
local function wallAhead(from: Vector3, dir: Vector3, length: number): Vector3?
	if not destruction then
		return nil
	end
	local hit = destruction.probe(from, dir * length)
	return if hit then hit.Position else nil
end

local function alive(ctx: Ctx): boolean
	return ctx.character.Parent ~= nil and ctx.fighter.humanoid.Health > 0
end

-- ── kinds ──

local runners: { [string]: (Ctx) -> () } = {}

runners.Strike = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	local hits = a.hits or 1
	for i = 1, hits do
		if not alive(ctx) or ctx.fighter.stunEnd > now() then
			return
		end
		local range = (a.range or 6) * ctx.reach
		local cf = CFrame.lookAt(ctx.root.Position, ctx.root.Position + ctx.dir) * CFrame.new(0, 0, -range / 2)
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { ctx.character }
		local valid: { [Model]: Fighter } = {}
		for _, c in candidates(ctx) do
			valid[c.model] = c
		end
		local seen: { [Model]: boolean } = {}
		local targets = {}
		for _, part in workspace:GetPartBoundsInBox(cf, Vector3.new(a.width or 5, STRIKE_HEIGHT, range), params) do
			local f = Fighters.fromPart(part)
			if f and not seen[f.model] and valid[f.model] then
				seen[f.model] = true
				table.insert(targets, valid[f.model])
			end
		end
		local last = i == hits
		for _, t in targets do
			hit(ctx, t, {
				damage = a.damage,
				posture = a.posture,
				knockback = if last or hits == 1 then a.knockback else 4,
				up = if last then a.up else 0,
				stun = a.stun,
			})
		end
		fx(ctx, "Hit", { index = i, at = cf.Position })
		if not last then
			task.wait(a.interval or 0.15)
		end
	end
end

runners.Cone = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	if not alive(ctx) or ctx.fighter.stunEnd > now() then
		return
	end
	local center = ctx.root.Position
	local radius = (a.radius or 10) * ctx.reach
	local cosHalf = math.cos(math.rad((a.angle or 90) / 2))
	local caught: { Fighter } = {}
	for _, t in inRadius(ctx, center, radius) do
		local to = flat(t.root.Position - center)
		if to:Dot(ctx.dir) >= cosHalf or (t.root.Position - center).Magnitude < 3 then
			local from = if a.pull then pullFrom(t, center) else center
			local blow = blowOf(a)
			if a.pull then
				blow.knockback = a.pull
			end
			if hit(ctx, t, blow, from) == "Hit" then
				table.insert(caught, t)
			end
		end
	end
	fx(ctx, "Hit", { at = center })
	local follow = a.follow
	if follow then
		task.wait(follow.delay)
		if not alive(ctx) then
			return
		end
		local at = ctx.root.Position
		for _, t in inRadius(ctx, at, follow.radius * ctx.reach) do
			hit(ctx, t, { damage = follow.damage, posture = follow.posture, up = follow.up, knockback = follow.knockback or 6, stun = 0.6 }, at)
		end
		fx(ctx, "Follow", { at = at })
	end
end

local function guard(ctx: Ctx, duration: number, reduction: number, armor: number?)
	local s = stateOf(ctx.player)
	s.guardUntil = now() + duration
	s.guardReduction = reduction
	if armor then
		ctx.fighter.armorUntil = math.max(ctx.fighter.armorUntil, now() + armor)
	end
end

runners.Burst = function(ctx)
	local a = ctx.ability
	if a.reduction then
		guard(ctx, a.windup, a.reduction, nil)
	end
	task.wait(a.windup)
	local origin = ctx.root.Position
	local dir = ctx.dir
	local offsets = a.offsets or { 0 }
	local pulses = a.pulses or 1
	local steps = math.max(#offsets, pulses)
	for i = 1, steps do
		if not alive(ctx) then
			return
		end
		local offset = offsets[math.min(i, #offsets)]
		local center = (if #offsets > 1 then origin else ctx.root.Position) + dir * offset * ctx.reach
		local radius = ((a.radius or 10) + (a.grow or 0) * (i - 1)) * ctx.reach
		local last = i == steps
		for _, t in inRadius(ctx, center, radius) do
			hit(ctx, t, {
				damage = a.damage,
				posture = a.posture,
				knockback = a.knockback or 10,
				up = if last or steps == 1 then a.up else 8,
				stun = a.stun,
			}, center)
		end
		fx(ctx, "Pulse", { index = i, at = center, radius = radius })
		if DC then
			smash(ctx, center, radius * DC.BLAST_SCALE, nil)
		end
		if not last then
			task.wait(a.interval or 0.4)
		end
	end
end

runners.Dash = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	if not alive(ctx) then
		return
	end
	local duration = a.duration or 0.3
	local ends = now() + duration + 0.1
	if a.armor then
		ctx.fighter.armorUntil = math.max(ctx.fighter.armorUntil, now() + math.max(a.armor, duration))
	end
	local hits = a.hits or 1
	local counts: { [Model]: number } = {}
	local lastHit: { [Model]: number } = {}
	local spacing = duration / hits
	local radius = (a.radius or 4.5) * ctx.reach
	local speed = (a.distance or 15) * (1 + (Progress.effects(ctx.player).dashRange or 0)) / duration
	local moveEnds = now() + duration
	local smashedAt = 0
	while now() < ends and alive(ctx) do
		if ctx.fighter.stunEnd > now() then
			return
		end
		-- one wall smash per DASH_SMASH_GAP, so a dash doesn't spend the server's blast budget.
		-- The server sees the caster late, so it looks LOOKAHEAD_TIME of travel further ahead,
		-- but never past where the dash ends.
		local reach = if DC then radius + 2 + speed * math.min(DC.LOOKAHEAD_TIME, math.max(0, moveEnds - now())) else 0
		local wall = if DC and now() - smashedAt >= DASH_SMASH_GAP then wallAhead(ctx.root.Position, ctx.dir, reach) else nil
		if wall then
			smashedAt = now()
			smash(ctx, wall, DC.DASH_RADIUS, ctx.dir)
		end
		for _, t in inRadius(ctx, ctx.root.Position, radius) do
			local n = counts[t.model] or 0
			if n < hits and now() - (lastHit[t.model] or 0) >= spacing then
				counts[t.model] = n + 1
				lastHit[t.model] = now()
				hit(ctx, t, blowOf(a))
			end
		end
		RunService.Heartbeat:Wait()
	end
	slipUntil[ctx.player] = now() + SLIPSTREAM_TIME
end

-- world geometry only: characters and mobs don't stop a throw (hits are found by distance)
local function worldParams(ctx: Ctx): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { ctx.character }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	for _, tag in MOB_TAGS do
		for _, m in CollectionService:GetTagged(tag) do
			table.insert(exclude, m)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

local function blocked(from: Vector3, to: Vector3, params: RaycastParams): Vector3?
	local hitResult = workspace:Raycast(from, to - from, params)
	return if hitResult then hitResult.Position else nil
end

local function flyProjectile(ctx: Ctx, dir: Vector3, index: number)
	local a = ctx.ability
	local speed = a.speed or 80
	local range = (a.range or 40) * ctx.reach
	local radius = a.radius or 2.5
	local pos = ctx.root.Position + Vector3.new(0, PROJECTILE_HEIGHT, 0) + dir * 2
	local travelled = 0
	local returning = false
	local bouncesLeft = a.bounces or 0
	local struck: { [Model]: boolean } = {}
	local heading = dir
	local target: Fighter? = nil
	local params = worldParams(ctx)
	while alive(ctx) do
		local dt = RunService.Heartbeat:Wait()
		local step = speed * dt
		local goal: Vector3
		if returning then
			local back = ctx.root.Position + Vector3.new(0, PROJECTILE_HEIGHT, 0) - pos
			if back.Magnitude <= step + 1 then
				return
			end
			heading = back.Unit
		elseif target then
			local to = target.root.Position - pos
			heading = if to.Magnitude > 0 then to.Unit else heading
		end
		goal = pos + heading * step
		if not returning then
			local wall = blocked(pos, goal, params)
			if wall then
				if DC then
					smash(ctx, wall, DC.PROJECTILE_RADIUS, heading)
				end
				if a.returns then
					returning = true
					struck = {}
					goal = wall
				else
					fx(ctx, "Stop", { index = index, at = wall })
					return
				end
			end
		end
		pos = goal
		travelled += step
		for _, t in inRadius(ctx, pos, radius) do
			if not struck[t.model] and math.abs(t.root.Position.Y - pos.Y) <= 5 then
				struck[t.model] = true
				hit(ctx, t, blowOf(a), pos - heading * 2)
				if bouncesLeft > 0 then
					bouncesLeft -= 1
					local nextT, best = nil, (a.bounceRange or 15)
					for _, c in candidates(ctx) do
						if not struck[c.model] then
							local d = (c.root.Position - pos).Magnitude
							if d < best then
								nextT, best = c, d
							end
						end
					end
					if nextT then
						target = nextT
						fx(ctx, "Bounce", { index = index, from = pos, to = nextT.model })
					else
						fx(ctx, "Stop", { index = index, at = pos })
						return
					end
				elseif not a.pierce and not a.returns then
					fx(ctx, "Stop", { index = index, at = pos })
					return
				end
			end
		end
		if not returning and travelled >= range then
			if a.returns then
				returning = true
				struck = {}
			else
				fx(ctx, "Stop", { index = index, at = pos })
				return
			end
		end
		if travelled > range * 3 then
			return
		end
	end
end

runners.Projectile = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	if not alive(ctx) or ctx.fighter.stunEnd > now() then
		return
	end
	local count = a.count or 1
	local spread = math.rad(a.spread or 0)
	for i = 1, count do
		local angle = if count > 1 then -spread / 2 + spread * (i - 1) / (count - 1) else 0
		local dir = (CFrame.Angles(0, angle, 0) * CFrame.lookAt(Vector3.zero, ctx.dir)).LookVector
		task.spawn(flyProjectile, ctx, flat(dir), i)
	end
end

runners.Wave = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	if not alive(ctx) then
		return
	end
	local origin = ctx.root.Position
	local range = (a.range or 20) * ctx.reach
	local halfWidth = (a.width or 6) / 2
	local speed = a.speed or 60
	local struck: { [Model]: boolean } = {}
	local front = 0
	while front < range do
		local dt = RunService.Heartbeat:Wait()
		local before = front
		front = math.min(range, front + speed * dt)
		local wall = if DC then wallAhead(origin + ctx.dir * before + Vector3.new(0, 1, 0), ctx.dir, front - before + 1) else nil
		if wall then
			smash(ctx, wall, halfWidth + 1, ctx.dir)
		end
		for _, t in candidates(ctx) do
			if not struck[t.model] then
				local o = t.root.Position - origin
				local along = o:Dot(ctx.dir)
				local side = (o - ctx.dir * along)
				if along >= 0 and along <= front and Vector2.new(side.X, side.Z).Magnitude <= halfWidth + 1 and math.abs(o.Y) <= HEIGHT then
					struck[t.model] = true
					hit(ctx, t, blowOf(a), origin + ctx.dir * (along - 2))
				end
			end
		end
	end
end

runners.Leap = function(ctx)
	local a = ctx.ability
	task.wait(a.windup + (a.duration or 0.5))
	if not alive(ctx) then
		return
	end
	local center = ctx.root.Position
	local radius = (a.radius or 12) * ctx.reach
	for _, t in inRadius(ctx, center, radius) do
		hit(ctx, t, blowOf(a), center)
	end
	fx(ctx, "Land", { at = center, radius = radius })
	slipUntil[ctx.player] = now() + SLIPSTREAM_TIME
	if DC then
		smash(ctx, center, radius * DC.BLAST_SCALE, nil)
	end
	if a.suppress then
		local ends = now() + a.suppress
		while now() < ends and alive(ctx) do
			for _, t in inRadius(ctx, ctx.root.Position, radius) do
				t.posture = math.max(0, t.posture - SUPPRESS_DRAIN * 0.5 * ctx.posture)
				t.postureHitAt = now()
			end
			task.wait(0.5)
		end
	end
end

runners.Counter = function(ctx)
	local a = ctx.ability
	local f = ctx.fighter
	local window = (a.window or 0.8) + (Progress.effects(ctx.player).iframes or 0)
	local start = now()
	f.iframeStart = start
	f.iframeEnd = start + window
	local radius = (a.radius or 9) * ctx.reach
	while now() < start + window and alive(ctx) do
		for _, t in inRadius(ctx, ctx.root.Position, radius) do
			-- someone mid-swing at us: blow them back
			if t.actionEnd > now() or (t.pendingHitAt > 0 and t.pendingHitAt >= start) then
				f.iframeEnd = now() + 0.25
				local center = ctx.root.Position
				for _, v in inRadius(ctx, center, radius) do
					hit(ctx, v, blowOf(a), center)
				end
				fx(ctx, "Counter", { at = center })
				return
			end
		end
		RunService.Heartbeat:Wait()
	end
end

runners.Guard = function(ctx)
	local a = ctx.ability
	local duration = a.duration or 4
	guard(ctx, duration, a.reduction or 0.3, a.armor)
	if a.allyHeal and a.radius then
		local ends = now() + duration
		local per = a.allyHeal / duration
		while now() < ends and alive(ctx) do
			for _, ally in allies(ctx, ctx.root.Position, a.radius) do
				if ally ~= ctx.player then
					heal(ally, per)
				end
			end
			task.wait(1)
		end
	end
end

runners.Heal = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	local duration = a.duration or 5
	local ticks = math.max(1, math.floor(duration / 0.5))
	local per = (a.heal or 20) / ticks
	for _ = 1, ticks do
		if not alive(ctx) then
			return
		end
		for _, ally in allies(ctx, ctx.root.Position, (a.radius or 10) * ctx.reach) do
			heal(ally, per)
		end
		task.wait(0.5)
	end
end

runners.Aura = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	local ends = now() + (a.duration or 5)
	while now() < ends and alive(ctx) do
		local center = ctx.root.Position
		local radius = (a.radius or 14) * ctx.reach
		for _, t in inRadius(ctx, center, radius) do
			hit(ctx, t, { damage = a.damage, posture = a.posture, knockback = 0, stun = 0.15 }, center)
		end
		if a.allyHeal then
			for _, ally in allies(ctx, center, radius) do
				heal(ally, a.allyHeal)
			end
		end
		task.wait(a.interval or 0.5)
	end
end

runners.Storm = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	local center = ctx.root.Position + ctx.dir * 3
	local dir = ctx.dir
	local ends = now() + (a.duration or 3)
	local speed = a.speed or 12
	local radius = (a.radius or 8) * ctx.reach
	local caught: { [Model]: Fighter } = {}
	local last = now()
	while now() < ends and alive(ctx) do
		local t0 = now()
		center += dir * speed * (t0 - last)
		last = t0
		if DC then
			smash(ctx, center, radius * DC.BLAST_SCALE, dir)
		end
		for _, t in inRadius(ctx, center, radius) do
			caught[t.model] = t
			hit(ctx, t, { damage = a.damage, posture = a.posture, knockback = a.pull or 10, stun = 0.35 }, pullFrom(t, center))
		end
		task.wait(a.interval or 0.3)
	end
	for _, t in caught do
		if t.model.Parent and t.humanoid.Health > 0 then
			hit(ctx, t, { damage = a.damage, posture = a.posture, up = a.up, knockback = 20, stun = 0.8 }, center)
		end
	end
	fx(ctx, "End", { at = center })
end

runners.Tidy = function(ctx)
	local a = ctx.ability
	task.wait(a.windup)
	if not alive(ctx) then
		return
	end
	local pile = Salvage.nearest(ctx.root.Position, (a.radius or 12) * ctx.reach)
	if pile and Salvage.process(ctx.player, pile) then
		fx(ctx, "Tidy", { at = pile.model:GetPivot().Position })
	else
		local s = stateOf(ctx.player)
		s.cooldowns[ctx.key] = now() + TIDY_REFUND
		ctx.player:SetAttribute("CooldownEnd_" .. ctx.key, s.cooldowns[ctx.key])
		Sync.notify(ctx.player, "Toast", { text = "No junk pile close enough to tidy.", color = "Red" })
	end
end

runners.Hop = function(ctx)
	local a = ctx.ability
	local f = ctx.fighter
	f.iframeStart = now()
	f.iframeEnd = now() + (a.iframes or 0.3) + (Progress.effects(ctx.player).iframes or 0)
	slipUntil[ctx.player] = now() + (a.duration or 0.25) + SLIPSTREAM_TIME
end

-- ── requests ──

local function request(player: Player, key: string, direction: any, stamp: any)
	if not Guard.allow(player, "Ability", JC.RATE) then
		return
	end
	if TIER_FOR[key] == nil then
		return
	end
	local p = Profiles.get(player)
	local character = player.Character
	if not p or not p.relic or not character then
		return
	end
	local relic = Relics.get(p.relic.id)
	local a = relic and relic.abilities[key]
	if not relic or not a then
		return
	end
	if p.relic.tier < TIER_FOR[key] then
		return
	end
	local f = Fighters.get(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not f or not root or not root:IsA("BasePart") or f.humanoid.Health <= 0 then
		return
	end
	local t = now()
	if f.stunEnd > t or f.ragdollEnd > t or f.heldBy or f.actionEnd > t or f.blocking or player:GetAttribute("Knocked")
		or f.knocked or f.carrying or f.gripping or f.carriedBy then
		return
	end
	local s = stateOf(player)
	local tolerance = 0.15
	if (s.cooldowns[key] or 0) > t + tolerance or s.busyUntil > t + tolerance then
		return
	end
	local fx0 = Progress.effects(player)
	if a.ultimate then
		local need = JC.ANIMA_MAX * (1 - (fx0.ultCost or 0))
		if s.anima + 0.5 < need then
			return
		end
		setAnima(player, s.anima - need)
	end
	local dir = if typeof(direction) == "Vector3" and direction == direction then flat(direction) else flat(root.CFrame.LookVector)
	local cooldown = a.cooldown * (1 - (fx0.cooldown or 0))
	s.cooldowns[key] = t + cooldown
	s.busyUntil = t + a.windup + a.lock
	character:SetAttribute("RelicBusyUntil", s.busyUntil)
	player:SetAttribute("CooldownEnd_" .. key, s.cooldowns[key])
	if fx0.abilityArmor then
		f.armorUntil = math.max(f.armorUntil, t + fx0.abilityArmor)
	end
	local melee = JC.MELEE_KINDS[a.kind] == true
	local ctx: Ctx = {
		player = player,
		character = character,
		fighter = f,
		root = root,
		ability = a,
		relic = relic.id,
		key = key,
		dir = dir,
		start = t,
		damage = 1 + Economy.TIER_DAMAGE_BONUS * p.relic.tier + (fx0.abilityDamage or 0) + (if melee then fx0.meleeDamage or 0 else 0),
		posture = 1 + (fx0.postureDamage or 0),
		reach = 1 + (fx0.reach or 0),
		jack = fx0.jack or 0,
		allies = false,
	}
	fx(ctx, "Start", { dir = dir, origin = root.Position, start = t })
	if key == "R" and fx0.rally then
		for _, ally in allies(ctx, root.Position, RALLY_RADIUS) do
			if ally ~= player then
				heal(ally, fx0.rally)
			end
		end
	end
	local run = runners[a.kind]
	if run then
		task.spawn(function()
			local ok, err = pcall(run, ctx)
			if not ok then
				warn("[RelicService] " .. relic.id .. " " .. key .. ": " .. tostring(err))
			end
		end)
	end
end

-- ── character hooks: guard reduction and Second Wind ──

local function hookCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	local s = stateOf(player)
	if s.healthConn then
		s.healthConn:Disconnect()
	end
	s.lastHealth = humanoid.Health
	s.guardUntil = 0
	s.healthConn = humanoid.HealthChanged:Connect(function(health)
		local lost = s.lastHealth - health
		s.lastHealth = health
		if lost <= 0 or health <= 0 then
			return
		end
		-- Guard: give back a share of what was just lost
		if s.guardUntil > now() and s.guardReduction > 0 then
			local back = lost * s.guardReduction
			s.lastHealth = math.min(humanoid.MaxHealth, health + back)
			humanoid.Health = s.lastHealth
		end
		-- Second Wind
		local fx0 = Progress.effects(player)
		if fx0.secondWind and humanoid.Health / humanoid.MaxHealth < SECOND_WIND_BELOW and os.clock() >= s.secondWindReady then
			s.secondWindReady = os.clock() + SECOND_WIND_COOLDOWN
			task.spawn(function()
				local ends = os.clock() + SECOND_WIND_TIME
				while os.clock() < ends and humanoid.Parent and humanoid.Health > 0 do
					humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + SECOND_WIND_RATE * 0.5)
					task.wait(0.5)
				end
			end)
			Sync.notify(player, "Toast", { text = "Second Wind!", color = "Lime" })
		end
	end)
	for key in TIER_FOR do
		player:SetAttribute("CooldownEnd_" .. key, s.cooldowns[key] or 0)
	end
end

function RelicService.start()
	Remotes.get("AbilityRequest").OnServerEvent:Connect(function(player, key, direction, stamp)
		if typeof(key) == "string" then
			request(player, key, direction, stamp)
		end
	end)
	Ledger.onDamage(function(attacker, victim, amount)
		local fxA = if attacker then Progress.effects(attacker) else nil
		if attacker and attacker.Character ~= victim then
			local fed = if Survival.wellFed(attacker) then SurvivalConfig.WELL_FED_ANIMA else 0
			RelicService.addAnima(attacker, amount * JC.ANIMA_PER_DAMAGE * (1 + (if fxA then fxA.anima or 0 else 0) + fed))
		end
		local victimPlayer = Players:GetPlayerFromCharacter(victim)
		if victimPlayer then
			RelicService.addAnima(victimPlayer, amount * JC.ANIMA_PER_DAMAGE_TAKEN)
		end
	end)
	local function watch(player: Player)
		player:SetAttribute("AnimaMax", JC.ANIMA_MAX)
		setAnima(player, 0)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local s = states[player]
		if s and s.healthConn then
			s.healthConn:Disconnect()
		end
		states[player] = nil
		slipUntil[player] = nil
		momentumAt[player] = nil
	end)
	-- Anima fades out of combat
	task.spawn(function()
		while true do
			task.wait(0.5)
			local t = os.clock()
			for player, s in states do
				if s.anima > 0 and t - s.lastCombat > JC.ANIMA_DECAY_DELAY then
					local keep = Progress.effects(player).animaKeep or 0
					setAnima(player, s.anima - JC.ANIMA_DECAY * 0.5 * (1 - keep))
				end
			end
		end
	end)
end

return RelicService
