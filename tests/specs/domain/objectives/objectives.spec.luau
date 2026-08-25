--!strict
local Objectives = require(Domain.Objectives.Objectives)

describe("Objectives", function()
	it("starts the chain with Embark", function()
		expect(Objectives.List[1].id).toBe("Embark")
	end)

	it("get() returns nil past the end of the chain", function()
		expect(Objectives.get(Objectives.Count + 1)).toBeNil()
	end)

	it("get() resolves every valid index", function()
		for index = 1, Objectives.Count do
			expect(Objectives.get(index) ~= nil).toBeTruthy()
		end
	end)

	it("Count matches the length of List", function()
		expect(Objectives.Count).toBe(#Objectives.List)
	end)

	it("has no empty title or hint anywhere in the chain", function()
		for _, objective in Objectives.List do
			expect(objective.title ~= "").toBeTruthy()
			expect(objective.hint ~= "").toBeTruthy()
		end
	end)

	it("never rewards a negative amount", function()
		for _, objective in Objectives.List do
			expect(objective.reward >= 0).toBeTruthy()
		end
		expect(Objectives.Completion.reward >= 0).toBeTruthy()
	end)
end)
