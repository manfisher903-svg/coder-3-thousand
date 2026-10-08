--[[
	WorldBuilder
	Generates a playable GREYBOX map if Workspace.Bases / Workspace.Biomes don't exist yet, so the
	whole game loop works on an empty Baseplate in minutes. Once you build your real map with the same
	names (see docs/05-build-guide.md) this script does nothing.

	Layout (top-down, +Z is "deeper"):
		z = -170 .. 90     Hub with 8 player bases in a row (bases face +Z)
		z = 130 + 140*k    Biome k (Meadow first ... Abyssal last), 700 studs wide
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfig = require(Shared.Config.BiomeConfig)
local GameConfig = require(Shared.Config.GameConfig)

local WorldBuilder = {}

local BASE_SPACING = 90
local BASE_SIZE = 70
local BASE_Z = -60
local BIOME_START_Z = 130
local BIOME_DEPTH = 140
local BIOME_WIDTH = 700

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		if key ~= "Parent" then
			(p :: any)[key] = value
		end
	end
	p.Parent = props.Parent
	return p
end

local function invisible(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	return part({
		Name = name, Size = size, CFrame = cframe, Transparency = 1,
		CanCollide = false, CanTouch = false, CanQuery = false, Parent = parent,
	})
end

local function label(adornee: BasePart, text: string, color: Color3, size: Vector2, offset: Vector3)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size.X, size.Y)
	gui.StudsOffset = offset
	gui.MaxDistance = 250
	gui.LightInfluence = 0
	local text_ = Instance.new("TextLabel")
	text_.Name = "Text"
	text_.Size = UDim2.fromScale(1, 1)
	text_.BackgroundTransparency = 1
	text_.Font = Enum.Font.FredokaOne
	text_.TextScaled = true
	text_.TextColor3 = color
	text_.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = text_
	text_.Parent = gui
	gui.Parent = adornee
end

local function buildBases()
	local bases = Instance.new("Folder")
	bases.Name = "Bases"
	local count = GameConfig.MaxBases
	local firstX = -((count - 1) * BASE_SPACING) / 2

	for i = 1, count do
		local x = firstX + (i - 1) * BASE_SPACING
		local center = Vector3.new(x, 0, BASE_Z)
		local model = Instance.new("Model")
		model.Name = "Base" .. i

		local floor = part({
			Name = "Plot", Size = Vector3.new(BASE_SIZE, 1, BASE_SIZE), CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)),
			Color = Color3.fromRGB(60, 55, 80), Material = Enum.Material.Slate, Parent = model,
		})
		model.PrimaryPart = floor

		invisible("Zone", Vector3.new(BASE_SIZE, 40, BASE_SIZE), CFrame.new(center + Vector3.new(0, 20, 0)), model)

		local barrier = part({
			Name = "Barrier", Size = Vector3.new(BASE_SIZE + 2, 30, BASE_SIZE + 2), CFrame = CFrame.new(center + Vector3.new(0, 15, 0)),
			Material = Enum.Material.ForceField, Color = Color3.fromRGB(120, 200, 255), Transparency = 1,
			CanCollide = false, CanTouch = false, CanQuery = false, Parent = model,
		})
		barrier.CastShadow = false

		invisible("Spawn", Vector3.new(4, 1, 4), CFrame.new(center + Vector3.new(0, 4, BASE_SIZE / 2 - 6)), model)

		local pedestals = Instance.new("Folder")
		pedestals.Name = "Pedestals"
		pedestals.Parent = model
		local index = 0
		for row = 0, 4 do
			for col = 0, 4 do
				index += 1
				local pos = center + Vector3.new(-24 + col * 12, 1.6, -26 + row * 11)
				part({
					Name = "Pedestal" .. index, Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 6, 6),
					CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
					Color = Color3.fromRGB(110, 100, 140), Material = Enum.Material.Marble, Parent = pedestals,
				})
			end
		end

		local button = part({
			Name = "LockButton", Size = Vector3.new(3, 1.5, 3), CFrame = CFrame.new(center + Vector3.new(BASE_SIZE / 2 - 5, 1.75, BASE_SIZE / 2 - 5)),
			Color = Color3.fromRGB(80, 200, 255), Material = Enum.Material.Neon, Parent = model,
		})
		label(button, "LOCK BASE", Color3.fromRGB(120, 220, 255), Vector2.new(150, 40), Vector3.new(0, 3, 0))

		local sign = part({
			Name = "Sign", Size = Vector3.new(16, 6, 1), CFrame = CFrame.new(center + Vector3.new(0, 10, BASE_SIZE / 2)),
			Color = Color3.fromRGB(40, 30, 60), Material = Enum.Material.Neon, Transparency = 0.3, Parent = model,
		})
		label(sign, "Empty Base", Color3.new(1, 1, 1), Vector2.new(300, 70), Vector3.new(0, 0, 0))

		model.Parent = bases
	end
	bases.Parent = Workspace
end

local function buildBiomes()
	local biomes = Instance.new("Folder")
	biomes.Name = "Biomes"
	local rng = Random.new(1337)

	for k, biomeId in ipairs(BiomeConfig.Order) do
		local biome = BiomeConfig.Get(biomeId)
		local z0 = BIOME_START_Z + (k - 1) * BIOME_DEPTH
		local centerZ = z0 + BIOME_DEPTH / 2
		local model = Instance.new("Model")
		model.Name = biomeId

		local ground = part({
			Name = "Ground", Size = Vector3.new(BIOME_WIDTH, 4, BIOME_DEPTH), CFrame = CFrame.new(0, -2, centerZ),
			Color = biome.Color, Material = Enum.Material.Grass, Parent = model,
		})
		model.PrimaryPart = ground

		invisible("Zone", Vector3.new(BIOME_WIDTH, 80, BIOME_DEPTH), CFrame.new(0, 38, centerZ), model)

		local gate = part({
			Name = "Gate", Size = Vector3.new(BIOME_WIDTH, 14, 1), CFrame = CFrame.new(0, 7, z0),
			Color = biome.Color, Material = Enum.Material.ForceField, Transparency = 0.4,
			CanCollide = false, CanTouch = false, CanQuery = false, Parent = model,
		})
		for _, gx in ipairs({ -200, 0, 200 }) do
			local post = invisible("GateLabel", Vector3.new(1, 1, 1), CFrame.new(gx, 10, z0), model)
			label(post, string.format("%s\nRequires %d Speed", biome.Name, biome.SpeedRequired), Color3.new(1, 1, 1), Vector2.new(320, 90), Vector3.new(0, 0, 0))
		end
		gate.CastShadow = false

		local spawns = Instance.new("Folder")
		spawns.Name = "SoulSpawns"
		spawns.Parent = model
		for s = 1, biome.MaxOrbs + 4 do
			local px = rng:NextNumber(-BIOME_WIDTH / 2 + 30, BIOME_WIDTH / 2 - 30)
			local pz = rng:NextNumber(z0 + 35, z0 + BIOME_DEPTH - 10)
			invisible("Spawn" .. s, Vector3.new(2, 1, 2), CFrame.new(px, 3.5, pz), spawns)
		end

		local guardianSpawns = Instance.new("Folder")
		guardianSpawns.Name = "GuardianSpawns"
		guardianSpawns.Parent = model
		for s = 1, biome.Guardian.Count do
			local px = -BIOME_WIDTH / 2 + (s / (biome.Guardian.Count + 1)) * BIOME_WIDTH
			invisible("GuardianSpawn" .. s, Vector3.new(2, 1, 2), CFrame.new(px, 5, centerZ + 10), guardianSpawns)
		end

		-- Cover / obstacles so chases have line-of-sight breaks
		for _ = 1, 18 do
			local h = rng:NextNumber(6, 16)
			part({
				Name = "Rock", Size = Vector3.new(rng:NextNumber(6, 14), h, rng:NextNumber(6, 14)),
				CFrame = CFrame.new(rng:NextNumber(-320, 320), h / 2, rng:NextNumber(z0 + 20, z0 + BIOME_DEPTH - 10)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				Color = biome.Color:Lerp(Color3.new(0, 0, 0), 0.45), Material = Enum.Material.Rock, Parent = model,
			})
		end

		model.Parent = biomes
	end
	biomes.Parent = Workspace
end

local function buildHub()
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	local endZ = BIOME_START_Z + #BiomeConfig.Order * BIOME_DEPTH

	part({ Name = "HubGround", Size = Vector3.new(820, 4, 260), CFrame = CFrame.new(0, -2, -40), Color = Color3.fromRGB(45, 40, 60), Material = Enum.Material.Slate, Parent = hub })
	part({ Name = "Path", Size = Vector3.new(BIOME_WIDTH, 4, BIOME_START_Z - 90), CFrame = CFrame.new(0, -2, (90 + BIOME_START_Z) / 2), Color = Color3.fromRGB(70, 65, 90), Material = Enum.Material.Cobblestone, Parent = hub })

	local walls = {
		{ Vector3.new(4, 60, 260), Vector3.new(-410, 30, -40) },
		{ Vector3.new(4, 60, 260), Vector3.new(410, 30, -40) },
		{ Vector3.new(820, 60, 4), Vector3.new(0, 30, -170) },
		{ Vector3.new(4, 60, endZ - 90), Vector3.new(-BIOME_WIDTH / 2, 30, (90 + endZ) / 2) },
		{ Vector3.new(4, 60, endZ - 90), Vector3.new(BIOME_WIDTH / 2, 30, (90 + endZ) / 2) },
		{ Vector3.new(BIOME_WIDTH, 60, 4), Vector3.new(0, 30, endZ) },
		{ Vector3.new(55, 60, 4), Vector3.new(-382, 30, 90) },
		{ Vector3.new(55, 60, 4), Vector3.new(382, 30, 90) },
	}
	for i, w in ipairs(walls) do
		part({ Name = "Wall" .. i, Size = w[1], CFrame = CFrame.new(w[2]), Transparency = 1, Parent = hub })
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, 0.5, 40)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = hub

	hub.Parent = Workspace
end

function WorldBuilder.EnsureWorld()
	local built = false
	if not Workspace:FindFirstChild("Hub") and not Workspace:FindFirstChild("Bases") then
		buildHub()
		built = true
	end
	if not Workspace:FindFirstChild("Bases") then
		buildBases()
		built = true
	end
	if not Workspace:FindFirstChild("Biomes") then
		buildBiomes()
		built = true
	end
	if built then
		local baseplate = Workspace:FindFirstChild("Baseplate")
		if baseplate and baseplate:IsA("BasePart") then
			baseplate.CanCollide = false
			baseplate.Transparency = 1
		end
		print("[WorldBuilder] Generated greybox world (replace with your own map when ready).")
	end
end

return WorldBuilder
