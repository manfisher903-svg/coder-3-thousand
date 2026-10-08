--[[
	BiomeConfig
	Each biome = a guarded zone that spawns Soul Orbs. Deeper biomes are further from the bases,
	need more Speed to enter, spawn more valuable souls and are guarded by faster guardians.

	Workspace.Biomes.<Id> must contain (WorldBuilder generates a greybox if missing):
		Zone            Part   - invisible box covering the biome (its -Z / Front face points to the bases)
		SoulSpawns      Folder - Parts where orbs appear
		GuardianSpawns  Folder - Parts where guardians start (optional, falls back to Zone centre)
		GateReturn      Part   - (optional) where under-speed players get pushed back to
]]

export type GuardianAbility = {
	Type: "SlowPulse" | "Blink",
	Cooldown: number,
	Radius: number?,
	SlowFactor: number?,
	Duration: number?,
	MinDistance: number?,
	BehindDistance: number?,
}

export type Guardian = {
	Name: string,
	Speed: number,
	Count: number,
	AggroRadius: number,
	CatchRadius: number,
	Scale: number,
	Color: Color3,
	Ability: GuardianAbility?,
}

export type Biome = {
	Id: string,
	Name: string,
	Order: number,
	SpeedRequired: number,
	IncomeMult: number,
	HatchMult: number,
	MaxOrbs: number,
	RespawnSeconds: number,
	Color: Color3,
	Guardian: Guardian,
	Species: { [string]: string },
}

local BiomeConfig = {}

BiomeConfig.Order = { "Meadow", "Ember", "Frost", "Crypt", "Storm", "Void", "Celestial", "Abyssal" }

BiomeConfig.Biomes = {
	Meadow = {
		Id = "Meadow", Name = "Whispering Meadow", Order = 1,
		SpeedRequired = 16, IncomeMult = 1, HatchMult = 1.0,
		MaxOrbs = 10, RespawnSeconds = 3, Color = Color3.fromRGB(110, 190, 90),
		Guardian = {
			Name = "Wisp Sentry", Speed = 12, Count = 2, AggroRadius = 35, CatchRadius = 4.5,
			Scale = 1, Color = Color3.fromRGB(200, 255, 200),
		},
		Species = {
			Common = "Wisplet", Uncommon = "Glowmoth", Rare = "Fernling", Epic = "Dewdrop Sprite",
			Legendary = "Meadow Monarch", Mythic = "Elder Willowshade", Secret = "The First Whisper",
		},
	},
	Ember = {
		Id = "Ember", Name = "Ember Hollow", Order = 2,
		SpeedRequired = 22, IncomeMult = 3, HatchMult = 1.15,
		MaxOrbs = 10, RespawnSeconds = 4, Color = Color3.fromRGB(200, 80, 40),
		Guardian = {
			Name = "Cinder Hound", Speed = 16, Count = 3, AggroRadius = 40, CatchRadius = 4.5,
			Scale = 1, Color = Color3.fromRGB(255, 110, 40),
		},
		Species = {
			Common = "Cinderpup", Uncommon = "Ashling", Rare = "Flickerfox", Epic = "Magma Imp",
			Legendary = "Phoenix Wraith", Mythic = "Inferno Djinn", Secret = "Heart of the Hollow",
		},
	},
	Frost = {
		Id = "Frost", Name = "Frostveil Peaks", Order = 3,
		SpeedRequired = 30, IncomeMult = 9, HatchMult = 1.3,
		MaxOrbs = 9, RespawnSeconds = 5, Color = Color3.fromRGB(170, 220, 255),
		Guardian = {
			Name = "Glacial Warden", Speed = 20, Count = 3, AggroRadius = 45, CatchRadius = 5,
			Scale = 1.2, Color = Color3.fromRGB(150, 220, 255),
			Ability = { Type = "SlowPulse", Cooldown = 8, Radius = 18, SlowFactor = 0.6, Duration = 2 },
		},
		Species = {
			Common = "Snowsoul", Uncommon = "Frostkit", Rare = "Icicle Owl", Epic = "Glacier Golem",
			Legendary = "Aurora Stag", Mythic = "Rimefang Wyrm", Secret = "Winter's Last Breath",
		},
	},
	Crypt = {
		Id = "Crypt", Name = "Sunken Crypt", Order = 4,
		SpeedRequired = 40, IncomeMult = 25, HatchMult = 1.45,
		MaxOrbs = 9, RespawnSeconds = 6, Color = Color3.fromRGB(90, 90, 110),
		Guardian = {
			Name = "Bone Knight", Speed = 26, Count = 3, AggroRadius = 45, CatchRadius = 5,
			Scale = 1.3, Color = Color3.fromRGB(230, 225, 200),
			Ability = { Type = "SlowPulse", Cooldown = 7, Radius = 16, SlowFactor = 0.55, Duration = 1.5 },
		},
		Species = {
			Common = "Bonewisp", Uncommon = "Ghoulet", Rare = "Lantern Lich", Epic = "Grave Knight",
			Legendary = "Banshee Queen", Mythic = "Crypt Colossus", Secret = "The Nameless King",
		},
	},
	Storm = {
		Id = "Storm", Name = "Storm Spire", Order = 5,
		SpeedRequired = 52, IncomeMult = 70, HatchMult = 1.6,
		MaxOrbs = 8, RespawnSeconds = 7, Color = Color3.fromRGB(80, 110, 170),
		Guardian = {
			Name = "Thunder Djinn", Speed = 32, Count = 3, AggroRadius = 50, CatchRadius = 5,
			Scale = 1.3, Color = Color3.fromRGB(120, 200, 255),
			Ability = { Type = "Blink", Cooldown = 9, MinDistance = 22, BehindDistance = 9 },
		},
		Species = {
			Common = "Sparkling", Uncommon = "Zephyr Kit", Rare = "Thunder Ram", Epic = "Storm Roc",
			Legendary = "Tempest Titan", Mythic = "Skyfather Shade", Secret = "Eye of the Storm",
		},
	},
	Void = {
		Id = "Void", Name = "Void Rift", Order = 6,
		SpeedRequired = 66, IncomeMult = 200, HatchMult = 1.8,
		MaxOrbs = 8, RespawnSeconds = 8, Color = Color3.fromRGB(40, 10, 60),
		Guardian = {
			Name = "Void Stalker", Speed = 40, Count = 4, AggroRadius = 55, CatchRadius = 5.5,
			Scale = 1.4, Color = Color3.fromRGB(120, 40, 200),
			Ability = { Type = "Blink", Cooldown = 7, MinDistance = 20, BehindDistance = 8 },
		},
		Species = {
			Common = "Voidmite", Uncommon = "Shadowlurker", Rare = "Riftwalker", Epic = "Null Serpent",
			Legendary = "Abyss Watcher", Mythic = "Event Horizon", Secret = "The Hollow Star",
		},
	},
	Celestial = {
		Id = "Celestial", Name = "Celestial Garden", Order = 7,
		SpeedRequired = 82, IncomeMult = 600, HatchMult = 2.0,
		MaxOrbs = 7, RespawnSeconds = 9, Color = Color3.fromRGB(255, 240, 180),
		Guardian = {
			Name = "Seraph Sentinel", Speed = 50, Count = 4, AggroRadius = 60, CatchRadius = 6,
			Scale = 1.5, Color = Color3.fromRGB(255, 255, 220),
			Ability = { Type = "SlowPulse", Cooldown = 6, Radius = 22, SlowFactor = 0.6, Duration = 1.5 },
		},
		Species = {
			Common = "Starlet", Uncommon = "Moonhare", Rare = "Comet Koi", Epic = "Seraphling",
			Legendary = "Solar Archon", Mythic = "Galaxy Leviathan", Secret = "Origin Soul",
		},
	},
	Abyssal = {
		Id = "Abyssal", Name = "Abyssal Throne", Order = 8,
		SpeedRequired = 100, IncomeMult = 2000, HatchMult = 2.3,
		MaxOrbs = 6, RespawnSeconds = 10, Color = Color3.fromRGB(110, 0, 20),
		Guardian = {
			Name = "The Soul Reaper", Speed = 62, Count = 2, AggroRadius = 70, CatchRadius = 7,
			Scale = 2.2, Color = Color3.fromRGB(20, 20, 20),
			Ability = { Type = "Blink", Cooldown = 6, MinDistance = 18, BehindDistance = 10 },
		},
		Species = {
			Common = "Soulshard", Uncommon = "Dread Wisp", Rare = "Chain Revenant", Epic = "Reaper's Hound",
			Legendary = "Throne Wraith", Mythic = "Soul Devourer", Secret = "The Reaper's Reflection",
		},
	},
} :: { [string]: Biome }

function BiomeConfig.Get(id: string): Biome
	return BiomeConfig.Biomes[id] or BiomeConfig.Biomes.Meadow
end

return BiomeConfig
