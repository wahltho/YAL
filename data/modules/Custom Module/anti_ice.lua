local P = {}

P.MOISTURE_ON_STABLE_SEC = 6
P.MOISTURE_CLEAR_STABLE_SEC = 30
P.TEMPERATURE_STABLE_SEC = 6
P.STRUCTURAL_ICE_ON = 0.01
P.STRUCTURAL_ICE_CLEAR = 0.003
P.STRUCTURAL_ICE_EVIDENCE = 0.003
P.STRUCTURAL_ICE_ON_STABLE_SEC = 6
P.STRUCTURAL_ICE_CLEAR_STABLE_SEC = 30
P.ICE_DELTA_EPSILON = 0.0000001
P.PRECIPITATION_THRESHOLD = 0.01
P.CLOUD_COVERAGE_THRESHOLD = 0.5
P.FOG_VISIBILITY_SM = 1
P.FOG_MAX_AGL_FT = 1500
P.MAX_TAT_C = 10
P.MIN_CLIMB_CRUISE_SAT_C = -40
P.MIN_WING_ANTI_ICE_AGL_FT = 400
P.HIGH_WING_ANTI_ICE_ALTITUDE_FT = 35000

local function finiteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

local function elapsed(now, since)
    if since == nil then return 0 end
    return math.max(0, now - since)
end

local function maxFinite(a, b)
    a = finiteNumber(a) or 0
    b = finiteNumber(b) or 0
    return math.max(a, b)
end

function P.newState()
    return {
        context_active = false,
        last_now = nil,
        moisture_since = nil,
        moisture_clear_since = nil,
        moisture_active = nil,
        moisture_reason = nil,
        structural_since = nil,
        structural_clear_since = nil,
        structural_active = nil,
        warm_since = nil,
        cold_sat_since = nil,
        engine_demand = nil,
        engine_reason = nil,
        wing_demand = nil,
        wing_reason = nil
    }
end

function P.isInCloudLayer(altitudeM, coverage, basesM, topsM)
    local altitude = finiteNumber(altitudeM)
    if not altitude or type(coverage) ~= "table" or type(basesM) ~= "table" or type(topsM) ~= "table" then
        return false
    end

    local count = math.max(#coverage, #basesM, #topsM)
    for index = 1, count do
        local layerCoverage = finiteNumber(coverage[index])
        local base = finiteNumber(basesM[index])
        local top = finiteNumber(topsM[index])
        if layerCoverage and layerCoverage >= P.CLOUD_COVERAGE_THRESHOLD
            and base and top and top > base
            and altitude >= base and altitude <= top then
            return true
        end
    end
    return false
end

function P.visibleMoisture(input)
    input = input or {}
    if (finiteNumber(input.precipitation_ratio) or 0) >= P.PRECIPITATION_THRESHOLD then
        return true, "precipitation"
    end
    if (finiteNumber(input.snow_ratio) or 0) >= P.PRECIPITATION_THRESHOLD then
        return true, "snow"
    end
    if (finiteNumber(input.hail_ratio) or 0) >= P.PRECIPITATION_THRESHOLD then
        return true, "hail"
    end

    if input.in_cloud_layer == true then
        return true, "cloud-layer"
    end

    local visibility = finiteNumber(input.visibility_sm)
    local heightAgl = finiteNumber(input.height_agl_ft)
    if visibility and visibility >= 0 and visibility <= P.FOG_VISIBILITY_SM
        and heightAgl and heightAgl >= 0 and heightAgl <= P.FOG_MAX_AGL_FT then
        return true, "fog"
    end

    local iceDelta = finiteNumber(input.ice_delta)
    if iceDelta and iceDelta > P.ICE_DELTA_EPSILON then
        return true, "active-icing"
    end

    local maxIce = maxFinite(input.frame_ice_left, input.frame_ice_right)
    if maxIce >= P.STRUCTURAL_ICE_EVIDENCE then
        return true, "structural-ice"
    end
    return false, nil
end

local function updateMoistureState(state, input, now)
    local moisture, reason = P.visibleMoisture(input)
    if moisture then
        state.moisture_clear_since = nil
        if state.moisture_since == nil then state.moisture_since = now end
        state.moisture_reason = reason
        if elapsed(now, state.moisture_since) >= P.MOISTURE_ON_STABLE_SEC then
            state.moisture_active = true
        end
    else
        state.moisture_since = nil
        if state.moisture_clear_since == nil then state.moisture_clear_since = now end
        if elapsed(now, state.moisture_clear_since) >= P.MOISTURE_CLEAR_STABLE_SEC then
            state.moisture_active = false
            state.moisture_reason = nil
        end
    end
end

local function updateStructuralState(state, input, now)
    local maxIce = maxFinite(input.frame_ice_left, input.frame_ice_right)
    if maxIce >= P.STRUCTURAL_ICE_ON then
        state.structural_clear_since = nil
        if state.structural_since == nil then state.structural_since = now end
        if elapsed(now, state.structural_since) >= P.STRUCTURAL_ICE_ON_STABLE_SEC then
            state.structural_active = true
        end
    elseif maxIce <= P.STRUCTURAL_ICE_CLEAR then
        state.structural_since = nil
        if state.structural_clear_since == nil then state.structural_clear_since = now end
        if elapsed(now, state.structural_clear_since) >= P.STRUCTURAL_ICE_CLEAR_STABLE_SEC then
            state.structural_active = false
        end
    else
        state.structural_since = nil
        state.structural_clear_since = nil
    end
    return maxIce
end

local function updateTemperatureTimers(state, input, now)
    local tat = finiteNumber(input.tat_c)
    local sat = finiteNumber(input.sat_c)
    local warm = tat and tat > P.MAX_TAT_C
    local coldSat = input.climb_or_cruise == true and sat and sat < P.MIN_CLIMB_CRUISE_SAT_C

    if warm then
        if state.warm_since == nil then state.warm_since = now end
    else
        state.warm_since = nil
    end
    if coldSat then
        if state.cold_sat_since == nil then state.cold_sat_since = now end
    else
        state.cold_sat_since = nil
    end

    return tat, warm == true and elapsed(now, state.warm_since) >= P.TEMPERATURE_STABLE_SEC,
        coldSat == true and elapsed(now, state.cold_sat_since) >= P.TEMPERATURE_STABLE_SEC
end

local function resolveEngineDemand(state, tat, warmStable, coldSatStable)
    if not tat then return state.engine_demand, state.engine_reason end
    if warmStable then return false, "tat-above-10" end
    if coldSatStable then return false, "sat-below-minus-40" end
    if tat <= P.MAX_TAT_C and state.moisture_active == true then
        return true, state.moisture_reason or "icing-conditions"
    end
    if state.moisture_active == false then
        return false, "icing-conditions-clear"
    end
    return state.engine_demand, state.engine_reason
end

local function resolveWingDemand(state, input, tat)
    local pressureAltitude = finiteNumber(input.pressure_altitude_ft)
    local heightAgl = finiteNumber(input.height_agl_ft)
    if pressureAltitude and pressureAltitude >= P.HIGH_WING_ANTI_ICE_ALTITUDE_FT then
        return false, "altitude-above-fl350"
    end
    if tat and tat > P.MAX_TAT_C then
        return false, "tat-above-10"
    end
    if heightAgl and heightAgl < P.MIN_WING_ANTI_ICE_AGL_FT then
        return false, "below-400-feet-agl"
    end
    if not tat then return state.wing_demand, state.wing_reason end
    if state.structural_active == true then
        return true, "structural-ice"
    end
    if state.structural_active == false then
        return false, "wing-anti-ice-clear"
    end
    return state.wing_demand, state.wing_reason
end

function P.update(state, input)
    state = type(state) == "table" and state or P.newState()
    input = input or {}
    local now = finiteNumber(input.now) or 0

    if input.enabled ~= true or input.airborne ~= true then
        local wasActive = state.context_active == true
        state = P.newState()
        state.last_now = now
        return state, { reset = wasActive }
    end
    if state.last_now and now < state.last_now then
        state = P.newState()
    end
    state.context_active = true
    state.last_now = now

    updateMoistureState(state, input, now)
    local maxIce = updateStructuralState(state, input, now)
    local tat, warmStable, coldSatStable = updateTemperatureTimers(state, input, now)

    local previousEngine = state.engine_demand
    local previousEngineReason = state.engine_reason
    local previousWing = state.wing_demand
    local previousWingReason = state.wing_reason
    local engineDemand, engineReason = resolveEngineDemand(state, tat, warmStable, coldSatStable)
    local wingDemand, wingReason = resolveWingDemand(state, input, tat)
    state.engine_demand = engineDemand
    state.engine_reason = engineReason
    state.wing_demand = wingDemand
    state.wing_reason = wingReason

    local wingInhibited = wingReason == "altitude-above-fl350"
        or wingReason == "tat-above-10"
        or wingReason == "below-400-feet-agl"
    return state, {
        engine_changed = previousEngine ~= engineDemand or previousEngineReason ~= engineReason,
        engine_demand = engineDemand,
        engine_reason = engineReason,
        wing_changed = previousWing ~= wingDemand or previousWingReason ~= wingReason,
        wing_demand = wingDemand,
        wing_reason = wingReason,
        moisture_active = state.moisture_active,
        moisture_reason = state.moisture_reason,
        structural_active = state.structural_active,
        max_frame_ice = maxIce,
        wing_ice_inhibited = wingInhibited and state.structural_active == true,
        wing_inhibit_reason = wingInhibited and wingReason or nil
    }
end

return P
