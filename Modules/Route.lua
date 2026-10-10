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
		self:UpdateWindow()
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

function Route:UpdateWaypoint()
	local step = self:CurrentStep()
	if step and step.map and step.x and step.y and self:Settings().autoArrow then
		ns.SetWaypoint(step.map, step.x, step.y, self:StepText(step, true), OWNER)
	else
		ns.ClearWaypoint(OWNER)
	end
end

function Route:MarkCurrentDone()
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
function Route:CreateWindow()
	if self.frame then return end
	local f = CreateFrame("Frame", "ForeverCompanionRouteFrame", UIParent, "BackdropTemplate")
	f:SetSize(300, 120)
	f:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	f:SetBackdropColor(0, 0, 0, 0.75)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(frame) if not self:Settings().locked then frame:StartMoving() end end)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		self:Settings().point = { point, "UIParent", relPoint, x, y }
	end)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	title:SetPoint("TOPRIGHT", -60, -8)
	title:SetJustifyH("LEFT")
	f.title = title

	local progress = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	progress:SetPoint("TOPRIGHT", -10, -9)
	f.progress = progress

	local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	body:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	f.body = body

	local nextStep = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	nextStep:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -6)
	nextStep:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	nextStep:SetJustifyH("LEFT")
	f.nextStep = nextStep

	local function MakeButton(text, onClick)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(70, 20)
		b:SetText(text)
		b:SetScript("OnClick", onClick)
		return b
	end
	f.back = MakeButton(L["Back"], function() self:Back() end)
	f.back:SetPoint("BOTTOMLEFT", 8, 8)
	f.skip = MakeButton(L["Done"], function() self:MarkCurrentDone() end)
	f.skip:SetPoint("BOTTOMRIGHT", -8, 8)

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
	local recording = CharState().recording
	if not self.route then
		f.title:SetText(L["XP route"])
		f.progress:SetText("")
		if recording then
			f.body:SetText(string.format(L["Recording a route: %d steps so far. /fc route stop to finish."], #recording.steps))
		else
			f.body:SetText(L["No route available yet for this character at this level. Routes are added with updates; you can record your own with /fc route record."])
		end
		f.nextStep:SetText("")
		f.back:Hide()
		f.skip:Hide()
	else
		local state = CharState()
		local step = self.route.steps[state.step]
		f.title:SetText(self.route.name or self.route.id)
		f.progress:SetFormattedText("%d/%d", state.step, #self.route.steps)
		f.body:SetText(step and self:StepText(step) or "")
		local nextOne = self.route.steps[state.step + 1]
		f.nextStep:SetText(nextOne and (L["Next:"] .. " " .. self:StepText(nextOne, true)) or "")
		f.back:SetShown(state.step > 1)
		f.skip:Show()
	end
	local height = 44 + f.body:GetStringHeight() + f.nextStep:GetStringHeight() + 20
	f:SetHeight(math.max(90, height))
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
	self:Advance()
end

function Route:OnDisable()
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
