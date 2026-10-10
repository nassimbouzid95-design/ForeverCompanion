-- ForeverCompanion: Hardcore survival. Zone and target danger warnings, a danger badge on the target
-- frame, a survival panel, a pre-pull checklist when entering a dungeon and a survival window.
-- Works out of combat only (WoW Forever does not let addons read combat). Builds on Safety: the death
-- log, durability/bag warnings and nameplate alerts stay there.
local _, ns = ...
local L = ns.L
local UI = ns.UI
local C = UI.COLORS

local Hardcore = ns.NewModule("Hardcore", {
	sound = true,
	bannerDuration = 4,       -- seconds the banner stays fully visible
	zoneWarn = true,
	zoneLevelGap = 2,         -- warn when the zone minimum is above your level + this
	hostileZoneWarn = true,
	targetWarn = true,
	targetLevelGap = 4,       -- warn when the target is this many levels above you (or more)
	targetWarnElite = true,
	targetWarnSkull = true,
	targetBadge = true,
	prepull = true,
	prepullBanner = true,
	prepullDurability = 50,   -- percent
	checkPotions = true,
	checkBandages = true,
	checkFood = true,
	checkDrinks = true,
	checkHearth = true,
	requestPlayed = true,
	panel = { shown = false, locked = false },
}, {
	window = {},
})

ns.RegisterDefaults("char", "Hardcore", {
	deaths = 0,
	log = {},               -- { time, level, zone, subzone, played, aliveFor }
	lastDeathPlayed = nil,  -- /played seconds at the last death
	lastDeathTime = nil,    -- time() of the last death
	playedAtLogout = nil,   -- estimated /played total saved at logout
})

local SESSION_START = GetTime()
local HEARTHSTONE = 6948

---------------------------------------------------------------------------
-- Item lists (Classic item IDs). Anything not listed is still counted when the client reports the
-- item as Food & Drink or Bandage.
---------------------------------------------------------------------------
local function Set(list)
	local t = {}
	for _, id in ipairs(list) do t[id] = true end
	return t
end

local POTIONS = Set({
	118, 858, 4596, 929, 1710, 3928, 13446, 18839, 17348, 17349, -- healing potions and draughts
	11951, 11952,                                                -- Whipper Root Tuber, Night Dragon's Breath
	5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009,  -- healthstones
	5510, 19010, 19011, 9421, 19012, 19013,
})

local BANDAGES = Set({
	1251, 2581, 3530, 3531, 6450, 6451, 8544, 8545, 14529, 14530,
	19066, 19067, 19068, 20065, 20066, 20067, 20232, 20234, 20235, 20237, 20243, 20244,
})

local FOOD = Set({
	4540, 4541, 4542, 4544, 4601, 8950,                 -- bread
	117, 2287, 3770, 3771, 4599, 8952,                  -- meat
	414, 422, 1707, 3927, 8932,                         -- cheese
	4536, 4537, 4538, 4539, 4602, 8953,                 -- fruit
	4604, 4605, 4606, 4607, 4608, 8948,                 -- mushrooms
	787, 4592, 4593, 4594, 21552, 8957, 5095, 6290, 6887, 13930, 13933, 13934, 13935, -- fish
	724, 2680, 2683, 2684, 2687, 3220, 3662, 3726, 3727, 3728, 5472, 12209, 12210,     -- cooking
	12212, 12213, 12215, 12216, 13851, 18045, 20452, 21023,
	1113, 1114, 1487, 5349, 8075, 8076, 22895,          -- conjured food
	13724, 19301,                                       -- Enriched Manna Biscuit, Alterac Manna Biscuit
})

local DRINKS = Set({
	159, 1179, 1205, 1708, 1645, 8766, 19300,           -- vendor water and juices
	5350, 2288, 2136, 3772, 8077, 8078, 8079,           -- conjured water
	13724, 19301,
})

local CONSUMABLE_CLASS, FOOD_SUBCLASS, BANDAGE_SUBCLASS = 0, 5, 7

local function ItemCount(itemID)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(itemID) or 0 end
	if GetItemCount then return GetItemCount(itemID) or 0 end
	return 0
end

-- Counts the survival consumables in the bags: { potions, bandages, food, drinks }.
function Hardcore:CountSupplies()
	local counts = { potions = 0, bandages = 0, food = 0, drinks = 0 }
	if not (C_Container and C_Container.GetContainerNumSlots) then return counts end
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and not ns.IsSecret(id) then
				local n = info.stackCount or 1
				local classID, subClassID
				if C_Item and C_Item.GetItemInfoInstant then
					classID, subClassID = select(6, C_Item.GetItemInfoInstant(id))
				end
				if POTIONS[id] then counts.potions = counts.potions + n end
				if BANDAGES[id] or (classID == CONSUMABLE_CLASS and subClassID == BANDAGE_SUBCLASS) then
					counts.bandages = counts.bandages + n
				end
				if DRINKS[id] then counts.drinks = counts.drinks + n end
				if FOOD[id] or (classID == CONSUMABLE_CLASS and subClassID == FOOD_SUBCLASS and not DRINKS[id]) then
					counts.food = counts.food + n
				end
			end
		end
	end
	return counts
end

-- Hearthstone state: "none", "ready" or "cooldown" plus the seconds left.
function Hardcore:HearthState()
	if ItemCount(HEARTHSTONE) == 0 then return "none" end
	local getCooldown = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
	if not getCooldown then return "ready" end
	local start, duration = getCooldown(HEARTHSTONE)
	if ns.AnySecret(start, duration) or not start or not duration then return "ready" end
	local left = start + duration - GetTime()
	if duration > 1.5 and left > 0 then return "cooldown", left end
	return "ready"
end

function Hardcore:HearthText()
	local state, left = self:HearthState()
	if state == "none" then return UI.Colorize(L["No hearthstone in your bags"], C.bad) end
	if state == "cooldown" then return UI.Colorize(string.format(L["Hearthstone: %s"], ns.FormatDuration(left)), C.warn) end
	return UI.Colorize(L["Hearthstone ready"], C.good)
end

local function LowestDurability()
	if ns.LowestDurability then return ns.LowestDurability() end
	local lowest = 1
	for slot = 1, 19 do
		local current, max = GetInventoryItemDurability(slot)
		if current and max and max > 0 then lowest = math.min(lowest, current / max) end
	end
	return lowest
end

---------------------------------------------------------------------------
-- Danger rating of a unit (Trivial, Easy, Fair, Hard, Deadly)
---------------------------------------------------------------------------
local RATINGS = {
	{ key = "trivial", label = L["Trivial"], color = { 0.6, 0.6, 0.6, 1 } },
	{ key = "easy", label = L["Easy"], color = C.good },
	{ key = "fair", label = L["Fair"], color = C.warn },
	{ key = "hard", label = L["Hard"], color = { 1, 0.5, 0.2, 1 } },
	{ key = "deadly", label = L["Deadly"], color = C.bad },
}

-- Highest level that gives no XP (grey), Classic formula.
local function GrayLevel(level)
	if level <= 5 then return 0 end
	if level <= 39 then return level - math.floor(level / 10) - 5 end
	if level <= 59 then return level - math.floor(level / 5) - 1 end
	return level - 9
end

-- Returns rating (from RATINGS), level, classification; nil when the unit cannot be read.
function ns.HardcoreDanger(unit)
	if not UnitExists(unit) then return nil end
	local level, classification = UnitLevel(unit), UnitClassification(unit)
	local myLevel = UnitLevel("player")
	if ns.AnySecret(level, classification, myLevel) or not level then return nil end
	local elite = classification == "elite" or classification == "rareelite"
	if level == -1 or classification == "worldboss" then return RATINGS[5], level, classification end
	if not elite and level <= GrayLevel(myLevel) then return RATINGS[1], level, classification end
	local diff = level + (elite and 3 or 0) - myLevel
	local index = diff >= 5 and 5 or diff >= 3 and 4 or diff >= -2 and 3 or 2
	return RATINGS[index], level, classification
end

---------------------------------------------------------------------------
-- Banner: big centered warning that fades in and out.
---------------------------------------------------------------------------
local FADE_IN, FADE_OUT = 0.25, 0.8

function Hardcore:CreateBanner()
	if self.banner then return self.banner end
	local f = CreateFrame("Frame", "ForeverCompanionHardcoreBanner", UIParent, "BackdropTemplate")
	f:SetFrameStrata("HIGH")
	f:SetSize(560, 78)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 210)
	f:EnableMouse(false)
	UI.Backdrop(f, { 0.16, 0.03, 0.03, 0.92 }, C.bad)
	local glow = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	glow:SetPoint("TOPLEFT", 1, -1)
	glow:SetPoint("BOTTOMRIGHT", -1, 1)
	UI.Gradient(glow, { 0.35, 0.06, 0.05, 0.85 }, { 0.10, 0.02, 0.02, 0.85 })
	f.glow = glow
	f.stripe = UI.Fill(f, C.bad, "ARTWORK")
	f.stripe:SetPoint("TOPLEFT", 1, -1)
	f.stripe:SetPoint("BOTTOMLEFT", 1, 1)
	f.stripe:SetWidth(4)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
	f.icon:SetSize(44, 44)
	f.icon:SetPoint("LEFT", 18, 0)
	f.title = UI.Text(f, 22, C.bad, "CENTER")
	f.title:SetFontObject(UI.Font(22, "OUTLINE"))
	f.title:SetPoint("TOPLEFT", 70, -14)
	f.title:SetPoint("TOPRIGHT", -20, -14)
	f.title:SetWordWrap(false)
	f.sub = UI.Text(f, 14, C.text, "CENTER")
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
	f.sub:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -6)
	f:SetScript("OnUpdate", function(frame, elapsed)
		frame.t = (frame.t or 0) + elapsed
		local hold = frame.hold or 4
		if frame.t < FADE_IN then
			frame:SetAlpha(frame.t / FADE_IN)
		elseif frame.t < FADE_IN + hold then
			frame:SetAlpha(1)
		elseif frame.t < FADE_IN + hold + FADE_OUT then
			frame:SetAlpha(1 - (frame.t - FADE_IN - hold) / FADE_OUT)
		else
			frame:Hide()
		end
	end)
	f:Hide()
	self.banner = f
	return f
end

-- color: C.bad (danger, default) or C.warn (checklist). sound: SOUNDKIT id or false.
function Hardcore:ShowBanner(title, sub, color, sound)
	local f = self:CreateBanner()
	color = color or C.bad
	f.title:SetTextColor(color[1], color[2], color[3])
	f.stripe:SetVertexColor(color[1], color[2], color[3])
	f:SetBackdropBorderColor(color[1], color[2], color[3], 1)
	f.title:SetText(title or "")
	f.sub:SetText(sub or "")
	f:SetHeight((sub and sub ~= "") and math.max(78, f.sub:GetStringHeight() + 52) or 56)
	f.hold = self:Settings().bannerDuration or 4
	f.t = 0
	f:SetAlpha(0)
	f:Show()
	if sound ~= false and self:Settings().sound then
		PlaySound(sound or SOUNDKIT.RAID_WARNING or 8959)
	end
end

---------------------------------------------------------------------------
-- Played time and deaths
---------------------------------------------------------------------------
local function Char()
	return ns.FC.db.char.Hardcore
end

function Hardcore:PlayedNow()
	if self.playedBase then return self.playedBase.total + (GetTime() - self.playedBase.at) end
end

-- Seconds survived since the last death (played time), and whether it is played or real time.
function Hardcore:AliveFor()
	local c = Char()
	local played = self:PlayedNow()
	if played and (c.lastDeathPlayed or not c.lastDeathTime) then
		return math.max(0, played - (c.lastDeathPlayed or 0)), true
	end
	if c.lastDeathTime then return time() - c.lastDeathTime, false end
end

-- /played without the chat message: the chat frames stop listening for our own request only.
-- When they cannot be muted, the request is skipped and the panel waits for a manual /played.
function Hardcore:RequestPlayed()
	if not self:Settings().requestPlayed or self.playedRequested or self.playedPending then return end
	if not RequestTimePlayed or InCombatLockdown() then return end
	local muted = {}
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local cf = _G["ChatFrame" .. i]
		if cf and cf.IsEventRegistered and cf:IsEventRegistered("TIME_PLAYED_MSG") then
			if pcall(cf.UnregisterEvent, cf, "TIME_PLAYED_MSG") then
				muted[#muted + 1] = cf
			else
				self.muted = muted
				self:RestorePlayedChat()
				return
			end
		end
	end
	if #muted == 0 then return end
	self.muted = muted
	self.playedPending = true
	self.playedRequested = true
	RequestTimePlayed()
	self.restoreTimer = self:ScheduleTimer("RestorePlayedChat", 5)
end

function Hardcore:RestorePlayedChat()
	self.playedPending = false
	if self.restoreTimer then self:CancelTimer(self.restoreTimer) self.restoreTimer = nil end
	for _, cf in ipairs(self.muted or {}) do pcall(cf.RegisterEvent, cf, "TIME_PLAYED_MSG") end
	self.muted = nil
end

function Hardcore:TIME_PLAYED_MSG(_, total)
	if ns.IsSecret(total) or type(total) ~= "number" then return end
	self.playedBase = { total = total, at = GetTime() }
	-- A death recorded before the played time was known: place it now.
	if self.pendingDeath then
		local entry, at = self.pendingDeath.entry, self.pendingDeath.at
		entry.played = total - (GetTime() - at)
		local c = Char()
		if c.lastDeathTime == entry.time then c.lastDeathPlayed = entry.played end
		self.pendingDeath = nil
	end
	if self.playedPending then
		-- Let the event finish its dispatch before the chat frames listen again.
		C_Timer.After(0.5, function() self:RestorePlayedChat() end)
	end
	self:UpdatePanel()
	self:RenderWindow()
end

function Hardcore:PLAYER_DEAD()
	local c = Char()
	local played = self:PlayedNow()
	local entry = {
		time = time(), level = UnitLevel("player"),
		zone = GetRealZoneText(), subzone = GetSubZoneText(),
		played = played,
		aliveFor = played and c.lastDeathPlayed and (played - c.lastDeathPlayed) or nil,
	}
	if ns.IsSecret(entry.level) then entry.level = nil end
	c.deaths = (c.deaths or 0) + 1
	c.lastDeathTime = entry.time
	c.lastDeathPlayed = played
	table.insert(c.log, 1, entry)
	while #c.log > 100 do table.remove(c.log) end
	if not played then self.pendingDeath = { entry = entry, at = GetTime() } end
	self:UpdatePanel()
	self:RenderWindow()
end

function Hardcore:PLAYER_LOGOUT()
	Char().playedAtLogout = self:PlayedNow()
end

-- Deaths of this character: our own log, completed with Safety's (killer, older deaths).
function Hardcore:DeathHistory()
	local rows = {}
	for _, d in ipairs(Char().log) do
		rows[#rows + 1] = { time = d.time, level = d.level, zone = d.zone, subzone = d.subzone, aliveFor = d.aliveFor }
	end
	local Safety = ns.FC:GetModule("Safety", true)
	local log = Safety and ns.FC.db.global.Safety and ns.FC.db.global.Safety.deaths
	if log then
		local me = ns.PlayerKey()
		for _, s in ipairs(log) do
			if s.char == me and s.time then
				local match
				for _, r in ipairs(rows) do
					if r.time and math.abs(r.time - s.time) <= 5 then match = r break end
				end
				if match then
					match.killer = s.killer
					match.subzone = match.subzone or s.subzone
				else
					rows[#rows + 1] = { time = s.time, level = s.level, zone = s.zone, subzone = s.subzone, killer = s.killer }
				end
			end
		end
	end
	table.sort(rows, function(a, b) return (a.time or 0) > (b.time or 0) end)
	return rows
end

---------------------------------------------------------------------------
-- Zone danger
---------------------------------------------------------------------------
function Hardcore:CheckZone()
	if IsInInstance() then return end
	local s = self:Settings()
	if not (s.zoneWarn or s.hostileZoneWarn) then return end
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if not mapID or ns.IsSecret(mapID) then return end
	if not ns.ZoneLevelInfo then return end
	local info, zoneID = ns.ZoneLevelInfo(mapID)
	if not info then return end
	-- Crossing a border back and forth only warns once a minute.
	if self.lastZoneWarn == zoneID and GetTime() - (self.lastZoneWarnAt or 0) < 60 then return end
	local level = UnitLevel("player")
	if ns.IsSecret(level) then return end
	local name = ns.MapName(zoneID)
	if s.zoneWarn and info[1] > level + s.zoneLevelGap then
		self.lastZoneWarn, self.lastZoneWarnAt = zoneID, GetTime()
		self:ShowBanner(string.format(L["Danger: %s is level %d-%d"], name, info[1], info[2]),
			string.format(L["You are level %d. Stay on the roads and avoid elites."], level))
		return
	end
	local faction = UnitFactionGroup("player")
	if s.hostileZoneWarn and info.faction and faction and info.faction ~= faction and faction ~= "Neutral" then
		self.lastZoneWarn, self.lastZoneWarnAt = zoneID, GetTime()
		self:ShowBanner(string.format(L["Hostile territory: %s"], name),
			L["Enemy guards and players may attack you here."])
	end
end

---------------------------------------------------------------------------
-- Target danger: banner and badge
---------------------------------------------------------------------------
function Hardcore:CreateBadge()
	if self.badge then return self.badge end
	if not TargetFrame then return nil end
	local badge = UI.Chip(TargetFrame, 11)
	badge:SetFrameStrata(TargetFrame:GetFrameStrata() or "MEDIUM")
	badge:SetFrameLevel((TargetFrame:GetFrameLevel() or 1) + 10)
	badge:SetPoint("BOTTOM", TargetFrame, "TOP", -20, -6)
	badge:Hide()
	self.badge = badge
	return badge
end

function Hardcore:UpdateBadge(rating)
	if not self:Settings().targetBadge or not rating then
		if self.badge then self.badge:Hide() end
		return
	end
	local badge = self:CreateBadge()
	if not badge then return end
	badge:Set(rating.label, rating.color)
	badge:Show()
end

function Hardcore:CheckTarget()
	if InCombatLockdown() or not UnitExists("target") then
		self:UpdateBadge(nil)
		return
	end
	if not UnitCanAttack("player", "target") or UnitIsDead("target") then
		self:UpdateBadge(nil)
		return
	end
	local rating, level, classification = ns.HardcoreDanger("target")
	self:UpdateBadge(rating)
	if not rating then return end

	local s = self:Settings()
	if not s.targetWarn or IsInInstance() then return end
	local name, myLevel = UnitName("target"), UnitLevel("player")
	if ns.AnySecret(name, myLevel) or not name then return end
	local guid = UnitGUID("target")
	local key = (guid and not ns.IsSecret(guid)) and guid or (name .. level)
	if self.warnedTargets[key] then return end

	local reason
	if level == -1 or classification == "worldboss" then
		if s.targetWarnSkull then reason = L["Skull level: far too strong for you."] end
	elseif (classification == "elite" or classification == "rareelite") and s.targetWarnElite and rating.key ~= "trivial" then
		reason = string.format(L["Elite, level %d: only pull it with a group."], level)
	elseif level - myLevel >= s.targetLevelGap then
		reason = string.format(L["Level %d: %d levels above you."], level, level - myLevel)
	end
	if reason then
		self.warnedTargets[key] = true
		self:ShowBanner(string.format(L["Danger: %s"], name), reason)
	end
end

function Hardcore:PLAYER_TARGET_CHANGED()
	self:CheckTarget()
end

---------------------------------------------------------------------------
-- Pre-pull checklist
---------------------------------------------------------------------------
local MANA_LESS = { WARRIOR = true, ROGUE = true }

-- Returns the list of problems and the supply counts.
function Hardcore:PrepullProblems()
	local s = self:Settings()
	local problems = {}
	local durability = math.floor(LowestDurability() * 100)
	if durability < s.prepullDurability then
		problems[#problems + 1] = string.format(L["Durability %d%%: repair first"], durability)
	end
	local counts = self:CountSupplies()
	if s.checkPotions and counts.potions == 0 then problems[#problems + 1] = L["No healing potion or healthstone"] end
	if s.checkBandages and counts.bandages == 0 then problems[#problems + 1] = L["No bandages"] end
	if s.checkFood and counts.food == 0 then problems[#problems + 1] = L["No food"] end
	local _, class = UnitClass("player")
	if s.checkDrinks and not MANA_LESS[class] and counts.drinks == 0 then problems[#problems + 1] = L["No drinks"] end
	if s.checkHearth then
		local state, left = self:HearthState()
		if state == "none" then
			problems[#problems + 1] = L["No hearthstone in your bags"]
		elseif state == "cooldown" then
			problems[#problems + 1] = string.format(L["Hearthstone on cooldown (%s)"], ns.FormatDuration(left))
		end
	end
	return problems, counts
end

function Hardcore:RunPrepull(where)
	if InCombatLockdown() then return end
	local problems, counts = self:PrepullProblems()
	where = where or GetRealZoneText() or ""
	if #problems == 0 then
		ns.Print(UI.Colorize(string.format(L["Pre-pull check: ready (%d potions, %d bandages, %d food)."],
			counts.potions, counts.bandages, counts.food), C.good))
		return
	end
	ns.Print(string.format(L["Pre-pull check for %s:"], where))
	for _, p in ipairs(problems) do print("  - " .. UI.Colorize(p, C.warn)) end
	if self:Settings().prepullBanner then
		self:ShowBanner(L["Pre-pull check"], table.concat(problems, "  ·  "), C.warn, SOUNDKIT.READY_CHECK or 8960)
	end
end

function Hardcore:CheckInstance()
	local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	if instanceType ~= "party" and instanceType ~= "raid" then
		self.lastInstance = nil
		return
	end
	if self.lastInstance == instanceID then return end
	self.lastInstance = instanceID
	if self:Settings().prepull then self:RunPrepull(name) end
end

function Hardcore:OnZoneChanged()
	wipe(self.warnedTargets)
	if self.zoneTimer then return end
	-- Map data is not ready on the loading screen: look a moment later.
	self.zoneTimer = self:ScheduleTimer(function()
		self.zoneTimer = nil
		if InCombatLockdown() then return end
		self:CheckInstance()
		self:CheckZone()
	end, 1.5)
end

---------------------------------------------------------------------------
-- Survival panel
---------------------------------------------------------------------------
local PANEL_ROWS = { "deaths", "alive", "level", "hearth" }

function Hardcore:CreatePanel()
	if self.panel then return self.panel end
	local f = UI.Panel("ForeverCompanionHardcorePanel", 240, 112, function() return self:Settings().panel end)
	f:SetFrameStrata("MEDIUM")
	local point = self:Settings().panel.point
	if point then
		f:SetPoint(point[1], UIParent, point[3], point[4], point[5])
	else
		f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 120)
	end
	f.title = UI.Text(f, 13, C.gold)
	f.title:SetPoint("TOPLEFT", 14, -9)
	f.title:SetText(L["Survival"])
	f.close = UI.CloseButton(f, function() self:SetPanelShown(false) end)
	f.close:SetSize(20, 20)
	f.close:SetPoint("TOPRIGHT", -2, -2)
	f.rows = {}
	local labels = { deaths = L["Deaths"], alive = L["Alive for"], level = L["Level"], hearth = L["Hearthstone"] }
	for i, key in ipairs(PANEL_ROWS) do
		local label = UI.Text(f, 12, C.muted)
		label:SetPoint("TOPLEFT", 14, -12 - i * 20)
		label:SetText(labels[key])
		local value = UI.Text(f, 12, C.text, "RIGHT")
		value:SetPoint("TOPRIGHT", -12, -12 - i * 20)
		value:SetPoint("LEFT", label, "RIGHT", 6, 0)
		value:SetWordWrap(false)
		f.rows[key] = value
	end
	f:SetScript("OnShow", function()
		self:RequestPlayed()
		if not self.panelTicker then self.panelTicker = self:ScheduleRepeatingTimer("UpdatePanel", 1) end
	end)
	f:SetScript("OnHide", function()
		if self.panelTicker then self:CancelTimer(self.panelTicker) self.panelTicker = nil end
	end)
	f:Hide()
	self.panel = f
	return f
end

function Hardcore:AliveText()
	local alive, isPlayed = self:AliveFor()
	if not alive then return UI.Colorize(L["type /played"], C.muted) end
	local text = ns.FormatDuration(alive)
	if not isPlayed then text = text .. " " .. UI.Colorize(L["(real time)"], C.muted) end
	return text
end

function Hardcore:UpdatePanel()
	local f = self.panel
	if not (f and f:IsShown()) then return end
	local deaths = Char().deaths or 0
	f.rows.deaths:SetText(UI.Colorize(tostring(deaths), deaths == 0 and C.good or C.bad))
	f.rows.alive:SetText(self:AliveText())
	local level = UnitLevel("player")
	f.rows.level:SetText(ns.IsSecret(level) and "--" or tostring(level))
	f.rows.hearth:SetText(InCombatLockdown() and "--" or self:HearthText())
end

function Hardcore:SetPanelShown(shown)
	self:Settings().panel.shown = shown and true or false
	if shown then
		self:CreatePanel():Show()
		self:UpdatePanel()
	elseif self.panel then
		self.panel:Hide()
	end
	self:RenderWindow()
end

function Hardcore:TogglePanel()
	self:SetPanelShown(not (self.panel and self.panel:IsShown()))
end

---------------------------------------------------------------------------
-- Window: /fc hc
---------------------------------------------------------------------------
local cards = UI.Pool(function(parent)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.Backdrop(card, C.panel, C.border)
	card.label = UI.Text(card, 11, C.muted, "CENTER")
	card.label:SetPoint("TOPLEFT", 6, -10)
	card.label:SetPoint("TOPRIGHT", -6, -10)
	card.label:SetWordWrap(false)
	card.value = UI.Text(card, 17, C.text, "CENTER")
	card.value:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -8)
	card.value:SetPoint("TOPRIGHT", card.label, "BOTTOMRIGHT", 0, -8)
	card.value:SetWordWrap(false)
	return card
end)

local sections = UI.Pool(function(parent) return UI.SectionTitle(parent, "") end)

local deathRows = UI.Pool(function(parent)
	local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.Backdrop(row, C.panel, C.border)
	row.level = UI.Chip(row, 12)
	row.level:SetPoint("LEFT", 10, 0)
	row.where = UI.Text(row, 13, C.text)
	row.where:SetPoint("TOPLEFT", 64, -7)
	row.where:SetPoint("RIGHT", -150, 0)
	row.where:SetWordWrap(false)
	row.detail = UI.Text(row, 11, C.muted)
	row.detail:SetPoint("TOPLEFT", row.where, "BOTTOMLEFT", 0, -3)
	row.detail:SetPoint("RIGHT", -10, 0)
	row.detail:SetWordWrap(false)
	row.date = UI.Text(row, 11, C.muted, "RIGHT")
	row.date:SetPoint("TOPRIGHT", -10, -8)
	return row
end)

local lines = UI.Pool(function(parent)
	local f = CreateFrame("Frame", nil, parent)
	f.text = UI.Text(f, 12, C.text)
	f.text:SetPoint("TOPLEFT")
	f.text:SetPoint("RIGHT")
	return f
end)

function Hardcore:CreateWindow()
	if self.frame then return self.frame end
	local f = UI.Window("ForeverCompanionHardcore", L["Hardcore survival"], 600, 560, self:Global().window,
		{ resizable = true, minWidth = 480, minHeight = 360 })
	f.OnResized = function() self:RenderWindow() end
	local bar = CreateFrame("Frame", nil, f.content)
	bar:SetPoint("TOPLEFT", 16, -10)
	bar:SetPoint("TOPRIGHT", -16, -10)
	bar:SetHeight(26)
	f.panelButton = UI.Button(bar, L["Survival panel"], 150, 26, "accent", function() self:TogglePanel() end)
	f.panelButton:SetPoint("LEFT")
	f.checkButton = UI.Button(bar, L["Run the pre-pull check"], 190, 26, "normal", function() self:RunPrepull() end)
	f.checkButton:SetPoint("LEFT", f.panelButton, "RIGHT", 8, 0)
	f.optionsButton = UI.Button(bar, L["Options"], 100, 26, "ghost", function() ns.OpenOptions() end)
	f.optionsButton:SetPoint("RIGHT")
	local scroll = UI.Scroll(f.content)
	scroll:SetPoint("TOPLEFT", 0, -44)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	f.scroll = scroll
	self.stack = UI.Stack(scroll.child, 16)
	f:SetScript("OnShow", function()
		self:RequestPlayed()
		if not self.windowTicker then self.windowTicker = self:ScheduleRepeatingTimer("RenderWindow", 5) end
	end)
	f:SetScript("OnHide", function()
		if self.windowTicker then self:CancelTimer(self.windowTicker) self.windowTicker = nil end
	end)
	self.frame = f
	return f
end

function Hardcore:ToggleWindow()
	local f = self:CreateWindow()
	if f:IsShown() then f:Hide() return end
	f:Show()
	self:RenderWindow()
end

local function OnOff(value)
	return value and UI.Colorize(L["On"], C.good) or UI.Colorize(L["Off"], C.muted)
end

function Hardcore:AddSection(text, gap)
	local s = sections:Acquire(self.stack.child)
	s:SetText(text)
	self.stack:Add(s, 28, gap or 18)
end

function Hardcore:AddLine(text, gap)
	local f = lines:Acquire(self.stack.child)
	f.text:SetText(text)
	self.stack:Add(f, math.max(16, f.text:GetStringHeight() + 4), gap or 4)
end

function Hardcore:RenderWindow()
	local f = self.frame
	if not (f and f:IsShown()) then return end
	cards:ReleaseAll()
	sections:ReleaseAll()
	deathRows:ReleaseAll()
	lines:ReleaseAll()
	local stack, child = self.stack, f.scroll.child
	stack:Reset()
	stack:Space(6)

	local c = Char()
	local deaths = c.deaths or 0
	local level = UnitLevel("player")
	local played = self:PlayedNow()
	local stats = {
		{ L["Deaths"], UI.Colorize(tostring(deaths), deaths == 0 and C.good or C.bad) },
		{ L["Alive for"], self:AliveText() },
		{ L["Level"], ns.IsSecret(level) and "--" or tostring(level) },
		{ L["Played"], played and ns.FormatDuration(played) or UI.Colorize("--", C.muted) },
		{ L["Hearthstone"], InCombatLockdown() and "--" or self:HearthText() },
	}
	local width = math.max(300, (child:GetWidth() or 560) - 32)
	local cardW = (width - 8 * (#stats - 1)) / #stats
	for i, stat in ipairs(stats) do
		local card = cards:Acquire(child)
		card:SetPoint("TOPLEFT", child, "TOPLEFT", 16 + (i - 1) * (cardW + 8), -stack.y)
		card:SetSize(cardW, 62)
		card.label:SetText(stat[1])
		card.value:SetText(stat[2])
		card.value:SetFontObject(UI.Font(i == 5 and 12 or 17))
	end
	stack:Space(62)
	f.panelButton:SetText(self.panel and self.panel:IsShown() and L["Hide the panel"] or L["Survival panel"])
	f.subtitle:SetText(ns.PlayerKey())

	-- Supplies right now.
	if not InCombatLockdown() then
		local counts = self:CountSupplies()
		self:AddSection(L["Supplies"])
		self:AddLine(string.format(L["Healing potions: %d  ·  Bandages: %d  ·  Food: %d  ·  Drinks: %d  ·  Durability: %d%%"],
			counts.potions, counts.bandages, counts.food, counts.drinks, math.floor(LowestDurability() * 100)), 8)
	end

	-- Death history.
	local history = self:DeathHistory()
	self:AddSection(string.format(L["Death history (%d)"], #history))
	if #history == 0 then
		self:AddLine(UI.Colorize(L["No death recorded. Keep it up!"], C.good), 8)
	end
	for i, d in ipairs(history) do
		if i > 50 then break end
		local row = deathRows:Acquire(child)
		row.level:Set(d.level and tostring(d.level) or "?", d.level and UI.LevelColor(d.level) or C.muted)
		local where = d.zone or "?"
		if d.subzone and d.subzone ~= "" then where = where .. " - " .. d.subzone end
		row.where:SetText(where)
		local detail = {}
		if d.killer then detail[#detail + 1] = L["last enemy targeted:"] .. " " .. d.killer end
		if d.aliveFor then detail[#detail + 1] = string.format(L["survived %s"], ns.FormatDuration(d.aliveFor)) end
		row.detail:SetText(table.concat(detail, "  ·  "))
		row.date:SetText(d.time and date("%d/%m/%Y %H:%M", d.time) or "")
		stack:Add(row, 44, i == 1 and 8 or 4)
	end

	-- Settings summary.
	local s = self:Settings()
	self:AddSection(L["Settings"])
	self:AddLine(L["Zone warnings"] .. ": " .. OnOff(s.zoneWarn) .. UI.Colorize("  " .. string.format(L["(zone minimum above your level +%d)"], s.zoneLevelGap), C.muted), 8)
	self:AddLine(L["Hostile territory warnings"] .. ": " .. OnOff(s.hostileZoneWarn))
	self:AddLine(L["Target warnings"] .. ": " .. OnOff(s.targetWarn) .. UI.Colorize("  " .. string.format(L["(%d+ levels above you, elites: %s, skulls: %s)"],
		s.targetLevelGap, s.targetWarnElite and L["On"] or L["Off"], s.targetWarnSkull and L["On"] or L["Off"]), C.muted))
	self:AddLine(L["Danger badge on the target frame"] .. ": " .. OnOff(s.targetBadge))
	self:AddLine(L["Pre-pull checklist"] .. ": " .. OnOff(s.prepull) .. UI.Colorize("  " .. string.format(L["(durability below %d%%)"], s.prepullDurability), C.muted))
	self:AddLine(L["Survival panel"] .. ": " .. OnOff(self.panel and self.panel:IsShown()))
	self:AddLine(L["Sound"] .. ": " .. OnOff(s.sound))
	self:AddLine(UI.Colorize(L["Warnings only work out of combat, as WoW Forever does not let addons read combat."], C.muted), 10)
	f.scroll:SetContentHeight(stack.y + 20)
end

---------------------------------------------------------------------------
-- Enable / commands / options
---------------------------------------------------------------------------
function Hardcore:OnEnable()
	self.warnedTargets = self.warnedTargets or {}
	local c = Char()
	if not self.playedBase and c.playedAtLogout then
		-- Played time grows with session time: last logout total + time since this session started.
		self.playedBase = { total = c.playedAtLogout, at = SESSION_START }
	end
	self:RegisterEvent("PLAYER_DEAD")
	self:RegisterEvent("PLAYER_LOGOUT")
	self:RegisterEvent("TIME_PLAYED_MSG")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "CheckTarget")
	self:RegisterEvent("PLAYER_LEVEL_UP", "UpdatePanel")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChanged")
	if self:Settings().panel.shown then self:SetPanelShown(true) end
end

function Hardcore:OnDisable()
	-- Played time is no longer followed: forget the estimate rather than keep a stale one.
	Char().playedAtLogout = nil
	if self.panel then self.panel:Hide() end
	if self.frame then self.frame:Hide() end
	if self.badge then self.badge:Hide() end
	if self.banner then self.banner:Hide() end
	if self.playedPending then self:RestorePlayedChat() end
	self.zoneTimer = nil
end

function Hardcore:OnProfileChanged()
	if self.panel then self.panel:SetShown(self:Settings().panel.shown) end
	self:CheckTarget()
	self:RenderWindow()
end

ns.RegisterCommand("hc", L["hardcore survival window (/fc hc panel, /fc hc check)"], function(rest)
	if not Hardcore:IsEnabled() then ns.OpenOptions() return end
	rest = (rest or ""):lower()
	if rest == "panel" then
		Hardcore:TogglePanel()
	elseif rest == "check" then
		Hardcore:RunPrepull()
	else
		Hardcore:ToggleWindow()
	end
end)

function Hardcore:GetOptions()
	local get, set = ns.ProfileAccessors("Hardcore", function() self:RenderWindow() end)
	return {
		get = get, set = set,
		args = {
			open = { type = "execute", order = 1, name = L["Hardcore survival"], func = function() self:ToggleWindow() end },
			panelShown = {
				type = "toggle", order = 2, name = L["Show the survival panel"],
				get = function() return self:Settings().panel.shown end,
				set = function(_, v) self:SetPanelShown(v) end,
			},
			panelLocked = {
				type = "toggle", order = 3, name = L["Lock the panel"],
				get = function() return self:Settings().panel.locked end,
				set = function(_, v) self:Settings().panel.locked = v end,
			},
			sound = { type = "toggle", order = 4, name = L["Play a sound"] },
			bannerDuration = { type = "range", order = 5, name = L["Warning duration (seconds)"], min = 1, max = 10, step = 1 },

			zoneHeader = { type = "header", order = 10, name = L["Zones"] },
			zoneWarn = { type = "toggle", order = 11, width = "full", name = L["Warn when entering a zone above my level"] },
			zoneLevelGap = { type = "range", order = 12, name = L["Zone minimum above my level by more than"], min = 0, max = 10, step = 1 },
			hostileZoneWarn = { type = "toggle", order = 13, width = "full", name = L["Warn when entering enemy faction territory"] },

			targetHeader = { type = "header", order = 20, name = L["Targets"] },
			targetWarn = { type = "toggle", order = 21, width = "full", name = L["Warn when I target a dangerous enemy"] },
			targetLevelGap = { type = "range", order = 22, name = L["Levels above me"], min = 1, max = 10, step = 1 },
			targetWarnElite = { type = "toggle", order = 23, name = L["Warn on elites"] },
			targetWarnSkull = { type = "toggle", order = 24, name = L["Warn on skull-level enemies"] },
			targetBadge = {
				type = "toggle", order = 25, width = "full", name = L["Danger badge on the target frame"],
				set = function(info, v) set(info, v) self:CheckTarget() end,
			},

			prepullHeader = { type = "header", order = 30, name = L["Pre-pull checklist"] },
			prepull = { type = "toggle", order = 31, width = "full", name = L["Check my supplies when entering a dungeon or raid"] },
			prepullBanner = { type = "toggle", order = 32, name = L["Show a warning banner"] },
			prepullDurability = { type = "range", order = 33, name = L["Warn when durability is below (%)"], min = 0, max = 100, step = 5 },
			checkPotions = { type = "toggle", order = 34, name = L["Healing potions"] },
			checkBandages = { type = "toggle", order = 35, name = L["Bandages"] },
			checkFood = { type = "toggle", order = 36, name = L["Food"] },
			checkDrinks = { type = "toggle", order = 37, name = L["Drinks"] },
			checkHearth = { type = "toggle", order = 38, name = L["Hearthstone"] },

			otherHeader = { type = "header", order = 40, name = L["Played time"] },
			requestPlayed = { type = "toggle", order = 41, width = "full", name = L["Ask the server for my played time when I open the panel (no chat message)"] },
			note = { type = "description", order = 42, name = "\n" .. L["Warnings only work out of combat, as WoW Forever does not let addons read combat."] .. "\n" .. L["/fc hc opens the window, /fc hc panel toggles the panel, /fc hc check runs the pre-pull check."] },
		},
	}
end
