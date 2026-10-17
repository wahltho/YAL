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

local refs, logs, sink = {}, {}, {}
local now = 0
local realTime = os.time
os.time = function() return now end
function get(ref) return refs[ref] end
function set() error("cruise altitude reminder must never write aircraft controls") end
helpers = {
    roundnumber = function(value) return math.floor(value + 0.5) end,
    addspaces = tostring,
    logInfoTS = function(text) logs[#logs + 1] = text end,
    clearSpeakStringSink = function(key)
        assert(key == "advice:cruise_altitude", "only this reminder's speech may be cancelled")
        sink[key] = nil
    end,
    command_once = function() error("cruise altitude reminder must never command aircraft controls") end,
    stepQuickViewsCgUpdate = function() end,
    stepDefaultViewUpdate = function() end
}
package.loaded.helpers = helpers
local def = require("definitions")
local yal = require("yal")
local names = {
    airgroundsensor = "ground", fmsflightphase = "phase", altitude = "altitude",
    fmccruisealt = "cruise", mcpaltitude = "mcp", verticalspeed = "vs",
    apvnavaltmode = "vnavalt"
}
for field, ref in pairs(names) do yal[field] = ref end
yal.commandtable = {}

local function context(overrides)
    yal.resetCruiseAltitudeGuard()
    refs = {
        ground = def.OFF, phase = def.FMSFLIGHTPHASE_CLIMB,
        altitude = 39000, cruise = 41000, mcp = 39000, vs = 0,
        vnavalt = def.ON
    }
    for key, value in pairs(overrides or {}) do refs[key] = value end
    yal.flightstate = def.FLIGHTSTATECLIMB
    yal.configvalues = {
        [def.CONFIGLOWEAIRSPACEALT] = 10000,
        [def.CONFIGAUTOFUNCTIONS] = def.ON,
        [def.CONFIGVOICEADVICEONLY] = def.OFF
    }
    yal.commandtable, logs, sink = {}, {}, {}
    now = 0
end

local function tick(time)
    now = time
    yal.updateCruiseAltitudeGuard()
end

local function assertSilent(label)
    tick(0)
    tick(15)
    tick(600)
    assert(#yal.commandtable == 0 and #logs == 0, label)
end

for _, gap in ipairs({ 1000, 2000, 5000 }) do
    for _, vnav in ipairs({ def.OFF, def.ON }) do
        context({ cruise = 39000 + gap, vnavalt = vnav })
        tick(0)
        tick(14)
        assert(#yal.commandtable == 0, "level-off must persist for the full grace period")
        tick(15)
        assert(#yal.commandtable == 1 and #logs == 1,
            "stable MCP-limited level-off must warn regardless of gap size or VNAV ALT")
        local entry = yal.commandtable[1]
        assert(entry[1] == def.TEXT and entry[3] == def.CRUISE_ALT_MISMATCH_SPEECH_KEY,
            "reminder uses real keyed YAL speech queue")
        assert(entry[2]:find("Planned cruise altitude is " .. (39000 + gap), 1, true)
            and entry[2]:find("M C P altitude is 39000", 1, true), "reminder includes both targets")
        assert((entry[2]:find("V N A V Alt active", 1, true) ~= nil) == (vnav == def.ON),
            "VNAV ALT prefix follows actual mode without bypassing stabilization")
        tick(16)
        tick(314)
        assert(#logs == 1, "reminder does not repeat within five minutes")
        tick(315)
        assert(#logs == 2 and #yal.commandtable == 1, "repeat remains deduplicated by speech key")
    end
end

context({ vs = 1200, altitude = 38900 })
assertSilent("normal climb near selected level is not a level-off")
context({ altitude = 36000 })
assertSilent("level flight far from MCP target does not trigger this guard")
context({ vs = -1200 })
assertSilent("actual descent is not a missed climb even with stale climb phase")
context({ cruise = 39000, mcp = 41000 })
assertSilent("MCP above cruise is not a failure to reach cruise")
context({ altitude = 41000 })
assertSilent("actual cruise reached cannot warn just because MCP is below cruise")
context({ altitude = 38800, cruise = 39500, mcp = 39000 })
assertSilent("sub-threshold MCP discrepancy remains suppressed")
context({ altitude = 40200, mcp = 40200 })
assertSilent("sub-threshold actual cruise discrepancy remains suppressed")
context({ altitude = 39199, mcp = 39000, cruise = 40000 })
assertSilent("both actual and selected levels must be sufficiently below cruise")
context({ ground = def.ON })
assertSilent("ground cannot trigger a cruise reminder")
context({ altitude = 10000, mcp = 10000 })
assertSilent("configured lower-airspace altitude retains its separate reminder")

for _, phase in ipairs({ def.FMSFLIGHTPHASE_CRZ_DES, def.FMSFLIGHTPHASE_DESCENT,
    def.FMSFLIGHTPHASE_APPROACH, def.FMSFLIGHTPHASE_GO_AROUND }) do
    context({ phase = phase })
    assertSilent("descent/approach phase overrides stale YAL climb state")
end
context()
yal.flightstate = def.FLIGHTSTATEAPPROACH
assertSilent("YAL arrival state overrides stale FMS climb phase")

for _, field in ipairs({ "cruise", "mcp", "altitude", "vs" }) do
    for _, invalid in ipairs({ "missing", "invalid", 0 / 0, math.huge, -math.huge }) do
        context()
        refs[field] = invalid
        if invalid == "missing" then refs[field] = nil end
        assertSilent("invalid " .. field .. " must not invent a level-off")
    end
end

context()
refs.vs = nil
assertSilent("missing vertical speed must not be treated as level flight")

context({ vs = 100, altitude = 38800 })
tick(0)
tick(15)
assert(#logs == 1, "level-band and vertical-speed boundaries are inclusive")
context({ vs = 101 })
assertSilent("vertical speed outside the level band resets stabilization")
context({ altitude = 38799 })
assertSilent("altitude outside the selected-level band is not a level-off")

for _, phase in ipairs({ def.FMSFLIGHTPHASE_CLIMB, def.FMSFLIGHTPHASE_CRUISE,
    def.FMSFLIGHTPHASE_CRZ_CLB }) do
    context({ phase = phase })
    yal.flightstate = def.FLIGHTSTATECRUISE
    tick(0)
    tick(15)
    assert(#logs == 1, "existing climb/cruise authorities also support an inflight reload")
end

context()
tick(0)
tick(10)
refs.vs = 700
tick(11)
refs.vs = 0
tick(12)
tick(26)
assert(#logs == 0, "interrupted level-off must restart stabilization")
tick(27)
assert(#logs == 1, "new continuous level-off can warn")

for _, change in ipairs({
    function() refs.mcp = 41000 end,
    function() refs.altitude = 41000 end,
    function() refs.vs = 700 end,
    function() refs.phase = def.FMSFLIGHTPHASE_DESCENT end,
    function() refs.ground = def.ON end,
    function() refs.cruise = 39000 end
}) do
    context()
    tick(0)
    tick(15)
    sink[def.CRUISE_ALT_MISMATCH_SPEECH_KEY] = "old reminder"
    yal.commandtableentry(def.TEXT, "Unrelated advice", "advice:other")
    change()
    tick(16)
    assert(yal.cruiseAltMismatchKey == nil and yal.cruiseAltMismatchFirstSeenAt == nil
        and yal.cruiseAltMismatchLastWarnAt == nil, "resolved context clears guard state")
    assert(#yal.commandtable == 1 and yal.commandtable[1][3] == "advice:other",
        "resolved context removes only stale cruise advice from real local queue")
    assert(sink[def.CRUISE_ALT_MISMATCH_SPEECH_KEY] == nil,
        "resolved context also cancels keyed sink speech")
end

context()
tick(0)
tick(15)
refs.cruise = 43000
tick(16)
assert(#yal.commandtable == 0, "FMC target change cancels old planned-altitude speech")
tick(30)
assert(#logs == 1, "FMC target change starts a fresh grace period")
tick(31)
assert(#logs == 2 and yal.commandtable[1][2]:find("43000", 1, true),
    "new FMC target is used after stabilization")

context()
tick(0)
tick(10)
refs.mcp, refs.altitude = 37000, 37000
tick(11)
tick(25)
assert(#logs == 0, "MCP target change starts a fresh grace period")
tick(26)
assert(#logs == 1, "changed selected level can warn after its own grace period")

context()
tick(100)
tick(115)
tick(50)
assert(#yal.commandtable == 0 and yal.cruiseAltMismatchFirstSeenAt == 50,
    "clock regression clears old speech and restarts stabilization")
tick(65)
assert(#logs == 2, "clock regression cannot stall warnings indefinitely")

context()
tick(0)
tick(14)
yal.resetCruiseAltitudeGuard()
tick(15)
tick(29)
assert(#logs == 0, "fresh reload/reset cannot inherit a nearly complete timer")
tick(30)
assert(#logs == 1, "reload into an existing level-off eventually warns")

-- Exercise the actual do_yal disable branch without running unrelated procedures.
settings.newSettingsAvailable = false
yal.needstempinit = false
yal.updateSharedVariables = function() end
yal.updateDepartureMcpSpeedOwnership = function() end
yal.updateAntiIce = function() end
yal.lastExecutedLoopIndex = 1
yal.ongoingtaskstepindex = 1
yal.procedureloop1, yal.procedureloop2, yal.procedureloop3 =
    { lock = def.NOPROCEDURE }, { lock = def.NOPROCEDURE }, { lock = def.NOPROCEDURE }
yal.loopStateTables = { yal.procedureloop1, yal.procedureloop2, yal.procedureloop3 }
yal.commandtableloop = function() return def.STANDARDWAIT end
yal.configvalues[def.CONFIGAUTOFUNCTIONS] = def.OFF
yal.configvalues[def.CONFIGVOICEADVICEONLY] = def.OFF
yal.do_yal()
assert(yal.cruiseAltMismatchKey == nil and #yal.commandtable == 0,
    "disabled background functions clear actual guard state and queued speech")

yal.updateAutoUnicomHoldEvents = function() end
yal.autofunctions = function() end
yal.ongoingtasks = function() yal.updateCruiseAltitudeGuard() end
for _, adviceOnly in ipairs({ false, true }) do
    context()
    yal.configvalues[def.CONFIGAUTOFUNCTIONS] = adviceOnly and def.OFF or def.ON
    yal.configvalues[def.CONFIGVOICEADVICEONLY] = adviceOnly and def.ON or def.OFF
    yal.do_yal()
    now = 15
    yal.do_yal()
    assert(#yal.commandtable == 1, "actual background dispatch enables Auto and Advice-only modes")
    yal.configvalues[def.CONFIGAUTOFUNCTIONS] = def.OFF
    yal.configvalues[def.CONFIGVOICEADVICEONLY] = def.OFF
    yal.do_yal()
    assert(#yal.commandtable == 0 and yal.cruiseAltMismatchKey == nil,
        "actual background dispatch cancels pending advice when both modes are off")
end

os.time = realTime
print("test_cruise_altitude_guard: all checks passed")
