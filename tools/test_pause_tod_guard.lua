package.path = "data/modules/Custom Module/?.lua;" .. package.path

local guard = require("pause_tod_guard")

local function fail(message)
    error(message, 2)
end

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        fail(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, label)
    if value ~= true then fail(label .. ": expected true") end
end

local function assert_false(value, label)
    if value ~= false then fail(label .. ": expected false") end
end

local function copy(source, overrides)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local armBase = {
    pause_setting_on = true,
    airborne = true,
    in_cruise = true,
    tod_distance_nm = 7.9
}

local eligible, reason = guard.isArmEligible(armBase)
assert_true(eligible, "actual TOD pause arms")
assert_equal(reason, "tod-pause", "actual TOD pause reason")

eligible = guard.isArmEligible(copy(armBase, { monitor_active = false }))
assert_true(eligible, "TOD pause does not depend on the advice monitor")
eligible = guard.isArmEligible(copy(armBase, { tod_distance_nm = 9 }))
assert_false(eligible, "pause outside Zibo TOD window does not arm")
eligible = guard.isArmEligible(copy(armBase, { tod_distance_nm = 0 / 0 }))
assert_false(eligible, "invalid TOD value does not arm")
eligible = guard.isArmEligible(copy(armBase, { in_cruise = false }))
assert_false(eligible, "pause outside cruise does not arm")

assert_true(guard.isMcpDescentSelected(5000, 41000), "preselected descent MCP")
assert_true(guard.isMcpDescentSelected(40900, 41000), "MCP descent threshold is inclusive")
assert_false(guard.isMcpDescentSelected(40901, 41000), "MCP inside descent threshold")
assert_false(guard.isMcpDescentSelected(5000, 0), "invalid cruise altitude")
assert_false(guard.isMcpDescentSelected(0, 41000), "invalid MCP altitude")

local ownershipBase = {
    owned = true,
    pause_setting_on = false,
    airborne = true,
    flightstate = 3,
    cruise_flightstate = 3,
    fms_phase = 2,
    cruise_fms_phase = 2
}

assert_equal(guard.autoDisableOwnershipAction(ownershipBase), "hold",
    "temporary pause ownership survives reload in cruise")
assert_equal(guard.autoDisableOwnershipAction(copy(ownershipBase, { flightstate = 4 })), "restore",
    "temporary pause ownership restores after YAL leaves cruise")
assert_equal(guard.autoDisableOwnershipAction(copy(ownershipBase, { fms_phase = 5 })), "restore",
    "temporary pause ownership restores after FMS leaves cruise")
assert_equal(guard.autoDisableOwnershipAction(copy(ownershipBase, { airborne = false })), "restore",
    "temporary pause ownership restores on ground")
assert_equal(guard.autoDisableOwnershipAction(copy(ownershipBase, { pause_setting_on = true })), "clear",
    "manual pause setting restore clears ownership")
assert_equal(guard.autoDisableOwnershipAction(copy(ownershipBase, { owned = false })), "none",
    "unowned pause setting remains untouched")

local releaseBase = {
    now = 100,
    pause_setting_on = true,
    airborne = true,
    in_cruise = true,
    tod_distance_nm = 7.8,
    baseline_mcp_ft = 40000,
    current_mcp_ft = 40000,
    vertical_speed_fpm = 0
}

local action
action, reason = guard.evaluateRelease(releaseBase)
assert_equal(action, "repause", "unchanged cruise release is protected")
assert_equal(reason, "unchanged-cruise", "unchanged cruise release reason")

action, reason = guard.evaluateReleaseWithGrace(releaseBase)
assert_equal(action, "grace", "ambiguous first release starts grace period")
assert_equal(reason, "unchanged-cruise", "grace retains release reason")

action = guard.evaluateReleaseWithGrace(copy(releaseBase, {
    now = 109,
    grace_until = 110
}))
assert_equal(action, "grace", "ambiguous release remains unpaused inside grace period")

action = guard.evaluateReleaseWithGrace(copy(releaseBase, {
    now = 110,
    grace_until = 110
}))
assert_equal(action, "repause", "ambiguous release re-pauses at grace deadline")

action, reason = guard.evaluateReleaseWithGrace(copy(releaseBase, {
    now = 105,
    grace_until = 110,
    current_mcp_ft = 39900
}))
assert_equal(action, "accept", "lower MCP accepts release during grace period")
assert_equal(reason, "mcp-lowered", "grace MCP release reason")

action, reason = guard.evaluateRelease(copy(releaseBase, { confirm_until = 110 }))
assert_equal(action, "accept", "second release inside confirmation window")
assert_equal(reason, "confirmed-release", "confirmed release reason")

action, reason = guard.evaluateReleaseWithGrace(copy(releaseBase, { confirm_until = 110 }))
assert_equal(action, "accept", "confirmed second release bypasses grace period")
assert_equal(reason, "confirmed-release", "confirmed grace release reason")

action, reason = guard.evaluateRelease(copy(releaseBase, { current_mcp_ft = 39900 }))
assert_equal(action, "accept", "lower MCP accepts release")
assert_equal(reason, "mcp-lowered", "lower MCP reason")

action = guard.evaluateRelease(copy(releaseBase, { current_mcp_ft = 40100 }))
assert_equal(action, "repause", "higher MCP is not descent intent")

action, reason = guard.evaluateRelease(copy(releaseBase, {
    baseline_mcp_ft = 5000,
    current_mcp_ft = 5000,
    cruise_altitude_ft = 41000
}))
assert_equal(action, "accept", "preselected descent MCP accepts first release")
assert_equal(reason, "mcp-below-cruise", "preselected descent MCP reason")

action = guard.evaluateRelease(copy(releaseBase, { cruise_altitude_ft = 0 }))
assert_equal(action, "repause", "invalid cruise altitude does not bypass protection")

action, reason = guard.evaluateRelease(copy(releaseBase, { in_cruise = false }))
assert_equal(action, "accept", "descent phase accepts release")
assert_equal(reason, "left-cruise", "descent phase reason")

action, reason = guard.evaluateRelease(copy(releaseBase, { vertical_speed_fpm = -300 }))
assert_equal(action, "accept", "established descent accepts release")
assert_equal(reason, "descent-established", "established descent reason")

action, reason = guard.evaluateRelease(copy(releaseBase, { pause_setting_on = false }))
assert_equal(action, "accept", "disabled Pause at TOD accepts release")
assert_equal(reason, "pause-setting-off", "disabled Pause at TOD reason")

action, reason = guard.evaluateRelease(copy(releaseBase, { tod_distance_nm = -0.1 }))
assert_equal(action, "accept", "passed TOD accepts release")
assert_equal(reason, "tod-passed", "passed TOD reason")

action, reason = guard.evaluateRelease(copy(releaseBase, { tod_distance_nm = 1.9 }))
assert_equal(action, "accept", "release outside protected TOD window")
assert_equal(reason, "tod-context-changed", "changed TOD context reason")

action, reason = guard.evaluateRelease(copy(releaseBase, { tod_distance_nm = false }))
assert_equal(action, "accept", "invalid TOD fails open")
assert_equal(reason, "tod-invalid", "invalid TOD reason")

assert_true(guard.isNativeSaveLatched({
    expected_slot = 6,
    load_save = 1,
    load_save2 = 6
}), "native save request latch")
assert_false(guard.isNativeSaveLatched({
    expected_slot = 6,
    load_save = 1,
    load_save2 = 5
}), "native save wrong slot is rejected")

action, reason = guard.evaluateNativeSave({
    expected_slot = 6,
    requested_at = 100,
    now = 101,
    load_save = 1,
    load_save2 = 6,
    status = 0,
    status_slot = 0,
    error_code = 0
})
assert_equal(action, "wait", "native save pending")
assert_equal(reason, "save-pending", "native save pending reason")

action, reason = guard.evaluateNativeSave({
    expected_slot = 6,
    requested_at = 100,
    now = 102,
    load_save = 0,
    load_save2 = 0,
    status = 2,
    status_slot = 6,
    error_code = 0
})
assert_equal(action, "success", "native save completion")
assert_equal(reason, "save-complete", "native save completion reason")

action, reason = guard.evaluateNativeSave({
    expected_slot = 6,
    requested_at = 100,
    now = 110,
    load_save = 1,
    load_save2 = 6,
    status = 0,
    status_slot = 0,
    error_code = 0
})
assert_equal(action, "failed", "native save timeout")
assert_equal(reason, "save-timeout", "native save timeout reason")

action, reason = guard.evaluateNativeSave({
    expected_slot = 6,
    requested_at = 100,
    now = 102,
    load_save = 0,
    load_save2 = 0,
    status = -1,
    status_slot = 6,
    error_code = 4
})
assert_equal(action, "failed", "native save error")
assert_equal(reason, "save-status-mismatch", "native save error reason")

print("test_pause_tod_guard: all checks passed")
