--[[
	PlayerDataService
	Loads, session-locks, autosaves and releases player profiles.

	Session locking: every record is stored as { Data = <profile>, Lock = { JobId, Time } }.
	  * On join we UpdateAsync and only claim the record if no OTHER live server holds the lock
	    (a lock older than SessionLockStaleSeconds is treated as a crashed server and taken over).
	  * Autosaves refresh the lock timestamp and REFUSE to write if another server stole the lock
	    (prevents item duplication through fast server-hopping).
	  * On leave / shutdown we save one last time and clear the lock.

	API
		:GetData(player) -> PlayerData?
		:IsLoaded(player) -> boolean
		:WaitForData(player, timeout?) -> PlayerData?
		:SaveAsync(player, release?) -> boolean
		:MarkDirty(player)            schedule a StateChanged push to the client (batched)
		:Notify(player, msg, kind?)
		.ProfileLoaded(player, data)  Signal
		.ProfileReleasing(player, data) Signal - fired right before the final save (sync work only)
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Signal = require(Shared.Util.Signal)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local PlayerDataService = {}
PlayerDataService.ProfileLoaded = Signal.new()
PlayerDataService.ProfileReleasing = Signal.new()

local DEFAULT_DATA = {
	Version = GameConfig.DataVersion,
	Essence = EconomyConfig.StartingEssence,
	Speed = EconomyConfig.StartingSpeed,
	CarryLevel = 0,
	TreadmillTier = 1,
	Pedestals = EconomyConfig.StartingPedestals,
	Rebirths = 0,
	RebirthTokens = 0,
	Perks = { SoulMagnet = 0, Attunement = 0, SwiftStart = 0, QuickIncubation = 0, TreadmillMemory = 0 },
	Pets = {},
	NextPetId = 1,
	Slots = {},
	PendingOrbs = {},
	Boosts = { Essence2x = 0, Luck2x = 0, Luck5x = 0 },
	RedeemedCodes = {},
	ProcessedReceipts = {},
	StarterPackBought = false,
	ShieldUntil = 0,
	LastRobbed = nil,
	LastOnline = 0,
	LastIncome = 0,
	Stats = { TotalEssence = 0, Steals = 0, BaseSteals = 0, TimesRobbed = 0, Hatched = 0, PlayTime = 0, RobuxSpent = 0 },
}

type Profile = {
	Player: Player,
	Key: string,
	Data: any,
	Released: boolean,
	LastSave: number,
}

local profiles: { [Player]: Profile } = {}
local releasingUserIds: { [number]: boolean } = {} -- final save in flight (same-server rejoin guard)
local dirty: { [Player]: boolean } = {}
local Services: any
local store: any

-- Utilities -------------------------------------------------------------------------
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in pairs(value) do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Fill in any keys added to DEFAULT_DATA since the profile was created (safe schema migration).
local function reconcile(target: any, template: any)
	for key, value in pairs(template) do
		if target[key] == nil then
			target[key] = deepCopy(value)
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			reconcile(target[key], value)
		end
	end
end

local function migrate(data: any)
	-- Example for future versions:
	-- if data.Version < 2 then data.NewField = ...; data.Version = 2 end
	data.Version = GameConfig.DataVersion
end

-- In-memory DataStore used in Studio when API access is disabled.
local function createMockStore()
	local memory = {}
	return {
		UpdateAsync = function(_, key, transform)
			local result = transform(deepCopy(memory[key]))
			if result ~= nil then
				memory[key] = deepCopy(result)
			end
			return deepCopy(memory[key])
		end,
	}
end

local function getStore()
	local ok, realStore = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok and realStore and RunService:IsStudio() and GameConfig.UseMockDataStoreInStudio then
		-- Probe API access; Studio throws if "Enable Studio Access to API Services" is off.
		local probeOk = pcall(function()
			realStore:GetAsync("__probe")
		end)
		if not probeOk then
			warn("[PlayerDataService] No DataStore access in Studio -> using in-memory mock store (data will not persist).")
			return createMockStore()
		end
	end
	if not ok then
		warn("[PlayerDataService] DataStore unavailable -> using mock store:", realStore)
		return createMockStore()
	end
	return realStore
end

-- Loading ------------------------------------------------------------------------------
local function loadProfileAsync(player: Player): any?
	local key = "Player_" .. player.UserId
	for attempt = 1, GameConfig.LoadRetryAttempts do
		local lockedByOther = false
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(stored)
				lockedByOther = false
				stored = stored or {}
				local lock = stored.Lock
				if lock and lock.JobId ~= game.JobId and os.time() - (lock.Time or 0) < GameConfig.SessionLockStaleSeconds then
					lockedByOther = true
					return nil -- cancel the write, someone else owns this profile
				end
				stored.Lock = { JobId = game.JobId, Time = os.time() }
				return stored
			end)
		end)

		if ok and not lockedByOther then
			local data = (result and result.Data) or deepCopy(DEFAULT_DATA)
			reconcile(data, DEFAULT_DATA)
			migrate(data)
			return data
		end
		if not ok then
			warn(string.format("[PlayerDataService] Load attempt %d failed for %s: %s", attempt, player.Name, tostring(result)))
		end
		task.wait(GameConfig.LoadRetryDelay)
	end
	return nil
end

-- Saving --------------------------------------------------------------------------------
local function saveProfileAsync(profile: Profile, release: boolean): boolean
	if profile.Released then
		return true
	end
	local lostLock = false
	local data = profile.Data
	data.LastOnline = os.time()
	local ok, err = pcall(function()
		store:UpdateAsync(profile.Key, function(stored)
			lostLock = false
			stored = stored or {}
			if stored.Lock and stored.Lock.JobId ~= game.JobId then
				lostLock = true
				return nil
			end
			stored.Data = data
			stored.Lock = if release then nil else { JobId = game.JobId, Time = os.time() }
			return stored
		end)
	end)
	if not ok then
		warn("[PlayerDataService] Save failed for", profile.Player.Name, err)
		return false
	end
	if lostLock then
		warn("[PlayerDataService] Session lock lost for", profile.Player.Name, "- kicking to protect data")
		profile.Released = true
		profiles[profile.Player] = nil
		profile.Player:Kick("Your data was opened in another server. Please rejoin.")
		return false
	end
	profile.LastSave = os.clock()
	if release then
		profile.Released = true
	end
	return true
end

-- Leaderstats ------------------------------------------------------------------------------
local function createLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local essence = Instance.new("StringValue")
	essence.Name = "Essence"
	essence.Parent = folder
	local rebirths = Instance.new("IntValue")
	rebirths.Name = "Rebirths"
	rebirths.Parent = folder
	local steals = Instance.new("IntValue")
	steals.Name = "Steals"
	steals.Parent = folder
	folder.Parent = player
end

-- Mirrors frequently-changing numbers onto player attributes + leaderstats.
-- The client UI reads attributes (cheap), and the full snapshot only on structural change.
function PlayerDataService:Replicate(player: Player)
	local data = self:GetData(player)
	if not data then
		return
	end
	player:SetAttribute("Essence", data.Essence)
	player:SetAttribute("Speed", data.Speed)
	player:SetAttribute("CarryLevel", data.CarryLevel)
	player:SetAttribute("TreadmillTier", data.TreadmillTier)
	player:SetAttribute("Pedestals", data.Pedestals)
	player:SetAttribute("Rebirths", data.Rebirths)
	player:SetAttribute("RebirthTokens", data.RebirthTokens)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		(stats :: any).Essence.Value = Format.Number(data.Essence);
		(stats :: any).Rebirths.Value = data.Rebirths;
		(stats :: any).Steals.Value = data.Stats.Steals
	end
end

-- Full UI snapshot ------------------------------------------------------------------------------
function PlayerDataService:BuildSnapshot(player: Player)
	local data = self:GetData(player)
	if not data then
		return nil
	end
	local monetization = Services.MonetizationService
	local petService = Services.PetService
	return {
		Essence = data.Essence,
		Speed = data.Speed,
		CarryLevel = data.CarryLevel,
		TreadmillTier = data.TreadmillTier,
		Pedestals = data.Pedestals,
		ActivePedestals = petService:GetActivePedestalCount(player),
		Rebirths = data.Rebirths,
		RebirthTokens = data.RebirthTokens,
		Perks = data.Perks,
		Pets = data.Pets,
		Slots = data.Slots,
		PendingOrbs = #data.PendingOrbs,
		Boosts = data.Boosts,
		Passes = monetization:GetOwnedPasses(player),
		StarterPackBought = data.StarterPackBought,
		VaultSize = Services.RebirthService:GetVaultSize(player),
		CanStealBack = data.LastRobbed ~= nil and os.time() - data.LastRobbed.Time < 600,
		Income = Services.EconomyService:GetIncome(player),
		Luck = Services.EconomyService:GetLuck(player),
		Stats = data.Stats,
		ServerTime = os.time(),
	}
end

function PlayerDataService:MarkDirty(player: Player)
	dirty[player] = true
end

function PlayerDataService:Notify(player: Player, message: string, kind: string?)
	Remotes.Event("Notify"):FireClient(player, message, kind or "info")
end

-- Public API ------------------------------------------------------------------------------------
function PlayerDataService:GetData(player: Player): any?
	local profile = profiles[player]
	return profile and not profile.Released and profile.Data or nil
end

function PlayerDataService:IsLoaded(player: Player): boolean
	return self:GetData(player) ~= nil
end

function PlayerDataService:WaitForData(player: Player, timeout: number?): any?
	local deadline = os.clock() + (timeout or 30)
	while player.Parent and os.clock() < deadline do
		local data = self:GetData(player)
		if data then
			return data
		end
		task.wait(0.1)
	end
	return nil
end

function PlayerDataService:SaveAsync(player: Player, release: boolean?): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	return saveProfileAsync(profile, release == true)
end

function PlayerDataService:GetAllLoaded(): { [Player]: any }
	local result = {}
	for player, profile in pairs(profiles) do
		if not profile.Released then
			result[player] = profile.Data
		end
	end
	return result
end

-- Lifecycle ----------------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	createLeaderstats(player)
	-- If this player just left THIS server, wait for their final save before reading.
	local waitUntil = os.clock() + 30
	while releasingUserIds[player.UserId] and os.clock() < waitUntil do
		task.wait(0.2)
	end
	local data = loadProfileAsync(player)
	if not player.Parent then
		-- Left while loading: give the lock back immediately so they can join another server.
		if data then
			saveProfileAsync({ Player = player, Key = "Player_" .. player.UserId, Data = data, Released = false, LastSave = 0 }, true)
		end
		return
	end
	if not data then
		player:Kick("Your data is still saving from another server. Please rejoin in a minute.")
		return
	end
	profiles[player] = {
		Player = player,
		Key = "Player_" .. player.UserId,
		Data = data,
		Released = false,
		LastSave = os.clock(),
	}
	player:SetAttribute("DataLoaded", true)
	PlayerDataService:Replicate(player)
	PlayerDataService.ProfileLoaded:Fire(player, data)
	PlayerDataService:MarkDirty(player)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	dirty[player] = nil
	if not profile or profile.Released then
		return
	end
	-- Synchronous handlers (drop carried orb, clear base...) run first so the save is final.
	for _, handler in ipairs(PlayerDataService._releasingHandlers) do
		local ok, err = pcall(handler, player, profile.Data)
		if not ok then
			warn("[PlayerDataService] Releasing handler error:", err)
		end
	end
	PlayerDataService.ProfileReleasing:Fire(player, profile.Data)
	releasingUserIds[player.UserId] = true
	saveProfileAsync(profile, true)
	releasingUserIds[player.UserId] = nil
	profiles[player] = nil
end

-- Services that must mutate data synchronously before the final save register here.
PlayerDataService._releasingHandlers = {} :: { (Player, any) -> () }
function PlayerDataService:OnBeforeRelease(handler: (Player, any) -> ())
	table.insert(self._releasingHandlers, handler)
end

function PlayerDataService:Init(services)
	Services = services
	store = getStore()
end

function PlayerDataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	-- Staggered autosave
	task.spawn(function()
		while true do
			task.wait(5)
			for _, profile in pairs(profiles) do
				if not profile.Released and os.clock() - profile.LastSave >= GameConfig.AutosaveInterval then
					profile.LastSave = os.clock() -- reserve the slot so a slow save isn't queued twice
					task.spawn(saveProfileAsync, profile, false)
				end
			end
		end
	end)

	-- Batched snapshot pushes (max 4/sec per player)
	task.spawn(function()
		local stateChanged = Remotes.Event("StateChanged")
		while true do
			task.wait(0.25)
			for player in pairs(dirty) do
				dirty[player] = nil
				if player.Parent and self:IsLoaded(player) then
					local ok, snapshot = pcall(self.BuildSnapshot, self, player)
					if ok and snapshot then
						stateChanged:FireClient(player, snapshot)
					elseif not ok then
						warn("[PlayerDataService] Snapshot error:", snapshot)
					end
				end
			end
		end
	end)

	Remotes.Function("GetState").OnServerInvoke = function(player)
		return self:BuildSnapshot(player)
	end

	game:BindToClose(function()
		local pending = 0
		for player, profile in pairs(profiles) do
			pending += 1
			task.spawn(function()
				for _, handler in ipairs(self._releasingHandlers) do
					pcall(handler, player, profile.Data)
				end
				saveProfileAsync(profile, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerDataService
