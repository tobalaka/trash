--!strict
--[[
	NpcRenderer - draws the named NPCs on this client (vault: NPCs). The server only places an
	invisible anchor per NPC (tag NpcAnchor, attributes NpcId and Ground); here each one gets a
	body from the Townsfolk look kit with its fixed outfit (Shared/Data/Npcs style), animated by
	Townsfolk Animate: idle sway, gestures, looking at you, shopkeepers waving. Same seed on every
	client, so everyone sees the same person.

	Quest markers float over NPCs with something for you: "!" a new quest, "?" ready to turn in or
	waiting to talk, "…" waiting for an item. They come from the ProfileSync snapshot's `marks`.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Npcs = require(Shared:WaitForChild("Data"):WaitForChild("Npcs"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Townsfolk = ReplicatedStorage:WaitForChild("Client"):WaitForChild("Townsfolk")
local Looks = require(Townsfolk:WaitForChild("Looks"))
local Animate = require(Townsfolk:WaitForChild("Animate"))

local TAG = "NpcAnchor"
local BUILD_RADIUS = 220
local DROP_RADIUS = 260
local POSE_RADIUS = 140 -- posed every frame inside this, every 4th frame beyond
local FAR_EVERY = 4
local MARK_OFFSET = 5.4
local MARK_COLORS = {
	["!"] = Color3.fromRGB(255, 214, 58),
	["?"] = Color3.fromRGB(120, 222, 44),
	["…"] = Color3.fromRGB(176, 176, 166),
}

type Entry = {
	anchor: BasePart,
	npc: Npcs.Npc,
	body: Looks.Body?,
	state: Animate.State?,
	position: Vector3,
	yaw: number,
	last: number,
	mark: BillboardGui?,
}

local NpcRenderer = {}

local entries: { [BasePart]: Entry } = {}
local marks: { [string]: string } = {}
local folder: Folder? = nil

local function bodyFolder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "NpcBodies"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function refreshMark(e: Entry)
	local symbol = marks[e.npc.id]
	if not symbol then
		if e.mark then
			e.mark:Destroy()
			e.mark = nil
		end
		return
	end
	local gui = e.mark
	if not gui then
		local g = Instance.new("BillboardGui")
		g.Name = "QuestMark"
		g.Size = UDim2.fromOffset(60, 60)
		g.StudsOffset = Vector3.new(0, MARK_OFFSET, 0)
		g.AlwaysOnTop = true
		g.MaxDistance = 120
		g.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Name = "Symbol"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.FontFace = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)
		label.TextScaled = true
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = Color3.fromRGB(12, 13, 14)
		label.Parent = g
		g.Adornee = e.anchor
		g.Parent = e.anchor
		e.mark = g
		gui = g
	end
	local label = (gui :: BillboardGui):FindFirstChild("Symbol") :: TextLabel
	label.Text = symbol
	label.TextColor3 = MARK_COLORS[symbol] or MARK_COLORS["!"]
end

local function add(anchor: Instance)
	if not anchor:IsA("BasePart") or entries[anchor] then
		return
	end
	local npc = Npcs.byId[anchor:GetAttribute("NpcId") :: string]
	if not npc then
		return
	end
	local ground = anchor:GetAttribute("Ground")
	local look = anchor.CFrame.LookVector
	local e: Entry = {
		anchor = anchor,
		npc = npc,
		body = nil,
		state = nil,
		position = Vector3.new(anchor.Position.X, if typeof(ground) == "number" then ground else anchor.Position.Y - anchor.Size.Y / 2, anchor.Position.Z),
		yaw = math.atan2(-look.X, -look.Z),
		last = 0,
		mark = nil,
	}
	entries[anchor] = e
	refreshMark(e)
end

local function remove(anchor: Instance)
	local e = entries[anchor :: BasePart]
	if not e then
		return
	end
	if e.body then
		e.body.model:Destroy()
	end
	if e.mark then
		e.mark:Destroy()
	end
	entries[anchor :: BasePart] = nil
end

local function build(e: Entry)
	local style = e.npc.style or {}
	local body = Looks.build(e.npc.seed, e.npc.role :: any, style.kid == true, nil, style.scale or 1, style :: any)
	body.model.Name = e.npc.id
	e.body = body
	e.state = Animate.newState(e.yaw)
end

function NpcRenderer.start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
	for _, a in CollectionService:GetTagged(TAG) do
		add(a)
	end
	Remotes.get("ProfileSync").OnClientEvent:Connect(function(snap)
		if typeof(snap) == "table" and typeof(snap.marks) == "table" then
			marks = snap.marks
			for _, e in entries do
				refreshMark(e)
			end
		end
	end)

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local frame = 0
	RunService.RenderStepped:Connect(function()
		frame += 1
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local eye = camera.CFrame.Position
		local player = Players.LocalPlayer
		local head = player.Character and player.Character:FindFirstChild("Head")
		local focus = if head and head:IsA("BasePart") then head.Position else nil
		local t = workspace:GetServerTimeNow()
		table.clear(parts)
		table.clear(cframes)
		for _, e in entries do
			local d = (e.position - eye).Magnitude
			if not e.body and d < BUILD_RADIUS then
				build(e)
				local first: { BasePart }, firstFrames: { CFrame } = {}, {}
				Animate.step(e.body :: Looks.Body, e.state :: Animate.State, {
					position = e.position,
					yaw = e.yaw,
					moving = false,
					speed = 0,
					travelled = 0,
					role = e.npc.role :: any,
					seed = e.npc.seed,
					member = 1,
					members = 1,
				}, t, 0, focus, first, firstFrames)
				for i, p in first do
					p.CFrame = firstFrames[i]
				end
				;(e.body :: Looks.Body).model.Parent = bodyFolder()
				e.last = t
			elseif e.body and d > DROP_RADIUS then
				e.body.model:Destroy()
				e.body = nil
				e.state = nil
			end
			local body, state = e.body, e.state
			if body and state and (d < POSE_RADIUS or frame % FAR_EVERY == 0) then
				Animate.step(body, state, {
					position = e.position,
					yaw = e.yaw,
					moving = false,
					speed = 0,
					travelled = 0,
					role = e.npc.role :: any,
					seed = e.npc.seed,
					member = 1,
					members = 1,
				}, t, math.clamp(t - e.last, 0, 0.5), focus, parts, cframes)
				e.last = t
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end)
end

return NpcRenderer
