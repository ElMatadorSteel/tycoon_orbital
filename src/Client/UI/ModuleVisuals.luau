--!strict
-- The presentation-side half of the module catalogue: color and icon, keyed
-- by the same id as Domain/Station/ModuleCatalog.luau. Split out because
-- Color3 is a Roblox datatype and Domain must stay loadable under Lune (see
-- ModuleCatalog.luau's header) -- this is the table CLAUDE.md's Stage 2
-- notes said would show up "when the Client stage needs one." Nothing but
-- the Client reads this.

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Client and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach -- confirmed the first time
-- Rojo actually connected Studio (see CLAUDE.md's cutover notes). Lune has
-- no `game`, so the fallback below -- an ordinary relative require -- is
-- what actually runs there, unchanged from before.
local function fromShared(path: string): any
	if game then
		local node: any = (game :: any):GetService("ReplicatedStorage").Shared
		for segment in path:gmatch("[^/]+") do
			node = node[segment]
		end
		return node
	end
	return "../../Shared/" .. path
end

local Icons = require(fromShared("Icons"))

export type Visual = { color: Color3, material: Enum.Material }

local ModuleVisuals = {}

ModuleVisuals.Colors = {
	Core = { color = Color3.fromRGB(210, 215, 225), material = Enum.Material.Metal },
	Corridor = { color = Color3.fromRGB(120, 126, 138), material = Enum.Material.Metal },
	Conduit = { color = Color3.fromRGB(95, 140, 175), material = Enum.Material.DiamondPlate },
	SolarPanel = { color = Color3.fromRGB(40, 60, 120), material = Enum.Material.Glass },
	Battery = { color = Color3.fromRGB(215, 170, 60), material = Enum.Material.Metal },
	Radiator = { color = Color3.fromRGB(200, 205, 210), material = Enum.Material.SmoothPlastic },
	OreCollector = { color = Color3.fromRGB(140, 120, 95), material = Enum.Material.Metal },
	Smelter = { color = Color3.fromRGB(180, 90, 60), material = Enum.Material.CorrodedMetal },
	Fabricator = { color = Color3.fromRGB(90, 175, 160), material = Enum.Material.Metal },
	CargoBay = { color = Color3.fromRGB(150, 155, 165), material = Enum.Material.DiamondPlate },
} :: { [string]: Visual }

-- One icon per module. Kept as its own table, same as the legacy catalogue:
-- swapping icon packs should never touch a module's gameplay definition.
ModuleVisuals.Icons = {
	Core = Icons.Stats["Power2"],
	Corridor = Icons.Arrows["Expand"],
	Conduit = Icons.Arrows["Trade"],
	SolarPanel = Icons.Stats["Energy"],
	Battery = Icons.Stats["Power"],
	Radiator = Icons.Currency["Fire"],
	OreCollector = Icons.Gems["GemIcon"],
	Smelter = Icons.Menus["Settings"],
	Fabricator = Icons.Stats["Rocket"],
	CargoBay = Icons.RNG["Crate"],
} :: { [string]: string }

-- One icon per build-menu tab. "Tous" (All) isn't a module category, hence
-- its own entry.
ModuleVisuals.CategoryIcons = {
	Tous = Icons.Misc["More"],
	Structure = Icons.Arrows["Expand"],
	Logistique = Icons.Arrows["Trade"],
	Energie = Icons.Stats["Energy"],
	Thermique = Icons.Currency["Fire"],
	Production = Icons.Menus["Settings"],
	Commerce = Icons.RNG["Crate"],
} :: { [string]: string }

function ModuleVisuals.colorOf(id: string): Color3?
	local visual = ModuleVisuals.Colors[id]
	return if visual then visual.color else nil
end

function ModuleVisuals.iconFor(id: string): string?
	return ModuleVisuals.Icons[id]
end

return ModuleVisuals
