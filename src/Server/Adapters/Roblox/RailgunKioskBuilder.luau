--!strict
-- Builds the Railgun purchase pad and dispenser into the Lobby scenery,
-- procedurally -- no manual Studio authoring required, same reasoning as
-- StationSceneBuilder building plot geometry itself rather than requiring
-- hand-placed models. Two separate parts, matching the classic tycoon flow
-- the user asked for: a floor PAD you pay at (a ProximityPrompt; the
-- purchase itself goes through Net.PurchaseRailgun, invoked by the CLIENT
-- off this prompt -- see MiningController, not this file), and a
-- DISPENSER you walk through to receive the Tool into your Backpack once
-- you own it.
--
-- The Touched-based give-tool check is the one place this adapter reaches
-- past pure scene-building into reading profile state (`unlocked.Railgun`)
-- -- justified because "should this player receive the tool" is a real
-- authorization check, not incidental. The purchase itself (spend credits,
-- set the flag) stays entirely in PurchaseRailgun; this file only ever
-- reads the flag, never writes it.
--
-- Per ARCHITECTURE.md, adapters are not covered by the Lune suite -- this
-- one is hand/live-verified in Studio instead (see CLAUDE.md's Mining
-- feature notes).

local Players = game:GetService("Players")

-- The Tool a player actually receives. An authored model when one lives at
-- ReplicatedStorage.RailgunModel.Railgun (place-file only, same caveat as
-- the drill and pickaxe templates). The procedural fallback below keeps the
-- feature working even if the model is missing.
-- Deliberately no embedded scripts -- MiningController (Client) owns all
-- behaviour, matching this codebase's rule that logic lives in Controllers,
-- never in ad-hoc per-instance scripts.
local function buildToolTemplate(): Tool
	if game then
		local folder = (game :: any):GetService("ReplicatedStorage"):FindFirstChild("RailgunModel")
		local template = folder and folder:FindFirstChild("Railgun")
		if template and template:IsA("Tool") and template:FindFirstChild("Handle") then
			local clone = template:Clone()
			clone.CanBeDropped = false
			return clone
		end
	end

	-- Procedural fallback
	local tool = Instance.new("Tool")
	tool.Name = "Railgun"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 4)
	handle.Color = Color3.fromRGB(255, 205, 60)
	handle.Material = Enum.Material.Neon
	handle.CanCollide = false
	handle.Parent = tool

	return tool
end

local function hasRailgunTool(player: Player): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and backpack:FindFirstChild("Railgun") then
		return true
	end
	local character = player.Character
	return character ~= nil and character:FindFirstChild("Railgun") ~= nil
end

local RailgunKioskBuilder = {}
RailgunKioskBuilder.__index = RailgunKioskBuilder

export type Config = {
	profileRepository: any, -- Ports.ProfileRepository
}

function RailgunKioskBuilder.new(config: Config)
	return setmetatable(
		{ _config = config, _toolTemplate = buildToolTemplate() },
		RailgunKioskBuilder
	)
end

-- Wires a dispenser Part's Touched event so players who own the railgun
-- receive the tool when they walk through it. Called by StationSceneBuilder
-- after building a player's research mine zone (the dispenser geometry now
-- lives in ResearchMineBuilder, on the house plateau).
function RailgunKioskBuilder:wireDispenser(dispenser: BasePart)
	local config = self._config
	dispenser.Touched:Connect(function(hit: BasePart)
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		local profile = config.profileRepository:load(player.UserId)
		if not profile.unlocked.Railgun then
			return
		end
		if hasRailgunTool(player) then
			return
		end

		local clone = self._toolTemplate:Clone()
		clone.Parent = player.Backpack
	end)
end

-- Give the tool to a player who already owns it (e.g. on join / respawn).
-- Idempotent: does nothing when the player already holds one.
function RailgunKioskBuilder:grantTool(player: Player)
	if hasRailgunTool(player) then
		return
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end
	local clone = self._toolTemplate:Clone()
	clone.Parent = backpack
end

return RailgunKioskBuilder
