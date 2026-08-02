package.path = "data/modules/Custom Module/?.lua;" .. package.path

local guard = require("route_warning_guard")

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)), 2)
    end
end

local function evaluate(overrides)
    local input = {
        eligible = true,
        tod_distance_nm = 95,
        destination_distance_nm = 145,
        remaining_distance_nm = 65,
        on_route = true,
        previous_tod_distance_nm = 100,
        previous_destination_distance_nm = 150,
        previous_reference_distance_nm = 70,
        warning_diff_nm = 20,
        reset_diff_nm = 10,
        max_rise_nm = 1
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return guard.evaluatePositiveTodSample(input)
end

local result = evaluate()
assert_equal(result.status, "candidate", "stable decreasing route shortfall")
assert_equal(result.reason, "stable-route-shortfall", "stable route shortfall reason")
assert_equal(result.diff_nm, 30, "stable route shortfall difference")

result = evaluate({
    tod_distance_nm = 654.109,
    destination_distance_nm = 774.639,
    remaining_distance_nm = 641.233,
    previous_tod_distance_nm = 649.5,
    previous_destination_distance_nm = 770,
    previous_reference_distance_nm = 636.8
})
assert_equal(result.status, "hold", "remote false positive remains below hardened difference")
assert_equal(result.reason, "difference-below-warning", "remote difference suppression reason")

result = evaluate({
    tod_distance_nm = 654.109,
    destination_distance_nm = 774.639,
    remaining_distance_nm = 620,
    previous_tod_distance_nm = 649.5,
    previous_destination_distance_nm = 770,
    previous_reference_distance_nm = 616
})
assert_equal(result.status, "reset", "increasing remote FMS distances invalidate a larger shortfall")
assert_equal(result.reason, "tod-increasing", "increasing TOD suppression reason")

result = evaluate({ previous_tod_distance_nm = false })
assert_equal(result.status, "baseline", "first bad sample establishes trend baseline")

result = evaluate({ tod_distance_nm = 74, remaining_distance_nm = 65 })
assert_equal(result.status, "clear", "small difference clears warning latch")

result = evaluate({ eligible = false })
assert_equal(result.status, "reset", "non-cruise context resets candidate")

result = evaluate({ destination_distance_nm = 0 })
assert_equal(result.status, "reset", "invalid destination distance is rejected")

result = evaluate({
    on_route = false,
    remaining_distance_nm = nil,
    tod_distance_nm = 170,
    destination_distance_nm = 140,
    previous_tod_distance_nm = 175,
    previous_destination_distance_nm = 145,
    previous_reference_distance_nm = 145
})
assert_equal(result.status, "candidate", "destination distance remains the off-route fallback")
assert_equal(result.reference_distance_nm, 140, "off-route fallback reference")

print("test_route_warning_guard: all checks passed")
