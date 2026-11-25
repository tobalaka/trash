--!strict
-- One generic recording dummy per admin; previews never execute damaging abilities.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage.Shared
local Settings = require(Shared.Config.Showcase)
local Combat = require(Shared.Config.Combat)
local Movement = require(Shared.Config.Movement)
local Animations = require(Shared.Config.Animations)
local Relics = require(Shared.Data.Relics)
local Anims = require(Shared.Anims)
local Fighters = require(game.ServerScriptService.Combat.Fighters)
local Ragdoll = require(game.ServerScriptService.Combat.Ragdoll)
local Knock = require(game.ServerScriptService.Combat.Knock)
local Ground = require(script.Parent.Ground)
local Gear = require(script.Parent.Gear)
local Theme = require(ReplicatedStorage.UI.Theme)

local Showcase = {}
local sessions: { [Player]: any } = {}
local folder: Folder? = nil
local catalog: { any }? = nil
local byId: { [string]: any } = {}
local order: { string } = {}
local FIELDS = {
	{ "M1", "nextAttackAt" }, { "Roll", "rollCooldownEnd" }, { "Parry", "parryCooldownEnd" },
	{ "Uppercut", "uppercutCooldownEnd" }, { "Aerial", "aerialCooldownEnd" },
	{ "Grab", "grabCooldownEnd" }, { "Feint", "feintCooldownEnd" },
	{ "Crit", "critCooldownEnd" }, { "Carry", "carryCooldownEnd" },
}

local function resolved(name: string, seen: any?): string?
	seen = seen or {}
	if seen[name] then return nil end
	seen[name] = true
	local def = Animations[name]
	if not def then return nil end
	if def.id and def.id ~= "" then return name end
	local source, clip = (def.studio or ""):match("^([^/]+)/(.+)$")
	local saves = ReplicatedStorage:FindFirstChild("StudioAnimSaves")
	local group = saves and source and saves:FindFirstChild(source)
	if group and group:FindFirstChild(clip) then return name end
	return if def.fallback then resolved(def.fallback, seen) else nil
end

function Showcase.catalog(): { any }
	if catalog then return catalog end
	local entries = {}
	for name in Animations do
		table.insert(entries, { id = name, name = name, group = "Player", available = resolved(name) ~= nil })
	end
	for _, relic in Relics.list do
		for _, key in Relics.KEYS do
			local move = relic.abilities[key]
			table.insert(entries, { id = relic.id .. "." .. key, name = relic.name .. " · " .. key .. " · " .. move.name,
				group = "Relic", available = true, relic = relic.id, key = key, cooldown = move.cooldown })
		end
	end
	table.sort(entries, function(a, b) return a.group .. a.name < b.group .. b.name end)
	for _, entry in entries do
		byId[entry.id] = entry
		if entry.available then table.insert(order, entry.id) end
	end
	catalog = entries
	return entries
end

function Showcase.info(player: Player): any
	local session = sessions[player]
	return { clips = Showcase.catalog(), spawned = session ~= nil,
		mode = if session then session.mode else "Not spawned" }
end

local function stop(session: any)
	session.auto = false
	if session.track then session.track:Stop(Settings.FADE); session.track = nil end
	session.model:SetAttribute("PreviewName", "")
	session.model:SetAttribute("PreviewRelic", "")
	session.model:SetAttribute("PreviewSerial", (session.model:GetAttribute("PreviewSerial") or 0) + 1)
end

local function remove(player: Player)
	local session = sessions[player]
	if not session then return end
	stop(session)
	Fighters.remove(session.model)
	session.container:Destroy()
	sessions[player] = nil
end

local function board(parent: Instance, origin: CFrame): TextLabel
	local part = Instance.new("Part")
	part.Name, part.Size, part.CFrame = "CombatDisplay", Settings.BOARD_SIZE,
		origin * CFrame.new(Settings.BOARD_OFFSET)
	part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
	part.Color, part.Material = Theme.Color.Ink, Enum.Material.SmoothPlastic
	part.Parent = parent
	local gui = Instance.new("SurfaceGui")
	gui.Name, gui.Face, gui.CanvasSize = "ShowcaseTelemetry", Enum.NormalId.Front, Settings.BOARD_PIXELS
	gui.LightInfluence, gui.Parent = 0, part
	local text = Instance.new("TextLabel")
	text.Name, text.Size, text.Position = "Readout", UDim2.new(1, -40, 1, -32), UDim2.fromOffset(20, 16)
	text.BackgroundTransparency, text.TextSize = 1, 23
	text.Font, text.TextColor3 = Enum.Font.RobotoMono, Theme.Color.GoldHi
	text.TextXAlignment, text.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
	text.TextWrapped, text.Parent = false, gui
	return text
end

local function spawn(player: Player): (boolean, string)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return false, "Press PLAY and spawn before creating a dummy." end
	local template = workspace:FindFirstChild("TrainingDummy")
	if not template or not template:IsA("Model") then return false, "TrainingDummy template is missing." end
	local point = root.Position + root.CFrame.LookVector * Settings.SPAWN_DISTANCE
	local ground = Ground.at(point.X, point.Z, Settings.GROUND_TOP)
	if not ground then return false, "Choose a location with ground below it." end
	local position = ground + Vector3.new(0, Settings.ROOT_HEIGHT, 0)
	local origin = CFrame.lookAt(position, Vector3.new(root.Position.X, position.Y, root.Position.Z))
	remove(player)
	local container = Instance.new("Folder")
	container.Name, container.Parent = tostring(player.UserId), folder
	local model = template:Clone()
	model.Name = "ShowcaseDummy"
	for _, child in model:GetDescendants() do
		if child:IsA("LuaSourceContainer") or child:IsA("Accessory") or child:IsA("BillboardGui")
			or child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then child:Destroy() end
	end
	for key in model:GetAttributes() do model:SetAttribute(key, nil) end
	model:SetAttribute("ShowcaseOwner", player.UserId)
	model:SetAttribute("PreviewSerial", 0)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local dummyRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoid or not dummyRoot then container:Destroy(); model:Destroy(); return false, "Template must be an R6 humanoid." end
	local head = model:FindFirstChild("Head")
	if head and head:IsA("Part") then
		for _, child in head:GetChildren() do
			if child:IsA("DataModelMesh") or child:IsA("Decal") or child:IsA("SurfaceAppearance") then child:Destroy() end
		end
		head.Size, head.Shape, head.Color = Vector3.new(2, 1, 1), Enum.PartType.Block, Theme.Color.GoldHi
	end
	for _, child in model:GetDescendants() do
		if child:IsA("BasePart") then
			child.Anchored, child.Material = false, Enum.Material.SmoothPlastic
			if child ~= head then child.Color = Theme.Color.SlateHi end
		end
	end
	model.PrimaryPart = dummyRoot
	humanoid.MaxHealth, humanoid.Health = Settings.MAX_HEALTH, Settings.MAX_HEALTH
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model:PivotTo(origin)
	model.Parent = container
	dummyRoot.Anchored = true
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local session: any = { model = model, container = container, origin = origin, root = dummyRoot,
		humanoid = humanoid, set = Anims.forAnimator(animator), mode = "Preview", index = 0,
		auto = false, next = 0, lastDamage = 0, readout = board(container, origin) }
	sessions[player] = session
	local oldHealth = humanoid.Health
	humanoid.HealthChanged:Connect(function(health)
		if health < oldHealth then session.lastDamage = oldHealth - health end
		oldHealth = health
	end)
	Fighters.get(model)
	return true, "Showcase dummy spawned ahead of you. Preview animations or choose Training."
end

local function play(session: any, id: string): (boolean, string)
	local clip = byId[id]
	if not clip or not clip.available then return false, "This clip has no published animation or saved fallback." end
	local automatic = session.auto
	stop(session)
	session.auto = automatic
	session.mode = "Preview"
	local fighter = Fighters.get(session.model)
	if fighter and Ragdoll.active(fighter) then Ragdoll.stop(fighter) end
	session.root.Anchored = true
	session.model:PivotTo(session.origin)
	session.model:SetAttribute("PreviewName", clip.name)
	session.model:SetAttribute("PreviewStart", workspace:GetServerTimeNow())
	session.model:SetAttribute("PreviewRelic", clip.relic or "")
	session.model:SetAttribute("PreviewKey", clip.key or "")
	local duration = Settings.PREVIEW_SECONDS
	if clip.group == "Relic" then
		Gear.relic(session.model, clip.relic)
		local move = Relics.get(clip.relic).abilities[clip.key]
		duration = math.max(duration, move.windup + move.lock)
	else
		Gear.relic(session.model, nil)
		local ok, track = pcall(function() return session.set:play(resolved(id), Settings.FADE) end)
		if not ok or not track then stop(session); return false, "Animation could not load: " .. id end
		session.track = track
		duration = math.clamp(track.Length, Settings.PREVIEW_SECONDS, Settings.MAX_PREVIEW_SECONDS)
	end
	session.index = table.find(order, id) or 1
	session.next = workspace:GetServerTimeNow() + duration + Settings.CLIP_GAP
	session.model:SetAttribute("PreviewSerial", (session.model:GetAttribute("PreviewSerial") or 0) + 1)
	return true, "Previewing " .. clip.name .. "."
end

function Showcase.execute(player: Player, request: any): (boolean, string)
	Showcase.catalog()
	if request.action == "ShowcaseSpawn" then return spawn(player) end
	if request.action == "ShowcaseRemove" then remove(player); return true, "Showcase dummy removed." end
	local session = sessions[player]
	if not session then return false, "Spawn a showcase dummy first." end
	if request.action == "ShowcaseReset" then return spawn(player)
	elseif request.action == "ShowcaseStop" then stop(session); return true, "Animation playback stopped."
	elseif request.action == "ShowcaseTraining" then
		stop(session)
		session.mode = "Training"
		session.root.Anchored = false
		return true, "Training mode: hit the dummy. The board shows your real combat timers."
	elseif request.action == "ShowcasePlay" then
		if typeof(request.clip) ~= "string" or not byId[request.clip] then return false, "Choose a known animation." end
		session.auto = false
		return play(session, request.clip)
	elseif request.action == "ShowcaseNext" or request.action == "ShowcaseAuto" then
		session.auto = request.action == "ShowcaseAuto"
		return play(session, order[session.index % #order + 1])
	end
	return false, "Unknown showcase action."
end

local function readout(player: Player, session: any, at: number)
	local character = player.Character
	local fighter = character and Fighters.get(character)
	local dummy = Fighters.get(session.model)
	local lines = { "TRASH / ANIMATION & COMBAT LAB", "MODE: " .. session.mode .. (if session.auto then " / AUTO" else ""),
		"CLIP: " .. tostring(session.model:GetAttribute("PreviewName") or "None"), "", "LIVE PLAYER COOLDOWNS (seconds)" }
	for _, row in FIELDS do
		local ends = if fighter then fighter[row[2]] else 0
		if row[1] == "Carry" and character then ends = Knock.carryCooldownEnd(character) end
		if typeof(ends) ~= "number" then ends = player:GetAttribute("CooldownEnd_" .. row[1]) end
		local remaining = if typeof(ends) == "number" then math.max(0, ends - at) else nil
		local base = if row[1] == "Roll" then Movement.ROLL_COOLDOWN else Combat[string.upper(row[1]) .. "_COOLDOWN"]
		table.insert(lines, string.format("%-12s %-6s / %s", row[1],
			if remaining == nil then "--" elseif remaining > 0 then string.format("%.2f", remaining) else "READY",
			if typeof(base) == "number" then string.format("%.2fs base", base) else "attack timing"))
	end
	local relic = Relics.get(player:GetAttribute("Relic") or "")
	if relic then
		for _, key in Relics.KEYS do
			local remaining = math.max(0, (player:GetAttribute("CooldownEnd_" .. key) or 0) - at)
			table.insert(lines, string.format("%-12s %s  / %.1fs base", key,
				if remaining > 0 then string.format("%.2f", remaining) else "READY", relic.abilities[key].cooldown))
		end
	end
	table.insert(lines, string.format("\nState: %s / Combo: %d / Posture: %.0f", if character then character:GetAttribute("CombatState") or "Idle" else "Unspawned",
		if fighter then fighter.combo else 0, if fighter then fighter.posture else 0))
	table.insert(lines, string.format("Dummy HP: %.0f / Last hit: %.1f / Posture: %.0f", session.humanoid.Health,
		session.lastDamage, if dummy then dummy.posture else 0))
	table.insert(lines, string.format("Parry window %.2fs / Perfect dodge %.2fs", Combat.PARRY_WINDOW, Combat.PERFECT_DODGE_WINDOW))
	table.insert(lines, "Preview poses do not trigger attacks or start player cooldowns.")
	session.readout.Text = table.concat(lines, "\n")
	session.model:SetAttribute("ShowcaseMode", session.mode)
end

function Showcase.start()
	Showcase.catalog()
	folder = Instance.new("Folder")
	folder.Name, folder.Parent = "AdminShowcases", workspace
	Players.PlayerRemoving:Connect(remove)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < Settings.UPDATE_GAP then return end
		elapsed = 0
		local at = workspace:GetServerTimeNow()
		for player, session in sessions do
			if not player.Parent or player:GetAttribute("AdminAccess") ~= true then remove(player); continue end
			if session.auto and at >= session.next then play(session, order[session.index % #order + 1]) end
			readout(player, session, at)
		end
	end)
end

return Showcase
