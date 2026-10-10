-- ForeverCompanion: leveling helpers (XP tracker window and quest automation).
local _, ns = ...
local L = ns.L

local Leveling = ns.NewModule("Leveling", {
	showTracker = true,
	locked = false,
	scale = 1,
	point = { "TOP", "UIParent", "TOP", 0, -120 },
	autoAccept = false,
	autoTurnIn = false,
	skipTrivial = true,
	pickBestReward = false,
})

local session = { start = 0, gained = 0, lastXP = 0, lastMax = 0, lastLevel = 0 }

local function MaxLevel()
	return GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or GetMaxPlayerLevel() or 60
end

local function CompletedQuestXP()
	local total, count = 0, 0
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and not info.isHeader and info.questID and C_QuestLog.IsComplete(info.questID) then
			count = count + 1
			local xp = GetQuestLogRewardXP and GetQuestLogRewardXP(info.questID) or 0
			total = total + (xp or 0)
		end
	end
	return total, count
end

---------------------------------------------------------------------------
-- XP tracker window
---------------------------------------------------------------------------
function Leveling:CreateTracker()
	if self.frame then return end
	local UI, C = ns.UI, ns.UI.COLORS
	local f = UI.Panel("ForeverCompanionXPFrame", 360, 92, function() return self:Settings() end)

	f.level = UI.Text(f, 16, C.gold)
	f.level:SetPoint("TOPLEFT", 14, -10)
	f.rate = UI.Text(f, 13, C.text, "RIGHT")
	f.rate:SetPoint("TOPRIGHT", -12, -12)

	local bar = UI.Bar(f, 20, C.xp)
	bar:SetPoint("TOPLEFT", 14, -34)
	bar:SetPoint("TOPRIGHT", -12, -34)
	-- Rested XP: a lighter bar under the XP bar.
	local rested = CreateFrame("StatusBar", nil, bar)
	rested:SetPoint("TOPLEFT", 1, -1)
	rested:SetPoint("BOTTOMRIGHT", -1, 1)
	rested:SetStatusBarTexture(UI.MEDIA .. "Bar")
	rested:SetStatusBarColor(C.rested[1], C.rested[2], C.rested[3], C.rested[4])
	rested:SetFrameLevel(bar.bar:GetFrameLevel() - 1)
	bar.text:SetFontObject(UI.Font(12))

	f.line1 = UI.Text(f, 12, C.muted)
	f.line1:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -7)
	f.line1:SetPoint("RIGHT", -12, 0)
	f.line1:SetWordWrap(false)

	f:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["XP tracker"])
		GameTooltip:AddDoubleLine(L["Session time"], ns.FormatDuration(GetTime() - session.start), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddDoubleLine(L["XP gained this session"], ns.FormatNumber(session.gained), 1, 1, 1, 1, 1, 1)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(L["Right-click to reset the session"], 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then self:ResetSession() end
	end)

	f.bar, f.rested = bar, rested
	self.frame = f
	self:ApplyLayout()
end

function Leveling:ApplyLayout()
	local f, s = self.frame, self:Settings()
	if not f then return end
	f:SetScale(s.scale)
	f:ClearAllPoints()
	local p = s.point
	f:SetPoint(p[1], UIParent, p[3], p[4], p[5])
	f:SetShown(s.showTracker and UnitLevel("player") < MaxLevel())
end

function Leveling:ResetSession()
	session.start = GetTime()
	session.gained = 0
	session.lastXP = UnitXP("player")
	session.lastMax = UnitXPMax("player")
	session.lastLevel = UnitLevel("player")
	self:UpdateTracker()
end

function Leveling:PLAYER_XP_UPDATE()
	local xp, max, level = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
	if ns.AnySecret(xp, max) then return end
	if level > session.lastLevel then
		session.gained = session.gained + (session.lastMax - session.lastXP) + xp
	elseif xp > session.lastXP then
		session.gained = session.gained + (xp - session.lastXP)
	end
	session.lastXP, session.lastMax, session.lastLevel = xp, max, level
	self:UpdateTracker()
end

function Leveling:UpdateTracker()
	local f = self.frame
	if not f then return end
	local level = UnitLevel("player")
	if level >= MaxLevel() then
		f:Hide()
		return
	end
	local xp, max = UnitXP("player"), UnitXPMax("player")
	if ns.AnySecret(xp, max) or max == 0 then return end
	local restedXP = GetXPExhaustion() or 0
	local C = ns.UI.COLORS
	f.bar:SetValue(xp, max)
	f.rested:SetMinMaxValues(0, max)
	f.rested:SetValue(math.min(max, xp + restedXP))
	f.bar.text:SetFormattedText("%s / %s   (%.1f%%)", ns.FormatNumber(xp), ns.FormatNumber(max), xp / max * 100)
	f.level:SetFormattedText("%s %d", LEVEL, level)

	local elapsed = GetTime() - session.start
	local perHour = elapsed > 30 and session.gained / elapsed * 3600 or 0
	local remaining = max - xp
	local eta = perHour > 0 and remaining / perHour * 3600 or nil
	f.rate:SetText(ns.UI.Colorize(ns.FormatNumber(math.floor(perHour)), C.text) .. ns.UI.Colorize(" " .. L["XP/h"], C.muted))

	local questXP, questCount = CompletedQuestXP()
	local parts = {
		L["Level in:"] .. " " .. ns.UI.Colorize(ns.FormatDuration(eta), C.text),
		L["Rested:"] .. " " .. ns.UI.Colorize(string.format("%.0f%%", restedXP / max * 100), { 0.45, 0.7, 1 }),
	}
	if questCount > 0 then
		local color = questXP >= remaining and C.good or C.gold
		parts[#parts + 1] = ns.UI.Colorize(string.format(L["%d to turn in (+%s XP)"], questCount, ns.FormatNumber(questXP)), color)
	end
	f.line1:SetText(table.concat(parts, ns.UI.Colorize("  ·  ", C.muted)))
end

---------------------------------------------------------------------------
-- Quest automation (hold Shift to skip)
---------------------------------------------------------------------------
local function AutomationAllowed()
	return not IsShiftKeyDown()
end

function Leveling:QUEST_DETAIL()
	local s = self:Settings()
	if not (s.autoAccept and AutomationAllowed()) then return end
	if QuestGetAutoAccept and QuestGetAutoAccept() then
		AcknowledgeAutoAcceptQuest()
	else
		AcceptQuest()
	end
end

function Leveling:QUEST_ACCEPT_CONFIRM()
	if self:Settings().autoAccept and AutomationAllowed() then ConfirmAcceptQuest() end
end

function Leveling:QUEST_PROGRESS()
	if self:Settings().autoTurnIn and AutomationAllowed() and IsQuestCompletable() then
		CompleteQuest()
	end
end

function Leveling:QUEST_COMPLETE()
	local s = self:Settings()
	if not (s.autoTurnIn and AutomationAllowed()) then return end
	local choices = GetNumQuestChoices()
	if choices <= 1 then
		GetQuestReward(choices)
	elseif s.pickBestReward then
		local best, bestPrice = 1, -1
		for i = 1, choices do
			local link = GetQuestItemLink("choice", i)
			local price = link and select(11, C_Item.GetItemInfo(link)) or 0
			if price and price > bestPrice then best, bestPrice = i, price end
		end
		GetQuestReward(best)
	end
end

function Leveling:GOSSIP_SHOW()
	local s = self:Settings()
	if not AutomationAllowed() then return end
	if s.autoTurnIn then
		for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
			if quest.isComplete then
				C_GossipInfo.SelectActiveQuest(quest.questID)
				return
			end
		end
	end
	if s.autoAccept then
		for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
			if not (s.skipTrivial and quest.isTrivial) then
				C_GossipInfo.SelectAvailableQuest(quest.questID)
				return
			end
		end
	end
end

function Leveling:QUEST_GREETING()
	local s = self:Settings()
	if not AutomationAllowed() then return end
	if s.autoTurnIn then
		for i = 1, GetNumActiveQuests() do
			local _, isComplete = GetActiveTitle(i)
			if isComplete then
				SelectActiveQuest(i)
				return
			end
		end
	end
	if s.autoAccept then
		for i = 1, GetNumAvailableQuests() do
			local isTrivial = GetAvailableQuestInfo and GetAvailableQuestInfo(i)
			if not (s.skipTrivial and isTrivial) then
				SelectAvailableQuest(i)
				return
			end
		end
	end
end

---------------------------------------------------------------------------
function Leveling:OnEnable()
	self:CreateTracker()
	self:ResetSession()
	self:ApplyLayout()
	self:RegisterEvent("PLAYER_XP_UPDATE")
	self:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, function() self:ApplyLayout(); self:UpdateTracker() end) end)
	self:RegisterEvent("UPDATE_EXHAUSTION", "UpdateTracker")
	self:RegisterEvent("QUEST_LOG_UPDATE", "UpdateTracker")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_ACCEPT_CONFIRM")
	self:RegisterEvent("QUEST_PROGRESS")
	self:RegisterEvent("QUEST_COMPLETE")
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("QUEST_GREETING")
	self.ticker = C_Timer.NewTicker(5, function() self:UpdateTracker() end)
end

function Leveling:OnDisable()
	if self.ticker then self.ticker:Cancel() end
	if self.frame then self.frame:Hide() end
end

function Leveling:OnProfileChanged()
	self:ApplyLayout()
end

function Leveling:GetOptions()
	local get, set = ns.ProfileAccessors("Leveling", function() self:ApplyLayout(); self:UpdateTracker() end)
	return {
		get = get, set = set,
		args = {
			trackerHeader = { type = "header", order = 1, name = L["XP tracker"] },
			showTracker = { type = "toggle", order = 2, name = L["Show the XP tracker"] },
			locked = { type = "toggle", order = 3, name = L["Lock position"] },
			scale = { type = "range", order = 4, name = L["Scale"], min = 0.5, max = 2, step = 0.05 },
			questHeader = { type = "header", order = 10, name = L["Quest automation"] },
			questNote = { type = "description", order = 11, name = L["Hold Shift while talking to an NPC to skip automation."] },
			autoAccept = { type = "toggle", order = 12, name = L["Accept quests automatically"] },
			autoTurnIn = { type = "toggle", order = 13, name = L["Turn in quests automatically"] },
			skipTrivial = { type = "toggle", order = 14, name = L["Ignore grey (trivial) quests"] },
			pickBestReward = { type = "toggle", order = 15, width = "full", name = L["When there is a reward choice, take the one that sells for the most"] },
		},
	}
end
