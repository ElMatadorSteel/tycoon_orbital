--!strict
-- Where each station plot sits -- ported from the layout loop in the legacy
-- PlotService:Start(). Pure: returns plain {x, y, z} positions, not a
-- CFrame (no Roblox datatypes in Domain -- see CLAUDE.md). The Adapter that
-- actually builds the plot converts to a real CFrame at the point of use.
--
-- Orientation stays aligned to the world axes on purpose: the build grid
-- depends on it, and nothing justifies complicating that.

export type Rules = {
	centerX: number,
	centerZ: number,
	count: number,
	distance: number, -- studs between the lobby and a plot at its base distance
	spread: number, -- degrees between two plots
	altitude: number,
}

export type Slot = { index: number, x: number, y: number, z: number }

-- Alternating distance/altitude offsets, purely for visual variety (reads
-- as ships in orbit rather than a straight row of platforms) -- not
-- balance numbers, so they stay local constants here rather than moving
-- into Config, same as the legacy PlotService treated them.
local ALTERNATE_DISTANCE = 160
local ALTITUDE_STEP = 65

local Layout = {}

function Layout.slots(rules: Rules): { Slot }
	local spreadRad = math.rad(rules.spread)
	local middle = (rules.count + 1) / 2

	local result = {}
	for index = 1, rules.count do
		local angle = (index - middle) * spreadRad
		local distance = rules.distance + (if index % 2 == 0 then ALTERNATE_DISTANCE else 0)
		local altitude = rules.altitude + (index % 3 - 1) * ALTITUDE_STEP

		table.insert(result, {
			index = index,
			x = rules.centerX + math.sin(angle) * distance,
			y = altitude,
			z = rules.centerZ + math.cos(angle) * distance,
		})
	end
	return result
end

return Layout
