--[[
	CompanionService
	Pick one of your spirits as a Companion: it floats next to you (rendered by every client from
	player attributes) and gives you an active ability based on its biome (AbilityConfig.ByBiome).
	Rarer / mutated companions recharge faster. The companion keeps earning on its pedestal.

	Player attributes (for UI + client-side companion visuals):
		CompanionSpecies, CompanionRarity, CompanionMutation, AbilityId, AbilityName, AbilityCooldown,
		AbilityReadyAt (Workspace:GetServerTimeNow() timestamp)
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local CompanionService = {}

local Services: any
local readyAt: { [Player]: number } = {} -- os.clock() time the ability is ready
local ATTRIBUTES = { "CompanionSpecies", "CompanionRarity", "CompanionMutation", "AbilityId", "AbilityName", "AbilityCooldown", "AbilityReadyAt" }

local function getCompanion(player: Player): (any?, any?)
	local data = Services.PlayerDataService:GetData(player)
	if not data or data.CompanionId == "" then
		return nil, data
	end
	return data.Pets[data.CompanionId], data
end

-- Re-syncs attributes; clears the companion if the pet no longer exists (sold, fused, lost in rebirth).
function CompanionService:Refresh(player: Player)
	local pet, data = getCompanion(player)
	if data and data.CompanionId ~= "" and not pet then
		data.CompanionId = ""
	end
	if not pet then
		for _, name in ipairs(ATTRIBUTES) do
			player:SetAttribute(name, nil)
		end
		return
	end
	local ability = AbilityConfig.ByBiome[pet.Biome] or AbilityConfig.ByBiome.Meadow
	local cooldown = AbilityConfig.GetCooldown(pet.Biome, PetConfig.GetRarity(pet.Rarity).Order, pet.Mutation ~= "None")
	player:SetAttribute("CompanionSpecies", pet.Species)
	player:SetAttribute("CompanionRarity", pet.Rarity)
	player:SetAttribute("CompanionMutation", pet.Mutation)
	player:SetAttribute("AbilityId", ability.Id)
	player:SetAttribute("AbilityName", ability.Name)
	player:SetAttribute("AbilityCooldown", cooldown)
	local remaining = math.max(0, (readyAt[player] or 0) - os.clock())
	player:SetAttribute("AbilityReadyAt", Workspace:GetServerTimeNow() + remaining)
end

function CompanionService:SetCompanion(player: Player, petId: any)
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return { ok = false }
	end
	if petId == nil or petId == "" then
		data.CompanionId = ""
		self:Refresh(player)
		Services.PlayerDataService:MarkDirty(player)
		return { ok = true, msg = "Companion dismissed." }
	end
	petId = tostring(petId)
	local pet = data.Pets[petId]
	if not pet then
		return { ok = false, msg = "Spirit not found." }
	end
	data.CompanionId = petId
	self:Refresh(player)
	Services.PlayerDataService:MarkDirty(player)
	local ability = AbilityConfig.ByBiome[pet.Biome] or AbilityConfig.ByBiome.Meadow
	return { ok = true, msg = string.format("%s follows you! Ability: %s (Q)", pet.Species, ability.Name) }
end

local function freezeEffect(player: Player, ability: any)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0
	end
	return Services.GuardianService:FreezeNear(root.Position, ability.Radius or 30, ability.Duration or 3)
end

-- Temporarily fades a character (Shadow Cloak). Restores original transparency afterwards.
local function cloak(player: Player, seconds: number)
	local character = player.Character
	if not character then
		return
	end
	local original: { [BasePart]: number } = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			original[part] = part.Transparency
			part.Transparency = math.max(part.Transparency, 0.92)
		end
	end
	task.delay(seconds, function()
		for part, value in pairs(original) do
			if part.Parent then
				part.Transparency = value
			end
		end
	end)
end

function CompanionService:UseAbility(player: Player)
	local pet = getCompanion(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not pet then
		return { ok = false, msg = "Choose a Companion spirit in the Spirits menu first!" }
	end
	if not root then
		return { ok = false }
	end
	local now = os.clock()
	if now < (readyAt[player] or 0) then
		return { ok = false, msg = string.format("Recharging (%.0fs)", readyAt[player] - now) }
	end
	local ability = AbilityConfig.ByBiome[pet.Biome] or AbilityConfig.ByBiome.Meadow
	local steal = Services.StealService
	local id = ability.Id
	local msg = ability.Name .. "!"

	if id == "WispRush" then
		steal:ApplySlow(player, ability.SpeedMult or 1.35, ability.Duration or 3)
	elseif id == "FlameDash" or id == "LightningStep" then
		local look = root.CFrame.LookVector
		steal:Launch(player, Vector3.new(look.X, 0, look.Z).Unit * (ability.Power or 110) + Vector3.new(0, 18, 0))
		if ability.SpeedMult then
			steal:ApplySlow(player, ability.SpeedMult, ability.Duration or 2)
		end
	elseif id == "FrostNova" then
		local frozen = freezeEffect(player, ability)
		msg = string.format("Frost Nova froze %d guardian(s)!", frozen)
	elseif id == "GraveVeil" then
		steal:HideFromGuardians(player, ability.Duration or 4)
	elseif id == "ShadowCloak" then
		steal:HideFromGuardians(player, ability.Duration or 5)
		cloak(player, ability.Duration or 5)
	elseif id == "HaloWard" then
		steal:Ward(player, ability.Duration or 8)
	elseif id == "ReapersRend" then
		local frozen = freezeEffect(player, ability)
		steal:ApplySlow(player, ability.SpeedMult or 1.4, ability.Duration or 4)
		msg = string.format("Reaper's Rend! %d guardian(s) frozen!", frozen)
	end

	local cooldown = AbilityConfig.GetCooldown(pet.Biome, PetConfig.GetRarity(pet.Rarity).Order, pet.Mutation ~= "None")
	readyAt[player] = now + cooldown
	player:SetAttribute("AbilityReadyAt", Workspace:GetServerTimeNow() + cooldown)
	return { ok = true, msg = msg }
end

function CompanionService:Init(services)
	Services = services
	Services.PlayerDataService.ProfileLoaded:Connect(function(player)
		self:Refresh(player)
	end)
end

function CompanionService:Start()
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
	end)
	Remotes.Function("SetCompanion").OnServerInvoke = function(player, petId)
		if not RateLimiter.Check(player, "SetCompanion", 0.5) then
			return { ok = false, msg = "Slow down!" }
		end
		return self:SetCompanion(player, petId)
	end
	Remotes.Function("UseAbility").OnServerInvoke = function(player)
		if not RateLimiter.Check(player, "UseAbility", 0.25) then
			return { ok = false }
		end
		return self:UseAbility(player)
	end
end

return CompanionService
