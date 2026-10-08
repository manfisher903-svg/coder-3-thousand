--[[
	RateLimiter
	Per-player, per-action cooldowns for anything a client can trigger.
	RateLimiter.Check(player, "Upgrade", 0.15) -> true if allowed (and records the call).
]]

local Players = game:GetService("Players")

local RateLimiter = {}

local lastCall: { [Player]: { [string]: number } } = {}

function RateLimiter.Check(player: Player, key: string, cooldown: number): boolean
	local now = os.clock()
	local calls = lastCall[player]
	if not calls then
		calls = {}
		lastCall[player] = calls
	end
	local previous = calls[key]
	if previous and now - previous < cooldown then
		return false
	end
	calls[key] = now
	return true
end

Players.PlayerRemoving:Connect(function(player)
	lastCall[player] = nil
end)

return RateLimiter
