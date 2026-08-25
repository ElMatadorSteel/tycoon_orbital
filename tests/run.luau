--!strict
-- Entry point: `lune run tests/run.luau [-- <filter>]`, always from the repo
-- root (scripts/test.ps1 enforces this -- fs.* paths below are CWD-relative,
-- unlike require() which is relative to this file).

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local ORIGINAL_REQUIRE = require

local testkit = require("./testkit")
local harness = require("./harness")
local fakes = require("./fakes")

-- Globals available to every spec -- see DEVELOPMENT.md's "Globals
-- available in a spec". Must be set before any spec is require()'d.
describe = testkit.describe
it = testkit.it
beforeEach = testkit.beforeEach
expect = testkit.expect
Domain = harness.Domain
Application = harness.Application
Config = harness.Config
Shared = harness.Shared
Server = harness.Server
Tree = harness.Tree
Composition = harness.Composition
Fakes = fakes

-- DEVELOPMENT.md's own example spec writes `require(Domain.Subject.MyRule)`
-- -- a table, not a path, since Domain.Subject.MyRule is already the loaded
-- module (see harness.luau for why: Lune has no loadstring, so nothing here
-- can lazily load an arbitrary Instance-like reference). This shadow makes
-- that literal idiom work: a non-string argument is already-resolved and is
-- returned as-is; a genuine string path still goes through Lune's real
-- require. Specs should reach Domain/Application code through the globals
-- above, not through their own "./relative" requires -- a spec-authored
-- relative path would resolve against *this* file, not the spec's own
-- location, since that's where the call ends up once it falls through here.
require = function(target: any): any
	if typeof(target) == "string" then
		return ORIGINAL_REQUIRE(target)
	end
	return target
end

local SPECS_DIR = "tests/specs"

local function collectSpecs(dir: string): { string }
	local files = {}
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, name in entries do
		local path = `{dir}/{name}`
		local meta = fs.metadata(path)
		if meta.kind == "dir" then
			for _, nested in collectSpecs(path) do
				table.insert(files, nested)
			end
		elseif name:match("%.spec%.luau$") then
			table.insert(files, path)
		end
	end
	return files
end

local filter = process.args[1]
if filter == "" then
	filter = nil
end

local specs = collectSpecs(SPECS_DIR)
local ran = 0

for _, path in specs do
	if not filter or path:find(filter, 1, true) then
		ran += 1
		-- Relative to this file: strip the "tests/" prefix and the
		-- extension, e.g. "tests/specs/domain/economy/spend.spec.luau" ->
		-- "./specs/domain/economy/spend.spec".
		local requirePath = "./" .. (path:gsub("^tests/", ""):gsub("%.luau$", ""))
		ORIGINAL_REQUIRE(requirePath)
	end
end

local summary = testkit.summary()
stdio.write(`\n{ran} spec file(s), {summary.passed} passed, {summary.failed} failed\n`)
for _, failure in summary.failures do
	stdio.write(`  x {failure.path}\n    {failure.message}\n\n`)
end

if ran == 0 then
	stdio.write(`No spec matched{if filter then ` filter "{filter}"` else ""}.\n`)
	process.exit(1)
end
if summary.failed > 0 then
	process.exit(1)
end
