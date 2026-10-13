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
	autoRoutes = true, -- follow the built-in leveling routes (Data\RoutesAuto.lua)
	showUpgrades = true, -- best-in-slot items of your level to pick up, under the steps
	routeDungeons = true, -- dungeon steps of the built-in routes (off: solo, they are skipped)
	stepsShown = 3,
	idleAlpha = 0.75, -- opacity while the mouse is elsewhere
	collapsed = false,
}, {
	recorded = {}, -- [name] = route
	imported = {}, -- list of routes pasted by the player
})
ns.RegisterDefaults("char", "Route", {
	routeID = nil,
	step = 1,
	manualDone = {}, -- ["routeID:step"] = true
	finished = {},   -- [routeID] = true
	dungeons = {},   -- [instanceID or name] = highest level at which the character entered it
	recording = nil, -- route being recorded
})

ns.Route = Route
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
	if title and not ns.IsSecret(title) and title ~= "" then return title end
	local q = step.quest and ns.QuestDB and ns.QuestDB[step.quest]
	return step.name or (q and q[7]) or (step.quest and ("#" .. step.quest)) or ""
end

local function InLog(questID)
	local index = C_QuestLog.GetLogIndexForQuestID(questID)
	return index ~= nil and index ~= 0
end

-- "Zone (x, y)" for a world position (continent 0 = Eastern Kingdoms, 1 = Kalimdor).
local CONTINENT_MAPS = { [0] = 1415, [1] = 1414 }
function ns.WorldPlace(continent, x, y)
	if continent and continent < 0 then
		return string.format("%s (%.0f, %.0f)", ns.MapName(-continent), x / 100, y / 100)
	end
	local contMap = CONTINENT_MAPS[continent]
	local mx, my = ns.WorldToMap(continent, x, y, contMap)
	if mx and C_Map.GetMapInfoAtPosition then
		local ok, info = pcall(C_Map.GetMapInfoAtPosition, contMap, mx, my)
		if ok and info and info.mapID and info.mapID ~= contMap then
			local zx, zy = ns.WorldToMap(continent, x, y, info.mapID)
			if zx then return string.format("%s (%.0f, %.0f)", info.name or "?", zx * 100, zy * 100) end
			return info.name
		end
	end
	-- not on Kalimdor or the Eastern Kingdoms (Zephras Isle...): the player's own map, if the point is on it
	local here = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local hx, hy
	if here then hx, hy = ns.WorldToMap(continent, x, y, here) end
	if hx and hy then return string.format("%s (%.0f, %.0f)", ns.MapName(here), hx * 100, hy * 100) end
	local cn = ns.CONTINENT_NAMES[continent]
	if cn then return L[cn] end
	return here and ns.MapName(here) or "?"
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

-- Quests this character can not take: another class or race, or not offered by the giver when the player talked
-- to them (ns.notOffered, this session only).  Their steps are passed.
ns.notOffered = ns.notOffered or {}

-- Quests that need each quest first (questID -> quests whose previous quest it is), built on first use.
local followers
local function Followers(questID)
	if not followers then
		followers = {}
		for id, q in pairs(ns.QuestDB or {}) do
			local prev = q[5]
			if prev and prev > 0 then
				followers[prev] = followers[prev] or {}
				table.insert(followers[prev], id)
			end
		end
	end
	return followers[questID]
end

-- Done another way: a quest that needs this one is already taken or done (the game did not report this one, or it
-- was done before the addon), or this one is a breadcrumb whose quest is already taken or done (no longer offered).
local function Superseded(questID)
	local target = ns.QuestBreadcrumbs and ns.QuestBreadcrumbs[questID]
	if target and (InLog(target) or TurnedIn(target)) then return true end
	for _, other in ipairs(Followers(questID) or {}) do
		if InLog(other) or TurnedIn(other) then return true end
	end
	return false
end

local function Unavailable(questID)
	if not questID or InLog(questID) or TurnedIn(questID) then return false end
	if ns.notOffered[questID] then return true end
	local q = ns.QuestDB and ns.QuestDB[questID]
	if not q then return false end
	if Superseded(questID) then return true end
	local _, _, classID = UnitClass("player")
	if q[4] and q[4] ~= 0 and classID and not HasBit(q[4], 2 ^ (classID - 1)) then return true end
	local raceBit = ns.PlayerRaceBit()
	if q[3] and q[3] ~= 0 and raceBit and not HasBit(q[3], raceBit) then return true end
	return false
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
	local raceBit = ns.PlayerRaceBit()
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
		local where = entry.where or (entry.id and ns.Instances[entry.id])
		if entry.kind == "dungeon" and level >= entry.min - 2 and level <= entry.max - 2 and where and not seen[entry.id or entry.key] then
			seen[entry.id or entry.key] = true
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
	local routes = ns.MatchingRoutes(faction, race, class, self:Settings().style, self:Global().imported)
	if not self:Settings().autoRoutes then
		for i = #routes, 1, -1 do
			if routes[i].auto then table.remove(routes, i) end
		end
	end
	return routes
end

function Route:FindRoute(id)
	for _, r in ipairs(ns.Routes) do if r.id == id then return r end end
	for _, r in ipairs(self:Global().imported) do if r.id == id then return r end end
end

function Route:ChooseRoute()
	local state = CharState()
	local level = UnitLevel("player")
	local current = state.routeID and self:FindRoute(state.routeID)
	if current then
		-- a route picked by hand for another class or race (or from an older version) is replaced
		local fits = false
		for _, r in ipairs(self:AllRoutes()) do if r == current then fits = true break end end
		if not fits then current = nil; state.routeID = nil end
	end
	if current and not state.finished[current.id] and level <= current.maxLevel then
		return current
	end
	for _, route in ipairs(self:AllRoutes()) do
		if not state.finished[route.id] and level >= route.minLevel and level <= route.maxLevel then
			if state.routeID ~= route.id then
				state.routeID = route.id
				state.step = 1
				if route.auto then
					ns.Print(string.format(L["Leveling route: %s (levels %d-%d), followed automatically."], route.name or "", route.minLevel, route.maxLevel))
				end
			end
			return route
		end
	end
	state.routeID = nil
	return nil
end

-- Remembers the dungeons the character entered (dungeon steps of the routes).
function Route:NoteInstance()
	if not (IsInInstance and IsInInstance()) then return end
	local name, kind, _, _, _, _, _, instanceID = GetInstanceInfo()
	if kind ~= "party" and kind ~= "raid" then return end
	local visits = CharState().dungeons
	if not visits then visits = {}; CharState().dungeons = visits end
	local level = UnitLevel("player")
	if instanceID then visits[instanceID] = math.max(visits[instanceID] or 0, level) end
	if name and not ns.IsSecret(name) then visits[name] = math.max(visits[name] or 0, level) end
end

function Route:IsStepDone(route, index)
	local step = route.steps[index]
	local kind = step[1]
	if CharState().manualDone[route.id .. ":" .. index] then return true end
	if kind == "accept" then
		return InLog(step.quest) or TurnedIn(step.quest) or Unavailable(step.quest)
	elseif kind == "complete" then
		return TurnedIn(step.quest) or (InLog(step.quest) and C_QuestLog.IsComplete(step.quest)) or Unavailable(step.quest)
	elseif kind == "turnin" then
		return TurnedIn(step.quest) or Unavailable(step.quest)
	elseif kind == "level" then
		return UnitLevel("player") >= step.level
	elseif kind == "note" and step.abandon then
		return not InLog(step.quest)
	elseif kind == "dungeon" then
		if not Route:Settings().routeDungeons then return true end
		-- done once the character has been inside at the step's level (wings of one instance share its map ID)
		local visits = CharState().dungeons or {}
		local seen = (step.instance and visits[step.instance]) or (step.entry and step.entry.name and visits[step.entry.name])
		local inside = IsInInstance and IsInInstance()
		return seen and seen >= (step.lvl or 1) - 1 and not inside or UnitLevel("player") > (step.maxLvl or 60)
	elseif kind == "goto" and step.wx then
		-- also done once a later quest step of the route is done (you are already there)
		local nextStep = route.steps[index + 1]
		if nextStep and nextStep.quest and (InLog(nextStep.quest) or TurnedIn(nextStep.quest)) then return true end
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
	if step and (step.wx or step.map) and self:Settings().autoArrow then
		if not self:PointsAt(step) then self:PointAt(step) end
	else
		ns.ClearWaypoint(OWNER)
	end
end

-- Arrow on a step: map position first (new zones such as Zephras Isle), world position otherwise.
function Route:PointAt(step)
	local title = self:StepText(step, true)
	if step.npc and (step[1] == "accept" or step[1] == "turnin") then title = step.npc .. " · " .. title end
	if step.map and step.x and step.y then
		ns.SetWaypoint(step.map, step.x, step.y, title, OWNER)
	elseif step.wx then
		ns.SetWorldWaypoint(step.cont, step.wx, step.wy, title, OWNER)
	end
end

function Route:PointsAt(step)
	local wp = ns.GetWaypoint()
	if not (wp and wp.owner == OWNER) then return false end
	if step.map and step.x then return wp.mapID == step.map and wp.x == step.x and wp.y == step.y end
	return ns.SameWaypoint(step.cont, step.wx, step.wy)
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
	end
	-- quest steps keep the arrow until the quest is accepted, done or turned in
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
		body = step.entry and ns.InstanceEntryName and ns.InstanceEntryName(step.entry) or ns.InstanceName(step.instance)
		if not short then body = body .. "\n|cffbbbbbb" .. L["Group up for this dungeon (Group Finder or /4 LookingForGroup), do its quests inside, then continue the route."] .. "|r" end
	elseif kind == "goto" and step.zone then
		body = string.format(L["Travel to %s"], step.zone)
		if step.ship and not short then
			body = body .. "\n|cffbbbbbb" .. (UnitFactionGroup("player") == "Horde" and L["Take the zeppelin or the boat to the other continent."] or L["Take the boat to the other continent."]) .. "|r"
		end
	elseif kind == "note" and step.abandon then
		body = string.format(L["Abandon: %s"], QuestTitle(step))
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
		text = text .. string.format("\n|cff888888%s (%.0f, %.0f)|r", ns.MapName(step.map), step.x * 100, step.y * 100)
	elseif step.wx then
		text = text .. "\n|cff888888" .. ns.WorldPlace(step.cont, step.wx, step.wy) .. "|r"
	elseif false then
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
	["goto"] = { L["Go to"], C.text },
	level = { L["Level"], { 1, 0.6, 0.2 } },
	train = { L["Train"], { 0.8, 0.6, 1 } },
	dungeon = { L["Dungeon"], C.bad },
	note = { L["Note"], C.muted },
	gear = { L["BiS"], { 0.75, 0.5, 1 } },
}

-- Compact step window ("HUD"): a slim header, one line per step with a coloured mark for its kind, details
-- only under the current step, and one line for the best-in-slot reminder.  Faded until the mouse is over it.
local WIDTH, ROW_H, PAD = 250, 17, 8

local function KindColor(kind)
	local tag = TAG[kind] or TAG.note
	return tag[2]
end

local function SetRow(row, kind, first)
	local c = KindColor(kind)
	row.mark:SetVertexColor(c[1], c[2], c[3], first and 1 or 0.7)
	row.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], first and 0.10 or 0)
	row.first = first
end

local function PlaceRow(f, row, y, detail)
	row.detail:SetText(detail or "")
	local h = ROW_H + ((detail and detail ~= "") and (row.detail:GetStringHeight() + 2) or 0)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 2, -y)
	row:SetPoint("RIGHT", f, "RIGHT", -PAD + 2, 0)
	row:SetHeight(h)
	return y + h + 1
end

-- One line for the gear upgrades of your level (best-in-slot lists of the leveling guide).
function Route:AddUpgradeRows(f, y)
	if not (self:Settings().showUpgrades and ns.GearUpgrades) then return y end
	local ok, ups = pcall(ns.GearUpgrades)
	if not ok or not ups or #ups == 0 then return y end
	local u
	for _, x in ipairs(ups) do if x.name then u = x break end end
	if not u then return y end
	local row = f.rows:Acquire(f)
	SetRow(row, "gear", false)
	local color = u.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[u.quality]
	row.titleText = u.name
	row.tipLines = { u.inBags and L["in your bags: equip it"] or u.source or "", #ups > 1 and string.format(L["%d more upgrades: open the gear list"], #ups - 1) or nil }
	row.title:SetText(UI.Colorize(L["BiS"] .. " ", TAG.gear[2]) .. (color and color.hex and (color.hex .. u.name .. "|r") or u.name))
	row.dist:SetText(#ups > 1 and UI.Colorize("+" .. (#ups - 1), C.muted) or "")
	row:SetScript("OnClick", function(_, button)
		if button == "RightButton" or not ns.GoToUpgrade(u) then ns.ToggleClassGuide("gear") end
	end)
	return PlaceRow(f, row, y, u.inBags and UI.Colorize(L["in your bags: equip it"], C.good) or nil)
end

function Route:CreateWindow()
	if self.frame then return end
	local f = UI.Panel("ForeverCompanionRouteFrame", WIDTH, 60, function() return self:Settings() end)
	f:SetBackdropColor(C.bg[1], C.bg[2], C.bg[3], 0.62)
	f:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 0.5)
	f.stripe:SetWidth(2)
	f.stripe:SetAlpha(0.7)

	-- header: title (click to fold), progress, back / done / dungeon buttons
	f.header = CreateFrame("Button", nil, f)
	f.header:SetPoint("TOPLEFT", 0, 0)
	f.header:SetPoint("TOPRIGHT", -52, 0)
	f.header:SetHeight(22)
	f.header:RegisterForDrag("LeftButton")
	f.header:SetScript("OnDragStart", function() if not self:Settings().locked then f:StartMoving() end end)
	f.header:SetScript("OnDragStop", function() f:GetScript("OnDragStop")(f) end)
	f.header:SetScript("OnClick", function()
		local s = self:Settings()
		s.collapsed = not s.collapsed
		self:UpdateWindow()
	end)
	f.header:SetScript("OnEnter", function(h)
		GameTooltip:SetOwner(h, "ANCHOR_LEFT")
		GameTooltip:AddLine(f.tip or "", 1, 1, 1)
		GameTooltip:AddLine(L["Click: fold or unfold"], 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	f.header:SetScript("OnLeave", GameTooltip_Hide)
	f.title = UI.Text(f.header, 12, C.gold)
	f.title:SetPoint("LEFT", PAD + 2, 0)
	f.title:SetPoint("RIGHT", -34, 0)
	f.title:SetWordWrap(false)
	f.progress = UI.Text(f.header, 10, C.muted, "RIGHT")
	f.progress:SetPoint("RIGHT", -2, 0)

	f.skip = UI.IconButton(f, 14, "Interface\\RaidFrame\\ReadyCheck-Ready", L["Mark this step as done"], function()
		if self.route then self:MarkCurrentDone() else
			local best = Assistant:Best()
			if best then Assistant.ignored[best.kind .. best.id] = true; self:Refresh() end
		end
	end)
	f.skip:SetPoint("TOPRIGHT", -6, -4)
	f.back = UI.IconButton(f, 14, "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", L["Back"], function() self:Back() end)
	f.back:SetPoint("RIGHT", f.skip, "LEFT", -3, 0)
	f.dungeon = UI.IconButton(f, 14, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull", L["Point the arrow to the nearest dungeon for your level"], function()
		local target = f.dungeonTarget
		if target then
			ns.SetWaypoint(target.where.zone, target.where.x, target.where.y, target.entry.name or ns.InstanceName(target.entry.id), "guide")
		end
	end)
	f.dungeon:SetPoint("RIGHT", f.back, "LEFT", -3, 0)

	f.body = UI.Text(f, 11, C.muted)
	f.body:SetPoint("TOPLEFT", PAD + 2, -24)
	f.body:SetPoint("RIGHT", -PAD, 0)
	f.body:SetJustifyV("TOP")

	f.rows = UI.Pool(function(parent)
		local row = CreateFrame("Button", nil, parent)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.bg = UI.Fill(row, { 1, 1, 1, 0 }, "BACKGROUND")
		row.bg:SetAllPoints()
		row.mark = UI.Fill(row, { 1, 1, 1, 1 }, "ARTWORK")
		row.mark:SetPoint("TOPLEFT", 2, -4)
		row.mark:SetSize(3, ROW_H - 8)
		row.title = UI.Text(row, 12)
		row.title:SetPoint("TOPLEFT", 10, -2)
		row.title:SetPoint("RIGHT", -60, 0)
		row.title:SetWordWrap(false)
		row.dist = UI.Text(row, 10, C.muted, "RIGHT")
		row.dist:SetPoint("TOPRIGHT", -3, -4)
		row.detail = UI.Text(row, 11, C.muted)
		row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -1)
		row.detail:SetPoint("RIGHT", -3, 0)
		row.detail:SetJustifyV("TOP")
		row:SetScript("OnEnter", function(r)
			if not r.first then r.bg:SetVertexColor(1, 1, 1, 0.05) end
			f:SetAlpha(1)
			GameTooltip:SetOwner(r, "ANCHOR_LEFT")
			GameTooltip:AddLine(r.titleText or "", 1, 1, 1, true)
			for _, line in ipairs(r.tipLines or {}) do
				if line and line ~= "" then GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
			end
			GameTooltip:AddLine(L["Click: point the arrow here"], 0.6, 0.6, 0.6)
			GameTooltip:AddLine(L["Right-click: skip this quest"], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function(r)
			if not r.first then r.bg:SetVertexColor(1, 1, 1, 0) end
			GameTooltip_Hide()
		end)
		return row
	end)

	-- faded while the mouse is elsewhere
	f:SetScript("OnUpdate", function(frame, elapsed)
		frame.fade = (frame.fade or 0) + elapsed
		if frame.fade < 0.2 then return end
		frame.fade = 0
		local target = (frame:IsMouseOver() and 1) or self:Settings().idleAlpha or 0.75
		frame:SetAlpha(target)
	end)
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
	f.body:SetText("")
	local recording = CharState().recording
	local y = 24
	if not self.route then
		f.title:SetText(L["Next quests"])
		f.progress:SetText(recording and UI.Colorize(string.format(L["Recording: %d steps"], #recording.steps), C.bad) or "")
		local best = Assistant:Best()
		local dungeons = s.suggestDungeons and Assistant:SuggestedDungeons() or {}
		local names = {}
		for i = 1, math.min(3, #dungeons) do
			local e = dungeons[i].entry
			names[#names + 1] = (e.name or ns.InstanceName(e.id)) .. string.format(" %d-%d", e.min, e.max)
		end
		f.tip = #names > 0 and (L["Dungeons for your level:"] .. " " .. table.concat(names, ", ")) or L["Next quests"]
		f.dungeon:SetShown(dungeons[1] ~= nil)
		f.dungeonTarget = dungeons[1]
		f.back:Hide()
		f.skip.tooltip = L["Skip this quest and point to the next one"]
		f.skip:SetShown(best ~= nil)
		if not s.collapsed then
			for i = 1, math.min(s.assistantCount, #Assistant.steps) do
				local step = Assistant.steps[i]
				local row = f.rows:Acquire(f)
				SetRow(row, step.kind, i == 1)
				local q = ns.QuestDB[step.id]
				row.titleText = Assistant:Title(step.id)
				row.tipLines = nil
				row.title:SetText(UI.Colorize((q[1] > 0 and q[1] or UnitLevel("player")) .. " ", C.muted) .. row.titleText)
				row.dist:SetText(step.dist >= 1e6 and L[ns.CONTINENT_NAMES[step.cont] or "Kalimdor"] or string.format(L["%d yards"], step.dist))
				local lines = {}
				if i == 1 and step.kind == "complete" and C_QuestLog.GetQuestObjectives then
					for _, obj in ipairs(C_QuestLog.GetQuestObjectives(step.id) or {}) do
						if obj.text and not ns.IsSecret(obj.text) then
							lines[#lines + 1] = UI.Colorize(obj.text, obj.finished and C.good or C.muted)
						end
					end
				end
				row:SetScript("OnClick", function(_, button)
					if button == "RightButton" then
						Assistant.ignored[step.kind .. step.id] = true
					else
						Assistant.pinned = step.kind .. step.id
						ns.SetWorldWaypoint(step.cont, step.x, step.y, Assistant:Title(step.id), OWNER)
					end
					self:Refresh()
				end)
				y = PlaceRow(f, row, y, table.concat(lines, "\n"))
			end
			if #Assistant.steps == 0 then
				f.body:SetText(L["No quest found around your level. Try another zone or a dungeon."])
				y = y + f.body:GetStringHeight() + 4
			end
		end
	else
		f.dungeon:Hide()
		local state = CharState()
		local route = self.route
		f.title:SetText(route.name or route.id)
		f.progress:SetFormattedText("%d/%d", state.step, #route.steps)
		f.tip = string.format(L["Route levels %d-%d"], route.minLevel, route.maxLevel) .. (route.auto and ("  ·  " .. L["built-in route"]) or "")
		f.back:SetShown(state.step > 1)
		f.skip.tooltip = L["Mark this step as done"]
		f.skip:Show()
		if not s.collapsed then
			local shown, index = 0, state.step
			while index <= #route.steps and shown < s.stepsShown do
				local step = route.steps[index]
				if index == state.step or not self:IsStepDone(route, index) then
					shown = shown + 1
					local first = index == state.step
					local row = f.rows:Acquire(f)
					SetRow(row, step[1], first)
					row.titleText = self:StepText(step, true)
					local kindLabel = UI.Colorize(((TAG[step[1]] or TAG.note)[1] or "") .. " ", KindColor(step[1]))
					row.title:SetText(kindLabel .. row.titleText)
					row.title:SetTextColor(first and 1 or 0.8, first and 1 or 0.8, first and 1 or 0.8)
					row.dist:SetText("")
					if step.wx then
						local cont, wx, wy = ns.PlayerWorldPosition()
						if cont == step.cont and wx then
							row.dist:SetText(string.format(L["%d yards"], math.floor(math.sqrt((wx - step.wx) ^ 2 + (wy - step.wy) ^ 2))))
						end
					end
					local full = self:StepText(step)
					local rest = full:match("^[^\n]*\n(.*)$")
					if step.npc and (step[1] == "accept" or step[1] == "turnin") then
						local who = UI.Colorize(step.npc, C.gold)
						rest = rest and (who .. "  ·  " .. rest) or who
					end
					row.tipLines = { rest }
					local detail
					if first then detail = rest end
					local stepIndex = index
					row:SetScript("OnClick", function(_, button)
						if button == "RightButton" then
							CharState().manualDone[route.id .. ":" .. stepIndex] = true
							self:Advance()
						elseif step.wx or step.map then
							self:PointAt(step)
						end
					end)
					y = PlaceRow(f, row, y, detail)
				end
				index = index + 1
			end
		end
	end
	if not s.collapsed then y = self:AddUpgradeRows(f, y) end
	f:SetHeight(y + (s.collapsed and 0 or PAD - 2))
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

-- Talking to the giver of the current "accept" step: if the quest is not in what they offer, the step is passed
-- (and its later steps), so the route never waits on a quest the character can not get.
function Route:CheckOffered(offeredIDs, offeredTitles)
	local step = self.route and self:CurrentStep()
	if not (step and step[1] == "accept" and step.quest) or InLog(step.quest) or TurnedIn(step.quest) then return end
	local q = ns.QuestDB and ns.QuestDB[step.quest]
	if q and q[2] and UnitLevel("player") < q[2] then return end
	local npc = UnitName("npc")
	local near = false
	if step.npc and npc and not ns.IsSecret(npc) and npc == step.npc then near = true end
	if not near and step.wx then
		local cont, wx, wy = ns.PlayerWorldPosition()
		near = cont == step.cont and wx and math.sqrt((wx - step.wx) ^ 2 + (wy - step.wy) ^ 2) < 15
	end
	if not near then return end
	if offeredIDs[step.quest] then return end
	local title = QuestTitle(step)
	if title and offeredTitles[title] then return end
	ns.notOffered[step.quest] = true
	ns.Print(string.format(L["%s is not offered to you: step passed."], title or ("#" .. step.quest)))
	self:Advance()
end

-- Talking to any quest giver: the coming "accept" steps of that NPC whose quest they do not offer (although its
-- level and previous quest are met) are passed too, so the route does not send you back to them for nothing.
function Route:CheckOfferedAhead(offeredIDs, offeredTitles)
	local route = self.route
	local npc = UnitName("npc")
	if not route or not npc or ns.IsSecret(npc) then return end
	local state, level, changed = CharState(), UnitLevel("player"), false
	for index = state.step, math.min(#route.steps, state.step + 60) do
		local step = route.steps[index]
		local id = step.quest
		if step[1] == "accept" and id and step.npc == npc and not ns.notOffered[id] and not InLog(id) and not TurnedIn(id) then
			local q = ns.QuestDB and ns.QuestDB[id]
			local ready = q and (not q[2] or level >= q[2]) and (not q[5] or q[5] == 0 or TurnedIn(q[5]))
			local title = QuestTitle(step)
			if ready and not offeredIDs[id] and not (title and offeredTitles[title]) then
				ns.notOffered[id] = true
				changed = true
			end
		end
	end
	if changed then self:Advance() end
end

function Route:GOSSIP_SHOW()
	self.lastGossip = GetTime()
	if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
	local ids, titles = {}, {}
	for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
		if info.questID then ids[info.questID] = true end
		if info.title and not ns.IsSecret(info.title) then titles[info.title] = true end
	end
	for _, info in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
		if info.questID then ids[info.questID] = true end
	end
	self:CheckOffered(ids, titles)
	self:CheckOfferedAhead(ids, titles)
end

function Route:QUEST_GREETING()
	self.lastGossip = GetTime()
	local ids, titles = {}, {}
	for i = 1, (GetNumAvailableQuests and GetNumAvailableQuests() or 0) do
		local title = GetAvailableTitle(i)
		if title and not ns.IsSecret(title) then titles[title] = true end
	end
	for i = 1, (GetNumActiveQuests and GetNumActiveQuests() or 0) do
		local title = GetActiveTitle(i)
		if title and not ns.IsSecret(title) then titles[title] = true end
	end
	self:CheckOffered(ids, titles)
	self:CheckOfferedAhead(ids, titles)
end

function Route:QUEST_DETAIL()
	-- a quest picked from a list of several is not the giver's only quest
	if self.lastGossip and GetTime() - self.lastGossip < 30 then return end
	local id = GetQuestID and GetQuestID()
	if id and id ~= 0 then self:CheckOffered({ [id] = true }, {}) end
end

function Route:OnEnable()
	self:CreateWindow()
	self:RegisterEvent("GOSSIP_SHOW")
	self:RegisterEvent("QUEST_GREETING")
	self:RegisterEvent("QUEST_DETAIL")
	self:RegisterEvent("QUEST_ACCEPTED")
	self:RegisterEvent("QUEST_TURNED_IN")
	self:RegisterEvent("QUEST_LOG_UPDATE")
	self:RegisterEvent("PLAYER_LEVEL_UP", function() C_Timer.After(0.5, function() self:Advance() end) end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Advance")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
		self:NoteInstance()
		self:Advance()
	end)
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
			showUpgrades = { type = "toggle", order = 9.5, width = "full", name = L["Show the best-in-slot items of my level to pick up"] },
			autoRoutes = { type = "toggle", order = 9.1, width = "full", name = L["Follow the built-in leveling route of my race and class (1-60)"] },
			routeDungeons = { type = "toggle", order = 9.15, width = "full", name = L["Include the dungeons in the route (off: solo leveling, they are skipped)"] },
			stepsShown = { type = "range", order = 9.2, name = L["Route steps listed"], min = 1, max = 10, step = 1 },
			idleAlpha = { type = "range", order = 9.25, name = L["Opacity when the mouse is elsewhere"], min = 0.2, max = 1, step = 0.05, isPercent = true },
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
