--!strict
-- Mounts the REAL Composition/Container.luau with fake ports, exercising
-- DigBlock end-to-end: mine generation, digging, backpack limits, regen,
-- and persistence across loads.
local Container = require(Composition.Container)

local GRID_RULES = {
	regenInterval = 21600, -- 6h
	layers = {
		{
			width = 4,
			depth = 4,
			density = 0.5,
			pool = {
				{ id = "Iron", weight = 80 },
				{ id = "Copper", weight = 20 },
			},
		},
		{
			width = 4,
			depth = 4,
			density = 0.3,
			pool = {
				{ id = "Titanium", weight = 60 },
				{ id = "Iridium", weight = 40 },
			},
		},
	},
}

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
			{ id = "Common", name = "c", weight = 60, minReward = 15, maxReward = 30 },
		},
	},
	asteroidLifetime = 8,
	mineGrid = GRID_RULES,
	backpackCapacity = 5,
	digCooldown = 1,
}

local STARTING_CREDITS = 100000

describe("DigBlock (real Container, fake ports)", function()
	local container
	local profileRepository
	local sessionRegistry
	local clock
	local userId = 5000

	beforeEach(function()
		userId += 1
		clock = Fakes.TestClock.new(1000)
		profileRepository = Fakes.InMemoryProfileRepository.new(clock, {
			startingCredits = STARTING_CREDITS,
			maxModules = 100,
			maxLevel = RULES.upgrade.maxLevel,
		})
		sessionRegistry = Application.SessionRegistry.new()
		container = Container.new({
			ports = {
				profileRepository = profileRepository,
				stationRepository = Fakes.InMemoryStationRepository.new(),
				clock = clock,
				statsPublisher = Fakes.RecordingStatsPublisher.new(),
				notifier = Fakes.RecordingNotifier.new(),
				sceneBuilder = Fakes.RecordingSceneBuilder.new(),
				teleporter = Fakes.RecordingTeleporter.new(),
				asteroidField = Fakes.RecordingAsteroidField.new(),
				movementActuator = { setWalkSpeed = function() end, release = function() end },
			},
			sessionRegistry = sessionRegistry,
			rules = RULES,
		})
	end)

	-- Unlock the mine before digging
	local function unlockMine()
		local profile = profileRepository:load(userId)
		profile.unlocked.ResearchMine = true
		profileRepository:save(userId, profile)
	end

	it("refuses when the mine is not unlocked", function()
		clock:setMonotonic(10)
		local result = container.useCases.digBlock:run(userId, 1, 0, 0)
		expect(result.ok).toBeFalsy()
		expect(result.error).toBe("mine not unlocked")
	end)

	it("digs a block and generates the mine on first dig", function()
		unlockMine()
		clock:setMonotonic(10)
		local result = container.useCases.digBlock:run(userId, 1, 0, 0)
		expect(result.ok).toBeTruthy()
		-- Mine was generated and persisted
		local profile = profileRepository:load(userId)
		expect(profile.mine).toBeTruthy()
		expect(profile.mine.generatedAt).toBe(1000) -- epoch from clock:now()
	end)

	it("collects ore into the backpack when a block contains ore", function()
		unlockMine()
		-- Dig multiple blocks until we find ore (density is 0.5, so likely quick)
		local foundOre = false
		for y = 0, 3 do
			for x = 0, 3 do
				clock:setMonotonic(10 + y * 4 + x * 2)
				local result = container.useCases.digBlock:run(userId, 1, x, y)
				if result.ok and result.value.oreId then
					foundOre = true
					local profile = profileRepository:load(userId)
					expect(profile.ores[result.value.oreId] >= 1).toBeTruthy()
					break
				end
			end
			if foundOre then
				break
			end
		end
		-- With density=0.5 on 16 cells, statistically guaranteed to find at least one
		expect(foundOre).toBeTruthy()
	end)

	it("refuses to dig an already dug block", function()
		unlockMine()
		clock:setMonotonic(10)
		container.useCases.digBlock:run(userId, 1, 0, 0)
		clock:setMonotonic(20) -- past cooldown
		local result = container.useCases.digBlock:run(userId, 1, 0, 0)
		expect(result.ok).toBeFalsy()
		expect(result.error).toBe("cannot dig here")
	end)

	it("enforces dig cooldown", function()
		unlockMine()
		clock:setMonotonic(10)
		container.useCases.digBlock:run(userId, 1, 0, 0)
		-- Try again immediately
		clock:setMonotonic(10.5) -- 0.5s < 1s cooldown
		local result = container.useCases.digBlock:run(userId, 1, 1, 0)
		expect(result.ok).toBeFalsy()
		expect(result.error).toBe("cooldown")
	end)

	it("allows digging after cooldown passes", function()
		unlockMine()
		clock:setMonotonic(10)
		container.useCases.digBlock:run(userId, 1, 0, 0)
		clock:setMonotonic(11) -- exactly at cooldown boundary
		local result = container.useCases.digBlock:run(userId, 1, 1, 0)
		expect(result.ok).toBeTruthy()
	end)

	it("refuses when backpack is full but still digs the block", function()
		unlockMine()
		-- Fill the backpack manually (capacity = 5)
		local profile = profileRepository:load(userId)
		profile.ores.Iron = 5
		profileRepository:save(userId, profile)

		clock:setMonotonic(10)
		local result = container.useCases.digBlock:run(userId, 1, 0, 0)
		expect(result.ok).toBeTruthy()
		-- Block is consumed (dug)
		expect(result.value.bagFull).toBe(true)
		-- Ore count unchanged (could not pick up)
		local reloaded = profileRepository:load(userId)
		expect(reloaded.ores.Iron).toBe(5)
	end)

	it("refuses out-of-bounds coordinates", function()
		unlockMine()
		clock:setMonotonic(10)
		local result = container.useCases.digBlock:run(userId, 1, 99, 99)
		expect(result.ok).toBeFalsy()
		expect(result.error).toBe("cannot dig here")
	end)

	it("refuses an invalid layer", function()
		unlockMine()
		clock:setMonotonic(10)
		local result = container.useCases.digBlock:run(userId, 99, 0, 0)
		expect(result.ok).toBeFalsy()
		expect(result.error).toBe("cannot dig here")
	end)

	it("regenerates the mine after regenInterval", function()
		unlockMine()
		clock:setMonotonic(10)
		container.useCases.digBlock:run(userId, 1, 0, 0)

		-- Advance epoch past the regen interval
		clock:set(1000 + 21601) -- past 6h
		clock:setMonotonic(30)
		local result = container.useCases.digBlock:run(userId, 1, 0, 0)
		-- Should succeed: the grid was regenerated, cell (0,0) is fresh
		expect(result.ok).toBeTruthy()

		-- generatedAt is the new epoch
		local profile = profileRepository:load(userId)
		expect(profile.mine.generatedAt).toBe(1000 + 21601)
	end)

	it("preserves dug state across loads within regen window", function()
		unlockMine()
		clock:setMonotonic(10)
		container.useCases.digBlock:run(userId, 1, 0, 0)

		-- "Reconnect": build a new container with the same profile repo
		local container2 = Container.new({
			ports = {
				profileRepository = profileRepository,
				stationRepository = Fakes.InMemoryStationRepository.new(),
				clock = clock,
				statsPublisher = Fakes.RecordingStatsPublisher.new(),
				notifier = Fakes.RecordingNotifier.new(),
				sceneBuilder = Fakes.RecordingSceneBuilder.new(),
				teleporter = Fakes.RecordingTeleporter.new(),
				asteroidField = Fakes.RecordingAsteroidField.new(),
				movementActuator = { setWalkSpeed = function() end, release = function() end },
			},
			sessionRegistry = Application.SessionRegistry.new(),
			rules = RULES,
		})
		clock:setMonotonic(20)
		local result = container2.useCases.digBlock:run(userId, 1, 0, 0)
		-- Still dug from the first session
		expect(result.ok).toBeFalsy()
		expect(result.error).toBe("cannot dig here")
	end)

	it("can dig in different layers", function()
		unlockMine()
		clock:setMonotonic(10)
		local r1 = container.useCases.digBlock:run(userId, 1, 0, 0)
		expect(r1.ok).toBeTruthy()
		clock:setMonotonic(12)
		local r2 = container.useCases.digBlock:run(userId, 2, 0, 0)
		expect(r2.ok).toBeTruthy()
	end)
end)
