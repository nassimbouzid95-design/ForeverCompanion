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
