--!strict
-- The contracts Application depends on, as types. Implemented once by a
-- Roblox adapter in production, once by a fake in tests -- see
-- ARCHITECTURE.md's Ports table. Only the ports this slice actually needs
-- are declared here; Marketplace is added when the systems that need it
-- are ported, not speculatively.

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Server and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach -- confirmed the first time
-- Rojo actually connected Studio (see CLAUDE.md's cutover notes). Lune has
-- no `game`, so the fallback below -- an ordinary relative require -- is
-- what actually runs there, unchanged from before.
local function fromShared(path: string): any
	if game then
		local node: any = (game :: any):GetService("ReplicatedStorage").Shared
		for segment in path:gmatch("[^/]+") do
			node = node[segment]
		end
		return node
	end
	return "../../Shared/" .. path
end

local Profile = require(fromShared("Domain/Profile/Profile"))
local Placement = require(fromShared("Domain/Station/Placement"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
type Profile = Profile.Profile
type Station = Placement.Station
type ModulePlacement = Placement.ModulePlacement

-- load() always returns a usable Profile -- blank on "nothing stored" AND
-- on a failed read, matching the legacy SaveService:_load fallback. On a
-- genuine read failure the repository also marks that user frozen
-- internally, so a subsequent save() returns false and writes nothing: "a
-- failed load never overwrites a save" (ARCHITECTURE.md).
export type ProfileRepository = {
	load: (self: ProfileRepository, userId: number) -> Profile,
	save: (self: ProfileRepository, userId: number, profile: Profile) -> boolean,
}

-- load() always returns a usable Station -- the core already placed, on
-- "nothing stored" too (see Domain/Station/Placement.initial()). Unlike
-- ProfileRepository, station state is never itself durably persisted: only
-- profile.modules is (kept in sync by StationProfileSync on every change),
-- matching the legacy StationService, whose per-player station table was
-- always in-memory only.
export type StationRepository = {
	load: (self: StationRepository, userId: number) -> Station,
	save: (self: StationRepository, userId: number, station: Station) -> (),
}

-- Two readings, not one, per ARCHITECTURE.md's "two clocks, not one":
-- now() is an absolute epoch -- a save's `savedAt` must survive a
-- disconnection, which a monotonic clock cannot promise. monotonic() is for
-- durations that only make sense within a session (the orbital phase):
-- using the wall clock there breaks the moment the system time moves.
export type Clock = {
	now: (self: Clock) -> number,
	monotonic: (self: Clock) -> number,
}

-- State replicates through attributes, not RemoteEvents (ARCHITECTURE.md):
-- less traffic, no possible desync between a snapshot and an event, and the
-- live state is readable in the Studio explorer while playing. `snapshot`
-- is one of Application/Snapshot.luau's builders -- only the fields being
-- published this call, never a full replace of everything the client knows.
export type StatsPublisher = {
	publish: (self: StatsPublisher, userId: number, snapshot: { [string]: any }) -> (),
}

-- For one-off messages a player should see once, not persistent state: a
-- "+150" gain popup, a completed-objective banner. Kept separate from
-- StatsPublisher on purpose -- these still make sense as an event even in
-- an attributes-first design (ARCHITECTURE.md's Ports table backs this one
-- with a remote event in production, not an attribute).
export type Notifier = {
	notify: (self: Notifier, userId: number, kind: string, payload: any) -> (),
}

-- Materialises what the Domain/Application layers only ever decided about:
-- the actual 3D plot and module Instances. A ModulePlacement deliberately
-- carries no Model reference (see Domain/Station/Placement.luau), so this
-- port -- and only this port -- is where "which Instance backs this
-- placement" lives. claimPlot returns false when every plot is occupied
-- (matching the legacy "Toutes les stations sont occupées"); it is
-- idempotent for a user who already claimed one this session.
export type SceneBuilder = {
	claimPlot: (self: SceneBuilder, userId: number) -> boolean,
	releasePlot: (self: SceneBuilder, userId: number) -> (),
	placeModule: (
		self: SceneBuilder,
		userId: number,
		placement: ModulePlacement,
		definition: ModuleCatalog.ModuleDef
	) -> (),
	removeModule: (self: SceneBuilder, userId: number, x: number, y: number) -> (),
	setModuleLevel: (self: SceneBuilder, userId: number, x: number, y: number, level: number) -> (),
	-- The research mine: the pad itself is built with the plot (claimPlot),
	-- locked, and wired to fire researchPadTouched (a Signal, not a direct
	-- use-case call -- an Adapter invoking Application would invert the
	-- dependency rule) when its OWNER steps on it. buildResearchMine is what
	-- a successful UnlockResearchMine resolves to (idempotent: also what
	-- RestoreResearchMine calls on every reconnection of an owner);
	-- refuseResearchMine is what an unaffordable attempt resolves to instead.
	buildResearchMine: (self: SceneBuilder, userId: number) -> boolean,
	hasResearchMine: (self: SceneBuilder, userId: number) -> boolean,
	refuseResearchMine: (self: SceneBuilder, userId: number) -> (),
	-- The shovel: putting the tool in the player's hands, and the two ways
	-- its pad answers. grantShovel returns false when the player is not
	-- connected -- the profile still carries the unlock, so the next join
	-- hands it over (see RestoreStation).
	grantShovel: (self: SceneBuilder, userId: number) -> boolean,
	markShovelUnlocked: (self: SceneBuilder, userId: number) -> (),
	refuseShovel: (self: SceneBuilder, userId: number) -> (),
}

-- Moves a player's character -- to the lobby, or to their claimed station.
-- Deliberately just two named actions, not a generic "go to this CFrame":
-- Application never has a CFrame to hand it (no Roblox datatypes here),
-- and the two destinations this game actually has are exactly these.
export type Teleporter = {
	sendToLobby: (self: Teleporter, userId: number) -> (),
	sendToStation: (self: Teleporter, userId: number) -> (),
}

-- Applies a movement decision to the character. Separate from Teleporter --
-- that one moves a body to a place, this one changes how the body moves --
-- and, like it, deliberately not a generic "set any Humanoid property":
-- Application has no Humanoid to hand it and no business knowing there is
-- one.
--
-- The implementation is expected to REMEMBER the commanded speed and
-- re-apply it whenever the character is rebuilt. WalkSpeed lives on the
-- Humanoid, which dies with every respawn and every trip to the lobby, so
-- an actuator that only wrote once would be forgotten almost immediately.
-- release() drops that memory, on PlayerRemoving.
export type MovementActuator = {
	setWalkSpeed: (self: MovementActuator, userId: number, speed: number) -> (),
	release: (self: MovementActuator, userId: number) -> (),
}

-- The Railgun mining side-feature's asteroid visuals. Deliberately just
-- spawn/despawn -- no "onExpire" callback: lifetime/expiry is decided
-- authoritatively by RunMiningTick comparing spawnedAt against the clock
-- every tick and calling despawn itself, not by the adapter's own tween
-- completion. This keeps the adapter dumb (cosmetic movement only) and the
-- timing rule testable with a fake clock, same reasoning as SceneBuilder
-- never owning placement rules itself.
export type AsteroidField = {
	spawn: (self: AsteroidField, userId: number, asteroidId: string, tier: string) -> (),
	despawn: (self: AsteroidField, userId: number, asteroidId: string) -> (),
}

return {}
