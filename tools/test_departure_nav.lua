package.path = "data/modules/Custom Module/?.lua;" .. package.path

sasl = {
    getOS = function() return "Linux" end,
    getProjectName = function() return "YAL" end,
    getXPlanePath = function() return "/tmp/X-Plane" end,
    getProjectPath = function() return "/tmp/YAL" end,
    readConfig = function() return {} end,
    writeConfig = function() return true end,
    logDebug = function() end,
    logWarning = function() end,
    gl = { loadFont = function() return 1 end }
}

local values = {}
function get(ref) return values[ref] end
function set(ref, value) values[ref] = value end

local def = require("definitions")
local settings = require("settings")
local departureNav = require("departure_nav")

assert(settings.appSettings[def.CONFIGDEPARTURENAVSETUP] == def.OFF, "Departure NAV Setup must default OFF")

local function sidLine(routeType, sid, transition, ident, region, section, course)
    local fields = {}
    for index = 1, 21 do fields[index] = "" end
    fields[1] = "SID:010"
    fields[2] = routeType
    fields[3] = sid
    fields[4] = transition
    fields[12] = "CF"
    fields[14] = ident or ""
    fields[15] = region or ""
    fields[16] = section or ""
    fields[21] = course or ""
    return table.concat(fields, ",")
end

local lookupCount = 0
local function lookup(ident, region)
    lookupCount = lookupCount + 1
    if ident == "ATA" and region == "EN" then
        return { type = 2, frequency = 11740, _source = "test" }
    end
    if ident == "ABC" and region == "EN" then
        return { type = 1, frequency = 11320, _source = "test" }
    end
    return nil
end

local base = {
    icao = "ENAT",
    runway = "11",
    sid = "ELSE1A",
    transition = "",
    legs = "ENAT RW11 ELSEV ATA",
    lookupNavaid = lookup
}

local conventional = {}
for key, value in pairs(base) do conventional[key] = value end
conventional.cifpLines = {
    sidLine("2", "ELSE1A", "RW11", "", "", "", "1090"),
    sidLine("2", "ELSE1A", "RW11", "ATA", "EN", "D", "3100")
}
local plan = departureNav.resolve(conventional)
assert(plan.status == "actionable", "one explicit conventional assignment should be actionable")
assert(plan.captain.ident == "ATA", "resolved VOR ident")
assert(plan.captain.frequency == 11740, "resolved VOR frequency")
assert(plan.captain.course == 310, "resolved magnetic course")

lookupCount = 0
local rnav = {}
for key, value in pairs(base) do rnav[key] = value end
rnav.sid = "KOMI1A"
rnav.cifpLines = { sidLine("5", "KOMI1A", "RW11", "ATA", "EN", "D", "1090") }
plan = departureNav.resolve(rnav)
assert(plan.status == "rnav", "RNAV SID must remain silent")
assert(lookupCount == 0, "RNAV SID must not resolve or tune a recommended navaid")

local ambiguous = {}
for key, value in pairs(base) do ambiguous[key] = value end
ambiguous.cifpLines = {
    sidLine("2", "ELSE1A", "RW11", "ATA", "EN", "D", "3100"),
    sidLine("2", "ELSE1A", "RW11", "ABC", "EN", "D", "2700")
}
plan = departureNav.resolve(ambiguous)
assert(plan.status == "ambiguous_raw_data", "multiple assignments must not be guessed")

local wrongRunway = {}
for key, value in pairs(base) do wrongRunway[key] = value end
wrongRunway.cifpLines = { sidLine("2", "ELSE1A", "RW29", "ATA", "EN", "D", "3100") }
plan = departureNav.resolve(wrongRunway)
assert(plan.status == "no_explicit_raw_data", "wrong-runway records must be ignored")

local transitionSpecific = {}
for key, value in pairs(base) do transitionSpecific[key] = value end
transitionSpecific.transition = "ELSEV"
transitionSpecific.cifpLines = { sidLine("3", "ELSE1A", "ELSEV", "ATA", "EN", "D", "3100") }
plan = departureNav.resolve(transitionSpecific)
assert(plan.status == "actionable", "an explicit matching enroute transition may be used")

local withoutTransition = {}
for key, value in pairs(transitionSpecific) do withoutTransition[key] = value end
withoutTransition.transition = ""
plan = departureNav.resolve(withoutTransition)
assert(plan.status == "no_explicit_raw_data", "transition records must not be inferred")

local signature = departureNav.contextSignature(base)
local changedRunway = {}
for key, value in pairs(base) do changedRunway[key] = value end
changedRunway.runway = "29"
assert(departureNav.contextSignature(changedRunway) ~= signature, "runway change must invalidate context")
local changedLegs = {}
for key, value in pairs(base) do changedLegs[key] = value end
changedLegs.legs = "ENAT RW11 ELSEV ATA NEWFIX"
assert(departureNav.contextSignature(changedLegs) ~= signature, "route/transition change must invalidate context")

assert(departureNav.shouldRetryAtBeforeTaxi("no_selection") == true, "missing Cockpit Init selection must retry Before Taxi")
assert(departureNav.shouldRetryAtBeforeTaxi("data_unavailable") == true, "temporarily unavailable data must retry Before Taxi")
assert(departureNav.shouldRetryAtBeforeTaxi("sid_not_found") == true, "an unresolved SID must retry Before Taxi")
assert(departureNav.shouldRetryAtBeforeTaxi("no_explicit_raw_data") == true, "incomplete raw-data resolution must retry Before Taxi")
assert(departureNav.shouldRetryAtBeforeTaxi("rnav") == false, "an authoritative RNAV no-action result must be final")
assert(departureNav.shouldRetryAtBeforeTaxi("ambiguous_raw_data") == false, "an authoritative ambiguous result must remain silent")

package.loaded.helpers = {
    formatcgvalue = function() return nil end
}
package.loaded.refdata = {}
local resolvedPlan = { status = "actionable", signature = "sig-a", captain = {} }
yal = {
    configvalues = { [def.CONFIGDEPARTURENAVSETUP] = def.OFF },
    loopStateTables = {
        [1] = { lock = def.COCKPITINITPROCEDURE },
        [2] = { lock = def.NOPROCEDURE },
        [3] = { lock = def.NOPROCEDURE }
    },
    getDepartureNavSignature = function() return "sig-a" end,
    triggerChildProcedure = function(parentLoop, parentProc, childProc)
        yal.triggeredChild = { parentLoop, parentProc, childProc }
        yal.loopStateTables[3].lock = childProc
        return true
    end,
    saveLoopState = function() end,
    resolveDepartureNavPlan = function()
        return resolvedPlan
    end,
    completeDepartureNavEvaluation = function(plan)
        yal.departureNavCompletedSignature = type(plan) == "table" and plan.signature or plan
        if yal.proceduretable then
            yal.proceduretable[def.DEPARTURENAVPROCEDURE].set = true
        end
    end,
    setDepartureNavLoopPlan = function(loop, plan)
        loop.departureNavSignature = plan.signature
        loop.departureNavIdent = plan.captain and plan.captain.ident or "ATA"
        loop.departureNavFrequency = plan.captain and plan.captain.frequency or 11740
        loop.departureNavCourse = plan.captain and plan.captain.course or 310
    end,
    getDepartureNavLoopPlan = function(loop)
        if not loop.departureNavIdent then return nil end
        return {
            signature = loop.departureNavSignature,
            status = "actionable",
            captain = {
                ident = loop.departureNavIdent,
                frequency = loop.departureNavFrequency,
                course = loop.departureNavCourse
            }
        }
    end,
    checkDepartureNavParentStep = function(loop, parentProcId)
        yal.checkedDepartureNavParent = parentProcId
        local currentSignature = yal.getDepartureNavSignature()
        if yal.departureNavCompletedSignature == currentSignature then
            loop.departureNavChildPending = nil
            loop.departureNavPendingPlan = nil
            return true
        end
        if loop.departureNavChildPending then return false end
        loop.departureNavPendingPlan = yal.resolveDepartureNavPlan()
        local currentPlan = loop.departureNavPendingPlan
        if not currentPlan or currentPlan.status ~= "actionable" then
            local retryAtBeforeTaxi = parentProcId == def.COCKPITINITPROCEDURE
                and departureNav.shouldRetryAtBeforeTaxi(currentPlan and currentPlan.status)
            if not retryAtBeforeTaxi then
                yal.completeDepartureNavEvaluation(currentPlan or currentSignature)
            end
            loop.departureNavPendingPlan = nil
            return true
        end
        return false
    end,
    runDepartureNavParentStep = function(loop, parentProcId)
        yal.actedDepartureNavParent = parentProcId
        local childLoop = yal.loopStateTables[3]
        if childLoop.lock == def.NOPROCEDURE
            and yal.triggerChildProcedure(1, parentProcId, def.DEPARTURENAVPROCEDURE, false) then
            loop.departureNavChildPending = true
            yal.setDepartureNavLoopPlan(childLoop, loop.departureNavPendingPlan)
            loop.departureNavPendingPlan = nil
        end
    end
}

package.loaded.proceduredata = nil
local proceduredata = require("proceduredata")
assert(proceduredata.fillProcedureTable())
local cockpitInit = yal.proceduretable[def.COCKPITINITPROCEDURE]
local cockpitEnsure = cockpitInit.steps.ensure_departure_nav
local beforeTaxi = yal.proceduretable[def.BEFORETAXIPROCEDURE]
local beforeTaxiEnsure = beforeTaxi.steps.ensure_departure_nav
local beforeTakeoff = yal.proceduretable[def.BEFORETAKEOFFPROCEDURE]
assert(cockpitInit.steps.wait_settoflaps_done.nextStep == "ensure_departure_nav", "Cockpit Init must run Departure NAV after takeoff data")
assert(cockpitEnsure.nextStep == "view_pedestal", "Cockpit Init must continue with its established pedestal sequence")
assert(beforeTaxi.startStep == "ensure_departure_nav", "Before Taxi must retry Departure NAV before its established first step")
assert(beforeTaxiEnsure.nextStep == "view_main_panel", "Before Taxi must continue with its established main-panel step")
assert(beforeTakeoff.startStep == "view_pedestal", "Before Takeoff must retain its established first step")
assert(beforeTakeoff.steps.ensure_departure_nav == nil, "Before Takeoff must no longer own Departure NAV")
assert(beforeTakeoff.steps.check_takeoff_trim.nextStep == "check_mcp_speed", "trim must no longer defer Departure NAV until takeoff roll")
assert(cockpitEnsure.skipIf() == true and beforeTaxiEnsure.skipIf() == true, "disabled setting must bypass both Departure NAV owners")

yal.configvalues[def.CONFIGDEPARTURENAVSETUP] = def.ON
local cockpitLoop = {}
assert(cockpitEnsure.check(cockpitLoop) == false, "actionable Cockpit Init context should require the child")
assert(yal.checkedDepartureNavParent == def.COCKPITINITPROCEDURE, "Cockpit Init must identify itself as the child owner")
cockpitEnsure.action(cockpitLoop)
assert(yal.triggeredChild[1] == 1, "Departure NAV parent loop")
assert(yal.triggeredChild[2] == def.COCKPITINITPROCEDURE, "Cockpit Init must own the first Departure NAV run")
assert(yal.triggeredChild[3] == def.DEPARTURENAVPROCEDURE, "Departure NAV child procedure")

local child = yal.proceduretable[def.DEPARTURENAVPROCEDURE]
assert(child.repeatable == true and child.stateNeutral == true, "Departure NAV child must be repeatable and flight-state neutral")
local childLoop = yal.loopStateTables[3]
assert(childLoop.departureNavIdent == "ATA", "resolved plan must be passed to child as persistent scalar state")
child.steps.record_departure_nav_completion.action(childLoop)
assert(yal.departureNavCompletedSignature == "sig-a", "completed context must be latched")
assert(cockpitEnsure.check(cockpitLoop) == true, "completed context should release Cockpit Init")
local beforeTaxiLoop = {}
assert(beforeTaxiEnsure.check(beforeTaxiLoop) == true, "Before Taxi must not duplicate a completed Cockpit Init setup")

yal.departureNavCompletedSignature = nil
yal.proceduretable[def.DEPARTURENAVPROCEDURE].set = false
yal.loopStateTables[3].lock = def.NOPROCEDURE
resolvedPlan = { status = "no_selection", signature = "sig-a" }
cockpitLoop = {}
assert(cockpitEnsure.check(cockpitLoop) == true, "Cockpit Init must continue when departure selection is not ready")
assert(yal.departureNavCompletedSignature == nil, "a transient Cockpit Init result must not be latched")
resolvedPlan = { status = "actionable", signature = "sig-a", captain = {} }
beforeTaxiLoop = {}
assert(beforeTaxiEnsure.check(beforeTaxiLoop) == false, "Before Taxi must retry a transient Cockpit Init result")
beforeTaxiEnsure.action(beforeTaxiLoop)
assert(yal.triggeredChild[2] == def.BEFORETAXIPROCEDURE, "Before Taxi must own the retry child")

yal.departureNavCompletedSignature = nil
yal.proceduretable[def.DEPARTURENAVPROCEDURE].set = false
yal.loopStateTables[3].lock = def.NOPROCEDURE
resolvedPlan = { status = "rnav", signature = "sig-a" }
cockpitLoop = {}
assert(cockpitEnsure.check(cockpitLoop) == true, "RNAV decision must pass without starting a child")
assert(yal.loopStateTables[3].lock == def.NOPROCEDURE, "silent RNAV evaluation must not occupy Loop 3")
assert(yal.proceduretable[def.DEPARTURENAVPROCEDURE].set == true, "silent evaluation must be latched for later change detection")

yal.loopStateTables[1].lock = def.COCKPITINITPROCEDURE
assert(child.prerequisite() == true, "Departure NAV child must be allowed during Cockpit Init")
yal.loopStateTables[1].lock = def.BEFORETAXIPROCEDURE
assert(child.prerequisite() == true, "Departure NAV child must be allowed during Before Taxi")
yal.loopStateTables[1].lock = def.BEFORETAKEOFFPROCEDURE
yal.proceduretable[def.BEFORETAXIPROCEDURE].set = false
assert(child.prerequisite() == false, "Before Takeoff must not directly own Departure NAV")

print("test_departure_nav: all checks passed")
