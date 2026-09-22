local P = {}

P.SPEECH_KEYS = {
    trim = "takeoff_readiness:trim",
    mcp_speed = "takeoff_readiness:mcp_speed",
    mcp_heading = "takeoff_readiness:mcp_heading"
}

local function copyMap(values)
    local result = {}
    for key, value in pairs(values or {}) do
        result[key] = value
    end
    return result
end

function P.evaluateContext(input)
    input = input or {}
    local common = input.on_ground == true
        and input.powered == true
        and input.preflight == true
        and input.slow == true
        and input.no_main_procedure == true

    if not common then
        return { open = false, mode = "closed" }
    end
    if input.before_taxi_done ~= true and input.taxi_light_off == true then
        return { open = true, mode = "pre_before_taxi" }
    end
    if input.before_takeoff_done == true and input.takeoff_context == true then
        return { open = true, mode = "post_before_takeoff" }
    end
    return { open = false, mode = "closed" }
end

function P.updatePostCompletionState(state, input)
    input = input or {}
    if input.before_takeoff_done ~= true then
        return nil
    end

    local signatures = input.signatures or {}
    local matched = input.matched or {}
    if not state then
        return { baseline = copyMap(signatures) }
    end

    state.baseline = state.baseline or {}
    for key, signature in pairs(signatures) do
        if matched[key] == true then
            state.baseline[key] = signature
        elseif state.baseline[key] == nil then
            state.baseline[key] = signature
        end
    end
    return state
end

function P.allowMismatch(mode, state, key, signature, mismatch)
    if mismatch ~= true then
        return false
    end
    if mode == "pre_before_taxi" then
        return true
    end
    if mode ~= "post_before_takeoff" or not state or not state.baseline then
        return false
    end
    return state.baseline[key] ~= nil and state.baseline[key] ~= signature
end

return P
