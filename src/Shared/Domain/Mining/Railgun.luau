--!strict
-- Railgun purchase/fire rules: cooldown gating and spawn-cap/roll gating.
-- Pure -- no Roblox API, no Shared/Balance reads (see CLAUDE.md's "Domain
-- code takes config as parameters").

export type Rules = {
	cost: number,
	cooldown: number, -- seconds between two shots
	maxActive: number, -- concurrent asteroids allowed per player
	spawnChancePerTick: number, -- rolled once per Mining tick, only while under maxActive
}

local Railgun = {}

-- now/lastFireAt are monotonic clock readings (Ports.Clock:monotonic()),
-- same as every other session-duration check in this codebase (the orbital
-- phase).
function Railgun.canFire(lastFireAt: number, now: number, cooldown: number): boolean
	return now - lastFireAt >= cooldown
end

function Railgun.canSpawn(activeCount: number, maxActive: number): boolean
	return activeCount < maxActive
end

function Railgun.shouldSpawn(roll: number, activeCount: number, rules: Rules): boolean
	if not Railgun.canSpawn(activeCount, rules.maxActive) then
		return false
	end
	return roll < rules.spawnChancePerTick
end

return Railgun
