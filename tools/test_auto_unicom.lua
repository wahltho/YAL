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
    on_runway_profile = true,
    on_departure_runway = false,
    final_gate = false,
    preflight = false,
    before_taxi_started = false,
    before_takeoff_started = false,
    parking_brake_released = false,
    wheel_speed = 0,
    pushback_active = false,
    eng1_n1_percent = 0,
    eng2_n1_percent = 0,
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

local groundEvents = {}
local groundEngine = core.newEventEngine({
    emit = function(event)
        table.insert(groundEvents, event)
        return true
    end
})
local groundIdle = copy(base, {
    preflight = true,
    parking_brake_released = true
})
groundEngine:update(groundIdle, 0)

local pushing = copy(groundIdle, {
    wheel_speed = -3,
    ground_speed_kts = 2
})
groundEngine:update(pushing, 1)
groundEngine:update(pushing, 2.9)
assert_equal(#groundEvents, 0, "pushback waits for stable reverse movement")
groundEngine:update(pushing, 3)
assert_equal(#groundEvents, 1, "pushback emitted after stable reverse movement")
assert_equal(groundEvents[1].id, "departure.start_push", "pushback event id")

local taxiingWithoutProcedure = copy(groundIdle, {
    wheel_speed = 6,
    ground_speed_kts = 6
})
groundEngine:update(taxiingWithoutProcedure, 4)
groundEngine:update(taxiingWithoutProcedure, 8)
assert_equal(#groundEvents, 1, "taxi requires Before Taxi start latch")

local taxiing = copy(taxiingWithoutProcedure, { before_taxi_started = true })
groundEngine:update(taxiing, 9)
groundEngine:update(taxiing, 11.9)
assert_equal(#groundEvents, 1, "taxi waits for stable forward movement")
groundEngine:update(taxiing, 12)
assert_equal(#groundEvents, 2, "taxi emitted while Before Taxi may still be running")
assert_equal(groundEvents[2].id, "departure.taxi_runway", "taxi event id")

local takeoffOffRunway = copy(taxiing, {
    before_takeoff_started = true,
    wheel_speed = 20,
    ground_speed_kts = 20,
    eng1_n1_percent = 50,
    eng2_n1_percent = 50
})
groundEngine:update(takeoffOffRunway, 13)
groundEngine:update(takeoffOffRunway, 15)
assert_equal(#groundEvents, 2, "takeoff requires departure runway helper")

local takeoffLowN1 = copy(takeoffOffRunway, {
    on_departure_runway = true,
    eng1_n1_percent = 39,
    eng2_n1_percent = 50
})
groundEngine:update(takeoffLowN1, 16)
groundEngine:update(takeoffLowN1, 18)
assert_equal(#groundEvents, 2, "takeoff requires both engines above forty percent N1")

local takeoffRoll = copy(takeoffOffRunway, { on_departure_runway = true })
groundEngine:update(takeoffRoll, 19)
groundEngine:update(takeoffRoll, 20)
assert_equal(#groundEvents, 3, "takeoff emitted after stable roll")
assert_equal(groundEvents[3].id, "departure.lineup_takeoff", "takeoff event id")

local groundReloadEvents = {}
local groundReloadEngine = core.newEventEngine({
    emit = function(event) table.insert(groundReloadEvents, event) return true end
})
groundReloadEngine:update(taxiing, 0)
groundReloadEngine:update(taxiing, 10)
assert_equal(#groundReloadEvents, 0, "taxi reload baseline emits no departure backfill")

local takeoffReloadEvents = {}
local takeoffReloadEngine = core.newEventEngine({
    emit = function(event) table.insert(takeoffReloadEvents, event) return true end
})
takeoffReloadEngine:update(takeoffRoll, 0)
takeoffReloadEngine:update(takeoffRoll, 10)
assert_equal(#takeoffReloadEvents, 0, "takeoff reload baseline emits no departure backfill")

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
    fms_phase = 1,
    radio_altitude_ft = 9200,
    altitude_ft = 9500,
    pressure_altitude_ft = 9500,
    vertical_speed_fpm = 1200,
    ground_speed_kts = 250
}), 15)
engine:update(copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 1,
    radio_altitude_ft = 9700,
    altitude_ft = 10000,
    pressure_altitude_ft = 10000,
    vertical_speed_fpm = 1200,
    ground_speed_kts = 250
}), 16)
assert_equal(#emitted, 3, "climb FL100 crossing emitted once")
assert_equal(emitted[3].text, phraseCases[12][3], "climb crossing freezes FL100 phrase")
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
    "departure.climb_level_10000",
    "arrival.top_of_descent",
    "arrival.approach",
    "arrival.on_final",
    "arrival.runway_vacated"
}
assert_equal(#emitted, #expectedEvents, "normal event count")
for index, id in ipairs(expectedEvents) do
    assert_equal(emitted[index].id, id, "normal event order " .. tostring(index))
end

local climbReloadEvents = {}
local climbReloadEngine = core.newEventEngine({
    emit = function(event) table.insert(climbReloadEvents, event) return true end
})
local loadedAboveClimbLevel = copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 1,
    radio_altitude_ft = 10200,
    altitude_ft = 10500,
    pressure_altitude_ft = 10500,
    vertical_speed_fpm = 1000
})
climbReloadEngine:update(loadedAboveClimbLevel, 0)
climbReloadEngine:update(copy(loadedAboveClimbLevel, {
    altitude_ft = 11000,
    pressure_altitude_ft = 11000
}), 10)
assert_equal(#climbReloadEvents, 0, "reload above FL100 emits no climb backfill")

local climbFlightLoadEvents = {}
local climbFlightLoadEngine = core.newEventEngine({
    emit = function(event) table.insert(climbFlightLoadEvents, event) return true end
})
local climbFlightLoadBase = copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 1,
    radio_altitude_ft = 8700,
    altitude_ft = 9000,
    pressure_altitude_ft = 9000,
    vertical_speed_fpm = 1000
})
climbFlightLoadEngine:update(climbFlightLoadBase, 0)
climbFlightLoadEngine:update(climbFlightLoadBase, 8)
climbFlightLoadEngine:update(copy(climbFlightLoadBase, {
    altitude_ft = 12000,
    pressure_altitude_ft = 12000
}), 9)
climbFlightLoadEngine:update(copy(climbFlightLoadBase, {
    altitude_ft = 9900,
    pressure_altitude_ft = 9900,
    vertical_speed_fpm = -800
}), 10)
climbFlightLoadEngine:update(copy(climbFlightLoadBase, {
    altitude_ft = 10000,
    pressure_altitude_ft = 10000,
    vertical_speed_fpm = 1000
}), 11)
assert_equal(#climbFlightLoadEvents, 0, "flight-load altitude jump produces no FL100 climb report")

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

local descentProgressEvents = {}
local descentProgressEngine = core.newEventEngine({
    emit = function(event)
        table.insert(descentProgressEvents, event)
        return true
    end
})
local descentProgressBase = copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 2,
    altitude_ft = 41000,
    pressure_altitude_ft = 41000,
    planned_altitude_ft = 41000,
    vertical_speed_fpm = 0,
    tod_distance_nm = 10
})
descentProgressEngine:update(descentProgressBase, 0)
descentProgressEngine:update(copy(descentProgressBase, { tod_distance_nm = 2 }), 1)
descentProgressEngine:update(copy(descentProgressBase, {
    fms_phase = 5,
    altitude_ft = 40900,
    pressure_altitude_ft = 40900,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), 2)
descentProgressEngine:update(copy(descentProgressBase, {
    fms_phase = 5,
    altitude_ft = 40500,
    pressure_altitude_ft = 40500,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), 10)
assert_equal(#descentProgressEvents, 1, "TOD anchors descent progress reports")
assert_equal(descentProgressEvents[1].id, "arrival.top_of_descent", "descent progress TOD event")

local descentNow = 10
for altitude = 40000, 30000, -1000 do
    descentNow = descentNow + 1
    descentProgressEngine:update(copy(descentProgressBase, {
        fms_phase = 5,
        altitude_ft = altitude,
        pressure_altitude_ft = altitude,
        vertical_speed_fpm = -1000,
        tod_distance_nm = 0
    }), descentNow)
end
assert_equal(#descentProgressEvents, 2, "FL400 suppressed and FL300 emitted")
assert_equal(descentProgressEvents[2].id, "arrival.descent_level_30000", "FL300 event id")
assert_equal(descentProgressEvents[2].text, phraseCases[11][3], "FL300 frozen crossing phrase")

for altitude = 29000, 20000, -1000 do
    descentNow = descentNow + 1
    descentProgressEngine:update(copy(descentProgressBase, {
        fms_phase = 5,
        altitude_ft = altitude,
        pressure_altitude_ft = altitude,
        vertical_speed_fpm = -1000,
        tod_distance_nm = 0
    }), descentNow)
end
assert_equal(#descentProgressEvents, 3, "FL200 emitted once")
assert_equal(descentProgressEvents[3].id, "arrival.descent_level_20000", "FL200 event id")

for altitude = 19000, 11000, -1000 do
    descentNow = descentNow + 1
    descentProgressEngine:update(copy(descentProgressBase, {
        fms_phase = 5,
        altitude_ft = altitude,
        pressure_altitude_ft = altitude,
        vertical_speed_fpm = -1000,
        tod_distance_nm = 0
    }), descentNow)
end
descentNow = descentNow + 1
descentProgressEngine:update(copy(descentProgressBase, {
    fms_phase = 6,
    altitude_ft = 10500,
    pressure_altitude_ft = 10500,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), descentNow)
descentNow = descentNow + 8
descentProgressEngine:update(copy(descentProgressBase, {
    fms_phase = 6,
    altitude_ft = 9500,
    pressure_altitude_ft = 9500,
    vertical_speed_fpm = -1000,
    tod_distance_nm = 0
}), descentNow)
assert_equal(#descentProgressEvents, 4, "approach replaces FL100 progress report")
assert_equal(descentProgressEvents[4].id, "arrival.approach", "approach takeover event")

local descentReloadEvents = {}
local descentReloadEngine = core.newEventEngine({
    emit = function(event) table.insert(descentReloadEvents, event) return true end
})
local loadedInDescent = copy(descentProgressBase, {
    fms_phase = 5,
    altitude_ft = 30500,
    pressure_altitude_ft = 30500,
    vertical_speed_fpm = -800,
    tod_distance_nm = 0
})
descentReloadEngine:update(loadedInDescent, 0)
descentReloadEngine:update(copy(loadedInDescent, {
    altitude_ft = 30100,
    pressure_altitude_ft = 30100
}), 8)
descentReloadEngine:update(copy(loadedInDescent, {
    altitude_ft = 29900,
    pressure_altitude_ft = 29900
}), 9)
assert_equal(#descentReloadEvents, 0, "reload suppresses nearby FL300 report")
local reloadNow = 9
for altitude = 29000, 20000, -1000 do
    reloadNow = reloadNow + 1
    descentReloadEngine:update(copy(loadedInDescent, {
        altitude_ft = altitude,
        pressure_altitude_ft = altitude
    }), reloadNow)
end
assert_equal(#descentReloadEvents, 1, "reload baseline allows later separated boundary")
assert_equal(descentReloadEvents[1].id, "arrival.descent_level_20000", "reload later boundary event")

local flightLoadEvents = {}
local flightLoadEngine = core.newEventEngine({
    emit = function(event) table.insert(flightLoadEvents, event) return true end
})
local flightLoadBase = copy(descentProgressBase, {
    fms_phase = 4,
    altitude_ft = 35000,
    pressure_altitude_ft = 35000,
    vertical_speed_fpm = -800,
    tod_distance_nm = 20
})
flightLoadEngine:update(flightLoadBase, 0)
flightLoadEngine:update(flightLoadBase, 8)
flightLoadEngine:update(copy(flightLoadBase, {
    altitude_ft = 19000,
    pressure_altitude_ft = 19000
}), 9)
flightLoadEngine:update(copy(flightLoadBase, {
    altitude_ft = 31000,
    pressure_altitude_ft = 31000,
    vertical_speed_fpm = 1000
}), 10)
flightLoadEngine:update(copy(flightLoadBase, {
    altitude_ft = 29900,
    pressure_altitude_ft = 29900,
    vertical_speed_fpm = -800
}), 11)
assert_equal(#flightLoadEvents, 0, "flight-load altitude jump produces no progress report")

local reloadEvents = {}
local reloadEngine = core.newEventEngine({ emit = function(event) table.insert(reloadEvents, event) return true end })
local loadedOnFinal = copy(base, {
    on_ground = false,
    on_runway_profile = false,
    final_gate = true,
    fms_phase = 7,
    altitude_ft = 2000,
    pressure_altitude_ft = 2000,
    vertical_speed_fpm = -500,
    tod_distance_nm = 0
})
reloadEngine:update(loadedOnFinal, 0)
reloadEngine:update(loadedOnFinal, 20)
assert_equal(#reloadEvents, 0, "phase seven reload baseline emits nothing")

local armedApproachEvents = {}
local armedApproachEngine = core.newEventEngine({
    emit = function(event) table.insert(armedApproachEvents, event) return true end
})
local beforeArmedApproach = copy(base, {
    on_ground = false,
    on_runway_profile = false,
    fms_phase = 5,
    altitude_ft = 6000,
    pressure_altitude_ft = 6000,
    vertical_speed_fpm = -800,
    tod_distance_nm = 0
})
armedApproachEngine:update(beforeArmedApproach, 0)
local armedApproach = copy(beforeArmedApproach, { fms_phase = 7 })
armedApproachEngine:update(armedApproach, 1)
armedApproachEngine:update(armedApproach, 9)
assert_equal(#armedApproachEvents, 1, "go-around-armed phase emits approach")
assert_equal(armedApproachEvents[1].id, "arrival.approach", "phase seven approach event")
local armedFinal = copy(armedApproach, { final_gate = true })
armedApproachEngine:update(armedFinal, 10)
armedApproachEngine:update(armedFinal, 15)
assert_equal(#armedApproachEvents, 2, "go-around-armed phase emits final")
assert_equal(armedApproachEvents[2].id, "arrival.on_final", "phase seven final event")

local activeGoAroundEvents = {}
local activeGoAroundEngine = core.newEventEngine({
    emit = function(event) table.insert(activeGoAroundEvents, event) return true end
})
activeGoAroundEngine:update(beforeArmedApproach, 0)
local activeGoAround = copy(beforeArmedApproach, { fms_phase = 8, final_gate = true })
activeGoAroundEngine:update(activeGoAround, 1)
activeGoAroundEngine:update(activeGoAround, 10)
assert_equal(#activeGoAroundEvents, 0, "active go-around emits no approach or final")

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

print("auto_unicom tests passed")
