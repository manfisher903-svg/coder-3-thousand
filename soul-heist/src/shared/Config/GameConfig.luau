--[[
	GameConfig
	Global, non-economy tuning for Steal a Soul. Shared with the client (nothing secret here).
]]

local GameConfig = {
	-- Data ---------------------------------------------------------------
	DataStoreName = "SoulHeist_PlayerData_v1", -- bump the suffix ONLY for a full wipe
	DataVersion = 1,
	AutosaveInterval = 60, -- seconds between autosaves per player
	SessionLockStaleSeconds = 300, -- a lock older than this is considered abandoned (crashed server)
	LoadRetryAttempts = 5,
	LoadRetryDelay = 6,
	UseMockDataStoreInStudio = true, -- falls back to in-memory data if Studio has no API access

	-- Testing --------------------------------------------------------------
	StudioGrantAllPasses = false, -- set true to test every Game Pass in Studio

	-- Social bonuses ------------------------------------------------------
	GroupId = 0, -- your Roblox group id (0 = disabled)
	PremiumIncomeBonus = 0.10,
	GroupIncomeBonus = 0.10,
	FriendIncomeBonus = 0.10, -- per friend in server
	MaxFriendBonuses = 4,

	-- Base ---------------------------------------------------------------
	MaxBases = 8, -- players per server should equal this (set in Game Settings)
	PhysicalPedestalsPerBase = 25, -- 20 buyable + 5 from the Extra Pedestals pass
	BaseLockDuration = 45,
	BaseLockCooldown = 120,
	NewPlayerProtectionSeconds = 900, -- bases can't be robbed during a player's first 15 min of playtime
	BaseStealHoldBase = 2.0, -- seconds to hold "Steal" on someone else's pedestal (+ rarity bonus)
	BaseStealMaxDistance = 14,

	-- Orbs ---------------------------------------------------------------
	WorldOrbPickupMaxDistance = 14,
	DroppedOrbLifetime = 45,
	MaxCarried = 1,

	-- PvP tool ------------------------------------------------------------
	Lantern = { Range = 9, Cooldown = 1.2, StunSeconds = 0.8, Knockback = 45 },
	Scythe = { Range = 13, Cooldown = 0.8, StunSeconds = 1.4, Knockback = 70 },

	-- Day / Night ---------------------------------------------------------
	DayNight = {
		CycleSeconds = 600, -- full cycle
		NightStart = 360, -- seconds into the cycle when night begins (6 min day / 4 min night)
		EclipseEveryNthNight = 4,
		Night = { SpawnLuck = 2, MutationLuck = 2, GuardianSpeed = 1.20 },
		Eclipse = { SpawnLuck = 5, MutationLuck = 4, GuardianSpeed = 1.35 },
	},

	-- Inventory -----------------------------------------------------------
	InventoryCap = 60,
	MaxPendingOrbs = 10,

	-- Anti-exploit ----------------------------------------------------------
	AntiExploit = {
		CheckInterval = 0.5,
		SpeedTolerance = 1.35, -- allowed multiple of expected WalkSpeed
		FlatTolerance = 8, -- studs/sec of slack (latency, slopes)
		StrikesBeforeRubberband = 3,
	},
}

return GameConfig
