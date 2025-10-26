local P = {}
helpers = P -- package name

local def = require("definitions")

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


P.xpVersion = sasl.getXPVersion()
P.isXp11 = (P.xpVersion < 12000)
P.isXp12 = (P.xpVersion >= 12000 and P.xpVersion < 13000)

--------------------------------------------------------------------------------------------------------------
function P.initTailNum()
    P.isZibo = ((string.sub(get(acf_tailnum), 1, 5) == "ZB738") or (string.sub(get(acf_tailnum), 1, 4) == "B736") or (string.sub(get(acf_tailnum), 1, 4) == "B737")  or (string.sub(get(acf_tailnum), 1, 4) == "738") or (string.sub(get(acf_tailnum), 1, 4) == "B739"))
    if P.isZibo then
        sasl.logDebug("is zibo YES ->" .. string.sub(get(acf_tailnum), 1, 5) .. "<-") 
    else 
        sasl.logDebug("is zibo NO ->" .. string.sub(get(acf_tailnum), 1, 5) .. "<-")
    end
    return P.isZibo
end

--------------------------------------------------------------------------------------------------------------
function P.checkForUpdate()
    local url = def.YALGITHUBURL
    local updateAvailable = false
    local newVersion = ""
    local downloadResult, contents = sasl.net.downloadFileContentsSync(url)
    if downloadResult then -- ... process data
        newVersion = helpers.cleanString(contents, true)
        sasl.logDebug(string.format("Current version: %s, available version %s", def.VERSION, newVersion))
        if (tonumber(newVersion) > (tonumber(def.VERSION))) then
            updateAvailable = true
            sasl.logInfo(string.format("New YAL version available v%s", newVersion))
        else
            sasl.logInfo("YAL is up to date, no new version available")
        end
    else
        sasl.logInfo("Check for Update FAILED")
    end
    return updateAvailable, newVersion
end

-------------------------------------------------------------------------------------------------------------- 
function P.get(dataref)
return get(globalProperty(dataref))
end    

function P.command_once(cmd)
    local cmdId = sasl.findCommand(cmd) 
    sasl.commandOnce(cmdId)
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
function file_exists_v2(file)
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
function dir_exists_v2(path)
    return file_exists_v2(path .. "/")
end

function P.check_create_path(path)
    if not dir_exists_v2(path) then
        sasl.logInfo("Folder " .. path .. " does not exist... creating it")
        P.create_directories({path})
        if not dir_exists_v2(path) then
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
            if byte ~= 0 then
                cleanStr = cleanStr .. string.char(byte)
            end
        end
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
        if string.match(char, "%a") or string.match(char, "%d") then
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
function P.isvalidrwy(runway)
    if type(runway) ~= "string" then
        return false
    end

    local pattern = "^(%d?%d)([LRCT]?)$"

    local number, suffix = string.match(runway, pattern)

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
function P.adjustrwy(runway, increment)
    
    if not P.isvalidrwy(runway) then
        return nil
    end

    local number, suffix = string.match(runway, "^(%d+)(%a*)$")

    number = tonumber(number)

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
    local number = tonumber(string.match(runway, "%d+"))
    local letter = string.match(runway, "%a") or ""

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
function P.decodemetar(metar)
    local result = {}
    local parts = {}

    sasl.logDebug("Starting METAR parsing")
    local current_part = ""
    for i = 1, #metar do
        local c = string.sub(metar, i, i)
        if (c == " ") then
            if (#current_part > 0) then
                table.insert(parts, current_part)
                current_part = ""
            end
        else
            current_part = current_part .. c
        end
    end
    if (#current_part > 0) then
        table.insert(parts, current_part)
    end

    sasl.logDebug("METAR parts:")
    for idx, part_val in ipairs(parts) do
        sasl.logDebug(string.format("   [%d] = %s", idx, part_val))
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

        elseif (not result.visibility and string.find(part, "SM$")) then
            local sm_val_str = string.sub(part, 1, #part - 2)
            local sm_value
            local int_part, frac_part = string.match(sm_val_str, "^(%d+)%s+(%d+/%d+)$")
            if int_part and frac_part then
                local num, den = string.match(frac_part, "(%d+)/(%d+)")
                if num and den then
                    sm_value = tonumber(int_part) + (tonumber(num) / tonumber(den))
                end
            else
                local num, den = string.match(sm_val_str, "^(%d+)/(%d+)$")
                if num and den then
                    sm_value = tonumber(num) / tonumber(den)
                else
                    sm_value = tonumber(sm_val_str)
                end
            end

            if (sm_value) then
                local meters = math.floor(sm_value * 1609.34 + 0.5)
                result.visibility = { value = math.min(meters, 10000) }
                sasl.logDebug(string.format("Parsed visibility: %sSM, converted to %d meters", sm_val_str, result.visibility.value))
                parsed = true

                -- ## START VISIBILITY CHANGE ##
                if result.visibility and i + 1 <= #parts then
                    local next_part = parts[i + 1]
                    local dir_vis_val, dir_code = string.match(next_part, "^(%d%d%d%d)([NSEW][EW]?)$")
                    if dir_vis_val and dir_code then
                        result.visibility.directional = {
                            value = tonumber(dir_vis_val),
                            direction = dir_code
                        }
                        sasl.logDebug(string.format("Parsed directional visibility: %d meters towards %s",
                                      result.visibility.directional.value, result.visibility.directional.direction))
                        i = i + 1
                    end
                end
                -- ## END VISIBILITY CHANGE ##
            else
                sasl.logError("Warning: Could not parse SM visibility value from: " .. part)
            end

        elseif (not result.visibility and #part == 4 and (tonumber(part) or part == "9999")) then
            if (part == "9999") then
                result.visibility = { value = 10000 }
                sasl.logDebug("Parsed visibility: 10000+ meters (from 9999)")
            else
                result.visibility = { value = tonumber(part) }
                sasl.logDebug(string.format("Parsed visibility: %d meters", result.visibility.value))
            end
            parsed = true

            -- ## START VISIBILITY CHANGE ##
            if result.visibility and i + 1 <= #parts then
                local next_part = parts[i + 1]
                local dir_vis_val, dir_code = string.match(next_part, "^(%d%d%d%d)([NSEW][EW]?)$")
                if dir_vis_val and dir_code then
                    result.visibility.directional = {
                        value = tonumber(dir_vis_val),
                        direction = dir_code
                    }
                    sasl.logDebug(string.format("Parsed directional visibility: %d meters towards %s",
                                  result.visibility.directional.value, result.visibility.directional.direction))
                    i = i + 1
                end
            end
            -- ## END VISIBILITY CHANGE ##

        elseif (string.sub(part, 1, 1) == "R" and string.find(part, "/", 1, true) and #part >= 5) then
            result.runway_reports = result.runway_reports or {}
            table.insert(result.runway_reports, part)
            sasl.logDebug("Parsed runway report: "..part)
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
            sasl.logInfo("METAR Parsing unknown element: " .. part)
        end
        i = i + 1
    end

    sasl.logDebug("METAR parsing complete")
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
                sasl.logInfo("METAR for " .. metarTable.icaocode .. " successfully downloaded.")
                metarTable.metar.raw_text = metarstring
                metarTable.decodedmetar = helpers.decodemetar(metarstring)
                metarTable.metarfound = true
            else
                sasl.logInfo("Downloaded METAR file for " .. metarTable.icaocode .. " was empty.")
            end
        else
            sasl.logInfo("Could not open temp file for " .. metarTable.icaocode)
        end
        os.remove(path)
    else
        sasl.logInfo("Download of METAR failed for " .. metarTable.icaocode .. ": " .. tostring(responseCodeOrError))
    end
end

--------------------------------------------------------------------------------------------------------------
function P.getMetar(icaocode, metarTable)

    if not (icaocode and icaocode ~= "XXXX" and metarTable) then return end

    local metarstring = sasl.weather.getMETARForAirport(icaocode)

    if (metarstring and (metarstring ~= "") and (metarstring:sub(1, 4) == icaocode)) then
        sasl.logInfo("METAR for " .. icaocode .. " successfully loaded from X-Plane.")
        metarTable.icaocode = icaocode
        metarTable.metar.raw_text = metarstring
        metarTable.decodedmetar = helpers.decodemetar(metarstring)
        metarTable.metarfound = true
    else
        sasl.logInfo("X-Plane METAR for " .. icaocode .. " not found or invalid. Trying async web download.")
        
        local metarUrl = def.AVWEATHERFURLCSV .. icaocode
        local tempFilePath = def.YALCACHEPATH .. icaocode .. "_metar.txt"
        metarTable.icaocode = icaocode


        sasl.net.downloadFileAsync(metarUrl, tempFilePath, function(url, path, isOk, responseCodeOrError)
            P.onMetarDownloaded(url, path, isOk, responseCodeOrError, metarTable)
        end)
    end
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
function P.shouldCheckRunwaySuitability(metar, runwayDesignator)
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
    local magneticWindDirection = (windDirection - magnetic_variation + 360) % 360 

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

    sasl.logDebug(string.format("Runway %s is suitable based on current wind conditions.", runwayDesignator))
    return true -- Landebahn ist innerhalb der Schwellenwerte geeignet
end

--------------------------------------------------------------------------------------------------------------
-- Nimmt jetzt runwayName ("07L", "25R", etc.)
function P.formatMetarSpeechSummary(metar, runwayName)
    local parts = {}

    local icaocode = metar.icaocode
    local metar_data = metar.decodedmetar

    if icaocode and #icaocode > 0 then
        table.insert(parts, P.addspaces(icaocode))
    end

    -- NEU: Heading aus Runway-Namen ableiten, nur wenn gültig
    local derivedHeading = nil
    -- *** VERBESSERUNG: Prüfe mit P.isvalidrwy ***
    if P.isvalidrwy(runwayName) then
        -- Versuche, die ersten zwei Ziffern zu extrahieren
        local rwyNumStr = string.match(runwayName, "^(%d%d)")
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
                      sasl.logInfo("formatMetarSpeechSummary: Ungültiges Heading " .. tostring(derivedHeading or "nil") .. " aus Runway '" .. runwayName .. "' abgeleitet (nach Nummern-Extraktion).") -- Geändert zu logInfo
                 end
            else
                 sasl.logInfo("formatMetarSpeechSummary: Konnte Ziffern '" .. rwyNumStr .. "' aus Runway '" .. runwayName .. "' nicht in Zahl umwandeln.") -- Geändert zu logInfo
            end
        else
             sasl.logInfo("formatMetarSpeechSummary: Konnte keine Heading-Zahl aus gültiger Runway '" .. runwayName .. "' extrahieren (string.match fehlgeschlagen).") -- Geändert zu logInfo
        end
    else
         -- Log optional, wenn ungültige Namen übergeben werden könnten
         if runwayName and runwayName ~= "" then
              sasl.logInfo("formatMetarSpeechSummary: Übergabener runwayName '".. runwayName .."' ist laut P.isvalidrwy ungültig. Keine Windkomponentenberechnung.") -- Geändert zu logInfo
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
            sasl.logInfo(string.format("Calculating wind components: dir=%s, speed=%s, rwyHdg=%s",
                           tostring(dir), tostring(speed), tostring(derivedHeading)))
            -- Ruft die korrigierte Funktion auf, die vorzeichenbehafteten Crosswind liefert
            local headwind, crosswind = P.calculateWindComponents(dir, derivedHeading, speed)
            sasl.logInfo(string.format("Calculated components: headwind=%.2f, crosswind=%.2f", headwind, crosswind))

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
        if metar_data.cavok then
            vis_part = "Visibility 10 kilometers or more"
        elseif vis_val >= 10000 then
            vis_part = vis_part .. "10 kilometers or more"
        elseif vis_val >= 1609 then
            vis_part = vis_part .. string.format("%d statute miles", math.floor(vis_val / 1609.34 + 0.5))
        elseif vis_val >= 1000 then
            vis_part = vis_part .. string.format("%d kilometers", math.floor(vis_val / 1000 + 0.5))
        else
            vis_part = vis_part .. string.format("%d meters", vis_val)
        end
        if metar_data.visibility.directional then
             vis_part = vis_part .. string.format(" specific %d meters to the %s",
                                 metar_data.visibility.directional.value,
                                 metar_data.visibility.directional.direction)
        end
        table.insert(parts, vis_part)
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
                    report_str = report_str .. " (" .. cloud.type .. ")"
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

    return table.concat(parts, ". ") -- Punkt als Trenner
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
    local relativeAngle = windDirectionDegrees - runwayHeadingDegrees

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
function P.determineTakeoffFlapsSetting(totalweightkgs, deprwylen, deprwyheading, elevation, metar)
    local STANDARD_TAKEOFF_FLAPS = 5
    local TAKEOFF_WEIGHT_THRESHOLD_HIGH = 65000
    local TAKEOFF_WEIGHT_THRESHOLD_VERY_HIGH = 70000

    local TAKEOFF_RUNWAY_LENGTH_SHORT_THRESHOLD = 2000
    local TAKEOFF_RUNWAY_LENGTH_VERY_SHORT_THRESHOLD = 1600

    local TAKEOFF_DENSITY_ALTITUDE_THRESHOLD_HIGH = 3000

    local TAKEOFF_TAILWIND_CONSIDERATION_THRESHOLD = 5
    -- local TAKEOFF_WET_RUNWAY_PENALTY_FLAPS = 1 -- Not currently used directly, logic adds flap step

    -- Check for essential METAR data
    if not (metar.decodedmetar and metar.decodedmetar.wind and metar.decodedmetar.wind.direction ~= nil and metar.decodedmetar.wind.speed ~= nil and
            metar.decodedmetar.temperature and metar.decodedmetar.temperature.value ~= nil and
            metar.decodedmetar.pressure and metar.decodedmetar.pressure.qnh_hpa ~= nil) then
        sasl.logInfo("determineTakeoffFlapsSetting: Insufficient METAR data, returning default flaps " .. STANDARD_TAKEOFF_FLAPS)
        return STANDARD_TAKEOFF_FLAPS
    end

    -- Check for essential input parameters
    if not (type(totalweightkgs) == "number" and totalweightkgs > 0 and
            type(deprwylen) == "number" and deprwylen > 0 and
            type(elevation) == "number" and type(deprwyheading) == "number") then
        sasl.logInfo("determineTakeoffFlapsSetting: Invalid input parameters (weight, length, elevation, heading), returning default flaps " .. STANDARD_TAKEOFF_FLAPS)
        return STANDARD_TAKEOFF_FLAPS
    end

    -- Determine if runway is likely wet/contaminated
    local isRunwayWet = false
    if metar.decodedmetar.weather then -- Check if weather array exists
        for _, wx in ipairs(metar.decodedmetar.weather) do
            if wx.phenomenon == "RA" or wx.phenomenon == "SN" or wx.phenomenon == "DZ" or
               wx.phenomenon == "FZRA" or wx.phenomenon == "FZDZ" or wx.phenomenon == "FZFG" then
                isRunwayWet = true
                break
            end
        end
    end
    -- Also consider freezing temps, though precipitation is a stronger indicator
    if not isRunwayWet and metar.decodedmetar.temperature.value < 1 then
        -- Maybe add a log here if needed, but precip check is usually sufficient
        -- isRunwayWet = true -- Decide if temp alone should trigger it
    end
    if isRunwayWet then sasl.logDebug("determineTakeoffFlapsSetting: Runway considered wet/contaminated based on METAR.") end

    -- Start with standard flaps
    local recommendedFlaps = STANDARD_TAKEOFF_FLAPS

    -- Calculate wind components (using magnetic)
    local headwindComponent = 0
    local crosswindComponent = 0 -- Although not used, calculate for completeness
    local trueWindDirection = metar.decodedmetar.wind.direction
    local windSpeed = metar.decodedmetar.wind.speed

    if type(trueWindDirection) == "number" and windSpeed > 0 then -- Only calculate if wind is numeric and has speed
        -- Get magnetic variation
        local magnetic_variation = 0
        if metar.latitude and metar.longitude then
            magnetic_variation = sasl.getMagneticVariation(metar.latitude, metar.longitude) or 0
        -- Add fallback if needed, e.g., using aircraft position:
        -- elseif P.latitude and P.longitude then
        --     magnetic_variation = sasl.getMagneticVariation(P.latitude, P.longitude) or 0
        end

        -- Correct wind direction to magnetic
        local magneticWindDirection = (trueWindDirection - magnetic_variation + 360) % 360

        -- Calculate components using MAGNETIC wind and MAGNETIC runway heading
        headwindComponent, crosswindComponent = P.calculateWindComponents(
            magneticWindDirection,
            deprwyheading,
            windSpeed
        )

        sasl.logDebug(string.format("Takeoff Flaps Calc: TrueWind=%s@%dkt, MagVar=%.1f, MagWind=%03d@%dkt, RwyHdg=%d -> Headwind=%.1f kt, Crosswind=%.1f kt",
                        tostring(trueWindDirection), windSpeed, magnetic_variation, math.floor(magneticWindDirection+0.5), windSpeed, deprwyheading, headwindComponent, crosswindComponent))
    else
         sasl.logDebug("Takeoff Flaps Calc: Wind is VRB, Calm, or direction not numeric. Using 0 for components.")
    end

    -- Adjust flaps based on weight
    if totalweightkgs > TAKEOFF_WEIGHT_THRESHOLD_VERY_HIGH then
        recommendedFlaps = 15
        sasl.logDebug("Takeoff Flaps Calc: Weight > VERY_HIGH threshold -> Base flaps 15")
    elseif totalweightkgs > TAKEOFF_WEIGHT_THRESHOLD_HIGH then
        recommendedFlaps = math.max(recommendedFlaps, 10)
        sasl.logDebug("Takeoff Flaps Calc: Weight > HIGH threshold -> Base flaps increased to " .. recommendedFlaps)
    end

    -- Adjust flaps based on runway length
    if deprwylen < TAKEOFF_RUNWAY_LENGTH_VERY_SHORT_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 15)
        sasl.logDebug("Takeoff Flaps Calc: Runway < VERY_SHORT threshold -> Flaps increased to " .. recommendedFlaps)
    elseif deprwylen < TAKEOFF_RUNWAY_LENGTH_SHORT_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 10)
        sasl.logDebug("Takeoff Flaps Calc: Runway < SHORT threshold -> Flaps increased to " .. recommendedFlaps)
    end

    -- Adjust flaps based on density altitude
    local airport_elev_m = elevation -- Use provided elevation as primary source
    -- Optional: Use METAR elevation if more reliable?
    -- if (metar.metar and tonumber(metar.metar.elevation_m)) then
    --     airport_elev_m = metar.metar.elevation_m
    -- end

    local densityAltitude = P.calculateDensityAltitude(
        airport_elev_m, -- Should be in meters for the function
        metar.decodedmetar.temperature.value,
        metar.decodedmetar.pressure.qnh_hpa
    )
    sasl.logDebug(string.format("Takeoff Flaps Calc: Density Altitude calculated: %.0f ft", densityAltitude * 3.28084)) -- Log in feet
    if densityAltitude * 3.28084 > TAKEOFF_DENSITY_ALTITUDE_THRESHOLD_HIGH then -- Compare threshold in feet
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

    sasl.logInfo("determineTakeoffFlapsSetting: Recommended flaps setting: " .. recommendedFlaps)
    return recommendedFlaps
end

--------------------------------------------------------------------------------------------------------------
function P.calcappflapsvref(totalweightkgs, desrwylen, desrwyheading, vref30, metar)

    local weatherData = metar.decodedmetar

    -- Check essential METAR data
    if not (weatherData and weatherData.wind and weatherData.wind.direction ~= nil and weatherData.wind.speed ~= nil and
            weatherData.temperature and weatherData.temperature.value ~= nil and
            weatherData.pressure and weatherData.pressure.qnh_hpa ~= nil) then
        sasl.logInfo("calcappflapsvref: Insufficient METAR data, returning default 30/" .. tostring(vref30))
        return 30, vref30
    end

    -- Check essential input parameters
    if not (type(totalweightkgs) == "number" and totalweightkgs > 0 and
            type(desrwylen) == "number" and desrwylen > 0 and
            type(desrwyheading) == "number" and -- Keep as number
            type(vref30) == "number" and vref30 > 0) then
        sasl.logInfo("calcappflapsvref: Invalid input parameters, returning default 30/" .. tostring(vref30))
        return 30, vref30
    end

    -- Calculate wind components (using magnetic)
    local headwindComponent = 0
    local crosswindKnots = 0 -- Signed: +Left / -Right
    local trueWindDirection = weatherData.wind.direction
    local windSpeed = weatherData.wind.speed

    if type(trueWindDirection) == "number" and windSpeed > 0 then
        -- Get magnetic variation
        local magnetic_variation = 0
        if metar.latitude and metar.longitude then
            magnetic_variation = sasl.getMagneticVariation(metar.latitude, metar.longitude) or 0
        end

        -- Correct wind direction to magnetic
        local magneticWindDirection = (trueWindDirection - magnetic_variation + 360) % 360

        -- Calculate components using MAGNETIC wind and MAGNETIC runway heading
        headwindComponent, crosswindKnots = P.calculateWindComponents(
            magneticWindDirection,
            desrwyheading, -- Assume this is already magnetic
            windSpeed
        )
        sasl.logDebug(string.format("App Flaps Calc: TrueWind=%s@%dkt, MagVar=%.1f, MagWind=%03d@%dkt, RwyHdg=%d -> Headwind=%.1f kt, Crosswind=%.1f kt",
                        tostring(trueWindDirection), windSpeed, magnetic_variation, math.floor(magneticWindDirection+0.5), windSpeed, desrwyheading, headwindComponent, crosswindKnots))
    else
        sasl.logDebug("App Flaps Calc: Wind is VRB, Calm, or direction not numeric. Using 0 for components.")
    end


    -- Determine bad weather conditions
    local isBadWeather = false
    if weatherData.weather then
        for _, wx_entry in ipairs(weatherData.weather) do
            -- Consider heavy rain/snow, thunderstorms, freezing conditions etc.
            if wx_entry.intensity == "heavy" or wx_entry.phenomenon == "TS" or
               wx_entry.phenomenon == "SN" or wx_entry.phenomenon == "FZRA" or wx_entry.phenomenon == "FZDZ" then
                isBadWeather = true
                sasl.logDebug("App Flaps Calc: Bad weather detected (precipitation/TS).")
                break
            end
        end
    end
    -- Low vis / Low ceiling might also imply bad weather/need for more flaps
    if not isBadWeather and weatherData.visibility and weatherData.visibility.value and (weatherData.visibility.value < 5000) then
         isBadWeather = true
         sasl.logDebug("App Flaps Calc: Bad weather detected (low visibility).")
    end
    if not isBadWeather and weatherData.clouds and #weatherData.clouds > 0 then
         for _, cloud in ipairs(weatherData.clouds) do
             if (cloud.coverage == "BKN" or cloud.coverage == "OVC") and cloud.altitude and cloud.altitude < 1000 then
                 isBadWeather = true
                 sasl.logDebug("App Flaps Calc: Bad weather detected (low ceiling).")
                 break
             end
         end
    end

    -- Determine flaps setting (Passes SIGNED crosswind)
    local flapsSetting = P.determineLandingFlapsSetting(desrwylen, windSpeed, crosswindKnots, isBadWeather, totalweightkgs)

    -- Calculate Vref (Passes SIGNED crosswind - ensure calculateVref handles it or use math.abs if needed there)
    local vrefKnots = P.calculateVref(totalweightkgs, flapsSetting, weatherData, crosswindKnots)

    -- Round final values
    flapsSetting = math.floor(flapsSetting + 0.5)
    vrefKnots = math.floor(vrefKnots + 0.5)

    sasl.logInfo("calcappflapsvref: Calculated Flaps=" .. flapsSetting .. ", Vref=" .. vrefKnots)
    return flapsSetting, vrefKnots
end

--------------------------------------------------------------------------------------------------------------
function P.determineLandingFlapsSetting(runwayLengthMeters, windSpeedKnots, crosswindKnots, isBadWeather, weightKg)
    local LANDING_SHORT_RUNWAY_THRESHOLD = 2000
    local LANDING_HIGH_WIND_THRESHOLD = 20 -- Gusts might be more relevant here
    local LANDING_HIGH_CROSSWIND_THRESHOLD = 15
    local LANDING_HIGH_WEIGHT_THRESHOLD = 55000 -- In Kg

    -- *** KORREKTUR: Benutze math.abs() für den Crosswind-Vergleich ***
    local crosswindMagnitude = math.abs(crosswindKnots)

    sasl.logDebug(string.format("determineLandingFlapsSetting: Inputs: RwyLen=%.0f, WindSpd=%.0f, XWindMag=%.1f (Signed=%.1f), BadWx=%s, Weight=%.0f",
                   runwayLengthMeters, windSpeedKnots, crosswindMagnitude, crosswindKnots, tostring(isBadWeather), weightKg))

    -- Determine if Flaps 40 are recommended
    if runwayLengthMeters < LANDING_SHORT_RUNWAY_THRESHOLD or
       windSpeedKnots > LANDING_HIGH_WIND_THRESHOLD or
       crosswindMagnitude > LANDING_HIGH_CROSSWIND_THRESHOLD or -- Vergleich mit Betrag
       isBadWeather or
       weightKg > LANDING_HIGH_WEIGHT_THRESHOLD then
        sasl.logDebug("determineLandingFlapsSetting: Recommending Flaps 40 due to conditions.")
        return 40
    else
        sasl.logDebug("determineLandingFlapsSetting: Recommending Flaps 30.")
        return 30
    end
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
    local hasPrecipitation = false
    if weatherData.weather then
        for _, wx_entry in ipairs(weatherData.weather) do
            if wx_entry.phenomenon == "RA" or wx_entry.phenomenon == "SN" or wx_entry.phenomenon == "DZ" or wx_entry.phenomenon == "FZRA" or wx_entry.phenomenon == "FZDZ" then
                hasPrecipitation = true
                break
            end
        end
    end

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
function P.calcautobrake(landingSpeed, totalweightkgs, desrwylen, metar)
    local autobrakeSettings = {
        {maxDeceleration = 1.5, setting = def.AUTOBRAKE1},
        {maxDeceleration = 2.0, setting = def.AUTOBRAKE2},
        {maxDeceleration = 3.0, setting = def.AUTOBRAKE3},
        {maxDeceleration = 4.0, setting = def.AUTOBRAKEMAX}
    }

    local weatherData = metar.decodedmetar

    local requiredDeceleration = (landingSpeed^2) / (2 * desrwylen)

    if ((P.fieldexists(weatherData, "weather") and ((P.containsvalue(weatherData.weather, "FZRA")) or (P.containsvalue(weatherData.weather, "FZDZ")) or (P.containsvalue(weatherData.weather, "FZFG"))))
        or (P.fieldexists(weatherData, "temperature.value") and (weatherData.temperature.value < 1))) then
        requiredDeceleration = requiredDeceleration * 1.5
    elseif (P.fieldexists(weatherData, "weather") and (P.containsvalue(weatherData.weather, "SN")))  then
        requiredDeceleration = requiredDeceleration * 1.3
    elseif (P.fieldexists(weatherData, "weather") and (P.containsvalue(weatherData.weather, "RA"))) then
        requiredDeceleration = requiredDeceleration * 1.2
    end

    local weightFactor = totalweightkgs / 70000
    requiredDeceleration = requiredDeceleration * weightFactor

    for _, setting in ipairs(autobrakeSettings) do
        if requiredDeceleration <= setting.maxDeceleration then
            return setting.setting
        end
    end

    return def.AUTOBRAKE1
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
    local leg_names = {}
    local seenWaypoints = {}

    for word in string.gmatch(legs_string, "([^%s]+)") do
        table.insert(leg_names, word)
    end

    local max_count = math.min(#lat_array, #leg_names)

    for i = 1, max_count do
        local lat = lat_array[i]
        local lon = lon_array[i]
        local leg_name = leg_names[i]

        if lat ~= 0 or lon ~= 0 then
            if leg_name ~= "(INTC)" and leg_name ~= "DISCONTINUITY" and not leg_name:match("^%b()") then
                local identifier = string.format("%.4f_%.4f", lat, lon)
                if not seenWaypoints[identifier] then
                    local waypoint = {
                        name = leg_name,
                        latitude = lat,
                        longitude = lon,
                        distance_to_next = 0,
                        true_course = 0,
                        magnetic_course = 0
                    }
                    table.insert(waypoints, waypoint)
                    seenWaypoints[identifier] = true
                end
            end
        else
            break
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
function P.getdistancealongroute(detailed_route, currentLat, currentLon)
    local cumulativeDistance = 0
    local totalWaypoints = #detailed_route

    for i = 1, totalWaypoints - 1 do
        local wp1 = detailed_route[i]
        local wp2 = detailed_route[i + 1]
        local segmentDistance = wp1.distance_to_next

        local distFromAircraftToStart = P.getdistance(currentLat, currentLon, wp1.latitude, wp1.longitude)
        local distFromAircraftToEnd = P.getdistance(currentLat, currentLon, wp2.latitude, wp2.longitude)

        if math.abs(distFromAircraftToStart + distFromAircraftToEnd - segmentDistance) < 0.1 then
            cumulativeDistance = cumulativeDistance + distFromAircraftToStart
            return cumulativeDistance
        end

        cumulativeDistance = cumulativeDistance + segmentDistance
    end

    return cumulativeDistance
end

--------------------------------------------------------------------------------------------------------------
function P.getpointonroute(detailed_route, currentLat, currentLon, distanceInNM)
    local currentDistance = P.getdistancealongroute(detailed_route, currentLat, currentLon)
    local targetDistance = currentDistance + distanceInNM
    
    local cumulativeDistance = 0
    local totalWaypoints = #detailed_route
    
    if totalWaypoints < 2 then
        sasl.logInfo("Route has not enough waypoints")
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
function P.estimatefuelattod(currentLeftLbs, currentRightLbs, currentCenterLbs, distanceToTODNM)
    -- ANGENOMMENE WERTE
    local assumed_cruise_speed_knots = 450      -- Durchschnittliche Geschwindigkeit im Reiseflug (NM/h)
    local assumed_cruise_fuel_flow_lbs_hr = 5000 -- Treibstofffluss im Reiseflug (lbs/h)

    -- Geschätzter Treibstoffverbrauch von der aktuellen Position bis zum T/D
    local estimated_flight_time_hours = distanceToTODNM / assumed_cruise_speed_knots
    local estimated_fuel_burn_lbs = estimated_flight_time_hours * assumed_cruise_fuel_flow_lbs_hr
    
    -- Kopien der aktuellen Tankstände, um mit der Berechnung zu beginnen
    local remainingBurn = estimated_fuel_burn_lbs
    local finalLeftLbs = currentLeftLbs
    local finalRightLbs = currentRightLbs
    local finalCenterLbs = currentCenterLbs
    
    -- Verbrauchslogik simulieren (Center-Tank zuerst)
    if finalCenterLbs > 1000 and remainingBurn > 0 then
        local centerToBurn = finalCenterLbs - 1000
        
        if remainingBurn >= centerToBurn then
            -- Den gesamten verfügbaren Treibstoff aus dem Center-Tank verbrauchen
            finalCenterLbs = 1000
            remainingBurn = remainingBurn - centerToBurn
        else
            -- Nur den benötigten Treibstoff aus dem Center-Tank verbrauchen
            finalCenterLbs = finalCenterLbs - remainingBurn
            remainingBurn = 0
        end
    end
    
    -- Restlichen Verbrauch auf die Wing-Tanks aufteilen
    if remainingBurn > 0 then
        local wingBurn = remainingBurn / 2
        finalLeftLbs = finalLeftLbs - wingBurn
        finalRightLbs = finalRightLbs - wingBurn
    end
    
    -- Ergebnis-Tabelle mit den geschätzten finalen Tankinhalten
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
                    sasl.logInfo(" VOR SH LAT: " .. vor_lat .. " LON: " .. vor_lon .. " gefunden.")
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
function P.buildnavdatatable(navdatatable)

    local function search_for_dme(target_table, icao, navid, navtype)
        if not (icao and navid and navtype) then return nil end
        for i, entry in ipairs(target_table) do
            if (entry[def.DESTICAO] == icao and
                entry[def.DESTNAVID] == navid and
                entry[def.DESTNAVTYPE] == navtype) then
                return i
            end
        end
        return nil
    end

    for i = #navdatatable, 1, -1 do table.remove(navdatatable, i) end

    -- ... (Datei-Öffnen-Logik bleibt unverändert) ...
    local srcnavdatafile = io.open("Custom Data/earth_nav.dat", "r")
    if not srcnavdatafile then
        srcnavdatafile = io.open("Custom Scenery/Global Airports/Earth nav data/earth_nav.dat", "r")
        if not srcnavdatafile then
            srcnavdatafile = io.open("Resources/default data/earth_nav.dat", "r")
            if not srcnavdatafile then
                sasl.logError("No Navdatabase Source: Could not find earth_nav.dat!")
                return false
            else
                sasl.logInfo("Navdatabase Sourse: Resources/default data/earth_nav.dat")
            end
        else
            sasl.logInfo("Navdatabase Sourse: Custom Scenery/Global Airports/Earth nav data/earth_nav.dat")
        end
    else
        sasl.logInfo("Navdatabase Sourse: Custom Data/earth_nav.dat")
    end

    for i = 1, 3 do srcnavdatafile:read() end

    local navdatarecord = srcnavdatafile:read()
    while navdatarecord do
        if navdatarecord:sub(1, 2) == "99" then break end

        local navdataitems = {}
        for navdataitem in navdatarecord:gmatch("%S+") do table.insert(navdataitems, navdataitem) end

        if #navdataitems > def.SRCLONPOS then
            local lat_val = tonumber(navdataitems[def.SRCLATPOS])
            local lon_val = tonumber(navdataitems[def.SRCLONPOS])

            if lat_val and lon_val then
                local record_type_str = navdataitems[def.SRCTYPECODE]

                if (record_type_str == def.NAVDATARECTYPEILS) then
                    local newEntry = {}
                    newEntry[def.DESTICAO] = navdataitems[def.SRCICAO] -- S9
                    newEntry[def.DESTRWY] = navdataitems[def.SRCRWY] -- S11
                    newEntry[def.DESTNAVTYPE] = string.sub(navdataitems[def.SRCNAVTYPE], 1, 3) -- S12
                    newEntry[def.DESTNAVID] = navdataitems[def.SRCNAVID] -- S8
                    newEntry[def.DESTFREQ] = tonumber(navdataitems[def.SRCFREQ]) -- S5
                    newEntry[def.DESTLATPOS] = lat_val
                    newEntry[def.DESTLONPOS] = lon_val

                    local course_val_packed = tonumber(navdataitems[def.SRCCOURSE]) -- S7

                    if course_val_packed then
                        local magnetic_course = math.floor(course_val_packed / 360) 
                        newEntry[def.DESTCOURSE] = P.calccourse(magnetic_course)
                    else
                        newEntry[def.DESTCOURSE] = 0
                    end
                    newEntry[def.DESTNAVDME] = false
                    table.insert(navdatatable, newEntry)

                elseif (record_type_str == def.NAVDATARECTYPEVOR) then
                    local newEntry = {}
                    newEntry[def.DESTICAO] = navdataitems[def.SRCICAO]
                    newEntry[def.DESTRWY] = ""
                    newEntry[def.DESTNAVTYPE] = def.NAVTYPEVOR
                    newEntry[def.DESTNAVID] = navdataitems[def.SRCNAVID]
                    newEntry[def.DESTFREQ] = tonumber(navdataitems[def.SRCFREQ])
                    newEntry[def.DESTLATPOS] = lat_val
                    newEntry[def.DESTLONPOS] = lon_val
                    newEntry[def.DESTCOURSE] = 0
                    newEntry[def.DESTNAVDME] = false
                    table.insert(navdatatable, newEntry)

                elseif (record_type_str == def.NAVDATARECTYPEDME) then
                    local index = search_for_dme(navdatatable, navdataitems[def.SRCICAO], navdataitems[def.SRCNAVID], def.NAVTYPEILS)
                    if index then navdatatable[index][def.DESTNAVDME] = true end

                elseif (record_type_str == def.NAVDATARECTYPELPV or record_type_str == def.NAVDATARECTYPEGLS) then
                    local newEntry = {}
                    newEntry[def.DESTICAO] = navdataitems[def.SRCICAO] -- S9
                    newEntry[def.DESTRWY] = navdataitems[def.SRCRWY] -- S11
                    newEntry[def.DESTFREQ] = tonumber(navdataitems[def.SRCFREQ]) -- S5
                    newEntry[def.DESTLATPOS] = lat_val
                    newEntry[def.DESTLONPOS] = lon_val
                    newEntry[def.DESTNAVDME] = true

                    if record_type_str == def.NAVDATARECTYPELPV then
                        newEntry[def.DESTNAVTYPE] = def.NAVTYPELPV
                    else
                        newEntry[def.DESTNAVTYPE] = def.NAVTYPEGLS
                    end
                    newEntry[def.DESTNAVID] = navdataitems[def.SRCNAVID] -- S8
                    
                    local raw_course_str = navdataitems[def.SRCCOURSE] 
                    local true_course = tonumber(raw_course_str) -- S7

                    if true_course then
                        if true_course > 100000 then 
                            true_course = true_course % 10000 
                        end
                        
                        local mag_variation = sasl.getMagneticVariation(lat_val, lon_val)
                        if not mag_variation then mag_variation = 0 end
                        
                        local magnetic_course = true_course + mag_variation
                        
                        magnetic_course = P.calccourse(magnetic_course)
                        newEntry[def.DESTCOURSE] = magnetic_course
                        
                    else
                        sasl.logInfo("Could not read true course for LPV/GLS (Spalte 7/SRCCOURSE): " .. navdatarecord)
                        newEntry[def.DESTCOURSE] = 0 -- Fallback zu 0
                    end
                    
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
            local ilsCourse = lookupTable[key]
            
            if ilsCourse then
                value[def.DESTCOURSE] = ilsCourse
            end
        end
    end

    sasl.logInfo("Navdata Table created, " .. #navdatatable .. " entries.")
    return true
end
--------------------------------------------------------------------------------------------------------------
function P.writenavdatatable(navdatatable)

    destnavdatafile = io.open("Custom Data/yal_nav.dat", "w")

    if not destnavdatafile then
        sasl.logError("Could not open Custom Data/yal_nav.dat")
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
function P.buildairportdatatable(airport_db)
  
    local file = io.open("Resources/default data/earth_aptmeta.dat", "r")


    if not file then
        sasl.logError("Could not open Resources/default data/earth_aptmeta.dat")
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
    
    sasl.logInfo("Airport Data Table created, " .. line_count .. " entries.")

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
function P.getnavdataindex(navdatatable, icao, rwy, navtype)
    if not (P.isvalidicao(icao) and P.isvalidrwy(rwy)) then
        return nil
    end

    local rwy_offsets = {0, 1, -1, 2, -2, 3, -3}

    for _, offset in ipairs(rwy_offsets) do
        local current_rwy = P.adjustrwy(rwy, offset)
        if current_rwy then
            -- Durchlaufe die gesamte navdatatable
            for i, entry in ipairs(navdatatable) do
                -- Prüfe auf eine Übereinstimmung
                if (entry[def.DESTICAO] == icao and 
                    entry[def.DESTRWY] == current_rwy and 
                    entry[def.DESTNAVTYPE] == navtype) then
                    
                    return i -- Erfolg! Gib den numerischen Index zurück.
                end
            end
        end
    end
    
    return nil -- Nichts gefunden
end

--------------------------------------------------------------------------------------------------------------
function P.getrwyheadingfromnavdata(navdatatable, icao, rwy)

    if not (P.isvalidicao(icao) and P.isvalidrwy(rwy)) then
        return nil
    end

    local result = nil
    local navdatatableindex = P.getnavdataindex(navdatatable, icao, rwy, def.NAVTYPEILS)

    if (navdatatableindex ~= nil) then
        result = navdatatable[navdatatableindex][def.DESTCOURSE]
    else
        navdatatableindex = P.getnavdataindex(navdatatable, icao, rwy, def.NAVTYPEGLS)
        if (navdatatableindex ~= nil) then
            result = navdatatable[navdatatableindex][def.DESTCOURSE]
        else
            navdatatableindex = P.getnavdataindex(navdatatable, icao, rwy, def.NAVTYPELPV)
            if (navdatatableindex ~= nil) then
                result = navdatatable[navdatatableindex][def.DESTCOURSE]
            end
        end
    end

    return result

end 

return helpers