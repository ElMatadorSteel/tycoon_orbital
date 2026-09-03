--!strict
-- The dev-mode panel: a small button docked top-right (deliberately away
-- from the build dock -- this is a testing tool, only ever parented under
-- RunService:IsStudio()).
--
-- Same rule as BuildPanel: this module only displays. It decides nothing
-- and never talks to the server -- it tells DevController through its onXxx
-- callbacks, and DevController tells it back through its SetXxx setters
-- whenever the real server-side state changes.

local TweenService = game:GetService("TweenService")

local Theme = require("./Theme")

local COLORS = Theme.Colors
local FUNCTION = Theme.Function
local SPACE = Theme.Space

local PANEL_WIDTH = 340

-- The build dock (BuildPanel) is anchored to the same right edge, vertically
-- centered, and tall enough with several buttons that its topmost one
-- already sits close to the very top of the screen -- smaller than any
-- Theme.Control token and flush against the top edge is what it takes for
-- this button to clear it without overlapping.
local DEV_BUTTON_SIZE = 32
local DEV_BUTTON_TOP = 0

local DevPanel = {}
DevPanel.__index = DevPanel

export type DevPanel = typeof(setmetatable({} :: any, DevPanel))

----------------------------------------------------------------------

local function sectionLabel(text: string): TextLabel
	return Theme.caption({
		Size = UDim2.new(1, 0, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
	})
end

-- A small state button that just flips a boolean and re-labels itself.
local function toggleButton(name: string, offText: string, onText: string, initial: boolean)
	local button = Theme.chunky({
		Name = name,
		Size = UDim2.new(1, 0, 0, Theme.Control.md),
		BackgroundColor3 = if initial then COLORS.Valid else COLORS.MenuInner,
		Radius = Theme.Radius.md,
		Inner = true,
	}, {
		Theme.body({
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.new(1, 1, 1),
			Text = if initial then onText else offText,
		}),
	})

	local state = initial
	local label = button.Face:FindFirstChild("Label") :: TextLabel

	local function paint()
		button:SetColor(if state then COLORS.Valid else COLORS.MenuInner)
		label.Text = if state then onText else offText
	end

	local obj = { Root = button.Root, Face = button.Face }
	function obj.set(_self, value: boolean)
		state = value
		paint()
	end
	function obj.get(_self): boolean
		return state
	end
	obj.Face.Activated:Connect(function()
		if obj.onToggle then
			obj.onToggle(not state)
		end
	end)
	return obj
end

local function textBox(name: string, placeholder: string): TextBox
	return Theme.new("TextBox", {
		Name = name,
		Size = UDim2.new(1, 0, 0, Theme.Control.md),
		BackgroundColor3 = COLORS.MenuInner,
		Font = Theme.Font.Body,
		TextSize = Theme.TextSize.small,
		TextColor3 = COLORS.Text,
		PlaceholderText = placeholder,
		PlaceholderColor3 = COLORS.TextDim,
		ClearTextOnFocus = false,
		Text = "",
	}, { Theme.corner(Theme.Radius.md), Theme.stroke(nil, Theme.Line.thin) })
end

local function actionButton(name: string, text: string, color: Color3)
	return Theme.chunky({
		Name = name,
		Size = UDim2.new(1, 0, 0, Theme.Control.md),
		BackgroundColor3 = color,
		Radius = Theme.Radius.md,
		Inner = true,
	}, {
		Theme.body({
			Name = "Label",
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.new(1, 1, 1),
			Text = text,
		}),
	})
end

----------------------------------------------------------------------

function DevPanel.new(parent: ScreenGui): DevPanel
	local self = setmetatable({}, DevPanel)

	self.onSetRebirths = nil :: ((count: number, resetStation: boolean) -> ())?
	self.onSetUltimate = nil :: ((enabled: boolean) -> ())?
	self.onSetEarlyRebirth = nil :: ((enabled: boolean) -> ())?
	self.onGiveCredits = nil :: ((amount: number) -> ())?
	self.onSetUnlimitedMoney = nil :: ((enabled: boolean) -> ())?
	self.onResetAll = nil :: (() -> ())?
	-- nil speed means "back to normal" -- the default lives in Balance, not
	-- in this view.
	self.onSetWalkSpeed = nil :: ((speed: number?) -> ())?

	self._open = false

	----------------------------------------------------------------------
	-- Dock button, top-right -- away from the build dock on purpose.

	self._openButton = Theme.chunky({
		Name = "DevButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -SPACE.xl, 0, DEV_BUTTON_TOP),
		Size = UDim2.fromOffset(DEV_BUTTON_SIZE, DEV_BUTTON_SIZE),
		BackgroundColor3 = Color3.fromRGB(90, 90, 100),
		Radius = Theme.Radius.md,
		Inner = true,
		Parent = parent,
	}, {
		Theme.body({
			Size = UDim2.fromScale(1, 1),
			TextSize = Theme.TextSize.small,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.new(1, 1, 1),
			Text = "DEV",
		}),
	})
	self._openButton.Face.Activated:Connect(function()
		self:Toggle()
	end)

	----------------------------------------------------------------------
	-- Window

	-- First in the list on purpose: it is the control a tester reaches for
	-- most often, since crossing the map precedes checking anything else.
	-- No bounds printed here -- they are balance numbers, and the applied
	-- value echoed back by the server is what teaches the range.
	local speedLabel = sectionLabel("DÉPLACEMENT")
	self._speedCurrent = Theme.caption({
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Vitesse : normale",
	})
	self._speedBox = textBox("SpeedBox", "Vitesse de marche")
	local applySpeed = actionButton("ApplySpeed", "Appliquer", COLORS.Valid)
	local resetSpeed = actionButton("ResetSpeed", "Vitesse normale", COLORS.MenuInner)

	local rebirthsLabel = sectionLabel("RENAISSANCES")
	self._rebirthsCurrent = Theme.caption({
		Size = UDim2.new(1, 0, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Actuel : 0",
	})
	self._rebirthsBox = textBox("RebirthsBox", "Nouveau nombre de renaissances")
	self._resetToggle = toggleButton(
		"ResetToggle",
		"Réinitialiser la station : Non",
		"Réinitialiser la station : Oui",
		false
	)
	local applyRebirths = actionButton("ApplyRebirths", "Appliquer", FUNCTION.Rebirth)

	local ultimateLabel = sectionLabel("ULTIMATE (x1,5 permanent)")
	self._ultimateToggle =
		toggleButton("UltimateToggle", "Ultimate : désactivé", "Ultimate : actif", false)

	local earlyLabel = sectionLabel("RENAISSANCE ANTICIPÉE (dès niv. 5)")
	self._earlyToggle = toggleButton("EarlyToggle", "Débloquée : non", "Débloquée : oui", false)

	local moneyLabel = sectionLabel("ARGENT")
	self._creditsBox = textBox("CreditsBox", "Montant à se donner")
	local giveCredits = actionButton("GiveCredits", "Donner", FUNCTION.Money)
	self._unlimitedToggle =
		toggleButton("UnlimitedToggle", "Argent illimité : non", "Argent illimité : oui", false)

	local resetLabel = sectionLabel("RÉINITIALISATION COMPLÈTE")
	local resetAllButton = actionButton("ResetAll", "TOUT RÉINITIALISER", COLORS.Invalid)

	local list = Theme.new("ScrollingFrame", {
		Name = "List",
		Size = UDim2.new(1, -SPACE.xl * 2, 1, -(SPACE.xl * 2 + 40)),
		Position = UDim2.fromOffset(SPACE.xl, SPACE.xl + 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = COLORS.Inner,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
	}, {
		Theme.new("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, SPACE.sm),
		}),
		speedLabel,
		self._speedCurrent,
		self._speedBox,
		applySpeed.Root,
		resetSpeed.Root,
		rebirthsLabel,
		self._rebirthsCurrent,
		self._rebirthsBox,
		self._resetToggle.Root,
		applyRebirths.Root,
		ultimateLabel,
		self._ultimateToggle.Root,
		earlyLabel,
		self._earlyToggle.Root,
		moneyLabel,
		self._creditsBox,
		giveCredits.Root,
		self._unlimitedToggle.Root,
		resetLabel,
		resetAllButton.Root,
	})

	local title = Theme.new("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -Theme.Control.md, 0, 32),
		BackgroundTransparency = 1,
		Font = Theme.Font.Display,
		TextSize = Theme.TextSize.body,
		TextColor3 = COLORS.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "MODE DEV",
	}, { Theme.textStroke(Theme.Line.base) })

	local close = Theme.chunky({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = COLORS.Invalid,
		Radius = Theme.Radius.md,
		Inner = true,
	}, {
		Theme.body({
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Color3.new(1, 1, 1),
			Text = "x",
		}),
	})
	close.Face.Activated:Connect(function()
		self:Close()
	end)

	self._panelScale = Theme.new("UIScale", { Scale = 1 })

	self._panel = Theme.panel({
		Name = "DevPanel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -SPACE.xl, 0, DEV_BUTTON_TOP + DEV_BUTTON_SIZE + SPACE.sm),
		Size = UDim2.fromOffset(PANEL_WIDTH, 620),
		BackgroundColor3 = COLORS.Menu,
		Radius = Theme.Radius.lg,
		StrokeColor = COLORS.Inner,
		StrokeThickness = 4,
		Visible = false,
		ZIndex = 9,
		Parent = parent,
	}, { Theme.padding(SPACE.xl), title, close.Root, list, self._panelScale })

	----------------------------------------------------------------------

	applySpeed.Face.Activated:Connect(function()
		local speed = tonumber(self._speedBox.Text)
		if not speed then
			return
		end
		if self.onSetWalkSpeed then
			self.onSetWalkSpeed(speed)
		end
	end)
	resetSpeed.Face.Activated:Connect(function()
		if self.onSetWalkSpeed then
			self.onSetWalkSpeed(nil)
		end
	end)

	applyRebirths.Face.Activated:Connect(function()
		local count = tonumber(self._rebirthsBox.Text)
		if not count then
			return
		end
		if self.onSetRebirths then
			self.onSetRebirths(count, self._resetToggle:get())
		end
	end)
	self._resetToggle.onToggle = function(next: boolean)
		self._resetToggle:set(next)
	end

	self._ultimateToggle.onToggle = function(next: boolean)
		if self.onSetUltimate then
			self.onSetUltimate(next)
		end
	end
	self._earlyToggle.onToggle = function(next: boolean)
		if self.onSetEarlyRebirth then
			self.onSetEarlyRebirth(next)
		end
	end

	giveCredits.Face.Activated:Connect(function()
		local amount = tonumber(self._creditsBox.Text)
		if not amount then
			return
		end
		if self.onGiveCredits then
			self.onGiveCredits(amount)
		end
	end)
	self._unlimitedToggle.onToggle = function(next: boolean)
		if self.onSetUnlimitedMoney then
			self.onSetUnlimitedMoney(next)
		end
	end

	-- Two-step confirm: first click arms it (turns white-on-red text, waits
	-- 4s), second click while armed actually fires the reset.
	local resetLabelText = resetAllButton.Face:FindFirstChild("Label") :: TextLabel
	local armed = false
	local armToken = 0
	resetAllButton.Face.Activated:Connect(function()
		if armed then
			armed = false
			resetAllButton:SetColor(COLORS.Invalid)
			resetLabelText.TextColor3 = Color3.new(1, 1, 1)
			resetLabelText.Text = "TOUT RÉINITIALISER"
			if self.onResetAll then
				self.onResetAll()
			end
			return
		end
		armed = true
		armToken += 1
		local token = armToken
		resetAllButton:SetColor(Color3.new(1, 1, 1))
		resetLabelText.TextColor3 = COLORS.Invalid
		resetLabelText.Text = "CLIQUER POUR CONFIRMER"
		task.delay(4, function()
			if armed and armToken == token then
				armed = false
				resetAllButton:SetColor(COLORS.Invalid)
				resetLabelText.TextColor3 = Color3.new(1, 1, 1)
				resetLabelText.Text = "TOUT RÉINITIALISER"
			end
		end)
	end)

	return self
end

----------------------------------------------------------------------

function DevPanel:Open()
	if self._open then
		return
	end
	self._open = true
	self._panel.Visible = true
	self._panelScale.Scale = 0.9
	TweenService:Create(self._panelScale, Theme.Tween.Pop, { Scale = 1 }):Play()
end

function DevPanel:Close()
	if not self._open then
		return
	end
	self._open = false
	self._panel.Visible = false
end

function DevPanel:Toggle()
	if self._open then
		self:Close()
	else
		self:Open()
	end
end

function DevPanel:SetRebirths(count: number)
	self._rebirthsCurrent.Text = `Actuel : {count}`
end

function DevPanel:SetUltimateEnabled(enabled: boolean)
	self._ultimateToggle:set(enabled)
end

function DevPanel:SetEarlyRebirthEnabled(enabled: boolean)
	self._earlyToggle:set(enabled)
end

function DevPanel:SetUnlimitedMoneyEnabled(enabled: boolean)
	self._unlimitedToggle:set(enabled)
end

-- Shows the speed the SERVER actually applied, which is not necessarily the
-- one typed: an out-of-range request comes back clamped, and reading the
-- clamped value here is what tells the tester it was clamped rather than
-- ignored.
function DevPanel:SetWalkSpeed(speed: number)
	self._speedCurrent.Text = `Vitesse : {speed}`
end

return DevPanel
