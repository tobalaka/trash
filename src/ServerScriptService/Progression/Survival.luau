--!strict
--[[
	Survival - Hunger, Thirst and Blood (shown as Vitality), the knocked loop, Wastezone gas and
	using items (vault: Hunger-Thirst, Blood). The server owns every value; the HUD reads the
	Hunger / Thirst / Blood attributes (+ "<Name>Max").

	Each TICK:
	  - Hunger and Thirst drain (half speed in your own faction's base, faster under smog, slower
	    with Iron Stomach).
	  - Blood drains while either is empty, and recovers slowly while both are above LOW.
	  - In the Wastezone, without an active Bottle Respirator, gas drains Blood and Health.
	  - At 0 Blood the player is knocked: down for KNOCK_TIME (CombatService's Ragdoll), up for
	    KNOCK_UP_TIME, down again... until they eat or drink (designer rules). Hits taken while
	    down cost Blood. An ally of the same side with Supporter's Field Revive can hold E on
	    them (REVIVE_HOLD) to get them up with REVIVE_BLOOD and a share of food and water.
	  - Well Fed: both meters at WELL_FED_AT or more speed Blood recovery and give Relic moves a
	    little extra (RelicService reads Survival.wellFed). Shown as the WellFed attribute.
	Meters persist in the profile, so leaving and rejoining doesn't refill them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local S = require(Config:WaitForChild("Survival"))
local Environment = require(Config:WaitForChild("Environment"))
local Factions = require(Config:WaitForChild("Factions"))
local Items = require(Shared:WaitForChild("Data"):WaitForChild("Items"))
local Levels = require(Config:WaitForChild("Levels"))
local Remotes = require(Shared:WaitForChild("ProgressionRemotes"))
local Anims = require(Shared:WaitForChild("Anims"))
local Profiles = require(script.Parent:WaitForChild("Profiles"))
local Sync = require(script.Parent:WaitForChild("Sync"))
local Inventory = require(script.Parent:WaitForChild("Inventory"))
local Progress = require(script.Parent:WaitForChild("Progress"))
local Regions = require(script.Parent:WaitForChild("Regions"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local Bus = require(script.Parent:WaitForChild("Bus"))
local Titles = require(script.Parent:WaitForChild("Titles"))

local Combat = ServerScriptService:WaitForChild("Combat")
local Fighters = require(Combat:WaitForChild("Fighters"))
local Ragdoll = require(Combat:WaitForChild("Ragdoll"))

local USE_RATE = 3
local REVIVE_PROMPT = "HelpUp"
local REVIVE_RATE = 2

type Live = {
	knock: string?, -- "down" | "up"
	knockUntil: number,
	bleedUntil: number, -- bandage: Blood can't drain
	gasUntil: number,
	healConn: RBXScriptConnection?,
	lastHealth: number,
}

local Survival = {}

local live: { [Player]: Live } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function state(player: Player): Live
	local l = live[player]
	if not l then
		l = { knock = nil, knockUntil = 0, bleedUntil = 0, gasUntil = 0, healConn = nil, lastHealth = 0 }
		live[player] = l
	end
	return l
end

local function publish(player: Player, p: Profiles.Profile)
	local m = p.survival
	player:SetAttribute("Hunger", math.floor(m.hunger * 10 + 0.5) / 10)
	player:SetAttribute("Thirst", math.floor(m.thirst * 10 + 0.5) / 10)
	player:SetAttribute("Blood", math.floor(m.blood * 10 + 0.5) / 10)
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

local function stopKnock(player: Player)
	local l = state(player)
	if not l.knock then
		return
	end
	l.knock = nil
	player:SetAttribute("Knocked", nil)
	local character = player.Character
	local f = character and Fighters.get(character)
	if f and Ragdoll.active(f) then
		Ragdoll.stop(f)
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local prompt = root and root:FindFirstChild(REVIVE_PROMPT)
	if prompt then
		prompt:Destroy()
	end
end

local function knockDown(player: Player)
	local l = state(player)
	local character = player.Character
	local f = character and Fighters.get(character)
	l.knock = "down"
	l.knockUntil = now() + S.KNOCK_TIME
	player:SetAttribute("Knocked", true)
	-- allies with Field Revive can help them up (clients only show it to those who can)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and not root:FindFirstChild(REVIVE_PROMPT) then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = REVIVE_PROMPT
		prompt.ActionText = "Help up"
		prompt.ObjectText = player.DisplayName
		prompt.HoldDuration = S.REVIVE_HOLD
		prompt.MaxActivationDistance = S.REVIVE_RANGE
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt:SetAttribute("Faction", (Profiles.get(player) or {} :: any).faction)
		prompt.Parent = root
	end
	if f then
		Ragdoll.start(f, S.KNOCK_TIME)
		f.stunEnd = math.max(f.stunEnd, now() + S.KNOCK_TIME)
	end
end

local function step(dt: number)
	local pollution = workspace:GetAttribute("Pollution")
	local smog = typeof(pollution) == "number" and pollution >= Environment.POLLUTION_HIGH
	local t = now()
	for _, player in Players:GetPlayers() do
		local p = Profiles.get(player)
		local humanoid = humanoidOf(player)
		if not p or not humanoid then
			continue
		end
		local l = state(player)
		local m = p.survival
		local fx = Progress.effects(player)
		local region = Regions.of(player)
		local mult = 1 - (fx.drain or 0)
		if p.faction and region == Factions.INFO[p.faction].region then
			mult *= S.SAFE_ZONE_DRAIN
		end
		if smog then
			mult *= S.SMOG_DRAIN
		end
		m.hunger = math.max(0, m.hunger - S.HUNGER_DRAIN / 60 * dt * mult)
		m.thirst = math.max(0, m.thirst - S.THIRST_DRAIN / 60 * dt * mult)

		local bleeding = l.bleedUntil > t
		local fed = m.hunger >= S.WELL_FED_AT and m.thirst >= S.WELL_FED_AT
		if player:GetAttribute("WellFed") ~= (if fed then true else nil) then
			player:SetAttribute("WellFed", if fed then true else nil)
		end
		if (m.hunger <= 0 or m.thirst <= 0) and not bleeding then
			m.blood = math.max(0, m.blood - S.BLOOD_DRAIN * dt)
		elseif m.hunger >= S.LOW and m.thirst >= S.LOW and not l.knock then
			m.blood = math.min(S.BLOOD_MAX, m.blood + S.BLOOD_REGEN * dt * (if fed then S.WELL_FED_REGEN else 1))
		end

		-- Wastezone gas
		local toxic = region ~= nil and S.GAS_REGIONS[region] == true and l.gasUntil <= t
		if toxic then
			local resist = 1 - (fx.gasResist or 0)
			if not bleeding then
				m.blood = math.max(0, m.blood - S.GAS_BLOOD_DRAIN * dt * resist)
			end
			humanoid:TakeDamage(S.GAS_HEALTH_DRAIN * dt * resist)
		end
		if player:GetAttribute("Toxic") ~= toxic then
			player:SetAttribute("Toxic", toxic)
		end

		-- the knocked loop
		if m.blood <= 0 then
			if not l.knock then
				knockDown(player)
			elseif t >= l.knockUntil then
				if l.knock == "down" then
					l.knock = "up"
					l.knockUntil = t + S.KNOCK_UP_TIME
					local f = player.Character and Fighters.get(player.Character :: Model)
					if f and Ragdoll.active(f) then
						Ragdoll.stop(f)
					end
				else
					knockDown(player)
				end
			end
		elseif l.knock then
			stopKnock(player)
		end
		publish(player, p)
		Profiles.markDirty(player) -- meters persist; saved on the next autosave or on leave
	end
end

-- ── using items ──

function Survival.use(player: Player, itemId: string)
	if not Guard.allow(player, "UseItem", USE_RATE) then
		return
	end
	local p = Profiles.get(player)
	local item = Items.get(itemId)
	local humanoid = humanoidOf(player)
	if not p or not item or not item.use or not humanoid then
		return
	end
	if not Inventory.take(player, itemId, 1) then
		return
	end
	local use = item.use
	local fx = Progress.effects(player)
	local power = 1 + (fx.itemPower or 0)
	local m = p.survival
	local l = state(player)
	if use.hunger then
		m.hunger = math.min(S.HUNGER_MAX, m.hunger + use.hunger * power)
	end
	if use.thirst then
		m.thirst = math.min(S.THIRST_MAX, m.thirst + use.thirst * power)
	end
	if use.blood and use.blood < 0 and not fx.cleanGut then
		m.blood = math.max(0, m.blood + use.blood)
	end
	if use.stopBleed then
		l.bleedUntil = math.max(l.bleedUntil, now() + use.stopBleed)
	end
	if use.gas then
		l.gasUntil = math.max(l.gasUntil, now()) + use.gas
		player:SetAttribute("GasUntil", l.gasUntil)
	end
	if use.heal and use.healTime then
		local total = use.heal * power
		local per = total / use.healTime
		local ends = now() + use.healTime
		task.spawn(function()
			while now() < ends and humanoid.Parent and humanoid.Health > 0 do
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + per * 0.25)
				task.wait(0.25)
			end
		end)
	end
	-- eating or drinking while knocked gets you back up (designer rule)
	if l.knock and (use.hunger or use.thirst) and m.hunger > 0 and m.thirst > 0 then
		m.blood = math.max(m.blood, S.KNOCK_EXIT_BLOOD)
		stopKnock(player)
	end
	publish(player, p)
	Sync.changed(player)
	-- everyone sees the item used: bandages wrap, drinks tip back, food is eaten
	local anim = if use.heal or use.stopBleed then "Bandage" elseif use.thirst then "Drink" elseif use.hunger then "Eat" else nil
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if anim and animator and not l.knock then
		Anims.forAnimator(animator):play(anim, 0.15)
	end
	Sync.notify(player, "Toast", { text = "Used " .. item.name, color = "Lime" })
	Bus.emit(player, "Consume", { item = itemId, food = use.hunger ~= nil, water = use.thirst ~= nil })
end

-- seconds of gas protection left
function Survival.gasLeft(player: Player): number
	return math.max(0, state(player).gasUntil - now())
end

-- both meters high: a small Relic bonus (RelicService)
function Survival.wellFed(player: Player): boolean
	return player:GetAttribute("WellFed") == true
end

-- `helper` held the Help up prompt on knocked `patient`
local function revive(helper: Player, patient: Player)
	if helper == patient or not Guard.allow(helper, "Revive", REVIVE_RATE) then
		return
	end
	local hp, pp = Profiles.get(helper), Profiles.get(patient)
	local l = state(patient)
	if not hp or not pp or not l.knock or not humanoidOf(helper) or helper:GetAttribute("Knocked") then
		return
	end
	if not Progress.effects(helper).revive then
		Sync.notify(helper, "Toast", { text = "Only a Supporter with Field Revive can help them up.", color = "Red" })
		return
	end
	if not hp.faction or hp.faction ~= pp.faction then
		return
	end
	local a, b = Regions.rootOf(helper), Regions.rootOf(patient)
	if not a or not b or (a.Position - b.Position).Magnitude > S.REVIVE_RANGE + 2 then
		return
	end
	local m = pp.survival
	m.blood = math.max(m.blood, S.REVIVE_BLOOD)
	m.hunger = math.min(S.HUNGER_MAX, m.hunger + S.REVIVE_FOOD)
	m.thirst = math.min(S.THIRST_MAX, m.thirst + S.REVIVE_FOOD)
	stopKnock(patient)
	publish(patient, pp)
	Sync.changed(patient)
	Sync.notify(patient, "Toast", { text = helper.DisplayName .. " helped you up.", color = "Lime" })
	Progress.grant(helper, { exp = Levels.EXP.REVIVE, standing = Factions.STANDING.REVIVE }, "Helped " .. patient.DisplayName .. " up")
	Titles.bump(helper, "revives", 1)
	Bus.emit(helper, "Revive", { patient = patient })
end

function Survival.start()
	Inventory.onUse(Survival.use)
	game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, helper)
		if prompt.Name ~= REVIVE_PROMPT then
			return
		end
		local character = prompt.Parent and prompt.Parent.Parent
		local patient = character and Players:GetPlayerFromCharacter(character)
		if patient then
			revive(helper, patient)
		end
	end)
	Remotes.get("UseItem").OnServerEvent:Connect(function(player, itemId)
		if typeof(itemId) == "string" then
			Survival.use(player, itemId)
		end
	end)
	local function watch(player: Player)
		player:SetAttribute("HungerMax", S.HUNGER_MAX)
		player:SetAttribute("ThirstMax", S.THIRST_MAX)
		player:SetAttribute("BloodMax", S.BLOOD_MAX)
		player.CharacterAdded:Connect(function(character)
			local l = state(player)
			l.knock = nil
			player:SetAttribute("Knocked", nil)
			local p = Profiles.get(player)
			if p then
				p.survival.blood = math.max(p.survival.blood, S.RESPAWN_BLOOD)
				publish(player, p)
			end
			local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
			if not humanoid then
				return
			end
			if l.healConn then
				l.healConn:Disconnect()
			end
			l.lastHealth = humanoid.Health
			l.healConn = humanoid.HealthChanged:Connect(function(health)
				local lost = l.lastHealth - health
				l.lastHealth = health
				local profile = Profiles.get(player)
				if lost > 0 and l.knock == "down" and profile then
					profile.survival.blood = math.max(0, profile.survival.blood - S.KNOCK_HIT_LOSS)
				end
			end)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		local l = live[player]
		if l and l.healConn then
			l.healConn:Disconnect()
		end
		live[player] = nil
	end)
	Profiles.onLoaded(function(player, p)
		publish(player, p)
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(S.TICK)
			local t = os.clock()
			step(t - last)
			last = t
		end
	end)
end

return Survival
