-- Run manually: require(ServerScriptService.Combat.Tests.CoreSpec).Run()
local Core=require(script.Parent.Parent.Core)
local C=require(script.Parent.Parent.Config)
local Tests={}

function Tests.Run()
	local passed=0
	local function check(value,message)
		assert(value,message)
		passed+=1
	end
	local function fresh() return Core.new(0) end
	local function attack(s,name,now)
		local ok,result=Core.request(s,name,now)
		assert(ok,name.." at "..now..": "..tostring(result))
		return result.attack
	end
	local function raw(name)
		return {name=name,definition=C.Attacks[name],hit={},sequence=1}
	end
	local function hit(a,b,swing,now,front,launch)
		return Core.hit(a,b,swing,now,{front=front ~= false,canLaunch=launch ~= false,height=3})
	end
	do
		local a,b=fresh(),fresh()
		local swing=attack(a,"M1",0)
		check(not Core.request(a,"M1",0.1),"M1 spam bypasses recovery")
		Core.request(b,"GuardStart",0.12)
		b.posture=50
		local result=hit(a,b,swing,0.24)
		check(result.outcome == "Parry","timed F must parry")
		check(b.posture == 25 and a.posture == 10,"parry posture accounting")
		check(Core.canDefend(a,0.36),"parried attacker can defend before counter M1")
		check(not Core.request(a,"M1",0.40),"parried attacker offense stays locked")
		check(hit(a,b,swing,0.25).outcome == "AlreadyHit","lingering swing hits only once")
	end
	do
		local a,b=fresh(),fresh()
		Core.request(b,"GuardStart",0)
		local swing=attack(a,"M1",0)
		check(hit(a,b,swing,0.24).outcome == "Block","late held F becomes block")
		check(b.posture == 18,"blocked damage becomes posture")
		Core.tick(a,0.61,0)
		check(attack(a,"M1",0.61).sequence == 2,"blocked M1 preserves animation sequence")
		local c,d=fresh(),fresh()
		Core.request(d,"GuardStart",0.12)
		check(hit(c,d,attack(c,"M1",0),0.24,false).outcome == "Hit","rear hit bypasses F")
	end
	do
		local a,b=fresh(),fresh()
		Core.request(b,"GuardStart",0)
		b.posture=98
		local result=hit(a,b,attack(a,"M1",0),0.24)
		check(result.guardBreak and not result.damage,"breaking blocked attack deals no health damage")
		local c=fresh()
		check(hit(c,b,raw("M1"),0.50).outcome == "Hit","break permits one punish")
		check(hit(fresh(),b,raw("M1"),0.55).outcome == "Evaded","second guaranteed punish rejected")
		check(b.posture == 35,"break restores posture baseline")
		local p,q=fresh(),fresh()
		p.posture=95
		Core.request(q,"GuardStart",0.12)
		check(hit(p,q,attack(p,"M1",0),0.24).guardBreak,"parried attacker can break posture")
	end
	do
		local a=fresh()
		attack(a,"Critical",0)
		check(Core.request(a,"Feint",0.10),"early feint accepted")
		check(not Core.request(a,"M1",0.20),"feint has offense lock")
		check(Core.canDefend(a,0.20),"feint permits defense before offense")
		check(not Core.request(a,"Critical",0.30),"feint does not refund critical cooldown")
		local b=fresh()
		attack(b,"M1",0)
		check(not Core.request(b,"Feint",0.20),"late feint rejected")
		Core.tick(b,0.61,0)
		check(attack(b,"M1",0.61).sequence == 1,"whiff resets sequence")
	end
	do
		local a,b=fresh(),fresh()
		Core.request(b,"Dodge",0.10)
		check(hit(a,b,attack(a,"M1",0),0.24).outcome == "Evaded","dodge rejects contact")
		check(Core.request(b,"DodgeCancel",0.20),"early dodge cancel accepted")
		check(b.dodgeInvulnerable == 0,"cancel removes invulnerability")
		check(not Core.request(b,"M1",0.40),"cancel retains original offense lock")
		check(Core.canDefend(b,0.35),"cancel permits guard at original quarter second")
		check(not Core.request(b,"Dodge",0.70),"cancel does not refund dodge cooldown")
		local air=fresh(); air.grounded=false
		check(Core.request(air,"Dodge",0),"first air dodge accepted")
		check(not Core.request(air,"Dodge",1.1),"second air dodge rejected")
	end
	do
		local a,b=fresh(),fresh()
		local swing=attack(a,"Uppercut",0)
		check(hit(a,b,swing,0.42).launch,"clean uppercut launches")
		check(Core.request(a,"Chase",0.50),"chase overrides own uppercut recovery")
		check(not Core.request(a,"M1",0.70),"chase attack gate enforced")
		check(Core.request(a,"M1",0.72),"chase air attack can start after gate")
		check(b.air.remaining == 2,"launcher does not spend air budget")
		hit(fresh(),b,raw("AirM1"),0.94)
		check(b.air.remaining == 1,"first follow-up spends shared budget")
		hit(fresh(),b,raw("AirM1"),1.54)
		check(not b.air and b.airLocked,"second attacker cannot refill air budget")
		check(Core.protected(b,1.60),"air end gets protected reset")
		check(not b.pursuing and not a.pursuing,"end clears chase owner")
		b.grounded=true
		Core.tick(b,1.70,0)
		Core.tick(b,1.91,0)
		check(not b.airLocked,"actionable grounding clears relaunch lock")
	end
	do
		local a,b=fresh(),fresh()
		Core.request(b,"GuardStart",0)
		check(not hit(a,b,attack(a,"Uppercut",0),0.42).launch,"blocked uppercut never launches")
		local c,d=fresh(),fresh()
		check(not hit(c,d,attack(c,"Uppercut",0),0.42,true,false).launch,"low ceiling prevents launch")
		local e,f=fresh(),fresh()
		hit(e,f,raw("M1"),0.30)
		check(not hit(fresh(),f,raw("Uppercut"),0.40).launch,"ordinary hitstun cannot confirm launcher")
		local g,h=fresh(),fresh()
		attack(h,"M1",0.30)
		check(hit(g,h,raw("Uppercut"),0.42).launch,"uppercut can punish committed attack startup")
	end
	do
		local a,b=fresh(),fresh()
		hit(a,b,raw("Uppercut"),0)
		Core.request(b,"GuardStart",0.40)
		check(hit(fresh(),b,raw("AirM1"),0.50).outcome == "Parry","actionable air parry works")
		check(not b.air and b.airLocked,"air parry ends pursuit")
		local c,d=fresh(),fresh()
		hit(c,d,raw("Uppercut"),0)
		Core.tick(d,2.01,0)
		check(not d.air,"timeout ends aerial exchange")
	end
	do
		local b=fresh()
		for index=0,6 do hit(fresh(),b,raw("M1"),index*0.15) end
		Core.tick(b,1.00,0)
		check(Core.protected(b,1.00) and Core.canDefend(b,1.00),"global control cap spans all attackers")
		local c=fresh(); c.posture=80
		Core.tick(c,2,0.50)
		check(c.posture == 70,"idle posture regeneration")
		Core.request(c,"GuardStart",2)
		Core.tick(c,4,0.5)
		check(c.posture == 70,"held guard prevents regeneration")
		check(not Core.request(c,"Damage",4),"unknown action rejected")
	end
	return {passed=passed, suite="CombatCore"}
end

return Tests
