--!strict
-- Implements the Clock port: os.time() for the absolute epoch, os.clock()
-- for the monotonic reading. Roblox and Lune both provide these
-- identically, so this adapter also happens to be safe to require under
-- Lune (it just isn't part of what the suite is meant to cover, per
-- ARCHITECTURE.md's "adapters are deliberately thin and are not covered").

local SystemClock = {}
SystemClock.__index = SystemClock

function SystemClock.new()
	return setmetatable({}, SystemClock)
end

function SystemClock:now(): number
	return os.time()
end

function SystemClock:monotonic(): number
	return os.clock()
end

return SystemClock
