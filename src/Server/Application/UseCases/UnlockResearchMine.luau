--!strict
-- One-time unlock: spend credits, flip profile.unlocked.ResearchMine on, and
-- build the extension the pad opens. Triggered by walking onto the pad at
-- the edge of one's own deck -- StationSceneBuilder fires the signal,
-- Composition/Bootstrap connects it to this.
--
-- Shaped on PurchaseRailgun, with one addition: the refusal is visible.
-- Buying the Railgun happens at a prompt the player pressed, so a Result is
-- answer enough; a tycoon pad is something you walk across by accident, and
-- "nothing happened" is indistinguishable from a broken pad unless the pad
-- itself says otherwise.
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

local ResearchMine = require(fromShared("Domain/Research/ResearchMine"))
local Credits = require(fromShared("Domain/Economy/Credits"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	statsPublisher: any, -- Ports.StatsPublisher
	sceneBuilder: any, -- Ports.SceneBuilder
	researchRules: ResearchMine.Rules,
}

local UnlockResearchMine = {}
UnlockResearchMine.__index = UnlockResearchMine

function UnlockResearchMine:run(userId: number): Result<nil, string>
	local profile = self.profileRepository:load(userId)

	-- Standing on an already-open pad. Not a refusal worth showing: the mine
	-- behind it is the answer.
	if ResearchMine.isUnlocked(profile.unlocked) then
		return Result.err("research mine already unlocked")
	end

	local spend = Credits.spend(profile.credits, self.researchRules.cost)
	if not spend.ok then
		self.sceneBuilder:refuseResearchMine(userId)
		return spend
	end

	-- Paid and persisted before anything is built. The geometry is derived
	-- from the profile (RestoreStation rebuilds it on every reconnection),
	-- so a mine that failed to build is a cosmetic loss for one session --
	-- whereas a mine built against a save that never landed is a mine the
	-- player paid for twice.
	profile.credits = spend.value
	profile.unlocked[ResearchMine.UnlockId] = true
	self.profileRepository:save(userId, profile)

	self.sceneBuilder:buildResearchMine(userId)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.statsPublisher:publish(userId, Snapshot.research(true))

	return Result.ok(nil)
end

return UnlockResearchMine
