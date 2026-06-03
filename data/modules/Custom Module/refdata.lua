local M = {}

local def = require("definitions")

local S = {
    yal = nil,
    helpers = nil,
    initialized = false,
    available = false,
    probeCountdown = 0,
    categories = {},
    seq = { apt = 0, rnw = 0, landing_nav = 0 },
    lastActiveKey = nil,
    logged = {}
}

local STATUS_NAMES = {
    [0] = "idle",
    [1] = "found",
    [2] = "invalid_input",
    [3] = "not_found",
    [4] = "source_unavailable"
}

local function logInfo(message)
    if S.helpers and S.helpers.logInfoTS then
        S.helpers.logInfoTS(message)
    elseif sasl and sasl.logInfo then
        sasl.logInfo(tostring(message))
    end
end

local function logDebug(message)
    if S.helpers and S.helpers.logDebugTS then
        S.helpers.logDebugTS(message)
    elseif sasl and sasl.logDebug then
        sasl.logDebug(tostring(message))
    end
end

local function logOnce(key, message, debugOnly)
    if S.logged[key] == message then
        return
    end
    S.logged[key] = message
    if debugOnly then
        logDebug(message)
    else
        logInfo(message)
    end
end

local function stripNulls(value)
    value = tostring(value or "")
    local len = #value
    for i = 1, len do
        if string.byte(value, i) == 0 then
            return string.sub(value, 1, i - 1)
        end
    end
    return value
end

local function readString(prop)
    if not prop then
        return ""
    end
    local ok, value = pcall(get, prop)
    if ok and value ~= nil then
        return stripNulls(value)
    end
    local size = 0
    if prop.size then
        local okSize, rawSize = pcall(prop.size)
        if okSize then
            size = tonumber(rawSize) or 0
        end
    end
    if size > 0 then
        ok, value = pcall(get, prop, 0, size)
        if ok and value ~= nil then
            return stripNulls(value)
        end
    end
    return ""
end

local function writeString(prop, value)
    if not prop then
        return false
    end
    local text = tostring(value or "")
    local ok = pcall(set, prop, text)
    if ok then
        return true
    end
    ok = pcall(set, prop, text, 0, #text)
    return ok == true
end

local function readNumber(prop)
    if not prop then
        return nil
    end
    local ok, value = pcall(get, prop)
    if ok then
        return tonumber(value)
    end
    return nil
end

local function writeNumber(prop, value)
    if not prop then
        return false
    end
    local ok = pcall(set, prop, tonumber(value) or 0)
    return ok == true
end

local function cleanText(value)
    local text = tostring(value or "")
    if S.helpers and S.helpers.cleanstring then
        text = S.helpers.cleanstring(text)
    end
    return string.upper(text)
end

local function upperText(value)
    return string.upper(tostring(value or ""))
end

local function validIcao(value)
    if S.helpers and S.helpers.isvalidicao then
        return S.helpers.isvalidicao(value)
    end
    return type(value) == "string" and #value == 4
end

local function validRunway(value)
    if S.helpers and S.helpers.isvalidrwy then
        return S.helpers.isvalidrwy(value)
    end
    return type(value) == "string" and value ~= ""
end

local function headingDiff(a, b)
    a = tonumber(a)
    b = tonumber(b)
    if not (a and b) then
        return nil
    end
    if S.helpers and S.helpers.headingdiff then
        return math.abs(S.helpers.headingdiff(a, b))
    end
    local diff = math.abs((a - b + 180) % 360 - 180)
    return diff
end

local function normalizeDegrees(value)
    value = tonumber(value)
    if not value then
        return nil
    end
    return (value + 360) % 360
end

local function validLatLon(lat, lon)
    lat = tonumber(lat)
    lon = tonumber(lon)
    return lat ~= nil and lon ~= nil
        and math.abs(lat) > 0.000001
        and math.abs(lon) > 0.000001
end

local function readMagVarAt(lat, lon)
    lat = tonumber(lat)
    lon = tonumber(lon)
    if not validLatLon(lat, lon) then
        return nil
    end
    if not (sasl and sasl.getMagneticVariation) then
        return nil
    end
    local ok, value = pcall(sasl.getMagneticVariation, lat, lon)
    if ok then
        return tonumber(value)
    end
    return nil
end

local function magneticToTrue(magnetic, magVar)
    magnetic = tonumber(magnetic)
    magVar = tonumber(magVar)
    if not (magnetic and magVar) then
        return nil
    end
    return normalizeDegrees(magnetic - magVar)
end

local function entryMagCourse(entry)
    return tonumber(entry and entry[def.DESTCOURSE])
end

local function entryMagVar(entry)
    local magVar = tonumber(entry and entry[def.DESTMAGVAR])
    if magVar ~= nil then
        return magVar
    end
    return readMagVarAt(entry and entry[def.DESTLATPOS], entry and entry[def.DESTLONPOS])
end

local function entryTrueCourse(entry)
    if not entry then
        return nil
    end
    if entry.isTrueCourse and entry.truecourse then
        return normalizeDegrees(entry.truecourse)
    end
    return magneticToTrue(entryMagCourse(entry), entryMagVar(entry))
end

local function apiMagCourse(api)
    local course = tonumber(api and api.mag_course)
    if course ~= nil and course >= 0 then
        return normalizeDegrees(course)
    end
    return nil
end

local function boolValue(value)
    if type(value) == "boolean" then
        return value
    end
    return (tonumber(value) or 0) ~= 0
end

local function fmt(value)
    if type(value) == "number" then
        return string.format("%.6g", value)
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    return tostring(value)
end

local function categoryAvailable(name)
    local cat = S.categories[name]
    if not cat or not cat.available then
        return false
    end
    return (tonumber(readNumber(cat.available)) or 0) == 1
end

local function probe()
    S.categories = {}
    S.available = false

    local refs = S.yal and S.yal.refdata
    if not (refs and refs.nav and refs.nav.available and isProperty(refs.nav.available))
        and S.yal and S.yal.bindExternalDatarefs then
        pcall(S.yal.bindExternalDatarefs, true)
        refs = S.yal and S.yal.refdata
    end
    if not (refs and refs.nav and refs.nav.available and isProperty(refs.nav.available)) then
        logOnce("api-missing", "RefdataCompare: Zibo refdata API unavailable", false)
        return false
    end

    S.categories = refs
    S.available = true
    for _, name in ipairs({ "apt", "rnw", "landing_nav" }) do
        local cat = S.categories[name]
        if categoryAvailable(name) then
            logOnce(
                "category-ready-" .. name,
                "RefdataCompare: " .. name .. " available rows=" .. tostring(readNumber(cat.row_count) or "?")
                    .. " source=" .. tostring(readString(cat.source_path)),
                true
            )
        else
            logOnce("category-unavailable-" .. name, "RefdataCompare: " .. name .. " unavailable", false)
        end
    end
    return true
end

local function ensureReady()
    if S.available then
        return true
    end
    if S.probeCountdown and S.probeCountdown > 0 then
        S.probeCountdown = S.probeCountdown - 1
        return false
    end
    local ok = probe()
    S.probeCountdown = ok and 0 or 600
    return ok
end

local function nextSeq(name)
    local value = (tonumber(S.seq[name]) or 0) + 1
    if value > 1000000000 then
        value = 1
    end
    S.seq[name] = value
    return value
end

local function runQuery(name, writer, reader, logKey, silentStatus)
    if not ensureReady() then
        return nil
    end
    if not categoryAvailable(name) then
        return nil
    end
    local cat = S.categories[name]
    local q = cat and cat.query
    if not q then
        return nil
    end

    writer(q)
    local seq = nextSeq(name)
    if not writeNumber(q.request_seq, seq) then
        logOnce("query-write-" .. name, "RefdataCompare: " .. name .. " request_seq write failed", false)
        return nil
    end

    local resultSeq = readNumber(q.result_seq)
    if resultSeq ~= seq then
        logOnce("query-stale-" .. tostring(logKey or name), "RefdataCompare: " .. name .. " stale result_seq=" .. tostring(resultSeq) .. " request_seq=" .. tostring(seq), false)
        return nil
    end

    local status = tonumber(readNumber(q.status)) or 0
    if status ~= 1 then
        if not silentStatus then
            logOnce("query-status-" .. tostring(logKey or name) .. "-" .. tostring(status), "RefdataCompare: " .. name .. " query " .. tostring(logKey or "") .. " status=" .. tostring(STATUS_NAMES[status] or status), false)
        end
        return nil
    end

    return reader(q)
end

local function diffLog(scope, key, field, yalValue, apiValue, tolerance, mode)
    if yalValue == nil or apiValue == nil then
        return
    end

    local different = false
    if mode == "heading" then
        local diff = headingDiff(yalValue, apiValue)
        different = diff ~= nil and diff > (tolerance or 1)
    elseif mode == "bool" then
        different = boolValue(yalValue) ~= boolValue(apiValue)
    elseif type(yalValue) == "number" or type(apiValue) == "number" then
        local y = tonumber(yalValue)
        local a = tonumber(apiValue)
        different = y ~= nil and a ~= nil and math.abs(y - a) > (tolerance or 0)
    else
        different = cleanText(yalValue) ~= cleanText(apiValue)
    end

    if different then
        local message = "RefdataCompare " .. tostring(scope) .. " " .. tostring(key)
            .. " diff " .. tostring(field) .. " yal=" .. fmt(yalValue) .. " api=" .. fmt(apiValue)
        logOnce("diff-" .. tostring(scope) .. "-" .. tostring(key) .. "-" .. tostring(field) .. "-" .. fmt(yalValue) .. "-" .. fmt(apiValue), message, false)
    end
end

local function queryApt(icao)
    icao = cleanText(icao)
    if not validIcao(icao) then
        return nil
    end
    return runQuery("apt", function(q)
        writeString(q.icao, icao)
    end, function(q)
        return {
            lat = readNumber(q.lat),
            lon = readNumber(q.lon),
            transition_altitude_ft = readNumber(q.transition_altitude_ft),
            transition_level_ft = readNumber(q.transition_level_ft),
            longest_runway_m = readNumber(q.longest_runway_m),
            elevation_ft = readNumber(q.elevation_ft),
            airport_type = readNumber(q.airport_type),
            has_ils = readNumber(q.has_ils),
            max_rwy_ft = readNumber(q.max_rwy_ft)
        }
    end, "APT " .. icao)
end

local function queryRnw(icao, runway)
    icao = cleanText(icao)
    runway = cleanText(runway)
    if not (validIcao(icao) and validRunway(runway)) then
        return nil
    end
    return runQuery("rnw", function(q)
        writeString(q.icao, icao)
        writeString(q.runway, runway)
    end, function(q)
        return {
            start_lat = readNumber(q.start_lat),
            start_lon = readNumber(q.start_lon),
            end_lat = readNumber(q.end_lat),
            end_lon = readNumber(q.end_lon),
            length_m = readNumber(q.length_m),
            course_deg = readNumber(q.course_deg)
        }
    end, "RNW " .. icao .. " " .. runway)
end

local function queryLandingNav(opts)
    opts = opts or {}
    local icao = cleanText(opts.icao)
    local runway = cleanText(opts.runway)
    local kind = upperText(opts.kind)
    local ident = cleanText(opts.ident)
    if not (validIcao(icao) and validRunway(runway)) then
        return nil
    end

    return runQuery("landing_nav", function(q)
        writeString(q.ident, ident)
        writeString(q.region_filter, "")
        writeString(q.airport_filter, icao)
        writeString(q.runway_filter, runway)
        writeString(q.kind_filter, kind)
        writeNumber(q.frequency_filter, 0)
        writeNumber(q.match_index, tonumber(opts.match_index) or 0)
    end, function(q)
        return {
            match_count = readNumber(q.match_count),
            result_ident = readString(q.result_ident),
            kind_code = readNumber(q.kind_code),
            source_parse_type = readNumber(q.source_parse_type),
            lat = readNumber(q.lat),
            lon = readNumber(q.lon),
            gs_lat = readNumber(q.gs_lat),
            gs_lon = readNumber(q.gs_lon),
            frequency = readNumber(q.frequency),
            course_deg = readNumber(q.course_deg),
            mag_course = readNumber(q.mag_course),
            slope_deg = readNumber(q.slope_deg),
            height_ft = readNumber(q.height_ft),
            has_gs = readNumber(q.has_gs),
            dme_lat = readNumber(q.dme_lat),
            dme_lon = readNumber(q.dme_lon),
            dme_elevation_ft = readNumber(q.dme_elevation_ft),
            dme_range_nm = readNumber(q.dme_range_nm),
            dme_bias_nm = readNumber(q.dme_bias_nm),
            dme_ident = readString(q.dme_ident),
            dme_frequency = readNumber(q.dme_frequency),
            gs_range_nm = readNumber(q.gs_range_nm),
            gs_raw_bearing = readNumber(q.gs_raw_bearing),
            has_dme = readNumber(q.has_dme),
            region = readString(q.region),
            airport = readString(q.airport),
            runway = readString(q.runway),
            kind = readString(q.kind),
            app_id = readString(q.app_id),
            service_level = readString(q.service_level),
            name = readString(q.name)
        }
    end, "LANDING_NAV " .. icao .. " " .. runway .. " " .. kind .. " " .. ident, opts.silentStatus)
end

local function compareAirport(label, icao)
    local P = S.yal
    if not (P and P.airportdatatable) then
        return
    end
    icao = cleanText(icao)
    if not validIcao(icao) then
        return
    end
    local yalEntry = P.airportdatatable[icao]
    if not yalEntry then
        return
    end
    local api = queryApt(icao)
    if not api then
        return
    end
    local key = label .. " " .. icao
    diffLog("APT", key, "lat", tonumber(yalEntry.latitude), api.lat, 0.02)
    diffLog("APT", key, "lon", tonumber(yalEntry.longitude), api.lon, 0.02)
    diffLog("APT", key, "elevation_ft", tonumber(yalEntry.elevation_ft), api.elevation_ft, 20)
    diffLog("APT", key, "max_rwy_ft", tonumber(yalEntry.max_rwy_ft), api.max_rwy_ft, 50)
    diffLog("APT", key, "has_ils", yalEntry.has_ils, api.has_ils, nil, "bool")
end

local function compareRunway(label, icao, runway, yalRwy)
    icao = cleanText(icao)
    runway = cleanText(runway)
    if not (validIcao(icao) and validRunway(runway)) then
        return
    end
    local api = queryRnw(icao, runway)
    if not api then
        return
    end
    yalRwy = yalRwy or {}
    local key = label .. " " .. icao .. " " .. runway
    local length = tonumber(yalRwy.length_m)
    local courseMag = tonumber(yalRwy.course_deg)
    local startLat = tonumber(yalRwy.start_lat)
    local startLon = tonumber(yalRwy.start_lon)
    local endLat = tonumber(yalRwy.end_lat)
    local endLon = tonumber(yalRwy.end_lon)
    if length and length > 0 then
        diffLog("RNW", key, "length_m", length, api.length_m, 5)
    end
    if courseMag and courseMag >= 0 then
        local magVar = readMagVarAt(startLat, startLon) or readMagVarAt(api.start_lat, api.start_lon)
        local courseTrue = magneticToTrue(courseMag, magVar)
        if courseTrue then
            diffLog("RNW", key, "course_deg_true", courseTrue, api.course_deg, 1, "heading")
        end
    end
    if startLat and math.abs(startLat) > 0.000001 then
        diffLog("RNW", key, "start_lat", startLat, api.start_lat, 0.005)
    end
    if startLon and math.abs(startLon) > 0.000001 then
        diffLog("RNW", key, "start_lon", startLon, api.start_lon, 0.005)
    end
    if endLat and math.abs(endLat) > 0.000001 then
        diffLog("RNW", key, "end_lat", endLat, api.end_lat, 0.005)
    end
    if endLon and math.abs(endLon) > 0.000001 then
        diffLog("RNW", key, "end_lon", endLon, api.end_lon, 0.005)
    end
end

local function landingKindForEntry(entry)
    if not entry then
        return nil
    end
    local navType = entry[def.DESTNAVTYPE]
    if navType == def.NAVTYPEILS then return "ILS" end
    if navType == def.NAVTYPEIGS then return "IGS" end
    if navType == def.NAVTYPELDA then return "LDA" end
    if navType == def.NAVTYPEGLS then return "GLS" end
    if navType == def.NAVTYPELPV then return "LPV" end
    if navType == def.NAVTYPERNAV then
        if entry.isLateralOnly or cleanText(entry.serviceLevel) == "LP" then
            return "LP"
        end
        return nil
    end
    if navType == def.NAVTYPELOC then return "LOC" end
    return nil
end

local function isFinalApproachKind(kind)
    return kind == "GLS" or kind == "LPV" or kind == "LP"
end

local function isLocalizerKind(kind)
    return kind == "ILS"
        or kind == "IGS"
        or kind == "LOC"
        or kind == "LOC_GS"
        or kind == "LDA"
end

local function entryAppId(entry, context)
    local appId = cleanText(entry and entry.app_id or "")
    if appId ~= "" then
        return appId
    end
    appId = cleanText(context and context.selectedAppId or "")
    if appId ~= "" then
        return appId
    end
    return cleanText(entry and entry[def.DESTNAVID] or "")
end

local function serviceLevelForEntry(entry)
    return cleanText(entry and entry.serviceLevel or "")
end

local function frequencyMatches(entry, api)
    local yFreq = tonumber(entry and entry[def.DESTFREQ])
    local aFreq = tonumber(api and api.frequency)
    return yFreq ~= nil and aFreq ~= nil and math.abs(yFreq - aFreq) <= 0.5
end

local function courseMatches(entry, api)
    if not (entry and api) then
        return false
    end
    local apiMag = apiMagCourse(api)
    if apiMag then
        local diffMag = headingDiff(entryMagCourse(entry), apiMag)
        if diffMag ~= nil and diffMag <= 1 then
            return true
        end
    end
    local diff = headingDiff(entryTrueCourse(entry), api.course_deg)
    return diff ~= nil and diff <= 1
end

local function scoreFinalLandingMatch(entry, context, api)
    if not api then
        return -1000000
    end
    local score = 0
    local appId = entryAppId(entry, context)
    local ident = cleanText(entry and entry[def.DESTNAVID] or "")
    local service = serviceLevelForEntry(entry)
    local apiAppId = cleanText(api.app_id)
    local apiIdent = cleanText(api.result_ident)
    local apiService = cleanText(api.service_level)

    if appId ~= "" then
        if apiAppId == appId then
            score = score + 1000
        elseif apiIdent == appId then
            score = score + 400
        else
            score = score - 100
        end
    end
    if ident ~= "" and apiIdent == ident then
        score = score + 250
    end
    if frequencyMatches(entry, api) then
        score = score + 100
    end
    if service ~= "" and apiService == service then
        score = score + 50
    end
    if courseMatches(entry, api) then
        score = score + 25
    end
    return score
end

local function queryFinalLandingForEntry(entry, context, kind)
    local icao = entry and entry[def.DESTICAO]
    local runway = entry and entry[def.DESTRWY]
    local first = queryLandingNav({
        icao = icao,
        runway = runway,
        kind = kind,
        ident = "",
        match_index = 0
    })
    if not first then
        return nil
    end

    local best = first
    local bestScore = scoreFinalLandingMatch(entry, context, first)
    local matchCount = tonumber(first.match_count) or 1
    if matchCount > 1 then
        local maxIndex = math.min(matchCount - 1, 49)
        for index = 1, maxIndex do
            local candidate = queryLandingNav({
                icao = icao,
                runway = runway,
                kind = kind,
                ident = "",
                match_index = index,
                silentStatus = true
            })
            local candidateScore = scoreFinalLandingMatch(entry, context, candidate)
            if candidateScore > bestScore then
                best = candidate
                bestScore = candidateScore
            end
        end
        if matchCount > 50 then
            logOnce(
                "landing-nav-match-cap-" .. cleanText(icao) .. "-" .. cleanText(runway) .. "-" .. tostring(kind),
                "RefdataCompare: landing_nav match enumeration capped at 50 of " .. tostring(matchCount)
                    .. " for " .. cleanText(icao) .. " " .. cleanText(runway) .. " " .. tostring(kind),
                false
            )
        end
    end
    return best
end

local function queryLandingForEntry(entry, context)
    local icao = entry and entry[def.DESTICAO]
    local runway = entry and entry[def.DESTRWY]
    local kind = landingKindForEntry(entry)
    local ident = entry and entry[def.DESTNAVID]
    if not kind then
        return nil
    end

    if isFinalApproachKind(kind) then
        return queryFinalLandingForEntry(entry, context, kind), kind
    end

    local api = queryLandingNav({
        icao = icao,
        runway = runway,
        kind = kind,
        ident = ident,
        frequency = entry[def.DESTFREQ],
        silentStatus = (kind == "LOC")
    })
    if (not api) and kind == "LOC" then
        api = queryLandingNav({
            icao = icao,
            runway = runway,
            kind = "LOC_GS",
            ident = ident,
            frequency = entry[def.DESTFREQ]
        })
    end
    return api, kind
end

local function compareLandingEntry(entry, context)
    if not entry then
        return
    end
    local api, kind = queryLandingForEntry(entry, context)
    if not api then
        return
    end
    local icao = cleanText(entry[def.DESTICAO])
    local runway = cleanText(entry[def.DESTRWY])
    local navType = tostring(entry[def.DESTNAVTYPE] or "")
    local ident = tostring(entry[def.DESTNAVID] or "")
    local key = icao .. " " .. runway .. " " .. navType .. " " .. ident

    if isFinalApproachKind(kind) then
        diffLog("LANDING_NAV", key, "app_id", entryAppId(entry, context), api.app_id, nil)
    else
        diffLog("LANDING_NAV", key, "ident", ident, api.result_ident, nil)
        diffLog("LANDING_NAV", key, "app_id", tostring(entry.app_id or ""), api.app_id, nil)
    end
    diffLog("LANDING_NAV", key, "airport", icao, api.airport, nil)
    diffLog("LANDING_NAV", key, "runway", runway, api.runway, nil)
    diffLog("LANDING_NAV", key, "kind", kind, api.kind, nil)
    diffLog("LANDING_NAV", key, "frequency", tonumber(entry[def.DESTFREQ]), api.frequency, 0)
    local courseTrue = entryTrueCourse(entry)
    if isLocalizerKind(kind) then
        diffLog("LANDING_NAV", key, "mag_course", entryMagCourse(entry), apiMagCourse(api), 1, "heading")
    elseif courseTrue then
        diffLog("LANDING_NAV", key, "course_deg_true", courseTrue, api.course_deg, 1, "heading")
    else
        diffLog("LANDING_NAV", key, "course_deg", tonumber(entry[def.DESTCOURSE]), api.course_deg, 1, "heading")
    end
    diffLog("LANDING_NAV", key, "lat", tonumber(entry[def.DESTLATPOS]), api.lat, 0.001)
    diffLog("LANDING_NAV", key, "lon", tonumber(entry[def.DESTLONPOS]), api.lon, 0.001)
    diffLog("LANDING_NAV", key, "height_ft", tonumber(entry[def.DESTELEVATION]), api.height_ft, 5)
    diffLog("LANDING_NAV", key, "service_level", tostring(entry.serviceLevel or ""), api.service_level, nil)

    local yHasGs = (tonumber(entry[def.DESTGSSLOPE]) or 0) > 0
        or (tonumber(entry[def.DESTGSRANGE]) or 0) > 0
    diffLog("LANDING_NAV", key, "has_gs", yHasGs, api.has_gs, nil, "bool")
    if yHasGs or boolValue(api.has_gs) then
        diffLog("LANDING_NAV", key, "gs_lat", tonumber(entry[def.DESTGSLAT]), api.gs_lat, 0.001)
        diffLog("LANDING_NAV", key, "gs_lon", tonumber(entry[def.DESTGSLON]), api.gs_lon, 0.001)
        diffLog("LANDING_NAV", key, "gs_range_nm", tonumber(entry[def.DESTGSRANGE]), api.gs_range_nm, 0.1)
        diffLog("LANDING_NAV", key, "slope_deg", tonumber(entry[def.DESTGSSLOPE]), api.slope_deg, 0.01)
        diffLog("LANDING_NAV", key, "gs_raw_bearing", tonumber(entry[def.DESTGSRAWBEARING]), api.gs_raw_bearing, 1)
    end

    local yDmeIdent = tostring(entry[def.DESTDMEIDENT] or "")
    local yHasDme = yDmeIdent ~= "" or (tonumber(entry[def.DESTDMEFREQ]) or 0) > 0
    if yHasDme or boolValue(api.has_dme) then
        diffLog("LANDING_NAV", key, "has_dme", yHasDme, api.has_dme, nil, "bool")
        diffLog("LANDING_NAV", key, "dme_ident", yDmeIdent, api.dme_ident, nil)
        diffLog("LANDING_NAV", key, "dme_frequency", tonumber(entry[def.DESTDMEFREQ]), api.dme_frequency, 0)
        diffLog("LANDING_NAV", key, "dme_lat", tonumber(entry[def.DESTDMELAT]), api.dme_lat, 0.001)
        diffLog("LANDING_NAV", key, "dme_lon", tonumber(entry[def.DESTDMELON]), api.dme_lon, 0.001)
        diffLog("LANDING_NAV", key, "dme_elevation_ft", tonumber(entry[def.DESTDMEELEVATION]), api.dme_elevation_ft, 5)
        diffLog("LANDING_NAV", key, "dme_range_nm", tonumber(entry[def.DESTDMERANGE]), api.dme_range_nm, 0.1)
    end

end

function M.initialize(yalRef, helpersRef)
    S.yal = yalRef
    S.helpers = helpersRef
    S.initialized = true
    S.available = false
    S.probeCountdown = 0
    S.lastActiveKey = nil
    probe()
end

function M.compareActive(force)
    if not S.initialized then
        return
    end
    local P = S.yal
    if not P then
        return
    end

    local depIcao = cleanText(P.depicao and get(P.depicao) or "")
    local depRwy = cleanText(P.deprwy and get(P.deprwy) or "")
    local desIcao = cleanText(P.desicao and get(P.desicao) or "")
    local desRwy = cleanText(P.desrwy and get(P.desrwy) or "")
    local key = depIcao .. "|" .. depRwy .. "|" .. desIcao .. "|" .. desRwy
        .. "|" .. tostring(P.deprwylen and get(P.deprwylen) or "")
        .. "|" .. tostring(P.deprwyheading and get(P.deprwyheading) or "")
        .. "|" .. tostring(P.deprwylatstartpos and get(P.deprwylatstartpos) or "")
        .. "|" .. tostring(P.deprwylonstartpos and get(P.deprwylonstartpos) or "")
        .. "|" .. tostring(P.deprwylatendpos and get(P.deprwylatendpos) or "")
        .. "|" .. tostring(P.deprwylonendpos and get(P.deprwylonendpos) or "")
        .. "|" .. tostring(P.desrwylen and get(P.desrwylen) or "")
        .. "|" .. tostring(P.desrwyheading and get(P.desrwyheading) or "")
        .. "|" .. tostring(P.desrwylatstartpos and get(P.desrwylatstartpos) or "")
        .. "|" .. tostring(P.desrwylonstartpos and get(P.desrwylonstartpos) or "")
        .. "|" .. tostring(P.desrwylatendpos and get(P.desrwylatendpos) or "")
        .. "|" .. tostring(P.desrwylonendpos and get(P.desrwylonendpos) or "")
    if (not force) and S.available and key == S.lastActiveKey then
        return
    end
    S.lastActiveKey = key

    if not ensureReady() then
        return
    end

    compareAirport("DEP", depIcao)
    compareAirport("DEST", desIcao)
    compareRunway("DEP", depIcao, depRwy, {
        length_m = P.deprwylen and get(P.deprwylen) or nil,
        course_deg = P.deprwyheading and get(P.deprwyheading) or nil,
        start_lat = P.deprwylatstartpos and get(P.deprwylatstartpos) or nil,
        start_lon = P.deprwylonstartpos and get(P.deprwylonstartpos) or nil,
        end_lat = P.deprwylatendpos and get(P.deprwylatendpos) or nil,
        end_lon = P.deprwylonendpos and get(P.deprwylonendpos) or nil
    })
    compareRunway("DEST", desIcao, desRwy, {
        length_m = P.desrwylen and get(P.desrwylen) or nil,
        course_deg = P.desrwyheading and get(P.desrwyheading) or nil,
        start_lat = P.desrwylatstartpos and get(P.desrwylatstartpos) or nil,
        start_lon = P.desrwylonstartpos and get(P.desrwylonstartpos) or nil,
        end_lat = P.desrwylatendpos and get(P.desrwylatendpos) or nil,
        end_lon = P.desrwylonendpos and get(P.desrwylonendpos) or nil
    })
end

function M.compareLandingNavForEntry(_, entry, context)
    if not S.initialized or not entry then
        return
    end
    if not ensureReady() then
        return
    end
    compareLandingEntry(entry, context)
end

return M
