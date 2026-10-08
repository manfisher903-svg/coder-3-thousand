--[[
	DayNightService
	Drives the 10-minute day/night cycle and the Soul Eclipse event.

	Day      : normal spawns.
	Night    : 2x spawn luck, 2x mutation luck, Moonlit mutation unlocked, guardians +20% speed.
	Eclipse  : every 4th night (or bought via "Summon Soul Eclipse"): 5x spawn luck, Eclipsed mutation,
	           guardians +35% speed. Server-wide announcement.

	Replicated as Workspace attributes: IsNight, IsEclipse, EclipseEndsAt, CycleTime
]]

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local Remotes = require(Shared.Remotes)

local DayNightService = {}
DayNightService.PhaseChanged = Signal.new() -- (isNight: boolean, isEclipse: boolean)

local cfg = GameConfig.DayNight
local isNight = false
local purchasedEclipseUntil = 0
local naturalEclipse = false
local nightCount = 0

function DayNightService:IsNight(): boolean
	return isNight
end

function DayNightService:IsEclipse(): boolean
	return naturalEclipse or os.time() < purchasedEclipseUntil
end

function DayNightService:GetSpawnLuck(): number
	if self:IsEclipse() then
		return cfg.Eclipse.SpawnLuck
	elseif isNight then
		return cfg.Night.SpawnLuck
	end
	return 1
end

function DayNightService:GetMutationLuck(): number
	if self:IsEclipse() then
		return cfg.Eclipse.MutationLuck
	elseif isNight then
		return cfg.Night.MutationLuck
	end
	return 1
end

function DayNightService:GetGuardianSpeedMult(): number
	if self:IsEclipse() then
		return cfg.Eclipse.GuardianSpeed
	elseif isNight then
		return cfg.Night.GuardianSpeed
	end
	return 1
end

-- Called by MonetizationService (product) or admins.
function DayNightService:StartEclipse(seconds: number, byName: string?)
	purchasedEclipseUntil = math.max(purchasedEclipseUntil, os.time()) + seconds
	Workspace:SetAttribute("IsEclipse", true)
	Workspace:SetAttribute("EclipseEndsAt", purchasedEclipseUntil)
	local who = byName and (byName .. " summoned a ") or "A "
	Remotes.Event("Announce"):FireAllClients(who .. "SOUL ECLIPSE! 5x soul luck for everyone!", Color3.fromRGB(255, 80, 30))
	self.PhaseChanged:Fire(isNight, true)
end

local function applyLighting(cycleTime: number)
	-- Map the cycle onto ClockTime: day phase 6:00 -> 18:00, night phase 18:00 -> 6:00
	local clock
	if cycleTime < cfg.NightStart then
		clock = 6 + (cycleTime / cfg.NightStart) * 12
	else
		clock = 18 + ((cycleTime - cfg.NightStart) / (cfg.CycleSeconds - cfg.NightStart)) * 12
	end
	Lighting.ClockTime = clock % 24
end

function DayNightService:Init() end

function DayNightService:Start()
	local startClock = os.clock()
	Workspace:SetAttribute("IsNight", false)
	Workspace:SetAttribute("IsEclipse", false)

	task.spawn(function()
		local lastEclipseState = false
		while true do
			local cycleTime = (os.clock() - startClock) % cfg.CycleSeconds
			local nowNight = cycleTime >= cfg.NightStart
			if nowNight ~= isNight then
				isNight = nowNight
				if isNight then
					nightCount += 1
					naturalEclipse = nightCount % cfg.EclipseEveryNthNight == 0
					if naturalEclipse then
						Remotes.Event("Announce"):FireAllClients("A SOUL ECLIPSE rises... rare souls everywhere!", Color3.fromRGB(255, 80, 30))
					else
						Remotes.Event("Announce"):FireAllClients("Night falls. Souls glow brighter... guardians hunt faster.", Color3.fromRGB(140, 150, 255))
					end
				else
					naturalEclipse = false
					Remotes.Event("Announce"):FireAllClients("Dawn breaks. The guardians calm down.", Color3.fromRGB(255, 220, 120))
				end
				Workspace:SetAttribute("IsNight", isNight)
				self.PhaseChanged:Fire(isNight, self:IsEclipse())
			end
			local eclipse = self:IsEclipse()
			if eclipse ~= lastEclipseState then
				lastEclipseState = eclipse
				Workspace:SetAttribute("IsEclipse", eclipse)
				Lighting.Ambient = eclipse and Color3.fromRGB(120, 30, 20) or Color3.fromRGB(70, 70, 90)
			end
			Workspace:SetAttribute("CycleTime", cycleTime)
			applyLighting(cycleTime)
			task.wait(1)
		end
	end)
end

return DayNightService
