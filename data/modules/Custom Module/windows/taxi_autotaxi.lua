local M = {}

function M.attach(U, C, def, helpers, settings)
    local is_valid_latlon = U.is_valid_latlon
    local latlon_to_local = U.latlon_to_local
    local find_nearest_segment = U.find_nearest_segment
    local project_point_to_segment = U.project_point_to_segment
    local heading_deg_from_to = U.heading_deg_from_to
    local heading_diff_signed = U.heading_diff_signed
    local heading_diff_deg = U.heading_diff_deg
    local clamp = U.clamp

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

    local function auto_taxi_apply_overrides(comp, yal)
        if not comp or not yal or comp._autoTaxiOverrideActive then
            return
        end
        if comp._autoTaxiAllowOverride == false then
            return
        end
        auto_taxi_log(comp, "overrides on")
        comp._autoTaxiOverrideActive = true
        if yal.override_throttles and isProperty(yal.override_throttles) then
            comp._autoTaxiPrevOverrideThrottles = get(yal.override_throttles)
            set(yal.override_throttles, def.ON)
        end
        if yal.override_wheel_steer and isProperty(yal.override_wheel_steer) then
            comp._autoTaxiPrevOverrideSteer = get(yal.override_wheel_steer)
            set(yal.override_wheel_steer, def.ON)
        end
        if yal.override_toe_brakes and isProperty(yal.override_toe_brakes) then
            comp._autoTaxiPrevOverrideBrakes = get(yal.override_toe_brakes)
            set(yal.override_toe_brakes, def.ON)
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
        if comp._autoTaxiActive or comp._autoTaxiOverrideActive then
            auto_taxi_log(comp, "release " .. tostring(reason or ""))
        end
        if yal then
            if comp._autoTaxiOverrideActive then
                if yal.override_throttles and isProperty(yal.override_throttles) then
                    set(yal.override_throttles, comp._autoTaxiPrevOverrideThrottles or def.OFF)
                end
                if yal.override_wheel_steer and isProperty(yal.override_wheel_steer) then
                    set(yal.override_wheel_steer, comp._autoTaxiPrevOverrideSteer or def.OFF)
                end
                if yal.override_toe_brakes and isProperty(yal.override_toe_brakes) then
                    set(yal.override_toe_brakes, comp._autoTaxiPrevOverrideBrakes or def.OFF)
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
        comp._autoTaxiActive = false
        comp._autoTaxiAllowOverride = false
    end

    local function auto_taxi_manual_input(comp, yal)
        if not yal then
            return nil
        end
        local thr1 = (yal.hardware_throttle_1 and get(yal.hardware_throttle_1)) or 0
        local thr2 = (yal.hardware_throttle_2 and get(yal.hardware_throttle_2)) or 0
        if thr1 > 0.05 or thr2 > 0.05 then
            return "throttle"
        end
        local yaw = (yal.yoke_heading_ratio and get(yal.yoke_heading_ratio)) or 0
        if math.abs(yaw) > 0.2 then
            return "steer"
        end
        if yal.parkingbrakepos and get(yal.parkingbrakepos) == def.ON then
            return "parking-brake"
        end
        return nil
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
        if #path < 2 then
            return false
        end
        local data = route.data
        local seg_idx = find_nearest_segment(data, path, aircraft.east, aircraft.north)
        if not seg_idx or seg_idx >= #path then
            return false
        end
        if comp._autoTaxiTargetSegIdx and comp._autoTaxiTargetSegIdx <= seg_idx then
            comp._autoTaxiTargetSegIdx = nil
            comp._autoTaxiTargetTime = nil
            comp._autoTaxiTargetAction = nil
        end
        local n1 = data.nodes[path[seg_idx]]
        local n2 = data.nodes[path[seg_idx + 1]]
        if not n1 or not n2 then
            return false
        end
        local dx = n2.east - n1.east
        local dy = n2.north - n1.north
        local seg_len = math.sqrt(dx * dx + dy * dy)
        local lookahead_m = (C and C.autoTaxiLookaheadMeters) or 25
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
        local lead_m = (C and C.autoTaxiGuidanceLeadMeters) or (C and C.autoTaxiTurnLeadMeters) or 20
        local target_idx = nil
        local gidx = comp._autoTaxiTargetSegIdx
        if gidx and gidx > seg_idx and gidx <= (#path - 1) and dist_to_node <= lead_m then
            local h_curr = heading_deg_from_to(n1.east, n1.north, n2.east, n2.north)
            local tn1 = data.nodes[path[gidx]]
            local tn2 = data.nodes[path[gidx + 1]]
            if h_curr and tn1 and tn2 and tn1.east and tn1.north and tn2.east and tn2.north then
                local h_tgt = heading_deg_from_to(tn1.east, tn1.north, tn2.east, tn2.north)
                if h_tgt and heading_diff_deg(h_curr, h_tgt) >= ((C and C.autoTaxiTurnAngleDeg) or 25) * 0.5 then
                    target_idx = gidx
                end
            end
        end
        if not target_idx and (seg_idx + 3) <= #path and dist_to_node <= lead_m then
            local n3 = data.nodes[path[seg_idx + 2]]
            local n4 = data.nodes[path[seg_idx + 3]]
            if n3 and n4 and n3.east and n3.north and n4.east and n4.north then
                local v2x = n3.east - n2.east
                local v2y = n3.north - n2.north
                local v3x = n4.east - n3.east
                local v3y = n4.north - n3.north
                local len2 = math.sqrt(v2x * v2x + v2y * v2y)
                local max_seg = (C and C.autoTaxiSCurveMaxSeg) or 50
                if len2 > 0.1 and len2 <= max_seg then
                    local cross1 = dx * v2y - dy * v2x
                    local cross2 = v2x * v3y - v2y * v3x
                    if cross1 ~= 0 and cross2 ~= 0 and (cross1 * cross2) < 0 then
                        target_idx = seg_idx + 2
                    end
                end
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
        if target_idx and comp._autoTaxiLastTarget ~= target_idx then
            comp._autoTaxiLastTarget = target_idx
            auto_taxi_log(comp, "target seg " .. tostring(target_idx))
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
        if now then
            local last_log = comp._autoTaxiControlLog or 0
            if (now - last_log) >= 2.0 then
                comp._autoTaxiControlLog = now
                auto_taxi_log(comp, string.format("ctrl seg=%s tgt=%s gs=%.1f kt", tostring(seg_idx), tostring(target_idx or ""), gs_kts))
            end
        end
        local mag_var = 0
        if aircraft.lat and aircraft.lon then
            mag_var = sasl.getMagneticVariation(aircraft.lat, aircraft.lon) or 0
        end
        local desired_mag = (desired_true - mag_var + 360) % 360
        local track_mag = (yal.groundtrackmag and get(yal.groundtrackmag)) or desired_mag
        local diff = heading_diff_signed(desired_mag, track_mag)
        local max_err = (C and C.autoTaxiSteerMaxErrDeg) or 35
        local max_steer = (C and C.autoTaxiSteerMaxDeg) or 25
        local steer_deg = clamp(diff / max_err, -1, 1) * max_steer

        local gs_ms = (yal.groundspeed and (get(yal.groundspeed) or 0)) or 0
        local gs_kts = gs_ms * 1.94384
        local target_kts = (C and C.autoTaxiSpeedKts) or 8
        local slow_kts = (C and C.autoTaxiTurnSpeedKts) or 5
        local gate_kts = (C and C.autoTaxiGateSpeedKts) or 3
        local stop_dist = (C and C.autoTaxiStopDistMeters) or 8
        local turn_angle = (C and C.autoTaxiTurnAngleDeg) or 25
        local turn_lead = (C and C.autoTaxiTurnLeadMeters) or 20
        local dist_to_seg_end = math.sqrt(
            (n2.east - aircraft.east) * (n2.east - aircraft.east)
            + (n2.north - aircraft.north) * (n2.north - aircraft.north)
        )
        if seg_idx + 2 <= #path then
            local n3 = data.nodes[path[seg_idx + 2]]
            if n3 then
                local h1 = heading_deg_from_to(n1.east, n1.north, n2.east, n2.north)
                local h2 = heading_deg_from_to(n2.east, n2.north, n3.east, n3.north)
                if h1 and h2 and heading_diff_deg(h1, h2) >= turn_angle and dist_to_seg_end <= turn_lead then
                    target_kts = slow_kts
                end
            end
        end
        if comp._guidanceState == "gate" then
            target_kts = math.min(target_kts, gate_kts)
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
        if comp.mode ~= 0 and comp.mode ~= 1 then
            comp._autoTaxiReady = false
            return
        end
        local settingsTable = settings and settings.appSettings or nil
        if not settingsTable then
            return
        end
        if settingsTable[def.CONFIGAUTOFUNCTIONS] ~= def.ON then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, comp.yal or _G.yal, "auto-functions-off")
            auto_taxi_log_once(comp, now, "gate:auto-functions-off", "blocked: auto functions off")
            return
        end
        if settingsTable[def.CONFIGVOICEADVICEONLY] == def.ON then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, comp.yal or _G.yal, "voice-advice-only")
            auto_taxi_log_once(comp, now, "gate:voice-advice-only", "blocked: voice advice only")
            return
        end
        if settingsTable[def.CONFIGAUTOTAXIING] ~= def.ON then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, comp.yal or _G.yal, "setting-off")
            auto_taxi_log_once(comp, now, "gate:setting-off", "blocked: auto taxiing off")
            return
        end
        if settingsTable[def.CONFIGAUTOTAXIGUIDANCE] ~= def.ON then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, comp.yal or _G.yal, "guidance-off")
            auto_taxi_log_once(comp, now, "gate:guidance-off", "blocked: auto taxi guidance off")
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
            return
        end
        if comp._editRoute or comp._drawRoute then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "edit-draw")
            auto_taxi_log_once(comp, now, "gate:edit-draw", "blocked: edit/draw active")
            return
        end
        if not (yal.airgroundsensor and get(yal.airgroundsensor) == def.ON) then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "airborne")
            auto_taxi_log_once(comp, now, "gate:airborne", "blocked: airborne")
            return
        end
        local gs_ms = (yal.groundspeed and (get(yal.groundspeed) or 0)) or 0
        local gs_kts = gs_ms * 1.94384
        local max_kts = (C and C.autoTaxiMaxActiveSpeedKts) or 40
        if gs_kts > max_kts then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "groundspeed")
            auto_taxi_log_once(comp, now, "gate:groundspeed", "blocked: gs " .. string.format("%.1f", gs_kts))
            return
        end
        local flightstate = yal.flightstate
        if comp.mode == 0 then
            if flightstate ~= def.FLIGHTSTATEPREFLIGHT then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "flightstate")
                auto_taxi_log_once(comp, now, "gate:flightstate", "blocked: flightstate " .. tostring(flightstate))
                return
            end
        elseif comp.mode == 1 then
            if flightstate ~= def.FLIGHTSTATETAXITOGATE then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "flightstate")
                auto_taxi_log_once(comp, now, "gate:flightstate", "blocked: flightstate " .. tostring(flightstate))
                return
            end
            local proc = yal.proceduretable and yal.proceduretable[def.AFTERLANDINGPROCEDURE]
            if not (proc and proc.set) then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "after-landing")
                auto_taxi_log_once(comp, now, "gate:after-landing", "blocked: after-landing incomplete")
                return
            end
        end
        if yal.parkingbrakepos and get(yal.parkingbrakepos) == def.ON then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "parking-brake")
            auto_taxi_log_once(comp, now, "gate:parking-brake", "blocked: parking brake")
            return
        end
        if comp.mode == 0 then
            local proc = yal.proceduretable and yal.proceduretable[def.BEFORETAXIPROCEDURE]
            if not (proc and proc.set) then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "before-taxi")
                auto_taxi_log_once(comp, now, "gate:before-taxi", "blocked: before-taxi incomplete")
                return
            end
        end
        if not comp._route or not comp._route.path or #comp._route.path < 2 then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "route")
            auto_taxi_log_once(comp, now, "gate:route", "blocked: no route")
            return
        end
        if comp._routeErr == "taxi-complete" then
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "taxi-complete")
            auto_taxi_log_once(comp, now, "gate:taxi-complete", "blocked: taxi complete")
            return
        end
        local aircraft = comp._aircraftPoint
        if comp.mode == 0 then
            if U.update_pushback_state and U.update_pushback_state(comp, now, yal, aircraft) then
                comp._autoTaxiReady = false
                auto_taxi_release_controls(comp, yal, "pushback")
                auto_taxi_log_once(comp, now, "gate:pushback", "blocked: pushback active")
                return
            end
        end
        local hold_until = comp._autoTaxiHoldUntil or 0
        if now < hold_until then
            comp._autoTaxiReady = false
            return
        end
        local manual = auto_taxi_manual_input(comp, yal)
        if manual then
            local hold_sec = (C and C.autoTaxiManualHoldSec) or 3
            comp._autoTaxiHoldUntil = now + hold_sec
            comp._autoTaxiReady = false
            auto_taxi_release_controls(comp, yal, "manual-" .. tostring(manual))
            auto_taxi_log_once(comp, now, "gate:manual", "blocked: manual input " .. tostring(manual))
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
            return
        end
        if not auto_taxi_apply_controls(comp, now, yal, aircraft) then
            auto_taxi_release_controls(comp, yal, "apply-failed")
            comp._autoTaxiReady = false
            auto_taxi_log_once(comp, now, "gate:apply-failed", "blocked: apply failed")
        end
    end
end

return M
