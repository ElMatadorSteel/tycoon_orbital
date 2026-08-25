--!strict
-- Ported from the legacy ReturnToLobby remote: a "go back to the lobby"
-- teleport, not a logout. It does NOT release the claimed plot -- legacy
-- only ever releases one on PlayerRemoving (StationService:_teardown), and
-- a returning player keeps their station for the rest of the session.

local Snapshot = require("../Snapshot")

export type Dependencies = {
	statsPublisher: any, -- Ports.StatsPublisher
	teleporter: any, -- Ports.Teleporter
}

local ReturnToLobby = {}
ReturnToLobby.__index = ReturnToLobby

function ReturnToLobby:run(userId: number)
	self.statsPublisher:publish(userId, Snapshot.location("Lobby"))
	self.teleporter:sendToLobby(userId)
end

return ReturnToLobby
