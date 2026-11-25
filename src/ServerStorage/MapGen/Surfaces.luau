--!strict
--[[
	MapGen.Surfaces - MaterialVariants from our generated tiles, set as base-material overrides.

	Overriding a BASE material re-skins every part and mesh that uses it. Ground is shared by
	several regions' ground caps, so the trash texture is a named (non-override) variant that
	GroundBuilder assigns only to the wasteland caps (SURFACES[...].variant).
	  CorrodedMetal -> rust_metal      (chipped teal paint over rust; slum sheet metal)
	  Concrete      -> grime_concrete  (stained, cracked)
	  TRASH_TrashGround (named)        (wasteland ground caps)
	  Fabric        -> patch_panels is NOT used here (patchwork reads better from geometry)
	StudsPerTile is large on terrain-scale surfaces (like the reference world) so tiling never
	reads as a repeating pattern from a distance.
]]

local MaterialService = game:GetService("MaterialService")
local Decor = require(script.Parent.Decor)

local Surfaces = {}

local VARIANTS = {
	{ name = "TRASH_RustMetal", base = Enum.Material.CorrodedMetal, image = "rust_metal", studs = 14, override = true },
	{ name = "TRASH_GrimeConcrete", base = Enum.Material.Concrete, image = "grime_concrete", studs = 22, override = true },
	{ name = "TRASH_TrashGround", base = Enum.Material.Ground, image = "trash_ground", studs = 36, override = false },
	{ name = "TRASH_PatchPanels", base = Enum.Material.DiamondPlate, image = "patch_panels", studs = 30, override = false },
}

function Surfaces.apply(): number
	local n = 0
	for _, v in VARIANTS do
		local img = Decor.image(v.image)
		if not img then
			warn("[MapGen] surfaces: missing image " .. v.image)
			continue
		end
		local mv = MaterialService:FindFirstChild(v.name) :: MaterialVariant?
		if not mv then
			mv = Instance.new("MaterialVariant")
			mv.Name = v.name
			mv.Parent = MaterialService
		end
		local m = mv :: MaterialVariant
		m.BaseMaterial = v.base
		m.ColorMap = img
		m.StudsPerTile = v.studs
		m.MaterialPattern = Enum.MaterialPattern.Organic
		if v.override then
			MaterialService:SetBaseMaterialOverride(v.base, v.name)
		end
		n += 1
	end
	print("[MapGen] surfaces: " .. n .. " material variants")
	return n
end

return Surfaces
