--!strict
--[[
	Pollution - the server's air quality, 0 (clean) to 100 (smog), replicated as the Workspace
	attribute "Pollution" for the HUD's air bar (vault: Pollution).

	It creeps up on its own (the city never stops dumping), jumps with every Sky Dump, and moves
	with how the Heap handles its waste: sorting and purifying bring it down most, stripping
	least, smelting pushes it up (Config.Environment.DELTA). At or above POLLUTION_HIGH the dome
	is in smog: survival drains faster and Smoglings crawl out more often. At or below
	POLLUTION_LOW skies are clear and every pile yields more.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Environment = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Environment"))

local PUBLISH_STEP = 0.1 -- only republish when the shown value moves this much

local Pollution = {}

local value = Environment.POLLUTION_START
local shown = -1

local function publish()
	local rounded = math.floor(value * 10 + 0.5) / 10
	if math.abs(rounded - shown) >= PUBLISH_STEP then
		shown = rounded
		workspace:SetAttribute("Pollution", rounded)
		local state = if value >= Environment.POLLUTION_HIGH then "Smog" elseif value <= Environment.POLLUTION_LOW then "Clear" else "Hazy"
		if workspace:GetAttribute("AirState") ~= state then
			workspace:SetAttribute("AirState", state)
		end
	end
end

function Pollution.get(): number
	return value
end

function Pollution.add(delta: number)
	value = math.clamp(value + delta, Environment.POLLUTION_MIN, Environment.POLLUTION_MAX)
	publish()
end

-- by a DELTA key (Sort, Strip, Purify, Smelt, Dump, ...)
function Pollution.apply(key: string, times: number?)
	local d = Environment.DELTA[key]
	if d then
		Pollution.add(d * (times or 1))
	end
end

function Pollution.isHigh(): boolean
	return value >= Environment.POLLUTION_HIGH
end

function Pollution.isLow(): boolean
	return value <= Environment.POLLUTION_LOW
end

function Pollution.start()
	workspace:SetAttribute("PollutionHigh", Environment.POLLUTION_HIGH)
	workspace:SetAttribute("PollutionLow", Environment.POLLUTION_LOW)
	publish()
	task.spawn(function()
		while true do
			task.wait(10)
			Pollution.add(Environment.POLLUTION_DRIFT / 6)
		end
	end)
end

return Pollution
