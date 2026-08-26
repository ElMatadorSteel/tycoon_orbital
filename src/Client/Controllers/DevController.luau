--!strict
-- Wires the dev-mode panel (UI/DevPanel.luau) to Net's dev-only remotes.
-- Only ever builds anything at all in Studio -- these remotes have no
-- server-side handler in production anyway (see Composition/Container.luau's
-- `development` flag), so there is nothing for this panel to do there.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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
local State = require("../State")
local DevPanel = require("../UI/DevPanel")

local DevController = {}

function DevController:Start()
	if not RunService:IsStudio() then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevUI"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Above BuildUI (10): a dev override should never be hidden behind the
	-- build menu if both happen to be open at once.
	gui.DisplayOrder = 20
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = DevPanel.new(gui)

	panel.onSetRebirths = function(count: number, resetStation: boolean)
		Net.DevSetRebirths:InvokeServer(count, resetStation)
	end
	panel.onSetUltimate = function(enabled: boolean)
		Net.DevSetPass:InvokeServer("Ultimate", enabled)
		panel:SetUltimateEnabled(enabled)
	end
	panel.onSetEarlyRebirth = function(enabled: boolean)
		Net.DevSetPass:InvokeServer("EarlyRebirth", enabled)
		panel:SetEarlyRebirthEnabled(enabled)
	end
	panel.onGiveCredits = function(amount: number)
		Net.DevGiveCredits:InvokeServer(amount)
	end
	panel.onSetUnlimitedMoney = function(enabled: boolean)
		Net.DevSetUnlimitedMoney:InvokeServer(enabled)
		panel:SetUnlimitedMoneyEnabled(enabled)
	end
	panel.onResetAll = function()
		Net.DevResetAll:InvokeServer()
	end

	State.Changed:Connect(function(key: string, value: any)
		if key == "Rebirths" then
			panel:SetRebirths(value :: number)
		elseif key == "HasUltimate" then
			panel:SetUltimateEnabled(value == true)
		elseif key == "HasEarlyRebirth" then
			panel:SetEarlyRebirthEnabled(value == true)
		end
	end)

	local initialRebirths = State.get("Rebirths")
	if initialRebirths then
		panel:SetRebirths(initialRebirths :: number)
	end
	panel:SetUltimateEnabled(State.get("HasUltimate") == true)
	panel:SetEarlyRebirthEnabled(State.get("HasEarlyRebirth") == true)
end

return DevController
