--!strict
-- The mining cooldown: how long a player has to wait between two hits on the
-- SAME vein. Deliberately the only rule here -- unlike Domain/Mining/Railgun
-- a vein is not spawned or despawned, it is a fixed fixture of the mine, so
-- there is no spawn-chance or lifetime rule to go with it, only this one.

export type Rules = { cooldown: number }

local Vein = {}

function Vein.canMine(lastMinedAt: number, now: number, cooldown: number): boolean
	return now - lastMinedAt >= cooldown
end

return Vein
