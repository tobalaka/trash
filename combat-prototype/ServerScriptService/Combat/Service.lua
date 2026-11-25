-- Server adapter: input validation, swept sword contacts, movement, and replication.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace")
local C=require(script.Parent.Config)
local Core=require(script.Parent.Core)
local TestIntegration=require(script.Parent.TestIntegration)
local TrainingYard=require(script.Parent.TrainingYard)
local Service={}
local actors={}
local connections={}
local playerConnections={}
local buckets={}
local started=false
local requestRemote, eventRemote

local ACTIONS={M1=true, AirM1=true, Critical=true, Uppercut=true, SprintAttack=true,
	Downslam=true, GuardStart=true, GuardEnd=true, Feint=true, Dodge=true,
	DodgeCancel=true, Chase=true}

local function clock() return Workspace:GetServerTimeNow() end
local function finite(n) return n == n and math.abs(n) < 1e7 end
local function validVector(v)
	return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z)
end
local function planar(v) return Vector3.new(v.X,0,v.Z) end
local function directionOf(v)
	local flat=planar(v)
	return flat.Magnitude > 0.001 and flat.Unit or Vector3.new(0,0,-1)
end

local function broadcast(kind, actor, fields)
	if not eventRemote then return end
	local packet={kind=kind, character=actor.character, serverTime=clock()}
	if fields then for key,value in fields do packet[key]=value end end
	eventRemote:FireAllClients(packet)
	TestIntegration.OnEvent(kind,actor,fields)
end

local function setAttribute(model, name, value)
	if model:GetAttribute(name) ~= value then model:SetAttribute(name,value) end
end

local function alive(a)
	return a.character.Parent ~= nil and a.humanoid.Health > 0 and a.root.Parent ~= nil
		and validVector(a.root.Position) and validVector(a.root.AssemblyLinearVelocity)
end

local function rayParams(excluded)
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances=excluded
	params.RespectCanCollide=true
	return params
end

local function worldParams()
	local excluded={}
	for character in actors do table.insert(excluded,character) end
	return rayParams(excluded)
end

local function grounded(a)
	if a.core.air and a.root.AssemblyLinearVelocity.Y > 1 then return false end
	local legs=a.humanoid.RigType == Enum.HumanoidRigType.R6 and 2 or 0
	local depth=a.humanoid.HipHeight+a.root.Size.Y/2+legs+0.35
	local hit=Workspace:Raycast(a.root.Position,Vector3.new(0,-depth,0),worldParams())
	return hit ~= nil and hit.Normal.Y > 0.4
end

local function networkOwnership(a, serverOwned)
	if a.root.Anchored then return end
	local canSet=a.root:CanSetNetworkOwnership()
	if not canSet then return end
	if serverOwned then a.root:SetNetworkOwner(nil) else a.root:SetNetworkOwner(a.player) end
end

local function stopMotion(a, onlyKind)
	if a.motion and (not onlyKind or a.motion.kind == onlyKind) then
		a.motion.constraint:Destroy()
		a.motion.attachment:Destroy()
		a.motion=nil
		if a.root.Parent then
			local velocity=a.root.AssemblyLinearVelocity
			a.root.AssemblyLinearVelocity=Vector3.new(0,velocity.Y,0)
		end
	end
end

local function move(a, velocity, duration, kind)
	stopMotion(a)
	-- Short player dodges must not wait for a server ownership round trip.
	local serverOwned=not (kind == "Dodge" and a.player ~= nil)
	networkOwnership(a,serverOwned)
	a.serverOwned=serverOwned
	local attachment=Instance.new("Attachment")
	attachment.Name="CombatMotionAttachment"
	attachment.Parent=a.root
	local constraint=Instance.new("LinearVelocity")
	constraint.Name="CombatMotion"
	constraint.Attachment0=attachment
	constraint.RelativeTo=Enum.ActuatorRelativeTo.World
	constraint.VelocityConstraintMode=Enum.VelocityConstraintMode.Plane
	constraint.PrimaryTangentAxis=Vector3.new(1,0,0)
	constraint.SecondaryTangentAxis=Vector3.new(0,0,1)
	constraint.MaxForce=math.max(10000,a.root.AssemblyMass*6000)
	constraint.PlaneVelocity=Vector2.new(velocity.X,velocity.Z)
	constraint.Parent=a.root
	if kind == "Chase" then
		a.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		a.root.AssemblyLinearVelocity=velocity
	end
	a.motion={constraint=constraint,attachment=attachment,untilTime=clock()+duration,kind=kind,
		velocity=Vector3.new(velocity.X,0,velocity.Z),origin=a.root.Position}
end

local function positionValid(a, now)
	if not alive(a) then return false end
	local elapsed=math.max(0,now-a.lastPositionTime)
	local allowance=math.max(a.baseWalkSpeed,24)*elapsed+4
	if a.motion or a.core.air or a.core.pursuing then allowance=100*elapsed+5 end
	if (a.root.Position-a.lastPosition).Magnitude > allowance then
		a.invalidUntil=now+0.50
		if a.core.attack then a.core.attack.cancelled="Movement"; a.core.attack=nil end
	end
	a.lastPosition=a.root.Position
	a.lastPositionTime=now
	return now >= a.invalidUntil
end

local function sync(a, now)
	local s=a.core
	local inAirExchange=s.air ~= nil or s.pursuing ~= nil
	if inAirExchange then
		if not a.airForce then
			local attachment=Instance.new("Attachment")
			attachment.Name="CombatAirAttachment"
			attachment.Parent=a.root
			local force=Instance.new("VectorForce")
			force.Name="CombatAirGravity"
			force.Attachment0=attachment
			force.RelativeTo=Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass=true
			force.Parent=a.root
			a.airForce={force=force,attachment=attachment}
		end
		a.airForce.force.Force=Vector3.new(0,a.root.AssemblyMass*Workspace.Gravity*(1-C.AirGravityScale),0)
	elseif a.airForce then
		a.airForce.force:Destroy()
		a.airForce.attachment:Destroy()
		a.airForce=nil
	end
	setAttribute(a.character,"CombatState",Core.stateName(s,now))
	setAttribute(a.character,"Posture",math.floor(s.posture*10+0.5)/10)
	setAttribute(a.character,"MaxPosture",C.MaxPosture)
	setAttribute(a.character,"Blocking",Core.guarding(s,now))
	setAttribute(a.character,"Parrying",Core.guarding(s,now) and now < s.parryUntil)
	setAttribute(a.character,"CombatProtected",Core.protected(s,now))
	setAttribute(a.character,"AirHitsRemaining",s.air and s.air.remaining or 0)
	setAttribute(a.character,"AirExchange",s.air ~= nil or s.pursuing ~= nil)
	local movementLocked=now < s.defenseUntil or s.attack ~= nil or now < s.dodgeUntil
	local speed=movementLocked and 0 or (Core.guarding(s,now) and a.baseWalkSpeed*0.4 or a.baseWalkSpeed)
	if a.humanoid.WalkSpeed ~= speed then a.humanoid.WalkSpeed=speed end
	local jumpPower=movementLocked and 0 or a.baseJumpPower
	local jumpHeight=movementLocked and 0 or a.baseJumpHeight
	if a.humanoid.JumpPower ~= jumpPower then a.humanoid.JumpPower=jumpPower end
	if a.humanoid.JumpHeight ~= jumpHeight then a.humanoid.JumpHeight=jumpHeight end
	local owned=(movementLocked or a.motion ~= nil or s.air ~= nil or s.pursuing ~= nil)
		and not (a.player and now < s.dodgeUntil)
	if owned ~= a.serverOwned then networkOwnership(a,owned); a.serverOwned=owned end
end

local function drain(a)
	for _,event in a.core.events do
		if event.kind == "Reaction" or event.kind == "ControlReset" or event.kind == "AirReset" then stopMotion(a) end
		if event.kind == "PursuitEnded" then stopMotion(a,"Chase") end
		if event.kind == "AirReset" or event.kind == "ControlReset" then
			local v=a.root.AssemblyLinearVelocity
			a.root.AssemblyLinearVelocity=Vector3.new(v.X,math.min(v.Y,0),v.Z)
		end
		broadcast(event.kind,a,{reason=event.reason})
	end
	table.clear(a.core.events)
end

function Service.RegisterCharacter(character, player)
	if actors[character] then return actors[character].core end
	local humanoid=character:FindFirstChildOfClass("Humanoid")
	local root=character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then return nil,"MissingRig" end
	local now=clock()
	local a={character=character,humanoid=humanoid,root=root,player=player,core=Core.new(now),
		baseWalkSpeed=humanoid.WalkSpeed,baseJumpPower=humanoid.JumpPower,baseJumpHeight=humanoid.JumpHeight,
		lastPosition=root.Position,lastPositionTime=now,invalidUntil=0,serverOwned=false}
	actors[character]=a
	a.core.character=character
	a.core.grounded=grounded(a)
	if not a.core.grounded then a.core.groundSince=nil end
	humanoid.MaxHealth=C.Health
	humanoid.Health=C.Health
	a.died=humanoid.Died:Connect(function() Service.UnregisterCharacter(character) end)
	a.removed=character.AncestryChanged:Connect(function(_,parent)
		if parent == nil then Service.UnregisterCharacter(character) end
	end)
	sync(a,now)
	broadcast("Registered",a)
	return a.core
end

function Service.UnregisterCharacter(character)
	local a=actors[character]
	if not a then return end
	local now=clock()
	if a.core.air then Core.endAir(a.core,now,"Removed") end
	if a.core.pursuing and a.core.pursuing.active then Core.endAir(a.core.pursuing.victim,now,"Removed") end
	if a.core.chase and a.core.chase.air.active then Core.endAir(a.core.chase.target,now,"Removed") end
	actors[character]=nil
	stopMotion(a)
	if a.airForce then a.airForce.force:Destroy(); a.airForce.attachment:Destroy(); a.airForce=nil end
	a.died:Disconnect()
	a.removed:Disconnect()
	if a.root.Parent then networkOwnership(a,false) end
	if a.humanoid.Parent then
		a.humanoid.WalkSpeed=a.baseWalkSpeed
		a.humanoid.JumpPower=a.baseJumpPower
		a.humanoid.JumpHeight=a.baseJumpHeight
	end
	setAttribute(character,"CombatState","Inactive")
	setAttribute(character,"Blocking",false)
	setAttribute(character,"Parrying",false)
	setAttribute(character,"AirExchange",false)
	setAttribute(character,"CombatProtected",false)
end

function Service.GetState(character)
	return actors[character] and actors[character].core
end

-- Trusted server entry point for players, NPCs, and integration checks.
function Service.Request(character, action, direction)
	local a=actors[character]
	if not a or not alive(a) then return false,"NoCharacter" end
	if type(action) ~= "string" or not ACTIONS[action] then return false,"UnknownAction" end
	if direction ~= nil and not validVector(direction) then return false,"InvalidDirection" end
	if action ~= "Dodge" and direction ~= nil then return false,"UnexpectedPayload" end
	local now=clock()
	if not positionValid(a,now) and action ~= "GuardEnd" then return false,"Movement" end
	a.core.grounded=grounded(a)
	if action == "SprintAttack" and planar(a.root.AssemblyLinearVelocity).Magnitude < 8 then return false,"NotMoving" end
	local accepted,result=Core.request(a.core,action,now)
	if not accepted then return false,result end
	if result.kind == "Attack" then
		local spawnShield=a.character:FindFirstChildOfClass("ForceField")
		if spawnShield then spawnShield:Destroy() end
		result.attack.facing=directionOf(a.root.CFrame.LookVector)
		result.attack.sweepAt=result.attack.activeAt
		if result.attack.name == "SprintAttack" then
			local drift=result.attack.facing*12
			move(a,Vector3.new(drift.X,a.root.AssemblyLinearVelocity.Y,drift.Z),0.20,"SprintAttack")
		end
		broadcast("Attack",a,{action=result.attack.name,attackId=result.attack.id,
			sequence=result.attack.sequence,startedAt=result.attack.start,activeAt=result.attack.activeAt,
			activeEnd=result.attack.activeEnd,endsAt=result.attack.endsAt})
	elseif result.kind == "Dodge" then
		local v=direction and planar(direction) or -directionOf(a.root.CFrame.LookVector)
		if v.Magnitude < 0.01 then v=-directionOf(a.root.CFrame.LookVector) end
		v=v.Unit*C.DodgeSpeed
		move(a,Vector3.new(v.X,a.root.AssemblyLinearVelocity.Y,v.Z),C.DodgeTravelTime,"Dodge")
		broadcast("Dodge",a,{direction=v.Unit,airborne=not a.core.grounded,endsAt=a.core.offenseUntil})
	elseif result.kind == "DodgeCancel" then
		stopMotion(a,"Dodge")
		a.root.AssemblyLinearVelocity=Vector3.new(0,a.root.AssemblyLinearVelocity.Y,0)
		broadcast("DodgeCancel",a,{endsAt=a.core.offenseUntil})
	elseif result.kind == "Chase" then
		local target=actors[result.target.character]
		if target and alive(target) then
			local offset=planar(target.root.Position-a.root.Position)
			-- Finish within sword reach without driving both humanoids into the same space.
			if offset.Magnitude > 0 then offset=offset.Unit*math.min(C.ChaseHorizontal,math.max(0,offset.Magnitude-C.Reach/2)) end
			local horizontal=offset/C.ChaseTravelTime
			local vertical=math.sqrt(2*Workspace.Gravity*C.AirGravityScale*C.ChaseVertical)
			move(a,Vector3.new(horizontal.X,vertical,horizontal.Z),C.ChaseTravelTime,"Chase")
			broadcast("Chase",a,{target=target.character,endsAt=now+C.ChaseTravelTime})
		end
	else
		if result.kind == "Feint" then stopMotion(a,"SprintAttack") end
		broadcast(result.kind,a)
	end
	drain(a)
	sync(a,now)
	return true,result.kind
end

local function canSee(a,b)
	local delta=b.root.Position-a.root.Position
	local hit=Workspace:Raycast(a.root.Position,delta,rayParams({a.character}))
	return not hit or hit.Instance:IsDescendantOf(b.character)
end

local function contact(a,b,attack,now)
	if a == b or not a.root.Parent or not alive(b) or attack.hit[b.core] then return end
	if b.character:FindFirstChildOfClass("ForceField") then return end
	local delta=b.root.Position-a.root.Position
	if delta.Magnitude > C.Reach+2 or math.abs(delta.Y) > C.HitboxHeight+1 then return end
	if not canSee(a,b) then return end
	local incoming=planar(a.root.Position-b.root.Position)
	local facing=directionOf(b.root.CFrame.LookVector)
	local front=incoming.Magnitude < 0.01 or facing:Dot(incoming.Unit) >= math.cos(math.rad(C.GuardAngle/2))
	local ceiling=Workspace:Raycast(b.root.Position,Vector3.new(0,C.LaunchHeight+2,0),worldParams())
	local result=Core.hit(a.core,b.core,attack,now,{front=front,canLaunch=ceiling == nil,height=b.root.Position.Y})
	if result.outcome == "AlreadyHit" or result.outcome == "Cancelled" then return end
	if result.damage then
		b.humanoid:TakeDamage(result.damage)
		if alive(b) then
			if result.launch then
				networkOwnership(b,true)
				b.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
				local v=b.root.AssemblyLinearVelocity
				b.root.AssemblyLinearVelocity=Vector3.new(v.X,math.sqrt(2*Workspace.Gravity*C.AirGravityScale*C.LaunchHeight),v.Z)
			elseif result.downslam then
				local v=b.root.AssemblyLinearVelocity
				b.root.AssemblyLinearVelocity=Vector3.new(v.X,math.min(v.Y,-35),v.Z)
			elseif result.flourish then
				local push=planar(delta)
				if push.Magnitude > 0.01 then b.root:ApplyImpulse(push.Unit*b.root.AssemblyMass*C.FlourishSpeed) end
			elseif b.core.air then
				local air=b.core.air
				if b.root.Position.Y < air.startY+C.AirHeightCap-2 then
					local v=b.root.AssemblyLinearVelocity
					b.root.AssemblyLinearVelocity=Vector3.new(v.X,math.max(v.Y,16),v.Z)
				end
				if a.core.pursuing == air and a.root.Position.Y < air.startY+C.AirHeightCap-2 then
					local v=a.root.AssemblyLinearVelocity
					a.root.AssemblyLinearVelocity=Vector3.new(v.X,math.max(v.Y,16),v.Z)
				end
			end
		end
	end
	broadcast("Contact",a,{target=b.character,outcome=result.outcome,damage=result.damage or 0,
		guardBreak=result.guardBreak or false,attackId=attack.id,launch=result.launch or false,
		action=attack.name,sequence=attack.sequence,reactionEnd=b.core.defenseUntil,
		sourceRecoveryEnd=a.core.offenseUntil})
end

local function collectContacts(a,attack,now)
	local finish=math.min(now,attack.activeEnd)
	local start=math.max(attack.activeAt,attack.sweepAt or attack.activeAt)
	if finish < start or now-attack.activeEnd > C.MaxStep then return {} end
	attack.sweepAt=finish
	attack.sweptDone=finish >= attack.activeEnd
	local result,seen={},{}
	local params=OverlapParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances={a.character}
	-- Four radial samples cover the interval even when a server frame skips active startup.
	for index=0,4 do
		local t=start+(finish-start)*index/4
		local alpha=math.clamp((t-attack.activeAt)/attack.definition.Active,0,1)
		local angle=math.rad(-C.SweepAngle/2+C.SweepAngle*alpha)
		local frame=CFrame.lookAt(a.root.Position,a.root.Position+attack.facing)*CFrame.Angles(0,angle,0)
		local box=frame*CFrame.new(0,0,-C.Reach/2)
		for _,part in Workspace:GetPartBoundsInBox(box,Vector3.new(C.HitboxWidth,C.HitboxHeight,C.Reach),params) do
			local model=part:FindFirstAncestorOfClass("Model")
			while model and not actors[model] do model=model.Parent and model.Parent:FindFirstAncestorOfClass("Model") end
			local b=model and actors[model]
			if b and not seen[b] then seen[b]=true; table.insert(result,b) end
		end
	end
	return result
end

local function step(dt)
	local now=clock()
	local active={}
	for character,a in actors do
		if not alive(a) then Service.UnregisterCharacter(character); continue end
		positionValid(a,now)
		local s=a.core
		local wasGrounded=s.grounded
		s.grounded=grounded(a)
		if s.air and s.grounded and not wasGrounded then Core.endAir(s,now,"Landing") end
		if a.motion then
			local velocity=a.motion.velocity
			local travel=planar(a.root.Position-a.motion.origin)
			local budget=C.DodgeSpeed*C.DodgeTravelTime+2
			local dodgeLimit=a.motion.kind == "Dodge" and travel.Magnitude > budget
			if dodgeLimit then
				a.root.CFrame+=travel.Unit*(budget-travel.Magnitude)
				a.invalidUntil=now+0.50
			end
			local probe=velocity*math.min(dt,0.05)
			if velocity.Magnitude > 0.01 then probe+=velocity.Unit*1.5 end
			local wall=probe.Magnitude > 0.01 and Workspace:Raycast(a.root.Position,probe,rayParams({a.character}))
			local chaseLimit=a.motion.kind == "Chase" and planar(a.root.Position-a.motion.origin).Magnitude >= C.ChaseHorizontal
			if now >= a.motion.untilTime or wall or chaseLimit or dodgeLimit then stopMotion(a) end
		end
		if s.air then
			local air=s.air
			local v=a.root.AssemblyLinearVelocity
			if a.root.Position.Y >= air.startY+C.AirHeightCap then
				a.root.AssemblyLinearVelocity=Vector3.new(v.X,math.min(v.Y,0),v.Z)
			end
			if v.Y > 0 and Workspace:Raycast(a.root.Position,Vector3.new(0,2.5,0),worldParams()) then
				Core.endAir(s,now,"Ceiling")
			end
		end
		if s.pursuing and a.root.Position.Y >= s.pursuing.startY+C.AirHeightCap then
			local v=a.root.AssemblyLinearVelocity
			a.root.AssemblyLinearVelocity=Vector3.new(v.X,math.min(v.Y,0),v.Z)
		end
		local attack=s.attack
		if attack and not attack.sweptDone and now >= attack.activeAt and (attack.sweepAt or attack.activeAt) <= attack.activeEnd
			and now-a.lastPositionTime <= C.MaxStep and now >= a.invalidUntil then
			table.insert(active,{actor=a,attack=attack,targets=collectContacts(a,attack,now)})
		end
		Core.tick(s,now,math.min(dt,C.MaxStep))
	end
	-- Capture all active swings before resolving reactions, so equal-frame active attacks can trade.
	for _,swing in active do
		for _,target in swing.targets do contact(swing.actor,target,swing.attack,now) end
	end
	for _,a in actors do drain(a); sync(a,now) end
end

local function addPlayer(player)
	local function spawn(character)
		local humanoid=character:WaitForChild("Humanoid",10)
		local root=character:WaitForChild("HumanoidRootPart",10)
		if started and humanoid and root and player.Character == character then Service.RegisterCharacter(character,player) end
	end
	playerConnections[player]={player.CharacterAdded:Connect(spawn),player.CharacterRemoving:Connect(Service.UnregisterCharacter)}
	if player.Character then task.spawn(spawn,player.Character) end
end

function Service.Start()
	if started then return end
	assert(RunService:IsServer(),"Combat Service runs on the server")
	started=true
	local folder=ReplicatedStorage:FindFirstChild("CombatRemotes")
	if not folder then folder=Instance.new("Folder"); folder.Name="CombatRemotes"; folder.Parent=ReplicatedStorage end
	assert(folder:IsA("Folder"),"CombatRemotes must be a Folder")
	local function remote(name)
		local value=folder:FindFirstChild(name)
		if not value then value=Instance.new("RemoteEvent"); value.Name=name; value.Parent=folder end
		assert(value:IsA("RemoteEvent"),name.." must be a RemoteEvent")
		return value
	end
	requestRemote=remote("CombatRequest")
	eventRemote=remote("CombatEvent")
	table.insert(connections,requestRemote.OnServerEvent:Connect(function(player,action,direction,...)
		local now=clock()
		local bucket=buckets[player] or {tokens=C.RequestBurst,time=now}
		bucket.tokens=math.min(C.RequestBurst,bucket.tokens+(now-bucket.time)*C.RequestRate)
		bucket.time=now
		buckets[player]=bucket
		if bucket.tokens < 1 then return end
		bucket.tokens-=1
		if select("#",...) > 0 or type(action) ~= "string" or #action > 20 then return end
		if not player.Character then return end
		local a=actors[player.Character]
		if not a or a.player ~= player then return end
		Service.Request(player.Character,action,direction)
	end))
	table.insert(connections,Players.PlayerAdded:Connect(addPlayer))
	table.insert(connections,Players.PlayerRemoving:Connect(function(player)
		buckets[player]=nil
		if player.Character then Service.UnregisterCharacter(player.Character) end
		for _,connection in playerConnections[player] or {} do connection:Disconnect() end
		playerConnections[player]=nil
	end))
	table.insert(connections,RunService.Heartbeat:Connect(step))
	for _,player in Players:GetPlayers() do addPlayer(player) end
	TestIntegration.Start(Service)
	TrainingYard.Start(Service)
end

function Service.Stop()
	if not started then return end
	started=false
	TrainingYard.Stop()
	for _,connection in connections do connection:Disconnect() end
	table.clear(connections)
	for _,list in playerConnections do for _,connection in list do connection:Disconnect() end end
	table.clear(playerConnections)
	for character in actors do Service.UnregisterCharacter(character) end
	table.clear(buckets)
end

return Service


