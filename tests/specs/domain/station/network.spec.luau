--!strict
local Network = require(Domain.Station.Network)
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

describe("Network.build", function()
	it("connects two adjacent carrying modules into one network", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0) -- occupies (0,0)-(1,1)
		place(station, "CargoBay", 2, 0) -- occupies (2,0)-(3,1), touches at x=1/x=2
		local networks = Network.build(station)
		expect(#networks).toBe(1)
		expect(#networks[1]).toBe(2)
	end)

	it("does not connect through a corridor, since it carries nothing", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "Corridor", 2, 0) -- touches OreCollector, but doesn't carry
		place(station, "CargoBay", 3, 0) -- touches the corridor, not the collector directly
		local networks = Network.build(station)
		expect(#networks).toBe(2) -- OreCollector alone, CargoBay alone
	end)

	it("connects through a conduit, since it carries", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "Conduit", 2, 0)
		place(station, "CargoBay", 3, 0)
		local networks = Network.build(station)
		expect(#networks).toBe(1)
		expect(#networks[1]).toBe(3)
	end)

	it("skip treats an id as non-carrying, splitting the network back apart", function()
		local station = emptyStation()
		place(station, "OreCollector", 0, 0)
		place(station, "Conduit", 2, 0)
		place(station, "CargoBay", 3, 0)
		local networks = Network.build(station, { Conduit = true })
		expect(#networks).toBe(2)
	end)

	it("gives a non-carrying module no network of its own", function()
		local station = emptyStation()
		place(station, "Corridor", 0, 0)
		local networks = Network.build(station)
		expect(#networks).toBe(0)
	end)
end)
