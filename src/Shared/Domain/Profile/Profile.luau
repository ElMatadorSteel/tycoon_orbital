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

export type Profile = {
	version: number,
	credits: number,
	modules: { SavedModule },
	objective: number, -- rank in the Shared/Objectives chain, 1 = the first
	-- Reserved for progression. Already written and read today so there is
	-- no migration to do the day they get wired up.
	unlocked: { [string]: boolean },
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
