--!strict
-- Rebuilds a station from what was saved to profile.modules -- the "replay
-- a save" path Placement.canPlace's `free` parameter and PlaceModule.
-- luau's own header comment always pointed at, but nothing ever built.
-- Station DATA in this architecture is memory-only (see
-- Ports.StationRepository's header) and gets wiped on every server
-- restart; without this, a player's blueprint only ever existed as unused
-- rows in profile.modules, and their station always came back down to
-- just the core. Ported from legacy StationService:EnsureStation's loop
-- over the saved profile. Called from EmbarkStation, once per session --
-- see SessionRegistry:hasRestored.

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
local ResearchMine = require(fromShared("Domain/Research/ResearchMine"))
local Shovel = require(fromShared("Domain/Research/Shovel"))
local StationProfileSync = require("../StationProfileSync")

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	sceneBuilder: any, -- Ports.SceneBuilder
	gridRules: Grid.Rules,
}

local RestoreStation = {}
RestoreStation.__index = RestoreStation

function RestoreStation:run(userId: number)
	local profile = self.profileRepository:load(userId)
	local station = self.stationRepository:load(userId)
	local saved = StationProfileSync.restore(profile.modules)

	for _, placement in saved do
		-- SceneBuilder:claimPlot already placed the core's Instance AND its
		-- DATA entry (Placement.initial() seeds both station.occupancy and
		-- station.placements with it) -- replaying it here would build a
		-- second, overlapping Instance. But claimPlot always starts it at
		-- level 1, and the core is upgradable like any other module (see
		-- ModuleCatalog.isUpgradable: power > 0), so its LEVEL still needs
		-- restoring even though its existence doesn't.
		if placement.id == "Core" then
			local existing = station.occupancy[Grid.key(placement.x, placement.y)]
			if existing and existing.level ~= placement.level then
				existing.level = placement.level
				self.sceneBuilder:setModuleLevel(userId, placement.x, placement.y, placement.level)
			end
			continue
		end

		local definition = ModuleCatalog.get(placement.id)
		if not definition then
			continue -- a module retired from the catalogue since this was saved
		end

		-- `free`: every one of these was a valid placement once. Corrupted
		-- or overlapping save data is skipped rather than crashing the
		-- whole restore -- one bad row shouldn't cost the rest of a station.
		local check = Placement.canPlace(
			station,
			definition,
			placement.x,
			placement.y,
			placement.rotation,
			self.gridRules,
			true
		)
		if not check.ok then
			continue
		end

		for _, cell in check.value.cells do
			station.occupancy[Grid.key(cell.x, cell.y)] = placement
		end
		table.insert(station.placements, placement)

		self.sceneBuilder:placeModule(userId, placement, definition)
	end

	-- The research extension is derived from the profile, never persisted as
	-- geometry -- exactly like the modules above, and rebuilt on the same
	-- once-per-session path. Without this a player who bought the mine finds
	-- their gangway ending in the void after any server restart.
	if ResearchMine.isUnlocked(profile.unlocked) then
		self.sceneBuilder:buildResearchMine(userId)

		-- Both derived from the profile, never persisted as scene state: the
		-- tool because a Backpack does not survive a server restart, the pad's
		-- colour because the pit was only just rebuilt above and comes back
		-- locked-looking otherwise.
		if Shovel.isUnlocked(profile.unlocked) then
			self.sceneBuilder:grantShovel(userId)
			self.sceneBuilder:markShovelUnlocked(userId)
		end
	end

	self.stationRepository:save(userId, station)
end

return RestoreStation
