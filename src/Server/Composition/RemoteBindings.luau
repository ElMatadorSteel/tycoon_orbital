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

	Net.MoveModule.OnServerInvoke = function(
		player: Player,
		x: number,
		y: number,
		newX: number,
		newY: number,
		rotation: number?
	)
		return respond(container.useCases.moveModule:run(player.UserId, x, y, newX, newY, rotation))
	end

	Net.ReturnToLobby.OnServerInvoke = function(player: Player)
		container.useCases.returnToLobby:run(player.UserId)
		return true, nil
	end

	Net.RebirthStation.OnServerInvoke = function(player: Player)
		return respond(container.useCases.rebirthStation:run(player.UserId))
	end

	Net.PurchaseRailgun.OnServerInvoke = function(player: Player)
		return respond(container.useCases.purchaseRailgun:run(player.UserId))
	end

	Net.FireRailgun.OnServerInvoke = function(player: Player, asteroidId: string)
		return respond(container.useCases.fireRailgun:run(player.UserId, asteroidId))
	end

	Net.MineVein.OnServerInvoke = function(player: Player, veinId: string)
		return respond(container.useCases.mineVein:run(player.UserId, veinId))
	end

	Net.DigBlock.OnServerInvoke = function(player: Player, layer: number, x: number, y: number)
		return respond(container.useCases.digBlock:run(player.UserId, layer, x, y))
	end

	-- oreId is optional -- nil sells the whole bag. Passed straight through
	-- rather than defaulted here: SellOres type-checks it itself, which is
	-- where that check belongs when the caller may not be our client.
	Net.SellOres.OnServerInvoke = function(player: Player, oreId: string?)
		return respond(container.useCases.sellOres:run(player.UserId, oreId))
	end

	-- Only bound when Container was built in development mode -- see its own
	-- header. A client InvokeServer against any of these in production hits
	-- an Instance with no OnServerInvoke callback set, which errors out
	-- rather than doing anything.
	if container.useCases.devSetPass then
		Net.DevSetPass.OnServerInvoke = function(player: Player, passId: string, enabled: boolean)
			return respond(container.useCases.devSetPass:run(player.UserId, passId, enabled))
		end
	end
	if container.useCases.devSetRebirths then
		Net.DevSetRebirths.OnServerInvoke = function(
			player: Player,
			count: number,
			resetStation: boolean
		)
			return respond(
				container.useCases.devSetRebirths:run(player.UserId, count, resetStation)
			)
		end
	end
	if container.useCases.devSetUnlimitedMoney then
		Net.DevSetUnlimitedMoney.OnServerInvoke = function(player: Player, enabled: boolean)
			return respond(container.useCases.devSetUnlimitedMoney:run(player.UserId, enabled))
		end
	end
	if container.useCases.devResetAll then
		Net.DevResetAll.OnServerInvoke = function(player: Player)
			return respond(container.useCases.devResetAll:run(player.UserId))
		end
	end
	if container.useCases.devGiveOres then
		Net.DevGiveOres.OnServerInvoke = function(player: Player, oreId: string?, amount: number?)
			return respond(container.useCases.devGiveOres:run(player.UserId, oreId, amount))
		end
	end
	-- speed is optional -- nil means "back to the default walking speed",
	-- which is what the panel's reset button sends. Passed straight through:
	-- DevSetWalkSpeed type-checks and clamps it itself.
	if container.useCases.devSetWalkSpeed then
		Net.DevSetWalkSpeed.OnServerInvoke = function(player: Player, speed: number?)
			return respond(container.useCases.devSetWalkSpeed:run(player.UserId, speed))
		end
	end
	-- addCredits is an ordinary, always-wired use case (not dev-only on its
	-- own) -- only the REMOTE that lets a client trigger it arbitrarily is
	-- gated to development mode.
	if container.development then
		Net.DevGiveCredits.OnServerInvoke = function(player: Player, amount: number)
			if typeof(amount) ~= "number" or amount ~= amount then
				return false, "invalid amount"
			end
			return true, container.useCases.addCredits:run(player.UserId, amount)
		end
	end
end

return RemoteBindings
