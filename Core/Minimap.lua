-- ForeverCompanion: minimap button and data-broker launcher.
local ADDON, ns = ...
local L = ns.L

local ICON = "Interface\\Icons\\INV_Misc_Map_01"

local function OnClick(_, button)
	if button == "RightButton" then
		ns.OpenOptions()
	elseif IsShiftKeyDown() and ns.ToggleRouteWindow then
		ns.ToggleRouteWindow()
	elseif ns.ToggleDungeonGuide then
		ns.ToggleDungeonGuide()
	end
end

local function OnTooltipShow(tooltip)
	tooltip:AddLine(ns.TAG .. " " .. (ns.VERSION or ""))
	tooltip:AddLine(" ")
	tooltip:AddLine(L["Left-click: dungeon & raid guide"], 1, 1, 1)
	tooltip:AddLine(L["Shift-click: XP route"], 1, 1, 1)
	tooltip:AddLine(L["Right-click: options"], 1, 1, 1)
	tooltip:AddLine(L["Drag: move the button"], 0.7, 0.7, 0.7)
end

-- Fallback button when LibDBIcon is not installed.
local function CreateOwnButton(db)
	local button = CreateFrame("Button", "ForeverCompanionMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(ICON)
	icon:SetPoint("TOPLEFT", 7, -6)

	local function UpdatePosition()
		local angle = math.rad(db.angle or 215)
		local radius = (Minimap:GetWidth() / 2) + 5
		button:ClearAllPoints()
		button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
	end

	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
			UpdatePosition()
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button:SetScript("OnClick", OnClick)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		OnTooltipShow(GameTooltip)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)

	UpdatePosition()
	return button
end

function ns.SetupMinimap()
	local db = ns.FC.db.profile.minimap
	local LDB = LibStub("LibDataBroker-1.1", true)
	local launcher = LDB and LDB:NewDataObject(ADDON, {
		type = "launcher",
		text = "Forever",
		icon = ICON,
		OnClick = OnClick,
		OnTooltipShow = OnTooltipShow,
	})

	local DBIcon = LibStub("LibDBIcon-1.0", true)
	if DBIcon and launcher then
		DBIcon:Register(ADDON, launcher, db)
		ns.UpdateMinimapButton = function()
			if ns.FC.db.profile.minimap.hide then DBIcon:Hide(ADDON) else DBIcon:Show(ADDON) end
		end
	else
		local button = CreateOwnButton(db)
		ns.UpdateMinimapButton = function()
			button:SetShown(not ns.FC.db.profile.minimap.hide)
		end
	end
	ns.UpdateMinimapButton()
end
