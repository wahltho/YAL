local M = {}

M.EVENT_TTL_SEC = {
    ["departure.start_push"] = 60,
    ["departure.taxi_runway"] = 120,
    ["departure.lineup_takeoff"] = 45,
    ["departure.airborne"] = 60,
    ["departure.on_climb"] = 120,
    ["enroute.hold_enter"] = 120,
    ["enroute.hold_exit"] = 120,
    ["arrival.top_of_descent"] = 120,
    ["arrival.on_descent"] = 120,
    ["arrival.approach"] = 180,
    ["arrival.on_final"] = 60,
    ["arrival.runway_vacated"] = 120
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

local DESCENT_PROGRESS_PREFIX = "arrival.descent_level_"
local DESCENT_PROGRESS_LEVELS_FT = { 40000, 30000, 20000, 10000 }
local DESCENT_PROGRESS_MIN_SEPARATION_FT = 5000
local DESCENT_PROGRESS_MAX_SAMPLE_DROP_FT = 2000
local APPROACH_MERGE_LEVEL_FT = 10000
local CLIMB_PROGRESS_PREFIX = "departure.climb_level_"
local CLIMB_PROGRESS_LEVELS_FT = { 10000, 20000, 30000, 40000 }
local CLIMB_PROGRESS_MAX_SAMPLE_RISE_FT = 2000
local TAKEOFF_ROLL_SPEED_KTS = 25
local TAKEOFF_ROLL_HOLD_SEC = 2
local RUNWAY_VACATED_HOLD_SEC = 2
local HOLD_ENTER_EVENT_ID = "enroute.hold_enter"
local HOLD_EXIT_EVENT_ID = "enroute.hold_exit"

local function is_climb_progress_event(eventId)
    return type(eventId) == "string"
        and eventId:sub(1, #CLIMB_PROGRESS_PREFIX) == CLIMB_PROGRESS_PREFIX
end

local function is_descent_progress_event(eventId)
    return type(eventId) == "string"
        and eventId:sub(1, #DESCENT_PROGRESS_PREFIX) == DESCENT_PROGRESS_PREFIX
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

local PARKING_NAME_NOISE = {
    GATE = true,
    GATES = true,
    STAND = true,
    STANDS = true,
    PARKING = true,
    PARK = true,
    RAMP = true,
    APRON = true,
    TERMINAL = true,
    AIRCRAFT = true,
    START = true,
    POSITION = true,
    POS = true,
    HEAVY = true,
    JET = true,
    JETS = true,
    TURBOPROP = true,
    TURBOPROPS = true
}

local function pushback_parking_label(snapshot)
    if snapshot.pushback_parking_found ~= true then return nil end
    local rampType = tostring(snapshot.pushback_parking_type or ""):lower()
    if rampType ~= "gate" and rampType ~= "misc" then return nil end

    local rawName = tostring(snapshot.pushback_parking_name or "")
        :gsub("[|/_]", " ")
    local name = clean_token(rawName, true)
    if not name then return nil end
    if name == "CLASS" or name:sub(1, 6) == "CLASS "
        or name == "AIRCRAFT" or name:sub(1, 9) == "AIRCRAFT "
        or name == "RAMP START" or name:sub(1, 11) == "RAMP START " then
        return nil
    end
    local identifier = {}
    for token in name:gmatch("%S+") do
        if not PARKING_NAME_NOISE[token] then
            identifier[#identifier + 1] = token
        end
    end
    if #identifier == 0 then return nil end
    local text = table.concat(identifier, " ")
    if #text > 24 then return nil end
    return (rampType == "gate" and "gate " or "stand ") .. text
end

M.normalizeText = normalize_text
M.normalizeRunway = normalize_runway

local function aircraft_type(snapshot)
    return clean_token(snapshot.aircraft_type, false) or "B738"
end

local function hold_episode_key(snapshot)
    local waypoint = clean_token(snapshot.hold_waypoint, false)
    local pathType = clean_token(snapshot.hold_path_type, false)
    if not waypoint or (pathType ~= "HM" and pathType ~= "HA" and pathType ~= "HF") then return nil end
    return waypoint .. "|" .. pathType, waypoint, pathType
end

local function copy_hold_snapshot(snapshot)
    local result = {}
    for key, value in pairs(snapshot or {}) do result[key] = value end
    return result
end

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

local function arrival_context(snapshot)
    local airport = clean_token(snapshot.arrival_icao, false)
    local runway = normalize_runway(snapshot.arrival_runway)
    if not airport or #airport ~= 4 or not runway then return nil end
    return airport, runway
end

local function departure_context(snapshot)
    local airport = clean_token(snapshot.departure_icao, false)
    local runway = normalize_runway(snapshot.departure_runway)
    if not airport or #airport ~= 4 or not runway then return nil end
    return airport, runway
end

function M.buildMessage(eventId, snapshot)
    snapshot = snapshot or {}
    local ac = aircraft_type(snapshot)

    if eventId == "departure.start_push" then
        local airport = clean_token(snapshot.pushback_airport_icao, false)
            or clean_token(snapshot.departure_icao, false)
        if not airport or #airport ~= 4 then return nil, "missing_departure_context" end
        local parking = pushback_parking_label(snapshot)
        local text = string.format("%s Traffic, %s, pushing back", airport, ac)
        if parking then text = text .. " from " .. parking end
        return normalize_text(text)
    end

    if eventId == "departure.taxi_runway" then
        local airport, runway = departure_context(snapshot)
        if not airport then return nil, "missing_departure_context" end
        return normalize_text(string.format("%s Traffic, %s taxiing to holding point runway %s", airport, ac, runway))
    end

    if eventId == "departure.lineup_takeoff" then
        local airport, runway = departure_context(snapshot)
        if not airport then return nil, "missing_departure_context" end
        return normalize_text(string.format("%s Traffic, %s taking off runway %s", airport, ac, runway))
    end

    if eventId == "departure.airborne" then
        local airport, runway = departure_context(snapshot)
        local altitude = format_altitude(snapshot, false)
        if not airport or not altitude then return nil, "missing_departure_context" end
        return normalize_text(string.format("%s Traffic, %s airborne off runway %s, passing %s", airport, ac, runway, altitude))
    end

    if eventId == HOLD_ENTER_EVENT_ID or eventId == HOLD_EXIT_EVENT_ID then
        local waypoint = clean_token(snapshot.hold_waypoint, false)
        if not waypoint then return nil, "missing_hold_context" end
        if eventId == HOLD_ENTER_EVENT_ID then
            return normalize_text(string.format("Traffic, %s, entering a hold over %s", ac, waypoint))
        end
        return normalize_text(string.format("Traffic, %s, exiting hold over %s", ac, waypoint))
    end

    if eventId == "departure.on_climb" or is_climb_progress_event(eventId) then
        local airport = clean_token(snapshot.departure_icao, false)
        local altitude = format_altitude(snapshot, false)
        if not airport or #airport ~= 4 or not altitude then return nil, "missing_climb_context" end
        local sid = clean_token(snapshot.sid, false)
        local planned = format_planned_altitude(snapshot)
        local text = string.format("Traffic, %s climbing out of %s", ac, airport)
        if sid then text = text .. " on " .. sid .. " departure" end
        text = text .. ", passing " .. altitude
        if planned then text = text .. " for " .. planned end
        return normalize_text(text)
    end

    if eventId == "arrival.top_of_descent" then
        local airport, runway = arrival_context(snapshot)
        local altitude = format_altitude(snapshot, true)
        if not airport or not altitude then return nil, "missing_tod_context" end
        local star = clean_token(snapshot.star, false)
        local text = string.format("%s Traffic, %s,", airport, ac)
        if star then text = text .. " " .. star .. " arrival" end
        text = text .. " at TOD, leaving " .. altitude .. ", expecting runway " .. runway
        return normalize_text(text)
    end

    if eventId == "arrival.on_descent" or eventId == "arrival.approach"
        or is_descent_progress_event(eventId) then
        local airport, runway = arrival_context(snapshot)
        local altitude = format_altitude(snapshot, true)
        if not airport or not altitude then return nil, "missing_arrival_context" end
        local star = clean_token(snapshot.star, false)
        local approach = approach_label(snapshot)
        local text = string.format("%s Traffic, %s", airport, ac)
        if star then text = text .. " " .. star .. " arrival" end
        text = text .. " for "
        if approach then text = text .. approach .. " approach " end
        text = text .. "runway " .. runway .. ", on descent passing " .. altitude
        return normalize_text(text)
    end

    if eventId == "arrival.on_final" then
        local airport, runway = arrival_context(snapshot)
        if not airport then return nil, "missing_final_context" end
        local kind = clean_token(snapshot.approach_procedure_type, false)
        if kind == "ILS" then
            return normalize_text(string.format("%s Traffic, %s established on ILS runway %s", airport, ac, runway))
        elseif kind == "LOC" then
            return normalize_text(string.format("%s Traffic, %s established on Localizer runway %s", airport, ac, runway))
        end
        return normalize_text(string.format("%s Traffic, %s on final runway %s", airport, ac, runway))
    end

    if eventId == "arrival.runway_vacated" then
        local airport, runway = arrival_context(snapshot)
        if not airport then return nil, "missing_vacated_context" end
        return normalize_text(string.format("%s Traffic, runway %s vacated, taxiing to gate", airport, runway))
    end

    return nil, "unknown_event"
end

local function copy_snapshot(snapshot)
    local result = {}
    for key, value in pairs(snapshot or {}) do result[key] = value end
    return result
end

local function snapshot_at_altitude(snapshot, altitude)
    local frozen = copy_snapshot(snapshot)
    frozen.altitude_ft = altitude
    frozen.pressure_altitude_ft = altitude
    return frozen
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
        { "beforeTaxi", snapshot.before_taxi_started and 1 or 0 },
        { "beforeTaxiSource", snapshot.before_taxi_source },
        { "beforeTakeoff", snapshot.before_takeoff_started and 1 or 0 },
        { "beforeTakeoffSource", snapshot.before_takeoff_source },
        { "ra", snapshot.radio_altitude_ft },
        { "alt", snapshot.altitude_ft },
        { "pressureAlt", snapshot.pressure_altitude_ft },
        { "vs", snapshot.vertical_speed_fpm },
        { "gs", snapshot.ground_speed_kts },
        { "dep", snapshot.departure_icao },
        { "depRwy", snapshot.departure_runway },
        { "arr", snapshot.arrival_icao },
        { "arrRwy", snapshot.arrival_runway },
        { "sid", snapshot.sid },
        { "star", snapshot.star },
        { "app", snapshot.approach_id },
        { "tod", snapshot.tod_distance_nm },
        { "wheelSpeed", snapshot.wheel_speed },
        { "onDepRwy", snapshot.on_departure_runway and 1 or 0 },
        { "bpb", snapshot.pushback_active and 1 or 0 },
        { "pushAirport", snapshot.pushback_airport_icao },
        { "pushParking", snapshot.pushback_parking_found and 1 or 0 },
        { "pushParkingType", snapshot.pushback_parking_type },
        { "pushParkingName", snapshot.pushback_parking_name },
        { "pushParkingDist", snapshot.pushback_parking_distance_m },
        { "holdSource", snapshot.hold_source },
        { "holdApi", snapshot.hold_api_version },
        { "holdActive", snapshot.hold_active and 1 or 0 },
        { "holdEntryComplete", snapshot.hold_entry_complete and 1 or 0 },
        { "holdExitArmed", snapshot.hold_exit_armed and 1 or 0 },
        { "holdWaypoint", snapshot.hold_waypoint },
        { "holdPath", snapshot.hold_path_type },
        { "holdTarget", snapshot.hold_target_altitude_ft },
        { "holdLegacyNav", snapshot.hold_legacy_nav_mode },
        { "holdLegacyPhase", snapshot.hold_legacy_phase },
        { "holdLegacyTerm", snapshot.hold_legacy_term },
        { "arrClear", snapshot.arrival_runway_clear and 1 or 0 },
        { "final", snapshot.final_gate and 1 or 0 }
    }
    local parts = {}
    for _, field in ipairs(fields) do
        parts[#parts + 1] = field[1] .. "=" .. tostring(field[2] or "")
    end
    return table.concat(parts, " ")
end

M.summarizeSources = summarize_sources
M.snapshotAtAltitude = snapshot_at_altitude
M.holdEpisodeKey = hold_episode_key
M.isApproachPhase = is_approach_phase
M.CLIMB_PROGRESS_LEVELS_FT = CLIMB_PROGRESS_LEVELS_FT
M.DESCENT_PROGRESS_LEVELS_FT = DESCENT_PROGRESS_LEVELS_FT
M.DESCENT_PROGRESS_MIN_SEPARATION_FT = DESCENT_PROGRESS_MIN_SEPARATION_FT

function M.newEvent(eventId, snapshot, now)
    local text, reason = M.buildMessage(eventId, snapshot)
    if not text then return nil, reason end
    return {
        id = eventId,
        text = text,
        inputs = summarize_sources(snapshot),
        created_at = now,
        expires_at = now + (M.EVENT_TTL_SEC[eventId] or 120)
    }
end

local function add_candidate(candidates, eventId, snapshot, options)
    options = options or {}
    candidates[#candidates + 1] = {
        id = eventId,
        key = options.key or eventId,
        snapshot = snapshot,
        stable_for = tonumber(options.stable_for) or 0,
        consumes = options.consumes,
        report_altitude_ft = options.report_altitude_ft,
        min_report_separation_ft = options.min_report_separation_ft,
        cancel_hold_entry = options.cancel_hold_entry == true
    }
end

local function prior_climb_events(level)
    local consumed = {
        "departure.start_push",
        "departure.taxi_runway",
        "departure.lineup_takeoff",
        "departure.airborne",
        "departure.on_climb"
    }
    for _, prior in ipairs(CLIMB_PROGRESS_LEVELS_FT) do
        if prior < level then
            consumed[#consumed + 1] = CLIMB_PROGRESS_PREFIX .. tostring(prior)
        end
    end
    return consumed
end

local function prior_arrival_events(level)
    local consumed = { "arrival.top_of_descent", "arrival.on_descent" }
    for _, prior in ipairs(DESCENT_PROGRESS_LEVELS_FT) do
        if prior > level then
            consumed[#consumed + 1] = DESCENT_PROGRESS_PREFIX .. tostring(prior)
        end
    end
    return consumed
end

local function all_descent_events()
    local consumed = { "arrival.top_of_descent", "arrival.on_descent" }
    for _, level in ipairs(DESCENT_PROGRESS_LEVELS_FT) do
        consumed[#consumed + 1] = DESCENT_PROGRESS_PREFIX .. tostring(level)
    end
    return consumed
end

function M.collectEventCandidates(snapshot, previous)
    snapshot = snapshot or {}
    previous = previous or {}
    local candidates = {}
    local onGround = snapshot.on_ground == true
    local wheelSpeed = tonumber(snapshot.wheel_speed) or 0
    local forward = wheelSpeed > 1
    local reverse = wheelSpeed < -1
    local altitude = tonumber(snapshot.altitude_ft)
    local phase = tonumber(snapshot.fms_phase) or 0

    if onGround and snapshot.preflight == true
        and (snapshot.pushback_active == true or reverse) then
        add_candidate(candidates, "departure.start_push", snapshot, { stable_for = 2 })
    end
    if onGround and snapshot.before_taxi_started == true and forward
        and snapshot.pushback_active ~= true then
        add_candidate(candidates, "departure.taxi_runway", snapshot, {
            consumes = { "departure.start_push" }
        })
    end
    if onGround and snapshot.before_takeoff_started == true
        and snapshot.on_departure_runway == true and forward
        and (tonumber(snapshot.ground_speed_kts) or 0) >= TAKEOFF_ROLL_SPEED_KTS then
        add_candidate(candidates, "departure.lineup_takeoff", snapshot, {
            stable_for = TAKEOFF_ROLL_HOLD_SEC,
            consumes = { "departure.start_push", "departure.taxi_runway" }
        })
    end

    if not onGround and (snapshot.initial_climb_state == true or snapshot.climb_state == true)
        and (tonumber(snapshot.radio_altitude_ft) or 0) > 50 then
        add_candidate(candidates, "departure.airborne", snapshot, {
            consumes = {
                "departure.start_push",
                "departure.taxi_runway",
                "departure.lineup_takeoff"
            }
        })
    end
    if not onGround and snapshot.climb_state == true then
        add_candidate(candidates, "departure.on_climb", snapshot, {
            consumes = {
                "departure.start_push",
                "departure.taxi_runway",
                "departure.lineup_takeoff",
                "departure.airborne"
            }
        })
        if altitude then
            for _, level in ipairs(CLIMB_PROGRESS_LEVELS_FT) do
                if altitude >= level then
                    add_candidate(candidates, CLIMB_PROGRESS_PREFIX .. tostring(level),
                        snapshot_at_altitude(snapshot, level), {
                            consumes = prior_climb_events(level)
                        })
                end
            end
        end
    end

    local currentHoldKey = not onGround and snapshot.hold_active == true
        and hold_episode_key(snapshot) or nil
    local previousHoldKey = previous.on_ground ~= true and previous.hold_active == true
        and hold_episode_key(previous) or nil
    if previousHoldKey and previousHoldKey ~= currentHoldKey then
        add_candidate(candidates, HOLD_EXIT_EVENT_ID, copy_hold_snapshot(previous), {
            key = HOLD_EXIT_EVENT_ID .. "|" .. previousHoldKey,
            consumes = { HOLD_ENTER_EVENT_ID .. "|" .. previousHoldKey },
            cancel_hold_entry = true
        })
    end
    if currentHoldKey then
        add_candidate(candidates, HOLD_ENTER_EVENT_ID, snapshot, {
            key = HOLD_ENTER_EVENT_ID .. "|" .. currentHoldKey
        })
        if snapshot.hold_exit_armed == true then
            add_candidate(candidates, HOLD_EXIT_EVENT_ID, snapshot, {
                key = HOLD_EXIT_EVENT_ID .. "|" .. currentHoldKey,
                consumes = { HOLD_ENTER_EVENT_ID .. "|" .. currentHoldKey }
            })
        end
    end

    if not onGround and snapshot.descent_state == true then
        local descentEntryId = snapshot.descent_entry_kind == "tod"
            and "arrival.top_of_descent" or "arrival.on_descent"
        add_candidate(candidates, descentEntryId, snapshot, {
            consumes = {
                descentEntryId == "arrival.top_of_descent"
                    and "arrival.on_descent" or "arrival.top_of_descent"
            },
            report_altitude_ft = altitude
        })

        if altitude then
            for _, level in ipairs(DESCENT_PROGRESS_LEVELS_FT) do
                if altitude <= level then
                    local consumes = prior_arrival_events(level)
                    if level == APPROACH_MERGE_LEVEL_FT and is_approach_phase(phase) then
                        consumes[#consumes + 1] = "arrival.approach"
                    end
                    add_candidate(candidates, DESCENT_PROGRESS_PREFIX .. tostring(level),
                        snapshot_at_altitude(snapshot, level), {
                            consumes = consumes,
                            report_altitude_ft = level,
                            min_report_separation_ft = DESCENT_PROGRESS_MIN_SEPARATION_FT
                        })
                end
            end
        end

        if is_approach_phase(phase) and altitude and altitude <= APPROACH_MERGE_LEVEL_FT then
            add_candidate(candidates, "arrival.approach", snapshot, {
                consumes = all_descent_events()
            })
        end
        if is_approach_phase(phase) and snapshot.final_gate == true then
            local consumes = all_descent_events()
            consumes[#consumes + 1] = "arrival.approach"
            add_candidate(candidates, "arrival.on_final", snapshot, {
                stable_for = 5,
                consumes = consumes
            })
        end
    end

    if onGround and snapshot.post_landing_state == true
        and snapshot.arrival_runway_clear == true then
        local consumes = all_descent_events()
        consumes[#consumes + 1] = "arrival.approach"
        consumes[#consumes + 1] = "arrival.on_final"
        add_candidate(candidates, "arrival.runway_vacated", snapshot, {
            stable_for = RUNWAY_VACATED_HOLD_SEC,
            consumes = consumes
        })
    end

    return candidates
end

local Mailbox = {}
Mailbox.__index = Mailbox

local SUPERSEDED_EVENTS = {
    [HOLD_EXIT_EVENT_ID] = {
        [HOLD_ENTER_EVENT_ID] = true
    },
    ["departure.taxi_runway"] = {
        ["departure.start_push"] = true
    },
    ["departure.lineup_takeoff"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true
    },
    ["departure.airborne"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.lineup_takeoff"] = true
    },
    ["departure.on_climb"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
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
    ["arrival.runway_vacated"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true,
        ["arrival.approach"] = true,
        ["arrival.on_final"] = true
    }
}

local function supersedes_event(eventId, queuedId)
    local fixed = SUPERSEDED_EVENTS[eventId]
    if fixed and fixed[queuedId] then return true end
    if is_climb_progress_event(eventId) then
        return queuedId == "departure.start_push"
            or queuedId == "departure.taxi_runway"
            or queuedId == "departure.lineup_takeoff"
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
        or eventId == "arrival.runway_vacated" then
        return is_descent_progress_event(queuedId)
    end
    return false
end

function M.newMailbox(options)
    options = options or {}
    return setmetatable({
        writeText = options.writeText or function() return false end,
        writeSeq = options.writeSeq or function() return false end,
        log = options.log or function() end,
        queue = {},
        queuedIds = {},
        outstanding = nil,
        nextSeq = nil,
        blocked = false,
        maxQueue = tonumber(options.maxQueue) or 8,
        timeoutSec = tonumber(options.timeoutSec) or 30
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

function Mailbox:cancelQueuedForHoldEnd()
    local kept = {}
    for _, event in ipairs(self.queue) do
        if event.id == HOLD_ENTER_EVENT_ID then
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
        if resultSeq == self.outstanding.seq and TERMINAL_RESULTS[resultCode] then
            local completed = self.outstanding
            completed.result_code = resultCode
            completed.result_name = M.RESULT_NAMES[resultCode] or tostring(resultCode)
            completed.result_detail = tostring(api.result_detail or "")
            self.outstanding = nil
            self.log("terminal", completed)
        elseif now - self.outstanding.committed_at > self.timeoutSec then
            local timedOut = self.outstanding
            self.outstanding = nil
            self.blocked = true
            self.log("timeout", timedOut)
        end
        return
    end

    if self.blocked or #self.queue == 0 then return end
    if tonumber(api.api_version) ~= 1 or tonumber(api.ready) ~= 1 then return end
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
    if not self.writeText(event.text) then return end
    if not self.writeSeq(self.nextSeq) then
        self.blocked = true
        self.log("sequence_write_failed", event)
        return
    end

    table.remove(self.queue, 1)
    self.queuedIds[event.id] = nil
    event.seq = self.nextSeq
    event.committed_at = now
    self.nextSeq = self.nextSeq + 1
    self.outstanding = event
    self.log("committed", event)
end

return M
