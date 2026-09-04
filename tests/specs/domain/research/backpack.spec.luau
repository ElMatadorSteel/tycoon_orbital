--!strict
local Backpack = require(Domain.Research.Backpack)

describe("Backpack.count", function()
	it("counts an empty bag as 0", function()
		expect(Backpack.count({})).toBe(0)
	end)

	it("sums all ore counts", function()
		expect(Backpack.count({ Iron = 3, Copper = 7 })).toBe(10)
	end)

	it("ignores zero or negative entries", function()
		expect(Backpack.count({ Iron = 5, Copper = 0, Titanium = -1 })).toBe(5)
	end)
end)

describe("Backpack.isFull", function()
	it("is not full when under capacity", function()
		expect(Backpack.isFull({ Iron = 10 }, 50)).toBeFalsy()
	end)

	it("is full when at capacity", function()
		expect(Backpack.isFull({ Iron = 30, Copper = 20 }, 50)).toBeTruthy()
	end)

	it("is full when over capacity (corrupted data)", function()
		expect(Backpack.isFull({ Iron = 99 }, 50)).toBeTruthy()
	end)
end)
