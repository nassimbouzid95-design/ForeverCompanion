-- ForeverCompanion: map coordinates and personal map notes.
local _, ns = ...
local L = ns.L

local Map = ns.NewModule("Map", {
	worldMapCoords = true,
	minimapCoords = true,
	decimals = 1,
}, {
	notes = {}, -- list of { map, x, y, text, added }
})

---------------------------------------------------------------------------
-- Coordinates
---------------------------------------------------------------------------
function Map:FormatCoords(x, y)
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
		local px, py = mapID and ns.PlayerPositionOn(mapID)
		if px then parts[#parts + 1] = L["Player"] .. ": " .. self:FormatCoords(px, py) end
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
		text:SetText(x and self:FormatCoords(x, y) or "")
	end)
	self.miniText = holder
end

function Map:ApplySettings()
	local s = self:Settings()
	self:CreateWorldMapCoords()
	self:CreateMinimapCoords()
	if self.worldText then self.worldText:SetShown(s.worldMapCoords) end
	if self.miniText then self.miniText:SetShown(s.minimapCoords) end
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
			notes = {
				type = "group", order = 10, name = L["My notes"],
				args = self.notesArgs,
			},
		},
	}
end
