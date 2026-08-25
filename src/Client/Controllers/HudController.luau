--!strict
-- HUD: the credits capsule, income, and the three gauges that are the
-- game's whole flavor (power, heat, orbit).
--
-- Everything is INDEPENDENT capsules, clear against the black sky. No big
-- panel grouping them together: each measurement reads on its own, and the
-- whole thing breathes.
--
-- The gauges only appear on the station: in the lobby there is nothing for
-- them to show.

local Players = game:GetService("Players")
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

local State = require("../State")
local GainFeed = require("../UI/GainFeed")
local Theme = require("../UI/Theme")
local Icons = require(fromShared("Icons"))

local COLORS = Theme.Colors
local SPACE = Theme.Space

local WIDTH = 280
local PURSE_HEIGHT = 54
local PILL_HEIGHT = 46

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

	local purse = Theme.capsule({
		Name = "Purse",
		Position = UDim2.fromOffset(SPACE.xl, SPACE.xl),
		Width = WIDTH,
		Height = PURSE_HEIGHT,
		Color = Theme.Function.Money,
		Image = Icons.Cash["CashIcon"],
		Value = "0",
		Parent = gui,
	})

	local purseScale = Theme.new("UIScale", { Scale = 1, Parent = purse.Root })

	local income = Theme.body({
		Name = "Income",
		Position = UDim2.fromOffset(SPACE.xl + SPACE.md, SPACE.xl + PURSE_HEIGHT + 2),
		Size = UDim2.fromOffset(WIDTH, 22),
		TextSize = Theme.TextSize.small,
		TextColor3 = COLORS.Valid,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Revenu : 0 cr/s",
		Visible = false,
		Parent = gui,
	})

	----------------------------------------------------------------------
	-- The three gauges, each in its own capsule

	local top = SPACE.xl + PURSE_HEIGHT + 2 + 22 + SPACE.sm
	local function pill(index: number, caption: string, color: Color3, image: string)
		return Theme.gaugePill({
			Name = caption,
			Position = UDim2.fromOffset(SPACE.xl, top + (index - 1) * (PILL_HEIGHT + SPACE.sm)),
			Width = WIDTH,
			Height = PILL_HEIGHT,
			Caption = caption,
			Color = color,
			Image = image,
			Visible = false,
			Parent = gui,
		})
	end

	local rows = {
		power = pill(1, "ÉNERGIE", COLORS.Accent, Icons.Stats["Energy"]),
		heat = pill(2, "CHALEUR", COLORS.Heat, Icons.Currency["Fire"]),
		sun = pill(3, "SOLEIL", COLORS.Credit, Icons.Stars["Star"]),
	}

	local modules = Theme.caption({
		Name = "Modules",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, SPACE.xl + SPACE.xs, 1, -SPACE.xl),
		Size = UDim2.fromOffset(220, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "0 module",
		Visible = false,
		Parent = gui,
	})

	----------------------------------------------------------------------

	local function setOnStation(onStation: boolean)
		income.Visible = onStation
		modules.Visible = onStation
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
		modules.Text = if count <= 1 then `{count} module` else `{count} modules`
	end

	State.Changed:Connect(function(key: string, value: any)
		if key == "Location" then
			setOnStation(value == "Station")
			if value == "Station" then
				refreshModuleCount()
			end
		elseif key == "Credits" then
			local amount = value :: number
			purse.Value.Text = tostring(amount)
			-- The balance flickers on every change: makes a spend register.
			purseScale.Scale = 1.1
			TweenService:Create(purseScale, Theme.Tween.Pop, { Scale = 1 }):Play()
		elseif key == "Income" then
			income.Text = `Revenu : {string.format("%.1f", value :: number)} cr/s`
		elseif key == "PowerProduction" or key == "PowerConsumption" then
			local production = State.get("PowerProduction") or 0
			local consumption = State.get("PowerConsumption") or 0
			local demand = math.max(consumption, 1)
			local ratio = production / demand
			rows.power.Gauge:SetRatio(ratio)
			rows.power:SetColor(if ratio >= 1 then COLORS.Accent else COLORS.Invalid)
			rows.power.Value.Text = `{math.floor(production)}/{math.floor(consumption)}`
		elseif key == "HeatLoad" or key == "HeatCapacity" then
			local load = State.get("HeatLoad") or 0
			local capacity = State.get("HeatCapacity") or 0
			local heatRatio = load / math.max(capacity, 1)
			rows.heat.Gauge:SetRatio(heatRatio)
			rows.heat:SetColor(if heatRatio > 1 then COLORS.Invalid else COLORS.Heat)
			rows.heat.Value.Text = `{math.floor(load)}/{math.floor(capacity)}`
		elseif key == "Sunlight" then
			local sunlight = value :: number
			rows.sun.Gauge:SetRatio(sunlight)
			rows.sun.Value.Text = if sunlight < 0.05 then "ÉCLIPSE" else "SOLEIL"
		end
	end)

	State.Notified:Connect(function(kind: string, payload: any)
		if kind == "Power" or kind == "Storage" or kind == "Cooling" then
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
