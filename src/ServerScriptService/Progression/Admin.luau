--!strict
-- Owner-authorized game controls. Clients request named actions, never code or paths.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(script.Parent:WaitForChild("AdminConfig"))
local Levels = require(Shared.Config.Levels)
local Economy = require(Shared.Config.Economy)
local Survival = require(Shared.Config.Survival)
local Items = require(Shared.Data.Items)
local Relics = require(Shared.Data.Relics)
local Remotes = require(Shared.ProgressionRemotes)
local Profiles = require(script.Parent.Profiles)
local Progress = require(script.Parent.Progress)
local Inventory = require(script.Parent.Inventory)
local Sync = require(script.Parent.Sync)
local FactionService = require(script.Parent.FactionService)
local Ground = require(script.Parent.Ground)
local Showcase = require(script.Parent.Showcase)

local Admin = {}
local store = DataStoreService:GetDataStore(Config.ACCESS_STORE)
local access: { [number]: { allowed: boolean, expires: number } } = {}
local lastRequest: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local studioAccess: { [number]: boolean } = {}

local function integer(value: any, minimum: number, maximum: number): boolean
	return typeof(value) == "number" and value == value and value >= minimum
		and value <= maximum and value % 1 == 0
end

local function positionValid(value: any): boolean
	if typeof(value) ~= "Vector3" then return false end
	for _, n in { value.X, value.Y, value.Z } do
		if n ~= n or math.abs(n) > Config.MAX_COORDINATE then return false end
	end
	return value.Y > workspace.FallenPartsDestroyHeight + Config.TELEPORT_HEIGHT
end

local function setAccess(userId: number, allowed: boolean)
	access[userId] = { allowed = allowed, expires = os.clock() + Config.ACCESS_TTL }
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:SetAttribute("AdminAccess", allowed or userId == Config.OWNER_ID)
		if not allowed and userId ~= Config.OWNER_ID then
			Remotes.get("AdminResult"):FireClient(player, { close = true, message = "Admin access revoked." })
		end
	end
end

local function authorized(player: Player): boolean
	if player.Parent ~= Players then return false end
	if player.UserId == Config.OWNER_ID then return true end
	if RunService:IsStudio() and studioAccess[player.UserId] ~= nil then return studioAccess[player.UserId] end
	local cached = access[player.UserId]
	if cached and cached.expires > os.clock() then return cached.allowed end
	local ok, saved = pcall(function() return store:GetAsync(tostring(player.UserId)) end)
	local allowed = ok and saved == true
	setAccess(player.UserId, allowed)
	return allowed
end

local function snapshot(player: Player): any
	local roster, destinations = {}, {}
	for _, other in Players:GetPlayers() do
		table.insert(roster, { id = other.UserId, name = other.Name, display = other.DisplayName,
			admin = other.UserId == Config.OWNER_ID or other:GetAttribute("AdminAccess") == true })
	end
	table.sort(roster, function(a, b) return a.name < b.name end)
	local volumes = ReplicatedStorage:FindFirstChild("MapRegionVolumes")
	if volumes then
		for _, region in volumes:GetChildren() do
			if region:IsA("BasePart") then table.insert(destinations, region.Name) end
		end
	end
	table.sort(destinations)
	return { players = roster, destinations = destinations, owner = player.UserId == Config.OWNER_ID,
		maxLevel = Levels.MAX, maxStack = Economy.MAX_STACK, defaultItems = Config.DEFAULT_ITEMS,
		studio = RunService:IsStudio(), teleportHeight = Config.TELEPORT_HEIGHT, showcase = Showcase.info(player) }
end

local function targetFor(actor: Player, request: any): Player?
	local id = request.target or actor.UserId
	if not integer(id, 1, 2 ^ 53) then return nil end
	return Players:GetPlayerByUserId(id)
end

local function teleport(target: Player, destination: Vector3): (boolean, string)
	if not positionValid(destination) then return false, "Invalid or out-of-bounds destination." end
	local character = target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false, "Target must be alive and spawned." end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(CFrame.new(destination))
	return true, "Teleported " .. target.Name .. "."
end

local function changeAccess(actor: Player, request: any): (boolean, string)
	if actor.UserId ~= Config.OWNER_ID then return false, "Only the owner can manage admin access." end
	local identity = request.identity
	if typeof(identity) ~= "string" or #identity == 0 or #identity > Config.MAX_TEXT then
		return false, "Enter a Roblox username or User ID." end
	local id = tonumber(identity)
	if not id then
		local ok, resolved = pcall(function() return Players:GetUserIdFromNameAsync(identity) end)
		if not ok then return false, "Roblox username was not found." end
		id = resolved
	end
	if not integer(id, 1, 2 ^ 53) then return false, "Invalid User ID." end
	if id == Config.OWNER_ID then return false, "Owner access cannot be changed." end
	local allowed = request.action == "GrantAdmin"
	local ok = pcall(function()
		store:UpdateAsync(tostring(id), function() return allowed end)
	end)
	if not ok then
		if not RunService:IsStudio() then return false, "Access was not saved. Try again when DataStore access returns." end
		studioAccess[id] = allowed
		setAccess(id, allowed)
		return true, (if allowed then "Granted" else "Revoked") .. " admin for this Studio test only; DataStore access is disabled."
	end
	studioAccess[id] = nil
	setAccess(id, allowed)
	-- Other servers invalidate their cache; TTL also bounds missed messages.
	pcall(function() MessagingService:PublishAsync(Config.ACCESS_TOPIC, { id = id, allowed = allowed }) end)
	return true, (if allowed then "Granted admin to " else "Revoked admin from ") .. tostring(id) .. "."
end

function Admin.execute(actor: Player, request: any): (boolean, string)
	if not authorized(actor) then return false, "You do not have admin access." end
	if typeof(request) ~= "table" or typeof(request.action) ~= "string" then
		return false, "Invalid admin request." end
	local action = request.action
	if action:sub(1, 8) == "Showcase" then return Showcase.execute(actor, request) end
	if action == "GrantAdmin" or action == "RevokeAdmin" then return changeAccess(actor, request) end
	if action == "Refresh" then return true, "Player list refreshed." end
	local target = targetFor(actor, request)
	if not target then return false, "Choose a player currently in this server." end
	local profile = Profiles.get(target)
	if not profile then return false, "Target profile is still loading." end
	if Profiles.isReadOnly(target) and not RunService:IsStudio() then
		return false, "Target save is unavailable. Rejoin before modifying progress." end
	if action == "AddLevels" or action == "MaxLevel" then
		local amount = request.amount
		if action == "AddLevels" and not integer(amount, 1, Levels.MAX) then
			return false, "Enter a whole number of levels from 1 to " .. Levels.MAX .. "." end
		local goal = if action == "MaxLevel" then Levels.MAX else math.min(Levels.MAX, profile.level + amount)
		local exp = -profile.exp
		for level = profile.level, goal - 1 do exp += Levels.need(level) end
		if goal > profile.level then Progress.addExp(target, math.max(0, exp)) end
		return true, target.Name .. " is level " .. profile.level .. "."
	elseif action == "AllItems" or action == "GiveItem" then
		if not integer(request.amount, 1, Economy.MAX_STACK) then
			return false, "Item quantity must be between 1 and " .. Economy.MAX_STACK .. "." end
		if action == "GiveItem" then
			if typeof(request.item) ~= "string" or not Items.get(request.item) then return false, "Unknown item." end
			Inventory.give(target, request.item, request.amount)
		else
			for _, item in Items.list do Inventory.give(target, item.id, request.amount) end
		end
		return true, "Items given to " .. target.Name .. "."
	elseif action == "Resources" then
		if not integer(request.amount, 1, Config.MAX_AMOUNT) then return false, "Invalid resource amount." end
		Inventory.earn(target, { dollars = request.amount, scrap = request.amount, residue = request.amount })
		return true, "Resources given to " .. target.Name .. "."
	elseif action == "EquipRelic" then
		local relic = typeof(request.relic) == "string" and Relics.get(request.relic)
		if not relic then return false, "Unknown Relic." end
		profile.relic = { id = relic.id, rarity = relic.rarity, tier = if profile.relic then profile.relic.tier else 0 }
		profile.pending = nil
		Sync.changed(target)
		FactionService.dress(target)
		return true, "Equipped " .. relic.name .. " on " .. target.Name .. "."
	elseif action == "MaxRelic" then
		if not profile.relic then return false, "Equip a Relic first." end
		profile.relic.tier = Economy.MAX_TIER
		Sync.changed(target)
		return true, "All Relic moves unlocked for " .. target.Name .. "."
	elseif action == "Restore" then
		profile.survival.hunger = Survival.HUNGER_MAX
		profile.survival.thirst = Survival.THIRST_MAX
		profile.survival.blood = Survival.BLOOD_MAX
		local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then humanoid.Health = humanoid.MaxHealth end
		Sync.changed(target)
		return true, "Restored health and survival meters for " .. target.Name .. "."
	elseif action == "TeleportPosition" then
		if not positionValid(request.position) then return false, "Enter finite X, Y, Z coordinates above the void." end
		return teleport(target, request.position)
	elseif action == "TeleportRegion" then
		if typeof(request.region) ~= "string" then return false, "Choose a region." end
		local volumes = ReplicatedStorage:FindFirstChild("MapRegionVolumes")
		local region = volumes and volumes:FindFirstChild(request.region)
		if not region or not region:IsA("BasePart") then return false, "Unknown region." end
		local ground = Ground.at(region.Position.X, region.Position.Z, Config.GROUND_TOP)
		if not ground then return false, "No ground found at this region." end
		return teleport(target, ground + Vector3.new(0, Config.TELEPORT_HEIGHT, 0))
	elseif action == "GoToPlayer" or action == "BringPlayer" then
		local destinationPlayer = if action == "GoToPlayer" then target else actor
		local destinationRoot = destinationPlayer.Character and destinationPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not destinationRoot or not destinationRoot:IsA("BasePart") then return false, "Destination player is not spawned." end
		return teleport(if action == "GoToPlayer" then actor else target,
			destinationRoot.Position + destinationRoot.CFrame.RightVector * Config.TELEPORT_HEIGHT)
	end
	return false, "Unknown admin action."
end

local function respond(player: Player, request: any, open: boolean?)
	if busy[player] or os.clock() - (lastRequest[player] or -math.huge) < Config.REQUEST_GAP then return end
	lastRequest[player] = os.clock()
	busy[player] = true
	local ok, success, message = pcall(Admin.execute, player, request)
	busy[player] = nil
	if not ok then warn("[Admin] " .. tostring(success)); success, message = false, "Admin action failed." end
	if player.Parent ~= Players then return end
	local payload: any = { success = success, message = message, open = open and success or false }
	if authorized(player) then payload.state = snapshot(player) end
	Remotes.get("AdminResult"):FireClient(player, payload)
	if success and typeof(request) == "table" and request.action ~= "Refresh" then
		print(string.format("[Admin] %d %s target=%s", player.UserId, request.action, tostring(request.target or request.identity)))
	end
end

function Admin.start()
	Showcase.start()
	Remotes.get("AdminRequest").OnServerEvent:Connect(function(player, request)
		respond(player, request, typeof(request) == "table" and request.action == "Refresh")
	end)
	local command = Instance.new("TextChatCommand")
	command.Name = "TRASHAdminCommand"
	command.PrimaryAlias = "/admin"
	command.Parent = TextChatService
	command.Triggered:Connect(function(source)
		local player = source and Players:GetPlayerByUserId(source.UserId)
		if player then respond(player, { action = "Refresh" }, true) end
	end)
	local function joined(player: Player)
		player:SetAttribute("AdminOwner", player.UserId == Config.OWNER_ID)
		task.spawn(function() player:SetAttribute("AdminAccess", authorized(player)) end)
		player.Chatted:Connect(function(message)
			if string.lower(message):match("^%s*/admin%s*$") then respond(player, { action = "Refresh" }, true) end
		end)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do joined(player) end
	Players.PlayerRemoving:Connect(function(player)
		access[player.UserId], lastRequest[player], busy[player] = nil, nil, nil
	end)
	task.spawn(function()
		local ok, err = pcall(function()
			MessagingService:SubscribeAsync(Config.ACCESS_TOPIC, function(message)
				local data = message.Data
				if typeof(data) == "table" and integer(data.id, 1, 2 ^ 53) and typeof(data.allowed) == "boolean" then
					-- Read the saved value, so out-of-order messages cannot re-grant revoked access.
					access[data.id] = nil
					local player = Players:GetPlayerByUserId(data.id)
					if player then task.spawn(authorized, player) end
				end
			end)
		end)
		if not ok then warn("[Admin] Cross-server access updates use TTL: " .. tostring(err)) end
	end)
end

return Admin
