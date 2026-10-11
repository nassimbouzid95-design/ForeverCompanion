-- Minimal WoW API mock to load ForeverCompanion and run its init/enable paths.
local _xpcall = xpcall
xpcall = function(f, h, ...) local args = { n = select("#", ...), ... } return _xpcall(function() return f(unpack(args, 1, args.n)) end, h) end
local root = arg[1]
local frames = {}
local function noop() end
local Dummy
local dummyMT = {}
dummyMT.__index = function(t, k) return Dummy end
dummyMT.__call = function() return nil end
Dummy = setmetatable({}, dummyMT)

local frameMethods = {}
function frameMethods:SetScript(name, fn) self.scripts[name] = fn end
function frameMethods:GetScript(name) return self.scripts[name] end
function frameMethods:HookScript(name, fn) self.scripts[name] = fn end
function frameMethods:RegisterEvent(e) self.events[e] = true end
function frameMethods:RegisterUnitEvent(e) self.events[e] = true end
function frameMethods:UnregisterEvent(e) self.events[e] = nil end
function frameMethods:UnregisterAllEvents() self.events = {} end
function frameMethods:IsEventRegistered(e) return self.events[e] end
function frameMethods:GetName() return self.name end
function frameMethods:GetWidth() return self.w or 100 end
function frameMethods:SetWidth(w) self.w = w end
function frameMethods:SetSize(w, h) self.w, self.h = w, h end
function frameMethods:SetHeight(h) self.h = h end
function frameMethods:GetVerticalScroll() return self.vs or 0 end
function frameMethods:SetVerticalScroll(v) self.vs = v end
function frameMethods:GetStringWidth() return 50 end
function frameMethods:GetHeight() return self.h or 20 end
function frameMethods:GetStringHeight() return 12 end
function frameMethods:GetStringWidth() return 50 end
function frameMethods:GetFrameLevel() return 1 end
function frameMethods:GetEffectiveScale() return 1 end
function frameMethods:GetCenter() return 0, 0 end
function frameMethods:IsShown() return self.shown end
function frameMethods:IsVisible() return self.shown end
function frameMethods:Show() self.shown = true end
function frameMethods:Hide() self.shown = false end
function frameMethods:SetShown(v) self.shown = v end
function frameMethods:GetParent() return self.parent end
function frameMethods:CreateFontString() return NewFrame("FontString") end
function frameMethods:CreateTexture() return NewFrame("Texture") end
function frameMethods:CreateAnimationGroup() return NewFrame("Anim") end
function frameMethods:CreateAnimation() return NewFrame("Anim") end
function frameMethods:GetFontString() return NewFrame("FontString") end
function frameMethods:GetObjectType() return self.kind end
function frameMethods:GetNumPoints() return 0 end
function frameMethods:GetText() return self.text or "" end
function frameMethods:SetText(t) self.text = t end
function frameMethods:SetFormattedText(f, ...) self.text = string.format(f, ...) end
function frameMethods:GetFont() return "font", 12, "" end
function frameMethods:GetRegions() return end
function frameMethods:GetChildren() return end
function frameMethods:EnumerateValidItems() return ipairs({}) end
local fmMT = { __index = function(t, k)
	if frameMethods[k] then return frameMethods[k] end
	if type(k) == "string" and (k:match("Texture$") or k:match("FontString$") or k:match("Frame$") or k:match("Bar$")) and k:match("^Get") then
		return function() return NewFrame("Sub") end
	end
	if type(k) == "string" and k:match("^%l") then return nil end
	return noop
end }
function NewFrame(kind, name, parent)
	local f = setmetatable({ scripts = {}, events = {}, kind = kind, name = name, parent = parent }, fmMT)
	frames[#frames + 1] = f
	if name then _G[name] = f end
	return f
end
CreateFrame = function(kind, name, parent) return NewFrame(kind, name, parent) end
CreateFont = function(name) return NewFrame("Font", name) end
CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
Mixin = function(t, ...) for _, m in ipairs({ ... }) do for k, v in pairs(m) do t[k] = v end end return t end
GetCursorPosition = function() return 0, 0 end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UIParent = NewFrame("Frame", "UIParent")
Minimap = NewFrame("Frame", "Minimap")
WorldMapFrame = NewFrame("Frame", "WorldMapFrame")
WorldMapFrame.ScrollContainer = NewFrame("Frame")
WorldMapFrame.ScrollContainer.GetCanvasScale = function() return 1 end
WorldMapFrame.canvas = NewFrame("Frame")
WorldMapFrame.GetCanvas = function() return WorldMapFrame.canvas end
WorldMapFrame.GetMapID = function() return 1411 end
WorldMapFrame.OnMapChanged = function() end
WorldMapFrame.shown = true
GameTooltip = NewFrame("GameTooltip", "GameTooltip")
NewFrame("Frame", "ContainerFrame1")
ItemRefTooltip = NewFrame("GameTooltip", "ItemRefTooltip")

function FireEvent(event, ...)
	for _, f in ipairs(frames) do
		if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
	end
end

-- Real-ish API
geterrorhandler = function() return function(e) print("ERRORHANDLER: " .. tostring(e)) end end
seterrorhandler = noop
securecallfunction = function(f, ...) return f(...) end
securecall = function(f, ...) if type(f) == "string" then f = _G[f] end return f(...) end
issecurevariable = function() return true end
hooksecurefunc = function(a, b, c)
	if type(a) == "string" then local orig = _G[a]; _G[a] = function(...) local r = { orig(...) }; b(...); return unpack(r) end
	else local orig = a[b]; a[b] = function(...) local r = { orig and orig(...) }; c(...); return unpack(r) end end
end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = p end return unpack(out) end
strmatch = string.match; strfind = string.find; format = string.format; tinsert = table.insert; tremove = table.remove
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strlower = string.lower; strupper = string.upper; strsub = string.sub; gsub = string.gsub; strrep = string.rep; strlen = string.len
max = math.max; min = math.min; floor = math.floor; ceil = math.ceil; abs = math.abs
tostringall = function(...) return ... end
GetLocale = function() return "frFR" end
GetTime = function() return os.clock() end
time = os.time; date = os.date
GetBuildInfo = function() return "12.1.0", "1", "", 120100 end
issecretvalue = function() return false end
UnitFullName = function() return "Nassim", "Forever" end
UnitName = function() return "Nassim" end
UnitNameUnmodified = UnitName
GetCurrentRegionName = function() return "EU" end
GetCurrentRegion = function() return 3 end
GetNormalizedRealmName = function() return "Forever" end
GetRealmName = function() return "Forever" end
UnitClass = function() return "Guerrier", "WARRIOR", 1 end
UnitRace = function() return "Orc", "Orc", 2 end
UnitFactionGroup = function() return "Horde" end
UnitLevel = function() return 12 end
UnitXP = function() return 500 end
UnitXPMax = function() return 2000 end
GetXPExhaustion = function() return 300 end
GetMaxPlayerLevel = function() return 60 end
GetMoney = function() return 12345 end
GetRealZoneText = function() return "Durotar" end
GetSubZoneText = function() return "" end
GetInstanceInfo = function() return "Durotar", "none", 0, "", 5, 0, false, 1 end
InCombatLockdown = function() return false end
IsShiftKeyDown = function() return false end
GetNumSavedInstances = function() return 0 end
GetNumLootItems = function() return 0 end
GetInboxNumItems = function() return 0 end
GetProfessions = function() return end
GetNetStats = function() return 0, 0, 40, 50 end
GetFramerate = function() return 60 end
GetInventoryItemDurability = function() return 50, 100 end
GetInventoryItemID = function() return nil end
GetAverageItemLevel = function() return 20, 19 end
GetPlayerFacing = function() return 0 end
GetCVar = function() return nil end
RequestRaidInfo = noop
GetNumSkillLines = function() return 0 end
NUM_CONTAINER_FRAMES = 13
IsInInstance = function() return false end
IsInGuild = function() return false end
CanMerchantRepair = function() return true end
GetRepairAllCost = function() return 500, true end
RepairAllItems = noop
MerchantFrame = NewFrame("Frame")
IsLoggedIn = function() return loggedIn end
PlaySound = noop
BreakUpLargeNumbers = function(n) return tostring(n) end
GetMoneyString = function(n) return tostring(n) .. "c" end
NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { WrapTextInColorCode = function(_, t) return t end } end })
SOUNDKIT = setmetatable({}, { __index = function() return 1 end })
Enum = setmetatable({ ItemQuality = { Poor = 0 }, LootSlotType = { Item = 1 }, BagIndex = { Backpack = 0, CharacterBankTab_1 = 6 }, TooltipDataType = { Item = 0, Unit = 2 } }, { __index = function() return Dummy end })
C_AddOns = { GetAddOnMetadata = function() return "dev" end, IsAddOnLoaded = function() return true end }
C_Timer = { After = function(_, f) end, NewTicker = function(_, f) return { Cancel = noop } end, NewTimer = function() return { Cancel = noop } end }
C_QuestLog = { GetNumQuestLogEntries = function() return 0 end, GetInfo = noop, IsComplete = function() return false end, GetLogIndexForQuestID = noop, IsQuestFlaggedCompleted = function() return false end, GetTitleForQuestID = noop, GetQuestObjectives = function() return {} end }
C_Map = { GetBestMapForUnit = function() return 1411 end, GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end, GetMapInfo = function() return { name = "Durotar" } end, GetMapWorldSize = function() return 1000, 700 end, CanSetUserWaypointOnMap = function() return true end, SetUserWaypoint = noop, HasUserWaypoint = function() return false end, ClearUserWaypoint = noop }
CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end
-- Fake projection: map (x, y) -> world (mapID*10 - y*1000, -x*1000) on Kalimdor.
C_Map.GetWorldPosFromMapPos = function(mapID, v) return 1, CreateVector2D(mapID * 10 - v.y * 1000, -v.x * 1000) end
C_Map.GetMapPosFromWorldPos = function(cont, v, mapID) if cont ~= 1 then return nil end return mapID, CreateVector2D(-v.y / 1000, (mapID * 10 - v.x) / 1000) end
C_Texture = { GetAtlasInfo = function() return nil end }
C_Container = { GetContainerNumSlots = function() return 16 end, GetContainerItemInfo = noop, GetContainerNumFreeSlots = function() return 10 end }
C_Item = { GetItemInfo = noop, GetItemNameByID = noop, IsEquippableItem = function() return false end, GetItemIconByID = noop, GetItemQualityByID = noop }
C_CVar = { GetCVar = function() return "0" end, SetCVar = noop }
C_CurrencyInfo = { GetCoinTextureString = function(n) return n .. "c" end }
C_NamePlate = { GetNamePlates = function() return {} end }
C_UnitAuras = { GetAuraDataByIndex = noop }
C_SuperTrack = { SetSuperTrackedUserWaypoint = noop }
TooltipDataProcessor = { AddTooltipPostCall = noop }
ChatFrame_AddMessageEventFilter = noop
SetItemRef = noop
Settings = { RegisterCanvasLayoutCategory = function() return { GetID = function() return 1 end, ID = 1 } end, RegisterCanvasLayoutSubcategory = function() return { GetID = function() return 2 end, ID = 2 } end, RegisterAddOnCategory = noop, OpenToCategory = noop }
InterfaceOptions_AddCategory = noop
UISpecialFrames = {}
setmetatable(_G, { __index = function(t, k) if type(k) == "string" and (k:match("Lib") or k:match("^Ace") or k:match("^ForeverCompanion")) then return nil end if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then return k end return Dummy end })

-- Loader for xml includes
local function loadLua(path, ...)
	local chunk, err = loadfile(root .. "/" .. path:gsub("\\", "/"))
	if not chunk then error(err) end
	return chunk(...)
end
local ns = {}
local function loadXml(path)
	local dir = path:match("^(.*)[/\\]") or ""
	local fh = io.open(root .. "/" .. path:gsub("\\", "/")); if not fh then error("missing " .. path) end; local text = fh:read("*a"):gsub("<!%-%-.-%-%->", "")
	for kind, file in text:gmatch('<(%a+) file="([^"]+)"') do
		local full = (dir ~= "" and dir .. "/" or "") .. file:gsub("\\", "/")
		if kind == "Script" then loadLua(full, "ForeverCompanion", ns) else loadXml(full) end
	end
end
local toc = io.open(root .. "/ForeverCompanion.toc"):read("*a")
for line in toc:gmatch("[^\n]+") do
	if not line:match("^#") and line:match("%S") then
		line = line:gsub("%s+$", "")
		if line:match("%.xml$") then loadXml(line) else loadLua(line, "ForeverCompanion", ns) end
	end
end
print("files loaded")
FireEvent("ADDON_LOADED", "ForeverCompanion")
loggedIn = true
FireEvent("PLAYER_LOGIN")
print("login done")
local FC = ns.FC
for name, m in FC:IterateModules() do print(name, m:IsEnabled()) end
FireEvent("PLAYER_ENTERING_WORLD")
FireEvent("PLAYER_XP_UPDATE")
FireEvent("QUEST_LOG_UPDATE")
FireEvent("MERCHANT_SHOW")
FireEvent("LOOT_OPENED")
-- slash commands
FC:SlashCommand("help")
FC:SlashCommand("way 45 62 Test")
FC:SlashCommand("note Coffre")
FC:SlashCommand("camp Feu")
FC:SlashCommand("route record test")
FC:SlashCommand("route note hello")
FC:SlashCommand("route stop")
FC:SlashCommand("find epee")
-- options table build
local opts = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("ForeverCompanion", "dialog", "ForeverCompanion-1.0")
print("options groups:")
local t = LibStub("AceConfigRegistry-3.0"):GetOptionsTable("ForeverCompanion")
local tbl = t("dialog", "Harness-1.0")
for k in pairs(tbl.args) do io.write(k, " ") end print()
local ok, err = pcall(function() LibStub("AceConfigRegistry-3.0"):ValidateOptionsTable(tbl, "ForeverCompanion") end)
print("validate", ok, err)
-- route encode/decode
local route = FC.db.global.Route.recorded["test"]
print("recorded steps", route and #route.steps)
local enc = ns.Encode(route)
print("roundtrip", ns.Decode(enc).id)
FC:SetModuleEnabled("Bags", false)
print("Bags", FC:GetModule("Bags"):IsEnabled())
print("ALL OK")
-- ===== Extended scenarios =====
FC:SetModuleEnabled("Bags", true)
-- Route engine with a test route
ns.RegisterRoute({ id = "t1", name = "Test", faction = "Horde", minLevel = 10, maxLevel = 15, steps = {
	{ "accept", quest = 1 }, { "goto", map = 1411, x = 0.5, y = 0.5, text = "here" }, { "turnin", quest = 1 }, { "level", level = 13 },
} })
local inLog = {}
C_QuestLog.GetLogIndexForQuestID = function(q) return inLog[q] end
local Route = FC:GetModule("Route")
Route:Advance()
print("route", Route.route and Route.route.id, FC.db.char.Route.step)
inLog[1] = 1
FireEvent("QUEST_ACCEPTED", 1)
print("after accept step", FC.db.char.Route.step, ns.GetWaypoint() and ns.GetWaypoint().title)
-- arrival on goto (player at 0.5,0.5 same as target)
FC:GetModule("Arrow"):Update()
print("after arrival step", FC.db.char.Route.step)
C_QuestLog.IsQuestFlaggedCompleted = function(q) return q == 1 end
Route:Advance()
print("after turnin step", FC.db.char.Route.step)
FC:SlashCommand("route lua t1")
-- Loot collector
GetInstanceInfo = function() return "Les Mortemines", "party", 1, "Normal", 5, 0, false, 36 end
FireEvent("ENCOUNTER_END", 1144, "Edwin VanCleef", 1, 5, 1)
GetNumLootItems = function() return 2 end
GetLootSlotType = function() return 1 end
GetLootSlotLink = function(i) return "|Hitem:" .. (i == 1 and 5193 or 5191) .. ":|h[x]|h" end
GetLootSourceInfo = function() return "Creature-0-1-36-1-639-0000AAAA", 1 end
FireEvent("LOOT_OPENED")
GetLootSourceInfo = function() return "Creature-0-1-36-1-1729-0000BBBB", 1 end
GetNumLootItems = function() return 1 end
FireEvent("LOOT_OPENED")
local inst = ns.CollectedInstances()[36]
for npcID, npc in pairs(inst.npcs) do print("npc", npcID, npc.kills, npc.looted, npc.boss) end
print("rate", ns.DropRate(36, 639, 5193))
local src = ns.ItemDropSources(5193)
print("sources", #src, src[1] and src[1].rate)
local exp = FC:GetModule("LootCollector"):Export()
FC:GetModule("LootCollector"):Import(exp)
print("kills after import", inst.npcs[639].kills)
FC:GetModule("LootCollector"):Import(exp)
-- Guide
local Guide = FC:GetModule("DungeonGuide")
local ok, err = pcall(function() Guide:Toggle() end)
print("guide open", ok, err)
if ok then
	local fails, pages = 0, 0
	local paths = { "home", "wishlist" }
	for _, key in ipairs(Guide.order) do
		local entry = Guide.list[key]
		paths[#paths + 1] = key
		paths[#paths + 1] = key .. ">trash"
		paths[#paths + 1] = key .. ">quests"
		for i in ipairs(Guide:Bosses(entry)) do paths[#paths + 1] = key .. ">b" .. i end
	end
	for _, p in ipairs(paths) do
		pages = pages + 1
		local ok2, err2 = pcall(Guide.Open, Guide, p)
		if not ok2 then fails = fails + 1 print("page FAIL", p, err2) end
	end
	local nq, nqa = 0, 0
	for _, key in ipairs(Guide.order) do nq = nq + #Guide:Quests(Guide.list[key]) nqa = nqa + #Guide:Quests(Guide.list[key], true) end
	print("guide quests mine/all", nq, nqa)
	Guide:Settings().allQuests = true
	for _, key in ipairs(Guide.order) do
		local ok3, err3 = pcall(Guide.Open, Guide, key .. ">quests")
		if not ok3 then fails = fails + 1 print("page FAIL all", key, err3) end
	end
	Guide:Settings().allQuests = false
	print("guide pages", pages, "fails", fails, "nav rows height", Guide.nav.child:GetHeight())
	Guide.search:SetText("vancleef")
	Guide.filter = "vancleef"
	print("search", pcall(Guide.RenderNav, Guide))
	Guide:GET_ITEM_INFO_RECEIVED()
end
local src = ns.ItemDropSources(5193)
print("db sources 5193", #src, src[1] and src[1].name, src[1] and src[1].rate, src[1] and src[1].where)
-- Quest assistant
local logQuests = { 823, 790 }
C_QuestLog.GetNumQuestLogEntries = function() return #logQuests end
C_QuestLog.GetInfo = function(i) return { questID = logQuests[i] } end
C_QuestLog.IsComplete = function(q) return q == 823 end
C_QuestLog.IsQuestFlaggedCompleted = function(q) return false end
ns.ClearWaypoint()
FC.db.char.Route.routeID = nil
ns.Routes = {}
Route:Advance()
local A = ns.QuestAssistant
print("assistant pickups", #A.pickups, "active", #A.active, "steps", #A.steps)
for i = 1, math.min(6, #A.steps) do print("  ", A:StepLine(A.steps[i])) end
local wp = ns.GetWaypoint()
print("arrow ->", wp and wp.title, wp and wp.owner, wp and wp.continent)
FC:GetModule("Arrow"):Update()
print("arrow dist", FC:GetModule("Arrow").frame.dist.text)
Route:MarkCurrentDone()
print("after skip ->", ns.GetWaypoint() and ns.GetWaypoint().title)
print("dungeons", #A:SuggestedDungeons())
-- Map pins
local Map = FC:GetModule("Map")
print("pins", pcall(Map.RefreshPins, Map))
-- Bags
local btn = NewFrame("Button")
btn.GetBagID = function() return 0 end
btn.GetID = function() return 1 end
btn.shown = true
ContainerFrame1.shown = true
ContainerFrame1.EnumerateValidItems = function() return ipairs({ btn }) end
C_Container.GetContainerItemInfo = function() return { hyperlink = "|Hitem:5193|h[x]|h", quality = 0, itemID = 5193 } end
print("bags", pcall(function() FC:GetModule("Bags"):RefreshVisible() end), btn.fcJunk and btn.fcJunk.shown)
-- Alts window
print("alts", pcall(function() FC:GetModule("Alts"):ShowWindow() end))
print("deaths", pcall(function() FireEvent("PLAYER_DEAD"); FC:SlashCommand("deaths") end))
print("dropexport", pcall(function() FC:SlashCommand("drops export") end))
-- Economy
local Eco = FC:GetModule("Economy")
GetMoney = function() return 20000 end
FireEvent("MERCHANT_SHOW")
FireEvent("PLAYER_MONEY")
GetMoney = function() return 15000 end
FireEvent("PLAYER_MONEY")
Eco:RecordPrice(5193, 12345, true)
Eco:RecordPrice(2589, 50, true)
Eco:Global().recipes["Nassim-Forever"] = { r1 = { name = "Linen Bandage", prof = "First Aid", out = 1251, n = 1, r = { 2589, 1 } } }
Eco:AddToShopping("Nassim-Forever", "r1", 3)
print("eco price", ns.AuctionPrice(5193), "cost", Eco:RecipeCost(Eco:Global().recipes["Nassim-Forever"].r1))
Eco:OnTooltip(GameTooltip, { id = 1251 })
for _, tab in ipairs({ "gold", "prices", "crafts", "shopping" }) do
	print("eco tab", tab, pcall(function() Eco:Toggle(tab) end))
end
Eco.filter = "lin"
print("eco filter", pcall(Eco.Render, Eco))
for _, c in ipairs{"hc", "hc panel", "hc check", "hc", "pvp", "pvp", "menu"} do
	print("cmd", c, pcall(FC.SlashCommand, FC, c))
end
print("hc danger", pcall(ns.HardcoreDanger, "target"))
print("eco scan", pcall(Eco.StartScan, Eco))
print("hub", pcall(ns.ToggleHub, UIParent), pcall(ns.ToggleHub))
print("END")
