--[[
	RewardService
	Reasons to come back every day and to keep playing:
	  * Daily login streak (7-day cycle, resets if you miss a UTC day)
	  * Playtime gifts (unlock after N minutes in the current session)
	  * Daily quests (3 per day, chosen per player, + a bonus for finishing all 3)

	Other services report progress with RewardService:Progress(player, kind, amount).
	Kinds: Deliver, DeliverRare, DeliverNight, BaseSteal, Hatch, BuySpeed, Bonk, Candy
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RewardConfig = require(Shared.Config.RewardConfig)
local Remotes = require(Shared.Remotes)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Rewards = require(script.Parent.Parent.Util.Rewards)

local RewardService = {}

local Services: any
local sessionStart: { [Player]: number } = {}
local playtimeClaimed: { [Player]: { [number]: boolean } } = {}

local questById = {}
for _, quest in ipairs(RewardConfig.QuestPool) do
	questById[quest.Id] = quest
end

-- Daily streak ---------------------------------------------------------------------------------------
local function dailyState(data: any): (boolean, number)
	local today = RewardConfig.Today()
	local canClaim = data.Daily.LastClaimDay < today
	local nextDay
	if data.Daily.LastClaimDay == today - 1 or data.Daily.LastClaimDay == today then
		nextDay = data.Daily.Streak % #RewardConfig.Daily + 1
	else
		nextDay = 1 -- streak broken (or first time)
	end
	if not canClaim then
		nextDay = (data.Daily.Streak - 1) % #RewardConfig.Daily + 1 -- today's (already claimed) day
	end
	return canClaim, nextDay
end

function RewardService:ClaimDaily(player: Player)
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return { ok = false, msg = "Data not loaded yet." }
	end
	local canClaim, day = dailyState(data)
	if not canClaim then
		return { ok = false, msg = "Come back tomorrow for your next gift!" }
	end
	local today = RewardConfig.Today()
	local continued = data.Daily.LastClaimDay == today - 1
	data.Daily.Streak = continued and data.Daily.Streak + 1 or 1
	data.Daily.LastClaimDay = today
	data.Stats.DaysPlayed += 1
	local granted = Rewards.Grant(Services, player, RewardConfig.Daily[day].Rewards)
	Services.PlayerDataService:MarkDirty(player)
	return { ok = true, msg = string.format("Day %d reward: %s (streak %d)", day, table.concat(granted, ", "), data.Daily.Streak) }
end

-- Playtime gifts ---------------------------------------------------------------------------------------
function RewardService:ClaimPlaytime(player: Player, index: any)
	index = tonumber(index)
	local gift = index and RewardConfig.Playtime[index]
	local start = sessionStart[player]
	if not gift or not start then
		return { ok = false }
	end
	local claimed = playtimeClaimed[player]
	if claimed[index] then
		return { ok = false, msg = "Already claimed." }
	end
	if os.clock() - start < gift.Minutes * 60 then
		return { ok = false, msg = "Not ready yet!" }
	end
	claimed[index] = true
	local granted = Rewards.Grant(Services, player, gift.Rewards)
	return { ok = true, msg = "Gift: " .. table.concat(granted, ", ") }
end

-- Daily quests ------------------------------------------------------------------------------------------
local function ensureQuests(player: Player, data: any)
	local today = RewardConfig.Today()
	if data.Quests.Day == today and #data.Quests.List > 0 then
		return
	end
	local eventActive = Services.EventService:IsActive()
	local pool = {}
	for _, quest in ipairs(RewardConfig.QuestPool) do
		if not quest.EventOnly or eventActive then
			table.insert(pool, quest)
		end
	end
	-- Deterministic per player per day, so rejoining doesn't reroll.
	local rng = Random.new(today * 7919 + player.UserId)
	local list = {}
	local usedKinds = {}
	while #list < RewardConfig.QuestsPerDay and #pool > 0 do
		local quest = table.remove(pool, rng:NextInteger(1, #pool))
		if not usedKinds[quest.Kind] then
			usedKinds[quest.Kind] = true
			table.insert(list, { Id = quest.Id, Progress = 0, Claimed = false })
		end
	end
	data.Quests = { Day = today, List = list, BonusClaimed = false }
end

function RewardService:Progress(player: Player, kind: string, amount: number?)
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return
	end
	ensureQuests(player, data)
	local changed = false
	for _, entry in ipairs(data.Quests.List) do
		local quest = questById[entry.Id]
		if quest and quest.Kind == kind and entry.Progress < quest.Goal then
			entry.Progress = math.min(quest.Goal, entry.Progress + (amount or 1))
			changed = true
			if entry.Progress >= quest.Goal then
				Services.PlayerDataService:Notify(player, "Quest complete: " .. quest.Text .. "! Claim it in Gifts.", "success")
			end
		end
	end
	if changed then
		Services.PlayerDataService:MarkDirty(player)
	end
end

function RewardService:ClaimQuest(player: Player, which: any)
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return { ok = false }
	end
	ensureQuests(player, data)
	if which == "Bonus" then
		if data.Quests.BonusClaimed then
			return { ok = false, msg = "Bonus already claimed today." }
		end
		for _, entry in ipairs(data.Quests.List) do
			if not entry.Claimed then
				return { ok = false, msg = "Claim all 3 quests first!" }
			end
		end
		data.Quests.BonusClaimed = true
		local granted = Rewards.Grant(Services, player, RewardConfig.AllQuestsBonus)
		return { ok = true, msg = "All quests bonus: " .. table.concat(granted, ", ") }
	end
	local index = tonumber(which)
	local entry = index and data.Quests.List[index]
	local quest = entry and questById[entry.Id]
	if not entry or not quest then
		return { ok = false }
	end
	if entry.Claimed then
		return { ok = false, msg = "Already claimed." }
	end
	if entry.Progress < quest.Goal then
		return { ok = false, msg = "Not finished yet." }
	end
	entry.Claimed = true
	local granted = Rewards.Grant(Services, player, quest.Rewards)
	return { ok = true, msg = "Quest reward: " .. table.concat(granted, ", ") }
end

-- Snapshot for the UI ---------------------------------------------------------------------------------------
function RewardService:GetSnapshot(player: Player)
	local data = Services.PlayerDataService:GetData(player)
	if not data then
		return nil
	end
	ensureQuests(player, data)
	local canClaim, day = dailyState(data)
	local quests = {}
	for i, entry in ipairs(data.Quests.List) do
		local quest = questById[entry.Id]
		if quest then
			quests[i] = { Text = quest.Text, Goal = quest.Goal, Progress = entry.Progress, Claimed = entry.Claimed }
		end
	end
	local claimed = {}
	for index in pairs(playtimeClaimed[player] or {}) do
		table.insert(claimed, index)
	end
	return {
		DailyCanClaim = canClaim,
		DailyDay = day,
		DailyStreak = data.Daily.Streak,
		SessionSeconds = sessionStart[player] and math.floor(os.clock() - sessionStart[player]) or 0,
		PlaytimeClaimed = claimed,
		Quests = quests,
		QuestBonusClaimed = data.Quests.BonusClaimed,
		NextResetIn = (RewardConfig.Today() + 1) * 86400 - os.time(),
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------
function RewardService:Init(services)
	Services = services
	Services.PlayerDataService.ProfileLoaded:Connect(function(player, data)
		sessionStart[player] = os.clock()
		playtimeClaimed[player] = {}
		ensureQuests(player, data)
		local canClaim = dailyState(data)
		if canClaim then
			Services.PlayerDataService:Notify(player, "Your daily gift is ready! Open Gifts to claim it.", "warning")
		end
	end)
end

function RewardService:Start()
	Players.PlayerRemoving:Connect(function(player)
		sessionStart[player] = nil
		playtimeClaimed[player] = nil
	end)

	local function guarded(key: string, fn: (Player, any) -> any)
		return function(player: Player, arg: any)
			if not RateLimiter.Check(player, key, 0.4) then
				return { ok = false, msg = "Slow down!" }
			end
			local result = fn(player, arg)
			Services.PlayerDataService:MarkDirty(player)
			return result
		end
	end
	Remotes.Function("ClaimDaily").OnServerInvoke = guarded("ClaimDaily", function(player)
		return self:ClaimDaily(player)
	end)
	Remotes.Function("ClaimPlaytime").OnServerInvoke = guarded("ClaimPlaytime", function(player, index)
		return self:ClaimPlaytime(player, index)
	end)
	Remotes.Function("ClaimQuest").OnServerInvoke = guarded("ClaimQuest", function(player, which)
		return self:ClaimQuest(player, which)
	end)

	-- Tell players when a playtime gift unlocks.
	task.spawn(function()
		while true do
			task.wait(15)
			for player, start in pairs(sessionStart) do
				local minutes = (os.clock() - start) / 60
				for index, gift in ipairs(RewardConfig.Playtime) do
					local claimed = playtimeClaimed[player]
					if claimed and not claimed[index] and minutes >= gift.Minutes and minutes < gift.Minutes + 0.25 then
						Services.PlayerDataService:Notify(player, "Playtime gift unlocked: " .. gift.Label .. "! Open Gifts.", "warning")
						Services.PlayerDataService:MarkDirty(player)
					end
				end
			end
		end
	end)
end

return RewardService
