--!strict
-- One-time unlock per stage: spend credits, flip profile.unlocked.House_<id>,
-- and reveal the corresponding group of parts on the house plateau.
-- Triggered by walking onto the stage's pad -- HouseBuilder fires the signal,
-- Composition/Bootstrap connects it to this.

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

local Credits = require(fromShared("Domain/Economy/Credits"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any,
	statsPublisher: any,
	houseBuilder: any,
	houseStages: { { id: string, name: string, cost: number } },
}

local PurchaseHouseStage = {}
PurchaseHouseStage.__index = PurchaseHouseStage

function PurchaseHouseStage:run(userId: number, stageId: string): Result<nil, string>
	local profile = self.profileRepository:load(userId)

	local unlockKey = "House_" .. stageId
	if profile.unlocked[unlockKey] then
		return Result.err("already owned")
	end

	-- Find the stage config to get its cost
	local cost = nil
	for _, stage in self.houseStages do
		if stage.id == stageId then
			cost = stage.cost
			break
		end
	end
	if not cost then
		return Result.err("unknown stage")
	end

	-- Enforce sequential ordering: all previous stages must be owned
	for _, stage in self.houseStages do
		if stage.id == stageId then
			break
		end
		if not profile.unlocked["House_" .. stage.id] then
			self.houseBuilder:refuse(userId, stageId)
			return Result.err("previous stage not purchased")
		end
	end

	local spend = Credits.spend(profile.credits, cost)
	if not spend.ok then
		self.houseBuilder:refuse(userId, stageId)
		return spend
	end

	profile.credits = spend.value
	profile.unlocked[unlockKey] = true
	self.profileRepository:save(userId, profile)

	self.houseBuilder:unlockStage(userId, stageId)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))

	return Result.ok(nil)
end

return PurchaseHouseStage
