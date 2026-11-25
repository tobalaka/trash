--!strict
--[[
	State - the read-only values the UI shows. The server owns them (Client-Server-Split); the UI
	never writes gameplay state.

	Live play: the LocalPlayer's replicated attributes (names in Theme.Attr) and its Humanoid.
	Edit-mode preview (no LocalPlayer): MockData.player, and observers fire once.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local MockData = require(script.Parent:WaitForChild("MockData"))

local State = {}

State.live = RunService:IsRunning() and Players.LocalPlayer ~= nil

local mock = MockData.player :: { [string]: any }

function State.get(attr: string): any
	if State.live then
		return (Players.LocalPlayer :: Player):GetAttribute(attr)
	end
	return mock[attr]
end

function State.number(attr: string, default: number): number
	local v = State.get(attr)
	return if typeof(v) == "number" then v else default
end

function State.string(attr: string, default: string): string
	local v = State.get(attr)
	return if typeof(v) == "string" and v ~= "" then v else default
end

-- Max for a meter: "<Name>Max" if the server sets it, else Theme.DEFAULT_MAX.
function State.max(attr: string): number
	return State.number(attr .. "Max", Theme.DEFAULT_MAX)
end

-- Calls `fn` now and on every change. Returns a disconnect function.
function State.observe(attr: string, fn: (any) -> ()): () -> ()
	fn(State.get(attr))
	if not State.live then
		return function() end
	end
	local player = Players.LocalPlayer :: Player
	local a = player:GetAttributeChangedSignal(attr):Connect(function()
		fn(State.get(attr))
	end)
	local b = player:GetAttributeChangedSignal(attr .. "Max"):Connect(function()
		fn(State.get(attr))
	end)
	return function()
		a:Disconnect()
		b:Disconnect()
	end
end

-- Calls `fn(health, maxHealth)` for the current Humanoid, across respawns.
function State.observeHealth(fn: (number, number) -> ())
	if not State.live then
		fn(mock.Health, mock.MaxHealth)
		return
	end
	local player = Players.LocalPlayer :: Player
	local conns: { RBXScriptConnection } = {}
	local function hook(character: Model)
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		local hum = humanoid :: Humanoid
		local function push()
			fn(hum.Health, hum.MaxHealth)
		end
		table.insert(conns, hum.HealthChanged:Connect(push))
		table.insert(conns, hum:GetPropertyChangedSignal("MaxHealth"):Connect(push))
		push()
	end
	if player.Character then
		task.spawn(hook, player.Character)
	end
	player.CharacterAdded:Connect(hook)
end

function State.displayName(): string
	if State.live then
		return (Players.LocalPlayer :: Player).DisplayName
	end
	return mock.DisplayName
end

-- Seconds left on an ability cooldown ("CooldownEnd_<Key>" holds a server time).
function State.cooldownLeft(key: string): number
	if not State.live then
		return (MockData.cooldowns :: { [string]: number })[key] or 0
	end
	local ends = State.get(Theme.Attr.CooldownPrefix .. key)
	if typeof(ends) ~= "number" then
		return 0
	end
	return math.max(0, ends - workspace:GetServerTimeNow())
end

return State
