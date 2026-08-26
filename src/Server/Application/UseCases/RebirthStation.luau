--!strict
-- The prestige action: once the core has reached the required level (see
-- Domain/Rebirth/Rebirth.luau -- lower with the paid EarlyRebirth pass),
-- reset the station AND the credits back to their starting state, in
-- exchange for a permanent, stacking production boost. Every future
-- RunProductionTick call picks the new bonus up automatically through
-- Rebirth.multiplier(profile.rebirths, ...) -- there is nothing else to
-- wire per rebirth.

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

local RebirthStation = {}
RebirthStation.__index = RebirthStation

function RebirthStation:run(userId: number): Result<number, string>
	local station = self.stationRepository:load(userId)
	local profile = self.profileRepository:load(userId)

	local coreLevel = Placement.coreLevel(station)
	local hasEarlyPass = profile.unlocked[Rebirth.Passes.EarlyRebirth] == true
	if not Rebirth.canRebirth(coreLevel, hasEarlyPass, self.rebirthRules) then
		return Result.err("not eligible for rebirth yet")
	end

	-- Tear down every placed module except the core -- claimPlot already
	-- built its Instance and this never touches that, same as RestoreStation
	-- never replaying it. The core's LEVEL still resets, mirroring how
	-- RestoreStation resyncs it rather than leaving it alone.
	for _, placement in station.placements do
		if placement.id ~= "Core" then
			self.sceneBuilder:removeModule(userId, placement.x, placement.y)
		end
	end
	self.sceneBuilder:setModuleLevel(userId, -1, -1, 1)

	station = Placement.initial()
	profile.credits = self.startingCredits
	profile.rebirths += 1
	StationProfileSync.apply(profile, station.placements)

	self.stationRepository:save(userId, station)
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	local hasUltimate = profile.unlocked[Rebirth.Passes.Ultimate] == true
	local boost = Rebirth.multiplier(profile.rebirths, hasUltimate, self.rebirthRules)
	self.statsPublisher:publish(
		userId,
		Snapshot.rebirth(profile.rebirths, hasUltimate, hasEarlyPass, boost)
	)

	return Result.ok(profile.rebirths)
end

return RebirthStation
