--!strict
-- Load -> decide (Domain) -> save -> publish. Ported from
-- EconomyService:TrySpend, now with its replication side effect restored
-- (Stage 4) via the StatsPublisher port instead of firing a remote
-- directly.

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

local Result = require(fromShared("Domain/Support/Result"))
local Credits = require(fromShared("Domain/Economy/Credits"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

local SpendCredits = {}
SpendCredits.__index = SpendCredits

-- Built by Composition/Container.luau via
-- setmetatable(table.clone({ profileRepository = ... }), SpendCredits).
export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	statsPublisher: any, -- Ports.StatsPublisher
}

function SpendCredits:run(userId: number, amount: number): Result<number, string>
	local profile = self.profileRepository:load(userId)

	local result = Credits.spend(profile.credits, amount)
	if result.ok then
		profile.credits = result.value
		self.profileRepository:save(userId, profile)
		self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	end
	return result
end

return SpendCredits
