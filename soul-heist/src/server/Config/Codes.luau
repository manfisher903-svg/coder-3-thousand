--[[
	Codes (SERVER ONLY - lives in ServerScriptService so exploiters can't read unreleased codes)

	Reward fields (all optional, combine freely):
		Essence        flat Essence
		IncomeSeconds  Essence = max(Essence, income/sec * IncomeSeconds) -> stays relevant late-game
		Boost          { Kind = "Essence2x" | "Luck2x" | "Luck5x", Seconds = n }
		Orb            { Rarity = "Epic", Biome = "Best" | biomeId }   ("Best" = player's best unlocked biome)
	Expires = os.time() style unix timestamp (nil = never). Use https://www.epochconverter.com
	MinRebirths = only usable after N rebirths.
	Codes are case-insensitive. Each player can redeem each code once.
]]

return {
	RELEASE = {
		Rewards = { Essence = 500, Boost = { Kind = "Luck2x", Seconds = 15 * 60 } },
	},
	SOULTHIEF = {
		Rewards = { Essence = 250, IncomeSeconds = 10 * 60 },
	},
	FREEEPIC = {
		Rewards = { Orb = { Rarity = "Epic", Biome = "Best" } },
	},
	LIKE10K = {
		Rewards = { IncomeSeconds = 30 * 60, Essence = 2_000, Boost = { Kind = "Essence2x", Seconds = 15 * 60 } },
	},
	ECLIPSE = {
		Rewards = { Boost = { Kind = "Luck5x", Seconds = 10 * 60 } },
		Expires = nil,
	},
	REBORN = {
		Rewards = { Orb = { Rarity = "Legendary", Biome = "Best" } },
		MinRebirths = 1,
	},
}
