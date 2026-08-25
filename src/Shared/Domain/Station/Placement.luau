--!strict
-- Placement/removal validation rules -- ported from the legacy
-- StationService:Place/:Remove, minus the credit cost check (Economy's
-- job) and minus building or replicating anything (Adapters'/Application's
-- job). The server is the sole authority: the client only ever sends an
-- intention, this is what judges it.

local Grid = require("../Grid/Grid")
local ModuleCatalog = require("./ModuleCatalog")
local Result = require("../Support/Result")

type Cell = Grid.Cell
type Result<T, E> = Result.Result<T, E>
type ModuleDef = ModuleCatalog.ModuleDef

export type ModulePlacement = { id: string, x: number, y: number, rotation: number, level: number }
export type Occupancy = { [string]: ModulePlacement } -- keyed by Grid.key(x, y)

export type Station = {
	occupancy: Occupancy,
	placements: { ModulePlacement },
}

local Placement = {}

function Placement.cellsFree(occupancy: Occupancy, cells: { Grid.Cell }): boolean
	for _, cell in cells do
		if occupancy[Grid.key(cell.x, cell.y)] then
			return false
		end
	end
	return true
end

-- A module must touch the existing station: no floating piece.
function Placement.touchesStation(occupancy: Occupancy, cells: { Grid.Cell }): boolean
	for _, cell in cells do
		for _, neighbour in Grid.neighbours(cell.x, cell.y) do
			if occupancy[Grid.key(neighbour.x, neighbour.y)] then
				return true
			end
		end
	end
	return false
end

function Placement.hasModule(placements: { ModulePlacement }, id: string): boolean
	for _, placement in placements do
		if placement.id == id then
			return true
		end
	end
	return false
end

export type PlacementCheck = { width: number, height: number, cells: { Cell } }

-- `free`: skips the touches-station and uniqueness checks. Reserved for
-- replaying a save and for the starting core.
function Placement.canPlace(
	station: Station,
	definition: ModuleDef,
	x: number,
	y: number,
	rotation: number,
	gridRules: Grid.Rules,
	free: boolean?
): Result<PlacementCheck, string>
	local width, height = ModuleCatalog.sizeOf(definition, rotation)

	if not Grid.isInBounds(x, y, width, height, gridRules) then
		return Result.err("out of bounds")
	end

	local cells = Grid.cells(x, y, width, height)
	if not Placement.cellsFree(station.occupancy, cells) then
		return Result.err("cell already occupied")
	end

	if
		definition.unique
		and not free
		and Placement.hasModule(station.placements, definition.id)
	then
		return Result.err("only one of this module per station")
	end

	if not free and not Placement.touchesStation(station.occupancy, cells) then
		return Result.err("must touch the station")
	end

	return Result.ok({ width = width, height = height, cells = cells })
end

function Placement.canRemove(
	station: Station,
	x: number,
	y: number
): Result<ModulePlacement, string>
	local existing = station.occupancy[Grid.key(x, y)]
	if not existing then
		return Result.err("no module here")
	end
	local definition = ModuleCatalog.get(existing.id)
	if definition and definition.unique then
		return Result.err("cannot be demolished")
	end
	return Result.ok(existing)
end

-- A station always starts with its core already placed, centred on the
-- grid origin (a 2x2 module anchored at -1,-1) -- ported from the "free"
-- placement StationService:EnsureStation makes before anything else.
function Placement.initial(): Station
	local core = ModuleCatalog.get("Core")
	assert(core, "ModuleCatalog is missing the Core module")
	local width, height = ModuleCatalog.sizeOf(core, 0)
	local placement: ModulePlacement = { id = "Core", x = -1, y = -1, rotation = 0, level = 1 }

	local occupancy: Occupancy = {}
	for _, cell in Grid.cells(-1, -1, width, height) do
		occupancy[Grid.key(cell.x, cell.y)] = placement
	end

	return { occupancy = occupancy, placements = { placement } }
end

return Placement
