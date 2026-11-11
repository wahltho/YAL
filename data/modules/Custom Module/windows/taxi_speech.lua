-- Withdrawal follows the existing taxi owner and geometry, never popup expiry.
local M = {}

function M.attach(U, C, def, helpers)
    local function snapshot(comp)
        local copy = {}
        for key, value in pairs(comp) do copy[key] = value end
        return copy
    end

    local function aircraft(comp)
        local yal = comp.yal or _G.yal
        if not yal then return nil end
        local lat, lon = get(yal.aircraftlatpos), get(yal.aircraftlonpos)
        if not U.is_valid_latlon(lat, lon) then return nil end
        local east, north = U.latlon_to_local(lat, lon)
        if not east or not north then return nil end
        return { lat = lat, lon = lon, east = east, north = north,
            heading = get(yal.groundtrackmag), nose_offset = yal.gear_znose and -get(yal.gear_znose) or nil }
    end

    local function available(comp, mode, warning)
        local yal = comp.yal or _G.yal
        if not yal or get(yal.airgroundsensor) ~= def.ON or comp.mode ~= mode
            or comp._drawRoute or comp._editRoute or comp._pushbackActive then return false end
        if not U.is_voice_enabled() then return false end
        if not warning and not U.is_auto_taxi_guidance_enabled() then return false end
        if mode == 0 then
            if yal.flightstate ~= def.FLIGHTSTATEPREFLIGHT or comp._takeoffRollGuidance then return false end
            if not warning and get(yal.parkingbrakepos) == def.ON then return false end
            if not warning and not helpers.before_taxi_started(yal) then return false end
        elseif yal.flightstate ~= def.FLIGHTSTATETAXITOGATE then return false end
        return true
    end

    function U.queue_taxi_speech(comp, text, info, key, pending, priority)
        local yal = comp.yal or _G.yal
        if not yal or not yal.queueConditionalSpeech then return false end
        if info and U.is_taxi_complete_info(info) then
            yal.commandtableentry(def.TAXI, text) -- Existing one-shot completion event.
            return true
        end
        local mode, route = comp.mode, comp._route
        local token = {}
        comp._speechOwners = comp._speechOwners or {}
        key = key or "taxi:guidance"
        comp._speechOwners[key] = token
        local issued = tonumber(comp._guidanceActiveSegIdx or comp._autoTaxiLastSegIdx) or 0
        if issued == 0 and route and route.data and route.path then
            local ac = aircraft(comp)
            issued = ac and U.find_nearest_segment(route.data, route.path, ac.east, ac.north) or 0
        end
        local commit = tonumber(info and info.targetSegIdx) or issued
        if info and (info.action == "TURN LEFT" or info.action == "TURN RIGHT") then
            commit = math.max(commit, issued + 1)
        end
        return yal.queueConditionalSpeech(key, text, function()
            if comp._speechOwners[key] ~= token or not available(comp, mode, key == "taxi:before_taxi_missing") then return false end
            if key ~= "taxi:before_taxi_missing" and comp._route ~= route then return false end
            if pending then return pending() == true end
            if comp._routeErr or comp._arrTaxiCompleteAnnounced or comp._depTaxiCompleteAnnounced then return false end
            if info and U.is_raas_duplicate_voice_suppressed
                and U.is_raas_duplicate_voice_suppressed(comp, info, true) then return false end
            local ac = aircraft(comp)
            if not ac then return false end
            if info and info.kind == "ramp" and comp._guidanceState == "gate" then
                local current = U.gate_alignment_info(snapshot(comp), ac)
                return current ~= nil and current.action == info.action and current.direction == info.direction
                    and current.label == info.label
            end
            if info and info.kind == "runway" and not info.targetSegIdx and comp._depProfile then
                local state = U.compute_dep_threshold_state(comp, comp._depProfile, nil, nil, ac)
                return state ~= nil and not (state.perp <= state.corridor and state.heading_diff
                    and state.heading_diff <= ((comp._tuning and comp._tuning.autoTaxiAlignHeadingDeg)
                        or C.autoTaxiAlignHeadingDeg or 8))
            end
            if not route or not route.data or not route.path then return false end
            local seg = U.find_nearest_segment(route.data, route.path, ac.east, ac.north)
            if not seg or seg > commit then return false end
            local current = comp._speechSegmentInfo and comp._speechSegmentInfo(seg)
            local label = current and current.display or U.get_edge_label(route.data, route.path[seg], route.path[seg + 1])
            if info and info.display and info.display ~= "" and seg > issued and label == info.display then return false end
            return comp._guidanceState ~= "complete"
        end, "voice", def.TAXI, priority or 20)
    end

    function U.queue_gate_speech(comp, text, stage, stopDistance)
        local target = comp._gateCalloutKey
        return U.queue_taxi_speech(comp, text, nil, "taxi:gate", function()
            if comp._gateCalloutKey ~= target or comp._arrTaxiCompleteAnnounced or comp._routeErr == "taxi-complete" then return false end
            local ac = aircraft(comp)
            local route = comp._route
            local distance = ac and U.gate_distance_meters(snapshot(comp), ac, route, route and route.data or comp._data)
            if not distance or math.abs(get((comp.yal or _G.yal).groundspeed)) <= 0.2 then return false end
            if stage == 4 then return distance <= stopDistance end
            local thresholds = { 30, 10, 5 }
            return (comp._gateCalloutStage or 0) <= stage and distance <= thresholds[stage]
                and distance > (thresholds[stage + 1] or stopDistance)
        end)
    end

    function U.queue_threshold_speech(comp, text, stage)
        local target, profile = comp._depThresholdCalloutKey, comp._depProfile
        return U.queue_taxi_speech(comp, text, nil, "taxi:threshold", function()
            if comp._depThresholdCalloutKey ~= target or comp._depProfile ~= profile
                or comp._depTaxiCompleteAnnounced or (comp._depThresholdCalloutStage or 0) > stage then return false end
            local ac = aircraft(comp)
            local state = ac and U.compute_dep_threshold_state(comp, profile, nil, nil, ac)
            local thresholds = { 300, 150, 50, 20 }
            local distance = state and math.abs(state.along_to_threshold)
            return state and state.along_to_threshold < 0 and not state.reached and not comp._depThresholdLatched
                and state.perp <= state.corridor and distance <= thresholds[stage]
                and distance > (thresholds[stage + 1] or 0)
        end)
    end

    function U.queue_before_taxi_warning(comp)
        return U.queue_taxi_speech(comp, "Warning, before taxi procedure not started", nil, "taxi:before_taxi_missing", function()
            local yal = comp.yal or _G.yal
            return not helpers.before_taxi_started(yal) and get(yal.parkingbrakepos) ~= def.ON
                and (math.abs(get(yal.groundspeed)) >= 3 or math.abs(get(yal.tirespeed)) >= 3)
        end, 50)
    end
end

return M
