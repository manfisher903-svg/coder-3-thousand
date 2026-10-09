--[[
	MonetizationConfig
	Paste your real Game Pass / Developer Product IDs into the Id fields (Creator Hub -> your experience
	-> Monetization). Prices here are DISPLAY ONLY - the real price is whatever you set on Roblox,
	so keep them in sync. Id = 0 means "not created yet" (the shop hides it).
]]

export type PassInfo = { Id: number, Price: number, Name: string, Desc: string, Order: number }
export type ProductInfo = { Id: number, Price: number, Name: string, Desc: string, Order: number, Hidden: boolean?, Event: boolean? }

local MonetizationConfig = {}

MonetizationConfig.GamePasses = {
	VIP = { Id = 0, Price = 299, Order = 1, Name = "VIP Soul Thief", Desc = "+10% Essence, +1 Pedestal, gold VIP tag, VIP lounge" },
	DoubleEssence = { Id = 0, Price = 449, Order = 2, Name = "2x Essence", Desc = "Permanently doubles ALL Essence income" },
	SuperLuck = { Id = 0, Price = 399, Order = 3, Name = "Super Luck", Desc = "2x Luck: more mutations + rarity Ascensions" },
	ExtraPedestals = { Id = 0, Price = 349, Order = 4, Name = "+5 Pedestals", Desc = "5 extra pedestals in your base, forever" },
	FastHatch = { Id = 0, Price = 249, Order = 5, Name = "Fast Hatch", Desc = "All souls hatch 2x faster" },
	PhantomSteps = { Id = 0, Price = 199, Order = 6, Name = "Phantom Steps", Desc = "+4 Speed and carry souls 25% lighter" },
	ReaperScythe = { Id = 0, Price = 299, Order = 7, Name = "Reaper Scythe", Desc = "Longer-range, faster bonk weapon that stuns longer" },
	Fortress = { Id = 0, Price = 249, Order = 8, Name = "Fortress", Desc = "Base lock lasts 2x longer, cooldown halved" },
	SoulVault = { Id = 0, Price = 149, Order = 9, Name = "Soul Vault+", Desc = "Keep +3 extra spirits through every rebirth" },
	OfflineOvertime = { Id = 0, Price = 199, Order = 10, Name = "Spirit Overtime", Desc = "Earn 50% offline for up to 12h (free: 10% for 2h)" },
} :: { [string]: PassInfo }

MonetizationConfig.Products = {
	StarterPack = { Id = 0, Price = 99, Order = 1, Name = "Starter Pack (once)", Desc = "Epic orb + 5,000 Essence + 30 min 2x Essence" },
	InstantHatchOne = { Id = 0, Price = 25, Order = 2, Name = "Instant Hatch", Desc = "Hatch your slowest soul right now" },
	InstantHatchAll = { Id = 0, Price = 79, Order = 3, Name = "Hatch All", Desc = "Hatch every incubating soul right now" },
	StealBack = { Id = 0, Price = 39, Order = 4, Name = "Soul Echo", Desc = "Recover a copy of the last soul stolen from you", Hidden = true },
	EssenceSmall = { Id = 0, Price = 49, Order = 5, Name = "Essence Pouch", Desc = "15 min of income" },
	EssenceMedium = { Id = 0, Price = 149, Order = 6, Name = "Essence Jar", Desc = "1 hour of income" },
	EssenceLarge = { Id = 0, Price = 399, Order = 7, Name = "Essence Urn", Desc = "4 hours of income (BEST VALUE)" },
	EssenceHuge = { Id = 0, Price = 999, Order = 8, Name = "Essence Reliquary", Desc = "12 hours of income" },
	Essence2x30 = { Id = 0, Price = 79, Order = 9, Name = "2x Essence (30m)", Desc = "Stacks with the 2x pass for 4x" },
	Luck2x30 = { Id = 0, Price = 59, Order = 10, Name = "Lucky Potion (30m)", Desc = "2x Luck for 30 minutes" },
	Luck5x30 = { Id = 0, Price = 199, Order = 11, Name = "Mega Luck (30m)", Desc = "5x Luck for 30 minutes" },
	BaseShield10 = { Id = 0, Price = 49, Order = 12, Name = "Soul Shield (10m)", Desc = "Nobody can steal from your base for 10 minutes" },
	RebirthSkip = { Id = 0, Price = 199, Order = 13, Name = "Rebirth Skip", Desc = "Rebirth now without paying Essence" },
	LegendaryOrb = { Id = 0, Price = 399, Order = 14, Name = "Legendary Soul", Desc = "A Legendary orb from your best unlocked biome" },
	MythicOrb = { Id = 0, Price = 1299, Order = 15, Name = "Mythic Soul", Desc = "A Mythic orb from your best unlocked biome" },
	ServerEclipse = { Id = 0, Price = 499, Order = 16, Name = "Summon Soul Eclipse", Desc = "15 min server-wide Eclipse: 5x spawn luck for EVERYONE" },
	-- Seasonal (only shown while an event is active)
	CandySmall = { Id = 0, Price = 49, Order = 17, Name = "Candy Bag", Desc = "120 Candy for the event shop", Event = true },
	CandyLarge = { Id = 0, Price = 199, Order = 18, Name = "Candy Cauldron", Desc = "600 Candy for the event shop (BEST VALUE)", Event = true },
} :: { [string]: ProductInfo }

-- Effect constants used by the server
MonetizationConfig.Effects = {
	BoostSeconds = 30 * 60,
	ShieldSeconds = 10 * 60,
	EclipseSeconds = 15 * 60,
	StealBackWindow = 10 * 60,
	StarterPackEssence = 5_000,
	VIPIncomeBonus = 0.10,
	VIPPedestals = 1,
	ExtraPedestals = 5,
	PhantomSpeed = 4,
	PhantomLighter = 0.25,
	CandySmall = 120,
	CandyLarge = 600,
}

function MonetizationConfig.FindProductKey(productId: number): string?
	for key, info in pairs(MonetizationConfig.Products) do
		if info.Id == productId and info.Id ~= 0 then
			return key
		end
	end
	return nil
end

function MonetizationConfig.FindPassKey(passId: number): string?
	for key, info in pairs(MonetizationConfig.GamePasses) do
		if info.Id == passId and info.Id ~= 0 then
			return key
		end
	end
	return nil
end

return MonetizationConfig
