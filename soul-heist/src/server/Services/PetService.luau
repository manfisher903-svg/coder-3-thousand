--[[
	PetService
	Pedestals, incubation (hatching), Spirit Pets, inventory and pedestal visuals.

	Pedestal states (data.Slots[tostring(i)]):
		nil                                  empty
		{ Type="Orb", Rarity, Biome, HatchEnd, HatchDuration }   incubating (STEALABLE by other players)
		{ Type="Pet", PetId }                hatched spirit generating Essence (safe)

	Hatching: when HatchEnd passes, the orb hatches using the OWNER's luck:
		1) Ascension roll: chance = min(50%, 3% × luck) to jump one rarity tier
		2) Mutation roll : rarest first, chance × luck × night/eclipse mutation luck
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PetConfig = require(Shared.Config.PetConfig)
local BiomeConfig = require(Shared.Config.BiomeConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ModelFactory = require(script.Parent.Parent.World.ModelFactory)

local PetService = {}

local Services: any
local rng = Random.new()

-- Pedestal helpers -----------------------------------------------------------------------------
function PetService:GetActivePedestalCount(player: Player): number
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return 0
	end
	local monetization = Services.MonetizationService
	local count = data.Pedestals
	if monetization:HasPass(player, "ExtraPedestals") then
		count += MonetizationConfig.Effects.ExtraPedestals
	end
	if monetization:HasPass(player, "VIP") then
		count += MonetizationConfig.Effects.VIPPedestals
	end
	return math.min(count, GameConfig.PhysicalPedestalsPerBase)
end

function PetService:FindFreeSlot(player: Player): number?
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return nil
	end
	for i = 1, self:GetActivePedestalCount(player) do
		if data.Slots[tostring(i)] == nil then
			return i
		end
	end
	return nil
end

local function getPlacedPetIds(data: any): { [string]: number }
	local placed = {}
	for key, slot in pairs(data.Slots) do
		if slot.Type == "Pet" and slot.PetId then
			placed[slot.PetId] = tonumber(key) :: number
		end
	end
	return placed
end

function PetService:GetInventoryCount(player: Player): number
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return 0
	end
	local placed = getPlacedPetIds(data)
	local count = 0
	for id in pairs(data.Pets) do
		if not placed[id] then
			count += 1
		end
	end
	return count
end

-- Visuals --------------------------------------------------------------------------------------------
local function getPedestalPart(player: Player, index: number): BasePart?
	local base = Services.BaseService:GetBase(player)
	return base and base.Pedestals[index] or nil
end

local function clearPedestal(pedestal: BasePart)
	local existing = pedestal:FindFirstChild("Display")
	if existing then
		existing:Destroy()
	end
end

local function pedestalTop(pedestal: BasePart, height: number): CFrame
	local top = pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + height, 0)
	-- Cylinders lie on their side, so use world-up placement regardless of pedestal rotation.
	if pedestal:IsA("Part") and pedestal.Shape == Enum.PartType.Cylinder then
		top = pedestal.Position + Vector3.new(0, pedestal.Size.X / 2 + height, 0)
	end
	return CFrame.new(top)
end

function PetService:RenderSlot(player: Player, index: number)
	local pedestal = getPedestalPart(player, index)
	local data = Services.PlayerDataService:GetData(player)
	if not pedestal or not data then
		return
	end
	clearPedestal(pedestal)

	local active = index <= self:GetActivePedestalCount(player)
	pedestal.Transparency = active and 0 or 0.85
	pedestal.CanCollide = active
	if not active then
		return
	end

	local slot = data.Slots[tostring(index)]
	if not slot then
		return
	end

	local model: Model
	if slot.Type == "Orb" then
		model = ModelFactory.MakeOrb(slot.Rarity, slot.Biome, slot.Mutation)
		model:PivotTo(pedestalTop(pedestal, 2.5))
		local info = model.PrimaryPart and model.PrimaryPart:FindFirstChild("Info")
		if info then
			ModelFactory.SetLine(info, 2, "Hatching: " .. Format.Time(slot.HatchEnd - os.time()))
		end
		-- Other players can steal incubating souls (owner's client hides this prompt locally).
		local rarity = PetConfig.GetRarity(slot.Rarity)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "StealPrompt"
		prompt.ActionText = "Steal Soul"
		prompt.ObjectText = rarity.Id .. " Soul"
		prompt.HoldDuration = GameConfig.BaseStealHoldBase + rarity.PickupHold
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("OwnerUserId", player.UserId)
		prompt.Parent = model.PrimaryPart
		local ownerUserId = player.UserId
		prompt.Triggered:Connect(function(thief)
			Services.StealService:TryStealFromBase(thief, ownerUserId, index)
		end)
	elseif slot.Type == "Pet" then
		local pet = data.Pets[slot.PetId]
		if not pet then
			data.Slots[tostring(index)] = nil
			return
		end
		local income = Formulas.PetIncome(pet.Rarity, pet.Biome, pet.Mutation)
		model = ModelFactory.MakePet(pet.Species, pet.Rarity, pet.Mutation, "+" .. Format.Number(income) .. "/s")
		model:PivotTo(pedestalTop(pedestal, 2.2))
	else
		return
	end
	model.Name = "Display"
	model.Parent = pedestal
end

function PetService:RenderBase(player: Player)
	local base = Services.BaseService:GetBase(player)
	if not base then
		return
	end
	for i = 1, #base.Pedestals do
		self:RenderSlot(player, i)
	end
end

function PetService:ClearBase(base: any)
	for _, pedestal in ipairs(base.Pedestals) do
		clearPedestal(pedestal)
		pedestal.Transparency = 0.85
	end
end

-- Orbs ------------------------------------------------------------------------------------------------
function PetService:GetHatchDuration(player: Player, rarityId: string, biomeId: string): number
	local data = Services.PlayerDataService:GetData(player)
	local fast = Services.MonetizationService:HasPass(player, "FastHatch")
	return Formulas.HatchSeconds(rarityId, biomeId, fast, data and data.Perks.QuickIncubation or 0)
end

-- Places an orb on the first free pedestal. Returns the slot index or nil if full.
function PetService:PlaceOrb(player: Player, orb: { Rarity: string, Biome: string, Mutation: string? }): number?
	local data = Services.PlayerDataService:GetData(player)
	local index = self:FindFreeSlot(player)
	if not data or not index then
		return nil
	end
	local duration = self:GetHatchDuration(player, orb.Rarity, orb.Biome)
	data.Slots[tostring(index)] = {
		Type = "Orb",
		Rarity = orb.Rarity,
		Biome = orb.Biome,
		Mutation = orb.Mutation, -- pre-set mutation (event shop souls); nil = rolled at hatch
		HatchEnd = os.time() + duration,
		HatchDuration = duration,
	}
	self:RenderSlot(player, index)
	Services.PlayerDataService:MarkDirty(player)
	return index
end

-- Removes an incubating orb (used by stealing). Returns the orb data or nil.
function PetService:TakeOrb(player: Player, index: number): { Rarity: string, Biome: string, Mutation: string? }?
	local data = Services.PlayerDataService:GetData(player)
	local slot = data and data.Slots[tostring(index)]
	if not slot or slot.Type ~= "Orb" then
		return nil
	end
	data.Slots[tostring(index)] = nil
	self:RenderSlot(player, index)
	Services.PlayerDataService:MarkDirty(player)
	return { Rarity = slot.Rarity, Biome = slot.Biome, Mutation = slot.Mutation }
end

-- Gives an orb: placed now if a pedestal is free, otherwise queued (purchases/codes never get lost).
function PetService:GiveOrb(player: Player, orb: { Rarity: string, Biome: string, Mutation: string? }): boolean
	if self:PlaceOrb(player, orb) then
		return true
	end
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return false
	end
	table.insert(data.PendingOrbs, orb)
	Services.PlayerDataService:Notify(player, "Pedestals full - your soul is waiting. Free a pedestal to place it.", "warning")
	Services.PlayerDataService:MarkDirty(player)
	return true
end

-- Best biome the player can enter with current Speed.
function PetService:GetBestBiome(player: Player): string
	local data = Services.PlayerDataService:GetData(player)
	local best = BiomeConfig.Order[1]
	if data then
		for _, id in ipairs(BiomeConfig.Order) do
			if data.Speed >= BiomeConfig.Get(id).SpeedRequired then
				best = id
			end
		end
	end
	return best
end

-- Hatching ----------------------------------------------------------------------------------------------
local function rollMutation(luck: number): string
	local dayNight = Services.DayNightService
	local mutationLuck = luck * dayNight:GetMutationLuck()
	for _, id in ipairs(PetConfig.MutationOrder) do
		local mutation = PetConfig.Mutations[id]
		local allowed = (not mutation.NightOnly or dayNight:IsNight() or dayNight:IsEclipse())
			and (not mutation.EclipseOnly or dayNight:IsEclipse())
			and (not mutation.EventOnly or Services.EventService:IsActive())
		if allowed and rng:NextNumber() < math.min(mutation.Chance * mutationLuck, 0.5) then
			return id
		end
	end
	return "None"
end

function PetService:Hatch(player: Player, index: number)
	local data = Services.PlayerDataService:GetData(player)
	local slot = data and data.Slots[tostring(index)]
	if not slot or slot.Type ~= "Orb" then
		return
	end
	local luck = Services.EconomyService:GetLuck(player)
	local rarityId = slot.Rarity
	local ascended = false
	if rarityId ~= PetConfig.RarityOrder[#PetConfig.RarityOrder] then
		local chance = math.min(PetConfig.AscendBaseChance * luck, PetConfig.AscendMaxChance)
		if rng:NextNumber() < chance then
			rarityId = PetConfig.NextRarity(rarityId)
			ascended = true
		end
	end
	local mutation = if slot.Mutation and PetConfig.Mutations[slot.Mutation] then slot.Mutation else rollMutation(luck)
	local biome = BiomeConfig.Get(slot.Biome)

	local id = tostring(data.NextPetId)
	data.NextPetId += 1
	data.Pets[id] = {
		Id = id,
		Species = biome.Species[rarityId] or "Lost Soul",
		Rarity = rarityId,
		Biome = slot.Biome,
		Mutation = mutation,
		Locked = false,
		HatchedAt = os.time(),
	}
	data.Slots[tostring(index)] = { Type = "Pet", PetId = id }
	data.Stats.Hatched += 1
	local species = data.Pets[id].Species
	local discovered = not data.Index[species]
	if discovered then
		data.Index[species] = true -- Spirit Index: +1% Essence per species
	end
	Services.RewardService:Progress(player, "Hatch", 1)

	self:RenderSlot(player, index)
	Services.EconomyService:Recalculate(player)

	local pet = data.Pets[id]
	local income = Formulas.PetIncome(pet.Rarity, pet.Biome, pet.Mutation)
	Remotes.Event("HatchResult"):FireClient(player, {
		Species = pet.Species,
		Rarity = pet.Rarity,
		Mutation = pet.Mutation,
		Biome = pet.Biome,
		Income = income,
		Ascended = ascended,
		NewDiscovery = discovered,
	})
	if PetConfig.GetRarity(pet.Rarity).Order >= 6 or (mutation ~= "None" and PetConfig.GetMutation(mutation).Mult >= 15) then
		local label = (mutation ~= "None" and (mutation .. " ") or "") .. pet.Rarity .. " " .. pet.Species
		Remotes.Event("Announce"):FireAllClients(player.DisplayName .. " hatched a " .. label .. "!", PetConfig.GetRarity(pet.Rarity).Color)
	end
end

-- Instant hatch (developer products). mode "One" = the soul with the most time left, "All" = every soul.
function PetService:InstantHatch(player: Player, mode: string): boolean
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return false
	end
	local targets = {}
	for key, slot in pairs(data.Slots) do
		if slot.Type == "Orb" then
			table.insert(targets, { Index = tonumber(key) :: number, Remaining = slot.HatchEnd - os.time() })
		end
	end
	if #targets == 0 then
		return false
	end
	table.sort(targets, function(a, b)
		return a.Remaining > b.Remaining
	end)
	if mode == "One" then
		self:Hatch(player, targets[1].Index)
	else
		for _, t in ipairs(targets) do
			self:Hatch(player, t.Index)
		end
	end
	return true
end

-- Inventory actions (from the client) -------------------------------------------------------------------
local function petAction(player: Player, action: any, arg1: any, arg2: any)
	if not RateLimiter.Check(player, "PetAction", 0.15) then
		return { ok = false, msg = "Slow down!" }
	end
	local data = Services.PlayerDataService:GetData(player)
	if not data or type(action) ~= "string" then
		return { ok = false }
	end

	if action == "Store" then
		-- arg1 = pedestal index: move a hatched pet off its pedestal into inventory
		local index = tonumber(arg1)
		local slot = index and data.Slots[tostring(index)]
		if not slot or slot.Type ~= "Pet" then
			return { ok = false, msg = "No spirit on that pedestal." }
		end
		if PetService:GetInventoryCount(player) >= GameConfig.InventoryCap then
			return { ok = false, msg = "Inventory full! Sell some spirits." }
		end
		data.Slots[tostring(index)] = nil
		PetService:RenderSlot(player, index :: number)
		Services.EconomyService:Recalculate(player)
		return { ok = true }
	elseif action == "Place" then
		-- arg1 = petId: put an inventory pet on the first free pedestal
		local petId = tostring(arg1)
		if not data.Pets[petId] or getPlacedPetIds(data)[petId] then
			return { ok = false, msg = "Spirit not in inventory." }
		end
		local index = PetService:FindFreeSlot(player)
		if not index then
			return { ok = false, msg = "No free pedestal." }
		end
		data.Slots[tostring(index)] = { Type = "Pet", PetId = petId }
		PetService:RenderSlot(player, index)
		Services.EconomyService:Recalculate(player)
		return { ok = true }
	elseif action == "Sell" then
		-- arg1 = petId (must be in inventory and unlocked)
		local petId = tostring(arg1)
		local pet = data.Pets[petId]
		if not pet or getPlacedPetIds(data)[petId] then
			return { ok = false, msg = "Store the spirit before selling it." }
		end
		if pet.Locked then
			return { ok = false, msg = "Unlock the spirit first." }
		end
		if data.CompanionId == petId then
			return { ok = false, msg = "That's your Companion! Pick another one first." }
		end
		local value = math.floor(Formulas.PetIncome(pet.Rarity, pet.Biome, pet.Mutation) * PetConfig.SellSeconds)
		data.Pets[petId] = nil
		Services.EconomyService:AddEssence(player, value)
		Services.PlayerDataService:MarkDirty(player)
		return { ok = true, msg = "Sold for " .. Format.Number(value) .. " Essence" }
	elseif action == "Lock" then
		-- arg1 = petId, arg2 = boolean. Locked pets survive rebirth (up to vault size).
		local petId = tostring(arg1)
		local pet = data.Pets[petId]
		if not pet then
			return { ok = false }
		end
		local wantLocked = arg2 == true
		if wantLocked and not pet.Locked then
			local lockedCount = 0
			for _, p in pairs(data.Pets) do
				if p.Locked then
					lockedCount += 1
				end
			end
			local vault = Services.RebirthService:GetVaultSize(player)
			if lockedCount >= vault then
				return { ok = false, msg = string.format("Vault full (%d). Rebirth more or get Soul Vault+.", vault) }
			end
		end
		pet.Locked = wantLocked
		Services.PlayerDataService:MarkDirty(player)
		return { ok = true }
	end
	if action == "FuseRarity" then
		-- Soul Fusion: 3 inventory spirits of the same rarity -> 1 soul of the NEXT rarity.
		-- Uses the 3 lowest-income unlocked, non-companion spirits. Result comes from the best biome
		-- among the three, and has a 50% chance to inherit the best mutation among them.
		local rarityId = tostring(arg1)
		local rarity = PetConfig.Rarities[rarityId]
		if not rarity or rarity.Order >= #PetConfig.RarityOrder then
			return { ok = false, msg = "Can't fuse that rarity." }
		end
		local placed = getPlacedPetIds(data)
		local candidates = {}
		for id, pet in pairs(data.Pets) do
			if pet.Rarity == rarityId and not placed[id] and not pet.Locked and data.CompanionId ~= id then
				table.insert(candidates, pet)
			end
		end
		if #candidates < 3 then
			return { ok = false, msg = "Need 3 " .. rarityId .. " spirits in your inventory (not vaulted)." }
		end
		table.sort(candidates, function(a, b)
			return Formulas.PetIncome(a.Rarity, a.Biome, a.Mutation) < Formulas.PetIncome(b.Rarity, b.Biome, b.Mutation)
		end)
		local bestBiome, bestMutation = candidates[1].Biome, "None"
		for i = 1, 3 do
			local pet = candidates[i]
			if BiomeConfig.Get(pet.Biome).Order > BiomeConfig.Get(bestBiome).Order then
				bestBiome = pet.Biome
			end
			if PetConfig.GetMutation(pet.Mutation).Mult > PetConfig.GetMutation(bestMutation).Mult then
				bestMutation = pet.Mutation
			end
			data.Pets[pet.Id] = nil
		end
		local inherited = bestMutation ~= "None" and rng:NextNumber() < 0.5
		local nextRarity = PetConfig.NextRarity(rarityId)
		PetService:GiveOrb(player, { Rarity = nextRarity, Biome = bestBiome, Mutation = inherited and bestMutation or nil })
		data.Stats.Fusions = (data.Stats.Fusions or 0) + 1
		Services.PlayerDataService:MarkDirty(player)
		local extra = inherited and (" It kept the " .. bestMutation .. " mutation!") or ""
		return { ok = true, msg = string.format("Soul Fusion! A %s %s Soul is incubating.%s", nextRarity, BiomeConfig.Get(bestBiome).Name, extra) }
	end
	return { ok = false, msg = "Unknown action." }
end

-- Lifecycle -------------------------------------------------------------------------------------------------
function PetService:Init(services)
	Services = services
	Services.PlayerDataService.ProfileLoaded:Connect(function(player, data)
		-- Clean slots referencing deleted pets. (Orbs that finished while offline hatch on the next tick.)
		for key, slot in pairs(data.Slots) do
			if slot.Type == "Pet" and not data.Pets[slot.PetId] then
				data.Slots[key] = nil
			end
		end
	end)
end

function PetService:Start()
	Remotes.Function("PetAction").OnServerInvoke = petAction

	-- 1 Hz: hatch timers, countdown labels, pending orb placement
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for player, data in pairs(Services.PlayerDataService:GetAllLoaded()) do
				if Services.BaseService:GetBase(player) then
					for key, slot in pairs(data.Slots) do
						if slot.Type == "Orb" then
							local index = tonumber(key) :: number
							if now >= slot.HatchEnd then
								self:Hatch(player, index)
							else
								local pedestal = getPedestalPart(player, index)
								local display = pedestal and pedestal:FindFirstChild("Display")
								local primary = display and (display :: Model).PrimaryPart
								if primary then
									ModelFactory.SetLine(primary:FindFirstChild("Info"), 2, "Hatching: " .. Format.Time(slot.HatchEnd - now))
								end
							end
						end
					end
					if #data.PendingOrbs > 0 and self:FindFreeSlot(player) then
						local orb = table.remove(data.PendingOrbs, 1)
						self:PlaceOrb(player, orb)
					end
				end
			end
		end
	end)
end

return PetService
