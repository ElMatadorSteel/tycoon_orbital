--!strict
-- Load -> validate (Placement) -> refund (Economy) -> save -> publish.
-- Ported from StationService:Remove.

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
type ModulePlacement = Placement.ModulePlacement

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	statsPublisher: any, -- Ports.StatsPublisher
	sceneBuilder: any, -- Ports.SceneBuilder
	refundRatio: number, -- fraction of the base cost refunded
}

local RemoveModule = {}
RemoveModule.__index = RemoveModule

function RemoveModule:run(userId: number, x: number, y: number): Result<ModulePlacement, string>
	local station = self.stationRepository:load(userId)

	local check = Placement.canRemove(station, x, y)
	if not check.ok then
		return check
	end
	local existing = check.value

	local definition = ModuleCatalog.get(existing.id)
	if not definition then
		return Result.err("unknown module")
	end

	local width, height = ModuleCatalog.sizeOf(definition, existing.rotation)
	for _, cell in Grid.cells(existing.x, existing.y, width, height) do
		station.occupancy[Grid.key(cell.x, cell.y)] = nil
	end

	local index = table.find(station.placements, existing)
	if index then
		table.remove(station.placements, index)
	end

	local profile = self.profileRepository:load(userId)
	profile.credits = Credits.add(profile.credits, math.floor(definition.cost * self.refundRatio))
	StationProfileSync.apply(profile, station.placements)

	self.stationRepository:save(userId, station)
	self.profileRepository:save(userId, profile)
	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.sceneBuilder:removeModule(userId, x, y)

	return Result.ok(existing)
end

return RemoveModule
