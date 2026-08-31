--!strict
-- The research-mine unlock: the one-time purchase a tycoon pad on the
-- station deck triggers. Pure -- no Roblox API, no Shared/Balance read, same
-- as Domain/Mining/Railgun which this deliberately mirrors.
--
-- Only the DECISION lives here. What the mine looks like, where the path
-- runs and what the pad is made of belong to the Adapter that builds them
-- (Adapters/Roblox/ResearchMineBuilder), and the spend itself goes through
-- Domain/Economy/Credits like every other purchase.

export type Rules = {
	cost: number,
}

-- The key written into profile.unlocked. A constant rather than a literal
-- repeated at each call site: the profile is persisted, so a typo in one of
-- three places would read as "not unlocked" forever rather than as an error.
local UNLOCK_ID = "ResearchMine"

local ResearchMine = {}

ResearchMine.UnlockId = UNLOCK_ID

function ResearchMine.isUnlocked(unlocked: { [string]: boolean }): boolean
	return unlocked[UNLOCK_ID] == true
end

-- Asked by the pad before it charges anything: a player who steps on it
-- without the credits gets a refusal, not a failed purchase. Separate from
-- Credits.spend on purpose -- a question that costs money is not a question.
function ResearchMine.canUnlock(
	credits: number,
	unlocked: { [string]: boolean },
	rules: Rules
): boolean
	if ResearchMine.isUnlocked(unlocked) then
		return false
	end
	return credits >= rules.cost
end

return ResearchMine
