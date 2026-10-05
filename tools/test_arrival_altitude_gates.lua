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
local proceduredata = require("proceduredata")

yal.altitude = "altitude"
yal.radioaltitude = "radio"
yal.desicao = "icao"
yal.desrwyalt = "runway_elevation"
local field, geometryOpen, geometryCalls, geometryArgs
local airportSource = "zibo_api"
local realGeometryGate = yal.isArrivalRunwayRadioAltGateOpen
-- Keep both elevation getters real, including their elevation/source return contract.
yal.getAirportRefdata = function()
    if airportSource == "fallback" then return nil end
    return { elevation_ft = field, _source = airportSource }
end
yal.isArrivalRunwayRadioAltGateOpen = function(distance, heading)
    geometryCalls = geometryCalls + 1
    geometryArgs = { distance, heading }
    return geometryOpen
end

local function context(elevation, altitude, radio, geometry)
    field = elevation
    refs.altitude, refs.radio = altitude, radio
    geometryOpen, geometryCalls, geometryArgs = geometry ~= false, 0, nil
end

context(6550, 9555.05859375, 1900.4959716797)
assert(yal.isArrivalBelow2500Gate() == false, "KEGE terrain RA must not override 3005 ft above field")
assert(geometryCalls == 0, "valid field elevation never consults radio-altitude geometry")

for _, source in ipairs({ "zibo_api", "yal_cache", "fallback" }) do
    airportSource = source
    refs.runway_elevation = 6550
    context(6550, 9555.05859375, 1900.4959716797)
    local elevation, returnedSource = yal.getDestinationAirportElevationFt()
    assert(elevation == 6550 and returnedSource == source, source .. " real getter returns elevation and source")
    assert(not yal.isArrivalBelow2500Gate() and not yal.isArrivalBelow1000Gate() and geometryCalls == 0,
        source .. " source string must not become tonumber's optional base")
    context(6550, 9049, nil, false)
    assert(yal.isArrivalBelow2500Gate() and not yal.isArrivalBelow1000Gate(),
        source .. " source metadata leaves field-height semantics unchanged")
    refs.altitude = 7549
    assert(yal.isArrivalBelow1000Gate(), source .. " Below1000 uses the actual getter")

    refs.runway_elevation = nil
    context(nil, 9555, 500)
    elevation, returnedSource = yal.getDestinationAirportElevationFt()
    assert(elevation == nil and returnedSource == "fallback", "unavailable elevation still returns source metadata")
    assert(yal.isArrivalBelow2500Gate() and yal.isArrivalBelow1000Gate(),
        "nil elevation plus fallback source string still permits geometry-gated radio altitude")
end
airportSource = "zibo_api"

for _, gate in ipairs({
    { fn = yal.isArrivalBelow2500Gate, height = 2500, distance = 8, heading = 60 },
    { fn = yal.isArrivalBelow1000Gate, height = 1000, distance = 4, heading = 40 }
}) do
    for _, elevation in ipairs({ 6550, 0, -500 }) do
        context(elevation, elevation + gate.height + 100, 100)
        assert(gate.fn() == false, "low terrain RA cannot advance a valid field gate")
        context(elevation, elevation + gate.height, 100)
        assert(gate.fn() == false, "exact height threshold retains strict comparison")
        context(elevation, elevation + gate.height - 1, 99999, false)
        assert(gate.fn() == true and geometryCalls == 0, "field height works without radio or runway alignment")
        context(elevation, elevation + gate.height - 1, nil, false)
        assert(gate.fn() == true, "valid field height does not require radio altitude")
    end

    for _, invalid in ipairs({ "missing", "bad", -1000, -2000, 0 / 0, math.huge, -math.huge }) do
        local elevation = invalid
        if invalid == "missing" then elevation = nil end
        context(elevation, 9555, gate.height - 1)
        assert(gate.fn() == true and geometryCalls == 1, "unavailable elevation retains geometry-gated RA fallback")
        assert(geometryArgs[1] == gate.distance and geometryArgs[2] == gate.heading,
            "fallback retains existing runway distance and alignment limits")
        geometryOpen = false
        assert(gate.fn() == false, "radio fallback requires arrival runway geometry")
        refs.radio = gate.height
        geometryCalls = 0
        assert(gate.fn() == false and geometryCalls == 0, "fallback exact threshold stays closed")
    end

    for _, invalid in ipairs({ "missing", "bad", 0 / 0, math.huge, -math.huge }) do
        local value = invalid
        if invalid == "missing" then value = nil end
        context(6550, value, 100)
        assert(gate.fn() == false and geometryCalls == 0, "known field with invalid altitude fails closed")
        context(nil, 9555, value)
        assert(gate.fn() == false and geometryCalls == 0, "invalid radio altitude cannot open fallback")
    end
end

-- Exercise the unchanged runway fallback, not just a permissive geometry stub.
yal.isArrivalRunwayRadioAltGateOpen = realGeometryGate
yal.aircraftlatpos, yal.aircraftlonpos, yal.groundtrackmag = "lat", "lon", "track"
refs.lat, refs.lon, refs.track = 39.6, -106.9, 250
local distance, headingDiff = 3, 0
helpers.getdistance = function() return distance end
helpers.headingdiff = function() return headingDiff end
yal.getDestinationRunwayRefdata = function()
    return { start_lat = 39.64, start_lon = -106.92, course_deg_mag = 250 }
end
context(nil, 9555, 500)
assert(yal.isArrivalBelow2500Gate() and yal.isArrivalBelow1000Gate(), "near aligned runway permits RA fallback")
distance = 5
assert(yal.isArrivalBelow2500Gate() and not yal.isArrivalBelow1000Gate(), "1000 gate keeps tighter distance")
distance = 9
assert(not yal.isArrivalBelow2500Gate(), "far runway rejects RA fallback")
distance, headingDiff = 3, 50
assert(yal.isArrivalBelow2500Gate() and not yal.isArrivalBelow1000Gate(), "1000 gate keeps tighter alignment")
headingDiff = 61
assert(not yal.isArrivalBelow2500Gate(), "misalignment rejects RA fallback")
headingDiff, refs.lat = 0, nil
assert(not yal.isArrivalBelow2500Gate(), "missing position rejects RA fallback")
refs.lat = 39.6

assert(proceduredata.fillProcedureTable())
local consumers2500 = {
    def.ALTITUDEB10000PROCEDURE, def.SETILSPROCEDURE, def.SETVREFPROCEDURE,
    def.SETWINDCORRPROCEDURE, def.SETAUTOBRAKEPROCEDURE
}
context(6550, 9555.05859375, 1900.4959716797)
for _, id in ipairs(consumers2500) do
    local transition = yal.proceduretable[id].transitionConditions[1]
    assert(transition.silent and not transition.condition(), "terrain RA cannot prematurely cancel " .. id)
end
refs.altitude = 9049
for _, id in ipairs(consumers2500) do
    assert(yal.proceduretable[id].transitionConditions[1].condition(), "actual field threshold still cancels " .. id)
end
local transition1000 = yal.proceduretable[def.RADIOALTITUDEB2500PROCEDURE].transitionConditions[1]
context(6550, 8000, 500)
assert(transition1000.silent and not transition1000.condition(), "low terrain RA cannot cancel Below2500 early")
refs.altitude = 7549
assert(transition1000.condition(), "actual Below1000 still supersedes Below2500")

-- Both procedure starts and approach-prep completion use the same real helper.
yal.desicao, yal.desrwy = "icao", "runway"
yal.distdest, yal.verticalspeed = "distance", "vs"
refs.icao, refs.runway, refs.distance, refs.vs = "KEGE", "25", 100, -1000
yal.fmsselectedapp = nil
helpers.isvalidicao = function(value) return value == "KEGE" end
helpers.isvalidrwy = function(value) return value == "25" end
context(6550, 9555.05859375, 1900.4959716797)
yal.triggerapproachprep()
assert(yal.approachPrepCompletedForKey == nil, "terrain RA cannot mark approach preparation completed")
refs.altitude = 9049
yal.triggerapproachprep()
assert(yal.approachPrepCompletedForKey == "KEGE|25", "actual field gate still supersedes approach preparation")

yal.updateAutoUnicomDescentEvents = function() end
yal.clearPauseTodGuardState = function() end
yal.configvalues = { [def.CONFIGLOWEAIRSPACEALT] = 10000, [def.CONFIGAUTOFLAPS] = def.OFF }
yal.loopStateTables = {
    { lock = def.NOPROCEDURE }, { lock = def.DURINGDESCENTPROCEDURE }, { lock = def.NOPROCEDURE }
}
local triggered = {}
yal.triggerprocedure = function(id)
    local proc = yal.proceduretable[id]
    if proc.set then return false end
    triggered[#triggered + 1] = id
    yal.loopStateTables[proc.loop].lock = id
    return true
end
context(6550, 9555.05859375, 1900.4959716797)
yal.duringdescent()
assert(#triggered == 1 and triggered[1] == def.ALTITUDEB10000PROCEDURE,
    "Below10000 retains its barometric start without premature Below2500")
assert(not yal.pendingAltitudeB2500Trigger and not yal.pendingAltitudeB1000Trigger,
    "terrain RA cannot queue later procedures")
refs.altitude = 9049
yal.duringdescent()
assert(yal.pendingAltitudeB2500Trigger and #triggered == 1, "true field crossing waits for busy procedure loop")
yal.proceduretable[def.ALTITUDEB10000PROCEDURE].set = true
yal.loopStateTables[1].lock = def.NOPROCEDURE
yal.duringdescent()
assert(triggered[2] == def.RADIOALTITUDEB2500PROCEDURE and not yal.pendingAltitudeB2500Trigger,
    "pending Below2500 starts when existing loop becomes free")
refs.altitude, refs.radio = 8000, 500
yal.duringdescent()
assert(not yal.pendingAltitudeB1000Trigger, "terrain RA still cannot queue Below1000")
refs.altitude = 7549
yal.duringdescent()
assert(yal.pendingAltitudeB1000Trigger, "actual field crossing queues Below1000")
yal.proceduretable[def.RADIOALTITUDEB2500PROCEDURE].set = true
yal.loopStateTables[1].lock = def.NOPROCEDURE
yal.duringdescent()
assert(triggered[3] == def.RADIOALTITUDEB1000PROCEDURE and not yal.pendingAltitudeB1000Trigger,
    "pending Below1000 starts when existing loop becomes free")

print("arrival altitude gate tests passed")
