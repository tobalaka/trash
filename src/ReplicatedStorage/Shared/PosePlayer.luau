--!strict
-- Runtime playback of saved R6 poses. Visual only; no root movement or damage.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local PosePlayer = {}
local clips: {[Instance]: any} = setmetatable({}, {__mode = "k"}) :: any
local rigs: {[Model]: any} = {}
local serial = 0

local function clipFor(sequence: KeyframeSequence): any
	if clips[sequence] then return clips[sequence] end
	local clip = {length = 0, channels = {}}
	local frames = sequence:GetKeyframes()
	table.sort(frames, function(a, b) return a.Time < b.Time end)
	for _, frame in frames do
		clip.length = math.max(clip.length, frame.Time)
		for _, pose in frame:GetDescendants() do
			if pose:IsA("Pose") and pose.Parent and pose.Parent:IsA("Pose") then
				local key = pose.Parent.Name .. "/" .. pose.Name
				clip.channels[key] = clip.channels[key] or {}
				table.insert(clip.channels[key], {time = frame.Time, cf = pose.CFrame, weight = pose.Weight,
					style = pose.EasingStyle.Name, direction = pose.EasingDirection.Name})
			end
		end
	end
	clip.length = math.max(clip.length, 1 / 30)
	clips[sequence] = clip
	return clip
end

local function sample(keys: any, at: number): (CFrame, number)
	if at <= keys[1].time then return keys[1].cf, keys[1].weight end
	local a, b = keys[#keys], keys[#keys]
	for i = 2, #keys do
		if keys[i].time >= at then a, b = keys[i - 1], keys[i]; break end
	end
	local t = if b.time > a.time then math.clamp((at - a.time) / (b.time - a.time), 0, 1) else 0
	if a.style == "Constant" then t = 0
	elseif a.style ~= "Linear" then
		local style = Enum.EasingStyle[a.style]
		local direction = Enum.EasingDirection[a.direction]
		if style and direction then t = TweenService:GetValue(t, style, direction) end
	end
	return a.cf:Lerp(b.cf, t), a.weight + (b.weight - a.weight) * t
end

local function restore(rig: any)
	for motor, previous in rig.previous do
		if motor.Parent and motor.Transform == previous.written then motor.Transform = previous.base end
	end
	table.clear(rig.previous)
end

local function rigFor(model: Model): any
	local rig = rigs[model]
	if rig then return rig end
	rig = {tracks = {}, motors = {}, previous = {}}
	for _, motor in model:GetDescendants() do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			rig.motors[motor.Part0.Name .. "/" .. motor.Part1.Name] = motor
		end
	end
	rigs[model] = rig
	return rig
end

function PosePlayer.new(model: Model, sequence: KeyframeSequence, priority: Enum.AnimationPriority, looped: boolean, notify: ((string, number, number) -> ())?): any
	local clip = clipFor(sequence)
	local rig = rigFor(model)
	local track: any = {Length = clip.length, IsPlaying = false, Looped = looped, Priority = priority,
		TimePosition = 0, Speed = 1, weight = 0, target = 0, fade = 0.1, clip = clip, order = 0, changed = 0}
	function track:Play(fade: number?, weight: number?, speed: number?)
		serial += 1
		self.order = serial
		self.Speed = speed or 1
		self.TimePosition = if self.Speed < 0 then self.Length else 0
		self.weight = 0
		self.target = weight or 1
		self.fade = math.max(fade or 0.1, 0.001)
		self.IsPlaying = true
		if notify then notify("Play", self.fade, self.Speed) end
	end
	function track:Stop(fade: number?)
		self.target = 0
		self.fade = math.max(fade or 0.1, 0.001)
		if notify then notify("Stop", self.fade, 0) end
	end
	function track:AdjustSpeed(speed: number)
		local old = self.Speed
		self.Speed = speed
		if notify and math.abs(old - speed) > 0.08 and os.clock() - self.changed >= 0.12 then
			self.changed = os.clock()
			notify("Speed", 0, speed)
		end
	end
	function track:Destroy()
		self.IsPlaying = false
		rig.tracks[self] = nil
	end
	rig.tracks[track] = true
	return track
end

RunService.PreAnimation:Connect(function()
	for _, rig in rigs do restore(rig) end
end)

RunService.PreSimulation:Connect(function(dt)
	for model, rig in rigs do
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not model.Parent or not hum or hum.Health <= 0 then
			restore(rig)
			for track in rig.tracks do track.IsPlaying = false end
			rigs[model] = nil
			continue
		end
		local active = {}
		for track in rig.tracks do
			if track.IsPlaying then
				track.TimePosition += dt * track.Speed
				if track.Looped then track.TimePosition %= track.Length
				elseif track.TimePosition >= track.Length or track.TimePosition < 0 then
					track.TimePosition = math.clamp(track.TimePosition, 0, track.Length)
					track.target = 0
				end
				local step = dt / track.fade
				track.weight += math.clamp(track.target - track.weight, -step, step)
				if track.target == 0 and track.weight <= 0 then track.IsPlaying = false
				else table.insert(active, track) end
			end
		end
		if RunService:IsServer() or model:GetAttribute("RelicAnimating") or model:GetAttribute("Ragdolled") then continue end
		table.sort(active, function(a, b)
			local ap = if a.Priority == Enum.AnimationPriority.Core then -1 else a.Priority.Value
			local bp = if b.Priority == Enum.AnimationPriority.Core then -1 else b.Priority.Value
			return if ap == bp then a.order < b.order else ap < bp
		end)
		for key, motor in rig.motors do
			if not motor.Parent or not motor.Enabled then continue end
			local base = motor.Transform
			local blended = base
			local touched = false
			for _, track in active do
				local keys = track.clip.channels[key]
				if keys then
					local cf, weight = sample(keys, track.TimePosition)
					blended = blended:Lerp(cf, math.clamp(weight * track.weight, 0, 1))
					touched = true
				end
			end
			if touched then
				rig.previous[motor] = {base = base, written = blended}
				motor.Transform = blended
			end
		end
	end
end)
return PosePlayer
