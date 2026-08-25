--!strict
local ModuleCatalog = require(Domain.Station.ModuleCatalog)

local UPGRADE_RULES = { maxLevel = 4, gainPerLevel = 0.5, costFactor = 2, minCost = 100 }

describe("ModuleCatalog.get / Order", function()
	it("resolves every id listed in Order to a real definition", function()
		for _, id in ModuleCatalog.Order do
			local definition = ModuleCatalog.get(id)
			expect(definition ~= nil).toBeTruthy()
			expect((definition :: any).id).toBe(id)
		end
	end)

	it("returns nil for an unknown id", function()
		expect(ModuleCatalog.get("NotAModule")).toBeNil()
	end)
end)

describe("ModuleCatalog.sizeOf", function()
	it("keeps the footprint unchanged on an even number of quarter-turns", function()
		local definition = ModuleCatalog.get("SolarPanel") :: any -- size 2x1
		local w0, h0 = ModuleCatalog.sizeOf(definition, 0)
		local w2, h2 = ModuleCatalog.sizeOf(definition, 2)
		expect(w0).toBe(2)
		expect(h0).toBe(1)
		expect(w2).toBe(2)
		expect(h2).toBe(1)
	end)

	it("swaps width and height on an odd number of quarter-turns", function()
		local definition = ModuleCatalog.get("SolarPanel") :: any
		local w1, h1 = ModuleCatalog.sizeOf(definition, 1)
		local w3, h3 = ModuleCatalog.sizeOf(definition, 3)
		expect(w1).toBe(1)
		expect(h1).toBe(2)
		expect(w3).toBe(1)
		expect(h3).toBe(2)
	end)

	it("defaults to unrotated when rotation is nil", function()
		local definition = ModuleCatalog.get("Radiator") :: any -- size 2x1
		local w, h = ModuleCatalog.sizeOf(definition, nil)
		expect(w).toBe(2)
		expect(h).toBe(1)
	end)
end)

describe("ModuleCatalog.isUpgradable", function()
	it("is upgradable when it produces power, stores capacity, or has a rate", function()
		expect(ModuleCatalog.isUpgradable(ModuleCatalog.get("SolarPanel") :: any)).toBeTruthy()
		expect(ModuleCatalog.isUpgradable(ModuleCatalog.get("Battery") :: any)).toBeTruthy()
		expect(ModuleCatalog.isUpgradable(ModuleCatalog.get("OreCollector") :: any)).toBeTruthy()
		expect(ModuleCatalog.isUpgradable(ModuleCatalog.get("Radiator") :: any)).toBeTruthy() -- needsClearance
	end)

	it("is not upgradable when it only carries or is purely structural", function()
		expect(ModuleCatalog.isUpgradable(ModuleCatalog.get("Corridor") :: any)).toBeFalsy()
		expect(ModuleCatalog.isUpgradable(ModuleCatalog.get("Conduit") :: any)).toBeFalsy()
	end)
end)

describe("ModuleCatalog.levelMultiplier / upgradeCost", function()
	it("is exactly 1x at level 1, so the catalogue sheet reads as-is", function()
		expect(ModuleCatalog.levelMultiplier(1, UPGRADE_RULES)).toBe(1)
		expect(ModuleCatalog.levelMultiplier(nil, UPGRADE_RULES)).toBe(1)
	end)

	it("grows by gainPerLevel for each level above 1", function()
		expect(ModuleCatalog.levelMultiplier(3, UPGRADE_RULES)).toBeNear(1 + 2 * 0.5)
	end)

	it("floors the upgrade cost at minCost", function()
		local cheap = ModuleCatalog.get("Corridor") :: any -- cost 25
		expect(ModuleCatalog.upgradeCost(cheap, 1, UPGRADE_RULES)).toBe(UPGRADE_RULES.minCost)
	end)

	it("grows the upgrade cost geometrically with costFactor once above the floor", function()
		local definition = ModuleCatalog.get("Fabricator") :: any -- cost 1200
		local costAt1 = ModuleCatalog.upgradeCost(definition, 1, UPGRADE_RULES)
		local costAt2 = ModuleCatalog.upgradeCost(definition, 2, UPGRADE_RULES)
		expect(costAt2 > costAt1).toBeTruthy()
	end)
end)
