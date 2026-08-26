--!strict
-- Mounts the REAL Composition/Container.luau with fake ports, exercising
-- PlaceModule/RemoveModule/UpgradeModule together -- this is what proves the
-- production wiring works, not just that each Domain rule is right alone.
local Container = require(Composition.Container)

local RULES = {
	grid = { cellSize = 8, radius = 12 },
	refundRatio = 0.5,
	upgrade = { maxLevel = 4, gainPerLevel = 0.5, costFactor = 2, minCost = 100 },
	orbit = { period = 180, eclipseFraction = 0.3 },
	heat = { baseCapacity = 40, capacityPerRadiator = 60, overheatPenalty = 0.55 },
	resourceValues = { Ore = 5, Alloy = 22, Component = 75 },
}

-- Generous on purpose: the max-level-cap test alone needs 300+600+1200 to
-- climb from level 1 to 4 with these UpgradeRules (costFactor=2). This test
-- suite is about the rules' shape (refusals, level caps, sync), not about
-- pinching a tight budget -- that's what Config/Balance's own spec is for.
local STARTING_CREDITS = 100000

describe("Station use cases (real Container, fake ports)", function()
	local container
	local statsPublisher
	local notifier
	local sceneBuilder
	local userId = 1

	beforeEach(function()
		userId += 1 -- fresh user per test: repositories cache per userId
		local clock = Fakes.TestClock.new(1000)
		local profileRepository = Fakes.InMemoryProfileRepository.new(clock, {
			startingCredits = STARTING_CREDITS,
			maxModules = 100,
			maxLevel = RULES.upgrade.maxLevel,
		})
		local stationRepository = Fakes.InMemoryStationRepository.new()
		statsPublisher = Fakes.RecordingStatsPublisher.new()
		notifier = Fakes.RecordingNotifier.new()
		sceneBuilder = Fakes.RecordingSceneBuilder.new()
		container = Container.new({
			ports = {
				profileRepository = profileRepository,
				stationRepository = stationRepository,
				clock = clock,
				statsPublisher = statsPublisher,
				notifier = notifier,
				sceneBuilder = sceneBuilder,
				teleporter = Fakes.RecordingTeleporter.new(),
			},
			sessionRegistry = Application.SessionRegistry.new(),
			rules = RULES,
		})
	end)

	it(
		"places a module touching the core, deducts its cost, and keeps the profile in sync",
		function()
			local result = container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
			expect(result.ok).toBeTruthy()

			local profile = container.ports.profileRepository:load(userId)
			expect(profile.credits).toBe(STARTING_CREDITS - 25) -- Corridor costs 25 in the real catalogue

			local station = container.ports.stationRepository:load(userId)
			expect(#station.placements).toBe(2) -- core + corridor

			expect(#profile.modules).toBe(2)
			expect(statsPublisher:latest(userId).Credits).toBe(profile.credits)
		end
	)

	describe("gain notifications on placement", function()
		it(
			"announces nothing for a plain module (no power, storage or cooling to speak of)",
			function()
				container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
				expect(#notifier.calls).toBe(0)
			end
		)

		it("announces Power for a module that produces it", function()
			container.useCases.placeModule:run(userId, "SolarPanel", 1, -1, 0)
			expect(#notifier.calls).toBe(1)
			expect(notifier.calls[1].kind).toBe("Power")
			expect(notifier.calls[1].payload).toBe(12) -- SolarPanel's power in the real catalogue
		end)

		it("announces Storage for a module with capacity", function()
			container.useCases.placeModule:run(userId, "Battery", 1, -1, 0)
			expect(#notifier.calls).toBe(1)
			expect(notifier.calls[1].kind).toBe("Storage")
			expect(notifier.calls[1].payload).toBe(120)
		end)

		it("announces Cooling, using the configured capacityPerRadiator, for a radiator", function()
			container.useCases.placeModule:run(userId, "Radiator", 1, -1, 0)
			expect(#notifier.calls).toBe(1)
			expect(notifier.calls[1].kind).toBe("Cooling")
			expect(notifier.calls[1].payload).toBe(RULES.heat.capacityPerRadiator)
		end)
	end)

	it("refuses to place when the station doesn't have the credits", function()
		container.useCases.spendCredits:run(userId, STARTING_CREDITS) -- drain the balance first
		local result = container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
		expect(result.ok).toBeFalsy()

		local station = container.ports.stationRepository:load(userId)
		expect(#station.placements).toBe(1) -- unchanged: just the core
	end)

	it("refuses to place somewhere that doesn't touch the station", function()
		local result = container.useCases.placeModule:run(userId, "Corridor", 8, 8, 0)
		expect(result.ok).toBeFalsy()
	end)

	it("removing a module refunds it and drops it from the profile", function()
		container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
		local before = container.ports.profileRepository:load(userId).credits

		local result = container.useCases.removeModule:run(userId, 1, -1)
		expect(result.ok).toBeTruthy()

		local profile = container.ports.profileRepository:load(userId)
		expect(profile.credits).toBe(before + math.floor(25 * RULES.refundRatio))
		expect(#profile.modules).toBe(1) -- back down to just the core
		expect(statsPublisher:latest(userId).Credits).toBe(profile.credits)

		local station = container.ports.stationRepository:load(userId)
		expect(#station.placements).toBe(1)
	end)

	it("refuses to remove the unique core", function()
		local result = container.useCases.removeModule:run(userId, -1, -1)
		expect(result.ok).toBeFalsy()
	end)

	it("upgrades a module, charges for it, and persists the new level in the profile", function()
		container.useCases.placeModule:run(userId, "SolarPanel", 1, -1, 0) -- upgradable, cost 150
		local afterPlace = container.ports.profileRepository:load(userId).credits

		local result = container.useCases.upgradeModule:run(userId, 1, -1)
		expect(result.ok).toBeTruthy()
		expect((result :: any).value).toBe(2)

		local profile = container.ports.profileRepository:load(userId)
		expect(profile.credits < afterPlace).toBeTruthy()

		-- Regression guard: UpgradeModule mutates the placement's level in
		-- place, but profile.modules is a separate snapshot copy -- without
		-- re-syncing it after the upgrade, this would still read 1.
		local upgraded
		for _, entry in profile.modules do
			if entry.id == "SolarPanel" then
				upgraded = entry
			end
		end
		expect(upgraded ~= nil).toBeTruthy()
		expect((upgraded :: any).lv).toBe(2)
		expect(statsPublisher:latest(userId).Credits).toBe(profile.credits)
	end)

	it("refuses to upgrade a module that has nothing to upgrade", function()
		container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
		local result = container.useCases.upgradeModule:run(userId, 1, -1)
		expect(result.ok).toBeFalsy()
	end)

	it("refuses to upgrade past the level cap", function()
		container.useCases.placeModule:run(userId, "SolarPanel", 1, -1, 0)
		for _ = 1, RULES.upgrade.maxLevel - 1 do
			local step = container.useCases.upgradeModule:run(userId, 1, -1)
			expect(step.ok).toBeTruthy()
		end
		local overCap = container.useCases.upgradeModule:run(userId, 1, -1)
		expect(overCap.ok).toBeFalsy()
	end)

	describe("SceneBuilder wiring", function()
		it("asks the scene builder to place the module Instance on success", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
			expect(#sceneBuilder.placeCalls).toBe(1)
			expect(sceneBuilder.placeCalls[1].userId).toBe(userId)
			expect(sceneBuilder.placeCalls[1].placement.id).toBe("Corridor")
		end)

		it("does not touch the scene builder on a refused placement", function()
			container.useCases.placeModule:run(userId, "Corridor", 8, 8, 0) -- doesn't touch the station
			expect(#sceneBuilder.placeCalls).toBe(0)
		end)

		it("asks the scene builder to remove the module Instance on success", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
			container.useCases.removeModule:run(userId, 1, -1)
			expect(#sceneBuilder.removeCalls).toBe(1)
			expect(sceneBuilder.removeCalls[1]).toEqual({ userId = userId, x = 1, y = -1 })
		end)

		it("asks the scene builder to update the level on a successful upgrade", function()
			container.useCases.placeModule:run(userId, "SolarPanel", 1, -1, 0)
			container.useCases.upgradeModule:run(userId, 1, -1)
			expect(#sceneBuilder.levelCalls).toBe(1)
			expect(sceneBuilder.levelCalls[1]).toEqual({ userId = userId, x = 1, y = -1, level = 2 })
		end)
	end)

	describe("MoveModule", function()
		it("moves a module and keeps the profile in sync", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)

			local result = container.useCases.moveModule:run(userId, 1, -1, 0, -2, 0)
			expect(result.ok).toBeTruthy()

			local station = container.ports.stationRepository:load(userId)
			expect(#station.placements).toBe(2) -- still just core + the same corridor

			local profile = container.ports.profileRepository:load(userId)
			local moved
			for _, entry in profile.modules do
				if entry.id == "Corridor" then
					moved = entry
				end
			end
			expect(moved ~= nil).toBeTruthy()
			expect((moved :: any).x).toBe(0)
			expect((moved :: any).y).toBe(-2)
		end)

		it("does not charge or refund anything for a move", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
			local before = container.ports.profileRepository:load(userId).credits

			container.useCases.moveModule:run(userId, 1, -1, 0, -2, 0)

			local after = container.ports.profileRepository:load(userId).credits
			expect(after).toBe(before)
		end)

		it("preserves the module's level across a move", function()
			container.useCases.placeModule:run(userId, "SolarPanel", 1, -1, 0)
			container.useCases.upgradeModule:run(userId, 1, -1) -- now level 2

			container.useCases.moveModule:run(userId, 1, -1, 0, -2, 0)

			local station = container.ports.stationRepository:load(userId)
			local moved
			for _, placement in station.placements do
				if placement.id == "SolarPanel" then
					moved = placement
				end
			end
			expect(moved ~= nil).toBeTruthy()
			expect((moved :: any).level).toBe(2)
		end)

		it("refuses to move the unique core", function()
			local result = container.useCases.moveModule:run(userId, -1, -1, 5, 5, 0)
			expect(result.ok).toBeFalsy()

			local station = container.ports.stationRepository:load(userId)
			expect(station.occupancy["-1,-1"] ~= nil).toBeTruthy()
		end)

		it("refuses a destination that overlaps another module", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
			local result = container.useCases.moveModule:run(userId, 1, -1, -1, -1, 0)
			expect(result.ok).toBeFalsy()
		end)

		it("refuses a destination that touches nothing", function()
			container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
			local result = container.useCases.moveModule:run(userId, 1, -1, 8, 8, 0)
			expect(result.ok).toBeFalsy()
		end)

		describe("SceneBuilder wiring", function()
			it("removes the old Instance and places a new one on a successful move", function()
				container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
				sceneBuilder.removeCalls = {}
				sceneBuilder.placeCalls = {}

				container.useCases.moveModule:run(userId, 1, -1, 0, -2, 0)

				expect(#sceneBuilder.removeCalls).toBe(1)
				expect(sceneBuilder.removeCalls[1]).toEqual({ userId = userId, x = 1, y = -1 })
				expect(#sceneBuilder.placeCalls).toBe(1)
				expect(sceneBuilder.placeCalls[1].placement.x).toBe(0)
				expect(sceneBuilder.placeCalls[1].placement.y).toBe(-2)
			end)

			it("does not touch the scene builder on a refused move", function()
				container.useCases.placeModule:run(userId, "Corridor", 1, -1, 0)
				sceneBuilder.removeCalls = {}
				sceneBuilder.placeCalls = {}

				container.useCases.moveModule:run(userId, 1, -1, 8, 8, 0)

				expect(#sceneBuilder.removeCalls).toBe(0)
				expect(#sceneBuilder.placeCalls).toBe(0)
			end)
		end)
	end)
end)
