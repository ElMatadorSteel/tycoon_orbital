--!strict
local Checks = require(Domain.Objectives.Checks)
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

describe("Checks.ById.Collector / Solar / Radiator", function()
	it("passes once the matching module exists anywhere on the station", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "SolarPanel", 3, 0)
		place(station, "Radiator", 0, 3)
		expect(Checks.ById.Collector(station)).toBeTruthy()
		expect(Checks.ById.Solar(station)).toBeTruthy()
		expect(Checks.ById.Radiator(station)).toBeTruthy()
	end)

	it("fails on an empty station", function()
		local station = emptyStation()
		expect(Checks.ById.Collector(station)).toBeFalsy()
		expect(Checks.ById.Solar(station)).toBeFalsy()
		expect(Checks.ById.Radiator(station)).toBeFalsy()
	end)
end)

describe("Checks.ById.Sell", function()
	it("passes once a collector and a cargo bay share a network", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "CargoBay", 2, 0)
		expect(Checks.ById.Sell(station)).toBeTruthy()
	end)

	it("fails when the two exist but aren't connected", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "CargoBay", 10, 10)
		expect(Checks.ById.Sell(station)).toBeFalsy()
	end)
end)

describe("Checks.ById.Conduit", function()
	it("fails when a conduit exists but bridges nothing (touches only one worker)", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "Conduit", 2, 0)
		expect(Checks.ById.Conduit(station)).toBeFalsy()
	end)

	it("passes once a conduit is the only thing bridging two workers", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "Conduit", 2, 0)
		place(station, "CargoBay", 3, 0)
		expect(Checks.ById.Conduit(station)).toBeTruthy()
	end)

	it("fails when the two workers are already connected without the conduit", function()
		-- OreCollector and CargoBay touch directly; the conduit stuck onto
		-- the side isn't bridging anything -- buying one isn't the point,
		-- understanding what it's for is.
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "CargoBay", 2, 0)
		place(station, "Conduit", 0, 2)
		expect(Checks.ById.Conduit(station)).toBeFalsy()
	end)
end)
