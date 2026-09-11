--!strict
-- The Railgun mining side-feature: buying it at the lobby pad, receiving it
-- from the dispenser, and firing it at asteroids near your own station.
--
-- Free-aim, screen-center raycast: the client only ever CLAIMS which
-- asteroid id it hit (Net.FireRailgun:InvokeServer(asteroidId)) -- the
-- server is sole judge of whether that claim pays out.

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
	return "../../Shared/" .. path
end

local Balance = require(fromShared("Balance"))
local Net = require(fromShared("Net"))
local Icons = require(fromShared("Icons"))
local Theme = require("../UI/Theme")
local WeaponSelector = require("../UI/WeaponSelector")

local COLORS = Theme.Colors
local SPACE = Theme.Space

local MAX_HIT_DISTANCE = 1000

-- Laser beam: a thin neon cylinder from the tool to the target, fading out.
local BEAM_COLOR = Color3.fromRGB(255, 205, 60)
local BEAM_THICKNESS = 0.15
local BEAM_FADE_TIME = 0.25

local MiningController = {}

MiningController._equippedTool = nil :: Tool?

local function getCamera(): Camera
	return workspace.CurrentCamera
end

----------------------------------------------------------------------
-- Ephemeral toast -- same visual language as BuildPanel's own.

function MiningController:_buildToast(gui: ScreenGui)
	local icon = Theme.new("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SPACE.md, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		Image = Icons.Misc["Accept"],
	})
	local label = Theme.body({
		Position = UDim2.fromOffset(SPACE.md + 34, 0),
		Size = UDim2.new(1, -(SPACE.md + 42), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local scale = Theme.new("UIScale", { Scale = 1 })

	self._toastIcon = icon
	self._toastLabel = label
	self._toastScale = scale
	self._toast = Theme.panel({
		Name = "MiningToast",
		AnchorPoint = Vector2.new(0.5, 1),
		-- Lifted clear of the weapon selector, which owns the bottom centre.
		Position = UDim2.new(0.5, 0, 1, -(SPACE.xl + Theme.Hotbar.Reserve + 60 + SPACE.md)),
		Size = UDim2.fromOffset(440, Theme.Control.md),
		Radius = Theme.Radius.md,
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	}, { icon, label, scale })
end

function MiningController:_toastMessage(message: string, isError: boolean?)
	self._toastLabel.Text = message
	self._toastIcon.Image = if isError then Icons.Misc["Deny"] else Icons.Misc["Accept"]
	self._toast.BackgroundColor3 = if isError
		then Theme.darken(COLORS.Invalid, 0.3)
		else Theme.darken(COLORS.Valid, 0.3)
	self._toast.Visible = true

	self._toastScale.Scale = 0.7
	TweenService:Create(self._toastScale, Theme.Tween.Pop, { Scale = 1 }):Play()

	self._toastToken = (self._toastToken or 0) + 1
	local token = self._toastToken
	task.delay(1.5, function()
		if self._toastToken == token then
			self._toast.Visible = false
		end
	end)
end

----------------------------------------------------------------------
-- First-person detection: the crosshair only shows when the camera is
-- right on the character's head.  Threshold picked by eye -- anything
-- under ~2 studs reads as first person.  Higher than the head-bob
-- amplitude so the crosshair doesn't flicker while walking.
local FP_THRESHOLD = 2

function MiningController:_isFirstPerson(): boolean
	local character = Players.LocalPlayer.Character
	if not character then
		return false
	end
	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return false
	end
	return (getCamera().CFrame.Position - head.Position).Magnitude < FP_THRESHOLD
end

----------------------------------------------------------------------
-- Crosshair -- visible only in first person while the Railgun is equipped.
-- Uses its own ScreenGui with ScreenInsets = None so it sits at the true
-- viewport centre, not the CoreUI-safe centre (which is shifted down by
-- the topbar height).

function MiningController:_buildCrosshair(playerGui: Instance)
	local crosshairGui = Instance.new("ScreenGui")
	crosshairGui.Name = "CrosshairUI"
	crosshairGui.ResetOnSpawn = false
	crosshairGui.ScreenInsets = Enum.ScreenInsets.None
	crosshairGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	crosshairGui.DisplayOrder = 9
	crosshairGui.Parent = playerGui

	self._crosshair = Theme.new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = crosshairGui,
	}, {
		Theme.new("Frame", {
			Name = "H",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(24, 2),
			BackgroundColor3 = Theme.Function.Ultimate,
			BorderSizePixel = 0,
		}),
		Theme.new("Frame", {
			Name = "V",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(2, 24),
			BackgroundColor3 = Theme.Function.Ultimate,
			BorderSizePixel = 0,
		}),
	})
end

function MiningController:_setEquipped(equipped: boolean)
	self._equipped = equipped
	self._crosshair.Visible = equipped and self:_isFirstPerson()
end

----------------------------------------------------------------------
-- Firing

-- Returns the asteroid id AND the world-space hit position, so the beam
-- can be drawn even after the server despawns the model.
-- First person: raycast from viewport centre (locked cursor).
-- Third person: raycast from the mouse position (free cursor).
function MiningController:_aimResult(): (string?, Vector3?)
	local player = Players.LocalPlayer
	local asteroidsRoot = workspace:FindFirstChild("Asteroids")
	local folder = asteroidsRoot and asteroidsRoot:FindFirstChild(`Asteroids_{player.UserId}`)

	local camera = getCamera()
	local ray
	if self:_isFirstPerson() then
		local viewport = camera.ViewportSize
		ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	else
		-- Mouse.X/Y are in screen space (absolute), so ScreenPointToRay
		-- is the correct match — ViewportPointToRay would double-offset
		-- by the topbar height.
		local mouse = player:GetMouse()
		ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	end

	-- When there is an asteroid folder, try to hit one first.
	if folder then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { folder }

		local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_HIT_DISTANCE, params)
		if result then
			local model = result.Instance:FindFirstAncestorWhichIsA("Model")
			if model and model.Parent == folder then
				local asteroidId = model:GetAttribute("AsteroidId")
				if typeof(asteroidId) == "string" then
					return asteroidId, result.Position
				end
			end
		end
	end

	-- Nothing hit: return a far-away point along the aim direction so the
	-- beam still fires into the void (visual feedback that the weapon works).
	local farPoint = ray.Origin + ray.Direction * MAX_HIT_DISTANCE
	return nil, farPoint
end

function MiningController:_beamOrigin(): Vector3?
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return nil
	end
	-- Fire from the tool handle if equipped, otherwise from the character root.
	local tool = self._equippedTool
	if tool then
		local handle = tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			return handle.Position
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

function MiningController:_fireBeam(target: Vector3)
	local origin = self:_beamOrigin()
	if not origin then
		return
	end

	local direction = target - origin
	local distance = direction.Magnitude
	if distance < 1 then
		return
	end

	local beam = Instance.new("Part")
	beam.Name = "RailgunBeam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = BEAM_COLOR
	beam.Size = Vector3.new(BEAM_THICKNESS, BEAM_THICKNESS, distance)
	beam.CFrame = CFrame.lookAt(origin, target) * CFrame.new(0, 0, -distance / 2)
	beam.Parent = workspace

	TweenService:Create(beam, TweenInfo.new(BEAM_FADE_TIME, Enum.EasingStyle.Quad), {
		Transparency = 1,
		Size = Vector3.new(BEAM_THICKNESS * 3, BEAM_THICKNESS * 3, distance),
	}):Play()

	task.delay(BEAM_FADE_TIME + 0.05, function()
		beam:Destroy()
	end)
end

function MiningController:_fire()
	local asteroidId, hitPos = self:_aimResult()
	if not asteroidId then
		-- Nothing under the crosshair: fire the beam into the void anyway
		-- so the player sees the weapon is working.
		if hitPos then
			self:_fireBeam(hitPos)
		end
		return
	end

	-- Capture the hit position BEFORE calling the server, because the
	-- server despawns the asteroid model on success.
	self:_fireBeam(hitPos :: Vector3)

	local ok, result = Net.FireRailgun:InvokeServer(asteroidId)
	if ok then
		self:_toastMessage(`+{result.reward} cr ({result.tier})`, false)
		-- Only a SHOT THE SERVER ACCEPTED starts the cooldown read-out. A
		-- refused shot spent nothing, and showing a sweep for it would teach
		-- the player a rule the game does not have.
		self._selector:BeginCooldown()
	else
		self:_toastMessage(tostring(result), true)
	end
end

----------------------------------------------------------------------
-- Tool tracking

function MiningController:_bindTool(tool: Tool)
	if tool:GetAttribute("MiningBound") then
		return -- already connected -- Backpack/Character both fire ChildAdded
	end
	tool:SetAttribute("MiningBound", true)

	tool.Equipped:Connect(function()
		self._equippedTool = tool
		self:_setEquipped(true)
	end)
	tool.Unequipped:Connect(function()
		if self._equippedTool == tool then
			self._equippedTool = nil
		end
		self:_setEquipped(false)
	end)
	tool.Activated:Connect(function()
		self:_fire()
	end)
end

function MiningController:_scanForTool(container: Instance)
	local existing = container:FindFirstChild("Railgun")
	if existing and existing:IsA("Tool") then
		self:_bindTool(existing)
	end
	container.ChildAdded:Connect(function(child)
		if child.Name == "Railgun" and child:IsA("Tool") then
			self:_bindTool(child)
		end
	end)
end

----------------------------------------------------------------------
-- The purchase pad -- client-initiated: a purchase can fail (insufficient
-- funds, already owned), and only the client can show a toast for that.

function MiningController:_bindPad()
	local scenery = workspace:WaitForChild("Scenery")
	local lobby = scenery:WaitForChild("Lobby")
	local pad = lobby:WaitForChild("RailgunPad")
	local prompt = pad:WaitForChild("ProximityPrompt") :: ProximityPrompt

	prompt.Triggered:Connect(function()
		local ok, reason = Net.PurchaseRailgun:InvokeServer()
		self:_toastMessage(if ok then "Railgun acheté !" else tostring(reason), not ok)
	end)
end

function MiningController:Start()
	local player = Players.LocalPlayer

	local gui = Instance.new("ScreenGui")
	gui.Name = "MiningUI"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 8
	local playerGui = player:WaitForChild("PlayerGui")
	gui.Parent = playerGui

	self:_buildCrosshair(playerGui)
	self:_buildToast(gui)

	-- The hotbar. It reads the Backpack itself, so it needs telling only the
	-- two things it cannot know: how long the cooldown lasts, and what to draw
	-- when a tool carries no TextureId of its own.
	self._selector = WeaponSelector.new(gui, {
		Cooldown = Balance.Mining.Railgun.Cooldown,
		FallbackImage = Icons.Stats["Rocket"],
	})

	self:_bindPad()

	local backpack = player:WaitForChild("Backpack")
	self:_scanForTool(backpack)

	local function onCharacter(character: Model)
		self:_scanForTool(character)
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	-- Update crosshair visibility as the player zooms in/out.
	RunService.Heartbeat:Connect(function()
		if self._equipped then
			self._crosshair.Visible = self:_isFirstPerson()
		end
	end)
end

return MiningController
