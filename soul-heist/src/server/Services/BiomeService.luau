--[[
	BiomeService
	Biome zones, Speed gates, Soul Orb spawning (rarity rolls) and dropped orbs.

	Spawn rarity weights come from PetConfig.SpawnWeight, modified by server luck (night/eclipse):
		Rare and above  : weight × spawnLuck
		Uncommon        : weight × sqrt(spawnLuck)
	Speed gates: a player inside a biome Zone with Speed below SpeedRequired is pushed back out.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PetConfig = require(Shared.Config.PetConfig)
local BiomeConfig = require(Shared.Config.BiomeConfig)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local ModelFactory = require(script.Parent.Parent.World.ModelFactory)

export type BiomeRuntime = {
	Id: string,
	Config: any,
	Model: Instance,
	Zone: BasePart,
	Spawns: { BasePart },
	GuardianSpawns: { BasePart },
	GateReturn: BasePart?,
	Occupied: { [BasePart]: Model },
	ActiveCount: number,
}

local BiomeService = {}

local Services: any
local runtimes: { BiomeRuntime } = {}
local byId: { [string]: BiomeRuntime } = {}
local rng = Random.new()
local droppedFolder: Folder
local WORLD_ORB_LIFETIME = 150

local function partsIn(folder: Instance?): { BasePart }
	local list = {}
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
	end
	return list
end

-- Zones -----------------------------------------------------------------------------------------------
function BiomeService:IsInZone(runtime: BiomeRuntime, position: Vector3, padding: number?): boolean
	local localPos = runtime.Zone.CFrame:PointToObjectSpace(position)
	local half = runtime.Zone.Size / 2 + Vector3.one * (padding or 0)
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

function BiomeService:GetBiomeAt(position: Vector3): BiomeRuntime?
	for _, runtime in ipairs(runtimes) do
		if self:IsInZone(runtime, position) then
			return runtime
		end
	end
	return nil
end

function BiomeService:GetRuntime(id: string): BiomeRuntime?
	return byId[id]
end

function BiomeService:GetRuntimes(): { BiomeRuntime }
	return runtimes
end

-- Rarity roll -----------------------------------------------------------------------------------------
function BiomeService:RollRarity(spawnLuck: number): string
	local weights = {}
	local total = 0
	for _, id in ipairs(PetConfig.RarityOrder) do
		local rarity = PetConfig.Rarities[id]
		local w = rarity.SpawnWeight
		if rarity.Order >= 3 then
			w *= spawnLuck
		elseif rarity.Order == 2 then
			w *= math.sqrt(spawnLuck)
		end
		weights[id] = w
		total += w
	end
	local roll = rng:NextNumber() * total
	for _, id in ipairs(PetConfig.RarityOrder) do
		roll -= weights[id]
		if roll <= 0 then
			return id
		end
	end
	return "Common"
end

-- Orb pickup --------------------------------------------------------------------------------------------
local function attachPickupPrompt(model: Model, orb: { Rarity: string, Biome: string }, onTaken: () -> (), requiredSpeed: number?)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local rarity = PetConfig.GetRarity(orb.Rarity)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Steal Soul"
	prompt.ObjectText = orb.Rarity .. " Soul"
	prompt.HoldDuration = rarity.PickupHold
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = primary

	local taken = false
	prompt.Triggered:Connect(function(player)
		if taken or not RateLimiter.Check(player, "Pickup", 0.3) then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - primary.Position).Magnitude > GameConfig.WorldOrbPickupMaxDistance then
			return
		end
		if Services.StealService:IsCarrying(player) then
			Services.PlayerDataService:Notify(player, "You can only carry one soul!", "error")
			return
		end
		if requiredSpeed then
			if Services.StealService:GetBaseSpeed(player) < requiredSpeed then
				return
			end
		end
		if Services.StealService:PickUp(player, orb, nil) then
			taken = true
			onTaken()
			model:Destroy()
		end
	end)
end

function BiomeService:SpawnWorldOrb(runtime: BiomeRuntime): boolean
	local free = {}
	for _, spawnPart in ipairs(runtime.Spawns) do
		if not runtime.Occupied[spawnPart] then
			table.insert(free, spawnPart)
		end
	end
	if #free == 0 then
		return false
	end
	local spawnPart = free[rng:NextInteger(1, #free)]
	local rarityId = self:RollRarity(Services.DayNightService:GetSpawnLuck())
	local orb = { Rarity = rarityId, Biome = runtime.Id }
	local model = ModelFactory.MakeOrb(rarityId, runtime.Id)
	model:PivotTo(spawnPart.CFrame + Vector3.new(0, 2, 0))
	model.Parent = runtime.Model

	runtime.Occupied[spawnPart] = model
	runtime.ActiveCount += 1
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		runtime.Occupied[spawnPart] = nil
		runtime.ActiveCount -= 1
	end
	attachPickupPrompt(model, orb, release, runtime.Config.SpeedRequired)
	model.Destroying:Connect(release)

	-- Old uncollected souls fade so the field keeps rerolling.
	task.delay(WORLD_ORB_LIFETIME + rng:NextNumber(0, 30), function()
		if model.Parent then
			model:Destroy()
		end
	end)

	local rarity = PetConfig.GetRarity(rarityId)
	if rarity.Announce then
		Remotes.Event("Announce"):FireAllClients(
			string.format("A %s Soul appeared in %s!", rarityId, runtime.Config.Name),
			rarity.Color
		)
	end
	return true
end

function BiomeService:SpawnDroppedOrb(orb: { Rarity: string, Biome: string }, position: Vector3)
	local model = ModelFactory.MakeOrb(orb.Rarity, orb.Biome)
	model:PivotTo(CFrame.new(position + Vector3.new(0, 1, 0)))
	model.Name = "DroppedSoul"
	model.Parent = droppedFolder
	attachPickupPrompt(model, orb, function() end, nil)
	task.delay(GameConfig.DroppedOrbLifetime, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Speed gates ----------------------------------------------------------------------------------------------
local function pushOutOfBiome(player: Player, runtime: BiomeRuntime, root: BasePart)
	local target: Vector3
	if runtime.GateReturn then
		target = runtime.GateReturn.Position
	else
		local zone = runtime.Zone
		local localPos = zone.CFrame:PointToObjectSpace(root.Position)
		local world = zone.CFrame:PointToWorldSpace(Vector3.new(localPos.X, 0, -zone.Size.Z / 2 - 8))
		target = Vector3.new(world.X, root.Position.Y, world.Z)
	end
	Services.AntiExploitService:Teleport(player, CFrame.new(target))
	if RateLimiter.Check(player, "GateNotify", 2) then
		Services.PlayerDataService:Notify(
			player,
			string.format("%s requires %d Speed! Upgrade at your Treadmill.", runtime.Config.Name, runtime.Config.SpeedRequired),
			"error"
		)
	end
end

-- Lifecycle -------------------------------------------------------------------------------------------------
function BiomeService:Init(services)
	Services = services
	droppedFolder = Instance.new("Folder")
	droppedFolder.Name = "DroppedSouls"
	droppedFolder.Parent = Workspace

	local biomesFolder = Workspace:WaitForChild("Biomes")
	for _, id in ipairs(BiomeConfig.Order) do
		local model = biomesFolder:FindFirstChild(id)
		local zone = model and model:FindFirstChild("Zone")
		if not (model and zone and zone:IsA("BasePart")) then
			warn("[BiomeService] Biome '" .. id .. "' missing in Workspace.Biomes (needs a Zone part) - skipped")
			continue
		end
		local runtime: BiomeRuntime = {
			Id = id,
			Config = BiomeConfig.Get(id),
			Model = model,
			Zone = zone,
			Spawns = partsIn(model:FindFirstChild("SoulSpawns")),
			GuardianSpawns = partsIn(model:FindFirstChild("GuardianSpawns")),
			GateReturn = model:FindFirstChild("GateReturn") :: BasePart?,
			Occupied = {},
			ActiveCount = 0,
		}
		if #runtime.Spawns == 0 then
			warn("[BiomeService] Biome '" .. id .. "' has no SoulSpawns")
		end
		table.insert(runtimes, runtime)
		byId[id] = runtime
	end
end

function BiomeService:Start()
	-- Orb spawners (one loop per biome)
	for _, runtime in ipairs(runtimes) do
		task.spawn(function()
			-- Pre-fill half the field so the server never starts empty
			for _ = 1, math.floor(runtime.Config.MaxOrbs / 2) do
				self:SpawnWorldOrb(runtime)
			end
			while true do
				task.wait(runtime.Config.RespawnSeconds)
				if runtime.ActiveCount < runtime.Config.MaxOrbs then
					self:SpawnWorldOrb(runtime)
				end
			end
		end)
	end

	-- Speed gate enforcement
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, player in ipairs(Players:GetPlayers()) do
				local data = Services.PlayerDataService:GetData(player)
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if data and root then
					local runtime = self:GetBiomeAt(root.Position)
					player:SetAttribute("Biome", runtime and runtime.Id or nil)
					if runtime and Services.StealService:GetBaseSpeed(player) < runtime.Config.SpeedRequired then
						pushOutOfBiome(player, runtime, root)
					end
				end
			end
		end
	end)
end

return BiomeService
