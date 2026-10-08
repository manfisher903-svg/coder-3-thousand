--[[
	Formulas
	Pure math shared by server (authoritative) and client (UI previews). No side effects.
]]

local Config = script.Parent:WaitForChild("Config")
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local PetConfig = require(Config:WaitForChild("PetConfig"))
local BiomeConfig = require(Config:WaitForChild("BiomeConfig"))

local Formulas = {}

-- Speed ------------------------------------------------------------------
function Formulas.SpeedCost(currentSpeed: number): number
	return math.floor(EconomyConfig.SpeedBaseCost * EconomyConfig.SpeedGrowth ^ (currentSpeed - 16))
end

-- Total cost to buy `count` speed points starting at currentSpeed (geometric series).
function Formulas.SpeedCostBulk(currentSpeed: number, count: number): number
	local total = 0
	for i = 0, count - 1 do
		total += Formulas.SpeedCost(currentSpeed + i)
	end
	return total
end

-- How many points can be afforded with `essence`, up to `maxPoints`.
function Formulas.SpeedAffordable(currentSpeed: number, essence: number, maxPoints: number): (number, number)
	local count, total = 0, 0
	while count < maxPoints do
		local nextCost = Formulas.SpeedCost(currentSpeed + count)
		if total + nextCost > essence then
			break
		end
		total += nextCost
		count += 1
	end
	return count, total
end

function Formulas.TreadmillCap(tier: number): number
	local t = EconomyConfig.Treadmill[math.clamp(tier, 1, #EconomyConfig.Treadmill)]
	return t.Cap
end

-- Carry --------------------------------------------------------------------
function Formulas.CarryCost(level: number): number
	return math.floor(EconomyConfig.CarryBaseCost * EconomyConfig.CarryGrowth ^ level)
end

function Formulas.CarryReduction(level: number): number
	return math.min(level, EconomyConfig.CarryMaxLevel) * EconomyConfig.CarryReductionPerLevel
end

-- WalkSpeed while carrying a soul of `rarityId`.
function Formulas.CarriedSpeed(speed: number, rarityId: string, carryLevel: number, phantom: boolean): number
	local heaviness = PetConfig.GetRarity(rarityId).Heaviness
	local reduction = Formulas.CarryReduction(carryLevel) + (phantom and 0.25 or 0)
	local slow = heaviness * math.max(0, 1 - reduction)
	return speed * (1 - slow)
end

-- Pedestals ----------------------------------------------------------------
function Formulas.PedestalCost(currentCount: number): number
	-- cost of buying pedestal number currentCount + 1
	local n = currentCount + 1
	return math.floor(EconomyConfig.PedestalBaseCost * EconomyConfig.PedestalGrowth ^ (n - 4))
end

-- Rebirth -------------------------------------------------------------------
function Formulas.RebirthCost(rebirths: number): number
	return math.floor(EconomyConfig.RebirthBaseCost * EconomyConfig.RebirthGrowth ^ rebirths)
end

function Formulas.RebirthMultiplier(rebirths: number): number
	return 1 + EconomyConfig.RebirthMultPerRebirth * rebirths
end

function Formulas.RebirthTokens(rebirthsAfter: number): number
	return EconomyConfig.RebirthTokensBase + math.floor(rebirthsAfter / 3)
end

function Formulas.VaultSize(rebirths: number, hasVaultPass: boolean): number
	return EconomyConfig.VaultBaseSize + math.floor(rebirths / 2) + (hasVaultPass and EconomyConfig.VaultPassBonus or 0)
end

function Formulas.PerkCost(perkId: string, currentLevel: number): number?
	local perk = EconomyConfig.Perks[perkId]
	if not perk or currentLevel >= perk.MaxLevel then
		return nil
	end
	return perk.CostBase + perk.CostPerLevel * currentLevel
end

-- Pets ------------------------------------------------------------------------
function Formulas.PetIncome(rarityId: string, biomeId: string, mutationId: string?): number
	local rarity = PetConfig.GetRarity(rarityId)
	local biome = BiomeConfig.Get(biomeId)
	local mutation = PetConfig.GetMutation(mutationId)
	return rarity.BaseIncome * biome.IncomeMult * mutation.Mult
end

function Formulas.HatchSeconds(rarityId: string, biomeId: string, fastHatch: boolean, quickIncubationLevel: number): number
	local base = PetConfig.GetRarity(rarityId).HatchSeconds * BiomeConfig.Get(biomeId).HatchMult
	local perkMult = 1 - math.min(quickIncubationLevel, 8) * EconomyConfig.Perks.QuickIncubation.PerLevel
	local passMult = fastHatch and 0.5 or 1
	return math.max(3, math.floor(base * perkMult * passMult))
end

return Formulas
