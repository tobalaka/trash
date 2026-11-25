--!strict
--[[
	Action - the one move a character is performing right now: Roll, Slide, Vault, Mantle,
	WallBounce, Attack or Uppercut. Kept in the character's "Action" attribute, set by this
	client only (not replicated), so Locomotion, Movement and CombatController can read it
	without requiring each other. The server's own view is the "CombatState" attribute.
]]

local Action = {}

local tokens: { [Model]: {} } = setmetatable({}, { __mode = "k" }) :: any

function Action.get(character: Model): string?
	local a = character:GetAttribute("Action")
	return if typeof(a) == "string" then a else nil
end

-- Starts `name`; it clears itself after `duration` unless another action replaced it first.
function Action.set(character: Model, name: string, duration: number?): {}
	local token = {}
	tokens[character] = token
	character:SetAttribute("Action", name)
	if duration then
		task.delay(duration, function()
			Action.clear(character, token)
		end)
	end
	return token
end

function Action.clear(character: Model, token: {})
	if tokens[character] == token then
		tokens[character] = nil
		character:SetAttribute("Action", nil)
	end
end

return Action
