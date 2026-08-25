--!strict
-- Binds every client-facing RemoteFunction (Shared/Net.luau) to its use
-- case. The only place a Result<T, E> gets flattened into the
-- (ok: boolean, valueOrError: any) tuple a RemoteFunction actually returns
-- over the wire, and the only place a Player gets reduced to the userId
-- every use case takes -- neither Application nor Shared/Net.luau should
-- know about either.

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

local Net = require(fromShared("Net"))

local RemoteBindings = {}

local function respond(result: { ok: boolean, value: any?, error: any? }): (boolean, any)
	if result.ok then
		return true, result.value
	end
	return false, result.error
end

function RemoteBindings.bind(container: any)
	Net.PlaceModule.OnServerInvoke = function(
		player: Player,
		id: string,
		x: number,
		y: number,
		rotation: number?
	)
		return respond(container.useCases.placeModule:run(player.UserId, id, x, y, rotation))
	end

	Net.RemoveModule.OnServerInvoke = function(player: Player, x: number, y: number)
		return respond(container.useCases.removeModule:run(player.UserId, x, y))
	end

	Net.UpgradeModule.OnServerInvoke = function(player: Player, x: number, y: number)
		return respond(container.useCases.upgradeModule:run(player.UserId, x, y))
	end

	Net.ReturnToLobby.OnServerInvoke = function(player: Player)
		container.useCases.returnToLobby:run(player.UserId)
		return true, nil
	end
end

return RemoteBindings
