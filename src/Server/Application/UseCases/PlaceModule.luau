--!strict
-- Load -> validate (Grid/Placement) -> spend (Economy) -> save -> publish.
-- Ported from StationService:Place, minus building or replicating any
-- Roblox geometry (an Adapter's job, added when the scene-building stage
-- lands) and minus the "free" placement path used to replay a save or drop
-- the starting core (a separate RestoreStation-style use case, not this
-- one).

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
	notifier: any, -- Ports.Notifier
	sceneBuilder: any, -- Ports.SceneBuilder
	gridRules: Grid.Rules,
	capacityPerRadiator: number, -- only used for the "Cooling" gain notification below
}

-- What the module BRINGS, announced on screen -- ported from
-- StationService:_announceGains. Credits themselves go through
-- StatsPublisher as state, not this: this is only for a transient popup.
local function announceGains(
	deps: Dependencies,
	userId: number,
	definition: ModuleCatalog.ModuleDef
)
	if definition.power > 0 then
		deps.notifier:notify(userId, "Power", definition.power)
	end
	if definition.capacity then
		deps.notifier:notify(userId, "Storage", definition.capacity)
	end
	if definition.needsClearance then
		-- The radiator has no negative heat in the catalogue: its dissipation
		-- capacity is a global setting instead.
		deps.notifier:notify(userId, "Cooling", deps.capacityPerRadiator)
	end
end

local PlaceModule = {}
PlaceModule.__index = PlaceModule

function PlaceModule:run(
	userId: number,
	id: string,
	x: number,
	y: number,
	rotation: number?
): Result<ModulePlacement, string>
	local definition = ModuleCatalog.get(id)
	if not definition then
		return Result.err("unknown module")
	end

	-- Quarter-turns, clockwise; NaN and fractions neutralised -- same rule
	-- as the legacy StationService:Place.
	local turn = 0
	if typeof(rotation) == "number" and rotation == rotation then
		turn = math.floor(rotation) % 4
	end

	local station = self.stationRepository:load(userId)
	local check = Placement.canPlace(station, definition, x, y, turn, self.gridRules, false)
	if not check.ok then
		return check
	end

	local profile = self.profileRepository:load(userId)
	local spend = Credits.spend(profile.credits, definition.cost)
	if not spend.ok then
		return spend
	end

	local placement: ModulePlacement = { id = id, x = x, y = y, rotation = turn, level = 1 }
	for _, cell in check.value.cells do
		station.occupancy[Grid.key(cell.x, cell.y)] = placement
	end
	table.insert(station.placements, placement)

	profile.credits = spend.value
	StationProfileSync.apply(profile, station.placements)

	self.stationRepository:save(userId, station)
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.sceneBuilder:placeModule(userId, placement, definition)
	announceGains(self, userId, definition)

	return Result.ok(placement)
end

return PlaceModule
