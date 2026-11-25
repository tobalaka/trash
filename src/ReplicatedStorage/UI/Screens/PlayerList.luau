--!strict
--[[
	PlayerList - Deepwoken's top-right list (deep.webp): each player's name in bold serif with a
	soft outline, and under it a small faction square and their rank. Replaces the core list.
	Faction and rank come from the "Faction" and "Rank" player attributes (server-set).
]]

local Players = game:GetService("Players")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local State = require(UI:WaitForChild("State"))
local MockData = require(UI:WaitForChild("MockData"))

local C, F, A = Theme.Color, Theme.Font, Theme.Attr

local PlayerList = {}

local ROW_H = 36

local function factionColor(faction: string): Color3
	return (C :: any)[faction] or C.Neutral
end

local function row(parent: Instance, order: number, name: string, faction: string, title: string, isLocal: boolean): any
	local r = Kit.new("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
	local n = Kit.label(name, F.Title, 15, if isLocal then C.GoldHi else C.Text, {
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = r,
	})
	Kit.stroke(C.Ink, 1.5, 0.4).Parent = n
	local sub = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 15),
		BackgroundTransparency = 1,
		Parent = r,
	}, { Kit.list("X", 5, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center) })
	Kit.new("Frame", {
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = factionColor(faction),
		LayoutOrder = 1,
		Parent = sub,
	}, { Kit.stroke(C.Ink, 1, 0.2) })
	local t = Kit.label(faction .. "  ·  " .. title, F.Body, 14, C.TextDim, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 15),
		LayoutOrder = 2,
		Parent = sub,
	})
	Kit.stroke(C.Ink, 1, 0.55).Parent = t
	return r
end

function PlayerList.build(root: Instance): any
	local list = Kit.new("Frame", {
		Name = "PlayerList",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		Size = UDim2.fromOffset(260, 600),
		BackgroundTransparency = 1,
		Parent = root,
	}, { Kit.list("Y", 0) })

	local function rebuild()
		for _, c in list:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		if not State.live then
			for i, p in MockData.players do
				row(list, i, p.name, p.faction, p.title, i == 1)
			end
			return
		end
		local players = Players:GetPlayers()
		table.sort(players, function(a, b)
			return a.DisplayName:lower() < b.DisplayName:lower()
		end)
		for i, p in players do
			local faction = p:GetAttribute(A.Faction)
			local rank = p:GetAttribute(A.Rank)
			row(
				list,
				i,
				p.DisplayName,
				if typeof(faction) == "string" then faction else "Unaligned",
				if typeof(rank) == "string" then rank else "Drifter",
				p == Players.LocalPlayer
			)
		end
	end

	if State.live then
		local pending = false
		local function queue()
			if pending then
				return
			end
			pending = true
			-- a short delay so a leaving player is gone from GetPlayers()
			task.delay(0.1, function()
				pending = false
				rebuild()
			end)
		end
		local function watch(p: Player)
			p:GetAttributeChangedSignal(A.Faction):Connect(queue)
			p:GetAttributeChangedSignal(A.Rank):Connect(queue)
			queue()
		end
		for _, p in Players:GetPlayers() do
			watch(p)
		end
		Players.PlayerAdded:Connect(watch)
		Players.PlayerRemoving:Connect(queue)
	end
	rebuild()
	return { frame = list }
end

return PlayerList
