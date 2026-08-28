--!strict
-- One mining-field tick for one player: expire anything past its lifetime,
-- then maybe spawn a new asteroid. Cheap no-op for anyone who hasn't bought
-- a Railgun -- called unconditionally for every connected player, same
-- shape as RunProductionTick's own per-player loop in Bootstrap.
--
-- Deliberately does NOT know about "is this player on their station" --
-- AsteroidFieldRenderer's own spawn() is a safe no-op when the player has
-- never claimed a plot (no origin to spawn from), same defensive shape as
-- StationSceneBuilder:placeModule's "no claimed plot to build onto -- nothing
-- sensible to do" early return.

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

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	sessionRegistry: any, -- Application.SessionRegistry
	asteroidField: any, -- Ports.AsteroidField
	clock: any, -- Ports.Clock (monotonic() is what's used here)
	railgunRules: Railgun.Rules,
	tierRules: AsteroidTiers.Rules,
	asteroidLifetime: number,
}

local RunMiningTick = {}
RunMiningTick.__index = RunMiningTick

function RunMiningTick:run(userId: number)
	local profile = self.profileRepository:load(userId)
	if not profile.unlocked.Railgun then
		return
	end

	local now = self.clock:monotonic()
	local asteroids = self.sessionRegistry:asteroids(userId)

	local activeCount = 0
	local expired: { string } = {}
	for asteroidId, state in asteroids do
		if now - state.spawnedAt >= self.asteroidLifetime then
			table.insert(expired, asteroidId)
		else
			activeCount += 1
		end
	end
	for _, asteroidId in expired do
		self.sessionRegistry:removeAsteroid(userId, asteroidId)
		self.asteroidField:despawn(userId, asteroidId)
	end

	if Railgun.shouldSpawn(math.random(), activeCount, self.railgunRules) then
		local tier = AsteroidTiers.pick(math.random(), self.tierRules)
		local asteroidId = self.sessionRegistry:spawnAsteroid(userId, tier, now)
		self.asteroidField:spawn(userId, asteroidId, tier)
	end
end

return RunMiningTick
