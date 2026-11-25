--!strict
--[[
	HQArt.Buildings - dresses MapGen's part-built houses and shops with the Town1 kit (gen_town.py).

	Per building (seeded from its position, so a re-run is identical) one window style A-D is picked, and the
	matching shutter style; a door style and an awning style are picked separately. Then:
	  * every 3.6 x 4.6 Pane gets a frame with glazing bars around it (the glass part stays, lit panes glow
	    through the bars);
	  * every Door, Shutter and Awning part becomes invisible but keeps colliding exactly as before, and the painted
	    mesh is laid over it (awnings stretch along X to the shop's width);
	The pieces are placed by their AUTHORED origin (template attribute "Origin"), never by their bounding box, so a
	door's handle or an awning's valance doesn't shift them.
	Everything new lives in an "HQ_Dress" folder in the building; remove() restores the hidden parts.

	  require(game.ServerStorage.HQArt.Buildings).apply(workspace.World) -> counts
]]

local Buildings = {}

local FOLDER = "HQ_Dress"
local STYLES = { "A", "B", "C", "D" }
local DOORS = { "DoorA", "DoorB", "DoorC" }
local AWNINGS = { "AwningA", "AwningB", "AwningC" }

local function kit(name: string): (MeshPart?, Vector3)
	local m = game.ServerStorage.HQArt.Kit:FindFirstChild(name) :: Model?
	if not m then
		return nil, Vector3.zero
	end
	local body = m:FindFirstChild("Body") :: MeshPart?
	return body, (m:GetAttribute("Origin") :: Vector3?) or Vector3.zero
end

local function near(a: Vector3, b: Vector3, tol: number): boolean
	return math.abs(a.X - b.X) <= tol and math.abs(a.Y - b.Y) <= tol and math.abs(a.Z - b.Z) <= tol
end

local function place(folder: Instance, tmpl: MeshPart, origin: Vector3, cf: CFrame, sx: number?, shadow: boolean?): MeshPart
	local p = tmpl:Clone()
	-- dressing never collides: the hidden originals keep the collision. Box fidelity keeps 6k+ copies out of the
	-- physics data; window frames sit flush in the wall, so they cast no shadow (review 1 cost pass)
	pcall(function()
		p.CollisionFidelity = Enum.CollisionFidelity.Box
	end)
	p.CastShadow = shadow ~= false
	if sx and sx ~= 1 then
		p.Size = Vector3.new(p.Size.X * sx, p.Size.Y, p.Size.Z)
		origin = Vector3.new(origin.X * sx, origin.Y, origin.Z)
	end
	p.CFrame = cf * CFrame.new(-origin)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = folder
	return p
end

local function hide(part: BasePart)
	if part:GetAttribute("HQHidden") == nil then
		part:SetAttribute("HQHidden", part.Transparency)
	end
	part.Transparency = 1
end

function Buildings.remove(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("Folder") and d.Name == FOLDER then
			d:Destroy()
		elseif d:IsA("BasePart") then
			local t = d:GetAttribute("HQHidden")
			if typeof(t) == "number" then
				d.Transparency = t
				d:SetAttribute("HQHidden", nil)
			end
		end
	end
end

local function dress(model: Model, rng: Random, counts: { [string]: number })
	local style = STYLES[rng:NextInteger(1, #STYLES)]
	local win, wo = kit("Window" .. style)
	local sh, so = kit("Shutter" .. style)
	local door, dO = kit(DOORS[rng:NextInteger(1, #DOORS)])
	local aw, ao = kit(AWNINGS[rng:NextInteger(1, #AWNINGS)])
	local folder: Folder? = nil
	local function f(): Folder
		if not folder then
			local x = Instance.new("Folder")
			x.Name = FOLDER
			x.Parent = model
			folder = x
		end
		return folder :: Folder
	end
	for _, p in model:GetDescendants() do -- a snapshot: the pieces added below are never visited
		if not p:IsA("BasePart") then
			continue
		end
		if p.Name == "Pane" and win and near(p.Size, Vector3.new(3.6, 4.6, 0.2), 0.05) then
			place(f(), win, wo, p.CFrame, nil, false)
			counts.windows += 1
		elseif p.Name == "Door" and door and near(p.Size, Vector3.new(5.8, 8.9, 0.3), 0.05) then
			hide(p)
			place(f(), door, dO, p.CFrame)
			counts.doors += 1
		elseif p.Name == "Shutter" and sh and near(p.Size, Vector3.new(1.8, 4.2, 0.2), 0.05) then
			hide(p)
			place(f(), sh, so, p.CFrame)
			counts.shutters += 1
		elseif p.Name == "Awning" and aw and math.abs(p.Size.Z - 5) < 0.1 then
			hide(p)
			local a = place(f(), aw, ao, p.CFrame, p.Size.X / 30)
			a.CanCollide = false
			counts.awnings += 1
		end
	end
end

function Buildings.apply(root: Instance): { [string]: number }
	Buildings.remove(root)
	local counts = { windows = 0, doors = 0, shutters = 0, awnings = 0, buildings = 0 }
	local list = {}
	for _, m in root:GetDescendants() do
		if m:IsA("Model") and (m.Name == "House" or m.Name == "Shop") then
			table.insert(list, m)
		end
	end
	for i, m in list do
		local p = m:GetPivot().Position
		dress(m, Random.new(math.floor(math.abs(p.X * 13 + p.Z * 7 + p.Y * 3)) % 2147483647 + 1), counts)
		counts.buildings += 1
		if i % 40 == 0 then
			task.wait()
		end
	end
	return counts
end

return Buildings
