--!strict
-- Development-only: puts ore in the bag so the exchange can be exercised
-- before digging exists to fill it.
--
-- Real path, separate data, enabled by the composition root (DEVELOPMENT.md).
-- It writes profile.ores and publishes through Snapshot.ore exactly as mining
-- will, so what gets tested is the production pipeline rather than a shortcut
-- around it -- and it lives in its own file so a published build, whose
-- Container never builds it, cannot reach it at all.

local function fromShared(path: string): any
	if game then
		local node: any = (game :: any):GetService("ReplicatedStorage").Shared
		for segment in path:gmatch("[^/]+") do
			node = node[segment]
		end
		return node
	end
	return "../../../Shared/" .. path
end

local OreCatalog = require(fromShared("Domain/Research/OreCatalog"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	statsPublisher: any, -- Ports.StatsPublisher
}

local DevGiveOres = {}
DevGiveOres.__index = DevGiveOres

-- `oreId` nil gives some of everything, which is the case worth one keypress.
function DevGiveOres:run(userId: number, oreId: string?, amount: number?): Result<nil, string>
	local count = math.floor(tonumber(amount) or 10)
	if count <= 0 then
		return Result.err("invalid amount")
	end
	if oreId ~= nil and not OreCatalog.get(oreId) then
		return Result.err("unknown ore")
	end

	local profile = self.profileRepository:load(userId)

	for _, ore in OreCatalog.Ores do
		if oreId == nil or ore.id == oreId then
			local held = (profile.ores[ore.id] or 0) + count
			profile.ores[ore.id] = held
			self.statsPublisher:publish(userId, Snapshot.ore(ore.id, held))
		end
	end

	self.profileRepository:save(userId, profile)
	return Result.ok(nil)
end

return DevGiveOres
