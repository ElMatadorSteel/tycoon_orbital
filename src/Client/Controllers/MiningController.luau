--!strict
-- The Railgun mining side-feature: buying it at the lobby pad, receiving it
-- from the dispenser, and firing it at asteroids near your own station.
--
-- Free-aim, screen-center raycast: the client only ever CLAIMS which
-- asteroid id it hit (Net.FireRailgun:InvokeServer(asteroidId)) -- the
-- server is sole judge of whether that claim pays out (see
-- Application/UseCases/FireRailgun's own header for why re-simulating the
-- camera geometry server-side isn't needed for that to be safe).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

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

local Net = require(fromShared("Net"))
local Icons = require(fromShared("Icons"))
local Theme = require("../UI/Theme")

local COLORS = Theme.Colors
local SPACE = Theme.Space

local MAX_HIT_DISTANCE = 1000

local MiningController = {}

MiningController._equippedTool = nil :: Tool?

local function getCamera(): Camera
	return workspace.CurrentCamera
end

----------------------------------------------------------------------
-- Ephemeral toast -- same visual language as BuildPanel's own (icon +
-- label in a Theme.panel), rebuilt small and standalone here rather than
-- reaching into BuildController's private panel instance: too small a
-- piece to justify cross-controller coupling.

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
		Position = UDim2.new(0.5, 0, 1, -(SPACE.xl + 60 + SPACE.md)),
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
-- Crosshair -- visible only while the Railgun is the equipped tool.

function MiningController:_buildCrosshair(gui: ScreenGui)
	self._crosshair = Theme.new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(24, 24),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
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
	self._crosshair.Visible = equipped
end

----------------------------------------------------------------------
-- Firing

function MiningController:_hoveredAsteroidId(): string?
	local player = Players.LocalPlayer
	local asteroidsRoot = workspace:FindFirstChild("Asteroids")
	local folder = asteroidsRoot and asteroidsRoot:FindFirstChild(`Asteroids_{player.UserId}`)
	if not folder then
		return nil
	end

	local camera = getCamera()
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder }

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_HIT_DISTANCE, params)
	if not result then
		return nil
	end

	local model = result.Instance:FindFirstAncestorWhichIsA("Model")
	if not model or model.Parent ~= folder then
		return nil
	end

	local asteroidId = model:GetAttribute("AsteroidId")
	return if typeof(asteroidId) == "string" then asteroidId else nil
end

function MiningController:_fire()
	local asteroidId = self:_hoveredAsteroidId()
	if not asteroidId then
		return -- nothing under the crosshair -- no network call, no cooldown spent
	end

	local ok, result = Net.FireRailgun:InvokeServer(asteroidId)
	if ok then
		self:_toastMessage(`+{result.reward} cr ({result.tier})`, false)
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
-- The purchase pad -- client-initiated (not server-Triggered like
-- LaunchPad): a purchase can fail (insufficient funds, already owned), and
-- only the client can show a toast for that, the same way every other
-- action in this game already works.

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
	gui.Parent = player:WaitForChild("PlayerGui")

	self:_buildCrosshair(gui)
	self:_buildToast(gui)

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
end

return MiningController
