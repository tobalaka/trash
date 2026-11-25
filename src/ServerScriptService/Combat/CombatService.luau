--!strict
-- Server-authoritative combat; clients predict animations (ADR-001, ADR-002).
-- Resolve hits after windup and latency forgiveness; clamp client timestamps.
-- Publish combat state, posture and cooldowns. Play NPC reactions on the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local MoveConfig = require(Shared:WaitForChild("Config"):WaitForChild("Movement"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Anims = require(Shared:WaitForChild("Anims"))
local Fighters = require(script.Parent:WaitForChild("Fighters"))
local Hitbox = require(script.Parent:WaitForChild("Hitbox"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))
local Ragdoll = require(script.Parent:WaitForChild("Ragdoll"))
local Knock = require(script.Parent:WaitForChild("Knock"))

type Fighter = Fighters.Fighter
type HitKind = "M1" | "Heavy" | "Uppercut" | "Aerial" | "Crit"

local DODGES = { Forward = true, Backward = true, Left = true, Right = true, Air = true }
local THROWS = { Up = true, Down = true, Left = true, Right = true }
local DAMAGE: { [HitKind]: number } = {
	M1 = Config.M1_BASE_DAMAGE,
	Heavy = Config.HEAVY_DAMAGE,
	Uppercut = Config.UPPERCUT_DAMAGE,
	Aerial = Config.AERIAL_DAMAGE,
	Crit = Config.CRIT_DAMAGE,
}
local TOLERANCE = Config.LATENCY_FORGIVENESS -- network jitter allowed on cooldown and chain timing
local HEAVY_REACTION = 5 -- reaction index for launches, slams and finishers

local CombatService = {}

local result: RemoteEvent

local function now(): number
	return workspace:GetServerTimeNow()
end

local function clampStamp(stamp: any, received: number): number
	if typeof(stamp) ~= "number" or stamp ~= stamp then
		return received
	end
	return math.clamp(stamp, received - Config.MAX_TIMESTAMP_SKEW, received)
end

local function fighterOf(player: Player): Fighter?
	local character = player.Character
	return if character then Fighters.get(character) else nil
end

local function setCooldown(f: Fighter, key: string, ends: number)
	if f.player then
		f.player:SetAttribute("CooldownEnd_" .. key, ends)
	end
end

-- reaction animations for NPC dummies (players play their own)
local function npcReact(t: Fighter, kind: string, detail: any)
	if t.player then
		return
	end
	local animator = t.humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	task.spawn(function()
		local set = Anims.forAnimator(animator)
		local index = if typeof(detail) == "number" then math.clamp(detail, 1, 5) else 1
		if kind == "Hit" then
			set:play("HitReact" .. index, 0.05)
		elseif kind == "Blocked" then
			set:play("BlockHit" .. ((index - 1) % 3 + 1), 0.05)
		elseif kind == "Break" then
			set:play("GuardBroken", 0.1)
			task.delay(Config.POSTURE_BREAK_STUN, function()
				set:stop("GuardBroken", 0.2)
			end)
		elseif kind == "GrabConnect" then
			set:play("Grabbed", 0.1)
		elseif kind == "Throw" or kind == "GrabRelease" then
			set:stop("Grabbed", 0.1)
		elseif kind == "Carry" then
			set:play("Carried", 0.2)
		elseif kind == "Drop" or kind == "GetUp" then
			set:stop("Carried", 0.2)
		end
	end)
end

local function fire(kind: string, attacker: Fighter?, target: Fighter?, detail: any)
	result:FireAllClients(kind, if attacker then attacker.model else nil, if target then target.model else nil, detail)
	if target then
		npcReact(target, kind, detail)
	end
end

local function reject(player: Player)
	result:FireClient(player, "Reject", player.Character, nil, nil)
end

local function stun(f: Fighter, duration: number)
	f.stunEnd = math.max(f.stunEnd, now() + duration)
	f.blocking = false
	f.parryArmed = false
	f.actionEnd = 0
	f.pendingHitAt = 0
	f.armorUntil = 0
	f.combo = 0
	f.chainUntil = 0
	f.attackSerial += 1 -- drops a pending hit or grab
	Knock.interrupt(f) -- and lets go of a grip or a carried body
end

local function breakPosture(f: Fighter, duration: number)
	f.posture = 0
	f.postureHitAt = now()
	f.broken = true
	stun(f, duration)
end

-- Returns true when this damage broke the posture.
local function hurtPosture(f: Fighter, amount: number): boolean
	f.posture = math.max(0, f.posture - amount)
	f.postureHitAt = now()
	if f.posture <= 0 then
		breakPosture(f, Config.POSTURE_BREAK_STUN)
		return true
	end
	return false
end

local function knock(f: Fighter, velocity: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Name = "Knockback"
	attachment.Parent = f.root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "Knockback"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.MaxForce = Config.KNOCKBACK_FORCE
	mover.VectorVelocity = velocity
	mover.Parent = f.root
	Debris:AddItem(mover, Config.KNOCKBACK_TIME)
	Debris:AddItem(attachment, Config.KNOCKBACK_TIME)
end

-- ── air combo: a launched body floats on a vertical-only mover ─────────────

local function clearJuggle(f: Fighter)
	f.juggleUntil = 0
	f.juggleSerial += 1
	for _, d in f.root:GetChildren() do
		if d.Name == "Juggle" or d.Name == "JuggleAtt" then
			d:Destroy()
		end
	end
end

-- Rises for `rise` seconds to `height` studs (rise 0: no rise), then holds still in the air for
-- `hold` seconds. Only the Y axis is held, so pushes and knockback still move the body sideways.
local function juggle(f: Fighter, rise: number, height: number, hold: number)
	f.juggleSerial += 1
	local serial = f.juggleSerial
	local att = f.root:FindFirstChild("JuggleAtt") :: Attachment?
	if not att then
		local a = Instance.new("Attachment")
		a.Name = "JuggleAtt"
		a.Parent = f.root
		att = a
	end
	local mover = f.root:FindFirstChild("Juggle") :: LinearVelocity?
	if not mover then
		local m = Instance.new("LinearVelocity")
		m.Name = "Juggle"
		m.Attachment0 = att
		m.RelativeTo = Enum.ActuatorRelativeTo.World
		m.ForceLimitMode = Enum.ForceLimitMode.PerAxis
		m.MaxAxesForce = Vector3.new(0, Config.KNOCKBACK_FORCE, 0)
		m.Parent = f.root
		mover = m
	end
	local m = mover :: LinearVelocity
	m.VectorVelocity = Vector3.new(0, if rise > 0 then height / rise else 0, 0)
	f.juggleUntil = now() + rise + hold
	if rise > 0 then
		task.delay(rise, function()
			if f.juggleSerial == serial and m.Parent then
				m.VectorVelocity = Vector3.zero
			end
		end)
	end
	task.delay(rise + hold, function()
		if f.juggleSerial == serial then
			clearJuggle(f)
		end
	end)
end

-- Anti-gank: remembers who hit `t`; GANK_ATTACKERS different attackers within GANK_WINDOW turn
-- the buff on (or keep it on). Returns whether `t` is ganked right now.
local function noteAttacker(t: Fighter, a: Fighter, at: number): boolean
	t.recentAttackers[a] = at
	local count = 0
	for who, when in t.recentAttackers do
		if at - when > Config.GANK_WINDOW or not who.model.Parent then
			t.recentAttackers[who] = nil
		else
			count += 1
		end
	end
	if count >= Config.GANK_ATTACKERS then
		t.gankUntil = at + Config.GANK_DURATION
	end
	return t.gankUntil > at
end

local function flatUnit(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
end

local function facing(defender: Fighter, attacker: Fighter): boolean
	local to = flatUnit(attacker.root.Position - defender.root.Position)
	if to == Vector3.zero then
		return true
	end
	return flatUnit(defender.root.CFrame.LookVector):Dot(to) >= math.cos(math.rad(Config.BLOCK_ANGLE / 2))
end

local function busy(f: Fighter, at: number): boolean
	return f.humanoid.Health <= 0 or (f.model:GetAttribute("RelicBusyUntil") or 0) > at
		or f.stunEnd > at or at < f.actionEnd - TOLERANCE or f.heldBy ~= nil or f.ragdollEnd > at
		or f.knocked or f.carriedBy ~= nil or f.carrying ~= nil or f.gripping ~= nil
end

-- Launcher cancel: the swing's recovery may be cut into an uppercut right after a landed hit.
local function cancelable(f: Fighter, at: number): boolean
	return f.humanoid.Health > 0 and (f.model:GetAttribute("RelicBusyUntil") or 0) <= at
		and f.landedCombo >= Config.CANCEL_MIN_HIT
		and at - f.landedAt <= Config.CANCEL_WINDOW + TOLERANCE
		and f.pendingHitAt == 0
		and f.stunEnd <= at
		and f.heldBy == nil
		and f.ragdollEnd <= at
		and not f.knocked and f.carriedBy == nil and f.carrying == nil and f.gripping == nil
end

-- TRASH-Destruction, when the place has it: walls it can break are broken, not splatted on
local breakable: ((BasePart) -> boolean)? = nil
local function isBreakable(part: BasePart): boolean
	if breakable == nil then
		local folder = ServerScriptService:FindFirstChild("Destruction")
		local module = folder and folder:FindFirstChild("DestructionService")
		local ok, service = pcall(function()
			return if module and module:IsA("ModuleScript") then (require(module) :: any) else nil
		end)
		if ok and service and service.isBreakable then
			breakable = service.isBreakable
		else
			breakable = function(_: BasePart)
				return false
			end
		end
	end
	return (breakable :: (BasePart) -> boolean)(part)
end

-- A body knocked along `dir` that meets a solid, unbreakable wall within WALL_SPLAT_RANGE
-- slams into it: a little damage, a longer stun, and a WallSplat result at the contact.
local function wallSplat(a: Fighter, t: Fighter, dir: Vector3, speed: number)
	if dir == Vector3.zero or speed <= 0 then
		return
	end
	local ignore: { Instance } = {}
	for model in Fighters.all() do
		table.insert(ignore, model)
	end
	local fx = workspace:FindFirstChild("RelicFxLocal")
	if fx then
		table.insert(ignore, fx)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(t.root.Position, dir * Config.WALL_SPLAT_RANGE, params)
	if not hit or not hit.Instance:IsA("BasePart") or math.abs(hit.Normal.Y) > 0.5 or isBreakable(hit.Instance) then
		return
	end
	local travel = math.max(0.05, (hit.Distance - 1.5) / speed)
	task.delay(travel, function()
		if not t.model.Parent or not hit.Instance.Parent or t.humanoid.Health <= 0 or t.heldBy
			or (t.root.Position - hit.Position).Magnitude > 4 then
			return
		end
		for _, mover in t.root:GetChildren() do
			if mover.Name == "Knockback" and (mover:IsA("LinearVelocity") or mover:IsA("Attachment")) then mover:Destroy() end
		end
		if a.player then
			t.lastPlayerHitAt = now()
		end
		t.humanoid:TakeDamage(Config.WALL_SPLAT_DAMAGE)
		stun(t, Config.WALL_SPLAT_STUN)
		fire("WallSplat", a, t, hit.Position)
	end)
end

-- ── hits ────────────────────────────────────────────────────────────────────

local function resolve(a: Fighter, t: Fighter, kind: HitKind, hitAt: number, reaction: number, finisher: boolean, hitStun: number?)
	if t.humanoid.Health <= 0 or t.heldBy or t.knocked or t.carriedBy then
		return -- a knocked body only takes a grip
	end
	if t.iframeStart <= hitAt and hitAt <= t.iframeEnd then
		if hitAt - t.iframeStart <= Config.PERFECT_DODGE_WINDOW + TOLERANCE then
			t.rollCooldownEnd = 0
			setCooldown(t, "Roll", 0)
			fire("PerfectDodge", a, t)
		else
			fire("Dodged", a, t)
		end
		return
	end
	local ganked = noteAttacker(t, a, hitAt)
	local taken = if ganked then Config.GANK_DAMAGE_TAKEN else 1
	if a.player then
		t.lastPlayerHitAt = hitAt
	end
	local downed = t.ragdollEnd > hitAt
	local front = facing(t, a)
	local timedParry = front
		and t.parryArmed
		and t.blockPressAt <= hitAt + Config.LATENCY_FORGIVENESS
		and hitAt - t.blockPressAt <= Config.PARRY_WINDOW + Config.LATENCY_FORGIVENESS
	if not downed and (timedParry or t.freeParryUntil > hitAt) then
		t.parryArmed = false -- one parry per press
		t.freeParryUntil = 0
		if kind == "Uppercut" then
			-- a parried uppercut throws both fighters apart (Block-Parry)
			local away = flatUnit(t.root.Position - a.root.Position)
			knock(t, away * Config.PARRIED_UPPERCUT_KNOCKBACK)
			knock(a, -away * Config.PARRIED_UPPERCUT_KNOCKBACK)
		else
			breakPosture(a, Config.PARRY_ATTACKER_STUN)
		end
		fire("Parry", a, t)
		return
	end

	local juggled = t.juggleUntil > hitAt
	local spike = juggled and finisher and (kind == "M1" or kind == "Heavy")
	local damage = if spike then Config.SPIKE_DAMAGE elseif kind == "M1" and finisher then Config.FINISHER_DAMAGE else DAMAGE[kind]
	damage *= taken
	if t.blocking and front and not downed then
		local postureDamage = damage * Config.BLOCK_POSTURE_DRAIN_MULT
		if kind == "Heavy" then
			postureDamage += Config.FLOURISH_POSTURE_DAMAGE
		elseif kind == "Uppercut" then
			postureDamage += Config.UPPERCUT_POSTURE_DAMAGE
		elseif kind == "Crit" then
			postureDamage += Config.CRIT_POSTURE_DAMAGE
		end
		if ganked then
			postureDamage *= Config.GANK_POSTURE_TAKEN
		end
		t.humanoid:TakeDamage(damage * (1 - Config.BLOCK_DAMAGE_REDUCTION))
		fire(if hurtPosture(t, postureDamage) then "Break" else "Blocked", a, t, reaction)
		return
	end

	-- counter hit: the target was winding up a swing of their own
	local counter = not downed and t.pendingHitAt > hitAt
	local bonus = if counter then Config.COUNTER_STUN_BONUS else 0
	if counter then
		damage *= Config.COUNTER_DAMAGE_MULT
		fire("Counter", a, t)
	end
	t.humanoid:TakeDamage(damage)
	if kind == "M1" or kind == "Heavy" then
		a.landedAt = hitAt
		a.landedCombo = reaction
	end
	if not downed and t.armorUntil <= hitAt then
		local forward = flatUnit(a.root.CFrame.LookVector)
		if kind == "Uppercut" then
			-- the launch: both fighters go up (the attacker's client follows the Launch result)
			stun(t, Config.LAUNCH_RISE + Config.JUGGLE_HOLD + bonus)
			juggle(t, Config.LAUNCH_RISE, Config.LAUNCH_HEIGHT, Config.JUGGLE_HOLD)
			fire("Launch", a, t, { rise = Config.LAUNCH_RISE, height = Config.LAUNCH_HEIGHT, hold = Config.JUGGLE_HOLD })
		elseif kind == "Aerial" then
			clearJuggle(t)
			stun(t, Config.AERIAL_STUN + bonus)
			knock(t, Vector3.new(0, -Config.AERIAL_SLAM, 0))
		elseif kind == "Crit" then
			clearJuggle(t)
			stun(t, Config.CRIT_STUN + bonus)
			knock(t, forward * Config.CRIT_KNOCKBACK + Vector3.new(0, 12, 0))
			wallSplat(a, t, forward, Config.CRIT_KNOCKBACK)
			fire("CritHit", a, t)
		elseif spike then
			-- the air finisher drives the body into the ground
			clearJuggle(t)
			stun(t, Config.SPIKE_STUN + bonus)
			knock(t, forward * Config.SPIKE_FORWARD + Vector3.new(0, -Config.SPIKE_SPEED, 0))
			fire("Spike", a, t)
		elseif juggled then
			-- an air hit: the body keeps floating in front of the attacker
			stun(t, math.max(hitStun or Config.M1_HITSTUN, Config.JUGGLE_HOLD) + bonus)
			juggle(t, 0, 0, Config.JUGGLE_HOLD)
			knock(t, forward * Config.JUGGLE_PUSH)
		elseif finisher then
			stun(t, Config.FINISHER_STUN + bonus)
			knock(t, forward * Config.FINISHER_KNOCKBACK + Vector3.new(0, 8, 0))
			wallSplat(a, t, forward, Config.FINISHER_KNOCKBACK)
		else
			stun(t, (hitStun or Config.M1_HITSTUN) + bonus)
			knock(t, forward * Config.M1_PUSH)
		end
	end
	fire("Hit", a, t, if kind == "Uppercut" or kind == "Aerial" or kind == "Crit" or finisher then HEAVY_REACTION else reaction)
end

-- Runs the hit `windup` after `received`, unless the attacker was interrupted or feinted.
local function schedule(a: Fighter, kind: HitKind, received: number, windup: number, reaction: number, finisher: boolean, hitStun: number?)
	a.attackSerial += 1
	local serial = a.attackSerial
	local hitAt = received + windup
	a.pendingHitAt = hitAt
	task.delay(windup + Config.LATENCY_FORGIVENESS, function()
		if a.attackSerial ~= serial or a.humanoid.Health <= 0 then
			return
		end
		a.pendingHitAt = 0
		local drop = if kind == "Aerial" then Config.AERIAL_HITBOX_DROP else 0
		for _, t in Hitbox.front(a, drop) do
			if a.attackSerial ~= serial then
				break -- parried (or otherwise interrupted) part-way through the targets
			end
			resolve(a, t, kind, hitAt, reaction, finisher, hitStun)
		end
	end)
end

local function onAttack(player: Player, comboIndex: any, _stamp: any)
	if not RateLimit.allow(player, "Attack", Config.RATE_ATTACK) then
		return
	end
	if typeof(comboIndex) ~= "number" or comboIndex ~= math.floor(comboIndex) then
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	local received = now()
	if busy(f, received) or f.blocking or received < f.nextAttackAt - TOLERANCE then
		reject(player)
		return
	end
	local maxCombo = if player:GetAttribute("FinalUpgradeUnlocked") == true then Config.COMBO_LENGTH else Config.COMBO_LENGTH - 1
	local expected = if f.combo > 0 and received <= f.chainUntil + TOLERANCE then f.combo + 1 else 1
	if expected > maxCombo then
		expected = 1
	end
	if comboIndex ~= expected then
		reject(player)
		return
	end
	local hit = Config.M1_HITS[comboIndex]
	local animationEnd = received + hit.length
	f.actionEnd = animationEnd
	local finisher = comboIndex >= maxCombo
	if finisher then
		f.combo = 0
		f.chainUntil = 0
		f.nextAttackAt = received + Config.COMBO_RESET
	else
		f.combo = comboIndex
		f.chainUntil = animationEnd + Config.COMBO_WINDOW
		f.nextAttackAt = animationEnd
	end
	-- the stun lasts until the next hit of the chain can land (true combo)
	local nextHit = Config.M1_HITS[comboIndex + 1]
	local hitStun = if not finisher and nextHit then hit.length - hit.windup + nextHit.windup + Config.COMBO_STUN_PAD else nil
	schedule(f, if comboIndex == Config.COMBO_LENGTH then "Heavy" else "M1", received, hit.windup, comboIndex, finisher, hitStun)
end

local function onAerial(player: Player, _stamp: any)
	if not RateLimit.allow(player, "Attack", Config.RATE_ATTACK) then
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	local received = now()
	if busy(f, received) or f.blocking or received < f.aerialCooldownEnd - TOLERANCE then
		reject(player)
		return
	end
	f.aerialCooldownEnd = received + Config.AERIAL_COOLDOWN
	setCooldown(f, "Aerial", f.aerialCooldownEnd)
	f.combo = 0
	f.chainUntil = 0
	f.actionEnd = received + Config.AERIAL_LENGTH
	f.nextAttackAt = f.actionEnd
	schedule(f, "Aerial", received, Config.AERIAL_WINDUP, HEAVY_REACTION, false)
end

local function onUppercut(player: Player, _stamp: any)
	if not RateLimit.allow(player, "Attack", Config.RATE_ATTACK) then
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	local received = now()
	if (busy(f, received) and not cancelable(f, received)) or received < f.uppercutCooldownEnd - TOLERANCE then
		reject(player)
		return
	end
	f.landedCombo = 0
	f.blocking = false
	f.uppercutCooldownEnd = received + Config.UPPERCUT_COOLDOWN
	setCooldown(f, "Uppercut", f.uppercutCooldownEnd)
	f.combo = 0
	f.chainUntil = 0
	f.actionEnd = received + Config.UPPERCUT_WINDUP + Config.UPPERCUT_RECOVERY
	f.nextAttackAt = f.actionEnd
	schedule(f, "Uppercut", received, Config.UPPERCUT_WINDUP, HEAVY_REACTION, false)
end

local function onCrit(player: Player, _stamp: any)
	if not RateLimit.allow(player, "Attack", Config.RATE_ATTACK) then
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	local received = now()
	if busy(f, received) or f.blocking or received < f.critCooldownEnd - TOLERANCE then
		reject(player)
		return
	end
	f.critCooldownEnd = received + Config.CRIT_COOLDOWN
	setCooldown(f, "Crit", f.critCooldownEnd)
	f.combo = 0
	f.chainUntil = 0
	f.actionEnd = received + Config.CRIT_LENGTH
	f.nextAttackAt = f.actionEnd
	fire("CritStart", f, nil) -- everyone sees the red warning flash
	schedule(f, "Crit", received, Config.CRIT_WINDUP, HEAVY_REACTION, false)
end

local function onFeint(player: Player)
	if not RateLimit.allow(player, "Attack", Config.RATE_ATTACK) then
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	local received = now()
	if f.pendingHitAt == 0 or received >= f.pendingHitAt or received < f.feintCooldownEnd - TOLERANCE then
		reject(player)
		return
	end
	f.attackSerial += 1 -- the swing never lands
	f.pendingHitAt = 0
	f.armorUntil = 0
	f.combo = 0
	f.chainUntil = 0
	f.actionEnd = received + Config.FEINT_RECOVERY
	f.nextAttackAt = f.actionEnd
	f.feintCooldownEnd = received + Config.FEINT_COOLDOWN
	fire("Feint", f, nil)
end

-- ── grabs ───────────────────────────────────────────────────────────────────

local function throw(a: Fighter, t: Fighter, direction: string)
	if a.player then
		t.lastPlayerHitAt = now()
	end
	t.humanoid:TakeDamage(Config.THROW_DAMAGE)
	if direction == "Up" then
		Ragdoll.release(t, false)
		knock(t, Vector3.new(0, Config.THROW_UP_VELOCITY, 0))
		-- stunned until the peak of the throw
		stun(t, Config.KNOCKBACK_TIME + Config.THROW_UP_VELOCITY / workspace.Gravity)
	elseif direction == "Down" then
		Ragdoll.release(t, true)
		Ragdoll.start(t, Config.BURY_RAGDOLL_DURATION)
		t.root.AssemblyLinearVelocity = Vector3.new(0, -Config.BURY_VELOCITY, 0)
		t.freeParryUntil = now() + Config.BURY_RAGDOLL_DURATION + Config.BURY_FREE_PARRY
		stun(t, Config.BURY_RAGDOLL_DURATION)
	else
		local side = flatUnit(a.root.CFrame.RightVector) * (if direction == "Right" then 1 else -1)
		Ragdoll.release(t, true)
		Ragdoll.start(t, Config.FLING_RAGDOLL_DURATION)
		t.root.AssemblyLinearVelocity = side * Config.FLING_VELOCITY + Vector3.new(0, Config.FLING_LIFT, 0)
		stun(t, Config.FLING_RAGDOLL_DURATION)
		wallSplat(a, t, side, Config.FLING_VELOCITY)
	end
	fire("Throw", a, t, direction)
end

local function onGrab(player: Player, direction: any, _stamp: any)
	if not RateLimit.allow(player, "Attack", Config.RATE_ATTACK) then
		return
	end
	if typeof(direction) ~= "string" or not THROWS[direction] then
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	local received = now()
	if busy(f, received) or received < f.grabCooldownEnd - TOLERANCE then
		reject(player)
		return
	end
	local release = (Config.THROW_RELEASE :: { [string]: number })[direction]
	f.blocking = false
	f.combo = 0
	f.chainUntil = 0
	f.grabCooldownEnd = received + Config.GRAB_COOLDOWN
	setCooldown(f, "Grab", f.grabCooldownEnd)
	f.actionEnd = received + Config.GRAB_STARTUP + release + Config.THROW_RECOVERY
	f.nextAttackAt = f.actionEnd
	if player:GetAttribute("FinalUpgradeUnlocked") == true then
		f.armorUntil = received + Config.GRAB_STARTUP + release -- hyper-armor (Directional-Grab)
	end
	f.attackSerial += 1
	local serial = f.attackSerial
	local connectAt = received + Config.GRAB_STARTUP
	f.pendingHitAt = connectAt
	task.delay(Config.GRAB_STARTUP + Config.LATENCY_FORGIVENESS, function()
		if f.attackSerial ~= serial or f.humanoid.Health <= 0 then
			return
		end
		f.pendingHitAt = 0
		local victim = Hitbox.nearest(f, Config.GRAB_RANGE, function(t)
			return t.humanoid.Health > 0
				and not t.heldBy
				and not t.knocked -- a knocked body only takes a grip or a carry
				and t.carriedBy == nil
				and t.grippedBy == nil
				and t.ragdollEnd <= connectAt
				and not (t.iframeStart <= connectAt and connectAt <= t.iframeEnd)
		end)
		if not victim then
			f.actionEnd = now() + Config.GRAB_WHIFF_RECOVERY
			f.nextAttackAt = f.actionEnd
			f.armorUntil = 0
			fire("GrabWhiff", f, nil)
			return
		end
		local held = victim :: Fighter
		stun(held, release + 0.3)
		Ragdoll.hold(held, f)
		fire("GrabConnect", f, held, direction)
		task.delay(release, function()
			if held.heldBy ~= f then
				return
			end
			if f.attackSerial ~= serial or f.humanoid.Health <= 0 or held.humanoid.Health <= 0 then
				Ragdoll.release(held, false) -- the grabber was interrupted: the victim drops free
				fire("GrabRelease", f, held)
				return
			end
			throw(f, held, direction)
		end)
	end)
end

-- ── defence ─────────────────────────────────────────────────────────────────

local function onBlockStart(player: Player, stamp: any)
	if not RateLimit.allow(player, "Block", Config.RATE_BLOCK) then
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	local received = now()
	if f.broken or busy(f, received) then
		return
	end
	f.blocking = true
	if received >= f.parryCooldownEnd - TOLERANCE then
		f.parryArmed = true
		f.blockPressAt = clampStamp(stamp, received)
		f.parryCooldownEnd = received + Config.PARRY_COOLDOWN
		setCooldown(f, "Parry", f.parryCooldownEnd)
	else
		f.parryArmed = false
	end
end

local function onBlockEnd(player: Player)
	if not RateLimit.allow(player, "Block", Config.RATE_BLOCK) then
		return
	end
	local f = fighterOf(player)
	if f then
		f.blocking = false -- parryArmed stays: a quick tap of F is still a parry
	end
end

local function onDodge(player: Player, direction: any, stamp: any)
	if not RateLimit.allow(player, "Dodge", Config.RATE_DODGE) then
		return
	end
	if typeof(direction) ~= "string" or not DODGES[direction] then
		return
	end
	local f = fighterOf(player)
	if not f then
		return
	end
	local received = now()
	if busy(f, received) or received < f.rollCooldownEnd - TOLERANCE then
		return
	end
	f.blocking = false
	f.iframeStart = clampStamp(stamp, received)
	f.iframeEnd = f.iframeStart + MoveConfig.ROLL_IFRAMES
	f.rollCooldownEnd = received + MoveConfig.ROLL_COOLDOWN
	setCooldown(f, "Roll", f.rollCooldownEnd)
	fire("Dash", f, nil, direction) -- other clients draw the dash (CombatFx)
end

-- ── state ───────────────────────────────────────────────────────────────────

local function stateOf(f: Fighter, at: number): string
	if f.ragdollEnd > at then
		return "Ragdolled"
	elseif f.heldBy then
		return "Grabbed"
	elseif f.stunEnd > at then
		return "Stunned"
	elseif f.iframeEnd > at then
		return "Dodging"
	elseif f.actionEnd > at then
		return "Attacking"
	elseif f.blocking then
		return "Blocking"
	end
	return "Idle"
end

local function tick(dt: number)
	local at = now()
	Knock.step(at)
	for model, f in Fighters.all() do
		if f.broken and at >= f.stunEnd then
			f.broken = false
			f.posture = Config.POSTURE_MAX
		elseif not f.broken and f.posture < Config.POSTURE_MAX and at - f.postureHitAt >= Config.POSTURE_REGEN_DELAY then
			f.posture = math.min(Config.POSTURE_MAX, f.posture + Config.POSTURE_REGEN_RATE * dt)
		end
		-- failsafe: nobody stays ragdolled past their time
		if f.ragdollEnd == 0 and Ragdoll.active(f) and not f.heldBy then
			Ragdoll.stop(f)
		end
		local state = stateOf(f, at)
		if state ~= f.shownState then
			f.shownState = state
			model:SetAttribute("CombatState", state)
		end
		local armored = f.armorUntil > at
		if armored ~= f.shownArmor then
			f.shownArmor = armored
			model:SetAttribute("HyperArmor", if armored then true else nil)
		end
		local ganked = f.gankUntil > at
		if (model:GetAttribute("Ganked") == true) ~= ganked then
			model:SetAttribute("Ganked", if ganked then true else nil)
		end
		local shown = math.floor(f.posture + 0.5)
		if f.player and shown ~= f.shownPosture then
			f.shownPosture = shown
			f.player:SetAttribute("Posture", shown)
		end
	end
end

local function onCharacter(player: Player, character: Model)
	character:WaitForChild("HumanoidRootPart", 10)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or character.Parent == nil then
		return
	end
	player:SetAttribute("PostureMax", Config.POSTURE_MAX)
	player:SetAttribute("Posture", Config.POSTURE_MAX)
	for _, key in { "Roll", "Parry", "Uppercut", "Grab", "Aerial", "Crit" } do
		player:SetAttribute("CooldownEnd_" .. key, 0)
	end
	Fighters.get(character)
end

function CombatService.start()
	result = Remotes.get("CombatResult")
	Remotes.get("AttackRequest").OnServerEvent:Connect(onAttack)
	Remotes.get("AerialRequest").OnServerEvent:Connect(onAerial)
	Remotes.get("UppercutRequest").OnServerEvent:Connect(onUppercut)
	Remotes.get("FeintRequest").OnServerEvent:Connect(onFeint)
	Remotes.get("GrabRequest").OnServerEvent:Connect(onGrab)
	Remotes.get("BlockStart").OnServerEvent:Connect(onBlockStart)
	Remotes.get("BlockEnd").OnServerEvent:Connect(onBlockEnd)
	Remotes.get("DodgeRequest").OnServerEvent:Connect(onDodge)
	Remotes.get("CritRequest").OnServerEvent:Connect(onCrit)
	Knock.init({ fire = fire, stun = stun, busy = busy })

	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	RunService.Heartbeat:Connect(tick)
end

return CombatService
