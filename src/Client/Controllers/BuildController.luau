--!strict
-- Build mode: menu, grid-snapped ghost preview, placement/demolition/
-- upgrade, and the build camera.
--
-- Two structural points:
--
--   * LOCATION. The server says where the player is ("Lobby" or "Station").
--     In the lobby they have no station: every tool is put away and the
--     keys go dead.
--   * CAMERA. Building on a grid with the character camera is unplayable.
--     Picking up a tool switches to a top-down view centered on the
--     station, showing the whole buildable area.
--
-- The client re-runs the same checks the server does, but only to color the
-- preview. The server stays sole judge: we send it intent and display its
-- response as-is.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Client and src/Shared to different service roots with no common
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
	return "../../Shared/" .. path
end

local Balance = require(fromShared("Balance"))
local Grid = require(fromShared("Domain/Grid/Grid"))
local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local ModuleGeometry = require(fromShared("ModuleGeometry"))
local Net = require(fromShared("Net"))
local State = require("../State")

local BuildPanel = require("../UI/BuildPanel")
local Theme = require("../UI/Theme")

local COLORS = Theme.Colors

local GRID_RULES: Grid.Rules = { cellSize = Balance.Grid.CellSize, radius = Balance.Grid.Radius }
local MAX_LEVEL = Balance.Upgrade.MaxLevel

-- Roblox recreates the camera on respawn: re-read it on every access
-- instead of keeping a reference that would go stale.
local function getCamera(): Camera
	return workspace.CurrentCamera
end

-- Build-site view: high enough to cover the whole grid at once.
local VIEW = {
	Pitch = math.rad(58),
	ZoomDefault = 210,
	ZoomMin = 90,
	-- Deliberately low ceiling. StreamingEnabled is on: past this, the
	-- platform starts unloading under the camera. 250 already shows the
	-- whole grid (200 studs) with margin.
	ZoomMax = 250,
	ZoomStep = 18,
	YawStep = math.rad(15),
	-- Mouse-edge panning: how close to the viewport's border (in pixels)
	-- starts sliding the view, and how fast it slides once it does.
	PanEdgeMargin = 48,
	PanSpeed = 70,
}

type Entry = { id: string, x: number, y: number, rotation: number, level: number }

local BuildController = {}

BuildController._location = "Lobby"
BuildController._selected = nil :: string?
BuildController._rotation = 0
BuildController._demolishing = false
BuildController._upgrading = false
BuildController._modifying = false
BuildController._movingFrom = nil :: { x: number, y: number }?
BuildController._movingLevel = nil :: number?
BuildController._origin = nil :: CFrame?
BuildController._occupancy = {} :: { [string]: Entry }
BuildController._credits = 0
BuildController._anchor = nil :: { x: number, y: number }?
BuildController._hovered = nil :: Entry?
BuildController._buildView = false
BuildController._zoom = VIEW.ZoomDefault
BuildController._yaw = 0
BuildController._panTarget = nil :: Vector3?
BuildController._folder = nil :: Folder?

----------------------------------------------------------------------
-- Station folder / occupancy, rebuilt from the real Instances -- a placed
-- module's data replicates for free as an ordinary Roblox Instance (see
-- CLAUDE.md's Stage 4 reframe), so there is no snapshot payload to mirror
-- here, just the folder's current children.

local function myFolder(): Folder?
	local stations = workspace:FindFirstChild("Stations")
	if not stations then
		return nil
	end
	local folder = stations:FindFirstChild(`Station_{Players.LocalPlayer.UserId}`)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

function BuildController:_syncOccupancy()
	table.clear(self._occupancy)
	local folder = self._folder
	if not folder then
		return
	end

	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local id = model:GetAttribute("ModuleId")
		local x = model:GetAttribute("X")
		local y = model:GetAttribute("Y")
		local rotation = model:GetAttribute("Rotation")
		local level = model:GetAttribute("Level")
		if
			typeof(id) ~= "string"
			or typeof(x) ~= "number"
			or typeof(y) ~= "number"
			or typeof(rotation) ~= "number"
			or typeof(level) ~= "number"
		then
			continue
		end

		local definition = ModuleCatalog.get(id)
		if not definition then
			continue
		end

		local entry: Entry = { id = id, x = x, y = y, rotation = rotation, level = level }
		local width, depth = ModuleCatalog.sizeOf(definition, rotation)
		for _, cell in Grid.cells(x, y, width, depth) do
			self._occupancy[Grid.key(cell.x, cell.y)] = entry
		end
	end
end

function BuildController:_bindStation()
	local folder = myFolder()
	self._folder = folder
	if not folder then
		self._origin = nil
		table.clear(self._occupancy)
		return
	end

	local origin = folder:GetAttribute("Origin")
	self._origin = if typeof(origin) == "CFrame" then origin else nil
	self:_syncOccupancy()

	folder.ChildAdded:Connect(function()
		self:_syncOccupancy()
	end)
	folder.ChildRemoved:Connect(function()
		self:_syncOccupancy()
	end)
end

----------------------------------------------------------------------
-- Current location

function BuildController:_setLocation(location: string)
	self._location = location
	local onStation = location == "Station"

	if onStation and not self._folder then
		self:_bindStation()
	end

	if not onStation then
		self._selected = nil
		self._demolishing = false
		self._upgrading = false
		self._modifying = false
		self._movingFrom = nil
		self:_destroyGhost()
		self:_destroyHighlight()
		self._panel:SetSelected(nil)
		self._panel:SetDemolishing(false)
		self._panel:SetUpgrading(false)
		self._panel:SetModifying(false)
		self._panTarget = nil
	end

	self._panel:SetAvailable(onStation)
	self:_refreshView()
end

----------------------------------------------------------------------
-- Build camera

-- Deliberately NOT tied to the character: build/modify/upgrade/demolish are
-- all easier with a view that stays put while walking, and steers only
-- through the mouse instead (see the edge-pan below). Starts centred on the
-- station and is nil'd out on leaving it (_setLocation), so returning later
-- re-centres rather than resuming wherever a previous visit left off.
function BuildController:_updateCamera(deltaTime: number)
	local origin = self._origin
	if not origin then
		return
	end

	if not self._panTarget then
		self._panTarget = origin.Position
	end

	-- Mouse-edge panning: hovering near a viewport border slides the view in
	-- that direction, no click needed -- the only way to look at a different
	-- part of a large station without walking there, now that the view no
	-- longer follows the character.
	local camera = getCamera()
	local viewport = camera.ViewportSize
	local mouse = UserInputService:GetMouseLocation()

	local panRight, panForward = 0, 0
	if mouse.X <= VIEW.PanEdgeMargin then
		panRight = -1
	elseif mouse.X >= viewport.X - VIEW.PanEdgeMargin then
		panRight = 1
	end
	if mouse.Y <= VIEW.PanEdgeMargin then
		panForward = -1
	elseif mouse.Y >= viewport.Y - VIEW.PanEdgeMargin then
		panForward = 1
	end

	if panRight ~= 0 or panForward ~= 0 then
		-- Relative to the view's CURRENT facing (yaw), not raw world axes:
		-- "toward the right edge" always pans right on screen, however the
		-- view is currently rotated (Q/E).
		local right = Vector3.new(math.cos(self._yaw), 0, -math.sin(self._yaw))
		local forward = Vector3.new(math.sin(self._yaw), 0, math.cos(self._yaw))
		local delta = (right * panRight + forward * panForward) * VIEW.PanSpeed * deltaTime
		self._panTarget = self._panTarget + delta
	end

	-- Clamped to the grid itself: nothing built ever sits past its edge.
	local maxExtent = GRID_RULES.radius * GRID_RULES.cellSize
	local localX = math.clamp(self._panTarget.X - origin.Position.X, -maxExtent, maxExtent)
	local localZ = math.clamp(self._panTarget.Z - origin.Position.Z, -maxExtent, maxExtent)
	self._panTarget =
		Vector3.new(origin.Position.X + localX, origin.Position.Y, origin.Position.Z + localZ)

	local horizontal = math.cos(VIEW.Pitch) * self._zoom
	local offset = Vector3.new(
		math.sin(self._yaw) * horizontal,
		math.sin(VIEW.Pitch) * self._zoom,
		math.cos(self._yaw) * horizontal
	)
	camera.CFrame = CFrame.lookAt(self._panTarget + offset, self._panTarget)
end

function BuildController:_setBuildView(active: boolean)
	if active == self._buildView then
		return
	end
	self._buildView = active

	if active then
		getCamera().CameraType = Enum.CameraType.Scriptable
		self:_updateCamera(0)
	else
		getCamera().CameraType = Enum.CameraType.Custom
	end

	-- The character is NOT frozen: WASD still moves it, camera-relative to
	-- whatever the view currently faces. But moving no longer pans the
	-- camera itself -- that's mouse-edge panning now (see _updateCamera) --
	-- so the view stays put and predictable while working across a big
	-- station.
end

-- In build mode as soon as the menu is open or a tool is in hand, and only
-- on your own station.
function BuildController:_refreshView()
	self:_setBuildView(
		self._location == "Station"
			and (
				self._panel:IsOpen()
				or self._selected ~= nil
				or self._demolishing
				or self._upgrading
				or self._modifying
			)
	)
end

----------------------------------------------------------------------
-- Mouse -> cell

-- Intersection of the camera ray with the station's plane. Going through
-- the plane rather than a raycast means already-placed modules don't block
-- aiming at the cell behind them.
function BuildController:_cellUnderMouse(): { x: number, y: number }?
	local origin = self._origin
	if not origin then
		return nil
	end

	local mouse = UserInputService:GetMouseLocation()
	local ray = getCamera():ViewportPointToRay(mouse.X, mouse.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end

	local distance = (origin.Position.Y - ray.Origin.Y) / ray.Direction.Y
	if distance < 0 then
		return nil
	end

	local worldPoint = ray.Origin + ray.Direction * distance
	local localPoint = origin:PointToObjectSpace(worldPoint)
	return {
		x = math.round(localPoint.X / GRID_RULES.cellSize),
		y = math.round(localPoint.Z / GRID_RULES.cellSize),
	}
end

-- The module is centered on the cursor, not anchored by its corner.
local function anchorFor(cell: { x: number, y: number }, width: number, depth: number)
	return {
		x = cell.x - math.floor((width - 1) / 2),
		y = cell.y - math.floor((depth - 1) / 2),
	}
end

----------------------------------------------------------------------
-- Same validation as the server, just to color the preview
--
-- Doubles as the move-preview check: while self._movingFrom is set, the
-- module's OWN old cells never block it (it's vacating them, see
-- Placement.canMove server-side) and there's no cost -- a move is free.

function BuildController:_canPlace(
	definition: ModuleCatalog.ModuleDef,
	anchor: { x: number, y: number }
): boolean
	local width, depth = ModuleCatalog.sizeOf(definition, self._rotation)

	if not Grid.isInBounds(anchor.x, anchor.y, width, depth, GRID_RULES) then
		return false
	end
	if not self._movingFrom and self._credits < definition.cost then
		return false
	end

	local ignoreEntry = if self._movingFrom
		then self._occupancy[Grid.key(self._movingFrom.x, self._movingFrom.y)]
		else nil

	local cells = Grid.cells(anchor.x, anchor.y, width, depth)
	for _, cell in cells do
		local occupant = self._occupancy[Grid.key(cell.x, cell.y)]
		if occupant and occupant ~= ignoreEntry then
			return false
		end
	end

	for _, cell in cells do
		for _, neighbour in Grid.neighbours(cell.x, cell.y) do
			local occupant = self._occupancy[Grid.key(neighbour.x, neighbour.y)]
			if occupant and occupant ~= ignoreEntry then
				return true
			end
		end
	end
	return false
end

----------------------------------------------------------------------
-- Preview
--
-- The ghost is built from the SAME ModuleGeometry the server uses for the
-- real placement (StationSceneBuilder.buildModuleModel), not a generic box:
-- it shows the exact shape, facing AND level before placing -- essential
-- once a module isn't symmetric (collector, smelter, cargo bay...) and once
-- a module's look actually changes with its level. Building for a NEW
-- module (from the catalogue) always previews level 1 -- that is what
-- placing pays for. Picking one UP to move it (self._movingFrom set)
-- previews it at its OWN current level (self._movingLevel, captured in
-- _pickUpForMove) -- moving never changes a module's level, so the ghost
-- must not silently reset it to 1 either.
--
-- Falls back to the legacy ReplicatedStorage.ModuleModels template, then to
-- a generic box, in exactly the same order StationSceneBuilder falls back
-- server-side -- so the preview and the real placement can never disagree
-- about which module ids have geometry.

local GHOST_TRANSPARENCY_BOOST = 0.55 -- added to the model's own transparency
local GHOST_TRANSPARENCY_MAX = 0.85 -- never fully invisible

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

function BuildController:_destroyGhost()
	if self._ghost then
		self._ghost:Destroy()
		self._ghost = nil
	end
	self._ghostParts = nil
	self._ghostHighlight = nil
	self._anchor = nil
end

-- Toggles visibility of the whole ghost (every part + its Highlight)
-- without rebuilding anything: called every frame.
function BuildController:_setGhostVisible(visible: boolean)
	local parts = self._ghostParts
	if not parts then
		return
	end
	for part, shownTransparency in parts do
		part.Transparency = if visible then shownTransparency else 1
	end
	if self._ghostHighlight then
		self._ghostHighlight.Enabled = visible
	end
end

function BuildController:_rebuildGhost()
	self:_destroyGhost()

	local definition = if self._selected then ModuleCatalog.get(self._selected) else nil
	if not definition then
		return
	end

	local parts: { [BasePart]: number } = {}
	local ghost: Model | BasePart
	local highlight: Highlight? = nil

	-- New build -> always level 1 (what placing actually buys). Moving an
	-- existing module -> its own current level, captured when it was picked
	-- up -- never assume 1 here, or the ghost would misrepresent an upgraded
	-- module as freshly built.
	local level = if self._movingFrom then self._movingLevel or 1 else 1
	local built = ModuleGeometry.build(definition, GRID_RULES.cellSize, level, MAX_LEVEL)
	local template = if not built then templateFor(definition.id) else nil
	if built or template then
		local model = if built then built else (template :: Model):Clone()
		model.Name = "Ghost"
		model.PrimaryPart = nil

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.CastShadow = false
				local shown = math.clamp(
					descendant.Transparency + GHOST_TRANSPARENCY_BOOST,
					0,
					GHOST_TRANSPARENCY_MAX
				)
				descendant.Transparency = shown
				parts[descendant] = shown
			elseif descendant:IsA("Light") then
				-- A halo that follows the mouse distracts more than it helps.
				descendant.Enabled = false
			end
		end

		model.Parent = workspace.Effects
		ghost = model

		-- Validity goes through a Highlight, not part color: the module
		-- must still be recognizable (the solar panel's blue, the
		-- radiator's orange...), not just a uniformly tinted block.
		highlight = Instance.new("Highlight")
		highlight.Name = "Validity"
		highlight.FillColor = COLORS.Valid
		highlight.OutlineColor = COLORS.Valid
		highlight.FillTransparency = 0.75
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = model
		highlight.Parent = model
	else
		local width, depth = ModuleCatalog.sizeOf(definition, self._rotation)
		local part = Instance.new("Part")
		part.Name = "Ghost"
		part.Size = Vector3.new(
			width * GRID_RULES.cellSize - 0.5,
			definition.height,
			depth * GRID_RULES.cellSize - 0.5
		)
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = COLORS.Valid
		part.Transparency = 0.5
		part.Parent = workspace.Effects

		parts[part] = 0.5
		ghost = part
	end

	self._ghost = ghost
	self._ghostParts = parts
	self._ghostHighlight = highlight
end

function BuildController:_updateGhost()
	local ghost = self._ghost
	local definition = if self._selected then ModuleCatalog.get(self._selected) else nil
	if not (ghost and definition and self._origin) then
		return
	end

	local cell = self:_cellUnderMouse()
	if not cell then
		self:_setGhostVisible(false)
		self._anchor = nil
		return
	end

	local width, depth = ModuleCatalog.sizeOf(definition, self._rotation)
	local anchor = anchorFor(cell, width, depth)
	self._anchor = anchor

	local valid = self:_canPlace(definition, anchor)
	self:_setGhostVisible(true)

	local color = if valid then COLORS.Valid else COLORS.Invalid
	if self._ghostHighlight then
		self._ghostHighlight.FillColor = color
		self._ghostHighlight.OutlineColor = color
	elseif ghost:IsA("BasePart") then
		ghost.Color = color
	end

	-- Same pivot math as the server (StationSceneBuilder.buildModuleModel):
	-- the ghost turns and lands exactly like the real module, in the same
	-- clockwise direction.
	local offset = Grid.offset(anchor.x, anchor.y, width, depth, GRID_RULES)
	local pivot = (self._origin :: CFrame)
		* CFrame.new(offset.x, offset.y, offset.z)
		* CFrame.Angles(0, -math.rad(90) * self._rotation, 0)

	if ghost:IsA("Model") then
		ghost:PivotTo(pivot)
	else
		ghost.CFrame = pivot * CFrame.new(0, definition.height / 2, 0)
	end
end

----------------------------------------------------------------------
-- Demolition highlight
--
-- Deliberately NOT the ground-plane math _cellUnderMouse() uses for the
-- placement ghost: that projects the mouse ray onto the deck's plane,
-- which is exactly right for picking an empty cell (there's nothing to
-- intersect yet) but wrong for picking an EXISTING module with real
-- height -- what's visually under the cursor (the side or top of a tall
-- Fabricator, say) lands on a different deck cell than what's actually on
-- screen, worse the taller the module and the more oblique the camera
-- angle. A real raycast against the placed Instances themselves always
-- matches what the player is actually looking at, at any height.
local MAX_HOVER_DISTANCE = 1000

function BuildController:_hoveredEntry(): Entry?
	local folder = self._folder
	if not folder then
		return nil
	end

	local mouse = UserInputService:GetMouseLocation()
	local ray = getCamera():ViewportPointToRay(mouse.X, mouse.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_HOVER_DISTANCE, params)
	if not result then
		return nil
	end

	-- Only a direct child of the station folder is a real placed module --
	-- excludes the StationSpawn part sitting in the same folder.
	local model = result.Instance:FindFirstAncestorWhichIsA("Model")
	if not model or model.Parent ~= folder then
		return nil
	end

	local x = model:GetAttribute("X")
	local y = model:GetAttribute("Y")
	if typeof(x) ~= "number" or typeof(y) ~= "number" then
		return nil
	end

	return self._occupancy[Grid.key(x, y)]
end

function BuildController:_destroyHighlight()
	if self._highlight then
		self._highlight:Destroy()
		self._highlight = nil
	end
	self._hovered = nil
end

function BuildController:_updateHighlight()
	local origin = self._origin
	if not origin then
		return
	end

	local entry = self:_hoveredEntry()
	local definition = if entry then ModuleCatalog.get(entry.id) else nil
	if not (entry and definition) then
		self:_destroyHighlight()
		return
	end

	if not self._highlight then
		local box = Instance.new("Part")
		box.Name = "ActionHighlight"
		box.Anchored = true
		box.CanCollide = false
		box.CanQuery = false
		box.CanTouch = false
		box.Transparency = 0.45
		box.Material = Enum.Material.Neon
		box.Color = COLORS.Invalid
		box.Parent = workspace.Effects
		self._highlight = box
	end

	local width, depth = ModuleCatalog.sizeOf(definition, entry.rotation)
	local offset = Grid.offset(entry.x, entry.y, width, depth, GRID_RULES)
	self._highlight.Size = Vector3.new(
		width * GRID_RULES.cellSize - 0.2,
		definition.height + 0.4,
		depth * GRID_RULES.cellSize - 0.2
	)
	self._highlight.CFrame = origin
		* CFrame.new(offset.x, offset.y, offset.z)
		* CFrame.new(0, definition.height / 2, 0)
	-- The same highlight serves all three modes: red demolishes, amber
	-- upgrades, teal picks up to move. Color alone says what the click will
	-- do.
	self._highlight.Color = if self._upgrading
		then Theme.Function.Info
		elseif self._modifying then Theme.Function.Move
		else COLORS.Invalid

	self._hovered = entry
end

----------------------------------------------------------------------
-- Modes

function BuildController:_select(id: string?)
	self._selected = id
	self._rotation = 0
	if id then
		self._demolishing = false
		self._upgrading = false
		self._panel:SetDemolishing(false)
		self._panel:SetUpgrading(false)
		self:_exitModify()
		self:_destroyHighlight()
		-- Close the menu: the player needs to see their station to place.
		self._panel:Close()
	end
	self._panel:SetSelected(id)
	self:_rebuildGhost()
	self:_refreshView()
end

function BuildController:_toggleDemolish()
	local wanted = not self._demolishing
	if wanted then
		self:_select(nil)
		self._upgrading = false
		self._panel:SetUpgrading(false)
		self:_exitModify()
		self._panel:Close()
	else
		self:_destroyHighlight()
	end
	self._demolishing = wanted
	self._panel:SetDemolishing(wanted)
	self:_refreshView()
end

-- The modes are mutually exclusive: they share the same highlight and left
-- click, letting them coexist would make the action unpredictable.
function BuildController:_toggleUpgrade()
	local wanted = not self._upgrading
	if wanted then
		self:_select(nil)
		self._demolishing = false
		self._panel:SetDemolishing(false)
		self:_exitModify()
		self._panel:Close()
	else
		self:_destroyHighlight()
	end
	self._upgrading = wanted
	self._panel:SetUpgrading(wanted)
	self:_refreshView()
end

function BuildController:_toggleModify()
	local wanted = not self._modifying
	if wanted then
		self:_select(nil)
		self._demolishing = false
		self._upgrading = false
		self._panel:SetDemolishing(false)
		self._panel:SetUpgrading(false)
		self._panel:Close()
	else
		self:_cancelMove()
		self:_destroyHighlight()
	end
	self._modifying = wanted
	self._panel:SetModifying(wanted)
	self:_refreshView()
end

-- Used by the OTHER modes/selections when they take over: leaves modify mode
-- entirely, cancelling a move in progress rather than silently abandoning
-- it mid-air.
function BuildController:_exitModify()
	if not self._modifying then
		return
	end
	self:_cancelMove()
	self._modifying = false
	self._panel:SetModifying(false)
end

-- "Picks up" an existing module to reposition it: reuses the ordinary
-- ghost-preview machinery (self._selected/self._rotation), just sourced from
-- an existing placement instead of the catalogue.
function BuildController:_pickUpForMove(entry: Entry)
	self._movingFrom = { x = entry.x, y = entry.y }
	self._movingLevel = entry.level
	self._selected = entry.id
	self._rotation = entry.rotation
	self:_destroyHighlight()
	self:_rebuildGhost()
	self:_refreshView()
end

function BuildController:_cancelMove()
	if not self._movingFrom then
		return
	end
	self._movingFrom = nil
	self._movingLevel = nil
	self._selected = nil
	self._rotation = 0
	self:_destroyGhost()
	self:_refreshView()
end

----------------------------------------------------------------------
-- Actions

function BuildController:_place()
	local definition = if self._selected then ModuleCatalog.get(self._selected) else nil
	local anchor = self._anchor
	if not (definition and anchor) then
		return
	end

	local ok, reason =
		Net.PlaceModule:InvokeServer(definition.id, anchor.x, anchor.y, self._rotation)
	if ok then
		self._panel:Toast(`{definition.name} posé`, false)
	else
		self._panel:Toast(tostring(reason), true)
	end
end

function BuildController:_upgrade()
	local entry = self._hovered
	if not entry then
		return
	end

	local ok, reason = Net.UpgradeModule:InvokeServer(entry.x, entry.y)
	-- The server's response is shown as-is, success or refusal: it's the
	-- one that knows the exact cost and the cap.
	self._panel:Toast(tostring(reason), not ok)
end

function BuildController:_demolish()
	local entry = self._hovered
	if not entry then
		return
	end

	local ok, reason = Net.RemoveModule:InvokeServer(entry.x, entry.y)
	if ok then
		local definition = ModuleCatalog.get(entry.id)
		self._panel:Toast(`{if definition then definition.name else entry.id} démonté`, false)
		self:_destroyHighlight()
	else
		self._panel:Toast(tostring(reason), true)
	end
end

-- Left click while in modify mode: picks a module up if none is in hand
-- yet, or confirms the move already in progress.
function BuildController:_modifyClick()
	if self._movingFrom then
		self:_confirmMove()
		return
	end

	local entry = self._hovered
	if not entry then
		return
	end
	if entry.id == "Core" then
		self._panel:Toast("Le noyau ne peut pas être déplacé", true)
		return
	end
	self:_pickUpForMove(entry)
end

-- Right click while in modify mode: cancels the move in hand, or leaves the
-- mode entirely if nothing is picked up yet -- same shape as demolish/
-- upgrade's own right-click.
function BuildController:_modifyCancelOrExit()
	if self._movingFrom then
		self:_cancelMove()
	else
		self:_toggleModify()
	end
end

function BuildController:_confirmMove()
	local from = self._movingFrom
	local anchor = self._anchor
	if not (from and anchor) then
		return
	end

	local ok, reason =
		Net.MoveModule:InvokeServer(from.x, from.y, anchor.x, anchor.y, self._rotation)
	self._panel:Toast(if ok then "Module déplacé" else tostring(reason), not ok)

	self._movingFrom = nil
	self._movingLevel = nil
	self._selected = nil
	self._rotation = 0
	self:_destroyGhost()
end

----------------------------------------------------------------------

function BuildController:_onInput(input: InputObject, gameProcessed: boolean)
	-- None of these shortcuts mean anything in the lobby.
	if self._location ~= "Station" then
		return
	end

	if input.KeyCode == Enum.KeyCode.B then
		self._panel:Toggle()
		self:_refreshView()
		return
	end
	if input.KeyCode == Enum.KeyCode.R and self._selected then
		-- One clockwise quarter-turn per press; wraps to 0 after the fourth
		-- (same math server-side, in StationSceneBuilder.buildModuleModel).
		self._rotation = (self._rotation + 1) % 4
		self:_rebuildGhost()
		return
	end
	if input.KeyCode == Enum.KeyCode.X then
		self:_toggleDemolish()
		return
	end
	if input.KeyCode == Enum.KeyCode.U then
		self:_toggleUpgrade()
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		self:_toggleModify()
		return
	end

	-- View rotation, only while in build mode.
	if self._buildView then
		if input.KeyCode == Enum.KeyCode.Q then
			self._yaw -= VIEW.YawStep
			return
		elseif input.KeyCode == Enum.KeyCode.E then
			self._yaw += VIEW.YawStep
			return
		end
	end

	-- gameProcessed is true when the click was consumed by the interface:
	-- without this check, clicking a menu card would also place a module.
	if gameProcessed or self._panel:IsOpen() then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if self._demolishing then
			self:_demolish()
		elseif self._upgrading then
			self:_upgrade()
		elseif self._modifying then
			self:_modifyClick()
		elseif self._selected then
			self:_place()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if self._demolishing then
			self:_toggleDemolish()
		elseif self._upgrading then
			self:_toggleUpgrade()
		elseif self._modifying then
			self:_modifyCancelOrExit()
		else
			self:_select(nil)
		end
	end
end

function BuildController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildUI"
	gui.ResetOnSpawn = false
	-- Same rule as the HUD: leave the Roblox topbar alone. See the comment
	-- in HudController.
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	-- Sibling: ZIndex compares between siblings, within the parent's
	-- context. Under Global (Instance.new's default) it compares across the
	-- whole ScreenGui: the window's backdrop (ZIndex 6) drew OVER its own
	-- content (ZIndex 1), and the menu opened empty.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- The highest of the three: the menu is modal, it must cover everything,
	-- objective banner included. Hud = 1, ObjectiveUI = 5, BuildUI = 10.
	gui.DisplayOrder = 10
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	self._panel = BuildPanel.new(gui)
	self._panel.onSelect = function(id)
		self:_select(id)
	end
	self._panel.onToggleDemolish = function()
		self:_toggleDemolish()
	end
	self._panel.onToggleUpgrade = function()
		self:_toggleUpgrade()
	end
	self._panel.onToggleModify = function()
		self:_toggleModify()
	end
	self._panel.onOpenChanged = function()
		self:_refreshView()
	end
	self._panel.onReturnToLobby = function()
		Net.ReturnToLobby:InvokeServer()
	end
	self._panel.onRebirthRequested = function()
		-- The free rebirth's own bonus alone -- deliberately never blended
		-- with Ultimate or EarlyRebirth's own wording: those are separate,
		-- unrelated purchases (Ultimate boosts production regardless of
		-- rebirths; EarlyRebirth only changes WHEN a rebirth is allowed,
		-- never by how much).
		local percent = math.floor(Balance.Rebirth.BonusPerRebirth * 100)
		self._panel:ShowConfirm(
			"RENAISSANCE ?",
			`Ajoute +{percent}% de production, cumulable à chaque renaissance -- indépendant de tes autres bonus (Ultimate, Renaissance anticipée). Réinitialise ta station ET tes crédits. Cette action est irréversible.`,
			Theme.Function.Rebirth,
			function()
				local ok, reason = Net.RebirthStation:InvokeServer()
				self._panel:Toast(if ok then "Renaissance !" else tostring(reason), not ok)
			end
		)
	end
	self._panel.onUltimateRequested = function()
		self._panel:ShowConfirm(
			"ULTIMATE",
			`Multiplie TOUTE la production par x{Balance.Rebirth.UltimateMultiplier}, en permanence -- indépendant des renaissances.`,
			Theme.Function.Ultimate,
			function()
				-- No real Roblox Game Pass exists yet for this: grants it
				-- directly, the same dev-only path the Dev Mode panel uses,
				-- until a real Game Pass is created and this is swapped for
				-- an actual MarketplaceService purchase prompt.
				local ok, reason = Net.DevSetPass:InvokeServer("Ultimate", true)
				self._panel:Toast(if ok then "Ultimate débloqué !" else tostring(reason), not ok)
			end
		)
	end

	self._panel:SetCredits(0)
	-- Always starts in the lobby; the server will confirm.
	self._panel:SetAvailable(false)

	State.Changed:Connect(function(key: string, value: any)
		if key == "Location" then
			self:_setLocation(value :: string)
		elseif key == "Credits" then
			self._credits = value :: number
			self._panel:SetCredits(self._credits)
		elseif key == "HasUltimate" then
			self._panel:SetUltimateOwned(value == true)
		end
	end)

	local initialLocation = State.get("Location")
	if initialLocation then
		self:_setLocation(initialLocation :: string)
	end
	local initialCredits = State.get("Credits")
	if initialCredits then
		self._credits = initialCredits :: number
		self._panel:SetCredits(self._credits)
	end
	self._panel:SetUltimateOwned(State.get("HasUltimate") == true)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		self:_onInput(input, gameProcessed)
	end)

	UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed or not self._buildView then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			self._zoom = math.clamp(
				self._zoom - input.Position.Z * VIEW.ZoomStep,
				VIEW.ZoomMin,
				VIEW.ZoomMax
			)
		end
	end)

	RunService.RenderStepped:Connect(function(deltaTime: number)
		if self._buildView then
			self:_updateCamera(deltaTime)
		end
		if self._panel:IsOpen() or self._location ~= "Station" then
			return
		end
		if self._demolishing or self._upgrading or (self._modifying and not self._movingFrom) then
			self:_updateHighlight()
		elseif self._selected then
			self:_updateGhost()
		end
	end)
end

return BuildController
