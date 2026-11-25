--!strict
-- Admin controls share the game's window, fonts, borders and modal input handling.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = script.Parent.Parent
local Kit = require(UI.Kit)
local Theme = require(UI.Theme)
local Items = require(ReplicatedStorage.Shared.Data.Items)
local Relics = require(ReplicatedStorage.Shared.Data.Relics)
local Showcase = require(script.Parent.Showcase)
local C, F = Theme.Color, Theme.Font
local Admin = {}
local WIDTH, HEIGHT = 1040, 720
local LEFT_WIDTH, GAP, ROW_HEIGHT = 216, 20, 42
local DEFAULT_LEVELS, DEFAULT_RESOURCES = "5", "10000"

function Admin.build(root: Instance, ctx: any): any
	local player = Players.LocalPlayer
	local win = Kit.window({ name = "Admin", title = "Admin · The Heap", size = Vector2.new(WIDTH, HEIGHT), style = "dark" })
	win.frame.Parent = root
	local selected = player.UserId
	local state: any = nil
	local armed: number? = nil
	local activeTab = "Player"
	local status = Kit.label("Select a player. /admin opens this panel.", F.BodyItalic, 16, C.TextDim, {
		Name = "Status", Position = UDim2.new(0, 0, 1, -46), Size = UDim2.new(1, 0, 0, 46),
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = win.body,
	})
	local function say(text: string, success: boolean?)
		status.Text = text
		status.TextColor3 = if success == false then C.Magenta else C.GoldHi
	end
	local function label(parent: Instance, text: string, y: number)
		return Kit.label(text, F.HeaderBold, 16, C.GoldHi, {
			Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Left, Parent = parent,
		})
	end
	local function button(parent: Instance, text: string, x: number, y: number, width: number, callback: () -> ())
		local b = Kit.outlineButton(text, Vector2.new(width, ROW_HEIGHT), {
			Position = UDim2.fromOffset(x, y), TextSize = 16, Parent = parent,
		})
		b.Activated:Connect(callback)
		return b
	end
	local function input(parent: Instance, placeholder: string, value: string, x: number, y: number, width: number): TextBox
		return Kit.new("TextBox", {
			Name = placeholder, PlaceholderText = placeholder, Text = value,
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, ROW_HEIGHT),
			BackgroundColor3 = C.Ink, BackgroundTransparency = 0.1,
			FontFace = F.HeaderBold, TextSize = 17, TextColor3 = C.Text,
			PlaceholderColor3 = C.TextDim, ClearTextOnFocus = false, Parent = parent,
		}, { Kit.stroke(C.SlateLine, 1), Kit.pad(0, 10, 0, 10) })
	end
	local function scroll(parent: Instance, x: number, y: number, width: UDim, bottom: number): ScrollingFrame
		return Kit.new("ScrollingFrame", {
			Position = UDim2.fromOffset(x, y), Size = UDim2.new(width.Scale, width.Offset, 1, -bottom),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
			ScrollBarImageColor3 = C.Gold, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Parent = parent,
		}, { Kit.list("Y", 8), Kit.pad(2, 4, 4, 2) })
	end
	local function send(action: string, data: any?)
		local request = data or {}
		request.action, request.target = action, selected
		say("Working…")
		ctx.act(request)
	end
	local left = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0, LEFT_WIDTH, 1, -58), Parent = win.body })
	label(left, "TARGET PLAYER", 0)
	local roster = scroll(left, 0, 36, UDim.new(1, 0), 148)
	button(left, "Hide UI · H restores", 0, 0, LEFT_WIDTH, function() ctx.cinematic() end).Position = UDim2.new(0, 0, 1, -96)
	button(left, "Refresh players", 0, 0, LEFT_WIDTH, function() send("Refresh") end).Position = UDim2.new(0, 0, 1, -44)
	local right = Kit.new("Frame", {
		BackgroundTransparency = 1, Position = UDim2.fromOffset(LEFT_WIDTH + GAP, 0),
		Size = UDim2.new(1, -(LEFT_WIDTH + GAP), 1, -58), Parent = win.body,
	})
	local pages, tabs = {}, {}
	for index, name in { "Player", "Travel", "Access", "Showcase" } do
		pages[name] = Kit.new("Frame", {
			Name = name, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 52),
			Size = UDim2.new(1, 0, 1, -52), Visible = name == activeTab, Parent = right,
		})
		tabs[name] = button(right, string.upper(name), (index - 1) * 175, 0, 164, function()
			activeTab = name
			for key, page in pages do page.Visible = key == name end
		end)
	end
	local controls = pages.Player
	local showcase = Showcase.build(pages.Showcase, ctx)
	label(controls, "PROGRESSION", 0)
	local levels = input(controls, "Levels to add", DEFAULT_LEVELS, 0, 30, 140)
	button(controls, "Give levels", 152, 30, 190, function() send("AddLevels", { amount = tonumber(levels.Text) }) end)
	button(controls, "Max level", 354, 30, 218, function() send("MaxLevel") end)
	label(controls, "INVENTORY · QUANTITY PER ITEM", 88)
	local quantity = input(controls, "Quantity", "100", 0, 118, 140)
	button(controls, "Give ALL items", 152, 118, 230, function() send("AllItems", { amount = tonumber(quantity.Text) }) end)
	button(controls, "Restore health / meters", 394, 118, 306, function() send("Restore") end)
	local resources = input(controls, "Resource amount", DEFAULT_RESOURCES, 0, 174, 140)
	button(controls, "Give Dollars + Scrap + Anima", 152, 174, 360, function() send("Resources", { amount = tonumber(resources.Text) }) end)
	button(controls, "Max Relic", 524, 174, 176, function() send("MaxRelic") end)
	label(controls, "GIVE ONE ITEM OR EQUIP ANY RELIC", 232)
	local search = input(controls, "Search items and Relics", "", 0, 262, 700)
	local catalogue = scroll(controls, 0, 318, UDim.new(1, 0), 318)
	local function renderCatalogue()
		for _, child in catalogue:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
		local query = string.lower(search.Text)
		for _, relic in Relics.list do
			if string.find(string.lower(relic.name), query, 1, true) then
				local b = button(catalogue, "Equip Relic: " .. relic.name, 0, 0, 670,
					function() send("EquipRelic", { relic = relic.id }) end)
				b.TextColor3 = C.GoldHi
			end
		end
		for _, item in Items.list do
			if string.find(string.lower(item.name .. " " .. item.id), query, 1, true) then
				button(catalogue, "Give: " .. item.name, 0, 0, 670,
					function() send("GiveItem", { item = item.id, amount = tonumber(quantity.Text) }) end)
			end
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(renderCatalogue)
	renderCatalogue()
	local travel = pages.Travel
	label(travel, "PLAYER TELEPORTS", 0)
	button(travel, "Go to selected player", 0, 30, 340, function() send("GoToPlayer") end)
	button(travel, "Bring selected player", 352, 30, 348, function() send("BringPlayer") end)
	label(travel, "EXACT COORDINATES · SELECTED PLAYER", 88)
	local x = input(travel, "X", "", 0, 118, 164)
	local y = input(travel, "Y", "", 176, 118, 164)
	local z = input(travel, "Z", "", 352, 118, 164)
	button(travel, "Teleport", 528, 118, 172, function()
		local px, py, pz = tonumber(x.Text), tonumber(y.Text), tonumber(z.Text)
		if not px or not py or not pz then say("Enter all three coordinates.", false); return end
		send("TeleportPosition", { position = Vector3.new(px, py, pz) })
	end)
	button(travel, "Pick a point in the world", 0, 174, 700, function()
		armed = selected
		ctx.close()
		ctx.toast("Click a world surface to teleport the selected player. Esc cancels.", C.GoldHi)
	end)
	label(travel, "REGIONS · TELEPORT SELECTED PLAYER", 232)
	local regions = scroll(travel, 0, 266, UDim.new(1, 0), 266)
	local management = pages.Access
	label(management, "OWNER · ADMIN ACCESS", 0)
	local info = Kit.label("", F.BodyItalic, 18, C.TextDim, {
		Position = UDim2.fromOffset(0, 36), Size = UDim2.fromOffset(700, 88), TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = management,
	})
	local identity = input(management, "Roblox username or User ID", "", 0, 142, 700)
	local grant = button(management, "Grant full admin", 0, 200, 340, function() send("GrantAdmin", { identity = identity.Text:match("^%s*(.-)%s*$") }) end)
	local revoke = button(management, "Revoke admin", 352, 200, 348, function() send("RevokeAdmin", { identity = identity.Text:match("^%s*(.-)%s*$") }) end)
	button(management, "Use selected player", 0, 258, 700, function() identity.Text = tostring(selected) end)
	local function renderState()
		if not state then return end
		for _, child in roster:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
		for _, other in state.players do
			local text = (if other.id == selected then "› " else "") .. other.name
			if other.id == player.UserId then text ..= " (you)" end
			if other.admin then text ..= " · ADMIN" end
			local b = button(roster, text, 0, 0, LEFT_WIDTH - 14, function() selected = other.id; renderState() end)
			b.TextSize = 14
			b.TextColor3 = if other.id == selected then C.GoldHi else C.Text
		end
		for _, child in regions:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
		for _, name in state.destinations do button(regions, name, 0, 0, 670, function() send("TeleportRegion", { region = name }) end) end
		info.Text = if state.owner then "Grant or revoke the same gameplay controls for friends. Access is saved across sessions. Only you can manage grants. Friends open the panel with /admin."
			else "You have the same gameplay controls as the owner. Only the owner can grant or revoke admin access."
		if state.studio then info.Text ..= " With Studio API access off, changes last for this test only." end
		identity.Visible, grant.Visible, revoke.Visible = state.owner, state.owner, state.owner
		levels.PlaceholderText = "1–" .. tostring(state.maxLevel) .. " levels"
	end
	UserInputService.InputBegan:Connect(function(key, processed)
		if not armed then return end
		if key.KeyCode == Enum.KeyCode.Escape then armed = nil; ctx.open(); return end
		if processed or key.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		local mouse = player:GetMouse()
		if not mouse.Target then return end
		local targetId = armed
		armed = nil
		ctx.open()
		ctx.act({ action = "TeleportPosition", target = targetId,
			position = mouse.Hit.Position + Vector3.new(0, state.teleportHeight, 0) })
	end)
	local api: any = { window = win }
	function api.receive(payload: any)
		if payload.state then showcase.receive(payload.state.showcase) end
		if payload.state then state = payload.state; renderState() end
		if payload.message then say(payload.message, payload.success) end
	end
	return api
end

return Admin
