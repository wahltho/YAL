local P = {}

P.MOISTURE_ON_STABLE_SEC = 6
P.MOISTURE_CLEAR_STABLE_SEC = 30
P.ENGINE_ON_STABLE_SEC = 15
P.ENGINE_CLEAR_STABLE_SEC = 30
P.TEMPERATURE_STABLE_SEC = 6
P.STRUCTURAL_ICE_ON = 0.01
P.STRUCTURAL_ICE_CLEAR = 0.003
P.STRUCTURAL_ICE_EVIDENCE = 0.003
P.STRUCTURAL_ICE_ON_STABLE_SEC = 6
P.STRUCTURAL_ICE_CLEAR_STABLE_SEC = 30
P.WING_CLEAR_STABLE_SEC = 120
P.ICE_DELTA_EPSILON = 0.0000001
P.PRECIPITATION_THRESHOLD = 0.01
P.CLOUD_COVERAGE_THRESHOLD = 0.5
P.FOG_VISIBILITY_SM = 1
P.FOG_MAX_AGL_FT = 1500
P.MAX_TAT_C = 10
P.MIN_CLIMB_CRUISE_SAT_C = -40
P.MIN_WING_ANTI_ICE_AGL_FT = 400
P.HIGH_WING_ANTI_ICE_ALTITUDE_FT = 35000
P.LOOKAHEAD_HORIZON_SEC = 300
P.LOOKAHEAD_STEP_SEC = 5
P.LOOKAHEAD_REFRESH_SEC = 1
P.LOOKAHEAD_MIN_VERTICAL_SPEED_FPM = 200
P.LOOKAHEAD_MAX_ENTRY_SEC = 60
P.LOOKAHEAD_DESCENT_MAX_ENTRY_SEC = 120
P.LOOKAHEAD_MIN_CORRIDOR_SEC = 45
P.LOOKAHEAD_REARM_MIN_CORRIDOR_SEC = 120

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

local function cockpitTemperature(value)
    value = finiteNumber(value)
    if not value then return nil end
    return math.floor(value + 0.5)
end

local function buildTemperatureProfile(levelsM, temperaturesC)
    if type(levelsM) ~= "table" or type(temperaturesC) ~= "table" then return nil end
    local points = {}
    local count = math.max(#levelsM, #temperaturesC)
    for index = 1, count do
        local altitude = finiteNumber(levelsM[index])
        local temperature = finiteNumber(temperaturesC[index])
        if altitude and altitude >= 0 and altitude <= 25000
            and temperature and temperature >= -120 and temperature <= 80 then
            points[#points + 1] = { altitude = altitude, temperature = temperature }
        end
    end
    if #points < 2 then return nil end
    table.sort(points, function(a, b) return a.altitude < b.altitude end)
    return points
end

local function interpolateTemperature(points, altitudeM)
    local altitude = finiteNumber(altitudeM)
    if not altitude or type(points) ~= "table" or #points < 2 then return nil end
    if altitude < points[1].altitude or altitude > points[#points].altitude then return nil end
    for index = 2, #points do
        local lower = points[index - 1]
        local upper = points[index]
        if altitude <= upper.altitude then
            local span = upper.altitude - lower.altitude
            if span <= 0 then return upper.temperature end
            local ratio = (altitude - lower.altitude) / span
            return lower.temperature + (upper.temperature - lower.temperature) * ratio
        end
    end
    return nil
end

function P.findCloudLayer(altitudeM, coverage, basesM, topsM)
    local altitude = finiteNumber(altitudeM)
    if not altitude or type(coverage) ~= "table" or type(basesM) ~= "table" or type(topsM) ~= "table" then
        return nil
    end

    local count = math.max(#coverage, #basesM, #topsM)
    for index = 1, count do
        local layerCoverage = finiteNumber(coverage[index])
        local base = finiteNumber(basesM[index])
        local top = finiteNumber(topsM[index])
        if layerCoverage and layerCoverage >= P.CLOUD_COVERAGE_THRESHOLD
            and base and top and top > base
            and altitude >= base and altitude <= top then
            return index, layerCoverage, base, top
        end
    end
    return nil
end

function P.newState()
    return {
        context_active = false,
        last_now = nil,
        moisture_since = nil,
        moisture_clear_since = nil,
        moisture_active = nil,
        moisture_reason = nil,
        engine_eligible_since = nil,
        engine_clear_since = nil,
        structural_since = nil,
        structural_clear_since = nil,
        structural_active = nil,
        warm_since = nil,
        cold_sat_since = nil,
        temperature_rearm_pending = false,
        lookahead = nil,
        lookahead_updated_at = nil,
        engine_demand = nil,
        engine_reason = nil,
        wing_demand = nil,
        wing_reason = nil,
        wing_clear_since = nil
    }
end

function P.isInCloudLayer(altitudeM, coverage, basesM, topsM)
    return P.findCloudLayer(altitudeM, coverage, basesM, topsM) ~= nil
end

function P.analyzeVerticalIcingCorridor(input)
    input = input or {}
    local altitude = finiteNumber(input.elevation_m)
    local verticalSpeed = finiteNumber(input.vertical_speed_fpm)
    local tat = finiteNumber(input.tat_c)
    local sat = finiteNumber(input.sat_c)
    local currentLayer, currentCoverage, currentBase, currentTop = P.findCloudLayer(
        altitude, input.cloud_coverage, input.cloud_bases_m, input.cloud_tops_m)
    local result = {
        valid = false,
        max_entry_sec = verticalSpeed and verticalSpeed < 0 and input.climb_or_cruise ~= true
            and P.LOOKAHEAD_DESCENT_MAX_ENTRY_SEC or P.LOOKAHEAD_MAX_ENTRY_SEC,
        current_layer_id = currentLayer,
        current_layer_coverage = currentCoverage,
        current_layer_base_m = currentBase,
        current_layer_top_m = currentTop
    }

    if not altitude or not verticalSpeed or not tat or not sat then
        result.reason = "missing-flight-input"
        return result
    end
    if math.abs(verticalSpeed) < P.LOOKAHEAD_MIN_VERTICAL_SPEED_FPM then
        result.reason = "vertical-speed-low"
        return result
    end

    local profile = buildTemperatureProfile(input.temperature_altitudes_m, input.temperatures_aloft_c)
    if not profile then
        result.reason = "temperature-profile-invalid"
        return result
    end
    local profileSatNow = interpolateTemperature(profile, altitude)
    if not profileSatNow then
        result.reason = "temperature-profile-out-of-range"
        return result
    end

    local satOffset = sat - profileSatNow
    local recoveryRise = math.max(0, math.min(40, tat - sat))
    local verticalMetersPerSecond = verticalSpeed * 0.00508
    local activeSegment = nil
    local activeThermalSegment = nil
    local segments = {}
    local thermalSegments = {}
    local sampledThrough = 0

    for seconds = 0, P.LOOKAHEAD_HORIZON_SEC, P.LOOKAHEAD_STEP_SEC do
        local projectedAltitude = altitude + verticalMetersPerSecond * seconds
        local projectedSatRaw = interpolateTemperature(profile, projectedAltitude)
        if not projectedSatRaw then
            break
        end
        sampledThrough = seconds
        local projectedSat = projectedSatRaw + satOffset
        local projectedTat = projectedSat + recoveryRise
        local layerIndex = P.findCloudLayer(
            projectedAltitude, input.cloud_coverage, input.cloud_bases_m, input.cloud_tops_m)
        local temperatureEligible = projectedTat <= P.MAX_TAT_C
        local coldSatInhibit = input.climb_or_cruise == true
            and projectedSat < P.MIN_CLIMB_CRUISE_SAT_C
        local thermalQualifying = temperatureEligible and not coldSatInhibit
        local qualifying = layerIndex ~= nil and thermalQualifying

        if thermalQualifying then
            if not activeThermalSegment then
                activeThermalSegment = {
                    entry_sec = seconds,
                    projected_tat_min_c = projectedTat,
                    projected_tat_max_c = projectedTat
                }
            else
                activeThermalSegment.projected_tat_min_c = math.min(
                    activeThermalSegment.projected_tat_min_c, projectedTat)
                activeThermalSegment.projected_tat_max_c = math.max(
                    activeThermalSegment.projected_tat_max_c, projectedTat)
            end
        elseif activeThermalSegment then
            activeThermalSegment.exit_sec = seconds
            activeThermalSegment.qualifying_duration_sec = seconds - activeThermalSegment.entry_sec
            thermalSegments[#thermalSegments + 1] = activeThermalSegment
            activeThermalSegment = nil
        end

        if qualifying then
            if not activeSegment then
                activeSegment = {
                    entry_sec = seconds,
                    layer_id = layerIndex,
                    projected_tat_min_c = projectedTat,
                    projected_tat_max_c = projectedTat
                }
            else
                activeSegment.projected_tat_min_c = math.min(activeSegment.projected_tat_min_c, projectedTat)
                activeSegment.projected_tat_max_c = math.max(activeSegment.projected_tat_max_c, projectedTat)
            end
        elseif activeSegment then
            activeSegment.exit_sec = seconds
            activeSegment.qualifying_duration_sec = seconds - activeSegment.entry_sec
            segments[#segments + 1] = activeSegment
            activeSegment = nil
        end
    end
    if activeSegment then
        activeSegment.exit_sec = sampledThrough
        activeSegment.qualifying_duration_sec = sampledThrough - activeSegment.entry_sec
        segments[#segments + 1] = activeSegment
    end
    if activeThermalSegment then
        activeThermalSegment.exit_sec = sampledThrough
        activeThermalSegment.qualifying_duration_sec = sampledThrough - activeThermalSegment.entry_sec
        thermalSegments[#thermalSegments + 1] = activeThermalSegment
    end

    result.valid = sampledThrough >= P.LOOKAHEAD_MAX_ENTRY_SEC
    result.sampled_through_sec = sampledThrough
    if not result.valid then
        result.reason = "projected-profile-too-short"
        return result
    end
    result.reason = #segments > 0 and "corridor-found" or "no-qualifying-corridor"
    result.corridors = segments
    local selected = nil
    for _, segment in ipairs(segments) do
        if segment.entry_sec <= result.max_entry_sec
            and segment.qualifying_duration_sec >= P.LOOKAHEAD_MIN_CORRIDOR_SEC then
            selected = segment
            break
        end
    end
    selected = selected or segments[1]
    if selected then
        result.corridor_layer_id = selected.layer_id
        result.entry_sec = selected.entry_sec
        result.exit_sec = selected.exit_sec
        result.qualifying_duration_sec = selected.qualifying_duration_sec
        result.projected_tat_min_c = selected.projected_tat_min_c
        result.projected_tat_max_c = selected.projected_tat_max_c
    end
    local selectedThermal = thermalSegments[1]
    if selectedThermal then
        result.thermal_entry_sec = selectedThermal.entry_sec
        result.thermal_exit_sec = selectedThermal.exit_sec
        result.thermal_duration_sec = selectedThermal.qualifying_duration_sec
        result.thermal_tat_min_c = selectedThermal.projected_tat_min_c
        result.thermal_tat_max_c = selectedThermal.projected_tat_max_c
    end
    return result
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
    return moisture, reason
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
    local displayedTat = cockpitTemperature(tat)
    local sat = finiteNumber(input.sat_c)
    local warm = displayedTat and displayedTat > P.MAX_TAT_C
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

    return tat, displayedTat,
        warm == true and elapsed(now, state.warm_since) >= P.TEMPERATURE_STABLE_SEC,
        coldSat == true and elapsed(now, state.cold_sat_since) >= P.TEMPERATURE_STABLE_SEC
end

local function hasActualIcingEvidence(input)
    if (finiteNumber(input.ice_delta) or 0) > P.ICE_DELTA_EPSILON then return true end
    return maxFinite(input.frame_ice_left, input.frame_ice_right) >= P.STRUCTURAL_ICE_EVIDENCE
end

local function qualifyingCloudCorridor(lookahead, minimumDuration, currentOnly)
    if type(lookahead) ~= "table" or lookahead.valid ~= true then return false end
    local maxEntry = finiteNumber(lookahead.max_entry_sec) or P.LOOKAHEAD_MAX_ENTRY_SEC
    local corridors = lookahead.corridors
    if type(corridors) ~= "table" then corridors = { lookahead } end
    for _, corridor in ipairs(corridors) do
        local entry = finiteNumber(corridor.entry_sec)
        if entry and entry <= maxEntry and (not currentOnly or entry == 0)
            and (finiteNumber(corridor.qualifying_duration_sec) or 0) >= minimumDuration then
            return true
        end
    end
    return false
end

local function lookaheadSupportsEngineOn(lookahead, minimumDuration)
    return qualifyingCloudCorridor(lookahead, minimumDuration, false)
end

local function currentCloudCorridorSupportsEngineOn(lookahead, minimumDuration)
    return qualifyingCloudCorridor(lookahead, minimumDuration, true)
end

local function resolveEngineDemand(
    state, input, now, tat, displayedTat, warmStable, coldSatStable, moisture, moistureReason, lookahead)
    if not tat or not displayedTat then return state.engine_demand, state.engine_reason end
    local actualIcingEvidence = hasActualIcingEvidence(input)
    if warmStable then
        state.engine_eligible_since = nil
        state.engine_clear_since = nil
        state.temperature_rearm_pending = moisture == true or state.moisture_active == true
        return false, "tat-above-10"
    end
    if coldSatStable then
        state.engine_eligible_since = nil
        state.engine_clear_since = nil
        state.temperature_rearm_pending = moisture == true or state.moisture_active == true
        return false, "sat-below-minus-40"
    end

    local sat = finiteNumber(input.sat_c)
    -- Never start above the FCOM limit; use the whole-degree cockpit value only
    -- to avoid an OFF transition the crew display cannot yet show.
    local warm = tat > P.MAX_TAT_C
    local coldSat = input.climb_or_cruise == true and sat and sat < P.MIN_CLIMB_CRUISE_SAT_C
    local forecastEligible = lookaheadSupportsEngineOn(lookahead, P.LOOKAHEAD_MIN_CORRIDOR_SEC)
    local engineMoisture = moisture == true or forecastEligible
    local eligible = engineMoisture and not warm and not coldSat
    if eligible then
        state.engine_clear_since = nil
        if state.engine_demand == true then
            state.engine_eligible_since = nil
            return true, moistureReason or state.moisture_reason or "icing-conditions"
        end

        local requiredDuration = state.temperature_rearm_pending == true
            and P.LOOKAHEAD_REARM_MIN_CORRIDOR_SEC or P.LOOKAHEAD_MIN_CORRIDOR_SEC
        local forecastSupportsEvidence = true
        if not actualIcingEvidence and lookahead and lookahead.valid == true then
            if moisture == true then
                if moistureReason == "cloud-layer" then
                    forecastSupportsEvidence = currentCloudCorridorSupportsEngineOn(
                        lookahead, requiredDuration)
                end
            else
                forecastSupportsEvidence = lookaheadSupportsEngineOn(lookahead, requiredDuration)
            end
        end
        if not forecastSupportsEvidence then
            state.engine_eligible_since = nil
            return nil, moisture == true and moistureReason ~= "cloud-layer"
                and "icing-temperature-window-short" or "icing-corridor-short"
        end

        if state.engine_eligible_since == nil then state.engine_eligible_since = now end
        if elapsed(now, state.engine_eligible_since) >= P.ENGINE_ON_STABLE_SEC
            and (state.moisture_active == true or forecastEligible or actualIcingEvidence) then
            state.temperature_rearm_pending = false
            return true, moistureReason or (forecastEligible and "icing-layer-ahead")
                or state.moisture_reason or "icing-conditions"
        end
        return nil, "icing-conditions-confirming"
    end

    state.engine_eligible_since = nil
    if state.moisture_active == false then
        if state.engine_demand == true then
            if state.engine_clear_since == nil then state.engine_clear_since = now end
            if elapsed(now, state.engine_clear_since) < P.ENGINE_CLEAR_STABLE_SEC then
                return true, state.engine_reason
            end
        end
        state.engine_clear_since = nil
        state.temperature_rearm_pending = false
        return false, "icing-conditions-clear"
    end

    state.engine_clear_since = nil
    if state.engine_demand == false then
        return false, "icing-conditions-clear"
    end
    return state.engine_demand, state.engine_reason
end

local function resolveWingDemand(state, input, now, tat, moisture, lookahead)
    local pressureAltitude = finiteNumber(input.pressure_altitude_ft)
    local heightAgl = finiteNumber(input.height_agl_ft)
    if pressureAltitude and pressureAltitude >= P.HIGH_WING_ANTI_ICE_ALTITUDE_FT then
        state.wing_clear_since = nil
        return false, "altitude-above-fl350"
    end
    if tat and tat > P.MAX_TAT_C then
        state.wing_clear_since = nil
        return false, "tat-above-10"
    end
    if heightAgl and heightAgl < P.MIN_WING_ANTI_ICE_AGL_FT then
        state.wing_clear_since = nil
        return false, "below-400-feet-agl"
    end
    if not tat then
        state.wing_clear_since = nil
        return state.wing_demand, state.wing_reason
    end
    -- Removed ice can mean protection is working, not that icing has ended.
    if state.wing_demand == true then
        if moisture or qualifyingCloudCorridor(lookahead, P.LOOKAHEAD_MIN_CORRIDOR_SEC, false) then
            state.wing_clear_since = nil
        elseif state.wing_clear_since == nil then
            state.wing_clear_since = now
        end
        if state.wing_clear_since == nil
            or elapsed(now, state.wing_clear_since) < P.WING_CLEAR_STABLE_SEC then
            return true, state.wing_reason
        end
        state.wing_clear_since = nil
        return false, "wing-anti-ice-clear"
    end
    state.wing_clear_since = nil
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

    local moisture, moistureReason = updateMoistureState(state, input, now)
    local maxIce = updateStructuralState(state, input, now)
    local tat, displayedTat, warmStable, coldSatStable = updateTemperatureTimers(state, input, now)
    if state.lookahead_updated_at == nil
        or elapsed(now, state.lookahead_updated_at) >= P.LOOKAHEAD_REFRESH_SEC then
        state.lookahead = P.analyzeVerticalIcingCorridor(input)
        state.lookahead_updated_at = now
    end
    local lookahead = state.lookahead

    local previousEngine = state.engine_demand
    local previousEngineReason = state.engine_reason
    local previousWing = state.wing_demand
    local previousWingReason = state.wing_reason
    local engineDemand, engineReason = resolveEngineDemand(
        state, input, now, tat, displayedTat, warmStable, coldSatStable,
        moisture, moistureReason, lookahead)
    local wingDemand, wingReason = resolveWingDemand(state, input, now, tat, moisture, lookahead)
    state.engine_demand = engineDemand
    state.engine_reason = engineReason
    state.wing_demand = wingDemand
    state.wing_reason = wingReason

    local wingInhibited = wingReason == "altitude-above-fl350"
        or wingReason == "tat-above-10"
        or wingReason == "below-400-feet-agl"
    return state, {
        engine_changed = previousEngine ~= engineDemand,
        engine_reason_changed = previousEngineReason ~= engineReason,
        engine_demand = engineDemand,
        engine_reason = engineReason,
        wing_changed = previousWing ~= wingDemand or previousWingReason ~= wingReason,
        wing_demand = wingDemand,
        wing_reason = wingReason,
        moisture_active = state.moisture_active,
        moisture_reason = state.moisture_reason,
        structural_active = state.structural_active,
        max_frame_ice = maxIce,
        displayed_tat_c = displayedTat,
        lookahead = lookahead,
        wing_ice_inhibited = wingInhibited and state.structural_active == true,
        wing_inhibit_reason = wingInhibited and wingReason or nil
    }
end

return P
