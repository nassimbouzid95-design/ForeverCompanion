-- ForeverCompanion: battlegrounds and honor.
-- Records every battleground game (Warsong Gulch, Arathi Basin, Alterac Valley, Darkspear Islands...)
-- with its result, duration and honor, and keeps session stats (honor and honorable kills since login,
-- world PvP included). Only out-of-combat data is used: honor and kill counters, the winner of the
-- match and, once the match is over and you are out of combat, your own line of the scoreboard.
local _, ns = ...
local L = ns.L
local UI = ns.UI
local C = UI.COLORS

local PvP = ns.NewModule("PvP", {
	showPanel = true,
	panelOnlyInBG = true,
	locked = false,
	point = { "TOP", "UIParent", "TOP", 0, -140 },
	announce = true,
	allCharacters = false,
}, {
	games = {},   -- [name-realm] = list of finished games, oldest first
	current = {}, -- [name-realm] = game in progress (survives a /reload)
	session = {}, -- [name-realm] = { start, honor, hks, bgHonor, worldHonor, worldHks, games }
	window = {},  -- position and size
})

local MAX_GAMES = 500
local MAX_RECENT = 100
local ROW_HEIGHT = 24
local RESUME_DELAY = 300 -- a game seen less than 5 minutes ago is resumed after a reload or a disconnect
local GRACE_TIME = 15    -- honor received just after leaving still belongs to the game

---------------------------------------------------------------------------
-- Safe API readers. Everything is guarded: the function may not exist on this client,
-- may error, or may hand us a secret value.
---------------------------------------------------------------------------
local function Clean(v)
	if v == nil or ns.IsSecret(v) then return nil end
	return v
end

local function Number(v)
	v = Clean(v)
	return type(v) == "number" and v or nil
end

local function HonorCurrencyID()
	local consts = type(Constants) == "table" and Constants.CurrencyConsts
	local id = type(consts) == "table" and consts.HONOR_CURRENCY_ID
	return type(id) == "number" and id or 1792
end

-- Current honor and where it was read from (the source matters: only readings of the same source are compared).
local function ReadHonor()
	if C_CurrencyInfo and type(C_CurrencyInfo.GetCurrencyInfo) == "function" then
		local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, HonorCurrencyID())
		if ok and type(info) == "table" then
			local name, quantity = Clean(info.name), Number(info.quantity)
			if quantity and type(name) == "string" and name ~= "" then return quantity, "currency" end
		end
	end
	if type(GetHonorCurrency) == "function" then
		local ok, honor = pcall(GetHonorCurrency)
		honor = ok and Number(honor)
		if honor then return honor, "honorCurrency" end
	end
	if type(GetPVPSessionStats) == "function" then
		local ok, _, honor = pcall(GetPVPSessionStats)
		honor = ok and Number(honor)
		if honor then return honor, "session" end
	end
end

-- Honorable kills counter (lifetime when available, else today's).
local function ReadKills()
	if type(GetPVPLifetimeStats) == "function" then
		local ok, hks = pcall(GetPVPLifetimeStats)
		hks = ok and Number(hks)
		if hks then return hks, "lifetime" end
	end
	if type(GetPVPSessionStats) == "function" then
		local ok, hks = pcall(GetPVPSessionStats)
		hks = ok and Number(hks)
		if hks then return hks, "session" end
	end
end

-- Winning team of the current match (0 = Horde, 1 = Alliance), nil while it is not over.
local function MatchWinner()
	if C_PvP and type(C_PvP.GetActiveMatchWinner) == "function" then
		local ok, winner = pcall(C_PvP.GetActiveMatchWinner)
		winner = ok and Number(winner)
		if winner then return winner end
	end
	if type(GetBattlefieldWinner) == "function" then
		local ok, winner = pcall(GetBattlefieldWinner)
		winner = ok and Number(winner)
		if winner then return winner end
	end
end

-- Our team in the match, same numbering as the winner.
local function MyTeam()
	if type(GetBattlefieldArenaFaction) == "function" then
		local ok, team = pcall(GetBattlefieldArenaFaction)
		team = ok and Number(team)
		if team == 0 or team == 1 then return team end
	end
	local faction = UnitFactionGroup("player")
	if faction == "Horde" then return 0 elseif faction == "Alliance" then return 1 end
end

-- One scoreboard line: only the non-combat columns are read.
local function ScoreRow(index)
	if C_PvP and type(C_PvP.GetScoreInfo) == "function" then
		local ok, info = pcall(C_PvP.GetScoreInfo, index)
		if ok and type(info) == "table" then
			return {
				name = Clean(info.name), guid = Clean(info.guid), kb = Number(info.killingBlows),
				hks = Number(info.honorableKills), deaths = Number(info.deaths), honor = Number(info.honorGained),
			}
		end
	end
	if type(GetBattlefieldScore) == "function" then
		local ok, name, kb, hks, deaths, honor = pcall(GetBattlefieldScore, index)
		if ok then
			return { name = Clean(name), kb = Number(kb), hks = Number(hks), deaths = Number(deaths), honor = Number(honor) }
		end
	end
end

local function IsMe(row)
	local guid = UnitGUID and Clean(UnitGUID("player"))
	if guid and row.guid and row.guid == guid then return true end
	local me = UnitName("player")
	local name = type(row.name) == "string" and row.name
	return name and (name == me or name:match("^([^%-]+)") == me) or false
end

-- Registers an event only when this client knows it (unknown events raise an error on modern clients).
local function SafeRegister(self, event, handler)
	if C_EventUtils and type(C_EventUtils.IsEventValid) == "function" then
		local ok, valid = pcall(C_EventUtils.IsEventValid, event)
		if ok and not valid then return end
	end
	pcall(self.RegisterEvent, self, event, handler)
end

---------------------------------------------------------------------------
-- Counters: honor and kills are cumulative values; we add up their increases.
-- A drop (honor spent, daily reset) or a change of source only moves the baseline.
---------------------------------------------------------------------------
local function Feed(counter, value, source)
	if value == nil then return 0 end
	local gain = 0
	if counter.ready and counter.last and counter.source == source and value > counter.last then
		gain = value - counter.last
	end
	counter.last, counter.source = value, source
	return gain
end

local function NewSession()
	return { start = time(), honor = 0, hks = 0, bgHonor = 0, worldHonor = 0, worldHks = 0, games = 0 }
end

function PvP:Session()
	local key = ns.PlayerKey()
	local sessions = self:Global().session
	sessions[key] = sessions[key] or NewSession()
	return sessions[key]
end

local function PerHour(amount, seconds)
	if not seconds or seconds < 60 then return 0 end
	return amount / seconds * 3600
end

function PvP:SessionHonorPerHour()
	local s = self:Session()
	return PerHour(s.honor, time() - s.start)
end

-- Takes fresh baselines; gains are only counted once the game data has settled after a loading screen.
function PvP:ResetBaselines()
	self.honorCounter, self.killCounter = {}, {}
	self:UpdateCounters()
	self.honorCounter.ready, self.killCounter.ready = true, true
end

function PvP:UpdateCounters()
	if not self.honorCounter then return end
	local s = self:Session()
	local game = self.game
	if not game and self.graceGame and GetTime() < (self.graceUntil or 0) then game = self.graceGame end
	local honor, honorSource = ReadHonor()
	local gain = Feed(self.honorCounter, honor, honorSource)
	if gain > 0 then
		s.honor = s.honor + gain
		if game then
			game.honor = (game.honor or 0) + gain
			s.bgHonor = s.bgHonor + gain
		else
			s.worldHonor = s.worldHonor + gain
		end
	end
	local hks, killSource = ReadKills()
	local kills = Feed(self.killCounter, hks, killSource)
	if kills > 0 then
		s.hks = s.hks + kills
		if game then
			game.hks = (game.hks or 0) + kills
		else
			s.worldHks = s.worldHks + kills
		end
	end
	if gain > 0 or kills > 0 then
		self:UpdatePanel()
		self:RenderWindow()
	end
end

-- Many events can fire together (currency, kills, chat): read the counters once, a moment later.
function PvP:QueueCounters()
	if self.countersQueued then return end
	self.countersQueued = true
	C_Timer.After(0.5, function()
		self.countersQueued = false
		self:UpdateCounters()
	end)
end

---------------------------------------------------------------------------
-- Battleground games
---------------------------------------------------------------------------
function PvP:StartGame(name, mapID)
	local now = time()
	local game = {
		bg = name, map = mapID, start = now, lastSeen = now,
		char = ns.PlayerKey(), faction = UnitFactionGroup("player"),
		honor = 0, hks = 0,
	}
	self:Global().current[ns.PlayerKey()] = game
	self.game = game
	return game
end

function PvP:FinishGame(game, leftAt)
	local key = game.char or ns.PlayerKey()
	game.left = leftAt or time()
	game.duration = math.max(0, (game.ended or game.left) - game.start)
	game.result = game.result or "unknown"
	game.lastSeen = nil
	local games = self:Global().games
	games[key] = games[key] or {}
	local list = games[key]
	list[#list + 1] = game
	while #list > MAX_GAMES do table.remove(list, 1) end
	self:Global().current[key] = nil
	if self.game == game then self.game = nil end
	self.graceGame, self.graceUntil = game, GetTime() + GRACE_TIME
	self.pendingScore = nil
	local s = self:Session()
	s.games = (s.games or 0) + 1
	if self:Settings().announce and not leftAt then
		-- Wait for the end-of-match honor to arrive before printing the summary.
		C_Timer.After(5, function() self:Announce(game) end)
	end
	self:RenderWindow()
end

local function ResultText(result)
	if result == "win" then return UI.Colorize(L["Victory"], C.good) end
	if result == "loss" then return UI.Colorize(L["Defeat"], C.bad) end
	return UI.Colorize(L["Unknown"], C.muted)
end

local function GameHonor(game)
	if game.honor and game.honor > 0 then return game.honor end
	return game.scoreHonor or game.honor or 0
end

local function GameKills(game)
	return game.scoreHks or game.hks or 0
end

function PvP:Announce(game)
	ns.Print(string.format(L["%s: %s in %s, %s honor, %d honorable kills."], game.bg or "?", ResultText(game.result),
		ns.FormatDuration(game.duration), ns.FormatNumber(math.floor(GameHonor(game))), GameKills(game)))
end

-- Called when the zone changes: starts, resumes or closes a game.
function PvP:CheckInstance()
	local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
	local inBG = instanceType == "pvp"
	self.inBG = inBG
	local key = ns.PlayerKey()
	local current = self.game or self:Global().current[key]
	if current then
		local fresh = time() - (current.lastSeen or current.start or 0) < RESUME_DELAY
		if inBG and fresh and (current.map == instanceID or current.bg == name) then
			self.game = current
		elseif inBG then
			-- A different battleground (or a game left long ago): close the old one first.
			self:FinishGame(current, current.lastSeen)
			self:StartGame(name, instanceID)
		else
			self:UpdateCounters()
			self:FinishGame(current, (not fresh) and current.lastSeen or nil)
		end
	elseif inBG then
		self:StartGame(name, instanceID)
	end
	self:UpdatePanel()
end

-- Looks for the end of the match; the result is the winner compared with our team.
function PvP:CheckMatchEnd()
	local game = self.game
	if not game or game.ended then return end
	local winner = MatchWinner()
	if winner == nil then return end
	game.ended = time()
	local team = MyTeam()
	if team and winner == team then
		game.result = "win"
	elseif team and (winner == 0 or winner == 1) then
		game.result = "loss"
	else
		game.result = "unknown"
	end
	self.pendingScore = true
	if type(RequestBattlefieldScoreData) == "function" then pcall(RequestBattlefieldScoreData) end
	self:ReadScore()
end

-- Our own scoreboard line, once the match is over and only out of combat.
function PvP:ReadScore()
	local game = self.game
	if not (self.pendingScore and game and game.ended) or InCombatLockdown() then return end
	if type(GetNumBattlefieldScores) ~= "function" then self.pendingScore = nil return end
	local ok, count = pcall(GetNumBattlefieldScores)
	count = ok and Number(count)
	if not count or count == 0 then return end
	for i = 1, count do
		local row = ScoreRow(i)
		if row and IsMe(row) then
			game.kb, game.scoreHks, game.deaths, game.scoreHonor = row.kb, row.hks, row.deaths, row.honor
			game.players = count
			self.pendingScore = nil
			return
		end
	end
end

function PvP:OnBattlefieldEvent()
	if not self.game then self:CheckInstance() end
	self:CheckMatchEnd()
	self:ReadScore()
end

function PvP:Tick()
	if self.game then
		self.game.lastSeen = time()
		self:CheckMatchEnd()
	end
	self:UpdatePanel()
end

---------------------------------------------------------------------------
-- Session panel
---------------------------------------------------------------------------
function PvP:CreatePanel()
	if self.panel then return end
	local f = UI.Panel("ForeverCompanionPvPPanel", 230, 98, function() return self:Settings() end)
	f.title = UI.Text(f, 13, C.accent)
	f.title:SetPoint("TOPLEFT", 14, -9)
	f.title:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	f.title:SetWordWrap(false)
	f.values = {}
	for i, label in ipairs({ L["Time in game"], L["Honor this session"], L["Honor per hour"] }) do
		local text = UI.Text(f, 12, C.muted)
		text:SetPoint("TOPLEFT", 14, -12 - i * 20)
		text:SetText(label)
		local value = UI.Text(f, 12, C.gold, "RIGHT")
		value:SetPoint("TOPRIGHT", -12, -12 - i * 20)
		f.values[i] = value
	end
	f:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then self:ShowWindow() end
	end)
	f:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(L["Right-click: open the PvP window"], 1, 1, 1)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip_Hide() end)
	self.panel = f
	self:PlacePanel()
end

function PvP:PlacePanel()
	local f, p = self.panel, self:Settings().point
	if not f then return end
	f:ClearAllPoints()
	f:SetPoint(p[1], UIParent, p[3], p[4], p[5])
end

function PvP:UpdatePanel()
	local f = self.panel
	if not f then return end
	local s = self:Settings()
	local show = s.showPanel and (self.inBG or not s.panelOnlyInBG)
	f:SetShown(show and true or false)
	if not show then return end
	local game = self.game
	f.title:SetText(game and game.bg or L["World PvP"])
	f.values[1]:SetText(game and ns.FormatDuration(time() - game.start) or "--")
	f.values[2]:SetText(ns.FormatNumber(math.floor(self:Session().honor)))
	f.values[3]:SetText(ns.FormatNumber(math.floor(self:SessionHonorPerHour())))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
-- Columns: { share of the width, alignment }.
local BG_COLUMNS = { { 0.34 }, { 0.11, "RIGHT" }, { 0.11, "RIGHT" }, { 0.12, "RIGHT" }, { 0.16, "RIGHT" }, { 0.16, "RIGHT" } }
local GAME_COLUMNS = { { 0.15 }, { 0.31 }, { 0.14 }, { 0.14, "RIGHT" }, { 0.14, "RIGHT" }, { 0.12, "RIGHT" } }

local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetHeight(ROW_HEIGHT)
	row.bg = UI.Fill(row, C.panel, "BACKGROUND")
	row.bg:SetAllPoints()
	row.cells = {}
	for i = 1, 6 do
		local cell = UI.Text(row, 13)
		cell:SetWordWrap(false)
		row.cells[i] = cell
	end
	return row
end

local function FillRow(row, columns, width, values, header, shade)
	local bg = header and C.header or shade and C.panel2 or C.panel
	row.bg:SetVertexColor(bg[1], bg[2], bg[3], 1)
	local color = header and C.muted or C.text
	local x, usable = 10, width - 20
	for i, cell in ipairs(row.cells) do
		local col = columns[i]
		if col then
			local w = usable * col[1]
			cell:ClearAllPoints()
			cell:SetPoint("LEFT", row, "LEFT", x, 0)
			cell:SetWidth(math.max(10, w - 8))
			cell:SetJustifyH(col[2] or "LEFT")
			cell:SetTextColor(color[1], color[2], color[3])
			cell:SetText(values[i] or "")
			cell:Show()
			x = x + w
		else
			cell:Hide()
		end
	end
end

-- Finished games of this character (or of every character), newest first.
function PvP:Games()
	local list = {}
	local all = self:Global().games
	if self:Settings().allCharacters then
		for _, games in pairs(all) do
			for _, game in ipairs(games) do list[#list + 1] = game end
		end
	else
		for _, game in ipairs(all[ns.PlayerKey()] or {}) do list[#list + 1] = game end
	end
	table.sort(list, function(a, b) return (a.start or 0) > (b.start or 0) end)
	return list
end

-- Per-battleground totals, most played first.
local function BattlegroundStats(games)
	local byKey, list = {}, {}
	for _, game in ipairs(games) do
		local key = game.map or game.bg or "?"
		local stat = byKey[key]
		if not stat then
			stat = { name = game.bg or "?", games = 0, wins = 0, duration = 0, honor = 0 }
			byKey[key] = stat
			list[#list + 1] = stat
		end
		stat.games = stat.games + 1
		if game.result == "win" then stat.wins = stat.wins + 1 end
		stat.duration = stat.duration + (game.duration or 0)
		stat.honor = stat.honor + GameHonor(game)
	end
	table.sort(list, function(a, b)
		if a.games ~= b.games then return a.games > b.games end
		return a.name < b.name
	end)
	return list
end

function PvP:CreateWindow()
	if self.window then return end
	local f = UI.Window("ForeverCompanionPvP", L["PvP & battlegrounds"], 720, 600, self:Global().window,
		{ resizable = true, minWidth = 560, minHeight = 380 })
	f.OnResized = function() self:RenderWindow() end

	-- Toolbar: character filter.
	local bar = CreateFrame("Frame", nil, f.content)
	bar:SetPoint("TOPLEFT", 16, -10)
	bar:SetPoint("TOPRIGHT", -16, -10)
	bar:SetHeight(26)
	local show = UI.Text(bar, 12, C.muted)
	show:SetPoint("LEFT", 0, 0)
	show:SetText(L["Show:"])
	f.filters = {}
	local function Filter(text, allCharacters)
		local b = UI.Button(bar, text, 140, 24, "normal", function()
			self:Settings().allCharacters = allCharacters
			self:RenderWindow()
		end)
		b.allCharacters = allCharacters
		f.filters[#f.filters + 1] = b
		return b
	end
	Filter(L["This character"], false):SetPoint("LEFT", show, "RIGHT", 10, 0)
	Filter(L["All characters"], true):SetPoint("LEFT", f.filters[1], "RIGHT", 6, 0)
	f.reset = UI.Button(bar, L["Reset session"], 130, 24, "ghost", function()
		self:Global().session[ns.PlayerKey()] = NewSession()
		self:UpdatePanel()
		self:RenderWindow()
	end)
	f.reset:SetPoint("RIGHT", 0, 0)

	local scroll = UI.Scroll(f.content)
	scroll:SetPoint("TOPLEFT", 0, -44)
	scroll:SetPoint("BOTTOMRIGHT", -4, 4)
	f.scroll = scroll
	local child = scroll.child
	f.stack = UI.Stack(child, 16)

	f.chipBar = CreateFrame("Frame", nil, child)
	f.chips = {}
	for i = 1, 4 do
		local chip = UI.Chip(f.chipBar, 13)
		if i == 1 then chip:SetPoint("LEFT", 0, 0) else chip:SetPoint("LEFT", f.chips[i - 1], "RIGHT", 8, 0) end
		f.chips[i] = chip
	end
	f.bgTitle = UI.SectionTitle(child, L["Battlegrounds"])
	f.recentTitle = UI.SectionTitle(child, L["Recent games"])
	f.empty = CreateFrame("Frame", nil, child)
	f.empty.text = UI.Text(f.empty, 13, C.muted)
	f.empty.text:SetPoint("TOPLEFT", 0, 0)
	f.empty.text:SetPoint("RIGHT", 0, 0)
	f.empty.text:SetText(L["No battleground recorded yet. Join one and your games will appear here."])
	f.rows = UI.Pool(CreateRow)
	self.window = f
end

function PvP:ShowWindow()
	self:CreateWindow()
	self.window:Show()
	self:RenderWindow()
end

function PvP:ToggleWindow()
	if self.window and self.window:IsShown() then self.window:Hide() else self:ShowWindow() end
end

function PvP:RenderWindow()
	local f = self.window
	if not f or not f:IsShown() then return end
	local allCharacters = self:Settings().allCharacters
	for _, b in ipairs(f.filters) do
		local c = b.allCharacters == (allCharacters and true or false) and C.accent or C.border
		b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
		local t = b.allCharacters == (allCharacters and true or false) and C.accent or C.text
		b.label:SetTextColor(t[1], t[2], t[3])
	end

	local s = self:Session()
	f.subtitle:SetText(string.format(L["Session: %s honor, %d honorable kills, %s honor/hour"],
		ns.FormatNumber(math.floor(s.honor)), s.hks, ns.FormatNumber(math.floor(self:SessionHonorPerHour()))))

	local games = self:Games()
	local wins, duration, honor = 0, 0, 0
	for _, game in ipairs(games) do
		if game.result == "win" then wins = wins + 1 end
		duration = duration + (game.duration or 0)
		honor = honor + GameHonor(game)
	end

	local child, stack = f.scroll.child, f.stack
	local width = math.max(400, child:GetWidth() - 32)
	f.rows:ReleaseAll()
	stack:Reset()
	stack:Space(12)

	f.chips[1]:Set(string.format(L["Games: %d"], #games), C.text)
	f.chips[2]:Set(string.format(L["Wins: %d"], wins), C.good)
	f.chips[3]:Set(string.format(L["Win rate: %.0f%%"], ns.Percent(wins, #games)), C.gold)
	f.chips[4]:Set(string.format(L["Honor/hour: %s"], ns.FormatNumber(math.floor(PerHour(honor, duration)))), C.accent)
	stack:Add(f.chipBar, 24)

	local hasGames = #games > 0
	f.empty:SetShown(not hasGames)
	f.bgTitle:SetShown(hasGames)
	f.recentTitle:SetShown(hasGames)
	if not hasGames then
		stack:Add(f.empty, 40, 20)
		f.scroll:SetContentHeight(stack.y + 10)
		return
	end

	-- Per battleground.
	stack:Add(f.bgTitle, nil, 16)
	stack:Space(6)
	local header = f.rows:Acquire(child)
	FillRow(header, BG_COLUMNS, width, { L["Battleground"], L["Games"], L["Wins"], L["Win %"], L["Avg. duration"], L["Avg. honor"] }, true)
	stack:Add(header, ROW_HEIGHT)
	for i, stat in ipairs(BattlegroundStats(games)) do
		local row = f.rows:Acquire(child)
		FillRow(row, BG_COLUMNS, width, {
			stat.name, stat.games, stat.wins,
			string.format("%.0f%%", ns.Percent(stat.wins, stat.games)),
			ns.FormatDuration(stat.duration / stat.games),
			ns.FormatNumber(math.floor(stat.honor / stat.games)),
		}, false, i % 2 == 0)
		stack:Add(row, ROW_HEIGHT)
	end

	-- Recent games.
	stack:Add(f.recentTitle, nil, 20)
	stack:Space(6)
	header = f.rows:Acquire(child)
	FillRow(header, GAME_COLUMNS, width, { L["Date"], L["Battleground"], L["Result"], L["Duration"], L["Honor"], L["HKs"] }, true)
	stack:Add(header, ROW_HEIGHT)
	for i = 1, math.min(#games, MAX_RECENT) do
		local game = games[i]
		local where = game.bg or "?"
		if allCharacters and game.char then
			where = where .. UI.Colorize("  " .. (game.char:match("^([^%-]+)") or game.char), C.muted)
		end
		local row = f.rows:Acquire(child)
		FillRow(row, GAME_COLUMNS, width, {
			date("%d/%m %H:%M", game.start or 0), where, ResultText(game.result),
			ns.FormatDuration(game.duration), ns.FormatNumber(math.floor(GameHonor(game))), GameKills(game),
		}, false, i % 2 == 0)
		stack:Add(row, ROW_HEIGHT)
	end
	f.scroll:SetContentHeight(stack.y + 16)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function PvP:PLAYER_ENTERING_WORLD(_, isInitialLogin)
	local key = ns.PlayerKey()
	local sessions = self:Global().session
	if isInitialLogin or not sessions[key] then sessions[key] = NewSession() end
	-- Baselines are taken a little later, once currencies are loaded, so a login never counts as a gain.
	self.honorCounter, self.killCounter = {}, {}
	self:UpdateCounters()
	C_Timer.After(3, function()
		if self:IsEnabled() then self:ResetBaselines() end
	end)
	self:CheckInstance()
end

function PvP:OnEnable()
	self:CreatePanel()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CheckInstance")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		self:ReadScore()
		self:QueueCounters()
	end)
	self:RegisterEvent("PLAYER_LOGOUT", function()
		if self.game then self.game.lastSeen = time() end
	end)
	SafeRegister(self, "UPDATE_BATTLEFIELD_STATUS", "OnBattlefieldEvent")
	SafeRegister(self, "UPDATE_BATTLEFIELD_SCORE", "OnBattlefieldEvent")
	SafeRegister(self, "PVP_MATCH_COMPLETE", "OnBattlefieldEvent")
	for _, event in ipairs({ "CURRENCY_DISPLAY_UPDATE", "HONOR_CURRENCY_UPDATE", "PLAYER_PVP_KILLS_CHANGED",
		"PLAYER_PVP_RANK_CHANGED", "CHAT_MSG_COMBAT_HONOR_GAIN" }) do
		SafeRegister(self, event, "QueueCounters")
	end
	self.ticker = C_Timer.NewTicker(1, function() self:Tick() end)
	if IsLoggedIn and IsLoggedIn() then self:PLAYER_ENTERING_WORLD() end
end

function PvP:OnDisable()
	if self.ticker then self.ticker:Cancel() end
	self.ticker = nil
	if self.panel then self.panel:Hide() end
end

function PvP:OnProfileChanged()
	self:PlacePanel()
	self:UpdatePanel()
	self:RenderWindow()
end

ns.RegisterCommand("pvp", L["battleground history and honor stats"], function() PvP:ToggleWindow() end)

function PvP:GetOptions()
	local get, set = ns.ProfileAccessors("PvP", function()
		self:UpdatePanel()
		self:RenderWindow()
	end)
	return {
		get = get, set = set,
		args = {
			open = { type = "execute", order = 1, name = L["PvP & battlegrounds"], func = function() self:ShowWindow() end },
			showPanel = { type = "toggle", order = 2, name = L["Show the session panel"] },
			panelOnlyInBG = { type = "toggle", order = 3, name = L["Only in battlegrounds"] },
			locked = { type = "toggle", order = 4, name = L["Lock position"] },
			announce = { type = "toggle", order = 5, width = "full", name = L["Print a summary at the end of each battleground"] },
			allCharacters = { type = "toggle", order = 6, width = "full", name = L["Show the games of all characters in the window"] },
			resetSession = { type = "execute", order = 7, name = L["Reset session"], func = function()
				self:Global().session[ns.PlayerKey()] = NewSession()
				self:UpdatePanel()
				self:RenderWindow()
			end },
			clear = { type = "execute", order = 8, name = L["Forget this character's games"], confirm = true, func = function()
				self:Global().games[ns.PlayerKey()] = nil
				self:RenderWindow()
			end },
			help = { type = "description", order = 9, name = "\n" .. L["/fc pvp opens the window. Right-click the session panel to open it too. Honor counts every gain, world PvP included."] },
		},
	}
end
