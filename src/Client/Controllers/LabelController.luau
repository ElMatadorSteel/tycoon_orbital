--!strict
-- Each module's name, floating above it. Without this, a dense station is
-- just a pile of shapes: you can no longer tell the collector from the
-- smelter.
--
-- Entirely CLIENT-side. A label is pure presentation: the server has no
-- business building text, let alone hardcoding a font or a color -- it all
-- comes from UI/Theme.
--
-- The server stamps every model with a ModuleId attribute. The instance's
-- name is never parsed for it: it already carries the coordinates.

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

local ModuleCatalog = require(fromShared("Domain/Station/ModuleCatalog"))
local Balance = require(fromShared("Balance"))
local Theme = require("../UI/Theme")

-- Read straight from the configuration rather than replicated from the server:
-- these are constants, identical for every player, and a price the client works
-- out itself is a price the server never has to send. The server still decides
-- what an upgrade actually costs when one is bought -- this is a read-out, not
-- an authority.
local UPGRADE_RULES = {
	maxLevel = Balance.Upgrade.MaxLevel,
	gainPerLevel = Balance.Upgrade.GainPerLevel,
	costFactor = Balance.Upgrade.CostFactor,
	minCost = Balance.Upgrade.MinCost,
}

local LabelController = {}

local function attach(model: Instance)
	if not model:IsA("Model") or model:FindFirstChild("Label") then
		return
	end

	local id = model:GetAttribute("ModuleId")
	if typeof(id) ~= "string" then
		return
	end
	local definition = ModuleCatalog.get(id)
	if not definition then
		return
	end

	-- An invisible anchor placed exactly at the model's true horizontal
	-- centre and real top (masts, chimneys, domes included), rather than
	-- adorning to "whichever BasePart happens to be found first" (the old
	-- "Body" or FindFirstChildWhichIsA("BasePart") lookup). Roblox does not
	-- guarantee GetChildren() preserves the SERVER's build order once a
	-- whole subtree replicates in one burst -- and a placed module is built
	-- complete (40-90+ parts, per ModuleGeometry) before ever being
	-- parented, so it always replicates as exactly that kind of burst. The
	-- old lookup was landing on whichever part happened to deserialize
	-- first -- a corner bolt, a leg, a mast -- and the label floated over
	-- THAT part's position instead of the model's centre: exactly the
	-- "sometimes below, sometimes beside" symptom. A dedicated anchor at a
	-- computed position is deterministic regardless of child order.
	local center, size = model:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(center.Position.X, center.Position.Y + size.Y / 2, center.Position.Z)
	anchor.Parent = model

	local label = Theme.worldLabel(anchor, Theme.Label.Clearance)
	label.Parent = model

	-- The level lives in a model attribute. Following its changes instead
	-- of rebuilding the label means an upgrade doesn't make the name flash.
	local row = label:FindFirstChild("Row")
	local text = row and row:FindFirstChild("Text")
	local upgradeIcon = row and row:FindFirstChild("UpgradeIcon")
	local costIcon = row and row:FindFirstChild("CostIcon")
	local costText = row and row:FindFirstChild("UpgradeCost")
	if
		not (text and text:IsA("TextLabel"))
		or not (upgradeIcon and upgradeIcon:IsA("ImageLabel"))
		or not (costIcon and costIcon:IsA("ImageLabel"))
		or not (costText and costText:IsA("TextLabel"))
	then
		return
	end

	-- A corridor or a conduit would stay identical after an upgrade, so the
	-- catalogue says they have no levels -- and a price on them would lie.
	local upgradable = ModuleCatalog.isUpgradable(definition)

	local function refresh()
		local level = model:GetAttribute("Level")
		local rank = if typeof(level) == "number" then math.floor(level) else 1
		text.Text = Theme.Words.ModuleLabel(definition.name, rank)

		if not upgradable then
			upgradeIcon.Visible = false
			costIcon.Visible = false
			costText.Visible = false
			return
		end

		upgradeIcon.Visible = true
		costText.Visible = true

		if rank >= UPGRADE_RULES.maxLevel then
			-- No price at the ceiling: a number there reads as "buyable".
			costIcon.Visible = false
			costText.Text = Theme.Words.UpgradeMaxed
			costText.TextColor3 = Theme.Function.Info
		else
			costIcon.Visible = true
			costText.Text =
				Theme.Words.UpgradeCost(ModuleCatalog.upgradeCost(definition, rank, UPGRADE_RULES))
			costText.TextColor3 = Theme.Function.Money
		end
	end

	refresh()
	model:GetAttributeChangedSignal("Level"):Connect(refresh)
end

local function watchStation(station: Instance)
	for _, child in station:GetChildren() do
		attach(child)
	end
	station.ChildAdded:Connect(attach)
end

function LabelController:Start()
	local stations = workspace:WaitForChild("Stations")

	-- One folder per player, one model per module inside it. Both levels
	-- are watched: stations appear on embark, modules as they're built.
	for _, station in stations:GetChildren() do
		watchStation(station)
	end
	stations.ChildAdded:Connect(watchStation)
end

return LabelController
