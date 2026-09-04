--!strict
-- The ore backpack: a fixed-capacity bag a player fills by digging and
-- empties by selling. Capacity is a hard ceiling, not an upgradeable stat.

local Backpack = {}

function Backpack.count(bag: { [string]: number }): number
	local total = 0
	for _, n in bag do
		if n > 0 then
			total += n
		end
	end
	return total
end

function Backpack.isFull(bag: { [string]: number }, capacity: number): boolean
	return Backpack.count(bag) >= capacity
end

return Backpack
