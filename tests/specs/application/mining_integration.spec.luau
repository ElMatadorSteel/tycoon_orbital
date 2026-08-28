--!strict
-- Mounts the REAL Composition/Container.luau with fake ports, exercising
-- PurchaseRailgun/RunMiningTick/FireRailgun together -- this is what proves
-- the three use cases are actually wired up in Container.luau and agree
-- with each other on SessionRegistry state, not just that the Domain rules
-- are right in isolation.
local Container = require(Composition.Container)

local RULES = {
	grid = { cellSize = 8, radius = 12 },
	refundRatio = 0.5,
	upgrade = {
		maxLevel = 10,
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
	profileRules = { startingCredits = 800, maxModules = 100, maxLevel = 10 },
	unlimitedMoneyCeiling = 999999999,
	railgun = { cost = 500, cooldown = 1.5, maxActive = 3, spawnChancePerTick = 0.12 },
	asteroidTiers = {
		tiers = {
			{
				id = "Common",
				name = "Astéroïde commun",
				weight = 60,
				minReward = 15,
				maxReward = 30,
			},
			{
				id = "Legendary",
				name = "Astéroïde légendaire",
				weight = 3,
				minReward = 900,
				maxReward = 1500,
			},
		},
	},
	asteroidLifetime = 8,
}
local STARTING_CREDITS = 100000

describe("Mining (real Container, fake ports)", function()
	local container
	local profileRepository
	local sessionRegistry
	local asteroidField
	local clock
	local userId = 2000

	beforeEach(function()
		userId += 1
		clock = Fakes.TestClock.new(1000)
		profileRepository = Fakes.InMemoryProfileRepository.new(clock, {
			startingCredits = STARTING_CREDITS,
			maxModules = 100,
			maxLevel = RULES.upgrade.maxLevel,
		})
		sessionRegistry = Application.SessionRegistry.new()
		asteroidField = Fakes.RecordingAsteroidField.new()
		container = Container.new({
			ports = {
				profileRepository = profileRepository,
				stationRepository = Fakes.InMemoryStationRepository.new(),
				clock = clock,
				statsPublisher = Fakes.RecordingStatsPublisher.new(),
				notifier = Fakes.RecordingNotifier.new(),
				sceneBuilder = Fakes.RecordingSceneBuilder.new(),
				teleporter = Fakes.RecordingTeleporter.new(),
				asteroidField = asteroidField,
			},
			sessionRegistry = sessionRegistry,
			rules = RULES,
		})
	end)

	describe("PurchaseRailgun", function()
		it("spends credits and sets the flag", function()
			local result = container.useCases.purchaseRailgun:run(userId)
			expect(result.ok).toBeTruthy()

			local profile = profileRepository:load(userId)
			expect(profile.credits).toBe(STARTING_CREDITS - RULES.railgun.cost)
			expect(profile.unlocked.Railgun).toBe(true)
		end)

		it("refuses without enough credits, spending nothing", function()
			local poor = Fakes.InMemoryProfileRepository.new(
				clock,
				{ startingCredits = 10, maxModules = 100, maxLevel = 10 }
			)
			local poorContainer = Container.new({
				ports = {
					profileRepository = poor,
					stationRepository = Fakes.InMemoryStationRepository.new(),
					clock = clock,
					statsPublisher = Fakes.RecordingStatsPublisher.new(),
					notifier = Fakes.RecordingNotifier.new(),
					sceneBuilder = Fakes.RecordingSceneBuilder.new(),
					teleporter = Fakes.RecordingTeleporter.new(),
					asteroidField = Fakes.RecordingAsteroidField.new(),
				},
				sessionRegistry = Application.SessionRegistry.new(),
				rules = RULES,
			})

			local result = poorContainer.useCases.purchaseRailgun:run(userId)
			expect(result.ok).toBeFalsy()
			expect(poor:load(userId).credits).toBe(10)
			expect(poor:load(userId).unlocked.Railgun).toBeFalsy()
		end)

		it("refuses a second purchase once already owned", function()
			container.useCases.purchaseRailgun:run(userId)
			local result = container.useCases.purchaseRailgun:run(userId)
			expect(result.ok).toBeFalsy()
		end)
	end)

	describe("RunMiningTick", function()
		it("does nothing without a railgun -- no spawn, no despawn", function()
			container.useCases.runMiningTick:run(userId)
			expect(#asteroidField.spawnCalls).toBe(0)
			local count = 0
			for _ in sessionRegistry:asteroids(userId) do
				count += 1
			end
			expect(count).toBe(0)
		end)

		it("never spawns past MaxActive, however favourable the roll", function()
			container.useCases.purchaseRailgun:run(userId)
			math.randomseed(1) -- deterministic across the whole run below

			-- Force three spawns directly via SessionRegistry (bypassing the
			-- roll) to reach the cap, then confirm a real tick can't add a
			-- fourth even across many attempts.
			sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())
			sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())
			sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())

			for _ = 1, 50 do
				container.useCases.runMiningTick:run(userId)
			end

			local count = 0
			for _ in sessionRegistry:asteroids(userId) do
				count += 1
			end
			expect(count).toBe(3)
		end)

		it("expires an asteroid past its lifetime and despawns it", function()
			container.useCases.purchaseRailgun:run(userId)
			local id = sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())

			clock:setMonotonic(RULES.asteroidLifetime) -- exactly at the boundary: expired

			container.useCases.runMiningTick:run(userId)

			expect(sessionRegistry:asteroids(userId)[id]).toBeNil()
			expect(#asteroidField.despawnCalls).toBe(1)
			expect(asteroidField.despawnCalls[1].asteroidId).toBe(id)
		end)
	end)

	describe("FireRailgun", function()
		it("refuses without a railgun", function()
			local result = container.useCases.fireRailgun:run(userId, "Asteroid_1")
			expect(result.ok).toBeFalsy()
		end)

		it("refuses an unknown/expired target id", function()
			container.useCases.purchaseRailgun:run(userId)
			local result = container.useCases.fireRailgun:run(userId, "NotSpawned")
			expect(result.ok).toBeFalsy()
		end)

		it("credits the reward, despawns the asteroid, and sets the cooldown", function()
			container.useCases.purchaseRailgun:run(userId)
			local creditsAfterPurchase = profileRepository:load(userId).credits
			local id = sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())

			local result = container.useCases.fireRailgun:run(userId, id)
			expect(result.ok).toBeTruthy()
			local reward = (result :: any).value.reward
			expect(reward >= 15 and reward <= 30).toBeTruthy() -- Common's own range

			expect(profileRepository:load(userId).credits).toBe(creditsAfterPurchase + reward)
			expect(sessionRegistry:asteroids(userId)[id]).toBeNil()
			expect(#asteroidField.despawnCalls).toBe(1)
			expect(sessionRegistry:lastFire(userId)).toBe(clock:monotonic())
		end)

		it("refuses a second shot before the cooldown elapses", function()
			container.useCases.purchaseRailgun:run(userId)
			local first = sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())
			container.useCases.fireRailgun:run(userId, first)

			local second = sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())
			local result = container.useCases.fireRailgun:run(userId, second)
			expect(result.ok).toBeFalsy()
			-- The still-alive target was NOT consumed by the refused attempt.
			expect(sessionRegistry:asteroids(userId)[second]).toBeTruthy()
		end)

		it("allows a second shot once the cooldown has elapsed", function()
			container.useCases.purchaseRailgun:run(userId)
			local first = sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())
			container.useCases.fireRailgun:run(userId, first)

			clock:setMonotonic(clock:monotonic() + RULES.railgun.cooldown)
			local second = sessionRegistry:spawnAsteroid(userId, "Common", clock:monotonic())
			local result = container.useCases.fireRailgun:run(userId, second)
			expect(result.ok).toBeTruthy()
		end)
	end)
end)
