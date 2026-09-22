package.path = "data/modules/Custom Module/?.lua;" .. package.path

local guard = require("takeoff_readiness_guard")

local function context(overrides)
    local input = {
        on_ground = true,
        powered = true,
        preflight = true,
        slow = true,
        no_main_procedure = true,
        before_taxi_done = false,
        before_takeoff_done = false,
        taxi_light_off = true,
        takeoff_context = false
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return guard.evaluateContext(input)
end

local result = context()
assert(result.open == true and result.mode == "pre_before_taxi",
    "preflight readiness must be available before Before Taxi")

result = context({ no_main_procedure = false })
assert(result.open == false, "an active Before Taxi procedure must own the flow")

result = context({ before_taxi_done = true, takeoff_context = true })
assert(result.open == false,
    "runway alignment after Before Taxi must not reopen ongoing checks before Before Takeoff")

result = context({
    before_taxi_done = true,
    before_takeoff_done = false,
    takeoff_context = true,
    no_main_procedure = false
})
assert(result.open == false, "active Before Takeoff must exclusively own trim and MCP checks")

result = context({
    before_taxi_done = true,
    before_takeoff_done = true,
    takeoff_context = true
})
assert(result.open == true and result.mode == "post_before_takeoff",
    "completed Before Takeoff may retain a final drift check")

result = context({
    before_taxi_done = true,
    before_takeoff_done = true,
    takeoff_context = false
})
assert(result.open == false, "post-procedure drift checks require takeoff context")

local signatures = {
    trim = "5.00:4.00",
    mcp_speed = "145:140",
    mcp_heading = "270:260"
}
local state = guard.updatePostCompletionState(nil, {
    before_takeoff_done = true,
    signatures = signatures,
    matched = { trim = false, mcp_speed = false, mcp_heading = false }
})

assert(guard.allowMismatch("post_before_takeoff", state, "trim", signatures.trim, true) == false,
    "an unresolved value present when Before Takeoff is skipped must not immediately repeat")
assert(guard.allowMismatch("pre_before_taxi", state, "trim", signatures.trim, true) == true,
    "the early preflight guard must still report an existing mismatch")
assert(guard.allowMismatch("closed", state, "trim", "5.00:3.75", true) == false,
    "closed procedure phases must never report a mismatch")

assert(guard.allowMismatch("post_before_takeoff", state, "trim", "5.00:3.75", true) == true,
    "a value changed after completion must re-arm the final drift check")

state = guard.updatePostCompletionState(state, {
    before_takeoff_done = true,
    signatures = { trim = "5.00:5.00" },
    matched = { trim = true }
})
assert(guard.allowMismatch("post_before_takeoff", state, "trim", "5.00:5.00", false) == false,
    "a matched value must refresh the post-procedure baseline")
assert(guard.allowMismatch("post_before_takeoff", state, "trim", "5.00:4.75", true) == true,
    "a mismatch introduced after a matched baseline must be reported")

state = guard.updatePostCompletionState(state, { before_takeoff_done = false })
assert(state == nil, "a new-flight procedure reset must clear the post-completion baseline")

assert(guard.SPEECH_KEYS.trim ~= guard.SPEECH_KEYS.mcp_speed
    and guard.SPEECH_KEYS.mcp_speed ~= guard.SPEECH_KEYS.mcp_heading,
    "takeoff readiness messages need independently cancellable speech keys")

print("test_takeoff_readiness_guard: all checks passed")
