-- Run from a normal server Script in Play mode, not the command/plugin require cache.
-- Temporary rigs are removed even on failure.
local Service=require(script.Parent.Parent.Service)
local RunService=game:GetService("RunService")
local Tests={}

function Tests.Run()
	assert(RunService:IsRunning() and RunService:IsServer(),"Run in server Play mode")
	local passed=0
	local created={}
	local folder=Instance.new("Folder")
	folder.Name="CombatIntegrationTemporary"
	folder.Parent=workspace
	local function check(value,message) assert(value,message); passed+=1 end
	local function rig(name,position,facing)
		local description=Instance.new("HumanoidDescription")
		local model=game:GetService("Players"):CreateHumanoidModelFromDescriptionAsync(description,Enum.HumanoidRigType.R6)
		description:Destroy()
		model.Name=name
		local root=model:FindFirstChild("HumanoidRootPart")
		local humanoid=model:FindFirstChildOfClass("Humanoid")
		root.Anchored=true
		model.PrimaryPart=root
		model:PivotTo(CFrame.lookAt(position,position+facing))
		model.Parent=folder
		table.insert(created,model)
		return model,root,humanoid
	end

	local ok,result=xpcall(function()
		local platform=Instance.new("Part")
		platform.Name="TemporaryFloor"
		platform.Size=Vector3.new(80,1,80)
		platform.Position=Vector3.new(10000,-0.5,10000)
		platform.Anchored=true
		platform.Parent=folder
		local a,ar,ah=rig("Attacker",Vector3.new(10000,3,10000),Vector3.new(0,0,-1))
		local b,br,bh=rig("Defender",Vector3.new(10000,3,9996),Vector3.new(0,0,1))
		Service.RegisterCharacter(a)
		Service.RegisterCharacter(b)
		check(Service.GetState(a).grounded,"R6 grounded detection")
		check(game.ReplicatedStorage.CombatRemotes.CombatRequest:IsA("RemoteEvent"),"request remote exists")
		check(not Service.Request(a,"Damage"),"unknown action rejected")
		check(not Service.Request(a,"M1",{damage=100000}),"table damage payload rejected")
		check(not Service.Request(a,"Dodge",Vector3.new(0/0,0,0)),"NaN direction rejected")
		check(Service.Request(a,"M1"),"M1 request accepted")
		check(not Service.Request(a,"M1"),"recovery prevents M1 spam")
		task.wait(0.42)
		check(bh.Health == 90,"server sword sweep deals exactly one M1 hit")
		task.wait(0.30)
		Service.Request(b,"GuardStart")
		task.wait(0.20)
		check(Service.Request(a,"M1"),"second swing accepted")
		task.wait(0.42)
		check(bh.Health == 90,"held block prevents health damage")
		check(Service.GetState(b).posture == 18,"held block adds posture")
		Service.Request(b,"GuardEnd")
		task.wait(0.30)
		check(Service.Request(a,"M1"),"parry test swing accepted")
		task.wait(0.14)
		check(Service.Request(b,"GuardStart"),"fresh F accepted")
		task.wait(0.28)
		check(bh.Health == 90 and Service.GetState(a).posture == 10,"real contacts resolve parry")
		Service.Request(b,"GuardEnd")
		task.wait(0.40)
		local wall=Instance.new("Part")
		wall.Size=Vector3.new(6,8,0.5)
		wall.Position=Vector3.new(10000,3,9998)
		wall.Anchored=true
		wall.Parent=folder
		check(Service.Request(a,"M1"),"wall test swing accepted")
		task.wait(0.42)
		check(bh.Health == 90,"solid wall prevents damage")
		wall:Destroy()
		task.wait(0.30)
		br.Anchored=false
		task.wait(0.40)
		local before=br.Position.Y
		check(Service.Request(a,"Uppercut"),"uppercut request accepted")
		task.wait(0.55)
		check(bh.Health == 78,"uppercut damage is server applied")
		check(br.Position.Y > before+1,"uppercut creates real upward movement")
		check(Service.GetState(b).air ~= nil,"launch owns shared victim exchange")
		ar.Anchored=false
		local chaseOrigin=ar.Position
		check(Service.Request(a,"Chase"),"real confirmed launch allows chase")
		check(Service.GetState(a).pursuing ~= nil,"chase records exchange owner")
		task.wait(0.18)
		check(ar.Position.Y > chaseOrigin.Y+1,"chase creates real upward movement")
		check((Vector3.new(ar.Position.X,0,ar.Position.Z)-Vector3.new(chaseOrigin.X,0,chaseOrigin.Z)).Magnitude <= 11,"chase horizontal travel stays bounded")
		task.wait(math.max(0,Service.GetState(a).airAttackGate-workspace:GetServerTimeNow())+0.02)
		check(Service.Request(a,"M1"),"first real air follow-up accepted")
		task.wait(0.61)
		check(bh.Health == 68,"first real air follow-up connects")
		check(Service.Request(a,"M1"),"second real air follow-up accepted")
		task.wait(0.35)
		check(bh.Health == 58,"second real air follow-up connects; health="..bh.Health.." attacker="..tostring(ar.Position).." defender="..tostring(br.Position))
		check(Service.GetState(b).air == nil and Service.GetState(b).airLocked,"second real air hit ends exchange")
		check(br:FindFirstChild("CombatAirGravity") == nil,"air reset removes gravity assist")
		Service.UnregisterCharacter(b)
		check(Service.GetState(b) == nil and not Service.GetState(a).pursuing,"removal clears both sides of exchange")
		check(not Service.Request(b,"M1"),"removed character cannot request combat")
		check(ah.Health == 100,"test defender never deals unintended damage")
		return {suite="CombatIntegration",passed=passed}
	end,debug.traceback)
	for _,model in created do Service.UnregisterCharacter(model) end
	folder:Destroy()
	if not ok then error(result) end
	return result
end

return Tests


