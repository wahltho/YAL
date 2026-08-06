local M = {}

M.CRUISE_REPORT_INTERVAL_SEC = 600
M.CRUISE_LEVEL_MAX_VS_FPM = 300

M.EVENT_TTL_SEC = {
    ["departure.flightplan_active"] = 120,
    ["departure.start_push"] = 60,
    ["departure.taxi_runway"] = 120,
    ["departure.runway_crossing"] = 60,
    ["departure.hold_short"] = 120,
    ["departure.backtrack"] = 90,
    ["departure.intersection"] = 60,
    ["departure.lining_up"] = 60,
    ["departure.lineup_takeoff"] = 45,
    ["departure.airborne"] = 60,
    ["departure.on_climb"] = 120,
    ["enroute.in_cruise"] = 120,
    ["enroute.hold_enter"] = 120,
    ["enroute.holding"] = 120,
    ["enroute.hold_descending"] = 120,
    ["enroute.hold_exit"] = 120,
    ["arrival.top_of_descent"] = 120,
    ["arrival.on_descent"] = 120,
    ["arrival.approach"] = 180,
    ["arrival.on_final"] = 60,
    ["arrival.short_final"] = 45,
    ["arrival.backtrack"] = 120,
    ["arrival.runway_vacated"] = 120,
    ["arrival.runway_crossing"] = 60,
    ["arrival.parking_position"] = 120
}

M.RESULT_NAMES = {
    [10] = "ACCEPTED",
    [20] = "PREVIEW_READY",
    [21] = "SUBMITTED_VISIBLE",
    [30] = "REJECTED_TEXT",
    [31] = "REJECTED_POLICY",
    [32] = "REJECTED_CONTEXT",
    [40] = "FAILED_BEFORE_SUBMIT",
    [41] = "UNCERTAIN_AFTER_SUBMIT",
    [42] = "CANCELLED"
}

M.VOICE_RESULT_NAMES = {
    [1] = "NOT_REQUESTED",
    [10] = "ACCEPTED",
    [20] = "TRANSMITTED",
    [30] = "REJECTED_TEXT",
    [31] = "DISABLED",
    [32] = "REJECTED_CONTEXT",
    [40] = "FAILED_BEFORE_PTT",
    [41] = "UNCERTAIN_AFTER_PTT",
    [42] = "CANCELLED"
}

local TERMINAL_RESULTS = {
    [20] = true,
    [21] = true,
    [30] = true,
    [31] = true,
    [32] = true,
    [40] = true,
    [41] = true,
    [42] = true
}

local TERMINAL_VOICE_RESULTS = {
    [20] = true,
    [30] = true,
    [31] = true,
    [32] = true,
    [40] = true,
    [41] = true,
    [42] = true
}

local DESCENT_PROGRESS_PREFIX = "arrival.descent_level_"
local CLIMB_PROGRESS_PREFIX = "departure.climb_level_"
local PROGRESS_LEVEL_BOUNDARY_GUARD_FT = 5000
local OFP_STATION_NAME_MAX_LENGTH = 24
local OFP_AIRPORT_DESCRIPTORS = {
    AERODROME = true,
    AIRPORT = true,
    INTERNATIONAL = true,
    INTL = true,
    MUNICIPAL = true,
    REGIONAL = true
}
local HOLD_ENTER_EVENT_ID = "enroute.hold_enter"
local HOLDING_EVENT_ID = "enroute.holding"
local HOLD_DESCENDING_EVENT_ID = "enroute.hold_descending"
local HOLD_EXIT_EVENT_ID = "enroute.hold_exit"
local HOLD_TARGET_TOLERANCE_FT = 100
local HOLD_MAINTAINING_MAX_VS_FPM = 150

local function is_climb_progress_event(eventId)
    return type(eventId) == "string"
        and eventId:sub(1, #CLIMB_PROGRESS_PREFIX) == CLIMB_PROGRESS_PREFIX
end

local function is_descent_progress_event(eventId)
    return type(eventId) == "string"
        and eventId:sub(1, #DESCENT_PROGRESS_PREFIX) == DESCENT_PROGRESS_PREFIX
end

function M.shouldSuppressProgressLevel(levelFt, boundaryAltitudeFt)
    local level = tonumber(levelFt)
    local boundary = tonumber(boundaryAltitudeFt)
    if not level or not boundary or level <= 0 or boundary <= 0 then return false end
    local distance = boundary - level
    return distance >= 0 and distance < PROGRESS_LEVEL_BOUNDARY_GUARD_FT
end

function M.isCruiseReportDue(lastReportAt, now, intervalSec)
    local current = tonumber(now)
    if not current then return false end

    local previous = tonumber(lastReportAt)
    if not previous then return true end

    local interval = tonumber(intervalSec) or M.CRUISE_REPORT_INTERVAL_SEC
    if interval < 0 then interval = M.CRUISE_REPORT_INTERVAL_SEC end
    return current - previous >= interval
end

function M.isCruiseLevelStable(verticalSpeedFpm)
    local verticalSpeed = tonumber(verticalSpeedFpm)
    if not verticalSpeed then return true end
    return math.abs(verticalSpeed) <= M.CRUISE_LEVEL_MAX_VS_FPM
end

function M.isHoldLevelStable(altitudeFt, verticalSpeedFpm, targetAltitudeFt)
    local target = tonumber(targetAltitudeFt)
    if not target or target <= 0 then return true end

    local altitude = tonumber(altitudeFt)
    local verticalSpeed = tonumber(verticalSpeedFpm)
    if not altitude or not verticalSpeed then return false end

    return math.abs(altitude - target) <= HOLD_TARGET_TOLERANCE_FT
        and math.abs(verticalSpeed) <= HOLD_MAINTAINING_MAX_VS_FPM
end

local function is_approach_phase(phase)
    return phase == 6 or phase == 7
end

local function round(value)
    value = tonumber(value)
    if not value then return nil end
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function clean_token(value, allowSpace)
    local text = trim(value):upper()
    if text == "" or text == "------" then return nil end
    local pattern = allowSpace and "[^A-Z0-9%- ]" or "[^A-Z0-9%-]"
    text = text:gsub(pattern, "")
    text = text:gsub("%s+", " ")
    if text == "" then return nil end
    return text
end

local function normalize_runway(value)
    local runway = clean_token(value, false)
    if not runway then return nil end
    runway = runway:gsub("^RW", "")
    if runway:match("^%d%d?T$") then
        runway = runway:sub(1, -2)
    end
    if not runway:match("^%d%d?[LRC]?$") then return nil end
    local number = tonumber(runway:match("^(%d%d?)"))
    if not number or number < 1 or number > 36 then return nil end
    return string.format("%02d", number) .. (runway:match("[LRC]$") or "")
end

local function normalize_text(value)
    local text = tostring(value or ""):gsub("%s+", " ")
    text = trim(text)
    if text == "" or #text > 254 or text:sub(1, 1) == "." then return nil end
    for i = 1, #text do
        local byte = text:byte(i)
        if byte < 32 or byte > 126 then return nil end
    end
    return text
end

local function normalize_voice_text(value)
    local text = tostring(value or ""):gsub("%s+", " ")
    text = trim(text)
    if text == "" or #text > 1024 then return nil end
    for i = 1, #text do
        local byte = text:byte(i)
        if byte < 32 or byte > 126 then return nil end
    end
    return text
end

local function is_ascii_alphanumeric_char(char)
    if not char or char == "" then return false end
    local byte = char:byte(1)
    return (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
end

local function replace_token(text, token, replacement)
    token = tostring(token or "")
    replacement = tostring(replacement or "")
    if token == "" or replacement == "" or token == replacement then return text end

    local output = {}
    local cursor = 1
    while cursor <= #text do
        local startPos, endPos = text:find(token, cursor, true)
        if not startPos then
            output[#output + 1] = text:sub(cursor)
            break
        end
        local before = startPos > 1 and text:sub(startPos - 1, startPos - 1) or nil
        local after = endPos < #text and text:sub(endPos + 1, endPos + 1) or nil
        if not is_ascii_alphanumeric_char(before) and not is_ascii_alphanumeric_char(after) then
            output[#output + 1] = text:sub(cursor, startPos - 1)
            output[#output + 1] = replacement
            cursor = endPos + 1
        else
            output[#output + 1] = text:sub(cursor, endPos)
            cursor = endPos + 1
        end
    end
    return table.concat(output)
end

local function spaced_digits(value)
    local digits = tostring(value or "")
    local parts = {}
    for index = 1, #digits do
        local char = digits:sub(index, index)
        if char:match("%d") then parts[#parts + 1] = char end
    end
    return table.concat(parts, " ")
end

local AVIATION_DIGITS = {
    ["0"] = "zero",
    ["1"] = "one",
    ["2"] = "two",
    ["3"] = "tree",
    ["4"] = "fower",
    ["5"] = "fife",
    ["6"] = "six",
    ["7"] = "seven",
    ["8"] = "eight",
    ["9"] = "niner"
}

local COORDINATE_DIGITS = {
    ["0"] = "zero",
    ["1"] = "one",
    ["2"] = "two",
    ["3"] = "tree",
    ["4"] = "four",
    ["5"] = "fife",
    ["6"] = "six",
    ["7"] = "seven",
    ["8"] = "eight",
    ["9"] = "niner"
}

local function title_identifier_word(value)
    local text = tostring(value or ""):lower()
    if text == "" then return "" end
    return text:sub(1, 1):upper() .. text:sub(2)
end

local function voice_coordinate_identifier(token)
    local latitude, northSouth, longitude, eastWest = token:match("^(%d%d?)([NS])(%d%d?%d?)([EW])$")
    if not latitude or tonumber(latitude) > 90 or tonumber(longitude) > 180 then return nil end
    local parts = {}
    for index = 1, #latitude do
        parts[#parts + 1] = COORDINATE_DIGITS[latitude:sub(index, index)]
    end
    parts[#parts + 1] = northSouth == "N" and "north" or "south"
    for index = 1, #longitude do
        parts[#parts + 1] = COORDINATE_DIGITS[longitude:sub(index, index)]
    end
    parts[#parts + 1] = eastWest == "E" and "east" or "west"
    return table.concat(parts, " ")
end

local NAV_NAME_SUFFIXES = { " VOR/DME", " VOR DME", " TACAN", " DME", " VOR", " NDB" }

local function voice_navigation_name(value)
    local text = tostring(value or "")
    local nullIndex = text:find("\0", 1, true)
    if nullIndex then text = text:sub(1, nullIndex - 1) end
    text = trim(text):upper()
    for _, suffix in ipairs(NAV_NAME_SUFFIXES) do
        if #text > #suffix and text:sub(-#suffix) == suffix then
            text = trim(text:sub(1, #text - #suffix))
            break
        end
    end
    if text == "" or #text > 48 then return nil end
    for index = 1, #text do
        local byte = text:byte(index)
        local valid = (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or byte == 32 or byte == 39 or byte == 45
        if not valid then return nil end
    end
    local words = {}
    for word in text:gmatch("%S+") do
        words[#words + 1] = title_identifier_word(word)
    end
    return #words > 0 and table.concat(words, " ") or nil
end

local function voice_named_identifier(value, spellNato, resolvedNavName)
    local token = clean_token(value, false)
    if not token then return nil end
    local coordinate = voice_coordinate_identifier(token)
    if coordinate then return coordinate end

    local navName = voice_navigation_name(resolvedNavName)
    if navName then
        local _, digits, suffix = token:match("^([A-Z]+)(%d+)([A-Z]*)$")
        if digits then
            local parts = { navName, spaced_digits(digits) }
            if suffix ~= "" then parts[#parts + 1] = spellNato(suffix) end
            return table.concat(parts, " ")
        end
        return navName
    end
    if token:match("^[A-Z][A-Z][A-Z][A-Z][A-Z]$") then
        return title_identifier_word(token)
    end

    local letters, digits, suffix = token:match("^([A-Z]+)(%d+)([A-Z]*)$")
    if letters and digits then
        local spokenLetters = #letters == 5 and title_identifier_word(letters) or spellNato(letters)
        local parts = { spokenLetters, spaced_digits(digits) }
        if suffix ~= "" then parts[#parts + 1] = spellNato(suffix) end
        return table.concat(parts, " ")
    end
    return spellNato(token)
end

local function clean_callsign(value)
    local token = tostring(value or "")
    local nullIndex = token:find("\0", 1, true)
    if nullIndex then token = token:sub(1, nullIndex - 1) end
    token = trim(token):upper()
    if #token < 2 or #token > 7 or token:find("[^A-Z0-9]") then return nil end
    return token
end

local function text_callsign(snapshot)
    local callsign = clean_callsign(snapshot and snapshot.effective_callsign)
    if not callsign then return nil end
    if callsign:sub(1, 3) == "DLH" and #callsign > 3 then
        return "Lufthansa " .. callsign:sub(4), callsign
    end
    return callsign, callsign
end

local function voice_callsign(snapshot, spellNato)
    local callsign = clean_callsign(snapshot and snapshot.effective_callsign)
    if not callsign then return nil end
    local startIndex = 1
    local parts = {}
    if callsign:sub(1, 3) == "DLH" and #callsign > 3 then
        parts[#parts + 1] = "Lufthansa"
        startIndex = 4
    end
    for index = startIndex, #callsign do
        local char = callsign:sub(index, index)
        parts[#parts + 1] = AVIATION_DIGITS[char] or spellNato(char)
    end
    return table.concat(parts, " ")
end

local function dotted_initial_count(token)
    local count = 0
    local index = 1
    while index <= #token do
        local byte = token:byte(index)
        if not byte or byte < 65 or byte > 90 or token:sub(index + 1, index + 1) ~= "." then
            return nil
        end
        count = count + 1
        index = index + 2
    end
    return count
end

local function strip_leading_dotted_initials(text)
    local position = 1
    local initialCount = 0
    local remainderStart = 1

    while position <= #text do
        while text:sub(position, position) == " " do position = position + 1 end
        local tokenStart = position
        while position <= #text and text:sub(position, position) ~= " " do
            position = position + 1
        end
        local count = dotted_initial_count(text:sub(tokenStart, position - 1))
        if not count then break end
        initialCount = initialCount + count
        while text:sub(position, position) == " " do position = position + 1 end
        remainderStart = position
    end

    if initialCount < 2 or remainderStart > #text then return text end
    local remainder = text:sub(remainderStart)
    local letterCount = 0
    for index = 1, #remainder do
        local byte = remainder:byte(index)
        if byte and byte >= 65 and byte <= 90 then letterCount = letterCount + 1 end
    end
    if letterCount < 3 then return text end
    return remainder
end

local function clean_station_name(value)
    local text = trim(value):gsub("%s+", " ")
    if text == "" or #text > 64 or text:sub(1, 1) == "." then return nil end
    for index = 1, #text do
        local byte = text:byte(index)
        if byte < 32 or byte > 126 then return nil end
    end
    return strip_leading_dotted_initials(text:upper())
end

local function clean_ofp_station_name(value)
    local text = trim(value)
    local slash = text:find("/", 1, true)
    if slash then text = trim(text:sub(1, slash - 1)) end
    local station = clean_station_name(text)
    if not station or #station > OFP_STATION_NAME_MAX_LENGTH then return nil end
    local finalWord = station:match("([^ ]+)$") or ""
    local descriptor = finalWord:gsub("[^A-Z]", "")
    if OFP_AIRPORT_DESCRIPTORS[descriptor] then return nil end
    return station
end

local function voice_station_name(value)
    local station = clean_station_name(value)
    if not station then return nil end
    local spoken = station:lower():gsub("(%a)([%a]*)", function(first, rest)
        return first:upper() .. rest
    end)
    return spoken:gsub("'S(%f[^%a])", "'s")
end

local function voice_runway(value)
    local runway = normalize_runway(value)
    if not runway then return nil end
    local digits = runway:match("^(%d%d)")
    local suffix = runway:match("([LRC])$")
    local suffixNames = { L = "Left", R = "Right", C = "Center" }
    local text = spaced_digits(digits)
    if suffix then text = text .. " " .. suffixNames[suffix] end
    return text
end

local function add_voice_token(replacements, raw, spoken)
    raw = tostring(raw or "")
    spoken = tostring(spoken or "")
    if raw ~= "" and spoken ~= "" and raw ~= spoken then
        replacements[#replacements + 1] = { raw = raw, spoken = spoken }
    end
end

local function is_ascii_alphanumeric(byte)
    return byte and ((byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122))
end

local function sanitize_parking_name(value)
    local raw = tostring(value or "")
    local result = {}
    for index = 1, #raw do
        local byte = raw:byte(index)
        local previousByte = index > 1 and raw:byte(index - 1) or nil
        local nextByte = index < #raw and raw:byte(index + 1) or nil

        if byte == 44 or byte == 58 or byte == 59
            or byte == 40 or byte == 91 or byte == 123 then
            break
        elseif byte == 45 then
            if is_ascii_alphanumeric(previousByte) and is_ascii_alphanumeric(nextByte) then
                -- A-12 is a single stand identifier; normalize it to A12.
            else
                break
            end
        elseif byte == 47 then
            if not (is_ascii_alphanumeric(previousByte) and is_ascii_alphanumeric(nextByte)) then
                break
            end
            if #result > 0 and result[#result] ~= " " then
                result[#result + 1] = " "
            end
        elseif is_ascii_alphanumeric(byte) then
            if byte >= 97 and byte <= 122 then byte = byte - 32 end
            result[#result + 1] = string.char(byte)
        elseif #result > 0 and result[#result] ~= " " then
            result[#result + 1] = " "
        end
    end
    if result[#result] == " " then result[#result] = nil end
    if #result == 0 then return nil end
    return table.concat(result)
end

local PARKING_IDENTIFIER_MARKER = {
    GATE = true,
    GATES = true,
    STAND = true,
    STANDS = true,
    PARKING = true,
    PARK = true,
    RAMP = true,
    APRON = true
}

local function token_has_digit(token)
    for index = 1, #token do
        local byte = token:byte(index)
        if byte >= 48 and byte <= 57 then return true end
    end
    return false
end

local function token_has_letter(token)
    for index = 1, #token do
        local byte = token:byte(index)
        if byte >= 65 and byte <= 90 then return true end
    end
    return false
end

local function is_short_letter_token(token)
    if type(token) ~= "string" or #token < 1 or #token > 2 then return false end
    for index = 1, #token do
        local byte = token:byte(index)
        if byte < 65 or byte > 90 then return false end
    end
    return true
end

local function extract_parking_identifier(name)
    local tokens = {}
    local cargo = false
    for token in name:gmatch("%S+") do
        tokens[#tokens + 1] = token
        if token == "CARGO" then cargo = true end
    end

    local bestIdentifier = nil
    local bestScore = -1
    for index, token in ipairs(tokens) do
        if token_has_digit(token) then
            local identifier = token
            local score = token_has_letter(token) and 40 or 20
            local markerIndex = index - 1

            if not token_has_letter(token) and is_short_letter_token(tokens[index - 1])
                and not PARKING_IDENTIFIER_MARKER[tokens[index - 1]] then
                identifier = tokens[index - 1] .. identifier
                markerIndex = index - 2
                score = 40
            end
            if is_short_letter_token(tokens[index + 1])
                and not PARKING_IDENTIFIER_MARKER[tokens[index + 1]] then
                identifier = identifier .. tokens[index + 1]
                score = 40
            end
            if PARKING_IDENTIFIER_MARKER[tokens[markerIndex]] then
                score = score + 10
            end

            if #identifier <= 12 and score > bestScore then
                bestIdentifier = identifier
                bestScore = score
            end
        end
    end

    if not bestIdentifier then
        for index, token in ipairs(tokens) do
            if PARKING_IDENTIFIER_MARKER[token] and is_short_letter_token(tokens[index + 1]) then
                bestIdentifier = tokens[index + 1]
                break
            end
        end
    end
    if not bestIdentifier then return nil end
    if cargo then return "CARGO " .. bestIdentifier end
    return bestIdentifier
end

local function parking_label(snapshot, prefix)
    if snapshot[prefix .. "_found"] ~= true then return nil end
    local rampType = tostring(snapshot[prefix .. "_type"] or ""):lower()

    local name = sanitize_parking_name(snapshot[prefix .. "_name"])
    if not name then return nil end
    local identifier = extract_parking_identifier(name)
    if not identifier then return nil end
    return (rampType == "gate" and "gate " or "stand ") .. identifier
end

M.normalizeText = normalize_text
M.normalizeVoiceText = normalize_voice_text
M.normalizeRunway = normalize_runway

local function airport_label(snapshot, icaoField, stationField)
    local icao = clean_token(snapshot[icaoField], false)
    if not icao or #icao ~= 4 or icao:find("-", 1, true) then return nil end

    if snapshot.ofp_valid == true or tonumber(snapshot.ofp_valid) == 1 then
        local originIcao = clean_token(snapshot.ofp_origin_icao, false)
        local destinationIcao = clean_token(snapshot.ofp_destination_icao, false)
        if originIcao == icao then
            local originName = clean_ofp_station_name(snapshot.ofp_origin_name)
            if originName then return originName, icao, "ofp" end
        end
        if destinationIcao == icao then
            local destinationName = clean_ofp_station_name(snapshot.ofp_destination_name)
            if destinationName then return destinationName, icao, "ofp" end
        end
    end

    local stationIcaoField = stationField:gsub("_name$", "_icao")
    local stationIcao = clean_token(snapshot[stationIcaoField], false)
    local station = stationIcao == icao and clean_station_name(snapshot[stationField]) or nil
    return station or icao, icao, station and "refdata" or "icao"
end

M.resolveAirportLabel = airport_label

local function format_altitude(snapshot, descent)
    local indicated = tonumber(snapshot.altitude_ft)
    local pressure = tonumber(snapshot.pressure_altitude_ft) or indicated
    if not indicated or not pressure then return nil end

    local transition = tonumber(descent and snapshot.transition_level_ft or snapshot.transition_altitude_ft) or 0
    if transition > 0 and indicated >= transition then
        return "FL" .. tostring(round(pressure / 100))
    end
    return tostring(round(indicated / 100) * 100) .. "ft"
end

local function format_planned_altitude(snapshot)
    local planned = tonumber(snapshot.planned_altitude_ft)
    if not planned or planned <= 0 then return nil end
    local transition = tonumber(snapshot.transition_altitude_ft) or 0
    if transition > 0 and planned >= transition then
        return "FL" .. tostring(round(planned / 100))
    end
    return tostring(round(planned / 100) * 100) .. "ft"
end

local function format_hold_target_altitude(snapshot)
    local target = tonumber(snapshot.hold_target_altitude_ft)
    if not target or target <= 0 then return nil end
    local transition = tonumber(snapshot.transition_level_ft) or 0
    if transition <= 0 then
        transition = tonumber(snapshot.transition_altitude_ft) or 0
    end
    if transition > 0 and target >= transition then
        return "FL" .. tostring(round(target / 100))
    end
    return tostring(round(target / 100) * 100) .. "ft"
end

local function approach_label(snapshot)
    local family = clean_token(snapshot.approach_procedure_type, false)
    local resolved = clean_token(snapshot.approach_resolved_kind, false)
    local suffix = clean_token(snapshot.approach_suffix, false)

    if not family then
        local raw = clean_token(snapshot.approach_id, false)
        if raw then
            if raw:sub(1, 3) == "LDA" then
                family = "LDA"
            else
                local map = { I = "ILS", G = "GLS", L = "LPV", R = "RNAV" }
                family = map[raw:sub(1, 1)]
            end
        end
    end

    if family == "ILS" and (resolved == "LOC" or resolved == "LOC-GS" or resolved == "LOC_GS" or resolved == "LOCGS") then
        family = "LOC"
    elseif family == "RNAV" and resolved == "LP" then
        family = "LP"
    elseif family == "RNAV" and resolved == "LPV" then
        family = "LPV"
    end

    if not family then return nil end
    if suffix then return family .. " " .. suffix end
    return family
end

M.approachLabel = approach_label

local MESSAGE_CONTRACTS = {
    ["departure.flightplan_active"] = { scope = "local", station = "departure", missing = "missing_preflight_context" },
    ["departure.start_push"] = { scope = "local", station = "pushback", missing = "missing_departure_context" },
    ["departure.taxi_runway"] = { scope = "local", station = "departure", runway = "departure", missing = "missing_departure_context" },
    ["departure.runway_crossing"] = { scope = "local", station = "departure", runway = "crossing", missing = "missing_runway_crossing_context" },
    ["arrival.runway_crossing"] = { scope = "local", station = "arrival", runway = "crossing", missing = "missing_runway_crossing_context" },
    ["departure.hold_short"] = { scope = "local", station = "departure", runway = "departure", missing = "missing_departure_context" },
    ["departure.backtrack"] = { scope = "local", station = "departure", runway = "departure", missing = "missing_departure_context" },
    ["departure.lining_up"] = { scope = "local", station = "departure", runway = "departure", missing = "missing_departure_context" },
    ["departure.intersection"] = { scope = "local", station = "departure", runway = "departure", missing = "missing_intersection_context" },
    ["departure.lineup_takeoff"] = { scope = "local", station = "departure", runway = "departure", missing = "missing_departure_context" },
    ["departure.airborne"] = { scope = "local", station = "departure", runway = "departure", missing = "missing_departure_context" },
    ["departure.on_climb"] = { scope = "departure_enroute", station = "departure", missing = "missing_climb_context" },
    ["departure.climb_progress"] = { scope = "departure_enroute", station = "departure", missing = "missing_climb_context" },
    [HOLD_ENTER_EVENT_ID] = { scope = "enroute", missing = "missing_hold_context" },
    [HOLDING_EVENT_ID] = { scope = "enroute", missing = "missing_hold_context" },
    [HOLD_DESCENDING_EVENT_ID] = { scope = "enroute", missing = "missing_hold_descent_context" },
    [HOLD_EXIT_EVENT_ID] = { scope = "enroute", missing = "missing_hold_context" },
    ["enroute.in_cruise"] = { scope = "enroute", missing = "missing_cruise_context" },
    ["arrival.top_of_descent"] = { scope = "arrival_enroute", station = "arrival", runway = "arrival", missing = "missing_tod_context" },
    ["arrival.on_descent"] = { scope = "arrival_enroute", station = "arrival", runway = "arrival", missing = "missing_arrival_context" },
    ["arrival.descent_progress"] = { scope = "arrival_enroute", station = "arrival", runway = "arrival", missing = "missing_arrival_context" },
    ["arrival.approach"] = { scope = "local", station = "arrival", runway = "arrival", missing = "missing_arrival_context" },
    ["arrival.on_final"] = { scope = "local", station = "arrival", runway = "arrival", missing = "missing_final_context" },
    ["arrival.short_final"] = { scope = "local", station = "arrival", runway = "arrival", missing = "missing_short_final_context" },
    ["arrival.backtrack"] = { scope = "local", station = "arrival", runway = "arrival", missing = "missing_arrival_backtrack_context" },
    ["arrival.runway_vacated"] = { scope = "local", station = "arrival", runway = "arrival", missing = "missing_vacated_context" },
    ["arrival.parking_position"] = { scope = "local", station = "arrival_parking", missing = "missing_arrival_parking_context" }
}

local function message_contract(eventId)
    if is_climb_progress_event(eventId) then return MESSAGE_CONTRACTS["departure.climb_progress"] end
    if is_descent_progress_event(eventId) then return MESSAGE_CONTRACTS["arrival.descent_progress"] end
    return MESSAGE_CONTRACTS[eventId]
end

function M.messageScope(eventId)
    local contract = message_contract(eventId)
    return contract and contract.scope or nil
end

local function context_station(snapshot, stationRole)
    if stationRole == "departure" then
        return airport_label(snapshot, "departure_icao", "departure_station_name")
    end
    if stationRole == "arrival" then
        return airport_label(snapshot, "arrival_icao", "arrival_station_name")
    end
    if stationRole == "pushback" then
        return airport_label(snapshot, "pushback_airport_icao", "pushback_station_name")
            or airport_label(snapshot, "departure_icao", "departure_station_name")
    end
    if stationRole == "arrival_parking" then
        return airport_label(snapshot, "arrival_parking_airport_icao", "arrival_parking_station_name")
            or airport_label(snapshot, "arrival_icao", "arrival_station_name")
    end
    return nil
end

local function context_runway(snapshot, runwayRole)
    if runwayRole == "departure" then return normalize_runway(snapshot.departure_runway) end
    if runwayRole == "arrival" then return normalize_runway(snapshot.arrival_runway) end
    if runwayRole == "crossing" then return normalize_runway(snapshot.crossing_runway) end
    return nil
end

local function message_context(eventId, snapshot, callsign)
    local contract = message_contract(eventId)
    if not contract then return nil, "unknown_event" end

    local station = contract.station and context_station(snapshot, contract.station) or nil
    local runway = contract.runway and context_runway(snapshot, contract.runway) or nil
    if contract.station and not station then return nil, contract.missing end
    if contract.runway and not runway then return nil, contract.missing end

    local prefix = callsign
    if contract.scope == "local" then
        prefix = string.format("%s Traffic, %s", station, callsign)
    elseif contract.scope == "departure_enroute" then
        prefix = string.format("%s climbing out of %s", callsign, station)
    elseif contract.scope == "arrival_enroute" then
        prefix = string.format("%s inbound %s", callsign, station)
    end

    return {
        contract = contract,
        prefix = prefix,
        station = station,
        runway = runway
    }
end

local function departure_intersection(snapshot)
    local intersection = clean_token(snapshot.departure_intersection, true)
    if not intersection then return nil end
    if intersection:sub(1, 13) == "INTERSECTION " then
        intersection = intersection:sub(14)
    end
    intersection = trim(intersection)
    if intersection == "" or #intersection > 24 then return nil end
    return intersection
end

function M.buildMessage(eventId, snapshot)
    snapshot = snapshot or {}
    local ac = text_callsign(snapshot)
    if not ac then return nil, "missing_effective_callsign" end
    local context, contextReason = message_context(eventId, snapshot, ac)
    if not context then return nil, contextReason end

    if eventId == "departure.flightplan_active" then
        local airportIcao = clean_token(snapshot.departure_icao, false)
        local destination, destinationIcao = airport_label(snapshot, "arrival_icao", "arrival_station_name")
        if not destination or airportIcao == destinationIcao then
            return nil, "missing_preflight_context"
        end
        local parking = parking_label(snapshot, "preflight_parking") or "parking position"
        return normalize_text(string.format(
            "%s at %s, preparing for departure to %s",
            context.prefix,
            parking,
            destination
        ))
    end

    if eventId == "departure.start_push" then
        local parking = parking_label(snapshot, "pushback_parking")
        local text = context.prefix .. " pushing back"
        if parking then text = text .. " from " .. parking end
        return normalize_text(text)
    end

    if eventId == "departure.taxi_runway" then
        return normalize_text(string.format("%s taxiing to holding point runway %s", context.prefix, context.runway))
    end

    if eventId == "departure.runway_crossing" or eventId == "arrival.runway_crossing" then
        local text = string.format("%s crossing runway %s", context.prefix, context.runway)
        local taxiway = clean_token(snapshot.crossing_taxiway, true)
        if taxiway and #taxiway <= 24 then
            text = text .. " at taxiway " .. taxiway
        end
        return normalize_text(text)
    end

    if eventId == "departure.hold_short" then
        local intersection = departure_intersection(snapshot)
        if intersection then
            return normalize_text(string.format(
                "%s holding short runway %s at taxiway %s",
                context.prefix,
                context.runway,
                intersection
            ))
        end
        return normalize_text(string.format(
            "%s holding short runway %s",
            context.prefix,
            context.runway
        ))
    end

    if eventId == "departure.backtrack" then
        return normalize_text(string.format("%s backtracking runway %s", context.prefix, context.runway))
    end

    if eventId == "departure.lining_up" then
        local text = string.format("%s lining up runway %s", context.prefix, context.runway)
        local intersection = departure_intersection(snapshot)
        if intersection then text = text .. " at taxiway " .. intersection end
        return normalize_text(text)
    end

    if eventId == "departure.intersection" then
        local intersection = departure_intersection(snapshot)
        if not intersection then return nil, "missing_intersection_context" end
        return normalize_text(string.format(
            "%s lining up runway %s at taxiway %s",
            context.prefix,
            context.runway,
            intersection
        ))
    end

    if eventId == "departure.lineup_takeoff" then
        return normalize_text(string.format("%s taking off runway %s", context.prefix, context.runway))
    end

    if eventId == "departure.airborne" then
        local altitude = format_altitude(snapshot, false)
        if not altitude then return nil, "missing_departure_context" end
        return normalize_text(string.format("%s airborne runway %s, passing %s", context.prefix, context.runway, altitude))
    end

    if eventId == HOLD_ENTER_EVENT_ID or eventId == HOLDING_EVENT_ID
        or eventId == HOLD_DESCENDING_EVENT_ID or eventId == HOLD_EXIT_EVENT_ID then
        local waypoint = clean_token(snapshot.hold_waypoint, false)
        if not waypoint then return nil, "missing_hold_context" end
        if eventId == HOLD_ENTER_EVENT_ID then
            return normalize_text(string.format("%s entering a hold over %s", context.prefix, waypoint))
        end
        if eventId == HOLDING_EVENT_ID then
            local altitude = format_hold_target_altitude(snapshot) or format_altitude(snapshot, false)
            if not altitude then return nil, "missing_hold_context" end
            return normalize_text(string.format(
                "%s maintaining %s whilst holding over %s",
                context.prefix,
                altitude,
                waypoint
            ))
        end
        if eventId == HOLD_DESCENDING_EVENT_ID then
            local altitude = format_altitude(snapshot, true)
            local target = format_hold_target_altitude(snapshot)
            if not altitude or not target then return nil, "missing_hold_descent_context" end
            return normalize_text(string.format(
                "%s in a hold over %s on descent passing %s for %s",
                context.prefix,
                waypoint,
                altitude,
                target
            ))
        end
        return normalize_text(string.format("%s exiting hold over %s", context.prefix, waypoint))
    end

    if eventId == "enroute.in_cruise" then
        local nextWaypoint = clean_token(snapshot.cruise_next_waypoint, false)
        if snapshot.cruise_entry == true then
            local altitude = format_planned_altitude(snapshot) or format_altitude(snapshot, false)
            if not altitude then return nil, "missing_cruise_context" end
            local phaseText = M.isCruiseLevelStable(snapshot.vertical_speed_fpm) and "level at" or "reaching"
            local text = string.format("%s %s %s", context.prefix, phaseText, altitude)
            if nextWaypoint then text = text .. ", " .. nextWaypoint .. " next" end
            return normalize_text(text)
        end
        local altitude = format_altitude(snapshot, false)
        if not altitude then return nil, "missing_cruise_context" end
        if snapshot.cruise_periodic == true then
            local text = string.format("%s maintaining %s", context.prefix, altitude)
            if nextWaypoint then text = text .. ", " .. nextWaypoint .. " next" end
            return normalize_text(text)
        end
        local waypoint = clean_token(snapshot.cruise_waypoint, false)
        if not waypoint then return nil, "missing_cruise_context" end
        local text = string.format(
            "%s passing %s, maintaining %s",
            context.prefix,
            waypoint,
            altitude
        )
        if nextWaypoint then text = text .. ", " .. nextWaypoint .. " next" end
        return normalize_text(text)
    end

    if eventId == "departure.on_climb" or is_climb_progress_event(eventId) then
        local altitude = format_altitude(snapshot, false)
        if not altitude then return nil, "missing_climb_context" end
        local sid = eventId == "departure.on_climb" and clean_token(snapshot.sid, false) or nil
        local nextWaypoint = clean_token(snapshot.climb_next_waypoint, false)
        local planned = format_planned_altitude(snapshot)
        local text = context.prefix
        if sid then text = text .. " on " .. sid .. " departure" end
        text = text .. ", passing " .. altitude
        if planned then text = text .. " for " .. planned end
        if nextWaypoint then text = text .. ", " .. nextWaypoint .. " next" end
        return normalize_text(text)
    end

    if eventId == "arrival.top_of_descent" then
        local altitude = format_altitude(snapshot, true)
        if not altitude then return nil, "missing_tod_context" end
        local star = clean_token(snapshot.star, false)
        local text = context.prefix
        if star then text = text .. ", " .. star .. " arrival" end
        text = text .. ", at TOD leaving " .. altitude .. ", expecting runway " .. context.runway
        return normalize_text(text)
    end

    if eventId == "arrival.on_descent" then
        local altitude = format_planned_altitude(snapshot) or format_altitude(snapshot, true)
        if not altitude then return nil, "missing_arrival_context" end
        local star = clean_token(snapshot.star, false)
        local approach = approach_label(snapshot)
        local text = context.prefix
        if star then text = text .. ", " .. star .. " arrival" end
        if approach then text = text .. ", " .. approach .. " approach" end
        text = text .. " runway " .. context.runway .. ", descent started from " .. altitude
        return normalize_text(text)
    end

    if eventId == "arrival.approach" then
        local altitude = format_altitude(snapshot, true)
        if not altitude then return nil, "missing_arrival_context" end
        local star = clean_token(snapshot.star, false)
        local approach = approach_label(snapshot)
        local text = context.prefix
        if star then text = text .. " " .. star .. " arrival" end
        text = text .. " for "
        if approach then text = text .. approach .. " approach " end
        text = text .. "runway " .. context.runway .. ", on descent passing " .. altitude
        return normalize_text(text)
    end

    if is_descent_progress_event(eventId) then
        local altitude = format_altitude(snapshot, true)
        if not altitude then return nil, "missing_arrival_context" end
        local star = clean_token(snapshot.star, false)
        local approach = approach_label(snapshot)
        local text = context.prefix
        if star then text = text .. ", " .. star .. " arrival" end
        if approach then text = text .. ", " .. approach .. " approach" end
        text = text .. " runway " .. context.runway .. ", on descent passing " .. altitude
        return normalize_text(text)
    end

    if eventId == "arrival.on_final" then
        local kind = clean_token(snapshot.approach_procedure_type, false)
        if kind == "ILS" then
            return normalize_text(string.format("%s established on ILS runway %s", context.prefix, context.runway))
        elseif kind == "LOC" then
            return normalize_text(string.format("%s established on Localizer runway %s", context.prefix, context.runway))
        end
        return normalize_text(string.format("%s on final runway %s", context.prefix, context.runway))
    end

    if eventId == "arrival.short_final" then
        return normalize_text(string.format("%s short final runway %s", context.prefix, context.runway))
    end

    if eventId == "arrival.backtrack" then
        return normalize_text(string.format("%s backtracking runway %s", context.prefix, context.runway))
    end

    if eventId == "arrival.runway_vacated" then
        return normalize_text(string.format("%s runway %s vacated, taxiing to gate", context.prefix, context.runway))
    end

    if eventId == "arrival.parking_position" then
        if snapshot.arrival_parking_found ~= true then
            return nil, "missing_arrival_parking_context"
        end
        local parking = parking_label(snapshot, "arrival_parking")
        local text = context.prefix .. " parked"
        if parking then
            text = text .. " at " .. parking
        else
            text = text .. " at parking position"
        end
        return normalize_text(text)
    end

    return nil, "unknown_event"
end

function M.buildVoiceMessage(eventId, snapshot, spellNato, visibleText)
    if type(spellNato) ~= "function" then return nil, "missing_nato_formatter" end
    snapshot = snapshot or {}

    local text, reason = visibleText, nil
    if not text then text, reason = M.buildMessage(eventId, snapshot) end
    if not text then return nil, reason end

    text = text:gsub("FL(%d+)", function(value)
        return "flight level " .. spaced_digits(value)
    end)
    text = text:gsub("(%d+)ft", function(value)
        return spaced_digits(value) .. " feet"
    end)
    text = text:gsub("runway%s+(%d%d?[LRC]?)", function(value)
        return "runway " .. (voice_runway(value) or value)
    end)

    local replacements = {}
    add_voice_token(replacements, text_callsign(snapshot), voice_callsign(snapshot, spellNato))

    local airports = {
        { "departure_icao", "departure_station_name" },
        { "arrival_icao", "arrival_station_name" },
        { "pushback_airport_icao", "pushback_station_name" },
        { "arrival_parking_airport_icao", "arrival_parking_station_name" }
    }
    for _, value in ipairs(airports) do
        local label, token = airport_label(snapshot, value[1], value[2])
        if label and label ~= token then
            add_voice_token(replacements, label, voice_station_name(label))
        elseif token then
            add_voice_token(replacements, token, spellNato(token))
        end
    end

    local namedIdentifiers = {
        { "sid", snapshot.sid },
        { "star", snapshot.star },
        { "climb_next_waypoint", snapshot.climb_next_waypoint },
        { "cruise_waypoint", snapshot.cruise_waypoint },
        { "cruise_next_waypoint", snapshot.cruise_next_waypoint },
        { "hold_waypoint", snapshot.hold_waypoint }
    }
    for _, entry in ipairs(namedIdentifiers) do
        local fieldName = entry[1]
        local value = entry[2]
        local token = clean_token(value, false)
        if token then
            add_voice_token(
                replacements,
                token,
                voice_named_identifier(token, spellNato, snapshot[fieldName .. "_nav_name"])
            )
        end
    end

    local approachSuffix = clean_token(snapshot.approach_suffix, false)
    if approachSuffix then add_voice_token(replacements, approachSuffix, spellNato(approachSuffix)) end

    local taxiway = clean_token(snapshot.crossing_taxiway, true)
    if taxiway then add_voice_token(replacements, taxiway, spellNato(taxiway)) end
    local intersection = departure_intersection(snapshot)
    if intersection then add_voice_token(replacements, intersection, spellNato(intersection)) end

    for _, prefix in ipairs({ "preflight_parking", "pushback_parking", "arrival_parking" }) do
        local parking = parking_label(snapshot, prefix)
        local identifier = parking and parking:match("^%S+%s+(.+)$") or nil
        if identifier then add_voice_token(replacements, identifier, spellNato(identifier)) end
    end

    local fixedTokens = {
        { "TOD", "top of descent" },
        { "RNAV", "R NAV" },
        { "ILS", "I L S" },
        { "GLS", "G L S" },
        { "LPV", "L P V" },
        { "LDA", "L D A" },
        { "LOC", "L O C" },
        { "LP", "L P" },
        { "SHORT FINAL", "short final" }
    }
    for _, replacement in ipairs(fixedTokens) do
        add_voice_token(replacements, replacement[1], replacement[2])
    end

    for _, replacement in ipairs(replacements) do
        text = replace_token(text, replacement.raw, replacement.spoken)
    end
    text = text:gsub("%d", function(value) return AVIATION_DIGITS[value] end)
    return normalize_voice_text(text)
end

local function summarize_sources(snapshot)
    local fields = {
        { "phase", snapshot.fms_phase },
        { "onGround", snapshot.on_ground and 1 or 0 },
        { "preflight", snapshot.preflight and 1 or 0 },
        { "initialClimbState", snapshot.initial_climb_state and 1 or 0 },
        { "climbState", snapshot.climb_state and 1 or 0 },
        { "descentState", snapshot.descent_state and 1 or 0 },
        { "postLandingState", snapshot.post_landing_state and 1 or 0 },
        { "descentEntry", snapshot.descent_entry_kind },
        { "ra", snapshot.radio_altitude_ft },
        { "alt", snapshot.altitude_ft },
        { "pressureAlt", snapshot.pressure_altitude_ft },
        { "vs", snapshot.vertical_speed_fpm },
        { "gs", snapshot.ground_speed_kts },
        { "callsign", snapshot.effective_callsign },
        { "dep", snapshot.departure_icao },
        { "depStation", snapshot.departure_station_name },
        { "depRwy", snapshot.departure_runway },
        { "arr", snapshot.arrival_icao },
        { "arrStation", snapshot.arrival_station_name },
        { "arrRwy", snapshot.arrival_runway },
        { "ofpValid", (snapshot.ofp_valid == true or tonumber(snapshot.ofp_valid) == 1) and 1 or 0 },
        { "ofpSeq", snapshot.ofp_update_seq },
        { "ofpOrigin", snapshot.ofp_origin_icao },
        { "ofpOriginName", snapshot.ofp_origin_name },
        { "ofpDestination", snapshot.ofp_destination_icao },
        { "ofpDestinationName", snapshot.ofp_destination_name },
        { "sid", snapshot.sid },
        { "sidNav", snapshot.sid_nav_name },
        { "climbNext", snapshot.climb_next_waypoint },
        { "climbNextNav", snapshot.climb_next_waypoint_nav_name },
        { "star", snapshot.star },
        { "starNav", snapshot.star_nav_name },
        { "app", snapshot.approach_id },
        { "tod", snapshot.tod_distance_nm },
        { "preflightParking", snapshot.preflight_parking_found and 1 or 0 },
        { "preflightParkingSource", snapshot.preflight_parking_source },
        { "preflightParkingType", snapshot.preflight_parking_type },
        { "preflightParkingName", snapshot.preflight_parking_name },
        { "preflightParkingDist", snapshot.preflight_parking_distance_m },
        { "pushAirport", snapshot.pushback_airport_icao },
        { "pushParking", snapshot.pushback_parking_found and 1 or 0 },
        { "pushParkingSource", snapshot.pushback_parking_source },
        { "pushParkingType", snapshot.pushback_parking_type },
        { "pushParkingName", snapshot.pushback_parking_name },
        { "pushParkingDist", snapshot.pushback_parking_distance_m },
        { "arrivalParking", snapshot.arrival_parking_found and 1 or 0 },
        { "arrivalParkingSource", snapshot.arrival_parking_source },
        { "arrivalParkingType", snapshot.arrival_parking_type },
        { "arrivalParkingName", snapshot.arrival_parking_name },
        { "arrivalParkingDist", snapshot.arrival_parking_distance_m },
        { "crossingRwy", snapshot.crossing_runway },
        { "crossingTwy", snapshot.crossing_taxiway },
        { "holdSource", snapshot.hold_source },
        { "holdWaypoint", snapshot.hold_waypoint },
        { "holdWaypointNav", snapshot.hold_waypoint_nav_name },
        { "holdPath", snapshot.hold_path_type },
        { "holdEntryComplete", snapshot.hold_entry_complete and 1 or 0 },
        { "holdTarget", snapshot.hold_target_altitude_ft },
        { "cruisePeriodic", snapshot.cruise_periodic and 1 or 0 },
        { "cruiseWaypoint", snapshot.cruise_waypoint },
        { "cruiseWaypointNav", snapshot.cruise_waypoint_nav_name },
        { "cruiseNext", snapshot.cruise_next_waypoint },
        { "cruiseNextNav", snapshot.cruise_next_waypoint_nav_name },
        { "final", snapshot.final_gate and 1 or 0 },
        { "shortFinal", snapshot.short_final_gate and 1 or 0 }
    }
    local parts = {}
    for _, field in ipairs(fields) do
        parts[#parts + 1] = field[1] .. "=" .. tostring(field[2] or "")
    end
    return table.concat(parts, " ")
end

M.summarizeSources = summarize_sources
M.isApproachPhase = is_approach_phase

function M.newEvent(eventId, snapshot, now, spellNato)
    local text, reason = M.buildMessage(eventId, snapshot)
    if not text then return nil, reason end
    local voiceText = M.buildVoiceMessage(eventId, snapshot, spellNato, text)
    return {
        id = eventId,
        text = text,
        voice_text = voiceText,
        inputs = summarize_sources(snapshot),
        created_at = now,
        expires_at = now + (M.EVENT_TTL_SEC[eventId] or 120)
    }
end

local Mailbox = {}
Mailbox.__index = Mailbox

local SUPERSEDED_EVENTS = {
    [HOLDING_EVENT_ID] = {
        [HOLD_ENTER_EVENT_ID] = true
    },
    [HOLD_DESCENDING_EVENT_ID] = {
        [HOLD_ENTER_EVENT_ID] = true,
        [HOLDING_EVENT_ID] = true
    },
    [HOLD_EXIT_EVENT_ID] = {
        [HOLD_ENTER_EVENT_ID] = true,
        [HOLDING_EVENT_ID] = true,
        [HOLD_DESCENDING_EVENT_ID] = true
    },
    ["departure.start_push"] = {
        ["departure.flightplan_active"] = true
    },
    ["departure.taxi_runway"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true
    },
    ["departure.runway_crossing"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true
    },
    ["departure.hold_short"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.runway_crossing"] = true
    },
    ["departure.backtrack"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.hold_short"] = true,
        ["departure.runway_crossing"] = true
    },
    ["departure.lining_up"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.runway_crossing"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true,
        ["departure.intersection"] = true
    },
    ["departure.intersection"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.runway_crossing"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true,
        ["departure.lining_up"] = true
    },
    ["departure.lineup_takeoff"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.runway_crossing"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true,
        ["departure.lining_up"] = true,
        ["departure.intersection"] = true
    },
    ["departure.airborne"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.runway_crossing"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true,
        ["departure.intersection"] = true,
        ["departure.lining_up"] = true,
        ["departure.lineup_takeoff"] = true
    },
    ["departure.on_climb"] = {
        ["departure.flightplan_active"] = true,
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.runway_crossing"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true,
        ["departure.intersection"] = true,
        ["departure.lining_up"] = true,
        ["departure.lineup_takeoff"] = true,
        ["departure.airborne"] = true
    },
    ["arrival.approach"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true
    },
    ["arrival.on_final"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true,
        ["arrival.approach"] = true
    },
    ["arrival.short_final"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true,
        ["arrival.approach"] = true,
        ["arrival.on_final"] = true
    },
    ["arrival.backtrack"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true,
        ["arrival.approach"] = true,
        ["arrival.on_final"] = true,
        ["arrival.short_final"] = true
    },
    ["arrival.runway_vacated"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true,
        ["arrival.approach"] = true,
        ["arrival.on_final"] = true,
        ["arrival.short_final"] = true,
        ["arrival.backtrack"] = true
    },
    ["arrival.runway_crossing"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true,
        ["arrival.approach"] = true,
        ["arrival.on_final"] = true,
        ["arrival.short_final"] = true,
        ["arrival.backtrack"] = true,
        ["arrival.runway_vacated"] = true
    },
    ["arrival.parking_position"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true,
        ["arrival.approach"] = true,
        ["arrival.on_final"] = true,
        ["arrival.short_final"] = true,
        ["arrival.backtrack"] = true,
        ["arrival.runway_vacated"] = true,
        ["arrival.runway_crossing"] = true
    }
}

local function supersedes_event(eventId, queuedId)
    local fixed = SUPERSEDED_EVENTS[eventId]
    if fixed and fixed[queuedId] then return true end
    if is_climb_progress_event(eventId) then
        return queuedId == "departure.flightplan_active"
            or queuedId == "departure.start_push"
            or queuedId == "departure.taxi_runway"
            or queuedId == "departure.runway_crossing"
            or queuedId == "departure.hold_short"
            or queuedId == "departure.backtrack"
            or queuedId == "departure.intersection"
            or queuedId == "departure.lining_up"
            or queuedId == "departure.lineup_takeoff"
            or queuedId == "departure.airborne"
            or queuedId == "departure.on_climb"
            or is_climb_progress_event(queuedId)
    end
    if eventId == "enroute.in_cruise" then
        return queuedId == "departure.flightplan_active"
            or queuedId == "departure.airborne"
            or queuedId == "departure.on_climb"
            or is_climb_progress_event(queuedId)
    end
    if is_descent_progress_event(eventId) then
        return queuedId == "arrival.top_of_descent"
            or queuedId == "arrival.on_descent"
            or is_descent_progress_event(queuedId)
    end
    if eventId == "arrival.approach"
        or eventId == "arrival.on_final"
        or eventId == "arrival.short_final"
        or eventId == "arrival.backtrack"
        or eventId == "arrival.runway_vacated"
        or eventId == "arrival.runway_crossing"
        or eventId == "arrival.parking_position" then
        return is_descent_progress_event(queuedId)
    end
    return false
end

function M.newMailbox(options)
    options = options or {}
    return setmetatable({
        writeText = options.writeText or function() return false end,
        writeVoiceText = options.writeVoiceText or function() return false end,
        writeChannels = options.writeChannels or function() return false end,
        writeSeq = options.writeSeq or function() return false end,
        log = options.log or function() end,
        queue = {},
        queuedIds = {},
        outstanding = nil,
        nextSeq = nil,
        blocked = false,
        maxQueue = tonumber(options.maxQueue) or 8,
        timeoutSec = tonumber(options.timeoutSec) or 30,
        voiceTimeoutSec = tonumber(options.voiceTimeoutSec) or 90
    }, Mailbox)
end

function Mailbox:clear()
    self.queue = {}
    self.queuedIds = {}
    self.outstanding = nil
    self.nextSeq = nil
    self.blocked = false
end

function Mailbox:enqueue(event)
    if type(event) ~= "table" or not event.id then return false end
    local text = normalize_text(event.text)
    if not text or self.queuedIds[event.id] or (self.outstanding and self.outstanding.id == event.id) then
        return false
    end
    local kept = {}
    for _, queued in ipairs(self.queue) do
        if supersedes_event(event.id, queued.id) then
            self.queuedIds[queued.id] = nil
            self.log("superseded", queued)
        else
            table.insert(kept, queued)
        end
    end
    self.queue = kept
    if #self.queue >= self.maxQueue then return false end
    event.text = text
    if event.voice_text ~= nil then
        event.voice_text = normalize_voice_text(event.voice_text)
    end
    table.insert(self.queue, event)
    self.queuedIds[event.id] = true
    return true
end

function Mailbox:prune(now)
    local kept = {}
    for _, event in ipairs(self.queue) do
        if not event.expires_at or now <= event.expires_at then
            table.insert(kept, event)
        else
            self.queuedIds[event.id] = nil
            self.log("expired", event)
        end
    end
    self.queue = kept
end

function Mailbox:cancelQueuedForGoAround()
    local kept = {}
    for _, event in ipairs(self.queue) do
        local eventId = tostring(event.id or "")
        local cancel = eventId == "arrival.top_of_descent"
            or eventId == "arrival.on_descent"
            or eventId == "arrival.approach"
            or eventId == "arrival.on_final"
            or eventId == "arrival.short_final"
            or is_descent_progress_event(eventId)
        if cancel then
            self.queuedIds[event.id] = nil
            self.log("cancelled_go_around", event)
        else
            table.insert(kept, event)
        end
    end
    self.queue = kept
end

function Mailbox:cancelQueuedForHoldStart()
    local kept = {}
    for _, event in ipairs(self.queue) do
        local cancel = event.id == "arrival.approach"
            or event.id == "arrival.on_final"
            or event.id == "arrival.short_final"
        if cancel then
            self.queuedIds[event.id] = nil
            self.log("cancelled_hold_start", event)
        else
            table.insert(kept, event)
        end
    end
    self.queue = kept
end

function Mailbox:cancelQueuedForHoldEnd()
    local kept = {}
    for _, event in ipairs(self.queue) do
        if event.id == HOLD_ENTER_EVENT_ID or event.id == HOLDING_EVENT_ID
            or event.id == HOLD_DESCENDING_EVENT_ID then
            self.queuedIds[event.id] = nil
            self.log("cancelled_hold_end", event)
        else
            table.insert(kept, event)
        end
    end
    self.queue = kept
end

function Mailbox:tick(api, now)
    self:prune(now)
    api = api or {}

    if self.outstanding then
        local resultSeq = tonumber(api.result_seq) or 0
        local resultCode = tonumber(api.result_code) or 0
        if not self.outstanding.text_terminal
            and resultSeq == self.outstanding.seq and TERMINAL_RESULTS[resultCode] then
            self.outstanding.result_code = resultCode
            self.outstanding.result_name = M.RESULT_NAMES[resultCode] or tostring(resultCode)
            self.outstanding.result_detail = tostring(api.result_detail or "")
            self.outstanding.text_terminal = true
            self.outstanding.text_terminal_at = now
            self.log("terminal", self.outstanding)
        end

        if self.outstanding.channels == 3 and not self.outstanding.voice_terminal then
            local voiceResultSeq = tonumber(api.voice_result_seq) or 0
            local voiceResultCode = tonumber(api.voice_result_code) or 0
            if voiceResultSeq == self.outstanding.seq and TERMINAL_VOICE_RESULTS[voiceResultCode] then
                self.outstanding.voice_result_code = voiceResultCode
                self.outstanding.voice_result_name = M.VOICE_RESULT_NAMES[voiceResultCode]
                    or tostring(voiceResultCode)
                self.outstanding.voice_result_detail = tostring(api.voice_result_detail or "")
                self.outstanding.voice_terminal = true
                self.log("voice_terminal", self.outstanding)
            end
        end

        if self.outstanding.text_terminal
            and (self.outstanding.channels ~= 3 or self.outstanding.voice_terminal) then
            self.outstanding = nil
        else
            local timeoutStart = self.outstanding.committed_at
            local timeoutSec = self.timeoutSec
            if self.outstanding.channels == 3 and self.outstanding.text_terminal then
                timeoutStart = self.outstanding.text_terminal_at or timeoutStart
                timeoutSec = self.voiceTimeoutSec
            end
            if now - timeoutStart <= timeoutSec then return end
            local timedOut = self.outstanding
            self.outstanding = nil
            self.blocked = true
            self.log("timeout", timedOut)
        end
        return
    end

    if self.blocked or #self.queue == 0 then return end
    local apiVersion = tonumber(api.api_version)
    if (apiVersion ~= 1 and apiVersion ~= 2 and apiVersion ~= 3) or tonumber(api.ready) ~= 1 then return end
    local mode = tonumber(api.mode) or 0
    if mode ~= 2 or tonumber(api.transport_state) ~= 5 then return end

    if not self.nextSeq then
        local currentRequest = tonumber(api.request_seq) or 0
        local currentResult = tonumber(api.result_seq) or 0
        self.nextSeq = math.max(currentRequest, currentResult) + 1
    end
    if self.nextSeq <= 0 or self.nextSeq > 2147480000 then
        self.blocked = true
        self.log("sequence_exhausted", { seq = self.nextSeq })
        return
    end

    local event = self.queue[1]
    local channels = 1
    if not self.writeText(event.text) then return end
    if apiVersion >= 2 then
        if event.voice_text then
            channels = 3
            if not self.writeVoiceText(event.voice_text) then return end
        end
        if not self.writeChannels(channels) then return end
    end
    if not self.writeSeq(self.nextSeq) then
        self.blocked = true
        self.log("sequence_write_failed", event)
        return
    end

    table.remove(self.queue, 1)
    self.queuedIds[event.id] = nil
    event.seq = self.nextSeq
    event.api_version = apiVersion
    event.channels = channels
    event.committed_at = now
    self.nextSeq = self.nextSeq + 1
    self.outstanding = event
    self.log("committed", event)
end

return M
