--!strict
-- Prestige mechanic: once the core reaches a threshold level, a player may
-- reset their station and credits for a small, permanent, per-rebirth
-- production multiplier that stacks across every future rebirth. A paid
-- pass lowers that threshold -- the reward for rebirthing is identical
-- either way, only the wait is shorter (see Balance.Rebirth's own comment
-- for the exact numbers).
--
-- Its own Domain subject rather than folded into Station or Profile: it
-- reads from both (the core's level, the profile's rebirth count and
-- unlocked passes) but decides something neither of them owns.
--
-- `enabled` is the modular per-zone switch this was explicitly asked for:
-- flip it off and Rebirth.canRebirth never returns true, whatever the
-- core's level -- the whole mechanic goes dormant without touching any
-- other rule. Only one zone exists today, so it's one flag in Balance; a
-- future multi-zone build would key this per zone instead.

export type Rules = {
	enabled: boolean,
	normalThreshold: number, -- core level required for a free rebirth
	earlyThreshold: number, -- core level required with the EarlyRebirth pass
	bonusPerRebirth: number, -- +this, additive, per rebirth already banked
	ultimateMultiplier: number, -- flat multiplier while the Ultimate pass is owned
}

local Rebirth = {}

-- The two paid passes, as the exact profile.unlocked[...] keys -- named
-- here once so nothing else has to spell the strings out.
Rebirth.Passes = {
	Ultimate = "Ultimate",
	EarlyRebirth = "EarlyRebirth",
}

-- Whether a rebirth can be performed right now, given the core's current
-- level and whether the player has unlocked the early-rebirth pass.
function Rebirth.canRebirth(coreLevel: number, hasEarlyPass: boolean, rules: Rules): boolean
	if not rules.enabled then
		return false
	end
	local threshold = if hasEarlyPass then rules.earlyThreshold else rules.normalThreshold
	return coreLevel >= threshold
end

-- The global production multiplier from every rebirth banked so far, plus
-- the Ultimate pass if owned. Additive across rebirths -- a second rebirth
-- does not multiply the first one's bonus, it would compound explosively --
-- then Ultimate multiplies the total once, on top.
function Rebirth.multiplier(rebirths: number, hasUltimate: boolean, rules: Rules): number
	local base = 1 + math.max(0, rebirths) * rules.bonusPerRebirth
	if hasUltimate then
		return base * rules.ultimateMultiplier
	end
	return base
end

return Rebirth
