--!strict
-- Local mirror of the replicated state -- the one place that reads the
-- server's published attributes (Ports.StatsPublisher) and turns them into
-- subscriptions, and the one place that listens to Shared/Net.luau's Notify
-- event (Ports.Notifier). Controllers go through here instead of touching
-- LocalPlayer:GetAttributeChangedSignal or Net.Notify directly -- see
-- ARCHITECTURE.md's "State replicates through attributes, not RemoteEvents"
-- and its Client/State.luau entry in the target layout.

local Players = game:GetService("Players")

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Client and src/Shared to different service roots with no common
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
	return "../Shared/" .. path
end

local Net = require(fromShared("Net"))
local Signal = require(fromShared("Signal"))

local player = Players.LocalPlayer

-- Every attribute a use case can publish, per Application/Snapshot.luau.
-- Watched eagerly so State.Changed fires no matter which controller (if
-- any) is currently listening for a given key.
local WATCHED = {
	"Credits",
	"Objective",
	"Location",
	"Sunlight",
	"Efficiency",
	"PowerProduction",
	"PowerConsumption",
	"PowerCharge",
	"PowerStorage",
	"HeatLoad",
	"HeatCapacity",
	"Income",
	"Rebirths",
	"HasUltimate",
	"HasEarlyRebirth",
	"GlobalBoost",
}

local State = {}

-- (key: string, value: any) -> ()
State.Changed = Signal.new()
-- (kind: string, payload: any) -> () -- a "+150" gain, an ObjectiveCompleted
-- banner cue; see Ports.Notifier's callers for the kinds in use.
State.Notified = Signal.new()

function State.get(key: string): any
	return player:GetAttribute(key)
end

for _, key in WATCHED do
	player:GetAttributeChangedSignal(key):Connect(function()
		State.Changed:Fire(key, player:GetAttribute(key))
	end)
end

Net.Notify.OnClientEvent:Connect(function(kind: string, payload: any)
	State.Notified:Fire(kind, payload)
end)

return State
