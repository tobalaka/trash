--!strict
-- Hitbox - the server's own hit checks: boxes in front of the attacker's server-side position.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Combat"))
local Fighters = require(script.Parent:WaitForChild("Fighters"))

type Fighter = Fighters.Fighter

local Hitbox = {}

-- True when solid world geometry stands between the two bodies (a wall between the fighters).
-- Only collidable parts count, and every fighter and the local effect folders are ignored.
local function walled(attacker: Fighter, target: Fighter): boolean
	local ignore: { Instance } = {}
	for model in Fighters.all() do
		table.insert(ignore, model)
	end
	for _, name in { "RelicFxLocal", "CombatFxLocal" } do
		local fx = workspace:FindFirstChild(name)
		if fx then
			table.insert(ignore, fx)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	params.IgnoreWater = true
	local from = attacker.root.Position
	return workspace:Raycast(from, target.root.Position - from, params) ~= nil
end

local function query(attacker: Fighter, width: number, height: number, depth: number, drop: number): { Fighter }
	local cf = attacker.root.CFrame * CFrame.new(0, -drop, -depth / 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker.model }
	local hits: { Fighter } = {}
	local seen: { [Model]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(cf, Vector3.new(width, height, depth), params) do
		local target = Fighters.fromPart(part)
		if target and not seen[target.model] then
			seen[target.model] = true
			if not walled(attacker, target) then
				table.insert(hits, target)
			end
		end
	end
	return hits
end

-- Everyone in the attack box. `drop` lowers the box (the aerial slam hits below the attacker).
function Hitbox.front(attacker: Fighter, drop: number?): { Fighter }
	return query(attacker, Config.HITBOX_WIDTH, Config.HITBOX_HEIGHT, Config.HITBOX_RANGE + Config.HITBOX_LAG_PAD, drop or 0)
end

-- The closest fighter within `range` in front of the attacker that `accept` allows.
function Hitbox.nearest(attacker: Fighter, range: number, accept: (Fighter) -> boolean): Fighter?
	local best: Fighter? = nil
	local bestDistance = math.huge
	for _, target in query(attacker, 4, Config.HITBOX_HEIGHT, range + Config.HITBOX_LAG_PAD, 0) do
		local distance = (target.root.Position - attacker.root.Position).Magnitude
		if distance < bestDistance and accept(target) then
			best, bestDistance = target, distance
		end
	end
	return best
end

return Hitbox
