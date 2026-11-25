--!strict
--[[
	Icons - small vector icons drawn with Frames (no uploaded images). Each icon is a square
	container; shapes are placed in scale units so one icon works at any size.

	Icons.make(name, size, color, cutout) draws one icon; `cutout` is the colour of holes (the
	background it sits on). Icons.shadowed adds the chunky dark drop copy the egg-style tiles use.
]]

local Kit = require(script.Parent:WaitForChild("Kit"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local C = Theme.Color

local Icons = {}

type Painter = (canvas: Frame, size: number, color: Color3, cutout: Color3) -> ()

local function piece(canvas: Instance, color: Color3, x: number, y: number, w: number, h: number, props: { [string]: any }?): any
	return Kit.new("Frame", Kit.merge({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
		Parent = canvas,
	}, props))
end

local function rounded(f: Instance, radiusScale: number, size: number)
	Kit.corner(radiusScale * size).Parent = f
end

local function circle(f: Instance)
	Kit.round().Parent = f
end

local painters: { [string]: Painter } = {
	-- inventory: a satchel with a ring handle and buckle
	bag = function(canvas, size, color, cutout)
		local ring = piece(canvas, color, 0.5, 0.3, 0.4, 0.36, { BackgroundTransparency = 1 })
		circle(ring)
		Kit.stroke(color, size * 0.085).Parent = ring
		rounded(piece(canvas, color, 0.5, 0.64, 0.78, 0.58), 0.16, size)
		rounded(piece(canvas, Kit.tint(color, -0.22), 0.5, 0.45, 0.78, 0.16), 0.06, size)
		rounded(piece(canvas, cutout, 0.5, 0.56, 0.16, 0.14), 0.03, size)
	end,
	-- settings: a cog
	gear = function(canvas, size, color, cutout)
		for i = 0, 3 do
			rounded(piece(canvas, color, 0.5, 0.5, 0.2, 0.9, { Rotation = i * 45 }), 0.04, size)
		end
		circle(piece(canvas, color, 0.5, 0.5, 0.68, 0.68))
		circle(piece(canvas, cutout, 0.5, 0.5, 0.28, 0.28))
	end,
	-- world map: three folded panels
	map = function(canvas, size, color, cutout)
		local dark = Kit.tint(color, -0.25)
		piece(canvas, color, 0.24, 0.47, 0.25, 0.7)
		piece(canvas, dark, 0.5, 0.53, 0.26, 0.7)
		piece(canvas, color, 0.76, 0.47, 0.25, 0.7)
		circle(piece(canvas, cutout, 0.5, 0.46, 0.14, 0.14))
	end,
	-- journal: an open book with a bookmark
	book = function(canvas, size, color, cutout)
		rounded(piece(canvas, color, 0.29, 0.52, 0.4, 0.66, { Rotation = -6 }), 0.04, size)
		rounded(piece(canvas, color, 0.71, 0.52, 0.4, 0.66, { Rotation = 6 }), 0.04, size)
		piece(canvas, cutout, 0.5, 0.52, 0.05, 0.66)
		for i = 0, 2 do
			piece(canvas, cutout, 0.29, 0.36 + i * 0.13, 0.26, 0.04, { Rotation = -6, BackgroundTransparency = 0.4 })
		end
		piece(canvas, Kit.tint(color, -0.35), 0.74, 0.22, 0.08, 0.3)
	end,
	-- air quality: a leaf with a centre vein
	leaf = function(canvas, size, color, cutout)
		rounded(piece(canvas, color, 0.5, 0.48, 0.5, 0.78, { Rotation = 40 }), 0.24, size)
		piece(canvas, cutout, 0.5, 0.5, 0.05, 0.62, { Rotation = 40, BackgroundTransparency = 0.3 })
	end,
	-- skill paths: rising bars
	skills = function(canvas, size, color, _cutout)
		for i, h in { 0.36, 0.56, 0.8 } do
			local f = piece(canvas, color, 0.22 + (i - 1) * 0.28, 0.9, 0.2, h, { AnchorPoint = Vector2.new(0.5, 1) })
			rounded(f, 0.04, size)
		end
	end,
	-- shop: a stall with a scalloped awning
	shop = function(canvas, size, color, cutout)
		local dark = Kit.tint(color, -0.25)
		rounded(piece(canvas, dark, 0.5, 0.66, 0.74, 0.5), 0.05, size)
		rounded(piece(canvas, cutout, 0.5, 0.75, 0.22, 0.32), 0.03, size)
		rounded(piece(canvas, color, 0.5, 0.24, 0.9, 0.16), 0.04, size)
		for i = 0, 3 do
			circle(piece(canvas, if i % 2 == 0 then color else dark, 0.17 + i * 0.22, 0.34, 0.22, 0.22))
		end
	end,
	-- vitality: a heart
	heart = function(canvas, _size, color, _cutout)
		circle(piece(canvas, color, 0.3, 0.38, 0.5, 0.5))
		circle(piece(canvas, color, 0.7, 0.38, 0.5, 0.5))
		piece(canvas, color, 0.5, 0.58, 0.5, 0.5, { Rotation = 45 })
	end,
	-- thirst: a drop
	drop = function(canvas, _size, color, _cutout)
		circle(piece(canvas, color, 0.5, 0.62, 0.66, 0.66))
		piece(canvas, color, 0.5, 0.47, 0.4, 0.4, { Rotation = 45 })
	end,
	-- hunger: a steaming bowl
	bowl = function(canvas, size, color, _cutout)
		local clip = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.4),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Parent = canvas,
		})
		circle(piece(clip, color, 0.5, 0, 1, 2))
		rounded(piece(canvas, color, 0.5, 0.5, 0.94, 0.1), 0.05, size)
		for i, x in { 0.38, 0.62 } do
			rounded(piece(canvas, color, x, 0.27 - (i - 1) * 0.04, 0.08, 0.22, { BackgroundTransparency = 0.35 }), 0.04, size)
		end
	end,
	-- scrap: a hex nut (three rotated rectangles make a hexagon)
	nut = function(canvas, _size, color, cutout)
		for i = 0, 2 do
			piece(canvas, color, 0.5, 0.5, 0.44, 0.76, { Rotation = 90 + i * 60 })
		end
		circle(piece(canvas, cutout, 0.5, 0.5, 0.32, 0.32))
	end,
	-- Robux price mark: a hexagon ring with a square core
	robux = function(canvas, size, color, cutout)
		for i = 0, 2 do
			rounded(piece(canvas, color, 0.5, 0.5, 0.5, 0.86, { Rotation = 90 + i * 60 }), 0.04, size)
		end
		for i = 0, 2 do
			piece(canvas, cutout, 0.5, 0.5, 0.3, 0.52, { Rotation = 90 + i * 60 })
		end
		rounded(piece(canvas, color, 0.5, 0.5, 0.26, 0.26), 0.03, size)
	end,
	-- anima residue: a faceted crystal
	crystal = function(canvas, _size, color, _cutout)
		piece(canvas, color, 0.5, 0.5, 0.58, 0.58, { Rotation = 45 })
		piece(canvas, Kit.tint(color, 0.45), 0.42, 0.42, 0.2, 0.2, { Rotation = 45 })
	end,
	-- dollars: a coin
	coin = function(canvas, size, color, _cutout)
		circle(piece(canvas, color, 0.5, 0.5, 0.88, 0.88))
		local ring = piece(canvas, color, 0.5, 0.5, 0.64, 0.64, { BackgroundTransparency = 1 })
		circle(ring)
		Kit.stroke(Kit.tint(color, -0.3), size * 0.05).Parent = ring
		Kit.label("$", Theme.Font.Display, size * 0.5, Kit.tint(color, -0.45), {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(1, 1),
			Parent = canvas,
		})
	end,
	-- locked ability
	lock = function(canvas, size, color, cutout)
		local ring = piece(canvas, color, 0.5, 0.36, 0.44, 0.5, { BackgroundTransparency = 1 })
		rounded(ring, 0.22, size)
		Kit.stroke(color, size * 0.09).Parent = ring
		rounded(piece(canvas, color, 0.5, 0.68, 0.68, 0.46), 0.08, size)
		circle(piece(canvas, cutout, 0.5, 0.64, 0.14, 0.14))
	end,
	-- map marker: a chevron over a dot, pointing up
	arrow = function(canvas, size, color, _cutout)
		rounded(piece(canvas, color, 0.37, 0.42, 0.16, 0.56, { Rotation = 35 }), 0.06, size)
		rounded(piece(canvas, color, 0.63, 0.42, 0.16, 0.56, { Rotation = -35 }), 0.06, size)
		circle(piece(canvas, color, 0.5, 0.78, 0.24, 0.24))
	end,
	-- roll: a wheel trailing speed streaks
	roll = function(canvas, size, color, cutout)
		for i, w in { 0.24, 0.34, 0.24 } do
			rounded(piece(canvas, color, 0.44, 0.32 + (i - 1) * 0.18, w, 0.09, { AnchorPoint = Vector2.new(1, 0.5) }), 0.04, size)
		end
		circle(piece(canvas, color, 0.68, 0.5, 0.5, 0.5))
		local hub = piece(canvas, color, 0.68, 0.5, 0.28, 0.28, { BackgroundTransparency = 1 })
		circle(hub)
		Kit.stroke(cutout, size * 0.06).Parent = hub
	end,
	-- parry: a shield with a centre ridge
	shield = function(canvas, size, color, _cutout)
		rounded(piece(canvas, color, 0.5, 0.36, 0.7, 0.46), 0.08, size)
		piece(canvas, color, 0.5, 0.56, 0.5, 0.5, { Rotation = 45 })
		rounded(piece(canvas, Kit.tint(color, -0.3), 0.5, 0.5, 0.08, 0.62), 0.04, size)
	end,
	-- uppercut: two rising chevrons
	uppercut = function(canvas, size, color, _cutout)
		for i, y in { 0.4, 0.68 } do
			local t = if i == 1 then 0 else 0.4
			rounded(piece(canvas, color, 0.39, y, 0.15, 0.42, { Rotation = 45, BackgroundTransparency = t }), 0.06, size)
			rounded(piece(canvas, color, 0.61, y, 0.15, 0.42, { Rotation = -45, BackgroundTransparency = t }), 0.06, size)
		end
	end,
}

function Icons.make(name: string, size: number, color: Color3, cutout: Color3?): any
	local canvas = Kit.new("Frame", {
		Name = "Icon_" .. name,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	})
	local painter = painters[name]
	if painter then
		painter(canvas, size, color, cutout or C.Ink)
	end
	return canvas
end

-- Icon with a solid drop copy underneath (egg-style chunky icons).
function Icons.shadowed(name: string, size: number, color: Color3, cutout: Color3?, shadow: Color3?): any
	local holder = Kit.new("Frame", {
		Name = "Icon_" .. name,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	})
	local back = Icons.make(name, size, shadow or C.Ink, shadow or C.Ink)
	back.Position = UDim2.fromOffset(0, math.max(2, size * 0.07))
	back.Parent = holder
	for _, d in back:GetDescendants() do
		if d:IsA("Frame") and d.BackgroundTransparency < 1 then
			d.BackgroundTransparency = math.max(d.BackgroundTransparency, 0.35)
		end
	end
	local front = Icons.make(name, size, color, cutout)
	front.Parent = holder
	return holder
end

return Icons
