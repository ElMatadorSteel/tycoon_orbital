--!strict
-- Spend ores to level up the drill. Only Iron/Copper/Titanium are used
-- for drill upgrades; rarer ores are reserved for the rocket.
--
-- Triggered by the client's upgrade button in the research panel.

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

local Drill = require(fromShared("Domain/Research/Drill"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any,
	statsPublisher: any,
	drillRules: Drill.Rules,
}

local UpgradeDrill = {}
UpgradeDrill.__index = UpgradeDrill

function UpgradeDrill:run(userId: number): Result<number, string>
	local profile = self.profileRepository:load(userId)

	if not Drill.isUnlocked(profile.unlocked) then
		return Result.err("drill not unlocked")
	end

	local level = profile.drillLevel or 1
	if not Drill.canUpgrade(level, profile.ores, self.drillRules) then
		return Result.err("cannot upgrade drill")
	end

	local cost = Drill.upgradeCost(level, self.drillRules)
	if not cost then
		return Result.err("already at max level")
	end

	-- Deduct ores.
	for oreId, needed in cost do
		profile.ores[oreId] = (profile.ores[oreId] or 0) - needed
		if profile.ores[oreId] <= 0 then
			profile.ores[oreId] = nil
		end
	end

	profile.drillLevel = level + 1
	self.profileRepository:save(userId, profile)

	-- Publish updated ore counts and drill level.
	for oreId in cost do
		self.statsPublisher:publish(userId, Snapshot.ore(oreId, profile.ores[oreId] or 0))
	end
	self.statsPublisher:publish(userId, Snapshot.drill(true, profile.drillLevel))

	return Result.ok(profile.drillLevel)
end

return UpgradeDrill
