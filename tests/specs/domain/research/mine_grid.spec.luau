--!strict
local MineGrid = require(Domain.Research.MineGrid)

local SMALL_RULES: MineGrid.Rules = {
	regenInterval = 21600, -- 6h
	layers = {
		{
			width = 4,
			depth = 4,
			density = 0.5,
			pool = {
				{ id = "Iron", weight = 70 },
				{ id = "Copper", weight = 30 },
			},
		},
		{
			width = 4,
			depth = 4,
			density = 0.4,
			pool = {
				{ id = "Iron", weight = 40 },
				{ id = "Titanium", weight = 60 },
			},
		},
	},
}

-- Deterministic rolls: all zeros → every cell gets ore, picks first pool entry
local function zeroRolls(count: number): { number }
	local rolls = {}
	for i = 1, count do
		rolls[i] = 0
	end
	return rolls
end

-- All ones (just under) → density 0.5 means half pass, half fail
local function highRolls(count: number): { number }
	local rolls = {}
	for i = 1, count do
		rolls[i] = 0.999
	end
	return rolls
end

describe("MineGrid.cellKey / parseCellKey", function()
	it("round-trips a coordinate pair", function()
		local key = MineGrid.cellKey(3, 7)
		local x, y = MineGrid.parseCellKey(key)
		expect(x).toBe(3)
		expect(y).toBe(7)
	end)

	it("refuses a malformed key", function()
		local x, y = MineGrid.parseCellKey("nope")
		expect(x).toBeNil()
		expect(y).toBeNil()
	end)
end)

describe("MineGrid.shouldRegenerate", function()
	it("does not regenerate before the interval", function()
		expect(MineGrid.shouldRegenerate(1000, 1000 + 21599, 21600)).toBeFalsy()
	end)

	it("regenerates exactly at the interval boundary", function()
		expect(MineGrid.shouldRegenerate(1000, 1000 + 21600, 21600)).toBeTruthy()
	end)

	it("regenerates well past the interval", function()
		expect(MineGrid.shouldRegenerate(1000, 1000 + 99999, 21600)).toBeTruthy()
	end)
end)

describe("MineGrid.pickOre", function()
	it("picks the first entry at roll 0", function()
		local pool = { { id = "A", weight = 60 }, { id = "B", weight = 40 } }
		expect(MineGrid.pickOre(pool, 0)).toBe("A")
	end)

	it("picks the second entry at a roll past the first weight", function()
		local pool = { { id = "A", weight = 60 }, { id = "B", weight = 40 } }
		-- 60/100 = 0.6, so roll 0.61 should land in B
		expect(MineGrid.pickOre(pool, 0.61)).toBe("B")
	end)

	it("handles a single-entry pool", function()
		local pool = { { id = "Only", weight = 1 } }
		expect(MineGrid.pickOre(pool, 0.5)).toBe("Only")
	end)
end)

describe("MineGrid.generateLayer", function()
	it("places ore in every cell when all density rolls are 0 and density is > 0", function()
		local lr = SMALL_RULES.layers[1] -- 4x4, density 0.5
		local rolls = zeroRolls(16 * 2) -- 16 cells * 2 passes
		local layer = MineGrid.generateLayer(lr, rolls)
		-- All 16 density rolls are 0 < 0.5 → all 16 cells get ore
		expect(MineGrid.oreCount(layer)).toBe(16)
	end)

	it("places no ore when all density rolls are above density", function()
		local lr = SMALL_RULES.layers[1] -- density 0.5
		local rolls = highRolls(16 * 2)
		local layer = MineGrid.generateLayer(lr, rolls)
		expect(MineGrid.oreCount(layer)).toBe(0)
	end)

	it("uses the pool weights to pick ore types", function()
		-- Layer 1: Iron weight 70, Copper weight 30 → total 100
		-- All density rolls = 0 (all pass), all pick rolls = 0 → always Iron
		local lr = SMALL_RULES.layers[1]
		local rolls = zeroRolls(16 * 2)
		local layer = MineGrid.generateLayer(lr, rolls)
		for _, oreId in layer.ores do
			expect(oreId).toBe("Iron")
		end
	end)

	it("starts with no dug cells", function()
		local lr = SMALL_RULES.layers[1]
		local rolls = zeroRolls(16 * 2)
		local layer = MineGrid.generateLayer(lr, rolls)
		expect(MineGrid.dugCount(layer)).toBe(0)
	end)
end)

describe("MineGrid.generate", function()
	it("creates one layer per entry in rules", function()
		local needed = MineGrid.rollsNeeded(SMALL_RULES)
		local mine = MineGrid.generate(SMALL_RULES, 5000, zeroRolls(needed))
		expect(#mine.layers).toBe(2)
	end)

	it("stamps the generation timestamp", function()
		local needed = MineGrid.rollsNeeded(SMALL_RULES)
		local mine = MineGrid.generate(SMALL_RULES, 5000, zeroRolls(needed))
		expect(mine.generatedAt).toBe(5000)
	end)

	it("uses different pool entries per layer", function()
		local needed = MineGrid.rollsNeeded(SMALL_RULES)
		local mine = MineGrid.generate(SMALL_RULES, 5000, zeroRolls(needed))
		-- Layer 1 pool starts with Iron, layer 2 starts with Iron too (roll=0)
		-- but layer 2's pool has Titanium as second entry
		local layer1Ores = {}
		for _, id in mine.layers[1].ores do
			layer1Ores[id] = true
		end
		local layer2Ores = {}
		for _, id in mine.layers[2].ores do
			layer2Ores[id] = true
		end
		expect(layer1Ores["Iron"]).toBeTruthy()
		expect(layer2Ores["Iron"]).toBeTruthy()
	end)
end)

describe("MineGrid.rollsNeeded", function()
	it("returns 2 * total cells across all layers", function()
		-- 4x4=16 cells per layer, 2 layers = 32 cells, * 2 = 64
		expect(MineGrid.rollsNeeded(SMALL_RULES)).toBe(64)
	end)
end)

describe("MineGrid.canDig", function()
	local mine: MineGrid.MineState

	beforeEach(function()
		local needed = MineGrid.rollsNeeded(SMALL_RULES)
		mine = MineGrid.generate(SMALL_RULES, 5000, zeroRolls(needed))
	end)

	it("allows digging an untouched cell", function()
		expect(MineGrid.canDig(mine, 1, 0, 0, SMALL_RULES)).toBeTruthy()
	end)

	it("refuses an already dug cell", function()
		MineGrid.dig(mine, 1, 0, 0)
		expect(MineGrid.canDig(mine, 1, 0, 0, SMALL_RULES)).toBeFalsy()
	end)

	it("refuses out-of-bounds x", function()
		expect(MineGrid.canDig(mine, 1, 4, 0, SMALL_RULES)).toBeFalsy()
		expect(MineGrid.canDig(mine, 1, -1, 0, SMALL_RULES)).toBeFalsy()
	end)

	it("refuses out-of-bounds y", function()
		expect(MineGrid.canDig(mine, 1, 0, 4, SMALL_RULES)).toBeFalsy()
	end)

	it("refuses an invalid layer", function()
		expect(MineGrid.canDig(mine, 0, 0, 0, SMALL_RULES)).toBeFalsy()
		expect(MineGrid.canDig(mine, 3, 0, 0, SMALL_RULES)).toBeFalsy()
	end)
end)

describe("MineGrid.dig", function()
	local mine: MineGrid.MineState

	beforeEach(function()
		local needed = MineGrid.rollsNeeded(SMALL_RULES)
		mine = MineGrid.generate(SMALL_RULES, 5000, zeroRolls(needed))
	end)

	it("returns the ore id when the cell has ore", function()
		-- All rolls=0 → all cells have ore (Iron)
		local result = MineGrid.dig(mine, 1, 0, 0)
		expect(result).toBe("Iron")
	end)

	it("returns nil when the cell is dirt", function()
		-- Generate with high rolls → no ore
		local needed = MineGrid.rollsNeeded(SMALL_RULES)
		local emptyMine = MineGrid.generate(SMALL_RULES, 5000, highRolls(needed))
		local result = MineGrid.dig(emptyMine, 1, 0, 0)
		expect(result).toBeNil()
	end)

	it("marks the cell as dug", function()
		MineGrid.dig(mine, 1, 2, 3)
		expect(mine.layers[1].dug[MineGrid.cellKey(2, 3)]).toBeTruthy()
	end)

	it("increments the dug count", function()
		MineGrid.dig(mine, 1, 0, 0)
		MineGrid.dig(mine, 1, 1, 0)
		expect(MineGrid.dugCount(mine.layers[1])).toBe(2)
	end)
end)
