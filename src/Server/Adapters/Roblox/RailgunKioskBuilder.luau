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

local PAD_COLOR = Color3.fromRGB(72, 214, 255)
local DISPENSER_COLOR = Color3.fromRGB(46, 52, 98)
local PROP_COLOR = Color3.fromRGB(255, 205, 60)

local function part(parent: Instance, name: string, props: { [string]: any }): BasePart
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Anchored = true
	instance.CastShadow = false
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

-- A small procedural prop, purely cosmetic -- what makes the dispenser
-- recognisable at a glance, not the actual Tool a player receives.
local function buildDisplayProp(parent: Instance, cframe: CFrame)
	part(parent, "RailgunProp", {
		Size = Vector3.new(1, 1, 6),
		CFrame = cframe * CFrame.new(0, 3, 0),
		Color = PROP_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
end

-- The Tool a player actually receives: one Part named "Handle" (Roblox's own
-- convention for what gets welded into a character's hand on equip).
-- Deliberately no embedded LocalScript -- MiningController (Client) owns all
-- behaviour, matching this codebase's rule that logic lives in Controllers,
-- never in ad-hoc per-instance scripts.
local function buildToolTemplate(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Railgun"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 4)
	handle.Color = PROP_COLOR
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
	lobby: Instance, -- workspace.Scenery.Lobby
	lobbySpawn: BasePart, -- offset anchor -- see Bootstrap's LobbySpawn resolution
	profileRepository: any, -- Ports.ProfileRepository
}

function RailgunKioskBuilder.new(config: Config)
	return setmetatable(
		{ _config = config, _toolTemplate = buildToolTemplate() },
		RailgunKioskBuilder
	)
end

function RailgunKioskBuilder:build()
	local config = self._config
	local base = config.lobbySpawn.CFrame

	----------------------------------------------------------------------
	-- The pad: press E to buy. The purchase itself is entirely client-
	-- initiated (Net.PurchaseRailgun) -- see MiningController -- so no
	-- server-side Triggered binding lives here, unlike LaunchPad.
	local pad = part(config.lobby, "RailgunPad", {
		Size = Vector3.new(8, 1, 8),
		CFrame = base * CFrame.new(-24, 0, -6),
		Color = PAD_COLOR,
		Material = Enum.Material.Neon,
		CanCollide = true,
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Acheter"
	prompt.ObjectText = "Railgun"
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 10
	prompt.Parent = pad

	----------------------------------------------------------------------
	-- The dispenser: walk through it to receive the Tool, once owned.
	local dispenser = part(config.lobby, "RailgunDispenser", {
		Size = Vector3.new(6, 8, 2),
		CFrame = base * CFrame.new(-24, 4, -14),
		Color = DISPENSER_COLOR,
		Material = Enum.Material.Metal,
		CanCollide = false, -- a gate to walk THROUGH, not a wall
		CanTouch = true,
	})
	buildDisplayProp(dispenser, base * CFrame.new(-24, 0, -14))

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
			return -- idempotent: standing in the gate doesn't spam clones
		end

		local clone = self._toolTemplate:Clone()
		clone.Parent = player.Backpack
	end)
end

return RailgunKioskBuilder
