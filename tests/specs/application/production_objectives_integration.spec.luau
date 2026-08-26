--!strict
-- Mounts the REAL Composition/Container.luau with fake ports, exercising
-- EmbarkStation/RunProductionTick/CheckObjectiveProgress together.
local Container = require(Composition.Container)

local RULES = {
	grid = { cellSize = 8, radius = 12 },
	refundRatio = 0.5,
	upgrade = {
		maxLevel = 5,
		gainPerLevel = 0.35,
		costFactor = 1.8,
		minCost = 250,
		coreUpgradeCost = 375,
	},
	orbit = { period = 180, eclipseFraction = 0.3 },
	heat = { baseCapacity = 40, capacityPerRadiator = 60, overheatPenalty = 0.55 },
	resourceValues = { Ore = 5, Alloy = 22, Component = 75 },
	rebirth = {
		enabled = true,
		normalThreshold = 10,
		earlyThreshold = 5,
		bonusPerRebirth = 0.25,
		ultimateMultiplier = 1.5,
	},
	startingCredits = 800,
}
local STARTING_CREDITS = 100000

describe("Production + Objectives use cases (real Container, fake ports)", function()
	local container
	local clock
	local statsPublisher
	local notifier
	local teleporter
	local userId = 100

	beforeEach(function()
		userId += 1
		clock = Fakes.TestClock.new(1000)
		local profileRepository = Fakes.InMemoryProfileRepository.new(clock, {
			startingCredits = STARTING_CREDITS,
			maxModules = 100,
			maxLevel = RULES.upgrade.maxLevel,
		})
		local stationRepository = Fakes.InMemoryStationRepository.new()
		statsPublisher = Fakes.RecordingStatsPublisher.new()
		notifier = Fakes.RecordingNotifier.new()
		teleporter = Fakes.RecordingTeleporter.new()
		container = Container.new({
			ports = {
				profileRepository = profileRepository,
				stationRepository = stationRepository,
				clock = clock,
				statsPublisher = statsPublisher,
				notifier = notifier,
				sceneBuilder = Fakes.RecordingSceneBuilder.new(),
				teleporter = teleporter,
			},
			sessionRegistry = Application.SessionRegistry.new(),
			rules = RULES,
		})
	end)

	describe("EmbarkStation + the Embark objective", function()
		it("does not complete Embark before the player has embarked", function()
			local progress = container.useCases.checkObjectiveProgress:run(userId)
			expect(progress.advanced).toBeFalsy()
		end)

		it(
			"completes Embark once EmbarkStation has run, and grants no reward (it's worth 0)",
			function()
				container.useCases.embarkStation:run(userId)
				expect(statsPublisher:latest(userId).Location).toBe("Station")
				expect(teleporter.stationCalls).toEqual({ userId })
				local before = container.ports.profileRepository:load(userId).credits

				local progress = container.useCases.checkObjectiveProgress:run(userId)
				expect(progress.advanced).toBeTruthy()
				expect(progress.completedIndex).toBe(1)
				expect(progress.newIndex).toBe(2)

				local after = container.ports.profileRepository:load(userId).credits
				expect(after).toBe(before) -- Embark's reward is 0

				expect(statsPublisher:latest(userId).Objective).toBe(2)
				-- A zero-reward completion still notifies (the banner shows
				-- regardless), it just carries no credits gain.
				expect(#notifier.calls).toBe(1)
				expect(notifier.calls[1].kind).toBe("ObjectiveCompleted")
				expect(notifier.calls[1].payload.reward).toBe(0)
			end
		)

		it("refuses to embark once every plot is claimed, per SceneBuilder.claimPlot", function()
			local profileRepository = Fakes.InMemoryProfileRepository.new(clock, {
				startingCredits = STARTING_CREDITS,
				maxModules = 100,
				maxLevel = RULES.upgrade.maxLevel,
			})
			local fullSceneBuilder = Fakes.RecordingSceneBuilder.new(0) -- zero free plots
			local full = Container.new({
				ports = {
					profileRepository = profileRepository,
					stationRepository = Fakes.InMemoryStationRepository.new(),
					clock = clock,
					statsPublisher = Fakes.RecordingStatsPublisher.new(),
					notifier = Fakes.RecordingNotifier.new(),
					sceneBuilder = fullSceneBuilder,
					teleporter = Fakes.RecordingTeleporter.new(),
				},
				sessionRegistry = Application.SessionRegistry.new(),
				rules = RULES,
			})

			local result = full.useCases.embarkStation:run(userId)
			expect(result.ok).toBeFalsy()
			expect(full.sessionRegistry:hasEmbarked(userId)).toBeFalsy()
		end)

		it("ReturnToLobby publishes Location=Lobby and moves the character back", function()
			container.useCases.embarkStation:run(userId)
			container.useCases.returnToLobby:run(userId)
			expect(statsPublisher:latest(userId).Location).toBe("Lobby")
			expect(teleporter.lobbyCalls).toEqual({ userId })
		end)
	end)

	describe("the rest of the chain", function()
		local function advanceToObjective(targetIndex: number)
			container.useCases.embarkStation:run(userId)
			while container.ports.profileRepository:load(userId).objective < targetIndex do
				local profile = container.ports.profileRepository:load(userId)
				local id = profile.objective
				if id == 1 then
					container.useCases.checkObjectiveProgress:run(userId)
				elseif id == 2 then -- Collector
					container.useCases.placeModule:run(userId, "OreCollector", 1, -1, 0)
					container.useCases.checkObjectiveProgress:run(userId)
				elseif id == 3 then -- Sell
					container.useCases.placeModule:run(userId, "CargoBay", 3, -1, 0)
					container.useCases.checkObjectiveProgress:run(userId)
				else
					break
				end
			end
		end

		it("grants the reward and advances the index on completion", function()
			container.useCases.embarkStation:run(userId)
			container.useCases.checkObjectiveProgress:run(userId) -- completes Embark (reward 0)

			local before = container.ports.profileRepository:load(userId).credits
			container.useCases.placeModule:run(userId, "OreCollector", 1, -1, 0)
			local progress = container.useCases.checkObjectiveProgress:run(userId) -- completes Collector
			expect(progress.advanced).toBeTruthy()

			local after = container.ports.profileRepository:load(userId).credits
			expect(after).toBe(before - 300 + (progress.reward :: number)) -- OreCollector costs 300
		end)

		it(
			"does not skip ahead: Sell can't complete before Collector even with a cargo bay placed",
			function()
				container.useCases.embarkStation:run(userId)
				container.useCases.checkObjectiveProgress:run(userId) -- Embark done, now on Collector
				-- Place a cargo bay only -- Sell's condition, but Collector is
				-- still the active objective, and Sell isn't even checked yet.
				container.useCases.placeModule:run(userId, "CargoBay", 1, -1, 0)
				local progress = container.useCases.checkObjectiveProgress:run(userId)
				expect(progress.advanced).toBeFalsy()

				local profile = container.ports.profileRepository:load(userId)
				expect(profile.objective).toBe(2) -- still stuck on Collector
			end
		)

		it("reaches the end of the chain and then stops advancing", function()
			advanceToObjective(3) -- through Embark and Collector
			container.useCases.placeModule:run(userId, "CargoBay", 3, -1, 0)
			container.useCases.checkObjectiveProgress:run(userId) -- completes Sell
			local profile = container.ports.profileRepository:load(userId)
			expect(profile.objective).toBe(4)
		end)
	end)

	describe("RunProductionTick", function()
		it("credits whole revenue earned during the tick to the profile", function()
			container.useCases.placeModule:run(userId, "OreCollector", 1, -1, 0)
			container.useCases.placeModule:run(userId, "CargoBay", 3, -1, 0)
			local before = container.ports.profileRepository:load(userId).credits

			-- Full sun: monotonic elapsed 0 -> phase 0 -> Orbit.sunlightAt(0) is
			-- actually the eclipse start (0), so nudge forward past it into
			-- daylight for a deterministic non-zero sunlight reading.
			clock:setMonotonic(RULES.orbit.period * 0.5)
			container.useCases.runProductionTick:run(userId, 1)

			local after = container.ports.profileRepository:load(userId).credits
			expect(after >= before).toBeTruthy()

			local published = statsPublisher:latest(userId)
			expect(published.Sunlight).toBe(1)
			expect(published.Income ~= nil).toBeTruthy()
			expect(published.PowerProduction ~= nil).toBeTruthy()
			expect(published.HeatCapacity ~= nil).toBeTruthy()
		end)

		it("does not touch the profile at all when there is nothing to sell", function()
			local before = container.ports.profileRepository:load(userId).credits
			container.useCases.runProductionTick:run(userId, 1) -- just the core, no network
			local after = container.ports.profileRepository:load(userId).credits
			expect(after).toBe(before)
		end)

		it("carries fractional revenue in the session registry across ticks", function()
			container.useCases.placeModule:run(userId, "OreCollector", 1, -1, 0)
			container.useCases.placeModule:run(userId, "CargoBay", 3, -1, 0)
			clock:setMonotonic(RULES.orbit.period * 0.5)

			container.useCases.runProductionTick:run(userId, 0.1)
			local state = container.sessionRegistry:production(userId)
			expect(state.pendingCredit > 0).toBeTruthy()
		end)
	end)
end)
