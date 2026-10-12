-- ForeverCompanion: interface kit. Every window of the addon is built with these pieces so they
-- share one look: dark panels, thin borders, a cyan accent, gold titles and readable fonts.
local _, ns = ...

local UI = {}
ns.UI = UI

UI.MEDIA = "Interface\\AddOns\\ForeverCompanion\\Media\\"
UI.WHITE = "Interface\\Buttons\\WHITE8x8"

UI.COLORS = {
	bg      = { 0.047, 0.055, 0.078, 0.96 },
	panel   = { 0.082, 0.094, 0.129, 1 },
	panel2  = { 0.114, 0.129, 0.176, 1 },
	hover   = { 0.157, 0.180, 0.243, 1 },
	header  = { 0.067, 0.078, 0.110, 1 },
	border  = { 0.204, 0.231, 0.306, 1 },
	accent  = { 0.20, 0.80, 1.00, 1 },
	gold    = { 1.00, 0.82, 0.30, 1 },
	text    = { 0.93, 0.94, 0.97, 1 },
	muted   = { 0.58, 0.62, 0.70, 1 },
	good    = { 0.35, 0.90, 0.45, 1 },
	warn    = { 1.00, 0.76, 0.22, 1 },
	bad     = { 1.00, 0.36, 0.32, 1 },
	xp      = { 0.62, 0.30, 0.95, 1 },
	rested  = { 0.20, 0.55, 1.00, 0.55 },
}
local C = UI.COLORS

---------------------------------------------------------------------------
-- Themes: each one replaces the colours above (in place, so every module sees them).  Applied once
-- at login, before any window is built; changing the theme asks for a /reload.
---------------------------------------------------------------------------
UI.THEMES = {
	forever = { label = "Forever (cyan)" },
	arcane = {
		label = "Arcane (violet)",
		bg = { 0.055, 0.043, 0.082, 0.96 }, panel = { 0.094, 0.075, 0.137, 1 }, panel2 = { 0.133, 0.106, 0.192, 1 },
		hover = { 0.188, 0.149, 0.267, 1 }, header = { 0.075, 0.059, 0.114, 1 }, header2 = { 0.16, 0.11, 0.26, 1 },
		border = { 0.255, 0.204, 0.353, 1 }, accent = { 0.72, 0.45, 1.00, 1 },
	},
	horde = {
		label = "Horde (red)",
		bg = { 0.071, 0.043, 0.039, 0.96 }, panel = { 0.122, 0.071, 0.063, 1 }, panel2 = { 0.169, 0.098, 0.086, 1 },
		hover = { 0.235, 0.133, 0.114, 1 }, header = { 0.094, 0.055, 0.047, 1 }, header2 = { 0.24, 0.09, 0.07, 1 },
		border = { 0.333, 0.192, 0.165, 1 }, accent = { 0.95, 0.30, 0.22, 1 },
	},
	alliance = {
		label = "Alliance (blue & gold)",
		bg = { 0.035, 0.051, 0.090, 0.96 }, panel = { 0.063, 0.090, 0.153, 1 }, panel2 = { 0.090, 0.125, 0.208, 1 },
		hover = { 0.125, 0.173, 0.282, 1 }, header = { 0.047, 0.067, 0.118, 1 }, header2 = { 0.09, 0.15, 0.30, 1 },
		border = { 0.180, 0.239, 0.373, 1 }, accent = { 0.35, 0.60, 1.00, 1 }, gold = { 1.00, 0.84, 0.36, 1 },
	},
	emerald = {
		label = "Emerald (green)",
		bg = { 0.035, 0.067, 0.055, 0.96 }, panel = { 0.059, 0.110, 0.090, 1 }, panel2 = { 0.086, 0.153, 0.125, 1 },
		hover = { 0.118, 0.212, 0.173, 1 }, header = { 0.047, 0.086, 0.071, 1 }, header2 = { 0.07, 0.20, 0.14, 1 },
		border = { 0.165, 0.290, 0.239, 1 }, accent = { 0.30, 0.92, 0.60, 1 },
	},
	classic = {
		label = "Classic (parchment & gold)",
		bg = { 0.078, 0.063, 0.043, 0.96 }, panel = { 0.129, 0.106, 0.075, 1 }, panel2 = { 0.176, 0.145, 0.102, 1 },
		hover = { 0.243, 0.200, 0.141, 1 }, header = { 0.106, 0.086, 0.059, 1 }, header2 = { 0.25, 0.19, 0.11, 1 },
		border = { 0.380, 0.306, 0.196, 1 }, accent = { 1.00, 0.78, 0.30, 1 }, gold = { 1.00, 0.88, 0.55, 1 },
		text = { 0.96, 0.92, 0.84, 1 }, muted = { 0.68, 0.62, 0.52, 1 },
	},
	midnight = {
		label = "Midnight (black)",
		bg = { 0.020, 0.020, 0.024, 0.97 }, panel = { 0.055, 0.055, 0.063, 1 }, panel2 = { 0.086, 0.086, 0.098, 1 },
		hover = { 0.133, 0.133, 0.153, 1 }, header = { 0.035, 0.035, 0.043, 1 }, header2 = { 0.10, 0.10, 0.12, 1 },
		border = { 0.165, 0.165, 0.188, 1 }, accent = { 0.85, 0.85, 0.92, 1 },
	},
	class = { label = "My class colour" },
}
UI.THEME_ORDER = { "forever", "arcane", "horde", "alliance", "emerald", "classic", "midnight", "class" }
C.header2 = { 0.10, 0.13, 0.19, 1 }
local DEFAULT = {}
for k, v in pairs(C) do DEFAULT[k] = { v[1], v[2], v[3], v[4] } end

function UI.ApplyTheme(name)
	local theme = UI.THEMES[name] or UI.THEMES.forever
	for k, v in pairs(DEFAULT) do
		local src = theme[k] or v
		local dst = C[k]
		dst[1], dst[2], dst[3], dst[4] = src[1], src[2], src[3], src[4]
	end
	if name == "class" then
		local _, class = UnitClass("player")
		local cc = class and (C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
		if cc then C.accent[1], C.accent[2], C.accent[3] = cc.r, cc.g, cc.b end
	end
	UI.theme = name
end

-- Appearance settings (scale and opacity of the windows), filled in by Core.lua.
function UI.Appearance()
	local db = ns.FC and ns.FC.db and ns.FC.db.profile.appearance
	return db or { scale = 1, opacity = 0.96 }
end

function UI.Hex(color)
	return string.format("ff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
end

function UI.Colorize(text, color)
	return "|c" .. UI.Hex(color) .. text .. "|r"
end

---------------------------------------------------------------------------
-- Fonts: one font object per size and style, built on the game font so every locale works.
---------------------------------------------------------------------------
local fonts = {}
function UI.Font(size, style)
	style = style or ""
	local key = size .. style
	if fonts[key] then return fonts[key] end
	local font = CreateFont("ForeverCompanionFont" .. size .. style:gsub(",", ""))
	local file = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
	font:SetFont(file, size, style:find("OUTLINE") and "OUTLINE" or "")
	font:SetShadowOffset(1, -1)
	font:SetShadowColor(0, 0, 0, 0.9)
	fonts[key] = font
	return font
end

-- FontString with size, color and alignment.
function UI.Text(parent, size, color, justify, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFontObject(UI.Font(size or 13))
	local c = color or C.text
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(true)
	return fs
end

---------------------------------------------------------------------------
-- Backgrounds and borders
---------------------------------------------------------------------------
function UI.Backdrop(frame, bg, border)
	if not frame.SetBackdrop and BackdropTemplateMixin then Mixin(frame, BackdropTemplateMixin) end
	if not frame.SetBackdrop then return end
	frame:SetBackdrop({ bgFile = UI.WHITE, edgeFile = UI.WHITE, edgeSize = 1 })
	bg = bg or C.panel
	border = border or C.border
	frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
	frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

function UI.Fill(parent, color, layer)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(UI.WHITE)
	t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	return t
end

-- Vertical gradient (top -> bottom). Falls back to a flat color on clients without SetGradient colors.
function UI.Gradient(texture, top, bottom)
	texture:SetTexture(UI.WHITE)
	local ok = CreateColor and pcall(texture.SetGradient, texture, "VERTICAL",
		CreateColor(bottom[1], bottom[2], bottom[3], bottom[4] or 1), CreateColor(top[1], top[2], top[3], top[4] or 1))
	if not ok then texture:SetVertexColor(top[1], top[2], top[3], top[4] or 1) end
end

function UI.Separator(parent, color)
	local line = UI.Fill(parent, color or C.border, "ARTWORK")
	line:SetHeight(1)
	return line
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local BUTTON_STYLES = {
	normal = { bg = C.panel2, hover = C.hover, border = C.border, text = C.text },
	accent = { bg = { 0.06, 0.36, 0.48, 1 }, hover = { 0.09, 0.47, 0.62, 1 }, border = { 0.20, 0.80, 1.00, 0.9 }, text = { 1, 1, 1, 1 } },
	ghost  = { bg = { 0, 0, 0, 0 }, hover = C.hover, border = { 0, 0, 0, 0 }, text = C.muted },
	danger = { bg = { 0.35, 0.09, 0.09, 1 }, hover = { 0.48, 0.12, 0.12, 1 }, border = { 1, 0.36, 0.32, 0.8 }, text = { 1, 1, 1, 1 } },
}

function UI.Button(parent, text, width, height, style, onClick)
	local s = BUTTON_STYLES[style or "normal"]
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(width or 120, height or 26)
	UI.Backdrop(b, s.bg, s.border)
	b.label = UI.Text(b, 13, s.text, "CENTER")
	b.label:SetPoint("LEFT", 8, 0)
	b.label:SetPoint("RIGHT", -8, 0)
	b.label:SetWordWrap(false)
	b.label:SetText(text or "")
	b.style = s
	b:SetScript("OnEnter", function(self)
		self:SetBackdropColor(s.hover[1], s.hover[2], s.hover[3], s.hover[4] or 1)
		if self.tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropColor(s.bg[1], s.bg[2], s.bg[3], s.bg[4] or 1)
		GameTooltip_Hide()
	end)
	b:SetScript("OnMouseDown", function(self) self.label:SetPoint("LEFT", 9, -1) end)
	b:SetScript("OnMouseUp", function(self) self.label:SetPoint("LEFT", 8, 0) end)
	if onClick then b:SetScript("OnClick", onClick) end
	function b:SetText(t) self.label:SetText(t) end
	function b:GetText() return self.label:GetText() end
	function b:FitText(min)
		self:SetWidth(math.max(min or 60, self.label:GetStringWidth() + 26))
	end
	return b
end

-- Small square button with an icon texture or a single glyph.
function UI.IconButton(parent, size, texture, tooltip, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	if texture then b.icon:SetTexture(texture) end
	b.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
	b:SetScript("OnEnter", function(self)
		self.icon:SetVertexColor(1, 1, 1)
		if tooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine(tooltip, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
		GameTooltip_Hide()
	end)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- Close button drawn as an "x".
function UI.CloseButton(parent, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(26, 26)
	b.label = UI.Text(b, 18, C.muted, "CENTER")
	b.label:SetPoint("CENTER", 0, 1)
	b.label:SetText("×")
	b:SetScript("OnEnter", function(self) self.label:SetTextColor(C.bad[1], C.bad[2], C.bad[3]) end)
	b:SetScript("OnLeave", function(self) self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
	b:SetScript("OnClick", onClick)
	return b
end

---------------------------------------------------------------------------
-- Inputs
---------------------------------------------------------------------------
function UI.EditBox(parent, width, height, placeholder)
	local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
	e:SetSize(width or 200, height or 26)
	UI.Backdrop(e, { 0.03, 0.035, 0.05, 1 }, C.border)
	e:SetFontObject(UI.Font(13))
	e:SetTextColor(C.text[1], C.text[2], C.text[3])
	e:SetTextInsets(26, 8, 0, 0)
	e:SetAutoFocus(false)
	local icon = e:CreateTexture(nil, "OVERLAY")
	icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", 7, -1)
	icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
	e.placeholder = UI.Text(e, 13, C.muted)
	e.placeholder:SetPoint("LEFT", 26, 0)
	e.placeholder:SetText(placeholder or "")
	e:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3]) end)
	e:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3]) end)
	e:HookScript("OnTextChanged", function(self) self.placeholder:SetShown(self:GetText() == "") end)
	return e
end

---------------------------------------------------------------------------
-- Status bar
---------------------------------------------------------------------------
function UI.Bar(parent, height, color)
	local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	holder:SetHeight(height or 14)
	UI.Backdrop(holder, { 0.02, 0.025, 0.035, 1 }, C.border)
	local bar = CreateFrame("StatusBar", nil, holder)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	bar:SetStatusBarTexture(UI.MEDIA .. "Bar")
	color = color or C.accent
	bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	holder.bar = bar
	holder.text = UI.Text(bar, math.max(10, math.floor((height or 14) * 0.72)), C.text, "CENTER")
	holder.text:SetPoint("CENTER", 0, 0)
	function holder:SetValue(value, max)
		self.bar:SetMinMaxValues(0, max or 1)
		self.bar:SetValue(value)
	end
	function holder:SetColor(c) self.bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1) end
	return holder
end

---------------------------------------------------------------------------
-- Scroll area with a slim scroll bar. Content goes into scroll.child; call SetContentHeight.
---------------------------------------------------------------------------
function UI.Scroll(parent)
	local holder = CreateFrame("Frame", nil, parent)
	local sf = CreateFrame("ScrollFrame", nil, holder)
	sf:SetPoint("TOPLEFT")
	sf:SetPoint("BOTTOMRIGHT", -10, 0)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(10, 10)
	sf:SetScrollChild(child)
	holder.frame, holder.child = sf, child

	local track = UI.Fill(holder, { 1, 1, 1, 0.04 }, "ARTWORK")
	track:SetPoint("TOPRIGHT", -2, 0)
	track:SetPoint("BOTTOMRIGHT", -2, 0)
	track:SetWidth(4)
	local thumb = CreateFrame("Frame", nil, holder)
	thumb:SetWidth(4)
	thumb.tex = UI.Fill(thumb, { C.accent[1], C.accent[2], C.accent[3], 0.6 }, "OVERLAY")
	thumb.tex:SetAllPoints()
	thumb:EnableMouse(true)
	holder.thumb = thumb

	local function Max()
		return math.max(0, child:GetHeight() - sf:GetHeight())
	end
	function holder:UpdateThumb()
		local view, total = sf:GetHeight(), child:GetHeight()
		if total <= view + 1 or view <= 0 then
			thumb:Hide() track:Hide()
			return
		end
		thumb:Show() track:Show()
		local h = math.max(24, view * view / total)
		local offset = (sf:GetVerticalScroll() / Max()) * (view - h)
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -2, -offset)
	end
	function holder:SetScroll(value)
		sf:SetVerticalScroll(math.max(0, math.min(Max(), value)))
		self:UpdateThumb()
	end
	function holder:GetScroll() return sf:GetVerticalScroll() end
	function holder:SetContentHeight(h)
		child:SetHeight(math.max(1, h))
		self:SetScroll(sf:GetVerticalScroll())
	end
	function holder:ScrollToTop() self:SetScroll(0) end

	sf:EnableMouseWheel(true)
	sf:SetScript("OnMouseWheel", function(_, delta) holder:SetScroll(sf:GetVerticalScroll() - delta * 60) end)
	sf:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w) holder:UpdateThumb() end)
	thumb:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" then return end
		local _, startY = GetCursorPosition()
		local startScroll = sf:GetVerticalScroll()
		local scale = thumb:GetEffectiveScale()
		thumb:SetScript("OnUpdate", function()
			local _, y = GetCursorPosition()
			local view = sf:GetHeight()
			local ratio = Max() / math.max(1, view - thumb:GetHeight())
			holder:SetScroll(startScroll + (startY - y) / scale * ratio)
		end)
	end)
	thumb:SetScript("OnMouseUp", function() thumb:SetScript("OnUpdate", nil) end)
	return holder
end

---------------------------------------------------------------------------
-- Frame pools, so long lists reuse their rows.
---------------------------------------------------------------------------
function UI.Pool(create)
	local pool = { free = {}, used = {} }
	function pool:Acquire(parent)
		local f = table.remove(self.free) or create(parent)
		if parent and f:GetParent() ~= parent then f:SetParent(parent) end
		f:ClearAllPoints()
		f:Show()
		self.used[#self.used + 1] = f
		return f
	end
	function pool:ReleaseAll()
		for _, f in ipairs(self.used) do
			f:Hide()
			self.free[#self.free + 1] = f
		end
		wipe(self.used)
	end
	return pool
end

-- Vertical layout helper for a scroll child: place frames one under the other.
function UI.Stack(child, padding)
	local stack = { y = 0, child = child, pad = padding or 16 }
	function stack:Reset() self.y = 0 end
	function stack:Add(frame, height, gap, indent)
		self.y = self.y + (gap or 0)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", self.child, "TOPLEFT", self.pad + (indent or 0), -self.y)
		frame:SetPoint("RIGHT", self.child, "RIGHT", -self.pad, 0)
		if height then frame:SetHeight(height) end
		self.y = self.y + frame:GetHeight()
		return frame
	end
	function stack:Space(h) self.y = self.y + h end
	return stack
end

---------------------------------------------------------------------------
-- Item icon with a quality-colored border.
---------------------------------------------------------------------------
function UI.ItemIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetSize(size, size)
	UI.Backdrop(f, { 0, 0, 0, 1 }, C.border)
	f.icon = f:CreateTexture(nil, "ARTWORK")
	f.icon:SetPoint("TOPLEFT", 1, -1)
	f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	function f:SetItem(texture, quality)
		self.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
		local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		if color then
			self:SetBackdropBorderColor(color.r, color.g, color.b, 1)
		else
			self:SetBackdropBorderColor(C.border[1], C.border[2], C.border[3], 1)
		end
	end
	return f
end

-- Rounded "chip" label (level ranges, tags).
function UI.Chip(parent, size)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	UI.Backdrop(f, C.panel2, C.border)
	f.text = UI.Text(f, size or 12, C.text, "CENTER")
	f.text:SetPoint("CENTER")
	f.text:SetWordWrap(false)
	function f:Set(text, color)
		self.text:SetText(text)
		local c = color or C.text
		self.text:SetTextColor(c[1], c[2], c[3])
		self:SetBackdropBorderColor(c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, 1)
		self:SetSize(self.text:GetStringWidth() + 16, (size or 12) + 10)
	end
	return f
end

-- Color for content of a given level relative to the player (grey, green, yellow, orange, red).
function UI.LevelColor(minLevel, maxLevel)
	local level = UnitLevel("player") or 1
	maxLevel = maxLevel or minLevel
	if level > maxLevel + 5 then return { 0.6, 0.6, 0.6 } end
	if level > maxLevel then return C.good end
	if level >= minLevel then return C.warn end
	if level >= minLevel - 3 then return { 1, 0.5, 0.2 } end
	return C.bad
end

---------------------------------------------------------------------------
-- Window: header with logo, title and close button, draggable, resizable, closes with Escape.
-- store: a saved table where position and size are kept ({ point = {...}, w = , h = }).
---------------------------------------------------------------------------
function UI.Window(name, title, width, height, store, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetFrameStrata(opts.strata or "HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	local look = UI.Appearance()
	UI.Backdrop(f, { C.bg[1], C.bg[2], C.bg[3], look.opacity or C.bg[4] }, C.border)
	if look.scale and look.scale ~= 1 then f:SetScale(look.scale) end
	f:SetSize(store and store.w or width, store and store.h or height)
	f:SetPoint("CENTER")
	if store and store.point then
		f:ClearAllPoints()
		f:SetPoint(store.point[1], UIParent, store.point[3], store.point[4], store.point[5])
	end

	-- Soft shadow around the window.
	local shadow = CreateFrame("Frame", nil, f, "BackdropTemplate")
	shadow:SetPoint("TOPLEFT", -6, 6)
	shadow:SetPoint("BOTTOMRIGHT", 6, -6)
	shadow:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
	if shadow.SetBackdrop then
		shadow:SetBackdrop({ edgeFile = "Interface\\GLUES\\COMMON\\TextPanel-Border", edgeSize = 8 })
		shadow:SetBackdropBorderColor(0, 0, 0, 0.6)
	end

	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(opts.headerHeight or 40)
	local hbg = header:CreateTexture(nil, "BACKGROUND")
	hbg:SetAllPoints()
	UI.Gradient(hbg, C.header2, C.header)
	local accent = UI.Fill(header, C.accent, "ARTWORK")
	accent:SetPoint("BOTTOMLEFT")
	accent:SetPoint("BOTTOMRIGHT")
	accent:SetHeight(2)
	accent:SetAlpha(0.9)
	-- soft glow of the accent colour under the header line
	local glow = f:CreateTexture(nil, "BORDER")
	glow:SetTexture(UI.WHITE)
	glow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	glow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
	glow:SetHeight(26)
	UI.Gradient(glow, { C.accent[1], C.accent[2], C.accent[3], 0.12 }, { C.accent[1], C.accent[2], C.accent[3], 0 })
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() f:StartMoving() end)
	header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		if store then
			local point, _, relPoint, x, y = f:GetPoint()
			store.point = { point, "UIParent", relPoint, x, y }
		end
	end)

	local logo = header:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(UI.MEDIA .. "Logo")
	logo:SetSize(26, 26)
	logo:SetPoint("LEFT", 10, 0)
	f.title = UI.Text(header, 16, C.gold)
	f.title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
	f.title:SetWordWrap(false)
	f.title:SetText(title or "")
	f.subtitle = UI.Text(header, 12, C.muted)
	f.subtitle:SetPoint("LEFT", f.title, "RIGHT", 10, -1)
	f.subtitle:SetWordWrap(false)
	f.close = UI.CloseButton(header, function() f:Hide() end)
	f.close:SetPoint("RIGHT", -8, 0)
	f.header = header

	f.content = CreateFrame("Frame", nil, f)
	f.content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
	f.content:SetPoint("BOTTOMRIGHT", -1, 1)

	if opts.resizable then
		f:SetResizable(true)
		if f.SetResizeBounds then
			f:SetResizeBounds(opts.minWidth or 400, opts.minHeight or 300)
		elseif f.SetMinResize then
			f:SetMinResize(opts.minWidth or 400, opts.minHeight or 300)
		end
		local grip = CreateFrame("Button", nil, f)
		grip:SetSize(16, 16)
		grip:SetPoint("BOTTOMRIGHT", -2, 2)
		grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
		grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
		grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
		grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
		grip:SetScript("OnMouseUp", function()
			f:StopMovingOrSizing()
			if store then store.w, store.h = f:GetWidth(), f:GetHeight() end
			if f.OnResized then f:OnResized() end
		end)
	end

	if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
	f:Hide()
	return f
end

-- Small floating panel (trackers: XP, quests, camps). Draggable unless locked.
function UI.Panel(name, width, height, getSettings)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(width, height)
	UI.Backdrop(f, { C.bg[1], C.bg[2], C.bg[3], 0.88 }, C.border)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(frame)
		if not (getSettings and getSettings().locked) then frame:StartMoving() end
	end)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		if getSettings then
			local point, _, relPoint, x, y = frame:GetPoint()
			getSettings().point = { point, "UIParent", relPoint, x, y }
		end
	end)
	local stripe = UI.Fill(f, C.accent, "ARTWORK")
	stripe:SetPoint("TOPLEFT", 1, -1)
	stripe:SetPoint("BOTTOMLEFT", 1, 1)
	stripe:SetWidth(3)
	f.stripe = stripe
	return f
end

-- Section title inside a panel: small caps-like accent label with a line.
function UI.SectionTitle(parent, text)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(26)
	f.text = UI.Text(f, 13, C.accent)
	f.text:SetPoint("BOTTOMLEFT", 0, 6)
	f.text:SetText(text or "")
	f.line = UI.Separator(f)
	f.line:SetPoint("BOTTOMLEFT", 0, 0)
	f.line:SetPoint("BOTTOMRIGHT", 0, 0)
	function f:SetText(t) self.text:SetText(t or "") end
	return f
end
