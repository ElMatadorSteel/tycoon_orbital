--!strict
-- The weapon selector: a hotbar of the tools the player actually carries.
--
-- It REPLACES Roblox's own backpack bar rather than sitting next to it. Two
-- reasons, and the first is not taste: with both on screen a player has two
-- places to equip from, and the grey one is the one their thumb already knows.
-- The second is that the default bar answers to nothing in this theme -- no
-- glass, no outline, no cooldown -- and a beautiful selector beside an ugly
-- one reads worse than either alone.
--
-- The catalogue is the BACKPACK, not a list written here. A tool in the
-- Character is the equipped one; a tool in the Backpack is a slot. That is
-- Roblox's own model, so the bar is correct for any tool the game ever adds
-- without this file being touched.
--
-- Today the game ships exactly one weapon, the Railgun. A one-slot hotbar is
-- not a failure of the design: it is the design, at n = 1.
--
-- This module only displays and equips. It knows nothing about mining, asks
-- the server for nothing, and is told when to run a cooldown.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Theme = require("./Theme")

local SPACE = Theme.Space

-- Nine slots is where every hotbar stops, because that is where the number row
-- stops. A tenth tool would simply have no key.
local KEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
}

local WeaponSelector = {}
WeaponSelector.__index = WeaponSelector

export type WeaponSelector = typeof(setmetatable({} :: any, WeaponSelector))

----------------------------------------------------------------------

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

----------------------------------------------------------------------

function WeaponSelector.new(parent: ScreenGui, config: { [string]: any }?): WeaponSelector
	local self = setmetatable({}, WeaponSelector)
	local options = config or {}

	self._player = Players.LocalPlayer
	self._fallbackImage = options.FallbackImage
	self._cooldown = options.Cooldown or 0
	self._cooldownLeft = 0
	self._slots = {} :: { [Tool]: any }
	self._order = {} :: { Tool }

	-- Roblox's bar goes away the moment ours exists. Wrapped, because
	-- SetCoreGuiEnabled throws while the CoreGui is still coming up.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	self._root = Theme.new("Frame", {
		Name = "WeaponSelector",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -SPACE.xl),
		Size = UDim2.fromOffset(0, Theme.Hotbar.Slot),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	}, {
		Theme.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, SPACE.sm),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})

	self:_bindPlayer()
	self:_bindKeys()

	-- One clock for the whole bar rather than one per slot: the cooldown is a
	-- property of the weapon, and there is only ever one running.
	RunService.Heartbeat:Connect(function(delta: number)
		self:_tickCooldown(delta)
	end)

	return self
end

----------------------------------------------------------------------
-- Where the tools are

-- Rebuilds are DEFERRED. Equipping moves a tool out of the Backpack and into
-- the Character, which fires a removal and an addition back to back: rebuilding
-- on each would tear the bar down and stand it up again mid-equip.
function WeaponSelector:_scheduleRefresh()
	if self._refreshQueued then
		return
	end
	self._refreshQueued = true
	task.defer(function()
		self._refreshQueued = false
		self:_refresh()
	end)
end

function WeaponSelector:_watch(container: Instance)
	container.ChildAdded:Connect(function()
		self:_scheduleRefresh()
	end)
	container.ChildRemoved:Connect(function()
		self:_scheduleRefresh()
	end)
end

-- Binds whatever Backpack the player currently has, and only once per instance.
--
-- This is not defensive padding: Roblox REPLACES the Backpack when the
-- character first loads, so a connection made to the one present at startup
-- dies with it and the bar never notices a tool again. Measured, not guessed --
-- the selector sat empty with two tools in the player's inventory.
function WeaponSelector:_bindBackpack()
	local backpack = self._player:FindFirstChildOfClass("Backpack")
	if backpack ~= self._backpack then
		self._backpack = backpack
		if backpack then
			self:_watch(backpack)
		end
	end
	self:_scheduleRefresh()
end

function WeaponSelector:_bindPlayer()
	-- The player is watched rather than the Backpack, because the Backpack is
	-- the thing that gets swapped out from under us.
	self._player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			self:_bindBackpack()
		end
	end)

	local function onCharacter(character: Model)
		self:_watch(character)
		self:_bindBackpack()
	end
	if self._player.Character then
		onCharacter(self._player.Character)
	end
	self._player.CharacterAdded:Connect(onCharacter)

	self:_bindBackpack()
end

-- Every tool the player carries, equipped or not, in a STABLE order.
--
-- Sorted by name rather than by discovery: a bar whose slots swap places when
-- you equip one is a bar whose number keys mean something different every time.
function WeaponSelector:_tools(): ({ Tool }, Tool?)
	local tools: { Tool } = {}
	local equipped: Tool? = nil

	local backpack = self._player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in backpack:GetChildren() do
			if child:IsA("Tool") then
				table.insert(tools, child)
			end
		end
	end

	local character = self._player.Character
	if character then
		for _, child in character:GetChildren() do
			if child:IsA("Tool") then
				table.insert(tools, child)
				equipped = child
			end
		end
	end

	table.sort(tools, function(a: Tool, b: Tool)
		return a.Name < b.Name
	end)
	return tools, equipped
end

----------------------------------------------------------------------
-- Building the slots

function WeaponSelector:_refresh()
	local tools, equipped = self:_tools()

	-- Slots are rebuilt only when the SET of tools changed. Equipping does not
	-- change that set, and a rebuild there would throw away the tile the player
	-- just clicked -- along with its press animation.
	local changed = #tools ~= #self._order
	if not changed then
		for index, tool in tools do
			if self._order[index] ~= tool then
				changed = true
				break
			end
		end
	end

	if changed then
		for _, slot in self._slots do
			slot.Root:Destroy()
		end
		self._slots = {}
		self._order = tools

		for index, tool in tools do
			local slot = Theme.weaponSlot({
				Name = tool.Name,
				LayoutOrder = index,
				Caption = tool.Name,
				Key = if index <= #KEYS then index else nil,
				Image = if tool.TextureId ~= "" then tool.TextureId else self._fallbackImage,
			})
			slot.Root.Parent = self._root
			self._slots[tool] = slot

			slot.Button.Face.Activated:Connect(function()
				self:_toggle(tool)
			end)
		end
	end

	self._root.Visible = #tools > 0
	for tool, slot in self._slots do
		slot:SetEquipped(tool == equipped)
	end
end

----------------------------------------------------------------------
-- Equipping

function WeaponSelector:_toggle(tool: Tool)
	local humanoid = humanoidOf(self._player)
	if not humanoid then
		return
	end
	-- A tool parented to the Character is the equipped one, so clicking the
	-- slot that is already lit puts it away. Same gesture both directions.
	if tool.Parent == self._player.Character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end
	self:_scheduleRefresh()
end

function WeaponSelector:_bindKeys()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed is true when a text box or the chat took the key: a
		-- player typing "1" is not asking to equip anything.
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		for index, key in KEYS do
			if input.KeyCode == key then
				local tool = self._order[index]
				if tool then
					self:_toggle(tool)
				end
				return
			end
		end
	end)
end

----------------------------------------------------------------------
-- Cooldown
--
-- Counted CLIENT-SIDE, from the moment a shot is accepted. The server remains
-- the only judge of whether the next one is allowed -- this is a read-out of
-- its rule, exactly like the eclipse countdown in HudController, and it is
-- allowed to be a frame or two optimistic because nothing depends on it.

function WeaponSelector:BeginCooldown(seconds: number?)
	local total = seconds or self._cooldown
	if total <= 0 then
		return
	end
	self._cooldown = total
	self._cooldownLeft = total
	self:_paintCooldown()
end

function WeaponSelector:_tickCooldown(delta: number)
	if self._cooldownLeft <= 0 then
		return
	end
	self._cooldownLeft = math.max(0, self._cooldownLeft - delta)
	self:_paintCooldown()
end

function WeaponSelector:_paintCooldown()
	for _, slot in self._slots do
		slot:SetCooldown(self._cooldownLeft, self._cooldown)
	end
end

return WeaponSelector
