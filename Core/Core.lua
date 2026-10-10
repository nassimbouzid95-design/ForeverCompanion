-- ForeverCompanion: addon object, database and module management.
local ADDON, ns = ...
local L = ns.L

local FC = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0", "AceTimer-3.0")
ns.FC = FC
_G.ForeverCompanion = FC

FC:SetDefaultModuleState(false)
FC:SetDefaultModuleLibraries("AceEvent-3.0", "AceTimer-3.0")

-- Every module gets these helpers.
FC:SetDefaultModulePrototype({
	-- Profile settings of this module.
	Settings = function(self)
		return FC.db.profile[self.moduleName]
	end,
	-- Account-wide data of this module.
	Global = function(self)
		return FC.db.global[self.moduleName]
	end,
	Print = function(self, ...)
		ns.Print(...)
	end,
})

-- Order and labels used by the options panel.
ns.moduleOrder = {
	"Leveling", "Route", "Arrow", "Map", "Camps", "Alts", "Bags",
	"LootCollector", "DungeonGuide", "Economy", "PvP", "Hardcore", "Interface", "Safety",
}

-- Creates a module and registers its default settings. enabledByDefault defaults to true.
function ns.NewModule(name, profileDefaults, globalDefaults, enabledByDefault)
	ns.defaults.profile.modules[name] = enabledByDefault ~= false
	if profileDefaults then ns.RegisterDefaults("profile", name, profileDefaults) end
	if globalDefaults then ns.RegisterDefaults("global", name, globalDefaults) end
	return FC:NewModule(name)
end

function FC:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("ForeverCompanionDB", ns.defaults, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshModules")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshModules")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshModules")

	self:RegisterChatCommand("fc", "SlashCommand")
	self:RegisterChatCommand("forever", "SlashCommand")

	ns.SetupOptions()
	ns.SetupMinimap()
end

function FC:OnEnable()
	self:RefreshModules()
	if not self.db.global.welcomed then
		self.db.global.welcomed = true
		ns.Print(L["Welcome! Type /fc to open the options, /fc help for all commands."])
	end
end

function FC:RefreshModules()
	for name, module in self:IterateModules() do
		local wanted = self.db.profile.modules[name]
		if wanted and not module:IsEnabled() then
			module:Enable()
		elseif not wanted and module:IsEnabled() then
			module:Disable()
		elseif wanted and module.OnProfileChanged then
			module:OnProfileChanged()
		end
	end
end

function FC:SetModuleEnabled(name, enabled)
	self.db.profile.modules[name] = enabled and true or false
	self:RefreshModules()
end

-- Slash commands. Modules register sub-commands with ns.RegisterCommand.
ns.commands = {}

function ns.RegisterCommand(word, help, handler)
	ns.commands[word] = { help = help, handler = handler }
end

function FC:SlashCommand(input)
	input = input or ""
	local word, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
	word = (word or ""):lower()
	if word == "" or word == "config" or word == "options" then
		ns.OpenOptions()
		return
	end
	if word == "help" then
		ns.Print(L["Commands:"])
		print("  /fc - " .. L["open the options"])
		local words = {}
		for w in pairs(ns.commands) do words[#words + 1] = w end
		table.sort(words)
		for _, w in ipairs(words) do
			print(string.format("  /fc %s - %s", w, ns.commands[w].help))
		end
		return
	end
	local cmd = ns.commands[word]
	if cmd then
		cmd.handler(rest)
	else
		ns.Print(L["Unknown command. Type /fc help."])
	end
end
