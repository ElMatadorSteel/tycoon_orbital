--!strict
-- The research zone's window: what the mine has produced, what it is worth,
-- and the exchange that turns it into credits.
--
-- A VIEW. It holds no rule and asks the server for nothing -- it renders the
-- ore counts it is handed and reports which button was pressed. Prices come
-- from the catalogue (shared with the server, so the figure on the row and
-- the credit that lands cannot disagree); the sale itself is Application's.
--
-- One row per mineral in the catalogue, ALWAYS, including minerals held at
-- zero. A list that only shows what you already have cannot tell a player
-- what there is to find, which on a zone built around four depths is most of
-- what the panel is for.

local TweenService = game:GetService("TweenService")

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Client and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach. Lune has no `game`, so the
-- fallback below -- an ordinary relative require -- is what runs there.
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

local OreCatalog = require(fromShared("Domain/Research/OreCatalog"))
local Icons = require(fromShared("Icons"))
local Theme = require("./Theme")

local COLORS = Theme.Colors
local SPACE = Theme.Space
local FUNCTION = Theme.Function
local WORDS = Theme.Words.Research

local PANEL = Vector2.new(560, 520)
local HEADER_ICON = 44
local ROW_HEIGHT = 64
local SWATCH = 40
local FOOTER_HEIGHT = Theme.Control.md
local SELL_WIDTH = 110

local ResearchPanel = {}
ResearchPanel.__index = ResearchPanel

export type ResearchPanel = typeof(setmetatable({} :: any, ResearchPanel))

----------------------------------------------------------------------

-- One mineral. Returns the pieces the panel has to write into later rather
-- than the frame alone: re-finding a label by name on every attribute change
-- is a lookup per ore per tick for no reason.
local function buildRow(ore: OreCatalog.Ore, order: number)
	local colour = Color3.fromRGB(ore.colour.R, ore.colour.G, ore.colour.B)

	-- The mineral's own colour, the same one its vein glows with down in the
	-- pit. That is the whole identification system for this panel: no icon
	-- pack has a distinct glyph per ore, and four colours a player has
	-- already seen underground beat four copies of one generic gem.
	local swatch = Theme.new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SPACE.md, 0.5, 0),
		Size = UDim2.fromOffset(SWATCH, SWATCH),
		BackgroundColor3 = colour,
	}, {
		Theme.corner(Theme.Radius.sm),
		Theme.stroke(nil, Theme.Line.base),
		Theme.gradient(colour, 0.22),
	})

	local textLeft = SPACE.md + SWATCH + SPACE.md

	local name = Theme.body({
		Name = "Name",
		Position = UDim2.fromOffset(textLeft, SPACE.sm),
		Size = UDim2.new(1, -textLeft, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = ore.name,
	})

	local detail = Theme.caption({
		Name = "Detail",
		Position = UDim2.fromOffset(textLeft, SPACE.sm + 20),
		Size = UDim2.new(1, -textLeft, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = `{WORDS.Depth(ore.depth)}  \u{00B7}  {WORDS.UnitValue(ore.value)}`,
	})

	-- Right-aligned, and the widest thing on the row after the name: the
	-- count is what a player scans the list for.
	--
	-- Held clear of the button by a full gap, not butted against it. At zero
	-- clearance the two boxes only touched -- no overlap -- but the button's
	-- heavy outline and gradient run right to its edge, and a figure that
	-- ends exactly there reads as one clipped by the button.
	local held = Theme.new("TextLabel", {
		Name = "Held",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(SELL_WIDTH + SPACE.md * 2), 0.5, 0),
		Size = UDim2.fromOffset(80, 24),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.title,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = WORDS.Held(0),
	}, { Theme.textStroke(Theme.Line.base) })

	local sellLabel = Theme.body({
		Size = UDim2.fromScale(1, 1),
		Text = WORDS.Sell,
	})
	local sell = Theme.chunky({
		Name = "Sell",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -SPACE.md, 0.5, 0),
		Size = UDim2.fromOffset(SELL_WIDTH, Theme.Control.sm),
		BackgroundColor3 = FUNCTION.Money,
		Radius = Theme.Radius.md,
		Inner = true,
	}, { sellLabel })

	local root = Theme.panel({
		Name = `Ore_{ore.id}`,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		BackgroundColor3 = Theme.Glass.Color,
		BackgroundTransparency = Theme.Glass.Well,
		Radius = Theme.Radius.md,
		Inner = true,
	}, { swatch, name, detail, held, sell.Root })

	return { Root = root, Held = held, Sell = sell, Ore = ore }
end

----------------------------------------------------------------------

function ResearchPanel.new(parent: Instance): ResearchPanel
	local self = setmetatable({}, ResearchPanel)

	-- (oreId: string?) -> () -- nil means the whole bag.
	self.onSell = nil :: ((string?) -> ())?

	self._open = false
	self._unlocked = false
	self._counts = {} :: { [string]: number }
	self._rows = {} :: { [string]: any }

	-- Same click-catcher as BuildPanel's: invisible, but it is what closes
	-- the window on a tap outside it.
	self._scrim = Theme.new("TextButton", {
		Name = "ResearchScrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 6,
		Parent = parent,
	})

	local headerIcon = Theme.new("ImageLabel", {
		Name = "Icon",
		Size = UDim2.fromOffset(HEADER_ICON, HEADER_ICON),
		BackgroundTransparency = 1,
		Image = Icons.Gems["GemIcon"],
		ScaleType = Enum.ScaleType.Fit,
	})

	local headerLeft = HEADER_ICON + SPACE.md

	local title = Theme.new("TextLabel", {
		Name = "Title",
		Position = UDim2.fromOffset(headerLeft, 0),
		Size = UDim2.new(1, -headerLeft, 0, 26),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.title,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = WORDS.Title,
	}, { Theme.textStroke(Theme.Line.base) })

	local subtitle = Theme.caption({
		Name = "Subtitle",
		Position = UDim2.fromOffset(headerLeft, 26),
		Size = UDim2.new(1, -headerLeft, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = WORDS.Subtitle,
	})

	local header = Theme.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER_ICON),
		BackgroundTransparency = 1,
	}, { headerIcon, title, subtitle })

	-- Shown INSTEAD of the list before the pad has been paid for. The window
	-- is reachable either way on purpose: a menu that appears out of nowhere
	-- once you buy something teaches nothing, and this is where a player
	-- finds out the zone exists.
	self._locked = Theme.prose({
		Name = "Locked",
		Position = UDim2.fromOffset(0, HEADER_ICON + SPACE.lg),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = WORDS.Locked,
		Visible = false,
	})

	local listTop = HEADER_ICON + SPACE.lg
	local listBottom = FOOTER_HEIGHT + SPACE.lg

	self._list = Theme.new("ScrollingFrame", {
		Name = "Ores",
		Position = UDim2.fromOffset(0, listTop),
		Size = UDim2.new(1, 0, 1, -(listTop + listBottom)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = COLORS.Text,
		ScrollBarImageTransparency = 0.6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, {
		Theme.new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, SPACE.sm),
		}),
	})

	-- Catalogue order, which is depth order: the list reads as a descent,
	-- surface mineral first.
	for index, ore in OreCatalog.Ores do
		local row = buildRow(ore, index)
		row.Root.Parent = self._list
		self._rows[ore.id] = row
		self._counts[ore.id] = 0
		row.Sell.Face.Activated:Connect(function()
			if self.onSell and (self._counts[ore.id] or 0) > 0 then
				self.onSell(ore.id)
			end
		end)
	end

	-- Shown over the list when every line is at zero. A row of four "x0"s
	-- answers "what can I find", but not "why is this empty".
	self._empty = Theme.prose({
		Name = "Empty",
		Position = UDim2.fromOffset(0, listTop),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = WORDS.Empty,
		Visible = false,
	})

	self._total = Theme.body({
		Name = "Total",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -(FOOTER_HEIGHT + SPACE.sm)),
		Size = UDim2.new(1, 0, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = FUNCTION.Money,
		Text = WORDS.Total(0),
	})

	local sellAllLabel = Theme.body({
		Size = UDim2.fromScale(1, 1),
		Text = WORDS.SellAll,
	})
	self._sellAll = Theme.chunky({
		Name = "SellAll",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromOffset(200, FOOTER_HEIGHT),
		BackgroundColor3 = FUNCTION.Money,
		Radius = Theme.Radius.md,
		Inner = true,
	}, { sellAllLabel })

	local closeLabel = Theme.body({
		Size = UDim2.fromScale(1, 1),
		Text = WORDS.Close,
	})
	self._close = Theme.chunky({
		Name = "Close",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(150, FOOTER_HEIGHT),
		BackgroundColor3 = COLORS.MenuInner,
		Radius = Theme.Radius.md,
		Inner = true,
	}, { closeLabel })

	self._scale = Theme.new("UIScale", { Scale = 1 })

	self._panel = Theme.panel({
		Name = "ResearchPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		-- The same glass as the build window: they are the same product.
		BackgroundColor3 = Theme.Glass.Color,
		BackgroundTransparency = Theme.Glass.Body,
		Radius = Theme.Radius.xl,
		StrokeThickness = Theme.Line.thick,
		Inner = true,
		Visible = false,
		ZIndex = 7,
		Parent = parent,
	}, {
		Theme.padding(SPACE.xl),
		header,
		self._locked,
		self._list,
		self._empty,
		self._total,
		self._sellAll.Root,
		self._close.Root,
		self._scale,
	})

	self._scrim.Activated:Connect(function()
		self:Close()
	end)
	self._close.Face.Activated:Connect(function()
		self:Close()
	end)
	self._sellAll.Face.Activated:Connect(function()
		if self.onSell and self:_totalValue() > 0 then
			self.onSell(nil)
		end
	end)

	self:_refresh()
	return self
end

----------------------------------------------------------------------

function ResearchPanel:_totalValue(): number
	return OreCatalog.appraise(self._counts)
end

function ResearchPanel:_refresh()
	local total = self:_totalValue()
	local hasAny = total > 0

	self._locked.Visible = not self._unlocked
	self._list.Visible = self._unlocked
	self._empty.Visible = self._unlocked and not hasAny
	self._total.Visible = self._unlocked
	self._sellAll.Root.Visible = self._unlocked

	self._total.Text = WORDS.Total(total)

	for id, row in self._rows do
		local count = self._counts[id] or 0
		row.Held.Text = WORDS.Held(count)
		-- Dimmed rather than hidden: the row still says what the mineral is
		-- worth and how deep it sits, which is the reason to keep it on screen.
		row.Held.TextTransparency = if count > 0 then 0 else 0.55
		row.Sell.Root.Visible = count > 0
	end
end

-- One mineral's count, as published by Snapshot.ore.
function ResearchPanel:SetOre(oreId: string, count: number)
	self._counts[oreId] = math.max(0, math.floor(count))
	self:_refresh()
end

function ResearchPanel:SetUnlocked(unlocked: boolean)
	self._unlocked = unlocked
	self:_refresh()
end

function ResearchPanel:IsOpen(): boolean
	return self._open
end

function ResearchPanel:Open()
	if self._open then
		return
	end
	self._open = true
	self._scrim.Visible = true
	self._panel.Visible = true
	self._scale.Scale = 0.88
	TweenService:Create(self._scale, Theme.Tween.Pop, { Scale = 1 }):Play()
end

function ResearchPanel:Close()
	if not self._open then
		return
	end
	self._open = false
	self._scrim.Visible = false
	self._panel.Visible = false
end

function ResearchPanel:Toggle()
	if self._open then
		self:Close()
	else
		self:Open()
	end
end

return ResearchPanel
