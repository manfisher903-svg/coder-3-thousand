--[[
	LeaderboardService
	Global top-10 boards (OrderedDataStore) for Lifetime Essence, Steals and Rebirths.
	Boards are built in the hub automatically, or use your own: Workspace.Leaderboards.<Essence|Steals|Rebirths>
	(a Part; the board UI is put on its Front face).

	OrderedDataStores only hold integers < 2^63, so Essence is stored as log10(x) * 10,000 and decoded.
	Writes every 2 minutes per player, reads every 2 minutes. Fails quietly in Studio without API access.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Format = require(Shared.Util.Format)

local LeaderboardService = {}

local Services: any
local UPDATE_INTERVAL = 120
local TOP = 10

local BOARDS = {
	{
		Key = "Essence", Title = "Richest Soul Thieves", Store = "LB_Essence_v1",
		Encode = function(data) return math.floor(math.log10(data.Stats.TotalEssence + 1) * 10_000) end,
		Decode = function(value) return Format.Number(10 ^ (value / 10_000) - 1) end,
		Color = Color3.fromRGB(120, 255, 200),
	},
	{
		Key = "Steals", Title = "Most Souls Stolen", Store = "LB_Steals_v1",
		Encode = function(data) return data.Stats.Steals end,
		Decode = function(value) return Format.Number(value) end,
		Color = Color3.fromRGB(255, 140, 60),
	},
	{
		Key = "Rebirths", Title = "Most Rebirths", Store = "LB_Rebirths_v1",
		Encode = function(data) return data.Rebirths end,
		Decode = function(value) return tostring(value) end,
		Color = Color3.fromRGB(230, 120, 255),
	},
}

local nameCache: { [number]: string } = {}

local function getName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	nameCache[userId] = ok and name or ("Player" .. userId)
	return nameCache[userId]
end

local function buildBoardPart(board, index: number, folder: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = board.Key
	part.Anchored = true
	part.Size = Vector3.new(16, 20, 1)
	part.Color = Color3.fromRGB(30, 20, 45)
	part.Material = Enum.Material.SmoothPlastic
	-- In the generated hub: three boards between the bases and the first biome, facing the bases.
	part.CFrame = CFrame.new((index - 2) * 22, 11, 70)
	part.Parent = folder
	return part
end

local function buildGui(board, part: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(400, 500)
	gui.LightInfluence = 0
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 60)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = board.Color
	title.Text = board.Title
	title.Parent = gui
	for rank = 1, TOP do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. rank
		row.Position = UDim2.new(0, 10, 0, 60 + (rank - 1) * 43)
		row.Size = UDim2.new(1, -20, 0, 40)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.FredokaOne
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = rank <= 3 and Color3.fromRGB(255, 215, 80) or Color3.new(1, 1, 1)
		row.Text = rank .. ". ..."
		row.Parent = gui
	end
	gui.Parent = part
	return gui
end

function LeaderboardService:Init(services)
	Services = services
end

function LeaderboardService:Start()
	local folder = Workspace:FindFirstChild("Leaderboards")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Leaderboards"
		folder.Parent = Workspace
	end

	local runtimes = {}
	for index, board in ipairs(BOARDS) do
		local part = folder:FindFirstChild(board.Key)
		if not (part and part:IsA("BasePart")) then
			part = buildBoardPart(board, index, folder)
		end
		local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, board.Store)
		table.insert(runtimes, { Board = board, Gui = buildGui(board, part :: BasePart), Store = ok and store or nil })
	end

	task.spawn(function()
		task.wait(10)
		while true do
			for _, runtime in ipairs(runtimes) do
				local store = runtime.Store
				if store then
					-- Write everyone currently in the server
					for player, data in pairs(Services.PlayerDataService:GetAllLoaded()) do
						local value = runtime.Board.Encode(data)
						if value and value > 0 then
							pcall(store.SetAsync, store, tostring(player.UserId), value)
						end
					end
					-- Read top 10
					local ok, pages = pcall(store.GetSortedAsync, store, false, TOP)
					if ok and pages then
						local entries = pages:GetCurrentPage()
						for rank = 1, TOP do
							local label = runtime.Gui:FindFirstChild("Row" .. rank) :: TextLabel
							local entry = entries[rank]
							if entry then
								label.Text = string.format("%d. %s - %s", rank, getName(tonumber(entry.key) or 0), runtime.Board.Decode(entry.value))
							else
								label.Text = rank .. ". -"
							end
						end
					else
						(runtime.Gui:FindFirstChild("Row1") :: TextLabel).Text = "Leaderboard offline (Studio?)"
					end
				end
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

return LeaderboardService
