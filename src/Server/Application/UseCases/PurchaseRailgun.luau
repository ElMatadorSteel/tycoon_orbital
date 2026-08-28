--!strict
-- One-time unlock: spend credits, flip profile.unlocked.Railgun on. Same
-- load -> validate -> spend -> save -> publish shape as PlaceModule, minus
-- any station/grid concern -- this touches only the profile. The dispenser
-- Tool pickup (see Adapters/Roblox/RailgunKioskBuilder) is a SEPARATE step:
-- this use case only ever grants the FLAG, never touches a Backpack.

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

local Railgun = require(fromShared("Domain/Mining/Railgun"))
local Credits = require(fromShared("Domain/Economy/Credits"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	statsPublisher: any, -- Ports.StatsPublisher
	railgunRules: Railgun.Rules,
}

local PurchaseRailgun = {}
PurchaseRailgun.__index = PurchaseRailgun

function PurchaseRailgun:run(userId: number): Result<nil, string>
	local profile = self.profileRepository:load(userId)

	if profile.unlocked.Railgun then
		return Result.err("railgun already owned")
	end

	local spend = Credits.spend(profile.credits, self.railgunRules.cost)
	if not spend.ok then
		return spend
	end

	profile.credits = spend.value
	profile.unlocked.Railgun = true
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	self.statsPublisher:publish(userId, Snapshot.mining(true))

	return Result.ok(nil)
end

return PurchaseRailgun
