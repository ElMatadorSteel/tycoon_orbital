--!strict
-- Development-only: resets EVERYTHING for this player back to exactly what
-- a brand new join looks like -- station, credits, rebirths, both paid
-- passes, objective progress. Unlike RebirthStation/DevSetRebirths, this
-- also clears profile.unlocked and profile.objective: those are a real
-- rebirth's business to leave alone (a rebirth doesn't revoke a purchase or
-- replay the onboarding chain), but "as if freshly joined" means genuinely
-- everything. `Profile.blank(rules)` already IS that exact shape (see its
-- own header -- it's what a never-before-seen userId gets), so this reuses
-- it rather than hand-duplicating the reset fields. Never wired outside
-- development mode -- see Composition/Container.luau's `development` flag.

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

local Profile = require(fromShared("Domain/Profile/Profile"))
local Placement = require(fromShared("Domain/Station/Placement"))
local Result = require(fromShared("Domain/Support/Result"))
local StationProfileSync = require("../StationProfileSync")
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	sceneBuilder: any, -- Ports.SceneBuilder
	statsPublisher: any, -- Ports.StatsPublisher
	profileRules: Profile.Rules,
}

local DevResetAll = {}
DevResetAll.__index = DevResetAll

function DevResetAll:run(userId: number): Result<nil, string>
	local station = self.stationRepository:load(userId)
	for _, placement in station.placements do
		if placement.id ~= "Core" then
			self.sceneBuilder:removeModule(userId, placement.x, placement.y)
		end
	end
	self.sceneBuilder:setModuleLevel(userId, -1, -1, 1)

	station = Placement.initial()
	local profile = Profile.blank(self.profileRules)
	StationProfileSync.apply(profile, station.placements)

	self.stationRepository:save(userId, station)
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.statsPublisher:publish(userId, Snapshot.objective(profile.objective))
	self.statsPublisher:publish(userId, Snapshot.rebirth(0, false, false, 1))

	return Result.ok(nil)
end

return DevResetAll
