-- ForeverCompanion: dungeon & raid guide.
-- Instances, bosses, health, loot and rates come from the built-in database (Data\InstanceDB.lua);
-- rates measured by the drop collector are shown next to them, and instances only the collector
-- knows (new Forever content) are listed too.
local _, ns = ...
local L = ns.L
local UI = ns.UI
local C = UI.COLORS

local Guide = ns.NewModule("DungeonGuide", {
	minTrashQuality = 2, -- uncommon and better
	wishlistAlert = true,
	showModels = true,
	allQuests = false, -- also list the quests of the other faction, races and classes
}, {
	wishlist = {}, -- [itemID] = true
	window = {},   -- position and size
	collapsed = {}, -- [category] = true
})

local SIDEBAR_WIDTH = 290

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
-- Loot of the new WoW Forever dungeons can list an item by name when its ID was not published
-- (details in ns.ForeverItems).  Returns the itemID once known (or once the game has seen the item).
function ns.ResolveItem(key)
	local info = ns.ForeverItems and ns.ForeverItems[key]
	if type(key) == "number" then return key, info end
	if info and info.id then return info.id, info end
	local _, link = C_Item.GetItemInfo(key)
	local id = link and not ns.IsSecret(link) and tonumber(link:match("item:(%d+)"))
	return id, info
end

local function EntryName(entry)
	if entry.kind == "world" then return L["World bosses"] end
	return entry.name or ns.InstanceName(entry.id)
end
ns.InstanceEntryName = EntryName

function Guide:BuildList()
	local list, order, known = {}, {}, {}
	for index, entry in ipairs(ns.InstanceDB or {}) do
		local key = "k" .. index
		list[key] = entry
		order[#order + 1] = key
		if entry.id then known[entry.id] = true end
	end
	for id, data in pairs(ns.CollectedInstances and ns.CollectedInstances() or {}) do
		-- a new Forever dungeon of the database gets its instance ID the first time someone goes in
		if not known[id] and data.name then
			for _, entry in ipairs(ns.InstanceDB or {}) do
				if not entry.id and entry.name and entry.name:lower() == data.name:lower() then
					entry.id = id
					known[id] = true
					break
				end
			end
		end
		if not known[id] then
			local entry = { id = id, name = data.name or ns.InstanceName(id), kind = data.kind == "raid" and "raid" or "dungeon", size = data.size, collected = true }
			for _, raid in ipairs(ns.ForeverRaids) do
				if raid.name == entry.name then entry.min, entry.max, entry.size, entry.isNew = raid.min, raid.max, raid.size, true end
			end
			local key = "c" .. id
			list[key] = entry
			order[#order + 1] = key
		end
	end
	table.sort(order, function(a, b)
		local ea, eb = list[a], list[b]
		if (ea.min or 99) ~= (eb.min or 99) then return (ea.min or 99) < (eb.min or 99) end
		return a < b
	end)
	self.list, self.order = list, order
	return list
end

function Guide:Bosses(entry)
	if not entry.collected then return entry.bosses or {} end
	local bosses = {}
	local data = ns.CollectedInstances()[entry.id]
	if data then
		for encounterID, enc in pairs(data.encounters) do
			bosses[#bosses + 1] = { name = enc.name or ("#" .. encounterID), npc = enc.npc, kills = enc.kills }
		end
		table.sort(bosses, function(a, b) return a.name < b.name end)
	end
	return bosses
end

-- Loot list of a creature: database rates + measured rates + items only the collector saw.
function Guide:LootList(entry, mob)
	local list, seen = {}, {}
	local loot = mob.loot or {}
	for i = 1, #loot, 2 do
		local itemID, rate = loot[i], loot[i + 1]
		if not seen[itemID] then
			seen[itemID] = true
			local measured, kills
			if entry.id and mob.npc then measured, kills = ns.DropRate(entry.id, mob.npc, itemID) end
			list[#list + 1] = { itemID = itemID, rate = rate >= 0 and rate or nil, measured = kills and kills > 0 and measured or nil, kills = kills }
		end
	end
	local data = entry.id and mob.npc and ns.CollectedInstances()[entry.id]
	local npc = data and data.npcs[mob.npc]
	if npc then
		for itemID in pairs(npc.items) do
			if not seen[itemID] then
				local measured, kills = ns.DropRate(entry.id, mob.npc, itemID)
				list[#list + 1] = { itemID = itemID, measured = measured, kills = kills }
			end
		end
	end
	table.sort(list, function(a, b) return (a.rate or a.measured or 0) > (b.rate or b.measured or 0) end)
	return list
end

function Guide:TrashMobs(entry)
	local mobs = {}
	for _, mob in ipairs(entry.trash or {}) do mobs[#mobs + 1] = mob end
	local data = entry.id and ns.CollectedInstances()[entry.id]
	if data then
		local known = {}
		for _, mob in ipairs(mobs) do if mob.npc then known[mob.npc] = true end end
		for _, boss in ipairs(entry.bosses or {}) do if boss.npc then known[boss.npc] = true end end
		for npcID, npc in pairs(data.npcs) do
			if not npc.boss and not known[npcID] and next(npc.items) then
				mobs[#mobs + 1] = { name = npc.name or ("#" .. npcID), npc = npcID }
			end
		end
	end
	return mobs
end

---------------------------------------------------------------------------
-- Dungeon quests (Data\DungeonQuests.lua)
---------------------------------------------------------------------------
local function HasBit(mask, bitValue)
	return mask % (bitValue + bitValue) >= bitValue
end

-- Quests of an instance this character can do (every quest when all is true).
function Guide:Quests(entry, all)
	local ids = entry.key and ns.DungeonQuests and ns.DungeonQuests[entry.key]
	if not ids then return {} end
	local faction = UnitFactionGroup("player")
	local side = faction == "Alliance" and 1 or faction == "Horde" and 2 or 0
	local _, _, raceID = UnitRace("player")
	local _, _, classID = UnitClass("player")
	local raceBit = raceID and raceID >= 1 and raceID <= 8 and 2 ^ (raceID - 1) or nil
	local classBit = classID and 2 ^ (classID - 1)
	local out = {}
	for _, id in ipairs(ids) do
		local q = ns.DungeonQuestInfo[id]
		if q and (all or ((q[4] == 0 or side == 0 or q[4] == side)
			and (q[5] == 0 or not raceBit or HasBit(q[5], raceBit))
			and (q[6] == 0 or not classBit or HasBit(q[6], classBit)))) then
			out[#out + 1] = id
		end
	end
	return out
end

local function QuestTitle(id)
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if type(title) == "string" and title ~= "" and not ns.IsSecret(title) then return title end
	local q = ns.DungeonQuestInfo[id]
	return q and q[1] or (ns.DungeonQuestPrev and ns.DungeonQuestPrev[id]) or ("#" .. id)
end

local function QuestDone(id)
	return C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id) or false
end

local function QuestInLog(id)
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
	return index ~= nil and index ~= 0
end

local function Place(continent, x, y)
	return ns.WorldPlace(continent, x, y)
end

-- One line for a quest giver or turn-in: { name, continent, x, y, inside, itemID }.
local function NpcLine(npc)
	if not npc then return UI.Colorize("?", C.muted) end
	if npc[6] then return string.format(L["Starts from an item: %s"], UI.Colorize(npc[1], C.gold)) end
	if npc[5] == 1 then return UI.Colorize(npc[1], C.gold) .. "  ·  " .. L["inside the instance"] end
	-- new Forever quests: position given on a zone map { uiMapID, x, y }, or no position at all
	if npc[8] then return UI.Colorize(npc[1], C.gold) .. "  ·  " .. ns.MapName(npc[8][1]) .. string.format(" (%.1f, %.1f)", npc[8][2] * 100, npc[8][3] * 100) end
	if not npc[2] then return UI.Colorize(npc[1], C.gold) end
	return UI.Colorize(npc[1], C.gold) .. "  ·  " .. Place(npc[2], npc[3], npc[4])
end

local function ItemCount(entry)
	local n = 0
	for _, boss in ipairs(entry.bosses or {}) do n = n + (boss.loot and #boss.loot / 2 or 0) end
	return n
end

local function Percent(rate)
	local c = rate >= 20 and C.good or rate >= 5 and C.warn or rate >= 1 and { 1, 0.55, 0.25 } or C.bad
	return UI.Colorize(string.format(rate >= 1 and "%.1f%%" or "%.2f%%", rate), c), c
end

local function MobLine(mob)
	local parts = {}
	if mob.level then parts[#parts + 1] = L["Level"] .. " " .. mob.level end
	if mob.hp then parts[#parts + 1] = string.format(L["%s HP"], ns.FormatNumber(mob.hp)) end
	return table.concat(parts, "  ·  ")
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local itemRows = UI.Pool(function(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(46)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = UI.Fill(row, C.panel, "BACKGROUND")
	row.bg:SetAllPoints()
	row.icon = UI.ItemIcon(row, 36)
	row.icon:SetPoint("LEFT", 6, 0)
	row.name = UI.Text(row, 14)
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -2)
	row.name:SetPoint("RIGHT", row, "RIGHT", -150, 0)
	row.name:SetWordWrap(false)
	row.info = UI.Text(row, 12, C.muted)
	row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 2)
	row.info:SetPoint("RIGHT", row, "RIGHT", -150, 0)
	row.info:SetWordWrap(false)
	row.rate = UI.Text(row, 16, C.text, "RIGHT")
	row.rate:SetPoint("TOPRIGHT", -12, -7)
	row.barBg = UI.Fill(row, { 1, 1, 1, 0.07 }, "ARTWORK")
	row.barBg:SetPoint("BOTTOMRIGHT", -12, 9)
	row.barBg:SetSize(110, 4)
	row.bar = UI.Fill(row, C.good, "OVERLAY")
	row.bar:SetPoint("LEFT", row.barBg, "LEFT")
	row.bar:SetHeight(4)
	row.star = row:CreateTexture(nil, "OVERLAY")
	row.star:SetTexture("Interface\\COMMON\\FavoritesIcon")
	row.star:SetSize(20, 20)
	row.star:SetPoint("RIGHT", row.rate, "LEFT", -6, 0)
	row:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(C.hover[1], C.hover[2], C.hover[3], 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		local itemID, info = ns.ResolveItem(self.itemID)
		if itemID then
			GameTooltip:SetItemByID(itemID)
		else
			GameTooltip:SetText(tostring(self.itemID))
			if info then
				GameTooltip:AddLine(L["Item level"] .. " " .. tostring(info.ilvl or "?") .. "  ·  " .. (info.slot or "") .. (info.type and info.type ~= "" and (" (" .. info.type .. ")") or ""), 1, 1, 1)
			end
			GameTooltip:AddLine(L["New in WoW Forever: details appear once the item has been seen in game."], 0.6, 0.6, 0.6, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Shift-click: link in chat  |  Ctrl-click: try on  |  Alt-click: wishlist"], 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetVertexColor(C.panel[1], C.panel[2], C.panel[3], 1)
		GameTooltip_Hide()
	end)
	row:SetScript("OnClick", function(self)
		local _, link = C_Item.GetItemInfo(ns.ResolveItem(self.itemID) or self.itemID)
		if IsAltKeyDown() then
			local wl = ns.FC:GetModule("DungeonGuide"):Global().wishlist
			wl[self.itemID] = not wl[self.itemID] or nil
			self:Refresh()
		elseif IsControlKeyDown() and link then
			DressUpItemLink(link)
		elseif IsShiftKeyDown() and link then
			local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
			if insert then insert(link) end
		end
	end)
	function row:Refresh()
		local itemID, finfo = ns.ResolveItem(self.itemID)
		itemID = itemID or self.itemID
		local name, _, quality, _, _, itemType, subType, _, equipLoc, icon = C_Item.GetItemInfo(itemID)
		if not name and finfo then
			name, quality, itemType, subType = finfo.name, finfo.quality, finfo.slot, finfo.type
			if type(itemID) == "string" then self.icon:SetItem(nil, quality) end
		end
		if not icon and type(itemID) == "number" and C_Item.GetItemInfoInstant then
			local _, t, st, el, ic = C_Item.GetItemInfoInstant(itemID)
			itemType, subType, equipLoc, icon = t, st, el, ic
		end
		self.icon:SetItem(icon, quality)
		if name then
			local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
			self.name:SetText(color and color.hex and (color.hex .. name .. "|r") or name)
		else
			self.name:SetText(UI.Colorize(L["Item"] .. " #" .. itemID, C.muted))
		end
		local info = {}
		if equipLoc and equipLoc ~= "" and type(_G[equipLoc]) == "string" then info[#info + 1] = _G[equipLoc] end
		if subType and subType ~= "" and subType ~= info[1] then info[#info + 1] = subType elseif itemType then info[#info + 1] = itemType end
		if self.extra then info[#info + 1] = self.extra end
		self.info:SetText(table.concat(info, "  ·  "))
		self.star:SetShown(ns.FC:GetModule("DungeonGuide"):Global().wishlist[itemID] == true)
		return name ~= nil
	end
	function row:SetData(item, extra)
		self.itemID, self.extra = item.itemID, extra
		local rate = item.rate or item.measured
		if item.count then
			self.rate:SetText(item.count > 1 and ("x" .. item.count) or "")
			self.bar:Hide() self.barBg:Hide()
		elseif rate then
			local text, color = Percent(rate)
			self.rate:SetText(text)
			self.bar:SetVertexColor(color[1], color[2], color[3], 1)
			self.bar:SetWidth(math.max(2, 110 * math.min(1, math.sqrt(rate / 100))))
			self.bar:Show() self.barBg:Show()
		else
			self.rate:SetText(UI.Colorize("?", C.muted))
			self.bar:Hide() self.barBg:Hide()
		end
		if item.measured and item.kills and item.kills > 0 and item.rate then
			self.extra = (extra and extra .. "  ·  " or "") .. string.format("%s %.1f%% (%d %s)", L["measured:"], item.measured, item.kills, L["kills"])
		end
		if not self:Refresh() and type(self.itemID) == "number" then
			if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(self.itemID) end
			ns.FC:GetModule("DungeonGuide").pending = true
		end
	end
	return row
end)

local textBlocks = UI.Pool(function(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.text = UI.Text(f, 13)
	f.text:SetPoint("TOPLEFT")
	f.text:SetPoint("TOPRIGHT")
	function f:Set(text, size, color)
		self.text:SetFontObject(UI.Font(size or 13))
		local c = color or C.text
		self.text:SetTextColor(c[1], c[2], c[3])
		self.text:SetText(text)
		self:SetHeight(math.max(1, self.text:GetStringHeight()))
	end
	return f
end)

local sections = UI.Pool(function(parent) return UI.SectionTitle(parent, "") end)

-- Clickable card (bosses, trash, suggested dungeons).
local cards = UI.Pool(function(parent)
	local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
	UI.Backdrop(card, C.panel, C.border)
	card:SetHeight(70)
	card.title = UI.Text(card, 15, C.gold)
	card.title:SetPoint("TOPLEFT", 12, -14)
	card.title:SetPoint("RIGHT", -104, 0)
	card.title:SetWordWrap(false)
	card.sub = UI.Text(card, 12, C.muted)
	card.sub:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -7)
	card.sub:SetPoint("RIGHT", -104, 0)
	card.sub:SetWordWrap(false)
	card.icons = {}
	for i = 1, 3 do
		local icon = UI.ItemIcon(card, 26)
		icon:SetPoint("RIGHT", -10 - (i - 1) * 30, 0)
		card.icons[i] = icon
	end
	card:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1) self:SetBackdropColor(C.panel2[1], C.panel2[2], C.panel2[3], 1) end)
	card:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1) self:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 1) end)
	function card:Set(title, sub, items, onClick, titleColor)
		self.title:SetText(title)
		local c = titleColor or C.gold
		self.title:SetTextColor(c[1], c[2], c[3])
		self.sub:SetText(sub or "")
		for i = 1, 3 do
			local itemID = items and items[i]
			if itemID then
				local _, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
				if not icon and C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(itemID)) end
				self.icons[i]:SetItem(icon, quality)
				self.icons[i]:Show()
			else
				self.icons[i]:Hide()
			end
		end
		self:SetScript("OnClick", onClick)
	end
	return card
end)

-- Quest card: status, title, level, giver, turn-in, prerequisite, objectives and arrow buttons.
local questBlocks = UI.Pool(function(parent)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.Backdrop(f, C.panel, C.border)
	f.stripe = UI.Fill(f, C.accent, "ARTWORK")
	f.stripe:SetPoint("TOPLEFT", 1, -1)
	f.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	f.stripe:SetWidth(3)
	f.status = f:CreateTexture(nil, "OVERLAY")
	f.status:SetSize(22, 22)
	f.status:SetPoint("TOPLEFT", 14, -12)
	f.title = UI.Text(f, 16, C.gold)
	f.title:SetPoint("LEFT", f.status, "RIGHT", 8, 0)
	f.title:SetPoint("RIGHT", f, "RIGHT", -200, 0)
	f.title:SetWordWrap(false)
	f.chips = { UI.Chip(f, 12), UI.Chip(f, 12) }
	f.body = UI.Text(f, 13, C.text)
	f.body:SetPoint("TOPLEFT", 16, -44)
	f.body:SetPoint("RIGHT", f, "RIGHT", -200, 0)
	f.body:SetSpacing(4)
	f.giverButton = UI.Button(f, L["Way to the giver"], 170, 26, "accent")
	f.giverButton:SetPoint("TOPRIGHT", -14, -46)
	f.turninButton = UI.Button(f, L["Way to the turn-in"], 170, 26, "normal")
	local function Way(button, npc, title)
		if npc and npc[8] then
			button:SetScript("OnClick", function()
				ns.SetWaypoint(npc[8][1], npc[8][2], npc[8][3], npc[1] .. " - " .. title, "guide")
				ns.Print(string.format(L["The arrow now points to %s (%s)."], npc[1], ns.MapName(npc[8][1])))
				PlaySound(SOUNDKIT.MAP_PING or 3175)
			end)
			button:Show()
		elseif npc and npc[2] and npc[5] ~= 1 and not npc[6] then
			button:SetScript("OnClick", function()
				ns.SetWorldWaypoint(npc[2], npc[3], npc[4], npc[1] .. " - " .. title, "guide")
				ns.Print(string.format(L["The arrow now points to %s (%s)."], npc[1], Place(npc[2], npc[3], npc[4])))
				PlaySound(SOUNDKIT.MAP_PING or 3175)
			end)
			button:Show()
		else
			button:Hide()
		end
	end
	function f:Set(id, q)
		local title = QuestTitle(id)
		local done, inLog = QuestDone(id), QuestInLog(id)
		if done then
			self.status:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
		elseif inLog then
			self.status:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
		else
			self.status:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
		end
		local color = done and C.muted or UI.LevelColor(q[2], q[2])
		self.title:SetText(title)
		self.title:SetTextColor(color[1], color[2], color[3])
		self.stripe:SetVertexColor(color[1], color[2], color[3], 1)
		self.chips[1]:Set(string.format(L["Level %d (from %d)"], q[2], q[3]), color)
		self.chips[1]:ClearAllPoints()
		self.chips[1]:SetPoint("TOPRIGHT", -14, -12)
		local sideText = q[4] == 1 and L["Alliance"] or q[4] == 2 and L["Horde"] or nil
		if done or inLog or sideText then
			self.chips[2]:Set(done and L["Done"] or inLog and L["In your quest log"] or sideText,
				done and C.good or inLog and C.warn or (q[4] == 1 and { 0.35, 0.6, 1 } or { 1, 0.35, 0.3 }))
			self.chips[2]:ClearAllPoints()
			self.chips[2]:SetPoint("RIGHT", self.chips[1], "LEFT", -6, 0)
			self.chips[2]:Show()
		else
			self.chips[2]:Hide()
		end
		local lines = {}
		local function Add(label, text) lines[#lines + 1] = UI.Colorize(label, C.muted) .. "  " .. text end
		Add(L["Giver:"], NpcLine(q.giver))
		if q.turnin then Add(L["Turn in:"], NpcLine(q.turnin)) end
		if q[7] and q[7] > 0 then
			Add(L["Requires:"], QuestTitle(q[7]) .. (QuestDone(q[7]) and UI.Colorize("  (" .. L["Done"] .. ")", C.good) or ""))
		end
		if q.group then Add(L["Group:"], string.format(L["%d players"], q.group)) end
		if q.kills then
			local kills = {}
			for i = 1, #q.kills, 2 do kills[#kills + 1] = q.kills[i + 1] > 1 and (q.kills[i] .. " x" .. q.kills[i + 1]) or q.kills[i] end
			Add(L["Kill:"], table.concat(kills, ", "))
		end
		if q.objectives and q.objectives ~= "" then
			lines[#lines + 1] = " "
			lines[#lines + 1] = UI.Colorize(q.objectives, { 0.82, 0.84, 0.9 })
		end
		self.body:SetText(table.concat(lines, "\n"))
		Way(self.giverButton, q.giver, title)
		Way(self.turninButton, q.turnin, title)
		self.turninButton:ClearAllPoints()
		if self.giverButton:IsShown() then
			self.turninButton:SetPoint("TOPRIGHT", self.giverButton, "BOTTOMRIGHT", 0, -6)
		else
			self.turninButton:SetPoint("TOPRIGHT", -14, -46)
		end
		self:SetHeight(math.max(118, 58 + self.body:GetStringHeight()))
	end
	return f
end)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function Guide:CreateWindow()
	if self.frame then return end
	local f = UI.Window("ForeverCompanionGuide", L["Dungeon & raid guide"], 1060, 700, self:Global().window,
		{ resizable = true, minWidth = 860, minHeight = 520 })
	self.frame = f
	f.OnResized = function() self:Render() end

	-- Sidebar
	local side = CreateFrame("Frame", nil, f.content, "BackdropTemplate")
	side:SetPoint("TOPLEFT", 0, 0)
	side:SetPoint("BOTTOMLEFT", 0, 0)
	side:SetWidth(SIDEBAR_WIDTH)
	UI.Backdrop(side, C.panel, { 0, 0, 0, 0 })
	local edge = UI.Separator(side)
	edge:SetPoint("TOPRIGHT")
	edge:SetPoint("BOTTOMRIGHT")
	edge:SetWidth(1)

	local search = UI.EditBox(side, SIDEBAR_WIDTH - 24, 30, L["Search a dungeon, boss or item"])
	search:SetPoint("TOPLEFT", 12, -12)
	search:HookScript("OnTextChanged", function(box)
		self.filter = box:GetText():lower()
		if self.filter == "" then self.filter = nil end
		self:RenderNav()
	end)
	self.search = search

	local nav = UI.Scroll(side)
	nav:SetPoint("TOPLEFT", 6, -52)
	nav:SetPoint("BOTTOMRIGHT", -2, 6)
	self.nav = nav

	-- Content
	local main = UI.Scroll(f.content)
	main:SetPoint("TOPLEFT", side, "TOPRIGHT", 0, -2)
	main:SetPoint("BOTTOMRIGHT", -4, 4)
	self.main = main
	self.stack = UI.Stack(main.child, 22)

	-- Hero header used by every page.
	local hero = CreateFrame("Frame", nil, main.child, "BackdropTemplate")
	UI.Backdrop(hero, C.panel, C.border)
	local glow = hero:CreateTexture(nil, "BACKGROUND", nil, 1)
	glow:SetPoint("TOPLEFT", 1, -1)
	glow:SetPoint("BOTTOMRIGHT", -1, 1)
	UI.Gradient(glow, { 0.06, 0.20, 0.28, 0.9 }, { 0.05, 0.06, 0.09, 0.9 })
	hero.model = CreateFrame("PlayerModel", nil, hero)
	hero.model:SetPoint("TOPLEFT", 6, -6)
	hero.model:SetPoint("BOTTOMLEFT", 6, 6)
	hero.model:SetWidth(190)
	hero.model:EnableMouse(true)
	hero.model:SetScript("OnMouseDown", function(m) m.dragX = GetCursorPosition() end)
	hero.model:SetScript("OnMouseUp", function(m) m.dragX = nil end)
	hero.model:SetScript("OnUpdate", function(m)
		if m.dragX then
			local x = GetCursorPosition()
			m.facing = (m.facing or 0) + (x - m.dragX) / 80
			m.dragX = x
			m:SetFacing(m.facing)
		end
	end)
	hero.badgeFrame = UI.ItemIcon(hero, 76)
	hero.badgeFrame:SetPoint("LEFT", 22, 0)
	hero.title = UI.Text(hero, 26, C.gold)
	hero.title:SetWordWrap(false)
	hero.sub = UI.Text(hero, 14, C.muted)
	hero.sub:SetPoint("TOPLEFT", hero.title, "BOTTOMLEFT", 0, -6)
	hero.sub:SetPoint("RIGHT", -20, 0)
	hero.chips = {}
	for i = 1, 5 do hero.chips[i] = UI.Chip(hero, 13) end
	hero.go = UI.Button(hero, L["Show the way to the entrance"], 250, 30, "accent")
	hero.go:SetPoint("BOTTOMRIGHT", -14, 14)
	self.hero = hero
	hero:Hide()

	-- "All quests / my quests" switch of the quest page.
	local questToggle = UI.Button(main.child, "", 320, 28, "ghost")
	questToggle:SetScript("OnClick", function()
		self:Settings().allQuests = not self:Settings().allQuests
		self:Render()
		self:RenderNav()
	end)
	questToggle:Hide()
	self.questToggle = questToggle

	f:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN or 829) end)
	f:SetScript("OnHide", function() PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE or 830) end)
end

-- Fills the hero header. opts: { title, sub, chips = { {text, color} }, npc, badge, way = entry, height }
function Guide:SetHero(opts)
	local hero = self.hero
	hero:Show()
	local showModel = opts.npc and self:Settings().showModels and true or false
	if showModel then
		hero.model:Show()
		if hero.model.ClearModel then hero.model:ClearModel() end
		if not pcall(hero.model.SetCreature, hero.model, opts.npc) then showModel = false end
		hero.model.facing = 0.4
		hero.model:SetFacing(0.4)
	end
	hero.model:SetShown(showModel)
	hero.badgeFrame:SetShown(not showModel and opts.badge ~= nil)
	if opts.badge then hero.badgeFrame:SetItem(opts.badge) end
	local left = showModel and 214 or (opts.badge and 116 or 24)
	hero.title:ClearAllPoints()
	hero.title:SetPoint("TOPLEFT", left, -24)
	hero.title:SetPoint("RIGHT", -20, 0)
	hero.title:SetText(opts.title)
	hero.sub:SetText(opts.sub or "")
	local prev
	for i, chip in ipairs(hero.chips) do
		local data = opts.chips and opts.chips[i]
		if data then
			chip:Set(data[1], data[2])
			chip:ClearAllPoints()
			if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("TOPLEFT", hero.sub, "BOTTOMLEFT", 0, -12) end
			chip:Show()
			prev = chip
		else
			chip:Hide()
		end
	end
	local where = opts.way and (opts.way.where or (opts.way.id and ns.Instances[opts.way.id]))
	hero.go:SetShown(where ~= nil)
	if where then
		hero.go:SetScript("OnClick", function()
			ns.SetWaypoint(where.zone, where.x, where.y, EntryName(opts.way), "guide")
			ns.Print(string.format(L["The arrow now points to %s (%s)."], EntryName(opts.way), ns.MapName(where.zone)))
			PlaySound(SOUNDKIT.MAP_PING or 3175)
		end)
	end
	self.stack:Add(hero, opts.height or (showModel and 210 or 136))
end

---------------------------------------------------------------------------
-- Sidebar navigation
---------------------------------------------------------------------------
local navRows = UI.Pool(function(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(28)
	row.bg = UI.Fill(row, { 1, 1, 1, 0 }, "BACKGROUND")
	row.bg:SetAllPoints()
	row.mark = UI.Fill(row, C.accent, "ARTWORK")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(3)
	row.expand = UI.Text(row, 14, C.muted, "CENTER")
	row.expand:SetPoint("LEFT", 4, 0)
	row.expand:SetWidth(14)
	row.text = UI.Text(row, 13)
	row.text:SetWordWrap(false)
	row.chip = UI.Chip(row, 11)
	row.chip:SetPoint("RIGHT", -8, 0)
	row:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetVertexColor(1, 1, 1, 0.05) end end)
	row:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetVertexColor(1, 1, 1, 0) end end)
	return row
end)

local CATEGORIES = {
	{ key = "dungeon", label = "Dungeons" },
	{ key = "raid", label = "Raids" },
	{ key = "world", label = "World bosses" },
}

local function Matches(filter, text)
	return type(text) == "string" and text:lower():find(filter, 1, true) ~= nil
end

-- Does the instance match the search? Second return: the bosses that match (nil = all).
function Guide:MatchEntry(entry)
	local filter = self.filter
	if not filter then return true, nil end
	local whole = Matches(filter, EntryName(entry))
	local bosses = {}
	local any = whole
	for i, boss in ipairs(self:Bosses(entry)) do
		local hit = Matches(filter, boss.name)
		if not hit then
			local loot = boss.loot or {}
			for j = 1, #loot, 2 do
				if Matches(filter, C_Item.GetItemNameByID and C_Item.GetItemNameByID(loot[j])) then hit = true break end
			end
		end
		if hit then bosses[i] = true any = true end
	end
	return any, (not whole) and bosses or nil
end

function Guide:RenderNav()
	if not self.frame then return end
	navRows:ReleaseAll()
	local child = self.nav.child
	local y = 0
	local collapsed = self:Global().collapsed
	local function Row(indent, height, size, color)
		local row = navRows:Acquire(child)
		row:SetHeight(height or 28)
		row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", child, "RIGHT", 0, 0)
		row.text:ClearAllPoints()
		row.text:SetPoint("LEFT", 20 + indent, 0)
		row.text:SetPoint("RIGHT", row.chip, "LEFT", -6, 0)
		row.text:SetFontObject(UI.Font(size or 13))
		local c = color or C.text
		row.text:SetTextColor(c[1], c[2], c[3])
		row.selected = false
		row.bg:SetVertexColor(1, 1, 1, 0)
		row.mark:Hide()
		row.chip:Hide()
		row.expand:SetText("")
		y = y + (height or 28)
		return row
	end
	local function Select(row, path)
		if self.path == path then
			row.selected = true
			row.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.14)
			row.mark:Show()
		end
		row:SetScript("OnClick", function() self:Open(path) end)
	end

	local home = Row(0, 30, 14)
	home.text:SetText(L["Home"])
	Select(home, "home")

	for _, cat in ipairs(CATEGORIES) do
		local keys = {}
		for _, key in ipairs(self.order) do
			local entry = self.list[key]
			local kind = (entry.kind == "raid" or entry.kind == "world") and entry.kind or "dungeon"
			if kind == cat.key and self:MatchEntry(entry) then keys[#keys + 1] = key end
		end
		if #keys > 0 then
			y = y + 8
			local isCollapsed = collapsed[cat.key] and not self.filter
			local head = Row(0, 30, 13, C.accent)
			head.text:SetText(L[cat.label] .. UI.Colorize("  " .. #keys, C.muted))
			head.expand:SetText(isCollapsed and "+" or "–")
			head:SetScript("OnClick", function()
				collapsed[cat.key] = not collapsed[cat.key] or nil
				self:RenderNav()
			end)
			if not isCollapsed then
				for _, key in ipairs(keys) do
					local entry = self.list[key]
					local row = Row(0)
					row.text:SetText(EntryName(entry) .. ((entry.isNew or entry.collected) and UI.Colorize(" *", C.accent) or ""))
					if entry.min and entry.kind ~= "world" then
						row.chip:Set(entry.min == entry.max and tostring(entry.min) or (entry.min .. "-" .. entry.max), UI.LevelColor(entry.min, entry.max))
						row.chip:Show()
					end
					local open = self.expanded == key or self.filter ~= nil
					row.expand:SetText(open and "–" or "+")
					Select(row, key)
					if open then
						local _, bossFilter = self:MatchEntry(entry)
						for i, boss in ipairs(self:Bosses(entry)) do
							if not bossFilter or bossFilter[i] then
								local color = boss.type == "rare" and { 0.75, 0.75, 1 } or boss.type == "extra" and C.muted or { 0.85, 0.87, 0.92 }
								local b = Row(14, 24, 12, color)
								b.text:SetText(boss.name)
								Select(b, key .. ">b" .. i)
							end
						end
						if entry.kind ~= "world" and not self.filter then
							local t = Row(14, 24, 12, C.muted)
							t.text:SetText(L["Trash"])
							Select(t, key .. ">trash")
							local count = #self:Quests(entry, self:Settings().allQuests)
							if count > 0 then
								local q = Row(14, 24, 12, C.accent)
								q.text:SetText(L["Quests"] .. UI.Colorize("  " .. count, C.muted))
								Select(q, key .. ">quests")
							end
						end
					end
				end
			end
		end
	end

	y = y + 8
	local count = 0
	for _ in pairs(self:Global().wishlist) do count = count + 1 end
	local wish = Row(0, 30, 13, C.gold)
	wish.text:SetText(L["Wishlist"] .. UI.Colorize("  " .. count, C.muted))
	Select(wish, "wishlist")
	self.nav:SetContentHeight(y + 8)
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
function Guide:Clear()
	itemRows:ReleaseAll()
	textBlocks:ReleaseAll()
	sections:ReleaseAll()
	cards:ReleaseAll()
	questBlocks:ReleaseAll()
	self.questToggle:Hide()
	self.hero:Hide()
	self.stack:Reset()
	self.stack:Space(18)
	self.pending = false
end

function Guide:AddText(text, size, color, gap)
	local block = textBlocks:Acquire(self.main.child)
	self.stack:Add(block, 10, gap or 6)
	block:Set(text, size, color)
	self.stack.y = self.stack.y - 10 + block:GetHeight()
	return block
end

function Guide:AddSection(text, gap)
	local s = sections:Acquire(self.main.child)
	s:SetText(text)
	self.stack:Add(s, 28, gap or 18)
	self.stack:Space(8)
end

function Guide:AddItems(list, filter)
	local shown = 0
	for _, item in ipairs(list) do
		if not filter or filter(item) then
			local row = itemRows:Acquire(self.main.child)
			self.stack:Add(row, 46, shown > 0 and 4 or 0)
			row:SetData(item)
			shown = shown + 1
		end
	end
	return shown
end

-- Cards in a grid (two or three columns depending on width).
function Guide:AddCards(list)
	local width = self.main.child:GetWidth() - 44
	local columns = width > 780 and 3 or 2
	local gap = 10
	local w = (width - gap * (columns - 1)) / columns
	local startY = self.stack.y
	for i, data in ipairs(list) do
		local card = cards:Acquire(self.main.child)
		local col = (i - 1) % columns
		local line = math.floor((i - 1) / columns)
		card:SetSize(w, 70)
		card:SetPoint("TOPLEFT", self.main.child, "TOPLEFT", 22 + col * (w + gap), -(startY + line * 80))
		card:Set(data.title, data.sub, data.items, data.onClick, data.color)
	end
	self.stack.y = startY + math.ceil(#list / columns) * 80
end

-- The three best items of a boss (highest quality first), shown on its card.
local function TopItems(boss)
	local ranked, loot = {}, boss.loot or {}
	for i = 1, #loot, 2 do
		ranked[#ranked + 1] = { loot[i], C_Item.GetItemQualityByID(loot[i]) or 2 }
	end
	table.sort(ranked, function(a, b) return a[2] > b[2] end)
	local items = {}
	for i = 1, math.min(3, #ranked) do items[i] = ranked[i][1] end
	return items
end

function Guide:PageHome()
	local total, bosses, items = 0, 0, 0
	for _, key in ipairs(self.order) do
		local entry = self.list[key]
		total = total + 1
		bosses = bosses + #self:Bosses(entry)
		items = items + ItemCount(entry)
	end
	self:SetHero({
		title = L["Dungeon & raid guide"],
		sub = L["Every dungeon and raid of WoW Forever, with the loot of each boss and of the trash, and how often each item drops."],
		badge = UI.MEDIA .. "Logo",
		chips = {
			{ string.format(L["%d instances"], total), C.accent },
			{ string.format(L["%d bosses"], bosses), C.gold },
			{ string.format(L["%d items"], items), C.good },
		},
		height = 140,
	})
	local level = UnitLevel("player")
	local suggested = {}
	for _, key in ipairs(self.order) do
		local entry = self.list[key]
		if entry.min and entry.kind ~= "world" and level >= entry.min - 3 and level <= entry.max then
			local list = entry.bosses or {}
			suggested[#suggested + 1] = {
				title = EntryName(entry),
				sub = string.format(L["Levels %d-%d"], entry.min, entry.max) .. "  ·  " .. string.format(L["%d bosses"], #self:Bosses(entry)),
				items = TopItems(list[#list] or {}),
				color = UI.LevelColor(entry.min, entry.max),
				onClick = function() self:Open(key) end,
			}
		end
	end
	if #suggested > 0 then
		self:AddSection(string.format(L["For your level (%d)"], level))
		self:AddCards(suggested)
	end
	self:AddSection(L["How to use"])
	self:AddText(L["Pick an instance on the left, then a boss for its loot or Trash for the loot of normal monsters. The search box finds dungeons, bosses and items."], 13, C.text)
	self:AddText(L["Shift-click: link in chat  |  Ctrl-click: try on  |  Alt-click: wishlist"], 12, C.muted, 8)
	self:AddSection(L["Where the numbers come from"])
	self:AddText(L["Bosses, health, loot and drop rates come from the Classic database (AtlasLootClassic and CMaNGOS). Rates measured in game by the addon are shown next to them. Forever may change some of them: share your data with /fc drops export."], 12, C.muted)
end

function Guide:PageInstance(key, entry)
	local chips = {}
	if entry.min and entry.kind ~= "world" then chips[#chips + 1] = { string.format(L["Levels %d-%d"], entry.min, entry.max), UI.LevelColor(entry.min, entry.max) } end
	if entry.size then chips[#chips + 1] = { string.format(L["%d players"], entry.size), C.text } end
	if entry.enter and entry.kind ~= "world" then chips[#chips + 1] = { string.format(L["Entry from level %d"], entry.enter), C.muted } end
	if entry.isNew then chips[#chips + 1] = { L["New in Forever"], C.accent } end
	local where = entry.where or (entry.id and ns.Instances[entry.id])
	self:SetHero({
		title = EntryName(entry),
		sub = where and ns.MapName(where.zone) or entry.zoneMap and ns.MapName(entry.zoneMap) or (entry.kind == "world" and L["Outdoors"] or ""),
		badge = entry.kind == "raid" and "Interface\\Icons\\INV_Misc_Head_Dragon_01" or entry.kind == "world" and "Interface\\Icons\\INV_Misc_Head_Dragon_Green" or "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
		chips = chips,
		way = entry,
		height = 140,
	})
	local list = {}
	for i, boss in ipairs(self:Bosses(entry)) do
		local count = boss.loot and #boss.loot / 2 or 0
		local sub = MobLine(boss)
		if boss.type == "extra" then
			sub = string.format("%d %s", count, L["items"])
		elseif count > 0 then
			sub = sub .. "  ·  " .. string.format("%d %s", count, L["items"])
		end
		list[#list + 1] = {
			title = boss.name .. (boss.type == "rare" and UI.Colorize("  " .. L["rare"], { 0.75, 0.75, 1 }) or ""),
			sub = sub,
			items = TopItems(boss),
			color = boss.type == "extra" and C.text or C.gold,
			onClick = function() self:Open(key .. ">b" .. i) end,
		}
	end
	if entry.kind ~= "world" then
		list[#list + 1] = {
			title = L["Trash"],
			sub = string.format(L["%d monsters"], #self:TrashMobs(entry)),
			color = C.muted,
			onClick = function() self:Open(key .. ">trash") end,
		}
	end
	local quests = self:Quests(entry, self:Settings().allQuests)
	if #quests > 0 then
		local done = 0
		for _, id in ipairs(quests) do if QuestDone(id) then done = done + 1 end end
		list[#list + 1] = {
			title = L["Quests"],
			sub = string.format(L["%d quests"], #quests) .. "  ·  " .. string.format(L["%d done"], done),
			color = C.accent,
			onClick = function() self:Open(key .. ">quests") end,
		}
	end
	self:AddSection(L["Bosses"])
	self:AddCards(list)
	if entry.collected then
		self:AddText(L["This instance is not in the built-in database yet: what you see here was recorded by the drop collector."], 12, C.muted, 14)
	end
end

function Guide:PageBoss(key, entry, boss)
	local chips = {}
	if boss.level then chips[#chips + 1] = { L["Level"] .. " " .. boss.level, C.gold } end
	if boss.hp then chips[#chips + 1] = { string.format(L["%s HP"], ns.FormatNumber(boss.hp)), C.good } end
	if boss.type == "rare" then chips[#chips + 1] = { L["rare"], { 0.75, 0.75, 1 } } end
	if boss.kills then chips[#chips + 1] = { string.format(L["Kills recorded: %d"], boss.kills), C.muted } end
	self:SetHero({
		title = boss.name,
		sub = EntryName(entry),
		npc = boss.type ~= "extra" and boss.npc or nil,
		badge = "Interface\\Icons\\INV_Misc_Bag_10",
		chips = chips,
		way = entry,
	})
	local list = self:LootList(entry, boss)
	self:AddSection(string.format("%s  (%d)", L["Loot"], #list))
	if #list == 0 then
		self:AddText(L["No loot known yet. Kill this boss with the addon on and its loot will appear here."], 13, C.muted)
	end
	self:AddItems(list)
end

function Guide:PageTrash(key, entry)
	local mobs = self:TrashMobs(entry)
	local qualityNames = { [0] = ITEM_QUALITY0_DESC, ITEM_QUALITY1_DESC, ITEM_QUALITY2_DESC, ITEM_QUALITY3_DESC, ITEM_QUALITY4_DESC }
	self:SetHero({
		title = EntryName(entry) .. " · " .. L["Trash"],
		sub = string.format(L["%d monsters"], #mobs),
		badge = "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01",
		chips = { { L["Items shown from:"] .. " " .. (qualityNames[self:Settings().minTrashQuality] or "?"), C.muted } },
		way = entry,
		height = 136,
	})
	if #mobs == 0 then
		self:AddText(L["No trash loot recorded yet for this instance."], 13, C.muted, 12)
		return
	end
	local minQuality = self:Settings().minTrashQuality
	local function filter(item)
		local quality = C_Item.GetItemQualityByID(item.itemID)
		return not quality or quality >= minQuality
	end
	for _, mob in ipairs(mobs) do
		self:AddSection((mob.name == "Trash mobs" and L["Trash mobs"] or mob.name) .. "   " .. UI.Colorize(MobLine(mob), C.muted))
		if self:AddItems(self:LootList(entry, mob), filter) == 0 then
			self:AddText(L["Nothing above the chosen quality."], 12, C.muted)
		end
	end
end

function Guide:PageQuests(key, entry)
	local all = self:Settings().allQuests
	local ids = self:Quests(entry, all)
	local done = 0
	for _, id in ipairs(ids) do if QuestDone(id) then done = done + 1 end end
	self:SetHero({
		title = EntryName(entry) .. " · " .. L["Quests"],
		sub = L["Quests that start or are done in this instance, with where to get them, what to do and the rewards."],
		badge = "Interface\\Icons\\INV_Misc_Book_08",
		chips = {
			{ string.format(L["%d quests"], #ids), C.accent },
			{ string.format(L["%d done"], done), C.good },
			{ all and L["Every faction and class"] or L["For your character"], C.muted },
		},
		way = entry,
		height = 140,
	})
	local toggle = self.questToggle
	toggle.label:SetText(all and L["Show my quests only"] or L["Show every quest (other factions and classes)"])
	toggle:Show()
	self.stack:Add(toggle, 28, 14)
	toggle:ClearAllPoints()
	toggle:SetPoint("TOPLEFT", self.main.child, "TOPLEFT", self.stack.pad, -(self.stack.y - 28))
	toggle:SetSize(340, 28)
	if #ids == 0 then
		self:AddText(L["No quest for your character in this instance."], 13, C.muted, 14)
		return
	end
	for index, id in ipairs(ids) do
		local q = ns.DungeonQuestInfo[id]
		local block = questBlocks:Acquire(self.main.child)
		self.stack:Add(block, 118, index == 1 and 16 or 26)
		self.stack.y = self.stack.y - 118
		block:Set(id, q)
		self.stack.y = self.stack.y + block:GetHeight()
		local function Rewards(label, list)
			if not list then return end
			self:AddText(label, 12, C.accent, 10)
			for i = 1, #list, 2 do
				local row = itemRows:Acquire(self.main.child)
				self.stack:Add(row, 46, 4, 18)
				row:SetData({ itemID = list[i], count = list[i + 1] })
			end
		end
		if q.choice then Rewards(#q.choice > 2 and L["Choose one reward:"] or L["Reward:"], q.choice) end
		Rewards(L["You also receive:"], q.reward)
		if q.money then self:AddText(L["Money:"] .. "  " .. ns.FormatMoney(q.money), 12, C.text, 8) end
	end
end

function Guide:PageWishlist()
	local count = 0
	for _ in pairs(self:Global().wishlist) do count = count + 1 end
	self:SetHero({
		title = L["Wishlist"],
		sub = L["Alt-click an item in the guide to add or remove it. You are alerted when it drops."],
		badge = "Interface\\Icons\\INV_Misc_Note_02",
		chips = { { string.format(L["%d items"], count), C.gold } },
		height = 136,
	})
	self:AddSection(L["Items"])
	for itemID in pairs(self:Global().wishlist) do
		local src = ns.ItemDropSources(itemID)[1]
		local row = itemRows:Acquire(self.main.child)
		self.stack:Add(row, 46, 4)
		row:SetData({ itemID = itemID, rate = src and src.rate }, src and (src.name .. " - " .. src.where) or nil)
	end
	if count == 0 then self:AddText(L["Nothing yet."], 13, C.muted) end
end

-- path: "home", "wishlist", "k3", "k3>b2", "k3>trash", "k3>quests"
function Guide:Open(path)
	self.path = path
	local key = path:match("^([kc]%d+)")
	if key then self.expanded = key end
	self.main:ScrollToTop()
	self:Render()
	self:RenderNav()
end

function Guide:Render()
	if not self.frame then return end
	self:Clear()
	local path = self.path or "home"
	local key, sub = path:match("^([kc]%d+)>?(.*)$")
	local entry = key and self.list[key]
	if path == "wishlist" then
		self:PageWishlist()
	elseif entry and sub == "quests" then
		self:PageQuests(key, entry)
	elseif entry and sub == "trash" then
		self:PageTrash(key, entry)
	elseif entry and sub:match("^b%d+$") then
		local boss = self:Bosses(entry)[tonumber(sub:sub(2))]
		if boss then self:PageBoss(key, entry, boss) else self:PageInstance(key, entry) end
	elseif entry then
		self:PageInstance(key, entry)
	else
		self:PageHome()
	end
	self.main:SetContentHeight(self.stack.y + 24)
	self.frame.subtitle:SetText(entry and EntryName(entry) or "")
end

function Guide:Toggle()
	self:CreateWindow()
	if self.frame:IsShown() then
		self.frame:Hide()
		return
	end
	self:BuildList()
	self.frame:Show()
	-- Open on the instance you are in, if any.
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	local found
	if instanceType == "party" or instanceType == "raid" then
		for _, key in ipairs(self.order) do
			if self.list[key].id == instanceID then found = key break end
		end
	end
	self:Open(found or self.path or "home")
end

function ns.ToggleDungeonGuide()
	if Guide:IsEnabled() then Guide:Toggle() else ns.OpenOptions() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Guide:LOOT_OPENED()
	if not self:Settings().wishlistAlert then return end
	for slot = 1, GetNumLootItems() do
		local link = GetLootSlotLink(slot)
		local itemID = ns.ItemIDFromLink(link)
		if itemID and self:Global().wishlist[itemID] then
			RaidNotice_AddMessage(RaidWarningFrame, string.format(L["Wishlist item dropped: %s"], link), ChatTypeInfo.RAID_WARNING)
			PlaySound(SOUNDKIT.READY_CHECK or 8960)
		end
	end
end

function Guide:GET_ITEM_INFO_RECEIVED()
	-- Item names arrive from the server after the page is drawn: fill the rows in place.
	if not (self.frame and self.frame:IsShown() and self.pending) or self.renderPending then return end
	self.renderPending = true
	C_Timer.After(0.25, function()
		self.renderPending = false
		local still = false
		for _, row in ipairs(itemRows.used) do
			if not row:Refresh() then still = true end
		end
		self.pending = still
	end)
end

function Guide:OnEnable()
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
end

function Guide:OnDisable()
	if self.frame then self.frame:Hide() end
end

ns.RegisterCommand("guide", L["open the dungeon & raid guide"], function() ns.ToggleDungeonGuide() end)

function Guide:GetOptions()
	local get, set = ns.ProfileAccessors("DungeonGuide", function() if self.frame and self.frame:IsShown() then self:Render() end end)
	return {
		get = get, set = set,
		args = {
			open = { type = "execute", order = 1, name = L["Open the guide"], func = function() self:Toggle() end },
			wishlistAlert = { type = "toggle", order = 2, width = "full", name = L["Alert me when a wishlist item drops"] },
			showModels = { type = "toggle", order = 3, width = "full", name = L["Show the 3D model of each boss"] },
			allQuests = { type = "toggle", order = 3.5, width = "full", name = L["Show every quest (other factions and classes)"] },
			minTrashQuality = {
				type = "select", order = 4, name = L["Trash items shown from quality"],
				values = { [0] = ITEM_QUALITY0_DESC, [1] = ITEM_QUALITY1_DESC, [2] = ITEM_QUALITY2_DESC, [3] = ITEM_QUALITY3_DESC, [4] = ITEM_QUALITY4_DESC },
			},
		},
	}
end
