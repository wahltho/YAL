local M = {}

function M.attach(U, C, def, helpers, settings)
    local is_valid_latlon = U.is_valid_latlon
    local latlon_to_local = U.latlon_to_local
    local ramp_key = U.ramp_key
    local taxiway_label_voice = U.taxiway_label_voice
    local normalize_runway_pair_label = U.normalize_runway_pair_label
    local format_runway_designator_text = U.format_runway_designator_text
    local normalize_runway_name = U.normalize_runway_name
    local normalize_taxiway_label = U.normalize_taxiway_label
    local is_visual_taxi_guidance_enabled = U.is_visual_taxi_guidance_enabled
    local is_auto_taxi_guidance_enabled = U.is_auto_taxi_guidance_enabled
    local is_voice_enabled = U.is_voice_enabled
    local find_nearest_segment = U.find_nearest_segment
    local heading_deg_from_to = U.heading_deg_from_to
    local heading_diff_deg = U.heading_diff_deg
    local project_point_to_segment = U.project_point_to_segment
    local distance_sq = U.distance_sq
    local is_runway_label = U.is_runway_label
    local get_edge_label = U.get_edge_label
    local arrival_grace_active = U.arrival_grace_active
    local is_on_runway_profile = U.is_on_runway_profile
    local distance_to_route = U.distance_to_route
    local distance_to_segments = U.distance_to_segments
    local runway_label_voice = U.runway_label_voice

    local function gate_distance_meters(comp, aircraft, route, data)
        local fn = U.gate_distance_meters
        if fn then
            return fn(comp, aircraft, route, data)
        end
        return nil
    end

    local function gate_note_text(dist, use_dgs)
        local fn = U.gate_note_text
        if fn then
            return fn(dist, use_dgs)
        end
        return nil
    end

    local function gate_alignment_info(comp, aircraft)
        local fn = U.gate_alignment_info
        if fn then
            return fn(comp, aircraft)
        end
        return nil
    end

    local function maybe_gate_voice_callouts(comp, dist, allow_voice, use_dgs)
        local fn = U.maybe_gate_voice_callouts
        if fn then
            return fn(comp, dist, allow_voice, use_dgs)
        end
        return nil
    end

    local function reset_gate_callouts(comp, key)
        local fn = U.reset_gate_callouts
        if fn then
            return fn(comp, key)
        end
        return nil
    end

    local function guidance_distance_for_speed(tirespeed)
        local speed = tonumber(tirespeed) or 0
        if speed <= 0 then
            return C.guidanceTurnDistance
        end
        local dist = speed * C.guidanceLeadTimeSec
        if dist < C.guidanceTurnDistance then
            dist = C.guidanceTurnDistance
        end
        if dist > C.guidanceMaxDistance then
            dist = C.guidanceMaxDistance
        end
        return dist
    end

    local function speak_guidance_text(comp, text)
        local yal = comp.yal or _G.yal
        if yal and yal.commandtableentry then
            yal.commandtableentry(def.TAXI, text)
            return
        end
        helpers.speak(text)
    end

    local function gate_target_key(comp, route)
        if not comp then
            return nil
        end
        if comp._endRamp then
            local key = ramp_key(comp._endRamp)
            if key and key ~= "" then
                return "ramp:" .. tostring(key)
            end
        end
        if route and route.path and #route.path > 0 then
            return "node:" .. tostring(route.path[#route.path])
        end
        return nil
    end

    local function gate_target_position(comp, route, data)
        if comp and comp._endRamp then
            local ramp = comp._endRamp
            local east = ramp.east
            local north = ramp.north
            if (east == nil or north == nil) and is_valid_latlon(ramp.lat, ramp.lon) then
                east, north = latlon_to_local(ramp.lat, ramp.lon)
            end
            if east ~= nil and north ~= nil then
                return east, north
            end
        end
        if route and data and route.path and #route.path > 0 and data.nodes then
            local node = data.nodes[route.path[#route.path]]
            if node and node.east ~= nil and node.north ~= nil then
                return node.east, node.north
            end
        end
        return nil
    end

    local function get_visual_popup(comp)
        local yal = comp and (comp.yal or _G.yal) or _G.yal
        if yal then
            return yal.taxiPopup
        end
        return nil
    end

    local function build_visual_label(kind, display)
        if not display or display == "" then
            return ""
        end
        if kind == "taxiway" then
            local spoken = taxiway_label_voice(display)
            if spoken == "" then
                return ""
            end
            return "TAXIWAY " .. spoken
        end
        if kind == "runway" then
            local normalized = normalize_runway_pair_label(display)
            local formatted = format_runway_designator_text(normalized)
            if formatted == "" then
                return ""
            end
            return "RWY " .. string.upper(formatted)
        end
        return display
    end

    local function is_taxi_complete_info(info)
        if not info then
            return false
        end
        local action = tostring(info.action or ""):lower()
        local text = tostring(info.text or ""):lower()
        return action == "taxi complete" or (text:find("taxi complete", 1, true) ~= nil)
    end

    local function set_visual_guidance(comp, info)
        if not comp or not info then
            return
        end
        comp._visualGuidance = info
    end

    local function queue_visual_guidance(comp, info)
        if not comp or not info then
            return
        end
        comp._visualGuidanceQueue = comp._visualGuidanceQueue or {}
        comp._visualGuidanceQueue[#comp._visualGuidanceQueue + 1] = info
    end

    local function clear_visual_guidance(comp, reason)
        if not comp then
            return
        end
        comp._visualGuidance = nil
        local popup = get_visual_popup(comp)
        if popup and popup.clearInstruction then
            popup:clearInstruction(reason)
        end
        if reason == "expired" or reason == "fulfilled" then
            if comp._visualGuidanceQueue and #comp._visualGuidanceQueue > 0 then
                local next = table.remove(comp._visualGuidanceQueue, 1)
                if next then
                    set_visual_guidance(comp, next)
                end
            end
        elseif reason == "before-takeoff" or reason == "disabled" or reason == "manual-clear" then
            comp._visualGuidanceQueue = {}
        end
    end

    local function set_guidance_state(comp, state, reason, log_taxi)
        if not comp then
            return
        end
        local prev = comp._guidanceState or "idle"
        if prev ~= state then
            comp._guidanceState = state
            if state ~= "route" then
                comp._autoTaxiTargetSegIdx = nil
                comp._autoTaxiTargetTime = nil
                comp._autoTaxiTargetAction = nil
            end
            if prev == "gate" and state ~= "gate" then
                comp._gateGuidanceActive = false
                comp._gateGuidanceStop = false
                comp._gateGuidanceLastDir = nil
                comp._gateGuidanceLastAction = nil
                comp._gateGuidanceLastTime = nil
                comp._gateNote = nil
                if comp._gateCalloutKey ~= nil then
                    reset_gate_callouts(comp, nil)
                end
                if comp._visualGuidance and not is_taxi_complete_info(comp._visualGuidance) then
                    clear_visual_guidance(comp, "gate-exit")
                    comp._visualGuidanceQueue = {}
                end
            end
            if state == "complete" then
                comp._gateGuidanceActive = false
                comp._gateGuidanceStop = false
                comp._gateNote = nil
                if comp._gateCalloutKey ~= nil then
                    reset_gate_callouts(comp, nil)
                end
                if comp._visualGuidance and not is_taxi_complete_info(comp._visualGuidance) then
                    clear_visual_guidance(comp, "taxi-complete")
                end
                comp._visualGuidanceQueue = {}
            end
            local logger = log_taxi or comp._logTaxi or (comp._helpers and comp._helpers.logInfoTS)
            if logger then
                if reason and reason ~= "" then
                    logger("TaxiGuideState: " .. tostring(prev) .. " -> " .. tostring(state) .. " | " .. tostring(reason))
                else
                    logger("TaxiGuideState: " .. tostring(prev) .. " -> " .. tostring(state))
                end
            end
        else
            comp._guidanceState = state
        end
    end

    local function before_takeoff_active_or_set(comp)
        local yal = comp and (comp.yal or _G.yal) or nil
        if not yal then
            return false
        end
        local proc = yal.proceduretable and yal.proceduretable[def.BEFORETAKEOFFPROCEDURE]
        if proc and proc.set then
            return true
        end
        if yal.loopStateTables then
            for _, loop in ipairs(yal.loopStateTables) do
                if loop and loop.lock == def.BEFORETAKEOFFPROCEDURE then
                    return true
                end
            end
        else
            local l1 = yal.procedureloop1
            local l2 = yal.procedureloop2
            local l3 = yal.procedureloop3
            if (l1 and l1.lock == def.BEFORETAKEOFFPROCEDURE)
                or (l2 and l2.lock == def.BEFORETAKEOFFPROCEDURE)
                or (l3 and l3.lock == def.BEFORETAKEOFFPROCEDURE) then
                return true
            end
        end
        return false
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

    local function update_visual_guidance(comp, now, aircraft)
        if not comp or not comp._visualGuidance then
            return
        end
        if not is_visual_taxi_guidance_enabled() then
            clear_visual_guidance(comp, "disabled")
            return
        end
        local info = comp._visualGuidance
        if info.showAt and now and now < info.showAt then
            local popup = get_visual_popup(comp)
            if popup and popup.clearInstruction then
                popup:clearInstruction("pending")
            end
            return
        end
        if info.expiresAt and now and now >= info.expiresAt then
            clear_visual_guidance(comp, "expired")
            return
        end
        if comp._gateNote and comp._gateNote ~= "" then
            info.note = comp._gateNote
        else
            info.note = nil
        end
        local popup = get_visual_popup(comp)
        if popup and popup.setInstruction then
            popup:setInstruction(info)
        end
        local targetSegIdx = info.targetSegIdx
        if targetSegIdx and aircraft and comp._route and comp._route.path and comp._route.data then
            local seg_idx = find_nearest_segment(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
            if seg_idx and seg_idx >= targetSegIdx and (not info.minShowUntil or (now and now >= info.minShowUntil)) then
                clear_visual_guidance(comp, "fulfilled")
            end
        end
    end

    local function maybe_speak_guidance(comp, now, aircraft)
        local yal = comp.yal or _G.yal
        local on_ground = (yal and yal.airgroundsensor and get(yal.airgroundsensor) == def.ON) or false
        local function diag(reason, extra)
            if not on_ground then
                return
            end
            local t = now or 0
            local last = comp._lastGuidanceDiagTime or 0
            if (t - last) < 10 then
                return
            end
            comp._lastGuidanceDiagTime = t
            local msg = "TaxiGuidance: " .. tostring(reason)
            if extra and extra ~= "" then
                msg = msg .. " | " .. tostring(extra)
            end
            local gs = (yal and yal.groundspeed and get(yal.groundspeed)) or nil
            local ts = (yal and yal.tirespeed and get(yal.tirespeed)) or nil
            if gs ~= nil or ts ~= nil then
                msg = msg .. " | gs=" .. tostring(gs) .. " ts=" .. tostring(ts)
            end
            local route = comp._route
            local pdata = (route and route.data) or comp._data
            local ppath = route and route.path or nil
            if aircraft and aircraft.east ~= nil and aircraft.north ~= nil and pdata and ppath and #ppath >= 2 then
                local seg = find_nearest_segment(pdata, ppath, aircraft.east, aircraft.north)
                if seg and (seg + 1) <= #ppath and pdata.nodes then
                    local n2 = pdata.nodes[ppath[seg + 1]]
                    if n2 and n2.east ~= nil and n2.north ~= nil then
                        local dx = n2.east - aircraft.east
                        local dy = n2.north - aircraft.north
                        local dist = math.sqrt(dx * dx + dy * dy)
                        msg = msg .. " dist=" .. string.format("%.1f", dist)
                    end
                end
            end
            helpers.logInfoTS(msg)
        end
        local auto_voice = is_auto_taxi_guidance_enabled()
        local visual_enabled = is_visual_taxi_guidance_enabled()
        if not auto_voice and not visual_enabled then
            diag("voice-disabled")
            return
        end
        if not aircraft or aircraft.east == nil or aircraft.north == nil then
            diag("no-aircraft-pos")
            return
        end
        if not on_ground then
            diag("not-on-ground")
            return
        end
        local gs = (yal and yal.groundspeed and (get(yal.groundspeed) or 0)) or 0
        if comp.mode == 0 then
            local block = U.update_pushback_state and U.update_pushback_state(comp, now, yal, aircraft) or false
            if block then
                comp._initialMoveAnchor = nil
                comp._guidanceMoveAnchor = nil
                diag("pushback-active")
                return
            end
            if not before_taxi_started(comp) then
                clear_visual_guidance(comp, "before-taxi")
                set_guidance_state(comp, "idle", "before-taxi", log_taxi)
                diag("before-taxi-not-started")
                return
            end
            if yal and yal.parkingbrakepos and get(yal.parkingbrakepos) == def.ON then
                clear_visual_guidance(comp, "parking-brake")
                set_guidance_state(comp, "idle", "parking-brake", log_taxi)
                diag("parking-brake")
                return
            end
            if comp._takeoffRollGuidance then
                local on_rwy = false
                if comp._depProfile and aircraft then
                    on_rwy = is_on_runway_profile(comp._depProfile, aircraft, 60, 5)
                end
                if (not on_rwy) and yal and yal.aircraftonrwy then
                    on_rwy = yal.aircraftonrwy(def.DEPARTURE, 40, (C and C.depThresholdHeadingLimit) or 25)
                end
                if (not on_rwy) and gs < 5 then
                    comp._takeoffRollGuidance = nil
                elseif on_ground then
                    clear_visual_guidance(comp, "takeoff-roll")
                    comp._visualGuidanceQueue = {}
                    local logger = comp._logTaxi or (helpers and helpers.logInfoTS)
                    set_guidance_state(comp, "complete", "takeoff-roll", logger)
                    diag("takeoff-roll")
                    return
                end
            end
            if gs >= ((C and C.depTakeoffLatchSpeed) or 25) then
                local on_rwy = false
                if comp._depProfile and aircraft then
                    on_rwy = is_on_runway_profile(comp._depProfile, aircraft, 60, 5)
                end
                if (not on_rwy) and yal and yal.aircraftonrwy then
                    on_rwy = yal.aircraftonrwy(def.DEPARTURE, 40, (C and C.depThresholdHeadingLimit) or 25)
                end
                if on_rwy then
                    comp._takeoffRollGuidance = true
                    clear_visual_guidance(comp, "takeoff-roll")
                    comp._visualGuidanceQueue = {}
                    local logger = comp._logTaxi or (helpers and helpers.logInfoTS)
                    set_guidance_state(comp, "complete", "takeoff-roll", logger)
                    diag("takeoff-roll")
                    return
                end
            end
        end
        local route = comp._route
        local data = (route and route.data) or comp._data
        local is_freehand = (route and route.data and route.data.route_source == "freehand") or false
        local log_taxi = comp._logTaxi or (helpers and helpers.logInfoTS)
        local function maybe_keep_gate_popup(info)
            if not info or info.kind ~= "ramp" then
                return
            end
            if info.keepOpen then
                return
            end
            if comp._arrTaxiCompleteAnnounced or comp._routeErr == "taxi-complete" then
                return
            end
            local hold_dist = (comp._tuning and comp._tuning.gatePopupHoldDist) or (C and C.gatePopupHoldDist) or 30
            if not hold_dist then
                return
            end
            local dist = info.dist
            if dist == nil and aircraft then
                dist = gate_distance_meters(comp, aircraft, comp._route, data)
            end
            if dist and dist <= hold_dist then
                info.keepOpen = true
            end
        end
        local guidance_state = comp._guidanceState or "idle"
        local gate_dist = nil
        if comp._routeErr == "taxi-complete" or comp._arrTaxiCompleteAnnounced or comp._depTaxiCompleteAnnounced then
            guidance_state = "complete"
            comp._gateGuidanceActive = false
            comp._gateGuidanceLastDist = nil
        else
            if comp.mode == 1 and yal and yal.flightstate ~= def.FLIGHTSTATETAXITOGATE then
                clear_visual_guidance(comp, "after-landing")
                set_guidance_state(comp, "idle", "after-landing", log_taxi)
                diag("after-landing")
                return
            end
            if comp.mode == 1 and comp._endRamp then
                local gate_ok = true
                local gate_speed = (comp._tuning and comp._tuning.gateGuidanceMaxSpeed) or (C and C.gateGuidanceMaxSpeed) or 12
                if gs > gate_speed then
                    gate_ok = false
                end
                local offRunway = nil
                if comp._arrProfile and aircraft then
                    offRunway = not is_on_runway_profile(comp._arrProfile, aircraft, 60, 5)
                elseif comp.yal and comp.yal.aircraftonrwy then
                    offRunway = not comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
                end
                if offRunway == false then
                    gate_ok = false
                end
                if gate_ok then
                    gate_dist = gate_distance_meters(comp, aircraft, route, data)
                    local gate_radius = (comp._tuning and comp._tuning.gateGuidanceRadius) or (C and C.gateGuidanceRadius) or 60
                    local gate_keep = gate_radius * 1.6
                    if gate_dist and gate_dist <= gate_radius then
                        comp._gateGuidanceActive = true
                    elseif comp._gateGuidanceActive and gate_dist and gate_dist <= gate_keep then
                        -- keep latch
                    else
                        comp._gateGuidanceActive = false
                    end
                    if comp._gateGuidanceActive and gate_dist and comp._gateGuidanceLastDist
                        and gate_dist > (comp._gateGuidanceLastDist + 5) and gate_dist > gate_radius then
                        comp._gateGuidanceActive = false
                    end
                else
                    comp._gateGuidanceActive = false
                end
                comp._gateGuidanceLastDist = gate_dist
                if comp._gateGuidanceActive then
                    guidance_state = "gate"
                end
            else
                comp._gateGuidanceActive = false
                comp._gateGuidanceLastDist = nil
            end
            if guidance_state ~= "gate" and comp._route and comp._route.path then
                guidance_state = "route"
            elseif guidance_state ~= "gate" then
                guidance_state = "idle"
            end
        end
        set_guidance_state(comp, guidance_state, "resolve", log_taxi)
        if guidance_state == "complete" then
            return
        end
        if guidance_state == "gate" and route and route.path and route.data and route.data.nodes then
            local gate_seg = comp._autoTaxiLastSegIdx or comp._guidanceActiveSegIdx
            if gate_seg and gate_seg >= 1 and gate_seg < #route.path then
                local node = route.data.nodes[route.path[gate_seg + 1]]
                local on_ramp = node and (node.is_ramp or node.ramp_name or node.ramp_id) or false
                if (not on_ramp) and gate_seg < (#route.path - 1) then
                    comp._gateGuidanceActive = false
                    guidance_state = "route"
                    set_guidance_state(comp, guidance_state, "gate-defer", log_taxi)
                end
            end
        end

        if guidance_state == "gate" then
            local gate_key = gate_target_key(comp, route)
            if gate_key ~= comp._gateCalloutKey then
                reset_gate_callouts(comp, gate_key)
            end
            if gate_key then
                local dist = gate_dist or gate_distance_meters(comp, aircraft, route, data)
                comp._gateNote = gate_note_text(dist, comp._gateUseDgs)
                if dist then
                    local stop_dist = (comp._gateUseDgs and ((C and C.gateDgsGoodZPos) or 0.2)) or C.gateStopDistance
                    if gs > 0.2 or dist <= stop_dist then
                        if not comp._arrTaxiCompleteAnnounced then
                            maybe_gate_voice_callouts(comp, dist, auto_voice, comp._gateUseDgs)
                        end
                    end
                end
            else
                comp._gateNote = nil
            end
            local gate_info = (U and gate_alignment_info) and gate_alignment_info(comp, aircraft) or nil
            if gate_info then
                local cooldown = (comp._tuning and comp._tuning.gateGuidanceCooldownSec) or (C and C.gateGuidanceCooldownSec) or 4
                local last_time = comp._gateGuidanceLastTime or 0
                local same = (gate_info.direction == comp._gateGuidanceLastDir) and (gate_info.action == comp._gateGuidanceLastAction)
                if gate_info.action == "STOP" then
                    if not comp._gateGuidanceStop then
                        local allow_voice = auto_voice
                        if comp._gateCalloutStop then
                            allow_voice = false
                        end
                        maybe_keep_gate_popup(gate_info)
                        U.emit_guidance(comp, now, gate_info, allow_voice)
                        comp._gateGuidanceStop = true
                        comp._gateGuidanceLastDir = gate_info.direction
                        comp._gateGuidanceLastAction = gate_info.action
                        comp._gateGuidanceLastTime = now
                    end
                    return
                end
                comp._gateGuidanceStop = false
                if (not same) or ((now - last_time) >= cooldown) then
                    maybe_keep_gate_popup(gate_info)
                    U.emit_guidance(comp, now, gate_info, auto_voice)
                    comp._gateGuidanceLastDir = gate_info.direction
                    comp._gateGuidanceLastAction = gate_info.action
                    comp._gateGuidanceLastTime = now
                    return
                end
            else
                comp._gateGuidanceStop = false
            end
            return
        else
            comp._gateNote = nil
            if comp._gateCalloutKey ~= nil then
                reset_gate_callouts(comp, nil)
            end
        end
        if not comp._route or not comp._route.path then
            diag("no-route")
            return
        end
        if comp.mode == 0 and before_takeoff_active_or_set(comp) then
            diag("before-takeoff")
        end
        if comp._depThresholdLatched and (comp.mode == 0) then
            diag("dep-threshold")
            return
        end
        local data = comp._route.data or comp._data
        local path = comp._route.path
        local first_guidance = (comp._lastGuidanceNodeId == nil and comp._lastGuidanceLabel == nil)
        local function freehand_segment_label(from_id, to_id)
            local route = comp._route
            local rdata = route and route.data or nil
            local base = comp._data
            if not rdata or not rdata.nodes or not base or not base.edges or not base.nodes then
                return nil
            end
            local n1 = rdata.nodes[from_id]
            local n2 = rdata.nodes[to_id]
            if not (n1 and n2 and n1.east and n1.north and n2.east and n2.north) then
                return nil
            end
            local seg_heading = heading_deg_from_to(n1.east, n1.north, n2.east, n2.north)
            if not seg_heading then
                return nil
            end
            local mid_e = (n1.east + n2.east) * 0.5
            local mid_n = (n1.north + n2.north) * 0.5
            local max_d2 = C.freehandLabelMaxMeters * C.freehandLabelMaxMeters

            local function search(allow_runway, max_angle)
                local best_label = nil
                local best_is_runway = false
                local best_d2 = nil
                for _, edge in ipairs(base.edges) do
                    local label = edge.label or ""
                    if label == "" then
                        goto continue
                    end
                    local is_rwy = is_runway_label(label)
                    if is_rwy and not allow_runway then
                        goto continue
                    end
                    local e1 = base.nodes[edge.from]
                    local e2 = base.nodes[edge.to]
                    if not (e1 and e2 and e1.east and e1.north and e2.east and e2.north) then
                        goto continue
                    end
                    local px, py = project_point_to_segment(mid_e, mid_n, e1.east, e1.north, e2.east, e2.north)
                    local d2 = distance_sq(mid_e, mid_n, px, py)
                    if d2 > max_d2 then
                        goto continue
                    end
                    local edge_heading = heading_deg_from_to(e1.east, e1.north, e2.east, e2.north)
                    if not edge_heading then
                        goto continue
                    end
                    local diff = heading_diff_deg(seg_heading, edge_heading)
                    local diff_rev = heading_diff_deg(seg_heading, (edge_heading + 180) % 360)
                    local ang = math.min(diff, diff_rev)
                    if ang > max_angle then
                        goto continue
                    end
                    if not best_d2 or d2 < best_d2 then
                        best_d2 = d2
                        best_label = label
                        best_is_runway = is_rwy
                    end
                    ::continue::
                end
                if best_label then
                    return best_label, best_is_runway
                end
                return nil
            end

            local key = string.format("%s|%s", tostring(from_id), tostring(to_id))
            comp._freehandLabelCache = comp._freehandLabelCache or {}
            if comp._freehandLabelCache[key] ~= nil then
                return comp._freehandLabelCache[key]
            end

            local label, is_rwy = search(false, C.freehandLabelMaxAngle)
            if not label then
                label, is_rwy = search(true, C.freehandRunwayLabelMaxAngle)
            end
            local result = nil
            if label then
                result = { label = label, is_runway = is_rwy }
            end
            comp._freehandLabelCache[key] = result
            return result
        end

        local function guidance_label_info(from_id, to_id, fallback_label, ramp_hint, allow_missing)
            local raw_label = get_edge_label(data, from_id, to_id)
            if (not raw_label or raw_label == "") and is_freehand then
                local fh = freehand_segment_label(from_id, to_id)
                if fh and fh.label and fh.label ~= "" then
                    if fh.is_runway then
                        local display = normalize_runway_name(fh.label)
                        if display == "" then
                            display = tostring(fh.label)
                        end
                        return { kind = "runway", text = runway_label_voice(fh.label), display = display }
                    end
                    raw_label = fh.label
                end
            end
            if raw_label and raw_label ~= "" then
                if raw_label == "RAMP" or (is_runway_label(raw_label) and raw_label ~= "RAMP") then
                    local display = normalize_runway_name(raw_label)
                    if display == "" then
                        display = tostring(raw_label)
                    end
                    return { kind = "runway", text = runway_label_voice(raw_label), display = display }
                end
                local display = normalize_taxiway_label(raw_label)
                if display == "" and not allow_missing then
                    display = tostring(raw_label)
                end
                return { kind = "taxiway", text = taxiway_label_voice(display), display = display }
            end
            if ramp_hint and ramp_hint ~= "" then
                return { kind = "ramp", text = ramp_hint, display = ramp_hint }
            end
            if fallback_label and fallback_label ~= "" then
                return { kind = "route", text = fallback_label, display = fallback_label }
            end
            if allow_missing then
                return nil
            end
            return { kind = "route", text = "Taxi", display = "ROUTE" }
        end

        local function build_guidance_from_segment(seg_idx)
            local from_id = path[seg_idx]
            local to_id = path[seg_idx + 1]
            if not from_id or not to_id then
                return nil
            end
            local info = guidance_label_info(from_id, to_id, nil, nil, true)
            if not info then
                return nil
            end
            if info.kind == "taxiway" then
                info.text = "Continue straight on " .. taxiway_label_voice(info.display or info.text or "")
                info.action = "CONTINUE"
            elseif info.kind == "runway" then
                info.text = "Continue on " .. runway_label_voice(info.display or info.text or "")
                info.action = "CONTINUE"
            end
            if info.display and info.display ~= "" then
                info.label = build_visual_label(info.kind, info.display)
            end
            info.direction = "straight"
            info.targetSegIdx = seg_idx
            return info
        end

        local function build_guidance_for_turn(seg_idx, turn_dir)
            local from_id = path[seg_idx]
            local to_id = path[seg_idx + 1]
            if not from_id or not to_id then
                return nil
            end
            local info = guidance_label_info(from_id, to_id, nil, nil, true)
            if not info then
                return nil
            end
            info.direction = turn_dir
            info.action = (turn_dir == "left") and "TURN LEFT" or "TURN RIGHT"
            info.targetSegIdx = seg_idx
            return info
        end

        local function build_guidance_for_crossing(seg_idx, label)
            local text = "Caution, crossing " .. runway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "CROSS RWY",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_exit(seg_idx, label, exit_dir)
            local text = "Leave " .. runway_label_voice(label) .. " to " .. exit_dir
            return {
                text = text,
                direction = exit_dir,
                action = "EXIT RWY",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_entry(seg_idx, label, turn_dir)
            local text = "Enter " .. runway_label_voice(label)
            local action = "ENTER RWY"
            if turn_dir == "left" then
                text = "Turn left on " .. runway_label_voice(label)
                action = "TURN LEFT"
            elseif turn_dir == "right" then
                text = "Turn right on " .. runway_label_voice(label)
                action = "TURN RIGHT"
            end
            return {
                text = text,
                direction = turn_dir or "straight",
                action = action,
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_runway_entry(seg_idx, label, turn_dir)
            local text = "Taxi via " .. runway_label_voice(label)
            local action = "TAXI VIA"
            if turn_dir == "left" then
                text = "Turn left on " .. runway_label_voice(label)
                action = "TURN LEFT"
            elseif turn_dir == "right" then
                text = "Turn right on " .. runway_label_voice(label)
                action = "TURN RIGHT"
            end
            return {
                text = text,
                direction = turn_dir or "straight",
                action = action,
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_continue(seg_idx, label)
            local text = "Continue straight on " .. taxiway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "CONTINUE",
                label = build_visual_label("taxiway", label),
                kind = "taxiway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_taxi(seg_idx, label)
            local text = "Taxi via " .. taxiway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "TAXI VIA",
                label = build_visual_label("taxiway", label),
                kind = "taxiway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_initial(seg_idx, label)
            local text = "Taxi via " .. taxiway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "TAXI VIA",
                label = build_visual_label("taxiway", label),
                kind = "taxiway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_ramp(seg_idx, label)
            return {
                text = "Taxi to " .. tostring(label),
                direction = "straight",
                action = "TAXI TO",
                label = label,
                kind = "ramp",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_route(seg_idx)
            return {
                text = "Taxi",
                direction = "straight",
                action = "TAXI",
                label = build_visual_label("route", "ROUTE"),
                kind = "route",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_turn_text(turn_dir, label)
            local text = "Turn " .. turn_dir .. " on " .. taxiway_label_voice(label)
            return {
                text = text,
                direction = turn_dir,
                action = (turn_dir == "left") and "TURN LEFT" or "TURN RIGHT",
                label = build_visual_label("taxiway", label),
                kind = "taxiway"
            }
        end

        local function build_guidance_for_runway_turn(turn_dir, label)
            local text = "Turn " .. turn_dir .. " on " .. runway_label_voice(label)
            return {
                text = text,
                direction = turn_dir,
                action = (turn_dir == "left") and "TURN LEFT" or "TURN RIGHT",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway"
            }
        end

        local function build_guidance_for_crossing_warning(seg_idx, label)
            local text = "Caution, crossing " .. runway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "CROSS RWY",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_runway_exit(seg_idx, label, exit_dir)
            local text = "Leave " .. runway_label_voice(label) .. " to " .. exit_dir
            return {
                text = text,
                direction = exit_dir,
                action = "EXIT RWY",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_runway_crossing(seg_idx, label)
            local text = "Caution, crossing " .. runway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "CROSS RWY",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_runway_continue(seg_idx, label)
            local text = "Continue on " .. runway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "CONTINUE",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_runway_entry(seg_idx, label)
            local text = "Taxi via " .. runway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "TAXI VIA",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_hold_short(seg_idx, label)
            local text = "Hold short of " .. runway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "HOLD SHORT",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_gate(seg_idx, label)
            return {
                text = "Taxi to " .. tostring(label),
                direction = "straight",
                action = "TAXI TO",
                label = label,
                kind = "ramp",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_stop()
            return {
                text = "Stop",
                direction = "straight",
                action = "STOP"
            }
        end

        local function build_guidance_for_gate_stop(seg_idx, label)
            return {
                text = "Stop",
                direction = "straight",
                action = "STOP",
                label = label,
                kind = "ramp",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_line_up(seg_idx, label)
            local text = "Line up on " .. runway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "LINE UP",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_takeoff(seg_idx, label)
            local text = "Cleared for takeoff " .. runway_label_voice(label)
            return {
                text = text,
                direction = "straight",
                action = "TAKEOFF",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_turning(seg_idx, label, turn_dir)
            local text = "Turn " .. turn_dir .. " on " .. taxiway_label_voice(label)
            return {
                text = text,
                direction = turn_dir,
                action = (turn_dir == "left") and "TURN LEFT" or "TURN RIGHT",
                label = build_visual_label("taxiway", label),
                kind = "taxiway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_turning_runway(seg_idx, label, turn_dir)
            local text = "Turn " .. turn_dir .. " on " .. runway_label_voice(label)
            return {
                text = text,
                direction = turn_dir,
                action = (turn_dir == "left") and "TURN LEFT" or "TURN RIGHT",
                label = build_visual_label("runway", normalize_runway_name(label)),
                kind = "runway",
                targetSegIdx = seg_idx
            }
        end

        local function build_guidance_for_route_complete()
            return {
                text = "Taxi complete",
                direction = "straight",
                action = "TAXI COMPLETE",
                label = build_visual_label("route", "ROUTE"),
                kind = "route"
            }
        end

        local function build_guidance_for_taxi_complete(seg_idx, label)
            return {
                text = "Taxi complete",
                direction = "straight",
                action = "TAXI COMPLETE",
                label = label,
                kind = "route",
                targetSegIdx = seg_idx
            }
        end

        local function maybe_skip_duplicate_guidance(new_info)
            if not new_info then
                return nil
            end
            if comp._lastGuidanceLabel == new_info.display and comp._lastGuidanceAction == new_info.action then
                return nil
            end
            return new_info
        end

        local function ramp_guidance_label(seg_idx)
            local label = nil
            local route = comp._route
            if route and route.data and route.path and route.path[seg_idx + 1] then
                local node = route.data.nodes[route.path[seg_idx + 1]]
                if node and node.is_ramp then
                    label = node.ramp_name or node.ramp_id or "Gate"
                    label = U.short_ramp_label and U.short_ramp_label(node) or label
                end
            end
            return label
        end

        local function resolve_ramp_guidance(seg_idx, info)
            if not info or info.kind ~= "ramp" then
                return info
            end
            local label = info.display
            if not label or label == "" then
                label = ramp_guidance_label(seg_idx)
            end
            if label and label ~= "" then
                info.display = label
                info.label = label
                return info
            end
            return nil
        end

        local function set_guidance(info)
            if not info then
                return false
            end
            if info.action == "STOP" and info.kind == "ramp" then
                if comp._routeErr == "taxi-complete" or comp._arrTaxiCompleteAnnounced then
                    return false
                end
            end
            if is_visual_taxi_guidance_enabled() and info.visual ~= false then
                if info.queue then
                    queue_visual_guidance(comp, info)
                else
                    set_visual_guidance(comp, info)
                end
            end
            if auto_voice and is_voice_enabled() and info.text and info.text ~= "" then
                local last_text = comp._lastGuidanceVoiceText
                local last_time = comp._lastGuidanceVoiceTime or 0
                local cooldown = (C and C.guidanceCooldown) or 8
                if info.text ~= last_text or (now and (now - last_time) >= cooldown) then
                    speak_guidance_text(comp, info.text)
                    comp._lastGuidanceVoiceText = info.text
                    comp._lastGuidanceVoiceTime = now or 0
                end
            end
            if comp._guidanceForceInitial then
                comp._guidanceForceInitial = nil
            end
            return true
        end

        if guidance_state ~= "route" then
            diag("not-route")
            return
        end
        if not route or not data or not path then
            diag("no-path")
            return
        end

        local seg_idx, dist = find_nearest_segment(data, path, aircraft.east, aircraft.north)
        if not seg_idx or seg_idx >= #path then
            diag("no-segment", string.format("seg=%s path=%s", tostring(seg_idx), tostring(path and #path or 0)))
            return
        end
        if dist == nil then
            diag("no-distance")
            return
        end

        if comp._guidanceRoute ~= route then
            comp._guidanceRoute = route
            comp._guidanceActiveSegIdx = nil
            comp._guidanceMonotonicSegIdx = nil
            comp._lastGuidanceSegment = nil
            comp._lastGuidanceLabel = nil
            comp._lastGuidanceAction = nil
        end
        local active_seg = comp._guidanceActiveSegIdx
        if active_seg and active_seg >= #path then
            active_seg = nil
            comp._guidanceActiveSegIdx = nil
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
                comp._guidanceActiveSegIdx = seg_idx
            end
        elseif not active_seg then
            comp._guidanceActiveSegIdx = seg_idx
        end
        do
            local auto_idx = comp._autoTaxiLastSegIdx
            if not auto_idx and comp._autoTaxiActive then
                auto_idx = comp._autoTaxiActiveSegIdx
            end
            if auto_idx and auto_idx >= 1 and auto_idx < #path then
                local gactive = comp._guidanceActiveSegIdx
                if gactive and auto_idx < gactive then
                    seg_idx = gactive
                else
                    seg_idx = auto_idx
                    comp._guidanceActiveSegIdx = seg_idx
                end
            end
        end
        do
            local mono = comp._guidanceMonotonicSegIdx
            if mono and mono >= 1 and mono < #path then
                if seg_idx < mono then
                    seg_idx = mono
                elseif seg_idx > mono then
                    comp._guidanceMonotonicSegIdx = seg_idx
                end
            else
                comp._guidanceMonotonicSegIdx = seg_idx
            end
            comp._guidanceActiveSegIdx = seg_idx
        end
        do
            local last_seg = comp._lastGuidanceSegment
            local last_action = comp._lastGuidanceAction
            if last_seg and last_action
                and (last_action == "TURN LEFT" or last_action == "TURN RIGHT")
                and seg_idx > last_seg
                and data and data.nodes and path[last_seg] and path[last_seg + 1] then
                local ln1 = data.nodes[path[last_seg]]
                local ln2 = data.nodes[path[last_seg + 1]]
                if ln1 and ln2 and ln1.east and ln1.north and ln2.east and ln2.north then
                    local _, _, t = project_point_to_segment(
                        aircraft.east, aircraft.north,
                        ln1.east, ln1.north,
                        ln2.east, ln2.north
                    )
                    if t and t < 1 then
                        seg_idx = last_seg
                        comp._guidanceActiveSegIdx = seg_idx
                        if comp._guidanceMonotonicSegIdx and comp._guidanceMonotonicSegIdx < seg_idx then
                            comp._guidanceMonotonicSegIdx = seg_idx
                        end
                    end
                end
            end
        end

        local next_idx = seg_idx + 1
        local seg_len = nil
        if data and data.nodes then
            local n1 = data.nodes[path[seg_idx]]
            local n2 = data.nodes[path[seg_idx + 1]]
            if n1 and n2 and n1.east and n1.north and n2.east and n2.north then
                seg_len = math.sqrt(distance_sq(n1.east, n1.north, n2.east, n2.north))
            end
        end
        if comp._autoTaxiTargetSegIdx and comp._autoTaxiTargetSegIdx == seg_idx then
            if comp._autoTaxiTargetAction == "CROSS RWY" then
                set_guidance(build_guidance_for_crossing_warning(seg_idx, comp._autoTaxiTargetLabel or ""))
                return
            elseif comp._autoTaxiTargetAction == "HOLD SHORT" then
                set_guidance(build_guidance_for_hold_short(seg_idx, comp._autoTaxiTargetLabel or ""))
                return
            end
        end

        local force_initial = comp._guidanceForceInitial and first_guidance
        local threshold = guidance_distance_for_speed((yal and yal.tirespeed and get(yal.tirespeed)) or 0)
        if comp._lastGuidanceSegment and comp._lastGuidanceSegment == seg_idx then
            if (now - (comp._lastGuidanceTime or 0)) < C.guidanceCooldown then
                diag("cooldown")
                return
            end
        end
        if dist > threshold then
            diag("too-far", string.format("dist=%.1f thresh=%.1f", dist, threshold))
            return
        end
        if not force_initial then
            if not comp._guidanceMoveAnchor then
                comp._guidanceMoveAnchor = {
                    east = aircraft.east,
                    north = aircraft.north,
                    t = now
                }
            end
            local moved = false
            local move_anchor = comp._guidanceMoveAnchor
            if move_anchor then
                local dx = aircraft.east - move_anchor.east
                local dy = aircraft.north - move_anchor.north
                local moved_dist = math.sqrt(dx * dx + dy * dy)
                if moved_dist >= C.initialGuidanceMinForwardMeters then
                    moved = true
                else
                    local elapsed = (now or 0) - (move_anchor.t or 0)
                    if elapsed >= C.initialGuidanceMinForwardSeconds then
                        moved = true
                    elseif moved_dist <= -C.initialGuidanceReverseResetMeters then
                        comp._guidanceMoveAnchor = nil
                    end
                end
            end
            if not moved then
                diag("forward-wait", string.format("dist=%.1f", dist))
                return
            end
            if first_guidance and gs < C.initialGuidanceMinSpeed then
                diag("too-slow", string.format("dist=%.1f", dist))
                return
            end
            if gs < C.guidanceMinSpeed then
                diag("non-forward-speed", string.format("dist=%.1f", dist))
                return
            end
        end
        local next_info = nil
        local next_label = nil
        local next_display = nil
        local next_kind = nil
        local raw_label = get_edge_label(data, path[seg_idx], path[seg_idx + 1])
        local next_raw_label = get_edge_label(data, path[seg_idx + 1], path[seg_idx + 2])
        local n1 = data.nodes[path[seg_idx]]
        local n2 = data.nodes[path[seg_idx + 1]]
        local n3 = data.nodes[path[seg_idx + 2]]
        local turn_dir = nil
        if n1 and n2 and n3 and n1.east and n1.north and n2.east and n2.north and n3.east and n3.north then
            local h1 = heading_deg_from_to(n1.east, n1.north, n2.east, n2.north)
            local h2 = heading_deg_from_to(n2.east, n2.north, n3.east, n3.north)
            if h1 and h2 then
                local diff = heading_diff_deg(h1, h2)
                if diff >= C.guidanceTurnAngle then
                    local cross = (n2.east - n1.east) * (n3.north - n2.north)
                        - (n2.north - n1.north) * (n3.east - n2.east)
                    turn_dir = (cross >= 0) and "left" or "right"
                end
            end
        end

        if seg_len and seg_len < C.guidanceFirstTurnMinMeters then
            if (now - (comp._lastGuidanceTime or 0)) < C.guidanceFirstTurnMinSeconds then
                diag("first-turn-delay", string.format("dist=%.1f", dist))
                return
            end
        end

        if raw_label and next_raw_label and raw_label ~= "" and next_raw_label ~= "" then
            local raw_rwy = is_runway_label(raw_label)
            local next_rwy = is_runway_label(next_raw_label)
            if raw_rwy ~= next_rwy then
                if raw_rwy and not next_rwy then
                    next_info = build_guidance_for_exit(seg_idx, raw_label, turn_dir or "straight")
                elseif not raw_rwy and next_rwy then
                    next_info = build_guidance_for_entry(seg_idx, next_raw_label, turn_dir)
                end
            elseif raw_rwy and next_rwy and raw_label == next_raw_label then
                next_info = build_guidance_for_runway_continue(seg_idx, raw_label)
            elseif raw_rwy and next_rwy and raw_label ~= next_raw_label then
                next_info = build_guidance_for_crossing_warning(seg_idx, next_raw_label)
            end
        end

        if not next_info then
            local info = guidance_label_info(path[seg_idx], path[seg_idx + 1], nil, nil, false)
            if info then
                next_display = info.display
                next_kind = info.kind
                next_label = info.text
            end
            if next_display and next_kind == "taxiway" then
                local next_info_raw = guidance_label_info(path[seg_idx + 1], path[seg_idx + 2], nil, nil, true)
                if next_info_raw and next_info_raw.display and next_info_raw.kind == "taxiway" then
                    local same = normalize_taxiway_label(next_display) == normalize_taxiway_label(next_info_raw.display)
                    if same and turn_dir and turn_dir ~= "straight" then
                        next_info = build_guidance_for_turn_text(turn_dir, next_info_raw.display)
                    elseif same and not turn_dir then
                        next_info = build_guidance_for_continue(seg_idx, next_info_raw.display)
                    elseif turn_dir and turn_dir ~= "straight" then
                        next_info = build_guidance_for_turning(seg_idx, next_info_raw.display, turn_dir)
                    end
                elseif turn_dir and turn_dir ~= "straight" then
                    next_info = build_guidance_for_turning(seg_idx, next_display, turn_dir)
                end
            end
            if not next_info then
                if next_kind == "taxiway" then
                    if turn_dir and turn_dir ~= "straight" then
                        next_info = build_guidance_for_turning(seg_idx, next_display, turn_dir)
                    else
                        next_info = build_guidance_for_taxi(seg_idx, next_display)
                    end
                elseif next_kind == "runway" then
                    if turn_dir and turn_dir ~= "straight" then
                        next_info = build_guidance_for_runway_turn(turn_dir, next_display)
                    else
                        next_info = build_guidance_for_runway_entry(seg_idx, next_display)
                    end
                elseif next_kind == "ramp" then
                    next_info = build_guidance_for_gate(seg_idx, next_display)
                else
                    if comp._lastGuidanceAction then
                        next_info = nil
                    else
                        next_info = build_guidance_for_route(seg_idx)
                    end
                end
            end
        end

        if next_info then
            next_info.display = next_info.display or next_display
            next_info.kind = next_info.kind or next_kind
            next_info.text = next_info.text or next_label or "Taxi"
            if next_info.kind == "taxiway" and next_info.display and next_info.display ~= "" then
                next_info.label = build_visual_label(next_info.kind, next_info.display)
            elseif next_info.kind == "runway" and next_info.display and next_info.display ~= "" then
                next_info.label = build_visual_label(next_info.kind, next_info.display)
            end
            if next_info.kind == "runway" and next_info.action == "CONTINUE" then
                local last_action = comp._lastGuidanceAction
                local last_label = comp._lastGuidanceLabel
                if last_action == "LEAVE RWY" and last_label and next_info.display
                    and last_label == next_info.display then
                    local last_seg = comp._lastGuidanceSegment
                    if last_seg and seg_idx and seg_idx <= (last_seg + 1) then
                        next_info = nil
                    end
                end
                if (last_action == "TURN LEFT" or last_action == "TURN RIGHT")
                    and last_label and next_info.display
                    and last_label == next_info.display then
                    local last_seg = comp._lastGuidanceSegment
                    if last_seg and seg_idx and seg_idx <= (last_seg + 1) then
                        next_info = nil
                    end
                end
            end
            if comp._lastGuidanceSegment == seg_idx and comp._lastGuidanceAction and next_info.action then
                local last_action = comp._lastGuidanceAction
                local new_action = next_info.action
                local last_basic = (last_action == "TURN LEFT" or last_action == "TURN RIGHT"
                    or last_action == "CONTINUE" or last_action == "TAXI VIA")
                local new_basic = (new_action == "TURN LEFT" or new_action == "TURN RIGHT"
                    or new_action == "CONTINUE" or new_action == "TAXI VIA")
                if last_basic and new_basic and last_action ~= new_action then
                    local last_turn = (last_action == "TURN LEFT" or last_action == "TURN RIGHT")
                    local new_turn = (new_action == "TURN LEFT" or new_action == "TURN RIGHT")
                    if last_turn then
                        next_info = nil
                    elseif not last_turn and not new_turn then
                        next_info = nil
                    end
                end
            end
            next_info = resolve_ramp_guidance(seg_idx, next_info)
            next_info = maybe_skip_duplicate_guidance(next_info)
            if next_info then
                if is_visual_taxi_guidance_enabled() and next_info.visual ~= false then
                    next_info.showAt = now and (now + C.visualGuidanceSyncDelay) or nil
                    next_info.minShowUntil = now and (now + C.visualGuidanceMinShow) or nil
                    next_info.expiresAt = now and (now + C.visualGuidanceDuration) or nil
                end
                if set_guidance(next_info) then
                    comp._lastGuidanceSegment = seg_idx
                    comp._lastGuidanceNodeId = path[seg_idx + 1]
                    comp._lastGuidanceLabel = next_info.display
                    comp._lastGuidanceAction = next_info.action
                    comp._lastGuidanceTime = now
                end
                return
            end
        end

        if not next_info and dist <= (C.guidanceTurnDistance * 0.5) then
            local info = build_guidance_from_segment(seg_idx)
            if info then
                if is_visual_taxi_guidance_enabled() and info.visual ~= false then
                    info.showAt = now and (now + C.visualGuidanceSyncDelay) or nil
                    info.minShowUntil = now and (now + C.visualGuidanceMinShow) or nil
                    info.expiresAt = now and (now + C.visualGuidanceDuration) or nil
                end
                if set_guidance(info) then
                    comp._lastGuidanceSegment = seg_idx
                    comp._lastGuidanceNodeId = path[seg_idx + 1]
                    comp._lastGuidanceLabel = info.display
                    comp._lastGuidanceAction = info.action
                    comp._lastGuidanceTime = now
                end
                return
            end
        end
        diag("no-guidance")
    end

    local function emit_guidance(comp, now, info, allow_voice)
        if not comp or not info or not info.text or info.text == "" then
            return
        end
        if helpers and helpers.logInfoTS then
            local msg = "TaxiGuide: " .. tostring(info.text)
            if info.action or info.direction or info.kind then
                msg = msg
                    .. " | action=" .. tostring(info.action or "")
                    .. " dir=" .. tostring(info.direction or "")
                    .. " kind=" .. tostring(info.kind or "")
            end
            helpers.logInfoTS(msg)
        end
        if allow_voice and is_voice_enabled() then
            speak_guidance_text(comp, info.text)
        end
        if info.targetSegIdx then
            if comp._autoTaxiTargetSegIdx ~= info.targetSegIdx then
                comp._autoTaxiTargetSegIdx = info.targetSegIdx
                comp._autoTaxiTargetTime = now
                comp._autoTaxiTargetAction = info.action
                if helpers and helpers.logInfoTS then
                    helpers.logInfoTS("AutoTaxiTarget: seg=" .. tostring(info.targetSegIdx) .. " action=" .. tostring(info.action or ""))
                end
            else
                comp._autoTaxiTargetTime = now
                comp._autoTaxiTargetAction = info.action
            end
        end
        if is_visual_taxi_guidance_enabled() and info.visual ~= false then
            info.issuedAt = now
            info.showAt = now and (now + (C and C.visualGuidanceSyncDelay or 0)) or nil
            info.expiresAt = now and (now + (C and C.visualGuidanceSyncDelay or 0) + (C and C.visualGuidanceDuration or 7)) or nil
            info.minShowUntil = now and (now + (C and C.visualGuidanceSyncDelay or 0) + (C and C.visualGuidanceMinShow or 1.0)) or nil
            if info.queue and comp._visualGuidance then
                queue_visual_guidance(comp, info)
            else
                set_visual_guidance(comp, info)
            end
        end
    end

    U.guidance_distance_for_speed = guidance_distance_for_speed
    U.speak_guidance_text = speak_guidance_text
    U.build_visual_label = build_visual_label
    U.is_taxi_complete_info = is_taxi_complete_info
    U.set_visual_guidance = set_visual_guidance
    U.queue_visual_guidance = queue_visual_guidance
    U.clear_visual_guidance = clear_visual_guidance
    U.set_guidance_state = set_guidance_state
    U.update_visual_guidance = update_visual_guidance
    U.maybe_speak_guidance = maybe_speak_guidance
    U.emit_guidance = emit_guidance
end

return M
