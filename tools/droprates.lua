_G.AtlasLoot = { Data = { Droprate = { AddData = function(self, d) DATA = d end } } }
dofile(arg[1])
local f = assert(loadfile(arg[2])); f()
local parts = {}
for npc, items in pairs(DATA) do
	local p = {}
	for item, r in pairs(items) do p[#p + 1] = '"' .. item .. '":' .. r end
	parts[#parts + 1] = '"' .. npc .. '":{' .. table.concat(p, ",") .. "}"
end
local ov = {}
for item, r in pairs(DROPRATE_OV or {}) do if r then ov[#ov + 1] = '"' .. item .. '":' .. r end end
print('{"rates":{' .. table.concat(parts, ",") .. '},"override":{' .. table.concat(ov, ",") .. "}}")
