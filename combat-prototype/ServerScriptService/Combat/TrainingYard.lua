-- Test-copy practice targets. All attacks and defenses use the normal combat service.
local Players=game:GetService("Players")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Core=require(script.Parent.Core)
local Yard={}
local connections={}
local targets={}
local started=false

function Yard.Stop()
	for _,connection in connections do connection:Disconnect() end
	table.clear(connections)
	table.clear(targets)
	started=false
end

function Yard.Start(service)
	if started or not workspace:GetAttribute("JoblessCombatTest") then return end
	local folder=workspace:FindFirstChild("CombatTrainingYard")
	if not folder then return end
	started=true
	local function reset(model,home)
		service.UnregisterCharacter(model)
		model:PivotTo(home)
		local root=model.HumanoidRootPart
		root.AssemblyLinearVelocity=Vector3.zero
		root.AssemblyAngularVelocity=Vector3.zero
		model.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		service.RegisterCharacter(model)
		model.Humanoid.MaxHealth=10000
		model.Humanoid.Health=10000
		model:SetAttribute("TrainingLastResult","")
	end
	for _,model in folder.Targets:GetChildren() do
		local home=model:GetAttribute("TrainingHome")
		local mode=model:GetAttribute("TrainingMode")
		if not home or not mode then continue end
		targets[model]={home=home,mode=mode}
		local prompt=folder.ResetPosts:FindFirstChild(model.Name):FindFirstChildOfClass("ProximityPrompt")
		table.insert(connections,prompt.Triggered:Connect(function(player)
			local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position-prompt.Parent.Position).Magnitude <= 12 then reset(model,home) end
		end))
	end
	local remote=ReplicatedStorage.CombatRemotes:FindFirstChild("TrainingYardTravel")
	if not remote then
		remote=Instance.new("RemoteEvent")
		remote.Name="TrainingYardTravel"
		remote.Parent=ReplicatedStorage.CombatRemotes
	end
	local travelTimes={}
	table.insert(connections,remote.OnServerEvent:Connect(function(player,...)
		if select("#",...) > 0 then return end
		local now=workspace:GetServerTimeNow()
		if now < (travelTimes[player] or 0) then return end
		travelTimes[player]=now+2
		local character=player.Character
		local state=character and service.GetState(character)
		local root=character and character:FindFirstChild("HumanoidRootPart")
		if not state or not root or character.Humanoid.Health <= 0 then return end
		if state.attack or state.air or state.pursuing or now < state.defenseUntil then return end
		service.UnregisterCharacter(character)
		character.PrimaryPart=root
		character:PivotTo(folder.Arrival.CFrame+Vector3.new(0,3,0))
		root.AssemblyLinearVelocity=Vector3.zero
		root.AssemblyAngularVelocity=Vector3.zero
		local shield=character:FindFirstChildOfClass("ForceField")
		if shield then shield:Destroy() end
		service.RegisterCharacter(character,player)
	end))
	table.insert(connections,Players.PlayerRemoving:Connect(function(player) travelTimes[player]=nil end))
	local elapsed=0
	table.insert(connections,RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt
		if elapsed < 0.03 then return end
		elapsed=0
		local now=workspace:GetServerTimeNow()
		for model,info in targets do
			local state=service.GetState(model)
			if not state or not model.Parent then continue end
			local root=model.HumanoidRootPart
			local humanoid=model.Humanoid
			local away=(root.Position-info.home.Position).Magnitude
			if not state.air and away > 22 and now-state.lastPressure > 1 then reset(model,info.home); continue end
			local nearest,distance=nil,14
			for _,player in Players:GetPlayers() do
				local character=player.Character
				local other=character and character:FindFirstChild("HumanoidRootPart")
				local health=character and character:FindFirstChildOfClass("Humanoid")
				if other and health and health.Health > 0 and (other.Position-info.home.Position).Magnitude <= 16 then
					local gap=(other.Position-root.Position).Magnitude
					if gap < distance then nearest=character; distance=gap end
				end
			end
			if info.mode == "Block" then
				if not state.guardHeld then service.Request(model,"GuardStart") end
				-- This station tests held block, including the first incoming swing.
				state.parryUntil=0
			elseif info.mode == "Parry" then
				if state.guardHeld and now >= state.parryUntil then service.Request(model,"GuardEnd") end
				local incoming=nearest and service.GetState(nearest)
				local attack=incoming and incoming.attack
				if attack and distance <= 8 and not state.air and now >= state.forcedUntil then
					local position=nearest.HumanoidRootPart.Position
					local flat=Vector3.new(position.X,root.Position.Y,position.Z)
					if (flat-root.Position).Magnitude > 0.1 then root.CFrame=CFrame.lookAt(root.Position,flat) end
					if now >= attack.activeAt-0.08 and now < attack.activeEnd and now >= state.parryReady and not state.guardHeld then
						service.Request(model,"GuardStart")
					end
				end
			elseif info.mode == "Attack" then
				if nearest and not state.air and not state.pursuing and now >= state.forcedUntil then
					local position=nearest.HumanoidRootPart.Position
					local flat=Vector3.new(position.X,root.Position.Y,position.Z)
					if not state.attack and (flat-root.Position).Magnitude > 0.1 then root.CFrame=CFrame.lookAt(root.Position,flat) end
					if distance > 4.5 then humanoid:MoveTo(flat)
					else
						humanoid:MoveTo(root.Position)
						if now >= (info.nextAttack or 0) then
							local accepted=service.Request(model,"M1")
							if accepted then info.nextAttack=now+0.9 end
						end
					end
				else
					humanoid:MoveTo(info.home.Position)
				end
			end
			local label=model.Head.TrainingLabel.Stats
			local text=string.format("HP %.0f / 10000 | Posture %.0f / 100\n%s | Last: %s",humanoid.Health,state.posture,Core.stateName(state,now),model:GetAttribute("TrainingLastResult") or "")
			if label.Text ~= text then label.Text=text end
		end
	end))
end

return Yard
