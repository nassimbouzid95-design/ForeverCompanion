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
