--!strict
-- Business failures go through Result.ok/Result.err; error() stays reserved
-- for contract violations (programming bugs), per DEVELOPMENT.md.

export type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

local Result = {}

function Result.ok<T>(value: T): Result<T, any>
	return { ok = true, value = value }
end

function Result.err<E>(err: E): Result<any, E>
	return { ok = false, error = err }
end

function Result.isOk<T, E>(result: Result<T, E>): boolean
	return result.ok
end

-- Unwraps a success value, or raises a contract violation if called on an
-- error -- only use where the caller has already checked `.ok`.
function Result.unwrap<T, E>(result: Result<T, E>): T
	if not result.ok then
		error(`Result.unwrap called on an error: {tostring(result.error)}`, 2)
	end
	return result.value
end

return Result
