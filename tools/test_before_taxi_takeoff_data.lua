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
assert(ensure.branch(loop) == "recheck_mcp_altitude", "complete data should continue to MCP recheck")
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
assert(ensure.branch(loop) == "recheck_mcp_altitude", "completed child should continue to MCP recheck")
assert(loop.takeoffDataChildPending == nil, "child wait latch should clear")
assert(
    yal.proceduretable[def.SETTOFLAPSPROCEDURE].prerequisite() == true,
    "Set Takeoff Flaps should be allowed while Before Taxi is active"
)

local recheck = beforeTaxi.steps.recheck_mcp_altitude
local init = yal.proceduretable[def.COCKPITINITPROCEDURE].steps.set_mcp_altitude
assert(not recheck.check and recheck.nextStep == "ensure_departure_nav", "non-blocking in both modes")
yal.mcpaltitude, yal.fmccruisealt, yal.departureMcpAltitudeReviewedDr = "mcp", "cruise", "reviewed"
yal.configvalues[def.CONFIGLOWEAIRSPACEALT] = 10000
yal.procedureSpeechKey = function(proc, step, role)
    assert(proc == def.BEFORETAXIPROCEDURE and step == "recheck_mcp_altitude" and role == "step")
    return "test-key"
end
local messages = {}
yal.commandtableentry = function(state, message, key)
    assert(state == def.TEXT and key == "test-key")
    messages[#messages+1] = message
end
for _, advice in ipairs({ def.OFF, def.ON }) do
    yal.configvalues[def.CONFIGVOICEADVICEONLY] = advice
    messages = {}
    values.mcp, values.cruise, values.reviewed = 5000, 8000, 0
    assert(not init.check() and init.branch() == false and values.reviewed == 0)
    recheck.action()
    assert(values.mcp == 5000 and messages[1] == "Verify initial climb altitude. M C P set to 5000 feet")
    recheck.action()
    assert(#messages == 1 and values.reviewed == 1, "only one reminder per flight")
    values.mcp, values.reviewed = 8000, 0
    recheck.action()
    assert(#messages == 1 and values.reviewed == 1, "correct lower FMC cruise target is silent")
    values.cruise, values.reviewed = 0, 0
    init.action()
    assert(values.mcp == 10000 and values.reviewed == 0, "auto write alone is not a passed check")
    assert(init.check() and init.branch() == "set_bank_angle" and values.reviewed == 1)
    values.mcp = 4500
    recheck.action()
    assert(values.mcp == 4500 and #messages == 1, "later clearance is left alone after successful init")

    for _, case in ipairs({
        {mcp=39000, cruise=39000}, {mcp=10000, cruise=39000}, {mcp=10000, cruise=8000},
        {mcp=10000, cruise=0}, {mcp=10000}, {mcp=0, cruise=0, warn=true}, {mcp=5000, warn=true}
    }) do
        values.mcp, values.cruise, values.reviewed = case.mcp, case.cruise, 0
        messages = {}
        recheck.action()
        recheck.action()
        assert(#messages == (case.warn and 1 or 0), "unexpected Before Taxi advice for MCP "
            .. case.mcp .. " / cruise " .. tostring(case.cruise))
        assert(values.mcp == case.mcp and values.reviewed == 1)
    end
end

print("test_before_taxi_takeoff_data: all checks passed")
