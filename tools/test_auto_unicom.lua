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
    climb_next_waypoint = "BIRCO",
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
        "Traffic, B738 climbing out of ENAT on ATKUP1A departure, passing 1800ft for FL370, BIRCO next"
    },
    {
        "arrival.top_of_descent",
        copy(base, { altitude_ft = 37000, pressure_altitude_ft = 37000 }),
        "ENSB Traffic, B738, NELSA3M arrival at TOD, leaving FL370, expecting runway 27"
    },
    {
        "arrival.on_descent",
        copy(base, { altitude_ft = 18000, pressure_altitude_ft = 18000 }),
        "ENSB Traffic, B738 NELSA3M arrival for RNAV W approach runway 27, descent started from FL370"
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
        "Traffic, B738 climbing out of ENAT, passing FL100 for FL370, BIRCO next"
    },
    {
        "departure.climb_level_20000",
        copy(base, { altitude_ft = 20000, pressure_altitude_ft = 20000 }),
        "Traffic, B738 climbing out of ENAT, passing FL200 for FL370, BIRCO next"
    },
    {
        "departure.climb_level_30000",
        copy(base, { altitude_ft = 30000, pressure_altitude_ft = 30000 }),
        "Traffic, B738 climbing out of ENAT, passing FL300 for FL370, BIRCO next"
    },
    {
        "departure.climb_level_40000",
        copy(base, { altitude_ft = 40000, pressure_altitude_ft = 40000, planned_altitude_ft = 41000 }),
        "Traffic, B738 climbing out of ENAT, passing FL400 for FL410, BIRCO next"
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
    },
    {
        "departure.hold_short",
        base,
        "ENAT Traffic, B738 holding short runway 09"
    },
    {
        "departure.hold_short",
        copy(base, { departure_intersection = "Intersection A" }),
        "ENAT Traffic, B738 holding short runway 09 at intersection A"
    },
    {
        "departure.backtrack",
        copy(base, { departure_intersection = "A" }),
        "ENAT Traffic, B738 backtracking runway 09, intersection A"
    },
    {
        "departure.intersection",
        copy(base, { departure_intersection = "A" }),
        "ENAT Traffic, B738 lining up runway 09, intersection A"
    },
    {
        "arrival.short_final",
        base,
        "ENSB Traffic, B738 on SHORT FINAL runway 27 - Landing is imminent"
    },
    {
        "enroute.in_cruise",
        copy(base, { cruise_waypoint = "BIRCO", altitude_ft = 37000, pressure_altitude_ft = 37000 }),
        "Traffic, B738 passing BIRCO, maintaining FL370"
    },
    {
        "enroute.holding",
        copy(base, { hold_waypoint = "BIRCO", altitude_ft = 37000, pressure_altitude_ft = 37000 }),
        "Traffic, B738 maintaining FL370 whilst holding over BIRCO"
    },
    {
        "enroute.hold_descending",
        copy(base, {
            hold_waypoint = "BIRCO",
            hold_target_altitude_ft = 25000,
            altitude_ft = 37000,
            pressure_altitude_ft = 37000
        }),
        "Traffic, B738, in a hold over BIRCO on descent passing FL370 for FL250"
    },
    {
        "arrival.backtrack",
        base,
        "ENSB Traffic, B738 backtracking runway 27"
    },
    {
        "arrival.parking_position",
        copy(base, {
            arrival_parking_found = true,
            arrival_parking_type = "gate",
            arrival_parking_name = "Gate B7"
        }),
        "ENSB Traffic, B738 parked at gate B7"
    },
    {
        "departure.flightplan_active",
        copy(base, {
            preflight_parking_found = true,
            preflight_parking_type = "gate",
            preflight_parking_name = "Gate 4"
        }),
        "ENAT Traffic, B738 at gate 4, preparing for departure to ENSB"
    },
    {
        "departure.runway_crossing",
        copy(base, { crossing_runway = "08", crossing_taxiway = "Z" }),
        "ENAT Traffic, B738 crossing runway 08 at taxiway Z"
    },
    {
        "arrival.runway_crossing",
        copy(base, { crossing_runway = "16" }),
        "ENSB Traffic, B738 crossing runway 16"
    },
    {
        "departure.lining_up",
        base,
        "ENAT Traffic, B738 lining up runway 09"
    }
}

for _, case in ipairs(phraseCases) do
    local text = core.buildMessage(case[1], case[2])
    assert_equal(text, case[3], "phrase " .. case[1])
    assert_true(not text:lower():find(" the ", 1, true), "phrase has no 'the' " .. case[1])
end

assert_equal(
    core.buildMessage("arrival.on_descent", copy(base, {
        altitude_ft = 18000,
        pressure_altitude_ft = 18000,
        planned_altitude_ft = 0
    })),
    "ENSB Traffic, B738 NELSA3M arrival for RNAV W approach runway 27, descent started from FL180",
    "descent-start phrase falls back to current altitude"
)

local missingText, missingReason = core.buildMessage(
    "departure.airborne",
    copy(base, { departure_icao = "" })
)
assert_equal(missingText, nil, "missing departure ICAO rejects phrase")
assert_equal(missingReason, "missing_departure_context", "missing departure reason")

missingText, missingReason = core.buildMessage(
    "departure.flightplan_active",
    copy(base, { arrival_icao = "" })
)
assert_equal(missingText, nil, "missing preflight destination rejects phrase")
assert_equal(missingReason, "missing_preflight_context", "missing preflight destination reason")

missingText, missingReason = core.buildMessage(
    "departure.runway_crossing",
    copy(base, { crossing_runway = "" })
)
assert_equal(missingText, nil, "runway crossing requires runway")
assert_equal(missingReason, "missing_runway_crossing_context", "missing crossing runway reason")

missingText, missingReason = core.buildMessage(
    "arrival.runway_crossing",
    copy(base, { arrival_icao = "", crossing_runway = "16" })
)
assert_equal(missingText, nil, "arrival runway crossing requires airport")
assert_equal(missingReason, "missing_runway_crossing_context", "missing crossing airport reason")

local genericPreflightText = core.buildMessage("departure.flightplan_active", base)
assert_equal(genericPreflightText,
    "ENAT Traffic, B738 at parking position, preparing for departure to ENSB",
    "preflight phrase falls back without ramp label")

missingText, missingReason = core.buildMessage(
    "arrival.approach",
    copy(base, { arrival_runway = "" })
)
assert_equal(missingText, nil, "missing arrival runway rejects phrase")
assert_equal(missingReason, "missing_arrival_context", "missing arrival reason")

missingText, missingReason = core.buildMessage(
    "arrival.short_final",
    copy(base, { arrival_runway = "" })
)
assert_equal(missingText, nil, "short final requires arrival runway")
assert_equal(missingReason, "missing_short_final_context", "missing short final reason")

missingText, missingReason = core.buildMessage(
    "arrival.backtrack",
    copy(base, { arrival_runway = "" })
)
assert_equal(missingText, nil, "arrival backtrack requires arrival runway")
assert_equal(missingReason, "missing_arrival_backtrack_context", "missing arrival backtrack reason")

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
    core.buildMessage("departure.flightplan_active", copy(base, {
        departure_icao = "EDNY",
        arrival_icao = "EVRA",
        preflight_parking_found = true,
        preflight_parking_type = "tie_down",
        preflight_parking_name = "heavy|jets Apron 1 - Terminal"
    })),
    "EDNY Traffic, B738 at stand 1, preparing for departure to EVRA",
    "preflight strips EDNY ramp descriptor punctuation"
)
assert_equal(
    core.buildMessage("departure.flightplan_active", copy(base, {
        departure_icao = "KMIA",
        arrival_icao = "KMSY",
        preflight_parking_found = true,
        preflight_parking_type = "misc",
        preflight_parking_name = "REMOTE E 28"
    })),
    "KMIA Traffic, B738 at stand E28, preparing for departure to KMSY",
    "preflight extracts split stand identifier from KMIA descriptor"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_airport_icao = "EDNY",
        pushback_parking_found = true,
        pushback_parking_type = "tie_down",
        pushback_parking_name = "heavy|jets Apron 1 - Terminal"
    })),
    "EDNY Traffic, B738, pushing back from stand 1",
    "pushback strips EDNY ramp descriptor punctuation"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_airport_icao = "KMIA",
        pushback_parking_found = true,
        pushback_parking_type = "misc",
        pushback_parking_name = "REMOTE E 28"
    })),
    "KMIA Traffic, B738, pushing back from stand E28",
    "pushback extracts split stand identifier from KMIA descriptor"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_parking_found = true,
        pushback_parking_type = "gate",
        pushback_parking_name = "Gate B7, North"
    })),
    "ENAT Traffic, B738, pushing back from gate B7",
    "pushback strips comma-delimited ramp descriptor"
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
        pushback_parking_type = "gate",
        pushback_parking_name = "Gate -"
    })),
    phraseCases[8][3],
    "generic pushback phrase for punctuation-only gate"
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
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "Apron 42"
    })),
    "ENSB Traffic, B738 parked at stand 42",
    "arrival parking stand phrase"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "4 SMALL"
    })),
    "ENSB Traffic, B738 parked at stand 4",
    "arrival parking strips stand size suffix"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "HEAVY 4L"
    })),
    "ENSB Traffic, B738 parked at gate 4L",
    "arrival parking keeps attached gate suffix"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "Gate A-12"
    })),
    "ENSB Traffic, B738 parked at gate A12",
    "arrival parking normalizes embedded punctuation"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "4 R MEDIUM"
    })),
    "ENSB Traffic, B738 parked at stand 4R",
    "arrival parking compacts separate stand suffix"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "REMOTE E 28"
    })),
    "ENSB Traffic, B738 parked at stand E28",
    "arrival parking extracts split stand identifier from descriptor"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "Terminal 2 Gate E 28"
    })),
    "ENSB Traffic, B738 parked at gate E28",
    "arrival parking prefers marked identifier over descriptor number"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "jets|turboprops|props 216"
    })),
    "ENSB Traffic, B738 parked at gate 216",
    "arrival parking strips complete EVRA aircraft class field"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "Gate"
    })),
    "ENSB Traffic, B738 parked at parking position",
    "arrival unnamed parking phrase"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "REMOTE NORTH"
    })),
    "ENSB Traffic, B738 parked at parking position",
    "arrival descriptor-only name uses generic parking phrase"
)
missingText, missingReason = core.buildMessage("arrival.parking_position", base)
assert_equal(missingText, nil, "arrival parking requires nearby ramp")
assert_equal(missingReason, "missing_arrival_parking_context", "missing arrival parking reason")

assert_equal(
    core.buildMessage("departure.on_climb", copy(base, {
        altitude_ft = 1800,
        pressure_altitude_ft = 1800,
        climb_next_waypoint = ""
    })),
    "Traffic, B738 climbing out of ENAT on ATKUP1A departure, passing 1800ft for FL370",
    "initial climb phrase retains SID and tolerates missing next waypoint"
)
assert_equal(
    core.buildMessage("enroute.in_cruise", copy(base, {
        cruise_entry = true,
        cruise_next_waypoint = "BIRCO",
        altitude_ft = 38795,
        pressure_altitude_ft = 38824,
        planned_altitude_ft = 39000
    })),
    "Traffic, B738 level at FL390, BIRCO next",
    "cruise entry phrase uses nominal FMC cruise level"
)
assert_equal(
    core.buildMessage("enroute.in_cruise", copy(base, {
        cruise_entry = true,
        cruise_next_waypoint = "",
        altitude_ft = 37000,
        pressure_altitude_ft = 37000,
        planned_altitude_ft = 0
    })),
    "Traffic, B738 level at FL370",
    "cruise entry falls back to live altitude and tolerates missing next waypoint"
)
assert_equal(
    core.buildMessage("enroute.in_cruise", copy(base, {
        cruise_waypoint = "BIRCO",
        cruise_next_waypoint = "SOMOR",
        altitude_ft = 38795,
        pressure_altitude_ft = 38824,
        planned_altitude_ft = 39000
    })),
    "Traffic, B738 passing BIRCO, maintaining FL388, SOMOR next",
    "recurring cruise phrase keeps live pressure altitude"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "cargo",
        arrival_parking_name = "Cargo 12"
    })),
    "ENSB Traffic, B738 parked at stand CARGO 12",
    "arrival parking accepts unfiltered ramp type"
)

assert_equal(
    core.buildMessage("arrival.on_final", copy(base, { approach_procedure_type = "LOC" })),
    "ENSB Traffic, B738 established on Localizer runway 27",
    "LOC final phrase"
)

local missingHoldText, missingHoldReason = core.buildMessage("enroute.hold_enter", base)
assert_equal(missingHoldText, nil, "hold phrase requires waypoint")
assert_equal(missingHoldReason, "missing_hold_context", "missing hold waypoint reason")

local missingCruiseText, missingCruiseReason = core.buildMessage("enroute.in_cruise", base)
assert_equal(missingCruiseText, nil, "cruise phrase requires waypoint")
assert_equal(missingCruiseReason, "missing_cruise_context", "missing cruise waypoint reason")

local missingHoldDescentText, missingHoldDescentReason = core.buildMessage(
    "enroute.hold_descending",
    copy(base, { hold_waypoint = "BIRCO" })
)
assert_equal(missingHoldDescentText, nil, "hold descent phrase requires target altitude")
assert_equal(missingHoldDescentReason, "missing_hold_descent_context", "missing hold descent target reason")

local missingIntersectionText, missingIntersectionReason = core.buildMessage("departure.intersection", base)
assert_equal(missingIntersectionText, nil, "legacy intersection line-up requires intersection")
assert_equal(missingIntersectionReason, "missing_intersection_context", "missing intersection reason")
assert_equal(
    core.buildMessage("departure.lining_up", copy(base, { departure_intersection = "Intersection A" })),
    "ENAT Traffic, B738 lining up runway 09, intersection A",
    "line-up phrase keeps optional intersection"
)

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
    id = "arrival.on_final",
    text = phraseCases[6][3],
    expires_at = 100
}), "enqueue final supersession")
assert_equal(#supersessionMailbox.queue, 1, "final supersedes approach")
assert_equal(supersessionMailbox.queue[1].id, "arrival.on_final", "final remains queued")
assert_true(supersessionMailbox:enqueue({
    id = "arrival.short_final",
    text = phraseCases[22][3],
    expires_at = 100
}), "enqueue short-final supersession")
assert_equal(#supersessionMailbox.queue, 1, "short final supersedes final")
assert_equal(supersessionMailbox.queue[1].id, "arrival.short_final", "short final remains queued")
assert_true(supersessionMailbox:enqueue({
    id = "departure.taxi_runway",
    text = phraseCases[9][3],
    expires_at = 100
}), "enqueue unrelated departure event before go-around cancellation")
supersessionMailbox:cancelQueuedForGoAround()
assert_equal(#supersessionMailbox.queue, 1, "go-around cancellation removes only queued arrival events")
assert_equal(supersessionMailbox.queue[1].id, "departure.taxi_runway", "go-around cancellation preserves departure event")
assert_equal(supersessionLogs[#supersessionLogs].kind, "cancelled_go_around", "go-around queue cancellation logged")

local parkingMailbox = core.newMailbox({})
assert_true(parkingMailbox:enqueue({
    id = "arrival.runway_vacated",
    text = phraseCases[7][3],
    expires_at = 100
}), "enqueue runway vacated before parking")
assert_true(parkingMailbox:enqueue({
    id = "arrival.runway_crossing",
    text = "ENSB Traffic, B738 crossing runway 16",
    expires_at = 100
}), "enqueue runway crossing before parking")
assert_true(parkingMailbox:enqueue({
    id = "arrival.parking_position",
    text = "ENSB Traffic, B738 parked at gate B7",
    expires_at = 100
}), "enqueue arrival parking supersession")
assert_equal(#parkingMailbox.queue, 1, "parking supersedes queued runway-crossing report")
assert_equal(parkingMailbox.queue[1].id, "arrival.parking_position", "parking report remains queued")

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
    id = "enroute.holding",
    text = core.buildMessage("enroute.holding", copy(base, {
        hold_waypoint = "BIRCO",
        altitude_ft = 37000,
        pressure_altitude_ft = 37000
    })),
    expires_at = 100
}), "enqueue established hold supersession")
assert_equal(#holdMailbox.queue, 1, "established hold supersedes queued hold entry")
assert_equal(holdMailbox.queue[1].id, "enroute.holding", "established hold remains queued")
assert_true(holdMailbox:enqueue({
    id = "enroute.hold_descending",
    text = core.buildMessage("enroute.hold_descending", copy(base, {
        hold_waypoint = "BIRCO",
        hold_target_altitude_ft = 25000,
        altitude_ft = 37000,
        pressure_altitude_ft = 37000
    })),
    expires_at = 100
}), "enqueue descending hold supersession")
assert_equal(#holdMailbox.queue, 1, "descending hold supersedes established hold")
assert_equal(holdMailbox.queue[1].id, "enroute.hold_descending", "descending hold remains queued")
assert_true(holdMailbox:enqueue({
    id = "enroute.hold_exit",
    text = phraseCases[17][3],
    expires_at = 100
}), "enqueue hold exit supersession")
assert_equal(#holdMailbox.queue, 1, "hold exit supersedes queued hold state")
assert_equal(holdMailbox.queue[1].id, "enroute.hold_exit", "hold exit remains queued")
assert_equal(holdMailboxLogs[1].kind, "superseded", "hold supersession logged")
holdMailbox = core.newMailbox({
    log = function(kind, event) table.insert(holdMailboxLogs, { kind = kind, event = event }) end
})
assert_true(holdMailbox:enqueue({
    id = "enroute.hold_descending",
    text = core.buildMessage("enroute.hold_descending", copy(base, {
        hold_waypoint = "BIRCO",
        hold_target_altitude_ft = 25000,
        altitude_ft = 37000,
        pressure_altitude_ft = 37000
    })),
    expires_at = 100
}), "enqueue hold descent before cancellation")
assert_true(holdMailbox:enqueue({
    id = "departure.taxi_runway",
    text = phraseCases[9][3],
    expires_at = 100
}), "enqueue unrelated event before hold cancellation")
holdMailbox:cancelQueuedForHoldEnd()
assert_equal(#holdMailbox.queue, 1, "hold cancellation removes only hold state")
assert_equal(holdMailbox.queue[1].id, "departure.taxi_runway", "hold cancellation preserves unrelated event")
assert_equal(holdMailboxLogs[#holdMailboxLogs].kind, "cancelled_hold_end", "hold cancellation logged")

holdMailbox = core.newMailbox({
    log = function(kind, event) table.insert(holdMailboxLogs, { kind = kind, event = event }) end
})
assert_true(holdMailbox:enqueue({
    id = "arrival.approach",
    text = phraseCases[5][3],
    expires_at = 100
}), "enqueue approach before hold start")
assert_true(holdMailbox:enqueue({
    id = "arrival.descent_level_10000",
    text = core.buildMessage("arrival.descent_level_10000", copy(base, {
        altitude_ft = 10000,
        pressure_altitude_ft = 10000
    })),
    expires_at = 100
}), "enqueue descent level before hold start")
holdMailbox:cancelQueuedForHoldStart()
assert_equal(#holdMailbox.queue, 1, "hold start removes only approach and final events")
assert_equal(holdMailbox.queue[1].id, "arrival.descent_level_10000",
    "hold start preserves ordinary descent-level event")
assert_equal(holdMailboxLogs[#holdMailboxLogs].kind, "cancelled_hold_start",
    "hold start cancellation logged")

local holdExitApproachOrder = core.newMailbox()
assert_true(holdExitApproachOrder:enqueue({
    id = "enroute.hold_exit",
    text = phraseCases[17][3],
    expires_at = 100
}), "enqueue hold exit before deferred approach")
assert_true(holdExitApproachOrder:enqueue({
    id = "arrival.approach",
    text = phraseCases[5][3],
    expires_at = 100
}), "enqueue deferred approach after hold exit")
assert_equal(#holdExitApproachOrder.queue, 2, "hold exit and deferred approach remain queued")
assert_equal(holdExitApproachOrder.queue[1].id, "enroute.hold_exit", "hold exit remains first")
assert_equal(holdExitApproachOrder.queue[2].id, "arrival.approach", "deferred approach remains second")
assert_true(holdExitApproachOrder:enqueue({
    id = "arrival.on_final",
    text = phraseCases[6][3],
    expires_at = 100
}), "enqueue final after hold exit")
assert_equal(#holdExitApproachOrder.queue, 2, "final supersedes deferred approach after hold exit")
assert_equal(holdExitApproachOrder.queue[1].id, "enroute.hold_exit", "hold exit remains ahead of final")
assert_equal(holdExitApproachOrder.queue[2].id, "arrival.on_final", "final follows hold exit")

local departureSupersession = core.newMailbox()
assert_true(departureSupersession:enqueue({
    id = "departure.flightplan_active",
    text = "ENAT Traffic, B738 at gate 4, preparing for departure to ENSB",
    expires_at = 100
}), "enqueue preflight before supersession")
assert_true(departureSupersession:enqueue({
    id = "departure.start_push",
    text = phraseCases[8][3],
    expires_at = 100
}), "enqueue push before supersession")
assert_equal(#departureSupersession.queue, 1, "push supersedes queued preflight")
assert_equal(departureSupersession.queue[1].id, "departure.start_push", "push remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.taxi_runway",
    text = phraseCases[9][3],
    expires_at = 100
}), "enqueue taxi supersession")
assert_equal(#departureSupersession.queue, 1, "taxi supersedes queued push")
assert_equal(departureSupersession.queue[1].id, "departure.taxi_runway", "taxi remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.runway_crossing",
    text = "ENAT Traffic, B738 crossing runway 08 at taxiway Z",
    expires_at = 100
}), "enqueue departure crossing supersession")
assert_equal(#departureSupersession.queue, 1, "crossing supersedes taxi")
assert_equal(departureSupersession.queue[1].id, "departure.runway_crossing", "crossing remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.hold_short",
    text = phraseCases[18][3],
    expires_at = 100
}), "enqueue hold-short supersession")
assert_equal(#departureSupersession.queue, 1, "hold short supersedes crossing")
assert_equal(departureSupersession.queue[1].id, "departure.hold_short", "hold short remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.backtrack",
    text = phraseCases[20][3],
    expires_at = 100
}), "enqueue backtrack supersession")
assert_equal(#departureSupersession.queue, 1, "backtrack supersedes hold short")
assert_equal(departureSupersession.queue[1].id, "departure.backtrack", "backtrack remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.lining_up",
    text = phraseCases[#phraseCases][3],
    expires_at = 100
}), "enqueue line-up supersession")
assert_equal(#departureSupersession.queue, 1, "line-up supersedes backtrack")
assert_equal(departureSupersession.queue[1].id, "departure.lining_up", "line-up remains queued")
assert_true(departureSupersession:enqueue({
    id = "departure.lineup_takeoff",
    text = phraseCases[10][3],
    expires_at = 100
}), "enqueue takeoff supersession")
assert_equal(#departureSupersession.queue, 1, "takeoff supersedes line-up")
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

local arrivalSupersession = core.newMailbox()
assert_true(arrivalSupersession:enqueue({
    id = "arrival.short_final",
    text = phraseCases[22][3],
    expires_at = 100
}), "enqueue short final before arrival backtrack")
assert_true(arrivalSupersession:enqueue({
    id = "arrival.backtrack",
    text = "ENSB Traffic, B738 backtracking runway 27",
    expires_at = 100
}), "enqueue arrival backtrack supersession")
assert_equal(#arrivalSupersession.queue, 1, "arrival backtrack supersedes short final")
assert_equal(arrivalSupersession.queue[1].id, "arrival.backtrack", "arrival backtrack remains queued")
assert_true(arrivalSupersession:enqueue({
    id = "arrival.runway_vacated",
    text = phraseCases[7][3],
    expires_at = 100
}), "enqueue runway vacated supersession")
assert_equal(#arrivalSupersession.queue, 1, "runway vacated supersedes arrival backtrack")
assert_equal(arrivalSupersession.queue[1].id, "arrival.runway_vacated", "runway vacated remains queued")
assert_true(arrivalSupersession:enqueue({
    id = "arrival.runway_crossing",
    text = "ENSB Traffic, B738 crossing runway 16",
    expires_at = 100
}), "enqueue arrival crossing supersession")
assert_equal(#arrivalSupersession.queue, 1, "arrival crossing supersedes runway vacated")
assert_equal(arrivalSupersession.queue[1].id, "arrival.runway_crossing", "arrival crossing remains queued")
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

local eventAdapterValues = {
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
    fmsselectedsid = "ATKUP1A",
    fmsselectedstar = "NELSA3M",
    fmsselectedapp = "R27-W",
    nearesticao = "ESSA",
    aircraftlatpos = 59.6519,
    aircraftlonpos = 17.9186,
    autogate_gpu = 1,
    autogate_nearest = 10 / 1852,
    autogate_nearest_name = "4",
    aircraft_icao = "B738"
}
local eventAdapterYal = copy(baselineYal, {
    nearesticao = "nearesticao",
    aircraftlatpos = "aircraftlatpos",
    aircraftlonpos = "aircraftlonpos",
    autogategpu = "autogate_gpu",
    autogatenearest = "autogate_nearest",
    autogatenearestname = "autogate_nearest_name",
    flightstate = baselineDef.FLIGHTSTATEPREFLIGHT
})
local eventAdapterWrites = {}
local eventAdapterLogs = {}
local pushbackRamp = { ramp_type = "misc", name = "Apron 42" }
local pushbackDistanceSquared = 25
local pushbackSearchAirports = {}
local function configure_event_adapter_test()
    autoUnicom.configure({
        yal = eventAdapterYal,
        def = baselineDef,
        helpers = {
            logInfoTS = function(message) table.insert(eventAdapterLogs, message) end,
            forceCleanString = function(value) return tostring(value or "") end,
            extractprimaryicao = function(value) return tostring(value or "") end,
            isvalidicao = function(value) return type(value) == "string" and #value == 4 end,
            getNearestRamp = function(icao, lat, lon, opts)
                table.insert(pushbackSearchAirports, icao)
                assert_equal(lat, eventAdapterValues.aircraftlatpos, "pushback search latitude")
                assert_equal(lon, eventAdapterValues.aircraftlonpos, "pushback search longitude")
                assert_equal(opts, nil, "nearest ramp search has no suitability filter")
                return pushbackRamp, pushbackDistanceSquared
            end
        },
        sources = {
            pressure_altitude = "pressure_altitude",
            aircraft_icao = "aircraft_icao"
        },
        getRefs = function() return repeatRefs end,
        read = function(prop) return eventAdapterValues[prop] end,
        writeText = function(_, text)
            table.insert(eventAdapterWrites, { kind = "text", value = text })
            return true
        end,
        writeSeq = function(_, seq)
            table.insert(eventAdapterWrites, { kind = "seq", value = seq })
            return true
        end
    })
end

configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_equal(#pushbackSearchAirports, 0, "activation does not infer a preflight event")
pushbackRamp = { ramp_type = "gate", name = "Gate 4" }
pushbackDistanceSquared = 10 * 10
assert_true(autoUnicom.handleYalEvent("departure.flightplan_active", {
    departure_icao = "ENAT",
    arrival_icao = "ENSB"
}, 1), "YAL preflight event accepted")
autoUnicom.tick(true, 1)
assert_equal(#pushbackSearchAirports, 0, "Zibo nearest gate bypasses preflight apt.dat fallback")
assert_equal(eventAdapterWrites[1].value,
    "ENAT Traffic, B738 at gate 4, preparing for departure to ENSB",
    "YAL preflight event uses Zibo nearest gate")

eventAdapterWrites = {}
pushbackSearchAirports = {}
eventAdapterValues.autogate_gpu = 0
eventAdapterValues.autogate_nearest = 5 / 1852
eventAdapterValues.autogate_nearest_name = "42"
pushbackRamp = { ramp_type = "misc", name = "Apron 42" }
pushbackDistanceSquared = 25
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_equal(#pushbackSearchAirports, 0, "activation does not infer a pushback event")
assert_true(autoUnicom.handleYalEvent("departure.start_push", nil, 1), "YAL pushback event accepted")
autoUnicom.tick(true, 1)
assert_equal(#pushbackSearchAirports, 0, "Zibo nearest stand bypasses pushback apt.dat fallback")
assert_equal(eventAdapterWrites[1].value, "ESSA Traffic, B738, pushing back from stand 42",
    "YAL pushback event uses Zibo nearest stand")

eventAdapterWrites = {}
pushbackSearchAirports = {}
eventAdapterValues.nearesticao = ""
eventAdapterValues.request_seq = 40
eventAdapterValues.result_seq = 40
eventAdapterValues.result_code = 21
eventAdapterValues.autogate_gpu = 1
eventAdapterValues.autogate_nearest = 81 / 1852
eventAdapterValues.autogate_nearest_name = "A12"
pushbackRamp = { ramp_type = "gate", name = "Gate A12" }
pushbackDistanceSquared = 81 * 81
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("departure.start_push", nil, 1), "generic pushback event accepted")
autoUnicom.tick(true, 1)
assert_equal(pushbackSearchAirports[1], "ENAT", "departure airport is pushback search fallback")
assert_equal(eventAdapterWrites[1].value, phraseCases[8][3],
    "pushback ramp beyond 80 meters keeps generic phrase")

eventAdapterWrites = {}
eventAdapterValues.request_seq = 50
eventAdapterValues.result_seq = 50
eventAdapterValues.result_code = 21
eventAdapterValues.transport_state = 4
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("arrival.approach", nil, 1), "YAL approach event queues")
assert_equal(autoUnicom.getDebugState().queue_depth, 1, "YAL event is queued while transport is busy")
assert_true(autoUnicom.handleYalEvent("arrival.go_around", nil, 2), "YAL go-around control event accepted")
assert_equal(autoUnicom.getDebugState().queue_depth, 0, "go-around removes stale queued arrival event")

eventAdapterValues.transport_state = 5
assert_true(autoUnicom.handleYalEvent("departure.climb_level_10000", {
    altitude_ft = 10000,
    pressure_altitude_ft = 10000,
    climb_next_waypoint = "BIRCO"
}, 3), "YAL altitude event accepted")
autoUnicom.tick(true, 3)
assert_equal(eventAdapterWrites[1].value, phraseCases[12][3], "YAL altitude payload freezes FL100")

eventAdapterWrites = {}
eventAdapterValues.request_seq = 55
eventAdapterValues.result_seq = 55
eventAdapterValues.result_code = 21
eventAdapterValues.desicao = "****"
eventAdapterValues.desrwy = "----"
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("arrival.runway_vacated", {
    arrival_icao = "PAHO",
    arrival_runway = "04"
}, 1), "YAL runway vacated event accepts latched arrival context")
autoUnicom.tick(true, 1)
assert_equal(eventAdapterWrites[1].value, "PAHO Traffic, runway 04 vacated, taxiing to gate",
    "runway vacated payload survives cleared FMC destination")

eventAdapterWrites = {}
eventAdapterValues.request_seq = 57
eventAdapterValues.result_seq = 57
eventAdapterValues.result_code = 21
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("arrival.backtrack", {
    arrival_icao = "PAHO",
    arrival_runway = "04"
}, 1), "YAL arrival backtrack event accepts latched arrival context")
autoUnicom.tick(true, 1)
assert_equal(eventAdapterWrites[1].value, "PAHO Traffic, B738 backtracking runway 04",
    "arrival backtrack payload survives cleared FMC destination")
eventAdapterValues.desicao = "ENSB"
eventAdapterValues.desrwy = "27"

eventAdapterWrites = {}
pushbackSearchAirports = {}
eventAdapterValues.nearesticao = "PAHO"
eventAdapterValues.request_seq = 58
eventAdapterValues.result_seq = 58
eventAdapterValues.result_code = 21
eventAdapterValues.autogate_gpu = 1
eventAdapterValues.autogate_nearest = 10 / 1852
eventAdapterValues.autogate_nearest_name = "B7"
pushbackRamp = { ramp_type = "gate", name = "Gate B7" }
pushbackDistanceSquared = 10 * 10
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("arrival.parking_position", {
    arrival_icao = "PAHO",
    arrival_runway = "04"
}, 1), "YAL arrival parking event accepts nearest ramp")
autoUnicom.tick(true, 1)
assert_equal(#pushbackSearchAirports, 0, "Zibo nearest gate bypasses arrival apt.dat fallback")
assert_equal(eventAdapterWrites[1].value, "PAHO Traffic, B738 parked at gate B7",
    "arrival parking uses Zibo nearest gate")

eventAdapterWrites = {}
eventAdapterValues.request_seq = 60
eventAdapterValues.result_seq = 60
eventAdapterValues.result_code = 21
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("enroute.hold_enter", {
    hold_source = "api",
    hold_waypoint = "BIRCO",
    hold_path_type = "HM"
}, 1), "YAL hold entry accepted")
assert_true(autoUnicom.handleYalEvent("enroute.hold_exit", {
    hold_source = "api",
    hold_waypoint = "BIRCO",
    hold_path_type = "HM"
}, 2), "YAL hold exit accepted")
assert_equal(autoUnicom.getDebugState().queue_depth, 1, "hold exit replaces queued hold entry")
autoUnicom.tick(true, 2)
assert_equal(eventAdapterWrites[1].value, phraseCases[17][3], "YAL hold exit text is committed")

print("auto_unicom tests passed")
