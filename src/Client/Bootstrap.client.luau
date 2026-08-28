--!strict
-- Client entry point. Starts each controller in a fixed order, mirroring
-- the legacy Client.Bootstrap -- see CLAUDE.md's "Migration status" for why
-- the order matters: HudController builds the ScreenGui the others parent
-- onto conceptually first, ObjectiveController and LabelController don't
-- depend on each other, BuildController is last since it's the heaviest.

local HudController = require("./Controllers/HudController")
local BuildController = require("./Controllers/BuildController")
local ObjectiveController = require("./Controllers/ObjectiveController")
local LabelController = require("./Controllers/LabelController")
local MiningController = require("./Controllers/MiningController")
local DevController = require("./Controllers/DevController")

local CONTROLLERS = {
	{ name = "HudController", controller = HudController },
	{ name = "BuildController", controller = BuildController },
	{ name = "ObjectiveController", controller = ObjectiveController },
	{ name = "LabelController", controller = LabelController },
	{ name = "MiningController", controller = MiningController },
	-- Last: a no-op outside Studio (see its own header), so it never delays
	-- anything real if it were ever slow to start.
	{ name = "DevController", controller = DevController },
}

for _, entry in CONTROLLERS do
	entry.controller:Start()
	print(`[Bootstrap] {entry.name} started`)
end
