--!strict
-- Validates a claimed hit on a vein and adds one unit of its ore to the
-- player's bag -- the mining twin of FireRailgun, which this deliberately
-- mirrors for the validation shape, with one real difference: a hit does
-- not pay out credits directly, it fills profile.ores (see Profile.luau's
-- own note on the bag) -- SellOres is the only place ore ever becomes
-- credits, same as Credits.spend is the only place a purchase ever happens.
--
-- The client's own raycast is trusted only as far as "which vein id did you
-- claim to hit": the server never re-simulates the camera geometry, only
-- the LOGICAL constraints (is the mine unlocked, does this vein id resolve
-- to a real ore, is its cooldown clear).
--
-- Unlike an asteroid, a vein is not spawned or despawned -- it is a fixed
-- fixture of the mine, and which ore it holds is DERIVED, not looked up in
-- any per-session state: OreCatalog.oreForVein(terrace, slot) is the same
-- formula Adapters/Roblox/ResearchMineBuilder used to decide what to put
-- there in the first place. A forged vein id that doesn't parse, or parses
-- to a (terrace, slot) with no ore, is refused the same way either kind of
-- mistake would be.

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Server and src/Shared to different service roots with no common
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
	return "../../../Shared/" .. path
end

local OreCatalog = require(fromShared("Domain/Research/OreCatalog"))
local ResearchMine = require(fromShared("Domain/Research/ResearchMine"))
local Vein = require(fromShared("Domain/Research/Vein"))
local Result = require(fromShared("Domain/Support/Result"))
local Snapshot = require("../Snapshot")

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	profileRepository: any, -- Ports.ProfileRepository
	sessionRegistry: any, -- Application.SessionRegistry
	statsPublisher: any, -- Ports.StatsPublisher
	clock: any, -- Ports.Clock (monotonic() is what's used here)
	veinRules: Vein.Rules,
}

export type MineResult = { oreId: string, oreName: string, rarity: string, count: number }

local MineVein = {}
MineVein.__index = MineVein

function MineVein:run(userId: number, veinId: string): Result<MineResult, string>
	local profile = self.profileRepository:load(userId)
	if not ResearchMine.isUnlocked(profile.unlocked) then
		return Result.err("mine de recherche non débloquée")
	end

	local terrace, slot = OreCatalog.parseVeinId(veinId)
	local ore = if terrace and slot then OreCatalog.oreForVein(terrace, slot) else nil
	if not ore then
		return Result.err("filon invalide")
	end

	local now = self.clock:monotonic()
	if
		not Vein.canMine(
			self.sessionRegistry:lastVeinMine(userId, veinId),
			now,
			self.veinRules.cooldown
		)
	then
		return Result.err("filon en recharge")
	end
	self.sessionRegistry:setLastVeinMine(userId, veinId, now)

	local count = (profile.ores[ore.id] or 0) + 1
	profile.ores[ore.id] = count
	self.profileRepository:save(userId, profile)

	self.statsPublisher:publish(userId, Snapshot.ore(ore.id, count))
	-- No notifier call: nothing here is credits, so the "Credits" GainFeed
	-- kind would show the wrong icon for it. The client's own toast (built
	-- from this Result) is feedback enough -- matches every refusal toast
	-- already in this game, just also firing on success.

	return Result.ok({ oreId = ore.id, oreName = ore.name, rarity = ore.rarity, count = count })
end

return MineVein
