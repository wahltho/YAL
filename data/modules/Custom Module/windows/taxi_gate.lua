local M = {}

function M.attach(U, C, def, helpers)
    local is_valid_latlon = U.is_valid_latlon
    local latlon_to_local = U.latlon_to_local
    local distance_sq = U.distance_sq
    local short_ramp_label = U.short_ramp_label
    local build_visual_label = U.build_visual_label
    local is_voice_enabled = U.is_voice_enabled
    local speak_guidance_text = U.speak_guidance_text
    local clamp = U.clamp

    local function ramp_frame_values(ramp, aircraft)
        if not ramp or not aircraft or aircraft.east == nil or aircraft.north == nil then
            return nil
        end
        local east = ramp.east
        local north = ramp.north
        if (east == nil or north == nil) and is_valid_latlon(ramp.lat, ramp.lon) then
            east, north = latlon_to_local(ramp.lat, ramp.lon)
        end
        if east == nil or north == nil then
            return nil
        end
        local dx = aircraft.east - east
        local dy = aircraft.north - north
        if aircraft.heading and type(aircraft.heading) == "number" then
            local offset = aircraft.nose_offset or (C and C.gateStopOffsetMeters or 10)
            local rad = math.rad(aircraft.heading % 360)
            dx = dx + math.sin(rad) * offset
            dy = dy + math.cos(rad) * offset
        end
        local dist = math.sqrt(dx * dx + dy * dy)
        local hdg = tonumber(ramp.heading)
        if not hdg then
            return dx, dy, nil, dist
        end
        local rad = math.rad(hdg % 360)
        local sin_h = math.sin(rad)
        local cos_h = math.cos(rad)
        local local_x = cos_h * dx - sin_h * dy
        local local_z = sin_h * dx + cos_h * dy
        return local_x, local_z, hdg, dist
    end

    local function ramp_dgs_values(ramp, aircraft)
        if not ramp or not aircraft or aircraft.east == nil or aircraft.north == nil then
            return nil
        end
        local dgs_good_x = (C and C.gateDgsGoodX) or 2.0
        local dgs_good_z_pos = (C and C.gateDgsGoodZPos) or 0.2
        local dgs_good_z_neg = (C and C.gateDgsGoodZNeg) or -0.5
        local dgs_azi_cross = (C and C.gateDgsAziCrossover) or 6
        local dgs_ref_span = (C and C.gateDgsRefBlendSpan) or 20
        local dgs_azi_scale = (C and C.gateDgsAziScale) or 0.3
        local east = ramp.east
        local north = ramp.north
        if (east == nil or north == nil) and is_valid_latlon(ramp.lat, ramp.lon) then
            east, north = latlon_to_local(ramp.lat, ramp.lon)
        end
        if east == nil or north == nil then
            return nil
        end
        local hdg = tonumber(ramp.heading)
        if not hdg then
            return nil
        end
        if type(aircraft.heading) ~= "number" then
            return nil
        end
        local dx = aircraft.east - east
        local dy = aircraft.north - north
        local rad = math.rad(hdg % 360)
        local sin_h = math.sin(rad)
        local cos_h = math.cos(rad)
        local local_x = cos_h * dx - sin_h * dy
        local local_z = sin_h * dx + cos_h * dy
        local local_hdgt = helpers.headingdiff(aircraft.heading, hdg)
        if type(local_hdgt) ~= "number" then
            return nil
        end
        local nw = aircraft.nose_offset or (C and C.gateStopOffsetMeters) or 11
        if not nw or nw == 0 then
            return nil
        end
        local mw = aircraft.main_offset or nw
        local rad_h = math.rad(local_hdgt)
        local sin_hr = math.sin(rad_h)
        local nw_z = local_z - nw
        local nw_x = local_x + nw * sin_hr
        local mw_z = local_z - mw
        local mw_x = local_x + mw * sin_hr
        local a = clamp((nw_z - dgs_azi_cross) / dgs_ref_span, 0, 1)
        local plane_ref_z = (1 - a) * nw + a * mw
        local ref_z = local_z - plane_ref_z
        local ref_x = local_x + plane_ref_z * sin_hr
        return {
            local_x = local_x,
            local_z = local_z,
            local_hdgt = local_hdgt,
            nw_z = nw_z,
            nw_x = nw_x,
            mw_z = mw_z,
            mw_x = mw_x,
            ref_z = ref_z,
            ref_x = ref_x,
            dgs_good_x = dgs_good_x,
            dgs_good_z_pos = dgs_good_z_pos,
            dgs_good_z_neg = dgs_good_z_neg,
            dgs_azi_cross = dgs_azi_cross,
            dgs_azi_scale = dgs_azi_scale
        }
    end

    local function gate_final_thresholds(radius)
        local final_limit = math.max(15, math.min(30, (radius or 60) * 0.5))
        local stop_limit = math.max((C and C.gateStopDistance) or 2, math.min(8, final_limit * 0.35))
        return final_limit, stop_limit
    end

    local function gate_tracking_distance(comp, fallback_dist, radius)
        local ref_dist = comp and comp._gateActivationDist or nil
        local track_dist = ref_dist
        if track_dist == nil or (fallback_dist ~= nil and fallback_dist > track_dist) then
            track_dist = fallback_dist
        end
        local final_limit, stop_limit = gate_final_thresholds(radius)
        local stage = "approach"
        if track_dist ~= nil then
            if track_dist <= stop_limit then
                stage = "stop"
            elseif track_dist <= final_limit then
                stage = "final"
            end
        end
        return track_dist, stage, final_limit, stop_limit
    end

    local function trusted_ramp_dgs(ramp, aircraft, fallback_dist, radius, ref_dist)
        local dgs = ramp_dgs_values(ramp, aircraft)
        if not dgs then
            return nil
        end
        local track_dist = ref_dist
        if track_dist == nil or (fallback_dist ~= nil and fallback_dist > track_dist) then
            track_dist = fallback_dist
        end
        local final_limit = gate_final_thresholds(radius)
        if track_dist and track_dist > final_limit then
            return nil
        end
        if fallback_dist and fallback_dist > radius then
            return nil
        end
        if dgs.nw_z ~= nil then
            local good_x = dgs.dgs_good_x or ((C and C.gateDgsGoodX) or 2.0)
            local good_z_pos = dgs.dgs_good_z_pos or ((C and C.gateDgsGoodZPos) or 0.2)
            local good_z_neg = dgs.dgs_good_z_neg or ((C and C.gateDgsGoodZNeg) or -0.5)
            local locgood = (math.abs(dgs.mw_x or 0) <= good_x)
                and dgs.nw_z >= good_z_neg
                and dgs.nw_z <= good_z_pos
            local dgs_dist = 0
            if locgood or dgs.nw_z < good_z_neg then
                dgs_dist = 0
            else
                dgs_dist = math.max(0, dgs.nw_z)
            end
            if fallback_dist ~= nil then
                local blend_limit = 30
                local max_diff = 15
                if fallback_dist > blend_limit then
                    return nil
                end
                if math.abs(fallback_dist - dgs_dist) > max_diff then
                    return nil
                end
            end
            if ref_dist ~= nil then
                local ref_stop_limit = math.max(15, radius * 0.5)
                local ref_max_diff = math.max(20, radius * 0.45)
                if ref_dist > ref_stop_limit and dgs_dist <= (good_z_pos + 1.0) then
                    return nil
                end
                if (ref_dist - dgs_dist) > ref_max_diff then
                    return nil
                end
            end
        end
        return dgs
    end

    local function select_best_ramp_for_aircraft(data, aircraft, opts)
        if not data or not data.ramps or not aircraft or aircraft.east == nil or aircraft.north == nil then
            return nil, nil
        end
        local filter = opts and opts.filter or nil
        local radius = (opts and opts.radius_m) or (C and C.gateSelectRadius) or 120
        local radius2 = radius * radius
        local heading = opts and opts.heading_deg or nil
        local best_heading = nil
        local best_any = nil
        for _, ramp in ipairs(data.ramps) do
            if filter and not filter(ramp) then
                goto continue
            end
            local local_x, local_z, ramp_hdg, dist = ramp_frame_values(ramp, aircraft)
            if not local_x or not local_z or not dist then
                goto continue
            end
            if dist * dist > radius2 then
                goto continue
            end
            local score_any = dist
            if (not best_any) or score_any < best_any.score then
                best_any = { ramp = ramp, dist = dist, score = score_any }
            end
            if ramp_hdg and heading then
                local hdg_diff = helpers.headingdiff(heading, ramp_hdg)
                if hdg_diff then
                    hdg_diff = math.abs(hdg_diff)
                    local behind_limit = (opts and opts.behind_limit) or (C and C.gateGuidanceBehindLimit) or -5
                    if hdg_diff <= 90 and local_z >= behind_limit then
                        local score = math.sqrt((local_x * 4) * (local_x * 4) + (local_z * local_z)) + hdg_diff
                        if (not best_heading) or score < best_heading.score then
                            best_heading = { ramp = ramp, dist = dist, score = score }
                        end
                    end
                end
            end
            ::continue::
        end
        if best_heading then
            return best_heading.ramp, best_heading.dist
        end
        if best_any then
            return best_any.ramp, best_any.dist
        end
        return nil, nil
    end

    local function gate_alignment_info(comp, aircraft)
        if not comp or not aircraft or not comp._endRamp then
            return nil
        end
        local tuning = comp._tuning or {}
        local radius = tuning.gateGuidanceRadius or (C and C.gateGuidanceRadius) or 60
        local gate_keep = radius * 1.6
        local guidance_limit = radius
        if comp._gateGuidanceActive or comp._gateFinalOwned or comp._gateFinalTurnPending then
            guidance_limit = math.max(radius, gate_keep)
        end
        local deadzone = tuning.gateGuidanceDeadzone or (C and C.gateGuidanceDeadzone) or 0.8
        local behind_limit = tuning.gateGuidanceBehindLimit or (C and C.gateGuidanceBehindLimit) or -5
        local ramp = comp._endRamp
        local local_x, local_z, ramp_hdg, fallback_dist = ramp_frame_values(ramp, aircraft)
        local track_dist, stage, _, stop_limit = gate_tracking_distance(comp, fallback_dist, radius)
        local dgs = trusted_ramp_dgs(ramp, aircraft, fallback_dist, radius, comp and comp._gateActivationDist or nil)
        local direction = "straight"
        local action = "ALIGN"
        local text = "Continue straight"
        local dist = nil
        comp._gateFinalState = stage
        if dgs and stage ~= "approach" then
            local cap_a = (C and C.gateDgsCapA) or 15
            local cap_z = (C and C.gateDgsCapZ) or 105
            local azi_a = (C and C.gateDgsAziA) or 15
            local azi_z = (C and C.gateDgsAziZ) or 85
            local azi_cross = dgs.dgs_azi_cross or ((C and C.gateDgsAziCrossover) or 6)
            local good_x = dgs.dgs_good_x or ((C and C.gateDgsGoodX) or 2.0)
            local good_z_pos = dgs.dgs_good_z_pos or ((C and C.gateDgsGoodZPos) or 0.2)
            local good_z_neg = dgs.dgs_good_z_neg or ((C and C.gateDgsGoodZNeg) or -0.5)
            dist = dgs.nw_z
            if dist == nil then
                return nil
            end
            if dist > radius then
                return nil
            end
            comp._gateUseDgs = true
            local azimuth = 0
            if dist > 0 then
                azimuth = math.deg(math.atan((dgs.nw_x or 0) / (dist + 5.0)))
            end
            local locgood = (math.abs(dgs.mw_x or 0) <= good_x)
                and dist >= good_z_neg
                and dist <= good_z_pos
            local state = comp._gateDgsState or "ENGAGED"
            if state == "ENGAGED" then
                if dist <= cap_z and math.abs(azimuth) <= cap_a then
                    state = "TRACK"
                end
            elseif state == "TRACK" then
                if locgood then
                    state = "GOOD"
                elseif dist < good_z_neg then
                    state = "BAD"
                elseif dist > cap_z or math.abs(azimuth) > cap_a then
                    state = "ENGAGED"
                end
            elseif state == "GOOD" then
                if not locgood then
                    state = "TRACK"
                end
            elseif state == "BAD" then
                if dist >= good_z_neg then
                    state = "TRACK"
                end
            else
                state = "ENGAGED"
            end
            comp._gateDgsState = state

            if stage == "stop" and (state == "GOOD" or state == "BAD" or locgood or dist < good_z_neg) then
                action = "STOP"
                text = "Stop"
            else
                if dist > azi_z or math.abs(azimuth) > azi_a then
                    -- lead-in only, keep straight
                else
                    local ref_z = dgs.ref_z
                    local ref_x = dgs.ref_x
                    if ref_z and ref_x then
                        if ref_z > azi_cross then
                            local req_hdgt = math.deg(math.atan(-ref_x / (0.3 * ref_z)))
                            local d_hdgt = req_hdgt - (dgs.local_hdgt or 0)
                            if d_hdgt < -1.5 then
                                direction = "left"
                                text = "Turn left"
                            elseif d_hdgt > 1.5 then
                                direction = "right"
                                text = "Turn right"
                            end
                        else
                            if ref_x < -0.25 then
                                direction = "right"
                                text = "Turn right"
                            elseif ref_x > 0.25 then
                                direction = "left"
                                text = "Turn left"
                            end
                        end
                    end
                end
            end
            if track_dist ~= nil and (dist == nil or track_dist > dist) then
                dist = track_dist
            end
        else
            if not local_x or not local_z or not fallback_dist then
                return nil
            end
            if fallback_dist > guidance_limit then
                return nil
            end
            dist = track_dist or fallback_dist
            local stop_dist = (C and C.gateStopDistance) or 2
            if stage == "stop" and ramp_hdg and local_z < behind_limit then
                action = "STOP"
                text = "Stop"
            elseif stage == "stop" and local_z <= math.max(stop_dist, stop_limit or stop_dist) then
                action = "STOP"
                text = "Stop"
            else
                if math.abs(local_x) > deadzone then
                    direction = (local_x > 0) and "left" or "right"
                    text = (direction == "left") and "Slight left" or "Slight right"
                end
            end
        end
        local ramp_label = short_ramp_label(ramp)
        if ramp_label == "" then
            ramp_label = "Ramp"
        end
        if action ~= "STOP" then
            if direction == "left" or direction == "right" then
                text = "Turn " .. direction .. " to " .. tostring(ramp_label)
            else
                text = "Taxi to " .. tostring(ramp_label)
            end
        end
        local hold_dist = tuning.gatePopupHoldDist or (C and C.gatePopupHoldDist) or 30
        local display_dist = dist
        if type(display_dist) == "number" then
            if display_dist < 0 then
                display_dist = 0
            end
        end
        return {
            text = text,
            direction = direction,
            action = action,
            label = build_visual_label("ramp", ramp_label),
            kind = "ramp",
            dist = display_dist,
            keepOpen = (hold_dist and display_dist and display_dist <= hold_dist) or false
        }
    end

    local function gate_distance_meters(comp, aircraft, route, data)
        if not comp or not aircraft or aircraft.east == nil or aircraft.north == nil then
            return nil
        end
        local best = nil
        local ax = aircraft.east
        local ay = aircraft.north
        if aircraft.heading and type(aircraft.heading) == "number" then
            local offset = aircraft.nose_offset or (C and C.gateStopOffsetMeters or 10)
            local rad = math.rad(aircraft.heading % 360)
            ax = ax + math.sin(rad) * offset
            ay = ay + math.cos(rad) * offset
        end
        if comp._endRamp then
            local ramp = comp._endRamp
            local local_x, local_z, ramp_hdg, fallback_dist = ramp_frame_values(ramp, aircraft)
            local radius = (C and C.gateGuidanceRadius) or 60
            local track_dist, stage, final_limit, stop_limit = gate_tracking_distance(comp, fallback_dist, radius)
            local dgs = trusted_ramp_dgs(ramp, aircraft, fallback_dist, radius, comp and comp._gateActivationDist or nil)
            comp._gateUseDgs = dgs ~= nil
            comp._gateFinalState = stage
            if dgs and dgs.nw_z ~= nil and stage ~= "approach" then
                local good_x = dgs.dgs_good_x or ((C and C.gateDgsGoodX) or 2.0)
                local good_z_pos = dgs.dgs_good_z_pos or ((C and C.gateDgsGoodZPos) or 0.2)
                local good_z_neg = dgs.dgs_good_z_neg or ((C and C.gateDgsGoodZNeg) or -0.5)
                local locgood = (math.abs(dgs.mw_x or 0) <= good_x)
                    and dgs.nw_z >= good_z_neg
                    and dgs.nw_z <= good_z_pos
                local dgs_dist = 0
                if locgood or dgs.nw_z < good_z_neg then
                    dgs_dist = 0
                else
                    dgs_dist = math.max(0, dgs.nw_z)
                end
                if stage == "stop" and fallback_dist ~= nil then
                    local blend_limit = 30
                    local max_diff = 15
                    if fallback_dist > blend_limit then
                        best = fallback_dist
                    else
                        local diff = math.abs(fallback_dist - dgs_dist)
                        if diff <= max_diff then
                            best = dgs_dist
                        else
                            best = fallback_dist
                        end
                    end
                elseif stage == "stop" then
                    best = dgs_dist
                elseif stage == "final" and track_dist ~= nil then
                    local blend_den = math.max(1, (final_limit or 0) - (stop_limit or 0))
                    local blend_w = clamp((track_dist - (stop_limit or 0)) / blend_den, 0, 1)
                    best = (blend_w * track_dist) + ((1 - blend_w) * dgs_dist)
                else
                    best = track_dist or dgs_dist
                end
            elseif track_dist then
                best = track_dist
            end
        else
            comp._gateUseDgs = false
            comp._gateFinalState = nil
        end
        if (not comp._endRamp) and route and data and route.path and #route.path > 0 and data.nodes then
            local node = data.nodes[route.path[#route.path]]
            if node and node.east ~= nil and node.north ~= nil then
                local d = math.sqrt(distance_sq(ax, ay, node.east, node.north))
                if best == nil or d < best then
                    best = d
                end
            end
        end
        return best
    end

    local function gate_note_text(dist, use_dgs)
        if not dist then
            return nil
        end
        local stop_dist = use_dgs and ((C and C.gateDgsGoodZPos) or 0.2) or ((C and C.gateStopDistance) or 2)
        if dist <= stop_dist then
            return "Stop"
        end
        if dist <= 80 then
            return string.format("Gate in %d m", math.floor(dist + 0.5))
        end
        return nil
    end

    local function reset_gate_callouts(comp, key)
        if not comp then
            return
        end
        comp._gateCalloutKey = key
        comp._gateCalloutStage = 0
        comp._gateCalloutStop = false
        comp._gateDgsState = "ENGAGED"
    end

    local function maybe_gate_voice_callouts(comp, dist, allow_voice, use_dgs)
        if not comp or not dist then
            return
        end
        if not allow_voice or not is_voice_enabled() then
            return
        end
        local stop_dist = use_dgs and ((C and C.gateDgsGoodZPos) or 0.2) or ((C and C.gateStopDistance) or 2)
        if dist <= stop_dist then
            if not comp._gateCalloutStop then
                speak_guidance_text(comp, "Stop")
                comp._gateCalloutStop = true
            end
            return
        end
        local stage = comp._gateCalloutStage or 0
        local thresholds = { 30, 10, 5 }
        for i, threshold in ipairs(thresholds) do
            if dist <= threshold and stage < i then
                speak_guidance_text(comp, "Gate in " .. tostring(threshold) .. " meters")
                comp._gateCalloutStage = i
            end
        end
    end

    U.ramp_frame_values = ramp_frame_values
    U.ramp_dgs_values = ramp_dgs_values
    U.select_best_ramp_for_aircraft = select_best_ramp_for_aircraft
    U._core_gate_distance_meters = gate_distance_meters
    U._core_gate_note_text = gate_note_text
    U._core_reset_gate_callouts = reset_gate_callouts
    U._core_maybe_gate_voice_callouts = maybe_gate_voice_callouts
    U.gate_alignment_info = gate_alignment_info
    U.gate_distance_meters = gate_distance_meters
    U.gate_note_text = gate_note_text
    U.reset_gate_callouts = reset_gate_callouts
    U.maybe_gate_voice_callouts = maybe_gate_voice_callouts
end

return M
