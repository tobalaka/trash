--!strict
--[[
	Guard - per-player, per-remote rate limiting (a token bucket per key). Every progression
	remote handler calls Guard.allow first (Client-Server-Split: rate limit every C -> S remote).
]]

local Players = game:GetService("Players")

local Guard = {}

type Bucket = { tokens: number, at: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

-- true if `player` may make another `key` request at `perSecond` (bursts up to perSecond)
function Guard.allow(player: Player, key: string, perSecond: number): boolean
	local mine = buckets[player]
	if not mine then
		mine = {}
		buckets[player] = mine
	end
	local now = os.clock()
	local b = mine[key]
	if not b then
		b = { tokens = perSecond, at = now }
		mine[key] = b
	end
	b.tokens = math.min(perSecond, b.tokens + (now - b.at) * perSecond)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return Guard
