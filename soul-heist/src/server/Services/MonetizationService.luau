--[[
	MonetizationService
	Game Pass ownership + Developer Product receipts.

	ProcessReceipt follows Roblox's required pattern:
	  1. Player must be in THIS server with data loaded, otherwise NotProcessedYet (Roblox retries later).
	  2. PurchaseId already in data.ProcessedReceipts -> PurchaseGranted (idempotent, never double-grant).
	  3. Grant, record the PurchaseId, then SAVE. Only return PurchaseGranted if the save succeeded.
	     If the server crashes before saving, Roblox re-sends the receipt and the grant happens again,
	     which is correct because the old grant was never persisted.
	Products whose effect can't apply right now (e.g. Instant Hatch with nothing incubating) give
	Essence compensation instead of failing, so a paid purchase is never wasted.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)

local MonetizationService = {}

local Services: any
local owned: { [Player]: { [string]: boolean } } = {}
local passesLoaded: { [Player]: boolean } = {}
local Effects = MonetizationConfig.Effects
local MAX_RECEIPT_HISTORY = 100

-- Game Passes ---------------------------------------------------------------------------------------
function MonetizationService:HasPass(player: Player, key: string): boolean
	local map = owned[player]
	return map ~= nil and map[key] == true
end

function MonetizationService:GetOwnedPasses(player: Player): { [string]: boolean }
	return table.clone(owned[player] or {})
end

function MonetizationService:WaitForPasses(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 10)
	while player.Parent and not passesLoaded[player] and os.clock() < deadline do
		task.wait(0.1)
	end
end

-- Applies the immediate side-effects of owning a pass (safe to call repeatedly).
local function applyPass(player: Player, key: string)
	if not Services.PlayerDataService:IsLoaded(player) then
		return
	end
	if key == "ExtraPedestals" or key == "VIP" then
		Services.PetService:RenderBase(player)
	elseif key == "PhantomSteps" then
		Services.StealService:RefreshWalkSpeed(player)
	elseif key == "ReaperScythe" then
		Services.ToolService:GiveTools(player)
	end
	if key == "VIP" then
		player:SetAttribute("VIP", true)
	end
	Services.EconomyService:Recalculate(player)
	Services.PlayerDataService:MarkDirty(player)
end

local function applyAllPasses(player: Player)
	for key, isOwned in pairs(owned[player] or {}) do
		if isOwned then
			applyPass(player, key)
		end
	end
end

local function loadPasses(player: Player)
	local map = {}
	owned[player] = map
	for key, info in pairs(MonetizationConfig.GamePasses) do
		if GameConfig.StudioGrantAllPasses and RunService:IsStudio() then
			map[key] = true
		elseif info.Id ~= 0 then
			for _ = 1, 3 do
				local ok, result = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, info.Id)
				if ok then
					map[key] = result
					break
				end
				task.wait(1)
			end
		end
	end
	passesLoaded[player] = true
	if Services.PlayerDataService:IsLoaded(player) then
		applyAllPasses(player)
	end
end

-- Developer products ---------------------------------------------------------------------------------------
local function compensate(player: Player, reason: string)
	local amount = math.max(1_000, Services.EconomyService:GetIncome(player) * 600)
	Services.EconomyService:AddEssence(player, amount)
	Services.PlayerDataService:Notify(player, reason .. " You received " .. Format.Number(amount) .. " Essence instead.", "info")
end

local function grantEssencePack(packKey: string)
	return function(player: Player)
		local pack = EconomyConfig.EssencePacks[packKey]
		local amount = math.max(pack.Floor, math.floor(Services.EconomyService:GetIncome(player) * pack.Seconds))
		Services.EconomyService:AddEssence(player, amount)
		Services.PlayerDataService:Notify(player, "+" .. Format.Number(amount) .. " Essence!", "success")
		return true
	end
end

local function grantBoost(kind: string, label: string)
	return function(player: Player)
		Services.EconomyService:AddBoost(player, kind, Effects.BoostSeconds)
		Services.PlayerDataService:Notify(player, label .. " active for 30 minutes!", "success")
		return true
	end
end

local function grantOrb(rarity: string)
	return function(player: Player)
		local biome = Services.PetService:GetBestBiome(player)
		Services.PetService:GiveOrb(player, { Rarity = rarity, Biome = biome })
		Services.PlayerDataService:Notify(player, "A " .. rarity .. " Soul is incubating in your base!", "success")
		return true
	end
end

local ProductHandlers: { [string]: (Player, any) -> boolean } = {
	StarterPack = function(player, data)
		if data.StarterPackBought then
			compensate(player, "Starter Pack already claimed.")
			return true
		end
		data.StarterPackBought = true
		Services.PetService:GiveOrb(player, { Rarity = "Epic", Biome = Services.PetService:GetBestBiome(player) })
		Services.EconomyService:AddEssence(player, Effects.StarterPackEssence)
		Services.EconomyService:AddBoost(player, "Essence2x", Effects.BoostSeconds)
		Services.PlayerDataService:Notify(player, "Starter Pack claimed! Epic Soul + Essence + 2x boost!", "success")
		return true
	end,
	InstantHatchOne = function(player)
		if not Services.PetService:InstantHatch(player, "One") then
			compensate(player, "Nothing was incubating.")
		end
		return true
	end,
	InstantHatchAll = function(player)
		if not Services.PetService:InstantHatch(player, "All") then
			compensate(player, "Nothing was incubating.")
		end
		return true
	end,
	StealBack = function(player, data)
		local robbed = data.LastRobbed
		if robbed and os.time() - robbed.Time <= Effects.StealBackWindow then
			data.LastRobbed = nil
			Services.PetService:GiveOrb(player, { Rarity = robbed.Rarity, Biome = robbed.Biome })
			Services.PlayerDataService:Notify(player, "Soul Echo! Your " .. robbed.Rarity .. " Soul is back!", "success")
		else
			compensate(player, "No recent stolen soul to echo.")
		end
		return true
	end,
	EssenceSmall = grantEssencePack("EssenceSmall"),
	EssenceMedium = grantEssencePack("EssenceMedium"),
	EssenceLarge = grantEssencePack("EssenceLarge"),
	EssenceHuge = grantEssencePack("EssenceHuge"),
	Essence2x30 = grantBoost("Essence2x", "2x Essence"),
	Luck2x30 = grantBoost("Luck2x", "2x Luck"),
	Luck5x30 = grantBoost("Luck5x", "5x Luck"),
	BaseShield10 = function(player, data)
		data.ShieldUntil = math.max(os.time(), data.ShieldUntil or 0) + Effects.ShieldSeconds
		player:SetAttribute("ShieldUntil", data.ShieldUntil)
		Services.PlayerDataService:Notify(player, "Soul Shield up for 10 minutes!", "success")
		return true
	end,
	RebirthSkip = function(player)
		local ok = Services.RebirthService:DoRebirth(player, true)
		if not ok then
			compensate(player, "Rebirth couldn't run.")
		end
		return true
	end,
	LegendaryOrb = grantOrb("Legendary"),
	MythicOrb = grantOrb("Mythic"),
	CandySmall = function(player)
		Services.EventService:AddCandy(player, Effects.CandySmall, false)
		Services.PlayerDataService:Notify(player, "+" .. Effects.CandySmall .. " Candy!", "success")
		return true
	end,
	CandyLarge = function(player)
		Services.EventService:AddCandy(player, Effects.CandyLarge, false)
		Services.PlayerDataService:Notify(player, "+" .. Effects.CandyLarge .. " Candy!", "success")
		return true
	end,
	ServerEclipse = function(player)
		Services.DayNightService:StartEclipse(Effects.EclipseSeconds, player.DisplayName)
		return true
	end,
}

local function processReceipt(receiptInfo): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local pds = Services.PlayerDataService
	local data = pds:WaitForData(player, 15)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if table.find(data.ProcessedReceipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local key = MonetizationConfig.FindProductKey(receiptInfo.ProductId)
	local handler = key and ProductHandlers[key]
	if not handler then
		warn("[MonetizationService] No handler for product", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handler, player, data)
	if not ok then
		warn("[MonetizationService] Handler error for", key, granted)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	table.insert(data.ProcessedReceipts, purchaseId)
	while #data.ProcessedReceipts > MAX_RECEIPT_HISTORY do
		table.remove(data.ProcessedReceipts, 1)
	end
	data.Stats.RobuxSpent += receiptInfo.CurrencySpent or 0
	pds:Replicate(player)
	pds:MarkDirty(player)

	if not pds:SaveAsync(player, false) then
		-- Data is still recorded in memory (no double grant this session); Roblox will retry
		-- and the in-memory PurchaseId check above will acknowledge it.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Lifecycle ----------------------------------------------------------------------------------------------------
function MonetizationService:Init(services)
	Services = services
	MarketplaceService.ProcessReceipt = processReceipt

	-- Pass effects need the profile; apply once both are ready.
	Services.PlayerDataService.ProfileLoaded:Connect(function(player)
		if passesLoaded[player] then
			applyAllPasses(player)
		end
	end)
end

function MonetizationService:Start()
	Players.PlayerAdded:Connect(loadPasses)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPasses, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		owned[player] = nil
		passesLoaded[player] = nil
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local key = MonetizationConfig.FindPassKey(passId)
		if not key then
			return
		end
		owned[player] = owned[player] or {}
		owned[player][key] = true
		applyPass(player, key)
		local info = MonetizationConfig.GamePasses[key]
		Services.PlayerDataService:Notify(player, "Thank you! " .. info.Name .. " unlocked!", "success")
		Remotes.Event("Announce"):FireAllClients(player.DisplayName .. " unlocked " .. info.Name .. "!", Color3.fromRGB(255, 215, 80))
	end)
end

return MonetizationService
