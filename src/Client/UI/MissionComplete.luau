--!strict
-- The end-of-chain screen. It only ever shows once in a profile's lifetime:
-- that's what gives it its weight, so it's allowed to take over the whole
-- screen for a second.
--
-- No button: it closes itself. A player who just succeeded shouldn't have
-- to click to get control back.

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

local Objectives = require(fromShared("Domain/Objectives/Objectives"))
local Theme = require("./Theme")

local COLORS = Theme.Colors
local SPACE = Theme.Space

local PANEL = Vector2.new(520, 240)
local HOLD = 4.5 -- seconds on screen before it fades
local SPARKS = 14

local MissionComplete = {}

-- A burst of sparks radiating from the center. The only place in the game
-- that allows itself this: anywhere else, an animation that grabs the eye
-- without carrying information is just noise.
local function burst(parent: GuiObject)
	for index = 1, SPARKS do
		local angle = (index / SPARKS) * math.pi * 2
		local palette = { COLORS.Credit, COLORS.Accent, COLORS.Valid, Theme.Function.Money }
		local spark = Theme.new("Frame", {
			Name = "Spark",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(10, 10),
			Rotation = math.deg(angle),
			BackgroundColor3 = palette[(index - 1) % #palette + 1],
			Parent = parent,
		}, { Theme.corner(3) })

		local distance = 190 + (index % 4) * 34
		local info = TweenInfo.new(1.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService
			:Create(spark, info, {
				Position = UDim2.new(
					0.5,
					math.cos(angle) * distance,
					0.5,
					math.sin(angle) * distance
				),
				Rotation = math.deg(angle) + 180,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(3, 3),
			})
			:Play()

		task.delay(1.2, function()
			spark:Destroy()
		end)
	end
end

function MissionComplete.show(parent: ScreenGui)
	local completion = Objectives.Completion

	local root = Theme.new("Frame", {
		Name = "MissionComplete",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = COLORS.Scrim,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	TweenService:Create(root, Theme.Tween.Slide, { BackgroundTransparency = 0.45 }):Play()

	local panel = Theme.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(PANEL.X, PANEL.Y),
		BackgroundColor3 = COLORS.Menu,
		Inner = true,
		Parent = root,
	})

	-- The panel arrives bouncing up from almost nothing: the gesture that
	-- says "you won" before the text is even read.
	local scale = Theme.new("UIScale", { Scale = 0.6, Parent = panel })
	TweenService:Create(scale, Theme.Tween.Pop, { Scale = 1 }):Play()

	Theme.title({
		Name = "Title",
		Position = UDim2.fromOffset(0, SPACE.xl),
		Size = UDim2.new(1, 0, 0, 40),
		TextSize = Theme.TextSize.display,
		Text = completion.title,
		Parent = panel,
	})

	Theme.body({
		Name = "Subtitle",
		Position = UDim2.fromOffset(SPACE.xl, SPACE.xl + 48),
		Size = UDim2.new(1, -SPACE.xl * 2, 0, 24),
		TextColor3 = COLORS.TextDim,
		Text = completion.subtitle,
		Parent = panel,
	})

	Theme.title({
		Name = "Gift",
		Position = UDim2.fromOffset(0, SPACE.xl + 96),
		Size = UDim2.new(1, 0, 0, 28),
		TextColor3 = COLORS.Credit,
		Text = completion.gift,
		Parent = panel,
	})

	Theme.body({
		Name = "Reward",
		Position = UDim2.fromOffset(0, SPACE.xl + 132),
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = COLORS.Valid,
		Text = `+{completion.reward} crédits`,
		Parent = panel,
	})

	Theme.caption({
		Name = "Steps",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -SPACE.md),
		Size = UDim2.new(1, 0, 0, 16),
		Text = `{Objectives.Count} objectifs sur {Objectives.Count}`,
		Parent = panel,
	})

	burst(root)

	task.delay(HOLD, function()
		if not root.Parent then
			return
		end
		local fade = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(root, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(scale, fade, { Scale = 0.85 }):Play()
		for _, descendant in panel:GetDescendants() do
			if descendant:IsA("TextLabel") then
				TweenService:Create(descendant, fade, { TextTransparency = 1 }):Play()
			elseif descendant:IsA("UIStroke") then
				TweenService:Create(descendant, fade, { Transparency = 1 }):Play()
			end
		end
		TweenService:Create(panel, fade, { BackgroundTransparency = 1 }):Play()
		task.delay(0.6, function()
			root:Destroy()
		end)
	end)
end

return MissionComplete
