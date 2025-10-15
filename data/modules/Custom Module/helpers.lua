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
    float XPLMGetMagneticVariation(double, double);
    void XPLMWorldToLocal(double inLatitude, double inLongitude, double inAltitude, double *outX, double *outY, double *outZ);
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
    downloadResult, contents = sasl.net.downloadFileContentsSync(url)
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
function P.getmagneticvariation(lat_val, lon_val)

    local magenticvariation = xplm.XPLMGetMagneticVariation(lat_val, lon_val)

    return magenticvariation
end

--------------------------------------------------------------------------------------------------------------
function P.worldtolocal(lat_val, lon_val, alt_val)

    local out_x = ffi.new("double[1]")
    local out_y = ffi.new("double[1]")
    local out_z = ffi.new("double[1]")

    xplm.XPLMWorldToLocal(lat_val, lon_val, alt_val, out_x, out_y, out_z)

    local local_x = out_x[0]
    local local_y = out_y[0]
    local local_z = out_z[0]

    return local_x, local_y, local_z
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
function P.aircraftonrwy(aircraftlat, aircraftlon, rwystartlat, rwystartlon, rwyendlat, rwyendlon, dist)

    if (rwystartlat == 0) then
        return true
    end

    local rwystartlatrad = math.rad(rwystartlat)
    local rwystartlonrad = math.rad(rwystartlon)
    local rwyendlatrad = math.rad(rwyendlat)
    local rwyendlonrad = math.rad(rwyendlon)
    local aircraftlatrad = math.rad(aircraftlat)
    local aircraftlonrad = math.rad(aircraftlon)

    local v1 = (rwyendlonrad - rwystartlonrad) * math.cos(rwystartlatrad)
    local v2 = (rwyendlatrad - rwystartlatrad)
    local d1 = (aircraftlatrad - rwystartlatrad)
    local d2 = (aircraftlonrad - rwystartlonrad) * math.cos(rwystartlatrad)
    local s = d1 * v1 + d2 * v2

    local disttorwy = math.sqrt(math.abs(d1 ^ 2 + d2 ^ 2 - 2 * s))

    if (disttorwy < dist) then
        return true
    else
        return false
    end
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
               ( part == "SKC" or part == "CLR" or part == "NSC" or part == "NCD" ) or -- NCD hinzugefügt
               ( string.sub(part, 1, 1) == '/' and (string.find(part, "TCU$") or string.find(part, "CB$")) ) or
               ( string.sub(part, 1, 1) == '/' and (string.find(part, "FEW$") or string.find(part, "SCT$") or string.find(part, "BKN$") or string.find(part, "OVC$")) ) or
               ( (string.sub(part, 1, 3) == "FEW" or string.sub(part, 1, 3) == "SCT" or string.sub(part, 1, 3) == "BKN" or string.sub(part, 1, 3) == "OVC") and string.sub(part, -3) == "///" )
        then
            result.clouds = result.clouds or {}
            if (part == "SKC" or part == "CLR" or part == "NSC" or part == "NCD") then -- NCD hinzugefügt
                table.insert(result.clouds, { coverage = part, altitude = nil, type = "" })
                sasl.logDebug("Parsed cloud: " .. part)
                parsed = true
            elseif (string.sub(part, 1, 1) == '/') then
                -- ... (Logik für Wolken mit fehlenden Daten bleibt unverändert) ...
                parsed = true
            elseif (string.sub(part, -3) == "///") then
                -- ... (Logik für Wolken mit fehlender Höhe bleibt unverändert) ...
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

        -- ##### NEUER BLOCK ZUM ABFANGEN VON '//' #####
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
                    sasl.logDebug(string.format("Parsed temp/dew: %d°C/%d°C", temp_val, dew_val))
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
function P.getMetar(icaocode)
    local metarstring = nil
    local metarsource = "X-Plane"

    metarstring = sasl.weather.getMETARForAirport(icaocode)

    if (not metarstring or (metarstring == "") or (metarstring:sub(1, 4) ~= icaocode)) then
        sasl.logInfo("XPLM METAR for " .. icaocode .. " not found. Trying web download.")
        
        metarstring = nil 
        
        local metarUrl = def.AVWEATHERFURLCSV .. icaocode
        local tempFilePath = def.YALCACHEPATH .. icaocode .. "_metar.txt"

        sasl.logDebug("URL " .. metarUrl)
        sasl.logDebug("Path " .. tempFilePath)

        if sasl.net.downloadFileSync(metarUrl, tempFilePath) then
            local file = io.open(tempFilePath, "r")
            if file then
                metarstring = file:read("*a")
                file:close()
                metarsource = "Aviation Weather"
            else
                sasl.logError("Error: Could not open temp file for " .. icaocode)
            end
            os.remove(tempFilePath)
        else
            sasl.logError("Error: Download of METAR failed for " .. icaocode)
        end
    end

    if (metarstring ~= nil and metarstring ~= "") then
        sasl.logInfo("METAR for " .. icaocode .. " successfully loaded from " .. metarsource)
    else
        sasl.logInfo("METAR for " .. icaocode .. " could not be obtained.")
        metarstring = nil
    end

    return metarstring
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

    -- 3. Windkomponenten berechnen
    local headwindComponent, crosswindKnots = P.calculateWindComponents(windDirection, runwayHeading, windSpeed)

    sasl.logDebug(string.format("Calculated for RWY %s (Heading %d): Headwind %.1f kt, Crosswind %.1f kt (from Wind %d@%dkt)",
                                 runwayDesignator, runwayHeading, headwindComponent, crosswindKnots, windDirection, windSpeed))


    -- 4. Ueberpruefung der Schwellenwerte
    -- Rueckenwind (HeadwindComponent ist negativ bei Rueckenwind)
    if headwindComponent < -MAX_TAILWIND_KN then
        sasl.logDebug(string.format("Runway %s: Tailwnd (%.1f kt) exceeds max allowed (%.1f kt). Check recommended.", runwayDesignator, math.abs(headwindComponent), MAX_TAILWIND_KN))
        return false -- Rueckenwind zu stark
    end

    -- Seitenwind
    if crosswindKnots > MAX_CROSSWIND_KN then
        sasl.logDebug(string.format("Runway %s: Crosswind (%.1f kt) exceeds max allowed (%.1f kt). Check recommended.", runwayDesignator, crosswindKnots, MAX_CROSSWIND_KN))
        return false -- Seitenwind zu stark
    end

    sasl.logDebug(string.format("Runway %s is suitable based on current wind conditions.", runwayDesignator))
    return true -- Landebahn ist innerhalb der Schwellenwerte geeignet
end

--------------------------------------------------------------------------------------------------------------
function P.formatMetarSpeechSummary(metar)
    local parts = {}

    -- Extract necessary data from the metar table
    local icaocode = metar.icaocode
    local metar_data = metar.decodedmetar

    -- Add airport ICAO code to the beginning of the summary
    if icaocode and #icaocode > 0 then
        table.insert(parts, P.addspaces(icaocode))
    end

    -- Wind
    if metar_data.wind then
        local dir = metar_data.wind.direction
        local speed = metar_data.wind.speed
        local gust = metar_data.wind.gust

        local wind_part = ""
        if speed == 0 then -- Handle calm condition
            wind_part = "Wind calm"
        elseif dir == "VRB" then
            wind_part = "Wind variable at "
            wind_part = wind_part .. string.format("%d knots", speed)
            if gust and gust > 0 then
                wind_part = wind_part .. string.format(" gusting %d", gust)
            end
        else
            wind_part = string.format("Wind %d at ", dir)
            wind_part = wind_part .. string.format("%d knots", speed)
            if gust and gust > 0 then
                wind_part = wind_part .. string.format(" gusting %d", gust)
            end
        end
        table.insert(parts, wind_part)
    end

    -- Visibility
    if metar_data.visibility then
        local vis_val = metar_data.visibility.value
        local vis_part = "Visibility "
        if metar_data.cavok then -- Prioritize CAVOK if present
            vis_part = "Visibility 10 kilometers or more"
        elseif vis_val >= 10000 then
            vis_part = vis_part .. "10 kilometers or more"
        elseif vis_val >= 1609 then -- Convert to miles if close to a mile (1609m = 1 mile)
            vis_part = vis_part .. string.format("%d statute miles", math.floor(vis_val / 1609.34 + 0.5))
        elseif vis_val >= 1000 then -- Convert to kilometers if 1km or more
            vis_part = vis_part .. string.format("%d kilometers", math.floor(vis_val / 1000 + 0.5))
        else
            vis_part = vis_part .. string.format("%d meters", vis_val)
        end
        table.insert(parts, vis_part)
    end

    -- General Weather (simplified)
    if metar_data.weather and #metar_data.weather > 0 then
        local weather_desc = {}
        for _, wx_entry in ipairs(metar_data.weather) do
            local intensity = ""
            if wx_entry.intensity == "light" then intensity = "light "
            elseif wx_entry.intensity == "heavy" then intensity = "heavy " end
            -- Map common phenomena to more speech-friendly terms
            local phenomenon = wx_entry.phenomenon
            if phenomenon == "RA" then phenomenon = "rain"
            elseif phenomenon == "SN" then phenomenon = "snow"
            elseif phenomenon == "DZ" then phenomenon = "drizzle"
            elseif phenomenon == "FG" then phenomenon = "fog"
            elseif phenomenon == "BR" then phenomenon = "mist"
            elseif phenomenon == "HZ" then phenomenon = "haze"
            elseif phenomenon == "TS" then phenomenon = "thunderstorm"
            -- Add more mappings for other weather codes if necessary
            end
            table.insert(weather_desc, intensity .. phenomenon)
        end
        if #weather_desc > 0 then
            table.insert(parts, "Currently " .. table.concat(weather_desc, " and "))
        end
    end

    -- Clouds (simplified, only highest significant cloud layer or broken/overcast)
    if metar_data.clouds and #metar_data.clouds > 0 then
        local cloud_part = ""
        local significant_cloud = nil

        -- Find the lowest broken/overcast layer or highest significant cloud
        for _, cloud in ipairs(metar_data.clouds) do
            if cloud.coverage == "OVC" or cloud.coverage == "BKN" or cloud.coverage == "VV" then
                significant_cloud = cloud
                break -- Found a ceiling, which is usually the most important
            elseif (not significant_cloud and cloud.altitude) then
                -- If no ceiling found yet, keep track of the highest cloud for "scattered/few" case
                if not significant_cloud or cloud.altitude > significant_cloud.altitude then
                    significant_cloud = cloud
                end
            end
        end

        if metar_data.cavok then
            -- CAVOK implies "no significant clouds" and visibility >= 10km, handled by visibility
        elseif significant_cloud then
            local coverage_str = significant_cloud.coverage
            local altitude_ft = significant_cloud.altitude

            -- Expanded cloud coverage abbreviations for speech
            local readable_coverage = coverage_str
            if coverage_str == "FEW" then readable_coverage = "few"
            elseif coverage_str == "SCT" then readable_coverage = "scattered"
            elseif coverage_str == "BKN" then readable_coverage = "broken"
            elseif coverage_str == "OVC" then readable_coverage = "overcast"
            elseif coverage_str == "SKC" or coverage_str == "CLR" then readable_coverage = "sky clear"
            elseif coverage_str == "NSC" then readable_coverage = "no significant clouds"
            elseif coverage_str == "VV" then readable_coverage = "vertical visibility"
            end

            if readable_coverage == "sky clear" or readable_coverage == "no significant clouds" then
                cloud_part = readable_coverage
            elseif readable_coverage == "vertical visibility" then
                cloud_part = string.format("%s %d feet", readable_coverage, altitude_ft)
            else
                cloud_part = string.format("%s clouds at %d feet", readable_coverage, altitude_ft)
            end
            table.insert(parts, cloud_part)
        end
    end

    return table.concat(parts, ", ")
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

    local magnetic_variation = P.getmagneticvariation(latpos, lonpos)
    
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
        return 0, 0
    end

    local angleDifference = math.abs(windDirectionDegrees - runwayHeadingDegrees)
    if angleDifference > 180 then
        angleDifference = 360 - angleDifference
    end
    local angleRad = math.rad(angleDifference)

    local headwindComponent = math.cos(angleRad) * windSpeedKnots
    local crosswindComponent = math.abs(math.sin(angleRad) * windSpeedKnots)

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
    local TAKEOFF_WET_RUNWAY_PENALTY_FLAPS = 1

    if not (metar.decodedmetar and metar.decodedmetar.wind and metar.decodedmetar.wind.direction ~= nil and metar.decodedmetar.wind.speed ~= nil and
            metar.decodedmetar.temperature and metar.decodedmetar.temperature.value ~= nil and
            metar.decodedmetar.pressure and metar.decodedmetar.pressure.qnh_hpa ~= nil) then
        return STANDARD_TAKEOFF_FLAPS
    end

    local isRunwayWet = false
    if ((P.fieldexists(metar.decodedmetar, "weather") and ((P.containsvalue(metar.decodedmetar.weather, "FZRA")) or (P.containsvalue(metar.decodedmetar.weather, "FZDZ")) or (P.containsvalue(metar.decodedmetar.weather, "FZFG"))))
        or (P.fieldexists(metar.decodedmetar, "temperature.value") and (metar.decodedmetar.temperature.value < 1))) then
        isRunwayWet = true
    elseif (P.fieldexists(metar.decodedmetar, "weather") and (P.containsvalue(metar.decodedmetar.weather, "SN")))  then
        isRunwayWet = true
    elseif (P.fieldexists(metar.decodedmetar, "weather") and (P.containsvalue(metar.decodedmetar.weather, "RA"))) then
        isRunwayWet = true
    end 

    if not (type(totalweightkgs) == "number" and totalweightkgs > 0 and
            type(deprwylen) == "number" and deprwylen > 0 and
            type(elevation) == "number" and type(deprwyheading) == "number") then
        return STANDARD_TAKEOFF_FLAPS
    end

    local recommendedFlaps = STANDARD_TAKEOFF_FLAPS

    local headwindComponent, crosswindComponent = P.calculateWindComponents(
        metar.decodedmetar.wind.direction,
        deprwyheading,
        metar.decodedmetar.wind.speed
    )

    if totalweightkgs > TAKEOFF_WEIGHT_THRESHOLD_VERY_HIGH then
        recommendedFlaps = 15
    elseif totalweightkgs > TAKEOFF_WEIGHT_THRESHOLD_HIGH then
        recommendedFlaps = math.max(recommendedFlaps, 10)
    end

    if deprwylen < TAKEOFF_RUNWAY_LENGTH_VERY_SHORT_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 15)
    elseif deprwylen < TAKEOFF_RUNWAY_LENGTH_SHORT_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 10)
    end

    local deprwyalt = 0

    if (metar.metar and tonumber(metar.metar.elevation_m)) then
        deprwyalt = metar.metar.elevation_m
    else
        deprwyalt = elevation
    end

    local densityAltitude = P.calculateDensityAltitude(
        deprwyalt,
        metar.decodedmetar.temperature.value,
        metar.decodedmetar.pressure.qnh_hpa
    )
    if densityAltitude > TAKEOFF_DENSITY_ALTITUDE_THRESHOLD_HIGH then
        recommendedFlaps = math.max(recommendedFlaps, 10)
    end

    if headwindComponent < -TAKEOFF_TAILWIND_CONSIDERATION_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 10)
    end

    if isRunwayWet then
        if recommendedFlaps == 5 then
            recommendedFlaps = 10
        elseif recommendedFlaps == 10 then
            recommendedFlaps = 15
        end
    end

    if recommendedFlaps > 15 then
        recommendedFlaps = 15
    elseif recommendedFlaps < 5 then
        recommendedFlaps = 5
    end

    if recommendedFlaps > 5 and recommendedFlaps < 10 then
        recommendedFlaps = 10
    elseif recommendedFlaps > 10 and recommendedFlaps < 15 then
        recommendedFlaps = 15
    end

    return recommendedFlaps
end

--------------------------------------------------------------------------------------------------------------
function P.calcappflapsvref(totalweightkgs, desrwylen, desrwyheading, vref30, metar)

    local weatherData = metar.decodedmetar

    if not (weatherData and weatherData.wind and weatherData.wind.direction ~= nil and weatherData.wind.speed ~= nil and
            weatherData.temperature and weatherData.temperature.value ~= nil and
            weatherData.pressure and weatherData.pressure.qnh_hpa ~= nil) then
        return 30, vref30
    end

    if not (type(totalweightkgs) == "number" and totalweightkgs > 0 and
            type(desrwylen) == "number" and desrwylen > 0 and
            type(desrwyheading) == "number") and 
            type(vref30) == "number" and vref30 > 0 then
        return 30, vref30
    end

    local headwindComponent, crosswindKnots = P.calculateWindComponents(
        weatherData.wind.direction,
        desrwyheading,
        weatherData.wind.speed
    )

    local isBadWeather = false


    if weatherData.weather then
        for _, wx_entry in ipairs(weatherData.weather) do
            if wx_entry.phenomenon == "RA" or wx_entry.phenomenon == "SN" then
                isBadWeather = true
                break 
            end
        end
    end

    if weatherData.visibility and weatherData.visibility.value and (weatherData.visibility.value < 5000) then
        isBadWeather = true
    end
    if weatherData.clouds and weatherData.clouds[1] and weatherData.clouds[1].altitude and (weatherData.clouds[1].altitude < 1000) then
        isBadWeather = true
    end

    local flapsSetting = P.determineLandingFlapsSetting(desrwylen, weatherData.wind.speed, crosswindKnots, isBadWeather, totalweightkgs)
    local vrefKnots = P.calculateVref(totalweightkgs, flapsSetting, weatherData, crosswindKnots)

    flapsSetting = math.floor(flapsSetting + 0.5)
    vrefKnots = math.floor(vrefKnots + 0.5)

    return flapsSetting, vrefKnots
end

--------------------------------------------------------------------------------------------------------------
function P.determineLandingFlapsSetting(runwayLengthMeters, windSpeedKnots, crosswindKnots, isBadWeather, weightKg)
    local LANDING_SHORT_RUNWAY_THRESHOLD = 2000
    local LANDING_HIGH_WIND_THRESHOLD = 20
    local LANDING_HIGH_CROSSWIND_THRESHOLD = 15
    local LANDING_HIGH_WEIGHT_THRESHOLD = 55000

    if runwayLengthMeters < LANDING_SHORT_RUNWAY_THRESHOLD or
       windSpeedKnots > LANDING_HIGH_WIND_THRESHOLD or
       crosswindKnots > LANDING_HIGH_CROSSWIND_THRESHOLD or
       isBadWeather or
       weightKg > LANDING_HIGH_WEIGHT_THRESHOLD then
        return 40
    else
        return 30
    end
end

--------------------------------------------------------------------------------------------------------------
function P.calculateVref(weightKg, flapsSetting, weatherData, crosswindKnots)
    local VREF_STALL_SPEED_FACTOR = 1.37
    local VREF_WIND_ADDITION = 5
    local VREF_PRECIPITATION_ADDITION = 5
    local VREF_CROSSWIND_ADDITION = 5
    local LANDING_HIGH_WIND_THRESHOLD_FOR_VREF = 20

    local stallSpeedKnots = P.calculateStallSpeed(weightKg, weatherData, flapsSetting)
    local vrefKnots = stallSpeedKnots * VREF_STALL_SPEED_FACTOR

    if weatherData.wind and weatherData.wind.speed and weatherData.wind.speed > LANDING_HIGH_WIND_THRESHOLD_FOR_VREF then
        vrefKnots = vrefKnots + VREF_WIND_ADDITION
    end

    local hasPrecipitation = false
    if weatherData.weather then
        for _, wx_entry in ipairs(weatherData.weather) do
            if wx_entry.phenomenon == "RA" or wx_entry.phenomenon == "SN" then
                hasPrecipitation = true
                break
            end
        end
    end

    if hasPrecipitation then
        vrefKnots = vrefKnots + VREF_PRECIPITATION_ADDITION
    end

    if crosswindKnots > VREF_CROSSWIND_ADDITION then
        vrefKnots = vrefKnots + VREF_CROSSWIND_ADDITION
    end

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

            local mag_var = P.getmagneticvariation(wp1.latitude, wp1.longitude)
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
    -- Hilfsfunktion, die nur innerhalb dieser Funktion benötigt wird
    local function search_for_dme(target_table, icao, navid, navtype)
        if not (icao and navid and navtype) then return nil end
        for i, entry in ipairs(target_table) do
            if (entry[def.DESTICAO] == icao and 
                entry[def.DESTNAVID] == navid and 
                entry[def.DESTNAVTYPE] == navtype) then
                return i -- Gib den numerischen Index zurück
            end
        end
        return nil
    end

    -- Tabelle leeren für einen sauberen Neuaufbau
    for i = #navdatatable, 1, -1 do table.remove(navdatatable, i) end

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
                    newEntry[def.DESTICAO] = navdataitems[def.SRCICAO]
                    newEntry[def.DESTRWY] = navdataitems[def.SRCRWY]
                    newEntry[def.DESTNAVTYPE] = string.sub(navdataitems[def.SRCNAVTYPE], 1, 3)
                    newEntry[def.DESTNAVID] = navdataitems[def.SRCNAVID]
                    newEntry[def.DESTFREQ] = tonumber(navdataitems[def.SRCFREQ])
                    newEntry[def.DESTLATPOS] = lat_val
                    newEntry[def.DESTLONPOS] = lon_val
                    local course_val = tonumber(navdataitems[def.SRCCOURSE])
                    if course_val then
                        local mag_var = P.getmagneticvariation(lat_val, lon_val)
                        newEntry[def.DESTCOURSE] = P.calccourse((course_val + mag_var + 360) % 360)
                    else
                        newEntry[def.DESTCOURSE] = 0
                    end
                    newEntry[def.DESTNAVDME] = false
                    table.insert(navdatatable, newEntry)

                elseif (record_type_str == def.NAVDATARECTYPEVOR) then
                    local newEntry = {}
                    newEntry[def.DESTICAO] = navdataitems[def.SRCICAO]
                    newEntry[def.DESTRWY] = "" -- VOR hat keine RWY
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

                elseif ((record_type_str == def.NAVDATARECTYPELPV) or (record_type_str == def.NAVDATARECTYPEGLS)) then
                    local newEntry = {}
                    if record_type_str == def.NAVDATARECTYPELPV then
                        newEntry[def.DESTNAVID] = navdataitems[def.SRCNAVTYPE]
                        newEntry[def.DESTNAVTYPE] = def.NAVTYPELPV
                    else
                        newEntry[def.DESTNAVID] = navdataitems[def.SRCNAVID]
                        newEntry[def.DESTNAVTYPE] = def.NAVTYPEGLS
                    end
                    newEntry[def.DESTICAO] = navdataitems[def.SRCICAO]
                    newEntry[def.DESTRWY] = navdataitems[def.SRCRWY]
                    newEntry[def.DESTFREQ] = tonumber(navdataitems[def.SRCFREQ])
                    newEntry[def.DESTLATPOS] = lat_val
                    newEntry[def.DESTLONPOS] = lon_val
                    
                    -- Deine extra Logik für den Kurs-String
                    local raw_course_data_string = navdataitems[def.SRCCOURSE]
                    local extracted_course_string = raw_course_data_string
                    if #raw_course_data_string > 3 and tonumber(raw_course_data_string:sub(1,3)) ~= nil then
                        extracted_course_string = raw_course_data_string:sub(4)
                    end
                    if #extracted_course_string >= 4 and extracted_course_string:sub(1,3) == "CRS" then
                        extracted_course_string = string.sub(extracted_course_string, 4, -1)
                    end
                    local course_val_lpv_gls = tonumber(extracted_course_string)
                    
                    if course_val_lpv_gls then
                        local mag_var = P.getmagneticvariation(lat_val, lon_val)
                        newEntry[def.DESTCOURSE] = P.calccourse((course_val_lpv_gls + mag_var + 360) % 360)
                    else
                        newEntry[def.DESTCOURSE] = 0
                    end
                    newEntry[def.DESTNAVDME] = true
                    table.insert(navdatatable, newEntry)
                end
            end
        end
        navdatarecord = srcnavdatafile:read()
    end
    srcnavdatafile:close()
    
    -- Post-processing (angepasst für numerische Indizes)
    local lookupTable = {}
    for i, entry in ipairs(navdatatable) do
        if entry[def.DESTNAVTYPE] == def.NAVTYPEILS then
            lookupTable[entry[def.DESTICAO] .. entry[def.DESTRWY]] = i
        end
    end

    for i, value in ipairs(navdatatable) do
        if (value[def.DESTNAVTYPE] == def.NAVTYPEGLS or value[def.DESTNAVTYPE] == def.NAVTYPELPV) then
            local ilsIndex = lookupTable[value[def.DESTICAO] .. value[def.DESTRWY]]
            if ilsIndex and navdatatable[ilsIndex] then
                value[def.DESTCOURSE] = navdatatable[ilsIndex][def.DESTCOURSE]
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