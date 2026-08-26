--!strict
-- Data-only catalogue of buildable modules: gameplay numbers only. Ported
-- from the legacy Shared/ModuleCatalog, deliberately WITHOUT color/material
-- (Color3/Enum.Material are Roblox datatypes -- Domain must stay
-- engine-agnostic, and they don't exist under Lune anyway). Those live in a
-- presentation-side catalogue, keyed by the same id, added when the Client
-- restructuring stage needs it -- nothing consumes it yet.
--
-- power   : positive = produces energy, negative = consumes it (per second)
-- heat    : positive = radiates heat, negative = dissipation capacity
-- carries : the module is part of the resource network. Two adjacent
--           modules that both carry are connected -- this is what makes
--           conduits necessary: a corridor carries nothing, it's only
--           walkable.

export type Size = { w: number, h: number }

export type ModuleDef = {
	id: string,
	name: string,
	description: string,
	category: string,
	size: Size,
	height: number,
	cost: number,
	power: number,
	heat: number,
	input: string?,
	output: string?,
	rate: number?,
	capacity: number?,
	carries: boolean?,
	needsClearance: boolean?,
	unique: boolean?,
}

export type ResourceDef = {
	id: string,
	name: string,
	value: number,
}

export type UpgradeRules = {
	maxLevel: number,
	gainPerLevel: number,
	costFactor: number,
	minCost: number,
	-- The core's own base cost is 0 (it ships with the station, see below),
	-- which would make the generic formula's floor its ENTIRE cost forever,
	-- never growing with level -- a dedicated flat rate instead, set higher
	-- than that floor on purpose (see Balance.Upgrade's own comment).
	coreUpgradeCost: number,
}

local ModuleCatalog = {}

ModuleCatalog.Resources = {
	Ore = { id = "Ore", name = "Minerai", value = 5 },
	Alloy = { id = "Alloy", name = "Alliage", value = 22 },
	Component = { id = "Component", name = "Composant", value = 75 },
} :: { [string]: ResourceDef }

ModuleCatalog.Categories = {
	"Structure",
	"Logistique",
	"Energie",
	"Thermique",
	"Production",
	"Commerce",
}

ModuleCatalog.Order = {
	"Core",
	"Corridor",
	"Conduit",
	"SolarPanel",
	"Battery",
	"Radiator",
	"OreCollector",
	"Smelter",
	"Fabricator",
	"CargoBay",
}

ModuleCatalog.Modules = {
	Core = {
		id = "Core",
		name = "Noyau",
		category = "Structure",
		description = "Le coeur de la station. Fournit l'énergie de démarrage.",
		size = { w = 2, h = 2 },
		height = 4,
		cost = 0,
		power = 20,
		heat = 2,
		carries = true,
		unique = true,
	},

	Corridor = {
		id = "Corridor",
		name = "Coursive",
		category = "Structure",
		description = "Passage praticable. Ne transporte aucune ressource.",
		size = { w = 1, h = 1 },
		height = 1,
		cost = 25,
		power = 0,
		heat = 0,
	},

	Conduit = {
		id = "Conduit",
		name = "Conduit",
		category = "Logistique",
		description = "Relie deux modules éloignés dans le même réseau.",
		size = { w = 1, h = 1 },
		height = 1.2,
		cost = 40,
		power = -0.5,
		heat = 0.2,
		carries = true,
	},

	SolarPanel = {
		id = "SolarPanel",
		name = "Panneau solaire",
		category = "Energie",
		description = "Produit de l'énergie, mais rien du tout dans l'ombre.",
		size = { w = 2, h = 1 },
		height = 0.6,
		cost = 150,
		power = 12,
		heat = 1,
	},

	Battery = {
		id = "Battery",
		name = "Batterie",
		category = "Energie",
		description = "Stocke l'énergie. C'est elle qui fait passer l'éclipse.",
		size = { w = 1, h = 1 },
		height = 2,
		cost = 200,
		power = 0,
		heat = 0.5,
		capacity = 120,
	},

	Radiator = {
		id = "Radiator",
		name = "Radiateur",
		category = "Thermique",
		description = "Évacue la chaleur. Inefficace s'il est enfermé entre des modules.",
		size = { w = 2, h = 1 },
		height = 0.5,
		cost = 180,
		power = -1,
		heat = 0,
		needsClearance = true,
	},

	OreCollector = {
		id = "OreCollector",
		name = "Collecteur",
		category = "Production",
		description = "Capte le minerai des débris en orbite.",
		size = { w = 2, h = 2 },
		height = 3,
		cost = 300,
		power = -8,
		heat = 6,
		output = "Ore",
		rate = 1,
		carries = true,
	},

	Smelter = {
		id = "Smelter",
		name = "Fonderie",
		category = "Production",
		description = "Transforme le minerai en alliage. Chauffe beaucoup.",
		size = { w = 2, h = 2 },
		height = 3.5,
		cost = 600,
		power = -14,
		heat = 14,
		input = "Ore",
		output = "Alloy",
		rate = 0.6,
		carries = true,
	},

	Fabricator = {
		id = "Fabricator",
		name = "Fabricateur",
		category = "Production",
		description = "Assemble les alliages en composants de grande valeur.",
		size = { w = 2, h = 2 },
		height = 3.5,
		cost = 1200,
		power = -20,
		heat = 16,
		input = "Alloy",
		output = "Component",
		rate = 0.4,
		carries = true,
	},

	CargoBay = {
		id = "CargoBay",
		name = "Soute",
		category = "Commerce",
		description = "Vend tout ce qui circule dans son réseau. Sans elle, rien ne rapporte.",
		size = { w = 2, h = 2 },
		height = 2.5,
		cost = 400,
		power = -4,
		heat = 2,
		rate = 4,
		carries = true,
	},
} :: { [string]: ModuleDef }

function ModuleCatalog.get(id: string): ModuleDef?
	return ModuleCatalog.Modules[id]
end

-- Effective dimensions of a module after rotation. `rotation` counts
-- quarter-turns (0-3, clockwise); an odd number swaps width and height, an
-- even one leaves them as they are.
function ModuleCatalog.sizeOf(definition: ModuleDef, rotation: number?): (number, number)
	if rotation and rotation % 2 == 1 then
		return definition.size.h, definition.size.w
	end
	return definition.size.w, definition.size.h
end

----------------------------------------------------------------------
-- Levels
--
-- A level-1 module is worth EXACTLY its sheet: the catalogue above stays
-- readable as-is, without having to mentally multiply it.

function ModuleCatalog.levelMultiplier(level: number?, rules: UpgradeRules): number
	local rank = math.max(1, level or 1)
	return 1 + (rank - 1) * rules.gainPerLevel
end

-- Cost of moving to the next level, from the current one. Geometric growth:
-- the first tier is affordable, the last one is earned.
--
-- The core is a special case: its base cost is 0 (it ships with the
-- station, not bought), so the generic formula would floor it at a FLAT
-- rate forever -- which is still the intent, just at its own dedicated
-- rate rather than the shared minCost every other module's floor uses.
function ModuleCatalog.upgradeCost(
	definition: ModuleDef,
	level: number,
	rules: UpgradeRules
): number
	if definition.id == "Core" then
		return rules.coreUpgradeCost
	end
	return math.max(rules.minCost, math.floor(definition.cost * rules.costFactor ^ level))
end

-- A module that produces nothing measurable doesn't get levels: a corridor
-- or a conduit would stay identical, and the button would lie.
function ModuleCatalog.isUpgradable(definition: ModuleDef): boolean
	return definition.power > 0
		or definition.capacity ~= nil
		or definition.rate ~= nil
		or definition.needsClearance == true
end

return ModuleCatalog
