-- ForeverCompanion: minimap button and data-broker launcher.
local ADDON, ns = ...
local L = ns.L

local ICON = "Interface\\AddOns\\ForeverCompanion\\Media\\Logo"

---------------------------------------------------------------------------
-- Hub: the menu opened by the minimap button, with every window of the addon.
---------------------------------------------------------------------------
local HUB_ENTRIES = {
	{ label = "Dungeon & raid guide", desc = "Bosses, loot and drop rates", icon = "Interface\\Icons\\INV_Misc_Book_09", command = "guide" },
	{ label = "Next quests", desc = "Quest assistant and XP route", icon = "Interface\\Icons\\INV_Misc_Map_01", run = function() if ns.ToggleRouteWindow then ns.ToggleRouteWindow() end end },
	{ label = "Economy", desc = "Gold, auction prices, professions", icon = "Interface\\Icons\\INV_Misc_Coin_01", command = "eco", module = "Economy" },
	{ label = "PvP", desc = "Battlegrounds and honor", icon = "Interface\\Icons\\INV_BannerPVP_02", command = "pvp", module = "PvP" },
	{ label = "Hardcore", desc = "Survival and dangers", icon = "Interface\\Icons\\Ability_Creature_Cursed_02", command = "hc", module = "Hardcore" },
	{ label = "My characters", desc = "Gold, levels, professions, lockouts", icon = "Interface\\Icons\\Achievement_Character_Human_Male", command = "alts" },
	{ label = "Options", desc = "Modules and settings", icon = "Interface\\Icons\\Trade_Engineering", run = function() ns.OpenOptions() end },
}

local hub
local function CreateHub()
	local UI, C = ns.UI, ns.UI.COLORS
	hub = CreateFrame("Frame", "ForeverCompanionHub", UIParent, "BackdropTemplate")
	hub:SetFrameStrata("DIALOG")
	hub:SetClampedToScreen(true)
	hub:EnableMouse(true)
	UI.Backdrop(hub, C.bg, C.border)
	local logo = hub:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(UI.MEDIA .. "Logo")
	logo:SetSize(30, 30)
	logo:SetPoint("TOPLEFT", 12, -10)
	local title = UI.Text(hub, 16, C.gold)
	title:SetPoint("LEFT", logo, "RIGHT", 8, 4)
	title:SetText("ForeverCompanion")
	local version = UI.Text(hub, 11, C.muted)
	version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	version:SetText(ns.VERSION or "")
	local line = UI.Separator(hub, C.accent)
	line:SetPoint("TOPLEFT", 1, -50)
	line:SetPoint("TOPRIGHT", -1, -50)
	hub.buttons = {}
	local y = 58
	for _, entry in ipairs(HUB_ENTRIES) do
		local b = CreateFrame("Button", nil, hub)
		b:SetHeight(44)
		b:SetPoint("TOPLEFT", 6, -y)
		b:SetPoint("RIGHT", -6, 0)
		b.bg = UI.Fill(b, { 1, 1, 1, 0 }, "BACKGROUND")
		b.bg:SetAllPoints()
		b.icon = UI.ItemIcon(b, 32)
		b.icon:SetPoint("LEFT", 6, 0)
		b.icon:SetItem(entry.icon)
		b.label = UI.Text(b, 14)
		b.label:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -1)
		b.label:SetText(L[entry.label])
		b.desc = UI.Text(b, 11, C.muted)
		b.desc:SetPoint("BOTTOMLEFT", b.icon, "BOTTOMRIGHT", 10, 1)
		b.desc:SetText(L[entry.desc])
		b:SetScript("OnEnter", function(self) self.bg:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.12) end)
		b:SetScript("OnLeave", function(self) self.bg:SetVertexColor(1, 1, 1, 0) end)
		b:SetScript("OnClick", function()
			hub:Hide()
			if entry.run then entry.run() else ns.FC:SlashCommand(entry.command) end
		end)
		b.entry = entry
		hub.buttons[#hub.buttons + 1] = b
		y = y + 46
	end
	hub:SetSize(290, y + 8)
	hub:SetScript("OnShow", function()
		-- Hide entries of modules that are turned off.
		local yy = 58
		for _, b in ipairs(hub.buttons) do
			local module = b.entry.module and ns.FC:GetModule(b.entry.module, true)
			local shown = not b.entry.module or (module and module:IsEnabled())
			b:SetShown(shown and true or false)
			if shown then
				b:SetPoint("TOPLEFT", 6, -yy)
				yy = yy + 46
			end
		end
		hub:SetHeight(yy + 8)
	end)
	-- Close when clicking elsewhere.
	hub:SetScript("OnUpdate", function()
		if not hub:IsMouseOver() and not (hub.anchor and hub.anchor:IsMouseOver()) then
			hub.away = (hub.away or 0) + 1
			if hub.away > 120 then hub:Hide() end
		else
			hub.away = 0
		end
	end)
	table.insert(UISpecialFrames, "ForeverCompanionHub")
end

function ns.ToggleHub(anchor)
	if not hub then CreateHub() end
	if hub:IsShown() then hub:Hide() return end
	hub.anchor = anchor
	hub:ClearAllPoints()
	if anchor and anchor.GetCenter and anchor:GetCenter() then
		local x, y = anchor:GetCenter()
		local right = x > UIParent:GetWidth() / 2
		local top = y > UIParent:GetHeight() / 2
		hub:SetPoint((top and "TOP" or "BOTTOM") .. (right and "RIGHT" or "LEFT"), anchor, (top and "BOTTOM" or "TOP") .. (right and "LEFT" or "RIGHT"))
	else
		hub:SetPoint("CENTER")
	end
	hub.away = 0
	hub:Show()
end

local function OnClick(frame, button)
	if button == "RightButton" then
		ns.OpenOptions()
	elseif IsShiftKeyDown() and ns.ToggleRouteWindow then
		ns.ToggleRouteWindow()
	elseif IsControlKeyDown() and ns.ToggleDungeonGuide then
		ns.ToggleDungeonGuide()
	else
		ns.ToggleHub(frame)
	end
end

local function OnTooltipShow(tooltip)
	tooltip:AddLine(ns.TAG .. " " .. (ns.VERSION or ""))
	tooltip:AddLine(" ")
	tooltip:AddLine(L["Left-click: menu"], 1, 1, 1)
	tooltip:AddLine(L["Ctrl-click: dungeon & raid guide"], 1, 1, 1)
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
	icon:SetSize(20, 20)
	icon:SetTexture(ICON)
	icon:SetPoint("TOPLEFT", 6, -5)

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

ns.RegisterCommand("menu", L["open the ForeverCompanion menu"], function() ns.ToggleHub() end)
