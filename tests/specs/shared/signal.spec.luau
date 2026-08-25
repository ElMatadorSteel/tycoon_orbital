--!strict
local Signal = require(Shared.Signal)

describe("Signal", function()
	it("calls every connected listener with the fired arguments", function()
		local signal = Signal.new()
		local received = {}
		signal:Connect(function(a, b)
			table.insert(received, { a, b })
		end)
		signal:Connect(function(a, b)
			table.insert(received, { a, b })
		end)

		signal:Fire("Credits", 150)

		expect(#received).toBe(2)
		expect(received[1][1]).toBe("Credits")
		expect(received[1][2]).toBe(150)
	end)

	it("stops calling a listener once it disconnects", function()
		local signal = Signal.new()
		local calls = 0
		local connection = signal:Connect(function()
			calls += 1
		end)

		signal:Fire()
		connection:Disconnect()
		signal:Fire()

		expect(calls).toBe(1)
	end)

	it("does not skip or double-call listeners when one disconnects itself mid-fire", function()
		local signal = Signal.new()
		local calls = 0
		local selfConnection: any = nil
		selfConnection = signal:Connect(function()
			calls += 1
			selfConnection:Disconnect()
		end)
		signal:Connect(function()
			calls += 1
		end)

		signal:Fire()

		expect(calls).toBe(2)
	end)

	it("fires with no arguments when none are given", function()
		local signal = Signal.new()
		local sawNil = false
		signal:Connect(function(value)
			sawNil = value == nil
		end)
		signal:Fire()
		expect(sawNil).toBeTruthy()
	end)
end)
