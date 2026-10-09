--[[
	EventConfig
	Limited-time seasonal events. Only one runs at a time.
	Hallow-Soul Festival (Halloween): spooky lighting + decorations, Candy pumpkins to collect,
	Candy from every delivered soul, the event-only "Haunted" mutation (x10), and a Candy Shop.

	To end the event early set Active = false. It also auto-ends at EndsAt (unix time, UTC).
]]

local EventConfig = {
	Active = true,
	Id = "Halloween2026",
	Name = "Hallow-Soul Festival",
	EndsAt = 1793577600, -- 2026-11-02 00:00 UTC
	Currency = "Candy",

	-- Candy pumpkins scattered around the hub and biomes
	MaxPumpkins = 30,
	PumpkinRespawnSeconds = 6,
	PumpkinCandy = { Min = 1, Max = 4 },
	GoldenPumpkinChance = 0.05, -- golden pumpkins give 15 candy
	GoldenPumpkinCandy = 15,

	-- Candy for delivering a soul home = DeliverCandyBase + rarity order (Common 1 ... Secret 7)
	DeliverCandyBase = 1,

	-- Haunted mutation chance during the event (x10 income). See PetConfig.Mutations.Haunted.

	-- Candy Shop. Orb entries come from the player's best unlocked biome with a guaranteed mutation.
	Shop = {
		{ Id = "HauntedRare", Name = "Haunted Rare Soul", Desc = "Guaranteed Haunted (x10)", Cost = 60, Orb = { Rarity = "Rare", Mutation = "Haunted" } },
		{ Id = "HauntedEpic", Name = "Haunted Epic Soul", Desc = "Guaranteed Haunted (x10)", Cost = 180, Orb = { Rarity = "Epic", Mutation = "Haunted" } },
		{ Id = "HauntedLegendary", Name = "Haunted Legendary Soul", Desc = "Guaranteed Haunted (x10)", Cost = 600, Orb = { Rarity = "Legendary", Mutation = "Haunted" } },
		{ Id = "HauntedMythic", Name = "Haunted Mythic Soul", Desc = "Guaranteed Haunted (x10)", Cost = 2000, Orb = { Rarity = "Mythic", Mutation = "Haunted" } },
		{ Id = "CandyLuck", Name = "Witch's Brew (15m)", Desc = "2x Luck for 15 minutes", Cost = 40, Boost = { Kind = "Luck2x", Seconds = 900 } },
		{ Id = "CandyEssence", Name = "Pumpkin Spice (15m)", Desc = "2x Essence for 15 minutes", Cost = 60, Boost = { Kind = "Essence2x", Seconds = 900 } },
	},

	-- Lighting while the event runs
	Lighting = {
		OutdoorAmbient = Color3.fromRGB(110, 70, 120),
		FogColor = Color3.fromRGB(60, 30, 70),
		AtmosphereDensity = 0.38,
		AtmosphereColor = Color3.fromRGB(200, 120, 60),
		Tint = Color3.fromRGB(255, 225, 200),
	},
}

function EventConfig.IsActive(): boolean
	return EventConfig.Active and os.time() < EventConfig.EndsAt
end

return EventConfig
