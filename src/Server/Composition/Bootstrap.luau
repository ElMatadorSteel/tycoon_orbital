--!strict
-- The real production entry point, wired live via src/Server/Bootstrap.
-- server.luau -- see CLAUDE.md's "Migration status" for the cutover this
-- completed.

local Players = game:GetService("Players")

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

	local gridRules = {
		cellSize = Balance.Grid.CellSize,
		radius = Balance.Grid.Radius,
	}

	local sceneBuilder = StationSceneBuilder.new({
		gridRules = gridRules,
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

	local container = Container.new({
		ports = {
			profileRepository = profileRepository,
			stationRepository = stationRepository,
			clock = clock,
			statsPublisher = AttributeStatsPublisher.new(),
			notifier = RemoteNotifier.new(),
			sceneBuilder = sceneBuilder,
			teleporter = teleporter,
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
		},
	})

	RemoteBindings.bind(container)

	-- The passerelle du lobby: this, and only this, is where a plot is ever
	-- claimed.
	launchPrompt.Triggered:Connect(function(player: Player)
		container.useCases.embarkStation:run(player.UserId)
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

		container.useCases.returnToLobby:run(player.UserId)
	end

	for _, player in Players:GetPlayers() do
		welcome(player)
	end
	Players.PlayerAdded:Connect(welcome)

	Players.PlayerRemoving:Connect(function(player: Player)
		local userId = player.UserId
		-- Every mutation already saves immediately (see e.g.
		-- PlaceModule/SpendCredits) -- this re-save is a safety net, not the
		-- only write, unlike the legacy SaveService's 3-moments-only design.
		profileRepository:save(userId, profileRepository:load(userId))
		profileRepository:release(userId)
		stationRepository:release(userId)
		sceneBuilder:releasePlot(userId)
		container.sessionRegistry:release(userId)
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

	return container
end

return Bootstrap
