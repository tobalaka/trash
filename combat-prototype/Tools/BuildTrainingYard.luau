-- Run once in Studio Edit mode for the isolated combat test copy.
assert(workspace:GetAttribute("JoblessCombatTest"),"Build only in the combat test copy")
local yard=workspace:FindFirstChild("CombatTrainingYard")
if not yard then yard=Instance.new("Folder");yard.Name="CombatTrainingYard";yard.Parent=workspace end
for _,name in {"Targets","ResetPosts"} do
 if not yard:FindFirstChild(name) then local folder=Instance.new("Folder");folder.Name=name;folder.Parent=yard end
end
assert(#yard.Targets:GetChildren() == 0,"Training yard already built")
local function part(name,size,position,color,parent,collide)
 local p=Instance.new("Part")
 p.Name=name;p.Size=size;p.Position=position;p.Anchored=true
 p.Material=Enum.Material.Sandstone;p.Color=color
 p.CanCollide=collide ~= false;p.CanTouch=false;p.TopSurface=Enum.SurfaceType.Smooth;p.BottomSurface=Enum.SurfaceType.Smooth
 p.Parent=parent or yard
 return p
end
local sand=Color3.fromRGB(170,131,83)
local dark=Color3.fromRGB(66,50,37)
part("PracticeFloor",Vector3.new(136,.5,88),Vector3.new(1380,9.25,1800),sand)
part("BackBorder",Vector3.new(136,.7,1),Vector3.new(1380,9.85,1756.5),dark)
part("LeftBorder",Vector3.new(1,.7,88),Vector3.new(1312.5,9.85,1800),dark)
part("RightBorder",Vector3.new(1,.7,88),Vector3.new(1447.5,9.85,1800),dark)
local arrival=part("Arrival",Vector3.new(10,.06,8),Vector3.new(1380,9.55,1832),Color3.fromRGB(81,143,140),yard,false)
local sign=part("Instructions",Vector3.new(124,9,.6),Vector3.new(1380,16,1762),dark)
local surface=Instance.new("SurfaceGui")
surface.Face=Enum.NormalId.Back;surface.CanvasSize=Vector2.new(1488,108);surface.Parent=sign
local title=Instance.new("TextLabel")
title.Size=UDim2.fromScale(1,1);title.BackgroundTransparency=1
title.Text="DESERT COMBAT YARD\nPARRY  |  BLOCK  |  IDLE  |  ATTACK\nM1 attack · F parry/block · Q dodge · M2 feint/cancel · Ctrl+M1 uppercut · Space chase · R critical/slam\nUse each station's reset post. Travel / reset button restores your health at the entrance."
title.TextColor3=Color3.fromRGB(255,232,187);title.TextSize=23;title.Font=Enum.Font.GothamMedium;title.Parent=surface
local modes={
 {name="ParryDummy",mode="Parry",title="AUTO PARRY",detail="Attacks trigger timed parries. Test recoil and pressure.",color=Color3.fromRGB(83,163,204)},
 {name="BlockDummy",mode="Block",title="HELD BLOCK",detail="No parries. Build posture, break guard, or attack behind.",color=Color3.fromRGB(218,176,75)},
 {name="IdleDummy",mode="Idle",title="IDLE / AERIAL",detail="No actions. Test M1, uppercut, chase, and downslam.",color=Color3.fromRGB(114,178,111)},
 {name="AttackDummy",mode="Attack",title="ATTACKER",detail="Enter this lane. Parries, blocks, dodges, and trades.",color=Color3.fromRGB(199,92,80)},
}
for i,info in modes do
 local x=1332+(i-1)*32
 part(info.mode.."Lane",Vector3.new(27,.04,54),Vector3.new(x,9.52,1797),info.color,yard,false)
 local description=Instance.new("HumanoidDescription")
 local model=game.Players:CreateHumanoidModelFromDescriptionAsync(description,Enum.HumanoidRigType.R6)
 description:Destroy()
 model.Name=info.name
 local root=model.HumanoidRootPart
 model.PrimaryPart=root
 local home=CFrame.lookAt(Vector3.new(x,12.5,1784),Vector3.new(x,12.5,1800))
 model:PivotTo(home)
 model:SetAttribute("TrainingMode",info.mode)
 model:SetAttribute("TrainingHome",home)
 model:SetAttribute("TrainingLastResult","")
 local humanoid=model.Humanoid
 humanoid.MaxHealth=10000;humanoid.Health=10000;humanoid.WalkSpeed=8
 humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
 local body=model:FindFirstChildOfClass("BodyColors")
 if body then body.TorsoColor3=info.color;body.LeftArmColor3=Color3.fromRGB(204,181,143);body.RightArmColor3=body.LeftArmColor3;body.HeadColor3=body.LeftArmColor3;body.LeftLegColor3=dark;body.RightLegColor3=dark end
 local gui=Instance.new("BillboardGui")
 gui.Name="TrainingLabel";gui.Size=UDim2.fromOffset(260,112);gui.StudsOffset=Vector3.new(0,3.5,0);gui.AlwaysOnTop=true;gui.MaxDistance=75;gui.Parent=model.Head
 local name=Instance.new("TextLabel")
 name.Name="Mode";name.Size=UDim2.new(1,0,0,27);name.BackgroundColor3=dark;name.BackgroundTransparency=.15;name.Text=info.title;name.TextColor3=info.color;name.TextSize=19;name.Font=Enum.Font.GothamBold;name.Parent=gui
 local detail=Instance.new("TextLabel")
 detail.Name="Instructions";detail.Position=UDim2.fromOffset(0,27);detail.Size=UDim2.new(1,0,0,38);detail.BackgroundTransparency=1;detail.TextWrapped=true;detail.Text=info.detail;detail.TextColor3=Color3.fromRGB(255,242,211);detail.TextSize=13;detail.Font=Enum.Font.GothamMedium;detail.Parent=gui
 local stats=detail:Clone()
 stats.Name="Stats";stats.Position=UDim2.fromOffset(0,66);stats.Size=UDim2.new(1,0,0,42);stats.Text="HP 10000 / 10000 | Posture 0 / 100";stats.Parent=gui
 model.Parent=yard.Targets
 game:GetService("CollectionService"):AddTag(model,"TrainingDummy")
 local post=part(info.name,Vector3.new(1,3,1),Vector3.new(x+10,11,1809),dark,yard.ResetPosts)
 local prompt=Instance.new("ProximityPrompt")
 prompt.Name="Reset";prompt.ActionText="Reset dummy";prompt.ObjectText=info.title;prompt.HoldDuration=.25;prompt.MaxActivationDistance=8;prompt.RequiresLineOfSight=false;prompt.Parent=post
 task.wait()
end
workspace.CurrentCamera.CFrame=CFrame.lookAt(Vector3.new(1392,44,1858),Vector3.new(1380,13,1790))
return {yard=yard:GetFullName(),targets=#yard.Targets:GetChildren(),arrival=tostring(arrival.Position)}
