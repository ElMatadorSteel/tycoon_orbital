--!strict
-- Syncs a station's placements into the profile's saved modules, mirroring
-- legacy StationService:_syncProfile -- called after EVERY change (place,
-- remove, upgrade), not just at save time, so a departing session never has
-- to reconstruct state from a half-destroyed station. Shared by
-- PlaceModule/RemoveModule/UpgradeModule instead of copy-pasted: the field
-- rename (rotation -> r, level -> lv) only needs to be right in one place.

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

local Placement = require(fromShared("Domain/Station/Placement"))
type ModulePlacement = Placement.ModulePlacement

local StationProfileSync = {}

function StationProfileSync.apply(profile: any, placements: { ModulePlacement })
	local modules = table.create(#placements)
	for _, placement in placements do
		table.insert(modules, {
			id = placement.id,
			x = placement.x,
			y = placement.y,
			r = placement.rotation,
			lv = placement.level,
		})
	end
	profile.modules = modules
end

return StationProfileSync
