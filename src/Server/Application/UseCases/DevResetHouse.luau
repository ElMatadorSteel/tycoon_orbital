--!strict
-- Development-only: resets house progress by clearing all House_* unlocked
-- keys and rebuilding the house on the plateau (all stages hidden again,
-- pads reset). Never wired outside development mode.

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
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any,
	statsPublisher: any,
	sceneBuilder: any,
	houseStages: { { id: string, name: string, cost: number } },
}

local DevResetHouse = {}
DevResetHouse.__index = DevResetHouse

function DevResetHouse:run(userId: number): Result<nil, string>
	local profile = self.profileRepository:load(userId)

	-- Clear all House_* keys from profile.unlocked
	for _, stage in self.houseStages do
		profile.unlocked["House_" .. stage.id] = nil
	end

	self.profileRepository:save(userId, profile)
	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))

	-- Rebuild the house scene (destroys old pads + house, creates fresh ones)
	self.sceneBuilder:rebuildHouse(userId)

	return Result.ok(nil)
end

return DevResetHouse
