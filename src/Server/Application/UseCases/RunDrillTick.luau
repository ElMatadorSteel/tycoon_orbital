--!strict
-- Passive ore production: called every drill tick for every connected player.
-- No-ops if the player has no drill. Otherwise, if enough time has elapsed
-- since the last production, rolls for an ore and adds it to the bag.
--
-- Deliberately does NOT save the profile (same reasoning as RunProductionTick):
-- a drill that produces every 1-12 seconds would flood the DataStore write
-- budget. Durability comes from Bootstrap's autosave loop and PlayerRemoving.

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

local Drill = require(fromShared("Domain/Research/Drill"))
local Snapshot = require("../Snapshot")

export type Dependencies = {
	profileRepository: any,
	sessionRegistry: any,
	statsPublisher: any,
	clock: any,
	drillRules: Drill.Rules,
	random: () -> number,
}

local RunDrillTick = {}
RunDrillTick.__index = RunDrillTick

function RunDrillTick:run(userId: number)
	local profile = self.profileRepository:load(userId)

	if not Drill.isUnlocked(profile.unlocked) then
		return
	end

	local level = profile.drillLevel or 1
	local interval = Drill.interval(level, self.drillRules)
	local now = self.clock:monotonic()
	local lastTick = self.sessionRegistry:lastDrillTick(userId)

	if now - lastTick < interval then
		return
	end

	self.sessionRegistry:setLastDrillTick(userId, now)

	local roll = self.random()
	local oreId = Drill.rollOre(level, self.drillRules, roll)
	if not oreId then
		return
	end

	profile.ores[oreId] = (profile.ores[oreId] or 0) + 1
	self.statsPublisher:publish(userId, Snapshot.ore(oreId, profile.ores[oreId]))
end

return RunDrillTick
