--!strict
-- The shared network contract: every RemoteEvent/RemoteFunction the client
-- and server use to talk to each other, created from one list. Ported from
-- the legacy Shared/Remotes.lua's self-creating pattern -- the server
-- creates them at boot, the client waits for them, and adding one is a
-- one-line addition here, nothing else.
--
-- RemoteFunctions here always resolve to `(ok: boolean, valueOrError: any)`
-- -- Composition/RemoteBindings.luau is what flattens a use case's
-- Result<T, E> into that shape; nothing else should touch OnServerInvoke.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Net"

local DEFINITIONS = {
	-- client -> server, with a response
	PlaceModule = "RemoteFunction",
	RemoveModule = "RemoteFunction",
	UpgradeModule = "RemoteFunction",
	ReturnToLobby = "RemoteFunction",

	-- server -> client, one-off notifications -- the transport behind
	-- Ports.Notifier (a "+150" gain popup, a completed-objective banner).
	Notify = "RemoteEvent",
}

local Net = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for name, className in DEFINITIONS do
		local existing = folder:FindFirstChild(name)
		if existing and existing.ClassName ~= className then
			existing:Destroy()
			existing = nil
		end
		if not existing then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

for name in DEFINITIONS do
	Net[name] = folder:WaitForChild(name)
end

return Net
