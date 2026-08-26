--!strict
local Rebirth = require(Domain.Rebirth.Rebirth)

local RULES = {
	enabled = true,
	normalThreshold = 10,
	earlyThreshold = 5,
	bonusPerRebirth = 0.25,
	ultimateMultiplier = 1.5,
}

describe("Rebirth.canRebirth", function()
	it("refuses below the normal threshold, without the early pass", function()
		expect(Rebirth.canRebirth(9, false, RULES)).toBeFalsy()
	end)

	it("allows at the normal threshold, without the early pass", function()
		expect(Rebirth.canRebirth(10, false, RULES)).toBeTruthy()
	end)

	it("refuses below the early threshold, even with the early pass", function()
		expect(Rebirth.canRebirth(4, true, RULES)).toBeFalsy()
	end)

	it("allows at the early threshold, with the early pass", function()
		expect(Rebirth.canRebirth(5, true, RULES)).toBeTruthy()
	end)

	it("does not let the early pass allow anything below ITS OWN threshold", function()
		-- The pass lowers the bar, it doesn't remove it.
		expect(Rebirth.canRebirth(6, false, RULES)).toBeFalsy() -- no pass: still needs 10
	end)

	it("is entirely dormant when disabled, whatever the core's level", function()
		local off = {
			enabled = false,
			normalThreshold = 10,
			earlyThreshold = 5,
			bonusPerRebirth = 0.25,
			ultimateMultiplier = 1.5,
		}
		expect(Rebirth.canRebirth(999, true, off)).toBeFalsy()
	end)
end)

describe("Rebirth.multiplier", function()
	it("is exactly 1x with no rebirths and no Ultimate", function()
		expect(Rebirth.multiplier(0, false, RULES)).toBe(1)
	end)

	it("stacks additively per rebirth", function()
		expect(Rebirth.multiplier(1, false, RULES)).toBeNear(1.25)
		expect(Rebirth.multiplier(3, false, RULES)).toBeNear(1.75) -- 1 + 3*0.25
	end)

	it("multiplies the whole thing by Ultimate on top, once", function()
		expect(Rebirth.multiplier(0, true, RULES)).toBeNear(1.5)
		expect(Rebirth.multiplier(3, true, RULES)).toBeNear(1.75 * 1.5)
	end)

	it("never goes below 1x even if rebirths were somehow negative", function()
		expect(Rebirth.multiplier(-5, false, RULES)).toBe(1)
	end)
end)
