--!strict
-- The research zone's window: what the mine has produced, what it is worth,
-- and the exchange that turns it into credits.
--
-- A VIEW. It holds no rule and asks the server for nothing -- it renders the
-- ore counts it is handed and reports which button was pressed. Prices come
-- from the catalogue (shared with the server, so the figure on the row and
-- the credit that lands cannot disagree); the sale itself is Application's.
--
-- Laid out as a BACKPACK -- a fixed grid of slots, not a list of rows.
--
-- Every mineral in the catalogue always has its slot, including ones held at
-- zero: a bag that only shows what you already carry cannot tell a player
-- what there is to find, which on a zone built around four depths is most of
-- what this panel is for. The grid is padded out to full rows with empty
-- slots, and those are the point rather than filler -- a bag with visible
-- room reads as a bag, a grid with gaps reads as a broken table, and a new
-- mineral drops into one with no layout change.
--
-- Each slot shows the mineral's ACTUAL 3D model (Theme.modelThumb over
-- ReplicatedStorage.ResearchModels.Ore_<id>), ringed in its rarity colour.
-- That is what makes the bag worth looking at: it holds the same objects the
-- player just dug out of the pit, not five recolours of one gem glyph.

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
local Rarity = require(fromShared("Domain/Research/Rarity"))
local Icons = require(fromShared("Icons"))
local Theme = require("./Theme")

local COLORS = Theme.Colors
local SPACE = Theme.Space
local FUNCTION = Theme.Function
local WORDS = Theme.Words.Research

-- Height measured, not guessed: the grid gets what is left after the header,
-- the footer AND the panel's own xl padding on both edges (172 in total), so
-- 400 leaves 228 for two rows of 102 with their 10 of gap. Anything less
-- scrolls a bag that has nothing to scroll.
local PANEL = Vector2.new(600, 400)
local HEADER_ICON = 44
local FOOTER_HEIGHT = Theme.Control.md

-- Five across, two down. Five is the catalogue's length today, so the first
-- row is exactly the minerals that exist and the second is the room left.
local COLUMNS = 5
local SLOTS = 10
local SLOT = 102
local SLOT_GAP = 10
local SLOT_PAD = 5
local BAND = 20

local ResearchPanel = {}
ResearchPanel.__index = ResearchPanel

export type ResearchPanel = typeof(setmetatable({} :: any, ResearchPanel))

----------------------------------------------------------------------

-- The mineral's own 3D model, the very object dug out of the pit -- or nil
-- when none has been placed for this ore yet. Same authored-with-fallback
-- arrangement the mine builder uses for the veins themselves, and the same
-- `if game` guard, so this module still loads under Lune.
local function oreModel(ore: OreCatalog.Ore): Model?
	if not game then
		return nil
	end
	local folder = (game :: any):GetService("ReplicatedStorage"):FindFirstChild("ResearchModels")
	local template = folder and folder:FindFirstChild(`Ore_{ore.id}`)
	return if template and template:IsA("Model") then template else nil
end

-- The room left in the bag. Real slots the catalogue has not filled yet, not
-- decoration: a new mineral drops into one with no layout change.
local function buildEmptySlot(order: number): Frame
	return Theme.new("Frame", {
		Name = "EmptySlot",
		LayoutOrder = order,
		Size = UDim2.fromOffset(SLOT, SLOT),
		BackgroundColor3 = Theme.Glass.Color,
		BackgroundTransparency = Theme.Glass.Well + 0.3,
	}, {
		Theme.corner(Theme.Radius.md),
		Theme.new("UIStroke", {
			Color = COLORS.TextDim,
			Thickness = Theme.Line.thin,
			Transparency = 0.65,
		}),
	})
end

-- One slot of the bag. Returns the pieces the panel writes into later rather
-- than the frame alone: re-finding a label by name on every attribute change
-- is a lookup per mineral per tick for no reason.
local function buildSlot(ore: OreCatalog.Ore, order: number)
	local colour = Color3.fromRGB(ore.colour.R, ore.colour.G, ore.colour.B)
	local tier = Rarity.get(ore.rarity)
	local ringColour = (tier and Theme.Rarity[tier.id]) or COLORS.TextDim

	local artSize = math.floor(SLOT * 0.58)
	local artProps: { [string]: any } = {
		Name = "Art",
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- Centred in the space ABOVE the name band, not in the slot, or the
		-- band cuts the bottom off the mineral.
		Position = UDim2.new(0.5, 0, 0, (SLOT - BAND) / 2),
		Size = UDim2.fromOffset(artSize, artSize),
	}

	-- The model when there is one, the mineral's own colour when there is
	-- not. That colour is the same one its vein glows with down in the pit,
	-- so even the fallback still says WHICH mineral this is.
	local model = oreModel(ore)
	local art: GuiObject
	if model then
		art = Theme.modelThumb(model, artProps)
	else
		local merged = table.clone(artProps)
		merged.BackgroundColor3 = colour
		art = Theme.new("Frame", merged, {
			Theme.corner(Theme.Radius.sm),
			Theme.gradient(colour, 0.22),
		})
	end

	-- A ring, not a stroke on the tile itself: Theme.chunky already owns the
	-- tile's own outline, and a second UIStroke on the same instance fights
	-- it. A transparent frame carrying its own is free of that.
	local ring = Theme.new("Frame", {
		Name = "Ring",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 6,
	}, {
		Theme.corner(Theme.Radius.md),
		Theme.new("UIStroke", { Color = ringColour, Thickness = Theme.Line.base }),
	})
	local ringStroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke

	local nameLabel = Theme.new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromOffset(SPACE.xs, 0),
		Size = UDim2.new(1, -SPACE.sm, 1, 0),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.caption,
		TextColor3 = COLORS.Text,
		TextScaled = true,
		TextWrapped = false,
		Text = ore.name,
	}, {
		Theme.textStroke(Theme.Line.thin),
		Theme.new("UITextSizeConstraint", {
			MaxTextSize = Theme.TextSize.caption,
			MinTextSize = 7,
		}),
	})

	local band = Theme.new("Frame", {
		Name = "NameBand",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -SLOT_PAD),
		Size = UDim2.new(1, -SLOT_PAD * 2, 0, BAND),
		BackgroundColor3 = COLORS.Scrim,
		BackgroundTransparency = 0.25,
		ZIndex = 4,
	}, { Theme.corner(Theme.Radius.sm), nameLabel })

	-- Top-right, over the art: the count is what a player scans a bag for,
	-- and that corner is where every inventory has taught them to look.
	local count = Theme.new("TextLabel", {
		Name = "Count",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -SLOT_PAD * 2, 0, SLOT_PAD),
		Size = UDim2.fromOffset(52, 22),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.body,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Right,
		Text = WORDS.Held(0),
		ZIndex = 7,
	}, { Theme.textStroke(Theme.Line.base) })

	-- The whole slot is the button. Clicking a bag slot to use what is in it
	-- is the convention players arrive with, and a separate "Échanger"
	-- button would not fit at this size anyway.
	local slot = Theme.chunky({
		Name = `Ore_{ore.id}`,
		LayoutOrder = order,
		Size = UDim2.fromOffset(SLOT, SLOT),
		BackgroundColor3 = Theme.Glass.Color,
		Radius = Theme.Radius.md,
		Inner = true,
	}, { art, band, ring, count })

	-- A ViewportFrame dims through ImageTransparency and a flat swatch
	-- through its background: one closure, so the panel never has to know
	-- which of the two this slot ended up with.
	local function setCarried(carried: boolean)
		count.TextTransparency = if carried then 0 else 0.55
		nameLabel.TextTransparency = if carried then 0 else 0.45
		ringStroke.Transparency = if carried then 0 else 0.6
		if art:IsA("ViewportFrame") then
			(art :: ViewportFrame).ImageTransparency = if carried then 0 else 0.7
		else
			(art :: Frame).BackgroundTransparency = if carried then 0 else 0.7
		end
	end

	return {
		Root = slot.Root,
		Face = slot.Face,
		Count = count,
		SetCarried = setCarried,
		Ore = ore,
	}
end

----------------------------------------------------------------------

function ResearchPanel.new(parent: Instance): ResearchPanel
	local self = setmetatable({}, ResearchPanel)

	-- (oreId: string?) -> () -- nil means the whole bag.
	self.onSell = nil :: ((string?) -> ())?

	self._open = false
	self._unlocked = false
	self._counts = {} :: { [string]: number }
	self._slots = {} :: { [string]: any }

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
		-- The backpack, matching the dock button that opens this window.
		Image = Icons.Menus["Inventory"],
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
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = WORDS.Locked,
		Visible = false,
	})

	local listTop = HEADER_ICON + SPACE.lg
	local listBottom = FOOTER_HEIGHT + SPACE.lg

	self._grid = Theme.new("ScrollingFrame", {
		Name = "Bag",
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
		Theme.new("UIGridLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			CellSize = UDim2.fromOffset(SLOT, SLOT),
			CellPadding = UDim2.fromOffset(SLOT_GAP, SLOT_GAP),
			-- Pinned to a fixed count rather than left to the width: five per
			-- row is the layout, and a bag that reflows as the window changes
			-- size is a bag whose slots move under the player's hand.
			FillDirectionMaxCells = COLUMNS,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
		}),
	})

	-- Catalogue order, which is depth order: the bag reads as a descent,
	-- surface mineral first.
	for index, ore in OreCatalog.Ores do
		local slot = buildSlot(ore, index)
		slot.Root.Parent = self._grid
		self._slots[ore.id] = slot
		self._counts[ore.id] = 0
		slot.Face.Activated:Connect(function()
			if self.onSell and (self._counts[ore.id] or 0) > 0 then
				self.onSell(ore.id)
			end
		end)
	end

	for index = #OreCatalog.Ores + 1, SLOTS do
		buildEmptySlot(index).Parent = self._grid
	end

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
		Position = UDim2.new(1, 0, 1, 0),
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
		Position = UDim2.new(0, 0, 1, 0),
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
		self._grid,
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
	self._grid.Visible = self._unlocked
	self._total.Visible = self._unlocked
	self._sellAll.Root.Visible = self._unlocked

	-- One line, two jobs. An empty bag showing "Valeur totale : 0 ¢" states
	-- the obvious and helps nobody, and the old overlay that said so instead
	-- covered the very slots that teach what there is to find.
	self._total.Text = if hasAny then WORDS.Total(total) else WORDS.Empty
	self._total.TextColor3 = if hasAny then FUNCTION.Money else COLORS.TextDim

	for id, slot in self._slots do
		local count = self._counts[id] or 0
		slot.Count.Text = WORDS.Held(count)
		-- Dimmed, never hidden: an empty slot still has to say which mineral
		-- belongs in it, which is half of what the bag is for.
		slot.SetCarried(count > 0)
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
