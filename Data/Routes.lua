-- ForeverCompanion: XP route registry.
--
-- A route is a list of steps for a level range, restricted to a faction, some races and/or
-- some classes. The Route module picks, at each moment, the first route that matches the
-- character and its level, and follows its steps.
--
-- ns.RegisterRoute({
--     id = "skyborne-horde-1-12",            -- unique id, used to save progress
--     name = "Zephras Isle (Skyborne)",
--     faction = "Horde",                     -- "Alliance", "Horde" or nil for both
--     races = { "Skyborne" },                -- race file names (UnitRace 2nd return), nil = all
--     classes = nil,                         -- class file names (UnitClass 2nd return), nil = all
--     minLevel = 1, maxLevel = 12,           -- the route applies while the player is in this range
--     style = "quests",                      -- "quests", "dungeons" (quests + dungeons) or "fastest"
--     steps = {
--         { "goto",     map = 1234, x = 0.45, y = 0.62, text = "Talk to ..." },
--         { "accept",   quest = 90001, map = 1234, x = 0.45, y = 0.62, npc = "Name" },
--         { "complete", quest = 90001, map = 1234, x = 0.51, y = 0.40, text = "Kill 8 ..." },
--         { "turnin",   quest = 90001, map = 1234, x = 0.45, y = 0.62 },
--         { "level",    level = 6, text = "Grind to level 6" },
--         { "train",    map = 1234, x = 0.40, y = 0.50, text = "Train new spells" },
--         { "dungeon",  instance = 389, text = "Ragefire Chasm" },
--         { "note",     text = "Free text" },
--     },
-- })
--
-- Steps are written from the real Forever client: use "/fc route record" while playing to turn
-- your own quest accepts, completions and turn-ins into steps, then "/fc route export".
-- Routes are shipped in Data\Routes\*.lua files as they are written and tested.
local _, ns = ...

ns.Routes = {}

local VALID_STEPS = {
	["goto"] = true, accept = true, complete = true, turnin = true,
	level = true, train = true, dungeon = true, note = true,
}

function ns.RegisterRoute(route)
	assert(type(route) == "table" and route.id and route.steps, "ForeverCompanion: invalid route")
	for i, step in ipairs(route.steps) do
		assert(VALID_STEPS[step[1]], "ForeverCompanion: route " .. route.id .. " step " .. i .. " has an unknown type")
	end
	route.minLevel = route.minLevel or 1
	route.maxLevel = route.maxLevel or 60
	ns.Routes[#ns.Routes + 1] = route
end

-- Generated routes (Data\RoutesAuto.lua) are packed in a string, expanded the first time the route is used:
--   a<quest> accept, c<quest>[@n] objectives (n-th objective point), t<quest> turn in, x<quest> abandon,
--   l<level> grind to level, d<key>@<level>,<last level> dungeon (ns.InstanceDB key), g<cont>,<x>,<y>,<zone>[,s] travel
--   (zone = index in ns.RouteZones, s = boat or zeppelin).  Positions come from ns.QuestDB.
-- Localised name of ns.RouteZones[index] = { uiMapID, English name }.
function ns.RouteZoneName(index)
	local z = ns.RouteZones and ns.RouteZones[index]
	if not z then return nil end
	local info = z[1] > 0 and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(z[1])
	return info and info.name or z[2]
end

local function QuestPoint(q, i)
	if q then return q[i], q[i + 1], q[i + 2] end
end

-- Map position (uiMapID, x, y as fractions) of a point of a new zone, kept by ns.ResolveNewZones.
local function MapPoint(step, m)
	if m then step.map, step.x, step.y = m[1], m[2], m[3] end
	if step.cont and step.cont < 0 then step.map, step.x, step.y = -step.cont, step.wx / 10000, step.wy / 10000 end
end

local function Expand(route)
	local steps = {}
	local npcs, names = ns.QuestNPCs or {}, ns.QuestNPCNames or {}
	for token in route.packed:gmatch("%S+") do
		local kind, rest = token:sub(1, 1), token:sub(2)
		local step
		if kind == "a" or kind == "t" or kind == "c" or kind == "x" then
			local id, point = rest:match("^(%d+)@?(%d*)$")
			id = tonumber(id)
			local q = ns.QuestDB and ns.QuestDB[id]
			local who = npcs[id]
			if kind == "a" then
				step = { "accept", quest = id, npc = who and names[who[1]] or nil }
				step.cont, step.wx, step.wy = QuestPoint(q, 8)
				MapPoint(step, q and q.sm)
			elseif kind == "t" then
				step = { "turnin", quest = id, npc = who and names[who[2]] or nil }
				step.cont, step.wx, step.wy = QuestPoint(q, 11)
				MapPoint(step, q and q.em)
			elseif kind == "c" then
				step = { "complete", quest = id }
				local o = q and q[14]
				if o and #o >= 3 then
					local i = (tonumber(point) or 0) * 3 + 1
					if not o[i] then i = 1 end
					step.cont, step.wx, step.wy = o[i], o[i + 1], o[i + 2]
					MapPoint(step, q.om and q.om[i])
				end
			else
				step = { "note", quest = id, abandon = true }
			end
		elseif kind == "l" then
			step = { "level", level = tonumber(rest) }
		elseif kind == "d" then
			local key, lvl, maxLvl = rest:match("^([^@]+)@?(%d*),?(%d*)$")
			step = { "dungeon", key = key, lvl = tonumber(lvl), maxLvl = tonumber(maxLvl) }
			for _, entry in ipairs(ns.InstanceDB or {}) do
				if entry.key == key then step.instance = entry.id; step.entry = entry break end
			end
		elseif kind == "g" then
			local c, x, y, z, ship = rest:match("^(-?%d+),(-?%d+),(-?%d+),(%d+),?([sa]?)$")
			if c then
				step = { "goto", zone = ns.RouteZoneName(tonumber(z)), ship = ship == "s" or nil, airship = ship == "a" or nil }
				local c0, x0, y0 = tonumber(c), tonumber(x), tonumber(y)
				step.cont, step.wx, step.wy = ns.ResolvePosition(c0, x0, y0)
				if c0 < 0 then step.map, step.x, step.y = -c0, x0 / 10000, y0 / 10000 end
			end
		end
		if step then steps[#steps + 1] = step end
	end
	return steps
end

local PACKED = { __index = function(route, key)
	if key == "steps" then
		local steps = Expand(route)
		rawset(route, "steps", steps)
		return steps
	end
end }

function ns.RegisterPackedRoute(id, zone, faction, races, class, minLevel, maxLevel, packed)
	ns.Routes[#ns.Routes + 1] = setmetatable({
		id = id, name = ns.RouteZoneName(zone) or "", faction = faction, races = races, classes = class and { class } or nil,
		minLevel = minLevel, maxLevel = maxLevel, auto = true, packed = packed,
	}, PACKED)
end

local function Contains(list, value)
	if not list then return true end
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

-- Routes that fit a character, sorted by level range then by preference for the chosen style.
function ns.MatchingRoutes(faction, race, class, style, extraRoutes)
	local result = {}
	local function consider(route)
		if (not route.faction or route.faction == faction)
			and Contains(route.races, race)
			and Contains(route.classes, class)
			and (not route.style or route.style == style or route.style == "quests") then
			result[#result + 1] = route
		end
	end
	for _, route in ipairs(ns.Routes) do consider(route) end
	for _, route in ipairs(extraRoutes or {}) do consider(route) end
	table.sort(result, function(a, b)
		if a.minLevel ~= b.minLevel then return a.minLevel < b.minLevel end
		-- Prefer the exact style over the generic "quests" route, then the most specific route.
		local aExact = a.style == style and 1 or 0
		local bExact = b.style == style and 1 or 0
		if aExact ~= bExact then return aExact > bExact end
		local aSpec = (a.races and 1 or 0) + (a.classes and 1 or 0)
		local bSpec = (b.races and 1 or 0) + (b.classes and 1 or 0)
		return aSpec > bSpec
	end)
	return result
end
