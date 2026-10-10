-- ForeverCompanion: bag helpers built on top of Blizzard's bags.
local _, ns = ...
local L = ns.L

local Bags = ns.NewModule("Bags", {
	sellJunk = true,
	repair = true,
	guildRepair = false,
	itemLevel = true,
	highlightUse = true,
	junkIcon = true,
	combinedBags = true,
})

local USE_PREFIX = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
local EQUIP_PREFIX = ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:"
local effectCache = {} -- [itemLink] = "use" | "equip" | false

-- Does the item have an on-use or on-equip effect? Forever adds hundreds of them.
local function ItemEffect(bag, slot, link)
	if effectCache[link] ~= nil then return effectCache[link] end
	local data = C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
	if not data then return nil end
	local result = false
	for _, line in ipairs(data.lines or {}) do
		local text = line.leftText
		if text and not ns.IsSecret(text) then
			if text:find(USE_PREFIX, 1, true) == 1 then result = "use" break end
			if text:find(EQUIP_PREFIX, 1, true) == 1 then result = "equip" end
		end
	end
	effectCache[link] = result
	return result
end

local function Decorate(button, settings)
	if not button.fcLevel then
		button.fcLevel = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		button.fcLevel:SetPoint("TOPLEFT", 2, -2)
		button.fcEffect = button:CreateTexture(nil, "OVERLAY")
		button.fcEffect:SetSize(12, 12)
		button.fcEffect:SetPoint("BOTTOMLEFT", 2, 2)
		button.fcJunk = button:CreateTexture(nil, "OVERLAY")
		button.fcJunk:SetSize(13, 13)
		button.fcJunk:SetPoint("TOPRIGHT", -2, -2)
		button.fcJunk:SetTexture("Interface\\Buttons\\UI-GroupLoot-Coin-Up")
	end
	button.fcLevel:Hide()
	button.fcEffect:Hide()
	button.fcJunk:Hide()

	local bag = button.GetBagID and button:GetBagID()
	if bag == nil and button:GetParent() then bag = button:GetParent():GetID() end
	local slot = button:GetID()
	local info = bag and C_Container.GetContainerItemInfo(bag, slot)
	if not info or not info.hyperlink then return end

	if settings.itemLevel and C_Item.IsEquippableItem(info.hyperlink) then
		local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
		local level = location:IsValid() and C_Item.GetCurrentItemLevel(location)
		if level and level > 1 then
			button.fcLevel:SetText(level)
			local color = ITEM_QUALITY_COLORS[info.quality or 1]
			if color then button.fcLevel:SetTextColor(color.r, color.g, color.b) end
			button.fcLevel:Show()
		end
	end
	if settings.highlightUse then
		local effect = ItemEffect(bag, slot, info.hyperlink)
		if effect == "use" then
			button.fcEffect:SetTexture("Interface\\Icons\\Spell_Holy_PowerInfusion")
			button.fcEffect:Show()
		elseif effect == "equip" then
			button.fcEffect:SetTexture("Interface\\Icons\\Spell_Holy_GreaterBlessingofKings")
			button.fcEffect:Show()
		end
	end
	if settings.junkIcon and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
		button.fcJunk:Show()
	end
end

-- Item buttons of a bag window, for both the modern (EnumerateValidItems) and the older
-- (ContainerFrame1Item1...) bag frames.
local function FrameButtons(frame)
	local list = {}
	if frame.EnumerateValidItems then
		local iter, state, start = frame:EnumerateValidItems()
		if iter then
			for _, button in iter, state, start do list[#list + 1] = button end
		end
		return list
	end
	local name = frame:GetName()
	for i = 1, 40 do
		local button = name and _G[name .. "Item" .. i]
		if not button then break end
		list[#list + 1] = button
	end
	return list
end

local function BagFrames()
	local frames = { ContainerFrameCombinedBags }
	for i = 1, NUM_CONTAINER_FRAMES or 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
	return frames
end

function Bags:RefreshVisible()
	if not self:IsEnabled() then return end
	local settings = self:Settings()
	for _, frame in pairs(BagFrames()) do
		if frame and frame:IsShown() then
			for _, button in ipairs(FrameButtons(frame)) do
				if button:IsShown() then Decorate(button, settings) end
			end
		end
	end
end

function Bags:ScheduleRefresh()
	if self.refreshPending then return end
	self.refreshPending = true
	C_Timer.After(0.05, function()
		self.refreshPending = false
		self:RefreshVisible()
	end)
end

function Bags:HookFrame(frame)
	if not frame or frame.fcHooked then return end
	frame.fcHooked = true
	if frame.UpdateItems then
		hooksecurefunc(frame, "UpdateItems", function() self:ScheduleRefresh() end)
	end
	frame:HookScript("OnShow", function() self:ScheduleRefresh() end)
end

function Bags:HookAll()
	for _, frame in pairs(BagFrames()) do self:HookFrame(frame) end
	if ContainerFrame_Update and not self.globalHooked then
		self.globalHooked = true
		hooksecurefunc("ContainerFrame_Update", function() self:ScheduleRefresh() end)
	end
end

---------------------------------------------------------------------------
-- Merchant
---------------------------------------------------------------------------
function Bags:SellJunk()
	local value, count, queue = 0, 0, {}
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue and not info.isLocked then
				local price = select(11, C_Item.GetItemInfo(info.itemID)) or 0
				value = value + price * (info.stackCount or 1)
				count = count + 1
				queue[#queue + 1] = { bag, slot }
			end
		end
	end
	if count == 0 then return end
	local native = C_MerchantFrame and C_MerchantFrame.SellAllJunkItems
	if native and (not C_MerchantFrame.IsSellAllJunkEnabled or C_MerchantFrame.IsSellAllJunkEnabled()) then
		C_MerchantFrame.SellAllJunkItems()
	else
		-- Older clients: sell one item at a time so the server keeps up.
		local i = 0
		local function SellNext()
			i = i + 1
			local entry = queue[i]
			if not entry or not MerchantFrame:IsShown() then return end
			C_Container.UseContainerItem(entry[1], entry[2])
			C_Timer.After(0.2, SellNext)
		end
		SellNext()
	end
	ns.Print(string.format(L["Sold %d junk items for %s."], count, ns.FormatMoney(value)))
end

function Bags:Repair()
	if not CanMerchantRepair() then return end
	local cost, canRepair = GetRepairAllCost()
	if not canRepair or cost == 0 then return end
	if self:Settings().guildRepair and IsInGuild() and CanGuildBankRepair and CanGuildBankRepair() then
		RepairAllItems(true)
		ns.Print(string.format(L["Repaired with guild funds for %s."], ns.FormatMoney(cost)))
	elseif GetMoney() >= cost then
		RepairAllItems()
		ns.Print(string.format(L["Repaired for %s."], ns.FormatMoney(cost)))
	else
		ns.Print(L["Not enough gold to repair."])
	end
end

function Bags:MERCHANT_SHOW()
	if IsShiftKeyDown() then return end
	local s = self:Settings()
	if s.repair then self:Repair() end
	if s.sellJunk then self:SellJunk() end
end

function Bags:ApplyCombined()
	if self:Settings().combinedBags and C_CVar.GetCVar("combinedBags") ~= nil then
		C_CVar.SetCVar("combinedBags", "1")
	end
end

function Bags:OnEnable()
	self:HookAll()
	self:ApplyCombined()
	self:RegisterEvent("MERCHANT_SHOW")
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function() wipe(effectCache) self:ScheduleRefresh() end)
	self:RegisterEvent("BAG_UPDATE_DELAYED", "ScheduleRefresh")
	self:RegisterEvent("ITEM_LOCK_CHANGED", "ScheduleRefresh")
	-- Bag windows can be created after login.
	self:RegisterEvent("ADDON_LOADED", function() self:HookAll() end)
	self:ScheduleRefresh()
end

function Bags:OnDisable()
	for _, frame in pairs(BagFrames()) do
		if frame then
			for _, button in ipairs(FrameButtons(frame)) do
				if button.fcLevel then button.fcLevel:Hide() button.fcEffect:Hide() button.fcJunk:Hide() end
			end
		end
	end
end

function Bags:OnProfileChanged()
	self:ApplyCombined()
	self:ScheduleRefresh()
end

function Bags:GetOptions()
	local get, set = ns.ProfileAccessors("Bags", function(key)
		if key == "combinedBags" then self:ApplyCombined() end
		self:ScheduleRefresh()
	end)
	return {
		get = get, set = set,
		args = {
			merchant = { type = "header", order = 1, name = L["At a merchant (hold Shift to skip)"] },
			sellJunk = { type = "toggle", order = 2, name = L["Sell junk (grey items)"] },
			repair = { type = "toggle", order = 3, name = L["Repair automatically"] },
			guildRepair = { type = "toggle", order = 4, name = L["Use guild funds first"] },
			display = { type = "header", order = 10, name = L["In your bags"] },
			itemLevel = { type = "toggle", order = 11, name = L["Show item level"] },
			highlightUse = { type = "toggle", order = 12, width = "full", name = L["Mark items with an on-use or on-equip effect"] },
			junkIcon = { type = "toggle", order = 13, name = L["Mark junk with a coin"] },
			combinedBags = { type = "toggle", order = 14, name = L["Single bag window"] },
		},
	}
end
