--!strict
local Rarity = require(Domain.Research.Rarity)

describe("Rarity.get", function()
	it("finds each of the five tiers by id", function()
		expect(Rarity.get("Common")).toBeTruthy()
		expect(Rarity.get("Rare")).toBeTruthy()
		expect(Rarity.get("Epic")).toBeTruthy()
		expect(Rarity.get("Legendary")).toBeTruthy()
		expect(Rarity.get("Mythic")).toBeTruthy()
	end)

	it("returns nil for an unknown id", function()
		expect(Rarity.get("Godlike")).toBeNil()
	end)

	it("orders Mythic above Common", function()
		local common = Rarity.get("Common")
		local mythic = Rarity.get("Mythic")
		expect(common).toBeTruthy()
		expect(mythic).toBeTruthy()
		expect((mythic :: any).order > (common :: any).order).toBeTruthy()
	end)
end)

describe("Rarity.List", function()
	it("has exactly five tiers", function()
		expect(#Rarity.List).toBe(5)
	end)

	it("is ordered ascending by its own order field", function()
		for index, rarity in Rarity.List do
			expect(rarity.order).toBe(index)
		end
	end)
end)
