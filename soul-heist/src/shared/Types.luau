--[[
	Types
	Shape of the saved player profile. Keep in sync with PlayerDataService.DEFAULT_DATA.
]]

export type OrbData = {
	Rarity: string,
	Biome: string,
}

-- Pedestal contents. Slots are stored as a dictionary keyed by tostring(index)
-- (DataStores cannot hold arrays with holes).
export type SlotData = {
	Type: "Orb" | "Pet",
	-- Orb
	Rarity: string?,
	Biome: string?,
	HatchEnd: number?, -- os.time() when it hatches
	HatchDuration: number?,
	-- Pet
	PetId: string?,
}

export type PetData = {
	Id: string,
	Species: string,
	Rarity: string,
	Biome: string,
	Mutation: string,
	Locked: boolean,
	HatchedAt: number,
}

export type PlayerData = {
	Version: number,
	Essence: number,
	Speed: number,
	CarryLevel: number,
	TreadmillTier: number,
	Pedestals: number,
	Rebirths: number,
	RebirthTokens: number,
	Perks: { [string]: number },
	Pets: { [string]: PetData },
	NextPetId: number,
	Slots: { [string]: SlotData },
	PendingOrbs: { OrbData },
	Boosts: { [string]: number }, -- seconds remaining (ticks only while online)
	RedeemedCodes: { [string]: boolean },
	ProcessedReceipts: { string },
	StarterPackBought: boolean,
	ShieldUntil: number,
	LastRobbed: { Rarity: string, Biome: string, Time: number }?,
	LastOnline: number,
	LastIncome: number,
	Stats: {
		TotalEssence: number,
		Steals: number,
		BaseSteals: number,
		TimesRobbed: number,
		Hatched: number,
		PlayTime: number,
		RobuxSpent: number,
	},
}

return {}
