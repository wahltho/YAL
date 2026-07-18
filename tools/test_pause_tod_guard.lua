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
    monitor_active = true,
    pause_setting_on = true,
    airborne = true,
    in_cruise = true,
    tod_distance_nm = 7.9
}

local eligible, reason = guard.isArmEligible(armBase)
assert_true(eligible, "actual TOD pause arms")
assert_equal(reason, "tod-pause", "actual TOD pause reason")

eligible = guard.isArmEligible(copy(armBase, { monitor_active = false }))
assert_false(eligible, "inactive YAL TOD monitor does not arm")
eligible = guard.isArmEligible(copy(armBase, { tod_distance_nm = 9 }))
assert_false(eligible, "pause outside Zibo TOD window does not arm")
eligible = guard.isArmEligible(copy(armBase, { in_cruise = false }))
assert_false(eligible, "pause outside cruise does not arm")

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

action, reason = guard.evaluateRelease(copy(releaseBase, { confirm_until = 110 }))
assert_equal(action, "accept", "second release inside confirmation window")
assert_equal(reason, "confirmed-release", "confirmed release reason")

action, reason = guard.evaluateRelease(copy(releaseBase, { current_mcp_ft = 39900 }))
assert_equal(action, "accept", "lower MCP accepts release")
assert_equal(reason, "mcp-lowered", "lower MCP reason")

action = guard.evaluateRelease(copy(releaseBase, { current_mcp_ft = 40100 }))
assert_equal(action, "repause", "higher MCP is not descent intent")

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

action, reason = guard.evaluateRelease(copy(releaseBase, { tod_distance_nm = false }))
assert_equal(action, "accept", "invalid TOD fails open")
assert_equal(reason, "tod-invalid", "invalid TOD reason")

print("test_pause_tod_guard: all checks passed")
