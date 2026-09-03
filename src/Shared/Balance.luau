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
		-- What DevSetWalkSpeed may command. Default is the Roblox stock
		-- WalkSpeed, so "reset" means exactly "as if nobody had touched it".
		-- Max is a tunnelling ceiling, not a taste call: past roughly this
		-- speed a character covers more ground between two frames than a thin
		-- wall is deep, and walks straight through it (ARCHITECTURE.md's
		-- "tunnelling is a physics problem"). Raise it knowingly.
		WalkSpeed = {
			Default = 16,
			Min = 8,
			Max = 200,
		},
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

	-- The research mine: a walkable extension of the player's own plot,
	-- opened once by stepping on a tycoon pad at the edge of the deck. Only
	-- the price and the mining pace live here. The dimensions of the path
	-- and of the pit are shape, not balance -- they stay local constants in
	-- Adapters/Roblox/ResearchMineBuilder, same as RIM_HEIGHT does in
	-- StationSceneBuilder and the layout jitter does in Domain/Plots/Layout.
	Research = {
		Mine = {
			-- Three times the Railgun, and a few production ticks past the
			-- first couple of upgrades: the pad should be visible from the
			-- first minute and affordable from the tenth, so it reads as the
			-- next goal rather than as scenery.
			Cost = 2500,
		},
		Shovel = {
			-- Well under the mine that contains it. Its pad stands INSIDE the
			-- zone you already paid 2500 to open, so it reads as the second
			-- half of one purchase rather than as a second gate of the same
			-- size -- and a player who walked all the way to the pit floor
			-- should not have to walk back out and grind again.
			Cost = 900,
		},
		Vein = {
			-- Slower than the Railgun's 1.5s: a vein is a fixture you return
			-- to again and again rather than a target that flies past, so the
			-- pace has to feel like digging, not like shooting.
			Cooldown = 4,
		},
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

	-- Presentation timings, read only by the client. Here rather than inline in
	-- the controller because no magic number lives outside the configuration
	-- (DEVELOPMENT.md) -- and because these are exactly the numbers someone will
	-- want to retune after watching the effect once.
	Vfx = {
		TeleportAura = {
			-- EmbarkStation publishes Location BEFORE calling the teleporter, so
			-- the attribute reaches the client a beat before the character has
			-- actually been moved. Without this pause the aura flashes once in
			-- the lobby before following the player to their station.
			ArrivalDelay = 0.2,
			-- How long the aura keeps emitting once the player has landed.
			Hold = 2.5,
			-- Lights dim over this long instead of cutting out, which reads as a
			-- despawn rather than as a bug.
			Fade = 1,
			-- Particles already in flight have to finish their life before the
			-- clone is destroyed, or they vanish mid-air. The longest emitter in
			-- effet_tp_vfx lives 3 seconds.
			Linger = 3,
			-- Studs below the HumanoidRootPart centre: an R15 root sits about
			-- three studs above the floor, and the disc belongs on the floor.
			Offset = 3,
		},

		-- The burst when a module gains a level. Short and loud: it has to be
		-- seen from wherever the player was standing when they pressed the
		-- button, and gone before it becomes scenery.
		Upgrade = {
			SparkCount = 34,
			SparkLifetime = 0.9,
			SparkSpeed = 22,
			SparkSize = 1.1,
			SparkSpread = 55, -- degrees the cone opens to
			-- Emitters are told to stop, then the holder is destroyed one
			-- lifetime later: destroying it immediately would cut the sparks
			-- already in flight out of the air.
			Linger = 1.2,
			-- Studs above the module's base that the burst starts from. Bursting
			-- at ground level buries half the sparks in the hull.
			Height = 2.5,

			-- Plain {R,G,B} rather than Color3: this module has to stay loadable
			-- under Lune, where Roblox datatypes do not exist -- same reason
			-- Lobby.Center is written this way.
			--
			-- Read by the server's ModuleGeometry for the max-level aura and by
			-- the client's EffectsController for the burst. One source, so the
			-- aura and the spark that announces it cannot drift apart.
			SparkColor = { R = 255, G = 196, B = 74 },
			-- Saturated rather than pale: Neon blooms toward white, and the
			-- first pass at (120,255,156) read as a white glow with no colour
			-- left in it at all.
			AuraColor = { R = 40, G = 220, B = 96 },

			-- Whether a module at (or one level below) its ceiling wears the
			-- green aura -- the ground ring, the halo over the roof, the corner
			-- beads and the point light that go with them.
			--
			-- Off. On a plot dense with topped-out modules the station read as a
			-- field of green rather than as machinery, and the aura was doing
			-- the level pips' job louder and less precisely. The geometry that
			-- draws it is untouched in ModuleGeometry: flip this back to true
			-- and it returns exactly as it was.
			MaxAura = false,
		},
	},
}

return Balance
