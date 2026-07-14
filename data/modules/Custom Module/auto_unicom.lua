local core = require("auto_unicom_core")

local M = {}
local runtime = nil
local eventEngine = nil
local mailbox = nil
local active = false
local lastSampleAt = nil
local connectionLogKey = nil
local lastIntendedMessageText = nil
local lastCommittedMessageText = nil
local manualRepeatCount = 0
local PUSHBACK_PARKING_MAX_DISTANCE_M = 80
local HOLD_RUNTIME_SNAPSHOT_ATTEMPTS = 3
local HOLD_PATH_TYPES = { HM = true, HA = true, HF = true }

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

local function event_engine_log(kind, event)
    event = event or {}
    if kind == "taxi_emit_rejected" then
        log("IVAO Auto-Unicom: taxi event rejected reason=" .. tostring(event.reason or "unknown")
            .. " gates={" .. tostring(event.inputs or "") .. "}")
    elseif kind == "climb_level_rejected" or kind == "descent_level_rejected" then
        log("IVAO Auto-Unicom: level event rejected event=" .. tostring(event.event_id or "unknown")
            .. " reason=" .. tostring(event.reason or "unknown")
            .. " gates={" .. tostring(event.inputs or "") .. "}")
    elseif kind == "ground_baseline_deferred" then
        log("IVAO Auto-Unicom: departure ground baseline deferred gates={"
            .. tostring(event.inputs or "") .. "}")
    elseif kind == "ground_cycle_reset" then
        log("IVAO Auto-Unicom: departure ground cycle armed gates={"
            .. tostring(event.inputs or "") .. "}")
    end
end

local function create_state_machines()
    mailbox = core.newMailbox({
        writeText = write_request_text,
        writeSeq = write_request_seq,
        log = mailbox_log,
        maxQueue = 8,
        timeoutSec = 30
    })
    eventEngine = core.newEventEngine({
        emit = enqueue_event,
        cancelQueuedForGoAround = function()
            if mailbox then mailbox:cancelQueuedForGoAround() end
        end,
        cancelQueuedForHoldEnd = function()
            if mailbox then mailbox:cancelQueuedForHoldEnd() end
        end,
        log = event_engine_log
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

local function normalize_hold_waypoint(value)
    local text = tostring(value or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" or #text > 16 then return nil end
    for index = 1, #text do
        local byte = text:byte(index)
        local valid = (byte >= 48 and byte <= 57)
            or (byte >= 65 and byte <= 90)
            or byte == 45
        if not valid then return nil end
    end
    return text
end

local function normalize_hold_path(value)
    local path = tostring(value or ""):upper():gsub("^%s+", ""):gsub("%s+$", "")
    if HOLD_PATH_TYPES[path] then return path end
    return nil
end

local function is_binary_number(value)
    return value == 0 or value == 1
end

local function read_hold_runtime_api(y)
    local api = y and y.holdRuntime or nil
    if type(api) ~= "table" or (tonumber(safe_read(api.api_version)) or 0) < 1 then return nil end

    for _ = 1, HOLD_RUNTIME_SNAPSHOT_ATTEMPTS do
        local seqBefore = tonumber(safe_read(api.update_seq))
        if seqBefore and seqBefore % 2 == 0 then
            local active = tonumber(safe_read(api.active))
            local entryComplete = tonumber(safe_read(api.entry_complete))
            local exitArmed = tonumber(safe_read(api.exit_armed))
            local waypointRaw = safe_read(api.waypoint)
            local pathRaw = safe_read(api.path_type)
            local targetAltitude = tonumber(safe_read(api.target_altitude_ft))
            local targetValid = tonumber(safe_read(api.target_altitude_valid))
            local seqAfter = tonumber(safe_read(api.update_seq))

            if seqAfter == seqBefore and seqAfter % 2 == 0
                and is_binary_number(active)
                and is_binary_number(entryComplete)
                and is_binary_number(exitArmed)
                and waypointRaw ~= nil and pathRaw ~= nil
                and targetAltitude ~= nil and is_binary_number(targetValid) then
                local waypoint = normalize_hold_waypoint(waypointRaw)
                local pathType = normalize_hold_path(pathRaw)
                if active == 0 or (waypoint and pathType) then
                    return {
                        source = "api",
                        api_version = tonumber(safe_read(api.api_version)) or 0,
                        active = active == 1,
                        entry_complete = active == 1 and entryComplete == 1,
                        exit_armed = active == 1 and exitArmed == 1,
                        waypoint = active == 1 and waypoint or nil,
                        path_type = active == 1 and pathType or nil,
                        target_altitude_ft = active == 1 and targetValid == 1 and targetAltitude > 0
                            and targetAltitude or nil,
                        target_altitude_valid = active == 1 and targetValid == 1 and targetAltitude > 0
                    }
                end
            end
        end
    end
    return nil
end

local function read_hold_legacy(y)
    local navMode = tonumber(safe_read(y and y.fmsnavmode))
    local pathType = normalize_hold_path(safe_read(y and y.fmsgpswptpath))
    local waypoint = normalize_hold_waypoint(safe_read(y and y.fmsfplnnavid))
    local holdPhase = tonumber(safe_read(y and y.fmsholdphase))
    local holdTerm = tonumber(safe_read(y and y.fmsholdterm))
    local active = navMode == 3 and pathType ~= nil and waypoint ~= nil
    return {
        source = "legacy",
        active = active,
        entry_complete = nil,
        exit_armed = active and holdTerm ~= nil and holdTerm > 1,
        waypoint = active and waypoint or nil,
        path_type = active and pathType or nil,
        target_altitude_ft = nil,
        target_altitude_valid = false,
        legacy_nav_mode = navMode,
        legacy_hold_phase = holdPhase,
        legacy_hold_term = holdTerm
    }
end

local function read_hold_state(snapshot, y)
    local hold = read_hold_runtime_api(y) or read_hold_legacy(y)
    snapshot.hold_source = hold.source
    snapshot.hold_api_version = hold.api_version
    snapshot.hold_active = hold.active == true
    snapshot.hold_entry_complete = hold.entry_complete == true
    snapshot.hold_exit_armed = hold.exit_armed == true
    snapshot.hold_waypoint = hold.waypoint
    snapshot.hold_path_type = hold.path_type
    snapshot.hold_target_altitude_ft = hold.target_altitude_ft
    snapshot.hold_target_altitude_valid = hold.target_altitude_valid == true
    snapshot.hold_legacy_nav_mode = hold.legacy_nav_mode
    snapshot.hold_legacy_phase = hold.legacy_hold_phase
    snapshot.hold_legacy_term = hold.legacy_hold_term
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

local function procedure_started_or_done(y, procedureId)
    local loops = { y.procedureloop1, y.procedureloop2, y.procedureloop3 }
    for _, loop in ipairs(loops) do
        if loop and loop.lock == procedureId and (tonumber(loop.stepindex) or 0) > 0 then
            return true, "active_loop"
        end
    end

    local procedure = y.proceduretable and y.proceduretable[procedureId] or nil
    if procedure and procedure.set == true then return true, "memory_set" end

    local persistentStatus = tonumber(safe_read(y.ProcSetStatusarraydr, procedureId))
    if persistentStatus == 1 then return true, "state_dataref" end
    return false, "none"
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

local function read_pushback_parking(snapshot, y)
    local wheelSpeed = tonumber(snapshot.wheel_speed) or 0
    local pushbackCandidate = snapshot.on_ground == true and snapshot.preflight == true
        and (snapshot.pushback_active == true or wheelSpeed < -1)
    if not pushbackCandidate then return end

    local helpers = runtime and runtime.helpers or nil
    local airport = normalize_icao(safe_read(y.nearesticao))
        or normalize_icao(snapshot.departure_icao)
    snapshot.pushback_airport_icao = airport
    if not airport or not helpers or not helpers.getNearestRamp or not helpers.isRampSuitableFor738 then return end

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
        lon,
        { filter = helpers.isRampSuitableFor738 }
    )
    distanceSquared = tonumber(distanceSquared)
    if not ok or not ramp or not distanceSquared or distanceSquared < 0
        or distanceSquared > PUSHBACK_PARKING_MAX_DISTANCE_M * PUSHBACK_PARKING_MAX_DISTANCE_M then
        return
    end

    local rampType = tostring(ramp.ramp_type or ""):lower()
    if rampType ~= "gate" and rampType ~= "misc" then return end
    snapshot.pushback_parking_found = true
    snapshot.pushback_parking_type = rampType
    snapshot.pushback_parking_name = tostring(ramp.name or "")
    snapshot.pushback_parking_distance_m = math.sqrt(distanceSquared)
end

local function build_snapshot()
    local y = runtime.yal
    local def = runtime.def
    local sources = runtime.sources or {}
    local wheelSpeed = tonumber(safe_read(y.tirespeed)) or 0
    local beforeTaxiStarted, beforeTaxiSource = procedure_started_or_done(y, def.BEFORETAXIPROCEDURE)
    local beforeTakeoffStarted, beforeTakeoffSource = procedure_started_or_done(y, def.BEFORETAKEOFFPROCEDURE)
    local snapshot = {
        on_ground = safe_read(y.airgroundsensor) == def.ON,
        radio_altitude_ft = tonumber(safe_read(y.radioaltitude)),
        altitude_ft = tonumber(safe_read(y.altitude_ft)) or tonumber(safe_read(y.altitude)),
        pressure_altitude_ft = tonumber(safe_read(sources.pressure_altitude)),
        vertical_speed_fpm = tonumber(safe_read(y.verticalspeed)),
        ground_speed_kts = tonumber(safe_read(y.groundspeed)),
        wheel_speed = wheelSpeed,
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
        before_taxi_started = beforeTaxiStarted,
        before_taxi_source = beforeTaxiSource,
        before_takeoff_started = beforeTakeoffStarted,
        before_takeoff_source = beforeTakeoffSource,
        pushback_active = y.BPBStarted ~= nil
            and tonumber(safe_read(y.BPBStarted)) == def.ON
            and (y.BPBOpComplete == nil or tonumber(safe_read(y.BPBOpComplete)) ~= def.ON),
        on_departure_runway = false,
        arrival_runway_clear = false,
        final_gate = false
    }

    read_pushback_parking(snapshot, y)
    read_hold_state(snapshot, y)

    if y.aircraftonrwy then
        local ok, value = pcall(y.aircraftonrwy, def.DEPARTURE, 40, 20)
        snapshot.on_departure_runway = ok and value == true
    end
    if y.isAircraftOnArrivalRunwaySurface then
        local ok, value = pcall(y.isAircraftOnArrivalRunwaySurface, 40)
        snapshot.arrival_runway_clear = ok and value == false
    end

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
    if phase == 6 or phase == 7 then
        eventId = snapshot.final_gate == true and "arrival.on_final" or "arrival.approach"
    elseif phase == 4 or phase == 5 then
        eventId = "arrival.on_descent"
    elseif phase == 1 then
        eventId = "departure.on_climb"
    elseif phase == 0 and (tonumber(snapshot.radio_altitude_ft) or 0) > 50 then
        eventId = "departure.airborne"
    end
    if not eventId then return end

    local text = core.buildMessage(eventId, snapshot)
    if not text then return end
    lastIntendedMessageText = text
    log(string.format("IVAO Auto-Unicom: baseline repeat candidate event=%s text=%s", eventId, text))
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
    create_state_machines()
    active = false
    lastSampleAt = nil
    connectionLogKey = nil
    lastIntendedMessageText = nil
    lastCommittedMessageText = nil
    manualRepeatCount = 0
end

function M.rebaseline()
    if not runtime then return end
    create_state_machines()
    active = false
    lastSampleAt = nil
    connectionLogKey = nil
    lastIntendedMessageText = nil
    lastCommittedMessageText = nil
    manualRepeatCount = 0
end

function M.tick(enabled, now)
    if not runtime or not eventEngine or not mailbox then return end
    now = tonumber(now) or os.time()

    if enabled ~= true then
        if active then
            eventEngine:deactivate()
            mailbox:clear()
        end
        active = false
        lastSampleAt = nil
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
        eventEngine:activate(snapshot, now)
        capture_baseline_repeat_candidate(snapshot)
        mailbox:clear()
        lastSampleAt = now
        log("IVAO Auto-Unicom enabled; current flight state baselined without event backfill")
    elseif not lastSampleAt or now - lastSampleAt >= 1 then
        lastSampleAt = now
        eventEngine:update(build_snapshot(), now)
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
