--[[
	GuardianService
	Stealth-heist guardian AI. One loop drives every guardian.

	Guardians don't just chase whoever is closest. They have to SEE you:
	  * Vision cone (~150° in front) + line of sight: rocks, ruins and walls hide you
	  * Hearing: anyone very close is noticed from any direction (smaller while sneaking)
	  * Sight range grows with the rarity of the soul you carry (rare souls glow brighter),
	    shrinks while you sneak, and is shorter at night (but guardians move faster)
	  * Break line of sight for 2.5s and they lose you ("?") and walk back
	  * A guardian that spots you ("!") alerts other guardians nearby (backup)
	States: Patrol -> Chase -> Search ("?") -> Return
	Catch: within CatchRadius -> soul knocked loose (unless protected by Halo Ward) + knockback.
	Abilities per biome: SlowPulse (Frost/Crypt/Celestial), Blink (Storm/Void/Abyssal).
	Companion abilities can freeze guardians (FreezeNear) or hide players from them.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BiomeConfig = require(Shared.Config.BiomeConfig)
local PetConfig = require(Shared.Config.PetConfig)
local AbilityConfig = require(Shared.Config.AbilityConfig)
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
	State: "Patrol" | "Chase" | "Search" | "Return",
	Target: Player?,
	LastSeenAt: number,
	LastSeenPosition: Vector3?,
	FrozenUntil: number,
	Info: Instance?,
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
		LastSeenAt = 0,
		LastSeenPosition = nil,
		FrozenUntil = 0,
		Info = model:FindFirstChild("Info", true),
		NextPatrolAt = 0,
		NextCatchAt = 0,
		NextAbilityAt = os.clock() + rng:NextNumber(2, 5),
	}
end

local Stealth = AbilityConfig.Stealth

-- Line of sight from the guardian's eyes to the player. Non-solid parts (orbs, zones, effects) don't block.
local function hasLineOfSight(g: Guardian, player: Player, root: BasePart): boolean
	local origin = g.Root.Position + Vector3.new(0, 2 * (g.Config.Scale or 1), 0)
	local exclude: { Instance } = { g.Model }
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 1, 4 do
		params.FilterDescendantsInstances = exclude
		local result = Workspace:Raycast(origin, root.Position - origin, params)
		if not result then
			return true
		end
		if result.Instance.CanCollide and result.Instance.Transparency < 0.9 then
			return false -- blocked by something solid
		end
		table.insert(exclude, result.Instance)
	end
	return true
end

-- Can this guardian currently perceive this (soul-carrying) player?
local function canPerceive(g: Guardian, player: Player, root: BasePart): boolean
	if Services.StealService:IsHiddenFromGuardians(player) then
		return false
	end
	local offset = root.Position - g.Root.Position
	local distance = offset.Magnitude
	local sneaking = player:GetAttribute("Sneaking") == true
	local hearing = sneaking and Stealth.SneakHearingRadius or Stealth.HearingRadius
	if distance <= hearing then
		return true
	end
	local carried = Services.StealService:GetCarried(player)
	local glow = 1 + (carried and PetConfig.GetRarity(carried.Orb.Rarity).Order or 0) * Stealth.GlowPerRarity
	local sight = g.Config.AggroRadius * glow
	if sneaking then
		sight *= Stealth.SneakSightMult
	end
	if Services.DayNightService:IsNight() then
		sight *= Stealth.NightSightMult
	end
	if distance > sight then
		return false
	end
	local look = g.Root.CFrame.LookVector
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude > 0.1 and Vector3.new(look.X, 0, look.Z).Unit:Dot(flat.Unit) < Stealth.ViewDot then
		return false -- outside the vision cone
	end
	return hasLineOfSight(g, player, root)
end

local function setIndicator(g: Guardian, mark: string?)
	local text = g.Config.Name
	if mark then
		text = mark .. " " .. g.Config.Name .. " " .. mark
	end
	ModelFactory.SetLine(g.Info, 1, text, mark == "!" and Color3.fromRGB(255, 40, 40) or (mark and Color3.fromRGB(255, 220, 80) or Color3.fromRGB(255, 80, 80)))
end

local function isValidTarget(g: Guardian, player: Player, root: BasePart?): boolean
	return root ~= nil
		and Services.StealService:IsCarrying(player)
		and Services.BiomeService:IsInZone(g.Biome, root.Position, LEASH_PADDING)
end

-- Picks a newly-spotted carrier (closest one this guardian can perceive).
local function findTarget(g: Guardian): (Player?, BasePart?)
	local bestPlayer, bestRoot, bestDistance = nil, nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local root = getRoot(player)
		if root and isValidTarget(g, player, root) and canPerceive(g, player, root) then
			local distance = (root.Position - g.Root.Position).Magnitude
			if distance < bestDistance then
				bestPlayer, bestRoot, bestDistance = player, root, distance
			end
		end
	end
	return bestPlayer, bestRoot
end

local function startChase(g: Guardian, player: Player, root: BasePart, alertOthers: boolean)
	local wasChasing = g.State == "Chase" and g.Target == player
	g.State = "Chase"
	g.Target = player
	g.LastSeenAt = os.clock()
	g.LastSeenPosition = root.Position
	setIndicator(g, "!")
	if wasChasing then
		return
	end
	if alertOthers then
		Services.PlayerDataService:Notify(player, g.Config.Name .. " spotted you! RUN or break line of sight!", "error")
		for _, other in ipairs(guardians) do
			if other ~= g and other.Biome == g.Biome and other.State ~= "Chase" and os.clock() >= other.FrozenUntil
				and (other.Root.Position - g.Root.Position).Magnitude <= Stealth.BackupRadius then
				startChase(other, player, root, false)
			end
		end
	end
end

-- Companion ability hook: freezes every guardian within radius. Returns how many were frozen.
function GuardianService:FreezeNear(position: Vector3, radius: number, seconds: number): number
	local count = 0
	for _, g in ipairs(guardians) do
		if (g.Root.Position - position).Magnitude <= radius then
			g.FrozenUntil = os.clock() + seconds
			g.State = "Return"
			g.Target = nil
			setIndicator(g, "*")
			count += 1
		end
	end
	return count
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

	-- Frozen by a Frost Nova / Reaper's Rend
	if now < g.FrozenUntil then
		g.Humanoid.WalkSpeed = 0
		g.Humanoid:MoveTo(g.Root.Position)
		return
	end
	g.Humanoid.WalkSpeed = g.Config.Speed * Services.DayNightService:GetGuardianSpeedMult()

	-- Keep chasing the current target while we can see them (or saw them very recently)
	if g.State == "Chase" or g.State == "Search" then
		local target = g.Target
		local root = target and getRoot(target)
		if target and root and isValidTarget(g, target, root)
			and (root.Position - g.Root.Position).Magnitude <= g.Config.AggroRadius * Stealth.ChaseRangeMult then
			if canPerceive(g, target, root) then
				startChase(g, target, root, false)
			elseif now - g.LastSeenAt > Stealth.LoseTrackSeconds then
				target = nil -- lost them
			else
				g.State = "Search"
				setIndicator(g, "?")
			end
		else
			target = nil
		end

		if target and root then
			local distance = (root.Position - g.Root.Position).Magnitude
			if g.State == "Chase" and distance <= g.Config.CatchRadius and now >= g.NextCatchAt then
				g.NextCatchAt = now + CATCH_COOLDOWN
				if Services.StealService:TryKnockLoose(target, g.Config.Name .. " caught you! Your soul dropped!") then
					Services.StealService:Knockback(target, g.Root.Position, 60)
					Services.StealService:ApplySlow(target, 0.5, 1)
				end
				return
			end
			if g.State == "Chase" then
				useAbility(g, root, distance)
				local lead = root.AssemblyLinearVelocity * 0.3
				g.Humanoid:MoveTo(root.Position + Vector3.new(lead.X, 0, lead.Z))
			elseif g.LastSeenPosition then
				g.Humanoid:MoveTo(g.LastSeenPosition) -- search where we last saw them
			end
			return
		end
		g.State = "Return"
		g.Target = nil
		setIndicator(g, "?")
	end

	-- Look for new intruders
	local spotted, spottedRoot = findTarget(g)
	if spotted and spottedRoot then
		startChase(g, spotted, spottedRoot, true)
		return
	end

	if g.State == "Return" then
		if (g.Root.Position - g.Home).Magnitude < 8 then
			g.State = "Patrol"
			setIndicator(g, nil)
		else
			g.Humanoid:MoveTo(g.Home)
		end
		return
	end

	-- Patrol: wander near home (the vision cone follows the walking direction)
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
