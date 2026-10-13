-- ForeverCompanion: leveling guide for your race, class and faction.
-- Built-in route of your race (Data\RoutesAuto.lua), best gear every 5 levels with where to get it
-- (Data\GearGuide.lua), leveling talents, spells learned while leveling and rotations (Data\ClassGuide.lua).
local _, ns = ...
local L = ns.L
local UI = ns.UI
local C = UI.COLORS

local Guide = ns.NewModule("ClassGuide", {
	levelUpTips = true, -- new spells and talent point in the chat when you level up
	upgradeTips = true, -- tell me when a best-in-slot item of my level can be picked up
}, {
	window = {},
})
ns.RegisterDefaults("char", "ClassGuideTold", {})   -- [itemKey] = level at which the upgrade was announced

local TABS = {
	{ key = "route", label = "Leveling route" },
	{ key = "gear", label = "Best gear" },
	{ key = "talents", label = "Talents" },
	{ key = "spells", label = "Spells" },
	{ key = "rotation", label = "Rotation" },
	{ key = "prof", label = "Professions" },
}

local SLOTS = {
	{ "head", 1, "HEADSLOT", "Head" }, { "neck", 2, "NECKSLOT", "Neck" }, { "shoulder", 3, "SHOULDERSLOT", "Shoulder" },
	{ "back", 15, "BACKSLOT", "Back" }, { "chest", 5, "CHESTSLOT", "Chest" }, { "wrist", 9, "WRISTSLOT", "Wrist" },
	{ "hands", 10, "HANDSSLOT", "Hands" }, { "waist", 6, "WAISTSLOT", "Waist" }, { "legs", 7, "LEGSSLOT", "Legs" },
	{ "feet", 8, "FEETSLOT", "Feet" }, { "finger", 11, "FINGER0SLOT", "Finger", 12 },
	{ "trinket", 13, "TRINKET0SLOT", "Trinket", 14 },
	{ "mainhand", 16, "MAINHANDSLOT", "Main Hand" }, { "offhand", 17, "SECONDARYHANDSLOT", "Off Hand" },
	{ "ranged", 18, "RANGEDSLOT", "Ranged" },
}

-- Talent trees in the game's order.
local TREES = {
	WARRIOR = { "Arms", "Fury", "Protection" },
	PALADIN = { "Holy", "Protection", "Retribution" },
	HUNTER = { "Beast Mastery", "Marksmanship", "Survival" },
	ROGUE = { "Assassination", "Combat", "Subtlety" },
	PRIEST = { "Discipline", "Holy", "Shadow" },
	SHAMAN = { "Elemental", "Enhancement", "Restoration" },
	MAGE = { "Arcane", "Fire", "Frost" },
	WARLOCK = { "Affliction", "Demonology", "Destruction" },
	DRUID = { "Balance", "Feral Combat", "Restoration" },
}

local CONDITIONS = {
	opener = "Opener", pull = "To pull", keep_up = "Keep it up", on_cooldown = "On cooldown", spam = "Spam",
	filler = "Filler", execute = "Target under 20% health", low_health = "When you are low on health",
	low_mana = "When you are low on mana", combo_5 = "At 5 combo points", proc = "When it procs",
	interrupt = "Interrupt casts", aoe = "Several enemies", before_combat = "Before the fight",
	pet_attack = "Send your pet first", finisher = "Finisher", kite = "Keep your distance",
	heal_self = "Heal yourself", drink = "Eat and drink after the fight",
}

local TIPS = {
	ammo = "Carry plenty of ammunition and use the best quiver or ammo pouch you have.",
	battle_stance = "Stay in Battle Stance while leveling: Charge, Overpower and Mortal Strike need it.",
	cat_leveling = "Level in Cat Form; switch to Bear Form when several enemies attack you.",
	conjure_food = "Conjure your own food and water to save money.",
	dead_zone = "Stay out of the dead zone: either at range or in melee, never in between.",
	feed_pet = "Keep your pet happy: feed it often so it deals full damage.",
	first_aid = "Learn First Aid and bandage between fights to cut downtime.",
	frost_aoe = "From the 30s, group several enemies, Frost Nova them and Blizzard or Cone of Cold them down.",
	life_tap = "Use Life Tap to turn health into mana, then get the health back with Drain Life.",
	multi_dot = "Spread DoTs on several enemies and let your demon tank.",
	pet_tank = "Send your pet in first and let it build threat before you shoot.",
	poisons = "Apply poisons on both weapons from level 20.",
	pull_one = "Pull one enemy at a time and avoid adds.",
	rage_dump = "Use Heroic Strike only when you have spare rage.",
	seal_judge = "Judge the Seal of the Crusader, then keep a damage Seal up and judge again on cooldown.",
	shift_heal = "Leave your form to heal yourself, then shift back.",
	soul_shards = "Keep a few Soul Shards: finish enemies with Drain Soul.",
	spirit_tap = "Spirit Tap boosts regeneration after a kill: chain pulls instead of drinking.",
	stealth_opener = "Open from Stealth when you can for a free first strike.",
	swords = "Use swords to profit from Sword Specialization; a slow main hand and a fast off hand.",
	totems_long_fights = "Drop totems only for long or group fights; they cost a lot of mana.",
	two_hander = "Use the slowest, strongest two-handed weapon you can find.",
	wand_finish = "Finish enemies with your wand to save mana.",
	weapon_imbue = "Keep a weapon imbue on your weapon: Rockbiter early, Windfury from level 30.",
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Player()
	local _, class = UnitClass("player")
	local _, race = UnitRace("player")
	local faction = UnitFactionGroup("player")
	return class, race, faction == "Alliance" and 1 or faction == "Horde" and 2 or 0, UnitLevel("player")
end

local function SpellInfo(spellID)
	if not spellID or spellID == 0 then return nil end
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellID)
		if type(info) == "table" then return info.name, info.iconID or info.originalIconID end
	end
	if GetSpellInfo then
		local name, _, icon = GetSpellInfo(spellID)
		return name, icon
	end
end

local function Known(spellID)
	if IsPlayerSpell and IsPlayerSpell(spellID) then return true end
	if IsSpellKnown and IsSpellKnown(spellID) then return true end
	return false
end

-- Racial spells (some priest spells) only for the races that get them.
local function ForMe(spell)
	if not spell[5] then return true end
	local _, race = UnitRace("player")
	return (("," .. spell[5] .. ","):find("," .. race .. ",", 1, true)) ~= nil
end

local function Data()
	local class = Player()
	return ns.ClassGuide and ns.ClassGuide[class], class
end

local function TreeName(class, tree)
	local name = TREES[class] and TREES[class][tree]
	return name and L[name] or "?"
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local sections = UI.Pool(function(parent) return UI.SectionTitle(parent, "") end)

local texts = UI.Pool(function(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.text = UI.Text(f, 13)
	f.text:SetPoint("TOPLEFT")
	f.text:SetPoint("TOPRIGHT")
	return f
end)

-- Row with an icon, a title, a detail line and a right-hand value.
local rows = UI.Pool(function(parent)
	local row = CreateFrame("Button", nil, parent)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.bg = UI.Fill(row, C.panel, "BACKGROUND")
	row.bg:SetAllPoints()
	row.mark = UI.Fill(row, C.accent, "ARTWORK")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	row.mark:SetWidth(3)
	row.icon = UI.ItemIcon(row, 34)
	row.icon:SetPoint("LEFT", 8, 0)
	row.title = UI.Text(row, 14)
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
	row.title:SetPoint("RIGHT", row, "RIGHT", -190, 0)
	row.title:SetWordWrap(false)
	row.info = UI.Text(row, 12, C.muted)
	row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
	row.info:SetPoint("RIGHT", row, "RIGHT", -190, 0)
	row.info:SetWordWrap(false)
	row.value = UI.Text(row, 13, C.text, "RIGHT")
	row.value:SetPoint("RIGHT", -12, 0)
	row.value:SetWidth(176)
	row:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(C.hover[1], C.hover[2], C.hover[3], 1)
		if self.itemID or self.spellID or self.tipTitle then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if self.itemID then GameTooltip:SetItemByID(self.itemID)
			elseif self.spellID then GameTooltip:SetSpellByID(self.spellID)
			else GameTooltip:SetText(self.tipTitle) end
			if self.hint then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(self.hint, 0.6, 0.6, 0.6, true)
			end
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function(self)
		self.bg:SetVertexColor(C.panel[1], C.panel[2], C.panel[3], 1)
		GameTooltip_Hide()
	end)
	function row:Set(opts)
		self.itemID, self.spellID, self.hint, self.tipTitle = opts.itemID, opts.spellID, opts.hint, opts.tipTitle
		self.icon:SetItem(opts.icon, opts.quality)
		self.title:SetText(opts.title or "")
		self.info:SetText(opts.info or "")
		self.value:SetText(opts.value or "")
		self.mark:SetShown(opts.marked == true)
		if opts.markColor then self.mark:SetVertexColor(opts.markColor[1], opts.markColor[2], opts.markColor[3], 1) end
		self:SetScript("OnClick", opts.onClick)
	end
	return row
end)

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
function Guide:CreateWindow()
	if self.frame then return end
	local f = UI.Window("ForeverCompanionClassGuide", L["Leveling guide"], 940, 680, self:Global().window,
		{ resizable = true, minWidth = 760, minHeight = 480 })
	self.frame = f
	f.OnResized = function() self:Render() end

	local tabs = CreateFrame("Frame", nil, f.content)
	tabs:SetPoint("TOPLEFT", 16, -12)
	tabs:SetPoint("TOPRIGHT", -16, -12)
	tabs:SetHeight(30)
	f.tabs = {}
	local prev
	for _, tab in ipairs(TABS) do
		local b = UI.Button(tabs, L[tab.label], 140, 30, "normal", function() self.tab = tab.key self.frame.scroll:ScrollToTop() self:Render() end)
		if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("LEFT") end
		if b.FitText then b:FitText(110) end
		f.tabs[tab.key] = b
		prev = b
	end

	-- Level bracket buttons of the gear page.
	f.brackets = {}
	for i, level in ipairs({ 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60 }) do
		local b = UI.Button(f.content, tostring(level), 44, 26, "ghost", function() self.bracket = level self:Render() end)
		b:SetPoint("TOPLEFT", 16 + (i - 1) * 48, -52)
		b.level = level
		f.brackets[i] = b
	end

	local scroll = UI.Scroll(f.content)
	scroll:SetPoint("TOPLEFT", 0, -52)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	f.scroll = scroll
	self.stack = UI.Stack(scroll.child, 18)
end

function Guide:Clear()
	sections:ReleaseAll()
	texts:ReleaseAll()
	rows:ReleaseAll()
	self.stack:Reset()
	self.stack:Space(10)
end

function Guide:Section(text)
	local s = sections:Acquire(self.frame.scroll.child)
	s:SetText(text)
	self.stack:Add(s, 28, 14)
	self.stack:Space(8)
end

function Guide:Text(text, size, color, gap)
	local f = texts:Acquire(self.frame.scroll.child)
	self.stack:Add(f, 10, gap or 4)
	f.text:SetFontObject(UI.Font(size or 13))
	local c = color or C.text
	f.text:SetTextColor(c[1], c[2], c[3])
	f.text:SetText(text)
	f:SetHeight(math.max(1, f.text:GetStringHeight()))
	self.stack.y = self.stack.y - 10 + f:GetHeight()
end

function Guide:Row(opts, gap)
	local row = rows:Acquire(self.frame.scroll.child)
	self.stack:Add(row, 44, gap or 4)
	row:Set(opts)
	return row
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
function Guide:Header()
	local class, race, side, level = Player()
	local data = Data()
	local raceName = UnitRace("player")
	local className = UnitClass("player")
	local parts = { UI.Colorize(raceName .. " " .. className, C.gold), string.format(L["Level %d"], level) }
	if data and data.spec then parts[#parts + 1] = L["Spec:"] .. " " .. UI.Colorize(L[data.spec] or data.spec, C.accent) end
	parts[#parts + 1] = side == 1 and L["Alliance"] or side == 2 and L["Horde"] or ""
	self:Text(table.concat(parts, "   ·   "), 15, C.text, 4)
end

-- Built-in routes of this character (faction, race and class), in level order.
function Guide:Routes()
	local Route = ns.FC:GetModule("Route", true)
	local list = {}
	for _, route in ipairs(Route and Route:AllRoutes() or {}) do
		if route.auto then list[#list + 1] = route end
	end
	return list
end

-- Every step of one route, to check it before playing it (right-click on a route).
local STEP_COLOR = {
	accept = "ffffd100", complete = "ff66ccff", turnin = "ff33ff33", ["goto"] = "ffffffff", level = "ffff9933",
	dungeon = "ffff6666", note = "ffaaaaaa", train = "ffcc99ff",
}
function Guide:PageRouteSteps(route)
	local Route = ns.FC:GetModule("Route", true)
	local state = ns.FC.db.char.Route
	local isCurrent = Route and Route.route == route
	self:Section(string.format("%s  ·  %s", route.name or route.id, string.format(L["Levels %d-%d"], route.minLevel, route.maxLevel)))
	self:Row({
		icon = "Interface\\Icons\\INV_Misc_Map_01",
		title = L["Back to the route list"],
		info = string.format(L["%d steps"], #route.steps),
		onClick = function() self.viewRoute = nil; self:Render() end,
	})
	self.stack:Space(4)
	local lines = {}
	local function flush()
		if #lines > 0 then self:Text(table.concat(lines, "\n"), 11, C.text, 1) end
		wipe(lines)
	end
	for i, step in ipairs(route.steps) do
		local kind = step[1]
		local label = Route and Route.KindLabel and Route.KindLabel(kind) or kind
		local text = string.format("|cff888888%3d|r  |c%s%s|r  %s", i, STEP_COLOR[kind] or "ffffffff", label,
			Route and Route:StepText(step, true) or "")
		if step.quest then
			local q = ns.QuestDB and ns.QuestDB[step.quest]
			if q and q[1] and q[1] > 0 then text = text .. UI.Colorize(string.format(" [%d]", q[1]), C.muted) end
			text = text .. UI.Colorize(" #" .. step.quest, C.muted)
		end
		if step.npc and (kind == "accept" or kind == "turnin") then text = text .. "  ·  " .. UI.Colorize(step.npc, C.gold) end
		local place
		if step.map and step.x then
			place = string.format("%s (%.0f, %.0f)", ns.MapName(step.map), step.x * 100, step.y * 100)
		elseif step.wx and ns.WorldPlace then
			place = ns.WorldPlace(step.cont, step.wx, step.wy)
		end
		if place then text = text .. "  ·  " .. UI.Colorize(place, C.muted) end
		if isCurrent and i < state.step then text = "|TInterface\\RaidFrame\\ReadyCheck-Ready:11|t " .. text
		elseif isCurrent and i == state.step then text = UI.Colorize("> ", C.accent) .. text end
		lines[#lines + 1] = text
		if #lines >= 20 then flush() end
	end
	flush()
end

function Guide:PageRoute()
	local Route = ns.FC:GetModule("Route", true)
	if self.viewRoute then return self:PageRouteSteps(self.viewRoute) end
	local list = self:Routes()
	local state = ns.FC.db.char.Route
	local current = Route and Route.route
	self:Section(L["Your route from 1 to 60"])
	self:Text(L["The step window follows this route on its own: it moves to the next step when you accept, finish or turn in a quest, and the arrow points to each step. Click a zone to start from there."], 12, C.muted, 2)
	self:Text(L["Right-click: see all its steps"], 12, C.muted, 2)
	if #list == 0 then
		self:Text(L["No built-in route for your race and class yet."], 13, C.muted, 10)
		return
	end
	self.stack:Space(6)
	for index, route in ipairs(list) do
		local finished = state.finished[route.id]
		local isCurrent = current == route
		local quests = 0
		for _, step in ipairs(route.steps) do if step[1] == "accept" then quests = quests + 1 end end
		local value
		if isCurrent then
			value = UI.Colorize(string.format("%d / %d", state.step, #route.steps), C.accent)
		elseif finished then
			value = UI.Colorize(L["Done"], C.good)
		else
			value = UI.Colorize(string.format(L["%d steps"], #route.steps), C.muted)
		end
		self:Row({
			icon = "Interface\\Icons\\INV_Misc_Map_01",
			title = string.format("%d. %s", index, route.name or route.id),
			info = string.format(L["Levels %d-%d"], route.minLevel, route.maxLevel) .. "  ·  " .. string.format(L["%d quests"], quests),
			value = value,
			marked = isCurrent,
			markColor = C.accent,
			hint = L["Click: follow the route from here"] .. "\n" .. L["Right-click: see all its steps"],
			onClick = function(_, button)
				if button == "RightButton" then
					self.viewRoute = route
					self:Render()
					self.frame.scroll:ScrollToTop()
					return
				end
				state.routeID, state.step = route.id, 1
				state.finished[route.id] = nil
				state.routeMode = "follow"
				if Route then
					Route:Settings().showWindow = true
					Route:Advance()
				end
				self:Render()
			end,
		})
	end
end

-- An entry of the gear lists is an itemID, or the name of a new WoW Forever item whose ID was not
-- published (details in ns.GearItems).  Such an item is found by name once the game has seen it.
local function ItemRef(key)
	local info = ns.GearItems and ns.GearItems[key]
	if type(key) == "number" then return key, info end
	if info and info.id then return info.id, info end
	if not ns.ResolveItem then return nil, info end
	local id, finfo = ns.ResolveItem(key)
	return id, info or finfo
end

local function InstanceTitle(key)
	for _, e in ipairs(ns.InstanceDB or {}) do
		if e.key == key then return ns.InstanceEntryName and ns.InstanceEntryName(e) or e.name or key, e end
	end
	return key
end

local function SourceText(key)
	local src = ns.GearSources and ns.GearSources[key]
	if not src then return nil end
	-- some items come from a different quest for the Horde
	if src.h and UnitFactionGroup("player") == "Horde" then src = src.h end
	local kind = src[1]
	if kind == "quest" then
		local q = ns.QuestDB and ns.QuestDB[src[2]]
		local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(src[2])
		if not title or ns.IsSecret(title) then title = q and q[7] or ("#" .. src[2]) end
		local where = q and ns.WorldPlace and ns.WorldPlace(q[8], q[9], q[10])
		return L["Quest:"] .. " " .. title .. (where and ("  ·  " .. where) or ""), q and { q[8], q[9], q[10], title }
	elseif kind == "fquest" then
		-- quest of a new WoW Forever dungeon: { "fquest", title, instanceKey, level, giver, questID }
		local title = src[6] and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(src[6])
		if not title or ns.IsSecret(title) then title = src[2] end
		local text = L["Quest:"] .. " " .. title .. " (" .. string.format(L["Level %d"], src[4] or 0) .. ")  ·  " .. InstanceTitle(src[3])
		if src[5] then text = text .. "  ·  " .. src[5] end
		local q = src[6] and ns.DungeonQuestInfo and ns.DungeonQuestInfo[src[6]]
		local at = q and q.giver and q.giver[8]
		if at then
			text = text .. "  ·  " .. ns.MapName(at[1])
			return text, { map = at[1], x = at[2], y = at[3], title = (q.giver[1] or "") .. " - " .. title }
		end
		return text
	elseif kind == "drop" then
		local name = InstanceTitle(src[2])
		local rate = src[4] and src[4] > 0 and string.format(" (%.1f%%)", src[4]) or ""
		local boss = src[3] == "Trash" and L["Trash mobs"] or src[3] or "?"
		return L["Drop:"] .. " " .. boss .. " - " .. name .. rate
	elseif kind == "vendor" then
		local where = src[3] and ns.WorldPlace and ns.WorldPlace(src[3], src[4], src[5])
		return L["Vendor:"] .. " " .. (src[2] or "?") .. (where and ("  ·  " .. where) or ""), src[3] and { src[3], src[4], src[5], src[2] }
	elseif kind == "rare" or kind == "mob" then
		local where = src[3] and ns.WorldPlace and ns.WorldPlace(src[3], src[4], src[5])
		return (kind == "rare" and L["Rare:"] or L["Drop:"]) .. " " .. (src[2] or "?") .. (where and ("  ·  " .. where) or ""), src[3] and { src[3], src[4], src[5], src[2] }
	elseif kind == "crafted" then
		return L["Crafted:"] .. " " .. (L[src[2]] or src[2] or "?")
	end
end

function Guide:GearRow(key, rank, slot)
	local itemID, info = ItemRef(key)
	local name, link, quality, icon
	if itemID then
		name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
		if not icon and C_Item.GetItemInfoInstant then icon = select(5, C_Item.GetItemInfoInstant(itemID)) end
		if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) self.pending = true end
	end
	if not name and info then name, quality = info.name, info.quality end
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local source, target = SourceText(key)
	local src = ns.GearSources and ns.GearSources[key]
	local equipped = itemID and GetInventoryItemID and (GetInventoryItemID("player", slot[2]) == itemID or (slot[5] and GetInventoryItemID("player", slot[5]) == itemID))
	-- rings and trinkets: the first two are the ones to wear
	local best = rank == 1 or (slot[5] and rank == 2)
	local hints = {}
	if target then hints[#hints + 1] = L["Click: point the arrow there"] end
	if src and src.new then hints[#hints + 1] = L["New in WoW Forever."] end
	if info and info.est then hints[#hints + 1] = L["Its stats are not published yet: ranked from its item level and type."] end
	if info and not itemID then hints[#hints + 1] = L["Item level"] .. " " .. tostring(info.ilvl or "?") .. "  ·  " .. (info.slot or "") .. (info.type and info.type ~= "" and (" (" .. info.type .. ")") or "") end
	local title = name and (color and color.hex and (color.hex .. name .. "|r") or name) or UI.Colorize(L["Item"] .. " #" .. tostring(key), C.muted)
	if src and src.new then title = title .. "  " .. UI.Colorize(L["New"], C.accent) end
	self:Row({
		itemID = itemID,
		tipTitle = not itemID and name or nil,
		icon = icon, quality = quality,
		title = title,
		info = source or "",
		value = (equipped and UI.Colorize(L["Equipped"], C.good) .. "  " or "") .. UI.Colorize("#" .. rank, best and C.gold or C.muted),
		marked = equipped or best,
		markColor = equipped and C.good or C.accent,
		hint = #hints > 0 and table.concat(hints, "\n") or nil,
		onClick = function()
			if IsShiftKeyDown() and link then
				local insert = ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
				if insert then insert(link) end
			elseif IsControlKeyDown() and link then
				DressUpItemLink(link)
			elseif target and target.map then
				ns.SetWaypoint(target.map, target.x, target.y, target.title, "guide")
				PlaySound(SOUNDKIT.MAP_PING or 3175)
			elseif target then
				ns.SetWorldWaypoint(target[1], target[2], target[3], target[4], "guide")
				PlaySound(SOUNDKIT.MAP_PING or 3175)
			end
		end,
	}, 2)
end

---------------------------------------------------------------------------
-- Upgrades to pick up now: for each slot, the best item of the gear list of your level that you can
-- already use and do not wear (rings and trinkets: better than one of the two you wear).
---------------------------------------------------------------------------
local function Worn(slot)
	local a = GetInventoryItemID and GetInventoryItemID("player", slot[2])
	local b = slot[5] and GetInventoryItemID and GetInventoryItemID("player", slot[5])
	return a, b
end

local function QuestDone(src)
	local id = src and (src[1] == "quest" and src[2] or src[1] == "fquest" and src[6])
	return id and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)
end

function ns.GearUpgrades()
	local class, _, side, level = Player()
	local gear = ns.GearGuide and ns.GearGuide[class]
	gear = gear and gear[side]
	if not gear then return {} end
	local bracket = math.max(10, math.min(60, math.ceil(level / 5) * 5))
	local set = gear[bracket] or gear[math.max(10, bracket - 5)]
	if not set then return {} end
	local out = {}
	for _, slot in ipairs(SLOTS) do
		local list = set[slot[1]]
		if type(list) ~= "table" then list = { list } end
		local a, b = Worn(slot)
		-- rank of what is worn (rings / trinkets: the weaker of the two)
		local wornRank = {}
		for rank, key in ipairs(list) do
			local id = ItemRef(key)
			if id and (id == a or id == b) then wornRank[#wornRank + 1] = rank end
		end
		local limit = #list + 1
		if slot[5] then
			if #wornRank >= 2 then limit = math.max(wornRank[1], wornRank[2]) end
		elseif wornRank[1] then
			limit = wornRank[1]
		end
		for rank, key in ipairs(list) do
			if rank >= limit then break end
			local id, info = ItemRef(key)
			local src = ns.GearSources and ns.GearSources[key]
			if src and src.h and side == 2 then src = src.h end
			if id and id ~= a and id ~= b and not QuestDone(src) then
				local name, link, quality, _, minLevel = C_Item.GetItemInfo(id)
				if not name and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
				minLevel = minLevel or (info and info.req) or 0
				if minLevel <= level then
					local text, target = SourceText(key)
					local bags = C_Item.GetItemCount and C_Item.GetItemCount(id) or 0
					out[#out + 1] = { key = key, id = id, link = link, name = name or (info and info.name), quality = quality,
						slot = _G[slot[3]] or L[slot[4]], rank = rank, source = text, target = target, inBags = bags > 0 }
					break
				end
			end
		end
	end
	return out
end

-- Points the arrow at the place an upgrade comes from (quest giver, vendor, Forever dungeon quest).
function ns.GoToUpgrade(u)
	local t = u and u.target
	if not t then return false end
	if t.map then ns.SetWaypoint(t.map, t.x, t.y, t.title, "guide")
	else ns.SetWorldWaypoint(t[1], t[2], t[3], t[4], "guide") end
	return true
end

function Guide:AnnounceUpgrades()
	if not self:Settings().upgradeTips then return end
	local told = ns.FC.db.char.ClassGuideTold
	local level = UnitLevel("player")
	local fresh = {}
	for _, u in ipairs(ns.GearUpgrades()) do
		if not told[u.key] and u.name then
			told[u.key] = level
			fresh[#fresh + 1] = u
		end
	end
	if #fresh == 0 then return end
	ns.Print(L["Gear upgrade for your level:"])
	for i = 1, math.min(4, #fresh) do
		local u = fresh[i]
		local what = u.inBags and UI.Colorize(L["in your bags: equip it"], C.good) or (u.source or "")
		ns.Print(string.format("  %s (%s) - %s", u.link or u.name, u.slot, what))
	end
	if #fresh > 4 then ns.Print("  " .. string.format(L["and %d more: /fc lvl gear"], #fresh - 4)) end
	if ns.Route and ns.Route.Refresh then ns.Route:Refresh() end
end

function Guide:PageGear()
	local class, _, side, level = Player()
	local gear = ns.GearGuide and ns.GearGuide[class]
	gear = gear and gear[side]
	if not self.bracket then self.bracket = math.max(10, math.min(60, math.floor(level / 5) * 5)) end
	self.stack:Space(34)
	self:Section(string.format(L["Best gear at level %d"], self.bracket))
	local set = gear and gear[self.bracket]
	if not set then
		self:Text(L["No gear list for your class yet."], 13, C.muted, 6)
		return
	end
	self:Text(L["The 5 best items for each slot that you can get by this level, best first, with where to get them: quests, dungeon drops (new WoW Forever dungeons included), vendors and crafting. Rings and trinkets: wear the first two. Click an item with a quest or a vendor to point the arrow there. Shift-click: link in chat, Ctrl-click: try on."], 12, C.muted, 2)
	for _, slot in ipairs(SLOTS) do
		local list = set[slot[1]]
		if type(list) ~= "table" then list = { list } end
		if list[1] then
			self:Text(UI.Colorize(_G[slot[3]] or L[slot[4]], C.gold), 13, C.text, 10)
			for rank, key in ipairs(list) do self:GearRow(key, rank, slot) end
		end
	end
end

function Guide:PageTalents()
	local data, class = Data()
	local level = UnitLevel("player")
	if not (data and data.talents) then
		self:Section(L["Talents"])
		self:Text(L["No talent build for your class yet."], 13, C.muted, 6)
		return
	end
	-- points per tree at your level and at 60
	local now, total, ranks = { 0, 0, 0 }, { 0, 0, 0 }, {}
	for _, t in ipairs(data.talents) do
		total[t[2]] = total[t[2]] + 1
		if t[1] <= level then now[t[2]] = now[t[2]] + 1 end
	end
	self:Section(string.format(L["Leveling build: %s"], L[data.spec] or data.spec))
	self:Text(string.format("%s %d/%d/%d   ·   %s %d/%d/%d", L["At your level:"], now[1], now[2], now[3], L["At 60:"], total[1], total[2], total[3]), 13, C.text, 2)
	self:Text(string.format("%s / %s / %s", TreeName(class, 1), TreeName(class, 2), TreeName(class, 3)), 12, C.muted, 2)
	self.stack:Space(6)
	for _, t in ipairs(data.talents) do
		ranks[t[3]] = (ranks[t[3]] or 0) + 1
		local name, icon = SpellInfo(t[4])
		local isNext = t[1] == level or (t[1] > level and not self.nextMarked)
		local done = t[1] < level
		local color = done and C.muted or t[1] == level and C.gold or C.text
		self:Row({
			spellID = t[4] ~= 0 and t[4] or nil,
			icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
			title = UI.Colorize((name or t[3]) .. "  " .. string.format(L["rank %d"], ranks[t[3]]), color),
			info = TreeName(class, t[2]),
			value = UI.Colorize(string.format(L["Level %d"], t[1]), t[1] <= level and C.good or C.muted),
			marked = t[1] == level,
			markColor = C.gold,
		}, 2)
	end
end

function Guide:PageSpells()
	local data = Data()
	local level = UnitLevel("player")
	if not (data and data.spells) then
		self:Section(L["Spells"])
		self:Text(L["No spell list for your class yet."], 13, C.muted, 6)
		return
	end
	local missing, cost = 0, 0
	for _, s in ipairs(data.spells) do
		if ForMe(s) and s[1] <= level and not Known(s[2]) then missing = missing + 1 cost = cost + (s[4] or 0) end
	end
	self:Section(L["Spells learned while leveling"])
	if missing > 0 then
		self:Text(string.format(L["%d spells to learn at your trainer now, for %s."], missing, ns.FormatMoney(cost)), 14, C.gold, 2)
	else
		self:Text(L["You know every spell of your level."], 13, C.good, 2)
	end
	local lastLevel
	for _, s in ipairs(data.spells) do
		if ForMe(s) and (s[1] >= level - 1 or not Known(s[2])) then
			if s[1] ~= lastLevel then
				lastLevel = s[1]
				self:Text(string.format(L["Level %d"], s[1]), 13, s[1] <= level and C.accent or C.muted, 12)
			end
			local name, icon = SpellInfo(s[2])
			local known = Known(s[2])
			self:Row({
				spellID = s[2],
				icon = icon,
				title = (name or ("#" .. s[2])) .. ((s[3] or 0) > 0 and UI.Colorize("  " .. string.format(L["rank %d"], s[3]), C.muted) or ""),
				info = known and UI.Colorize(L["Known"], C.good) or (s[1] <= level and UI.Colorize(L["Learn it now"], C.gold) or ""),
				value = (s[4] or 0) > 0 and ns.FormatMoney(s[4]) or "",
				marked = not known and s[1] <= level,
				markColor = C.gold,
			}, 2)
		end
	end
end

function Guide:PageRotation()
	local data = Data()
	local level = UnitLevel("player")
	if not (data and data.rotations) then
		self:Section(L["Rotation"])
		self:Text(L["No rotation for your class yet."], 13, C.muted, 6)
		return
	end
	local current, nextBand
	for _, band in ipairs(data.rotations) do
		if level >= band[1] and level <= band[2] then current = band
		elseif band[1] > level and not nextBand then nextBand = band end
	end
	local function Show(band, title)
		self:Section(title .. "  " .. UI.Colorize(string.format(L["Levels %d-%d"], band[1], band[2]), C.muted))
		-- the steps you can use now (all of them for a band you have not reached yet)
		local steps, anyKnown = {}, false
		for _, step in ipairs(band[3]) do if Known(step[1]) then anyKnown = true end end
		for _, step in ipairs(band[3]) do
			if not anyKnown or band[1] > level or Known(step[1]) then steps[#steps + 1] = step end
		end
		for i, step in ipairs(steps) do
			local name, icon = SpellInfo(step[1])
			self:Row({
				spellID = step[1],
				icon = icon,
				title = UI.Colorize(i .. ".  ", C.muted) .. (name or ("#" .. step[1])),
				info = L[CONDITIONS[step[2]] or step[2]] or step[2],
				value = Known(step[1]) and "" or UI.Colorize(L["Not learned yet"], C.muted),
			}, 3)
		end
	end
	if current then Show(current, L["Your rotation now"]) end
	if nextBand then Show(nextBand, L["Next"]) end
	if data.tips and #data.tips > 0 then
		self:Section(L["Tips"])
		for _, key in ipairs(data.tips) do self:Text("•  " .. (TIPS[key] and L[TIPS[key]] or key), 13, C.text, 4) end
	end
end

function Guide:Render()
	if not (self.frame and self.frame:IsShown()) then return end
	self.tab = self.tab or "route"
	for key, b in pairs(self.frame.tabs) do
		local active = key == self.tab
		b:SetBackdropBorderColor(active and C.accent[1] or C.border[1], active and C.accent[2] or C.border[2], active and C.accent[3] or C.border[3], 1)
		b.label:SetTextColor(active and 1 or C.muted[1], active and 1 or C.muted[2], active and 1 or C.muted[3])
	end
	for _, b in ipairs(self.frame.brackets) do
		b:SetShown(self.tab == "gear")
		local active = b.level == self.bracket
		b:SetBackdropBorderColor(active and C.accent[1] or C.border[1], active and C.accent[2] or C.border[2], active and C.accent[3] or C.border[3], 1)
	end
	self:Clear()
	self.pending = false
	self:Header()
	if self.tab == "gear" then
		self.frame.brackets[1]:ClearAllPoints()
		for i, b in ipairs(self.frame.brackets) do
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", self.frame.scroll.child, "TOPLEFT", 18 + (i - 1) * 48, -(self.stack.y + 10))
		end
		self:PageGear()
	elseif self.tab == "talents" then self:PageTalents()
	elseif self.tab == "spells" then self:PageSpells()
	elseif self.tab == "rotation" then self:PageRotation()
	elseif self.tab == "prof" and ns.ProfessionGuide then ns.ProfessionGuide.Page(self)
	else self:PageRoute() end
	if self.tab ~= "prof" and ns.ProfessionGuide then ns.ProfessionGuide.HideButtons(self) end
	self.frame.scroll:SetContentHeight(self.stack.y + 24)
	self.frame.subtitle:SetText("")
end

function Guide:Toggle(tab)
	self:CreateWindow()
	if self.frame:IsShown() and not tab then self.frame:Hide() return end
	if tab then self.tab = tab end
	for _, b in ipairs(self.frame.brackets) do b:SetParent(self.frame.scroll.child) end
	self.frame:Show()
	self.frame.scroll:ScrollToTop()
	self:Render()
end

function ns.ToggleClassGuide(tab)
	if Guide:IsEnabled() then Guide:Toggle(tab) else ns.OpenOptions() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Guide:PLAYER_LEVEL_UP(_, level)
	if not self:Settings().levelUpTips then return end
	local data = Data()
	if not data then return end
	local names, cost = {}, 0
	for _, s in ipairs(data.spells or {}) do
		if s[1] == level and ForMe(s) then
			names[#names + 1] = SpellInfo(s[2]) or ("#" .. s[2])
			cost = cost + (s[4] or 0)
		end
	end
	if #names > 0 then
		ns.Print(string.format(L["New spells at your trainer: %s (%s)."], table.concat(names, ", "), ns.FormatMoney(cost)))
	end
	for _, t in ipairs(data.talents or {}) do
		if t[1] == level then
			ns.Print(string.format(L["Talent point: %s (%s)."], SpellInfo(t[4]) or t[3], TreeName(select(2, Data()), t[2])))
		end
	end
	if self.frame and self.frame:IsShown() then C_Timer.After(1, function() self:Render() end) end
	C_Timer.After(3, function() self:AnnounceUpgrades() end)
end

function Guide:GET_ITEM_INFO_RECEIVED()
	if not (self.frame and self.frame:IsShown() and self.pending) or self.renderPending then return end
	self.renderPending = true
	C_Timer.After(0.3, function()
		self.renderPending = false
		self:Render()
	end)
end

function Guide:OnEnable()
	self:RegisterEvent("PLAYER_LEVEL_UP")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
		if ns.Route and ns.Route.Refresh then C_Timer.After(0.5, function() ns.Route:Refresh() end) end
	end)
	-- first check a little after login, once item data had time to load
	C_Timer.After(15, function() self:AnnounceUpgrades() end)
	self:RegisterEvent("SPELLS_CHANGED", function() if self.frame and self.frame:IsShown() and (self.tab == "spells" or self.tab == "rotation") then self:Render() end end)
end

function Guide:OnDisable()
	if self.frame then self.frame:Hide() end
end

ns.RegisterCommand("lvl", L["leveling guide: route | gear | talents | spells | rotation | prof"], function(rest)
	local tab = (rest or ""):match("^(%S+)")
	ns.ToggleClassGuide(tab and tab:lower() or nil)
end)

function Guide:GetOptions()
	local get, set = ns.ProfileAccessors("ClassGuide")
	return {
		get = get, set = set,
		args = {
			open = { type = "execute", order = 1, name = L["Open the leveling guide"], func = function() self:Toggle() end },
			levelUpTips = { type = "toggle", order = 2, width = "full", name = L["When I level up, list the new spells and the talent to take"] },
			upgradeTips = { type = "toggle", order = 3, width = "full", name = L["Tell me when a best-in-slot item of my level can be picked up (chat and route window)"] },
		},
	}
end
