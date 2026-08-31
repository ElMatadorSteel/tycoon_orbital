--!strict
local Vein = require(Domain.Research.Vein)

describe("Vein.canMine", function()
	it("refuses just under the cooldown", function()
		expect(Vein.canMine(10, 13.999, 4)).toBeFalsy()
	end)

	it("allows exactly at the cooldown boundary", function()
		expect(Vein.canMine(10, 14, 4)).toBeTruthy()
	end)

	it("allows well past the cooldown", function()
		expect(Vein.canMine(10, 100, 4)).toBeTruthy()
	end)

	it("allows a vein that has never been mined (lastMinedAt = 0)", function()
		expect(Vein.canMine(0, 5, 4)).toBeTruthy()
	end)
end)
