--[[
	AbilityConfig
	Companion spirits: pick ONE spirit to follow you. Its biome decides your active ability (key Q).
	Rarer companions recharge faster (-6% cooldown per rarity tier above Common; mutated -10% more).
	This is the core difference from other steal games: your spirits help you pull off the heist.
]]

export type Ability = {
	Id: string,
	Name: string,
	Desc: string,
	Cooldown: number,
	Power: number?,
	Radius: number?,
	Duration: number?,
	SpeedMult: number?,
}

local AbilityConfig = {}

AbilityConfig.ByBiome = {
	Meadow = { Id = "WispRush", Name = "Wisp Rush", Desc = "+35% speed for 3s", Cooldown = 18, SpeedMult = 1.35, Duration = 3 },
	Ember = { Id = "FlameDash", Name = "Flame Dash", Desc = "Burst forward", Cooldown = 14, Power = 110 },
	Frost = { Id = "FrostNova", Name = "Frost Nova", Desc = "Freeze guardians within 30 studs for 3s", Cooldown = 25, Radius = 30, Duration = 3 },
	Crypt = { Id = "GraveVeil", Name = "Grave Veil", Desc = "Guardians can't see you for 4s", Cooldown = 28, Duration = 4 },
	Storm = { Id = "LightningStep", Name = "Lightning Step", Desc = "Huge dash + 20% speed for 2s", Cooldown = 16, Power = 160, SpeedMult = 1.2, Duration = 2 },
	Void = { Id = "ShadowCloak", Name = "Shadow Cloak", Desc = "Invisible to guardians AND players for 5s", Cooldown = 32, Duration = 5 },
	Celestial = { Id = "HaloWard", Name = "Halo Ward", Desc = "Blocks the next catch or bonk (8s)", Cooldown = 30, Duration = 8 },
	Abyssal = { Id = "ReapersRend", Name = "Reaper's Rend", Desc = "Freeze nearby guardians + 40% speed for 4s", Cooldown = 35, Radius = 35, Duration = 4, SpeedMult = 1.4 },
} :: { [string]: Ability }

AbilityConfig.CooldownReductionPerRarity = 0.06
AbilityConfig.MutatedCooldownReduction = 0.10

-- Stealth tuning used by GuardianService
AbilityConfig.Stealth = {
	ViewDot = 0.25, -- guardians see in a ~150° cone in front of them
	HearingRadius = 10, -- noticed from any direction this close
	SneakHearingRadius = 4,
	SneakSightMult = 0.55, -- sneaking shrinks how far guardians can see you
	SneakSpeedMult = 0.6, -- ...but you move slower
	NightSightMult = 0.85, -- darker nights = harder to spot (but guardians are faster)
	GlowPerRarity = 0.06, -- rarer souls glow brighter = spotted from further away
	LoseTrackSeconds = 2.5, -- break line of sight this long and the guardian gives up
	ChaseRangeMult = 1.6, -- keeps chasing up to AggroRadius x this
	BackupRadius = 45, -- spotting guardian alerts others this close
}

-- Haunt: after being robbed, the owner can curse the thief once (slow) within this window.
AbilityConfig.Haunt = { WindowSeconds = 20, SlowFactor = 0.55, Duration = 5 }

function AbilityConfig.GetCooldown(biomeId: string, rarityOrder: number, mutated: boolean): number
	local ability = AbilityConfig.ByBiome[biomeId] or AbilityConfig.ByBiome.Meadow
	local reduction = (rarityOrder - 1) * AbilityConfig.CooldownReductionPerRarity + (mutated and AbilityConfig.MutatedCooldownReduction or 0)
	return math.max(4, ability.Cooldown * (1 - reduction))
end

return AbilityConfig
