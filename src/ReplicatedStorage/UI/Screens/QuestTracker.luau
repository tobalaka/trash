--!strict
--[[
	QuestTracker - the quests pinned on screen (Track in the Journal), left of the ability column.
	Each shows its title in the quest line's colour and the step the player is on, with
	progress. With nothing pinned it shows the first running main quest so a new player always
	knows what to do next. Clicking it opens the Journal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Profile = require(UI:WaitForChild("Profile"))
local Journal = require(script.Parent:WaitForChild("Journal"))

local Quests = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Quests"))

local C, F = Theme.Color, Theme.Font

local QuestTracker = {}

local WIDTH = 300
local MAX_SHOWN = 3

function QuestTracker.build(root: Instance, open: () -> ()): any
	local holder = Kit.new("TextButton", {
		Name = "QuestTracker",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -160, 0, 330),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	}, { Kit.list("Y", 8, Enum.HorizontalAlignment.Right) })
	Kit.hudText("QUESTS  [J]", F.HeaderBold, 13, C.Gold, {
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 0,
		Parent = holder,
	})

	local function render(snap: any)
		for _, c in holder:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local active = if snap and snap.quests then snap.quests.active else {}
		local shown = {}
		for _, line in Quests.LINE_ORDER do
			for _, q in Quests.list do
				local state = active[q.id]
				if q.line == line and state and state.tracked and #shown < MAX_SHOWN then
					table.insert(shown, q)
				end
			end
		end
		if #shown == 0 then
			for _, q in Quests.list do
				if active[q.id] and q.kind == "Main" then
					table.insert(shown, q)
					break
				end
			end
		end
		holder.Visible = #shown > 0
		for i, q in shown do
			local color = (Theme.LineColor :: any)[q.line] or C.Gold
			local entry = Kit.new("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = i,
				Parent = holder,
			}, { Kit.list("Y", 1, Enum.HorizontalAlignment.Right) })
			Kit.hudText(q.title, F.Title, 16, color, {
				Size = UDim2.new(1, 0, 0, 20),
				TextXAlignment = Enum.TextXAlignment.Right,
				LayoutOrder = 1,
				Parent = entry,
			})
			Kit.hudText(Journal.stepText(q, active[q.id]), F.Body, 15, C.Text, {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				LayoutOrder = 2,
				Parent = entry,
			})
		end
	end

	Profile.observe(render)
	holder.Activated:Connect(open)
	return { frame = holder }
end

return QuestTracker
