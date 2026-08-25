--!strict
-- Mounts the REAL Composition/Container.luau with fake ports: this is what
-- proves the production wiring works, not just that the Domain rules are
-- right in isolation (DEVELOPMENT.md).
local Container = require(Composition.Container)

local RULES = { startingCredits = 500, maxModules = 100, maxLevel = 5 }

describe("Profile + Economy integration (real Container, fake ports)", function()
	local container
	local statsPublisher

	beforeEach(function()
		local clock = Fakes.TestClock.new(1000)
		local profileRepository = Fakes.InMemoryProfileRepository.new(clock, RULES)
		local stationRepository = Fakes.InMemoryStationRepository.new()
		statsPublisher = Fakes.RecordingStatsPublisher.new()
		container = Container.new({
			ports = {
				profileRepository = profileRepository,
				stationRepository = stationRepository,
				clock = clock,
				statsPublisher = statsPublisher,
				notifier = Fakes.RecordingNotifier.new(),
				sceneBuilder = Fakes.RecordingSceneBuilder.new(),
				teleporter = Fakes.RecordingTeleporter.new(),
			},
			sessionRegistry = Application.SessionRegistry.new(),
			rules = {
				grid = { cellSize = 8, radius = 12 },
				refundRatio = 0.5,
				upgrade = {
					maxLevel = RULES.maxLevel,
					gainPerLevel = 0.35,
					costFactor = 1.8,
					minCost = 250,
				},
				orbit = { period = 180, eclipseFraction = 0.3 },
				heat = { baseCapacity = 40, capacityPerRadiator = 60, overheatPenalty = 0.55 },
				resourceValues = { Ore = 5, Alloy = 22, Component = 75 },
			},
		})
	end)

	it("spends credits and persists the new balance", function()
		local userId = 42

		local spendResult = container.useCases.spendCredits:run(userId, 100)
		expect(spendResult.ok).toBe(true)
		expect((spendResult :: any).value).toBe(RULES.startingCredits - 100)

		local reloaded = container.ports.profileRepository:load(userId)
		expect(reloaded.credits).toBe(RULES.startingCredits - 100)
		expect(statsPublisher:latest(userId).Credits).toBe(RULES.startingCredits - 100)
	end)

	it("refuses to spend more than the balance and leaves it untouched", function()
		local userId = 7
		local result = container.useCases.spendCredits:run(userId, RULES.startingCredits + 1)
		expect(result.ok).toBe(false)

		local reloaded = container.ports.profileRepository:load(userId)
		expect(reloaded.credits).toBe(RULES.startingCredits)
		-- A refused spend publishes nothing: there is nothing new to tell the
		-- client.
		expect(statsPublisher:latest(userId).Credits).toBeNil()
	end)

	it("adds credits and persists the new balance", function()
		local userId = 99
		local newBalance = container.useCases.addCredits:run(userId, 250)
		expect(newBalance).toBe(RULES.startingCredits + 250)

		local reloaded = container.ports.profileRepository:load(userId)
		expect(reloaded.credits).toBe(RULES.startingCredits + 250)
	end)

	it("clones dependencies per use case instead of sharing one metatable", function()
		-- Regression guard for ARCHITECTURE.md's "dependencies are cloned,
		-- not shared": setting a metatable on the caller's ports table
		-- directly would make the last use case built silently win for all
		-- of them.
		local spendMeta = getmetatable(container.useCases.spendCredits)
		local addMeta = getmetatable(container.useCases.addCredits)
		expect(spendMeta ~= addMeta).toBeTruthy()
	end)
end)
