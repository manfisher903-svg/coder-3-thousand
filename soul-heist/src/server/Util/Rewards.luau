--[[
	Rewards
	One reward format for codes, daily streak, playtime gifts, quests and the event shop.
		{ Essence, IncomeSeconds, Boost = {Kind, Seconds}, Orb = {Rarity, Biome = "Best"|id, Mutation?}, Candy }
	Rewards.Grant(Services, player, rewards) -> { "500 Essence", "Epic Soul", ... } (human-readable list)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)

local Rewards = {}

function Rewards.Grant(Services: any, player: Player, rewards: any): { string }
	local granted = {}
	if type(rewards) ~= "table" then
		return granted
	end
	local essence = rewards.Essence or 0
	if rewards.IncomeSeconds then
		essence = math.max(essence, math.floor(Services.EconomyService:GetIncome(player) * rewards.IncomeSeconds))
	end
	if essence > 0 then
		Services.EconomyService:AddEssence(player, essence)
		table.insert(granted, Format.Number(essence) .. " Essence")
	end
	if rewards.Boost then
		Services.EconomyService:AddBoost(player, rewards.Boost.Kind, rewards.Boost.Seconds)
		table.insert(granted, rewards.Boost.Kind .. " (" .. Format.Time(rewards.Boost.Seconds) .. ")")
	end
	if rewards.Orb then
		local biome = rewards.Orb.Biome
		if biome == "Best" or biome == nil then
			biome = Services.PetService:GetBestBiome(player)
		end
		Services.PetService:GiveOrb(player, { Rarity = rewards.Orb.Rarity, Biome = biome, Mutation = rewards.Orb.Mutation })
		local prefix = rewards.Orb.Mutation and (rewards.Orb.Mutation .. " ") or ""
		table.insert(granted, prefix .. rewards.Orb.Rarity .. " Soul")
	end
	if rewards.Candy and rewards.Candy > 0 and Services.EventService:IsActive() then
		Services.EventService:AddCandy(player, rewards.Candy, false)
		table.insert(granted, rewards.Candy .. " Candy")
	end
	Services.PlayerDataService:MarkDirty(player)
	return granted
end

return Rewards
