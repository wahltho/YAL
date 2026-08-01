package.path = "data/modules/Custom Module/?.lua;" .. package.path

local migratedSettings = nil

sasl = {
    getOS = function() return "Linux" end,
    getProjectName = function() return "YAL" end,
    getXPlanePath = function() return "/tmp/X-Plane" end,
    getProjectPath = function() return "/tmp/YAL" end,
    readConfig = function()
        return { CUSTOMAPPROACHCALC = 1 }
    end,
    writeConfig = function(_, _, values)
        migratedSettings = values
        return true
    end,
    logDebug = function() end,
    logWarning = function() end,
    gl = { loadFont = function() return 1 end }
}

local values = {}
function get(ref) return values[ref] end
function set(ref, value) values[ref] = value end

local def = require("definitions")
local settings = require("settings")

assert(settings.appSettings.CUSTOMAPPROACHCALC == nil, "retired setting must not remain in memory")
assert(migratedSettings and migratedSettings.CUSTOMAPPROACHCALC == nil, "retired setting must be removed on write")

local commanded = nil
local windCorrection = 3
package.loaded.helpers = {
    addspaces = function(value) return tostring(value) end,
    calculateApproachWindCorrection = function(runwayHeading)
        assert(runwayHeading == 270, "wind correction should use destination runway heading")
        return windCorrection
    end,
    command_once = function(command) commanded = command end,
    convflaplevertoflappos = function(value) return value end,
    formatcgvalue = function(value)
        local number = tonumber(value)
        if number and number > 0 then return tostring(number) end
        return nil
    end,
    padNumberWithZerosStrict = function(value, length)
        return string.format("%0" .. tostring(length) .. "d", value)
    end,
    roundnumber = function(value) return math.floor(value + 0.5) end
}
package.loaded.refdata = {}

yal = {
    appflaps = "appflaps",
    appvrefcalc = "appvrefcalc",
    autobrakepos = "autobrakepos",
    calctakeoffcg = "calctakeoffcg",
    flapleverpos = "flapleverpos",
    fmccg = "fmccg",
    mcpspeed = "mcpspeed",
    tabcg = "tabcg",
    toflaps = "toflaps",
    vref = "vref",
    vref30 = "vref30",
    vrefapproachwindcorr = "vrefapproachwindcorr",
    configvalues = {
        [def.CONFIGVOICEADVICEONLY] = def.ON,
        [def.CONFIGFMCAUTOMATION] = def.ON,
    },
    getDestinationRunwayHeadingMag = function() return 270 end,
    loopStateTables = {
        [1] = { lock = def.BEFORETAXIPROCEDURE },
        [2] = { lock = def.NOPROCEDURE },
        [3] = { lock = def.NOPROCEDURE },
    },
}

local proceduredata = require("proceduredata")
assert(proceduredata.fillProcedureTable())

local setVref = yal.proceduretable[def.SETVREFPROCEDURE].steps.calculate_vref
local vrefLoop = {}
values.appflaps = 40
values.vref = 141.4
values.vref30 = 138
setVref.action(vrefLoop)
assert(vrefLoop.appflapscalc == 40, "existing approach flaps should be preserved")
assert(vrefLoop.appvrefcalc == 141.4, "existing VREF should be preserved")
assert(vrefLoop.appflapscalcstring == "40", "approach flaps should use FMC formatting")
assert(vrefLoop.appvrefcalcstring == "141", "VREF should be rounded for FMC input")

vrefLoop = {}
values.appflaps = 0
values.vref = 0
values.vref30 = 137.6
setVref.action(vrefLoop)
assert(vrefLoop.appflapscalc == 30, "missing approach flaps should fall back to 30")
assert(vrefLoop.appvrefcalc == 137.6, "missing VREF should fall back to FMC VREF30")
assert(vrefLoop.appvrefcalcstring == "138", "fallback VREF should be rounded for FMC input")

local windStep = yal.proceduretable[def.SETWINDCORRPROCEDURE].steps.calculate_windcorr
local windLoop = {}
windStep.action(windLoop)
assert(windLoop.appwindcorr == 5, "positive wind correction below five should use minimum five")
assert(windLoop.appwindcorrstring == "05", "wind correction should retain two-digit FMC formatting")
windCorrection = nil
windStep.action(windLoop)
assert(windLoop.appwindcorr == nil and windLoop.appwindcorrstring == nil, "missing wind data should clear the target")

local autobrakeStep = yal.proceduretable[def.SETAUTOBRAKEPROCEDURE].steps.set_autobrake
values.autobrakepos = def.AUTOBRAKEOFF
assert(autobrakeStep.check() == false, "autobrake OFF should require pilot selection")
assert(autobrakeStep.advice() == "Set Auto Brake", "autobrake advice should not invent a setting")
autobrakeStep.action()
assert(values.autobrakepos == def.AUTOBRAKEOFF, "standard autobrake path must not change the selector")
values.autobrakepos = def.AUTOBRAKE3
assert(autobrakeStep.check() == true, "any selected landing autobrake setting should pass")
assert(autobrakeStep.confirm() == "Auto Brake checked 3", "selected autobrake should be confirmed")

local takeoffCalc = yal.proceduretable[def.SETTOFLAPSPROCEDURE].steps.calculate_flaps
local takeoffLoop = {}
values.toflaps = 10
values.tabcg = 0
values.calctakeoffcg = 0
values.fmccg = 0
takeoffCalc.action(takeoffLoop)
assert(takeoffLoop.toflapscalc == 10, "existing FMC takeoff flaps should be preserved")
assert(takeoffLoop.flapsPreSet == true, "existing FMC takeoff flaps should be treated as preset")

takeoffLoop = {}
values.toflaps = 0
takeoffCalc.action(takeoffLoop)
assert(takeoffLoop.toflapscalc == 5, "missing FMC takeoff flaps should use standard flaps 5")
assert(takeoffLoop.flapsPreSet == true, "standard fallback should retain existing procedure sequencing")

local beforeTaxiFlaps = yal.proceduretable[def.BEFORETAXIPROCEDURE].steps.set_flaps_takeoff
values.toflaps = 0
values.flapleverpos = 5
commanded = nil
assert(beforeTaxiFlaps.check() == true, "Before Taxi should accept any positive takeoff flap without FMC target")
beforeTaxiFlaps.action()
assert(commanded == nil, "Before Taxi must not invent a takeoff flap target")
assert(beforeTaxiFlaps.confirm() == "Takeoff Flaps checked", "generic takeoff flaps should be confirmed generically")

values.toflaps = 10
values.flapleverpos = 5
assert(beforeTaxiFlaps.check() == false, "Before Taxi should enforce a positive FMC target")
beforeTaxiFlaps.action()
assert(commanded == "laminar/B738/push_button/flaps_10", "Before Taxi should command the FMC target")

local vappStep = yal.proceduretable[def.RADIOALTITUDEB1000PROCEDURE].steps.check_mcp_speed_vapp
values.mcpspeed = 145
assert(vappStep.check({ appvrefcalc = 140, appwindcorr = 5 }) == true, "VAPP should include wind correction")
values.mcpspeed = 140
assert(vappStep.check({ appvrefcalc = 140, appwindcorr = 5 }) == false, "uncorrected VREF should not satisfy corrected VAPP")

print("test_standard_performance_setup: all checks passed")
