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

-- Drive the real producer, adapter, mailbox validation and commit order together.
do
    local autoUnicom = require("auto_unicom")
    local writes, logs, apiRefs
    yal.fmctransalt, yal.fmsfplnnavid = "ta", "nav"
    yal.getAutoUnicomNavigationTarget = function() return refs.nav, false end
    yal.getAutoUnicomApproachContext = function() return {} end
    yal.isArrivalFinalEstablished = function() return false end
    yal.isArrivalShortFinal = function() return false end
    yal.getHoldRuntimeState = function() return { active = refs.holding == true } end
    local function setup(withVoice)
        reset(41000)
        refs.altitude, refs.legacy_altitude, refs.pressure, refs.vs = 40900, 40900, 40900, 400
        refs.cruise, refs.phase, refs.ta, refs.nav = 41000, def.FMSFLIGHTPHASE_CRUISE, 18000, "BIRCO"
        yal.flightstate = def.FLIGHTSTATECRUISE
        refs.api_version, refs.ready, refs.mode, refs.transport_state = 3, 1, 2, 4
        refs.effective_callsign = "DLH3210"
        refs.request_seq, refs.result_seq, refs.result_code = 10, 10, 21
        refs.voice_result_seq, refs.voice_result_code = 10, 20
        writes, logs, apiRefs = {}, {}, {}
        for _, name in ipairs({ "api_version", "ready", "mode", "transport_state", "effective_callsign",
            "request_text", "request_voice_text", "request_channels", "request_seq", "result_seq", "result_code",
            "voice_result_seq", "voice_result_code" }) do apiRefs[name] = name end
        autoUnicom.configure({
            yal = yal, def = def,
            helpers = {
                logInfoTS = function(message) logs[#logs + 1] = message end,
                spellNato = withVoice ~= false and function(value) return value end or nil
            },
            sources = { pressure_altitude = "pressure" },
            getRefs = function() return apiRefs end,
            read = function(prop) return refs[prop] end,
            writeText = function(prop, text)
                writes[#writes + 1] = { prop = prop, value = text }; refs[prop] = text; return true
            end,
            writeChannels = function(prop, channels)
                writes[#writes + 1] = { prop = prop, value = channels }; refs[prop] = channels; return true
            end,
            writeSeq = function(prop, seq)
                writes[#writes + 1] = { prop = prop, value = seq }; refs[prop] = seq; return true
            end
        })
        yal.setRuntimeEventSink(function(id, payload) return autoUnicom.handleYalEvent(id, payload, now) end)
        autoUnicom.tick(true, now)
        now = 1
        yal.updateAutoUnicomCruiseEvent()
        assert(yal.autoUnicomRuntime.cruiseInitialized and autoUnicom.getDebugState().queue_depth == 1,
            "real cruise producer latches local queue acceptance while transport waits")
        autoUnicom.tick(true, now)
        assert(#writes == 0, "not-ready transport has not externalized the entry")
    end
    local function advance(time)
        now = time
        yal.updateAutoUnicomCruiseEvent()
        autoUnicom.tick(true, now)
    end
    local function complete()
        refs.result_seq, refs.voice_result_seq = refs.request_seq, refs.request_seq
        refs.result_code, refs.voice_result_code = 21, 20
        autoUnicom.tick(true, now)
    end
    setup()
    refs.vs, refs.altitude, refs.legacy_altitude, refs.pressure = 200, 40980, 40980, 40980
    refs.transport_state = 5
    now = 2
    autoUnicom.tick(true, now)
    assert(#writes == 0 and autoUnicom.getDebugState().queue_depth == 0,
        "capture removes the stale reaching entry before any write")
    assert(not yal.autoUnicomRuntime.cruiseInitialized and yal.autoUnicomRuntime.cruiseLastReportAt == nil,
        "discarded uncommitted cruise entry rearms its actual producer")
    advance(3)
    assert(writes[1].value == "Lufthansa 3210 level at FL410, BIRCO next",
        "next producer cycle replaces reaching with current level-at wording")
    assert(writes[2].value:find("level at flight level fower one zero", 1, true), "replacement voice matches text")
    assert(writes[3].prop == "request_channels" and writes[4].prop == "request_seq" and writes[4].value == 11,
        "replacement uses ordinary text/voice/channels/sequence-last transaction")
    complete()
    advance(4)
    advance(602)
    assert(#writes == 4, "replacement is sent once and starts the unchanged ten-minute interval")
    advance(603)
    assert(#writes == 8 and writes[5].value == "Lufthansa 3210 maintaining FL410, BIRCO next",
        "normal periodic cruise report remains available after replacement")

    setup(false)
    refs.vs, refs.altitude, refs.legacy_altitude, refs.pressure = 200, 40980, 40980, 40980
    refs.transport_state = 5
    now = 2
    autoUnicom.tick(true, now)
    advance(3)
    assert(#writes == 3 and writes[1].value == "Lufthansa 3210 level at FL410, BIRCO next"
        and writes[2].value == 1 and writes[3].prop == "request_seq",
        "text-only producer follows the same replacement lifecycle without a voice payload")

    for _, change in ipairs({ "fmc", "mcp", "navigation" }) do
        setup()
        if change == "fmc" then
            refs.cruise, refs.mcp = 42000, 42000
        elseif change == "mcp" then
            refs.mcp = 40900
        else
            refs.nav = "SOMOR"
        end
        refs.transport_state = 5
        now = 2
        autoUnicom.tick(true, now)
        assert(#writes == 0 and not yal.autoUnicomRuntime.cruiseInitialized, "changed intention rearms unsent entry: " .. change)
        advance(3)
        local level = change == "fmc" and "420" or change == "mcp" and "409" or "410"
        local waypoint = change == "navigation" and "SOMOR" or "BIRCO"
        assert(writes[1].value == "Lufthansa 3210 reaching FL" .. level .. ", " .. waypoint .. " next",
            "replacement uses fresh target/navigation context: " .. change)
        complete()
        advance(4)
        assert(#writes == 4, "changed entry does not duplicate after commit: " .. change)
    end

    setup()
    refs.transport_state, refs.vs = 5, -500
    now = 2
    autoUnicom.tick(true, now)
    advance(3)
    assert(#writes == 0 and autoUnicom.getDebugState().queue_depth == 0,
        "descending cruise context cannot regenerate a fictional reaching-climb report")

    for _, change in ipairs({ "ground", "hold", "descent" }) do
        setup()
        refs.transport_state = 5
        if change == "ground" then
            refs.ground, yal.flightstate = def.ON, def.FLIGHTSTATETAXITOGATE
        elseif change == "hold" then
            refs.holding = true
        else
            refs.phase, yal.flightstate = def.FMSFLIGHTPHASE_DESCENT, def.FLIGHTSTATEAPPROACH
        end
        now = 2
        autoUnicom.tick(true, now)
        advance(3)
        assert(#writes == 0, "no replacement outside the existing cruise authority: " .. change)
    end

    setup()
    refs.transport_state = 5
    autoUnicom.tick(true, now)
    local committedText, committedVoice, committedSeq = refs.request_text, refs.request_voice_text, refs.request_seq
    refs.vs, refs.cruise, refs.mcp, refs.nav = 200, 42000, 42000, "SOMOR"
    refs.result_code = 10
    advance(2)
    assert(#writes == 4 and yal.autoUnicomRuntime.cruiseInitialized,
        "accepted transaction is never rearmed or rewritten on capture/target change")
    assert(refs.request_text == committedText and refs.request_voice_text == committedVoice and refs.request_seq == committedSeq,
        "committed mailbox text, voice and sequence stay immutable")
    complete()
    advance(3)
    assert(#writes == 4, "terminal result cannot replay a committed cruise entry")

    setup()
    refs.transport_state = 5
    autoUnicom.tick(true, now)
    complete()
    refs.transport_state = 4
    advance(601)
    assert(autoUnicom.getDebugState().queue_depth == 1, "periodic report waits normally")
    refs.nav, refs.transport_state = "SOMOR", 5
    now = 602
    autoUnicom.tick(true, now)
    assert(yal.autoUnicomRuntime.cruiseInitialized and yal.autoUnicomRuntime.cruiseLastReportAt == 601,
        "discarding a periodic report cannot recreate an already committed cruise entry")

    for _, clear in ipairs({ "disabled", "rebaseline", "reset" }) do
        setup()
        if clear == "disabled" then autoUnicom.tick(false, 2)
        elseif clear == "rebaseline" then autoUnicom.rebaseline()
        else autoUnicom.handleYalEvent("flight.reset", {}, 2) end
        assert(yal.autoUnicomRuntime.cruiseInitialized,
            "bulk lifecycle cleanup does not rearm an old producer: " .. clear)
        assert(#writes == 0 and autoUnicom.getDebugState().queue_depth == 0, "lifecycle cleanup remains local: " .. clear)
    end
    setup()
    autoUnicom.configure({ yal = yal, def = def, refs = {}, read = function(prop) return refs[prop] end })
    yal.autoUnicomRuntime.cruiseInitialized, yal.autoUnicomRuntime.cruiseLastReportAt = false, nil
    autoUnicom.tick(true, 2)
    yal.updateAutoUnicomCruiseEvent()
    assert(not yal.autoUnicomRuntime.cruiseInitialized and autoUnicom.getDebugState().queue_depth == 0,
        "upstream without an Auto-Unicom provider cannot consume or transmit an entry")
end

os.time = realTime
print("Auto-Unicom climb runtime tests PASS")
