--[[
	StealService
	Everything about carrying a soul: picking up, weight slowdown, being chased/bonked, dropping,
	delivering home, and stealing incubating souls out of other players' bases.

	Rules
	  * Carry 1 soul at a time. Heavier (rarer) souls slow you more; Carry upgrades + Phantom Steps reduce it.
	  * Touched by a guardian / bonked by a player / died -> the soul drops on the ground (anyone can grab it).
	  * Walk into YOUR base zone with a soul -> it's placed on a free pedestal and starts incubating.
	  * Incubating souls in other bases can be stolen (hold prompt) unless the base is locked/shielded/protected.
	  * WalkSpeed is ALWAYS set by the server here (never trust the client).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PetConfig = require(Shared.Config.PetConfig)
local BiomeConfig = require(Shared.Config.BiomeConfig)
local MonetizationConfig = require(Shared.Config.MonetizationConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
local Formulas = require(Shared.Formulas)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ModelFactory = require(script.Parent.Parent.World.ModelFactory)

export type Carried = {
	Orb: { Rarity: string, Biome: string, Mutation: string? },
	Visual: Model?,
	StolenFromUserId: number?,
}

local StealService = {}

local Services: any
local carrying: { [Player]: Carried } = {}
local slows: { [Player]: { { Factor: number, Until: number } } } = {}
local highlights: { [Player]: Highlight } = {}
local lastFullWarning: { [Player]: number } = {}
local hiddenUntil: { [Player]: number } = {} -- guardians can't perceive (Grave Veil / Shadow Cloak)
local wardUntil: { [Player]: number } = {} -- next knock-loose is blocked (Halo Ward)

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

-- Movement ------------------------------------------------------------------------------------------
function StealService:GetBaseSpeed(player: Player): number
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return 16
	end
	local speed = data.Speed
	if Services.MonetizationService:HasPass(player, "PhantomSteps") then
		speed += MonetizationConfig.Effects.PhantomSpeed
	end
	return speed
end

function StealService:RefreshWalkSpeed(player: Player)
	local humanoid = getHumanoid(player)
	local data = Services.PlayerDataService:GetData(player)
	if not humanoid or not data then
		return
	end
	local speed = self:GetBaseSpeed(player)
	local carried = carrying[player]
	if carried then
		local phantom = Services.MonetizationService:HasPass(player, "PhantomSteps")
		speed = Formulas.CarriedSpeed(speed, carried.Orb.Rarity, data.CarryLevel, phantom)
	end
	if player:GetAttribute("Sneaking") then
		speed *= AbilityConfig.Stealth.SneakSpeedMult
	end
	local now = os.clock()
	local list = slows[player]
	if list then
		for i = #list, 1, -1 do
			if list[i].Until <= now then
				table.remove(list, i)
			else
				speed *= list[i].Factor
			end
		end
	end
	humanoid.WalkSpeed = speed
	player:SetAttribute("WalkSpeed", speed)
end

function StealService:ApplySlow(player: Player, factor: number, duration: number)
	slows[player] = slows[player] or {}
	table.insert(slows[player], { Factor = factor, Until = os.clock() + duration })
	self:RefreshWalkSpeed(player)
	task.delay(duration + 0.05, function()
		if player.Parent then
			self:RefreshWalkSpeed(player)
		end
	end)
end

function StealService:Knockback(player: Player, fromPosition: Vector3, power: number)
	local root = getRoot(player)
	if not root then
		return
	end
	local direction = root.Position - fromPosition
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.1 then
		direction = Vector3.new(0, 0, 1)
	end
	Services.AntiExploitService:Grace(player, 1.5)
	Remotes.Event("Knockback"):FireClient(player, direction.Unit * power + Vector3.new(0, power * 0.5, 0))
end

-- Stealth & ability hooks ------------------------------------------------------------------------------
function StealService:IsHiddenFromGuardians(player: Player): boolean
	return (hiddenUntil[player] or 0) > os.clock()
end

function StealService:HideFromGuardians(player: Player, seconds: number)
	hiddenUntil[player] = math.max(hiddenUntil[player] or 0, os.clock() + seconds)
end

function StealService:Ward(player: Player, seconds: number)
	wardUntil[player] = os.clock() + seconds
	player:SetAttribute("Warded", true)
	task.delay(seconds, function()
		if (wardUntil[player] or 0) <= os.clock() then
			player:SetAttribute("Warded", nil)
		end
	end)
end

-- Guardians and bonks call this instead of Drop: Halo Ward can block it. Returns true if the soul dropped.
function StealService:TryKnockLoose(player: Player, reason: string): boolean
	if not carrying[player] then
		return false
	end
	if (wardUntil[player] or 0) > os.clock() then
		wardUntil[player] = 0
		player:SetAttribute("Warded", nil)
		Services.PlayerDataService:Notify(player, "Halo Ward blocked it!", "success")
		return false
	end
	self:Drop(player, reason)
	return true
end

-- Sends the player flying with a velocity (client applies it - it owns its character physics).
function StealService:Launch(player: Player, velocity: Vector3)
	Services.AntiExploitService:Grace(player, 2)
	Remotes.Event("Knockback"):FireClient(player, velocity)
end

function StealService:SetSneak(player: Player, on: boolean)
	player:SetAttribute("Sneaking", on or nil)
	self:RefreshWalkSpeed(player)
end

-- Haunt: the robbed owner curses the thief (once per robbery, within a short window).
function StealService:Haunt(owner: Player)
	local thiefId = owner:GetAttribute("HauntThiefId")
	local untilTime = owner:GetAttribute("HauntUntil") or 0
	if not thiefId or Workspace:GetServerTimeNow() > untilTime then
		return { ok = false, msg = "Nobody to haunt right now." }
	end
	owner:SetAttribute("HauntThiefId", nil)
	owner:SetAttribute("HauntUntil", nil)
	local thief = Players:GetPlayerByUserId(thiefId)
	local carried = thief and carrying[thief]
	if not thief or not carried or carried.StolenFromUserId ~= owner.UserId then
		return { ok = false, msg = "The thief already got away..." }
	end
	local haunt = AbilityConfig.Haunt
	self:ApplySlow(thief, haunt.SlowFactor, haunt.Duration)
	if highlights[thief] then
		highlights[thief].FillColor = Color3.fromRGB(140, 40, 255)
	end
	Services.PlayerDataService:Notify(thief, owner.DisplayName .. " is HAUNTING you! You're slowed!", "error")
	return { ok = true, msg = "You haunted " .. thief.DisplayName .. "! Catch them!" }
end

-- Carry state -----------------------------------------------------------------------------------------
function StealService:IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function StealService:GetCarried(player: Player): Carried?
	return carrying[player]
end

local function setThiefHighlight(player: Player, on: boolean)
	local existing = highlights[player]
	if existing then
		existing:Destroy()
		highlights[player] = nil
	end
	if on and player.Character then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 40, 40)
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.6
		highlight.Parent = player.Character
		highlights[player] = highlight
	end
end

function StealService:PickUp(player: Player, orb: { Rarity: string, Biome: string, Mutation: string? }, stolenFromUserId: number?): boolean
	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	if not root or not humanoid or humanoid.Health <= 0 or carrying[player] then
		return false
	end
	if not Services.PlayerDataService:IsLoaded(player) then
		return false
	end

	local visual = ModelFactory.MakeOrb(orb.Rarity, orb.Biome, orb.Mutation)
	visual:PivotTo(root.CFrame * CFrame.new(0, 4.5, 0))
	for _, part in ipairs(visual:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
	end
	visual.Name = "CarriedSoul"
	visual.Parent = player.Character

	carrying[player] = { Orb = { Rarity = orb.Rarity, Biome = orb.Biome, Mutation = orb.Mutation }, Visual = visual, StolenFromUserId = stolenFromUserId }
	player:SetAttribute("CarryingRarity", orb.Rarity)
	player:SetAttribute("CarryingBiome", orb.Biome)
	if stolenFromUserId then
		setThiefHighlight(player, true)
	end
	self:RefreshWalkSpeed(player)
	return true
end

-- Removes the carried soul without dropping it. Returns its data.
function StealService:Clear(player: Player): Carried?
	local carried = carrying[player]
	if not carried then
		return nil
	end
	carrying[player] = nil
	if carried.Visual then
		carried.Visual:Destroy()
	end
	player:SetAttribute("CarryingRarity", nil)
	player:SetAttribute("CarryingBiome", nil)
	setThiefHighlight(player, false)
	if player.Parent then
		self:RefreshWalkSpeed(player)
	end
	return carried
end

-- Drops the carried soul on the ground where anyone can pick it up.
function StealService:Drop(player: Player, reason: string?)
	local root = getRoot(player)
	local position = root and root.Position
	local carried = self:Clear(player)
	if not carried then
		return
	end
	if position then
		local offset = Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
		Services.BiomeService:SpawnDroppedOrb(carried.Orb, position + offset)
	end
	if reason and player.Parent then
		Services.PlayerDataService:Notify(player, reason, "error")
	end
end

-- Stealing from bases -------------------------------------------------------------------------------------
function StealService:TryStealFromBase(thief: Player, ownerUserId: number, index: number)
	local pds = Services.PlayerDataService
	if thief.UserId == ownerUserId then
		pds:Notify(thief, "That's your own soul!", "info")
		return
	end
	if not RateLimiter.Check(thief, "BaseSteal", 1) then
		return
	end
	if carrying[thief] then
		pds:Notify(thief, "You're already carrying a soul!", "error")
		return
	end
	local base, owner = Services.BaseService:GetBaseOfUserId(ownerUserId)
	if not base or not owner then
		return
	end
	local protected, reason = Services.BaseService:IsProtected(owner)
	if protected then
		pds:Notify(thief, reason or "Protected.", "error")
		return
	end
	local pedestal = base.Pedestals[index]
	local root = getRoot(thief)
	if not pedestal or not root or (root.Position - pedestal.Position).Magnitude > GameConfig.BaseStealMaxDistance then
		return -- too far: exploit attempt or lag
	end

	local orb = Services.PetService:TakeOrb(owner, index)
	if not orb then
		return
	end
	if not self:PickUp(thief, orb, ownerUserId) then
		Services.PetService:PlaceOrb(owner, orb) -- give it back if the pickup failed
		return
	end

	local ownerData = pds:GetData(owner)
	if ownerData then
		ownerData.LastRobbed = { Rarity = orb.Rarity, Biome = orb.Biome, Time = os.time() }
		ownerData.Stats.TimesRobbed += 1
		pds:MarkDirty(owner)
	end
	-- Give the owner a short window to Haunt the thief
	owner:SetAttribute("HauntThiefId", thief.UserId)
	owner:SetAttribute("HauntUntil", Workspace:GetServerTimeNow() + AbilityConfig.Haunt.WindowSeconds)
	pds:Notify(owner, string.format("%s is stealing your %s Soul! HAUNT them (H) and bonk them!", thief.DisplayName, orb.Rarity), "error")
	pds:Notify(thief, "You grabbed a " .. orb.Rarity .. " Soul! RUN HOME!", "success")
	local rarity = PetConfig.GetRarity(orb.Rarity)
	if rarity.Announce then
		Remotes.Event("Announce"):FireAllClients(
			string.format("%s is stealing %s's %s Soul!", thief.DisplayName, owner.DisplayName, orb.Rarity),
			rarity.Color
		)
	end
end

-- Delivery --------------------------------------------------------------------------------------------------
local function tryDeliver(player: Player)
	local carried = carrying[player]
	if not carried or not Services.BaseService:IsPlayerInOwnBase(player) then
		return
	end
	local index = Services.PetService:PlaceOrb(player, carried.Orb)
	if not index then
		local now = os.clock()
		if not lastFullWarning[player] or now - lastFullWarning[player] > 4 then
			lastFullWarning[player] = now
			Services.PlayerDataService:Notify(player, "All pedestals are full! Buy more or store/sell a spirit.", "warning")
		end
		return
	end
	local data = Services.PlayerDataService:GetData(player)
	data.Stats.Steals += 1
	local rewards = Services.RewardService
	rewards:Progress(player, "Deliver", 1)
	if PetConfig.GetRarity(carried.Orb.Rarity).Order >= 3 then
		rewards:Progress(player, "DeliverRare", 1)
	end
	if Services.DayNightService:IsNight() then
		rewards:Progress(player, "DeliverNight", 1)
	end
	if carried.StolenFromUserId then
		data.Stats.BaseSteals += 1
		rewards:Progress(player, "BaseSteal", 1)
	end
	Services.EventService:OnDeliver(player, carried.Orb.Rarity)
	StealService:Clear(player)
	local biome = BiomeConfig.Get(carried.Orb.Biome)
	local hatchSeconds = Services.PetService:GetHatchDuration(player, carried.Orb.Rarity, carried.Orb.Biome)
	Services.PlayerDataService:Notify(
		player,
		string.format("%s %s Soul secured! Hatching in %s", carried.Orb.Rarity, biome.Name, Format.Time(hatchSeconds)),
		"success"
	)
	Services.PlayerDataService:Replicate(player)
	Services.PlayerDataService:MarkDirty(player)
end

-- Lifecycle ---------------------------------------------------------------------------------------------------
function StealService:Init(services)
	Services = services
end

function StealService:Start()
	local function onCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		-- A fresh character never carries anything.
		if carrying[player] then
			self:Clear(player)
		end
		self:RefreshWalkSpeed(player)
		humanoid.Died:Connect(function()
			self:Drop(player, "You died and dropped your soul!")
		end)
	end

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end

	Services.PlayerDataService.ProfileLoaded:Connect(function(player)
		self:RefreshWalkSpeed(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:Drop(player, nil) -- leaving with a soul drops it for everyone else
		slows[player] = nil
		lastFullWarning[player] = nil
		hiddenUntil[player] = nil
		wardUntil[player] = nil
	end)

	Remotes.Event("SetSneak").OnServerEvent:Connect(function(player, on)
		if RateLimiter.Check(player, "Sneak", 0.2) then
			self:SetSneak(player, on == true)
		end
	end)
	Remotes.Function("Haunt").OnServerInvoke = function(player)
		if not RateLimiter.Check(player, "Haunt", 0.5) then
			return { ok = false }
		end
		return self:Haunt(player)
	end

	Remotes.Event("DropOrb").OnServerEvent:Connect(function(player)
		if RateLimiter.Check(player, "DropOrb", 0.5) then
			self:Drop(player, nil)
		end
	end)

	-- Delivery check loop
	task.spawn(function()
		while true do
			task.wait(0.15)
			for player in pairs(carrying) do
				if player.Parent then
					tryDeliver(player)
				else
					carrying[player] = nil
				end
			end
		end
	end)
end

return StealService
