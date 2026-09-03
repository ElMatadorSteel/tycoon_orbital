--!strict
-- The shovel unlock: the one-time purchase a pad down in the pit triggers.
-- Pure -- no Roblox API, no Shared/Balance read -- and shaped on
-- Domain/Research/ResearchMine, which it deliberately mirrors: they are the
-- same kind of decision about two different things.
--
-- What the shovel DOES once owned is not here. Domain/Research/Vein owns the
-- pace of digging; this file only answers whether the player has one.

export type Rules = {
	cost: number,
}

-- The key written into profile.unlocked. A constant rather than a literal at
-- each call site: the profile is persisted, so a typo in one of three places
-- reads as "not unlocked" forever rather than as an error.
local UNLOCK_ID = "Shovel"

local Shovel = {}

Shovel.UnlockId = UNLOCK_ID

function Shovel.isUnlocked(unlocked: { [string]: boolean }): boolean
	return unlocked[UNLOCK_ID] == true
end

-- Asked by the pad before it charges anything, so a player who cannot afford
-- it gets a refusal rather than a failed purchase.
function Shovel.canUnlock(credits: number, unlocked: { [string]: boolean }, rules: Rules): boolean
	if Shovel.isUnlocked(unlocked) then
		return false
	end
	return credits >= rules.cost
end

return Shovel
