-- ForeverCompanion: shared namespace, saved-variable defaults and small helpers.
local ADDON, ns = ...

ns.ADDON = ADDON
ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"
ns.L = LibStub("AceLocale-3.0"):GetLocale(ADDON)

-- Modules add their own defaults here at file load time, before AceDB is created.
ns.defaults = {
	profile = {
		modules = {},
		minimap = { hide = false, angle = 215 },
		appearance = { theme = "forever", scale = 1, opacity = 0.96 },
	},
	global = {},
	char = {},
}

function ns.RegisterDefaults(scope, key, tbl)
	ns.defaults[scope][key] = tbl
end

ns.COLOR = "|cff33ccff"
ns.TAG = ns.COLOR .. "Forever|rCompanion"

function ns.Print(...)
	print(ns.TAG .. ":", ...)
end

-- Midnight (and therefore Forever) can hand addons "secret" values during combat.
-- Anything coming from the game that we compare or store goes through this first.
function ns.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

function ns.AnySecret(...)
	if not issecretvalue then return false end
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return true end
	end
	return false
end

function ns.PlayerKey()
	local name, realm = UnitFullName("player")
	realm = realm or GetNormalizedRealmName() or ""
	return name .. "-" .. realm
end

function ns.NPCIDFromGUID(guid)
	if not guid or ns.IsSecret(guid) then return nil end
	local unitType, _, _, _, _, npcID = strsplit("-", guid)
	if unitType == "Creature" or unitType == "Vehicle" then
		return tonumber(npcID)
	end
end

function ns.ItemIDFromLink(link)
	if not link or ns.IsSecret(link) then return nil end
	return tonumber(link:match("item:(%d+)"))
end

function ns.FormatDuration(seconds)
	if not seconds or seconds ~= seconds or seconds == math.huge or seconds < 0 then return "--" end
	seconds = math.floor(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then return string.format("%dh%02dm", h, m) end
	if m > 0 then return string.format("%dm%02ds", m, s) end
	return string.format("%ds", s)
end

function ns.FormatMoney(copper)
	copper = copper or 0
	if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
		return C_CurrencyInfo.GetCoinTextureString(copper)
	end
	return GetMoneyString(copper, true)
end

function ns.FormatNumber(n)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

function ns.Percent(part, total)
	if not total or total == 0 then return 0 end
	return part / total * 100
end

function ns.ClassColored(text, classFile)
	local c = classFile and RAID_CLASS_COLORS[classFile]
	if not c then return text end
	return c:WrapTextInColorCode(text)
end

-- Distance (yards) and direction (radians, counter-clockwise from north) between two points of the same map.
function ns.MapVector(mapID, x1, y1, x2, y2)
	local width, height = C_Map.GetMapWorldSize(mapID)
	if not width or width == 0 then return nil end
	local dx = (x2 - x1) * width
	local dy = (y2 - y1) * height
	return math.sqrt(dx * dx + dy * dy), math.atan2(-dx, -dy)
end

function ns.PlayerMapPosition()
	local mapID = C_Map.GetBestMapForUnit("player")
	if not mapID then return nil end
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return mapID end
	local x, y = pos:GetXY()
	if ns.AnySecret(x, y) then return mapID end
	return mapID, x, y
end

-- Position of the player on a given map (works across zone/continent maps when the API allows it).
function ns.PlayerPositionOn(mapID)
	local pos = C_Map.GetPlayerMapPosition(mapID, "player")
	if not pos then return nil end
	local x, y = pos:GetXY()
	if ns.AnySecret(x, y) or (x == 0 and y == 0) then return nil end
	return x, y
end

function ns.MapName(mapID)
	local info = mapID and C_Map.GetMapInfo(mapID)
	return info and info.name or ("#" .. tostring(mapID))
end

-- One shared copy/paste window, used for exports and chat links.
function ns.ShowCopyBox(title, text, onAccept)
	local AceGUI = LibStub("AceGUI-3.0")
	local frame = AceGUI:Create("Frame")
	frame:SetTitle(title)
	frame:SetLayout("Fill")
	frame:SetWidth(520)
	frame:SetHeight(360)
	frame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
	local box = AceGUI:Create("MultiLineEditBox")
	box:SetLabel(onAccept and ns.L["Paste below then click Accept"] or ns.L["Select all with Ctrl+A then copy with Ctrl+C"])
	box:SetText(text or "")
	box:DisableButton(not onAccept)
	if onAccept then
		box:SetCallback("OnEnterPressed", function(_, _, value)
			onAccept(value)
			frame:Hide()
		end)
	end
	frame:AddChild(box)
	box:SetFocus()
	box.editBox:HighlightText()
	return frame
end

-- Compact text encoding for exports (AceSerializer output is safe to paste but long; this keeps it on one line).
function ns.Encode(tbl)
	local AceSerializer = LibStub("AceSerializer-3.0")
	return "FC1:" .. AceSerializer:Serialize(tbl)
end

function ns.Decode(text)
	if type(text) ~= "string" then return nil end
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	local payload = text:match("^FC1:(.*)$")
	if not payload then return nil end
	local ok, data = LibStub("AceSerializer-3.0"):Deserialize(payload)
	if ok then return data end
end

---------------------------------------------------------------------------
-- World coordinates. Server/world coordinates: x grows to the north, y grows to the west,
-- continent 0 = Eastern Kingdoms, 1 = Kalimdor. They let the arrow work from one zone to another.
---------------------------------------------------------------------------
function ns.MapToWorld(mapID, x, y)
	if not (mapID and x and y and C_Map.GetWorldPosFromMapPos) then return nil end
	local ok, continent, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
	if not ok or not continent or not pos then return nil end
	local wx, wy = pos:GetXY()
	if ns.AnySecret(continent, wx, wy) then return nil end
	return continent, wx, wy
end

-- Map coordinates of a world point on a given map (nil when it is not on that map).
function ns.WorldToMap(continent, wx, wy, mapID)
	if not (C_Map.GetMapPosFromWorldPos and mapID) then return nil end
	local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, CreateVector2D(wx, wy), mapID)
	if not ok or not pos then return nil end
	local x, y = pos:GetXY()
	if not x or x < 0 or x > 1 or y < 0 or y > 1 then return nil end
	return x, y
end

-- Race bit of the player in quest race masks (WoW Forever adds Skyborne: race IDs 95 and 96).
function ns.PlayerRaceBit()
	local _, _, raceID = UnitRace("player")
	if not raceID or ns.IsSecret(raceID) then return nil end
	if raceID >= 1 and raceID <= 8 then return 2 ^ (raceID - 1) end
	if raceID == 95 then return 4294967296 end
	if raceID == 96 then return 8589934592 end
	return nil
end

-- Quests of the new Forever zones are stored with map coordinates (continent = -uiMapID, x and y = map
-- position * 10000) until the game can place them in the world. Converted once at login, in place.
local function Resolve(c, x, y)
	if not c or c >= 0 then return c, x, y end
	local cont, wx, wy = ns.MapToWorld(-c, x / 10000, y / 10000)
	if cont then return cont, math.floor(wx + 0.5), math.floor(wy + 0.5) end
	return c, x, y
end
ns.ResolvePosition = Resolve

function ns.ResolveNewZones()
	-- the map position is kept too (q.sm, q.em, q.om[i]): the arrow and the map pin use it on maps the
	-- world coordinates do not cover well (Zephras Isle and the other new zones)
	for _, q in pairs(ns.QuestDB or {}) do
		if q[8] < 0 then q.sm = { -q[8], q[9] / 10000, q[10] / 10000 }; q[8], q[9], q[10] = Resolve(q[8], q[9], q[10]) end
		if q[11] < 0 then q.em = { -q[11], q[12] / 10000, q[13] / 10000 }; q[11], q[12], q[13] = Resolve(q[11], q[12], q[13]) end
		local o = q[14]
		for i = 1, #o, 3 do
			if o[i] < 0 then
				q.om = q.om or {}
				q.om[i] = { -o[i], o[i + 1] / 10000, o[i + 2] / 10000 }
				o[i], o[i + 1], o[i + 2] = Resolve(o[i], o[i + 1], o[i + 2])
			end
		end
	end
	for _, q in pairs(ns.DungeonQuestInfo or {}) do
		for _, npc in ipairs({ q.giver, q.turnin }) do
			if npc and npc[2] and npc[2] < 0 then npc[2], npc[3], npc[4] = Resolve(npc[2], npc[3], npc[4]) end
		end
	end
	for _, route in ipairs(ns.Routes or {}) do
		for _, step in ipairs(rawget(route, "steps") or {}) do   -- packed routes resolve when expanded
			if step.cont and step.cont < 0 then step.cont, step.wx, step.wy = Resolve(step.cont, step.wx, step.wy) end
		end
	end
end

function ns.PlayerWorldPosition()
	local mapID, x, y = ns.PlayerMapPosition()
	if not x then return nil end
	return ns.MapToWorld(mapID, x, y)
end

-- Distance (yards) and direction (radians, counter-clockwise from north) between two world points.
function ns.WorldVector(x1, y1, x2, y2)
	local dx, dy = x2 - x1, y2 - y1
	return math.sqrt(dx * dx + dy * dy), math.atan2(dy, dx)
end

ns.CONTINENT_NAMES = { [0] = "Eastern Kingdoms", [1] = "Kalimdor" }
