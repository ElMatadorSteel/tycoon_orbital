--!strict
-- The server's entry point -- the only Script directly under
-- ServerScriptService.Server (everything else is a ModuleScript, so nothing
-- else runs on its own). Mirrors the legacy Server.Bootstrap's role
-- (require the systems, start them) but delegates entirely to
-- Composition/Bootstrap.luau, which is where the actual wiring lives.

local Bootstrap = require("./Composition/Bootstrap")

Bootstrap.start()
