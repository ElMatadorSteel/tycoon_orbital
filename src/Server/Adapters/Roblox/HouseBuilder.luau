--!strict
-- Builds the tycoon-style house on the house plateau: sequential purchase
-- pads that each reveal one stage of an authored model stored in
-- ReplicatedStorage.HouseModels.SuburbanHouse. Stages are Folders inside
-- the model, named Stage1_Pelouse through Stage5_Toit, each containing
-- the BaseParts for that construction phase.
--
-- The builder does NOT decide whether a purchase succeeds -- it exposes a
-- Signal that fires with (userId, stageId), and the use case that handles
-- it calls back :unlockStage when it accepts. Same contract as every other
-- pad in this codebase (see StationSceneBuilder's researchPadTouched).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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

local Signal = require(fromShared("Signal"))

local PALETTE = {
	PadLocked = Color3.fromRGB(255, 176, 60),
	PadOpen = Color3.fromRGB(80, 226, 128),
	PadRefused = Color3.fromRGB(255, 82, 82),
	Trim = Color3.fromRGB(72, 214, 255),
	Structure = Color3.fromRGB(78, 86, 104),
}

-- Mapping from Balance stage ids to the folder names inside the model.
local STAGE_FOLDERS = {
	Jardin = "Stage01_Jardin",
	Fondations = "Stage02_Fondations",
	MursExterieurs = "Stage03_MursExterieurs",
	Garage = "Stage04_Garage",
	Cuisine = "Stage05_Cuisine",
	Salon = "Stage06_Salon",
	SalleAManger = "Stage07_SalleAManger",
	Entree = "Stage08_Entree",
	Etage = "Stage09_Etage",
	Toit = "Stage10_Toit",
}

-- The authored model is small; scale it up so the rooms feel right.
local HOUSE_SCALE = 1.5

-- Per-stage pad positions relative to the house centre (at scale 1).
-- Multiplied by HOUSE_SCALE at runtime so they track the scaled geometry.
-- y is the extra height above the ground floor (0 = ground, ~13 = upper).
local PAD_SIZE = 6
local STAGE_PAD_OFFSETS: { [string]: { x: number, z: number, y: number } } = {
	Jardin = { x = 0, z = -55, y = 0 }, -- front yard, away from house
	Fondations = { x = 0, z = 50, y = 0 }, -- behind the house
	MursExterieurs = { x = 50, z = 0, y = 0 }, -- right of house
	Garage = { x = 29, z = -40, y = 2 }, -- inside the garage
	Cuisine = { x = -25, z = 0, y = 2 }, -- inside the kitchen
	Salon = { x = 2, z = 23, y = 2 }, -- inside the living room
	SalleAManger = { x = -32, z = 23, y = 2 }, -- inside the dining room
	Entree = { x = -3, z = -9, y = 2 }, -- inside the entrance
	Etage = { x = -8, z = -7, y = 14 }, -- upstairs landing
	Toit = { x = -13, z = 7, y = 14 }, -- upstairs bathroom, near stairs
}

-- There used to be an UPSTAIRS_FLOOR_FILL here: an invisible 25 x 14 slab laid
-- across the opening in the upper floor at x -30.7..-5.7, z 5.1..19.1, on the
-- theory that the opening was a gap left by ScaleTo and players were falling
-- through it.
--
-- The opening is the stairwell.  It is walled on every side (a 25.8-stud wall
-- at x ~= -8, another at x ~= -32, balusters along z ~= 7) and the staircase
-- climbs through it, so nothing was ever falling into it.  What the slab did
-- do was sit 1.94 studs above the treads it covered -- 0.23 studs of headroom
-- once HOUSE_SCALE multiplied both -- which sealed the upper half of the
-- flight. That is the "physics broke when we scaled the model" symptom: the
-- slab and the stairs scaled together, the character did not.
--
-- Nothing replaces it. If a real fall hazard turns up, guard that edge with a
-- thin vertical part; never lay a floor across the stairwell.

local function part(parent: Instance, name: string, props: { [string]: any }): BasePart
	local instance = Instance.new("Part")
	instance.Name = name
	instance.Anchored = true
	instance.CanCollide = true
	instance.CastShadow = false
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

local function pointLight(host: BasePart, colour: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = colour
	light.Range = range
	light.Brightness = brightness
	light.Parent = host
end

local function label(pad: BasePart, title: string, subtitle: string)
	local anchor = Instance.new("Part")
	anchor.Name = "SignAnchor"
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.CFrame = CFrame.new(pad.Position + Vector3.new(0, 4, 0))
	anchor.Parent = pad

	local gui = Instance.new("BillboardGui")
	gui.Name = "Sign"
	gui.Size = UDim2.fromScale(8, 3)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80 * HOUSE_SCALE
	gui.Adornee = anchor
	gui.Parent = anchor

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.fromScale(1, 0.5)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextScaled = true
	titleLabel.Text = title
	titleLabel.Parent = gui

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.Size = UDim2.fromScale(1, 0.5)
	detailLabel.Position = UDim2.fromScale(0, 0.5)
	detailLabel.BackgroundTransparency = 1
	detailLabel.Font = Enum.Font.Gotham
	detailLabel.TextColor3 = PALETTE.PadLocked
	detailLabel.TextScaled = true
	detailLabel.Text = subtitle
	detailLabel.Parent = gui

	return gui
end

----------------------------------------------------------------------
-- Automatic doors: open when a player approaches, close after they leave.

local DOOR_OPEN_ANGLE = math.rad(-90)
local DOOR_CLOSE_DELAY = 3
local DOOR_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DOOR_DETECT_RANGE = 8 * HOUSE_SCALE

local function setupAutoDoor(doorPart: BasePart)
	-- _revealStage runs again whenever a stage is re-revealed (a stage already
	-- owned at build time, then a DevResetHouse rebuild).  A second handler on
	-- the same door fights the first over one CFrame tween, and the two
	-- disagree about CanCollide while they do it.
	if doorPart:GetAttribute("_autoDoor") then
		return
	end
	doorPart:SetAttribute("_autoDoor", true)

	-- Determine door width axis: the axis that is NOT thin and NOT height.
	local s = doorPart.Size
	local widthAxis: string
	local halfWidth: number
	if s.X < s.Z then
		-- thin in X → width along Z
		widthAxis = "Z"
		halfWidth = s.Z / 2
	else
		-- thin in Z → width along X
		widthAxis = "X"
		halfWidth = s.X / 2
	end

	-- Hinge offset: one edge of the door, in the door's local space.
	local hingeOffset: CFrame
	if widthAxis == "X" then
		hingeOffset = CFrame.new(-halfWidth, 0, 0)
	else
		hingeOffset = CFrame.new(0, 0, -halfWidth)
	end

	local closedCF = doorPart.CFrame
	local doorCenter = closedCF.Position
	-- What "closed" means for THIS door.  Two of the tagged doors are the
	-- authored glass panels, which are CanCollide = false on purpose; closing
	-- them back to a hard-coded `true` turned them into solid panes.
	local solidWhenClosed = doorPart.CanCollide
	local openCF = closedCF
		* hingeOffset
		* CFrame.Angles(0, DOOR_OPEN_ANGLE, 0)
		* hingeOffset:Inverse()

	local isOpen = false

	-- Proximity check: every heartbeat, see if any player character is near.
	local rangeSq = DOOR_DETECT_RANGE * DOOR_DETECT_RANGE
	-- Vertical window, measured from the door's own threshold rather than from
	-- its height: the authored doors are ~12 studs tall, which HOUSE_SCALE
	-- turns into ~18 -- taller than a storey -- so testing against the height
	-- opened a door for whoever was standing on the floor above it.
	local threshold = doorCenter.Y - s.Y / 2
	local storey = 6 * HOUSE_SCALE

	local connection: RBXScriptConnection
	connection = RunService.Heartbeat:Connect(function()
		if not doorPart.Parent then
			return
		end

		local nearby = false
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if hrp then
				local delta = hrp.Position - doorCenter
				local feet = hrp.Position.Y - 3
				if
					feet >= threshold - storey
					and feet <= threshold + storey
					and delta.X * delta.X + delta.Z * delta.Z <= rangeSq
				then
					nearby = true
					break
				end
			end
		end

		if nearby and not isOpen then
			isOpen = true
			doorPart.CanCollide = false
			doorPart.CanQuery = false
			TweenService:Create(doorPart, DOOR_TWEEN, { CFrame = openCF }):Play()
		elseif not nearby and isOpen then
			isOpen = false
			local tween = TweenService:Create(doorPart, DOOR_TWEEN, { CFrame = closedCF })
			tween.Completed:Once(function()
				doorPart.CanCollide = solidWhenClosed
				doorPart.CanQuery = true
			end)
			tween:Play()
		end
	end)

	-- Otherwise every rebuild leaks a handler that keeps walking the player
	-- list, once per door, for the rest of the server's life.
	doorPart.Destroying:Once(function()
		connection:Disconnect()
	end)
end

----------------------------------------------------------------------
-- Hide / show helpers: every visible instance type in the authored model
-- must be covered, not just BaseParts -- fires, lights, decals and scripts
-- would otherwise stay active while their parent wall is invisible.

local function hideDescendants(folder: Instance)
	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") then
			-- Save the authored CanCollide and Transparency so showDescendants
			-- restores what the model author chose instead of forcing every
			-- part solid and opaque.
			desc:SetAttribute("_origCanCollide", desc.CanCollide)
			desc:SetAttribute("_origTransparency", desc.Transparency)
			desc.Transparency = 1
			desc.CanCollide = false
			desc.CanQuery = false
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			desc:SetAttribute("_origTransparency", desc.Transparency)
			desc.Transparency = 1
		elseif
			desc:IsA("Light")
			or desc:IsA("Fire")
			or desc:IsA("Smoke")
			or desc:IsA("Sparkles")
			or desc:IsA("ParticleEmitter")
			or desc:IsA("BaseScript")
		then
			local node = desc :: any
			desc:SetAttribute("_origEnabled", node.Enabled)
			node.Enabled = false
		end
	end
end

local function showDescendants(folder: Instance)
	for _, desc in folder:GetDescendants() do
		if desc:IsA("BasePart") then
			-- Restore the model author's original Transparency: glass panes and
			-- window doors are authored semi-transparent, and forcing them to 0
			-- turned them into solid-looking panels you then walk straight
			-- through (they are CanCollide = false), which reads as broken
			-- collision even though nothing is.
			local origTransparency = desc:GetAttribute("_origTransparency")
			desc.Transparency = if origTransparency ~= nil then origTransparency else 0
			desc.CanQuery = true
			-- Restore the model author's original CanCollide.  Parts that
			-- were non-collidable in the template stay non-collidable,
			-- preventing invisible blockers from decorative/visual-only
			-- geometry.
			local orig = desc:GetAttribute("_origCanCollide")
			desc.CanCollide = if orig ~= nil then orig else true
			-- Set up automatic doors for tagged parts
			if desc:GetAttribute("Door") then
				setupAutoDoor(desc)
			end
		elseif desc:IsA("Decal") or desc:IsA("Texture") then
			local origTransparency = desc:GetAttribute("_origTransparency")
			desc.Transparency = if origTransparency ~= nil then origTransparency else 0
		elseif
			desc:IsA("Light")
			or desc:IsA("Fire")
			or desc:IsA("Smoke")
			or desc:IsA("Sparkles")
			or desc:IsA("ParticleEmitter")
			or desc:IsA("BaseScript")
		then
			-- Same reasoning as CanCollide: a script the template ships
			-- disabled stays disabled.  The imported model carries a legacy R6
			-- launcher (Torso.Velocity = 0,100,0) on a garden slab; forcing
			-- Enabled = true re-armed it on every reveal.
			local node = desc :: any
			local origEnabled = desc:GetAttribute("_origEnabled")
			node.Enabled = if origEnabled ~= nil then origEnabled else true
		end
	end
end

----------------------------------------------------------------------

export type StageConfig = {
	id: string,
	name: string,
	cost: number,
}

export type Config = {
	stages: { StageConfig },
}

type PadHandle = {
	pad: BasePart,
	sign: BillboardGui,
	stageId: string,
}

local HouseBuilder = {}
HouseBuilder.__index = HouseBuilder

function HouseBuilder.new(config: Config)
	return setmetatable({
		_config = config,
		_template = nil :: Model?,
		-- Per-userId state
		_pads = {} :: { [number]: { PadHandle } },
		_house = {} :: { [number]: Model },
		-- Fired with (userId, stageId) when a player touches a locked pad.
		stagePadTouched = Signal.new(),
	}, HouseBuilder)
end

function HouseBuilder:_loadTemplate(): Model?
	if self._template then
		return self._template
	end
	if not game then
		return nil
	end
	local folder = (game :: any):GetService("ReplicatedStorage"):FindFirstChild("HouseModels")
	local template = folder and folder:FindFirstChild("SuburbanHouse")
	if template and template:IsA("Model") then
		self._template = template
		return template
	end
	return nil
end

-- Format credits with thousands separator
local function money(n: number): string
	local s = tostring(n)
	local result = ""
	for i = #s, 1, -1 do
		result = s:sub(i, i) .. result
		if (#s - i + 1) % 3 == 0 and i > 1 then
			result = " " .. result
		end
	end
	return result .. " cr"
end

-- Build the house zone: pads + hidden house model, on the house plateau.
-- `plateauCFrame` is the world CFrame of the plateau centre at walking height.
-- `plateauWidth` and `plateauDepth` are the plateau dimensions.
function HouseBuilder:build(
	parent: Instance,
	plateauCFrame: CFrame,
	_plateauWidth: number,
	_plateauDepth: number,
	userId: number,
	unlockedStages: { [string]: boolean }
)
	local template = self:_loadTemplate()
	if not template then
		return
	end

	-- Clone the house, scale it up, and place it centred on the plateau
	local house = template:Clone()
	house.Name = `House_{userId}`
	house:ScaleTo(HOUSE_SCALE)

	-- Get the model's bounding box to position it correctly
	local box, size = house:GetBoundingBox()
	local baseY = box.Position.Y - size.Y / 2

	-- Position the house so its base sits on the plateau surface.
	-- plateauCFrame.Y is at WALK_Y - 0.5 (top of the platform slab),
	-- so the walking surface is plateauCFrame.Y + 0.5.
	local surfaceY = plateauCFrame.Position.Y + 0.5
	local offset = surfaceY - baseY
	house:PivotTo(
		CFrame.new(plateauCFrame.Position.X, box.Position.Y + offset, plateauCFrame.Position.Z)
			* CFrame.Angles(0, 0, 0)
	)

	-- Start with all stages hidden
	for _, folderName in STAGE_FOLDERS do
		local folder = house:FindFirstChild(folderName)
		if folder then
			hideDescendants(folder)
		end
	end

	house.Parent = parent
	self._house[userId] = house

	-- Place each purchase pad near the area it builds.
	local stages = self._config.stages

	local pads: { PadHandle } = {}
	for index, stage in stages do
		local offsets = STAGE_PAD_OFFSETS[stage.id]
		local padX = if offsets then offsets.x * HOUSE_SCALE else (index - 1) * (PAD_SIZE + 4)
		local padZ = if offsets then offsets.z * HOUSE_SCALE else 0
		local padY = if offsets then offsets.y * HOUSE_SCALE else 0
		local padCFrame = plateauCFrame * CFrame.new(padX, 0.8 + padY, padZ)

		local alreadyOwned = unlockedStages["House_" .. stage.id] == true

		if alreadyOwned then
			-- Already purchased: reveal stage, no pad needed.
			self:_revealStage(userId, stage.id)
			-- Still need a handle entry so index arithmetic stays correct.
			table.insert(pads, { pad = nil :: any, sign = nil :: any, stageId = stage.id })
		else
			local pad = part(parent, `HousePad_{stage.id}`, {
				Size = Vector3.new(PAD_SIZE, 0.6, PAD_SIZE),
				CFrame = padCFrame,
				Color = PALETTE.PadLocked,
				Material = Enum.Material.Neon,
			})
			pointLight(pad, PALETTE.PadLocked, 18, 1.6)

			local sign = label(pad, stage.name, money(stage.cost))

			local handle: PadHandle = {
				pad = pad,
				sign = sign,
				stageId = stage.id,
			}
			table.insert(pads, handle)
			-- Wire the pad's Touched to fire the signal
			pad.Touched:Connect(function(hit: BasePart)
				-- Only fire for the owning player
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player or player.UserId ~= userId then
					return
				end
				-- Debounce: don't fire if already owned
				if pad:GetAttribute("Owned") then
					return
				end
				self.stagePadTouched:Fire(userId, stage.id)
			end)

			-- Only show the NEXT available pad; hide future ones
			if index > 1 then
				local prevOwned = unlockedStages["House_" .. stages[index - 1].id] == true
				if not prevOwned then
					pad.Transparency = 1
					pad.CanCollide = false
					local anchor = pad:FindFirstChild("SignAnchor")
					if anchor then
						local gui = anchor:FindFirstChild("Sign")
						if gui then
							gui.Enabled = false
						end
					end
					local light = pad:FindFirstChildOfClass("PointLight")
					if light then
						light.Enabled = false
					end
				end
			end
		end
	end

	self._pads[userId] = pads
end

function HouseBuilder:_revealStage(userId: number, stageId: string)
	local house = self._house[userId]
	if not house then
		return
	end
	local folderName = STAGE_FOLDERS[stageId]
	if not folderName then
		return
	end
	local folder = house:FindFirstChild(folderName)
	if not folder then
		return
	end
	showDescendants(folder)
end

-- Called by the use case after a successful purchase.
function HouseBuilder:unlockStage(userId: number, stageId: string)
	self:_revealStage(userId, stageId)

	-- Update the pad visual
	local pads = self._pads[userId]
	if not pads then
		return
	end

	for index, handle in pads do
		if handle.stageId == stageId then
			-- Destroy the pad now that the stage is built.
			handle.pad:SetAttribute("Owned", true)
			handle.pad:Destroy()

			-- Show the NEXT pad (make it visible)
			local nextHandle = pads[index + 1]
			if nextHandle and nextHandle.pad then
				nextHandle.pad.Transparency = 0
				nextHandle.pad.CanCollide = true
				local nextAnchor = nextHandle.pad:FindFirstChild("SignAnchor")
				if nextAnchor then
					local gui = nextAnchor:FindFirstChild("Sign")
					if gui then
						gui.Enabled = true
					end
				end
				local nextLight = nextHandle.pad:FindFirstChildOfClass("PointLight")
				if nextLight then
					nextLight.Enabled = true
				end
			end
			break
		end
	end
end

-- Visual feedback for insufficient funds.
function HouseBuilder:refuse(userId: number, stageId: string)
	local pads = self._pads[userId]
	if not pads then
		return
	end
	for _, handle in pads do
		if handle.stageId == stageId and handle.pad then
			if handle.pad:GetAttribute("Refusing") then
				return
			end
			handle.pad:SetAttribute("Refusing", true)
			handle.pad.Color = PALETTE.PadRefused
			task.delay(0.45, function()
				if handle.pad.Parent then
					handle.pad.Color = PALETTE.PadLocked
					handle.pad:SetAttribute("Refusing", nil)
				end
			end)
			break
		end
	end
end

-- Remove all house instances and pads for a user so a fresh build can run.
function HouseBuilder:reset(userId: number)
	local house = self._house[userId]
	if house then
		house:Destroy()
		self._house[userId] = nil
	end
	local pads = self._pads[userId]
	if pads then
		for _, handle in pads do
			if handle.pad then
				handle.pad:Destroy()
			end
		end
		self._pads[userId] = nil
	end
end

return HouseBuilder
