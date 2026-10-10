-- ForeverCompanion: optimised XP route (step-by-step guide) and route recorder.
local _, ns = ...
local L = ns.L

local Route = ns.NewModule("Route", {
	showWindow = true,
	locked = false,
	scale = 1,
	point = { "RIGHT", "UIParent", "RIGHT", -60, 120 },
	style = "quests",
	autoArrow = true,
	assistantCount = 5,
	questLevelsBelow = 5,
	questLevelsAbove = 2,
	suggestDungeons = true,
}, {
	recorded = {}, -- [name] = route
	imported = {}, -- list of routes pasted by the player
})
ns.RegisterDefaults("char", "Route", {
	routeID = nil,
	step = 1,
	manualDone = {}, -- ["routeID:step"] = true
	finished = {},   -- [routeID] = true
	recording = nil, -- route being recorded
})

local OWNER = "route"

local function CharState()
	return ns.FC.db.char.Route
end

local function PlayerInfo()
	local faction = UnitFactionGroup("player")
	local _, race = UnitRace("player")
	local _, class = UnitClass("player")
	return faction, race, class, UnitLevel("player")
end

local function QuestTitle(step)
	local title = step.quest and C_QuestLog.GetTitleForQuestID(step.quest)
	return title or step.name or (step.quest and ("#" .. step.quest)) or ""
end

local function InLog(questID)
	return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
end

local function TurnedIn(questID)
	return C_QuestLog.IsQuestFlaggedCompleted(questID)
end

---------------------------------------------------------------------------
-- Quest assistant: when no written route fits, the next steps come from the quest database
-- (quests you can pick up, objectives of quests in your log, quests ready to turn in), sorted by distance.
---------------------------------------------------------------------------
local Assistant = { pickups = {}, active = {}, steps = {}, ignored = {} }
ns.QuestAssistant = Assistant

local function HasBit(mask, bitValue)
	return mask % (bitValue + bitValue) >= bitValue
end

local exclusiveGroups
local function ExclusiveGroups()
	if exclusiveGroups then return exclusiveGroups end
	exclusiveGroups = {}
	for id, q in pairs(ns.QuestDB or {}) do
		local group = q[15]
		if group and group > 0 then
			exclusiveGroups[group] = exclusiveGroups[group] or {}
			table.insert(exclusiveGroups[group], id)
		end
	end
	return exclusiveGroups
end

function Assistant:Title(questID)
	local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
	if title and title ~= "" and not ns.IsSecret(title) then return title end
	local q = ns.QuestDB[questID]
	return q and q[7] or ("#" .. questID)
end

function Assistant:IsDone(questID)
	local done = self.done[questID]
	if done == nil then
		done = C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
		self.done[questID] = done
	end
	return done
end

-- Heavy pass: which quests can this character pick up now, and which are in the log. Runs on quest events.
function Assistant:Rebuild()
	local db = ns.QuestDB
	if not db then return end
	self.done = {}
	if C_QuestLog.GetAllCompletedQuestIDs then
		for _, id in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do self.done[id] = true end
	end
	local _, _, raceID = UnitRace("player")
	local _, _, classID = UnitClass("player")
	local faction = UnitFactionGroup("player")
	local side = faction == "Alliance" and 1 or faction == "Horde" and 2 or 0
	local raceBit = raceID and raceID >= 1 and raceID <= 8 and 2 ^ (raceID - 1) or nil
	local classBit = classID and 2 ^ (classID - 1)
	local level = UnitLevel("player")
	local s = Route:Settings()

	wipe(self.active)
	local inLog = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and info.questID and not info.isHeader then
			inLog[info.questID] = true
			if db[info.questID] then
				self.active[#self.active + 1] = { id = info.questID, complete = C_QuestLog.IsComplete(info.questID) }
			end
		end
	end

	wipe(self.pickups)
	local groups = ExclusiveGroups()
	for id, q in pairs(db) do
		local qLevel = q[1] > 0 and q[1] or level
		if not inLog[id] and q[2] <= level and qLevel >= level - s.questLevelsBelow and qLevel <= level + s.questLevelsAbove
			and (q[6] == 0 or q[6] == side)
			and (q[3] == 0 or not raceBit or HasBit(q[3], raceBit))
			and (q[4] == 0 or not classBit or HasBit(q[4], classBit))
			and (q[5] == 0 or (q[5] > 0 and self:IsDone(q[5])) or (q[5] < 0 and inLog[-q[5]]))
			and not self:IsDone(id) then
			local ok = true
			local group = q[15] and q[15] > 0 and groups[q[15]]
			if group then
				for _, other in ipairs(group) do
					if other ~= id and (inLog[other] or self:IsDone(other)) then ok = false break end
				end
			end
			if ok then self.pickups[#self.pickups + 1] = id end
		end
	end
end

local function Nearest(continent, px, py, cont, x, y)
	if cont ~= continent then return 1e6 end
	local dx, dy = x - px, y - py
	return math.sqrt(dx * dx + dy * dy)
end

-- Light pass: distances from the player, best steps first. Runs every few seconds.
function Assistant:Sort()
	local db = ns.QuestDB
	local steps = wipe(self.steps)
	local continent, px, py = ns.PlayerWorldPosition()
	if not continent then
		-- Position unknown (in an instance): keep the order by level.
		continent, px, py = -1, 0, 0
	end
	local function add(kind, id, cont, x, y, weight)
		if self.ignored[kind .. id] then return end
		local dist = Nearest(continent, px, py, cont, x, y)
		steps[#steps + 1] = { kind = kind, id = id, cont = cont, x = x, y = y, dist = dist, score = dist * weight }
	end
	for _, a in ipairs(self.active) do
		local q = db[a.id]
		if a.complete then
			add("turnin", a.id, q[11], q[12], q[13], 0.6)
		else
			local objectives, best, bx, by, bc = q[14], nil, nil, nil, nil
			for i = 1, #objectives, 3 do
				local d = Nearest(continent, px, py, objectives[i], objectives[i + 1], objectives[i + 2])
				if not best or d < best then best, bc, bx, by = d, objectives[i], objectives[i + 1], objectives[i + 2] end
			end
			if bc then add("complete", a.id, bc, bx, by, 0.85) end
		end
	end
	for _, id in ipairs(self.pickups) do
		local q = db[id]
		add("accept", id, q[8], q[9], q[10], 1)
	end
	table.sort(steps, function(a, b) return a.score < b.score end)
	-- A quest the player clicked stays first until it is done.
	if self.pinned then
		for i, step in ipairs(steps) do
			if step.kind .. step.id == self.pinned then
				table.remove(steps, i)
				table.insert(steps, 1, step)
				break
			end
			if i == #steps then self.pinned = nil end
		end
	end
	return steps
end

function Assistant:Best()
	return self.steps[1]
end

function Assistant:StepLine(step)
	local q = ns.QuestDB[step.id]
	local color = step.kind == "turnin" and "ff33ff33" or step.kind == "complete" and "ff66ccff" or "ffffd100"
	local label = step.kind == "turnin" and L["Turn in"] or step.kind == "complete" and L["Do"] or L["Accept"]
	local dist = step.dist >= 1e6 and L[ns.CONTINENT_NAMES[step.cont] or "Kalimdor"] or string.format(L["%d yards"], step.dist)
	return string.format("|c%s%s|r [%d] %s |cff888888- %s|r", color, label, q[1] > 0 and q[1] or UnitLevel("player"), self:Title(step.id), dist)
end

-- Dungeons that fit the player's level, nearest entrance first.
function Assistant:SuggestedDungeons()
	local level = UnitLevel("player")
	local continent, px, py = ns.PlayerWorldPosition()
	local list, seen = {}, {}
	for _, entry in ipairs(ns.InstanceDB or {}) do
		local where = entry.id and ns.Instances[entry.id]
		if entry.kind == "dungeon" and level >= entry.min - 2 and level <= entry.max - 2 and where and not seen[entry.id] then
			seen[entry.id] = true
			local cont, wx, wy = ns.MapToWorld(where.zone, where.x, where.y)
			local dist = (cont and continent) and Nearest(continent, px, py, cont, wx, wy) or 1e6
			list[#list + 1] = { entry = entry, where = where, dist = dist }
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	return list
end

---------------------------------------------------------------------------
-- Engine
---------------------------------------------------------------------------
function Route:AllRoutes()
	local faction, race, class = PlayerInfo()
	return ns.MatchingRoutes(faction, race, class, self:Settings().style, self:Global().imported)
end

function Route:FindRoute(id)
	for _, r in ipairs(ns.Routes) do if r.id == id then return r end end
	for _, r in ipairs(self:Global().imported) do if r.id == id then return r end end
end

function Route:ChooseRoute()
	local state = CharState()
	local level = UnitLevel("player")
	local current = state.routeID and self:FindRoute(state.routeID)
	if current and not state.finished[current.id] and level <= current.maxLevel then
		return current
	end
	for _, route in ipairs(self:AllRoutes()) do
		if not state.finished[route.id] and level >= route.minLevel and level <= route.maxLevel then
			if state.routeID ~= route.id then
				state.routeID = route.id
				state.step = 1
			end
			return route
		end
	end
	state.routeID = nil
	return nil
end

function Route:IsStepDone(route, index)
	local step = route.steps[index]
	local kind = step[1]
	if CharState().manualDone[route.id .. ":" .. index] then return true end
	if kind == "accept" then
		return InLog(step.quest) or TurnedIn(step.quest)
	elseif kind == "complete" then
		return TurnedIn(step.quest) or (InLog(step.quest) and C_QuestLog.IsComplete(step.quest))
	elseif kind == "turnin" then
		return TurnedIn(step.quest)
	elseif kind == "level" then
		return UnitLevel("player") >= step.level
	end
	return false
end

-- Moves past every step already done (quests you did out of order are skipped automatically).
function Route:Advance()
	local route = self:ChooseRoute()
	self.route = route
	if not route then
		self.skipped = 0
		Assistant:Rebuild()
		self:Refresh()
		if ns.RefreshMapPins then ns.RefreshMapPins() end
		return
	end
	local state = CharState()
	local skipped = 0
	while state.step <= #route.steps and self:IsStepDone(route, state.step) do
		state.step = state.step + 1
		skipped = skipped + 1
	end
	if state.step > #route.steps then
		state.finished[route.id] = true
		ns.Print(string.format(L["Route finished: %s"], route.name or route.id))
		PlaySound(SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 or 3093)
		state.routeID = nil
		return self:Advance()
	end
	if skipped > 0 then PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE or 618) end
	self:UpdateWaypoint()
	self:UpdateWindow()
end

function Route:CurrentStep()
	if not self.route then return nil end
	return self.route.steps[CharState().step], CharState().step
end

-- Re-sorts the assistant by distance and points the arrow at its best step.
function Route:Refresh()
	if self.route then return end
	Assistant:Sort()
	self:UpdateWaypoint()
	self:UpdateWindow()
end

function Route:UpdateWaypoint()
	if not self.route then
		-- Never take over a waypoint the player or the guide placed.
		local current = ns.GetWaypoint()
		if current and current.owner ~= OWNER then return end
		local best = Assistant:Best()
		if best and best.dist < 1e6 and self:Settings().autoArrow then
			if not ns.SameWaypoint(best.cont, best.x, best.y) then
				ns.SetWorldWaypoint(best.cont, best.x, best.y, Assistant:Title(best.id), OWNER)
			end
		elseif self:Settings().autoArrow then
			ns.ClearWaypoint(OWNER)
		end
		return
	end
	local step = self:CurrentStep()
	if step and step.map and step.x and step.y and self:Settings().autoArrow then
		ns.SetWaypoint(step.map, step.x, step.y, self:StepText(step, true), OWNER)
	else
		ns.ClearWaypoint(OWNER)
	end
end

function Route:MarkCurrentDone()
	if not self.route then
		-- Assistant: skip this target until the next reload.
		local best = Assistant:Best()
		if best then Assistant.ignored[best.kind .. best.id] = true end
		self:Refresh()
		return
	end
	local step, index = self:CurrentStep()
	if not step then return end
	CharState().manualDone[self.route.id .. ":" .. index] = true
	self:Advance()
end

function Route:Back()
	local state = CharState()
	if not self.route or state.step <= 1 then return end
	state.step = state.step - 1
	CharState().manualDone[self.route.id .. ":" .. state.step] = nil
	self:UpdateWaypoint()
	self:UpdateWindow()
end

ns.arrivalCallbacks[OWNER] = function()
	if not Route.route then return end -- assistant: the next quest event moves the arrow
	local step = Route:CurrentStep()
	if step and step[1] == "goto" then
		Route:MarkCurrentDone()
	else
		ns.ClearWaypoint(OWNER)
	end
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local KIND_LABEL = {
	["goto"] = L["Go to"],
	accept = L["Accept"],
	complete = L["Do"],
	turnin = L["Turn in"],
	level = L["Level"],
	train = L["Train"],
	dungeon = L["Dungeon"],
	note = L["Note"],
}
local KIND_COLOR = {
	["goto"] = "ffffffff", accept = "ffffd100", complete = "ff66ccff", turnin = "ff33ff33",
	level = "ffff9933", train = "ffcc99ff", dungeon = "ffff6666", note = "ffaaaaaa",
}

function Route:StepText(step, short)
	local kind = step[1]
	local body
	if kind == "accept" or kind == "complete" or kind == "turnin" then
		body = QuestTitle(step)
		if step.npc and not short then body = body .. " (" .. step.npc .. ")" end
	elseif kind == "level" then
		body = string.format(L["Reach level %d"], step.level)
	elseif kind == "dungeon" then
		body = ns.InstanceName(step.instance)
	else
		body = step.text or ""
	end
	if short then return body end
	local label = string.format("|c%s%s|r", KIND_COLOR[kind] or "ffffffff", KIND_LABEL[kind] or kind)
	local text = label .. " : " .. body
	if step.text and (kind == "accept" or kind == "complete" or kind == "turnin" or kind == "level" or kind == "dungeon") then
		text = text .. "\n|cffbbbbbb" .. step.text .. "|r"
	end
	if kind == "complete" and step.quest and InLog(step.quest) then
		for _, obj in ipairs(C_QuestLog.GetQuestObjectives(step.quest) or {}) do
			if obj.text and not ns.IsSecret(obj.text) then
				text = text .. "\n" .. (obj.finished and "|cff33ff33" or "|cffffffff") .. "- " .. obj.text .. "|r"
			end
		end
	end
	if step.map and step.x then
		text = text .. string.format("\n|cff888888%s %.1f, %.1f|r", ns.MapName(step.map), step.x * 100, step.y * 100)
	end
	return text
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local UI = ns.UI
local C = UI.COLORS
local TAG = {
	accept = { L["Accept"], C.gold },
	complete = { L["Do"], { 0.4, 0.8, 1 } },
	turnin = { L["Turn in"], C.good },
}

function Route:CreateWindow()
	if self.frame then return end
	local f = UI.Panel("ForeverCompanionRouteFrame", 360, 200, function() return self:Settings() end)

	f.title = UI.Text(f, 16, C.gold)
	f.title:SetPoint("TOPLEFT", 14, -10)
	f.title:SetPoint("RIGHT", -70, 0)
	f.title:SetWordWrap(false)
	f.progress = UI.Text(f, 12, C.muted, "RIGHT")
	f.progress:SetPoint("TOPRIGHT", -12, -13)

	f.body = UI.Text(f, 13)
	f.body:SetPoint("TOPLEFT", 14, -36)
	f.body:SetPoint("RIGHT", -12, 0)
	f.body:SetJustifyV("TOP")

	f.rows = UI.Pool(function(parent)
		local row = CreateFrame("Button", nil, parent)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.bg = UI.Fill(row, { 1, 1, 1, 0 }, "BACKGROUND")
		row.bg:SetAllPoints()
		row.tag = UI.Chip(row, 11)
		row.tag:SetPoint("TOPLEFT", 0, -5)
		row.title = UI.Text(row, 13)
		row.title:SetPoint("TOPLEFT", 76, -6)
		row.title:SetPoint("RIGHT", -64, 0)
		row.title:SetWordWrap(false)
		row.dist = UI.Text(row, 12, C.muted, "RIGHT")
		row.dist:SetPoint("TOPRIGHT", -4, -7)
		row.detail = UI.Text(row, 12, C.muted)
		row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -4)
		row.detail:SetPoint("RIGHT", -4, 0)
		row.detail:SetJustifyV("TOP")
		row:SetScript("OnEnter", function(r)
			if not r.first then r.bg:SetVertexColor(1, 1, 1, 0.05) end
			GameTooltip:SetOwner(r, "ANCHOR_LEFT")
			GameTooltip:AddLine(r.titleText or "")
			GameTooltip:AddLine(L["Click: point the arrow here"], 0.7, 0.7, 0.7)
			GameTooltip:AddLine(L["Right-click: skip this quest"], 0.7, 0.7, 0.7)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function(r)
			if not r.first then r.bg:SetVertexColor(1, 1, 1, 0) end
			GameTooltip_Hide()
		end)
		return row
	end)

	f.footer = UI.Text(f, 12, C.muted)
	f.footer:SetPoint("RIGHT", -12, 0)
	f.footer:SetWordWrap(true)

	f.back = UI.Button(f, L["Back"], 80, 24, "normal", function() self:Back() end)
	f.back:SetPoint("BOTTOMLEFT", 14, 10)
	f.skip = UI.Button(f, L["Done"], 80, 24, "normal", function() self:MarkCurrentDone() end)
	f.skip:SetPoint("BOTTOMRIGHT", -12, 10)
	f.dungeon = UI.Button(f, L["Dungeon"], 100, 24, "accent", function()
		local target = f.dungeonTarget
		if target then
			ns.SetWaypoint(target.where.zone, target.where.x, target.where.y, target.entry.name or ns.InstanceName(target.entry.id), "guide")
		end
	end)
	f.dungeon:SetPoint("RIGHT", f.skip, "LEFT", -8, 0)
	f.dungeon.tooltip = L["Point the arrow to the nearest dungeon for your level"]
	self.frame = f
end

function Route:UpdateWindow()
	local f = self.frame
	if not f then return end
	local s = self:Settings()
	f:SetScale(s.scale)
	f:ClearAllPoints()
	f:SetPoint(s.point[1], UIParent, s.point[3], s.point[4], s.point[5])
	if not s.showWindow or UnitLevel("player") >= (GetMaxPlayerLevel() or 60) then
		f:Hide()
		return
	end
	f:Show()
	f.rows:ReleaseAll()
	local recording = CharState().recording
	local y = 38
	if not self.route then
		f.title:SetText(L["Next quests"])
		f.progress:SetText(recording and UI.Colorize(string.format(L["Recording: %d steps"], #recording.steps), C.bad) or "")
		f.body:SetText("")
		local best = Assistant:Best()
		for i = 1, math.min(s.assistantCount, #Assistant.steps) do
			local step = Assistant.steps[i]
			local row = f.rows:Acquire(f)
			local tag = TAG[step.kind]
			row.tag:Set(tag[1], tag[2])
			row.tag:SetWidth(68)
			local q = ns.QuestDB[step.id]
			row.titleText = Assistant:Title(step.id)
			row.title:SetText(UI.Colorize("[" .. (q[1] > 0 and q[1] or UnitLevel("player")) .. "] ", C.muted) .. row.titleText)
			row.dist:SetText(step.dist >= 1e6 and L[ns.CONTINENT_NAMES[step.cont] or "Kalimdor"] or string.format(L["%d yards"], step.dist))
			row.first = i == 1
			row.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], row.first and 0.12 or 0)
			local lines = {}
			if row.first and step.kind == "complete" and C_QuestLog.GetQuestObjectives then
				for _, obj in ipairs(C_QuestLog.GetQuestObjectives(step.id) or {}) do
					if obj.text and not ns.IsSecret(obj.text) then
						lines[#lines + 1] = (obj.finished and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " or "- ") .. UI.Colorize(obj.text, obj.finished and C.good or C.muted)
					end
				end
			end
			row.detail:SetText(table.concat(lines, "\n"))
			local h = 26 + (#lines > 0 and (row.detail:GetStringHeight() + 6) or 0)
			row:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -y)
			row:SetPoint("RIGHT", f, "RIGHT", -10, 0)
			row:SetHeight(h)
			row:SetScript("OnClick", function(_, button)
				if button == "RightButton" then
					Assistant.ignored[step.kind .. step.id] = true
				else
					Assistant.pinned = step.kind .. step.id
					ns.SetWorldWaypoint(step.cont, step.x, step.y, Assistant:Title(step.id), OWNER)
				end
				self:Refresh()
			end)
			y = y + h + 2
		end
		if #Assistant.steps == 0 then
			f.body:SetText(UI.Colorize(L["No quest found around your level. Try another zone or a dungeon."], C.muted))
			y = y + f.body:GetStringHeight() + 4
		end
		local dungeons = s.suggestDungeons and Assistant:SuggestedDungeons() or {}
		if dungeons[1] then
			local names = {}
			for i = 1, math.min(3, #dungeons) do
				local e = dungeons[i].entry
				names[#names + 1] = UI.Colorize(e.name or ns.InstanceName(e.id), C.text) .. UI.Colorize(string.format(" %d-%d", e.min, e.max), C.muted)
			end
			f.footer:SetText(L["Dungeons for your level:"] .. " " .. table.concat(names, ", "))
		else
			f.footer:SetText("")
		end
		f.dungeon:SetShown(dungeons[1] ~= nil)
		f.dungeonTarget = dungeons[1]
		f.back:Hide()
		f.skip:SetText(L["Skip"])
		f.skip.tooltip = L["Skip this quest and point to the next one"]
		f.skip:SetShown(best ~= nil)
	else
		f.dungeon:Hide()
		local state = CharState()
		local step = self.route.steps[state.step]
		f.title:SetText(self.route.name or self.route.id)
		f.progress:SetFormattedText("%d / %d", state.step, #self.route.steps)
		f.body:SetText(step and self:StepText(step) or "")
		y = y + f.body:GetStringHeight() + 6
		local nextOne = self.route.steps[state.step + 1]
		f.footer:SetText(nextOne and (L["Next:"] .. " " .. self:StepText(nextOne, true)) or "")
		f.back:SetShown(state.step > 1)
		f.skip:SetText(L["Done"])
		f.skip.tooltip = L["Mark this step as done"]
		f.skip:Show()
	end
	f.footer:ClearAllPoints()
	f.footer:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -(y + 6))
	f.footer:SetPoint("RIGHT", f, "RIGHT", -12, 0)
	local footer = f.footer:GetText() ~= "" and f.footer:GetStringHeight() + 10 or 0
	f:SetHeight(y + footer + 46)
end

function ns.ToggleRouteWindow()
	local s = Route:Settings()
	s.showWindow = not s.showWindow
	if Route:IsEnabled() then Route:UpdateWindow() end
end

---------------------------------------------------------------------------
-- Recorder: turns your own play into route steps.
---------------------------------------------------------------------------
local function Here()
	local mapID, x, y = ns.PlayerMapPosition()
	if x then
		return mapID, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000
	end
	return mapID
end

function Route:RecordStep(kind, fields)
	local rec = CharState().recording
	if not rec then return end
	local step = fields or {}
	step[1] = kind
	step.map, step.x, step.y = Here()
	rec.steps[#rec.steps + 1] = step
	rec.maxLevel = UnitLevel("player")
	self:UpdateWindow()
end

function Route:StartRecording(name)
	local faction, race, class, level = PlayerInfo()
	CharState().recording = {
		id = (name ~= "" and name or ("route-" .. date("%Y%m%d-%H%M"))):lower():gsub("%s+", "-"),
		name = name ~= "" and name or nil,
		faction = faction, races = { race }, classes = { class },
		minLevel = level, maxLevel = level,
		steps = {},
	}
	self.completeSeen = {}
	for i = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(i)
		if info and info.questID and C_QuestLog.IsComplete(info.questID) then self.completeSeen[info.questID] = true end
	end
	ns.Print(L["Recording started. Quests you accept, complete and turn in are added as steps."])
	self:UpdateWindow()
end

function Route:StopRecording()
	local rec = CharState().recording
	if not rec then return end
	CharState().recording = nil
	self:Global().recorded[rec.id] = rec
	ns.Print(string.format(L["Route saved as \"%s\" (%d steps). /fc route export %s to share it."], rec.id, #rec.steps, rec.id))
	self:UpdateWindow()
end

-- Lua source for a route, to ship it in Data\Routes.
local function ToLua(route)
	local out = { "ns.RegisterRoute({" }
	local function add(line) out[#out + 1] = line end
	add(string.format("\tid = %q,", route.id))
	if route.name then add(string.format("\tname = %q,", route.name)) end
	if route.faction then add(string.format("\tfaction = %q,", route.faction)) end
	if route.races then add(string.format("\traces = { %q },", route.races[1])) end
	if route.classes then add(string.format("\tclasses = { %q },", route.classes[1])) end
	add(string.format("\tminLevel = %d, maxLevel = %d,", route.minLevel, route.maxLevel))
	add("\tsteps = {")
	for _, step in ipairs(route.steps) do
		local parts = { string.format("%q", step[1]) }
		for _, key in ipairs({ "quest", "level", "instance", "map", "x", "y", "npc", "text" }) do
			local v = step[key]
			if v ~= nil then
				parts[#parts + 1] = type(v) == "string" and string.format("%s = %q", key, v) or (key .. " = " .. tostring(v))
			end
		end
		if step.quest then
			local title = C_QuestLog.GetTitleForQuestID(step.quest)
			if title then parts[#parts + 1] = string.format("name = %q", title) end
		end
		add("\t\t{ " .. table.concat(parts, ", ") .. " },")
	end
	add("\t},")
	add("})")
	return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Route:QUEST_ACCEPTED(_, questID)
	self:RecordStep("accept", { quest = questID })
	self:Advance()
end

function Route:QUEST_TURNED_IN(_, questID)
	self:RecordStep("turnin", { quest = questID })
	-- The completed flag is set a moment after the event.
	C_Timer.After(0.5, function() self:Advance() end)
end

function Route:QUEST_LOG_UPDATE()
	if self.pending then return end
	self.pending = true
	C_Timer.After(0.3, function()
		self.pending = false
		if CharState().recording and self.completeSeen then
			for i = 1, C_QuestLog.GetNumQuestLogEntries() do
				local info = C_QuestLog.GetInfo(i)
				if info and info.questID and not info.isHeader and not self.completeSeen[info.questID] and C_QuestLog.IsComplete(info.questID) then
					self.completeSeen[info.questID] = true
					self:RecordStep("complete", { quest = info.questID })
				end
			end
		end
		self:Advance()
	end)
end

function Route:OnEnable()
	self:CreateWindow()
	self:RegisterEvent("QUEST_ACCEPTED")
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, function() self:Advance() end) end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Advance")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "Refresh")
	self:Advance()
	if not self.ticker then
		self.ticker = C_Timer.NewTicker(2, function()
			if self:IsEnabled() and not self.route then self:Refresh() end
		end)
	end
end

function Route:OnDisable()
	if self.ticker then self.ticker:Cancel() self.ticker = nil end
	ns.ClearWaypoint(OWNER)
	if self.frame then self.frame:Hide() end
end

function Route:OnProfileChanged()
	self:Advance()
end

ns.RegisterCommand("route", L["route window | record [name] | stop | note <text> | goto <text> | export <id> | lua <id> | import | reset"], function(rest)
	local sub, arg = rest:match("^(%S*)%s*(.-)$")
	sub = (sub or ""):lower()
	if sub == "" then
		ns.ToggleRouteWindow()
	elseif sub == "record" then
		Route:StartRecording(arg)
	elseif sub == "stop" then
		Route:StopRecording()
	elseif sub == "note" or sub == "goto" or sub == "train" then
		if not CharState().recording then ns.Print(L["Not recording. /fc route record first."]) return end
		Route:RecordStep(sub, { text = arg })
	elseif sub == "export" or sub == "lua" then
		local route = Route:Global().recorded[arg] or (arg ~= "" and Route:FindRoute(arg)) or CharState().recording
		if not route then
			local names = {}
			for id in pairs(Route:Global().recorded) do names[#names + 1] = id end
			ns.Print(L["Recorded routes:"] .. " " .. (#names > 0 and table.concat(names, ", ") or NONE))
			return
		end
		ns.ShowCopyBox(route.id, sub == "lua" and ToLua(route) or ns.Encode(route))
	elseif sub == "import" then
		ns.ShowCopyBox(L["Import a route"], "", function(text)
			local route = ns.Decode(text)
			if type(route) == "table" and route.id and type(route.steps) == "table" then
				table.insert(Route:Global().imported, route)
				ns.Print(string.format(L["Route imported: %s"], route.id))
				Route:Advance()
			else
				ns.Print(L["This text is not a valid route."])
			end
		end)
	elseif sub == "reset" then
		local state = CharState()
		state.routeID, state.step = nil, 1
		wipe(state.manualDone)
		wipe(state.finished)
		Route:Advance()
	else
		ns.Print(L["Unknown command. Type /fc help."])
	end
end)

function Route:GetOptions()
	local get, set = ns.ProfileAccessors("Route", function() self:Advance() end)
	return {
		get = get, set = set,
		args = {
			showWindow = { type = "toggle", order = 1, name = L["Show the route window"] },
			locked = { type = "toggle", order = 2, name = L["Lock position"] },
			scale = { type = "range", order = 3, name = L["Scale"], min = 0.5, max = 2, step = 0.05 },
			autoArrow = { type = "toggle", order = 4, width = "full", name = L["Point the arrow at each step automatically"] },
			assistantCount = { type = "range", order = 6, name = L["Quests listed"], min = 1, max = 10, step = 1 },
			questLevelsBelow = { type = "range", order = 7, name = L["Quests up to N levels below mine"], min = 0, max = 15, step = 1 },
			questLevelsAbove = { type = "range", order = 8, name = L["Quests up to N levels above mine"], min = 0, max = 6, step = 1 },
			suggestDungeons = { type = "toggle", order = 9, width = "full", name = L["Suggest dungeons for my level"] },
			style = {
				type = "select", order = 5, name = L["Route style"],
				values = { quests = L["Quests only"], dungeons = L["Quests and dungeons"], fastest = L["Fastest"] },
			},
			current = {
				type = "description", order = 10, fontSize = "medium",
				name = function()
					local route = self.route
					return "\n" .. L["Current route:"] .. " " .. (route and (route.name or route.id) or NONE)
				end,
			},
			reset = {
				type = "execute", order = 11, name = L["Restart routes"],
				desc = L["Forget progress and pick the route again from your current level."],
				func = function() ns.FC:SlashCommand("route reset") end,
			},
			help = {
				type = "description", order = 20,
				name = "\n" .. L["Recording: /fc route record <name> starts, /fc route stop saves. While recording, /fc route note <text>, /fc route goto <text> and /fc route train <text> add manual steps. /fc route export <name> gives a text to share, /fc route import adds one."],
			},
		},
	}
end
