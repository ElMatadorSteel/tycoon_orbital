--!strict
local Placement = require(Domain.Station.Placement)

local GRID_RULES = { cellSize = 8, radius = 5 }
local CORRIDOR = { id = "Corridor", name = "Corridor", size = { w = 1, h = 1 } } :: any
local CORE = { id = "Core", name = "Core", size = { w = 2, h = 2 }, unique = true } :: any

describe("Placement.initial", function()
	it("starts with the core placed at -1,-1, a 2x2 footprint", function()
		local station = Placement.initial()
		expect(#station.placements).toBe(1)
		expect(station.placements[1].id).toBe("Core")

		local Grid = require(Domain.Grid.Grid)
		for _, cell in Grid.cells(-1, -1, 2, 2) do
			expect(station.occupancy[Grid.key(cell.x, cell.y)] ~= nil).toBeTruthy()
		end
	end)
end)

describe("Placement.canPlace", function()
	it("accepts a module touching the existing station on a free cell", function()
		local station = Placement.initial()
		-- (1, -1) is empty and orthogonally touches Core's (0, -1) cell.
		local result = Placement.canPlace(station, CORRIDOR, 1, -1, 0, GRID_RULES, false)
		expect(result.ok).toBeTruthy()
	end)

	it("refuses a module that touches nothing", function()
		local station = Placement.initial()
		local result = Placement.canPlace(station, CORRIDOR, 4, 4, 0, GRID_RULES, false)
		expect(result.ok).toBeFalsy()
	end)

	it("refuses a module overlapping an occupied cell", function()
		local station = Placement.initial()
		local result = Placement.canPlace(station, CORRIDOR, -1, -1, 0, GRID_RULES, false)
		expect(result.ok).toBeFalsy()
	end)

	it("refuses a module reaching outside the grid radius", function()
		local station = Placement.initial()
		local result =
			Placement.canPlace(station, CORRIDOR, GRID_RULES.radius + 1, 0, 0, GRID_RULES, false)
		expect(result.ok).toBeFalsy()
	end)

	it("refuses a second unique module even if it would otherwise fit", function()
		local station = Placement.initial()
		local result = Placement.canPlace(station, CORE, 1, -1, 0, GRID_RULES, false)
		expect(result.ok).toBeFalsy()
	end)

	it("free placement skips the touches-station and uniqueness checks", function()
		local station = { occupancy = {}, placements = {} }
		local result = Placement.canPlace(station, CORE, -1, -1, 0, GRID_RULES, true)
		expect(result.ok).toBeTruthy()
	end)

	it("free placement still refuses an occupied cell", function()
		local station = Placement.initial()
		local result = Placement.canPlace(station, CORRIDOR, -1, -1, 0, GRID_RULES, true)
		expect(result.ok).toBeFalsy()
	end)
end)

describe("Placement.canRemove", function()
	it("refuses to demolish the unique core", function()
		local station = Placement.initial()
		local result = Placement.canRemove(station, -1, -1)
		expect(result.ok).toBeFalsy()
	end)

	it("refuses when there is nothing at the given cell", function()
		local station = Placement.initial()
		local result = Placement.canRemove(station, 4, 4)
		expect(result.ok).toBeFalsy()
	end)
end)
