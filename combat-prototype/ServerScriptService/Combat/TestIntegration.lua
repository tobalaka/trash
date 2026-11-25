-- Copy-only adapters for TRASH presentation, training targets, and read-only legacy telemetry.
local Players=game:GetService("Players")
local CollectionService=game:GetService("CollectionService")
local RunService=game:GetService("RunService")
local ReplicatedStorage=game:GetService("ReplicatedStorage")
local Fighters=require(script.Parent.Fighters)
local Anims=require(ReplicatedStorage.Shared.Anims)
local Animations=require(ReplicatedStorage.Shared.CombatAnimations)
local npcSwings=setmetatable({},{__mode="k"})
local npcGuards=setmetatable({},{__mode="k"})
local Core=require(script.Parent.Core)
local Integration={}
local started=false

local function attribute(object,name,value)
	if object:GetAttribute(name) ~= value then object:SetAttribute(name,value) end
end

local function npcSet(model)
	if not model or Players:GetPlayerFromCharacter(model) then return nil end
	local humanoid=model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local animator=humanoid:FindFirstChildOfClass("Animator")
	if not animator then animator=Instance.new("Animator"); animator.Parent=humanoid end
	return Anims.forAnimator(animator)
end

local function stopNPC(model)
	Animations.stop(npcSwings[model],0.05)
	npcSwings[model]=nil
end

local function npcPose(model,name,duration)
	local set=npcSet(model)
	if set then return Animations.playTimed(set,name,duration) end
end

function Integration.OnEvent(kind,actor,fields)
	fields=fields or {}
	local now=workspace:GetServerTimeNow()
	local folder=ReplicatedStorage:FindFirstChild("Remotes")
	local result=folder and folder:FindFirstChild("CombatResult")
	local set=npcSet(actor.character)
	if kind == "Attack" and set then
		stopNPC(actor.character)
		Animations.stopReactions(set)
		npcSwings[actor.character]=Animations.playAttack(set,fields,now)
	elseif kind == "Dodge" and set then
		stopNPC(actor.character)
		npcSwings[actor.character]=Animations.playTimed(set,Animations.dodgeClip(actor.root.CFrame,fields.direction,fields.airborne),math.max(0,fields.endsAt-now))
	elseif kind == "Chase" and set then
		stopNPC(actor.character)
		npcSwings[actor.character]=Animations.playTimed(set,Animations.Poses.Chase,math.max(0,fields.endsAt-now))
	elseif kind == "Feint" or kind == "DodgeCancel" then
		stopNPC(actor.character)
		npcSwings[actor.character]=npcPose(actor.character,Animations.Poses.Feint,kind == "Feint" and 0.18 or 0.10)
		if kind == "Feint" and result then result:FireAllClients("Feint",actor.character,nil,0) end
	elseif kind == "Reaction" or kind == "AirReset" or kind == "ControlReset" then
		stopNPC(actor.character)
	elseif kind == "GuardStart" and set and Core.guarding(actor.core,now) then
		npcGuards[actor.character]=true
		Animations.hold(set,Animations.Poses.Block)
	elseif kind == "GuardEnd" and set then
		npcGuards[actor.character]=false
		Animations.stop(set:get(Animations.Poses.Block))
	end
	if kind == "Contact" then
		if fields.target and fields.target:GetAttribute("TrainingMode") then fields.target:SetAttribute("TrainingLastResult",fields.outcome) end
		if actor.character:GetAttribute("TrainingMode") == "Attack" then actor.character:SetAttribute("TrainingLastResult",fields.outcome) end
		local names={Hit="Hit",Block="Blocked",Parry="Parry"}
		local legacy=names[fields.outcome]
		local detail=fields.launch and 5 or math.max(fields.sequence or 1,1)
		if legacy and result then result:FireAllClients(legacy,actor.character,fields.target,detail) end
		if fields.outcome == "Hit" then
			stopNPC(fields.target)
			npcPose(fields.target,"HitReact"..math.clamp(detail,1,5),math.max(0,(fields.reactionEnd or now+0.18)-now))
		elseif fields.outcome == "Block" and not fields.guardBreak then
			npcPose(fields.target,"BlockHit"..((detail-1)%3+1),0.13)
		elseif fields.outcome == "Parry" then
			stopNPC(actor.character)
			npcPose(actor.character,Animations.Poses.Parried,math.max(0,(fields.sourceRecoveryEnd or now+0.30)-now))
			npcPose(fields.target,Animations.Poses.Parry,0.16)
		end
		if fields.guardBreak then
			local victim=fields.outcome == "Parry" and actor.character or fields.target
			if result then result:FireAllClients("Break",actor.character,victim,0) end
			local finish=fields.outcome == "Parry" and fields.sourceRecoveryEnd or fields.reactionEnd
			npcPose(victim,Animations.Poses.GuardBreak,math.max(0,(finish or now+0.70)-now))
		end
	end
end

function Integration.Start(service)
	if started then return end
	started=true
	local watched=setmetatable({},{__mode="k"})
	local function watch(model)
		if not model:IsA("Model") or watched[model] then return end
		local humanoid=model:FindFirstChildOfClass("Humanoid")
		if not humanoid or not model:FindFirstChild("HumanoidRootPart") then return end
		if not service.RegisterCharacter(model) then return end
		watched[model]=true
		local set=npcSet(model)
		if set then task.spawn(Animations.preload,set) end
		-- These targets support repeated combat testing without a legacy knock/revive loop.
		humanoid.MaxHealth=10000
		humanoid.Health=10000
		humanoid.HealthChanged:Connect(function(health)
			if model.Parent and health > 0 and health < 9000 then humanoid.Health=10000 end
		end)
	end
	for _,model in CollectionService:GetTagged("TrainingDummy") do watch(model) end
	CollectionService:GetInstanceAddedSignal("TrainingDummy"):Connect(watch)
	workspace.DescendantAdded:Connect(function(instance)
		if instance:IsA("Humanoid") then
			task.defer(function()
				local model=instance.Parent
				if model and model:IsA("Model") and string.find(model:GetFullName(),"AdminShowcases",1,true) then watch(model) end
			end)
		end
	end)
	local elapsed=0
	RunService.Heartbeat:Connect(function(dt)
		elapsed+=dt
		if elapsed < 0.05 then return end
		elapsed=0
		local now=workspace:GetServerTimeNow()
		local models={}
		for _,player in Players:GetPlayers() do if player.Character then models[player.Character]=player end end
		for model in watched do if model.Parent then models[model]=false end end
		for model,player in models do
			local state=service.GetState(model)
			if not state then continue end
			if not player and npcGuards[model] ~= Core.guarding(state,now) then
				npcGuards[model]=Core.guarding(state,now)
				local set=npcSet(model)
				if set then
					if npcGuards[model] then Animations.hold(set,Animations.Poses.Block)
					else Animations.stop(set:get(Animations.Poses.Block)) end
				end
			end
			attribute(model,"CombatDefenseUntil",state.defenseUntil)
			attribute(model,"CombatOffenseUntil",state.offenseUntil)
			attribute(model,"CombatChaseUntil",state.chase and state.chase.expires or 0)
			local fighter=Fighters.get(model)
			if fighter then
				fighter.posture=100-state.posture
				fighter.blocking=Core.guarding(state,now)
				fighter.broken=now < state.breakUntil
				fighter.stunEnd=state.forcedUntil
				fighter.actionEnd=state.offenseUntil
				fighter.combo=state.sequence
				fighter.juggleUntil=state.air and state.air.expires or 0
			end
			if player then
				attribute(player,"PostureMax",100)
				attribute(player,"Posture",100-state.posture)
				attribute(player,"CombatState",Core.stateName(state,now))
				for name,ends in state.cooldowns do attribute(player,"CooldownEnd_"..name,ends) end
			end
		end
	end)
end

return Integration


