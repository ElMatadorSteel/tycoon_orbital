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

-- What the HUD needs and sunlightAt cannot give it: a single reading tells you
-- how bright it is now, never how long that lasts.
--
-- `inEclipse` means "not at full sun" -- the ramps count as eclipse, because a
-- player watching their output fall does not care that the shadow is only
-- partial yet.
export type Phase = { inEclipse: boolean, secondsUntilChange: number }

function Orbit.eclipseAt(elapsed: number, rules: Rules): Phase
	local phase = (elapsed % rules.period) / rules.period
	local sunrise = rules.eclipseFraction -- full sun begins
	local sunset = 1 - RAMP -- full sun ends

	if phase >= sunrise and phase < sunset then
		return { inEclipse = false, secondsUntilChange = (sunset - phase) * rules.period }
	end

	-- The shadow straddles the wrap point: past sunset the next sunrise is in
	-- the NEXT revolution, so the difference has to be brought back positive
	-- before it means anything.
	local remaining = sunrise - phase
	if remaining <= 0 then
		remaining += 1
	end
	return { inEclipse = true, secondsUntilChange = remaining * rules.period }
end

return Orbit
