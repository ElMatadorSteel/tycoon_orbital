--!strict
local Orbit = require(Domain.Production.Orbit)

-- period=180, eclipseFraction=0.3, ramp=0.06 (fixed inside Orbit.luau) --
-- pinned reference points rather than re-deriving the arithmetic, per
-- DEVELOPMENT.md's "pin the intent, not just the arithmetic": retuning the
-- ramp width should surface here as a failing test, not as a bad feeling
-- three days later.
local RULES = { period = 180, eclipseFraction = 0.3 }

describe("Orbit.sunlightAt", function()
	it("is fully dark at the start of the eclipse", function()
		expect(Orbit.sunlightAt(0, RULES)).toBe(0)
	end)

	it("is fully dark right up to the start of the ramp out of eclipse", function()
		-- phase = eclipseFraction - ramp = 0.24 -> elapsed = 0.24 * period
		expect(Orbit.sunlightAt(0.24 * 180, RULES)).toBeNear(0)
	end)

	it("is halfway up the ramp out of eclipse at its midpoint", function()
		-- phase = 0.27 (midway between 0.24 and 0.30)
		expect(Orbit.sunlightAt(0.27 * 180, RULES)).toBeNear(0.5)
	end)

	it("is fully lit right at the end of the eclipse fraction", function()
		expect(Orbit.sunlightAt(0.3 * 180, RULES)).toBeNear(1)
	end)

	it("stays fully lit through the middle of the orbit", function()
		expect(Orbit.sunlightAt(0.5 * 180, RULES)).toBeNear(1)
	end)

	it("is still fully lit right up to the start of the ramp into eclipse", function()
		-- phase = 1 - ramp = 0.94
		expect(Orbit.sunlightAt(0.94 * 180, RULES)).toBeNear(1)
	end)

	it("is halfway down the ramp into eclipse at its midpoint", function()
		-- phase = 0.97 (midway between 0.94 and 1.0)
		expect(Orbit.sunlightAt(0.97 * 180, RULES)).toBeNear(0.5)
	end)

	it("wraps around: a full period is identical to elapsed = 0", function()
		expect(Orbit.sunlightAt(180, RULES)).toBe(0)
		expect(Orbit.sunlightAt(180 + 0.5 * 180, RULES)).toBeNear(1)
	end)
end)
