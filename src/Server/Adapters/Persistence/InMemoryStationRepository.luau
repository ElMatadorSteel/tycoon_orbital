--!strict
-- Session-only station state -- Roblox-free, same as
-- InMemoryProfileRepository, and for the same reason: real per-player
-- station state does not live in Studio's Play mode outside a running
-- server anyway, and this doubles as the test fake. A real running game
-- will eventually want this backed by something that survives a script
-- reload without dropping build state mid-session, but that is scene/
-- Adapter work for a later stage, not a Domain/Application concern.

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Server and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach -- confirmed the first time
-- Rojo actually connected Studio (see CLAUDE.md's cutover notes). Lune has
-- no `game`, so the fallback below -- an ordinary relative require -- is
-- what actually runs there, unchanged from before. Doesn't compromise this
-- file's Roblox-freeness above: the branch below never runs under Lune.
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

local Placement = require(fromShared("Domain/Station/Placement"))
type Station = Placement.Station

local InMemoryStationRepository = {}
InMemoryStationRepository.__index = InMemoryStationRepository

function InMemoryStationRepository.new()
	return setmetatable({
		_stations = {} :: { [number]: Station },
	}, InMemoryStationRepository)
end

function InMemoryStationRepository:load(userId: number): Station
	local existing = self._stations[userId]
	if existing then
		return existing
	end
	local fresh = Placement.initial()
	self._stations[userId] = fresh
	return fresh
end

function InMemoryStationRepository:save(userId: number, station: Station)
	self._stations[userId] = station
end

-- Call on PlayerRemoving, once this is wired into a real bootstrap: without
-- it, a long-running server slowly accumulates a station per user who ever
-- connected.
function InMemoryStationRepository:release(userId: number)
	self._stations[userId] = nil
end

return InMemoryStationRepository
