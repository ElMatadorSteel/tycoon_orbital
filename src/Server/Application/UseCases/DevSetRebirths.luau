--!strict
-- Development-only: sets the rebirth count directly to whatever a tester
-- wants, bypassing Rebirth.canRebirth entirely (that gate is the whole
-- point of a dev override) -- with a choice of whether it ALSO resets the
-- station and credits, exactly like a real rebirth (`resetStation = true`),
-- or leaves them untouched so a station built for a specific test stays put
-- while its production boost is tried at a different rebirth count
-- (`resetStation = false`). Never wired outside development mode -- see
-- Composition/Container.luau's `development` flag.

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

local Placement = require(fromShared("Domain/Station/Placement"))
local Rebirth = require(fromShared("Domain/Rebirth/Rebirth"))
local Result = require(fromShared("Domain/Support/Result"))
local StationProfileSync = require("../StationProfileSync")
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	sceneBuilder: any, -- Ports.SceneBuilder
	statsPublisher: any, -- Ports.StatsPublisher
	startingCredits: number,
	rebirthRules: Rebirth.Rules,
}

local DevSetRebirths = {}
DevSetRebirths.__index = DevSetRebirths

function DevSetRebirths:run(
	userId: number,
	count: number,
	resetStation: boolean
): Result<number, string>
	if typeof(count) ~= "number" or count ~= count or count < 0 then
		return Result.err("invalid rebirth count")
	end
	local rebirths = math.floor(count)

	local profile = self.profileRepository:load(userId)

	if resetStation then
		-- Same teardown/rebuild RebirthStation does, just to an EXACT count
		-- instead of +1.
		local station = self.stationRepository:load(userId)
		for _, placement in station.placements do
			if placement.id ~= "Core" then
				self.sceneBuilder:removeModule(userId, placement.x, placement.y)
			end
		end
		self.sceneBuilder:setModuleLevel(userId, -1, -1, 1)

		station = Placement.initial()
		profile.credits = self.startingCredits
		StationProfileSync.apply(profile, station.placements)
		self.stationRepository:save(userId, station)
		self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	end

	profile.rebirths = rebirths
	self.profileRepository:save(userId, profile)

	local hasUltimate = profile.unlocked[Rebirth.Passes.Ultimate] == true
	local hasEarlyPass = profile.unlocked[Rebirth.Passes.EarlyRebirth] == true
	local boost = Rebirth.multiplier(rebirths, hasUltimate, self.rebirthRules)
	self.statsPublisher:publish(
		userId,
		Snapshot.rebirth(rebirths, hasUltimate, hasEarlyPass, boost)
	)

	return Result.ok(rebirths)
end

return DevSetRebirths
