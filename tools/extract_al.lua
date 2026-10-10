-- Run AtlasLoot Classic's dungeon data in a stub environment and print it as JSON.
local path = arg[1]
local idc = 0
local function newid() idc = idc + 1 return idc end
local diffs = {}
local data = setmetatable({}, { __index = {
	AddDifficulty = function(self, name) local id = newid(); diffs[id] = name; return id end,
	AddItemTableType = function() return newid() end,
	AddExtraItemTableType = function() return newid() end,
	AddContentType = function(self, name) return name end,
} })
local entries = {}
local dmt = getmetatable(data)
dmt.__newindex = function(t, k, v) rawset(t, k, v); entries[#entries + 1] = k end
local loc = setmetatable({}, { __index = function(_, k) return k end })
AtlasLoot = {
	ItemDB = { Add = function() return data end },
	Locales = loc, IngameLocales = loc,
	ReturnForGameVersion = function(a) return a end,
	CLASSIC_VERSION_NUM = 1,
	GetLocales = function() return nil end,
	GameVersion_LT = function(self, v, value) return value == nil and true or value end,
	GameVersion_GE = function(self, v, value) if v == 1 then return value == nil and true or value end return nil end,
	BC_VERSION_NUM = 2, WRATH_VERSION_NUM = 3,
}
UnitFactionGroup = function() return "Horde" end
C_Map = { GetAreaInfo = function(id) return "Area" .. id end }
FACTION_HORDE = "Horde"; FACTION_ALLIANCE = "Alliance"
setmetatable(_G, { __index = function(_, k) return k end })
local chunk = assert(loadfile(path))
chunk("AtlasLootClassic_DungeonsAndRaids")

local function esc(s) return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"' end
local out = {}
local function w(s) out[#out + 1] = s end
w("[")
for i, key in ipairs(entries) do
	local inst = rawget(data, key)
	if type(inst) == "table" and inst.items then
		w((i > 1 and "," or "") .. "{")
		w('"key":' .. esc(key) .. ',"name":' .. esc(inst.name or "") .. ',"instanceID":' .. tostring(inst.InstanceID or "null") .. ',"mapID":' .. tostring(inst.MapID or "null"))
		w(',"content":' .. esc(inst.ContentType or ""))
		if type(inst.LevelRange) == "table" then w(',"levels":[' .. table.concat(inst.LevelRange, ",") .. ']') end
		w(',"bosses":[')
		local first = true
		for _, b in ipairs(inst.items) do
			if type(b) == "table" then
				local loot = {}
				for diffID, list in pairs(b) do
					if type(diffID) == "number" and type(list) == "table" then
						for _, e in ipairs(list) do
							if type(e) == "table" and type(e[2]) == "number" then loot[#loot + 1] = { e[1], e[2], diffs[diffID] } end
						end
					end
				end
				w((first and "" or ",") .. "{")
				first = false
				w('"name":' .. esc(b.name or "?") .. ',"npcID":' .. (type(b.npcID) == "table" and ("[" .. table.concat(b.npcID, ",") .. "]") or tostring(b.npcID or "null")))
				w(',"level":' .. esc(type(b.Level) == "table" and table.concat(b.Level, "-") or (b.Level or "")))
				w(',"special":' .. esc(b.specialType or "") .. ',"extra":' .. tostring(b.ExtraList and true or false))
				local parts = {}
				for _, l in ipairs(loot) do parts[#parts + 1] = "[" .. l[1] .. "," .. l[2] .. "," .. esc(l[3] or "") .. "]" end
				w(',"loot":[' .. table.concat(parts, ",") .. "]}")
			end
		end
		w("]}")
	end
end
w("]")
print(table.concat(out))
