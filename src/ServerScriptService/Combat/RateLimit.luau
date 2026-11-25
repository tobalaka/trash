--!strict
-- RateLimit - per-player, per-remote request budget over a rolling one-second window.

local Players = game:GetService("Players")

local RateLimit = {}

type Bucket = { count: number, start: number }

local buckets: { [Player]: { [string]: Bucket } } = {}

function RateLimit.allow(player: Player, key: string, perSecond: number): boolean
	local now = os.clock()
	local own = buckets[player]
	if not own then
		own = {}
		buckets[player] = own
	end
	local bucket = own[key]
	if not bucket or now - bucket.start >= 1 then
		own[key] = { count = 1, start = now }
		return true
	end
	if bucket.count >= perSecond then
		return false
	end
	bucket.count += 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return RateLimit
