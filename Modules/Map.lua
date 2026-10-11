-- ForeverCompanion: map coordinates and personal map notes.
local _, ns = ...
local L = ns.L

local Map = ns.NewModule("Map", {
	worldMapCoords = true,
	minimapCoords = true,
	decimals = 1,
	pinDungeons = true,
	pinQuests = true,
	pinObjectives = true,
	pinNotes = true,
	pinCamps = true,
	pinSize = 18,
}, {
	notes = {}, -- list of { map, x, y, text, added }
})

---------------------------------------------------------------------------
-- Coordinates
---------------------------------------------------------------------------
function Map:FormatCoords(x, y)
	if type(x) ~= "number" or type(y) ~= "number" or ns.AnySecret(x, y) then return "" end
	local fmt = "%." .. self:Settings().decimals .. "f, %." .. self:Settings().decimals .. "f"
	return string.format(fmt, x * 100, y * 100)
end

function Map:CreateWorldMapCoords()
	if self.worldText or not WorldMapFrame then return end
	local holder = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer or WorldMapFrame)
	holder:SetAllPoints()
	holder:SetFrameLevel((WorldMapFrame.ScrollContainer or WorldMapFrame):GetFrameLevel() + 20)
	local text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	text:SetPoint("BOTTOM", holder, "BOTTOM", 0, 8)
	text:SetShadowOffset(1, -1)
	local elapsed = 0
	holder:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.1 then return end
		elapsed = 0
		local parts = {}
		local mapID = WorldMapFrame:GetMapID()
		local px, py
		if mapID then px, py = ns.PlayerPositionOn(mapID) end
		if px and py then parts[#parts + 1] = L["Player"] .. ": " .. self:FormatCoords(px, py) end
		local cx, cy = WorldMapFrame:GetNormalizedCursorPosition()
		if cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 and WorldMapFrame.ScrollContainer:IsMouseOver() then
			parts[#parts + 1] = L["Cursor"] .. ": " .. self:FormatCoords(cx, cy)
		end
		text:SetText(table.concat(parts, "     "))
	end)
	self.worldText = holder
end

function Map:CreateMinimapCoords()
	if self.miniText then return end
	local holder = CreateFrame("Frame", nil, Minimap)
	holder:SetSize(80, 16)
	holder:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 2)
	holder:SetFrameLevel(Minimap:GetFrameLevel() + 10)
	local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	text:SetShadowOffset(1, -1)
	local elapsed = 0
	holder:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.2 then return end
		elapsed = 0
		local _, x, y = ns.PlayerMapPosition()
		text:SetText(self:FormatCoords(x, y))
	end)
	self.miniText = holder
end

function Map:ApplySettings()
	local s = self:Settings()
	self:CreateWorldMapCoords()
	self:CreateMinimapCoords()
	if self.worldText then self.worldText:SetShown(s.worldMapCoords) end
	if self.miniText then self.miniText:SetShown(s.minimapCoords) end
	self:HookWorldMap()
	ns.RefreshMapPins()
end

---------------------------------------------------------------------------
-- World map pins: dungeon and raid entrances, quests to pick up and turn in, quest objectives,
-- notes and camps. Pins are placed with world coordinates, so they show on zone and continent maps.
---------------------------------------------------------------------------
local pool, used = {}, {}

local function HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function SetIcon(texture, atlas, file)
	if atlas and HasAtlas(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(file)
		texture:SetTexCoord(0, 1, 0, 1)
	end
end

function Map:AcquirePin(canvas)
	local pin = table.remove(pool)
	if not pin then
		pin = CreateFrame("Button", nil, canvas)
		pin.icon = pin:CreateTexture(nil, "OVERLAY")
		pin.icon:SetAllPoints()
		pin:SetScript("OnEnter", function(frame)
			GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
			for i, line in ipairs(frame.lines or {}) do
				if i == 1 then GameTooltip:AddLine(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
			end
			GameTooltip:AddLine(L["Click: point the arrow here"], 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		pin:SetScript("OnLeave", GameTooltip_Hide)
		pin:SetScript("OnClick", function(frame)
			if frame.target then
				ns.SetWorldWaypoint(frame.target[1], frame.target[2], frame.target[3], frame.lines and frame.lines[1], "map")
			end
		end)
	end
	pin:SetParent(canvas)
	pin:SetFrameLevel(canvas:GetFrameLevel() + 2000)
	pin.icon:SetVertexColor(1, 1, 1)
	pin.icon:SetDesaturated(false)
	used[#used + 1] = pin
	return pin
end

function Map:ReleasePins()
	for _, pin in ipairs(used) do
		pin:Hide()
		pool[#pool + 1] = pin
	end
	wipe(used)
end

-- Adds a pin given world coordinates; skipped when the point is not on the displayed map.
function Map:AddPin(canvas, mapID, continent, wx, wy, kind, lines, size)
	local x, y = ns.WorldToMap(continent, wx, wy, mapID)
	if not x then return end
	local pin = self:AcquirePin(canvas)
	local scale = self.canvasScale or 1
	size = (size or self:Settings().pinSize) / scale
	pin:SetSize(size, size)
	pin:ClearAllPoints()
	pin:SetPoint("CENTER", canvas, "TOPLEFT", x * canvas:GetWidth(), -y * canvas:GetHeight())
	if kind == "dungeon" then
		SetIcon(pin.icon, "Dungeon", "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
	elseif kind == "raid" then
		SetIcon(pin.icon, "Raid", "Interface\\Icons\\INV_Misc_Head_Dragon_01")
	elseif kind == "accept" then
		SetIcon(pin.icon, nil, "Interface\\GossipFrame\\AvailableQuestIcon")
	elseif kind == "turnin" then
		SetIcon(pin.icon, nil, "Interface\\GossipFrame\\ActiveQuestIcon")
	elseif kind == "complete" then
		SetIcon(pin.icon, nil, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
	elseif kind == "camp" then
		SetIcon(pin.icon, nil, "Interface\\Icons\\INV_Misc_Bag_08")
	else
		SetIcon(pin.icon, nil, "Interface\\Icons\\INV_Misc_Note_01")
	end
	pin.lines = lines
	pin.target = { continent, wx, wy }
	pin:Show()
	return pin
end

local instanceWorld -- [instanceID] = { continent, wx, wy }
local function InstanceWorld(id, where)
	instanceWorld = instanceWorld or {}
	if instanceWorld[id] == nil then
		local continent, wx, wy = ns.MapToWorld(where.zone, where.x, where.y)
		instanceWorld[id] = continent and { continent, wx, wy } or false
	end
	return instanceWorld[id]
end

function Map:RefreshPins()
	if not (WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame.GetCanvas) then return end
	local canvas = WorldMapFrame:GetCanvas()
	local mapID = WorldMapFrame:GetMapID()
	self:ReleasePins()
	if not (canvas and mapID) or not self:IsEnabled() then return end
	local container = WorldMapFrame.ScrollContainer
	self.canvasScale = container and container.GetCanvasScale and container:GetCanvasScale() or 1
	local s = self:Settings()

	if s.pinDungeons then
		-- One pin per entrance, listing every instance behind it.
		local byEntrance = {}
		for id, where in pairs(ns.Instances) do
			local w = InstanceWorld(id, where)
			if w then
				local key = math.floor(w[2]) .. ":" .. math.floor(w[3])
				local group = byEntrance[key] or { w = w, names = {}, raid = true }
				byEntrance[key] = group
				group.names[#group.names + 1] = string.format("%s |cff888888(%d-%d)|r", ns.InstanceName(id), where.min, where.max)
				if where.kind ~= "raid" then group.raid = false end
			end
		end
		for _, group in pairs(byEntrance) do
			table.sort(group.names)
			local lines = { group.raid and L["Raid entrance"] or L["Dungeon entrance"] }
			for _, name in ipairs(group.names) do lines[#lines + 1] = name end
			self:AddPin(canvas, mapID, group.w[1], group.w[2], group.w[3], group.raid and "raid" or "dungeon", lines, s.pinSize + 4)
		end
	end

	local assistant = ns.QuestAssistant
	if assistant and ns.QuestDB and (s.pinQuests or s.pinObjectives) then
		local count = 0
		if s.pinQuests then
			for _, id in ipairs(assistant.pickups) do
				local q = ns.QuestDB[id]
				if self:AddPin(canvas, mapID, q[8], q[9], q[10], "accept", { assistant:Title(id), string.format(L["Quest level %d - pick it up here"], q[1] > 0 and q[1] or UnitLevel("player")) }) then
					count = count + 1
					if count >= 200 then break end
				end
			end
		end
		for _, a in ipairs(assistant.active) do
			local q = ns.QuestDB[a.id]
			if a.complete and s.pinQuests then
				self:AddPin(canvas, mapID, q[11], q[12], q[13], "turnin", { assistant:Title(a.id), L["Complete: turn it in here"] })
			elseif not a.complete and s.pinObjectives then
				local objectives = q[14]
				for i = 1, #objectives, 3 do
					self:AddPin(canvas, mapID, objectives[i], objectives[i + 1], objectives[i + 2], "complete", { assistant:Title(a.id), L["Quest objective area"] }, s.pinSize - 4)
				end
			end
		end
	end

	if s.pinNotes then
		for _, note in ipairs(self:Global().notes) do
			local continent, wx, wy = ns.MapToWorld(note.map, note.x, note.y)
			if continent then self:AddPin(canvas, mapID, continent, wx, wy, "note", { note.text, ns.MapName(note.map) }) end
		end
	end

	local Camps = ns.FC:GetModule("Camps", true)
	if s.pinCamps and Camps and Camps:IsEnabled() then
		for _, camp in ipairs(Camps:Global().camps or {}) do
			local continent, wx, wy = ns.MapToWorld(camp.map, camp.x, camp.y)
			if continent then self:AddPin(canvas, mapID, continent, wx, wy, "camp", { camp.name, L["Camp"] }) end
		end
	end
end

function ns.RefreshMapPins()
	if Map.pinsPending then return end
	Map.pinsPending = true
	C_Timer.After(0.1, function()
		Map.pinsPending = false
		Map:RefreshPins()
	end)
end

function Map:HookWorldMap()
	if self.mapHooked or not WorldMapFrame then return end
	self.mapHooked = true
	if WorldMapFrame.OnMapChanged then
		hooksecurefunc(WorldMapFrame, "OnMapChanged", function() ns.RefreshMapPins() end)
	end
	WorldMapFrame:HookScript("OnShow", function() ns.RefreshMapPins() end)
	-- Keep pins the same size on screen when zooming.
	local watcher = CreateFrame("Frame", nil, WorldMapFrame)
	local elapsed = 0
	watcher:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.2 then return end
		elapsed = 0
		local container = WorldMapFrame.ScrollContainer
		local scale = container and container.GetCanvasScale and container:GetCanvasScale() or 1
		local mapID = WorldMapFrame:GetMapID()
		if scale ~= self.canvasScale or mapID ~= self.pinMap then
			self.pinMap = mapID
			self:RefreshPins()
		end
	end)
end

---------------------------------------------------------------------------
-- Notes
---------------------------------------------------------------------------
function Map:AddNote(text)
	local mapID, x, y = ns.PlayerMapPosition()
	if not x then
		ns.Print(L["Your position is not available here."])
		return
	end
	table.insert(self:Global().notes, { map = mapID, x = x, y = y, text = text, added = time() })
	ns.Print(string.format(L["Note added: %s (%s %s)"], text, ns.MapName(mapID), self:FormatCoords(x, y)))
	self:RefreshNotesOptions()
	ns.RefreshMapPins()
end

-- The options table is built once, so the notes list is refilled in place when notes change.
Map.notesArgs = {}

function Map:RefreshNotesOptions()
	local args = wipe(self.notesArgs)
	if #self:Global().notes == 0 then
		args.empty = { type = "description", order = 0, name = L["No notes yet. Use /fc note <text> to add one at your position."] }
	end
	for i, note in ipairs(self:Global().notes) do
		args["n" .. i] = {
			type = "group", inline = true, order = i,
			name = string.format("%s - %s %s", note.text, ns.MapName(note.map), self:FormatCoords(note.x, note.y)),
			args = {
				go = {
					type = "execute", order = 1, name = L["Show the way"],
					func = function() ns.SetWaypoint(note.map, note.x, note.y, note.text, "note") end,
				},
				delete = {
					type = "execute", order = 2, name = DELETE,
					func = function()
						table.remove(self:Global().notes, i)
						self:RefreshNotesOptions()
					end,
				},
			},
		}
	end
	LibStub("AceConfigRegistry-3.0"):NotifyChange(ns.ADDON)
end

function Map:OnEnable()
	if WorldMapFrame then
		self:ApplySettings()
	else
		self:RegisterEvent("ADDON_LOADED", function(_, name)
			if name == "Blizzard_WorldMap" then self:ApplySettings() end
		end)
		self:CreateMinimapCoords()
	end
	self:ApplySettings()
end

function Map:OnDisable()
	if self.worldText then self.worldText:Hide() end
	if self.miniText then self.miniText:Hide() end
	self:ReleasePins()
end

function Map:OnProfileChanged()
	self:ApplySettings()
end

ns.RegisterCommand("note", L["<text> - add a map note at your position"], function(rest)
	if rest == "" then
		ns.Print(L["Usage: /fc note <text>"])
		return
	end
	Map:AddNote(rest)
end)

function Map:GetOptions()
	self:RefreshNotesOptions()
	local get, set = ns.ProfileAccessors("Map", function() self:ApplySettings() end)
	return {
		get = get, set = set,
		args = {
			worldMapCoords = { type = "toggle", order = 1, name = L["Coordinates on the world map"] },
			minimapCoords = { type = "toggle", order = 2, name = L["Coordinates under the minimap"] },
			decimals = { type = "range", order = 3, name = L["Decimals"], min = 0, max = 2, step = 1 },
			pins = { type = "header", order = 4, name = L["On the world map"] },
			pinDungeons = { type = "toggle", order = 5, name = L["Dungeon and raid entrances"] },
			pinQuests = { type = "toggle", order = 6, name = L["Quests to pick up and turn in"] },
			pinObjectives = { type = "toggle", order = 7, name = L["Objectives of my quests"] },
			pinNotes = { type = "toggle", order = 8, name = L["My notes"] },
			pinCamps = { type = "toggle", order = 9, name = L["Camps"] },
			pinSize = { type = "range", order = 10, name = L["Icon size"], min = 10, max = 32, step = 1 },
			notes = {
				type = "group", order = 10, name = L["My notes"],
				args = self.notesArgs,
			},
		},
	}
end
