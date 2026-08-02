local P = {}

local function finiteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

function P.evaluatePositiveTodSample(input)
    input = input or {}
    if input.eligible ~= true then
        return { status = "reset", reason = "not-eligible" }
    end

    local todDistance = finiteNumber(input.tod_distance_nm)
    local distDest = finiteNumber(input.destination_distance_nm)
    local remainingDistance = finiteNumber(input.remaining_distance_nm)
    local routeOn = input.on_route == true
    local warningDiff = finiteNumber(input.warning_diff_nm) or 20
    local resetDiff = finiteNumber(input.reset_diff_nm) or 10
    local maxRise = finiteNumber(input.max_rise_nm) or 1

    if not todDistance or todDistance <= 0 then
        return { status = "reset", reason = "tod-invalid" }
    end
    if not distDest or distDest <= 0 then
        return { status = "reset", reason = "destination-distance-invalid" }
    end

    local referenceDistance = routeOn and remainingDistance or distDest
    if not referenceDistance or referenceDistance <= 0 then
        return { status = "reset", reason = "route-distance-invalid" }
    end

    local diff = todDistance - referenceDistance
    local result = {
        tod_distance_nm = todDistance,
        destination_distance_nm = distDest,
        reference_distance_nm = referenceDistance,
        diff_nm = diff
    }

    if diff <= resetDiff then
        result.status = "clear"
        result.reason = "difference-cleared"
        return result
    end
    if diff <= warningDiff then
        result.status = "hold"
        result.reason = "difference-below-warning"
        return result
    end

    local previousTod = finiteNumber(input.previous_tod_distance_nm)
    local previousDistDest = finiteNumber(input.previous_destination_distance_nm)
    local previousReference = finiteNumber(input.previous_reference_distance_nm)
    if not previousTod or not previousDistDest or not previousReference then
        result.status = "baseline"
        result.reason = "trend-baseline"
        return result
    end

    if todDistance > previousTod + maxRise then
        result.status = "reset"
        result.reason = "tod-increasing"
        return result
    end
    if distDest > previousDistDest + maxRise then
        result.status = "reset"
        result.reason = "destination-distance-increasing"
        return result
    end
    if referenceDistance > previousReference + maxRise then
        result.status = "reset"
        result.reason = "route-distance-increasing"
        return result
    end

    result.status = "candidate"
    result.reason = "stable-route-shortfall"
    return result
end

return P
