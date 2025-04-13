local P = {}
settings = P -- package name

require("definitions")

local settingPath = definitions.XPOUTPUTPATH .. "preferences" .. definitions.OSSEPARATOR .. definitions.APPNAMEPREFIX .. ".prf"
local settingFormat = 'info'


local settingsDefinition = {
    VOICEREADBACK = { dvalue = 1 , type = "number", min = 0, max = 1 },
    AUTOFUNCTIONS = { dvalue = 1 , type = "number", min = 0, max = 1 },
    VOICEADVICEONLY = { dvalue = 1 , type = "number", min = 0, max = 1 },

    AUTOANTIICE = { dvalue = 1 , type = "number", min = 0, max = 1 },
    AUTOWIPER = { dvalue = 1 , type = "number", min = 0, max = 1 },
    AUTOBARO = { dvalue = 1 , type = "number", min = 0, max = 1 },
    AUTOCENTERTANKHANDLING = { dvalue = 1 , type = "number", min = 0, max = 1 },
    AUTOFLAPS = { dvalue = 1 , type = "number", min = 0, max = 1 },
    USEGROUNDPOWER = { dvalue = 1 , type = "number", min = 0, max = 1 },

    SPEEDRESTR250 = { dvalue = 1 , type = "number", min = 0, max = 1 },
    VREF30 = { dvalue = 1 , type = "number", min = 0, max = 1 },
    LOWERAIRSPACEALT = { dvalue = 10000 , type = "number", min = 1000, max = 20000 },
    BANKANGLEMAX = { dvalue = 4 , type = "number", min = 1, max = 4 },
    LOWERDU = { dvalue = 1 , type = "number", min = 0, max = 1 },
    TRANSPONDERCODE = { dvalue = 2000 , type = "number", min = 0, max = 7777 },
    GEARDOWNFLAPS = { dvalue = 5 , type = "number", min = 5, max = 15 },
    
    VIEWCHANGES = { dvalue = 1 , type = "number", min = 0, max = 1 },
    VIEWMAINPANEL = { dvalue = 1 , type = "number", min = 0, max = 20 },
    VIEWPEDESTAL = { dvalue = 3 , type = "number", min = 0, max = 20 },
    VIEWOVERHEADPANEL = { dvalue = 4 , type = "number", min = 0, max = 20 },
    VIEWFMS = { dvalue = 5 , type = "number", min = 0, max = 20 },
    VIEWTHROTTLE = { dvalue = 7 , type = "number", min = 0, max = 20 },
    VIEWUPPEROVERHEADPANEL = { dvalue = 10 , type = "number", min = 0, max = 20 },

    BRIGHTMAINPANEL = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    BRIGHTOVERHEAD = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    BRIGHTPEDESTRAL = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    GENBRIGHTBACKGROUND = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    GENBRIGHTAFDSFLOOD = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    GENBRIGHTPEDESTRALFLOOD = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    INSTRBRIGHTOUTBDDU = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    INSTRBRIGHTINBDDU = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    INSTRBRIGHTUPPERDU = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    INSTRBRIGHTLOWDU = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    INSTRBRIGHTINBDDUS = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    INSTRBRIGHTLOWDUS = { dvalue = 0.5 , type = "number", min = 0, max = 1 },

    WAKEOVERRIDE = { dvalue = 1 , type = "number", min = 0, max = 1 },
    TODPAUSEQUITTIME = { dvalue = 1800 , type = "number", min = 0, max = 9999 },
    SAVETIME = { dvalue = 300 , type = "number", min = 0, max = 9999 },
    SAVENUMBER = { dvalue = 1 , type = "number", min = 1, max = 8 },
    IGNOREALLBRIGHTHNESSSETTINGS = { dvalue = 0 , type = "number", min = 0, max = 1 },
    HIDEFBS = { dvalue = 1 , type = "number", min = 0, max = 1 },

} 

local defaultSettings = {}
for k, v in pairs(settingsDefinition) do
    defaultSettings[k] = settingsDefinition[k].dvalue
end

 


-- return tableTocheck, flag
-- if flag is true  tableTocheck is evently corrected if key are missing or invalid or eqaul to defaultSettings 
-- 
local function checkSettings(tableTocheck)

    if tableTocheck == nil then
        sasl.logDebug("No settings found, returning default")
        return defaultSettings, true
    end
    local result = false
    for k, v in pairs(settingsDefinition) do
        if tableTocheck[k] == nil or tableTocheck[k] < settingsDefinition[k].min 
            or tableTocheck[k] > settingsDefinition[k].max or type(tableTocheck[k]) ~= settingsDefinition[k].type then
                sasl.logDebug("key: " .. k .. " missing or incorrect, setting value to default: " .. settingsDefinition[k].dvalue)
                tableTocheck[k] = settingsDefinition[k].dvalue
                result = true
        end
    end
    return tableTocheck, result
end

function P.writeSettings(currentSetting)
    if sasl.writeConfig(settingPath, settingFormat, currentSetting) == false then
        sasl.logWarning("Unable to write settings to disk")
    end
    P.newSettingsAvailable = true
end

function P.getSettings()
    P.newSettingsAvailable = false
    local lSettings = nil
    pcall(function()
        lSettings = sasl.readConfig(settingPath, settingFormat)
    end
    )
    local currentSetting, result = checkSettings(lSettings)
    if result == true then
        P.writeSettings(currentSetting)
    end
    
    return currentSetting
end



P.appSettings = P.getSettings()
P.newSettingsAvailable = true
return settings
