--!strict
--[[
	AirQuality - the Heap's smog meter and the Sky Dump clock, under the top info line. Reads
	Workspace attributes the server sets (Pollution, AirState, DumpNext, DumpSite, DumpEnds,
	DumpScore_<faction>, DumpWinner; TRASH-Progression Pollution and SkyDumps).
	  meter   0-100 smog, coloured Clear / Hazy / Smog (Theme.Air), with the high and low marks
	  line    "Next Sky Dump 4:12" / "SKY DUMP INCOMING: Rust Gulch" / "Rust Gulch 2:40 · Menders 3
	          Scrappers 1" / "Scrappers claimed Rust Gulch"
	Everyone on the server shares the same air: sorting and purifying clean it, stripping and
	smelting dirty it.
	  turf    the Turf War (TRASH-Progression TurfWar): "TURF WAR on Hill Hall in 0:42", then the
	          time left and each side's control and people in the ring, over a two-colour bar
	          (TurfState, TurfEnds, TurfC, TurfR, TurfInC, TurfInR)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UI = script.Parent.Parent
local Theme = require(UI:WaitForChild("Theme"))
local Kit = require(UI:WaitForChild("Kit"))
local Icons = require(UI:WaitForChild("Icons"))
local State = require(UI:WaitForChild("State"))

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Environment = require(Shared:WaitForChild("Config"):WaitForChild("Environment"))
local Factions = require(Shared:WaitForChild("Config"):WaitForChild("Factions"))

local C, F = Theme.Color, Theme.Font

local AirQuality = {}

local WIDTH = 330
local BAR_W = 170
local TICK = 0.25
local PREVIEW_POLLUTION = 58

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function airColor(state: string): Color3
	return (Theme.Air :: any)[state] or Theme.Air.Hazy
end

function AirQuality.build(root: Instance): any
	local holder = Kit.new("Frame", {
		Name = "AirQuality",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(WIDTH, 82),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Parent = holder,
	}, { Kit.list("X", 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	local leaf = Icons.make("leaf", 18, Theme.Air.Clear, C.Ink)
	leaf.LayoutOrder = 1
	leaf.Parent = row
	Kit.hudText("AIR", F.HeaderBold, 14, C.Text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
		LayoutOrder = 2,
		Parent = row,
	})
	local track = Kit.new("Frame", {
		Size = UDim2.fromOffset(BAR_W, 10),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		LayoutOrder = 3,
		Parent = row,
	}, { Kit.corner(2), Kit.stroke(C.GoldDark, 1) })
	local fill = Kit.new("Frame", {
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = Theme.Air.Hazy,
		Parent = track,
	}, { Kit.corner(2) })
	-- the high and low marks
	for _, mark in { Environment.POLLUTION_LOW, Environment.POLLUTION_HIGH } do
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(mark / Environment.POLLUTION_MAX, 0.5),
			Size = UDim2.new(0, 2, 1, 6),
			BackgroundColor3 = C.Text,
			BackgroundTransparency = 0.3,
			ZIndex = 2,
			Parent = track,
		})
	end
	local stateLabel = Kit.hudText("", F.BodyBold, 16, C.Text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 4,
		Parent = row,
	})
	local dump = Kit.hudText("", F.Body, 15, C.TextDim, {
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = holder,
	})

	-- the Turf War line and its two-colour control bar (Menders from the left, Scrappers from the right)
	local turf = Kit.hudText("", F.HeaderBold, 15, C.Yellow, {
		Position = UDim2.fromOffset(0, 44),
		Size = UDim2.new(1, 0, 0, 18),
		Visible = false,
		Parent = holder,
	})
	local turfTrack = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(BAR_W + 80, 8),
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = holder,
	}, { Kit.corner(2), Kit.stroke(C.GoldDark, 1) })
	local turfC = Kit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Factions.INFO.Menders.color, Parent = turfTrack }, { Kit.corner(2) })
	local turfR = Kit.new("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Factions.INFO.Scrappers.color,
		Parent = turfTrack,
	}, { Kit.corner(2) })

	local function attr(name: string): any
		return if State.live then workspace:GetAttribute(name) else nil
	end

	local function refreshTurf()
		local state = attr("TurfState")
		local ends = attr("TurfEnds")
		local now = if State.live then workspace:GetServerTimeNow() else 0
		turf.Visible = typeof(state) == "string"
		turfTrack.Visible = state == "Open"
		if state == "Warning" and typeof(ends) == "number" then
			turf.Text = "TURF WAR on Hill Hall in " .. clock(ends - now)
		elseif state == "Open" then
			local c, r = attr("TurfC"), attr("TurfR")
			local ic, ir = attr("TurfInC"), attr("TurfInR")
			c = if typeof(c) == "number" then c else 0
			r = if typeof(r) == "number" then r else 0
			turf.Text = string.format("TURF WAR  %s  ·  Menders %d (%d)  ·  Scrappers %d (%d)", if typeof(ends) == "number" then clock(ends - now) else "", c, if typeof(ic) == "number" then ic else 0, r, if typeof(ir) == "number" then ir else 0)
			turfC.Size = UDim2.fromScale(math.clamp(c / 200, 0, 0.5), 1)
			turfR.Size = UDim2.fromScale(math.clamp(r / 200, 0, 0.5), 1)
		end
	end

	local function refreshAir()
		local p = attr("Pollution")
		local value = if typeof(p) == "number" then p else PREVIEW_POLLUTION
		local state = attr("AirState")
		if typeof(state) ~= "string" then
			state = if value >= Environment.POLLUTION_HIGH then "Smog" elseif value <= Environment.POLLUTION_LOW then "Clear" else "Hazy"
		end
		local color = airColor(state :: string)
		Kit.tween(fill, Theme.Tween.Med, { Size = UDim2.fromScale(math.clamp(value / Environment.POLLUTION_MAX, 0, 1), 1), BackgroundColor3 = color })
		stateLabel.Text = string.format("%s  %d", state, math.floor(value + 0.5))
		stateLabel.TextColor3 = color
		for _, d in leaf:GetDescendants() do
			if d:IsA("Frame") and d.BackgroundTransparency < 0.3 then
				d.BackgroundColor3 = color
			end
		end
	end

	local function refreshDump()
		if not State.live then
			dump.Text = "Next Sky Dump  4:12"
			return
		end
		local now = workspace:GetServerTimeNow()
		local ends = attr("DumpEnds")
		local site = attr("DumpSite")
		local winner = attr("DumpWinner")
		local nextAt = attr("DumpNext")
		if typeof(ends) == "number" and ends > now then
			local scores = {}
			for _, f in Factions.LIST do
				local s = attr("DumpScore_" .. f)
				table.insert(scores, string.format("%s %d", f, if typeof(s) == "number" then s else 0))
			end
			dump.Text = string.format("SKY DUMP: %s  %s  ·  %s", tostring(site), clock(ends - now), table.concat(scores, "  "))
			dump.TextColor3 = C.Yellow
		elseif typeof(site) == "string" and winner == nil and typeof(nextAt) == "number" and nextAt <= now then
			dump.Text = "SKY DUMP INCOMING: " .. site
			dump.TextColor3 = C.Rust
		elseif typeof(winner) == "string" and typeof(nextAt) == "number" then
			-- the winners keep their salvage bonus until the next dump
			local info = Factions.INFO[winner]
			dump.Text = string.format("%s claimed %s  ·  next dump %s", winner, tostring(site), clock(nextAt - now))
			dump.TextColor3 = if info then info.color else C.TextDim
		elseif typeof(nextAt) == "number" then
			dump.Text = "Next Sky Dump  " .. clock(nextAt - now)
			dump.TextColor3 = C.TextDim
		else
			dump.Text = ""
		end
	end

	refreshAir()
	refreshDump()
	if State.live then
		workspace:GetAttributeChangedSignal("Pollution"):Connect(refreshAir)
		workspace:GetAttributeChangedSignal("AirState"):Connect(refreshAir)
		task.spawn(function()
			while holder.Parent do
				refreshDump()
				refreshTurf()
				task.wait(TICK)
			end
		end)
	end
	return { frame = holder }
end

return AirQuality
