--!strict
-- Builds and destroys the asteroid Instances a player's Railgun shoots at.
-- Purely cosmetic: lifetime/expiry is decided authoritatively by
-- RunMiningTick (see Ports.AsteroidField's own header) -- the flight tween
-- here is just what makes an asteroid visually cross the sky over the same
-- span of time the Application layer already tracks.
--
-- Parents every asteroid into workspace.Asteroids.Asteroids_<userId>, a
-- SIBLING of workspace.Stations -- deliberately not nested inside
-- Station_<userId> itself, because BuildController's occupancy sync and
-- HudController's module counter both iterate that folder's direct children
-- expecting only placed modules; mixing asteroid Models in would corrupt
-- both.
--
-- Reuses the already-built StationSceneBuilder for plot geometry
-- (originFor(userId)) instead of tracking plot positions a second time --
-- same "depend on the already-built adapter" pattern CharacterTeleporter
-- already uses for spawnLocationFor.
--
-- Per ARCHITECTURE.md, adapters are not covered by the Lune suite -- this
-- one is hand/live-verified in Studio instead (see CLAUDE.md's Mining
-- feature notes).

local TweenService = game:GetService("TweenService")

-- Tier -> visuals. Roblox datatypes (Color3, Enum.Material) can never live
-- in Domain/Balance (see CLAUDE.md) -- this is where they belong instead,
-- keyed the same as Balance.Mining.Tiers' own ids. "Très reconnaissable"
-- per the user's own ask: each tier is a genuinely different size/finish,
-- not just a recolored sphere.
local VISUALS: { [string]: { size: number, color: Color3, material: Enum.Material, glow: boolean } } =
	{
		Common = {
			size = 4,
			color = Color3.fromRGB(120, 116, 110),
			material = Enum.Material.Rock,
			glow = false,
		},
		Rare = {
			size = 5.5,
			color = Color3.fromRGB(90, 160, 230),
			material = Enum.Material.Slate,
			glow = false,
		},
		Epic = {
			size = 7,
			color = Color3.fromRGB(170, 90, 230),
			material = Enum.Material.Neon,
			glow = true,
		},
		Legendary = {
			size = 9,
			color = Color3.fromRGB(255, 205, 60),
			material = Enum.Material.Neon,
			glow = true,
		},
	}
local DEFAULT_VISUAL = VISUALS.Common

-- The arc asteroids fly across: an altitude band above the deck, offset
-- outward from the plot so the flight reads as "passing by" rather than
-- crossing through the station itself.
local ARC = { minRadius = 90, maxRadius = 140, minHeight = 30, maxHeight = 70 }

local function randomPointOnArc(origin: CFrame): Vector3
	local angle = math.random() * math.pi * 2
	local radius = ARC.minRadius + math.random() * (ARC.maxRadius - ARC.minRadius)
	local height = ARC.minHeight + math.random() * (ARC.maxHeight - ARC.minHeight)
	return origin.Position + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

local AsteroidFieldRenderer = {}
AsteroidFieldRenderer.__index = AsteroidFieldRenderer

export type Config = {
	sceneBuilder: any, -- Adapters.Roblox.StationSceneBuilder (for originFor)
	asteroidsParent: Instance, -- workspace.Asteroids
	lifetime: number, -- seconds -- how long the flight tween takes
}

function AsteroidFieldRenderer.new(config: Config)
	return setmetatable({
		_config = config,
		_folders = {} :: { [number]: Folder }, -- userId -> Asteroids_<userId>
		_models = {} :: { [number]: { [string]: Model } }, -- userId -> asteroidId -> Model
	}, AsteroidFieldRenderer)
end

function AsteroidFieldRenderer:_folderFor(userId: number): Folder
	local existing = self._folders[userId]
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = `Asteroids_{userId}`
	folder.Parent = self._config.asteroidsParent
	self._folders[userId] = folder
	self._models[userId] = {}
	return folder
end

function AsteroidFieldRenderer:spawn(userId: number, asteroidId: string, tier: string)
	local origin = self._config.sceneBuilder:originFor(userId)
	if not origin then
		return -- no claimed plot to spawn near -- nothing sensible to do
	end

	local visual = VISUALS[tier] or DEFAULT_VISUAL
	local folder = self:_folderFor(userId)

	local model = Instance.new("Model")
	model.Name = `{tier}_{asteroidId}`
	model:SetAttribute("AsteroidId", asteroidId)
	model:SetAttribute("Tier", tier)

	local rock = Instance.new("Part")
	rock.Name = "Rock"
	rock.Shape = Enum.PartType.Ball
	rock.Size = Vector3.new(visual.size, visual.size, visual.size)
	rock.Color = visual.color
	rock.Material = visual.material
	rock.Anchored = true
	rock.CanCollide = false
	rock.CanTouch = false
	rock.CanQuery = true -- must stay raycast-hittable: this is the fire target
	rock.CastShadow = false
	local from = randomPointOnArc(origin)
	rock.CFrame = CFrame.new(from)
	rock.Parent = model

	if visual.glow then
		local light = Instance.new("PointLight")
		light.Color = visual.color
		light.Range = 16
		light.Brightness = 2
		light.Parent = rock
	end

	model.PrimaryPart = rock
	model.Parent = folder
	self._models[userId][asteroidId] = model

	local to = randomPointOnArc(origin)
	local tween = TweenService:Create(
		rock,
		TweenInfo.new(self._config.lifetime, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.new(to) }
	)
	tween:Play()
end

function AsteroidFieldRenderer:despawn(userId: number, asteroidId: string)
	local models = self._models[userId]
	local model = models and models[asteroidId]
	if model then
		model:Destroy()
		models[asteroidId] = nil
	end
end

return AsteroidFieldRenderer
