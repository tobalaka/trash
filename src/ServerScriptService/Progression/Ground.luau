--!strict
--[[
	Ground - where the walkable floor is, for placing spawns, NPCs and Sky Dump piles. Rays only
	hit the part-built ground (Workspace.Ground: terrain chunks, stairs, plinths) and the faction
	bases' floors, so the patchwork dome's shell overhead never counts as floor. Room checks are
	exact (a probe part and GetPartsInPart), because the dome's huge rotated panels have bounding
	boxes that cover whole plazas.
]]

local Ground = {}

local probe: Part? = nil

local function floorParams(): RaycastParams
	local include: { Instance } = {}
	local ground = workspace:FindFirstChild("Ground")
	if ground then
		table.insert(include, ground)
	end
	local world = workspace:FindFirstChild("World")
	local bases = world and world:FindFirstChild("Bases")
	if bases then
		table.insert(include, bases)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	return params
end

-- the floor under (x, z), searching down from `top`
function Ground.at(x: number, z: number, top: number?): Vector3?
	local from = top or 400
	local hit = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -(from + 400), 0), floorParams())
	return if hit then hit.Position else nil
end

-- true if a box of `size` standing on `position` touches nothing that collides (except `ignore`)
function Ground.clear(position: Vector3, size: Vector3, ignore: { Instance }?): boolean
	local p = probe
	if not p then
		local made = Instance.new("Part")
		made.Name = "GroundProbe"
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.Transparency = 1
		made.Parent = workspace
		probe = made
		p = made
	end
	local part = p :: Part
	part.Size = size
	part.CFrame = CFrame.new(position + Vector3.new(0, size.Y / 2 + 0.3, 0))
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { part }
	for _, i in ignore or {} do
		table.insert(exclude, i)
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return #workspace:GetPartsInPart(part, params) == 0
end

return Ground
