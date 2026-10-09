--[[
	EventService
	Seasonal events. Currently: the Hallow-Soul Festival (Halloween).

	While active:
	  * Spooky lighting (purple ambient, orange haze) + jack-o'-lanterns, tombstones and lanterns everywhere
	  * Candy pumpkins spawn around the hub and inside biomes (deeper biome = more candy, 5% golden = 15 candy)
	  * Delivering a soul home gives Candy (1 + rarity tier)
	  * The "Haunted" mutation (x10) can roll on any hatch
	  * Candy Shop: guaranteed Haunted souls + boosts (EventConfig.Shop)
	Replicated: Workspace attributes EventActive, EventName, EventEndsAt; player attribute Candy.
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EventConfig = require(Shared.Config.EventConfig)
local PetConfig = require(Shared.Config.PetConfig)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Rewards = require(script.Parent.Parent.Util.Rewards)

local EventService = {}

local Services: any
local rng = Random.new()
local pumpkinFolder: Folder
local pumpkinCount = 0

function EventService:IsActive(): boolean
	return EventConfig.IsActive()
end

function EventService:AddCandy(player: Player, amount: number, countForQuests: boolean?)
	local data = Services.PlayerDataService:GetData(player)
	if not data or amount <= 0 then
		return
	end
	data.Candy += amount
	data.Stats.CandyEarned += amount
	player:SetAttribute("Candy", data.Candy)
	if countForQuests ~= false then
		Services.RewardService:Progress(player, "Candy", amount)
	end
	Services.PlayerDataService:MarkDirty(player)
end

-- Called by StealService when a soul is delivered home.
function EventService:OnDeliver(player: Player, rarityId: string)
	if self:IsActive() then
		self:AddCandy(player, EventConfig.DeliverCandyBase + PetConfig.GetRarity(rarityId).Order, false)
	end
end

function EventService:BuyItem(player: Player, itemId: any)
	if not self:IsActive() then
		return { ok = false, msg = "The event has ended." }
	end
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return { ok = false }
	end
	local item
	for _, entry in ipairs(EventConfig.Shop) do
		if entry.Id == itemId then
			item = entry
		end
	end
	if not item then
		return { ok = false, msg = "Unknown item." }
	end
	if data.Candy < item.Cost then
		return { ok = false, msg = "Need " .. item.Cost .. " Candy" }
	end
	data.Candy -= item.Cost
	player:SetAttribute("Candy", data.Candy)
	local rewards = {}
	if item.Orb then
		rewards.Orb = { Rarity = item.Orb.Rarity, Biome = "Best", Mutation = item.Orb.Mutation }
	end
	if item.Boost then
		rewards.Boost = item.Boost
	end
	local granted = Rewards.Grant(Services, player, rewards)
	return { ok = true, msg = "Bought: " .. table.concat(granted, ", ") }
end

-- Visual dressing ---------------------------------------------------------------------------------------
local function makePart(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(part :: any)[key] = value
		end
	end
	part.Parent = props.Parent
	return part
end

-- A jack-o'-lantern model: orange ball, stem, glowing eyes + mouth, orange light.
local function makeJackOLantern(position: Vector3, size: number, golden: boolean?): Model
	local model = Instance.new("Model")
	model.Name = golden and "GoldenPumpkin" or "Pumpkin"
	local body = makePart({
		Name = "Body", Shape = Enum.PartType.Ball, Size = Vector3.one * size,
		Color = golden and Color3.fromRGB(255, 210, 60) or Color3.fromRGB(235, 110, 20),
		Material = golden and Enum.Material.Neon or Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(position), Parent = model,
	})
	makePart({
		Name = "Stem", Size = Vector3.new(size * 0.15, size * 0.3, size * 0.15), Color = Color3.fromRGB(70, 120, 40),
		CFrame = CFrame.new(position + Vector3.new(0, size * 0.55, 0)), Parent = model,
	})
	local glow = Color3.fromRGB(255, 200, 60)
	for _, side in ipairs({ -1, 1 }) do
		makePart({
			Name = "Eye", Size = Vector3.new(size * 0.18, size * 0.18, size * 0.1), Color = glow, Material = Enum.Material.Neon,
			CFrame = CFrame.new(position + Vector3.new(side * size * 0.2, size * 0.12, -size * 0.47)) * CFrame.Angles(0, 0, math.rad(45)),
			Parent = model,
		})
	end
	makePart({
		Name = "Mouth", Size = Vector3.new(size * 0.5, size * 0.1, size * 0.1), Color = glow, Material = Enum.Material.Neon,
		CFrame = CFrame.new(position + Vector3.new(0, -size * 0.18, -size * 0.46)), Parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 40)
	light.Range = size * 4
	light.Brightness = 1.5
	light.Parent = body
	model.PrimaryPart = body
	return model
end

local function makeTombstone(position: Vector3, parent: Instance)
	local height = rng:NextNumber(3, 5)
	makePart({
		Name = "Tombstone", Size = Vector3.new(2.6, height, 0.8), Color = Color3.fromRGB(110, 110, 120),
		Material = Enum.Material.Slate, CanCollide = true,
		CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), math.rad(rng:NextNumber(-8, 8))),
		Parent = parent,
	})
end

local function groundAt(x: number, z: number, top: number, depth: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { pumpkinFolder }
	local result = Workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -depth, 0), params)
	return result and result.Position or nil
end

-- Random point on the ground inside a box-shaped part (zone).
local function randomPointIn(zone: BasePart): Vector3?
	local half = zone.Size / 2
	local localPoint = Vector3.new(rng:NextNumber(-half.X * 0.9, half.X * 0.9), half.Y, rng:NextNumber(-half.Z * 0.9, half.Z * 0.9))
	local world = zone.CFrame:PointToWorldSpace(localPoint)
	return groundAt(world.X, world.Z, world.Y + 20, zone.Size.Y + 40)
end

local function spawnAreas(): { { Zone: BasePart, Bonus: number } }
	local areas = {}
	local hub = Workspace:FindFirstChild("Hub")
	local hubGround = hub and hub:FindFirstChild("HubGround")
	if hubGround and hubGround:IsA("BasePart") then
		table.insert(areas, { Zone = hubGround, Bonus = 0 })
	end
	for _, runtime in ipairs(Services.BiomeService:GetRuntimes()) do
		table.insert(areas, { Zone = runtime.Zone, Bonus = runtime.Config.Order - 1 })
	end
	return areas
end

local function decorate()
	if Workspace:FindFirstChild("HalloweenDecor") then
		return -- you built your own decorations
	end
	local decor = Instance.new("Folder")
	decor.Name = "HalloweenDecor"
	decor.Parent = Workspace

	-- Jack-o'-lanterns at every base corner
	local bases = Workspace:FindFirstChild("Bases")
	if bases then
		for _, base in ipairs(bases:GetChildren()) do
			local zone = base:FindFirstChild("Zone")
			if zone and zone:IsA("BasePart") then
				for _, corner in ipairs({ Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) }) do
					local x = zone.Position.X + corner.X * (zone.Size.X / 2 - 2)
					local z = zone.Position.Z + corner.Z * (zone.Size.Z / 2 - 2)
					local ground = groundAt(x, z, zone.Position.Y + zone.Size.Y / 2 + 20, zone.Size.Y + 40)
					if ground then
						makeJackOLantern(ground + Vector3.new(0, 1.6, 0), 3.2).Parent = decor
					end
				end
			end
		end
	end

	-- Tombstones + lanterns scattered through every area
	for _, area in ipairs(spawnAreas()) do
		for _ = 1, 14 do
			local point = randomPointIn(area.Zone)
			if point then
				if rng:NextNumber() < 0.6 then
					makeTombstone(point, decor)
				else
					makeJackOLantern(point + Vector3.new(0, 1.3, 0), rng:NextNumber(2.2, 3.4)).Parent = decor
				end
			end
		end
	end
end

local function applyLighting()
	local cfg = EventConfig.Lighting
	Lighting.OutdoorAmbient = cfg.OutdoorAmbient
	Lighting.FogColor = cfg.FogColor
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = cfg.AtmosphereDensity
	atmosphere.Color = cfg.AtmosphereColor
	atmosphere.Decay = Color3.fromRGB(70, 30, 90)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 2
	atmosphere.Parent = Lighting
	local correction: ColorCorrectionEffect = (Lighting:FindFirstChild("EventTint") :: any) or Instance.new("ColorCorrectionEffect")
	correction.Name = "EventTint"
	correction.TintColor = cfg.Tint
	correction.Saturation = 0.15
	correction.Parent = Lighting
end

-- Candy pumpkins ----------------------------------------------------------------------------------------
local function spawnPumpkin(areas: { { Zone: BasePart, Bonus: number } })
	if #areas == 0 then
		return
	end
	local area = areas[rng:NextInteger(1, #areas)]
	local point = randomPointIn(area.Zone)
	if not point then
		return
	end
	local golden = rng:NextNumber() < EventConfig.GoldenPumpkinChance
	local model = makeJackOLantern(point + Vector3.new(0, 1.2, 0), golden and 2.6 or 2.2, golden)
	local candy = golden and EventConfig.GoldenPumpkinCandy
		or rng:NextInteger(EventConfig.PumpkinCandy.Min, EventConfig.PumpkinCandy.Max) + area.Bonus
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Collect Candy"
	prompt.ObjectText = golden and "Golden Pumpkin" or "Pumpkin"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	local taken = false
	prompt.Triggered:Connect(function(player)
		if taken or not RateLimiter.Check(player, "Pumpkin", 0.25) then
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local body = model.PrimaryPart
		if not root or not body or (root.Position - body.Position).Magnitude > 14 then
			return
		end
		taken = true
		EventService:AddCandy(player, candy, true)
		Services.PlayerDataService:Notify(player, "+" .. candy .. " Candy!", golden and "warning" or "success")
		model:Destroy()
	end)
	model.Destroying:Connect(function()
		pumpkinCount -= 1
	end)
	pumpkinCount += 1
	model.Parent = pumpkinFolder
	-- Pumpkins rot after a while so they keep moving around
	task.delay(180, function()
		if model.Parent then
			model:Destroy()
		end
	end)
end

-- Lifecycle ------------------------------------------------------------------------------------------------
function EventService:Init(services)
	Services = services
end

function EventService:Start()
	Remotes.Function("BuyEventItem").OnServerInvoke = function(player, itemId)
		if not RateLimiter.Check(player, "EventShop", 0.3) then
			return { ok = false, msg = "Slow down!" }
		end
		local result = self:BuyItem(player, itemId)
		Services.PlayerDataService:MarkDirty(player)
		return result
	end

	Workspace:SetAttribute("EventActive", self:IsActive())
	Workspace:SetAttribute("EventName", EventConfig.Name)
	Workspace:SetAttribute("EventEndsAt", EventConfig.EndsAt)
	if not self:IsActive() then
		return
	end

	pumpkinFolder = Instance.new("Folder")
	pumpkinFolder.Name = "CandyPumpkins"
	pumpkinFolder.Parent = Workspace

	applyLighting()
	task.spawn(decorate)

	task.spawn(function()
		local areas = spawnAreas()
		while self:IsActive() do
			if pumpkinCount < EventConfig.MaxPumpkins then
				spawnPumpkin(areas)
			end
			task.wait(EventConfig.PumpkinRespawnSeconds)
		end
		Workspace:SetAttribute("EventActive", false)
		Remotes.Event("Announce"):FireAllClients("The " .. EventConfig.Name .. " has ended. See you next year!", Color3.fromRGB(255, 140, 40))
	end)
end

return EventService
