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

local function safe_read(prop)
    if not prop then return nil end
    if isProperty and not isProperty(prop) then return nil end
    local reader = runtime and runtime.read or get
    local ok, value = pcall(reader, prop)
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

local function create_state_machines()
    mailbox = core.newMailbox({
        writeText = write_request_text,
        writeSeq = write_request_seq,
        log = mailbox_log,
        maxQueue = 8,
        timeoutSec = 30
    })
    eventEngine = core.newEventEngine({ emit = enqueue_event })
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

local function procedure_started_or_done(y, procedureId)
    local procedure = y.proceduretable and y.proceduretable[procedureId] or nil
    if procedure and procedure.set == true then return true end

    local loops = { y.procedureloop1, y.procedureloop2, y.procedureloop3 }
    for _, loop in ipairs(loops) do
        if loop and loop.lock == procedureId then return true end
    end
    return false
end

local function build_snapshot()
    local y = runtime.yal
    local def = runtime.def
    local sources = runtime.sources or {}
    local wheelSpeed = tonumber(safe_read(y.tirespeed)) or 0
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
        before_taxi_started = procedure_started_or_done(y, def.BEFORETAXIPROCEDURE),
        before_takeoff_started = procedure_started_or_done(y, def.BEFORETAKEOFFPROCEDURE),
        parking_brake_released = (tonumber(safe_read(y.parkingbrakepos)) or 0) == def.OFF,
        eng1_n1_percent = tonumber(safe_read(y.eng1n1percent)),
        eng2_n1_percent = tonumber(safe_read(y.eng2n1percent)),
        pushback_active = y.BPBStarted ~= nil
            and tonumber(safe_read(y.BPBStarted)) == def.ON
            and (y.BPBOpComplete == nil or tonumber(safe_read(y.BPBOpComplete)) ~= def.ON),
        on_departure_runway = false,
        on_runway_profile = false,
        final_gate = false
    }

    if y.aircraftonrwy then
        local ok, value = pcall(y.aircraftonrwy, def.DEPARTURE, 40, 20)
        snapshot.on_departure_runway = ok and value == true
    end

    read_approach_ref(snapshot)
    parse_approach_fallback(snapshot)

    local runway = nil
    if y.getDestinationRunwayRefdata then
        local ok, value = pcall(y.getDestinationRunwayRefdata, true)
        if ok then runway = value end
    end
    local position = {
        lat = tonumber(safe_read(y.aircraftlatpos)),
        lon = tonumber(safe_read(y.aircraftlonpos))
    }
    local metrics = core.runwayMetrics(position, runway)
    if metrics then
        snapshot.on_runway_profile = metrics.on_profile == true
        snapshot.runway_threshold_distance_nm = metrics.threshold_distance_nm
        snapshot.runway_cross_track_nm = metrics.cross_track_m / 1852
    end

    local runwayCourse = runway and tonumber(runway.course_deg_mag) or nil
    local aircraftTrack = tonumber(safe_read(y.groundtrackmag))
    local trackDiff = nil
    if runwayCourse and aircraftTrack and runtime.helpers and runtime.helpers.headingdiff then
        trackDiff = runtime.helpers.headingdiff(aircraftTrack, runwayCourse)
    end
    snapshot.runway_track_diff_deg = trackDiff

    local procedureType = tostring(snapshot.approach_procedure_type or ""):upper()
    local localizerProcedure = procedureType == "ILS" or procedureType == "LOC"
    local localizerCaptured = (tonumber(safe_read(y.aploccapturedstat)) or 0) >= (def.CAPTURED or 2)
    snapshot.final_gate = metrics ~= nil
        and metrics.threshold_distance_nm <= 8
        and metrics.cross_track_m <= (0.5 * 1852)
        and trackDiff ~= nil and trackDiff <= 20
        and (not localizerProcedure or localizerCaptured)

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
