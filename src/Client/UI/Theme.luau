--!strict
-- Visual identity: cartoon Roblox style.
--
-- Four ingredients, applied everywhere:
--   * a LIGHT inner stroke (this is what gives the "sticker" look) and a
--     BLACK outer stroke,
--   * a vertical light -> dark gradient, for the volume,
--   * a solid shadow offset downward: the "plastic" relief,
--   * a COLOR PER FUNCTION, saturated. Two buttons that don't do the same
--     thing must never share a color.
--
-- IMPORTANT: no size, color or font should be hardcoded anywhere else.

local TweenService = game:GetService("TweenService")

local Theme = {}

----------------------------------------------------------------------
-- Scales. Pick from these, never invent an in-between value.

Theme.Space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 }
Theme.Radius = { sm = 8, md = 14, lg = 20, xl = 26 }
Theme.Line = { thin = 2, base = 3, thick = 4 }
Theme.TextSize = { caption = 12, small = 14, body = 16, title = 21, display = 28 }
Theme.Control = { sm = 36, md = 48, lg = 64 }
Theme.Icon = { button = 76, glyph = 34 }

Theme.Colors = {
	Panel = Color3.fromRGB(46, 52, 98),
	PanelDeep = Color3.fromRGB(30, 34, 68),
	Card = Color3.fromRGB(66, 74, 130),
	Outline = Color3.fromRGB(16, 18, 38),
	Scrim = Color3.fromRGB(8, 9, 20),
	Inner = Color3.fromRGB(255, 255, 255), -- the light inner stroke
	Menu = Color3.fromRGB(146, 74, 222), -- modal window background
	MenuInner = Color3.fromRGB(116, 56, 182), -- the well cut into a window
	Light = Color3.fromRGB(244, 246, 252), -- capsule background

	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(176, 184, 226),

	Accent = Color3.fromRGB(72, 214, 255),
	Credit = Color3.fromRGB(255, 206, 84),
	Valid = Color3.fromRGB(88, 214, 120),
	Invalid = Color3.fromRGB(255, 94, 94),
	Heat = Color3.fromRGB(255, 138, 76),
}

-- One color per function. This is what makes a cluster of buttons readable
-- at a glance, without reading the labels.
Theme.Function = {
	Build = Color3.fromRGB(78, 176, 255),
	Demolish = Color3.fromRGB(255, 88, 88),
	Lobby = Color3.fromRGB(170, 116, 255),
	Money = Color3.fromRGB(74, 206, 96),
	Info = Color3.fromRGB(255, 186, 62),
	Move = Color3.fromRGB(56, 191, 199),
	Rebirth = Color3.fromRGB(230, 90, 200),
	Ultimate = Color3.fromRGB(255, 205, 60),
}

-- Lighting for the 3D thumbnails. A ViewportFrame has its OWN lighting,
-- independent of Lighting -- this is what lets a module thumbnail read
-- clearly while the scene itself is nearly black (Ambient at 0.05).
Theme.Label = {
	-- Beyond this, nothing renders: neighbouring stations sit 900 studs
	-- away and shouldn't paper the sky with text.
	MaxDistance = 150,
	Clearance = 2.5, -- studs between a module's top and its label
}

Theme.Viewport = {
	Ambient = Color3.fromRGB(150, 158, 180),
	Light = Color3.fromRGB(255, 252, 245),
	Direction = Vector3.new(-0.45, -1, -0.6),
	FieldOfView = 26,
}

Theme.Font = {
	-- FredokaOne: the round, thick face seen all over Roblox.
	Display = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
}

Theme.Tween = {
	Snap = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Pop = TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	Slide = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
}

----------------------------------------------------------------------

function Theme.lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

function Theme.darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

-- Creates an instance, applies properties, then parents last -- avoids
-- ever rendering a half-configured instance.
function Theme.new(className: string, props: { [string]: any }, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

function Theme.corner(radius: number?): UICorner
	return Theme.new("UICorner", { CornerRadius = UDim.new(0, radius or Theme.Radius.md) })
end

function Theme.stroke(color: Color3?, thickness: number?): UIStroke
	return Theme.new("UIStroke", {
		Color = color or Theme.Colors.Outline,
		Thickness = thickness or Theme.Line.base,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

-- Text outline: without it, white text bleeds into light backgrounds.
function Theme.textStroke(thickness: number?): UIStroke
	return Theme.new("UIStroke", {
		Color = Theme.Colors.Outline,
		Thickness = thickness or Theme.Line.thin,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Theme.gradient(base: Color3, strength: number?): UIGradient
	local amount = strength or 0.22
	return Theme.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Theme.lighten(base, amount), Theme.darken(base, amount * 0.7)),
	})
end

function Theme.padding(px: number?): UIPadding
	local offset = UDim.new(0, px or Theme.Space.lg)
	return Theme.new("UIPadding", {
		PaddingTop = offset,
		PaddingBottom = offset,
		PaddingLeft = offset,
		PaddingRight = offset,
	})
end

----------------------------------------------------------------------
-- Text

local function makeLabel(size: number, color: Color3, props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = size,
		TextColor3 = color,
	}
	for key, value in props do
		merged[key] = value
	end
	return Theme.new("TextLabel", merged, { Theme.textStroke() })
end

function Theme.title(props: { [string]: any }): TextLabel
	return makeLabel(Theme.TextSize.title, Theme.Colors.Text, props)
end

function Theme.body(props: { [string]: any }): TextLabel
	return makeLabel(Theme.TextSize.body, Theme.Colors.Text, props)
end

function Theme.caption(props: { [string]: any }): TextLabel
	return makeLabel(Theme.TextSize.caption, Theme.Colors.TextDim, props)
end

-- The one text style with no outline: long-form descriptions.
function Theme.prose(props: { [string]: any }): TextLabel
	local merged: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.small,
		TextColor3 = Theme.Colors.TextDim,
	}
	for key, value in props do
		merged[key] = value
	end
	return Theme.new("TextLabel", merged)
end

----------------------------------------------------------------------

-- `Inner = true` adds the light inner trim. Same treatment as the buttons:
-- without it a panel doesn't read as part of the same visual family as the
-- rest of the interface.
function Theme.panel(props: { [string]: any }, children: { Instance }?): Frame
	local color = props.BackgroundColor3 or Theme.Colors.Panel
	local radius = props.Radius or Theme.Radius.lg
	local inner = props.Inner
	local strokeColor, strokeThickness = props.StrokeColor, props.StrokeThickness
	props.Radius, props.Inner, props.StrokeColor, props.StrokeThickness = nil, nil, nil, nil

	local decorations = {
		Theme.corner(radius),
		Theme.stroke(strokeColor, strokeThickness),
		Theme.gradient(color, 0.16),
	}

	if inner then
		table.insert(
			decorations,
			Theme.new("Frame", {
				Name = "Inner",
				Size = UDim2.new(1, -Theme.Line.thick * 2, 1, -Theme.Line.thick * 2),
				Position = UDim2.fromOffset(Theme.Line.thick, Theme.Line.thick),
				BackgroundTransparency = 1,
			}, {
				Theme.corner(radius - Theme.Line.thin),
				Theme.stroke(Theme.Colors.Inner, Theme.Line.thin),
			})
		)
	end
	if children then
		for _, child in children do
			table.insert(decorations, child)
		end
	end

	props.BackgroundColor3 = color
	return Theme.new("Frame", props, decorations)
end

export type Chunky = {
	Root: Frame,
	Face: TextButton,
	Shadow: Frame,
	SetColor: (Chunky, Color3) -> (),
	SetLifted: (Chunky, boolean) -> (),
}

-- "Raised" button: a solid shadow underneath, a face on top. `inner` adds
-- the light stroke that gives the sticker look.
function Theme.chunky(props: { [string]: any }, children: { Instance }?): Chunky
	local color = props.BackgroundColor3 or Theme.Colors.Card
	local radius = props.Radius or Theme.Radius.md
	local depth = props.Depth or 6
	local inner = props.Inner
	props.Radius, props.Depth, props.BackgroundColor3, props.Inner = nil, nil, nil, nil

	local root = Theme.new("Frame", props)
	root.BackgroundTransparency = 1

	local shadow = Theme.new("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 1, -depth),
		BackgroundColor3 = Theme.darken(color, 0.45),
		Parent = root,
	}, { Theme.corner(radius), Theme.stroke() })

	local gradient = Theme.gradient(color)
	local outerStroke = Theme.stroke()
	local face = Theme.new("TextButton", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, 0, 1, -depth),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Text = "",
		Parent = root,
	}, { Theme.corner(radius), outerStroke, gradient })

	-- The light trim is an inner frame, not a UIStroke: two strokes can't
	-- stack on the same instance.
	if inner then
		Theme.new("Frame", {
			Name = "Inner",
			Size = UDim2.new(1, -Theme.Line.thick * 2, 1, -Theme.Line.thick * 2),
			Position = UDim2.fromOffset(Theme.Line.thick, Theme.Line.thick),
			BackgroundTransparency = 1,
			Parent = face,
		}, {
			Theme.corner(radius - Theme.Line.thin),
			Theme.stroke(Theme.Colors.Inner, Theme.Line.base),
		})
	end

	if children then
		for _, child in children do
			child.Parent = face
		end
	end

	local obj = {} :: any
	obj.Root, obj.Face, obj.Shadow = root, face, shadow
	obj._lifted = false

	function obj:SetColor(newColor: Color3)
		face.BackgroundColor3 = newColor
		shadow.BackgroundColor3 = Theme.darken(newColor, 0.45)
		gradient.Color =
			ColorSequence.new(Theme.lighten(newColor, 0.22), Theme.darken(newColor, 0.154))
	end

	function obj:SetLifted(lifted: boolean)
		obj._lifted = lifted
		outerStroke.Color = if lifted then Theme.Colors.Accent else Theme.Colors.Outline
		outerStroke.Thickness = if lifted then Theme.Line.thick else Theme.Line.base
		TweenService:Create(face, Theme.Tween.Snap, {
			Position = UDim2.new(0.5, 0, 0, if lifted then -2 else 0),
		}):Play()
	end

	face.MouseEnter:Connect(function()
		if not obj._lifted then
			TweenService:Create(face, Theme.Tween.Snap, {
				Position = UDim2.new(0.5, 0, 0, -2),
			}):Play()
		end
	end)
	face.MouseLeave:Connect(function()
		if not obj._lifted then
			TweenService:Create(face, Theme.Tween.Snap, {
				Position = UDim2.fromScale(0.5, 0),
			}):Play()
		end
	end)
	face.MouseButton1Down:Connect(function()
		face.Position = UDim2.new(0.5, 0, 0, depth)
	end)
	face.MouseButton1Up:Connect(function()
		TweenService:Create(face, Theme.Tween.Snap, {
			Position = UDim2.new(0.5, 0, 0, if obj._lifted then -2 else 0),
		}):Play()
	end)

	return obj
end

----------------------------------------------------------------------
-- Icon button: a colored square, the icon centered, the caption BELOW it
-- rather than inside -- this is what lets a cluster of buttons sit in a
-- corner without the labels running into each other.

export type IconButton = {
	Root: Frame,
	Button: Chunky,
	SetColor: (IconButton, Color3) -> (),
	SetLifted: (IconButton, boolean) -> (),
	SetBadge: (IconButton, string?) -> (),
}

function Theme.iconButton(config: { [string]: any }): IconButton
	local size = config.Size or Theme.Icon.button
	local color = config.Color or Theme.Function.Build
	local captionHeight = 20

	local root = Theme.new("Frame", {
		Name = config.Name or "IconButton",
		AnchorPoint = config.AnchorPoint,
		Position = config.Position,
		Size = UDim2.fromOffset(size, size + captionHeight),
		BackgroundTransparency = 1,
		LayoutOrder = config.LayoutOrder,
	})

	-- The icon is an IMAGE when one is supplied, otherwise a character.
	-- Swapping an icon pack for emoji (or the reverse) only means filling
	-- in or clearing the Image field of the call.
	local glyph: GuiObject
	if config.Image then
		glyph = Theme.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromScale(0.62, 0.62),
			BackgroundTransparency = 1,
			Image = config.Image,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		glyph = Theme.body({
			Name = "Icon",
			Size = UDim2.fromScale(1, 1),
			TextSize = config.GlyphSize or Theme.Icon.glyph,
			Text = config.Icon or "?",
		})
	end

	local badgeLabel = Theme.body({
		Size = UDim2.fromScale(1, 1),
		TextSize = Theme.TextSize.caption - 1,
		Text = "",
	})
	local badge = Theme.new("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(size - 16, 18),
		BackgroundColor3 = Theme.Colors.Invalid,
		Visible = false,
		ZIndex = 3,
	}, { Theme.corner(9), Theme.stroke(nil, Theme.Line.thin), badgeLabel })

	local button = Theme.chunky({
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		Radius = Theme.Radius.lg,
		Inner = true,
		Parent = root,
	}, { glyph, badge })

	local caption = Theme.body({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 12, 0, captionHeight),
		TextSize = Theme.TextSize.small,
		Text = config.Caption or "",
		Parent = root,
	});
	(caption :: any).TextStrokeTransparency = 1

	local obj = {} :: any
	obj.Root, obj.Button, obj.Caption = root, button, caption

	function obj:SetColor(newColor: Color3)
		button:SetColor(newColor)
	end
	function obj:SetLifted(lifted: boolean)
		button:SetLifted(lifted)
	end
	function obj:SetBadge(text: string?)
		badge.Visible = text ~= nil
		badgeLabel.Text = text or ""
	end

	return obj
end

----------------------------------------------------------------------
-- Value capsule: light background, round icon on the left, big number.
-- The light background is deliberate: against a black sky, it's what
-- catches the eye first.

export type Capsule = { Root: Frame, Value: TextLabel, Action: TextButton }

function Theme.capsule(config: { [string]: any }): Capsule
	local color = config.Color or Theme.Function.Money
	local width = config.Width or 240
	local height = config.Height or 52

	local icon = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(height - 8, height - 8),
		BackgroundColor3 = color,
	}, {
		Theme.corner((height - 8) / 2),
		Theme.stroke(nil, Theme.Line.base),
		Theme.gradient(color, 0.3),
		(if config.Image
			then Theme.new("ImageLabel", {
				Name = "Icon",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.68, 0.68),
				BackgroundTransparency = 1,
				Image = config.Image,
				ScaleType = Enum.ScaleType.Fit,
			})
			else Theme.body({
				Name = "Icon",
				Size = UDim2.fromScale(1, 1),
				TextSize = Theme.TextSize.title,
				Text = config.Icon or "$",
			})),
	})

	local value = Theme.body({
		Position = UDim2.fromOffset(height + 4, 0),
		Size = UDim2.new(1, -(height + height + 4), 1, 0),
		TextSize = Theme.TextSize.title,
		TextColor3 = Theme.darken(color, 0.35),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Value or "0",
	});
	(value :: any).TextStrokeTransparency = 1
	local stroke = value:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = Theme.Colors.Inner
		stroke.Thickness = Theme.Line.thin
	end

	local action = Theme.new("TextButton", {
		Name = "Action",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(height - 16, height - 16),
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.title,
		TextColor3 = Theme.Colors.Text,
		Text = "+",
	}, {
		Theme.corner((height - 16) / 2),
		Theme.stroke(nil, Theme.Line.base),
		Theme.gradient(color, 0.3),
		Theme.textStroke(),
	})

	local root = Theme.new("Frame", {
		Name = config.Name or "Capsule",
		AnchorPoint = config.AnchorPoint,
		Position = config.Position,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Color3.fromRGB(244, 246, 252),
		Parent = config.Parent,
	}, {
		Theme.corner(height / 2),
		Theme.stroke(nil, Theme.Line.thick),
		icon,
		value,
		action,
	})

	return { Root = root, Value = value, Action = action } :: any
end

----------------------------------------------------------------------

export type Gauge =
	{ Root: Frame, SetRatio: (Gauge, number) -> (), SetColor: (Gauge, Color3) -> () }

function Theme.gauge(props: { [string]: any }, color: Color3): Gauge
	local fill = Theme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, { Theme.corner(Theme.Radius.sm), Theme.gradient(color, 0.3) })

	local radius = props.Radius or Theme.Radius.sm
	props.Radius = nil
	props.BackgroundColor3 = Theme.Colors.Scrim

	local root = Theme.new("Frame", props, {
		Theme.corner(radius),
		Theme.stroke(nil, Theme.Line.thin),
		Theme.new("Frame", {
			Name = "Clip",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, { Theme.corner(radius), fill }),
	})

	local obj = {} :: any
	obj.Root = root
	function obj:SetRatio(ratio: number)
		TweenService:Create(fill, Theme.Tween.Snap, {
			Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1),
		}):Play()
	end
	function obj:SetColor(newColor: Color3)
		fill.BackgroundColor3 = newColor
	end
	return obj
end

----------------------------------------------------------------------
-- Gauge pill: same family as Theme.capsule, light background and a thick
-- stroke. Each measurement is its own INDEPENDENT capsule rather than a row
-- in one big panel -- this is what keeps the HUD airy.

export type GaugePill = {
	Root: Frame,
	Gauge: Gauge,
	Value: TextLabel,
	SetColor: (GaugePill, Color3) -> (),
}

function Theme.gaugePill(config: { [string]: any }): GaugePill
	local color = config.Color or Theme.Colors.Accent
	local width = config.Width or 280
	local height = config.Height or 46
	local disc = height - 10

	local icon = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 5, 0.5, 0),
		Size = UDim2.fromOffset(disc, disc),
		BackgroundColor3 = color,
	}, {
		Theme.corner(disc / 2),
		Theme.stroke(nil, Theme.Line.base),
		Theme.gradient(color, 0.3),
		Theme.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.66, 0.66),
			BackgroundTransparency = 1,
			Image = config.Image or "",
			ScaleType = Enum.ScaleType.Fit,
		}),
	})

	-- On a light background labels have no outline: it would muddy the
	-- reading instead of serving it.
	local label = Theme.new("TextLabel", {
		Position = UDim2.fromOffset(disc + 12, 0),
		Size = UDim2.new(0, 68, 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.caption,
		TextColor3 = Color3.fromRGB(96, 104, 128),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = config.Caption or "",
	})

	local value = Theme.new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0, 66, 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.caption,
		TextColor3 = Theme.darken(color, 0.4),
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = "—",
	})

	local barLeft = disc + 12 + 68 + 6
	local gauge = Theme.gauge({
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, barLeft, 0.5, 0),
		Size = UDim2.new(1, -(barLeft + 66 + 18), 0, 12),
	}, color)

	local root = Theme.new("Frame", {
		Name = config.Name or "GaugePill",
		AnchorPoint = config.AnchorPoint,
		Position = config.Position,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Theme.Colors.Light,
		Visible = config.Visible,
		Parent = config.Parent,
	}, {
		Theme.corner(height / 2),
		Theme.stroke(nil, Theme.Line.thick),
		icon,
		label,
		gauge.Root,
		value,
	})

	local obj = {} :: any
	obj.Root, obj.Gauge, obj.Value = root, gauge, value
	function obj:SetColor(newColor: Color3)
		gauge:SetColor(newColor)
		value.TextColor3 = Theme.darken(newColor, 0.4)
	end
	return obj
end

----------------------------------------------------------------------

-- Floating label above a world object.
--
-- AlwaysOnTop stays FALSE: a label that pierces geometry turns a dense
-- station into text soup. It's fine for a module to hide the name of the
-- one behind it -- that's exactly what makes the depth readable.
function Theme.worldLabel(adornee: BasePart, text: string, offsetY: number): BillboardGui
	return Theme.new("BillboardGui", {
		Name = "Label",
		Adornee = adornee,
		Size = UDim2.fromOffset(180, 26),
		StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0),
		MaxDistance = Theme.Label.MaxDistance,
		AlwaysOnTop = false,
		LightInfluence = 0,
	}, {
		Theme.body({
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			Text = text,
		}),
	})
end

-- 3D thumbnail of a model, to show the object itself rather than a generic
-- icon. The model is cloned: the thumbnail shares nothing with the
-- original, so ten can be shown at once with no risk.
function Theme.modelThumb(template: Model, props: { [string]: any }): ViewportFrame
	local merged: { [string]: any } = {
		Name = "Thumb",
		BackgroundTransparency = 1,
		Ambient = Theme.Viewport.Ambient,
		LightColor = Theme.Viewport.Light,
		LightDirection = Theme.Viewport.Direction,
	}
	for key, value in props do
		merged[key] = value
	end

	local viewport = Theme.new("ViewportFrame", merged) :: ViewportFrame

	local model = template:Clone()
	model.Parent = viewport

	local camera = Theme.new("Camera", {
		FieldOfView = Theme.Viewport.FieldOfView,
		Parent = viewport,
	}) :: Camera
	viewport.CurrentCamera = camera

	-- Automatic framing: pull back along a diagonal until the bounding
	-- sphere fits the field of view. Works for a 1x1 the same as a 2x2 with
	-- chimneys, with no per-module tuning.
	local center, size = model:GetBoundingBox()
	local distance = (size.Magnitude / 2) / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local direction = Vector3.new(1, 0.62, 1).Unit
	camera.CFrame = CFrame.lookAt(center.Position + direction * distance, center.Position)

	return viewport
end

return Theme
