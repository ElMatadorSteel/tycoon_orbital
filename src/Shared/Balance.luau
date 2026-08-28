--!strict
-- Global balance numbers. The only source of constants -- read by Domain,
-- Application and the client alike. Ported as-is from the legacy
-- ReplicatedStorage.Shared.Config; values unchanged.
--
-- Lives directly under Shared, not in a Config/ folder: the legacy place
-- already has a ModuleScript at ReplicatedStorage.Shared.Config, so a
-- Config/Balance.luau here would have synced to a FOLDER at that exact
-- path once Rojo connects -- a genuine name collision, not just an unknown
-- sibling. See CLAUDE.md's Stage 5 notes for the full story.

local Balance = {
	GameName = "Orbital",

	Economy = {
		StartingCredits = 800,
		RefundRatio = 0.5, -- fraction refunded when a module is demolished
	},

	-- Module levels. A level only ever increases what a module PRODUCES,
	-- never what it consumes -- upgrading must always be a net gain, or the
	-- player can no longer tell whether it was a good idea.
	Upgrade = {
		MaxLevel = 10,
		GainPerLevel = 0.35, -- +35% of base output per level
		CostFactor = 1.8, -- cost = base cost * CostFactor^level
		-- Floor: every other upgradable module's base cost already clears
		-- this well before its own first level (see ModuleCatalog.luau's
		-- module_catalog spec) -- in practice this only ever binds for
		-- modules with no cost of their own, i.e. never, now that the core
		-- has its own dedicated rate below.
		MinCost = 250,
		-- The core's own flat upgrade rate -- its base cost is 0 (it ships
		-- with the station), so it needs a dedicated rate rather than
		-- MinCost's shared floor (raising MinCost instead would also raise
		-- OTHER modules' cheap early levels, which sit close to it). Set at
		-- 1.5x the old flat 250 rate: the core also gates every other
		-- module's own max level now (see Placement.coreLevel/UpgradeModule),
		-- so its own pace-setting upgrade should cost a bit more.
		CoreUpgradeCost = 375,
	},

	-- Dev-mode-only numbers -- never read outside `development` (see
	-- Composition/Container.luau's flag), no bearing on real balance.
	Dev = {
		UnlimitedMoneyCeiling = 999999999, -- what DevSetUnlimitedMoney tops credits up to
	},

	Save = {
		-- Changing this resets EVERYONE's save. Only do it when a format
		-- change makes old saves unreadable.
		StoreName = "OrbitalPlayer_v1",
		AutosaveInterval = 120, -- seconds between two automatic saves
		RetryCount = 3,
		RetryDelay = 2, -- seconds, doubles on each retry
		MaxModules = 800, -- safety net: the grid holds 625 at most
	},

	Grid = {
		CellSize = 8,
		Radius = 12, -- half-width of the grid, in cells
	},

	Plots = {
		Count = 6,
		Distance = 900, -- studs between the lobby and the stations
		Spread = 26, -- degrees between two stations
		Altitude = 0,
	},

	-- The station orbits the planet: it regularly passes through its
	-- shadow, and solar panels stop.
	Lobby = {
		-- Set back from the row of stations, so they're visible in the
		-- distance. Plain {X, Y, Z} rather than a real Vector3: this module
		-- must stay loadable under Lune (no Roblox datatypes exist there),
		-- and Domain must stay engine-agnostic anyway -- convert to
		-- Vector3.new only at the Adapter that actually builds the scene.
		Center = { X = 1000, Y = 60, Z = -700 },
		Radius = 46,
	},

	Orbit = {
		Period = 180, -- seconds for a full revolution
		EclipseFraction = 0.3, -- fraction of the orbit spent in shadow
	},

	Heat = {
		BaseCapacity = 40, -- heat tolerated with no radiator at all
		CapacityPerRadiator = 60,
		OverheatPenalty = 0.55, -- minimum efficiency at full overheat
	},

	Simulation = {
		TickRate = 0.5, -- seconds between two simulation steps
	},

	-- The prestige mechanic: reset the station and credits, once the core
	-- reaches the threshold below, for a small permanent production boost.
	-- `Enabled` is the modular per-zone switch this was built for -- only
	-- one zone exists today, so it's one flag; a later multi-zone build
	-- would key this per zone instead of adding a second flag elsewhere.
	Rebirth = {
		Enabled = true, -- temporarily on, on this one zone, to test it live
		NormalThreshold = 10, -- core level required for a free rebirth
		EarlyThreshold = 5, -- core level required with the paid EarlyRebirth pass
		BonusPerRebirth = 0.25, -- +25% production, additive, per rebirth banked
		UltimateMultiplier = 1.5, -- flat multiplier while the paid Ultimate pass is owned
	},

	-- Optional side content: a purchasable Railgun that shoots passing
	-- asteroids near a player's own station for bonus credits. Entirely
	-- separate from the main build/upgrade/rebirth loop -- nothing here
	-- feeds back into it besides the credits themselves.
	Mining = {
		Railgun = {
			Cost = 500, -- one-time purchase price
			Cooldown = 1.5, -- seconds between two shots
			MaxActive = 3, -- concurrent asteroids per player
			-- Checked once per Mining.TickRate, only while under MaxActive:
			-- ~1 spawn every ~4s of the cap not being full.
			SpawnChancePerTick = 0.12,
			AsteroidLifetime = 8, -- seconds an asteroid is shootable before it flies past
			TickRate = 1, -- separate from Simulation.TickRate -- independently tunable
		},
		-- Common is worth roughly one production tick's revenue; Legendary is
		-- worth roughly 2-4x the core's own upgrade cost (375) -- a real
		-- jackpot, appropriately rare at weight 3/100.
		Tiers = {
			{
				id = "Common",
				name = "Astéroïde commun",
				weight = 60,
				minReward = 15,
				maxReward = 30,
			},
			{
				id = "Rare",
				name = "Astéroïde rare",
				weight = 25,
				minReward = 60,
				maxReward = 110,
			},
			{
				id = "Epic",
				name = "Astéroïde épique",
				weight = 12,
				minReward = 220,
				maxReward = 380,
			},
			{
				id = "Legendary",
				name = "Astéroïde légendaire",
				weight = 3,
				minReward = 900,
				maxReward = 1500,
			},
		},
	},
}

return Balance
