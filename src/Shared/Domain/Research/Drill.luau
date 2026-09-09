--!strict
-- The drill: a one-time purchase that passively mines ores at a rate that
-- scales with its level. Pure -- no Roblox API, no Balance read.
--
-- Iron/Copper/Titanium ores upgrade the drill. Titanium/Iridium/Etherite
-- are reserved for the rocket (a later feature). The drill's own drop table
-- widens as it levels, so higher levels produce rarer ores more often.

export type Rules = {
	cost: number,
	maxLevel: number,
	-- Seconds between each ore production, indexed by level.
	intervals: { number },
	-- Weighted drop pool per level: { { id: string, weight: number } }.
	dropTable: { { { id: string, weight: number } } },
	-- Ore cost to go FROM level N TO level N+1, indexed by current level.
	upgradeCosts: { { [string]: number } },
}

local UNLOCK_ID = "Drill"

local Drill = {}

Drill.UnlockId = UNLOCK_ID

function Drill.isUnlocked(unlocked: { [string]: boolean }): boolean
	return unlocked[UNLOCK_ID] == true
end

function Drill.canUnlock(credits: number, unlocked: { [string]: boolean }, rules: Rules): boolean
	if Drill.isUnlocked(unlocked) then
		return false
	end
	return credits >= rules.cost
end

function Drill.canUpgrade(drillLevel: number, ores: { [string]: number }, rules: Rules): boolean
	if drillLevel >= rules.maxLevel then
		return false
	end
	local cost = rules.upgradeCosts[drillLevel]
	if not cost then
		return false
	end
	for oreId, needed in cost do
		if (ores[oreId] or 0) < needed then
			return false
		end
	end
	return true
end

function Drill.upgradeCost(drillLevel: number, rules: Rules): { [string]: number }?
	if drillLevel >= rules.maxLevel then
		return nil
	end
	return rules.upgradeCosts[drillLevel]
end

-- Seconds between productions at this level.
function Drill.interval(drillLevel: number, rules: Rules): number
	return rules.intervals[math.clamp(drillLevel, 1, #rules.intervals)]
end

-- Pick an ore from the weighted drop table for a given level.
-- `roll` is in [0, 1), as returned by math.random().
function Drill.rollOre(drillLevel: number, rules: Rules, roll: number): string?
	local pool = rules.dropTable[math.clamp(drillLevel, 1, #rules.dropTable)]
	if not pool or #pool == 0 then
		return nil
	end
	local totalWeight = 0
	for _, entry in pool do
		totalWeight += entry.weight
	end
	if totalWeight <= 0 then
		return nil
	end
	local cursor = 0
	for _, entry in pool do
		cursor += entry.weight
		if roll < cursor / totalWeight then
			return entry.id
		end
	end
	-- Rounding: return the last entry.
	return pool[#pool].id
end

return Drill
