--!strict
--[[
	Profile - the latest progression snapshot the server sent (ProgressionRemotes.ProfileSync):
	inventory, quests, Field Notes, perks, the Relic and a pending roll, quest markers. Lists live
	here; single HUD values stay in player attributes (State). The UI only reads it
	(Client-Server-Split).

	Edit-mode preview: MockData.profile stands in, so windows can be checked without Play.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local State = require(script.Parent:WaitForChild("State"))
local MockData = require(script.Parent:WaitForChild("MockData"))

local Profile = {}

Profile.data = nil :: { [string]: any }?

local listeners: { [number]: (any) -> () } = {}
local nextId = 0
local started = false

-- Calls `fn(snapshot)` now (if there is one) and after every update. Returns a disconnect.
function Profile.observe(fn: (any) -> ()): () -> ()
	nextId += 1
	local id = nextId
	listeners[id] = fn
	if Profile.data then
		task.spawn(fn, Profile.data)
	end
	return function()
		listeners[id] = nil
	end
end

local function publish(data: any)
	Profile.data = data
	for _, fn in listeners do
		task.spawn(fn, data)
	end
end

function Profile.count(itemId: string): number
	local d = Profile.data
	return if d and d.items then d.items[itemId] or 0 else 0
end

function Profile.start()
	if started then
		return
	end
	started = true
	if not State.live then
		publish((MockData :: any).profile)
		return
	end
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("ProgressionRemotes", 60)
		if not folder then
			return
		end
		local sync = folder:WaitForChild("ProfileSync") :: RemoteEvent
		sync.OnClientEvent:Connect(function(snapshot)
			if typeof(snapshot) == "table" then
				publish(snapshot)
			end
		end)
		;(folder:WaitForChild("RequestSync") :: RemoteEvent):FireServer()
	end)
end

-- a remote by name, or nil in the edit-mode preview
function Profile.remote(name: string): RemoteEvent?
	if not State.live then
		return nil
	end
	local folder = ReplicatedStorage:FindFirstChild("ProgressionRemotes")
	local r = folder and folder:FindFirstChild(name)
	return if r and r:IsA("RemoteEvent") then r else nil
end

function Profile.fire(name: string, ...: any)
	local r = Profile.remote(name)
	if r then
		r:FireServer(...)
	end
end

return Profile
