--!strict
-- One simulation tick -- ported from ProductionService:_step, minus firing
-- any remote and minus reading/writing the session's charge/pending-credit
-- state directly (that's Application/SessionRegistry's job; this function
-- takes them in and hands new values back, it owns no state itself).
--
-- Three stages, in this order, because each constrains the next:
--   1. POWER   panels produce nothing in shadow; batteries buffer the gap.
--              If they're empty, everything downstream slows down.
--   2. HEAT    modules heat up; radiators dissipate, but only in proportion
--              to the empty space around them.
--   3. FLOW    per connected network: ore -> alloy -> component, sold by
--              cargo bays. Computed per second, no stock: whatever isn't
--              transformed in the tick sells as-is, or is lost without a
--              cargo bay.

local Grid = require("../Grid/Grid")
local ModuleCatalog = require("../Station/ModuleCatalog")
local Network = require("../Station/Network")
local Placement = require("../Station/Placement")

type Station = Placement.Station
type ModulePlacement = Placement.ModulePlacement

export type HeatRules = {
	baseCapacity: number,
	capacityPerRadiator: number,
	overheatPenalty: number,
}

export type ResourceValues = { [string]: number } -- Ore/Alloy/Component -> credit value per unit

export type StepParams = {
	station: Station,
	sunlight: number,
	deltaTime: number,
	charge: number,
	pendingCredit: number,
	heatRules: HeatRules,
	resourceValues: ResourceValues,
}

export type PowerStats =
	{ production: number, consumption: number, charge: number, storage: number }
export type HeatStats = { load: number, capacity: number }

export type StepResult = {
	charge: number,
	pendingCredit: number,
	wholeRevenue: number,
	efficiency: number,
	power: PowerStats,
	heat: HeatStats,
	income: number, -- credits per second, for display
}

local Simulation = {}

-- A radiator only dissipates in proportion to the empty cells around it --
-- the constraint that stops stacking modules mindlessly.
local function radiatorClearance(station: Station, placement: ModulePlacement): number
	local definition = ModuleCatalog.get(placement.id)
	if not definition then
		return 0
	end

	local width, height = ModuleCatalog.sizeOf(definition, placement.rotation)
	local total, free = 0, 0

	for _, cell in Grid.cells(placement.x, placement.y, width, height) do
		for _, neighbour in Grid.neighbours(cell.x, cell.y) do
			local occupant = station.occupancy[Grid.key(neighbour.x, neighbour.y)]
			if occupant == placement then
				continue
			end
			total += 1
			if not occupant then
				free += 1
			end
		end
	end

	return if total == 0 then 1 else free / total
end

function Simulation.step(params: StepParams): StepResult
	local station = params.station
	local dt = params.deltaTime

	-- 1. Power
	local production, consumption, storage = 0, 0, 0
	local heatLoad, heatCapacity = 0, params.heatRules.baseCapacity

	for _, placement in station.placements do
		local definition = ModuleCatalog.get(placement.id)
		if not definition then
			continue
		end

		if definition.power > 0 then
			-- Only solar panels depend on the sun; the core always runs.
			production += definition.power * (if placement.id == "SolarPanel"
				then params.sunlight
				else 1)
		else
			consumption -= definition.power
		end

		storage += definition.capacity or 0
		heatLoad += math.max(0, definition.heat)

		if definition.needsClearance then
			heatCapacity += params.heatRules.capacityPerRadiator * radiatorClearance(
				station,
				placement
			)
		end
	end

	local charge = math.min(params.charge, storage)
	local balance = production - consumption
	local powerEfficiency = 1

	if balance >= 0 then
		charge = math.min(storage, charge + balance * dt)
	else
		local needed = -balance * dt
		if charge >= needed then
			charge -= needed
		else
			charge = 0
			-- Batteries flat: everything only runs as fast as what comes in.
			powerEfficiency = if consumption > 0 then production / consumption else 1
		end
	end

	-- 2. Heat
	local heatRatio = if heatCapacity > 0 then heatLoad / heatCapacity else 0
	local heatEfficiency = 1
	if heatRatio > 1 then
		local excess = math.clamp(heatRatio - 1, 0, 1)
		heatEfficiency = 1 - (1 - params.heatRules.overheatPenalty) * excess
	end

	local efficiency = math.clamp(powerEfficiency * heatEfficiency, 0, 1)

	-- 3. Flow, network by network
	local revenue = 0
	for _, network in Network.build(station) do
		local oreRate, smeltRate, fabRate, shipRate = 0, 0, 0, 0

		for _, placement in network do
			local definition = ModuleCatalog.get(placement.id)
			if not definition or not definition.rate then
				continue
			end
			if placement.id == "OreCollector" then
				oreRate += definition.rate
			elseif placement.id == "Smelter" then
				smeltRate += definition.rate
			elseif placement.id == "Fabricator" then
				fabRate += definition.rate
			elseif placement.id == "CargoBay" then
				shipRate += definition.rate
			end
		end

		if shipRate <= 0 then
			continue -- nothing to sell without a cargo bay in the network
		end

		local ore = oreRate * efficiency * dt
		local smelted = math.min(ore, smeltRate * efficiency * dt)
		ore -= smelted

		local fabricated = math.min(smelted, fabRate * efficiency * dt)
		local alloy = smelted - fabricated

		-- The cargo bay has a limited throughput: past it, the surplus is
		-- lost.
		local units = ore + alloy + fabricated
		local capacity = shipRate * dt
		local throttle = if units > capacity and units > 0 then capacity / units else 1

		local values = params.resourceValues
		revenue += throttle * (ore * (values.Ore or 0) + alloy * (values.Alloy or 0) + fabricated * (values.Component or 0))
	end

	-- Credits are whole numbers: the fraction carries over to the next tick.
	local pending = params.pendingCredit + revenue
	local whole = math.floor(pending)

	return {
		charge = charge,
		pendingCredit = pending - whole,
		wholeRevenue = whole,
		efficiency = efficiency,
		power = {
			production = production,
			consumption = consumption,
			charge = charge,
			storage = storage,
		},
		heat = { load = heatLoad, capacity = heatCapacity },
		income = if dt > 0 then revenue / dt else 0,
	}
end

return Simulation
