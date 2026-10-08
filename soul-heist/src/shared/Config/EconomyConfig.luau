--[[
	EconomyConfig
	Every number the economy runs on. See docs/02-economy.md for the reasoning and pacing tables.
	All cost formulas live in Shared/Formulas so client UI and server agree exactly.
]]

local EconomyConfig = {
	StartingEssence = 50,
	StartingSpeed = 16,
	StartingPedestals = 3,
	MaxPedestals = 20, -- purchasable with Essence (passes add on top)

	-- Speed: buying +1 Speed at current speed s costs floor(SpeedBaseCost * SpeedGrowth^(s - 16))
	SpeedBaseCost = 25,
	SpeedGrowth = 1.18,

	-- Treadmill tiers cap how high Speed can be bought.
	Treadmill = {
		{ Cap = 30, Cost = 0 },
		{ Cap = 45, Cost = 1_500 },
		{ Cap = 60, Cost = 15_000 },
		{ Cap = 80, Cost = 250_000 },
		{ Cap = 100, Cost = 5_000_000 },
		{ Cap = 130, Cost = 100_000_000, RequiresRebirths = 1 },
		{ Cap = 160, Cost = 5_000_000_000, RequiresRebirths = 5 },
	},

	-- Carry (Soul Harness): reduces the slowdown from carrying heavy souls.
	CarryMaxLevel = 15,
	CarryReductionPerLevel = 0.04, -- 15 levels = 60% less slowdown
	CarryBaseCost = 150,
	CarryGrowth = 2.0,

	-- Pedestals: the n-th pedestal (n > StartingPedestals) costs PedestalBaseCost * PedestalGrowth^(n - 4)
	PedestalBaseCost = 500,
	PedestalGrowth = 1.9,

	-- Rebirth
	RebirthBaseCost = 10_000_000,
	RebirthGrowth = 3.2,
	RebirthMultPerRebirth = 0.5, -- permanent income multiplier = 1 + 0.5 * rebirths
	RebirthTokensBase = 1, -- tokens per rebirth = 1 + floor(rebirthsAfter / 3)
	VaultBaseSize = 1, -- pets you can keep through a rebirth = 1 + floor(rebirths / 2) (+3 with pass)
	VaultPassBonus = 3,

	-- Rebirth perks bought with Rebirth Tokens (permanent, never reset)
	Perks = {
		SoulMagnet = { Name = "Soul Magnet", Desc = "+10% Luck per level", MaxLevel = 10, CostBase = 1, CostPerLevel = 1, PerLevel = 0.10 },
		Attunement = { Name = "Essence Attunement", Desc = "+10% Essence per level", MaxLevel = 20, CostBase = 1, CostPerLevel = 1, PerLevel = 0.10 },
		SwiftStart = { Name = "Swift Start", Desc = "+4 starting Speed per level", MaxLevel = 5, CostBase = 2, CostPerLevel = 2, PerLevel = 4 },
		QuickIncubation = { Name = "Quick Incubation", Desc = "-5% hatch time per level", MaxLevel = 8, CostBase = 1, CostPerLevel = 1, PerLevel = 0.05 },
		TreadmillMemory = { Name = "Treadmill Memory", Desc = "Keep your Treadmill tier on rebirth", MaxLevel = 1, CostBase = 5, CostPerLevel = 0, PerLevel = 1 },
	},
	PerkOrder = { "SoulMagnet", "Attunement", "SwiftStart", "QuickIncubation", "TreadmillMemory" },

	-- Offline earnings (fraction of last income/sec, capped duration)
	OfflineFreePercent = 0.10,
	OfflineFreeCapSeconds = 2 * 3600,
	OfflinePassPercent = 0.50,
	OfflinePassCapSeconds = 12 * 3600,

	-- Essence developer products: grants max(Floor, income/sec * Seconds)
	EssencePacks = {
		EssenceSmall = { Seconds = 15 * 60, Floor = 1_000 },
		EssenceMedium = { Seconds = 60 * 60, Floor = 5_000 },
		EssenceLarge = { Seconds = 4 * 3600, Floor = 25_000 },
		EssenceHuge = { Seconds = 12 * 3600, Floor = 100_000 },
	},
}

return EconomyConfig
