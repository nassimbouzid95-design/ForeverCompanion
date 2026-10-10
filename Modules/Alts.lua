-- ForeverCompanion: every character of the account at a glance.
local _, ns = ...
local L = ns.L

local Alts = ns.NewModule("Alts", {
	allRealms = false,
}, {
	chars = {}, -- [name-realm] = data
	goldHistory = {}, -- [YYYY-MM-DD] = total copper on that day
})

local BAG_FIRST, BAG_LAST = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4

local function Me()
	local key = ns.PlayerKey()
	local chars = Alts:Global().chars
	chars[key] = chars[key] or { bags = {}, bank = {}, mail = {}, lockouts = {}, professions = {} }
	return chars[key], key
end

function Alts:UpdateBasics()
	local c = Me()
	local name, realm = UnitFullName("player")
	c.name, c.realm = name, realm or GetNormalizedRealmName()
	c.class = select(2, UnitClass("player"))
	c.race = select(2, UnitRace("player"))
	c.raceName = UnitRace("player")
	c.faction = UnitFactionGroup("player")
	c.level = UnitLevel("player")
	c.money = GetMoney()
	c.xp, c.xpMax, c.rested = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0
	c.zone = GetRealZoneText()
	c.lastSeen = time()
	c.ilvl = GetAverageItemLevel and math.floor(select(2, GetAverageItemLevel()) or 0) or nil
	if c.level >= (GetMaxPlayerLevel() or 60) and not c.reached60 then c.reached60 = time() end
	self:RecordGold()
end

function Alts:RecordGold()
	local total = 0
	for _, c in pairs(self:Global().chars) do total = total + (c.money or 0) end
	self:Global().goldHistory[date("%Y-%m-%d")] = total
end

function Alts:UpdateProfessions()
	local c = Me()
	local list = {}
	if GetProfessions then
		for _, index in pairs({ GetProfessions() }) do
			if index then
				local name, icon, rank, max = GetProfessionInfo(index)
				list[#list + 1] = { name = name, icon = icon, rank = rank, max = max }
			end
		end
	end
	if #list == 0 and GetNumSkillLines then
		-- Classic-style skill list.
		local inProfessions = false
		for i = 1, GetNumSkillLines() do
			local name, isHeader, _, rank, _, _, max = GetSkillLineInfo(i)
			if isHeader then
				inProfessions = (name == TRADE_SKILLS or name == SECONDARY_SKILLS)
			elseif inProfessions then
				list[#list + 1] = { name = name, rank = rank, max = max }
			end
		end
	end
	c.professions = list
end

local function ScanContainer(bag, into)
	for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
		local info = C_Container.GetContainerItemInfo(bag, slot)
		if info and info.itemID then
			into[info.itemID] = (into[info.itemID] or 0) + (info.stackCount or 1)
		end
	end
end

function Alts:UpdateBags()
	local c = Me()
	local bags = {}
	for bag = BAG_FIRST, BAG_LAST do ScanContainer(bag, bags) end
	-- Equipped items count too, so "where is my item" finds them.
	for slot = 1, 19 do
		local id = GetInventoryItemID("player", slot)
		if id then bags[id] = (bags[id] or 0) + 1 end
	end
	c.bags = bags
end

function Alts:UpdateBank()
	local c = Me()
	local bank = {}
	for key, index in pairs(Enum.BagIndex or {}) do
		if type(key) == "string" and key:find("Bank") and not key:find("Account") then
			ScanContainer(index, bank)
		end
	end
	if not Enum.BagIndex then
		ScanContainer(BANK_CONTAINER or -1, bank)
		for bag = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7) do ScanContainer(bag, bank) end
	end
	c.bank = bank
end

function Alts:UpdateMail()
	local c = Me()
	local mail = {}
	for i = 1, GetInboxNumItems() do
		for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
			local _, itemID, _, count = GetInboxItem(i, a)
			if itemID then mail[itemID] = (mail[itemID] or 0) + (count or 1) end
		end
	end
	c.mail = mail
end

function Alts:UpdateLockouts()
	local c = Me()
	local list = {}
	for i = 1, GetNumSavedInstances() do
		local name, _, reset, _, locked, _, _, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
		if locked and reset and reset > 0 then
			list[#list + 1] = {
				name = name, expires = time() + reset, isRaid = isRaid, size = maxPlayers,
				difficulty = difficultyName, progress = encounterProgress, total = numEncounters,
			}
		end
	end
	c.lockouts = list
end

function Alts:TIME_PLAYED_MSG(_, total, thisLevel)
	local c = Me()
	c.played, c.playedLevel = total, thisLevel
end

-- Public: how many of an item every character owns. Returns a list of { name, class, bags, bank, mail }.
function ns.ItemOwners(itemID)
	local result = {}
	if not (Alts:IsEnabled() and itemID) then return result end
	local myRealm = GetNormalizedRealmName()
	for _, c in pairs(Alts:Global().chars) do
		if Alts:Settings().allRealms or c.realm == myRealm then
			local bags, bank, mail = c.bags and c.bags[itemID] or 0, c.bank and c.bank[itemID] or 0, c.mail and c.mail[itemID] or 0
			if bags + bank + mail > 0 then
				result[#result + 1] = { name = c.name, class = c.class, bags = bags, bank = bank, mail = mail }
			end
		end
	end
	table.sort(result, function(a, b) return a.name < b.name end)
	return result
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function SortedChars(self)
	local list = {}
	for key, c in pairs(self:Global().chars) do
		c.key = key
		list[#list + 1] = c
	end
	table.sort(list, function(a, b)
		if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
		return (a.name or "") < (b.name or "")
	end)
	return list
end

function Alts:ShowWindow()
	self:UpdateBasics()
	local AceGUI = LibStub("AceGUI-3.0")
	if self.window then self.window:Release() end
	local frame = AceGUI:Create("Frame")
	self.window = frame
	frame:SetTitle(L["My characters"])
	frame:SetLayout("Fill")
	frame:SetWidth(720)
	frame:SetHeight(520)
	frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget); self.window = nil end)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("List")
	frame:AddChild(scroll)

	local total, journeys = 0, 0
	for _, c in ipairs(SortedChars(self)) do
		total = total + (c.money or 0)
		if c.reached60 then journeys = journeys + 1 end

		local group = AceGUI:Create("InlineGroup")
		group:SetFullWidth(true)
		group:SetLayout("Flow")
		group:SetTitle(ns.ClassColored(string.format("%s - %s", c.name or "?", c.realm or ""), c.class))

		local lines = {}
		lines[#lines + 1] = string.format("%s %d %s  |  %s  |  %s", LEVEL, c.level or 0, c.raceName or "", ns.FormatMoney(c.money or 0), c.zone or "")
		if c.level and c.level < 60 and c.xpMax and c.xpMax > 0 then
			lines[#lines + 1] = string.format(L["XP %.0f%%, rested %.0f%%"], (c.xp or 0) / c.xpMax * 100, (c.rested or 0) / c.xpMax * 100)
		end
		if c.played then
			lines[#lines + 1] = L["Played:"] .. " " .. ns.FormatDuration(c.played)
		end
		if c.professions and #c.professions > 0 then
			local parts = {}
			for _, p in ipairs(c.professions) do parts[#parts + 1] = string.format("%s %d/%d", p.name, p.rank or 0, p.max or 0) end
			lines[#lines + 1] = L["Professions:"] .. " " .. table.concat(parts, ", ")
		end
		local now = time()
		local locks = {}
		for _, lock in ipairs(c.lockouts or {}) do
			if lock.expires > now then
				locks[#locks + 1] = string.format("%s %d/%d (%s)", lock.name, lock.progress or 0, lock.total or 0, ns.FormatDuration(lock.expires - now))
			end
		end
		if #locks > 0 then lines[#lines + 1] = L["Lockouts:"] .. " " .. table.concat(locks, ", ") end
		if c.lastSeen then lines[#lines + 1] = "|cff888888" .. L["Last seen:"] .. " " .. date("%d/%m/%Y %H:%M", c.lastSeen) .. "|r" end

		local label = AceGUI:Create("Label")
		label:SetFullWidth(true)
		label:SetText(table.concat(lines, "\n"))
		group:AddChild(label)

		if c.key ~= ns.PlayerKey() then
			local delete = AceGUI:Create("Button")
			delete:SetText(L["Forget this character"])
			delete:SetWidth(180)
			delete:SetCallback("OnClick", function()
				self:Global().chars[c.key] = nil
				self:ShowWindow()
			end)
			group:AddChild(delete)
		end
		scroll:AddChild(group)
	end

	local summary = AceGUI:Create("Label")
	summary:SetFullWidth(true)
	summary:SetFontObject(GameFontNormalLarge)
	summary:SetText(string.format(L["Total gold: %s   |   1-60 journeys completed (Legacy): %d"], ns.FormatMoney(total), journeys))
	scroll:AddChild(summary)
	frame:SetStatusText(L["Lockouts, professions and bank are updated when you log in on each character and open the bank."])
end

function Alts:Find(text)
	text = (text or ""):lower()
	if text == "" then ns.Print(L["Usage: /fc find <item name>"]) return end
	local found = 0
	local seen = {}
	for _, c in pairs(self:Global().chars) do
		for _, where in ipairs({ "bags", "bank", "mail" }) do
			for itemID in pairs(c[where] or {}) do
				if not seen[itemID] then
					local name = C_Item.GetItemNameByID(itemID)
					if name and name:lower():find(text, 1, true) then
						seen[itemID] = true
						local owners = ns.ItemOwners(itemID)
						local parts = {}
						for _, o in ipairs(owners) do
							parts[#parts + 1] = string.format("%s %d", ns.ClassColored(o.name, o.class), o.bags + o.bank + o.mail)
						end
						local _, link = C_Item.GetItemInfo(itemID)
						ns.Print((link or name) .. ": " .. table.concat(parts, ", "))
						found = found + 1
					end
				end
			end
		end
	end
	if found == 0 then ns.Print(L["Nothing found."]) end
end

function Alts:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		self:UpdateBasics(); self:UpdateProfessions(); self:UpdateBags()
		RequestRaidInfo()
	end)
	self:RegisterEvent("PLAYER_MONEY", "UpdateBasics")
	self:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(1, function() self:UpdateBasics() end) end)
	self:RegisterEvent("PLAYER_LOGOUT", "UpdateBasics")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "UpdateBags")
	self:RegisterEvent("BANKFRAME_OPENED", "UpdateBank")
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED", function() if BankFrame and BankFrame:IsShown() then self:UpdateBank() end end)
	self:RegisterEvent("MAIL_INBOX_UPDATE", "UpdateMail")
	self:RegisterEvent("UPDATE_INSTANCE_INFO", "UpdateLockouts")
	self:RegisterEvent("SKILL_LINES_CHANGED", "UpdateProfessions")
	self:RegisterEvent("TIME_PLAYED_MSG")
end

ns.RegisterCommand("alts", L["show all your characters"], function() Alts:ShowWindow() end)
ns.RegisterCommand("find", L["<item> - find an item on all your characters"], function(rest) Alts:Find(rest) end)

function Alts:GetOptions()
	local get, set = ns.ProfileAccessors("Alts")
	return {
		get = get, set = set,
		args = {
			open = { type = "execute", order = 1, name = L["My characters"], func = function() self:ShowWindow() end },
			allRealms = { type = "toggle", order = 2, width = "full", name = L["Count items on characters of every realm"] },
			help = { type = "description", order = 3, name = "\n" .. L["/fc alts opens the window, /fc find <item> searches every character. Type /played once on each character to record play time."] },
		},
	}
end
