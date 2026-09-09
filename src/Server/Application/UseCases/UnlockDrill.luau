--!strict
-- One-time purchase: spend credits, flip profile.unlocked.Drill on, set
-- drillLevel to 1, and tell the scene builder to mark the pad. Triggered by
-- walking onto the drill pad at the drill site in the research mine.
--
-- Shaped on UnlockResearchMine / UnlockShovel.

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
local Credits = require(fromShared("Domain/Economy/Credits"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any,
	statsPublisher: any,
	sceneBuilder: any,
	drillRules: Drill.Rules,
}

local UnlockDrill = {}
UnlockDrill.__index = UnlockDrill

function UnlockDrill:run(userId: number): Result<nil, string>
	local profile = self.profileRepository:load(userId)

	if Drill.isUnlocked(profile.unlocked) then
		return Result.err("drill already unlocked")
	end

	local spend = Credits.spend(profile.credits, self.drillRules.cost)
	if not spend.ok then
		self.sceneBuilder:refuseDrill(userId)
		return spend
	end

	profile.credits = spend.value
	profile.unlocked[Drill.UnlockId] = true
	profile.drillLevel = 1
	self.profileRepository:save(userId, profile)

	self.sceneBuilder:markDrillUnlocked(userId)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.statsPublisher:publish(userId, Snapshot.drill(true, 1))

	return Result.ok(nil)
end

return UnlockDrill
