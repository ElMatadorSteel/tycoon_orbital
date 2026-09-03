--!strict
-- HUD: the credits read-out, income, and the three gauges that are the
-- game's whole flavor (power, heat, orbit).
--
-- Everything is INDEPENDENT read-outs, clear against the sky. No big panel
-- grouping them together: each measurement reads on its own, and the whole
-- thing breathes.
--
-- The read-outs carry no surface either -- no capsule, no border, no motif.
-- A HUD is not a stack of windows: an icon, a caption, a figure and a hairline
-- bar are enough to identify a measurement. See `Theme.gaugeRow`.
--
-- The whole cluster sits in the BOTTOM-LEFT corner. The top of the screen is
-- Roblox's -- topbar, chat, menu -- and a read-out placed there is read second.
--
-- The gauges only appear on the station: in the lobby there is nothing for
-- them to show.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local State = require("../State")
local GainFeed = require("../UI/GainFeed")
local Theme = require("../UI/Theme")
local Icons = require(fromShared("Icons"))

local COLORS = Theme.Colors
local SPACE = Theme.Space

local WIDTH = 280
local PURSE_HEIGHT = 44
-- A row IS its bar now (see Theme.gaugeRow): nothing is stacked above it, so
-- the whole read-out fits in the height the bar alone used to need a caption
-- line on top of.
local ROW_HEIGHT = 32
-- Wider than it was, because the icons now stand TALLER than the row and break
-- its outline top and bottom. At the old 8px gap the overhang of one row met
-- the overhang of the next exactly.
local ROW_GAP = SPACE.md

-- How far the bars and the head lines run. Short on purpose: see the note in
-- `Theme.gaugeRow`. The row frame stays wider so a long figure has somewhere
-- to go without pushing the layout around.
-- Wide enough for the longest pair the bar has to hold at once: "EXPOSITION"
-- on the left and "ÉCLIPSE" on the right. At 196 they came within a few pixels
-- of touching in the middle, which reads as one run of text rather than two
-- ends of a capsule.
local BAR_WIDTH = 224

-- One icon size for every read-out, so the captions, the figures, the side
-- lines and the bars all start on the same vertical line. With the capsules
-- gone that column is the only thing left holding the cluster together.
-- Bigger than the 32px row it labels: the icon is meant to stand proud of the
-- bar, not sit inside it. See the overlap note in Theme.gaugeRow.
local ICON_BOX = 40
local CONTENT_X = ICON_BOX + SPACE.sm

-- The cluster hangs off the BOTTOM-LEFT corner rather than the top.
--
-- The top of the screen belongs to Roblox: the topbar lives there, and a
-- read-out placed under it competes with chat and the menu button for the same
-- glance. The bottom-left corner is empty, is where the eye rests between
-- actions, and is where the genre has kept its resource read-outs for twenty
-- years. Every offset below is measured UP from that corner.
local BOTTOM = SPACE.xl
local INCOME_H = 20
local SIDE_H = 18

-- Read the stack from the floor up: rate, balance, the two rebirth lines, the
-- three gauges, the module count.
local INCOME_Y = BOTTOM
local PURSE_Y = INCOME_Y + INCOME_H + 2
local REBIRTH_COUNT_Y = PURSE_Y + PURSE_HEIGHT + 2
local REBIRTH_PASSES_Y = REBIRTH_COUNT_Y + SIDE_H

local HudController = {}

function HudController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	-- The Roblox topbar (menu, chat, friends) occupies the top of the
	-- screen and draws OVER every interface: we can't get in front of it,
	-- only give it room. CoreUISafeInsets removes that band from the play
	-- area, so y = 0 starts right below it. Its height varies per device
	-- (notches, mobile): never hardcode it.
	--
	-- Trap: TopbarSafeInsets does the OPPOSITE of what its name suggests.
	-- It constrains the interface TO the topbar band -- meant for placing
	-- your own icons next to Roblox's, not for avoiding them.
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- See BuildController: the Theme's relief (shadow + face, inner frame)
	-- assumes stacking relative to the parent. Sibling everywhere, no
	-- exceptions.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	----------------------------------------------------------------------
	-- Purse

	-- Credits carry no ceiling, so the purse is the one read-out with no bar:
	-- same glyph and same caption as the gauges below it, the figure simply
	-- standing where their fill would be.
	local purse = Theme.gaugeRow({
		Name = "Purse",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, SPACE.xl, 1, -PURSE_Y),
		Width = WIDTH,
		Height = PURSE_HEIGHT,
		IconBox = ICON_BOX,
		BarWidth = BAR_WIDTH,
		ShowBar = false,
		Color = Theme.Function.Money,
		Image = Icons.Cash["CashIcon"],
		Caption = Theme.Words.Gauge.Credits,
		Value = "0",
		Parent = gui,
	})

	local purseScale = Theme.new("UIScale", { Scale = 1, Parent = purse.Root })

	local income = Theme.body({
		Name = "Income",
		AnchorPoint = Vector2.new(0, 1),
		-- Under the balance, not over it: the rate is what the balance is doing,
		-- so it reads as a footnote to the figure rather than a separate stat.
		Position = UDim2.new(0, SPACE.xl + CONTENT_X, 1, -INCOME_Y),
		Size = UDim2.fromOffset(WIDTH, INCOME_H),
		TextSize = Theme.TextSize.small,
		TextColor3 = COLORS.Valid,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = Theme.Words.Income(0),
		Visible = false,
		Parent = gui,
	})

	-- Two INDEPENDENT lines, deliberately never merged into one: the free
	-- rebirth count/bonus, Ultimate, and the EarlyRebirth pass are three
	-- unrelated things (a rebirth's own bonus has nothing to do with owning
	-- Ultimate, and EarlyRebirth only ever changes WHEN you can rebirth,
	-- never by how much) -- showing them as one blended line would read as
	-- if Ultimate caused that number. Each line only shows once it means
	-- something, so a player who hasn't touched any of this sees neither.
	local rebirthCount = Theme.caption({
		Name = "RebirthCount",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, SPACE.xl + CONTENT_X, 1, -REBIRTH_COUNT_Y),
		Size = UDim2.fromOffset(WIDTH, SIDE_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Function.Rebirth,
		Text = "",
		Visible = false,
		Parent = gui,
	})

	local rebirthPasses = Theme.caption({
		Name = "RebirthPasses",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, SPACE.xl + CONTENT_X, 1, -REBIRTH_PASSES_Y),
		Size = UDim2.fromOffset(WIDTH, SIDE_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Function.Rebirth,
		Text = "",
		Visible = false,
		Parent = gui,
	})

	----------------------------------------------------------------------
	-- The orbital countdown, top centre
	--
	-- The server publishes a DURATION every tick, and this counts it down
	-- locally in between. Two reasons that beats displaying the published
	-- number as-is: a value that only moves twice a second reads as a stutter,
	-- and a countdown is the one figure a player watches closely enough to
	-- notice. The server's next tick corrects any drift, so the local count
	-- never has to be right for long.

	local eclipse = Theme.banner({
		Name = "Eclipse",
		-- NEGATIVE, on purpose. The ScreenGui runs on CoreUISafeInsets, so y = 0
		-- is the first row BELOW Roblox's topbar -- and that inset measured 58px
		-- here, which is why "4" still left the banner floating a long way down
		-- the sky. Going higher means reaching up into the topbar band.
		--
		-- Safe to do for this one element: Roblox's own controls live at the two
		-- ENDS of that band (menu and chat left, others right) and the centre it
		-- is anchored to stays empty.
		Position = UDim2.new(0.5, 0, 0, -SPACE.xxl),
		Color = COLORS.Credit,
		Image = Icons.Stars["Star"],
		Visible = false,
		Parent = gui,
	})

	-- Seconds remaining, carried between server ticks. `nil` until the first
	-- publish: the banner shows nothing rather than a zero it invented.
	local eclipseRemaining: number? = nil
	local inEclipse = false

	-- Which of the two looks is currently applied. `paintEclipse` runs every
	-- frame, and repainting five properties sixty times a second to the values
	-- they already hold is work nobody asked for.
	local paintedEclipse: boolean? = nil

	local function paintEclipse()
		if not eclipseRemaining then
			return
		end
		-- Ceiling, not floor: a countdown that shows 0 for a whole second before
		-- anything happens reads as a frozen interface.
		local seconds = math.max(0, math.ceil(eclipseRemaining))

		if inEclipse then
			eclipse.Text.Text = Theme.Words.EclipseActive(seconds)
		else
			eclipse.Text.Text = Theme.Words.EclipseIncoming(seconds)
		end

		if paintedEclipse ~= inEclipse then
			paintedEclipse = inEclipse
			if inEclipse then
				eclipse:SetLook(COLORS.Heat, Icons.Currency["Fire"])
			else
				eclipse:SetLook(COLORS.Credit, Icons.Stars["Star"])
			end
		end
	end

	RunService.Heartbeat:Connect(function(delta: number)
		if not eclipse.Root.Visible or not eclipseRemaining then
			return
		end
		eclipseRemaining = math.max(0, eclipseRemaining - delta)
		paintEclipse()
	end)

	----------------------------------------------------------------------
	-- The three gauges, each its own frameless row

	-- Stacked upwards off the rebirth lines, index 1 highest, so the column
	-- still reads power / heat / sun top to bottom the way it always has.
	local gaugeBase = REBIRTH_PASSES_Y + SIDE_H + SPACE.sm
	local function readout(index: number, caption: string, color: Color3, image: string)
		return Theme.gaugeRow({
			Name = caption,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(
				0,
				SPACE.xl,
				1,
				-(gaugeBase + (3 - index) * (ROW_HEIGHT + ROW_GAP))
			),
			Width = WIDTH,
			Height = ROW_HEIGHT,
			IconBox = ICON_BOX,
			BarWidth = BAR_WIDTH,
			Caption = caption,
			Color = color,
			Image = image,
			Visible = false,
			Parent = gui,
		})
	end

	local rows = {
		power = readout(1, Theme.Words.Gauge.Power, COLORS.Accent, Icons.Stats["Energy"]),
		heat = readout(2, Theme.Words.Gauge.Heat, COLORS.Heat, Icons.Currency["Fire"]),
		sun = readout(3, Theme.Words.Gauge.Sun, COLORS.Credit, Icons.Stars["Star"]),
	}

	local modules = Theme.caption({
		Name = "Modules",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(
			0,
			SPACE.xl + CONTENT_X,
			1,
			-(gaugeBase + 3 * (ROW_HEIGHT + ROW_GAP) + SPACE.xs)
		),
		Size = UDim2.fromOffset(220, SIDE_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = Theme.Words.ModuleCount(0),
		Visible = false,
		Parent = gui,
	})

	----------------------------------------------------------------------

	local function refreshRebirthLine()
		local onStation = State.get("Location") == "Station"
		local rebirths = (State.get("Rebirths") :: number?) or 0

		if not onStation or rebirths <= 0 then
			rebirthCount.Visible = false
		else
			-- The free rebirth bonus's actual CURRENT result (this many rebirths
			-- banked so far), not the flat per-rebirth rate -- never mixed with
			-- Ultimate's own multiplier below (a separate, unrelated purchase).
			local percent = math.floor(Balance.Rebirth.BonusPerRebirth * 100 * rebirths)
			rebirthCount.Text = `Renaissances : {rebirths} (+{percent}%)`
			rebirthCount.Visible = true
		end

		if not onStation then
			rebirthPasses.Visible = false
			return
		end

		local hasUltimate = State.get("HasUltimate") == true
		local hasEarlyPass = State.get("HasEarlyRebirth") == true
		if not hasUltimate and not hasEarlyPass then
			rebirthPasses.Visible = false
			return
		end

		local parts = {}
		if hasUltimate then
			table.insert(parts, `Ultimate actif (x{Balance.Rebirth.UltimateMultiplier})`)
		end
		if hasEarlyPass then
			table.insert(
				parts,
				`Renaissance dès niv. {Balance.Rebirth.EarlyThreshold} débloquée`
			)
		end
		rebirthPasses.Text = table.concat(parts, "   ·   ")
		rebirthPasses.Visible = true
	end

	local function setOnStation(onStation: boolean)
		income.Visible = onStation
		modules.Visible = onStation
		refreshRebirthLine()
		-- Hidden in the lobby as a choice, not a limitation: the loop ticks for
		-- lobby players too, so the countdown would be live there. It is grouped
		-- with the station read-outs because that is where the eclipse costs the
		-- player something. Showing it in the lobby is a one-line change.
		eclipse.Root.Visible = onStation
		for _, row in rows do
			row.Root.Visible = onStation
		end
	end
	setOnStation(State.get("Location") == "Station")

	-- The "+150" pills that rise bottom-left. The server sends a gain kind
	-- and an amount, the feed knows what to do with it.
	local feed = GainFeed.new(gui)

	-- The station's module count replicates as ordinary Instances (see
	-- CLAUDE.md's Stage 5 notes), so it's counted straight off
	-- workspace.Stations rather than through a snapshot field. Counting only
	-- Models excludes the station's StationSpawn, which StationSceneBuilder
	-- parents into the same folder as the modules.
	local function refreshModuleCount()
		local player = Players.LocalPlayer
		local stations = workspace:FindFirstChild("Stations")
		local folder = stations and stations:FindFirstChild(`Station_{player.UserId}`)
		local count = 0
		if folder then
			for _, child in folder:GetChildren() do
				if child:IsA("Model") then
					count += 1
				end
			end
		end
		modules.Text = Theme.Words.ModuleCount(count)
	end

	State.Changed:Connect(function(key: string, value: any)
		if key == "Location" then
			setOnStation(value == "Station")
			if value == "Station" then
				refreshModuleCount()
			end
		elseif key == "Credits" then
			local amount = value :: number
			purse.Value.Text = Theme.Words.Amount(amount)
			-- The balance flickers on every change: makes a spend register.
			purseScale.Scale = 1.1
			TweenService:Create(purseScale, Theme.Tween.Pop, { Scale = 1 }):Play()
		elseif key == "Income" then
			income.Text = Theme.Words.Income(value :: number)
		elseif key == "PowerProduction" or key == "PowerConsumption" then
			local production = State.get("PowerProduction") or 0
			local consumption = State.get("PowerConsumption") or 0
			local demand = math.max(consumption, 1)
			local ratio = production / demand
			rows.power.Gauge:SetRatio(ratio)
			rows.power:SetColor(if ratio >= 1 then COLORS.Accent else COLORS.Invalid)
			rows.power.Value.Text = Theme.Words.Ratio(production, consumption)
		elseif key == "HeatLoad" or key == "HeatCapacity" then
			local load = State.get("HeatLoad") or 0
			local capacity = State.get("HeatCapacity") or 0
			local heatRatio = load / math.max(capacity, 1)
			rows.heat.Gauge:SetRatio(heatRatio)
			rows.heat:SetColor(if heatRatio > 1 then COLORS.Invalid else COLORS.Heat)
			rows.heat.Value.Text = Theme.Words.Ratio(load, capacity)
		elseif key == "Sunlight" then
			local sunlight = value :: number
			rows.sun.Gauge:SetRatio(sunlight)
			rows.sun.Value.Text = if sunlight < 0.05
				then Theme.Words.SunDark
				else Theme.Words.SunLit
		elseif
			key == "Rebirths"
			or key == "GlobalBoost"
			or key == "HasUltimate"
			or key == "HasEarlyRebirth"
		then
			refreshRebirthLine()
		elseif key == "EclipseIn" or key == "InEclipse" then
			-- Resynchronise on the server's figure. The local countdown between
			-- ticks is a smoothing convenience, never the authority.
			eclipseRemaining = State.get("EclipseIn")
			inEclipse = State.get("InEclipse") == true
			paintEclipse()
		end
	end)

	State.Notified:Connect(function(kind: string, payload: any)
		-- "Credits" is the Railgun's own gain popup (FireRailgun) --
		-- GainFeed.KINDS already carries a Credits entry (cash icon, money
		-- color), unused until now.
		if kind == "Power" or kind == "Storage" or kind == "Cooling" or kind == "Credits" then
			feed:Push(kind, payload)
		end
	end)

	local stations = workspace:WaitForChild("Stations")
	stations.ChildAdded:Connect(function()
		if State.get("Location") == "Station" then
			refreshModuleCount()
		end
	end)
	stations.ChildRemoved:Connect(function()
		if State.get("Location") == "Station" then
			refreshModuleCount()
		end
	end)
end

return HudController
