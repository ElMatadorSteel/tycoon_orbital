--!strict
-- Development-only: sets the tester's walk speed, so crossing the map to
-- check something is not an afternoon's walk.
--
-- Session-only, exactly like DevSetUnlimitedMoney -- nothing here reaches
-- the profile, so no real player's movement can ever depend on a flag
-- surviving a reconnect by accident. Surviving a RESPAWN is a different
-- matter and is the actuator's job (see HumanoidMovementActuator).

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

local Result = require(fromShared("Domain/Support/Result"))

type Result<T, E> = Result.Result<T, E>

export type Rules = { default: number, min: number, max: number }

export type Dependencies = {
	movementActuator: any, -- Ports.MovementActuator
	walkSpeedRules: Rules,
}

local DevSetWalkSpeed = {}
DevSetWalkSpeed.__index = DevSetWalkSpeed

-- `speed = nil` means "back to normal", which is what the panel's reset
-- button sends -- the default is a balance number, so the caller does not
-- get to decide what normal is.
--
-- Returns the speed ACTUALLY applied, not the one asked for: the panel
-- echoes that value back, so a clamped request reads as a clamp rather
-- than as the field having been ignored.
function DevSetWalkSpeed:run(userId: number, speed: number?): Result<number, string>
	local rules = self.walkSpeedRules
	local requested = if speed == nil then rules.default else speed

	-- `requested ~= requested` is the NaN test. A remote is a public API and
	-- its caller is not necessarily our client, so this checks the type
	-- rather than trusting the panel to have run tonumber() first.
	if typeof(requested) ~= "number" or requested ~= requested then
		return Result.err("invalid walk speed")
	end

	local applied = math.clamp(requested, rules.min, rules.max)
	self.movementActuator:setWalkSpeed(userId, applied)
	return Result.ok(applied)
end

return DevSetWalkSpeed
