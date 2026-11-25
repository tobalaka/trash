--!strict
--[[
	HQArt.Dress - cheap, map-wide dressing passes on MapGen's generated parts (re-runnable after a rebuild).

	groundMix()  The big ground materials have two painted versions (HQArt.Surfaces: HQ_Sand + HQ_Sand2, ...).
	             Ground parts get version 2 inside large soft patches of a slow interference field (sum of
	             sines over X/Z), so the same tile never repeats across a whole region and the switch happens in
	             broad patches, not part by part like salt and pepper.
	timber()     Posts, jambs, braces get HQ_TimberV (grain along the upright), heads, sills, floor bands,
	             ridges, lintels get HQ_TimberH: no more stacked-plank texture running across a post.
]]

local Dress = {}

local MIX = {
	[Enum.Material.Sand] = "HQ_Sand2",
	[Enum.Material.Grass] = "HQ_Grass2",
	[Enum.Material.Ground] = "HQ_Ground2",
	[Enum.Material.Slate] = "HQ_Stone2",
	[Enum.Material.Snow] = "HQ_Snow2",
	[Enum.Material.Sandstone] = "HQ_Sandstone2",
}

local function field(p: Vector3): number
	return math.sin(p.X * 0.0047 + 1.3) + math.sin(p.Z * 0.0061 + 0.7) + math.sin((p.X + p.Z) * 0.0033 + 2.1)
		+ 0.6 * math.sin((p.X - p.Z) * 0.011 + 4.0)
end

function Dress.groundMix(root: Instance?): number
	local n = 0
	for i, d in (root or workspace.Ground):GetDescendants() do
		if d:IsA("BasePart") then
			local v = MIX[d.Material]
			if v and (d.MaterialVariant == "" or d:GetAttribute("HQMix")) then
				local on = field(d.Position) > 0.35
				d.MaterialVariant = if on then v else ""
				d:SetAttribute("HQMix", on or nil)
				if on then
					n += 1
				end
			end
		end
		if i % 4000 == 0 then
			task.wait()
		end
	end
	return n
end

local UPRIGHT = { Post = true, Jamb = true, Brace = true, Pilaster = true }
local BEAM = { Head = true, Sill = true, Band = true, Ridge = true, Lintel = true, Beam = true, Crown = true, TrimDark = true }

function Dress.timber(root: Instance?): number
	local n = 0
	for i, d in (root or workspace.World):GetDescendants() do
		if d:IsA("BasePart") and d.Material == Enum.Material.WoodPlanks and d.MaterialVariant == "" then
			if UPRIGHT[d.Name] then
				d.MaterialVariant = "HQ_TimberV"
				n += 1
			elseif BEAM[d.Name] then
				d.MaterialVariant = "HQ_TimberH"
				n += 1
			end
		end
		if i % 4000 == 0 then
			task.wait()
		end
	end
	return n
end

return Dress
