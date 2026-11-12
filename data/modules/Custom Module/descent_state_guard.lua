local P = {}

local function finiteNumber(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return fallback
    end
    return number
end

function P.evaluateDescentEvidence(input)
    input = input or {}
    local verticalSpeed = finiteNumber(input.vertical_speed_fpm, 0)
    local altitude = finiteNumber(input.altitude_ft, 0)
    local cruiseAltitude = finiteNumber(input.cruise_altitude_ft, 0)
    local strongDescentThreshold = finiteNumber(input.strong_descent_fpm, -300)
    local shallowDescentThreshold = finiteNumber(input.shallow_descent_fpm, -100)
    local belowCruiseThreshold = finiteNumber(input.below_cruise_ft, 300)
    local belowCruise = cruiseAltitude > 0
        and altitude < cruiseAltitude - belowCruiseThreshold
    local strongDescent = verticalSpeed <= strongDescentThreshold
    local shallowDescentBelowCruise = belowCruise
        and verticalSpeed <= shallowDescentThreshold

    return {
        active = strongDescent or shallowDescentBelowCruise,
        vertical_speed_fpm = verticalSpeed,
        altitude_ft = altitude,
        cruise_altitude_ft = cruiseAltitude,
        below_cruise = belowCruise,
        strong_descent = strongDescent,
        shallow_descent_below_cruise = shallowDescentBelowCruise
    }
end

function P.evaluateRestoreRecovery(input)
    input = input or {}
    local evidence = P.evaluateDescentEvidence(input)
    local result = {
        recover = false,
        reason = "not-eligible",
        evidence = evidence
    }

    if input.aircraft_on_ground == true then
        result.reason = "on-ground"
        return result
    end
    local climbThreshold = finiteNumber(input.climb_recovery_fpm, 100)
    if input.restored_flightstate == input.approach_flightstate then
        if input.go_around_active == true or input.hold_active == true then
            result.reason = "arrival-maneuver-active"
            return result
        end
        local climbPhase = input.fms_climb_phase ~= nil and input.fms_phase == input.fms_climb_phase
        local cruiseClimbPhase = input.fms_crz_clb_phase ~= nil and input.fms_phase == input.fms_crz_clb_phase
        -- A loaded climbing situation can retain the previous flight's persistent APPROACH.
        if (climbPhase or cruiseClimbPhase) and evidence.vertical_speed_fpm >= climbThreshold then
            result.recover = true
            result.reason = "fms-climbing"
            result.flightstate = climbPhase and input.climb_flightstate or input.cruise_flightstate
            return result
        end
        result.pending = (climbPhase or cruiseClimbPhase) and not evidence.active
    end
    if input.fms_phase ~= input.fms_cruise_phase then
        result.reason = "fms-not-cruise"
        return result
    end
    if input.restored_flightstate == input.cruise_flightstate then
        result.recover = true
        result.reason = "restored-cruise"
        return result
    end
    if input.restored_flightstate ~= input.approach_flightstate then
        result.reason = "restored-state-not-descent"
        return result
    end
    if evidence.active then
        result.reason = "actual-descent"
        return result
    end

    if evidence.vertical_speed_fpm >= climbThreshold then
        result.recover = true
        result.reason = "climbing"
        return result
    end

    local nearCruiseThreshold = finiteNumber(input.near_cruise_ft, 300)
    local nearLevelThreshold = finiteNumber(input.near_level_fpm, 100)
    local nearCruise = evidence.cruise_altitude_ft > 0
        and math.abs(evidence.altitude_ft - evidence.cruise_altitude_ft) <= nearCruiseThreshold
    local nearLevel = math.abs(evidence.vertical_speed_fpm) <= nearLevelThreshold
    if nearCruise and nearLevel then
        result.recover = true
        result.reason = "level-near-cruise"
        return result
    end

    result.reason = "ambiguous-flightpath"
    return result
end

return P
