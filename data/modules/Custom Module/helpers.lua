local P = {}
helpers = P -- package name

local def = require("definitions")

function P.mmrBuildDigits(value)
    local val = tonumber(value) or 0
    val = math.floor(math.abs(val))
    local digits = {}
    for i = 1, 5 do
        digits[i] = val % 10
        val = math.floor(val / 10)
    end
    return digits
end

function P.mmrCopyActToStby(side)
    local yal = _G.yal
    if not yal or not yal.mmrinstalled or get(yal.mmrinstalled) ~= def.ON then
        return
    end
    local actMode, actValue, stbyModeRef
    local stbyArrILS, stbyArrILS2, stbyArrGLS, stbyArrVOR, stbyArrVOR2, stbyArrGeneric
    if side == def.MMRCAPTAIN then
        actMode = get(yal.mmrcptactmode)
        actValue = get(yal.mmrcptactvalue)
        stbyModeRef = yal.mmrcptstdbymode
        stbyArrILS = yal.mmrcptilsstbyvalue
        stbyArrILS2 = yal.mmrcptilsstbyvalue2
        stbyArrGLS = yal.mmrcptglsstbyvalue
        stbyArrVOR = yal.mmrcptvorstbyvalue
        stbyArrVOR2 = yal.mmrcptvorstbyvalue2
        stbyArrGeneric = yal.mmrcptstbyvalue
    else
        actMode = get(yal.mmrfoactmode)
        actValue = get(yal.mmrfoactvalue)
        stbyModeRef = yal.mmrfostdbymode
        stbyArrILS = yal.mmrfoilsstbyvalue
        stbyArrILS2 = yal.mmrfoilsstbyvalue2
        stbyArrGLS = yal.mmrfoglsstbyvalue
        stbyArrVOR = yal.mmrfovorstbyvalue
        stbyArrVOR2 = yal.mmrfovorstbyvalue2
        stbyArrGeneric = yal.mmrfostbyvalue
    end
    if not actMode or not stbyModeRef then
        return
    end
    set(stbyModeRef, actMode)
    local digits = P.mmrBuildDigits(actValue)
    if stbyArrGeneric then set(stbyArrGeneric, digits) end
    if actMode == def.MMRILS or actMode == def.MMRLOC then
        if stbyArrILS then set(stbyArrILS, digits) end
        if stbyArrILS2 then set(stbyArrILS2, digits) end
    elseif actMode == def.MMRGLS or actMode == def.MMRLPV then
        if stbyArrGLS then set(stbyArrGLS, digits) end
    else
        if stbyArrVOR then set(stbyArrVOR, digits) end
        if stbyArrVOR2 then set(stbyArrVOR2, digits) end
    end
end

local function parse_version_string(str)
    str = tostring(str or "")
    str = str:match("^%s*(.-)%s*$") or ""
    local major, minor, rest = str:match("^(%d+)%s*%.%s*(%d+)%s*(.*)$")
    if not major or not minor then
        return { valid = false }
    end
    local patch = 0
    local suffix = ""
    rest = rest or ""
    if rest ~= "" then
        local patchPart, suffixPart = rest:match("^%.%s*(%d+)%s*(.*)$")
        if patchPart then
            patch = tonumber(patchPart) or 0
            suffix = suffixPart or ""
        else
            suffix = rest
        end
    end
    suffix = suffix:match("^%s*(.-)%s*$") or ""
    local label, num = suffix:match("^([%a%-]+)([%d]*)")
    label = (label or ""):lower()
    local prereleaseType = "release"
    if label ~= "" then
        if label == "alpha" or label == "a" then
            prereleaseType = "alpha"
        elseif label == "beta" or label == "b" then
            prereleaseType = "beta"
        elseif label == "rc" then
            prereleaseType = "rc"
        else
            prereleaseType = "prerelease"
        end
    elseif suffix ~= "" then
        prereleaseType = "prerelease"
    end
    local prereleaseNum = tonumber(num) or 0
    return {
        valid = true,
        major = tonumber(major) or 0,
        minor = tonumber(minor) or 0,
        patch = patch,
        prereleaseType = prereleaseType,
        prereleaseNum = prereleaseNum,
    }
end

local function is_version_newer(newVersion, currentVersion)
    local orderMap = {
        alpha = 0,
        prerelease = 0,
        beta = 1,
        rc = 2,
        release = 3
    }
    local newParsed = parse_version_string(newVersion)
    local curParsed = parse_version_string(currentVersion)
    if not newParsed.valid then
        return false
    end
    if not curParsed.valid then
        return true
    end
    if newParsed.major ~= curParsed.major then
        return newParsed.major > curParsed.major
    end
    if newParsed.minor ~= curParsed.minor then
        return newParsed.minor > curParsed.minor
    end
    if newParsed.patch ~= curParsed.patch then
        return newParsed.patch > curParsed.patch
    end
    local newOrder = orderMap[newParsed.prereleaseType] or 0
    local curOrder = orderMap[curParsed.prereleaseType] or 0
    if newOrder ~= curOrder then
        return newOrder > curOrder
    end
    if newOrder < 3 then
        return newParsed.prereleaseNum > curParsed.prereleaseNum
    end
    return false
end

P.cifpCache = P.cifpCache or {}

local ffi = require("ffi")
local xplm_lib = {
    Linux = "Resources/plugins/XPLM_64.so",
    Windows = "XPLM_64",
    OSX = "Resources/plugins/XPLM.framework/XPLM"
}
local xplm = ffi.load(xplm_lib[ffi.os])

ffi.cdef [[
    void XPLMSpeakString(char *);
    ]]

--------------------------------------------------------------------------------------------------------------
local acf_tailnum = globalProperty("sim/aircraft/view/acf_tailnum")
local acf_relative_path = globalProperty("sim/aircraft/view/acf_relative_path")
local onground_any = globalProperty("sim/flightmodel/failures/onground_any")
local parking_brake_pos = globalProperty("laminar/B738/parking_brake_pos")
local parking_brake_ratio = globalProperty("sim/cockpit2/controls/parking_brake_ratio")
local pilots_head_x = globalProperty("sim/graphics/view/pilots_head_x")
local pilots_head_y = globalProperty("sim/graphics/view/pilots_head_y")
local pilots_head_z = globalProperty("sim/graphics/view/pilots_head_z")
local pilots_head_psi = globalProperty("sim/graphics/view/pilots_head_psi")
local pilots_head_the = globalProperty("sim/graphics/view/pilots_head_the")
local pilots_head_phi = globalProperty("sim/graphics/view/pilots_head_phi")
local tobii_eq = globalProperty("sim/graphics/view/eq_tobii_eyetracker")


P.xpVersion = sasl.getXPVersion()
P.isXp11 = (P.xpVersion < 12000)
P.isXp12 = (P.xpVersion >= 12000 and P.xpVersion < 13000)

--------------------------------------------------------------------------------------------------------------
function P.isZibo()
    local signature = "zibomod.by.Zibo"
    local pluginID = sasl.findPluginBySignature(signature)
    if pluginID == NO_PLUGIN_ID then
        return false
    end

    local tailnum = get(acf_tailnum)
    if type(tailnum) == "string" then
        if (string.sub(tailnum, 1, 5) == "ZB738")
            or (string.sub(tailnum, 1, 4) == "B736")
            or (string.sub(tailnum, 1, 4) == "B737")
            or (string.sub(tailnum, 1, 4) == "B738")
            or (string.sub(tailnum, 1, 4) == "738")
            or (string.sub(tailnum, 1, 4) == "B739") then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------------------------------------
local zibo_failure_categories = {
    "electric",
    "hydraulic",
    "system",
    "pressurisation",
    "engine"
}

P.ziboFailureDefs = P.ziboFailureDefs or {
    electric = {
        [0] = "AC Transfer Bus 1",
        [1] = "AC Transfer Bus 2",
        [2] = "AC Main Bus 1",
        [3] = "AC Main Bus 2",
        [4] = "AC Standby Bus",
        [5] = "AC Ground Service Bus 1",
        [6] = "AC Ground Service Bus 2",
        [7] = "DC Hot Battery Bus",
        [8] = "DC Switched Hot Battery Bus",
        [9] = "DC Battery Bus",
        [10] = "DC Bus 1",
        [11] = "DC Bus 2",
        [12] = "DC Ground Service Bus",
        [13] = "DC Standby Bus",
        [14] = "TR1 unit",
        [15] = "TR2 unit",
        [16] = "TR3 unit",
        [17] = "IDG1 / Engine Generator 1",
        [18] = "IDG2 / Engine Generator 2",
        [19] = "APU Generator",
        [20] = "BPCU",
        [21] = "Relay BTB1",
        [22] = "Relay BTB2",
        [23] = "Relay TRU3"
    },
    hydraulic = {
        [0] = "System A malfunction",
        [1] = "System B malfunction",
        [2] = "System Standby malfunction",
        [3] = "System A leak",
        [4] = "System B leak"
    },
    system = {
        [0] = "Autoland Land2",
        [1] = "Autoland Land3",
        [2] = "GPS signal (jamming)",
        [3] = "GPS L",
        [4] = "GPS R"
    },
    pressurisation = {
        [0] = "Rapid depressurization",
        [1] = "Slow depressurization",
        [2] = "Outflow valve",
        [3] = "L Pack valve",
        [4] = "R Pack valve",
        [5] = "Isolation valve",
        [6] = "APU bleed valve",
        [7] = "Eng1 bleed valve",
        [8] = "Eng2 bleed valve",
        [9] = "Primary pressurization unit",
        [10] = "Alternate pressurization unit",
        [11] = "Eng1 high stage valve",
        [12] = "Eng2 high stage valve",
        [13] = "Eng1 precooler valve",
        [14] = "Eng2 precooler valve",
        [15] = "APU pressurization"
    },
    engine = {
        [0] = "L Engine fire",
        [1] = "R Engine fire",
        [2] = "L Engine flameout",
        [3] = "R Engine flameout",
        [4] = "L Engine damage",
        [5] = "R Engine damage",
        [6] = "L Engine separate",
        [7] = "R Engine separate",
        [8] = "L Engine generator",
        [9] = "R Engine generator",
        [10] = "L Engine oil pump",
        [11] = "R Engine oil pump",
        [12] = "L Engine oil qty",
        [13] = "R Engine oil qty",
        [14] = "EEC1 Flight data",
        [15] = "EEC2 Flight data",
        [16] = "EEC1 Main unit",
        [17] = "EEC2 Main unit",
        [18] = "APU fire",
        [19] = "APU starting/running",
        [20] = "APU overspeed",
        [21] = "APU low oil quantity",
        [22] = "APU low oil pressure"
    }
}

local function get_zibo_failure_dr(category, index)
    if not P.isZibo() then
        return nil
    end
    if type(category) ~= "string" then
        return nil
    end
    if type(index) ~= "number" or index < 0 or index ~= math.floor(index) then
        return nil
    end

    P._ziboFailureDr = P._ziboFailureDr or {}
    local cat = P._ziboFailureDr[category]
    if not cat then
        cat = {}
        P._ziboFailureDr[category] = cat
    end

    local dr_index = index + 1 -- SASL uses 1-based array element access
    local dr = cat[dr_index]
    if not dr then
        local ok, new_dr = pcall(globalPropertyfae, "laminar/B738/failure/" .. category, dr_index)
        if not ok then
            return nil
        end
        dr = new_dr
        cat[dr_index] = dr
    end
    return dr
end

function P.getZiboFailureValue(category, index)
    local dr = get_zibo_failure_dr(category, index)
    if not dr then
        return nil
    end
    return get(dr)
end

function P.isZiboFailureActive(category, index)
    local value = P.getZiboFailureValue(category, index)
    return value == 1
end

function P.getZiboFailureName(category, index)
    local cat = P.ziboFailureDefs and P.ziboFailureDefs[category]
    if not cat then
        return nil
    end
    return cat[index]
end

function P.getZiboFailureCategories()
    return zibo_failure_categories
end

--------------------------------------------------------------------------------------------------------------
function P.logInfoTS(message)
    local timestamp = string.format("[%s]", os.date("%H:%M:%S"))
    sasl.logInfo(string.format("%s %s", timestamp, tostring(message)))
end

local function get_flightstate()
    if not P._flightstate_dr then
        local ok, dr = pcall(globalProperty, "YAL/state/flightstate")
        if ok then
            P._flightstate_dr = dr
        else
            return nil
        end
    end
    return get(P._flightstate_dr)
end

local function views_change_allowed()
    local on_ground = get(onground_any) == def.ON
    local park_set = (get(parking_brake_pos) == def.ON) or (get(parking_brake_ratio) >= 0.9)
    local state = get_flightstate()
    return on_ground and park_set and (state == def.FLIGHTSTATEPREFLIGHT)
end

--------------------------------------------------------------------------------------------------------------
function P.checkForUpdate(showBeta)
    local url = def.YALGITHUBURL
    if showBeta and def.YALBETAGITHUBURL and def.YALBETAGITHUBURL ~= "" then
        url = def.YALBETAGITHUBURL
    end
    sasl.logDebug(string.format("Checking for %s updates via %s", showBeta and "beta" or "stable", url))
    local updateAvailable = false
    local newVersion = ""
    local downloadResult, contents = sasl.net.downloadFileContentsSync(url)
    if downloadResult then -- ... process data
        newVersion = helpers.cleanString(contents, true)
        local currentVersion = tostring(def.VERSION or "")
        sasl.logDebug(string.format("Current version: %s, available version %s", currentVersion, newVersion))
        if is_version_newer(newVersion, currentVersion) then
            updateAvailable = true
            P.logInfoTS(string.format("New YAL version available v%s", newVersion))
        else
            P.logInfoTS("YAL is up to date, no new version available")
        end
    else
        P.logInfoTS("Check for Update FAILED")
    end
    return updateAvailable, newVersion
end

local function parse_zibo_version_triplet(text)
    local s = tostring(text or "")
    local major, minor, patch = s:match("(%d+)%.(%d+)%.(%d+)")
    if major then
        return {
            major = tonumber(major) or 0,
            minor = tonumber(minor) or 0,
            patch = tonumber(patch) or 0,
        }
    end
    major, minor = s:match("(%d+)%.(%d+)")
    if major then
        return {
            major = tonumber(major) or 0,
            minor = tonumber(minor) or 0,
            patch = 0,
        }
    end
    return nil
end

local function compare_zibo_triplet(a, b)
    if not a and not b then
        return 0
    end
    if not a then
        return -1
    end
    if not b then
        return 1
    end
    if a.major ~= b.major then
        return (a.major > b.major) and 1 or -1
    end
    if a.minor ~= b.minor then
        return (a.minor > b.minor) and 1 or -1
    end
    if a.patch ~= b.patch then
        return (a.patch > b.patch) and 1 or -1
    end
    return 0
end

local function format_zibo_triplet(v)
    if not v then
        return ""
    end
    return string.format("%d.%02d.%02d", v.major or 0, v.minor or 0, v.patch or 0)
end

local function parse_zibo_feed_latest(feed_xml)
    local best = nil
    for title in string.gmatch(tostring(feed_xml or ""), "<title>([^<]+)</title>") do
        local a, b, c = title:match("B738X_XP%d+_(%d+)_(%d+)_(%d+)%.zip")
        if not a then
            a, b, c = title:match("B738X_(%d+)_(%d+)_(%d+)%.zip")
        end
        if not a then
            a, b = title:match("B737%-800X_XP%d+_(%d+)_(%d+)_full%.zip")
            c = "0"
        end
        if not a then
            a, b = title:match("B737%-800X_(%d+)_(%d+)_full%.zip")
            c = "0"
        end
        if a then
            local v = {
                major = tonumber(a) or 0,
                minor = tonumber(b) or 0,
                patch = tonumber(c) or 0,
                title = title,
            }
            if (not best) or compare_zibo_triplet(v, best) > 0 then
                best = v
            end
        end
    end
    return best
end

function P.checkForZiboUpdate(localReleaseText)
    local localVersion = parse_zibo_version_triplet(localReleaseText)
    local localVersionText = format_zibo_triplet(localVersion)
    local downloadResult, contents = sasl.net.downloadFileContentsSync(def.ZIBOUPDATEFEEDURL)
    if not downloadResult or not contents or contents == "" then
        P.logInfoTS("Check for Zibo Update FAILED")
        return false, "", localVersionText
    end
    local latest = parse_zibo_feed_latest(contents)
    if not latest then
        P.logInfoTS("Check for Zibo Update FAILED (no version in feed)")
        return false, "", localVersionText
    end
    local latestText = format_zibo_triplet(latest)
    if not localVersion then
        P.logInfoTS("Check for Zibo Update skipped (local release not parseable)")
        return false, latestText, localVersionText
    end
    local updateAvailable = compare_zibo_triplet(latest, localVersion) > 0
    if updateAvailable then
        P.logInfoTS(string.format("New Zibo version available v%s (installed v%s)", latestText, localVersionText))
    else
        P.logInfoTS(string.format("Zibo is up to date (installed v%s, latest v%s)", localVersionText, latestText))
    end
    return updateAvailable, latestText, localVersionText
end

-------------------------------------------------------------------------------------------------------------- 
function P.get(dataref)
return get(globalProperty(dataref))
end    

function P.command_once(cmd)
    local cmdId = sasl.findCommand(cmd)
    if cmdId then
        sasl.commandOnce(cmdId)
    else
        sasl.logWarning("Command not found: " .. tostring(cmd))
    end
end

function P.command_begin(cmd)
    local cmdId = sasl.findCommand(cmd) 
    sasl.commandBegin(cmdId)
end

function P.command_end(cmd)
    local cmdId = sasl.findCommand(cmd) 
    sasl.commandEnd(cmdId)
end

--------------------------------------------------------------------------------------------------------------
function P.cp_file(source, destination)
    local inp = assert(io.open(source, "rb"))
    local out = assert(io.open(destination, "wb"))
    local data = inp:read("*all")
    out:write(data)
    out:close()
    inp:close()
end

--------------------------------------------------------------------------------------------------------------
function P.format_thousand(v)
    local s = string.format("%6d", math.floor(v))
    local pos = string.len(s) % 3
    if pos == 0 then
        pos = 3
    end
    return string.sub(s, 1, pos) .. string.gsub(string.sub(s, pos + 1), "(...)", " %1")
end

--------------------------------------------------------------------------------------------------------------
function P.timeConvert(seconds, sep)
    local seconds = tonumber(seconds)

    if seconds <= 0 then
        return "no data";
    else
        return string.format("%2d%s%02d", math.floor(seconds / 3600), sep, math.floor(seconds / 60) % 60)
    end
end

--------------------------------------------------------------------------------------------------------------
function P.cleanString(text, noSpace)
    local newText = ""
    local loopSkip = false

    for i = 1, string.len(text), 1 do
        -- ugly filtering
        if string.byte(string.sub(text, i, i)) >= 32 then
            newText = newText .. string.sub(text, i, i)
            loopSkip = false
        else
            if not loopSkip then
                newText = newText .. " "
            end
            loopSkip = true
        end
    end

    if noSpace then
        newText = string.gsub(newText, " ", "")
    end

    return newText
end

--------------------------------------------------------------------------------------------------------------
function P.ifnull(text, sub)
    if type(text) ~= 'string'  then
        return sub
    end
    return text
end

--------------------------------------------------------------------------------------------------------------
function P.trimInnerSpace(text)
    local newText = ""
    local loopSkip = false

    for i = 1, string.len(text), 1 do
        -- ugly filtering
        if string.byte(string.sub(text, i, i)) > 32 then
            newText = newText .. string.sub(text, i, i)
            loopSkip = false
        else
            if not loopSkip then
                newText = newText .. " "
            end
            loopSkip = true
        end
    end

    return newText
end

--------------------------------------------------------------------------------------------------------------
local function normalize_fmc_text(str)
    if type(str) ~= "string" then return "" end
    local trimmed = str:gsub("^%s+", ""):gsub("%s+$", "")
    return trimmed:gsub("%s+", " ")
end

function P.getFMCHeader(lineDataref)
    local raw = P.get(lineDataref or "laminar/B738/fmc1/Line00_L") or ""
    return normalize_fmc_text(raw), raw
end

function P.fmcHeaderContains(expected, lineDataref)
    local header = select(1, P.getFMCHeader(lineDataref))
    if expected ~= nil and expected ~= "" then
        sasl.logDebug(string.format("FMC Header check for '%s': '%s'", expected, header))
    else
        sasl.logDebug(string.format("FMC Header fetched: '%s'", header))
    end
    if expected == nil or expected == "" then
        return header
    end
    return header:upper():find(expected:upper(), 1, true) ~= nil
end

--------------------------------------------------------------------------------------------------------------
function P.splitText(text, tabSize, maxColumn)

    local tab = ""
    local current_pos = 1
    local current_length = 0
    local sub_string = ""
    local split = {}

    for i = 1, tabSize, 1 do
        tab = tab .. " "
    end

    for i = 1, #text, 1 do
        if string.sub(text, i, i) == " " and current_length > maxColumn then
            sub_string = string.sub(text, current_pos, i - 1)
            if #split > 0 then
                sub_string = tab .. sub_string
            end
            table.insert(split, sub_string)
            current_pos = i + 1
            current_length = 0
        end
        current_length = current_length + 1
    end

    sub_string = string.sub(text, current_pos, #text)
    if #split > 0 then
        sub_string = tab .. sub_string
    end
    if #sub_string > 0 then
        table.insert(split, sub_string)
    end
    return split
end

local function os_is_unix()
    return sasl.getOS() ~= 'Windows'
end

--------------------------------------------------------------------------------------------------------------
function P.tableToStringOrValue(value)
  if type(value) == "table" then
    -- Versuche, es als sequenzielle Tabelle zu behandeln
    local parts = {}
    local is_sequence = true
    for i = 1, #value do
        if value[i] == nil then 
            is_sequence = false 
            break 
        end
        table.insert(parts, tostring(value[i]))
    end
    
    if is_sequence and #parts > 0 then
        return "{ " .. table.concat(parts, ", ") .. " }"
    else 
        -- Fallback für nicht-sequenzielle Tabellen oder leere Tabellen
        return "(table)" -- Einfache Darstellung für komplexere Tabellen
    end
  else
    -- Für Zahlen, Strings, Booleans etc.
    return tostring(value) 
  end
end

--------------------------------------------------------------------------------------------------------------
function P.shallowcopy(original)
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = v
    end
    return copy
end

--------------------------------------------------------------------------------------------------------------
function P.create_directories(dirnames)
    local cmd, args = nil, ""

    for i, dirname in pairs(dirnames) do
        assert(dirname:find("\"", 1, true) == nil)
    end
    if os_is_unix() then
        for i, dirname in pairs(dirnames) do
            args = args .. " \"" .. dirname .. "\""
        end
        cmd = "mkdir -p -- " .. args
        sasl.logDebug("file", 1, "executing: " .. cmd)
        os.execute(cmd)
    else
        -- Because CMD.EXE on Windows is dumb as a sack of hammers,
        -- we need to feed it commands in 8191-character increments,
        -- because NOBODY would ever need more than 8191 characters
        -- on a line, right?
        for i, dirname in pairs(dirnames) do
            -- the 290 character reserve here is because CMD.EXE
            -- counts the hostname and current directory into
            -- its line length (?!)
            if #args + #dirname + 3 > 7900 then
                -- Unfuck any slashes into backslashes to deal
                -- with FlyWithLua's broken SCRIPT_DIRECTORY
                args = args:gsub("/", "\\")
                cmd = "mkdir " .. args
                sasl.logDebug("file", 1, "executing: " .. cmd)
                os.execute(cmd)
                args = ""
            end
            args = args .. " \"" .. dirname .. "\""
        end
        if args ~= "" then
            args = args:gsub("/", "\\")
            cmd = "mkdir " .. args
            sasl.logDebug("file", 1, "executing: " .. cmd)
            os.execute(cmd)
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function P.file_exists_v2(file)
    -- some error codes:
    -- 13 : EACCES - Permission denied
    -- 17 : EEXIST - File exists
    -- 20	: ENOTDIR - Not a directory
    -- 21	: EISDIR - Is a directory
    --
    local isok, errstr, errcode = os.rename(file, file)
    if isok == nil then
        if errcode == 13 then
            -- Permission denied, but it exists
            return true
        end
        return false
    end
    return true
end

--------------------------------------------------------------------------------------------------------------
function P.dir_exists_v2(path)
    return P.file_exists_v2(path .. "/")
end

function P.check_create_path(path)
    if not P.dir_exists_v2(path) then
        P.logInfoTS("Folder " .. path .. " does not exist... creating it")
        P.create_directories({path})
        if not P.dir_exists_v2(path) then
            sasl.logWarning("Failure to create folder " .. path)
            return false
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.remove_directory(dirname)
    local cmd

    assert(dirname:find("..", 1, true) == nil)
    if os_is_unix() then
        assert(dirname:find("/", 1, true) ~= 1 or #dirname > 1)
        cmd = "rm -rf -- \"" .. dirname .. "\""
    else
        dirname = dirname:gsub("/", "\\")
        assert(dirname:find("[a-zA-Z]:\\") ~= 1 or #dirname > 3)
        assert(dirname:find("[a-zA-Z]:\\[Ww][Ii][Nn][Dd][Oo][Ww][Ss]") == nil)
        cmd = "rd /s /q \"" .. dirname .. "\""
    end

    sasl.logDebug("file", 1, "executing: " .. cmd)
    local res = os.execute(cmd)
end

--------------------------------------------------------------------------------------------------------------
function P.speak(text)

    local c_str = ffi.new("char[?]", #text + 1)
    ffi.copy(c_str, text)
    xplm.XPLMSpeakString(c_str)
end

--------------------------------------------------------------------------------------------------------------
function P.calccourse(in_crs)
    local result = (in_crs + 360) % 360
    result = math.floor(result + 0.5)
    if (result >= 359.5) then
        result = 0
    end
    
    return result
end

--------------------------------------------------------------------------------------------------------------
function P.logtable(tbl, path)
    -- Der Startpfad ist der Name der Tabelle oder leer, falls nicht angegeben.
    path = path or ""

    for key, value in pairs(tbl) do
        -- Erstelle den vollständigen Pfad für den aktuellen Eintrag.
        local current_path
        if path == "" then
            current_path = tostring(key)
        else
            current_path = path .. "." .. tostring(key)
        end

        if type(value) == "table" then
            -- Wenn der Wert eine weitere Tabelle ist, rufe die Funktion
            -- rekursiv mit dem neuen, erweiterten Pfad auf.
            P.logtable(value, current_path)
        else
            -- Gib den vollständigen Pfad und den dazugehörigen Wert aus.
            sasl.logDebug(current_path .. " = " .. tostring(value))
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function P.fieldexists(tbl, path)
    local keys = {}
    local buffer = ""
    local inBrackets = false

    -- Manuelle Zerlegung des Pfads
    for i = 1, #path do
        local char = string.sub(path, i, i)

        if char == "[" then
            inBrackets = true
            if buffer ~= "" then
                table.insert(keys, buffer)
                buffer = ""
            end
        elseif char == "]" then
            inBrackets = false
            if buffer ~= "" then
                table.insert(keys, buffer)
                buffer = ""
            end
        elseif char == "." and not inBrackets then
            if buffer ~= "" then
                table.insert(keys, buffer)
                buffer = ""
            end
        else
            buffer = buffer .. char
        end
    end

    -- Fuege den letzten Puffer hinzu
    if buffer ~= "" then
        table.insert(keys, buffer)
    end

    -- Rekursive Ueberpruefung des Pfads
    local function recurse(tbl, keys, index)
        index = index or 1
        if index > #keys then
            return true
        end
        local key = keys[index]
        if type(tbl) == "table" and tbl[key] ~= nil then
            return recurse(tbl[key], keys, index + 1)
        else
            return false
        end
    end

    return recurse(tbl, keys)
end

--------------------------------------------------------------------------------------------------------------
function P.containsvalue(tbl, target_value)
    if type(tbl) ~= "table" then
        return false
    end
    -- Ueberpruefe, ob die Tabelle den Zielwert direkt enthaelt
    for key, value in pairs(tbl) do
        if value == target_value then
            return true
        elseif type(value) == "table" then
            -- Wenn der Wert eine Tabelle ist, rufe die Funktion rekursiv auf
            if P.containsvalue(value, target_value) then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------------------------------------
function P.stringToBytes(inputStr)
    local byteStr = ""
    if type(inputStr) == "string" then
        for i = 1, #inputStr do
            byteStr = byteStr .. string.byte(inputStr, i) .. " "
        end
    end
    return byteStr
end

--------------------------------------------------------------------------------------------------------------
function P.forceCleanString(inputStr)
    local cleanStr = ""
    if type(inputStr) == "string" then
        for i = 1, #inputStr do
            local byte = string.byte(inputStr, i)
            if byte == 0 then
                break
            end
            cleanStr = cleanStr .. string.char(byte)
        end
        cleanStr = cleanStr:match("^(.-)%s*$") or cleanStr
    end
    return cleanStr
end

--------------------------------------------------------------------------------------------------------------
function P.addspaces(input)
    local result = ""
    
    local inputstr = tostring(input)

    for i = 1, #inputstr do
        result = result .. string.sub(inputstr, i, i) .. " "
    end

    return string.sub(result, 1, -2)
end

--------------------------------------------------------------------------------------------------------------
function P.spellNato(input)
    if input == nil then
        return ""
    end
    local nato = {
        A = "Alpha", B = "Bravo", C = "Charlie", D = "Delta", E = "Echo", F = "Foxtrot",
        G = "Golf", H = "Hotel", I = "India", J = "Juliet", K = "Kilo", L = "Lima",
        M = "Mike", N = "November", O = "Oscar", P = "Papa", Q = "Quebec", R = "Romeo",
        S = "Sierra", T = "Tango", U = "Uniform", V = "Victor", W = "Whiskey", X = "X-ray",
        Y = "Yankee", Z = "Zulu"
    }
    local text = tostring(input)
    local words = {}
    local len = #text
    local i = 1
    while i <= len do
        local b = string.byte(text, i)
        if b then
            if b >= 65 and b <= 90 then
                local ch = string.sub(text, i, i)
                local w = nato[ch] or ch
                words[#words + 1] = w
            elseif b >= 97 and b <= 122 then
                local ch = string.upper(string.sub(text, i, i))
                local w = nato[ch] or ch
                words[#words + 1] = w
            elseif b >= 48 and b <= 57 then
                words[#words + 1] = string.sub(text, i, i)
            end
        end
        i = i + 1
    end
    return table.concat(words, " ")
end

--------------------------------------------------------------------------------------------------------------
function P.replaceRunwayPrefix(input)
    if type(input) ~= "string" then
        return input
    end

    if input:match("^RW%d") then
        local suffix = input:sub(3)
        return "runway " .. P.addspaces(suffix)
    end

    return P.addspaces(input)
end

--------------------------------------------------------------------------------------------------------------

function P.padNumberWithZerosStrict(number, length)
    local str = tostring(number)
    if #str > length then
        error("Eingabe ist laenger als die gewuenschte Laenge!")
    end
    return string.rep("0", length - #str) .. str
end

--------------------------------------------------------------------------------------------------------------
function P.cleanstring(str)
    local result = ""
    for i = 1, #str do
        local char = string.sub(str, i, i)
        local b = string.byte(char, 1)
        local is_digit = (b and b >= 48 and b <= 57)
        local is_alpha = (b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)))
        if is_alpha or is_digit then
            result = result .. char
        end
    end
    return result
end

--------------------------------------------------------------------------------------------------------------
function P.splitstring(input)
    local parts = {}
    local current_pos = 1

    while true do
        local start_word = string.find(input, "%S", current_pos)

        if not start_word then
            break
        end

        local end_word = string.find(input, "%s", start_word)

        if end_word then
            table.insert(parts, string.sub(input, start_word, end_word - 1))
            current_pos = end_word + 1
        else
            table.insert(parts, string.sub(input, start_word))
            break
        end
    end
    return parts
end

--------------------------------------------------------------------------------------------------------------
function P.TransponderPostotring(transponderposition)

    if (transponderposition == def.STANDBY) then -- def ist global (angenommen)
        return "Standby"
    elseif (transponderposition == def.ALTOFF) then
        return "Altitude Off"
    elseif (transponderposition == def.ALTON) then
        return "Altitude On"
    elseif (transponderposition == def.TA) then
        return "T A"
    elseif (transponderposition == def.TARA) then
        return "T A R A"
    end
end

--------------------------------------------------------------------------------------------------------------
function P.formatILSFrequency(freq)
    local freqStr = tostring(freq)
    
    local beforeComma = string.sub(freqStr, 1, 3)
    local afterComma = string.sub(freqStr, 4)
    
    if #afterComma < 2 then
        afterComma = afterComma .. string.rep("0", 2 - #afterComma)
    elseif #afterComma > 2 then
        afterComma = string.sub(afterComma, 1, 2)
    end
    
    return beforeComma .. "," .. afterComma
end

--------------------------------------------------------------------------------------------------------------
function P.isvalidicao(icao)
    if type(icao) ~= "string" or #icao ~= 4 then
        return false
    end

    for i = 1, 4 do
        local char = string.sub(icao, i, i)
        if char < "A" or char > "Z" then
            return false
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.extractprimaryicao(value)
    local text = tostring(value or "")
    text = P.forceCleanString(text)
    if text == "" then
        return ""
    end
    text = string.upper(text)

    local len = #text
    if len >= 4 then
        local function is_alpha_byte(b)
            return b and b >= 65 and b <= 90
        end
        for i = 1, (len - 3) do
            local b1 = string.byte(text, i)
            local b2 = string.byte(text, i + 1)
            local b3 = string.byte(text, i + 2)
            local b4 = string.byte(text, i + 3)
            if is_alpha_byte(b1) and is_alpha_byte(b2) and is_alpha_byte(b3) and is_alpha_byte(b4) then
                local candidate = string.sub(text, i, i + 3)
                if P.isvalidicao(candidate) then
                    return candidate
                end
            end
        end
    end

    local cleaned = string.upper(P.cleanstring(text))
    if #cleaned >= 4 then
        local fallback = string.sub(cleaned, 1, 4)
        if P.isvalidicao(fallback) then
            return fallback
        end
    end
    return ""
end

--------------------------------------------------------------------------------------------------------------
function P.isvalidrwy(runway)
    if type(runway) ~= "string" then
        return false
    end

    local len = #runway
    local i = 1
    while i <= len do
        local b = string.byte(runway, i)
        if not b or b < 48 or b > 57 then
            break
        end
        i = i + 1
    end
    local number = nil
    local suffix = ""
    if i > 1 then
        number = string.sub(runway, 1, i - 1)
        if i <= len then
            local b = string.byte(runway, i)
            if b and (b == 76 or b == 82 or b == 67 or b == 84) then -- L R C T
                suffix = string.sub(runway, i, i)
            end
        end
    end
    if not number then
        return false
    end

    local num = tonumber(number)
    if num < 1 or num > 36 then
        return false
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.before_taxi_started(yal)
    if not yal then
        return false
    end
    local proc = yal.proceduretable and yal.proceduretable[def.BEFORETAXIPROCEDURE]
    if proc and proc.set then
        return true
    end
    if yal.loopStateTables then
        for i = 1, #yal.loopStateTables do
            local loop = yal.loopStateTables[i]
            if loop and loop.lock == def.BEFORETAXIPROCEDURE then
                return true
            end
        end
    else
        local l1 = yal.procedureloop1
        local l2 = yal.procedureloop2
        local l3 = yal.procedureloop3
        if (l1 and l1.lock == def.BEFORETAXIPROCEDURE)
            or (l2 and l2.lock == def.BEFORETAXIPROCEDURE)
            or (l3 and l3.lock == def.BEFORETAXIPROCEDURE) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------------------------------------
function P.adjustrwy(runway, increment)
    
    if not P.isvalidrwy(runway) then
        return nil
    end

    local len = #runway
    local i = 1
    while i <= len do
        local b = string.byte(runway, i)
        if not b or b < 48 or b > 57 then
            break
        end
        i = i + 1
    end
    if i == 1 then
        return nil
    end
    local number = tonumber(string.sub(runway, 1, i - 1))
    local suffix = ""
    if i <= len then
        suffix = string.sub(runway, i, len)
    end

    increment = increment or 1
    number = number + increment

    if (number > 36) then
        number = number - 36
    elseif (number < 1) then
        number = number + 36
    end

    local formatted_number = string.format("%02d", number)

    return formatted_number .. suffix
end

--------------------------------------------------------------------------------------------------------------
function P.formatRunwayDesignator(runwayDesignator)

    if type(runwayDesignator) ~= "string" or runwayDesignator == "" then
        return ""
    end

    local parts = {}
    
    local mapping = {
        L = "Left",
        R = "Right",
        C = "Center"
    }

    local len = string.len(runwayDesignator)


    for i = 1, len do
        local char = string.sub(runwayDesignator, i, i)

        if i == 3 and mapping[char] then
            table.insert(parts, mapping[char])
        else
            table.insert(parts, char)
        end
    end

    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------------------------------------
function P.getoppositerwy(runway)
    local len = #runway
    local i = 1
    while i <= len do
        local b = string.byte(runway, i)
        if not b or b < 48 or b > 57 then
            break
        end
        i = i + 1
    end
    local number = nil
    if i > 1 then
        number = tonumber(string.sub(runway, 1, i - 1))
    end
    local letter = ""
    local j = i
    while j <= len do
        local b = string.byte(runway, j)
        local is_alpha = (b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)))
        if is_alpha then
            letter = string.sub(runway, j, j)
            break
        end
        j = j + 1
    end

    local oppositeNumber = (number + 18) % 36
    if (oppositeNumber == 0) then
        oppositeNumber = 36
    end

    local oppositeRunway = string.format("%02d", oppositeNumber) .. letter

    return oppositeRunway
end

--------------------------------------------------------------------------------------------------------------
function P.getoppositeheading(heading)
    local oppositeHeading = (heading + 180) % 360
    return oppositeHeading
end

--------------------------------------------------------------------------------------------------------------
function P.getheadingdiff(heading1, heading2)
    local diff = math.abs(heading1 - heading2)
    
    if (diff > 180) then
        diff = 360 - diff
    end
    
    return diff
end

--------------------------------------------------------------------------------------------------------------

function P.roundnumber(num, decimalPlaces)

    decimalPlaces = decimalPlaces or 0

    local power = 10^decimalPlaces

    if num >= 0 then
        return (math.floor(num * power + 0.5) / power)
    else
        return (math.ceil(num * power - 0.5) / power)
    end
end

--------------------------------------------------------------------------------------------------------------
function P.round_to_step(value, step)

    local v = tonumber(value)
    local s = tonumber(step)
    if not v or not s or s <= 0 then
        return nil
    end
    local scaled = v / s
    local rounded = P.roundnumber(scaled, 0)
    return rounded * s

end

--------------------------------------------------------------------------------------------------------------
function P.format_trim_quarter(value)

    local rounded = P.round_to_step(value, 0.25)
    if rounded == nil then
        return nil
    end
    local text = string.format("%.2f", rounded)
    text = text:gsub("%.?0+$", "")
    return text

end

--------------------------------------------------------------------------------------------------------------
function P.formatcgvalue(value)
    local cg = tonumber(value)
    if not cg then
        return nil
    end
    if math.abs(cg) < 0.01 then
        return nil
    end
    if math.abs(cg) < 1 then
        cg = cg * 100
    end
    local rounded = P.roundnumber(cg, 1)
    if rounded == 0 then
        return nil
    end
    return rounded
end

--------------------------------------------------------------------------------------------------------------
function P.headingdiff(heading1, heading2)

    local headingdifftemp = math.abs(heading1 - heading2)

    if (headingdifftemp > 180) then
        return (360 - headingdifftemp)
    else
        return (headingdifftemp)
    end
end

--------------------------------------------------------------------------------------------------------------

function P.convertpressure(value)

    value = tonumber(value)
    if value then
        if (value > 100) then
            local inches = value / def.INCHTOPAS -- def ist global (angenommen)
            return P.roundnumber(inches, 2)
        else
            local hpa = value * def.INCHTOPAS
            return P.roundnumber(hpa, 0)
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function P.formatQnhValue(value, useHpa)
    local num = tonumber(value)
    if not num then
        return nil
    end
    if useHpa then
        return string.format("%.0f", num)
    end
    return string.format("%.2f", num)
end

--------------------------------------------------------------------------------------------------------------
function P.gettrim(trimwheel)

    local trim = 0

    local trimwheelrounded = P.roundnumber(trimwheel * -100)

    if (trimwheelrounded <= 21) then
        trim = 6.50
    elseif (trimwheelrounded <= 24) then
        trim = 6.25
    elseif (trimwheelrounded <= 27) then
        trim = 6.0
    elseif (trimwheelrounded <= 30) then
        trim = 5.75
    elseif (trimwheelrounded <= 32) then
        trim = 5.5
    elseif (trimwheelrounded <= 34) then
        trim = 5.25
    elseif (trimwheelrounded <= 40) then
        trim = 5.0
    elseif (trimwheelrounded <= 42) then
        trim = 4.75
    elseif (trimwheelrounded <= 45) then
        trim = 4.5
    elseif (trimwheelrounded <= 48) then
        trim = 4.25
    elseif (trimwheelrounded <= 52) then
        trim = 4.0
    elseif (trimwheelrounded <= 55) then
        trim = 3.75
    elseif (trimwheelrounded <= 58) then
        trim = 3.5
    elseif (trimwheelrounded <= 61) then
        trim = 3.25
    elseif (trimwheelrounded <= 65) then
        trim = 3.0
    else
        trim = 5.0
    end

    return (trim)

end

--------------------------------------------------------------------------------------------------------------
function P.trimvalue_to_trimwheel(trim_value)

    local t = tonumber(trim_value)
    if not t then
        return nil
    end
    if not P._trimwheel_map then
        P._trimwheel_map = {
            {3.00, 65},
            {3.25, 61},
            {3.50, 58},
            {3.75, 55},
            {4.00, 52},
            {4.25, 48},
            {4.50, 45},
            {4.75, 42},
            {5.00, 40},
            {5.25, 34},
            {5.50, 32},
            {5.75, 30},
            {6.00, 27},
            {6.25, 24},
            {6.50, 21}
        }
    end
    local map = P._trimwheel_map
    local first = map[1]
    local last = map[#map]
    if t <= first[1] then
        return first[2]
    end
    if t >= last[1] then
        return last[2]
    end
    for i = 1, (#map - 1) do
        local t1 = map[i][1]
        local t2 = map[i + 1][1]
        if t >= t1 and t <= t2 then
            local w1 = map[i][2]
            local w2 = map[i + 1][2]
            local frac = (t - t1) / (t2 - t1)
            return w1 + (w2 - w1) * frac
        end
    end
    return last[2]

end

--------------------------------------------------------------------------------------------------------------
function P.trimwheel_matches_target(trimwheel, trim_value, tol)

    local target = P.trimvalue_to_trimwheel(trim_value)
    if not target then
        return false
    end
    local tw = tonumber(trimwheel)
    if not tw then
        return false
    end
    local actual = tw * -100
    local tolerance = tonumber(tol) or 0.5
    return math.abs(actual - target) <= tolerance

end

--------------------------------------------------------------------------------------------------------------
function P.trimwheel_matches_trim_step(trimwheel, trim_value, step)

    local tw = tonumber(trimwheel)
    local tv = tonumber(trim_value)
    local s = tonumber(step) or 0.25
    if (not tw) or (not tv) or (s <= 0) then
        return false
    end

    local currentTrim = P.gettrim(tw)
    local currentStep = P.round_to_step(currentTrim, s)
    local targetStep = P.round_to_step(tv, s)
    if (currentStep == nil) or (targetStep == nil) then
        return false
    end

    return math.abs(currentStep - targetStep) < 0.01

end

--------------------------------------------------------------------------------------------------------------
function P.isSpeedbrakeDown()

    local lever = tonumber(get(P.speedbrakelever)) or 0
    local ratio = tonumber(get(P.speedbrakeratio)) or 0
    local anim = tonumber(get(P.speedbrakeleveranim)) or 0

    return (lever < 0.05) and (math.abs(ratio) < 0.05) and (anim == 0)

end

--------------------------------------------------------------------------------------------------------------
function P.convflaplevertoflappos(flaplever)

    local returnvalue = 0

    if (flaplever == def.FLAPSUP) then -- def ist global (angenommen)
        returnvalue = 0
    elseif (flaplever == def.FLAPS1) then
        returnvalue = 1
    elseif (flaplever == def.FLAPS2) then
        returnvalue = 2
    elseif (flaplever == def.FLAPS5) then
        returnvalue = 5
    elseif (flaplever == def.FLAPS10) then
        returnvalue = 10
    elseif (flaplever == def.FLAPS15) then
        returnvalue = 15
    elseif (flaplever == def.FLAPS25) then
        returnvalue = 25
    elseif (flaplever == def.FLAPS30) then
        returnvalue = 30
    elseif (flaplever == def.FLAPS40) then
        returnvalue = 40
    end

    return (returnvalue)

end

--------------------------------------------------------------------------------------------------------------
function P.getbankanglestring(bankangle)

    local bankanglestring = ""

    if (bankangle == def.BANKANGLEMIN) then -- def ist global (angenommen)
        bankanglestring = "Minimum"
    elseif (bankangle == def.BANKANGLE15) then
        bankanglestring = "15"
    elseif (bankangle == def.BANKANGLE20) then
        bankanglestring = "20"
    elseif (bankangle == def.BANKANGLE25) then
        bankanglestring = "25"
    elseif (bankangle == def.BANKANGLEMAX) then
        bankanglestring = "Maximum"
    end

    return bankanglestring
end

--------------------------------------------------------------------------------------------------------------
local function sanitizeWeatherEntries(list)
    if type(list) ~= "table" then
        return nil
    end
    local sanitized = {}
    for _, entry in ipairs(list) do
        local intensity = "moderate"
        local phenomenon = nil
        if type(entry) == "string" then
            phenomenon = entry
        elseif type(entry) == "table" then
            if type(entry.phenomenon) == "string" and entry.phenomenon ~= "" then
                phenomenon = entry.phenomenon
            elseif type(entry.code) == "string" and entry.code ~= "" then
                phenomenon = entry.code
            elseif type(entry[1]) == "string" and entry[1] ~= "" then
                phenomenon = entry[1]
            end
            if type(entry.intensity) == "string" and entry.intensity ~= "" then
                intensity = entry.intensity
            elseif type(entry[2]) == "string" and entry[2] ~= "" then
                intensity = entry[2]
            end
        end
        if phenomenon and phenomenon ~= "" then
            table.insert(sanitized, {
                intensity = intensity,
                phenomenon = phenomenon
            })
        end
    end
    if #sanitized == 0 then
        return nil
    end
    return sanitized
end

function P.decodemetar(metar)
    local result = {}
    local parts = {}

    sasl.logDebug("Starting METAR parsing")
    local function push_part(part)
        if type(part) ~= "string" or part == "" then
            return
        end
        local cleaned = {}
        for i = 1, #part do
            local byte = string.byte(part, i)
            if byte and byte >= 32 and byte <= 126 then
                cleaned[#cleaned + 1] = string.char(byte)
            end
        end
        part = table.concat(cleaned)
        part = part:gsub("^%s+", ""):gsub("%s+$", "")
        if part == "" then
            return
        end
        part = part:gsub("[=%$]+$", "")
        if part == "" then
            return
        end
        table.insert(parts, part)
    end

    local current_part = ""
    for i = 1, #metar do
        local c = string.sub(metar, i, i)
        if (c == " " or c == "\r" or c == "\n" or c == "\t") then
            if (#current_part > 0) then
                push_part(current_part)
                current_part = ""
            end
        else
            current_part = current_part .. c
        end
    end
    if (#current_part > 0) then
        push_part(current_part)
    end

    sasl.logDebug("METAR parts:")
    for idx, part_val in ipairs(parts) do
        sasl.logDebug(string.format("   [%d] = %s", idx, part_val))
    end

    if #parts >= 1 then
        local first = parts[1]
        if first == "METAR" or first == "SPECI" or first == "TAF" then
            table.remove(parts, 1)
        end
    end

    if (#parts >= 1) then
        result.station = parts[1]
        sasl.logDebug("Parsed station: "..result.station)
    end

    if (#parts >= 2) then
        local dt = parts[2]
        if ((#dt == 7) and (string.sub(dt, 7) == "Z")) then
            local day = tonumber(string.sub(dt, 1, 2))
            local time_str = string.sub(dt, 3, 6)
            if (day and time_str) then
                result.date_time = { day = day, time = time_str, timezone = "Z" }
                sasl.logDebug(string.format("Parsed datetime: day=%d, time=%s", result.date_time.day, result.date_time.time))
            else
                sasl.logError("Warning: Could not parse day or time from: " .. dt)
            end
        else
            sasl.logError("Warning: Date/Time part not in expected format: " .. dt)
        end
    end

    local i = 3
    local parsing_main_data = true

    if (i <= #parts and parts[i] == "AUTO") then
        result.auto = true
        sasl.logDebug("Parsed AUTO: true")
        i = i + 1
    else
        result.auto = false
    end

    local weather_codes = {
        "RA","SN","DZ","SG","PL","GR","GS","IC","UP","FG","BR","SA",
        "DU","HZ","FU","VA","PY","PO","SQ","FC","SS","DS","SH","TS",
        "FZ","MI","PR","BC","DR","BL","VC","NSW"
    }

    local function is_weather_code(s)
        local code_to_check = s
        if string.sub(s, 1, 1) == "-" or string.sub(s, 1, 1) == "+" then
            code_to_check = string.sub(s, 2)
        end
        if #code_to_check < 2 then return false end

        for _, code in ipairs(weather_codes) do
            if string.find(code_to_check, code, 1, true) then
                if code_to_check == code then return true end
            end
        end
        for _, code in ipairs(weather_codes) do
            if string.find(s, code, 1, true) then
                return true
            end
        end
        return false
    end

    local function parse_fraction_value(value_str)
        if not value_str or value_str == "" then
            return nil
        end
        local slash_pos = string.find(value_str, "/", 1, true)
        if slash_pos then
            local num = tonumber(string.sub(value_str, 1, slash_pos - 1))
            local den = tonumber(string.sub(value_str, slash_pos + 1))
            if num and den and den ~= 0 then
                return num / den
            end
            return nil
        end
        return tonumber(value_str)
    end

    local function parse_sm_value(sm_text)
        if not sm_text or sm_text == "" then
            return nil
        end
        local more_than = false
        local less_than = false
        local first = string.sub(sm_text, 1, 1)
        if first == "P" then
            more_than = true
            sm_text = string.sub(sm_text, 2)
        elseif first == "M" then
            less_than = true
            sm_text = string.sub(sm_text, 2)
        end

        local space_pos = string.find(sm_text, " ", 1, true)
        local total = 0
        if space_pos then
            local int_str = string.sub(sm_text, 1, space_pos - 1)
            local frac_str = string.sub(sm_text, space_pos + 1)
            if int_str ~= "" then
                local int_val = tonumber(int_str)
                if not int_val then
                    return nil
                end
                total = total + int_val
            end
            if frac_str ~= "" then
                local frac_val = parse_fraction_value(frac_str)
                if not frac_val then
                    return nil
                end
                total = total + frac_val
            end
        else
            local val = parse_fraction_value(sm_text)
            if not val then
                return nil
            end
            total = total + val
        end

        return total, more_than, less_than
    end

    local function apply_visibility_meters(meters, more_than, less_than, vis_index)
        if type(meters) ~= "number" then
            return vis_index
        end
        result.visibility = { value = math.min(meters, 10000) }
        if more_than then
            result.visibility.more_than = true
        end
        if less_than then
            result.visibility.less_than = true
        end
        if vis_index and vis_index + 1 <= #parts then
            local next_part = parts[vis_index + 1]
            local dir_vis_val, dir_code = nil, nil
            local len = #next_part
            if len >= 5 then
                local is_digits = true
                for i = 1, 4 do
                    local b = string.byte(next_part, i)
                    if not b or b < 48 or b > 57 then
                        is_digits = false
                        break
                    end
                end
                if is_digits then
                    local code = string.sub(next_part, 5, len)
                    if code ~= "" then
                        local ok = true
                        for i = 1, #code do
                            local b = string.byte(code, i)
                            local is_card = (b == 78 or b == 83 or b == 69 or b == 87) -- N S E W
                            if not is_card then
                                ok = false
                                break
                            end
                        end
                        if ok then
                            dir_vis_val = string.sub(next_part, 1, 4)
                            dir_code = code
                        end
                    end
                end
            end
            if dir_vis_val and dir_code then
                result.visibility.directional = {
                    value = tonumber(dir_vis_val),
                    direction = dir_code
                }
                sasl.logDebug(string.format("Parsed directional visibility: %d meters towards %s",
                              result.visibility.directional.value, result.visibility.directional.direction))
                return vis_index + 1
            end
        end
        return vis_index
    end

    local function parse_rvr_value(value_str, unit)
        if not value_str or value_str == "" then
            return nil
        end
        local more_than = false
        local less_than = false
        local first_char = string.sub(value_str, 1, 1)
        if first_char == "P" then
            more_than = true
            value_str = string.sub(value_str, 2)
        elseif first_char == "M" then
            less_than = true
            value_str = string.sub(value_str, 2)
        end
        if value_str == "" then
            return nil
        end
        local value = tonumber(value_str)
        if not value then
            return nil
        end
        local meters = value
        if unit == "FT" then
            meters = math.floor(value * 0.3048 + 0.5)
        end
        return {
            value = value,
            meters = meters,
            more_than = more_than,
            less_than = less_than
        }
    end

    local function parse_rvr_report(token)
        if type(token) ~= "string" then
            return nil
        end
        if string.sub(token, 1, 1) ~= "R" then
            return nil
        end
        local slash_pos = string.find(token, "/", 2, true)
        if not slash_pos then
            return nil
        end

        local runway_part = string.sub(token, 2, slash_pos - 1)
        local rvr_part = string.sub(token, slash_pos + 1)
        if runway_part == "" or rvr_part == "" then
            return nil
        end

        runway_part = string.upper(runway_part)

        local unit = "M"
        if #rvr_part >= 2 and string.sub(rvr_part, -2) == "FT" then
            unit = "FT"
            rvr_part = string.sub(rvr_part, 1, -3)
        end

        local trend = nil
        if #rvr_part >= 1 then
            local trend_char = string.sub(rvr_part, -1)
            if trend_char == "U" or trend_char == "D" or trend_char == "N" then
                trend = trend_char
                rvr_part = string.sub(rvr_part, 1, -2)
            end
        end

        if rvr_part == "" then
            return nil
        end

        local min_part = rvr_part
        local max_part = nil
        local var_pos = string.find(rvr_part, "V", 1, true)
        if var_pos then
            min_part = string.sub(rvr_part, 1, var_pos - 1)
            max_part = string.sub(rvr_part, var_pos + 1)
        end

        local min_val = parse_rvr_value(min_part, unit)
        if not min_val then
            return nil
        end

        local max_val = nil
        if max_part and max_part ~= "" then
            max_val = parse_rvr_value(max_part, unit)
        end

        local runway_number = nil
        local runway_side = nil
        if #runway_part >= 2 then
            local runway_num_str = string.sub(runway_part, 1, 2)
            local runway_num = tonumber(runway_num_str)
            if runway_num then
                runway_number = runway_num
            end
            if #runway_part >= 3 then
                local side_char = string.sub(runway_part, 3, 3)
                if side_char == "L" or side_char == "R" or side_char == "C" then
                    runway_side = side_char
                end
            end
        end

        return {
            runway = runway_part,
            number = runway_number,
            side = runway_side,
            unit = unit,
            trend = trend,
            min = min_val,
            max = max_val,
            raw = token
        }
    end

    while (i <= #parts and parsing_main_data) do
        local part = parts[i]
        sasl.logDebug(string.format("Processing part %d: %s", i, part))
        local parsed = false

        if (part == "TEMPO" or part == "BECMG" or (string.len(part) >= 4 and string.sub(part, 1, 4) == "PROB") or part == "TREND") then
            parsing_main_data = false
            sasl.logDebug("Trend/change group found, METAR main data parsing stopped: " .. part)
            break

        elseif (part == "CAVOK") then
            result.cavok = true
            result.visibility = { value = 10000 }
            result.clouds = result.clouds or {}
            table.insert(result.clouds, {coverage="NSC", altitude=nil, type=""})
            sasl.logDebug("Parsed CAVOK: visibility >= 10km, no significant clouds/weather")
            parsed = true

        elseif (not result.wind and
                ( (string.sub(part, 1, 3) == "VRB") or (tonumber(string.sub(part, 1, 3)) ~= nil) ) and
                (#part >= 5) and
                (string.sub(part, -2) == "KT" or string.sub(part, -3) == "MPS" or string.sub(part, -3) == "KMH")
               ) then
            local dir_str = string.sub(part, 1, 3)
            local direction = (dir_str == "VRB") and "VRB" or tonumber(dir_str)
            local var_dir_match = nil
            if ((#part >= 9) and (string.sub(part, 6, 6) == "V")) then
                local d1_str = string.sub(part, 4, 5)
                local d2_str = string.sub(part, 7, 9)
                local d1 = tonumber(d1_str)
                local d2 = tonumber(d2_str)
                if (d1 and d2) then
                    var_dir_match = { dir1 = d1, dir2 = d2 }
                    sasl.logDebug(string.format("Parsed variable wind direction (within main wind group): %d-%d", d1, d2))
                end
            end

            local unit_str = (string.sub(part, -2) == "KT" and "KT") or
                             (string.sub(part, -3) == "MPS" and "MPS") or
                             (string.sub(part, -3) == "KMH" and "KMH") or nil

            if (direction and unit_str) then
                local speed_part_end = #part - #unit_str
                local speed_str_val = ""
                local gust_str_val = nil
                local g_pos = string.find(part, "G", 4)

                if (g_pos and g_pos < speed_part_end) then
                    speed_str_val = string.sub(part, 4, g_pos - 1)
                    gust_str_val = string.sub(part, g_pos + 1, speed_part_end)
                else
                    speed_str_val = string.sub(part, 4, speed_part_end)
                end

                local speed = tonumber(speed_str_val)
                local gust = (gust_str_val and tonumber(gust_str_val)) or 0

                if (speed ~= nil) then
                    if (unit_str == "MPS") then
                        speed = math.floor(speed * 1.94384 + 0.5)
                        if (gust_str_val) then gust = math.floor(gust * 1.94384 + 0.5) end
                    elseif (unit_str == "KMH") then
                        speed = math.floor(speed * 0.539957 + 0.5)
                        if (gust_str_val) then gust = math.floor(gust * 0.539957 + 0.5) end
                    end

                    result.wind = {
                        direction = direction,
                        speed = speed,
                        gust = gust,
                        variable_direction = var_dir_match
                    }
                    sasl.logDebug(string.format("Parsed wind: dir=%s, speed=%d kt, gust=%d kt%s",
                        tostring(direction), speed, gust, (var_dir_match and string.format(", var=%d-%d", var_dir_match.dir1, var_dir_match.dir2)) or ""))
                    parsed = true
                else
                    sasl.logError("Warning: Could not parse wind speed from: " .. part)
                end
            else
                sasl.logError("Warning: Could not parse wind direction or unit from: " .. part)
            end

        elseif (result.wind and not result.wind.variable_direction and
                #part == 7 and
                string.sub(part, 4, 4) == "V" and
                tonumber(string.sub(part, 1, 3)) and
                tonumber(string.sub(part, 5, 7))
               ) then
            local d1 = tonumber(string.sub(part, 1, 3))
            local d2 = tonumber(string.sub(part, 5, 7))
            if d1 and d2 then
                result.wind.variable_direction = { dir1 = d1, dir2 = d2 }
                sasl.logDebug(string.format("Parsed separate variable wind direction group: %d V %d", d1, d2))
                parsed = true
            end

        elseif (not result.visibility) then
            local visibility_parsed = false

            if tonumber(part) and i + 1 <= #parts then
                local next_part = parts[i + 1]
                if #next_part > 2 and string.sub(next_part, -2) == "SM" then
                    local sm_val_str = part .. " " .. string.sub(next_part, 1, #next_part - 2)
                    local sm_value, more_than, less_than = parse_sm_value(sm_val_str)
                    if sm_value then
                        local meters = math.floor(sm_value * 1609.34 + 0.5)
                        local vis_index = i + 1
                        i = apply_visibility_meters(meters, more_than, less_than, vis_index)
                        sasl.logDebug(string.format("Parsed visibility: %sSM, converted to %d meters", sm_val_str, result.visibility.value))
                        parsed = true
                        visibility_parsed = true
                    end
                end
            end

            if (not visibility_parsed) and (#part > 2) and (string.sub(part, -2) == "SM") then
                local sm_val_str = string.sub(part, 1, #part - 2)
                local sm_value, more_than, less_than = parse_sm_value(sm_val_str)
                if (sm_value) then
                    local meters = math.floor(sm_value * 1609.34 + 0.5)
                    local vis_index = i
                    i = apply_visibility_meters(meters, more_than, less_than, vis_index)
                    sasl.logDebug(string.format("Parsed visibility: %sSM, converted to %d meters", sm_val_str, result.visibility.value))
                    parsed = true
                    visibility_parsed = true
                else
                    sasl.logError("Warning: Could not parse SM visibility value from: " .. part)
                end
            end

            if (not visibility_parsed) and (#part > 2) and (string.sub(part, -2) == "KM") and (string.sub(part, -3) ~= "KMH") then
                local km_val_str = string.sub(part, 1, #part - 2)
                local km_val = tonumber(km_val_str)
                if km_val then
                    local meters = math.floor(km_val * 1000 + 0.5)
                    local vis_index = i
                    i = apply_visibility_meters(meters, false, false, vis_index)
                    sasl.logDebug(string.format("Parsed visibility: %sKM, converted to %d meters", km_val_str, result.visibility.value))
                    parsed = true
                    visibility_parsed = true
                else
                    sasl.logError("Warning: Could not parse KM visibility value from: " .. part)
                end
            end

            if (not visibility_parsed) then
                local ndv_value = nil
                local len = #part
                if len >= 7 then
                    local suffix = string.sub(part, len - 2, len)
                    if suffix == "NDV" then
                        local ok = true
                        for i = 1, len - 3 do
                            local b = string.byte(part, i)
                            if not b or b < 48 or b > 57 then
                                ok = false
                                break
                            end
                        end
                        if ok then
                            ndv_value = string.sub(part, 1, len - 3)
                        end
                    end
                end
                if ndv_value then
                    local numeric_val = tonumber(ndv_value)
                    local meters = (ndv_value == "9999") and 10000 or numeric_val
                    local vis_index = i
                    i = apply_visibility_meters(meters, false, false, vis_index)
                    if ndv_value == "9999" then
                        sasl.logDebug("Parsed visibility: 10000+ meters (from 9999NDV)")
                    else
                        sasl.logDebug(string.format("Parsed visibility: %d meters (NDV)", result.visibility.value))
                    end
                    result.visibility_ndv = true
                    parsed = true
                    visibility_parsed = true
                elseif #part == 4 and (tonumber(part) or part == "9999") then
                    local meters = (part == "9999") and 10000 or tonumber(part)
                    local vis_index = i
                    i = apply_visibility_meters(meters, false, false, vis_index)
                    if (part == "9999") then
                        sasl.logDebug("Parsed visibility: 10000+ meters (from 9999)")
                    else
                        sasl.logDebug(string.format("Parsed visibility: %d meters", result.visibility.value))
                    end
                    parsed = true
                end
            end

        elseif (string.sub(part, 1, 1) == "R" and string.find(part, "/", 1, true) and #part >= 5) then
            result.runway_reports = result.runway_reports or {}
            table.insert(result.runway_reports, part)
            local rvr_entry = parse_rvr_report(part)
            if rvr_entry then
                result.rvr = result.rvr or {}
                table.insert(result.rvr, rvr_entry)
                sasl.logDebug(string.format("Parsed RVR: RWY %s %s%s%s",
                    rvr_entry.runway or "?",
                    rvr_entry.min and rvr_entry.min.value or "?",
                    rvr_entry.max and ("V" .. rvr_entry.max.value) or "",
                    rvr_entry.unit or ""))
            else
                sasl.logDebug("Parsed runway report: "..part)
            end
            parsed = true

        elseif (is_weather_code(part)) then
            result.weather = result.weather or {}
            local intensity = "moderate"
            local phenomenon = part
            if string.sub(part, 1, 1) == "-" then
                intensity = "light"
                phenomenon = string.sub(part, 2)
            elseif string.sub(part, 1, 1) == "+" then
                intensity = "heavy"
                phenomenon = string.sub(part, 2)
            end

            table.insert(result.weather, {
                intensity = intensity,
                phenomenon = phenomenon
            })
            sasl.logDebug(string.format("Parsed weather: %s (%s)", phenomenon, intensity))
            parsed = true

        elseif ( (string.sub(part, 1, 3) == "FEW" or string.sub(part, 1, 3) == "SCT" or string.sub(part, 1, 3) == "BKN" or string.sub(part, 1, 3) == "OVC") and
                 #part >= 6 and tonumber(string.sub(part, 4, 6)) ~= nil ) or
               ( string.sub(part, 1, 2) == "VV" and #part >= 5 and tonumber(string.sub(part, 3, 5)) ~= nil ) or
               ( part == "SKC" or part == "CLR" or part == "NSC" or part == "NCD" ) or
               ( string.sub(part, 1, 1) == '/' and (string.find(part, "TCU$") or string.find(part, "CB$")) ) or
               ( string.sub(part, 1, 1) == '/' and (string.find(part, "FEW$") or string.find(part, "SCT$") or string.find(part, "BKN$") or string.find(part, "OVC$")) ) or
               ( (string.sub(part, 1, 3) == "FEW" or string.sub(part, 1, 3) == "SCT" or string.sub(part, 1, 3) == "BKN" or string.sub(part, 1, 3) == "OVC") and string.sub(part, -3) == "///" )
        then
            result.clouds = result.clouds or {}
            if (part == "SKC" or part == "CLR" or part == "NSC" or part == "NCD") then
                table.insert(result.clouds, { coverage = part, altitude = nil, type = "" })
                sasl.logDebug("Parsed cloud: " .. part)
                parsed = true
            elseif (string.sub(part, 1, 1) == '/') then
                 parsed = true
            elseif (string.sub(part, -3) == "///") then
                 parsed = true
            else
                local coverage_code
                local altitude_str_val
                local altitude_idx_start
                if string.sub(part, 1, 2) == "VV" then
                    coverage_code = "VV"
                    altitude_idx_start = 3
                else
                    coverage_code = string.sub(part, 1, 3)
                    altitude_idx_start = 4
                end
                altitude_str_val = string.sub(part, altitude_idx_start, altitude_idx_start + 2)
                local altitude_val = tonumber(altitude_str_val)
                if altitude_val then
                    local cloud_significant_type = ""
                    if #part > (altitude_idx_start + 2) then
                        cloud_significant_type = string.sub(part, altitude_idx_start + 3)
                    end
                    table.insert(result.clouds, { coverage = coverage_code, altitude = altitude_val * 100, type = cloud_significant_type })
                    sasl.logDebug(string.format("Parsed cloud: %s at %d ft%s", coverage_code, altitude_val * 100, (cloud_significant_type ~= "" and (" ("..cloud_significant_type..")")) or ""))
                    parsed = true
                else
                    sasl.logError("Warning: Could not parse cloud altitude for: " .. part .. " (altitude_str: '" .. altitude_str_val .. "')")
                end
            end

        elseif (part == "//") then
            result.temperature = { value = nil }
            result.dew_point = { value = nil }
            sasl.logDebug("Parsed missing temperature/dew point data ('//')")
            parsed = true

        elseif ( string.find(part, "/", 1, true) and (#part >= 5 and #part <= 7) and
                 (string.sub(part, 1, 1) == "M" or tonumber(string.sub(part, 1, 1)) ~= nil) ) then
            local slash_pos = string.find(part, "/", 2, true)
            if slash_pos then
                local temp_str_val = string.sub(part, 1, slash_pos - 1)
                local dew_str_val = string.sub(part, slash_pos + 1)
                local temp_val = tonumber((string.gsub(temp_str_val, "M", "-")))
                local dew_val = tonumber((string.gsub(dew_str_val, "M", "-")))

                if ((temp_val ~= nil) and (dew_val ~= nil)) then
                    result.temperature = { value = temp_val }
                    result.dew_point = { value = dew_val }
                    sasl.logDebug(string.format("Parsed temp/dew: %d C/%d C", temp_val, dew_val))
                    parsed = true
                end
            end

        elseif ((#part == 5) and (string.sub(part, 1, 1) == "Q" or string.sub(part, 1, 1) == "A") and tonumber(string.sub(part, 2))) then
            local val_str = string.sub(part, 2)
            if (string.sub(part, 1, 1) == "Q") then
                result.pressure = { qnh_hpa = tonumber(val_str) }
                sasl.logDebug(string.format("Parsed pressure: %d hPa", result.pressure.qnh_hpa))
            elseif (string.sub(part, 1, 1) == "A") then
                local inHg = tonumber(val_str) / 100
                result.pressure = { qnh_hpa = math.floor(inHg * 33.8639) }
                sasl.logDebug(string.format("Parsed pressure: %.2f inHg, converted to %d hPa", inHg, result.pressure.qnh_hpa))
            end
            parsed = true

        elseif (part == "NOSIG") then
            result.nosig = true
            sasl.logDebug("Parsed NOSIG")
            parsed = true

        elseif (part == "RMK") then
            result.remarks = ""
            local remark_idx = i + 1
            while(remark_idx <= #parts) do
                local current_remark = parts[remark_idx]
                if (current_remark == "TEMPO" or current_remark == "BECMG" or (string.len(current_remark) >=4 and string.sub(current_remark, 1, 4) == "PROB") or current_remark == "TREND") then
                    break
                end
                result.remarks = result.remarks .. current_remark .. " "
                remark_idx = remark_idx + 1
            end
            i = remark_idx - 1
            sasl.logDebug("Parsed RMK: " .. result.remarks)
            parsed = true
        end

        if (not parsed) then
            P.logInfoTS("METAR Parsing unknown element: " .. part)
        end
        i = i + 1
    end

    if not (result.pressure and tonumber(result.pressure.qnh_hpa)) then
        for _, part in ipairs(parts) do
            if #part >= 6 and string.sub(part, 1, 3) == "SLP" then
                local slp_digits = string.sub(part, 4, 6)
                local slp_val = tonumber(slp_digits)
                if slp_val then
                    local base = (slp_val >= 500) and 900 or 1000
                    local qnh = base + (slp_val / 10)
                    result.pressure = result.pressure or {}
                    result.pressure.qnh_hpa = qnh
                    sasl.logDebug(string.format("Parsed pressure from SLP: %s -> %.1f hPa", slp_digits, qnh))
                    break
                end
            end
        end
    end

    local need_temp = not (result.temperature and result.temperature.value ~= nil)
    local need_dew = not (result.dew_point and result.dew_point.value ~= nil)
    if need_temp or need_dew then
        for _, part in ipairs(parts) do
            if #part == 9 and string.sub(part, 1, 1) == "T" then
                local temp_sign = string.sub(part, 2, 2)
                local temp_str = string.sub(part, 3, 5)
                local dew_sign = string.sub(part, 6, 6)
                local dew_str = string.sub(part, 7, 9)
                local temp_val = tonumber(temp_str)
                local dew_val = tonumber(dew_str)
                if (temp_sign == "0" or temp_sign == "1") and (dew_sign == "0" or dew_sign == "1") and temp_val and dew_val then
                    local temp = temp_val / 10
                    if temp_sign == "1" then temp = -temp end
                    local dew = dew_val / 10
                    if dew_sign == "1" then dew = -dew end
                    result.temperature = result.temperature or {}
                    result.dew_point = result.dew_point or {}
                    if need_temp then result.temperature.value = temp end
                    if need_dew then result.dew_point.value = dew end
                    sasl.logDebug(string.format("Parsed temp/dew from T-group: %.1f C/%.1f C", temp, dew))
                    break
                end
            end
        end
    end

    sasl.logDebug("METAR parsing complete")
    result.weather = sanitizeWeatherEntries(result.weather)
    return result
end

--------------------------------------------------------------------------------------------------------------
function P.onMetarDownloaded(url, path, isOk, responseCodeOrError, metarTable)

    if isOk then
        local file = io.open(path, "r")
        if file then
            local metarstring = file:read("*a")
            file:close()

            if metarstring and #metarstring > 0 then
                P.logInfoTS("METAR for " .. metarTable.icaocode .. " successfully downloaded.")
                metarTable.metar.raw_text = metarstring
                metarTable.decodedmetar = helpers.decodemetar(metarstring)
                metarTable.metarfound = true
            else
                P.logInfoTS("Downloaded METAR file for " .. metarTable.icaocode .. " was empty.")
            end
        else
            P.logInfoTS("Could not open temp file for " .. metarTable.icaocode)
        end
        os.remove(path)
    else
        P.logInfoTS("Download of METAR failed for " .. metarTable.icaocode .. ": " .. tostring(responseCodeOrError))
    end
end

--------------------------------------------------------------------------------------------------------------
function P.getMetar(icaocode, metarTable)

    if not (icaocode and icaocode ~= "XXXX" and metarTable) then return end

    local metarstring = sasl.weather.getMETARForAirport(icaocode)

    if (metarstring and (metarstring ~= "") and (metarstring:sub(1, 4) == icaocode)) then
        P.logInfoTS("METAR for " .. icaocode .. " successfully loaded from X-Plane.")
        metarTable.icaocode = icaocode
        metarTable.metar.raw_text = metarstring
        metarTable.decodedmetar = helpers.decodemetar(metarstring)
        metarTable.metarfound = true
    else
        P.logInfoTS("X-Plane METAR for " .. icaocode .. " not found or invalid. Trying async web download.")
        
        local metarUrl = def.AVWEATHERFURLCSV .. icaocode
        local tempFilePath = def.YALCACHEPATH .. icaocode .. "_metar.txt"
        metarTable.icaocode = icaocode


        sasl.net.downloadFileAsync(metarUrl, tempFilePath, function(url, path, isOk, responseCodeOrError)
            P.onMetarDownloaded(url, path, isOk, responseCodeOrError, metarTable)
        end)
    end
end
--------------------------------------------------------------------------------------------------------------
function P.isGroundIcingCondition(wx_in, tat_c)
    if not wx_in and tat_c == nil then
        return false
    end

    local function normalize_temp(v)
        if v == nil then
            return nil
        elseif type(v) == "number" then
            return v
        elseif type(v) == "table" then
            if v.value ~= nil and type(v.value) == "number" then
                return v.value
            end
            if v.temp ~= nil and type(v.temp) == "number" then
                return v.temp
            end
            if v.temperature ~= nil and type(v.temperature) == "number" then
                return v.temperature
            end
        end
        return nil
    end

    local temp_c = nil
    if wx_in then
        temp_c = normalize_temp(wx_in.temp) or normalize_temp(wx_in.temperature)
    end
    if temp_c == nil and tat_c ~= nil then
        temp_c = tat_c
    end
    if temp_c == nil then
        return false
    end

    local precip = false
    if wx_in then
        if wx_in.precipitation then precip = true end
        if wx_in.freezing then precip = true end
    end

    if (not precip) and wx_in and wx_in.weather and type(wx_in.weather) == "table" then
        for _, w in ipairs(wx_in.weather) do
            local phenomenon = nil
            if type(w) == "string" then
                phenomenon = w
            elseif type(w) == "table" then
                if type(w.phenomenon) == "string" and w.phenomenon ~= "" then
                    phenomenon = w.phenomenon
                elseif type(w.code) == "string" and w.code ~= "" then
                    phenomenon = w.code
                end
            end
            if phenomenon then
                local upper = phenomenon:upper()
                if upper:find("RA", 1, true)
                or upper:find("SN", 1, true)
                or upper:find("DZ", 1, true)
                or upper:find("PL", 1, true)
                or upper:find("GR", 1, true)
                or upper:find("GS", 1, true)
                or upper:find("IC", 1, true)
                or upper:find("BR", 1, true)
                or upper:find("FG", 1, true)
                or upper:find("FZ", 1, true) then
                    precip = true
                    break
                end
            end
        end
    end

    local dew_c = nil
    if wx_in then
        dew_c = normalize_temp(wx_in.dew_point)
    end
    local dew_spread = nil
    if dew_c ~= nil then
        dew_spread = math.abs(temp_c - dew_c)
    end

    local low_cloud = false
    if wx_in and wx_in.clouds and type(wx_in.clouds) == "table" then
        for _, c in ipairs(wx_in.clouds) do
            local alt = c and c.altitude or nil
            if alt and alt > 0 and alt <= 1500 then
                low_cloud = true
                break
            end
        end
    end

    local vis_m = nil
    if wx_in and wx_in.visibility then
        if type(wx_in.visibility) == "table" then
            vis_m = wx_in.visibility.value
        else
            vis_m = wx_in.visibility
        end
    end

    local visible_moisture = precip
        or low_cloud
        or (vis_m and vis_m <= 5000)
        or (dew_spread and dew_spread <= 2)

    if temp_c <= 10 then
        if visible_moisture or temp_c <= 5 then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------------------------------------
function P.getRunwayHeadingFromDesignator(runwayDesignator)
    if not runwayDesignator or #runwayDesignator < 2 then
        sasl.logError("Error: Invalid runway designator provided: " .. tostring(runwayDesignator))
        return nil
    end

    local rwyNumberStr = string.sub(runwayDesignator, 1, 2)
    local rwyNumber = tonumber(rwyNumberStr)

    if not rwyNumber then
        sasl.logError("Error: Could not parse runway number from designator: " .. runwayDesignator)
        return nil
    end

    -- Runway Heading ist die Nummer * 10
    local heading = rwyNumber * 10
    return heading
end

--------------------------------------------------------------------------------------------------------------
local function normalizeRunwayIdForRvr(runwayDesignator)
    if type(runwayDesignator) ~= "string" or runwayDesignator == "" then
        return nil
    end

    local num_str, suffix = nil, ""
    local len = #runwayDesignator
    local i = 1
    while i <= len do
        local b = string.byte(runwayDesignator, i)
        if not b or b < 48 or b > 57 then
            break
        end
        i = i + 1
    end
    if i > 1 and i <= 3 then
        num_str = string.sub(runwayDesignator, 1, i - 1)
        if i <= len then
            local b = string.byte(runwayDesignator, i)
            local is_alpha = (b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)))
            if is_alpha then
                suffix = string.sub(runwayDesignator, i, i)
            end
        end
    end
    if not num_str then
        return nil
    end

    local num = tonumber(num_str)
    if not num or num < 1 or num > 36 then
        return nil
    end

    suffix = suffix and string.upper(suffix) or ""
    if suffix ~= "L" and suffix ~= "R" and suffix ~= "C" then
        suffix = ""
    end

    return string.format("%02d", num) .. suffix
end

local function getRvrEntryForRunway(rvrList, runwayDesignator)
    if type(rvrList) ~= "table" then
        return nil
    end

    local target = normalizeRunwayIdForRvr(runwayDesignator)
    if not target then
        return nil
    end

    local bestEntry = nil
    local bestMeters = nil

    for _, entry in ipairs(rvrList) do
        local entryRunway = normalizeRunwayIdForRvr(entry.runway or "")
        if entryRunway == target then
            local meters = entry.min and entry.min.meters
            if meters then
                local effective = meters
                if entry.min.less_than then
                    effective = math.max(0, meters - 1)
                end
                if not bestMeters or effective < bestMeters then
                    bestMeters = effective
                    bestEntry = entry
                end
            end
        end
    end

    return bestEntry
end

local function getRvrMetersForRunway(rvrList, runwayDesignator)
    local entry = getRvrEntryForRunway(rvrList, runwayDesignator)
    if not entry or not entry.min or not entry.min.meters then
        return nil
    end
    local meters = entry.min.meters
    if entry.min.less_than then
        meters = math.max(0, meters - 1)
    end
    return meters, entry
end

--------------------------------------------------------------------------------------------------------------
function P.shouldCheckRunwaySuitability(metar, runwayDesignator, navType)
    -- --- Schwellenwerte anpassbar ---
    local MAX_TAILWIND_KN = 10     -- Maximal erlaubter Rueckenwind fuer normale Landung
    local MAX_CROSSWIND_KN = 20    -- Maximal erlaubter Seitenwind (oft Flugzeug-spezifisch)
    local MIN_WIND_SPEED_FOR_CHECK = 5 -- Mindestwindstaerke, ab der Windkomponenten relevant werden

    local weatherData = metar.decodedmetar

    sasl.logDebug("Checking suitability for runway: " .. tostring(runwayDesignator)) -- sasl.logDebug ist global (angenommen)

    -- 1. Grundlegende Wetterdaten pruefen
    if not (weatherData and weatherData.wind and weatherData.wind.direction ~= nil and weatherData.wind.speed ~= nil) then
        sasl.logDebug("Warning: Insufficient wind data to check runway suitability. Returning true (default safe).")
        return true -- Wenn keine Winddaten vorhanden sind, koennen wir nicht pruefen. Annahme: Landebahn ist standardmaessig ok.
    end

    local windDirection = weatherData.wind.direction
    local windSpeed = weatherData.wind.speed

    -- Wenn Wind "calm" ist, ist die Landebahn in Bezug auf Wind immer geeignet
    if windSpeed == 0 then
        sasl.logDebug("Wind is calm. Runway is suitable based def.ON wind.") -- def ist global (angenommen)
        return true
    end

    -- Wenn der Wind sehr schwach ist, sind die Komponenteneffekte minimal
    if windSpeed < MIN_WIND_SPEED_FOR_CHECK then
          sasl.logDebug(string.format("Wind speed (%d kt) is below check threshold (%d kt). Runway is suitable based def.ON wind.", windSpeed, MIN_WIND_SPEED_FOR_CHECK))
          return true
    end

    -- Sicherstellen, dass wir eine numerische Windrichtung besitzen
    local numericWindDirection = windDirection
    if type(numericWindDirection) ~= "number" then
        local vari = weatherData.wind.variable_direction
        if vari and type(vari.dir1) == "number" and type(vari.dir2) == "number" then
            numericWindDirection = (vari.dir1 + vari.dir2) / 2
            sasl.logDebug(string.format(
                "Wind direction is variable (%s). Using averaged value %.1f° for component calculation.",
                tostring(windDirection),
                numericWindDirection
            ))
        else
            sasl.logDebug(string.format(
                "Wind direction '%s' is non-numeric and no variable range provided. Recommend manual runway suitability check.",
                tostring(windDirection)
            ))
            return false
        end
    end

    -- 2. Landebahn-Richtung ableiten
    local runwayHeading = P.getRunwayHeadingFromDesignator(runwayDesignator)
    if not runwayHeading then
        sasl.logError("Error: Could not determine runway heading from designator. Returning true (default safe).")
        return true -- Kann Landebahn nicht ableiten, kann nicht pruefen.
    end

 -- 3. Windkomponenten berechnen (Korrigiert für magnetische Konsistenz)
    --    Annahme: windDirection ist True, runwayHeading ist Magnetic
    local magnetic_variation = 0 -- Default
    if metar.latitude and metar.longitude then -- Versuche, Variation vom METAR-Ort zu bekommen
         magnetic_variation = sasl.getMagneticVariation(metar.latitude, metar.longitude) or 0
    end
    -- Konvertiere Wind zu magnetisch
    local magneticWindDirection = (numericWindDirection - magnetic_variation + 360) % 360 

    -- Berechne Komponenten mit magnetischer Windrichtung und magnetischem Runway-Heading
    local headwindComponent, crosswindKnots = P.calculateWindComponents(magneticWindDirection, runwayHeading, windSpeed)

    sasl.logDebug(string.format("Calculated for RWY %s (Mag Hdg %d): Headwind %.1f kt, Crosswind %.1f kt (from Mag Wind %03d@%dkt, True Wind %s@%dkt, MagVar %.1f)",
                                runwayDesignator, runwayHeading, headwindComponent, crosswindKnots,
                                math.floor(magneticWindDirection + 0.5), windSpeed,
                                tostring(windDirection), windSpeed, magnetic_variation))

    -- 4. Ueberpruefung der Schwellenwerte
    -- Rueckenwind (HeadwindComponent ist negativ bei Rueckenwind)
    if headwindComponent < -MAX_TAILWIND_KN then
        sasl.logDebug(string.format("Runway %s: Tailwnd (%.1f kt) exceeds max allowed (%.1f kt). Check recommended.", runwayDesignator, math.abs(headwindComponent), MAX_TAILWIND_KN))
        return false -- Rueckenwind zu stark
    end

    -- Seitenwind- KORRIGIET
    local crosswindMagnitude = math.abs(crosswindKnots) -- Get the absolute value
    if crosswindMagnitude > MAX_CROSSWIND_KN then
        -- Log the signed value for context, but compare the magnitude
        sasl.logDebug(string.format("Runway %s: Crosswind magnitude (%.1f kt, signed: %.1f kt) exceeds max allowed (%.1f kt). Check recommended.", 
                       runwayDesignator, crosswindMagnitude, crosswindKnots, MAX_CROSSWIND_KN))
        return false -- Seitenwind zu stark
    end

    local rvrMeters = nil
    if weatherData and weatherData.rvr then
        rvrMeters = getRvrMetersForRunway(weatherData.rvr, runwayDesignator)
    end

    if rvrMeters then
        local rvrThreshold = 1200
        if navType == def.NAVTYPEILS
            or navType == def.NAVTYPEGLS
            or navType == def.NAVTYPELPV then
            rvrThreshold = 550
        elseif navType == def.NAVTYPELOC
            or navType == def.NAVTYPELDA
            or navType == def.NAVTYPEIGS
            or navType == def.NAVTYPERNAV then
            rvrThreshold = 1200
        end

        if rvrMeters < rvrThreshold then
            sasl.logDebug(string.format("Runway %s: RVR %d m below threshold %d m for %s. Check recommended.",
                runwayDesignator,
                rvrMeters,
                rvrThreshold,
                tostring(navType or "unknown")))
            return false
        end
    end

    sasl.logDebug(string.format("Runway %s is suitable based on current conditions.", runwayDesignator))
    return true -- Landebahn ist innerhalb der Schwellenwerte geeignet
end

--------------------------------------------------------------------------------------------------------------
-- Nimmt jetzt runwayName ("07L", "25R", etc.)
function P.formatMetarSpeechSummary(metar, runwayName)
    local parts = {}

    local icaocode = metar.icaocode
    local metar_data = metar.decodedmetar

    if icaocode and #icaocode > 0 then
        table.insert(parts, P.spellNato(icaocode))
    end

    -- NEU: Heading aus Runway-Namen ableiten, nur wenn gültig
    local derivedHeading = nil
    -- *** VERBESSERUNG: Prüfe mit P.isvalidrwy ***
    if P.isvalidrwy(runwayName) then
        -- Versuche, die ersten zwei Ziffern zu extrahieren
        local rwyNumStr = nil
        if #runwayName >= 2 then
            local b1 = string.byte(runwayName, 1)
            local b2 = string.byte(runwayName, 2)
            if b1 and b2 and b1 >= 48 and b1 <= 57 and b2 >= 48 and b2 <= 57 then
                rwyNumStr = string.sub(runwayName, 1, 2)
            end
        end
        if rwyNumStr then
            local rwyNum = tonumber(rwyNumStr)
            if rwyNum then
                if rwyNum == 0 then -- Handle "runway 00" edge case if needed, though unlikely
                   derivedHeading = 360 -- Or handle as error depending on format
                elseif rwyNum >= 1 and rwyNum <= 36 then
                   derivedHeading = rwyNum * 10
                end
                 -- Überprüfung, ob das Ergebnis im gültigen Bereich liegt (eigentlich durch obiges check abgedeckt)
                 if not (derivedHeading and derivedHeading >= 1 and derivedHeading <= 360) then
                      derivedHeading = nil -- Ungültiges Ergebnis
                      P.logInfoTS("formatMetarSpeechSummary: Ungültiges Heading " .. tostring(derivedHeading or "nil") .. " aus Runway '" .. runwayName .. "' abgeleitet (nach Nummern-Extraktion).") -- Geändert zu logInfo
                 end
            else
                 P.logInfoTS("formatMetarSpeechSummary: Konnte Ziffern '" .. rwyNumStr .. "' aus Runway '" .. runwayName .. "' nicht in Zahl umwandeln.") -- Geändert zu logInfo
            end
        else
             P.logInfoTS("formatMetarSpeechSummary: Konnte keine Heading-Zahl aus gültiger Runway '" .. runwayName .. "' extrahieren (Parsing fehlgeschlagen).") -- Geändert zu logInfo
        end
    else
         -- Log optional, wenn ungültige Namen übergeben werden könnten
         if runwayName and runwayName ~= "" then
              P.logInfoTS("formatMetarSpeechSummary: Übergabener runwayName '".. runwayName .."' ist laut P.isvalidrwy ungültig. Keine Windkomponentenberechnung.") -- Geändert zu logInfo
         end
    end
    -- derivedHeading ist jetzt entweder eine Zahl (10-360) oder nil

    if metar_data.wind then
        local dir = metar_data.wind.direction
        local speed = metar_data.wind.speed
        local gust = metar_data.wind.gust
        local wind_part = ""

        if speed == 0 then
            wind_part = "Wind calm"
        -- GEÄNDERT: Prüfe derivedHeading und numerische Windrichtung
        elseif derivedHeading and type(dir) == "number" then
            -- Ruft die korrigierte Funktion auf, die vorzeichenbehafteten Crosswind liefert
            local headwind, crosswind = P.calculateWindComponents(dir, derivedHeading, speed)

            -- Gib den Runway-NAMEN aus
            wind_part = string.format("Wind runway %s, ", runwayName)

            -- Format Headwind/Tailwind
            if headwind >= 1 then
                wind_part = wind_part .. string.format("headwind %d knots", math.floor(headwind + 0.5))
            elseif headwind <= -1 then
                wind_part = wind_part .. string.format("tailwind %d knots", math.floor(math.abs(headwind) + 0.5))
            else
                -- Optional: "no headwind component" hinzufügen, wenn gewünscht
            end

            -- Korrigierte Crosswind-Logik
            if crosswind >= 1 then -- Positiv = Links
                if headwind >= 1 or headwind <= -1 then wind_part = wind_part .. "," end
                wind_part = wind_part .. string.format(" crosswind from left %d knots", math.floor(crosswind + 0.5))
            elseif crosswind <= -1 then -- Negativ = Rechts
                if headwind >= 1 or headwind <= -1 then wind_part = wind_part .. "," end
                wind_part = wind_part .. string.format(" crosswind from right %d knots", math.floor(math.abs(crosswind) + 0.5))
            end

             -- Füge Böen-Info hinzu, falls relevant
             if gust and gust > speed then
                  wind_part = wind_part .. string.format(" (gusting %d knots)", gust)
             end

        -- Fallback (wenn kein Heading abgeleitet werden konnte oder Wind VRB etc.)
        elseif dir == "VRB" then
            wind_part = string.format("Wind variable at %d knots", speed)
            if gust and gust > 0 then wind_part = wind_part .. string.format(" gusting %d", gust) end
        elseif type(dir) == "number" then -- Windrichtung numerisch, aber kein RWY-Heading
             wind_part = string.format("Wind %03d degrees at %d knots", dir, speed)
             if gust and gust > 0 then wind_part = wind_part .. string.format(" gusting %d", gust) end
        else -- Windrichtung ist Text (z.B. N)
             wind_part = string.format("Wind %s at %d knots", tostring(dir), speed)
             if gust and gust > 0 then wind_part = wind_part .. string.format(" gusting %d", gust) end
        end
        table.insert(parts, wind_part)
    end

    -- Rest der Funktion (Visibility, Weather, Clouds) bleibt unverändert
    if metar_data.visibility then
        local vis_val = metar_data.visibility.value
        local vis_part = "Visibility "
        local vis_prefix = ""
        if metar_data.visibility.more_than then
            vis_prefix = "more than "
        elseif metar_data.visibility.less_than then
            vis_prefix = "less than "
        end
        if metar_data.cavok then
            vis_part = "Visibility 10 kilometers or more"
        elseif vis_val >= 10000 then
            vis_part = vis_part .. "10 kilometers or more"
        elseif vis_val >= 1609 then
            vis_part = vis_part .. vis_prefix .. string.format("%d statute miles", math.floor(vis_val / 1609.34 + 0.5))
        elseif vis_val >= 1000 then
            vis_part = vis_part .. vis_prefix .. string.format("%d kilometers", math.floor(vis_val / 1000 + 0.5))
        else
            vis_part = vis_part .. vis_prefix .. string.format("%d meters", vis_val)
        end
        if metar_data.visibility.directional then
             vis_part = vis_part .. string.format(" specific %d meters to the %s",
                                 metar_data.visibility.directional.value,
                                 metar_data.visibility.directional.direction)
        end
        table.insert(parts, vis_part)
    end

    if metar_data.rvr then
        local rvr_entry = getRvrEntryForRunway(metar_data.rvr, runwayName)
        if rvr_entry and rvr_entry.min and rvr_entry.min.value then
            local unit_label = (rvr_entry.unit == "FT") and "feet" or "meters"
            local function format_rvr_value(value)
                if not value then
                    return nil
                end
                local prefix = ""
                if value.more_than then
                    prefix = "more than "
                elseif value.less_than then
                    prefix = "less than "
                end
                return prefix .. tostring(value.value)
            end

            local min_str = format_rvr_value(rvr_entry.min)
            local rvr_part = nil
            if rvr_entry.max and rvr_entry.max.value then
                local max_str = format_rvr_value(rvr_entry.max)
                rvr_part = string.format("RVR runway %s, variable %s to %s %s", runwayName, min_str, max_str, unit_label)
            else
                rvr_part = string.format("RVR runway %s, %s %s", runwayName, min_str, unit_label)
            end

            if rvr_entry.trend == "U" then
                rvr_part = rvr_part .. ", increasing"
            elseif rvr_entry.trend == "D" then
                rvr_part = rvr_part .. ", decreasing"
            elseif rvr_entry.trend == "N" then
                rvr_part = rvr_part .. ", no change"
            end

            if rvr_part then
                table.insert(parts, rvr_part)
            end
        end
    end

    if metar_data.weather and #metar_data.weather > 0 then
        local weather_desc = {}
        for _, wx_entry in ipairs(metar_data.weather) do
            local intensity = ""
            if wx_entry.intensity == "light" then intensity = "light "
            elseif wx_entry.intensity == "heavy" then intensity = "heavy " end
            local phenomenon = wx_entry.phenomenon
            if phenomenon == "RA" then phenomenon = "rain"
            elseif phenomenon == "SN" then phenomenon = "snow"
            elseif phenomenon == "DZ" then phenomenon = "drizzle"
            elseif phenomenon == "FG" then phenomenon = "fog"
            elseif phenomenon == "BR" then phenomenon = "mist"
            elseif phenomenon == "HZ" then phenomenon = "haze"
            elseif phenomenon == "TS" then phenomenon = "thunderstorm"
            -- Füge hier bei Bedarf weitere Übersetzungen hinzu
            end
            table.insert(weather_desc, intensity .. phenomenon)
        end
        if #weather_desc > 0 then
            table.insert(parts, "Currently " .. table.concat(weather_desc, " and "))
        end
    end

    if metar_data.clouds and #metar_data.clouds > 0 then
        if metar_data.cavok then
             table.insert(parts, "sky clear")
        else
            local cloud_reports = {}
            for _, cloud in ipairs(metar_data.clouds) do
                local coverage_str = cloud.coverage
                local altitude_ft = cloud.altitude
                local readable_coverage = coverage_str

                if coverage_str == "FEW" then readable_coverage = "few"
                elseif coverage_str == "SCT" then readable_coverage = "scattered"
                elseif coverage_str == "BKN" then readable_coverage = "broken"
                elseif coverage_str == "OVC" then readable_coverage = "overcast"
                elseif coverage_str == "SKC" or coverage_str == "CLR" then readable_coverage = "sky clear"
                elseif coverage_str == "NSC" then readable_coverage = "no significant clouds"
                elseif coverage_str == "VV" then readable_coverage = "vertical visibility"
                end

                local report_str = ""
                if readable_coverage == "sky clear" or readable_coverage == "no significant clouds" then
                    report_str = readable_coverage
                elseif readable_coverage == "vertical visibility" and altitude_ft then
                    report_str = string.format("%s %d feet", readable_coverage, altitude_ft)
                elseif altitude_ft then
                    report_str = string.format("%s clouds at %d feet", readable_coverage, altitude_ft)
                else
                    report_str = readable_coverage -- Falls keine Höhe angegeben ist
                end

                if cloud.type and cloud.type ~= "" then
                    local trimmedType = cloud.type:gsub("%s+", "")
                    if trimmedType:find("%w") then
                        report_str = report_str .. " (" .. trimmedType .. ")"
                    end
                end

                if report_str ~= "" then
                    table.insert(cloud_reports, report_str)
                end
            end
            if #cloud_reports > 0 then
                table.insert(parts, table.concat(cloud_reports, ", "))
            end
        end
    end

    if metar_data.pressure and metar_data.pressure.qnh_hpa then
        local qnhHpa = tonumber(metar_data.pressure.qnh_hpa)
        if qnhHpa then
            local qnhText = nil
            local useHpa = false
            if yal and yal.baroinhpa then
                useHpa = (get(yal.baroinhpa) == def.ON)
            end
            if useHpa then
                qnhText = P.formatQnhValue(qnhHpa, true)
            else
                qnhText = P.formatQnhValue(P.convertpressure(qnhHpa), false)
            end
            if qnhText then
                table.insert(parts, "Q N H " .. P.addspaces(qnhText))
            end
        end
    end

    local filtered_parts = {}
    for _, part in ipairs(parts) do
        if type(part) == "string" and part:find("%w") then
            table.insert(filtered_parts, part)
        end
    end

    return table.concat(filtered_parts, ". ") -- Punkt als Trenner
end

--------------------------------------------------------------------------------------------------------------
function P.formatWindSpeechSummary(metar, latpos, lonpos)


    if (not metar or not metar.decodedmetar or not metar.decodedmetar.wind or not metar.decodedmetar.wind.direction or (type(metar.decodedmetar.wind.speed) ~= "number")) then
        return nil
    end

    local wind_data = metar.decodedmetar.wind

    if wind_data.speed <= 2 then
        return "Wind calm."
    end

    local magnetic_variation = sasl.getMagneticVariation(latpos, lonpos)
    
    local report_parts = {"Wind"}

    local function correct_and_round(true_dir)
        local magnetic_dir = true_dir + magnetic_variation
        local rounded_dir = math.floor((magnetic_dir / 10) + 0.5) * 10
        rounded_dir = (rounded_dir - 1 + 360) % 360 + 1
        if rounded_dir == 0 then rounded_dir = 360 end
        return rounded_dir
    end

    if wind_data.direction == "VRB" then
        table.insert(report_parts, "variable")
    elseif wind_data.variable_direction then
        local mag_dir1 = correct_and_round(wind_data.variable_direction.dir1)
        local mag_dir2 = correct_and_round(wind_data.variable_direction.dir2)
        table.insert(report_parts, "variable between " .. string.format("%03d", mag_dir1) .. " and " .. string.format("%03d", mag_dir2))
    else
        local magnetic_direction = correct_and_round(wind_data.direction)
        table.insert(report_parts, string.format("%03d", magnetic_direction))
    end

    table.insert(report_parts, "at")
    table.insert(report_parts, wind_data.speed)

    if wind_data.gust and wind_data.gust > wind_data.speed then
        table.insert(report_parts, "gusting")
        table.insert(report_parts, wind_data.gust)
    end

    table.insert(report_parts, "knots.")

    return table.concat(report_parts, " ")
end

--------------------------------------------------------------------------------------------------------------
function P.calculateAirDensity(weatherData)
    local SPECIFIC_GAS_CONSTANT_DRY_AIR = 287.05
    
    if not (weatherData and weatherData.pressure and weatherData.pressure.qnh_hpa and
            weatherData.temperature and weatherData.temperature.value ~= nil) then
        return 1.225
    end

    local pressureHPa = weatherData.pressure.qnh_hpa
    local temperatureKelvin = weatherData.temperature.value + 273.15

    local airDensity = (pressureHPa * 100) / (SPECIFIC_GAS_CONSTANT_DRY_AIR * temperatureKelvin)

    return airDensity
end

--------------------------------------------------------------------------------------------------------------
function P.calculateDensityAltitude(fieldElevationMeters, temperatureCelsius, pressureHPa)
    local STANDARD_PRESSURE_HPA = 1013.25
    local STANDARD_TEMPERATURE_CELSIUS = 15
    local METERS_TO_FEET = 3.28084

    local fieldElevationFt = fieldElevationMeters * METERS_TO_FEET

    if type(fieldElevationFt) ~= "number" or type(temperatureCelsius) ~= "number" or type(pressureHPa) ~= "number" then
        return 0
    end

    local temperatureDeviation = temperatureCelsius - STANDARD_TEMPERATURE_CELSIUS
    local pressureAltitude = fieldElevationFt + (STANDARD_PRESSURE_HPA - pressureHPa) * 30

    local densityAltitude = pressureAltitude + (temperatureDeviation * 120)
    return densityAltitude
end

--------------------------------------------------------------------------------------------------------------
function P.calculateWindComponents(windDirectionDegrees, runwayHeadingDegrees, windSpeedKnots)
    if type(windDirectionDegrees) ~= "number" or type(runwayHeadingDegrees) ~= "number" or type(windSpeedKnots) ~= "number" then
        return 0, 0 -- Return zero for invalid inputs
    end

    -- 1. Calculate relative angle (wind relative to runway)
    local relativeAngle = runwayHeadingDegrees - windDirectionDegrees

    -- 2. Normalize angle to +/- 180 degrees
    --    Ensures the angle represents the shortest way around the compass
    while relativeAngle > 180 do relativeAngle = relativeAngle - 360 end
    while relativeAngle <= -180 do relativeAngle = relativeAngle + 360 end -- Use <= to include -180

    -- 3. Convert to radians for Lua's math functions
    local relativeAngleRad = math.rad(relativeAngle)

    -- 4. Calculate headwind/tailwind component
    --    cos(0)=1 (pure headwind), cos(180)=-1 (pure tailwind), cos(90)=0
    --    Result is positive for headwind component, negative for tailwind component
    local headwindComponent = math.cos(relativeAngleRad) * windSpeedKnots

    -- 5. Calculate SIGNED crosswind component (NO math.abs!)
    --    sin(90)=1 (wind from left), sin(-90)=-1 (wind from right), sin(0)=0
    --    Result is positive for left crosswind, negative for right crosswind
    local crosswindComponent = math.sin(relativeAngleRad) * windSpeedKnots

    -- Return signed components
    return headwindComponent, crosswindComponent
end

--------------------------------------------------------------------------------------------------------------
function P.calculateStallSpeed(weightKg, weatherData, flapsSetting)
    local GRAVITY = 9.80665
    local WING_AREA_737 = 124.6
    local METER_PER_SECOND_TO_KNOTS = 1.94384
    
    local MAX_LIFT_COEFFICIENT_VALUES = {
        [0] = 1.6, [1] = 1.7, [5] = 1.8, [10] = 2.0,
        [15] = 2.2, [20] = 2.4, [25] = 2.6, [30] = 2.8, [40] = 3.0
    }
    local DEFAULT_MAX_LIFT_COEFFICIENT = 2.5

    local maxLiftCoefficient = MAX_LIFT_COEFFICIENT_VALUES[flapsSetting] or DEFAULT_MAX_LIFT_COEFFICIENT
    local airDensity = P.calculateAirDensity(weatherData)

    if airDensity <= 0 or maxLiftCoefficient <= 0 or WING_AREA_737 <= 0 or weightKg <= 0 then
        return 0
    end

    local stallSpeedMps = math.sqrt((2 * weightKg * GRAVITY) / (airDensity * WING_AREA_737 * maxLiftCoefficient))
    local stallSpeedKnots = stallSpeedMps * METER_PER_SECOND_TO_KNOTS

    return stallSpeedKnots
end

--------------------------------------------------------------------------------------------------------------
local function toNumber(value, default)
    if value == nil then
        return default
    end

    local valueType = type(value)

    if valueType == "number" then
        return value
    elseif valueType == "string" then
        local num = tonumber(value)
        return num or default
    elseif valueType == "boolean" then
        return value and 1 or 0
    elseif valueType == "table" then
        if value.value ~= nil then
            return toNumber(value.value, default)
        end
    elseif valueType == "userdata" then
        local ok, result = pcall(get, value)
        if ok and type(result) == "number" then
            return result
        end
    end

    local num = tonumber(value)
    return num or default
end

local function normalizeWeatherCode(entry)
    if type(entry) == "table" then
        if entry.code then
            return tostring(entry.code):upper()
        end
        local parts = {}
        if entry.intensity and entry.intensity ~= "" then
            table.insert(parts, tostring(entry.intensity))
        end
        if entry.descriptor and entry.descriptor ~= "" then
            table.insert(parts, tostring(entry.descriptor))
        end
        if entry.phenomenon and entry.phenomenon ~= "" then
            table.insert(parts, tostring(entry.phenomenon))
        end
        if #parts > 0 then
            return table.concat(parts):upper()
        end
    elseif type(entry) == "string" then
        return entry:upper()
    end
    return nil
end

local function weatherListHasPhenomenon(weatherList, targets)
    if type(weatherList) ~= "table" or #weatherList == 0 then
        return false
    end
    for _, entry in ipairs(weatherList) do
        local code = normalizeWeatherCode(entry)
        if code then
            for _, needle in ipairs(targets) do
                if code:find(needle, 1, true) then
                    return true
                end
            end
        end
    end
    return false
end

function P.determineTakeoffFlapsSetting(totalweightkgs, deprwylen, deprwyheading, elevation, metar, baseFlaps)
    local baseFlapsNum = toNumber(baseFlaps, 5)
    if baseFlapsNum <= 0 then
        baseFlapsNum = 5
    end
    local STANDARD_TAKEOFF_FLAPS = baseFlapsNum
    local TAKEOFF_WEIGHT_THRESHOLD_HIGH = 65000
    local TAKEOFF_WEIGHT_THRESHOLD_VERY_HIGH = 70000

    local TAKEOFF_RUNWAY_LENGTH_SHORT_THRESHOLD = 2000
    local TAKEOFF_RUNWAY_LENGTH_VERY_SHORT_THRESHOLD = 1600

    local TAKEOFF_DENSITY_ALTITUDE_THRESHOLD_HIGH = 3000

    local TAKEOFF_TAILWIND_CONSIDERATION_THRESHOLD = 5
    -- local TAKEOFF_WET_RUNWAY_PENALTY_FLAPS = 1 -- Not currently used directly, logic adds flap step

    local totalWeightKg = toNumber(totalweightkgs, 0)
    local runwayLengthMeters = toNumber(deprwylen, 0)
    local runwayHeading = toNumber(deprwyheading, 0)
    local airportElevationMeters = toNumber(elevation, 0)

    P.logInfoTS(string.format("determineTakeoffFlapsSetting: inputs weight=%.0f kg, rwyLen=%.0f m, rwyHdg=%s, elev=%.0f m, baseFlaps=%s",
        totalWeightKg, runwayLengthMeters, tostring(runwayHeading), airportElevationMeters, tostring(baseFlaps)))

    if totalWeightKg <= 0 or runwayLengthMeters <= 0 then
        P.logInfoTS("determineTakeoffFlapsSetting: Invalid input parameters (weight, length, elevation, heading), returning default flaps " .. STANDARD_TAKEOFF_FLAPS)
        return STANDARD_TAKEOFF_FLAPS
    end

    local weatherData = (metar and metar.decodedmetar) or {}
    local windInfo = weatherData.wind or {}
    local rawWindDirection = toNumber(windInfo.direction, nil)
    if rawWindDirection == nil and type(windInfo.direction) == "string" then
        local dirStr = windInfo.direction:upper()
        if dirStr ~= "" and dirStr ~= "VRB" then
            rawWindDirection = toNumber(dirStr, nil)
        end
    end
    local windSpeed = toNumber(windInfo.speed, 0)
    if windSpeed < 0 then windSpeed = 0 end

    local temperatureC = toNumber(weatherData.temperature and weatherData.temperature.value, 15)
    local qnhHpa = toNumber(weatherData.pressure and weatherData.pressure.qnh_hpa, 1013.25)

    -- Determine if runway is likely wet/contaminated
    local isRunwayWet = weatherListHasPhenomenon(weatherData.weather, {"RA", "DZ", "SN", "FZ", "TS"})
    if not isRunwayWet and temperatureC < 1 then
        isRunwayWet = true
    end
    if isRunwayWet then sasl.logDebug("determineTakeoffFlapsSetting: Runway considered wet/contaminated based on METAR.") end

    -- Start with FMC/Zibo base flaps if provided, else standard
    local recommendedFlaps = STANDARD_TAKEOFF_FLAPS

    -- Calculate wind components (using magnetic)
    local headwindComponent = 0
    local crosswindComponent = 0 -- Although not used, calculate for completeness
    if rawWindDirection and windSpeed > 0 and runwayHeading ~= nil then -- Only calculate if wind is numeric and has speed
        -- Get magnetic variation
        local magnetic_variation = 0
        local metarLat = toNumber(metar and metar.latitude, nil)
        local metarLon = toNumber(metar and metar.longitude, nil)
        if metarLat and metarLon then
            magnetic_variation = sasl.getMagneticVariation(metarLat, metarLon) or 0
        end

        -- Correct wind direction to magnetic
        local magneticWindDirection = (rawWindDirection - magnetic_variation + 360) % 360

        -- Calculate components using MAGNETIC wind and MAGNETIC runway heading
        headwindComponent, crosswindComponent = P.calculateWindComponents(
            magneticWindDirection,
            runwayHeading,
            windSpeed
        )

        sasl.logDebug(string.format("Takeoff Flaps Calc: TrueWind=%s@%dkt, MagVar=%.1f, MagWind=%03d@%dkt, RwyHdg=%d -> Headwind=%.1f kt, Crosswind=%.1f kt",
                        tostring(rawWindDirection), windSpeed, magnetic_variation, math.floor(magneticWindDirection+0.5), windSpeed, runwayHeading, headwindComponent, crosswindComponent))
    else
         sasl.logDebug("Takeoff Flaps Calc: Wind is VRB, Calm, or direction not numeric. Using 0 for components.")
    end

    -- Adjust flaps based on weight
    if totalWeightKg > TAKEOFF_WEIGHT_THRESHOLD_VERY_HIGH then
        recommendedFlaps = 15
        sasl.logDebug("Takeoff Flaps Calc: Weight > VERY_HIGH threshold -> Base flaps 15")
    elseif totalWeightKg > TAKEOFF_WEIGHT_THRESHOLD_HIGH then
        recommendedFlaps = math.max(recommendedFlaps, 10)
        sasl.logDebug("Takeoff Flaps Calc: Weight > HIGH threshold -> Base flaps increased to " .. recommendedFlaps)
    end

    -- Adjust flaps based on runway length
    if runwayLengthMeters < TAKEOFF_RUNWAY_LENGTH_VERY_SHORT_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 15)
        sasl.logDebug("Takeoff Flaps Calc: Runway < VERY_SHORT threshold -> Flaps increased to " .. recommendedFlaps)
    elseif runwayLengthMeters < TAKEOFF_RUNWAY_LENGTH_SHORT_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 10)
        sasl.logDebug("Takeoff Flaps Calc: Runway < SHORT threshold -> Flaps increased to " .. recommendedFlaps)
    end

    -- Adjust flaps based on density altitude
    local densityAltitudeFeet = P.calculateDensityAltitude(
        airportElevationMeters,
        temperatureC,
        qnhHpa
    )
    sasl.logDebug(string.format("Takeoff Flaps Calc: Density Altitude calculated: %.0f ft", densityAltitudeFeet))
    if densityAltitudeFeet > TAKEOFF_DENSITY_ALTITUDE_THRESHOLD_HIGH then -- Threshold in feet
        recommendedFlaps = math.max(recommendedFlaps, 10)
        sasl.logDebug("Takeoff Flaps Calc: Density Altitude > HIGH threshold -> Flaps increased to " .. recommendedFlaps)
    end

    -- Adjust flaps for tailwind
    if headwindComponent < -TAKEOFF_TAILWIND_CONSIDERATION_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 10)
        sasl.logDebug("Takeoff Flaps Calc: Tailwind > Threshold -> Flaps increased to " .. recommendedFlaps)
    end

    -- Adjust flaps for wet runway (increase by one step)
    if isRunwayWet then
        if recommendedFlaps == 5 then
            recommendedFlaps = 10
            sasl.logDebug("Takeoff Flaps Calc: Wet runway -> Flaps increased from 5 to 10")
        elseif recommendedFlaps == 10 then
            recommendedFlaps = 15
            sasl.logDebug("Takeoff Flaps Calc: Wet runway -> Flaps increased from 10 to 15")
        elseif recommendedFlaps == 15 then
             sasl.logDebug("Takeoff Flaps Calc: Wet runway -> Flaps already 15, no change.")
             -- Consider if Flaps 25 might be needed in extreme cases (short, wet, heavy, high DA) - outside simple logic
        end
    end

    -- Crosswind consideration: keep flaps lower for strong crosswind
    if math.abs(crosswindComponent) > 20 then
        recommendedFlaps = math.min(recommendedFlaps, 5)
        sasl.logDebug("Takeoff Flaps Calc: Strong crosswind -> Limiting flaps to 5")
    end

    -- Final constraints (ensure flaps are 5, 10, or 15)
    -- Clamp to max 15 first
    if recommendedFlaps > 15 then
        recommendedFlaps = 15
    end
    -- Then ensure it's one of the discrete steps
    if recommendedFlaps < 10 and recommendedFlaps > 5 then
        recommendedFlaps = 10 -- Round up between 5 and 10
    elseif recommendedFlaps < 5 then
         recommendedFlaps = 5 -- Minimum is 5
    elseif recommendedFlaps > 10 and recommendedFlaps < 15 then
         recommendedFlaps = 15 -- Round up between 10 and 15
    end

    P.logInfoTS("determineTakeoffFlapsSetting: Recommended flaps setting: " .. recommendedFlaps)
    return recommendedFlaps
end

--------------------------------------------------------------------------------------------------------------
function P.calcappflapsvref(totalweightkgs, desrwylen, desrwyheading, baseVref, metar, baseFlaps)

    local totalWeightKg = toNumber(totalweightkgs, 0)
    local runwayLengthMeters = toNumber(desrwylen, 0)
    local runwayHeading = toNumber(desrwyheading, 0)
    local targetFlaps = toNumber(baseFlaps, 30)
    local targetVref = toNumber(baseVref, 0)

    if targetVref <= 0 then
        -- fallback
        targetVref = 140
    end

    if totalWeightKg <= 0 or runwayLengthMeters <= 0 then
        P.logInfoTS("calcappflapsvref: Invalid input parameters, returning base " .. tostring(targetFlaps) .. "/" .. tostring(targetVref))
        return targetFlaps, targetVref
    end

    local weatherData = (metar and metar.decodedmetar) or {}
    local windInfo = weatherData.wind or {}
    local rawWindDirection = toNumber(windInfo.direction, nil)
    if rawWindDirection == nil and type(windInfo.direction) == "string" then
        local dirStr = windInfo.direction:upper()
        if dirStr ~= "" and dirStr ~= "VRB" then
            rawWindDirection = toNumber(dirStr, nil)
        end
    end
    local windSpeed = toNumber(windInfo.speed, 0)
    if windSpeed < 0 then windSpeed = 0 end
    weatherData.wind = weatherData.wind or {}
    weatherData.wind.speed = windSpeed

    local headwindComponent = 0
    local crosswindKnots = 0
    local tailwindKnots = 0
    if rawWindDirection and windSpeed > 0 and runwayHeading ~= nil then
        local magnetic_variation = 0
        local metarLat = toNumber(metar and metar.latitude, nil)
        local metarLon = toNumber(metar and metar.longitude, nil)
        if metarLat and metarLon then
            magnetic_variation = sasl.getMagneticVariation(metarLat, metarLon) or 0
        end

        local magneticWindDirection = (rawWindDirection - magnetic_variation + 360) % 360
        headwindComponent, crosswindKnots = P.calculateWindComponents(
            magneticWindDirection,
            runwayHeading,
            windSpeed
        )
        tailwindKnots = math.max(-headwindComponent, 0)
        sasl.logDebug(string.format("App Flaps Calc: TrueWind=%s@%dkt, MagVar=%.1f, MagWind=%03d@%dkt, RwyHdg=%d -> Headwind=%.1f kt, Crosswind=%.1f kt",
                        tostring(rawWindDirection), windSpeed, magnetic_variation, math.floor(magneticWindDirection+0.5), windSpeed, runwayHeading, headwindComponent, crosswindKnots))
    else
        sasl.logDebug("App Flaps Calc: Wind is VRB, Calm, or direction not numeric. Using 0 for components.")
    end

    local hasPrecip = weatherListHasPhenomenon(weatherData.weather, {"TS", "SN", "FZ", "RA", "DZ"})
    local visibilityMeters = nil
    if weatherData.visibility then
        if type(weatherData.visibility) == "table" then
            visibilityMeters = toNumber(weatherData.visibility.value, nil)
        else
            visibilityMeters = toNumber(weatherData.visibility, nil)
        end
    end
    if not hasPrecip and visibilityMeters and visibilityMeters < 5000 then
        hasPrecip = true
        sasl.logDebug("App Flaps Calc: Treating low visibility as adverse condition.")
    end

    -- Custom adjustments: moderate deltas on top of FMC/Zibo baseline
    local shortRunway = (runwayLengthMeters > 0 and runwayLengthMeters < 2000)
    local crosswindMag = math.abs(crosswindKnots)

    if shortRunway or hasPrecip or tailwindKnots > 5 then
        targetFlaps = math.max(targetFlaps, 40)
    end
    if crosswindMag > 15 then
        targetFlaps = math.min(targetFlaps, 30)
    end

    local vrefAdd = 0
    if hasPrecip then vrefAdd = vrefAdd + 5 end
    if crosswindMag > 15 then vrefAdd = vrefAdd + 5 end
    if tailwindKnots > 5 then vrefAdd = vrefAdd + 5 end
    if shortRunway then vrefAdd = vrefAdd + 2 end
    vrefAdd = math.min(vrefAdd, 10)
    targetVref = targetVref + vrefAdd

    targetFlaps = math.floor(targetFlaps + 0.5)
    targetVref = math.floor(targetVref + 0.5)

    P.logInfoTS(string.format("calcappflapsvref: Base Flaps/Vref %s/%s -> Custom %d/%d (add %d kts, wx=%s, tail=%.1f, xwind=%.1f)",
        tostring(baseFlaps), tostring(baseVref), targetFlaps, targetVref, vrefAdd, tostring(hasPrecip), tailwindKnots, crosswindKnots))

    return targetFlaps, targetVref
end

--------------------------------------------------------------------------------------------------------------
-- Compute recommended approach wind correction (B737-style: 1/2 headwind + gust increment, capped)
function P.calculateApproachWindCorrection(runwayHeadingMag, metar)
    local runwayHeading = toNumber(runwayHeadingMag, nil)
    if not runwayHeading then
        return nil
    end

    local weatherData = (metar and metar.decodedmetar) or {}
    local windInfo = weatherData.wind or {}
    local rawDir = windInfo.direction
    local windDir = toNumber(rawDir, nil)
    if (not windDir) and type(rawDir) == "string" then
        local dirStr = rawDir:upper()
        if dirStr ~= "" and dirStr ~= "VRB" then
            windDir = toNumber(dirStr, nil)
        end
    end

    local windSpeed = toNumber(windInfo.speed, 0) or 0
    if windSpeed < 0 then windSpeed = 0 end
    local gust = toNumber(windInfo.gust, 0) or 0
    if gust < 0 then gust = 0 end

    if (not windDir) or windSpeed == 0 then
        return nil
    end

    local magVar = 0
    local metarLat = toNumber(metar and metar.latitude, nil)
    local metarLon = toNumber(metar and metar.longitude, nil)
    if metarLat and metarLon then
        magVar = sasl.getMagneticVariation(metarLat, metarLon) or 0
    end
    local magneticWindDirection = (windDir - magVar + 360) % 360

    local headwind = 0
    headwind = P.calculateWindComponents(magneticWindDirection, runwayHeading, windSpeed)

    local gustIncrement = 0
    if gust > windSpeed then
        gustIncrement = gust - windSpeed
    end

    local additive = math.max(headwind / 2, 0) + gustIncrement
    additive = math.max(additive, 0)
    additive = math.min(additive, 20) -- Boeing cap

    return math.floor(additive + 0.5)
end

--------------------------------------------------------------------------------------------------------------
function P.determineLandingFlapsSetting(runwayLengthMeters, tailwindKnots, crosswindKnots, isBadWeather, weightKg)
    local LANDING_SHORT_RUNWAY_THRESHOLD = 2000
    local LANDING_HIGH_TAILWIND_THRESHOLD = 5 -- Consider Flaps 40 if tailwind exceeds 5 kts
    local LANDING_HIGH_CROSSWIND_THRESHOLD = 15
    local LANDING_HIGH_WEIGHT_THRESHOLD = 55000 -- In Kg

    local crosswindMagnitude = math.abs(crosswindKnots)
    local tailwindMagnitude = math.max(tailwindKnots or 0, 0)

    P.logInfoTS(string.format("determineLandingFlapsSetting: Inputs RwyLen=%.0f m, Tailwind=%.1f kts, XWind=%.1f kts (signed %.1f), BadWx=%s, Weight=%.0f kg",
                   runwayLengthMeters, tailwindMagnitude, crosswindMagnitude, crosswindKnots, tostring(isBadWeather), weightKg))

    local requiresFlaps40 =
        (runwayLengthMeters > 0 and runwayLengthMeters < LANDING_SHORT_RUNWAY_THRESHOLD) or
        (tailwindMagnitude > LANDING_HIGH_TAILWIND_THRESHOLD) or
        isBadWeather or
        (weightKg or 0) > LANDING_HIGH_WEIGHT_THRESHOLD

    if crosswindMagnitude > LANDING_HIGH_CROSSWIND_THRESHOLD and not (runwayLengthMeters > 0 and runwayLengthMeters < LANDING_SHORT_RUNWAY_THRESHOLD) then
        P.logInfoTS("determineLandingFlapsSetting: High crosswind detected - preferring Flaps 30 for controllability.")
        return 30
    end

    if requiresFlaps40 then
        P.logInfoTS("determineLandingFlapsSetting: Recommending Flaps 40 due to landing distance factors.")
        return 40
    end

    P.logInfoTS("determineLandingFlapsSetting: Conditions nominal - recommending Flaps 30.")
    return 30
end

--------------------------------------------------------------------------------------------------------------
function P.calculateVref(weightKg, flapsSetting, weatherData, crosswindKnots) -- Receives SIGNED crosswind
    local VREF_STALL_SPEED_FACTOR = 1.37
    local VREF_WIND_ADDITION = 5 -- Typically half the headwind + full gust increment, but 5 is a common simplification
    local VREF_PRECIPITATION_ADDITION = 5
    local VREF_CROSSWIND_THRESHOLD_FOR_ADDITION = 10 -- Example threshold (adjust as needed)
    local VREF_CROSSWIND_ADDITION = 5           -- Example additive if crosswind > threshold
    local LANDING_HIGH_WIND_THRESHOLD_FOR_VREF = 20


    local stallSpeedKnots = P.calculateStallSpeed(weightKg, weatherData, flapsSetting)
    local vrefKnots = stallSpeedKnots * VREF_STALL_SPEED_FACTOR

    -- Additive for general wind speed (could refine to use headwind component if desired)
    if weatherData.wind and weatherData.wind.speed and weatherData.wind.speed > LANDING_HIGH_WIND_THRESHOLD_FOR_VREF then -- Use the constant defined earlier
        vrefKnots = vrefKnots + VREF_WIND_ADDITION
        sasl.logDebug(string.format("Vref Calc: Added %d kts for high wind.", VREF_WIND_ADDITION))
    end

    -- Additive for precipitation
    local hasPrecipitation = weatherListHasPhenomenon(weatherData.weather, {"RA", "SN", "DZ", "FZ", "GR", "GS"})
    if hasPrecipitation then
        vrefKnots = vrefKnots + VREF_PRECIPITATION_ADDITION
        sasl.logDebug(string.format("Vref Calc: Added %d kts for precipitation.", VREF_PRECIPITATION_ADDITION))
    end

    -- *** KORRIGIERTER Crosswind Additive Check ***
    local crosswindMagnitude = math.abs(crosswindKnots)
    if crosswindMagnitude > VREF_CROSSWIND_THRESHOLD_FOR_ADDITION then -- Compare magnitude to threshold
        vrefKnots = vrefKnots + VREF_CROSSWIND_ADDITION
        sasl.logDebug(string.format("Vref Calc: Added %d kts for high crosswind (%.1f kts > %.0f kts).", VREF_CROSSWIND_ADDITION, crosswindMagnitude, VREF_CROSSWIND_THRESHOLD_FOR_ADDITION))
    end
    -- *** ENDE KORREKTUR ***

    sasl.logDebug(string.format("Vref Calc: Stall=%.1f, Base Vref=%.1f, Final Vref=%.1f", stallSpeedKnots, stallSpeedKnots * VREF_STALL_SPEED_FACTOR, vrefKnots))
    return vrefKnots
end

--------------------------------------------------------------------------------------------------------------
function P.calcautobrake(landingSpeed, totalweightkgs, desrwylen, metar, customAdjust)
    local autobrakeSettings = {
        {maxDeceleration = 1.5, setting = def.AUTOBRAKE1},
        {maxDeceleration = 2.0, setting = def.AUTOBRAKE2},
        {maxDeceleration = 3.0, setting = def.AUTOBRAKE3},
        {maxDeceleration = 4.0, setting = def.AUTOBRAKEMAX}
    }

    local weatherData = metar.decodedmetar

    -- Normalize inputs: speed in m/s, runway length in meters (convert if value looks like feet)
    local landingSpeedMps = (tonumber(landingSpeed) or 0) * 0.514444
    local runwayLengthMeters = tonumber(desrwylen) or 0
    if runwayLengthMeters > 5000 then -- likely feet
        runwayLengthMeters = runwayLengthMeters * 0.3048
    end
    if runwayLengthMeters <= 0 or landingSpeedMps <= 0 then
        sasl.logDebug("calcautobrake: invalid inputs, fallback to Autobrake 2")
        return def.AUTOBRAKE2
    end

    local requiredDeceleration = (landingSpeedMps ^ 2) / (2 * runwayLengthMeters)
    local appliedMultiplier = 1

    if ((P.fieldexists(weatherData, "weather") and ((P.containsvalue(weatherData.weather, "FZRA")) or (P.containsvalue(weatherData.weather, "FZDZ")) or (P.containsvalue(weatherData.weather, "FZFG"))))
        or (P.fieldexists(weatherData, "temperature.value") and (weatherData.temperature.value < 1))) then
        requiredDeceleration = requiredDeceleration * 1.5
        appliedMultiplier = appliedMultiplier * 1.5
    elseif (P.fieldexists(weatherData, "weather") and (P.containsvalue(weatherData.weather, "SN")))  then
        requiredDeceleration = requiredDeceleration * 1.3
        appliedMultiplier = appliedMultiplier * 1.3
    elseif (P.fieldexists(weatherData, "weather") and (P.containsvalue(weatherData.weather, "RA"))) then
        requiredDeceleration = requiredDeceleration * 1.2
        appliedMultiplier = appliedMultiplier * 1.2
    end

    local weightFactor = totalweightkgs / 70000
    requiredDeceleration = requiredDeceleration * weightFactor
    appliedMultiplier = appliedMultiplier * weightFactor

    if customAdjust and weatherData then
        if P.containsvalue(weatherData.weather, "RA") or P.containsvalue(weatherData.weather, "SN") or P.containsvalue(weatherData.weather, "FZRA") then
            requiredDeceleration = requiredDeceleration * 1.1
            appliedMultiplier = appliedMultiplier * 1.1
        end
        if desrwylen > 0 and desrwylen < 1800 then
            requiredDeceleration = requiredDeceleration * 1.05
            appliedMultiplier = appliedMultiplier * 1.05
        end
    end

    local chosenSetting = def.AUTOBRAKEMAX
    for _, setting in ipairs(autobrakeSettings) do
        if requiredDeceleration <= setting.maxDeceleration then
            chosenSetting = setting.setting
            break
        end
    end

    if chosenSetting == def.AUTOBRAKEMAX and requiredDeceleration <= autobrakeSettings[#autobrakeSettings].maxDeceleration then
        chosenSetting = def.AUTOBRAKEMAX
    end

    P.logInfoTS(string.format(
        "calcautobrake: vref=%.0f kts, weight=%.0f kg, rwyLen=%.0f m, custom=%s, multiplier=%.2f, reqDecel=%.2f -> AutoBrake %s",
        tonumber(landingSpeed) or 0,
        totalweightkgs or 0,
        runwayLengthMeters,
        tostring(customAdjust),
        appliedMultiplier,
        requiredDeceleration,
        (chosenSetting == def.AUTOBRAKEMAX) and "MAX" or tostring(chosenSetting - 1)
    ))

    return chosenSetting
end


--------------------------------------------------------------------------------------------------------------
function P.getdistance(lat1, lon1, lat2, lon2)
    local R = 3440.065
    local lat1_rad = math.rad(lat1)
    local lat2_rad = math.rad(lat2)
    local delta_lat = math.rad(lat2 - lat1)
    local delta_lon = math.rad(lon2 - lon1)

    local a = math.sin(delta_lat / 2) * math.sin(delta_lat / 2) +
              math.cos(lat1_rad) * math.cos(lat2_rad) *
              math.sin(delta_lon / 2) * math.sin(delta_lon / 2)
    local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    local distance = R * c
    return distance
end

--------------------------------------------------------------------------------------------------------------
function P.getbearing(lat1, lon1, lat2, lon2)
    local lat1_rad = math.rad(lat1)
    local lon1_rad = math.rad(lon1)
    local lat2_rad = math.rad(lat2)
    local lon2_rad = math.rad(lon2)

    local dLon = lon2_rad - lon1_rad

    local y = math.sin(dLon) * math.cos(lat2_rad)
    local x = math.cos(lat1_rad) * math.sin(lat2_rad) -
              math.sin(lat1_rad) * math.cos(lat2_rad) * math.cos(dLon)

    local bearing_rad = math.atan2(y, x)
    local bearing_deg = math.deg(bearing_rad)

    return (bearing_deg + 360) % 360
end


--------------------------------------------------------------------------------------------------------------
function P.buildlegstable(legs_string, lat_array, lon_array)
    local waypoints = {}
    if type(legs_string) ~= "string" or not lat_array or not lon_array then
        return waypoints
    end

    local leg_names = {}
    for word in string.gmatch(legs_string, "([^%s]+)") do
        table.insert(leg_names, word)
    end

    local skip_ids = {
        ["DISCONTINUITY"] = true,
        ["(INTC)"] = true,
        ["(HOLD)"] = true,
        ["HOLD"] = true,
        [""] = true
    }

    local max_count = math.min(#lat_array, #leg_names)
    local last_lat, last_lon = nil, nil

    for i = 1, max_count do
        local lat = lat_array[i]
        local lon = lon_array[i]
        local leg_name = leg_names[i] or ""

        if not skip_ids[leg_name] and not (lat == 0 and lon == 0) then
            local waypoint = {
                name = leg_name,
                latitude = lat,
                longitude = lon,
                distance_to_next = 0,
                true_course = 0,
                magnetic_course = 0
            }
            table.insert(waypoints, waypoint)
            last_lat, last_lon = lat, lon
        end
    end

    if #waypoints > 1 then
        for i = 1, #waypoints - 1 do
            local wp1 = waypoints[i]
            local wp2 = waypoints[i + 1]

            local distance_to_next = P.getdistance(wp1.latitude, wp1.longitude, wp2.latitude, wp2.longitude)
            local true_course = P.getbearing(wp1.latitude, wp1.longitude, wp2.latitude, wp2.longitude)

            local mag_var = sasl.getMagneticVariation(wp1.latitude, wp1.longitude)
            local magnetic_course = (true_course - mag_var + 360) % 360

            wp1.distance_to_next = distance_to_next
            wp1.true_course = true_course
            wp1.magnetic_course = magnetic_course
        end
    end

    return waypoints
end

--------------------------------------------------------------------------------------------------------------
function P.getRemainingRouteDistance(legs_string, lat_array, lon_array, aircraftLat, aircraftLon)
    if type(legs_string) ~= "string" or not lat_array or not lon_array then
        return nil
    end

    local detailed_route = P.buildlegstable(legs_string, lat_array, lon_array)
    local waypoint_count = #detailed_route

    if waypoint_count < 2 then
        return nil
    end

    local totalDistance = 0
    for i = 1, waypoint_count - 1 do
        totalDistance = totalDistance + (detailed_route[i].distance_to_next or 0)
    end

    if totalDistance <= 0 then
        return nil
    end

    if not aircraftLat or not aircraftLon then
        return totalDistance, detailed_route[waypoint_count], false
    end

    local distanceFromStart, onRoute = P.getdistancealongroute(detailed_route, aircraftLat, aircraftLon)
    if not distanceFromStart then
        return totalDistance, detailed_route[waypoint_count], false
    end

    local remaining = totalDistance - distanceFromStart
    if remaining < 0 then
        remaining = 0
    end

    return remaining, detailed_route[waypoint_count], onRoute == true
end

--------------------------------------------------------------------------------------------------------------
function P.getdistancealongroute(detailed_route, currentLat, currentLon)
    local cumulativeDistance = 0
    local totalWaypoints = #detailed_route
    local foundSegment = false
    local onroute_tolerance_nm = 0.5

    for i = 1, totalWaypoints - 1 do
        local wp1 = detailed_route[i]
        local wp2 = detailed_route[i + 1]
        local segmentDistance = wp1.distance_to_next

        local distFromAircraftToStart = P.getdistance(currentLat, currentLon, wp1.latitude, wp1.longitude)
        local distFromAircraftToEnd = P.getdistance(currentLat, currentLon, wp2.latitude, wp2.longitude)

        if math.abs(distFromAircraftToStart + distFromAircraftToEnd - segmentDistance) < onroute_tolerance_nm then
            cumulativeDistance = cumulativeDistance + distFromAircraftToStart
            foundSegment = true
            return cumulativeDistance, foundSegment
        end

        cumulativeDistance = cumulativeDistance + segmentDistance
    end

    return cumulativeDistance, foundSegment
end

--------------------------------------------------------------------------------------------------------------
function P.getpointonroute(detailed_route, currentLat, currentLon, distanceInNM)
    local currentDistance = P.getdistancealongroute(detailed_route, currentLat, currentLon)
    local targetDistance = currentDistance + distanceInNM
    
    local cumulativeDistance = 0
    local totalWaypoints = #detailed_route
    
    if totalWaypoints < 2 then
        P.logInfoTS("Route has not enough waypoints")
        return nil
    end

    for i = 1, totalWaypoints - 1 do
        local wp1 = detailed_route[i]
        local wp2 = detailed_route[i + 1]
        local segmentDistance = wp1.distance_to_next

        if cumulativeDistance + segmentDistance >= targetDistance then
            local distanceIntoSegment = targetDistance - cumulativeDistance
            local fraction = distanceIntoSegment / segmentDistance

            local pointLat = wp1.latitude + (wp2.latitude - wp1.latitude) * fraction
            local pointLon = wp1.longitude + (wp2.longitude - wp1.longitude) * fraction
            
            local trueCourse = wp1.true_course
            local magneticCourse = wp1.magnetic_course

            local remainingDistance = segmentDistance - distanceIntoSegment

            return {
                latitude = pointLat,
                longitude = pointLon,
                truecourse = trueCourse,
                magneticcourse = magneticCourse,
                nextwaypointname = wp2.name,
                remainingdistance = remainingDistance
            }
        end
        cumulativeDistance = cumulativeDistance + segmentDistance
    end

    return nil
end

--------------------------------------------------------------------------------------------------------------
function P.estimatefuelattod(currentLeftLbs, currentRightLbs, currentCenterLbs, distanceToTODNM, opts)
    local assumed_cruise_speed_knots = 450
    local assumed_cruise_fuel_flow_lbs_hr = 5000

    local dist_nm = tonumber(distanceToTODNM) or 0
    if dist_nm < 0 then
        dist_nm = 0
    end

    local finalLeftLbs = tonumber(currentLeftLbs) or 0
    local finalRightLbs = tonumber(currentRightLbs) or 0
    local finalCenterLbs = tonumber(currentCenterLbs) or 0

    local fuel_flow_lbs_hr = nil
    local speed_kt = nil
    local phase = 1
    local alt_ft = nil
    local ias_kt = nil
    local tas_kt = nil
    local gs_kt = nil
    local wc_speed = 0
    local isa_dev_c = 0

    if type(opts) == "table" then
        fuel_flow_lbs_hr = tonumber(opts.fuel_flow_lbs_hr)
        phase = tonumber(opts.phase) or phase
        alt_ft = tonumber(opts.alt_ft)
        ias_kt = tonumber(opts.ias_kt)
        tas_kt = tonumber(opts.tas_kt)
        gs_kt = tonumber(opts.gs_kt)
        wc_speed = tonumber(opts.wc_speed) or 0
        isa_dev_c = tonumber(opts.isa_dev_c) or 0
    end

    if not fuel_flow_lbs_hr or fuel_flow_lbs_hr <= 0 then
        if alt_ft and ias_kt and ias_kt > 0 then
            fuel_flow_lbs_hr = P.estimateFuelFlow(phase, alt_ft, alt_ft, ias_kt, wc_speed, isa_dev_c)
        else
            fuel_flow_lbs_hr = assumed_cruise_fuel_flow_lbs_hr
        end
    end

    if gs_kt and gs_kt > 0 then
        speed_kt = gs_kt
    elseif tas_kt and tas_kt > 0 then
        speed_kt = tas_kt
    elseif ias_kt and ias_kt > 0 and alt_ft then
        speed_kt = P.atmoIasToTas(ias_kt, alt_ft)
    end
    if not speed_kt or speed_kt <= 0 then
        speed_kt = assumed_cruise_speed_knots
    end

    local estimated_flight_time_hours = dist_nm / speed_kt
    local estimated_fuel_burn_lbs = estimated_flight_time_hours * fuel_flow_lbs_hr

    local remainingBurn = estimated_fuel_burn_lbs

    if finalCenterLbs > 1000 and remainingBurn > 0 then
        local centerToBurn = finalCenterLbs - 1000

        if remainingBurn >= centerToBurn then
            finalCenterLbs = 1000
            remainingBurn = remainingBurn - centerToBurn
        else
            finalCenterLbs = finalCenterLbs - remainingBurn
            remainingBurn = 0
        end
    end

    if remainingBurn > 0 then
        local wingBurn = remainingBurn / 2
        finalLeftLbs = finalLeftLbs - wingBurn
        finalRightLbs = finalRightLbs - wingBurn
    end

    return {
        left = finalLeftLbs,
        right = finalRightLbs,
        center = finalCenterLbs,
        total = finalLeftLbs + finalRightLbs + finalCenterLbs
    }
end

--------------------------------------------------------------------------------------------------------------
function P.calculateRequiredFuelNow(distanceToTODNM, reserveFuelLbs)
    if type(distanceToTODNM) ~= "number" or distanceToTODNM < 0 or
       type(reserveFuelLbs) ~= "number" or reserveFuelLbs < 0 then
        return nil
    end

    local CRUISE_SPEED_KNOTS = 450
    local CRUISE_FUEL_FLOW_LBS_HR = 5000

    local FUEL_FOR_DESCENT_LBS = 1200
    local FUEL_FOR_APPROACH_LBS = 1800
    local FUEL_FOR_TAXI_IN_LBS = 300

    local flightTimeHoursToTOD = distanceToTODNM / CRUISE_SPEED_KNOTS
    local cruiseBurnLbs = flightTimeHoursToTOD * CRUISE_FUEL_FLOW_LBS_HR

    local descentAndLandingBurn = FUEL_FOR_DESCENT_LBS + FUEL_FOR_APPROACH_LBS + FUEL_FOR_TAXI_IN_LBS

    local totalRequiredFuelNow = cruiseBurnLbs + descentAndLandingBurn + reserveFuelLbs

    return totalRequiredFuelNow
end

--------------------------------------------------------------------------------------------------------------
function P.findnearestvor(navdatatable, airport_lat, airport_lon)
    local nearest_vor = nil
    local min_distance_sq = math.huge
    local max_distance_nm = 100
    for key, navdata in pairs(navdatatable) do
        if navdata[def.DESTNAVTYPE] == def.NAVTYPEVOR then
            local vor_lat = tonumber(navdata[def.DESTLATPOS])
            local vor_lon = tonumber(navdata[def.DESTLONPOS])

            if vor_lat and vor_lon then
                local distance_nm = P.getdistance(airport_lat, airport_lon, vor_lat, vor_lon)

                if (navdata[def.DESTNAVID] == "SH") then
                    P.logInfoTS(" VOR SH LAT: " .. vor_lat .. " LON: " .. vor_lon .. " gefunden.")
                end


                if distance_nm <= max_distance_nm then
                    local distance_sq = distance_nm * distance_nm
                    if distance_sq < min_distance_sq then
                        min_distance_sq = distance_sq
                        nearest_vor = {
                            navid = navdata[def.DESTNAVID],
                            frequency = navdata[def.DESTFREQ]
                        }
                    end
                end
            end
        end
    end

    if nearest_vor then
        sasl.logDebug(string.format("Nearest VOR found: %s (Frequenz: %.2f) within radious of 100 NM.", nearest_vor.name, nearest_vor.frequency))
    else
        sasl.logDebug("No VOR within radious of 100 NM, of LAT: " .. airport_lat .. " LON: " .. airport_lon .. " found.")
    end

    return nearest_vor
end

--------------------------------------------------------------------------------------------------------------
local function trimString(str)
    if type(str) ~= "string" then
        return ""
    end
    return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function getLocalizerRunwayMap(icao)
    if type(icao) ~= "string" or icao == "" then
        return nil
    end

    icao = string.upper(icao)
    P.localizerRunwayCache = P.localizerRunwayCache or {}

    if P.localizerRunwayCache[icao] ~= nil then
        return P.localizerRunwayCache[icao] or nil
    end

    local srcnavdatafile = io.open("Custom Data/earth_nav.dat", "rb")
    if not srcnavdatafile then
        srcnavdatafile = io.open("Custom Scenery/Global Airports/Earth nav data/earth_nav.dat", "rb")
        if not srcnavdatafile then
            srcnavdatafile = io.open("Resources/default data/earth_nav.dat", "rb")
        end
    end

    if not srcnavdatafile then
        P.localizerRunwayCache[icao] = false
        return nil
    end

    for _ = 1, 3 do
        srcnavdatafile:read()
    end

    local runwayMap = {}

    for navdatarecord in srcnavdatafile:lines() do
        if string.sub(navdatarecord, 1, 2) == "99" then
            break
        end

        local navdataitems = {}
        for navdataitem in navdatarecord:gmatch("%S+") do
            table.insert(navdataitems, navdataitem)
        end

        if #navdataitems > def.NAVSRC_COL_NAME then
            local recordType = navdataitems[def.NAVSRC_COL_TYPE]
            local region = navdataitems[def.NAVSRC_COL_REGION]

            if (recordType == def.NAVDATARECTYPEILS or recordType == def.NAVDATARECTYPELOC)
                and region == icao then
                local name = navdataitems[def.NAVSRC_COL_NAME] or ""
                local prefix = string.sub(name, 1, 3)
                if prefix == def.NAVTYPEILS
                    or prefix == def.NAVTYPELOC
                    or prefix == def.NAVTYPELDA
                    or prefix == def.NAVTYPEIGS then
                    local ident = navdataitems[def.NAVSRC_COL_IDENT]
                    local runway = navdataitems[def.NAVSRC_COL_RUNWAY]
                    if ident and ident ~= "" and runway and runway ~= "" then
                        runwayMap[string.upper(ident)] = string.upper(runway)
                    end
                end
            end
        end
    end

    srcnavdatafile:close()

    if next(runwayMap) then
        P.localizerRunwayCache[icao] = runwayMap
        return runwayMap
    end

    P.localizerRunwayCache[icao] = false
    return nil
end

local function formatCIFPApproachName(typeChar, runwayPart, suffix)
    local prefix = typeChar
    if typeChar == "LDA" then
        prefix = "LDA"
    elseif typeChar == "I" then
        prefix = "ILS"
    elseif typeChar == "G" then
        prefix = "GLS"
    elseif typeChar == "L" then
        prefix = "LPV"
    elseif typeChar == "R" then
        prefix = "RNAV"
    end

    local formattedRunway = P.formatRunwayDesignator(runwayPart)
    local suffixPart = ""
    if suffix and suffix ~= "" then
        suffixPart = " " .. P.spellNato(suffix)
    end

    return string.format("%s %s%s", prefix, formattedRunway, suffixPart)
end

function P.loadCIFP(icao)
    if type(icao) ~= "string" or #icao < 3 then
        return nil
    end

    icao = string.upper(icao)
    P.cifpCache = P.cifpCache or {}

    if P.cifpCache[icao] ~= nil then
        return P.cifpCache[icao] or nil
    end

    local searchPaths = {
        string.format("Custom Data/CIFP/%s.dat", icao),
        string.format("Resources/default data/CIFP/%s.dat", icao)
    }

    local file
    local usedPath
    for _, candidate in ipairs(searchPaths) do
        local handle = io.open(candidate, "r")
        if handle then
            file = handle
            usedPath = candidate
            break
        end
    end

    if not file then
        sasl.logDebug(string.format("CIFP: No file for %s (checked Custom & Default)", icao))
        P.cifpCache[icao] = false
        return nil
    end

    sasl.logDebug(string.format("CIFP: Loaded %s from %s", icao, usedPath))

    local approaches = {}
    local entryByCode = {}
    local runwayMap = nil

    local function addEntryToApproaches(entry, navType, runwayPart)
        if not entry or not navType or not runwayPart or runwayPart == "" then
            return
        end
        local runwayKey = string.upper(runwayPart)
        approaches[navType] = approaches[navType] or {}
        approaches[navType][runwayKey] = approaches[navType][runwayKey] or {}
        entry.runway = runwayKey
        entry.displayName = formatCIFPApproachName(entry.typeChar, runwayKey, entry.suffix or "")
        entry.registered = true
        table.insert(approaches[navType][runwayKey], entry)
    end

    local function resolveLdaEntry(entry)
        if not entry or entry.registered or entry.navType ~= def.NAVTYPELDA then
            return
        end
        runwayMap = runwayMap or getLocalizerRunwayMap(icao)
        if not runwayMap then
            return
        end

        local function tryIdent(ident)
            if not ident or ident == "" then
                return false
            end
            local key = string.upper(ident)
            local runway = runwayMap[key]
            if runway and runway ~= "" then
                entry.localizerIdent = key
                addEntryToApproaches(entry, entry.navType, runway)
                return true
            end
            return false
        end

        if tryIdent(entry.localizerIdent) then
            return
        end
        if tryIdent(entry.finalFixIdent) then
            return
        end
        if entry.legFixes then
            for fixIdent in pairs(entry.legFixes) do
                if tryIdent(fixIdent) then
                    return
                end
            end
        end
    end

    for line in file:lines() do
        if string.sub(line, 1, 6) == "APPCH:" then
            local parts = {}
            for token in string.gmatch(line, "([^,]+)") do
                table.insert(parts, trimString(token))
            end

            local code = parts[3]
            if code and code ~= "" then
                code = string.upper(code)
                local typeTag
                local navType
                if string.sub(code, 1, 3) == def.NAVTYPELDA then
                    typeTag = def.NAVTYPELDA
                    navType = def.NAVTYPELDA
                else
                    local typeChar = string.sub(code, 1, 1)
                    if typeChar == "I" then
                        typeTag = typeChar
                        navType = def.NAVTYPEILS
                    elseif typeChar == "G" then
                        typeTag = typeChar
                        navType = def.NAVTYPEGLS
                    elseif typeChar == "L" then
                        typeTag = typeChar
                        navType = def.NAVTYPELPV
                    elseif typeChar == "R" then
                        typeTag = typeChar
                        navType = def.NAVTYPERNAV
                    end
                end

                if navType then
                    local entry = entryByCode[code]
                    if not entry then
                        local prefixLen = typeTag and #typeTag or 1
                        local rest = string.sub(code, prefixLen + 1)
                        local runwayPart, suffix = rest:match("^(%d%d%a?)(%a*)$")
                        if runwayPart then
                            runwayPart = string.upper(runwayPart)
                            suffix = suffix or ""
                            entry = {
                                code = code,
                                navType = navType,
                                typeChar = typeTag,
                                runway = runwayPart,
                                suffix = suffix,
                                displayName = nil,
                                course = nil,
                                finalFixIdent = nil,
                                legFixes = {},
                                registered = false,
                                localizerIdent = nil
                            }
                            entryByCode[code] = entry
                            addEntryToApproaches(entry, navType, runwayPart)
                        elseif navType == def.NAVTYPELDA then
                            suffix = suffix or rest or ""
                            entry = {
                                code = code,
                                navType = navType,
                                typeChar = typeTag,
                                runway = nil,
                                suffix = suffix,
                                displayName = nil,
                                course = nil,
                                finalFixIdent = nil,
                                legFixes = {},
                                registered = false,
                                localizerIdent = nil
                            }
                            entryByCode[code] = entry
                        end
                    end

                    entry = entryByCode[code]
                    if entry then
                        local function register_fix(fix)
                            fix = trimString(fix or "")
                            if fix ~= "" then
                                entry.legFixes[fix] = true
                            end
                            return fix
                        end

                        local procedureFix = register_fix(parts[4])
                        register_fix(parts[5])

                        local pathTerminator = trimString(parts[12] or "")
                        local segmentType = trimString(parts[9] or "")
                        local fixIdent = trimString(parts[5] or "")
                        local isRunwayLeg = fixIdent ~= "" and string.sub(fixIdent, 1, 2) == "RW"
                        local isFinalLeg = (pathTerminator == "CF") or (pathTerminator == "TF")

                        if segmentType == "M" and (pathTerminator == "CA" or pathTerminator == "VA") then
                            local alt1 = tonumber(trimString(parts[24] or "")) or 0
                            local alt2 = tonumber(trimString(parts[25] or "")) or 0
                            local missAlt = (alt1 > 0) and alt1 or ((alt2 > 0) and alt2 or nil)
                            if missAlt and not entry.missedAlt then
                                entry.missedAlt = missAlt
                            end
                        end

                        if isRunwayLeg and isFinalLeg then
                            if not entry.course then
                                local courseField = trimString(parts[21] or "")
                                local courseValue = tonumber(courseField)
                                local courseIsTrue = false
                                if not courseValue and courseField ~= "" then
                                    local upper = string.upper(courseField)
                                    if string.sub(upper, -1) == "T" then
                                        courseIsTrue = true
                                        courseValue = tonumber(string.sub(upper, 1, -2))
                                    end
                                end
                                if courseValue then
                                    -- ARINC: course stored in 1/10 deg. "T" indicates true course.
                                    local courseDeg = P.calccourse(courseValue / 10.0)
                                    entry.course_raw = courseDeg
                                    entry.course_is_true = courseIsTrue
                                    if not courseIsTrue then
                                        entry.course = courseDeg
                                    end
                                end
                            end

                            if not entry.finalFixIdent then
                                local recommendedFix = register_fix(parts[14])
                                entry.finalFixIdent = recommendedFix ~= "" and recommendedFix or procedureFix
                            end
                        else
                            register_fix(parts[14])
                        end

                        if entry.navType == def.NAVTYPELDA and not entry.registered then
                            local identCandidate = trimString(parts[14] or "")
                            if identCandidate ~= "" and not entry.localizerIdent then
                                entry.localizerIdent = string.upper(identCandidate)
                            end
                        end
                    end
                end
            end
        end
    end

    file:close()

    for _, entry in pairs(entryByCode) do
        if entry.navType == def.NAVTYPELDA and not entry.registered then
            resolveLdaEntry(entry)
            if not entry.registered then
                sasl.logDebug(string.format("CIFP: LDA approach %s missing runway; skipping.", entry.code or "?"))
            end
        end
    end

    P.cifpCache[icao] = approaches
    if approaches and next(approaches) then
        return approaches
    end
    P.cifpCache[icao] = false
    return nil
end

function P.getCIFPApproach(icao, navType, runway)
    if type(icao) ~= "string" or type(navType) ~= "string" or type(runway) ~= "string" then
        return nil
    end

    local cifpData = P.loadCIFP(icao)
    if not cifpData then
        return nil
    end

    local navEntries = cifpData[navType]
    if not navEntries then
        return nil
    end

    local rwy = string.upper(runway)
    rwy = rwy:gsub("^RW", "")
    local candidates = navEntries[rwy]
    if not candidates or #candidates == 0 then
        return nil
    end

    return candidates[1]
end

function P.getCIFPApproachName(icao, navType, runway)
    local entry = P.getCIFPApproach(icao, navType, runway)
    return entry and entry.displayName or nil
end

function P.getCIFPApproachCourse(icao, navType, runway)
    local entry = P.getCIFPApproach(icao, navType, runway)
    return entry and entry.course or nil
end

function P.getCIFPApproachCourseInfo(icao, navType, runway)
    local entry = P.getCIFPApproach(icao, navType, runway)
    if not entry then
        return nil, nil
    end
    if entry.course_raw ~= nil then
        return entry.course_raw, entry.course_is_true == true
    end
    if entry.course ~= nil then
        return entry.course, false
    end
    return nil, nil
end

function P.calcApproachCourseZibo(entry, ctx)
    if not entry then
        return nil
    end
    ctx = ctx or {}

    local navType = entry[def.DESTNAVTYPE]
    local icao = ctx.icao or entry[def.DESTICAO]
    local runway = ctx.runway or entry[def.DESTRWY]
    local function markSource(source)
        if ctx then
            ctx.source = source
        end
    end

    local appId = ctx.appId
    if type(appId) == "string" then
        appId = appId:gsub("%s+", ""):upper()
    end
    if appId and ctx.navdatatable and ctx.navIndices
        and (navType == def.NAVTYPEGLS or navType == def.NAVTYPELPV or navType == def.NAVTYPERNAV) then
        for _, idx in ipairs(ctx.navIndices) do
            local cand = ctx.navdatatable[idx]
            if cand and cand[def.DESTNAVTYPE] == navType then
                local candId = cand[def.DESTNAVID]
                local candIdUpper = type(candId) == "string" and candId:upper() or candId
                local appIdUpper = appId
                local altId = cand.alt_id
                local altIdUpper = type(altId) == "string" and altId:upper() or altId
                local appIdStored = cand.app_id
                local appIdStoredUpper = type(appIdStored) == "string" and appIdStored:upper() or appIdStored
                if (appIdUpper and candIdUpper == appIdUpper)
                    or (appIdUpper and altIdUpper == appIdUpper)
                    or (appIdUpper and appIdStoredUpper == appIdUpper) then
                    entry = cand
                    navType = cand[def.DESTNAVTYPE]
                    break
                end
            end
        end
    end
    local magVar = ctx.magVar
    if magVar == nil then
        magVar = entry[def.DESTMAGVAR]
        if magVar == nil then
            local lat = entry[def.DESTLATPOS]
            local lon = entry[def.DESTLONPOS]
            if lat and lon and lat ~= 0 and lon ~= 0 then
                magVar = sasl.getMagneticVariation(lat, lon)
            end
        end
    end
    magVar = tonumber(magVar) or 0

    local function decode_raw_course(raw)
        local rawVal = tonumber(raw)
        if not rawVal then
            return nil, nil, false
        end
        if rawVal > 360 then
            local mag = math.floor(rawVal / 360)
            local trueC = rawVal - mag
            return P.calccourse(trueC), P.calccourse(mag), true
        end
        return P.calccourse(rawVal), nil, false
    end

    local function clean_leg_token(token)
        if type(token) ~= "string" then
            return ""
        end
        return token:gsub("[%(%)]", ""):gsub("%s+", "")
    end

    local function is_runway_leg(token)
        local clean = clean_leg_token(token)
        return clean:upper():match("^RW%d%d?[LRC]?") ~= nil
    end

    local function matches_dest_runway(token, destRunway)
        if not token or not destRunway then
            return false
        end
        local cleanToken = clean_leg_token(token):upper():gsub("^RW", "")
        local cleanDest = clean_leg_token(destRunway):upper():gsub("^RW", "")
        return cleanToken == cleanDest
    end

    local function get_fms_final_mag_course()
        local legsStr = ctx.fmslegs
        local latArr = ctx.fmslegslat
        local lonArr = ctx.fmslegslon
        if type(legsStr) ~= "string" or not latArr or not lonArr then
            return nil
        end
        local waypoints = P.buildlegstable(legsStr, latArr, lonArr)
        if not waypoints or #waypoints < 2 then
            return nil
        end
        local destRunway = runway
        local selectedCourse = nil
        if destRunway and P.isvalidrwy(destRunway) then
            for i = #waypoints - 1, 1, -1 do
                local nxt = waypoints[i + 1]
                if nxt and nxt.name and matches_dest_runway(nxt.name, destRunway) then
                    selectedCourse = waypoints[i].magnetic_course
                    break
                end
            end
        else
            for i = #waypoints - 1, 1, -1 do
                local nxt = waypoints[i + 1]
                if nxt and nxt.name and is_runway_leg(nxt.name) then
                    selectedCourse = waypoints[i].magnetic_course
                    break
                end
            end
        end
        if selectedCourse and selectedCourse ~= 0 then
            return P.calccourse(selectedCourse)
        end
        return nil
    end

    local function cifp_course_mag(candidateType)
        if not (icao and runway and candidateType) then
            return nil
        end
        local course, isTrue = P.getCIFPApproachCourseInfo(icao, candidateType, runway)
        if course == nil then
            return nil
        end
        if isTrue then
            return P.calccourse(course + magVar)
        end
        return P.calccourse(course)
    end

    if navType == def.NAVTYPEILS or navType == def.NAVTYPELOC
        or navType == def.NAVTYPELDA or navType == def.NAVTYPEIGS then
        local raw = entry[def.DESTRAWBEARING]
        local trueC, magC, hasMag = decode_raw_course(raw)
        if hasMag and magC then
            markSource("RAW_MAG")
            return P.calccourse(magC)
        end
        if trueC then
            markSource("RAW_TRUE")
            return P.calccourse(trueC + magVar)
        end
        if entry[def.DESTCOURSE] ~= nil then
            markSource("NAV")
            return P.calccourse(entry[def.DESTCOURSE])
        end
    elseif navType == def.NAVTYPEGLS then
        if entry.isTrueCourse and entry.truecourse then
            markSource("NAV_TRUE")
            return P.calccourse(entry.truecourse + magVar)
        end
        if entry[def.DESTCOURSE] ~= nil then
            markSource("NAV")
            return P.calccourse(entry[def.DESTCOURSE])
        end
    else
        -- Detected-only RNAV entries are weaker than a matched navdata entry.
        -- In this case prefer the destination runway heading over the live FMS leg
        -- track, which can reflect an intercept/dogleg instead of the displayed FAC.
        if navType == def.NAVTYPERNAV then
            if entry._detectedOnly then
                local runwayMag = tonumber(ctx.runwayMag)
                if runwayMag then
                    markSource("RUNWAY_MAG")
                    return P.calccourse(runwayMag)
                end
                local runwayTrue = tonumber(ctx.runwayTrue)
                if runwayTrue then
                    markSource("RUNWAY_TRUE")
                    return P.calccourse(runwayTrue + magVar)
                end
            end
            local fmsMag = get_fms_final_mag_course()
            if fmsMag then
                markSource("FMS")
                return P.calccourse(fmsMag)
            end
            local runwayMag = tonumber(ctx.runwayMag)
            if runwayMag then
                markSource("RUNWAY_MAG")
                return P.calccourse(runwayMag)
            end
            local runwayTrue = tonumber(ctx.runwayTrue)
            if runwayTrue then
                markSource("RUNWAY_TRUE")
                return P.calccourse(runwayTrue + magVar)
            end
        end
        if entry.isTrueCourse and entry.truecourse then
            markSource("NAV_TRUE")
            return P.calccourse(entry.truecourse + magVar)
        end
        local entryCourse = tonumber(entry[def.DESTCOURSE])
        if entryCourse and entryCourse > 0 then
            markSource("NAV")
            return P.calccourse(entryCourse)
        end
        local candidateTypes = { navType }
        if navType == def.NAVTYPELPV or navType == def.NAVTYPEGLS then
            candidateTypes = { navType, def.NAVTYPERNAV }
        end
        for _, candidateType in ipairs(candidateTypes) do
            local cifpMag = cifp_course_mag(candidateType)
            if cifpMag then
                markSource("CIFP")
                return cifpMag
            end
        end
        local fmsMag = get_fms_final_mag_course()
        if fmsMag then
            markSource("FMS")
            return P.calccourse(fmsMag)
        end
    end

    local runwayMag = tonumber(ctx.runwayMag)
    if runwayMag then
        markSource("RUNWAY_MAG")
        return P.calccourse(runwayMag)
    end
    local runwayTrue = tonumber(ctx.runwayTrue)
    if runwayTrue then
        markSource("RUNWAY_TRUE")
        return P.calccourse(runwayTrue + magVar)
    end
    markSource("NONE")
    return nil
end

function P.getCIFPMissedApproachAltitude(icao, navType, runway, detectedApproach)
    if detectedApproach and detectedApproach.entry and detectedApproach.entry.missedAlt and detectedApproach.entry.missedAlt > 0 then
        return detectedApproach.entry.missedAlt
    end
    if type(navType) ~= "string" and detectedApproach and type(detectedApproach.navType) == "string" then
        navType = detectedApproach.navType
    end
    if type(icao) ~= "string" or type(runway) ~= "string" or type(navType) ~= "string" then
        return nil
    end
    if navType == def.NAVTYPELOC or navType == def.NAVTYPEIGS then
        navType = def.NAVTYPEILS
    end
    local entry = P.getCIFPApproach(icao, navType, runway)
    if not entry and (navType == def.NAVTYPELPV or navType == def.NAVTYPEGLS) then
        entry = P.getCIFPApproach(icao, def.NAVTYPERNAV, runway)
    end
    return entry and entry.missedAlt or nil
end

function P.findApproachDME(navdatatable, icao, runway, refLat, refLon, refIdent, options)
    if type(navdatatable) ~= "table" then return nil end
    if type(icao) ~= "string" or icao == "" then return nil end

    icao = string.upper(icao)
    runway = runway and trimString(runway) or ""
    runway = runway ~= "" and string.upper(runway) or ""

    local includeILS = options and options.includeILS == true

    local refIdentUpper = nil
    if type(refIdent) == "string" then
        local trimmed = trimString(refIdent)
        if trimmed ~= "" then
            refIdentUpper = string.upper(trimmed)
        end
    end

    local function entryHasDME(entry)
        local navType = entry[def.DESTNAVTYPE]

        if navType == def.NAVTYPEDME then
            return true
        end
        if entry[def.DESTNAVDME] then
            if navType == def.NAVTYPEVOR then
                return true
            end
            if includeILS and (navType == def.NAVTYPEILS
                or navType == def.NAVTYPELOC
                or navType == def.NAVTYPELDA
                or navType == def.NAVTYPEIGS) then
                return true
            end
        end
        return false
    end

    local function buildScore(entry, strict)
        local score = 0
        local entryRunway = entry[def.DESTRWY] or ""
        entryRunway = entryRunway ~= "" and string.upper(entryRunway) or ""

        if runway ~= "" then
            if entryRunway == runway then
                score = score - 1000
            else
                score = score + (strict and 500 or 50)
            end
        elseif entryRunway ~= "" then
            score = score + (strict and 100 or 40)
        end

        if refLat and refLon and entry[def.DESTLATPOS] and entry[def.DESTLONPOS] and entry[def.DESTLATPOS] ~= 0 then
            local distanceNm = P.getdistance(refLat, refLon, entry[def.DESTLATPOS], entry[def.DESTLONPOS])
            score = score + distanceNm
        else
            score = score + 9999
        end

        local entryIdent = entry[def.DESTDMEIDENT]
        if not entryIdent or entryIdent == "" then
            entryIdent = entry[def.DESTNAVID] or ""
        end
        entryIdent = entryIdent ~= "" and string.upper(entryIdent) or ""

        if refIdentUpper and entryIdent ~= "" then
            if entryIdent == refIdentUpper then
                score = score - 500
            else
                local entrySuffix = #entryIdent >= 3 and entryIdent:sub(-3) or entryIdent
                local refSuffix = #refIdentUpper >= 3 and refIdentUpper:sub(-3) or refIdentUpper
                if entrySuffix ~= "" and entrySuffix == refSuffix then
                    score = score - 200
                end
            end
        end

        return score
    end

    local bestEntry = nil
    local bestScore = math.huge

    -- Pass 1: strict ICAO match
    for _, entry in ipairs(navdatatable) do
        if entry[def.DESTICAO] == icao and entryHasDME(entry) then
            local score = buildScore(entry, true)
            if score < bestScore then
                bestScore = score
                bestEntry = entry
            end
        end
    end

    if bestEntry and bestScore < math.huge then
        return bestEntry
    end

    -- Pass 2: nearby DME (e.g., separate TACAN)
    local maxDistanceNm = 8 -- conservative threshold
    bestScore = math.huge

    for _, entry in ipairs(navdatatable) do
        if entryHasDME(entry) then
            local hasValidCoords = entry[def.DESTLATPOS] and entry[def.DESTLONPOS] and entry[def.DESTLATPOS] ~= 0
            if hasValidCoords and refLat and refLon then
                local distanceNm = P.getdistance(refLat, refLon, entry[def.DESTLATPOS], entry[def.DESTLONPOS])
                if distanceNm <= maxDistanceNm then
                    local score = buildScore(entry, false)
                    if score < bestScore then
                        bestScore = score
                        bestEntry = entry
                    end
                end
            end
        end
    end

    return bestEntry
end

local function collectLegNameSet(legs_string, lat_array, lon_array)
    local names = {}
    if legs_string then
        local hasLatArray = type(lat_array) == "table" and type(lon_array) == "table"
        if hasLatArray then
            local legstable = P.buildlegstable(legs_string, lat_array, lon_array)
            if legstable and #legstable > 0 then
                for _, wp in ipairs(legstable) do
                    if wp.name and wp.name ~= "" then
                        names[string.upper(trimString(wp.name))] = true
                    end
                end
            end
        end
        if not next(names) then
            for word in string.gmatch(legs_string, "([^%s]+)") do
                local key = string.upper(trimString(word))
                if key ~= "" then
                    names[key] = true
                end
            end
        end
    end
    return names
end

local function normalizeSelectedApproachId(selectedAppId, expectedRunway)
    if type(selectedAppId) ~= "string" then return nil end
    local trimmed = trimString(selectedAppId):upper()
    if trimmed == "" or trimmed == "------" then return nil end

    local navType = nil
    local runwayPart = nil
    local suffix = nil

    if string.sub(trimmed, 1, 3) == def.NAVTYPELDA then
        navType = def.NAVTYPELDA
        local rest = string.sub(trimmed, 4)
        runwayPart, suffix = rest:match("^(%d%d%a?)(%a*)")
    else
        -- Pattern: first char = type, then runway (e.g. 08, 08L), optional suffix (Y/Z/etc.)
        local typeChar
        typeChar, runwayPart, suffix = trimmed:match("^(%a)(%d%d%a?)(%a*)")
        if not typeChar or not runwayPart then return nil end

        local navTypeMap = {
            I = def.NAVTYPEILS,
            L = def.NAVTYPELOC,
            R = def.NAVTYPERNAV,
            G = def.NAVTYPEGLS
        }
        navType = navTypeMap[typeChar]
    end
    if not navType or not runwayPart then return nil end

    if expectedRunway and string.upper(expectedRunway) ~= runwayPart then
        -- Different runway, don't apply
        return nil
    end

    return {
        navType = navType,
        suffix = suffix and suffix ~= "" and suffix or nil
    }
end

function P.detectCIFPApproachVariant(icao, runway, legs_string, lat_array, lon_array, selectedAppId)
    if not (P.isvalidicao(icao) and P.isvalidrwy(runway)) then
        return nil
    end

    local cifpData = P.loadCIFP(icao)
    if not cifpData then
        return nil
    end

    runway = string.upper(runway)
    local selectedInfo = normalizeSelectedApproachId(selectedAppId, runway)
    if selectedInfo then
        local entries = cifpData[selectedInfo.navType] and cifpData[selectedInfo.navType][runway]
        if entries and #entries > 0 then
            if selectedInfo.suffix then
                for _, entry in ipairs(entries) do
                    if entry.suffix and string.upper(entry.suffix) == selectedInfo.suffix then
                        return {
                            navType = selectedInfo.navType,
                            entry = entry,
                            score = math.huge,
                            priority = 0,
                            fromSelection = true
                        }
                    end
                end
            end
            return {
                navType = selectedInfo.navType,
                entry = entries[1],
                score = math.huge,
                priority = 0,
                fromSelection = true
            }
        end
    end

    local legNames = collectLegNameSet(legs_string, lat_array, lon_array)
    if not next(legNames) then
        return nil
    end

    local navPriority = {
        [def.NAVTYPELPV] = 1,
        [def.NAVTYPEGLS] = 2,
        [def.NAVTYPEILS] = 3,
        [def.NAVTYPELDA] = 4,
        [def.NAVTYPELOC] = 5,
        [def.NAVTYPEIGS] = 6
    }

    local bestMatch = nil

    for navType, byRunway in pairs(cifpData) do
        local entries = byRunway[runway]
        if entries then
            for _, entry in ipairs(entries) do
                local matchScore = 0
                if entry.finalFixIdent then
                    local key = string.upper(entry.finalFixIdent)
                    if legNames[key] then
                        matchScore = matchScore + 5
                    end
                end
                if entry.legFixes then
                    for fixIdent in pairs(entry.legFixes) do
                        local key = string.upper(fixIdent)
                        if legNames[key] then
                            matchScore = matchScore + 1
                        end
                    end
                end

                if matchScore > 0 then
                    local currentPriority = navPriority[navType] or 99
                    if not bestMatch
                        or currentPriority < bestMatch.priority
                        or (currentPriority == bestMatch.priority and matchScore > bestMatch.score) then
                        bestMatch = {
                            navType = navType,
                            entry = entry,
                            score = matchScore,
                            priority = currentPriority
                        }
                    end
                end
            end
        end
    end

    return bestMatch
end

function P.detectFMSDiscontinuity(legs_string, lat_array, lon_array, aircraftLat, aircraftLon, options)
    if type(legs_string) ~= "string" then
        return nil
    end

    local tokens = {}
    for token in string.gmatch(legs_string, "([^%s]+)") do
        table.insert(tokens, token)
    end

    local usePositionFilter = type(lat_array) == "table"
        and type(lon_array) == "table"
        and type(aircraftLat) == "number"
        and type(aircraftLon) == "number"

    local tokenDistances = nil
    local distanceFromStart = nil
    local positionFilterActive = false

    if usePositionFilter then
        local detailed_route = P.buildlegstable(legs_string, lat_array, lon_array)
        if detailed_route and #detailed_route >= 2 then
            local totalDistance = 0
            for i = 1, #detailed_route - 1 do
                totalDistance = totalDistance + (detailed_route[i].distance_to_next or 0)
            end

            local remaining, _, onRoute = P.getRemainingRouteDistance(
                legs_string,
                lat_array,
                lon_array,
                aircraftLat,
                aircraftLon
            )

            if type(remaining) == "number" and totalDistance then
                distanceFromStart = totalDistance - remaining
                if distanceFromStart < 0 then
                    distanceFromStart = 0
                end
                if onRoute then
                    positionFilterActive = true
                else
                    positionFilterActive = false
                end
            end

            tokenDistances = {}
            local lastLat, lastLon = nil, nil
            local cumulative = 0
            for idx = 1, #tokens do
                local lat = lat_array[idx]
                local lon = lon_array[idx]
                if lat and lon and (lat ~= 0 or lon ~= 0) then
                    if lastLat and lastLon then
                        cumulative = cumulative + P.getdistance(lastLat, lastLon, lat, lon)
                    end
                    lastLat, lastLon = lat, lon
                end
                tokenDistances[idx] = cumulative
            end
        end
    end

    if options then
        if type(options.forceDistanceFromStart) == "number" then
            distanceFromStart = options.forceDistanceFromStart
        end
        if options.forcePositionFilter ~= nil then
            positionFilterActive = options.forcePositionFilter and true or false
        end
    end

    local lastUsableToken = nil
    local function isUsableToken(token)
        if not token or token == "" then return false end
        local clean = token:gsub("[-]", "")
        if clean == "" then return false end
        if token:match("^%b()%s*$") then return false end
        if token == "(INTC)" then return false end
        if token:upper() == "ROUTE" then return false end
        return token:upper() ~= "DISCONTINUITY"
    end

    local function findNextUsable(startIndex)
        for j = startIndex, #tokens do
            local candidate = tokens[j]
            if isUsableToken(candidate) then
                return candidate
            end
        end
        return nil
    end

    local function normalizeToken(token)
        if not token then return "" end
        local stripped = token:gsub("[%-%*]", "")
        return string.upper(stripped)
    end

    local maxAheadNm = options and options.maxAheadNm

    for idx, token in ipairs(tokens) do
        local upperToken = normalizeToken(token)
        if upperToken == "DISCONTINUITY" then
            local prevLeg = lastUsableToken
            local nextLeg = findNextUsable(idx + 1)

            local skip = false
            if positionFilterActive and tokenDistances and distanceFromStart and prevLeg then
                local prevIndex = idx - 1
                while prevIndex > 0 do
                    if tokens[prevIndex] == prevLeg then
                        break
                    end
                    prevIndex = prevIndex - 1
                end
                if prevIndex > 0 then
                    local prevDistance = tokenDistances[prevIndex]
                    if prevDistance and (prevDistance < (distanceFromStart - 5)) then
                        skip = true
                    elseif prevDistance and maxAheadNm then
                        if prevDistance > (distanceFromStart + maxAheadNm) then
                            skip = true
                        end
                    end
                end
            end

            if not skip then
                return {
                    index = idx,
                    total = #tokens,
                    previous = prevLeg,
                    next = nextLeg
                }
            end
        elseif isUsableToken(token) then
            lastUsableToken = token
        end
    end

    return nil
end

--------------------------------------------------------------------------------------------------------------
local function isUsableLegToken(token)
    if token == nil or token == "" then
        return false
    end
    if token == "DISCONTINUITY" then
        return false
    end
    if token:match("^%b()%s*$") then
        return false
    end
    return true
end

function P.hasUsableFMSLegs(legs_string)
    if type(legs_string) ~= "string" then
        return false
    end

    for token in string.gmatch(legs_string, "([^%s]+)") do
        if isUsableLegToken(token) then
            return true
        end
    end

    return false
end

function P.isFMSPlanLoaded(depIcao, destIcao, legs_string)
    if not (P.isvalidicao(depIcao) and P.isvalidicao(destIcao)) then
        return false
    end

    return P.hasUsableFMSLegs(legs_string)
end

--------------------------------------------------------------------------------------------------------------
function P.buildnavdatatable(navdatatable)

    local function find_nav_entry(target_table, icao, navid, navtype, runway)
        if not (icao and navid and navtype) then return nil end
        for i, entry in ipairs(target_table) do
            if  entry[def.DESTICAO] == icao
            and entry[def.DESTNAVID] == navid
            and entry[def.DESTNAVTYPE] == navtype then
                if (runway == nil) or (runway == "") or (entry[def.DESTRWY] == runway) then
                    return i
                end
            end
        end
        return nil
    end

    local function find_localizer_entry(target_table, icao, navid, runway)
        local index = find_nav_entry(target_table, icao, navid, def.NAVTYPEILS, runway)
        if not index then
            index = find_nav_entry(target_table, icao, navid, def.NAVTYPELDA, runway)
        end
        if not index then
            index = find_nav_entry(target_table, icao, navid, def.NAVTYPELOC, runway)
        end
        if not index then
            index = find_nav_entry(target_table, icao, navid, def.NAVTYPEIGS, runway)
        end
        return index
    end

    for i = #navdatatable, 1, -1 do table.remove(navdatatable, i) end

    local NAV_IDX_FILE = def.PLUGINOUTPUTPATH .. "nav_global.yalidx"

    local function stat_file_size(path)
        local f = io.open(path, "rb")
        if not f then
            return 0
        end
        local size = 0
        local ok_seek, end_pos = pcall(function()
            return f:seek("end")
        end)
        if ok_seek and end_pos then
            size = tonumber(end_pos) or 0
        end
        f:close()
        return size
    end

    local nav_path = nil
    local nav_size = 0
    local nav_label = nil
    local nav_candidates = {
        { path = "Custom Data/earth_nav.dat", label = "Custom Data/earth_nav.dat" },
        { path = "Custom Scenery/Global Airports/Earth nav data/earth_nav.dat", label = "Custom Scenery/Global Airports/Earth nav data/earth_nav.dat" },
        { path = "Resources/default data/earth_nav.dat", label = "Resources/default data/earth_nav.dat" }
    }
    for i = 1, #nav_candidates do
        local cand = nav_candidates[i]
        local sz = stat_file_size(cand.path)
        if sz > 0 then
            nav_path = cand.path
            nav_size = sz
            nav_label = cand.label
            break
        end
    end
    if not nav_path then
        sasl.logError("No Navdatabase Source: Could not find earth_nav.dat!")
        return false
    end

    P.logInfoTS("Navdatabase Sourse: " .. tostring(nav_label or nav_path))

    local function split_tabs_simple(line, max_parts)
        local parts = {}
        if not line then
            return parts
        end
        local start = 1
        local line_len = string.len(line)
        while start <= line_len do
            local tab = string.find(line, "\t", start, true)
            if not tab then
                parts[#parts + 1] = string.sub(line, start)
                break
            end
            parts[#parts + 1] = string.sub(line, start, tab - 1)
            start = tab + 1
            if max_parts and #parts >= (max_parts - 1) then
                parts[#parts + 1] = string.sub(line, start)
                break
            end
        end
        if #parts == 0 then
            parts[1] = ""
        end
        return parts
    end

    local function strip_cr(line)
        if not line then
            return line
        end
        local len = #line
        if len > 0 and string.byte(line, len) == 13 then
            return string.sub(line, 1, len - 1)
        end
        return line
    end

    local function load_nav_index(path, size)
        local f = io.open(NAV_IDX_FILE, "rb")
        if not f then
            return nil
        end
        local cache_epoch = tonumber(def.CACHE_EPOCH) or 1
        local idx_version = nil
        local idx_epoch = nil
        local idx_path = nil
        local idx_size = nil
        local entries = {}
        local first_line = strip_cr(f:read("*l"))
        if not first_line then
            f:close()
            return nil
        end
        do
            local first_parts = split_tabs_simple(first_line, 2)
            if first_parts[1] == "YALNAVIDX" then
                idx_version = tonumber(first_parts[2]) or 0
            else
                f:close()
                pcall(function() os.remove(NAV_IDX_FILE) end)
                return nil
            end
        end
        for line in f:lines() do
            line = strip_cr(line)
            if string.sub(line, 1, 6) == "EPOCH\t" then
                idx_epoch = tonumber(string.sub(line, 7)) or 0
            elseif string.sub(line, 1, 5) == "PATH\t" then
                idx_path = string.sub(line, 6)
            elseif string.sub(line, 1, 5) == "SIZE\t" then
                idx_size = tonumber(string.sub(line, 6)) or 0
            else
                local parts = split_tabs_simple(line, 34)
                local icao = parts[1]
                if icao and icao ~= "" then
                    local entry = {}
                    entry[def.DESTICAO] = parts[1] or ""
                    entry[def.DESTRWY] = parts[2] or ""
                    entry[def.DESTNAVTYPE] = parts[3] or ""
                    entry[def.DESTNAVID] = parts[4] or ""
                    entry[def.DESTFREQ] = tonumber(parts[5]) or 0
                    entry[def.DESTLATPOS] = tonumber(parts[6]) or 0
                    entry[def.DESTLONPOS] = tonumber(parts[7]) or 0
                    entry[def.DESTCOURSE] = tonumber(parts[8]) or 0
                    entry[def.DESTNAVDME] = (parts[9] == "1")
                    entry[def.DESTELEVATION] = tonumber(parts[10]) or 0
                    entry[def.DESTRANGE] = tonumber(parts[11]) or 0
                    entry[def.DESTRAWBEARING] = tonumber(parts[12]) or 0
                    entry[def.DESTMAGVAR] = tonumber(parts[13]) or 0
                    entry[def.DESTFACILITYNAME] = parts[14] or ""
                    entry[def.DESTSRCRECTYPE] = parts[15] or ""
                    entry[def.DESTDMELAT] = tonumber(parts[16]) or 0
                    entry[def.DESTDMELON] = tonumber(parts[17]) or 0
                    entry[def.DESTDMEELEVATION] = tonumber(parts[18]) or 0
                    entry[def.DESTDMERANGE] = tonumber(parts[19]) or 0
                    entry[def.DESTGSLAT] = tonumber(parts[20]) or 0
                    entry[def.DESTGSLON] = tonumber(parts[21]) or 0
                    entry[def.DESTGSELEVATION] = tonumber(parts[22]) or 0
                    entry[def.DESTGSRANGE] = tonumber(parts[23]) or 0
                    entry[def.DESTGSSLOPE] = tonumber(parts[24]) or 0
                    entry[def.DESTGSRAWBEARING] = tonumber(parts[25]) or 0
                    entry[def.DESTDMEIDENT] = parts[26] or ""
                    entry[def.DESTDMEFREQ] = tonumber(parts[27]) or 0
                    entry.truecourse = tonumber(parts[28]) or nil
                    entry.isTrueCourse = (parts[29] == "1")
                    local app_id = parts[30]
                    if app_id ~= nil and app_id ~= "" then
                        entry.app_id = app_id
                    end
                    local alt_id = parts[31]
                    if alt_id ~= nil and alt_id ~= "" then
                        entry.alt_id = alt_id
                    end
                    local service_level = parts[32]
                    if service_level ~= nil and service_level ~= "" then
                        entry.serviceLevel = tostring(service_level):upper()
                    end
                    entry.isLateralOnly = (parts[33] == "1")
                    -- Backward compatibility for older caches that did not persist LP flags.
                    if (not entry.isLateralOnly)
                        and entry[def.DESTNAVTYPE] == def.NAVTYPERNAV
                        and entry[def.DESTSRCRECTYPE] == def.NAVDATARECTYPELPV then
                        entry.isLateralOnly = true
                    end
                    if (not entry.serviceLevel)
                        and entry.isLateralOnly
                        and entry[def.DESTSRCRECTYPE] == def.NAVDATARECTYPELPV then
                        entry.serviceLevel = "LP"
                    end
                    table.insert(entries, entry)
                end
            end
        end
        f:close()
        if idx_version ~= 2 then
            P.logInfoTS("Navdata cache invalid (index version mismatch), rebuilding.")
            pcall(function() os.remove(NAV_IDX_FILE) end)
            return nil
        end
        if idx_epoch ~= cache_epoch then
            P.logInfoTS(
                "Navdata cache invalid (cache epoch "
                    .. tostring(idx_epoch)
                    .. " != "
                    .. tostring(cache_epoch)
                    .. "), rebuilding."
            )
            pcall(function() os.remove(NAV_IDX_FILE) end)
            return nil
        end
        if idx_path ~= path or (idx_size or 0) ~= (size or 0) then
            return nil
        end
        if #entries == 0 then
            return nil
        end
        return entries
    end

    local cached = load_nav_index(nav_path, nav_size)
    if cached then
        for i = 1, #cached do
            navdatatable[i] = cached[i]
        end
        P.logInfoTS(
            "Global Airports Navdata Table loaded from cache, "
                .. tostring(#navdatatable)
                .. " entries."
        )
        return true
    end

    local function write_nav_index(path, size, entries)
        local f = io.open(NAV_IDX_FILE, "w")
        if not f then
            sasl.logWarning("Navdata: failed to write nav index: " .. tostring(NAV_IDX_FILE))
            return false
        end
        f:write("YALNAVIDX\t2\n")
        f:write("EPOCH\t", tostring(tonumber(def.CACHE_EPOCH) or 1), "\n")
        f:write("PATH\t", tostring(path or ""), "\n")
        f:write("SIZE\t", tostring(size or 0), "\n")
        for i = 1, #entries do
            local e = entries[i]
            local fields = {
                tostring(e[def.DESTICAO] or ""),
                tostring(e[def.DESTRWY] or ""),
                tostring(e[def.DESTNAVTYPE] or ""),
                tostring(e[def.DESTNAVID] or ""),
                tostring(tonumber(e[def.DESTFREQ]) or 0),
                tostring(tonumber(e[def.DESTLATPOS]) or 0),
                tostring(tonumber(e[def.DESTLONPOS]) or 0),
                tostring(tonumber(e[def.DESTCOURSE]) or 0),
                (e[def.DESTNAVDME] and "1" or "0"),
                tostring(tonumber(e[def.DESTELEVATION]) or 0),
                tostring(tonumber(e[def.DESTRANGE]) or 0),
                tostring(tonumber(e[def.DESTRAWBEARING]) or 0),
                tostring(tonumber(e[def.DESTMAGVAR]) or 0),
                tostring(e[def.DESTFACILITYNAME] or ""),
                tostring(e[def.DESTSRCRECTYPE] or ""),
                tostring(tonumber(e[def.DESTDMELAT]) or 0),
                tostring(tonumber(e[def.DESTDMELON]) or 0),
                tostring(tonumber(e[def.DESTDMEELEVATION]) or 0),
                tostring(tonumber(e[def.DESTDMERANGE]) or 0),
                tostring(tonumber(e[def.DESTGSLAT]) or 0),
                tostring(tonumber(e[def.DESTGSLON]) or 0),
                tostring(tonumber(e[def.DESTGSELEVATION]) or 0),
                tostring(tonumber(e[def.DESTGSRANGE]) or 0),
                tostring(tonumber(e[def.DESTGSSLOPE]) or 0),
                tostring(tonumber(e[def.DESTGSRAWBEARING]) or 0),
                tostring(e[def.DESTDMEIDENT] or ""),
                tostring(tonumber(e[def.DESTDMEFREQ]) or 0),
                tostring(tonumber(e.truecourse) or ""),
                (e.isTrueCourse and "1" or "0"),
                tostring(e.app_id or ""),
                tostring(e.alt_id or ""),
                tostring(e.serviceLevel or ""),
                (e.isLateralOnly and "1" or "0")
            }
            f:write(table.concat(fields, "\t"), "\n")
        end
        f:close()
        return true
    end

    local srcnavdatafile = io.open(nav_path, "rb")
    if not srcnavdatafile then
        sasl.logError("Could not open " .. tostring(nav_path))
        return false
    end

    for i = 1, 3 do local _ = srcnavdatafile:read() end

    local navdatarecord = srcnavdatafile:read()
    while navdatarecord do
        if navdatarecord:sub(1, 2) == "99" then break end

        local navdataitems = {}
        for navdataitem in navdatarecord:gmatch("%S+") do table.insert(navdataitems, navdataitem) end

        if #navdataitems > def.NAVSRC_COL_LON then
            local lat_val = tonumber(navdataitems[def.NAVSRC_COL_LAT])
            local lon_val = tonumber(navdataitems[def.NAVSRC_COL_LON])

                if lat_val and lon_val then
                    local record_type_str = navdataitems[def.NAVSRC_COL_TYPE]

                if (record_type_str == def.NAVDATARECTYPEILS
                    or record_type_str == def.NAVDATARECTYPELOC) then
                    local newEntry = {}
                    newEntry[def.DESTICAO] = navdataitems[def.NAVSRC_COL_REGION]
                    newEntry[def.DESTRWY] = navdataitems[def.NAVSRC_COL_RUNWAY]
                    newEntry[def.DESTNAVTYPE] = string.sub(navdataitems[def.NAVSRC_COL_NAME], 1, 3)
                    newEntry[def.DESTNAVID] = navdataitems[def.NAVSRC_COL_IDENT]
                    newEntry[def.DESTFREQ] = tonumber(navdataitems[def.NAVSRC_COL_FREQ])
                    newEntry[def.DESTLATPOS] = lat_val
                    newEntry[def.DESTLONPOS] = lon_val

                    local course_val_packed = tonumber(navdataitems[def.NAVSRC_COL_BEARING])

                    if course_val_packed then
                        -- NAV1200 encodes localizer heading as magnetic course * 360
                        local magnetic_course = math.floor(course_val_packed / 360)
                        newEntry[def.DESTCOURSE] = P.calccourse(magnetic_course)
                    else
                        newEntry[def.DESTCOURSE] = 0
                    end
                    newEntry[def.DESTNAVDME] = false
                    newEntry[def.DESTELEVATION] = tonumber(navdataitems[def.NAVSRC_COL_ELEV_FT]) or 0
                    newEntry[def.DESTRANGE] = tonumber(navdataitems[def.NAVSRC_COL_RANGE_NM]) or 0
                    newEntry[def.DESTRAWBEARING] = course_val_packed or 0
                    local mag_var = sasl.getMagneticVariation(lat_val, lon_val)
                    newEntry[def.DESTMAGVAR] = mag_var or 0
                    newEntry[def.DESTFACILITYNAME] = navdataitems[def.NAVSRC_COL_NAME] or ""
                    newEntry[def.DESTSRCRECTYPE] = record_type_str
                    newEntry[def.DESTDMELAT] = 0
                    newEntry[def.DESTDMELON] = 0
                    newEntry[def.DESTDMEELEVATION] = 0
                    newEntry[def.DESTDMERANGE] = 0
                    newEntry[def.DESTGSLAT] = 0
                    newEntry[def.DESTGSLON] = 0
                    newEntry[def.DESTGSELEVATION] = 0
                    newEntry[def.DESTGSRANGE] = 0
                    newEntry[def.DESTGSSLOPE] = 0
                    newEntry[def.DESTGSRAWBEARING] = 0
                    newEntry[def.DESTDMEIDENT] = ""
                    newEntry[def.DESTDMEFREQ] = 0
                    table.insert(navdatatable, newEntry)

                elseif (record_type_str == def.NAVDATARECTYPEVOR or record_type_str == def.NAVDATARECTYPEVORDME) then
                    local newEntry = {}
                    newEntry[def.DESTICAO] = navdataitems[def.NAVSRC_COL_REGION]
                    newEntry[def.DESTRWY] = ""
                    newEntry[def.DESTNAVTYPE] = def.NAVTYPEVOR
                    newEntry[def.DESTNAVID] = navdataitems[def.NAVSRC_COL_IDENT]
                    newEntry[def.DESTFREQ] = tonumber(navdataitems[def.NAVSRC_COL_FREQ])
                    newEntry[def.DESTLATPOS] = lat_val
                    newEntry[def.DESTLONPOS] = lon_val
                    newEntry[def.DESTCOURSE] = 0
                    local hasDME = (record_type_str == def.NAVDATARECTYPEVORDME)
                    newEntry[def.DESTNAVDME] = hasDME
                    newEntry[def.DESTELEVATION] = tonumber(navdataitems[def.NAVSRC_COL_ELEV_FT]) or 0
                    newEntry[def.DESTRANGE] = tonumber(navdataitems[def.NAVSRC_COL_RANGE_NM]) or 0
                    local raw_bearing = tonumber(navdataitems[def.NAVSRC_COL_BEARING]) or 0
                    newEntry[def.DESTRAWBEARING] = raw_bearing
                    newEntry[def.DESTMAGVAR] = raw_bearing
                    newEntry[def.DESTFACILITYNAME] = navdataitems[def.NAVSRC_COL_NAME] or ""
                    newEntry[def.DESTSRCRECTYPE] = record_type_str
                    if hasDME then
                        newEntry[def.DESTDMELAT] = lat_val
                        newEntry[def.DESTDMELON] = lon_val
                        newEntry[def.DESTDMEELEVATION] = newEntry[def.DESTELEVATION]
                        newEntry[def.DESTDMERANGE] = newEntry[def.DESTRANGE]
                        newEntry[def.DESTDMEIDENT] = navdataitems[def.NAVSRC_COL_IDENT] or ""
                        newEntry[def.DESTDMEFREQ] = tonumber(navdataitems[def.NAVSRC_COL_FREQ]) or 0
                    else
                        newEntry[def.DESTDMELAT] = 0
                        newEntry[def.DESTDMELON] = 0
                        newEntry[def.DESTDMEELEVATION] = 0
                        newEntry[def.DESTDMERANGE] = 0
                        newEntry[def.DESTDMEIDENT] = ""
                        newEntry[def.DESTDMEFREQ] = 0
                    end
                    newEntry[def.DESTGSLAT] = 0
                    newEntry[def.DESTGSLON] = 0
                    newEntry[def.DESTGSELEVATION] = 0
                    newEntry[def.DESTGSRANGE] = 0
                    newEntry[def.DESTGSSLOPE] = 0
                    newEntry[def.DESTGSRAWBEARING] = 0
                    table.insert(navdatatable, newEntry)

                elseif (record_type_str == def.NAVDATARECTYPEDME) then
                    local icao = navdataitems[def.NAVSRC_COL_REGION]
                    local ident = navdataitems[def.NAVSRC_COL_IDENT]
                    local runway = navdataitems[def.NAVSRC_COL_RUNWAY]

                    local index = find_localizer_entry(navdatatable, icao, ident, runway)
                    if not index then
                        index = find_nav_entry(navdatatable, icao, ident, def.NAVTYPEVOR, runway)
                    end
                    -- Some DME records carry descriptive text instead of a runway designator.
                    -- If no match was found, retry without forcing the runway to align.
                    if not index then
                        index = find_localizer_entry(navdatatable, icao, ident, nil)
                    end
                    if not index then
                        index = find_nav_entry(navdatatable, icao, ident, def.NAVTYPEVOR, nil)
                    end

                    if index then
                        navdatatable[index][def.DESTNAVDME] = true
                        navdatatable[index][def.DESTDMELAT] = lat_val
                        navdatatable[index][def.DESTDMELON] = lon_val
                        navdatatable[index][def.DESTDMEELEVATION] = tonumber(navdataitems[def.NAVSRC_COL_ELEV_FT]) or navdatatable[index][def.DESTDMEELEVATION]
                        navdatatable[index][def.DESTDMERANGE] = tonumber(navdataitems[def.NAVSRC_COL_RANGE_NM]) or navdatatable[index][def.DESTDMERANGE]
                        navdatatable[index][def.DESTDMEIDENT] = ident or navdatatable[index][def.DESTDMEIDENT]
                        navdatatable[index][def.DESTDMEFREQ] = tonumber(navdataitems[def.NAVSRC_COL_FREQ]) or navdatatable[index][def.DESTDMEFREQ]
                    else
                        local newEntry = {}
                        newEntry[def.DESTICAO] = icao
                        newEntry[def.DESTRWY] = navdataitems[def.NAVSRC_COL_RUNWAY] or ""
                        newEntry[def.DESTNAVTYPE] = def.NAVTYPEDME
                        newEntry[def.DESTNAVID] = ident
                        local freq_val = tonumber(navdataitems[def.NAVSRC_COL_FREQ]) or 0
                        newEntry[def.DESTFREQ] = freq_val
                        newEntry[def.DESTCOURSE] = 0
                        newEntry[def.DESTNAVDME] = true
                        newEntry[def.DESTLATPOS] = lat_val
                        newEntry[def.DESTLONPOS] = lon_val
                        newEntry[def.DESTELEVATION] = tonumber(navdataitems[def.NAVSRC_COL_ELEV_FT]) or 0
                        newEntry[def.DESTRANGE] = tonumber(navdataitems[def.NAVSRC_COL_RANGE_NM]) or 0
                        newEntry[def.DESTRAWBEARING] = tonumber(navdataitems[def.NAVSRC_COL_BEARING]) or 0
                        newEntry[def.DESTMAGVAR] = 0
                        newEntry[def.DESTFACILITYNAME] = navdataitems[def.NAVSRC_COL_NAME] or ""
                        newEntry[def.DESTSRCRECTYPE] = record_type_str
                        newEntry[def.DESTDMELAT] = lat_val
                        newEntry[def.DESTDMELON] = lon_val
                        newEntry[def.DESTDMEELEVATION] = newEntry[def.DESTELEVATION]
                        newEntry[def.DESTDMERANGE] = newEntry[def.DESTRANGE]
                        newEntry[def.DESTGSLAT] = 0
                        newEntry[def.DESTGSLON] = 0
                        newEntry[def.DESTGSELEVATION] = 0
                        newEntry[def.DESTGSRANGE] = 0
                        newEntry[def.DESTGSSLOPE] = 0
                        newEntry[def.DESTGSRAWBEARING] = 0
                        newEntry[def.DESTDMEIDENT] = ident or ""
                        newEntry[def.DESTDMEFREQ] = freq_val
                        table.insert(navdatatable, newEntry)
                    end

                elseif (record_type_str == def.NAVDATARECTYPEGS) then
                    local icao = navdataitems[def.NAVSRC_COL_REGION]
                    local ident = navdataitems[def.NAVSRC_COL_IDENT]
                    local runway = navdataitems[def.NAVSRC_COL_RUNWAY]
                    local index = find_nav_entry(navdatatable, icao, ident, def.NAVTYPEILS, runway)
                    if index then
                        navdatatable[index][def.DESTGSLAT] = lat_val
                        navdatatable[index][def.DESTGSLON] = lon_val
                        navdatatable[index][def.DESTGSELEVATION] = tonumber(navdataitems[def.NAVSRC_COL_ELEV_FT]) or navdatatable[index][def.DESTGSELEVATION]
                        navdatatable[index][def.DESTGSRANGE] = tonumber(navdataitems[def.NAVSRC_COL_RANGE_NM]) or navdatatable[index][def.DESTGSRANGE]
                        local raw_value = tonumber(navdataitems[def.NAVSRC_COL_BEARING]) or 0
                        navdatatable[index][def.DESTGSRAWBEARING] = raw_value
                        navdatatable[index][def.DESTGSSLOPE] = raw_value / 100000
                    end

                elseif (record_type_str == def.NAVDATARECTYPELPV or record_type_str == def.NAVDATARECTYPEGLS) then
                    local newEntry = {}
                    newEntry[def.DESTICAO] = navdataitems[def.NAVSRC_COL_REGION]
                    newEntry[def.DESTRWY] = navdataitems[def.NAVSRC_COL_RUNWAY]
                    newEntry[def.DESTFREQ] = tonumber(navdataitems[def.NAVSRC_COL_FREQ])
                    newEntry[def.DESTLATPOS] = lat_val
                    newEntry[def.DESTLONPOS] = lon_val
                    newEntry[def.DESTNAVDME] = true
                    local service_level = navdataitems[#navdataitems]
                    if service_level then
                        service_level = tostring(service_level):upper()
                        if service_level == "LP" or service_level == "LPV" or service_level == "GLS" then
                            newEntry.serviceLevel = service_level
                        else
                            service_level = nil
                        end
                    end

                    if record_type_str == def.NAVDATARECTYPELPV then
                        if service_level == "LP" then
                            newEntry[def.DESTNAVTYPE] = def.NAVTYPERNAV
                            newEntry.isLateralOnly = true
                        else
                            newEntry[def.DESTNAVTYPE] = def.NAVTYPELPV
                        end
                    else
                        newEntry[def.DESTNAVTYPE] = def.NAVTYPEGLS
                    end
                    newEntry[def.DESTNAVID] = navdataitems[def.NAVSRC_COL_IDENT]
                    newEntry.app_id = navdataitems[def.NAVSRC_COL_IDENT]
                    local alt_id = navdataitems[def.NAVSRC_COL_NAME]
                    if alt_id and alt_id ~= "" then
                        newEntry.alt_id = alt_id
                    end
                    
                    local raw_course_str = navdataitems[def.NAVSRC_COL_BEARING]
                    local raw_course = tonumber(raw_course_str)
                    if raw_course then
                        -- LP/LPV/GLS: bearing encodes true course; values >= 1000 include a prefix.
                        local true_course = raw_course
                        if raw_course >= 1000 then
                            true_course = raw_course % 1000
                        end
                        local trueCourseNormalized = (true_course + 360) % 360
                        local mag_variation = sasl.getMagneticVariation(lat_val, lon_val) or 0
                        newEntry.truecourse = trueCourseNormalized
                        newEntry.isTrueCourse = true
                        newEntry[def.DESTCOURSE] = P.calccourse(trueCourseNormalized + mag_variation)
                        newEntry[def.DESTMAGVAR] = mag_variation
                    else
                        P.logInfoTS("Could not read true course for LPV/GLS (column NAVSRC_COL_BEARING): " .. navdatarecord)
                        newEntry[def.DESTCOURSE] = 0 -- Fallback zu 0
                    end
                    
                    newEntry[def.DESTELEVATION] = tonumber(navdataitems[def.NAVSRC_COL_ELEV_FT]) or 0
                    newEntry[def.DESTRANGE] = tonumber(navdataitems[def.NAVSRC_COL_RANGE_NM]) or 0
                    newEntry[def.DESTRAWBEARING] = tonumber(raw_course_str) or 0
                    if not newEntry[def.DESTMAGVAR] then
                        local mag_var = sasl.getMagneticVariation(lat_val, lon_val)
                        newEntry[def.DESTMAGVAR] = mag_var or 0
                    end
                    newEntry[def.DESTFACILITYNAME] = navdataitems[def.NAVSRC_COL_NAME] or ""
                    newEntry[def.DESTSRCRECTYPE] = record_type_str
                    newEntry[def.DESTDMELAT] = 0
                    newEntry[def.DESTDMELON] = 0
                    newEntry[def.DESTDMEELEVATION] = 0
                    newEntry[def.DESTDMERANGE] = 0
                    newEntry[def.DESTGSLAT] = 0
                    newEntry[def.DESTGSLON] = 0
                    newEntry[def.DESTGSELEVATION] = 0
                    newEntry[def.DESTGSRANGE] = 0
                    newEntry[def.DESTGSSLOPE] = 0
                    newEntry[def.DESTGSRAWBEARING] = 0
                    newEntry[def.DESTDMEIDENT] = ""
                    newEntry[def.DESTDMEFREQ] = 0
                    table.insert(navdatatable, newEntry)
                end
            end
        end
        navdatarecord = srcnavdatafile:read()
    end
    srcnavdatafile:close()

    local lookupTable = {}
    for i, entry in ipairs(navdatatable) do
        if entry[def.DESTNAVTYPE] == def.NAVTYPEILS then
            local key = entry[def.DESTICAO] .. entry[def.DESTRWY]
            lookupTable[key] = entry[def.DESTCOURSE]
        end
    end

        for i, value in ipairs(navdatatable) do
        if (value[def.DESTNAVTYPE] == def.NAVTYPEGLS or value[def.DESTNAVTYPE] == def.NAVTYPELPV) then
            local key = value[def.DESTICAO] .. value[def.DESTRWY]
            local ilsEntryIndex = lookupTable[key]

            if (value[def.DESTCOURSE] == 0 or value[def.DESTCOURSE] == nil) and ilsEntryIndex then
                local ilsEntry = navdatatable[ilsEntryIndex]
                if ilsEntry then
                    value[def.DESTCOURSE] = ilsEntry[def.DESTCOURSE]
                    value.truecourse = ilsEntry.truecourse
                    value.isTrueCourse = ilsEntry.isTrueCourse
                end
            end
        end
    end

    write_nav_index(nav_path, nav_size, navdatatable)

    P.logInfoTS("Global Airports Navdata Table created, " .. #navdatatable .. " entries.")
    return true
end
--------------------------------------------------------------------------------------------------------------
function P.writenavdatatable(navdatatable)
    local basePath = def.PLUGINOUTPUTPATH
    local destnavdatafile = io.open(basePath .. "yal_nav.dat", "w")

    if not destnavdatafile then
        sasl.logError("Could not open " .. basePath .. "yal_nav.dat")
        return false
    end

    for row_key, row in pairs(navdatatable) do
        destnavdatafile:write(row_key .. ": ")
        for col_index, value in ipairs(row) do
            destnavdatafile:write(tostring(value) .. " ")
        end
        destnavdatafile:write("\n")
    end

    destnavdatafile:close()

    return true
end

--------------------------------------------------------------------------------------------------------------
local AIRPORT_META_PATH = "Resources/default data/earth_aptmeta.dat"
local AIRPORT_META_IDX_FILE = def.PLUGINOUTPUTPATH .. "airport_meta.yalidx"

function P.buildairportdatatable(airport_db)
    if not airport_db then
        return false
    end

    for k in pairs(airport_db) do
        airport_db[k] = nil
    end

    local function stat_file_size(path)
        local f = io.open(path, "rb")
        if not f then
            return 0
        end
        local size = 0
        local ok_seek, end_pos = pcall(function()
            return f:seek("end")
        end)
        if ok_seek and end_pos then
            size = tonumber(end_pos) or 0
        end
        f:close()
        return size
    end

    local function compute_airport_meta()
        local size = stat_file_size(AIRPORT_META_PATH)
        if size <= 0 then
            return nil
        end
        return {
            path = AIRPORT_META_PATH,
            size = size
        }
    end

    local function write_airport_meta_index(meta, db)
        if not meta or not db then
            return false
        end
        local file = io.open(AIRPORT_META_IDX_FILE, "w")
        if not file then
            sasl.logWarning("Airportdata: failed to write airport meta index: " .. tostring(AIRPORT_META_IDX_FILE))
            return false
        end
        file:write("YALAPTMETAIDX\t1\n")
        file:write("EPOCH\t", tostring(tonumber(def.CACHE_EPOCH) or 1), "\n")
        file:write("PATH\t", tostring(meta.path or ""), "\n")
        file:write("SIZE\t", tostring(meta.size or 0), "\n")
        for icao, data in pairs(db) do
            local latitude = tonumber(data.latitude) or 0
            local longitude = tonumber(data.longitude) or 0
            local elevation = tonumber(data.elevation_ft) or 0
            local airport_type = tostring(data.airport_type or "")
            local max_rwy_ft = tonumber(data.max_rwy_ft) or 0
            local has_ils = (data.has_ils and 1) or 0
            file:write(
                tostring(icao), "\t",
                string.format("%.6f", latitude), "\t",
                string.format("%.6f", longitude), "\t",
                tostring(elevation), "\t",
                airport_type, "\t",
                tostring(max_rwy_ft), "\t",
                tostring(has_ils), "\n"
            )
        end
        file:close()
        return true
    end

    local function load_airport_meta_index(meta)
        local file = io.open(AIRPORT_META_IDX_FILE, "rb")
        if not file then
            return nil
        end
        local cache_epoch = tonumber(def.CACHE_EPOCH) or 1
        local idx_version = nil
        local idx_epoch = nil
        local idx_path = nil
        local idx_size = nil
        local entries = {}
        for line in file:lines() do
            local len = #line
            if len > 0 and string.byte(line, len) == 13 then
                line = string.sub(line, 1, len - 1)
            end
            if string.sub(line, 1, 14) == "YALAPTMETAIDX\t" then
                idx_version = tonumber(string.sub(line, 15)) or 0
            elseif string.sub(line, 1, 6) == "EPOCH\t" then
                idx_epoch = tonumber(string.sub(line, 7)) or 0
            elseif string.sub(line, 1, 5) == "PATH\t" then
                idx_path = string.sub(line, 6)
            elseif string.sub(line, 1, 5) == "SIZE\t" then
                idx_size = tonumber(string.sub(line, 6)) or 0
            else
                local icao, lat, lon, elev, atype, rwy, ils =
                    line:match("^(%S+)\t([-%d%.]+)\t([-%d%.]+)\t([-%d]+)\t([^\t]*)\t([-%d]+)\t([01])$")
                if icao then
                    entries[icao] = {
                        latitude = tonumber(lat),
                        longitude = tonumber(lon),
                        elevation_ft = tonumber(elev),
                        airport_type = atype,
                        max_rwy_ft = tonumber(rwy),
                        has_ils = (ils == "1")
                    }
                end
            end
        end
        file:close()
        if idx_version ~= 1 then
            P.logInfoTS("Airportdata cache invalid (index version mismatch), rebuilding.")
            pcall(function() os.remove(AIRPORT_META_IDX_FILE) end)
            return nil
        end
        if idx_epoch ~= cache_epoch then
            P.logInfoTS(
                "Airportdata cache invalid (cache epoch "
                    .. tostring(idx_epoch)
                    .. " != "
                    .. tostring(cache_epoch)
                    .. "), rebuilding."
            )
            pcall(function() os.remove(AIRPORT_META_IDX_FILE) end)
            return nil
        end
        if not meta or idx_path ~= meta.path or (idx_size or 0) ~= (meta.size or 0) then
            return nil
        end
        return entries
    end

    local meta = compute_airport_meta()
    if not meta then
        sasl.logError("Could not stat " .. tostring(AIRPORT_META_PATH))
        return false
    end

    local cached = load_airport_meta_index(meta)
    if cached and next(cached) ~= nil then
        for icao, entry in pairs(cached) do
            airport_db[icao] = entry
        end
        P.logInfoTS(
            "Global Airports Airportdata Table loaded from cache, "
                .. tostring(P.getTableSize(airport_db))
                .. " entries."
        )
        return true
    end

    local file = io.open(AIRPORT_META_PATH, "rb")


    if not file then
        sasl.logError("Could not open " .. tostring(AIRPORT_META_PATH))
        return false
    end

    local line_count = 0

    for line in file:lines() do
        local icao, _, lat, lon, elev, type, rwy, ils = 
            line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
        

        if icao then
            airport_db[icao] = {
                latitude     = tonumber(lat),
                longitude    = tonumber(lon),
                elevation_ft = tonumber(elev),
                airport_type = type,
                max_rwy_ft   = tonumber(rwy),
                has_ils      = (ils == "I")
            }
            line_count = line_count + 1
        end
    end

    -- Datei wieder schließen
    file:close()

    write_airport_meta_index(meta, airport_db)

    P.logInfoTS("Global Airports Airportdata Table created, " .. line_count .. " entries.")

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.writeairportdatatable(airport_db)
    local basePath = def.PLUGINOUTPUTPATH
    local destairportfile = io.open(basePath .. "yal_apt.dat", "w")

    if not destairportfile then
        sasl.logError("Could not open " .. basePath .. "yal_apt.dat")
        return false
    end

    for icao, data in pairs(airport_db) do
        local latitude = tonumber(data.latitude) or 0
        local longitude = tonumber(data.longitude) or 0
        local elevation = tonumber(data.elevation_ft) or 0
        local airport_type = tostring(data.airport_type or "")
        local max_rwy_ft = tonumber(data.max_rwy_ft) or 0
        local has_ils = (data.has_ils and 1) or 0

        destairportfile:write(string.format(
            "%s %.6f %.6f %d %s %d %d\n",
            tostring(icao),
            latitude,
            longitude,
            elevation,
            airport_type,
            max_rwy_ft,
            has_ils
        ))
    end

    destairportfile:close()

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.writetaxidatatable()
    if not (P.global_apt_index_ready == true and P.global_apt_index and next(P.global_apt_index) ~= nil) then
        P.logInfoTS("Global Airports Taxidata Table dump skipped (index not ready).")
        return false
    end

    local basePath = def.PLUGINOUTPUTPATH
    local destfile = io.open(basePath .. "yal_taxi.dat", "w")
    if not destfile then
        sasl.logError("Could not open " .. basePath .. "yal_taxi.dat")
        return false
    end

    local function write_line(text)
        destfile:write(tostring(text or "") .. "\n")
    end

    local keys = {}
    for icao, _ in pairs(P.global_apt_index) do
        keys[#keys + 1] = icao
    end
    table.sort(keys)

    write_line("YAL Taxidata Dump")
    write_line("Entries: " .. tostring(#keys))

    local function sorted_node_ids(nodes)
        local ids = {}
        for id, _ in pairs(nodes or {}) do
            ids[#ids + 1] = id
        end
        table.sort(ids, function(a, b)
            return (tonumber(a) or 0) < (tonumber(b) or 0)
        end)
        return ids
    end

    for _, icao in ipairs(keys) do
        local entry = P.global_apt_index[icao]
        if entry then
            entry.icao = icao
            write_line("")
            write_line("ICAO " .. tostring(icao))
            write_line(
                "ENTRY path=" .. tostring(entry.path)
                    .. " offset=" .. tostring(entry.offset)
                    .. " length=" .. tostring(entry.length)
                    .. " has_routes=" .. tostring(entry.has_routes)
                    .. " source=" .. tostring(entry.source)
            )
            local data, err = parse_taxi_data(entry)
            if not data then
                write_line("ERROR " .. tostring(err))
            else
                write_line(
                    "META route_source=" .. tostring(data.route_source)
                        .. " has_routes=" .. tostring(data.has_routes)
                        .. " has_fallback=" .. tostring(data.has_fallback)
                )
                write_line("NODES " .. tostring(P.getTableSize(data.nodes or {})))
                for _, id in ipairs(sorted_node_ids(data.nodes)) do
                    local node = data.nodes[id]
                    if node then
                        write_line(
                            string.format(
                                "NODE %s %.6f %.6f %.2f %.2f ramp=%s",
                                tostring(id),
                                tonumber(node.lat) or 0,
                                tonumber(node.lon) or 0,
                                tonumber(node.east) or 0,
                                tonumber(node.north) or 0,
                                node.is_ramp and "1" or "0"
                            )
                        )
                    end
                end

                write_line("EDGES " .. tostring(#(data.edges or {})))
                for _, edge in ipairs(data.edges or {}) do
                    write_line(
                        string.format(
                            "EDGE %s %s %s %s",
                            tostring(edge.from),
                            tostring(edge.to),
                            tostring(edge.dir or ""),
                            tostring(edge.label or "")
                        )
                    )
                end

                write_line("RAMPS " .. tostring(#(data.ramps or {})))
                for _, ramp in ipairs(data.ramps or {}) do
                    write_line(
                        string.format(
                            "RAMP %.6f %.6f heading=%.1f type=%s size=%s op=%s name=%s node=%s anchor=%s",
                            tonumber(ramp.lat) or 0,
                            tonumber(ramp.lon) or 0,
                            tonumber(ramp.heading) or 0,
                            tostring(ramp.ramp_type or ""),
                            tostring(ramp.ramp_size or ""),
                            tostring(ramp.ramp_operation or ""),
                            tostring(ramp.name or ""),
                            tostring(ramp.node_id or ""),
                            tostring(ramp.route_anchor_node_id or "")
                        )
                    )
                end

                write_line("RUNWAYS " .. tostring(#(data.runways or {})))
                for _, rwy in ipairs(data.runways or {}) do
                    write_line(
                        string.format(
                            "RWY %s %.6f %.6f %s %.6f %.6f width=%.1f",
                            tostring(rwy.rwy1 or ""),
                            tonumber(rwy.lat1) or 0,
                            tonumber(rwy.lon1) or 0,
                            tostring(rwy.rwy2 or ""),
                            tonumber(rwy.lat2) or 0,
                            tonumber(rwy.lon2) or 0,
                            tonumber(rwy.width) or 0
                        )
                    )
                end

                write_line("POLYGONS " .. tostring(#(data.polygons or {})))
                for i, poly in ipairs(data.polygons or {}) do
                    local pts = poly.points or {}
                    write_line("POLY " .. tostring(i) .. " points=" .. tostring(#pts))
                    for _, pt in ipairs(pts) do
                        write_line(
                            string.format(
                                "PT %.2f %.2f",
                                tonumber(pt.east) or 0,
                                tonumber(pt.north) or 0
                            )
                        )
                    end
                end
            end
        end
    end

    destfile:close()
    P.logInfoTS("Global Airports Taxidata Table dump created.")
    return true
end

--------------------------------------------------------------------------------------------------------------
-- Taxi routing: apt.dat locator

local function is_space_byte(byte)
    return byte == 32 or byte == 9 or byte == 10 or byte == 13
end

local function trim_ascii(text)
    if not text then
        return ""
    end
    local start_idx = 1
    local end_idx = #text
    while start_idx <= end_idx do
        local b = string.byte(text, start_idx)
        if b and not is_space_byte(b) then
            break
        end
        start_idx = start_idx + 1
    end
    while end_idx >= start_idx do
        local b = string.byte(text, end_idx)
        if b and not is_space_byte(b) then
            break
        end
        end_idx = end_idx - 1
    end
    if end_idx < start_idx then
        return ""
    end
    return string.sub(text, start_idx, end_idx)
end

local function next_token(line, pos)
    local len = #line
    local i = pos or 1
    while i <= len do
        local b = string.byte(line, i)
        if b and not is_space_byte(b) then
            break
        end
        i = i + 1
    end
    if i > len then
        return nil, len + 1
    end
    local start_idx = i
    i = i + 1
    while i <= len do
        local b = string.byte(line, i)
        if b and is_space_byte(b) then
            break
        end
        i = i + 1
    end
    return string.sub(line, start_idx, i - 1), i
end

local function split_pipe(line)
    local parts = {}
    local start_idx = 1
    for i = 1, #line do
        if string.byte(line, i) == 124 then
            parts[#parts + 1] = string.sub(line, start_idx, i - 1)
            start_idx = i + 1
        end
    end
    parts[#parts + 1] = string.sub(line, start_idx)
    return parts
end

local function tokenize_line(line)
    local tokens = {}
    local pos = 1
    while true do
        local tok
        tok, pos = next_token(line, pos)
        if not tok then
            break
        end
        tokens[#tokens + 1] = tok
    end
    return tokens
end

local function get_file_size(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local size = file:seek("end")
    file:close()
    return size
end

local lfs_ok, lfs = pcall(require, "lfs")

local function get_file_mtime(path)
    if not lfs_ok or not lfs or not path then
        return nil
    end
    local ok, attr = pcall(lfs.attributes, path)
    if not ok or not attr then
        return nil
    end
    local mtime = attr.modification
    if type(mtime) ~= "number" then
        return nil
    end
    return math.floor(mtime)
end

local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619
local FNV_MOD = 4294967296

local bit_ok, bit = pcall(require, "bit")
if not bit_ok then
    bit = _G.bit
end
local bit32_ok, bit32 = pcall(require, "bit32")
if not bit32_ok then
    bit32 = _G.bit32
end
local bxor = (bit and bit.bxor) or (bit32 and bit32.bxor) or nil

local function xor32(a, b)
    if bxor then
        return bxor(a, b)
    end
    -- Portable (but slower) XOR fallback for small samples.
    local res = 0
    local bitval = 1
    local aa = math.floor(a or 0)
    local bb = math.floor(b or 0)
    for _ = 1, 32 do
        local abit = aa % 2
        local bbit = bb % 2
        if abit ~= bbit then
            res = res + bitval
        end
        aa = (aa - abit) / 2
        bb = (bb - bbit) / 2
        bitval = bitval * 2
    end
    return res
end

local function fnv1a_update(hash, chunk)
    if not chunk or chunk == "" then
        return hash
    end
    local h = hash or FNV_OFFSET
    for i = 1, #chunk do
        local b = string.byte(chunk, i)
        if b then
            h = xor32(h, b)
            h = (h * FNV_PRIME) % FNV_MOD
        end
    end
    return h
end

local function compute_file_fingerprint(path, size, sample_bytes)
    if not path then
        return nil
    end
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local ok = true
    local function read_at(offset, bytes)
        if not ok then
            return ""
        end
        local o = offset or 0
        if o < 0 then
            o = 0
        end
        ok = file:seek("set", o) ~= nil
        if not ok then
            return ""
        end
        return file:read(bytes) or ""
    end

    local sz = size or get_file_size(path) or 0
    local bytes = math.floor(sample_bytes or 2048)
    if bytes < 256 then
        bytes = 256
    end
    if sz > 0 and bytes > sz then
        bytes = sz
    end
    if bytes <= 0 then
        file:close()
        return nil
    end

    local max_offset = math.max(0, sz - bytes)
    local half = math.floor(bytes / 2)
    local positions = {
        0,
        math.max(0, math.floor(sz * 0.25) - half),
        math.max(0, math.floor(sz * 0.50) - half),
        math.max(0, math.floor(sz * 0.75) - half),
        max_offset
    }
    local seen = {}
    local hash = FNV_OFFSET
    for _, pos in ipairs(positions) do
        local p = pos
        if p > max_offset then
            p = max_offset
        end
        if not seen[p] then
            seen[p] = true
            local chunk = read_at(p, bytes)
            hash = fnv1a_update(hash, chunk)
        end
    end
    file:close()
    local out = math.floor(hash % FNV_MOD)
    return string.format("%08x", out)
end

local function global_apt_path()
    return sasl.getXPlanePath() .. def.OSSEPARATOR .. "Global Scenery" .. def.OSSEPARATOR .. "Global Airports"
        .. def.OSSEPARATOR .. "Earth nav data" .. def.OSSEPARATOR .. "apt.dat"
end

local GLOBAL_APT_INDEX_VERSION = 8
local GLOBAL_APT_INDEX_FILE = def.PLUGINOUTPUTPATH .. "apt_global.yalidx"
local GLOBAL_APT_META_REFRESH_SEC = 30
local GLOBAL_APT_INDEX_STEP_LINES = 10000
local GLOBAL_APT_INDEX_STEP_SEC = 0.0015
local GLOBAL_APT_FINGERPRINT_BYTES = 2048
local GLOBAL_APT_INDEX_FAST_LINES = 20000000

local function is_global_apt(path)
    if not path then
        return false
    end
    return path == global_apt_path()
end

local function is_absolute_path(path)
    if not path or path == "" then
        return false
    end
    local first = string.sub(path, 1, 1)
    if first == "/" or first == "\\" then
        return true
    end
    if #path >= 2 and string.sub(path, 2, 2) == ":" then
        return true
    end
    return false
end

local function ensure_trailing_sep(path)
    local last = string.sub(path, -1)
    if last == "/" or last == "\\" then
        return path
    end
    return path .. def.OSSEPARATOR
end

local function normalize_pack_path(path)
    path = trim_ascii(path)
    if path == "" then
        return nil
    end
    if string.sub(path, 1, 1) == "\"" and string.sub(path, -1) == "\"" then
        path = string.sub(path, 2, -2)
    end
    if not is_absolute_path(path) then
        path = sasl.getXPlanePath() .. def.OSSEPARATOR .. path
    end
    return ensure_trailing_sep(path)
end

local function get_active_scenery_packs()
    local packs = {}
    local ini_path = sasl.getXPlanePath() .. def.OSSEPARATOR .. "Custom Scenery" .. def.OSSEPARATOR .. "scenery_packs.ini"
    local file = io.open(ini_path, "r")
    if not file then
        return packs
    end
    for line in file:lines() do
        local token, pos = next_token(line, 1)
        if token == "SCENERY_PACK" then
            local rest = trim_ascii(string.sub(line, pos))
            if rest ~= "" then
                local full_path = normalize_pack_path(rest)
                if full_path then
                    packs[#packs + 1] = full_path
                end
            end
        end
    end
    file:close()
    return packs
end

local function build_apt_search_paths(include_global)
    if include_global == nil then
        include_global = false
    end
    local paths = {}
    local seen = {}
    local packs = get_active_scenery_packs()
    for _, pack_path in ipairs(packs) do
        local apt_path = pack_path .. "Earth nav data" .. def.OSSEPARATOR .. "apt.dat"
        if not seen[apt_path] and P.file_exists_v2(apt_path) then
            seen[apt_path] = true
            paths[#paths + 1] = apt_path
        end
    end
    if include_global then
        local global_apt = global_apt_path()
        if not seen[global_apt] and P.file_exists_v2(global_apt) then
            seen[global_apt] = true
            paths[#paths + 1] = global_apt
        end
    end
    return paths
end

P.addon_apt_cache = P.addon_apt_cache or {}

local function get_addon_apt_paths()
    local paths = build_apt_search_paths(false)
    local key = table.concat(paths, "|")
    if key ~= (P.addon_apt_cache_key or "") then
        P.addon_apt_cache_key = key
        P.addon_apt_cache = {}
    end
    return paths, key
end

local function is_int_token(token)
    if not token or token == "" then
        return false
    end
    local len = #token
    local i = 1
    if string.byte(token, 1) == 45 then
        if len == 1 then
            return false
        end
        i = 2
    end
    while i <= len do
        local b = string.byte(token, i)
        if not b or b < 48 or b > 57 then
            return false
        end
        i = i + 1
    end
    return true
end

local function is_icao_token(token)
    if not token or token == "" then
        return false
    end
    local t = string.upper(token)
    local len = #t
    if len < 3 or len > 4 then
        return false
    end
    for i = 1, len do
        local b = string.byte(t, i)
        if not b then
            return false
        end
        local is_digit = (b >= 48 and b <= 57)
        local is_alpha = (b >= 65 and b <= 90)
        if not is_digit and not is_alpha then
            return false
        end
    end
    return true
end

local function parse_airport_header_icao(line)
    local token, pos = next_token(line, 1)
    if token ~= "1" and token ~= "16" and token ~= "17" then
        return nil
    end
    local t2, t3, t4, t5 = nil, nil, nil, nil
    t2, pos = next_token(line, pos)
    t3, pos = next_token(line, pos)
    t4, pos = next_token(line, pos)
    t5, pos = next_token(line, pos)
    if not (t2 and t3 and t4 and t5) then
        return nil
    end
    if not (is_int_token(t2) and is_int_token(t3) and is_int_token(t4)) then
        return nil
    end
    if not is_icao_token(t5) then
        return nil
    end
    return t5
end

local function scan_apt_for_icao(apt_path, target_icao)
    local file = io.open(apt_path, "rb")
    if not file then
        return nil, "open-failed"
    end
    local found_offset = nil
    local has_routes = false
    local block_end = nil
    while true do
        local line_pos = file:seek()
        local line = file:read("*l")
        if not line then
            break
        end
        local header_icao = parse_airport_header_icao(line)
        if header_icao then
            header_icao = string.upper(header_icao)
            if found_offset then
                block_end = line_pos
                break
            end
            if header_icao == target_icao then
                found_offset = line_pos
                has_routes = false
            end
        elseif found_offset then
            local code = next_token(line, 1)
            if code == "1201" or code == "1202" or code == "1206" then
                has_routes = true
            end
        end
    end
    local size = file:seek("end")
    file:close()
    if not found_offset then
        return nil, "not-found"
    end
    if not block_end then
        block_end = size or found_offset
    end
    return {
        icao = target_icao,
        path = apt_path,
        offset = found_offset,
        length = block_end - found_offset,
        size = size or 0,
        has_routes = has_routes
    }
end


local function build_taxi_label(tokens)
    if #tokens < 5 then
        return ""
    end
    local kind = tokens[5]
    if not kind then
        return ""
    end
    if kind == "runway" then
        local rwy = tokens[6] or ""
        if rwy ~= "" then
            return "RWY " .. rwy
        end
        return "RWY"
    end
    if kind:sub(1, 8) == "taxiway" then
        local name = kind:gsub("^taxiway[_%-]*", "")
        local suffix = tokens[6] or ""
        if name == "" then
            name = suffix
            suffix = ""
        end
        local label = name
        if suffix ~= "" and suffix ~= name then
            local name_trim = trim_ascii(name)
            local suffix_trim = trim_ascii(suffix)
            if #name_trim == 1 and suffix_trim ~= "" then
                label = suffix_trim
            else
                label = name_trim .. " " .. suffix_trim
            end
        end
        return trim_ascii(label)
    end
    return trim_ascii(table.concat(tokens, " ", 5))
end

local function is_runway_label(label)
    if not label or label == "" then
        return false
    end
    return string.sub(label, 1, 3) == "RWY"
end

local function geo_scale(ref_lat)
    if not ref_lat then
        return nil, nil
    end
    local lat_rad = math.rad(ref_lat)
    local m_per_deg_lat = 111132.92 - 559.82 * math.cos(2 * lat_rad) + 1.175 * math.cos(4 * lat_rad) - 0.0023 * math.cos(6 * lat_rad)
    local m_per_deg_lon = 111412.84 * math.cos(lat_rad) - 93.5 * math.cos(3 * lat_rad) + 0.118 * math.cos(5 * lat_rad)
    return m_per_deg_lat, m_per_deg_lon
end

function P.geoScale(ref_lat)
    return geo_scale(ref_lat)
end

function P.projectLatLon(lat, lon, ref_lat, ref_lon, mlat, mlon)
    if not (ref_lat and ref_lon and lat and lon) then
        return nil, nil
    end
    if not (mlat and mlon) then
        mlat, mlon = geo_scale(ref_lat)
    end
    if not (mlat and mlon) then
        return nil, nil
    end
    local east = (lon - ref_lon) * mlon
    local north = (lat - ref_lat) * mlat
    return east, north
end

function P.localToLatLon(east, north, ref_lat, ref_lon, mlat, mlon)
    if not (ref_lat and ref_lon and east ~= nil and north ~= nil) then
        return nil, nil
    end
    if not (mlat and mlon) then
        mlat, mlon = geo_scale(ref_lat)
    end
    if not (mlat and mlon) then
        return nil, nil
    end
    local lat = ref_lat + (north / mlat)
    local lon = ref_lon + (east / mlon)
    return lat, lon
end

local function project_to_local(lat, lon, ref_lat, ref_lon, mlat, mlon)
    if type(ref_lat) == "table" then
        local ref = ref_lat
        ref_lat = ref.ref_lat
        ref_lon = ref.ref_lon
        mlat = ref.ref_mlat
        mlon = ref.ref_mlon
    end
    if ref_lat and ref_lon then
        local east, north = P.projectLatLon(lat, lon, ref_lat, ref_lon, mlat, mlon)
        if east ~= nil and north ~= nil then
            return east, -north
        end
    end
    local x, _, z = sasl.worldToLocal(lat, lon, 0)
    return x, z
end

local function update_bounds(bounds, x, y)
    if not bounds.minX or x < bounds.minX then bounds.minX = x end
    if not bounds.maxX or x > bounds.maxX then bounds.maxX = x end
    if not bounds.minY or y < bounds.minY then bounds.minY = y end
    if not bounds.maxY or y > bounds.maxY then bounds.maxY = y end
end

local function parse_taxi_data(entry)
    if not entry or not entry.path or not entry.offset then
        return nil, "invalid-entry"
    end
    local file = io.open(entry.path, "rb")
    if not file then
        return nil, "open-failed"
    end
    file:seek("set", entry.offset)
    local limit = entry.offset + (entry.length or 0)
    local strict_limit = limit > entry.offset
    local allow_extend = entry.source == "global-index"
    local extended = false
    local target_icao = entry.icao
    if allow_extend and entry.has_routes == false then
        strict_limit = false
        extended = true
    end
    local nodes = {}
    local edges = {}
    local ramps = {}
    local runways = {}
    local polygons = {}
    local has_routes = false
    local fallback_polys = {}
    local current_poly = nil
    local last_ramp = nil

    local function finalize_poly()
        if current_poly and #current_poly >= 2 then
            fallback_polys[#fallback_polys + 1] = current_poly
        end
        current_poly = nil
    end

    local function add_poly_point(poly, lat, lon)
        if not poly or not lat or not lon then
            return
        end
        local last = poly[#poly]
        if last and math.abs(last.lat - lat) < 1e-7 and math.abs(last.lon - lon) < 1e-7 then
            return
        end
        poly[#poly + 1] = { lat = lat, lon = lon }
    end

    local function build_fallback_graph(polys)
        local f_nodes = {}
        local f_edges = {}
        local node_by_key = {}
        local next_id = 1
        local function node_key(lat, lon)
            return string.format("%.6f|%.6f", lat, lon)
        end
        local function add_node(lat, lon)
            local key = node_key(lat, lon)
            local id = node_by_key[key]
            if not id then
                id = next_id
                next_id = next_id + 1
                node_by_key[key] = id
                f_nodes[id] = { id = id, lat = lat, lon = lon }
            end
            return id
        end
        for _, poly in ipairs(polys) do
            local first_id = nil
            local prev_id = nil
            for _, pt in ipairs(poly) do
                if pt.lat and pt.lon then
                    local id = add_node(pt.lat, pt.lon)
                    if not first_id then
                        first_id = id
                    end
                    if prev_id and prev_id ~= id then
                        f_edges[#f_edges + 1] = { from = prev_id, to = id, dir = "both", label = "TWY" }
                    end
                    prev_id = id
                end
            end
            -- Do not close the polygon loop (last -> first). For taxiway polygons
            -- this creates artificial long edges and spaghetti routes.
        end
        return f_nodes, f_edges
    end

    local function add_ramp_links(nodes_tbl, ramps_tbl, runway_nodes_tbl, max_dist, edge_nodes_tbl, edges_tbl)
        local near_links = {}
        local far_links = {}
        if not nodes_tbl or not ramps_tbl or max_dist <= 0 then
            return near_links, far_links, edges_tbl
        end
        local max_id = 0
        for id, _ in pairs(nodes_tbl) do
            if type(id) == "number" and id > max_id then
                max_id = id
            end
        end
        local next_id = max_id + 1
        local max_d2 = max_dist * max_dist
        local has_edge_filter = edge_nodes_tbl and next(edge_nodes_tbl) ~= nil

        local EDGE_PROJ_REUSE_M = 8
        local EDGE_PROJ_ENDPOINT_SNAP_M = 3
        local HEADING_RADIUS_M = 150
        local HEADING_ANGLE_DEG = 60
        local reuse_d2 = EDGE_PROJ_REUSE_M * EDGE_PROJ_REUSE_M
        local endpoint_d2 = EDGE_PROJ_ENDPOINT_SNAP_M * EDGE_PROJ_ENDPOINT_SNAP_M
        local heading_radius2 = HEADING_RADIUS_M * HEADING_RADIUS_M
        local heading_cos = math.cos(math.rad(HEADING_ANGLE_DEG))

        local edge_projections = {}

        local function project_point_to_segment(px, py, x1, y1, x2, y2)
            local dx = x2 - x1
            local dy = y2 - y1
            local len2 = dx * dx + dy * dy
            if len2 <= 1e-6 then
                return x1, y1, 0
            end
            local t = ((px - x1) * dx + (py - y1) * dy) / len2
            if t < 0 then
                t = 0
            elseif t > 1 then
                t = 1
            end
            return x1 + dx * t, y1 + dy * t, t
        end

        local function find_best_edge(ramp)
            if not edges_tbl then
                return nil
            end
            local best = nil
            local best_any = nil
            local best_nearest_nonrunway = nil
            local best_gate_backward = nil
            local best_heading = nil
            local best_forward = nil
            local heading = tonumber(ramp.heading)
            local dir_e = nil
            local dir_n = nil
            local ramp_type = string.lower(tostring(ramp.ramp_type or ""))
            local is_gate = (ramp_type == "gate")
            local prefer_local_misc_link = (ramp_type == "misc")
            if heading then
                local rad = math.rad(heading % 360)
                dir_e = math.sin(rad)
                dir_n = math.cos(rad)
            end
            for idx, edge in ipairs(edges_tbl) do
                local n1 = nodes_tbl[edge.from]
                local n2 = nodes_tbl[edge.to]
                if n1 and n2 and n1.east and n1.north and n2.east and n2.north then
                    local px, py, t = project_point_to_segment(ramp.east, ramp.north, n1.east, n1.north, n2.east, n2.north)
                    local dx = ramp.east - px
                    local dy = ramp.north - py
                    local d2 = dx * dx + dy * dy
                    local is_runway = is_runway_label(edge.label or "")
                    local entry = {
                        edge = edge,
                        edge_index = idx,
                        proj_east = px,
                        proj_north = py,
                        t = t,
                        d2 = d2,
                        score = d2
                    }
                    if not best_any or d2 < best_any.d2 then
                        best_any = entry
                    end
                    if not is_runway then
                        local along = nil
                        local cross = nil
                        local score = d2
                        if not best_nearest_nonrunway or d2 < best_nearest_nonrunway.d2 then
                            best_nearest_nonrunway = entry
                        end
                        if dir_e then
                            local vx = px - ramp.east
                            local vy = py - ramp.north
                            along = vx * dir_e + vy * dir_n
                            cross = math.abs(vx * dir_n - vy * dir_e)
                            local behind = 0
                            if along < 0 then
                                behind = ((-along) * (-along)) * 4
                            end
                            score = d2 + (cross * cross) + behind
                            entry.along = along
                            entry.cross = cross
                        end
                        entry.score = score
                        if is_gate then
                            local gate_cross = cross or 0
                            local gate_score = d2 + (gate_cross * gate_cross)
                            local ahead = 0
                            if along and along > 5 then
                                ahead = ((along - 5) * (along - 5)) * 4
                            end
                            gate_score = gate_score + ahead
                            entry.gate_score = gate_score
                            if not best_gate_backward or gate_score < best_gate_backward.gate_score then
                                best_gate_backward = entry
                            end
                        end
                        if not best or score < best.score then
                            best = entry
                        end
                        if dir_e and along ~= nil then
                            if along >= -5 and (not best_forward or score < best_forward.score) then
                                best_forward = entry
                            end
                        end
                        if dir_e and d2 <= heading_radius2 then
                            local vx = px - ramp.east
                            local vy = py - ramp.north
                            local v2 = vx * vx + vy * vy
                            local ok = false
                            if v2 <= 1e-6 then
                                ok = true
                            else
                                local inv_len = 1 / math.sqrt(v2)
                                local dot = (vx * dir_e + vy * dir_n) * inv_len
                                ok = (dot >= heading_cos)
                            end
                            if ok and along and along >= -5 and (not best_heading or score < best_heading.score) then
                                best_heading = entry
                            end
                        end
                    end
                end
            end
            local choice = nil
            local mode = nil
            if is_gate then
                choice = best_gate_backward or best_nearest_nonrunway
                if choice == best_gate_backward and dir_e then
                    mode = "gate-backward"
                else
                    mode = "gate-nearest-nonrunway"
                end
            elseif prefer_local_misc_link then
                choice = best_nearest_nonrunway or best
                mode = "misc-nearest-nonrunway"
                if choice and dir_e then
                    local choice_bad = false
                    local choice_dist = math.sqrt(choice.d2 or 0)
                    if choice_dist > 60 then
                        choice_bad = true
                    end
                    if choice.along ~= nil and choice.along < -20 then
                        choice_bad = true
                    end
                    if choice.cross ~= nil and choice.cross > 18 then
                        choice_bad = true
                    end
                    local better = best_heading or best_forward or best
                    if choice_bad and better and better ~= choice then
                        choice = better
                        if better == best_heading then
                            mode = "misc-heading"
                        elseif better == best_forward then
                            mode = "misc-forward"
                        else
                            mode = "misc-scored"
                        end
                    end
                end
            else
                choice = best_heading
                mode = "heading"
                if not choice then
                    choice = best_forward
                    mode = "forward"
                end
                if not choice then
                    choice = best
                    mode = "nearest-nonrunway"
                end
            end
            if not choice then
                choice = best_any
                mode = "nearest-any"
            end
            if choice then
                choice.mode = mode
            end
            return choice
        end

        local function get_or_create_proj_node(best_edge)
            if not best_edge or not best_edge.edge then
                return nil
            end
            local edge = best_edge.edge
            local idx = best_edge.edge_index
            local n1 = nodes_tbl[edge.from]
            local n2 = nodes_tbl[edge.to]
            if not (n1 and n2 and n1.east and n1.north and n2.east and n2.north) then
                return nil
            end
            local px = best_edge.proj_east
            local py = best_edge.proj_north
            local t = best_edge.t or 0

            local dx1 = px - n1.east
            local dy1 = py - n1.north
            if (dx1 * dx1 + dy1 * dy1) <= endpoint_d2 then
                return edge.from
            end
            local dx2 = px - n2.east
            local dy2 = py - n2.north
            if (dx2 * dx2 + dy2 * dy2) <= endpoint_d2 then
                return edge.to
            end

            local list = edge_projections[idx]
            if list then
                for _, proj in ipairs(list) do
                    local dx = proj.east - px
                    local dy = proj.north - py
                    if (dx * dx + dy * dy) <= reuse_d2 then
                        return proj.node_id
                    end
                end
            end

            local proj_id = next_id
            next_id = next_id + 1
            local lat = nil
            local lon = nil
            if n1.lat and n1.lon and n2.lat and n2.lon then
                lat = n1.lat + (n2.lat - n1.lat) * t
                lon = n1.lon + (n2.lon - n1.lon) * t
            end
            nodes_tbl[proj_id] = {
                id = proj_id,
                lat = lat,
                lon = lon,
                x = px,
                z = -py,
                east = px,
                north = py,
                is_ramp_link = true
            }
            edge_projections[idx] = edge_projections[idx] or {}
            edge_projections[idx][#edge_projections[idx] + 1] = { node_id = proj_id, t = t, east = px, north = py }
            return proj_id
        end

        for _, ramp in ipairs(ramps_tbl) do
            if ramp.x and ramp.z and ramp.east and ramp.north then
                ramp.link_node_id = nil
                ramp.link_edge_from = nil
                ramp.link_edge_to = nil
                ramp.link_edge_label = nil
                ramp.link_distance_m = nil
                ramp.link_score = nil
                ramp.link_mode = nil
                ramp.link_along = nil
                ramp.link_cross = nil
                ramp.route_anchor_node_id = nil
                local rid = next_id
                next_id = next_id + 1
                nodes_tbl[rid] = {
                    id = rid,
                    lat = ramp.lat,
                    lon = ramp.lon,
                    x = ramp.x,
                    z = ramp.z,
                    east = ramp.east,
                    north = ramp.north,
                    is_ramp = true
                }
                ramp.node_id = rid

                local linked = false
                local best_edge = find_best_edge(ramp)
                if best_edge and best_edge.d2 then
                    local proj_id = get_or_create_proj_node(best_edge)
                    if proj_id then
                        far_links[#far_links + 1] = { from = rid, to = proj_id }
                        if best_edge.d2 <= max_d2 then
                            near_links[#near_links + 1] = { from = rid, to = proj_id }
                        end
                        ramp.link_node_id = proj_id
                        ramp.link_edge_from = best_edge.edge and best_edge.edge.from or nil
                        ramp.link_edge_to = best_edge.edge and best_edge.edge.to or nil
                        ramp.link_edge_label = best_edge.edge and best_edge.edge.label or nil
                        ramp.link_distance_m = math.sqrt(best_edge.d2 or 0)
                        ramp.link_score = best_edge.score or best_edge.d2
                        ramp.link_mode = best_edge.mode or "edge"
                        ramp.link_along = best_edge.along
                        ramp.link_cross = best_edge.cross
                        ramp.route_anchor_node_id = proj_id
                        linked = true
                    end
                end

                if not linked then
                    local function find_best(require_edge)
                        local best_id = nil
                        local best_d2 = nil
                        local best_nr_id = nil
                        local best_nr_d2 = nil
                        for id, node in pairs(nodes_tbl) do
                            if node and not node.is_ramp and not node.is_ramp_link and node.x and node.z then
                                if require_edge and (not edge_nodes_tbl or not edge_nodes_tbl[id]) then
                                    goto continue
                                end
                                local dx = node.x - ramp.x
                                local dz = node.z - ramp.z
                                local d2 = dx * dx + dz * dz
                                if not best_d2 or d2 < best_d2 then
                                    best_d2 = d2
                                    best_id = id
                                end
                                if runway_nodes_tbl and not runway_nodes_tbl[id] then
                                    if not best_nr_d2 or d2 < best_nr_d2 then
                                        best_nr_d2 = d2
                                        best_nr_id = id
                                    end
                                end
                            end
                            ::continue::
                        end
                        return best_id, best_d2, best_nr_id, best_nr_d2
                    end

                    local best_id, best_d2, best_nr_id, best_nr_d2 = find_best(has_edge_filter)
                    if not best_id and not best_nr_id and has_edge_filter then
                        best_id, best_d2, best_nr_id, best_nr_d2 = find_best(false)
                    end
                    local link_id = best_nr_id or best_id
                    local link_d2 = best_nr_id and best_nr_d2 or best_d2
                    if link_id and link_d2 then
                        far_links[#far_links + 1] = { from = rid, to = link_id }
                        if link_d2 <= max_d2 then
                            near_links[#near_links + 1] = { from = rid, to = link_id }
                        end
                        ramp.link_node_id = link_id
                        ramp.link_distance_m = math.sqrt(link_d2 or 0)
                        ramp.link_score = link_d2
                        if best_nr_id and link_id == best_nr_id then
                            ramp.link_mode = "nearest-node-nonrunway"
                        else
                            ramp.link_mode = "nearest-node"
                        end
                        ramp.route_anchor_node_id = link_id
                    end
                end
                if not ramp.route_anchor_node_id then
                    ramp.route_anchor_node_id = rid
                end
            end
        end

        local edges_out = edges_tbl
        if edges_tbl and next(edge_projections) ~= nil then
            local new_edges = {}
            for idx, edge in ipairs(edges_tbl) do
                local projs = edge_projections[idx]
                if projs and #projs > 0 then
                    table.sort(projs, function(a, b)
                        return (a.t or 0) < (b.t or 0)
                    end)
                    local prev = edge.from
                    for _, proj in ipairs(projs) do
                        if proj.node_id and proj.node_id ~= prev then
                            new_edges[#new_edges + 1] = { from = prev, to = proj.node_id, dir = edge.dir, label = edge.label }
                            prev = proj.node_id
                        end
                    end
                    if prev ~= edge.to then
                        new_edges[#new_edges + 1] = { from = prev, to = edge.to, dir = edge.dir, label = edge.label }
                    end
                else
                    new_edges[#new_edges + 1] = edge
                end
            end
            edges_out = new_edges
        end

        return near_links, far_links, edges_out
    end

    local debug_icao = (target_icao == "KCAE")
    if debug_icao and not (P.taxi_debug_once and P.taxi_debug_once[target_icao]) then
        P.taxi_debug_once = P.taxi_debug_once or {}
        P.taxi_debug_once[target_icao] = true
        helpers.logInfoTS(
            "TaxiParse: " .. tostring(target_icao)
                .. " path=" .. tostring(entry.path)
                .. " offset=" .. tostring(entry.offset)
                .. " length=" .. tostring(entry.length)
                .. " has_routes=" .. tostring(entry.has_routes)
                .. " strict_limit=" .. tostring(strict_limit)
                .. " extended=" .. tostring(extended)
        )
    end
    local debug_1201 = 0
    while true do
        local pos = file:seek()
        if not pos then break end
        if strict_limit and pos >= limit then
            if allow_extend and not has_routes then
                strict_limit = false
                extended = true
            else
                break
            end
        end
        local line = file:read("*l")
        if not line then
            break
        end
        if extended then
            local header_icao = parse_airport_header_icao(line)
            if header_icao then
                header_icao = string.upper(header_icao)
                if not target_icao then
                    target_icao = header_icao
                elseif header_icao ~= target_icao then
                    break
                end
            end
        end
        local code = next_token(line, 1)
        if code ~= "1201" and code ~= "1202" and code ~= "1206" then
            local i = 1
            local len = #line
            while i <= len do
                local b = string.byte(line, i)
                if b and not is_space_byte(b) then
                    break
                end
                i = i + 1
            end
            if i <= len then
                local prefix = string.sub(line, i, i + 3)
                if prefix == "1201" or prefix == "1202" or prefix == "1206" then
                    code = prefix
                end
            end
        end
        if code == "110" then
            finalize_poly()
            current_poly = {}
        elseif current_poly and (code == "111" or code == "112" or code == "113" or code == "114") then
            local tokens = tokenize_line(line)
            local lat = nil
            local lon = nil
            if code == "111" or code == "113" then
                lat = tonumber(tokens[2])
                lon = tonumber(tokens[3])
            else
                lat = tonumber(tokens[4]) or tonumber(tokens[2])
                lon = tonumber(tokens[5]) or tonumber(tokens[3])
            end
            add_poly_point(current_poly, lat, lon)
        elseif current_poly and code and code ~= "" then
            finalize_poly()
        end
        if code == "100" then
            last_ramp = nil
            local tokens = tokenize_line(line)
            local width = tonumber(tokens[2])
            local rwy1 = tokens[9]
            local lat1 = tonumber(tokens[10])
            local lon1 = tonumber(tokens[11])
            local rwy2 = tokens[18]
            local lat2 = tonumber(tokens[19])
            local lon2 = tonumber(tokens[20])
            if lat1 and lon1 and lat2 and lon2 then
                runways[#runways + 1] = {
                    width = width or 0,
                    rwy1 = rwy1 or "",
                    rwy2 = rwy2 or "",
                    lat1 = lat1,
                    lon1 = lon1,
                    lat2 = lat2,
                    lon2 = lon2
                }
            end
        elseif code == "1201" then
            last_ramp = nil
            local tokens = tokenize_line(line)
            local lat = tonumber(tokens[2])
            local lon = tonumber(tokens[3])
            local id = tonumber(tokens[5]) or tonumber(tokens[#tokens])
            if lat and lon and id then
                nodes[id] = { id = id, lat = lat, lon = lon }
                has_routes = true
                if debug_icao and debug_1201 < 3 then
                    debug_1201 = debug_1201 + 1
                    helpers.logInfoTS("TaxiParse: " .. tostring(target_icao) .. " saw 1201 node id=" .. tostring(id))
                end
            end
        elseif code == "1202" then
            last_ramp = nil
            local tokens = tokenize_line(line)
            local from_id = tonumber(tokens[2])
            local to_id = tonumber(tokens[3])
            local dir = tokens[4] or ""
            if from_id and to_id then
                edges[#edges + 1] = {
                    from = from_id,
                    to = to_id,
                    dir = dir,
                    label = build_taxi_label(tokens)
                }
                has_routes = true
            end
        elseif code == "1206" then
            has_routes = true
        elseif code == "1300" then
            local tokens = tokenize_line(line)
            local lat = tonumber(tokens[2])
            local lon = tonumber(tokens[3])
            if lat and lon then
                local heading = tonumber(tokens[4]) or 0
                local ramp_type = tokens[5] or ""
                local ramp_operation = ""
                local name_start = 6
                local op_token = tokens[6]
                if op_token then
                    local op = string.lower(op_token)
                    if op == "airline" or op == "cargo" or op == "general_aviation" or op == "military" or op == "none" then
                        ramp_operation = op
                        name_start = 7
                    end
                end
                local name = ""
                if #tokens >= name_start then
                    name = table.concat(tokens, " ", name_start)
                end
                local ramp = {
                    lat = lat,
                    lon = lon,
                    heading = heading,
                    ramp_type = ramp_type,
                    ramp_operation = ramp_operation,
                    name = name
                }
                ramps[#ramps + 1] = ramp
                last_ramp = ramp
            end
        elseif code == "1301" then
            if last_ramp then
                local tokens = tokenize_line(line)
                local size = tokens[2]
                local op = tokens[3]
                if size and size ~= "" then
                    last_ramp.ramp_size = size
                end
                if op then
                    local op_clean = string.lower(op)
                    if op_clean == "airline" or op_clean == "cargo"
                        or op_clean == "general_aviation" or op_clean == "military" or op_clean == "none" then
                        last_ramp.ramp_operation = op_clean
                    end
                end
            end
        end
    end
    file:close()
    finalize_poly()

    local atc_routes = has_routes
    local has_fallback = false
    local route_source = "none"
    if atc_routes and next(nodes) ~= nil then
        route_source = "atc"
    else
        local f_nodes, f_edges = build_fallback_graph(fallback_polys)
        if f_nodes and next(f_nodes) ~= nil then
            nodes = f_nodes
            edges = f_edges
            has_fallback = true
            route_source = "fallback"
        end
    end

    local function is_valid_latlon(lat, lon)
        return lat ~= nil and lon ~= nil and lat >= -90 and lat <= 90 and lon >= -180 and lon <= 180
    end

    local function compute_ref_latlon(nodes_tbl, ramps_tbl, runways_tbl, polys_tbl)
        local sum_lat = 0
        local sum_lon = 0
        local count = 0
        if runways_tbl and #runways_tbl > 0 then
            for _, rwy in ipairs(runways_tbl) do
                if is_valid_latlon(rwy.lat1, rwy.lon1) and is_valid_latlon(rwy.lat2, rwy.lon2) then
                    sum_lat = sum_lat + (rwy.lat1 + rwy.lat2) * 0.5
                    sum_lon = sum_lon + (rwy.lon1 + rwy.lon2) * 0.5
                    count = count + 1
                end
            end
        end
        if count == 0 and ramps_tbl and #ramps_tbl > 0 then
            for _, ramp in ipairs(ramps_tbl) do
                if is_valid_latlon(ramp.lat, ramp.lon) then
                    sum_lat = sum_lat + ramp.lat
                    sum_lon = sum_lon + ramp.lon
                    count = count + 1
                end
            end
        end
        if count == 0 and nodes_tbl and next(nodes_tbl) ~= nil then
            for _, node in pairs(nodes_tbl) do
                if is_valid_latlon(node.lat, node.lon) then
                    sum_lat = sum_lat + node.lat
                    sum_lon = sum_lon + node.lon
                    count = count + 1
                end
            end
        end
        if count == 0 and polys_tbl and #polys_tbl > 0 then
            for _, poly in ipairs(polys_tbl) do
                for _, pt in ipairs(poly) do
                    if is_valid_latlon(pt.lat, pt.lon) then
                        sum_lat = sum_lat + pt.lat
                        sum_lon = sum_lon + pt.lon
                        count = count + 1
                    end
                end
            end
        end
        if count > 0 then
            return sum_lat / count, sum_lon / count
        end
        return nil, nil
    end

    local function compute_ref_latlon_all(nodes_tbl, ramps_tbl, runways_tbl, polys_tbl)
        local sum_lat = 0
        local sum_lon = 0
        local count = 0
        if nodes_tbl and next(nodes_tbl) ~= nil then
            for _, node in pairs(nodes_tbl) do
                if is_valid_latlon(node.lat, node.lon) then
                    sum_lat = sum_lat + node.lat
                    sum_lon = sum_lon + node.lon
                    count = count + 1
                end
            end
        end
        if ramps_tbl and #ramps_tbl > 0 then
            for _, ramp in ipairs(ramps_tbl) do
                if is_valid_latlon(ramp.lat, ramp.lon) then
                    sum_lat = sum_lat + ramp.lat
                    sum_lon = sum_lon + ramp.lon
                    count = count + 1
                end
            end
        end
        if runways_tbl and #runways_tbl > 0 then
            for _, rwy in ipairs(runways_tbl) do
                if is_valid_latlon(rwy.lat1, rwy.lon1) then
                    sum_lat = sum_lat + rwy.lat1
                    sum_lon = sum_lon + rwy.lon1
                    count = count + 1
                end
                if is_valid_latlon(rwy.lat2, rwy.lon2) then
                    sum_lat = sum_lat + rwy.lat2
                    sum_lon = sum_lon + rwy.lon2
                    count = count + 1
                end
            end
        end
        if polys_tbl and #polys_tbl > 0 then
            for _, poly in ipairs(polys_tbl) do
                for _, pt in ipairs(poly) do
                    if is_valid_latlon(pt.lat, pt.lon) then
                        sum_lat = sum_lat + pt.lat
                        sum_lon = sum_lon + pt.lon
                        count = count + 1
                    end
                end
            end
        end
        if count > 0 then
            return sum_lat / count, sum_lon / count
        end
        return nil, nil
    end

    local function reproject_all_geometry(ref_lat_new, ref_lon_new)
        if not is_valid_latlon(ref_lat_new, ref_lon_new) then
            return nil, nil, nil
        end
        local mlat_new, mlon_new = geo_scale(ref_lat_new)
        local ref_new = {
            ref_lat = ref_lat_new,
            ref_lon = ref_lon_new,
            ref_mlat = mlat_new,
            ref_mlon = mlon_new
        }
        local new_bounds = { minX = nil, maxX = nil, minY = nil, maxY = nil }

        for _, poly in ipairs(polygons) do
            poly.points = {}
        end
        polygons = {}
        for _, poly in ipairs(fallback_polys) do
            local pts = {}
            for _, pt in ipairs(poly) do
                if is_valid_latlon(pt.lat, pt.lon) then
                    local x, z = project_to_local(pt.lat, pt.lon, ref_new)
                    pts[#pts + 1] = { east = x, north = -z }
                end
            end
            if #pts >= 2 then
                polygons[#polygons + 1] = { points = pts }
            end
        end

        for _, node in pairs(nodes) do
            local x, z = project_to_local(node.lat, node.lon, ref_new)
            node.x = x
            node.z = z
            node.east = x
            node.north = -z
            update_bounds(new_bounds, node.east, node.north)
        end
        for _, ramp in ipairs(ramps) do
            local x, z = project_to_local(ramp.lat, ramp.lon, ref_new)
            ramp.x = x
            ramp.z = z
            ramp.east = x
            ramp.north = -z
            update_bounds(new_bounds, ramp.east, ramp.north)
        end
        for _, runway in ipairs(runways) do
            local x1, z1 = project_to_local(runway.lat1, runway.lon1, ref_new)
            local x2, z2 = project_to_local(runway.lat2, runway.lon2, ref_new)
            runway.x1 = x1
            runway.z1 = z1
            runway.east1 = x1
            runway.north1 = -z1
            runway.x2 = x2
            runway.z2 = z2
            runway.east2 = x2
            runway.north2 = -z2
            update_bounds(new_bounds, runway.east1, runway.north1)
            update_bounds(new_bounds, runway.east2, runway.north2)
        end
        for _, poly in ipairs(polygons) do
            for _, pt in ipairs(poly.points or {}) do
                update_bounds(new_bounds, pt.east or 0, pt.north or 0)
            end
        end

        return ref_new, new_bounds, polygons
    end

    local function bounds_need_reprojection(bounds_tbl)
        if not bounds_tbl or bounds_tbl.minX == nil or bounds_tbl.maxX == nil or bounds_tbl.minY == nil or bounds_tbl.maxY == nil then
            return true
        end
        local width = math.abs((bounds_tbl.maxX or 0) - (bounds_tbl.minX or 0))
        local height = math.abs((bounds_tbl.maxY or 0) - (bounds_tbl.minY or 0))
        return width > 50000 or height > 50000
    end

    local ref_lat, ref_lon = compute_ref_latlon(nodes, ramps, runways, fallback_polys)
    local ref_mlat, ref_mlon = nil, nil
    if ref_lat and ref_lon then
        ref_mlat, ref_mlon = geo_scale(ref_lat)
    end
    local ref = { ref_lat = ref_lat, ref_lon = ref_lon, ref_mlat = ref_mlat, ref_mlon = ref_mlon }

    local bounds = { minX = nil, maxX = nil, minY = nil, maxY = nil }
    for _, poly in ipairs(fallback_polys) do
        local pts = {}
        for _, pt in ipairs(poly) do
            if pt.lat and pt.lon then
                local x, z = project_to_local(pt.lat, pt.lon, ref)
                pts[#pts + 1] = { east = x, north = -z }
            end
        end
        if #pts >= 2 then
            polygons[#polygons + 1] = { points = pts }
        end
    end
    for _, node in pairs(nodes) do
        local x, z = project_to_local(node.lat, node.lon, ref)
        node.x = x
        node.z = z
        node.east = x
        node.north = -z
        update_bounds(bounds, node.east, node.north)
    end
    for _, ramp in ipairs(ramps) do
        local x, z = project_to_local(ramp.lat, ramp.lon, ref)
        ramp.x = x
        ramp.z = z
        ramp.east = x
        ramp.north = -z
        update_bounds(bounds, ramp.east, ramp.north)
    end
    for _, runway in ipairs(runways) do
        local x1, z1 = project_to_local(runway.lat1, runway.lon1, ref)
        local x2, z2 = project_to_local(runway.lat2, runway.lon2, ref)
        runway.x1 = x1
        runway.z1 = z1
        runway.east1 = x1
        runway.north1 = -z1
        runway.x2 = x2
        runway.z2 = z2
        runway.east2 = x2
        runway.north2 = -z2
        update_bounds(bounds, runway.east1, runway.north1)
        update_bounds(bounds, runway.east2, runway.north2)
    end
    for _, poly in ipairs(polygons) do
        for _, pt in ipairs(poly.points or {}) do
            update_bounds(bounds, pt.east or 0, pt.north or 0)
        end
    end

    if (not is_valid_latlon(ref_lat, ref_lon)) or bounds_need_reprojection(bounds) then
        local ref_lat2, ref_lon2 = compute_ref_latlon_all(nodes, ramps, runways, fallback_polys)
        local ref2, bounds2, polygons2 = reproject_all_geometry(ref_lat2, ref_lon2)
        if ref2 and bounds2 and (not bounds_need_reprojection(bounds2)) then
            ref_lat = ref2.ref_lat
            ref_lon = ref2.ref_lon
            ref_mlat = ref2.ref_mlat
            ref_mlon = ref2.ref_mlon
            ref = ref2
            bounds = bounds2
            polygons = polygons2 or polygons
            P.logInfoTS(
                "TaxiParse: reprojection sanity fallback icao="
                    .. tostring(target_icao or entry.icao or "?")
                    .. " width="
                    .. string.format("%.1f", math.abs((bounds.maxX or 0) - (bounds.minX or 0)))
                    .. " height="
                    .. string.format("%.1f", math.abs((bounds.maxY or 0) - (bounds.minY or 0)))
            )
        elseif bounds_need_reprojection(bounds) then
            P.logInfoTS(
                "TaxiParse: reprojection sanity fallback failed icao="
                    .. tostring(target_icao or entry.icao or "?")
                    .. " ref="
                    .. tostring(ref_lat2)
                    .. "/"
                    .. tostring(ref_lon2)
            )
        end
    end

    local runway_nodes = {}
    for _, edge in ipairs(edges) do
        if is_runway_label(edge.label) then
            runway_nodes[edge.from] = true
            runway_nodes[edge.to] = true
        end
    end

    local edge_nodes = {}
    for _, edge in ipairs(edges) do
        if edge.from and edge.to then
            edge_nodes[edge.from] = true
            edge_nodes[edge.to] = true
        end
    end

    local RAMP_LINK_MAX_METERS = 150
    local ramp_links, ramp_links_far, edges_after_ramps = add_ramp_links(
        nodes,
        ramps,
        runway_nodes,
        RAMP_LINK_MAX_METERS,
        edge_nodes,
        edges
    )
    if edges_after_ramps then
        edges = edges_after_ramps
    end

    local adjacency = {}
    local adjacency_any = {}
    for _, edge in ipairs(edges) do
        local n1 = nodes[edge.from]
        local n2 = nodes[edge.to]
        if n1 and n2 then
            local dx = (n2.x or 0) - (n1.x or 0)
            local dz = (n2.z or 0) - (n1.z or 0)
            local dist = math.sqrt(dx * dx + dz * dz)
            adjacency[edge.from] = adjacency[edge.from] or {}
            adjacency[edge.from][#adjacency[edge.from] + 1] = { to = edge.to, dist = dist, label = edge.label }
            if edge.dir ~= "oneway" then
                adjacency[edge.to] = adjacency[edge.to] or {}
                adjacency[edge.to][#adjacency[edge.to] + 1] = { to = edge.from, dist = dist, label = edge.label }
            end
            adjacency_any[edge.from] = adjacency_any[edge.from] or {}
            adjacency_any[edge.from][#adjacency_any[edge.from] + 1] = { to = edge.to, dist = dist, label = edge.label }
            adjacency_any[edge.to] = adjacency_any[edge.to] or {}
            adjacency_any[edge.to][#adjacency_any[edge.to] + 1] = { to = edge.from, dist = dist, label = edge.label }
        end
    end
    for _, link in ipairs(ramp_links) do
        local n1 = nodes[link.from]
        local n2 = nodes[link.to]
        if n1 and n2 then
            local dx = (n2.x or 0) - (n1.x or 0)
            local dz = (n2.z or 0) - (n1.z or 0)
            local dist = math.sqrt(dx * dx + dz * dz)
            adjacency[link.from] = adjacency[link.from] or {}
            adjacency[link.from][#adjacency[link.from] + 1] = { to = link.to, dist = dist, label = "RAMP" }
            adjacency[link.to] = adjacency[link.to] or {}
            adjacency[link.to][#adjacency[link.to] + 1] = { to = link.from, dist = dist, label = "RAMP" }
            adjacency_any[link.from] = adjacency_any[link.from] or {}
            adjacency_any[link.from][#adjacency_any[link.from] + 1] = { to = link.to, dist = dist, label = "RAMP" }
            adjacency_any[link.to] = adjacency_any[link.to] or {}
            adjacency_any[link.to][#adjacency_any[link.to] + 1] = { to = link.from, dist = dist, label = "RAMP" }
        end
    end

    local function clone_adjacency(src)
        local dst = {}
        for from, list in pairs(src or {}) do
            local copy = {}
            for i = 1, #list do
                copy[i] = list[i]
            end
            dst[from] = copy
        end
        return dst
    end

    local adjacency_relaxed = clone_adjacency(adjacency)
    local adjacency_any_relaxed = clone_adjacency(adjacency_any)
    if ramp_links_far and #ramp_links_far > 0 then
        for _, link in ipairs(ramp_links_far) do
            local n1 = nodes[link.from]
            local n2 = nodes[link.to]
            if n1 and n2 then
                local dx = (n2.x or 0) - (n1.x or 0)
                local dz = (n2.z or 0) - (n1.z or 0)
                local dist = math.sqrt(dx * dx + dz * dz)
                adjacency_relaxed[link.from] = adjacency_relaxed[link.from] or {}
                adjacency_relaxed[link.from][#adjacency_relaxed[link.from] + 1] = { to = link.to, dist = dist, label = "RAMP" }
                adjacency_relaxed[link.to] = adjacency_relaxed[link.to] or {}
                adjacency_relaxed[link.to][#adjacency_relaxed[link.to] + 1] = { to = link.from, dist = dist, label = "RAMP" }
                adjacency_any_relaxed[link.from] = adjacency_any_relaxed[link.from] or {}
                adjacency_any_relaxed[link.from][#adjacency_any_relaxed[link.from] + 1] = { to = link.to, dist = dist, label = "RAMP" }
                adjacency_any_relaxed[link.to] = adjacency_any_relaxed[link.to] or {}
                adjacency_any_relaxed[link.to][#adjacency_any_relaxed[link.to] + 1] = { to = link.from, dist = dist, label = "RAMP" }
            end
        end
    end

    local function has_links(adj, node_id)
        local list = adj and adj[node_id]
        return list and #list > 0
    end

    local function add_relaxed_link(from_id, to_id)
        local n1 = nodes[from_id]
        local n2 = nodes[to_id]
        if not n1 or not n2 then
            return
        end
        local dx = (n2.x or 0) - (n1.x or 0)
        local dz = (n2.z or 0) - (n1.z or 0)
        local dist = math.sqrt(dx * dx + dz * dz)
        adjacency_relaxed[from_id] = adjacency_relaxed[from_id] or {}
        adjacency_relaxed[from_id][#adjacency_relaxed[from_id] + 1] = { to = to_id, dist = dist, label = "RAMP" }
        adjacency_relaxed[to_id] = adjacency_relaxed[to_id] or {}
        adjacency_relaxed[to_id][#adjacency_relaxed[to_id] + 1] = { to = from_id, dist = dist, label = "RAMP" }
        adjacency_any_relaxed[from_id] = adjacency_any_relaxed[from_id] or {}
        adjacency_any_relaxed[from_id][#adjacency_any_relaxed[from_id] + 1] = { to = to_id, dist = dist, label = "RAMP" }
        adjacency_any_relaxed[to_id] = adjacency_any_relaxed[to_id] or {}
        adjacency_any_relaxed[to_id][#adjacency_any_relaxed[to_id] + 1] = { to = from_id, dist = dist, label = "RAMP" }
    end

    local ramp_nodes = {}
    for id, node in pairs(nodes) do
        if node and node.is_ramp then
            ramp_nodes[#ramp_nodes + 1] = id
        end
    end
    if #ramp_nodes > 0 then
        local connected_nodes = {}
        for id, _ in pairs(adjacency_relaxed) do
            if has_links(adjacency_relaxed, id) then
                connected_nodes[#connected_nodes + 1] = id
            end
        end
        for _, rid in ipairs(ramp_nodes) do
            if not has_links(adjacency_relaxed, rid) then
                local rnode = nodes[rid]
                local best_id = nil
                local best_d2 = nil
                if rnode and rnode.x and rnode.z then
                    for _, cid in ipairs(connected_nodes) do
                        if cid ~= rid then
                            local cnode = nodes[cid]
                            if cnode and cnode.x and cnode.z then
                                local dx = cnode.x - rnode.x
                                local dz = cnode.z - rnode.z
                                local d2 = dx * dx + dz * dz
                                if not best_d2 or d2 < best_d2 then
                                    best_d2 = d2
                                    best_id = cid
                                end
                            end
                        end
                    end
                end
                if best_id then
                    add_relaxed_link(rid, best_id)
                end
            end
        end
    end

    return {
        nodes = nodes,
        edges = edges,
        ramps = ramps,
        runways = runways,
        polygons = polygons,
        bounds = bounds,
        ref_lat = ref_lat,
        ref_lon = ref_lon,
        ref_mlat = ref_mlat,
        ref_mlon = ref_mlon,
        adjacency = adjacency,
        adjacency_any = adjacency_any,
        adjacency_relaxed = adjacency_relaxed,
        adjacency_any_relaxed = adjacency_any_relaxed,
        runway_nodes = runway_nodes,
        has_routes = atc_routes,
        has_fallback = has_fallback,
        route_source = route_source,
        can_route = (atc_routes or has_fallback),
        route_cache = {}
    }
end

local function taxi_label_trim(label)
    return trim_ascii(tostring(label or ""))
end

local function distance_sq(x1, y1, x2, y2)
    local dx = (x2 or 0) - (x1 or 0)
    local dy = (y2 or 0) - (y1 or 0)
    return dx * dx + dy * dy
end

local function taxi_label_missing(label)
    local s = taxi_label_trim(label)
    if s == "" then
        return true
    end
    local u = string.upper(s)
    return u == "NONE"
end

local function taxi_label_usable(label)
    if taxi_label_missing(label) then
        return false
    end
    local s = taxi_label_trim(label)
    if s == "" then
        return false
    end
    local u = string.upper(s)
    if u == "RAMP" then
        return false
    end
    return not is_runway_label(u)
end

local function segment_heading_deg(x1, y1, x2, y2)
    local dx = (x2 or 0) - (x1 or 0)
    local dy = (y2 or 0) - (y1 or 0)
    if dx == 0 and dy == 0 then
        return nil
    end
    local h = math.deg(math.atan2(dx, dy))
    if h < 0 then
        h = h + 360
    end
    return h
end

local function heading_diff_deg(h1, h2)
    if not h1 or not h2 then
        return 180
    end
    local diff = math.abs(((h1 - h2 + 180) % 360) - 180)
    if diff > 90 then
        diff = 180 - diff
    end
    return diff
end

local function build_global_edge_index(data, cell_size)
    local grid = {}
    local list = {}
    if not data or not data.edges or not data.nodes then
        return { grid = grid, cell = cell_size, list = list }
    end
    for _, edge in ipairs(data.edges) do
        if edge and edge.from and edge.to and taxi_label_usable(edge.label) then
            local n1 = data.nodes[edge.from]
            local n2 = data.nodes[edge.to]
            if n1 and n2 and n1.east and n1.north and n2.east and n2.north then
                local x1 = n1.east
                local y1 = n1.north
                local x2 = n2.east
                local y2 = n2.north
                local dx = x2 - x1
                local dy = y2 - y1
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0 then
                    local mx = (x1 + x2) * 0.5
                    local my = (y1 + y2) * 0.5
                    local h = segment_heading_deg(x1, y1, x2, y2)
                    local entry = {
                        x1 = x1,
                        y1 = y1,
                        x2 = x2,
                        y2 = y2,
                        len = len,
                        heading = h,
                        label = edge.label
                    }
                    list[#list + 1] = entry
                    local cx = math.floor(mx / cell_size)
                    local cy = math.floor(my / cell_size)
                    local key = tostring(cx) .. ":" .. tostring(cy)
                    grid[key] = grid[key] or {}
                    grid[key][#grid[key] + 1] = entry
                end
            end
        end
    end
    return { grid = grid, cell = cell_size, list = list }
end

local function normalize_runway_name(name)
    local n = taxi_label_trim(name)
    n = string.upper(n)
    n = n:gsub("^RWY", "")
    n = trim_ascii(n)
    return n
end

local function build_runway_end_map(runways)
    local map = {}
    for _, rwy in ipairs(runways or {}) do
        if rwy and rwy.lat1 and rwy.lon1 and rwy.lat2 and rwy.lon2 then
            local n1 = normalize_runway_name(rwy.rwy1 or "")
            local n2 = normalize_runway_name(rwy.rwy2 or "")
            if n1 ~= "" and not map[n1] then
                map[n1] = { lat = rwy.lat1, lon = rwy.lon1 }
            end
            if n2 ~= "" and not map[n2] then
                map[n2] = { lat = rwy.lat2, lon = rwy.lon2 }
            end
        end
    end
    return map
end

local function runways_compatible(addonData, globalData, max_dist_m)
    if not addonData or not globalData or not addonData.runways or not globalData.runways then
        return false
    end
    local addon_map = build_runway_end_map(addonData.runways)
    local global_map = build_runway_end_map(globalData.runways)
    local max_d = max_dist_m or 150
    for name, aend in pairs(addon_map) do
        local gend = global_map[name]
        if gend and aend.lat and aend.lon and gend.lat and gend.lon then
            local d = P.getdistance(aend.lat, aend.lon, gend.lat, gend.lon)
            if d and d * 1852 <= max_d then
                return true
            end
        end
    end
    return false
end

local function update_adj_label(adj, from_id, to_id, new_label, old_label)
    local list = adj and adj[from_id]
    if not list then
        return
    end
    for _, edge in ipairs(list) do
        if edge.to == to_id then
            if not old_label or edge.label == old_label or taxi_label_missing(edge.label) then
                edge.label = new_label
            end
        end
    end
end

local function patch_addon_labels(addonData, globalIndex, opts)
    local patched = 0
    local edges = addonData.edges or {}
    local nodes = addonData.nodes or {}
    for idx, edge in ipairs(edges) do
        if edge and edge.from and edge.to and taxi_label_missing(edge.label) then
            local n1 = nodes[edge.from]
            local n2 = nodes[edge.to]
            if n1 and n2 and n1.east and n1.north and n2.east and n2.north then
                local ax1 = n1.east
                local ay1 = n1.north
                local ax2 = n2.east
                local ay2 = n2.north
                local dx = ax2 - ax1
                local dy = ay2 - ay1
                local len_a = math.sqrt(dx * dx + dy * dy)
                if len_a > 0 then
                    local a_heading = segment_heading_deg(ax1, ay1, ax2, ay2)
                    local mx = (ax1 + ax2) * 0.5
                    local my = (ay1 + ay2) * 0.5
                    local cell = globalIndex.cell
                    local cx = math.floor(mx / cell)
                    local cy = math.floor(my / cell)
                    local best_label = nil
                    local best_dist = nil
                    for ox = -1, 1 do
                        for oy = -1, 1 do
                            local key = tostring(cx + ox) .. ":" .. tostring(cy + oy)
                            local bucket = globalIndex.grid[key]
                            if bucket then
                                for _, cand in ipairs(bucket) do
                                    local len_ratio = cand.len > 0 and (len_a / cand.len) or 0
                                    if len_ratio >= opts.len_ratio_min and len_ratio <= opts.len_ratio_max then
                                        local hdiff = heading_diff_deg(a_heading, cand.heading)
                                        if hdiff <= opts.heading_max_deg then
                                            local d11 = distance_sq(ax1, ay1, cand.x1, cand.y1)
                                            local d22 = distance_sq(ax2, ay2, cand.x2, cand.y2)
                                            local d12 = distance_sq(ax1, ay1, cand.x2, cand.y2)
                                            local d21 = distance_sq(ax2, ay2, cand.x1, cand.y1)
                                            local max_d2 = nil
                                            if (d11 + d22) <= (d12 + d21) then
                                                max_d2 = math.max(d11, d22)
                                            else
                                                max_d2 = math.max(d12, d21)
                                            end
                                            local max_d = math.sqrt(max_d2 or 0)
                                            if max_d <= opts.endpoint_max_m then
                                                if not best_dist or max_d < best_dist then
                                                    best_dist = max_d
                                                    best_label = cand.label
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if best_label then
                        addonData._labelBackup = addonData._labelBackup or {}
                        if addonData._labelBackup[idx] == nil then
                            addonData._labelBackup[idx] = edge.label
                        end
                        local old_label = edge.label
                        edge.label = best_label
                        update_adj_label(addonData.adjacency, edge.from, edge.to, best_label, old_label)
                        update_adj_label(addonData.adjacency_relaxed, edge.from, edge.to, best_label, old_label)
                        update_adj_label(addonData.adjacency_any, edge.from, edge.to, best_label, old_label)
                        update_adj_label(addonData.adjacency_any, edge.to, edge.from, best_label, old_label)
                        update_adj_label(addonData.adjacency_any_relaxed, edge.from, edge.to, best_label, old_label)
                        update_adj_label(addonData.adjacency_any_relaxed, edge.to, edge.from, best_label, old_label)
                        patched = patched + 1
                    end
                end
            end
        end
    end
    return patched
end

function P.patchTaxiLabelsFromGlobal(addonData, globalData, opts)
    if not addonData or not globalData then
        return 0, "invalid-data"
    end
    if addonData._labelsPatched then
        return 0, "already-patched"
    end
    if addonData.entry and addonData.entry.source == "global-index" then
        return 0, "global-source"
    end
    if not addonData.has_routes or not globalData.has_routes then
        return 0, "no-routes"
    end
    local options = opts or {}
    local endpoint_max_m = tonumber(options.endpoint_max_m) or 30
    local heading_max_deg = tonumber(options.heading_max_deg) or 25
    local len_ratio_min = tonumber(options.len_ratio_min) or 0.6
    local len_ratio_max = tonumber(options.len_ratio_max) or 1.6
    local cell_size = tonumber(options.cell_size_m) or 50
    local runway_max_m = tonumber(options.runway_max_m) or 150

    if not runways_compatible(addonData, globalData, runway_max_m) then
        return 0, "runway-mismatch"
    end

    local index = build_global_edge_index(globalData, cell_size)
    local patched = patch_addon_labels(addonData, index, {
        endpoint_max_m = endpoint_max_m,
        heading_max_deg = heading_max_deg,
        len_ratio_min = len_ratio_min,
        len_ratio_max = len_ratio_max
    })
    addonData._labelsPatched = true
    addonData._labelsPatchedCount = patched
    addonData._labelPatchSource = globalData.entry and globalData.entry.source or "global"
    if options.log then
        P.logInfoTS(
            "TaxiPatch: labels patched=" .. tostring(patched) ..
            " src=" .. tostring(addonData._labelPatchSource) ..
            " icao=" .. tostring(addonData.entry and addonData.entry.icao or "?")
        )
    end
    return patched, nil
end

function P.patchTaxiLabelsFromGlobalForIcao(addonData, icao, opts)
    if not addonData or not icao then
        return 0, "invalid-data"
    end
    if addonData._labelsPatched then
        return 0, "already-patched"
    end
    if not addonData.entry or addonData.entry.source ~= "addon" then
        return 0, "not-addon"
    end
    local gentry, gerr = P.findAptDatForIcaoWithPolicy(icao, "global")
    if not gentry then
        if gerr == "global-index-pending" then
            addonData._labelsPatchPending = true
            P.requestGlobalAptIndex("label-patch")
            return 0, "global-index-pending"
        end
        return 0, gerr or "global-not-found"
    end
    local gdata, gperr = parse_taxi_data(gentry)
    if not gdata then
        return 0, gperr or "global-parse-failed"
    end
    gdata.entry = gentry
    local patched, perr = P.patchTaxiLabelsFromGlobal(addonData, gdata, opts)
    addonData._labelsPatchPending = nil
    return patched, perr
end

local function find_nearest_node(data, lat, lon, avoid_runway)
    if not data or not data.nodes or not lat or not lon then
        return nil
    end
    local x, z = project_to_local(lat, lon, data)
    local best_id = nil
    local best_dist = nil
    local found_non_runway = false
    for id, node in pairs(data.nodes) do
        if avoid_runway and data.runway_nodes and data.runway_nodes[id] then
            goto continue
        end
        if node.x and node.z then
            local dx = node.x - x
            local dz = node.z - z
            local d2 = dx * dx + dz * dz
            if not best_dist or d2 < best_dist then
                best_dist = d2
                best_id = id
            end
            found_non_runway = true
        end
        ::continue::
    end
    if avoid_runway and not best_id and not found_non_runway then
        return find_nearest_node(data, lat, lon, false)
    end
    return best_id
end

local function ramp_name_has_excluded(text)
    if not text or text == "" then
        return false
    end
    local cleaned = string.lower(text)
    cleaned = string.gsub(cleaned, "[^%w]+", " ")
    if string.find(cleaned, "class b", 1, true) then
        return true
    end
    if string.find(cleaned, "cargo", 1, true) or string.find(cleaned, "freight", 1, true) then
        return true
    end
    for token in string.gmatch(cleaned, "%S+") do
        if token == "cargo" or token == "freight" or token == "mil" or token == "military"
            or token == "ga" or token == "hangar" or token == "heli" or token == "helipad" then
            return true
        end
    end
    return false
end

function P.isRampSuitableFor738(ramp)
    if not ramp then
        return false
    end
    local rtype = string.lower(tostring(ramp.ramp_type or ""))
    if rtype == "tie-down" or rtype == "tiedown" or rtype == "hangar" then
        return false
    end
    if string.find(rtype, "cargo", 1, true) or string.find(rtype, "freight", 1, true) then
        return false
    end
    if rtype ~= "gate" and rtype ~= "misc" then
        return false
    end
    local op = string.lower(tostring(ramp.ramp_operation or ""))
    if op == "cargo" or op == "general_aviation" or op == "military" then
        return false
    end
    if ramp_name_has_excluded(ramp.name) then
        return false
    end
    return true
end

local function find_nearest_ramp(data, lat, lon, filter_fn)
    if not data or not data.ramps or not lat or not lon then
        return nil
    end
    local x, z = project_to_local(lat, lon, data)
    local best = nil
    local best_dist = nil
    for _, ramp in ipairs(data.ramps) do
        if ramp.x and ramp.z then
            if filter_fn and not filter_fn(ramp) then
                goto continue
            end
            local dx = ramp.x - x
            local dz = ramp.z - z
            local d2 = dx * dx + dz * dz
            if not best_dist or d2 < best_dist then
                best_dist = d2
                best = ramp
            end
        end
        ::continue::
    end
    return best, best_dist
end

local function astar_route(data, start_id, goal_id, opts)
    if not data or not data.adjacency then
        return nil
    end
    local adjacency = data.adjacency
    local runway_nodes = data.runway_nodes
    if opts and opts.allow_far_ramp and data.adjacency_relaxed then
        adjacency = data.adjacency_relaxed
    end
    if opts and opts.ignore_oneway then
        if opts.allow_far_ramp and data.adjacency_any_relaxed then
            adjacency = data.adjacency_any_relaxed
        elseif data.adjacency_any then
            adjacency = data.adjacency_any
        end
    end
    if start_id == goal_id then
        return { start_id }
    end
    local nodes = data.nodes
    local open = { start_id }
    local open_set = { [start_id] = true }
    local came = {}
    local g = { [start_id] = 0 }
    local f = {}

    local function heuristic(a, b)
        local na = nodes[a]
        local nb = nodes[b]
        if not na or not nb then return 0 end
        local dx = (na.x or 0) - (nb.x or 0)
        local dz = (na.z or 0) - (nb.z or 0)
        return math.sqrt(dx * dx + dz * dz)
    end

    f[start_id] = heuristic(start_id, goal_id)

    while #open > 0 do
        local current_idx = 1
        local current = open[1]
        local best_f = f[current] or math.huge
        for i = 2, #open do
            local node_id = open[i]
            local score = f[node_id] or math.huge
            if score < best_f then
                best_f = score
                current = node_id
                current_idx = i
            end
        end

        if current == goal_id then
            local path = { current }
            while came[current] do
                current = came[current]
                table.insert(path, 1, current)
            end
            return path
        end

        table.remove(open, current_idx)
        open_set[current] = nil

        local neighbors = adjacency[current] or {}
        for _, edge in ipairs(neighbors) do
            if opts and opts.disallow_runway_edges and is_runway_label(edge.label) then
                goto continue
            end
            if opts and opts.avoid_runway_nodes and runway_nodes and runway_nodes[edge.to] and edge.to ~= goal_id then
                goto continue
            end
            local edge_cost = edge.dist or 0
            if opts and opts.runway_penalty and is_runway_label(edge.label) then
                edge_cost = edge_cost * opts.runway_penalty
            end
            local tentative = (g[current] or math.huge) + edge_cost
            if tentative < (g[edge.to] or math.huge) then
                came[edge.to] = current
                g[edge.to] = tentative
                f[edge.to] = tentative + heuristic(edge.to, goal_id)
                if not open_set[edge.to] then
                    open[#open + 1] = edge.to
                    open_set[edge.to] = true
                end
            end
            ::continue::
        end
    end
    return nil
end

function P.getTaxiData(icao)
    local code = trim_ascii(tostring(icao or ""))
    code = string.upper(code)
    if code == "" then
        return nil, "invalid-icao"
    end
    local entry, err = P.findAptDatForIcao(code)
    if not entry then
        return nil, err or "apt-not-found"
    end
    local data, perr = parse_taxi_data(entry)
    if not data then
        return nil, perr or "parse-failed"
    end
    data.entry = entry
    return data
end

function P.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
    local data = opts and opts.data or nil
    local err = nil
    if not data then
        data, err = P.getTaxiData(icao)
    end
    if not data then
        return nil, err
    end
    if not data.can_route then
        return nil, "no-routes"
    end
    local avoid_start = opts and opts.avoid_runway_start
    local avoid_end = opts and opts.avoid_runway_end
    local start_id = opts and opts.start_node_id or nil
    local end_id = opts and opts.end_node_id or nil
    if start_id and (not data.nodes or not data.nodes[start_id]) then
        start_id = nil
    end
    if end_id and (not data.nodes or not data.nodes[end_id]) then
        end_id = nil
    end
    if not start_id then
        start_id = find_nearest_node(data, start_lat, start_lon, avoid_start)
    end
    if not end_id then
        end_id = find_nearest_node(data, end_lat, end_lon, avoid_end)
    end
    if not start_id or not end_id then
        return nil, "no-nodes"
    end
    local key = tostring(start_id) .. "->" .. tostring(end_id)
    if opts and opts.runway_penalty then
        key = key .. "|rp=" .. tostring(opts.runway_penalty)
    end
    if opts and opts.ignore_oneway then
        key = key .. "|io=1"
    end
    if opts and opts.allow_far_ramp then
        key = key .. "|far=1"
    end
    if opts and opts.start_node_id then
        key = key .. "|sn=" .. tostring(opts.start_node_id)
    end
    if opts and opts.end_node_id then
        key = key .. "|en=" .. tostring(opts.end_node_id)
    end
    if data.route_cache[key] then
        return data.route_cache[key]
    end
    local path = astar_route(data, start_id, end_id, opts)
    if not path then
        return nil, "no-path"
    end
    local bounds = { minX = nil, maxX = nil, minY = nil, maxY = nil }
    for _, node_id in ipairs(path) do
        local node = data.nodes[node_id]
        if node then
            update_bounds(bounds, node.east or 0, node.north or 0)
        end
    end
    local route = {
        data = data,
        start_id = start_id,
        end_id = end_id,
        path = path,
        bounds = bounds
    }
    data.route_cache[key] = route
    return route
end

function P.getNearestRamp(icao, lat, lon, opts)
    local data = opts and opts.data or nil
    local err = nil
    if not data then
        data, err = P.getTaxiData(icao)
    end
    if not data then
        return nil, err
    end
    local filter_fn = opts and opts.filter
    return find_nearest_ramp(data, lat, lon, filter_fn)
end

local function split_kv_tab(line)
    if not line then
        return nil, nil
    end
    local tab = string.find(line, "\t", 1, true)
    if not tab then
        return line, ""
    end
    local key = string.sub(line, 1, tab - 1)
    local value = string.sub(line, tab + 1)
    return key, value
end

local function split_tabs(line, max_parts)
    local parts = {}
    if not line then
        return parts
    end
    local start = 1
    local line_len = string.len(line)
    while start <= line_len do
        local tab = string.find(line, "\t", start, true)
        if not tab then
            parts[#parts + 1] = string.sub(line, start)
            break
        end
        parts[#parts + 1] = string.sub(line, start, tab - 1)
        start = tab + 1
        if max_parts and #parts >= (max_parts - 1) then
            parts[#parts + 1] = string.sub(line, start)
            break
        end
    end
    if #parts == 0 then
        parts[1] = ""
    end
    return parts
end

local function global_meta_key(meta)
    if not meta then
        return ""
    end
    return tostring(meta.path or "") .. "|" .. tostring(meta.size or 0) .. "|" .. tostring(meta.fingerprint or "-")
end

local function compute_global_meta()
    local path = global_apt_path()
    if not P.file_exists_v2(path) then
        return nil
    end
    local size = get_file_size(path) or 0
    local mtime = get_file_mtime(path)
    local fingerprint = compute_file_fingerprint(path, size, GLOBAL_APT_FINGERPRINT_BYTES)
    return {
        path = path,
        size = size,
        mtime = mtime,
        fingerprint = fingerprint,
        checked_at = os.time()
    }
end

local function get_global_meta(force)
    local now = os.time()
    local meta = P.global_apt_meta
    if not force and P.global_apt_index_job and meta then
        return meta
    end
    if not force and meta and meta.checked_at and (now - meta.checked_at) < GLOBAL_APT_META_REFRESH_SEC then
        return meta
    end
    meta = compute_global_meta()
    P.global_apt_meta = meta
    return meta
end

local function meta_matches(idx_meta, cur_meta)
    if not idx_meta or not cur_meta then
        return false
    end
    if idx_meta.path ~= cur_meta.path then
        return false
    end
    if (idx_meta.size or 0) ~= (cur_meta.size or 0) then
        return false
    end
    if idx_meta.fingerprint and cur_meta.fingerprint then
        return idx_meta.fingerprint == cur_meta.fingerprint
    end
    if idx_meta.mtime and cur_meta.mtime then
        return idx_meta.mtime == cur_meta.mtime
    end
    return true
end

local function load_global_index(meta)
    local file = io.open(GLOBAL_APT_INDEX_FILE, "r")
    if not file then
        return nil
    end
    local line1 = file:read("*l")
    local tag, version_str = split_kv_tab(line1)
    if tag ~= "YALAPTIDX" or tonumber(version_str) ~= GLOBAL_APT_INDEX_VERSION then
        if tag == "YALAPTIDX" then
            helpers.logInfoTS("Global Airports Taxidata Table cache invalid (version " .. tostring(version_str) .. " != " .. tostring(GLOBAL_APT_INDEX_VERSION) .. ")")
        end
        file:close()
        return nil
    end

    local idx_meta = { path = nil, size = nil, mtime = nil, fingerprint = nil }
    while true do
        local line = file:read("*l")
        if not line then
            file:close()
            return nil
        end
        if line == "DATA" then
            break
        end
        local key, value = split_kv_tab(line)
        if key == "PATH" then
            idx_meta.path = value
        elseif key == "SIZE" then
            idx_meta.size = tonumber(value) or 0
        elseif key == "MTIME" then
            if value ~= "-" and value ~= "" then
                idx_meta.mtime = tonumber(value)
            end
        elseif key == "FINGERPRINT" then
            if value ~= "" and value ~= "-" then
                idx_meta.fingerprint = value
            end
        elseif key == "EPOCH" then
            idx_meta.epoch = tonumber(value)
        end
    end

    local cache_epoch = tonumber(def.CACHE_EPOCH) or 1
    if (idx_meta.epoch or -1) ~= cache_epoch then
        helpers.logInfoTS(
            "Global Airports Taxidata Table cache invalid (cache epoch "
                .. tostring(idx_meta.epoch)
                .. " != "
                .. tostring(cache_epoch)
                .. ")"
        )
        file:close()
        pcall(function() os.remove(GLOBAL_APT_INDEX_FILE) end)
        return nil
    end

    if not meta_matches(idx_meta, meta) then
        file:close()
        return nil
    end

    local entries = {}
    while true do
        local line = file:read("*l")
        if not line then
            break
        end
        local parts = split_tabs(line, 4)
        local icao = parts[1]
        if icao and icao ~= "" then
            entries[icao] = {
                icao = icao,
                path = meta.path,
                offset = tonumber(parts[2]) or 0,
                length = tonumber(parts[3]) or 0,
                size = meta.size,
                has_routes = tonumber(parts[4]) == 1,
                source = "global-index"
            }
        end
    end
    file:close()
    return entries
end

local function write_global_index(meta, entries)
    if not meta or not entries then
        return false
    end
    P.check_create_path(def.PLUGINOUTPUTPATH)
    local file = io.open(GLOBAL_APT_INDEX_FILE, "w")
    if not file then
        sasl.logWarning("Taxi: failed to write global apt index: " .. tostring(GLOBAL_APT_INDEX_FILE))
        return false
    end
    file:write("YALAPTIDX\t", tostring(GLOBAL_APT_INDEX_VERSION), "\n")
    file:write("EPOCH\t", tostring(tonumber(def.CACHE_EPOCH) or 1), "\n")
    file:write("PATH\t", tostring(meta.path or ""), "\n")
    file:write("MTIME\t", meta.mtime and tostring(meta.mtime) or "-", "\n")
    file:write("SIZE\t", tostring(meta.size or 0), "\n")
    file:write("FINGERPRINT\t", meta.fingerprint and tostring(meta.fingerprint) or "-", "\n")
    file:write("DATA\n")

    for icao, entry in pairs(entries) do
        if icao and entry and entry.offset then
            local has_routes = entry.has_routes and 1 or 0
            file:write(tostring(icao), "\t", tostring(entry.offset or 0), "\t", tostring(entry.length or 0), "\t", tostring(has_routes), "\n")
        end
    end
    file:close()
    return true
end

local function close_global_job(job)
    if job and job.file then
        pcall(function()
            job.file:close()
        end)
    end
end

local function finalize_job_airport(job, block_end)
    if not job or not job.current_icao or not job.current_offset then
        return
    end
    local length = (block_end or 0) - job.current_offset
    if length < 0 then
        length = 0
    end
    job.entries[job.current_icao] = {
        path = job.meta.path,
        offset = job.current_offset,
        length = length,
        size = job.meta.size,
        has_routes = job.current_has_routes,
        source = "global-index"
    }
end

local function start_global_index_job(meta, reason)
    close_global_job(P.global_apt_index_job)
    local file = io.open(meta.path, "rb")
    if not file then
        sasl.logWarning("Taxi: cannot open global apt.dat for indexing: " .. tostring(meta.path))
        return false
    end
    P.global_apt_index = {}
    P.global_apt_index_meta = meta
    P.global_apt_index_key = global_meta_key(meta)
    P.global_apt_index_ready = false
    P.global_apt_index_job = {
        file = file,
        meta = meta,
        entries = P.global_apt_index,
        current_icao = nil,
        current_offset = nil,
        current_has_routes = false,
        lines = 0,
        last_log_time = os.time(),
        reason = reason or "startup"
    }
    helpers.logInfoTS(
        "Global Airports Taxidata Table build started (" .. tostring(P.global_apt_index_job.reason) .. ")"
    )
    return true
end

local function step_global_index_job(job, max_lines, max_sec)
    if not job or not job.file then
        return true
    end
    local lines_budget = max_lines or GLOBAL_APT_INDEX_STEP_LINES
    local sec_budget = max_sec or GLOBAL_APT_INDEX_STEP_SEC
    local size = job.meta and job.meta.size or 0
    local lines = 0
    if sec_budget and sec_budget > 0 then
        if not P.global_index_timer then
            P.global_index_timer = sasl.createTimer()
        end
        sasl.startTimer(P.global_index_timer)
    end

    while lines < lines_budget do
        local pos = job.file:seek()
        if not pos then
            return true
        end
        local line = job.file:read("*l")
        if not line then
            local end_size = size
            if end_size <= 0 then
                end_size = get_file_size(job.meta.path) or 0
            end
            finalize_job_airport(job, end_size)
            return true
        end
        lines = lines + 1
        job.lines = job.lines + 1

        local header_icao = parse_airport_header_icao(line)
        if header_icao then
            header_icao = string.upper(header_icao)
            if job.current_icao and job.current_offset then
                finalize_job_airport(job, pos)
            end
            job.current_icao = header_icao
            job.current_offset = pos
            job.current_has_routes = false
        elseif job.current_icao then
            local code = next_token(line, 1)
            if code == "1201" or code == "1202" or code == "1206" then
                job.current_has_routes = true
            else
                -- Fallback: guard against odd whitespace or token parsing issues.
                local i = 1
                local len = #line
                while i <= len do
                    local b = string.byte(line, i)
                    if b and not is_space_byte(b) then
                        break
                    end
                    i = i + 1
                end
                if i <= len then
                    local prefix = string.sub(line, i, i + 3)
                    if prefix == "1201" or prefix == "1202" or prefix == "1206" then
                        job.current_has_routes = true
                    end
                end
            end
        end

        if (lines % 50 == 0) then
            local now_pos = job.file:seek() or pos
            if job.last_pos and now_pos <= job.last_pos then
                job.stall_count = (job.stall_count or 0) + 1
            else
                job.stall_count = 0
            end
            job.last_pos = now_pos

            -- Guard against pathological no-progress loops near EOF.
            if size > 0 then
                local near_end = (now_pos / size) >= 0.9995
                if near_end and (job.stall_count or 0) >= 5 then
                    finalize_job_airport(job, size)
                    return true
                end
            end

            if sec_budget and sec_budget > 0 then
                local elapsed = sasl.getElapsedSeconds(P.global_index_timer) or 0
                if elapsed >= sec_budget then
                    break
                end
            end
        end
    end

    local now = os.time()
    if now and job.last_log_time and (now - job.last_log_time) >= 5 then
        job.last_log_time = now
        local bytes = job.file:seek() or 0
        if size > 0 then
            local pct = math.floor((bytes / size) * 100)
            helpers.logInfoTS("Global Airports Taxidata Table indexing " .. tostring(pct) .. "%% (" .. tostring(job.lines) .. " lines)")
        else
            helpers.logInfoTS("Global Airports Taxidata Table indexing lines " .. tostring(job.lines))
        end
    end

    return false
end

local function finalize_global_index_job(job)
    if not job then
        return
    end
    close_global_job(job)
    P.global_apt_index_job = nil
    P.global_apt_index_ready = true
    write_global_index(P.global_apt_index_meta, P.global_apt_index)
    helpers.logInfoTS(
        "Global Airports Taxidata Table ready, "
            .. tostring(P.getTableSize(P.global_apt_index or {}))
            .. " entries (" .. tostring(job.lines or 0) .. " lines)"
    )
    if (sasl.getLogLevel() == LOG_DEBUG) then
        P.writetaxidatatable()
    end
end

local function ensure_global_index(reason)
    local meta = get_global_meta(false)
    if not meta then
        return nil, "global-apt-missing"
    end
    local key = global_meta_key(meta)
    if key ~= (P.global_apt_index_key or "") then
        close_global_job(P.global_apt_index_job)
        P.global_apt_index_job = nil
        P.global_apt_index = {}
        P.global_apt_index_ready = false
        P.global_apt_index_key = key
        P.global_apt_index_meta = meta
    end
    if P.global_apt_index_ready and P.global_apt_index and next(P.global_apt_index) ~= nil then
        return meta, nil
    end
    if (not P.global_apt_index_job) and (not P.global_apt_index_ready) then
        local loaded = load_global_index(meta)
        if loaded and next(loaded) ~= nil then
            P.global_apt_index = loaded
            P.global_apt_index_meta = meta
            P.global_apt_index_ready = true
            helpers.logInfoTS(
                "Global Airports Taxidata Table loaded from cache, "
                    .. tostring(P.getTableSize(P.global_apt_index or {}))
                    .. " entries"
            )
            return meta, nil
        end
        local started = start_global_index_job(meta, reason)
        if not started then
            return nil, "global-index-start-failed"
        end
    end
    return meta, "global-index-pending"
end

function P.requestGlobalAptIndex(reason)
    local _, err = ensure_global_index(reason or "request")
    return err == nil
end

function P.updateGlobalAptIndex(step_lines, fast_mode)
    local job = P.global_apt_index_job
    if not job then
        return
    end
    local done = false
    if fast_mode and not job.fast_attempted then
        job.fast_attempted = true
        helpers.logInfoTS("Global Airports Taxidata Table fast build started")
        done = step_global_index_job(job, GLOBAL_APT_INDEX_FAST_LINES, nil)
    else
        done = step_global_index_job(job, step_lines, GLOBAL_APT_INDEX_STEP_SEC)
    end
    if done then
        finalize_global_index_job(job)
    end
end

function P.isGlobalAptIndexReady()
    return P.global_apt_index_ready == true and P.global_apt_index and next(P.global_apt_index) ~= nil
end

function P.isGlobalAptIndexRunning()
    return P.global_apt_index_job ~= nil
end

local function get_global_index_entry(icao, reason)
    local meta, err = ensure_global_index(reason or "demand")
    if not meta then
        return nil, err
    end
    local entry = P.global_apt_index and P.global_apt_index[icao] or nil
    if entry then
        return entry
    end
    if err == "global-index-pending" then
        return nil, err
    end
    return nil, "not-found"
end

local function scan_addon_for_icao(code)
    local paths, cache_key = get_addon_apt_paths()
    local cached = P.addon_apt_cache and P.addon_apt_cache[code] or nil
    if cached and cached.key == cache_key then
        return cached.entry
    end
    local best = nil
    for _, apt_path in ipairs(paths) do
        local entry = scan_apt_for_icao(apt_path, code)
        if entry then
            if not entry.source then
                entry.source = "addon"
            end
            if entry.has_routes then
                best = entry
                break
            end
            if not best then
                best = entry
            end
        end
    end
    P.addon_apt_cache[code] = { key = cache_key, entry = best }
    return best
end

function P.findAptDatForIcao(icao)
    local code = trim_ascii(tostring(icao or ""))
    code = string.upper(code)
    if code == "" then
        return nil, "invalid-icao"
    end

    local addon_entry = scan_addon_for_icao(code)
    if addon_entry and addon_entry.has_routes then
        return addon_entry
    end

    local global_entry, gerr = get_global_index_entry(code, "find-icao")
    if global_entry and global_entry.has_routes then
        return global_entry
    end

    if gerr == "global-index-pending" and (not addon_entry or not addon_entry.has_routes) then
        return nil, gerr
    end

    -- Prefer global apt.dat for taxi routing when addon has no ATC routes,
    -- because global data often carries the ATC taxi graph.
    if global_entry then
        return global_entry
    end
    if addon_entry then
        return addon_entry
    end
    return nil, gerr or "not-found"
end

function P.findAptDatForIcaoWithPolicy(icao, policy)
    local code = trim_ascii(tostring(icao or ""))
    code = string.upper(code)
    if code == "" then
        return nil, "invalid-icao"
    end

    local pref = tostring(policy or "auto")
    local addon_entry = scan_addon_for_icao(code)
    local global_entry, gerr = get_global_index_entry(code, "find-icao")

    if pref == "addon" then
        if addon_entry then
            return addon_entry
        end
        if global_entry then
            return global_entry
        end
        return nil, gerr or "not-found"
    end

    if pref == "global" then
        if global_entry then
            return global_entry
        end
        if addon_entry then
            return addon_entry
        end
        return nil, gerr or "not-found"
    end

    return P.findAptDatForIcao(code)
end

function P.getTaxiDataWithPolicy(icao, policy)
    local entry, err = P.findAptDatForIcaoWithPolicy(icao, policy)
    if not entry then
        return nil, err or "apt-not-found"
    end
    local data, perr = parse_taxi_data(entry)
    if not data then
        return nil, perr or "parse-failed"
    end
    data.entry = entry
    if entry.source == "addon" then
        local patched, perr_patch = P.patchTaxiLabelsFromGlobalForIcao(data, entry.icao or icao, { log = true })
        if perr_patch == "global-index-pending" then
            data._labelsPatchPending = true
        elseif perr_patch and perr_patch ~= "already-patched" and perr_patch ~= "no-routes" and perr_patch ~= "runway-mismatch" then
            P.logInfoTS("TaxiPatch: label patch skipped (" .. tostring(perr_patch) .. ")")
        elseif patched and patched > 0 then
            -- labels patched; keep data in memory only
        end
    end
    return data
end

function P.clearTaxiIndexCache()
    close_global_job(P.global_apt_index_job)
    P.global_apt_index_job = nil
    P.global_apt_index = {}
    P.global_apt_index_ready = false
    P.addon_apt_cache = {}
    if P.global_index_timer then
        sasl.stopTimer(P.global_index_timer)
        P.global_index_timer = nil
    end
end

--------------------------------------------------------------------------------------------------------------
function P.writeZiboCalcTable(ziboTable)
    if type(ziboTable) ~= "table" then
        sasl.logDebug("writeZiboCalcTable: no table to write")
        return false
    end
    local function tableNameList(tbl)
        local list = {}
        for k, _ in pairs(tbl or {}) do
            table.insert(list, tostring(k))
        end
        table.sort(list)
        return list
    end
    local basePath = def.PLUGINOUTPUTPATH
    local file, err = io.open(basePath .. "yal_zibo_calc.txt", "w")
    if not file then
        sasl.logDebug("writeZiboCalcTable: open failed: " .. tostring(err))
        return false
    end
    local function writeSection(title, tbl)
        file:write("[" .. title .. "]\n")
        if not tbl then
            file:write("(nil)\n")
            return
        end
        local keys = tableNameList(tbl)
        for _, k in ipairs(keys) do
            file:write(k .. "\n")
        end
    end
    writeSection("flaps", ziboTable.flaps)
    writeSection("vref", ziboTable.vref)
    writeSection("vref_idx", ziboTable.vref and ziboTable.vref.idx)
    writeSection("cg", ziboTable.cg)
    writeSection("wet", ziboTable.wet)
    writeSection("takeoff", ziboTable.takeoff)
    file:close()
    sasl.logDebug("Zibo calc table written to " .. basePath .. "yal_zibo_calc.txt")
    return true
end

--------------------------------------------------------------------------------------------------------------

function P.getTableSize(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

--------------------------------------------------------------------------------------------------------------
function P.getnavdataindices(navdatatable, icao, rwy, navtypes)
    if not (P.isvalidicao(icao) and P.isvalidrwy(rwy)) then
        return {}
    end

    local navtypeList = {}
    if type(navtypes) == "table" then
        for _, t in ipairs(navtypes) do
            if t ~= nil then
                table.insert(navtypeList, t)
            end
        end
    elseif navtypes ~= nil then
        navtypeList = { navtypes }
    end

    if #navtypeList == 0 then
        return {}
    end

    local exactMatches = {}
    local offsetMatches = {}
    local seen = {}
    local rwy_offsets = {1, -1, 2, -2, 3, -3}

    for _, navtype in ipairs(navtypeList) do
        for idx, entry in ipairs(navdatatable) do
            if entry[def.DESTICAO] == icao
            and entry[def.DESTNAVTYPE] == navtype then
                if entry[def.DESTRWY] == rwy then
                    if not seen[idx] then
                        table.insert(exactMatches, idx)
                        seen[idx] = true
                    end
                else
                    -- Offsets are handled only if no exact matches are found.
                    local current_rwy = entry[def.DESTRWY]
                    if current_rwy and current_rwy ~= "" then
                        for _, offset in ipairs(rwy_offsets) do
                            local current_expected = P.adjustrwy(rwy, offset)
                            if current_expected and current_rwy == current_expected then
                                if not seen[idx] then
                                    table.insert(offsetMatches, idx)
                                    seen[idx] = true
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    if #exactMatches > 0 then
        return exactMatches
    end
    
    return offsetMatches
end

function P.getnavdataindex(navdatatable, icao, rwy, navtype)
    local indices = P.getnavdataindices(navdatatable, icao, rwy, navtype)
    if indices and #indices > 0 then
        return indices[1]
    end
    return nil
end

--------------------------------------------------------------------------------------------------------------
function P.getrwyheadingfromnavdata(navdatatable, icao, rwy)

    if not (P.isvalidicao(icao) and P.isvalidrwy(rwy)) then
        return nil
    end

    local navTypePriority = {
        def.NAVTYPEILS,
        def.NAVTYPEGLS,
        def.NAVTYPELPV,
        def.NAVTYPELDA,
        def.NAVTYPELOC,
        def.NAVTYPEIGS
    }

    local function runwayUsesTrueLocal(runway)
        if type(runway) ~= "string" then
            return false
        end
        local clean = string.upper(runway):gsub("^RW", "")
        return clean:sub(-1) == "T"
    end

    local function getCourseFromNavEntry(entry)
        if not entry then return nil end
        if entry.isTrueCourse and entry.truecourse then
            if runwayUsesTrueLocal(rwy) then
                return entry.truecourse
            end
            local magVar = entry[def.DESTMAGVAR]
            if magVar == nil then
                local lat = entry[def.DESTLATPOS]
                local lon = entry[def.DESTLONPOS]
                if lat and lon and lat ~= 0 and lon ~= 0 then
                    magVar = sasl.getMagneticVariation(lat, lon)
                end
            end
            magVar = magVar or 0
            return P.calccourse(entry.truecourse + magVar)
        end
        return entry[def.DESTCOURSE]
    end

    local function tryCIFPCourse(navType)
        if not navType then return nil end
        local candidateTypes = { navType }
        if navType == def.NAVTYPELPV or navType == def.NAVTYPEGLS then
            table.insert(candidateTypes, def.NAVTYPERNAV)
        end
        for _, candidate in ipairs(candidateTypes) do
            local cifpCourse = P.getCIFPApproachCourse(icao, candidate, rwy)
            if cifpCourse then
                return P.calccourse(cifpCourse)
            end
        end
        return nil
    end

    for _, navType in ipairs(navTypePriority) do
        local cifpHeading = tryCIFPCourse(navType)
        if cifpHeading then
            return cifpHeading
        end

        local navIndex = P.getnavdataindex(navdatatable, icao, rwy, navType)
        if navIndex then
            local entry = navdatatable[navIndex]
            local course = getCourseFromNavEntry(entry)
            if course then
                return course
            end
        end
    end

    return nil

end 

--------------------------------------------------------------------------------------------------------------
function P.loadZiboReferenceTables()
    local path = def.ZIBO_B738_CALC_PATH
    local file, err = io.open(path, "r")
    if not file then
        sasl.logDebug("Zibo reference load failed (open): " .. tostring(err))
        return nil
    end
    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        sasl.logDebug("Zibo reference load failed: empty file")
        return nil
    end

    -- Generic table extractor
    local function extractTableAt(pos)
        if not pos then return nil end
        local bracePos = content:find("{", pos)
        if not bracePos then return nil end
        local depth = 0
        for i = bracePos, #content do
            local ch = content:sub(i, i)
            if ch == "{" then
                depth = depth + 1
            elseif ch == "}" then
                depth = depth - 1
                if depth == 0 then
                    local literal = content:sub(bracePos, i)
                    local chunk, loadErr = loadstring("return " .. literal)
                    if not chunk then
                        return nil
                    end
                    setfenv(chunk, {})
                    local ok, res = pcall(chunk)
                    if ok and type(res) == "table" then
                        return res
                    end
                    return nil
                end
            end
        end
        return nil
    end

    local result = {
        flaps = {},
        cg = {},
        vref = { idx = {} },
        wet = {},
        takeoff = {}
    }

    -- Collect all table names from assignments and raw_table('name')
    local names = {}
    for name in content:gmatch("([%w_]+)%s*=") do
        names[name] = true
    end
    for name in content:gmatch("raw_table%('%s*([%w_]+)%s*'%)") do
        names[name] = true
    end

    local function categorize(name, tbl)
        if not tbl then return end
        if name:match("^flaps_") then
            result.flaps[name] = tbl
        elseif name:match("^cg_") then
            result.cg[name] = tbl
        elseif name:match("^vref_calc_idx") then
            result.vref.idx[name] = tbl
        elseif name:match("^vref_calc") then
            result.vref[name] = tbl
        elseif name == "v1_wet" or name == "vr_wet" or name == "v2_wet" or name == "v1_adj_wet" then
            result.wet[name] = tbl
        elseif name == "takeoff_thrust" or name == "v1_adj_wet" then
            result.takeoff[name] = tbl
        end
    end

    for name in pairs(names) do
        if name:match("^(flaps_.*)") or name:match("^cg_") or name:match("^vref_calc") or name:match("^v1_") or name:match("^v2_") or name:match("^vr_") or name:match("^takeoff_thrust") then
            local startPos = select(1, content:find(name .. "%s*="))
            if startPos then
                local tbl = extractTableAt(startPos)
                categorize(name, tbl)
            end
        end
    end

    local hasData = (next(result.flaps) ~= nil) or (next(result.vref) ~= nil) or (next(result.cg) ~= nil) or (next(result.wet) ~= nil) or (next(result.takeoff) ~= nil)
    if not hasData then
        sasl.logDebug("Zibo reference load: no tables parsed from " .. path)
        return nil
    end

    local flapsCount, vrefCount, vrefIdxCount, cgCount, wetCount, takeoffCount = 0, 0, 0, 0, 0, 0
    for _ in pairs(result.flaps) do flapsCount = flapsCount + 1 end
    for _ in pairs(result.vref) do vrefCount = vrefCount + 1 end
    for _ in pairs(result.vref.idx) do vrefIdxCount = vrefIdxCount + 1 end
    for _ in pairs(result.cg) do cgCount = cgCount + 1 end
    for _ in pairs(result.wet) do wetCount = wetCount + 1 end
    for _ in pairs(result.takeoff) do takeoffCount = takeoffCount + 1 end
    P.logInfoTS(string.format("Loaded Zibo reference tables from %s (flaps=%d, vref=%d idx=%d, cg=%d, wet=%d, takeoff=%d)", path, flapsCount, vrefCount, vrefIdxCount, cgCount, wetCount, takeoffCount))
    return result
end

--------------------------------------------------------------------------------------------------------------
function P.getFuelCapacityFactor(fuelTemp)
    local temp = tonumber(fuelTemp) or 15
    local delta = temp - 15
    -- temp_coef = 1 +/- delta*0.00092
    local coef
    if delta < 0 then
        coef = 1 + (math.abs(delta) * 0.00092)
    else
        coef = 1 - (delta * 0.00092)
    end
    return coef
end

--------------------------------------------------------------------------------------------------------------
function P.getZiboVref(ziboTable, variant, flaps, weightKgs)
    if type(ziboTable) ~= "table" or type(ziboTable.vref) ~= "table" then return nil end
    local function pickVrefTable()
        if variant == def.B737VARIANT_600 then
            return ziboTable.vref["vref_calc_600"]
        elseif variant == def.B737VARIANT_700 or variant == def.B737VARIANT_MAX7 then
            return ziboTable.vref["vref_calc_700"]
        elseif variant == def.B737VARIANT_900 or variant == def.B737VARIANT_MAX8 or variant == def.B737VARIANT_MAX9 then
            return ziboTable.vref["vref_calc_900"] or ziboTable.vref["vref_calc"]
        else -- default/-1/800/8200 etc.
            return ziboTable.vref["vref_calc"]
        end
    end

    local vrefTbl = pickVrefTable()
    if type(vrefTbl) ~= "table" then return nil end
    local flapKey = tonumber(flaps)
    if not flapKey then return nil end
    local flapSub = vrefTbl[flapKey]
    if type(flapSub) ~= "table" then return nil end

    local weightTon = (tonumber(weightKgs) or 0) / 1000
    if weightTon <= 0 then return nil end

    -- find nearest lower/upper weights
    local lowerW, upperW = nil, nil
    for w, _ in pairs(flapSub) do
        local wt = tonumber(w)
        if wt then
            if wt <= weightTon and (not lowerW or wt > lowerW) then lowerW = wt end
            if wt >= weightTon and (not upperW or wt < upperW) then upperW = wt end
        end
    end
    if not lowerW and not upperW then return nil end
    if lowerW and not upperW then upperW = lowerW end
    if upperW and not lowerW then lowerW = upperW end

    local vLower = flapSub[lowerW]
    local vUpper = flapSub[upperW]
    if not vLower or not vUpper then return nil end
    if upperW == lowerW then return tonumber(vLower) end

    local ratio = (weightTon - lowerW) / (upperW - lowerW)
    local vref = vLower + (vUpper - vLower) * ratio
    return tonumber(vref)
end

--------------------------------------------------------------------------------------------------------------
-- Zibo thrust rating selection based on variant and N1 mode
-- Returns a rating tag string matching table suffixes, e.g. "24k", "22k_700", "18k_600"
function P.selectZiboThrustRating(variant, n1mode)
    local v = tonumber(variant) or def.B737VARIANT_DEFAULT
    if v < 0 then v = def.B737VARIANT_800 end -- default -> 800
    local mode = tonumber(n1mode) or 0 -- 0=TO, 1=TO1, 2=TO2

    -- Ratings per family
    if v == def.B737VARIANT_600 then
        if mode >= 2 then return "18k_600" else return "20k_600" end
    elseif v == def.B737VARIANT_700 or v == def.B737VARIANT_MAX7 then
        if mode >= 2 then return "20k_700" else return "22k_700" end
    elseif v == def.B737VARIANT_900 or v == def.B737VARIANT_MAX8 or v == def.B737VARIANT_MAX9 then
        -- 900/MAX haben 22k/24k Tabellen
        if mode >= 2 then return "22k_900"
        elseif mode >= 1 then return "22k_900"
        else return "24k_900" end
    else -- 800 / default
        if mode >= 2 then return "20k"
        elseif mode >= 1 then return "22k"
        else return "24k" end
    end
end

--------------------------------------------------------------------------------------------------------------
-- Fuel prediction helpers (per-engine flows in lbs/hr unless noted)

local function rescale(x1, y1, x2, y2, x)
    if x2 == x1 then return y1 end
    local t = (x - x1) / (x2 - x1)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return y1 + t * (y2 - y1)
end

local function mach_to_tas(mach, alt_ft, isa_dev_c)
    isa_dev_c = isa_dev_c or 0
    local oat = (15 + isa_dev_c) - (alt_ft * 0.002)
    if oat <= -273.15 then return 100 end
    return mach * 39 * math.sqrt(oat + 273.15)
end

local function tas_to_mach(tas_kt, alt_ft, isa_dev_c)
    isa_dev_c = isa_dev_c or 0
    local oat = (15 + isa_dev_c) - (alt_ft * 0.002)
    if oat <= -273.15 then return 0.82 end
    return tas_kt / (39 * math.sqrt(oat + 273.15))
end

local function ias_to_tas(ias_kt, alt_ft)
    local dens_corr = 1 + 0.02 * ((alt_ft or 0) / 10000)
    return (ias_kt or 0) * dens_corr
end

local function clb_ff(alt_ft)
    local a = alt_ft or 0
    local ff
    if a <= 5000 then ff = 6800
    elseif a < 10000 then ff = rescale(5000, 6800, 10000, 5960, a)
    elseif a < 15000 then ff = rescale(10000, 5960, 15000, 5380, a)
    elseif a < 20000 then ff = rescale(15000, 5380, 20000, 4840, a)
    elseif a < 25000 then ff = rescale(20000, 4840, 25000, 4320, a)
    elseif a < 30000 then ff = rescale(25000, 4320, 30000, 3840, a)
    elseif a < 35000 then ff = rescale(30000, 3840, 35000, 3260, a)
    else                 ff = rescale(35000, 3260, 40000, 2640, a)
    end
    return ff * 1.15
end

local function crz_ff(alt_ft, spd)
    local a = math.min(alt_ft or 0, 41000)
    local ff, ff2
    if spd < 100 then
        a = math.max(a, 25000)
        if a <= 25000 then
            if spd < 0.60 then ff = 2220
            elseif spd < 0.70 then ff = rescale(0.60, 2220, 0.70, 2800, spd)
            elseif spd < 0.80 then ff = rescale(0.70, 2800, 0.80, 3600, spd)
            else               ff = rescale(0.80, 3600, 0.82, 3820, spd)
            end
        elseif a < 30000 then
            if spd < 0.60 then ff = 2080
            elseif spd < 0.70 then ff = rescale(0.60, 2080, 0.70, 3600, spd)
            elseif spd < 0.80 then ff = rescale(0.70, 3600, 0.80, 3040, spd)
            else               ff = rescale(0.80, 3040, 0.82, 3220, spd)
            end
            if spd < 0.60 then ff2 = 2220
            elseif spd < 0.70 then ff2 = rescale(0.60, 2220, 0.70, 2800, spd)
            elseif spd < 0.80 then ff2 = rescale(0.70, 2800, 0.80, 3600, spd)
            else               ff2 = rescale(0.80, 3600, 0.82, 3820, spd)
            end
            ff = rescale(25000, ff2, 30000, ff, a)
        elseif a < 35000 then
            if spd < 0.60 then ff = 1960
            elseif spd < 0.70 then ff = rescale(0.60, 1960, 0.70, 2120, spd)
            elseif spd < 0.80 then ff = rescale(0.70, 2120, 0.80, 2620, spd)
            else               ff = rescale(0.80, 2620, 0.82, 2840, spd)
            end
            if spd < 0.60 then ff2 = 2080
            elseif spd < 0.70 then ff2 = rescale(0.60, 2080, 0.70, 3600, spd)
            elseif spd < 0.80 then ff2 = rescale(0.70, 3600, 0.80, 3040, spd)
            else               ff2 = rescale(0.80, 3040, 0.82, 3220, spd)
            end
            ff = rescale(30000, ff2, 35000, ff, a)
        else
            if spd < 0.60 then ff = 1960
            elseif spd < 0.70 then ff = rescale(0.60, 1960, 0.70, 2010, spd)
            elseif spd < 0.80 then ff = rescale(0.70, 2010, 0.80, 2440, spd)
            else               ff = rescale(0.80, 2440, 0.82, 2620, spd)
            end
            if spd < 0.60 then ff2 = 1960
            elseif spd < 0.70 then ff2 = rescale(0.60, 1960, 0.70, 2120, spd)
            elseif spd < 0.80 then ff2 = rescale(0.70, 2120, 0.80, 2620, spd)
            else               ff2 = rescale(0.80, 2620, 0.82, 2840, spd)
            end
            ff = rescale(35000, ff2, 41000, ff, a)
        end
    else
        a = math.max(math.min(a, 30000), 10000)
        if a <= 10000 then
            if     spd < 180 then ff = 1500
            elseif spd < 250 then ff = rescale(180, 1500, 250, 2100, spd)
            elseif spd < 270 then ff = rescale(250, 2100, 270, 2400, spd)
            elseif spd < 290 then ff = rescale(270, 2400, 290, 2720, spd)
            elseif spd < 320 then ff = rescale(290, 2720, 320, 3280, spd)
            else                 ff = rescale(320, 3280, 340, 3660, spd)
            end
        elseif a < 15000 then
            if     spd < 250 then ff = 2060
            elseif spd < 270 then ff = rescale(250, 2060, 270, 2360, spd)
            elseif spd < 290 then ff = rescale(270, 2360, 290, 2680, spd)
            elseif spd < 320 then ff = rescale(290, 2680, 320, 3240, spd)
            else                 ff = rescale(320, 3240, 340, 3600, spd)
            end
            if     spd < 180 then ff2 = 1500
            elseif spd < 250 then ff2 = rescale(180, 1500, 250, 2100, spd)
            elseif spd < 270 then ff2 = rescale(250, 2100, 270, 2400, spd)
            elseif spd < 290 then ff2 = rescale(270, 2400, 290, 2720, spd)
            elseif spd < 320 then ff2 = rescale(290, 2720, 320, 3280, spd)
            else                 ff2 = rescale(320, 3280, 340, 3660, spd)
            end
            ff = rescale(10000, ff2, 15000, ff, a)
        elseif a < 20000 then
            if     spd < 250 then ff = 2040
            elseif spd < 270 then ff = rescale(250, 2040, 270, 2320, spd)
            elseif spd < 290 then ff = rescale(270, 2320, 290, 2640, spd)
            elseif spd < 320 then ff = rescale(290, 2640, 320, 3200, spd)
            else                 ff = rescale(320, 3200, 340, 3600, spd)
            end
            if     spd < 250 then ff2 = 2060
            elseif spd < 270 then ff2 = rescale(250, 2060, 270, 2360, spd)
            elseif spd < 290 then ff2 = rescale(270, 2360, 290, 2680, spd)
            elseif spd < 320 then ff2 = rescale(290, 2680, 320, 3240, spd)
            else                 ff2 = rescale(320, 3240, 340, 3600, spd)
            end
            ff = rescale(15000, ff2, 20000, ff, a)
        elseif a < 25000 then
            if     spd < 250 then ff = 2000
            elseif spd < 270 then ff = rescale(250, 2000, 270, 2300, spd)
            elseif spd < 290 then ff = rescale(270, 2300, 290, 2640, spd)
            elseif spd < 320 then ff = rescale(290, 2640, 320, 3200, spd)
            else                 ff = rescale(320, 3200, 340, 3620, spd)
            end
            if     spd < 250 then ff2 = 2040
            elseif spd < 270 then ff2 = rescale(250, 2040, 270, 2320, spd)
            elseif spd < 290 then ff2 = rescale(270, 2320, 290, 2640, spd)
            elseif spd < 320 then ff2 = rescale(290, 2640, 320, 3200, spd)
            else                 ff2 = rescale(320, 3200, 340, 3600, spd)
            end
            ff = rescale(20000, ff2, 25000, ff, a)
        else
            if     spd < 250 then ff = 1960
            elseif spd < 270 then ff = rescale(250, 1960, 270, 2280, spd)
            elseif spd < 290 then ff = rescale(270, 2280, 290, 2640, spd)
            elseif spd < 320 then ff = rescale(290, 2640, 320, 3280, spd)
            else                 ff = rescale(320, 3280, 340, 3280, spd)
            end
            if     spd < 250 then ff2 = 2000
            elseif spd < 270 then ff2 = rescale(250, 2000, 270, 2300, spd)
            elseif spd < 290 then ff2 = rescale(270, 2300, 290, 2640, spd)
            elseif spd < 320 then ff2 = rescale(290, 2640, 320, 3200, spd)
            else                 ff2 = rescale(320, 3200, 340, 3620, spd)
            end
            ff = rescale(25000, ff2, 41000, ff, a)
        end
    end
    return ff * 1.02
end

local function calc_fuel_flow(phase, alt_from_ft, alt_to_ft, leg_speed, wc_speed, isa_dev_c)
    local tas_kt
    if (leg_speed or 0) == 0 then
        tas_kt = 160 + (wc_speed or 0)
    elseif leg_speed < 100 then
        tas_kt = mach_to_tas(leg_speed, alt_to_ft, isa_dev_c) + (wc_speed or 0)
    else
        tas_kt = ias_to_tas(leg_speed, alt_to_ft) + (wc_speed or 0)
    end
    local per_eng
    if phase == 0 or phase == 1 then
        per_eng = clb_ff(alt_to_ft)
    else
        local spd_mach = (leg_speed < 100) and leg_speed or tas_to_mach(tas_kt, alt_to_ft, isa_dev_c)
        per_eng = crz_ff(alt_to_ft, spd_mach)
    end
    return per_eng * 2
end

function P.estimateFuelForLeg(dist_nm, tas_kt, alt_ft, leg_speed, wc_speed, isa_dev_c, phase)
    if not dist_nm or not tas_kt or tas_kt <= 0 then return 0 end
    local ff_total = calc_fuel_flow(phase or 1, alt_ft or 0, alt_ft or 0, leg_speed or tas_kt, wc_speed or 0, isa_dev_c)
    local time_hr = dist_nm / tas_kt
    return ff_total * time_hr
end

function P.estimateFuelFlow(phase, alt_from_ft, alt_to_ft, leg_speed, wc_speed, isa_dev_c)
    return calc_fuel_flow(phase or 1, alt_from_ft or 0, alt_to_ft or alt_from_ft or 0, leg_speed or 0, wc_speed or 0, isa_dev_c or 0)
end

function P.atmoMachToTas(mach, alt_ft, isa_dev_c)
    return mach_to_tas(mach, alt_ft or 0, isa_dev_c or 0)
end

function P.atmoTasToMach(tas_kt, alt_ft, isa_dev_c)
    return tas_to_mach(tas_kt or 0, alt_ft or 0, isa_dev_c or 0)
end

function P.atmoIasToTas(ias_kt, alt_ft)
    return ias_to_tas(ias_kt or 0, alt_ft or 0)
end

-- CG / QuickView helpers ------------------------------------------------------
local function get_zibo_base_path()
    return sasl.getXPlanePath() .. def.OSSEPARATOR .. "Aircraft" .. def.OSSEPARATOR .. "B737-800X" .. def.OSSEPARATOR
end

local QV_UPDATE_STAGE_SELECT = 0
local QV_UPDATE_STAGE_SAVE = 1
local DEFAULT_VIEW_STAGE_NORMALIZE = 0
local DEFAULT_VIEW_STAGE_SELECT = 1
local DEFAULT_VIEW_STAGE_APPLY = 2

P.quickViewCgUpdateJob = P.quickViewCgUpdateJob or nil
P.defaultViewUpdateJob = P.defaultViewUpdateJob or nil

local function get_current_zibo_variant()
    local rel = get(acf_relative_path)
    if type(rel) ~= "string" or rel == "" then
        return nil, "aircraft path not available"
    end
    local rel_lower = string.lower(rel)
    if string.find(rel_lower, "b738_4k.acf", 1, true) then
        return {
            name = "4k",
            acf = "b738_4k.acf",
            prefs = "b738_4k_prefs.txt",
            xcamera = "X-Camera_b738_4k.csv",
            keyY = "CG_BASE_4K_Y",
            keyZ = "CG_BASE_4K_Z"
        }
    end
    if string.find(rel_lower, "b738.acf", 1, true) then
        return {
            name = "2k",
            acf = "b738.acf",
            prefs = "b738_prefs.txt",
            xcamera = "X-Camera_b738.csv",
            keyY = "CG_BASE_2K_Y",
            keyZ = "CG_BASE_2K_Z"
        }
    end
    return nil, "unsupported aircraft: " .. tostring(rel)
end

local function read_acf_cg(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, err
    end
    local cg = { lat = 0.0 }
    for line in file:lines() do
        local t1, t2, t3 = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if t1 == "P" and t2 == "acf/_cgY" then
            cg.vert = tonumber(t3)
        elseif t1 == "P" and t2 == "acf/_cgZ" then
            cg.long = tonumber(t3)
        end
    end
    file:close()
    if cg.vert == nil or cg.long == nil then
        return nil, "CG values not found"
    end
    return cg
end

local function read_acf_default_view(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, err
    end
    local view = {}
    for line in file:lines() do
        local t1, t2, t3 = line:match("^(%S+)%s+(%S+)%s+(%S+)")
        if t1 == "P" and t2 == "acf/_pe_xyz/0" then
            view.lat = tonumber(t3)
        elseif t1 == "P" and t2 == "acf/_pe_xyz/1" then
            view.vert = tonumber(t3)
        elseif t1 == "P" and t2 == "acf/_pe_xyz/2" then
            view.long = tonumber(t3)
        elseif t1 == "P" and t2 == "acf/_ang_offset/0,1" then
            view.pitch = tonumber(t3)
        end
    end
    file:close()
    if view.lat == nil or view.vert == nil or view.long == nil or view.pitch == nil then
        return nil, "Default view values not found"
    end
    return view
end

local function read_qv0(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, err
    end
    local qv = {}
    for line in file:lines() do
        local key, val = line:match("^(%S+)%s+([-%d%.]+)")
        if key == "_iql_pe_x_0" then
            qv.lat = tonumber(val)
        elseif key == "_iql_pe_y_0" then
            qv.vert = tonumber(val)
        elseif key == "_iql_pe_z_0" then
            qv.long = tonumber(val)
        elseif key == "_iql_look_os_the_0" then
            qv.pitch = tonumber(val)
        end
    end
    file:close()
    if qv.lat == nil or qv.vert == nil or qv.long == nil or qv.pitch == nil then
        return nil, "QV0 values not found"
    end
    return qv
end

local function read_quickview_indices(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, err
    end
    local seen = {}
    local list = {}
    for line in file:lines() do
        local idx = line:match("^_iql_pe_z_(%d+)%s")
        if idx then
            local num = tonumber(idx)
            if num and not seen[num] then
                seen[num] = true
                list[#list + 1] = num
            end
        end
    end
    file:close()
    table.sort(list)
    if #list == 0 then
        return nil, "no quick views found"
    end
    return list
end

local function read_quickview_data(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, err
    end
    local data = {}
    for line in file:lines() do
        local idx, val = line:match("^_iql_pe_x_(%d+)%s+([-%d%.]+)")
        if idx then
            local i = tonumber(idx)
            data[i] = data[i] or {}
            data[i].x = tonumber(val)
        else
            idx, val = line:match("^_iql_pe_y_(%d+)%s+([-%d%.]+)")
            if idx then
                local i = tonumber(idx)
                data[i] = data[i] or {}
                data[i].y = tonumber(val)
            else
                idx, val = line:match("^_iql_pe_z_(%d+)%s+([-%d%.]+)")
                if idx then
                    local i = tonumber(idx)
                    data[i] = data[i] or {}
                    data[i].z = tonumber(val)
                else
                    idx, val = line:match("^_iql_look_os_psi_(%d+)%s+([-%d%.]+)")
                    if idx then
                        local i = tonumber(idx)
                        data[i] = data[i] or {}
                        data[i].psi = tonumber(val)
                    else
                        idx, val = line:match("^_iql_look_os_the_(%d+)%s+([-%d%.]+)")
                        if idx then
                            local i = tonumber(idx)
                            data[i] = data[i] or {}
                            data[i].the = tonumber(val)
                        else
                            idx, val = line:match("^_iql_look_os_phi_(%d+)%s+([-%d%.]+)")
                            if idx then
                                local i = tonumber(idx)
                                data[i] = data[i] or {}
                                data[i].phi = tonumber(val)
                            end
                        end
                    end
                end
            end
        end
    end
    file:close()

    local list = {}
    for i, v in pairs(data) do
        if v and v.x ~= nil and v.y ~= nil and v.z ~= nil then
            list[#list + 1] = i
        end
    end
    table.sort(list)
    if #list == 0 then
        return nil, "no quick views found"
    end
    return list, data
end

local function capture_pilots_head()
    return {
        x = get(pilots_head_x),
        y = get(pilots_head_y),
        z = get(pilots_head_z),
        psi = get(pilots_head_psi),
        the = get(pilots_head_the),
        phi = get(pilots_head_phi)
    }
end

local function restore_pilots_head(state)
    if not state then
        return
    end
    if state.x ~= nil then set(pilots_head_x, state.x) end
    if state.y ~= nil then set(pilots_head_y, state.y) end
    if state.z ~= nil then set(pilots_head_z, state.z) end
    if state.psi ~= nil then set(pilots_head_psi, state.psi) end
    if state.the ~= nil then set(pilots_head_the, state.the) end
    if state.phi ~= nil then set(pilots_head_phi, state.phi) end
end

local function approx_equal(a, b, tol)
    tol = tol or 0.0001
    if a == nil or b == nil then return false end
    return math.abs(a - b) <= tol
end

local function backup_file(path)
    local stamp = os.date("%Y%m%d-%H%M%S")
    local backup_path = path .. ".yal_bak_" .. stamp
    local infile, err = io.open(path, "rb")
    if not infile then
        return false, err
    end
    local outfile, err2 = io.open(backup_path, "wb")
    if not outfile then
        infile:close()
        return false, err2
    end
    while true do
        local chunk = infile:read(8192)
        if not chunk then break end
        outfile:write(chunk)
    end
    infile:close()
    outfile:close()
    return true, backup_path
end

local function backup_yal_prefs(context, job)
    if job and job.settings_backup_done then
        return
    end
    local prefs_path = def.PREFFILE
    local infile = io.open(prefs_path, "rb")
    if not infile then
        P.logInfoTS((context or "YAL prefs") .. ": YAL prefs not found, skipping backup (" .. tostring(prefs_path) .. ")")
        if job then job.settings_backup_done = true end
        return
    end
    infile:close()
    local ok, backup_or_err = backup_file(prefs_path)
    if ok then
        P.logInfoTS((context or "YAL prefs") .. ": YAL prefs backup created at " .. tostring(backup_or_err))
    else
        P.logInfoTS((context or "YAL prefs") .. ": YAL prefs backup failed (" .. tostring(backup_or_err) .. ")")
    end
    if job then job.settings_backup_done = true end
end

local function rewrite_file(path, line_fn)
    local infile, err = io.open(path, "r")
    if not infile then
        return false, err
    end
    local ok, backup_or_err = backup_file(path)
    if not ok then
        infile:close()
        return false, backup_or_err
    end
    local tmp = path .. ".yal_tmp"
    local outfile, err2 = io.open(tmp, "w")
    if not outfile then
        infile:close()
        return false, err2
    end
    for line in infile:lines() do
        outfile:write(line_fn(line) .. "\n")
    end
    infile:close()
    outfile:close()
    local ok, err3 = os.rename(tmp, path)
    if not ok then
        local err_text = tostring(err3 or ""):lower()
        if err_text:find("exist") then
            os.remove(path)
            ok, err3 = os.rename(tmp, path)
        end
        if not ok then
            os.remove(tmp)
            return false, err3
        end
    end
    return true
end

local function shift_quickviews_z(prefs_path, delta_m)
    return rewrite_file(prefs_path, function(line)
        local prefix, idx, val = line:match("^(_iql_pe_z_)(%d+)%s+([-%d%.]+)")
        if prefix then
            local old = tonumber(val)
            if old then
                local new_val = old - delta_m
                return string.format("%s%s %.6f", prefix, idx, new_val)
            end
        end
        return line
    end)
end

local function trim_csv_field(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function split_csv_line(line)
    local fields = {}
    local i = 1
    local len = #line
    local in_quotes = false
    local field = ""
    while i <= len do
        local ch = string.sub(line, i, i)
        if ch == '"' then
            local next_ch = string.sub(line, i + 1, i + 1)
            if in_quotes and next_ch == '"' then
                field = field .. '"'
                i = i + 1
            else
                in_quotes = not in_quotes
            end
        elseif ch == "," and not in_quotes then
            fields[#fields + 1] = field
            field = ""
        else
            field = field .. ch
        end
        i = i + 1
    end
    fields[#fields + 1] = field
    return fields
end

local function csv_escape(value)
    local text = tostring(value or "")
    if text:find("[,\"]") then
        text = '"' .. text:gsub("\"", "\"\"") .. '"'
    end
    return text
end

local function join_csv_line(fields)
    local out = {}
    for i = 1, #fields do
        out[i] = csv_escape(fields[i])
    end
    return table.concat(out, ",")
end

local function update_xcamera_cg_offsets(path, delta_m_y, delta_m_z)
    local infile, err = io.open(path, "r")
    if not infile then
        return false, err
    end
    local header_line = infile:read("*l")
    if not header_line then
        infile:close()
        return false, "empty file"
    end
    local header = split_csv_line(header_line)
    local idx = {}
    for i = 1, #header do
        idx[trim_csv_field(header[i])] = i
    end
    local idx_category = idx["Category Name"]
    if not idx_category then
        infile:close()
        return false, "missing Category Name column"
    end
    local idx_cgy = idx["CGY Offset"]
    local idx_cgz = idx["CGZ Offset"]
    local idx_y = idx["Y"]
    local idx_z = idx["Z"]
    local idx_origin = idx["Camera Origin"]
    if idx_y == nil or idx_z == nil then
        infile:close()
        return false, "missing Y/Z columns"
    end

    local rows = {}
    local updated = 0
    local offsets_reset = 0
    for line in infile:lines() do
        local fields = split_csv_line(line)
        while #fields < #header do
            fields[#fields + 1] = ""
        end
        local category = trim_csv_field(fields[idx_category] or "")
        local origin = trim_csv_field(fields[idx_origin] or "")
        local should_update
        if idx_origin then
            should_update = (origin == "" or origin == "0")
        else
            should_update = (category == "Cockpit")
        end
        if should_update then
            local old_y = tonumber(fields[idx_y])
            local old_z = tonumber(fields[idx_z])
            if old_y ~= nil and old_z ~= nil then
                fields[idx_y] = string.format("%.6f", old_y - delta_m_y)
                fields[idx_z] = string.format("%.6f", old_z - delta_m_z)
                updated = updated + 1
            end
            if idx_cgy ~= nil and idx_cgz ~= nil then
                local off_y = tonumber(fields[idx_cgy])
                local off_z = tonumber(fields[idx_cgz])
                if off_y ~= nil and off_z ~= nil then
                    if approx_equal(off_y, -delta_m_y) and approx_equal(off_z, -delta_m_z) then
                        fields[idx_cgy] = "0.000000"
                        fields[idx_cgz] = "0.000000"
                        offsets_reset = offsets_reset + 1
                    end
                end
            end
        end
        rows[#rows + 1] = fields
    end
    infile:close()

    local outfile, err2 = io.open(path, "w")
    if not outfile then
        return false, err2
    end
    outfile:write(header_line .. "\n")
    for i = 1, #rows do
        outfile:write(join_csv_line(rows[i]) .. "\n")
    end
    outfile:close()
    return true, updated, false, offsets_reset
end

local function apply_default_view_from_qv0_data(acf_path, qv)
    local cg, err2 = read_acf_cg(acf_path)
    if not cg then
        return false, err2
    end
    local current_view, err3 = read_acf_default_view(acf_path)
    if not current_view then
        return false, err3
    end
    local meters_to_feet = 3.28084
    local new_lat = (cg.lat or 0.0) + (qv.lat * meters_to_feet)
    local new_vert = cg.vert + (qv.vert * meters_to_feet)
    local new_long = cg.long + (qv.long * meters_to_feet)
    local new_pitch = qv.pitch

    if approx_equal(current_view.lat, new_lat) and approx_equal(current_view.vert, new_vert)
        and approx_equal(current_view.long, new_long) and approx_equal(current_view.pitch, new_pitch) then
        return true, "no-change"
    end

    return rewrite_file(acf_path, function(line)
        if line:match("^P%s+acf/_pe_xyz/0%s+") then
            return string.format("P acf/_pe_xyz/0 %.6f", new_lat)
        elseif line:match("^P%s+acf/_pe_xyz/1%s+") then
            return string.format("P acf/_pe_xyz/1 %.6f", new_vert)
        elseif line:match("^P%s+acf/_pe_xyz/2%s+") then
            return string.format("P acf/_pe_xyz/2 %.6f", new_long)
        elseif line:match("^P%s+acf/_ang_offset/0,1%s+") then
            return string.format("P acf/_ang_offset/0,1 %.6f", new_pitch)
        end
        return line
    end)
end

local function queue_quickview_cg_job(variant, cg, delta_y, delta_z, indices, qv_data)
    local delta_m_z = delta_z * 0.3048
    local delta_m_y = delta_y * 0.3048
    P.quickViewCgUpdateJob = {
        variant = variant,
        indices = indices,
        index_pos = 1,
        qv_data = qv_data,
        delta_m_z = delta_m_z,
        delta_m_y = delta_m_y,
        delta_z = delta_z,
        delta_y = delta_y,
        total = #indices,
        stage = QV_UPDATE_STAGE_SELECT,
        snapshot = capture_pilots_head(),
        target_cg_vert = cg.vert,
        target_cg_long = cg.long,
        settings_backup_done = false
    }
    P.logInfoTS(string.format("QuickViews CG update queued: %s (%d views, deltaY %.4f ft, deltaZ %.4f ft)", variant.name, #indices, delta_y, delta_z))
end

function P.adjustQuickViewsForCgChange()
    local settings = require("settings")
    if not views_change_allowed() then
        P.logInfoTS("QuickViews CG update blocked (requires preflight, on ground, parking brake set)")
        return
    end
    if P.defaultViewUpdateJob then
        P.logInfoTS("QuickViews CG update blocked (default view update in progress)")
        return
    end
    if P.quickViewCgUpdateJob then
        P.logInfoTS("QuickViews CG update already in progress")
        return
    end
    local variant, v_err = get_current_zibo_variant()
    if not variant then
        P.logInfoTS("QuickViews CG update: " .. tostring(v_err))
        return
    end

    local base = get_zibo_base_path()
    local acf_path = base .. variant.acf
    local prefs_path = base .. variant.prefs
    local cg, err = read_acf_cg(acf_path)
    if not cg then
        P.logInfoTS("QuickViews CG update: failed to read " .. variant.name .. " CG (" .. tostring(err) .. ")")
        return
    end

    local stored_y = tonumber(settings.appSettings[variant.keyY])
    local stored_z = tonumber(settings.appSettings[variant.keyZ])
    if stored_y == nil or stored_z == nil then
        settings.appSettings[variant.keyY] = cg.vert
        settings.appSettings[variant.keyZ] = cg.long
        backup_yal_prefs("QuickViews CG update")
        settings.writeSettings(settings.appSettings)
        P.logInfoTS("QuickViews CG update: stored baseline for " .. variant.name .. " (no adjustment performed)")
        return
    end

    local delta_z = cg.long - stored_z
    local delta_y = cg.vert - stored_y
    if math.abs(delta_z) < 0.0001 and math.abs(delta_y) < 0.0001 then
        P.logInfoTS("QuickViews CG update: no CG change for " .. variant.name)
        return
    end

    local indices, qv_data = read_quickview_data(prefs_path)
    if not indices then
        P.logInfoTS("QuickViews CG update: failed to read quick views (" .. tostring(qv_data) .. ")")
        return
    end

    local ok_backup, backup_or_err = backup_file(prefs_path)
    if not ok_backup then
        P.logInfoTS("QuickViews CG update: backup failed (" .. tostring(backup_or_err) .. ")")
        return
    end
    P.logInfoTS("QuickViews CG update: backup created at " .. tostring(backup_or_err))

    queue_quickview_cg_job(variant, cg, delta_y, delta_z, indices, qv_data)
end

function P.adjustQuickViewsAndXCameraForCgChange()
    local settings = require("settings")
    if not views_change_allowed() then
        P.logInfoTS("QuickViews+X-Camera CG update blocked (requires preflight, on ground, parking brake set)")
        return
    end
    if P.defaultViewUpdateJob then
        P.logInfoTS("QuickViews+X-Camera CG update blocked (default view update in progress)")
        return
    end
    if P.quickViewCgUpdateJob then
        P.logInfoTS("QuickViews+X-Camera CG update already in progress")
        return
    end
    local variant, v_err = get_current_zibo_variant()
    if not variant then
        P.logInfoTS("QuickViews+X-Camera CG update: " .. tostring(v_err))
        return
    end

    local base = get_zibo_base_path()
    local acf_path = base .. variant.acf
    local prefs_path = base .. variant.prefs
    local xcamera_path = base .. variant.xcamera
    local cg, err = read_acf_cg(acf_path)
    if not cg then
        P.logInfoTS("QuickViews+X-Camera CG update: failed to read " .. variant.name .. " CG (" .. tostring(err) .. ")")
        return
    end

    local stored_y = tonumber(settings.appSettings[variant.keyY])
    local stored_z = tonumber(settings.appSettings[variant.keyZ])
    if stored_y == nil or stored_z == nil then
        settings.appSettings[variant.keyY] = cg.vert
        settings.appSettings[variant.keyZ] = cg.long
        backup_yal_prefs("QuickViews+X-Camera CG update")
        settings.writeSettings(settings.appSettings)
        P.logInfoTS("QuickViews+X-Camera CG update: stored baseline for " .. variant.name .. " (no adjustment performed)")
        return
    end

    local delta_z = cg.long - stored_z
    local delta_y = cg.vert - stored_y
    if math.abs(delta_z) < 0.0001 and math.abs(delta_y) < 0.0001 then
        P.logInfoTS("QuickViews+X-Camera CG update: no CG change for " .. variant.name)
        return
    end

    local indices, qv_data = read_quickview_data(prefs_path)
    if not indices then
        P.logInfoTS("QuickViews+X-Camera CG update: failed to read quick views (" .. tostring(qv_data) .. ")")
        return
    end

    local ok_backup, backup_or_err = backup_file(prefs_path)
    if not ok_backup then
        P.logInfoTS("QuickViews+X-Camera CG update: prefs backup failed (" .. tostring(backup_or_err) .. ")")
        return
    end
    P.logInfoTS("QuickViews+X-Camera CG update: prefs backup created at " .. tostring(backup_or_err))

    local xcam_file = io.open(xcamera_path, "r")
    if not xcam_file then
        P.logInfoTS("QuickViews+X-Camera CG update: X-Camera file not found (" .. tostring(xcamera_path) .. ")")
        return
    end
    xcam_file:close()

    local ok_xcam_backup, xcam_backup_or_err = backup_file(xcamera_path)
    if not ok_xcam_backup then
        P.logInfoTS("QuickViews+X-Camera CG update: X-Camera backup failed (" .. tostring(xcam_backup_or_err) .. ")")
        return
    end
    P.logInfoTS("QuickViews+X-Camera CG update: X-Camera backup created at " .. tostring(xcam_backup_or_err))

    local delta_m_y = delta_y * 0.3048
    local delta_m_z = delta_z * 0.3048
    local ok_xcam, updated, used_offsets, offsets_reset = update_xcamera_cg_offsets(xcamera_path, delta_m_y, delta_m_z)
    if not ok_xcam then
        P.logInfoTS("QuickViews+X-Camera CG update: X-Camera update failed (" .. tostring(updated) .. ")")
        return
    end
    local mode = used_offsets and "offsets" or "positions"
    local reset_note = ""
    if offsets_reset and offsets_reset > 0 then
        reset_note = string.format(", %d offset resets", offsets_reset)
    end
    P.logInfoTS(string.format("QuickViews+X-Camera CG update: X-Camera updated (%d views, %s, origin=0 filter%s)", updated or 0, mode, reset_note))

    queue_quickview_cg_job(variant, cg, delta_y, delta_z, indices, qv_data)
end

function P.stepQuickViewsCgUpdate()
    local job = P.quickViewCgUpdateJob
    if not job then
        return false
    end

    if not views_change_allowed() then
        restore_pilots_head(job.snapshot)
        if job.tobiiWasOn and tobii_eq then
            local tobii_now = get(tobii_eq)
            if tobii_now == 0 then
                P.command_once("sim/view/tobii_eyetracker_toggle")
            end
        end
        P.quickViewCgUpdateJob = nil
        P.logInfoTS("QuickViews CG update aborted (view change no longer allowed)")
        return false
    end

    if tobii_eq then
        local tobii_on = (get(tobii_eq) == 1)
        if job.tobiiWasOn == nil then
            job.tobiiWasOn = tobii_on
        end
        if job.tobiiWasOn and tobii_on then
            if not job.tobiiDisableRequested then
                P.command_once("sim/view/tobii_eyetracker_toggle")
                job.tobiiDisableRequested = true
                P.logInfoTS("QuickViews CG update: Tobii active, disabling")
            end
            return true
        end
    end

    local idx = job.indices[job.index_pos]
    if not idx then
        local settings = require("settings")
        settings.appSettings[job.variant.keyY] = job.target_cg_vert
        settings.appSettings[job.variant.keyZ] = job.target_cg_long
        backup_yal_prefs("QuickViews CG update", job)
        settings.writeSettings(settings.appSettings)
        restore_pilots_head(job.snapshot)
        if job.tobiiWasOn and tobii_eq then
            local tobii_now = get(tobii_eq)
            if tobii_now == 0 then
                P.command_once("sim/view/tobii_eyetracker_toggle")
                P.logInfoTS("QuickViews CG update: Tobii restored")
            end
        end
        P.quickViewCgUpdateJob = nil
        P.logInfoTS(string.format("QuickViews CG update completed: %s (%d views, deltaY %.4f ft, deltaZ %.4f ft)", job.variant.name, job.total, job.delta_y, job.delta_z))
        return false
    end

    if job.stage == QV_UPDATE_STAGE_SELECT then
        P.command_once("sim/view/quick_look_" .. tostring(idx))
        job.stage = QV_UPDATE_STAGE_SAVE
        return true
    end

    local qv = job.qv_data and job.qv_data[idx] or nil
    if not qv then
        P.logInfoTS("QuickViews CG update: missing prefs data for quick view " .. tostring(idx))
    else
        local ok = false
        if qv.x ~= nil then
            set(pilots_head_x, qv.x)
            ok = true
        else
            P.logInfoTS("QuickViews CG update: missing head X for quick view " .. tostring(idx))
        end
        if qv.y ~= nil then
            set(pilots_head_y, qv.y - job.delta_m_y)
            ok = true
        else
            P.logInfoTS("QuickViews CG update: missing head Y for quick view " .. tostring(idx))
        end
        if qv.z ~= nil then
            set(pilots_head_z, qv.z - job.delta_m_z)
            ok = true
        else
            P.logInfoTS("QuickViews CG update: missing head Z for quick view " .. tostring(idx))
        end
        if qv.psi ~= nil then set(pilots_head_psi, qv.psi) end
        if qv.the ~= nil then set(pilots_head_the, qv.the) end
        if qv.phi ~= nil then set(pilots_head_phi, qv.phi) end
        if ok then
            P.command_once("sim/view/quick_look_" .. tostring(idx) .. "_mem")
        end
    end

    job.index_pos = job.index_pos + 1
    job.stage = QV_UPDATE_STAGE_SELECT
    if job.index_pos > job.total then
        local settings = require("settings")
        settings.appSettings[job.variant.keyY] = job.target_cg_vert
        settings.appSettings[job.variant.keyZ] = job.target_cg_long
        backup_yal_prefs("QuickViews CG update", job)
        settings.writeSettings(settings.appSettings)
        restore_pilots_head(job.snapshot)
        P.quickViewCgUpdateJob = nil
        P.logInfoTS(string.format("QuickViews CG update completed: %s (%d views, deltaY %.4f ft, deltaZ %.4f ft)", job.variant.name, job.total, job.delta_y, job.delta_z))
        return false
    end

    return true
end

function P.applyDefaultViewFromQV0()
    if P.quickViewCgUpdateJob then
        P.logInfoTS("Default view update blocked (QuickViews CG update in progress)")
        return
    end
    local variant, v_err = get_current_zibo_variant()
    if not variant then
        P.logInfoTS("Default view update: " .. tostring(v_err))
        return
    end
    local base = get_zibo_base_path()
    local qv, qv_err = read_qv0(base .. variant.prefs)
    if not qv then
        P.logInfoTS("Default view update failed: " .. tostring(qv_err))
        return
    end
    local ok, err = apply_default_view_from_qv0_data(base .. variant.acf, qv)
    if ok then
        if err == "no-change" then
            P.logInfoTS("Default view already matches QV0 (" .. variant.name .. ")")
        else
            P.logInfoTS("Default view updated from QV0 (" .. variant.name .. ")")
            P.logInfoTS("Default view update: ACF updated (reload not performed)")
        end
    else
        P.logInfoTS("Default view update failed (" .. variant.name .. "): " .. tostring(err))
    end
end

function P.stepDefaultViewUpdate()
    local job = P.defaultViewUpdateJob
    if not job then
        return false
    end
    if P.quickViewCgUpdateJob then
        restore_pilots_head(job.snapshot)
        P.defaultViewUpdateJob = nil
        P.logInfoTS("Default view update aborted (QuickViews CG update in progress)")
        return false
    end
    if not views_change_allowed() then
        restore_pilots_head(job.snapshot)
        P.defaultViewUpdateJob = nil
        P.logInfoTS("Default view update aborted (view change no longer allowed)")
        return false
    end

    if job.stage == DEFAULT_VIEW_STAGE_NORMALIZE then
        P.command_once("sim/view/default_view")
        job.stage = DEFAULT_VIEW_STAGE_SELECT
        return true
    end

    if job.stage == DEFAULT_VIEW_STAGE_SELECT then
        P.command_once("sim/view/quick_look_0")
        job.stage = DEFAULT_VIEW_STAGE_APPLY
        return true
    end

    local qv = {
        lat = get(pilots_head_x),
        vert = get(pilots_head_y),
        long = get(pilots_head_z),
        pitch = get(pilots_head_the)
    }
    restore_pilots_head(job.snapshot)
    if qv.lat == nil or qv.vert == nil or qv.long == nil or qv.pitch == nil then
        P.defaultViewUpdateJob = nil
        P.logInfoTS("Default view update failed: current QV0 values not found")
        return false
    end

    local base = get_zibo_base_path()
    local did_adjust = false
    local ok, err = apply_default_view_from_qv0_data(base .. job.variant.acf, qv)
    if ok then
        if err == "no-change" then
            P.logInfoTS("Default view already matches QV0 (" .. job.variant.name .. ")")
        else
            did_adjust = true
            P.logInfoTS("Default view updated from QV0 (" .. job.variant.name .. ")")
        end
    else
        P.logInfoTS("Default view update failed (" .. job.variant.name .. "): " .. tostring(err))
    end
    P.defaultViewUpdateJob = nil
    if did_adjust then
        P.logInfoTS("Default view update: ACF updated (reload not performed)")
    end
    return false
end

local function check_default_view_matches_qv0(variant, base)
    local acf_path = base .. variant.acf
    local prefs_path = base .. variant.prefs
    local qv, qv_err = read_qv0(prefs_path)
    if not qv then
        P.logInfoTS("Default view check failed (" .. variant.name .. "): " .. tostring(qv_err))
        return
    end
    local cg, cg_err = read_acf_cg(acf_path)
    if not cg then
        P.logInfoTS("Default view check failed (" .. variant.name .. "): " .. tostring(cg_err))
        return
    end
    local current_view, view_err = read_acf_default_view(acf_path)
    if not current_view then
        P.logInfoTS("Default view check failed (" .. variant.name .. "): " .. tostring(view_err))
        return
    end
    local meters_to_feet = 3.28084
    local new_lat = (cg.lat or 0.0) + (qv.lat * meters_to_feet)
    local new_vert = cg.vert + (qv.vert * meters_to_feet)
    local new_long = cg.long + (qv.long * meters_to_feet)
    local new_pitch = qv.pitch
    if approx_equal(current_view.lat, new_lat) and approx_equal(current_view.vert, new_vert)
        and approx_equal(current_view.long, new_long) and approx_equal(current_view.pitch, new_pitch) then
        P.logInfoTS("Default view matches QV0 (" .. variant.name .. ")")
    else
        P.logInfoTS(string.format(
            "Default view mismatch vs QV0 (%s): def %.6f/%.6f/%.6f/%.6f vs qv0 %.6f/%.6f/%.6f/%.6f",
            variant.name,
            current_view.lat, current_view.vert, current_view.long, current_view.pitch,
            new_lat, new_vert, new_long, new_pitch
        ))
    end
end

function P.checkCgBaselineAtStartup()
    local settings = require("settings")
    local base = get_zibo_base_path()
    local variants = {
        { name = "4k", acf = "b738_4k.acf", keyY = "CG_BASE_4K_Y", keyZ = "CG_BASE_4K_Z" },
        { name = "2k", acf = "b738.acf", keyY = "CG_BASE_2K_Y", keyZ = "CG_BASE_2K_Z" },
    }
    for _, v in ipairs(variants) do
        local acf_path = base .. v.acf
        local cg, err = read_acf_cg(acf_path)
        if not cg then
            P.logInfoTS("CG baseline check failed (" .. v.name .. "): " .. tostring(err))
        else
            local stored_y = tonumber(settings.appSettings[v.keyY])
            local stored_z = tonumber(settings.appSettings[v.keyZ])
            if stored_y == nil or stored_z == nil then
                settings.appSettings[v.keyY] = cg.vert
                settings.appSettings[v.keyZ] = cg.long
                settings.writeSettings(settings.appSettings)
                P.logInfoTS(string.format("CG baseline stored (%s): Y=%.6f Z=%.6f", v.name, cg.vert, cg.long))
            else
                if approx_equal(stored_y, cg.vert) and approx_equal(stored_z, cg.long) then
                    P.logInfoTS(string.format("CG baseline matches (%s): Y=%.6f Z=%.6f", v.name, stored_y, stored_z))
                else
                    P.logInfoTS(string.format(
                        "CG baseline mismatch (%s): stored Y/Z %.6f/%.6f vs acf %.6f/%.6f",
                        v.name, stored_y, stored_z, cg.vert, cg.long
                    ))
                end
            end
        end
    end
end

function P.checkDefaultViewAtStartup()
    local base = get_zibo_base_path()
    local variants = {
        { name = "4k", acf = "b738_4k.acf", prefs = "b738_4k_prefs.txt" },
        { name = "2k", acf = "b738.acf", prefs = "b738_prefs.txt" },
    }
    for _, v in ipairs(variants) do
        check_default_view_matches_qv0(v, base)
    end
end

return helpers
