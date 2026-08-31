--!strict
-- The ONLY file allowed to assemble use cases from ports. Deliberately
-- Roblox-API-free: it takes ports as an argument instead of requiring an
-- Adapter module itself, which is what lets an integration test mount this
-- exact production wiring with fake ports (see DEVELOPMENT.md's "Integration
-- tests mount the real container with fake ports"). Picking which concrete
-- adapter backs a port (DataStore vs in-memory, ...) is Bootstrap's job, not
-- this file's.

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

local Grid = require(fromShared("Domain/Grid/Grid"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local Simulation = require(fromShared("Domain/Production/Simulation"))
local Orbit = require(fromShared("Domain/Production/Orbit"))
local Rebirth = require(fromShared("Domain/Rebirth/Rebirth"))
local Profile = require(fromShared("Domain/Profile/Profile"))
local Railgun = require(fromShared("Domain/Mining/Railgun"))
local AsteroidTiers = require(fromShared("Domain/Mining/AsteroidTiers"))
local ResearchMine = require(fromShared("Domain/Research/ResearchMine"))
local Vein = require(fromShared("Domain/Research/Vein"))
local SpendCredits = require("../Application/UseCases/SpendCredits")
local AddCredits = require("../Application/UseCases/AddCredits")
local PlaceModule = require("../Application/UseCases/PlaceModule")
local RemoveModule = require("../Application/UseCases/RemoveModule")
local UpgradeModule = require("../Application/UseCases/UpgradeModule")
local MoveModule = require("../Application/UseCases/MoveModule")
local RestoreStation = require("../Application/UseCases/RestoreStation")
local EmbarkStation = require("../Application/UseCases/EmbarkStation")
local ReturnToLobby = require("../Application/UseCases/ReturnToLobby")
local RunProductionTick = require("../Application/UseCases/RunProductionTick")
local CheckObjectiveProgress = require("../Application/UseCases/CheckObjectiveProgress")
local RebirthStation = require("../Application/UseCases/RebirthStation")
local DevSetPass = require("../Application/UseCases/DevSetPass")
local DevSetRebirths = require("../Application/UseCases/DevSetRebirths")
local DevSetUnlimitedMoney = require("../Application/UseCases/DevSetUnlimitedMoney")
local DevResetAll = require("../Application/UseCases/DevResetAll")
local PurchaseRailgun = require("../Application/UseCases/PurchaseRailgun")
local RunMiningTick = require("../Application/UseCases/RunMiningTick")
local FireRailgun = require("../Application/UseCases/FireRailgun")
local UnlockResearchMine = require("../Application/UseCases/UnlockResearchMine")
local RestoreResearchMine = require("../Application/UseCases/RestoreResearchMine")
local MineVein = require("../Application/UseCases/MineVein")
local SellOres = require("../Application/UseCases/SellOres")

export type Ports = {
	profileRepository: any, -- Ports.ProfileRepository
	stationRepository: any, -- Ports.StationRepository
	clock: any, -- Ports.Clock
	statsPublisher: any, -- Ports.StatsPublisher
	notifier: any, -- Ports.Notifier
	sceneBuilder: any, -- Ports.SceneBuilder
	teleporter: any, -- Ports.Teleporter
	asteroidField: any, -- Ports.AsteroidField
}

-- Plain balance numbers, not ports: there is nothing to swap an
-- implementation of here, just production Balance vs a test's own fixture
-- (see CLAUDE.md's "domain specs use their own fixtures").
export type Rules = {
	grid: Grid.Rules,
	refundRatio: number,
	upgrade: ModuleCatalog.UpgradeRules,
	orbit: Orbit.Rules,
	heat: Simulation.HeatRules,
	resourceValues: Simulation.ResourceValues,
	rebirth: Rebirth.Rules,
	startingCredits: number, -- what RebirthStation resets credits back to
	profileRules: Profile.Rules, -- what DevResetAll rebuilds a blank profile with
	unlimitedMoneyCeiling: number, -- dev-only, see DevSetUnlimitedMoney
	railgun: Railgun.Rules,
	asteroidTiers: AsteroidTiers.Rules,
	asteroidLifetime: number, -- seconds an asteroid is shootable before it flies past
	researchMine: ResearchMine.Rules,
	vein: Vein.Rules,
}

export type Container = {
	ports: Ports,
	sessionRegistry: any,
	development: boolean,
	useCases: {
		spendCredits: any,
		addCredits: any,
		placeModule: any,
		removeModule: any,
		upgradeModule: any,
		moveModule: any,
		restoreStation: any,
		embarkStation: any,
		returnToLobby: any,
		runProductionTick: any,
		checkObjectiveProgress: any,
		rebirthStation: any,
		purchaseRailgun: any,
		runMiningTick: any,
		fireRailgun: any,
		unlockResearchMine: any,
		restoreResearchMine: any,
		mineVein: any,
		sellOres: any,
		-- Only present when built with development = true:
		devSetPass: any?,
		devSetRebirths: any?,
		devSetUnlimitedMoney: any?,
		devResetAll: any?,
	},
}

local Container = {}
Container.__index = Container

-- sessionRegistry isn't a port (no alternative implementation is ever
-- swapped in, see Application/SessionRegistry.luau's header) but it IS
-- shared, mutable state that several use cases must operate on the SAME
-- instance of -- so, like ports, it's handed in rather than constructed
-- here.
function Container.new(
	options: {
		ports: Ports,
		rules: Rules,
		sessionRegistry: any,
		-- Decided once in Bootstrap via RunService:IsStudio() (see CLAUDE.md's
		-- "development-only affordances" rule) -- never inferred here.
		development: boolean?,
	}
): Container
	local ports = options.ports
	local rules = options.rules
	local sessionRegistry = options.sessionRegistry

	-- Built separately, ahead of the table below: embarkStation depends on
	-- this exact instance (not a fresh one), since it's the one whose
	-- SessionRegistry-gated call must actually run.
	local restoreStation = setmetatable({
		profileRepository = ports.profileRepository,
		stationRepository = ports.stationRepository,
		sceneBuilder = ports.sceneBuilder,
		gridRules = rules.grid,
	}, RestoreStation)

	local restoreResearchMine = setmetatable({
		profileRepository = ports.profileRepository,
		sceneBuilder = ports.sceneBuilder,
	}, RestoreResearchMine)

	-- Each use case gets its OWN dependency table, built fresh here rather
	-- than cloned from one shared bag: what matters is that no two use
	-- cases share the same table before setmetatable() runs on it (that
	-- would make the metatable set last silently win for both). The
	-- repository/registry/publisher instances inside are still the same
	-- shared objects across use cases, which is correct -- they must
	-- operate on the same session state.
	local useCases = {
		spendCredits = setmetatable({
			profileRepository = ports.profileRepository,
			statsPublisher = ports.statsPublisher,
		}, SpendCredits),

		addCredits = setmetatable({
			profileRepository = ports.profileRepository,
			statsPublisher = ports.statsPublisher,
		}, AddCredits),

		placeModule = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			statsPublisher = ports.statsPublisher,
			notifier = ports.notifier,
			sceneBuilder = ports.sceneBuilder,
			gridRules = rules.grid,
			capacityPerRadiator = rules.heat.capacityPerRadiator,
		}, PlaceModule),

		removeModule = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			statsPublisher = ports.statsPublisher,
			sceneBuilder = ports.sceneBuilder,
			refundRatio = rules.refundRatio,
		}, RemoveModule),

		upgradeModule = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			statsPublisher = ports.statsPublisher,
			sceneBuilder = ports.sceneBuilder,
			upgradeRules = rules.upgrade,
		}, UpgradeModule),

		moveModule = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			sceneBuilder = ports.sceneBuilder,
			gridRules = rules.grid,
		}, MoveModule),

		restoreStation = restoreStation,

		embarkStation = setmetatable({
			sessionRegistry = sessionRegistry,
			statsPublisher = ports.statsPublisher,
			sceneBuilder = ports.sceneBuilder,
			teleporter = ports.teleporter,
			restoreStation = restoreStation,
			restoreResearchMine = restoreResearchMine,
		}, EmbarkStation),

		returnToLobby = setmetatable({
			statsPublisher = ports.statsPublisher,
			teleporter = ports.teleporter,
		}, ReturnToLobby),

		runProductionTick = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			sessionRegistry = sessionRegistry,
			statsPublisher = ports.statsPublisher,
			clock = ports.clock,
			orbitRules = rules.orbit,
			heatRules = rules.heat,
			resourceValues = rules.resourceValues,
			upgradeRules = rules.upgrade,
			rebirthRules = rules.rebirth,
			unlimitedMoneyCeiling = rules.unlimitedMoneyCeiling,
		}, RunProductionTick),

		checkObjectiveProgress = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			sessionRegistry = sessionRegistry,
			statsPublisher = ports.statsPublisher,
			notifier = ports.notifier,
		}, CheckObjectiveProgress),

		rebirthStation = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			sceneBuilder = ports.sceneBuilder,
			statsPublisher = ports.statsPublisher,
			startingCredits = rules.startingCredits,
			rebirthRules = rules.rebirth,
		}, RebirthStation),

		purchaseRailgun = setmetatable({
			profileRepository = ports.profileRepository,
			statsPublisher = ports.statsPublisher,
			railgunRules = rules.railgun,
		}, PurchaseRailgun),

		runMiningTick = setmetatable({
			profileRepository = ports.profileRepository,
			sessionRegistry = sessionRegistry,
			asteroidField = ports.asteroidField,
			clock = ports.clock,
			railgunRules = rules.railgun,
			tierRules = rules.asteroidTiers,
			asteroidLifetime = rules.asteroidLifetime,
		}, RunMiningTick),

		fireRailgun = setmetatable({
			profileRepository = ports.profileRepository,
			sessionRegistry = sessionRegistry,
			asteroidField = ports.asteroidField,
			statsPublisher = ports.statsPublisher,
			notifier = ports.notifier,
			clock = ports.clock,
			railgunRules = rules.railgun,
			tierRules = rules.asteroidTiers,
		}, FireRailgun),

		unlockResearchMine = setmetatable({
			profileRepository = ports.profileRepository,
			statsPublisher = ports.statsPublisher,
			sceneBuilder = ports.sceneBuilder,
			researchRules = rules.researchMine,
		}, UnlockResearchMine),

		restoreResearchMine = restoreResearchMine,

		mineVein = setmetatable({
			profileRepository = ports.profileRepository,
			sessionRegistry = sessionRegistry,
			statsPublisher = ports.statsPublisher,
			clock = ports.clock,
			veinRules = rules.vein,
		}, MineVein),

		sellOres = setmetatable({
			profileRepository = ports.profileRepository,
			statsPublisher = ports.statsPublisher,
			notifier = ports.notifier,
		}, SellOres),
	}

	-- Dev-only affordances, never present in production: see CLAUDE.md's
	-- rule that these must be appended by the container, only in
	-- development mode, going through the exact same use-case path a real
	-- purchase (or, for DevSetUnlimitedMoney/DevSetRebirths/DevResetAll,
	-- nothing real at all -- there is no player-facing equivalent) would.
	if options.development then
		local castUseCases = useCases :: any
		castUseCases.devSetPass = setmetatable({
			profileRepository = ports.profileRepository,
			statsPublisher = ports.statsPublisher,
			rebirthRules = rules.rebirth,
		}, DevSetPass)
		castUseCases.devSetRebirths = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			sceneBuilder = ports.sceneBuilder,
			statsPublisher = ports.statsPublisher,
			startingCredits = rules.startingCredits,
			rebirthRules = rules.rebirth,
		}, DevSetRebirths)
		castUseCases.devSetUnlimitedMoney = setmetatable({
			sessionRegistry = sessionRegistry,
		}, DevSetUnlimitedMoney)
		castUseCases.devResetAll = setmetatable({
			profileRepository = ports.profileRepository,
			stationRepository = ports.stationRepository,
			sceneBuilder = ports.sceneBuilder,
			statsPublisher = ports.statsPublisher,
			profileRules = rules.profileRules,
		}, DevResetAll)
	end

	return setmetatable({
		ports = ports,
		sessionRegistry = sessionRegistry,
		useCases = useCases,
		development = options.development == true,
	}, Container) :: any
end

return Container
