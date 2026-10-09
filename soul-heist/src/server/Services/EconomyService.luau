--[[
	EconomyService
	Passive income, multipliers, luck, timed boosts, offline earnings.

	Income/sec = Σ(placed pet income) × RebirthMult × AttunementMult × SocialMult × PassMult × BoostMult × IndexMult
		RebirthMult    = 1 + 0.5 × rebirths
		AttunementMult = 1 + 0.10 × Attunement perk level
		SocialMult     = 1 + Premium(0.10) + Group(0.10) + VIP(0.10) + 0.10 × friends in server (max 4)
		PassMult       = 2 with the 2x Essence pass
		BoostMult      = 2 while a 2x Essence potion is active (stacks with the pass -> 4x)
		IndexMult      = 1 + 0.01 × unique spirits discovered (Spirit Index)

	Luck = SuperLuckPass(2) × Potion(2 or 5) × (1 + 0.10 × Soul Magnet level)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Formulas = require(Shared.Formulas)
local RewardConfig = require(Shared.Config.RewardConfig)
local Format = require(Shared.Util.Format)

local EconomyService = {}

local Services: any
local incomeCache: { [Player]: number } = {}
local friendsWith: { [Player]: { [Player]: boolean } } = {}
local groupMember: { [Player]: boolean } = {}

local function countKeys(map: { [any]: any }?): number
	local count = 0
	for _ in pairs(map or {}) do
		count += 1
	end
	return count
end

-- Multipliers -----------------------------------------------------------------------------
local function countFriendsInServer(player: Player): number
	local count = 0
	local map = friendsWith[player]
	if map then
		for other, isFriend in pairs(map) do
			if isFriend and other.Parent then
				count += 1
			end
		end
	end
	return math.min(count, GameConfig.MaxFriendBonuses)
end

function EconomyService:GetMultiplierBreakdown(player: Player)
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return { Total = 1 }
	end
	local monetization = Services.MonetizationService
	local social = 1
	if player.MembershipType == Enum.MembershipType.Premium then
		social += GameConfig.PremiumIncomeBonus
	end
	if groupMember[player] then
		social += GameConfig.GroupIncomeBonus
	end
	if monetization:HasPass(player, "VIP") then
		social += MonetizationConfig.Effects.VIPIncomeBonus
	end
	social += countFriendsInServer(player) * GameConfig.FriendIncomeBonus

	local breakdown = {
		Rebirth = Formulas.RebirthMultiplier(data.Rebirths),
		Attunement = 1 + (data.Perks.Attunement or 0) * EconomyConfig.Perks.Attunement.PerLevel,
		Social = social,
		Pass = monetization:HasPass(player, "DoubleEssence") and 2 or 1,
		Boost = (data.Boosts.Essence2x or 0) > 0 and 2 or 1,
		Index = 1 + countKeys(data.Index) * RewardConfig.IndexBonusPerSpecies,
	}
	breakdown.Total = breakdown.Rebirth * breakdown.Attunement * breakdown.Social * breakdown.Pass * breakdown.Boost * breakdown.Index
	return breakdown
end

function EconomyService:GetLuck(player: Player): number
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return 1
	end
	local luck = 1
	if Services.MonetizationService:HasPass(player, "SuperLuck") then
		luck *= 2
	end
	if (data.Boosts.Luck5x or 0) > 0 then
		luck *= 5
	elseif (data.Boosts.Luck2x or 0) > 0 then
		luck *= 2
	end
	luck *= 1 + (data.Perks.SoulMagnet or 0) * EconomyConfig.Perks.SoulMagnet.PerLevel
	return luck
end

-- Income -------------------------------------------------------------------------------------
function EconomyService:GetBaseIncome(player: Player): number
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return 0
	end
	local total = 0
	local active = Services.PetService:GetActivePedestalCount(player)
	for i = 1, active do
		local slot = data.Slots[tostring(i)]
		if slot and slot.Type == "Pet" then
			local pet = data.Pets[slot.PetId]
			if pet then
				total += Formulas.PetIncome(pet.Rarity, pet.Biome, pet.Mutation)
			end
		end
	end
	return total
end

function EconomyService:Recalculate(player: Player)
	if not Services.PlayerDataService:IsLoaded(player) then
		return
	end
	local income = self:GetBaseIncome(player) * self:GetMultiplierBreakdown(player).Total
	incomeCache[player] = income
	player:SetAttribute("Income", income)
	player:SetAttribute("Luck", self:GetLuck(player))
	Services.PlayerDataService:MarkDirty(player)
end

function EconomyService:GetIncome(player: Player): number
	return incomeCache[player] or 0
end

-- Essence ---------------------------------------------------------------------------------------
function EconomyService:AddEssence(player: Player, amount: number)
	local data = Services.PlayerDataService:GetData(player)
	if not data or amount ~= amount or amount <= 0 or amount == math.huge then
		return
	end
	data.Essence += amount
	data.Stats.TotalEssence += amount
	Services.PlayerDataService:Replicate(player)
end

function EconomyService:CanAfford(player: Player, cost: number): boolean
	local data = Services.PlayerDataService:GetData(player)
	return data ~= nil and data.Essence >= cost
end

-- Atomically checks and spends. Returns true on success.
function EconomyService:TrySpend(player: Player, cost: number): boolean
	local data = Services.PlayerDataService:GetData(player)
	if not data or cost ~= cost or cost < 0 or data.Essence < cost then
		return false
	end
	data.Essence -= cost
	Services.PlayerDataService:Replicate(player)
	return true
end

-- Boosts ---------------------------------------------------------------------------------------------
function EconomyService:AddBoost(player: Player, kind: string, seconds: number)
	local data = Services.PlayerDataService:GetData(player)
	if not data or data.Boosts[kind] == nil then
		return
	end
	data.Boosts[kind] += seconds
	self:Recalculate(player)
end

-- Offline earnings ----------------------------------------------------------------------------------
local function grantOfflineEarnings(player: Player, data: any)
	Services.MonetizationService:WaitForPasses(player)
	if data.LastOnline <= 0 or data.LastIncome <= 0 then
		return
	end
	local elapsed = os.time() - data.LastOnline
	if elapsed < 60 then
		return
	end
	local hasPass = Services.MonetizationService:HasPass(player, "OfflineOvertime")
	local percent = hasPass and EconomyConfig.OfflinePassPercent or EconomyConfig.OfflineFreePercent
	local cap = hasPass and EconomyConfig.OfflinePassCapSeconds or EconomyConfig.OfflineFreeCapSeconds
	local amount = math.floor(data.LastIncome * math.min(elapsed, cap) * percent)
	if amount > 0 then
		EconomyService:AddEssence(player, amount)
		local tip = hasPass and "" or " (Spirit Overtime pass = 5x more!)"
		Services.PlayerDataService:Notify(player, string.format("Your spirits earned %s Essence while you were away!%s", Format.Number(amount), tip), "success")
	end
end

-- Social -------------------------------------------------------------------------------------------
local function refreshFriends(newPlayer: Player)
	friendsWith[newPlayer] = friendsWith[newPlayer] or {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= newPlayer then
			local ok, isFriend = pcall(newPlayer.IsFriendsWithAsync, newPlayer, other.UserId)
			if ok then
				friendsWith[newPlayer][other] = isFriend
				friendsWith[other] = friendsWith[other] or {}
				friendsWith[other][newPlayer] = isFriend
				if isFriend then
					EconomyService:Recalculate(other)
				end
			end
		end
	end
	EconomyService:Recalculate(newPlayer)
end

-- Lifecycle -----------------------------------------------------------------------------------------
function EconomyService:Init(services)
	Services = services
	Services.PlayerDataService.ProfileLoaded:Connect(function(player, data)
		if GameConfig.GroupId ~= 0 then
			local ok, inGroup = pcall(player.IsInGroup, player, GameConfig.GroupId)
			groupMember[player] = ok and inGroup or false
		end
		self:Recalculate(player)
		grantOfflineEarnings(player, data)
		refreshFriends(player)
	end)
end

function EconomyService:Start()
	Players.PlayerRemoving:Connect(function(player)
		incomeCache[player] = nil
		groupMember[player] = nil
		friendsWith[player] = nil
		for other, map in pairs(friendsWith) do
			if map[player] then
				map[player] = nil
				self:Recalculate(other)
			end
		end
	end)

	-- 1 Hz income tick
	task.spawn(function()
		while true do
			task.wait(1)
			for player, data in pairs(Services.PlayerDataService:GetAllLoaded()) do
				local income = incomeCache[player] or 0
				if income > 0 then
					data.Essence += income
					data.Stats.TotalEssence += income
				end
				data.LastIncome = income
				data.Stats.PlayTime += 1

				local boostExpired = false
				for kind, remaining in pairs(data.Boosts) do
					if remaining > 0 then
						data.Boosts[kind] = math.max(0, remaining - 1)
						if data.Boosts[kind] == 0 then
							boostExpired = true
						end
					end
				end
				if boostExpired then
					self:Recalculate(player)
					Services.PlayerDataService:Notify(player, "A boost has expired.", "warning")
				end
				Services.PlayerDataService:Replicate(player)
			end
		end
	end)
end

return EconomyService
