-- Test-copy controls use accepted server actions and reuse the original animation library.
local Players=game:GetService("Players")
local UserInputService=game:GetService("UserInputService")
local ContextActionService=game:GetService("ContextActionService")
local GuiService=game:GetService("GuiService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local RunService=game:GetService("RunService")
local Anims=require(ReplicatedStorage.Shared.Anims)
local Animations=require(ReplicatedStorage.Shared.CombatAnimations)
local Action=require(script.Parent.Action)
local Controller={}

function Controller.start(character)
	local player=Players.LocalPlayer
	local humanoid=character:WaitForChild("Humanoid")
	local root=character:WaitForChild("HumanoidRootPart")
	local set=Anims.forAnimator(humanoid:WaitForChild("Animator"))
	local remotes=ReplicatedStorage:WaitForChild("CombatRemotes")
	local request=remotes:WaitForChild("CombatRequest")
	local events=remotes:WaitForChild("CombatEvent")
	local connections={}
	local swing,token,rollName
	local binding="JoblessCombatMovement"
	local function now() return workspace:GetServerTimeNow() end
	local function send(action,direction) request:FireServer(action,direction) end
	local function stopSwing()
		if swing then Animations.stop(swing,0.08); swing=nil end
		if token then Action.clear(character,token); token=nil end
	end
	local function availableInput()
		return humanoid.Health > 0 and not UserInputService:GetFocusedTextBox() and not GuiService.MenuIsOpen
	end
	local function blocking()
		if character:GetAttribute("Blocking") then Animations.hold(set,Animations.Poses.Block)
		else Animations.stop(set:get(Animations.Poses.Block),0.08) end
	end
	ContextActionService:BindActionAtPriority(binding,function(_,state,input)
		if not availableInput() then return Enum.ContextActionResult.Pass end
		if input.KeyCode == Enum.KeyCode.Q then
			if state == Enum.UserInputState.Begin then
				local direction=humanoid.MoveDirection
				if direction.Magnitude < 0.01 then direction=-root.CFrame.LookVector end
				send("Dodge",direction)
			end
			return Enum.ContextActionResult.Sink
		end
		local chase=(character:GetAttribute("CombatChaseUntil") or 0) > now()
		local locked=(character:GetAttribute("CombatDefenseUntil") or 0) > now()
		if chase or locked or character:GetAttribute("AirExchange") then
			if chase and state == Enum.UserInputState.Begin then send("Chase") end
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end,false,3000,Enum.KeyCode.Q,Enum.KeyCode.Space)
	table.insert(connections,UserInputService.InputBegan:Connect(function(input,processed)
		if processed or not availableInput() then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local current=Action.get(character)
			if current and current ~= "Attack" and current ~= "Uppercut" then return end
			if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
				send("Uppercut")
			elseif character:GetAttribute("Sprinting") and now() >= (player:GetAttribute("CooldownEnd_SprintAttack") or 0) then
				send("SprintAttack")
			else send("M1") end
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			send(character:GetAttribute("CombatState") == "Dodge" and "DodgeCancel" or "Feint")
		elseif input.KeyCode == Enum.KeyCode.F then send("GuardStart")
		elseif input.KeyCode == Enum.KeyCode.R then
			send(character:GetAttribute("AirExchange") and "Downslam" or "Critical")
		end
	end))
	table.insert(connections,UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.F then send("GuardEnd") end
	end))
	table.insert(connections,UserInputService.WindowFocusReleased:Connect(function() send("GuardEnd") end))
	table.insert(connections,character:GetAttributeChangedSignal("Blocking"):Connect(blocking))
	task.spawn(function()
		local report=Animations.preload(set)
		if character.Parent then
			character:SetAttribute("CombatAnimationsReady",#report.missing == 0)
			character:SetAttribute("CombatAnimationMissing",table.concat(report.missing,","))
			character:SetAttribute("CombatAnimationNative",#report.native)
			character:SetAttribute("CombatAnimationSaved",#report.saved)
		end
		if #report.missing > 0 then warn("[Combat animations] Missing: "..table.concat(report.missing,", ")) end
	end)
	local function remaining(packet,duration)
		return math.max(0,(packet.endsAt or packet.serverTime+duration)-now())
	end
	table.insert(connections,events.OnClientEvent:Connect(function(packet)
		if type(packet) ~= "table" then return end
		if packet.character == character then
			if packet.kind == "Attack" then
				stopSwing()
				Animations.stopReactions(set)
				local duration=math.max(0,packet.endsAt-now())
				token=Action.set(character,packet.action == "Uppercut" and "Uppercut" or "Attack",duration)
				swing=Animations.playAttack(set,packet,now())
			elseif packet.kind == "Feint" then
				stopSwing()
				swing=Animations.playTimed(set,Animations.Poses.Feint,remaining(packet,0.18))
			elseif packet.kind == "Chase" then
				stopSwing()
				local duration=remaining(packet,0.20)
				token=Action.set(character,"Uppercut",duration)
				swing=Animations.playTimed(set,Animations.Poses.Chase,duration)
			elseif packet.kind == "Dodge" then
				stopSwing()
				Animations.stopReactions(set)
				rollName=Animations.dodgeClip(root.CFrame,packet.direction,packet.airborne)
				local duration=remaining(packet,0.45)
				token=Action.set(character,"Roll",duration)
				swing=Animations.playTimed(set,rollName,duration)
			elseif packet.kind == "DodgeCancel" then
				stopSwing()
				token=Action.set(character,"Roll",remaining(packet,0.45))
				swing=Animations.playTimed(set,Animations.Poses.DodgeCancel,0.10)
			elseif packet.kind == "Reaction" then stopSwing()
			elseif packet.kind == "ControlReset" then stopSwing(); Animations.stopReactions(set)
			elseif packet.kind == "AirReset" then
				stopSwing()
				Animations.stopReactions(set)
			elseif packet.kind == "Contact" and packet.outcome == "Parry" then
				stopSwing()
				local duration=math.max(0,(packet.sourceRecoveryEnd or now()+0.30)-now())
				Animations.playTimed(set,packet.guardBreak and Animations.Poses.GuardBreak or Animations.Poses.Parried,duration)
			end
		end
		if packet.kind == "Contact" and packet.target == character then
			if packet.outcome == "Hit" then
				stopSwing()
				local name=packet.launch and Animations.Poses.Launch or "HitReact"..math.clamp(packet.sequence or 1,1,5)
				Animations.playTimed(set,name,math.max(0,(packet.reactionEnd or now()+0.18)-now()))
			elseif packet.outcome == "Block" then
				local name=packet.guardBreak and Animations.Poses.GuardBreak or "BlockHit"..((math.max(1,packet.sequence or 1)-1)%3+1)
				local duration=packet.guardBreak and math.max(0,(packet.reactionEnd or now()+0.70)-now()) or 0.13
				Animations.playTimed(set,name,duration)
			elseif packet.outcome == "Parry" then Animations.playTimed(set,Animations.Poses.Parry,0.16) end
		end
	end))
	local landedFromCombat=false
	table.insert(connections,character:GetAttributeChangedSignal("AirExchange"):Connect(function()
		if character:GetAttribute("AirExchange") then landedFromCombat=true end
	end))
	table.insert(connections,humanoid.StateChanged:Connect(function(_,state)
		if state == Enum.HumanoidStateType.Landed and landedFromCombat then
			landedFromCombat=false
			Animations.playTimed(set,Animations.Poses.Landing,0.20)
		end
	end))
	local gui=player.PlayerGui:FindFirstChild("JoblessCombatTest")
	if not gui then
		gui=Instance.new("ScreenGui")
		gui.Name="JoblessCombatTest"
		gui.ResetOnSpawn=false
		gui.DisplayOrder=500
		gui.Parent=player.PlayerGui
		local label=Instance.new("TextLabel")
		label.Name="Status"
		label.AnchorPoint=Vector2.new(0.5,0)
		label.Position=UDim2.new(0.5,0,0,40)
		label.Size=UDim2.fromOffset(640,58)
		label.BackgroundColor3=Color3.fromRGB(20,24,31)
		label.BackgroundTransparency=0.15
		label.TextColor3=Color3.fromRGB(235,225,192)
		label.Font=Enum.Font.GothamMedium
		label.TextSize=13
		label.Parent=gui
	end
	local yard=gui:FindFirstChild("TrainingYard")
	if not yard then
		yard=Instance.new("TextButton")
		yard.Name="TrainingYard"
		yard.AnchorPoint=Vector2.new(0.5,0)
		yard.Position=UDim2.new(0.5,0,0,102)
		yard.Size=UDim2.fromOffset(260,28)
		yard.BackgroundColor3=Color3.fromRGB(35,29,22)
		yard.TextColor3=Color3.fromRGB(245,218,163)
		yard.Text="Travel / reset at desert combat yard"
		yard.Font=Enum.Font.GothamMedium
		yard.TextSize=12
		yard.Parent=gui
	end
	table.insert(connections,yard.Activated:Connect(function()
		local travel=remotes:FindFirstChild("TrainingYardTravel")
		if travel then travel:FireServer() end
	end))
	local elapsed=0
	table.insert(connections,RunService.RenderStepped:Connect(function(dt)
		elapsed+=dt
		if elapsed < 0.1 then return end
		elapsed=0
		gui.Status.Text=string.format("JOBLESS LEGACY · COMBAT TEST COPY | HP %.0f | Posture %.0f/100\nM1 attack · M2 feint/cancel · F parry/block · Q dodge · Ctrl+M1 uppercut · Space chase · R critical/slam",humanoid.Health,character:GetAttribute("Posture") or 0)
	end))
	local cleaned=false
	local function cleanup()
		if cleaned then return end
		cleaned=true
		ContextActionService:UnbindAction(binding)
		for _,connection in connections do connection:Disconnect() end
		stopSwing()
		Animations.stopReactions(set)
		Animations.stop(set:get(Animations.Poses.Block),0)
	end
	humanoid.Died:Once(cleanup)
	character.AncestryChanged:Connect(function(_,parent) if not parent then cleanup() end end)
end

return Controller


