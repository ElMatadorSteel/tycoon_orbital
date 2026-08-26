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

describe("Placement.coreLevel", function()
	it("reads the core's level, starting at 1", function()
		local station = Placement.initial()
		expect(Placement.coreLevel(station)).toBe(1)
	end)

	it("tracks the core's level after it changes", function()
		local station = Placement.initial()
		station.placements[1].level = 4 -- the core is always placements[1]
		expect(Placement.coreLevel(station)).toBe(4)
	end)
end)

describe("Placement.canMove", function()
	local Grid = require(Domain.Grid.Grid)

	-- A real "Corridor" placed by hand (canMove looks its definition up from
	-- the real ModuleCatalog by id, unlike canPlace, which takes one as a
	-- parameter -- so this needs a real catalogue id, not the CORRIDOR/CORE
	-- fixtures above).
	local function stationWithCorridor(): Placement.Station
		local station = Placement.initial()
		local placement = { id = "Corridor", x = 1, y = -1, rotation = 0, level = 1 }
		station.occupancy[Grid.key(1, -1)] = placement
		table.insert(station.placements, placement)
		return station
	end

	it("refuses when there is nothing at the given cell", function()
		local station = Placement.initial()
		local result = Placement.canMove(station, 4, 4, 5, 5, 0, GRID_RULES)
		expect(result.ok).toBeFalsy()
	end)

	it("refuses to move the unique core", function()
		local station = Placement.initial()
		local result = Placement.canMove(station, -1, -1, 5, 5, 0, GRID_RULES)
		expect(result.ok).toBeFalsy()
	end)

	it("accepts a move onto a free cell still touching the station", function()
		local station = stationWithCorridor()
		-- (0,-2) is free and orthogonally touches Core's (0,-1) cell.
		local result = Placement.canMove(station, 1, -1, 0, -2, 0, GRID_RULES)
		expect(result.ok).toBeTruthy()
	end)

	it("does not block a module from moving onto its own current cell", function()
		local station = stationWithCorridor()
		local result = Placement.canMove(station, 1, -1, 1, -1, 0, GRID_RULES)
		expect(result.ok).toBeTruthy()
	end)

	it("refuses a destination overlapping another module", function()
		local station = stationWithCorridor()
		local result = Placement.canMove(station, 1, -1, -1, -1, 0, GRID_RULES)
		expect(result.ok).toBeFalsy()
	end)

	it("refuses a destination touching nothing", function()
		local station = stationWithCorridor()
		local result = Placement.canMove(station, 1, -1, 4, 4, 0, GRID_RULES)
		expect(result.ok).toBeFalsy()
	end)

	it("refuses a destination outside the grid radius", function()
		local station = stationWithCorridor()
		local result = Placement.canMove(station, 1, -1, GRID_RULES.radius + 1, 0, 0, GRID_RULES)
		expect(result.ok).toBeFalsy()
	end)
end)
