--[[
	Steal a Soul - server bootstrap
	1. Creates RemoteEvents/Functions
	2. Generates a greybox world if you haven't built one yet
	3. Requires every service, calls :Init(Services) on all, then :Start() on all

	Services talk to each other through the shared `Services` table passed into Init,
	so there are no circular require() problems.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local WorldBuilder = require(script.Parent.World.WorldBuilder)

Remotes.Init()
WorldBuilder.EnsureWorld()

local ServicesFolder = script.Parent.Services

-- Order matters only for :Start() (Init never yields and only wires signals).
local ORDER = {
	"PlayerDataService",
	"AntiExploitService",
	"DayNightService",
	"MonetizationService",
	"EconomyService",
	"BaseService",
	"PetService",
	"BiomeService",
	"StealService",
	"GuardianService",
	"UpgradeService",
	"RebirthService",
	"CodesService",
	"ToolService",
}

local Services = {}
for _, name in ipairs(ORDER) do
	local module = ServicesFolder:FindFirstChild(name)
	assert(module, "Missing service module: " .. name)
	Services[name] = require(module)
end

for _, name in ipairs(ORDER) do
	local service = Services[name]
	if service.Init then
		service:Init(Services)
	end
end

-- PlayerDataService starts LAST so every other service has connected its PlayerAdded /
-- ProfileLoaded handlers before the first profile loads.
for _, name in ipairs(ORDER) do
	if name ~= "PlayerDataService" and Services[name].Start then
		Services[name]:Start()
	end
end
Services.PlayerDataService:Start()

print("[SoulHeist] Server ready -", #ORDER, "services running")
