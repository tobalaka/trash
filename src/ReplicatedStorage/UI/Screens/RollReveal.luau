--!strict
--[[
	RollReveal - the Relic roll (server: Gacha, RollResult). A full-screen reveal: the faction's
	pool flickers past, then the rolled Relic lands on a sunburst in its rarity colour, turning in
	3D, with its name, rarity, what it used to be and its playstyle.
	  first Relic   it is bound straight away              [Continue]
	  duplicate     it melts into Anima Residue            [Continue]
	  different     current and new side by side           [Keep New] [Keep Current] -> RollChoice
	A roll left undecided (the player rejoined) is shown again from the snapshot's `pending`.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Models = require(UI:WaitForChild("Models"))

local Relics = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Data"):WaitForChild("Relics"))

local C, F = Theme.Color, Theme.Font

local RollReveal = {}

local FLICKER_TIME = 1.6
local FLICKER_STEP = 0.09
local STAGE = 300
local SIDE = 210

local function rarityColor(r: string?): Color3
	return (Theme.Rarity :: any)[r or ""] or Theme.Rarity.Common
end

export type RollContext = { choose: (keepNew: boolean) -> () }

function RollReveal.build(root: Instance, ctx: RollContext): any
	local overlay = Kit.new("Frame", {
		Name = "RollReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.15,
		Visible = false,
		ZIndex = 200,
		Parent = root,
	})
	Kit.new("TextButton", { Name = "Modal", Size = UDim2.fromScale(1, 1), Modal = true, ZIndex = 200, Parent = overlay })
	local center = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(900, 640),
		BackgroundTransparency = 1,
		ZIndex = 201,
		Parent = overlay,
	})
	local banner = Kit.chunky("RELIC ROLL", 54, C.GoldHi, {
		Size = UDim2.new(1, 0, 0, 60),
		ZIndex = 205,
		Parent = center,
	})
	local content = Kit.new("Frame", {
		Position = UDim2.fromOffset(0, 70),
		Size = UDim2.new(1, 0, 1, -150),
		BackgroundTransparency = 1,
		ZIndex = 201,
		Parent = center,
	})
	local buttons = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		ZIndex = 205,
		Parent = center,
	}, { Kit.list("X", 24, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })

	local api: any = { frame = overlay }
	local token = 0

	local function clear()
		for _, c in content:GetChildren() do
			c:Destroy()
		end
		for _, c in buttons:GetChildren() do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
	end

	-- one Relic on a stage: sunburst, 3D model, name, rarity, origin line
	local function showcase(parent: Instance, j: any, rarity: string, size: number, x: number, caption: string?): any
		local rc = rarityColor(rarity)
		local holder = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(x, 0),
			Size = UDim2.fromOffset(size + 120, size + 150),
			BackgroundTransparency = 1,
			ZIndex = 202,
			Parent = parent,
		})
		if caption then
			Kit.label(string.upper(caption), F.HeaderBold, 15, C.TextDim, {
				Position = UDim2.fromOffset(0, -22),
				Size = UDim2.new(1, 0, 0, 18),
				ZIndex = 203,
				Parent = holder,
			})
		end
		local stage = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = C.Night,
			ClipsDescendants = true,
			ZIndex = 202,
			Parent = holder,
		}, { Kit.corner(6), Kit.stroke(rc, 3) })
		local burst = Kit.sunburst(stage, UDim2.fromScale(0.5, 0.5), 12, size, rc, 0.35)
		burst.ZIndex = 202
		local vp = Kit.viewport(Models.make(j.model), { size = UDim2.fromScale(1, 1), yaw = 30, pitch = 14 })
		vp.ZIndex = 203
		vp.Parent = stage
		Kit.spin(vp, function()
			return overlay.Visible
		end)
		if RunService:IsRunning() then
			local conn
			conn = RunService.RenderStepped:Connect(function(dt)
				if not burst.Parent then
					conn:Disconnect()
					return
				end
				burst.Rotation += dt * 12
			end)
		end
		Kit.chunky(j.name, 34, C.Text, {
			Position = UDim2.fromOffset(0, size + 8),
			Size = UDim2.new(1, 0, 0, 40),
			ZIndex = 203,
			Parent = holder,
		})
		local chip = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, size + 52),
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = rc,
			ZIndex = 203,
			Parent = holder,
		}, { Kit.corner(3), Kit.pad(0, 10, 0, 10), Kit.stroke(C.Ink, 1.5) })
		Kit.label(string.upper(rarity), F.Header, 13, C.Ink, {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 22),
			ZIndex = 204,
			Parent = chip,
		})
		Kit.label(j.origin .. "  ·  " .. j.style, F.BodyItalic, 16, C.TextDim, {
			Position = UDim2.fromOffset(0, size + 82),
			Size = UDim2.new(1, 0, 0, 44),
			TextWrapped = true,
			ZIndex = 203,
			Parent = holder,
		})
		Kit.pop(holder, 0.3)
		return holder
	end

	local function button(text: string, color: Color3, order: number, fn: () -> ())
		Kit.gloss({ text = text, color = color, size = UDim2.fromOffset(250, 56), textSize = 26, layoutOrder = order, parent = buttons, onClick = fn })
	end

	local function close()
		token += 1
		overlay.Visible = false
		clear()
	end
	api.close = close

	-- the choice between the current Relic and a new roll
	function api.choice(newId: string, newRarity: string, currentId: string?, currentRarity: string?)
		token += 1
		clear()
		overlay.Visible = true
		banner.Text = "KEEP OR SWAP?"
		local new = Relics.get(newId)
		local cur = Relics.get(currentId)
		if new then
			showcase(content, new, newRarity, SIDE, if cur then 0.72 else 0.5, "New roll")
		end
		if cur then
			showcase(content, cur, currentRarity or cur.rarity, SIDE, 0.28, "Wielding")
			Kit.chunky("VS", 40, C.Rust, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, SIDE / 2),
				Size = UDim2.fromOffset(80, 48),
				ZIndex = 204,
				Parent = content,
			})
		end
		button("KEEP NEW", C.Lime, 1, function()
			ctx.choose(true)
			close()
		end)
		button("KEEP CURRENT", C.Slate, 2, function()
			ctx.choose(false)
			close()
		end)
	end

	-- RollResult: { id, rarity, equipped?, duplicate?, residue?, pending?, current? }
	function api.reveal(result: any, currentRarity: string?)
		token += 1
		local mine = token
		clear()
		overlay.Visible = true
		local j = Relics.get(result.id)
		if not j then
			close()
			return
		end
		banner.Text = "ROLLING..."
		banner.TextColor3 = C.GoldHi
		-- flicker through the faction's pool
		local pool = Relics.byFaction[j.faction] or { j }
		local flicker = Kit.chunky("", 46, C.Text, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.35),
			Size = UDim2.new(1, 0, 0, 56),
			ZIndex = 204,
			Parent = content,
		})
		task.spawn(function()
			local t, i = 0, 0
			while t < FLICKER_TIME and token == mine and not Kit.reduceMotion do
				i = i % #pool + 1
				flicker.Text = pool[i].name
				flicker.TextColor3 = rarityColor(pool[i].rarity)
				task.wait(FLICKER_STEP)
				t += FLICKER_STEP
			end
			if token ~= mine then
				return
			end
			flicker:Destroy()
			if result.pending then
				api.choice(result.id, result.rarity, result.current, currentRarity)
				return
			end
			banner.Text = if result.rarity == "Legendary" then "LEGENDARY!" elseif result.duplicate then "DUPLICATE" else "NEW RELIC"
			banner.TextColor3 = rarityColor(result.rarity)
			Kit.pop(banner, 0.4)
			showcase(content, j, result.rarity, STAGE, 0.5, nil)
			if result.duplicate then
				Kit.chunky(string.format("+%d Anima Residue", result.residue or 0), 28, C.Anima, {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, 4),
					Size = UDim2.new(1, 0, 0, 34),
					ZIndex = 204,
					Parent = content,
				})
			end
			button("CONTINUE", C.Lime, 1, close)
		end)
	end

	return api
end

return RollReveal
