--!strict
-- One completion predicate per station-based objective -- ported from
-- ObjectiveService's CHECKS. "Embark" is deliberately NOT here: it judges
-- whether the player walked onto their station this session, not anything
-- about the station's contents, so it belongs to session state
-- (Application/SessionRegistry), not to this table. The use case that
-- drives the chain special-cases it, same as the legacy service did
-- ("seul le premier objectif se juge sans station").

local Network = require("../Station/Network")
local Placement = require("../Station/Placement")
local ModuleCatalog = require("../Station/ModuleCatalog")

type Station = Placement.Station
type ModulePlacement = Placement.ModulePlacement

local Checks = {}

local function has(station: Station, id: string): boolean
	for _, placement in station.placements do
		if placement.id == id then
			return true
		end
	end
	return false
end

-- Two modules are in the same network if they both carry and are connected
-- cell-by-cell. The rule isn't redefined here: Network.build owns it.
local function sameNetwork(station: Station, a: string, b: string): boolean
	for _, network in Network.build(station) do
		local foundA, foundB = false, false
		for _, placement in network do
			if placement.id == a then
				foundA = true
			end
			if placement.id == b then
				foundB = true
			end
		end
		if foundA and foundB then
			return true
		end
	end
	return false
end

-- A module that works: it produces, transforms or sells. The core has none
-- of that -- it carries resources without doing anything to them.
local function isWorker(placement: ModulePlacement): boolean
	local definition = ModuleCatalog.get(placement.id)
	return definition ~= nil
		and (definition.input ~= nil or definition.output ~= nil or definition.rate ~= nil)
end

local function networkOf(networks: { { ModulePlacement } }, placement: ModulePlacement): number?
	for index, network in networks do
		if table.find(network, placement) then
			return index
		end
	end
	return nil
end

-- A conduit that WORKS, i.e. actually carries the network -- if it were
-- removed, two modules that were working together would end up split. The
-- nuance matters: a conduit merely stuck onto an already-complete network
-- doesn't clear the objective -- the point isn't to have bought one, it's
-- to have understood what it's for. Networks are compared with and without
-- conduits.
local function workingConduit(station: Station): boolean
	local withConduits = Network.build(station)
	local without = Network.build(station, { Conduit = true })

	for _, network in withConduits do
		local conduits = 0
		local workers = {}
		for _, placement in network do
			if placement.id == "Conduit" then
				conduits += 1
			elseif isWorker(placement) then
				table.insert(workers, placement)
			end
		end

		if conduits > 0 and #workers >= 2 then
			local first = networkOf(without, workers[1])
			for index = 2, #workers do
				if networkOf(without, workers[index]) ~= first then
					return true
				end
			end
		end
	end

	return false
end

-- One condition per station-based objective, keyed by id. An objective
-- missing here deliberately blocks the chain rather than advancing it on
-- its own.
Checks.ById = {
	Collector = function(station: Station): boolean
		return has(station, "OreCollector")
	end,
	Sell = function(station: Station): boolean
		return sameNetwork(station, "OreCollector", "CargoBay")
	end,
	Solar = function(station: Station): boolean
		return has(station, "SolarPanel")
	end,
	Radiator = function(station: Station): boolean
		return has(station, "Radiator")
	end,
	Conduit = function(station: Station): boolean
		return workingConduit(station)
	end,
} :: { [string]: (Station) -> boolean }

return Checks
