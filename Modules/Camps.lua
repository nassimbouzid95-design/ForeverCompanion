-- ForeverCompanion: WoW Forever camps.
-- The camping system is new in Forever and its API is not documented yet, so this module relies on
-- what every client exposes: your position and your own buffs (readable out of combat).
-- Camp buffs are recognised by name patterns that you can edit in the options.
local _, ns = ...
local L = ns.L

local Camps = ns.NewModule("Camps", {
	showTracker = true,
	locked = false,
	point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -220, -220 },
	patterns = "camp\ncampement\nfeu de camp\ncampfire\nbivouac",
	warnExpire = 60,
	autoRecord = true,
}, {
	camps = {}, -- list of { map, x, y, name, visits, last }
})

local function Patterns(self)
	local list = {}
	for line in (self:Settings().patterns or ""):gmatch("[^\n]+") do
		line = strtrim(line):lower()
		if line ~= "" then list[#list + 1] = line end
	end
	return list
end

-- Our own camp-related buffs, as { name, icon, expires, duration }.
function Camps:ScanBuffs()
	local found = {}
	if InCombatLockdown() then return self.lastBuffs or found end
	local patterns = Patterns(self)
	for i = 1, 40 do
		local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
		if not aura then break end
		local name = aura.name
		if name and not ns.IsSecret(name) then
			local lower = name:lower()
			for _, p in ipairs(patterns) do
				if lower:find(p, 1, true) then
					found[#found + 1] = { name = name, icon = aura.icon, expires = aura.expirationTime, duration = aura.duration }
					break
				end
			end
		end
	end
	self.lastBuffs = found
	return found
end

function Camps:CreateTracker()
	if self.frame then return end
	local f = CreateFrame("Frame", "ForeverCompanionCampFrame", UIParent)
	f:SetSize(200, 20)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(frame) if not self:Settings().locked then frame:StartMoving() end end)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		self:Settings().point = { point, "UIParent", relPoint, x, y }
	end)
	f.lines = {}
	self.frame = f
end

function Camps:UpdateTracker()
	local f = self.frame
	if not f then return end
	local s = self:Settings()
	f:ClearAllPoints()
	f:SetPoint(s.point[1], UIParent, s.point[3], s.point[4], s.point[5])
	local buffs = s.showTracker and self:ScanBuffs() or {}
	for i, buff in ipairs(buffs) do
		local line = f.lines[i]
		if not line then
			line = CreateFrame("Frame", nil, f)
			line:SetSize(200, 20)
			line.icon = line:CreateTexture(nil, "ARTWORK")
			line.icon:SetSize(18, 18)
			line.icon:SetPoint("LEFT")
			line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			line.text:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
			f.lines[i] = line
		end
		line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * 22)
		line.icon:SetTexture(buff.icon)
		local left = buff.expires and buff.expires > 0 and (buff.expires - GetTime()) or nil
		line.text:SetText(buff.name .. "  " .. (left and ns.FormatDuration(left) or ""))
		if left and left < s.warnExpire then
			line.text:SetTextColor(1, 0.3, 0.3)
			local key = buff.name .. ":" .. tostring(buff.expires)
			self.warned = self.warned or {}
			if not self.warned[key] then
				self.warned[key] = true
				ns.Print(string.format(L["%s expires in %s"], buff.name, ns.FormatDuration(left)))
				PlaySound(SOUNDKIT.RAID_WARNING or 8959)
			end
		else
			line.text:SetTextColor(1, 1, 1)
		end
		line:Show()
	end
	for i = #buffs + 1, #f.lines do f.lines[i]:Hide() end
	f:SetHeight(math.max(20, #buffs * 22))
	f:SetShown(#buffs > 0)
end

-- Remembers a camp at the current position (merged with a known camp within 40 yards).
function Camps:RecordCamp(name)
	local mapID, x, y = ns.PlayerMapPosition()
	if not x then return end
	for _, camp in ipairs(self:Global().camps) do
		if camp.map == mapID then
			local d = ns.MapVector(mapID, x, y, camp.x, camp.y)
			if d and d < 40 then
				camp.visits = (camp.visits or 0) + 1
				camp.last = time()
				if name and name ~= "" then camp.name = name end
				return camp, false
			end
		end
	end
	local camp = { map = mapID, x = x, y = y, name = name ~= "" and name or ns.MapName(mapID), visits = 1, last = time() }
	table.insert(self:Global().camps, camp)
	return camp, true
end

function Camps:UNIT_AURA(_, unit)
	if unit ~= "player" or InCombatLockdown() then return end
	local buffs = self:ScanBuffs()
	if self:Settings().autoRecord and #buffs > 0 and not self.hadBuff then
		local _, isNew = self:RecordCamp(buffs[1].name)
		if isNew then ns.Print(L["New camp remembered."]) end
	end
	self.hadBuff = #buffs > 0
	self:UpdateTracker()
end

function Camps:OnEnable()
	self:CreateTracker()
	self:RegisterEvent("UNIT_AURA")
	self.ticker = C_Timer.NewTicker(1, function() self:UpdateTracker() end)
	self:UpdateTracker()
end

function Camps:OnDisable()
	if self.ticker then self.ticker:Cancel() end
	if self.frame then self.frame:Hide() end
end

function Camps:OnProfileChanged()
	self:UpdateTracker()
end

ns.RegisterCommand("camp", L["[name] - remember a camp at your position"], function(rest)
	local camp, isNew = Camps:RecordCamp(rest)
	if camp then
		ns.Print(isNew and L["New camp remembered."] or L["Camp updated."])
	else
		ns.Print(L["Your position is not available here."])
	end
end)

Camps.campArgs = {}
function Camps:RefreshCampOptions()
	local args = wipe(self.campArgs)
	local camps = self:Global().camps
	if #camps == 0 then
		args.empty = { type = "description", order = 0, name = L["No camp yet. They are added when you get a camp buff, or with /fc camp."] }
	end
	for i, camp in ipairs(camps) do
		args["c" .. i] = {
			type = "group", inline = true, order = i,
			name = string.format("%s - %s %.1f, %.1f (%d)", camp.name, ns.MapName(camp.map), camp.x * 100, camp.y * 100, camp.visits or 1),
			args = {
				go = { type = "execute", order = 1, name = L["Show the way"], func = function() ns.SetWaypoint(camp.map, camp.x, camp.y, camp.name, "camp") end },
				delete = { type = "execute", order = 2, name = DELETE, func = function()
					table.remove(camps, i)
					self:RefreshCampOptions()
				end },
			},
		}
	end
	LibStub("AceConfigRegistry-3.0"):NotifyChange(ns.ADDON)
end

function Camps:GetOptions()
	self:RefreshCampOptions()
	local get, set = ns.ProfileAccessors("Camps", function() self:UpdateTracker() end)
	return {
		get = get, set = set,
		args = {
			showTracker = { type = "toggle", order = 1, name = L["Show camp buff timers"] },
			locked = { type = "toggle", order = 2, name = L["Lock position"] },
			autoRecord = { type = "toggle", order = 3, width = "full", name = L["Remember a camp automatically when you get a camp buff"] },
			warnExpire = { type = "range", order = 4, name = L["Warn before expiry (seconds)"], min = 0, max = 600, step = 10 },
			patterns = {
				type = "input", order = 5, multiline = 5, width = "full",
				name = L["Camp buff names (one per line, partial match)"],
			},
			list = { type = "group", order = 10, name = L["Known camps"], args = self.campArgs },
		},
	}
end
