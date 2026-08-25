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
		MaxLevel = 5,
		GainPerLevel = 0.35, -- +35% of base output per level
		CostFactor = 1.8, -- cost = base cost * CostFactor^level
		-- Floor: the core costs 0 in the catalogue, its upgrade would
		-- otherwise be free.
		MinCost = 250,
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
}

return Balance
