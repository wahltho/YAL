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

local function test_spell_nato(value)
    local nato = {
        A = "Alpha", B = "Bravo", C = "Charlie", D = "Delta", E = "Echo", F = "Foxtrot",
        G = "Golf", H = "Hotel", I = "India", J = "Juliet", K = "Kilo", L = "Lima",
        M = "Mike", N = "November", O = "Oscar", P = "Papa", Q = "Quebec", R = "Romeo",
        S = "Sierra", T = "Tango", U = "Uniform", V = "Victor", W = "Whiskey", X = "X-ray",
        Y = "Yankee", Z = "Zulu"
    }
    local parts = {}
    local text = tostring(value or ""):upper()
    for index = 1, #text do
        local char = text:sub(index, index)
        if nato[char] then
            parts[#parts + 1] = nato[char]
        elseif char:match("%d") then
            parts[#parts + 1] = char
        end
    end
    return table.concat(parts, " ")
end

local function copy(source, overrides)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

assert_true(core.shouldSuppressProgressLevel(40000, 41000),
    "FL400 is suppressed near FL410 phase boundary")
assert_true(core.shouldSuppressProgressLevel(30000, 34000),
    "progress level below 5000 feet from boundary is suppressed")
assert_equal(core.shouldSuppressProgressLevel(30000, 35000), false,
    "progress level exactly 5000 feet from boundary is retained")
assert_equal(core.shouldSuppressProgressLevel(30000, 29000), false,
    "progress level above phase boundary is retained")
assert_equal(core.shouldSuppressProgressLevel(30000, nil), false,
    "missing phase boundary retains progress level")
assert_equal(core.resolveClimbTargetAltitude(5000, 10000, 37000), 10000,
    "MCP restriction is the next effective climb target")
assert_equal(core.resolveClimbTargetAltitude(5000, 40000, 37000), 37000,
    "FMC cruise caps an MCP selection above planned cruise")
assert_equal(core.resolveClimbTargetAltitude(5000, nil, 37000), 37000,
    "missing MCP falls back to FMC cruise")
assert_equal(core.resolveClimbTargetAltitude(5000, 10000, nil), 10000,
    "missing FMC cruise falls back to MCP")
assert_equal(core.resolveClimbTargetAltitude(12200, 12000, 37000), 12000,
    "small level-capture overshoot retains the selected target")
assert_equal(core.resolveClimbTargetAltitude(12300, 12000, 37000), nil,
    "MCP materially below current climb altitude is not announced as a target")
assert_true(core.isClimbTargetReached(11800, 12000),
    "climb target is reaching at the tolerance boundary")
assert_equal(core.isClimbTargetReached(11799, 12000), false,
    "climb target remains passing below the tolerance boundary")
assert_equal(core.isCruiseReportDue(1000, 1599), false,
    "cruise report remains gated before 600 seconds")
assert_true(core.isCruiseReportDue(1000, 1600),
    "cruise report is due exactly at 600 seconds")
assert_true(core.isCruiseReportDue(nil, 1600),
    "missing prior cruise report is immediately due")
assert_equal(core.isCruiseReportDue(1600, 1600), false,
    "cruise reload baseline starts a fresh report interval")
assert_true(core.isCruiseLevelStable(300),
    "cruise entry remains level at the vertical-speed boundary")
assert_equal(core.isCruiseLevelStable(301), false,
    "cruise entry reports reaching while still climbing")
assert_equal(core.isCruiseLevelStable(-301), false,
    "cruise entry reports reaching while still descending")
assert_true(core.isCruiseLevelStable(nil),
    "missing vertical speed preserves the previous cruise-entry wording")
assert_true(core.isVectorLegIdentifier("(VECTO\0"),
    "truncated Zibo vector identifier is recognized before cleaning")
assert_true(core.isVectorLegIdentifier("(VECTOR)"),
    "full Zibo vector identifier is recognized")
assert_equal(core.isVectorLegIdentifier("VECTO"), false,
    "genuine VECTO waypoint is not treated as a vector leg")
assert_equal(core.normalizeVectorHeading(239.6), 240,
    "vector heading is rounded to the nearest degree")
assert_equal(core.normalizeVectorHeading(0), 360,
    "northbound vector heading uses aviation heading 360")
assert_equal(core.normalizeVectorHeading(361), nil,
    "invalid vector heading is rejected")
assert_equal(core.vectorHeadingForIndex({ 0, 196.654266, 194, 210 }, 4), 210,
    "one-based active leg index selects KSNA HAWWC3 vector instead of preceding runway leg")
assert_equal(core.vectorHeadingForIndex({ 0, 196.654266, 194, 210 }, 0), nil,
    "invalid active leg index does not select a vector heading")
local vectorPassed, vectorWaypoint, vectorActive = core.advanceCruiseWaypointState(
    "BIRCO", false, nil, true
)
assert_equal(vectorPassed, nil, "entering vector does not report previous waypoint as passed")
assert_equal(vectorWaypoint, nil, "entering vector clears tracked cruise waypoint")
assert_true(vectorActive, "entering vector latches vector state")
local exitPassed, exitWaypoint, exitVectorActive = core.advanceCruiseWaypointState(
    vectorWaypoint, vectorActive, "NESDI", false
)
assert_equal(exitPassed, nil, "leaving vector does not report stale waypoint as passed")
assert_equal(exitWaypoint, "NESDI", "leaving vector tracks the new waypoint")
assert_equal(exitVectorActive, false, "leaving vector clears vector state")
local normalPassed = core.advanceCruiseWaypointState("BIRCO", false, "NESDI", false)
assert_equal(normalPassed, "BIRCO", "normal cruise waypoint sequencing remains unchanged")
assert_equal(core.isHoldLevelStable(5177, -321, 5100), false,
    "hold is not maintaining while still descending")
assert_true(core.isHoldLevelStable(5105, -50, 5100),
    "hold is maintaining near the valid target")
assert_equal(core.isHoldLevelStable(5250, 0, 5100), false,
    "hold is not maintaining outside target tolerance")
assert_equal(core.isHoldLevelStable(5100, 200, 5100), false,
    "hold is not maintaining with excessive vertical speed")
assert_equal(core.isHoldLevelStable(5177, -321, nil), false,
    "targetless hold is not maintaining while still descending")
assert_true(core.isHoldLevelStable(5177, -50, nil),
    "targetless hold can use live altitude after vertical stabilization")
assert_equal(core.isHoldLevelStable(5177, -120, nil), false,
    "targetless hold cannot be descending and maintaining at the same time")
assert_true(core.isHoldDescending(5300, -321, 5100),
    "hold descent is detected above a valid lower target")
assert_equal(core.isHoldDescending(5300, -50, 5100), false,
    "minor vertical motion is not treated as hold descent")
assert_equal(core.isHoldDescending(5177, -321, nil), true,
    "targetless established hold can still report active descent")
assert_equal(core.isHoldDescending(5177, -321, 5100), false,
    "hold descent is not reported at or below the target tolerance")

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
    departure_station_name = "ALTA",
    departure_station_icao = "ENAT",
    departure_runway = "09",
    arrival_icao = "ENSB",
    arrival_station_name = "SVALBARD",
    arrival_station_icao = "ENSB",
    arrival_runway = "27",
    effective_callsign = "DLH3210",
    aircraft_type = "B738",
    sid = "ATKUP1A",
    climb_next_waypoint = "BIRCO",
    star = "NELSA3M",
    approach_id = "R27-W",
    approach_procedure_type = "RNAV",
    approach_suffix = "W"
}

local vectorClimbSnapshot = copy(base, {
    altitude_ft = 1800,
    pressure_altitude_ft = 1800,
    climb_next_waypoint = "VECTO",
    navigation_vector_active = true,
    navigation_vector_heading_deg = 240
})
local vectorClimbText = core.buildMessage("departure.on_climb", vectorClimbSnapshot)
assert_equal(
    vectorClimbText,
    "Lufthansa 3210 climbing out of ALTA on ATKUP1A departure, passing 1800ft for FL370, flying heading 240",
    "active vector renders its leg heading instead of a pseudo-waypoint"
)
assert_equal(
    core.buildVoiceMessage("departure.on_climb", vectorClimbSnapshot, test_spell_nato, vectorClimbText),
    "Lufthansa tree two one zero climbing out of Alta on Atkup one Alpha departure, passing one eight zero zero feet for flight level tree seven zero, flying heading two fower zero",
    "active vector heading is spoken digit by digit"
)
assert_equal(
    core.buildMessage("departure.on_climb", copy(base, {
        altitude_ft = 1800,
        pressure_altitude_ft = 1800,
        climb_next_waypoint = "VECTO",
        navigation_vector_active = false
    })),
    "Lufthansa 3210 climbing out of ALTA on ATKUP1A departure, passing 1800ft for FL370, VECTO next",
    "genuine VECTO waypoint remains a normal waypoint"
)
assert_equal(
    core.buildMessage("enroute.in_cruise", copy(base, {
        cruise_periodic = true,
        cruise_next_waypoint = "VECTO",
        navigation_vector_active = true,
        navigation_vector_heading_deg = nil,
        altitude_ft = 40000,
        pressure_altitude_ft = 40000
    })),
    "Lufthansa 3210 maintaining FL400",
    "vector without a valid leg heading is omitted instead of guessed"
)

assert_equal(
    core.buildMessage("enroute.holding", copy(base, {
        hold_waypoint = "BIRCO",
        altitude_ft = 37000,
        pressure_altitude_ft = 37000
    })),
    "Lufthansa 3210 maintaining FL370 whilst holding over BIRCO",
    "hold without target uses live altitude"
)

local descendingHoldEntry = copy(base, {
    hold_waypoint = "BIRCO",
    hold_descending = true,
    hold_target_altitude_ft = 5100,
    altitude_ft = 12000,
    pressure_altitude_ft = 12000
})
local descendingHoldEntryText = core.buildMessage("enroute.hold_enter", descendingHoldEntry)
assert_equal(
    descendingHoldEntryText,
    "Lufthansa 3210 entering a hold over BIRCO on descent passing FL120 for 5100ft",
    "hold entry includes an already active descent"
)
assert_equal(
    core.buildVoiceMessage("enroute.hold_enter", descendingHoldEntry, test_spell_nato, descendingHoldEntryText),
    "Lufthansa tree two one zero entering a hold over Birco on descent passing flight level one two zero for fife one zero zero feet",
    "descending hold entry has paired voice text"
)

local function test_refdata_airport(icao)
    local names = { ENAT = "ALTA", ENSB = "SVALBARD" }
    local name = names[tostring(icao or ""):upper()]
    if not name then return { station_name = "", station_name_valid = false } end
    return { station_name = name, station_name_valid = true }
end

local function test_refdata_nav(ident)
    local names = {
        DCS = "DEAN CROSS DME",
        LIH = "LIHUE VOR/DME",
        WAL = "WALLASEY VOR/DME"
    }
    local name = names[tostring(ident or ""):upper()]
    return name and { name = name } or nil
end

local phraseCases = {
    {
        "departure.airborne",
        base,
        "ALTA Traffic, Lufthansa 3210 airborne runway 09, passing 300ft"
    },
    {
        "departure.on_climb",
        copy(base, { altitude_ft = 1800, pressure_altitude_ft = 1800 }),
        "Lufthansa 3210 climbing out of ALTA on ATKUP1A departure, passing 1800ft for FL370, BIRCO next"
    },
    {
        "arrival.top_of_descent",
        copy(base, { altitude_ft = 37000, pressure_altitude_ft = 37000 }),
        "Lufthansa 3210 inbound SVALBARD, NELSA3M arrival, at TOD leaving FL370, expecting runway 27"
    },
    {
        "arrival.on_descent",
        copy(base, { altitude_ft = 18000, pressure_altitude_ft = 18000 }),
        "Lufthansa 3210 inbound SVALBARD, NELSA3M arrival, RNAV W approach runway 27, descent started from FL370"
    },
    {
        "arrival.approach",
        copy(base, { altitude_ft = 6000, pressure_altitude_ft = 6000 }),
        "SVALBARD Traffic, Lufthansa 3210 NELSA3M arrival for RNAV W approach runway 27, on descent passing 6000ft"
    },
    {
        "arrival.on_final",
        copy(base, { approach_procedure_type = "ILS" }),
        "SVALBARD Traffic, Lufthansa 3210 established on ILS runway 27"
    },
    {
        "arrival.runway_vacated",
        base,
        "SVALBARD Traffic, Lufthansa 3210 runway 27 vacated, taxiing to gate"
    },
    {
        "departure.start_push",
        base,
        "ALTA Traffic, Lufthansa 3210 pushing back"
    },
    {
        "departure.taxi_runway",
        base,
        "ALTA Traffic, Lufthansa 3210 taxiing to holding point runway 09"
    },
    {
        "departure.lineup_takeoff",
        base,
        "ALTA Traffic, Lufthansa 3210 taking off runway 09"
    },
    {
        "arrival.descent_level_30000",
        copy(base, { altitude_ft = 30000, pressure_altitude_ft = 30000 }),
        "Lufthansa 3210 inbound SVALBARD, NELSA3M arrival, RNAV W approach runway 27, on descent passing FL300"
    },
    {
        "departure.climb_level_10000",
        copy(base, { altitude_ft = 10000, pressure_altitude_ft = 10000 }),
        "Lufthansa 3210 climbing out of ALTA, passing FL100 for FL370, BIRCO next"
    },
    {
        "departure.climb_level_20000",
        copy(base, { altitude_ft = 20000, pressure_altitude_ft = 20000 }),
        "Lufthansa 3210 climbing out of ALTA, passing FL200 for FL370, BIRCO next"
    },
    {
        "departure.climb_level_30000",
        copy(base, { altitude_ft = 30000, pressure_altitude_ft = 30000 }),
        "Lufthansa 3210 climbing out of ALTA, passing FL300 for FL370, BIRCO next"
    },
    {
        "departure.climb_level_40000",
        copy(base, { altitude_ft = 40000, pressure_altitude_ft = 40000, planned_altitude_ft = 41000 }),
        "Lufthansa 3210 climbing out of ALTA, passing FL400 for FL410, BIRCO next"
    },
    {
        "enroute.hold_enter",
        copy(base, { hold_waypoint = "BIRCO", hold_path_type = "HM" }),
        "Lufthansa 3210 entering a hold over BIRCO"
    },
    {
        "enroute.hold_exit",
        copy(base, { hold_waypoint = "BIRCO", hold_path_type = "HM" }),
        "Lufthansa 3210 exiting hold over BIRCO"
    },
    {
        "departure.hold_short",
        base,
        "ALTA Traffic, Lufthansa 3210 holding short runway 09"
    },
    {
        "departure.hold_short",
        copy(base, { departure_intersection = "Intersection A" }),
        "ALTA Traffic, Lufthansa 3210 holding short runway 09 at taxiway A"
    },
    {
        "departure.backtrack",
        copy(base, { departure_intersection = "A" }),
        "ALTA Traffic, Lufthansa 3210 backtracking runway 09"
    },
    {
        "departure.intersection",
        copy(base, { departure_intersection = "A" }),
        "ALTA Traffic, Lufthansa 3210 lining up runway 09 at taxiway A"
    },
    {
        "arrival.short_final",
        base,
        "SVALBARD Traffic, Lufthansa 3210 short final runway 27"
    },
    {
        "enroute.in_cruise",
        copy(base, { cruise_waypoint = "BIRCO", altitude_ft = 37000, pressure_altitude_ft = 37000 }),
        "Lufthansa 3210 passing BIRCO, maintaining FL370"
    },
    {
        "enroute.holding",
        copy(base, {
            hold_waypoint = "BIRCO",
            hold_target_altitude_ft = 5100,
            altitude_ft = 5177,
            pressure_altitude_ft = 5173
        }),
        "Lufthansa 3210 maintaining 5100ft whilst holding over BIRCO"
    },
    {
        "enroute.hold_descending",
        copy(base, {
            hold_waypoint = "BIRCO",
            hold_target_altitude_ft = 25000,
            altitude_ft = 37000,
            pressure_altitude_ft = 37000
        }),
        "Lufthansa 3210 in a hold over BIRCO on descent passing FL370 for FL250"
    },
    {
        "arrival.backtrack",
        base,
        "SVALBARD Traffic, Lufthansa 3210 backtracking runway 27"
    },
    {
        "arrival.parking_position",
        copy(base, {
            arrival_parking_found = true,
            arrival_parking_type = "gate",
            arrival_parking_name = "Gate B7"
        }),
        "SVALBARD Traffic, Lufthansa 3210 parked at gate B7"
    },
    {
        "departure.flightplan_active",
        copy(base, {
            preflight_parking_found = true,
            preflight_parking_type = "gate",
            preflight_parking_name = "Gate 4"
        }),
        "ALTA Traffic, Lufthansa 3210 at gate 4, preparing for departure to SVALBARD"
    },
    {
        "departure.runway_crossing",
        copy(base, { crossing_runway = "08", crossing_taxiway = "Z" }),
        "ALTA Traffic, Lufthansa 3210 crossing runway 08 at taxiway Z"
    },
    {
        "arrival.runway_crossing",
        copy(base, { crossing_runway = "16" }),
        "SVALBARD Traffic, Lufthansa 3210 crossing runway 16"
    },
    {
        "departure.lining_up",
        base,
        "ALTA Traffic, Lufthansa 3210 lining up runway 09"
    }
}

for _, case in ipairs(phraseCases) do
    local text = core.buildMessage(case[1], case[2])
    assert_equal(text, case[3], "phrase " .. case[1])
    assert_true(not text:lower():find(" the ", 1, true), "phrase has no 'the' " .. case[1])

    local scope = core.messageScope(case[1])
    assert_true(scope ~= nil, "message contract exists " .. case[1])
    local voice = core.buildVoiceMessage(case[1], case[2], test_spell_nato, text)
    assert_true(voice ~= nil, "paired voice message exists " .. case[1])
    if scope == "local" then
        assert_true(text:find(" Traffic, ", 1, true) ~= nil,
            "local message addresses Traffic " .. case[1])
        assert_true(voice:find(" Traffic, ", 1, true) ~= nil,
            "local voice message keeps Traffic address " .. case[1])
    elseif scope == "departure_enroute" then
        assert_true(text:find("climbing out of ALTA", 1, true) ~= nil,
            "departure enroute message retains departure station " .. case[1])
        assert_true(voice:find("climbing out of Alta", 1, true) ~= nil,
            "departure enroute voice retains departure station " .. case[1])
        assert_true(text:find(" Traffic, ", 1, true) == nil,
            "departure enroute message omits local Traffic address " .. case[1])
    elseif scope == "arrival_enroute" then
        assert_true(text:find("inbound SVALBARD", 1, true) ~= nil,
            "arrival enroute message retains destination station " .. case[1])
        assert_true(voice:find("inbound Svalbard", 1, true) ~= nil,
            "arrival enroute voice retains destination station " .. case[1])
        assert_true(text:find(" Traffic, ", 1, true) == nil,
            "arrival enroute message omits local Traffic address " .. case[1])
    elseif scope == "enroute" then
        assert_true(text:find(" Traffic, ", 1, true) == nil,
            "global enroute message omits local Traffic address " .. case[1])
    else
        fail("unknown message-contract scope " .. tostring(scope) .. " for " .. case[1])
    end
end

assert_equal(core.messageScope("departure.climb_level_20000"), "departure_enroute",
    "dynamic climb event uses departure-enroute contract")
assert_equal(core.messageScope("arrival.descent_level_20000"), "arrival_enroute",
    "dynamic descent event uses arrival-enroute contract")
assert_equal(core.messageScope("unknown.event"), nil, "unknown event has no message contract")

local pacdDescentSnapshot = copy(base, {
    arrival_icao = "PACD",
    arrival_station_name = "",
    arrival_station_icao = "PACD",
    arrival_runway = "15",
    ofp_valid = true,
    ofp_origin_icao = "PHLI",
    ofp_origin_name = "LIHUE",
    ofp_destination_icao = "PACD",
    ofp_destination_name = "COLD BAY",
    star = "",
    approach_id = "I15",
    approach_procedure_type = "ILS",
    approach_suffix = "",
    altitude_ft = 39976,
    pressure_altitude_ft = 39966,
    planned_altitude_ft = 40000
})
local pacdDescentText = core.buildMessage("arrival.on_descent", pacdDescentSnapshot)
assert_equal(
    pacdDescentText,
    "Lufthansa 3210 inbound COLD BAY, ILS approach runway 15, descent started from FL400",
    "descent start retains selected PACD destination label"
)
assert_equal(
    core.buildVoiceMessage("arrival.on_descent", pacdDescentSnapshot, test_spell_nato, pacdDescentText),
    "Lufthansa tree two one zero inbound Cold Bay, I L S approach runway one fife, descent started from flight level fower zero zero",
    "descent voice retains same PACD destination semantics"
)

local normalFlightSequence = {
    { "departure.flightplan_active", copy(base, {
        preflight_parking_found = true,
        preflight_parking_type = "gate",
        preflight_parking_name = "Gate 4"
    }), "ALTA Traffic" },
    { "departure.start_push", base, "ALTA Traffic" },
    { "departure.taxi_runway", base, "ALTA Traffic" },
    { "departure.hold_short", base, "ALTA Traffic" },
    { "departure.lining_up", base, "ALTA Traffic" },
    { "departure.lineup_takeoff", base, "ALTA Traffic" },
    { "departure.airborne", base, "ALTA Traffic" },
    { "departure.on_climb", copy(base, { altitude_ft = 1800, pressure_altitude_ft = 1800 }), "climbing out of ALTA" },
    { "departure.climb_level_10000", copy(base, { altitude_ft = 10000, pressure_altitude_ft = 10000 }), "climbing out of ALTA" },
    { "enroute.in_cruise", copy(base, {
        cruise_entry = true,
        cruise_next_waypoint = "BIRCO",
        altitude_ft = 37000,
        pressure_altitude_ft = 37000
    }), "level at FL370" },
    { "arrival.top_of_descent", copy(base, { altitude_ft = 37000, pressure_altitude_ft = 37000 }), "inbound SVALBARD" },
    { "arrival.on_descent", copy(base, { altitude_ft = 36000, pressure_altitude_ft = 36000 }), "inbound SVALBARD" },
    { "arrival.descent_level_30000", copy(base, { altitude_ft = 30000, pressure_altitude_ft = 30000 }), "inbound SVALBARD" },
    { "arrival.approach", copy(base, { altitude_ft = 6000, pressure_altitude_ft = 6000 }), "SVALBARD Traffic" },
    { "arrival.on_final", copy(base, { approach_procedure_type = "ILS" }), "SVALBARD Traffic" },
    { "arrival.short_final", base, "SVALBARD Traffic" },
    { "arrival.runway_vacated", base, "SVALBARD Traffic" },
    { "arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "Gate B7"
    }), "SVALBARD Traffic" }
}

for sequenceIndex, stage in ipairs(normalFlightSequence) do
    local message = core.buildMessage(stage[1], stage[2])
    assert_true(message ~= nil, "normal-flight stage renders " .. sequenceIndex .. " " .. stage[1])
    assert_true(message:find(stage[3], 1, true) ~= nil,
        "normal-flight stage keeps semantic context " .. sequenceIndex .. " " .. stage[1])
    local voice = core.buildVoiceMessage(stage[1], stage[2], test_spell_nato, message)
    assert_true(voice ~= nil and voice:find("Lufthansa", 1, true) ~= nil,
        "normal-flight stage renders paired voice " .. sequenceIndex .. " " .. stage[1])
end

local voiceCases = {
    {
        "departure.airborne",
        base,
        "Alta Traffic, Lufthansa tree two one zero airborne runway zero niner, passing tree zero zero feet"
    },
    {
        "departure.on_climb",
        copy(base, { altitude_ft = 1800, pressure_altitude_ft = 1800 }),
        "Lufthansa tree two one zero climbing out of Alta on Atkup one Alpha departure, passing one eight zero zero feet for flight level tree seven zero, Birco next"
    },
    {
        "enroute.in_cruise",
        copy(base, {
            cruise_periodic = true,
            cruise_next_waypoint = "RIGVU",
            altitude_ft = 40000,
            pressure_altitude_ft = 40000
        }),
        "Lufthansa tree two one zero maintaining flight level fower zero zero, Rigvu next"
    },
    {
        "arrival.approach",
        copy(base, { altitude_ft = 6000, pressure_altitude_ft = 6000 }),
        "Svalbard Traffic, Lufthansa tree two one zero Nelsa tree Mike arrival for R NAV Whiskey approach runway two seven, on descent passing six zero zero zero feet"
    },
    {
        "departure.runway_crossing",
        copy(base, { crossing_runway = "08", crossing_taxiway = "Z" }),
        "Alta Traffic, Lufthansa tree two one zero crossing runway zero eight at taxiway Zulu"
    },
    {
        "arrival.parking_position",
        copy(base, {
            arrival_parking_found = true,
            arrival_parking_type = "gate",
            arrival_parking_name = "Gate B7"
        }),
        "Svalbard Traffic, Lufthansa tree two one zero parked at gate Bravo seven"
    },
    {
        "arrival.on_descent",
        copy(base, { altitude_ft = 18000, pressure_altitude_ft = 18000 }),
        "Lufthansa tree two one zero inbound Svalbard, Nelsa tree Mike arrival, R NAV Whiskey approach runway two seven, descent started from flight level tree seven zero"
    }
}

for _, case in ipairs(voiceCases) do
    local visibleText = core.buildMessage(case[1], case[2])
    local voiceText = core.buildVoiceMessage(case[1], case[2], test_spell_nato, visibleText)
    assert_equal(voiceText, case[3], "voice phrase " .. case[1])
end

local navCruiseSnapshot = copy(base, {
    cruise_entry = true,
    cruise_next_waypoint = "DCS",
    cruise_next_waypoint_nav_name = "DEAN CROSS DME"
})
local navCruiseText = core.buildMessage("enroute.in_cruise", navCruiseSnapshot)
assert_equal(
    core.buildVoiceMessage("enroute.in_cruise", navCruiseSnapshot, test_spell_nato, navCruiseText),
    "Lufthansa tree two one zero level at flight level tree seven zero, Dean Cross next",
    "resolved NAV facility name is spoken without facility suffix"
)

local navFallbackSnapshot = copy(navCruiseSnapshot, { cruise_next_waypoint_nav_name = "" })
assert_equal(
    core.buildVoiceMessage("enroute.in_cruise", navFallbackSnapshot, test_spell_nato, navCruiseText),
    "Lufthansa tree two one zero level at flight level tree seven zero, Delta Charlie Sierra next",
    "missing NAV API retains conservative NATO fallback"
)

local omittedPrivateFixSnapshot = copy(navCruiseSnapshot, {
    cruise_entry = false,
    cruise_periodic = false,
    cruise_waypoint = "",
    cruise_waypoint_omitted = true,
    cruise_next_waypoint = "",
    altitude_ft = 37000,
    pressure_altitude_ft = 37000
})
local omittedPrivateFixText = core.buildMessage("enroute.in_cruise", omittedPrivateFixSnapshot)
assert_equal(
    omittedPrivateFixText,
    "Lufthansa 3210 maintaining FL370",
    "adapter-omitted private waypoint retains a useful cruise report"
)

local coordinateSnapshot = copy(navCruiseSnapshot, {
    cruise_next_waypoint = "15N154W",
    cruise_next_waypoint_nav_name = ""
})
local coordinateText = core.buildMessage("enroute.in_cruise", coordinateSnapshot)
local coordinateVoice = core.buildVoiceMessage(
    "enroute.in_cruise",
    coordinateSnapshot,
    test_spell_nato,
    coordinateText
)
assert_equal(
    coordinateVoice,
    "Lufthansa tree two one zero level at flight level tree seven zero, one fife north one fife four west next",
    "coordinate fix uses cardinal directions and coordinate four"
)
assert_true(not coordinateVoice:find("fower", 1, true), "coordinate fix does not use aviation fower")

local navSidSnapshot = copy(base, {
    altitude_ft = 1800,
    pressure_altitude_ft = 1800,
    sid = "WAL2T",
    sid_nav_name = "WALLASEY VOR/DME"
})
local navSidText = core.buildMessage("departure.on_climb", navSidSnapshot)
assert_equal(
    core.buildVoiceMessage("departure.on_climb", navSidSnapshot, test_spell_nato, navSidText),
    "Lufthansa tree two one zero climbing out of Alta on Wallasey two Tango departure, passing one eight zero zero feet for flight level tree seven zero, Birco next",
    "SID navaid prefix uses resolved facility name"
)

local voiceEvent = core.newEvent("departure.airborne", base, 0, test_spell_nato)
assert_equal(voiceEvent.text, phraseCases[1][3], "generated event keeps exact visible text")
assert_equal(voiceEvent.voice_text, voiceCases[1][3], "generated event carries formatted v2 voice text")

local noCallsignText, noCallsignReason = core.buildMessage(
    "departure.airborne",
    copy(base, { effective_callsign = "" })
)
assert_equal(noCallsignText, nil, "missing effective callsign rejects phrase")
assert_equal(noCallsignReason, "missing_effective_callsign", "missing effective callsign reason")
assert_equal(
    core.buildMessage("departure.airborne", copy(base, { effective_callsign = "DLH3210\0STALE" })),
    phraseCases[1][3],
    "NUL-terminated effective callsign is sanitized"
)

local rawCallsignSnapshot = copy(base, { effective_callsign = "N123AB" })
local rawCallsignText = core.buildMessage("departure.airborne", rawCallsignSnapshot)
assert_equal(rawCallsignText,
    "ALTA Traffic, N123AB airborne runway 09, passing 300ft",
    "non-DLH callsign remains raw in visible text")
assert_equal(
    core.buildVoiceMessage("departure.airborne", rawCallsignSnapshot, test_spell_nato, rawCallsignText),
    "Alta Traffic, November one two tree Alpha Bravo airborne runway zero niner, passing tree zero zero feet",
    "non-DLH callsign uses NATO and aviation digits in voice")

local callsignSuffixSnapshot = copy(base, { effective_callsign = "DLH12A" })
local callsignSuffixText = core.buildMessage("departure.airborne", callsignSuffixSnapshot)
assert_equal(callsignSuffixText,
    "ALTA Traffic, Lufthansa 12A airborne runway 09, passing 300ft",
    "DLH prefix is replaced only in visible identity")
assert_equal(
    core.buildVoiceMessage("departure.airborne", callsignSuffixSnapshot, test_spell_nato, callsignSuffixText),
    "Alta Traffic, Lufthansa one two Alpha airborne runway zero niner, passing tree zero zero feet",
    "DLH suffix receives aviation voice formatting")

local stationFallbackSnapshot = copy(base, { departure_station_name = "" })
local stationFallbackText = core.buildMessage("departure.airborne", stationFallbackSnapshot)
assert_equal(stationFallbackText,
    "ENAT Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "empty station name falls back to ICAO in visible text")
assert_equal(
    core.buildVoiceMessage("departure.airborne", stationFallbackSnapshot, test_spell_nato, stationFallbackText),
    "Echo November Alpha Tango Traffic, Lufthansa tree two one zero airborne runway zero niner, passing tree zero zero feet",
    "empty station name falls back to NATO ICAO in voice")

local initialedStationSnapshot = copy(base, {
    departure_icao = "LZIB",
    departure_station_name = "STEFANIK",
    departure_station_icao = "LZIB",
    ofp_valid = true,
    ofp_origin_icao = "LZIB",
    ofp_origin_name = "M.R. STEFANIK"
})
local initialedStationText = core.buildMessage("departure.airborne", initialedStationSnapshot)
assert_equal(
    initialedStationText,
    "STEFANIK Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "compact leading airport-name initials are removed"
)
assert_equal(
    core.buildVoiceMessage("departure.airborne", initialedStationSnapshot, test_spell_nato, initialedStationText),
    "Stefanik Traffic, Lufthansa tree two one zero airborne runway zero niner, passing tree zero zero feet",
    "voice uses the same station name without leading initials"
)
assert_equal(
    core.resolveAirportLabel(copy(initialedStationSnapshot, {
        ofp_origin_name = "M. R. STEFANIK"
    }), "departure_icao", "departure_station_name"),
    "STEFANIK",
    "spaced leading airport-name initials are removed"
)
assert_equal(
    core.resolveAirportLabel(copy(initialedStationSnapshot, {
        ofp_origin_name = "ST. JOHN'S"
    }), "departure_icao", "departure_station_name"),
    "ST. JOHN'S",
    "ordinary dotted abbreviations remain unchanged"
)
local apostropheStationSnapshot = copy(base, {
    departure_icao = "CYYT",
    departure_station_name = "ST. JOHN'S",
    departure_station_icao = "CYYT"
})
local apostropheStationText = core.buildMessage("departure.airborne", apostropheStationSnapshot)
assert_equal(
    core.buildVoiceMessage("departure.airborne", apostropheStationSnapshot, test_spell_nato, apostropheStationText),
    "St. John's Traffic, Lufthansa tree two one zero airborne runway zero niner, passing tree zero zero feet",
    "possessive station-name suffix remains lowercase in voice text"
)
assert_equal(
    core.resolveAirportLabel(copy(initialedStationSnapshot, {
        ofp_origin_name = "E. MIDLANDS"
    }), "departure_icao", "departure_station_name"),
    "E. MIDLANDS",
    "a single leading initial remains unchanged"
)

local staleStationSnapshot = copy(base, { departure_icao = "ESSA" })
assert_equal(
    core.buildMessage("departure.airborne", staleStationSnapshot),
    "ESSA Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "station name is ignored when its ICAO does not match")

local ofpSnapshot = copy(base, {
    departure_icao = "EGPE",
    departure_station_name = "INVERNESS TOWER",
    departure_station_icao = "EGPE",
    arrival_icao = "ENTC",
    arrival_station_name = "TROMSO",
    arrival_station_icao = "ENTC",
    ofp_valid = true,
    ofp_origin_icao = "EGPE",
    ofp_origin_name = "INVERNESS",
    ofp_destination_icao = "ENTC",
    ofp_destination_name = "LANGNES"
})
local ofpDepartureText = core.buildMessage("departure.airborne", ofpSnapshot)
assert_equal(ofpDepartureText,
    "INVERNESS Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "matching OFP origin name overrides Refdata station name")
assert_equal(
    core.buildVoiceMessage("departure.airborne", ofpSnapshot, test_spell_nato, ofpDepartureText),
    "Inverness Traffic, Lufthansa tree two one zero airborne runway zero niner, passing tree zero zero feet",
    "matching OFP origin name is formatted for voice")
assert_equal(
    core.buildMessage("arrival.short_final", ofpSnapshot),
    "LANGNES Traffic, Lufthansa 3210 short final runway 27",
    "matching OFP destination name overrides Refdata station name")

local slashOfpSnapshot = copy(base, {
    departure_icao = "EDDF",
    departure_station_name = "FRANKFURT",
    departure_station_icao = "EDDF",
    ofp_valid = true,
    ofp_origin_icao = "EDDF",
    ofp_origin_name = "FRANKFURT/MAIN"
})
local slashOfpText = core.buildMessage("departure.airborne", slashOfpSnapshot)
assert_equal(slashOfpText,
    "FRANKFURT Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "OFP station name keeps only the part before slash")
assert_equal(
    core.buildVoiceMessage("departure.airborne", slashOfpSnapshot, test_spell_nato, slashOfpText),
    "Frankfurt Traffic, Lufthansa tree two one zero airborne runway zero niner, passing tree zero zero feet",
    "OFP slash normalization is shared by voice output")

assert_equal(
    core.buildMessage("departure.airborne", copy(base, {
        departure_icao = "KCMY",
        departure_station_name = "SPARTA/MCCOY",
        departure_station_icao = "KCMY",
        ofp_valid = false
    })),
    "SPARTA/MCCOY Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "slash normalization does not alter Refdata station names")

local longOfpSnapshot = copy(base, {
    arrival_icao = "PHNL",
    arrival_station_name = "HONOLULU",
    arrival_station_icao = "PHNL",
    ofp_valid = true,
    ofp_destination_icao = "PHNL",
    ofp_destination_name = "DANIEL K INOUYE INTL"
})
local longOfpText = core.buildMessage("arrival.short_final", longOfpSnapshot)
assert_equal(longOfpText,
    "HONOLULU Traffic, Lufthansa 3210 short final runway 27",
    "formal OFP airport name falls back to Refdata station name")
assert_equal(
    core.buildVoiceMessage("arrival.short_final", longOfpSnapshot, test_spell_nato, longOfpText),
    "Honolulu Traffic, Lufthansa tree two one zero short final runway two seven",
    "voice uses the same Refdata fallback as visible text")

local abbreviatedRegionalSnapshot = copy(base, {
    arrival_icao = "KTEX",
    arrival_station_name = "",
    arrival_station_icao = "",
    ofp_valid = true,
    ofp_destination_icao = "KTEX",
    ofp_destination_name = "TELLURIDE REGL"
})
local abbreviatedRegionalText = core.buildMessage("arrival.short_final", abbreviatedRegionalSnapshot)
assert_equal(
    abbreviatedRegionalText,
    "TELLURIDE Traffic, Lufthansa 3210 short final runway 27",
    "abbreviated regional descriptor is removed from OFP station name"
)
assert_equal(
    core.buildVoiceMessage(
        "arrival.short_final",
        abbreviatedRegionalSnapshot,
        test_spell_nato,
        abbreviatedRegionalText
    ),
    "Telluride Traffic, Lufthansa tree two one zero short final runway two seven",
    "abbreviated regional descriptor is removed from voice station name"
)

local embeddedAirportDescriptorSnapshot = copy(base, {
    departure_icao = "KSNA",
    departure_station_name = "",
    departure_station_icao = "",
    ofp_valid = true,
    ofp_origin_icao = "KSNA",
    ofp_origin_name = "JOHN WAYNE ARPT ORANGE CO"
})
local embeddedAirportDescriptorText = core.buildMessage("departure.airborne", embeddedAirportDescriptorSnapshot)
assert_equal(
    embeddedAirportDescriptorText,
    "JOHN WAYNE Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "embedded airport descriptor removes trailing administrative name text"
)
assert_equal(
    core.buildVoiceMessage(
        "departure.airborne",
        embeddedAirportDescriptorSnapshot,
        test_spell_nato,
        embeddedAirportDescriptorText
    ),
    "John Wayne Traffic, Lufthansa tree two one zero airborne runway zero niner, passing tree zero zero feet",
    "embedded airport descriptor produces concise voice station name"
)

assert_equal(
    core.resolveAirportLabel(copy(base, {
        departure_icao = "KIPL",
        departure_station_name = "IMPERIAL CO",
        departure_station_icao = "KIPL",
        ofp_valid = false
    }), "departure_icao", "departure_station_name"),
    "IMPERIAL",
    "known trailing county abbreviation is removed"
)

assert_equal(
    core.resolveAirportLabel(copy(base, {
        departure_icao = "KAAA",
        departure_station_name = "MOUNT PLEASANT SC",
        departure_station_icao = "KAAA",
        ofp_valid = false
    }), "departure_icao", "departure_station_name"),
    "MOUNT PLEASANT SC",
    "unrecognized two-letter station-name token is not removed"
)

local longOfpIcaoFallbackSnapshot = copy(longOfpSnapshot, {
    arrival_station_name = "",
    arrival_station_icao = ""
})
local longOfpIcaoFallbackText = core.buildMessage("arrival.short_final", longOfpIcaoFallbackSnapshot)
assert_equal(longOfpIcaoFallbackText,
    "PHNL Traffic, Lufthansa 3210 short final runway 27",
    "overlong OFP airport name falls back to ICAO without Refdata station name")
assert_equal(
    core.buildVoiceMessage(
        "arrival.short_final",
        longOfpIcaoFallbackSnapshot,
        test_spell_nato,
        longOfpIcaoFallbackText
    ),
    "Papa Hotel November Lima Traffic, Lufthansa tree two one zero short final runway two seven",
    "voice NATO-spells ICAO after formal OFP fallback")

assert_equal(
    core.buildMessage("arrival.short_final", copy(longOfpSnapshot, {
        ofp_destination_name = "HARTSFIELD JACKSON ATLANTA"
    })),
    "HONOLULU Traffic, Lufthansa 3210 short final runway 27",
    "overlong OFP airport name falls back to Refdata station name")

assert_equal(
    core.buildMessage("departure.airborne", copy(ofpSnapshot, {
        ofp_origin_name = "INVERNESS AIRPORT"
    })),
    "INVERNESS Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "formal OFP and Refdata controller descriptors are removed")

assert_equal(
    core.buildMessage("departure.airborne", copy(base, {
        departure_icao = "KINL",
        departure_station_name = "FALLS TOWER",
        departure_station_icao = "KINL",
        ofp_valid = true,
        ofp_origin_icao = "KINL",
        ofp_origin_name = "INTERNATIONAL FALLS"
    })),
    "INTERNATIONAL FALLS Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "valid multiword OFP name is not rejected by a non-final descriptor word")
assert_equal(
    core.buildMessage("departure.airborne", copy(base, {
        ofp_valid = true,
        ofp_origin_icao = "EGPE",
        ofp_origin_name = "INVERNESS"
    })),
    phraseCases[1][3],
    "OFP origin name is ignored when its ICAO does not match")
assert_equal(
    core.buildMessage("departure.airborne", copy(base, {
        ofp_valid = false,
        ofp_origin_icao = "ENAT",
        ofp_origin_name = "INVERNESS"
    })),
    phraseCases[1][3],
    "invalid OFP snapshot retains Refdata station name")

assert_equal(
    core.buildMessage("arrival.on_descent", copy(base, {
        altitude_ft = 18000,
        pressure_altitude_ft = 18000,
        planned_altitude_ft = 0
    })),
    "Lufthansa 3210 inbound SVALBARD, NELSA3M arrival, RNAV W approach runway 27, descent started from FL180",
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
    "ALTA Traffic, Lufthansa 3210 at parking position, preparing for departure to SVALBARD",
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
    "ESSA Traffic, Lufthansa 3210 pushing back from gate A12",
    "pushback gate phrase"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_parking_found = true,
        pushback_parking_type = "misc",
        pushback_parking_name = "Apron 42"
    })),
    "ALTA Traffic, Lufthansa 3210 pushing back from stand 42",
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
    "EDNY Traffic, Lufthansa 3210 at stand 1, preparing for departure to EVRA",
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
    "KMIA Traffic, Lufthansa 3210 at stand E28, preparing for departure to KMSY",
    "preflight extracts split stand identifier from KMIA descriptor"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_airport_icao = "EDNY",
        pushback_parking_found = true,
        pushback_parking_type = "tie_down",
        pushback_parking_name = "heavy|jets Apron 1 - Terminal"
    })),
    "EDNY Traffic, Lufthansa 3210 pushing back from stand 1",
    "pushback strips EDNY ramp descriptor punctuation"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_airport_icao = "KMIA",
        pushback_parking_found = true,
        pushback_parking_type = "misc",
        pushback_parking_name = "REMOTE E 28"
    })),
    "KMIA Traffic, Lufthansa 3210 pushing back from stand E28",
    "pushback extracts split stand identifier from KMIA descriptor"
)
assert_equal(
    core.buildMessage("departure.start_push", copy(base, {
        pushback_parking_found = true,
        pushback_parking_type = "gate",
        pushback_parking_name = "Gate B7, North"
    })),
    "ALTA Traffic, Lufthansa 3210 pushing back from gate B7",
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
    "SVALBARD Traffic, Lufthansa 3210 parked at stand 42",
    "arrival parking stand phrase"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "4 SMALL"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at stand 4",
    "arrival parking strips stand size suffix"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "HEAVY 4L"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at gate 4L",
    "arrival parking keeps attached gate suffix"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "Gate A-12"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at gate A12",
    "arrival parking normalizes embedded punctuation"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "4 R MEDIUM"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at stand 4R",
    "arrival parking compacts separate stand suffix"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "REMOTE E 28"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at stand E28",
    "arrival parking extracts split stand identifier from descriptor"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "Terminal 2 Gate E 28"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at gate E28",
    "arrival parking prefers marked identifier over descriptor number"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "jets|turboprops|props 216"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at gate 216",
    "arrival parking strips complete EVRA aircraft class field"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "gate",
        arrival_parking_name = "Gate"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at parking position",
    "arrival unnamed parking phrase"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "misc",
        arrival_parking_name = "REMOTE NORTH"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at parking position",
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
    "Lufthansa 3210 climbing out of ALTA on ATKUP1A departure, passing 1800ft for FL370",
    "initial climb phrase retains SID and tolerates missing next waypoint"
)
assert_equal(
    core.buildMessage("departure.on_climb", copy(base, {
        altitude_ft = 1800,
        pressure_altitude_ft = 1800,
        mcp_altitude_ft = 10000
    })),
    "Lufthansa 3210 climbing out of ALTA on ATKUP1A departure, passing 1800ft for FL100, BIRCO next",
    "initial climb phrase uses intermediate MCP restriction"
)
local reachingMcpSnapshot = copy(base, {
    altitude_ft = 10000,
    pressure_altitude_ft = 10000,
    mcp_altitude_ft = 10000
})
local reachingMcpText = core.buildMessage("departure.climb_level_10000", reachingMcpSnapshot)
assert_equal(
    reachingMcpText,
    "Lufthansa 3210 climbing out of ALTA, reaching FL100, BIRCO next",
    "climb progress does not say passing target for the same target"
)
assert_equal(
    core.buildVoiceMessage("departure.climb_level_10000", reachingMcpSnapshot, test_spell_nato, reachingMcpText),
    "Lufthansa tree two one zero climbing out of Alta, reaching flight level one zero zero, Birco next",
    "reaching MCP target has paired voice text"
)
assert_equal(
    core.buildMessage("departure.on_climb", copy(base, {
        altitude_ft = 1800,
        pressure_altitude_ft = 1800,
        mcp_altitude_ft = 40000
    })),
    phraseCases[2][3],
    "MCP above FMC cruise retains FMC cruise as effective climb target"
)
assert_equal(
    core.buildMessage("departure.climb_level_10000", copy(base, {
        altitude_ft = 12300,
        pressure_altitude_ft = 12300,
        mcp_altitude_ft = 12000,
        climb_next_waypoint = ""
    })),
    "Lufthansa 3210 climbing out of ALTA, passing FL123",
    "MCP materially below current altitude is omitted"
)
assert_equal(
    core.buildMessage("enroute.in_cruise", copy(base, {
        cruise_entry = true,
        cruise_next_waypoint = "BIRCO",
        altitude_ft = 38795,
        pressure_altitude_ft = 38824,
        planned_altitude_ft = 39000
    })),
    "Lufthansa 3210 level at FL390, BIRCO next",
    "cruise entry phrase uses nominal FMC cruise level"
)
local climbingCruiseEntry = copy(base, {
    cruise_entry = true,
    cruise_next_waypoint = "TUDGI",
    altitude_ft = 39860,
    pressure_altitude_ft = 39880,
    planned_altitude_ft = 40000,
    vertical_speed_fpm = 1243
})
local climbingCruiseEntryText = core.buildMessage("enroute.in_cruise", climbingCruiseEntry)
assert_equal(
    climbingCruiseEntryText,
    "Lufthansa 3210 reaching FL400, TUDGI next",
    "cruise entry does not claim level flight while still climbing"
)
assert_equal(
    core.buildVoiceMessage("enroute.in_cruise", climbingCruiseEntry, test_spell_nato, climbingCruiseEntryText),
    "Lufthansa tree two one zero reaching flight level fower zero zero, Tudgi next",
    "climbing cruise entry voice retains the reaching phrase"
)
assert_equal(
    core.buildMessage("enroute.in_cruise", copy(base, {
        cruise_entry = true,
        cruise_next_waypoint = "",
        altitude_ft = 37000,
        pressure_altitude_ft = 37000,
        planned_altitude_ft = 0
    })),
    "Lufthansa 3210 level at FL370",
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
    "Lufthansa 3210 passing BIRCO, maintaining FL388, SOMOR next",
    "recurring cruise phrase keeps live pressure altitude"
)
assert_equal(
    core.buildMessage("enroute.in_cruise", copy(base, {
        cruise_periodic = true,
        cruise_next_waypoint = "RIGVU",
        altitude_ft = 40000,
        pressure_altitude_ft = 40000
    })),
    "Lufthansa 3210 maintaining FL400, RIGVU next",
    "periodic cruise phrase does not claim a stale waypoint passage"
)
assert_equal(
    core.buildMessage("enroute.in_cruise", copy(base, {
        cruise_periodic = true,
        cruise_next_waypoint = "",
        altitude_ft = 40000,
        pressure_altitude_ft = 40000
    })),
    "Lufthansa 3210 maintaining FL400",
    "periodic cruise phrase tolerates a missing next waypoint"
)
assert_equal(
    core.buildMessage("arrival.parking_position", copy(base, {
        arrival_parking_found = true,
        arrival_parking_type = "cargo",
        arrival_parking_name = "Cargo 12"
    })),
    "SVALBARD Traffic, Lufthansa 3210 parked at stand CARGO 12",
    "arrival parking accepts unfiltered ramp type"
)

assert_equal(
    core.buildMessage("arrival.on_final", copy(base, { approach_procedure_type = "LOC" })),
    "SVALBARD Traffic, Lufthansa 3210 established on Localizer runway 27",
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
    copy(base, {
        hold_waypoint = "BIRCO",
        altitude_ft = false,
        pressure_altitude_ft = false
    })
)
assert_equal(missingHoldDescentText, nil, "hold descent phrase requires current altitude")
assert_equal(missingHoldDescentReason, "missing_hold_descent_context", "missing hold descent altitude reason")
assert_equal(
    core.buildMessage("enroute.hold_descending", copy(base, {
        hold_waypoint = "BIRCO",
        altitude_ft = 12220,
        pressure_altitude_ft = 12210
    })),
    "Lufthansa 3210 in a hold over BIRCO on descent passing FL122",
    "targetless hold descent omits an invented target"
)

local missingIntersectionText, missingIntersectionReason = core.buildMessage("departure.intersection", base)
assert_equal(missingIntersectionText, nil, "legacy intersection line-up requires intersection")
assert_equal(missingIntersectionReason, "missing_intersection_context", "missing intersection reason")
assert_equal(
    core.buildMessage("departure.lining_up", copy(base, { departure_intersection = "Intersection A" })),
    "ALTA Traffic, Lufthansa 3210 lining up runway 09 at taxiway A",
    "line-up phrase identifies confirmed intersection as taxiway"
)
assert_equal(
    core.buildVoiceMessage(
        "departure.lining_up",
        copy(base, { departure_intersection = "Intersection A" }),
        test_spell_nato
    ),
    "Alta Traffic, Lufthansa tree two one zero lining up runway zero niner at taxiway Alpha",
    "line-up voice speaks confirmed taxiway naturally"
)
assert_equal(
    core.buildVoiceMessage(
        "departure.hold_short",
        copy(base, { departure_intersection = "Intersection A" }),
        test_spell_nato
    ),
    "Alta Traffic, Lufthansa tree two one zero holding short runway zero niner at taxiway Alpha",
    "hold-short voice identifies confirmed taxiway naturally"
)
assert_equal(
    core.buildVoiceMessage(
        "departure.backtrack",
        copy(base, { departure_intersection = "A" }),
        test_spell_nato
    ),
    "Alta Traffic, Lufthansa tree two one zero backtracking runway zero niner",
    "backtrack voice omits runway-entry intersection"
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
assert_true(mailbox:enqueue({
    id = "departure.airborne",
    text = phraseCases[1][3],
    voice_text = phraseCases[1][3],
    created_at = 0,
    expires_at = 60
}), "mailbox enqueue")
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
assert_equal(#writes, 2, "v1 ignores staged voice text and stays text-only")
api.result_seq = 8
api.result_code = 10
mailbox:tick(api, 1)
assert_true(mailbox.outstanding ~= nil, "accepted is non-terminal")
api.result_code = 21
mailbox:tick(api, 2)
assert_true(mailbox.outstanding == nil, "submitted result completes request")
assert_equal(mailboxLogs[#mailboxLogs].kind, "terminal", "terminal result logged")

local v2Writes = {}
local v2Logs = {}
local v2Mailbox = core.newMailbox({
    writeText = function(text)
        table.insert(v2Writes, { kind = "text", value = text })
        return true
    end,
    writeVoiceText = function(text)
        table.insert(v2Writes, { kind = "voice", value = text })
        return true
    end,
    writeChannels = function(channels)
        table.insert(v2Writes, { kind = "channels", value = channels })
        return true
    end,
    writeSeq = function(seq)
        table.insert(v2Writes, { kind = "seq", value = seq })
        return true
    end,
    log = function(kind, event)
        table.insert(v2Logs, { kind = kind, event = event })
    end
})
local v2Api = {
    api_version = 2,
    ready = 1,
    mode = 2,
    transport_state = 5,
    request_seq = 20,
    result_seq = 20,
    result_code = 21,
    voice_result_seq = 20,
    voice_result_code = 20
}
assert_true(v2Mailbox:enqueue({
    id = "departure.on_climb",
    text = phraseCases[2][3],
    voice_text = voiceCases[2][3],
    created_at = 0,
    expires_at = 60
}), "v2 voice mailbox enqueue")
v2Mailbox:tick(v2Api, 0)
assert_equal(v2Writes[1].kind, "text", "v2 text written first")
assert_equal(v2Writes[2].kind, "voice", "v2 voice text written after text")
assert_equal(v2Writes[2].value, voiceCases[2][3], "v2 exact voice text")
assert_equal(v2Writes[3].kind, "channels", "v2 channels written after voice text")
assert_equal(v2Writes[3].value, 3, "v2 text plus voice mask")
assert_equal(v2Writes[4].kind, "seq", "v2 sequence remains final write")
assert_equal(v2Writes[4].value, 21, "v2 increasing sequence")
v2Api.result_seq = 21
v2Api.result_code = 21
v2Mailbox:tick(v2Api, 1)
assert_true(v2Mailbox.outstanding ~= nil, "v2 text result does not hide pending voice")
assert_equal(v2Logs[#v2Logs].kind, "terminal", "v2 text result logged separately")
v2Api.voice_result_seq = 21
v2Api.voice_result_code = 10
v2Mailbox:tick(v2Api, 32)
assert_true(v2Mailbox.outstanding ~= nil, "v2 pending voice uses separate extended timeout")
v2Api.voice_result_code = 20
v2Api.voice_result_detail = "VOICE_TRANSMITTED"
v2Mailbox:tick(v2Api, 33)
assert_true(v2Mailbox.outstanding == nil, "v2 request completes after voice result")
assert_equal(v2Logs[#v2Logs].kind, "voice_terminal", "v2 voice result logged separately")
assert_equal(v2Logs[#v2Logs].event.voice_result_name, "TRANSMITTED", "v2 voice result decoded")

local v2TextWrites = {}
local v2TextMailbox = core.newMailbox({
    writeText = function(text)
        table.insert(v2TextWrites, { kind = "text", value = text })
        return true
    end,
    writeVoiceText = function(text)
        table.insert(v2TextWrites, { kind = "voice", value = text })
        return true
    end,
    writeChannels = function(channels)
        table.insert(v2TextWrites, { kind = "channels", value = channels })
        return true
    end,
    writeSeq = function(seq)
        table.insert(v2TextWrites, { kind = "seq", value = seq })
        return true
    end
})
assert_true(v2TextMailbox:enqueue({
    id = "departure.airborne",
    text = phraseCases[1][3],
    created_at = 0,
    expires_at = 60
}), "v2 text-only mailbox enqueue")
v2Api.request_seq = 30
v2Api.result_seq = 30
v2Api.result_code = 21
v2Api.voice_result_seq = 30
v2Api.voice_result_code = 20
v2TextMailbox:tick(v2Api, 0)
assert_equal(v2TextWrites[1].kind, "text", "v2 text-only writes text first")
assert_equal(v2TextWrites[2].kind, "channels", "v2 text-only writes channel before sequence")
assert_equal(v2TextWrites[2].value, 1, "v2 text-only mask")
assert_equal(v2TextWrites[3].kind, "seq", "v2 text-only sequence last")
assert_equal(#v2TextWrites, 3, "v2 text-only never writes voice staging")

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
    text = "SVALBARD Traffic, Lufthansa 3210 crossing runway 16",
    expires_at = 100
}), "enqueue runway crossing before parking")
assert_true(parkingMailbox:enqueue({
    id = "arrival.parking_position",
    text = "SVALBARD Traffic, Lufthansa 3210 parked at gate B7",
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
    id = "enroute.holding",
    text = core.buildMessage("enroute.holding", copy(base, {
        hold_waypoint = "BIRCO",
        hold_target_altitude_ft = 25000,
        altitude_ft = 25020,
        pressure_altitude_ft = 25010
    })),
    expires_at = 100
}), "enqueue level hold after descent")
assert_equal(#holdMailbox.queue, 1, "level hold supersedes stale queued descent")
assert_equal(holdMailbox.queue[1].id, "enroute.holding", "level hold remains queued after descent")
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
    text = "ALTA Traffic, Lufthansa 3210 at gate 4, preparing for departure to SVALBARD",
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
    text = "ALTA Traffic, Lufthansa 3210 crossing runway 08 at taxiway Z",
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
    text = "SVALBARD Traffic, Lufthansa 3210 backtracking runway 27",
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
    text = "SVALBARD Traffic, Lufthansa 3210 crossing runway 16",
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
    result_detail = "result_detail",
    request_channels = "request_channels",
    request_voice_text = "request_voice_text",
    voice_state = "voice_state",
    voice_result_seq = "voice_result_seq",
    voice_result_code = "voice_result_code",
    voice_result_detail = "voice_result_detail",
    effective_callsign = "effective_callsign"
}
local repeatValues = {
    api_version = 3,
    ready = 1,
    mode = 2,
    transport_state = 5,
    request_text = phraseCases[5][3],
    request_seq = 12,
    result_seq = 12,
    result_code = 21,
    result_detail = "SUBMITTED_VISIBLE",
    effective_callsign = "DLH3210"
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
    mcpaltitude = "mcpaltitude",
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
    api_version = 3,
    ready = 1,
    mode = 2,
    transport_state = 5,
    request_text = phraseCases[3][3],
    request_seq = 12,
    result_seq = 12,
    result_code = 21,
    result_detail = "SUBMITTED_VISIBLE",
    effective_callsign = "DLH3210",
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
    mcpaltitude = 37000,
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
        spellNato = test_spell_nato,
        parseSelectedApproachId = function()
            return { suffix = "W", navType = "RNAV" }
        end
    },
    sources = {
        pressure_altitude = "pressure_altitude",
        aircraft_icao = "aircraft_icao"
    },
    refdata = { getAirport = test_refdata_airport },
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

repeatValues.mode = 2
repeatValues.api_version = 2
configure_repeat_test()
autoUnicom.tick(true, 0)
assert_equal(autoUnicom.getDebugState().active, false, "API v2 cannot activate identity-aware Auto-Unicom")
local repeatedV2, repeatV2Reason = autoUnicom.repeatLastMessage(true)
assert_equal(repeatedV2, false, "API v2 repeat is rejected")
assert_equal(repeatV2Reason, "api_unavailable", "API v2 repeat rejection reason")

repeatValues.api_version = 3
repeatValues.effective_callsign = ""
configure_repeat_test()
autoUnicom.tick(true, 0)
assert_equal(autoUnicom.getDebugState().active, false, "empty effective callsign keeps Auto-Unicom inactive")
local repeatedNoCallsign, repeatNoCallsignReason = autoUnicom.repeatLastMessage(true)
assert_equal(repeatedNoCallsign, false, "repeat without effective callsign is rejected")
assert_equal(repeatNoCallsignReason, "api_unavailable", "missing callsign repeat rejection reason")
local missingCallsignLogs = {}
autoUnicom.configure({
    helpers = { logInfoTS = function(message) table.insert(missingCallsignLogs, message) end },
    getRefs = function() return repeatRefs end,
    read = function(prop) return repeatValues[prop] end
})
autoUnicom.tick(true, 0)
autoUnicom.tick(true, 1)
assert_equal(#missingCallsignLogs, 1, "missing callsign diagnostic is latched")
assert_equal(
    missingCallsignLogs[1],
    "IVAO Auto-Unicom API ready but effective callsign is unavailable",
    "missing callsign diagnostic text"
)
repeatValues.effective_callsign = "DLH3210"

local eventAdapterValues = {
    api_version = 3,
    ready = 1,
    mode = 2,
    transport_state = 5,
    request_seq = 30,
    result_seq = 30,
    result_code = 21,
    result_detail = "SUBMITTED_VISIBLE",
    effective_callsign = "DLH3210",
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
    mcpaltitude = 37000,
    depicao = "ENAT",
    deprwy = "09",
    desicao = "ENSB",
    desrwy = "27",
    fmsselectedsid = "ATKUP1A",
    fmsselectedstar = "NELSA3M",
    fmsselectedapp = "R27-W",
    fmsfplnnavid = "",
    fmslegs = "",
    fmslegslat = {},
    fmslegslon = {},
    fmslegscrsmag = {},
    fmsvnavidx = 0,
    fmscustomwptnum = 0,
    fmscustomwptid = "",
    fmscustomwptlat = {},
    fmscustomwptlon = {},
    ofp_api_version = 1,
    ofp_update_seq = 2,
    ofp_valid = 0,
    ofp_origin_icao = "",
    ofp_origin_name = "",
    ofp_destination_icao = "",
    ofp_destination_name = "",
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
    fmsfplnnavid = "fmsfplnnavid",
    fmslegs = "fmslegs",
    fmslegslat = "fmslegslat",
    fmslegslon = "fmslegslon",
    fmslegscrsmag = "fmslegscrsmag",
    fmsvnavidx = "fmsvnavidx",
    fmscustomwptnum = "fmscustomwptnum",
    fmscustomwptid = "fmscustomwptid",
    fmscustomwptlat = "fmscustomwptlat",
    fmscustomwptlon = "fmscustomwptlon",
    ofpRuntime = {
        api_version = "ofp_api_version",
        update_seq = "ofp_update_seq",
        valid = "ofp_valid",
        origin_icao = "ofp_origin_icao",
        origin_name = "ofp_origin_name",
        destination_icao = "ofp_destination_icao",
        destination_name = "ofp_destination_name"
    },
    flightstate = baselineDef.FLIGHTSTATEPREFLIGHT
})
local eventAdapterWrites = {}
local eventAdapterLogs = {}
local ofpUpdateSeqReads = nil
local ofpUpdateSeqReadIndex = 0
local pushbackRamp = { ramp_type = "misc", name = "Apron 42" }
local pushbackDistanceSquared = 25
local pushbackSearchAirports = {}
local eventAdapterFixApiAvailable = false
local eventAdapterPublishedFixes = {}
local function configure_event_adapter_test()
    ofpUpdateSeqReadIndex = 0
    autoUnicom.configure({
        yal = eventAdapterYal,
        def = baselineDef,
        helpers = {
            logInfoTS = function(message) table.insert(eventAdapterLogs, message) end,
            spellNato = test_spell_nato,
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
        refdata = {
            getAirport = test_refdata_airport,
            getNavByIdent = test_refdata_nav,
            getFixByIdent = function(ident)
                return eventAdapterPublishedFixes[tostring(ident or ""):upper()]
            end,
            isCategoryAvailable = function(category)
                return category == "fix" and eventAdapterFixApiAvailable
            end
        },
        getRefs = function() return repeatRefs end,
        read = function(prop)
            if prop == "ofp_update_seq" and type(ofpUpdateSeqReads) == "table" then
                ofpUpdateSeqReadIndex = ofpUpdateSeqReadIndex + 1
                return ofpUpdateSeqReads[ofpUpdateSeqReadIndex]
                    or ofpUpdateSeqReads[#ofpUpdateSeqReads]
            end
            return eventAdapterValues[prop]
        end,
        writeText = function(prop, text)
            local kind = prop == repeatRefs.request_voice_text and "voice" or "text"
            table.insert(eventAdapterWrites, { kind = kind, value = text })
            return true
        end,
        writeChannels = function(_, channels)
            table.insert(eventAdapterWrites, { kind = "channels", value = channels })
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
    "ALTA Traffic, Lufthansa 3210 at gate 4, preparing for departure to SVALBARD",
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
assert_equal(eventAdapterWrites[1].value, "ESSA Traffic, Lufthansa 3210 pushing back from stand 42",
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
assert_equal(eventAdapterWrites[1].value, "PAHO Traffic, Lufthansa 3210 runway 04 vacated, taxiing to gate",
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
assert_equal(eventAdapterWrites[1].value, "PAHO Traffic, Lufthansa 3210 backtracking runway 04",
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
assert_equal(eventAdapterWrites[1].value, "PAHO Traffic, Lufthansa 3210 parked at gate B7",
    "arrival parking uses Zibo nearest gate")

eventAdapterWrites = {}
eventAdapterValues.request_seq = 80
eventAdapterValues.result_seq = 80
eventAdapterValues.result_code = 21
eventAdapterValues.voice_result_seq = 80
eventAdapterValues.voice_result_code = 20
eventAdapterValues.desicao = "ENSB"
eventAdapterValues.desrwy = "27"
eventAdapterValues.ofp_valid = 1
eventAdapterValues.ofp_origin_icao = "PHLI"
eventAdapterValues.ofp_origin_name = "LIHUE"
eventAdapterValues.ofp_destination_icao = "ENSB"
eventAdapterValues.ofp_destination_name = "LANGNES"
eventAdapterValues.nearesticao = "ENSB"
configure_event_adapter_test()
autoUnicom.tick(true, 0)

local function commit_cached_arrival_event(eventId, payload, now)
    eventAdapterWrites = {}
    assert_true(autoUnicom.handleYalEvent(eventId, payload, now), eventId .. " accepted")
    autoUnicom.tick(true, now)
    local text = eventAdapterWrites[1] and eventAdapterWrites[1].value or nil
    local voiceText = eventAdapterWrites[2] and eventAdapterWrites[2].value or nil
    local seq = nil
    for _, write in ipairs(eventAdapterWrites) do
        if write.kind == "seq" then seq = write.value end
    end
    assert_true(seq ~= nil, eventId .. " committed")
    eventAdapterValues.result_seq = seq
    eventAdapterValues.result_code = 21
    eventAdapterValues.voice_result_seq = seq
    eventAdapterValues.voice_result_code = 20
    autoUnicom.tick(true, now + 0.1)
    return text, voiceText
end

commit_cached_arrival_event("arrival.approach", nil, 1)
eventAdapterValues.desicao = "****"
eventAdapterValues.desrwy = "----"
eventAdapterValues.ofp_valid = 0
eventAdapterValues.ofp_origin_icao = ""
eventAdapterValues.ofp_origin_name = ""
eventAdapterValues.ofp_destination_icao = ""
eventAdapterValues.ofp_destination_name = ""

local cachedBacktrackText, cachedBacktrackVoice = commit_cached_arrival_event("arrival.backtrack", {
    arrival_icao = "ENSB",
    arrival_runway = "27"
}, 2)
assert_equal(cachedBacktrackText, "LANGNES Traffic, Lufthansa 3210 backtracking runway 27",
    "arrival backtrack retains OFP name over Refdata after FMC reset")
assert_equal(cachedBacktrackVoice,
    "Langnes Traffic, Lufthansa tree two one zero backtracking runway two seven",
    "arrival backtrack voice retains OFP name after FMC reset")
assert_equal(commit_cached_arrival_event("arrival.runway_vacated", {
    arrival_icao = "ENSB",
    arrival_runway = "27"
}, 3), "LANGNES Traffic, Lufthansa 3210 runway 27 vacated, taxiing to gate",
    "runway vacated retains station name after FMC reset")
assert_equal(commit_cached_arrival_event("arrival.runway_crossing", {
    arrival_icao = "ENSB",
    crossing_runway = "22"
}, 4), "LANGNES Traffic, Lufthansa 3210 crossing runway 22",
    "arrival runway crossing retains station name after FMC reset")
local cachedParkingText, cachedParkingVoice = commit_cached_arrival_event("arrival.parking_position", {
    arrival_icao = "ENSB",
    arrival_runway = "27",
    arrival_parking_found = true,
    arrival_parking_type = "gate",
    arrival_parking_name = "B7",
    arrival_parking_airport_icao = "ENSB"
}, 5)
assert_equal(cachedParkingText, "LANGNES Traffic, Lufthansa 3210 parked at gate B7",
    "arrival parking retains station name after FMC reset")
assert_equal(cachedParkingVoice,
    "Langnes Traffic, Lufthansa tree two one zero parked at gate Bravo seven",
    "arrival parking voice retains station name after FMC reset")
assert_equal(commit_cached_arrival_event("arrival.backtrack", {
    arrival_icao = "PANC",
    arrival_runway = "07R"
}, 6), "PANC Traffic, Lufthansa 3210 backtracking runway 07R",
    "cached station name is never reused for another ICAO")

eventAdapterValues.desicao = "ENSB"
eventAdapterValues.desrwy = "27"
eventAdapterValues.ofp_valid = 0
eventAdapterValues.nearesticao = "PAHO"

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

eventAdapterWrites = {}
eventAdapterValues.request_seq = 65
eventAdapterValues.result_seq = 65
eventAdapterValues.result_code = 21
eventAdapterValues.ofp_valid = 1
eventAdapterValues.ofp_origin_icao = "ENAT"
eventAdapterValues.ofp_origin_name = "INVERNESS"
eventAdapterValues.ofp_destination_icao = "ENSB"
eventAdapterValues.ofp_destination_name = "LANGNES"
ofpUpdateSeqReads = nil
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("departure.airborne", nil, 1),
    "stable OFP Runtime snapshot event accepted")
autoUnicom.tick(true, 1)
assert_equal(eventAdapterWrites[1].value,
    "INVERNESS Traffic, Lufthansa 3210 airborne runway 09, passing 300ft",
    "adapter prefers matching OFP airport name")

eventAdapterWrites = {}
eventAdapterValues.request_seq = 66
eventAdapterValues.result_seq = 66
eventAdapterValues.result_code = 21
ofpUpdateSeqReads = { 2, 4, 2, 4, 2, 4, 2, 4, 2, 4, 2, 4 }
configure_event_adapter_test()
autoUnicom.tick(true, 0)
ofpUpdateSeqReadIndex = 0
assert_true(autoUnicom.handleYalEvent("departure.airborne", nil, 1),
    "event with unstable OFP Runtime snapshot accepted through fallback")
autoUnicom.tick(true, 1)
assert_equal(eventAdapterWrites[1].value, phraseCases[1][3],
    "unstable OFP Runtime snapshot retains Refdata fallback")
ofpUpdateSeqReads = nil
eventAdapterValues.ofp_valid = 0
eventAdapterValues.ofp_origin_icao = ""
eventAdapterValues.ofp_origin_name = ""
eventAdapterValues.ofp_destination_icao = ""
eventAdapterValues.ofp_destination_name = ""

eventAdapterWrites = {}
eventAdapterValues.request_seq = 67
eventAdapterValues.result_seq = 67
eventAdapterValues.result_code = 21
eventAdapterValues.altitude_ft = 1800
eventAdapterValues.pressure_altitude = 1800
eventAdapterValues.fmsfplnnavid = "(VECTO\0"
eventAdapterValues.fmslegscrsmag = { 0, 196.654266, 194, 210 }
eventAdapterValues.fmsvnavidx = 4
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("departure.on_climb", nil, 1),
    "raw Zibo vector event accepted")
autoUnicom.tick(true, 1)
assert_equal(
    eventAdapterWrites[1].value,
    "Lufthansa 3210 climbing out of ALTA on ATKUP1A departure, passing 1800ft for FL370, flying heading 210",
    "adapter resolves KSNA active vector leg instead of preceding runway leg"
)
assert_equal(
    eventAdapterWrites[2].value,
    "Lufthansa tree two one zero climbing out of Alta on Atkup one Alpha departure, passing one eight zero zero feet for flight level tree seven zero, flying heading two one zero",
    "adapter keeps vector semantics aligned in Voice"
)
eventAdapterValues.altitude_ft = 300
eventAdapterValues.pressure_altitude = 300
eventAdapterValues.fmsfplnnavid = ""
eventAdapterValues.fmslegscrsmag = {}
eventAdapterValues.fmsvnavidx = 0

eventAdapterWrites = {}
eventAdapterValues.request_seq = 68
eventAdapterValues.result_seq = 68
eventAdapterValues.result_code = 21
eventAdapterValues.fmslegs = "TAKIE 15N154W KOA"
eventAdapterValues.fmslegslat = { 14.2, 15, 19.4 }
eventAdapterValues.fmslegslon = { -151.1, -154, -155.9 }
eventAdapterValues.fmsvnavidx = 2
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("enroute.in_cruise", {
    cruise_entry = true,
    cruise_next_waypoint = "15N154",
    planned_altitude_ft = 40000
}, 1), "truncated coordinate waypoint event accepted")
autoUnicom.tick(true, 1)
assert_equal(
    eventAdapterWrites[1].value,
    "Lufthansa 3210 level at FL400, 15N154W next",
    "full FMS leg restores truncated coordinate waypoint"
)
assert_equal(
    eventAdapterWrites[2].value,
    "Lufthansa tree two one zero level at flight level fower zero zero, one fife north one fife four west next",
    "restored coordinate waypoint gets dedicated voice formatting"
)

eventAdapterWrites = {}
eventAdapterValues.request_seq = 69
eventAdapterValues.result_seq = 69
eventAdapterValues.result_code = 21
eventAdapterValues.fmslegs = "SUBUK DCS NESDI"
eventAdapterValues.fmslegslat = { 54.1, 54.7217, 55.2 }
eventAdapterValues.fmslegslon = { -3.3, -3.3408, -2.8 }
eventAdapterValues.fmsvnavidx = 3
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("enroute.in_cruise", {
    cruise_waypoint = "DCS",
    cruise_next_waypoint = "NESDI",
    altitude_ft = 37000,
    pressure_altitude_ft = 37000
}, 1), "NAV facility waypoint event accepted")
autoUnicom.tick(true, 1)
assert_equal(
    eventAdapterWrites[1].value,
    "Lufthansa 3210 passing DCS, maintaining FL370, NESDI next",
    "visible waypoint text retains NAV ident"
)
assert_equal(
    eventAdapterWrites[2].value,
    "Lufthansa tree two one zero passing Dean Cross, maintaining flight level tree seven zero, Nesdi next",
    "NAV adapter enriches position report voice with facility name"
)

eventAdapterWrites = {}
eventAdapterValues.request_seq = 70
eventAdapterValues.result_seq = 70
eventAdapterValues.result_code = 21
eventAdapterValues.fmslegs = "CLAWW PHL01 LIH JABDI"
eventAdapterValues.fmslegslat = { 41.9, 42.1, 42.2, 42.3 }
eventAdapterValues.fmslegslon = { -71.0, -71.1, -71.2, -71.3 }
eventAdapterValues.fmsvnavidx = 2
eventAdapterValues.fmscustomwptnum = 1
eventAdapterValues.fmscustomwptid = "PHL01"
eventAdapterValues.fmscustomwptlat = { 42.1 }
eventAdapterValues.fmscustomwptlon = { -71.1 }
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("enroute.in_cruise", {
    cruise_entry = true,
    cruise_next_waypoint = "PHL01",
    planned_altitude_ft = 37000
}, 1), "custom next waypoint event accepted")
autoUnicom.tick(true, 1)
assert_equal(
    eventAdapterWrites[1].value,
    "Lufthansa 3210 level at FL370, LIH next",
    "custom next waypoint skips to following operational route leg"
)
assert_equal(
    eventAdapterWrites[2].value,
    "Lufthansa tree two one zero level at flight level tree seven zero, Lihue next",
    "custom next waypoint voice uses following NAV facility name"
)

eventAdapterWrites = {}
eventAdapterValues.request_seq = 71
eventAdapterValues.result_seq = 71
eventAdapterValues.result_code = 21
eventAdapterValues.fmslegs = "CLAWW PHL01"
eventAdapterValues.fmslegslat = { 41.9, 42.1 }
eventAdapterValues.fmslegslon = { -71.0, -71.1 }
eventAdapterValues.fmsvnavidx = 2
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("enroute.in_cruise", {
    cruise_entry = true,
    cruise_next_waypoint = "PHL01",
    planned_altitude_ft = 37000
}, 1), "terminal custom next waypoint event accepted")
autoUnicom.tick(true, 1)
assert_equal(
    eventAdapterWrites[1].value,
    "Lufthansa 3210 level at FL370",
    "terminal custom next waypoint is omitted"
)
assert_equal(eventAdapterWrites[1].value:find("PHL01", 1, true), nil,
    "terminal custom next waypoint is absent from visible text")
assert_equal(eventAdapterWrites[2].value:find("PHL01", 1, true), nil,
    "terminal custom next waypoint is absent from voice text")

eventAdapterWrites = {}
eventAdapterValues.request_seq = 72
eventAdapterValues.result_seq = 72
eventAdapterValues.result_code = 21
eventAdapterValues.fmslegs = "PHL01 LIH"
eventAdapterValues.fmslegslat = { 42.1, 42.2 }
eventAdapterValues.fmslegslon = { -71.1, -71.2 }
eventAdapterValues.fmsvnavidx = 2
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("enroute.in_cruise", {
    cruise_waypoint = "PHL01",
    cruise_next_waypoint = "LIH",
    altitude_ft = 37000,
    pressure_altitude_ft = 37000
}, 1), "passed custom waypoint event accepted")
autoUnicom.tick(true, 1)
assert_equal(
    eventAdapterWrites[1].value,
    "Lufthansa 3210 maintaining FL370, LIH next",
    "passed custom waypoint is omitted without losing position report"
)

eventAdapterWrites = {}
eventAdapterValues.request_seq = 73
eventAdapterValues.result_seq = 73
eventAdapterValues.result_code = 21
eventAdapterValues.fmscustomwptnum = 0
eventAdapterValues.fmscustomwptid = ""
eventAdapterValues.fmscustomwptlat = {}
eventAdapterValues.fmscustomwptlon = {}
eventAdapterValues.fmslegs = "MAARE D271V HUXEL"
eventAdapterValues.fmslegslat = { 41.8, 42.0, 42.2 }
eventAdapterValues.fmslegslon = { -71.0, -71.2, -71.4 }
eventAdapterValues.fmsvnavidx = 2
eventAdapterFixApiAvailable = true
eventAdapterPublishedFixes = { HUXEL = { ident = "HUXEL", lat = 42.2, lon = -71.4 } }
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("enroute.in_cruise", {
    cruise_entry = true,
    cruise_next_waypoint = "D271V",
    planned_altitude_ft = 37000
}, 1), "unpublished Refdata waypoint event accepted")
autoUnicom.tick(true, 1)
assert_equal(
    eventAdapterWrites[1].value,
    "Lufthansa 3210 level at FL370, HUXEL next",
    "FIX API skips an unpublished generated waypoint"
)

eventAdapterWrites = {}
eventAdapterValues.request_seq = 74
eventAdapterValues.result_seq = 74
eventAdapterValues.result_code = 21
eventAdapterValues.fmslegs = "PHL01"
eventAdapterValues.fmslegslat = { 42.0 }
eventAdapterValues.fmslegslon = { -71.0 }
eventAdapterValues.fmsvnavidx = 1
eventAdapterValues.fmscustomwptnum = 1
eventAdapterValues.fmscustomwptid = "PHL01"
eventAdapterValues.fmscustomwptlat = { 42.0 }
eventAdapterValues.fmscustomwptlon = { -71.0 }
eventAdapterFixApiAvailable = false
eventAdapterPublishedFixes = {}
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("enroute.hold_enter", {
    hold_waypoint = "PHL01"
}, 1), "custom hold waypoint event accepted")
autoUnicom.tick(true, 1)
assert_equal(
    eventAdapterWrites[1].value,
    "Lufthansa 3210 entering a hold at position 4200N07100W",
    "custom hold waypoint uses geographic position"
)
assert_equal(
    eventAdapterWrites[2].value,
    "Lufthansa tree two one zero entering a hold at position four two degrees zero zero minutes north zero seven one degrees zero zero minutes west",
    "custom hold waypoint voice speaks geographic position"
)

eventAdapterValues.fmslegs = ""
eventAdapterValues.fmslegslat = {}
eventAdapterValues.fmslegslon = {}
eventAdapterValues.fmsvnavidx = 0
eventAdapterValues.fmscustomwptnum = 0
eventAdapterValues.fmscustomwptid = ""
eventAdapterValues.fmscustomwptlat = {}
eventAdapterValues.fmscustomwptlon = {}
eventAdapterFixApiAvailable = false
eventAdapterPublishedFixes = {}

eventAdapterWrites = {}
eventAdapterValues.api_version = 3
eventAdapterValues.request_seq = 75
eventAdapterValues.result_seq = 75
eventAdapterValues.result_code = 21
eventAdapterValues.voice_state = 1
eventAdapterValues.voice_result_seq = 75
eventAdapterValues.voice_result_code = 20
eventAdapterValues.voice_result_detail = "VOICE_TRANSMITTED"
eventAdapterLogs = {}
configure_event_adapter_test()
autoUnicom.tick(true, 0)
assert_true(autoUnicom.handleYalEvent("departure.airborne", nil, 1), "YAL v3 event accepted")
autoUnicom.tick(true, 1)
assert_equal(eventAdapterWrites[1].kind, "text", "YAL v3 adapter writes text first")
assert_equal(eventAdapterWrites[2].kind, "voice", "YAL v3 adapter writes voice text second")
assert_equal(eventAdapterWrites[1].value, phraseCases[1][3], "YAL v3 adapter keeps visible text aligned")
assert_equal(eventAdapterWrites[2].value, voiceCases[1][3], "YAL v3 adapter writes formatted voice text")
assert_equal(eventAdapterWrites[3].kind, "channels", "YAL v3 adapter writes channels third")
assert_equal(eventAdapterWrites[3].value, 3, "YAL v3 adapter requests text plus voice")
assert_equal(eventAdapterWrites[4].kind, "seq", "YAL v3 adapter commits sequence last")
local queuedVoiceLogged = false
local committedVoiceLogged = false
for _, message in ipairs(eventAdapterLogs) do
    if message:find("IVAO Auto-Unicom: queued event=departure.airborne", 1, true)
        and message:find("voice_text=" .. voiceCases[1][3], 1, true) then
        queuedVoiceLogged = true
    end
    if message:find("IVAO Auto-Unicom: committed event=departure.airborne", 1, true)
        and message:find("voice_text=" .. voiceCases[1][3], 1, true) then
        committedVoiceLogged = true
    end
end
assert_true(queuedVoiceLogged, "queued Auto-Unicom log includes normalized voice text")
assert_true(committedVoiceLogged, "committed Auto-Unicom log includes exact voice payload")

eventAdapterValues.result_seq = 76
eventAdapterValues.result_code = 21
eventAdapterValues.voice_result_seq = 76
eventAdapterValues.voice_result_code = 20
autoUnicom.tick(true, 2)
eventAdapterWrites = {}
assert_true(autoUnicom.repeatLastMessage(true), "YAL v3 repeat accepts last structured message")
autoUnicom.tick(true, 3)
assert_equal(eventAdapterWrites[1].value, phraseCases[1][3], "YAL v3 repeat keeps visible text")
assert_equal(eventAdapterWrites[2].value, voiceCases[1][3], "YAL v3 repeat keeps paired voice text")
assert_equal(eventAdapterWrites[3].value, 3, "YAL v3 repeat keeps text plus voice channels")

print("auto_unicom tests passed")
