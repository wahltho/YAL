package.path = "data/modules/Custom Module/?.lua;" .. package.path

local core = require("auto_unicom_core")
local autoUnicom = require("auto_unicom")

local function fail(message)
    error(message, 2)
end

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        fail(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, label)
    if not value then fail(label .. ": expected true") end
end

local function copy(source, overrides)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local base = {
    on_ground = true,
    on_departure_runway = false,
    arrival_runway_clear = false,
    final_gate = false,
    preflight = false,
    initial_climb_state = false,
    climb_state = false,
    descent_state = false,
    post_landing_state = false,
    descent_entry_kind = nil,
    before_taxi_started = false,
    before_takeoff_started = false,
    wheel_speed = 0,
    pushback_active = false,
    fms_phase = 0,
    radio_altitude_ft = 0,
    altitude_ft = 300,
    pressure_altitude_ft = 300,
    vertical_speed_fpm = 0,
    ground_speed_kts = 0,
    tod_distance_nm = 100,
    transition_altitude_ft = 7000,
    transition_level_ft = 7000,
    planned_altitude_ft = 37000,
    departure_icao = "ENAT",
    departure_runway = "09",
    arrival_icao = "ENSB",
    arrival_runway = "27",
    aircraft_type = "B738",
    sid = "ATKUP1A",
    star = "NELSA3M",
    approach_id = "R27-W",
    approach_procedure_type = "RNAV",
    approach_suffix = "W"
}

local phraseCases = {
    {
        "departure.airborne",
        base,
        "ENAT Traffic, B738 airborne off runway 09, passing 300ft"
    },
    {
        "departure.on_climb",
        copy(base, { altitude_ft = 1800, pressure_altitude_ft = 1800 }),
        "Traffic, B738 climbing out of ENAT on ATKUP1A departure, passing 1800ft for FL370"
    },
    {
        "arrival.top_of_descent",
        copy(base, { altitude_ft = 37000, pressure_altitude_ft = 37000 }),
        "ENSB Traffic, B738, NELSA3M arrival at TOD, leaving FL370, expecting runway 27"
    },
    {
        "arrival.on_descent",
        copy(base, { altitude_ft = 18000, pressure_altitude_ft = 18000 }),
        "ENSB Traffic, B738 NELSA3M arrival for RNAV W approach runway 27, on descent passing FL180"
    },
    {
        "arrival.approach",
        copy(base, { altitude_ft = 6000, pressure_altitude_ft = 6000 }),
        "ENSB Traffic, B738 NELSA3M arrival for RNAV W approach runway 27, on descent passing 6000ft"
    },
    {
        "arrival.on_final",
        copy(base, { approach_procedure_type = "ILS" }),
        "ENSB Traffic, B738 established on ILS runway 27"
    },
    {
        "arrival.runway_vacated",
        base,
        "ENSB Traffic, runway 27 vacated, taxiing to gate"
    },
    {
        "departure.start_push",
        base,
        "ENAT Traffic, B738, pushing back"
    },
    {
        "departure.taxi_runway",
        base,
        "ENAT Traffic, B738 taxiing to holding point runway 09"
    },
    {
        "departure.lineup_takeoff",
        base,
        "ENAT Traffic, B738 taking off runway 09"
    },
    {
        "arrival.descent_level_30000",
        copy(base, { altitude_ft = 30000, pressure_altitude_ft = 30000 }),
        "ENSB Traffic, B738 NELSA3M arrival for RNAV W approach runway 27, on descent passing FL300"
    },
    {
        "departure.climb_level_10000",
        copy(base, { altitude_ft = 10000, pressure_altitude_ft = 10000 }),
        "Traffic, B738 climbing out of ENAT on ATKUP1A departure, passing FL100 for FL370"
    },
    {
        "departure.climb_level_20000",
        copy(base, { altitude_ft = 20000, pressure_altitude_ft = 20000 }),
        "Traffic, B738 climbing out of ENAT on ATKUP1A departure, passing FL200 for FL370"
    },
    {
        "departure.climb_level_30000",
        copy(base, { altitude_ft = 30000, pressure_altitude_ft = 30000 }),
        "Traffic, B738 climbing out of ENAT on ATKUP1A departure, passing FL300 for FL370"
    },
    {
        "departure.climb_level_40000",
        copy(base, { altitude_ft = 40000, pressure_altitude_ft = 40000, planned_altitude_ft = 41000 }),
        "Traffic, B738 climbing out of ENAT on ATKUP1A departure, passing FL400 for FL410"
    },
    {
        "enroute.hold_enter",
        copy(base, { hold_waypoint = "BIRCO", hold_path_type = "HM" }),
        "Traffic, B738, entering a hold over BIRCO"
    },
    {
        "enroute.hold_exit",
        copy(base, { hold_waypoint = "BIRCO", hold_path_type = "HM" }),
        "Traffic, B738, exiting hold over BIRCO"
    }
}

for _, case in ipairs(phraseCases) do
    local text = core.buildMessage(case[1], case[2])
    assert_equal(text, case[3], "phrase " .. case[1])
    assert_true(not text:lower():find(" the ", 1, true), "phrase has no 'the' " .. case[1])
end

local missingText, missingReason = core.buildMessage(
    "departure.airborne",
    copy(base, { departure_icao = "" })
)
assert_equal(missingText, nil, "missing departure ICAO rejects phrase")
assert_equal(missingReason, "missing_departure_context", "missing departure reason")

missingText, missingReason = core.buildMessage(
    "arrival.approach",
    copy(base, { arrival_runway = "" })
)
assert_equal(missingText, nil, "missing arrival runway rejects phrase")
assert_equal(missingReason, "missing_arrival_context", "missing arrival reason")

assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_airport_icao = "ESSA",
        pushback_parking_found = true,
        pushback_parking_type = "gate",
        pushback_parking_name = "Gate A12"
    })),
    "ESSA Traffic, B738, pushing back from gate A12",
    "pushback gate phrase"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_parking_found = true,
        pushback_parking_type = "misc",
        pushback_parking_name = "Apron 42"
    })),
    "ENAT Traffic, B738, pushing back from stand 42",
    "pushback apron stand phrase"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_parking_found = true,
        pushback_parking_type = "gate",
        pushback_parking_name = "Gate"
    })),
    phraseCases[8][3],
    "generic pushback phrase for unnamed gate"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_parking_found = true,
        pushback_parking_type = "misc",
        pushback_parking_name = "Class C"
    })),
    phraseCases[8][3],
    "generic pushback phrase for ramp class"
)

assert_equal(
    core.buildMessage("arrival.on_final", copy(base, { approach_procedure_type = "LOC" })),
    "ENSB Traffic, B738 established on Localizer runway 27",
    "LOC final phrase"
)

local missingHoldText, missingHoldReason = core.buildMessage("enroute.hold_enter", base)
assert_equal(missingHoldText, nil, "hold phrase requires waypoint")
assert_equal(missingHoldReason, "missing_hold_context", "missing hold waypoint reason")

local function find_candidate(candidates, eventId)
    for _, candidate in ipairs(candidates) do
        if candidate.id == eventId then return candidate end
    end
    return nil
end

local holdIdle = copy(base, { on_ground = false })
local holdEntering = copy(holdIdle, {
    hold_source = "api",
    hold_api_version = 1,
    hold_active = true,
    hold_exit_armed = false,
    hold_waypoint = "BIRCO",
    hold_path_type = "HM"
})
local holdCandidates = core.collectEventCandidates(holdEntering, holdIdle)
local holdEnter = find_candidate(holdCandidates, "enroute.hold_enter")
assert_true(holdEnter ~= nil, "active hold produces entry candidate")
assert_equal(holdEnter.key, "enroute.hold_enter|BIRCO|HM", "hold entry dedupe uses episode")

local holdExitArmed = copy(holdEntering, { hold_exit_armed = true })
holdCandidates = core.collectEventCandidates(holdExitArmed, holdEntering)
local holdExit = find_candidate(holdCandidates, "enroute.hold_exit")
assert_true(holdExit ~= nil, "armed hold exit produces exit candidate")
assert_equal(holdExit.key, "enroute.hold_exit|BIRCO|HM", "hold exit dedupe uses episode")

holdCandidates = core.collectEventCandidates(holdIdle, holdEntering)
holdExit = find_candidate(holdCandidates, "enroute.hold_exit")
assert_true(holdExit ~= nil, "ended hold produces exit candidate")
assert_true(holdExit.cancel_hold_entry, "ended hold cancels stale queued entry")
assert_equal(holdExit.snapshot.hold_waypoint, "BIRCO", "ended hold keeps previous fix")

local secondHold = copy(holdEntering, {
    hold_source = "legacy",
    hold_waypoint = "ROBUR",
    hold_path_type = "HF"
})
holdCandidates = core.collectEventCandidates(secondHold, holdEntering)
assert_true(find_candidate(holdCandidates, "enroute.hold_exit") ~= nil,
    "hold change produces previous exit candidate")
assert_true(find_candidate(holdCandidates, "enroute.hold_enter") ~= nil,
    "hold change produces next entry candidate")

local groundIdle = copy(base, { preflight = true })
local pushing = copy(groundIdle, {
    wheel_speed = -3,
    ground_speed_kts = 2,
    pushback_airport_icao = "ESSA",
    pushback_parking_found = true,
    pushback_parking_type = "gate",
    pushback_parking_name = "Gate A12"
})
local groundCandidates = core.collectEventCandidates(pushing, groundIdle)
local pushCandidate = find_candidate(groundCandidates, "departure.start_push")
assert_true(pushCandidate ~= nil, "reverse movement produces pushback candidate")
assert_equal(pushCandidate.stable_for, 2, "pushback uses generic two-second stability")
local pushEvent = core.newEvent(pushCandidate.id, pushCandidate.snapshot, 3)
assert_equal(pushEvent.text, "ESSA Traffic, B738, pushing back from gate A12",
    "pushback candidate builds gate phrase")

local bpbPush = copy(groundIdle, { pushback_active = true })
assert_true(find_candidate(core.collectEventCandidates(bpbPush, groundIdle),
    "departure.start_push") ~= nil, "BetterPushback active produces pushback candidate")

local taxiWithoutProcedure = copy(groundIdle, { wheel_speed = 6, ground_speed_kts = 6 })
assert_equal(find_candidate(core.collectEventCandidates(taxiWithoutProcedure, groundIdle),
    "departure.taxi_runway"), nil, "taxi requires accepted Before Taxi")
local taxiing = copy(taxiWithoutProcedure, { before_taxi_started = true })
local taxiCandidate = find_candidate(core.collectEventCandidates(taxiing, groundIdle),
    "departure.taxi_runway")
assert_true(taxiCandidate ~= nil, "accepted Before Taxi plus movement produces taxi candidate")
assert_equal(taxiCandidate.consumes[1], "departure.start_push",
    "taxi closes earlier pushback event")

local takeoffOffRunway = copy(taxiing, {
    before_takeoff_started = true,
    wheel_speed = 25,
    ground_speed_kts = 25
})
assert_equal(find_candidate(core.collectEventCandidates(takeoffOffRunway, taxiing),
    "departure.lineup_takeoff"), nil, "takeoff requires YAL runway detection")
local takeoffRoll = copy(takeoffOffRunway, { on_departure_runway = true })
local takeoffCandidate = find_candidate(core.collectEventCandidates(takeoffRoll, taxiing),
    "departure.lineup_takeoff")
assert_true(takeoffCandidate ~= nil, "accepted Before Takeoff plus runway roll produces takeoff candidate")
assert_equal(takeoffCandidate.stable_for, 2, "takeoff uses generic two-second stability")

local transientPreflight = copy(groundIdle, { on_ground = false })
assert_equal(#core.collectEventCandidates(transientPreflight, nil), 0,
    "preflight air-ground transient baselines no departure event")
assert_true(find_candidate(core.collectEventCandidates(bpbPush, transientPreflight),
    "departure.start_push") ~= nil, "confirmed ground push remains eligible after sensor transient")

local airborneBeforeState = copy(base, {
    on_ground = false,
    radio_altitude_ft = 200,
    altitude_ft = 300,
    pressure_altitude_ft = 300
})
assert_equal(find_candidate(core.collectEventCandidates(airborneBeforeState, base),
    "departure.airborne"), nil, "airborne waits for accepted YAL flight state")
local initialClimb = copy(airborneBeforeState, { initial_climb_state = true })
assert_true(find_candidate(core.collectEventCandidates(initialClimb, airborneBeforeState),
    "departure.airborne") ~= nil, "Initial Climb produces airborne candidate")

local climb = copy(airborneBeforeState, {
    climb_state = true,
    radio_altitude_ft = 9700,
    altitude_ft = 10000,
    pressure_altitude_ft = 10000
})
local climbCandidates = core.collectEventCandidates(climb, initialClimb)
assert_true(find_candidate(climbCandidates, "departure.on_climb") ~= nil,
    "YAL Climb state produces climb candidate")
assert_true(find_candidate(climbCandidates, "departure.climb_level_10000") ~= nil,
    "YAL Climb state and altitude produce FL100 candidate")
assert_equal(find_candidate(climbCandidates, "departure.climb_level_20000"), nil,
    "unreached climb level is not a candidate")

local descent = copy(base, {
    on_ground = false,
    descent_state = true,
    descent_entry_kind = "tod",
    fms_phase = 5,
    altitude_ft = 40900,
    pressure_altitude_ft = 40900
})
local descentCandidates = core.collectEventCandidates(descent, climb)
assert_true(find_candidate(descentCandidates, "arrival.top_of_descent") ~= nil,
    "YAL TOD descent entry produces TOD candidate")
assert_equal(find_candidate(descentCandidates, "arrival.descent_level_40000"), nil,
    "descent level waits for current altitude")

local atFl400 = copy(descent, { altitude_ft = 40000, pressure_altitude_ft = 40000 })
assert_true(find_candidate(core.collectEventCandidates(atFl400, descent),
    "arrival.descent_level_40000") ~= nil, "descent altitude produces FL400 candidate")

local approachHigh = copy(descent, {
    descent_entry_kind = "descent",
    fms_phase = 6,
    altitude_ft = 10500,
    pressure_altitude_ft = 10500
})
assert_equal(find_candidate(core.collectEventCandidates(approachHigh, descent),
    "arrival.approach"), nil, "approach report waits for FL100 preparation point")
local approach = copy(approachHigh, { altitude_ft = 9500, pressure_altitude_ft = 9500 })
local approachCandidates = core.collectEventCandidates(approach, approachHigh)
assert_true(find_candidate(approachCandidates, "arrival.descent_level_10000") ~= nil,
    "approach crossing includes FL100 report")
assert_true(find_candidate(approachCandidates, "arrival.approach") ~= nil,
    "approach crossing includes approach candidate")

local final = copy(approach, { final_gate = true })
local finalCandidate = find_candidate(core.collectEventCandidates(final, approach),
    "arrival.on_final")
assert_true(finalCandidate ~= nil, "YAL final gate produces final candidate")
assert_equal(finalCandidate.stable_for, 5, "final uses generic five-second stability")
local goAround = copy(final, { fms_phase = 8 })
assert_equal(find_candidate(core.collectEventCandidates(goAround, final),
    "arrival.approach"), nil, "active go-around produces no approach candidate")
assert_equal(find_candidate(core.collectEventCandidates(goAround, final),
    "arrival.on_final"), nil, "active go-around produces no final candidate")

local runwayClear = copy(base, {
    on_ground = true,
    post_landing_state = true,
    arrival_runway_clear = true
})
local vacatedCandidate = find_candidate(core.collectEventCandidates(runwayClear, final),
    "arrival.runway_vacated")
assert_true(vacatedCandidate ~= nil, "YAL post-landing runway-clear state produces vacated candidate")
assert_equal(vacatedCandidate.stable_for, 2, "runway vacated uses generic two-second stability")

local writes = {}
local mailboxLogs = {}
local mailbox = core.newMailbox({
    writeText = function(text)
        table.insert(writes, { kind = "text", value = text, length = #text })
        return true
    end,
    writeSeq = function(seq)
        table.insert(writes, { kind = "seq", value = seq })
        return true
    end,
    log = function(kind, event)
        table.insert(mailboxLogs, { kind = kind, event = event })
    end
})
assert_true(mailbox:enqueue({ id = "departure.airborne", text = phraseCases[1][3], created_at = 0, expires_at = 60 }), "mailbox enqueue")
local api = {
    api_version = 1,
    ready = 1,
    mode = 1,
    transport_state = 4,
    request_seq = 7,
    result_seq = 7,
    result_code = 0
}
mailbox:tick(api, 0)
assert_equal(#writes, 0, "dry-run mode does not commit")
api.mode = 2
mailbox:tick(api, 0)
assert_equal(#writes, 0, "send mode waits for READY")
api.transport_state = 5
mailbox:tick(api, 0)
assert_equal(writes[1].kind, "text", "mailbox text first")
assert_equal(writes[1].value, phraseCases[1][3], "mailbox exact text")
assert_equal(writes[1].length, #phraseCases[1][3], "mailbox exact length")
assert_equal(writes[2].kind, "seq", "mailbox seq last")
assert_equal(writes[2].value, 8, "mailbox increasing seq")
api.result_seq = 8
api.result_code = 10
mailbox:tick(api, 1)
assert_true(mailbox.outstanding ~= nil, "accepted is non-terminal")
api.result_code = 21
mailbox:tick(api, 2)
assert_true(mailbox.outstanding == nil, "submitted result completes request")
assert_equal(mailboxLogs[#mailboxLogs].kind, "terminal", "terminal result logged")

local supersessionLogs = {}
local supersessionMailbox = core.newMailbox({
    log = function(kind, event)
        table.insert(supersessionLogs, { kind = kind, event = event })
    end
})
assert_true(supersessionMailbox:enqueue({
    id = "arrival.top_of_descent",
    text = phraseCases[3][3],
    expires_at = 100
}), "enqueue TOD before supersession")
assert_true(supersessionMailbox:enqueue({
    id = "arrival.descent_level_30000",
    text = phraseCases[11][3],
    expires_at = 100
}), "enqueue descent level supersession")
assert_equal(#supersessionMailbox.queue, 1, "descent level supersedes queued TOD")
assert_equal(supersessionMailbox.queue[1].id, "arrival.descent_level_30000", "descent level remains queued")
assert_true(supersessionMailbox:enqueue({
    id = "arrival.descent_level_20000",
    text = core.buildMessage("arrival.descent_level_20000", copy(base, {
        altitude_ft = 20000,
        pressure_altitude_ft = 20000
    })),
    expires_at = 100
}), "enqueue later descent level supersession")
assert_equal(#supersessionMailbox.queue, 1, "later descent level supersedes older level")
assert_equal(supersessionMailbox.queue[1].id, "arrival.descent_level_20000", "later descent level remains queued")
assert_true(supersessionMailbox:enqueue({
    id = "arrival.approach",
    text = phraseCases[5][3],
    expires_at = 100
}), "enqueue approach supersession")
assert_equal(#supersessionMailbox.queue, 1, "supersession keeps only current event")
assert_equal(supersessionMailbox.queue[1].id, "arrival.approach", "approach supersedes queued descent level")
assert_equal(supersessionLogs[1].kind, "superseded", "supersession logged")
assert_true(supersessionMailbox:enqueue({
    id = "departure.taxi_runway",
    text = phraseCases[9][3],
    expires_at = 100
}), "enqueue unrelated departure event before go-around cancellation")
supersessionMailbox:cancelQueuedForGoAround()
assert_equal(#supersessionMailbox.queue, 1, "go-around cancellation removes only queued arrival events")
assert_equal(supersessionMailbox.queue[1].id, "departure.taxi_runway", "go-around cancellation preserves departure event")
assert_equal(supersessionLogs[#supersessionLogs].kind, "cancelled_go_around", "go-around queue cancellation logged")

local holdMailboxLogs = {}
local holdMailbox = core.newMailbox({
    log = function(kind, event) table.insert(holdMailboxLogs, { kind = kind, event = event }) end
})
assert_true(holdMailbox:enqueue({
    id = "enroute.hold_enter",
    text = phraseCases[16][3],
    expires_at = 100
}), "enqueue hold entry")
assert_true(holdMailbox:enqueue({
    id = "enroute.hold_exit",
    text = phraseCases[17][3],
    expires_at = 100
}), "enqueue hold exit supersession")
assert_equal(#holdMailbox.queue, 1, "hold exit supersedes queued hold entry")
assert_equal(holdMailbox.queue[1].id, "enroute.hold_exit", "hold exit remains queued")
assert_equal(holdMailboxLogs[1].kind, "superseded", "hold supersession logged")
holdMailbox = core.newMailbox({
    log = function(kind, event) table.insert(holdMailboxLogs, { kind = kind, event = event }) end
})
assert_true(holdMailbox:enqueue({
    id = "enroute.hold_enter",
    text = phraseCases[16][3],
    expires_at = 100
}), "enqueue hold entry before cancellation")
assert_true(holdMailbox:enqueue({
    id = "departure.taxi_runway",
    text = phraseCases[9][3],
    expires_at = 100
}), "enqueue unrelated event before hold cancellation")
holdMailbox:cancelQueuedForHoldEnd()
assert_equal(#holdMailbox.queue, 1, "hold cancellation removes only hold entry")
assert_equal(holdMailbox.queue[1].id, "departure.taxi_runway", "hold cancellation preserves unrelated event")
assert_equal(holdMailboxLogs[#holdMailboxLogs].kind, "cancelled_hold_end", "hold cancellation logged")

local departureSupersession = core.newMailbox()
assert_true(departureSupersession:enqueue({
    id = "departure.start_push",
    text = phraseCases[8][3],
    expires_at = 100
}), "enqueue push before supersession")
assert_true(departureSupersession:enqueue({
    id = "departure.taxi_runway",
    text = phraseCases[9][3],
    expires_at = 100
}), "enqueue taxi supersession")
assert_equal(#departureSupersession.queue, 1, "taxi supersedes queued push")
assert_equal(departureSupersession.queue[1].id, "departure.taxi_runway", "taxi remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.lineup_takeoff",
    text = phraseCases[10][3],
    expires_at = 100
}), "enqueue takeoff supersession")
assert_equal(#departureSupersession.queue, 1, "takeoff supersedes earlier ground messages")
assert_equal(departureSupersession.queue[1].id, "departure.lineup_takeoff", "takeoff remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.airborne",
    text = phraseCases[1][3],
    expires_at = 100
}), "enqueue airborne supersession")
assert_equal(#departureSupersession.queue, 1, "airborne supersedes queued takeoff")
assert_equal(departureSupersession.queue[1].id, "departure.airborne", "airborne remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.on_climb",
    text = phraseCases[2][3],
    expires_at = 100
}), "enqueue initial climb supersession")
assert_equal(#departureSupersession.queue, 1, "initial climb supersedes airborne")
assert_equal(departureSupersession.queue[1].id, "departure.on_climb", "initial climb remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.climb_level_10000",
    text = phraseCases[12][3],
    expires_at = 100
}), "enqueue FL100 climb supersession")
assert_equal(#departureSupersession.queue, 1, "FL100 climb supersedes earlier departure messages")
assert_equal(departureSupersession.queue[1].id, "departure.climb_level_10000", "FL100 climb remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.climb_level_20000",
    text = phraseCases[13][3],
    expires_at = 100
}), "enqueue FL200 climb supersession")
assert_equal(#departureSupersession.queue, 1, "FL200 climb supersedes queued FL100 report")
assert_equal(departureSupersession.queue[1].id, "departure.climb_level_20000", "FL200 climb remains queued")

local uncertainWrites = 0
local uncertainMailbox = core.newMailbox({
    writeText = function() uncertainWrites = uncertainWrites + 1 return true end,
    writeSeq = function() uncertainWrites = uncertainWrites + 1 return true end
})
assert_true(uncertainMailbox:enqueue({
    id = "arrival.on_final",
    text = phraseCases[6][3],
    expires_at = 100
}), "enqueue uncertain request")
uncertainMailbox:tick(api, 3)
assert_equal(uncertainWrites, 2, "uncertain request committed once")
api.result_seq = uncertainMailbox.outstanding.seq
api.result_code = 41
uncertainMailbox:tick(api, 4)
assert_true(uncertainMailbox.outstanding == nil, "uncertain result completes request")
uncertainMailbox:tick(api, 5)
assert_equal(uncertainWrites, 2, "uncertain result is never retried")

local repeatRefs = {
    api_version = "api_version",
    ready = "ready",
    mode = "mode",
    transport_state = "transport_state",
    request_text = "request_text",
    request_seq = "request_seq",
    result_seq = "result_seq",
    result_code = "result_code",
    result_detail = "result_detail"
}
local repeatValues = {
    api_version = 1,
    ready = 1,
    mode = 2,
    transport_state = 5,
    request_text = phraseCases[5][3],
    request_seq = 12,
    result_seq = 12,
    result_code = 21,
    result_detail = "SUBMITTED_VISIBLE"
}
local function configure_repeat_test()
    autoUnicom.configure({
        helpers = { logInfoTS = function() end },
        getRefs = function() return repeatRefs end,
        read = function(prop) return repeatValues[prop] end
    })
end

local baselineYal = {
    airgroundsensor = "airgroundsensor",
    radioaltitude = "radioaltitude",
    altitude_ft = "altitude_ft",
    altitude = "altitude_ft",
    verticalspeed = "verticalspeed",
    groundspeed = "groundspeed",
    tirespeed = "tirespeed",
    fmsflightphase = "fmsflightphase",
    vnavtoddist = "vnavtoddist",
    fmctransalt = "fmctransalt",
    fmctranslvl = "fmctranslvl",
    fmccruisealt = "fmccruisealt",
    depicao = "depicao",
    deprwy = "deprwy",
    desicao = "desicao",
    desrwy = "desrwy",
    fmsselectedsid = "fmsselectedsid",
    fmsselectedstar = "fmsselectedstar",
    fmsselectedapp = "fmsselectedapp",
    proceduretable = {},
    flightstate = 4
}
local baselineDef = {
    ON = 1,
    OFF = 0,
    FLIGHTSTATEPREFLIGHT = 0,
    FLIGHTSTATEINITIALCLIMB = 1,
    FLIGHTSTATECLIMB = 2,
    FLIGHTSTATEAPPROACH = 4,
    FLIGHTSTATETAXITOGATE = 5,
    FLIGHTSTATESHUTDOWN = 6,
    BEFORETAXIPROCEDURE = 5,
    BEFORETAKEOFFPROCEDURE = 6,
    CAPTURED = 2
}
local baselineValues = {
    api_version = 1,
    ready = 1,
    mode = 2,
    transport_state = 5,
    request_text = phraseCases[3][3],
    request_seq = 12,
    result_seq = 12,
    result_code = 21,
    result_detail = "SUBMITTED_VISIBLE",
    airgroundsensor = 0,
    radioaltitude = 5000,
    altitude_ft = 6000,
    pressure_altitude = 6000,
    verticalspeed = -800,
    groundspeed = 180,
    tirespeed = 0,
    fmsflightphase = 7,
    vnavtoddist = 0,
    fmctransalt = 7000,
    fmctranslvl = 7000,
    fmccruisealt = 37000,
    depicao = "ENAT",
    deprwy = "09",
    desicao = "ENSB",
    desrwy = "27",
    fmsselectedsid = "ATKUP1A",
    fmsselectedstar = "NELSA3M",
    fmsselectedapp = "R27-W",
    aircraft_icao = "B738"
}
autoUnicom.configure({
    yal = baselineYal,
    def = baselineDef,
    helpers = {
        logInfoTS = function() end,
        parseSelectedApproachId = function()
            return { suffix = "W", navType = "RNAV" }
        end
    },
    sources = {
        pressure_altitude = "pressure_altitude",
        aircraft_icao = "aircraft_icao"
    },
    getRefs = function() return repeatRefs end,
    read = function(prop) return baselineValues[prop] end
})
autoUnicom.tick(true, 0)
local repeatedBaseline, repeatedBaselineText = autoUnicom.repeatLastMessage(true)
assert_true(repeatedBaseline, "repeat baseline candidate accepted")
assert_equal(repeatedBaselineText, phraseCases[5][3], "repeat prefers skipped phase seven approach")

configure_repeat_test()
local repeated, repeatedText = autoUnicom.repeatLastMessage(true)
assert_true(repeated, "repeat last accepted")
assert_equal(repeatedText, phraseCases[5][3], "repeat last preserves exact text")
assert_equal(autoUnicom.getDebugState().queue_depth, 1, "repeat last queues one request")
local repeatedAgain, repeatPendingReason = autoUnicom.repeatLastMessage(true)
assert_equal(repeatedAgain, false, "repeat last blocks a pending duplicate")
assert_equal(repeatPendingReason, "request_pending", "repeat pending reason")

repeatValues.request_text = ""
configure_repeat_test()
local repeatedEmpty, repeatEmptyReason = autoUnicom.repeatLastMessage(true)
assert_equal(repeatedEmpty, false, "repeat last rejects empty history")
assert_equal(repeatEmptyReason, "no_last_message", "repeat empty reason")

repeatValues.request_text = phraseCases[5][3]
repeatValues.mode = 1
configure_repeat_test()
local repeatedDryRun, repeatDryRunReason = autoUnicom.repeatLastMessage(true)
assert_equal(repeatedDryRun, false, "repeat last requires send mode")
assert_equal(repeatDryRunReason, "send_mode_inactive", "repeat send mode reason")

local repeatedDisabled, repeatDisabledReason = autoUnicom.repeatLastMessage(false)
assert_equal(repeatedDisabled, false, "repeat last requires enabled feature")
assert_equal(repeatDisabledReason, "feature_disabled", "repeat disabled reason")

local persistentTaxiLogs = {}
local persistentTaxiWrites = {}
local persistentTaxiValues = {
    api_version = 1,
    ready = 1,
    mode = 2,
    transport_state = 5,
    request_seq = 20,
    result_seq = 20,
    result_code = 21,
    result_detail = "SUBMITTED_VISIBLE",
    airgroundsensor = 1,
    radioaltitude = 0,
    altitude_ft = 300,
    pressure_altitude = 300,
    verticalspeed = 0,
    groundspeed = 0,
    tirespeed = 0,
    fmsflightphase = 0,
    vnavtoddist = 100,
    fmctransalt = 7000,
    fmctranslvl = 7000,
    fmccruisealt = 37000,
    depicao = "ENAT",
    deprwy = "09",
    desicao = "ENSB",
    desrwy = "27",
    aircraft_icao = "B738",
    parkingbrakepos = 0,
    eng1n1percent = 20,
    eng2n1percent = 20
}
local persistentTaxiYal = {
    airgroundsensor = "airgroundsensor",
    radioaltitude = "radioaltitude",
    altitude_ft = "altitude_ft",
    altitude = "altitude_ft",
    verticalspeed = "verticalspeed",
    groundspeed = "groundspeed",
    tirespeed = "tirespeed",
    fmsflightphase = "fmsflightphase",
    vnavtoddist = "vnavtoddist",
    fmctransalt = "fmctransalt",
    fmctranslvl = "fmctranslvl",
    fmccruisealt = "fmccruisealt",
    depicao = "depicao",
    deprwy = "deprwy",
    desicao = "desicao",
    desrwy = "desrwy",
    parkingbrakepos = "parkingbrakepos",
    eng1n1percent = "eng1n1percent",
    eng2n1percent = "eng2n1percent",
    proceduretable = { [5] = { set = false }, [6] = { set = false } },
    procedureloop1 = { lock = 0 },
    procedureloop2 = { lock = 0 },
    procedureloop3 = { lock = 0 },
    ProcSetStatusarraydr = "procedureset",
    flightstate = 0
}
local persistentProcedureSet = 1
local function configure_persistent_taxi_test()
    autoUnicom.configure({
        yal = persistentTaxiYal,
        def = baselineDef,
        helpers = {
            logInfoTS = function(message) table.insert(persistentTaxiLogs, message) end
        },
        sources = {
            pressure_altitude = "pressure_altitude",
            aircraft_icao = "aircraft_icao"
        },
        getRefs = function() return repeatRefs end,
        read = function(prop, index)
            if prop == "procedureset" then
                return index == 5 and persistentProcedureSet or 0
            end
            return persistentTaxiValues[prop]
        end,
        writeText = function(_, text)
            table.insert(persistentTaxiWrites, { kind = "text", value = text })
            return true
        end,
        writeSeq = function(_, seq)
            table.insert(persistentTaxiWrites, { kind = "seq", value = seq })
            return true
        end
    })
end

configure_persistent_taxi_test()
autoUnicom.tick(true, 0)
persistentTaxiValues.tirespeed = 6
persistentTaxiValues.groundspeed = 6
autoUnicom.tick(true, 1)
autoUnicom.tick(true, 4)
assert_equal(persistentTaxiWrites[1].kind, "text", "persistent Before Taxi fallback writes text")
assert_equal(persistentTaxiWrites[1].value, phraseCases[9][3], "persistent Before Taxi fallback taxi phrase")
assert_true(
    table.concat(persistentTaxiLogs, "\n"):find("beforeTaxiSource=state_dataref", 1, true) ~= nil,
    "persistent Before Taxi source is logged"
)

persistentTaxiLogs = {}
persistentTaxiWrites = {}
persistentProcedureSet = 0
persistentTaxiYal.procedureloop1 = { lock = 5, stepindex = 0 }
persistentTaxiValues.tirespeed = 0
persistentTaxiValues.groundspeed = 0
configure_persistent_taxi_test()
autoUnicom.tick(true, 0)
persistentTaxiValues.tirespeed = 6
persistentTaxiValues.groundspeed = 6
autoUnicom.tick(true, 1)
autoUnicom.tick(true, 2)
assert_equal(#persistentTaxiWrites, 0, "reserved Before Taxi loop does not trigger taxi")
persistentTaxiYal.procedureloop1.stepindex = 1
autoUnicom.tick(true, 3)
autoUnicom.tick(true, 4)
assert_equal(persistentTaxiWrites[1].value, phraseCases[9][3], "accepted Before Taxi step triggers taxi")
assert_true(
    table.concat(persistentTaxiLogs, "\n"):find("beforeTaxiSource=active_loop", 1, true) ~= nil,
    "accepted Before Taxi loop source is logged"
)

local pushbackAdapterValues = {
    api_version = 1,
    ready = 1,
    mode = 2,
    transport_state = 5,
    request_seq = 30,
    result_seq = 30,
    result_code = 21,
    result_detail = "SUBMITTED_VISIBLE",
    airgroundsensor = 0,
    radioaltitude = 0,
    altitude_ft = 300,
    pressure_altitude = 300,
    verticalspeed = 0,
    groundspeed = 0,
    tirespeed = 0,
    fmsflightphase = 0,
    vnavtoddist = 100,
    fmctransalt = 7000,
    fmctranslvl = 7000,
    fmccruisealt = 37000,
    depicao = "ENAT",
    deprwy = "09",
    desicao = "ENSB",
    desrwy = "27",
    nearesticao = "ESSA",
    aircraftlatpos = 59.6519,
    aircraftlonpos = 17.9186,
    aircraft_icao = "B738"
}
local pushbackAdapterYal = copy(baselineYal, {
    nearesticao = "nearesticao",
    aircraftlatpos = "aircraftlatpos",
    aircraftlonpos = "aircraftlonpos",
    flightstate = baselineDef.FLIGHTSTATEPREFLIGHT
})
local pushbackAdapterWrites = {}
local pushbackRamp = { ramp_type = "misc", name = "Apron 42" }
local pushbackDistanceSquared = 25
local pushbackSearchAirports = {}
local function configure_pushback_adapter_test()
    autoUnicom.configure({
        yal = pushbackAdapterYal,
        def = baselineDef,
        helpers = {
            logInfoTS = function() end,
            forceCleanString = function(value) return tostring(value or "") end,
            extractprimaryicao = function(value) return tostring(value or "") end,
            isvalidicao = function(value) return type(value) == "string" and #value == 4 end,
            isRampSuitableFor738 = function(ramp)
                local rampType = ramp and ramp.ramp_type or ""
                return rampType == "gate" or rampType == "misc"
            end,
            getNearestRamp = function(icao, lat, lon, opts)
                table.insert(pushbackSearchAirports, icao)
                assert_equal(lat, pushbackAdapterValues.aircraftlatpos, "pushback search latitude")
                assert_equal(lon, pushbackAdapterValues.aircraftlonpos, "pushback search longitude")
                assert_true(opts.filter({ ramp_type = "gate" }), "pushback search accepts gate")
                assert_true(opts.filter({ ramp_type = "misc" }), "pushback search accepts misc")
                assert_equal(opts.filter({ ramp_type = "hangar" }), false, "pushback search rejects other ramp")
                return pushbackRamp, pushbackDistanceSquared
            end
        },
        sources = {
            pressure_altitude = "pressure_altitude",
            aircraft_icao = "aircraft_icao"
        },
        getRefs = function() return repeatRefs end,
        read = function(prop) return pushbackAdapterValues[prop] end,
        writeText = function(_, text)
            table.insert(pushbackAdapterWrites, { kind = "text", value = text })
            return true
        end,
        writeSeq = function(_, seq)
            table.insert(pushbackAdapterWrites, { kind = "seq", value = seq })
            return true
        end
    })
end

configure_pushback_adapter_test()
autoUnicom.tick(true, 0)
assert_equal(#pushbackSearchAirports, 0, "preflight sensor transient does not baseline pushback")
pushbackAdapterValues.airgroundsensor = 1
pushbackAdapterValues.tirespeed = -3
pushbackAdapterValues.groundspeed = 2
autoUnicom.tick(true, 1)
autoUnicom.tick(true, 3)
assert_equal(pushbackSearchAirports[1], "ESSA", "nearest airport drives pushback ramp search")
assert_equal(pushbackAdapterWrites[1].value, "ESSA Traffic, B738, pushing back from stand 42",
    "adapter uses nearest misc ramp instead of searching past it for gate")

pushbackAdapterWrites = {}
pushbackSearchAirports = {}
pushbackAdapterValues.nearesticao = ""
pushbackAdapterValues.tirespeed = 0
pushbackAdapterValues.groundspeed = 0
pushbackRamp = { ramp_type = "gate", name = "Gate A12" }
pushbackDistanceSquared = 81 * 81
configure_pushback_adapter_test()
autoUnicom.tick(true, 0)
pushbackAdapterValues.tirespeed = -3
pushbackAdapterValues.groundspeed = 2
autoUnicom.tick(true, 1)
autoUnicom.tick(true, 3)
assert_equal(pushbackSearchAirports[1], "ENAT", "departure airport is pushback search fallback")
assert_equal(pushbackAdapterWrites[1].value, phraseCases[8][3],
    "pushback ramp beyond 80 meters keeps generic phrase")

local runwaySurface = true
local runwayVacatedWrites = {}
local runwayVacatedYal = copy(persistentTaxiYal, {
    flightstate = baselineDef.FLIGHTSTATETAXITOGATE,
    isAircraftOnArrivalRunwaySurface = function(distanceMeters)
        assert_equal(distanceMeters, 40, "arrival runway surface check distance")
        return runwaySurface
    end,
    isArrivalRunwayRadioAltGateOpen = function(maxDistanceNm, maxHeadingDiff, maxCrossTrackNm)
        assert_equal(maxDistanceNm, 8, "final runway gate distance")
        assert_equal(maxHeadingDiff, 20, "final runway gate heading")
        assert_equal(maxCrossTrackNm, 0.5, "final runway gate cross-track")
        return false
    end
})
local runwayVacatedValues = copy(persistentTaxiValues, {
    airgroundsensor = 1,
    groundspeed = 15,
    tirespeed = 15,
    fmsflightphase = 0
})
autoUnicom.configure({
    yal = runwayVacatedYal,
    def = baselineDef,
    helpers = { logInfoTS = function() end },
    sources = {
        pressure_altitude = "pressure_altitude",
        aircraft_icao = "aircraft_icao"
    },
    getRefs = function() return repeatRefs end,
    read = function(prop)
        return runwayVacatedValues[prop] or repeatValues[prop]
    end,
    writeText = function(_, text)
        table.insert(runwayVacatedWrites, { kind = "text", value = text })
        return true
    end,
    writeSeq = function(_, seq)
        table.insert(runwayVacatedWrites, { kind = "seq", value = seq })
        return true
    end
})
autoUnicom.tick(true, 0)
autoUnicom.tick(true, 2)
assert_equal(#runwayVacatedWrites, 0, "TAXITOGATE while on runway emits no vacated report")
runwaySurface = false
autoUnicom.tick(true, 3)
autoUnicom.tick(true, 4.9)
assert_equal(#runwayVacatedWrites, 0, "adapter runway-clear state is debounced")
autoUnicom.tick(true, 5.9)
assert_equal(runwayVacatedWrites[1].value, phraseCases[7][3], "adapter emits vacated after stable clear state")

local holdAdapterValues = copy(baselineValues, {
    hold_api_version = 1,
    hold_update_seq = 2,
    hold_active = 0,
    hold_entry_complete = 0,
    hold_exit_armed = 0,
    hold_waypoint = "",
    hold_path_type = "",
    hold_target_altitude_ft = 0,
    hold_target_altitude_valid = 0,
    hold_legacy_nav_mode = 3,
    hold_legacy_path_type = "HF",
    hold_legacy_waypoint = "ROBUR",
    hold_legacy_phase = 0,
    hold_legacy_term = 2
})
local holdAdapterYal = copy(baselineYal, {
    holdRuntime = {
        api_version = "hold_api_version",
        update_seq = "hold_update_seq",
        active = "hold_active",
        entry_complete = "hold_entry_complete",
        exit_armed = "hold_exit_armed",
        waypoint = "hold_waypoint",
        path_type = "hold_path_type",
        target_altitude_ft = "hold_target_altitude_ft",
        target_altitude_valid = "hold_target_altitude_valid"
    },
    fmsnavmode = "hold_legacy_nav_mode",
    fmsgpswptpath = "hold_legacy_path_type",
    fmsfplnnavid = "hold_legacy_waypoint",
    fmsholdphase = "hold_legacy_phase",
    fmsholdterm = "hold_legacy_term"
})
local holdAdapterWrites = {}
local holdAdapterLogs = {}
local function configure_hold_adapter(values, readOverride)
    autoUnicom.configure({
        yal = holdAdapterYal,
        def = baselineDef,
        helpers = { logInfoTS = function(message) table.insert(holdAdapterLogs, message) end },
        sources = {
            pressure_altitude = "pressure_altitude",
            aircraft_icao = "aircraft_icao"
        },
        getRefs = function() return repeatRefs end,
        read = readOverride or function(prop) return values[prop] end,
        writeText = function(_, text)
            table.insert(holdAdapterWrites, { kind = "text", value = text })
            return true
        end,
        writeSeq = function(_, seq)
            table.insert(holdAdapterWrites, { kind = "seq", value = seq })
            return true
        end
    })
end

configure_hold_adapter(holdAdapterValues)
autoUnicom.tick(true, 0)
autoUnicom.tick(true, 1)
assert_equal(#holdAdapterWrites, 0, "stable inactive API is authoritative over stale active legacy refs")
holdAdapterValues.hold_update_seq = 4
holdAdapterValues.hold_active = 1
holdAdapterValues.hold_waypoint = "BIRCO"
holdAdapterValues.hold_path_type = "HM"
holdAdapterValues.hold_target_altitude_ft = 10000
holdAdapterValues.hold_target_altitude_valid = 1
autoUnicom.tick(true, 2)
assert_equal(holdAdapterWrites[1].value, phraseCases[16][3], "stable API snapshot emits hold entry")
assert_true(table.concat(holdAdapterLogs, "\n"):find("holdSource=api", 1, true) ~= nil,
    "API hold source is logged")
holdAdapterValues.result_seq = 13
holdAdapterValues.result_code = 21
autoUnicom.tick(true, 3)
holdAdapterValues.hold_update_seq = 6
holdAdapterValues.hold_exit_armed = 1
autoUnicom.tick(true, 4)
assert_equal(holdAdapterWrites[3].value, phraseCases[17][3], "API exit armed emits hold exit")
holdAdapterValues.result_seq = 14
holdAdapterValues.hold_update_seq = 8
holdAdapterValues.hold_active = 0
holdAdapterValues.hold_exit_armed = 0
holdAdapterValues.hold_waypoint = ""
holdAdapterValues.hold_path_type = ""
holdAdapterValues.hold_target_altitude_ft = 0
holdAdapterValues.hold_target_altitude_valid = 0
autoUnicom.tick(true, 5)
assert_equal(#holdAdapterWrites, 4, "active drop does not duplicate API armed exit")

local oddHoldValues = copy(holdAdapterValues, {
    request_seq = 20,
    result_seq = 20,
    result_code = 21,
    hold_update_seq = 3,
    hold_active = 1,
    hold_waypoint = "WRONG",
    hold_path_type = "HM",
    hold_legacy_nav_mode = 0,
    hold_legacy_path_type = "",
    hold_legacy_waypoint = "",
    hold_legacy_term = 0
})
holdAdapterWrites = {}
holdAdapterLogs = {}
configure_hold_adapter(oddHoldValues)
autoUnicom.tick(true, 0)
oddHoldValues.hold_legacy_nav_mode = 3
oddHoldValues.hold_legacy_path_type = "HA"
oddHoldValues.hold_legacy_waypoint = "LALAD"
autoUnicom.tick(true, 1)
assert_equal(holdAdapterWrites[1].value, "Traffic, B738, entering a hold over LALAD",
    "odd API sequence uses legacy hold fallback")
assert_true(table.concat(holdAdapterLogs, "\n"):find("holdSource=legacy", 1, true) ~= nil,
    "odd API fallback source is logged")
oddHoldValues.result_seq = 21
oddHoldValues.result_code = 21
autoUnicom.tick(true, 2)
oddHoldValues.hold_legacy_term = 2
autoUnicom.tick(true, 3)
assert_equal(holdAdapterWrites[3].value, "Traffic, B738, exiting hold over LALAD",
    "legacy EXEC hold term emits hold exit")

local changingHoldValues = copy(oddHoldValues, {
    request_seq = 30,
    result_seq = 30,
    hold_legacy_nav_mode = 0,
    hold_legacy_path_type = "",
    hold_legacy_waypoint = "",
    hold_legacy_term = 0
})
local changingSeq = 0
holdAdapterWrites = {}
holdAdapterLogs = {}
configure_hold_adapter(changingHoldValues, function(prop)
    if prop == "hold_update_seq" then
        changingSeq = changingSeq + 2
        return changingSeq
    end
    return changingHoldValues[prop]
end)
autoUnicom.tick(true, 0)
changingHoldValues.hold_legacy_nav_mode = 3
changingHoldValues.hold_legacy_path_type = "HF"
changingHoldValues.hold_legacy_waypoint = "OKDIT"
autoUnicom.tick(true, 1)
assert_equal(holdAdapterWrites[1].value, "Traffic, B738, entering a hold over OKDIT",
    "changing API sequence uses legacy hold fallback")

print("auto_unicom tests passed")
