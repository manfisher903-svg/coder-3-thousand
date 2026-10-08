--[[
	BaseService
	Assigns each player a base (plot), handles spawning at home, base lock + Soul Shield,
	new-player protection and intruder push-out.

	Workspace.Bases.BaseN (Model) must contain:
		Zone (Part)          invisible box = the base area (delivery + lock area)
		Pedestals (Folder)   Pedestal1..Pedestal25 (Parts)
		Spawn (Part)         where the owner spawns
		Barrier (Part)       visual force field shown while locked
		LockButton (Part)    owner presses to lock
		Sign (Part)          shows owner's name (BillboardGui with a TextLabel named "Text")
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Format = require(Shared.Util.Format)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

export type BaseInfo = {
	Model: Model,
	Zone: BasePart,
	Pedestals: { BasePart },
	Spawn: BasePart,
	Barrier: BasePart?,
	LockButton: BasePart?,
	Sign: BasePart?,
	Owner: Player?,
	LockedUntil: number,
	LockCooldownUntil: number,
}

local BaseService = {}

local Services: any
local bases: { BaseInfo } = {}
local baseByPlayer: { [Player]: BaseInfo } = {}

local function numberSuffix(name: string): number
	return tonumber(string.match(name, "%d+$")) or 0
end

local function setSignText(base: BaseInfo, text: string)
	if not base.Sign then
		return
	end
	local label = base.Sign:FindFirstChild("Text", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function BaseService:IsPointInBase(base: BaseInfo, position: Vector3): boolean
	local localPos = base.Zone.CFrame:PointToObjectSpace(position)
	local half = base.Zone.Size / 2
	return math.abs(localPos.X) <= half.X and math.abs(localPos.Y) <= half.Y and math.abs(localPos.Z) <= half.Z
end

function BaseService:GetBase(player: Player): BaseInfo?
	return baseByPlayer[player]
end

function BaseService:GetBaseOfUserId(userId: number): (BaseInfo?, Player?)
	for player, base in pairs(baseByPlayer) do
		if player.UserId == userId then
			return base, player
		end
	end
	return nil, nil
end

function BaseService:IsPlayerInOwnBase(player: Player): boolean
	local base = baseByPlayer[player]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return base ~= nil and root ~= nil and self:IsPointInBase(base, root.Position)
end

function BaseService:IsLocked(base: BaseInfo): boolean
	return os.clock() < base.LockedUntil
end

-- Returns true + reason if `owner`'s base can't be robbed right now.
function BaseService:IsProtected(owner: Player): (boolean, string?)
	local base = baseByPlayer[owner]
	local data = Services.PlayerDataService:GetData(owner)
	if not base or not data then
		return true, "That base is empty."
	end
	if self:IsLocked(base) then
		return true, "That base is locked!"
	end
	if os.time() < (data.ShieldUntil or 0) then
		return true, "That base has a Soul Shield!"
	end
	if data.Stats.PlayTime < GameConfig.NewPlayerProtectionSeconds and data.Rebirths == 0 then
		return true, "New players are protected for their first 15 minutes."
	end
	return false, nil
end

function BaseService:Lock(player: Player): (boolean, string?)
	local base = baseByPlayer[player]
	if not base then
		return false, "You don't have a base."
	end
	local now = os.clock()
	if now < base.LockedUntil then
		return false, "Already locked."
	end
	if now < base.LockCooldownUntil then
		return false, "Lock recharging: " .. Format.Time(base.LockCooldownUntil - now)
	end
	local fortress = Services.MonetizationService:HasPass(player, "Fortress")
	local duration = GameConfig.BaseLockDuration * (fortress and 2 or 1)
	local cooldown = GameConfig.BaseLockCooldown * (fortress and 0.5 or 1)
	base.LockedUntil = now + duration
	base.LockCooldownUntil = now + duration + cooldown
	player:SetAttribute("BaseLockedUntil", os.time() + duration)
	player:SetAttribute("BaseLockReadyAt", os.time() + duration + cooldown)
	if base.Barrier then
		base.Barrier.Transparency = 0.6
	end
	return true, string.format("Base locked for %ds!", duration)
end

function BaseService:TeleportHome(player: Player)
	local base = baseByPlayer[player]
	local character = player.Character
	if base and character then
		Services.AntiExploitService:Teleport(player, base.Spawn.CFrame + Vector3.new(0, 3, 0))
	end
end

local function assignBase(player: Player)
	if baseByPlayer[player] then
		return
	end
	for _, base in ipairs(bases) do
		if base.Owner == nil then
			base.Owner = player
			base.LockedUntil = 0
			base.LockCooldownUntil = 0
			baseByPlayer[player] = base
			player:SetAttribute("BaseName", base.Model.Name)
			setSignText(base, player.DisplayName .. "'s Soul Sanctum")
			Services.PetService:RenderBase(player)
			BaseService:TeleportHome(player)
			return
		end
	end
	player:Kick("This server is full of soul thieves - please join another server.")
end

local function releaseBase(player: Player)
	local base = baseByPlayer[player]
	if not base then
		return
	end
	baseByPlayer[player] = nil
	Services.PetService:ClearBase(base)
	base.Owner = nil
	base.LockedUntil = 0
	if base.Barrier then
		base.Barrier.Transparency = 1
	end
	setSignText(base, "Empty Base")
end

local function pushOut(base: BaseInfo, player: Player, root: BasePart)
	local center = base.Zone.Position
	local offset = Vector3.new(root.Position.X - center.X, 0, root.Position.Z - center.Z)
	if offset.Magnitude < 0.1 then
		offset = Vector3.new(0, 0, 1)
	end
	local radius = math.max(base.Zone.Size.X, base.Zone.Size.Z) / 2 + 8
	local target = center + offset.Unit * radius
	Services.AntiExploitService:Teleport(player, CFrame.new(target.X, root.Position.Y + 2, target.Z))
	Services.PlayerDataService:Notify(player, "That base is locked!", "error")
end

function BaseService:Init(services)
	Services = services
	local folder = Workspace:WaitForChild("Bases")
	local models = folder:GetChildren()
	table.sort(models, function(a, b)
		return numberSuffix(a.Name) < numberSuffix(b.Name)
	end)
	for _, model in ipairs(models) do
		if model:IsA("Model") then
			local pedestalsFolder = model:FindFirstChild("Pedestals")
			local pedestals = {}
			if pedestalsFolder then
				for _, p in ipairs(pedestalsFolder:GetChildren()) do
					if p:IsA("BasePart") then
						table.insert(pedestals, p)
					end
				end
				table.sort(pedestals, function(a, b)
					return numberSuffix(a.Name) < numberSuffix(b.Name)
				end)
			end
			local zone = model:FindFirstChild("Zone")
			local spawn = model:FindFirstChild("Spawn")
			if not (zone and zone:IsA("BasePart") and spawn and spawn:IsA("BasePart")) then
				warn("[BaseService] " .. model:GetFullName() .. " is missing Zone or Spawn - skipped")
				continue
			end
			local base: BaseInfo = {
				Model = model,
				Zone = zone,
				Pedestals = pedestals,
				Spawn = spawn,
				Barrier = model:FindFirstChild("Barrier") :: BasePart?,
				LockButton = model:FindFirstChild("LockButton") :: BasePart?,
				Sign = model:FindFirstChild("Sign") :: BasePart?,
				Owner = nil,
				LockedUntil = 0,
				LockCooldownUntil = 0,
			}
			if base.LockButton then
				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Lock Base"
				prompt.ObjectText = "Soul Barrier"
				prompt.HoldDuration = 0.3
				prompt.MaxActivationDistance = 10
				prompt.RequiresLineOfSight = false
				prompt.Parent = base.LockButton
				prompt.Triggered:Connect(function(player)
					if base.Owner ~= player then
						Services.PlayerDataService:Notify(player, "This isn't your base!", "error")
						return
					end
					local ok, msg = BaseService:Lock(player)
					Services.PlayerDataService:Notify(player, msg or "", ok and "success" or "error")
				end)
			end
			table.insert(bases, base)
		end
	end

	Services.PlayerDataService.ProfileLoaded:Connect(function(player)
		assignBase(player)
	end)
end

function BaseService:Start()
	Players.PlayerRemoving:Connect(releaseBase)

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 5)
			task.wait(0.2) -- let the default spawn finish before moving them home
			self:TeleportHome(player)
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in ipairs(Players:GetPlayers()) do
		hookCharacter(player)
	end

	Remotes.Function("RequestLock").OnServerInvoke = function(player)
		if not RateLimiter.Check(player, "Lock", 0.5) then
			return { ok = false, msg = "Slow down!" }
		end
		local ok, msg = self:Lock(player)
		return { ok = ok, msg = msg }
	end

	-- Lock enforcement + barrier visuals
	task.spawn(function()
		while true do
			task.wait(0.2)
			for _, base in ipairs(bases) do
				local owner = base.Owner
				if owner then
					local locked = self:IsLocked(base)
					if not locked and base.Barrier and base.Barrier.Transparency < 1 then
						base.Barrier.Transparency = 1
					end
					if locked then
						for _, other in ipairs(Players:GetPlayers()) do
							if other ~= owner then
								local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
								if root and self:IsPointInBase(base, root.Position) then
									pushOut(base, other, root)
								end
							end
						end
					end
				end
			end
		end
	end)
end

return BaseService
