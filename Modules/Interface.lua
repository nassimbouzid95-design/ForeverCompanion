-- ForeverCompanion: interface improvements (info bar, tooltips, chat).
local _, ns = ...
local L = ns.L

local UI = ns.NewModule("Interface", {
	infoBar = true,
	infoLocked = false,
	infoPoint = { "BOTTOM", "UIParent", "BOTTOM", 0, 2 },
	infoScale = 1,
	tooltipItemLevel = true,
	tooltipOwners = true,
	tooltipDrops = true,
	tooltipNPC = true,
	chatTimestamps = false,
	chatURLs = true,
})

---------------------------------------------------------------------------
-- Info bar: gold, free bag slots, durability, latency, FPS.
---------------------------------------------------------------------------
local function FreeBagSlots()
	local free, total = 0, 0
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
		total = total + (C_Container.GetContainerNumSlots(bag) or 0)
	end
	return free, total
end

function ns.LowestDurability()
	local lowest = 1
	for slot = 1, 19 do
		local current, max = GetInventoryItemDurability(slot)
		if current and max and max > 0 then lowest = math.min(lowest, current / max) end
	end
	return lowest
end

local function Colored(value, low, high, text)
	local color = value <= low and "ffff4444" or value <= high and "ffffd100" or "ff33ff33"
	return "|c" .. color .. text .. "|r"
end

function UI:CreateInfoBar()
	if self.bar then return end
	local f = CreateFrame("Frame", "ForeverCompanionInfoBar", UIParent, "BackdropTemplate")
	f:SetSize(420, 20)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	f:SetBackdropColor(0, 0, 0, 0.55)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(frame) if not self:Settings().infoLocked then frame:StartMoving() end end)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		self:Settings().infoPoint = { point, "UIParent", relPoint, x, y }
	end)
	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	f.text = text
	local elapsed = 1
	f:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 1 then return end
		elapsed = 0
		self:UpdateInfoBar()
	end)
	self.bar = f
end

function UI:UpdateInfoBar()
	local f = self.bar
	local free, total = FreeBagSlots()
	local durability = ns.LowestDurability()
	local _, _, home, world = GetNetStats()
	local fps = GetFramerate()
	f.text:SetText(table.concat({
		ns.FormatMoney(GetMoney()),
		L["Bags"] .. " " .. Colored(free, 2, 8, free .. "/" .. total),
		L["Durability"] .. " " .. Colored(durability * 100, 20, 50, string.format("%d%%", durability * 100)),
		Colored(-math.max(home, world), -300, -150, math.max(home, world) .. " ms"),
		Colored(fps, 20, 40, string.format("%d fps", fps)),
	}, "   "))
	f:SetWidth(f.text:GetStringWidth() + 24)
end

function UI:ApplyInfoBar()
	local s = self:Settings()
	if s.infoBar then
		self:CreateInfoBar()
		self.bar:SetScale(s.infoScale)
		self.bar:ClearAllPoints()
		self.bar:SetPoint(s.infoPoint[1], UIParent, s.infoPoint[3], s.infoPoint[4], s.infoPoint[5])
		self.bar:Show()
	elseif self.bar then
		self.bar:Hide()
	end
end

---------------------------------------------------------------------------
-- Tooltips
---------------------------------------------------------------------------
local tooltipHooked = false

local function OnItemTooltip(tooltip, data)
	if not UI:IsEnabled() or tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
	local s = UI:Settings()
	local itemID = data and data.id
	if not itemID or ns.IsSecret(itemID) then return end

	if s.tooltipItemLevel then
		local _, link = tooltip:GetItem()
		if link and not ns.IsSecret(link) and C_Item.IsEquippableItem(link) then
			local level = C_Item.GetDetailedItemLevelInfo(link)
			if level and level > 1 then
				tooltip:AddLine(string.format(L["Item level %d"], level), 1, 0.82, 0)
			end
		end
	end

	if s.tooltipDrops and ns.ItemDropSources then
		local sources = ns.ItemDropSources(itemID)
		for i = 1, math.min(3, #sources) do
			local src = sources[i]
			local rate = src.rate and string.format("%.1f%%", src.rate) or "?"
			tooltip:AddDoubleLine(
				string.format("|cff33ccff%s|r %s", L["Drop:"], src.name),
				string.format("%s |cff888888(%d %s, %s)|r", rate, src.kills, L["kills"], ns.InstanceName(src.instanceID)),
				1, 1, 1, 1, 1, 1)
		end
	end

	if s.tooltipOwners and ns.ItemOwners then
		local owners = ns.ItemOwners(itemID)
		if #owners > 0 then
			local total = 0
			for _, o in ipairs(owners) do
				total = total + o.bags + o.bank + o.mail
				local parts = {}
				if o.bags > 0 then parts[#parts + 1] = L["bags"] .. " " .. o.bags end
				if o.bank > 0 then parts[#parts + 1] = L["bank"] .. " " .. o.bank end
				if o.mail > 0 then parts[#parts + 1] = L["mail"] .. " " .. o.mail end
				tooltip:AddDoubleLine(ns.ClassColored(o.name, o.class), table.concat(parts, ", "), 1, 1, 1, 0.8, 0.8, 0.8)
			end
			if #owners > 1 then tooltip:AddDoubleLine(L["Total"], total, 1, 0.82, 0, 1, 1, 1) end
		end
	end
end

local function OnUnitTooltip(tooltip)
	if not UI:IsEnabled() or not UI:Settings().tooltipNPC or tooltip ~= GameTooltip then return end
	local _, unit = tooltip:GetUnit()
	if not unit or ns.IsSecret(unit) then return end
	local guid = UnitGUID(unit)
	local npcID = ns.NPCIDFromGUID(guid)
	if not npcID then return end
	local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	local data = ns.CollectedInstances and ns.CollectedInstances()[instanceID]
	local npc = data and data.npcs[npcID]
	if npc and npc.kills > 0 then
		local count = 0
		for _ in pairs(npc.items) do count = count + 1 end
		tooltip:AddLine(string.format(L["%d kills recorded, %d different items"], npc.kills, count), 0.2, 0.8, 1)
	end
end

function UI:HookTooltips()
	if tooltipHooked or not TooltipDataProcessor then return end
	tooltipHooked = true
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end

---------------------------------------------------------------------------
-- Chat: clickable links for URLs.
---------------------------------------------------------------------------
local URL_PATTERNS = {
	"(https?://[%w_%-%.%%/~#&=%?:+]+)",
	"(www%.[%w_%-%.%%/~#&=%?:+]+)",
	"(discord%.gg/[%w]+)",
}

local function URLFilter(_, _, msg, ...)
	if not UI:IsEnabled() or not UI:Settings().chatURLs or ns.IsSecret(msg) or type(msg) ~= "string" then return false end
	local changed = false
	for _, pattern in ipairs(URL_PATTERNS) do
		msg = msg:gsub(pattern, function(url)
			changed = true
			return "|cff33ccff|Haddon:ForeverCompanion:" .. url .. "|h[" .. url .. "]|h|r"
		end)
	end
	if changed then return false, msg, ... end
	return false
end

local CHAT_EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
	"CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}

local chatHooked = false
function UI:HookChat()
	if chatHooked then return end
	chatHooked = true
	-- Midnight moved chat helpers into ChatFrameUtil; older clients still have the global.
	local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if not addFilter then return end
	for _, event in ipairs(CHAT_EVENTS) do
		addFilter(event, URLFilter)
	end
	-- Clicking our link opens a copy box.
	hooksecurefunc("SetItemRef", function(link)
		local url = link and type(link) == "string" and link:match("^addon:ForeverCompanion:(.+)$")
		if url then ns.ShowCopyBox(L["Copy the link"], url) end
	end)
end

function UI:ApplyChat()
	local s = self:Settings()
	if s.chatTimestamps then
		C_CVar.SetCVar("showTimestamps", "%H:%M ")
	elseif C_CVar.GetCVar("showTimestamps") == "%H:%M " then
		C_CVar.SetCVar("showTimestamps", "none")
	end
end

---------------------------------------------------------------------------
function UI:OnEnable()
	self:ApplyInfoBar()
	self:HookTooltips()
	self:HookChat()
	self:ApplyChat()
end

function UI:OnDisable()
	if self.bar then self.bar:Hide() end
end

function UI:OnProfileChanged()
	self:ApplyInfoBar()
	self:ApplyChat()
end

function UI:GetOptions()
	local get, set = ns.ProfileAccessors("Interface", function()
		self:ApplyInfoBar()
		self:ApplyChat()
	end)
	return {
		get = get, set = set,
		args = {
			barHeader = { type = "header", order = 1, name = L["Info bar"] },
			infoBar = { type = "toggle", order = 2, name = L["Show the info bar"] },
			infoLocked = { type = "toggle", order = 3, name = L["Lock position"] },
			infoScale = { type = "range", order = 4, name = L["Scale"], min = 0.5, max = 2, step = 0.05 },
			tipHeader = { type = "header", order = 10, name = L["Tooltips"] },
			tooltipItemLevel = { type = "toggle", order = 11, name = L["Item level"] },
			tooltipOwners = { type = "toggle", order = 12, name = L["Who owns it on my characters"] },
			tooltipDrops = { type = "toggle", order = 13, name = L["Where it drops and how often"] },
			tooltipNPC = { type = "toggle", order = 14, name = L["Kills recorded on creatures"] },
			chatHeader = { type = "header", order = 20, name = L["Chat"] },
			chatTimestamps = { type = "toggle", order = 21, name = L["Timestamps"] },
			chatURLs = { type = "toggle", order = 22, name = L["Clickable web links"] },
		},
	}
end
