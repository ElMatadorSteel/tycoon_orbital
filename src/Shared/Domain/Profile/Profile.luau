--!strict
-- The persisted entity and its schema migration. Ported from the legacy
-- SaveService's blank()/sanitize() -- same guards, same defaults, just
-- moved out from under the DataStore code that used to surround it.
--
-- Never trust what comes out of a save: a previous version of the game may
-- have written a different shape entirely.
--
-- Takes its balance numbers as a `Rules` argument instead of requiring
-- Shared/Balance directly: Domain depends on nothing (ARCHITECTURE.md), and
-- domain specs use their own fixtures rather than the real configuration so
-- that rebalancing never breaks a test (DEVELOPMENT.md). Callers (Adapters,
-- Application) read the real Balance module and pass it in.

local VERSION = 1

export type Rules = {
	startingCredits: number,
	maxModules: number,
	maxLevel: number,
}

-- `r` absent from a save predating rotation: restored at 0, a harmless
-- default. `lv` absent from a save predating levels: restored at 1, exactly
-- the state of a module never upgraded. No migration needed either way.
export type SavedModule = { id: string, x: number, y: number, r: number, lv: number }

-- The persisted state of the research mine's digging grid. Generated
-- randomly, regenerated every Balance.Research.RegenInterval seconds.
-- Between regenerations the dug/ore state survives disconnections.
export type SavedMine = {
	generatedAt: number,
	layers: {
		{
			ores: { [string]: string }, -- cellKey → ore id
			dug: { [string]: boolean }, -- cellKey → true
		}
	},
}

export type Profile = {
	version: number,
	credits: number,
	modules: { SavedModule },
	objective: number, -- rank in the Shared/Objectives chain, 1 = the first
	-- Reserved for progression. Already written and read today so there is
	-- no migration to do the day they get wired up.
	unlocked: { [string]: boolean },
	-- What the research mine has produced and the player has not sold yet.
	-- Keyed by Domain/Research/OreCatalog id. Persisted rather than session-
	-- only because it is earned, not derived: a disconnection must not empty
	-- a bag the player spent time filling.
	ores: { [string]: number },
	-- The digging grid state, nil until the mine is first generated.
	mine: SavedMine?,
	rebirths: number,
	playtime: number,
	savedAt: number,
}

local Profile = {}

function Profile.blank(rules: Rules): Profile
	return {
		version = VERSION,
		credits = rules.startingCredits,
		modules = {},
		objective = 1,
		unlocked = {},
		ores = {},
		rebirths = 0,
		playtime = 0,
		savedAt = 0,
	}
end

-- value ~= value catches NaN, which survives a DataStore round-trip
-- untouched and contaminates every downstream computation.
local function number(value: any, fallback: number): number
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return value
end

function Profile.sanitize(raw: any, rules: Rules): Profile
	local profile = Profile.blank(rules)
	if typeof(raw) ~= "table" then
		return profile
	end

	profile.version = number(raw.version, VERSION)
	profile.credits = math.max(0, math.floor(number(raw.credits, profile.credits)))
	-- A save predating objectives has no such field: it restarts from the
	-- first one. That is exactly the intended behaviour, no migration.
	profile.objective = math.max(1, math.floor(number(raw.objective, 1)))
	profile.rebirths = math.max(0, math.floor(number(raw.rebirths, 0)))
	profile.playtime = math.max(0, number(raw.playtime, 0))
	profile.savedAt = math.max(0, number(raw.savedAt, 0))

	if typeof(raw.unlocked) == "table" then
		for key, value in raw.unlocked do
			if typeof(key) == "string" and value == true then
				profile.unlocked[key] = true
			end
		end
	end

	-- A save predating the mine has no bag at all: it starts empty, which is
	-- exactly right, so there is no migration to write. Ids are NOT checked
	-- against the catalogue here -- same reason module ids are not (see
	-- below): this module knows no game rules. An ore retired from the
	-- catalogue simply appraises at nothing.
	if typeof(raw.ores) == "table" then
		for key, value in raw.ores do
			if typeof(key) == "string" then
				local count = math.floor(number(value, 0))
				if count > 0 then
					profile.ores[key] = count
				end
			end
		end
	end

	-- The mine grid state. Validated structurally but NOT checked against
	-- the current layer config: a save can outlive a layer-count change,
	-- and the use case that loads the mine will regenerate it if stale.
	if typeof(raw.mine) == "table" then
		local mine = raw.mine
		local genAt = number(mine.generatedAt, 0)
		if genAt > 0 and typeof(mine.layers) == "table" then
			local sanitizedLayers = {}
			for i, layer in mine.layers do
				if typeof(layer) == "table" then
					local ores: { [string]: string } = {}
					local dug: { [string]: boolean } = {}
					if typeof(layer.ores) == "table" then
						for k, v in layer.ores do
							if typeof(k) == "string" and typeof(v) == "string" then
								ores[k] = v
							end
						end
					end
					if typeof(layer.dug) == "table" then
						for k, v in layer.dug do
							if typeof(k) == "string" and v == true then
								dug[k] = true
							end
						end
					end
					sanitizedLayers[i] = { ores = ores, dug = dug }
				end
			end
			if #sanitizedLayers > 0 then
				profile.mine = {
					generatedAt = genAt,
					layers = sanitizedLayers,
				}
			end
		end
	end

	if typeof(raw.modules) == "table" then
		for _, entry in raw.modules do
			if #profile.modules >= rules.maxModules then
				break
			end
			-- The id is not checked against the catalogue here: that is the
			-- station system's job, when it tries to re-place the module.
			-- This module knows nothing about the game's placement rules.
			if typeof(entry) == "table" and typeof(entry.id) == "string" then
				table.insert(profile.modules, {
					id = entry.id,
					x = math.round(number(entry.x, 0)),
					y = math.round(number(entry.y, 0)),
					-- Quarter-turns: 4 possible orientations, not just 0/1.
					r = math.floor(number(entry.r, 0)) % 4,
					lv = math.clamp(math.floor(number(entry.lv, 1)), 1, rules.maxLevel),
				})
			end
		end
	end

	return profile
end

return Profile
