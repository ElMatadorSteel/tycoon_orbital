--!strict
-- Rebuilds the research-mine ZONE (pit, gangway, veins, the pad turned
-- green) for a player who already unlocked it in a previous session. Same
-- shape and reason as RestoreStation: the zone is memory-only Instance
-- state, wiped on every server restart, while profile.unlocked.ResearchMine
-- survives in the save -- without this, a player who paid for the mine
-- would find only the locked pad again after a restart. Called from
-- EmbarkStation, once per session -- see SessionRegistry:hasBuiltResearchMine.

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

local ResearchMine = require(fromShared("Domain/Research/ResearchMine"))

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	sceneBuilder: any, -- Ports.SceneBuilder
}

local RestoreResearchMine = {}
RestoreResearchMine.__index = RestoreResearchMine

function RestoreResearchMine:run(userId: number)
	local profile = self.profileRepository:load(userId)
	if not ResearchMine.isUnlocked(profile.unlocked) then
		return -- pad stays locked: nothing to rebuild
	end

	self.sceneBuilder:buildResearchMine(userId)
end

return RestoreResearchMine
