--!strict
-- Implements the MovementActuator port: writes a commanded WalkSpeed onto
-- the player's Humanoid.
--
-- It REMEMBERS the last speed commanded for each user and re-applies it
-- every time that player's character is rebuilt. WalkSpeed lives on the
-- Humanoid, and the Humanoid is destroyed on every death AND on every
-- return to the lobby -- which this game does constantly (see
-- ReturnToLobby / EmbarkStation). Without the memory below, a tester's
-- speed would silently revert on their first trip through the lobby, which
-- is exactly the moment they wanted it.
--
-- The memory is per-session and lives here rather than in SessionRegistry
-- on purpose: no use case reads it back, and re-applying a commanded value
-- after the hardware it was written to got replaced is actuator mechanics,
-- not a game rule.

local Players = game:GetService("Players")

local HumanoidMovementActuator = {}
HumanoidMovementActuator.__index = HumanoidMovementActuator

function HumanoidMovementActuator.new()
	local self = setmetatable({ _speeds = {} :: { [number]: number } }, HumanoidMovementActuator)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			-- Spawned rather than awaited inline: WaitForChild here would
			-- block the CharacterAdded handler itself. The speed is read
			-- AFTER the wait, so a reset issued meanwhile still wins.
			task.spawn(function()
				local humanoid = character:WaitForChild("Humanoid", 5)
				local speed = self._speeds[player.UserId]
				if humanoid and speed then
					(humanoid :: Humanoid).WalkSpeed = speed
				end
			end)
		end)
	end

	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)

	return self
end

function HumanoidMovementActuator:setWalkSpeed(userId: number, speed: number)
	self._speeds[userId] = speed

	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return -- gone; the memory above is dropped by release()
	end
	local character = player.Character
	if not character then
		return -- not spawned yet; CharacterAdded above will apply it
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

function HumanoidMovementActuator:release(userId: number)
	self._speeds[userId] = nil
end

return HumanoidMovementActuator
