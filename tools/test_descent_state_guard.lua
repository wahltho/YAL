package.path = "data/modules/Custom Module/?.lua;" .. package.path

local guard = require("descent_state_guard")

local function assertEqual(actual, expected, label)
    assert(actual == expected,
        string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function evaluateEvidence(overrides)
    local input = {
        vertical_speed_fpm = 0,
        altitude_ft = 26000,
        cruise_altitude_ft = 37000,
        strong_descent_fpm = -300,
        shallow_descent_fpm = -100,
        below_cruise_ft = 300
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return guard.evaluateDescentEvidence(input)
end

local evidence = evaluateEvidence({ vertical_speed_fpm = 362 })
assertEqual(evidence.active, false, "climb below cruise is not descent evidence")

evidence = evaluateEvidence({ vertical_speed_fpm = -99 })
assertEqual(evidence.active, false, "far-below-cruise level noise is not descent evidence")

evidence = evaluateEvidence({ vertical_speed_fpm = -100 })
assertEqual(evidence.active, true, "shallow descent below cruise is evidence")

evidence = evaluateEvidence({
    vertical_speed_fpm = -300,
    altitude_ft = 36900
})
assertEqual(evidence.active, true, "strong descent near cruise is evidence")

local function evaluateRecovery(overrides)
    local input = {
        aircraft_on_ground = false,
        restored_flightstate = 4,
        climb_flightstate = 2,
        cruise_flightstate = 3,
        approach_flightstate = 4,
        fms_phase = 2,
        fms_cruise_phase = 2,
        fms_climb_phase = 1,
        fms_crz_clb_phase = 3,
        vertical_speed_fpm = 362,
        altitude_ft = 26000,
        cruise_altitude_ft = 37000,
        strong_descent_fpm = -300,
        shallow_descent_fpm = -100,
        below_cruise_ft = 300,
        climb_recovery_fpm = 100,
        near_cruise_ft = 300,
        near_level_fpm = 100
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return guard.evaluateRestoreRecovery(input)
end

local recovery = evaluateRecovery()
assertEqual(recovery.recover, true, "remote stale descent state recovers while climbing")
assertEqual(recovery.reason, "climbing", "climbing recovery reason")

recovery = evaluateRecovery({
    vertical_speed_fpm = 0,
    altitude_ft = 36800
})
assertEqual(recovery.recover, true, "level flight near cruise recovers")
assertEqual(recovery.reason, "level-near-cruise", "near-cruise recovery reason")

recovery = evaluateRecovery({ vertical_speed_fpm = -500 })
assertEqual(recovery.recover, false, "actual descent is preserved")
assertEqual(recovery.reason, "actual-descent", "actual descent rejection reason")

recovery = evaluateRecovery({
    vertical_speed_fpm = 0,
    altitude_ft = 26000
})
assertEqual(recovery.recover, false, "ambiguous level flight below cruise is preserved")

recovery = evaluateRecovery({
    vertical_speed_fpm = -200,
    altitude_ft = 36800
})
assertEqual(recovery.recover, false, "near-cruise descent is preserved")

recovery = evaluateRecovery({ fms_phase = 5 })
assertEqual(recovery.recover, false, "non-cruise FMS phase blocks recovery")

recovery = evaluateRecovery({ aircraft_on_ground = true })
assertEqual(recovery.recover, false, "ground state blocks inflight recovery")

recovery = evaluateRecovery({ restored_flightstate = 2 })
assertEqual(recovery.recover, false, "climb restore state is not rewritten")

recovery = evaluateRecovery({
    restored_flightstate = 3,
    vertical_speed_fpm = -800,
    altitude_ft = 30000
})
assertEqual(recovery.recover, true, "existing restored-cruise cleanup remains available")
assertEqual(recovery.reason, "restored-cruise", "restored-cruise recovery reason")

for phase, state in pairs({ [1] = 2, [3] = 3 }) do
    recovery = evaluateRecovery({ fms_phase = phase })
    assertEqual(recovery.recover, true, "confirmed FMS climb releases stale approach")
    assertEqual(recovery.flightstate, state, "recovery returns the matching existing flight state")
    local pending = evaluateRecovery({ fms_phase = phase, vertical_speed_fpm = 0 })
    assertEqual(pending.pending, true, "climb level-off leaves existing recovery pending")
    assertEqual(evaluateRecovery({ fms_phase = phase, vertical_speed_fpm = -500 }).pending,
        false, "actual descent cannot retain a climb-recovery retry")
    for _, condition in ipairs({ { hold_active = true }, { go_around_active = true },
        { vertical_speed_fpm = 0 }, { vertical_speed_fpm = -500 }, { aircraft_on_ground = true } }) do
        condition.fms_phase = phase
        assertEqual(evaluateRecovery(condition).recover, false,
            "climb phase alone cannot undo a hold, GA, level-off or descent")
    end
end

-- Exercise both real baselines and the subsequent runtime cycles, not just the pure guard.
do
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
    PLUGINS_MENU_ID, LOG_DEBUG, LOG_INFO = 1, 10, 20

    local refs, events, baselines, finalEstablished = {}, {}, 0, false
    local realTime, now = os.time, 0
    os.time = function() return now end
    function get(ref, index)
        if index then return refs[ref] and refs[ref][index] end
        return refs[ref]
    end
    function set(ref, value, index)
        if index then
            refs[ref] = refs[ref] or {}
            refs[ref][index] = value
        else
            refs[ref] = value
        end
    end
    function globalProperty(path) return path end
    function isProperty(ref) return type(ref) == "string" and refs[ref] ~= nil end
    function createGlobalPropertyi(path, value) refs[path] = value; return path end
    createGlobalPropertyf, createGlobalPropertys = createGlobalPropertyi, createGlobalPropertyi
    function createGlobalPropertyia(path, size)
        local value = {}
        for index = 1, size do value[index] = 0 end
        refs[path] = value
        return path
    end
    helpers = {
        logInfoTS = function() end,
        forceCleanString = function(value) return tostring(value or "") end,
        checkCgBaselineAtStartup = function() end,
        checkDefaultViewAtStartup = function() end,
        tableToStringOrValue = function(value) return tostring(value) end,
        shallowcopy = function(source)
            local result = {}
            for key, value in pairs(source or {}) do result[key] = value end
            return result
        end,
        roundnumber = function(value) return math.floor(value + 0.5) end
    }
    package.loaded.helpers = helpers
    local def = require("definitions")
    local yal = require("yal")
    local procedures = require("proceduredata")
    local refdata = require("refdata")
    for _, name in ipairs({ "airgroundsensor", "altitude", "altitude_ft", "pressurealtitudeft",
        "verticalspeed", "fmccruisealt", "fmsflightphase", "vnavtoddist", "mcpaltitude",
        "flightstatedr", "ProcSetStatusarraydr" }) do yal[name] = name end
    yal.YalinitGlobal = function()
        yal.autoUnicomRuntime = { sent = {} }
        yal.loopStateTables = { { lock = def.NOPROCEDURE }, { lock = def.NOPROCEDURE } }
        yal.resetDescentTriggerState(true)
        yal.descentTriggerRestoreHoldUntil = nil
        yal.isReloadWithinSession = false
        yal.procedurelooptemplate = { lock = def.NOPROCEDURE, stepindex = 0, currentStepName = "" }
        yal.loopenginekeys = { lock = true, stepindex = true, currentStepName = true }
    end
    procedures.fillProcedureTable = function()
        yal.proceduretable = {
            [def.AFTERTAKEOFFPROCEDURE] = { number = 8, set = true },
            [def.DURINGDESCENTPROCEDURE] = { number = 11, set = false,
                requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH } },
            [def.ALTITUDEB10000PROCEDURE] = { number = 12, set = false,
                requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH } }
        }
    end
    yal.buildProcedureLabelMaps = function() end
    -- Keep the real persistent state/loop restore; stub only external aircraft bindings.
    yal.bindExternalDatarefs = function() return 0 end
    yal.ensureApuStartCommandHook = function() end
    yal.updateApuStartState = function() end
    refdata.initialize = function() end
    yal.readconfig = function() end
    yal.commandtableentry = function() end
    yal.updateAutoUnicomArrivalContext = function() end
    yal.updateAutoUnicomDepartureContext = function() end
    yal.getAutoUnicomFlightPlanContext = function() return nil end
    yal.getHoldRuntimeState = function()
        return { active = refs.hold_active == true, waypoint = "BIRCO", path_type = "HM" }
    end
    yal.getAutoUnicomNavigationTarget = function() return "BIRCO", false end
    yal.isArrivalFinalEstablished = function() return finalEstablished end
    yal.isArrivalShortFinal = function() return false end
    yal.resetLoopState = function(loop) loop.lock = def.NOPROCEDURE end
    yal.saveLoopState = function() end
    yal.clearProcedureQueuedSpeech = function() end
    yal.duringdescent = function() yal.updateAutoUnicomDescentEvents() end
    yal.duringclimb = function() end
    local baseline = yal.baselineAutoUnicomRuntimeEvents
    yal.baselineAutoUnicomRuntimeEvents = function()
        baselines = baselines + 1
        baseline()
    end
    yal.setRuntimeEventSink(function(id)
        events[#events + 1] = id
        return true
    end)
    local function count(id)
        local total = 0
        for _, event in ipairs(events) do if event == id then total = total + 1 end end
        return total
    end
    local function initialize(state, phase, altitude, vs, adviceOnly)
        events, baselines, finalEstablished, now = {}, 0, false, 0
        refs = {
            airgroundsensor = def.OFF, [def.APPNAMEPREFIX .. "/state/flightstate"] = state,
            [def.APPNAMEPREFIX .. "/state/procedureset"] = { [def.AFTERTAKEOFFPROCEDURE] = 1 },
            fmsflightphase = phase, altitude = altitude, altitude_ft = altitude,
            pressurealtitudeft = altitude - 389, verticalspeed = vs,
            fmccruisealt = 40000, mcpaltitude = 6000, vnavtoddist = -96.9
        }
        yal.configvalues = {
            [def.CONFIGAUTOFUNCTIONS] = adviceOnly and def.OFF or def.ON,
            [def.CONFIGVOICEADVICEONLY] = adviceOnly and def.ON or def.OFF
        }
        yal.initializeScript()
        assert(yal.isReloadWithinSession, "real initDataref recognizes existing persistent state")
        assertEqual(baselines, 1, "initialization establishes its baseline")
        assertEqual(yal.determineFlightStateFromProcedures(), def.FLIGHTSTATECRUISE,
            "fixture reproduces the minimum procedure-state inference")
    end
    local function tick(time)
        now = time
        yal.autofunctions()
    end

    for _, adviceOnly in ipairs({ false, true }) do
        initialize(def.FLIGHTSTATEAPPROACH, def.FMSFLIGHTPHASE_DESCENT, 11948.436523438, -756, adviceOnly)
        assert(yal.autoUnicomRuntime.sent["arrival.descent_entry"], "startup baseline consumes historical descent")
        tick(12)
        assertEqual(baselines, 2, "real restore establishes the second baseline")
        tick(22)
        assertEqual(yal.flightstate, def.FLIGHTSTATEAPPROACH, "reload retains established descent")
        assertEqual(refs[yal.flightstatedr], def.FLIGHTSTATEAPPROACH, "persisted state is not regressed")
        assertEqual(count("arrival.on_descent") + count("arrival.top_of_descent"), 0,
            "no false descent-start message after reload or the ten-second trigger window")
        refs.altitude, refs.altitude_ft, refs.pressurealtitudeft = 10000, 10000, 9611
        tick(30)
        assertEqual(count("arrival.approach"), 1, "future approach boundary is still reported")
        finalEstablished = true
        tick(35)
        tick(40)
        assertEqual(count("arrival.on_final"), 1, "future established-final report is retained")
    end

    for _, phase in ipairs({ def.FMSFLIGHTPHASE_CLIMB, def.FMSFLIGHTPHASE_CRZ_CLB }) do
        for _, adviceOnly in ipairs({ false, true }) do
            initialize(def.FLIGHTSTATEAPPROACH, phase, 26000, 362, adviceOnly)
            yal.proceduretable[def.DURINGDESCENTPROCEDURE].set = true
            yal.loopStateTables[2].lock = def.DURINGDESCENTPROCEDURE
            tick(12)
            local expected = phase == def.FMSFLIGHTPHASE_CLIMB and def.FLIGHTSTATECLIMB or def.FLIGHTSTATECRUISE
            assertEqual(yal.flightstate, expected, "loaded climbing situation releases old approach state")
            assertEqual(refs[yal.flightstatedr], expected, "recovered flight state is persisted")
            assertEqual(yal.loopStateTables[2].lock, def.NOPROCEDURE, "climb recovery clears stale descent loop")
            assertEqual(yal.proceduretable[def.DURINGDESCENTPROCEDURE].set, false, "climb recovery clears descent flag")
            assert(not yal.autoUnicomRuntime.sent["arrival.descent_entry"], "new descent is not consumed by old arrival baseline")
            refs.fmsflightphase, refs.verticalspeed = def.FMSFLIGHTPHASE_CRUISE, 0
            refs.altitude, refs.altitude_ft = 40000, 40000
            tick(20)
            assertEqual(yal.flightstate, def.FLIGHTSTATECRUISE, "normal cruise remains reachable")
            yal.updateAutoUnicomCruiseEvent()
            assertEqual(count("enroute.in_cruise"), 1, "new cruise entry can be reported")
            refs.fmsflightphase, refs.verticalspeed = def.FMSFLIGHTPHASE_DESCENT, -756
            tick(60)
            tick(70)
            tick(71)
            assertEqual(count("arrival.on_descent"), 1, "genuine later descent remains reportable once")
        end
        for _, protection in ipairs({ "hold_active", "go_around_active" }) do
            initialize(def.FLIGHTSTATEAPPROACH, phase, 26000, 362)
            if protection == "hold_active" then
                refs.hold_active = true
            else
                yal.loopStateTables[1] = { lock = def.GOAROUNDPROCEDURE, stepindex = 1 }
            end
            tick(12)
            assertEqual(yal.flightstate, def.FLIGHTSTATEAPPROACH, "existing hold/accepted GA retains arrival ownership")
        end
    end

    for _, phase in ipairs({ def.FMSFLIGHTPHASE_CLIMB, def.FMSFLIGHTPHASE_CRZ_CLB }) do
        for _, adviceOnly in ipairs({ false, true }) do
            initialize(def.FLIGHTSTATEAPPROACH, phase, 26000, 0, adviceOnly)
            tick(12)
            assertEqual(yal.flightstate, def.FLIGHTSTATEAPPROACH, "level-off alone does not release arrival ownership")
            assertEqual(yal.staleDescentRestorePending, true, "existing recovery waits for confirmed climb")
            assertEqual(yal.isReloadWithinSession, false, "full restore still runs only once")
            tick(20)
            assertEqual(baselines, 2, "waiting does not repeat restore or baseline")
            refs.verticalspeed = 800
            refs.altitude, refs.altitude_ft = 26100, 26100
            tick(22)
            local expected = phase == def.FMSFLIGHTPHASE_CLIMB and def.FLIGHTSTATECLIMB or def.FLIGHTSTATECRUISE
            assertEqual(yal.flightstate, expected, "resumed climb resolves the pending restored state")
            assertEqual(refs[yal.flightstatedr], expected, "delayed recovery is persisted")
            assertEqual(yal.staleDescentRestorePending, false, "successful retry retires restore ownership")
            assertEqual(baselines, 3, "resolved climb replaces the historical arrival baseline once")
            assert(not yal.autoUnicomRuntime.sent["arrival.descent_entry"], "future descent remains available")
            tick(23)
            assertEqual(baselines, 3, "resolved restore does not run again")
            refs.fmsflightphase, refs.verticalspeed = def.FMSFLIGHTPHASE_CRUISE, 0
            refs.altitude, refs.altitude_ft = 40000, 40000
            tick(30)
            assertEqual(yal.flightstate, def.FLIGHTSTATECRUISE, "cruise is reachable after level-off recovery")
            refs.fmsflightphase, refs.verticalspeed = def.FMSFLIGHTPHASE_DESCENT, -800
            tick(60)
            tick(70)
            tick(71)
            assertEqual(count("arrival.on_descent"), 1, "later real descent is neither consumed nor replayed")
        end
    end
    for _, protection in ipairs({ "hold", "go-around", "descent" }) do
        initialize(def.FLIGHTSTATEAPPROACH, def.FMSFLIGHTPHASE_CLIMB, 26000, 0)
        tick(12)
        assert(yal.staleDescentRestorePending, "fixture starts with an unresolved climb level-off")
        refs.verticalspeed = 800
        if protection == "hold" then refs.hold_active = true
        elseif protection == "go-around" then
            yal.loopStateTables[1] = { lock = def.GOAROUNDPROCEDURE, stepindex = 1 }
        else refs.fmsflightphase, refs.verticalspeed = def.FMSFLIGHTPHASE_DESCENT, -800 end
        tick(20)
        assertEqual(yal.staleDescentRestorePending, false, "definite arrival owner cancels pending recovery: " .. protection)
        assertEqual(yal.flightstate, def.FLIGHTSTATEAPPROACH, "existing arrival authority is preserved: " .. protection)
    end

    for _, flightpath in ipairs({
        { def.FMSFLIGHTPHASE_DESCENT, 12000, 0 },
        { def.FMSFLIGHTPHASE_CRUISE, 26000, -500 },
        { def.FMSFLIGHTPHASE_CRUISE, 26000, 0 },
        { def.FMSFLIGHTPHASE_GO_AROUND, 6000, 1500 }
    }) do
        initialize(def.FLIGHTSTATEAPPROACH, flightpath[1], flightpath[2], flightpath[3])
        tick(12)
        tick(22)
        assertEqual(yal.flightstate, def.FLIGHTSTATEAPPROACH, "existing conservative recovery remains authoritative")
        assertEqual(count("arrival.on_descent") + count("arrival.top_of_descent") + count("arrival.go_around"), 0,
            "level-off, ambiguous flightpath and active missed approach do not replay historical events")
    end

    for _, flightpath in ipairs({ { 39800, 0 }, { 26000, 362 } }) do
        initialize(def.FLIGHTSTATEAPPROACH, def.FMSFLIGHTPHASE_CRUISE, flightpath[1], flightpath[2])
        yal.proceduretable[def.DURINGDESCENTPROCEDURE].set = true
        yal.loopStateTables[2].lock = def.DURINGDESCENTPROCEDURE
        tick(12)
        assertEqual(yal.flightstate, def.FLIGHTSTATECRUISE, "confirmed stale descent still recovers")
        assertEqual(yal.loopStateTables[2].lock, def.NOPROCEDURE, "stale descent loop is cleared")
        assertEqual(yal.proceduretable[def.DURINGDESCENTPROCEDURE].set, false, "stale procedure flag is cleared")
        assert(yal.descentTriggerRestoreHoldUntil > now, "existing restore guard stays armed")
    end

    initialize(def.FLIGHTSTATECRUISE, def.FMSFLIGHTPHASE_CRUISE, 40000, 0)
    tick(12)
    refs.fmsflightphase, refs.verticalspeed = def.FMSFLIGHTPHASE_DESCENT, -756
    refs.altitude, refs.altitude_ft = 39985, 39985
    tick(20)
    tick(30)
    tick(31)
    assertEqual(count("arrival.on_descent"), 1, "real new descent after a cruise reload is reported exactly once")
    os.time = realTime
end

print("test_descent_state_guard: all checks passed")
