--!strict
--[[
	Kit - the UI building blocks every screen shares: instance helpers, the Deepwoken ornate frame,
	the egg-style gloss button and chunky text, Type Soul outline buttons, bars, windows, sunbursts,
	masking tape and 3D item viewports. See Theme for the look this fuses.

	Sizes are authored at 1080p. A scaled root (Kit.scaledRoot) fits them to the screen; UIStroke
	thickness is not scaled by UIScale, so Kit tracks each stroke's base thickness and rescales it.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Exped = require(script.Parent:WaitForChild("Exped"))

local C, F = Theme.Color, Theme.Font
local WHITE = Color3.new(1, 1, 1)

local Kit = {}

-- Current root scale (strokes are created at base * scale) and the reduce-motion setting.
Kit.scale = 1
Exped.getScale = function(): number
	return Kit.scale
end
Kit.reduceMotion = false

local DEFAULTS: { [string]: { [string]: any } } = {
	Frame = { BorderSizePixel = 0 },
	TextLabel = { BorderSizePixel = 0, BackgroundTransparency = 1, TextColor3 = C.Text, FontFace = F.Body, TextSize = 16 },
	TextButton = { BorderSizePixel = 0, BackgroundTransparency = 1, AutoButtonColor = false, Text = "", TextColor3 = C.Text, FontFace = F.Body },
	TextBox = { BorderSizePixel = 0, BackgroundTransparency = 1, TextColor3 = C.Text, FontFace = F.Body, ClearTextOnFocus = false },
	ScrollingFrame = {
		BorderSizePixel = 0,
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = C.SlateLine,
		ScrollBarImageTransparency = 0.3,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	},
	ViewportFrame = { BorderSizePixel = 0, BackgroundTransparency = 1 },
}

-- Creates an instance with class defaults, then props, then children. "Parent" is set last.
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst: any = Instance.new(className)
	local defaults = DEFAULTS[className]
	if defaults then
		for k, v in defaults do
			inst[k] = v
		end
	end
	local parent: Instance? = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.merge(a: { [string]: any }, b: { [string]: any }?): { [string]: any }
	if b then
		for k, v in b do
			a[k] = v
		end
	end
	return a
end

-- ── modifiers ───────────────────────────────────────────────────────────────

function Kit.corner(radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function Kit.round(): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

-- A stroke whose thickness follows the root scale. `textMode` strokes text instead of the border
-- on TextLabels/TextButtons (the egg-style outline).
function Kit.stroke(color: Color3, thickness: number, transparency: number?, onBorder: boolean?): UIStroke
	local s = Kit.new("UIStroke", {
		Color = color,
		Thickness = thickness * Kit.scale,
		Transparency = transparency or 0,
		ApplyStrokeMode = if onBorder then Enum.ApplyStrokeMode.Border else Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
	s:SetAttribute("BaseThickness", thickness)
	return s
end

function Kit.scaleStrokes(root: Instance, scale: number)
	for _, d in root:GetDescendants() do
		if d:IsA("UIStroke") then
			local base = d:GetAttribute("BaseThickness")
			if typeof(base) == "number" then
				d.Thickness = base * scale
			end
		end
	end
end

function Kit.pad(top: number, right: number?, bottom: number?, left: number?): UIPadding
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, top),
		PaddingRight = UDim.new(0, right or top),
		PaddingBottom = UDim.new(0, bottom or top),
		PaddingLeft = UDim.new(0, left or right or top),
	})
end

function Kit.list(axis: string, gap: number, h: Enum.HorizontalAlignment?, v: Enum.VerticalAlignment?): UIListLayout
	return Kit.new("UIListLayout", {
		FillDirection = if axis == "X" then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap),
		HorizontalAlignment = h or Enum.HorizontalAlignment.Left,
		VerticalAlignment = v or Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function Kit.grid(cell: Vector2, gap: Vector2): UIGridLayout
	return Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(cell.X, cell.Y),
		CellPadding = UDim2.fromOffset(gap.X, gap.Y),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

-- Vertical colour gradient (top to bottom).
function Kit.vgrad(top: Color3, bottom: Color3, mid: Color3?): UIGradient
	local seq = if mid
		then ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(0.5, mid), ColorSequenceKeypoint.new(1, bottom) })
		else ColorSequence.new(top, bottom)
	return Kit.new("UIGradient", { Color = seq, Rotation = 90 })
end

-- Multiplies an object's colour from full at the top to `bottom` at the base (glossy shading).
function Kit.shade(bottom: number): UIGradient
	return Kit.vgrad(WHITE, Color3.new(bottom, bottom, bottom))
end

-- Lighten (t > 0) or darken (t < 0) a colour.
function Kit.tint(c: Color3, t: number): Color3
	return if t >= 0 then c:Lerp(WHITE, t) else c:Lerp(Color3.new(0, 0, 0), -t)
end

-- Sheen. 2026-10-25 (EXPED skin): a soft highlight fading down from the top edge instead of the
-- egg-shop diagonal stripes. `strength` is how bright the top edge gets.
function Kit.sheen(parent: GuiObject, radius: number?, strength: number?): Frame
	local top = 1 - (strength or 0.2) * 0.8
	return Kit.new("Frame", {
		Name = "Sheen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		Parent = parent,
	}, {
		Kit.new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, top),
				NumberSequenceKeypoint.new(0.45, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
		Kit.corner(radius or 0),
	})
end

-- ── text ────────────────────────────────────────────────────────────────────

function Kit.label(text: string, font: Font, size: number, color: Color3?, props: { [string]: any }?): any
	return Kit.new("TextLabel", Kit.merge({
		Text = text,
		FontFace = font,
		TextSize = size,
		TextColor3 = color or C.Text,
		Size = UDim2.new(1, 0, 0, size + 4),
	}, props))
end

-- Display text. 2026-10-25 (EXPED skin): heavy Gotham caps with EXPED's soft black stroke and a
-- faint metallic sheen, instead of the fat FredokaOne egg outline. Callers' colours are kept.
function Kit.chunky(text: string, size: number, color: Color3?, props: { [string]: any }?): any
	local l = Kit.label(text, Exped.Font.Heavy, math.floor(size * 0.86 + 0.5), color, props)
	Kit.stroke(C.Ink, math.max(1.2, size * 0.05), 0.35).Parent = l
	Exped.metal(l)
	return l
end

-- HUD text with a soft dark outline so it reads over any sky (Deepwoken top bar).
function Kit.hudText(text: string, font: Font, size: number, color: Color3?, props: { [string]: any }?): any
	local l = Kit.label(text, font, size, color, props)
	Kit.stroke(C.Ink, 1.2, 0.45).Parent = l
	return l
end

-- "-- FEATURED --" section heading.
function Kit.section(text: string, color: Color3, props: { [string]: any }?): any
	return Kit.chunky("-- " .. string.upper(text) .. " --", 40, color, Kit.merge({ Size = UDim2.new(1, 0, 0, 52) }, props))
end

-- ── ornaments ───────────────────────────────────────────────────────────────

export type OrnateOptions = {
	line: Color3?,
	corner: Color3?,
	inset: number?,
	cornerSize: number?,
	noCorners: boolean?,
	lineTransparency: number?,
}

-- Deepwoken frame: a thin outer line, a fainter inset line and small diamond corners.
function Kit.ornate(target: GuiObject, opts: OrnateOptions?)
	local o: OrnateOptions = opts or {}
	local line = o.line or C.SlateLine
	local lt = o.lineTransparency or 0.15
	Kit.stroke(line, 1, lt).Parent = target
	local inset = o.inset or 4
	if inset > 0 then
		Kit.new("Frame", {
			Name = "InnerLine",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(inset, inset),
			Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
			ZIndex = 4,
			Parent = target,
		}, { Kit.stroke(line, 1, math.min(1, lt + 0.45)) })
	end
	if not o.noCorners then
		local cs = o.cornerSize or 9
		for _, p in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
			Kit.new("Frame", {
				Name = "Corner",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(p.X, p.Y),
				Size = UDim2.fromOffset(cs, cs),
				Rotation = 45,
				BackgroundColor3 = o.corner or C.Gold,
				ZIndex = 6,
				Parent = target,
			}, {
				Kit.stroke(C.Ink, 1, 0.1),
				Kit.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0.36, 0.36),
					BackgroundColor3 = C.Ink,
					ZIndex = 6,
				}),
			})
		end
	end
end

-- A horizontal divider that fades out to the right (under setting titles and section headers).
function Kit.divider(color: Color3?, props: { [string]: any }?): any
	return Kit.new("Frame", Kit.merge({
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = color or C.SlateLine,
	}, props), {
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(0.7, 0.6),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
end

-- Masking tape strip (scrapbook touch).
function Kit.tape(parent: Instance, position: UDim2, rotation: number, width: number?): any
	return Kit.new("Frame", {
		Name = "Tape",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(width or 52, 15),
		Rotation = rotation,
		BackgroundColor3 = C.Tape,
		BackgroundTransparency = 0.18,
		ZIndex = 8,
		Parent = parent,
	}, {
		Kit.new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(0.08, 0),
				NumberSequenceKeypoint.new(0.92, 0),
				NumberSequenceKeypoint.new(1, 0.35),
			}),
		}),
	})
end

-- Marker-pen tag ("NEW!", faction tags), slightly rotated.
function Kit.markerTag(text: string, color: Color3, size: number, rotation: number, props: { [string]: any }?): any
	local holder = Kit.new("Frame", Kit.merge({
		Name = "Tag",
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = color,
		Rotation = rotation,
		ZIndex = 9,
	}, props), {
		Kit.corner(3),
		Kit.stroke(C.Ink, 2, 0, true),
		Kit.pad(2, 10, 2, 10),
	})
	Kit.chunky(text, size, C.Text, {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 4),
		ZIndex = 10,
		Parent = holder,
	})
	return holder
end

-- Light rays from a point (egg shop card backgrounds). The parent should clip.
function Kit.sunburst(parent: Instance, center: UDim2, rays: number, length: number, color: Color3, strength: number): any
	local holder = Kit.new("Frame", {
		Name = "Sunburst",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = center,
		Size = UDim2.fromOffset(2, 2),
		Parent = parent,
	})
	local fade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - strength),
		NumberSequenceKeypoint.new(1, 1),
	})
	for i = 0, rays - 1 do
		local pivot = Kit.new("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(length * 2, length * 0.16),
			Rotation = i * 180 / rays,
			Parent = holder,
		})
		-- each pivot carries two opposite rays so one rotated frame draws a full diameter
		for side = 0, 1 do
			Kit.new("Frame", {
				AnchorPoint = Vector2.new(side, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(0.5, 0, 1, 0),
				BackgroundColor3 = color,
				Parent = pivot,
			}, { Kit.new("UIGradient", { Transparency = fade, Rotation = if side == 0 then 0 else 180 }) })
		end
	end
	return holder
end

-- ── interaction ─────────────────────────────────────────────────────────────

function Kit.tween(inst: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

-- Hover grow, press squash and an optional wiggle (egg buttons). `target` gets the UIScale.
function Kit.hover(button: GuiButton, target: GuiObject?, grow: number?, wiggle: number?)
	local t: GuiObject = target or button
	local scale: any = t:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Name = "HoverScale", Parent = t })
	local up = grow or 1.05
	local baseRotation = t.Rotation
	button.MouseEnter:Connect(function()
		if Kit.reduceMotion then
			return
		end
		Kit.tween(scale, Theme.Tween.Fast, { Scale = up })
		if wiggle then
			Kit.tween(t, Theme.Tween.Pop, { Rotation = baseRotation + wiggle })
		end
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(scale, Theme.Tween.Fast, { Scale = 1 })
		if wiggle then
			Kit.tween(t, Theme.Tween.Fast, { Rotation = baseRotation })
		end
	end)
	button.MouseButton1Down:Connect(function()
		if not Kit.reduceMotion then
			Kit.tween(scale, Theme.Tween.Fast, { Scale = 0.93 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		Kit.tween(scale, Theme.Tween.Pop, { Scale = if Kit.reduceMotion then 1 else up })
	end)
end

-- One-shot bounce (currency changes, purchases).
function Kit.pop(target: GuiObject, amount: number?)
	if Kit.reduceMotion then
		return
	end
	local scale: any = target:FindFirstChild("PopScale") or Kit.new("UIScale", { Name = "PopScale", Parent = target })
	scale.Scale = 1 + (amount or 0.18)
	Kit.tween(scale, Theme.Tween.Pop, { Scale = 1 })
end

export type GlossOptions = {
	text: string,
	color: Color3,
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	textSize: number?,
	icon: GuiObject?,
	name: string?,
	layoutOrder: number?,
	parent: Instance?,
	onClick: (() -> ())?,
}

-- Egg / Steal price button: glossy fill, black outline, top shine, diagonal sheen, chunky label.
-- Returns the holder (with drop shadow), the button and the label.
function Kit.gloss(o: GlossOptions): (any, any, any)
	local holder = Kit.new("Frame", {
		Name = o.name or "Gloss",
		Size = o.size,
		Position = o.position or UDim2.new(),
		AnchorPoint = o.anchor or Vector2.zero,
		BackgroundTransparency = 1,
		LayoutOrder = o.layoutOrder or 0,
	})
	-- EXPED button (2026-10-25): a dark slot tinted by the button's colour, silver frame, white text
	local button = Kit.new("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = o.color:Lerp(Color3.new(0, 0, 0), 0.62),
		BackgroundTransparency = 0.05,
		AutoButtonColor = false,
		Text = "",
		Parent = holder,
	}, {
		Kit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)),
		}),
	})
	Exped.frame(button, "Slot", 12, o.color:Lerp(WHITE, 0.6)).ZIndex = 4
	local row = Kit.new("Frame", {
		Name = "Row",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = button,
	}, { Kit.list("X", 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center) })
	if o.icon then
		o.icon.LayoutOrder = 1
		o.icon.ZIndex = 2
		o.icon.Parent = row
	end
	local size = math.floor((o.textSize or 24) * 0.8 + 0.5)
	local label = Exped.text(o.text, size, {
		Name = "Label",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, size + 4),
		LayoutOrder = 2,
		ZIndex = 2,
		Parent = row,
	})
	Kit.hover(button, holder)
	if o.onClick then
		button.Activated:Connect(o.onClick)
	end
	if o.parent then
		holder.Parent = o.parent
	end
	return holder, button, label
end

-- Outline button ("Back", "Next", "[LEARN ALL]"). 2026-10-25 (EXPED skin): a dark slot with the
-- silver frame and white Gotham text; hover lifts the slot a shade.
function Kit.outlineButton(text: string, size: Vector2, props: { [string]: any }?): any
	local b = Kit.new("TextButton", Kit.merge({
		Name = text,
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = Exped.Color.Panel,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = text,
		FontFace = Exped.Font.Bold,
		TextSize = 18,
		TextColor3 = C.Text,
	}, props))
	Exped.stroke(b)
	Exped.frame(b, "Slot", 10)
	local rest = b.BackgroundColor3
	b.MouseEnter:Connect(function()
		Kit.tween(b, Theme.Tween.Fast, { BackgroundColor3 = Color3.fromRGB(58, 58, 62) })
	end)
	b.MouseLeave:Connect(function()
		Kit.tween(b, Theme.Tween.Fast, { BackgroundColor3 = rest })
	end)
	return b
end

-- ── bars ────────────────────────────────────────────────────────────────────

export type BarOptions = {
	size: UDim2,
	color: Color3,
	vertical: boolean?,
	centered: boolean?, -- fills outward from the middle (posture)
	trackColor: Color3?,
	trackTransparency: number?,
	ghostColor: Color3?,
	radius: number?,
	name: string?,
}

export type Bar = {
	root: any,
	fill: any,
	ghost: any,
	fraction: number,
	set: (self: Bar, value: number, max: number, instant: boolean?) -> (),
}

local function barSize(o: BarOptions, f: number): UDim2
	if o.vertical then
		return UDim2.fromScale(1, f)
	end
	return UDim2.fromScale(f, 1)
end

-- A meter with a lagging "ghost" fill that shows recent loss (Deepwoken health).
function Kit.bar(o: BarOptions): Bar
	local anchor = if o.vertical then Vector2.new(0, 1) elseif o.centered then Vector2.new(0.5, 0) else Vector2.zero
	local pos = if o.vertical then UDim2.fromScale(0, 1) elseif o.centered then UDim2.fromScale(0.5, 0) else UDim2.new()
	local radius = o.radius or 0
	local root = Kit.new("Frame", {
		Name = o.name or "Bar",
		Size = o.size,
		BackgroundColor3 = o.trackColor or C.Ink,
		BackgroundTransparency = o.trackTransparency or 0.2,
		ClipsDescendants = true,
	}, { Kit.corner(radius) })
	local ghost = Kit.new("Frame", {
		Name = "Ghost",
		AnchorPoint = anchor,
		Position = pos,
		Size = barSize(o, 1),
		BackgroundColor3 = o.ghostColor or C.PaperHi,
		BackgroundTransparency = 0.25,
		Parent = root,
	}, { Kit.corner(radius) })
	local fill = Kit.new("Frame", {
		Name = "Fill",
		AnchorPoint = anchor,
		Position = pos,
		Size = barSize(o, 1),
		BackgroundColor3 = o.color,
		Parent = root,
	}, {
		Kit.corner(radius),
		Kit.new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Kit.tint(o.color, 0.35)),
				ColorSequenceKeypoint.new(0.45, o.color),
				ColorSequenceKeypoint.new(1, Kit.tint(o.color, -0.3)),
			}),
			Rotation = if o.vertical then 0 else 90,
		}),
	})
	local token = 0
	local bar: Bar = {
		root = root,
		fill = fill,
		ghost = ghost,
		fraction = 1,
		set = function(self: Bar, value: number, max: number, instant: boolean?)
			local f = if max > 0 then math.clamp(value / max, 0, 1) else 0
			local old = self.fraction
			self.fraction = f
			token += 1
			local mine = token
			if instant then
				fill.Size = barSize(o, f)
				ghost.Size = barSize(o, f)
				return
			end
			Kit.tween(fill, Theme.Tween.Fast, { Size = barSize(o, f) })
			if f >= old then
				ghost.Size = barSize(o, f)
			else
				task.delay(0.35, function()
					if token == mine then
						Kit.tween(ghost, Theme.Tween.Ghost, { Size = barSize(o, f) })
					end
				end)
			end
		end,
	}
	return bar
end

-- ── 3D item viewports (Deepwoken "3D icons") ────────────────────────────────

export type ViewportOptions = {
	size: UDim2,
	position: UDim2?,
	anchor: Vector2?,
	yaw: number?,
	pitch: number?,
	fov: number?,
	zoom: number?,
}

function Kit.viewport(model: Model, o: ViewportOptions): any
	local vp = Kit.new("ViewportFrame", {
		Name = "Viewport",
		Size = o.size,
		Position = o.position or UDim2.new(),
		AnchorPoint = o.anchor or Vector2.zero,
		Ambient = Color3.fromRGB(176, 166, 154),
		LightColor = Color3.fromRGB(255, 244, 226),
		LightDirection = Vector3.new(-0.7, -1, -0.6),
	})
	local cam = Instance.new("Camera")
	cam.FieldOfView = o.fov or 28
	cam.Parent = vp
	vp.CurrentCamera = cam
	model.Parent = vp
	local cf, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * (o.zoom or 1.05)
	local dir = CFrame.Angles(0, math.rad(o.yaw or 35), 0) * CFrame.Angles(math.rad(-(o.pitch or 18)), 0, 0)
	cam.CFrame = CFrame.lookAt(cf.Position + dir.LookVector * -dist, cf.Position)
	return vp
end

-- Spins a viewport's model while `active()` is true (hover). Client only.
function Kit.spin(vp: ViewportFrame, active: () -> boolean)
	if not RunService:IsRunning() then
		return
	end
	local model = vp:FindFirstChildOfClass("Model")
	if not model then
		return
	end
	local base = model:GetPivot()
	local angle = 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		if active() then
			angle += dt * 1.6
		elseif angle ~= 0 then
			angle = angle * (1 - math.min(1, dt * 8))
			if math.abs(angle) < 0.01 then
				angle = 0
			end
		else
			return
		end
		model:PivotTo(base * CFrame.Angles(0, angle, 0))
	end)
	vp.Destroying:Once(function()
		conn:Disconnect()
	end)
end

-- ── windows ─────────────────────────────────────────────────────────────────

export type WindowOptions = {
	name: string,
	title: string,
	size: Vector2,
	style: string?, -- "slate" (default), "dark", "parchment"
	header: Color3?, -- egg-style gloss header bar in this colour instead of a title plate
}

export type Window = {
	frame: any,
	body: any,
	close: any,
	scale: UIScale,
}

-- EXPED close: a dark slot with a silver frame and a white brush-stroke X (2026-10-25).
function Kit.closeButton(props: { [string]: any }?): (any, any)
	local holder = Kit.new("Frame", Kit.merge({
		Name = "Close",
		Size = UDim2.fromOffset(36, 36),
		BackgroundTransparency = 1,
		ZIndex = 20,
	}, props))
	local b = Kit.new("TextButton", {
		Name = "Button",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Exped.Color.Panel,
		BackgroundTransparency = 0.15,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 21,
		Parent = holder,
	})
	Exped.frame(b, "Slot", 10).ZIndex = 24
	Exped.icon("Feint", 20, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		ZIndex = 22,
		Parent = b,
	})
	b.MouseEnter:Connect(function()
		Kit.tween(b, Theme.Tween.Fast, { BackgroundColor3 = Exped.Color.Cooldown })
	end)
	b.MouseLeave:Connect(function()
		Kit.tween(b, Theme.Tween.Fast, { BackgroundColor3 = Exped.Color.Panel })
	end)
	Kit.hover(b, holder, 1.08, 0)
	return holder, b
end

function Kit.window(o: WindowOptions): Window
	local style = o.style or "slate"
	local frame = Kit.new("Frame", {
		Name = o.name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(o.size.X, o.size.Y),
		BackgroundColor3 = WHITE,
		Visible = false,
	})
	local scale = Kit.new("UIScale", { Name = "OpenScale", Parent = frame })
	-- EXPED panels (2026-10-25): near-black body, a thin silver ornament frame 9-sliced over it,
	-- white titles with a faint metallic sheen. Parchment windows keep their paper (those screens
	-- print dark ink on it) under the same silver frame.
	if style == "parchment" then
		frame.BackgroundColor3 = C.Paper
		Kit.vgrad(C.PaperHi, C.PaperDark, C.Paper).Parent = frame
	else
		frame.BackgroundColor3 = Exped.Color.Window
		frame.BackgroundTransparency = if style == "dark" then 0.03 else 0.07
		Kit.vgrad(Color3.fromRGB(44, 44, 48), Color3.fromRGB(18, 18, 20)).Parent = frame
	end
	Exped.frame(frame, "Panel", 30, nil, 9).ZIndex = 30

	local top = 28
	local closeHolder, closeButton
	if o.header then
		-- a dark title strip with the window's colour as a thin underline
		local bar = Kit.new("Frame", {
			Name = "Header",
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 52),
			BackgroundColor3 = Exped.Color.PanelDeep,
			BackgroundTransparency = 0.35,
			ZIndex = 2,
			Parent = frame,
		})
		Kit.new("Frame", {
			Name = "Accent",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = o.header,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = bar,
		}, {
			Kit.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.2, 0),
					NumberSequenceKeypoint.new(0.8, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		local title = Exped.text(string.upper(o.title), 28, {
			Name = "Title",
			Position = UDim2.fromOffset(18, 0),
			Size = UDim2.new(1, -90, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
			Parent = bar,
		})
		Exped.metal(title)
		closeHolder, closeButton = Kit.closeButton({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Parent = bar,
		})
		top = 74
	else
		-- EXPED title: centred white caps with a divider that fades at both ends
		local ink = style == "parchment"
		local title = Exped.text(string.upper(o.title), 20, {
			Name = "Title",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.new(1, -120, 0, 24),
			TextColor3 = if ink then C.PaperInk else Exped.Color.Text,
			ZIndex = 11,
			Parent = frame,
		})
		if ink then
			title:FindFirstChildOfClass("UIStroke"):Destroy()
		else
			Exped.metal(title)
		end
		Kit.new("Frame", {
			Name = "TitleRule",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 38),
			Size = UDim2.new(0.7, 0, 0, 1),
			BackgroundColor3 = if ink then C.PaperInk else Exped.Color.Silver,
			BorderSizePixel = 0,
			ZIndex = 11,
			Parent = frame,
		}, {
			Kit.new("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.39, 0),
					NumberSequenceKeypoint.new(0.55, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		-- inset past the frame's corner ornament
		closeHolder, closeButton = Kit.closeButton({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -26, 0, 12),
			Parent = frame,
		})
		top = 48
	end
	local body = Kit.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, top),
		Size = UDim2.new(1, -36, 1, -(top + 18)),
		Parent = frame,
	})
	return { frame = frame, body = body, close = closeButton, scale = scale }
end

-- Fits authored 1080p offsets to the screen: the root is sized 1/scale and scaled by `scale`.
function Kit.scaledRoot(gui: ScreenGui, userScale: () -> number): (any, () -> ())
	local root = Kit.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	local uiScale = Kit.new("UIScale", { Parent = root })
	local function apply()
		local cam = workspace.CurrentCamera
		local vy = if cam then cam.ViewportSize.Y else Theme.DESIGN_HEIGHT
		local s = math.clamp(vy / Theme.DESIGN_HEIGHT, Theme.SCALE_MIN, Theme.SCALE_MAX) * userScale()
		Kit.scale = s
		uiScale.Scale = s
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		Kit.scaleStrokes(root, s)
	end
	apply()
	return root, apply
end

return Kit
