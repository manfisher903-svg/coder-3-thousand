--[[
	ModelFactory
	Builds every runtime visual: soul orbs, spirit pets, guardians and tools.

	Placeholder art is generated so the game runs on an empty baseplate. To use real art, drop models in:
		ReplicatedStorage.Assets.Pets.<Species name>   (Model, PrimaryPart set)  -> used for spirit pets
		ReplicatedStorage.Assets.Orbs.<Rarity id>      (Model, PrimaryPart set)  -> used for soul orbs
		ServerStorage.Guardians.<Biome id>             (Model with Humanoid + HumanoidRootPart)
		ServerStorage.Tools.SoulLantern / ReaperScythe (Tool with Handle)
	Anything you add there automatically replaces the placeholder.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetConfig = require(Shared.Config.PetConfig)
local BiomeConfig = require(Shared.Config.BiomeConfig)

local ModelFactory = {}

local function findAsset(root: Instance, ...: string): Instance?
	local current: Instance? = root
	for _, name in ipairs({ ... }) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

-- Billboard with up to N stacked text lines. Returns the gui; lines are named "Line1", "Line2", ...
function ModelFactory.Billboard(adornee: BasePart, lines: { { Text: string, Color: Color3? } }, offsetY: number, maxDistance: number?)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(220, 22 * #lines)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = maxDistance or 90
	gui.LightInfluence = 0
	gui.Adornee = adornee
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = gui
	for i, line in ipairs(lines) do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.LayoutOrder = i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 22)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = line.Text
		label.TextColor3 = line.Color or Color3.new(1, 1, 1)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Parent = label
		label.Parent = gui
	end
	gui.Parent = adornee
	return gui
end

function ModelFactory.SetLine(gui: Instance?, index: number, text: string, color: Color3?)
	if not gui then
		return
	end
	local label = gui:FindFirstChild("Line" .. index)
	if label and label:IsA("TextLabel") then
		label.Text = text
		if color then
			label.TextColor3 = color
		end
	end
end

local function glowPart(name: string, size: Vector3, color: Color3, shape: Enum.PartType): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function addSparkles(parent: BasePart, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Sparkles"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Speed = NumberRange.new(1, 3)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Parent = parent
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 2
	light.Parent = parent
end

local function weldTo(root: BasePart, part: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

-- Soul Orb ---------------------------------------------------------------------
function ModelFactory.MakeOrb(rarityId: string, biomeId: string, mutationId: string?): Model
	local rarity = PetConfig.GetRarity(rarityId)
	local biome = BiomeConfig.Get(biomeId)

	local custom = findAsset(ReplicatedStorage, "Assets", "Orbs", rarityId)
	local model: Model
	local core: BasePart
	if custom and custom:IsA("Model") and custom.PrimaryPart then
		model = custom:Clone()
		core = model.PrimaryPart :: BasePart
	else
		model = Instance.new("Model")
		local size = rarity.OrbSize
		core = glowPart("Core", Vector3.new(size, size, size), rarity.Color, Enum.PartType.Ball)
		core.Parent = model
		local shell = glowPart("Shell", Vector3.new(size * 1.35, size * 1.35, size * 1.35), biome.Color, Enum.PartType.Ball)
		shell.Material = Enum.Material.ForceField
		shell.Transparency = 0.2
		shell.Parent = model
		model.PrimaryPart = core
	end
	model.Name = "SoulOrb"
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	addSparkles(core, rarity.Color, 4 + rarity.Order * 3)
	local mutation = mutationId and PetConfig.Mutations[mutationId]
	ModelFactory.Billboard(core, {
		{ Text = (mutation and (mutation.Id .. " ") or "") .. rarity.Id .. " Soul", Color = mutation and mutation.Color or rarity.Color },
		{ Text = biome.Name, Color = biome.Color },
	}, rarity.OrbSize + 1.2, 120)
	model:SetAttribute("Rarity", rarityId)
	model:SetAttribute("Biome", biomeId)
	CollectionService:AddTag(model, "Bob")
	return model
end

-- Spirit Pet ---------------------------------------------------------------------
function ModelFactory.MakePet(species: string, rarityId: string, mutationId: string, incomeText: string): Model
	local rarity = PetConfig.GetRarity(rarityId)
	local mutation = PetConfig.GetMutation(mutationId)

	local custom = findAsset(ReplicatedStorage, "Assets", "Pets", species)
	local model: Model
	local body: BasePart
	if custom and custom:IsA("Model") and custom.PrimaryPart then
		model = custom:Clone()
		body = model.PrimaryPart :: BasePart
	else
		model = Instance.new("Model")
		local size = 1.6 + rarity.Order * 0.25
		local color = if mutationId ~= "None" then mutation.Color else rarity.Color
		body = glowPart("Body", Vector3.new(size, size, size), color, Enum.PartType.Ball)
		body.Material = Enum.Material.SmoothPlastic
		body.Parent = model
		for _, side in ipairs({ -1, 1 }) do
			local eye = glowPart("Eye", Vector3.new(0.3, 0.45, 0.2), Color3.new(1, 1, 1), Enum.PartType.Block)
			eye.CFrame = body.CFrame * CFrame.new(side * size * 0.2, size * 0.1, -size * 0.48)
			eye.Parent = model
		end
		local aura = glowPart("Aura", Vector3.new(size * 1.3, size * 1.3, size * 1.3), rarity.Color, Enum.PartType.Ball)
		aura.Transparency = 0.75
		aura.Parent = model
		model.PrimaryPart = body
	end
	model.Name = "SpiritPet"
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
	addSparkles(body, rarity.Color, 2 + rarity.Order * 2)
	local lines = {
		{ Text = species, Color = Color3.new(1, 1, 1) },
		{ Text = rarity.Id, Color = rarity.Color },
		{ Text = incomeText, Color = Color3.fromRGB(120, 255, 160) },
	}
	if mutationId ~= "None" then
		table.insert(lines, 2, { Text = mutationId, Color = mutation.Color })
	end
	ModelFactory.Billboard(body, lines, 3.2, 70)
	CollectionService:AddTag(model, "Bob")
	return model
end

-- Guardian ---------------------------------------------------------------------
function ModelFactory.MakeGuardian(biomeId: string): Model
	local biome = BiomeConfig.Get(biomeId)
	local g = biome.Guardian
	local custom = findAsset(ServerStorage, "Guardians", biomeId)
	if custom and custom:IsA("Model") and custom:FindFirstChildOfClass("Humanoid") then
		local clone = custom:Clone()
		clone.Name = g.Name
		return clone
	end

	local scale = g.Scale
	local model = Instance.new("Model")
	model.Name = g.Name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * scale
	root.Transparency = 1
	root.CanCollide = true
	root.Parent = model

	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size = Vector3.new(2.6, 3, 1.6) * scale
	torso.Color = g.Color
	torso.Material = Enum.Material.Neon
	torso.CanCollide = false
	torso.Massless = true
	torso.CFrame = root.CFrame * CFrame.new(0, 0.5 * scale, 0)
	torso.Parent = model
	weldTo(root, torso)

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(2, 2, 2) * scale
	head.Color = g.Color
	head.Material = Enum.Material.Neon
	head.CanCollide = false
	head.Massless = true
	head.CFrame = root.CFrame * CFrame.new(0, 2.6 * scale, 0)
	head.Parent = model
	weldTo(root, head)

	for _, side in ipairs({ -1, 1 }) do
		local eye = Instance.new("Part")
		eye.Name = "Eye"
		eye.Size = Vector3.new(0.4, 0.4, 0.2) * scale
		eye.Color = Color3.fromRGB(255, 30, 30)
		eye.Material = Enum.Material.Neon
		eye.CanCollide = false
		eye.Massless = true
		eye.CFrame = head.CFrame * CFrame.new(side * 0.4 * scale, 0.1 * scale, -0.95 * scale)
		eye.Parent = model
		weldTo(head, eye)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2.2 * scale
	humanoid.WalkSpeed = g.Speed
	humanoid.MaxHealth = math.huge
	humanoid.Health = math.huge
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.Parent = model

	model.PrimaryPart = root
	ModelFactory.Billboard(head, { { Text = g.Name, Color = Color3.fromRGB(255, 80, 80) } }, 2.2 * scale, 120)
	return model
end

-- Tools ----------------------------------------------------------------------------
function ModelFactory.MakeWeapon(isScythe: boolean): Tool
	local name = isScythe and "ReaperScythe" or "SoulLantern"
	local custom = findAsset(ServerStorage, "Tools", name)
	if custom and custom:IsA("Tool") then
		return custom:Clone()
	end
	local tool = Instance.new("Tool")
	tool.Name = isScythe and "Reaper Scythe" or "Soul Lantern"
	tool.ToolTip = "Click near a thief to knock their soul loose!"
	tool.CanBeDropped = false
	tool.RequiresHandle = true

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = isScythe and Vector3.new(0.4, 5, 0.4) or Vector3.new(0.4, 2.4, 0.4)
	handle.Color = isScythe and Color3.fromRGB(40, 40, 40) or Color3.fromRGB(90, 60, 40)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = tool

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Massless = true
	head.CanCollide = false
	head.Material = Enum.Material.Neon
	if isScythe then
		head.Size = Vector3.new(0.3, 0.6, 3.2)
		head.Color = Color3.fromRGB(200, 40, 60)
		head.CFrame = handle.CFrame * CFrame.new(0, 2.4, -1.4)
	else
		head.Shape = Enum.PartType.Ball
		head.Size = Vector3.new(1.2, 1.2, 1.2)
		head.Color = Color3.fromRGB(120, 220, 255)
		head.CFrame = handle.CFrame * CFrame.new(0, 1.6, 0)
		local light = Instance.new("PointLight")
		light.Color = head.Color
		light.Range = 12
		light.Parent = head
	end
	head.Parent = tool
	weldTo(handle, head)
	tool.Grip = CFrame.new(0, -0.8, 0)
	return tool
end

return ModelFactory
