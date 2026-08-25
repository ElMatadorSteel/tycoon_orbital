--!strict
-- The orbital sunlight phase -- ported from ProductionService:GetSunlight.
-- Pure function of an elapsed-time reading; the caller decides where that
-- number comes from (a monotonic clock in production, a fixed value in a
-- spec).

export type Rules = { period: number, eclipseFraction: number }

-- The transition isn't instant: a fixed ramp softens the cutoff between
-- full sun and full shadow so it doesn't read as a bug.
local RAMP = 0.06

local Orbit = {}

-- 0 in shadow, 1 in full sun, with a smooth ramp at the edges.
function Orbit.sunlightAt(elapsed: number, rules: Rules): number
	local phase = (elapsed % rules.period) / rules.period
	local eclipse = rules.eclipseFraction

	if phase < eclipse - RAMP then
		return 0
	elseif phase < eclipse then
		return (phase - (eclipse - RAMP)) / RAMP
	elseif phase < 1 - RAMP then
		return 1
	end
	return (1 - phase) / RAMP
end

return Orbit
