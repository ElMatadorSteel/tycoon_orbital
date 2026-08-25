--!strict
-- RestoreStation replays profile.modules back into the station -- both its
-- in-memory data AND the scene. See DEVELOPMENT.md's "integration tests
-- mount the real wiring with fake ports."
local RestoreStation = require(Application.UseCases.RestoreStation)

local GRID_RULES = { cellSize = 8, radius = 12 }

describe("RestoreStation", function()
	local profileRepository
	local stationRepository
	local sceneBuilder
	local restoreStation
	local userId = 1

	beforeEach(function()
		userId += 1
		local clock = Fakes.TestClock.new(1000)
		profileRepository = Fakes.InMemoryProfileRepository.new(clock, {
			startingCredits = 800,
			maxModules = 100,
			maxLevel = 5,
		})
		stationRepository = Fakes.InMemoryStationRepository.new()
		sceneBuilder = Fakes.RecordingSceneBuilder.new()
		restoreStation = setmetatable({
			profileRepository = profileRepository,
			stationRepository = stationRepository,
			sceneBuilder = sceneBuilder,
			gridRules = GRID_RULES,
		}, RestoreStation)
	end)

	it("does nothing when the saved profile has no modules beyond the core", function()
		restoreStation:run(userId)
		local station = stationRepository:load(userId)
		expect(#station.placements).toBe(1) -- just the core
		expect(#sceneBuilder.placeCalls).toBe(0)
	end)

	it(
		"restores the core's saved level -- claimPlot always starts it at 1, but it's upgradable",
		function()
			local profile = profileRepository:load(userId)
			profile.modules = { { id = "Core", x = -1, y = -1, r = 0, lv = 3 } }
			profileRepository:save(userId, profile)

			restoreStation:run(userId)

			local station = stationRepository:load(userId)
			expect(#station.placements).toBe(1) -- still just the core, never replayed as a
			-- second Instance
			expect(station.placements[1].level).toBe(3)
			expect(#sceneBuilder.placeCalls).toBe(0) -- no second core built
			expect(#sceneBuilder.levelCalls).toBe(1)
			expect(sceneBuilder.levelCalls[1]).toEqual({
				userId = userId,
				x = -1,
				y = -1,
				level = 3,
			})
		end
	)

	it("does not touch the scene builder when the saved core is still level 1", function()
		local profile = profileRepository:load(userId)
		profile.modules = { { id = "Core", x = -1, y = -1, r = 0, lv = 1 } }
		profileRepository:save(userId, profile)

		restoreStation:run(userId)

		expect(#sceneBuilder.levelCalls).toBe(0)
	end)

	it("replays every saved module into the station and the scene", function()
		local profile = profileRepository:load(userId)
		profile.modules = {
			{ id = "Core", x = -1, y = -1, r = 0, lv = 1 },
			{ id = "Corridor", x = 1, y = -1, r = 0, lv = 1 },
			{ id = "SolarPanel", x = 2, y = -1, r = 1, lv = 2 },
		}
		profileRepository:save(userId, profile)

		restoreStation:run(userId)

		local station = stationRepository:load(userId)
		expect(#station.placements).toBe(3) -- the synthesized core + 2 restored

		-- The core is never replayed through the scene builder: claimPlot
		-- already placed its Instance before RestoreStation ever runs.
		expect(#sceneBuilder.placeCalls).toBe(2)
		local ids = {}
		for _, call in sceneBuilder.placeCalls do
			ids[call.placement.id] = true
		end
		expect(ids.Corridor).toBeTruthy()
		expect(ids.SolarPanel).toBeTruthy()
	end)

	it("restores the saved level and rotation, not just the id and position", function()
		local profile = profileRepository:load(userId)
		profile.modules = {
			{ id = "Core", x = -1, y = -1, r = 0, lv = 1 },
			{ id = "SolarPanel", x = 2, y = -1, r = 1, lv = 3 },
		}
		profileRepository:save(userId, profile)

		restoreStation:run(userId)

		expect(sceneBuilder.placeCalls[1].placement.rotation).toBe(1)
		expect(sceneBuilder.placeCalls[1].placement.level).toBe(3)
	end)

	it("skips a saved entry that no longer fits (corrupted or overlapping save)", function()
		local profile = profileRepository:load(userId)
		profile.modules = {
			{ id = "Core", x = -1, y = -1, r = 0, lv = 1 },
			{ id = "Corridor", x = -1, y = -1, r = 0, lv = 1 }, -- overlaps the core
		}
		profileRepository:save(userId, profile)

		restoreStation:run(userId)

		local station = stationRepository:load(userId)
		expect(#station.placements).toBe(1) -- only the core; the overlap was skipped
		expect(#sceneBuilder.placeCalls).toBe(0)
	end)

	it("skips a saved module id no longer in the catalogue", function()
		local profile = profileRepository:load(userId)
		profile.modules = { { id = "Retired", x = 1, y = -1, r = 0, lv = 1 } }
		profileRepository:save(userId, profile)

		restoreStation:run(userId)

		local station = stationRepository:load(userId)
		expect(#station.placements).toBe(1)
		expect(#sceneBuilder.placeCalls).toBe(0)
	end)

	it("does not require the saved modules to touch each other in order", function()
		-- A far-flung entry that only touches a module restored AFTER it in
		-- the saved list, not before -- free placement must not depend on
		-- restore order the way an ordinary PlaceModule call would.
		local profile = profileRepository:load(userId)
		profile.modules = {
			{ id = "Core", x = -1, y = -1, r = 0, lv = 1 },
			{ id = "Conduit", x = 5, y = -1, r = 0, lv = 1 },
			{ id = "Conduit", x = 4, y = -1, r = 0, lv = 1 },
			{ id = "Conduit", x = 3, y = -1, r = 0, lv = 1 },
			{ id = "Conduit", x = 2, y = -1, r = 0, lv = 1 },
			{ id = "Corridor", x = 1, y = -1, r = 0, lv = 1 },
		}
		profileRepository:save(userId, profile)

		restoreStation:run(userId)

		expect(#sceneBuilder.placeCalls).toBe(5)
	end)
end)
