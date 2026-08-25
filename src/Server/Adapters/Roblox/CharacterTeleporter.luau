--!strict
-- Implements the Teleporter port -- ported from the teleport half of
-- legacy LobbyService:Send / StationService:SendToStation (claiming the
-- plot itself is StationSceneBuilder:claimPlot's job, called separately by
-- EmbarkStation; this adapter only ever moves the character once that's
-- already decided).

local Players = game:GetService("Players")

export type Config = {
	lobbySpawn: SpawnLocation,
	sceneBuilder: any, -- Ports.SceneBuilder, extended here with :spawnLocationFor
}

local CharacterTeleporter = {}
CharacterTeleporter.__index = CharacterTeleporter

function CharacterTeleporter.new(config: Config)
	return setmetatable({ _config = config }, CharacterTeleporter)
end

local function moveTo(player: Player, spawnPart: SpawnLocation)
	player.RespawnLocation = spawnPart
	local character = player.Character
	if character then
		character:PivotTo(spawnPart.CFrame * CFrame.new(0, 3, 0))
	end
end

function CharacterTeleporter:sendToLobby(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	moveTo(player, self._config.lobbySpawn)
end

function CharacterTeleporter:sendToStation(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	local spawnPart = self._config.sceneBuilder:spawnLocationFor(userId)
	if not spawnPart then
		return -- no claimed plot -- nothing sensible to do
	end
	moveTo(player, spawnPart)
end

return CharacterTeleporter
