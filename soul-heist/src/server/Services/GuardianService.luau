--[[
	GuardianService
	Lightweight guardian chase AI. One loop drives every guardian (cheap: ~20-30 NPCs per server).

	States
		Patrol : wander to random points near home inside the biome zone
		Chase  : target = nearest player CARRYING a soul within AggroRadius and inside the leash
		         (biome zone + LEASH_PADDING). Leads the target slightly using its velocity.
		Return : target escaped the leash -> walk home, then Patrol
	Catch  : within CatchRadius -> the player drops the soul + knockback. Per-guardian cooldown.
	Abilities (optional per biome)
		SlowPulse : AoE slow around the guardian (Frost / Crypt / Celestial)
		Blink     : teleports just behind a fleeing target (Storm / Void / Abyssal)
	Night/Eclipse multiply guardian speed (DayNightService).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfig = require(Shared.Config.BiomeConfig)
local ModelFactory = require(script.Parent.Parent.World.ModelFactory)

local GuardianService = {}

local TICK = 0.15
local LEASH_PADDING = 25
local CATCH_COOLDOWN = 1.5

type Guardian = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Biome: any, -- BiomeRuntime
	Config: any,
	Home: Vector3,
	State: "Patrol" | "Chase" | "Return",
	Target: Player?,
	NextPatrolAt: number,
	NextCatchAt: number,
	NextAbilityAt: number,
}

local Services: any
local guardians: { Guardian } = {}
local rng = Random.new()

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function spawnGuardian(runtime: any, index: number): Guardian?
	local config = runtime.Config.Guardian
	local model = ModelFactory.MakeGuardian(runtime.Id)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		warn("[GuardianService] Guardian model for " .. runtime.Id .. " needs a Humanoid and HumanoidRootPart")
		return nil
	end
	local spawnPart = runtime.GuardianSpawns[((index - 1) % math.max(#runtime.GuardianSpawns, 1)) + 1]
	local home = spawnPart and spawnPart.Position or runtime.Zone.Position
	model:PivotTo(CFrame.new(home + Vector3.new(0, 4, 0)))
	model.Parent = runtime.Model
	root:SetNetworkOwner(nil) -- server-simulated: exploiters can't fling/freeze guardians

	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Biome = runtime,
		Config = config,
		Home = home,
		State = "Patrol",
		Target = nil,
		NextPatrolAt = 0,
		NextCatchAt = 0,
		NextAbilityAt = os.clock() + rng:NextNumber(2, 5),
	}
end

-- Finds the closest player carrying a soul inside this guardian's aggro + leash.
local function findTarget(g: Guardian): (Player?, BasePart?)
	local bestPlayer, bestRoot, bestDistance = nil, nil, g.Config.AggroRadius
	for _, player in ipairs(Players:GetPlayers()) do
		if Services.StealService:IsCarrying(player) then
			local root = getRoot(player)
			if root and Services.BiomeService:IsInZone(g.Biome, root.Position, LEASH_PADDING) then
				local distance = (root.Position - g.Root.Position).Magnitude
				if distance < bestDistance then
					bestPlayer, bestRoot, bestDistance = player, root, distance
				end
			end
		end
	end
	return bestPlayer, bestRoot
end

local function pulseEffect(position: Vector3, radius: number, color: Color3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.5
	ring.Size = Vector3.new(0.4, radius * 2, radius * 2)
	ring.CFrame = CFrame.new(position - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	game:GetService("Debris"):AddItem(ring, 0.4)
end

local function useAbility(g: Guardian, targetRoot: BasePart, distance: number)
	local ability = g.Config.Ability
	if not ability or os.clock() < g.NextAbilityAt then
		return
	end
	if ability.Type == "SlowPulse" and distance <= (ability.Radius or 15) then
		g.NextAbilityAt = os.clock() + ability.Cooldown
		pulseEffect(g.Root.Position, ability.Radius or 15, g.Config.Color)
		for _, player in ipairs(Players:GetPlayers()) do
			local root = getRoot(player)
			if root and (root.Position - g.Root.Position).Magnitude <= (ability.Radius or 15) then
				Services.StealService:ApplySlow(player, ability.SlowFactor or 0.6, ability.Duration or 1.5)
			end
		end
	elseif ability.Type == "Blink" and distance >= (ability.MinDistance or 20) then
		g.NextAbilityAt = os.clock() + ability.Cooldown
		local toGuardian = g.Root.Position - targetRoot.Position
		toGuardian = Vector3.new(toGuardian.X, 0, toGuardian.Z)
		if toGuardian.Magnitude > 0.1 then
			local destination = targetRoot.Position + toGuardian.Unit * (ability.BehindDistance or 9)
			pulseEffect(g.Root.Position, 4, g.Config.Color)
			g.Model:PivotTo(CFrame.lookAt(destination, targetRoot.Position))
			pulseEffect(destination, 4, g.Config.Color)
		end
	end
end

local function tick(g: Guardian)
	if g.Root.Position.Y < -50 then -- fell off the map
		g.Model:PivotTo(CFrame.new(g.Home + Vector3.new(0, 4, 0)))
	end
	local now = os.clock()
	g.Humanoid.WalkSpeed = g.Config.Speed * Services.DayNightService:GetGuardianSpeedMult()

	local target, targetRoot = findTarget(g)
	if target and targetRoot then
		g.State = "Chase"
		g.Target = target
		local distance = (targetRoot.Position - g.Root.Position).Magnitude
		if distance <= g.Config.CatchRadius and now >= g.NextCatchAt then
			g.NextCatchAt = now + CATCH_COOLDOWN
			Services.StealService:Drop(target, g.Config.Name .. " caught you! Your soul dropped!")
			Services.StealService:Knockback(target, g.Root.Position, 60)
			Services.StealService:ApplySlow(target, 0.5, 1)
			return
		end
		useAbility(g, targetRoot, distance)
		local lead = targetRoot.AssemblyLinearVelocity * 0.3
		g.Humanoid:MoveTo(targetRoot.Position + Vector3.new(lead.X, 0, lead.Z))
		return
	end

	if g.State == "Chase" then
		g.State = "Return"
		g.Target = nil
	end

	if g.State == "Return" then
		if (g.Root.Position - g.Home).Magnitude < 8 then
			g.State = "Patrol"
		else
			g.Humanoid:MoveTo(g.Home)
		end
		return
	end

	-- Patrol
	if now >= g.NextPatrolAt then
		g.NextPatrolAt = now + rng:NextNumber(3, 7)
		local offset = Vector3.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-30, 30))
		local point = g.Home + offset
		if Services.BiomeService:IsInZone(g.Biome, point) then
			g.Humanoid:MoveTo(point)
		end
	end
end

function GuardianService:Init(services)
	Services = services
end

function GuardianService:Start()
	for _, runtime in ipairs(Services.BiomeService:GetRuntimes()) do
		local config = BiomeConfig.Get(runtime.Id).Guardian
		for i = 1, config.Count do
			local g = spawnGuardian(runtime, i)
			if g then
				table.insert(guardians, g)
			end
		end
	end

	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, g in ipairs(guardians) do
				local ok, err = pcall(tick, g)
				if not ok then
					warn("[GuardianService] tick error:", err)
				end
			end
		end
	end)
end

return GuardianService
