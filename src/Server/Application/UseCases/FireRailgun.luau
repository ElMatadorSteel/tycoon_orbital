--!strict
-- Validates a claimed hit and pays it out. The client's own camera raycast
-- is trusted only as far as "which asteroid id did you claim to hit" --
-- exactly like BuildController's own placement clicks, the server never
-- re-simulates the camera geometry itself, only the LOGICAL constraints:
-- does this id exist, is it still alive, is it this player's, is the
-- cooldown clear. A cheating client can only ever claim ids the server
-- itself handed out (SessionRegistry:spawnAsteroid), so the worst a forged
-- claim can do is ignore the cooldown -- which this still enforces
-- server-side regardless of what the client sends.

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

local AsteroidTiers = require(fromShared("Domain/Mining/AsteroidTiers"))
local Railgun = require(fromShared("Domain/Mining/Railgun"))
local Credits = require(fromShared("Domain/Economy/Credits"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	sessionRegistry: any, -- Application.SessionRegistry
	asteroidField: any, -- Ports.AsteroidField
	statsPublisher: any, -- Ports.StatsPublisher
	notifier: any, -- Ports.Notifier
	clock: any, -- Ports.Clock (monotonic() is what's used here)
	railgunRules: Railgun.Rules,
	tierRules: AsteroidTiers.Rules,
}

export type FireResult = { tier: string, reward: number }

local FireRailgun = {}
FireRailgun.__index = FireRailgun

function FireRailgun:run(userId: number, asteroidId: string): Result<FireResult, string>
	local profile = self.profileRepository:load(userId)
	if not profile.unlocked.Railgun then
		return Result.err("no railgun owned")
	end

	local now = self.clock:monotonic()
	if
		not Railgun.canFire(self.sessionRegistry:lastFire(userId), now, self.railgunRules.cooldown)
	then
		return Result.err("still recharging")
	end

	local asteroids = self.sessionRegistry:asteroids(userId)
	local state = asteroids[asteroidId]
	if not state then
		return Result.err("invalid target")
	end

	self.sessionRegistry:setLastFire(userId, now)
	self.sessionRegistry:removeAsteroid(userId, asteroidId)
	self.asteroidField:despawn(userId, asteroidId)

	local reward = AsteroidTiers.reward(state.tier, math.random(), self.tierRules)
	profile.credits = Credits.add(profile.credits, reward)
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.notifier:notify(userId, "Credits", reward)

	return Result.ok({ tier = state.tier, reward = reward })
end

return FireRailgun
