--!strict
-- The gains that float up on screen: "+150" with its icon, like any good
-- tycoon. It's the immediate feedback that makes a payout legible -- without
-- it, revenue trickling in on its own goes unnoticed.
--
-- This module listens to nothing and talks to nobody: HudController pushes
-- gains into it. It only knows its own presentation.

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
local Theme = require("./Theme")

local COLORS = Theme.Colors
local SPACE = Theme.Space

local WIDTH = 204
local HEIGHT = 36
local ICON = 32
local ROW = 40 -- vertical gap between two simultaneous gains
-- Rise over the gain's lifetime. MUST stay under ROW: past that, a rising
-- gain would eventually bite into the row above it.
local RISE = 28
local LIFETIME = 1.25
local MAX_ROWS = 6 -- beyond this, drop the gain rather than stack it

-- The server only ever sends a keyword: all rendering is decided here, no
-- text ever crosses the network. Adding a gain kind is one line.
local KINDS: { [string]: { Icon: string, Color: Color3, Suffix: string } } = {
	Credits = { Icon = Icons.Cash["CashIcon"], Color = Theme.Function.Money, Suffix = "" },
	Power = { Icon = Icons.Stats["Energy"], Color = COLORS.Accent, Suffix = " én." },
	Storage = { Icon = Icons.Stats["Power"], Color = COLORS.Credit, Suffix = " stock" },
	Cooling = { Icon = Icons.Currency["Fire"], Color = COLORS.Heat, Suffix = " froid" },
}

local GainFeed = {}
GainFeed.__index = GainFeed

export type GainFeed = typeof(setmetatable({} :: any, GainFeed))

function GainFeed.new(parent: ScreenGui): GainFeed
	local self = setmetatable({}, GainFeed)

	-- Bottom-left: the HUD column is already busy up top, and the eye
	-- catches motion in an otherwise empty corner.
	self._root = Theme.new("Frame", {
		Name = "GainFeed",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, SPACE.xl, 1, -(SPACE.xl + 28)),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- Occupied rows. A gain keeps its row until it dies, then frees it: two
	-- gains can never overlap, whatever the pace. The old system cycled a
	-- counter modulo N, which ended up reassigning a still-occupied row.
	self._rows = {} :: { [number]: boolean }

	return self
end

-- First free row, counting from the bottom.
function GainFeed:_claimRow(): number?
	for row = 0, MAX_ROWS - 1 do
		if not self._rows[row] then
			self._rows[row] = true
			return row
		end
	end
	return nil
end

function GainFeed:Push(kind: string, amount: number)
	local style = KINDS[kind]
	if not style or amount <= 0 then
		return
	end

	local row = self:_claimRow()
	if not row then
		return
	end
	local offset = row * -ROW

	-- No background, no frame: just the icon and the number. The BLACK text
	-- outline stays, though -- it's the only thing keeping a light number
	-- from getting lost against a light hull.
	local pill = Theme.new("Frame", {
		Name = "Gain",
		Position = UDim2.fromOffset(0, offset),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundTransparency = 1,
		Parent = self._root,
	}, {
		Theme.new("ImageLabel", {
			Name = "Icon",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(ICON, ICON),
			BackgroundTransparency = 1,
			Image = style.Icon,
			ScaleType = Enum.ScaleType.Fit,
		}),
		-- title (21), not body (16): the next notch up in the Theme scale,
		-- not an invented in-between size.
		Theme.title({
			Name = "Amount",
			Position = UDim2.fromOffset(ICON + 8, 0),
			Size = UDim2.new(1, -(ICON + 8), 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = style.Color,
			Text = `+{amount}{style.Suffix}`,
		}),
	})

	local info = TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(pill, info, {
		Position = UDim2.fromOffset(0, offset - RISE),
	}):Play()

	-- Text, icon and text outline fade out together.
	for _, descendant in pill:GetDescendants() do
		if descendant:IsA("TextLabel") then
			TweenService:Create(descendant, info, { TextTransparency = 1 }):Play()
		elseif descendant:IsA("ImageLabel") then
			TweenService:Create(descendant, info, { ImageTransparency = 1 }):Play()
		elseif descendant:IsA("UIStroke") then
			TweenService:Create(descendant, info, { Transparency = 1 }):Play()
		end
	end

	task.delay(LIFETIME + 0.1, function()
		self._rows[row] = nil
		pill:Destroy()
	end)
end

return GainFeed
