--!strict
-- Development-only: toggles a per-session (never persisted -- see
-- SessionRegistry's own header on why volatile state never reaches the
-- profile) flag that RunProductionTick tops credits back up against every
-- tick, so nothing a tester does can ever run the balance dry while it's on.
-- Never wired outside development mode -- see Composition/Container.luau's
-- `development` flag.

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

local Result = require(fromShared("Domain/Support/Result"))

type Result<T, E> = Result.Result<T, E>

export type Dependencies = {
	sessionRegistry: any, -- Application.SessionRegistry
}

local DevSetUnlimitedMoney = {}
DevSetUnlimitedMoney.__index = DevSetUnlimitedMoney

function DevSetUnlimitedMoney:run(userId: number, enabled: boolean): Result<boolean, string>
	self.sessionRegistry:setUnlimitedMoney(userId, enabled)
	return Result.ok(enabled)
end

return DevSetUnlimitedMoney
