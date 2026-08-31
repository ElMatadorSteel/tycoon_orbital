--!strict
-- The teleport aura: the disc of light that flares under a player the moment
-- they materialise at their station, and fades a few seconds later.
--
-- Entirely CLIENT-side, per ARCHITECTURE.md's "Comfort is client, authority is
-- server". Nothing here grants, spends or moves anything, so there is nothing
-- for the server to revalidate. The trade-off is deliberate and worth knowing:
-- only the arriving player sees their own aura. Showing it to onlookers would
-- mean a new port and an adapter cloning into Workspace on the server, for an
-- effect that plays on a plot its owner is usually alone on.
--
-- The trigger is the replicated Location attribute, not a remote event: state
-- reaches the client through attributes (ARCHITECTURE.md).
--
-- The aura is welded to the character rather than anchored at the arrival
-- point. Welding is what makes the ordering inside EmbarkStation harmless: the
-- character can be pivoted after the aura exists and the aura simply goes with
-- it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- fromShared(path) reaches ReplicatedStorage.Shared directly: Rojo maps
-- src/Client and src/Shared to different service roots with no common
-- ancestor a relative "../.." path can reach.
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
local Icons = require(fromShared("Icons"))
local State = require("../State")

local RULES = Balance.Vfx.TeleportAura
local UPGRADE = Balance.Vfx.Upgrade
local MAX_LEVEL = Balance.Upgrade.MaxLevel
local TEMPLATE_NAME = "effet_tp_vfx"

local function colourOf(triple: { R: number, G: number, B: number }): Color3
	return Color3.fromRGB(triple.R, triple.G, triple.B)
end

local player = Players.LocalPlayer

local EffectsController = {}

local activeAura: BasePart? = nil
-- Bumped every time an aura starts or stops. A delayed step compares the token
-- it captured against this one, so a second teleport during the fade cannot
-- have its predecessor's timer tear down the new aura.
local generation = 0

local function setEmitting(aura: BasePart, on: boolean)
	for _, descendant in aura:GetDescendants() do
		if
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
		then
			descendant.Enabled = on
		end
	end
end

local function fadeLights(aura: BasePart, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, descendant in aura:GetDescendants() do
		if descendant:IsA("Light") then
			TweenService:Create(descendant, info, { Brightness = 0 }):Play()
		end
	end
end

local function clear()
	generation += 1
	if activeAura then
		activeAura:Destroy()
		activeAura = nil
	end
end

local function play(template: BasePart, container: Instance)
	local character = player.Character
	if not character then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	clear()
	local token = generation

	local aura = template:Clone()
	aura.Anchored = false
	aura.CanCollide = false
	aura.CanTouch = false
	aura.CanQuery = false
	aura.Massless = true

	-- The template's own rotation is what lays the disc flat. Reusing it beats
	-- hardcoding the quarter-turn it happens to be: re-authoring the effect in
	-- Studio then cannot silently stand it on its edge.
	aura.CFrame = CFrame.new(root.Position - Vector3.new(0, RULES.Offset, 0))
		* template.CFrame.Rotation

	-- Parented beside the character, not inside it: a stray part in a character
	-- model is one more thing every "walk the character" loop has to skip.
	aura.Parent = container

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = aura
	weld.Parent = aura

	activeAura = aura
	setEmitting(aura, true)

	task.delay(RULES.Hold, function()
		if token ~= generation then
			return
		end
		setEmitting(aura, false)
		fadeLights(aura, RULES.Fade)

		task.delay(RULES.Linger, function()
			if token ~= generation then
				return
			end
			clear()
		end)
	end)
end

----------------------------------------------------------------------
-- The upgrade burst
--
-- Client-side, on the same grounds as the teleport aura: it grants nothing and
-- moves nothing, so the server has nothing to revalidate. Unlike the aura this
-- one IS worth seeing on someone else's module, but it fires off the replicated
-- Level attribute, so every client watching that module runs it independently
-- and they all see it -- no port, no remote.

local function sparkAt(container: Instance, pivot: CFrame, reachedMax: boolean)
	local holder = Instance.new("Part")
	holder.Name = "UpgradeSpark"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = pivot * CFrame.new(0, UPGRADE.Height, 0)
	holder.Parent = container

	local attachment = Instance.new("Attachment")
	attachment.Parent = holder

	local colour = colourOf(if reachedMax then UPGRADE.AuraColor else UPGRADE.SparkColor)

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = Icons.Stars["Star"]
	emitter.Color = ColorSequence.new(colour)
	emitter.Lifetime = NumberRange.new(UPGRADE.SparkLifetime * 0.6, UPGRADE.SparkLifetime)
	emitter.Speed = NumberRange.new(UPGRADE.SparkSpeed * 0.4, UPGRADE.SparkSpeed)
	emitter.SpreadAngle = Vector2.new(UPGRADE.SparkSpread, UPGRADE.SparkSpread)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.LightEmission = 1
	emitter.Drag = 3
	-- Shrinking to nothing rather than cutting out: a spark that vanishes at
	-- full size reads as a dropped frame.
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.2, UPGRADE.SparkSize),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	-- A one-shot burst, not a running emitter.
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(UPGRADE.SparkCount)

	-- Destroyed a full lifetime later, so the sparks already in flight finish
	-- rather than blinking out mid-air.
	task.delay(UPGRADE.Linger, function()
		holder:Destroy()
	end)
end

local function watchModule(model: Instance, container: Instance)
	if not model:IsA("Model") then
		return
	end

	local previous = model:GetAttribute("Level")

	model:GetAttributeChangedSignal("Level"):Connect(function()
		local level = model:GetAttribute("Level")
		-- Only on a rise. The attribute is also written when a station is
		-- replayed from a save, and a plot that fireworks on every join would
		-- make the real upgrade worth nothing.
		if typeof(level) == "number" and typeof(previous) == "number" and level > previous then
			sparkAt(container, model:GetPivot(), level >= MAX_LEVEL)
		end
		previous = level
	end)
end

local function watchStation(station: Instance, container: Instance)
	for _, child in station:GetChildren() do
		watchModule(child, container)
	end
	station.ChildAdded:Connect(function(child)
		watchModule(child, container)
	end)
end

function EffectsController:Start()
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local template = assets:WaitForChild(TEMPLATE_NAME)
	if not template:IsA("BasePart") then
		-- A contract violation, not a business failure: the effect was authored
		-- wrong, and failing silently here would leave a teleport looking broken
		-- with nothing in the output to say why.
		error(
			`ReplicatedStorage.Assets.{TEMPLATE_NAME} must be a BasePart, got {template.ClassName}`
		)
	end

	local container = workspace:WaitForChild("Effects")

	-- 1. Arriving at the station from the lobby.
	State.Changed:Connect(function(key: string, value: any)
		if key ~= "Location" then
			return
		end
		if value ~= "Station" then
			clear()
			return
		end
		task.delay(RULES.ArrivalDelay, function()
			-- Re-read rather than trust the captured value: a player who bounced
			-- straight back to the lobby should not get an aura there.
			if State.get("Location") == "Station" then
				play(template :: BasePart, container)
			end
		end)
	end)

	-- 2. Respawning while already based at the station. The server has set
	-- RespawnLocation to the plot's spawn by then, so the character materialises
	-- at the base and the aura belongs there too -- no arrival delay, nothing
	-- moves the character afterwards.
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("HumanoidRootPart")
		if State.get("Location") == "Station" then
			play(template :: BasePart, container)
		end
	end)

	player.CharacterRemoving:Connect(clear)

	-- 3. Modules gaining a level, on any station -- one folder per player, one
	-- model per module inside it, both levels watched as they appear.
	local stations = workspace:WaitForChild("Stations")
	for _, station in stations:GetChildren() do
		watchStation(station, container)
	end
	stations.ChildAdded:Connect(function(station)
		watchStation(station, container)
	end)
end

return EffectsController
