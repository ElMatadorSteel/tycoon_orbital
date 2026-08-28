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

local Balance = require(fromShared("Balance"))
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

	-- Two INDEPENDENT lines, deliberately never merged into one: the free
	-- rebirth count/bonus, Ultimate, and the EarlyRebirth pass are three
	-- unrelated things (a rebirth's own +25% has nothing to do with owning
	-- Ultimate, and EarlyRebirth only ever changes WHEN you can rebirth,
	-- never by how much) -- showing them as one blended "(x1.88) · Ultimate"
	-- line reads as if Ultimate caused that number. Each line is only shown
	-- once it means something, so a player who hasn't touched any of this
	-- sees neither.
	local rebirthCount = Theme.caption({
		Name = "RebirthCount",
		Position = UDim2.fromOffset(SPACE.xl + SPACE.md, SPACE.xl + PURSE_HEIGHT + 2 + 22),
		Size = UDim2.fromOffset(WIDTH, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Function.Rebirth,
		Text = "",
		Visible = false,
		Parent = gui,
	})

	local rebirthPasses = Theme.caption({
		Name = "RebirthPasses",
		Position = UDim2.fromOffset(SPACE.xl + SPACE.md, SPACE.xl + PURSE_HEIGHT + 2 + 22 + 18),
		Size = UDim2.fromOffset(WIDTH, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Function.Rebirth,
		Text = "",
		Visible = false,
		Parent = gui,
	})

	----------------------------------------------------------------------
	-- The three gauges, each in its own capsule

	local top = SPACE.xl + PURSE_HEIGHT + 2 + 22 + 18 + 18 + SPACE.sm
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

	local function refreshRebirthLine()
		local onStation = State.get("Location") == "Station"
		local rebirths = (State.get("Rebirths") :: number?) or 0

		if not onStation or rebirths <= 0 then
			rebirthCount.Visible = false
		else
			-- The free rebirth bonus's actual CURRENT result (25% per
			-- rebirth banked so far), not the flat per-rebirth rate --
			-- never mixed with Ultimate's own multiplier below (a separate,
			-- unrelated purchase).
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

		-- Two independent, unrelated purchases -- Ultimate boosts production
		-- regardless of rebirths; EarlyRebirth only ever changes WHEN a
		-- rebirth is allowed, never by how much. Listed separately, never
		-- combined into one number.
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
		for _, row in rows do
			row.Root.Visible = onStation
		end
		refreshRebirthLine()
	end
	setOnStation(State.get("Location") == "Station")

	-- The "+150" pills that rise bottom-left. The server sends a gain kind
	-- and an amount, the feed knows what to do with it.
	local feed = GainFeed.new(gui)

	-- The station's module count replicates as ordinary Instances (see
	-- CLAUDE.md's Stage 5 notes), so it's counted straight off the player's
	-- own station folder rather than through a snapshot field. Counting only
	-- Models excludes the station's StationSpawn, which StationSceneBuilder
	-- parents into the same folder as the modules.
	local ownFolder: Folder? = nil

	local function refreshModuleCount()
		local count = 0
		if ownFolder then
			for _, child in ownFolder:GetChildren() do
				if child:IsA("Model") then
					count += 1
				end
			end
		end
		modules.Text = if count <= 1 then `{count} module` else `{count} modules`
	end

	-- Bound once, then kept correct by folder.ChildAdded/Removed below --
	-- not by re-scanning on every Location change. A snapshot taken right
	-- when Location flips to "Station" can race a big batch of module
	-- Instances still replicating in (RestoreStation replaying a large
	-- saved station, in particular), and a later placement while already on
	-- the station would never have been counted at all: nothing was
	-- listening to this folder's OWN children before.
	local function bindOwnStation()
		if ownFolder then
			return
		end
		local stations = workspace:FindFirstChild("Stations")
		local folder = stations and stations:FindFirstChild(`Station_{Players.LocalPlayer.UserId}`)
		if not folder then
			return
		end
		ownFolder = folder
		refreshModuleCount()
		folder.ChildAdded:Connect(refreshModuleCount)
		folder.ChildRemoved:Connect(refreshModuleCount)
	end

	State.Changed:Connect(function(key: string, value: any)
		if key == "Location" then
			setOnStation(value == "Station")
			if value == "Station" then
				bindOwnStation()
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
		elseif
			key == "Rebirths"
			or key == "GlobalBoost"
			or key == "HasUltimate"
			or key == "HasEarlyRebirth"
		then
			refreshRebirthLine()
		end
	end)

	State.Notified:Connect(function(kind: string, payload: any)
		-- "Credits" is the Railgun's own gain popup (Application/UseCases/
		-- FireRailgun) -- GainFeed.KINDS already carries a Credits entry
		-- (cash icon, money color), unused until now.
		if kind == "Power" or kind == "Storage" or kind == "Cooling" or kind == "Credits" then
			feed:Push(kind, payload)
		end
	end)

	-- Covers the case where Location already reads "Station" (e.g. this
	-- controller starting after the attribute already replicated) but the
	-- own folder doesn't exist client-side yet: bind as soon as it appears.
	local stations = workspace:WaitForChild("Stations")
	stations.ChildAdded:Connect(function()
		if State.get("Location") == "Station" then
			bindOwnStation()
		end
	end)

	if State.get("Location") == "Station" then
		bindOwnStation()
	end
end

return HudController
