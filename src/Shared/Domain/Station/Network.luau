--!strict
-- Resource-network connectivity -- ported from the legacy ProductionService's
-- buildNetworks/:Networks. Shared by Production (what flows where) and
-- Objectives (whether a conduit is actually bridging two workers), so it
-- lives with the other Station rules rather than under Production alone.

local Grid = require("../Grid/Grid")
local ModuleCatalog = require("./ModuleCatalog")
local Placement = require("./Placement")

type Station = Placement.Station
type ModulePlacement = Placement.ModulePlacement

local Network = {}

-- Two adjacent modules are connected only if both carry -- a corridor
-- carries nothing, so it never bridges a network. `skip`: pretend these ids
-- carry nothing, used to check whether a conduit is the thing actually
-- holding two otherwise-disconnected workers together.
function Network.build(station: Station, skip: { [string]: boolean }?): { { ModulePlacement } }
	local seen: { [ModulePlacement]: boolean } = {}
	local networks: { { ModulePlacement } } = {}

	local function carries(placement: ModulePlacement): boolean
		if skip and skip[placement.id] then
			return false
		end
		local definition = ModuleCatalog.get(placement.id)
		return definition ~= nil and definition.carries == true
	end

	local function cellsOf(placement: ModulePlacement)
		local definition = ModuleCatalog.get(placement.id)
		if not definition then
			return {}
		end
		local width, height = ModuleCatalog.sizeOf(definition, placement.rotation)
		return Grid.cells(placement.x, placement.y, width, height)
	end

	for _, placement in station.placements do
		if not carries(placement) or seen[placement] then
			continue
		end

		local network: { ModulePlacement } = {}
		local queue: { ModulePlacement } = { placement }
		seen[placement] = true

		while #queue > 0 do
			local current = table.remove(queue) :: ModulePlacement
			table.insert(network, current)

			for _, cell in cellsOf(current) do
				for _, neighbour in Grid.neighbours(cell.x, cell.y) do
					local other = station.occupancy[Grid.key(neighbour.x, neighbour.y)]
					if not other or seen[other] then
						continue
					end
					if carries(other) then
						seen[other] = true
						table.insert(queue, other)
					end
				end
			end
		end

		table.insert(networks, network)
	end

	return networks
end

return Network
