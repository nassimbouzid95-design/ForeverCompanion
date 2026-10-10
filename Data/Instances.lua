-- ForeverCompanion: reference list of instances.
-- Keyed by instance map ID (8th return of GetInstanceInfo, 10th of EJ_GetInstanceInfo).
-- Bosses and loot lists come from the in-game Adventure Guide at runtime; drop rates come
-- from the drop collector and from ns.DropRates (Data files that can be filled in later).
-- Instances discovered in game that are missing here (new Forever dungeons) are added
-- automatically by the drop collector.
local _, ns = ...

-- kind: "dungeon" or "raid". min/max: recommended levels. size: players.
-- zone: uiMapID of the zone holding the entrance, x/y: entrance position (used to place a waypoint).
-- Entrance positions use the Classic map IDs and are approximate: check them on the Forever client.
ns.Instances = {
	-- Classic dungeons
	[389] = { name = "Ragefire Chasm", kind = "dungeon", min = 13, max = 18, size = 5, zone = 1454, x = 0.517, y = 0.585 },
	[43]  = { name = "Wailing Caverns", kind = "dungeon", min = 17, max = 24, size = 5, zone = 1413, x = 0.462, y = 0.357 },
	[36]  = { name = "The Deadmines", kind = "dungeon", min = 17, max = 26, size = 5, zone = 1436, x = 0.424, y = 0.716 },
	[33]  = { name = "Shadowfang Keep", kind = "dungeon", min = 22, max = 30, size = 5, zone = 1421, x = 0.448, y = 0.678 },
	[48]  = { name = "Blackfathom Deeps", kind = "dungeon", min = 24, max = 32, size = 5, zone = 1440, x = 0.142, y = 0.140 },
	[34]  = { name = "The Stockade", kind = "dungeon", min = 24, max = 32, size = 5, zone = 1453, x = 0.506, y = 0.665 },
	[90]  = { name = "Gnomeregan", kind = "dungeon", min = 29, max = 38, size = 5, zone = 1426, x = 0.243, y = 0.396 },
	[47]  = { name = "Razorfen Kraul", kind = "dungeon", min = 29, max = 38, size = 5, zone = 1413, x = 0.407, y = 0.946 },
	[189] = { name = "Scarlet Monastery", kind = "dungeon", min = 26, max = 45, size = 5, zone = 1420, x = 0.825, y = 0.330 },
	[129] = { name = "Razorfen Downs", kind = "dungeon", min = 37, max = 46, size = 5, zone = 1413, x = 0.490, y = 0.950 },
	[70]  = { name = "Uldaman", kind = "dungeon", min = 41, max = 51, size = 5, zone = 1418, x = 0.429, y = 0.130 },
	[209] = { name = "Zul'Farrak", kind = "dungeon", min = 42, max = 46, size = 5, zone = 1446, x = 0.390, y = 0.213 },
	[349] = { name = "Maraudon", kind = "dungeon", min = 46, max = 55, size = 5, zone = 1443, x = 0.290, y = 0.625 },
	[109] = { name = "The Temple of Atal'Hakkar", kind = "dungeon", min = 50, max = 56, size = 5, zone = 1435, x = 0.698, y = 0.540 },
	[230] = { name = "Blackrock Depths", kind = "dungeon", min = 52, max = 60, size = 5, zone = 1428, x = 0.293, y = 0.384 },
	[229] = { name = "Blackrock Spire", kind = "dungeon", min = 55, max = 60, size = 10, zone = 1428, x = 0.293, y = 0.384 },
	[429] = { name = "Dire Maul", kind = "dungeon", min = 55, max = 60, size = 5, zone = 1444, x = 0.589, y = 0.443 },
	[289] = { name = "Scholomance", kind = "dungeon", min = 58, max = 60, size = 5, zone = 1422, x = 0.690, y = 0.729 },
	[329] = { name = "Stratholme", kind = "dungeon", min = 58, max = 60, size = 5, zone = 1423, x = 0.312, y = 0.142 },

	-- Classic raids
	[309] = { name = "Zul'Gurub", kind = "raid", min = 60, max = 60, size = 20, zone = 1434, x = 0.534, y = 0.172 },
	[509] = { name = "Ruins of Ahn'Qiraj", kind = "raid", min = 60, max = 60, size = 20, zone = 1451, x = 0.365, y = 0.938 },
	[409] = { name = "Molten Core", kind = "raid", min = 60, max = 60, size = 40, zone = 1428, x = 0.293, y = 0.384 },
	[249] = { name = "Onyxia's Lair", kind = "raid", min = 60, max = 60, size = 40, zone = 1445, x = 0.529, y = 0.776 },
	[469] = { name = "Blackwing Lair", kind = "raid", min = 60, max = 60, size = 40, zone = 1428, x = 0.293, y = 0.384 },
	[531] = { name = "Temple of Ahn'Qiraj", kind = "raid", min = 60, max = 60, size = 40, zone = 1451, x = 0.469, y = 0.075 },
	[533] = { name = "Naxxramas", kind = "raid", min = 60, max = 60, size = 40, zone = 1423, x = 0.398, y = 0.258 },
}

-- WoW Forever raids announced at BlizzCon 2026. Their instance IDs are not known yet, so they are
-- matched by name until the drop collector records the real ID the first time someone zones in.
ns.ForeverRaids = {
	{ name = "Hyjal Summit", kind = "raid", min = 60, max = 60, size = 20 },
	{ name = "Barrow Deeps", kind = "raid", min = 60, max = 60, size = 10 },
}

-- Reference drop rates, keyed by instance ID then by npc ID (boss or trash) then by item ID,
-- as a percentage. Empty on purpose: only verified numbers belong here. Rates measured in game
-- by the drop collector are always shown, and are merged with these when both exist.
--   ns.DropRates[230] = { [9019] = { [11931] = 21.4 } }
ns.DropRates = {}

-- Localised instance name: the game knows the name of every instance map ID.
function ns.InstanceName(instanceID)
	local name = GetRealZoneText and GetRealZoneText(instanceID)
	if name and name ~= "" then return name end
	local info = ns.Instances[instanceID]
	return info and info.name or ("#" .. tostring(instanceID))
end
