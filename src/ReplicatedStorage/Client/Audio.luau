--!strict
-- Shared client mixer: bounded positional cues, separate volume controls, and quiet zone beds.
-- Legacy Sounds[name] arrays remain compatible with callers not yet migrated to Audio.play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")

local Config: any = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Sounds"))
local Mix = Config.Mix
local player = Players.LocalPlayer
local random = Random.new()

local Audio = {}
local started = false
local groups: { [string]: SoundGroup } = {}
local voices: { Sound } = {}
local recent: { [string]: number } = {}
local background: { [string]: Sound } = {}
local tweens: { [Sound]: Tween } = {}
local targets: { [Sound]: number } = {}
local combatUntil = 0
local warned: { [string]: boolean } = {}
local assetReady: { [string]: boolean } = {}

local function setting(category: string): number
	local value = player:GetAttribute("Audio" .. category .. "Volume")
	return if typeof(value) == "number" then math.clamp(value, 0, 1) else 1
end

local function group(name: string, parent: Instance): SoundGroup
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		return existing
	end
	local result = Instance.new("SoundGroup")
	result.Name = name
	result.Parent = parent
	return result
end

local function applyMix()
	for category, target in groups do
		target.Volume = Mix[category] * setting(category)
	end
	-- The imported footstep system owns this hierarchy. Keep its routing, lower its gain,
	-- and make its sounds obey the same Master/SFX sliders as combat.
	local main = SoundService:FindFirstChild("Main")
	local character = main and main:FindFirstChild("Character")
	if character and character:IsA("SoundGroup") then
		character.Volume = Mix.LegacyCharacter * Mix.Master * setting("Master") * Mix.SFX * setting("SFX")
		for _, name in { "Footsteps", "Landing", "Jumping" } do
			local target = character:FindFirstChild(name)
			if target and target:IsA("SoundGroup") then
				target.Volume = Mix[name]
			end
		end
	end
end

local function ensureMix()
	if groups.Master then
		return
	end
	groups.Master = group("TRASH_Audio", SoundService)
	for _, category in { "SFX", "Music", "Ambience" } do
		groups[category] = group(category, groups.Master)
	end
	applyMix()
	for _, category in { "Master", "SFX", "Music", "Ambience" } do
		player:GetAttributeChangedSignal("Audio" .. category .. "Volume"):Connect(applyMix)
	end
end

function Audio.setVolume(category: string, value: number)
	if Mix[category] == nil or not table.find({ "Master", "SFX", "Music", "Ambience" }, category) then
		return
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return
	end
	ensureMix()
	player:SetAttribute("Audio" .. category .. "Volume", math.clamp(value, 0, 1))
end

local function positionParent(where: (Instance | Vector3)?): (Instance, Attachment?)
	if typeof(where) == "Vector3" then
		local point = Instance.new("Attachment")
		point.Name = "TRASH_SoundPoint"
		point.Parent = workspace.Terrain
		point.WorldPosition = where
		return point, point
	elseif typeof(where) == "Instance" then
		if where:IsA("Model") then
			local root = where:FindFirstChild("HumanoidRootPart") or where.PrimaryPart
			if root and root:IsA("BasePart") then
				return root, nil
			end
		elseif where:IsA("BasePart") or where:IsA("Attachment") then
			return where, nil
		end
	end
	return SoundService, nil
end

-- volume is an optional absolute cue volume before the Master/SFX mix (0..1).
function Audio.play(name: string, where: (Instance | Vector3)?, volume: number?, pitch: number?): Sound?
	local ids = Config[name]
	if typeof(ids) ~= "table" or typeof(ids[1]) ~= "string" then
		return nil
	end
	local at = os.clock()
	if at - (recent[name] or -math.huge) < Mix.MinCueInterval then
		return nil
	end
	recent[name] = at
	ensureMix()
	if #voices >= Mix.MaxVoices then
		local oldest = table.remove(voices, 1)
		if oldest then
			oldest:Destroy()
		end
	end
	local parent, point = positionParent(where)
	local sound = Instance.new("Sound")
	sound.Name = "TRASH_" .. name
	local selected = ids[random:NextInteger(1, #ids)]
	if assetReady[selected] == false then
		-- the preload reported this asset as unavailable: only a cue with its own fitting
		-- fallback plays anything (an unrelated default sound is worse than silence)
		local fallback = Config.Fallbacks[name]
		if not fallback then
			sound:Destroy()
			if point then
				point:Destroy()
			end
			return nil
		end
		selected = fallback
	end
	sound.SoundId = selected
	local tuning = Config.Tuning[selected]
	sound.Volume = math.clamp((volume or Config.Volumes[name] or Config.Volumes.Hit) * (tuning and tuning.volume or 1), 0, 10)
	local speed = (tuning and tuning.speed or 1) * (Config.Speeds[name] or 1)
	sound.PlaybackSpeed = math.clamp((pitch or random:NextNumber(Mix.PitchMin, Mix.PitchMax)) * speed, 0.5, 3)
	local distortion = Config.Distortion[name]
	if distortion then
		local effect = Instance.new("DistortionSoundEffect")
		effect.Level = distortion
		effect.Parent = sound
	end
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = Mix.RollOffMinDistance
	sound.RollOffMaxDistance = Mix.RollOffMaxDistance
	sound.SoundGroup = groups.SFX
	sound.Parent = parent
	table.insert(voices, sound)
	sound.Destroying:Once(function()
		local index = table.find(voices, sound)
		if index then
			table.remove(voices, index)
		end
		if point then
			task.defer(function()
				point:Destroy()
			end)
		end
	end)
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
	-- Stop stalled cues before they become an unrelated late impact. A slow first fetch is
	-- not a failure: only the preload's verdict (assetReady) switches a cue to its fallback.
	task.delay(Mix.LoadTimeout, function()
		if sound.Parent and not sound.IsLoaded then
			sound:Destroy()
		end
	end)
	task.delay(Mix.VoiceLifetime, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
	if name ~= "UI" and name ~= "UIHover" and name ~= "Dash" and name ~= "AirDash" and name ~= "Jump" and name ~= "Swing"
		and name ~= "SwingWeapon" and name ~= "WallClimb" then
		combatUntil = at + Mix.CombatDuckSeconds
	end
	return sound
end

local function fade(sound: Sound, volume: number)
	if targets[sound] == volume then
		return
	end
	targets[sound] = volume
	local previous = tweens[sound]
	if previous then
		previous:Cancel()
	end
	local tween = TweenService:Create(sound, TweenInfo.new(Mix.Crossfade), { Volume = volume })
	tweens[sound] = tween
	tween:Play()
end

-- ── music ──────────────────────────────────────────────────────────────────
-- One track plays at a time, picked from Config.Music by mode: Menu (intro or a window open),
-- the zone's list (Config.MusicZones by the Region attribute), Combat for a while after this
-- player trades blows (Audio.engage), Boss against the Junk Ram or during a Turf War. A mode
-- change crossfades to a random track of the new mode.

local musicMode: string? = nil
local musicSound: Sound? = nil
local engagedUntil = 0
local engagedBoss = false

-- Called when this player hits or is hit; `other` is the other fighter.
function Audio.engage(other: Model?)
	engagedUntil = os.clock() + Mix.CombatMusicSeconds
	if other and other:GetAttribute("Mob") == "JunkRam" then
		engagedBoss = true
	end
end

local function musicModeNow(menu: boolean): string
	if menu then
		return "Menu"
	end
	if os.clock() < engagedUntil then
		return if engagedBoss or workspace:GetAttribute("TurfState") == "Open" then "Boss" else "Combat"
	end
	engagedBoss = false
	local region = player:GetAttribute("Region")
	return Config.MusicZones[if typeof(region) == "string" then region else "Default"] or Config.MusicZones.Default
end

local function musicVolume(mode: string): number
	return Mix["Music" .. mode] or Mix.MusicWorld
end

local function switchMusic(mode: string)
	musicMode = mode
	local old = musicSound
	musicSound = nil
	if old then
		fade(old, 0)
		task.delay(Mix.Crossfade + 0.1, function()
			targets[old] = nil
			tweens[old] = nil
			old:Destroy()
		end)
	end
	local list = Config.Music[mode]
	if typeof(list) ~= "table" or #list == 0 then
		return
	end
	local id = list[random:NextInteger(1, #list)]
	local sound = Instance.new("Sound")
	sound.Name = "TRASH_Music_" .. mode
	sound.SoundId = id
	sound.Volume = 0
	sound.Looped = true
	sound.SoundGroup = groups.Music
	sound.Parent = SoundService
	musicSound = sound
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
		if musicSound ~= sound then
			return
		end
		if sound.IsLoaded then
			sound:Play()
			fade(sound, musicVolume(mode))
		elseif not warned[id] then
			warned[id] = true
			warn("[Audio] Could not load music " .. mode .. " (" .. id .. "). Swap it in Shared/Config/Sounds Music.")
		end
	end)
end

local function updateMusic(menu: boolean)
	local mode = musicModeNow(menu)
	if mode ~= musicMode then
		switchMusic(mode)
	elseif musicSound and musicSound.IsPlaying then
		fade(musicSound, musicVolume(mode))
	end
end

local function updateBackground()
	local region = player:GetAttribute("Region")
	local levels = Config.Regions[if typeof(region) == "string" then region else "Default"] or Config.Regions.Default
	local menu = player:GetAttribute("MenuOpen") == true or player.Character == nil
	local duck = if menu then Mix.MenuAmbience else 1
	for i, name in { "Wind", "Industry", "Forest" } do
		local sound = background[name]
		if sound then
			fade(sound, levels[i] * duck)
		end
	end
	updateMusic(menu)
end

local function startBackground(name: string, id: string)
	local sound = Instance.new("Sound")
	sound.Name = "TRASH_" .. name
	sound.SoundId = id
	sound.Volume = 0
	sound.Looped = true
	sound.SoundGroup = groups[if name == "Music" then "Music" else "Ambience"]
	sound.Parent = SoundService
	background[name] = sound
	task.spawn(function()
		local ok = pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
		if ok and sound.IsLoaded then
			sound.Volume = 0
			targets[sound] = nil
			sound:Play()
			updateBackground()
		else
			if not warned[id] then
				warned[id] = true
				warn("[Audio] Could not load " .. name .. " (" .. id .. "). Check experience audio access.")
			end
			-- Wind has an installed Roblox fallback; never loop an unrelated effect as music.
			if name == "Wind" then
				sound.SoundId = "rbxasset://sounds/action_falling.ogg"
				sound.Volume = 0
				targets[sound] = nil
				sound:Play()
				updateBackground()
			end
		end
	end)
end

function Audio.start()
	if started then
		return
	end
	started = true
	ensureMix()
	for name, id in Config.Background do
		startBackground(name, id)
	end
	-- Warm sound objects without delaying the intro or the player's first input.
	-- Preload Sound instances, not bare id strings: a string is fetched as an image, fails with
	-- "Asset type does not match requested type", and would mark every cue as unavailable.
	task.spawn(function()
		local warm: { Sound } = {}
		local seen: { [string]: boolean } = {}
		for name in Config.Volumes do
			for _, id in Config[name] do
				if not seen[id] then
					seen[id] = true
					local s = Instance.new("Sound")
					s.SoundId = id
					table.insert(warm, s)
				end
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(warm, function(id: string, status: Enum.AssetFetchStatus)
				if status == Enum.AssetFetchStatus.Success then
					assetReady[id] = true
				elseif status == Enum.AssetFetchStatus.Failure then
					assetReady[id] = false
				end
			end)
		end)
		for _, s in warm do
			s:Destroy()
		end
	end)
	task.delay(1, function()
		applyMix()
		local main = SoundService:FindFirstChild("Main")
		if main then
			pcall(function()
				ContentProvider:PreloadAsync({ main })
			end)
		end
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	local function hookButton(instance: Instance)
		if instance:IsA("GuiButton") then
			instance.Activated:Connect(function()
				Audio.play("UI")
			end)
			instance.MouseEnter:Connect(function()
				Audio.play("UIHover")
			end)
		end
	end
	for _, instance in playerGui:GetDescendants() do
		hookButton(instance)
	end
	playerGui.DescendantAdded:Connect(hookButton)
	task.spawn(function()
		while started do
			updateBackground()
			task.wait(Mix.UpdateInterval)
		end
	end)
end

return Audio
