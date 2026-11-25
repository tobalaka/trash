--!strict
-- Published clips use Animator. Unpublished saves use the same runtime R6 pose player
-- in Studio and live games, with a validated cosmetic relay for observers.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Config = require(script.Parent.Config.Animations)
local PosePlayer = require(script.Parent.PosePlayer)
local Anims = {}
export type Set = any
local sets: {[Animator]: any} = setmetatable({}, {__mode = "k"}) :: any
local warned: {[string]: boolean} = {}
local function sequenceFor(name: string, seen: any?): KeyframeSequence?
	seen = seen or {}
	if seen[name] then return nil end
	seen[name] = true
	local def = Config[name]
	if not def then return nil end
	local folder = RS:WaitForChild("StudioAnimSaves", 10)
	if folder and def.studio then
		local source, clip = string.match(def.studio, "^([^/]+)/(.+)$")
		local group = source and folder:FindFirstChild(source)
		local seq = group and group:FindFirstChild(clip)
		if seq and seq:IsA("KeyframeSequence") then return seq end
	end
	return if def.fallback then sequenceFor(def.fallback, seen) else nil
end
function Anims.resolve(name: string): string?
	local def = Config[name]
	return if def and def.id ~= "" then def.id else nil
end
function Anims.forAnimator(animator: Animator): Set
	if sets[animator] then return sets[animator] end
	local model = animator:FindFirstAncestorOfClass("Model")
	local tracks: {[string]: any} = {}
	local set = {}
	function set:get(name: string): any
		if tracks[name] then return tracks[name] end
		local def = Config[name]
		if not def or not model or not model.Parent then return nil end
		local track: any = nil
		if def.id ~= "" then
			local animation = Instance.new("Animation")
			animation.AnimationId = def.id
			local ok, loaded = pcall(function() return animator:LoadAnimation(animation) end)
			animation:Destroy()
			if ok then track = loaded; track.Priority = def.priority; track.Looped = def.looped end
		end
		if not track then track = self:useSaved(name) end
		if not track and not warned[name] then warned[name] = true; warn("[Anims] Missing saved clip: " .. name) end
		tracks[name] = track
		return track
	end
	function set:useSaved(name: string): any
		if type(tracks[name]) == "table" then return tracks[name] end
		local def = Config[name]
		local seq = def and sequenceFor(name)
		if not seq or not model or not model.Parent then return nil end
		local old = tracks[name]
		if old then old:Stop(0); old:Destroy() end
		local track = PosePlayer.new(model, seq, def.priority, def.looped, function(mode, fade, speed)
			local relay = RS:FindFirstChild("AnimationRelay") :: RemoteEvent?
			if not relay then return end
			-- the last argument marks a server-started clip: its owner plays it too
			if RunService:IsServer() then relay:FireAllClients(model, mode, name, fade, speed, true)
			elseif Players.LocalPlayer.Character == model then relay:FireServer(mode, name, fade, speed) end
		end)
		tracks[name] = track
		return track
	end
	function set:play(name: string, fade: number?, speed: number?): any
		local track = self:get(name)
		if track then track:Play(fade or 0.1, 1, speed or 1) end
		return track
	end
	function set:playFor(name: string, duration: number, fade: number?): any
		local track = self:get(name)
		if track then track:Play(fade or 0.1, 1, if duration > 0 and track.Length > 0 then track.Length / duration else 1) end
		return track
	end
	function set:stop(name: string, fade: number?)
		local track = tracks[name]
		if track then track:Stop(fade or 0.1) end
	end
	function set:preload()
		for name in Config do self:get(name) end
	end
	sets[animator] = set
	return set
end
if RunService:IsClient() then
	task.spawn(function()
		local relay = RS:WaitForChild("AnimationRelay", 20) :: RemoteEvent?
		if not relay then return end
		relay.OnClientEvent:Connect(function(model, mode, name, fade, speed, fromServer)
			if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent then return end
			-- this client already plays its own clips; only server-started ones are news to it
			if model == Players.LocalPlayer.Character and fromServer ~= true then return end
			local hum = model:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if not animator then return end
			local track = Anims.forAnimator(animator):get(name)
			if not track then return end
			if mode == "Play" then track:Play(fade, 1, speed)
			elseif mode == "Stop" then track:Stop(fade)
			elseif mode == "Speed" then track:AdjustSpeed(speed) end
		end)
	end)
end
return Anims

