--!strict
-- Dig a single block in the research mine grid. If the block contains ore
-- and the backpack is not full, the ore is added to profile.ores.
-- Returns what was found (ore or dirt) so the client can show feedback.
--
-- The mine grid is persisted in profile.mine and regenerated every
-- Balance.Research.RegenInterval seconds. If the grid is stale or missing,
-- this use case generates a fresh one before digging.

local function fromShared(path: string): any
	if game then
		local node: any = (game :: any):GetService("ReplicatedStorage").Shared
		for segment in path:gmatch("[^/]+") do
			node = node[segment]
		end
		return node
	end
	return "../../../Shared/" .. path
end

local Backpack = require(fromShared("Domain/Research/Backpack"))
local MineGrid = require(fromShared("Domain/Research/MineGrid"))
local OreCatalog = require(fromShared("Domain/Research/OreCatalog"))
local ResearchMine = require(fromShared("Domain/Research/ResearchMine"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any,
	statsPublisher: any,
	clock: any,
	sessionRegistry: any,
	sceneBuilder: any, -- Ports.SceneBuilder
	gridRules: MineGrid.Rules,
	backpackCapacity: number,
	digCooldown: number,
	-- Injected by the container so Domain stays pure: the use case calls
	-- this to get random numbers for grid generation. Returns [0, 1).
	random: () -> number,
}

export type DigResult = {
	oreId: string?, -- nil if dirt
	oreName: string?, -- nil if dirt
	rarity: string?, -- nil if dirt
	newCount: number?, -- new count of that ore in the bag, nil if dirt
	bagFull: boolean,
}

local DigBlock = {}
DigBlock.__index = DigBlock

-- Ensure the mine grid exists and is fresh. Returns the (possibly new) grid.
function DigBlock:_ensureGrid(profile: any, now: number): any
	local mine = profile.mine
	if
		mine and not MineGrid.shouldRegenerate(mine.generatedAt, now, self.gridRules.regenInterval)
	then
		-- Check layer count matches rules (config may have changed)
		if #mine.layers == #self.gridRules.layers then
			return mine
		end
	end
	-- Generate a fresh grid
	local needed = MineGrid.rollsNeeded(self.gridRules)
	local rolls = {}
	for i = 1, needed do
		rolls[i] = self.random()
	end
	local newMine = MineGrid.generate(self.gridRules, now, rolls)
	profile.mine = newMine
	return newMine
end

function DigBlock:run(
	userId: number,
	layer: number,
	x: number,
	y: number
): Result<DigResult, string>
	-- Type-check network input
	if typeof(layer) ~= "number" or typeof(x) ~= "number" or typeof(y) ~= "number" then
		return Result.err("invalid coordinates")
	end
	layer = math.floor(layer)
	x = math.floor(x)
	y = math.floor(y)

	local profile = self.profileRepository:load(userId)
	if not ResearchMine.isUnlocked(profile.unlocked) then
		return Result.err("mine not unlocked")
	end

	-- Dig cooldown (global, not per-block)
	local now = self.clock:monotonic()
	local lastDig = self.sessionRegistry:lastDig(userId)
	if lastDig > 0 and (now - lastDig) < self.digCooldown then
		return Result.err("cooldown")
	end

	local epochNow = self.clock:now()
	local mine = self:_ensureGrid(profile, epochNow)

	if not MineGrid.canDig(mine, layer, x, y, self.gridRules) then
		return Result.err("cannot dig here")
	end

	local oreId = MineGrid.dig(mine, layer, x, y)
	self.sessionRegistry:setLastDig(userId, now)
	self.sceneBuilder:removeMineBlock(userId, layer, x, y)

	local result: DigResult = { bagFull = Backpack.isFull(profile.ores, self.backpackCapacity) }

	if oreId then
		local ore = OreCatalog.get(oreId)
		if ore and not result.bagFull then
			local count = (profile.ores[oreId] or 0) + 1
			profile.ores[oreId] = count
			result.oreId = oreId
			result.oreName = ore.name
			result.rarity = ore.rarity
			result.newCount = count
			result.bagFull = Backpack.isFull(profile.ores, self.backpackCapacity)
			self.statsPublisher:publish(userId, Snapshot.ore(oreId, count))
		elseif ore and result.bagFull then
			-- Ore found but bag is full: the block is consumed (dug) but
			-- the ore is lost. This is intentional: you see it but can't
			-- pick it up, creating pressure to sell.
			result.oreId = oreId
			result.oreName = ore.name
			result.rarity = ore.rarity
		end
	end

	self.profileRepository:save(userId, profile)

	return Result.ok(result)
end

return DigBlock
