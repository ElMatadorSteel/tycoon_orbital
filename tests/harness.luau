--!strict
-- Rebuilds `Shared` and `Server` as nested tables mirroring src/Shared and
-- src/Server, by walking the disk and requiring every .luau module found.
-- This is a deliberate, simpler stand-in for ARCHITECTURE.md's "harness that
-- rebuilds the Roblox tree ... and provides script, require and
-- game:GetService": Lune has no `loadstring`, so a literal fake-Instance +
-- require(instance) emulation isn't possible. Instead, every module is
-- pre-required once here, and a shadow `require` (installed by run.luau)
-- treats a non-string argument as an already-resolved module and returns it
-- as-is -- so a spec can still write `require(Domain.Economy.Spend)` exactly
-- like the DEVELOPMENT.md example, it just resolves eagerly instead of
-- lazily. Domain/Application code itself never depends on this file.
--
-- IMPORTANT: fs.* paths below are resolved relative to the process's CWD
-- (always the repo root -- see scripts/test.ps1), while require() paths are
-- resolved relative to *this file* (tests/harness.luau) -- two different
-- bases, do not mix them up.

local fs = require("@lune/fs")

local function walk(diskDir: string, requireDir: string): { [string]: any }
	local node: { [string]: any } = {}
	local entries = fs.readDir(diskDir)
	table.sort(entries)
	for _, name in entries do
		local childDisk = `{diskDir}/{name}`
		local meta = fs.metadata(childDisk)
		if meta.kind == "dir" then
			node[name] = walk(childDisk, `{requireDir}/{name}`)
		elseif name:match("%.luau$") then
			local moduleName = (name:gsub("%.luau$", ""))
			node[moduleName] = require(`{requireDir}/{name}`)
		end
	end
	return node
end

local harness = {}

-- src/Shared/Domain and Server/Application are walked in full -- both are,
-- by the dependency rule, guaranteed to touch no Roblox API, so they load
-- fine under Lune. src/Shared itself is NOT walked wholesale: it also holds
-- Net.luau, which touches game:GetService at module load time (it creates
-- its RemoteEvents/Functions immediately on require) -- so Shared is built
-- one known-safe entry at a time instead, the same way Composition.Container
-- is singled out below. Server/Adapters is, for the same reason, never
-- auto-required here either ("a test of them would only assert that the
-- engine does what the engine does", per ARCHITECTURE.md, is the other half
-- of why it doesn't matter).
harness.Shared = {
	Domain = walk("src/Shared/Domain", "../src/Shared/Domain"),
	Balance = require("../src/Shared/Balance"),
	Signal = require("../src/Shared/Signal"),
	Icons = require("../src/Shared/Icons"),
}
harness.Application = walk("src/Server/Application", "../src/Server/Application")

-- Convenience aliases matching DEVELOPMENT.md's list of spec globals.
-- Config -> Shared.Balance, not a Shared.Config sub-table: there is no
-- Config/ folder under src/Shared (see src/Shared/Balance.luau's header
-- for why -- it collided with a legacy ModuleScript at that exact path).
harness.Domain = harness.Shared.Domain
harness.Config = harness.Shared.Balance
harness.Server = { Application = harness.Application }

-- Composition/Container.luau is Roblox-API-free by design (it takes ports
-- as an argument instead of requiring a concrete adapter) and is exactly
-- what integration specs mount with fake ports, per DEVELOPMENT.md. It is
-- named individually rather than picked up by a walk of the whole
-- Composition/ folder, because Composition/Bootstrap.luau -- its sibling --
-- is NOT safe to require here: it chooses and constructs the real DataStore
-- adapter, which touches game:GetService at module load time.
--
-- Specs must reach any of this through the globals below, not through their
-- own "./relative" require()s: run.luau's shadowed global `require` routes
-- every string path through a call written in run.luau's own source, so a
-- spec-authored relative path would silently resolve against tests/, not
-- against the spec file itself.
harness.Composition = {
	Container = require("../src/Server/Composition/Container"),
}

harness.Tree = {
	ReplicatedStorage = { Shared = harness.Shared },
	ServerScriptService = { Server = harness.Server },
}

return harness
