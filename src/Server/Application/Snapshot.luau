--!strict
-- The presentation model sent to the client -- one builder per concern,
-- rather than one monolithic table. Attributes replicate independently
-- (SetAttribute on one key never touches another), so a use case only ever
-- publishes the handful of fields it actually just changed; this file's
-- job is just to be the one place their NAMES and shapes are decided, so
-- they can't drift between use cases (a typo'd "Credits" vs "credits" in
-- two different files would silently desync the client).
--
-- Everything returned is attribute-compatible: numbers, strings, booleans
-- only -- no nested tables, no Roblox datatypes (see CLAUDE.md's "no Roblox
-- datatypes in Domain/Config", which applies here for the same reason:
-- these tables are handed to Ports.StatsPublisher, whose test double is
-- Roblox-free). The station's own module list is NOT part of this: once
-- placed modules are real Instances (the 3D-building stage), they replicate
-- to the client for free through ordinary Roblox instance replication --
-- there is nothing to snapshot there.

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
	return "../../Shared/" .. path
end

local Simulation = require(fromShared("Domain/Production/Simulation"))

export type CreditsSnapshot = { Credits: number }
export type ObjectiveSnapshot = { Objective: number }
export type LocationSnapshot = { Location: string }
export type RebirthSnapshot = {
	Rebirths: number,
	HasUltimate: boolean,
	HasEarlyRebirth: boolean,
	GlobalBoost: number,
}
export type MiningSnapshot = { HasRailgun: boolean }
export type ResearchSnapshot = { HasResearchMine: boolean }
export type OreSnapshot = { [string]: number }
export type ShovelSnapshot = { HasShovel: boolean }
export type ProductionSnapshot = {
	Sunlight: number,
	Efficiency: number,
	PowerProduction: number,
	PowerConsumption: number,
	PowerCharge: number,
	PowerStorage: number,
	HeatLoad: number,
	HeatCapacity: number,
	Income: number,
	-- The orbital countdown. Published as a duration rather than as a deadline:
	-- an absolute time would need the client and the server to agree on a clock,
	-- and they do not. The client counts this one down locally between ticks.
	EclipseIn: number,
	InEclipse: boolean,
}

local Snapshot = {}

function Snapshot.credits(amount: number): CreditsSnapshot
	return { Credits = amount }
end

function Snapshot.objective(index: number): ObjectiveSnapshot
	return { Objective = index }
end

-- "Lobby" or "Station" -- matches the legacy LocationChanged payload, which
-- gates whether the client shows build/HUD UI at all.
function Snapshot.location(value: string): LocationSnapshot
	return { Location = value }
end

-- globalBoost is passed in already computed (Rebirth.multiplier), not
-- recomputed here: this file only names shapes, it doesn't own rules.
function Snapshot.rebirth(
	rebirths: number,
	hasUltimate: boolean,
	hasEarlyRebirth: boolean,
	globalBoost: number
): RebirthSnapshot
	return {
		Rebirths = rebirths,
		HasUltimate = hasUltimate,
		HasEarlyRebirth = hasEarlyRebirth,
		GlobalBoost = globalBoost,
	}
end

function Snapshot.mining(hasRailgun: boolean): MiningSnapshot
	return { HasRailgun = hasRailgun }
end

function Snapshot.research(hasResearchMine: boolean): ResearchSnapshot
	return { HasResearchMine = hasResearchMine }
end

-- ONE ORE PER CALL, not the whole bag in one table. Attributes are flat --
-- numbers, strings and booleans only (see this file's header) -- so an
-- inventory has to replicate as one attribute per line rather than as a
-- nested table. "Ore" prefixes the id so a mineral can never collide with a
-- field like Credits, and so the client can derive the attribute name from
-- the catalogue instead of keeping a second list in step with this one.
function Snapshot.ore(oreId: string, count: number): OreSnapshot
	return { [`Ore{oreId}`] = count }
end

function Snapshot.shovel(hasShovel: boolean): ShovelSnapshot
	return { HasShovel = hasShovel }
end

function Snapshot.production(stats: {
	sunlight: number,
	efficiency: number,
	power: Simulation.PowerStats,
	heat: Simulation.HeatStats,
	income: number,
	eclipseIn: number,
	inEclipse: boolean,
}): ProductionSnapshot
	return {
		Sunlight = stats.sunlight,
		Efficiency = stats.efficiency,
		PowerProduction = stats.power.production,
		PowerConsumption = stats.power.consumption,
		PowerCharge = stats.power.charge,
		PowerStorage = stats.power.storage,
		HeatLoad = stats.heat.load,
		HeatCapacity = stats.heat.capacity,
		Income = stats.income,
		EclipseIn = stats.eclipseIn,
		InEclipse = stats.inEclipse,
	}
end

return Snapshot
