--!strict
local AsteroidTiers = require(Domain.Mining.AsteroidTiers)

-- Cumulative shares: Common 0-60, Rare 60-85, Epic 85-97, Legendary 97-100.
local RULES = {
	tiers = {
		{ id = "Common", name = "Astéroïde commun", weight = 60, minReward = 15, maxReward = 30 },
		{ id = "Rare", name = "Astéroïde rare", weight = 25, minReward = 60, maxReward = 110 },
		{
			id = "Epic",
			name = "Astéroïde épique",
			weight = 12,
			minReward = 220,
			maxReward = 380,
		},
		{
			id = "Legendary",
			name = "Astéroïde légendaire",
			weight = 3,
			minReward = 900,
			maxReward = 1500,
		},
	},
}

describe("AsteroidTiers.get", function()
	it("finds a tier by id", function()
		local tier = AsteroidTiers.get("Rare", RULES)
		expect(tier).toBeTruthy()
		expect((tier :: any).minReward).toBe(60)
	end)

	it("returns nil for an unknown id", function()
		expect(AsteroidTiers.get("NotATier", RULES)).toBeNil()
	end)
end)

describe("AsteroidTiers.pick", function()
	it("lands on Common at roll = 0", function()
		expect(AsteroidTiers.pick(0, RULES)).toBe("Common")
	end)

	it("stays on Common just below its own boundary (60%)", function()
		expect(AsteroidTiers.pick(0.599, RULES)).toBe("Common")
	end)

	it("crosses into Rare exactly AT the 60% boundary", function()
		-- Exact ties fall to the NEXT tier, not the current one.
		expect(AsteroidTiers.pick(0.6, RULES)).toBe("Rare")
	end)

	it("stays on Rare just below its own boundary (85%)", function()
		expect(AsteroidTiers.pick(0.849, RULES)).toBe("Rare")
	end)

	it("crosses into Epic exactly AT the 85% boundary", function()
		expect(AsteroidTiers.pick(0.85, RULES)).toBe("Epic")
	end)

	it("crosses into Legendary exactly AT the 97% boundary", function()
		expect(AsteroidTiers.pick(0.97, RULES)).toBe("Legendary")
	end)

	it("lands on Legendary just below roll = 1", function()
		expect(AsteroidTiers.pick(0.999999, RULES)).toBe("Legendary")
	end)

	it("clamps roll = 1 to still return the last tier, not fall through", function()
		expect(AsteroidTiers.pick(1, RULES)).toBe("Legendary")
	end)
end)

describe("AsteroidTiers.reward", function()
	it("is exactly the tier's minReward at roll = 0", function()
		expect(AsteroidTiers.reward("Common", 0, RULES)).toBe(15)
	end)

	it("is exactly the tier's maxReward at roll = 1", function()
		expect(AsteroidTiers.reward("Common", 1, RULES)).toBe(30)
	end)

	it("interpolates linearly in between, floored to a whole credit", function()
		-- Legendary: 900 + (1500-900)*0.5 = 1200
		expect(AsteroidTiers.reward("Legendary", 0.5, RULES)).toBe(1200)
	end)
end)
