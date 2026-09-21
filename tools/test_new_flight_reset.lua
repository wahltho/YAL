package.path = "data/modules/Custom Module/?.lua;" .. package.path

sasl = setmetatable({
    appendMenuItem = function() return 1 end,
    createMenu = function() return 1 end,
    createCommand = function() return 1 end,
    registerCommandHandler = function() end,
    appendMenuSeparator = function() end,
    getOS = function() return "Linux" end,
    getProjectName = function() return "YAL" end,
    getProjectPath = function() return "/tmp/YAL" end,
    getXPlanePath = function() return "/tmp/X-Plane" end,
    readConfig = function() return {} end,
    writeConfig = function() return true end,
    getLogLevel = function() return 0 end,
    gl = { loadFont = function() return 1 end }
}, { __index = function() return function() end end })
PLUGINS_MENU_ID = 1
LOG_DEBUG = 10

local refs = {}
function get(ref) return refs[ref] end
function set(ref, value) refs[ref] = value end

helpers = { logInfoTS = function() end }
package.loaded.helpers = helpers
local def = require("definitions")
local yal = require("yal")
local proceduredata = require("proceduredata")
local refdata = require("refdata")

yal.flightstate = def.FLIGHTSTATESHUTDOWN
yal.procedureloop1 = { lock = def.NOPROCEDURE }
yal.procedureloop2 = { lock = def.NOPROCEDURE }
yal.procedureloop3 = { lock = def.NOPROCEDURE }
yal.loopStateTables = { yal.procedureloop1, yal.procedureloop2, yal.procedureloop3 }
yal.battery = "battery"
yal.gpuon = "gpu"
yal.fmsflightphase = "fmsphase"
yal.ProcSetStatusarraydr = "procstatus"
refs.battery = def.OFF
refs.gpu = def.OFF
refs.fmsphase = 0
refs.flightstate = def.FLIGHTSTATESHUTDOWN

local taxiReset = false
yal.taxiComponent = {
    resetForNewFlight = function() taxiReset = true end
}
yal.YalinitGlobal = function() yal.flightstate = def.FLIGHTSTATEPREFLIGHT end
proceduredata.fillProcedureTable = function()
    yal.proceduretable = { [def.COLDANDDARKPROCEDURE] = { set = false } }
end
yal.buildProcedureLabelMaps = function() end
yal.initDataref = function()
    yal.flightstatedr = "flightstate"
    yal.flightstate = refs.flightstate
    yal.isReloadWithinSession = true
end
refdata.initialize = function() end
yal.readconfig = function() end
yal.apurunning = function() return def.OFF end
yal.resetLoopState = function(loop) loop.lock = def.NOPROCEDURE end
yal.saveLoopState = function() end
yal.baselineAutoUnicomRuntimeEvents = function() end
yal.prepareRefdataLegacyTables = function() end
yal.commandtableentry = function() end
yal.YANSHisinstalled = function() return false end
yal.BPBisinstalled = function() return false end

assert(yal.yalresetForNewFlight() == true, "new-flight reset succeeds at parking")
assert(yal.flightstate == def.FLIGHTSTATEPREFLIGHT, "new flight is PREFLIGHT in memory")
assert(refs.flightstate == def.FLIGHTSTATEPREFLIGHT, "new flight persists PREFLIGHT")
assert(yal.isReloadWithinSession == false, "new flight is not treated as a reload")
assert(taxiReset, "new flight resets the persistent taxi component")

print("test_new_flight_reset: all checks passed")
