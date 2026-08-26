--!strict
-- Mounts the REAL Composition/Container.luau with fake ports, exercising
-- RebirthStation/DevSetPass/DevSetRebirths/DevSetUnlimitedMoney/DevResetAll
-- together with RunProductionTick -- this is what proves the global boost
-- actually reaches the real production step, not just that
-- Rebirth.multiplier is right in isolation.
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
}
local STARTING_CREDITS = 100000

describe("Rebirth (real Container, fake ports)", function()
	local container
	local statsPublisher
	local sceneBuilder
	local stationRepository
	local profileRepository
	local userId = 1000

	beforeEach(function()
		userId += 1
		local clock = Fakes.TestClock.new(1000)
		profileRepository = Fakes.InMemoryProfileRepository.new(clock, {
			startingCredits = STARTING_CREDITS,
			maxModules = 100,
			maxLevel = RULES.upgrade.maxLevel,
		})
		stationRepository = Fakes.InMemoryStationRepository.new()
		statsPublisher = Fakes.RecordingStatsPublisher.new()
		sceneBuilder = Fakes.RecordingSceneBuilder.new()
		container = Container.new({
			ports = {
				profileRepository = profileRepository,
				stationRepository = stationRepository,
				clock = clock,
				statsPublisher = statsPublisher,
				notifier = Fakes.RecordingNotifier.new(),
				sceneBuilder = sceneBuilder,
				teleporter = Fakes.RecordingTeleporter.new(),
			},
			sessionRegistry = Application.SessionRegistry.new(),
			rules = RULES,
			development = true, -- so the dev-only use cases exist to test with
		})
	end)

	local function coreToLevel(level: number)
		local station = stationRepository:load(userId)
		station.placements[1].level = level -- the core is always placements[1]
		stationRepository:save(userId, station)
	end

	local function prodContainer()
		return Container.new({
			ports = {
				profileRepository = profileRepository,
				stationRepository = stationRepository,
				clock = Fakes.TestClock.new(1000),
				statsPublisher = statsPublisher,
				notifier = Fakes.RecordingNotifier.new(),
				sceneBuilder = sceneBuilder,
				teleporter = Fakes.RecordingTeleporter.new(),
			},
			sessionRegistry = Application.SessionRegistry.new(),
			rules = RULES,
			-- development omitted: exactly what production looks like
		})
	end

	describe("RebirthStation", function()
		it("refuses below the normal threshold", function()
			coreToLevel(9)
			local result = container.useCases.rebirthStation:run(userId)
			expect(result.ok).toBeFalsy()
		end)

		it(
			"succeeds at the normal threshold: resets the station and credits, banks a rebirth",
			function()
				container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
				coreToLevel(10)

				local result = container.useCases.rebirthStation:run(userId)
				expect(result.ok).toBeTruthy()
				expect((result :: any).value).toBe(1) -- one rebirth banked

				local station = stationRepository:load(userId)
				expect(#station.placements).toBe(1) -- back down to just the core
				expect(station.placements[1].level).toBe(1) -- the core's level resets too

				local profile = profileRepository:load(userId)
				expect(profile.credits).toBe(RULES.startingCredits)
				expect(profile.rebirths).toBe(1)
				expect(#profile.modules).toBe(1)
			end
		)

		it("refuses at the early threshold without the EarlyRebirth pass", function()
			coreToLevel(5)
			local result = container.useCases.rebirthStation:run(userId)
			expect(result.ok).toBeFalsy()
		end)

		it("succeeds at the early threshold once the EarlyRebirth pass is granted", function()
			container.useCases.devSetPass:run(userId, "EarlyRebirth", true)
			coreToLevel(5)
			local result = container.useCases.rebirthStation:run(userId)
			expect(result.ok).toBeTruthy()
		end)

		it("is entirely dormant when disabled, whatever the core's level", function()
			local offRules = table.clone(RULES)
			offRules.rebirth = table.clone(RULES.rebirth)
			offRules.rebirth.enabled = false
			local offContainer = Container.new({
				ports = {
					profileRepository = profileRepository,
					stationRepository = stationRepository,
					clock = Fakes.TestClock.new(1000),
					statsPublisher = statsPublisher,
					notifier = Fakes.RecordingNotifier.new(),
					sceneBuilder = sceneBuilder,
					teleporter = Fakes.RecordingTeleporter.new(),
				},
				sessionRegistry = Application.SessionRegistry.new(),
				rules = offRules,
			})
			coreToLevel(10)
			local result = offContainer.useCases.rebirthStation:run(userId)
			expect(result.ok).toBeFalsy()
		end)

		describe("SceneBuilder wiring", function()
			it("removes every non-core module and resets the core's level in the scene", function()
				container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
				container.useCases.placeModule:run(userId, "Conduit", 2, -1, 0)
				coreToLevel(10)
				sceneBuilder.removeCalls = {}
				sceneBuilder.levelCalls = {}

				container.useCases.rebirthStation:run(userId)

				expect(#sceneBuilder.removeCalls).toBe(2) -- the two non-core modules
				expect(#sceneBuilder.levelCalls).toBe(1)
				expect(sceneBuilder.levelCalls[1]).toEqual({
					userId = userId,
					x = -1,
					y = -1,
					level = 1,
				})
			end)
		end)
	end)

	describe("DevSetPass", function()
		it("refuses an unknown pass id", function()
			local result = container.useCases.devSetPass:run(userId, "NotAPass", true)
			expect(result.ok).toBeFalsy()
		end)

		it("turns Ultimate on, persisted on the profile", function()
			local result = container.useCases.devSetPass:run(userId, "Ultimate", true)
			expect(result.ok).toBeTruthy()
			local profile = profileRepository:load(userId)
			expect(profile.unlocked.Ultimate).toBe(true)
		end)

		it(
			"turns Ultimate back off just as easily -- no real-money equivalent, dev-only",
			function()
				container.useCases.devSetPass:run(userId, "Ultimate", true)
				container.useCases.devSetPass:run(userId, "Ultimate", false)
				local profile = profileRepository:load(userId)
				expect(profile.unlocked.Ultimate).toBe(false)
			end
		)

		it("does not exist at all when the container was NOT built in development mode", function()
			expect(prodContainer().useCases.devSetPass).toBeNil()
		end)
	end)

	describe("DevSetRebirths", function()
		it("sets the rebirth count directly, bypassing the core-level gate entirely", function()
			local result = container.useCases.devSetRebirths:run(userId, 5, false)
			expect(result.ok).toBeTruthy()
			expect(profileRepository:load(userId).rebirths).toBe(5)
		end)

		it("leaves the station and credits untouched when resetStation is false", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
			local creditsBefore = profileRepository:load(userId).credits

			container.useCases.devSetRebirths:run(userId, 3, false)

			local station = stationRepository:load(userId)
			expect(#station.placements).toBe(2) -- core + corridor, untouched
			expect(profileRepository:load(userId).credits).toBe(creditsBefore)
			expect(profileRepository:load(userId).rebirths).toBe(3)
		end)

		it("resets the station and credits too when resetStation is true", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)

			container.useCases.devSetRebirths:run(userId, 7, true)

			local station = stationRepository:load(userId)
			expect(#station.placements).toBe(1) -- back down to just the core
			expect(profileRepository:load(userId).credits).toBe(RULES.startingCredits)
			expect(profileRepository:load(userId).rebirths).toBe(7)
		end)

		it("refuses a negative or NaN count", function()
			expect(container.useCases.devSetRebirths:run(userId, -1, false).ok).toBeFalsy()
			expect(container.useCases.devSetRebirths:run(userId, 0 / 0, false).ok).toBeFalsy()
		end)

		it("does not exist at all when the container was NOT built in development mode", function()
			expect(prodContainer().useCases.devSetRebirths).toBeNil()
		end)
	end)

	describe("DevSetUnlimitedMoney", function()
		it("tops credits back up to the ceiling on the next production tick", function()
			container.useCases.devSetUnlimitedMoney:run(userId, true)
			container.useCases.runProductionTick:run(userId, 1)
			expect(profileRepository:load(userId).credits).toBe(RULES.unlimitedMoneyCeiling)
		end)

		it("does nothing to credits once turned back off", function()
			container.useCases.devSetUnlimitedMoney:run(userId, true)
			container.useCases.runProductionTick:run(userId, 1)
			container.useCases.devSetUnlimitedMoney:run(userId, false)
			container.useCases.spendCredits:run(userId, 100)
			container.useCases.runProductionTick:run(userId, 1)
			expect(profileRepository:load(userId).credits).toBe(RULES.unlimitedMoneyCeiling - 100)
		end)

		it("does not exist at all when the container was NOT built in development mode", function()
			expect(prodContainer().useCases.devSetUnlimitedMoney).toBeNil()
		end)
	end)

	describe("DevResetAll", function()
		it("resets station, credits, rebirths, both passes, and the objective", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
			coreToLevel(10)
			container.useCases.rebirthStation:run(userId)
			container.useCases.devSetPass:run(userId, "Ultimate", true)
			container.useCases.devSetPass:run(userId, "EarlyRebirth", true)

			local result = container.useCases.devResetAll:run(userId)
			expect(result.ok).toBeTruthy()

			local station = stationRepository:load(userId)
			expect(#station.placements).toBe(1)
			expect(station.placements[1].level).toBe(1)

			local profile = profileRepository:load(userId)
			expect(profile.credits).toBe(RULES.profileRules.startingCredits)
			expect(profile.rebirths).toBe(0)
			expect(profile.objective).toBe(1)
			expect(profile.unlocked.Ultimate).toBeFalsy()
			expect(profile.unlocked.EarlyRebirth).toBeFalsy()
		end)

		it("does not exist at all when the container was NOT built in development mode", function()
			expect(prodContainer().useCases.devResetAll).toBeNil()
		end)
	end)

	describe("the boost reaching real production", function()
		it("scales tick revenue once Ultimate is granted, with no rebirths needed", function()
			container.useCases.placeModule:run(userId, "OreCollector", 1, -1, 0)
			container.useCases.placeModule:run(userId, "CargoBay", 3, -1, 0)

			local baseline = container.useCases.runProductionTick:run(userId, 1)
			container.useCases.devSetPass:run(userId, "Ultimate", true)
			local boosted = container.useCases.runProductionTick:run(userId, 1)

			-- Same station, same tick length -- only Ultimate (x1.5) changed.
			expect(boosted.income).toBeNear(baseline.income * 1.5)
		end)

		it("stacks the rebirth bonus across multiple rebirths", function()
			container.useCases.placeModule:run(userId, "OreCollector", 1, -1, 0)
			container.useCases.placeModule:run(userId, "CargoBay", 3, -1, 0)
			local before = container.useCases.runProductionTick:run(userId, 1)

			coreToLevel(10)
			container.useCases.rebirthStation:run(userId) -- 1 rebirth banked, +25%
			container.useCases.placeModule:run(userId, "OreCollector", 1, -1, 0)
			container.useCases.placeModule:run(userId, "CargoBay", 3, -1, 0)
			local after = container.useCases.runProductionTick:run(userId, 1)

			expect(after.income).toBeNear(before.income * 1.25)
		end)
	end)
end)
