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
        cruise_flightstate = 3,
        approach_flightstate = 4,
        fms_phase = 2,
        fms_cruise_phase = 2,
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

print("test_descent_state_guard: all checks passed")
