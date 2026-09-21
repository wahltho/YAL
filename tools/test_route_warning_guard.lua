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

local function evaluate_arrival_setup(overrides)
    local input = {
        approach_source_available = true,
        destination_valid = true,
        runway_valid = true,
        approach_selected = false,
        missing_for_sec = 10,
        stable_sec = 8,
        pre_tod_eligible = true,
        post_tod_eligible = false,
        tod_distance_nm = 75,
        ground_speed_kt = 450,
        early_tod_min = 10,
        early_tod_fallback_nm = 75,
        final_tod_nm = 30,
        early_warned = false,
        final_warned = false,
        fallback_warned = false
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return guard.evaluateArrivalSetup(input)
end

result = evaluate_arrival_setup()
assert_equal(result.status, "warning", "missing approach triggers at ten minutes to TOD")
assert_equal(result.stage, "early", "ten-minute reminder uses early stage")
assert_equal(result.missing_kind, "approach", "missing approach is identified directly")

result = evaluate_arrival_setup({ missing_for_sec = 7 })
assert_equal(result.status, "hold", "transient missing approach is stabilized")
assert_equal(result.reason, "missing-not-stable", "transient selection reason")

result = evaluate_arrival_setup({ tod_distance_nm = 30 })
assert_equal(result.status, "warning", "missing approach triggers final TOD reminder")
assert_equal(result.stage, "final", "thirty-mile reminder uses final stage")

result = evaluate_arrival_setup({
    pre_tod_eligible = false,
    post_tod_eligible = true,
    tod_distance_nm = 0
})
assert_equal(result.status, "warning", "post-TOD fallback catches a missed reminder")
assert_equal(result.stage, "fallback", "post-TOD reminder uses fallback stage")

result = evaluate_arrival_setup({
    pre_tod_eligible = false,
    post_tod_eligible = true,
    tod_distance_nm = 0,
    early_warned = true
})
assert_equal(result.status, "hold", "post-TOD fallback does not repeat a pre-TOD reminder")
assert_equal(result.reason, "pre-tod-warning-already-issued", "post-TOD repeat suppression reason")

result = evaluate_arrival_setup({ approach_selected = true })
assert_equal(result.status, "clear", "selected approach completes arrival setup")
assert_equal(result.incomplete, false, "complete setup does not suppress route checks")

result = evaluate_arrival_setup({ runway_valid = false })
assert_equal(result.missing_kind, "runway", "missing runway takes priority over approach")

result = evaluate_arrival_setup({
    approach_source_available = false,
    destination_valid = false,
    runway_valid = false
})
assert_equal(result.status, "unavailable", "missing source fails open")
assert_equal(result.incomplete, false, "missing source does not suppress legacy route checks")

print("test_route_warning_guard: all checks passed")
