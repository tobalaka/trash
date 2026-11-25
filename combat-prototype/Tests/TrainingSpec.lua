-- Run in server Play mode after a real Studio player has entered the game.
local Service=require(script.Parent.Parent.Service)
local Players=game:GetService("Players")
local Tests={}
function Tests.Run()
 local player=Players:GetPlayers()[1]
 assert(player and player.Character,"Enter Play before running training checks")
 local character=player.Character
 local root=character.HumanoidRootPart
 local humanoid=character.Humanoid
 local yard=workspace.CombatTrainingYard
 local passed=0
 local function check(value,message) assert(value,message);passed+=1 end
 local function position(location)
  Service.UnregisterCharacter(character)
  character.PrimaryPart=root
  character:PivotTo(location)
  root.AssemblyLinearVelocity=Vector3.zero
  root.AssemblyAngularVelocity=Vector3.zero
  Service.RegisterCharacter(character,player)
  local shield=character:FindFirstChildOfClass("ForceField")
  if shield then shield:Destroy() end
  task.wait(.7)
 end
 local function face(model)
  local point=model:GetAttribute("TrainingHome").Position
  position(CFrame.lookAt(point+Vector3.new(0,0,4),point))
 end
 local parry=yard.Targets.ParryDummy
 local block=yard.Targets.BlockDummy
 local idle=yard.Targets.IdleDummy
 local attacker=yard.Targets.AttackDummy
 for _,model in {parry,block,idle,attacker} do
  check(Service.GetState(model)~=nil,"training target registered")
  check(not model.HumanoidRootPart.Anchored,"training target supports launch")
 end
 check(block:GetAttribute("Blocking") and not block:GetAttribute("Parrying"),"held block never starts with a parry")
 check(idle:GetAttribute("CombatState")=="Idle","idle target takes no actions")
 local oldRotate=humanoid.AutoRotate
 humanoid.AutoRotate=false
 local wall,probe,probeConnection
 local ok,result=xpcall(function()
  face(parry)
  check(Service.Request(character,"M1"),"parry station accepts player swing")
  task.wait(.45)
  check(parry:GetAttribute("TrainingLastResult")=="Parry","automatic dummy parries actual player attack")
  check(parry.Humanoid.Health==10000,"parry prevents damage")
  face(block)
  check(Service.Request(character,"M1"),"block station accepts player swing")
  task.wait(.45)
  check(block:GetAttribute("TrainingLastResult")=="Block","block dummy blocks rather than parries")
  check(block.Humanoid.Health==10000 and Service.GetState(block).posture>=18,"block builds posture without health damage")
  for _=1,5 do
   task.wait(.25)
   check(Service.Request(character,"M1"),"posture pressure swing accepted")
   task.wait(.45)
  end
  check(Service.GetState(block).breakUntil>workspace:GetServerTimeNow(),"repeated pressure breaks dummy guard")
  face(idle)
  check(Service.Request(character,"Uppercut"),"idle station accepts uppercut")
  local height=idle.HumanoidRootPart.Position.Y
  task.wait(.55)
  check(idle.Humanoid.Health==9988,"idle dummy receives uppercut damage")
  check(idle.HumanoidRootPart.Position.Y>height+1 and Service.GetState(idle).air~=nil,"idle dummy physically launches")
  check(Service.Request(character,"Chase"),"idle dummy launch supports chase")
  task.wait(.35)
  check(Service.Request(character,"M1"),"aerial M1 accepted on idle dummy")
  task.wait(.45)
  check(idle.Humanoid.Health==9978,"aerial follow-up connects against training target")
  position(CFrame.new(1380,12.55,1828))
  local origin=root.Position
  local clientTravel
  probe=script.Parent.DashClientProbe:Clone()
  local report=Instance.new("RemoteEvent");report.Name="Report";report.Parent=probe
  probeConnection=report.OnServerEvent:Connect(function(sender,distance)
   if sender==player and type(distance)=="number" then clientTravel=distance end
  end)
  probe.Parent=player.PlayerGui
  task.wait(.2)
  check(Service.Request(character,"Dodge",Vector3.new(1,0,0)),"player dodge accepted")
  check(root:GetNetworkOwner()==player,"player retains local dash simulation")
  task.wait(.65)
  check(clientTravel and clientTravel>.5,"client moves during first 100 ms of dash")
  check((root.Position-origin).Magnitude>1,"dash movement reaches server")
  probeConnection:Disconnect();probeConnection=nil
  probe:Destroy();probe=nil
  check(root:FindFirstChild("CombatMotion")==nil,"dash constraint clears")
  check((root.Position-origin).Magnitude<10.5,"dash stays within server travel budget")
  task.wait(.6)
  check(Service.Request(character,"Dodge",Vector3.new(1,0,0)),"cancel test dodge accepted")
  task.wait(.05)
  check(Service.Request(character,"DodgeCancel"),"early dash cancel accepted")
  check(root:FindFirstChild("CombatMotion")==nil,"dash cancel removes movement constraint")
  task.wait(.8)
  position(CFrame.new(1380,12.55,1828))
  wall=Instance.new("Part")
  wall.Size=Vector3.new(1,10,10);wall.Position=root.Position+Vector3.new(3,0,0);wall.Anchored=true;wall.Parent=workspace
  origin=root.Position
  check(Service.Request(character,"Dodge",Vector3.new(1,0,0)),"wall test dodge accepted")
  task.wait(.45)
  check(root.Position.X<origin.X+3,"dash does not pass through a solid wall")
  wall:Destroy();wall=nil
  face(attacker)
  local health=humanoid.Health
  task.wait(1.05)
  check(humanoid.Health<health,"attacker dummy damages real nearby player")
  check(attacker:GetAttribute("TrainingLastResult")=="Hit","attacker uses normal combat contacts")
  position(CFrame.new(1380,12.55,1832))
  task.wait(1.2)
  check(not Service.GetState(attacker).attack,"attacker stops when player leaves lane")
  return {passed=passed,suite="CombatTrainingYard"}
 end,debug.traceback)
 if wall then wall:Destroy() end
 if probeConnection then probeConnection:Disconnect() end
 if probe then probe:Destroy() end
 humanoid.AutoRotate=oldRotate
 position(CFrame.new(1380,12.55,1832))
 if not ok then error(result) end
 return result
end
return Tests
