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
	local s = self:Settings()
	local f = CreateFrame("Frame", "ForeverCompanionXPFrame", UIParent, "BackdropTemplate")
	f:SetSize(260, 58)
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0, 0, 0, 0.7)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetScript("OnDragStart", function(frame)
		if not self:Settings().locked then frame:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		self:Settings().point = { point, "UIParent", relPoint, x, y }
	end)

	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetPoint("TOPLEFT", 8, -8)
	bar:SetPoint("TOPRIGHT", -8, -8)
	bar:SetHeight(12)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(0.58, 0.0, 0.55)
	local rested = CreateFrame("StatusBar", nil, f)
	rested:SetAllPoints(bar)
	rested:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	rested:SetStatusBarColor(0.0, 0.39, 0.88, 0.5)
	rested:SetFrameLevel(bar:GetFrameLevel() - 1)
	local barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	barText:SetPoint("CENTER")

	local line1 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	line1:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
	line1:SetJustifyH("LEFT")
	local line2 = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -2)
	line2:SetJustifyH("LEFT")

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

	f.bar, f.rested, f.barText, f.line1, f.line2 = bar, rested, barText, line1, line2
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
	f.bar:SetMinMaxValues(0, max)
	f.bar:SetValue(xp)
	f.rested:SetMinMaxValues(0, max)
	f.rested:SetValue(math.min(max, xp + restedXP))
	f.barText:SetFormattedText("%s %d  -  %.1f%%", LEVEL, level, xp / max * 100)

	local elapsed = GetTime() - session.start
	local perHour = elapsed > 30 and session.gained / elapsed * 3600 or 0
	local remaining = max - xp
	local eta = perHour > 0 and remaining / perHour * 3600 or nil
	f.line1:SetFormattedText(L["XP/hour: %s  |  Level in: %s"], ns.FormatNumber(math.floor(perHour)), ns.FormatDuration(eta))

	local questXP, questCount = CompletedQuestXP()
	local restedPct = restedXP / max * 100
	f.line2:SetFormattedText(L["Rested: %.0f%%  |  Quests to turn in: %d (%s XP)"], restedPct, questCount, ns.FormatNumber(questXP))
	if questXP >= remaining and questCount > 0 then
		f.line2:SetTextColor(0.2, 1, 0.2)
	else
		f.line2:SetTextColor(1, 0.82, 0)
	end
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
