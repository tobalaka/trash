--!strict
--[[
	TurfWar - the Server Raid (vault: Turf-War; GDD Faction Systems: "Server Raids (such as King
	of the Hill) trigger every 45-60 minutes, rewarding victorious factions with high-tier
	endgame materials and Stat-Reset Pills"). Tuning in Config.Turf.

	A warning goes out, then a ring opens on Hill Hall in the middle of Patchwork Town. Every TICK,
	the side with more living, standing members inside the ring gains control (RATE per extra
	member, up to MAX_RATE); an even ring holds still. First to CAPTURE wins, or whoever leads
	when DURATION runs out; a tie wins nothing.
	  - Everyone who stood in the ring took part. Winners who took part get WIN (with a chance at a
	    Stat Reset Pill); the other side's part-takers get JOIN.
	  - The winning side gets the salvage buff a Sky Dump gives (Salvage.setBuff).
	  - Workspace attributes drive the HUD bar: TurfState (Warning | Open), TurfC / TurfR
	    (control 0-100), TurfInC / TurfInR (members in the ring), TurfEnds (server time).
	  - WorldEvent TurfWarning / TurfOpen / TurfOver for the banners.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local T = require(Config:WaitForChild("Turf"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Salvage = require(script.Parent:WaitForChild("Salvage"))
local Regions = require(script.Parent:WaitForChild("Regions"))
local Ground = require(script.Parent:WaitForChild("Ground"))
local Titles = require(script.Parent:WaitForChild("Titles"))
local Bus = require(script.Parent:WaitForChild("Bus"))

local RING_NAME = "TurfRing"
local RING_HEIGHT = 0.4
local RING_COLOR = Color3.fromRGB(255, 214, 58)

local TurfWar = {}

local running = false
local rng = Random.new()

local function now(): number
	return workspace:GetServerTimeNow()
end

local function setState(state: string?, ends: number?)
	workspace:SetAttribute("TurfState", state)
	workspace:SetAttribute("TurfEnds", ends)
	if not state then
		for _, a in { "TurfC", "TurfR", "TurfInC", "TurfInR" } do
			workspace:SetAttribute(a, nil)
		end
	end
end

local function makeRing(center: Vector3): Model
	local model = Instance.new("Model")
	model.Name = RING_NAME
	local disc = Instance.new("Part")
	disc.Name = "Disc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(RING_HEIGHT, T.RADIUS * 2, T.RADIUS * 2)
	disc.CFrame = CFrame.new(center + Vector3.new(0, RING_HEIGHT / 2 + 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disc.Color = RING_COLOR
	disc.Material = Enum.Material.ForceField
	disc.Transparency = 0.35
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Parent = model
	-- a beacon so the hill can be found from across town
	local beam = Instance.new("Part")
	beam.Name = "Beacon"
	beam.Size = Vector3.new(3, 160, 3)
	beam.CFrame = CFrame.new(center + Vector3.new(0, 80, 0))
	beam.Color = RING_COLOR
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.55
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.CastShadow = false
	beam.Parent = model
	model.Parent = workspace
	return model
end

-- the faction members standing in the ring right now (alive and not knocked)
local function inside(center: Vector3): { [string]: { Player } }
	local out: { [string]: { Player } } = { Menders = {}, Scrappers = {} }
	for _, player in Players:GetPlayers() do
		local p = Profiles.get(player)
		local root = Regions.rootOf(player)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if p and p.faction and out[p.faction] and root and humanoid and humanoid.Health > 0 and not player:GetAttribute("Knocked") then
			local offset = root.Position - center
			if Vector2.new(offset.X, offset.Z).Magnitude <= T.RADIUS and math.abs(offset.Y) <= T.HEIGHT then
				table.insert(out[p.faction], player)
			end
		end
	end
	return out
end

local function pay(winner: string?, took: { [Player]: string })
	for player, faction in took do
		if player.Parent and Profiles.get(player) then
			if faction == winner then
				local w = T.WIN
				local items: { [string]: number } = {}
				if rng:NextNumber() < w.pillChance then
					items.ResetPill = 1
				end
				Progress.grant(player, { exp = w.exp, scrap = w.scrap, residue = w.residue, standing = w.standing, items = items }, "Turf War won!")
				Titles.bump(player, "turfWins", 1)
				Bus.emit(player, "Turf", { won = true })
			else
				local j = T.JOIN
				Progress.grant(player, { exp = j.exp, scrap = j.scrap, residue = j.residue, standing = j.standing }, "Turf War")
				Bus.emit(player, "Turf", { won = false })
			end
		end
	end
end

-- Runs one Turf War from the warning to the payout. Yields until it is over.
function TurfWar.run()
	if running then
		return
	end
	running = true
	local ground = Ground.at(T.CENTER.X, T.CENTER.Z)
	local center = Vector3.new(T.CENTER.X, if ground then ground.Y else T.CENTER.Y, T.CENTER.Z)
	local remotes = Remotes.get("WorldEvent")
	setState("Warning", now() + T.WARNING)
	remotes:FireAllClients("TurfWarning", { seconds = T.WARNING, place = "Hill Hall" })
	task.wait(T.WARNING)

	local ring = makeRing(center)
	local control = { Menders = 0, Scrappers = 0 }
	local took: { [Player]: string } = {}
	local ends = now() + T.DURATION
	setState("Open", ends)
	remotes:FireAllClients("TurfOpen", { place = "Hill Hall", seconds = T.DURATION })
	local winner: string? = nil
	while now() < ends do
		task.wait(T.TICK)
		local members = inside(center)
		for faction, list in members do
			for _, player in list do
				took[player] = faction
			end
		end
		local c, r = #members.Menders, #members.Scrappers
		if c ~= r then
			local leader = if c > r then "Menders" else "Scrappers"
			control[leader] = math.min(T.CAPTURE, control[leader] + math.min(T.MAX_RATE, math.abs(c - r) * T.RATE))
		end
		workspace:SetAttribute("TurfC", math.floor(control.Menders))
		workspace:SetAttribute("TurfR", math.floor(control.Scrappers))
		workspace:SetAttribute("TurfInC", c)
		workspace:SetAttribute("TurfInR", r)
		if control.Menders >= T.CAPTURE or control.Scrappers >= T.CAPTURE then
			winner = if control.Menders >= T.CAPTURE then "Menders" else "Scrappers"
			break
		end
	end
	if not winner and control.Menders ~= control.Scrappers then
		winner = if control.Menders > control.Scrappers then "Menders" else "Scrappers"
	end
	ring:Destroy()
	setState(nil, nil)
	remotes:FireAllClients("TurfOver", { winner = winner, place = "Hill Hall", menders = math.floor(control.Menders), scrappers = math.floor(control.Scrappers) })
	if winner then
		Salvage.setBuff(winner, T.BUFF_TIME)
	end
	pay(winner, took)
	running = false
end

function TurfWar.isRunning(): boolean
	return running
end

function TurfWar.start()
	setState(nil, nil)
	task.spawn(function()
		task.wait(T.FIRST)
		while true do
			if #Players:GetPlayers() > 0 then
				local ok, err = pcall(TurfWar.run)
				if not ok then
					running = false
					setState(nil, nil)
					warn("[TurfWar] " .. tostring(err))
				end
			end
			task.wait(rng:NextInteger(T.INTERVAL[1], T.INTERVAL[2]))
		end
	end)
end

return TurfWar
