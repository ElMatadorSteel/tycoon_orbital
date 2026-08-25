--!strict
-- Credit balance rules. Ported from the legacy EconomyService:Add/:TrySpend
-- decision logic -- deliberately without the remote-firing/gain-batching
-- side effects, which are a replication concern, not a rule.

local Result = require("../Support/Result")
type Result<T, E> = Result.Result<T, E>

local Credits = {}

function Credits.canSpend(balance: number, amount: number): boolean
	return balance >= amount
end

-- Returns the new balance, or an error result leaving the balance
-- conceptually untouched (the caller never applies it) if funds are short.
function Credits.spend(balance: number, amount: number): Result<number, string>
	if not Credits.canSpend(balance, amount) then
		return Result.err("insufficient credits")
	end
	return Result.ok(balance - amount)
end

-- Floored at 0, same as the legacy rule -- a balance never goes negative.
function Credits.add(balance: number, amount: number): number
	return math.max(0, balance + amount)
end

return Credits
