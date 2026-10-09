--[[
	RewardConfig
	Daily login streak, playtime gifts and daily quests.

	Reward table fields (all optional, combine freely) - same format as promo codes:
		Essence        flat Essence
		IncomeSeconds  Essence = max(Essence, income/sec * IncomeSeconds) -> scales with progress
		Boost          { Kind = "Essence2x" | "Luck2x" | "Luck5x", Seconds = n }
		Orb            { Rarity = "Epic", Biome = "Best", Mutation = "Haunted"? }
		Candy          event currency (only granted while an event is active)
]]

local RewardConfig = {}

-- 7-day login streak. Claim once per UTC day; miss a day and the streak restarts at day 1.
RewardConfig.Daily = {
	{ Label = "Essence", Rewards = { Essence = 500, IncomeSeconds = 10 * 60 } },
	{ Label = "2x Luck 15m", Rewards = { Boost = { Kind = "Luck2x", Seconds = 15 * 60 } } },
	{ Label = "Big Essence", Rewards = { Essence = 2_000, IncomeSeconds = 30 * 60 } },
	{ Label = "2x Essence 30m", Rewards = { Boost = { Kind = "Essence2x", Seconds = 30 * 60 } } },
	{ Label = "Epic Soul", Rewards = { Orb = { Rarity = "Epic", Biome = "Best" } } },
	{ Label = "Huge Essence", Rewards = { Essence = 10_000, IncomeSeconds = 60 * 60, Candy = 50 } },
	{ Label = "LEGENDARY Soul", Rewards = { Orb = { Rarity = "Legendary", Biome = "Best" }, Boost = { Kind = "Luck5x", Seconds = 15 * 60 } } },
}

-- Gifts unlocked by minutes played in THIS session (claim from the Gifts panel).
RewardConfig.Playtime = {
	{ Minutes = 3, Label = "Essence", Rewards = { Essence = 300, IncomeSeconds = 3 * 60 } },
	{ Minutes = 10, Label = "Rare Soul", Rewards = { Orb = { Rarity = "Rare", Biome = "Best" } } },
	{ Minutes = 20, Label = "2x Luck 10m", Rewards = { Boost = { Kind = "Luck2x", Seconds = 10 * 60 }, Candy = 20 } },
	{ Minutes = 35, Label = "Epic Soul", Rewards = { Orb = { Rarity = "Epic", Biome = "Best" } } },
	{ Minutes = 60, Label = "Essence Jackpot", Rewards = { IncomeSeconds = 45 * 60, Essence = 5_000, Candy = 50 } },
}

-- Daily quests: 3 picked per player per day from this pool.
-- Kind is the event counted by QuestService:Progress(player, kind, amount).
RewardConfig.QuestPool = {
	{ Id = "Steal8", Kind = "Deliver", Goal = 8, Text = "Bring 8 souls home", Rewards = { IncomeSeconds = 10 * 60, Essence = 500, Candy = 15 } },
	{ Id = "Steal20", Kind = "Deliver", Goal = 20, Text = "Bring 20 souls home", Rewards = { IncomeSeconds = 25 * 60, Essence = 1_500, Candy = 30 } },
	{ Id = "Hatch5", Kind = "Hatch", Goal = 5, Text = "Hatch 5 spirits", Rewards = { IncomeSeconds = 10 * 60, Essence = 500, Candy = 15 } },
	{ Id = "Hatch15", Kind = "Hatch", Goal = 15, Text = "Hatch 15 spirits", Rewards = { Boost = { Kind = "Luck2x", Seconds = 15 * 60 }, Candy = 30 } },
	{ Id = "Rob1", Kind = "BaseSteal", Goal = 1, Text = "Steal a soul from another player's base", Rewards = { IncomeSeconds = 15 * 60, Essence = 1_000, Candy = 25 } },
	{ Id = "Rare3", Kind = "DeliverRare", Goal = 3, Text = "Bring home 3 Rare or better souls", Rewards = { Orb = { Rarity = "Epic", Biome = "Best" } } },
	{ Id = "Speed10", Kind = "BuySpeed", Goal = 10, Text = "Buy 10 Speed", Rewards = { IncomeSeconds = 10 * 60, Essence = 750 } },
	{ Id = "Bonk3", Kind = "Bonk", Goal = 3, Text = "Knock a soul loose from 3 thieves", Rewards = { IncomeSeconds = 15 * 60, Candy = 25 } },
	{ Id = "Candy40", Kind = "Candy", Goal = 40, Text = "Collect 40 Candy from pumpkins", Rewards = { Boost = { Kind = "Essence2x", Seconds = 15 * 60 }, Candy = 20 }, EventOnly = true },
	{ Id = "Night5", Kind = "DeliverNight", Goal = 5, Text = "Bring home 5 souls at night", Rewards = { Boost = { Kind = "Luck2x", Seconds = 10 * 60 }, Candy = 20 } },
}
RewardConfig.QuestsPerDay = 3
RewardConfig.AllQuestsBonus = { Orb = { Rarity = "Legendary", Biome = "Best" } }

-- Spirit Index: +1% Essence per unique species discovered (56 at launch = +56%).
RewardConfig.IndexBonusPerSpecies = 0.01

function RewardConfig.Today(): number
	return os.time() // 86400
end

return RewardConfig
