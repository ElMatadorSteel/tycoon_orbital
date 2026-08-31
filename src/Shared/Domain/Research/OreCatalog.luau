--!strict
-- What the research mine is made of. Pure data, in the shape
-- Domain/Station/ModuleCatalog and Domain/Mining/AsteroidTiers already use:
-- an ordered list plus a lookup, no Roblox API and no Balance read.
--
-- Today this only names and colours the veins the mine is built with. It is
-- declared as a catalogue rather than as a colour table in the builder
-- because the digging and the rocket repair that follow both need the same
-- identities, and a vein whose ore is implied by its colour is a vein no
-- rule can talk about.
--
-- `colour` is a plain {R, G, B} rather than a Color3: Domain stays free of
-- Roblox datatypes so it loads under Lune (same reason as Balance.Lobby.
-- Center) -- the Adapter converts at the point of use.

local Rarity = require("./Rarity")

export type Ore = {
	id: string,
	name: string,
	colour: { R: number, G: number, B: number },
	-- Which of the five tiers this ore belongs to -- Common through Mythic.
	-- Independent of `depth`/`hardness` below: rarity is what the player
	-- reads on a label, depth/hardness are what the mine is built and dug
	-- with. They happen to rise together in this catalogue (a mine gets
	-- rarer as it gets deeper), but nothing enforces that they must.
	rarity: Rarity.RarityId,
	-- Which terrace of the pit it outcrops on, 1 = the rim, 3 = the floor.
	-- Depth is the whole difficulty curve of a mine: the builder reads this
	-- to place the veins, and the drill will read it to gate them.
	depth: number,
	-- How much work one vein takes to break, in arbitrary units. Pickaxe
	-- work and drill throughput will both be expressed against this, so
	-- retuning "how long does mining feel" stays one number per ore.
	hardness: number,
	value: number, -- credits one unit is worth when sold
}

local ORES: { Ore } = {
	{
		id = "Iron",
		name = "Fer",
		colour = { R = 176, G = 141, B = 116 },
		rarity = "Common",
		depth = 1,
		hardness = 1,
		value = 12,
	},
	{
		id = "Copper",
		name = "Cuivre",
		colour = { R = 232, G = 132, B = 62 },
		rarity = "Rare",
		depth = 1,
		hardness = 1.5,
		value = 25,
	},
	{
		id = "Titanium",
		name = "Titane",
		colour = { R = 118, G = 214, B = 232 },
		rarity = "Epic",
		depth = 2,
		hardness = 3,
		value = 70,
	},
	{
		id = "Iridium",
		name = "Iridium",
		colour = { R = 186, G = 124, B = 255 },
		rarity = "Legendary",
		depth = 3,
		hardness = 6,
		value = 210,
	},
	{
		id = "Etherite",
		name = "Éthérite",
		-- A pale, almost-white pink: the four ores below it all read as ROCK
		-- lit from within, this one is meant to read as LIGHT given a rock
		-- shape -- the rarest thing in the pit has to look like nothing else
		-- in it, not just like a brighter version of the same crystal.
		colour = { R = 255, G = 214, B = 250 },
		rarity = "Mythic",
		-- Shares the floor with Iridium rather than opening a fourth
		-- terrace: VEIN_ANGLES only ever hands the builder 4 slots per
		-- terrace, and OreCatalog.oreForVein already cycles through
		-- whichever ores share a depth -- two ores at depth 3 means the
		-- floor's four veins alternate Iridium/Etherite/Iridium/Etherite for
		-- free, no Adapter change required.
		depth = 3,
		hardness = 9,
		value = 630,
	},
}

local OreCatalog = {}

OreCatalog.Ores = ORES

-- How many veins the mine builder places per terrace (Adapters/Roblox/
-- ResearchMineBuilder's own VEIN_ANGLES). Kept here, not just there: vein
-- placement (the Adapter) and vein mining (MineVein, Application) both need
-- to agree on how a (terrace, slot) pair resolves to an ore, and one shared
-- formula is what makes that agreement possible instead of assumed.
OreCatalog.AnglesPerTerrace = 4

function OreCatalog.get(id: string): Ore?
	for _, ore in ORES do
		if ore.id == id then
			return ore
		end
	end
	return nil
end

function OreCatalog.atDepth(depth: number): { Ore }
	local result = {}
	for _, ore in ORES do
		if ore.depth == depth then
			table.insert(result, ore)
		end
	end
	return result
end

-- The one formula both the Adapter (placing a vein) and MineVein (paying out
-- a click on one) run: which ore sits at a given terrace's given angle slot.
-- A terrace with more than one ore cycles through them by slot -- this is
-- what puts Iridium AND Etherite on the floor from a single VEIN_ANGLES list.
function OreCatalog.oreForVein(terrace: number, slot: number): Ore?
	local ores = OreCatalog.atDepth(terrace)
	if #ores == 0 then
		return nil
	end
	return ores[(slot - 1) % #ores + 1]
end

-- The stable id stamped on a vein's Model (the "VeinId" attribute) and sent
-- back by the client when it is mined -- deliberately not the ore's own id,
-- since two veins in the same mine can share an ore (see Etherite above) and
-- MineVein has to tell them apart to enforce a per-vein cooldown.
function OreCatalog.veinId(terrace: number, slot: number): string
	return `T{terrace}_{slot}`
end

-- The inverse of veinId, for the server to recover (terrace, slot) from
-- whatever string a client sent -- which may not be one this format ever
-- produced (a stale build, a forged call), so this returns nil rather than
-- erroring on anything that doesn't parse.
function OreCatalog.parseVeinId(id: string): (number?, number?)
	local terrace, slot = id:match("^T(%d+)_(%d+)$")
	if not terrace or not slot then
		return nil, nil
	end
	return tonumber(terrace), tonumber(slot)
end

return OreCatalog
