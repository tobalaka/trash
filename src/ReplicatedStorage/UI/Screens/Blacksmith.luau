--!strict
--[[
	Blacksmith - your faction's smith (server: Blacksmith, Gacha), opened from their dialogue with
	OpenWindow("Blacksmith", { npc, kind, faction }).
	  left    the wielded Relic in 3D, its name and rarity, and the upgrade ladder: Tier 1 Z,
	          2 X, 3 C, 4 M1 Mastery, each with the move it unlocks
	  right   what the next tier needs (snapshot `smith`: level, rank, Scrap, Residue and the
	          salvaged materials, each ticked when met) and the Upgrade button; below it the
	          roll: Relic Spins held, the Dollar price, and how close the pity guarantees are
	Upgrade sends StationAction(npc, "Upgrade"); Roll sends RollRelic. The server decides both.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Models = require(UI:WaitForChild("Models"))
local State = require(UI:WaitForChild("State"))
local Profile = require(UI:WaitForChild("Profile"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Economy = require(Shared:WaitForChild("Config"):WaitForChild("Economy"))
local Relics = require(Shared:WaitForChild("Data"):WaitForChild("Relics"))

local C, F, A = Theme.Color, Theme.Font, Theme.Attr

local Blacksmith = {}

local STAGE = 220

local function rarityColor(r: string?): Color3
	return (Theme.Rarity :: any)[r or ""] or Theme.Rarity.Common
end

local function line(parent: Instance, order: number, text: string, font: Font, size: number, color: Color3): any
	return Kit.label(text, font, size, color, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
		Parent = parent,
	})
end

export type BlacksmithContext = { upgrade: (npcId: string) -> (), roll: () -> () }

function Blacksmith.build(root: Instance, ctx: BlacksmithContext): any
	local win = Kit.window({ name = "Blacksmith", title = "Blacksmith", size = Vector2.new(1000, 640) })
	win.frame.Parent = root
	local left = Kit.new("Frame", {
		Size = UDim2.new(0, 420, 1, 0),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.5,
		Parent = win.body,
	}, { Kit.stroke(C.SlateLine, 1, 0.55), Kit.list("Y", 8, Enum.HorizontalAlignment.Center), Kit.pad(14, 14, 14, 14) })
	local right = Kit.new("ScrollingFrame", {
		Position = UDim2.fromOffset(440, 0),
		Size = UDim2.new(1, -440, 1, 0),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.7,
		Parent = win.body,
	}, { Kit.stroke(C.SlateLine, 1, 0.55), Kit.list("Y", 8), Kit.pad(14, 18, 14, 18) })

	local npcId: string? = nil

	local function clear(frame: Instance)
		for _, c in frame:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end

	local function renderLeft(snap: any)
		clear(left)
		local owned = snap and snap.relic
		local j = owned and Relics.get(owned.id)
		if not j then
			line(left, 1, "You have no Relic yet. Join a faction at the Gate Market: your first roll is free.", F.Serif, 18, C.TextDim)
			return
		end
		local rc = rarityColor(owned.rarity)
		local stage = Kit.new("Frame", {
			Size = UDim2.fromOffset(STAGE, STAGE),
			BackgroundColor3 = C.Night,
			ClipsDescendants = true,
			LayoutOrder = 1,
			Parent = left,
		}, { Kit.corner(4), Kit.stroke(rc, 2.5) })
		Kit.sunburst(stage, UDim2.fromScale(0.5, 0.5), 10, STAGE, rc, 0.25)
		local vp = Kit.viewport(Models.make(j.model), { size = UDim2.fromScale(1, 1), yaw = 30, pitch = 14 })
		vp.Parent = stage
		Kit.spin(vp, function()
			return win.frame.Visible
		end)
		Kit.label(j.name, F.Title, 24, C.Text, { Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 2, Parent = left })
		Kit.label(string.format("%s  ·  Tier %d / %d", owned.rarity, owned.tier, Economy.MAX_TIER), F.BodyBold, 16, rc, { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 3, Parent = left })
		-- the ladder
		local ladder = Kit.new("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 4,
			Parent = left,
		}, { Kit.list("Y", 4) })
		for t, def in Economy.TIERS do
			local reached = owned.tier >= t
			local ability = j.abilities[def.unlocks]
			local name = if ability then ability.name else "5th M1 hit, grab armour, full strength"
			local r = Kit.new("Frame", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundColor3 = if reached then C.GoldDark else C.Ink,
				BackgroundTransparency = if reached then 0.35 else 0.4,
				LayoutOrder = t,
				Parent = ladder,
			}, { Kit.corner(3) })
			Kit.label(string.format("T%d  %s", t, def.unlocks), F.Header, 14, if reached then C.GoldHi else C.TextMute, {
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.fromOffset(120, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = r,
			})
			Kit.label(name, F.BodyBold, 15, if reached then C.Text else C.TextDim, {
				Position = UDim2.fromOffset(130, 0),
				Size = UDim2.new(1, -140, 1, 0),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = r,
			})
		end
	end

	local function renderRight(snap: any)
		clear(right)
		local smith = snap and snap.smith
		local owned = snap and snap.relic
		Kit.label("NEXT UPGRADE", F.HeaderBold, 14, C.Gold, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Parent = right })
		if not owned then
			line(right, 2, "Nothing to upgrade yet.", F.Serif, 18, C.TextDim)
		elseif not smith then
			line(right, 2, "Fully upgraded. This Relic is as strong as it gets.", F.Serif, 18, C.GoldHi)
		else
			local j = Relics.get(owned.id)
			local ability = j and j.abilities[smith.unlocks]
			line(right, 2, string.format("Tier %d unlocks %s%s", smith.tier, smith.unlocks, if ability then ": " .. ability.name else ""), F.Title, 20, C.Text)
			if ability then
				line(right, 3, ability.desc, F.BodyItalic, 16, C.TextDim)
			end
			for i, req in smith.reqs do
				local text = if req.label:match("^Level") or req.label:match("^Rank") then req.label else string.format("%s  %d / %d", req.label, req.have, req.need)
				line(right, 3 + i, (if req.ok then "✓  " else "✗  ") .. text, F.BodyBold, 17, if req.ok then C.Lime else C.Rust)
			end
			local holder = Kit.gloss({
				text = if smith.ready then "UPGRADE" else "NOT READY",
				color = if smith.ready then C.Rust else C.Slate,
				size = UDim2.fromOffset(260, 52),
				textSize = 26,
				layoutOrder = 30,
				parent = right,
				onClick = function()
					if smith.ready and npcId then
						ctx.upgrade(npcId)
					end
				end,
			})
			holder.Name = "Upgrade"
			line(right, 31, "Scrap comes from salvage and sorting. Materials come from junk piles, the Wastezone and beasts.", F.BodyItalic, 15, C.TextDim)
		end
		Kit.divider(C.Gold, { LayoutOrder = 40, Parent = right })
		Kit.label("ROLL A RELIC", F.HeaderBold, 14, C.Gold, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 41, Parent = right })
		local spins = Profile.count("SpinToken")
		local pity = snap and snap.pity or { rare = 0, legendary = 0 }
		line(right, 42, string.format("Relic Spins: %d  ·  or $%d a roll", spins, Economy.SPIN_DOLLARS), F.BodyBold, 17, C.Text)
		line(right, 43, string.format("Rare or better within %d rolls  ·  Legendary within %d", math.max(1, Economy.PITY_RARE - pity.rare), math.max(1, Economy.PITY_LEGENDARY - pity.legendary)), F.Body, 16, C.TextDim)
		local can = snap ~= nil and snap.faction ~= nil and (spins > 0 or State.number(A.Dollars, 0) >= Economy.SPIN_DOLLARS)
		Kit.gloss({
			text = if spins > 0 then "ROLL (SPIN)" else string.format("ROLL  $%d", Economy.SPIN_DOLLARS),
			color = if can then Theme.Rarity.Epic else C.Slate,
			size = UDim2.fromOffset(260, 52),
			textSize = 24,
			layoutOrder = 44,
			parent = right,
			onClick = function()
				if can then
					ctx.roll()
				end
			end,
		})
	end

	local function render()
		local snap = Profile.data
		renderLeft(snap)
		renderRight(snap)
	end

	Profile.observe(function()
		if win.frame.Visible then
			render()
		end
	end)
	State.observe(A.Dollars, function()
		if win.frame.Visible then
			renderRight(Profile.data)
		end
	end)

	local api = { window = win }
	function api.show(data: any)
		npcId = data and data.npc
		render()
	end
	return api
end

return Blacksmith
