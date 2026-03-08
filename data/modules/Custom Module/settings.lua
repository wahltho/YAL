local P = {}
settings = P -- package name

local def = require("definitions")

local settingPath = def.XPOUTPUTPATH .. "preferences" .. def.OSSEPARATOR .. def.APPNAMEPREFIX .. ".prf"
local settingFormat = 'info'


local settingsDefinition = {
    [def.CONFIGVOICEREADBACK] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOFUNCTIONS] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGFMCAUTOMATION] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGHEADINGSYNCINTERVAL] = { dvalue = 0 , type = "number", min = 0, max = 9999 },
    [def.CONFIGVOICEADVICEONLY] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGVOICEADVICEREPEATSKIP] = { dvalue = 1 , type = "number", min = 0, max = 10 },
    [def.CONFIGVOICEADVICEMAXREPEATS] = { dvalue = 0 , type = "number", min = 0, max = 99 },
    [def.CONFIGTRIMADVICEPOPUP] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOFUELING] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGHOPPIEID] = { dvalue = "" , type = "string", minLen = 0, maxLen = 16 },
    [def.CONFIGCUSTOMAPPROACHCALC] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGBPBINTEGRATION] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGYANSHINTEGRATION] = { dvalue = 0 , type = "number", min = 0, max = 1 },

    [def.CONFIGAUTOANTIICE] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOWIPER] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOBARO] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOCENTERTANKHANDLING] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOFLAPS] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOCHOCKSPB] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGUSEGROUNDPOWER] = { dvalue = 1 , type = "number", min = 0, max = 1 },

    [def.CONFIGSPDRESTR250] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGVREF30SET] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGLOWEAIRSPACEALT] = { dvalue = 10000 , type = "number", min = 1000, max = 20000 },
    [def.CONFIGBANKANGLEMAX] = { dvalue = 4 , type = "number", min = 1, max = 4 },
    [def.CONFIGPACKSRESTOREALT] = { dvalue = 3000 , type = "number", min = 0, max = 20000 },
    [def.CONFIGLOWERDU] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGTRANSPONDER] = { dvalue = 2000 , type = "number", min = 0, max = 7777 },
    [def.CONFIGGEARDOWNFLAPS] = { dvalue = 5 , type = "number", min = 5, max = 15 },
    
    [def.CONFIGVIEWCHANGES] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGVIEWMAINPANEL] = { dvalue = 1 , type = "number", min = 0, max = 20 },
    [def.CONFIGVIEWPEDESTAL] = { dvalue = 3 , type = "number", min = 0, max = 20 },
    [def.CONFIGVIEWOVERHEADPANEL] = { dvalue = 4 , type = "number", min = 0, max = 20 },
    [def.CONFIGVIEWFMS] = { dvalue = 5 , type = "number", min = 0, max = 20 },
    [def.CONFIGVIEWTHROTTLE] = { dvalue = 7 , type = "number", min = 0, max = 20 },
    [def.CONFIGVIEWUPPEROVERHEADPANEL] = { dvalue = 10 , type = "number", min = 0, max = 20 },

    [def.CONFIGBRIGHTMAINPANEL] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGBRIGHTOVERHEAD] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGBRIGHTPEDESTRAL] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGGENBRIGHTBACKGROUND] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGGENBRIGHTAFDSFLOOD] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGGENBRIGHTPEDESTRALFLOOD] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGINSTRBRIGHTOUTBDDU] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGINSTRBRIGHTINBDDU] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGINSTRBRIGHTUPPERDU] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGINSTRBRIGHTLOWDU] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGINSTRBRIGHTINBDDUS] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },
    [def.CONFIGINSTRBRIGHTLOWDUS] = { dvalue = 0.5 , type = "number", min = 0, max = 1 },

    [def.CONFIGWAKEOVERRIDE] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGRUNWAYFRICTIONCLAMP] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGTODPAUSEQUITTIME] = { dvalue = 1800 , type = "number", min = 0, max = 9999 },
    [def.CONFIGSAVETIME] = { dvalue = 300 , type = "number", min = 0, max = 9999 },
    [def.CONFIGSAVENUMBER] = { dvalue = "1" , type = "string", minLen = 1, maxLen = 5 },
    [def.CONFIGSAVELAST] = { dvalue = 1 , type = "number", min = 1, max = 8 },
    [def.CONFIGIGNOREALLBRIGHTHNESSSETTINGS] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGHIDEEFBS] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGSHOWBETAUPDATES] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOUPDATECHECK] = { dvalue = 1 , type = "number", min = 0, max = 1 },
    [def.CONFIGJITLUAON] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGZIBOISMODDED] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGDEBUGOVERLAY] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGTAXIMAPORIENT] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGTAXIMAPFONTSIZE] = { dvalue = 12 , type = "number", min = 8, max = 24 },
    [def.CONFIGTAXIMAPZOOM] = { dvalue = 1.0 , type = "number", min = 0.2, max = 5 },
    [def.CONFIGAUTOTAXIGUIDANCE] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGVISUALTAXIGUIDANCE] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTOTAXIING] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGHOPPIEVOICE] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGAUTORESTARTDEV] = { dvalue = 0 , type = "number", min = 0, max = 1 },
    [def.CONFIGTRIMADVICEPOPUPX] = { dvalue = -1 , type = "number", min = -10000, max = 20000 },
    [def.CONFIGTRIMADVICEPOPUPY] = { dvalue = -1 , type = "number", min = -10000, max = 20000 },

}   

local defaultSettings = {}
for k, v in pairs(settingsDefinition) do
    defaultSettings[k] = settingsDefinition[k].dvalue
end

local function normalizeSaveNumber(val)
    if val == nil then
        return nil
    end
    if type(val) == "number" then
        local num = math.floor(val)
        if num < 1 or num > 8 then
            return nil
        end
        return tostring(num)
    end
    if type(val) ~= "string" then
        return nil
    end
    local s = val:gsub("%s+", "")
    if s == "" then
        return nil
    end
    local a, b = s:match("^(%d+)%-(%d+)$")
    if a and b then
        local n1 = tonumber(a)
        local n2 = tonumber(b)
        if not n1 or not n2 then
            return nil
        end
        if n1 < 1 or n1 > 8 or n2 < 1 or n2 > 8 then
            return nil
        end
        if n1 > n2 then
            n1, n2 = n2, n1
        end
        return tostring(n1) .. "-" .. tostring(n2)
    end
    local n = tonumber(s)
    if n and n >= 1 and n <= 8 then
        return tostring(math.floor(n))
    end
    return nil
end

 

local function checkSettings(tableTocheck)

    if tableTocheck == nil then
        sasl.logDebug("No settings found, returning default")
        return defaultSettings, true
    end
    local result = false
    for k, v in pairs(settingsDefinition) do
        local defn = settingsDefinition[k]
        if k == def.CONFIGSAVENUMBER then
            local cur = tableTocheck[k]
            if type(cur) == "number" then
                local num = math.floor(cur + 0.00001)
                if num < 1 or num > 8 or math.abs(cur - num) > 0.0001 then
                    sasl.logDebug("key: " .. k .. " missing or incorrect, setting value to default: " .. tostring(defn.dvalue))
                    tableTocheck[k] = defn.dvalue
                    result = true
                end
            else
                local normalized = normalizeSaveNumber(cur)
                if not normalized then
                    sasl.logDebug("key: " .. k .. " missing or incorrect, setting value to default: " .. tostring(defn.dvalue))
                    tableTocheck[k] = defn.dvalue
                    result = true
                elseif cur ~= normalized then
                    tableTocheck[k] = normalized
                    result = true
                end
            end
        elseif defn.type == "string" then
            local val = tableTocheck[k]
            if type(val) ~= "string" then
                sasl.logDebug("key: " .. k .. " missing or incorrect, setting value to default: " .. tostring(defn.dvalue))
                tableTocheck[k] = defn.dvalue
                result = true
            else
                local len = #val
                if (defn.minLen and len < defn.minLen) or (defn.maxLen and len > defn.maxLen) then
                    sasl.logDebug("key: " .. k .. " missing or incorrect, setting value to default: " .. tostring(defn.dvalue))
                    tableTocheck[k] = defn.dvalue
                    result = true
                end
            end
        else
            if tableTocheck[k] == nil or type(tableTocheck[k]) ~= defn.type or tableTocheck[k] < defn.min 
                or tableTocheck[k] > defn.max then
                     sasl.logDebug("key: " .. k .. " missing or incorrect, setting value to default: " .. tostring(defn.dvalue))
                     tableTocheck[k] = defn.dvalue
                     result = true
            end
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


function P.getSettingNumber(key, default)
    local tbl = P.appSettings
    if not tbl then
        return default
    end
    local val = tbl[key]
    if val == nil then
        return default
    end
    val = tonumber(val)
    if val == nil then
        return default
    end
    return val
end


P.appSettings = P.getSettings()
P.newSettingsAvailable = true
return settings
