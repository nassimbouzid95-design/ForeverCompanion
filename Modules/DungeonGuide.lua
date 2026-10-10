-- ForeverCompanion: dungeon & raid guide.
-- Instances = reference list (Data\Instances.lua) + the in-game Adventure Guide + instances met in game.
-- Bosses and loot lists come from the Adventure Guide when the client has it, and from the drop collector.
-- Drop rates come from the drop collector (and reference rates when we have verified ones).
local _, ns = ...
local L = ns.L

local Guide = ns.NewModule("DungeonGuide", {
	minTrashQuality = 2, -- uncommon and better
	wishlistAlert = true,
}, {
	wishlist = {}, -- [itemID] = true
})

local AceGUI = LibStub("AceGUI-3.0")
local SEP = "\001"

---------------------------------------------------------------------------
-- Building the instance list
---------------------------------------------------------------------------
local function ReadJournal(list)
	if not (EJ_GetNumTiers and EJ_GetInstanceByIndex) then return end
	local ok = pcall(function()
		for tier = 1, EJ_GetNumTiers() do
			EJ_SelectTier(tier)
			for _, isRaid in ipairs({ false, true }) do
				local index = 1
				while true do
					local journalID, name = EJ_GetInstanceByIndex(index, isRaid)
					if not journalID then break end
					local mapID = select(10, EJ_GetInstanceInfo(journalID))
					if mapID and mapID > 0 then
						local entry = list[mapID] or { id = mapID }
						list[mapID] = entry
						entry.name = entry.name or name
						entry.kind = entry.kind or (isRaid and "raid" or "dungeon")
						entry.journalID = journalID
						entry.bosses = {}
						local b = 1
						while true do
							local bossName, _, journalEncounterID, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(b, journalID)
							if not bossName then break end
							entry.bosses[#entry.bosses + 1] = { name = bossName, journalEncounterID = journalEncounterID, encounterID = dungeonEncounterID }
							b = b + 1
						end
					end
					index = index + 1
				end
			end
		end
	end)
	return ok
end

function Guide:BuildList()
	local list = {}
	for id, info in pairs(ns.Instances) do
		list[id] = { id = id, name = ns.InstanceName(id), kind = info.kind, min = info.min, max = info.max, size = info.size, zone = info.zone, x = info.x, y = info.y }
	end
	ReadJournal(list)
	for id, data in pairs(ns.CollectedInstances and ns.CollectedInstances() or {}) do
		local entry = list[id] or { id = id }
		list[id] = entry
		entry.name = entry.name or data.name or ns.InstanceName(id)
		entry.kind = entry.kind or data.kind
		entry.size = entry.size or data.size
	end
	for _, raid in ipairs(ns.ForeverRaids) do
		for _, entry in pairs(list) do
			if entry.name == raid.name then
				entry.size, entry.min, entry.max, entry.isNew = entry.size or raid.size, raid.min, raid.max, true
			end
		end
	end
	self.list = list
	return list
end

---------------------------------------------------------------------------
-- Tree
---------------------------------------------------------------------------
local function SortInstances(a, b)
	if (a.min or 99) ~= (b.min or 99) then return (a.min or 99) < (b.min or 99) end
	return (a.name or "") < (b.name or "")
end

-- Bosses of an instance: Adventure Guide first, then bosses only the collector knows.
function Guide:Bosses(entry)
	local bosses, known = {}, {}
	for _, boss in ipairs(entry.bosses or {}) do
		bosses[#bosses + 1] = boss
		if boss.encounterID then known[boss.encounterID] = true end
	end
	local data = ns.CollectedInstances()[entry.id]
	if data then
		local extra = {}
		for encounterID, enc in pairs(data.encounters) do
			if not known[encounterID] then
				extra[#extra + 1] = { name = enc.name or ("#" .. encounterID), encounterID = encounterID }
			end
		end
		table.sort(extra, function(a, b) return a.name < b.name end)
		for _, boss in ipairs(extra) do bosses[#bosses + 1] = boss end
	end
	return bosses
end

function Guide:BuildTree()
	local dungeons, raids = {}, {}
	for _, entry in pairs(self:BuildList()) do
		local node = {
			value = "i" .. entry.id,
			text = string.format("%s%s", entry.name or "?", entry.min and string.format(" |cff888888(%d-%d)|r", entry.min, entry.max) or ""),
			children = {},
			sort = entry,
		}
		for i, boss in ipairs(self:Bosses(entry)) do
			node.children[#node.children + 1] = { value = "b" .. i, text = boss.name }
		end
		node.children[#node.children + 1] = { value = "trash", text = "|cffaaaaaa" .. L["Trash"] .. "|r" }
		if entry.kind == "raid" then raids[#raids + 1] = node else dungeons[#dungeons + 1] = node end
	end
	local function sorter(a, b) return SortInstances(a.sort, b.sort) end
	table.sort(dungeons, sorter)
	table.sort(raids, sorter)
	for _, n in ipairs(dungeons) do n.sort = nil end
	for _, n in ipairs(raids) do n.sort = nil end
	return {
		{ value = "dungeons", text = L["Dungeons"], children = dungeons },
		{ value = "raids", text = L["Raids"], children = raids },
		{ value = "wishlist", text = "|cffffd100" .. L["Wishlist"] .. "|r" },
	}
end

---------------------------------------------------------------------------
-- Item rows
---------------------------------------------------------------------------
local function RateText(rate, kills)
	if not rate then
		return kills > 0 and string.format("|cff8888880%% (%d %s)|r", kills, L["kills"]) or "|cff888888" .. L["no data"] .. "|r"
	end
	local color = rate >= 20 and "ff33ff33" or rate >= 5 and "ffffd100" or "ffff8844"
	if kills > 0 then
		return string.format("|c%s%.1f%%|r |cff888888(%d %s)|r", color, rate, kills, L["kills"])
	end
	return string.format("|c%s%.1f%%|r |cff888888(%s)|r", color, rate, L["reference"])
end

function Guide:AddItemRow(container, itemID, rateText)
	local row = AceGUI:Create("InteractiveLabel")
	row:SetFullWidth(true)
	row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	local function Render()
		local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
		local star = self:Global().wishlist[itemID] and "|TInterface\\COMMON\\FavoritesIcon:14|t " or ""
		row:SetImage(icon or C_Item.GetItemIconByID(itemID))
		row:SetImageSize(18, 18)
		row:SetText(string.format("%s%s   %s", star, link or name or ("#" .. itemID), rateText or ""))
		return quality
	end
	Render()
	row:SetCallback("OnEnter", function(widget)
		GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR")
		GameTooltip:SetItemByID(itemID)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Shift-click: link in chat  |  Ctrl-click: try on  |  Alt-click: wishlist"], 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	row:SetCallback("OnLeave", GameTooltip_Hide)
	row:SetCallback("OnClick", function()
		local _, link = C_Item.GetItemInfo(itemID)
		if IsAltKeyDown() then
			local wl = self:Global().wishlist
			wl[itemID] = not wl[itemID] or nil
			Render()
		elseif IsControlKeyDown() and link then
			DressUpItemLink(link)
		elseif IsShiftKeyDown() and link then
			local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
			if insert then insert(link) end
		end
	end)
	container:AddChild(row)
end

local function Heading(container, text)
	local h = AceGUI:Create("Heading")
	h:SetFullWidth(true)
	h:SetText(text)
	container:AddChild(h)
end

local function Text(container, text, font)
	local label = AceGUI:Create("Label")
	label:SetFullWidth(true)
	if font then label:SetFontObject(font) end
	label:SetText(text)
	container:AddChild(label)
	return label
end

-- Loot of a boss: Adventure Guide list + items seen by the collector, sorted by rate.
function Guide:BossLoot(entry, boss)
	local items = {}
	local data = ns.CollectedInstances()[entry.id]
	local enc = data and boss.encounterID and data.encounters[boss.encounterID]
	local npcID = enc and enc.npc

	if boss.journalEncounterID and EJ_SelectEncounter then
		pcall(function()
			EJ_SelectInstance(entry.journalID)
			EJ_SelectEncounter(boss.journalEncounterID)
			if EJ_ResetLootFilter then EJ_ResetLootFilter() end
			for i = 1, EJ_GetNumLoot() do
				local info = C_EncounterJournal.GetLootInfoByIndex(i)
				if info and info.itemID then items[info.itemID] = true end
			end
		end)
	end
	if npcID and data.npcs[npcID] then
		for itemID in pairs(data.npcs[npcID].items) do items[itemID] = true end
	end
	local list = {}
	for itemID in pairs(items) do
		local rate, kills = 0, 0
		if npcID then rate, kills = ns.DropRate(entry.id, npcID, itemID) end
		list[#list + 1] = { itemID = itemID, rate = rate, kills = kills or 0 }
	end
	table.sort(list, function(a, b) return (a.rate or 0) > (b.rate or 0) end)
	return list, enc
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
function Guide:ShowInstance(container, entry)
	Text(container, entry.name or "?", GameFontNormalHuge)
	local parts = {}
	if entry.min then parts[#parts + 1] = string.format(L["Levels %d-%d"], entry.min, entry.max) end
	if entry.size then parts[#parts + 1] = string.format(L["%d players"], entry.size) end
	if entry.zone then parts[#parts + 1] = ns.MapName(entry.zone) end
	if entry.isNew then parts[#parts + 1] = "|cff33ccff" .. L["New in Forever"] .. "|r" end
	Text(container, table.concat(parts, "  |  "), GameFontHighlight)
	if entry.zone and entry.x then
		local go = AceGUI:Create("Button")
		go:SetText(L["Show the way to the entrance"])
		go:SetWidth(240)
		go:SetCallback("OnClick", function() ns.SetWaypoint(entry.zone, entry.x, entry.y, entry.name, "guide") end)
		container:AddChild(go)
	end
	local data = ns.CollectedInstances()[entry.id]
	local kills = 0
	if data then for _, npc in pairs(data.npcs) do kills = kills + npc.kills end end
	Text(container, "\n" .. string.format(L["Kills recorded in this instance: %d"], kills))
	Text(container, "|cff888888" .. L["Select a boss on the left for its loot and drop rates, or Trash for the loot of normal monsters."] .. "|r")
end

function Guide:ShowBoss(container, entry, boss)
	Text(container, boss.name, GameFontNormalHuge)
	Text(container, entry.name, GameFontHighlight)
	local list, enc = self:BossLoot(entry, boss)
	Text(container, string.format(L["Kills recorded: %d"], enc and enc.kills or 0))
	Heading(container, L["Loot"])
	if #list == 0 then
		Text(container, "|cff888888" .. L["No loot known yet. Kill this boss with the addon on and its loot will appear here."] .. "|r")
	end
	for _, item in ipairs(list) do
		self:AddItemRow(container, item.itemID, RateText(item.rate, item.kills))
	end
end

function Guide:ShowTrash(container, entry)
	Text(container, entry.name .. " - " .. L["Trash"], GameFontNormalHuge)
	local data = ns.CollectedInstances()[entry.id]
	local npcs = {}
	if data then
		for npcID, npc in pairs(data.npcs) do
			if not npc.boss and next(npc.items) then npcs[#npcs + 1] = { id = npcID, npc = npc } end
		end
	end
	table.sort(npcs, function(a, b) return a.npc.kills > b.npc.kills end)
	if #npcs == 0 then
		Text(container, "|cff888888" .. L["No trash loot recorded yet for this instance."] .. "|r")
		return
	end
	local minQuality = self:Settings().minTrashQuality
	for _, e in ipairs(npcs) do
		Heading(container, string.format("%s  |cff888888(%d %s)|r", e.npc.name or ("#" .. e.id), math.max(e.npc.kills, e.npc.looted), L["kills"]))
		local items = {}
		for itemID in pairs(e.npc.items) do
			local quality = C_Item.GetItemQualityByID(itemID)
			if not quality or quality >= minQuality then
				local rate, kills = ns.DropRate(entry.id, e.id, itemID)
				items[#items + 1] = { itemID = itemID, rate = rate, kills = kills }
			end
		end
		table.sort(items, function(a, b) return (a.rate or 0) > (b.rate or 0) end)
		for _, item in ipairs(items) do
			self:AddItemRow(container, item.itemID, RateText(item.rate, item.kills))
		end
	end
end

function Guide:ShowWishlist(container)
	Text(container, L["Wishlist"], GameFontNormalHuge)
	Text(container, "|cff888888" .. L["Alt-click an item in the guide to add or remove it. You are alerted when it drops."] .. "|r")
	for itemID in pairs(self:Global().wishlist) do
		local sources = ns.ItemDropSources(itemID)
		local where = sources[1] and string.format("%s - %s %s", ns.InstanceName(sources[1].instanceID), sources[1].name, RateText(sources[1].rate, sources[1].kills)) or ""
		self:AddItemRow(container, itemID, where)
	end
end

function Guide:Select(path)
	local content = self.content
	content:ReleaseChildren()
	local instanceKey, sub = path:match("i(%d+)" .. SEP .. "?([^" .. SEP .. "]*)$")
	if path:find("wishlist", 1, true) then
		self:ShowWishlist(content)
	elseif instanceKey then
		local entry = self.list[tonumber(instanceKey)]
		if not entry then return end
		if sub == "trash" then
			self:ShowTrash(content, entry)
		elseif sub and sub:match("^b%d+$") then
			local boss = self:Bosses(entry)[tonumber(sub:sub(2))]
			if boss then self:ShowBoss(content, entry, boss) end
		else
			self:ShowInstance(content, entry)
		end
	else
		Text(content, L["Dungeon & raid guide"], GameFontNormalHuge)
		Text(content, L["Every dungeon and raid of WoW Forever, with the loot of each boss and of the trash, and how often each item drops."])
	end
	content:DoLayout()
end

function Guide:Toggle()
	if self.frame then
		self.frame:Hide() -- fires OnClose, which releases it
		return
	end
	local frame = AceGUI:Create("Frame")
	self.frame = frame
	frame:SetTitle(ns.TAG .. " - " .. L["Dungeon & raid guide"])
	frame:SetLayout("Fill")
	frame:SetWidth(860)
	frame:SetHeight(600)
	frame:SetStatusText(L["Drop rates are measured by players using the addon. Share yours with /fc drops export."])
	frame:SetCallback("OnClose", function(widget)
		AceGUI:Release(widget)
		self.frame, self.content = nil, nil
	end)

	local tree = AceGUI:Create("TreeGroup")
	tree:SetLayout("Fill")
	tree:SetTree(self:BuildTree())
	tree:SetTreeWidth(260, true)
	frame:AddChild(tree)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	tree:AddChild(scroll)
	self.content = scroll

	tree:SetCallback("OnGroupSelected", function(_, _, path)
		self.path = path
		self:Select(path)
	end)
	-- Open on the instance you are in, if any.
	local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if (instanceType == "party" or instanceType == "raid") and self.list[instanceID] then
		local top = self.list[instanceID].kind == "raid" and "raids" or "dungeons"
		tree:SelectByPath(top, "i" .. instanceID)
	else
		self:Select("")
	end
end

function ns.ToggleDungeonGuide()
	if Guide:IsEnabled() then Guide:Toggle() else ns.OpenOptions() end
end

---------------------------------------------------------------------------
-- Wishlist alert
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

function Guide:EJ_LOOT_DATA_RECIEVED()
	-- Item info arrives a bit later than the list; redraw the page once.
	if self.content and self.path and not self.redrawPending then
		self.redrawPending = true
		C_Timer.After(0.3, function()
			self.redrawPending = false
			if self.content then self:Select(self.path) end
		end)
	end
end

function Guide:OnEnable()
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
end

function Guide:OnDisable()
	if self.frame then self.frame:Hide() end
end

ns.RegisterCommand("guide", L["open the dungeon & raid guide"], function() ns.ToggleDungeonGuide() end)

function Guide:GetOptions()
	local get, set = ns.ProfileAccessors("DungeonGuide")
	return {
		get = get, set = set,
		args = {
			open = { type = "execute", order = 1, name = L["Open the guide"], func = function() self:Toggle() end },
			wishlistAlert = { type = "toggle", order = 2, width = "full", name = L["Alert me when a wishlist item drops"] },
			minTrashQuality = {
				type = "select", order = 3, name = L["Trash items shown from quality"],
				values = { [0] = ITEM_QUALITY0_DESC, [1] = ITEM_QUALITY1_DESC, [2] = ITEM_QUALITY2_DESC, [3] = ITEM_QUALITY3_DESC, [4] = ITEM_QUALITY4_DESC },
			},
		},
	}
end
