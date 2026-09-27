package.path = "data/modules/Custom Module/?.lua;" .. package.path

sasl = {
    getOS = function() return "Linux" end,
    getProjectName = function() return "YAL" end,
    getXPlanePath = function() return "/tmp/X-Plane" end,
    getProjectPath = function() return "/tmp/YAL" end,
    gl = { loadFont = function() return 1 end }
}

local values = {}
function get(ref) return values[ref] end
function set(ref, value) values[ref] = value end

package.loaded.helpers = {
    formatcgvalue = function(value)
        local number = tonumber(value)
        if number and number > 0 then
            return tostring(number)
        end
        return nil
    end
}
package.loaded.refdata = {}

local def = require("definitions")

yal = {
    toflaps = "toflaps",
    fmccg = "fmccg",
    v1setspeed = "v1setspeed",
    vrsetspeed = "vrsetspeed",
    v2setspeed = "v2setspeed",
    airgroundsensor = "airgroundsensor",
    groundspeed = "groundspeed",
    onDepartureRunway = false,
    aircraftonrwy = function(runwayType, distMeters, headingLimit)
        assert(runwayType == def.DEPARTURE, "takeoff-roll transition must use departure runway")
        assert(distMeters == 40, "takeoff-roll transition runway distance")
        assert(headingLimit == 20, "takeoff-roll transition heading limit")
        return yal.onDepartureRunway
    end,
    loopStateTables = {
        [1] = { lock = def.BEFORETAXIPROCEDURE },
        [2] = { lock = def.NOPROCEDURE },
        [3] = { lock = def.NOPROCEDURE }
    },
    configvalues = {},
    triggerChildProcedure = function(parentLoop, parentProc, childProc)
        yal.lastTrigger = { parentLoop, parentProc, childProc }
        yal.loopStateTables[3].lock = childProc
        return true
    end
}

local proceduredata = require("proceduredata")
assert(proceduredata.fillProcedureTable())

local beforeTaxi = yal.proceduretable[def.BEFORETAXIPROCEDURE]
local beforeTakeoff = yal.proceduretable[def.BEFORETAKEOFFPROCEDURE]
local ensure = beforeTaxi.steps.ensure_takeoff_data
local loop = {}

local function assertTakeoffRollTransitions(proc, label)
    assert(#proc.transitionConditions == 2, label .. " transition count")

    values.airgroundsensor = def.ON
    values.groundspeed = 46
    yal.onDepartureRunway = false
    assert(proc.transitionConditions[1].condition() == false, label .. " remains ground-active")
    assert(proc.transitionConditions[2].condition() == false, label .. " must not transition on taxiway")

    yal.onDepartureRunway = true
    assert(proc.transitionConditions[2].condition() == true, label .. " transitions on departure runway takeoff roll")

    values.airgroundsensor = def.OFF
    values.groundspeed = 0
    yal.onDepartureRunway = false
    assert(proc.transitionConditions[1].condition() == true, label .. " terminates airborne")
end

assertTakeoffRollTransitions(beforeTaxi, "Before Taxi")
assertTakeoffRollTransitions(beforeTakeoff, "Before Takeoff")

values.toflaps = 5
values.fmccg = 24.5
values.v1setspeed = 130
values.vrsetspeed = 135
values.v2setspeed = 140

assert(ensure.check(loop) == true, "complete takeoff data should pass silently")
assert(ensure.branch(loop) == "ensure_departure_nav", "complete data should continue to Departure NAV")
assert(yal.lastTrigger == nil, "complete takeoff data must not trigger the child")

values.v2setspeed = 0
assert(ensure.check(loop) == false, "missing V2 should require the child")
assert(ensure.branch(loop) == false, "missing data should remain on the guard step")

ensure.action(loop, beforeTaxi)
assert(loop.takeoffDataChildPending == true, "Before Taxi should wait for the child")
assert(yal.lastTrigger[1] == 1, "Before Taxi parent loop")
assert(yal.lastTrigger[2] == def.BEFORETAXIPROCEDURE, "Before Taxi parent procedure")
assert(yal.lastTrigger[3] == def.SETTOFLAPSPROCEDURE, "Set Takeoff Flaps child")
assert(ensure.check(loop) == false, "running child must keep Before Taxi waiting")
assert(ensure.branch(loop) == false, "running child must not advance Before Taxi")

yal.proceduretable[def.SETTOFLAPSPROCEDURE].set = true
yal.loopStateTables[3].lock = def.NOPROCEDURE
assert(ensure.check(loop) == true, "completed child should release Before Taxi")
assert(ensure.branch(loop) == "ensure_departure_nav", "completed child should continue to Departure NAV")
assert(loop.takeoffDataChildPending == nil, "child wait latch should clear")
assert(
    yal.proceduretable[def.SETTOFLAPSPROCEDURE].prerequisite() == true,
    "Set Takeoff Flaps should be allowed while Before Taxi is active"
)

print("test_before_taxi_takeoff_data: all checks passed")
