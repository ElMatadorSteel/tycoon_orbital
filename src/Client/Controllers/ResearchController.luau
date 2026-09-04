--!strict
-- Drives the research zone: opens the ore panel from the dock button, keeps
-- its lines in step with the replicated attributes, sends a sale -- and
-- mines the blocks in the pit the panel's own bag fills from.
--
-- The panel button lives in BuildPanel's left dock, beside Lobby and
-- Renaissance, because that dock is the home of every control that takes
-- you OUT of the build loop -- see the note there. It is reached through
-- BuildController:Panel() rather than rebuilt here: two docks on the same
-- screen edge would overlap, and the one that already exists is the one the
-- player knows.
--
-- Mining a block needs no equipped Tool, unlike the Railgun: a block is a
-- fixed fixture a player walks up to and clicks, not a moving target aimed
-- at from across a station. A plain click, filtered to the player's OWN
-- research-mine BlockGrid folder, is enough -- a stray click anywhere else
-- simply hits nothing and no-ops. The client only ever CLAIMS which block
-- it hit (Net.DigBlock:InvokeServer(layer, x, y)) -- the server is sole
-- judge of whether that claim pays out (see Application/UseCases/DigBlock).

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Client and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach. Lune has no `game`, so the
-- fallback below -- an ordinary relative require -- is what runs there.
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
local OreCatalog = require(fromShared("Domain/Research/OreCatalog"))
local Icons = require(fromShared("Icons"))
local State = require("../State")
local Theme = require("../UI/Theme")
local ResearchPanel = require("../UI/ResearchPanel")
local BuildController = require("./BuildController")

local COLORS = Theme.Colors
local SPACE = Theme.Space
local MAX_HIT_DISTANCE = 1000

local ResearchController = {}

local function getCamera(): Camera
	return workspace.CurrentCamera
end

----------------------------------------------------------------------
-- Ephemeral toast for a mined hit

function ResearchController:_buildToast(gui: ScreenGui)
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
		Name = "ResearchToast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(SPACE.xl + 60 + SPACE.md + Theme.Control.md + SPACE.sm)),
		Size = UDim2.fromOffset(440, Theme.Control.md),
		Radius = Theme.Radius.md,
		Visible = false,
		ZIndex = 8,
		Parent = gui,
	}, { icon, label, scale })
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
-- Mining: raycast to find which block the player is looking at

-- Returns the block Part if the crosshair is over a mineable block in the
-- player's own mine, or nil otherwise. The block carries Layer, BlockX,
-- BlockY attributes stamped by ResearchMineBuilder.buildBlockGrid.
function ResearchController:_hoveredBlock(): BasePart?
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
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)

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

	-- Must have block attributes
	local layer = hit:GetAttribute("Layer")
	if typeof(layer) ~= "number" then
		return nil
	end

	return hit :: BasePart
end

----------------------------------------------------------------------
-- The dig swing

local SWING_LIFT = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWING_STRIKE = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local SWING_RECOVER = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SWING_SECONDS = 0.1 + 0.09 + 0.22

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

function ResearchController:_mine()
	local block = self:_hoveredBlock()
	if not block then
		return
	end

	local layer = block:GetAttribute("Layer") :: number
	local bx = block:GetAttribute("BlockX") :: number
	local by = block:GetAttribute("BlockY") :: number

	self:_playDigSwing()

	local ok, result = Net.DigBlock:InvokeServer(layer, bx, by)
	if ok then
		if result.oreId then
			self:_toastMessage(`+1 {result.oreName} ({result.newCount or "?"} au total)`, false)
		else
			self:_toastMessage("Terre", false)
		end
	else
		if result == "cooldown" then
			-- Silent: no toast for normal cooldown
		else
			self:_toastMessage(tostring(result), true)
		end
	end
end

----------------------------------------------------------------------
-- Surface teleport: the ProximityPrompt on the SurfacePad teleports
-- the player back to the gangway entrance.

function ResearchController:_setupSurfaceTeleport()
	local player = Players.LocalPlayer

	-- The pad is built when the mine is built, which can happen after this
	-- controller starts. Poll for it.
	task.spawn(function()
		while true do
			local plots = workspace:FindFirstChild("Plots")
			local zone = plots and plots:FindFirstChild(`ResearchMine_{player.UserId}`, true)
			if zone then
				local pad = zone:FindFirstChild("SurfacePad")
				if pad and pad:IsA("BasePart") then
					local prompt = pad:FindFirstChildOfClass("ProximityPrompt")
					if prompt then
						prompt.Triggered:Connect(function()
							local character = player.Character
							if not character then
								return
							end
							local root = character:FindFirstChild("HumanoidRootPart")
							if not root or not root:IsA("BasePart") then
								return
							end
							local sx = pad:GetAttribute("SurfaceX")
							local sy = pad:GetAttribute("SurfaceY")
							local sz = pad:GetAttribute("SurfaceZ")
							if typeof(sx) == "number" and typeof(sy) == "number" and typeof(sz) == "number" then
								root.CFrame = CFrame.new(sx, sy, sz)
							end
						end)
						return -- done
					end
				end
			end
			task.wait(2)
		end
	end)
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

	Players.LocalPlayer.CharacterAdded:Connect(function()
		self._digTrack = nil
		self._swinging = false
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

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_mine()
		end
	end)

	self:_setupSurfaceTeleport()
end

return ResearchController
