-- Deterministic combat rules. No networking, physics, or client-owned values.
local C = require(script.Parent.Config)
local Core = {}

local function emit(s, kind, reason)
	table.insert(s.events, {kind=kind, reason=reason})
end

function Core.new(now)
	return {
		posture=0, grounded=true, groundSince=now-C.RelaunchGroundTime,
		offenseUntil=0, defenseUntil=0, parryUntil=0, parryReady=0,
		guardHeld=false, protectionUntil=0, protectAt=0, breakUntil=0,
		breakPending=false, breakImmune=0, lastPressure=now,
		cooldowns={}, sequence=0, lastM1=-math.huge, nextAttackId=0,
		dodgeUntil=0, dodgeInvulnerable=0, dodgeStarted=0, airDodgeUsed=false,
		airLocked=false, air=nil, pursuing=nil, chase=nil,
		forcedUntil=0, controlSince=nil, freeSince=nil, events={},
	}
end

function Core.protected(s, now)
	return now < s.protectionUntil or s.protectAt > now
end

local function cancelAttack(s, reason)
	if s.attack then s.attack.cancelled=reason; s.attack=nil end
	s.sequence=0
end

local function protect(s, now, delay)
	s.protectAt=now+delay
	s.protectionUntil=now+delay+C.ResetProtection
	s.posture=math.min(s.posture, C.ResetPosture)
	s.breakImmune=now+delay+C.BreakImmunity
	s.breakPending=false
	s.breakUntil=0
end

function Core.endAir(victim, now, reason, winner)
	local air=victim.air
	if not air then return end
	air.active=false
	victim.air=nil
	victim.airLocked=true
	victim.chase=nil
	if air.owner then
		if air.owner.pursuing == air then air.owner.pursuing=nil end
		if air.owner.chase and air.owner.chase.air == air then air.owner.chase=nil end
		emit(air.owner, "PursuitEnded", reason)
	end
	if victim ~= winner then
		cancelAttack(victim, "AirReset")
		victim.offenseUntil=now+C.AirFinalReaction
		victim.defenseUntil=now+C.AirFinalReaction
	else
		victim.offenseUntil=math.max(victim.offenseUntil, now+C.ParryRecovery)
		victim.defenseUntil=math.max(victim.defenseUntil, now+C.ParryRecovery)
	end
	protect(victim, now, math.max(0, victim.defenseUntil-now))
	emit(victim, "AirReset", reason)
end

local function forceReset(s, now)
	if s.air then Core.endAir(s, now, "ControlCap", s) end
	cancelAttack(s, "ControlCap")
	s.offenseUntil=now
	s.defenseUntil=now
	s.dodgeUntil=0
	s.dodgeInvulnerable=0
	s.forcedUntil=now
	protect(s, now, 0)
	s.controlSince=nil
	s.freeSince=now
	emit(s, "ControlReset", "ControlCap")
end

local function force(s, now, offense, defense, reason)
	if now-s.forcedUntil >= C.ActionableReset then s.controlSince=nil end
	if s.freeSince and now-s.freeSince >= C.ActionableReset then s.controlSince=nil end
	s.controlSince=s.controlSince or now
	s.freeSince=nil
	local cap=s.controlSince+C.ControlCap
	if now >= cap then forceReset(s, now); return end
	cancelAttack(s, reason)
	s.dodgeUntil=0
	s.dodgeInvulnerable=0
	s.parryUntil=0
	s.offenseUntil=math.min(now+offense, cap)
	s.defenseUntil=math.min(now+defense, cap)
	s.forcedUntil=math.max(s.offenseUntil, s.defenseUntil)
	emit(s, "Reaction", reason)
end

local function addPosture(s, amount, now)
	s.posture=math.min(C.MaxPosture, s.posture+amount)
	s.lastPressure=now
	if s.posture < C.MaxPosture then return false end
	if now < s.breakImmune then s.posture=C.MaxPosture-1; return false end
	force(s, now, C.GuardBreak, C.GuardBreak, "GuardBreak")
	if Core.protected(s, now) then return false end
	s.breakPending=true
	s.breakUntil=s.defenseUntil
	emit(s, "GuardBreak")
	return true
end

function Core.canDefend(s, now)
	return now >= s.defenseUntil and not s.attack and now >= s.dodgeUntil
end

function Core.guarding(s, now)
	return s.guardHeld and Core.canDefend(s, now)
end

function Core.request(s, action, now)
	Core.tick(s, now, 0)
	if action == "GuardEnd" then
		if s.guardHeld then s.offenseUntil=math.max(s.offenseUntil, now+C.GuardRelease) end
		s.guardHeld=false
		s.parryUntil=0
		return true, {kind="GuardEnd"}
	elseif action == "GuardStart" then
		if s.guardHeld then return false, "AlreadyHeld" end
		s.guardHeld=true
		if Core.canDefend(s, now) and now >= s.parryReady then
			s.parryUntil=now+C.ParryWindow
			s.parryReady=now+C.ParryCooldown
		end
		s.lastPressure=now
		return true, {kind="GuardStart"}
	elseif action == "Feint" then
		local attack=s.attack
		if not attack or now > attack.start+attack.definition.Startup*C.FeintFraction then return false,"FeintWindow" end
		if now < (s.cooldowns.Feint or 0) then return false,"Cooldown" end
		cancelAttack(s, "Feint")
		s.offenseUntil=now+C.FeintOffense
		s.defenseUntil=now+C.FeintDefense
		s.cooldowns.Feint=now+C.FeintCooldown
		return true,{kind="Feint"}
	elseif action == "DodgeCancel" then
		if now >= s.dodgeUntil or now > s.dodgeStarted+C.DodgeCancelWindow then return false,"CancelWindow" end
		s.dodgeUntil=0
		s.dodgeInvulnerable=0
		s.defenseUntil=s.dodgeStarted+C.DodgeCancelDefense
		return true,{kind="DodgeCancel"}
	elseif action == "Chase" then
		local chase=s.chase
		if not chase or now > chase.expires or not chase.air.active then return false,"NoLaunch" end
		if now < s.forcedUntil then return false,"Locked" end
		cancelAttack(s, "Chase")
		s.chase=nil
		s.pursuing=chase.air
		s.airDodgeUsed=false
		s.offenseUntil=math.max(now, chase.hitTime+C.ChaseAttackDelay)
		s.defenseUntil=now
		s.airAttackGate=chase.hitTime+C.ChaseAttackDelay
		s.grounded=false
		return true,{kind="Chase", target=chase.target}
	elseif action == "Dodge" then
		if not Core.canDefend(s, now) then return false,"Locked" end
		if now < (s.cooldowns.Dodge or 0) then return false,"Cooldown" end
		if not s.grounded and s.airDodgeUsed then return false,"AirDodgeSpent" end
		if not s.grounded then s.airDodgeUsed=true end
		s.cooldowns.Dodge=now+C.DodgeCooldown
		s.dodgeStarted=now
		s.dodgeUntil=now+C.DodgeDuration
		s.dodgeInvulnerable=now+C.DodgeInvulnerability
		s.offenseUntil=s.dodgeUntil
		s.defenseUntil=s.dodgeUntil
		s.sequence=0
		return true,{kind="Dodge"}
	end
	if action == "M1" and not s.grounded then action="AirM1" end
	local definition=C.Attacks[action]
	if not definition then return false,"UnknownAction" end
	if s.attack or s.guardHeld or now < s.offenseUntil then return false,"Locked" end
	if now < (s.cooldowns[action] or 0) then return false,"Cooldown" end
	if action == "Uppercut" or action == "SprintAttack" then
		if not s.grounded then return false,"GroundOnly" end
	elseif action == "Downslam" then
		local air=s.air or s.pursuing
		if s.grounded or not air or not air.active or s.slamAir == air then return false,"NoAirExchange" end
		s.slamAir=air
	elseif action == "AirM1" and s.grounded then return false,"AirOnly" end
	if action == "Critical" and not s.grounded then return false,"UseDownslam" end
	if not s.grounded and now < (s.airAttackGate or 0) then return false,"ChaseStartup" end
	s.protectionUntil=0
	s.protectAt=0
	s.nextAttackId+=1
	if action == "M1" then
		if now-s.lastM1 > C.SequenceTimeout then s.sequence=0 end
		s.sequence=s.sequence%4+1
		s.lastM1=now
	else s.sequence=0 end
	local attack={id=s.nextAttackId, name=action, definition=definition, start=now,
		activeAt=now+definition.Startup, activeEnd=now+definition.Startup+definition.Active,
		endsAt=now+definition.Startup+definition.Active+definition.Recovery,
		hit={}, sequence=s.sequence, connected=false}
	s.attack=attack
	s.offenseUntil=attack.endsAt
	s.defenseUntil=attack.endsAt
	s.cooldowns[action]=now+(definition.Cooldown or definition.Startup+definition.Active+definition.Recovery)
	s.lastPressure=now
	return true,{kind="Attack", attack=attack}
end

function Core.tick(s, now, dt)
	if s.attack and now >= s.attack.endsAt then
		if not s.attack.connected then s.sequence=0 end
		s.attack=nil
	end
	if s.protectAt > 0 and now >= s.protectAt then s.protectAt=0 end
	if s.breakPending and now >= s.breakUntil then
		s.breakPending=false
		s.posture=C.ResetPosture
		s.breakImmune=now+C.BreakImmunity
	end
	if s.controlSince and now >= s.controlSince+C.ControlCap and s.forcedUntil >= s.controlSince+C.ControlCap then
		forceReset(s, now)
	end
	if now >= s.forcedUntil then
		s.freeSince=s.freeSince or now
		if now-s.freeSince >= C.ActionableReset then s.controlSince=nil end
	end
	if s.air and now >= s.air.expires then Core.endAir(s, now, "Timeout") end
	if s.grounded and now >= s.defenseUntil then
		s.groundSince=s.groundSince or now
		if now-s.groundSince >= C.RelaunchGroundTime then
			s.airLocked=false
			s.airDodgeUsed=false
			s.airAttackGate=nil
		end
	else s.groundSince=nil end
	if not s.attack and not s.guardHeld and now >= s.dodgeUntil and now >= s.offenseUntil
		and now-s.lastPressure >= C.PostureDelay then
		s.posture=math.max(0,s.posture-C.PostureRate*dt)
	end
end

function Core.hit(attacker, defender, attack, now, context)
	if attack.hit[defender] then return {outcome="AlreadyHit"} end
	if attack.cancelled == "Parry" then return {outcome="Cancelled"} end
	attack.hit[defender]=true
	if Core.protected(defender, now) or now < defender.dodgeInvulnerable then return {outcome="Evaded"} end
	local definition=attack.definition
	attack.connected=true
	if context.front and Core.guarding(defender, now) then
		defender.lastPressure=now
		if now < defender.parryUntil then
			defender.parryUntil=0
			defender.parryReady=now+C.ParryRecovery
			defender.posture=math.max(0,defender.posture-C.ParryRelief)
			defender.offenseUntil=now+C.ParryRecovery
			defender.defenseUntil=now+C.ParryRecovery
			force(attacker, now, C.ParriedOffense, C.ParriedDefense, "Parry")
			attack.cancelled="Parry"
			local broken=addPosture(attacker,C.ParryPressure,now)
			local air=defender.air or defender.pursuing
			if air and air.active then Core.endAir(air.victim,now,"AirParry",defender) end
			return {outcome="Parry", guardBreak=broken}
		end
		local broken=addPosture(defender,definition.Posture,now)
		if not broken and not Core.protected(defender,now) then
			defender.offenseUntil=math.max(defender.offenseUntil,now+C.GuardReaction)
		end
		return {outcome="Block",guardBreak=broken}
	end
	attack.connected=true
	local wasBroken=defender.breakPending
	local canLaunch=attack.name == "Uppercut" and context.canLaunch and defender.grounded
		and not defender.airLocked and not Core.protected(defender,now)
		and (now >= defender.forcedUntil or wasBroken)
	local reaction=definition.Reaction
	if attack.name == "Uppercut" and not canLaunch then reaction=0.18 end
	if not defender.airLocked then force(defender,now,reaction,reaction,"Hit") end
	local capReset=Core.protected(defender,now) and not wasBroken
	if capReset then canLaunch=false end
	if wasBroken then
		defender.posture=C.ResetPosture
		protect(defender,now,math.max(0,defender.defenseUntil-now))
	end
	defender.lastPressure=now
	if canLaunch then
		local air={active=true,victim=defender,owner=attacker,expires=now+C.AirDuration,
			remaining=C.AirHits,startY=context.height or 0}
		defender.air=air
		defender.grounded=false
		defender.groundSince=nil
		attacker.chase={target=defender,air=air,expires=now+C.ChaseWindow,hitTime=now}
	elseif not defender.grounded and not defender.airLocked and not capReset then
		local air=defender.air
		if not air then
			air={active=true,victim=defender,expires=now+C.AirDuration,remaining=C.AirHits,startY=context.height or 0}
			defender.air=air
		end
		air.remaining-=1
		if attack.name == "Downslam" or air.remaining <= 0 then Core.endAir(defender,now,"AirLimit") end
	end
	return {outcome="Hit",damage=definition.Damage,launch=canLaunch,
		flourish=attack.name == "M1" and attack.sequence == 4,
		downslam=attack.name == "Downslam"}
end

function Core.stateName(s, now)
	if now < s.breakUntil then return "GuardBreak" end
	if s.attack then return s.attack.name end
	if now < s.dodgeUntil then return "Dodge" end
	if now < s.defenseUntil then return "Recovery" end
	if Core.guarding(s,now) then return "Guard" end
	if now < s.offenseUntil then return "Recovery" end
	return "Idle"
end

return Core
