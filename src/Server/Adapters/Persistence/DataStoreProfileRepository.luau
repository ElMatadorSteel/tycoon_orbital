--!strict
-- Ported from the legacy SaveService:_load/:Save/retry -- same retry with
-- growing delay, same "__probe" availability check, same UpdateAsync guard
-- against a newer concurrent write, same freeze-on-failed-read.

local DataStoreService = game:GetService("DataStoreService")

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

local Profile = require(fromShared("Domain/Profile/Profile"))
type Profile = Profile.Profile
type Rules = Profile.Rules

export type Config = {
	storeName: string,
	retryCount: number,
	retryDelay: number, -- seconds, doubles on each retry
}

local function retry(retryCount: number, retryDelay: number, label: string, fn: () -> any): boolean
	for attempt = 1, retryCount do
		local ok, result = pcall(fn)
		if ok then
			return true
		end
		if attempt == retryCount then
			warn(
				`[DataStoreProfileRepository] {label}: failed after {attempt} attempts -- {result}`
			)
			return false
		end
		-- Growing delay: a rate-limited DataStore does not unblock by being
		-- hammered.
		task.wait(retryDelay * attempt)
	end
	return false
end

local DataStoreProfileRepository = {}
DataStoreProfileRepository.__index = DataStoreProfileRepository

function DataStoreProfileRepository.new(config: Config, clock: any, rules: Rules)
	local self = setmetatable({
		_clock = clock,
		_config = config,
		_rules = rules,
		_store = nil :: DataStore?,
		-- The profile actually read for a user is cached here after the
		-- first load(), and returned as-is on every later call within the
		-- session -- exactly like the legacy SaveService._profiles table.
		-- Without this, a second load() would hit the DataStore again (or
		-- return a fresh blank() if it's unavailable) and silently discard
		-- whatever the caller had already mutated in memory since the first
		-- load.
		_cache = {} :: { [number]: Profile },
		_lastWrite = {} :: { [number]: number },
		_frozen = {} :: { [number]: boolean },
	}, DataStoreProfileRepository)

	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(config.storeName)
	end)
	if ok then
		-- GetDataStore succeeds even without API access: only a real network
		-- call reveals the problem. Probed once so the failure is reported
		-- clearly instead of failing player by player.
		if pcall(function()
			return store:GetAsync("__probe")
		end) then
			self._store = store
		end
	end

	return self
end

function DataStoreProfileRepository:isAvailable(): boolean
	return self._store ~= nil
end

function DataStoreProfileRepository:_key(userId: number): string
	return `Player_{userId}`
end

function DataStoreProfileRepository:load(userId: number): Profile
	local cached = self._cache[userId]
	if cached then
		return cached
	end

	local store = self._store
	if not store then
		local fresh = Profile.blank(self._rules)
		self._cache[userId] = fresh
		return fresh
	end

	local raw
	local ok = retry(self._config.retryCount, self._config.retryDelay, `load {userId}`, function()
		raw = store:GetAsync(self:_key(userId))
	end)

	local profile: Profile
	if not ok then
		-- A failed read must never let a save happen: writing a blank
		-- profile over real progress is worse than saving nothing.
		self._frozen[userId] = true
		warn(
			`[DataStoreProfileRepository] {userId}: unreadable profile, saving disabled for this session`
		)
		profile = Profile.blank(self._rules)
	elseif raw == nil then
		self._lastWrite[userId] = 0
		profile = Profile.blank(self._rules)
	else
		profile = Profile.sanitize(raw, self._rules)
		self._lastWrite[userId] = profile.savedAt
	end

	self._cache[userId] = profile
	return profile
end

-- Drops the cached profile for a user (call on PlayerRemoving, once this is
-- wired into a real bootstrap) so a later rejoin re-reads the DataStore
-- instead of reusing a stale in-memory copy.
function DataStoreProfileRepository:release(userId: number)
	self._cache[userId] = nil
	self._lastWrite[userId] = nil
	self._frozen[userId] = nil
end

function DataStoreProfileRepository:save(userId: number, profile: Profile): boolean
	local store = self._store
	if not store or self._frozen[userId] then
		return false
	end

	local stamp = self._clock:now()
	local last = self._lastWrite[userId] or 0

	local ok = retry(self._config.retryCount, self._config.retryDelay, `save {userId}`, function()
		return store:UpdateAsync(self:_key(userId), function(stored)
			-- Another session wrote after our read: it knows more than we
			-- do. Returning nil cancels the write without raising an error.
			if
				typeof(stored) == "table"
				and typeof(stored.savedAt) == "number"
				and stored.savedAt > last
			then
				return nil
			end
			profile.savedAt = stamp
			return profile
		end)
	end)

	if ok then
		self._lastWrite[userId] = stamp
	end
	return ok
end

return DataStoreProfileRepository
