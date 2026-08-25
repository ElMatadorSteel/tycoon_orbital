--!strict
-- Claims a plot, moves the character there, marks the player as having
-- walked onto their station this session, and publishes it -- ported from
-- StationService:SendToStation/EnsureStation. Can now fail: every plot
-- occupied (six total) is a real, if rare, refusal the legacy service had
-- too ("Toutes les stations sont occupées").

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

local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	sessionRegistry: any, -- Application.SessionRegistry
	statsPublisher: any, -- Ports.StatsPublisher
	sceneBuilder: any, -- Ports.SceneBuilder
	teleporter: any, -- Ports.Teleporter
}

local EmbarkStation = {}
EmbarkStation.__index = EmbarkStation

function EmbarkStation:run(userId: number): Result<nil, string>
	local claimed = self.sceneBuilder:claimPlot(userId)
	if not claimed then
		return Result.err("every station is occupied")
	end

	self.sessionRegistry:setEmbarked(userId, true)
	self.statsPublisher:publish(userId, Snapshot.location("Station"))
	self.teleporter:sendToStation(userId)

	return Result.ok(nil)
end

return EmbarkStation
