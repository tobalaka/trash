--!strict
--[[
	Remotes - the movement and combat RemoteEvents (04-Architecture/Remotes). The server creates
	them under ReplicatedStorage.Remotes at start; clients wait for them.

	AttackRequest    C -> S  comboIndex: number, stamp: number
	AerialRequest    C -> S  stamp: number
	UppercutRequest  C -> S  stamp: number
	FeintRequest     C -> S
	GrabRequest      C -> S  direction: "Up" | "Down" | "Left" | "Right", stamp: number
	BlockStart       C -> S  stamp: number
	BlockEnd         C -> S
	DodgeRequest     C -> S  direction: "Forward" | "Backward" | "Left" | "Right" | "Air", stamp: number
	CritRequest      C -> S  stamp: number
	GripRequest      C -> S  target: Model (a knocked fighter)
	CarryRequest     C -> S  target: Model? (a knocked fighter to pick up; nil drops the one carried)
	GearState        C -> S  "Glide", on: boolean (the Tarp Glider opened or folded; Combat/MoveGear)
	CombatResult     S -> C  kind: string, attacker: Model?, target: Model?, detail: any

	`stamp` is the client's workspace:GetServerTimeNow() at the key press.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.NAMES = {
	"AttackRequest",
	"AerialRequest",
	"UppercutRequest",
	"FeintRequest",
	"GrabRequest",
	"BlockStart",
	"BlockEnd",
	"DodgeRequest",
	"CritRequest",
	"GripRequest",
	"CarryRequest",
	"GearState",
	"CombatResult",
}

local FOLDER = "Remotes"

function Remotes.init()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER
		folder.Parent = ReplicatedStorage
	end
	for _, name in Remotes.NAMES do
		if not (folder :: Instance):FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	return ReplicatedStorage:WaitForChild(FOLDER):WaitForChild(name) :: RemoteEvent
end

return Remotes
