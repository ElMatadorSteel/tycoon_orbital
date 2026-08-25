--!strict
-- Minimal synchronous pub/sub -- no Roblox API, so it stays loadable under
-- Lune like the rest of Shared. Client/State.luau uses this to turn
-- attribute changes and Net.Notify events into one subscription surface,
-- per ARCHITECTURE.md's target layout (Shared/Signal.luau); nothing under
-- Domain needs it today.

export type Connection = {
	Disconnect: (Connection) -> (),
}

export type Signal = {
	Connect: (Signal, (...any) -> ()) -> Connection,
	Fire: (Signal, ...any) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	return setmetatable({ _listeners = {} }, Signal) :: any
end

function Signal:Connect(callback: (...any) -> ()): Connection
	local listeners = (self :: any)._listeners
	local entry = { callback = callback }
	table.insert(listeners, entry)

	local connection = {} :: Connection
	function connection.Disconnect()
		local index = table.find(listeners, entry)
		if index then
			table.remove(listeners, index)
		end
	end
	return connection
end

-- Listeners are snapshotted before firing: a listener that disconnects
-- itself (or another) mid-fire must not skip or double-call anyone.
function Signal:Fire(...: any)
	local listeners = table.clone((self :: any)._listeners)
	for _, entry in listeners do
		entry.callback(...)
	end
end

return Signal
