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
local now = 0
local realTime = os.time
os.time = function() return now end

yal.airgroundsensor = "ground"
yal.altitude = "legacy_altitude"
yal.altitude_ft = "altitude"
yal.pressurealtitudeft = "pressure"
yal.verticalspeed = "vs"
yal.mcpaltitude = "mcp"
yal.fmccruisealt = "cruise"
yal.fmsflightphase = "phase"
yal.apvnavaltmode = "vnav_alt"
yal.apalthldstat = "alt_hold"
yal.updateAutoUnicomAirborneEvent = function() end
yal.getAutoUnicomNavigationTarget = function() return "BIRCO", false, nil end
yal.updateAutoUnicomArrivalContext = function() end
yal.getAutoUnicomFlightPlanContext = function() return nil end
yal.getHoldRuntimeState = function() return { active = false } end
yal.configvalues = { [def.CONFIGLOWEAIRSPACEALT] = 10000 }
yal.proceduretable = {
    [def.DURINGCLIMBPROCEDURE] = { loop = 1 },
    [def.ALTITUDEA10000PROCEDURE] = { loop = 2 }
}
yal.loopStateTables = {
    { lock = def.DURINGCLIMBPROCEDURE },
    { lock = def.ALTITUDEA10000PROCEDURE }
}
yal.autoflapsuphandling = function() end

local events, attempts, accept
local function reset(mcp)
    now = 0
    events, attempts, accept = {}, 0, true
    refs = {
        ground = def.OFF, altitude = 9000, legacy_altitude = 9000,
        pressure = 8900, vs = 0, mcp = mcp or 37000, cruise = 37000,
        phase = def.FMSFLIGHTPHASE_CLIMB, vnav_alt = 1, alt_hold = 0
    }
    yal.flightstate = def.FLIGHTSTATECLIMB
    yal.autoUnicomRuntime = { sent = { ["departure.on_climb"] = true } }
    yal.setRuntimeEventSink(function(id, payload)
        if id == "departure.climb_resumed" then attempts = attempts + 1 end
        if not accept then return false end
        events[#events + 1] = { id = id, payload = payload }
        return true
    end)
end

local function tick(time, altitude, vs)
    now = time
    refs.altitude, refs.legacy_altitude, refs.vs = altitude, altitude, vs
    yal.duringclimb()
end

local function hold(altitude, since)
    for time = since or 0, (since or 0) + 5 do tick(time, altitude, 0) end
    assert(yal.autoUnicomRuntime.climbLevel.stable, "five seconds genuinely level arms resume report")
end

local function resume(altitude, since)
    for step = 0, 3 do tick(since + step, altitude + step * 50, 1000) end
end

local function resumeCount()
    local count = 0
    for _, event in ipairs(events) do
        if event.id == "departure.climb_resumed" then count = count + 1 end
    end
    return count
end

reset(9000)
hold(9000)
refs.mcp, refs.vnav_alt = 37000, 0
resume(9050, 6)
assert(#events == 1 and events[1].id == "departure.climb_resumed", "MCP change plus actual climb reports once")
assert(events[1].payload.climb_from_altitude_ft == 9000, "reports held indicated altitude")
assert(events[1].payload.climb_from_pressure_altitude_ft == 8900, "captures original held pressure altitude")
assert(events[1].payload.mcp_altitude_ft == 37000 and events[1].payload.climb_next_waypoint == "BIRCO",
    "existing climb target and navigation payload")
tick(10, 9300, 1000)
assert(#events == 1, "continued climb does not repeat")
tick(11, 10000, 1000)
assert(#events == 1 and yal.autoUnicomRuntime.sent["departure.climb_level_10000"],
    "adjacent 10000-ft report consumed quietly")
tick(70, 11000, 1000)
assert(#events == 1, "suppressed progress is not replayed after quiet period")
tick(71, 20000, 1000)
assert(#events == 2 and events[2].id == "departure.climb_level_20000", "later normal progress remains")

reset()
hold(9000)
refs.vnav_alt = 0
resume(9050, 6)
assert(#events == 1, "MCP already at cruise while VNAV ALT held restriction needs no fresh dial change")
hold(16000, 20)
resume(16050, 26)
assert(events[#events].id == "departure.climb_resumed"
    and events[#events].payload.climb_from_altitude_ft == 16000, "another true level-off re-arms report")

reset(9000)
for time = 0, 5 do
    refs.mcp = 12000 + time * 1000
    tick(time, 9000, 0)
end
assert(yal.autoUnicomRuntime.climbLevel.stable, "MCP debounce does not interrupt actual level observation")
refs.mcp = 37000
resume(9050, 6)
assert(#events == 1, "stable climb target after dial movement uses remembered level")

reset(9000)
hold(9000)
refs.mcp, refs.vnav_alt = 37000, 0
for time = 6, 12 do tick(time, 9000, 0) end
assert(#events == 0, "dial or AP-mode change without actual climb is silent")
for time = 13, 16 do tick(time, 9050, 1000) end
assert(#events == 0, "positive VS alone without 100-ft actual departure is silent")
tick(17, 9100, 1000)
assert(#events == 1, "actual upward departure completes report")

reset()
for time = 0, 4 do tick(time, 9000, 0) end
resume(9050, 5)
assert(#events == 0, "brief level-off is insufficient")
reset()
hold(9000)
tick(6, 9050, 1000)
tick(7, 9100, 200)
tick(8, 9150, 1000)
tick(9, 9200, 1000)
tick(10, 9250, 1000)
assert(#events == 0, "rate fluctuation resets the three-second climb debounce")
tick(11, 9300, 1000)
assert(#events == 1, "stable rate after fluctuation reports")

for _, mode in ipairs({ "LVL_CHG", "VS", "MANUAL" }) do
    reset()
    refs.vnav_alt, refs.alt_hold = 0, 0
    hold(9000)
    resume(9050, 6)
    assert(#events == 1, mode .. " does not require VNAV PATH as successor")
end

reset(9000)
hold(9000)
resume(9050, 6)
assert(#events == 0, "old MCP restriction is not a higher climb target")
refs.mcp = 16000
tick(10, 9300, 1000)
assert(#events == 0, "new target waits for existing MCP debounce")
tick(11, 9350, 1000)
assert(#events == 1 and events[1].payload.mcp_altitude_ft == 16000, "stable higher target reports actual climb")

reset()
refs.mcp = nil
hold(9000)
resume(9050, 6)
assert(#events == 1, "existing FMC target fallback is retained")
reset()
refs.mcp, refs.cruise = 0, 0
hold(9000)
resume(9050, 6)
assert(#events == 0, "missing target cannot publish incomplete report")

for _, invalid in ipairs({ 0 / 0, math.huge }) do
    reset()
    hold(9000)
    tick(6, invalid, 1000)
    resume(9050, 7)
    assert(resumeCount() == 0 and yal.autoUnicomRuntime.climbLevel == nil,
        "invalid altitude clears old observation")
    reset()
    hold(9000)
    tick(6, 9050, invalid)
    resume(9050, 7)
    assert(#events == 0, "invalid VS cannot preserve a level for later replay")
end
reset()
hold(9000)
tick(6, 8950, -1000)
resume(9050, 7)
assert(#events == 0, "downward departure is not resumed climb")
reset()
hold(9000)
refs.ground = def.ON
tick(6, 9100, 1000)
assert(yal.autoUnicomRuntime.climbLevel == nil and #events == 0, "ground cannot publish resumed climb")
reset()
hold(9000)
yal.flightstate = def.FLIGHTSTATECRUISE
tick(6, 9100, 1000)
assert(yal.autoUnicomRuntime.climbLevel == nil and #events == 0, "observer follows existing CLIMB authority")

reset()
hold(9000)
accept = false
resume(9050, 6)
assert(attempts == 1 and yal.autoUnicomRuntime.climbResumeLastAt == nil,
    "local rejection does not consume observation or suppress progress")
accept = true
tick(10, 9300, 1000)
assert(attempts == 2 and #events == 1, "local rejected event may enqueue later")
tick(11, 9350, 1000)
assert(attempts == 2, "accepted event is latched, not resubmitted")

reset()
hold(9000)
accept = false
resume(9050, 6)
accept = true
tick(127, 9500, 1000)
assert(resumeCount() == 0 and yal.autoUnicomRuntime.climbLevel == nil,
    "unsent leaving report expires with existing event TTL instead of reporting an old level")

reset()
hold(9000)
yal.autoUnicomRuntime.climbResumeLastAt = 1
yal.baselineAutoUnicomRuntimeEvents()
assert(yal.autoUnicomRuntime.climbLevel == nil and yal.autoUnicomRuntime.climbResumeLastAt == nil,
    "actual reload baseline clears held level and quiet period")
resume(9050, 6)
assert(#events == 0, "reload during climb does not report historical level departure")
hold(16000, 20)
resume(16050, 26)
assert(events[#events].id == "departure.climb_resumed", "new level after reload can report")

os.time = realTime
print("Auto-Unicom climb runtime tests PASS")
