--!strict
-- One-time unlock: spend credits, flip profile.unlocked.ResearchMine on,
-- open the zone. Same load -> validate -> spend -> save -> publish shape as
-- PurchaseRailgun, which this deliberately mirrors -- the one addition is
-- telling the scene builder to actually open the pit (or flash the pad red
-- on a refusal), since unlike the Railgun there is no separate dispenser
-- step: unlocking IS receiving the thing.
--
-- Triggered by StationSceneBuilder's researchPadTouched Signal (see
-- Composition/Bootstrap.luau), not by a RemoteFunction: the pad is a walk-
-- onto trigger, same as the legacy LaunchPad, not a client-initiated
-- purchase like the Railgun's pad -- there is no player-facing failure
-- message to show beyond the pad itself flashing red.

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Server and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach -- confirmed the first time
-- Rojo actually connected Studio (see CLAUDE.md's cutover notes). Lune has
-- no `game`, so the fallback below -- an ordinary relative require -- is
-- what actually runs there, unchanged from before.
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

	if ResearchMine.isUnlocked(profile.unlocked) then
		self.sceneBuilder:refuseResearchMine(userId)
		return Result.err("recherche déjà débloquée")
	end

	local spend = Credits.spend(profile.credits, self.researchRules.cost)
	if not spend.ok then
		self.sceneBuilder:refuseResearchMine(userId)
		return spend
	end

	profile.credits = spend.value
	profile.unlocked[ResearchMine.UnlockId] = true
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.statsPublisher:publish(userId, Snapshot.research(true))
	self.sceneBuilder:buildResearchMine(userId)

	return Result.ok(nil)
end

return UnlockResearchMine
