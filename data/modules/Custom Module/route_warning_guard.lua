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

function P.evaluateArrivalSetup(input)
    input = input or {}
    if input.approach_source_available ~= true then
        return { status = "unavailable", reason = "approach-source-unavailable", incomplete = false }
    end

    local missingKind = nil
    if input.destination_valid ~= true then
        missingKind = "destination"
    elseif input.runway_valid ~= true then
        missingKind = "runway"
    elseif input.approach_selected ~= true then
        missingKind = "approach"
    end

    if not missingKind then
        return { status = "clear", reason = "arrival-setup-complete", incomplete = false }
    end

    local result = {
        status = "hold",
        reason = "outside-warning-gate",
        incomplete = true,
        missing_kind = missingKind
    }
    local missingFor = finiteNumber(input.missing_for_sec) or 0
    local stableSec = finiteNumber(input.stable_sec) or 8
    if missingFor < stableSec then
        result.reason = "missing-not-stable"
        return result
    end

    if input.post_tod_eligible == true then
        if input.early_warned == true or input.final_warned == true then
            result.reason = "pre-tod-warning-already-issued"
        elseif input.fallback_warned ~= true then
            result.status = "warning"
            result.reason = "post-tod-fallback"
            result.stage = "fallback"
        else
            result.reason = "post-tod-already-warned"
        end
        return result
    end

    if input.pre_tod_eligible ~= true then
        return result
    end

    local todDistance = finiteNumber(input.tod_distance_nm)
    if not todDistance or todDistance <= 0 then
        result.reason = "tod-invalid"
        return result
    end
    result.tod_distance_nm = todDistance

    local finalTodNm = finiteNumber(input.final_tod_nm) or 30
    if todDistance <= finalTodNm then
        if input.final_warned ~= true then
            result.status = "warning"
            result.reason = "final-tod-gate"
            result.stage = "final"
        else
            result.reason = "final-already-warned"
        end
        return result
    end

    local groundSpeed = finiteNumber(input.ground_speed_kt)
    local earlyEligible = false
    if groundSpeed and groundSpeed >= 100 then
        result.time_to_tod_min = (todDistance / groundSpeed) * 60
        earlyEligible = result.time_to_tod_min <= (finiteNumber(input.early_tod_min) or 10)
    else
        earlyEligible = todDistance <= (finiteNumber(input.early_tod_fallback_nm) or 75)
    end

    if earlyEligible then
        if input.early_warned ~= true then
            result.status = "warning"
            result.reason = "early-tod-gate"
            result.stage = "early"
        else
            result.reason = "early-already-warned"
        end
    end
    return result
end

return P
