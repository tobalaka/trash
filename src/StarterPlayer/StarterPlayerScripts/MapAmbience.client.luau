--!strict
--[[
	MapAmbience (client) - animates Texture objects tagged "ScrollingTexture" (sludge skins on
	polluted water, drifting smog sheets). Attributes on the Texture: SpeedU, SpeedV (studs/s).
	Only textures within ACTIVE_RANGE of the camera are updated; the list is refreshed once a
	second, so cost stays flat no matter how many pools the map has.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "ScrollingTexture"
local ACTIVE_RANGE = 600

local camera = workspace.CurrentCamera
local active: { Texture } = {}
local refreshTimer = 0

local function refresh()
	table.clear(active)
	local camPos = camera.CFrame.Position
	for _, inst in CollectionService:GetTagged(TAG) do
		if inst:IsA("Texture") and inst.Parent and inst.Parent:IsA("BasePart") then
			local part = inst.Parent :: BasePart
			if (part.Position - camPos).Magnitude < ACTIVE_RANGE + part.Size.Magnitude / 2 then
				table.insert(active, inst)
			end
		end
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	refreshTimer -= dt
	if refreshTimer <= 0 then
		refreshTimer = 1
		refresh()
	end
	for _, tex in active do
		local su = (tex:GetAttribute("SpeedU") :: number?) or 0
		local sv = (tex:GetAttribute("SpeedV") :: number?) or 0
		tex.OffsetStudsU = (tex.OffsetStudsU + su * dt) % tex.StudsPerTileU
		tex.OffsetStudsV = (tex.OffsetStudsV + sv * dt) % tex.StudsPerTileV
	end
end)
