--!strict
-- Volatile per-player state that must NEVER reach the profile -- it does
-- not need to survive a disconnect, and persisting it would be pure waste.
-- Not a port: unlike ProfileRepository/StationRepository, there is no
-- alternative implementation to ever swap in, so the Composition root just
-- builds one directly.
--
-- Two things live here so far:
--   - production: the fractional energy charge and pending credit a tick
--     carries over to the next one (ported from ProductionService's
--     private _charge/_pending tables).
--   - embarked: whether this player has walked onto their station THIS
--     SESSION. Legacy always starts a freshly-connected player in the
--     lobby regardless of prior progress (Players.CharacterAutoLoads =
--     false, LobbyService:welcome), so a returning player with
--     profile.objective already past "Embark" still has to press E again
--     -- this is exactly session state, not something profile.objective
--     already encodes.

export type ProductionState = { charge: number, pendingCredit: number }

local SessionRegistry = {}
SessionRegistry.__index = SessionRegistry

function SessionRegistry.new()
	return setmetatable({
		_production = {} :: { [number]: ProductionState },
		_embarked = {} :: { [number]: boolean },
	}, SessionRegistry)
end

function SessionRegistry:production(userId: number): ProductionState
	local existing = self._production[userId]
	if existing then
		return existing
	end
	local fresh = { charge = 0, pendingCredit = 0 }
	self._production[userId] = fresh
	return fresh
end

function SessionRegistry:hasEmbarked(userId: number): boolean
	return self._embarked[userId] == true
end

function SessionRegistry:setEmbarked(userId: number, value: boolean)
	self._embarked[userId] = value
end

-- Call on PlayerRemoving, once this is wired into a real bootstrap: nothing
-- here should outlive the connection it belongs to.
function SessionRegistry:release(userId: number)
	self._production[userId] = nil
	self._embarked[userId] = nil
end

return SessionRegistry
