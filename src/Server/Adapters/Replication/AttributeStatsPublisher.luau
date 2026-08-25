--!strict
-- Implements the StatsPublisher port via Instance:SetAttribute on the
-- Player -- the engine replicates attributes automatically, so there is
-- nothing else this adapter needs to do. Setting one attribute never
-- touches another, so a snapshot with only some fields is exactly what's
-- meant to happen (see Application/Snapshot.luau's header). If the player
-- has already left, publishing silently does nothing: nobody is left to
-- see it.

local Players = game:GetService("Players")

local AttributeStatsPublisher = {}
AttributeStatsPublisher.__index = AttributeStatsPublisher

function AttributeStatsPublisher.new()
	return setmetatable({}, AttributeStatsPublisher)
end

function AttributeStatsPublisher:publish(userId: number, snapshot: { [string]: any })
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return
	end
	for key, value in snapshot do
		player:SetAttribute(key, value)
	end
end

return AttributeStatsPublisher
