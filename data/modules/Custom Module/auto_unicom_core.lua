local M = {}

M.EVENT_TTL_SEC = {
    ["departure.start_push"] = 60,
    ["departure.taxi_runway"] = 120,
    ["departure.hold_short"] = 120,
    ["departure.backtrack"] = 90,
    ["departure.intersection"] = 60,
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
local CLIMB_PROGRESS_PREFIX = "departure.climb_level_"
local HOLD_ENTER_EVENT_ID = "enroute.hold_enter"
local HOLDING_EVENT_ID = "enroute.holding"
local HOLD_DESCENDING_EVENT_ID = "enroute.hold_descending"
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

local function parking_label(snapshot, prefix)
    if snapshot[prefix .. "_found"] ~= true then return nil end
    local rampType = tostring(snapshot[prefix .. "_type"] or ""):lower()

    local rawName = tostring(snapshot[prefix .. "_name"] or "")
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
    local ac = aircraft_type(snapshot)

    if eventId == "departure.start_push" then
        local airport = clean_token(snapshot.pushback_airport_icao, false)
            or clean_token(snapshot.departure_icao, false)
        if not airport or #airport ~= 4 then return nil, "missing_departure_context" end
        local parking = parking_label(snapshot, "pushback_parking")
        local text = string.format("%s Traffic, %s, pushing back", airport, ac)
        if parking then text = text .. " from " .. parking end
        return normalize_text(text)
    end

    if eventId == "departure.taxi_runway" then
        local airport, runway = departure_context(snapshot)
        if not airport then return nil, "missing_departure_context" end
        return normalize_text(string.format("%s Traffic, %s taxiing to holding point runway %s", airport, ac, runway))
    end

    if eventId == "departure.hold_short" then
        local airport, runway = departure_context(snapshot)
        if not airport then return nil, "missing_departure_context" end
        local intersection = departure_intersection(snapshot)
        if intersection then
            return normalize_text(string.format(
                "%s Traffic, %s, holding short of intersection %s",
                airport,
                ac,
                intersection
            ))
        end
        return normalize_text(string.format(
            "%s Traffic, %s, holding short of holding point runway %s",
            airport,
            ac,
            runway
        ))
    end

    if eventId == "departure.backtrack" then
        local airport, runway = departure_context(snapshot)
        if not airport then return nil, "missing_departure_context" end
        local text = string.format("%s Traffic, %s backtracking runway %s", airport, ac, runway)
        local intersection = departure_intersection(snapshot)
        if intersection then text = text .. ", intersection " .. intersection end
        return normalize_text(text)
    end

    if eventId == "departure.intersection" then
        local airport, runway = departure_context(snapshot)
        local intersection = departure_intersection(snapshot)
        if not airport or not intersection then return nil, "missing_intersection_context" end
        local text = string.format(
            "%s Traffic, %s lining up and taking off runway %s, intersection %s",
            airport,
            ac,
            runway,
            intersection
        )
        local sid = clean_token(snapshot.sid, false)
        if sid then text = text .. ", " .. sid .. " departure" end
        return normalize_text(text)
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

    if eventId == HOLD_ENTER_EVENT_ID or eventId == HOLDING_EVENT_ID
        or eventId == HOLD_DESCENDING_EVENT_ID or eventId == HOLD_EXIT_EVENT_ID then
        local waypoint = clean_token(snapshot.hold_waypoint, false)
        if not waypoint then return nil, "missing_hold_context" end
        if eventId == HOLD_ENTER_EVENT_ID then
            return normalize_text(string.format("Traffic, %s, entering a hold over %s", ac, waypoint))
        end
        if eventId == HOLDING_EVENT_ID then
            local altitude = format_altitude(snapshot, false)
            if not altitude then return nil, "missing_hold_context" end
            return normalize_text(string.format(
                "Traffic, %s maintaining %s whilst holding over %s",
                ac,
                altitude,
                waypoint
            ))
        end
        if eventId == HOLD_DESCENDING_EVENT_ID then
            local altitude = format_altitude(snapshot, true)
            local target = format_hold_target_altitude(snapshot)
            if not altitude or not target then return nil, "missing_hold_descent_context" end
            return normalize_text(string.format(
                "Traffic, %s, in a hold over %s on descent passing %s for %s",
                ac,
                waypoint,
                altitude,
                target
            ))
        end
        return normalize_text(string.format("Traffic, %s, exiting hold over %s", ac, waypoint))
    end

    if eventId == "enroute.in_cruise" then
        local waypoint = clean_token(snapshot.cruise_waypoint, false)
        local altitude = format_altitude(snapshot, false)
        if not waypoint or not altitude then return nil, "missing_cruise_context" end
        return normalize_text(string.format(
            "Traffic, %s passing %s, maintaining %s",
            ac,
            waypoint,
            altitude
        ))
    end

    if eventId == "departure.on_climb" or is_climb_progress_event(eventId) then
        local airport = clean_token(snapshot.departure_icao, false)
        local altitude = format_altitude(snapshot, false)
        if not airport or #airport ~= 4 or not altitude then return nil, "missing_climb_context" end
        local nextWaypoint = clean_token(snapshot.climb_next_waypoint, false)
        local planned = format_planned_altitude(snapshot)
        local text = string.format("Traffic, %s climbing out of %s", ac, airport)
        text = text .. ", passing " .. altitude
        if planned then text = text .. " for " .. planned end
        if nextWaypoint then text = text .. ", " .. nextWaypoint .. " next" end
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

    if eventId == "arrival.short_final" then
        local airport, runway = arrival_context(snapshot)
        if not airport then return nil, "missing_short_final_context" end
        return normalize_text(string.format(
            "%s Traffic, %s on SHORT FINAL runway %s - Landing is imminent",
            airport,
            ac,
            runway
        ))
    end

    if eventId == "arrival.backtrack" then
        local airport, runway = arrival_context(snapshot)
        if not airport then return nil, "missing_arrival_backtrack_context" end
        return normalize_text(string.format("%s Traffic, %s backtracking runway %s", airport, ac, runway))
    end

    if eventId == "arrival.runway_vacated" then
        local airport, runway = arrival_context(snapshot)
        if not airport then return nil, "missing_vacated_context" end
        return normalize_text(string.format("%s Traffic, runway %s vacated, taxiing to gate", airport, runway))
    end

    if eventId == "arrival.parking_position" then
        local airport = clean_token(snapshot.arrival_parking_airport_icao, false)
            or clean_token(snapshot.arrival_icao, false)
        if not airport or #airport ~= 4 or snapshot.arrival_parking_found ~= true then
            return nil, "missing_arrival_parking_context"
        end
        local parking = parking_label(snapshot, "arrival_parking")
        local text = string.format("%s Traffic, %s parked", airport, ac)
        if parking then
            text = text .. " at " .. parking
        else
            text = text .. " at parking position"
        end
        return normalize_text(text)
    end

    return nil, "unknown_event"
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
        { "dep", snapshot.departure_icao },
        { "depRwy", snapshot.departure_runway },
        { "arr", snapshot.arrival_icao },
        { "arrRwy", snapshot.arrival_runway },
        { "sid", snapshot.sid },
        { "climbNext", snapshot.climb_next_waypoint },
        { "star", snapshot.star },
        { "app", snapshot.approach_id },
        { "tod", snapshot.tod_distance_nm },
        { "pushAirport", snapshot.pushback_airport_icao },
        { "pushParking", snapshot.pushback_parking_found and 1 or 0 },
        { "pushParkingType", snapshot.pushback_parking_type },
        { "pushParkingName", snapshot.pushback_parking_name },
        { "pushParkingDist", snapshot.pushback_parking_distance_m },
        { "holdSource", snapshot.hold_source },
        { "holdWaypoint", snapshot.hold_waypoint },
        { "holdPath", snapshot.hold_path_type },
        { "holdEntryComplete", snapshot.hold_entry_complete and 1 or 0 },
        { "holdTarget", snapshot.hold_target_altitude_ft },
        { "cruiseWaypoint", snapshot.cruise_waypoint },
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
    ["departure.taxi_runway"] = {
        ["departure.start_push"] = true
    },
    ["departure.hold_short"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true
    },
    ["departure.backtrack"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.hold_short"] = true
    },
    ["departure.intersection"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true,
        ["departure.lineup_takeoff"] = true
    },
    ["departure.lineup_takeoff"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true
    },
    ["departure.airborne"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true,
        ["departure.intersection"] = true,
        ["departure.lineup_takeoff"] = true
    },
    ["departure.on_climb"] = {
        ["departure.start_push"] = true,
        ["departure.taxi_runway"] = true,
        ["departure.hold_short"] = true,
        ["departure.backtrack"] = true,
        ["departure.intersection"] = true,
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
    ["arrival.parking_position"] = {
        ["arrival.top_of_descent"] = true,
        ["arrival.on_descent"] = true,
        ["arrival.approach"] = true,
        ["arrival.on_final"] = true,
        ["arrival.short_final"] = true,
        ["arrival.backtrack"] = true,
        ["arrival.runway_vacated"] = true
    }
}

local function supersedes_event(eventId, queuedId)
    local fixed = SUPERSEDED_EVENTS[eventId]
    if fixed and fixed[queuedId] then return true end
    if is_climb_progress_event(eventId) then
        return queuedId == "departure.start_push"
            or queuedId == "departure.taxi_runway"
            or queuedId == "departure.hold_short"
            or queuedId == "departure.backtrack"
            or queuedId == "departure.intersection"
            or queuedId == "departure.lineup_takeoff"
            or queuedId == "departure.airborne"
            or queuedId == "departure.on_climb"
            or is_climb_progress_event(queuedId)
    end
    if eventId == "enroute.in_cruise" then
        return queuedId == "departure.airborne"
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
        or eventId == "arrival.parking_position" then
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
