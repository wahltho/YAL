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
    gl = { loadFont = function() return 1 end }
}, { __index = function() return function() end end })
PLUGINS_MENU_ID = 1

local refs = {}
function get(ref) return refs[ref] end
function set(ref, value) refs[ref] = value end

helpers = { logInfoTS = function() end }
package.loaded.helpers = helpers
local def = require("definitions")
local yal = require("yal")
yal.clearYalQueuedSpeech = function() end
yal.ProcSetStatusarraydr = nil

local signature = "departure-a"
yal.getDepartureNavSignature = function() return signature end
yal.configvalues = { [def.CONFIGDEPARTURENAVSETUP] = def.ON }
yal.proceduretable = {
    [def.COCKPITINITPROCEDURE] = { name = "Cockpit Init" },
    [def.BEFORETAXIPROCEDURE] = { name = "Before Taxi", set = true },
    [def.BEFORETAKEOFFPROCEDURE] = { name = "Before Takeoff", set = false },
    [def.DEPARTURENAVPROCEDURE] = { name = "Departure NAV", set = false }
}

local function loops(parentId)
    local parent = { lock = parentId }
    local child = {
        lock = def.DEPARTURENAVPROCEDURE,
        parentLoopIndex = 1,
        parentProcId = parentId
    }
    yal.procedureloop1 = parent
    yal.procedureloop2 = { lock = def.NOPROCEDURE }
    yal.procedureloop3 = child
    yal.loopStateTables = { parent, yal.procedureloop2, child }
    yal.departureNavCompletedSignature = nil
    yal.proceduretable[def.DEPARTURENAVPROCEDURE].set = false
    return parent, child
end

local parent, child = loops(def.BEFORETAXIPROCEDURE)
yal.findMostRecentLoop = function() return parent, 1 end
yal.skipprocedure()
assert(yal.departureNavCompletedSignature == signature,
    "skipping Before Taxi latches its Departure NAV child")
assert(child.procedureabort == true and child.procedureskipped == true,
    "parent skip stops the active NAV child")

parent, child = loops(def.BEFORETAXIPROCEDURE)
child.lock = def.NOPROCEDURE
yal.findMostRecentLoop = function() return parent, 1 end
yal.skipprocedure()
assert(yal.departureNavCompletedSignature == signature,
    "skipping Before Taxi before the child starts still latches NAV")

parent, child = loops(def.BEFORETAXIPROCEDURE)
yal.configvalues[def.CONFIGDEPARTURENAVSETUP] = def.OFF
yal.findMostRecentLoop = function() return parent, 1 end
yal.skipprocedure()
assert(yal.departureNavCompletedSignature == nil,
    "skipping Before Taxi cannot complete a disabled NAV option")
yal.configvalues[def.CONFIGDEPARTURENAVSETUP] = def.ON

parent, child = loops(def.BEFORETAXIPROCEDURE)
yal.findMostRecentLoop = function() return child, 3 end
yal.skipprocedure()
assert(yal.departureNavCompletedSignature == signature,
    "skipping the Before Taxi NAV child latches NAV")

parent, child = loops(def.COCKPITINITPROCEDURE)
yal.findMostRecentLoop = function() return child, 3 end
yal.skipprocedure()
assert(yal.departureNavCompletedSignature == nil,
    "Cockpit Init NAV skip still permits the Before Taxi retry")

parent, child = loops(def.BEFORETAXIPROCEDURE)
yal.findMostRecentLoop = function() return child, 3 end
yal.abortprocedure()
assert(yal.departureNavCompletedSignature == nil,
    "abort does not suppress later NAV evaluation")

yal.configvalues = { [def.CONFIGDEPARTURENAVSETUP] = def.ON }
yal.airgroundsensor = "airground"
yal.groundspeed = "groundspeed"
refs.airground = def.ON
refs.groundspeed = 0
yal.flightstate = def.FLIGHTSTATEPREFLIGHT
yal.proceduretable[def.BEFORETAXIPROCEDURE].set = true
yal.procedureloop3.lock = def.NOPROCEDURE
local triggered = 0
yal.resolveDepartureNavPlan = function()
    return { status = "actionable", signature = signature, captain = {} }
end
yal.triggerprocedure = function() triggered = triggered + 1; return true end
yal.setDepartureNavLoopPlan = function() end
yal.saveLoopState = function() end

yal.procedureloop1.lock = def.BEFORETAKEOFFPROCEDURE
yal.updateDepartureNavSetup()
assert(triggered == 0, "Before Takeoff does not restart Departure NAV")

yal.procedureloop1.lock = def.NOPROCEDURE
yal.proceduretable[def.BEFORETAKEOFFPROCEDURE].set = true
yal.updateDepartureNavSetup()
assert(triggered == 0, "completed Before Takeoff does not restart Departure NAV")

yal.proceduretable[def.BEFORETAKEOFFPROCEDURE].set = false
yal.departureNavCompletedSignature = signature
yal.updateDepartureNavSetup()
assert(triggered == 0, "matching completed NAV context does not restart")

signature = "departure-b"
yal.updateDepartureNavSetup()
assert(triggered == 1, "changed departure selection remains eligible before takeoff")

print("test_departure_nav_runtime: all checks passed")
