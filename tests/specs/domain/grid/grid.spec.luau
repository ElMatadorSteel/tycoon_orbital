--!strict
local Grid = require(Domain.Grid.Grid)

local RULES = { cellSize = 8, radius = 2 }

describe("Grid.key", function()
	it("formats a cell as a stable string", function()
		expect(Grid.key(3, -4)).toBe("3,-4")
	end)
end)

describe("Grid.cells", function()
	it("lists every cell covered by a module's footprint", function()
		local cells = Grid.cells(0, 0, 2, 2)
		expect(#cells).toBe(4)
		local keys = {}
		for _, cell in cells do
			keys[Grid.key(cell.x, cell.y)] = true
		end
		expect(keys["0,0"]).toBeTruthy()
		expect(keys["1,0"]).toBeTruthy()
		expect(keys["0,1"]).toBeTruthy()
		expect(keys["1,1"]).toBeTruthy()
	end)

	it("returns a single cell for a 1x1 module", function()
		local cells = Grid.cells(5, -3, 1, 1)
		expect(#cells).toBe(1)
		expect(cells[1].x).toBe(5)
		expect(cells[1].y).toBe(-3)
	end)
end)

describe("Grid.isInBounds", function()
	it("accepts a module fully inside the radius", function()
		expect(Grid.isInBounds(-2, -2, 1, 1, RULES)).toBeTruthy()
		expect(Grid.isInBounds(1, 1, 2, 2, RULES)).toBeTruthy() -- reaches exactly to radius 2
	end)

	it("refuses a module reaching past the radius", function()
		expect(Grid.isInBounds(2, 0, 2, 1, RULES)).toBeFalsy() -- would reach x = 3
	end)
end)

describe("Grid.offset", function()
	it("centres a module on its footprint", function()
		local offset = Grid.offset(0, 0, 2, 2, RULES)
		expect(offset.x).toBeNear(0.5 * RULES.cellSize)
		expect(offset.z).toBeNear(0.5 * RULES.cellSize)
		expect(offset.y).toBe(0)
	end)

	it("matches the cell centre for a 1x1 module", function()
		local offset = Grid.offset(1, 1, 1, 1, RULES)
		expect(offset.x).toBeNear(1 * RULES.cellSize)
		expect(offset.z).toBeNear(1 * RULES.cellSize)
	end)
end)

describe("Grid.neighbours", function()
	it("returns the four orthogonal cells, never a diagonal", function()
		local neighbours = Grid.neighbours(0, 0)
		expect(#neighbours).toBe(4)
		local keys = {}
		for _, cell in neighbours do
			keys[Grid.key(cell.x, cell.y)] = true
		end
		expect(keys["0,1"]).toBeTruthy()
		expect(keys["1,0"]).toBeTruthy()
		expect(keys["0,-1"]).toBeTruthy()
		expect(keys["-1,0"]).toBeTruthy()
		expect(keys["1,1"]).toBeFalsy()
	end)
end)
