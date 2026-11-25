--!strict
--[[
	MobStrike - how a mob's attack lands on players, by the same rules CombatService uses between
	players (Block-Parry, Posture, Ragdoll): i-frames dodge it, a timed block facing the mob parries
	it, a block facing the mob cuts blockable damage and drains posture, and anything else hits,
	stuns, knocks back and may ragdoll.

	CombatService is not touched (Map-Art-Direction rule 8). This module reads and writes the shared
	Fighter records and announces outcomes on CombatResult, so players get the same flashes, sounds
	and reaction animations as in PvP.

	Mobs also join combat as targets through CombatService itself: Fighters picks up any model
	with a Humanoid. `MobStrike.enlist` marks a mob's own Fighter as permanently downed, which
	CombatService reads as: takes full damage, never hitstunned, knocked back or grabbed.
]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local CombatFolder = ServerScriptService:WaitForChild("Combat")
local Fighters = require(CombatFolder:WaitForChild("Fighters"))
local Ragdoll = require(CombatFolder:WaitForChild("Ragdoll"))
local Knock = require(CombatFolder:WaitForChild("Knock"))

export type Fighter = Fighters.Fighter
export type Strike = {
	damage: number,
	posture: number,
	parryable: boolean,
	blockable: boolean,
	stun: number,
	knockback: number,
	up: number,
	ragdoll: number,
}
export type Outcome = "Hit" | "Blocked" | "Break" | "Parry" | "Dodged" | "None"

local HEAVY_REACTION = 5 -- CombatController's reaction index for launches and slams
local LIGHT_REACTIONS = 4 -- HitReact1..4 for ordinary hits
local TARGET_TAG = "MobTarget" -- non-player models mobs may fight (test dummies, escorts)

local MobStrike = {}
MobStrike.TARGET_TAG = TARGET_TAG

local result: RemoteEvent? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

local function flatUnit(v: Vector3): Vector3
	local flat = Vector3.new(v.X, 0, v.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zero
end

function MobStrike.fire(kind: string, attacker: Model?, target: Model?, detail: any)
	if not result then
		result = Remotes.get("CombatResult")
	end
	(result :: RemoteEvent):FireAllClients(kind, attacker, target, detail)
end

-- Registers a mob with CombatService's fighter list as a body that cannot be grabbed, stunned
-- or knocked back by players.
function MobStrike.enlist(model: Model): Fighter?
	local f = Fighters.get(model)
	if f then
		f.ragdollEnd = math.huge
	end
	return f
end

-- Players, plus models tagged TARGET_TAG, that are alive.
function MobStrike.isVictim(f: Fighter): boolean
	return f.humanoid.Health > 0 and (f.player ~= nil or CollectionService:HasTag(f.model, TARGET_TAG))
end

-- Every living victim: player characters and TARGET_TAG models (registered as fighters on demand).
function MobStrike.victims(): { Fighter }
	local list: { Fighter } = {}
	local function add(model: Instance?)
		if model and model:IsA("Model") then
			local f = Fighters.get(model)
			if f and MobStrike.isVictim(f) then
				table.insert(list, f)
			end
		end
	end
	for _, player in Players:GetPlayers() do
		add(player.Character)
	end
	for _, model in CollectionService:GetTagged(TARGET_TAG) do
		add(model)
	end
	return list
end

local function collect(parts: { BasePart }, exclude: Model): { Fighter }
	local hits: { Fighter } = {}
	local seen: { [Model]: boolean } = {}
	for _, part in parts do
		local f = Fighters.fromPart(part)
		if f and f.model ~= exclude and not seen[f.model] and MobStrike.isVictim(f) then
			seen[f.model] = true
			table.insert(hits, f)
		end
	end
	return hits
end

-- Victims touching an oriented box.
function MobStrike.inBox(mob: Model, cf: CFrame, size: Vector3): { Fighter }
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { mob }
	return collect(workspace:GetPartBoundsInBox(cf, size, params), mob)
end

-- Victims whose root is within `radius` (flat distance) of `center` and within `height` above or
-- below it.
function MobStrike.inRadius(mob: Model, center: Vector3, radius: number, height: number): { Fighter }
	local hits: { Fighter } = {}
	for _, f in MobStrike.victims() do
		local offset = f.root.Position - center
		if f.model ~= mob and Vector2.new(offset.X, offset.Z).Magnitude <= radius and math.abs(offset.Y) <= height then
			table.insert(hits, f)
		end
	end
	return hits
end

-- A fighter in the air (jumping, launched) clears ground shockwaves.
function MobStrike.airborne(f: Fighter, minHeight: number): boolean
	if f.humanoid.FloorMaterial ~= Enum.Material.Air then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { f.model }
	local hit = workspace:Raycast(f.root.Position, Vector3.new(0, -(minHeight + f.humanoid.HipHeight + 3), 0), params)
	return hit == nil
end

local function facing(defender: Fighter, from: Vector3): boolean
	local to = flatUnit(from - defender.root.Position)
	if to == Vector3.zero then
		return true
	end
	return flatUnit(defender.root.CFrame.LookVector):Dot(to) >= math.cos(math.rad(CombatConfig.BLOCK_ANGLE / 2))
end

-- Same effect as CombatService's stun: the fighter drops whatever it was doing.
local function stun(f: Fighter, duration: number)
	f.stunEnd = math.max(f.stunEnd, now() + duration)
	f.blocking = false
	f.parryArmed = false
	f.actionEnd = 0
	f.pendingHitAt = 0
	f.armorUntil = 0
	f.combo = 0
	f.chainUntil = 0
	f.attackSerial += 1
	Knock.interrupt(f) -- and lets go of a grip or a carried body
end

-- Returns true when this drain broke the posture.
local function hurtPosture(f: Fighter, amount: number): boolean
	f.posture = math.max(0, f.posture - amount)
	f.postureHitAt = now()
	if f.posture <= 0 then
		f.posture = 0
		f.broken = true
		stun(f, CombatConfig.POSTURE_BREAK_STUN)
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
	mover.MaxForce = CombatConfig.KNOCKBACK_FORCE
	mover.VectorVelocity = velocity
	mover.Parent = f.root
	Debris:AddItem(mover, CombatConfig.KNOCKBACK_TIME)
	Debris:AddItem(attachment, CombatConfig.KNOCKBACK_TIME)
end

-- Pushes without damage (roars): skipped by i-frames, blocked by nothing.
function MobStrike.shove(t: Fighter, from: Vector3, speed: number, up: number)
	local at = now()
	if t.iframeStart <= at and at <= t.iframeEnd then
		return
	end
	knock(t, flatUnit(t.root.Position - from) * speed + Vector3.new(0, up, 0))
end

--[[
	Resolves one hit of `s` from the mob on `t`, landing at server time `hitAt`. `from` is where the
	blow comes from (the mob's root by default; a projectile's landing point for blocks).
]]
function MobStrike.resolve(mob: Fighter, t: Fighter, s: Strike, hitAt: number, from: Vector3?): Outcome
	if t.humanoid.Health <= 0 or t.heldBy or t.knocked or t.carriedBy then -- knocked bodies only take a grip
		return "None"
	end
	if t.iframeStart <= hitAt and hitAt <= t.iframeEnd then
		if hitAt - t.iframeStart <= CombatConfig.PERFECT_DODGE_WINDOW + CombatConfig.LATENCY_FORGIVENESS then
			t.rollCooldownEnd = 0
			if t.player then
				t.player:SetAttribute("CooldownEnd_Roll", 0)
			end
			MobStrike.fire("PerfectDodge", mob.model, t.model)
		else
			MobStrike.fire("Dodged", mob.model, t.model)
		end
		return "Dodged"
	end
	local origin = from or mob.root.Position
	local downed = t.ragdollEnd > hitAt
	local front = facing(t, origin)
	if s.parryable and not downed then
		local tolerance = CombatConfig.LATENCY_FORGIVENESS
		local timed = front
			and t.parryArmed
			and t.blockPressAt <= hitAt + tolerance
			and hitAt - t.blockPressAt <= CombatConfig.PARRY_WINDOW + tolerance
		if timed or t.freeParryUntil > hitAt then
			t.parryArmed = false -- one parry per press
			t.freeParryUntil = 0
			MobStrike.fire("Parry", mob.model, t.model)
			return "Parry"
		end
	end
	if s.blockable and t.blocking and front and not downed then
		if mob.player then
			t.lastPlayerHitAt = hitAt
		end
		t.humanoid:TakeDamage(s.damage * (1 - CombatConfig.BLOCK_DAMAGE_REDUCTION))
		local drain = if s.posture > 0 then s.posture else s.damage * CombatConfig.BLOCK_POSTURE_DRAIN_MULT
		local broke = hurtPosture(t, drain)
		MobStrike.fire(if broke then "Break" else "Blocked", mob.model, t.model, math.random(1, 3))
		return if broke then "Break" else "Blocked"
	end

	if mob.player then
		t.lastPlayerHitAt = hitAt -- a relic move: a player's blow (Combat/Knock knocks instead of killing)
	end
	t.humanoid:TakeDamage(s.damage)
	local heavy = s.ragdoll > 0 or s.up >= 30
	if not downed and t.armorUntil <= hitAt and t.humanoid.Health > 0 then
		local push = flatUnit(t.root.Position - origin) * s.knockback + Vector3.new(0, s.up, 0)
		if s.ragdoll > 0 then
			Ragdoll.start(t, s.ragdoll)
			t.root.AssemblyLinearVelocity = push
			stun(t, s.ragdoll)
		else
			stun(t, s.stun)
			knock(t, push)
		end
	end
	MobStrike.fire("Hit", mob.model, t.model, if heavy then HEAVY_REACTION else math.random(1, LIGHT_REACTIONS))
	return "Hit"
end

return MobStrike
