--!strict
-- The objective banner: what the player must do right now.
--
-- It only ever displays the text from Domain/Objectives/Objectives, indexed
-- by the number the server publishes. No copy is written here, and this
-- controller never decides an objective is complete: it learns it.
--
-- Placed top-center: the HUD occupies the top-left corner, the build
-- buttons the right edge. The build menu, being modal, covers it when it
-- opens -- intentional, an objective isn't meant to be read while picking a
-- module.

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

local Objectives = require(fromShared("Domain/Objectives/Objectives"))
local State = require("../State")
local MissionComplete = require("../UI/MissionComplete")
local Theme = require("../UI/Theme")

local COLORS = Theme.Colors
local SPACE = Theme.Space

local WIDTH = 460
local HEIGHT = 104

local ObjectiveController = {}

function ObjectiveController:Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ObjectiveUI"
	gui.ResetOnSpawn = false
	-- Same rule as the HUD: leave room for the Roblox topbar.
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 5
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local root = Theme.panel({
		Name = "Objective",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, SPACE.lg),
		Size = UDim2.fromOffset(WIDTH, HEIGHT),
		BackgroundColor3 = COLORS.PanelDeep,
		Inner = true,
		Visible = false,
		Parent = gui,
	})

	local scale = Theme.new("UIScale", { Scale = 1, Parent = root })

	local step = Theme.caption({
		Name = "Step",
		Position = UDim2.fromOffset(SPACE.lg, SPACE.md),
		Size = UDim2.fromOffset(160, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Function.Info,
		Text = "",
		Parent = root,
	})

	local title = Theme.title({
		Name = "Title",
		Position = UDim2.fromOffset(SPACE.lg, SPACE.md + 18),
		Size = UDim2.new(1, -SPACE.lg * 2, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = root,
	})

	local hint = Theme.prose({
		Name = "Hint",
		Position = UDim2.fromOffset(SPACE.lg, SPACE.md + 48),
		Size = UDim2.new(1, -SPACE.lg * 2, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Text = "",
		Parent = root,
	})

	-- Unlike the rest, no outline: this is the only text that must be able
	-- to fade cleanly, and a UIStroke wouldn't track the fade.
	local reward = Theme.prose({
		Name = "Reward",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -SPACE.lg, 0, SPACE.md),
		Size = UDim2.fromOffset(140, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = Theme.TextSize.body,
		TextColor3 = COLORS.Valid,
		TextTransparency = 1,
		Text = "",
		Parent = root,
	})

	local function render(index: number)
		local objective = Objectives.get(index)
		if not objective then
			-- Chain finished: the banner disappears for good.
			root.Visible = false
			return
		end

		root.Visible = true
		step.Text = `OBJECTIF {index}/{Objectives.Count}`
		title.Text = objective.title
		hint.Text = objective.hint
	end

	State.Notified:Connect(function(kind: string, payload: any)
		if kind ~= "ObjectiveCompleted" then
			return
		end
		local completedIndex = payload.index :: number
		local rewardAmount = payload.reward :: number

		if rewardAmount > 0 then
			reward.Text = `+{rewardAmount} cr`
			reward.TextTransparency = 0
			TweenService:Create(
				reward,
				TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1 }
			):Play()
		end
		-- The banner flickers: makes the content change register.
		scale.Scale = 1.08
		TweenService:Create(scale, Theme.Tween.Pop, { Scale = 1 }):Play()

		-- The last objective in the chain: don't just make the banner
		-- disappear, mark the moment. The server only ever notifies
		-- ObjectiveCompleted the instant an objective falls, never on
		-- reconnect: the screen can't replay itself.
		if completedIndex >= Objectives.Count then
			MissionComplete.show(gui)
		end
	end)

	State.Changed:Connect(function(key: string, value: any)
		if key == "Objective" then
			render(value :: number)
		end
	end)

	local initial = State.get("Objective")
	if initial then
		render(initial :: number)
	end
end

return ObjectiveController
