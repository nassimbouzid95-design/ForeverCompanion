-- ForeverCompanion: drop collector.
-- Blizzard does not publish drop rates, so they are measured: every corpse you loot inside a
-- dungeon or raid is recorded (which creature, which items), and every kill you see is counted.
-- rate = number of corpses that dropped the item / number of kills.
local _, ns = ...
local L = ns.L

local Collector = ns.NewModule("LootCollector", {
	announceNew = false,
}, {
	instances = {}, -- [instanceID] = { name, kind, size, npcs = { [npcID] = npcData }, encounters = { [encounterID] = { name, kills, npc } } }
	imported = {},  -- [exportID] = time, so the same export is never counted twice
})
-- npcData = { name, boss = encounterID|nil, kills = n, looted = n, items = { [itemID] = n } }

local seenGUIDs = {}     -- corpses already counted this session
local looted = {}        -- corpses already looted this session
local guidNames = {}     -- GUID -> name, learnt from nameplates / target / mouseover
local lastEncounter      -- { id, name, time }
local reverseIndex       -- [itemID] = list of { instanceID, npcID }

local function CurrentInstance()
	local name, instanceType, _, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
	if instanceType ~= "party" and instanceType ~= "raid" then return nil end
	return instanceID, name, instanceType == "raid" and "raid" or "dungeon", maxPlayers
end

function Collector:InstanceData(instanceID, name, kind, size)
	local db = self:Global().instances
	local data = db[instanceID]
	if not data then
		data = { npcs = {}, encounters = {} }
		db[instanceID] = data
	end
	data.name = name or data.name
	data.kind = kind or data.kind
	data.size = size or data.size
	return data
end

local function NPCData(instance, npcID, name)
	local npc = instance.npcs[npcID]
	if not npc then
		npc = { kills = 0, looted = 0, items = {} }
		instance.npcs[npcID] = npc
	end
	if name and not ns.IsSecret(name) then npc.name = name end
	return npc
end

-- Remember names of creatures as we see them, so loot sources can be named.
function Collector:LearnUnit(unit)
	local guid = UnitGUID(unit)
	if not guid or ns.IsSecret(guid) or UnitIsPlayer(unit) then return end
	local name = UnitName(unit)
	if name and not ns.IsSecret(name) then guidNames[guid] = name end
	-- A dead creature we can see is a kill, if it was tapped by us or our group.
	if UnitIsDead(unit) and not seenGUIDs[guid] and not UnitIsTapDenied(unit) then
		self:CountKill(guid, name)
	end
end

function Collector:CountKill(guid, name)
	local instanceID, iname, kind, size = CurrentInstance()
	if not instanceID then return end
	local npcID = ns.NPCIDFromGUID(guid)
	if not npcID then return end
	seenGUIDs[guid] = true
	local npc = NPCData(self:InstanceData(instanceID, iname, kind, size), npcID, name or guidNames[guid])
	npc.kills = npc.kills + 1
end

function Collector:ScanNameplates()
	if not CurrentInstance() then return end
	for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if unit then pcall(self.LearnUnit, self, unit) end
	end
end

function Collector:ENCOUNTER_END(_, encounterID, encounterName, _, _, success)
	if ns.AnySecret(encounterID, success) or success ~= 1 then return end
	local instanceID, iname, kind, size = CurrentInstance()
	if not instanceID then return end
	local instance = self:InstanceData(instanceID, iname, kind, size)
	local enc = instance.encounters[encounterID] or { kills = 0 }
	instance.encounters[encounterID] = enc
	if not ns.IsSecret(encounterName) then enc.name = encounterName end
	enc.kills = enc.kills + 1
	lastEncounter = { id = encounterID, name = enc.name, time = GetTime() }
end

-- Is this creature the boss of the encounter that just ended?
local function LinkBoss(instance, npcID, npc)
	if npc.boss then return end
	if not lastEncounter or GetTime() - lastEncounter.time > 180 then return end
	local enc = instance.encounters[lastEncounter.id]
	if not enc or enc.npc then return end
	-- Same name as the encounter, or a creature never met before looted right after the kill.
	if npc.name == lastEncounter.name or (npc.looted <= 1 and npc.kills <= 1) then
		npc.boss = lastEncounter.id
		enc.npc = npcID
	end
end

function Collector:LOOT_OPENED()
	local instanceID, iname, kind, size = CurrentInstance()
	if not instanceID then return end
	local instance = self:InstanceData(instanceID, iname, kind, size)
	local perCorpse = {} -- guid -> { [itemID] = true }

	for slot = 1, GetNumLootItems() do
		if GetLootSlotType(slot) == Enum.LootSlotType.Item then
			local itemID = ns.ItemIDFromLink(GetLootSlotLink(slot))
			local sources = { GetLootSourceInfo(slot) }
			for i = 1, #sources, 2 do
				local guid = sources[i]
				if itemID and guid and not ns.IsSecret(guid) and ns.NPCIDFromGUID(guid) then
					perCorpse[guid] = perCorpse[guid] or {}
					perCorpse[guid][itemID] = true
				end
			end
		end
	end

	for guid, items in pairs(perCorpse) do
		if not looted[guid] then
			looted[guid] = true
			local npcID = ns.NPCIDFromGUID(guid)
			local npc = NPCData(instance, npcID, guidNames[guid])
			if not seenGUIDs[guid] then
				seenGUIDs[guid] = true
				npc.kills = npc.kills + 1
			end
			npc.looted = npc.looted + 1
			LinkBoss(instance, npcID, npc)
			for itemID in pairs(items) do
				local isNew = not npc.items[itemID]
				npc.items[itemID] = (npc.items[itemID] or 0) + 1
				if isNew and self:Settings().announceNew then
					local _, link = C_Item.GetItemInfo(itemID)
					ns.Print(string.format(L["New drop recorded: %s from %s"], link or itemID, npc.name or npcID))
				end
			end
			reverseIndex = nil
		end
	end
end

---------------------------------------------------------------------------
-- Public API for the guide and the tooltips
---------------------------------------------------------------------------
-- Rate (percentage) of an item on a creature, merging reference rates when they exist.
function ns.DropRate(instanceID, npcID, itemID)
	local data = Collector:Global().instances[instanceID]
	local npc = data and data.npcs[npcID]
	local measured, kills
	if npc and npc.kills > 0 and npc.items[itemID] then
		kills = math.max(npc.kills, npc.looted)
		measured = npc.items[itemID] / kills * 100
	end
	local ref = ns.DropRates[instanceID] and ns.DropRates[instanceID][npcID] and ns.DropRates[instanceID][npcID][itemID]
	return measured or ref, kills or 0, ref
end

function ns.CollectedInstances()
	return Collector:Global().instances
end

-- Where does an item drop? List of { instanceID, npcID, name, rate, kills, boss }.
function ns.ItemDropSources(itemID)
	if not reverseIndex then
		reverseIndex = {}
		for instanceID, data in pairs(Collector:Global().instances) do
			for npcID, npc in pairs(data.npcs) do
				for id in pairs(npc.items) do
					reverseIndex[id] = reverseIndex[id] or {}
					table.insert(reverseIndex[id], { instanceID, npcID })
				end
			end
		end
	end
	local result = {}
	for _, entry in ipairs(reverseIndex[itemID] or {}) do
		local data = Collector:Global().instances[entry[1]]
		local npc = data.npcs[entry[2]]
		local rate, kills = ns.DropRate(entry[1], entry[2], itemID)
		result[#result + 1] = { instanceID = entry[1], npcID = entry[2], name = npc.name or ("#" .. entry[2]), rate = rate, kills = kills, boss = npc.boss }
	end
	table.sort(result, function(a, b) return (a.rate or 0) > (b.rate or 0) end)
	return result
end

---------------------------------------------------------------------------
-- Sharing: export your data, import someone else's (counts are added together).
---------------------------------------------------------------------------
function Collector:Export()
	return ns.Encode({
		kind = "drops",
		id = ns.PlayerKey() .. "-" .. time(),
		instances = self:Global().instances,
	})
end

function Collector:Import(text)
	local data = ns.Decode(text)
	if type(data) ~= "table" or data.kind ~= "drops" or type(data.instances) ~= "table" then
		ns.Print(L["This text is not valid drop data."])
		return
	end
	if type(data.id) == "string" and data.id:find(ns.PlayerKey() .. "-", 1, true) == 1 then
		ns.Print(L["This is your own data, it is already counted."])
		return
	end
	if self:Global().imported[data.id] then
		ns.Print(L["This data was already imported."])
		return
	end
	for instanceID, src in pairs(data.instances) do
		local dst = self:InstanceData(instanceID, src.name, src.kind, src.size)
		for encounterID, enc in pairs(src.encounters or {}) do
			local d = dst.encounters[encounterID] or { kills = 0 }
			dst.encounters[encounterID] = d
			d.name = d.name or enc.name
			d.npc = d.npc or enc.npc
			d.kills = d.kills + (enc.kills or 0)
		end
		for npcID, npc in pairs(src.npcs or {}) do
			local d = NPCData(dst, npcID, npc.name)
			d.boss = d.boss or npc.boss
			d.kills = d.kills + (npc.kills or 0)
			d.looted = d.looted + (npc.looted or 0)
			for itemID, n in pairs(npc.items or {}) do
				d.items[itemID] = (d.items[itemID] or 0) + n
			end
		end
	end
	self:Global().imported[data.id] = time()
	reverseIndex = nil
	ns.Print(L["Drop data imported."])
end

function Collector:OnEnable()
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("ENCOUNTER_END")
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() pcall(self.LearnUnit, self, "target") end)
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() pcall(self.LearnUnit, self, "mouseover") end)
	self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) pcall(self.LearnUnit, self, unit) end)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		local instanceID, name, kind, size = CurrentInstance()
		if instanceID then self:InstanceData(instanceID, name, kind, size) end
	end)
	self.ticker = C_Timer.NewTicker(0.5, function() self:ScanNameplates() end)
end

function Collector:OnDisable()
	if self.ticker then self.ticker:Cancel() end
end

ns.RegisterCommand("drops", L["export | import - share drop data"], function(rest)
	rest = rest:lower()
	if rest == "export" then
		ns.ShowCopyBox(L["Drop data"], Collector:Export())
	elseif rest == "import" then
		ns.ShowCopyBox(L["Import drop data"], "", function(text) Collector:Import(text) end)
	else
		ns.Print(L["Usage: /fc drops export | import"])
	end
end)

function Collector:GetOptions()
	local get, set = ns.ProfileAccessors("LootCollector")
	return {
		get = get, set = set,
		args = {
			about = {
				type = "description", order = 1, fontSize = "medium",
				name = L["Every corpse you loot in a dungeon or raid is recorded with its items, and every kill you see is counted. Rates are shown in the guide and in item tooltips with the number of kills they are based on: the more kills, the more reliable."] .. "\n",
			},
			announceNew = { type = "toggle", order = 2, width = "full", name = L["Announce in chat when a new drop is recorded"] },
			export = { type = "execute", order = 3, name = L["Export my data"], func = function() ns.ShowCopyBox(L["Drop data"], self:Export()) end },
			import = { type = "execute", order = 4, name = L["Import data"], func = function() ns.ShowCopyBox(L["Import drop data"], "", function(text) self:Import(text) end) end },
		},
	}
end
