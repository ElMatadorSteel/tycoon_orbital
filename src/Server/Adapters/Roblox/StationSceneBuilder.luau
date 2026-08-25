--!strict
-- Builds and tears down the 3D scene: plot structures and the module
-- models placed on them. Ported near-verbatim from the legacy PlotService
-- (buildDeck/buildRim/buildKeel/buildWings/:Claim/:Release) and
-- StationService (buildModel), merged into one adapter because placing a
-- module inherently needs the origin of an already-claimed plot -- keeping
-- them apart would just mean threading that origin back and forth.
--
-- This adapter owns state a Domain/Application object deliberately does
-- not (see Domain/Station/Placement.luau's ModulePlacement, which has no
-- Model field on purpose): which slot each user owns, and which Instance
-- backs each placed module, so removeModule() knows what to destroy.
-- Per ARCHITECTURE.md, adapters are not covered by the Lune suite -- this
-- one was instead hand-verified against the real ModuleModels templates
-- via execute_luau before being written here (see the Stage 5 notes in
-- CLAUDE.md).

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

local Grid = require(fromShared("Domain/Grid/Grid"))
local Layout = require(fromShared("Domain/Plots/Layout"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local Placement = require(fromShared("Domain/Station/Placement"))

type Slot = Layout.Slot
type ModulePlacement = Placement.ModulePlacement

local PALETTE = {
	Hull = Color3.fromRGB(182, 190, 205),
	HullShade = Color3.fromRGB(140, 149, 170),
	Seam = Color3.fromRGB(44, 48, 68),
	Frame = Color3.fromRGB(74, 80, 104),
	Trim = Color3.fromRGB(72, 214, 255),
	Solar = Color3.fromRGB(30, 48, 104),
	Thruster = Color3.fromRGB(255, 146, 66),
	Grid = Color3.fromRGB(58, 64, 88),
	Radiator = Color3.fromRGB(228, 232, 240),
	Beacon = Color3.fromRGB(255, 90, 90),
}

local PANEL_CELLS = 5 -- one hull panel covers 5 cells
local GRID_LINE_WIDTH = 0.16
local RIM_HEIGHT = 3

local function part(parent: Instance, name: string, props: { [string]: any }): BasePart
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Anchored = true
	instance.CanCollide = false
	instance.CastShadow = false
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

----------------------------------------------------------------------
-- The deck

local function buildDeck(model: Model, origin: CFrame, span: number, gridRules: Grid.Rules)
	local deck = part(model, "Deck", {
		Size = Vector3.new(span, 1, span),
		CFrame = origin * CFrame.new(0, -0.9, 0),
		Color = PALETTE.Seam,
		Material = Enum.Material.Metal,
		CanCollide = true,
	})
	model.PrimaryPart = deck

	local panelSize = PANEL_CELLS * gridRules.cellSize
	local count = math.floor(span / panelSize)
	local start = -(count - 1) / 2

	for ix = 0, count - 1 do
		for iz = 0, count - 1 do
			local shaded = (ix + iz) % 2 == 0
			part(model, "Panel", {
				Size = Vector3.new(panelSize - 1.4, 0.4, panelSize - 1.4),
				CFrame = origin
					* CFrame.new((start + ix) * panelSize, -0.2, (start + iz) * panelSize),
				Color = if shaded then PALETTE.Hull else PALETTE.HullShade,
				Material = Enum.Material.Metal,
				CanCollide = true,
			})
		end
	end

	local cells = gridRules.radius * 2 + 1
	for index = 0, cells do
		local offset = -span / 2 + index * gridRules.cellSize
		part(model, "GridX", {
			Size = Vector3.new(span, 0.06, GRID_LINE_WIDTH),
			CFrame = origin * CFrame.new(0, -0.01, offset),
			Color = PALETTE.Grid,
			Material = Enum.Material.SmoothPlastic,
			CanQuery = false,
		})
		part(model, "GridZ", {
			Size = Vector3.new(GRID_LINE_WIDTH, 0.06, span),
			CFrame = origin * CFrame.new(offset, -0.01, 0),
			Color = PALETTE.Grid,
			Material = Enum.Material.SmoothPlastic,
			CanQuery = false,
		})
	end
end

----------------------------------------------------------------------
-- Rim and frame

local function buildRim(model: Model, origin: CFrame, span: number)
	local half = span / 2

	for _, axis in { true, false } do
		for _, sign in { -1, 1 } do
			local offset = if axis
				then Vector3.new(0, RIM_HEIGHT / 2, sign * half)
				else Vector3.new(sign * half, RIM_HEIGHT / 2, 0)

			part(model, "Rim", {
				Size = if axis
					then Vector3.new(span + 3, RIM_HEIGHT, 1.6)
					else Vector3.new(1.6, RIM_HEIGHT, span + 3),
				CFrame = origin * CFrame.new(offset),
				Color = PALETTE.Frame,
				Material = Enum.Material.Metal,
				CanCollide = true,
			})
			part(model, "RimLight", {
				Size = if axis
					then Vector3.new(span + 3.4, 0.4, 0.5)
					else Vector3.new(0.5, 0.4, span + 3.4),
				CFrame = origin * CFrame.new(offset + Vector3.new(0, RIM_HEIGHT / 2, 0)),
				Color = PALETTE.Trim,
				Material = Enum.Material.Neon,
			})
		end
	end

	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			local corner = Vector3.new(dx * half, 0, dz * half)
			part(model, "CornerNode", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(11, 7, 7),
				CFrame = origin
					* CFrame.new(corner + Vector3.new(0, 4.5, 0))
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = PALETTE.Hull,
				Material = Enum.Material.Metal,
				CanCollide = true,
			})
			part(model, "CornerLight", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1.2, 7.4, 7.4),
				CFrame = origin
					* CFrame.new(corner + Vector3.new(0, 10.4, 0))
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = PALETTE.Trim,
				Material = Enum.Material.Neon,
			})
		end
	end
end

local function buildKeel(model: Model, origin: CFrame, span: number)
	local half = span / 2

	part(model, "Keel", {
		Size = Vector3.new(span * 0.5, 6, span * 0.5),
		CFrame = origin * CFrame.new(0, -4.4, 0),
		Color = PALETTE.Frame,
		Material = Enum.Material.Metal,
	})

	for _, dx in { -1, 1 } do
		for _, dz in { -1, 1 } do
			part(model, "Strut", {
				Size = Vector3.new(3, 3, span * 0.86),
				CFrame = origin
					* CFrame.new(dx * half * 0.42, -3.2, dz * half * 0.42)
					* CFrame.Angles(0, math.rad(dx * dz * 45), 0),
				Color = PALETTE.Frame,
				Material = Enum.Material.Metal,
			})

			local nozzle = Vector3.new(dx * half * 0.55, -8, dz * half * 0.55)
			part(model, "Thruster", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(7, 8, 8),
				CFrame = origin * CFrame.new(nozzle) * CFrame.Angles(0, 0, math.rad(90)),
				Color = PALETTE.Frame,
				Material = Enum.Material.Metal,
			})
			part(model, "ThrusterGlow", {
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(1, 7, 7),
				CFrame = origin
					* CFrame.new(nozzle - Vector3.new(0, 3.6, 0))
					* CFrame.Angles(0, 0, math.rad(90)),
				Color = PALETTE.Thruster,
				Material = Enum.Material.Neon,
			})
		end
	end
end

----------------------------------------------------------------------
-- Appendages

local function buildWings(model: Model, origin: CFrame, span: number)
	local half = span / 2

	for _, sign in { -1, 1 } do
		part(model, "WingArm", {
			Size = Vector3.new(64, 2.2, 3.4),
			CFrame = origin * CFrame.new(sign * (half + 32), 1.5, 0),
			Color = PALETTE.Frame,
			Material = Enum.Material.Metal,
		})

		for index = 0, 3 do
			part(model, "SolarWing", {
				Size = Vector3.new(13, 0.5, 30),
				CFrame = origin
					* CFrame.new(sign * (half + 10 + index * 15), 2.6, 0)
					* CFrame.Angles(math.rad(18), 0, 0),
				Color = PALETTE.Solar,
				Material = Enum.Material.Glass,
				Reflectance = 0.25,
			})
		end

		for index = 0, 2 do
			part(model, "RadiatorFin", {
				Size = Vector3.new(34, 0.4, 11),
				CFrame = origin
					* CFrame.new(0, -6 - index * 3.4, sign * (half + 12 + index * 9))
					* CFrame.Angles(math.rad(sign * 12), 0, 0),
				Color = PALETTE.Radiator,
				Material = Enum.Material.SmoothPlastic,
			})
		end
	end

	part(model, "Mast", {
		Size = Vector3.new(1.2, 26, 1.2),
		CFrame = origin * CFrame.new(half - 10, 13, -half + 10),
		Color = PALETTE.Hull,
		Material = Enum.Material.Metal,
	})
	local beacon = part(model, "Beacon", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(2.4, 2.4, 2.4),
		CFrame = origin * CFrame.new(half - 10, 26.5, -half + 10),
		Color = PALETTE.Beacon,
		Material = Enum.Material.Neon,
	})

	local light = Instance.new("PointLight")
	light.Range = 26
	light.Brightness = 2
	light.Color = PALETTE.Beacon
	light.Parent = beacon
end

local function buildStructure(index: number, origin: CFrame, gridRules: Grid.Rules): Model
	local span = (gridRules.radius * 2 + 1) * gridRules.cellSize

	local model = Instance.new("Model")
	model.Name = `Plot_{index}`

	buildDeck(model, origin, span, gridRules)
	buildRim(model, origin, span)
	buildKeel(model, origin, span)
	buildWings(model, origin, span)

	-- StreamingEnabled is on: without this the platform unloads as the
	-- camera moves away, and modules would appear to float in the void.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	return model
end

----------------------------------------------------------------------
-- Module models
--
-- CONTRACT (unchanged from the legacy StationService): built at rotation
-- 0, centred on the origin, base at y = 0, WorldPivot at the origin, and NO
-- PrimaryPart. A PrimaryPart sitting on the base plate would sink the
-- module into the hull by half its thickness, because PivotTo() uses a
-- PrimaryPart's CFrame and ignores WorldPivot when one is set -- stripped
-- on clone as a safety net, since Studio sometimes assigns one on its own.

local function templateFor(id: string): Model?
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ModuleModels")
	if not folder then
		return nil
	end
	local template = folder:FindFirstChild(id)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

local function buildModuleModel(
	definition: ModuleCatalog.ModuleDef,
	x: number,
	y: number,
	rotation: number,
	origin: CFrame,
	gridRules: Grid.Rules
): Model
	local width, height = ModuleCatalog.sizeOf(definition, rotation)
	local offset = Grid.offset(x, y, width, height, gridRules)

	-- rotation counts quarter-turns clockwise, as seen from the top-down
	-- build camera -- the negative sign is what gives it that direction
	-- (see StationService history / CLAUDE.md).
	local pivot = origin
		* CFrame.new(offset.x, offset.y, offset.z)
		* CFrame.Angles(0, -math.rad(90) * rotation, 0)

	local template = templateFor(definition.id)
	if template then
		local model = template:Clone()
		model.Name = `{definition.id}_{x}_{y}`
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = true
			end
		end
		model.PrimaryPart = nil
		model:PivotTo(pivot)
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		return model
	end

	-- No template yet: fall back to a flat coloured box sized from the
	-- catalogue, so a new module can be played with immediately.
	local model = Instance.new("Model")
	model.Name = `{definition.id}_{x}_{y}`

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(
		width * gridRules.cellSize - 0.5,
		definition.height,
		height * gridRules.cellSize - 0.5
	)
	body.Color = Color3.fromRGB(190, 190, 190)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = true
	body.TopSurface = Enum.SurfaceType.Smooth
	body.BottomSurface = Enum.SurfaceType.Smooth
	body.CFrame = pivot * CFrame.new(0, definition.height / 2, 0)
	body.Parent = model

	model.PrimaryPart = body
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return model
end

----------------------------------------------------------------------

local StationSceneBuilder = {}
StationSceneBuilder.__index = StationSceneBuilder

export type Config = {
	gridRules: Grid.Rules,
	layoutRules: Layout.Rules,
	plotsParent: Instance, -- workspace.Plots
	stationsParent: Instance, -- workspace.Stations
}

function StationSceneBuilder.new(config: Config)
	return setmetatable({
		_config = config,
		_slots = Layout.slots(config.layoutRules),
		_owner = {} :: { [number]: number }, -- slotIndex -> userId
		_origin = {} :: { [number]: CFrame }, -- userId -> plot origin
		_structure = {} :: { [number]: Model }, -- userId -> plot structure
		_folder = {} :: { [number]: Folder }, -- userId -> module container
		_spawn = {} :: { [number]: SpawnLocation }, -- userId -> station spawn point
		_models = {} :: { [number]: { [string]: Model } }, -- userId -> gridKey -> module Model
	}, StationSceneBuilder)
end

-- Builds the structure only when claimed: an unclaimed slot stays
-- invisible, five empty slabs lined up would just read as forgotten
-- geometry.
function StationSceneBuilder:claimPlot(userId: number): boolean
	if self._origin[userId] then
		return true -- already claimed this session
	end

	for _, slot in self._slots do
		if not self._owner[slot.index] then
			self._owner[slot.index] = userId

			local origin = CFrame.new(slot.x, slot.y, slot.z)
			local structure = buildStructure(slot.index, origin, self._config.gridRules)
			structure.Parent = self._config.plotsParent

			local folder = Instance.new("Folder")
			folder.Name = `Station_{userId}`
			-- The client's BuildController has no other way to learn its own
			-- plot's origin (mouse-ray -> grid-cell math, the ghost preview's
			-- pivot): CFrame is an attribute-compatible type, so this is
			-- simpler and less fragile than making the client re-derive it
			-- from the StationSpawn's offset.
			folder:SetAttribute("Origin", origin)
			folder.Parent = self._config.stationsParent

			-- Set back from the core, on the deck -- ported from
			-- StationService:EnsureStation's spawnPart placement.
			local spawnPart = Instance.new("SpawnLocation")
			spawnPart.Name = "StationSpawn"
			spawnPart.Size = Vector3.new(10, 1, 10)
			spawnPart.CFrame = origin * CFrame.new(0, 1, 22)
			spawnPart.Anchored = true
			spawnPart.Enabled = false
			spawnPart.Neutral = true
			spawnPart.Transparency = 1
			spawnPart.CanCollide = false
			spawnPart.Parent = folder

			self._origin[userId] = origin
			self._structure[userId] = structure
			self._folder[userId] = folder
			self._spawn[userId] = spawnPart
			self._models[userId] = {}

			-- The starting core -- ported from the legacy
			-- StationService:EnsureStation, which placed it as part of the
			-- same "ensure this player has a station" step, not through the
			-- ordinary PlaceModule use case (it's free and unique, and
			-- Placement.initial() already accounts for it in the station's
			-- DATA at (-1, -1) -- this is what gives it the matching
			-- Instance, which nothing else ever did).
			local coreDefinition = ModuleCatalog.get("Core")
			if coreDefinition then
				local coreModel =
					buildModuleModel(coreDefinition, -1, -1, 0, origin, self._config.gridRules)
				coreModel:SetAttribute("ModuleId", "Core")
				coreModel:SetAttribute("Level", 1)
				coreModel:SetAttribute("X", -1)
				coreModel:SetAttribute("Y", -1)
				coreModel:SetAttribute("Rotation", 0)
				coreModel.Parent = folder
				self._models[userId][Grid.key(-1, -1)] = coreModel
			end

			return true
		end
	end

	return false -- every plot is occupied
end

function StationSceneBuilder:originFor(userId: number): CFrame?
	return self._origin[userId]
end

-- The station's spawn point -- what Ports.Teleporter's real adapter needs
-- to set player.RespawnLocation and move the character there.
function StationSceneBuilder:spawnLocationFor(userId: number): SpawnLocation?
	return self._spawn[userId]
end

function StationSceneBuilder:releasePlot(userId: number)
	for index, owner in self._owner do
		if owner == userId then
			self._owner[index] = nil
		end
	end
	if self._structure[userId] then
		self._structure[userId]:Destroy()
		self._structure[userId] = nil
	end
	if self._folder[userId] then
		self._folder[userId]:Destroy()
		self._folder[userId] = nil
	end
	self._origin[userId] = nil
	self._spawn[userId] = nil
	self._models[userId] = nil
end

function StationSceneBuilder:placeModule(
	userId: number,
	placement: ModulePlacement,
	definition: ModuleCatalog.ModuleDef
)
	local origin = self._origin[userId]
	local folder = self._folder[userId]
	if not origin or not folder then
		return -- no claimed plot to build onto -- nothing sensible to do
	end

	local model = buildModuleModel(
		definition,
		placement.x,
		placement.y,
		placement.rotation,
		origin,
		self._config.gridRules
	)
	model:SetAttribute("ModuleId", definition.id)
	model:SetAttribute("Level", placement.level)
	-- X/Y/Rotation ride along too, not just for label purposes: the client's
	-- BuildController has no other way to reconstruct occupancy for its
	-- (advisory-only, server-revalidated) ghost preview, now that a
	-- station's contents replicate as ordinary Instances instead of a
	-- StationChanged payload -- see CLAUDE.md's Stage 4 reframe.
	model:SetAttribute("X", placement.x)
	model:SetAttribute("Y", placement.y)
	model:SetAttribute("Rotation", placement.rotation)
	model.Parent = folder

	self._models[userId][Grid.key(placement.x, placement.y)] = model
end

function StationSceneBuilder:removeModule(userId: number, x: number, y: number)
	local models = self._models[userId]
	if not models then
		return
	end
	local key = Grid.key(x, y)
	local model = models[key]
	if model then
		model:Destroy()
		models[key] = nil
	end
end

function StationSceneBuilder:setModuleLevel(userId: number, x: number, y: number, level: number)
	local models = self._models[userId]
	local model = models and models[Grid.key(x, y)]
	if model then
		model:SetAttribute("Level", level)
	end
end

return StationSceneBuilder
