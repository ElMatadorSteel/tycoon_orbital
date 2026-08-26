--!strict
local Simulation = require(Domain.Production.Simulation)
local Grid = require(Domain.Grid.Grid)
local ModuleCatalog = require(Domain.Station.ModuleCatalog)

local function emptyStation()
	return { occupancy = {}, placements = {} }
end

local function place(station: any, id: string, x: number, y: number, rotation: number?)
	local definition = ModuleCatalog.get(id) :: any
	local width, height = ModuleCatalog.sizeOf(definition, rotation)
	local placement = { id = id, x = x, y = y, rotation = rotation or 0, level = 1 }
	for _, cell in Grid.cells(x, y, width, height) do
		station.occupancy[Grid.key(cell.x, cell.y)] = placement
	end
	table.insert(station.placements, placement)
	return placement
end

-- Fixture rules -- deliberately not the real Balance numbers, per
-- DEVELOPMENT.md's "domain specs use their own fixtures".
local HEAT_RULES = { baseCapacity = 40, capacityPerRadiator = 60, overheatPenalty = 0.5 }
local LOW_HEAT_RULES = { baseCapacity = 20, capacityPerRadiator = 60, overheatPenalty = 0.5 }
local RESOURCE_VALUES = { Ore = 5, Alloy = 22, Component = 75 }
-- gainPerLevel = 0.5: a level-2 module's levelMultiplier is 1.5, a
-- level-3's is 2 -- clean numbers to check the boost against by hand.
local UPGRADE_RULES =
	{ maxLevel = 5, gainPerLevel = 0.5, costFactor = 2, minCost = 100, coreUpgradeCost = 150 }

local function baseParams(overrides: { [string]: any }?)
	local params = {
		station = emptyStation(),
		sunlight = 1,
		deltaTime = 1,
		charge = 0,
		pendingCredit = 0,
		heatRules = HEAT_RULES,
		resourceValues = RESOURCE_VALUES,
		upgradeRules = UPGRADE_RULES,
	}
	if overrides then
		for key, value in overrides do
			(params :: any)[key] = value
		end
	end
	return params
end

describe("Simulation.step -- power", function()
	it("a bare core produces no revenue and stays at full efficiency", function()
		local station = emptyStation()
		place(station, "Core", -1, -1)
		local result = Simulation.step(baseParams({ station = station }))
		expect(result.efficiency).toBe(1)
		expect(result.wholeRevenue).toBe(0)
		expect(result.power.production).toBe(20)
		expect(result.power.consumption).toBe(0)
	end)

	it(
		"throttles power efficiency when consumption outpaces production and the battery is empty",
		function()
			local station = emptyStation()
			place(station, "Core", -1, -1) -- power +20
			place(station, "Smelter", 1, -1) -- power -14
			place(station, "Fabricator", 1, 1) -- power -20
			local result = Simulation.step(baseParams({ station = station, charge = 0 }))
			-- production 20, consumption 34 -> powerEfficiency = 20/34
			expect(result.power.production).toBe(20)
			expect(result.power.consumption).toBe(34)
			expect(result.efficiency).toBeNear(20 / 34)
			expect(result.charge).toBe(0) -- drained, not negative
		end
	)

	it("draws down the battery instead of throttling, while it has charge", function()
		local station = emptyStation()
		place(station, "Core", -1, -1) -- +20
		place(station, "Smelter", 1, -1) -- -14
		place(station, "Fabricator", 1, 1) -- -20
		place(station, "Battery", 0, 1) -- capacity 120, without this storage is 0
		-- deficit is 14/s; a charge of 100 (within the battery's capacity)
		-- comfortably covers one second.
		local result = Simulation.step(baseParams({ station = station, charge = 100 }))
		expect(result.efficiency).toBe(1)
		expect(result.charge).toBeNear(100 - 14)
	end)
end)

describe("Simulation.step -- heat", function()
	it("applies the overheat penalty once load exceeds capacity", function()
		local station = emptyStation()
		place(station, "Core", -1, -1) -- heat 2
		place(station, "Smelter", 1, -1) -- heat 14
		place(station, "Fabricator", 1, 1) -- heat 16
		place(station, "Battery", 0, 1) -- capacity 120 (and heat 0.5) so charge below can buffer
		-- total load 32.5 (2 + 14 + 16 + the battery's own 0.5), LOW_HEAT_RULES
		-- caps base capacity at 20 with no radiators -> heatRatio 1.625,
		-- excess clamped to 1 max -> 0.625.
		local result = Simulation.step(baseParams({
			station = station,
			charge = 100, -- comfortably covers the 14/s deficit so power never throttles here
			heatRules = LOW_HEAT_RULES,
		}))
		expect(result.heat.load).toBe(32.5)
		expect(result.heat.capacity).toBe(20)
		-- heatEfficiency = 1 - (1 - 0.5) * 0.625 = 0.6875, powerEfficiency = 1
		expect(result.efficiency).toBeNear(0.6875)
	end)

	it("never drops efficiency below the overheat penalty floor", function()
		local station = emptyStation()
		place(station, "Core", -1, -1)
		place(station, "Smelter", 1, -1)
		place(station, "Fabricator", 1, 1)
		place(station, "Battery", 0, 1)
		local result = Simulation.step(baseParams({
			station = station,
			charge = 100,
			heatRules = { baseCapacity = 1, capacityPerRadiator = 0, overheatPenalty = 0.5 },
		}))
		expect(result.efficiency).toBeNear(0.5)
	end)
end)

describe("Simulation.step -- resource flow", function()
	it("sells what an ore collector produces through a connected cargo bay", function()
		local station = emptyStation()
		place(station, "Core", -1, -1)
		place(station, "OreCollector", 1, -1) -- rate 1, touches the cargo bay below
		place(station, "CargoBay", 1, 1) -- rate 4
		local result = Simulation.step(baseParams({ station = station, charge = 1000 }))
		-- 1 unit of ore/s at full efficiency, under the cargo bay's rate-4
		-- cap -> no throttling, sold at Ore's fixture value of 5.
		expect(result.wholeRevenue).toBe(5)
	end)

	it("sells nothing from a network with no cargo bay", function()
		local station = emptyStation()
		place(station, "Core", -1, -1)
		place(station, "OreCollector", 1, -1)
		local result = Simulation.step(baseParams({ station = station, charge = 1000 }))
		expect(result.wholeRevenue).toBe(0)
	end)

	it("carries a fractional remainder over as pendingCredit instead of dropping it", function()
		local station = emptyStation()
		place(station, "Core", -1, -1)
		place(station, "OreCollector", 1, -1)
		place(station, "CargoBay", 1, 1)
		-- A short tick: 1 unit/s * 0.1s * value 5 = 0.5, entirely fractional.
		local result = Simulation.step(baseParams({
			station = station,
			charge = 1000,
			deltaTime = 0.1,
		}))
		expect(result.wholeRevenue).toBe(0)
		expect(result.pendingCredit).toBeNear(0.5)
	end)
end)

-- Regression coverage for a real bug: ModuleCatalog.levelMultiplier existed
-- but nothing ever called it, so upgrading a module raised its level (and
-- its cost) without changing a single simulated number. Balance.Upgrade's
-- own rule is "a level only ever increases what a module PRODUCES, never
-- what it consumes" -- these pin both halves of that.
describe("Simulation.step -- module levels", function()
	it("a higher-level solar panel produces more power", function()
		local station = emptyStation()
		place(station, "Core", -1, -1) -- +20, level 1
		local panel = place(station, "SolarPanel", 1, -1) -- base +12
		panel.level = 2 -- multiplier 1.5 under UPGRADE_RULES
		local result = Simulation.step(baseParams({ station = station }))
		expect(result.power.production).toBe(20 + 12 * 1.5)
	end)

	it("a higher-level battery stores more", function()
		local station = emptyStation()
		local battery = place(station, "Battery", -1, -1) -- base capacity 120
		battery.level = 2
		local result = Simulation.step(baseParams({ station = station }))
		expect(result.power.storage).toBe(120 * 1.5)
	end)

	it("a higher-level radiator dissipates more heat", function()
		local station = emptyStation()
		local radiator = place(station, "Radiator", -1, -1) -- fully isolated -> full clearance
		radiator.level = 2
		local result = Simulation.step(baseParams({ station = station }))
		-- baseCapacity 40 + capacityPerRadiator 60 * clearance 1 * boost 1.5
		expect(result.heat.capacity).toBe(40 + 60 * 1.5)
	end)

	it("a higher-level ore collector and cargo bay raise revenue", function()
		local station = emptyStation()
		place(station, "Core", -1, -1)
		local collector = place(station, "OreCollector", 1, -1) -- base rate 1
		collector.level = 3 -- multiplier 2
		place(station, "CargoBay", 1, 1) -- base rate 4, level 1 -> still 4, no throttle
		local result = Simulation.step(baseParams({ station = station, charge = 1000 }))
		-- 1 * 2 units/s * value 5
		expect(result.income).toBeNear(10)
	end)

	it("does not scale what a module consumes, only what it produces", function()
		local station = emptyStation()
		place(station, "Core", -1, -1) -- heat 2, level 1
		local smelter = place(station, "Smelter", 1, -1) -- power -14, heat 14
		smelter.level = 3 -- multiplier 2, but consumption/heat must stay fixed
		local result = Simulation.step(baseParams({ station = station, charge = 1000 }))
		expect(result.power.consumption).toBe(14)
		expect(result.heat.load).toBe(2 + 14)
	end)
end)
