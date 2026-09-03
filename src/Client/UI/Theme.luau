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

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Client and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach.
local function fromShared(path: string): any
	if game then
		local node: any = (game :: any):GetService("ReplicatedStorage").Shared
		for segment in path:gmatch("[^/]+") do
			node = node[segment]
		end
		return node
	end
	return "../../Shared/" .. path
end

local Icons = require(fromShared("Icons"))

local Theme = {}

----------------------------------------------------------------------
-- Scales. Pick from these, never invent an in-between value.

Theme.Space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32 }
Theme.Radius = { sm = 8, md = 14, lg = 20, xl = 26 }
Theme.Line = { thin = 2, base = 3, thick = 4 }
Theme.TextSize = { caption = 12, small = 14, body = 16, title = 21, display = 28 }
Theme.Control = { sm = 36, md = 48, lg = 64 }
-- `button` grew from 76 the moment the caption moved onto the tile: the strip
-- under it is gone, so a bigger tile still takes LESS room in the column than
-- the old tile-plus-label did.
Theme.Icon = { button = 88, glyph = 34 }

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

-- Tinted surfaces.
--
-- A capsule takes the colour of what it measures instead of one shared neutral:
-- with four of them stacked down the left edge, the tint is what lets a glance
-- land on the right one before a single label has been read.
--
-- The tint is heavy -- the surface stays near-white -- and that is the point. A
-- saturated panel under dark text throws away the contrast the reading depends
-- on, and four saturated panels in a column fight each other instead of
-- separating.
Theme.Surface = {
	-- Enough colour to read as coloured. Higher and the surface washes out to
	-- white; lower and dark text starts fighting the background it sits on.
	Tint = 0.55,

	-- Which motif fills a surface: "stars", "stripes", "grid" or "dots". One
	-- word, and every capsule, pill and banner follows.
	Motif = "stars",

	MarkTransparency = 0.82, -- a motif you can read is noise, not texture
	MarkShade = 0.3, -- how far a mark is darkened from its surface colour

	-- The starfield. Sparse and irregular on purpose: a tiled icon repeats as a
	-- recognisable picture and the eye starts counting the copies, which is what
	-- made the first attempt at an icon motif unusable. Scattered glyphs at
	-- three sizes and three shapes never line up, so they read as sky.
	StarSpacing = 44, -- pixels between star centres, along the width
	StarSizeMin = 9,
	StarSizeMax = 17,
	StarTransparency = 0.84,
	-- Fixed, so the scatter is the same every session. A field that reshuffles
	-- on each respawn reads as a glitch.
	StarSeed = 20260825,

	StripePitch = 15, -- pixels between diagonal bands, measured along the width
	StripeWidth = 5,
	StripeAngle = 45,

	GridPitch = 14,
	GridWidth = 2,

	DotPitch = 16,
	DotSize = 4,
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
	-- The research zone. Ice cyan rather than another blue-green: Move's teal
	-- is muted and Build's blue is saturated, and this has to be told apart
	-- from both at icon size with no label under it.
	Research = Color3.fromRGB(120, 240, 255),
}

-- Windows are dark GLASS, not painted panels.
--
-- Roblox has no backdrop blur for a GuiObject, so the effect is built from the
-- two things it does have: a near-black body at high transparency, and the
-- lighter inner rim `Theme.panel` already draws. The scene showing through IS
-- the frosting -- on a station of neon trim and coloured hulls there is always
-- something behind the glass to catch.
--
-- Near-black rather than pure black: a true 0,0,0 body kills the colour coming
-- through it and the panel reads as a hole rather than as a pane.
Theme.Glass = {
	Color = Color3.fromRGB(10, 11, 24),
	-- The window body. High enough to see the station move behind it.
	Body = 0.38,
	-- The well cut into it. DENSER, not lighter: a recess is the part of the
	-- pane you can see least through, and that is what reads as depth.
	Well = 0.16,
}

-- The weapon selector's slot, and the band it claims at the bottom centre.
--
-- `Reserve` is published so the things that ALSO live at the bottom centre --
-- BuildPanel's active-tool band, both toasts -- can stack above it instead of
-- landing on it. One source of truth beats four hand-tuned offsets.
Theme.Hotbar = {
	Slot = 80,
	Reserve = 80 + 8,
}

-- Emoji fallback for a read-out with no artwork.
--
-- The HUD is labelled from the icon pack (`Icons`), which is what makes it look
-- of a piece with the rest of the game. These stay as the cheap way to stand a
-- new read-out up before an icon has been chosen for it, and as the answer if a
-- Creator Store id is ever moderated away and the ImageLabel goes blank.
Theme.Glyph = {
	Credits = "💰",
	Income = "📈",
	Power = "⚡",
	Heat = "🔥",
	Sun = "☀️",
	Modules = "🛰️",
}

-- Lighting for the 3D thumbnails. A ViewportFrame has its OWN lighting,
-- independent of Lighting -- this is what lets a module thumbnail read
-- clearly while the scene itself is nearly black (Ambient at 0.05).
Theme.Label = {
	-- Beyond this, nothing renders: neighbouring stations sit 900 studs
	-- away and shouldn't paper the sky with text.
	MaxDistance = 150,
	Clearance = 2.5, -- studs between a module's top and its label
	Width = 260,
	Height = 30,
	Glyph = 22,
}

----------------------------------------------------------------------
-- Words
--
-- No string a player can read is written in a view (DEVELOPMENT.md). Anything
-- that has to be renamed, translated or reworded is a data change here, not a
-- hunt through the controllers.
--
-- The rest of the interface has not been migrated yet: BuildPanel and
-- HudController still hold their strings inline. New text goes here.

Theme.Words = {
	-- The research exchange. Every string the panel shows lives here, so the
	-- zone can be renamed or translated without opening a view.
	Research = {
		Title = "Zone de recherche",
		Subtitle = "Échange des minerais extraits de la mine",
		Button = "Recherche",
		Close = "Fermer",
		SellAll = "Tout échanger",
		Sell = "Échanger",
		Empty = "Aucun minerai. Descends dans la mine pour en extraire.",
		Locked = "Zone de recherche verrouillée. Marche sur le pad au bord du deck pour l'ouvrir.",
		Total = function(amount: number): string
			return `Valeur totale : {amount} ¢`
		end,
		Held = function(count: number): string
			return `x{count}`
		end,
		UnitValue = function(value: number): string
			return `{value} ¢ l'unité`
		end,
		Sold = function(amount: number): string
			return `+{amount} ¢`
		end,
		Depth = function(depth: number): string
			return `Terrasse {depth}`
		end,
		-- The sections the panel does not fill yet. Named rather than left
		-- blank so the shape of what is coming is visible in one place.
		SoonTitle = "Bientôt",
		Soon = "Foreuse, raffinage et réparation de la fusée.",
	},

	EclipseIncoming = function(seconds: number): string
		return `Éclipse dans : {seconds}s`
	end,
	EclipseActive = function(seconds: number): string
		return `Éclipse en cours : {seconds}s`
	end,
	-- Level, not "Nv. 1 of 5": a player reads the ceiling off the MAX badge
	-- when it appears, and does not need it before then.
	ModuleLabel = function(name: string, level: number): string
		return `{name}  Nv.{level}`
	end,
	UpgradeCost = function(cost: number): string
		return `{cost}`
	end,
	UpgradeMaxed = "MAX",

	-- The caption sitting above each HUD bar. Short and uppercase: it is read
	-- once, to learn which bar is which, and skipped on every glance after.
	Gauge = {
		Credits = "CRÉDITS",
		Power = "ÉNERGIE",
		Heat = "CHALEUR",
		Sun = "EXPOSITION",
	},

	-- The figure on a gauge's head line. Produced against the same capacity the
	-- bar's ratio uses, so the number and the fill can never disagree.
	Ratio = function(current: number, capacity: number): string
		return `{math.floor(current)} / {math.floor(capacity)}`
	end,
	SunLit = "SOLEIL",
	SunDark = "ÉCLIPSE",

	-- The build window's own title and its accent line. A window that only
	-- names itself makes the player work out what it is for; one line in the
	-- accent colour answers that before they have read a single card.
	BuildTitle = "CONSTRUCTION",
	BuildHint = "Choisis un module, puis pose-le sur la grille.",

	-- A balance grouped in thousands. Past four digits an unbroken run of
	-- numerals stops being a quantity and becomes a serial number -- the player
	-- has to count the digits to know whether they can afford anything.
	--
	-- The separator is a narrow no-break space (U+202F), the French convention,
	-- and no-break so the grouping can never wrap mid-figure.
	Amount = function(value: number): string
		local digits = tostring(math.floor(math.abs(value)))
		local grouped = ""
		for index = #digits, 1, -1 do
			local place = #digits - index
			if place > 0 and place % 3 == 0 then
				grouped = "\u{202F}" .. grouped
			end
			grouped = digits:sub(index, index) .. grouped
		end
		return if value < 0 then `-{grouped}` else grouped
	end,
	Income = function(rate: number): string
		return `Revenu : {string.format("%.1f", rate)} cr/s`
	end,
	ModuleCount = function(count: number): string
		return if count <= 1 then `{count} module` else `{count} modules`
	end,
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

-- The background a surface of this function colour sits on.
function Theme.surface(color: Color3): Color3
	return Theme.lighten(color, Theme.Surface.Tint)
end

-- Background motifs.
--
-- Generated out of frames rather than tiled from an image. Every pattern
-- texture on the Creator Store belongs to someone else and can be moderated
-- away -- Icons.luau already carries that warning, and a motif that vanishes
-- takes the texture of the whole HUD with it. Generating it also means the
-- marks take the surface's own colour instead of being tinted approximations of
-- someone else's PNG.
--
-- HOW THE ROUNDED ENDS ARE HANDLED
--
-- ClipsDescendants clips to the RECTANGLE, not to the rounded corners, so a
-- full-bleed motif cannot simply be clipped by the capsule -- it would square
-- off both ends. Two answers, and which one applies depends on the motif:
--
--   * marks that are POINTS (dots) are tested against the stadium outline and
--     dropped when they fall outside it;
--   * marks that are LINES (stripes, grid) are drawn into a band inset by the
--     corner radius, which is a plain rectangle and so clips exactly. The two
--     rounded caps stay clear, which reads as deliberate margin.

local function markProps(color: Color3): { [string]: any }
	return {
		BackgroundColor3 = Theme.darken(color, Theme.Surface.MarkShade),
		BackgroundTransparency = Theme.Surface.MarkTransparency,
		BorderSizePixel = 0,
	}
end

-- The clipped middle of a capsule: everything between the two rounded caps.
local function motifBand(width: number, height: number, radius: number, marks: { Instance }): Frame
	local inset = math.min(radius, width / 2)
	return Theme.new("Frame", {
		Name = "Pattern",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(inset, 0),
		Size = UDim2.fromOffset(math.max(0, width - inset * 2), height),
		ClipsDescendants = true,
	}, marks) :: Frame
end

local function stripeMarks(color: Color3, width: number, height: number, radius: number): Frame
	local pitch = Theme.Surface.StripePitch
	local band = math.max(0, width - math.min(radius, width / 2) * 2)
	local marks: { Instance } = {}

	-- A band rotated off the vertical reaches sideways by half the height on
	-- each side, so the run starts and ends a height beyond the visible strip --
	-- otherwise the first and last stripes are cut short of the edges.
	local first = -height
	local last = band + height

	local index = 0
	while first + index * pitch <= last do
		local props = markProps(color)
		props.Name = "Stripe"
		props.AnchorPoint = Vector2.new(0.5, 0.5)
		props.Position = UDim2.fromOffset(first + index * pitch, height / 2)
		props.Size = UDim2.fromOffset(Theme.Surface.StripeWidth, height * 2.5)
		props.Rotation = Theme.Surface.StripeAngle
		table.insert(marks, Theme.new("Frame", props))
		index += 1
	end

	return motifBand(width, height, radius, marks)
end

local function gridMarks(color: Color3, width: number, height: number, radius: number): Frame
	local pitch = Theme.Surface.GridPitch
	local thickness = Theme.Surface.GridWidth
	local band = math.max(0, width - math.min(radius, width / 2) * 2)
	local marks: { Instance } = {}

	for index = 0, math.floor(band / pitch) do
		local props = markProps(color)
		props.Name = "GridX"
		props.Position = UDim2.fromOffset(index * pitch, 0)
		props.Size = UDim2.fromOffset(thickness, height)
		table.insert(marks, Theme.new("Frame", props))
	end

	for index = 0, math.floor(height / pitch) do
		local props = markProps(color)
		props.Name = "GridY"
		props.Position = UDim2.fromOffset(0, index * pitch)
		props.Size = UDim2.fromOffset(band, thickness)
		table.insert(marks, Theme.new("Frame", props))
	end

	return motifBand(width, height, radius, marks)
end

local function dotMarks(color: Color3, width: number, height: number, radius: number): Frame
	local pitch = Theme.Surface.DotPitch
	local size = Theme.Surface.DotSize
	local margin = size

	local leftCentre = math.min(radius, width / 2)
	local rightCentre = width - leftCentre
	local midY = height / 2

	local function inside(x: number, y: number): boolean
		local cx = if x < leftCentre then leftCentre elseif x > rightCentre then rightCentre else nil
		if cx then
			local dx, dy = x - cx, y - midY
			return dx * dx + dy * dy <= (leftCentre - margin) ^ 2
		end
		return y >= margin and y <= height - margin
	end

	local marks: { Instance } = {}
	local rows = math.max(1, math.floor(height / pitch))
	local columns = math.max(1, math.floor(width / pitch))

	for row = 0, rows - 1 do
		local y = (height - (rows - 1) * pitch) / 2 + row * pitch
		-- Rows staggered by half a pitch: a square grid of dots reads as a grid,
		-- an offset one reads as texture.
		local stagger = if row % 2 == 1 then pitch / 2 else 0
		for column = 0, columns - 1 do
			local x = (width - (columns - 1) * pitch) / 2 + column * pitch + stagger
			if inside(x, y) then
				local props = markProps(color)
				props.Name = "Dot"
				props.AnchorPoint = Vector2.new(0.5, 0.5)
				props.Position = UDim2.fromOffset(x, y)
				props.Size = UDim2.fromOffset(size, size)
				table.insert(marks, Theme.new("Frame", props, { Theme.corner(size / 2) }))
			end
		end
	end

	return Theme.new("Frame", {
		Name = "Pattern",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height),
	}, marks) :: Frame
end

-- Three shapes, cycled. One glyph repeated at one size is the thing that made
-- the earlier tiled-icon attempt read as wallpaper instead of as texture.
local STAR_GLYPHS = {
	Icons.Stars["Star"],
	Icons.Stars["Star2"],
	Icons.Stars["Star3"],
}

local function starMarks(
	color: Color3,
	width: number,
	height: number,
	radius: number,
	density: number?
): Frame
	local surface = Theme.Surface

	-- `density` shrinks the grid AND the marks together: half the spacing at
	-- half the size is the same field seen from twice as far, which is what
	-- "smaller motifs" actually means. Default 1 leaves every existing surface
	-- exactly as it was.
	local scale = density or 1
	local spacing = surface.StarSpacing * scale
	local sizeMin = math.max(2, math.floor(surface.StarSizeMin * scale))
	local sizeMax = math.max(sizeMin, math.floor(surface.StarSizeMax * scale))

	-- The seed is offset by the surface's own colour. Three gauge pills share a
	-- size and a base seed, so one fixed seed put an identical star at an
	-- identical spot on all three -- which reads as a rendering artefact rather
	-- than as texture. Deriving it from the colour keeps each field stable
	-- between sessions while making them different from each other.
	local hue = math.floor(color.R * 255) * 7
		+ math.floor(color.G * 255) * 13
		+ math.floor(color.B * 255) * 17
	local rng = Random.new(surface.StarSeed + hue)
	local shade = Theme.darken(color, surface.MarkShade)

	-- A star is a POINT, so one that falls outside the rounded shape is dropped
	-- rather than clipped: ClipsDescendants clips to the RECTANGLE, which would
	-- square off the very corners this is trying to respect.
	--
	-- Rounded-RECTANGLE test, which collapses to the old stadium one when the
	-- radius is half the height -- so every capsule keeps the field it had. It
	-- had to be generalised because the button tiles are square: assuming a
	-- stadium there carved one out of an 88px tile and threw away every mark
	-- near the top and bottom corners.
	local r = math.min(radius, width / 2, height / 2)

	local function inside(x: number, y: number, size: number): boolean
		local half = size / 2
		local cx = if x < r then r elseif x > width - r then width - r else nil
		local cy = if y < r then r elseif y > height - r then height - r else nil
		if cx and cy then
			local dx, dy = x - cx, y - cy
			return dx * dx + dy * dy <= (r - half) ^ 2
		end
		if cx then
			return x - half >= 0 and x + half <= width
		end
		return y - half >= 0 and y + half <= height
	end

	local marks: { Instance } = {}
	local columns = math.max(2, math.floor(width / spacing))
	local step = width / columns

	-- ROWS as well as columns, once the surface is tall enough to hold them.
	-- A capsule is one row high and keeps the single jittered line it always
	-- had; a square tile needs a grid, or its "field" is one line of stars
	-- across the middle and nothing anywhere else.
	local rows = math.max(1, math.floor(height / spacing))
	local rowStep = height / rows

	for row = 0, rows - 1 do
		for column = 0, columns - 1 do
			-- A jittered cell rather than a free scatter: free placement
			-- clumps, and a clump in a 46px pill looks like a smudge.
			local x = (column + 0.5) * step + rng:NextNumber(-step * 0.3, step * 0.3)
			local y = if rows == 1
				then rng:NextNumber(height * 0.22, height * 0.78)
				else (row + 0.5) * rowStep + rng:NextNumber(-rowStep * 0.3, rowStep * 0.3)
			local size = rng:NextInteger(sizeMin, sizeMax)

			if inside(x, y, size) then
				table.insert(
					marks,
					Theme.new("ImageLabel", {
						Name = "Star",
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(x, y),
						Size = UDim2.fromOffset(size, size),
						Rotation = rng:NextInteger(-30, 30),
						BackgroundTransparency = 1,
						Image = STAR_GLYPHS[(column + row) % #STAR_GLYPHS + 1],
						ImageColor3 = shade,
						-- The small ones sit further back, which is what stops
						-- the field reading as one flat layer of stickers.
						ImageTransparency = surface.StarTransparency
							+ (sizeMax - size) / sizeMax * 0.08,
						ScaleType = Enum.ScaleType.Fit,
					})
				)
			end
		end
	end

	return Theme.new("Frame", {
		Name = "Pattern",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height),
	}, marks) :: Frame
end

-- The optional fifth argument is the density scalar. Only the starfield reads
-- it; the geometric motifs have their own pitch in Theme.Surface and ignore it.
local MOTIFS: { [string]: (Color3, number, number, number, number?) -> Frame } = {
	stars = starMarks,
	stripes = stripeMarks,
	grid = gridMarks,
	dots = dotMarks,
}

-- The motif for the inside of a surface, per Theme.Surface.Motif.
-- `density` scales the field down: 0.5 is twice as many marks at half the size.
-- Omit it for the capsules, which are tuned at 1.
function Theme.motif(
	color: Color3,
	width: number,
	height: number,
	radius: number,
	density: number?
): Frame
	local build = MOTIFS[Theme.Surface.Motif] or starMarks
	return build(color, width, height, radius, density)
end

-- Repaints an existing motif, for a surface whose colour changes with its state.
-- Handles both mark kinds: the geometric motifs are frames tinted through their
-- background, the starfield is images tinted through ImageColor3.
function Theme.recolourMotif(field: Frame, color: Color3)
	local shade = Theme.darken(color, Theme.Surface.MarkShade)
	for _, mark in field:GetChildren() do
		if mark:IsA("ImageLabel") then
			mark.ImageColor3 = shade
		elseif mark:IsA("Frame") then
			mark.BackgroundColor3 = shade
		end
	end
end

-- Brings a motif forward by `amount`.
--
-- `Theme.Surface.StarTransparency` is tuned for the near-white capsules, where
-- 0.84 is exactly enough. On a saturated button tile or inside a gauge's dark
-- track the same value renders nothing at all -- and an invisible texture is
-- pure cost. Per-surface rather than global, because the capsules are right.
function Theme.emphasiseMotif(field: Frame, amount: number)
	for _, mark in field:GetChildren() do
		if mark:IsA("ImageLabel") then
			mark.ImageTransparency = math.clamp(mark.ImageTransparency - amount, 0, 1)
		elseif mark:IsA("Frame") then
			mark.BackgroundTransparency = math.clamp(mark.BackgroundTransparency - amount, 0, 1)
		end
	end
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
				-- A LIGHTENED TINT OF THE SURFACE, not pure white.
				--
				-- White read as a hard rim drawn around everything -- on the
				-- build window it was a 5px halo that fought the black outline
				-- for the edge. The reference images do carry an inner line,
				-- but it is always the object's own colour lifted a notch, so
				-- it reads as a lit edge rather than as a second border.
				Theme.stroke(Theme.lighten(color, 0.4), Theme.Line.thin),
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
	-- FLAT by default: one rounded shape with a black outline, nothing behind
	-- it. The solid drop shadow that used to sit under every face read as a
	-- SECOND button peeking out from under the first -- which is what it
	-- literally is. The reference images use a single shape and put all the
	-- relief in the outline and the gradient.
	--
	-- Still a parameter, because a caller that genuinely wants the raised
	-- plastic look can ask; nothing in the interface does today.
	local depth = props.Depth or 0
	local inner = props.Inner
	-- How heavy the black outline is. Optional, because it is the one thing a
	-- caller might want louder than the shared default: a big standalone tile
	-- carries a thicker line than a card packed into a grid.
	local line = props.Stroke or Theme.Line.base
	props.Radius, props.Depth, props.BackgroundColor3, props.Inner, props.Stroke =
		nil, nil, nil, nil, nil

	local root = Theme.new("Frame", props)
	root.BackgroundTransparency = 1

	local shadow = Theme.new("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.new(1, 0, 1, -depth),
		BackgroundColor3 = Theme.darken(color, 0.45),
		-- Kept in the tree rather than skipped: SetColor writes to it, and a
		-- caller can still ask for depth. It simply has nothing to show when
		-- the face covers it exactly.
		Visible = depth > 0,
		Parent = root,
	}, { Theme.corner(radius), Theme.stroke(nil, line) })

	local gradient = Theme.gradient(color)
	local outerStroke = Theme.stroke(nil, line)
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
			-- Same rule as Theme.panel: the object's own colour lifted, never
			-- white. See the note there.
			Theme.stroke(Theme.lighten(color, 0.4), Theme.Line.thin),
		})
	end

	if children then
		for _, child in children do
			child.Parent = face
		end
	end

	-- Press feedback, now that there is no depth to sink into. A flat button
	-- that does not answer the finger feels broken, and the shrink is the
	-- flat-design equivalent of the face dropping onto its shadow.
	local press = Theme.new("UIScale", { Scale = 1, Parent = root })

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
		outerStroke.Thickness = if lifted then line + 1 else line
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
		TweenService:Create(press, Theme.Tween.Snap, { Scale = 1 }):Play()
		if not obj._lifted then
			TweenService:Create(face, Theme.Tween.Snap, {
				Position = UDim2.fromScale(0.5, 0),
			}):Play()
		end
	end)
	face.MouseButton1Down:Connect(function()
		face.Position = UDim2.new(0.5, 0, 0, depth)
		press.Scale = 0.94
	end)
	face.MouseButton1Up:Connect(function()
		TweenService:Create(face, Theme.Tween.Snap, {
			Position = UDim2.new(0.5, 0, 0, if obj._lifted then -2 else 0),
		}):Play()
		TweenService:Create(press, Theme.Tween.Snap, { Scale = 1 }):Play()
	end)

	return obj
end

----------------------------------------------------------------------
-- Icon button: a coloured tile, the icon large inside it, the label ON the
-- tile along its bottom edge.
--
-- The label used to hang BELOW the tile, on its own strip. That strip was 20px
-- of nothing per button, it made the clickable target smaller than the space
-- the button occupied, and a floating word under a square reads as a caption
-- for a picture rather than as the name of a control.
--
-- Inside, over a heavy black outline, the whole tile becomes one object: it is
-- the thing you press, and the word on it is what it does. That is what the
-- polished simulators on the platform all do, and why their buttons read from
-- across the screen at a size where ours needed squinting.

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
	-- A button whose artwork says it on its own drops the word entirely and
	-- gives the whole tile to the icon. Pass no Caption to get that.
	--
	-- It is a real choice, not a shortcut: a labelled tile and a bare one read
	-- as two different KINDS of control, which is worth something when the bare
	-- one is the button that wipes the station.
	local hasCaption = config.Caption ~= nil and config.Caption ~= ""
	-- `Bare` strips the tile down to its artwork: no face, no shadow, no
	-- outline, no inner trim -- just the icon, floating. The chunky is still
	-- built underneath, invisible, because it is what carries the press
	-- animation and the `Face.Activated` event every caller is wired to.
	local bare = config.Bare == true
	-- The band along the bottom of the tile the label sits in. The icon is
	-- centred in what is left, not in the tile: centring it in the tile puts it
	-- behind the word.
	local captionHeight = if hasCaption then config.CaptionHeight or 24 else 0

	local root = Theme.new("Frame", {
		Name = config.Name or "IconButton",
		AnchorPoint = config.AnchorPoint,
		Position = config.Position,
		Size = UDim2.fromOffset(size, size),
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
			-- Centred in the space ABOVE the label band, and bigger than it
			-- was: the artwork is what identifies the button at a glance.
			-- Scaled against the FACE, which is shorter than the tile by the
			-- shadow depth -- 0.66 measured against `size` overlapped the
			-- label band by three pixels.
			Position = UDim2.new(0.5, 0, 0, (size - captionHeight) / 2),
			Size = UDim2.fromScale(
				if bare then 0.94 elseif hasCaption then 0.54 else 0.72,
				if bare then 0.94 elseif hasCaption then 0.54 else 0.72
			),
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

	-- Built as a list rather than inline, because the caption is optional and a
	-- nil in the middle of an array literal leaves a hole the child loop cannot
	-- be trusted to walk past.
	local faceChildren: { Instance } = {}

	-- A starfield behind the artwork, in a darker shade of the tile's own
	-- colour. It is what keeps a big flat tile from reading as a coloured
	-- rectangle -- the same texture the capsules and the banner already carry,
	-- so the dock finally belongs to the same family.
	--
	-- Only on a tile that HAS a face: a bare button is artwork floating on the
	-- sky, and a pattern behind it would be a field of marks with nothing to
	-- sit on.
	--
	-- The radius passed is the tile's own, which is what tells the motif's
	-- stadium test to keep its marks off the rounded corners. A child is not
	-- clipped by a UICorner, so anything it placed there would visibly poke out.
	local field: Frame? = nil
	if not bare then
		local pattern = Theme.motif(color, size, size, Theme.Radius.lg, 0.45)
		Theme.emphasiseMotif(pattern, 0.35)
		-- Under everything else on the face, which all sit at the default 1.
		pattern.ZIndex = 0
		field = pattern
		table.insert(faceChildren, pattern)
	end

	table.insert(faceChildren, glyph)

	local caption: TextLabel? = nil
	if hasCaption then
		-- Display face and a heavy black outline, both louder than the shared
		-- default: on a tile this is the text, not a note attached to one.
		caption = Theme.new("TextLabel", {
			Name = "Caption",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.new(1, -6, 0, captionHeight),
			BackgroundTransparency = 1,
			Font = Theme.Font.Display,
			TextSize = Theme.TextSize.small,
			TextColor3 = Theme.Colors.Text,
			-- Scaled down rather than truncated: "Renaissance" is twice the
			-- length of "Lobby", and a clipped verb is worse than a smaller
			-- one. The constraint below is what keeps TextScaled from also
			-- blowing the short labels up to the height of the band.
			TextScaled = true,
			TextWrapped = false,
			Text = config.Caption,
		}, {
			Theme.textStroke(Theme.Line.base),
			Theme.new("UITextSizeConstraint", {
				MaxTextSize = Theme.TextSize.small,
				MinTextSize = 9,
			}),
		})
		table.insert(faceChildren, caption :: any)
	end

	table.insert(faceChildren, badge)

	local button = Theme.chunky({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		Radius = Theme.Radius.lg,
		Inner = true,
		Stroke = Theme.Line.thick,
		Parent = root,
	}, faceChildren)

	-- A soft halo behind the artwork, breathing slowly.
	--
	-- Built from concentric discs rather than a glow texture: Roblox has no
	-- radial gradient for a Frame, and an uploaded image would be one more
	-- Creator Store id that can be moderated away and leave a grey square
	-- (the warning at the top of `Icons` is not hypothetical). Four rings at
	-- rising transparency read as a falloff at the only distance that matters.
	--
	-- It exists because a BARE button has no tile to be found by. The glow is
	-- what puts it back on the map without putting the frame back.
	if config.Glow then
		local halo = Theme.new("Frame", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			-- Under the chunky, which sits at the default ZIndex of 1.
			ZIndex = 0,
			Parent = root,
		})

		for index = 1, 4 do
			local spread = 1 + index * 0.22
			Theme.new("Frame", {
				Name = `Ring{index}`,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(spread, spread),
				BackgroundColor3 = Theme.lighten(color, 0.25),
				BackgroundTransparency = 0.55 + index * 0.1,
				ZIndex = 0,
				Parent = halo,
			}, { Theme.corner(math.floor(size * spread / 2)) })
		end

		-- Breathing, not blinking: slow, sinusoidal, and it never leaves.
		-- A halo that switches off reads as a bug the first time and as a
		-- notification every time after.
		local pulse = Theme.new("UIScale", { Scale = 0.94, Parent = halo })
		TweenService:Create(
			pulse,
			TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 1.08 }
		):Play()
	end

	-- Stripped AFTER the chunky is built rather than by not building it: the
	-- press animation, the lift and `Face.Activated` all live on the face, and
	-- every caller reaches for them.
	if bare then
		button.Shadow.Visible = false
		button.Face.BackgroundTransparency = 1
		for _, decoration in button.Face:GetChildren() do
			if decoration:IsA("UIStroke") or decoration:IsA("UIGradient") then
				decoration.Enabled = false
			elseif decoration.Name == "Inner" then
				(decoration :: any).Visible = false
			end
		end
	end

	-- A small tally pinned to the button's bottom-right. Not the red `Badge`
	-- above the tile: that one shouts "there is something to do here", and a
	-- count of how many times you have already rebirthed is the opposite --
	-- it is a score, read when you look for it and ignored otherwise.
	local counter: TextLabel? = nil
	if config.Counter ~= nil then
		local counterHeight = 22
		local pill = Theme.new("Frame", {
			Name = "Counter",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 4, 1, 0),
			Size = UDim2.fromOffset(counterHeight + 12, counterHeight),
			BackgroundColor3 = Theme.darken(color, 0.35),
			ZIndex = 4,
			Parent = root,
		}, {
			Theme.corner(counterHeight / 2),
			Theme.stroke(nil, Theme.Line.base),
			Theme.gradient(Theme.darken(color, 0.35), 0.2),
		})
		counter = Theme.new("TextLabel", {
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Font.Display,
			TextSize = Theme.TextSize.small,
			TextColor3 = Theme.Colors.Text,
			Text = tostring(config.Counter),
			ZIndex = 4,
			Parent = pill,
		}, { Theme.textStroke(Theme.Line.thin) })
	end

	local obj = {} :: any
	obj.Root, obj.Button, obj.Caption, obj.Counter = root, button, caption, counter

	function obj:SetColor(newColor: Color3)
		button:SetColor(newColor)
		if field then
			Theme.recolourMotif(field, newColor)
		end
	end
	function obj:SetLifted(lifted: boolean)
		button:SetLifted(lifted)
	end
	function obj:SetBadge(text: string?)
		badge.Visible = text ~= nil
		badgeLabel.Text = text or ""
	end
	function obj:SetCounter(text: string)
		if counter then
			counter.Text = text
		end
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

	local children: { Instance } = {
		Theme.corner(height / 2),
		Theme.stroke(nil, Theme.Line.thick),
		Theme.motif(color, width, height, height / 2),
		icon,
		value,
		action,
	}

	local root = Theme.new("Frame", {
		Name = config.Name or "Capsule",
		AnchorPoint = config.AnchorPoint,
		Position = config.Position,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Theme.surface(color),
		Parent = config.Parent,
	}, children)

	return { Root = root, Value = value, Action = action } :: any
end

----------------------------------------------------------------------

export type Gauge =
	{ Root: Frame, SetRatio: (Gauge, number) -> (), SetColor: (Gauge, Color3) -> () }

-- How much of a masked fill is painted. See `Theme.gauge`.
--
-- Four keypoints: opaque up to the cut, transparent immediately after. The two
-- degenerate ends get a flat sequence of their own -- a keypoint at exactly 0
-- or 1 would collide with the fixed endpoints a NumberSequence always carries,
-- and the constructor rejects two keypoints at the same time.
local FILL_CUT = 0.001

-- Exported: the weapon slot's cooldown veil is the same trick turned on its
-- side, and there is no reason for two copies of this arithmetic.
function Theme.fillMask(ratio: number): NumberSequence
	local cut = math.clamp(ratio, 0, 1)
	if cut <= FILL_CUT then
		return NumberSequence.new(1)
	end
	if cut >= 1 - FILL_CUT then
		return NumberSequence.new(0)
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(cut, 0),
		NumberSequenceKeypoint.new(cut + FILL_CUT, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

function Theme.gauge(props: { [string]: any }, color: Color3): Gauge
	local radius = props.Radius or Theme.Radius.sm
	props.Radius = nil
	props.BackgroundColor3 = Theme.Colors.Scrim

	-- The fill is FULL SIZE and masked by a gradient. It is never resized.
	--
	-- The obvious build -- a narrow fill inside a ClipsDescendants frame -- is
	-- ruled out by two engine facts DEVELOPMENT.md spells out: a UICorner
	-- radius is capped by the SMALLER side of what it rounds, so a 6px-wide
	-- fill gets a 3px radius instead of the capsule's; and ClipsDescendants
	-- clips to the RECTANGLE, not to the rounded corners. Between them the fill
	-- came out square-ended AND spilled over the capsule's rounded ends, which
	-- is exactly what it was doing.
	--
	-- At full size the fill carries the SAME UICorner as the track, so its ends
	-- are the track's ends by construction, and a horizontal transparency
	-- gradient decides how much of it is painted. No clipping involved.
	local mask = Theme.new("UIGradient", { Rotation = 0, Transparency = Theme.fillMask(0) })
	local fill = Theme.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, { Theme.corner(radius), mask })

	local root = Theme.new("Frame", props, {
		Theme.corner(radius),
		Theme.stroke(nil, Theme.Line.thin),
		fill,
	})

	-- TweenService cannot interpolate a NumberSequence, so the ratio is tweened
	-- as a plain number and the sequence rebuilt from it. Tweening matters: the
	-- server publishes twice a second, and a bar that jumps reads as a stutter.
	local ratio = Theme.new("NumberValue", { Name = "Ratio", Value = 0, Parent = fill })
	ratio.Changed:Connect(function(value: number)
		mask.Transparency = Theme.fillMask(value)
	end)

	local obj = {} :: any
	obj.Root = root
	function obj:SetRatio(target: number)
		TweenService:Create(ratio, Theme.Tween.Snap, {
			Value = math.clamp(target, 0, 1),
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
	--
	-- The caption is derived from the surface colour rather than fixed grey: a
	-- neutral grey that read fine on the old near-white background goes muddy
	-- the moment the surface carries real colour.
	local label = Theme.new("TextLabel", {
		Position = UDim2.fromOffset(disc + 12, 0),
		Size = UDim2.new(0, 68, 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.caption,
		TextColor3 = Theme.darken(color, 0.5),
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

	local children: { Instance } = {
		Theme.corner(height / 2),
		Theme.stroke(nil, Theme.Line.thick),
		Theme.motif(color, width, height, height / 2),
		icon,
		label,
		gauge.Root,
		value,
	}

	local root = Theme.new("Frame", {
		Name = config.Name or "GaugePill",
		AnchorPoint = config.AnchorPoint,
		Position = config.Position,
		Size = UDim2.fromOffset(width, height),
		BackgroundColor3 = Theme.surface(color),
		Visible = config.Visible,
		Parent = config.Parent,
	}, children)

	local obj = {} :: any
	obj.Root, obj.Gauge, obj.Value = root, gauge, value
	function obj:SetColor(newColor: Color3)
		gauge:SetColor(newColor)
		value.TextColor3 = Theme.darken(newColor, 0.4)
	end
	return obj
end

----------------------------------------------------------------------

----------------------------------------------------------------------
-- Gauge row: an icon, and a bar that carries everything else.
--
-- The anatomy is lifted wholesale from the reference shot: ONE capsule per
-- reading, fully rounded, heavy black outline, with the name pinned inside its
-- left end and the figure inside its right end -- the "Niveau 55 …
-- 102.30K/188.71K" bar. The fill runs underneath both.
--
-- Why both labels go INSIDE, having tried them outside:
--
--   A caption stacked above the bar doubles the row's height for a word read
--   once, and a column of them turns into two competing columns of text.
--   Inside, the bar IS the row, and a stack of them reads as one block.
--
--   Left and right ends rather than centred, because they answer different
--   questions -- "which reading is this" and "how much" -- and a player who
--   only wants the second should never have to find it among the first.
--
-- Everything is drawn in the theme's own language (see the header): rounded to
-- a full stadium, black outline at Line.thick, both labels carrying their own
-- black text stroke so they survive over the fill AND over the empty track.
--
-- `gaugePill` and `capsule` are deliberately left in place: they are the
-- capsule family, and nothing forces a view onto this one.

export type GaugeRow = {
	Root: Frame,
	Gauge: Gauge,
	Value: TextLabel,
	Caption: TextLabel,
	SetColor: (GaugeRow, Color3) -> (),
}

function Theme.gaugeRow(config: { [string]: any }): GaugeRow
	local color = config.Color or Theme.Colors.Accent
	local width = config.Width or 280
	-- The bar fills the row: there is nothing stacked above it any more.
	local height = config.Height or 32
	local iconBox = config.IconBox or 40
	local barWidth = config.BarWidth or 196
	-- A quantity with no ceiling (credits) has nothing to fill: it drops the
	-- bar entirely and stands the figure next to its icon, at display size.
	local showBar = config.ShowBar ~= false
	-- Breathing room between a label and the rounded end it sits against. A
	-- stadium's end is a half-circle, so text flush to the edge reads as
	-- clipped even when it is not.
	local pad = config.Pad or 14

	-- The icon straddles the bar's left end: part of it lies OVER the capsule,
	-- the rest hangs outside it. Bigger than the row is tall, too, so it breaks
	-- the bar's outline top and bottom as well.
	--
	-- That overlap is the whole trick. An icon parked beside a bar is a second
	-- column the eye has to cross; an icon sunk into it belongs to it, and the
	-- part sticking out is what pulls it in front of everything else in the row.
	local overlap = config.IconOverlap or math.floor(iconBox * 0.4)
	local barLeft = iconBox - overlap

	-- Where text starts when there is no bar to sit inside. Clear of the icon
	-- entirely: with nothing under it, an overlapping figure is just a collision.
	local left = iconBox + Theme.Space.sm

	-- Bare artwork, no coloured disc behind it. The pack's icons already carry
	-- their own colour and their own outline, and a disc is how a 34px row
	-- grows back into the capsule this replaced.
	--
	-- ZIndex 2 puts it OVER the bar, which sits at the default 1. Declared
	-- before the bar in the children list, so the order alone would bury it --
	-- and relying on order here would make the overlap depend on an argument
	-- list nobody would think to check.
	local icon = if config.Image
		then Theme.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(iconBox, iconBox),
			BackgroundTransparency = 1,
			Image = config.Image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
		})
		else Theme.new("TextLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(iconBox, iconBox),
			BackgroundTransparency = 1,
			-- Body, not Display: FredokaOne carries no emoji, so the engine
			-- falls back mid-string and the glyph lands off its own baseline.
			Font = Theme.Font.Body,
			TextSize = math.floor(iconBox * 0.78),
			TextColor3 = Theme.Colors.Text,
			Text = config.Glyph or "",
			ZIndex = 2,
		})

	local gauge = Theme.gauge({
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, barLeft, 0.5, 0),
		Size = UDim2.fromOffset(barWidth, height),
		Radius = height / 2,
		Visible = showBar,
	}, color)

	-- Opaque track, in a dark tint OF THE GAUGE'S OWN colour rather than the
	-- shared near-black scrim `Theme.gauge` defaults to. Against a black sky
	-- that scrim vanished outright, leaving the fill floating with no empty
	-- half to be read against -- which is most of what a bar is for.
	gauge.Root.BackgroundColor3 = Theme.darken(color, 0.68)
	gauge.Root.BackgroundTransparency = 0
	local groove = gauge.Root:FindFirstChildOfClass("UIStroke")
	if groove then
		groove.Thickness = Theme.Line.thick
	end

	-- A starfield in the track, UNDER the fill.
	--
	-- Under, not over: the empty half of a bar is the part with nothing to look
	-- at, and texture is what stops it reading as a dead slot. Over the fill it
	-- would only dirty the one thing in the row that has to stay legible.
	--
	-- The radius is the bar's own, so the motif's stadium test keeps its marks
	-- out of the rounded ends -- a child is not clipped by a UICorner.
	local field = Theme.motif(color, barWidth, height, height / 2, 0.45)
	Theme.emphasiseMotif(field, 0.35)
	field.ZIndex = 0
	field.Parent = gauge.Root

	-- Both labels are parented to the bar and declared AFTER the fill, so they
	-- draw over it: the ScreenGui runs on Sibling ZIndex, where order in the
	-- parent is what stacks.
	-- The left inset has to clear the slice of icon lying over the capsule, or
	-- the caption starts underneath it. The right inset is the plain padding.
	local padLeft = pad + overlap

	local function inBar(name: string, alignment: Enum.TextXAlignment, text: string): TextLabel
		return Theme.new("TextLabel", {
			Name = name,
			Position = UDim2.fromOffset(padLeft, 0),
			Size = UDim2.new(1, -(padLeft + pad), 1, 0),
			BackgroundTransparency = 1,
			Font = Theme.Font.Display,
			TextSize = Theme.TextSize.small,
			TextColor3 = Theme.Colors.Text,
			TextXAlignment = alignment,
			TextYAlignment = Enum.TextYAlignment.Center,
			Text = text,
			Parent = gauge.Root,
		}, { Theme.textStroke(Theme.Line.base) })
	end

	local caption = inBar("Caption", Enum.TextXAlignment.Left, config.Caption or "")
	local value = inBar("Value", Enum.TextXAlignment.Right, config.Value or "—")

	-- With no bar the figure has nothing to sit inside, so it stands beside the
	-- icon at display size -- the reference's bare "icon + big number" stat.
	if not showBar then
		value.Parent = nil
		value.Position = UDim2.fromOffset(left, 0)
		value.Size = UDim2.new(1, -left, 1, 0)
		value.TextSize = Theme.TextSize.display
		value.TextXAlignment = Enum.TextXAlignment.Left
		caption.Visible = false
	end

	local children: { Instance } = { icon, gauge.Root }
	if not showBar then
		table.insert(children, value)
	end

	local root = Theme.new("Frame", {
		Name = config.Name or "GaugeRow",
		AnchorPoint = config.AnchorPoint,
		Position = config.Position,
		Size = UDim2.fromOffset(width, height),
		BackgroundTransparency = 1,
		Visible = config.Visible,
		Parent = config.Parent,
	}, children)

	local obj = {} :: any
	obj.Root, obj.Gauge, obj.Value, obj.Caption = root, gauge, value, caption
	function obj:SetColor(newColor: Color3)
		gauge:SetColor(newColor)
		gauge.Root.BackgroundColor3 = Theme.darken(newColor, 0.68)
		-- The power row turns red when demand outruns supply: the texture has
		-- to follow, or the track keeps the stars of a colour it no longer is.
		Theme.recolourMotif(field, newColor)
	end
	return obj
end

----------------------------------------------------------------------
-- Weapon slot: one tile of the hotbar.
--
-- Glass, like the windows, so the selector reads as part of the same interface
-- rather than as a widget bolted on. Everything a player needs is on the tile:
-- the weapon's own artwork, its name along the bottom, the key that equips it
-- in the corner, and the cooldown drawn OVER the art.
--
-- The cooldown is a veil masked by a gradient, not a resized frame -- the same
-- reason the gauges are (see `Theme.gauge`): a shrinking child inside a
-- rounded tile comes out square-ended and spills past the corners. At Rotation
-- 270 the dark drains downward and the art is revealed from the top, which is
-- the direction every game with a cooldown has taught players to read.

export type WeaponSlot = {
	Root: Frame,
	Button: Chunky,
	SetEquipped: (WeaponSlot, boolean) -> (),
	SetCooldown: (WeaponSlot, number, number) -> (),
}

function Theme.weaponSlot(config: { [string]: any }): WeaponSlot
	local size = config.Size or Theme.Hotbar.Slot
	local band = 20
	local pad = 5

	local root = Theme.new("Frame", {
		Name = config.Name or "WeaponSlot",
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		LayoutOrder = config.LayoutOrder,
	})

	local icon = Theme.new("ImageLabel", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- Centred in the space ABOVE the name band, not in the tile.
		Position = UDim2.new(0.5, 0, 0, (size - band) / 2),
		Size = UDim2.fromOffset(math.floor(size * 0.5), math.floor(size * 0.5)),
		BackgroundTransparency = 1,
		Image = config.Image or "",
		ScaleType = Enum.ScaleType.Fit,
	})

	local veilMask = Theme.new("UIGradient", { Rotation = 270, Transparency = Theme.fillMask(0) })
	local veil = Theme.new("Frame", {
		Name = "Cooldown",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Colors.Scrim,
		BackgroundTransparency = 0.2,
		Visible = false,
		ZIndex = 2,
	}, { Theme.corner(Theme.Radius.lg), veilMask })

	local remaining = Theme.new("TextLabel", {
		Name = "Remaining",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, (size - band) / 2),
		Size = UDim2.fromOffset(size, 26),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.title,
		TextColor3 = Theme.Colors.Text,
		Text = "",
		Visible = false,
		ZIndex = 3,
	}, { Theme.textStroke(Theme.Line.base) })

	local nameLabel = Theme.new("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -Theme.Space.sm, 1, 0),
		Position = UDim2.fromOffset(Theme.Space.xs, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.caption,
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		TextWrapped = false,
		Text = config.Caption or "",
	}, {
		Theme.textStroke(Theme.Line.thin),
		Theme.new("UITextSizeConstraint", {
			MaxTextSize = Theme.TextSize.caption,
			MinTextSize = 7,
		}),
	})

	local nameBand = Theme.new("Frame", {
		Name = "NameBand",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -pad),
		Size = UDim2.new(1, -pad * 2, 0, band),
		BackgroundColor3 = Theme.Colors.Scrim,
		BackgroundTransparency = 0.25,
		ZIndex = 4,
	}, { Theme.corner(Theme.Radius.sm), nameLabel })

	-- The key that equips it. Top-left, small, and quiet: it teaches the
	-- shortcut once and then stops asking to be read.
	local keyBadge = Theme.new("Frame", {
		Name = "Key",
		Position = UDim2.fromOffset(pad, pad),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Theme.Colors.Scrim,
		BackgroundTransparency = 0.2,
		ZIndex = 4,
	}, {
		Theme.corner(Theme.Radius.sm),
		Theme.new("TextLabel", {
			Name = "Text",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Theme.Font.Display,
			TextSize = Theme.TextSize.caption,
			TextColor3 = Theme.Colors.TextDim,
			Text = tostring(config.Key or ""),
			ZIndex = 4,
		}),
	})

	local button = Theme.chunky({
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Glass.Color,
		Radius = Theme.Radius.lg,
		Inner = true,
		Stroke = Theme.Line.thick,
		Parent = root,
	}, { icon, veil, remaining, nameBand, keyBadge })

	-- Glass has to be applied to the FACE: Theme.chunky's props configure the
	-- root, and the face it builds underneath is opaque by construction.
	button.Face.BackgroundTransparency = Theme.Glass.Body

	-- Equipping lifts the tile as well as recolouring its outline. Scale is
	-- what carries at a glance; the accent stroke confirms it up close.
	local lift = Theme.new("UIScale", { Scale = 1, Parent = root })

	local obj = {} :: any
	obj.Root, obj.Button, obj.Icon, obj.Label = root, button, icon, nameLabel

	function obj:SetEquipped(equipped: boolean)
		button:SetLifted(equipped)
		TweenService:Create(lift, Theme.Tween.Snap, {
			Scale = if equipped then 1.08 else 1,
		}):Play()
	end

	-- `left` is seconds remaining, `total` the full cooldown. Both, because
	-- the veil needs the ratio and the figure needs the seconds.
	function obj:SetCooldown(left: number, total: number)
		local active = left > 0 and total > 0
		veil.Visible = active
		remaining.Visible = active
		if not active then
			veilMask.Transparency = Theme.fillMask(0)
			return
		end
		veilMask.Transparency = Theme.fillMask(math.clamp(left / total, 0, 1))
		remaining.Text = string.format("%.1f", left)
	end

	return obj
end

----------------------------------------------------------------------

-- Floating label above a world object.
--
-- AlwaysOnTop stays FALSE: a label that pierces geometry turns a dense
-- station into text soup. It's fine for a module to hide the name of the
-- one behind it -- that's exactly what makes the depth readable.
-- A module's floating label: its name and level, and -- when it can still be
-- upgraded -- the icon and price of the next level.
--
-- The price belongs on the label rather than behind a click: it answers "is
-- this one worth walking over to" from wherever the player already is, which is
-- the question a station full of modules keeps asking.
--
-- Laid out with a horizontal UIListLayout and AutomaticSize on the two text
-- runs, so the row stays centred whether or not the price half is showing. A
-- fixed three-column layout leaves a hole where the price would be on the
-- modules that have none.
function Theme.worldLabel(adornee: BasePart, offsetY: number): BillboardGui
	return Theme.new("BillboardGui", {
		Name = "Label",
		Adornee = adornee,
		Size = UDim2.fromOffset(Theme.Label.Width, Theme.Label.Height),
		StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0),
		MaxDistance = Theme.Label.MaxDistance,
		AlwaysOnTop = false,
		LightInfluence = 0,
	}, {
		Theme.new("Frame", {
			Name = "Row",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, {
			Theme.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, Theme.Space.xs),
			}),
			Theme.body({
				Name = "Text",
				LayoutOrder = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Theme.Label.Height),
				Text = "",
			}),
			Theme.new("ImageLabel", {
				Name = "UpgradeIcon",
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(Theme.Label.Glyph, Theme.Label.Glyph),
				Image = Icons.Arrows["GoldUpgrade"],
				ScaleType = Enum.ScaleType.Fit,
				Visible = false,
			}),
			Theme.new("ImageLabel", {
				Name = "CostIcon",
				LayoutOrder = 3,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(Theme.Label.Glyph, Theme.Label.Glyph),
				Image = Icons.Cash["CashIcon"],
				ScaleType = Enum.ScaleType.Fit,
				Visible = false,
			}),
			Theme.body({
				Name = "UpgradeCost",
				LayoutOrder = 4,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, Theme.Label.Height),
				TextColor3 = Theme.Function.Money,
				Text = "",
				Visible = false,
			}),
		}),
	})
end

----------------------------------------------------------------------

export type Banner = {
	Root: Frame,
	Text: TextLabel,
	Icon: ImageLabel,
	SetLook: (Banner, Color3, string) -> (),
}

-- The top-centre read-out. Deliberately not a capsule: a capsule carries an
-- action button on its right, and this one is pure information -- there is
-- nothing to press on it.
--
-- AutomaticSize on the root is what keeps it centred as the text changes width;
-- a fixed width would make a two-digit countdown sit off-centre against a
-- three-digit one.
function Theme.banner(config: { [string]: any }): Banner
	local color = config.Color or Theme.Colors.Credit
	local image = config.Image or Icons.Stars["Star"]
	local radius = Theme.Control.sm / 2

	local icon = Theme.new("ImageLabel", {
		Name = "Icon",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(Theme.Icon.glyph, Theme.Icon.glyph),
		Image = image,
		ScaleType = Enum.ScaleType.Fit,
	}) :: ImageLabel

	local text = Theme.body({
		Name = "Text",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Theme.Control.sm),
		TextSize = Theme.TextSize.title,
		TextColor3 = Theme.darken(color, 0.4),
		Text = config.Text or "",
	}) :: TextLabel

	local width = config.Width or 300
	local pattern = Theme.motif(color, width, Theme.Control.sm, radius)

	-- The icon and the text sit in their own frame, and the dot field is that
	-- frame's SIBLING. A UIListLayout lays out every GuiObject beside it, so a
	-- full-bleed field left in the same frame would be given a column of its own
	-- and shove the content off the banner.
	local content = Theme.new("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Theme.Space.sm),
		}),
		icon,
		text,
	})

	local root = Theme.new("Frame", {
		Name = config.Name or "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = config.Position or UDim2.new(0.5, 0, 0, Theme.Space.xl),
		Size = UDim2.fromOffset(width, Theme.Control.sm),
		BackgroundColor3 = Theme.surface(color),
		Visible = config.Visible ~= false,
		Parent = config.Parent,
	}, {
		Theme.corner(radius),
		Theme.stroke(nil, Theme.Line.thick),
		pattern,
		content,
	}) :: Frame

	local banner = {} :: any
	banner.Root = root
	banner.Text = text
	banner.Icon = icon

	-- Colour and icon change together, always: a banner whose text turned red
	-- while its motif stayed yellow reads as a rendering bug.
	function banner:SetLook(newColor: Color3, newImage: string)
		root.BackgroundColor3 = Theme.surface(newColor)
		text.TextColor3 = Theme.darken(newColor, 0.4)
		icon.Image = newImage
		Theme.recolourMotif(pattern, newColor)
	end

	return banner
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
