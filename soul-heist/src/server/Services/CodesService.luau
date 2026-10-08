--[[
	CodesService
	Redeemable promo codes (definitions in ServerScriptService/Server/Config/Codes - never replicated).
	RedeemCode(code) -> { ok, msg }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Codes = require(script.Parent.Parent.Config.Codes)

local CodesService = {}

local Services: any
local MAX_CODE_LENGTH = 32

local function normalize(code: any): string?
	if type(code) ~= "string" or #code == 0 or #code > MAX_CODE_LENGTH then
		return nil
	end
	local cleaned = string.upper((string.gsub(code, "%s+", "")))
	if not string.match(cleaned, "^[%w_]+$") then
		return nil
	end
	return cleaned
end

local function grantRewards(player: Player, rewards: any): { string }
	local granted = {}
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
		Services.PetService:GiveOrb(player, { Rarity = rewards.Orb.Rarity, Biome = biome })
		table.insert(granted, rewards.Orb.Rarity .. " Soul")
	end
	return granted
end

function CodesService:Redeem(player: Player, rawCode: any)
	if not RateLimiter.Check(player, "Code", 2) then
		return { ok = false, msg = "Wait a moment before trying another code." }
	end
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return { ok = false, msg = "Data not loaded yet." }
	end
	local code = normalize(rawCode)
	local entry = code and Codes[code]
	if not code or not entry then
		return { ok = false, msg = "Invalid code." }
	end
	if data.RedeemedCodes[code] then
		return { ok = false, msg = "You already redeemed this code." }
	end
	if entry.Expires and os.time() > entry.Expires then
		return { ok = false, msg = "This code has expired." }
	end
	if entry.MinRebirths and data.Rebirths < entry.MinRebirths then
		return { ok = false, msg = "Requires " .. entry.MinRebirths .. " rebirth(s)." }
	end
	data.RedeemedCodes[code] = true
	local granted = grantRewards(player, entry.Rewards)
	Services.PlayerDataService:MarkDirty(player)
	return { ok = true, msg = "Redeemed: " .. table.concat(granted, ", ") }
end

function CodesService:Init(services)
	Services = services
end

function CodesService:Start()
	Remotes.Function("RedeemCode").OnServerInvoke = function(player, code)
		return self:Redeem(player, code)
	end
end

return CodesService
