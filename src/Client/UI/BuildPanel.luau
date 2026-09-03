--!strict
-- The build menu: a cluster of icon buttons docked to the right edge,
-- always visible, and a modal window that opens over everything.
--
-- Art direction for the window:
--   * bright purple background, thick WHITE border, very rounded corners,
--   * a big capitalized title, white with a thick black outline,
--   * a darker well cut in behind the grid,
--   * every card takes ITS MODULE'S COLOR, with a big icon centered. Color
--     is not relegated to a small dot anymore.
--
-- Every card goes through a UIGridLayout: they CANNOT have different sizes,
-- whatever the content.
--
-- This module only displays. It decides nothing and never talks to the
-- server: it tells BuildController through its onXxx callbacks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Client and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach -- confirmed the first time
-- Rojo actually connected Studio (see CLAUDE.md's cutover notes). Lune has
-- no `game`, so the fallback below -- an ordinary relative require -- is
-- what actually runs there, unchanged from before.
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

local Balance = require(fromShared("Balance"))
local Icons = require(fromShared("Icons"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local ModuleGeometry = require(fromShared("ModuleGeometry"))
local ModuleVisuals = require("./ModuleVisuals")
local Theme = require("./Theme")

-- Card thumbnails are built from the SAME ModuleGeometry the server places
-- with (StationSceneBuilder.buildModuleModel), always at level 1 -- a card
-- shows what buying the module gets you, never an upgraded look nobody has
-- paid for yet. Falls back to the legacy ReplicatedStorage.ModuleModels
-- template, then to the icon pack, in the same order the build ghost and
-- the server's own placement already fall back in.
local THUMB_CELL_SIZE = Balance.Grid.CellSize
local THUMB_MAX_LEVEL = Balance.Upgrade.MaxLevel

local ModuleModels = ReplicatedStorage:WaitForChild("ModuleModels", 10)
if not ModuleModels then
	warn("[BuildPanel] ReplicatedStorage.ModuleModels missing -- cards fall back to icons")
end

local COLORS = Theme.Colors
local FUNCTION = Theme.Function
local SPACE = Theme.Space

-- Height set for 3 rows of cards: 3 x 160 + 2 x 12 = 504 px. The whole
-- catalogue fits without scrolling.
-- Sized so the whole catalogue fits WITHOUT SCROLLING: 10 modules, five to a
-- row, two rows. The scrollbar that used to sit over the last card is gone
-- because there is nothing left to scroll.
--
-- The width came free. The old window spent 176px -- 21% of itself -- on a
-- vertical column of seven category pills that a player touches once a
-- session. Those are a horizontal bar now, and the grid got the space.
local PANEL = Vector2.new(880, 580)
local CARD = Vector2.new(150, 178)
local TITLE_HEIGHT = 44
local TITLE_ICON = 44
local SUBTITLE_HEIGHT = 24
-- The "?" pill in a card's top row, sitting beside the name band.
local INFO_BADGE = 24
local TAB_HEIGHT = 44
-- The confirmation dialog's header tile.
local CONFIRM_ICON = 40
local ICON = Theme.Icon.button
-- The caption lives ON the tile now (see Theme.iconButton), so a button's
-- footprint is just the tile -- no strip underneath to account for.
local ICON_TOTAL = ICON

-- Tiles per row in the right-hand dock.
local DOCK_COLUMNS = 2

-- Pixels of the bottom-left corner already spoken for by HudController's
-- read-out cluster. The left dock sits on the same edge, so it is anchored
-- clear of this rather than centred: a Renaissance caption landing on the
-- module count is the one collision splitting the buttons can create.
--
-- A reserve rather than a query: the two views are built independently, and a
-- dock that measured the HUD would have to be rebuilt every time a read-out
-- appeared or vanished.
-- Measured, not guessed: the cluster runs 272px from the bottom edge up to the
-- module count, and a caption sits under each dock button. 340 clears both with
-- room to spare -- at 300 the "Renaissance" caption landed on "0 module".
local HUD_RESERVE = 340

local ALL = "Tous"

local BuildPanel = {}
BuildPanel.__index = BuildPanel

export type BuildPanel = typeof(setmetatable({} :: any, BuildPanel))

----------------------------------------------------------------------

local function image(id: string, props: { [string]: any }): ImageLabel
	local merged: { [string]: any } = {
		Name = "Icon",
		BackgroundTransparency = 1,
		Image = id,
		ScaleType = Enum.ScaleType.Fit,
	}
	for key, value in props do
		merged[key] = value
	end
	return Theme.new("ImageLabel", merged)
end

local function statLine(definition: ModuleCatalog.ModuleDef): string
	local parts = { `{definition.size.w}×{definition.size.h}` }
	if definition.power ~= 0 then
		table.insert(parts, `{if definition.power > 0 then "+" else ""}{definition.power} én.`)
	end
	if definition.heat > 0 then
		table.insert(parts, `{definition.heat}°`)
	end
	return table.concat(parts, "  ")
end

-- A card is THREE BANDS, the way the reference art builds one: a name strip
-- across the top, the artwork in the middle, a price strip across the bottom.
--
-- Bands rather than free-floating labels, because a band has edges. Every
-- element used to be positioned against the card itself and drifted into its
-- neighbours -- the name ran under the "?" badge, the price pill hung off the
-- bottom edge. Here each row owns a horizontal slice and cannot leave it.
--
-- The rows, top to bottom (card is 178 tall):
--   6..34    name band, and the "?" badge BESIDE it -- same row, not on top
--   38..116  artwork, centred in what is left
--   118..134 the stat line
--   144..172 price band
local CARD_PAD = 6
local CARD_BAND = 28
local CARD_ART_TOP = 38
local CARD_ART_HEIGHT = 78
local CARD_STAT_TOP = 118

local function buildCard(definition: ModuleCatalog.ModuleDef)
	local color = ModuleVisuals.colorOf(definition.id) or COLORS.Card

	----------------------------------------------------------------------
	-- Top row: name band + info badge, side by side

	local nameLabel = Theme.new("TextLabel", {
		Name = "Name",
		Size = UDim2.new(1, -SPACE.sm, 1, 0),
		Position = UDim2.fromOffset(SPACE.xs, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.small,
		TextColor3 = COLORS.Text,
		-- Scaled, so a long name shrinks instead of running out of its band.
		TextScaled = true,
		TextWrapped = false,
		Text = definition.name,
	}, {
		Theme.textStroke(Theme.Line.base),
		Theme.new("UITextSizeConstraint", {
			MaxTextSize = Theme.TextSize.small,
			MinTextSize = 8,
		}),
	})

	local nameBand = Theme.new("Frame", {
		Name = "NameBand",
		Position = UDim2.fromOffset(CARD_PAD, CARD_PAD),
		-- Stops exactly where the badge begins. The two share the row and the
		-- arithmetic here is what guarantees they never touch.
		Size = UDim2.new(1, -(CARD_PAD * 2 + INFO_BADGE + SPACE.xs), 0, CARD_BAND),
		BackgroundColor3 = Theme.darken(color, 0.34),
	}, { Theme.corner(Theme.Radius.sm), Theme.stroke(nil, Theme.Line.thin), nameLabel })

	local infoButton = Theme.new("TextButton", {
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -CARD_PAD, 0, CARD_PAD),
		Size = UDim2.fromOffset(INFO_BADGE, CARD_BAND),
		BackgroundColor3 = COLORS.Accent,
		AutoButtonColor = false,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.small,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "?",
		ZIndex = 2,
	}, {
		Theme.corner(Theme.Radius.sm),
		Theme.stroke(nil, Theme.Line.thin),
		Theme.textStroke(Theme.Line.thin),
	})

	local children = { nameBand, infoButton }

	----------------------------------------------------------------------
	-- Middle: the artwork, centred in its slice

	-- Show the object itself rather than a generic icon: the player
	-- recognizes what they're about to place. Built at level 1 -- a card is
	-- what BUYING the module looks like, never an upgraded look nobody has
	-- paid for. The icon pack stays the fallback, for a module without a
	-- model yet.
	local artCentre = CARD_ART_TOP + CARD_ART_HEIGHT / 2
	local built = ModuleGeometry.build(definition, THUMB_CELL_SIZE, 1, THUMB_MAX_LEVEL)
	local legacyTemplate = if not built and ModuleModels
		then ModuleModels:FindFirstChild(definition.id)
		else nil
	local template = built
		or (if legacyTemplate and legacyTemplate:IsA("Model") then legacyTemplate else nil)
	if template then
		table.insert(
			children,
			Theme.modelThumb(template, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, artCentre),
				Size = UDim2.fromOffset(84, 74),
			})
		)
		-- modelThumb clones the model in; the source built here has nothing
		-- left to do once that clone exists.
		if built then
			built:Destroy()
		end
	else
		local iconId = ModuleVisuals.iconFor(definition.id)
		if iconId then
			table.insert(
				children,
				image(iconId, {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, 0, 0, artCentre),
					Size = UDim2.fromOffset(64, 64),
				})
			)
		end
	end

	table.insert(
		children,
		Theme.new("TextLabel", {
			Name = "Stats",
			Position = UDim2.fromOffset(CARD_PAD, CARD_STAT_TOP),
			Size = UDim2.new(1, -CARD_PAD * 2, 0, 16),
			BackgroundTransparency = 1,
			Font = Theme.Font.Display,
			TextSize = Theme.TextSize.caption,
			TextColor3 = Theme.lighten(color, 0.7),
			Text = statLine(definition),
		}, { Theme.textStroke(Theme.Line.thin) })
	)

	----------------------------------------------------------------------
	-- Bottom row: the price band
	--
	-- Coin and figure are laid out by a centred UIListLayout rather than
	-- placed by hand: the pair stays centred whatever the number's width,
	-- which a fixed offset cannot do between "25" and "1200".

	local costLabel = Theme.new("TextLabel", {
		Name = "Cost",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, CARD_BAND),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.small,
		TextColor3 = COLORS.Credit,
		Text = tostring(definition.cost),
	}, { Theme.textStroke(Theme.Line.base) })

	table.insert(
		children,
		Theme.new("Frame", {
			Name = "CostBand",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -CARD_PAD),
			Size = UDim2.new(1, -CARD_PAD * 2, 0, CARD_BAND),
			BackgroundColor3 = Theme.darken(color, 0.5),
		}, {
			Theme.corner(Theme.Radius.sm),
			Theme.stroke(nil, Theme.Line.thin),
			Theme.new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, SPACE.xs),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			image(Icons.Cash["CashIcon"], {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(18, 18),
			}),
			costLabel,
		})
	)

	-- The card takes the module's color: this is what makes the grid
	-- readable at a glance, same as the reference art.
	local card = Theme.chunky({
		Name = definition.id,
		Size = UDim2.fromOffset(CARD.X, CARD.Y),
		BackgroundColor3 = color,
		Radius = Theme.Radius.md,
		Inner = true,
	}, children)

	return card, { name = nameLabel, cost = costLabel }, infoButton
end

----------------------------------------------------------------------

function BuildPanel.new(parent: ScreenGui): BuildPanel
	local self = setmetatable({}, BuildPanel)

	self.onSelect = nil :: ((string?) -> ())?
	self.onToggleDemolish = nil :: (() -> ())?
	self.onToggleUpgrade = nil :: (() -> ())?
	self.onToggleModify = nil :: (() -> ())?
	self.onOpenChanged = nil :: ((boolean) -> ())?
	self.onReturnToLobby = nil :: (() -> ())?
	self.onRebirthRequested = nil :: (() -> ())?
	self.onResearchRequested = nil :: (() -> ())?

	self._entries = {} :: { [string]: any }
	self._selected = nil :: string?
	self._credits = 0
	self._category = ALL
	self._open = false

	----------------------------------------------------------------------
	-- Two docks, split by what the buttons DO -- not by how many fit.
	--
	-- Right: the four verbs that act on the station. Build, upgrade, move,
	-- demolish are one mode -- a player runs through them in sequence, and they
	-- belong in one toolbar, on the edge the build window itself opens from.
	--
	-- Left: the two that take you OUT of that loop. Neither is ever pressed
	-- mid-build, and both are consequential -- Renaissance wipes the station.
	-- Sitting one slot under Démolir, it was a mis-tap away from the button a
	-- player hits most; on the far edge it cannot be reached by accident.
	--
	-- Splitting also halves the column: six 96px buttons ran 616px down the
	-- screen, taller than most viewports, and the stack was the interface.
	--
	-- The left dock hangs off the bottom edge, lifted by HUD_RESERVE so it
	-- stacks ABOVE the read-out cluster instead of over it.

	-- Laid out as a GRID, two tiles wide, the way the reference does it. A
	-- single column of big tiles is a stripe down the edge of the screen and
	-- reads as a ruler; two columns read as a pad, and halve the distance the
	-- thumb travels between the first button and the last.
	self._dock = Theme.new("Frame", {
		Name = "Dock",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SPACE.xl, 0.5, 0),
		Size = UDim2.fromOffset(
			DOCK_COLUMNS * ICON_TOTAL + (DOCK_COLUMNS - 1) * SPACE.sm,
			ICON_TOTAL * 2 + SPACE.sm
		),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Theme.new("UIGridLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			CellSize = UDim2.fromOffset(ICON, ICON),
			CellPadding = UDim2.fromOffset(SPACE.sm, SPACE.sm),
			-- Right, so a dock that does not fill its last row stays flush
			-- against the screen edge instead of drifting inwards.
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			FillDirectionMaxCells = DOCK_COLUMNS,
		}),
	})

	self._dockLeft = Theme.new("Frame", {
		Name = "DockLeft",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, SPACE.xl, 1, -HUD_RESERVE),
		Size = UDim2.fromOffset(ICON, ICON_TOTAL * 3 + SPACE.sm * 2),
		BackgroundTransparency = 1,
		Parent = parent,
	}, {
		Theme.new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, SPACE.sm),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	})

	self._openButton = Theme.iconButton({
		Name = "Construire",
		LayoutOrder = 1,
		Color = FUNCTION.Build,
		Image = Icons.Menus["Store"],
		Caption = "Construire",
	})
	self._openButton.Root.Parent = self._dock

	-- One color per function: amber for upgrading, distinct from the blue
	-- that builds and the red that demolishes.
	self._upgradeButton = Theme.iconButton({
		Name = "Ameliorer",
		LayoutOrder = 2,
		Color = FUNCTION.Info,
		Image = Icons.Stars["Star"],
		Caption = "Améliorer",
	})
	self._upgradeButton.Root.Parent = self._dock

	self._modifyButton = Theme.iconButton({
		Name = "Modifier",
		LayoutOrder = 3,
		Color = FUNCTION.Move,
		Image = Icons.Menus["Teleport"],
		Caption = "Modifier",
	})
	self._modifyButton.Root.Parent = self._dock

	self._demolishButton = Theme.iconButton({
		Name = "Demolir",
		LayoutOrder = 4,
		Color = FUNCTION.Demolish,
		Image = Icons.Menus["Trash"],
		Caption = "Démolir",
	})
	self._demolishButton.Root.Parent = self._dock

	-- Bare, like the rebirth button beside it: the two controls that take you
	-- OUT of the build loop share a look, and it is deliberately not the look
	-- of the tiles that act ON the station. A house needs no label.
	self._lobbyButton = Theme.iconButton({
		Name = "Lobby",
		LayoutOrder = 1,
		Color = FUNCTION.Lobby,
		Image = Icons.Misc["House"],
		Bare = true,
	})
	self._lobbyButton.Root.Parent = self._dockLeft

	-- The one BARE control in the interface: no tile, no outline, no shadow --
	-- the recycle arrows alone, and a small tally of how many rebirths are
	-- banked. It is not a station verb like the four on the right, and looking
	-- unlike them is the point: nothing about it should invite a reflex tap.
	self._rebirthButton = Theme.iconButton({
		Name = "Renaissance",
		LayoutOrder = 2,
		Color = FUNCTION.Rebirth,
		Image = Icons.Arrows["Rebirth"],
		Bare = true,
		Counter = 0,
	})
	self._rebirthButton.Root.Parent = self._dockLeft

	-- The research zone. Bare like the two above it, because it belongs to
	-- the same family: controls that take you out of the build loop rather
	-- than verbs that act on the station. Last in the column -- it is the
	-- newest and the least urgent of the three, and the order the eye reads
	-- them in should not change under a player who already knows the dock.
	self._researchButton = Theme.iconButton({
		Name = "Recherche",
		LayoutOrder = 3,
		Color = FUNCTION.Research,
		Image = Icons.Gems["GemIcon"],
		Bare = true,
	})
	self._researchButton.Root.Parent = self._dockLeft

	----------------------------------------------------------------------
	-- Scrim

	-- INVISIBLE, but still there: it is the click-catcher that closes the menu
	-- when you tap outside it, and dropping it would drop that.
	--
	-- It used to dim the whole screen to 40%. On a game whose backdrop is
	-- already near-black space, that darkened the station to nearly nothing
	-- and read as a rendering fault rather than as a modal veil.
	self._scrim = Theme.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.Scrim,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})

	----------------------------------------------------------------------
	-- Window

	-- Header: an icon tile, the title, a rule running out to the close button,
	-- and an accent line under the whole thing.
	--
	-- A title alone floating in the corner is what made this window read as a
	-- grey box with text on it. The tile gives the window a face, and the rule
	-- is what turns "some text near the top" into a header BAR -- it draws the
	-- boundary the content then sits below.
	local titleIcon = Theme.new("Frame", {
		Name = "TitleIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, TITLE_HEIGHT / 2),
		Size = UDim2.fromOffset(TITLE_ICON, TITLE_ICON),
		BackgroundColor3 = FUNCTION.Build,
	}, {
		Theme.corner(Theme.Radius.md),
		Theme.stroke(nil, Theme.Line.thick),
		Theme.gradient(FUNCTION.Build, 0.2),
		image(Icons.Menus["Store"], {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.62, 0.62),
		}),
	})

	local titleLeft = TITLE_ICON + SPACE.md

	local title = Theme.new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(titleLeft, 0),
		Size = UDim2.new(1, -(titleLeft + Theme.Control.md + SPACE.md), 0, TITLE_HEIGHT),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.display,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = Theme.Words.BuildTitle,
	}, { Theme.textStroke(Theme.Line.base) })

	local rule = Theme.new("Frame", {
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(0, Theme.Line.base),
		BackgroundColor3 = Theme.darken(COLORS.Menu, 0.4),
	}, { Theme.corner(Theme.Line.base) })

	-- Driven off the rendered width rather than a guessed one: TextBounds is
	-- the only thing that knows how wide "CONSTRUCTION" actually came out in
	-- this font at this size, and the rule has to start where the word ends.
	local function fitRule()
		local start = titleLeft + title.TextBounds.X + SPACE.md
		rule.Position = UDim2.fromOffset(start, TITLE_HEIGHT / 2)
		rule.Size = UDim2.new(1, -(start + Theme.Control.md + SPACE.md), 0, Theme.Line.base)
	end
	title:GetPropertyChangedSignal("TextBounds"):Connect(fitRule)
	fitRule()

	-- CENTRED across the window, like the reference's two lines under its
	-- header. Left-aligned it read as a third item in the header row; centred
	-- it reads as the window addressing the player.
	local subtitle = Theme.new("TextLabel", {
		Name = "Subtitle",
		Position = UDim2.fromOffset(0, TITLE_HEIGHT + SPACE.xs),
		Size = UDim2.new(1, 0, 0, SUBTITLE_HEIGHT),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.body,
		-- Gold, the one colour the window does not otherwise use: it is the
		-- line that speaks to the player rather than labelling something.
		TextColor3 = COLORS.Credit,
		Text = Theme.Words.BuildHint,
	}, { Theme.textStroke(Theme.Line.base) })

	----------------------------------------------------------------------
	-- Category bar
	--
	-- The list is built HERE, before the window, because the chips share the
	-- width evenly and that division needs the count.

	local categories = { ALL }
	for _, name in ModuleCatalog.Categories do
		table.insert(categories, name)
	end

	local tabsTop = TITLE_HEIGHT + SPACE.xs + SUBTITLE_HEIGHT + SPACE.md
	local tabWidth =
		math.floor((PANEL.X - SPACE.xl * 2 - SPACE.sm * (#categories - 1)) / #categories)

	local tabBar = Theme.new("Frame", {
		Name = "Tabs",
		Position = UDim2.fromOffset(0, tabsTop),
		Size = UDim2.new(1, 0, 0, TAB_HEIGHT),
		BackgroundTransparency = 1,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, SPACE.sm),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	self._close = Theme.chunky({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(Theme.Control.md, Theme.Control.md),
		BackgroundColor3 = FUNCTION.Demolish,
		Radius = Theme.Radius.md,
		Inner = true,
	}, {
		image(Icons.Misc["Deny"], {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.55, 0.55),
		}),
	})

	local contentTop = tabsTop + TAB_HEIGHT + SPACE.md

	self._grid = Theme.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = COLORS.Inner,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	}, {
		Theme.new("UIGridLayout", {
			CellSize = UDim2.fromOffset(CARD.X, CARD.Y),
			CellPadding = UDim2.fromOffset(SPACE.md, SPACE.md),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	-- Cut-in well: it detaches the grid from the window's background.
	--
	-- Darkened well past MenuInner, which was so close to the window's own
	-- purple that the cards looked like they were floating on the body rather
	-- than sitting in a recess. The reference gets this separation for free
	-- from its two greens; ours has to be made.
	local well = Theme.panel({
		Name = "Well",
		Position = UDim2.fromOffset(0, contentTop),
		Size = UDim2.new(1, 0, 1, -contentTop),
		BackgroundColor3 = Theme.Glass.Color,
		BackgroundTransparency = Theme.Glass.Well,
		Radius = Theme.Radius.lg,
		StrokeThickness = Theme.Line.thick,
	}, { Theme.padding(SPACE.md), self._grid })

	self._panelScale = Theme.new("UIScale", { Scale = 1 })

	self._panel = Theme.panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		BackgroundColor3 = Theme.Glass.Color,
		Radius = Theme.Radius.xl,
		-- Black outline outside, light rim inside, and the body see-through
		-- between them: see Theme.Glass. The 5px WHITE stroke this used to
		-- carry is what made the menu look like a sticker peeled off a page.
		StrokeThickness = Theme.Line.thick,
		BackgroundTransparency = Theme.Glass.Body,
		Inner = true,
		Visible = false,
		ZIndex = 6,
		Parent = parent,
	}, {
		Theme.padding(SPACE.xl),
		rule,
		titleIcon,
		title,
		subtitle,
		self._close.Root,
		tabBar,
		well,
		self._panelScale,
	})

	----------------------------------------------------------------------
	-- Category tabs

	self._tabs = {}
	local tabOrder = 0

	-- A chip is icon-left, label filling the rest, and the label is SCALED:
	-- "Logistique" and "Tous" get the same chip width, and a fixed text size
	-- would clip one to make the other look right.
	local ICON_BOX = 22
	local iconGap = SPACE.sm

	for _, name in categories do
		tabOrder += 1
		local iconId = ModuleVisuals.CategoryIcons[name]
		local labelLeft = if iconId then iconGap + ICON_BOX + SPACE.xs else iconGap
		local children = {
			Theme.new("TextLabel", {
				Name = "Label",
				Position = UDim2.fromOffset(labelLeft, 0),
				Size = UDim2.new(1, -(labelLeft + SPACE.sm), 1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Font.Display,
				TextSize = Theme.TextSize.small,
				TextColor3 = COLORS.Text,
				TextScaled = true,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = name,
			}, {
				Theme.textStroke(Theme.Line.thin),
				Theme.new("UITextSizeConstraint", {
					MaxTextSize = Theme.TextSize.small,
					MinTextSize = 9,
				}),
			}),
		}
		if iconId then
			table.insert(
				children,
				image(iconId, {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, iconGap, 0.5, 0),
					Size = UDim2.fromOffset(ICON_BOX, ICON_BOX),
				})
			)
		end

		local tab = Theme.chunky({
			Name = name,
			Size = UDim2.fromOffset(tabWidth, TAB_HEIGHT),
			-- Lifted off the glass rather than darkened into it: on a near-black
			-- pane a dark chip disappears, and these are the one control in the
			-- window a player has to find without looking for it.
			BackgroundColor3 = Theme.lighten(Theme.Glass.Color, 0.16),
			Radius = Theme.Radius.md,
			Inner = true,
		}, children)
		tab.Root.LayoutOrder = tabOrder
		tab.Root.Parent = tabBar
		self._tabs[name] = tab

		tab.Face.Activated:Connect(function()
			self:SetCategory(name)
		end)
	end

	----------------------------------------------------------------------
	-- Cards

	local order = 0
	for _, id in ModuleCatalog.Order do
		local definition = ModuleCatalog.get(id)
		-- The core ships with the station: it isn't buildable.
		if not definition or definition.unique then
			continue
		end

		order += 1
		local card, labels, infoButton = buildCard(definition)
		card.Root.LayoutOrder = order
		card.Root.Parent = self._grid

		self._entries[id] = { card = card, labels = labels, definition = definition }

		card.Face.Activated:Connect(function()
			if self.onSelect then
				self.onSelect(if self._selected == id then nil else id)
			end
		end)

		infoButton.Activated:Connect(function()
			self:_showInfo(definition)
		end)
	end

	----------------------------------------------------------------------
	-- Banner for the module currently in hand

	self._activeBadge = Theme.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SPACE.md, 0.5, 0),
		Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = COLORS.Accent,
	}, { Theme.corner(19), Theme.stroke(nil, Theme.Line.thin) })

	self._activeIcon = image("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.74, 0.74),
		Parent = self._activeBadge,
	})

	self._activeName = Theme.body({
		Position = UDim2.fromOffset(SPACE.md + 48, 6),
		Size = UDim2.new(1, -(SPACE.md + 56), 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	self._activeHint = Theme.caption({
		Position = UDim2.fromOffset(SPACE.md + 48, 28),
		Size = UDim2.new(1, -(SPACE.md + 56), 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "R pivoter   ·   clic droit annuler",
	})

	self._active = Theme.panel({
		Name = "Active",
		AnchorPoint = Vector2.new(0.5, 1),
		-- Above the weapon selector, which owns the bottom centre. Everything
		-- that lands there stacks off Theme.Hotbar.Reserve rather than each
		-- guessing its own offset.
		Position = UDim2.new(0.5, 0, 1, -(SPACE.xl + Theme.Hotbar.Reserve)),
		Size = UDim2.fromOffset(360, 60),
		BackgroundColor3 = COLORS.PanelDeep,
		Radius = Theme.Radius.lg,
		Inner = true,
		Visible = false,
		Parent = parent,
	}, { self._activeBadge, self._activeName, self._activeHint })

	----------------------------------------------------------------------
	-- Info popup: shown by a card's "?" badge, describing what that module
	-- actually does. Reuses the Active band's screen position -- the two
	-- are mutually exclusive by construction (Active only shows once the
	-- menu is closed; this only shows while it's open).

	local INFO_WIDTH = 480

	self._infoTitle = Theme.body({
		Position = UDim2.fromOffset(SPACE.md, SPACE.sm),
		-- Leaves room on the right for the close button, so a long name
		-- never runs under it.
		Size = UDim2.new(1, -(SPACE.md * 2 + 24), 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})

	self._infoText = Theme.prose({
		Position = UDim2.fromOffset(SPACE.md, SPACE.sm + 22),
		Size = UDim2.new(1, -SPACE.md * 2, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
	})

	-- Discreet: no background, dim white -- it reads as "close" without
	-- competing with the module name for attention.
	self._infoClose = Theme.new("TextButton", {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -SPACE.sm, 0, SPACE.sm),
		Size = UDim2.fromOffset(20, 20),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Font = Theme.Font.Display,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		TextTransparency = 0.4,
		Text = "×",
	})

	self._info = Theme.panel({
		Name = "Info",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(SPACE.xl + Theme.Hotbar.Reserve)),
		Size = UDim2.fromOffset(INFO_WIDTH, SPACE.sm + 22 + SPACE.sm),
		BackgroundColor3 = COLORS.PanelDeep,
		Radius = Theme.Radius.lg,
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	}, { self._infoTitle, self._infoText, self._infoClose })

	-- infoText's own AutomaticSize.Y keeps its AbsoluteSize accurate for
	-- whatever text is currently set; this is what keeps the popup itself
	-- exactly as tall as that text, never a fixed box with empty space
	-- (a short description) or clipped text (a long one).
	self._infoText:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self._info.Size =
			UDim2.fromOffset(INFO_WIDTH, SPACE.sm + 22 + self._infoText.AbsoluteSize.Y + SPACE.sm)
	end)

	self._infoClose.Activated:Connect(function()
		self._info.Visible = false
		self._infoOpenId = nil
	end)

	----------------------------------------------------------------------
	-- Generic confirmation modal -- for any destructive/irreversible action
	-- (currently just Rebirth). `confirmColor` tints the confirm button so
	-- distinct actions sharing this one dialog still read as distinct.

	-- Same header grammar as the build window: a tile, the title beside it,
	-- and a rule out to the edge. A confirmation that looks like a different
	-- product from the menu that opened it is how a player stops trusting
	-- either -- and this is the one dialog that wipes a station.
	self._confirmIcon = Theme.new("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(0, CONFIRM_ICON / 2),
		Size = UDim2.fromOffset(CONFIRM_ICON, CONFIRM_ICON),
		BackgroundColor3 = FUNCTION.Rebirth,
	}, {
		Theme.corner(Theme.Radius.md),
		Theme.stroke(nil, Theme.Line.thick),
		image(Icons.Misc["Exclaim"], {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.58, 0.58),
		}),
	})

	local confirmLeft = CONFIRM_ICON + SPACE.md

	self._confirmTitle = Theme.new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(confirmLeft, 0),
		Size = UDim2.new(1, -confirmLeft, 0, CONFIRM_ICON),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.title,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, { Theme.textStroke(Theme.Line.base) })

	self._confirmRule = Theme.new("Frame", {
		Name = "Rule",
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(0, Theme.Line.base),
		BackgroundColor3 = Theme.darken(COLORS.Menu, 0.4),
	}, { Theme.corner(Theme.Line.base) })

	local function fitConfirmRule()
		local start = confirmLeft + self._confirmTitle.TextBounds.X + SPACE.md
		self._confirmRule.Position = UDim2.fromOffset(start, CONFIRM_ICON / 2)
		self._confirmRule.Size = UDim2.new(1, -start, 0, Theme.Line.base)
	end
	self._confirmTitle:GetPropertyChangedSignal("TextBounds"):Connect(fitConfirmRule)

	self._confirmBody = Theme.prose({
		Position = UDim2.fromOffset(0, CONFIRM_ICON + SPACE.md),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	})

	local confirmCancelLabel = Theme.body({
		Size = UDim2.fromScale(1, 1),
		Text = "Annuler",
	})
	self._confirmCancel = Theme.chunky({
		Size = UDim2.fromOffset(150, Theme.Control.md),
		BackgroundColor3 = COLORS.MenuInner,
		Radius = Theme.Radius.md,
		Inner = true,
	}, { confirmCancelLabel })

	local confirmOkLabel = Theme.body({
		Size = UDim2.fromScale(1, 1),
		Text = "Confirmer",
	})
	self._confirmOk = Theme.chunky({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(150, Theme.Control.md),
		BackgroundColor3 = FUNCTION.Rebirth,
		Radius = Theme.Radius.md,
		Inner = true,
	}, { confirmOkLabel })

	local confirmButtons = Theme.new("Frame", {
		Name = "Buttons",
		Position = UDim2.new(0, 0, 1, -Theme.Control.md),
		Size = UDim2.new(1, 0, 0, Theme.Control.md),
		BackgroundTransparency = 1,
	}, { self._confirmCancel.Root, self._confirmOk.Root })

	self._confirmScale = Theme.new("UIScale", { Scale = 1 })

	self._confirm = Theme.panel({
		Name = "Confirm",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(440, 40 + 90 + SPACE.lg + Theme.Control.md),
		-- Same glass as the build window: the two are the same product.
		BackgroundColor3 = Theme.Glass.Color,
		BackgroundTransparency = Theme.Glass.Body,
		Radius = Theme.Radius.xl,
		StrokeThickness = Theme.Line.thick,
		Inner = true,
		Visible = false,
		ZIndex = 9,
		Parent = parent,
	}, {
		Theme.padding(SPACE.xl),
		self._confirmRule,
		self._confirmIcon,
		self._confirmTitle,
		self._confirmBody,
		confirmButtons,
		self._confirmScale,
	})

	-- Grows with the body text, same AutomaticSize-driven resize _info uses.
	--
	-- Every band is named rather than folded into one constant, because the
	-- old figure counted the window's padding ONCE when Theme.padding applies
	-- it top AND bottom. The dialog came out 24px short and the last line of
	-- the body ran under the buttons -- on the one dialog whose small print is
	-- the whole point of showing it.
	self._confirmBody:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self._confirm.Size = UDim2.fromOffset(
			440,
			SPACE.xl * 2
				+ CONFIRM_ICON
				+ SPACE.md
				+ self._confirmBody.AbsoluteSize.Y
				+ SPACE.lg
				+ Theme.Control.md
		)
	end)

	self._confirmCancel.Face.Activated:Connect(function()
		self._confirm.Visible = false
		self._confirmCallback = nil
	end)
	self._confirmOk.Face.Activated:Connect(function()
		self._confirm.Visible = false
		local callback = self._confirmCallback
		self._confirmCallback = nil
		if callback then
			callback()
		end
	end)

	----------------------------------------------------------------------
	-- Ephemeral toast

	self._toastIcon = image(Icons.Misc["Accept"], {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SPACE.md, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
	})
	self._toastLabel = Theme.body({
		Position = UDim2.fromOffset(SPACE.md + 34, 0),
		Size = UDim2.new(1, -(SPACE.md + 42), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	self._toastScale = Theme.new("UIScale", { Scale = 1 })

	self._toast = Theme.panel({
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(SPACE.xl + Theme.Hotbar.Reserve + 60 + SPACE.md)),
		Size = UDim2.fromOffset(440, Theme.Control.md),
		BackgroundColor3 = COLORS.PanelDeep,
		Radius = Theme.Radius.lg,
		Inner = true,
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	}, { self._toastIcon, self._toastLabel, self._toastScale })

	----------------------------------------------------------------------

	self._openButton.Button.Face.Activated:Connect(function()
		self:Toggle()
	end)
	self._close.Face.Activated:Connect(function()
		self:Close()
	end)
	self._scrim.Activated:Connect(function()
		self:Close()
	end)
	self._upgradeButton.Button.Face.Activated:Connect(function()
		if self.onToggleUpgrade then
			self.onToggleUpgrade()
		end
	end)
	self._demolishButton.Button.Face.Activated:Connect(function()
		if self.onToggleDemolish then
			self.onToggleDemolish()
		end
	end)
	self._modifyButton.Button.Face.Activated:Connect(function()
		if self.onToggleModify then
			self.onToggleModify()
		end
	end)
	self._lobbyButton.Button.Face.Activated:Connect(function()
		if self.onReturnToLobby then
			self.onReturnToLobby()
		end
	end)
	self._rebirthButton.Button.Face.Activated:Connect(function()
		if self.onRebirthRequested then
			self.onRebirthRequested()
		end
	end)
	self._researchButton.Button.Face.Activated:Connect(function()
		if self.onResearchRequested then
			self.onResearchRequested()
		end
	end)

	self:SetCategory(ALL)
	return self
end

----------------------------------------------------------------------

function BuildPanel:IsOpen(): boolean
	return self._open
end

function BuildPanel:Open()
	if self._open then
		return
	end
	self._open = true
	self._scrim.Visible = true
	self._panel.Visible = true
	self._panelScale.Scale = 0.88
	TweenService:Create(self._panelScale, Theme.Tween.Pop, { Scale = 1 }):Play()
	if self.onOpenChanged then
		self.onOpenChanged(true)
	end
end

function BuildPanel:Close()
	if not self._open then
		return
	end
	self._open = false
	self._scrim.Visible = false
	self._panel.Visible = false
	self._info.Visible = false
	self._infoOpenId = nil
	if self.onOpenChanged then
		self.onOpenChanged(false)
	end
end

-- Toggles the info popup for one module's "?" badge: tapping the same
-- badge again closes it, tapping a different one just swaps the text.
function BuildPanel:_showInfo(definition: ModuleCatalog.ModuleDef)
	if self._infoOpenId == definition.id then
		self._info.Visible = false
		self._infoOpenId = nil
		return
	end
	self._infoOpenId = definition.id
	self._infoTitle.Text = definition.name
	self._infoText.Text = definition.description
	self._info.Visible = true
end

function BuildPanel:Toggle()
	if self._open then
		self:Close()
	else
		self:Open()
	end
end

-- In the lobby the player has no station: none of this makes sense.
-- How many rebirths are banked, shown on the tally beside the bare button.
function BuildPanel:SetRebirths(count: number)
	self._rebirthButton:SetCounter(tostring(count))
end

function BuildPanel:SetAvailable(available: boolean)
	self._dock.Visible = available
	self._dockLeft.Visible = available
	if not available then
		self:Close()
		self._active.Visible = false
		self._toast.Visible = false
	end
end

function BuildPanel:SetCategory(name: string)
	self._category = name
	for tabName, tab in self._tabs do
		tab:SetLifted(tabName == name)
		tab:SetColor(if tabName == name then FUNCTION.Build else COLORS.MenuInner)
	end
	for _, entry in self._entries do
		entry.card.Root.Visible = name == ALL or entry.definition.category == name
	end
end

function BuildPanel:SetSelected(id: string?)
	self._selected = id
	for entryId, entry in self._entries do
		entry.card:SetLifted(entryId == id)
	end
	self._openButton:SetLifted(id ~= nil)

	local definition = if id then ModuleCatalog.get(id) else nil
	self._active.Visible = definition ~= nil
	if definition then
		self._activeBadge.BackgroundColor3 = ModuleVisuals.colorOf(definition.id) or COLORS.Card
		self._activeIcon.Image = ModuleVisuals.iconFor(definition.id) or ""
		self._activeName.Text = definition.name
	end
end

-- Dims modules out of budget: the player sees what they can afford to place.
function BuildPanel:SetCredits(credits: number)
	self._credits = credits
	local affordable = 0
	for _, entry in self._entries do
		local canAfford = credits >= entry.definition.cost
		if canAfford then
			affordable += 1
		end
		local color = ModuleVisuals.colorOf(entry.definition.id) or COLORS.Card
		entry.card:SetColor(if canAfford then color else Theme.darken(color, 0.6))
		entry.labels.cost.TextColor3 = if canAfford then COLORS.Credit else COLORS.Invalid
		entry.labels.name.TextColor3 = if canAfford then COLORS.Text else COLORS.TextDim
	end

	-- Badge on the open button: how many modules are within budget.
	self._openButton:SetBadge(if affordable > 0 then tostring(affordable) else nil)
end

function BuildPanel:SetUpgrading(active: boolean)
	self._upgradeButton:SetLifted(active)

	if active then
		self._active.Visible = true
		self._activeBadge.BackgroundColor3 = FUNCTION.Info
		self._activeIcon.Image = Icons.Stars["Star"]
		self._activeName.Text = "Amélioration"
		self._activeHint.Text = "clic sur un module   ·   clic droit annuler"
	else
		self._activeHint.Text = "R pivoter   ·   clic droit annuler"
		self._active.Visible = self._selected ~= nil
		if self._selected then
			self:SetSelected(self._selected)
		end
	end
end

function BuildPanel:SetModifying(active: boolean)
	self._modifyButton:SetLifted(active)

	if active then
		self._active.Visible = true
		self._activeBadge.BackgroundColor3 = FUNCTION.Move
		self._activeIcon.Image = Icons.Menus["Teleport"]
		self._activeName.Text = "Modification"
		self._activeHint.Text = "clic ramasser/poser   ·   clic droit annuler"
	else
		self._activeHint.Text = "R pivoter   ·   clic droit annuler"
		self._active.Visible = self._selected ~= nil
		if self._selected then
			self:SetSelected(self._selected)
		end
	end
end

function BuildPanel:SetDemolishing(active: boolean)
	self._demolishButton:SetLifted(active)

	if active then
		self._active.Visible = true
		self._activeBadge.BackgroundColor3 = COLORS.Invalid
		self._activeIcon.Image = Icons.Menus["Trash"]
		self._activeName.Text = "Démolition"
		self._activeHint.Text = "clic sur un module   ·   clic droit annuler"
	else
		self._activeHint.Text = "R pivoter   ·   clic droit annuler"
		self._active.Visible = self._selected ~= nil
		if self._selected then
			self:SetSelected(self._selected)
		end
	end
end

function BuildPanel:ShowConfirm(
	title: string,
	body: string,
	confirmColor: Color3,
	onConfirm: () -> ()
)
	self._confirmTitle.Text = title
	self._confirmBody.Text = body
	self._confirmOk:SetColor(confirmColor)
	-- The header tile takes the same colour as the confirm button: the dialog
	-- announces which action it is about before the title has been read.
	self._confirmIcon.BackgroundColor3 = confirmColor
	self._confirmCallback = onConfirm
	self._confirm.Visible = true
	self._confirmScale.Scale = 0.85
	TweenService:Create(self._confirmScale, Theme.Tween.Pop, { Scale = 1 }):Play()
end

function BuildPanel:Toast(message: string, isError: boolean?)
	self._toastLabel.Text = message
	self._toastIcon.Image = if isError then Icons.Misc["Deny"] else Icons.Misc["Accept"]
	self._toast.BackgroundColor3 = if isError
		then Theme.darken(COLORS.Invalid, 0.3)
		else Theme.darken(COLORS.Valid, 0.3)
	self._toast.Visible = true

	self._toastScale.Scale = 0.7
	TweenService:Create(self._toastScale, Theme.Tween.Pop, { Scale = 1 }):Play()

	self._toastToken = (self._toastToken or 0) + 1
	local token = self._toastToken
	task.delay(1.5, function()
		if self._toastToken == token then
			self._toast.Visible = false
		end
	end)
end

return BuildPanel
