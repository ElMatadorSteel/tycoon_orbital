--!strict
local Credits = require(Domain.Economy.Credits)

describe("Credits.add", function()
	it("increases the balance", function()
		expect(Credits.add(100, 50)).toBe(150)
	end)

	it("floors at zero when subtracting more than the balance", function()
		expect(Credits.add(10, -50)).toBe(0)
	end)

	it("never goes negative even from zero", function()
		expect(Credits.add(0, -1)).toBe(0)
	end)
end)
