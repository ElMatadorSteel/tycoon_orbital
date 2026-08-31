--!strict
local ResearchMine = require(Domain.Research.ResearchMine)

local RULES = { cost = 2500 }

describe("ResearchMine.isUnlocked", function()
	it("is false when the flag is absent", function()
		expect(ResearchMine.isUnlocked({})).toBeFalsy()
	end)

	it("is true once the flag is set", function()
		expect(ResearchMine.isUnlocked({ ResearchMine = true })).toBeTruthy()
	end)
end)

describe("ResearchMine.canUnlock", function()
	it("refuses without enough credits", function()
		expect(ResearchMine.canUnlock(2499, {}, RULES)).toBeFalsy()
	end)

	it("allows exactly at the cost", function()
		expect(ResearchMine.canUnlock(2500, {}, RULES)).toBeTruthy()
	end)

	it("refuses if already unlocked, however many credits", function()
		expect(ResearchMine.canUnlock(999999, { ResearchMine = true }, RULES)).toBeFalsy()
	end)
end)
