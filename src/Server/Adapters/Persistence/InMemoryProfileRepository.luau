--!strict
-- Studio-without-API-access fallback AND the double used by tests -- it has
-- no Roblox dependency at all, which is exactly why the same file serves
-- both roles.

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Server and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach -- confirmed the first time
-- Rojo actually connected Studio (see CLAUDE.md's cutover notes). Lune has
-- no `game`, so the fallback below -- an ordinary relative require -- is
-- what actually runs there, unchanged from before. Doesn't compromise this
-- file's Roblox-freeness above: the branch below never runs under Lune.
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

local InMemoryProfileRepository = {}
InMemoryProfileRepository.__index = InMemoryProfileRepository

function InMemoryProfileRepository.new(clock: any, rules: Rules)
	return setmetatable({
		_clock = clock,
		_rules = rules,
		_profiles = {} :: { [number]: Profile },
	}, InMemoryProfileRepository)
end

function InMemoryProfileRepository:load(userId: number): Profile
	local existing = self._profiles[userId]
	if existing then
		return existing
	end
	local fresh = Profile.blank(self._rules)
	self._profiles[userId] = fresh
	return fresh
end

function InMemoryProfileRepository:save(userId: number, profile: Profile): boolean
	profile.savedAt = self._clock:now()
	self._profiles[userId] = profile
	return true
end

return InMemoryProfileRepository
