--!strict
-- The five rarity tiers a mineral can belong to. Pure classification data --
-- an ore's own id/colour/value/depth/hardness already live in OreCatalog,
-- this file only names the five buckets those ores are sorted into and their
-- display order, so a label or a filter can read "Common" -> "Commun" and
-- rank tiers against each other without hardcoding the list a second time.

export type RarityId = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type RarityDef = {
	id: RarityId,
	name: string,
	-- Ascending: 1 is the most common, 5 the rarest. Used to sort a UI list
	-- or to compare two tiers ("is this rarer than that") without string
	-- comparison.
	order: number,
}

local Rarity = {}

-- Ordered list, index == `order`: the display order IS the array order, so
-- there is only one place that can drift from the other.
local LIST: { RarityDef } = {
	{ id = "Common", name = "Commun", order = 1 },
	{ id = "Rare", name = "Rare", order = 2 },
	{ id = "Epic", name = "Épique", order = 3 },
	{ id = "Legendary", name = "Légendaire", order = 4 },
	{ id = "Mythic", name = "Mythique", order = 5 },
}

Rarity.List = LIST

function Rarity.get(id: string): RarityDef?
	for _, rarity in LIST do
		if rarity.id == id then
			return rarity
		end
	end
	return nil
end

return Rarity
