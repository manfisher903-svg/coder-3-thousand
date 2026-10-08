--[[
	Remotes
	Single source of truth for every RemoteEvent / RemoteFunction.
	Server: Remotes.Init() creates them under ReplicatedStorage.Remotes.
	Client: Remotes.Event(name) / Remotes.Function(name) waits for them.

	Server -> Client (RemoteEvent)
		Notify(message: string, kind: "info"|"success"|"error"|"warning")
		StateChanged(snapshot)               full UI snapshot (pets, slots, perks, passes...)
		HatchResult(result)                  pop-up when a soul hatches
		Announce(message, color)             server-wide banner (rare spawns, big steals, eclipse)
		Knockback(velocity: Vector3)         client applies it to its own character (it owns its physics)
	Client -> Server (RemoteEvent)
		DropOrb()                            voluntarily drop the carried soul
	Client -> Server (RemoteFunction) - all return { ok: boolean, msg: string? }
		GetState()                           returns snapshot
		RequestUpgrade(kind, amount)         kind: "Speed"|"Carry"|"Treadmill"|"Pedestal"
		RequestRebirth()
		BuyPerk(perkId)
		RedeemCode(code)
		PetAction(action, arg1, arg2)        action: "Store"|"Place"|"Sell"|"Lock"
		RequestLock()                        lock your base
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.EventNames = { "Notify", "StateChanged", "HatchResult", "Announce", "Knockback", "DropOrb" }
Remotes.FunctionNames = { "GetState", "RequestUpgrade", "RequestRebirth", "BuyPerk", "RedeemCode", "PetAction", "RequestLock" }

local FOLDER_NAME = "Remotes"

function Remotes.Init()
	assert(RunService:IsServer(), "Remotes.Init must run on the server")
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in ipairs(Remotes.EventNames) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	for _, name in ipairs(Remotes.FunctionNames) do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

local function getFolder(): Folder
	return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
end

function Remotes.Event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
