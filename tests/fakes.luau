--!strict
-- Reusable test doubles, exposed as the `Fakes` global by run.luau (see
-- DEVELOPMENT.md's list of spec globals).

local InMemoryProfileRepository =
	require("../src/Server/Adapters/Persistence/InMemoryProfileRepository")
local InMemoryStationRepository =
	require("../src/Server/Adapters/Persistence/InMemoryStationRepository")

-- A clock the test drives, per ARCHITECTURE.md: "the clock is a port for
-- the same reason the DataStore is one... expiries, streaks and cooldowns
-- are exactly the rules worth testing."
local TestClock = {}
TestClock.__index = TestClock

function TestClock.new(startEpoch: number?)
	return setmetatable({ _now = startEpoch or 0, _monotonic = 0 }, TestClock)
end

function TestClock:now(): number
	return self._now
end

function TestClock:advance(seconds: number)
	self._now += seconds
end

function TestClock:set(epoch: number)
	self._now = epoch
end

-- Separate from now()/advance(): a real Clock backs these with two
-- different primitives (os.time() vs os.clock()), so a test that only
-- means to move the orbital phase shouldn't also have to reason about
-- epoch time, and vice versa.
function TestClock:monotonic(): number
	return self._monotonic
end

function TestClock:setMonotonic(value: number)
	self._monotonic = value
end

-- Recording fakes for StatsPublisher/Notifier (ARCHITECTURE.md's Ports
-- table names them exactly this). Unlike InMemoryProfileRepository/
-- InMemoryStationRepository, these are test-only -- production always
-- wants the real attribute/RemoteEvent adapters, there is no legitimate
-- in-memory production use for either.

local RecordingStatsPublisher = {}
RecordingStatsPublisher.__index = RecordingStatsPublisher

function RecordingStatsPublisher.new()
	return setmetatable({
		_latest = {} :: { [number]: { [string]: any } }, -- merged snapshot per user
		calls = {} :: { { userId: number, snapshot: { [string]: any } } }, -- every publish(), in order
	}, RecordingStatsPublisher)
end

function RecordingStatsPublisher:publish(userId: number, snapshot: { [string]: any })
	local merged = self._latest[userId] or {}
	for key, value in snapshot do
		merged[key] = value
	end
	self._latest[userId] = merged
	table.insert(self.calls, { userId = userId, snapshot = snapshot })
end

-- The union of every field ever published for this user, like reading
-- their current attributes back -- not just the last call's fields.
function RecordingStatsPublisher:latest(userId: number): { [string]: any }
	return self._latest[userId] or {}
end

local RecordingNotifier = {}
RecordingNotifier.__index = RecordingNotifier

function RecordingNotifier.new()
	return setmetatable({
		calls = {} :: { { userId: number, kind: string, payload: any } },
	}, RecordingNotifier)
end

function RecordingNotifier:notify(userId: number, kind: string, payload: any)
	table.insert(self.calls, { userId = userId, kind = kind, payload = payload })
end

-- A no-op/recording SceneBuilder: doesn't touch any Instance (there is
-- none under Lune), just tracks who has "claimed a plot" so claimPlot's
-- idempotency/capacity behaviour is still exercisable, and records every
-- call so a test can assert a use case invoked the right one.
local RecordingSceneBuilder = {}
RecordingSceneBuilder.__index = RecordingSceneBuilder

function RecordingSceneBuilder.new(maxSlots: number?)
	return setmetatable({
		_claimed = {} :: { [number]: boolean },
		_maxSlots = maxSlots or math.huge,
		placeCalls = {} :: { { userId: number, placement: any, definition: any } },
		removeCalls = {} :: { { userId: number, x: number, y: number } },
		levelCalls = {} :: { { userId: number, x: number, y: number, level: number } },
	}, RecordingSceneBuilder)
end

function RecordingSceneBuilder:claimPlot(userId: number): boolean
	if self._claimed[userId] then
		return true
	end
	local count = 0
	for _ in self._claimed do
		count += 1
	end
	if count >= self._maxSlots then
		return false
	end
	self._claimed[userId] = true
	return true
end

function RecordingSceneBuilder:releasePlot(userId: number)
	self._claimed[userId] = nil
end

function RecordingSceneBuilder:placeModule(userId: number, placement: any, definition: any)
	table.insert(
		self.placeCalls,
		{ userId = userId, placement = placement, definition = definition }
	)
end

function RecordingSceneBuilder:removeModule(userId: number, x: number, y: number)
	table.insert(self.removeCalls, { userId = userId, x = x, y = y })
end

function RecordingSceneBuilder:setModuleLevel(userId: number, x: number, y: number, level: number)
	table.insert(self.levelCalls, { userId = userId, x = x, y = y, level = level })
end

-- A recording AsteroidField: doesn't touch any Instance (there is none
-- under Lune), just records every call so a test can assert RunMiningTick/
-- FireRailgun invoked the right one.
local RecordingAsteroidField = {}
RecordingAsteroidField.__index = RecordingAsteroidField

function RecordingAsteroidField.new()
	return setmetatable({
		spawnCalls = {} :: { { userId: number, asteroidId: string, tier: string } },
		despawnCalls = {} :: { { userId: number, asteroidId: string } },
	}, RecordingAsteroidField)
end

function RecordingAsteroidField:spawn(userId: number, asteroidId: string, tier: string)
	table.insert(self.spawnCalls, { userId = userId, asteroidId = asteroidId, tier = tier })
end

function RecordingAsteroidField:despawn(userId: number, asteroidId: string)
	table.insert(self.despawnCalls, { userId = userId, asteroidId = asteroidId })
end

-- A recording Teleporter: doesn't move anything (there is no character
-- under Lune), just records every call so a test can assert a use case
-- invoked the right one.
local RecordingTeleporter = {}
RecordingTeleporter.__index = RecordingTeleporter

function RecordingTeleporter.new()
	return setmetatable({
		lobbyCalls = {} :: { number },
		stationCalls = {} :: { number },
	}, RecordingTeleporter)
end

function RecordingTeleporter:sendToLobby(userId: number)
	table.insert(self.lobbyCalls, userId)
end

function RecordingTeleporter:sendToStation(userId: number)
	table.insert(self.stationCalls, userId)
end

return {
	TestClock = TestClock,
	InMemoryProfileRepository = InMemoryProfileRepository,
	InMemoryStationRepository = InMemoryStationRepository,
	RecordingStatsPublisher = RecordingStatsPublisher,
	RecordingNotifier = RecordingNotifier,
	RecordingSceneBuilder = RecordingSceneBuilder,
	RecordingTeleporter = RecordingTeleporter,
	RecordingAsteroidField = RecordingAsteroidField,
}
