--!strict
-- Load -> decide (Domain) -> save -> publish. Ported from
-- EconomyService:Add. The legacy gain-batching (accumulate over ~1s before
-- showing a "+150" popup) is deliberately not reproduced here: it needs a
-- real recurring loop to flush into, which is Composition/Bootstrap's job
-- once one exists (the 3D-building / live-loop stage) -- so for now this
-- publishes the new balance immediately as state, with no popup.

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

local Credits = require(fromShared("Domain/Economy/Credits"))
local Snapshot = require("../Snapshot")

local AddCredits = {}
AddCredits.__index = AddCredits

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	statsPublisher: any, -- Ports.StatsPublisher
}

function AddCredits:run(userId: number, amount: number): number
	local profile = self.profileRepository:load(userId)
	profile.credits = Credits.add(profile.credits, amount)
	self.profileRepository:save(userId, profile)
	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	return profile.credits
end

return AddCredits
