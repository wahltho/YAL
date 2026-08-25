package.path = "data/modules/Custom Module/?.lua;" .. package.path

sasl = {
    getOS = function() return "Linux" end,
    getProjectName = function() return "YAL" end,
    getXPlanePath = function() return "/tmp/X-Plane" end,
    getProjectPath = function() return "/tmp/YAL" end,
    getXPVersion = function() return 12000 end,
    gl = { loadFont = function() return 1 end }
}

package.preload.ffi = function()
    return {
        os = "OSX",
        load = function() return {} end,
        cdef = function() end
    }
end

NO_PLUGIN_ID = -1
function globalProperty(name) return name end

local values = {}
function get(ref) return values[ref] end
function set(ref, value) values[ref] = value end

local def = require("definitions")
local realRefdata = require("refdata")
local realHelpers = require("helpers")

local function findUpvalue(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    for index = 1, 100 do
        local name, value = debug.getupvalue(fn, index)
        if not name then break end
        if name == wanted then return value end
        if type(value) == "function" then
            local nested = findUpvalue(value, wanted, seen)
            if nested then return nested end
        end
    end
    return nil
end

local function copy(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

local lgskQ01 = {
    api_version = 2,
    update_seq = 2,
    selected = true,
    nav_valid = false,
    course_valid = true,
    procedure_id = "Q01",
    procedure_type = "NDB",
    resolved_nav_kind = "",
    airport = "LGSK",
    runway = "01",
    nav_ident = "",
    frequency_raw = 0,
    frequency_mhz = 0,
    channel = 0,
    course_deg = 7,
    course_reference = "MAG",
    has_dme = false,
    dme_ident = "",
    dme_frequency_raw = 0,
    support_nav_valid = true,
    support_nav_ident = "SKC",
    support_nav_kind = "NDB",
    support_nav_role = "support_nav",
    support_nav_frequency_raw = 326
}

local validate = findUpvalue(realRefdata.getApproachRefForContext, "approachRefSnapshotValid")
local toNavEntry = findUpvalue(realRefdata.getApproachRefForContext, "approachRefToNavEntry")
local readSnapshot = findUpvalue(realRefdata.getApproachRefForContext, "readApproachRefSnapshot")
assert(type(validate) == "function", "Approach-Ref validator must remain reachable for regression tests")
assert(type(toNavEntry) == "function", "Approach-Ref nav-entry adapter must remain reachable for regression tests")
assert(type(readSnapshot) == "function", "Approach-Ref atomic reader must remain reachable for regression tests")

local snapshot = copy(lgskQ01)
local valid, reason = validate(snapshot)
assert(valid == true and reason == nil, "API v2 LGSK Q01 must be accepted")
assert(snapshot.course_only_non_precision == true, "Q01 must be classified as course-only non-precision")
assert(snapshot.nav_type == nil, "course-only NDB must not fabricate a primary NAV type")
assert(toNavEntry(snapshot) == nil, "course-only NDB must not fabricate a primary NAV entry")

local v1Snapshot = copy(lgskQ01)
v1Snapshot.api_version = 1
valid, reason = validate(v1Snapshot)
assert(valid == false and reason == "procedure_type_version", "new NDB semantics require Approach-Ref API v2")

for _, procedureType in ipairs({ "VOR", "VDM" }) do
    local fixture = copy(lgskQ01)
    fixture.procedure_id = procedureType == "VOR" and "V01" or "D01"
    fixture.procedure_type = procedureType
    fixture.support_nav_kind = procedureType == "VOR" and "VOR" or "VOR/DME"
    fixture.support_nav_frequency_raw = 11320
    valid, reason = validate(fixture)
    assert(valid == true and reason == nil, procedureType .. " course-only snapshot must be accepted in API v2")
    assert(realRefdata.isApproachRefCourseOnlyNonPrecision(fixture), procedureType .. " must use course-only policy")
end

local v1Rnav = copy(lgskQ01)
v1Rnav.api_version = 1
v1Rnav.procedure_id = "R25-P"
v1Rnav.procedure_type = "RNAV"
v1Rnav.runway = "25"
v1Rnav.course_deg = 251
v1Rnav.support_nav_valid = false
v1Rnav.support_nav_ident = ""
v1Rnav.support_nav_kind = ""
v1Rnav.support_nav_role = ""
v1Rnav.support_nav_frequency_raw = 0
valid, reason = validate(v1Rnav)
assert(valid == true and reason == nil, "existing API v1 RNAV negative-primary snapshot must remain valid")
assert(v1Rnav.nav_type == def.NAVTYPERNAV, "existing API v1 RNAV mapping must remain unchanged")

local ekvgR12W = copy(v1Rnav)
ekvgR12W.api_version = 3
ekvgR12W.procedure_id = "R12-W"
ekvgR12W.airport = "EKVG"
ekvgR12W.runway = "12"
ekvgR12W.course_deg = 122
ekvgR12W.procedure_class_valid = true
ekvgR12W.rnp_ar = true
ekvgR12W.ian_eligible = false
valid, reason = validate(ekvgR12W)
assert(valid == true and reason == nil, "API v3 EKVG R12-W RNP AR snapshot must be accepted")
assert(ekvgR12W.nav_type == def.NAVTYPERNAV, "RNP AR remains an RNAV navigation type")

local v3Refs = {}
for field, value in pairs(ekvgR12W) do
    if field ~= "nav_type" and field ~= "course_only_non_precision" then
        local ref = "approach_ref/" .. field
        v3Refs[field] = ref
        if type(value) == "boolean" then
            values[ref] = value and 1 or 0
        else
            values[ref] = value
        end
    end
end
local atomicV3, readReason = readSnapshot(v3Refs)
assert(readReason == nil and atomicV3 ~= nil, "API v3 snapshot must be read atomically")
assert(atomicV3.procedure_class_valid == true and atomicV3.rnp_ar == true
        and atomicV3.ian_eligible == false,
    "API v3 classification fields must be part of the atomic snapshot")

local ensbR09Z = copy(ekvgR12W)
ensbR09Z.procedure_id = "R09-Z"
ensbR09Z.airport = "ENSB"
ensbR09Z.runway = "09"
ensbR09Z.course_deg = 95
ensbR09Z.rnp_ar = false
ensbR09Z.ian_eligible = true
valid, reason = validate(ensbR09Z)
assert(valid == true and reason == nil, "API v3 ENSB R09-Z IAN-eligible snapshot must be accepted")

local invalidClass = copy(ekvgR12W)
invalidClass.procedure_class_valid = false
valid, reason = validate(invalidClass)
assert(valid == false and reason == "nonempty_invalid_procedure_class",
    "classification fields must be zero when their validity flag is false")

local conflictingClass = copy(ekvgR12W)
conflictingClass.ian_eligible = true
valid, reason = validate(conflictingClass)
assert(valid == false and reason == "procedure_class_conflict",
    "RNP AR must never be published as IAN-eligible")

local guidanceInput = {
    navType = def.NAVTYPERNAV,
    selectedNavType = def.NAVTYPERNAV,
    mmrInstalled = true,
    lpvInstalled = true,
    ianInfo = 1,
    facCourse = 122,
    facTrack = 122,
    isLateralOnly = false
}

local legacyGuidance = realHelpers.resolveApproachGuidanceCapabilities(copy(guidanceInput))
assert(legacyGuidance.facGpPossible == true, "API v1/v2 guidance heuristic must remain unchanged")
assert(legacyGuidance.guidanceSummary == "Expected F A C / G P guidance",
    "legacy RNAV guidance summary must remain unchanged")

local rnpArGuidanceInput = copy(guidanceInput)
rnpArGuidanceInput.procedureClassValid = true
rnpArGuidanceInput.rnpAr = true
rnpArGuidanceInput.ianEligible = false
local rnpArGuidance = realHelpers.resolveApproachGuidanceCapabilities(rnpArGuidanceInput)
assert(rnpArGuidance.facPossible == false and rnpArGuidance.gpPossible == false,
    "RNP AR classification must override runtime FAC indicators")
assert(rnpArGuidance.expectedLateralMode == "LNAV" and rnpArGuidance.expectedVerticalMode == "VNAV",
    "RNP AR must retain LNAV/VNAV")
assert(rnpArGuidance.guidanceSummary == "Expected L N A V / V N A V guidance",
    "RNP AR guidance announcement must be LNAV/VNAV")

local ianGuidanceInput = copy(guidanceInput)
ianGuidanceInput.procedureClassValid = true
ianGuidanceInput.rnpAr = false
ianGuidanceInput.ianEligible = true
local ianGuidance = realHelpers.resolveApproachGuidanceCapabilities(ianGuidanceInput)
assert(ianGuidance.facGpPossible == true, "statically eligible RNAV must retain valid FAC/GP evidence")

local staticallyEligibleWithoutRuntime = copy(ianGuidanceInput)
staticallyEligibleWithoutRuntime.ianInfo = 0
staticallyEligibleWithoutRuntime.facCourse = 0
staticallyEligibleWithoutRuntime.facTrack = 0
local noRuntimeGuidance = realHelpers.resolveApproachGuidanceCapabilities(staticallyEligibleWithoutRuntime)
assert(noRuntimeGuidance.facPossible == false,
    "static IAN eligibility must not fabricate runtime FAC availability")

local function addSpaces(value)
    local text = tostring(value or "")
    local chars = {}
    for index = 1, #text do chars[#chars + 1] = text:sub(index, index) end
    return table.concat(chars, " ")
end

local messages = {}
local runwayFallbackCalls = 0
local activeApproachFixture = lgskQ01
local procedureRefdata = {
    getApproachRefForContext = function(context)
        assert(context.icao == activeApproachFixture.airport,
            "Set ILS must pass destination ICAO to Approach-Ref")
        assert(context.runway == activeApproachFixture.runway,
            "Set ILS must pass destination runway to Approach-Ref")
        assert(context.selectedAppId == activeApproachFixture.procedure_id,
            "Set ILS must preserve the raw selected-approach context")
        assert(context.requireCommitted == true, "Set ILS must retain the MOD/EXEC gate")
        return activeApproachFixture, nil, "accepted"
    end,
    isApproachRefCourseOnlyNonPrecision = realRefdata.isApproachRefCourseOnlyNonPrecision
}

package.loaded.helpers = {
    addspaces = addSpaces,
    calccourse = function(value) return value end,
    formatILSFrequency = function(value)
        error("NDB support frequency must not use the ILS formatter: " .. tostring(value))
    end,
    formatRunwayDesignator = addSpaces,
    headingdiff = function(a, b)
        local diff = math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) % 360
        return math.min(diff, 360 - diff)
    end,
    isvalidicao = function(value) return type(value) == "string" and #value == 4 end,
    loadCIFP = function() error("accepted Q01 must not search for an RNAV alternative") end,
    logDebugTS = function() end,
    logInfoTS = function() end,
    padNumberWithZerosStrict = function(value, length)
        return string.format("%0" .. tostring(length) .. "d", tonumber(value) or 0)
    end,
    parseSelectedApproachId = realHelpers.parseSelectedApproachId,
    resolveApproachGuidanceCapabilities = realHelpers.resolveApproachGuidanceCapabilities,
    spellNato = realHelpers.spellNato
}
package.loaded.refdata = procedureRefdata

yal = {
    approachRef = {},
    configvalues = {},
    desicao = "desicao",
    desrwy = "desrwy",
    fmsselectedapp = "fmsselectedapp",
    mcppilotcourse = "mcppilotcourse",
    mcpcopilotcourse = "mcpcopilotcourse",
    navdatatable = {},
    commandtableentry = function(_, message) messages[#messages + 1] = message end,
    getDestinationRunwayHeadingMag = function()
        runwayFallbackCalls = runwayFallbackCalls + 1
        return 14
    end
}
values.desicao = "LGSK"
values.desrwy = "01"
values.fmsselectedapp = "Q01"
values.mcppilotcourse = 14
values.mcpcopilotcourse = 14

package.loaded.proceduredata = nil
local proceduredata = require("proceduredata")
assert(proceduredata.fillProcedureTable())

local setIls = yal.proceduretable[def.SETILSPROCEDURE]
local loop = {}
assert(setIls.steps.find_navdata.branch(loop) == "announce_no_approach", "Q01 must use the accepted course-only flow")
assert(loop.approachRefAccepted == true, "Q01 Approach-Ref snapshot must remain accepted")
assert(loop.apiNavdata == nil, "Q01 must not create primary NAV data")

setIls.steps.announce_no_approach.action(loop)
setIls.steps.announce_heading_only.action(loop)
setIls.steps.announce_support_navaid_only.action(loop)
assert(messages[1] == "Runway 0 1 has N D B Approach", "Q01 procedure announcement")
assert(messages[2] == "Final approach course 0 0 7", "Q01 must announce the authoritative CIFP course")
assert(messages[3] == "Supporting N D B for Runway 0 1 is Sierra Kilo Charlie with frequency 3 2 6 kilohertz",
    "Q01 supporting NDB announcement")
assert(runwayFallbackCalls == 0, "accepted Q01 must never consult runway heading fallback")

assert(setIls.steps.finish_approach_course_only.branch(loop) == "view_main_panel",
    "course-only Q01 must continue to Captain Course")
assert(setIls.steps.set_capt_course.advice(loop) == "Set Captain Course 0 0 7", "Captain Course advice must use 007")
setIls.steps.set_capt_course.action(loop)
assert(values.mcppilotcourse == 7, "Captain Course must be set from the authoritative Q01 course")
assert(setIls.steps.set_fo_course.skipIf(loop) == true, "course-only Q01 must not manage the Copilot Course")
assert(values.mcpcopilotcourse == 14, "Copilot Course must remain untouched")
assert(runwayFallbackCalls == 0, "Q01 course lifecycle must remain independent of runway heading")

activeApproachFixture = ekvgR12W
values.desicao = "EKVG"
values.desrwy = "12"
values.fmsselectedapp = "R12-W"
values.mcppilotcourse = 122
values.mcpcopilotcourse = 122
messages = {}
loop = {}

assert(setIls.steps.find_navdata.branch(loop) == "announce_no_approach",
    "RNP AR without a primary target must use the accepted non-tunable flow")
setIls.steps.announce_no_approach.action(loop)
setIls.steps.announce_heading_only.action(loop)
assert(messages[1] == "R N P Authorization Required Whiskey Approach Runway 1 2. F M C guidance, no frequency or channel tuning required. Expected L N A V / V N A V guidance",
    "RNP AR announcement must identify the class and retain LNAV/VNAV")
assert(messages[2] == "Final approach course 1 2 2",
    "RNP AR may retain the authoritative final-course information")
assert(setIls.steps.finish_approach_course_only.branch(loop) == false,
    "RNP AR must not continue into Captain Course management")
assert(values.mcppilotcourse == 122 and values.mcpcopilotcourse == 122,
    "RNP AR must leave both Course selectors untouched")

print("test_approach_ref_v2: API v2/v3 checks passed")
