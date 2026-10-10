-- ForeverCompanion: open-world safety (the Forever world is meant to be dangerous).
local _, ns = ...
local L = ns.L

local Safety = ns.NewModule("Safety", {
	durabilityWarn = 25,  -- percent
	bagsWarn = 2,         -- free slots
	dangerAlert = true,
	dangerLevelGap = 3,   -- alert for elites this many levels above you (or more)
	rareAlert = true,
	sound = true,
}, {
	deaths = {}, -- list of { char, level, map, x, y, zone, subzone, time, killer }
})

local alerted = {} -- GUIDs already announced

local function Alert(text)
	RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo.RAID_WARNING)
	if Safety:Settings().sound then PlaySound(SOUNDKIT.RAID_WARNING or 8959) end
end

-- Death log --------------------------------------------------------------
function Safety:PLAYER_DEAD()
	local mapID, x, y = ns.PlayerMapPosition()
	local killer = self.lastTarget
	local entry = {
		char = ns.PlayerKey(), level = UnitLevel("player"),
		map = mapID, x = x, y = y,
		zone = GetRealZoneText(), subzone = GetSubZoneText(),
		time = time(), killer = killer,
	}
	table.insert(self:Global().deaths, 1, entry)
	while #self:Global().deaths > 200 do table.remove(self:Global().deaths) end
end

function Safety:PLAYER_TARGET_CHANGED()
	if UnitExists("target") and UnitCanAttack("player", "target") then
		local name, level = UnitName("target"), UnitLevel("target")
		if not ns.AnySecret(name, level) then
			self.lastTarget = string.format("%s (%s)", name, level == -1 and "??" or level)
		end
	end
end

function Safety:ShowDeaths()
	local lines = {}
	for i, d in ipairs(self:Global().deaths) do
		if i > 30 then break end
		lines[#lines + 1] = string.format("%s  %s %d  %s%s%s%s",
			date("%d/%m %H:%M", d.time), d.char, d.level or 0, d.zone or "",
			d.subzone and d.subzone ~= "" and (" - " .. d.subzone) or "",
			d.x and string.format(" (%.1f, %.1f)", d.x * 100, d.y * 100) or "",
			d.killer and ("  |  " .. L["last enemy targeted:"] .. " " .. d.killer) or "")
	end
	ns.ShowCopyBox(L["Death log"], #lines > 0 and table.concat(lines, "\n") or L["No death recorded. Keep it up!"])
end

-- Durability and bags -----------------------------------------------------
function Safety:CheckDurability()
	local pct = ns.LowestDurability() * 100
	local limit = self:Settings().durabilityWarn
	if pct <= limit and not self.durabilityWarned then
		self.durabilityWarned = true
		Alert(string.format(L["Low durability: %d%%. Repair before heading out!"], pct))
	elseif pct > limit then
		self.durabilityWarned = false
	end
end

function Safety:CheckBags()
	local free = 0
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
	end
	local limit = self:Settings().bagsWarn
	if free <= limit and not self.bagsWarned then
		self.bagsWarned = true
		ns.Print(string.format(L["Only %d free bag slots left."], free))
	elseif free > limit then
		self.bagsWarned = false
	end
end

-- Dangerous mobs (out of combat only, from nameplates) -----------------------
function Safety:NAME_PLATE_UNIT_ADDED(_, unit)
	if InCombatLockdown() or IsInInstance() then return end
	local s = self:Settings()
	local ok, guid = pcall(UnitGUID, unit)
	if not ok or not guid or ns.IsSecret(guid) or alerted[guid] then return end
	if UnitIsPlayer(unit) or not UnitCanAttack("player", unit) or UnitIsDead(unit) then return end
	local classification = UnitClassification(unit)
	local level, myLevel = UnitLevel(unit), UnitLevel("player")
	local name = UnitName(unit)
	if ns.AnySecret(classification, level, name) then return end

	if s.rareAlert and (classification == "rare" or classification == "rareelite") then
		alerted[guid] = true
		Alert(string.format(L["Rare nearby: %s"], name))
	elseif s.dangerAlert and (classification == "elite" or classification == "worldboss")
		and (level == -1 or level - myLevel >= s.dangerLevelGap) then
		alerted[guid] = true
		Alert(string.format(L["Danger: %s (level %s) nearby"], name, level == -1 and "??" or level))
	end
end

function Safety:OnEnable()
	self:RegisterEvent("PLAYER_DEAD")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "CheckDurability")
	self:RegisterEvent("BAG_UPDATE_DELAYED", "CheckBags")
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() wipe(alerted); self:CheckDurability() end)
end

ns.RegisterCommand("deaths", L["show the death log"], function() Safety:ShowDeaths() end)

function Safety:GetOptions()
	local get, set = ns.ProfileAccessors("Safety")
	return {
		get = get, set = set,
		args = {
			durabilityWarn = { type = "range", order = 1, name = L["Warn when durability is below (%)"], min = 0, max = 100, step = 5 },
			bagsWarn = { type = "range", order = 2, name = L["Warn when free bag slots are at most"], min = 0, max = 20, step = 1 },
			dangerAlert = { type = "toggle", order = 3, width = "full", name = L["Alert when a much stronger elite appears nearby"] },
			dangerLevelGap = { type = "range", order = 4, name = L["Level gap"], min = 0, max = 10, step = 1 },
			rareAlert = { type = "toggle", order = 5, name = L["Alert when a rare appears"] },
			sound = { type = "toggle", order = 6, name = L["Play a sound"] },
			deaths = { type = "execute", order = 7, name = L["Death log"], func = function() self:ShowDeaths() end },
			note = { type = "description", order = 8, name = "\n" .. L["Alerts only work out of combat and outside instances, as WoW Forever does not let addons read combat."] },
		},
	}
end
