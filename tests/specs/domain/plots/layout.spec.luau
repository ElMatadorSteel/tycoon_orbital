--!strict
local Layout = require(Domain.Plots.Layout)

describe("Layout.slots", function()
	it("returns exactly `count` slots, indexed in order", function()
		local slots = Layout.slots({
			centerX = 0,
			centerZ = 0,
			count = 6,
			distance = 900,
			spread = 26,
			altitude = 0,
		})
		expect(#slots).toBe(6)
		for index, slot in slots do
			expect(slot.index).toBe(index)
		end
	end)

	it(
		"pins exact positions with spread=0 (angle collapses to 0, sin=0/cos=1 for every slot)",
		function()
			-- With every angle at 0: x stays exactly centerX, and z is exactly
			-- centerZ + distance -- easy to pin without a calculator, and it
			-- still exercises the real distance/altitude alternation.
			local slots = Layout.slots({
				centerX = 0,
				centerZ = 0,
				count = 4,
				distance = 100,
				spread = 0,
				altitude = 10,
			})

			expect(slots[1].x).toBeNear(0)
			expect(slots[1].z).toBeNear(100) -- 100 + 0 (odd index, no distance bonus)
			expect(slots[1].y).toBe(10) -- 10 + (1%3 - 1) * 65 = 10

			expect(slots[2].z).toBeNear(260) -- 100 + 160 (even index bonus)
			expect(slots[2].y).toBe(75) -- 10 + (2%3 - 1) * 65 = 75

			expect(slots[3].z).toBeNear(100)
			expect(slots[3].y).toBe(-55) -- 10 + (3%3 - 1) * 65 = -55

			expect(slots[4].z).toBeNear(260)
			expect(slots[4].y).toBe(10)
		end
	)

	it("offsets every position from the given lobby center", function()
		local atOrigin = Layout.slots({
			centerX = 0,
			centerZ = 0,
			count = 1,
			distance = 500,
			spread = 0,
			altitude = 0,
		})
		local offset = Layout.slots({
			centerX = 1000,
			centerZ = -700,
			count = 1,
			distance = 500,
			spread = 0,
			altitude = 0,
		})
		expect(offset[1].x).toBeNear(atOrigin[1].x + 1000)
		expect(offset[1].z).toBeNear(atOrigin[1].z - 700)
	end)
end)
