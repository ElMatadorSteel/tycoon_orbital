--!strict
-- One-time unlock: spend credits, flip profile.unlocked.Shovel on, and put
-- the tool in the player's hands. Triggered by walking onto the pad on the
-- rim terrace of one's own mine -- StationSceneBuilder fires the signal,
-- Composition/Bootstrap connects it to this.
--
-- Shaped on UnlockResearchMine, down to the visible refusal: a tycoon pad is
-- something you walk across by accident, and "nothing happened" is
-- indistinguishable from a broken pad unless the pad itself says otherwise.

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

local Shovel = require(fromShared("Domain/Research/Shovel"))
local ResearchMine = require(fromShared("Domain/Research/ResearchMine"))
local Credits = require(fromShared("Domain/Economy/Credits"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	statsPublisher: any, -- Ports.StatsPublisher
	sceneBuilder: any, -- Ports.SceneBuilder
	shovelRules: Shovel.Rules,
}

local UnlockShovel = {}
UnlockShovel.__index = UnlockShovel

function UnlockShovel:run(userId: number): Result<nil, string>
	local profile = self.profileRepository:load(userId)

	-- The pad is built with the mine and stands inside it, so reaching it
	-- already implies this. Checked anyway: geometry is not a permission
	-- system, and a use case that trusts one is a use case that breaks the
	-- day something else calls it.
	if not ResearchMine.isUnlocked(profile.unlocked) then
		return Result.err("research mine not unlocked")
	end

	if Shovel.isUnlocked(profile.unlocked) then
		-- Standing on an already-bought pad. Not a refusal worth showing --
		-- but the tool may be missing (a fresh server, an empty Backpack), so
		-- hand it over again before saying no. grantShovel is idempotent.
		self.sceneBuilder:grantShovel(userId)
		return Result.err("shovel already owned")
	end

	local spend = Credits.spend(profile.credits, self.shovelRules.cost)
	if not spend.ok then
		self.sceneBuilder:refuseShovel(userId)
		return spend
	end

	-- Paid and persisted before the tool is handed over, same order as the
	-- mine's own unlock: the profile is the authority and the tool is derived
	-- from it (RestoreStation re-grants on every reconnection), so a grant
	-- that failed costs one session -- a grant against a save that never
	-- landed is a shovel the player buys twice.
	profile.credits = spend.value
	profile.unlocked[Shovel.UnlockId] = true
	self.profileRepository:save(userId, profile)

	self.sceneBuilder:grantShovel(userId)
	self.sceneBuilder:markShovelUnlocked(userId)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.statsPublisher:publish(userId, Snapshot.shovel(true))

	return Result.ok(nil)
end

return UnlockShovel
