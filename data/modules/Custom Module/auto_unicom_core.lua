local M = {}

M.EVENT_TTL_SEC = {
    ["departure.start_push"] = 60,
    ["departure.taxi_runway"] = 120,
    ["departure.lineup_takeoff"] = 45,
    ["departure.airborne"] = 60,
    ["departure.on_climb"] = 120,
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
        local airport = clean_token(snapshot.departure_icao, false)
        if not airport or #airport ~= 4 then return nil, "missing_departure_context" end
        return normalize_text(string.format("%s Traffic, %s, pushing back", airport, ac))
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

    if eventId == "departure.on_climb" then
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

    if eventId == "arrival.on_descent" or eventId == "arrival.approach" then
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

local function actual_descent(snapshot)
    local vs = tonumber(snapshot.vertical_speed_fpm) or 0
    local altitude = tonumber(snapshot.altitude_ft) or 0
    local cruise = tonumber(snapshot.planned_altitude_ft) or 0
    return vs <= -300 or (cruise > 0 and altitude < cruise - 300)
end

local Engine = {}
Engine.__index = Engine

local function summarize_sources(snapshot)
    local fields = {
        { "phase", snapshot.fms_phase },
        { "onGround", snapshot.on_ground and 1 or 0 },
        { "preflight", snapshot.preflight and 1 or 0 },
        { "beforeTaxi", snapshot.before_taxi_started and 1 or 0 },
        { "beforeTakeoff", snapshot.before_takeoff_started and 1 or 0 },
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
        { "n1", tostring(snapshot.eng1_n1_percent or "") .. "/" .. tostring(snapshot.eng2_n1_percent or "") },
        { "bpb", snapshot.pushback_active and 1 or 0 },
        { "final", snapshot.final_gate and 1 or 0 }
    }
    local parts = {}
    for _, field in ipairs(fields) do
        parts[#parts + 1] = field[1] .. "=" .. tostring(field[2] or "")
    end
    return table.concat(parts, " ")
end

function M.newEventEngine(options)
    options = options or {}
    return setmetatable({
        emit = options.emit or function() return true end,
        log = options.log or function() end,
        active = false,
        sent = {},
        phase = nil,
        phase_since = nil,
        last_on_ground = nil,
        last_preflight = nil,
        ground_since = nil,
        ground_armed = false,
        flight_active = false,
        takeoff_at = nil,
        before_taxi_seen = false,
        before_takeoff_seen = false,
        push_since = nil,
        taxi_since = nil,
        takeoff_roll_since = nil,
        tod_previous = nil,
        tod_crossed_at = nil,
        last_positive_tod_at = nil,
        final_since = nil,
        vacated_since = nil,
        touchdown_latched = false
    }, Engine)
end

function Engine:markSent(eventId)
    self.sent[eventId] = true
end

function Engine:resetDepartureGroundCycle(snapshot)
    self.sent["departure.start_push"] = nil
    self.sent["departure.taxi_runway"] = nil
    self.sent["departure.lineup_takeoff"] = nil
    self.before_taxi_seen = snapshot.before_taxi_started == true
    self.before_takeoff_seen = snapshot.before_takeoff_started == true
    self.push_since = nil
    self.taxi_since = nil
    self.takeoff_roll_since = nil
end

function Engine:activate(snapshot, now)
    self.active = true
    self.sent = {}
    self.phase = tonumber(snapshot.fms_phase)
    self.phase_since = now
    self.last_on_ground = snapshot.on_ground == true
    self.last_preflight = snapshot.preflight == true
    self.ground_since = self.last_on_ground and now or nil
    self.ground_armed = false
    self.flight_active = not self.last_on_ground
    self.takeoff_at = nil
    self.before_taxi_seen = snapshot.before_taxi_started == true
    self.before_takeoff_seen = snapshot.before_takeoff_started == true
    self.push_since = nil
    self.taxi_since = nil
    self.takeoff_roll_since = nil
    self.tod_previous = tonumber(snapshot.tod_distance_nm)
    self.tod_crossed_at = nil
    self.last_positive_tod_at = nil
    self.final_since = nil
    self.vacated_since = nil
    self.touchdown_latched = false

    if not self.last_on_ground then
        self:markSent("departure.start_push")
        self:markSent("departure.taxi_runway")
        self:markSent("departure.lineup_takeoff")
        self:markSent("departure.airborne")
        self:markSent("departure.on_climb")
        if (self.phase or 0) >= 4 then
            self:markSent("arrival.on_descent")
        end
        if (self.phase or 0) >= 5 then
            self:markSent("arrival.top_of_descent")
        end
        if (self.phase or 0) >= 6 then
            self:markSent("arrival.approach")
        end
        if snapshot.final_gate == true then
            self:markSent("arrival.on_final")
        end
    else
        local gs = tonumber(snapshot.ground_speed_kts) or 0
        local wheelSpeed = tonumber(snapshot.wheel_speed) or 0
        local forward = wheelSpeed > 1
        local reverse = wheelSpeed < -1
        local moving = math.abs(wheelSpeed) > 1
        if moving and (snapshot.pushback_active == true or reverse) then
            self:markSent("departure.start_push")
        end
        if self.before_takeoff_seen
            or (self.before_taxi_seen and moving and gs >= 3 and forward) then
            self:markSent("departure.start_push")
            self:markSent("departure.taxi_runway")
        end
        if self.before_takeoff_seen
            and snapshot.on_departure_runway == true
            and moving and gs > 5 and forward
            and (tonumber(snapshot.eng1_n1_percent) or 0) > 40
            and (tonumber(snapshot.eng2_n1_percent) or 0) > 40 then
            self:markSent("departure.lineup_takeoff")
        end
    end
end

function Engine:deactivate()
    self.active = false
    self.sent = {}
    self.final_since = nil
    self.vacated_since = nil
    self.push_since = nil
    self.taxi_since = nil
    self.takeoff_roll_since = nil
end

function Engine:beginFlight(snapshot, now)
    self.sent = {}
    self.flight_active = true
    self.takeoff_at = now
    self.push_since = nil
    self.taxi_since = nil
    self.takeoff_roll_since = nil
    self.tod_previous = tonumber(snapshot.tod_distance_nm)
    self.tod_crossed_at = nil
    self.last_positive_tod_at = nil
    self.final_since = nil
    self.vacated_since = nil
    self.touchdown_latched = false
end

function Engine:tryEmit(eventId, snapshot, now)
    if self.sent[eventId] then return false end
    local text, reason = M.buildMessage(eventId, snapshot)
    if not text then return false, reason end
    local accepted = self.emit({
        id = eventId,
        text = text,
        inputs = summarize_sources(snapshot),
        created_at = now,
        expires_at = now + (M.EVENT_TTL_SEC[eventId] or 120)
    })
    if accepted == false then return false, "queue_rejected" end
    self.sent[eventId] = true
    return true
end

function Engine:update(snapshot, now)
    if not self.active then
        self:activate(snapshot, now)
        return
    end

    local onGround = snapshot.on_ground == true
    local phase = tonumber(snapshot.fms_phase) or 0
    if phase ~= self.phase then
        self.phase = phase
        self.phase_since = now
    elseif self.phase_since == nil then
        self.phase_since = now
    end
    local phaseStable = now - self.phase_since

    local preflight = snapshot.preflight == true
    if onGround and preflight and self.last_preflight ~= true then
        self:resetDepartureGroundCycle(snapshot)
    end
    if snapshot.before_taxi_started == true then
        self.before_taxi_seen = true
    end
    if snapshot.before_takeoff_started == true then
        self.before_takeoff_seen = true
    end

    local gs = tonumber(snapshot.ground_speed_kts) or 0
    local wheelSpeed = tonumber(snapshot.wheel_speed) or 0
    local forward = wheelSpeed > 1
    local reverse = wheelSpeed < -1
    local moving = math.abs(wheelSpeed) > 1
    local parkingBrakeReleased = snapshot.parking_brake_released == true

    local pushGate = onGround and preflight and parkingBrakeReleased
        and moving
        and (snapshot.pushback_active == true or reverse)
    if pushGate and not self.sent["departure.start_push"] then
        self.push_since = self.push_since or now
        if now - self.push_since >= 2 then
            self:tryEmit("departure.start_push", snapshot, now)
        end
    else
        self.push_since = nil
    end

    local taxiGate = onGround and preflight and self.before_taxi_seen
        and parkingBrakeReleased and snapshot.pushback_active ~= true
        and moving and gs >= 3 and forward
    if taxiGate and not self.sent["departure.taxi_runway"] then
        self.taxi_since = self.taxi_since or now
        if now - self.taxi_since >= 3 then
            local emitted = self:tryEmit("departure.taxi_runway", snapshot, now)
            if emitted then self:markSent("departure.start_push") end
        end
    else
        self.taxi_since = nil
    end

    local takeoffGate = onGround and preflight and self.before_takeoff_seen
        and parkingBrakeReleased and snapshot.on_departure_runway == true
        and moving and gs > 5 and forward
        and (tonumber(snapshot.eng1_n1_percent) or 0) > 40
        and (tonumber(snapshot.eng2_n1_percent) or 0) > 40
    if takeoffGate and not self.sent["departure.lineup_takeoff"] then
        self.takeoff_roll_since = self.takeoff_roll_since or now
        if now - self.takeoff_roll_since >= 1 then
            local emitted = self:tryEmit("departure.lineup_takeoff", snapshot, now)
            if emitted then
                self:markSent("departure.start_push")
                self:markSent("departure.taxi_runway")
            end
        end
    else
        self.takeoff_roll_since = nil
    end

    if onGround then
        if self.last_on_ground ~= true then
            self.ground_since = now
            self.ground_armed = false
            if self.flight_active and snapshot.on_runway_profile == true then
                self.touchdown_latched = true
            end
        elseif self.ground_since and now - self.ground_since >= 3 then
            self.ground_armed = true
        end
    elseif self.last_on_ground == true and self.ground_armed then
        self:beginFlight(snapshot, now)
    end

    if self.flight_active and not onGround and self.takeoff_at then
        local sinceTakeoff = now - self.takeoff_at
        if sinceTakeoff >= 3 and sinceTakeoff <= 60 and (tonumber(snapshot.radio_altitude_ft) or 0) > 50 then
            self:tryEmit("departure.airborne", snapshot, now)
        end
        if phase == 1 and phaseStable >= 8
            and (tonumber(snapshot.radio_altitude_ft) or 0) >= 1500
            and (tonumber(snapshot.vertical_speed_fpm) or 0) >= 300 then
            self:tryEmit("departure.on_climb", snapshot, now)
        end
    end

    local tod = tonumber(snapshot.tod_distance_nm)
    if not onGround and tod and tod > 1 and (phase == 2 or phase == 4) then
        self.last_positive_tod_at = now
    end
    if not onGround and tod and self.tod_previous and self.tod_previous > 1 and tod <= 1 then
        self.tod_crossed_at = now
    end
    self.tod_previous = tod

    if not onGround and self.flight_active and actual_descent(snapshot) then
        local recentTodCrossing = self.tod_crossed_at and (now - self.tod_crossed_at <= 300)
        local recentPositiveTod = self.last_positive_tod_at and (now - self.last_positive_tod_at <= 300)
        if phase == 5 and phaseStable >= 8
            and not self.sent["arrival.on_descent"]
            and recentTodCrossing and recentPositiveTod then
            self:tryEmit("arrival.top_of_descent", snapshot, now)
        elseif (phase == 4 or phase == 5) and phaseStable >= 8
            and not self.sent["arrival.top_of_descent"]
            and not recentTodCrossing then
            self:tryEmit("arrival.on_descent", snapshot, now)
        end
    end

    if not onGround and self.flight_active and phase == 6 and phaseStable >= 8 then
        self:tryEmit("arrival.approach", snapshot, now)
    end

    local finalGate = not onGround and self.flight_active and phase == 6 and snapshot.final_gate == true
    if finalGate then
        self.final_since = self.final_since or now
        if now - self.final_since >= 5 then
            self:tryEmit("arrival.on_final", snapshot, now)
        end
    else
        self.final_since = nil
    end

    local vacatedGate = self.touchdown_latched and onGround
        and snapshot.on_runway_profile == false
        and (tonumber(snapshot.ground_speed_kts) or 999) < 45
    if vacatedGate then
        self.vacated_since = self.vacated_since or now
        if now - self.vacated_since >= 5 then
            self:tryEmit("arrival.runway_vacated", snapshot, now)
        end
    else
        self.vacated_since = nil
    end

    self.last_on_ground = onGround
    self.last_preflight = preflight
end

local Mailbox = {}
Mailbox.__index = Mailbox

local SUPERSEDED_EVENTS = {
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
    local superseded = SUPERSEDED_EVENTS[event.id]
    if superseded then
        local kept = {}
        for _, queued in ipairs(self.queue) do
            if superseded[queued.id] then
                self.queuedIds[queued.id] = nil
                self.log("superseded", queued)
            else
                table.insert(kept, queued)
            end
        end
        self.queue = kept
    end
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

local EARTH_RADIUS_M = 6371000

function M.runwayMetrics(position, runway)
    if not position or not runway then return nil end
    local lat = tonumber(position.lat)
    local lon = tonumber(position.lon)
    local startLat = tonumber(runway.start_lat)
    local startLon = tonumber(runway.start_lon)
    local endLat = tonumber(runway.end_lat)
    local endLon = tonumber(runway.end_lon)
    if not lat or not lon or not startLat or not startLon or not endLat or not endLon then return nil end
    if lat == 0 or lon == 0 or startLat == 0 or startLon == 0 or endLat == 0 or endLon == 0 then return nil end

    local cosLat = math.cos(math.rad(startLat))
    local vx = math.rad(endLon - startLon) * cosLat * EARTH_RADIUS_M
    local vy = math.rad(endLat - startLat) * EARTH_RADIUS_M
    local px = math.rad(lon - startLon) * cosLat * EARTH_RADIUS_M
    local py = math.rad(lat - startLat) * EARTH_RADIUS_M
    local lengthSq = vx * vx + vy * vy
    if lengthSq < 1 then return nil end
    local length = math.sqrt(lengthSq)
    local along = (px * vx + py * vy) / length
    local cross = math.abs(vx * py - vy * px) / length
    local threshold = math.sqrt(px * px + py * py) / 1852
    return {
        cross_track_m = cross,
        along_track_m = along,
        runway_length_m = length,
        threshold_distance_nm = threshold,
        on_profile = cross <= 60 and along >= -100 and along <= length + 200
    }
end

return M
