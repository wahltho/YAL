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

local commands = {}
helpers = {
    logInfoTS = function() end,
    command_once = function(command)
        commands[#commands + 1] = command
        if command == "laminar/B738/toggle_switch/eng1_heat" then refs.eng1 = 1 - refs.eng1 end
        if command == "laminar/B738/toggle_switch/eng2_heat" then refs.eng2 = 1 - refs.eng2 end
        if command == "laminar/B738/toggle_switch/wing_heat" then refs.wing = 1 - refs.wing end
    end
}
package.loaded.helpers = helpers
local def = require("definitions")
local yal = require("yal")
local antiIceCallbacks = {
    queue = yal.queueAntiIceAdvice,
    clear = yal.clearAntiIceSpeech,
    reset = yal.resetAntiIceAdviceState
}

local names = {
    airgroundsensor = "airground", totalflighttimesec = "time",
    aircraftcloudcoverage1 = "coverage1", aircraftcloudcoverage2 = "coverage2",
    aircraftcloudcoverage3 = "coverage3", aircraftcloudbase1 = "base1",
    aircraftcloudbase2 = "base2", aircraftcloudbase3 = "base3",
    aircraftcloudtop1 = "top1", aircraftcloudtop2 = "top2",
    aircraftcloudtop3 = "top3", elevation = "elevation",
    fmsflightphase = "phase", aircraftprecipitation = "precipitation",
    aircraftsnow = "snow", aircrafthail = "hail",
    aircraftvisibilitysm = "visibility", radioaltitude = "agl",
    frameice = "iceleft", frameice2 = "iceright", icedelta = "icedelta",
    tatdegc = "tat", satdegc = "sat", verticalspeed = "vvi",
    pressurealtitudeft = "pressurealt", eng1n1percent = "n1left", eng2n1percent = "n1right",
    eng1heatpos = "eng1",
    eng2heatpos = "eng2", wingheatpos = "wing"
}
for field, ref in pairs(names) do yal[field] = ref end
refs.airground = def.OFF
refs.phase = def.FMSFLIGHTPHASE_DESCENT
refs.coverage1 = 0.8
refs.base1 = 200
refs.top1 = 1050
refs.elevation = 1600
refs.vvi = -1200
refs.tat = 5
refs.sat = -5
refs.agl = 5200
refs.pressurealt = 5200
refs.precipitation = 0
refs.snow = 0
refs.hail = 0
refs.visibility = 10
refs.iceleft = 0
refs.iceright = 0
refs.icedelta = 0
refs.eng1 = def.OFF
refs.eng2 = def.OFF
refs.wing = def.OFF

yal.antiIceTemperatureAltitudeRefs = {}
yal.antiIceTemperatureAloftRefs = {}
for index = 1, 6 do
    local altitudeRef = "alt" .. index
    local temperatureRef = "temp" .. index
    yal.antiIceTemperatureAltitudeRefs[index] = altitudeRef
    yal.antiIceTemperatureAloftRefs[index] = temperatureRef
    refs[altitudeRef] = (index - 1) * 1000
    refs[temperatureRef] = -5
end

yal.flightstate = def.FLIGHTSTATEAPPROACH
yal.configvalues = {
    [def.CONFIGAUTOANTIICE] = def.ON,
    [def.CONFIGAUTOFUNCTIONS] = def.ON,
    [def.CONFIGVOICEADVICEONLY] = def.OFF
}
yal.commandtableentry = function() end
yal.clearYalQueuedSpeech = function() end
yal.clearAntiIceSpeech = function() end

refs.time = 0
yal.updateAntiIce()
refs.time = 15
yal.updateAntiIce()
assert(#commands == 2, "auto mode turns on both engine anti-ice switches before the layer")
refs.time = 16
yal.updateAntiIce()
assert(#commands == 2, "auto mode does not repeat commands once switches match")

yal.configvalues[def.CONFIGAUTOFUNCTIONS] = def.OFF
yal.configvalues[def.CONFIGVOICEADVICEONLY] = def.ON
yal.antiIceRuntime = nil
yal.antiIceWeatherProfileAt = nil
yal.antiIceAdviceState = { engine = {}, wing = {} }
refs.eng1 = def.OFF
refs.eng2 = def.OFF
local advice = {}
yal.queueAntiIceAdvice = function(system, stateName, text)
    advice[#advice + 1] = { system = system, state = stateName, text = text }
end
yal.resetAntiIceAdviceState = function() end
refs.time = 100
yal.updateAntiIce()
refs.time = 115
yal.updateAntiIce()
assert(#commands == 2, "voice advice mode never moves the switches")
assert(#advice == 1 and advice[1].system == "engine" and advice[1].state == "on",
    "voice advice mode announces the anticipated icing layer")

yal.antiIceRuntime = nil
yal.antiIceWeatherProfileAt = nil
refs.elevation = 600
refs.agl = 2000
refs.base1 = 0
refs.top1 = 1000
refs.time = 200
yal.updateAntiIce()
refs.time = 215
yal.updateAntiIce()
assert(#advice == 2 and advice[2].state == "on",
    "current icing below 2500 feet remains actionable in voice mode")

yal.queueAntiIceAdvice = antiIceCallbacks.queue
yal.clearAntiIceSpeech = antiIceCallbacks.clear
yal.resetAntiIceAdviceState = antiIceCallbacks.reset

local queued, history = {}, {}
yal.commandtableentry = function(_, text, key)
    queued[key] = text
    history[#history + 1] = { key = key, text = text }
end
yal.clearYalQueuedSpeech = function(key) queued[key] = nil end

local function wingCommandCount()
    local count = 0
    for _, command in ipairs(commands) do
        if command == "laminar/B738/toggle_switch/wing_heat" then count = count + 1 end
    end
    return count
end

local function wingOffSpeechCount()
    local count = 0
    for _, entry in ipairs(history) do
        if entry.key == "advice:anti_ice:wing:off" or entry.key == "status:anti_ice:wing:off" then
            count = count + 1
        end
    end
    return count
end

local function tick(now)
    refs.time = now
    yal.updateAntiIce()
end

for _, adviceMode in ipairs({ false, true }) do
    commands, queued, history = {}, {}, {}
    yal.antiIceRuntime = nil
    yal.antiIceWeatherProfileAt = nil
    yal.antiIceAdviceState = { engine = {}, wing = {} }
    yal.antiIceLastEngineCommandAt = nil
    yal.antiIceLastWingCommandAt = nil
    yal.antiIceWingInhibitWarnedReason = nil
    yal.configvalues[def.CONFIGAUTOFUNCTIONS] = adviceMode and def.OFF or def.ON
    yal.configvalues[def.CONFIGVOICEADVICEONLY] = adviceMode and def.ON or def.OFF
    refs.elevation = 3000
    refs.vvi = -1000
    refs.agl = 9000
    refs.pressurealt = 10000
    refs.coverage1 = 0.8
    refs.base1 = 0
    refs.top1 = 5000
    refs.eng1, refs.eng2 = def.ON, def.ON
    refs.wing = def.OFF
    refs.iceleft, refs.iceright, refs.icedelta = 0.0141, 0, 0.0005336
    tick(0)
    assert(wingCommandCount() == 0 and next(queued) == nil,
        "no wing action or advice before confirmed structural ice")
    tick(6)
    assert(yal.antiIceRuntime.wing_demand == true, "adapter publishes confirmed structural Wing ON")
    if adviceMode then
        assert(wingCommandCount() == 0 and queued["advice:anti_ice:wing:on"] ~= nil,
            "real advice path queues Wing ON without moving the switch")
        refs.wing = def.ON
        tick(8)
        assert(queued["advice:anti_ice:wing:on"] == nil,
            "pilot response clears the satisfied Wing ON advice")
    else
        assert(wingCommandCount() == 1 and refs.wing == def.ON,
            "auto path sets Wing ON exactly once")
    end
    refs.iceleft, refs.icedelta = 0, 0.0001402
    tick(10)
    tick(40)
    assert(yal.antiIceRuntime.structural_active == false,
        "measured ice can clear while protection is working")
    tick(200)
    assert(yal.antiIceRuntime.wing_demand == true and wingOffSpeechCount() == 0,
        "ice removal in current icing produces no Wing OFF command or speech")

    refs.icedelta = -0.0001
    refs.elevation, refs.vvi = 1600, -1200
    refs.base1, refs.top1 = 200, 1050
    tick(201)
    tick(301)
    assert(yal.antiIceRuntime.wing_demand == true and wingOffSpeechCount() == 0,
        "actual adapter lookahead bridges the gap before another icing layer")
    refs.coverage1 = 0
    tick(302)
    tick(421)
    assert(yal.antiIceRuntime.wing_demand == true and wingOffSpeechCount() == 0,
        "adapter holds Wing ON for the full 120-second clear interval")
    queued["advice:anti_ice:wing:on"] = "obsolete wing ON"
    tick(422)
    assert(yal.antiIceRuntime.wing_demand == false and wingOffSpeechCount() == 1,
        "adapter publishes one normal Wing OFF only after the clear interval")
    assert(queued["advice:anti_ice:wing:on"] == nil and queued["status:anti_ice:wing:on"] == nil,
        "OFF transition removes obsolete keyed Wing ON speech")
    if adviceMode then
        assert(wingCommandCount() == 0 and refs.wing == def.ON
            and queued["advice:anti_ice:wing:off"] == "Wing ice cleared. Set wing anti ice off.",
            "real voice mode requests Wing OFF without executing it")
    else
        assert(wingCommandCount() == 2 and refs.wing == def.OFF,
            "auto mode executes exactly one Wing ON and one final Wing OFF")
    end
end

for _, adviceMode in ipairs({ false, true }) do
    commands, queued, history = {}, {}, {}
    yal.antiIceRuntime = nil
    yal.antiIceWeatherProfileAt = nil
    yal.antiIceAdviceState = { engine = {}, wing = {} }
    yal.antiIceLastEngineCommandAt = nil
    yal.antiIceLastWingCommandAt = nil
    yal.configvalues[def.CONFIGAUTOFUNCTIONS] = adviceMode and def.OFF or def.ON
    yal.configvalues[def.CONFIGVOICEADVICEONLY] = adviceMode and def.ON or def.OFF
    yal.flightstate = def.FLIGHTSTATEPREFLIGHT
    refs.airground = def.ON
    refs.n1left, refs.n1right = 0, 0
    refs.eng1, refs.eng2, refs.wing = def.OFF, def.OFF, def.OFF
    refs.elevation, refs.agl, refs.pressurealt = 200, -1, 650
    refs.tat, refs.sat, refs.vvi = 15, 5, 0
    refs.precipitation, refs.visibility = 0.1, 10
    refs.iceleft, refs.iceright, refs.icedelta = 0, 0, 0
    refs.coverage1 = 0
    tick(0)
    tick(30)
    assert(#commands == 0 and next(queued) == nil,
        "cold/dark and APU-only preparation never requests engine anti-ice")
    refs.n1right = 20
    tick(31)
    tick(60)
    assert(#commands == 0 and next(queued) == nil,
        "one completed engine start does not replace the both-engines-running authority")

    refs.n1left = 20
    tick(61)
    tick(75)
    assert(#commands == 0 and next(queued) == nil,
        "ground icing completes the existing ON confirmation interval")
    tick(76)
    assert(yal.antiIceRuntime.engine_demand == true,
        "real adapter uses ground OAT rather than warmer TAT and needs no bleed-switch gate")
    assert(wingCommandCount() == 0 and yal.antiIceRuntime.wing_demand == nil,
        "ground engine protection never requests Wing anti-ice")
    if adviceMode then
        assert(#commands == 0 and queued["advice:anti_ice:engine:on"] ~= nil,
            "Advice mode requests engine anti-ice before taxi without switch movement")
        refs.eng1, refs.eng2 = def.ON, def.ON
        tick(77)
        assert(queued["advice:anti_ice:engine:on"] == nil,
            "actual pilot response clears the ground Engine ON advice")
    else
        assert(#commands == 2 and refs.eng1 == def.ON and refs.eng2 == def.ON,
            "Auto mode switches only both engine anti-ice systems ON before taxi")
    end
    refs.airground, refs.tat, refs.agl = def.OFF, 5, 100
    refs.phase = def.FMSFLIGHTPHASE_CLIMB
    yal.flightstate = def.FLIGHTSTATEINITIALCLIMB
    local beforeTakeoffSpeech = #history
    tick(78)
    assert(yal.antiIceRuntime.engine_demand == true and #history == beforeTakeoffSpeech,
        "takeoff keeps the established engine demand without a duplicate instruction")

    refs.airground, refs.agl = def.ON, 0
    yal.flightstate = def.FLIGHTSTATEAFTERLANDING
    tick(100)
    assert(yal.antiIceRuntime.engine_demand == true,
        "actual landing does not discard required engine protection")
    refs.precipitation = 0
    tick(101)
    tick(131)
    tick(160)
    assert(yal.antiIceRuntime.engine_demand == true,
        "ground clear conditions cannot prematurely turn engine protection OFF")
    queued["advice:anti_ice:engine:on"] = "obsolete engine ON"
    tick(161)
    assert(yal.antiIceRuntime.engine_demand == false
        and queued["advice:anti_ice:engine:on"] == nil,
        "ground OFF transition clears obsolete Engine ON speech")
    if adviceMode then
        assert(#commands == 0 and queued["advice:anti_ice:engine:off"] ~= nil,
            "Advice mode requests OFF only after the clear latch")
    else
        assert(#commands == 4 and refs.eng1 == def.OFF and refs.eng2 == def.OFF,
            "Auto mode completes one engine ON/OFF cycle without touching Wing")
    end
    refs.n1left, refs.n1right = 0, 0
    tick(162)
    assert(yal.antiIceRuntime.engine_demand == nil and next(queued) == nil,
        "shutdown resets the shared owner and removes old ground advice")
end

for _, adviceMode in ipairs({ false, true }) do
    commands, queued, history = {}, {}, {}
    yal.antiIceRuntime = nil
    yal.antiIceWeatherProfileAt = nil
    yal.antiIceAdviceState = { engine = {}, wing = {} }
    yal.antiIceLastEngineCommandAt = nil
    yal.antiIceLastWingCommandAt = nil
    yal.configvalues[def.CONFIGAUTOFUNCTIONS] = adviceMode and def.OFF or def.ON
    yal.configvalues[def.CONFIGVOICEADVICEONLY] = adviceMode and def.ON or def.OFF
    yal.flightstate = def.FLIGHTSTATEAFTERLANDING
    refs.airground = def.ON
    refs.n1left, refs.n1right = 20, 20
    refs.eng1, refs.eng2, refs.wing = def.OFF, def.OFF, def.OFF
    refs.tat, refs.sat, refs.vvi, refs.agl = -4.4, -4.4, 0, 0
    refs.coverage1, refs.precipitation, refs.hail = 0, 0, 0
    refs.visibility, refs.snow = 7.41, 0.0129
    refs.iceleft, refs.iceright, refs.icedelta = 0, 0, 0
    tick(0)
    tick(15)
    assert(yal.antiIceRuntime.engine_demand == true, "snow starts ground protection through the real adapter")
    if adviceMode then
        assert(queued["advice:anti_ice:engine:on"] ~= nil and #commands == 0,
            "snow ON advice follows the normal Voice Advice Only path")
        refs.eng1, refs.eng2 = def.ON, def.ON
        tick(16)
    end
    local initialCommands, initialSpeech = #commands, #history
    for index, ratio in ipairs({ 0.0065, 0.0101, 0.0099, 0.0107, 0.0129, 0.0054, 0.0103, 0.0118 }) do
        refs.snow = ratio
        for _, offset in ipairs({ 1, 31, 61, 90 }) do
            tick(16 + (index - 1) * 90 + offset)
            assert(yal.antiIceRuntime.engine_demand == true
                and refs.eng1 == def.ON and refs.eng2 == def.ON,
                "recorded ground snow oscillations cannot reverse the engine demand or switches")
            assert(#commands == initialCommands and #history == initialSpeech,
                "matching engine switches produce no extra commands or contradictory speech")
            assert(wingCommandCount() == 0 and yal.antiIceRuntime.wing_demand == nil,
                "ground snow never leaks into the Wing adapter")
        end
    end
    refs.snow = 0.003
    tick(737)
    tick(767)
    tick(796)
    assert(yal.antiIceRuntime.engine_demand == true, "actual adapter retains the full clear delay")
    queued["advice:anti_ice:engine:on"] = "obsolete snow ON"
    tick(797)
    assert(yal.antiIceRuntime.engine_demand == false and queued["advice:anti_ice:engine:on"] == nil,
        "one confirmed clear transition removes obsolete Engine ON speech")
    if adviceMode then
        assert(#commands == 0 and queued["advice:anti_ice:engine:off"] ~= nil,
            "ground snow clearing advises OFF without moving either engine switch")
    else
        assert(#commands == 4 and refs.eng1 == def.OFF and refs.eng2 == def.OFF,
            "ground snow has one ON and one final OFF command per engine")
    end
    refs.eng1, refs.eng2 = def.OFF, def.OFF
    tick(798)
    refs.snow = 0.0099
    local afterClearCommands, afterClearSpeech = #commands, #history
    tick(800)
    tick(890)
    assert(yal.antiIceRuntime.engine_demand == false
        and #commands == afterClearCommands and #history == afterClearSpeech,
        "post-clear snow inside the hysteresis band cannot re-trigger commands or speech")
end

commands, queued, history = {}, {}, {}
yal.antiIceRuntime = nil
yal.antiIceWeatherProfileAt = nil
yal.antiIceAdviceState = { engine = {}, wing = {} }
yal.configvalues[def.CONFIGAUTOFUNCTIONS] = def.OFF
yal.configvalues[def.CONFIGVOICEADVICEONLY] = def.ON
refs.airground, refs.tat, refs.sat, refs.agl = def.OFF, 5, 5, 3000
refs.iceleft, refs.iceright, refs.icedelta = 0, 0.02, 0
refs.eng1, refs.eng2, refs.wing = def.OFF, def.OFF, def.OFF
refs.n1left, refs.n1right = 20, 20
tick(200)
tick(206)
assert(queued["advice:anti_ice:wing:on"] ~= nil, "airborne Wing advice exists before landing")
refs.airground, refs.agl = def.ON, 0
tick(207)
assert(queued["advice:anti_ice:wing:on"] == nil and #commands == 0,
    "landing removes obsolete Wing speech without a combined ground switch command")
refs.wing = def.ON
yal.configvalues[def.CONFIGAUTOFUNCTIONS] = def.ON
yal.configvalues[def.CONFIGVOICEADVICEONLY] = def.OFF
tick(208)
assert(refs.wing == def.ON and wingCommandCount() == 0,
    "a manually selected ground Wing switch is outside the Engine owner's authority")
queued["advice:anti_ice:engine:on"] = "obsolete engine ON"
yal.configvalues[def.CONFIGAUTOANTIICE] = def.OFF
tick(209)
assert(next(queued) == nil and #commands == 0,
    "disabling ground protection clears stale advice without moving any switch")

-- The old rotating ground task must no longer act as a second Engine/Wing owner.
commands, queued, history = {}, {}, {}
yal.configvalues[def.CONFIGAUTOANTIICE] = def.ON
yal.ongoingcoretaskindex = 4
yal.iceprotection = function() error("obsolete combined ground anti-ice owner") end
yal.runOneCoreOngoingTask()
assert(yal.ongoingcoretaskindex == 5 and #commands == 0 and next(queued) == nil,
    "reserved ground-task slot preserves the other task cadence without anti-ice actions")

print("test_anti_ice_adapter: all checks passed")
