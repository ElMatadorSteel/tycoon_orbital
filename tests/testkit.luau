--!strict
-- Minimal hand-rolled BDD runner (describe/it/beforeEach/expect). No
-- external test framework dependency -- see DEVELOPMENT.md's "Test first"
-- section for why the harness is worth owning: it must run identically
-- under Lune, in tens of milliseconds, with nothing to install per-machine.

export type Failure = { path: string, message: string }
export type Summary = { passed: number, failed: number, failures: { Failure } }

local testkit = {}

local suiteNames: { string } = {}
local hookStack: { { () -> () } } = {}
local passed = 0
local failed = 0
local failures: { Failure } = {}

function testkit.describe(name: string, fn: () -> ())
	table.insert(suiteNames, name)
	table.insert(hookStack, {})
	local ok, err = pcall(fn)
	table.remove(hookStack)
	table.remove(suiteNames)
	if not ok then
		error(err, 0)
	end
end

function testkit.beforeEach(fn: () -> ())
	local hooks = hookStack[#hookStack]
	if not hooks then
		error("beforeEach() called outside of a describe() block", 0)
	end
	table.insert(hooks, fn)
end

function testkit.it(name: string, fn: () -> ())
	for _, hooks in hookStack do
		for _, hook in hooks do
			hook()
		end
	end

	local path = table.concat(suiteNames, " > ") .. " > " .. name
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, { path = path, message = tostring(err) })
	end
end

-- Deep-enough equality for the plain data tables specs compare (profiles,
-- placements, Result values) -- not a general-purpose deep-equal.
local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if typeof(a) ~= "table" or typeof(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil and b[key] ~= nil then
			return false
		end
	end
	return true
end

local function fail(message: string): never
	-- Level 3: blame the spec's assertion line, not expect()/fail() themselves.
	error(message, 3)
end

function testkit.expect(actual: any)
	return {
		toBe = function(expected: any)
			if actual ~= expected then
				fail(`expected {tostring(actual)} to be {tostring(expected)}`)
			end
		end,
		toEqual = function(expected: any)
			if not deepEqual(actual, expected) then
				fail(`expected {tostring(actual)} to equal {tostring(expected)}`)
			end
		end,
		toBeTruthy = function()
			if not actual then
				fail(`expected {tostring(actual)} to be truthy`)
			end
		end,
		toBeFalsy = function()
			if actual then
				fail(`expected {tostring(actual)} to be falsy`)
			end
		end,
		toBeNil = function()
			if actual ~= nil then
				fail(`expected {tostring(actual)} to be nil`)
			end
		end,
		toBeNear = function(expected: number, tolerance: number?)
			local eps = tolerance or 1e-6
			if typeof(actual) ~= "number" or math.abs(actual - expected) > eps then
				fail(`expected {tostring(actual)} to be near {expected} (+/- {eps})`)
			end
		end,
	}
end

function testkit.summary(): Summary
	return { passed = passed, failed = failed, failures = failures }
end

return testkit
