--!strict
-- Implements the Notifier port via Shared/Net.luau's `Notify` RemoteEvent
-- -- the shared contract now owns creating it, this adapter just fires it.
-- `kind` and `payload` are sent through as-is; the client decides what to
-- do with them (a Gain popup, a banner) -- this adapter only delivers.

local Players = game:GetService("Players")

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

local Net = require(fromShared("Net"))

local RemoteNotifier = {}
RemoteNotifier.__index = RemoteNotifier

function RemoteNotifier.new()
	return setmetatable({}, RemoteNotifier)
end

function RemoteNotifier:notify(userId: number, kind: string, payload: any)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	(Net.Notify :: RemoteEvent):FireClient(player, kind, payload)
end

return RemoteNotifier
