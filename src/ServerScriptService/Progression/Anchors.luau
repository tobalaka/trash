--!strict
--[[
	Anchors - where each NPC stands (set by NpcService), so stations and quests can check that a
	player is really next to the NPC they claim to be talking to.
]]

local Regions = require(script.Parent:WaitForChild("Regions"))

local Anchors = {}

local anchors: { [string]: BasePart } = {}

function Anchors.set(id: string, part: BasePart)
	anchors[id] = part
end

function Anchors.get(id: string): BasePart?
	return anchors[id]
end

-- true if the player's character is within `distance` studs of NPC `id`
function Anchors.near(player: Player, id: string, distance: number): boolean
	local anchor = anchors[id]
	local root = Regions.rootOf(player)
	if not anchor or not root then
		return false
	end
	return (root.Position - anchor.Position).Magnitude <= distance
end

return Anchors
