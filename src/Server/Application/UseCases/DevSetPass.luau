--!strict
-- Development-only affordance: turns a paid pass (Ultimate/EarlyRebirth) on
-- OR off without a real purchase, so the whole rebirth mechanic is testable
-- before any real Roblox Game Pass exists to buy. Takes the SAME path a real
-- purchase eventually will -- grant -> save -> snapshot -- per CLAUDE.md's
-- rule for dev affordances: this is not a bypass around the pipeline, only
-- a different trigger for it. A future real purchase flow
-- (MarketplaceService.PromptGamePassPurchaseFinished) would set the exact
-- same profile.unlocked flag TRUE and go through nothing else; only the
-- "turn it off again" direction has no real-money equivalent, and only ever
-- makes sense as a dev/testing action.
--
-- Wired into Container ONLY in development mode (see Composition/
-- Container.luau's `development` flag) -- there is no remote for this in
-- production; RemoteBindings only binds it when the use case exists.

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

local Rebirth = require(fromShared("Domain/Rebirth/Rebirth"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	statsPublisher: any, -- Ports.StatsPublisher
	rebirthRules: Rebirth.Rules,
}

local DevSetPass = {}
DevSetPass.__index = DevSetPass

function DevSetPass:run(userId: number, passId: string, enabled: boolean): Result<nil, string>
	if passId ~= Rebirth.Passes.Ultimate and passId ~= Rebirth.Passes.EarlyRebirth then
		return Result.err("unknown pass")
	end

	local profile = self.profileRepository:load(userId)
	profile.unlocked[passId] = enabled
	self.profileRepository:save(userId, profile)

	local hasUltimate = profile.unlocked[Rebirth.Passes.Ultimate] == true
	local hasEarlyPass = profile.unlocked[Rebirth.Passes.EarlyRebirth] == true
	local boost = Rebirth.multiplier(profile.rebirths, hasUltimate, self.rebirthRules)
	self.statsPublisher:publish(
		userId,
		Snapshot.rebirth(profile.rebirths, hasUltimate, hasEarlyPass, boost)
	)

	return Result.ok(nil)
end

return DevSetPass
