--!strict
--[[
	WorldMap - the world map in the EXPED skin (2026-10-25): a real top-down picture of the built
	world (trash-art/tools/map_render.py from a straight-down ray scan of the place, the same square
	this module computes from MapRegionVolumes), region names in white, the faction emblems on the
	two bases, the Smog Spire marker, a compass and the player's arrow, in a dark silver-framed
	window. Re-scan and re-upload WORLD_MAP if MapGen rebuilds the world. North is -Z.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Icons = require(UI:WaitForChild("Icons"))
local Exped = require(UI:WaitForChild("Exped"))

-- the top-down render of the world for exactly this module's square (span = 1.1 x the larger side)
local WORLD_MAP = "rbxassetid://73299757692879"

local C, F = Theme.Color, Theme.Font

local WorldMap = {}

local CANVAS = 720
local MARGIN = 0.05

type Volume = { region: string, priority: number, cx: number, cz: number, sx: number, sz: number, round: boolean }

local function readVolumes(): { Volume }
	local folder = ReplicatedStorage:FindFirstChild("MapRegionVolumes")
	local out: { Volume } = {}
	if not folder then
		return out
	end
	for _, v in folder:GetChildren() do
		if v:IsA("BasePart") then
			local region = v:GetAttribute("Region")
			if typeof(region) == "string" then
				local round = v:GetAttribute("Shape") == "Cylinder"
				local r = v:GetAttribute("Radius")
				local sx = if round and typeof(r) == "number" then r * 2 else v.Size.X
				local sz = if round and typeof(r) == "number" then r * 2 else v.Size.Z
				table.insert(out, {
					region = region,
					priority = (v:GetAttribute("Priority") :: number?) or 0,
					cx = v.Position.X,
					cz = v.Position.Z,
					sx = sx,
					sz = sz,
					round = round,
				})
			end
		end
	end
	table.sort(out, function(a, b)
		return a.priority < b.priority
	end)
	return out
end

local function marker(parent: Instance, x: number, y: number, icon: string, label: string, size: number)
	Exped.icon(icon, size, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		ZIndex = 6,
		Parent = parent,
	})
	Exped.text(label, 14, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(x, 0, y, size * 0.55),
		Size = UDim2.fromOffset(200, 16),
		ZIndex = 6,
		Parent = parent,
	})
end

function WorldMap.build(root: Instance): any
	local win = Kit.window({ name = "Map", title = "The Heap", size = Vector2.new(CANVAS + 60, CANVAS + 100), style = "dark" })
	win.frame.Parent = root

	local canvas = Kit.new("Frame", {
		Name = "Canvas",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(CANVAS, CANVAS),
		BackgroundColor3 = Exped.Color.PanelDeep,
		ClipsDescendants = true,
		Parent = win.body,
	})
	Kit.new("ImageLabel", {
		Name = "World",
		Image = WORLD_MAP,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = canvas,
	})

	local volumes = readVolumes()
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, v in volumes do
		minX = math.min(minX, v.cx - v.sx / 2)
		maxX = math.max(maxX, v.cx + v.sx / 2)
		minZ = math.min(minZ, v.cz - v.sz / 2)
		maxZ = math.max(maxZ, v.cz + v.sz / 2)
	end
	if #volumes == 0 then
		minX, maxX, minZ, maxZ = -4000, 4000, -4000, 4000
	end
	local span = math.max(maxX - minX, maxZ - minZ) * (1 + MARGIN * 2)
	local midX, midZ = (minX + maxX) / 2, (minZ + maxZ) / 2
	local function toMap(x: number, z: number): (number, number)
		return 0.5 + (x - midX) / span, 0.5 + (z - midZ) / span
	end

	-- region label positions: the area-weighted centre of each region's volumes
	local centroids: { [string]: { x: number, z: number, w: number } } = {}
	for _, v in volumes do
		local area = v.sx * v.sz
		local c = centroids[v.region] or { x = 0, z = 0, w = 0 }
		c.x += v.cx * area
		c.z += v.cz * area
		c.w += area
		centroids[v.region] = c
	end
	-- markers first (bases, then points of interest), so region names can step around them
	local markers: { Vector2 } = {}
	for region, c in centroids do
		if region == "MendersBase" or region == "ScrappersBase" then
			local info = (Theme.Regions :: any)[region]
			local u, w = toMap(c.x / c.w, c.z / c.w)
			marker(canvas, u, w, if region == "MendersBase" then "Menders" else "Scrappers", if info then info.name else region, 30)
			table.insert(markers, Vector2.new(u, w))
		end
	end
	for _, poi in Theme.MapPOI do
		local x, z = poi.x, poi.z
		local node: Instance? = workspace
		for _, seg in poi.path do
			node = if node then node:FindFirstChild(seg) else nil
		end
		if node and node:IsA("Model") then
			local p = node:GetPivot().Position
			x, z = p.X, p.Z
		end
		local u, w = toMap(x, z)
		marker(canvas, u, w, "Posture", poi.name, 24)
		table.insert(markers, Vector2.new(u, w))
	end
	for region, c in centroids do
		if region ~= "MendersBase" and region ~= "ScrappersBase" then
			local info = (Theme.Regions :: any)[region]
			local u, w = toMap(c.x / c.w, c.z / c.w)
			-- the Outskirts square shares the dome's centre: its name goes in the band above the dome
			if region == "Town" then
				w -= 0.075
			end
			-- a name that would sit on a marker (and its caption) moves above it
			for _, m in markers do
				if math.abs(u - m.X) < 0.16 and w > m.Y - 0.05 and w < m.Y + 0.07 then
					w = m.Y - 0.06
				end
			end
			local l = Exped.text(string.upper(if info then info.name else region), if region == "Town" then 15 else 19, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(u, w),
				Size = UDim2.fromOffset(260, 24),
				ZIndex = 5,
				Parent = canvas,
			})
			Exped.metal(l)
		end
	end

	-- compass rose
	local compass = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(70, 70),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = canvas,
	})
	Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(44, 44),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = compass,
	}, { Kit.round(), Kit.stroke(Exped.Color.Silver, 1.5, 0.2) })
	for _, rot in { 0, 90 } do
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(2, 62),
			Rotation = rot,
			BackgroundColor3 = Exped.Color.Silver,
			ZIndex = 9,
			Parent = compass,
		})
	end
	Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 14),
		Rotation = 45,
		BackgroundColor3 = C.GoldDark,
		ZIndex = 9,
		Parent = compass,
	}, { Kit.stroke(C.Ink, 1) })
	Exped.text("N", 18, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(20, 20),
		ZIndex = 9,
		Parent = compass,
	})

	-- the player
	local arrow = Kit.new("Frame", {
		Name = "You",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = canvas,
	})
	local pulse = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1,
		ZIndex = 10,
		Parent = arrow,
	}, { Kit.round(), Kit.stroke(Exped.Color.Text, 2, 0.2) })
	local glyph = Icons.make("arrow", 26, Exped.Color.Text, C.Ink)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.ZIndex = 11
	glyph.Parent = arrow

	Kit.label("Surveyed by the Menders' cartographers. The Heap keeps moving.", F.BodyItalic, 15, Exped.Color.TextDim, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 20),
		TextTransparency = 0.25,
		Parent = win.body,
	})

	local function place(pos: Vector3, look: Vector3)
		local u, w = toMap(pos.X, pos.Z)
		arrow.Position = UDim2.fromScale(math.clamp(u, 0, 1), math.clamp(w, 0, 1))
		arrow.Rotation = math.deg(math.atan2(look.X, -look.Z))
	end

	if RunService:IsRunning() then
		local player = Players.LocalPlayer
		RunService.RenderStepped:Connect(function()
			if not win.frame.Visible then
				return
			end
			local cam = workspace.CurrentCamera
			local character = player and player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart")
			local pos = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else cam.Focus.Position
			place(pos, cam.CFrame.LookVector)
			local t = os.clock() % 1.4 / 1.4
			pulse.Size = UDim2.fromOffset(24 + t * 26, 24 + t * 26)
			local s = pulse:FindFirstChildOfClass("UIStroke")
			if s then
				s.Transparency = t
			end
		end)
	else
		-- preview: stand the arrow in the dome town, facing north-east
		place(Vector3.new(551, 0, -1332), Vector3.new(0.6, 0, -0.8))
	end
	return { window = win }
end

return WorldMap
