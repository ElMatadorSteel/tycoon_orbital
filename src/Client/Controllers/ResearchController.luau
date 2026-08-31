--!strict
-- Drives the research zone: opens the ore panel from the dock button, keeps
-- its lines in step with the replicated attributes, sends a sale -- and
-- mines the veins in the pit the panel's own bag fills from.
--
-- The panel button lives in BuildPanel's left dock, beside Lobby and
-- Renaissance, because that dock is the home of every control that takes
-- you OUT of the build loop -- see the note there. It is reached through
-- BuildController:Panel() rather than rebuilt here: two docks on the same
-- screen edge would overlap, and the one that already exists is the one the
-- player knows.
--
-- Mining a vein needs no equipped Tool, unlike the Railgun: a vein is a
-- fixed fixture a player walks up to and clicks, not a moving target aimed
-- at from across a station. A plain click, filtered to the player's OWN
-- research-mine folder, is enough -- a stray click anywhere else in the game
-- simply hits nothing there and no-ops, the same way BuildController's
-- demolish-click only ever does something when a real module is under it.
-- The client only ever CLAIMS which vein id it hit
-- (Net.MineVein:InvokeServer(veinId)) -- the server is sole judge of
-- whether that claim pays out (see Application/UseCases/MineVein's own
-- header).

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
-- Ephemeral toast for a mined hit -- same visual language as
-- MiningController's own. The panel needs none of its own: a sale's result
-- is the bag emptying, which the panel already shows live off the
-- replicated attributes. A vein's result is a count going up somewhere the
-- player usually is NOT looking (the panel), so a hit still gets a toast.

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
		-- Stacked just above MiningController's own toast band, so the two
		-- side features never draw on top of each other if both ever fire
		-- close together.
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
-- Mining

-- Recursive: the zone (uniquely named ResearchMine_<userId> by
-- StationSceneBuilder) sits nested inside the anonymous Plot_<slotIndex>
-- structure, not as a direct child of workspace.Plots, and veins live
-- several layers inside THAT -- a plain FindFirstChild would only ever look
-- at one level.
function ResearchController:_hoveredVeinId(): string?
	local player = Players.LocalPlayer
	local plots = workspace:FindFirstChild("Plots")
	local zone = plots and plots:FindFirstChild(`ResearchMine_{player.UserId}`, true)
	if not zone then
		return nil
	end

	local camera = getCamera()
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { zone }

	local result = workspace:Raycast(ray.Origin, ray.Direction * MAX_HIT_DISTANCE, params)
	if not result then
		return nil
	end

	local cluster = result.Instance:FindFirstAncestorWhichIsA("Model")
	if not cluster then
		return nil
	end

	local veinId = cluster:GetAttribute("VeinId")
	return if typeof(veinId) == "string" then veinId else nil
end

function ResearchController:_mine()
	local veinId = self:_hoveredVeinId()
	if not veinId then
		return -- nothing under the cursor -- no network call, no cooldown spent
	end

	local ok, result = Net.MineVein:InvokeServer(veinId)
	if ok then
		self:_toastMessage(`+1 {result.oreName} ({result.count} au total)`, false)
	else
		self:_toastMessage(tostring(result), true)
	end
end

function ResearchController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ResearchUI"
	gui.ResetOnSpawn = false
	-- Same rule as the others: leave the Roblox topbar alone.
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Above the build window (10), because it opens from a button that window
	-- owns: opening it behind its own trigger reads as a dead button.
	gui.DisplayOrder = 11
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = ResearchPanel.new(gui)
	self._panel = panel
	self:_buildToast(gui)

	panel.onSell = function(oreId: string?)
		-- No optimistic update. The counts on screen come from the attributes
		-- the server publishes, so the row empties when the sale actually
		-- landed -- a local decrement would show a sale that failed.
		Net.SellOres:InvokeServer(oreId)
	end

	local buildPanel = BuildController:Panel()
	if buildPanel then
		buildPanel.onResearchRequested = function()
			-- Closing the build window first: both are modal and centred, and
			-- stacked they read as one broken window.
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
			-- The dock the button sits in is hidden in the lobby, so a window
			-- left open there could not be closed from its own trigger.
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

	-- Known accepted rough edge, same one MiningController's own header
	-- already flags for the Railgun: this InputBegan connection and
	-- BuildController's own MouseButton1 handling are independent event
	-- paths with no cross-controller coordination, so a click while both a
	-- build tool is selected AND a vein happens to be under the cursor
	-- fires both. Not reachable in practice -- the build grid and the pit
	-- floor are never on screen at the same time -- so flagged here rather
	-- than solved.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed is true when the click was consumed by the
		-- interface (the research panel, a menu button, ...): without this
		-- check, closing a window with a click could also try to mine
		-- whatever happened to be behind it.
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			self:_mine()
		end
	end)
end

return ResearchController
