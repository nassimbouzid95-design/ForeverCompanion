-- ForeverCompanion: economy. Auction house prices (scan and passive), where your gold comes from
-- and goes, gold history, recipes of every character with their cost and profit, shopping list.
local _, ns = ...
local L = ns.L
local UI = ns.UI
local C = UI.COLORS

local Eco = ns.NewModule("Economy", {
	tooltipPrice = true,
	tooltipCraft = true,
	scanButton = true,
}, {
	prices = {},   -- [realm] = { [itemID] = { p = unit price, t = time, h = { [day] = price } } }
	scans = {},    -- [realm] = time of the last full scan
	recipes = {},  -- [charKey] = { [recipeKey] = { name, prof, out = itemID, n = count, r = { itemID, qty, ... } } }
	shopping = {}, -- list of { char = key, recipe = recipeKey, count = n }
	vendor = {},   -- [itemID] = price at a merchant (reagents sold by vendors)
	ledger = {},   -- [day] = { [category] = { inc = copper, out = copper } }
	window = {},
})

local SCAN_COOLDOWN = 15 * 60
local HISTORY_DAYS = 14

local function Today() return date("%Y-%m-%d") end
local function Realm() return GetNormalizedRealmName() or GetRealmName() or "?" end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------
function Eco:RealmPrices()
	local all = self:Global().prices
	local realm = Realm()
	all[realm] = all[realm] or {}
	return all[realm]
end

-- Record the lowest unit price seen for an item.
function Eco:RecordPrice(itemID, unitPrice, fresh)
	if not itemID or not unitPrice or unitPrice <= 0 or ns.AnySecret(itemID, unitPrice) then return end
	local prices = self:RealmPrices()
	local entry = prices[itemID]
	local now = time()
	if not entry then
		entry = { h = {} }
		prices[itemID] = entry
	end
	-- A full scan replaces the price; passive sightings only lower a price seen in the last hour.
	if fresh or not entry.p or now - (entry.t or 0) > 3600 or unitPrice < entry.p then
		entry.p, entry.t = math.floor(unitPrice), now
	end
	local day = Today()
	entry.h = entry.h or {}
	if not entry.h[day] or unitPrice < entry.h[day] then entry.h[day] = math.floor(unitPrice) end
end

function ns.AuctionPrice(itemID)
	if not (Eco:IsEnabled() and itemID) then return nil end
	local entry = Eco:RealmPrices()[itemID]
	if entry then return entry.p, entry.t end
end

-- Average of the daily lowest prices, a steadier value than the last price.
function Eco:AveragePrice(itemID)
	local entry = self:RealmPrices()[itemID]
	if not entry or not entry.h then return nil end
	local sum, n = 0, 0
	for _, p in pairs(entry.h) do sum, n = sum + p, n + 1 end
	return n > 0 and math.floor(sum / n) or nil
end

local function PruneHistory(prices)
	local limit = date("%Y-%m-%d", time() - HISTORY_DAYS * 86400)
	for _, entry in pairs(prices) do
		for day in pairs(entry.h or {}) do
			if day < limit then entry.h[day] = nil end
		end
	end
end

---------------------------------------------------------------------------
-- Auction house: full scan (ReplicateItems) and prices seen while browsing.
---------------------------------------------------------------------------
local AH = C_AuctionHouse

function Eco:CanScan()
	local last = self:Global().scans[Realm()] or 0
	return AH and AH.ReplicateItems and time() - last >= SCAN_COOLDOWN, SCAN_COOLDOWN - (time() - last)
end

function Eco:StartScan()
	local ok, wait = self:CanScan()
	if not ok then
		if AH and AH.ReplicateItems then
			ns.Print(string.format(L["Full scan possible again in %s."], ns.FormatDuration(wait)))
		else
			ns.Print(L["The full scan is not available on this client. Prices are still recorded while you browse."])
		end
		return
	end
	self.scanning = true
	self:UpdateScanButton()
	ns.Print(L["Auction house scan started..."])
	AH.ReplicateItems()
end

function Eco:REPLICATE_ITEM_LIST_UPDATE()
	if not self.scanning or self.processing then return end
	self.processing = true
	local total = AH.GetNumReplicateItems()
	local index, lowest = 0, {}
	-- Read in chunks so the game does not freeze on a big auction house.
	local function Chunk()
		local last = math.min(total - 1, index + 2000)
		for i = index, last do
			local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID, hasAll = AH.GetReplicateItemInfo(i)
			if hasAll ~= false and itemID and buyout and buyout > 0 and count and count > 0 then
				local unit = buyout / count
				if not lowest[itemID] or unit < lowest[itemID] then lowest[itemID] = unit end
			end
		end
		index = last + 1
		if index < total then
			C_Timer.After(0, Chunk)
		else
			local n = 0
			for itemID, unit in pairs(lowest) do
				self:RecordPrice(itemID, unit, true)
				n = n + 1
			end
			PruneHistory(self:RealmPrices())
			self:Global().scans[Realm()] = time()
			self.scanning, self.processing = false, false
			self:UpdateScanButton()
			ns.Print(string.format(L["Scan finished: %d auctions, %d items priced."], total, n))
			PlaySound(SOUNDKIT.AUCTION_WINDOW_OPEN or 5274)
			if self.frame and self.frame:IsShown() then self:Render() end
		end
	end
	Chunk()
end

function Eco:AUCTION_HOUSE_BROWSE_RESULTS_UPDATED()
	if not (AH and AH.GetBrowseResults) then return end
	for _, result in ipairs(AH.GetBrowseResults() or {}) do
		if result.itemKey and result.minPrice then self:RecordPrice(result.itemKey.itemID, result.minPrice) end
	end
end

function Eco:COMMODITY_SEARCH_RESULTS_UPDATED(_, itemID)
	if not (AH and AH.GetCommoditySearchResultInfo and itemID) then return end
	local info = AH.GetCommoditySearchResultInfo(itemID, 1)
	if info and info.unitPrice then self:RecordPrice(itemID, info.unitPrice) end
end

function Eco:ITEM_SEARCH_RESULTS_UPDATED(_, itemKey)
	if not (AH and AH.GetItemSearchResultInfo and itemKey) then return end
	local info = AH.GetItemSearchResultInfo(itemKey, 1)
	if info and info.buyoutAmount then self:RecordPrice(itemKey.itemID, info.buyoutAmount / math.max(1, info.quantity or 1)) end
end

function Eco:UpdateScanButton()
	local b = self.scanButton
	if not b then return end
	local ok, wait = self:CanScan()
	if self.scanning then
		b:SetText(L["Scanning..."])
	elseif ok then
		b:SetText(L["Scan prices"])
	else
		b:SetText(string.format(L["Scan in %s"], ns.FormatDuration(wait)))
	end
end

function Eco:AUCTION_HOUSE_SHOW()
	self.context = "auction"
	if not self:Settings().scanButton then return end
	local parent = AuctionHouseFrame or AuctionFrame
	if not parent then return end
	if not self.scanButton then
		local b = UI.Button(parent, L["Scan prices"], 150, 24, "accent", function() self:StartScan() end)
		b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -30, -28)
		b:SetFrameStrata("HIGH")
		b.tooltip = L["Reads every auction once (allowed every 15 minutes) and saves the lowest price of each item."]
		self.scanButton = b
	end
	self.scanButton:Show()
	self:UpdateScanButton()
end

---------------------------------------------------------------------------
-- Gold ledger: each change of money is filed under what you were doing.
---------------------------------------------------------------------------
local CATEGORIES = {
	{ key = "loot", label = "Loot" },
	{ key = "quest", label = "Quests" },
	{ key = "vendor", label = "Merchant" },
	{ key = "auction", label = "Auction house" },
	{ key = "mail", label = "Mail" },
	{ key = "repair", label = "Repairs" },
	{ key = "training", label = "Training" },
	{ key = "travel", label = "Travel" },
	{ key = "trade", label = "Trade" },
	{ key = "other", label = "Other" },
}

function Eco:PLAYER_MONEY()
	local money = GetMoney()
	if ns.IsSecret(money) then return end
	local delta = money - (self.money or money)
	self.money = money
	if delta == 0 then return end
	local category = self.context or "other"
	if category == "vendor" and delta < 0 and self.repairing then category = "repair" end
	local day = Today()
	local ledger = self:Global().ledger
	ledger[day] = ledger[day] or {}
	local entry = ledger[day][category] or { inc = 0, out = 0 }
	ledger[day][category] = entry
	if delta > 0 then entry.inc = entry.inc + delta else entry.out = entry.out - delta end
	self.session = self.session or { inc = 0, out = 0, start = GetTime() }
	if delta > 0 then self.session.inc = self.session.inc + delta else self.session.out = self.session.out - delta end
end

-- Totals over the last N days: { [category] = { inc, out } }, income, expenses.
function Eco:LedgerTotals(days)
	local totals, inc, out = {}, 0, 0
	local limit = date("%Y-%m-%d", time() - (days - 1) * 86400)
	for day, cats in pairs(self:Global().ledger) do
		if day >= limit then
			for key, e in pairs(cats) do
				totals[key] = totals[key] or { inc = 0, out = 0 }
				totals[key].inc = totals[key].inc + e.inc
				totals[key].out = totals[key].out + e.out
				inc, out = inc + e.inc, out + e.out
			end
		end
	end
	return totals, inc, out
end

---------------------------------------------------------------------------
-- Recipes: read when a profession window opens (modern API first, older API as a fallback).
---------------------------------------------------------------------------
local function MyRecipes()
	local key = ns.PlayerKey()
	local all = Eco:Global().recipes
	all[key] = all[key] or {}
	return all[key]
end

function Eco:ScanModernTradeSkill()
	local TS = C_TradeSkillUI
	if not (TS and TS.GetAllRecipeIDs and TS.GetRecipeSchematic) then return false end
	local prof
	if TS.GetBaseProfessionInfo then
		local info = TS.GetBaseProfessionInfo()
		prof = info and info.professionName
	end
	local recipes = MyRecipes()
	local n = 0
	for _, recipeID in ipairs(TS.GetAllRecipeIDs() or {}) do
		local info = TS.GetRecipeInfo and TS.GetRecipeInfo(recipeID)
		if info and info.learned then
			local ok, schematic = pcall(TS.GetRecipeSchematic, recipeID, false)
			if ok and schematic and schematic.outputItemID then
				local reagents = {}
				for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
					local reagent = slot.reagents and slot.reagents[1]
					if reagent and reagent.itemID and (slot.reagentType == nil or slot.reagentType == 1) then
						reagents[#reagents + 1] = reagent.itemID
						reagents[#reagents + 1] = slot.quantityRequired or 1
					end
				end
				recipes["r" .. recipeID] = { name = info.name, prof = prof, out = schematic.outputItemID, n = schematic.quantityMin or 1, r = reagents }
				n = n + 1
			end
		end
	end
	return n > 0
end

function Eco:ScanClassicTradeSkill()
	if not (GetNumTradeSkills and GetTradeSkillInfo) then return false end
	local prof = GetTradeSkillLine and GetTradeSkillLine()
	local recipes = MyRecipes()
	for i = 1, GetNumTradeSkills() do
		local name, kind = GetTradeSkillInfo(i)
		if name and kind ~= "header" then
			local out = ns.ItemIDFromLink(GetTradeSkillItemLink(i))
			if out then
				local reagents = {}
				for j = 1, GetTradeSkillNumReagents(i) do
					local _, _, count = GetTradeSkillReagentInfo(i, j)
					local id = ns.ItemIDFromLink(GetTradeSkillReagentItemLink(i, j))
					if id then
						reagents[#reagents + 1] = id
						reagents[#reagents + 1] = count or 1
					end
				end
				local min = GetTradeSkillNumMade and GetTradeSkillNumMade(i) or 1
				recipes["c" .. out] = { name = name, prof = prof, out = out, n = min, r = reagents }
			end
		end
	end
	return true
end

function Eco:ScanTradeSkill()
	if InCombatLockdown() then return end
	if not self:ScanModernTradeSkill() then self:ScanClassicTradeSkill() end
	self.craftIndex = nil
end

-- Cost of the reagents of a recipe at auction prices (nil parts are counted as unknown).
function Eco:RecipeCost(recipe)
	local cost, unknown = 0, 0
	for i = 1, #recipe.r, 2 do
		local price = ns.AuctionPrice(recipe.r[i]) or self:VendorBuyPrice(recipe.r[i])
		if price then cost = cost + price * recipe.r[i + 1] else unknown = unknown + 1 end
	end
	return cost, unknown
end

-- Reagents sold by vendors (thread, vials, flux...) never reach the auction house: their price is
-- read from every merchant you visit.
function Eco:VendorBuyPrice(itemID)
	local realm = self:Global().vendor
	return realm and realm[itemID]
end

function Eco:RecordMerchant()
	if not (GetMerchantNumItems and GetMerchantItemID) then return end
	local vendor = self:Global().vendor
	for i = 1, GetMerchantNumItems() do
		local itemID = GetMerchantItemID(i)
		local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
		local price, quantity
		if info then
			price, quantity = info.price, info.stackCount
		elseif GetMerchantItemInfo then
			local _, _, p, q = GetMerchantItemInfo(i)
			price, quantity = p, q
		end
		if itemID and price and price > 0 and not ns.AnySecret(itemID, price) then
			vendor[itemID] = math.floor(price / math.max(1, quantity or 1))
		end
	end
end

-- Which known recipe makes this item (for the tooltip).
function Eco:RecipeFor(itemID)
	if not self.craftIndex then
		self.craftIndex = {}
		for charKey, recipes in pairs(self:Global().recipes) do
			for key, recipe in pairs(recipes) do
				self.craftIndex[recipe.out] = self.craftIndex[recipe.out] or { recipe = recipe, char = charKey, key = key }
			end
		end
	end
	return self.craftIndex[itemID]
end

---------------------------------------------------------------------------
-- Shopping list
---------------------------------------------------------------------------
local function CountOwned(itemID)
	local total = C_Item.GetItemCount and C_Item.GetItemCount(itemID, true) or 0
	if ns.ItemOwners then
		local me = UnitName("player")
		for _, o in ipairs(ns.ItemOwners(itemID)) do
			if o.name ~= me then total = total + o.bags + o.bank + o.mail end
		end
	end
	return total
end

function Eco:AddToShopping(charKey, recipeKey, count)
	for _, entry in ipairs(self:Global().shopping) do
		if entry.char == charKey and entry.recipe == recipeKey then
			entry.count = entry.count + (count or 1)
			return
		end
	end
	table.insert(self:Global().shopping, { char = charKey, recipe = recipeKey, count = count or 1 })
end

-- Reagents needed by the whole list: { { itemID, need, have, price } }, total cost of what is missing.
function Eco:ShoppingNeeds()
	local need = {}
	for _, entry in ipairs(self:Global().shopping) do
		local recipe = self:Global().recipes[entry.char] and self:Global().recipes[entry.char][entry.recipe]
		if recipe then
			for i = 1, #recipe.r, 2 do
				need[recipe.r[i]] = (need[recipe.r[i]] or 0) + recipe.r[i + 1] * entry.count
			end
		end
	end
	local list, cost = {}, 0
	for itemID, n in pairs(need) do
		local have = CountOwned(itemID)
		local price = ns.AuctionPrice(itemID) or self:VendorBuyPrice(itemID)
		if price and have < n then cost = cost + price * (n - have) end
		list[#list + 1] = { itemID = itemID, need = n, have = have, price = price }
	end
	table.sort(list, function(a, b) return (a.need - a.have) > (b.need - b.have) end)
	return list, cost
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function Age(t)
	local s = time() - (t or 0)
	if s < 3600 then return string.format(L["%d min ago"], math.max(1, math.floor(s / 60))) end
	if s < 86400 then return string.format(L["%d h ago"], math.floor(s / 3600)) end
	return string.format(L["%d days ago"], math.floor(s / 86400))
end

function Eco:OnTooltip(tooltip, data)
	if not self:IsEnabled() or tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local itemID = data and data.id
	if not itemID or ns.IsSecret(itemID) then return end
	local s = self:Settings()
	if s.tooltipPrice then
		local price, t = ns.AuctionPrice(itemID)
		if price then
			tooltip:AddDoubleLine(UI.Colorize(L["Auction house"], C.accent), ns.FormatMoney(price) .. UI.Colorize("  " .. Age(t), C.muted), 1, 1, 1, 1, 1, 1)
			local avg = self:AveragePrice(itemID)
			if avg and math.abs(avg - price) > price * 0.1 then
				tooltip:AddDoubleLine(UI.Colorize(L["14-day average"], C.muted), ns.FormatMoney(avg), 1, 1, 1, 1, 1, 1)
			end
		end
	end
	if s.tooltipCraft then
		local craft = self:RecipeFor(itemID)
		if craft then
			local cost, unknown = self:RecipeCost(craft.recipe)
			local unit = cost / math.max(1, craft.recipe.n or 1)
			local line = ns.FormatMoney(math.floor(unit)) .. (unknown > 0 and UI.Colorize(" +?", C.muted) or "")
			tooltip:AddDoubleLine(UI.Colorize(L["Crafting cost"], C.accent), line, 1, 1, 1, 1, 1, 1)
			local price = ns.AuctionPrice(itemID)
			if price and unknown == 0 then
				local profit = price - unit
				tooltip:AddDoubleLine(UI.Colorize(L["Profit"], C.muted), UI.Colorize((profit < 0 and "-" or "") .. ns.FormatMoney(math.abs(math.floor(profit))), profit >= 0 and C.good or C.bad), 1, 1, 1, 1, 1, 1)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local TABS = {
	{ key = "gold", label = "Gold" },
	{ key = "prices", label = "Auction house" },
	{ key = "crafts", label = "Professions" },
	{ key = "shopping", label = "Shopping list" },
}

local rows = UI.Pool(function(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(42)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = UI.Fill(row, C.panel, "BACKGROUND")
	row.bg:SetAllPoints()
	row.icon = UI.ItemIcon(row, 32)
	row.icon:SetPoint("LEFT", 6, 0)
	row.name = UI.Text(row, 14)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
	row.name:SetPoint("RIGHT", row, "RIGHT", -230, 0)
	row.name:SetWordWrap(false)
	row.info = UI.Text(row, 12, C.muted)
	row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
	row.info:SetPoint("RIGHT", row, "RIGHT", -230, 0)
	row.info:SetWordWrap(false)
	row.value = UI.Text(row, 14, C.text, "RIGHT")
	row.value:SetPoint("TOPRIGHT", -12, -6)
	row.sub = UI.Text(row, 12, C.muted, "RIGHT")
	row.sub:SetPoint("BOTTOMRIGHT", -12, 6)
	row.action = UI.Button(row, "+", 26, 22, "accent")
	row.action:SetPoint("RIGHT", -170, 0)
	row:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(C.hover[1], C.hover[2], C.hover[3], 1)
		if self.itemID then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(self.itemID)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetVertexColor(C.panel[1], C.panel[2], C.panel[3], 1)
		GameTooltip_Hide()
	end)
	function row:Set(itemID, name, info, value, sub)
		self.itemID = itemID
		local itemName, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
		if not icon and C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(itemID)) end
		self.icon:SetItem(icon, quality)
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
		name = name or itemName or (L["Item"] .. " #" .. itemID)
		self.name:SetText(color and color.hex and (color.hex .. name .. "|r") or name)
		self.info:SetText(info or "")
		self.value:SetText(value or "")
		self.sub:SetText(sub or "")
		self.action:Hide()
		self:SetScript("OnClick", nil)
		if not itemName and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
	end
	return row
end)

local texts = UI.Pool(function(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.text = UI.Text(f, 13)
	f.text:SetPoint("TOPLEFT")
	f.text:SetPoint("TOPRIGHT")
	f.right = UI.Text(f, 13, C.text, "RIGHT")
	f.right:SetPoint("TOPRIGHT")
	return f
end)
local sections = UI.Pool(function(parent) return UI.SectionTitle(parent, "") end)
local bars = UI.Pool(function(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.fill = UI.Fill(f, C.accent, "ARTWORK")
	f.fill:SetPoint("BOTTOMLEFT")
	f.fill:SetPoint("BOTTOMRIGHT")
	f:EnableMouse(true)
	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(self.label or "")
		GameTooltip:AddLine(self.value or "", 1, 1, 1)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	return f
end)

function Eco:CreateWindow()
	if self.frame then return end
	local f = UI.Window("ForeverCompanionEconomy", L["Economy"], 900, 640, self:Global().window,
		{ resizable = true, minWidth = 720, minHeight = 460 })
	self.frame = f
	f.OnResized = function() self:Render() end

	local tabs = CreateFrame("Frame", nil, f.content)
	tabs:SetPoint("TOPLEFT", 16, -12)
	tabs:SetPoint("TOPRIGHT", -16, -12)
	tabs:SetHeight(30)
	f.tabs = {}
	local prev
	for _, tab in ipairs(TABS) do
		local b = UI.Button(tabs, L[tab.label], 150, 30, "normal", function() self.tab = tab.key self:Render() end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT") end
		b:FitText(120)
		f.tabs[tab.key] = b
		prev = b
	end
	f.search = UI.EditBox(tabs, 220, 28, L["Search"])
	f.search:SetPoint("RIGHT")
	f.search:HookScript("OnTextChanged", function(box)
		self.filter = box:GetText():lower()
		if self.filter == "" then self.filter = nil end
		if self.tab == "prices" or self.tab == "crafts" then self:Render() end
	end)

	local scroll = UI.Scroll(f.content)
	scroll:SetPoint("TOPLEFT", 0, -52)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	f.scroll = scroll
	self.stack = UI.Stack(scroll.child, 16)
end

function Eco:Clear()
	rows:ReleaseAll()
	texts:ReleaseAll()
	sections:ReleaseAll()
	bars:ReleaseAll()
	self.stack:Reset()
	self.stack:Space(10)
end

function Eco:Section(text)
	local s = sections:Acquire(self.frame.scroll.child)
	s:SetText(text)
	self.stack:Add(s, 28, 14)
	self.stack:Space(8)
end

function Eco:Line(left, right, size, color)
	local f = texts:Acquire(self.frame.scroll.child)
	f.text:SetFontObject(UI.Font(size or 13))
	f.right:SetFontObject(UI.Font(size or 13))
	local c = color or C.text
	f.text:SetTextColor(c[1], c[2], c[3])
	f.text:SetText(left or "")
	f.right:SetText(right or "")
	self.stack:Add(f, math.max(18, f.text:GetStringHeight() + 4), 2)
	return f
end

function Eco:Row(itemID, name, info, value, sub)
	local row = rows:Acquire(self.frame.scroll.child)
	self.stack:Add(row, 42, 4)
	row:Set(itemID, name, info, value, sub)
	return row
end

local function Signed(copper)
	if copper >= 0 then return UI.Colorize("+", C.good) .. ns.FormatMoney(copper) end
	return UI.Colorize("-", C.bad) .. ns.FormatMoney(-copper)
end

function Eco:PageGold()
	local history = ns.FC.db.global.Alts and ns.FC.db.global.Alts.goldHistory or {}
	local days = {}
	for i = 29, 0, -1 do days[#days + 1] = date("%Y-%m-%d", time() - i * 86400) end
	local total = 0
	for _, c in pairs(ns.FC.db.global.Alts and ns.FC.db.global.Alts.chars or {}) do total = total + (c.money or 0) end

	local _, inc1, out1 = self:LedgerTotals(1)
	local totals7, inc7, out7 = self:LedgerTotals(7)
	local session = self.session
	local perHour = session and (GetTime() - session.start) > 60 and (session.inc - session.out) / (GetTime() - session.start) * 3600 or 0

	self:Section(L["Account"])
	self:Line(L["Gold on all characters"], ns.FormatMoney(total), 15)
	self:Line(L["Today"], Signed(inc1 - out1), 13)
	self:Line(L["Last 7 days"], Signed(inc7 - out7), 13)
	self:Line(L["This session, per hour"], Signed(math.floor(perHour)), 13)

	-- Bar chart: account gold over 30 days.
	self:Section(L["Gold over the last 30 days"])
	local child = self.frame.scroll.child
	local width = child:GetWidth() - 32
	local height = 140
	local maxValue = 1
	local last
	for _, day in ipairs(days) do
		local v = history[day] or last
		if v then maxValue = math.max(maxValue, v) last = v end
	end
	last = nil
	local barW = math.max(4, width / #days - 3)
	local top = self.stack.y
	for i, day in ipairs(days) do
		local v = history[day] or last
		last = v
		local bar = bars:Acquire(child)
		bar:SetSize(barW, height)
		bar:SetPoint("TOPLEFT", child, "TOPLEFT", 16 + (i - 1) * (barW + 3), -top)
		local h = v and math.max(2, v / maxValue * height) or 0
		bar.fill:SetHeight(math.max(0.1, h))
		bar.fill:SetShown(h > 0)
		bar.fill:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], i == #days and 1 or 0.55)
		bar.label = day
		bar.value = v and ns.FormatMoney(v) or L["no data"]
	end
	self.stack.y = top + height + 4
	self:Line(UI.Colorize(days[1], C.muted), UI.Colorize(days[#days], C.muted), 11)

	self:Section(L["Where your gold came from and went (7 days)"])
	local maxCat = 1
	for _, e in pairs(totals7) do maxCat = math.max(maxCat, e.inc, e.out) end
	local any = false
	for _, cat in ipairs(CATEGORIES) do
		local e = totals7[cat.key]
		if e and (e.inc > 0 or e.out > 0) then
			any = true
			self:Line(L[cat.label], (e.inc > 0 and UI.Colorize("+", C.good) .. ns.FormatMoney(e.inc) or "") ..
				(e.out > 0 and "   " .. UI.Colorize("-", C.bad) .. ns.FormatMoney(e.out) or ""), 13)
		end
	end
	if not any then self:Line(L["Nothing recorded yet: gold you earn and spend is filed here from now on."], nil, 12, C.muted) end
	self.frame.subtitle:SetText(ns.FormatMoney(total))
end

function Eco:PagePrices()
	local prices = self:RealmPrices()
	local list = {}
	local filter = self.filter
	for itemID, entry in pairs(prices) do
		local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
		if not filter or (name and name:lower():find(filter, 1, true)) then
			list[#list + 1] = { itemID = itemID, entry = entry, name = name or "" }
		end
	end
	table.sort(list, function(a, b)
		if filter then return a.name < b.name end
		return (a.entry.t or 0) > (b.entry.t or 0)
	end)
	local last = self:Global().scans[Realm()]
	self:Section(string.format(L["%d prices on %s"], #list, Realm()))
	self:Line(last and string.format(L["Last full scan: %s"], Age(last)) or L["No full scan yet: open the auction house and click Scan prices."], nil, 12, C.muted)
	for i = 1, math.min(200, #list) do
		local e = list[i]
		local avg = self:AveragePrice(e.itemID)
		self:Row(e.itemID, nil, Age(e.entry.t), ns.FormatMoney(e.entry.p), avg and (L["avg."] .. " " .. ns.FormatMoney(avg)) or "")
	end
	if #list > 200 then self:Line(string.format(L["%d more: use the search box."], #list - 200), nil, 12, C.muted) end
	self.frame.subtitle:SetText(string.format(L["%d prices"], #list))
end

function Eco:PageCrafts()
	local filter = self.filter
	local groups = {}
	for charKey, recipes in pairs(self:Global().recipes) do
		for key, recipe in pairs(recipes) do
			local name = recipe.name or ""
			if not filter or name:lower():find(filter, 1, true) then
				local g = (recipe.prof or "?") .. "|" .. charKey
				groups[g] = groups[g] or { prof = recipe.prof or "?", char = charKey, list = {} }
				local cost, unknown = self:RecipeCost(recipe)
				local price = ns.AuctionPrice(recipe.out)
				local profit = price and unknown == 0 and price * (recipe.n or 1) - cost or nil
				table.insert(groups[g].list, { key = key, recipe = recipe, cost = cost, unknown = unknown, profit = profit })
			end
		end
	end
	local ordered = {}
	for _, g in pairs(groups) do ordered[#ordered + 1] = g end
	table.sort(ordered, function(a, b) return a.prof .. a.char < b.prof .. b.char end)
	if #ordered == 0 then
		self:Section(L["Professions"])
		self:Line(L["Open each profession window once on each character: its recipes are saved here with their cost and profit."], nil, 13, C.muted)
	end
	for _, g in ipairs(ordered) do
		self:Section(g.prof .. "  ·  " .. (g.char:match("^[^-]+") or g.char))
		table.sort(g.list, function(a, b) return (a.profit or -1e12) > (b.profit or -1e12) end)
		for i = 1, math.min(80, #g.list) do
			local e = g.list[i]
			local cost = ns.FormatMoney(math.floor(e.cost)) .. (e.unknown > 0 and UI.Colorize(" +?", C.muted) or "")
			local profit = e.profit and (e.profit >= 0 and UI.Colorize(L["Profit"] .. " ", C.muted) .. Signed(math.floor(e.profit)) or UI.Colorize(L["Loss"] .. " ", C.muted) .. Signed(math.floor(e.profit))) or UI.Colorize(L["no price"], C.muted)
			local row = self:Row(e.recipe.out, e.recipe.name, L["Cost:"] .. " " .. cost, profit, "")
			row.action:Show()
			row.action.tooltip = L["Add to the shopping list"]
			row.action:SetScript("OnClick", function()
				self:AddToShopping(g.char, e.key, 1)
				ns.Print(string.format(L["Added to the shopping list: %s"], e.recipe.name or "?"))
			end)
		end
	end
end

function Eco:PageShopping()
	local shopping = self:Global().shopping
	self:Section(L["Recipes to craft"])
	if #shopping == 0 then
		self:Line(L["Empty. Add recipes from the Professions tab with the + button."], nil, 13, C.muted)
	end
	for index, entry in ipairs(shopping) do
		local recipe = self:Global().recipes[entry.char] and self:Global().recipes[entry.char][entry.recipe]
		if recipe then
			local row = self:Row(recipe.out, recipe.name, (entry.char:match("^[^-]+") or entry.char), "x" .. entry.count, "")
			row.action:Show()
			row.action:SetText("-")
			row.action.tooltip = L["Left-click: one less  |  Right-click: remove"]
			row.action:RegisterForClicks("LeftButtonUp", "RightButtonUp")
			row.action:SetScript("OnClick", function(_, button)
				if button == "RightButton" or entry.count <= 1 then
					table.remove(shopping, index)
				else
					entry.count = entry.count - 1
				end
				self:Render()
			end)
			row:SetScript("OnClick", function()
				entry.count = entry.count + 1
				self:Render()
			end)
		end
	end
	local needs, cost = self:ShoppingNeeds()
	if #needs > 0 then
		self:Section(L["Reagents"])
		for _, n in ipairs(needs) do
			local missing = math.max(0, n.need - n.have)
			local status = missing == 0 and UI.Colorize(L["OK"], C.good) or UI.Colorize(string.format(L["%d missing"], missing), C.bad)
			self:Row(n.itemID, nil, string.format(L["Need %d, have %d (all characters)"], n.need, n.have), status,
				missing > 0 and n.price and ns.FormatMoney(n.price * missing) or "")
		end
		self:Line(L["Cost of what is missing"], ns.FormatMoney(math.floor(cost)), 15, C.gold)
	end
end

function Eco:Render()
	if not self.frame then return end
	self.tab = self.tab or "gold"
	for key, b in pairs(self.frame.tabs) do
		local active = key == self.tab
		b:SetBackdropBorderColor(active and C.accent[1] or C.border[1], active and C.accent[2] or C.border[2], active and C.accent[3] or C.border[3], 1)
		b.label:SetTextColor(active and 1 or C.muted[1], active and 1 or C.muted[2], active and 1 or C.muted[3])
	end
	self.frame.search:SetShown(self.tab == "prices" or self.tab == "crafts")
	self:Clear()
	self.frame.subtitle:SetText("")
	if self.tab == "prices" then self:PagePrices()
	elseif self.tab == "crafts" then self:PageCrafts()
	elseif self.tab == "shopping" then self:PageShopping()
	else self:PageGold() end
	self.frame.scroll:SetContentHeight(self.stack.y + 20)
end

function Eco:Toggle(tab)
	self:CreateWindow()
	if self.frame:IsShown() and not tab then self.frame:Hide() return end
	if tab then self.tab = tab end
	self.frame:Show()
	self.frame.scroll:ScrollToTop()
	self:Render()
end

function ns.ToggleEconomy(tab)
	if Eco:IsEnabled() then Eco:Toggle(tab) else ns.OpenOptions() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Eco:OnEnable()
	self.money = GetMoney()
	self.session = { inc = 0, out = 0, start = GetTime() }
	self:RegisterEvent("PLAYER_MONEY")
	self:RegisterEvent("AUCTION_HOUSE_SHOW")
	self:RegisterEvent("AUCTION_HOUSE_CLOSED", function() self.context = nil end)
	self:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
	self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
	self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
	self:RegisterEvent("MERCHANT_SHOW", function()
		self.context = "vendor"
		C_Timer.After(0.5, function() self:RecordMerchant() end)
	end)
	self:RegisterEvent("MERCHANT_CLOSED", function() self.context = nil end)
	self:RegisterEvent("MAIL_SHOW", function() self.context = "mail" end)
	self:RegisterEvent("MAIL_CLOSED", function() self.context = nil end)
	self:RegisterEvent("TRAINER_SHOW", function() self.context = "training" end)
	self:RegisterEvent("TRAINER_CLOSED", function() self.context = nil end)
	self:RegisterEvent("TAXIMAP_OPENED", function() self.context = "travel" end)
	self:RegisterEvent("TAXIMAP_CLOSED", function() C_Timer.After(1, function() if self.context == "travel" then self.context = nil end end) end)
	self:RegisterEvent("TRADE_SHOW", function() self.context = "trade" end)
	self:RegisterEvent("TRADE_CLOSED", function() C_Timer.After(1, function() if self.context == "trade" then self.context = nil end end) end)
	self:RegisterEvent("LOOT_OPENED", function() self.context = "loot" end)
	self:RegisterEvent("LOOT_CLOSED", function() C_Timer.After(0.5, function() if self.context == "loot" then self.context = nil end end) end)
	self:RegisterEvent("QUEST_COMPLETE", function() self.context = "quest" end)
	self:RegisterEvent("QUEST_FINISHED", function() C_Timer.After(1, function() if self.context == "quest" then self.context = nil end end) end)
	self:RegisterEvent("TRADE_SKILL_SHOW", function() C_Timer.After(1, function() self:ScanTradeSkill() end) end)
	self:RegisterEvent("TRADE_SKILL_LIST_UPDATE", function()
		if self.tsPending then return end
		self.tsPending = true
		C_Timer.After(2, function() self.tsPending = false self:ScanTradeSkill() end)
	end)
	-- Repairs: tell them apart from other merchant spending.
	if RepairAllItems and not self.repairHooked then
		self.repairHooked = true
		hooksecurefunc("RepairAllItems", function()
			self.repairing = true
			C_Timer.After(1, function() self.repairing = false end)
		end)
	end
	if TooltipDataProcessor and not self.tooltipHooked then
		self.tooltipHooked = true
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data) self:OnTooltip(tooltip, data) end)
	end
end

function Eco:OnDisable()
	if self.frame then self.frame:Hide() end
	if self.scanButton then self.scanButton:Hide() end
end

ns.RegisterCommand("eco", L["economy window: gold, auction prices, professions, shopping list (scan to scan the auction house)"], function(rest)
	rest = (rest or ""):lower()
	if rest == "scan" then Eco:StartScan()
	elseif rest == "prices" or rest == "hv" then ns.ToggleEconomy("prices")
	elseif rest == "crafts" or rest == "metiers" then ns.ToggleEconomy("crafts")
	elseif rest == "shopping" or rest == "courses" then ns.ToggleEconomy("shopping")
	else ns.ToggleEconomy() end
end)

function Eco:GetOptions()
	local get, set = ns.ProfileAccessors("Economy")
	return {
		get = get, set = set,
		args = {
			open = { type = "execute", order = 1, name = L["Open the economy window"], func = function() self:Toggle() end },
			tooltipPrice = { type = "toggle", order = 2, width = "full", name = L["Auction price in item tooltips"] },
			tooltipCraft = { type = "toggle", order = 3, width = "full", name = L["Crafting cost and profit in item tooltips"] },
			scanButton = { type = "toggle", order = 4, width = "full", name = L["Scan button on the auction house"] },
			reset = {
				type = "execute", order = 10, name = L["Forget the prices of this realm"], confirm = true,
				func = function() Eco:Global().prices[Realm()] = nil end,
			},
		},
	}
end
