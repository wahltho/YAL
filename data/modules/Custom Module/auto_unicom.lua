local core = require("auto_unicom_core")

local M = {}
local runtime = nil
local mailbox = nil
local active = false
local connectionLogKey = nil
local callsignUnavailableLogged = false
local lastIntendedMessageText = nil
local lastIntendedMessageVoiceText = nil
local lastCommittedMessageText = nil
local lastCommittedMessageVoiceText = nil
local manualRepeatCount = 0
local stationNameCache = {}
local PREFLIGHT_PARKING_MAX_DISTANCE_M = 35
local PUSHBACK_PARKING_MAX_DISTANCE_M = 80
local ARRIVAL_PARKING_MAX_DISTANCE_M = 35
local NM_TO_METERS = 1852
local OFP_SNAPSHOT_READ_ATTEMPTS = 3
local FMS_DISPLAY_IDENT_MAX_LENGTH = 6

local function log(message)
    if runtime and runtime.helpers and runtime.helpers.logInfoTS then
        runtime.helpers.logInfoTS(message)
    elseif sasl and sasl.logInfo then
        sasl.logInfo(message)
    end
end

local function refs()
    if runtime and runtime.getRefs then return runtime.getRefs() end
    return runtime and runtime.refs or nil
end

local function safe_read(prop, index)
    if not prop then return nil end
    if isProperty and not isProperty(prop) then return nil end
    local reader = runtime and runtime.read or get
    local ok, value = pcall(reader, prop, index)
    if not ok then return nil end
    return value
end

local function clean_effective_callsign(value)
    local text = tostring(value or "")
    local nullIndex = text:find("\0", 1, true)
    if nullIndex then text = text:sub(1, nullIndex - 1) end
    text = text:match("^%s*(.-)%s*$"):upper()
    if #text < 2 or #text > 7 or text:find("[^A-Z0-9]") then return "" end
    return text
end

local function clean_data_string(value)
    local text = tostring(value or "")
    local nullIndex = text:find("\0", 1, true)
    if nullIndex then text = text:sub(1, nullIndex - 1) end
    return text
end

local function write_request_text(text)
    local api = refs()
    local prop = api and api.request_text or nil
    if not prop or (isProperty and not isProperty(prop)) then return false end
    if runtime and runtime.writeText then return runtime.writeText(prop, text) end
    return pcall(set, prop, text)
end

local function write_request_seq(seq)
    local api = refs()
    local prop = api and api.request_seq or nil
    if not prop or (isProperty and not isProperty(prop)) then return false end
    if runtime and runtime.writeSeq then return runtime.writeSeq(prop, seq) end
    return pcall(set, prop, seq)
end

local function write_request_voice_text(text)
    local api = refs()
    local prop = api and api.request_voice_text or nil
    if not prop or (isProperty and not isProperty(prop)) then return false end
    if runtime and runtime.writeText then return runtime.writeText(prop, text) end
    return pcall(set, prop, text)
end

local function write_request_channels(channels)
    local api = refs()
    local prop = api and api.request_channels or nil
    if not prop or (isProperty and not isProperty(prop)) then return false end
    if runtime and runtime.writeChannels then return runtime.writeChannels(prop, channels) end
    return pcall(set, prop, channels)
end

local function mailbox_log(kind, event)
    if kind == "committed" then
        lastCommittedMessageText = event.text
        lastCommittedMessageVoiceText = event.voice_text
        log(string.format("IVAO Auto-Unicom: committed event=%s seq=%s channels=%s text=%s voice_text=%s",
            tostring(event.id), tostring(event.seq), tostring(event.channels), tostring(event.text),
            tostring(event.voice_text or "")))
    elseif kind == "terminal" then
        log(string.format("IVAO Auto-Unicom: terminal event=%s seq=%s result=%s detail=%s",
            tostring(event.id), tostring(event.seq), tostring(event.result_name), tostring(event.result_detail or "")))
    elseif kind == "voice_terminal" then
        log(string.format("IVAO Auto-Unicom: voice terminal event=%s seq=%s result=%s detail=%s",
            tostring(event.id), tostring(event.seq), tostring(event.voice_result_name),
            tostring(event.voice_result_detail or "")))
    elseif kind == "expired" then
        log("IVAO Auto-Unicom: expired queued event=" .. tostring(event.id))
    elseif kind == "superseded" then
        log("IVAO Auto-Unicom: superseded queued event=" .. tostring(event.id))
    elseif kind == "cancelled_go_around" then
        log("IVAO Auto-Unicom: cancelled queued event after go-around=" .. tostring(event.id))
    elseif kind == "cancelled_hold_end" then
        log("IVAO Auto-Unicom: cancelled stale queued hold event=" .. tostring(event.id))
    elseif kind == "timeout" then
        log("IVAO Auto-Unicom: result timeout; transport blocked for session seq=" .. tostring(event.seq))
    elseif kind == "sequence_write_failed" then
        log("IVAO Auto-Unicom: request_seq write failed; transport blocked for session")
    elseif kind == "sequence_exhausted" then
        log("IVAO Auto-Unicom: request sequence exhausted; transport blocked for session")
    end
end

local function enqueue_event(event)
    local intendedText = core.normalizeText(event and event.text)
    if intendedText then
        lastIntendedMessageText = intendedText
        lastIntendedMessageVoiceText = core.normalizeVoiceText(event and event.voice_text)
    end
    if not mailbox or not mailbox:enqueue(event) then return false end
    log(string.format("IVAO Auto-Unicom: queued event=%s inputs={%s} text=%s voice_text=%s",
        tostring(event.id), tostring(event.inputs or ""), tostring(event.text),
        tostring(event.voice_text or "")))
    return true
end

local function create_runtime_state()
    mailbox = core.newMailbox({
        writeText = write_request_text,
        writeVoiceText = write_request_voice_text,
        writeChannels = write_request_channels,
        writeSeq = write_request_seq,
        log = mailbox_log,
        maxQueue = 8,
        timeoutSec = 30,
        voiceTimeoutSec = 90
    })
end

local function read_approach_ref(snapshot)
    local api = runtime.yal and runtime.yal.approachRef or nil
    if type(api) ~= "table" or not api.update_seq then return end
    local seqBefore = tonumber(safe_read(api.update_seq))
    if not seqBefore or seqBefore % 2 ~= 0 then return end

    local selected = tonumber(safe_read(api.selected)) or 0
    local airport = tostring(safe_read(api.airport) or "")
    local runway = tostring(safe_read(api.runway) or "")
    local procedureId = tostring(safe_read(api.procedure_id) or "")
    local procedureType = tostring(safe_read(api.procedure_type) or "")
    local resolvedKind = tostring(safe_read(api.resolved_nav_kind) or "")
    local seqAfter = tonumber(safe_read(api.update_seq))
    if seqAfter ~= seqBefore or seqAfter % 2 ~= 0 or selected ~= 1 then return end

    local expectedAirport = tostring(snapshot.arrival_icao or ""):upper()
    local expectedRunway = core.normalizeRunway(snapshot.arrival_runway)
    local apiRunway = core.normalizeRunway(runway)
    if airport:upper() ~= expectedAirport or not expectedRunway or apiRunway ~= expectedRunway then return end

    snapshot.approach_id = procedureId ~= "" and procedureId or snapshot.approach_id
    snapshot.approach_procedure_type = procedureType ~= "" and procedureType or snapshot.approach_procedure_type
    snapshot.approach_resolved_kind = resolvedKind ~= "" and resolvedKind or nil
end

local function parse_approach_fallback(snapshot)
    local helpers = runtime.helpers
    if not helpers or not helpers.parseSelectedApproachId then return end
    local parsed = helpers.parseSelectedApproachId(snapshot.approach_id, nil)
    if not parsed then return end
    snapshot.approach_suffix = parsed.suffix
    if not snapshot.approach_procedure_type then
        snapshot.approach_procedure_type = parsed.navType
    end
end

local function normalize_icao(value)
    local helpers = runtime and runtime.helpers or nil
    local text = tostring(value or "")
    if helpers and helpers.forceCleanString then
        text = helpers.forceCleanString(text)
    end
    if helpers and helpers.extractprimaryicao then
        text = helpers.extractprimaryicao(text) or ""
    end
    text = tostring(text):upper():gsub("^%s+", ""):gsub("%s+$", "")
    if #text ~= 4 then return nil end
    for index = 1, 4 do
        local byte = text:byte(index)
        if not byte or byte < 65 or byte > 90 then return nil end
    end
    if helpers and helpers.isvalidicao and not helpers.isvalidicao(text) then return nil end
    return text
end

local function read_ofp_runtime(snapshot)
    local api = runtime.yal and runtime.yal.ofpRuntime or nil
    if type(api) ~= "table" or not api.api_version or not api.update_seq then return end

    local apiVersion = tonumber(safe_read(api.api_version))
    if not apiVersion or apiVersion < 1 then return end

    for _ = 1, OFP_SNAPSHOT_READ_ATTEMPTS do
        local seqBefore = tonumber(safe_read(api.update_seq))
        if seqBefore and seqBefore % 2 == 0 then
            local valid = tonumber(safe_read(api.valid)) or 0
            local originIcao = clean_data_string(safe_read(api.origin_icao))
            local originName = clean_data_string(safe_read(api.origin_name))
            local destinationIcao = clean_data_string(safe_read(api.destination_icao))
            local destinationName = clean_data_string(safe_read(api.destination_name))
            local seqAfter = tonumber(safe_read(api.update_seq))

            if seqAfter == seqBefore and seqAfter % 2 == 0 then
                snapshot.ofp_api_version = math.floor(apiVersion)
                snapshot.ofp_update_seq = seqAfter
                snapshot.ofp_valid = valid == 1
                if snapshot.ofp_valid then
                    snapshot.ofp_origin_icao = normalize_icao(originIcao)
                    snapshot.ofp_origin_name = originName
                    snapshot.ofp_destination_icao = normalize_icao(destinationIcao)
                    snapshot.ofp_destination_name = destinationName
                end
                return
            end
        end
    end
end

local function read_nearest_parking(snapshot, y, airport, prefix, maxDistanceMeters)
    local helpers = runtime and runtime.helpers or nil
    if not airport or not helpers then return end

    local ziboDistanceNm = tonumber(safe_read(y.autogatenearest))
    local ziboName = tostring(safe_read(y.autogatenearestname) or "")
    if helpers.forceCleanString then ziboName = helpers.forceCleanString(ziboName) end
    if ziboDistanceNm and ziboDistanceNm >= 0 and ziboDistanceNm * NM_TO_METERS <= maxDistanceMeters
        and ziboName ~= "" then
        snapshot[prefix .. "_found"] = true
        snapshot[prefix .. "_type"] = tonumber(safe_read(y.autogategpu)) == 1 and "gate" or "misc"
        snapshot[prefix .. "_name"] = ziboName
        snapshot[prefix .. "_distance_m"] = ziboDistanceNm * NM_TO_METERS
        snapshot[prefix .. "_source"] = "zibo"
        return
    end

    if not helpers.getNearestRamp then return end

    local lat = tonumber(safe_read(y.aircraftlatpos))
    local lon = tonumber(safe_read(y.aircraftlonpos))
    if not lat or not lon or lat < -90 or lat > 90 or lon < -180 or lon > 180
        or (lat == 0 and lon == 0) then
        return
    end

    local ok, ramp, distanceSquared = pcall(
        helpers.getNearestRamp,
        airport,
        lat,
        lon
    )
    distanceSquared = tonumber(distanceSquared)
    if not ok or not ramp or not distanceSquared or distanceSquared < 0
        or distanceSquared > maxDistanceMeters * maxDistanceMeters then
        return
    end

    snapshot[prefix .. "_found"] = true
    snapshot[prefix .. "_type"] = tostring(ramp.ramp_type or ""):lower()
    snapshot[prefix .. "_name"] = tostring(ramp.name or "")
    snapshot[prefix .. "_distance_m"] = math.sqrt(distanceSquared)
    snapshot[prefix .. "_source"] = "local"
end

local function read_pushback_parking(snapshot, y)
    local airport = normalize_icao(safe_read(y.nearesticao))
        or normalize_icao(snapshot.departure_icao)
    snapshot.pushback_airport_icao = airport
    read_nearest_parking(snapshot, y, airport, "pushback_parking", PUSHBACK_PARKING_MAX_DISTANCE_M)
end

local function read_preflight_parking(snapshot, y)
    local airport = normalize_icao(snapshot.departure_icao)
    read_nearest_parking(snapshot, y, airport, "preflight_parking", PREFLIGHT_PARKING_MAX_DISTANCE_M)
end

local function read_arrival_parking(snapshot, y)
    local arrivalAirport = normalize_icao(snapshot.arrival_icao)
    local searchAirport = normalize_icao(safe_read(y.nearesticao)) or arrivalAirport
    snapshot.arrival_parking_airport_icao = arrivalAirport or searchAirport
    read_nearest_parking(snapshot, y, searchAirport, "arrival_parking", ARRIVAL_PARKING_MAX_DISTANCE_M)
end

local STATION_NAME_FIELDS = {
    { "departure_icao", "departure_station_name", "departure_station_icao" },
    { "arrival_icao", "arrival_station_name", "arrival_station_icao" },
    { "pushback_airport_icao", "pushback_station_name", "pushback_station_icao" },
    { "arrival_parking_airport_icao", "arrival_parking_station_name", "arrival_parking_station_icao" }
}
local RETAINED_ARRIVAL_STATION_FIELDS = {
    STATION_NAME_FIELDS[2],
    STATION_NAME_FIELDS[4]
}

local function enrich_station_names(snapshot)
    local adapter = runtime and runtime.refdata or nil
    if type(adapter) ~= "table" or type(adapter.getAirport) ~= "function" then return end
    for _, fields in ipairs(STATION_NAME_FIELDS) do
        local icao = normalize_icao(snapshot[fields[1]])
        snapshot[fields[2]] = nil
        snapshot[fields[3]] = nil
        if icao then
            local ok, airport = pcall(adapter.getAirport, icao)
            if ok and type(airport) == "table" and airport.station_name_valid == true
                and tostring(airport.station_name or "") ~= "" then
                snapshot[fields[2]] = tostring(airport.station_name)
                snapshot[fields[3]] = icao
            end
        end
    end
end

local function retain_station_names(snapshot)
    if type(core.resolveAirportLabel) ~= "function" then return end
    for _, fields in ipairs(RETAINED_ARRIVAL_STATION_FIELDS) do
        local icao = normalize_icao(snapshot[fields[1]])
        if icao then
            local label, resolvedIcao, source = core.resolveAirportLabel(snapshot, fields[1], fields[2])
            local cached = stationNameCache[icao]
            if resolvedIcao == icao and label and label ~= icao and source == "ofp" then
                stationNameCache[icao] = { name = label, source = source }
            elseif resolvedIcao == icao and label and label ~= icao and source == "refdata"
                and (not cached or cached.source ~= "ofp") then
                stationNameCache[icao] = { name = label, source = source }
            elseif cached then
                snapshot[fields[2]] = cached.name
                snapshot[fields[3]] = icao
            end
        end
    end
end

local function clean_navigation_identifier(value)
    local text = clean_data_string(value):upper():match("^%s*(.-)%s*$") or ""
    if text == "" or #text > 16 or text:find("[^A-Z0-9%-]") then return nil end
    return text
end

local function route_array_value(values, index)
    if type(values) ~= "table" then return nil end
    return tonumber(values[index])
end

local function read_fms_route_legs(y)
    local legsText = clean_data_string(safe_read(y.fmslegs))
    local latitudes = safe_read(y.fmslegslat)
    local longitudes = safe_read(y.fmslegslon)
    if legsText == "" then return {}, nil end

    local legs = {}
    local index = 0
    for rawIdent in legsText:gmatch("%S+") do
        index = index + 1
        local ident = clean_navigation_identifier(rawIdent)
        if ident then
            local latitude = route_array_value(latitudes, index)
            local longitude = route_array_value(longitudes, index)
            local positionValid = latitude ~= nil and longitude ~= nil
                and latitude >= -90 and latitude <= 90
                and longitude >= -180 and longitude <= 180
                and not (latitude == 0 and longitude == 0)
            legs[#legs + 1] = {
                ident = ident,
                route_index = index,
                latitude = positionValid and latitude or nil,
                longitude = positionValid and longitude or nil
            }
        end
    end

    local activeIndex = tonumber(safe_read(y.fmsvnavidx))
    if activeIndex then activeIndex = math.floor(activeIndex + 0.5) end
    return legs, activeIndex
end

local function route_leg_matches(legIdent, requestedIdent)
    if legIdent == requestedIdent then return true end
    return #requestedIdent == FMS_DISPLAY_IDENT_MAX_LENGTH
        and #legIdent > FMS_DISPLAY_IDENT_MAX_LENGTH
        and legIdent:sub(1, FMS_DISPLAY_IDENT_MAX_LENGTH) == requestedIdent
end

local function find_route_leg(legs, requestedIdent, preferredIndex)
    requestedIdent = clean_navigation_identifier(requestedIdent)
    if not requestedIdent then return nil end
    local best = nil
    local bestDelta = nil
    for _, leg in ipairs(legs or {}) do
        if route_leg_matches(leg.ident, requestedIdent) then
            local delta = preferredIndex and math.abs(leg.route_index - preferredIndex) or leg.route_index
            if not bestDelta or delta < bestDelta then
                best = leg
                bestDelta = delta
            end
        end
    end
    return best
end

local function nav_ident_for_procedure(value)
    local ident = clean_navigation_identifier(value)
    if not ident then return nil end
    local prefix = ident:match("^([A-Z]+)%d+[A-Z]*$")
    return prefix or ident
end

local function resolve_nav_name(ident, leg)
    ident = clean_navigation_identifier(ident)
    if not ident or #ident > 4 or ident:find("[^A-Z]") then return nil end
    local adapter = runtime and runtime.refdata or nil
    if type(adapter) ~= "table" or type(adapter.getNavByIdent) ~= "function" then return nil end
    local ok, nav = pcall(
        adapter.getNavByIdent,
        ident,
        leg and leg.latitude or nil,
        leg and leg.longitude or nil
    )
    if not ok or type(nav) ~= "table" or tostring(nav.name or "") == "" then return nil end
    return tostring(nav.name)
end

local function enrich_navigation_identifiers(snapshot)
    local y = runtime and runtime.yal or nil
    if not y then return end
    local legs, activeIndex = read_fms_route_legs(y)
    local waypointFields = {
        { "climb_next_waypoint", 0 },
        { "cruise_next_waypoint", 0 },
        { "cruise_waypoint", -1 },
        { "hold_waypoint", 0 }
    }
    for _, field in ipairs(waypointFields) do
        local fieldName = field[1]
        local ident = clean_navigation_identifier(snapshot[fieldName])
        if ident then
            local preferredIndex = activeIndex and activeIndex + field[2] or nil
            local leg = find_route_leg(legs, ident, preferredIndex)
            if leg then
                ident = leg.ident
                snapshot[fieldName] = ident
                snapshot[fieldName .. "_latitude"] = leg.latitude
                snapshot[fieldName .. "_longitude"] = leg.longitude
            end
            snapshot[fieldName .. "_nav_name"] = resolve_nav_name(ident, leg)
        end
    end

    for _, fieldName in ipairs({ "sid", "star" }) do
        local procedureIdent = clean_navigation_identifier(snapshot[fieldName])
        local navIdent = nav_ident_for_procedure(procedureIdent)
        if navIdent then
            local leg = find_route_leg(legs, navIdent, activeIndex)
            snapshot[fieldName .. "_nav_name"] = resolve_nav_name(navIdent, leg)
        end
    end
end

local function build_snapshot()
    local y = runtime.yal
    local def = runtime.def
    local sources = runtime.sources or {}
    local api = refs()
    local activeNavigationId = safe_read(y.fmsfplnnavid)
    local vectorLegActive = core.isVectorLegIdentifier(activeNavigationId)
    local vectorHeading = nil
    if vectorLegActive then
        local activeLegIndex = tonumber(safe_read(y.fmsvnavidx))
        vectorHeading = core.vectorHeadingForIndex(safe_read(y.fmslegscrsmag), activeLegIndex)
    end
    local snapshot = {
        on_ground = safe_read(y.airgroundsensor) == def.ON,
        radio_altitude_ft = tonumber(safe_read(y.radioaltitude)),
        altitude_ft = tonumber(safe_read(y.altitude_ft)) or tonumber(safe_read(y.altitude)),
        pressure_altitude_ft = tonumber(safe_read(sources.pressure_altitude)),
        vertical_speed_fpm = tonumber(safe_read(y.verticalspeed)),
        ground_speed_kts = tonumber(safe_read(y.groundspeed)),
        fms_phase = tonumber(safe_read(y.fmsflightphase)),
        tod_distance_nm = tonumber(safe_read(y.vnavtoddist)),
        transition_altitude_ft = tonumber(safe_read(y.fmctransalt)),
        transition_level_ft = tonumber(safe_read(y.fmctranslvl)),
        planned_altitude_ft = tonumber(safe_read(y.fmccruisealt)),
        mcp_altitude_ft = tonumber(safe_read(y.mcpaltitude)),
        departure_icao = tostring(safe_read(y.depicao) or ""),
        departure_runway = tostring(safe_read(y.deprwy) or ""),
        arrival_icao = tostring(safe_read(y.desicao) or ""),
        arrival_runway = tostring(safe_read(y.desrwy) or ""),
        sid = tostring(safe_read(y.fmsselectedsid) or ""),
        climb_next_waypoint = vectorLegActive and "" or tostring(activeNavigationId or ""),
        navigation_vector_active = vectorLegActive,
        navigation_vector_heading_deg = vectorHeading,
        star = tostring(safe_read(y.fmsselectedstar) or ""),
        approach_id = tostring(safe_read(y.fmsselectedapp) or ""),
        effective_callsign = clean_effective_callsign(safe_read(api and api.effective_callsign)),
        aircraft_type = tostring(safe_read(sources.aircraft_icao) or ""),
        preflight = y.flightstate == def.FLIGHTSTATEPREFLIGHT,
        initial_climb_state = y.flightstate == def.FLIGHTSTATEINITIALCLIMB,
        climb_state = y.flightstate == def.FLIGHTSTATECLIMB,
        descent_state = y.flightstate == def.FLIGHTSTATEAPPROACH,
        post_landing_state = y.flightstate == def.FLIGHTSTATETAXITOGATE
            or y.flightstate == def.FLIGHTSTATESHUTDOWN,
        descent_entry_kind = y.descentEntryReason,
        final_gate = false,
        short_final_gate = false
    }

    read_ofp_runtime(snapshot)
    read_approach_ref(snapshot)
    parse_approach_fallback(snapshot)

    local runwayGateOpen = false
    if y.isArrivalRunwayRadioAltGateOpen then
        local ok, value = pcall(y.isArrivalRunwayRadioAltGateOpen, 8, 20, 0.5)
        runwayGateOpen = ok and value == true
    end
    local procedureType = tostring(snapshot.approach_procedure_type or ""):upper()
    local resolvedKind = tostring(snapshot.approach_resolved_kind or ""):upper()
    local captureRequired = procedureType == "ILS" or procedureType == "LOC"
        or procedureType == "LDA" or procedureType == "GLS"
        or resolvedKind == "ILS" or resolvedKind == "IGS" or resolvedKind == "LOC"
        or resolvedKind == "LOC_GS" or resolvedKind == "LOC-GS" or resolvedKind == "LDA"
        or resolvedKind == "GLS" or resolvedKind == "LPV" or resolvedKind == "LP"
    local captured = (tonumber(safe_read(y.aploccapturedstat)) or 0) >= (def.CAPTURED or 2)
        or (tonumber(safe_read(y.aplpvloccapturedstat)) or 0) >= (def.CAPTURED or 2)
        or (tonumber(safe_read(y.apglsloccapturedstat)) or 0) >= (def.CAPTURED or 2)
        or (tonumber(safe_read(y.apfacloccapturedstat)) or 0) >= (def.CAPTURED or 2)
    snapshot.final_gate = runwayGateOpen and (not captureRequired or captured)
    if y.isArrivalShortFinal then
        local ok, value = pcall(y.isArrivalShortFinal)
        snapshot.short_final_gate = ok and value == true
    end

    return snapshot
end

local function read_mailbox_api()
    local api = refs()
    if type(api) ~= "table" then return {} end
    local apiVersion = tonumber(safe_read(api.api_version))
    local state = {
        api_version = apiVersion,
        ready = tonumber(safe_read(api.ready)),
        mode = tonumber(safe_read(api.mode)),
        transport_state = tonumber(safe_read(api.transport_state)),
        request_seq = tonumber(safe_read(api.request_seq)),
        result_seq = tonumber(safe_read(api.result_seq)),
        result_code = tonumber(safe_read(api.result_code)),
        result_detail = tostring(safe_read(api.result_detail) or "")
    }
    if apiVersion and apiVersion >= 2 then
        state.voice_state = tonumber(safe_read(api.voice_state))
        state.voice_result_seq = tonumber(safe_read(api.voice_result_seq))
        state.voice_result_code = tonumber(safe_read(api.voice_result_code))
        state.voice_result_detail = tostring(safe_read(api.voice_result_detail) or "")
    end
    if apiVersion == 3 then
        state.effective_callsign = clean_effective_callsign(safe_read(api.effective_callsign))
    end
    return state
end

local function capture_baseline_repeat_candidate(snapshot)
    if not snapshot or snapshot.on_ground == true then return end
    local phase = tonumber(snapshot.fms_phase) or 0
    local eventId = nil
    if snapshot.descent_state == true and (phase == 6 or phase == 7) then
        if snapshot.short_final_gate == true then
            eventId = "arrival.short_final"
        else
            eventId = snapshot.final_gate == true and "arrival.on_final" or "arrival.approach"
        end
    elseif snapshot.descent_state == true then
        eventId = "arrival.on_descent"
    elseif snapshot.climb_state == true then
        eventId = "departure.on_climb"
    elseif snapshot.initial_climb_state == true
        and (tonumber(snapshot.radio_altitude_ft) or 0) > 50 then
        eventId = "departure.airborne"
    end
    if not eventId then return end

    local text = core.buildMessage(eventId, snapshot)
    if not text then return end
    lastIntendedMessageText = text
    lastIntendedMessageVoiceText = core.buildVoiceMessage(
        eventId,
        snapshot,
        runtime.helpers and runtime.helpers.spellNato,
        text
    )
    log(string.format("IVAO Auto-Unicom: baseline repeat candidate event=%s text=%s", eventId, text))
end

function M.handleYalEvent(eventId, payload, now)
    if not runtime or not mailbox or not active then return false end
    if eventId == "arrival.go_around" then
        mailbox:cancelQueuedForGoAround()
        return true
    end

    local snapshot = build_snapshot()
    for key, value in pairs(payload or {}) do
        snapshot[key] = value
    end
    if eventId == "departure.flightplan_active" then
        read_preflight_parking(snapshot, runtime.yal)
    elseif eventId == "departure.start_push" then
        read_pushback_parking(snapshot, runtime.yal)
    elseif eventId == "arrival.parking_position" and snapshot.arrival_parking_found ~= true then
        read_arrival_parking(snapshot, runtime.yal)
    elseif eventId == "enroute.hold_enter" or eventId == "enroute.holding"
        or eventId == "enroute.hold_descending" then
        mailbox:cancelQueuedForHoldStart()
    elseif eventId == "enroute.hold_exit" then
        mailbox:cancelQueuedForHoldEnd()
    end
    enrich_station_names(snapshot)
    retain_station_names(snapshot)
    enrich_navigation_identifiers(snapshot)

    now = tonumber(now) or os.time()
    local event, reason = core.newEvent(
        eventId,
        snapshot,
        now,
        runtime.helpers and runtime.helpers.spellNato
    )
    if not event then
        log("IVAO Auto-Unicom: YAL event rejected event=" .. tostring(eventId)
            .. " reason=" .. tostring(reason)
            .. " inputs={" .. core.summarizeSources(snapshot) .. "}")
        return false
    end
    if not enqueue_event(event) then
        log("IVAO Auto-Unicom: YAL event rejected event=" .. tostring(eventId) .. " reason=queue_rejected")
        return false
    end
    return true
end

function M.repeatLastMessage(enabled)
    if enabled ~= true then
        log("IVAO Auto-Unicom: repeat last rejected reason=feature_disabled")
        return false, "feature_disabled"
    end
    if not runtime or not mailbox then
        log("IVAO Auto-Unicom: repeat last rejected reason=not_initialized")
        return false, "not_initialized"
    end

    local api = read_mailbox_api()
    if api.api_version ~= 3 or api.ready ~= 1 or tostring(api.effective_callsign or "") == "" then
        log("IVAO Auto-Unicom: repeat last rejected reason=api_unavailable")
        return false, "api_unavailable"
    end
    if api.mode ~= 2 then
        log("IVAO Auto-Unicom: repeat last rejected reason=send_mode_inactive")
        return false, "send_mode_inactive"
    end
    if mailbox.blocked then
        log("IVAO Auto-Unicom: repeat last rejected reason=transport_blocked")
        return false, "transport_blocked"
    end
    if mailbox.outstanding or #mailbox.queue > 0 then
        log("IVAO Auto-Unicom: repeat last rejected reason=request_pending")
        return false, "request_pending"
    end

    local apiRefs = refs()
    local source = "last_intended"
    local rawText = lastIntendedMessageText
    local rawVoiceText = lastIntendedMessageVoiceText
    if not rawText then
        source = "last_committed"
        rawText = lastCommittedMessageText
        rawVoiceText = lastCommittedMessageVoiceText
    end
    if not rawText then
        source = "api_request_text"
        rawText = safe_read(apiRefs and apiRefs.request_text)
        rawVoiceText = nil
    end
    local text = core.normalizeText(rawText)
    if not text then
        log("IVAO Auto-Unicom: repeat last rejected reason=no_last_message")
        return false, "no_last_message"
    end

    manualRepeatCount = manualRepeatCount + 1
    local now = os.time() or 0
    local accepted = enqueue_event({
        id = "manual.repeat_last." .. tostring(manualRepeatCount),
        text = text,
        voice_text = core.normalizeVoiceText(rawVoiceText),
        inputs = "source=" .. source,
        created_at = now,
        expires_at = now + 120
    })
    if not accepted then
        log("IVAO Auto-Unicom: repeat last rejected reason=queue_rejected")
        return false, "queue_rejected"
    end
    log("IVAO Auto-Unicom: repeat last accepted source=" .. source .. " text=" .. text)
    return true, text
end

function M.configure(options)
    runtime = options
    create_runtime_state()
    active = false
    connectionLogKey = nil
    callsignUnavailableLogged = false
    lastIntendedMessageText = nil
    lastIntendedMessageVoiceText = nil
    lastCommittedMessageText = nil
    lastCommittedMessageVoiceText = nil
    manualRepeatCount = 0
    stationNameCache = {}
end

function M.rebaseline()
    if not runtime then return end
    create_runtime_state()
    active = false
    connectionLogKey = nil
    callsignUnavailableLogged = false
    lastIntendedMessageText = nil
    lastIntendedMessageVoiceText = nil
    lastCommittedMessageText = nil
    lastCommittedMessageVoiceText = nil
    manualRepeatCount = 0
    stationNameCache = {}
end

function M.tick(enabled, now)
    if not runtime or not mailbox then return end
    now = tonumber(now) or os.time()

    if enabled ~= true then
        if active then
            mailbox:clear()
        end
        active = false
        connectionLogKey = nil
        callsignUnavailableLogged = false
        return
    end

    local api = read_mailbox_api()
    local apiCompatible = api.api_version == 3 and api.ready == 1
    local callsignAvailable = tostring(api.effective_callsign or "") ~= ""
    if apiCompatible and not callsignAvailable then
        if not callsignUnavailableLogged then
            callsignUnavailableLogged = true
            log("IVAO Auto-Unicom API ready but effective callsign is unavailable")
        end
    else
        callsignUnavailableLogged = false
    end
    local apiReady = apiCompatible and callsignAvailable
    if apiReady then
        local key = tostring(api.api_version) .. "|" .. tostring(api.mode)
        if connectionLogKey ~= key then
            connectionLogKey = key
            log("IVAO Auto-Unicom API connected version=" .. tostring(api.api_version) .. " mode=" .. tostring(api.mode))
        end
    end

    if not apiReady then
        if active then mailbox:clear() end
        active = false
        connectionLogKey = nil
        return
    end

    if not active then
        active = true
        local snapshot = build_snapshot()
        enrich_station_names(snapshot)
        retain_station_names(snapshot)
        enrich_navigation_identifiers(snapshot)
        capture_baseline_repeat_candidate(snapshot)
        mailbox:clear()
        log("IVAO Auto-Unicom enabled; waiting for YAL runtime events")
    end

    mailbox:tick(api, now)
end

function M.getDebugState()
    return {
        active = active,
        queue_depth = mailbox and #mailbox.queue or 0,
        outstanding_seq = mailbox and mailbox.outstanding and mailbox.outstanding.seq or nil,
        blocked = mailbox and mailbox.blocked or false
    }
end

return M
