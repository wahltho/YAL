local M = {}

function M.attach(U, C, def, helpers, settings)
    local is_valid_latlon = U.is_valid_latlon
    local latlon_to_local = U.latlon_to_local
    local find_nearest_segment = U.find_nearest_segment
    local project_point_to_segment = U.project_point_to_segment
    local heading_deg_from_to = U.heading_deg_from_to
    local heading_diff_signed = U.heading_diff_signed
    local heading_diff_deg = U.heading_diff_deg
    local is_on_runway_profile = U.is_on_runway_profile
    local is_runway_label = U.is_runway_label
    local get_edge_label = U.get_edge_label
    local clamp = U.clamp
    local distance_sq = U.distance_sq

    local function auto_taxi_log(comp, msg)
        local logger = (comp and comp._logTaxi) or (helpers and helpers.logInfoTS)
        if logger then
            logger("AutoTaxi: " .. tostring(msg))
        end
    end
    local function auto_taxi_log_once(comp, now, key, msg, interval)
        if not comp then
            return
        end
        local t = now or 0
        local last = comp._autoTaxiLogTimes and comp._autoTaxiLogTimes[key] or nil
        local min_dt = interval or 4
        if last and (t - last) < min_dt then
            return
        end
        if not comp._autoTaxiLogTimes then
            comp._autoTaxiLogTimes = {}
        end
        comp._autoTaxiLogTimes[key] = t
        auto_taxi_log(comp, msg)
    end
    local function auto_taxi_log_snapshot(comp, yal, reason)
        if not comp or not yal then
            return
        end
        local s = settings and settings.appSettings or nil
        local fs = yal.flightstate
        local ag = yal.airgroundsensor and get(yal.airgroundsensor) or nil
        local gs = yal.groundspeed and get(yal.groundspeed) or nil
        local pb = yal.parkingbrakepos and get(yal.parkingbrakepos) or nil
        local proc_after = yal.proceduretable and yal.proceduretable[def.AFTERLANDINGPROCEDURE] or nil
        local proc_before = yal.proceduretable and yal.proceduretable[def.BEFORETAXIPROCEDURE] or nil
        local l1 = yal.loopStateTables and yal.loopStateTables[1] and yal.loopStateTables[1].lock or nil
        local l2 = yal.loopStateTables and yal.loopStateTables[2] and yal.loopStateTables[2].lock or nil
        local l3 = yal.loopStateTables and yal.loopStateTables[3] and yal.loopStateTables[3].lock or nil
        local route_len = (comp._route and comp._route.path and #comp._route.path) or 0
        local msg = "override snapshot"
        if reason and reason ~= "" then
            msg = msg .. " " .. tostring(reason)
        end
        msg = msg
            .. " mode=" .. tostring(comp.mode)
            .. " autoMode=" .. tostring(comp.autoMode)
            .. " fs=" .. tostring(fs)
            .. " ag=" .. tostring(ag)
            .. " gs=" .. string.format("%.2f", (gs or 0))
            .. " pb=" .. tostring(pb)
            .. " route=" .. tostring(route_len)
            .. " beforeSet=" .. tostring(proc_before and proc_before.set)
            .. " afterSet=" .. tostring(proc_after and proc_after.set)
            .. " locks=" .. tostring(l1) .. "/" .. tostring(l2) .. "/" .. tostring(l3)
        if s then
            msg = msg
                .. " auto=" .. tostring(s[def.CONFIGAUTOFUNCTIONS])
                .. " guide=" .. tostring(s[def.CONFIGAUTOTAXIGUIDANCE])
                .. " taxi=" .. tostring(s[def.CONFIGAUTOTAXIING])
                .. " adv=" .. tostring(s[def.CONFIGVOICEADVICEONLY])
        end
        auto_taxi_log(comp, msg)
    end
    local function auto_taxi_log_snapshot_once(comp, now, key, yal, reason)
        if not comp then
            return
        end
        local k = "snap:" .. tostring(key or "")
        local t = now or 0
        local last = comp._autoTaxiLogTimes and comp._autoTaxiLogTimes[k] or nil
        local min_dt = 4
        if last and (t - last) < min_dt then
            return
        end
        if not comp._autoTaxiLogTimes then
            comp._autoTaxiLogTimes = {}
        end
        comp._autoTaxiLogTimes[k] = t
        auto_taxi_log_snapshot(comp, yal, reason)
    end

    local function before_taxi_started(comp)
        local yal = comp and (comp.yal or _G.yal) or nil
        if not yal then
            return false
        end
        local proc = yal.proceduretable and yal.proceduretable[def.BEFORETAXIPROCEDURE]
        if proc and proc.set then
            return true
        end
        if yal.loopStateTables then
            for _, loop in ipairs(yal.loopStateTables) do
                if loop and loop.lock == def.BEFORETAXIPROCEDURE then
                    return true
                end
            end
        else
            local l1 = yal.procedureloop1
            local l2 = yal.procedureloop2
            local l3 = yal.procedureloop3
            if (l1 and l1.lock == def.BEFORETAXIPROCEDURE)
                or (l2 and l2.lock == def.BEFORETAXIPROCEDURE)
                or (l3 and l3.lock == def.BEFORETAXIPROCEDURE) then
                return true
            end
        end
        return false
    end

    local function guidance_action_needs_slow(action)
        return action == "TURN LEFT"
            or action == "TURN RIGHT"
            or action == "ENTER RWY"
            or action == "EXIT RWY"
            or action == "CROSS RWY"
            or action == "HOLD SHORT"
            or action == "LINE UP"
            or action == "TAKEOFF"
    end

    local function auto_taxi_guidance_target(comp, seg_idx)
        if not comp then
            return nil
        end
        local active = comp._guidanceInstruction
        if active and active.action then
            local target_seg = tonumber(active.targetSegIdx or 0) or 0
            local commit_seg = tonumber(comp._guidanceInstructionCommitSeg or target_seg or 0) or 0
            if commit_seg < target_seg then
                commit_seg = target_seg
            end
            if commit_seg > 0 then
                if seg_idx and seg_idx > commit_seg then
                    return nil
                end
                local follow_seg = math.max(target_seg, commit_seg)
                if seg_idx and follow_seg < seg_idx then
                    follow_seg = seg_idx
                end
                return {
                    targetSegIdx = follow_seg,
                    commitSegIdx = commit_seg,
                    action = active.action,
                    display = tostring(active.display or comp._autoTaxiTargetLabel or "")
                }
            end
        end
        local target_seg = tonumber(comp._autoTaxiTargetSegIdx or 0) or 0
        if target_seg <= 0 then
            return nil
        end
        return {
            targetSegIdx = target_seg,
            commitSegIdx = target_seg,
            action = comp._autoTaxiTargetAction,
            display = tostring(comp._autoTaxiTargetLabel or "")
        }
    end

    local function auto_taxi_apply_overrides(comp, yal)
        if not comp or not yal or comp._autoTaxiOverrideActive then
            return
        end
        if comp._autoTaxiAllowOverride == false then
            return
        end
        auto_taxi_log_snapshot(comp, yal, "activate")
        auto_taxi_log(comp, "overrides on")
        comp._autoTaxiOverrideActive = true
        if yal.zibo_throttle_override and isProperty(yal.zibo_throttle_override) then
            comp._autoTaxiPrevOverrideThrottles = get(yal.zibo_throttle_override)
            set(yal.zibo_throttle_override, def.ON)
        end
        if yal.zibo_nosewheel_steer_override and isProperty(yal.zibo_nosewheel_steer_override) then
            comp._autoTaxiPrevOverrideSteer = get(yal.zibo_nosewheel_steer_override)
            set(yal.zibo_nosewheel_steer_override, def.ON)
        end
        if yal.zibo_toe_brake_override and isProperty(yal.zibo_toe_brake_override) then
            comp._autoTaxiPrevOverrideBrakes = get(yal.zibo_toe_brake_override)
            set(yal.zibo_toe_brake_override, def.ON)
        end
        if yal.throttle_use_1 and isProperty(yal.throttle_use_1) then
            comp._autoTaxiPrevThrottle1 = get(yal.throttle_use_1)
        end
        if yal.throttle_use_2 and isProperty(yal.throttle_use_2) then
            comp._autoTaxiPrevThrottle2 = get(yal.throttle_use_2)
        end
        if yal.left_brake_ratio and isProperty(yal.left_brake_ratio) then
            comp._autoTaxiPrevBrakeL = get(yal.left_brake_ratio)
        end
        if yal.right_brake_ratio and isProperty(yal.right_brake_ratio) then
            comp._autoTaxiPrevBrakeR = get(yal.right_brake_ratio)
        end
        if yal.tire_steer_cmd and isProperty(yal.tire_steer_cmd) then
            comp._autoTaxiPrevSteer = get(yal.tire_steer_cmd)
        end
    end

    local function auto_taxi_release_controls(comp, yal, reason)
        if not comp then
            return
        end
        local had_active = comp._autoTaxiActive or comp._autoTaxiOverrideActive
        if had_active then
            auto_taxi_log(comp, "release " .. tostring(reason or ""))
        end
        if had_active and yal then
            if comp._autoTaxiOverrideActive then
                if yal.zibo_throttle_override and isProperty(yal.zibo_throttle_override) then
                    set(yal.zibo_throttle_override, comp._autoTaxiPrevOverrideThrottles or def.OFF)
                end
                if yal.zibo_nosewheel_steer_override and isProperty(yal.zibo_nosewheel_steer_override) then
                    set(yal.zibo_nosewheel_steer_override, comp._autoTaxiPrevOverrideSteer or def.OFF)
                end
                if yal.zibo_toe_brake_override and isProperty(yal.zibo_toe_brake_override) then
                    set(yal.zibo_toe_brake_override, comp._autoTaxiPrevOverrideBrakes or def.OFF)
                end
            end
            if yal.throttle_use_1 and isProperty(yal.throttle_use_1) then
                if comp._autoTaxiPrevThrottle1 ~= nil then
                    set(yal.throttle_use_1, comp._autoTaxiPrevThrottle1)
                else
                    set(yal.throttle_use_1, 0)
                end
            end
            if yal.throttle_use_2 and isProperty(yal.throttle_use_2) then
                if comp._autoTaxiPrevThrottle2 ~= nil then
                    set(yal.throttle_use_2, comp._autoTaxiPrevThrottle2)
                else
                    set(yal.throttle_use_2, 0)
                end
            end
            if yal.left_brake_ratio and isProperty(yal.left_brake_ratio) then
                if comp._autoTaxiPrevBrakeL ~= nil then
                    set(yal.left_brake_ratio, comp._autoTaxiPrevBrakeL)
                else
                    set(yal.left_brake_ratio, 0)
                end
            end
            if yal.right_brake_ratio and isProperty(yal.right_brake_ratio) then
                if comp._autoTaxiPrevBrakeR ~= nil then
                    set(yal.right_brake_ratio, comp._autoTaxiPrevBrakeR)
                else
                    set(yal.right_brake_ratio, 0)
                end
            end
            if yal.tire_steer_cmd and isProperty(yal.tire_steer_cmd) then
                if comp._autoTaxiPrevSteer ~= nil then
                    set(yal.tire_steer_cmd, comp._autoTaxiPrevSteer)
                else
                    set(yal.tire_steer_cmd, 0)
                end
            end
        end
        comp._autoTaxiOverrideActive = false
        comp._autoTaxiPrevOverrideThrottles = nil
        comp._autoTaxiPrevOverrideSteer = nil
        comp._autoTaxiPrevOverrideBrakes = nil
        comp._autoTaxiPrevThrottle1 = nil
        comp._autoTaxiPrevThrottle2 = nil
        comp._autoTaxiPrevBrakeL = nil
        comp._autoTaxiPrevBrakeR = nil
        comp._autoTaxiPrevSteer = nil
        comp._autoTaxiSteer = nil
        comp._autoTaxiSteerTime = nil
        comp._autoTaxiLastBrake = nil
        comp._autoTaxiTurnSlow = nil
        comp._autoTaxiActiveSegIdx = nil
        comp._autoTaxiActiveRoute = nil
        comp._autoTaxiActive = false
        comp._autoTaxiAllowOverride = false
    end

    local function auto_taxi_manual_input(comp, yal, now)
        if not yal then
            return nil
        end
        local zthr1 = (yal.zibo_axis_throttle1 and get(yal.zibo_axis_throttle1)) or nil
        local zthr2 = (yal.zibo_axis_throttle2 and get(yal.zibo_axis_throttle2)) or nil
        if zthr1 ~= nil or zthr2 ~= nil then
            local z1 = zthr1 or 0
            local z2 = zthr2 or 0
            if math.abs(z1) > 0.05 or math.abs(z2) > 0.05 then
                return "throttle"
            end
        else
            local thr1 = (yal.hardware_throttle_1 and get(yal.hardware_throttle_1)) or 0
            local thr2 = (yal.hardware_throttle_2 and get(yal.hardware_throttle_2)) or 0
            if thr1 > 0.05 or thr2 > 0.05 then
                return "throttle"
            end
        end
        local yaw = nil
        if yal.zibo_axis_heading then
            yaw = get(yal.zibo_axis_heading)
        end
        if yaw == nil then
            yaw = (yal.yoke_heading_ratio and get(yal.yoke_heading_ratio)) or 0
            local yaw2 = (yal.yoke_heading_ratio_cockpit and get(yal.yoke_heading_ratio_cockpit)) or nil
            if yaw2 ~= nil and math.abs(yaw2) > math.abs(yaw) then
                yaw = yaw2
            end
        end
        if math.abs(yaw) > 0.2 then
            if not now then
                return "steer"
            end
            local t = comp and comp._autoTaxiManualType or nil
            if t ~= "steer" then
                comp._autoTaxiManualType = "steer"
                comp._autoTaxiManualSince = now
                return nil
            end
            local since = comp._autoTaxiManualSince or now
            local debounce = (C and C.autoTaxiManualDebounceSec) or 0.4
            if (now - since) >= debounce then
                return "steer"
            end
            return nil
        end
        local nw1 = (yal.zibo_axis_nosewheel and get(yal.zibo_axis_nosewheel)) or nil
        local nw2 = (yal.zibo_axis_nosewheel2 and get(yal.zibo_axis_nosewheel2)) or nil
        local nw3 = (yal.zibo_axis_nosewheel3 and get(yal.zibo_axis_nosewheel3)) or nil
        local nw = nil
        if nw1 ~= nil then
            nw = math.abs(nw1)
        end
        if nw2 ~= nil then
            local v = math.abs(nw2)
            if nw == nil or v > nw then
                nw = v
            end
        end
        if nw3 ~= nil then
            local v = math.abs(nw3)
            if nw == nil or v > nw then
                nw = v
            end
        end
        if nw ~= nil and nw > 0.05 then
            if not now then
                return "tiller"
            end
            local t = comp and comp._autoTaxiManualType or nil
            if t ~= "tiller" then
                comp._autoTaxiManualType = "tiller"
                comp._autoTaxiManualSince = now
                return nil
            end
            local since = comp._autoTaxiManualSince or now
            local debounce = (C and C.autoTaxiManualDebounceSec) or 0.4
            if (now - since) >= debounce then
                return "tiller"
            end
            return nil
        end
        local zlb = (yal.zibo_axis_left_toe_brake and get(yal.zibo_axis_left_toe_brake)) or nil
        local zrb = (yal.zibo_axis_right_toe_brake and get(yal.zibo_axis_right_toe_brake)) or nil
        if zlb ~= nil or zrb ~= nil then
            local lbrake = math.abs(zlb or 0)
            local rbrake = math.abs(zrb or 0)
            if lbrake > 0.1 or rbrake > 0.1 then
                if not now then
                    return "brake"
                end
                local t = comp and comp._autoTaxiManualType or nil
                if t ~= "brake" then
                    comp._autoTaxiManualType = "brake"
                    comp._autoTaxiManualSince = now
                    return nil
                end
                local since = comp._autoTaxiManualSince or now
                local debounce = (C and C.autoTaxiManualDebounceSec) or 0.4
                if (now - since) >= debounce then
                    return "brake"
                end
                return nil
            end
        else
            local lbrake = (yal.left_brake_ratio and get(yal.left_brake_ratio)) or 0
            local rbrake = (yal.right_brake_ratio and get(yal.right_brake_ratio)) or 0
            if comp and comp._autoTaxiOverrideActive and comp._autoTaxiLastBrake ~= nil then
                local ref = comp._autoTaxiLastBrake
                if lbrake > (ref + 0.08) or rbrake > (ref + 0.08) then
                    if not now then
                        return "brake"
                    end
                    local t = comp._autoTaxiManualType
                    if t ~= "brake" then
                        comp._autoTaxiManualType = "brake"
                        comp._autoTaxiManualSince = now
                        return nil
                    end
                    local since = comp._autoTaxiManualSince or now
                    local debounce = (C and C.autoTaxiManualDebounceSec) or 0.4
                    if (now - since) >= debounce then
                        return "brake"
                    end
                    return nil
                end
            else
                if lbrake > 0.1 or rbrake > 0.1 then
                    if not now then
                        return "brake"
                    end
                    local t = comp and comp._autoTaxiManualType or nil
                    if t ~= "brake" then
                        comp._autoTaxiManualType = "brake"
                        comp._autoTaxiManualSince = now
                        return nil
                    end
                    local since = comp._autoTaxiManualSince or now
                    local debounce = (C and C.autoTaxiManualDebounceSec) or 0.4
                    if (now - since) >= debounce then
                        return "brake"
                    end
                    return nil
                end
            end
        end
        if yal.parkingbrakepos and get(yal.parkingbrakepos) == def.ON then
            if comp then
                comp._autoTaxiManualType = nil
                comp._autoTaxiManualSince = nil
            end
            return "parking-brake"
        end
        if comp then
            comp._autoTaxiManualType = nil
            comp._autoTaxiManualSince = nil
        end
        return nil
    end

    local function auto_taxi_align_runway(comp, now, yal, aircraft, force_hold)
        if not comp or comp.mode ~= 0 or not yal or not aircraft then
            return false
        end
        if comp._depTaxiCompleteAnnounced or comp._routeErr == "taxi-complete" then
            return false
        end
        local profile = comp._depProfile
        if not profile or not profile.axis then
            return false
        end
        if not is_on_runway_profile(profile, aircraft, 80, 15) then
            return false
        end
        local limit = (C and C.autoTaxiAlignHeadingDeg) or 8
        local axis_heading_true = math.deg(math.atan2(profile.axis.x, profile.axis.y))
        if axis_heading_true < 0 then
            axis_heading_true = axis_heading_true + 360
        end
        local mag_var = 0
        if aircraft.lat and aircraft.lon then
            mag_var = sasl.getMagneticVariation(aircraft.lat, aircraft.lon) or 0
        end
        local axis_heading_mag = (axis_heading_true - mag_var + 360) % 360
        local hdg = (yal.groundtrackmag and get(yal.groundtrackmag)) or nil
        if hdg == nil then
            local hdg_true = yal.localpositionpsi and get(yal.localpositionpsi) or nil
            if hdg_true ~= nil then
                hdg = (hdg_true - mag_var + 360) % 360
            end
        end
        if hdg == nil then
            return false
        end
        local diff = heading_diff_deg(hdg, axis_heading_mag)
        if diff == nil then
            comp._autoTaxiAlignActive = false
            return false
        end
        if diff <= limit and not force_hold then
            comp._autoTaxiAlignActive = false
            return false
        end
        comp._autoTaxiAllowOverride = true
        local diff_signed = heading_diff_signed(axis_heading_mag, hdg)
        local max_err = (C and C.autoTaxiSteerMaxErrDeg) or 35
        local max_steer = (C and C.autoTaxiSteerMaxDeg) or 25
        local steer = clamp(diff_signed, -max_err, max_err)
        if max_err > 0 then
            steer = (steer / max_err) * max_steer
        end
        local prev = comp._autoTaxiSteer or 0
        local prev_time = comp._autoTaxiSteerTime or now
        local rate = (C and C.autoTaxiSteerSlewDegPerSec) or 90
        local dt = (now or 0) - (prev_time or 0)
        if dt < 0 then
            dt = 0
        end
        local max_delta = rate * dt
        if steer > (prev + max_delta) then
            steer = prev + max_delta
        elseif steer < (prev - max_delta) then
            steer = prev - max_delta
        end
        comp._autoTaxiSteer = steer
        comp._autoTaxiSteerTime = now

        local gs_kts = (yal.groundspeed and (get(yal.groundspeed) or 0)) or 0
        local target_kts = (C and C.autoTaxiAlignSpeedKts) or (C and C.autoTaxiTurnSpeedKts) or 5
        local throttle_base = (C and C.autoTaxiThrottleBase) or 0.05
        local throttle_kp = (C and C.autoTaxiThrottleKp) or 0.03
        local throttle_max = (C and C.autoTaxiThrottleMax) or 0.25
        local brake_kp = (C and C.autoTaxiBrakeKp) or 0.12
        local brake_max = (C and C.autoTaxiBrakeMax) or 0.6
        local throttle = throttle_base + (target_kts - gs_kts) * throttle_kp
        if throttle < 0 then
            throttle = 0
        elseif throttle > throttle_max then
            throttle = throttle_max
        end
        local brake = 0
        if gs_kts > target_kts then
            brake = (gs_kts - target_kts) * brake_kp
            if brake > brake_max then
                brake = brake_max
            end
            throttle = 0
        end

        auto_taxi_apply_overrides(comp, yal)
        if yal.tire_steer_cmd and isProperty(yal.tire_steer_cmd) then
            set(yal.tire_steer_cmd, steer)
        end
        if yal.throttle_use_1 and isProperty(yal.throttle_use_1) then
            set(yal.throttle_use_1, throttle)
        end
        if yal.throttle_use_2 and isProperty(yal.throttle_use_2) then
            set(yal.throttle_use_2, throttle)
        end
        if yal.left_brake_ratio and isProperty(yal.left_brake_ratio) then
            set(yal.left_brake_ratio, brake)
        end
        if yal.right_brake_ratio and isProperty(yal.right_brake_ratio) then
            set(yal.right_brake_ratio, brake)
        end
        comp._autoTaxiActive = true
        comp._autoTaxiAlignActive = true
        auto_taxi_log_once(comp, now, "align-rwy", string.format("align runway hdg diff=%.1f", diff), 2)
        return true
    end

    local function auto_taxi_apply_controls(comp, now, yal, aircraft)
        if not comp or not yal or not aircraft then
            return false
        end
        if comp._autoTaxiAllowOverride == false then
            return false
        end
        local route = comp._route
        if not route or not route.path or not route.data or not route.data.nodes then
            return false
        end
        local path = route.path
        if comp._autoTaxiPath and comp._autoTaxiPathRoute == route and #comp._autoTaxiPath > 1 then
            path = comp._autoTaxiPath
        end
        if #path < 2 then
            return false
        end
        local data = route.data
        local seg_idx, dist_route = find_nearest_segment(data, path, aircraft.east, aircraft.north)
        if not seg_idx or seg_idx >= #path then
            return false
        end
        if comp._autoTaxiActiveRoute ~= route then
            comp._autoTaxiActiveRoute = route
            comp._autoTaxiActiveSegIdx = nil
            comp._autoTaxiLastSegIdx = nil
            comp._autoTaxiEndStopLatched = false
        end
        local active_seg = comp._autoTaxiActiveSegIdx
        if active_seg and active_seg >= #path then
            active_seg = nil
            comp._autoTaxiActiveSegIdx = nil
        end
        if active_seg and active_seg ~= seg_idx then
            local use_active = false
            if active_seg > seg_idx then
                use_active = true
            else
                local an1 = data.nodes[path[active_seg]]
                local an2 = data.nodes[path[active_seg + 1]]
                if an1 and an2 and an1.east and an1.north and an2.east and an2.north then
                    local _, _, t = project_point_to_segment(
                        aircraft.east, aircraft.north,
                        an1.east, an1.north,
                        an2.east, an2.north
                    )
                    if t and t < 1 then
                        use_active = true
                    end
                end
            end
            if use_active then
                seg_idx = active_seg
            else
                comp._autoTaxiActiveSegIdx = seg_idx
            end
        elseif not active_seg then
            comp._autoTaxiActiveSegIdx = seg_idx
        end
        do
            if data and data.nodes and path[seg_idx] and path[seg_idx + 1] and path[seg_idx + 2] then
                local n_from = data.nodes[path[seg_idx]]
                local n_to = data.nodes[path[seg_idx + 1]]
                if n_from and n_to and n_from.east and n_from.north and n_to.east and n_to.north then
                    local d_from = distance_sq(aircraft.east, aircraft.north, n_from.east, n_from.north)
                    local d_to = distance_sq(aircraft.east, aircraft.north, n_to.east, n_to.north)
                    if d_to < d_from then
                        seg_idx = seg_idx + 1
                        comp._autoTaxiActiveSegIdx = seg_idx
                    end
                end
            end
        end
        local path_len = #path
        local near_end = (path_len > 1 and seg_idx >= (path_len - 1)) or false
        local max_offroute = (C and C.autoTaxiOffRouteMeters) or 20
        if dist_route and max_offroute > 0 then
            local on_runway = false
            if is_runway_label and get_edge_label then
                local raw_label = get_edge_label(data, path[seg_idx], path[seg_idx + 1])
                if raw_label and is_runway_label(raw_label) then
                    local profile = (comp.mode == 0 and comp._depProfile) or (comp.mode == 1 and comp._arrProfile) or nil
                    if profile and is_on_runway_profile and is_on_runway_profile(profile, aircraft, 80, 15) then
                        on_runway = true
                    end
                end
            elseif data.runway_nodes and (data.runway_nodes[path[seg_idx]] or data.runway_nodes[path[seg_idx + 1]]) then
                local profile = (comp.mode == 0 and comp._depProfile) or (comp.mode == 1 and comp._arrProfile) or nil
                if profile and is_on_runway_profile and is_on_runway_profile(profile, aircraft, 80, 15) then
                    on_runway = true
                end
            end
            if not on_runway and comp.mode == 1 then
                local profile = comp._arrProfile
                if profile and is_on_runway_profile and is_on_runway_profile(profile, aircraft, 80, 15) then
                    on_runway = true
                elseif yal and yal.aircraftonrwy then
                    on_runway = not yal.aircraftonrwy(def.ARRIVAL, 40, 20)
                end
            end
            if not on_runway and comp.mode == 0 then
                local profile = comp._depProfile
                if profile and is_on_runway_profile and is_on_runway_profile(profile, aircraft, 80, 15) then
                    on_runway = true
                end
            end
            if comp.mode == 0 and (comp._depThresholdReached or comp._depThresholdLatched) and yal and yal.aircraftonrwy then
                local on_rwy = yal.aircraftonrwy(def.DEPARTURE, 40, (C and C.depThresholdHeadingLimit) or 25)
                if on_rwy then
                    comp._autoTaxiRunwaySegIdx = comp._autoTaxiRunwaySegIdx or seg_idx
                    if auto_taxi_align_runway(comp, now, yal, aircraft, true) then
                        return true
                    end
                    seg_idx = comp._autoTaxiRunwaySegIdx
                else
                    comp._autoTaxiRunwaySegIdx = nil
                end
            else
                comp._autoTaxiRunwaySegIdx = nil
            end
            if on_runway then
                comp._autoTaxiOffrouteActive = false
            else
            local clear_dist = max_offroute * ((C and C.autoTaxiOffRouteClearFactor) or 0.7)
            local last_dist = comp._autoTaxiDivergeLastDist
            if last_dist and dist_route > last_dist and dist_route > clear_dist then
                if not comp._autoTaxiDivergeStart and now then
                    comp._autoTaxiDivergeStart = now
                end
            else
                comp._autoTaxiDivergeStart = nil
            end
            comp._autoTaxiDivergeLastDist = dist_route
            local reroute_cooldown = (C and C.rerouteCooldown) or 6
            local last_reroute = comp._lastRerouteTime or 0
            if comp._autoTaxiDivergeStart and now and (now - comp._autoTaxiDivergeStart) >= reroute_cooldown then
                if now and (now - last_reroute) >= reroute_cooldown then
                    if not (comp._editRoute or comp._drawRoute) and aircraft.lat and aircraft.lon then
                        if near_end then
                            auto_taxi_log_once(comp, now, "diverge-reroute-end", "skip reroute (near end)")
                            comp._autoTaxiDivergeStart = nil
                        else
                        comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
                        comp._routeStartAnchor = nil
                        comp._lastStartKey = nil
                        comp._route = nil
                        comp._routeErr = nil
                        comp._routeLabels = nil
                        comp._routeLabelStats = nil
                        comp._lastRerouteTime = now
                        comp._pendingRerouteEvent = true
                        comp._autoTaxiDivergeStart = nil
                        auto_taxi_log_once(comp, now, "diverge-reroute", "reroute reanchor (diverge)")
                        return false
                        end
                    end
                end
                comp._autoTaxiDivergeStart = nil
            end
            if comp._autoTaxiOffrouteActive then
                if dist_route <= clear_dist then
                    comp._autoTaxiOffrouteActive = false
                else
                    auto_taxi_log_once(
                        comp,
                        now,
                        "offroute-hold",
                        string.format("blocked: offroute hold dist=%.1f m", dist_route)
                    )
                    return false
                end
            end
            if dist_route > max_offroute then
                if comp.mode == 0 and (comp._depThresholdReached or comp._depThresholdLatched) then
                    auto_taxi_log_once(comp, now, "offroute-depentry", "blocked: offroute during dep-entry")
                    return false
                end
                comp._autoTaxiOffrouteActive = true
                auto_taxi_log_once(
                    comp,
                    now,
                    "offroute",
                    string.format("blocked: offroute dist=%.1f m", dist_route)
                )
                local reroute_cooldown = (C and C.rerouteCooldown) or 6
                local last_reroute = comp._lastRerouteTime or 0
                if now and (now - last_reroute) >= reroute_cooldown then
                    if not (comp._editRoute or comp._drawRoute) and aircraft.lat and aircraft.lon then
                        if near_end then
                            auto_taxi_log_once(comp, now, "offroute-reroute-end", "skip reroute (near end)")
                        else
                        comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
                        comp._routeStartAnchor = nil
                        comp._lastStartKey = nil
                        comp._route = nil
                        comp._routeErr = nil
                        comp._routeLabels = nil
                        comp._routeLabelStats = nil
                        comp._lastRerouteTime = now
                        comp._pendingRerouteEvent = true
                        auto_taxi_log_once(comp, now, "offroute-reroute", "reroute reanchor")
                        end
                    end
                end
                return false
            end
            end
        end
        local guidance_target = auto_taxi_guidance_target(comp, seg_idx)
        if comp._autoTaxiTargetSegIdx then
            local release_seg = guidance_target and guidance_target.commitSegIdx or comp._autoTaxiTargetSegIdx
            if seg_idx > release_seg then
                comp._autoTaxiTargetSegIdx = nil
                comp._autoTaxiTargetTime = nil
                comp._autoTaxiTargetAction = nil
                comp._autoTaxiTargetLabel = nil
                if not comp._guidanceInstruction then
                    guidance_target = nil
                end
            end
        end
        local n1 = data.nodes[path[seg_idx]]
        local n2 = data.nodes[path[seg_idx + 1]]
        if not n1 or not n2 then
            return false
        end
        local dx = n2.east - n1.east
        local dy = n2.north - n1.north
        local seg_len = math.sqrt(dx * dx + dy * dy)
        local gs_kts = (yal.groundspeed and (get(yal.groundspeed) or 0)) or 0
        local lookahead_base = (C and C.autoTaxiLookaheadMeters) or 25
        local lookahead_min = (C and C.autoTaxiLookaheadMinMeters) or 10
        local lookahead_max = (C and C.autoTaxiLookaheadMaxMeters) or 40
        local lookahead_speed = (C and C.autoTaxiLookaheadSpeedKts) or 1.2
        local lookahead_m = clamp(gs_kts * lookahead_speed, lookahead_min, lookahead_max)
        if lookahead_base and lookahead_base > 0 then
            local hi = math.max(lookahead_max, lookahead_base)
            lookahead_m = clamp(math.max(lookahead_m, lookahead_base), lookahead_min, hi)
        end
        local look_t = 0.5
        if seg_len > 0 then
            local _, _, t = project_point_to_segment(
                aircraft.east, aircraft.north,
                n1.east, n1.north,
                n2.east, n2.north
            )
            if t then
                look_t = clamp(t + (lookahead_m / seg_len), 0, 1)
            end
        end
        local lx = n1.east + dx * look_t
        local ly = n1.north + dy * look_t
        local dist_to_node = math.sqrt(
            (n2.east - aircraft.east) * (n2.east - aircraft.east)
            + (n2.north - aircraft.north) * (n2.north - aircraft.north)
        )
        local turn_lead = (C and C.autoTaxiTurnLeadMeters) or 20
        local lead_m = (C and C.autoTaxiGuidanceLeadMeters) or 0
        if lead_m <= 0 or turn_lead > lead_m then
            lead_m = turn_lead
        end
        local lead_speed = (C and C.autoTaxiTurnLeadSpeedKts) or 0
        if lead_speed > 0 then
            local lead_min = (C and C.autoTaxiTurnLeadMinMeters) or lead_m
            local lead_max = (C and C.autoTaxiTurnLeadMaxMeters) or lead_m
            local dyn_lead = clamp(gs_kts * lead_speed, lead_min, lead_max)
            if dyn_lead > lead_m then
                lead_m = dyn_lead
            end
        end
        local turn_min_seg = (C and C.autoTaxiTurnMinSegMeters) or 15
        if comp._autoTaxiActiveTargetFrom ~= seg_idx then
            if not (comp._autoTaxiActiveTargetSegIdx and comp._autoTaxiActiveTargetSegIdx > seg_idx) then
                comp._autoTaxiActiveTargetSegIdx = nil
            end
            comp._autoTaxiActiveTargetFrom = seg_idx
        end
        local target_idx = nil
        local target_reason = nil
        if comp._autoTaxiActiveTargetSegIdx and comp._autoTaxiActiveTargetSegIdx > seg_idx then
            target_idx = comp._autoTaxiActiveTargetSegIdx
            target_reason = "hold"
        end
        local gidx = guidance_target and guidance_target.targetSegIdx or comp._autoTaxiTargetSegIdx
        local target_lead = lead_m
        local target_lead_cfg = (C and C.autoTaxiGuidanceTargetLeadMeters) or 0
        if target_lead_cfg > target_lead then
            target_lead = target_lead_cfg
        end
        local turn_lead_active = math.max(turn_lead, lead_m, lookahead_m)
        if (not guidance_target) and gidx and gidx > seg_idx and gidx <= (#path - 1) and dist_to_node <= target_lead then
            local stale_sec = (C and C.autoTaxiGuidanceTargetStaleSec) or 12
            if comp._autoTaxiTargetTime and now and (now - comp._autoTaxiTargetTime) > stale_sec then
                gidx = nil
            end
        end
        if (not target_idx) and gidx and gidx > seg_idx and gidx <= (#path - 1) and dist_to_node <= target_lead then
            if guidance_target then
                target_idx = gidx
                target_reason = "guidance-transition"
            else
                local h_curr = heading_deg_from_to(n1.east, n1.north, n2.east, n2.north)
                local tn1 = data.nodes[path[gidx]]
                local tn2 = data.nodes[path[gidx + 1]]
                if h_curr and tn1 and tn2 and tn1.east and tn1.north and tn2.east and tn2.north then
                    local tdx = tn2.east - tn1.east
                    local tdy = tn2.north - tn1.north
                    local tlen = math.sqrt(tdx * tdx + tdy * tdy)
                    if tlen >= turn_min_seg then
                        local h_tgt = heading_deg_from_to(tn1.east, tn1.north, tn2.east, tn2.north)
                        if h_tgt and heading_diff_deg(h_curr, h_tgt) >= ((C and C.autoTaxiTurnAngleDeg) or 25) * 0.5 then
                            target_idx = gidx
                            target_reason = "guidance"
                        end
                    end
                end
            end
        end
        if not target_idx and (seg_idx + 2) <= #path and dist_to_node <= turn_lead_active then
            local n3 = data.nodes[path[seg_idx + 2]]
            if n3 and n3.east and n3.north then
                local h1 = heading_deg_from_to(n1.east, n1.north, n2.east, n2.north)
                local h2 = heading_deg_from_to(n2.east, n2.north, n3.east, n3.north)
                local turn_angle = (C and C.autoTaxiTurnAngleDeg) or 25
                local dx2 = n3.east - n2.east
                local dy2 = n3.north - n2.north
                local len2 = math.sqrt(dx2 * dx2 + dy2 * dy2)
                if h1 and h2 and len2 >= turn_min_seg and heading_diff_deg(h1, h2) >= turn_angle then
                    target_idx = seg_idx + 1
                    target_reason = "geom-turn"
                end
            end
        end
        -- NOTE: geom-scurve targeting disabled to avoid visible weaving on taxi-in/out.
        if target_idx then
            comp._autoTaxiActiveTargetSegIdx = target_idx
        else
            comp._autoTaxiActiveTargetSegIdx = nil
        end
        if target_idx and comp._autoTaxiLastTarget ~= target_idx then
            comp._autoTaxiLastTarget = target_idx
            if target_reason then
                auto_taxi_log(comp, "target seg " .. tostring(target_idx) .. " (" .. tostring(target_reason) .. ")")
            else
                auto_taxi_log(comp, "target seg " .. tostring(target_idx))
            end
        end
        if target_idx then
            local tn1 = data.nodes[path[target_idx]]
            local tn2 = data.nodes[path[target_idx + 1]]
            if tn1 and tn2 and tn1.east and tn1.north and tn2.east and tn2.north then
                local tdx = tn2.east - tn1.east
                local tdy = tn2.north - tn1.north
                local tlen = math.sqrt(tdx * tdx + tdy * tdy)
                if tlen > 0.1 then
                    local tlook = clamp(lookahead_m / tlen, 0, 1)
                    lx = tn1.east + tdx * tlook
                    ly = tn1.north + tdy * tlook
                end
            end
        end
        local desired_true = heading_deg_from_to(aircraft.east, aircraft.north, lx, ly)
        if not desired_true then
            return false
        end
        if comp._guidanceState == "gate" and comp._endRamp then
            local ramp = comp._endRamp
            local east = ramp.east
            local north = ramp.north
            if (east == nil or north == nil) and is_valid_latlon(ramp.lat, ramp.lon) then
                east, north = latlon_to_local(ramp.lat, ramp.lon)
            end
            if east ~= nil and north ~= nil then
                local gate_dist = (U.gate_distance_meters and U.gate_distance_meters(comp, aircraft, route, data)) or nil
                local gate_radius = (C and C.gateGuidanceRadius) or 60
                if gate_dist and gate_dist <= (gate_radius * 1.2) then
                    local gate_heading = heading_deg_from_to(aircraft.east, aircraft.north, east, north)
                    if gate_heading then
                        desired_true = gate_heading
                    end
                end
            end
        end
        local mag_var = 0
        if aircraft.lat and aircraft.lon then
            mag_var = sasl.getMagneticVariation(aircraft.lat, aircraft.lon) or 0
        end
        local desired_mag = (desired_true - mag_var + 360) % 360
        local track_mag = (yal.groundtrackmag and get(yal.groundtrackmag)) or desired_mag
        local heading_true = (yal.localpositionpsi and get(yal.localpositionpsi)) or nil
        local heading_mag = heading_true and ((heading_true - mag_var + 360) % 360) or nil
        local control_mag = track_mag
        if heading_mag then
            local blend_min = (C and C.autoTaxiHeadingBlendMinKts) or 3
            local blend_max = (C and C.autoTaxiHeadingBlendMaxKts) or 8
            local blend = 0
            if gs_kts <= blend_min then
                blend = 1
            elseif gs_kts < blend_max then
                blend = (blend_max - gs_kts) / (blend_max - blend_min)
            end
            if blend > 0 then
                local diff_ht = heading_diff_signed(heading_mag, track_mag)
                control_mag = (track_mag + diff_ht * blend + 360) % 360
            end
        end
        local diff = heading_diff_signed(desired_mag, control_mag)
        local max_err = (C and C.autoTaxiSteerMaxErrDeg) or 35
        local max_steer = (C and C.autoTaxiSteerMaxDeg) or 25
        local steer_deg = clamp(diff / max_err, -1, 1) * max_steer
        local steer_deadband = (C and C.autoTaxiSteerDeadbandDeg) or 1.0
        if math.abs(steer_deg) < steer_deadband then
            steer_deg = 0
        end
        local steer_rate = (C and C.autoTaxiSteerSlewDegPerSec) or 90
        local prev_steer = comp._autoTaxiSteer
        local prev_time = comp._autoTaxiSteerTime
        if prev_steer ~= nil and now and prev_time then
            local dt = now - prev_time
            if dt < 0 then
                dt = 0
            end
            if dt > 0 then
                local max_delta = steer_rate * dt
                local delta = steer_deg - prev_steer
                if delta > max_delta then
                    steer_deg = prev_steer + max_delta
                elseif delta < -max_delta then
                    steer_deg = prev_steer - max_delta
                end
            end
        end
        comp._autoTaxiSteer = steer_deg
        if now then
            comp._autoTaxiSteerTime = now
        end

        local target_kts = (C and C.autoTaxiSpeedKts) or 8
        local slow_kts = (C and C.autoTaxiTurnSpeedKts) or 5
        local gate_kts = (C and C.autoTaxiGateSpeedKts) or 3
        local stop_dist = (C and C.autoTaxiStopDistMeters) or 8
        local turn_angle = (C and C.autoTaxiTurnAngleDeg) or 25
        local last_seg = comp._autoTaxiLastSegIdx
        if not last_seg or seg_idx >= last_seg then
            comp._autoTaxiLastSegIdx = seg_idx
        end
        local dist_to_seg_end = math.sqrt(
            (n2.east - aircraft.east) * (n2.east - aircraft.east)
            + (n2.north - aircraft.north) * (n2.north - aircraft.north)
        )
        local progressed = (seg_len > 0 and (seg_len - dist_to_seg_end) or 0)
        if progressed < 0 then
            progressed = 0
        end
        local h1 = nil
        local h2 = nil
        if seg_idx + 2 <= #path then
            local n3 = data.nodes[path[seg_idx + 2]]
            if n3 then
                h1 = heading_deg_from_to(n1.east, n1.north, n2.east, n2.north)
                h2 = heading_deg_from_to(n2.east, n2.north, n3.east, n3.north)
            end
        end
        local guidance_slow_active = guidance_target
            and guidance_action_needs_slow(guidance_target.action)
            and seg_idx <= (guidance_target.commitSegIdx or seg_idx)
        if guidance_slow_active and dist_to_node <= turn_lead_active then
            if not comp._autoTaxiTurnSlow then
                comp._autoTaxiTurnSlow = true
                comp._autoTaxiTurnSegIdx = seg_idx
                auto_taxi_log_once(comp, now, "turnslow-on-guidance-" .. tostring(seg_idx), "turn slow on (guidance)")
            end
        elseif (target_reason == "geom-turn" or target_reason == "geom-scurve" or target_reason == "guidance-transition") and dist_to_node <= turn_lead then
            if not comp._autoTaxiTurnSlow then
                comp._autoTaxiTurnSlow = true
                comp._autoTaxiTurnSegIdx = seg_idx
                auto_taxi_log_once(comp, now, "turnslow-on-" .. tostring(seg_idx), "turn slow on (target)")
            end
        end
        if comp._autoTaxiTurnSlow then
            local hyst = (C and C.autoTaxiTurnHysteresisFactor) or 0.6
            if not guidance_slow_active and progressed >= turn_lead
                and (not (h1 and h2) or heading_diff_deg(h1, h2) < (turn_angle * hyst)) then
                auto_taxi_log_once(comp, now, "turnslow-off-" .. tostring(seg_idx), "turn slow off")
                comp._autoTaxiTurnSlow = false
                comp._autoTaxiTurnSegIdx = nil
            end
        end
        if (not comp._autoTaxiTurnSlow) and seg_idx + 2 <= #path and dist_to_seg_end <= turn_lead then
            local n3 = data.nodes[path[seg_idx + 2]]
            if n3 then
                if h1 and h2 and heading_diff_deg(h1, h2) >= turn_angle and dist_to_seg_end <= turn_lead then
                    comp._autoTaxiTurnSlow = true
                    comp._autoTaxiTurnSegIdx = seg_idx
                    auto_taxi_log_once(comp, now, "turnslow-on-" .. tostring(seg_idx), "turn slow on")
                end
            end
        end
        if comp._autoTaxiTurnSlow then
            target_kts = slow_kts
        end
        if comp.mode == 0 and (comp._depThresholdReached or comp._depThresholdLatched) then
            if math.abs(diff) > turn_angle then
                target_kts = math.min(target_kts, slow_kts)
            end
        end
        if comp._guidanceState == "gate" then
            target_kts = math.min(target_kts, gate_kts, slow_kts)
            if U.gate_distance_meters then
                local gdist = U.gate_distance_meters(comp, aircraft, route, data)
                local gstop = (C and C.gateStopDistance) or 2
                if gdist and gdist <= gstop then
                    target_kts = 0
                end
            end
        end
        local last_id = path[#path]
        local last_node = last_id and data.nodes[last_id] or nil
        if last_node and last_node.east and last_node.north then
            local dx_end = last_node.east - aircraft.east
            local dy_end = last_node.north - aircraft.north
            local dist_end = math.sqrt(dx_end * dx_end + dy_end * dy_end)
            if dist_end <= stop_dist then
                comp._autoTaxiEndStopLatched = true
            end
            if comp._autoTaxiEndStopLatched then
                target_kts = 0
            end
            if dist_end <= stop_dist then
                target_kts = 0
            end
        end
        local throttle_base = (C and C.autoTaxiThrottleBase) or 0.05
        local throttle_kp = (C and C.autoTaxiThrottleKp) or 0.03
        local throttle_max = (C and C.autoTaxiThrottleMax) or 0.25
        local brake_kp = (C and C.autoTaxiBrakeKp) or 0.12
        local brake_max = (C and C.autoTaxiBrakeMax) or 0.6
        local speed_err = target_kts - gs_kts
        local throttle = clamp(throttle_base + speed_err * throttle_kp, 0, throttle_max)
        local brake = 0
        if target_kts <= 0.5 then
            throttle = 0
            brake = brake_max
        elseif speed_err < -1 then
            brake = clamp((-speed_err) * brake_kp, 0, brake_max)
        end
        comp._autoTaxiLastBrake = brake
        if now then
            local last_log = comp._autoTaxiControlLog or 0
            if (now - last_log) >= 2.0 then
                comp._autoTaxiControlLog = now
                auto_taxi_log(comp, string.format(
                    "ctrl seg=%s tgt=%s gs=%.1f kt target=%.1f dist=%.1f steer=%.1f thr=%.2f brk=%.2f",
                    tostring(seg_idx),
                    tostring(target_idx or ""),
                    gs_kts,
                    target_kts,
                    dist_route or -1,
                    steer_deg,
                    throttle,
                    brake
                ))
            end
        end

        auto_taxi_apply_overrides(comp, yal)
        if yal.tire_steer_cmd and isProperty(yal.tire_steer_cmd) then
            set(yal.tire_steer_cmd, steer_deg)
        end
        if yal.throttle_use_1 and isProperty(yal.throttle_use_1) then
            set(yal.throttle_use_1, throttle)
        end
        if yal.throttle_use_2 and isProperty(yal.throttle_use_2) then
            set(yal.throttle_use_2, throttle)
        end
        if yal.left_brake_ratio and isProperty(yal.left_brake_ratio) then
            set(yal.left_brake_ratio, brake)
        end
        if yal.right_brake_ratio and isProperty(yal.right_brake_ratio) then
            set(yal.right_brake_ratio, brake)
        end
        comp._autoTaxiActive = true
        return true
    end

    U.auto_taxi_tick = function(comp, now)
        if not comp then
            return
        end
        if comp._autoTaxiForceRelease then
            auto_taxi_release_controls(comp, comp.yal or _G.yal, comp._autoTaxiForceRelease)
            comp._autoTaxiForceRelease = nil
        end
        if comp.mode ~= 0 and comp.mode ~= 1 then
            comp._autoTaxiReady = false
            return
        end
        local settingsTable = settings and settings.appSettings or nil
        if not settingsTable then
            return
        end
        if settingsTable[def.CONFIGAUTOTAXIING] ~= def.ON then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, comp.yal or _G.yal, "setting-off")
            auto_taxi_log_once(comp, now, "gate:setting-off", "blocked: auto taxiing off")
            auto_taxi_log_snapshot_once(comp, now, "gate:setting-off", comp.yal or _G.yal, "gate:setting-off")
            return
        end
        if settingsTable[def.CONFIGAUTOTAXIGUIDANCE] ~= def.ON then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, comp.yal or _G.yal, "guidance-off")
            auto_taxi_log_once(comp, now, "gate:guidance-off", "blocked: auto taxi guidance off")
            auto_taxi_log_snapshot_once(comp, now, "gate:guidance-off", comp.yal or _G.yal, "gate:guidance-off")
            return
        end
        local tick_sec = (C and C.autoTaxiTickSec) or 0.05
        local next_tick = comp._autoTaxiNext or 0
        if now < next_tick then
            return
        end
        comp._autoTaxiNext = now + tick_sec

        local yal = comp.yal or _G.yal
        if not yal then
            comp._autoTaxiReady = false
            auto_taxi_log_once(comp, now, "gate:no-yal", "blocked: no yal handle")
            return
        end
        if yal.autotaxipause then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "paused")
            auto_taxi_log_once(comp, now, "gate:paused", "blocked: paused")
            auto_taxi_log_snapshot_once(comp, now, "gate:paused", yal, "gate:paused")
            return
        end
        if comp._editRoute or comp._drawRoute then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "edit-draw")
            auto_taxi_log_once(comp, now, "gate:edit-draw", "blocked: edit/draw active")
            auto_taxi_log_snapshot_once(comp, now, "gate:edit-draw", yal, "gate:edit-draw")
            return
        end
        if not (yal.airgroundsensor and get(yal.airgroundsensor) == def.ON) then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "airborne")
            auto_taxi_log_once(comp, now, "gate:airborne", "blocked: airborne")
            auto_taxi_log_snapshot_once(comp, now, "gate:airborne", yal, "gate:airborne")
            return
        end
        local gs_kts = (yal.groundspeed and (get(yal.groundspeed) or 0)) or 0
        local max_kts = (C and C.autoTaxiMaxActiveSpeedKts) or 40
        if gs_kts > max_kts then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "groundspeed")
            auto_taxi_log_once(comp, now, "gate:groundspeed", "blocked: gs " .. string.format("%.1f", gs_kts))
            auto_taxi_log_snapshot_once(comp, now, "gate:groundspeed", yal, "gate:groundspeed")
            return
        end
        local flightstate = yal.flightstate
        if comp.mode == 0 then
            if flightstate ~= def.FLIGHTSTATEPREFLIGHT then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "flightstate")
                auto_taxi_log_once(comp, now, "gate:flightstate", "blocked: flightstate " .. tostring(flightstate))
                auto_taxi_log_snapshot_once(comp, now, "gate:flightstate", yal, "gate:flightstate")
                return
            end
        elseif comp.mode == 1 then
            if flightstate ~= def.FLIGHTSTATETAXITOGATE then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "flightstate")
                auto_taxi_log_once(comp, now, "gate:flightstate", "blocked: flightstate " .. tostring(flightstate))
                auto_taxi_log_snapshot_once(comp, now, "gate:flightstate", yal, "gate:flightstate")
                return
            end
        end
        if yal.parkingbrakepos and get(yal.parkingbrakepos) == def.ON then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "parking-brake")
            auto_taxi_log_once(comp, now, "gate:parking-brake", "blocked: parking brake")
            auto_taxi_log_snapshot_once(comp, now, "gate:parking-brake", yal, "gate:parking-brake")
            return
        end
        if comp.mode == 0 then
            if not before_taxi_started(comp) then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "before-taxi")
                auto_taxi_log_once(comp, now, "gate:before-taxi", "blocked: before-taxi not started")
                auto_taxi_log_snapshot_once(comp, now, "gate:before-taxi", yal, "gate:before-taxi")
                return
            end
        end
        if not comp._route or not comp._route.path or #comp._route.path < 2 then
            local manual = auto_taxi_manual_input(comp, yal, now)
            if manual then
                local hold_sec = (C and C.autoTaxiManualHoldSec) or 3
                comp._autoTaxiHoldUntil = now + hold_sec
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "manual-" .. tostring(manual))
                auto_taxi_log_once(comp, now, "gate:manual", "blocked: manual input " .. tostring(manual))
                auto_taxi_log_snapshot_once(comp, now, "gate:manual", yal, "gate:manual")
                return
            end
            local lat = yal.aircraftlatpos and get(yal.aircraftlatpos) or nil
            local lon = yal.aircraftlonpos and get(yal.aircraftlonpos) or nil
            if is_valid_latlon(lat, lon) then
                local ae, an = latlon_to_local(lat, lon)
                if ae and an then
                    local aircraft = { east = ae, north = an, lat = lat, lon = lon }
                    if auto_taxi_align_runway(comp, now, yal, aircraft) then
                        return
                    end
                end
            end
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "route")
            auto_taxi_log_once(comp, now, "gate:route", "blocked: no route")
            auto_taxi_log_snapshot_once(comp, now, "gate:route", yal, "gate:route")
            return
        end
        if comp._routeErr == "taxi-complete" or comp._depTaxiCompleteAnnounced or comp._arrTaxiCompleteAnnounced then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "taxi-complete")
            auto_taxi_log_once(comp, now, "gate:taxi-complete", "blocked: taxi complete")
            auto_taxi_log_snapshot_once(comp, now, "gate:taxi-complete", yal, "gate:taxi-complete")
            return
        end
        local aircraft = comp._aircraftPoint
        if comp.mode == 0 then
            if U.update_pushback_state and U.update_pushback_state(comp, now, yal, aircraft) then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "pushback")
                auto_taxi_log_once(comp, now, "gate:pushback", "blocked: pushback active")
                auto_taxi_log_snapshot_once(comp, now, "gate:pushback", yal, "gate:pushback")
                return
            end
        end
        local hold_until = comp._autoTaxiHoldUntil or 0
        if now < hold_until then
            local manual = auto_taxi_manual_input(comp, yal, now)
            if manual then
                local hold_sec = (C and C.autoTaxiManualHoldSec) or 3
                comp._autoTaxiHoldUntil = now + hold_sec
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "manual-" .. tostring(manual))
                auto_taxi_log_once(comp, now, "gate:manual-hold", "blocked: manual input " .. tostring(manual))
                auto_taxi_log_snapshot_once(comp, now, "gate:manual-hold", yal, "gate:manual-hold")
            end
            comp._autoTaxiReady = false
            return
        end
        local manual = auto_taxi_manual_input(comp, yal, now)
        if manual then
            local hold_sec = (C and C.autoTaxiManualHoldSec) or 3
            comp._autoTaxiHoldUntil = now + hold_sec
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "manual-" .. tostring(manual))
            auto_taxi_log_once(comp, now, "gate:manual", "blocked: manual input " .. tostring(manual))
            auto_taxi_log_snapshot_once(comp, now, "gate:manual", yal, "gate:manual")
            return
        end
        if not comp._autoTaxiReady then
            auto_taxi_log_once(comp, now, "gate:ready", "ready")
        end
        comp._autoTaxiReady = true
        comp._autoTaxiAllowOverride = true
        local lat = yal.aircraftlatpos and get(yal.aircraftlatpos) or nil
        local lon = yal.aircraftlonpos and get(yal.aircraftlonpos) or nil
        if (not aircraft) or aircraft.east == nil or aircraft.north == nil then
            if is_valid_latlon(lat, lon) then
                local ae, an = latlon_to_local(lat, lon)
                if ae and an then
                    aircraft = { east = ae, north = an }
                end
            end
        end
        if aircraft and is_valid_latlon(lat, lon) then
            aircraft.lat = lat
            aircraft.lon = lon
        end
        if not aircraft or aircraft.east == nil or aircraft.north == nil then
            auto_taxi_release_controls(comp, yal, "no-aircraft")
            auto_taxi_log_once(comp, now, "gate:no-aircraft", "blocked: no aircraft position")
            auto_taxi_log_snapshot_once(comp, now, "gate:no-aircraft", yal, "gate:no-aircraft")
            return
        end
        if comp.mode == 0 and gs_kts >= ((C and C.depTakeoffLatchSpeed) or 25) then
            local on_rwy = false
            if comp._depProfile and aircraft then
                on_rwy = is_on_runway_profile(comp._depProfile, aircraft, 60, 5)
            end
            if (not on_rwy) and yal and yal.aircraftonrwy then
                on_rwy = yal.aircraftonrwy(def.DEPARTURE, 40, (C and C.depThresholdHeadingLimit) or 25)
            end
            if on_rwy then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "takeoff-roll")
                auto_taxi_log_once(comp, now, "gate:takeoff-roll", "blocked: takeoff roll")
                auto_taxi_log_snapshot_once(comp, now, "gate:takeoff-roll", yal, "gate:takeoff-roll")
                return
            end
        end
        if not auto_taxi_apply_controls(comp, now, yal, aircraft) then
            auto_taxi_release_controls(comp, yal, "apply-failed")
            comp._autoTaxiReady = false
            auto_taxi_log_once(comp, now, "gate:apply-failed", "blocked: apply failed")
            auto_taxi_log_snapshot_once(comp, now, "gate:apply-failed", yal, "gate:apply-failed")
        end
    end
end

return M
