--!strict
local Profile = require(Domain.Profile.Profile)

-- Domain specs use their own fixtures, never the real Balance config, so
-- that rebalancing production numbers can never change what this test
-- means (DEVELOPMENT.md).
local RULES = { startingCredits = 800, maxModules = 5, maxLevel = 3 }

describe("Profile.sanitize", function()
	it("returns a blank profile for a missing/non-table value", function()
		local profile = Profile.sanitize(nil, RULES)
		expect(profile.credits).toBe(RULES.startingCredits)
		expect(profile.objective).toBe(1)
		expect(#profile.modules).toBe(0)
	end)

	it("falls back to the blank default on NaN credits", function()
		local nan = 0 / 0
		local profile = Profile.sanitize({ credits = nan }, RULES)
		expect(profile.credits).toBe(RULES.startingCredits)
	end)

	it("clamps a negative credits value to zero", function()
		local profile = Profile.sanitize({ credits = -500 }, RULES)
		expect(profile.credits).toBe(0)
	end)

	it("restarts the objective chain at 1 when the field is missing", function()
		local profile = Profile.sanitize({ credits = 100 }, RULES)
		expect(profile.objective).toBe(1)
	end)

	it("clamps a fractional/negative rotation to 0-3 quarter-turns", function()
		local profile = Profile.sanitize({
			modules = {
				{ id = "Conduit", x = 0, y = 0, r = -1 },
				{ id = "Conduit", x = 1, y = 0, r = 5.7 },
			},
		}, RULES)
		expect(profile.modules[1].r).toBe(3) -- -1 % 4 == 3
		expect(profile.modules[2].r).toBe(1) -- floor(5.7) % 4 == 5 % 4 == 1
	end)

	it("clamps module level to 1..maxLevel", function()
		local profile = Profile.sanitize({
			modules = {
				{ id = "SolarPanel", x = 0, y = 0, lv = 0 },
				{ id = "SolarPanel", x = 1, y = 0, lv = 99 },
			},
		}, RULES)
		expect(profile.modules[1].lv).toBe(1)
		expect(profile.modules[2].lv).toBe(RULES.maxLevel)
	end)

	it("defaults a missing level to 1", function()
		local profile = Profile.sanitize({
			modules = { { id = "Corridor", x = 0, y = 0 } },
		}, RULES)
		expect(profile.modules[1].lv).toBe(1)
	end)

	it("truncates modules beyond maxModules", function()
		local modules = {}
		for i = 1, RULES.maxModules + 10 do
			table.insert(modules, { id = "Corridor", x = i, y = 0 })
		end
		local profile = Profile.sanitize({ modules = modules }, RULES)
		expect(#profile.modules).toBe(RULES.maxModules)
	end)

	it("drops malformed module entries silently", function()
		local profile = Profile.sanitize({
			modules = { "not-a-table", { x = 0, y = 0 }, { id = 42 } },
		}, RULES)
		expect(#profile.modules).toBe(0)
	end)
end)
