--!strict
-- The mining grid: layers of blocks that can be dirt or ore, generated
-- randomly per layer with depth-dependent ore distribution.
--
-- A layer is a flat width x depth rectangle of cells. Each cell is either
-- nil (dirt, no ore) or an ore id string. The grid is generated once and
-- persisted; only regenerated after `regenInterval` seconds.
--
-- Pure: no Roblox API, no Balance require, everything comes in as rules.

export type LayerRules = {
	-- How many cells wide and deep this layer is.
	width: number,
	depth: number,
	-- Fraction of cells that contain ore (0..1).
	density: number,
	-- Weighted ore pool for this layer: { { id = "Iron", weight = 60 }, ... }
	pool: { { id: string, weight: number } },
}

export type Rules = {
	layers: { LayerRules },
	regenInterval: number, -- seconds between full regenerations
}

-- A single layer's state: which cells have ore and which are dug.
-- `ores` is keyed by "x,y" → ore id (only cells WITH ore).
-- `dug` is keyed by "x,y" → true (cells already broken by the player).
export type LayerState = {
	ores: { [string]: string },
	dug: { [string]: boolean },
}

export type MineState = {
	generatedAt: number, -- epoch timestamp of last generation
	layers: { LayerState },
}

local MineGrid = {}

function MineGrid.cellKey(x: number, y: number): string
	return `{x},{y}`
end

function MineGrid.parseCellKey(key: string): (number?, number?)
	local xs, ys = key:match("^(-?%d+),(-?%d+)$")
	if not xs or not ys then
		return nil, nil
	end
	return tonumber(xs), tonumber(ys)
end

-- Whether the whole mine should be regenerated based on time elapsed.
function MineGrid.shouldRegenerate(generatedAt: number, now: number, regenInterval: number): boolean
	return now - generatedAt >= regenInterval
end

-- Pick an ore id from a weighted pool. `roll` is in [0, 1).
function MineGrid.pickOre(pool: { { id: string, weight: number } }, roll: number): string
	local totalWeight = 0
	for _, entry in pool do
		totalWeight += entry.weight
	end

	local threshold = roll * totalWeight
	local cumulative = 0
	for _, entry in pool do
		cumulative += entry.weight
		if threshold < cumulative then
			return entry.id
		end
	end
	-- Fallback: last entry (floating-point edge case)
	return pool[#pool].id
end

-- Generate a single layer's ore placement. `rolls` is a flat array of
-- random numbers in [0, 1), one per cell (width * depth of them), used
-- in two passes: the first pass decides ore-or-dirt, the second picks
-- which ore. This makes the function pure and deterministic for a given
-- roll sequence, which is what makes it testable.
function MineGrid.generateLayer(layerRules: LayerRules, rolls: { number }): LayerState
	local ores: { [string]: string } = {}
	local cellCount = layerRules.width * layerRules.depth
	-- rolls layout: [1..cellCount] = density rolls, [cellCount+1..2*cellCount] = ore-pick rolls
	for i = 1, cellCount do
		if rolls[i] < layerRules.density then
			local x = (i - 1) % layerRules.width
			local y = math.floor((i - 1) / layerRules.width)
			local key = MineGrid.cellKey(x, y)
			local pickRoll = rolls[cellCount + i]
			ores[key] = MineGrid.pickOre(layerRules.pool, pickRoll)
		end
	end
	return { ores = ores, dug = {} }
end

-- Generate the full mine state from rules and a flat array of rolls.
-- The caller (Application) supplies the random numbers; Domain stays pure.
function MineGrid.generate(rules: Rules, now: number, allRolls: { number }): MineState
	local layers: { LayerState } = {}
	local offset = 0
	for i, layerRules in rules.layers do
		local cellCount = layerRules.width * layerRules.depth
		local rollsNeeded = cellCount * 2 -- density + ore pick
		local layerRolls = {}
		for j = 1, rollsNeeded do
			layerRolls[j] = allRolls[offset + j]
		end
		offset += rollsNeeded
		layers[i] = MineGrid.generateLayer(layerRules, layerRolls)
	end
	return { generatedAt = now, layers = layers }
end

-- How many rolls MineGrid.generate needs for the given rules.
function MineGrid.rollsNeeded(rules: Rules): number
	local total = 0
	for _, layerRules in rules.layers do
		total += layerRules.width * layerRules.depth * 2
	end
	return total
end

-- Whether a cell can be dug: it exists, is in bounds, and hasn't been dug yet.
function MineGrid.canDig(
	mine: MineState,
	layer: number,
	x: number,
	y: number,
	rules: Rules
): boolean
	if layer < 1 or layer > #mine.layers then
		return false
	end
	local lr = rules.layers[layer]
	if x < 0 or x >= lr.width or y < 0 or y >= lr.depth then
		return false
	end
	local key = MineGrid.cellKey(x, y)
	if mine.layers[layer].dug[key] then
		return false
	end
	return true
end

-- Dig a cell. Returns the ore id found (or nil for dirt). Marks the cell
-- as dug. The caller must persist the mine state after this.
function MineGrid.dig(mine: MineState, layer: number, x: number, y: number): string?
	local key = MineGrid.cellKey(x, y)
	local layerState = mine.layers[layer]
	layerState.dug[key] = true
	return layerState.ores[key]
end

-- Count how many cells in a layer have been dug.
function MineGrid.dugCount(layerState: LayerState): number
	local count = 0
	for _ in layerState.dug do
		count += 1
	end
	return count
end

-- Count how many ore cells exist in a layer (total, not remaining).
function MineGrid.oreCount(layerState: LayerState): number
	local count = 0
	for _ in layerState.ores do
		count += 1
	end
	return count
end

return MineGrid
