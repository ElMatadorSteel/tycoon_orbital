--!strict
-- Checks the REAL production config for internal consistency (ladders rise,
-- no required field missing) -- deliberately the one spec allowed to touch
-- the real Balance module, per DEVELOPMENT.md.
local Balance = require(Config)

describe("Balance internal consistency", function()
	it("has positive starting credits", function()
		expect(Balance.Economy.StartingCredits > 0).toBeTruthy()
	end)

	it("has a refund ratio between 0 and 1", function()
		expect(Balance.Economy.RefundRatio >= 0 and Balance.Economy.RefundRatio <= 1).toBeTruthy()
	end)

	it("has an upgrade ladder that actually rises", function()
		expect(Balance.Upgrade.MaxLevel > 1).toBeTruthy()
		expect(Balance.Upgrade.GainPerLevel > 0).toBeTruthy()
		expect(Balance.Upgrade.CostFactor > 1).toBeTruthy()
		expect(Balance.Upgrade.MinCost > 0).toBeTruthy()
	end)

	it("has save/retry settings that terminate", function()
		expect(Balance.Save.RetryCount > 0).toBeTruthy()
		expect(Balance.Save.RetryDelay > 0).toBeTruthy()
		expect(Balance.Save.MaxModules > 0).toBeTruthy()
		expect(Balance.Save.StoreName ~= "").toBeTruthy()
	end)

	it("keeps the module save cap above what the grid can ever hold", function()
		-- MaxModules is a safety net, deliberately above the grid's real
		-- capacity (2*Radius+1)^2 -- see Save.MaxModules's comment. If it
		-- ever dropped below that, a full station could lose modules on
		-- save.
		local cells = (2 * Balance.Grid.Radius + 1) ^ 2
		expect(Balance.Save.MaxModules >= cells).toBeTruthy()
	end)

	it("keeps the eclipse fraction within one full orbit", function()
		expect(Balance.Orbit.EclipseFraction > 0 and Balance.Orbit.EclipseFraction < 1).toBeTruthy()
		expect(Balance.Orbit.Period > 0).toBeTruthy()
	end)

	it("degrades but never fully stops production when overheated", function()
		expect(Balance.Heat.OverheatPenalty > 0 and Balance.Heat.OverheatPenalty < 1).toBeTruthy()
	end)
end)
