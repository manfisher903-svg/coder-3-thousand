--[[
	RebirthService
	Rebirth = reset run progress for a permanent income multiplier + Rebirth Tokens.

	Cost(n)   = 10M × 3.2^n Essence          (n = rebirths so far)
	Mult      = 1 + 0.5 × rebirths            (applied to all income, forever)
	Tokens    = 1 + floor(rebirthsAfter / 3)  (spend on permanent perks)
	RESETS    : Essence, Speed, Soul Harness, Treadmill tier (unless Treadmill Memory), every pedestal,
	            all spirits EXCEPT locked ones up to Vault size
	KEEPS     : pedestal count, Rebirths, tokens, perks, locked spirits (vault), pending orbs, passes, codes
	Vault     = 1 + floor(rebirths / 2) (+3 with Soul Vault+)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local RebirthService = {}

local Services: any

function RebirthService:GetVaultSize(player: Player): number
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return 0
	end
	return Formulas.VaultSize(data.Rebirths, Services.MonetizationService:HasPass(player, "SoulVault"))
end

function RebirthService:DoRebirth(player: Player, free: boolean): (boolean, string)
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return false, "Data not loaded"
	end
	local cost = Formulas.RebirthCost(data.Rebirths)
	if not free then
		if data.Essence < cost then
			return false, "Need " .. Format.Number(cost) .. " Essence to rebirth"
		end
	end

	-- Anything carried is lost (prevents carrying value across the reset).
	Services.StealService:Clear(player)

	-- Keep locked spirits (best first) up to vault size.
	local vaultSize = self:GetVaultSize(player)
	local locked = {}
	for _, pet in pairs(data.Pets) do
		if pet.Locked then
			table.insert(locked, pet)
		end
	end
	table.sort(locked, function(a, b)
		return Formulas.PetIncome(a.Rarity, a.Biome, a.Mutation) > Formulas.PetIncome(b.Rarity, b.Biome, b.Mutation)
	end)
	local keptPets = {}
	for i = 1, math.min(vaultSize, #locked) do
		keptPets[locked[i].Id] = locked[i]
	end

	data.Pets = keptPets
	data.Slots = {}
	local slotIndex = 0
	for id in pairs(keptPets) do
		slotIndex += 1
		data.Slots[tostring(slotIndex)] = { Type = "Pet", PetId = id }
	end

	data.Rebirths += 1
	data.RebirthTokens += Formulas.RebirthTokens(data.Rebirths)
	data.Essence = EconomyConfig.StartingEssence
	data.Speed = EconomyConfig.StartingSpeed + (data.Perks.SwiftStart or 0) * EconomyConfig.Perks.SwiftStart.PerLevel
	data.CarryLevel = 0
	if (data.Perks.TreadmillMemory or 0) < 1 then
		data.TreadmillTier = 1
	end

	-- Kept pets may exceed active pedestals in odd cases; overflow simply stays in inventory.
	local active = Services.PetService:GetActivePedestalCount(player)
	for key in pairs(data.Slots) do
		if (tonumber(key) :: number) > active then
			data.Slots[key] = nil
		end
	end

	Services.PetService:RenderBase(player)
	Services.EconomyService:Recalculate(player)
	Services.CompanionService:Refresh(player) -- companion may not have survived the rebirth
	Services.StealService:RefreshWalkSpeed(player)
	Services.BaseService:TeleportHome(player)
	Services.PlayerDataService:Replicate(player)
	Services.PlayerDataService:MarkDirty(player)

	Remotes.Event("Announce"):FireAllClients(
		string.format("%s REBIRTHED! (Rebirth %d - x%.1f Essence forever)", player.DisplayName, data.Rebirths, Formulas.RebirthMultiplier(data.Rebirths)),
		Color3.fromRGB(255, 120, 255)
	)
	-- Save immediately: rebirth is a big state change worth protecting.
	task.spawn(Services.PlayerDataService.SaveAsync, Services.PlayerDataService, player, false)
	return true, "Rebirth complete!"
end

function RebirthService:BuyPerk(player: Player, perkId: any): (boolean, string)
	local data = Services.PlayerDataService:GetData(player)
	if not data or type(perkId) ~= "string" or not EconomyConfig.Perks[perkId] then
		return false, "Unknown perk"
	end
	local level = data.Perks[perkId] or 0
	local cost = Formulas.PerkCost(perkId, level)
	if not cost then
		return false, "Perk maxed!"
	end
	if data.RebirthTokens < cost then
		return false, "Need " .. cost .. " Rebirth Tokens"
	end
	data.RebirthTokens -= cost
	data.Perks[perkId] = level + 1
	Services.EconomyService:Recalculate(player)
	Services.PlayerDataService:Replicate(player)
	Services.PlayerDataService:MarkDirty(player)
	return true, EconomyConfig.Perks[perkId].Name .. " -> level " .. (level + 1)
end

function RebirthService:Init(services)
	Services = services
end

function RebirthService:Start()
	Remotes.Function("RequestRebirth").OnServerInvoke = function(player)
		if not RateLimiter.Check(player, "Rebirth", 2) then
			return { ok = false, msg = "Slow down!" }
		end
		local ok, msg = self:DoRebirth(player, false)
		return { ok = ok, msg = msg }
	end

	Remotes.Function("BuyPerk").OnServerInvoke = function(player, perkId)
		if not RateLimiter.Check(player, "Perk", 0.3) then
			return { ok = false, msg = "Slow down!" }
		end
		local ok, msg = self:BuyPerk(player, perkId)
		return { ok = ok, msg = msg }
	end
end

return RebirthService
