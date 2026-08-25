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
local Theme = require("../UI/Theme")

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

	-- "Body" is the base plate, both for a real catalogue model and for the
	-- fallback box. Any part is accepted otherwise: a hand-edited model may
	-- have had it renamed.
	local body = model:FindFirstChild("Body") or model:FindFirstChildWhichIsA("BasePart")
	if not body or not body:IsA("BasePart") then
		return
	end

	-- The label sits above the model's real TOP, not above its base: a
	-- smelter's chimney rises well past its catalogue height.
	local center, size = model:GetBoundingBox()
	local offsetY = (center.Position.Y + size.Y / 2) - body.Position.Y + Theme.Label.Clearance

	local label = Theme.worldLabel(body, definition.name, offsetY)
	label.Parent = model

	-- The level lives in a model attribute. Following its changes instead
	-- of rebuilding the label means an upgrade doesn't make the name flash.
	local text = label:FindFirstChild("Text")
	if not text or not text:IsA("TextLabel") then
		return
	end

	local function refresh()
		local level = model:GetAttribute("Level")
		local rank = if typeof(level) == "number" then math.floor(level) else 1
		text.Text = `{definition.name}  Nv.{rank}`
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
