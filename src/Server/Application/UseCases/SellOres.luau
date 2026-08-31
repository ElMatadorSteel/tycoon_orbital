--!strict
-- The research exchange: turn mined ore into credits. Sells ONE mineral when
-- given an id, the whole bag when given nothing -- the panel offers both, and
-- they are the same operation over a different subset rather than two.
--
-- Pricing is not decided here. OreCatalog.appraise owns it, for the same
-- reason Credits owns spending: a number the exchange invents is a number no
-- spec can pin down.

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
	notifier: any, -- Ports.Notifier
}

local SellOres = {}
SellOres.__index = SellOres

-- `oreId` nil sells everything. Returns the credits earned, so the caller can
-- say how much rather than just that it worked.
function SellOres:run(userId: number, oreId: string?): Result<number, string>
	-- Anything off the wire is checked before use: a remote is a public API
	-- and its caller is not necessarily our client (DEVELOPMENT.md).
	if oreId ~= nil and typeof(oreId) ~= "string" then
		return Result.err("invalid ore id")
	end
	if oreId ~= nil and not OreCatalog.get(oreId) then
		return Result.err("unknown ore")
	end

	local profile = self.profileRepository:load(userId)

	-- The subset being sold, gathered first so appraise() sees exactly what
	-- is about to leave the bag and the two can never disagree.
	local selling: { [string]: number } = {}
	for id, count in profile.ores do
		if count > 0 and (oreId == nil or id == oreId) then
			selling[id] = count
		end
	end

	if next(selling) == nil then
		return Result.err("nothing to sell")
	end

	local earned = OreCatalog.appraise(selling)
	if earned <= 0 then
		-- Everything on offer was a retired mineral. Refused rather than
		-- silently binned: emptying a bag for nothing is not a sale.
		return Result.err("nothing to sell")
	end

	for id in selling do
		profile.ores[id] = nil
	end
	profile.credits += earned
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.credits(profile.credits))
	-- Only the lines that actually changed, republished at zero. Publishing
	-- the whole catalogue every sale would rewrite attributes nothing touched.
	for id in selling do
		self.statsPublisher:publish(userId, Snapshot.ore(id, 0))
	end

	-- The same "+150" pill every other payout uses. GainFeed already knows the
	-- Credits kind, so the exchange needs no popup of its own.
	self.notifier:notify(userId, "Credits", earned)

	return Result.ok(earned)
end

return SellOres
