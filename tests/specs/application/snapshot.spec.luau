--!strict
local Snapshot = require(Application.Snapshot)

describe("Snapshot", function()
	it("credits() returns exactly one attribute-compatible field", function()
		local snap = Snapshot.credits(150)
		expect(snap.Credits).toBe(150)
	end)

	it("objective() returns exactly one field", function()
		local snap = Snapshot.objective(3)
		expect(snap.Objective).toBe(3)
	end)

	it("location() carries the location string through as-is", function()
		expect(Snapshot.location("Station").Location).toBe("Station")
		expect(Snapshot.location("Lobby").Location).toBe("Lobby")
	end)

	it("rebirth() carries every field through as-is", function()
		local snap = Snapshot.rebirth(2, true, false, 1.875)
		expect(snap.Rebirths).toBe(2)
		expect(snap.HasUltimate).toBe(true)
		expect(snap.HasEarlyRebirth).toBe(false)
		expect(snap.GlobalBoost).toBe(1.875)
	end)

	it("production() flattens the nested power/heat stats into a flat table", function()
		local snap = Snapshot.production({
			sunlight = 0.5,
			efficiency = 0.9,
			power = { production = 20, consumption = 12, charge = 100, storage = 120 },
			heat = { load = 10, capacity = 40 },
			income = 3.5,
		})
		expect(snap.Sunlight).toBe(0.5)
		expect(snap.Efficiency).toBe(0.9)
		expect(snap.PowerProduction).toBe(20)
		expect(snap.PowerConsumption).toBe(12)
		expect(snap.PowerCharge).toBe(100)
		expect(snap.PowerStorage).toBe(120)
		expect(snap.HeatLoad).toBe(10)
		expect(snap.HeatCapacity).toBe(40)
		expect(snap.Income).toBe(3.5)
	end)

	it("every field production() returns is a plain number (attribute-compatible)", function()
		local snap = Snapshot.production({
			sunlight = 1,
			efficiency = 1,
			power = { production = 1, consumption = 1, charge = 1, storage = 1 },
			heat = { load = 1, capacity = 1 },
			income = 1,
		})
		for _, value in snap do
			expect(typeof(value)).toBe("number")
		end
	end)
end)
