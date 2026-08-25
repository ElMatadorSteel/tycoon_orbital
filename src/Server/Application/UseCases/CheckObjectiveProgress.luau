--!strict
-- Advances the onboarding chain by at most one step -- ported from
-- ObjectiveService:_check/_publish. The server judges, as everywhere else;
-- the client only ever receives the index it's currently on (Objectives.get
-- looks the text up locally, on both sides). The current index is state
-- (StatsPublisher); "you just completed this one, for this reward" is a
-- one-off (Notifier), same split as the legacy remote's two-part payload
-- (`index, completed?`).
--
-- "Embark" is judged from session state (has the player walked onto their
-- station this session), every other objective from the station's actual
-- contents -- same split as the legacy service, see
-- Domain/Objectives/Checks.luau's header for why.

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

local Objectives = require(fromShared("Domain/Objectives/Objectives"))
local Checks = require(fromShared("Domain/Objectives/Checks"))
local Credits = require(fromShared("Domain/Economy/Credits"))
local Snapshot = require("../Snapshot")

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	sessionRegistry: any, -- Application.SessionRegistry
	statsPublisher: any, -- Ports.StatsPublisher
	notifier: any, -- Ports.Notifier
}

export type ProgressResult = {
	advanced: boolean,
	completedIndex: number?,
	reward: number?,
	newIndex: number,
}

local CheckObjectiveProgress = {}
CheckObjectiveProgress.__index = CheckObjectiveProgress

function CheckObjectiveProgress:run(userId: number): ProgressResult
	local profile = self.profileRepository:load(userId)
	local index = profile.objective

	local objective = Objectives.get(index)
	if not objective then
		return { advanced = false, newIndex = index } -- chain finished
	end

	local passed: boolean
	if objective.id == "Embark" then
		passed = self.sessionRegistry:hasEmbarked(userId)
	else
		local check = Checks.ById[objective.id]
		if not check then
			return { advanced = false, newIndex = index }
		end
		passed = check(self.stationRepository:load(userId))
	end

	if not passed then
		return { advanced = false, newIndex = index }
	end

	profile.objective = index + 1
	if objective.reward > 0 then
		profile.credits = Credits.add(profile.credits, objective.reward)
	end
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.objective(profile.objective))
	if objective.reward > 0 then
		self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	end
	self.notifier:notify(userId, "ObjectiveCompleted", { index = index, reward = objective.reward })

	return {
		advanced = true,
		completedIndex = index,
		reward = objective.reward,
		newIndex = profile.objective,
	}
end

return CheckObjectiveProgress
