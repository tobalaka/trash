-- Placeholder R6 combat presentation. Gameplay hit windows remain server-owned.
local ContentProvider=game:GetService("ContentProvider")
local Definitions=require(script.Parent.Config.Animations)
local Animations={}
local owners=setmetatable({},{__mode="k"})

Animations.Attacks={
	M1={
		{Name="M1_1",Length=0.516667,Hit=0.216667},
		{Name="M1_2",Length=0.666667,Hit=0.283333},
		{Name="M1_3",Length=0.700000,Hit=0.266667},
		{Name="M1_4",Length=0.616667,Hit=0.183333},
	},
	AirM1={Name="M1_3",Length=0.700000,Hit=0.266667},
	SprintAttack={Name="M1_2",Length=0.666667,Hit=0.283333},
	Critical={Name="Crit",Length=1.000000,Hit=0.550000},
	Uppercut={Name="Uppercut",Length=0.883333,Hit=0.500000},
	Downslam={Name="AerialSlam",Length=0.833333,Hit=0.466667},
}
Animations.Poses={
	Block="Block", ParryAttempt="Block", Parry="Deflect", Parried="Parried",
	Feint="Deflect", Chase="AirDashForward", DodgeCancel="Deflect",
	GuardBreak="GuardBroken", Launch="HitReact5", Landing="SoftLand",
	RollForward="RollForward", RollBackward="RollBackward", RollLeft="RollLeft", RollRight="RollRight",
	AirForward="AirDashForward", AirBackward="AirDashBackward", AirLeft="AirDashLeft", AirRight="AirDashRight",
	Hit1="HitReact1", Hit2="HitReact2", Hit3="HitReact3", Hit4="HitReact4", Hit5="HitReact5",
}

function Animations.clip(action,sequence)
	if action == "M1" then return Animations.Attacks.M1[math.clamp(sequence or 1,1,4)] end
	return Animations.Attacks[action]
end

function Animations.dodgeClip(frame,direction,airborne)
	local forward=frame.LookVector:Dot(direction)
	local right=frame.RightVector:Dot(direction)
	local side=math.abs(forward) >= math.abs(right) and (forward > 0 and "Forward" or "Backward") or (right > 0 and "Right" or "Left")
	return Animations.Poses[(airborne and "Air" or "Roll")..side]
end

-- The clip's impact marker crosses at activeAt; recovery reaches its end at endsAt.
function Animations.plan(clip,packet,now)
	local start=packet.startedAt or packet.serverTime
	local hit=packet.activeAt
	local finish=packet.endsAt
	if now >= finish then return nil end
	local recoverySpeed=(clip.Length-clip.Hit)/math.max(0.01,finish-hit)
	if now < hit then
		local speed=clip.Hit/math.max(0.01,hit-start)
		return {position=math.max(0,now-start)*speed,speed=speed,
			recoverySpeed=recoverySpeed,hitDelay=hit-now,remaining=finish-now}
	end
	return {position=math.min(clip.Length,clip.Hit+(now-hit)*recoverySpeed),speed=recoverySpeed,
		recoverySpeed=recoverySpeed,hitDelay=0,remaining=finish-now}
end

local function get(set,name)
	local track=set:get(name)
	if track and track.Length <= 0 and set.useSaved then return set:useSaved(name) or track end
	return track
end

local function own(track)
	local token={}
	owners[track]=token
	return token
end

function Animations.stop(track,fade)
	if not track then return end
	owners[track]=nil
	track:Stop(fade or 0.06)
end

function Animations.playAttack(set,packet,now)
	local clip=Animations.clip(packet.action,packet.sequence)
	if not clip then return nil end
	local plan=Animations.plan(clip,packet,now)
	if not plan then return nil end
	local track=get(set,clip.Name)
	if not track then return nil end
	local token=own(track)
	track:Play(0.04,1,plan.speed)
	track.TimePosition=math.min(plan.position,math.max(0,track.Length-0.001))
	if plan.hitDelay > 0 then
		task.delay(plan.hitDelay,function()
			if owners[track] == token and track.IsPlaying then track:AdjustSpeed(plan.recoverySpeed) end
		end)
	end
	task.delay(plan.remaining,function()
		if owners[track] == token then Animations.stop(track,0.06) end
	end)
	return track
end

function Animations.playTimed(set,name,duration,fade)
	if duration <= 0 then return nil end
	local track=get(set,name)
	if not track then return nil end
	local token=own(track)
	track:Play(fade or 0.04,1,track.Length > 0 and track.Length/duration or 1)
	task.delay(duration,function()
		if owners[track] == token then Animations.stop(track,0.06) end
	end)
	return track
end

function Animations.hold(set,name)
	local track=get(set,name)
	if track then own(track); track:Play(0.06,1,1) end
	return track
end

function Animations.stopReactions(set)
	for _,name in {"GuardBroken","Parried","Deflect","BlockHit1","BlockHit2","BlockHit3","HitReact1","HitReact2","HitReact3","HitReact4","HitReact5"} do
		local track=set:get(name)
		if track then Animations.stop(track,0.05) end
	end
end

function Animations.usedNames()
	local names={}
	for _,clip in Animations.Attacks.M1 do names[clip.Name]=true end
	for action,clip in Animations.Attacks do if action ~= "M1" then names[clip.Name]=true end end
	for _,name in Animations.Poses do names[name]=true end
	return names
end

function Animations.preload(set)
	local names=Animations.usedNames()
	local ids,seen={},{}
	for name in names do
		local definition=Definitions[name]
		assert(definition,"Missing animation definition: "..name)
		set:get(name)
		if definition.id ~= "" and not seen[definition.id] then
			seen[definition.id]=true
			table.insert(ids,definition.id)
		end
	end
	local failures={}
	local ok,reason=pcall(function()
		ContentProvider:PreloadAsync(ids,function(id,status)
			if status ~= Enum.AssetFetchStatus.Success then table.insert(failures,id) end
		end)
	end)
	local deadline=os.clock()+2
	repeat
		local waiting=false
		for name in names do local track=set:get(name); if track and track.Length <= 0 then waiting=true end end
		if not waiting or os.clock() >= deadline then break end
		task.wait(0.05)
	until false
	local loaded,fallback,missing={},{},{}
	for name in names do
		local track=set:get(name)
		if track and track.Length <= 0 and set.useSaved then track=set:useSaved(name) end
		if not track or track.Length <= 0 then table.insert(missing,name)
		elseif type(track) == "table" then table.insert(fallback,name)
		else table.insert(loaded,name) end
	end
	table.sort(loaded); table.sort(fallback); table.sort(missing)
	return {native=loaded,saved=fallback,missing=missing,fetchFailures=failures,preloadError=not ok and tostring(reason) or nil}
end

return Animations

