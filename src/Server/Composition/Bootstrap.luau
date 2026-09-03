--!strict
-- The real production entry point, wired live via src/Server/Bootstrap.
-- server.luau -- see CLAUDE.md's "Migration status" for the cutover this
-- completed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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

local Balance = require(fromShared("Balance"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local Rebirth = require(fromShared("Domain/Rebirth/Rebirth"))
local ResearchMine = require(fromShared("Domain/Research/ResearchMine"))
local OreCatalog = require(fromShared("Domain/Research/OreCatalog"))
local Shovel = require(fromShared("Domain/Research/Shovel"))
local Container = require("./Container")
local RemoteBindings = require("./RemoteBindings")
local SessionRegistry = require("../Application/SessionRegistry")
local Snapshot = require("../Application/Snapshot")
local SystemClock = require("../Adapters/Roblox/SystemClock")
local DataStoreProfileRepository = require("../Adapters/Persistence/DataStoreProfileRepository")
local InMemoryStationRepository = require("../Adapters/Persistence/InMemoryStationRepository")
local AttributeStatsPublisher = require("../Adapters/Replication/AttributeStatsPublisher")
local RemoteNotifier = require("../Adapters/Replication/RemoteNotifier")
local StationSceneBuilder = require("../Adapters/Roblox/StationSceneBuilder")
local CharacterTeleporter = require("../Adapters/Roblox/CharacterTeleporter")
local AsteroidFieldRenderer = require("../Adapters/Roblox/AsteroidFieldRenderer")
local RailgunKioskBuilder = require("../Adapters/Roblox/RailgunKioskBuilder")
local HumanoidMovementActuator = require("../Adapters/Roblox/HumanoidMovementActuator")

-- Fails fast and loud: a half-wired lobby gives players who fall into the
-- void, much harder to diagnose than a startup error. Ported from the
-- legacy LobbyService:_resolve's `expect`.
local function expect(parent: Instance, name: string, className: string): Instance
	local child = parent:FindFirstChild(name)
	if not child or not child:IsA(className) then
		error(
			`[Bootstrap] {parent:GetFullName()}.{name} ({className}) missing. `
				.. `Has the lobby scenery been renamed or removed in Studio?`,
			0
		)
	end
	return child
end

local Bootstrap = {}

function Bootstrap.start()
	local clock = SystemClock.new()

	local profileRules = {
		startingCredits = Balance.Economy.StartingCredits,
		maxModules = Balance.Save.MaxModules,
		maxLevel = Balance.Upgrade.MaxLevel,
	}

	local profileRepository = DataStoreProfileRepository.new({
		storeName = Balance.Save.StoreName,
		retryCount = Balance.Save.RetryCount,
		retryDelay = Balance.Save.RetryDelay,
	}, clock, profileRules)

	if not profileRepository:isAvailable() then
		warn(
			"[Bootstrap] DataStore unavailable -- memory-only for this session. "
				.. "Enable Game Settings > Security > Enable Studio Access to API Services."
		)
	end

	-- Station state is never itself durably persisted, in production either
	-- -- only profile.modules is (see Ports.StationRepository). In-memory is
	-- therefore the real adapter here, not just a fallback.
	local stationRepository = InMemoryStationRepository.new()

	local resourceValues = {}
	for id, resource in ModuleCatalog.Resources do
		resourceValues[id] = resource.value
	end

	local rebirthRules = {
		enabled = Balance.Rebirth.Enabled,
		normalThreshold = Balance.Rebirth.NormalThreshold,
		earlyThreshold = Balance.Rebirth.EarlyThreshold,
		bonusPerRebirth = Balance.Rebirth.BonusPerRebirth,
		ultimateMultiplier = Balance.Rebirth.UltimateMultiplier,
	}

	local gridRules = {
		cellSize = Balance.Grid.CellSize,
		radius = Balance.Grid.Radius,
	}

	local sceneBuilder = StationSceneBuilder.new({
		gridRules = gridRules,
		maxLevel = Balance.Upgrade.MaxLevel,
		layoutRules = {
			centerX = Balance.Lobby.Center.X,
			centerZ = Balance.Lobby.Center.Z,
			count = Balance.Plots.Count,
			distance = Balance.Plots.Distance,
			spread = Balance.Plots.Spread,
			altitude = Balance.Plots.Altitude,
		},
		plotsParent = workspace:WaitForChild("Plots"),
		stationsParent = workspace:WaitForChild("Stations"),
		researchMineCost = Balance.Research.Mine.Cost,
		shovelCost = Balance.Research.Shovel.Cost,
	})

	-- Lobby scene contract -- unchanged from the legacy LobbyService: the
	-- decor itself is hand-authored in Studio, only these four pieces are
	-- load-bearing.
	local scenery = expect(workspace, "Scenery", "Folder")
	local lobby = expect(scenery, "Lobby", "Folder")
	local lobbySpawn = expect(lobby, "LobbySpawn", "SpawnLocation") :: SpawnLocation
	-- Disabled for random spawn selection: assigned explicitly via
	-- RespawnLocation instead, so a box ticked by accident in Studio can't
	-- break where players land.
	lobbySpawn.Enabled = false
	local launchPad = expect(lobby, "LaunchPad", "BasePart") :: BasePart
	local launchPrompt = launchPad:FindFirstChildOfClass("ProximityPrompt")
	if not launchPrompt then
		error(`[Bootstrap] no ProximityPrompt in {launchPad:GetFullName()}`, 0)
	end

	local teleporter = CharacterTeleporter.new({
		lobbySpawn = lobbySpawn,
		sceneBuilder = sceneBuilder,
	})

	-- New content, not hand-authored scenery: created here rather than
	-- WaitForChild'd.
	local asteroidsParent: Instance = workspace:FindFirstChild("Asteroids") :: Instance
	if not asteroidsParent then
		local folder = Instance.new("Folder")
		folder.Name = "Asteroids"
		folder.Parent = workspace
		asteroidsParent = folder
	end

	local asteroidField = AsteroidFieldRenderer.new({
		sceneBuilder = sceneBuilder,
		asteroidsParent = asteroidsParent,
		lifetime = Balance.Mining.Railgun.AsteroidLifetime,
	})

	RailgunKioskBuilder.new({
		lobby = lobby,
		lobbySpawn = lobbySpawn,
		profileRepository = profileRepository,
	}):build()

	-- Watches PlayerAdded itself, so it must exist before anyone can join:
	-- built here rather than lazily on the first dev command.
	local movementActuator = HumanoidMovementActuator.new()

	local container = Container.new({
		ports = {
			profileRepository = profileRepository,
			stationRepository = stationRepository,
			clock = clock,
			statsPublisher = AttributeStatsPublisher.new(),
			notifier = RemoteNotifier.new(),
			sceneBuilder = sceneBuilder,
			teleporter = teleporter,
			asteroidField = asteroidField,
			movementActuator = movementActuator,
		},
		sessionRegistry = SessionRegistry.new(),
		rules = {
			grid = gridRules,
			refundRatio = Balance.Economy.RefundRatio,
			upgrade = {
				maxLevel = Balance.Upgrade.MaxLevel,
				gainPerLevel = Balance.Upgrade.GainPerLevel,
				costFactor = Balance.Upgrade.CostFactor,
				minCost = Balance.Upgrade.MinCost,
				coreUpgradeCost = Balance.Upgrade.CoreUpgradeCost,
			},
			orbit = {
				period = Balance.Orbit.Period,
				eclipseFraction = Balance.Orbit.EclipseFraction,
			},
			heat = {
				baseCapacity = Balance.Heat.BaseCapacity,
				capacityPerRadiator = Balance.Heat.CapacityPerRadiator,
				overheatPenalty = Balance.Heat.OverheatPenalty,
			},
			resourceValues = resourceValues,
			rebirth = rebirthRules,
			startingCredits = Balance.Economy.StartingCredits,
			profileRules = profileRules,
			unlimitedMoneyCeiling = Balance.Dev.UnlimitedMoneyCeiling,
			walkSpeed = {
				default = Balance.Dev.WalkSpeed.Default,
				min = Balance.Dev.WalkSpeed.Min,
				max = Balance.Dev.WalkSpeed.Max,
			},
			railgun = {
				cost = Balance.Mining.Railgun.Cost,
				cooldown = Balance.Mining.Railgun.Cooldown,
				maxActive = Balance.Mining.Railgun.MaxActive,
				spawnChancePerTick = Balance.Mining.Railgun.SpawnChancePerTick,
			},
			asteroidTiers = { tiers = Balance.Mining.Tiers },
			asteroidLifetime = Balance.Mining.Railgun.AsteroidLifetime,
			researchMine = { cost = Balance.Research.Mine.Cost },
			shovel = { cost = Balance.Research.Shovel.Cost },
			vein = { cooldown = Balance.Research.Vein.Cooldown },
		},
		development = RunService:IsStudio(),
	})

	RemoteBindings.bind(container)

	-- The passerelle du lobby: this, and only this, is where a plot is ever
	-- claimed.
	launchPrompt.Triggered:Connect(function(player: Player)
		container.useCases.embarkStation:run(player.UserId)
	end)

	-- The research pad, and only this, is where the mine is ever bought. The
	-- pads themselves come and go with the plots, so what is connected here
	-- is the scene builder's signal rather than any one Instance -- the same
	-- reason the launch prompt above can be a direct connection and this
	-- cannot.
	sceneBuilder.researchPadTouched:Connect(function(userId: number)
		container.useCases.unlockResearchMine:run(userId)
	end)

	-- The shovel's pad, down on the rim terrace of the player's own pit. Same
	-- shape as the one above and for the same reason: the pads come and go
	-- with the plots, so what is connected here is the signal, never an
	-- Instance.
	sceneBuilder.shovelPadTouched:Connect(function(userId: number)
		container.useCases.unlockShovel:run(userId)
	end)

	-- We load the character ourselves, once the spawn point is known --
	-- without this a player falls into the void.
	Players.CharacterAutoLoads = false

	local function welcome(player: Player)
		player.RespawnLocation = lobbySpawn
		player:LoadCharacter()

		-- RunProductionTick/CheckObjectiveProgress only publish Credits and
		-- Objective when they CHANGE (a tick with nothing to sell publishes
		-- neither) -- without this, a freshly-joined client would read nil
		-- off both attributes until the player's first sale or objective
		-- completion. This is the one place the full initial profile state
		-- gets pushed, once, on join.
		local profile = profileRepository:load(player.UserId)
		container.ports.statsPublisher:publish(player.UserId, Snapshot.credits(profile.credits))
		container.ports.statsPublisher:publish(player.UserId, Snapshot.objective(profile.objective))
		local hasUltimate = profile.unlocked[Rebirth.Passes.Ultimate] == true
		local hasEarlyPass = profile.unlocked[Rebirth.Passes.EarlyRebirth] == true
		local boost = Rebirth.multiplier(profile.rebirths, hasUltimate, rebirthRules)
		container.ports.statsPublisher:publish(
			player.UserId,
			Snapshot.rebirth(profile.rebirths, hasUltimate, hasEarlyPass, boost)
		)
		container.ports.statsPublisher:publish(
			player.UserId,
			Snapshot.mining(profile.unlocked.Railgun == true)
		)
		container.ports.statsPublisher:publish(
			player.UserId,
			Snapshot.research(ResearchMine.isUnlocked(profile.unlocked))
		)
		-- Every mineral, including the ones held at zero. The exchange panel
		-- lists the whole catalogue and reads each line off its attribute;
		-- publishing only what the player holds would leave the rest showing
		-- nil until their first sale.
		for _, ore in OreCatalog.Ores do
			container.ports.statsPublisher:publish(
				player.UserId,
				Snapshot.ore(ore.id, profile.ores[ore.id] or 0)
			)
		end
		container.ports.statsPublisher:publish(
			player.UserId,
			Snapshot.shovel(Shovel.isUnlocked(profile.unlocked))
		)

		container.useCases.returnToLobby:run(player.UserId)
	end

	for _, player in Players:GetPlayers() do
		welcome(player)
	end
	Players.PlayerAdded:Connect(welcome)

	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		-- Most mutations already save immediately (PlaceModule, SpendCredits,
		-- UpgradeModule, ...) -- this re-save is their safety net. It is the
		-- ONLY write for whatever production-tick revenue accrued since the
		-- last periodic autosave below, so it is load-bearing here in a way
		-- it isn't for the others.
		profileRepository:save(userId, profileRepository:load(userId))
		profileRepository:release(userId)
		stationRepository:release(userId)
		sceneBuilder:releasePlot(userId)
		container.sessionRegistry:release(userId)
		movementActuator:release(userId)
	end)

	-- The recurring simulation tick -- ported from ProductionService:Start's
	-- loop. Every connected player, every Config.Simulation.TickRate
	-- seconds; a bad tick for one player must not stop the loop for
	-- everyone else, same as legacy's per-player pcall.
	task.spawn(function()
		while true do
			local deltaTime = task.wait(Balance.Simulation.TickRate)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					container.useCases.runProductionTick:run(player.UserId, deltaTime)
					container.useCases.checkObjectiveProgress:run(player.UserId)
				end)
				if not ok then
					warn(`[Bootstrap] tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)

	-- The mining side-feature's own tick loop -- separate cadence from the
	-- production loop above. RunMiningTick itself no-ops for anyone without
	-- a Railgun.
	task.spawn(function()
		while true do
			task.wait(Balance.Mining.Railgun.TickRate)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(function()
					container.useCases.runMiningTick:run(player.UserId)
				end)
				if not ok then
					warn(`[Bootstrap] mining tick failed for {player.Name}: {err}`)
				end
			end
		end
	end)

	-- Periodic autosave -- ported from the legacy SaveService's third moment
	-- (the other two are PlayerRemoving above and every other use case's own
	-- immediate save). RunProductionTick deliberately does NOT save on its
	-- own (see its own header): a busy factory earns whole revenue on nearly
	-- every tick, and saving that often floods this key's real DataStore
	-- write budget, which then queues up and delays every OTHER action
	-- (upgrading, building, ...) that also needs to save. This loop is what
	-- actually persists accrued tick revenue, just on a sane cadence.
	task.spawn(function()
		while true do
			task.wait(Balance.Save.AutosaveInterval)
			for _, player in Players:GetPlayers() do
				local userId = player.UserId
				local ok, err = pcall(function()
					profileRepository:save(userId, profileRepository:load(userId))
				end)
				if not ok then
					warn(`[Bootstrap] autosave failed for {player.Name}: {err}`)
				end
			end
		end
	end)

	return container
end

return Bootstrap
