-- ForeverCompanion: dungeon & raid guide.
-- Instances, bosses, health, loot and rates come from the built-in database (Data\InstanceDB.lua);
-- rates measured by the drop collector are shown next to them, and instances only the collector
-- knows (new Forever content) are listed too.
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
-- Instance list: the built-in database (Data\InstanceDB.lua) first, then instances only the
-- drop collector knows (new Forever content).
---------------------------------------------------------------------------
local function EntryName(entry)
	if entry.kind == "world" then return L["World bosses"] end
	return entry.name or ns.InstanceName(entry.id)
end
ns.InstanceEntryName = EntryName

function Guide:BuildList()
	local list, known = {}, {}
	for index, entry in ipairs(ns.InstanceDB or {}) do
		list["k" .. index] = entry
		if entry.id then known[entry.id] = true end
	end
	for id, data in pairs(ns.CollectedInstances and ns.CollectedInstances() or {}) do
		if not known[id] then
			local entry = { id = id, name = data.name or ns.InstanceName(id), kind = data.kind == "raid" and "raid" or "dungeon", size = data.size, collected = true }
			for _, raid in ipairs(ns.ForeverRaids) do
				if raid.name == entry.name then entry.min, entry.max, entry.size, entry.isNew = raid.min, raid.max, raid.size, true end
			end
			list["c" .. id] = entry
		end
	end
	self.list = list
	return list
end

-- Bosses of a collector-only instance.
function Guide:CollectedBosses(entry)
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

function Guide:Bosses(entry)
	if entry.collected then return self:CollectedBosses(entry) end
	return entry.bosses or {}
end

---------------------------------------------------------------------------
-- Tree
---------------------------------------------------------------------------
local function SortNodes(a, b)
	if (a.entry.min or 99) ~= (b.entry.min or 99) then return (a.entry.min or 99) < (b.entry.min or 99) end
	return a.index < b.index
end

local function BossLabel(boss)
	if boss.type == "rare" then return "|cffbbbbff" .. boss.name .. "|r |cff888888(" .. L["rare"] .. ")|r" end
	if boss.type == "extra" then return "|cffaaaaaa" .. boss.name .. "|r" end
	return boss.name
end

function Guide:BuildTree()
	local groups = { dungeon = {}, raid = {}, world = {} }
	local order = 0
	for key, entry in pairs(self:BuildList()) do
		order = order + 1
		local index = tonumber(key:sub(2)) or (1000 + order)
		local text = EntryName(entry)
		if entry.min and entry.kind ~= "world" then
			text = text .. string.format(" |cff888888(%d-%d)|r", entry.min, entry.max)
		end
		if entry.isNew or entry.collected then text = text .. " |cff33ccff*|r" end
		local node = { value = key, text = text, children = {}, entry = entry, index = index }
		for i, boss in ipairs(self:Bosses(entry)) do
			node.children[#node.children + 1] = { value = "b" .. i, text = BossLabel(boss) }
		end
		if entry.kind ~= "world" then
			node.children[#node.children + 1] = { value = "trash", text = "|cffaaaaaa" .. L["Trash"] .. "|r" }
		end
		local group = groups[entry.kind] or groups.dungeon
		group[#group + 1] = node
	end
	for _, group in pairs(groups) do
		table.sort(group, SortNodes)
		for _, node in ipairs(group) do node.entry, node.index = nil, nil end
	end
	local tree = {
		{ value = "dungeons", text = L["Dungeons"], children = groups.dungeon },
		{ value = "raids", text = L["Raids"], children = groups.raid },
	}
	-- World bosses: one entry, shown directly with its bosses.
	if groups.world[1] then tree[#tree + 1] = groups.world[1] end
	tree[#tree + 1] = { value = "wishlist", text = "|cffffd100" .. L["Wishlist"] .. "|r" }
	return tree
end

---------------------------------------------------------------------------
-- Item rows
---------------------------------------------------------------------------
local function Percent(rate)
	local color = rate >= 20 and "ff33ff33" or rate >= 5 and "ffffd100" or rate >= 1 and "ffff8844" or "ffff4444"
	local fmt = rate >= 1 and "%.1f%%" or "%.2f%%"
	return string.format("|c%s" .. fmt .. "|r", color, rate)
end

-- Reference rate from the database, plus the rate measured by the collector when there is one.
local function RateText(rate, measured, kills)
	local parts = {}
	if rate and rate >= 0 then
		parts[#parts + 1] = Percent(rate)
	elseif rate then
		parts[#parts + 1] = "|cff888888?|r"
	end
	if measured and kills and kills > 0 then
		parts[#parts + 1] = string.format("|cff888888%s %s (%d %s)|r", L["measured:"], Percent(measured), kills, L["kills"])
	end
	return table.concat(parts, "  ")
end
ns.DropRateText = RateText

function Guide:AddItemRow(container, itemID, rateText)
	local row = AceGUI:Create("InteractiveLabel")
	row:SetFullWidth(true)
	row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	local function Render()
		local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
		local star = self:Global().wishlist[itemID] and "|TInterface\\COMMON\\FavoritesIcon:14|t " or ""
		row:SetImage(icon or C_Item.GetItemIconByID(itemID))
		row:SetImageSize(18, 18)
		row:SetText(string.format("%s%s   %s", star, link or name or ("|cff888888" .. L["Item"] .. " #" .. itemID .. "|r"), rateText or ""))
		return name ~= nil
	end
	if not Render() then
		if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
		self.pendingRows[#self.pendingRows + 1] = Render
	end
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

local function MobInfo(mob)
	local parts = {}
	if mob.level then parts[#parts + 1] = L["Level"] .. " " .. mob.level end
	if mob.hp then parts[#parts + 1] = string.format(L["%s HP"], ns.FormatNumber(mob.hp)) end
	return table.concat(parts, "   ")
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
			list[#list + 1] = { itemID = itemID, rate = rate, measured = kills and kills > 0 and measured or nil, kills = kills }
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
	table.sort(list, function(a, b)
		local ra, rb = a.rate or a.measured or 0, b.rate or b.measured or 0
		return ra > rb
	end)
	return list
end

function Guide:WayButton(container, entry)
	local where = entry.id and ns.Instances[entry.id]
	if not where then return end
	local go = AceGUI:Create("Button")
	go:SetText(L["Show the way to the entrance"])
	go:SetWidth(260)
	go:SetCallback("OnClick", function()
		ns.SetWaypoint(where.zone, where.x, where.y, EntryName(entry), "guide")
		ns.Print(string.format(L["The arrow now points to %s (%s)."], EntryName(entry), ns.MapName(where.zone)))
	end)
	container:AddChild(go)
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
function Guide:ShowInstance(container, entry)
	Text(container, EntryName(entry), GameFontNormalHuge)
	local parts = {}
	if entry.min and entry.kind ~= "world" then parts[#parts + 1] = string.format(L["Levels %d-%d"], entry.min, entry.max) end
	if entry.enter and entry.kind ~= "world" then parts[#parts + 1] = string.format(L["Entry from level %d"], entry.enter) end
	if entry.size then parts[#parts + 1] = string.format(L["%d players"], entry.size) end
	local where = entry.id and ns.Instances[entry.id]
	if where then parts[#parts + 1] = ns.MapName(where.zone) end
	if entry.isNew then parts[#parts + 1] = "|cff33ccff" .. L["New in Forever"] .. "|r" end
	Text(container, table.concat(parts, "  |  "), GameFontHighlight)
	self:WayButton(container, entry)

	Heading(container, L["Bosses"])
	for _, boss in ipairs(self:Bosses(entry)) do
		if boss.type ~= "extra" then
			local count = boss.loot and #boss.loot / 2 or 0
			Text(container, string.format("%s   |cff888888%s   %d %s|r", BossLabel(boss), MobInfo(boss), count, L["items"]))
		end
	end
	if entry.collected then
		Text(container, "|cff888888" .. L["This instance is not in the built-in database yet: what you see here was recorded by the drop collector."] .. "|r")
	end
	Text(container, "\n|cff888888" .. L["Select a boss on the left for its loot and drop rates, or Trash for the loot of normal monsters."] .. "|r")
end

function Guide:ShowBoss(container, entry, boss)
	Text(container, BossLabel(boss), GameFontNormalHuge)
	Text(container, EntryName(entry), GameFontHighlight)
	local info = MobInfo(boss)
	if info ~= "" then Text(container, info, GameFontHighlightLarge) end
	if boss.kills then Text(container, string.format(L["Kills recorded: %d"], boss.kills)) end
	self:WayButton(container, entry)
	Heading(container, L["Loot"])
	local list = self:LootList(entry, boss)
	if #list == 0 then
		Text(container, "|cff888888" .. L["No loot known yet. Kill this boss with the addon on and its loot will appear here."] .. "|r")
	end
	for _, item in ipairs(list) do
		self:AddItemRow(container, item.itemID, RateText(item.rate, item.measured, item.kills))
	end
end

function Guide:ShowTrash(container, entry)
	Text(container, EntryName(entry) .. " - " .. L["Trash"], GameFontNormalHuge)
	local mobs = {}
	for _, mob in ipairs(entry.trash or {}) do mobs[#mobs + 1] = mob end
	-- Creatures only the collector saw.
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
	if #mobs == 0 then
		Text(container, "|cff888888" .. L["No trash loot recorded yet for this instance."] .. "|r")
		return
	end
	Text(container, "|cff888888" .. string.format(L["%d monsters. Items shown from the quality chosen in the options."], #mobs) .. "|r")
	local minQuality = self:Settings().minTrashQuality
	for _, mob in ipairs(mobs) do
		Heading(container, string.format("%s  |cff888888%s|r", mob.name, MobInfo(mob)))
		local shown = 0
		for _, item in ipairs(self:LootList(entry, mob)) do
			local quality = C_Item.GetItemQualityByID(item.itemID)
			if not quality or quality >= minQuality then
				self:AddItemRow(container, item.itemID, RateText(item.rate, item.measured, item.kills))
				shown = shown + 1
			end
		end
		if shown == 0 then Text(container, "|cff888888" .. L["Nothing above the chosen quality."] .. "|r") end
	end
end

function Guide:ShowWishlist(container)
	Text(container, L["Wishlist"], GameFontNormalHuge)
	Text(container, "|cff888888" .. L["Alt-click an item in the guide to add or remove it. You are alerted when it drops."] .. "|r")
	for itemID in pairs(self:Global().wishlist) do
		local src = ns.ItemDropSources(itemID)[1]
		self:AddItemRow(container, itemID, src and string.format("%s - %s  %s", src.where, src.name, src.rate and Percent(src.rate) or "") or "")
	end
end

function Guide:Select(path)
	local content = self.content
	content:ReleaseChildren()
	self.pendingRows = {}
	local key, sub = path:match("([kc]%d+)" .. SEP .. "?([^" .. SEP .. "]*)$")
	if path:find("wishlist", 1, true) then
		self:ShowWishlist(content)
	elseif key then
		local entry = self.list[key]
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
		Text(content, "\n" .. L["Bosses, health, loot and drop rates come from the Classic database (AtlasLootClassic and CMaNGOS). Rates measured in game by the addon are shown next to them. Forever may change some of them: share your data with /fc drops export."])
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
	frame:SetStatusText(L["Rates: Classic database, plus what the addon measured in game. Share yours with /fc drops export."])
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
	local found
	if instanceType == "party" or instanceType == "raid" then
		for key, entry in pairs(self.list) do
			if entry.id == instanceID and (not found or key < found) then found = key end
		end
	end
	if found then
		tree:SelectByPath(self.list[found].kind == "raid" and "raids" or "dungeons", found)
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

function Guide:GET_ITEM_INFO_RECEIVED()
	-- Item names arrive from the server after the page is drawn: fill the rows in place.
	if not self.content or not self.pendingRows or #self.pendingRows == 0 or self.renderPending then return end
	self.renderPending = true
	C_Timer.After(0.2, function()
		self.renderPending = false
		if not self.content then return end
		local still = {}
		for _, render in ipairs(self.pendingRows) do
			if not render() then still[#still + 1] = render end
		end
		self.pendingRows = still
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
