--!strict
-- Movement and combat keys (02-Systems/Input/Keybinds). The UI uses Tab K M P O and 1-0;
-- the custom shiftlock toggles on LeftAlt.

local Keys = {
	Sprint = Enum.KeyCode.LeftShift, -- hold
	SprintTap = Enum.KeyCode.W, -- double-tap and hold
	Crouch = Enum.KeyCode.LeftControl, -- hold; slide while sprinting; drop off a wall; Ctrl + Mouse1 = uppercut
	Roll = Enum.KeyCode.Q,
	Jump = Enum.KeyCode.Space, -- in the air: wall jump / mantle / wall climb / double jump; on the ground: vault
	Block = Enum.KeyCode.F,
	Grab = Enum.KeyCode.G, -- hold, then W / A / S / D picks the throw
	Attack = Enum.UserInputType.MouseButton1, -- in the air: aerial slam
	Feint = Enum.UserInputType.MouseButton2,
	-- B grips a nearby knocked target when GripReady; otherwise it uses the Relic ultimate.
	Crit = Enum.KeyCode.T,
	Grip = Enum.KeyCode.B, -- execute a knocked enemy in reach
	Carry = Enum.KeyCode.V, -- pick a knocked body up; again to set it down
}

return Keys
