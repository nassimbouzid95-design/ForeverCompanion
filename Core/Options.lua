-- ForeverCompanion: options panel (AceConfig). Each module can expose GetOptions().
local ADDON, ns = ...
local L = ns.L

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

local moduleLabels = {
	Leveling = L["Leveling 1-60"],
	Route = L["XP route"],
	Arrow = L["Navigation arrow"],
	Map = L["Map & exploration"],
	Camps = L["Camps"],
	Alts = L["Alts & Legacy"],
	Bags = L["Bags & inventory"],
	LootCollector = L["Drop collector"],
	DungeonGuide = L["Dungeon & raid guide"],
	Interface = L["Interface"],
	Safety = L["Open-world safety"],
	Economy = L["Economy"],
	PvP = L["PvP"],
	Hardcore = L["Hardcore"],
}
ns.moduleLabels = moduleLabels

local moduleDescriptions = {
	Leveling = L["Improved XP bar (XP/hour, time to level, rested XP) and optional quest automation."],
	Route = L["Step-by-step optimised 1-60 route for your race, faction and class, plus a route recorder."],
	Arrow = L["Arrow that points to your current objective or waypoint, with distance."],
	Map = L["Coordinates on the map and minimap, and personal map notes."],
	Camps = L["Remembers the camps you visit and tracks camp buffs."],
	Alts = L["Every character at a glance: level, gold, professions, lockouts, items."],
	Bags = L["Sell junk, auto-repair, item level and on-use highlights on bag items."],
	LootCollector = L["Records boss and trash kills and loot to compute drop rates."],
	DungeonGuide = L["Every dungeon and raid with bosses, loot, trash loot and drop rates."],
	Interface = L["Info bar, richer tooltips and chat improvements."],
	Safety = L["Death log, durability and bag warnings, dangerous mob alerts."],
	Economy = L["Auction prices, where your gold goes, recipes with cost and profit, shopping list."],
	PvP = L["Battleground results, honor per hour and statistics."],
	Hardcore = L["Warnings for dangerous zones and targets, survival panel, dungeon checklist."],
}

local function BuildOptions()
	local FC = ns.FC
	local options = {
		type = "group",
		name = ns.TAG,
		childGroups = "tree",
		args = {
			general = {
				type = "group",
				name = L["General"],
				order = 1,
				args = {
					intro = {
						type = "description",
						order = 1,
						fontSize = "medium",
						name = L["ForeverCompanion is an out-of-combat companion built for WoW Forever. Turn each module on or off below; every module has its own page in the list on the left."] .. "\n",
					},
					minimap = {
						type = "toggle",
						order = 2,
						name = L["Show minimap button"],
						get = function() return not FC.db.profile.minimap.hide end,
						set = function(_, v)
							FC.db.profile.minimap.hide = not v
							ns.UpdateMinimapButton()
						end,
					},
					modulesHeader = { type = "header", order = 10, name = L["Modules"] },
				},
			},
		},
	}

	for i, name in ipairs(ns.moduleOrder) do
		local module = FC:GetModule(name, true)
		if module then
			options.args.general.args["mod_" .. name] = {
				type = "toggle",
				order = 10 + i,
				width = "full",
				name = moduleLabels[name] or name,
				desc = moduleDescriptions[name],
				get = function() return FC.db.profile.modules[name] end,
				set = function(_, v) FC:SetModuleEnabled(name, v) end,
			}
			if module.GetOptions then
				local group = module:GetOptions()
				group.type = "group"
				group.name = moduleLabels[name] or name
				group.order = 10 + i
				group.disabled = function() return not FC.db.profile.modules[name] end
				options.args[name] = group
			end
		end
	end

	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(FC.db)
	options.args.profiles.order = 100
	return options
end

function ns.SetupOptions()
	-- Built lazily so every module (and its GetOptions) is already registered.
	local cached
	AceConfig:RegisterOptionsTable(ADDON, function()
		cached = cached or BuildOptions()
		return cached
	end)
	local _, categoryID = AceConfigDialog:AddToBlizOptions(ADDON, "ForeverCompanion")
	ns.optionsCategoryID = categoryID
	AceConfigDialog:SetDefaultSize(ADDON, 820, 620)
end

function ns.OpenOptions()
	AceConfigDialog:Open(ADDON)
end

-- Helper for modules: a profile-backed getter/setter pair.
function ns.ProfileAccessors(moduleName, onChange)
	return function(info)
		return ns.FC.db.profile[moduleName][info[#info]]
	end, function(info, value)
		ns.FC.db.profile[moduleName][info[#info]] = value
		if onChange then onChange(info[#info], value) end
	end
end
