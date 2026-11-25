--!strict
--[[
	Nameplate - the tag over a player's head (vault: Titles, Bounties): their worn title, and
	"WANTED · $X" (or "BOUNTY · $X") when there is a price on them. Built on the server from
	player attributes other systems set, so everyone sees the same thing:
	  Title / TitleColor   Titles (the worn title)
	  Wanted               Bounties: the Dollars a claim would pay, nil when nothing
	  WantedLevel          Bounties: heat (Wanted at Factions.WANTED_HEAT or more)
	The Roblox name above the head stays as it is; this sits just above it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Factions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Factions"))

local GUI_NAME = "TrashNameplate"
local OFFSET = Vector3.new(0, 3.4, 0)
local MAX_DISTANCE = 120
local WANTED_COLOR = Color3.fromRGB(255, 120, 60)
local BOUNTY_COLOR = Color3.fromRGB(255, 214, 58)
local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold)

local Nameplate = {}

local function label(parent: Instance, name: string, order: number, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size + 4)
	l.FontFace = FONT
	l.TextSize = size
	l.TextStrokeTransparency = 0.35
	l.TextStrokeColor3 = Color3.fromRGB(12, 13, 14)
	l.LayoutOrder = order
	l.Text = ""
	l.Visible = false
	l.Parent = parent
	return l
end

function Nameplate.refresh(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = head:FindFirstChild(GUI_NAME) :: BillboardGui?
	if not gui then
		local made = Instance.new("BillboardGui")
		made.Name = GUI_NAME
		made.Size = UDim2.fromOffset(260, 52)
		made.StudsOffset = OFFSET
		made.MaxDistance = MAX_DISTANCE
		made.LightInfluence = 0
		made.AlwaysOnTop = false
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Parent = made
		label(made, "Wanted", 1, 18)
		label(made, "Title", 2, 17)
		made.Parent = head
		gui = made
	end
	local g = gui :: BillboardGui
	local title = g:FindFirstChild("Title") :: TextLabel
	local wanted = g:FindFirstChild("Wanted") :: TextLabel
	local t = player:GetAttribute("Title")
	local color = player:GetAttribute("TitleColor")
	title.Visible = typeof(t) == "string"
	title.Text = if typeof(t) == "string" then "« " .. t .. " »" else ""
	title.TextColor3 = if typeof(color) == "Color3" then color else Color3.new(1, 1, 1)
	local value = player:GetAttribute("Wanted")
	local level = player:GetAttribute("WantedLevel")
	local isWanted = typeof(level) == "number" and level >= Factions.WANTED_HEAT
	wanted.Visible = typeof(value) == "number"
	if typeof(value) == "number" then
		wanted.Text = string.format("%s · $%d", if isWanted then "WANTED" else "BOUNTY", value)
		wanted.TextColor3 = if isWanted then WANTED_COLOR else BOUNTY_COLOR
	end
	g.Enabled = title.Visible or wanted.Visible
end

function Nameplate.start()
	local function watch(player: Player)
		for _, attr in { "Title", "TitleColor", "Wanted", "WantedLevel" } do
			player:GetAttributeChangedSignal(attr):Connect(function()
				Nameplate.refresh(player)
			end)
		end
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Head", 10)
			Nameplate.refresh(player)
		end)
		if player.Character then
			task.spawn(Nameplate.refresh, player)
		end
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
end

return Nameplate
