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
    addspaces = function(value) return tostring(value):gsub(".", "%0 "):sub(1, -2) end,
    formatQnhValue = function(value) return tostring(value) end,
    formatcgvalue = function(value) return tostring(value) end,
    padNumberWithZerosStrict = function(value) return tostring(value) end
}
package.loaded.refdata = {}

local def = require("definitions")

local queued = {}
local standardSet = false
local standardCommands = 0
local localQnhSet = false
local localQnhCommands = 0
yal = {
    fmctransalt = "fmctransalt",
    fmctranslvl = "fmctranslvl",
    fmccruisealt = "fmccruisealt",
    altitude = "altitude",
    verticalspeed = "verticalspeed",
    baroinhpa = "baroinhpa",
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
    end,
    getlocalqnh = function() return 29.92, 1013 end,
    isbarolocalqnhset = function() return localQnhSet end,
    setbarolocalinhg = function()
        localQnhCommands = localQnhCommands + 1
        localQnhSet = true
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

do
    local loop = {}
    assertFalse(proceduredata.isDescendingThroughTransition(loop, 6000, 5999, 0),
        "level-hold jitter below TL")
    assertFalse(proceduredata.isDescendingThroughTransition(loop, 6000, 5901, -500),
        "margin blocks nominal TL capture")
    assertFalse(proceduredata.isDescendingThroughTransition(loop, 6000, 5899, 0),
        "level aircraft below margin does not trigger")
    assertTrue(proceduredata.isDescendingThroughTransition(loop, 6000, 5899, -500),
        "resumed descent clears TL")
end

do
    local loop = {}
    assertFalse(proceduredata.isDescendingThroughTransition(loop, 6000, 6100, -1500),
        "continuous descent remains above TL")
    assertTrue(proceduredata.isDescendingThroughTransition(loop, 6000, 5880, -1500),
        "continuous descent crosses TL")
end

assertTrue(proceduredata.isDescendingThroughTransition({}, 6000, 3000, 0),
    "inflight restore already below TL")
assertFalse(proceduredata.isDescendingThroughTransition({}, 0, 3000, -1000),
    "invalid transition level")

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
assertEqual(step.ensureConfirmInAdviceMode, nil, "manual STD compliance suppresses follow-up confirmation")

step.action()
assertEqual(standardCommands, 1, "same-cycle automatic STD action")
assertTrue(step.check(loop), "STD completes transition step")
assertEqual(#queued, 1, "crossing announcement remains one-shot")
assertEqual(step.confirm(), "Q N H checked Standard", "STD confirmation")

local descentStep = yal.proceduretable[def.DURINGDESCENTPROCEDURE].steps.wait_for_transition
local descentLoop = {}
local queuedBeforeDescent = #queued
values.fmctranslvl = 6000
values.altitude = 5999
values.verticalspeed = 0
values.baroinhpa = def.ON

assertFalse(descentStep.check(descentLoop), "descent procedure remains waiting at TL")
assertEqual(descentStep.branch(descentLoop), "wait_for_transition", "descent waiting branch suppresses advice and action")
assertEqual(#queued, queuedBeforeDescent, "no transition-level speech while level at TL")

values.altitude = 5880
values.verticalspeed = -800
assertFalse(descentStep.check(descentLoop), "accepted descent crossing waits for local QNH")
assertEqual(descentStep.branch(descentLoop), false, "accepted descent crossing enables immediate action or advice")
assertEqual(#queued, queuedBeforeDescent + 1, "transition-level announcement queued once")
assertEqual(queued[#queued][2], "Passing Transition Level", "transition-level announcement text")
assertEqual(descentStep.advice(), "Set Q N H 1 0 1 3", "same-cycle local QNH advice")
assertEqual(descentStep.ensureConfirmInAdviceMode, nil, "manual local QNH compliance suppresses follow-up confirmation")

descentStep.action()
assertEqual(localQnhCommands, 1, "same-cycle automatic local QNH action")
assertTrue(descentStep.check(descentLoop), "local QNH completes descent transition step")
assertEqual(#queued, queuedBeforeDescent + 1, "transition-level announcement remains one-shot")
assertEqual(descentStep.confirm(), "Q N H checked and 1 0 1 3", "local QNH confirmation")

print("test_transition_altitude: all checks passed")
