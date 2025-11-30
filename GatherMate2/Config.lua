local GatherMate = LibStub("AceAddon-3.0"):GetAddon("GatherMate2")
local Config = GatherMate:NewModule("Config","AceConsole-3.0","AceEvent-3.0")
local Display = GatherMate:GetModule("Display")
local L = LibStub("AceLocale-3.0"):GetLocale("GatherMate2", false)

-- Databroker support
local DataBroker = LibStub:GetLibrary("LibDataBroker-1.1",true)
local DBIcon = LibStub("LibDBIcon-1.0", true)

--[[
	Code here for configuring the mod, and making the minimap button
]]

-- [[ ----------------------------------------------------------------------- ]]
-- [[ CUSTOM HELPER FUNCTIONS START                                           ]]
-- [[ ----------------------------------------------------------------------- ]]

-- Flag to suppress spam on login
local loginGracePeriod = true

-- Variables for Hat Reminder
local lastHatWarning = 0
local HAT_IDS = {
    HERB = 1004000, -- Herbalist's Hat
    MINE = 1004001  -- Miner's Hat
}
local BUFF_NAMES = {
    HERB = "Herbalism Speed",
    MINE = "Mining Speed"
}

-- Icon Getter for Tooltips/Messages
local function GetProfessionIcon(profKey)
    if profKey == "Herb Gathering" then return "|TInterface\\Icons\\Trade_Herbalism:16|t "
    elseif profKey == "Mining" then return "|TInterface\\Icons\\Trade_Mining:16|t "
    elseif profKey == "Woodcutting" then return "|TInterface\\Icons\\INV_TradeskillItem_03:16|t "
    elseif profKey == "Treasure" then return "|TInterface\\Icons\\Spell_Nature_MoonKey:16|t "
    end
    return ""
end

-- Text Display for the Menu
local function GetSkillDisplayText(profKey)
    local skill = GatherMate.skillRank[profKey]
    local name = (profKey == "Treasure") and "Lockpicking" or profKey
    if profKey == "Herb Gathering" then name = "Herbalism" end
    local icon = GetProfessionIcon(profKey)

    if skill == 0 then
        return icon .. "|cffff0000" .. name .. " Not Learned|r"
    else
        return icon .. "|cffffd700Current " .. name .. " Skill: " .. skill .. "|r"
    end
end

-- Color logic
local function GetSkillColor(req, current)
    if not req or req == 0 then return "ffffff" end -- No level = White
    
    if current < req then return "ff0000" -- Red
    elseif current >= (req + 100) then return "808080" -- Grey
    elseif current >= (req + 50) then return "00ff00" -- Green
    elseif current >= (req + 25) then return "ffff00" -- Yellow
    else return "ff9900" -- Orange
    end
end

-- Sorting Helper
local function ResolveNodeKey(key, profKey)
    local db = GatherMate.db.profile
    local settings = db.customSettings and db.customSettings[profKey]
    if settings and settings.sortLevel and string.match(key, "^%d%d%d_") then
        return string.sub(key, 5)
    end
    return key
end

-- Logic to determine if a node should be selected
local function IsNodeUseful(nodeID, profKey, isBackground)
    local minHarvestTable = GatherMate.nodeMinHarvest[profKey]
    if not minHarvestTable then return nil end

    local req = minHarvestTable[nodeID]
    
    -- Special Case: No level requirement (e.g. Dirt Piles, Gas)
    if not req or req == 0 then 
        -- If this is a background auto-update, DO NOT touch generic items.
        if isBackground then return nil end
        return true 
    end 

    local currentSkill = GatherMate.skillRank[profKey]

    if currentSkill < req then return false -- Red
    elseif currentSkill >= (req + 50) then return false -- Green/Grey
    else return true -- Orange/Yellow
    end
end

-- Auto-Update Worker
function GatherMate:PerformAutoUpdate(profKey, isBackground)
    local db = GatherMate.db.profile
    if not db.customSettings or not db.customSettings[profKey] then return end
    if isBackground and not db.customSettings[profKey].autoUpdate then return end

    local dbFilter = db.filter[profKey]
    local nids = GatherMate.nodeIDs[profKey]
    local changesMade = false
    local playSound = db.customSettings[profKey].sound

    for name, id in pairs(nids) do
        local shouldSelect = IsNodeUseful(id, profKey, isBackground)
        
        if shouldSelect ~= nil then
            if dbFilter[id] ~= shouldSelect then
                dbFilter[id] = shouldSelect
                changesMade = true

                -- Notifications (SUPPRESSED DURING LOGIN GRACE PERIOD)
                if not loginGracePeriod then
                    local iconPath = GatherMate.nodeTextures[profKey][id]
                    local iconString = iconPath and ("|T"..iconPath..":0|t ") or ""
                    local profIcon = GetProfessionIcon(profKey)

                    if shouldSelect then
                        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GatherMate2:|r Auto-selected " .. profIcon .. iconString .. "|cffffffff" .. name .. "|r")
                        
                        local prettyIcon = iconPath and ("|T"..iconPath..":20:20|t ") or ""
                        UIErrorsFrame:AddMessage(prettyIcon .. "You can now collect " .. name .. "!", 1.0, 0.82, 0.0, 1.0, UIERRORS_HOLD_TIME) 
                        
                        if playSound and isBackground then 
                            PlaySound("igQuestListComplete") 
                        end
                    else
                        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99GatherMate2:|r Auto-unselected " .. profIcon .. iconString .. "|cffaaaaaa" .. name .. "|r")
                    end
                end
            end
        end
    end

    if changesMade then Config:SendMessage("GatherMate2ConfigChanged") end
end

-- Hat Reminder Logic
local function CheckHatBuffs()
    local db = GatherMate.db.profile
    if not db.checkHats then return end
    if loginGracePeriod then return end -- Don't warn on login

    -- Throttle: Check every 60 seconds max to avoid spam
    local now = GetTime()
    if (now - lastHatWarning) < 60 then return end

    local warningTriggered = false

    -- Check Herb Hat (If Profession Learned)
    if GatherMate.skillRank["Herb Gathering"] > 0 and GetItemCount(HAT_IDS.HERB) > 0 then
        local name = UnitAura("player", BUFF_NAMES.HERB)
        if not name then
            UIErrorsFrame:AddMessage("|TInterface\\Icons\\Trade_Herbalism:20:20|t Equip your Herbalist's Hat to refresh the buff!", 1.0, 0.0, 0.0, 1.0, UIERRORS_HOLD_TIME)
            warningTriggered = true
        end
    end

    -- Check Mine Hat (If Profession Learned)
    if not warningTriggered and GatherMate.skillRank["Mining"] > 0 and GetItemCount(HAT_IDS.MINE) > 0 then
        local name = UnitAura("player", BUFF_NAMES.MINE)
        if not name then
            UIErrorsFrame:AddMessage("|TInterface\\Icons\\Trade_Mining:20:20|t Equip your Miner's Hat to refresh the buff!", 1.0, 0.0, 0.0, 1.0, UIERRORS_HOLD_TIME)
            warningTriggered = true
        end
    end

    if warningTriggered then
        lastHatWarning = now
        PlaySound("RaidWarning") -- Audible alert
    end
end

-- Generates the dynamic list for the UI
local function GetColoredNodeList(profKey)
    local new = {}
    local minHarvestTable = GatherMate.nodeMinHarvest[profKey] or {}
    local currentSkill = GatherMate.skillRank[profKey]
    local db = GatherMate.db.profile
    local settings = (db.customSettings and db.customSettings[profKey]) or {}
    
    for name, id in pairs(GatherMate.nodeIDs[profKey]) do
        local lvl = minHarvestTable[id] or 0
        local color = GetSkillColor(lvl, currentSkill)
        local paddedLvl = string.format("%03d", lvl)
        local label
        
        if lvl > 0 then label = string.format("|cff%s(%s) %s|r", color, paddedLvl, name)
        else label = name end
        
        if settings.sortLevel and lvl > 0 then
            local sortKey = paddedLvl .. "_" .. name
            new[sortKey] = label
        else
            new[name] = label
        end
    end
    return new
end

-- Wrappers for AceConfig
local function GetHerbList() return GetColoredNodeList("Herb Gathering") end
local function GetMineList() return GetColoredNodeList("Mining") end
local function GetTreasureList() return GetColoredNodeList("Treasure") end
local function GetWoodList() return GetColoredNodeList("Woodcutting") end

-- [[ CUSTOM HELPER FUNCTIONS END ------------------------------------------- ]]

-- Setup keybinds (these need to be global strings to show up properly in ESC -> Key Bindings)
BINDING_HEADER_GatherMate = "GatherMate2"
BINDING_NAME_TOGGLE_GATHERMATE2_MINIMAPICONS = L["Keybind to toggle Minimap Icons"]
BINDING_NAME_TOGGLE_GATHERMATE2_WORLDMAPICONS = L["Keybind to toggle Worldmap Icons"]
-- A helper function for keybindings
local KeybindHelper = {}
do
	local t = {}
	function KeybindHelper:MakeKeyBindingTable(...)
		for k in pairs(t) do t[k] = nil end
		for i = 1, select("#", ...) do
			local key = select(i, ...)
			if key ~= "" then
				tinsert(t, key)
			end
		end
		return t
	end
end


local prof_options = {
	["always"]          = L["Always show"],
	["with_profession"] = L["Only with profession"],
	["active"]          = L["Only while tracking"],
	["never"]           = L["Never show"],
}
local prof_options2 = { -- For Gas, which doesn't have tracking as a skill
	["always"]           = L["Always show"],
	["with_profession"]  = L["Only with profession"],
	["never"]            = L["Never show"],
}
local prof_options3 = {
	["always"]          = L["Always show"],
	["active"]          = L["Only while tracking"],
	["never"]           = L["Never show"],
}

local options = {}
local db
local imported = {}
-- setup the options, we need to reference GatherMate for this
options.type = "group"
options.name = "GatherMate2"
options.get = function( k ) return db[k.arg] end
options.set = function( k, v ) db[k.arg] = v; Config:UpdateConfig(); end
options.args = {}

-- Display Settings config tree
options.args.display = {
	type = "group",
	name = L["Display Settings"],
	order = 1,
	args = {},
}
options.args.display.args.general = {
	type = "group",
	name = L["General"],
	order = 1,
	args = {
		showGroup = {
			type = "group",
			name = L["Show Databases"],
			guiInline = true,
			order = 1,
			get = function(k) return db.show[k.arg] end,
			set = function(k, v) db.show[k.arg] = v; Config:UpdateConfig(); end,
			args = {
				desc = {
					order = 0,
					type = "description",
					name = L["Selected databases are shown on both the World Map and Minimap."],
				},
				showMinerals = {
					order = 1,
					name = L["Show Mining Nodes"],
					desc = L["Toggle showing mining nodes."],
					type = "select",
					values = prof_options,
					arg = "Mining"
				},
				showHerbs = {
					order = 2,
					name = L["Show Herbalism Nodes"],
					desc = L["Toggle showing herbalism nodes."],
					type = "select",
					values = prof_options,
					arg = "Herb Gathering"
				},
				showFishes = {
					order = 3,
					name = L["Show Fishing Nodes"],
					desc = L["Toggle showing fishing nodes."],
					type = "select",
					values = prof_options,
					arg = "Fishing"
				},
				showGases = {
					order = 4,
					name = L["Show Gas Clouds"],
					desc = L["Toggle showing gas clouds."],
					type = "select",
					values = prof_options2,
					arg = "Extract Gas"
				},
				showTreasure = {
					order = 5,
					name = L["Show Treasure Nodes"],
					desc = L["Toggle showing treasure nodes."],
					type = "select",
					values = prof_options3,
					arg = "Treasure"
				},
				showWoodcutting = {
					order = 6,
					name = L["Show Woodcutting Nodes"],
					desc = L["Toggle showing woodcutting nodes."],
					type = "select",
					values = prof_options,
					arg = "Woodcutting"
				}
			},
		},
		iconGroup = {
			type = "group",
			name = L["Icons"],
			guiInline = true,
			order = 2,
			args = {
				desc = {
					order = 0,
					type = "description",
					name = L["Control various aspects of node icons on both the World Map and Minimap."],
				},
				showMinimapIcons = {
					order = 1,
					name = L["Show Minimap Icons"],
					desc = L["Toggle showing Minimap icons."],
					type = "toggle",
					arg = "showMinimap",
				},
				showWorldMapIcons = {
					order = 2,
					name = L["Show World Map Icons"],
					desc = L["Toggle showing World Map icons."],
					type = "toggle",
					arg = "showWorldMap",
				},
				minimapTooltips = {
					order = 3,
					name = L["Minimap Icon Tooltips"],
					desc = L["Toggle showing Minimap icon tooltips."],
					type = "toggle",
					arg = "minimapTooltips",
					disabled = function() return not db.showMinimap end,
				},
				togglekey = {
					order = 4,
					name = L["Keybind to toggle Minimap Icons"],
					desc = L["Keybind to toggle Minimap Icons"],
					type = "keybinding",
					width = "double",
					get = function(info)
						return table.concat(KeybindHelper:MakeKeyBindingTable(GetBindingKey("TOGGLE_GATHERMATE2_MINIMAPICONS")), ", ")
					end,
					set = function(info, key)
						if key == "" then
							local t = KeybindHelper:MakeKeyBindingTable(GetBindingKey("TOGGLE_GATHERMATE2_MINIMAPICONS"))
							for i = 1, #t do
								SetBinding(t[i])
							end
						else
							local oldAction = GetBindingAction(key)
							local frame = LibStub("AceConfigDialog-3.0").OpenFrames["GatherMate"]
							if frame then
								if ( oldAction ~= "" and oldAction ~= "TOGGLE_GATHERMATE2_MINIMAPICONS" ) then
									frame:SetStatusText(KEY_UNBOUND_ERROR:format(GetBindingText(oldAction, "BINDING_NAME_")))
								else
									frame:SetStatusText(KEY_BOUND)
								end
							end
							SetBinding(key, "TOGGLE_GATHERMATE2_MINIMAPICONS")
						end
						SaveBindings(GetCurrentBindingSet())
					end,
				},
				togglekeyWorld = {
					order = 5,
					name = L["Keybind to toggle Worldmap Icons"],
					desc = L["Keybind to toggle Worldmap Icons"],
					type = "keybinding",
					width = "double",
					get = function(info)
						return table.concat(KeybindHelper:MakeKeyBindingTable(GetBindingKey("TOGGLE_GATHERMATE2_WORLDMAPICONS")), ", ")
					end,
					set = function(info, key)
						if key == "" then
							local t = KeybindHelper:MakeKeyBindingTable(GetBindingKey("TOGGLE_GATHERMATE2_WORLDMAPICONS"))
							for i = 1, #t do
								SetBinding(t[i])
							end
						else
							local oldAction = GetBindingAction(key)
							local frame = LibStub("AceConfigDialog-3.0").OpenFrames["GatherMate"]
							if frame then
								if ( oldAction ~= "" and oldAction ~= "TOGGLE_GATHERMATE2_WORLDMAPICONS" ) then
									frame:SetStatusText(KEY_UNBOUND_ERROR:format(GetBindingText(oldAction, "BINDING_NAME_")))
								else
									frame:SetStatusText(KEY_BOUND)
								end
							end
							SetBinding(key, "TOGGLE_GATHERMATE2_WORLDMAPICONS")
						end
						SaveBindings(GetCurrentBindingSet())
					end,
				},
                -- [[ CUSTOM: Minimap Button Toggle ]]
                showMMButton = {
                    order = 5.5,
                    name = "Show Minimap Button",
                    desc = "Toggles the minimap button.",
                    type = "toggle",
                    get = function() return not db.minimapIcon.hide end,
                    set = function(info, val) 
                        db.minimapIcon.hide = not val
                        if val then DBIcon:Show("GatherMate2") else DBIcon:Hide("GatherMate2") end
                    end,
                },
                -- [[ CUSTOM: Hat Reminder Toggle ]]
                hatReminder = {
                    order = 5.6,
                    name = "|cffff8000Hat Buff Reminder|r",
                    desc = "Displays a warning if you have a Gathering Hat in your bag but missing the speed buff.",
                    type = "toggle",
                    get = function() return db.checkHats end,
                    set = function(info, val) db.checkHats = val end,
                },
				space = {
					order = 6,
					name = "",
					desc = "",
					type = "description",
				},
				iconScale = {
					order = 7,
					name = L["Icon Scale"],
					desc = L["Icon scaling, this lets you enlarge or shrink your icons on both the World Map and Minimap."],
					type = "range",
					min = 0.5, max = 5, step = 0.01,
					arg = "scale",
				},
				iconAlpha = {
					order = 8,
					name = L["Icon Alpha"],
					desc = L["Icon alpha value, this lets you change the transparency of the icons. Only applies on World Map."],
					type = "range",
					min = 0.1, max = 1, step = 0.05,
					arg = "alpha",
				},
				minimapNodeRange = {
					order = 9,
					type = "toggle",
					name = L["Show Nodes on Minimap Border"],
					width = "double",
					desc = L["Shows more Nodes that are currently out of range on the minimap's border."],
					arg = "nodeRange",
				},
				tracking = {
					order = 10,
					name = L["Tracking Circle Color"],
					desc = L["Color of the tracking circle."],
					type = "group",
					guiInline = true,
					get = function(info)
						local t = db.trackColors[info.arg]
						return t.Red, t.Green, t.Blue, t.Alpha
					end,
					set = function(info, r, g, b, a)
						local t = db.trackColors[info.arg]
						t.Red = r
						t.Green = g
						t.Blue = b
						t.Alpha = a
						Config:UpdateConfig()
					end,
					args = {
						trackingColorMine = {
							order = 1,
							name = L["Mineral Veins"],
							desc = L["Color of the tracking circle."],
							type = "color",
							hasAlpha = true,
							arg = "Mining",
						},
						trackingColorHerb = {
							order = 2,
							name = L["Herb Bushes"],
							desc = L["Color of the tracking circle."],
							type = "color",
							hasAlpha = true,
							arg = "Herb Gathering",
						},
						trackingColorFish = {
							order = 3,
							name = L["Fishing"],
							desc = L["Color of the tracking circle."],
							type = "color",
							hasAlpha = true,
							arg = "Fishing",
						},
						trackingColorGas = {
							order = 4,
							name = L["Gas Clouds"],
							desc = L["Color of the tracking circle."],
							type = "color",
							hasAlpha = true,
							arg = "Extract Gas",
						},
						trackingColorTreasure = {
							order = 6,
							name = L["Treasure"],
							desc = L["Color of the tracking circle."],
							type = "color",
							hasAlpha = true,
							arg = "Treasure",
						},
						trackingColorWoodcutting = {
							order = 7,
							name = L["Woodcutting"],
							desc = L["Color of the tracking circle."],
							type = "color",
							hasAlpha = true,
							arg = "Woodcutting",
						},
						space = {
							order = 7,
							name = "",
							desc = "",
							type = "description",
						},
						trackDistance = {
							order = 15,
							name = L["Tracking Distance"],
							desc = L["The distance in yards to a node before it turns into a tracking circle"],
							type = "range",
							min = 50, max = 240, step = 5,
							get = options.get,
							set = options.set,
							arg = "trackDistance",
						},
						trackShow = {
							order = 20,
							name = L["Show Tracking Circle"],
							desc = L["Toggle showing the tracking circle."],
							type = "select",
							get = options.get,
							set = options.set,
							values = prof_options,
							arg = "trackShow",
						},
					},
				},
			},
		},
	},
}

-- Setup some storage arrays by db to sort node names and zones alphabetically
-- LEGACY behavior for Fish/Gas
local sortedFilter = setmetatable({}, {__index = function(t, k)
	local new = {}
	if k == "zones" then
		for index, zoneID in pairs(GatherMate.mapData:GetAllMapIDs()) do
			local name = GatherMate.mapData:MapLocalize(zoneID)
			new[name] = name
		end
	else
		local minHarvestTable = GatherMate.nodeMinHarvest[k]
		for name, id in pairs(GatherMate.nodeIDs[k]) do
			local lvl = minHarvestTable[id]
			if lvl then
				new[name] = "("..lvl..") "..name
			else
				new[name] = name
			end
		end
	end
	rawset(t, k, new)
	return new
end})

-- Setup some helper functions
local ConfigFilterHelper = {}
function ConfigFilterHelper:SelectAll(info)
	local db = db.filter[info.arg]
	local nids = GatherMate.nodeIDs[info.arg]
	for k, v in pairs(nids) do
		db[v] = true
	end
	Config:UpdateConfig()
end
function ConfigFilterHelper:SelectNone(info)
	local db = db.filter[info.arg]
	local nids = GatherMate.nodeIDs[info.arg]
	for k, v in pairs(nids) do
		db[v] = false
	end
	Config:UpdateConfig()
end

-- [[ CUSTOM: Manual Trigger Button ]]
function ConfigFilterHelper:SelectUseful(info)
    GatherMate:PerformAutoUpdate(info.arg, false)
end

-- [[ CUSTOM: Modifed SetState to handle Sorting Keys ]]
function ConfigFilterHelper:SetState(info, k, state)
    local realKey = ResolveNodeKey(k, info.arg)
    local id = GatherMate.nodeIDs[info.arg][realKey]
    if id then
	    db.filter[info.arg][id] = state
	    Config:UpdateConfig()
    end
end
-- [[ CUSTOM: Modifed GetState to handle Sorting Keys ]]
function ConfigFilterHelper:GetState(info, k)
    local realKey = ResolveNodeKey(k, info.arg)
    local id = GatherMate.nodeIDs[info.arg][realKey]
    if id then
	    return db.filter[info.arg][id]
    end
end

-- [[ CUSTOM: Toggle Helper for Custom Settings ]]
local function CustomToggleGet(info) 
    local prof = info.arg
    local setting = info[#info] -- gets "autoUpdate", "sortLevel", etc from key name
    return db.customSettings[prof] and db.customSettings[prof][setting]
end
local function CustomToggleSet(info, val) 
    local prof = info.arg
    local setting = info[#info]
    if not db.customSettings[prof] then db.customSettings[prof] = {} end
    db.customSettings[prof][setting] = val
    if setting == "autoUpdate" and val then GatherMate:PerformAutoUpdate(prof, false) end
end


local ImportHelper = {}

function ImportHelper:GetImportStyle(info,k)
	return db["importers"][info.arg].Style
end
function ImportHelper:SetImportStyle(info,k,state)
	db["importers"][info.arg].Style = k
end
function ImportHelper:GetImportDatabase(info,k)
	return db["importers"][info.arg].Databases[k]
end
function ImportHelper:SetImportDatabase(info,k,state)
	db["importers"][info.arg].Databases[k] = state
end
function ImportHelper:GetAutoImport(info, k)
	return db["importers"][info.arg].autoImport
end
function ImportHelper:SetAutoImport(info,state)
	db["importers"][info.arg].autoImport = state
end
function ImportHelper:GetBCOnly(info,k)
	return db["importers"][info.arg].bcOnly
end
function ImportHelper:SetBCOnly(info,state)
	db["importers"][info.arg].bcOnly = state
end
function ImportHelper:GetExpacOnly(info,k)
	return db["importers"][info.arg].expacOnly
end
function ImportHelper:SetExpacOnly(info,state)
	db["importers"][info.arg].expacOnly = state
end
function ImportHelper:GetExpac(info,k)
	return db["importers"][info.arg].expac
end
function ImportHelper:SetExpac(info,state)
	db["importers"][info.arg].expac = state
end

local commonFiltersDescTable = {
	order = 0,
	type = "description",
	name = L["Filter_Desc"],
}
options.args.display.args.filters = {
	type = "group",
	name = L["Filters"],
	order = 2,
	--childGroups = "tab", -- this makes the filter tree become inline tabs
	handler = ConfigFilterHelper,
	args = {},
}

-- [[ CUSTOM: Modified HERB Filter Menu ]]
options.args.display.args.filters.args.herbs = {
	type = "group",
	name = L["Herb filter"],
	desc = L["Select the herb nodes you wish to display."],
	args = {
		desc = commonFiltersDescTable,
        currentSkill = { order = 0.05, type = "description", fontSize = "medium", name = function() return GetSkillDisplayText("Herb Gathering") end, },
        autoUpdate = { order = 0.1, name = "|cff00ff00Enable Auto-Update|r", desc = "Auto-selects Orange/Yellow nodes based on skill.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Herb Gathering", width = "full", },
        sortLevel = { order = 0.2, name = "Sort by Level", desc = "Sort list by skill requirement.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Herb Gathering", width = "half", },
        sound = { order = 0.3, name = "Sound", desc = "Play sound on new useful node.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Herb Gathering", width = "half", },
		select_all = {
			order = 1,
			name = L["Select All"],
			desc = L["Select all nodes"],
			type = "execute",
			func = "SelectAll",
			arg = "Herb Gathering",
		},
		select_none = {
			order = 2,
			desc = L["Clear node selections"],
			name = L["Select None"],
			type = "execute",
			func = "SelectNone",
			arg = "Herb Gathering",
		},
        select_useful = { 
            order = 2.5, 
            name = "Force Update Now", 
            type = "execute", 
            func = "SelectUseful", 
            arg = "Herb Gathering", 
        },
		herblist = {
			order = 3,
			name = L["Herb Bushes"],
			type = "multiselect",
			values = GetHerbList,
			set = "SetState",
			get = "GetState",
			arg = "Herb Gathering",
		},
	},
}

-- [[ CUSTOM: Modified MINING Filter Menu ]]
options.args.display.args.filters.args.mines = {
	type = "group",
	name = L["Mine filter"],
	desc = L["Select the mining nodes you wish to display."],
	args = {
		desc = commonFiltersDescTable,
        currentSkill = { order = 0.05, type = "description", fontSize = "medium", name = function() return GetSkillDisplayText("Mining") end, },
        autoUpdate = { order = 0.1, name = "|cff00ff00Enable Auto-Update|r", desc = "Auto-selects Orange/Yellow nodes based on skill.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Mining", width = "full", },
        sortLevel = { order = 0.2, name = "Sort by Level", desc = "Sort list by skill requirement.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Mining", width = "half", },
        sound = { order = 0.3, name = "Sound", desc = "Play sound on new useful node.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Mining", width = "half", },
		select_all = {
			order = 1,
			name = L["Select All"],
			desc = L["Select all nodes"],
			type = "execute",
			func = "SelectAll",
			arg = "Mining",
		},
		select_none = {
			order = 2,
			desc = L["Clear node selections"],
			name = L["Select None"],
			type = "execute",
			func = "SelectNone",
			arg = "Mining",
		},
        select_useful = { order = 2.5, name = "Force Update Now", type = "execute", func = "SelectUseful", arg = "Mining", },
		minelist = {
			order = 3,
			name = L["Mineral Veins"],
			type = "multiselect",
			values = GetMineList,
			set = "SetState",
			get = "GetState",
			arg = "Mining",
		},
	},
}
options.args.display.args.filters.args.fish = {
	type = "group",
	name = L["Fish filter"],
	args = {
		desc = commonFiltersDescTable,
		select_all = {
			order = 1,
			name = L["Select All"],
			desc = L["Select all nodes"],
			type = "execute",
			func = "SelectAll",
			arg = "Fishing",
		},
		select_none = {
			order = 2,
			desc = L["Clear node selections"],
			name = L["Select None"],
			type = "execute",
			func = "SelectNone",
			arg = "Fishing",
		},
		fishlist = {
			order = 3,
			name = L["Fishes"],
			type = "multiselect",
			desc = L["Select the fish nodes you wish to display."],
			values = sortedFilter["Fishing"],
			set = "SetState",
			get = "GetState",
			arg = "Fishing",
		},
	},
}
options.args.display.args.filters.args.gas = {
	type = "group",
	name = L["Gas filter"],
	args = {
		desc = commonFiltersDescTable,
		select_all = {
			order = 1,
			name = L["Select All"],
			desc = L["Select all nodes"],
			type = "execute",
			func = "SelectAll",
			arg = "Extract Gas",
		},
		select_none = {
			order = 2,
			name = L["Select None"],
			desc = L["Clear node selections"],
			type = "execute",
			func = "SelectNone",
			arg = "Extract Gas",
		},
		gaslist = {
			order = 3,
			name = L["Gas Clouds"],
			desc = L["Select the gas clouds you wish to display."],
			type = "multiselect",
			values = sortedFilter["Extract Gas"],
			set = "SetState",
			get = "GetState",
			arg = "Extract Gas",
		},
	},
}

-- [[ CUSTOM: Modified TREASURE Filter Menu ]]
options.args.display.args.filters.args.treasure = {
	type = "group",
	name = L["Treasure filter"],
    desc = "Requires Lockpicking for auto-update on locked chests.",
	args = {
		desc = commonFiltersDescTable,
        currentSkill = { order = 0.05, type = "description", fontSize = "medium", name = function() return GetSkillDisplayText("Treasure") end, },
        autoUpdate = { order = 0.1, name = "|cff00ff00Enable Auto-Update|r", desc = "Auto-selects Orange/Yellow nodes based on skill.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Treasure", width = "full", },
        sortLevel = { order = 0.2, name = "Sort by Level", desc = "Sort list by skill requirement.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Treasure", width = "half", },
        sound = { order = 0.3, name = "Sound", desc = "Play sound on new useful node.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Treasure", width = "half", },
		select_all = {
			order = 1,
			name = L["Select All"],
			desc = L["Select all nodes"],
			type = "execute",
			func = "SelectAll",
			arg = "Treasure",
		},
		select_none = {
			order = 2,
			name = L["Select None"],
			desc = L["Clear node selections"],
			type = "execute",
			func = "SelectNone",
			arg = "Treasure",
		},
        select_useful = { order = 2.5, name = "Force Update Now", type = "execute", func = "SelectUseful", arg = "Treasure", },
		gaslist = {
			order = 3,
			name = L["Treasure"],
			desc = L["Select the treasure you wish to display."],
			type = "multiselect",
			values = GetTreasureList,
			set = "SetState",
			get = "GetState",
			arg = "Treasure",
		},
	},
}

-- [[ CUSTOM: Modified WOODCUTTING Filter Menu ]]
options.args.display.args.filters.args.woodcutting = {
	type = "group",
	name = L["Woodcutting filter"],
	args = {
		desc = commonFiltersDescTable,
        currentSkill = { order = 0.05, type = "description", fontSize = "medium", name = function() return GetSkillDisplayText("Woodcutting") end, },
        autoUpdate = { order = 0.1, name = "|cff00ff00Enable Auto-Update|r", desc = "Auto-selects Orange/Yellow nodes based on skill.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Woodcutting", width = "full", },
        sortLevel = { order = 0.2, name = "Sort by Level", desc = "Sort list by skill requirement.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Woodcutting", width = "half", },
        sound = { order = 0.3, name = "Sound", desc = "Play sound on new useful node.", type = "toggle", get = CustomToggleGet, set = CustomToggleSet, arg = "Woodcutting", width = "half", },
		select_all = {
			order = 1,
			name = L["Select All"],
			desc = L["Select all nodes"],
			type = "execute",
			func = "SelectAll",
			arg = "Woodcutting",
		},
		select_none = {
			order = 2,
			name = L["Select None"],
			desc = L["Clear node selections"],
			type = "execute",
			func = "SelectNone",
			arg = "Woodcutting",
		},
        select_useful = { order = 2.5, name = "Force Update Now", type = "execute", func = "SelectUseful", arg = "Woodcutting", },
		gaslist = {
			order = 3,
			name = L["Treasure"],
			desc = L["Select the woodcutting nodes you wish to display."],
			type = "multiselect",
			values = GetWoodList,
			set = "SetState",
			get = "GetState",
			arg = "Woodcutting",
		},
	},
}

local selectedDatabase, selectedNode, selectedZone = "Extract Gas", 0, nil

-- Cleanup config tree
options.args.cleanup = {
	type = "group",
	name = L["Database Maintenance"],
	order = 5,
	args = {
		cleanup = {
			order = 20,
			name = L["Cleanup Database"],
			type = "group",
			args = {
				cleanup = {
					order = 10,
					name = L["Cleanup Database"],
					type = "group",
					guiInline = true,
					args = {
						desc = {
							order = 0,
							type = "description",
							name = L["Cleanup_Desc"],
						},
						cleanup = {
							name = L["Cleanup Database"],
							desc = L["Cleanup your database by removing duplicates. This takes a few moments, be patient."],
							type = "execute",
							handler = GatherMate,
							func = "CleanupDB",
							order = 20,
						},
					},
				},
				deleteSelective = {
					order = 20,
					name = L["Delete Specific Nodes"],
					type = "group",
					guiInline = true,
					args = {
						desc = {
							order = 0,
							type = "description",
							name = L["DELETE_SPECIFIC_DESC"],
						},
						selectDB = {
							order = 30,
							name = L["Select Database"],
							desc = L["Select Database"],
							type = "select",
							values = {
								["Fishing"] = L["Fishes"],
								["Treasure"] = L["Treasure"],
								["Herb Gathering"] = L["Herb Bushes"],
								["Mining"] = L["Mineral Veins"],
								["Extract Gas"] = L["Gas Clouds"],
								["Woodcutting"] = L["Woodcutting"],
								["Worldforged"] = L["World Interactable"],
							},
							get = function() return selectedDatabase end,
							set = function(k, v)
								selectedDatabase = v
								selectedNode = 0
							end,
						},
						selectNode = {
							order = 40,
							name = L["Select Node"],
							desc = L["Select Node"],
							type = "select",
							values = function()
								return sortedFilter[selectedDatabase]
							end,
							get = function() return selectedNode end,
							set = function(k, v) selectedNode = v end,
						},
						selectZone = {
							order = 50,
							name = L["Select Zone"],
							desc = L["Select Zone"],
							type = "select",
							values = sortedFilter["zones"],
							get = function() return selectedZone end,
							set = function(k, v) selectedZone = v end,
						},
						delete = {
							order = 60,
							name = L["Delete"],
							desc = L["Delete selected node from selected zone"],
							type = "execute",
							confirm = true,
							confirmText = L["Are you sure you want to delete all of the selected node from the selected zone?"],
							func = function()
								if selectedZone and selectedNode ~= 0 then
									GatherMate:DeleteNodeFromZone(selectedDatabase, GatherMate.nodeIDs[selectedDatabase][selectedNode], selectedZone)
								end
							end,
							disabled = function()
								return selectedNode == 0 or selectedZone == nil
							end,
						},
					},
				},
				delete = {
					order = 30,
					name = L["Delete Entire Database"],
					type = "group",
					guiInline = true,
					func = function(info)
						GatherMate:ClearDB(info.arg)
					end,
					args = {
						desc = {
							order = 0,
							type = "description",
							name = L["DELETE_ENTIRE_DESC"],
						},
						Mine = {
							order = 5,
							name = L["Mineral Veins"],
							desc = L["Delete Entire Database"],
							type = "execute",
							arg = "Mining",
							confirm = true,
							confirmText = L["Are you sure you want to delete all nodes from this database?"],
						},
						Herb = {
							order = 5,
							name = L["Herb Bushes"],
							desc = L["Delete Entire Database"],
							type = "execute",
							arg = "Herb Gathering",
							confirm = true,
							confirmText = L["Are you sure you want to delete all nodes from this database?"],
						},
						Fish = {
							order = 5,
							name = L["Fishes"],
							desc = L["Delete Entire Database"],
							type = "execute",
							arg = "Fishing",
							confirm = true,
							confirmText = L["Are you sure you want to delete all nodes from this database?"],
						},
						Gas = {
							order = 5,
							name = L["Gas Clouds"],
							desc = L["Delete Entire Database"],
							type = "execute",
							arg = "Extract Gas",
							confirm = true,
							confirmText = L["Are you sure you want to delete all nodes from this database?"],
						},
						Treasure = {
							order = 5,
							name = L["Treasure"],
							desc = L["Delete Entire Database"],
							type = "execute",
							arg = "Treasure",
							confirm = true,
							confirmText = L["Are you sure you want to delete all nodes from this database?"],
						},
						Woodcutting = {
							order = 5,
							name = L["Woodcutting"],
							desc = L["Delete Entire Database"],
							type = "execute",
							arg = "Woodcutting",
							confirm = true,
							confirmText = L["Are you sure you want to delete all nodes from this database?"],
						},
					},
				},
			},
		},
		desc = {
			order = 0,
			type = "description",
			name = L["Cleanup_Desc"],
		},
		cleanup_range = {
			order = 10,
			name = L["Cleanup radius"],
			type = "group",
			guiInline = true,
			get = function(info)
				return db.cleanupRange[info.arg]
			end,
			set = function(info, v)
				db.cleanupRange[info.arg] = v
			end,
			args = {
				desc = {
					order = 0,
					type = "description",
					name = L["CLEANUP_RADIUS_DESC"],
				},
				Mine = {
					order = 5,
					name = L["Mineral Veins"],
					desc = L["Cleanup radius"],
					type = "range",
					min = 0, max = 30, step = 1,
					arg = "Mining",
				},
				Herb = {
					order = 5,
					name = L["Herb Bushes"],
					desc = L["Cleanup radius"],
					type = "range",
					min = 0, max = 30, step = 1,
					arg = "Herb Gathering",
				},
				Fish = {
					order = 5,
					name = L["Fishes"],
					desc = L["Cleanup radius"],
					type = "range",
					min = 0, max = 30, step = 1,
					arg = "Fishing",
				},
				Gas = {
					order = 5,
					name = L["Gas Clouds"],
					desc = L["Cleanup radius"],
					type = "range",
					min = 0, max = 100, step = 1,
					arg = "Extract Gas",
				},
				Treasure = {
					order = 5,
					name = L["Treasure"],
					desc = L["Cleanup radius"],
					type = "range",
					min = 0, max = 30, step = 1,
					arg = "Treasure",
				},
				Woodcutting = {
					order = 5,
					name = L["Woodcutting"],
					desc = L["Cleanup radius"],
					type = "range",
					min = 0, max = 100, step = 1,
					arg = "Woodcutting",
				}
			},
		},
		dblocking = {
			order = 11,
			name = L["Database Locking"],
			type = "group",
			guiInline = true,
			get = function(info)
				return db.dbLocks[info.arg]
			end,
			set = function(info,v)
				db.dbLocks[info.arg] = v
			end,
			args = {
				desc = {
					order = 0,
					type = "description",
					name = L["DATABASE_LOCKING_DESC"],
				},
				Mine = {
					order = 5,
					name = L["Mineral Veins"],
					desc = L["Database locking"],
					type = "toggle",
					arg = "Mining",
				},
				Herb = {
					order = 5,
					name = L["Herb Bushes"],
					desc = L["Database locking"],
					type = "toggle",
					arg = "Herb Gathering",
				},
				Fish = {
					order = 5,
					name = L["Fishes"],
					desc = L["Database locking"],
					type = "toggle",
					arg = "Fishing",
				},
				Gas = {
					order = 5,
					name = L["Gas Clouds"],
					desc = L["Database locking"],
					type = "toggle",
					arg = "Extract Gas",
				},
				Treasure = {
					order = 5,
					name = L["Treasure"],
					desc = L["Database locking"],
					type = "toggle",
					arg = "Treasure",
				},
				Woodcutting = {
					order = 5,
					name = L["Woodcutting"],
					desc = L["Database locking"],
					type = "toggle",
					arg = "Woodcutting",
				}
			}
		},
	},
}


-- GatherMateData Import config tree
options.args.importing = {
	type = "group",
	name = L["Import Data"],
	order = 10,
	args = {},
}
ImportHelper.db_options = {
	["Merge"] = L["Merge"],
	["Overwrite"] = L["Overwrite"]
}
ImportHelper.db_tables = {
	["Herbs"] = L["Herbalism"],
	["Mines"] = L["Mining"],
	["Gases"] = L["Gas Clouds"],
	["Fish"] = L["Fishing"],
	["Treasure"] = L["Treasure"],
	["Woodcutting"] = L["Woodcutting"],
	["Worldforged"] = L["World Interactable"],
}
ImportHelper.expac_data = {
	["TBC"] = L["The Burning Crusades"],
	["WRATH"] = L["Wrath of the Lich King"],
}
imported["GatherMate2_Data"] = false
options.args.importing = {
	type = "group",
	name = "GatherMate2Data", -- addon name to import from, don't localize
	handler = ImportHelper,
	disabled = function()
		local name, title, notes, enabled, loadable, reason, security = GetAddOnInfo("GatherMate2_Data")
		-- disable if the addon is not enabled, or
		-- disable if there is a reason why it can't be loaded ("MISSING" or "DISABLED")
		return not enabled or (reason ~= nil)
	end,
	args = {
		desc = {
			order = 0,
			type = "description",
			name = L["Importing_Desc"],
		},
		loadType = {
			order = 1,
			name = L["Import Style"],
			desc = L["Merge will add GatherMate2Data to your database. Overwrite will replace your database with the data in GatherMate2Data"],
			type = "select",
			values = ImportHelper.db_options,
			set = "SetImportStyle",
			get = "GetImportStyle",
			arg = "GatherMate2_Data",
		},
		loadDatabase = {
			order = 2,
			name = L["Databases to Import"],
			desc = L["Databases you wish to import"],
			type = "multiselect",
			values = ImportHelper.db_tables,
			set = "SetImportDatabase",
			get = "GetImportDatabase",
			arg = "GatherMate2_Data",
		},
		stylebox = {
			order = 4,
			type = "group",
			name = L["Import Options"],
			inline = true,
			args = {
				loadExpacToggle = {
					order = 4,
					name = L["Expansion Data Only"],
					type = "toggle",
					get = "GetExpacOnly",
					set = "SetExpacOnly",
					arg = "GatherMate2_Data"
				},
				loadExpansion = {
					order = 4,
					name = L["Expansion"],
					desc = L["Only import selected expansion data from WoWhead"],
					type = "select",
					get  = "GetExpac",
					set  = "SetExpac",
					values = ImportHelper.expac_data,
					arg  = "GatherMate2_Data",
				},
				loadAuto = {
					order = 5,
					name = L["Auto Import"],
					desc = L["Automatically import when ever you update your data module, your current import choice will be used."],
					type = "toggle",
					get = "GetAutoImport",
					set = "SetAutoImport",
					arg = "GatherMate2_Data",
				},
			}
		},
		loadData = {
			order = 8,
			name = L["Import GatherMate2Data"],
			desc = L["Load GatherMate2Data and import the data to your database."],
			type = "execute",
			func = function()
				local loaded, reason = LoadAddOn("GatherMate2_Data")
				local GatherMateData = LibStub("AceAddon-3.0"):GetAddon("GatherMate2_Data")
				if loaded then
					local dataVersion = tonumber(GetAddOnMetadata("GatherMate2_Data", "X-Generated-Version"):match("%d+"))
					local filter = nil
					if db.importers["GatherMate2_Data"].expacOnly then
						filter = db.importers["GatherMate2_Data"].expac
					end
					GatherMateData:PerformMerge(db.importers["GatherMate2_Data"].Databases,db.importers["GatherMate2_Data"].Style,filter)
					GatherMateData:CleanupImportData()
					Config:Print(L["GatherMate2Data has been imported."])
					Config:SendMessage("GatherMate2ConfigChanged")
					db["importers"]["GatherMate2_Data"]["lastImport"] = dataVersion
					imported["GatherMate2_Data"] = true
				else
					Config:Print(L["Failed to load GatherMateData due to "]..reason)
				end
			end,
			disabled = function()
				local cm = 0
				if db["importers"]["GatherMate2_Data"].Databases["Mines"] then cm = 1 end
				if db["importers"]["GatherMate2_Data"].Databases["Herbs"] then cm = 1 end
				if db["importers"]["GatherMate2_Data"].Databases["Gases"] then cm = 1 end
				if db["importers"]["GatherMate2_Data"].Databases["Fish"] then cm = 1 end
				if db["importers"]["GatherMate2_Data"].Databases["Treasure"] then cm = 1 end
				if db["importers"]["GatherMate2_Data"].Databases["Woodcutting"] then cm = 1 end
				if db["importers"]["GatherMate2_Data"].Databases["Worldforged"] then cm = 1 end
				return imported["GatherMate2_Data"] or (cm == 0 and not imported["GatherMate2_Data"])
			end,
		}
	},
}

options.args.faq_group = {
	type = "group",
	name = L["FAQ"],
	desc = L["Frequently Asked Questions"],
	order = -1,
	args = {
		header = {
			type = "header",
			name = L["Frequently Asked Questions"],
			order = 0,
		},
		desc = {
			type = "description",
			name = L["FAQ_TEXT"],
			order = 1,
		},
	},
}

local function config_toggle_get(info) return GatherMate.db.profile[info[#info]] end
local function config_toggle_set(info, v) GatherMate.db.profile[info[#info]] = v end

options.args.sharedata = {
	type = "group",
	name = L["Share Data"],
	desc = L["Settings for sharing of Node Data with other players"],
	order = -1,
	args = {
		desc = {
			type = "description",
			name = L["SHARE_TEXT"],
			order = 0,
		},
		ignore = {
			name = L["Ignore Players"],
			type = "group",
			guiInline = true,
			order = 1,
			args = {
				ignored_players = {
					type = "input",
					name = L["Ignored Players - Case Matters"],
					desc = L["Comma seperated list of players you are ignoring node data from.  EG: p1,p2 , p3"],
					width = "full",
					get = function(info)
						local names = ""
						for name, _ in pairs(GatherMate.db.profile.ignored_players) do
							names = names .. name .. ","
						end
						return names
					end,
					set = function(info, value)
						local people = {}
						for person in string.gmatch(value, "([^,]+)") do
							person = string.gsub(person, '%s*', '') -- remove any whitespace
							if person ~= "" then
								people[person] = true
							end
						end
						GatherMate.db.profile.ignored_players = people
					end,
				},
			},
		},
		print = {
			name = L["Print Options"],
			type = "group",
			guiInline = true,
			order = 3,
			args = {
				print_gather = {
					type = "toggle",
					name = L["Your Gathers"],
					desc = L["Print data when you gather a node"],
					order = 4,
					get = config_toggle_get,
					set = config_toggle_set,
				},
				print_guild = {
					type = "toggle",
					name = L["Guild Gathers"],
					desc = L["Print data when you get a node from guild"],
					order = 1,
					get = config_toggle_get,
					set = config_toggle_set,
				},
				print_party = {
					type = "toggle",
					name = L["Party Gathers"],
					desc = L["Print data when you get a node from party"],
					order = 2,
					get = config_toggle_get,
					set = config_toggle_set,
				},
				print_raid = {
					type = "toggle",
					name = L["Raid Gathers"],
					desc = L["Print data when you get a node from raid"],
					order = 3,
					get = config_toggle_get,
					set = config_toggle_set,
				},
			},
		},
		accept = {
			name = L["Accept Nodes"],
			type = "group",
			guiInline = true,
			order = 2,
			args = {
				accept_guild = {
					type = "toggle",
					name = L["Guild Gathers"],
					desc = L["Accept Data from other players in your Guild"],
					order = 1,
					get = config_toggle_get,
					set = config_toggle_set,
				},
				accept_party = {
					type = "toggle",
					name = L["Party Gathers"],
					desc = L["Accept Data from other players in your Party"],
					order = 2,
					get = config_toggle_get,
					set = config_toggle_set,
				},
				accept_raid = {
					type = "toggle",
					name = L["Raid Gathers"],
					desc = L["Accept Data from other players in your Raid"],
					order = 3,
					get = config_toggle_get,
					set = config_toggle_set,
				},
			},
		},
		send = {
			name = L["Send Nodes"],
			type = "group",
			guiInline = true,
			order = 3,
			args = {
				send_guild = {
					type = "toggle",
					name = L["Guild"],
					desc = L["Send Data to other players in your Guild"],
					order = 1,
					get = config_toggle_get,
					set = config_toggle_set,
				},
				send_party = {
					type = "toggle",
					name = L["Party"],
					desc = L["Send Data to other players in your Party"],
					order = 2,
					get = config_toggle_get,
					set = config_toggle_set,
				},
				send_raid = {
					type = "toggle",
					name = L["Raid"],
					desc = L["Send Data to other players in your Raid"],
					order = 3,
					get = config_toggle_get,
					set = config_toggle_set,
				},
			},
		},
	},
}


--[[
	Initialize the Config System
]]

local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

function Config:OnInitialize()
	db = GatherMate.db.profile
	if not db.ignored_players then db.ignored_players = {} end
	if not db.SinkOptions then db.SinkOptions = {} end
    
    -- [[ CUSTOM: Initialize Custom Settings Table ]]
    if not db.customSettings then db.customSettings = {} end
    if not db.minimapIcon then db.minimapIcon = { hide = false } end
    -- [[ CUSTOM: Force Hat Reminder OFF on reload/login ]]
    db.checkHats = false
    
	GatherMate:SetSinkStorage(db.SinkOptions)
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(GatherMate2.db)
	options.args.output = GatherMate:GetSinkAce3OptionsDataTable()

	self.importHelper = ImportHelper
	AceConfig:RegisterOptionsTable("GatherMate2", options)
	self.optionsFrame = LibStub("LibAboutPanel").new(nil, "GatherMate2")
	self.optionsFrame.Display = AceConfigDialog:AddToBlizOptions("GatherMate2", L["Display"], "GatherMate2", "display")
	self.optionsFrame.Database = AceConfigDialog:AddToBlizOptions("GatherMate2", L["Database"], "GatherMate2", "cleanup")
	self.optionsFrame.Import = AceConfigDialog:AddToBlizOptions("GatherMate2", L["Import"], "GatherMate2", "importing")
	self.optionsFrame.FAQ = AceConfigDialog:AddToBlizOptions("GatherMate2", L["FAQ"], "GatherMate2", "faq_group")
	self.optionsFrame.Profiles = AceConfigDialog:AddToBlizOptions("GatherMate2", L["Profiles"], "GatherMate2", "profiles")
	self.optionsFrame.DataShare = AceConfigDialog:AddToBlizOptions("GatherMate2", L["Share Data"], "GatherMate2", "sharedata")
	self.optionsFrame.Output = AceConfigDialog:AddToBlizOptions("GatherMate2", L["Output"], "GatherMate2", "output")
	self:RegisterChatCommand("gathermate", function() AceConfigDialog:Open("GatherMate2") end )
	self:RegisterMessage("GatherMate2ConfigChanged")
	if DataBroker then
		local launcher = DataBroker:NewDataObject("GatherMate2", {
		    type = "launcher",
		    icon = "Interface\\AddOns\\GatherMate2\\Artwork\\Icon.tga",
		    OnClick = function(clickedframe, button) 
                if button == "RightButton" then
                    -- Right-Click: Toggle Icons (Show/Hide Nodes)
                    local db = GatherMate.db.profile
                    db.showMinimap = not db.showMinimap
                    Config:UpdateConfig()
                elseif IsAltKeyDown() and button == "LeftButton" then
                    -- Alt+Left-Click: Toggle Hat Reminder
                    local db = GatherMate.db.profile
                    db.checkHats = not db.checkHats
                    local state = db.checkHats and "|cff00ff00ON|r" or "|cffff0000OFF|r"
                    print("|cff33ff99GatherMate2:|r Hat Reminder is now " .. state)
                else
                    -- Left-Click: Toggle Options Window
                    local ACD = LibStub("AceConfigDialog-3.0")
                    if ACD.OpenFrames["GatherMate2"] then
                        ACD:Close("GatherMate2")
                    else
                        ACD:Open("GatherMate2")
                    end
                end
            end,
            -- [[ CUSTOM: Tooltip for Minimap Icon ]]
            OnTooltipShow = function(tooltip)
                tooltip:AddLine("GatherMate2")
                tooltip:AddLine(" ")
                
                local skills = {
                    { key = "Herb Gathering", name = "Herbalism", icon = "|TInterface\\Icons\\Trade_Herbalism:14|t" },
                    { key = "Mining", name = "Mining", icon = "|TInterface\\Icons\\Trade_Mining:14|t" },
                    { key = "Woodcutting", name = "Woodcutting", icon = "|TInterface\\Icons\\INV_TradeskillItem_03:14|t" },
                    { key = "Treasure", name = "Lockpicking", icon = "|TInterface\\Icons\\Spell_Nature_MoonKey:14|t" },
                }
                
                -- Show Learned Skills
                for _, s in ipairs(skills) do
                    local lvl = GatherMate.skillRank[s.key]
                    if lvl > 0 then
                         tooltip:AddDoubleLine(s.icon .. " " .. s.name, lvl, 1,1,1, 0,1,0)
                    end
                end
                
                -- Shift-Hover Logic
                if IsShiftKeyDown() then
                    tooltip:AddLine(" ")
                    tooltip:AddLine("Skill-up Nodes:", 1, 0.8, 0)
                    local foundAny = false
                    
                    for _, s in ipairs(skills) do
                        local skill = GatherMate.skillRank[s.key]
                        if skill > 0 then
                            local nodes = {}
                            local minHarvestTable = GatherMate.nodeMinHarvest[s.key] or {}
                            
                            for name, id in pairs(GatherMate.nodeIDs[s.key]) do
                                local req = minHarvestTable[id]
                                if req and req > 0 then
                                    local color = GetSkillColor(req, skill)
                                    -- Only list Orange/Yellow
                                    if color == "ff9900" or color == "ffff00" then
                                        table.insert(nodes, { name = name, lvl = req, color = color })
                                    end
                                end
                            end
                            
                            if #nodes > 0 then
                                foundAny = true
                                table.sort(nodes, function(a,b) return a.lvl < b.lvl end)
                                tooltip:AddLine(s.icon .. " " .. s.name)
                                for _, n in ipairs(nodes) do
                                    -- Indent slightly, show name and level
                                    tooltip:AddLine("   |cff" .. n.color .. "(" .. n.lvl .. ") " .. n.name .. "|r")
                                end
                            end
                        end
                    end
                    if not foundAny then
                         tooltip:AddLine("   None", 0.5, 0.5, 0.5)
                    end
                else
                    tooltip:AddLine(" ")
                    tooltip:AddLine("|cffaaaaaaAlt+Left-Click: Toggle Hat Reminder|r")
                    tooltip:AddLine("|cffaaaaaaLeft-Click: Open Options|r")
                    tooltip:AddLine("|cffaaaaaaRight-Click: Toggle Icons|r")
                    tooltip:AddLine("|cffaaaaaaShift-Hover: Show Skill-up Nodes|r")
                end
            end,
		})
        -- [[ CUSTOM: Register Minimap Icon using LibDBIcon ]]
        if DBIcon then
            DBIcon:Register("GatherMate2", launcher, db.minimapIcon)
        end
	end
end

function Config:OnEnable()
	self:CheckAutoImport()
    
    -- Hook for Buff Checking
    self:RegisterEvent("UNIT_AURA", CheckHatBuffs)
    self:RegisterEvent("BAG_UPDATE", CheckHatBuffs)

    -- Login Grace Period Timer (10 seconds to silence login spam)
    local timerFrame = CreateFrame("Frame")
    local totalElapsed = 0
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        totalElapsed = totalElapsed + elapsed
        if totalElapsed > 10 then
            loginGracePeriod = false
            self:SetScript("OnUpdate", nil) -- Stop timer
        end
    end)
end

function Config:UpdateConfig()
	self:SendMessage("GatherMate2ConfigChanged")
    -- [[ CUSTOM: Update Minimap Icon Desaturation ]]
    if DBIcon then
        -- Safe check if button exists before accessing
        local button = _G["LibDBIcon10_GatherMate2"]
        if button and button.icon then
            button.icon:SetDesaturated(not db.showMinimap)
        end
    end
end

function Config:GatherMate2ConfigChanged()
	db = GatherMate.db.profile
end

function Config:CheckAutoImport()
	for k,v in pairs(db.importers) do
		local verline = GetAddOnMetadata(k, "X-Generated-Version")
		if verline and v["autoImport"] then
			local dataVersion = tonumber(verline:match("%d+"))
			if dataVersion and dataVersion > v["lastImport"] then
				local loaded, reason = LoadAddOn(k)
				local addon = LibStub("AceAddon-3.0"):GetAddon(k)
				if loaded then
					local filter = nil
					if v.expacOnly then
						filter = v.expac
					end
					addon:PerformMerge(v.Databases,v.Style,filter)
					addon:CleanupImportData()
					imported[k] = true
					Config:SendMessage("GatherMate2ConfigChanged")
					v["lastImport"] = dataVersion
					Config:Print(L["Auto import complete for addon "]..k)
				end
			end
		end
	end
end

-- Allows an external import module to insert their aceopttable into the Importing tree
-- returns a reference to the saved variables state for the addon
function Config:RegisterImportModule(moduleName, optionsTable)
	options.args.importing.args[moduleName] = optionsTable
	return db.importers[moduleName]
end
-- Allows an external module to insert their aceopttable
function Config:RegisterModule(moduleName, optionsTable)
	options.args[moduleName] = optionsTable
	self.optionsFrame["moduleName"] = AceConfigDialog:AddToBlizOptions("GatherMate2", moduleName, "GatherMate2", moduleName)
end