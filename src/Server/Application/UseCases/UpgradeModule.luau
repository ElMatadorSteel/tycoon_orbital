--!strict
-- Load -> validate -> pay (Economy) -> save -> publish. Ported from
-- StationService:Upgrade -- the server stays sole judge: it checks the
-- module exists, has something to upgrade, isn't already at the cap, and
-- that the player can pay.

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

local Grid = require(fromShared("Domain/Grid/Grid"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local Placement = require(fromShared("Domain/Station/Placement"))
local Credits = require(fromShared("Domain/Economy/Credits"))
local Result = require(fromShared("Domain/Support/Result"))
local StationProfileSync = require("../StationProfileSync")
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>
type UpgradeRules = ModuleCatalog.UpgradeRules

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	statsPublisher: any, -- Ports.StatsPublisher
	sceneBuilder: any, -- Ports.SceneBuilder
	upgradeRules: UpgradeRules,
}

local UpgradeModule = {}
UpgradeModule.__index = UpgradeModule

function UpgradeModule:run(userId: number, x: number, y: number): Result<number, string>
	local station = self.stationRepository:load(userId)

	local existing = station.occupancy[Grid.key(x, y)]
	if not existing then
		return Result.err("no module here")
	end

	local definition = ModuleCatalog.get(existing.id)
	if not definition then
		return Result.err("unknown module")
	end
	if not ModuleCatalog.isUpgradable(definition) then
		return Result.err("nothing to upgrade")
	end
	if existing.level >= self.upgradeRules.maxLevel then
		return Result.err("already at maximum level")
	end
	-- The core paces every other module: nothing may be upgraded past
	-- whatever level the core is CURRENTLY at (the core itself is exempt --
	-- it has nothing to be capped against).
	if existing.id ~= "Core" and existing.level >= Placement.coreLevel(station) then
		return Result.err("cannot exceed the core's level")
	end

	local cost = ModuleCatalog.upgradeCost(definition, existing.level, self.upgradeRules)

	local profile = self.profileRepository:load(userId)
	local spend = Credits.spend(profile.credits, cost)
	if not spend.ok then
		return spend
	end

	existing.level += 1
	profile.credits = spend.value
	-- existing.level was mutated in place, but profile.modules holds a
	-- SNAPSHOT copy made when the module was placed (see PlaceModule) --
	-- without re-syncing here, the new level would vanish on the next save.
	StationProfileSync.apply(profile, station.placements)

	self.stationRepository:save(userId, station)
	self.profileRepository:save(userId, profile)
	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.sceneBuilder:setModuleLevel(userId, x, y, existing.level)

	return Result.ok(existing.level)
end

return UpgradeModule
