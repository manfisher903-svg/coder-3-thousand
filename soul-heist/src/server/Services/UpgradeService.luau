--[[
	UpgradeService
	Essence sinks: Speed (Treadmill), Treadmill tiers (Speed cap), Soul Harness (Carry), Pedestals.
	RequestUpgrade(kind, amount) -> { ok, msg }
		kind "Speed"     amount = 1 | 10 | "Max"
		kind "Treadmill" buys the next tier (raises the Speed cap)
		kind "Carry"     +1 Soul Harness level
		kind "Pedestal"  +1 pedestal
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local UpgradeService = {}

local Services: any

local function fail(msg: string)
	return { ok = false, msg = msg }
end

local function buySpeed(player: Player, data: any, amount: any)
	local cap = Formulas.TreadmillCap(data.TreadmillTier)
	local room = cap - data.Speed
	if room <= 0 then
		return fail("Speed capped at " .. cap .. ". Upgrade your Treadmill!")
	end
	local wanted = if amount == "Max" then room elseif amount == 10 then math.min(10, room) else 1
	local count, cost = Formulas.SpeedAffordable(data.Speed, data.Essence, wanted)
	if count == 0 then
		return fail("Need " .. Format.Number(Formulas.SpeedCost(data.Speed)) .. " Essence")
	end
	if not Services.EconomyService:TrySpend(player, cost) then
		return fail("Not enough Essence")
	end
	data.Speed += count
	Services.StealService:RefreshWalkSpeed(player)
	return { ok = true, msg = string.format("+%d Speed (now %d)", count, data.Speed) }
end

local function buyTreadmill(player: Player, data: any)
	local nextTier = EconomyConfig.Treadmill[data.TreadmillTier + 1]
	if not nextTier then
		return fail("Treadmill is maxed!")
	end
	if nextTier.RequiresRebirths and data.Rebirths < nextTier.RequiresRebirths then
		return fail("Requires " .. nextTier.RequiresRebirths .. " rebirth(s)")
	end
	if not Services.EconomyService:TrySpend(player, nextTier.Cost) then
		return fail("Need " .. Format.Number(nextTier.Cost) .. " Essence")
	end
	data.TreadmillTier += 1
	return { ok = true, msg = "Treadmill upgraded! Speed cap: " .. nextTier.Cap }
end

local function buyCarry(player: Player, data: any)
	if data.CarryLevel >= EconomyConfig.CarryMaxLevel then
		return fail("Soul Harness is maxed!")
	end
	local cost = Formulas.CarryCost(data.CarryLevel)
	if not Services.EconomyService:TrySpend(player, cost) then
		return fail("Need " .. Format.Number(cost) .. " Essence")
	end
	data.CarryLevel += 1
	Services.StealService:RefreshWalkSpeed(player)
	return { ok = true, msg = "Soul Harness level " .. data.CarryLevel }
end

local function buyPedestal(player: Player, data: any)
	if data.Pedestals >= EconomyConfig.MaxPedestals then
		return fail("All pedestals unlocked!")
	end
	local cost = Formulas.PedestalCost(data.Pedestals)
	if not Services.EconomyService:TrySpend(player, cost) then
		return fail("Need " .. Format.Number(cost) .. " Essence")
	end
	data.Pedestals += 1
	Services.PetService:RenderBase(player)
	Services.EconomyService:Recalculate(player)
	return { ok = true, msg = "New pedestal unlocked! (" .. data.Pedestals .. ")" }
end

function UpgradeService:Init(services)
	Services = services
end

function UpgradeService:Start()
	Remotes.Function("RequestUpgrade").OnServerInvoke = function(player, kind, amount)
		if not RateLimiter.Check(player, "Upgrade", 0.1) then
			return fail("Slow down!")
		end
		local data = Services.PlayerDataService:GetData(player)
		if not data then
			return fail("Data not loaded yet")
		end
		local result
		if kind == "Speed" then
			result = buySpeed(player, data, amount)
		elseif kind == "Treadmill" then
			result = buyTreadmill(player, data)
		elseif kind == "Carry" then
			result = buyCarry(player, data)
		elseif kind == "Pedestal" then
			result = buyPedestal(player, data)
		else
			return fail("Unknown upgrade")
		end
		Services.PlayerDataService:Replicate(player)
		Services.PlayerDataService:MarkDirty(player)
		return result
	end
end

return UpgradeService
