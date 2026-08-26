--!strict
-- Load -> validate (Placement.canMove) -> save -> publish scene -- a "clean
-- up your layout" correction, not an economic action: no cost, no refund.
-- Ported from nothing; the legacy game never had a move tool.

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
local Result = require(fromShared("Domain/Support/Result"))
local StationProfileSync = require("../StationProfileSync")

type Result<T, E> = Result.Result<T, E>
type ModulePlacement = Placement.ModulePlacement

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	sceneBuilder: any, -- Ports.SceneBuilder
	gridRules: Grid.Rules,
}

local MoveModule = {}
MoveModule.__index = MoveModule

function MoveModule:run(
	userId: number,
	x: number,
	y: number,
	newX: number,
	newY: number,
	rotation: number?
): Result<ModulePlacement, string>
	local station = self.stationRepository:load(userId)

	-- Quarter-turns, clockwise; NaN and fractions neutralised -- same rule
	-- as PlaceModule.
	local turn = 0
	if typeof(rotation) == "number" and rotation == rotation then
		turn = math.floor(rotation) % 4
	end

	local check = Placement.canMove(station, x, y, newX, newY, turn, self.gridRules)
	if not check.ok then
		return check
	end

	local existing = station.occupancy[Grid.key(x, y)] :: ModulePlacement
	local definition = ModuleCatalog.get(existing.id)
	if not definition then
		return Result.err("unknown module")
	end

	-- Captured before mutating: the scene builder indexes a placed model by
	-- the ANCHOR it was built at, which is about to change.
	local oldX, oldY = existing.x, existing.y
	local oldWidth, oldHeight = ModuleCatalog.sizeOf(definition, existing.rotation)
	for _, cell in Grid.cells(oldX, oldY, oldWidth, oldHeight) do
		station.occupancy[Grid.key(cell.x, cell.y)] = nil
	end

	existing.x = newX
	existing.y = newY
	existing.rotation = turn
	for _, cell in check.value.cells do
		station.occupancy[Grid.key(cell.x, cell.y)] = existing
	end

	local profile = self.profileRepository:load(userId)
	StationProfileSync.apply(profile, station.placements)

	self.stationRepository:save(userId, station)
	self.profileRepository:save(userId, profile)

	-- Rebuilt rather than repositioned in place: the scene builder only ever
	-- indexes a module's Instance by its anchor cell, so a fresh model at the
	-- new anchor keeps that index correct -- same shape as any other
	-- placement, just carrying the same level along.
	self.sceneBuilder:removeModule(userId, oldX, oldY)
	self.sceneBuilder:placeModule(userId, existing, definition)

	return Result.ok(existing)
end

return MoveModule
