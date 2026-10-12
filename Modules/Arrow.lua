-- ForeverCompanion: navigation arrow pointing to the current waypoint.
-- Other modules call ns.SetWaypoint(mapID, x, y, title, owner) and ns.ClearWaypoint(owner).
local _, ns = ...
local L = ns.L

local Arrow = ns.NewModule("Arrow", {
	scale = 1,
	locked = false,
	point = { "CENTER", "UIParent", "CENTER", 0, 180 },
	arrivalDistance = 12,
	blizzardPin = true,
})

local waypoint -- { mapID, x, y, title, owner }

-- Public API, usable even when the module is off (the arrow just stays hidden).
function ns.SetWaypoint(mapID, x, y, title, owner)
	if not (mapID and x and y) then return end
	waypoint = { mapID = mapID, x = x, y = y, title = title or "", owner = owner }
	waypoint.continent, waypoint.wx, waypoint.wy = ns.MapToWorld(mapID, x, y)
	if Arrow:IsEnabled() then Arrow:Refresh() end
end

-- Waypoint given in world coordinates (quest and instance databases use them).
function ns.SetWorldWaypoint(continent, wx, wy, title, owner)
	if not (continent and wx and wy) then return end
	if continent < 0 then return ns.SetWaypoint(-continent, wx / 10000, wy / 10000, title, owner) end
	waypoint = { continent = continent, wx = wx, wy = wy, title = title or "", owner = owner }
	-- Best map to show it on: the zone the player is in, if the point is there.
	local here = C_Map.GetBestMapForUnit("player")
	local x, y = ns.WorldToMap(continent, wx, wy, here)
	if x then waypoint.mapID, waypoint.x, waypoint.y = here, x, y end
	if Arrow:IsEnabled() then Arrow:Refresh() end
end

function ns.SameWaypoint(continent, wx, wy)
	return waypoint and waypoint.continent == continent and waypoint.wx == wx and waypoint.wy == wy
end

function ns.ClearWaypoint(owner)
	if waypoint and (owner == nil or waypoint.owner == owner) then
		waypoint = nil
		if Arrow:IsEnabled() then Arrow:Refresh() end
	end
end

function ns.GetWaypoint()
	return waypoint
end

-- Callbacks fired when the player reaches the waypoint: ns.arrivalCallbacks[owner] = function(wp) end
ns.arrivalCallbacks = {}

function Arrow:CreateFrame()
	if self.frame then return end
	local f = CreateFrame("Button", "ForeverCompanionArrow", UIParent)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:RegisterForClicks("RightButtonUp")
	f:SetScript("OnDragStart", function(frame)
		if not self:Settings().locked then frame:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		self:Settings().point = { point, "UIParent", relPoint, x, y }
	end)
	f:SetScript("OnClick", function() ns.ClearWaypoint() end)
	f:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
		GameTooltip:AddLine(waypoint and waypoint.title ~= "" and waypoint.title or L["Waypoint"])
		if waypoint and waypoint.mapID then
			GameTooltip:AddLine(string.format("%s  %.1f, %.1f", ns.MapName(waypoint.mapID), waypoint.x * 100, waypoint.y * 100), 1, 1, 1)
		end
		GameTooltip:AddLine(L["Right-click to clear"], 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)

	local UI, C = ns.UI, ns.UI.COLORS
	f:SetSize(84, 84)
	local ring = f:CreateTexture(nil, "BACKGROUND")
	ring:SetTexture(UI.MEDIA .. "Ring")
	ring:SetAllPoints()
	f.ring = ring
	local glow = f:CreateTexture(nil, "BORDER")
	glow:SetTexture(UI.MEDIA .. "Glow")
	glow:SetPoint("CENTER")
	glow:SetSize(110, 110)
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0)
	f.glow = glow
	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetTexture(UI.MEDIA .. "Arrow")
	tex:SetSize(60, 60)
	tex:SetPoint("CENTER")
	f.arrow = tex

	local title = UI.Text(f, 15, C.gold, "CENTER")
	title:SetPoint("TOP", f, "BOTTOM", 0, -4)
	title:SetWidth(260)
	title:SetWordWrap(false)
	f.title = title
	local dist = UI.Text(f, 13, C.text, "CENTER")
	dist:SetPoint("TOP", title, "BOTTOM", 0, -3)
	f.dist = dist

	local elapsed = 0
	f:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.05 then return end
		elapsed = 0
		self:Update()
	end)
	self.frame = f
end

function Arrow:ApplyLayout()
	local f, s = self.frame, self:Settings()
	f:SetScale(s.scale)
	f:ClearAllPoints()
	f:SetPoint(s.point[1], UIParent, s.point[3], s.point[4], s.point[5])
end

function Arrow:Refresh()
	self:CreateFrame()
	self:ApplyLayout()
	if waypoint then
		self.frame.title:SetText(waypoint.title)
		self.frame:Show()
		if self:Settings().blizzardPin and waypoint.mapID and C_Map.CanSetUserWaypointOnMap(waypoint.mapID) then
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(waypoint.mapID, waypoint.x, waypoint.y))
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	else
		self.frame:Hide()
		if self:Settings().blizzardPin and C_Map.HasUserWaypoint() then C_Map.ClearUserWaypoint() end
	end
end

function Arrow:Update()
	local f = self.frame
	if not waypoint then f:Hide() return end
	local distance, angle
	local continent, px, py = ns.PlayerWorldPosition()
	if continent and waypoint.continent then
		if continent ~= waypoint.continent then
			f.arrow:SetRotation(0)
			f.arrow:SetVertexColor(0.6, 0.6, 0.6)
			f.glow:SetAlpha(0)
			f.dist:SetText(string.format(L["Go to %s"], L[ns.CONTINENT_NAMES[waypoint.continent] or "Kalimdor"]))
			return
		end
		distance, angle = ns.WorldVector(px, py, waypoint.wx, waypoint.wy)
	elseif waypoint.mapID then
		local mx, my = ns.PlayerPositionOn(waypoint.mapID)
		if mx then distance, angle = ns.MapVector(waypoint.mapID, mx, my, waypoint.x, waypoint.y) end
	end
	if not distance then
		-- Position hidden (inside an instance) or unknown.
		f.arrow:SetRotation(0)
		f.arrow:SetVertexColor(0.6, 0.6, 0.6)
		f.glow:SetAlpha(0)
		f.dist:SetText(waypoint.mapID and string.format(L["Go to %s"], ns.MapName(waypoint.mapID)) or "")
		return
	end
	local facing = GetPlayerFacing()
	if facing and not ns.IsSecret(facing) then
		f.arrow:SetRotation(angle - facing)
	end
	-- Green when facing it, yellow on the side, red when behind; glows when right on target.
	local diff = facing and math.abs(((angle - facing + math.pi) % (2 * math.pi)) - math.pi) or 0
	local t = diff / math.pi
	if t < 0.5 then
		f.arrow:SetVertexColor(0.3 + t * 1.4, 1, 0.35 - t * 0.5)
	else
		f.arrow:SetVertexColor(1, 1 - (t - 0.5) * 1.6, 0.1)
	end
	f.glow:SetAlpha(t < 0.06 and 0.35 or 0)
	f.glow:SetVertexColor(0.3, 1, 0.4)

	-- Time to arrival from the speed measured over the last seconds.
	local now = GetTime()
	local track = self.track
	if not track or track.target ~= waypoint then
		track = { target = waypoint, time = now, dist = distance, speed = 0 }
		self.track = track
	elseif now - track.time >= 1 then
		local speed = (track.dist - distance) / (now - track.time)
		track.speed = track.speed * 0.6 + speed * 0.4
		track.time, track.dist = now, distance
	end
	local text = string.format(L["%d yards"], distance)
	if track.speed > 1 then
		text = text .. ns.UI.Colorize("  ·  " .. ns.FormatDuration(distance / track.speed), ns.UI.COLORS.muted)
	end
	f.dist:SetText(text)

	if distance <= self:Settings().arrivalDistance then
		local reached = waypoint
		local callback = reached.owner and ns.arrivalCallbacks[reached.owner]
		if callback then
			callback(reached)
		else
			ns.ClearWaypoint()
			PlaySound(SOUNDKIT.MAP_PING)
		end
	end
end

local function ParseWay(text)
	-- "/fc way 45.2 61.8 title" on the current map, or "/fc way 1453 45.2 61.8 title".
	local nums, rest = {}, text
	for _ = 1, 3 do
		local n, r = rest:match("^%s*([%d%.]+)[,%s]*(.*)$")
		if not n then break end
		nums[#nums + 1] = tonumber(n)
		rest = r
	end
	local mapID, x, y
	if #nums == 3 then
		mapID, x, y = nums[1], nums[2], nums[3]
	elseif #nums == 2 then
		mapID, x, y = C_Map.GetBestMapForUnit("player"), nums[1], nums[2]
	else
		return nil
	end
	if x > 1 then x = x / 100 end
	if y > 1 then y = y / 100 end
	return mapID, x, y, rest
end

function Arrow:OnEnable()
	self:Refresh()
end

function Arrow:OnDisable()
	if self.frame then self.frame:Hide() end
end

function Arrow:OnProfileChanged()
	self:Refresh()
end

ns.RegisterCommand("way", L["[mapID] x y [title] - set a waypoint, with no argument clears it"], function(rest)
	if rest == "" then ns.ClearWaypoint() return end
	local mapID, x, y, title = ParseWay(rest)
	if not mapID then
		ns.Print(L["Usage: /fc way [mapID] x y [title]"])
		return
	end
	ns.SetWaypoint(mapID, x, y, title ~= "" and title or nil, "manual")
end)

function Arrow:GetOptions()
	local get, set = ns.ProfileAccessors("Arrow", function() self:Refresh() end)
	return {
		get = get, set = set,
		args = {
			locked = { type = "toggle", order = 1, name = L["Lock position"] },
			scale = { type = "range", order = 2, name = L["Scale"], min = 0.5, max = 2, step = 0.05 },
			arrivalDistance = { type = "range", order = 3, name = L["Arrival distance (yards)"], min = 3, max = 50, step = 1 },
			blizzardPin = { type = "toggle", order = 4, width = "full", name = L["Also place Blizzard's map pin on the waypoint"] },
		},
	}
end
