local Animations=require(game.ReplicatedStorage.Shared.CombatAnimations)
local Definitions=require(game.ReplicatedStorage.Shared.Config.Animations)
local Config=require(script.Parent.Parent.Config)
local Tests={}

function Tests.Run()
	local passed=0
	local function check(value,message) assert(value,message); passed+=1 end
	local function near(a,b) return math.abs(a-b)<0.00001 end
	for name in Animations.usedNames() do check(Definitions[name]~=nil,"Missing clip: "..name) end
	for action,definition in Config.Attacks do
		local count=action == "M1" and 4 or 1
		for sequence=1,count do
			local clip=Animations.clip(action,sequence)
			check(clip and clip.Hit>0 and clip.Hit<clip.Length,"Attack has an impact marker")
			local packet={startedAt=10,activeAt=10+definition.Startup,
				endsAt=10+definition.Startup+definition.Active+definition.Recovery}
			check(near(Animations.plan(clip,packet,10).position,0),"Attack starts at first pose")
			check(near(Animations.plan(clip,packet,packet.activeAt).position,clip.Hit),"Impact aligns with server active window")
			local late=Animations.plan(clip,packet,packet.activeAt+0.02)
			check(late.position>clip.Hit,"Late packets catch up instead of restarting")
			check(Animations.plan(clip,packet,packet.endsAt)==nil,"Expired attacks do not replay")
		end
	end
	local frame=CFrame.new()
	for _,case in {
		{Vector3.new(0,0,-1),"Forward"},{Vector3.new(0,0,1),"Backward"},
		{Vector3.new(-1,0,0),"Left"},{Vector3.new(1,0,0),"Right"},
	} do
		check(Animations.dodgeClip(frame,case[1],false)==Animations.Poses["Roll"..case[2]],"Ground dodge direction")
		check(Animations.dodgeClip(frame,case[1],true)==Animations.Poses["Air"..case[2]],"Air dodge direction")
	end
	local track={Length=2.2,Looped=true,IsPlaying=false}
	function track:Play(_,_,speed) self.IsPlaying=true; self.Speed=speed end
	function track:Stop() self.IsPlaying=false end
	local set={}
	function set:get() return track end
	Animations.playTimed(set,"GuardBroken",0.04)
	check(track.IsPlaying,"Guard break starts")
	task.wait(0.07)
	check(not track.IsPlaying,"Looped guard break stops at recovery end")
	Animations.playTimed(set,"Deflect",0.04)
	task.wait(0.02)
	Animations.playTimed(set,"Deflect",0.12)
	task.wait(0.05)
	check(track.IsPlaying,"Older stop cannot cancel a newer play")
	task.wait(0.10)
	check(not track.IsPlaying,"Newest timed play stops")
	Animations.hold(set,"Block")
	task.wait(0.05)
	check(track.IsPlaying,"Held block keeps its pose")
	Animations.stop(track)
	check(not track.IsPlaying,"Guard release stops held pose")
	return {suite="CombatAnimations",passed=passed}
end

return Tests

