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

local Icons = require(fromShared("Icons"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local ModuleVisuals = require("./ModuleVisuals")
local Theme = require("./Theme")

-- Module geometry, for the card thumbnails. With a timeout: if the folder
-- is missing, fall back to the icon pack rather than blocking the menu.
local ModuleModels = ReplicatedStorage:WaitForChild("ModuleModels", 10)
if not ModuleModels then
	warn("[BuildPanel] ReplicatedStorage.ModuleModels missing -- cards fall back to icons")
end

local COLORS = Theme.Colors
local FUNCTION = Theme.Function
local SPACE = Theme.Space

-- Height set for 3 rows of cards: 3 x 160 + 2 x 12 = 504 px. The whole
-- catalogue fits without scrolling.
local PANEL = Vector2.new(840, 640)
local RAIL_WIDTH = 176
local CARD = Vector2.new(134, 160)
local TITLE_HEIGHT = 44
local ICON = Theme.Icon.button
local ICON_TOTAL = ICON + 20

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

local function buildCard(definition: ModuleCatalog.ModuleDef)
	local nameLabel = Theme.body({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, SPACE.sm),
		Size = UDim2.new(1, -SPACE.md, 0, 34),
		TextSize = Theme.TextSize.small,
		TextWrapped = true,
		Text = definition.name,
	})

	local children = { nameLabel }

	-- Show the object itself rather than a generic icon: the player
	-- recognizes what they're about to place. The icon pack stays the
	-- fallback, for a module without a model yet.
	local template = if ModuleModels then ModuleModels:FindFirstChild(definition.id) else nil
	if template and template:IsA("Model") then
		table.insert(
			children,
			Theme.modelThumb(template, {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 40),
				Size = UDim2.fromOffset(68, 64),
			})
		)
	else
		local iconId = ModuleVisuals.iconFor(definition.id)
		if iconId then
			table.insert(
				children,
				image(iconId, {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 44),
					Size = UDim2.fromOffset(56, 56),
				})
			)
		end
	end

	table.insert(
		children,
		Theme.body({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 104),
			Size = UDim2.new(1, -SPACE.sm, 0, 16),
			TextSize = Theme.TextSize.caption,
			Text = statLine(definition),
		})
	)

	local costLabel = Theme.body({
		Position = UDim2.fromOffset(26, 0),
		Size = UDim2.new(1, -30, 1, 0),
		TextSize = Theme.TextSize.small,
		TextColor3 = COLORS.Credit,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = tostring(definition.cost),
	})

	table.insert(
		children,
		Theme.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -SPACE.sm),
			Size = UDim2.fromOffset(94, 26),
			BackgroundColor3 = COLORS.Scrim,
		}, {
			Theme.corner(13),
			Theme.stroke(nil, Theme.Line.thin),
			image(Icons.Cash["CashIcon"], {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 5, 0.5, 0),
				Size = UDim2.fromOffset(18, 18),
			}),
			costLabel,
		})
	)

	-- The classic "?" badge: what a module actually does, one tap away.
	-- A separate top-layer TextButton, not part of the card's own Face --
	-- Activated only ever fires on the topmost object under the pointer, so
	-- tapping it can never also select the card underneath.
	local infoButton = Theme.new("TextButton", {
		Name = "Info",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -4, 0, 4),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = COLORS.Accent,
		AutoButtonColor = false,
		Font = Theme.Font.Display,
		TextSize = 14,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "?",
		ZIndex = 2,
	}, { Theme.corner(11), Theme.stroke(nil, Theme.Line.thin) })
	table.insert(children, infoButton)

	-- The card takes the module's color: this is what makes the grid
	-- readable at a glance, same as the reference art.
	local color = ModuleVisuals.colorOf(definition.id) or COLORS.Card
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
	self.onRebirthRequested = nil :: (() -> ())? -- the dock button was clicked, before any confirm
	self.onUltimateRequested = nil :: (() -> ())? -- ditto, for the Ultimate button

	self._entries = {} :: { [string]: any }
	self._selected = nil :: string?
	self._credits = 0
	self._category = ALL
	self._open = false

	----------------------------------------------------------------------
	-- Button cluster docked to the right edge

	self._dock = Theme.new("Frame", {
		Name = "Dock",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SPACE.xl, 0.5, 0),
		Size = UDim2.fromOffset(ICON, ICON_TOTAL * 7 + SPACE.sm * 6),
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

	self._lobbyButton = Theme.iconButton({
		Name = "Lobby",
		LayoutOrder = 5,
		Color = FUNCTION.Lobby,
		Image = Icons.Misc["House"],
		Caption = "Lobby",
	})
	self._lobbyButton.Root.Parent = self._dock

	-- Only ever shown while on the station (SetAvailable), same as the
	-- rest of the dock -- eligibility itself is NOT precomputed here (no
	-- client-side core-level tracking exists): clicking always asks the
	-- server, whose refusal reason (not eligible yet, disabled this zone,
	-- ...) is shown as an ordinary toast, same pattern as every other action.
	self._rebirthButton = Theme.iconButton({
		Name = "Renaissance",
		LayoutOrder = 6,
		Color = FUNCTION.Rebirth,
		Image = Icons.Arrows["Rebirth"],
		Caption = "Renaissance",
	})
	self._rebirthButton.Root.Parent = self._dock

	-- Hidden once owned (SetUltimateOwned) -- it's a one-time purchase, not
	-- a repeatable action like everything else in this dock; once bought
	-- there is nothing left to click, and the HUD already shows it's active.
	self._ultimateButton = Theme.iconButton({
		Name = "Ultimate",
		LayoutOrder = 7,
		Color = FUNCTION.Ultimate,
		Image = Icons.Menus["VIP"],
		Caption = "Ultimate",
	})
	-- Permanent, not an affordability count like Construire's badge: the
	-- x1.5 multiplier this button grants, spelled out right on it.
	self._ultimateButton:SetBadge("x1,5")
	self._ultimateButton.Root.Parent = self._dock

	----------------------------------------------------------------------
	-- Scrim

	self._scrim = Theme.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.Scrim,
		BackgroundTransparency = 0.4,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
		ZIndex = 5,
		Parent = parent,
	})

	----------------------------------------------------------------------
	-- Window

	local title = Theme.new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -(Theme.Control.md + SPACE.md), 0, TITLE_HEIGHT),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.display,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "CONSTRUCTION",
	}, { Theme.textStroke(Theme.Line.base) })

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

	local contentTop = TITLE_HEIGHT + SPACE.lg

	local rail = Theme.new("Frame", {
		Name = "Rail",
		Position = UDim2.fromOffset(0, contentTop),
		Size = UDim2.new(0, RAIL_WIDTH, 1, -contentTop),
		BackgroundTransparency = 1,
	}, {
		Theme.new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, SPACE.sm),
		}),
	})

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
	local well = Theme.panel({
		Name = "Well",
		Position = UDim2.fromOffset(RAIL_WIDTH + SPACE.lg, contentTop),
		Size = UDim2.new(1, -(RAIL_WIDTH + SPACE.lg), 1, -contentTop),
		BackgroundColor3 = COLORS.MenuInner,
		Radius = Theme.Radius.lg,
	}, { Theme.padding(SPACE.sm + 2), self._grid })

	self._panelScale = Theme.new("UIScale", { Scale = 1 })

	self._panel = Theme.panel({
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		BackgroundColor3 = COLORS.Menu,
		Radius = Theme.Radius.xl,
		StrokeColor = COLORS.Inner,
		StrokeThickness = 5,
		Visible = false,
		ZIndex = 6,
		Parent = parent,
	}, { Theme.padding(SPACE.xl), title, self._close.Root, rail, well, self._panelScale })

	----------------------------------------------------------------------
	-- Category tabs

	self._tabs = {}
	local tabOrder = 0
	local categories = { ALL }
	for _, name in ModuleCatalog.Categories do
		table.insert(categories, name)
	end

	for _, name in categories do
		tabOrder += 1
		local iconId = ModuleVisuals.CategoryIcons[name]
		local children = {
			Theme.body({
				Position = UDim2.fromOffset(46, 0),
				Size = UDim2.new(1, -54, 1, 0),
				TextSize = Theme.TextSize.small,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = name,
			}),
		}
		if iconId then
			table.insert(
				children,
				image(iconId, {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, SPACE.md, 0.5, 0),
					Size = UDim2.fromOffset(24, 24),
				})
			)
		end

		local tab = Theme.chunky({
			Name = name,
			Size = UDim2.new(1, 0, 0, Theme.Control.md),
			BackgroundColor3 = COLORS.MenuInner,
			Radius = Theme.Radius.md,
			Inner = true,
		}, children)
		tab.Root.LayoutOrder = tabOrder
		tab.Root.Parent = rail
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
		Position = UDim2.new(0.5, 0, 1, -SPACE.xl),
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
		Position = UDim2.new(0.5, 0, 1, -SPACE.xl),
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
		Position = UDim2.new(0.5, 0, 1, -(SPACE.xl + 60 + SPACE.md)),
		Size = UDim2.fromOffset(440, Theme.Control.md),
		BackgroundColor3 = COLORS.PanelDeep,
		Radius = Theme.Radius.lg,
		Inner = true,
		Visible = false,
		ZIndex = 8,
		Parent = parent,
	}, { self._toastIcon, self._toastLabel, self._toastScale })

	----------------------------------------------------------------------
	-- Generic confirmation modal -- shared by Rebirth (destructive: wipes
	-- the station and credits) and Ultimate (a purchase, real money down
	-- the line): both always ask first, unlike every toggleable mode above.
	-- BuildPanel only displays; the title/body wording and what happens on
	-- confirm are entirely the caller's call, via ShowConfirm below.

	self._confirmTitle = Theme.new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(SPACE.xl, SPACE.xl),
		Size = UDim2.new(1, -SPACE.xl * 2, 0, 36),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.display,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	}, { Theme.textStroke(Theme.Line.base) })

	self._confirmBody = Theme.prose({
		Position = UDim2.fromOffset(SPACE.xl, SPACE.xl + 40),
		Size = UDim2.new(1, -SPACE.xl * 2, 0, 90),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
	})

	local confirmCancel = Theme.chunky({
		Name = "Cancel",
		Position = UDim2.new(0, SPACE.xl, 1, -(SPACE.xl + Theme.Control.md)),
		Size = UDim2.fromOffset(160, Theme.Control.md),
		BackgroundColor3 = COLORS.MenuInner,
		Radius = Theme.Radius.md,
		Inner = true,
	}, {
		Theme.body({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "Annuler",
		}),
	})

	self._confirmButton = Theme.chunky({
		Name = "Confirm",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -SPACE.xl, 1, -(SPACE.xl + Theme.Control.md)),
		Size = UDim2.fromOffset(220, Theme.Control.md),
		BackgroundColor3 = FUNCTION.Rebirth,
		Radius = Theme.Radius.md,
		Inner = true,
	}, {
		Theme.body({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.new(1, 1, 1),
			Text = "Confirmer",
		}),
	})

	self._confirm = Theme.panel({
		Name = "Confirm",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(480, 220),
		BackgroundColor3 = COLORS.Menu,
		Radius = Theme.Radius.xl,
		StrokeColor = COLORS.Inner,
		StrokeThickness = 5,
		Visible = false,
		ZIndex = 9,
		Parent = parent,
	}, { self._confirmTitle, self._confirmBody, confirmCancel.Root, self._confirmButton.Root })

	confirmCancel.Face.Activated:Connect(function()
		self._confirm.Visible = false
		self._pendingConfirm = nil
	end)
	self._confirmButton.Face.Activated:Connect(function()
		self._confirm.Visible = false
		local pending = self._pendingConfirm
		self._pendingConfirm = nil
		if pending then
			pending()
		end
	end)

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
	self._modifyButton.Button.Face.Activated:Connect(function()
		if self.onToggleModify then
			self.onToggleModify()
		end
	end)
	self._demolishButton.Button.Face.Activated:Connect(function()
		if self.onToggleDemolish then
			self.onToggleDemolish()
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
	self._ultimateButton.Button.Face.Activated:Connect(function()
		if self.onUltimateRequested then
			self.onUltimateRequested()
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

-- Generic: title/body wording and what happens on confirm are entirely the
-- caller's call (BuildController) -- this module only displays, per its own
-- header. confirmColor tints the Confirm button, so Rebirth (magenta) and
-- Ultimate (gold) read as visually distinct actions, not the same dialog
-- reused blindly.
function BuildPanel:ShowConfirm(
	title: string,
	body: string,
	confirmColor: Color3,
	onConfirm: () -> ()
)
	self._confirmTitle.Text = title
	self._confirmBody.Text = body
	self._confirmButton:SetColor(confirmColor)
	self._pendingConfirm = onConfirm
	self._confirm.Visible = true
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
function BuildPanel:SetAvailable(available: boolean)
	self._dock.Visible = available
	if not available then
		self:Close()
		self._active.Visible = false
		self._toast.Visible = false
		self._confirm.Visible = false
		self._pendingConfirm = nil
	end
end

-- Hides the Ultimate button once it's owned: nothing left to buy, and the
-- HUD already shows it's active.
function BuildPanel:SetUltimateOwned(owned: boolean)
	self._ultimateButton.Root.Visible = not owned
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
		self._activeHint.Text =
			"clic pour saisir/déposer   ·   R pivoter   ·   clic droit annuler"
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
