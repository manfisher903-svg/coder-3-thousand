--[[
	Steal a Soul - client
	Builds the whole HUD in code (no manual UI work needed), listens to server state and sends requests.
	The client is display-only: every action is validated by the server.

	Panels: Upgrades | Spirits | Rebirth | Shop | Codes   + Lock Base button, carry bar, toasts, banners.
	Replace the look later by editing THEME or swapping in your own ScreenGui - the data wiring stays the same.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PolicyService = game:GetService("PolicyService")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Formulas = require(Shared:WaitForChild("Formulas"))
local Format = require(Shared.Util:WaitForChild("Format"))
local EconomyConfig = require(Shared.Config:WaitForChild("EconomyConfig"))
local PetConfig = require(Shared.Config:WaitForChild("PetConfig"))
local BiomeConfig = require(Shared.Config:WaitForChild("BiomeConfig"))
local MonetizationConfig = require(Shared.Config:WaitForChild("MonetizationConfig"))

local THEME = {
	Bg = Color3.fromRGB(22, 16, 38),
	Panel = Color3.fromRGB(36, 26, 60),
	Row = Color3.fromRGB(52, 40, 84),
	Accent = Color3.fromRGB(140, 90, 255),
	Good = Color3.fromRGB(70, 200, 120),
	Bad = Color3.fromRGB(220, 70, 90),
	Gold = Color3.fromRGB(255, 200, 60),
	Text = Color3.fromRGB(245, 240, 255),
	SubText = Color3.fromRGB(190, 180, 220),
	Font = Enum.Font.FredokaOne,
}

local snapshot: any = nil
local serverTimeOffset = 0

-- Regions that restrict paid random items: hide products whose hatch outcome is random.
local RANDOM_ITEM_PRODUCTS = { LegendaryOrb = true, MythicOrb = true, StarterPack = true }
local paidRandomRestricted = false
task.spawn(function()
	local ok, policy = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	paidRandomRestricted = not ok or (policy and policy.ArePaidRandomItemsRestricted) == true
end)

-- UI helpers ----------------------------------------------------------------------------------------
local function new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		if key ~= "Parent" then
			(instance :: any)[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if props and props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius: number?)
	return new("UICorner", { CornerRadius = UDim.new(0, radius or 10) })
end

local function stroke(color: Color3?, thickness: number?)
	return new("UIStroke", { Color = color or Color3.new(0, 0, 0), Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

local function label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = THEME.Font,
		TextColor3 = THEME.Text,
		TextScaled = true,
	}
	for k, v in pairs(props) do
		defaults[k] = v
	end
	local l = new("TextLabel", defaults)
	new("UIStroke", { Thickness = 1.5, Parent = l })
	return l
end

local function button(text: string, color: Color3, onClick: () -> ()): TextButton
	local b = new("TextButton", {
		Text = text,
		Font = THEME.Font,
		TextScaled = true,
		TextColor3 = THEME.Text,
		BackgroundColor3 = color,
		AutoButtonColor = true,
	}, { corner(8), stroke(Color3.new(0, 0, 0), 2), new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }) })
	local busy = false
	b.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local ok, err = pcall(onClick)
			if not ok then
				warn(err)
			end
			busy = false
		end)
	end)
	return b
end

-- Root GUI -----------------------------------------------------------------------------------------------
local gui = new("ScreenGui", { Name = "SoulHUD", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = player:WaitForChild("PlayerGui") })

-- Toasts -----------------------------------------------------------------------------------------------------
local toastHolder = new("Frame", {
	Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 110), Size = UDim2.new(0, 340, 0.6, 0), Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }) })

local TOAST_COLORS = { info = THEME.Accent, success = THEME.Good, error = THEME.Bad, warning = THEME.Gold }
local toastCount = 0
local function toast(message: string, kind: string?)
	toastCount += 1
	local frame = new("Frame", {
		BackgroundColor3 = TOAST_COLORS[kind or "info"] or THEME.Accent, Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = toastCount, Parent = toastHolder,
	}, { corner(10), stroke() })
	label({ Text = message, Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), Parent = frame })
	task.delay(4, function()
		TweenService:Create(frame, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		task.wait(0.4)
		frame:Destroy()
	end)
	while #toastHolder:GetChildren() > 7 do
		local oldest, oldestOrder = nil, math.huge
		for _, child in ipairs(toastHolder:GetChildren()) do
			if child:IsA("Frame") and child.LayoutOrder < oldestOrder then
				oldest, oldestOrder = child, child.LayoutOrder
			end
		end
		if oldest then
			oldest:Destroy()
		else
			break
		end
	end
end

-- Banner (server-wide announcements) ------------------------------------------------------------------------
local banner = label({
	Name = "Banner", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120),
	Size = UDim2.new(0.6, 0, 0, 40), Text = "", TextTransparency = 1, Parent = gui,
})
local bannerToken = 0
local function announce(message: string, color: Color3?)
	bannerToken += 1
	local token = bannerToken
	banner.Text = message
	banner.TextColor3 = color or THEME.Gold
	banner.TextTransparency = 0
	task.delay(5, function()
		if token == bannerToken then
			TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
		end
	end)
end

-- Top bar ------------------------------------------------------------------------------------------------------
local topBar = new("Frame", {
	Name = "TopBar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(460, 100), BackgroundColor3 = THEME.Bg, BackgroundTransparency = 0.15, Parent = gui,
}, { corner(14), stroke(THEME.Accent, 2) })
local essenceLabel = label({ Text = "0", TextColor3 = Color3.fromRGB(150, 255, 230), Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 4), Parent = topBar })
local incomeLabel = label({ Text = "+0/s", TextColor3 = THEME.Good, Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 44), Parent = topBar })
local statsLabel = label({ Text = "", TextColor3 = THEME.SubText, Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 70), Parent = topBar })

local phaseLabel = label({
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 112), Size = UDim2.fromOffset(300, 0),
	Text = "", Parent = gui,
})

-- Carry bar -------------------------------------------------------------------------------------------------------
local carryBar = new("Frame", {
	Name = "CarryBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.fromOffset(460, 56), BackgroundColor3 = THEME.Bg, BackgroundTransparency = 0.1, Visible = false, Parent = gui,
}, { corner(12), stroke(THEME.Gold, 2) })
local carryLabel = label({ Text = "", Size = UDim2.new(0.72, -10, 1, -10), Position = UDim2.fromOffset(8, 5), Parent = carryBar })
local dropButton = button("Drop", THEME.Bad, function()
	Remotes.Event("DropOrb"):FireServer()
end)
dropButton.Size = UDim2.new(0.25, 0, 1, -12)
dropButton.Position = UDim2.new(0.74, 0, 0, 6)
dropButton.Parent = carryBar

-- Panels ---------------------------------------------------------------------------------------------------------
local panels: { [string]: Frame } = {}
local openPanelName: string? = nil

local function makePanel(name: string, title: string)
	local frame = new("Frame", {
		Name = name .. "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(0, 560, 0.62, 0), BackgroundColor3 = THEME.Panel, Visible = false, Parent = gui,
	}, { corner(16), stroke(THEME.Accent, 3), new("UISizeConstraint", { MinSize = Vector2.new(300, 250), MaxSize = Vector2.new(560, 620) }) })
	label({ Text = title, Size = UDim2.new(1, -70, 0, 40), Position = UDim2.fromOffset(16, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local close = button("X", THEME.Bad, function()
		frame.Visible = false
		openPanelName = nil
	end)
	close.Size = UDim2.fromOffset(40, 40)
	close.Position = UDim2.new(1, -52, 0, 8)
	close.Parent = frame
	local list = new("ScrollingFrame", {
		Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 56), Size = UDim2.new(1, -24, 1, -68),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, BorderSizePixel = 0, Parent = frame,
	}, { new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	panels[name] = frame
	return frame, list
end

local function togglePanel(name: string)
	for key, panel in pairs(panels) do
		panel.Visible = key == name and openPanelName ~= name
	end
	openPanelName = if openPanelName == name then nil else name
end

local function clearList(list: Instance)
	for _, child in ipairs(list:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

-- A row: title + subtitle on the left, up to 3 buttons on the right. Returns row, titleLabel, subLabel, buttons
local function makeRow(list: Instance, order: number, title: string, subtitle: string, buttons: { { Text: string, Color: Color3, OnClick: () -> () } }?)
	local row = new("Frame", { BackgroundColor3 = THEME.Row, Size = UDim2.new(1, -8, 0, 62), LayoutOrder = order, Parent = list }, { corner(10) })
	local buttonCount = buttons and #buttons or 0
	local textWidth = 1 - 0.2 * buttonCount
	local titleLabel = label({ Text = title, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(textWidth, -14, 0, 30), Position = UDim2.fromOffset(10, 4), Parent = row })
	local subLabel = label({ Text = subtitle, TextColor3 = THEME.SubText, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(textWidth, -14, 0, 22), Position = UDim2.fromOffset(10, 35), Parent = row })
	local created = {}
	for i, spec in ipairs(buttons or {}) do
		local b = button(spec.Text, spec.Color, spec.OnClick)
		b.Size = UDim2.new(0.19, -4, 0, 46)
		b.Position = UDim2.new(textWidth + 0.2 * (i - 1), 0, 0, 8)
		b.Parent = row
		table.insert(created, b)
	end
	return row, titleLabel, subLabel, created
end

local function sectionHeader(list: Instance, order: number, text: string)
	label({ Text = text, TextColor3 = THEME.Gold, Size = UDim2.new(1, -8, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Parent = list })
end

local function request(remoteName: string, ...: any)
	local ok, result = pcall(function(...)
		return Remotes.Function(remoteName):InvokeServer(...)
	end, ...)
	if not ok or type(result) ~= "table" then
		toast("Something went wrong, try again.", "error")
		return nil
	end
	if result.msg and result.msg ~= "" then
		toast(result.msg, result.ok and "success" or "error")
	end
	return result
end

local function promptProduct(key: string)
	local info = MonetizationConfig.Products[key]
	if not info or info.Id == 0 then
		toast("Coming soon!", "info")
		return
	end
	MarketplaceService:PromptProductPurchase(player, info.Id)
end

local function promptPass(key: string)
	local info = MonetizationConfig.GamePasses[key]
	if not info or info.Id == 0 then
		toast("Coming soon!", "info")
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, info.Id)
end

-- Upgrades panel ---------------------------------------------------------------------------------------------------
local _, upgradesList = makePanel("Upgrades", "Upgrades")
local upgradeRows = {}
do
	local _, t1, s1, b1 = makeRow(upgradesList, 1, "Speed", "", {
		{ Text = "+1", Color = THEME.Good, OnClick = function() request("RequestUpgrade", "Speed", 1) end },
		{ Text = "+10", Color = THEME.Good, OnClick = function() request("RequestUpgrade", "Speed", 10) end },
		{ Text = "MAX", Color = THEME.Gold, OnClick = function() request("RequestUpgrade", "Speed", "Max") end },
	})
	upgradeRows.Speed = { Title = t1, Sub = s1, Buttons = b1 }
	local _, t2, s2, b2 = makeRow(upgradesList, 2, "Treadmill", "", {
		{ Text = "Upgrade", Color = THEME.Accent, OnClick = function() request("RequestUpgrade", "Treadmill") end },
	})
	upgradeRows.Treadmill = { Title = t2, Sub = s2, Buttons = b2 }
	local _, t3, s3, b3 = makeRow(upgradesList, 3, "Soul Harness", "", {
		{ Text = "Upgrade", Color = THEME.Accent, OnClick = function() request("RequestUpgrade", "Carry") end },
	})
	upgradeRows.Carry = { Title = t3, Sub = s3, Buttons = b3 }
	local _, t4, s4, b4 = makeRow(upgradesList, 4, "Pedestals", "", {
		{ Text = "Buy", Color = THEME.Accent, OnClick = function() request("RequestUpgrade", "Pedestal") end },
	})
	upgradeRows.Pedestal = { Title = t4, Sub = s4, Buttons = b4 }
	sectionHeader(upgradesList, 5, "Biomes")
	for i, id in ipairs(BiomeConfig.Order) do
		local biome = BiomeConfig.Get(id)
		local _, t, s = makeRow(upgradesList, 5 + i, biome.Name, "", nil)
		upgradeRows["Biome" .. id] = { Title = t, Sub = s, Biome = biome }
	end
end

local function attr(name: string, default: any): any
	local value = player:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

local function refreshUpgrades()
	local essence = attr("Essence", 0)
	local speed = attr("Speed", 16)
	local tier = attr("TreadmillTier", 1)
	local carry = attr("CarryLevel", 0)
	local pedestals = attr("Pedestals", 3)
	local cap = Formulas.TreadmillCap(tier)

	local speedCost = Formulas.SpeedCost(speed)
	upgradeRows.Speed.Title.Text = string.format("Speed %d / %d", speed, cap)
	upgradeRows.Speed.Sub.Text = speed >= cap and "Capped - upgrade Treadmill" or ("Next: " .. Format.Number(speedCost))
	for _, b in ipairs(upgradeRows.Speed.Buttons) do
		b.BackgroundTransparency = (speed < cap and essence >= speedCost) and 0 or 0.5
	end

	local nextTier = EconomyConfig.Treadmill[tier + 1]
	upgradeRows.Treadmill.Title.Text = string.format("Treadmill Tier %d (cap %d)", tier, cap)
	if nextTier then
		local needs = nextTier.RequiresRebirths and attr("Rebirths", 0) < nextTier.RequiresRebirths
		upgradeRows.Treadmill.Sub.Text = needs and ("Needs " .. nextTier.RequiresRebirths .. " rebirth(s)")
			or string.format("Cap %d for %s", nextTier.Cap, Format.Number(nextTier.Cost))
		upgradeRows.Treadmill.Buttons[1].BackgroundTransparency = (not needs and essence >= nextTier.Cost) and 0 or 0.5
	else
		upgradeRows.Treadmill.Sub.Text = "MAXED"
	end

	upgradeRows.Carry.Title.Text = string.format("Soul Harness %d / %d", carry, EconomyConfig.CarryMaxLevel)
	if carry < EconomyConfig.CarryMaxLevel then
		local cost = Formulas.CarryCost(carry)
		upgradeRows.Carry.Sub.Text = string.format("-%s slowdown | Next: %s", Format.Percent(Formulas.CarryReduction(carry)), Format.Number(cost))
		upgradeRows.Carry.Buttons[1].BackgroundTransparency = essence >= cost and 0 or 0.5
	else
		upgradeRows.Carry.Sub.Text = "MAXED (-60% slowdown)"
	end

	upgradeRows.Pedestal.Title.Text = string.format("Pedestals %d / %d", pedestals, EconomyConfig.MaxPedestals)
	if pedestals < EconomyConfig.MaxPedestals then
		local cost = Formulas.PedestalCost(pedestals)
		upgradeRows.Pedestal.Sub.Text = "Next: " .. Format.Number(cost)
		upgradeRows.Pedestal.Buttons[1].BackgroundTransparency = essence >= cost and 0 or 0.5
	else
		upgradeRows.Pedestal.Sub.Text = "MAXED (+5 with pass)"
	end

	for _, id in ipairs(BiomeConfig.Order) do
		local row = upgradeRows["Biome" .. id]
		local unlocked = speed >= row.Biome.SpeedRequired
		row.Sub.Text = string.format("%s | Needs %d Speed | x%s income", unlocked and "UNLOCKED" or "LOCKED", row.Biome.SpeedRequired, Format.Number(row.Biome.IncomeMult))
		row.Sub.TextColor3 = unlocked and THEME.Good or THEME.SubText
	end
end

-- Spirits panel -----------------------------------------------------------------------------------------------------------
local _, spiritsList = makePanel("Spirits", "Spirits")

local function petIncome(pet): number
	return Formulas.PetIncome(pet.Rarity, pet.Biome, pet.Mutation)
end

local function petTitle(pet): string
	local mutation = pet.Mutation ~= "None" and (pet.Mutation .. " ") or ""
	return mutation .. pet.Species
end

local orbCountdownLabels: { { Label: TextLabel, HatchEnd: number, Prefix: string } } = {}

local function refreshSpirits()
	clearList(spiritsList)
	table.clear(orbCountdownLabels)
	if not snapshot then
		return
	end
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	local hasOrb = false
	for _, slot in pairs(snapshot.Slots) do
		if slot.Type == "Orb" then
			hasOrb = true
		end
	end
	if hasOrb then
		makeRow(spiritsList, nextOrder(), "Impatient?", "Hatch souls instantly", {
			{ Text = "Slowest R$" .. MonetizationConfig.Products.InstantHatchOne.Price, Color = THEME.Gold, OnClick = function() promptProduct("InstantHatchOne") end },
			{ Text = "All R$" .. MonetizationConfig.Products.InstantHatchAll.Price, Color = THEME.Gold, OnClick = function() promptProduct("InstantHatchAll") end },
		})
	end

	sectionHeader(spiritsList, nextOrder(), string.format("Pedestals (%d active)", snapshot.ActivePedestals))
	local placed = {}
	for i = 1, snapshot.ActivePedestals do
		local slot = snapshot.Slots[tostring(i)]
		if not slot then
			makeRow(spiritsList, nextOrder(), "#" .. i .. " Empty", "Steal a soul and bring it home!", nil)
		elseif slot.Type == "Orb" then
			local rarity = PetConfig.GetRarity(slot.Rarity)
			local _, title, sub = makeRow(spiritsList, nextOrder(), string.format("#%d %s Soul", i, slot.Rarity), "", nil)
			title.TextColor3 = rarity.Color
			table.insert(orbCountdownLabels, { Label = sub, HatchEnd = slot.HatchEnd, Prefix = BiomeConfig.Get(slot.Biome).Name .. " | Hatching in " })
		elseif slot.Type == "Pet" then
			local pet = snapshot.Pets[slot.PetId]
			if pet then
				placed[slot.PetId] = true
				local index = i
				local _, title = makeRow(spiritsList, nextOrder(), "#" .. i .. " " .. petTitle(pet), string.format("%s | +%s/s", pet.Rarity, Format.Number(petIncome(pet))), {
					{ Text = "Store", Color = THEME.Accent, OnClick = function() request("PetAction", "Store", index) end },
				})
				title.TextColor3 = PetConfig.GetRarity(pet.Rarity).Color
			end
		end
	end

	local inventory = {}
	for id, pet in pairs(snapshot.Pets) do
		if not placed[id] then
			table.insert(inventory, pet)
		end
	end
	table.sort(inventory, function(a, b)
		return petIncome(a) > petIncome(b)
	end)
	local lockedCount = 0
	for _, pet in pairs(snapshot.Pets) do
		if pet.Locked then
			lockedCount += 1
		end
	end
	sectionHeader(spiritsList, nextOrder(), string.format("Inventory (%d) | Vault %d/%d | Pending souls: %d", #inventory, lockedCount, snapshot.VaultSize, snapshot.PendingOrbs))
	for _, pet in ipairs(inventory) do
		local id = pet.Id
		local _, title = makeRow(spiritsList, nextOrder(), petTitle(pet) .. (pet.Locked and " [VAULT]" or ""), string.format("%s | +%s/s", pet.Rarity, Format.Number(petIncome(pet))), {
			{ Text = "Place", Color = THEME.Good, OnClick = function() request("PetAction", "Place", id) end },
			{ Text = pet.Locked and "Unvault" or "Vault", Color = THEME.Accent, OnClick = function() request("PetAction", "Lock", id, not pet.Locked) end },
			{ Text = "Sell", Color = THEME.Bad, OnClick = function() request("PetAction", "Sell", id) end },
		})
		title.TextColor3 = PetConfig.GetRarity(pet.Rarity).Color
	end
	-- Pets on pedestals can also be vaulted
	sectionHeader(spiritsList, nextOrder(), "Vault spirits on pedestals (kept through rebirth)")
	for id in pairs(placed) do
		local pet = snapshot.Pets[id]
		makeRow(spiritsList, nextOrder(), petTitle(pet), pet.Locked and "In vault" or "Not vaulted", {
			{ Text = pet.Locked and "Unvault" or "Vault", Color = THEME.Accent, OnClick = function() request("PetAction", "Lock", id, not pet.Locked) end },
		})
	end
end

-- Rebirth panel -------------------------------------------------------------------------------------------------------------
local _, rebirthList = makePanel("Rebirth", "Rebirth")

local function refreshRebirth()
	clearList(rebirthList)
	if not snapshot then
		return
	end
	local rebirths = snapshot.Rebirths
	local cost = Formulas.RebirthCost(rebirths)
	local essence = attr("Essence", 0)
	makeRow(rebirthList, 1, string.format("Rebirth %d -> %d", rebirths, rebirths + 1), string.format("x%.1f -> x%.1f Essence forever | +%d tokens", Formulas.RebirthMultiplier(rebirths), Formulas.RebirthMultiplier(rebirths + 1), Formulas.RebirthTokens(rebirths + 1)), nil)
	makeRow(rebirthList, 2, string.format("Cost: %s (%s)", Format.Number(cost), Format.Percent(math.min(1, essence / cost))), "Resets Essence, Speed, Harness, Treadmill & unvaulted spirits", {
		{ Text = "REBIRTH", Color = essence >= cost and THEME.Good or THEME.Row, OnClick = function() request("RequestRebirth") end },
		{ Text = "Skip R$" .. MonetizationConfig.Products.RebirthSkip.Price, Color = THEME.Gold, OnClick = function() promptProduct("RebirthSkip") end },
	})
	sectionHeader(rebirthList, 3, string.format("Perks | Rebirth Tokens: %d", snapshot.RebirthTokens))
	for i, perkId in ipairs(EconomyConfig.PerkOrder) do
		local perk = EconomyConfig.Perks[perkId]
		local level = snapshot.Perks[perkId] or 0
		local perkCost = Formulas.PerkCost(perkId, level)
		local id = perkId
		makeRow(rebirthList, 3 + i, string.format("%s %d/%d", perk.Name, level, perk.MaxLevel), perk.Desc, {
			{ Text = perkCost and (perkCost .. " tok") or "MAX", Color = (perkCost and snapshot.RebirthTokens >= perkCost) and THEME.Good or THEME.Row, OnClick = function() request("BuyPerk", id) end },
		})
	end
end

-- Shop panel ----------------------------------------------------------------------------------------------------------------
local _, shopList = makePanel("Shop", "Shop")

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return map[a].Order < map[b].Order
	end)
	return keys
end

local function refreshShop()
	clearList(shopList)
	local order = 0
	sectionHeader(shopList, 0, "Boosts & Items")
	for _, key in ipairs(sortedKeys(MonetizationConfig.Products)) do
		local info = MonetizationConfig.Products[key]
		local show = not info.Hidden and not (paidRandomRestricted and RANDOM_ITEM_PRODUCTS[key])
		if key == "StarterPack" and snapshot and snapshot.StarterPackBought then
			show = false
		end
		if key == "StealBack" and snapshot and snapshot.CanStealBack then
			show = true
		end
		if show then
			order += 1
			local productKey = key
			makeRow(shopList, order, info.Name, info.Desc, {
				{ Text = "R$ " .. info.Price, Color = THEME.Gold, OnClick = function() promptProduct(productKey) end },
			})
		end
	end
	order += 1
	sectionHeader(shopList, order, "Game Passes (permanent)")
	for _, key in ipairs(sortedKeys(MonetizationConfig.GamePasses)) do
		local info = MonetizationConfig.GamePasses[key]
		local ownedPass = snapshot and snapshot.Passes and snapshot.Passes[key]
		order += 1
		local passKey = key
		makeRow(shopList, order, info.Name, info.Desc, {
			{ Text = ownedPass and "OWNED" or ("R$ " .. info.Price), Color = ownedPass and THEME.Row or THEME.Accent, OnClick = function()
				if not ownedPass then
					promptPass(passKey)
				end
			end },
		})
	end
end

-- Codes panel -------------------------------------------------------------------------------------------------------------------
local _, codesList = makePanel("Codes", "Codes")
do
	local box = new("TextBox", {
		PlaceholderText = "Enter code...", Text = "", Font = THEME.Font, TextScaled = true, ClearTextOnFocus = false,
		TextColor3 = Color3.new(0, 0, 0), BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(1, -8, 0, 50), LayoutOrder = 1, Parent = codesList,
	}, { corner(8) })
	local redeem = button("Redeem", THEME.Good, function()
		local result = request("RedeemCode", box.Text)
		if result and result.ok then
			box.Text = ""
		end
	end)
	redeem.Size = UDim2.new(1, -8, 0, 50)
	redeem.LayoutOrder = 2
	redeem.Parent = codesList
	label({ Text = "Follow the group & like the game for new codes!", TextColor3 = THEME.SubText, Size = UDim2.new(1, -8, 0, 30), LayoutOrder = 3, Parent = codesList })
end

-- Side menu ------------------------------------------------------------------------------------------------------------------------
local menu = new("Frame", {
	Name = "Menu", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(120, 380),
	BackgroundTransparency = 1, Parent = gui,
}, { new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

local menuItems = {
	{ "Upgrades", THEME.Good },
	{ "Spirits", THEME.Accent },
	{ "Rebirth", Color3.fromRGB(230, 90, 230) },
	{ "Shop", THEME.Gold },
	{ "Codes", Color3.fromRGB(80, 160, 255) },
}
for i, item in ipairs(menuItems) do
	local name = item[1]
	local b = button(name, item[2], function()
		togglePanel(name)
		if name == "Upgrades" then
			refreshUpgrades()
		elseif name == "Spirits" then
			refreshSpirits()
		elseif name == "Rebirth" then
			refreshRebirth()
		elseif name == "Shop" then
			refreshShop()
		end
	end)
	b.Size = UDim2.new(1, 0, 0, 52)
	b.LayoutOrder = i
	b.Parent = menu
end
local lockButton = button("Lock Base", Color3.fromRGB(60, 140, 200), function()
	request("RequestLock")
end)
lockButton.Size = UDim2.new(1, 0, 0, 52)
lockButton.LayoutOrder = 10
lockButton.Parent = menu

-- Hatch popup ---------------------------------------------------------------------------------------------------------------------------
local hatchFrame = new("Frame", {
	Name = "Hatch", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(420, 170),
	BackgroundColor3 = THEME.Bg, Visible = false, Parent = gui,
}, { corner(18), stroke(THEME.Gold, 3) })
local hatchTitle = label({ Text = "", Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 8), TextColor3 = THEME.SubText, Parent = hatchFrame })
local hatchName = label({ Text = "", Size = UDim2.new(1, -20, 0, 54), Position = UDim2.fromOffset(10, 44), Parent = hatchFrame })
local hatchInfo = label({ Text = "", Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 104), TextColor3 = THEME.Good, Parent = hatchFrame })
local hatchToken = 0

local function showHatch(result)
	hatchToken += 1
	local token = hatchToken
	local rarity = PetConfig.GetRarity(result.Rarity)
	hatchTitle.Text = result.Ascended and "ASCENDED! Your soul hatched into..." or "Your soul hatched into..."
	hatchName.Text = (result.Mutation ~= "None" and (result.Mutation .. " ") or "") .. result.Species
	hatchName.TextColor3 = rarity.Color
	hatchInfo.Text = string.format("%s | +%s Essence/s", result.Rarity, Format.Number(result.Income))
	hatchFrame.Visible = true
	hatchFrame.Size = UDim2.fromOffset(20, 10)
	TweenService:Create(hatchFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(420, 170) }):Play()
	task.delay(3.5, function()
		if token == hatchToken then
			hatchFrame.Visible = false
		end
	end)
end

-- Live updates --------------------------------------------------------------------------------------------------------------------------------
local function refreshTopBar()
	essenceLabel.Text = Format.Number(attr("Essence", 0)) .. " Essence"
	incomeLabel.Text = "+" .. Format.Number(attr("Income", 0)) .. "/s"
	local rebirths = attr("Rebirths", 0)
	statsLabel.Text = string.format("Speed %d  |  Rebirth %d (x%.1f)  |  Luck x%.1f", attr("Speed", 16), rebirths, Formulas.RebirthMultiplier(rebirths), attr("Luck", 1))
end

local function refreshCarry()
	local rarity = player:GetAttribute("CarryingRarity")
	carryBar.Visible = rarity ~= nil
	if rarity then
		local biome = BiomeConfig.Get(player:GetAttribute("CarryingBiome") or "Meadow")
		carryLabel.Text = string.format("%s Soul (%s) - RUN HOME!", rarity, biome.Name)
		carryLabel.TextColor3 = PetConfig.GetRarity(rarity).Color
	end
end

local function refreshPhase()
	if Workspace:GetAttribute("IsEclipse") then
		phaseLabel.Text = "SOUL ECLIPSE - 5x luck!"
		phaseLabel.TextColor3 = Color3.fromRGB(255, 90, 40)
		phaseLabel.Size = UDim2.fromOffset(300, 26)
	elseif Workspace:GetAttribute("IsNight") then
		phaseLabel.Text = "Night - 2x luck, faster guardians"
		phaseLabel.TextColor3 = Color3.fromRGB(150, 160, 255)
		phaseLabel.Size = UDim2.fromOffset(300, 26)
	else
		phaseLabel.Text = ""
		phaseLabel.Size = UDim2.fromOffset(300, 0)
	end
end

local function onSnapshot(newSnapshot)
	if type(newSnapshot) ~= "table" then
		return
	end
	snapshot = newSnapshot
	serverTimeOffset = (newSnapshot.ServerTime or os.time()) - os.time()
	if openPanelName == "Spirits" then
		refreshSpirits()
	elseif openPanelName == "Rebirth" then
		refreshRebirth()
	elseif openPanelName == "Shop" then
		refreshShop()
	end
end

for _, name in ipairs({ "Essence", "Income", "Speed", "Rebirths", "Luck" }) do
	player:GetAttributeChangedSignal(name):Connect(function()
		refreshTopBar()
		if openPanelName == "Upgrades" then
			refreshUpgrades()
		end
	end)
end
for _, name in ipairs({ "TreadmillTier", "CarryLevel", "Pedestals" }) do
	player:GetAttributeChangedSignal(name):Connect(function()
		if openPanelName == "Upgrades" then
			refreshUpgrades()
		end
	end)
end
player:GetAttributeChangedSignal("CarryingRarity"):Connect(refreshCarry)
Workspace:GetAttributeChangedSignal("IsNight"):Connect(refreshPhase)
Workspace:GetAttributeChangedSignal("IsEclipse"):Connect(refreshPhase)

Remotes.Event("Notify").OnClientEvent:Connect(toast)
Remotes.Event("Announce").OnClientEvent:Connect(announce)
Remotes.Event("HatchResult").OnClientEvent:Connect(showHatch)
Remotes.Event("StateChanged").OnClientEvent:Connect(onSnapshot)
Remotes.Event("Knockback").OnClientEvent:Connect(function(velocity: Vector3)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and typeof(velocity) == "Vector3" then
		root.AssemblyLinearVelocity = velocity
	end
end)

-- Hide "Steal" prompts on your OWN pedestals (server rejects them anyway).
local function checkPrompt(prompt: Instance)
	if prompt:IsA("ProximityPrompt") and prompt:GetAttribute("OwnerUserId") == player.UserId then
		prompt.Enabled = false
	end
end
for _, d in ipairs(Workspace:GetDescendants()) do
	checkPrompt(d)
end
Workspace.DescendantAdded:Connect(function(d)
	if d:IsA("ProximityPrompt") then
		task.defer(checkPrompt, d) -- attributes replicate with the instance; defer to be safe
	end
end)

-- Floating / spinning souls and spirits (purely visual, client-side).
local bobbing: { [Model]: CFrame } = {}
CollectionService:GetInstanceAddedSignal("Bob"):Connect(function(model)
	if model:IsA("Model") then
		bobbing[model] = model:GetPivot()
	end
end)
CollectionService:GetInstanceRemovedSignal("Bob"):Connect(function(model)
	bobbing[model] = nil
end)
for _, model in ipairs(CollectionService:GetTagged("Bob")) do
	if model:IsA("Model") then
		bobbing[model] = model:GetPivot()
	end
end

local lastCountdown = 0
RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local camera = Workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position or Vector3.zero
	for model, base in pairs(bobbing) do
		if not model.Parent then
			bobbing[model] = nil
		elseif model.PrimaryPart and model.PrimaryPart.Anchored and (base.Position - camPos).Magnitude < 160 then
			model:PivotTo(base * CFrame.new(0, math.sin(t * 2 + base.Position.X) * 0.4, 0) * CFrame.Angles(0, (t * 0.8) % (math.pi * 2), 0))
		end
	end
	-- Hatch countdowns in the Spirits panel (4x per second)
	if t - lastCountdown > 0.25 then
		lastCountdown = t
		local now = os.time() + serverTimeOffset
		for _, entry in ipairs(orbCountdownLabels) do
			entry.Label.Text = entry.Prefix .. Format.Time(entry.HatchEnd - now)
		end
	end
end)

-- Initial state -------------------------------------------------------------------------------------------------------------------------------
task.spawn(function()
	while not player:GetAttribute("DataLoaded") do
		task.wait(0.2)
	end
	for _ = 1, 10 do
		local ok, result = pcall(function()
			return Remotes.Function("GetState"):InvokeServer()
		end)
		if ok and result then
			onSnapshot(result)
			break
		end
		task.wait(1)
	end
	refreshTopBar()
	refreshCarry()
	refreshPhase()
	toast("Steal glowing souls, run them home, hatch spirits, get rich!", "info")
end)
