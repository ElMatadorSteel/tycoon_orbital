--!strict
local Credits = require(Domain.Economy.Credits)

describe("Credits.spend", function()
	it("refuses when the balance is insufficient", function()
		local result = Credits.spend(50, 100)
		expect(result.ok).toBe(false)
	end)

	it("succeeds and returns the reduced balance when funds are sufficient", function()
		local result = Credits.spend(100, 40)
		expect(result.ok).toBe(true)
		expect((result :: any).value).toBe(60)
	end)

	it("allows spending the exact balance down to zero", function()
		local result = Credits.spend(100, 100)
		expect(result.ok).toBe(true)
		expect((result :: any).value).toBe(0)
	end)

	it("canSpend agrees with spend", function()
		expect(Credits.canSpend(50, 100)).toBe(false)
		expect(Credits.canSpend(100, 50)).toBe(true)
	end)
end)
