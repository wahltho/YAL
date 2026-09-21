package.path = "data/modules/Custom Module/?.lua;" .. package.path

package.loaded.definitions = { CONFIGDEBUGOVERLAY = 1, ON = 1 }
package.loaded.settings = {
    appSettings = {},
    getSettingNumber = function(_, default) return default end
}
package.loaded.helpers = {
    logInfoTS = function() end,
    roundnumber = function(value) return math.floor(value + 0.5) end
}

sasl = {
    createTimer = function() return {} end,
    startTimer = function() end
}
function createProperty(value) return value end

local taxi = require("windows.taxi")
local comp = taxi.newComponent({ yal = {} })
local graph = {
    nodes = {
        start = { east = 0, north = 0 },
        next = { east = 100, north = 0 }
    }
}
local route = { path = { "start", "next" }, data = graph }

comp._route = route
assert(comp:getPushbackHint() ~= nil, "first flight has a direction hint")

comp.mode = 1
comp.modeOverride = true
comp._lastMode = 1
comp._lastIcao = "ENAT"
comp._lastArrivalIcao = "ENAT"
comp._data = graph
comp._route = route
comp._pushbackStartedEver = true
comp._pushbackActive = true
comp._pushbackPlanSeen = true
assert(comp:getPushbackHint() == nil, "arrival mode has no departure pushback hint")

comp:resetForNewFlight()
assert(comp.mode == 0 and comp.modeOverride == false, "new flight restores automatic DEP mode")
assert(comp._lastMode == nil and comp._route == nil, "new flight invalidates arrival routing")
assert(comp._data == graph, "airport graph cache is retained")
assert(comp._lastArrivalIcao == nil, "arrival fallback airport is cleared")
assert(comp._pushbackStartedEver == false and comp._pushbackActive == false
    and comp._pushbackPlanSeen == false, "pushback lifecycle starts clean")

comp._route = route
assert(comp:getPushbackHint() ~= nil, "second flight gets a direction after route recomputation")

print("test_taxi_new_flight: all checks passed")
