--!strict
-- One simulation step for one player -- ported from
-- ProductionService:_step. Reads the station and the session's carried-over
-- charge/pending credit, runs the pure Domain step, writes the results
-- back to session state, credits whatever whole revenue came out of it, and
-- publishes the stats -- legacy's StationStats remote, now state instead of
-- an event.

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Server and src/Shared to different service roots with no common
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
	return "../../../Shared/" .. path
end

local Orbit = require(fromShared("Domain/Production/Orbit"))
local Simulation = require(fromShared("Domain/Production/Simulation"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local Credits = require(fromShared("Domain/Economy/Credits"))
local Snapshot = require("../Snapshot")

type OrbitRules = Orbit.Rules
type HeatRules = Simulation.HeatRules
type ResourceValues = Simulation.ResourceValues
type UpgradeRules = ModuleCatalog.UpgradeRules

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	sessionRegistry: any, -- Application.SessionRegistry
	statsPublisher: any, -- Ports.StatsPublisher
	clock: any, -- Ports.Clock (monotonic() is what's used here)
	orbitRules: OrbitRules,
	heatRules: HeatRules,
	resourceValues: ResourceValues,
	upgradeRules: UpgradeRules,
}

export type TickStats = {
	sunlight: number,
	efficiency: number,
	power: Simulation.PowerStats,
	heat: Simulation.HeatStats,
	income: number,
}

local RunProductionTick = {}
RunProductionTick.__index = RunProductionTick

function RunProductionTick:run(userId: number, deltaTime: number): TickStats
	local station = self.stationRepository:load(userId)
	local state = self.sessionRegistry:production(userId)

	local sunlight = Orbit.sunlightAt(self.clock:monotonic(), self.orbitRules)

	local result = Simulation.step({
		station = station,
		sunlight = sunlight,
		deltaTime = deltaTime,
		charge = state.charge,
		pendingCredit = state.pendingCredit,
		heatRules = self.heatRules,
		resourceValues = self.resourceValues,
		upgradeRules = self.upgradeRules,
	})

	state.charge = result.charge
	state.pendingCredit = result.pendingCredit

	if result.wholeRevenue > 0 then
		local profile = self.profileRepository:load(userId)
		profile.credits = Credits.add(profile.credits, result.wholeRevenue)
		-- Deliberately NOT profileRepository:save() here. A busy factory
		-- earns whole revenue on nearly every tick (every ~0.5s), and a real
		-- DataStore write is rate-limited -- calling it this often floods the
		-- write queue for this key, and every OTHER action that also needs
		-- to save (SpendCredits, PlaceModule, UpgradeModule, ...) then queues
		-- behind it, surfacing as multi-second delays on things a player
		-- just clicked. The mutation above is enough on its own: every
		-- ProfileRepository caches by reference (see
		-- DataStoreProfileRepository's header), so this change is visible to
		-- every other use case's next load() immediately, with or without an
		-- explicit save. Durability past that is Bootstrap's periodic
		-- autosave loop and the PlayerRemoving save, same as every other
		-- mutation already covers for the moment a session actually ends.
		self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	end

	local stats: TickStats = {
		sunlight = sunlight,
		efficiency = result.efficiency,
		power = result.power,
		heat = result.heat,
		income = result.income,
	}
	self.statsPublisher:publish(userId, Snapshot.production(stats))

	return stats
end

return RunProductionTick
