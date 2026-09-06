--!strict
-- Drives the research zone: opens the ore panel from the dock button, keeps
-- its lines in step with the replicated attributes, sends a sale -- and
-- mines the blocks in the pit the panel's own bag fills from.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

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
local OreCatalog = require(fromShared("Domain/Research/OreCatalog"))
local Icons = require(fromShared("Icons"))
local State = require("../State")
local Theme = require("../UI/Theme")
local ResearchPanel = require("../UI/ResearchPanel")
local BuildController = require("./BuildController")

local COLORS = Theme.Colors
local SPACE = Theme.Space
local MAX_HIT_DISTANCE = 1000

-- How long one block takes to break under an unbroken hold.
local DIG_SECONDS = Balance.Research.DigDuration

-- The progress ring.
--
-- Circular and drawn AT the cursor rather than a bar along the bottom of
-- the screen: the eyes are already on the block being broken, and a bar
-- somewhere else makes the player look away from it to read how far along
-- the dig is. The ring sits where they are looking anyway.
--
-- One unbroken arc, drawn by the same rounded-corner renderer as every
-- other circle in the interface, so it stays smooth at any size. Cut into
-- separate segments it read as a chain, which is a texture, not a gauge.
local RING_DIAMETER = 52
local RING_THICKNESS = 5
local RING_FILL = Theme.Function.Research
-- Pale, not dark. The ring is drawn over whatever the player happens to be
-- aiming at -- dirt, ore, their own character in the way -- and a dark track
-- disappears against half of that. The black rim under it takes care of the
-- other half.
local RING_TRACK = COLORS.Light
-- The unfilled part stays visible, not invisible: the ring has to show how
-- much is LEFT, not only how much is done.
local RING_TRACK_TRANSPARENCY = 0.55
-- The black outer edge the rest of the interface wears, here as a wider ring
-- sitting under the other two.
local RING_RIM = 3
local RING_RIM_TRANSPARENCY = 0.35

-- Block highlight: a SelectionBox drawn around the block being dug.
-- SelectionBox respects depth testing, so it only shows on blocks the
-- player can actually see -- unlike Highlight which bleeds through.
local HIGHLIGHT_COLOR = Theme.Function.Research
local HIGHLIGHT_LINE_THICKNESS = 0.06
local HIGHLIGHT_SURFACE_TRANSPARENCY = 0.85

local ResearchController = {}

local function getCamera(): Camera
	return workspace.CurrentCamera
end

----------------------------------------------------------------------

function ResearchController:_buildToast(gui: ScreenGui)
	local icon = Theme.new("ImageLabel", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, SPACE.md, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundTransparency = 1,
		Image = Icons.Misc["Accept"],
	})
	local lbl = Theme.body({
		Position = UDim2.fromOffset(SPACE.md + 34, 0),
		Size = UDim2.new(1, -(SPACE.md + 42), 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
	local scale = Theme.new("UIScale", { Scale = 1 })

	self._toastIcon = icon
	self._toastLabel = lbl
	self._toastScale = scale
	self._toast = Theme.panel({
		Name = "ResearchToast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(SPACE.xl + 60 + SPACE.md + Theme.Control.md + SPACE.sm)),
		Size = UDim2.fromOffset(440, Theme.Control.md),
		Radius = Theme.Radius.md,
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	}, { icon, lbl, scale })
end

function ResearchController:_toastMessage(message: string, isError: boolean?)
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

function ResearchController:_blockAtMouse(mouseX: number, mouseY: number): BasePart?
	local player = Players.LocalPlayer
	local plots = workspace:FindFirstChild("Plots")
	local zone = plots and plots:FindFirstChild(`ResearchMine_{player.UserId}`, true)
	if not zone then
		return nil
	end
	local grid = zone:FindFirstChild("BlockGrid")
	if not grid then
		return nil
	end

	local camera = getCamera()
	local ray = camera:ScreenPointToRay(mouseX, mouseY)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { grid }

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_HIT_DISTANCE, params)
	if not result then
		return nil
	end

	local hit = result.Instance
	if not hit:IsA("BasePart") then
		return nil
	end

	local layer = hit:GetAttribute("Layer")
	if typeof(layer) ~= "number" then
		return nil
	end

	return hit :: BasePart
end

----------------------------------------------------------------------

local SWING_LIFT = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWING_STRIKE = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SWING_RECOVER = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWING_SECONDS = 0.1 + 0.09 + 0.22
-- One swing per swing, back to back, for as long as the button is down: a
-- shovel that strikes once and then waits out the other two seconds reads
-- as a bug, not as digging.
local SWING_INTERVAL = SWING_SECONDS

local SHOVEL_NAME = "Pelle"

local function digAnimation(): Animation?
	if not game then
		return nil
	end
	local folder = (game :: any):GetService("ReplicatedStorage"):FindFirstChild("ResearchModels")
	local animation = folder and folder:FindFirstChild("DigAnimation")
	if animation and animation:IsA("Animation") and animation.AnimationId ~= "" then
		return animation
	end
	return nil
end

function ResearchController:_playDigSwing()
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animation = digAnimation()
	if animation then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local track = self._digTrack
			if not track then
				track = animator:LoadAnimation(animation)
				track.Priority = Enum.AnimationPriority.Action
				self._digTrack = track
			end
			track:Play(0.05)
			return
		end
	end

	local tool = character:FindFirstChild(SHOVEL_NAME)
	if not (tool and tool:IsA("Tool")) then
		return
	end
	if self._swinging then
		return
	end
	self._swinging = true

	local rest = tool.Grip
	local function restore()
		tool.Grip = rest
		self._swinging = false
	end

	local lift = TweenService:Create(tool, SWING_LIFT, {
		Grip = rest * CFrame.Angles(math.rad(22), 0, 0),
	})
	local strike = TweenService:Create(tool, SWING_STRIKE, {
		Grip = rest * CFrame.Angles(math.rad(-50), 0, 0),
	})
	local recover = TweenService:Create(tool, SWING_RECOVER, { Grip = rest })

	lift.Completed:Connect(function()
		strike:Play()
	end)
	strike.Completed:Connect(function()
		recover:Play()
	end)
	recover.Completed:Connect(restore)
	lift:Play()

	task.delay(SWING_SECONDS + 0.2, function()
		if self._swinging then
			restore()
		end
	end)
end

----------------------------------------------------------------------
-- Hold to dig
--
-- Pressure, not clicks. The button goes down, the ring fills at the cursor
-- over DIG_SECONDS, and the block breaks when the ring closes. Letting go
-- -- or drifting onto another block -- throws the progress away and starts
-- the next one from zero. That is the Minecraft rule, and it is the one a
-- player arrives already knowing.

-- One circle of the ring: a frame with no body at all, its corners rounded
-- the whole way to a disc, wearing the stroke that IS the ring. Returns the
-- stroke, since that is the part anything else has to reach.
local function ringCircle(
	parent: Instance,
	position: UDim2,
	color: Color3,
	thickness: number,
	transparency: number,
	zIndex: number
): UIStroke
	local stroke = Theme.new("UIStroke", {
		Color = color,
		Thickness = thickness,
		Transparency = transparency,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
	Theme.new("Frame", {
		Name = "Circle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = UDim2.fromOffset(RING_DIAMETER, RING_DIAMETER),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
		Parent = parent,
	}, { Theme.new("UICorner", { CornerRadius = UDim.new(1, 0) }), stroke })
	return stroke
end

-- Half the sweep, and the half of the circle it is drawn on.
--
-- The gradient's hard edge runs through the centre of the circle, so it
-- keeps a half-PLANE of the ring -- turn the gradient and that half-plane
-- turns with it. The clip cuts what survives down to one side of the
-- circle, and a half-plane cut down to a half-circle is exactly an arc.
-- Two of those, one per side, cover the full turn between them.
local function ringSweep(root: Frame, isRight: boolean): UIGradient
	local clip = Theme.new("Frame", {
		Name = if isRight then "RightHalf" else "LeftHalf",
		AnchorPoint = Vector2.new(if isRight then 0 else 1, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 12,
		Parent = root,
	})

	-- Pushed back to the clip's inner edge, which is the ring's centre.
	local centre = UDim2.fromScale(if isRight then 0 else 1, 0.5)
	local stroke = ringCircle(clip, centre, RING_FILL, RING_THICKNESS, 0, 12)

	return Theme.new("UIGradient", {
		-- Two keypoints a thousandth apart rather than one: a NumberSequence
		-- cannot hold two at the same time value, and the sliver between
		-- them is the arc's leading edge, softened by a fraction of a pixel.
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.499, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Rotation = if isRight then -180 else 0,
		Parent = stroke,
	})
end

function ResearchController:_buildDigRing(gui: ScreenGui)
	local span = RING_DIAMETER + (RING_THICKNESS + RING_RIM) * 2 + SPACE.xs
	local root = Theme.new("Frame", {
		Name = "DigRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(span, span),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})

	local centre = UDim2.fromScale(0.5, 0.5)
	-- Rim, then track, then the sweep on top of both.
	ringCircle(root, centre, COLORS.Outline, RING_THICKNESS + RING_RIM * 2, RING_RIM_TRANSPARENCY, 10)
	ringCircle(root, centre, RING_TRACK, RING_THICKNESS, RING_TRACK_TRANSPARENCY, 11)

	self._digSweepRight = ringSweep(root, true)
	self._digSweepLeft = ringSweep(root, false)
	self._digRing = root

	-- Reusable SelectionBox, reparented to the current target block.
	local box = Instance.new("SelectionBox")
	box.Name = "DigHighlight"
	box.Color3 = HIGHLIGHT_COLOR
	box.LineThickness = HIGHLIGHT_LINE_THICKNESS
	box.SurfaceColor3 = HIGHLIGHT_COLOR
	box.SurfaceTransparency = HIGHLIGHT_SURFACE_TRANSPARENCY
	self._highlight = box
end

function ResearchController:_highlightBlock(block: BasePart?)
	local box = self._highlight
	if not box then
		return
	end
	if block then
		box.Adornee = block
		box.Parent = block
	else
		box.Adornee = nil
		box.Parent = nil
	end
end

function ResearchController:_showDigRing(mouseX: number, mouseY: number, ratio: number)
	local ring = self._digRing
	if not ring then
		return
	end
	ring.Position = UDim2.fromOffset(mouseX, mouseY)
	ring.Visible = true

	-- The sweep, clockwise from twelve o'clock. Each half is turned to it and
	-- clamped at its own end of the circle: the right half is already full at
	-- half a turn, and the left one shows nothing until the sweep reaches it.
	local sweep = math.clamp(ratio, 0, 1) * 360
	self._digSweepRight.Rotation = math.min(sweep, 180) - 180
	self._digSweepLeft.Rotation = math.max(sweep, 180) - 180
end

function ResearchController:_hideDigRing()
	local ring = self._digRing
	if not ring then
		return
	end
	ring.Visible = false
	self._digSweepRight.Rotation = -180
	self._digSweepLeft.Rotation = 0
end

function ResearchController:_beginDig()
	if self._digHolding then
		return
	end
	local character = Players.LocalPlayer.Character
	if not character or not character:FindFirstChild(SHOVEL_NAME) then
		return
	end
	self._digHolding = true

	-- A token, not just the flag: a release followed immediately by a press
	-- would otherwise leave the old loop running alongside the new one.
	self._digToken = (self._digToken or 0) + 1
	local token = self._digToken

	task.spawn(function()
		local mouse = Players.LocalPlayer:GetMouse()
		local target: BasePart? = nil
		local progress = 0
		local nextSwing = 0

		while self._digHolding and self._digToken == token do
			local delta = RunService.RenderStepped:Wait()
			-- Re-aimed every frame. A block that has left the world -- dug,
			-- or carried off by a mine regeneration -- simply stops being
			-- returned here, and reads the same as aiming at nothing.
			local block = self:_blockAtMouse(mouse.X, mouse.Y)
			if block ~= target then
				target = block
				progress = 0
				nextSwing = 0
				self:_hideDigRing()
				self:_highlightBlock(target)
			end
			if not target then
				continue
			end

			progress += delta
			if os.clock() >= nextSwing then
				self:_playDigSwing()
				nextSwing = os.clock() + SWING_INTERVAL
			end
			self:_showDigRing(mouse.X, mouse.Y, progress / DIG_SECONDS)

			if progress >= DIG_SECONDS then
				progress = 0
				self:_hideDigRing()
				self:_mine(target)
				-- Held through the break: the next block under the cursor is
				-- picked up on the next frame and started from zero.
				target = nil
			end
		end

		self:_hideDigRing()
		self:_highlightBlock(nil)
	end)
end

function ResearchController:_stopDig()
	self._digHolding = false
	self:_hideDigRing()
	self:_highlightBlock(nil)
end

----------------------------------------------------------------------

-- Break one block, once its hold is complete. The swing is not started here
-- any more -- the hold loop has had the shovel working the whole time.
function ResearchController:_mine(block: BasePart)
	local layer = block:GetAttribute("Layer") :: number
	local bx = block:GetAttribute("BlockX") :: number
	local by = block:GetAttribute("BlockY") :: number

	local ok, result = Net.DigBlock:InvokeServer(layer, bx, by)
	if ok then
		if result.oreId then
			self:_toastMessage(`+1 {result.oreName} ({result.newCount or "?"} au total)`, false)
		else
			self:_toastMessage("Terre", false)
		end
	else
		if result == "cooldown" then
			-- Silent
		else
			self:_toastMessage(tostring(result), true)
		end
	end
end

----------------------------------------------------------------------

function ResearchController:_buildSurfaceButton(gui: ScreenGui)
	local btn = Theme.new("TextButton", {
		Name = "SurfaceBtn",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -SPACE.xl, 0, SPACE.xl),
		Size = UDim2.fromOffset(200, 44),
		BackgroundColor3 = COLORS.Accent,
		Text = "",
		AutoButtonColor = true,
		Visible = false,
		ZIndex = 9,
		Parent = gui,
	})
	Theme.corner(Theme.Radius.md).Parent = btn
	Theme.stroke(Theme.darken(COLORS.Accent, 0.3), 2).Parent = btn

	local surfLbl = Theme.body({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.8),
		Text = "\u{2191} Remonter",
		TextColor3 = Color3.fromRGB(255, 255, 255),
	})
	surfLbl.Parent = btn

	self._surfaceBtn = btn

	btn.Activated:Connect(function()
		self:_teleportToSurface()
	end)
end

function ResearchController:_teleportToSurface()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	local plots = workspace:FindFirstChild("Plots")
	local zone = plots and plots:FindFirstChild(`ResearchMine_{player.UserId}`, true)
	if not zone then
		return
	end
	local pad = zone:FindFirstChild("SurfacePad")
	if not pad or not pad:IsA("BasePart") then
		return
	end

	local sx = pad:GetAttribute("SurfaceX")
	local sy = pad:GetAttribute("SurfaceY")
	local sz = pad:GetAttribute("SurfaceZ")
	if typeof(sx) == "number" and typeof(sy) == "number" and typeof(sz) == "number" then
		root.CFrame = CFrame.new(sx, sy, sz)
	end
end

function ResearchController:_updateSurfaceButton()
	local player = Players.LocalPlayer
	local character = player.Character
	if not character or not self._surfaceBtn then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		self._surfaceBtn.Visible = false
		return
	end

	local plots = workspace:FindFirstChild("Plots")
	local zone = plots and plots:FindFirstChild(`ResearchMine_{player.UserId}`, true)
	if not zone then
		self._surfaceBtn.Visible = false
		return
	end

	local pad = zone:FindFirstChild("SurfacePad")
	if not pad or not pad:IsA("BasePart") then
		self._surfaceBtn.Visible = false
		return
	end

	self._surfaceBtn.Visible = root.Position.Y < pad.Position.Y + 8
end

function ResearchController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ResearchUI"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 11
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = ResearchPanel.new(gui)
	self._panel = panel
	self:_buildToast(gui)
	self:_buildDigRing(gui)

	Players.LocalPlayer.CharacterAdded:Connect(function()
		self._digTrack = nil
		self._swinging = false
		self:_stopDig()
	end)

	panel.onSell = function(oreId: string?)
		Net.SellOres:InvokeServer(oreId)
	end

	local buildPanel = BuildController:Panel()
	if buildPanel then
		buildPanel.onResearchRequested = function()
			if buildPanel:IsOpen() then
				buildPanel:Close()
			end
			panel:Toggle()
		end
	end

	local function seed()
		panel:SetUnlocked(State.get("HasResearchMine") == true)
		for _, ore in OreCatalog.Ores do
			panel:SetOre(ore.id, (State.get(`Ore{ore.id}`) :: number?) or 0)
		end
	end
	seed()

	State.Changed:Connect(function(key: string, value: any)
		if key == "HasResearchMine" then
			panel:SetUnlocked(value == true)
		elseif key == "Location" then
			if value ~= "Station" then
				panel:Close()
			end
		elseif key:sub(1, 3) == "Ore" then
			local id = key:sub(4)
			if OreCatalog.get(id) then
				panel:SetOre(id, (value :: number?) or 0)
			end
		end
	end)

	self:_buildSurfaceButton(gui)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_beginDig()
		end
	end)

	-- The release is taken whatever the interface did with it: a button let
	-- go over an open panel still has to stop the dig it started.
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_stopDig()
		end
	end)

	task.spawn(function()
		while true do
			self:_updateSurfaceButton()
			task.wait(0.5)
		end
	end)
end

return ResearchController
