--!strict
local Railgun = require(Domain.Mining.Railgun)

local RULES = {
	cost = 500,
	cooldown = 1.5,
	maxActive = 3,
	spawnChancePerTick = 0.12,
}

describe("Railgun.canFire", function()
	it("refuses just under the cooldown", function()
		expect(Railgun.canFire(10, 11.4999, 1.5)).toBeFalsy()
	end)

	it("allows exactly at the cooldown boundary", function()
		expect(Railgun.canFire(10, 11.5, 1.5)).toBeTruthy()
	end)

	it("allows well past the cooldown", function()
		expect(Railgun.canFire(10, 50, 1.5)).toBeTruthy()
	end)
end)

describe("Railgun.canSpawn", function()
	it("allows below the cap", function()
		expect(Railgun.canSpawn(2, 3)).toBeTruthy()
	end)

	it("refuses exactly at the cap", function()
		expect(Railgun.canSpawn(3, 3)).toBeFalsy()
	end)
end)

describe("Railgun.shouldSpawn", function()
	it("spawns when under the cap and the roll clears the threshold", function()
		expect(Railgun.shouldSpawn(0.119, 0, RULES)).toBeTruthy()
	end)

	it("does not spawn when the roll lands exactly on the threshold", function()
		expect(Railgun.shouldSpawn(0.12, 0, RULES)).toBeFalsy()
	end)

	it("never spawns at the cap, however favourable the roll", function()
		expect(Railgun.shouldSpawn(0, 3, RULES)).toBeFalsy()
	end)
end)
