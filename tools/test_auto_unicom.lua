package.path = "data/modules/Custom Module/?.lua;" .. package.path

local core = require("auto_unicom_core")

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
    on_runway_profile = true,
    final_gate = false,
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
    core.buildMessage("arrival.on_final", copy(base, { approach_procedure_type = "LOC" })),
    "ENSB Traffic, B738 established on Localizer runway 27",
    "LOC final phrase"
)

local emitted = {}
local engine = core.newEventEngine({
    emit = function(event)
        table.insert(emitted, event)
        return true
    end
})

engine:update(base, 0)
engine:update(base, 3)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 1,
    radio_altitude_ft = 20,
    altitude_ft = 100,
    pressure_altitude_ft = 100,
    vertical_speed_fpm = 1200,
    ground_speed_kts = 150
}), 4)
assert_equal(#emitted, 0, "airborne debounce before three seconds")
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 1,
    radio_altitude_ft = 200,
    altitude_ft = 300,
    pressure_altitude_ft = 300,
    vertical_speed_fpm = 1200,
    ground_speed_kts = 170
}), 7)
assert_equal(#emitted, 1, "airborne emitted after debounce")
assert_equal(emitted[1].id, "departure.airborne", "airborne debounce event")
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 1,
    radio_altitude_ft = 1500,
    altitude_ft = 1800,
    pressure_altitude_ft = 1800,
    vertical_speed_fpm = 1200,
    ground_speed_kts = 220
}), 12)
assert_equal(#emitted, 2, "climb emitted once after stable phase")
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 2,
    radio_altitude_ft = 30000,
    altitude_ft = 37000,
    pressure_altitude_ft = 37000,
    vertical_speed_fpm = 0,
    tod_distance_nm = 10
}), 20)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 2,
    radio_altitude_ft = 30000,
    altitude_ft = 37000,
    pressure_altitude_ft = 37000,
    vertical_speed_fpm = 0,
    tod_distance_nm = 2
}), 21)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 5,
    radio_altitude_ft = 29500,
    altitude_ft = 36500,
    pressure_altitude_ft = 36500,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), 22)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 5,
    radio_altitude_ft = 28500,
    altitude_ft = 35500,
    pressure_altitude_ft = 35500,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), 30)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 5,
    radio_altitude_ft = 28000,
    altitude_ft = 35000,
    pressure_altitude_ft = 35000,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), 31)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 6,
    radio_altitude_ft = 8000,
    altitude_ft = 9000,
    pressure_altitude_ft = 9000,
    vertical_speed_fpm = -800,
    tod_distance_nm = 0
}), 40)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 6,
    radio_altitude_ft = 5000,
    altitude_ft = 6000,
    pressure_altitude_ft = 6000,
    vertical_speed_fpm = -800,
    tod_distance_nm = 0
}), 48)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    final_gate = true,
    fms_phase = 6,
    radio_altitude_ft = 1800,
    altitude_ft = 2000,
    pressure_altitude_ft = 2000,
    vertical_speed_fpm = -600,
    tod_distance_nm = 0
}), 50)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    final_gate = true,
    fms_phase = 6,
    radio_altitude_ft = 1000,
    altitude_ft = 1200,
    pressure_altitude_ft = 1200,
    vertical_speed_fpm = -600,
    tod_distance_nm = 0
}), 55)
engine:update(copy(base, {
    on_ground = true,
    on_runway_profile = true,
    fms_phase = 6,
    radio_altitude_ft = 0,
    altitude_ft = 400,
    pressure_altitude_ft = 400,
    vertical_speed_fpm = 0,
    ground_speed_kts = 100,
    tod_distance_nm = 0
}), 60)
engine:update(copy(base, {
    on_ground = true,
    on_runway_profile = false,
    fms_phase = 6,
    radio_altitude_ft = 0,
    altitude_ft = 400,
    pressure_altitude_ft = 400,
    vertical_speed_fpm = 0,
    ground_speed_kts = 20,
    tod_distance_nm = 0
}), 61)
engine:update(copy(base, {
    on_ground = true,
    on_runway_profile = false,
    fms_phase = 6,
    radio_altitude_ft = 0,
    altitude_ft = 400,
    pressure_altitude_ft = 400,
    vertical_speed_fpm = 0,
    ground_speed_kts = 20,
    tod_distance_nm = 0
}), 66)

local expectedEvents = {
    "departure.airborne",
    "departure.on_climb",
    "arrival.top_of_descent",
    "arrival.approach",
    "arrival.on_final",
    "arrival.runway_vacated"
}
assert_equal(#emitted, #expectedEvents, "normal event count")
for index, id in ipairs(expectedEvents) do
    assert_equal(emitted[index].id, id, "normal event order " .. tostring(index))
end

local fallbackEvents = {}
local fallbackEngine = core.newEventEngine({
    emit = function(event)
        table.insert(fallbackEvents, event)
        return true
    end
})
local airborneCruise = copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 2,
    altitude_ft = 37000,
    pressure_altitude_ft = 37000,
    vertical_speed_fpm = 0,
    tod_distance_nm = 40
})
fallbackEngine:update(airborneCruise, 0)
fallbackEngine:update(copy(airborneCruise, {
    fms_phase = 4,
    altitude_ft = 36000,
    pressure_altitude_ft = 36000,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 30
}), 1)
fallbackEngine:update(copy(airborneCruise, {
    fms_phase = 4,
    altitude_ft = 35000,
    pressure_altitude_ft = 35000,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 25
}), 9)
assert_equal(#fallbackEvents, 1, "fallback event count")
assert_equal(fallbackEvents[1].id, "arrival.on_descent", "fallback event id")
fallbackEngine:update(copy(airborneCruise, {
    fms_phase = 5,
    altitude_ft = 34000,
    pressure_altitude_ft = 34000,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), 10)
fallbackEngine:update(copy(airborneCruise, {
    fms_phase = 5,
    altitude_ft = 33000,
    pressure_altitude_ft = 33000,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), 18)
assert_equal(#fallbackEvents, 1, "TOD does not follow on-descent fallback")

local reloadEvents = {}
local reloadEngine = core.newEventEngine({ emit = function(event) table.insert(reloadEvents, event) return true end })
local loadedOnFinal = copy(base, {
    on_ground = false,
    on_runway_profile = false,
    final_gate = true,
    fms_phase = 6,
    altitude_ft = 2000,
    pressure_altitude_ft = 2000,
    vertical_speed_fpm = -500,
    tod_distance_nm = 0
})
reloadEngine:update(loadedOnFinal, 0)
reloadEngine:update(loadedOnFinal, 20)
assert_equal(#reloadEvents, 0, "reload baseline emits nothing")

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
    id = "arrival.approach",
    text = phraseCases[5][3],
    expires_at = 100
}), "enqueue approach supersession")
assert_equal(#supersessionMailbox.queue, 1, "supersession keeps only current event")
assert_equal(supersessionMailbox.queue[1].id, "arrival.approach", "approach supersedes queued TOD")
assert_equal(supersessionLogs[1].kind, "superseded", "supersession logged")

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

print("auto_unicom tests passed")
