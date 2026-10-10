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
	if Arrow:IsEnabled() then Arrow:Refresh() end
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
	f:SetSize(56, 42)
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
		if waypoint then
			GameTooltip:AddLine(string.format("%s  %.1f, %.1f", ns.MapName(waypoint.mapID), waypoint.x * 100, waypoint.y * 100), 1, 1, 1)
		end
		GameTooltip:AddLine(L["Right-click to clear"], 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)

	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetTexture("Interface\\Minimap\\MinimapArrow")
	tex:SetSize(42, 42)
	tex:SetPoint("CENTER")
	f.arrow = tex

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", f, "BOTTOM", 0, -2)
	f.title = title
	local dist = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	dist:SetPoint("TOP", title, "BOTTOM", 0, -1)
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
		if self:Settings().blizzardPin and C_Map.CanSetUserWaypointOnMap(waypoint.mapID) then
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
	local px, py = ns.PlayerPositionOn(waypoint.mapID)
	if not px then
		-- Target is on another map, or position is hidden (instances).
		f.arrow:SetRotation(0)
		f.arrow:SetVertexColor(0.6, 0.6, 0.6)
		f.dist:SetText(string.format(L["Go to %s"], ns.MapName(waypoint.mapID)))
		return
	end
	local distance, angle = ns.MapVector(waypoint.mapID, px, py, waypoint.x, waypoint.y)
	if not distance then return end
	local facing = GetPlayerFacing()
	if facing and not ns.IsSecret(facing) then
		f.arrow:SetRotation(angle - facing)
	end
	-- Green when facing it, red when behind.
	local diff = facing and math.abs(((angle - facing + math.pi) % (2 * math.pi)) - math.pi) or 0
	local t = diff / math.pi
	f.arrow:SetVertexColor(t, 1 - t * 0.5, 0.1)
	f.dist:SetFormattedText(L["%d yards"], distance)

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
