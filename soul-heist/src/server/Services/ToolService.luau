--[[
	ToolService
	Light PvP: every player gets a Soul Lantern; Reaper Scythe pass owners get the Scythe.
	Hit detection is 100% server-side (Tool.Activated replicates to the server): the server finds the
	closest player in front of the attacker within range. The client never sends a target.

	Hitting a player who is CARRYING a soul knocks it loose (it drops on the ground) + short stun.
	Hitting a non-carrier only knocks them back a little (no griefing value).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ModelFactory = require(script.Parent.Parent.World.ModelFactory)

local ToolService = {}

local Services: any
local lastSwing: { [Player]: number } = {}

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function findVictim(attacker: Player, range: number): Player?
	local root = getRoot(attacker)
	if not root then
		return nil
	end
	local best, bestDistance = nil, range
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= attacker then
			local otherRoot = getRoot(other)
			local humanoid = other.Character and other.Character:FindFirstChildOfClass("Humanoid")
			if otherRoot and humanoid and humanoid.Health > 0 then
				local offset = otherRoot.Position - root.Position
				local distance = offset.Magnitude
				-- Must be roughly in front (60° cone) unless point-blank.
				local inFront = distance < 4 or root.CFrame.LookVector:Dot(offset.Unit) > 0.5
				if distance <= bestDistance and inFront then
					best, bestDistance = other, distance
				end
			end
		end
	end
	return best
end

local function onSwing(player: Player, isScythe: boolean)
	local stats = isScythe and GameConfig.Scythe or GameConfig.Lantern
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < stats.Cooldown then
		return
	end
	lastSwing[player] = now
	local victim = findVictim(player, stats.Range)
	local root = getRoot(player)
	if not victim or not root then
		return
	end
	if Services.StealService:IsCarrying(victim) then
		Services.StealService:Drop(victim, player.DisplayName .. " knocked your soul loose!")
		Services.StealService:ApplySlow(victim, 0.3, stats.StunSeconds)
		Services.StealService:Knockback(victim, root.Position, stats.Knockback)
		Services.PlayerDataService:Notify(player, "You knocked " .. victim.DisplayName .. "'s soul loose! Grab it!", "success")
	else
		Services.StealService:Knockback(victim, root.Position, stats.Knockback * 0.4)
	end
end

function ToolService:GiveTools(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack or not player.Character then
		return
	end
	local hasScythe = Services.MonetizationService:HasPass(player, "ReaperScythe")
	local function has(name: string): boolean
		return backpack:FindFirstChild(name) ~= nil or player.Character:FindFirstChild(name) ~= nil
	end
	local function give(isScythe: boolean)
		local tool = ModelFactory.MakeWeapon(isScythe)
		if has(tool.Name) then
			tool:Destroy()
			return
		end
		tool.Activated:Connect(function()
			onSwing(player, isScythe)
		end)
		tool.Parent = backpack
	end
	give(false)
	if hasScythe then
		give(true)
	end
end

function ToolService:Init(services)
	Services = services
end

function ToolService:Start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.5)
			Services.MonetizationService:WaitForPasses(player)
			self:GiveTools(player)
		end)
		if player.Character then
			task.spawn(self.GiveTools, self, player)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
end

return ToolService
