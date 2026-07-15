local core = require("auto_unicom_core")

local M = {}
local runtime = nil
local mailbox = nil
local active = false
local connectionLogKey = nil
local lastIntendedMessageText = nil
local lastCommittedMessageText = nil
local manualRepeatCount = 0
local PUSHBACK_PARKING_MAX_DISTANCE_M = 80
local ARRIVAL_PARKING_MAX_DISTANCE_M = 35

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

local function mailbox_log(kind, event)
    if kind == "committed" then
        lastCommittedMessageText = event.text
        log(string.format("IVAO Auto-Unicom: committed event=%s seq=%s text=%s",
            tostring(event.id), tostring(event.seq), tostring(event.text)))
    elseif kind == "terminal" then
        log(string.format("IVAO Auto-Unicom: terminal event=%s seq=%s result=%s detail=%s",
            tostring(event.id), tostring(event.seq), tostring(event.result_name), tostring(event.result_detail or "")))
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
    if intendedText then lastIntendedMessageText = intendedText end
    if not mailbox or not mailbox:enqueue(event) then return false end
    log(string.format("IVAO Auto-Unicom: queued event=%s inputs={%s} text=%s",
        tostring(event.id), tostring(event.inputs or ""), tostring(event.text)))
    return true
end

local function create_runtime_state()
    mailbox = core.newMailbox({
        writeText = write_request_text,
        writeSeq = write_request_seq,
        log = mailbox_log,
        maxQueue = 8,
        timeoutSec = 30
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

local function read_nearest_parking(snapshot, y, airport, prefix, maxDistanceMeters)
    local helpers = runtime and runtime.helpers or nil
    if not airport or not helpers or not helpers.getNearestRamp then return end

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
end

local function read_pushback_parking(snapshot, y)
    local airport = normalize_icao(safe_read(y.nearesticao))
        or normalize_icao(snapshot.departure_icao)
    snapshot.pushback_airport_icao = airport
    read_nearest_parking(snapshot, y, airport, "pushback_parking", PUSHBACK_PARKING_MAX_DISTANCE_M)
end

local function read_arrival_parking(snapshot, y)
    local arrivalAirport = normalize_icao(snapshot.arrival_icao)
    local searchAirport = normalize_icao(safe_read(y.nearesticao)) or arrivalAirport
    snapshot.arrival_parking_airport_icao = arrivalAirport or searchAirport
    read_nearest_parking(snapshot, y, searchAirport, "arrival_parking", ARRIVAL_PARKING_MAX_DISTANCE_M)
end

local function build_snapshot()
    local y = runtime.yal
    local def = runtime.def
    local sources = runtime.sources or {}
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
        departure_icao = tostring(safe_read(y.depicao) or ""),
        departure_runway = tostring(safe_read(y.deprwy) or ""),
        arrival_icao = tostring(safe_read(y.desicao) or ""),
        arrival_runway = tostring(safe_read(y.desrwy) or ""),
        sid = tostring(safe_read(y.fmsselectedsid) or ""),
        star = tostring(safe_read(y.fmsselectedstar) or ""),
        approach_id = tostring(safe_read(y.fmsselectedapp) or ""),
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
    return {
        api_version = tonumber(safe_read(api.api_version)),
        ready = tonumber(safe_read(api.ready)),
        mode = tonumber(safe_read(api.mode)),
        transport_state = tonumber(safe_read(api.transport_state)),
        request_seq = tonumber(safe_read(api.request_seq)),
        result_seq = tonumber(safe_read(api.result_seq)),
        result_code = tonumber(safe_read(api.result_code)),
        result_detail = tostring(safe_read(api.result_detail) or "")
    }
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
    if eventId == "departure.start_push" then
        read_pushback_parking(snapshot, runtime.yal)
    elseif eventId == "arrival.parking_position" and snapshot.arrival_parking_found ~= true then
        read_arrival_parking(snapshot, runtime.yal)
    elseif eventId == "enroute.hold_exit" then
        mailbox:cancelQueuedForHoldEnd()
    end

    now = tonumber(now) or os.time()
    local event, reason = core.newEvent(eventId, snapshot, now)
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
    if api.api_version ~= 1 or api.ready ~= 1 then
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
    if not rawText then
        source = "last_committed"
        rawText = lastCommittedMessageText
    end
    if not rawText then
        source = "api_request_text"
        rawText = safe_read(apiRefs and apiRefs.request_text)
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
    lastIntendedMessageText = nil
    lastCommittedMessageText = nil
    manualRepeatCount = 0
end

function M.rebaseline()
    if not runtime then return end
    create_runtime_state()
    active = false
    connectionLogKey = nil
    lastIntendedMessageText = nil
    lastCommittedMessageText = nil
    manualRepeatCount = 0
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
        return
    end

    local api = read_mailbox_api()
    if api.api_version == 1 and api.ready == 1 then
        local key = tostring(api.api_version) .. "|" .. tostring(api.mode)
        if connectionLogKey ~= key then
            connectionLogKey = key
            log("IVAO Auto-Unicom API connected version=" .. tostring(api.api_version) .. " mode=" .. tostring(api.mode))
        end
    end

    if not active then
        active = true
        local snapshot = build_snapshot()
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
