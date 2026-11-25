local RunService = game:GetService("RunService")

local Player = game.Players.LocalPlayer
local Character = Player.Character
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Torso = Character:WaitForChild("Torso")

-- Original C0 Reference

local RootJointOriginalC0 = HumanoidRootPart.RootJoint.C0
local NeckOriginalC0 = Torso.Neck.C0
local RightHipOriginalC0 = Torso["Right Hip"].C0
local LeftHipOriginalC0 = Torso["Left Hip"].C0

local PlayersTable = {}

--Customizable Settings

local RangeOfMotion = 45
local RangeOfMotionTorso = 90 - RangeOfMotion
local RangeOfMotionXZ = RangeOfMotion / 140
local LerpSpeed = 0.005
-- lean (2026-10-25, EXPED CharacterTilt + a visible lean): forward with speed, into turns
local LeanForward = math.rad(8) -- at LeanSpeed studs/s forward
local LeanSpeed = 40
local LeanTurn = math.rad(10) -- most roll into a turn
local LeanTurnRate = 0.003 -- radians of roll per (rad/s of turning x studs/s of speed): ~9 deg turning 2 rad/s at a run

--Main Code

RangeOfMotion = math.rad(RangeOfMotion)
RangeOfMotionTorso = math.rad(RangeOfMotionTorso)

function Calculate(dt, HumanoidRootPart, Humanoid, Torso)
	local DirectionOfMovement = HumanoidRootPart.CFrame:VectorToObjectSpace(HumanoidRootPart.AssemblyLinearVelocity)
	DirectionOfMovement =
		Vector3.new(DirectionOfMovement.X / Humanoid.WalkSpeed, 0, DirectionOfMovement.Z / Humanoid.WalkSpeed)

	local XResult = (DirectionOfMovement.X * (RangeOfMotion - (math.abs(DirectionOfMovement.Z) * (RangeOfMotion / 2))))
	local XResultTorso = (
		DirectionOfMovement.X * (RangeOfMotionTorso - (math.abs(DirectionOfMovement.Z) * (RangeOfMotionTorso / 2)))
	)
	local XResultXZ = (
		DirectionOfMovement.X * (RangeOfMotionXZ - (math.abs(DirectionOfMovement.Z) * (RangeOfMotionXZ / 2)))
	)

	if DirectionOfMovement.Z > 0.1 then
		XResult *= -1
		XResultTorso *= -1
		XResultXZ *= -1
	end

	local RightHipResult = RightHipOriginalC0
		* CFrame.new(-XResultXZ, 0, -math.abs(XResultXZ) + math.abs(-XResultXZ))
		* CFrame.Angles(0, -XResult, 0)
	local LeftHipResult = LeftHipOriginalC0
		* CFrame.new(-XResultXZ, 0, -math.abs(-XResultXZ) + math.abs(-XResultXZ))
		* CFrame.Angles(0, -XResult, 0)
	-- RootJoint frame: X+ leans forward, Y+ rolls to the left (into a left turn), Z is the strafe twist
	local Local = HumanoidRootPart.CFrame:VectorToObjectSpace(HumanoidRootPart.AssemblyLinearVelocity)
	local Flat = Vector3.new(Local.X, 0, Local.Z).Magnitude
	local Lean = math.clamp(-Local.Z / LeanSpeed, -0.4, 1) * LeanForward
	local Roll = math.clamp(HumanoidRootPart.AssemblyAngularVelocity.Y * Flat * LeanTurnRate, -LeanTurn, LeanTurn)
	local RootJointResult = RootJointOriginalC0 * CFrame.Angles(Lean, Roll, -XResultTorso)
	local NeckResult = NeckOriginalC0 * CFrame.Angles(0, 0, XResultTorso)

	local LerpTime = 1 - LerpSpeed ^ dt

	Torso["Right Hip"].C0 = Torso["Right Hip"].C0:Lerp(RightHipResult, LerpTime)
	Torso["Left Hip"].C0 = Torso["Left Hip"].C0:Lerp(LeftHipResult, LerpTime)
	HumanoidRootPart.RootJoint.C0 = HumanoidRootPart.RootJoint.C0:Lerp(RootJointResult, LerpTime)
	Torso.Neck.C0 = Torso.Neck.C0:Lerp(NeckResult, LerpTime)
end

RunService.RenderStepped:Connect(function(dt)
	for _, Player in game.Players:GetPlayers() do
		if Player.Character == nil then
			continue
		end
		if table.find(PlayersTable, Player) then
			continue
		end
		table.insert(PlayersTable, Player)
	end

	for i, Player in pairs(PlayersTable) do
		if Player == nil then
			table.remove(PlayersTable, i)
			continue
		end

		if game.Players:FindFirstChild(Player.Name) == nil then
			table.remove(PlayersTable, i)
			continue
		end

		if Player.Character == nil then
			table.remove(PlayersTable, i)
			continue
		end

		local HumanoidRootPart = Player.Character:FindFirstChild("HumanoidRootPart")
		local Humanoid = Player.Character:FindFirstChild("Humanoid")
		local Torso = Player.Character:FindFirstChild("Torso")

		if HumanoidRootPart == nil or Humanoid == nil or Torso == nil then
			continue
		end

		Calculate(dt, HumanoidRootPart, Humanoid, Torso)
	end
end)
