-- ForeverCompanion: professions page of the leveling guide (/fc lvl prof).
-- Which professions go together and which suit your class, where to gather, and the cheapest way from 1 to 300
-- for each crafting profession (Data\Professions.lua: recipe by recipe, with the materials to bring).
local _, ns = ...
local L = ns.L
local UI = ns.UI
local C = UI.COLORS

local P = {}
ns.ProfessionGuide = P

-- key, skill line, English name, icon
local PROFS = {
	{ "alchemy", 171, "Alchemy", 136240 },
	{ "blacksmithing", 164, "Blacksmithing", 136241 },
	{ "enchanting", 333, "Enchanting", 136244 },
	{ "engineering", 202, "Engineering", 136243 },
	{ "leatherworking", 165, "Leatherworking", 133611 },
	{ "tailoring", 197, "Tailoring", 136249 },
	{ "mining", 186, "Mining", 136248 },
	{ "herbalism", 182, "Herbalism", 136246 },
	{ "skinning", 393, "Skinning", 134366 },
	{ "cooking", 185, "Cooking", 133971 },
	{ "firstaid", 129, "First Aid", 135966 },
}
P.PROFS = PROFS
local BY_KEY = {}
for _, p in ipairs(PROFS) do BY_KEY[p[1]] = p end

-- Professions that work together: the gathering one feeds the crafting one.
local PAIRS = {
	{ "skinning", "leatherworking", "Skin what you kill: all the leather you need, plus armor kits and leather or mail gear for you." },
	{ "mining", "blacksmithing", "Ore becomes bars and sharpening stones: plate and mail armor, weapons and weightstones." },
	{ "mining", "engineering", "Bars and stones become bombs, scopes, goggles and gadgets: the strongest pair for PvP." },
	{ "herbalism", "alchemy", "Herbs become potions, elixirs and flasks for leveling, dungeons and raids; transmutes sell well." },
	{ "tailoring", "enchanting", "Cloth drops from humanoids, no gathering needed: disenchant what you sew to enchant your gear." },
	{ "herbalism", "mining", "Two gathering professions: the most gold while leveling, sold at the auction house." },
	{ "skinning", "mining", "Two gathering professions: easy gold while leveling, Skinning on everything you kill." },
}

-- Best pairs for each class (first = main choice), and the leveling tip.
local CLASS = {
	WARRIOR = { { "mining", "blacksmithing" }, { "mining", "engineering" } },
	PALADIN = { { "mining", "blacksmithing" }, { "herbalism", "alchemy" } },
	HUNTER = { { "skinning", "leatherworking" }, { "mining", "engineering" } },
	ROGUE = { { "skinning", "leatherworking" }, { "mining", "engineering" } },
	PRIEST = { { "tailoring", "enchanting" }, { "herbalism", "alchemy" } },
	SHAMAN = { { "skinning", "leatherworking" }, { "herbalism", "alchemy" } },
	MAGE = { { "tailoring", "enchanting" }, { "herbalism", "alchemy" } },
	WARLOCK = { { "tailoring", "enchanting" }, { "herbalism", "alchemy" } },
	DRUID = { { "skinning", "leatherworking" }, { "herbalism", "alchemy" } },
}

-- Gathering: skill needed, what you gather, where.
local GATHER = {
	mining = {
		{ 1, "Copper Vein", "Elwynn Forest, Dun Morogh, Darkshore, Durotar, Mulgore, Tirisfal Glades" },
		{ 65, "Tin Vein (and Silver from 75)", "Westfall, Redridge Mountains, Loch Modan, The Barrens, Silverpine Forest, Stonetalon Mountains" },
		{ 125, "Iron Deposit (and Gold from 155)", "Arathi Highlands, Hillsbrad Foothills, Desolace, Thousand Needles, Stranglethorn Vale" },
		{ 175, "Mithril Deposit (and Truesilver from 230)", "Badlands, Searing Gorge, The Hinterlands, Tanaris, Feralas, Azshara" },
		{ 245, "Small Thorium Vein (Rich from 275)", "Un'Goro Crater, Burning Steppes, Winterspring, Silithus, Eastern Plaguelands" },
	},
	herbalism = {
		{ 1, "Peacebloom, Silverleaf, Earthroot", "every starting zone" },
		{ 50, "Mageroyal, Briarthorn, Bruiseweed (100)", "The Barrens, Westfall, Darkshore, Loch Modan, Silverpine Forest, Redridge Mountains" },
		{ 115, "Wild Steelbloom, Kingsblood, Liferoot (150)", "Hillsbrad Foothills, Arathi Highlands, Ashenvale, Stonetalon Mountains, Wetlands" },
		{ 160, "Fadeleaf, Goldthorn, Khadgar's Whisker", "Stranglethorn Vale, Swamp of Sorrows, Dustwallow Marsh, Arathi Highlands" },
		{ 205, "Firebloom, Purple Lotus, Sungrass (230)", "Tanaris, Feralas, The Hinterlands, Searing Gorge, Azshara" },
		{ 250, "Gromsblood, Golden Sansam, Dreamfoil, Plaguebloom, Icecap", "Felwood, Un'Goro Crater, Western and Eastern Plaguelands, Winterspring" },
	},
	skinning = {
		{ 1, "Light Leather (beasts up to level 20)", "your starting zone and the next one" },
		{ 100, "Medium Leather (beasts 20-30)", "The Barrens, Stonetalon Mountains, Duskwood, Wetlands, Hillsbrad Foothills" },
		{ 150, "Heavy Leather (beasts 30-40)", "Arathi Highlands, Stranglethorn Vale, Desolace, Dustwallow Marsh" },
		{ 200, "Thick Leather (beasts 40-50)", "Tanaris, Feralas, The Hinterlands, Un'Goro Crater" },
		{ 250, "Rugged Leather (beasts 50-60)", "Un'Goro Crater, Winterspring, Burning Steppes, Eastern Plaguelands" },
	},
}
local GATHER_TIP = {
	mining = "Smelt your ore at a forge: smelting gives skill too. Buy a Mining Pick from a trade goods vendor.",
	herbalism = "Track herbs with Find Herbs and pick every herb you pass while questing.",
	skinning = "Skinning goes up to 5 times the level of the beast (from skill 100): skin every beast you kill. Buy a Skinning Knife.",
}

-- Trainer ranks: skill reached, title, character level needed.
local RANKS = { { 75, "Journeyman", 10, 50 }, { 150, "Expert", 20, 125 }, { 225, "Artisan", 35, 200 } }

local function ProfName(key)
	local p = BY_KEY[key]
	return p and L[p[3]] or key
end
P.ProfName = ProfName

-- The character's professions: [key] = { rank, max }.
function P.Known()
	local out = {}
	if GetProfessions and GetProfessionInfo then
		for _, index in ipairs({ GetProfessions() }) do
			if index then
				local _, _, rank, max, _, _, line = GetProfessionInfo(index)
				for _, p in ipairs(PROFS) do
					if p[2] == line then out[p[1]] = { rank or 0, max or 0 } end
				end
			end
		end
	end
	if next(out) == nil and GetNumSkillLines and GetSkillLineInfo then
		for i = 1, GetNumSkillLines() do
			local name, header, _, rank, _, _, max = GetSkillLineInfo(i)
			if name and not header then
				for _, p in ipairs(PROFS) do
					if name == L[p[3]] or name == p[3] then out[p[1]] = { rank or 0, max or 0 } end
				end
			end
		end
	end
	return out
end

local function ItemName(id, guide)
	local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id) or GetItemInfo and GetItemInfo(id)
	if not name then
		if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
		guide.pending = true
		return "#" .. id
	end
	return name
end

local function ItemIcon(id)
	if C_Item and C_Item.GetItemInfoInstant then return select(5, C_Item.GetItemInfoInstant(id)) end
	return GetItemIcon and GetItemIcon(id)
end

local function SpellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end

local function Place(v)
	local zone = v[2] and v[2] > 0 and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(v[2]) or ""
	return string.format("%s (%s %.0f, %.0f)", v[5] or "?", zone, v[3] or 0, v[4] or 0)
end

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
function P.Page(guide)
	local known = P.Known()
	local class = select(2, UnitClass("player"))
	local side = UnitFactionGroup("player") == "Horde" and "Horde" or "Alliance"

	-- default selection: a profession you have with a plan, else the first one of your class pair
	if not guide.prof then
		for _, p in ipairs(PROFS) do
			if known[p[1]] and (ns.ProfessionPlans[p[1]] or GATHER[p[1]]) then guide.prof = p[1] break end
		end
		guide.prof = guide.prof or (CLASS[class] and CLASS[class][1][2]) or "alchemy"
	end

	guide:Section(L["Best professions for your class"])
	for i, pair in ipairs(CLASS[class] or {}) do
		local text = UI.Colorize(ProfName(pair[1]) .. " + " .. ProfName(pair[2]), i == 1 and C.gold or C.accent)
		for _, d in ipairs(PAIRS) do
			if d[1] == pair[1] and d[2] == pair[2] then text = text .. "   " .. UI.Colorize(L[d[3]], C.muted) end
		end
		guide:Text((i == 1 and L["Main choice:"] or L["Also good:"]) .. " " .. text, 13, C.text, 4)
	end
	guide:Text(L["While leveling, take the gathering profession of your pair and level the crafting one at the same time with what you gather; two gathering professions make the most gold."], 12, C.muted, 6)

	if next(known) then
		local parts = {}
		for _, p in ipairs(PROFS) do
			local k = known[p[1]]
			if k then parts[#parts + 1] = string.format("%s %d/%d", L[p[3]], k[1], k[2]) end
		end
		guide:Text(L["Your professions:"] .. " " .. UI.Colorize(table.concat(parts, "   ·   "), C.gold), 13, C.text, 8)
	end

	guide:Section(L["Professions that go together"])
	for _, d in ipairs(PAIRS) do
		guide:Text(UI.Colorize(ProfName(d[1]) .. " + " .. ProfName(d[2]), C.accent) .. "   " .. L[d[3]], 13, C.text, 4)
	end
	guide:Text(L["Cooking, First Aid and Fishing do not count as main professions: every character can learn them, and First Aid saves a lot of downtime."], 12, C.muted, 6)

	-- profession buttons
	guide:Section(L["Leveling a profession from 1 to 300"])
	local frame = guide.frame
	frame.profButtons = frame.profButtons or {}
	local x, y0 = 0, guide.stack.y
	local width = (frame.scroll.child:GetWidth() or 800) - 36
	local row = 0
	for i, p in ipairs(PROFS) do
		local b = frame.profButtons[i]
		if not b then
			b = UI.Button(frame.scroll.child, L[p[3]], 120, 26, "ghost", function() guide.prof = p[1] guide:Render() end)
			if b.FitText then b:FitText(100) end
			frame.profButtons[i] = b
		end
		if x + 124 > width then x = 0 row = row + 1 end
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", frame.scroll.child, "TOPLEFT", 18 + x, -(y0 + row * 30))
		b:Show()
		local active = p[1] == guide.prof
		b:SetBackdropBorderColor(active and C.accent[1] or C.border[1], active and C.accent[2] or C.border[2], active and C.accent[3] or C.border[3], 1)
		x = x + 124
	end
	guide.stack:Space((row + 1) * 30 + 8)

	local key = guide.prof
	local mine = known[key]
	local skill = mine and mine[1] or 0
	if GATHER[key] then
		P.GatherPage(guide, key, skill)
	else
		P.CraftPage(guide, key, skill, side)
	end
end

function P.HideButtons(guide)
	for _, b in ipairs(guide.frame and guide.frame.profButtons or {}) do b:Hide() end
end

function P.GatherPage(guide, key, skill)
	guide:Text(L[GATHER_TIP[key]], 13, C.muted, 8)
	for _, t in ipairs(GATHER[key]) do
		local nextT
		for _, u in ipairs(GATHER[key]) do if u[1] > t[1] and (not nextT or u[1] < nextT) then nextT = u[1] end end
		local current = skill >= t[1] and (not nextT or skill < nextT)
		guide:Row({
			icon = BY_KEY[key][4],
			title = string.format("%d+   %s", t[1], L[t[2]]),
			info = L[t[3]],
			marked = current, markColor = C.good,
		})
	end
	P.RankNotes(guide, skill)
end

function P.RankNotes(guide, skill)
	local parts = {}
	for _, r in ipairs(RANKS) do
		parts[#parts + 1] = string.format(L["%s at skill %d (level %d) to go past %d"], L[r[2]], r[4], r[3], r[1])
	end
	guide:Text(L["Trainer ranks:"] .. " " .. table.concat(parts, "  ·  "), 12, C.muted, 8)
end

function P.CraftPage(guide, key, skill, side)
	local plan = ns.ProfessionPlans and ns.ProfessionPlans[key]
	local steps = plan and plan[side]
	if not steps then return end
	local total, left = 0, 0
	local shopping, order = {}, {}
	for _, s in ipairs(steps) do
		total = total + s[8]
		if skill < s[2] then
			-- the part of this step still to do
			local share = skill > s[1] and (s[2] - skill) / (s[2] - s[1]) or 1
			left = left + s[8] * share
			for _, m in ipairs(s[6]) do
				if not shopping[m[1]] then order[#order + 1] = m[1] end
				shopping[m[1]] = (shopping[m[1]] or 0) + math.ceil(m[2] * share)
			end
		end
	end
	guide:Text(string.format(L["Cheapest recipes taught by the trainers, skill point by skill point. Whole plan: about %s; what is left for you: about %s (material prices estimated from their value in the game)."],
		ns.FormatMoney(math.floor(total / 10000) * 10000), ns.FormatMoney(math.floor(left / 10000) * 10000)), 12, C.muted, 8)
	P.RankNotes(guide, skill)

	for _, s in ipairs(steps) do
		local from, to, spell, item, n, mats, recipe = s[1], s[2], s[3], s[4], s[5], s[6], s[7]
		local name = SpellName(spell) or (item > 0 and ItemName(item, guide)) or ("#" .. spell)
		local parts = {}
		for _, m in ipairs(mats) do parts[#parts + 1] = m[2] .. " " .. ItemName(m[1], guide) end
		local done = skill >= to
		local current = skill >= from and skill < to
		local hint
		if recipe > 0 then
			local v = ns.ProfessionVendors and ns.ProfessionVendors[recipe]
			v = v and v[side]
			hint = string.format(L["Recipe sold by %s"], v and Place(v) or "?")
		elseif recipe < 0 then
			hint = L["Recipe found in the world: buy it at the auction house"]
		end
		local title = string.format("%d-%d   %s %d× %s", from, to, L["Craft"], n, name)
		if done then title = UI.Colorize(title, C.muted) end
		guide:Row({
			icon = item > 0 and ItemIcon(item) or BY_KEY[key][4],
			itemID = item > 0 and item or nil, spellID = item == 0 and spell or nil,
			title = title,
			info = table.concat(parts, ", ") .. (hint and ("   " .. UI.Colorize(hint, C.warn)) or ""),
			value = done and UI.Colorize(L["Done"], C.good) or ns.FormatMoney(math.floor(s[8] / 100) * 100),
			hint = hint,
			marked = current, markColor = C.good,
		})
	end

	if #order > 0 then
		guide:Section(skill > 0 and L["Materials still needed"] or L["Materials needed"])
		local parts = {}
		for _, id in ipairs(order) do parts[#parts + 1] = shopping[id] .. " " .. ItemName(id, guide) end
		guide:Text(table.concat(parts, ",  "), 13, C.text, 4)
		guide:Text(L["Counts are averages: once a recipe turns green, some crafts give no skill point."], 12, C.muted, 6)
	end
end
