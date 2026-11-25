--!strict
--[[
	Knock - knocked, grip and carry (2026-10-25, EXPED / Deepwoken).

	A player or training dummy that drops to 0 health from a player's blow (fists, crits, throws,
	relic moves: lastPlayerHitAt within KNOCK_WINDOW) goes down instead of dying: health is held
	at 1, the body ragdolls for KNOCK_DURATION and nothing can hit it. Mobs, gas, falls and
	everything else still kill as before.
	While someone is down:
	  B (GripRequest)   an enemy in reach executes them: GRIP_TIME, then a real death (Ledger
	                    credits the kill as usual). A hit on the gripper stops it, and so does the
	                    gripper pressing B again (target nil: cancel, user 2026-10-25).
	  V (CarryRequest)  anyone in reach throws them over a shoulder; V again (target nil) drops them.
	                    A hit on the carrier drops them too.
	Left alone they get back up with KNOCK_GETUP_HEALTH and KNOCK_GETUP_GRACE of i-frames. Training
	dummies get up at full health, and an executed dummy is back up a moment later.

	Replicated: character attributes "Knocked", "Gripping", "Carrying", "Carried"; the player
	attribute "Knocked" too (Survival, relics and turf read it). CombatResult kinds: Knocked,
	GetUp, GripStart, GripCancel, Executed, Carry, Drop.
	CombatService owns the fighters; it hands this module fire / stun / busy through Knock.init.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"):WaitForChild("Combat"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Fighters = require(script.Parent:WaitForChild("Fighters"))
local Ragdoll = require(script.Parent:WaitForChild("Ragdoll"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))

type Fighter = Fighters.Fighter

local DUMMY_TAG = "TrainingDummy"
local KNOCK_WINDOW = 1.0 -- seconds: the blow that emptied the health bar came from a player
local REACH_PAD = 2 -- latency allowance on grip / carry range

local Knock = {}

type Api = {
	fire: (kind: string, attacker: Fighter?, target: Fighter?, detail: any) -> (),
	stun: (f: Fighter, duration: number) -> (),
	busy: (f: Fighter, at: number) -> boolean,
}
local api: Api

local executing: { [Fighter]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local carried: { [Fighter]: { Instance } } = setmetatable({}, { __mode = "k" }) :: any
local ownKnockAttr: { [Fighter]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local carryReadyAt: { [Fighter]: number } = setmetatable({}, { __mode = "k" }) :: any

local function now(): number
	return workspace:GetServerTimeNow()
end

local function isDummy(f: Fighter): boolean
	return CollectionService:HasTag(f.model, DUMMY_TAG)
end

local function alive(f: Fighter?): boolean
	return f ~= nil and f.model.Parent ~= nil and f.humanoid.Health > 0
end

local function reach(a: Fighter, t: Fighter, range: number): boolean
	return (a.root.Position - t.root.Position).Magnitude <= range + REACH_PAD
end

function Knock.isDown(f: Fighter): boolean
	return f.knocked
end

-- ── carry ───────────────────────────────────────────────────────────────────

local function drop(carrier: Fighter, why: string?)
	local t = carrier.carrying
	if not t then
		return
	end
	carrier.carrying = nil
	t.carriedBy = nil
	Ragdoll.uncarry(t, carried[t] or {})
	carried[t] = nil
	carryReadyAt[carrier] = now() + Config.CARRY_COOLDOWN
	if carrier.model.Parent then
		carrier.model:SetAttribute("Carrying", nil)
	end
	if t.model.Parent then
		t.model:SetAttribute("Carried", nil)
		-- set down in front of the carrier, then back to the floor as a ragdoll
		if alive(carrier) then
			t.root.CFrame = carrier.root.CFrame * CFrame.new(0, 0, -2.5)
		end
		if t.knocked then
			Ragdoll.start(t, math.max(0.5, t.knockUntil - now()), true)
		else
			t.humanoid.PlatformStand = false
		end
	end
	api.fire("Drop", carrier, t, why)
end

local function carry(a: Fighter, t: Fighter)
	a.carrying = t
	t.carriedBy = a
	Ragdoll.stop(t) -- the joints back, so the limp pose can play
	t.ragdollEnd = 0
	carried[t] = Ragdoll.carry(t, a)
	a.model:SetAttribute("Carrying", true)
	t.model:SetAttribute("Carried", true)
	api.fire("Carry", a, t)
end

-- ── knocked ─────────────────────────────────────────────────────────────────

local function cancelGrip(f: Fighter)
	local t = f.gripping
	if not t then
		return
	end
	f.gripping = nil
	t.grippedBy = nil
	-- free to act again at once
	f.actionEnd = math.min(f.actionEnd, now())
	f.nextAttackAt = math.min(f.nextAttackAt, now())
	if f.model.Parent then
		f.model:SetAttribute("Gripping", nil)
	end
	api.fire("GripCancel", f, t)
end

-- Anything that interrupts `f` (a stun, a knock) lets go of whoever it grips or carries.
function Knock.interrupt(f: Fighter)
	cancelGrip(f)
	drop(f, "Hit")
end

local function knockDown(f: Fighter)
	if f.knocked then
		return
	end
	Knock.interrupt(f)
	if f.heldBy then
		Ragdoll.release(f, true)
	end
	-- no more floating or knockback
	for _, d in f.root:GetChildren() do
		if d.Name == "Juggle" or d.Name == "JuggleAtt" or d.Name == "Knockback" then
			d:Destroy()
		end
	end
	f.juggleUntil = 0
	f.juggleSerial += 1
	api.stun(f, Config.KNOCK_DURATION)
	f.knocked = true
	f.knockUntil = now() + Config.KNOCK_DURATION
	Ragdoll.start(f, Config.KNOCK_DURATION, true)
	f.model:SetAttribute("Knocked", true)
	if f.player and f.player:GetAttribute("Knocked") ~= true then
		f.player:SetAttribute("Knocked", true)
		ownKnockAttr[f] = true
	end
	api.fire("Knocked", nil, f)
end

local function getUp(f: Fighter, healthFraction: number)
	if not f.knocked then
		return
	end
	if f.carriedBy then
		drop(f.carriedBy, "GetUp")
	end
	if f.grippedBy then
		cancelGrip(f.grippedBy)
	end
	f.knocked = false
	f.knockUntil = 0
	executing[f] = nil
	Ragdoll.stop(f)
	f.stunEnd = now()
	f.humanoid.Health = math.max(f.humanoid.Health, f.humanoid.MaxHealth * healthFraction)
	f.iframeStart = now()
	f.iframeEnd = now() + Config.KNOCK_GETUP_GRACE
	if f.model.Parent then
		f.model:SetAttribute("Knocked", nil)
		f.model:SetAttribute("Executed", nil)
	end
	if f.player and ownKnockAttr[f] then
		ownKnockAttr[f] = nil
		f.player:SetAttribute("Knocked", nil)
	end
	api.fire("GetUp", nil, f)
end

local function execute(t: Fighter, by: Fighter)
	api.fire("Executed", by, t)
	if t.player then
		-- the HealthChanged guard below lets this one through; the client sees Executed first
		executing[t] = true
		t.model:SetAttribute("Executed", true)
		task.defer(function()
			if t.humanoid.Parent then
				t.humanoid.Health = 0
			end
		end)
	else
		-- a training dummy: a real death would delete it, so it plays dead and stands back up
		t.knockUntil = now() + 1.6
	end
end

-- ── requests ────────────────────────────────────────────────────────────────

local function fighterOf(player: Player): Fighter?
	local character = player.Character
	return if character then Fighters.get(character) else nil
end

local function targetOf(model: any): Fighter?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	return Fighters.get(model)
end

local function onGrip(player: Player, model: any)
	if not RateLimit.allow(player, "Knock", Config.RATE_KNOCK) then
		return
	end
	local a, t = fighterOf(player), targetOf(model)
	if a and a.gripping then
		-- B again while gripping lets go (the body stays knocked)
		if model == nil or t == a.gripping then
			cancelGrip(a)
		end
		return
	end
	if not a or not t or a == t then
		return
	end
	local at = now()
	if a.knocked or a.carrying or api.busy(a, at) or a.blocking then
		return
	end
	if not t.knocked or t.grippedBy or t.carriedBy or executing[t] or not reach(a, t, Config.GRIP_RANGE) then
		return
	end
	a.gripping = t
	t.grippedBy = a
	a.combo = 0
	a.chainUntil = 0
	a.actionEnd = at + Config.GRIP_TIME
	a.nextAttackAt = a.actionEnd
	a.attackSerial += 1
	local serial = a.attackSerial
	t.knockUntil = math.max(t.knockUntil, at + Config.GRIP_TIME + 0.5)
	a.model:SetAttribute("Gripping", true)
	api.fire("GripStart", a, t)
	task.delay(Config.GRIP_TIME, function()
		if a.gripping ~= t or a.attackSerial ~= serial or not alive(a) or not t.knocked then
			if a.gripping == t then
				cancelGrip(a)
			end
			return
		end
		a.gripping = nil
		t.grippedBy = nil
		if a.model.Parent then
			a.model:SetAttribute("Gripping", nil)
		end
		execute(t, a)
	end)
end

local function onCarry(player: Player, model: any)
	if not RateLimit.allow(player, "Knock", Config.RATE_KNOCK) then
		return
	end
	local a = fighterOf(player)
	if not a then
		return
	end
	if a.carrying then
		drop(a, "Let go")
		return
	end
	local t = targetOf(model)
	local at = now()
	if not t or a == t or a.knocked or a.gripping or api.busy(a, at) or at < (carryReadyAt[a] or 0) then
		return
	end
	if not t.knocked or t.grippedBy or t.carriedBy or executing[t] or not reach(a, t, Config.CARRY_RANGE) then
		return
	end
	a.blocking = false
	carry(a, t)
end

-- ── watching health ─────────────────────────────────────────────────────────

-- Holds `model` at 1 health when a player's blow would have killed it (players and dummies).
function Knock.watch(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or model:GetAttribute("KnockWatched") then
		return
	end
	model:SetAttribute("KnockWatched", true)
	local f = Fighters.get(model)
	if not f then
		return
	end
	local fighter = f :: Fighter
	humanoid.HealthChanged:Connect(function(health)
		if health > 0 or executing[fighter] then
			return
		end
		local dummy = isDummy(fighter)
		if fighter.knocked or dummy or now() - fighter.lastPlayerHitAt <= KNOCK_WINDOW then
			humanoid.Health = 1 -- same frame: the 0 never replicates
			knockDown(fighter)
		end
	end)
end

function Knock.step(at: number)
	for _, f in Fighters.all() do
		if f.knocked and at >= f.knockUntil and not f.grippedBy then
			getUp(f, if isDummy(f) then 1 else Config.KNOCK_GETUP_HEALTH)
		end
		local t = f.carrying
		if t and (not alive(f) or f.knocked or not alive(t)) then
			drop(f, "Lost")
		end
		local g = f.gripping
		if g and (not alive(f) or not g.model.Parent or not reach(f, g, Config.GRIP_RANGE + 2)) then
			cancelGrip(f)
		end
	end
end

-- Read-only timing for the admin combat showcase.
function Knock.carryCooldownEnd(model: Model): number
	local fighter = Fighters.get(model)
	return if fighter then carryReadyAt[fighter] or 0 else 0
end

function Knock.init(given: Api)
	api = given
	Remotes.get("GripRequest").OnServerEvent:Connect(onGrip)
	Remotes.get("CarryRequest").OnServerEvent:Connect(onCarry)
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			character:WaitForChild("HumanoidRootPart", 10)
			if character.Parent then
				Knock.watch(character)
			end
		end)
		if player.Character then
			task.spawn(Knock.watch, player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	-- QA (Studio only): ServerStorage.QAKnock:Invoke(model) knocks a fighter through this module (an
	-- execute_luau require gets its own copy of the modules, so it cannot reach the live fighters)
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "QAKnock"
		hook.OnInvoke = function(model: Model)
			local f = Fighters.get(model)
			if f then
				knockDown(f)
			end
			return f ~= nil
		end
		hook.Parent = game:GetService("ServerStorage")
	end
	Fighters.onRemove(function(f)
		Knock.interrupt(f) -- drops what it carried, lets go of a grip
		if f.carriedBy then
			drop(f.carriedBy, "Lost")
		end
		if f.grippedBy then
			cancelGrip(f.grippedBy)
		end
		executing[f] = nil
	end)
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		local f = character and Fighters.get(character)
		if f then
			Knock.interrupt(f)
			if f.carriedBy then
				drop(f.carriedBy, "Left")
			end
		end
	end)
end

return Knock
