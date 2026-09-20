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
    formatcgvalue = function(value) return tostring(value) end
}
package.loaded.refdata = {}

local def = require("definitions")

yal = {
    hydro1pos = "hydro1pos",
    hydro2pos = "hydro2pos",
    elechydro1pos = "elechydro1pos",
    elechydro2pos = "elechydro2pos",
    configvalues = {}
}

local proceduredata = require("proceduredata")
assert(proceduredata.fillProcedureTable())

local function verifyShutdownProcedure(procedureId, label)
    local steps = yal.proceduretable[procedureId].steps
    local enginePumps = steps.eng_hyd_pumps_on
    local electricPumps = steps.elec_hyd_pumps_off

    assert(steps.wing_pumps_off.nextStep == "eng_hyd_pumps_on", label .. " should normalize engine pumps next")
    assert(enginePumps.nextStep == "elec_hyd_pumps_off", label .. " should then switch electric pumps off")

    values.hydro1pos = def.OFF
    values.hydro2pos = def.OFF
    assert(enginePumps.check() == false, label .. " should reject engine-driven pumps OFF")
    enginePumps.action()
    assert(values.hydro1pos == def.ON and values.hydro2pos == def.ON, label .. " should set engine-driven pumps ON")
    assert(enginePumps.check() == true, label .. " should accept engine-driven pumps ON")

    values.elechydro1pos = def.ON
    values.elechydro2pos = def.ON
    assert(electricPumps.check() == false, label .. " should reject electric pumps ON")
    electricPumps.action()
    assert(values.elechydro1pos == def.OFF and values.elechydro2pos == def.OFF, label .. " should set electric pumps OFF")
    assert(electricPumps.check() == true, label .. " should accept electric pumps OFF")
end

verifyShutdownProcedure(def.TURNAROUNDENGINESHUTDOWNPROCEDURE, "Turnaround shutdown")
verifyShutdownProcedure(def.FINALENGINESHUTDOWNPROCEDURE, "Final shutdown")

print("test_shutdown_hydraulics: all checks passed")
