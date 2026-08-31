--!strict
local OreCatalog = require(Domain.Research.OreCatalog)
local Rarity = require(Domain.Research.Rarity)

describe("OreCatalog consistency", function()
	it("gives every ore a valid, known rarity", function()
		for _, ore in OreCatalog.Ores do
			expect(Rarity.get(ore.rarity)).toBeTruthy()
		end
	end)

	it("covers all five rarities across the catalogue", function()
		local seen = {}
		for _, ore in OreCatalog.Ores do
			seen[ore.rarity] = true
		end
		for _, rarity in Rarity.List do
			expect(seen[rarity.id]).toBeTruthy()
		end
	end)

	it("rises in value as rarity rises (Common -> Mythic)", function()
		local byRarity = {}
		for _, ore in OreCatalog.Ores do
			byRarity[ore.rarity] = ore.value
		end
		expect(byRarity.Common < byRarity.Rare).toBeTruthy()
		expect(byRarity.Rare < byRarity.Epic).toBeTruthy()
		expect(byRarity.Epic < byRarity.Legendary).toBeTruthy()
		expect(byRarity.Legendary < byRarity.Mythic).toBeTruthy()
	end)

	it("has a unique id per ore", function()
		local seen = {}
		for _, ore in OreCatalog.Ores do
			expect(seen[ore.id]).toBeNil()
			seen[ore.id] = true
		end
	end)
end)

describe("OreCatalog.get", function()
	it("finds a known ore", function()
		expect(OreCatalog.get("Iron")).toBeTruthy()
	end)

	it("returns nil for an unknown id", function()
		expect(OreCatalog.get("Unobtanium")).toBeNil()
	end)
end)

describe("OreCatalog.atDepth", function()
	it("finds both ores sharing the floor (depth 3)", function()
		local ores = OreCatalog.atDepth(3)
		expect(#ores).toBe(2)
	end)

	it("returns an empty list for a depth with nothing", function()
		expect(#OreCatalog.atDepth(99)).toBe(0)
	end)
end)

describe("OreCatalog.oreForVein", function()
	it("cycles through both depth-3 ores across the four angle slots", function()
		local first = OreCatalog.oreForVein(3, 1)
		local second = OreCatalog.oreForVein(3, 2)
		local third = OreCatalog.oreForVein(3, 3)
		expect(first).toBeTruthy()
		expect(second).toBeTruthy()
		expect((first :: any).id).toBe((third :: any).id) -- wraps after 2 ores
		expect((first :: any).id ~= (second :: any).id).toBeTruthy()
	end)

	it("returns nil for a terrace with no ore", function()
		expect(OreCatalog.oreForVein(99, 1)).toBeNil()
	end)
end)

describe("OreCatalog.veinId / parseVeinId", function()
	it("round-trips a (terrace, slot) pair", function()
		local id = OreCatalog.veinId(2, 3)
		local terrace, slot = OreCatalog.parseVeinId(id)
		expect(terrace).toBe(2)
		expect(slot).toBe(3)
	end)

	it("refuses a malformed id", function()
		local terrace, slot = OreCatalog.parseVeinId("not-a-vein-id")
		expect(terrace).toBeNil()
		expect(slot).toBeNil()
	end)
end)
