--!strict
-- Build-grid maths. No Instances, no Roblox datatypes (Vector2/Vector3 do
-- not exist under Lune, and Domain must stay engine-agnostic anyway --
-- cells and offsets are plain {x, y} / {x, y, z} tables). Ported from the
-- legacy Shared/Grid, minus fromWorld(): converting a mouse ray to a grid
-- cell is inherently CFrame-based and belongs to the client Adapter that
-- owns the camera, not to a rule.
--
-- Convention unchanged: a module of size (w, h) anchored at (x, y) occupies
-- cells x..x+w-1 and y..y+h-1.

export type Cell = { x: number, y: number }
export type Offset = { x: number, y: number, z: number }

export type Rules = {
	cellSize: number,
	radius: number, -- half-width of the grid, in cells
}

local Grid = {}

function Grid.key(x: number, y: number): string
	return `{x},{y}`
end

-- Every cell covered by a module.
function Grid.cells(x: number, y: number, width: number, height: number): { Cell }
	local cells = {}
	for dx = 0, width - 1 do
		for dy = 0, height - 1 do
			table.insert(cells, { x = x + dx, y = y + dy })
		end
	end
	return cells
end

function Grid.isCellInBounds(x: number, y: number, rules: Rules): boolean
	return math.abs(x) <= rules.radius and math.abs(y) <= rules.radius
end

function Grid.isInBounds(x: number, y: number, width: number, height: number, rules: Rules): boolean
	return Grid.isCellInBounds(x, y, rules)
		and Grid.isCellInBounds(x + width - 1, y + height - 1, rules)
end

-- Offset of a module's centre from the station's origin.
function Grid.offset(x: number, y: number, width: number, height: number, rules: Rules): Offset
	return {
		x = (x + (width - 1) / 2) * rules.cellSize,
		y = 0,
		z = (y + (height - 1) / 2) * rules.cellSize,
	}
end

-- The four orthogonal neighbours of a cell.
function Grid.neighbours(x: number, y: number): { Cell }
	return {
		{ x = x, y = y + 1 },
		{ x = x + 1, y = y },
		{ x = x, y = y - 1 },
		{ x = x - 1, y = y },
	}
end

return Grid
