--[[
	PetConfig
	Rarities (shared by Soul Orbs and the Spirit Pets they hatch into) and mutations.

	Income of a pet  = Rarity.BaseIncome * Biome.IncomeMult * Mutation.Mult   (Essence / second)
	Carry slowdown   = Rarity.Heaviness (fraction of WalkSpeed lost while carrying, before Carry upgrades)
]]

export type Rarity = {
	Id: string,
	Order: number,
	Color: Color3,
	SpawnWeight: number,
	BaseIncome: number,
	HatchSeconds: number,
	Heaviness: number,
	PickupHold: number,
	OrbSize: number,
	Announce: boolean,
}

export type Mutation = {
	Id: string,
	Mult: number,
	Chance: number,
	Color: Color3,
	NightOnly: boolean?,
	EclipseOnly: boolean?,
	EventOnly: boolean?,
}

local PetConfig = {}

PetConfig.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

PetConfig.Rarities = {
	Common = {
		Id = "Common", Order = 1, Color = Color3.fromRGB(200, 200, 210),
		SpawnWeight = 60, BaseIncome = 1, HatchSeconds = 10,
		Heaviness = 0.10, PickupHold = 0.5, OrbSize = 1.6, Announce = false,
	},
	Uncommon = {
		Id = "Uncommon", Order = 2, Color = Color3.fromRGB(90, 220, 120),
		SpawnWeight = 25, BaseIncome = 3, HatchSeconds = 20,
		Heaviness = 0.15, PickupHold = 0.7, OrbSize = 1.8, Announce = false,
	},
	Rare = {
		Id = "Rare", Order = 3, Color = Color3.fromRGB(70, 150, 255),
		SpawnWeight = 10, BaseIncome = 8, HatchSeconds = 40,
		Heaviness = 0.20, PickupHold = 1.0, OrbSize = 2.0, Announce = false,
	},
	Epic = {
		Id = "Epic", Order = 4, Color = Color3.fromRGB(180, 90, 255),
		SpawnWeight = 4, BaseIncome = 25, HatchSeconds = 75,
		Heaviness = 0.28, PickupHold = 1.3, OrbSize = 2.3, Announce = false,
	},
	Legendary = {
		Id = "Legendary", Order = 5, Color = Color3.fromRGB(255, 190, 40),
		SpawnWeight = 0.9, BaseIncome = 80, HatchSeconds = 150,
		Heaviness = 0.36, PickupHold = 1.7, OrbSize = 2.6, Announce = true,
	},
	Mythic = {
		Id = "Mythic", Order = 6, Color = Color3.fromRGB(255, 70, 110),
		SpawnWeight = 0.09, BaseIncome = 300, HatchSeconds = 300,
		Heaviness = 0.45, PickupHold = 2.2, OrbSize = 3.0, Announce = true,
	},
	Secret = {
		Id = "Secret", Order = 7, Color = Color3.fromRGB(20, 20, 25),
		SpawnWeight = 0.01, BaseIncome = 1500, HatchSeconds = 600,
		Heaviness = 0.55, PickupHold = 3.0, OrbSize = 3.4, Announce = true,
	},
} :: { [string]: Rarity }

-- Mutations are rolled at HATCH time with the hatcher's luck (rarest first, first success wins).
PetConfig.MutationOrder = { "Rainbow", "Eclipsed", "Voidtouched", "Haunted", "Celestial", "Moonlit", "Spectral", "Gilded" }

PetConfig.Mutations = {
	None = { Id = "None", Mult = 1, Chance = 0, Color = Color3.new(1, 1, 1) },
	Gilded = { Id = "Gilded", Mult = 2, Chance = 0.05, Color = Color3.fromRGB(255, 215, 0) },
	Spectral = { Id = "Spectral", Mult = 3, Chance = 0.02, Color = Color3.fromRGB(140, 255, 255) },
	Moonlit = { Id = "Moonlit", Mult = 5, Chance = 0.008, Color = Color3.fromRGB(150, 170, 255), NightOnly = true },
	Celestial = { Id = "Celestial", Mult = 8, Chance = 0.003, Color = Color3.fromRGB(255, 250, 200) },
	Voidtouched = { Id = "Voidtouched", Mult = 15, Chance = 0.0005, Color = Color3.fromRGB(90, 0, 140) },
	Eclipsed = { Id = "Eclipsed", Mult = 40, Chance = 0.003, Color = Color3.fromRGB(255, 60, 0), EclipseOnly = true },
	Rainbow = { Id = "Rainbow", Mult = 25, Chance = 0.0001, Color = Color3.fromRGB(255, 0, 255) },
	-- Seasonal: only rolls while a seasonal event is active (EventConfig), also sold in the Candy Shop.
	Haunted = { Id = "Haunted", Mult = 10, Chance = 0.01, Color = Color3.fromRGB(255, 130, 20), EventOnly = true },
} :: { [string]: Mutation }

-- "Ascension": on hatch, chance for the soul to jump one rarity tier. Scales with luck.
PetConfig.AscendBaseChance = 0.03
PetConfig.AscendMaxChance = 0.5

-- Max pets that can be stored off-pedestal is GameConfig.InventoryCap.
-- Sell value of a pet = its income/sec * SellSeconds
PetConfig.SellSeconds = 60

function PetConfig.GetRarity(id: string): Rarity
	return PetConfig.Rarities[id] or PetConfig.Rarities.Common
end

function PetConfig.GetMutation(id: string?): Mutation
	return PetConfig.Mutations[id or "None"] or PetConfig.Mutations.None
end

function PetConfig.NextRarity(id: string): string
	local r = PetConfig.GetRarity(id)
	return PetConfig.RarityOrder[math.min(r.Order + 1, #PetConfig.RarityOrder)]
end

return PetConfig
