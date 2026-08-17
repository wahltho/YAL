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
    formatcgvalue = function(value) return tostring(value) end,
    padNumberWithZerosStrict = function(value) return tostring(value) end
}
package.loaded.refdata = {}

local def = require("definitions")

local queued = {}
local standardSet = false
local standardCommands = 0
yal = {
    fmctransalt = "fmctransalt",
    fmccruisealt = "fmccruisealt",
    altitude = "altitude",
    verticalspeed = "verticalspeed",
    configvalues = {
        [def.CONFIGAUTOBARO] = def.ON
    },
    commandtableentry = function(kind, text)
        queued[#queued + 1] = { kind, text }
    end,
    isbarostandardset = function() return standardSet end,
    setbarostandard = function()
        standardCommands = standardCommands + 1
        standardSet = true
    end
}

local proceduredata = require("proceduredata")

local function assertEqual(actual, expected, label)
    assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function assertFalse(value, label)
    assertEqual(value, false, label)
end

local function assertTrue(value, label)
    assertEqual(value, true, label)
end

do
    local loop = {}
    assertFalse(proceduredata.isClimbingThroughTransition(loop, 6000, 6001, 0),
        "level-hold jitter above TA")
    assertFalse(proceduredata.isClimbingThroughTransition(loop, 6000, 6099, 500),
        "margin blocks nominal TA capture")
    assertFalse(proceduredata.isClimbingThroughTransition(loop, 6000, 6101, 0),
        "level aircraft above margin does not trigger")
    assertTrue(proceduredata.isClimbingThroughTransition(loop, 6000, 6101, 500),
        "resumed climb clears TA")
end

do
    local loop = {}
    assertFalse(proceduredata.isClimbingThroughTransition(loop, 6000, 5900, 1500),
        "continuous climb remains below TA")
    assertTrue(proceduredata.isClimbingThroughTransition(loop, 6000, 6120, 1500),
        "continuous climb crosses TA")
end

assertTrue(proceduredata.isClimbingThroughTransition({}, 6000, 12000, 0),
    "inflight restore already above TA")
assertFalse(proceduredata.isClimbingThroughTransition({}, 0, 12000, 1000),
    "invalid transition altitude")

assert(proceduredata.fillProcedureTable())
local step = yal.proceduretable[def.DURINGCLIMBPROCEDURE].steps.wait_for_transition
local loop = {}
values.fmctransalt = 6000
values.fmccruisealt = 40000
values.altitude = 6001
values.verticalspeed = 0

assertFalse(step.check(loop), "procedure remains waiting at TA")
assertEqual(step.branch(loop), "wait_for_transition", "waiting branch suppresses advice and action")
assertEqual(#queued, 0, "no transition speech while level at TA")

values.altitude = 6120
values.verticalspeed = 800
assertFalse(step.check(loop), "accepted crossing waits for STD")
assertEqual(step.branch(loop), false, "accepted crossing enables immediate action or advice")
assertEqual(#queued, 1, "crossing announcement queued once")
assertEqual(queued[1][2], "Passing Transition Altitude", "crossing announcement text")
assertEqual(step.advice, "Set Q N H to Standard", "same-cycle advice text")

step.action()
assertEqual(standardCommands, 1, "same-cycle automatic STD action")
assertTrue(step.check(loop), "STD completes transition step")
assertEqual(#queued, 1, "crossing announcement remains one-shot")
assertEqual(step.confirm(), "Q N H checked Standard", "STD confirmation")

print("test_transition_altitude: all checks passed")
