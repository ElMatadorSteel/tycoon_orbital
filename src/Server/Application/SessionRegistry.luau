--!strict
-- Volatile per-player state that must NEVER reach the profile -- it does
-- not need to survive a disconnect, and persisting it would be pure waste.
-- Not a port: unlike ProfileRepository/StationRepository, there is no
-- alternative implementation to ever swap in, so the Composition root just
-- builds one directly.
--
-- Three things live here so far:
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
--   - restored: whether RestoreStation has already replayed this player's
--     saved modules THIS SESSION. Station data is memory-only (see
--     Ports.StationRepository's header) and gets rebuilt from scratch --
--     just the core -- every time claimPlot runs; without this flag,
--     re-embarking after a trip to the lobby (claimPlot's early-return
--     path, not a fresh claim) would replay the save a second time on top
--     of the station the player already has, duplicating every module.
--   - unlimitedMoney: a development-only toggle (DevSetUnlimitedMoney) --
--     RunProductionTick tops credits back up against a large ceiling every
--     tick while it's set, so no dev-mode spending can ever run it dry.
--     Deliberately session-only, never persisted: a real player's balance
--     must never depend on a flag surviving a reconnect by accident.
--   - asteroids/lastFire: the Railgun mining side-feature's live state --
--     which asteroid ids are currently alive for this player (tier +
--     spawnedAt, so RunMiningTick can judge expiry) and when they last
--     fired (so FireRailgun can enforce the cooldown). Same volatility
--     reasoning as `production`: an asteroid flying past has no meaning
--     across a disconnect, and the profile only ever needs to know the
--     credits a hit already earned, not the asteroid itself.
--   - researchMineBuilt: whether the research-mine ZONE (the pit, the
--     gangway, the veins) has already been built for this player THIS
--     SESSION -- same "session data rebuilt from a persisted flag" shape as
--     `restored`: the zone is memory-only, so EmbarkStation rebuilds it
--     from profile.unlocked.ResearchMine on the first embark of the
--     session, and this flag stops a lobby-and-back trip from building it a
--     second time on top of the one already standing.
--   - veinCooldowns: when a player last mined a given vein (keyed by
--     OreCatalog.veinId), so MineVein can enforce Balance.Research.Vein
--     .Cooldown per vein rather than globally -- mining the rim vein does
--     not lock the floor vein.

export type ProductionState = { charge: number, pendingCredit: number }
export type AsteroidState = { tier: string, spawnedAt: number }

local SessionRegistry = {}
SessionRegistry.__index = SessionRegistry

function SessionRegistry.new()
	return setmetatable({
		_production = {} :: { [number]: ProductionState },
		_embarked = {} :: { [number]: boolean },
		_restored = {} :: { [number]: boolean },
		_unlimitedMoney = {} :: { [number]: boolean },
		_asteroids = {} :: { [number]: { [string]: AsteroidState } },
		_lastFire = {} :: { [number]: number },
		_nextAsteroidId = {} :: { [number]: number },
		_researchMineBuilt = {} :: { [number]: boolean },
		_veinCooldowns = {} :: { [number]: { [string]: number } },
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

function SessionRegistry:hasRestored(userId: number): boolean
	return self._restored[userId] == true
end

function SessionRegistry:setRestored(userId: number, value: boolean)
	self._restored[userId] = value
end

function SessionRegistry:hasUnlimitedMoney(userId: number): boolean
	return self._unlimitedMoney[userId] == true
end

function SessionRegistry:setUnlimitedMoney(userId: number, value: boolean)
	self._unlimitedMoney[userId] = value
end

function SessionRegistry:asteroids(userId: number): { [string]: AsteroidState }
	local existing = self._asteroids[userId]
	if existing then
		return existing
	end
	local fresh = {}
	self._asteroids[userId] = fresh
	return fresh
end

-- Ids are per-player incrementing counters, not GUIDs: readable in the
-- Studio explorer while testing, and a player's own field never needs to be
-- globally unique across other players' fields.
function SessionRegistry:spawnAsteroid(userId: number, tier: string, now: number): string
	local nextId = (self._nextAsteroidId[userId] or 0) + 1
	self._nextAsteroidId[userId] = nextId
	local id = `Asteroid_{nextId}`
	self:asteroids(userId)[id] = { tier = tier, spawnedAt = now }
	return id
end

function SessionRegistry:removeAsteroid(userId: number, asteroidId: string)
	local asteroids = self._asteroids[userId]
	if asteroids then
		asteroids[asteroidId] = nil
	end
end

function SessionRegistry:lastFire(userId: number): number
	return self._lastFire[userId] or -math.huge -- never fired: no cooldown to wait out
end

function SessionRegistry:setLastFire(userId: number, now: number)
	self._lastFire[userId] = now
end

function SessionRegistry:hasBuiltResearchMine(userId: number): boolean
	return self._researchMineBuilt[userId] == true
end

function SessionRegistry:setBuiltResearchMine(userId: number, value: boolean)
	self._researchMineBuilt[userId] = value
end

function SessionRegistry:lastVeinMine(userId: number, veinId: string): number
	local cooldowns = self._veinCooldowns[userId]
	return (cooldowns and cooldowns[veinId]) or -math.huge -- never mined: no cooldown to wait out
end

function SessionRegistry:setLastVeinMine(userId: number, veinId: string, now: number)
	local cooldowns = self._veinCooldowns[userId]
	if not cooldowns then
		cooldowns = {}
		self._veinCooldowns[userId] = cooldowns
	end
	cooldowns[veinId] = now
end

-- Call on PlayerRemoving, once this is wired into a real bootstrap: nothing
-- here should outlive the connection it belongs to.
function SessionRegistry:release(userId: number)
	self._production[userId] = nil
	self._embarked[userId] = nil
	self._restored[userId] = nil
	self._unlimitedMoney[userId] = nil
	self._asteroids[userId] = nil
	self._lastFire[userId] = nil
	self._nextAsteroidId[userId] = nil
	self._researchMineBuilt[userId] = nil
	self._veinCooldowns[userId] = nil
end

return SessionRegistry
