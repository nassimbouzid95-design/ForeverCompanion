-- ForeverCompanion: level ranges of the outdoor zones, by Classic uiMapID (Classic Era 1.15 numbering).
-- ns.ZoneLevels[uiMapID] = { min, max, faction = "Alliance" | "Horde" | nil }
-- faction marks a faction's home territory (starting zones, their neighbours and the capitals);
-- contested zones have none. Capitals are listed with 1-60 so they never trigger a level warning.
--
-- Missing on purpose: Forever's new zones (Mount Hyjal, Shen'dralas, Riverglades, Zephras Isle).
-- Add them here once their uiMapIDs and level ranges are known.
local _, ns = ...

ns.ZoneLevels = {
	-- Kalimdor
	[1411] = { 1, 10, faction = "Horde" },     -- Durotar
	[1412] = { 1, 10, faction = "Horde" },     -- Mulgore
	[1413] = { 10, 25, faction = "Horde" },    -- The Barrens
	[1438] = { 1, 10, faction = "Alliance" },  -- Teldrassil
	[1439] = { 10, 20, faction = "Alliance" }, -- Darkshore
	[1440] = { 18, 30 },                       -- Ashenvale
	[1441] = { 25, 35 },                       -- Thousand Needles
	[1442] = { 15, 27 },                       -- Stonetalon Mountains
	[1443] = { 30, 40 },                       -- Desolace
	[1444] = { 40, 50 },                       -- Feralas
	[1445] = { 35, 45 },                       -- Dustwallow Marsh
	[1446] = { 40, 50 },                       -- Tanaris
	[1447] = { 45, 55 },                       -- Azshara
	[1448] = { 48, 55 },                       -- Felwood
	[1449] = { 48, 55 },                       -- Un'Goro Crater
	[1450] = { 1, 60 },                        -- Moonglade (no hostile mobs, never warns)
	[1451] = { 55, 60 },                       -- Silithus
	[1452] = { 55, 60 },                       -- Winterspring
	[1454] = { 1, 60, faction = "Horde" },     -- Orgrimmar
	[1456] = { 1, 60, faction = "Horde" },     -- Thunder Bluff
	[1457] = { 1, 60, faction = "Alliance" },  -- Darnassus

	-- Eastern Kingdoms
	[1416] = { 30, 40 },                       -- Alterac Mountains
	[1417] = { 30, 40 },                       -- Arathi Highlands
	[1418] = { 35, 45 },                       -- Badlands
	[1419] = { 45, 55 },                       -- Blasted Lands
	[1420] = { 1, 10, faction = "Horde" },     -- Tirisfal Glades
	[1421] = { 10, 20, faction = "Horde" },    -- Silverpine Forest
	[1422] = { 51, 58 },                       -- Western Plaguelands
	[1423] = { 53, 60 },                       -- Eastern Plaguelands
	[1424] = { 20, 30 },                       -- Hillsbrad Foothills
	[1425] = { 40, 50 },                       -- The Hinterlands
	[1426] = { 1, 10, faction = "Alliance" },  -- Dun Morogh
	[1427] = { 43, 50 },                       -- Searing Gorge
	[1428] = { 50, 58 },                       -- Burning Steppes
	[1429] = { 1, 10, faction = "Alliance" },  -- Elwynn Forest
	[1430] = { 55, 60 },                       -- Deadwind Pass
	[1431] = { 18, 30 },                       -- Duskwood
	[1432] = { 10, 20, faction = "Alliance" }, -- Loch Modan
	[1433] = { 15, 25, faction = "Alliance" }, -- Redridge Mountains
	[1434] = { 30, 45 },                       -- Stranglethorn Vale
	[1435] = { 35, 45 },                       -- Swamp of Sorrows
	[1436] = { 10, 20, faction = "Alliance" }, -- Westfall
	[1437] = { 20, 30 },                       -- Wetlands
	[1453] = { 1, 60, faction = "Alliance" },  -- Stormwind City
	[1455] = { 1, 60, faction = "Alliance" },  -- Ironforge
	[1458] = { 1, 60, faction = "Horde" },     -- Undercity
}

-- Level range of a map, walking up to its parent zone (caves and sub-maps have their own uiMapID).
function ns.ZoneLevelInfo(mapID)
	local guard = 0
	while mapID and guard < 6 do
		local info = ns.ZoneLevels[mapID]
		if info then return info, mapID end
		local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
		mapID = mapInfo and mapInfo.parentMapID
		guard = guard + 1
	end
end
