local M = {}

local defaultW = 860
local defaultH = 520
local headerH = 22
local toolbarH = 26
local mapPadding = 8
local updateInterval = 1.0
local guidanceCooldown = 8
local rerouteCooldown = 6
local rerouteDriftMeters = 40
local guidanceMinSpeed = 1
local initialGuidanceMinSpeed = 0.2
local guidanceTurnDistance = 80
local guidanceTurnAngle = 20
local guidanceLeadTimeSec = 12
local guidanceMaxDistance = 180
local guidanceStraightAngle = 10
local visualGuidanceDuration = 7
local visualGuidanceMinShow = 1.0
local visualGuidanceSyncDelay = 0.0
local startRampMaxMeters = 80
local startEndSnapMeters = 20
local projectionShiftThreshold = 500
local runwayRouteMaxSpeed = 45
local depThresholdGateMeters = 60
local depThresholdHeadingLimit = 25
local depTakeoffLatchSpeed = 25
local depTakeoffLatchHoldSec = 2.0
local depRunwayCorridorMin = 25
local depRunwayCorridorMax = 80
local depRunwayCorridorBuffer = 10
local qualityDistanceMeters = 150
local qualityDistanceSeconds = 6
local qualityRerouteWindowSec = 60
local qualityRerouteLimit = 6
local qualityBadLabelRatio = 0.3
local qualityNoneLabelRatio = 0.1
local qualityMinLabelEdges = 6
local qualityBadHoldSec = 8
local qualityArrGraceSec = 45
local arrStartNodeMaxMeters = 180
local autoGateSwitchDist = 35
local autoGateSwitchDelta = 20
local autoGateSwitchRatio = 0.6
local autoGateSwitchSpeed = 5
local autoGateSwitchHoldSec = 2.0
local autoGateSwitchCooldownSec = 10.0
local parkingBrakeCompleteDist = 35

local minZoom = 0.2
local maxZoom = 5
local zoomStep = 1.2
local minFont = 8
local maxFont = 24
local waypointDragPixels = 4
local editDecisionAngle = 10
local editHandleMergeMeters = 4

local def = require("definitions")
local settings = require("settings")
local helpers = require("helpers")

local function log_taxi(message)
    if helpers and helpers.logInfoTS then
        helpers.logInfoTS(message)
    end
end

local function copy_waypoints(src)
    local out = {}
    if not src then
        return out
    end
    for i, wp in ipairs(src) do
        if wp then
            out[i] = {
                lat = wp.lat,
                lon = wp.lon,
                east = wp.east,
                north = wp.north,
                segment_idx = wp.segment_idx
            }
        end
    end
    return out
end

local function copy_set(src)
    local out = {}
    if not src then
        return out
    end
    for k, v in pairs(src) do
        if v then
            out[k] = true
        end
    end
    return out
end

local function snapshot_edit_state(comp)
    return {
        routeWaypoints = copy_waypoints(comp._routeWaypoints),
        editStartOverride = comp._editStartOverride and {
            lat = comp._editStartOverride.lat,
            lon = comp._editStartOverride.lon,
            mode = comp._editStartOverride.mode,
            icao = comp._editStartOverride.icao
        } or nil,
        editEndOverride = comp._editEndOverride and {
            lat = comp._editEndOverride.lat,
            lon = comp._editEndOverride.lon,
            mode = comp._editEndOverride.mode,
            icao = comp._editEndOverride.icao
        } or nil,
        drawFreehand = comp._drawFreehand,
        editSuppressedNodes = copy_set(comp._editSuppressedNodes),
        selectedEndRampKey = comp._selectedEndRampKey,
        selectedDepEntryId = comp._selectedDepEntryId
    }
end

local function restore_edit_state(comp, state)
    if not state then
        return
    end
    comp._routeWaypoints = copy_waypoints(state.routeWaypoints)
    comp._editStartOverride = state.editStartOverride
    comp._editEndOverride = state.editEndOverride
    if state.drawFreehand ~= nil then
        comp._drawFreehand = state.drawFreehand
    end
    comp._editSuppressedNodes = copy_set(state.editSuppressedNodes)
    comp._selectedEndRampKey = state.selectedEndRampKey
    comp._selectedDepEntryId = state.selectedDepEntryId
end

local function push_undo(comp, reason)
    comp._undoState = snapshot_edit_state(comp)
    comp._undoReason = reason or "edit"
    log_taxi("TaxiEdit: undo-push reason=" .. tostring(comp._undoReason))
end

local function is_valid_latlon(lat, lon)
    if lat == nil or lon == nil then
        return false
    end
    if lat == 0 and lon == 0 then
        return false
    end
    return true
end

local function compute_bounds_center(bounds)
    if not bounds or not bounds.minX or not bounds.maxX or not bounds.minY or not bounds.maxY then
        return 0, 0
    end
    return (bounds.minX + bounds.maxX) * 0.5, (bounds.minY + bounds.maxY) * 0.5
end

local function update_bounds(bounds, x, y)
    if not bounds then
        return
    end
    if not bounds.minX or x < bounds.minX then
        bounds.minX = x
    end
    if not bounds.maxX or x > bounds.maxX then
        bounds.maxX = x
    end
    if not bounds.minY or y < bounds.minY then
        bounds.minY = y
    end
    if not bounds.maxY or y > bounds.maxY then
        bounds.maxY = y
    end
end

local function estimate_text_width(text, size)
    local len = string.len(text or "")
    return len * (size * 0.6)
end

local function compute_bounds_scale(bounds, mapW, mapH)
    if not bounds or not bounds.minX or not bounds.maxX or not bounds.minY or not bounds.maxY then
        return 1
    end
    local width = bounds.maxX - bounds.minX
    local height = bounds.maxY - bounds.minY
    if width <= 0 or height <= 0 then
        return 1
    end
    local scale = math.min(mapW / width, mapH / height)
    return scale * 0.92
end

local function rotate_point(dx, dy, radians)
    if radians == 0 then
        return dx, dy
    end
    local cosA = math.cos(radians)
    local sinA = math.sin(radians)
    return dx * cosA - dy * sinA, dx * sinA + dy * cosA
end

local function heading_to_compass(heading)
    local h = tonumber(heading) or 0
    h = h % 360
    local dirs = {
        "north",
        "north east",
        "east",
        "south east",
        "south",
        "south west",
        "west",
        "north west"
    }
    local idx = math.floor((h + 22.5) / 45) + 1
    if idx > #dirs then
        idx = 1
    end
    return dirs[idx]
end

local function distance_meters_latlon(lat1, lon1, lat2, lon2)
    if not lat1 or not lon1 or not lat2 or not lon2 then
        return nil
    end
    local r = 6371000
    local phi1 = math.rad(lat1)
    local phi2 = math.rad(lat2)
    local dphi = phi2 - phi1
    local dlambda = math.rad(lon2 - lon1)
    local sin_dphi = math.sin(dphi * 0.5)
    local sin_dlam = math.sin(dlambda * 0.5)
    local a = sin_dphi * sin_dphi + math.cos(phi1) * math.cos(phi2) * sin_dlam * sin_dlam
    local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c
end

local function latlon_to_local(lat, lon)
    local x, _, z = sasl.worldToLocal(lat, lon, 0)
    return x, -z
end

local function ensure_waypoint_latlon(wp)
    if not wp then
        return nil, nil
    end
    if is_valid_latlon(wp.lat, wp.lon) then
        return wp.lat, wp.lon
    end
    if wp.east ~= nil and wp.north ~= nil then
        local lat, lon = sasl.localToWorld(wp.east, 0, -wp.north)
        if is_valid_latlon(lat, lon) then
            wp.lat = lat
            wp.lon = lon
            return lat, lon
        end
    end
    return nil, nil
end

local function waypoint_matches_override(wp, override)
    if not wp or not override or not is_valid_latlon(override.lat, override.lon) then
        return false
    end
    local wlat, wlon = ensure_waypoint_latlon(wp)
    if not is_valid_latlon(wlat, wlon) then
        return false
    end
    local d = distance_meters_latlon(wlat, wlon, override.lat, override.lon)
    return d ~= nil and d <= 1.5
end

local function find_projection_ref(data)
    if not data then
        return nil, nil, nil
    end
    if data.nodes then
        for _, node in pairs(data.nodes) do
            if node and is_valid_latlon(node.lat, node.lon) and node.east ~= nil and node.north ~= nil then
                return node, node.east, node.north
            end
        end
    end
    if data.ramps then
        for _, ramp in ipairs(data.ramps) do
            if ramp and is_valid_latlon(ramp.lat, ramp.lon) and ramp.east ~= nil and ramp.north ~= nil then
                return ramp, ramp.east, ramp.north
            end
        end
    end
    if data.runways then
        for _, rwy in ipairs(data.runways) do
            if rwy and is_valid_latlon(rwy.lat1, rwy.lon1) and rwy.east1 ~= nil and rwy.north1 ~= nil then
                return { lat = rwy.lat1, lon = rwy.lon1 }, rwy.east1, rwy.north1
            end
        end
    end
    return nil, nil, nil
end

local function shift_bounds(bounds, dx, dy)
    if not bounds then
        return
    end
    if bounds.minX ~= nil then bounds.minX = bounds.minX + dx end
    if bounds.maxX ~= nil then bounds.maxX = bounds.maxX + dx end
    if bounds.minY ~= nil then bounds.minY = bounds.minY + dy end
    if bounds.maxY ~= nil then bounds.maxY = bounds.maxY + dy end
end

local function apply_projection_shift(data, dx, dy)
    if not data or (dx == 0 and dy == 0) then
        return
    end
    if data.nodes then
        for _, node in pairs(data.nodes) do
            if node.east ~= nil then
                node.east = node.east + dx
                node.x = node.east
            end
            if node.north ~= nil then
                node.north = node.north + dy
                node.z = -node.north
            end
        end
    end
    if data.ramps then
        for _, ramp in ipairs(data.ramps) do
            if ramp.east ~= nil then
                ramp.east = ramp.east + dx
                ramp.x = ramp.east
            end
            if ramp.north ~= nil then
                ramp.north = ramp.north + dy
                ramp.z = -ramp.north
            end
            ramp._draw_link_east = nil
            ramp._draw_link_north = nil
        end
    end
    if data.runways then
        for _, rwy in ipairs(data.runways) do
            if rwy.east1 ~= nil then
                rwy.east1 = rwy.east1 + dx
                rwy.x1 = rwy.east1
            end
            if rwy.north1 ~= nil then
                rwy.north1 = rwy.north1 + dy
                rwy.z1 = -rwy.north1
            end
            if rwy.east2 ~= nil then
                rwy.east2 = rwy.east2 + dx
                rwy.x2 = rwy.east2
            end
            if rwy.north2 ~= nil then
                rwy.north2 = rwy.north2 + dy
                rwy.z2 = -rwy.north2
            end
        end
    end
    if data.polygons then
        for _, poly in ipairs(data.polygons) do
            for _, pt in ipairs(poly.points or {}) do
                if pt.east ~= nil then
                    pt.east = pt.east + dx
                end
                if pt.north ~= nil then
                    pt.north = pt.north + dy
                end
            end
        end
    end
    shift_bounds(data.bounds, dx, dy)
    if data.route_cache then
        for _, route in pairs(data.route_cache) do
            if route and route.bounds then
                shift_bounds(route.bounds, dx, dy)
            end
        end
    end
end

local function align_taxi_data_projection(data)
    local ref, ref_east, ref_north = find_projection_ref(data)
    if not ref then
        return false, 0, 0
    end
    local cur_east, cur_north = latlon_to_local(ref.lat, ref.lon)
    if cur_east == nil or cur_north == nil then
        return false, 0, 0
    end
    local dx = cur_east - (ref_east or 0)
    local dy = cur_north - (ref_north or 0)
    local ax = math.abs(dx)
    local ay = math.abs(dy)
    if ax < 1 and ay < 1 then
        return false, dx, dy
    end
    if ax > projectionShiftThreshold or ay > projectionShiftThreshold then
        local function dist2_to_bounds(x, y, bounds)
            if not bounds or bounds.minX == nil or bounds.maxX == nil or bounds.minY == nil or bounds.maxY == nil then
                return nil
            end
            local ddx = 0
            if x < bounds.minX then
                ddx = bounds.minX - x
            elseif x > bounds.maxX then
                ddx = x - bounds.maxX
            end
            local ddy = 0
            if y < bounds.minY then
                ddy = bounds.minY - y
            elseif y > bounds.maxY then
                ddy = y - bounds.maxY
            end
            return ddx * ddx + ddy * ddy
        end
        local bounds = data and data.bounds or nil
        local d2_before = dist2_to_bounds(cur_east, cur_north, bounds)
        local d2_after = dist2_to_bounds(cur_east - dx, cur_north - dy, bounds)
        local allow = false
        if d2_before ~= nil and d2_after ~= nil then
            local before_far = d2_before > (projectionShiftThreshold * projectionShiftThreshold)
            local after_inside = (d2_after == 0)
            local after_much_closer = (d2_before > 0) and (d2_after <= d2_before * 0.05)
            if before_far and (after_inside or after_much_closer) then
                allow = true
            end
        end
        if not allow then
            if helpers and helpers.logInfoTS then
                helpers.logInfoTS(
                    string.format(
                        "TaxiProj: skip large shift dx=%.1f dy=%.1f d2_before=%s d2_after=%s",
                        dx,
                        dy,
                        d2_before ~= nil and string.format("%.1f", d2_before) or "nil",
                        d2_after ~= nil and string.format("%.1f", d2_after) or "nil"
                    )
                )
            end
            return false, dx, dy
        end
    end
    apply_projection_shift(data, dx, dy)
    return true, dx, dy
end

local function basename(path)
    if not path or path == "" then
        return ""
    end
    local len = #path
    local i = len
    while i > 0 do
        local b = string.byte(path, i)
        if b == 47 or b == 92 then
            return string.sub(path, i + 1)
        end
        i = i - 1
    end
    return path
end

local function trim_spaces(text)
    if not text then
        return ""
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    text = string.gsub(text, "%s+", " ")
    return text
end

local function normalize_taxiway_label(label)
    if not label or label == "" then
        return ""
    end
    local clean = string.upper(tostring(label))
    if string.sub(clean, 1, 3) == "RWY" then
        return ""
    end
    if clean == "RAMP" then
        return ""
    end
    clean = string.gsub(clean, "^TAXIWAY[%s_%-/]*", "")
    clean = string.gsub(clean, "^TWY[%s_%-/]*", "")
    clean = string.gsub(clean, "[_%-/]+", " ")
    clean = string.gsub(clean, "[^%w%s]+", "")
    clean = trim_spaces(clean)
    local parts = {}
    for part in clean:gmatch("%S+") do
        parts[#parts + 1] = part
    end
    if #parts == 2 and #parts[1] == 1 and #parts[2] >= 1 then
        clean = parts[2]
    end
    return clean
end

local function taxiway_label_voice(label)
    if not label or label == "" then
        return ""
    end
    local clean = tostring(label)
    clean = string.upper(clean)
    clean = trim_spaces(clean)
    if clean == "" then
        return ""
    end
    local all_alpha = true
    local len = #clean
    local i = 1
    while i <= len do
        local b = string.byte(clean, i)
        if b then
            local is_alpha = (b >= 65 and b <= 90)
            local is_digit = (b >= 48 and b <= 57)
            if not is_alpha and not is_digit then
                -- ignore separators
            elseif not is_alpha then
                all_alpha = false
            end
        end
        i = i + 1
    end
    if all_alpha and len > 2 then
        -- Speak full word (e.g. MAIN) instead of spelling.
        return clean
    end
    local nato = {
        A = "Alpha", B = "Bravo", C = "Charlie", D = "Delta", E = "Echo", F = "Foxtrot",
        G = "Golf", H = "Hotel", I = "India", J = "Juliet", K = "Kilo", L = "Lima",
        M = "Mike", N = "November", O = "Oscar", P = "Papa", Q = "Quebec", R = "Romeo",
        S = "Sierra", T = "Tango", U = "Uniform", V = "Victor", W = "Whiskey", X = "X-ray",
        Y = "Yankee", Z = "Zulu"
    }
    local words = {}
    i = 1
    while i <= len do
        local b = string.byte(clean, i)
        if b then
            if b >= 65 and b <= 90 then
                local ch = string.sub(clean, i, i)
                local w = nato[ch] or ch
                words[#words + 1] = w
            elseif b >= 48 and b <= 57 then
                words[#words + 1] = string.sub(clean, i, i)
            end
        end
        i = i + 1
    end
    return table.concat(words, " ")
end

local function runway_label_voice(label)
    if not label or label == "" then
        return "Runway"
    end
    local clean = string.upper(tostring(label))
    if string.sub(clean, 1, 3) == "RWY" then
        clean = trim_spaces(string.gsub(clean, "^RWY[%s_%-/]*", ""))
    end
    if clean == "" then
        return "Runway"
    end
    return "Runway " .. taxiway_label_voice(clean)
end

local function is_runway_label(label)
    if not label or label == "" then
        return false
    end
    return string.sub(label, 1, 3) == "RWY"
end

local function nearest_node_info(data, lat, lon, avoid_runway)
    if not data or not data.nodes or not is_valid_latlon(lat, lon) then
        return nil, nil
    end
    local best_id = nil
    local best_dist = nil
    for id, node in pairs(data.nodes) do
        if avoid_runway and data.runway_nodes and data.runway_nodes[id] then
            goto continue
        end
        if node and node.lat and node.lon then
            local d = distance_meters_latlon(lat, lon, node.lat, node.lon)
            if d and (not best_dist or d < best_dist) then
                best_dist = d
                best_id = id
            end
        end
        ::continue::
    end
    if not best_id or not best_dist then
        return nil, nil
    end
    return best_id, best_dist
end

local function nearest_non_runway_node(data, lat, lon)
    return nearest_node_info(data, lat, lon, true)
end

local function distance_sq(ax, ay, bx, by)
    local dx = (ax or 0) - (bx or 0)
    local dy = (ay or 0) - (by or 0)
    return dx * dx + dy * dy
end

local function point_segment_distance_sq(px, py, x1, y1, x2, y2)
    local vx = x2 - x1
    local vy = y2 - y1
    local wx = px - x1
    local wy = py - y1
    local c1 = wx * vx + wy * vy
    if c1 <= 0 then
        return distance_sq(px, py, x1, y1)
    end
    local c2 = vx * vx + vy * vy
    if c2 <= c1 then
        return distance_sq(px, py, x2, y2)
    end
    local b = c1 / c2
    local bx = x1 + b * vx
    local by = y1 + b * vy
    return distance_sq(px, py, bx, by)
end

local function project_point_to_segment(px, py, x1, y1, x2, y2)
    local vx = x2 - x1
    local vy = y2 - y1
    local len2 = vx * vx + vy * vy
    if len2 <= 0 then
        return x1, y1, 0
    end
    local t = ((px - x1) * vx + (py - y1) * vy) / len2
    if t < 0 then
        t = 0
    elseif t > 1 then
        t = 1
    end
    local bx = x1 + vx * t
    local by = y1 + vy * t
    return bx, by, t
end

local function clone_adjacency(src)
    local dst = {}
    for from, list in pairs(src or {}) do
        local copy = {}
        for i = 1, #list do
            copy[i] = list[i]
        end
        dst[from] = copy
    end
    return dst
end

local function adjacency_has_edge(adj, from_id, to_id)
    local list = adj and adj[from_id]
    if not list then
        return false
    end
    for _, edge in ipairs(list) do
        if edge.to == to_id then
            return true
        end
    end
    return false
end

local function add_adj_edge(adj, from_id, to_id, dist, label)
    if not adj then
        return
    end
    adj[from_id] = adj[from_id] or {}
    adj[from_id][#adj[from_id] + 1] = { to = to_id, dist = dist, label = label }
end

local function find_nearest_edge_projection(data, east, north, opts)
    if not data or not data.edges or not data.nodes then
        return nil
    end
    local disallow_runway = opts and opts.disallow_runway_edges
    local best = nil
    for _, edge in ipairs(data.edges) do
        local n1 = data.nodes[edge.from]
        local n2 = data.nodes[edge.to]
        if n1 and n2 then
            if disallow_runway and edge.label and string.sub(edge.label, 1, 3) == "RWY" then
                goto continue
            end
            local px, py, t = project_point_to_segment(east, north, n1.east, n1.north, n2.east, n2.north)
            local d2 = distance_sq(east, north, px, py)
            if not best or d2 < best.d2 then
                best = {
                    edge = edge,
                    proj_east = px,
                    proj_north = py,
                    t = t,
                    d2 = d2
                }
            end
        end
        ::continue::
    end
    return best
end


local function find_heading_edge_projection(data, east, north, heading_deg, opts)
    if not data or not data.edges or not data.nodes then
        return nil
    end
    local heading = tonumber(heading_deg)
    if not heading then
        return nil
    end
    local disallow_runway = opts and opts.disallow_runway_edges
    local radius = (opts and opts.radius_m) or 150
    local angle_deg = (opts and opts.angle_deg) or 60
    local radius2 = radius * radius
    local cos_tol = math.cos(math.rad(angle_deg))
    local rad = math.rad(heading % 360)
    local dir_e = math.sin(rad)
    local dir_n = math.cos(rad)
    local best = nil
    for _, edge in ipairs(data.edges) do
        local n1 = data.nodes[edge.from]
        local n2 = data.nodes[edge.to]
        if n1 and n2 then
            if disallow_runway and edge.label and string.sub(edge.label, 1, 3) == "RWY" then
                goto continue
            end
            local px, py, t = project_point_to_segment(east, north, n1.east, n1.north, n2.east, n2.north)
            local d2 = distance_sq(east, north, px, py)
            if d2 <= radius2 then
                local vx = px - east
                local vy = py - north
                local v2 = vx * vx + vy * vy
                local ok = false
                if v2 <= 1e-6 then
                    ok = true
                else
                    local inv_len = 1 / math.sqrt(v2)
                    local dot = math.abs((vx * dir_e + vy * dir_n) * inv_len)
                    ok = (dot >= cos_tol)
                end
                if ok and (not best or d2 < best.d2) then
                    best = {
                        edge = edge,
                        proj_east = px,
                        proj_north = py,
                        t = t,
                        d2 = d2
                    }
                end
            end
        end
        ::continue::
    end
    return best
end

local function find_preferred_edge_projection(data, east, north, opts)
    if not data or not data.edges or not data.nodes then
        return nil
    end
    local disallow_runway = opts and opts.disallow_runway_edges
    local radius = (opts and opts.radius_m) or 140
    local radius2 = radius * radius
    local label_len = {}
    local best_by_label = {}
    for _, edge in ipairs(data.edges) do
        local n1 = data.nodes[edge.from]
        local n2 = data.nodes[edge.to]
        if n1 and n2 then
            if disallow_runway and edge.label and string.sub(edge.label, 1, 3) == "RWY" then
                goto continue
            end
            local px, py, t = project_point_to_segment(east, north, n1.east, n1.north, n2.east, n2.north)
            local d2 = distance_sq(east, north, px, py)
            if d2 <= radius2 then
                local lbl = normalize_taxiway_label(edge.label or "")
                if lbl ~= "" then
                    local dx = n2.east - n1.east
                    local dy = n2.north - n1.north
                    local len = math.sqrt(dx * dx + dy * dy)
                    label_len[lbl] = (label_len[lbl] or 0) + len
                    local best = best_by_label[lbl]
                    if not best or d2 < best.d2 then
                        best_by_label[lbl] = {
                            edge = edge,
                            proj_east = px,
                            proj_north = py,
                            t = t,
                            d2 = d2
                        }
                    end
                end
            end
        end
        ::continue::
    end
    local best_label = nil
    local best_len = nil
    for lbl, len in pairs(label_len) do
        if not best_len or len > best_len then
            best_len = len
            best_label = lbl
        end
    end
    if best_label and best_by_label[best_label] then
        return best_by_label[best_label]
    end
    return nil
end

local function build_projected_data(data, start_proj, end_proj, waypoint_projs)
    if not start_proj and not end_proj and (not waypoint_projs or #waypoint_projs == 0) then
        return data, nil, nil, {}
    end
    local nodes = {}
    for id, node in pairs(data.nodes or {}) do
        nodes[id] = node
    end
    local adjacency = clone_adjacency(data.adjacency)
    local adjacency_any = clone_adjacency(data.adjacency_any)
    local adjacency_relaxed = clone_adjacency(data.adjacency_relaxed)
    local adjacency_any_relaxed = clone_adjacency(data.adjacency_any_relaxed)
    local runway_nodes = {}
    for k, v in pairs(data.runway_nodes or {}) do
        runway_nodes[k] = v
    end

    local function add_projection(proj, id)
        if not proj or not proj.edge then
            return
        end
        local edge = proj.edge
        local n1 = data.nodes[edge.from]
        local n2 = data.nodes[edge.to]
        if not (n1 and n2) then
            return
        end
        local ex = proj.proj_east
        local ny = proj.proj_north
        local lat, lon = sasl.localToWorld(ex, 0, -ny)
        nodes[id] = { east = ex, north = ny, x = ex, z = -ny, lat = lat, lon = lon }
        if edge.label and string.sub(edge.label, 1, 3) == "RWY" then
            runway_nodes[id] = true
        end
        local d1 = math.sqrt(distance_sq(n1.east, n1.north, ex, ny))
        local d2 = math.sqrt(distance_sq(n2.east, n2.north, ex, ny))
        local label = edge.label

        local fwd = adjacency_has_edge(data.adjacency, edge.from, edge.to)
        local rev = adjacency_has_edge(data.adjacency, edge.to, edge.from)
        if fwd then
            add_adj_edge(adjacency, edge.from, id, d1, label)
            add_adj_edge(adjacency, id, edge.to, d2, label)
        end
        if rev then
            add_adj_edge(adjacency, edge.to, id, d2, label)
            add_adj_edge(adjacency, id, edge.from, d1, label)
        end
        add_adj_edge(adjacency_any, edge.from, id, d1, label)
        add_adj_edge(adjacency_any, id, edge.to, d2, label)
        add_adj_edge(adjacency_any, edge.to, id, d2, label)
        add_adj_edge(adjacency_any, id, edge.from, d1, label)

        local rfwd = adjacency_has_edge(data.adjacency_relaxed, edge.from, edge.to)
        local rrev = adjacency_has_edge(data.adjacency_relaxed, edge.to, edge.from)
        if rfwd then
            add_adj_edge(adjacency_relaxed, edge.from, id, d1, label)
            add_adj_edge(adjacency_relaxed, id, edge.to, d2, label)
        end
        if rrev then
            add_adj_edge(adjacency_relaxed, edge.to, id, d2, label)
            add_adj_edge(adjacency_relaxed, id, edge.from, d1, label)
        end
        add_adj_edge(adjacency_any_relaxed, edge.from, id, d1, label)
        add_adj_edge(adjacency_any_relaxed, id, edge.to, d2, label)
        add_adj_edge(adjacency_any_relaxed, edge.to, id, d2, label)
        add_adj_edge(adjacency_any_relaxed, id, edge.from, d1, label)
    end

    local start_id = start_proj and "__taxi_start_proj" or nil
    local end_id = end_proj and "__taxi_end_proj" or nil
    if start_id and end_id and start_id == end_id then
        end_id = "__taxi_end_proj2"
    end
    add_projection(start_proj, start_id)
    add_projection(end_proj, end_id)

    local waypoint_ids = {}
    if waypoint_projs and #waypoint_projs > 0 then
        for i, proj in ipairs(waypoint_projs) do
            local wp_id = "__taxi_wp_" .. tostring(i)
            add_projection(proj, wp_id)
            waypoint_ids[i] = wp_id
        end
    end

    return {
        nodes = nodes,
        edges = data.edges,
        ramps = data.ramps,
        runways = data.runways,
        polygons = data.polygons,
        bounds = data.bounds,
        adjacency = adjacency,
        adjacency_any = adjacency_any,
        adjacency_relaxed = adjacency_relaxed,
        adjacency_any_relaxed = adjacency_any_relaxed,
        runway_nodes = runway_nodes,
        has_routes = data.has_routes,
        has_fallback = data.has_fallback,
        route_source = data.route_source,
        can_route = data.can_route,
        route_cache = {}
    }, start_id, end_id, waypoint_ids
end

local function distance_to_route(data, path, east, north)
    if not data or not data.nodes or not path or #path < 2 then
        return nil
    end
    local best = nil
    for i = 1, #path - 1 do
        local n1 = data.nodes[path[i]]
        local n2 = data.nodes[path[i + 1]]
        if n1 and n2 then
            local d2 = point_segment_distance_sq(east, north, n1.east, n1.north, n2.east, n2.north)
            if not best or d2 < best then
                best = d2
            end
        end
    end
    if not best then
        return nil
    end
    return math.sqrt(best)
end

local function distance_to_segments(segments, east, north)
    if not segments or #segments == 0 then
        return nil
    end
    local best = nil
    for _, seg in ipairs(segments) do
        local d2 = point_segment_distance_sq(
            east, north,
            seg.east1 or 0, seg.north1 or 0,
            seg.east2 or 0, seg.north2 or 0
        )
        if not best or d2 < best then
            best = d2
        end
    end
    if not best then
        return nil
    end
    return math.sqrt(best)
end

local function normalize_runway_name(name)
    local text = tostring(name or "")
    text = helpers.forceCleanString(text)
    text = helpers.cleanstring(text)
    text = string.upper(text)
    text = string.gsub(text, "^RWY", "")
    text = string.gsub(text, "%s+", "")
    return text
end

local function parse_runway_parts(name)
    local clean = normalize_runway_name(name)
    if clean == "" then
        return nil, ""
    end
    local len = #clean
    local i = 1
    while i <= len do
        local b = string.byte(clean, i)
        if not b or b < 48 or b > 57 then
            break
        end
        i = i + 1
    end
    if i == 1 then
        return nil, ""
    end
    local num = string.sub(clean, 1, i - 1)
    local suffix = ""
    local j = len
    while j >= 1 do
        local b = string.byte(clean, j)
        local is_alpha = (b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122)))
        if not is_alpha then
            break
        end
        j = j - 1
    end
    if j < len then
        suffix = string.sub(clean, j + 1, len)
    end
    return tonumber(num), suffix
end

local function find_runway_entry(data, runway_name, runway_lat, runway_lon)
    if not data or not data.runways or not runway_name then
        return nil
    end
    local target = normalize_runway_name(runway_name)
    if target == "" then
        return nil
    end
    for _, rwy in ipairs(data.runways) do
        if normalize_runway_name(rwy.rwy1) == target then
            return rwy, 1
        end
        if normalize_runway_name(rwy.rwy2) == target then
            return rwy, 2
        end
    end
    local target_num = parse_runway_parts(target)
    if not target_num then
        return nil
    end
    local candidates = {}
    for _, rwy in ipairs(data.runways) do
        local num1 = parse_runway_parts(rwy.rwy1)
        if num1 and num1 == target_num then
            candidates[#candidates + 1] = { rwy = rwy, side = 1 }
        end
        local num2 = parse_runway_parts(rwy.rwy2)
        if num2 and num2 == target_num then
            candidates[#candidates + 1] = { rwy = rwy, side = 2 }
        end
    end
    if #candidates == 0 then
        return nil
    end
    if #candidates == 1 then
        return candidates[1].rwy, candidates[1].side
    end
    if runway_lat and runway_lon then
        local best = nil
        local best_d2 = nil
        for _, cand in ipairs(candidates) do
            local rwy = cand.rwy
            local lat = cand.side == 1 and rwy.lat1 or rwy.lat2
            local lon = cand.side == 1 and rwy.lon1 or rwy.lon2
            if lat and lon then
                local dlat = lat - runway_lat
                local dlon = lon - runway_lon
                local d2 = dlat * dlat + dlon * dlon
                if not best_d2 or d2 < best_d2 then
                    best_d2 = d2
                    best = cand
                end
            end
        end
        if best then
            return best.rwy, best.side
        end
    end
    return candidates[1].rwy, candidates[1].side
end

local function compute_runway_landing_profile(data, runway_name, runway_lat, runway_lon)
    local rwy, side = find_runway_entry(data, runway_name, runway_lat, runway_lon)
    if not rwy or not rwy.east1 or not rwy.north1 or not rwy.east2 or not rwy.north2 then
        return nil
    end
    local sx, sy = rwy.east1, rwy.north1
    local ex, ey = rwy.east2, rwy.north2
    if side == 2 then
        sx, sy = rwy.east2, rwy.north2
        ex, ey = rwy.east1, rwy.north1
    end
    local dx = ex - sx
    local dy = ey - sy
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 1 then
        return nil
    end
    local roll = math.min(len * 0.4, 1200)
    local minRoll = math.min(300, len * 0.3)
    if roll < minRoll then
        roll = minRoll
    end
    local maxRoll = len * 0.9
    if roll > maxRoll then
        roll = maxRoll
    end
    local ux = dx / len
    local uy = dy / len
    local tx = sx + ux * roll
    local ty = sy + uy * roll
    return {
        threshold = { east = sx, north = sy },
        axis = { x = ux, y = uy },
        length = len,
        width = rwy.width or 0,
        roll = roll,
        touchdown = { east = tx, north = ty }
    }
end

local function find_nearest_runway_node(data, east, north)
    if not data or not data.nodes or not data.runway_nodes then
        return nil
    end
    local best_id = nil
    local best_d2 = nil
    for id, node in pairs(data.nodes) do
        if data.runway_nodes[id] and node.east and node.north then
            local dx = node.east - east
            local dy = node.north - north
            local d2 = dx * dx + dy * dy
            if not best_d2 or d2 < best_d2 then
                best_d2 = d2
                best_id = id
            end
        end
    end
    return best_id
end

local function find_holdshort_node_near(data, runway_lat, runway_lon)
    if not data or not is_valid_latlon(runway_lat, runway_lon) then
        return nil
    end
    local re, rn = latlon_to_local(runway_lat, runway_lon)
    if not re or not rn then
        return nil
    end
    local rwy_node_id = find_nearest_runway_node(data, re, rn)
    if not rwy_node_id then
        return nil
    end
    local adj = data.adjacency_any or data.adjacency or {}
    local neighbors = adj[rwy_node_id] or {}
    local best_id = nil
    local best_d2 = nil
    for _, edge in ipairs(neighbors) do
        local nid = edge.to
        if nid and (not (data.runway_nodes and data.runway_nodes[nid])) then
            local node = data.nodes and data.nodes[nid] or nil
            if node and node.east and node.north then
                local dx = node.east - re
                local dy = node.north - rn
                local d2 = dx * dx + dy * dy
                if (not best_d2) or d2 < best_d2 then
                    best_d2 = d2
                    best_id = nid
                end
            end
        end
    end
    return best_id
end

local function build_runway_backtrack_segments(data, profile, node_id, target_point)
    if not data or not profile or not node_id then
        return nil
    end
    local node = data.nodes and data.nodes[node_id]
    if not node or not node.east or not node.north then
        return nil
    end
    local axis = profile.axis
    local threshold = profile.threshold
    local target = target_point or threshold
    if not axis or not threshold then
        return nil
    end
    if not target or target.east == nil or target.north == nil then
        target = threshold
    end
    local dx = node.east - threshold.east
    local dy = node.north - threshold.north
    local along = dx * axis.x + dy * axis.y
    local cross = dx * axis.y - dy * axis.x
    local perp = math.abs(cross)
    if along < 60 then
        return nil
    end
    if perp > 120 then
        return nil
    end
    local length = profile.length or along
    local along_clamped = along
    if along_clamped < 0 then
        along_clamped = 0
    elseif along_clamped > length then
        along_clamped = length
    end
    local entry_east = threshold.east + axis.x * along_clamped
    local entry_north = threshold.north + axis.y * along_clamped
    local segments = {}
    if math.sqrt(distance_sq(node.east, node.north, entry_east, entry_north)) > 8 then
        segments[#segments + 1] = {
            east1 = node.east,
            north1 = node.north,
            east2 = entry_east,
            north2 = entry_north
        }
    end
    segments[#segments + 1] = {
        east1 = entry_east,
        north1 = entry_north,
        east2 = target.east,
        north2 = target.north
    }
    return segments
end

local collect_runway_exit_candidates

local function compute_along_perp(profile, node)
    if not profile or not profile.threshold or not profile.axis or not node or not node.east or not node.north then
        return nil, nil
    end
    local dx = node.east - profile.threshold.east
    local dy = node.north - profile.threshold.north
    local along = dx * profile.axis.x + dy * profile.axis.y
    local cross = dx * profile.axis.y - dy * profile.axis.x
    local perp = math.abs(cross)
    return along, perp
end

local function runway_corridor_half_width(profile)
    local width = tonumber(profile and profile.width) or 0
    local half = 0
    if width > 0 then
        half = (width * 0.5) + depRunwayCorridorBuffer
    else
        half = 35
    end
    if half < depRunwayCorridorMin then
        half = depRunwayCorridorMin
    end
    if depRunwayCorridorMax and half > depRunwayCorridorMax then
        half = depRunwayCorridorMax
    end
    return half
end

local function compute_dep_threshold_state(comp, profile, runway_lat, runway_lon, aircraft)
    if not profile or not profile.threshold or not profile.axis then
        return nil
    end
    if not aircraft or aircraft.east == nil or aircraft.north == nil then
        return nil
    end
    local along, perp = compute_along_perp(profile, aircraft)
    if not along or not perp then
        return nil
    end
    local corridor = runway_corridor_half_width(profile)
    local dist = math.sqrt(distance_sq(aircraft.east, aircraft.north, profile.threshold.east, profile.threshold.north))
    local axis_heading_true = math.deg(math.atan2(profile.axis.x, profile.axis.y))
    if axis_heading_true < 0 then
        axis_heading_true = axis_heading_true + 360
    end
    local mag_var = nil
    if aircraft.lat and aircraft.lon then
        mag_var = sasl.getMagneticVariation(aircraft.lat, aircraft.lon)
    end
    if (mag_var == nil) and runway_lat and runway_lon then
        mag_var = sasl.getMagneticVariation(runway_lat, runway_lon)
    end
    mag_var = mag_var or 0
    local axis_heading_mag = (axis_heading_true - mag_var + 360) % 360
    local yal = comp and (comp.yal or _G.yal) or nil
    local track_mag = yal and yal.groundtrackmag and get(yal.groundtrackmag) or nil
    local heading_diff = nil
    local heading_ok = false
    if track_mag ~= nil then
        heading_diff = helpers.headingdiff(track_mag, axis_heading_mag)
        heading_ok = heading_diff <= depThresholdHeadingLimit
    end
    local reached = (perp <= corridor) and heading_ok and (dist <= depThresholdGateMeters)
    return {
        reached = reached,
        dist = dist,
        perp = perp,
        corridor = corridor,
        heading_diff = heading_diff,
        axis_heading_mag = axis_heading_mag
    }
end


local function select_runway_exit_node(data, profile)
    if not data or not profile or not profile.touchdown or not profile.axis then
        return nil, false
    end
    local function exit_turn_ok(node_id)
        if not data.nodes or not data.adjacency_any then
            return true
        end
        local node = data.nodes[node_id]
        if not node or not node.east or not node.north then
            return true
        end
        local max_turn = 120
        local axis = profile.axis
        local best_angle = nil
        local neighbors = data.adjacency_any[node_id] or {}
        for _, edge in ipairs(neighbors) do
            local to_id = edge.to
            if to_id and data.nodes[to_id] then
                if data.runway_nodes and data.runway_nodes[to_id] then
                    goto continue
                end
                if edge.label and is_runway_label(edge.label) then
                    goto continue
                end
                local n2 = data.nodes[to_id]
                if n2.east and n2.north then
                    local vx = n2.east - node.east
                    local vy = n2.north - node.north
                    local vlen = math.sqrt(vx * vx + vy * vy)
                    if vlen > 0.1 then
                        local dot = (axis.x * vx + axis.y * vy) / vlen
                        if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
                        local angle = math.deg(math.acos(dot))
                        if not best_angle or angle < best_angle then
                            best_angle = angle
                        end
                    end
                end
            end
            ::continue::
        end
        if best_angle and best_angle > max_turn then
            return false
        end
        return true
    end

    local td = profile.touchdown
    local candidates = collect_runway_exit_candidates(data, td.east, td.north, 32)
    if #candidates == 0 then
        return find_nearest_runway_node(data, td.east, td.north), true
    end
    local rollout = profile.roll or 0
    local tol = 80
    local length = profile.length or 0
    local width = profile.width or 0
    local perp_limit = math.max(180, width * 4)
    local best_forward = nil
    local best_forward_cost = nil
    local best_back = nil
    local best_back_along = nil
    for _, cand in ipairs(candidates) do
        local node = data.nodes[cand.id]
        if node and node.east and node.north then
            local dx = node.east - profile.threshold.east
            local dy = node.north - profile.threshold.north
            local along = dx * profile.axis.x + dy * profile.axis.y
            local cross = dx * profile.axis.y - dy * profile.axis.x
            local perp = math.abs(cross)
            if not exit_turn_ok(cand.id) then
                goto continue
            end
            -- Only consider exits that are plausibly on/near the selected runway.
            if length > 0 then
                if along < -100 or along > (length + 150) then
                    goto continue
                end
            end
            if perp > perp_limit then
                goto continue
            end
            if along >= (rollout - tol) then
                local cost = math.abs(along - rollout)
                if not best_forward_cost or cost < best_forward_cost then
                    best_forward_cost = cost
                    best_forward = cand.id
                end
            else
                if not best_back_along or along > best_back_along then
                    best_back_along = along
                    best_back = cand.id
                end
            end
        end
        ::continue::
    end
    if best_forward then
        return best_forward, false
    end
    if best_back then
        return best_back, true
    end
    return find_nearest_runway_node(data, td.east, td.north), true
end

collect_runway_exit_candidates = function(data, ref_east, ref_north, max_candidates)
    if not data or not data.runway_nodes or not data.nodes then
        return {}
    end
    local adj = data.adjacency_any or data.adjacency or {}
    local candidates = {}
    local seen = {}
    for rwy_id, _ in pairs(data.runway_nodes) do
        local neighbors = adj[rwy_id]
        if neighbors then
            for _, edge in ipairs(neighbors) do
                local nid = edge.to
                if nid and (not data.runway_nodes[nid]) and (not seen[nid]) then
                    local node = data.nodes[nid]
                    if node and node.east and node.north then
                        local dx = node.east - ref_east
                        local dy = node.north - ref_north
                        local d2 = dx * dx + dy * dy
                        candidates[#candidates + 1] = { id = nid, d2 = d2 }
                        seen[nid] = true
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return (a.d2 or 0) < (b.d2 or 0) end)
    if max_candidates and #candidates > max_candidates then
        for i = max_candidates + 1, #candidates do
            candidates[i] = nil
        end
    end
    return candidates
end

local function copy_opts(opts)
    if not opts then
        return nil
    end
    local out = {}
    for k, v in pairs(opts) do
        out[k] = v
    end
    return out
end

local function route_with_waypoints(icao, start_lat, start_lon, end_lat, end_lon, opts, waypoint_ids, waypoints)
    if not waypoint_ids or #waypoint_ids == 0 then
        return helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
    end
    local data = opts and opts.data or nil
    if not data then
        return helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
    end
    local full_path = {}
    local bounds = { minX = nil, maxX = nil, minY = nil, maxY = nil }
    local function append_path(path)
        for i = 1, #path do
            local node_id = path[i]
            if #full_path == 0 or full_path[#full_path] ~= node_id then
                full_path[#full_path + 1] = node_id
            end
        end
    end
    local function update_bounds_for_path(path)
        for _, node_id in ipairs(path) do
            local node = data.nodes and data.nodes[node_id]
            if node and node.east and node.north then
                update_bounds(bounds, node.east, node.north)
            end
        end
    end
    local prev_end_id = nil
    local total_legs = #waypoint_ids + 1
    for leg = 1, total_legs do
        local leg_opts = copy_opts(opts) or {}
        leg_opts.data = data
        if prev_end_id then
            leg_opts.start_node_id = prev_end_id
        end
        if leg <= #waypoint_ids then
            leg_opts.end_node_id = waypoint_ids[leg]
        end
        local leg_end_lat = end_lat
        local leg_end_lon = end_lon
        if leg <= #waypoint_ids then
            local wp = waypoints and waypoints[leg]
            if wp and is_valid_latlon(wp.lat, wp.lon) then
                leg_end_lat = wp.lat
                leg_end_lon = wp.lon
            end
        end
        local route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, leg_end_lat, leg_end_lon, leg_opts)
        if not route then
            return nil, rerr
        end
        append_path(route.path or {})
        update_bounds_for_path(route.path or {})
        prev_end_id = route.end_id
    end
    if #full_path == 0 then
        return nil, "no-path"
    end
    return {
        data = data,
        start_id = full_path[1],
        end_id = full_path[#full_path],
        path = full_path,
        bounds = bounds
    }
end

local function try_route_from_candidates(icao, data, end_lat, end_lon, candidates, opts, waypoint_ids, waypoints)
    for _, cand in ipairs(candidates or {}) do
        local node = data.nodes[cand.id]
        if node and is_valid_latlon(node.lat, node.lon) then
            local local_opts = copy_opts(opts) or {}
            local_opts.start_node_id = cand.id
            local route, rerr = route_with_waypoints(icao, node.lat, node.lon, end_lat, end_lon, local_opts, waypoint_ids, waypoints)
            if route then
                return route, nil, node.lat, node.lon
            end
        end
    end
    return nil, "no-path"
end

local function try_route_to_candidates(icao, data, start_lat, start_lon, candidates, opts, waypoint_ids, waypoints)
    for _, cand in ipairs(candidates or {}) do
        local node = data.nodes[cand.id]
        if node and is_valid_latlon(node.lat, node.lon) then
            local local_opts = copy_opts(opts) or {}
            local_opts.end_node_id = cand.id
            local route, rerr = route_with_waypoints(icao, start_lat, start_lon, node.lat, node.lon, local_opts, waypoint_ids, waypoints)
            if route then
                return route, nil, node.lat, node.lon
            end
        end
    end
    return nil, "no-path"
end

local function collect_nearest_nodes(data, ref_east, ref_north, max_candidates)
    if not data or not data.nodes then
        return {}
    end
    local candidates = {}
    for id, node in pairs(data.nodes) do
        if node and node.east and node.north then
            if not (data.runway_nodes and data.runway_nodes[id]) and not node.is_ramp then
                local dx = node.east - ref_east
                local dy = node.north - ref_north
                local d2 = dx * dx + dy * dy
                candidates[#candidates + 1] = { id = id, d2 = d2 }
            end
        end
    end
    table.sort(candidates, function(a, b) return (a.d2 or 0) < (b.d2 or 0) end)
    if max_candidates and #candidates > max_candidates then
        for i = max_candidates + 1, #candidates do
            candidates[i] = nil
        end
    end
    return candidates
end

local function normalize_icao(value)
    local text = tostring(value or "")
    text = helpers.forceCleanString(text)
    text = helpers.cleanstring(text)
    text = string.upper(text)
    if #text > 4 then
        text = string.sub(text, 1, 4)
    end
    return text
end

local function build_route_labels(data, path)
    local labels = {}
    if not data or not data.adjacency or not path then
        return labels
    end
    for i = 1, #path - 1 do
        local from_id = path[i]
        local to_id = path[i + 1]
        local neighbors = data.adjacency[from_id] or {}
        for _, edge in ipairs(neighbors) do
            if edge.to == to_id and edge.label and edge.label ~= "" then
                if labels[#labels] ~= edge.label then
                    labels[#labels + 1] = edge.label
                end
                break
            end
        end
    end
    return labels
end

local function clamp(value, minVal, maxVal)
    if value < minVal then return minVal end
    if value > maxVal then return maxVal end
    return value
end

local function heading_deg_from_to(e1, n1, e2, n2)
    if e1 == nil or n1 == nil or e2 == nil or n2 == nil then
        return nil
    end
    local dx = e2 - e1
    local dy = n2 - n1
    if dx == 0 and dy == 0 then
        return nil
    end
    local h = math.deg(math.atan2(dx, dy))
    if h < 0 then
        h = h + 360
    end
    return h
end

local function heading_diff_deg(h1, h2)
    if h1 == nil or h2 == nil then
        return 0
    end
    local d = math.abs(h1 - h2) % 360
    if d > 180 then
        d = 360 - d
    end
    return d
end

local function node_degree(data, node_id)
    if not data or not node_id then
        return 0
    end
    local adj = data.adjacency_any or data.adjacency
    local edges = adj and adj[node_id] or nil
    return edges and #edges or 0
end

local function insert_waypoint_sorted(route_waypoints, wp)
    if not route_waypoints then
        return 1
    end
    local insert_at = #route_waypoints + 1
    if wp.segment_idx then
        for idx, existing in ipairs(route_waypoints) do
            if existing.segment_idx and existing.segment_idx > wp.segment_idx then
                insert_at = idx
                break
            end
        end
    end
    table.insert(route_waypoints, insert_at, wp)
    return insert_at
end

local function build_edit_handles(comp, start_lat, start_lon, end_lat, end_lon)
    comp._editHandles = {}
    local handles = comp._editHandles
    local route = comp._route
    if not route or not route.path or not route.data then
        return
    end
    local data = route.data
    local path = route.path
    local suppressed = comp._editSuppressedNodes or {}
    local merge_d2 = editHandleMergeMeters * editHandleMergeMeters

    local function find_near_handle(east, north)
        for idx, handle in ipairs(handles) do
            if handle and handle.east ~= nil and handle.north ~= nil then
                local dx = handle.east - east
                local dy = handle.north - north
                if (dx * dx + dy * dy) <= merge_d2 then
                    return idx
                end
            end
        end
        return nil
    end

    local function add_handle(kind, east, north, lat, lon, segment_idx, node_id, wp_idx)
        if east == nil or north == nil then
            return nil
        end
        local existing = find_near_handle(east, north)
        if existing then
            local handle = handles[existing]
            if kind == "manual" and handle.kind ~= "start" and handle.kind ~= "end" then
                handle.kind = "manual"
                handle.wp_idx = wp_idx
                handle.segment_idx = segment_idx or handle.segment_idx
            end
            return existing
        end
        handles[#handles + 1] = {
            kind = kind,
            east = east,
            north = north,
            lat = lat,
            lon = lon,
            segment_idx = segment_idx,
            node_id = node_id,
            wp_idx = wp_idx
        }
        return #handles
    end

    if is_valid_latlon(start_lat, start_lon) then
        local sx, sy = latlon_to_local(start_lat, start_lon)
        add_handle("start", sx, sy, start_lat, start_lon, 1, path[1], nil)
    end
    if is_valid_latlon(end_lat, end_lon) then
        local ex, ey = latlon_to_local(end_lat, end_lon)
        add_handle("end", ex, ey, end_lat, end_lon, #path, path[#path], nil)
    end

    if #path >= 3 then
        for i = 2, #path - 1 do
            local node_id = path[i]
            if node_id and not suppressed[node_id] then
                local cur = data.nodes and data.nodes[node_id]
                if cur and cur.east ~= nil and cur.north ~= nil then
                    local add = false
                    if node_degree(data, node_id) >= 3 then
                        add = true
                    end
                    local prev = data.nodes[path[i - 1]]
                    local nxt = data.nodes[path[i + 1]]
                    if prev and nxt and prev.east ~= nil and prev.north ~= nil and nxt.east ~= nil and nxt.north ~= nil then
                        local h1 = heading_deg_from_to(prev.east, prev.north, cur.east, cur.north)
                        local h2 = heading_deg_from_to(cur.east, cur.north, nxt.east, nxt.north)
                        if heading_diff_deg(h1, h2) >= editDecisionAngle then
                            add = true
                        end
                    end
                    if add then
                        add_handle("auto", cur.east, cur.north, cur.lat, cur.lon, i, node_id, nil)
                    end
                end
            end
        end
    end

    if comp._routeWaypoints and #comp._routeWaypoints > 0 then
        for idx, wp in ipairs(comp._routeWaypoints) do
            local skip = waypoint_matches_override(wp, comp._editStartOverride)
                or waypoint_matches_override(wp, comp._editEndOverride)
            if not skip then
                local we = wp.east
                local wn = wp.north
                if (we == nil or wn == nil) and is_valid_latlon(wp.lat, wp.lon) then
                    we, wn = latlon_to_local(wp.lat, wp.lon)
                end
                if we ~= nil and wn ~= nil then
                    add_handle("manual", we, wn, wp.lat, wp.lon, wp.segment_idx, nil, idx)
                end
            end
        end
    end

    local total = #handles
    local auto_count = 0
    local manual_count = 0
    local start_count = 0
    local end_count = 0
    for _, h in ipairs(handles) do
        if h.kind == "auto" then
            auto_count = auto_count + 1
        elseif h.kind == "manual" then
            manual_count = manual_count + 1
        elseif h.kind == "start" then
            start_count = start_count + 1
        elseif h.kind == "end" then
            end_count = end_count + 1
        end
    end
    local suppressed = 0
    if comp._editSuppressedNodes then
        for _ in pairs(comp._editSuppressedNodes) do
            suppressed = suppressed + 1
        end
    end
    local key = string.format(
        "%d|%d|%d|%d|%d|%d",
        #path,
        total,
        auto_count,
        manual_count,
        start_count + end_count,
        suppressed
    )
    if comp._lastEditHandleKey ~= key then
        comp._lastEditHandleKey = key
        log_taxi(
            string.format(
                "TaxiEdit: handles path=%d total=%d auto=%d manual=%d start=%d end=%d suppressed=%d",
                #path,
                total,
                auto_count,
                manual_count,
                start_count,
                end_count,
                suppressed
            )
        )
    end
end

local function mark_edit_dirty(comp)
    local was_dirty = comp._editDirty
    comp._editDirty = true
    comp._lastStartKey = nil
    comp._lastEndKey = nil
    comp._lastUpdate = nil
    if not was_dirty then
        log_taxi("TaxiEdit: dirty")
    end
end

local function getFont(comp)
    if comp._fontHandle then
        return comp._fontHandle
    end
    local font = nil
    if def and def.wFont then
        font = def.wFont
    end
    if not font then
        font = sasl.gl.loadFont("DejaVuSansMono.ttf")
    end
    comp._fontHandle = font
    return font
end

local function drawText(font, x, y, text, size, align, color)
    sasl.gl.drawText(font, x, y, tostring(text or ""), size or 12, false, false, align or TEXT_ALIGN_LEFT, color or {1, 1, 1, 1})
end

local function log_full_route_state(comp, data, mode, icao, vals)
    local function fmt_latlon(latv, lonv)
        if not latv or not lonv then
            return "nil/nil"
        end
        return string.format("%.6f/%.6f", tonumber(latv) or 0, tonumber(lonv) or 0)
    end
    local function fmt_local(x, y)
        if x == nil or y == nil then
            return "nil/nil"
        end
        return string.format("%.1f/%.1f", tonumber(x) or 0, tonumber(y) or 0)
    end
    local function fmt_node_latlon(node_id)
        if not node_id or not data or not data.nodes then
            return "nil"
        end
        local n = data.nodes[node_id]
        if not n then
            return tostring(node_id) .. ":?"
        end
        return tostring(node_id) .. ":" .. fmt_latlon(n.lat, n.lon)
    end

    local modeLabel = (mode == 1) and "ARR" or "DEP"
    helpers.logInfoTS("TaxiFull: ---- " .. tostring(icao) .. " " .. modeLabel .. " ----")
    helpers.logInfoTS("TaxiFull: runway raw=" .. tostring(vals.raw_dep or vals.raw_arr or "") .. " resolved=" .. tostring(vals.runway_name))
    helpers.logInfoTS("TaxiFull: runwayLatLon=" .. fmt_latlon(vals.runway_lat, vals.runway_lon) .. " chosen=" .. fmt_latlon(vals.chosen_lat, vals.chosen_lon))
    if vals.rwy1 or vals.rwy2 then
        helpers.logInfoTS("TaxiFull: rwy entry rwy1=" .. tostring(vals.rwy1) .. " rwy2=" .. tostring(vals.rwy2) .. " side=" .. tostring(vals.rwy_side))
    end
    if vals.rwy_entry_lat and vals.rwy_entry_lon then
        helpers.logInfoTS("TaxiFull: rwy entry latlon=" .. fmt_latlon(vals.rwy_entry_lat, vals.rwy_entry_lon) .. " d_to_ref_m=" .. tostring(vals.rwy_entry_dist_m or "?"))
    end
    helpers.logInfoTS("TaxiFull: aircraft latlon=" .. fmt_latlon(vals.aircraft_lat, vals.aircraft_lon))
    helpers.logInfoTS("TaxiFull: aircraft local=" .. fmt_local(vals.aircraft_east, vals.aircraft_north) .. " worldToLocal=" .. fmt_local(vals.aircraft_wtl_e, vals.aircraft_wtl_n))
    helpers.logInfoTS("TaxiFull: start=" .. fmt_latlon(vals.start_lat, vals.start_lon) .. " end=" .. fmt_latlon(vals.end_lat, vals.end_lon))
    helpers.logInfoTS("TaxiFull: nodes start=" .. fmt_node_latlon(vals.start_node_id) .. " d=" .. tostring(vals.start_node_dist or "?") ..
        " end=" .. fmt_node_latlon(vals.end_node_id) .. " d=" .. tostring(vals.end_node_dist or "?"))
    if vals.start_non_runway_node_id then
        helpers.logInfoTS("TaxiFull: start non-rwy=" .. fmt_node_latlon(vals.start_non_runway_node_id) .. " d=" .. tostring(vals.start_non_runway_node_dist or "?"))
    end
    if vals.dep_holdshort_id then
        helpers.logInfoTS("TaxiFull: dep holdshort=" .. fmt_node_latlon(vals.dep_holdshort_id) .. " d_rwy_m=" .. tostring(vals.dep_holdshort_dist_m or "?"))
    end
    if vals.arr_exit_id then
        helpers.logInfoTS("TaxiFull: arr exit=" .. fmt_node_latlon(vals.arr_exit_id))
    end
    helpers.logInfoTS("TaxiFull: reroute=" .. fmt_latlon(vals.reroute_lat, vals.reroute_lon))
    helpers.logInfoTS("TaxiFull: onGround=" .. tostring(vals.onGround) .. " gs=" .. tostring(vals.groundspeed or "?") .. " ts=" .. tostring(vals.tirespeed or "?"))
end

local function draw_route_L(project, n1, n2, shadowColor, mainColor)
    if not (n1 and n2 and n1.east and n1.north and n2.east and n2.north) then
        return
    end
    local x1, y1 = project(n1.east, n1.north)
    local x2, y2 = project(n2.east, n2.north)
    sasl.gl.drawLine(x1, y1, x2, y2, shadowColor)
    sasl.gl.drawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1, mainColor)
end

local function drawLineThick(x1, y1, x2, y2, color, width)
    local w = math.max(1, math.floor(width or 1))
    if w <= 1 then
        sasl.gl.drawLine(x1, y1, x2, y2, color)
        return
    end
    local offsets = { {0, 0} }
    if w >= 2 then
        offsets[#offsets + 1] = {1, 0}
        offsets[#offsets + 1] = {-1, 0}
        offsets[#offsets + 1] = {0, 1}
        offsets[#offsets + 1] = {0, -1}
    end
    if w >= 3 then
        offsets[#offsets + 1] = {1, 1}
        offsets[#offsets + 1] = {-1, 1}
        offsets[#offsets + 1] = {1, -1}
        offsets[#offsets + 1] = {-1, -1}
    end
    for _, off in ipairs(offsets) do
        sasl.gl.drawLine(x1 + off[1], y1 + off[2], x2 + off[1], y2 + off[2], color)
    end
end

local function try_polygon_fill(coords, color, map)
    if not coords or #coords < 6 then
        return false
    end
    if sasl.gl.drawPolygon then
        local ok = pcall(sasl.gl.drawPolygon, coords, true, 0, color)
        if ok then
            return true
        end
    end
    if sasl.gl.drawConvexPolygon then
        local ok = pcall(sasl.gl.drawConvexPolygon, coords, true, 0, color)
        if ok then
            return true
        end
    end
    return false
end

local function normalize_words(text)
    if not text then
        return ""
    end
    text = string.gsub(text, "[Gg]%s*[Aa]%s*[Tt]%s*[Ee]", "Gate")
    text = string.gsub(text, "[Cc]%s*[Aa]%s*[Rr]%s*[Gg]%s*[Oo]", "Cargo")
    return text
end

local function short_ramp_label(ramp)
    if not ramp then
        return ""
    end
    local name = trim_spaces(tostring(ramp.name or ""))
    name = normalize_words(name)
    local lower = string.lower(name)
    local idx = string.find(lower, "class", 1, true)
    if idx then
        local i = idx + 5
        local len = #lower
        while i <= len do
            local b = string.byte(lower, i)
            if not b or b > 32 then
                break
            end
            i = i + 1
        end
        if i <= len then
            local j = i
            while j <= len do
                local b = string.byte(lower, j)
                local is_digit = (b >= 48 and b <= 57)
                local is_alpha = (b >= 97 and b <= 122)
                if not is_digit and not is_alpha then
                    break
                end
                j = j + 1
            end
            if j > i then
                return "Class " .. string.upper(string.sub(lower, i, j - 1))
            end
        end
    end
    if string.find(lower, "cargo", 1, true) then
        return "Cargo"
    end
    local tokens = {}
    local cleaned = string.gsub(name, "[|/_%-]", " ")
    for tok in string.gmatch(cleaned, "%S+") do
        local l = string.lower(tok)
        local skip = (l == "gate" or l == "gates" or l == "stand" or l == "stands" or l == "parking"
            or l == "park" or l == "ramp" or l == "apron" or l == "jets" or l == "jet"
            or l == "turboprops" or l == "turboprop" or l == "ga" or l == "tie"
            or l == "down" or l == "tiedown" or l == "terminal")
        if not skip then
            if string.find(l, "heavy", 1, true) or string.find(l, "prop", 1, true) then
                skip = true
            end
        end
        if skip then
            -- skip noise tokens
        else
            tokens[#tokens + 1] = tok
        end
    end
    name = trim_spaces(table.concat(tokens, " "))
    local ramp_type = string.lower(tostring(ramp.ramp_type or ""))
    if ramp_type == "gate" then
        if name == "" then
            return "Gate"
        end
        name = normalize_words(name)
        name = trim_spaces(name)
        local label = "Gate " .. name
        if #label > 12 then
            label = string.sub(label, 1, 12)
        end
        return label
    end
    if name ~= "" then
        name = normalize_words(name)
        name = trim_spaces(name)
        if #name > 12 then
            name = string.sub(name, 1, 12)
        end
        return name
    end
    if ramp_type ~= "" then
        return ramp_type
    end
    return ""
end

local function ramp_key(ramp)
    return string.format("%.6f|%.6f", ramp and ramp.lat or 0, ramp and ramp.lon or 0)
end

local function is_voice_enabled()
    local settingsTable = settings and settings.appSettings
    if not settingsTable then
        return false
    end
    return (settingsTable[def.CONFIGVOICEREADBACK] == def.ON) or (settingsTable[def.CONFIGVOICEADVICEONLY] == def.ON)
end

local function is_auto_taxi_guidance_enabled()
    local settingsTable = settings and settings.appSettings
    if not settingsTable then
        return false
    end
    return settingsTable[def.CONFIGAUTOTAXIGUIDANCE] == def.ON
end

local function is_visual_taxi_guidance_enabled()
    local settingsTable = settings and settings.appSettings
    if not settingsTable then
        return false
    end
    return settingsTable[def.CONFIGVISUALTAXIGUIDANCE] == def.ON
end

local function find_runway_entry_label(data, node_id)
    if not data or not data.adjacency_any or not data.runway_nodes or not node_id then
        return ""
    end
    local edges = data.adjacency_any[node_id]
    if not edges then
        return ""
    end
    for _, edge in ipairs(edges) do
        if edge and edge.to and data.runway_nodes[edge.to] then
            if edge.label and edge.label ~= "" then
                return normalize_taxiway_label(edge.label)
            end
        end
    end
    return ""
end

local function get_edge_label(data, from_id, to_id)
    if not data or not from_id or not to_id then
        return ""
    end
    local neighbors = data.adjacency and data.adjacency[from_id]
    if neighbors then
        for _, edge in ipairs(neighbors) do
            if edge.to == to_id then
                return edge.label or ""
            end
        end
    end
    neighbors = data.adjacency_any and data.adjacency_any[from_id]
    if neighbors then
        for _, edge in ipairs(neighbors) do
            if edge.to == to_id then
                return edge.label or ""
            end
        end
    end
    return ""
end

local function compute_route_label_stats(data, path)
    local stats = { taxi_edges = 0, missing = 0, none = 0 }
    if not data or not path or #path < 2 then
        return stats
    end
    for i = 1, #path - 1 do
        local raw = get_edge_label(data, path[i], path[i + 1])
        if raw == "" then
            stats.taxi_edges = stats.taxi_edges + 1
            stats.missing = stats.missing + 1
        elseif raw == "RAMP" or is_runway_label(raw) then
            -- ignore
        else
            stats.taxi_edges = stats.taxi_edges + 1
            local norm = normalize_taxiway_label(raw)
            if norm == "" then
                stats.missing = stats.missing + 1
            elseif norm == "NONE" then
                stats.none = stats.none + 1
            end
        end
    end
    local denom = stats.taxi_edges > 0 and stats.taxi_edges or 1
    stats.bad = stats.missing + stats.none
    stats.bad_ratio = stats.bad / denom
    stats.none_ratio = stats.none / denom
    return stats
end

local function arrival_grace_active(comp, now)
    if not comp or not now then
        return false
    end
    local t0 = comp._arrOnGroundSince
    return t0 ~= nil and (now - t0) < qualityArrGraceSec
end

local function record_reroute_event(comp, now)
    if not comp then
        return
    end
    comp._quality = comp._quality or {}
    local events = comp._quality.rerouteEvents or {}
    events[#events + 1] = now
    local cutoff = now - qualityRerouteWindowSec
    local i = 1
    while i <= #events do
        if events[i] < cutoff then
            table.remove(events, i)
        else
            i = i + 1
        end
    end
    comp._quality.rerouteEvents = events
end

local function assess_route_quality(comp, now, dist)
    local reasons = {}
    if not comp or not now then
        return false, reasons
    end
    comp._quality = comp._quality or {}
    local quality = comp._quality
    if dist and dist > qualityDistanceMeters then
        if not quality.distBadSince then
            quality.distBadSince = now
        end
        if (now - quality.distBadSince) >= qualityDistanceSeconds then
            reasons[#reasons + 1] = "dist"
        end
    else
        quality.distBadSince = nil
    end
    local events = quality.rerouteEvents or {}
    if #events >= qualityRerouteLimit then
        reasons[#reasons + 1] = "reroute"
    end
    local stats = comp._routeLabelStats
    if stats and (stats.taxi_edges or 0) >= qualityMinLabelEdges then
        if (stats.bad_ratio or 0) >= qualityBadLabelRatio then
            reasons[#reasons + 1] = "labels"
        elseif (stats.none_ratio or 0) >= qualityNoneLabelRatio then
            reasons[#reasons + 1] = "label-none"
        end
    end
    return #reasons > 0, reasons
end

local function build_quality_log(comp, data, icao, mode, reasons)
    local stats = comp and comp._routeLabelStats or nil
    local reroutes = comp and comp._quality and comp._quality.rerouteEvents and #comp._quality.rerouteEvents or 0
    local dist = comp and comp._lastRouteDist or nil
    local label_info = ""
    if stats and (stats.taxi_edges or 0) > 0 then
        label_info = string.format(
            " labels=%d/%d none=%d badRatio=%.2f noneRatio=%.2f",
            stats.bad or 0,
            stats.taxi_edges or 0,
            stats.none or 0,
            stats.bad_ratio or 0,
            stats.none_ratio or 0
        )
    end
    return string.format(
        "icao=%s mode=%s src=%s routeSrc=%s reasons=%s dist=%.1f reroutes=%d%s",
        tostring(icao),
        tostring(mode),
        tostring(data and data.entry and data.entry.source or "?"),
        tostring(data and data.route_source or "?"),
        table.concat(reasons or {}, ","),
        dist or -1,
        reroutes,
        label_info
    )
end

local function maybe_force_global_for_quality(comp, now, icao, mode, data, helpers)
    if not comp or not data or not icao or not now then
        return false
    end
    if mode == 1 and arrival_grace_active(comp, now) then
        return false
    end
    if not comp._route or not comp._route.path then
        return false
    end
    if data.entry and data.entry.source == "global-index" then
        if comp._quality then
            comp._quality.badSince = nil
        end
        return false
    end
    if mode == 0 and comp._depThresholdLatched then
        return false
    end
    if comp._taxiGlobalPending and comp._taxiGlobalPending[icao] then
        return false
    end

    local bad, reasons = assess_route_quality(comp, now, comp._lastRouteDist)
    if not bad then
        if comp._quality then
            comp._quality.badSince = nil
        end
        return false
    end

    comp._quality = comp._quality or {}
    if not comp._quality.badSince then
        comp._quality.badSince = now
        comp._quality.badReasons = reasons
        return false
    end
    comp._quality.badReasons = reasons
    if (now - comp._quality.badSince) < qualityBadHoldSec then
        return false
    end

    local log_info = build_quality_log(comp, data, icao, mode, reasons)
    if helpers and helpers.isGlobalAptIndexReady and helpers.isGlobalAptIndexReady() then
        comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
        comp._taxiSourceByIcao[icao] = "global"
        if comp._taxiGlobalPending then
            comp._taxiGlobalPending[icao] = nil
        end
        comp._data = nil
        comp._dataErr = nil
        comp._route = nil
        comp._routeErr = nil
        comp._routeLabels = nil
        comp._routeLabelStats = nil
        comp._routeExtraSegments = nil
        comp._lastStartKey = nil
        comp._lastEndKey = nil
        comp._lastGuidanceNodeId = nil
        comp._lastGuidanceLabel = nil
        comp._lastGuidanceTime = nil
        comp._rerouteOverride = nil
        comp._needsCenter = true
        if comp._quality then
            comp._quality.badSince = nil
            comp._quality.distBadSince = nil
            comp._quality.rerouteEvents = {}
        end
        if helpers and helpers.logInfoTS then
            helpers.logInfoTS("TaxiQuality: forcing global " .. log_info)
        end
        return true
    end

    comp._taxiGlobalPending = comp._taxiGlobalPending or {}
    comp._taxiGlobalPending[icao] = true
    comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
    comp._taxiSourceByIcao[icao] = "global"
    if helpers and helpers.requestGlobalAptIndex then
        helpers.requestGlobalAptIndex("quality-fallback")
    end
    if helpers and helpers.logInfoTS then
        helpers.logInfoTS("TaxiQuality: global pending " .. log_info)
    end
    return false
end

local function find_nearest_segment(data, path, east, north)
    if not data or not data.nodes or not path or #path < 2 then
        return nil, nil
    end
    local best_idx = nil
    local best_d2 = nil
    for i = 1, #path - 1 do
        local n1 = data.nodes[path[i]]
        local n2 = data.nodes[path[i + 1]]
        if n1 and n2 then
            local d2 = point_segment_distance_sq(east, north, n1.east, n1.north, n2.east, n2.north)
            if not best_d2 or d2 < best_d2 then
                best_d2 = d2
                best_idx = i
            end
        end
    end
    if not best_idx then
        return nil, nil
    end
    return best_idx, math.sqrt(best_d2 or 0)
end

local function get_node_degree(data, node_id)
    if not data or not node_id then
        return 0
    end
    local edges = data.adjacency_any and data.adjacency_any[node_id]
    if not edges then
        return 0
    end
    return #edges
end

local function guidance_distance_for_speed(tirespeed)
    local speed = tonumber(tirespeed) or 0
    if speed <= 0 then
        return guidanceTurnDistance
    end
    local dist = speed * guidanceLeadTimeSec
    if dist < guidanceTurnDistance then
        dist = guidanceTurnDistance
    end
    if dist > guidanceMaxDistance then
        dist = guidanceMaxDistance
    end
    return dist
end

local function speak_guidance_text(comp, text)
    local yal = comp.yal or _G.yal
    if yal and yal.commandtableentry then
        yal.commandtableentry(def.TEXT, text)
        return
    end
    helpers.speak(text)
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
        return "TAXIWAY " .. display
    end
    if kind == "runway" then
        return "RWY " .. display
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

local function emit_guidance(comp, now, info, allow_voice)
    if not comp or not info or not info.text or info.text == "" then
        return
    end
    if allow_voice and is_voice_enabled() then
        speak_guidance_text(comp, info.text)
    end
    if is_visual_taxi_guidance_enabled() and info.visual ~= false then
        info.issuedAt = now
        info.showAt = now + visualGuidanceSyncDelay
        info.expiresAt = now + visualGuidanceSyncDelay + visualGuidanceDuration
        info.minShowUntil = now + visualGuidanceSyncDelay + visualGuidanceMinShow
        if info.queue and comp._visualGuidance then
            queue_visual_guidance(comp, info)
        else
            set_visual_guidance(comp, info)
        end
    end
end

local function maybe_speak_guidance(comp, now, aircraft)
    local auto_voice = is_auto_taxi_guidance_enabled()
    local visual_enabled = is_visual_taxi_guidance_enabled()
    if not auto_voice and not visual_enabled then
        return
    end
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
        helpers.logInfoTS(msg)
    end
    local voice_enabled = auto_voice and is_voice_enabled()
    if not voice_enabled and not visual_enabled then
        diag("voice-disabled")
        return
    end
            if not comp._route or not comp._route.path then
                diag("no-route")
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
    if comp.mode == 0 and before_takeoff_active_or_set(comp) then
        local kept = false
        if is_taxi_complete_info(comp._visualGuidance) then
            kept = true
            comp._visualGuidanceQueue = {}
        elseif comp._visualGuidanceQueue and #comp._visualGuidanceQueue > 0 then
            for i = 1, #comp._visualGuidanceQueue do
                local queued = comp._visualGuidanceQueue[i]
                if is_taxi_complete_info(queued) then
                    set_visual_guidance(comp, queued)
                    table.remove(comp._visualGuidanceQueue, i)
                    comp._visualGuidanceQueue = {}
                    kept = true
                    break
                end
            end
        end
        if not kept then
            clear_visual_guidance(comp, "before-takeoff")
        end
        diag("before-takeoff")
        return
    end
    if comp._depThresholdLatched and (comp.mode == 0) then
        diag("dep-threshold")
        return
    end
    local data = comp._route.data or comp._data
    local path = comp._route.path
    local function guidance_label_info(from_id, to_id, fallback_label, ramp_hint, allow_missing)
        local raw_label = get_edge_label(data, from_id, to_id)
        if raw_label and is_runway_label(raw_label) then
            local display = normalize_runway_name(raw_label)
            if display == "" then
                display = tostring(raw_label)
            end
            return { kind = "runway", text = runway_label_voice(raw_label), display = display }
        end
        if raw_label == "RAMP" then
            local ramp_label = ramp_hint and short_ramp_label(ramp_hint) or ""
            if ramp_label == "" then
                ramp_label = "Ramp"
            end
            return { kind = "ramp", text = ramp_label, display = ramp_label }
        end
        local label = normalize_taxiway_label(raw_label)
        if label == "" and fallback_label and fallback_label ~= "" then
            label = fallback_label
        end
        if label ~= "" then
            return { kind = "taxiway", text = taxiway_label_voice(label), display = label }
        end
        if allow_missing then
            return { kind = "taxiway", text = "", display = "", missingLabel = true }
        end
        return nil
    end
    local function emit(info)
        emit_guidance(comp, now, info, auto_voice)
    end
    local tirespeed = yal and yal.tirespeed and (get(yal.tirespeed) or 0) or 0
    if not comp._initialGuidanceDone and path and #path >= 2 then
        if tirespeed >= initialGuidanceMinSpeed then
            local info = guidance_label_info(path[1], path[2], nil, comp._startRamp, false)
            if info then
                local text = ""
                if info.kind == "taxiway" then
                    text = "Taxi via Taxiway " .. info.text
                elseif info.kind == "runway" then
                    text = "Taxi via " .. info.text
                elseif info.kind == "ramp" then
                    text = "Taxi from " .. info.text
                end
                if text ~= "" then
                    local action = ""
                    if info.kind == "ramp" then
                        action = "TAXI FROM"
                    else
                        action = "TAXI VIA"
                    end
                    local label = build_visual_label(info.kind, info.display)
                    emit({
                        text = text,
                        direction = "straight",
                        action = action,
                        label = label,
                        kind = info.kind
                    })
                    comp._initialGuidanceDone = true
                    return
                end
            end
        end
    end
    if tirespeed <= 0 then
        diag("non-forward-speed", "ts=" .. tostring(tirespeed))
        return
    end
    if tirespeed < guidanceMinSpeed then
        diag("too-slow", "ts=" .. tostring(tirespeed))
        return
    end
    local seg_idx = find_nearest_segment(data, path, aircraft.east, aircraft.north)
    if not seg_idx or seg_idx >= (#path - 1) then
        diag("no-segment", "seg=" .. tostring(seg_idx or "nil") .. " path=" .. tostring(#path))
        return
    end
    local n1 = data.nodes[path[seg_idx]]
    local n2 = data.nodes[path[seg_idx + 1]]
    local n3 = data.nodes[path[seg_idx + 2]]
    if not (n1 and n2 and n3) then
        diag("segment-nodes-missing")
        return
    end
    local curr_raw_label = get_edge_label(data, path[seg_idx], path[seg_idx + 1])
    local curr_label = normalize_taxiway_label(curr_raw_label)
    local next_info = guidance_label_info(path[seg_idx + 1], path[seg_idx + 2], curr_label, comp._endRamp, true)
    if not next_info or (next_info.text == "" and not next_info.missingLabel) then
        diag("next-label-empty")
        return
    end
    local v1x = n2.east - n1.east
    local v1y = n2.north - n1.north
    local v2x = n3.east - n2.east
    local v2y = n3.north - n2.north
    local len1 = math.sqrt(v1x * v1x + v1y * v1y)
    local len2 = math.sqrt(v2x * v2x + v2y * v2y)
    if len1 <= 0.1 or len2 <= 0.1 then
        return
    end
    local dot = (v1x * v2x + v1y * v2y) / (len1 * len2)
    if dot > 1 then dot = 1 end
    if dot < -1 then dot = -1 end
    local angle = math.deg(math.acos(dot))
    local ahead_dot = (aircraft.east - n2.east) * v1x + (aircraft.north - n2.north) * v1y
    if ahead_dot > 0 then
        diag("already-passed-turn")
        return
    end
    local dist_to_node = math.sqrt(distance_sq(aircraft.east, aircraft.north, n2.east, n2.north))
    local guidance_dist = guidance_distance_for_speed(tirespeed)
    if dist_to_node > guidance_dist then
        diag("too-far", string.format("dist=%.1f", dist_to_node))
        return
    end
    local last_time = comp._lastGuidanceTime or 0
    local label_key = next_info.kind .. ":" .. next_info.text
    if comp._lastGuidanceNodeId == path[seg_idx + 1]
        and comp._lastGuidanceLabel == label_key
        and (now - last_time) < guidanceCooldown then
        diag("cooldown")
        return
    end
    local cross = v1x * v2y - v1y * v2x
    local text = ""
    local direction = "straight"
    local action = ""
    local dep_mode = (comp.mode == 0)
    local entering_runway = next_info.kind == "runway" and (not curr_raw_label or not is_runway_label(curr_raw_label))
    local label_changed = curr_label ~= "" and next_info.display ~= "" and curr_label ~= next_info.display
    local force_turn = curr_raw_label and is_runway_label(curr_raw_label) and next_info.kind ~= "runway"
    local leaving_runway = (not dep_mode) and curr_raw_label and is_runway_label(curr_raw_label)
        and (next_info.kind == "taxiway" or next_info.kind == "ramp")
    if leaving_runway then
        local turn = (cross >= 0) and "left" or "right"
        local rwy_phrase = runway_label_voice(curr_raw_label)
        direction = turn
        action = "EXIT RWY"
        if next_info.kind == "taxiway" then
            if next_info.missingLabel then
                text = "Leave " .. rwy_phrase .. " to the " .. turn .. " at next taxiway"
            else
                text = "Leave " .. rwy_phrase .. " to the " .. turn .. " on Taxiway " .. next_info.text
            end
        else
            text = "Leave " .. rwy_phrase .. " to the " .. turn .. " to " .. next_info.text
        end
    elseif angle < guidanceTurnAngle and not force_turn then
        direction = "straight"
        action = "STRAIGHT"
        if next_info.kind == "taxiway" then
            local degree = get_node_degree(data, path[seg_idx + 1])
            if degree < 3 and not label_changed and angle < guidanceStraightAngle then
                diag("angle-too-small", string.format("angle=%.1f", angle))
                return
            end
            if next_info.missingLabel then
                text = "Continue straight"
            else
                text = "Continue straight on Taxiway " .. next_info.text
            end
        elseif next_info.kind == "runway" then
            local rwy_phrase = runway_label_voice(next_info.display ~= "" and next_info.display or next_info.text)
            if dep_mode and entering_runway then
                text = "Enter departure " .. rwy_phrase
                action = "ENTER RWY"
            else
                local backtrack = false
                if dep_mode then
                    local profile = comp._depProfile
                    if profile and profile.axis then
                        local len = math.sqrt(v1x * v1x + v1y * v1y)
                        if len > 0.1 then
                            local dot = (v1x * profile.axis.x + v1y * profile.axis.y) / len
                            if dot < -0.2 then
                                backtrack = true
                            end
                        end
                    end
                end
                if backtrack then
                    text = "Backtrack on " .. rwy_phrase
                    action = "BACKTRACK"
                else
                    text = "Continue straight on " .. rwy_phrase
                end
            end
        elseif next_info.kind == "ramp" then
            text = "Continue straight to " .. next_info.text
        end
    else
        local turn = (cross >= 0) and "left" or "right"
        direction = turn
        action = (turn == "left") and "TURN LEFT" or "TURN RIGHT"
        if next_info.kind == "taxiway" then
            if next_info.missingLabel then
                text = "Turn " .. turn .. " at next taxiway"
            else
                text = "Turn " .. turn .. " on Taxiway " .. next_info.text
            end
        elseif next_info.kind == "runway" then
            if dep_mode and entering_runway then
                local rwy_phrase = runway_label_voice(next_info.display ~= "" and next_info.display or next_info.text)
                text = "Turn " .. turn .. " on departure " .. rwy_phrase
            else
                text = "Turn " .. turn .. " on " .. next_info.text
            end
        elseif next_info.kind == "ramp" then
            text = "Turn " .. turn .. " to " .. next_info.text
        end
    end
    if text == "" then
        return
    end
    if dep_mode and entering_runway and next_info.kind == "runway" then
        comp._depRunwayEntryAnnounced = true
    end
    local label = build_visual_label(next_info.kind, next_info.display)
    emit({
        text = text,
        direction = direction,
        action = action,
        label = label,
        kind = next_info.kind,
        targetSegIdx = seg_idx + 1
    })
    comp._lastGuidanceNodeId = path[seg_idx + 1]
    comp._lastGuidanceLabel = label_key
    comp._lastGuidanceTime = now
end

local function getSettingNumber(key, fallback)
    local val = tonumber(settings.appSettings[key])
    if val == nil then
        return fallback
    end
    return val
end

local C = {
    defaultW = defaultW,
    defaultH = defaultH,
    headerH = headerH,
    toolbarH = toolbarH,
    mapPadding = mapPadding,
    updateInterval = updateInterval,
    guidanceCooldown = guidanceCooldown,
    rerouteCooldown = rerouteCooldown,
    rerouteDriftMeters = rerouteDriftMeters,
    guidanceMinSpeed = guidanceMinSpeed,
    guidanceTurnDistance = guidanceTurnDistance,
    guidanceTurnAngle = guidanceTurnAngle,
    guidanceLeadTimeSec = guidanceLeadTimeSec,
    guidanceMaxDistance = guidanceMaxDistance,
    guidanceStraightAngle = guidanceStraightAngle,
    startRampMaxMeters = startRampMaxMeters,
    autoGateSwitchDist = autoGateSwitchDist,
    autoGateSwitchDelta = autoGateSwitchDelta,
    autoGateSwitchRatio = autoGateSwitchRatio,
    autoGateSwitchSpeed = autoGateSwitchSpeed,
    autoGateSwitchHoldSec = autoGateSwitchHoldSec,
    autoGateSwitchCooldownSec = autoGateSwitchCooldownSec,
    parkingBrakeCompleteDist = parkingBrakeCompleteDist,
    minZoom = minZoom,
    maxZoom = maxZoom,
    zoomStep = zoomStep,
    minFont = minFont,
    maxFont = maxFont
}

local U = {
    is_valid_latlon = is_valid_latlon,
    compute_bounds_center = compute_bounds_center,
    update_bounds = update_bounds,
    estimate_text_width = estimate_text_width,
    compute_bounds_scale = compute_bounds_scale,
    rotate_point = rotate_point,
    distance_meters_latlon = distance_meters_latlon,
    latlon_to_local = latlon_to_local,
    basename = basename,
    trim_spaces = trim_spaces,
    normalize_taxiway_label = normalize_taxiway_label,
    taxiway_label_voice = taxiway_label_voice,
    is_runway_label = is_runway_label,
    nearest_node_info = nearest_node_info,
    nearest_non_runway_node = nearest_non_runway_node,
    distance_sq = distance_sq,
    point_segment_distance_sq = point_segment_distance_sq,
    project_point_to_segment = project_point_to_segment,
    clone_adjacency = clone_adjacency,
    adjacency_has_edge = adjacency_has_edge,
    add_adj_edge = add_adj_edge,
    find_nearest_edge_projection = find_nearest_edge_projection,
    find_heading_edge_projection = find_heading_edge_projection,
    find_preferred_edge_projection = find_preferred_edge_projection,
    build_projected_data = build_projected_data,
    distance_to_route = distance_to_route,
    distance_to_segments = distance_to_segments,
    normalize_runway_name = normalize_runway_name,
    parse_runway_parts = parse_runway_parts,
    find_runway_entry = find_runway_entry,
    compute_runway_landing_profile = compute_runway_landing_profile,
    find_nearest_runway_node = find_nearest_runway_node,
    find_holdshort_node_near = find_holdshort_node_near,
    build_runway_backtrack_segments = build_runway_backtrack_segments,
    compute_along_perp = compute_along_perp,
    select_runway_exit_node = select_runway_exit_node,
    copy_opts = copy_opts,
    route_with_waypoints = route_with_waypoints,
    try_route_from_candidates = try_route_from_candidates,
    try_route_to_candidates = try_route_to_candidates,
    collect_nearest_nodes = collect_nearest_nodes,
    normalize_icao = normalize_icao,
    build_route_labels = build_route_labels,
    clamp = clamp,
    getFont = getFont,
    drawText = drawText,
    log_full_route_state = log_full_route_state,
    draw_route_L = draw_route_L,
    drawLineThick = drawLineThick,
    try_polygon_fill = try_polygon_fill,
    normalize_words = normalize_words,
    short_ramp_label = short_ramp_label,
    ramp_key = ramp_key,
    is_voice_enabled = is_voice_enabled,
    is_auto_taxi_guidance_enabled = is_auto_taxi_guidance_enabled,
    find_runway_entry_label = find_runway_entry_label,
    get_edge_label = get_edge_label,
    find_nearest_segment = find_nearest_segment,
    get_node_degree = get_node_degree,
    guidance_distance_for_speed = guidance_distance_for_speed,
    speak_guidance_text = speak_guidance_text,
    maybe_speak_guidance = maybe_speak_guidance,
    clear_visual_guidance = clear_visual_guidance,
    update_visual_guidance = update_visual_guidance,
    maybe_force_global_for_quality = maybe_force_global_for_quality,
    getSettingNumber = getSettingNumber,
    emit_guidance = emit_guidance,
    arrival_grace_active = arrival_grace_active,
    runway_label_voice = runway_label_voice,
    build_visual_label = build_visual_label
}

function M.windowSize()
    return defaultW, defaultH
end

local function newComponentImpl(ctx, def, settings, helpers, C, U)
    local defaultW = C.defaultW
    local defaultH = C.defaultH
    local headerH = C.headerH
    local toolbarH = C.toolbarH
    local mapPadding = C.mapPadding
    local updateInterval = C.updateInterval
    local guidanceCooldown = C.guidanceCooldown
    local rerouteCooldown = C.rerouteCooldown
    local rerouteDriftMeters = C.rerouteDriftMeters
    local guidanceMinSpeed = C.guidanceMinSpeed
    local guidanceTurnDistance = C.guidanceTurnDistance
    local guidanceTurnAngle = C.guidanceTurnAngle
    local guidanceLeadTimeSec = C.guidanceLeadTimeSec
    local guidanceMaxDistance = C.guidanceMaxDistance
    local guidanceStraightAngle = C.guidanceStraightAngle
    local startRampMaxMeters = C.startRampMaxMeters
    local minZoom = C.minZoom
    local maxZoom = C.maxZoom
    local zoomStep = C.zoomStep
    local minFont = C.minFont
    local maxFont = C.maxFont

    local is_valid_latlon = U.is_valid_latlon
    local compute_bounds_center = U.compute_bounds_center
    local update_bounds = U.update_bounds
    local estimate_text_width = U.estimate_text_width
    local compute_bounds_scale = U.compute_bounds_scale
    local rotate_point = U.rotate_point
    local distance_meters_latlon = U.distance_meters_latlon
    local latlon_to_local = U.latlon_to_local
    local basename = U.basename
    local trim_spaces = U.trim_spaces
    local normalize_taxiway_label = U.normalize_taxiway_label
    local taxiway_label_voice = U.taxiway_label_voice
    local is_runway_label = U.is_runway_label
    local nearest_node_info = U.nearest_node_info
    local nearest_non_runway_node = U.nearest_non_runway_node
    local distance_sq = U.distance_sq
    local point_segment_distance_sq = U.point_segment_distance_sq
    local project_point_to_segment = U.project_point_to_segment
    local clone_adjacency = U.clone_adjacency
    local adjacency_has_edge = U.adjacency_has_edge
    local add_adj_edge = U.add_adj_edge
    local find_nearest_edge_projection = U.find_nearest_edge_projection
    local find_heading_edge_projection = U.find_heading_edge_projection
    local find_preferred_edge_projection = U.find_preferred_edge_projection
    local build_projected_data = U.build_projected_data
    local distance_to_route = U.distance_to_route
    local distance_to_segments = U.distance_to_segments
    local normalize_runway_name = U.normalize_runway_name
    local parse_runway_parts = U.parse_runway_parts
    local find_runway_entry = U.find_runway_entry
    local compute_runway_landing_profile = U.compute_runway_landing_profile
    local find_nearest_runway_node = U.find_nearest_runway_node
    local find_holdshort_node_near = U.find_holdshort_node_near
    local build_runway_backtrack_segments = U.build_runway_backtrack_segments
    local compute_along_perp = U.compute_along_perp
    local select_runway_exit_node = U.select_runway_exit_node
    local copy_opts = U.copy_opts
    local route_with_waypoints = U.route_with_waypoints
    local try_route_from_candidates = U.try_route_from_candidates
    local try_route_to_candidates = U.try_route_to_candidates
    local collect_nearest_nodes = U.collect_nearest_nodes
    local normalize_icao = U.normalize_icao
    local build_route_labels = U.build_route_labels
    local clamp = U.clamp
    local getFont = U.getFont
    local drawText = U.drawText
    local log_full_route_state = U.log_full_route_state
    local draw_route_L = U.draw_route_L
    local drawLineThick = U.drawLineThick
    local try_polygon_fill = U.try_polygon_fill
    local normalize_words = U.normalize_words
    local short_ramp_label = U.short_ramp_label
    local ramp_key = U.ramp_key
    local is_voice_enabled = U.is_voice_enabled
    local is_auto_taxi_guidance_enabled = U.is_auto_taxi_guidance_enabled
    local find_runway_entry_label = U.find_runway_entry_label
    local get_edge_label = U.get_edge_label
    local find_nearest_segment = U.find_nearest_segment
    local get_node_degree = U.get_node_degree
    local guidance_distance_for_speed = U.guidance_distance_for_speed
    local speak_guidance_text = U.speak_guidance_text
    local maybe_speak_guidance = U.maybe_speak_guidance
    local clear_visual_guidance = U.clear_visual_guidance
    local update_visual_guidance = U.update_visual_guidance
    local maybe_force_global_for_quality = U.maybe_force_global_for_quality
    local getSettingNumber = U.getSettingNumber

    local comp = {}
    comp.name = "yal_taxi_map_component"
    comp.components = {}
    comp.position = createProperty({0, 0, defaultW, defaultH})
    comp.size = {defaultW, defaultH}
    comp.fbo = createProperty(false)
    comp.renderTarget = -1
    comp.fpsLimit = createProperty(-1)
    comp.frames = 0
    comp.noRenderSignal = createProperty(false)
    comp.clip = createProperty(false)
    comp.clipSize = createProperty({0, 0, 0, 0})
    comp.visible = createProperty(true)
    comp._window = nil
    comp._layout = nil
    comp._buttons = {}
    comp.drag = nil
    comp.panX = 0
    comp.panY = 0
    comp.orientation = getSettingNumber(def.CONFIGTAXIMAPORIENT, 0)
    comp.zoom = clamp(getSettingNumber(def.CONFIGTAXIMAPZOOM, 1.0), minZoom, maxZoom)
    comp.fontSize = clamp(getSettingNumber(def.CONFIGTAXIMAPFONTSIZE, 12), minFont, maxFont)
    comp._fontHandle = nil
    comp._fontSizeCached = nil
    comp.mode = 0
    comp.modeOverride = false
    comp.centerEast = nil
    comp.centerNorth = nil
    comp._baseScale = 1
    comp._data = nil
    comp._route = nil
    comp._routeErr = nil
    comp._dataErr = nil
    comp._routeLabels = nil
    comp._startPoint = nil
    comp._endPoint = nil
    comp._startRamp = nil
    comp._endRamp = nil
    comp._startIsAircraft = false
    comp._selectedEndRampKey = nil
    comp._selectedDepEntryId = nil
    comp._runwayName = nil
    comp._fitBounds = nil
    comp._lastUpdate = nil
    comp._lastIcao = nil
    comp._lastMode = nil
    comp._lastStartKey = nil
    comp._lastEndKey = nil
    comp._routeStartAnchor = nil
    comp._routeExtraSegments = nil
    comp._lastArrivalIcao = nil
    comp._lastArrivalRunwayName = nil
    comp._lastArrivalRunwayLat = nil
    comp._lastArrivalRunwayLon = nil
    comp._lastDepRunwayName = nil
    comp._needsCenter = true
    comp._lastGuidanceNodeId = nil
    comp._lastGuidanceLabel = nil
    comp._lastGuidanceTime = nil
    comp._visualGuidance = nil
    comp._depRunwayEntryAnnounced = false
    comp._depTaxiCompleteAnnounced = false
    comp._arrTaxiCompleteAnnounced = false
    comp._initialGuidanceDone = false
    comp._lastRecomputeKey = nil
    comp._lastRerouteTime = nil
    comp._rerouteOverride = nil
    comp._depThresholdLatched = false
    comp._takeoffLatchSince = nil
    comp._aircraftPoint = nil
    comp._autoEndRampLowSpeedSince = nil
    comp._autoEndRampSwitchTime = nil
    comp._editRoute = false
    comp._drawRoute = false
    comp._drawFreehand = false
    comp._routeWaypoints = {}
    comp._wpDrag = nil
    comp._editHandles = nil
    comp._editSuppressedNodes = nil
    comp._editDirty = false
    comp._editStartOverride = nil
    comp._editEndOverride = nil
    comp._lastRouteStateKey = nil
    comp._undoState = nil
    comp._undoReason = nil
    comp._tuning = {
        autoGateSwitchDist = C.autoGateSwitchDist,
        autoGateSwitchDelta = C.autoGateSwitchDelta,
        autoGateSwitchRatio = C.autoGateSwitchRatio,
        autoGateSwitchSpeed = C.autoGateSwitchSpeed,
        autoGateSwitchHoldSec = C.autoGateSwitchHoldSec,
        autoGateSwitchCooldownSec = C.autoGateSwitchCooldownSec,
        parkingBrakeCompleteDist = C.parkingBrakeCompleteDist
    }
    comp._U = U
    comp._C = C
    comp._def = def
    comp._helpers = helpers
    comp._logTaxi = log_taxi
    comp._autoEndRampKey = nil
    comp._quality = { rerouteEvents = {} }
    comp._taxiSourceByIcao = {}
    comp._taxiGlobalPending = {}
    comp.yal = ctx and ctx.yal or _G.yal
    comp._timer = sasl.createTimer()
    sasl.startTimer(comp._timer)

    function comp:setWindow(win)
        self._window = win
        log_taxi("TaxiWindow: setWindow")
    end

    local function getSize()
        local p = get(comp.position)
        local w = (p and p[3] and p[3] > 0) and p[3] or defaultW
        local h = (p and p[4] and p[4] > 0) and p[4] or defaultH
        if comp._window and comp._window.getPosition then
            local _, _, ww, hh = comp._window:getPosition()
            if ww and hh and (ww ~= w or hh ~= h) then
                set(comp.position, {0, 0, ww, hh})
                if comp.size then
                    comp.size = {ww, hh}
                end
                if comp._data and comp._data.bounds then
                    comp._fitBounds = comp._data.bounds
                end
                comp._needsCenter = true
                w = ww
                h = hh
            end
        end
        return w, h
    end

    local function commitSettings()
        settings.appSettings[def.CONFIGTAXIMAPORIENT] = comp.orientation
        settings.appSettings[def.CONFIGTAXIMAPZOOM] = helpers.roundnumber(comp.zoom, 2)
        settings.appSettings[def.CONFIGTAXIMAPFONTSIZE] = math.floor(comp.fontSize + 0.5)
        settings.writeSettings(settings.appSettings)
    end

    local function set_center(east, north)
        if east == nil or north == nil then
            return
        end
        comp.centerEast = east
        comp.centerNorth = north
        comp.panX = 0
        comp.panY = 0
    end

    local function center_on_aircraft()
        local yal = comp.yal or _G.yal
        if not yal or not yal.aircraftlatpos or not yal.aircraftlonpos then
            return false
        end
        local lat = get(yal.aircraftlatpos)
        local lon = get(yal.aircraftlonpos)
        if not is_valid_latlon(lat, lon) then
            return false
        end
        local x, y = latlon_to_local(lat, lon)
        if x == nil or y == nil then
            return false
        end
        set_center(x, y)
        return true
    end

    local function fit_to_bounds(bounds, map)
        if not bounds or not map then
            return
        end
        local baseScale = comp._baseScale or 1
        local fitScale = compute_bounds_scale(bounds, map.w, map.h)
        if baseScale <= 0 then
            baseScale = 1
        end
        comp.zoom = clamp(fitScale / baseScale, minZoom, maxZoom)
        local cx, cy = compute_bounds_center(bounds)
        set_center(cx, cy)
        commitSettings()
    end

    local function addButton(tbl, x, y, w_, h_, label, action)
        tbl[#tbl + 1] = { x = x, y = y, w = w_, h = h_, label = label, action = action }
    end

    local function drawButton(font, b, active, size)
        local fill = active and {0.25, 0.35, 0.5, 0.9} or {0.2, 0.2, 0.2, 0.9}
        drawRectangle(b.x, b.y, b.w, b.h, fill)
        sasl.gl.drawFrame(b.x, b.y, b.w, b.h, {0.6, 0.6, 0.6, 1})
        drawText(font, b.x + 6, b.y + 2, b.label, size, TEXT_ALIGN_LEFT, {0.9, 0.9, 0.95, 1})
    end

    function comp:draw()
        local w, h = getSize()
        local font = getFont(comp)

        local layout = {
            close = { x = w - 24, y = h - headerH, w = 24, h = headerH },
            buttons = {},
            ramps = {},
            dep_entries = {},
            waypoints = {},
            map = {
                x = mapPadding,
                y = mapPadding,
                w = w - mapPadding * 2,
                h = h - headerH - toolbarH - mapPadding * 2
            }
        }
        layout.map.y = mapPadding

        drawRectangle(0, 0, w, h, {0, 0, 0, 0.78})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.6, 0.6, 0.6, 0.8})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 1})
        drawRectangle(0, h - headerH - toolbarH, w, toolbarH, {0.08, 0.08, 0.08, 1})

        local uiFontSize = def and def.wFontSize or 12
        local mapFontSize = comp.fontSize or 12
        drawText(font, 8, h - headerH + 4, "Taxi Map", uiFontSize, TEXT_ALIGN_LEFT, {0.9, 0.9, 0.95, 1})
        drawText(font, w - 18, h - headerH + 4, "X", uiFontSize, TEXT_ALIGN_LEFT, {0.9, 0.5, 0.5, 1})

        self:updateTaxiState(layout.map)

        local btnW = 78
        local btnH = toolbarH - 6
        local y = h - headerH - toolbarH + 3
        local x = 8

        local modeLabel = (comp.mode == 1) and "ARR" or "DEP"
        addButton(layout.buttons, x, y, 64, btnH, modeLabel, "toggle_mode")
        x = x + 70

        local orientLabel = (comp.orientation == 1) and "HDG UP" or "NORTH UP"
        addButton(layout.buttons, x, y, btnW + 10, btnH, orientLabel, "toggle_orient")
        x = x + btnW + 16
        addButton(layout.buttons, x, y, btnW, btnH, "ZOOM -", "zoom_out")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "ZOOM +", "zoom_in")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "FIT", "fit")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "CENTER", "center")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "AUTO", "auto_route")
        x = x + btnW + 10
        local editLabel = comp._editRoute and "EDIT ON" or "EDIT"
        addButton(layout.buttons, x, y, btnW, btnH, editLabel, "toggle_edit")
        x = x + btnW + 10
        local drawLabel = comp._drawRoute and "DRAWING" or "DRAW NEW"
        addButton(layout.buttons, x, y, btnW, btnH, drawLabel, "toggle_draw")
        x = x + btnW + 10
        addButton(layout.buttons, x, y, btnW, btnH, "UNDO", "undo_edit")
        x = x + btnW + 10
        addButton(layout.buttons, x, y, btnW, btnH, "A -", "font_down")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "A +", "font_up")

        for _, b in ipairs(layout.buttons) do
            local active = (b.action == "toggle_orient") and (comp.orientation == 1)
            if b.action == "toggle_edit" then
                active = comp._editRoute == true
            elseif b.action == "toggle_draw" then
                active = comp._drawRoute == true
            end
            drawButton(font, b, active, uiFontSize)
        end
        comp._buttons = layout.buttons

        local map = layout.map
        drawRectangle(map.x, map.y, map.w, map.h, {0.78, 0.86, 0.67, 0.98})
        sasl.gl.drawFrame(map.x, map.y, map.w, map.h, {0.4, 0.4, 0.4, 0.8})
        comp._baseScale = compute_bounds_scale((comp._data and comp._data.bounds), map.w, map.h)
        if sasl.gl.setClipArea then
            sasl.gl.setClipArea(map.x, map.y, map.w, map.h)
        end

        local centerEast = comp.centerEast
        local centerNorth = comp.centerNorth
        if centerEast == nil or centerNorth == nil then
            if center_on_aircraft() then
                centerEast = comp.centerEast
                centerNorth = comp.centerNorth
            elseif comp._data and comp._data.bounds then
                centerEast, centerNorth = compute_bounds_center(comp._data.bounds)
                set_center(centerEast, centerNorth)
            else
                centerEast, centerNorth = 0, 0
                set_center(centerEast, centerNorth)
            end
        end

        local heading = 0
        if comp.orientation == 1 then
            local yal = comp.yal or _G.yal
            if yal and yal.groundtrackmag then
                heading = get(yal.groundtrackmag) or 0
            elseif yal and yal.localpositionpsi then
                heading = get(yal.localpositionpsi) or 0
            end
        end
        local rot = -math.rad(heading or 0)

        local scale = (comp._baseScale or 1) * (comp.zoom or 1)

        local function project(east, north)
            local dx = (east or 0) - centerEast
            local dy = (north or 0) - centerNorth
            dx, dy = rotate_point(dx, dy, rot)
            local sx = map.x + map.w * 0.5 + dx * scale + comp.panX
            local sy = map.y + map.h * 0.5 + dy * scale + comp.panY
            return sx, sy
        end
        comp._mapTransform = {
            centerEast = centerEast,
            centerNorth = centerNorth,
            rot = rot,
            scale = scale,
            mapX = map.x,
            mapY = map.y,
            mapW = map.w,
            mapH = map.h,
            panX = comp.panX,
            panY = comp.panY
        }

        local taxiEdgeColor = {0.95, 0.85, 0.15, 0.95}
        local taxiFillColor = {0.62, 0.62, 0.62, 0.95}
        local apronFillColor = {0.58, 0.58, 0.58, 0.95}
        local runwayFillColor = {0.2, 0.2, 0.2, 1}
        local runwayEdgeColor = {0.05, 0.05, 0.05, 1}
        local runwayShoulderColor = {0.38, 0.38, 0.38, 1}
        local holdShortColor = {0.95, 0.6, 0.1, 1}
        local routeColor = {0.9, 0.15, 0.15, 1}
        local routeShadow = {0.2, 0.05, 0.05, 0.9}
        local rampColor = {0.85, 0.75, 0.25, 0.9}
        local rampGateColor = {0.35, 0.7, 1, 0.95}
        local startColor = {0.2, 0.85, 0.35, 1}
        local endColor = {1, 0.6, 0.2, 1}
        local aircraftColor = {0.1, 0.2, 0.95, 1}

        if comp._data and comp._data.polygons then
            for _, poly in ipairs(comp._data.polygons) do
                local pts = poly.points or {}
                if #pts >= 3 then
                    local coords = {}
                    for _, pt in ipairs(pts) do
                        local sx, sy = project(pt.east, pt.north)
                        coords[#coords + 1] = sx
                        coords[#coords + 1] = sy
                    end
                    local fill = taxiFillColor
                    if poly.kind == "apron" then
                        fill = apronFillColor
                    end
                    try_polygon_fill(coords, fill, map)
                end
            end
        end

        local taxi_labels = {}
        local taxi_label_positions = {}
        local taxi_label_min_px = 90
        local holdshort_marks = {}
        if comp._data and comp._data.edges then
            for _, edge in ipairs(comp._data.edges) do
                local n1 = comp._data.nodes[edge.from]
                local n2 = comp._data.nodes[edge.to]
                if n1 and n2 then
                    local x1, y1 = project(n1.east, n1.north)
                    local x2, y2 = project(n2.east, n2.north)
                    local color = taxiEdgeColor
                    if edge.label and string.sub(edge.label, 1, 3) == "RWY" then
                        color = runwayEdgeColor
                        if comp._data.runway_nodes and comp._data.runway_nodes[edge.from] ~= comp._data.runway_nodes[edge.to] then
                            local from_is_runway = comp._data.runway_nodes[edge.from] == true
                            local non = from_is_runway and n2 or n1
                            local run = from_is_runway and n1 or n2
                            local dx = run.east - non.east
                            local dy = run.north - non.north
                            local len = math.sqrt(dx * dx + dy * dy)
                            if len > 0.5 then
                                local ux = dx / len
                                local uy = dy / len
                                local px = -uy
                                local py = ux
                                local offset = 10
                                local half = 14
                                local bx = non.east + ux * offset
                                local by = non.north + uy * offset
                                local key = string.format("%.3f|%.3f|%.3f|%.3f", bx, by, px, py)
                                if not holdshort_marks[key] then
                                    holdshort_marks[key] = { bx = bx, by = by, px = px, py = py, half = half }
                                end
                            end
                        end
                    end
                    drawLineThick(x1, y1, x2, y2, color, 2)
                    if edge.label and string.sub(edge.label, 1, 3) ~= "RWY" then
                        local lbl = normalize_taxiway_label(edge.label)
                        if lbl and lbl ~= "" then
                            local mx = (x1 + x2) * 0.5
                            local my = (y1 + y2) * 0.5
                            if mx >= map.x and mx <= (map.x + map.w) and my >= map.y and my <= (map.y + map.h) then
                                local positions = taxi_label_positions[lbl]
                                if not positions then
                                    positions = {}
                                    taxi_label_positions[lbl] = positions
                                end
                                local too_close = false
                                for _, pos in ipairs(positions) do
                                    local dx = mx - pos.x
                                    local dy = my - pos.y
                                    if (dx * dx + dy * dy) < (taxi_label_min_px * taxi_label_min_px) then
                                        too_close = true
                                        break
                                    end
                                end
                                if not too_close then
                                    positions[#positions + 1] = { x = mx, y = my }
                                    taxi_labels[#taxi_labels + 1] = { x = mx, y = my, text = lbl }
                                end
                            end
                        end
                    end
                end
            end
        end

        if next(holdshort_marks) ~= nil then
            for _, mark in pairs(holdshort_marks) do
                local p1x, p1y = project(mark.bx + mark.px * mark.half, mark.by + mark.py * mark.half)
                local p2x, p2y = project(mark.bx - mark.px * mark.half, mark.by - mark.py * mark.half)
                drawLineThick(p1x, p1y, p2x, p2y, holdShortColor, 3)
            end
        end

        if comp._data and comp._data.runways then
            for _, rwy in ipairs(comp._data.runways) do
                local ex1 = rwy.east1 or 0
                local ny1 = rwy.north1 or 0
                local ex2 = rwy.east2 or 0
                local ny2 = rwy.north2 or 0
                local dx = ex2 - ex1
                local dy = ny2 - ny1
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 1 then
                    local ax = dx / len
                    local ay = dy / len
                    local ux = -dy / len
                    local uy = dx / len
                    local halfW = (rwy.width or 0) * 0.5
                    local shoulderW = halfW + 10
                    if halfW <= 0 then
                        halfW = 20
                        shoulderW = halfW + 10
                    end
                    local left1x = ex1 + ux * halfW
                    local left1y = ny1 + uy * halfW
                    local left2x = ex2 + ux * halfW
                    local left2y = ny2 + uy * halfW
                    local right1x = ex1 - ux * halfW
                    local right1y = ny1 - uy * halfW
                    local right2x = ex2 - ux * halfW
                    local right2y = ny2 - uy * halfW
                    local sh_left1x = ex1 + ux * shoulderW
                    local sh_left1y = ny1 + uy * shoulderW
                    local sh_left2x = ex2 + ux * shoulderW
                    local sh_left2y = ny2 + uy * shoulderW
                    local sh_right1x = ex1 - ux * shoulderW
                    local sh_right1y = ny1 - uy * shoulderW
                    local sh_right2x = ex2 - ux * shoulderW
                    local sh_right2y = ny2 - uy * shoulderW
                    local x1, y1 = project(left1x, left1y)
                    local x2, y2 = project(left2x, left2y)
                    local x3, y3 = project(right1x, right1y)
                    local x4, y4 = project(right2x, right2y)
                    local sh1x, sh1y = project(sh_left1x, sh_left1y)
                    local sh2x, sh2y = project(sh_left2x, sh_left2y)
                    local sh3x, sh3y = project(sh_right1x, sh_right1y)
                    local sh4x, sh4y = project(sh_right2x, sh_right2y)
                    try_polygon_fill({sh1x, sh1y, sh2x, sh2y, sh4x, sh4y, sh3x, sh3y}, runwayShoulderColor, map)
                    try_polygon_fill({x1, y1, x2, y2, x4, y4, x3, y3}, runwayFillColor, map)
                    drawLineThick(sh1x, sh1y, sh2x, sh2y, runwayShoulderColor, 3)
                    drawLineThick(sh3x, sh3y, sh4x, sh4y, runwayShoulderColor, 3)
                    drawLineThick(x1, y1, x2, y2, runwayEdgeColor, 2)
                    drawLineThick(x3, y3, x4, y4, runwayEdgeColor, 2)
                    local mx = (left1x + right1x) * 0.5
                    local my = (left1y + right1y) * 0.5
                    local mx2 = (left2x + right2x) * 0.5
                    local my2 = (left2y + right2y) * 0.5
                    local cx1, cy1 = project(mx, my)
                    local cx2, cy2 = project(mx2, my2)
                    drawLineThick(cx1, cy1, cx2, cy2, runwayFillColor, 2)

                    local labelOff = halfW + 12
                    local headOff = 18
                    local l1x = ex1 - ax * headOff + ux * labelOff
                    local l1y = ny1 - ay * headOff + uy * labelOff
                    local l2x = ex2 + ax * headOff - ux * labelOff
                    local l2y = ny2 + ay * headOff - uy * labelOff
                    local sx1, sy1 = project(l1x, l1y)
                    local sx2, sy2 = project(l2x, l2y)
                    if rwy.rwy1 and rwy.rwy1 ~= "" then
                        drawText(font, sx1 + 2, sy1 + 2, rwy.rwy1, mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 1})
                    end
                    if rwy.rwy2 and rwy.rwy2 ~= "" then
                        drawText(font, sx2 + 2, sy2 + 2, rwy.rwy2, mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 1})
                    end
                else
                    local x1, y1 = project(ex1, ny1)
                    local x2, y2 = project(ex2, ny2)
                    drawLineThick(x1, y1, x2, y2, runwayEdgeColor, 2)
                    if rwy.rwy1 and rwy.rwy1 ~= "" then
                        drawText(font, x1 + 2, y1 + 2, rwy.rwy1, mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 1})
                    end
                    if rwy.rwy2 and rwy.rwy2 ~= "" then
                        drawText(font, x2 + 2, y2 + 2, rwy.rwy2, mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 1})
                    end
                end
            end
        end

        if #taxi_labels > 0 then
            local labelColor = {0.1, 0.1, 0.1, 1}
            local boxFill = {0.95, 0.95, 0.95, 0.85}
            local boxFrame = {0.4, 0.4, 0.4, 0.9}
            for _, lbl in ipairs(taxi_labels) do
                local tw = estimate_text_width(lbl.text, mapFontSize)
                local th = mapFontSize + 4
                local bx = lbl.x + 2
                local by = lbl.y + 1
                drawRectangle(bx, by, tw + 6, th, boxFill)
                sasl.gl.drawFrame(bx, by, tw + 6, th, boxFrame)
                drawText(font, bx + 3, by + 2, lbl.text, mapFontSize, TEXT_ALIGN_LEFT, labelColor)
            end
        end

        local routeData = nil
        if comp._route and comp._route.path then
            routeData = comp._route.data or comp._data
            local path = comp._route.path
            for i = 1, #path - 1 do
                local n1 = routeData and routeData.nodes and routeData.nodes[path[i]]
                local n2 = routeData and routeData.nodes and routeData.nodes[path[i + 1]]
                if n1 and n2 then
                    local x1, y1 = project(n1.east, n1.north)
                    local x2, y2 = project(n2.east, n2.north)
                    local isRamp1 = n1.is_ramp == true
                    local isRamp2 = n2.is_ramp == true
                    if isRamp1 ~= isRamp2 then
                        draw_route_L(project, n1, n2, routeShadow, routeColor)
                    else
                        sasl.gl.drawLine(x1, y1, x2, y2, routeShadow)
                        sasl.gl.drawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1, routeColor)
                    end
                end
            end
        end
        if comp._routeExtraSegments then
            for _, seg in ipairs(comp._routeExtraSegments) do
                local x1, y1 = project(seg.east1, seg.north1)
                local x2, y2 = project(seg.east2, seg.north2)
                sasl.gl.drawLine(x1, y1, x2, y2, routeShadow)
                sasl.gl.drawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1, routeColor)
            end
        end
        if (not comp._drawFreehand) and routeData and routeData.nodes
            and comp._endRamp and comp._endRamp.east and comp._endRamp.north then
            local endNode = nil
            if comp._route and comp._route.path then
                local last_id = comp._route.path[#comp._route.path]
                endNode = routeData.nodes[last_id]
            end
            if endNode and endNode.east and endNode.north then
                local linkColor = routeColor
                if comp._selectedEndRampKey then
                    linkColor = {1.0, 0.6, 0.25, 1}
                end
                draw_route_L(project, endNode, comp._endRamp, routeShadow, linkColor)
            end
        end

        if comp._data and comp._data.ramps then
            local ramp_filter = helpers.isRampSuitableFor738
            local showLabels = (comp.zoom or 1) >= 1.5
            for _, ramp in ipairs(comp._data.ramps) do
                if ramp_filter and not ramp_filter(ramp) then
                    goto continue
                end
                local rtype = string.lower(ramp.ramp_type or "")
                if rtype == "gate" and ramp.east and ramp.north then
                    if ramp._draw_link_east == nil then
                        local proj = nil
                        if ramp.heading ~= nil then
                            proj = find_heading_edge_projection(
                                comp._data,
                                ramp.east,
                                ramp.north,
                                ramp.heading,
                                { disallow_runway_edges = true, radius_m = 150, angle_deg = 60 }
                            )
                        end
                        if not proj then
                            proj = find_nearest_edge_projection(
                                comp._data,
                                ramp.east,
                                ramp.north,
                                { disallow_runway_edges = true }
                            )
                        end
                        if proj and proj.edge then
                            ramp._draw_link_east = proj.proj_east
                            ramp._draw_link_north = proj.proj_north
                        else
                            ramp._draw_link_east = false
                            ramp._draw_link_north = false
                        end
                    end
                    if ramp._draw_link_east and ramp._draw_link_north then
                        local x1, y1 = project(ramp.east, ramp.north)
                        local x2, y2 = project(ramp._draw_link_east, ramp._draw_link_north)
                        sasl.gl.drawLine(x1, y1, x2, y2, {0.9, 0.82, 0.2, 0.6})
                    end
                end
                local key = ramp_key(ramp)
                local isSelected = (comp._selectedEndRampKey ~= nil) and (key == comp._selectedEndRampKey)
                local x, y = project(ramp.east, ramp.north)
                local color = rampColor
                local size = 4
                if rtype == "gate" then
                    color = rampGateColor
                end
                if isSelected then
                    color = endColor
                    size = 6
                end
                drawRectangle(x - size * 0.5, y - size * 0.5, size, size, color)
                if showLabels and ramp.name and ramp.name ~= "" then
                    local label = short_ramp_label(ramp)
                    if label ~= "" then
                        drawText(font, x + 4, y + 2, label, mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
                    end
                end
                if comp.mode == 1 then
                    layout.ramps[#layout.ramps + 1] = { x = x, y = y, key = key }
                end
                ::continue::
            end
        end

        if comp.mode == 0 and comp._depEntryCandidates and comp._data and comp._data.nodes then
            local showLabels = (comp.zoom or 1) >= 1.5
            for idx, cand in ipairs(comp._depEntryCandidates) do
                local node = comp._data.nodes[cand.id]
                if node and node.east and node.north then
                    local x, y = project(node.east, node.north)
                    local isSelected = (comp._selectedDepEntryId == cand.id)
                    local color = isSelected and endColor or {0.85, 0.65, 0.2, 1}
                    local size = isSelected and 7 or 5
                    drawRectangle(x - size * 0.5, y - size * 0.5, size, size, color)
                    if showLabels then
                        local label = (comp._depEntryLabels and comp._depEntryLabels[cand.id]) or ""
                        if label == "" then
                            label = "E" .. tostring(idx)
                        end
                        drawText(font, x + 5, y + 2, label, mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
                    end
                    layout.dep_entries[#layout.dep_entries + 1] = { x = x, y = y, id = cand.id }
                end
            end
        end

        local show_edit_handles = comp._editRoute and comp._editHandles and #comp._editHandles > 0
        if comp._startPoint and not show_edit_handles then
            local sx, sy = project(comp._startPoint.east, comp._startPoint.north)
            drawRectangle(sx - 3, sy - 3, 6, 6, startColor)
            drawText(font, sx + 5, sy + 2, "S", mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
        end
        if show_edit_handles then
            for i, handle in ipairs(comp._editHandles) do
                if handle and handle.east ~= nil and handle.north ~= nil then
                    local wx, wy = project(handle.east, handle.north)
                    local size = 5
                    local color = {0.7, 0.9, 0.3, 1}
                    local label = nil
                    if handle.kind == "start" then
                        size = 8
                        color = startColor
                        label = "S"
                    elseif handle.kind == "end" then
                        size = 8
                        color = endColor
                        label = "E"
                    elseif handle.kind == "manual" then
                        size = 7
                        color = {0.3, 0.8, 0.9, 1}
                        if handle.wp_idx then
                            label = "V" .. tostring(handle.wp_idx)
                        else
                            label = "V"
                        end
                    end
                    drawRectangle(wx - size * 0.5, wy - size * 0.5, size, size, color)
                    if label then
                        drawText(font, wx + size * 0.6, wy + 2, label, mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
                    end
                    layout.waypoints[#layout.waypoints + 1] = { x = wx, y = wy, handle_idx = i }
                end
            end
        elseif comp._routeWaypoints and #comp._routeWaypoints > 0 then
            for i, wp in ipairs(comp._routeWaypoints) do
                if wp and wp.east and wp.north then
                    local wx, wy = project(wp.east, wp.north)
                    drawRectangle(wx - 3, wy - 3, 6, 6, {0.7, 0.9, 0.3, 1})
                    drawText(font, wx + 5, wy + 2, "V" .. tostring(i), mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
                    layout.waypoints[#layout.waypoints + 1] = { x = wx, y = wy, idx = i }
                end
            end
        end
        if not show_edit_handles then
            if (not comp._drawFreehand) and comp._selectedEndRampKey
                and comp._endRamp and comp._endRamp.east and comp._endRamp.north then
                local ex, ey = project(comp._endRamp.east, comp._endRamp.north)
                drawRectangle(ex - 4, ey - 4, 8, 8, endColor)
                drawText(font, ex + 6, ey + 2, "E", mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
            elseif comp._endPoint then
                local ex, ey = project(comp._endPoint.east, comp._endPoint.north)
                drawRectangle(ex - 3, ey - 3, 6, 6, endColor)
                drawText(font, ex + 5, ey + 2, "E", mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
            end
        end

        local function draw_aircraft_marker(axp, ayp)
            local outer = 10
            local inner = 6
            drawRectangle(axp - outer * 0.5, ayp - outer * 0.5, outer, outer, {0, 0, 0, 0.9})
            drawRectangle(axp - inner * 0.5, ayp - inner * 0.5, inner, inner, aircraftColor)
            drawText(font, axp + 7, ayp + 4, "AC", mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
        end

        if comp._aircraftPoint then
            local axp, ayp = project(comp._aircraftPoint.east, comp._aircraftPoint.north)
            draw_aircraft_marker(axp, ayp)
        else
            local yal = comp.yal or _G.yal
            if yal and yal.aircraftlatpos and yal.aircraftlonpos then
                local lat = get(yal.aircraftlatpos)
                local lon = get(yal.aircraftlonpos)
                if is_valid_latlon(lat, lon) then
                    local ax, az = latlon_to_local(lat, lon)
                    if ax and az then
                        local axp, ayp = project(ax, az)
                        draw_aircraft_marker(axp, ayp)
                    end
                end
            end
        end

        local lineHeight = math.floor((mapFontSize or 12) * 1.25)
        local lineY = map.y + map.h - lineHeight - 2
        local lines = {}
        local info = string.format("Zoom %.2fx | Font %d | %s",
            comp.zoom or 1.0,
            math.floor(comp.fontSize + 0.5),
            (comp.orientation == 1) and "Heading Up" or "North Up")
        lines[#lines + 1] = info
        if comp._lastIcao then
            local modeLabel = (comp.mode == 1) and "ARR" or "DEP"
            lines[#lines + 1] = "ICAO " .. comp._lastIcao .. " | " .. modeLabel
        else
            lines[#lines + 1] = "ICAO n/a"
        end
        if comp._runwayName and comp._runwayName ~= "" then
            lines[#lines + 1] = "Runway " .. comp._runwayName
        else
            lines[#lines + 1] = "Runway n/a"
        end
        local gateLabel = ""
        if comp.mode == 1 then
            if comp._endRamp and comp._endRamp.name and comp._endRamp.name ~= "" then
                gateLabel = short_ramp_label(comp._endRamp)
            end
        else
            if comp._startRamp and comp._startRamp.name and comp._startRamp.name ~= "" then
                gateLabel = short_ramp_label(comp._startRamp)
            elseif comp._startIsAircraft then
                gateLabel = "Aircraft"
            end
        end
        if gateLabel ~= "" then
            lines[#lines + 1] = "Gate " .. gateLabel
        else
            lines[#lines + 1] = "Gate n/a"
        end

        for i = 1, #lines do
            drawText(font, map.x + 8, lineY - (i - 1) * lineHeight, lines[i], mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
        end

        if sasl.gl.resetClipArea then
            sasl.gl.resetClipArea()
        end

        -- Redraw header/toolbar and buttons on top to avoid map overdraw when zoomed.
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 1})
        drawRectangle(0, h - headerH - toolbarH, w, toolbarH, {0.08, 0.08, 0.08, 1})
        drawText(font, 8, h - headerH + 4, "Taxi Map", uiFontSize, TEXT_ALIGN_LEFT, {0.9, 0.9, 0.95, 1})
        drawText(font, w - 18, h - headerH + 4, "X", uiFontSize, TEXT_ALIGN_LEFT, {0.9, 0.5, 0.5, 1})
        for _, b in ipairs(layout.buttons) do
            local active = (b.action == "toggle_orient") and (comp.orientation == 1)
            if b.action == "toggle_edit" then
                active = comp._editRoute == true
            elseif b.action == "toggle_draw" then
                active = comp._drawRoute == true
            end
            drawButton(font, b, active, uiFontSize)
        end

        comp._layout = layout
    end

    function comp:onMouseDown(x, y, button, _, _)
        local layout = self._layout
        if not layout then
            return false
        end
        if not (button == MB_LEFT or button == 1) then
            return false
        end
        if layout.close then
            local c = layout.close
            if x >= c.x and x <= (c.x + c.w) and y >= c.y and y <= (c.y + c.h) then
                if self._window then
                    self._window:setIsVisible(false)
                else
                    set(self.visible, false)
                end
                log_taxi("TaxiWindow: close")
                return true
            end
        end
        for _, b in ipairs(self._buttons or layout.buttons or {}) do
            if x >= b.x and x <= (b.x + b.w) and y >= b.y and y <= (b.y + b.h) then
                if b.action == "toggle_mode" then
                    comp.mode = (comp.mode == 1) and 0 or 1
                    comp.modeOverride = true
                    comp._needsCenter = true
                    comp._lastUpdate = nil
                elseif b.action == "toggle_orient" then
                    comp.orientation = (comp.orientation == 1) and 0 or 1
                    commitSettings()
                elseif b.action == "zoom_in" then
                    comp.zoom = clamp(comp.zoom * zoomStep, minZoom, maxZoom)
                    commitSettings()
                elseif b.action == "zoom_out" then
                    comp.zoom = clamp(comp.zoom / zoomStep, minZoom, maxZoom)
                    commitSettings()
                elseif b.action == "fit" then
                    fit_to_bounds(comp._fitBounds, layout.map)
                    if comp._fitBounds and comp._aircraftPoint then
                        helpers.logInfoTS(
                            string.format(
                                "TaxiFit: mode=%s icao=%s bounds=[%.1f..%.1f, %.1f..%.1f] aircraft=%.1f/%.1f",
                                tostring(comp.mode),
                                tostring(comp._lastIcao or ""),
                                comp._fitBounds.minX or 0,
                                comp._fitBounds.maxX or 0,
                                comp._fitBounds.minY or 0,
                                comp._fitBounds.maxY or 0,
                                comp._aircraftPoint.east or 0,
                                comp._aircraftPoint.north or 0
                            )
                        )
                    end
                elseif b.action == "center" then
                    if not center_on_aircraft() then
                        if comp._fitBounds then
                            local cx, cy = compute_bounds_center(comp._fitBounds)
                            set_center(cx, cy)
                        end
                    end
                    commitSettings()
                elseif b.action == "auto_route" then
                    comp._editRoute = false
                    comp._drawRoute = false
                    comp._drawFreehand = false
                    comp._wpDrag = nil
                    comp._editHandles = nil
                    comp._editSuppressedNodes = nil
                    comp._editStartOverride = nil
                    comp._editEndOverride = nil
                    comp._routeWaypoints = {}
                    comp._route = nil
                    comp._routeErr = nil
                    comp._lastStartKey = nil
                    comp._lastEndKey = nil
                    comp._lastUpdate = nil
                    comp._undoState = nil
                    comp._undoReason = nil
                    log_taxi("TaxiRoute: auto-reset")
                elseif b.action == "font_down" then
                    comp.fontSize = clamp(comp.fontSize - 1, minFont, maxFont)
                    comp._fontHandle = nil
                    commitSettings()
                elseif b.action == "font_up" then
                    comp.fontSize = clamp(comp.fontSize + 1, minFont, maxFont)
                    comp._fontHandle = nil
                    commitSettings()
                elseif b.action == "toggle_edit" then
                    comp._editRoute = not comp._editRoute
                    if not comp._editRoute then
                        comp._drawRoute = false
                        comp._wpDrag = nil
                        comp._editHandles = nil
                        comp._editSuppressedNodes = nil
                    end
                    if comp._editRoute then
                        comp._editDirty = false
                        comp._editSuppressedNodes = {}
                        comp._editHandles = nil
                        clear_visual_guidance(comp, "edit-toggle")
                    end
                    log_taxi(
                        string.format(
                            "TaxiEdit: toggle edit=%s draw=%s route=%s waypoints=%d dirty=%s",
                            tostring(comp._editRoute),
                            tostring(comp._drawRoute),
                            tostring(comp._route ~= nil),
                            (comp._routeWaypoints and #comp._routeWaypoints) or 0,
                            tostring(comp._editDirty)
                        )
                    )
                elseif b.action == "toggle_draw" then
                    comp._drawRoute = not comp._drawRoute
                    if comp._drawRoute then
                        comp._editRoute = true
                        push_undo(comp, "draw-start")
                        comp._drawFreehand = true
                        comp._routeWaypoints = {}
                        comp._route = nil
                        comp._routeErr = nil
                        comp._lastUpdate = nil
                        comp._editDirty = false
                        comp._editSuppressedNodes = {}
                        comp._editHandles = nil
                        comp._editStartOverride = nil
                        comp._editEndOverride = nil
                    elseif not comp._routeWaypoints or #comp._routeWaypoints == 0 then
                        comp._drawFreehand = false
                    end
                    log_taxi(
                        string.format(
                            "TaxiDraw: toggle draw=%s edit=%s waypoints=%d",
                            tostring(comp._drawRoute),
                            tostring(comp._editRoute),
                            (comp._routeWaypoints and #comp._routeWaypoints) or 0
                        )
                    )
                elseif b.action == "undo_edit" then
                    if comp._undoState then
                        restore_edit_state(comp, comp._undoState)
                        mark_edit_dirty(comp)
                        log_taxi("TaxiEdit: undo reason=" .. tostring(comp._undoReason))
                    else
                        log_taxi("TaxiEdit: undo empty")
                    end
                elseif b.action == "clear_route" then
                    push_undo(comp, "clear-route")
                    comp._routeWaypoints = {}
                    comp._selectedEndRampKey = nil
                    comp._autoEndRampKey = nil
                    comp._editStartOverride = nil
                    comp._editEndOverride = nil
                    comp._drawFreehand = false
                    comp._editDirty = false
                    comp._editHandles = nil
                    comp._editSuppressedNodes = nil
                    comp._lastStartKey = nil
                    comp._lastEndKey = nil
                    comp._route = nil
                    comp._routeErr = nil
                    comp._lastUpdate = nil
                    log_taxi("TaxiEdit: clear-route")
                end
                return true
            end
        end
        if layout.ramps and comp.mode == 1 then
            local hitRadius = 8
            local hitD2 = hitRadius * hitRadius
            local best = nil
            local bestDist = nil
            for _, hit in ipairs(layout.ramps) do
                local dx = x - hit.x
                local dy = y - hit.y
                local d2 = dx * dx + dy * dy
                if d2 <= hitD2 and (not bestDist or d2 < bestDist) then
                    best = hit
                    bestDist = d2
                end
            end
            if best then
                if comp._selectedEndRampKey == best.key then
                    comp._selectedEndRampKey = nil
                    comp._autoEndRampKey = nil
                    log_taxi("TaxiEdit: end-ramp cleared")
                else
                    comp._selectedEndRampKey = best.key
                    comp._autoEndRampKey = nil
                    log_taxi("TaxiEdit: end-ramp selected key=" .. tostring(best.key))
                end
                comp._lastEndKey = nil
                comp._route = nil
                comp._routeErr = nil
                comp._lastUpdate = nil
                return true
            end
        end
        if layout.waypoints and comp._editRoute then
            local hitRadius = 8
            local hitRadiusAuto = 12
            local hitRadiusManual = 10
            local hitRadiusSE = 12
            local best = nil
            local bestDist = nil
            for _, hit in ipairs(layout.waypoints) do
                local radius = hitRadius
                if hit.handle_idx and comp._editHandles and comp._editHandles[hit.handle_idx] then
                    local h = comp._editHandles[hit.handle_idx]
                    if h then
                        if h.kind == "auto" then
                            radius = hitRadiusAuto
                        elseif h.kind == "start" or h.kind == "end" then
                            radius = hitRadiusSE
                        elseif h.kind == "manual" then
                            radius = hitRadiusManual
                        end
                    end
                end
                local hitD2 = radius * radius
                local dx = x - hit.x
                local dy = y - hit.y
                local d2 = dx * dx + dy * dy
                if d2 <= hitD2 and (not bestDist or d2 < bestDist) then
                    best = hit
                    bestDist = d2
                end
            end
            if best then
                if best.handle_idx and comp._editHandles and comp._editHandles[best.handle_idx] then
                    local handle = comp._editHandles[best.handle_idx]
                    if handle and handle.kind == "auto" then
                        push_undo(comp, "auto-handle")
                        log_taxi(
                            string.format(
                                "TaxiEdit: handle-down kind=auto seg=%s node=%s",
                                tostring(handle.segment_idx),
                                tostring(handle.node_id)
                            )
                        )
                        local auto_node_id = handle.node_id
                        if not comp._routeWaypoints then
                            comp._routeWaypoints = {}
                        end
                        local wlat = handle.lat
                        local wlon = handle.lon
                        if not is_valid_latlon(wlat, wlon) and handle.east ~= nil and handle.north ~= nil then
                            wlat, wlon = sasl.localToWorld(handle.east, 0, -handle.north)
                        end
                        if is_valid_latlon(wlat, wlon) then
                            local wp = {
                                lat = wlat,
                                lon = wlon,
                                east = handle.east,
                                north = handle.north,
                                segment_idx = handle.segment_idx
                            }
                            local new_idx = insert_waypoint_sorted(comp._routeWaypoints, wp)
                            handle.kind = "manual"
                            handle.wp_idx = new_idx
                            handle.node_id = nil
                            log_taxi(
                                string.format(
                                    "TaxiEdit: auto->manual wp=%d seg=%s",
                                    tonumber(new_idx or -1),
                                    tostring(handle.segment_idx)
                                )
                            )
                            comp._wpDrag = {
                                handle_idx = best.handle_idx,
                                kind = "manual",
                                wp_idx = new_idx,
                                segment_idx = handle.segment_idx,
                                startX = x,
                                startY = y,
                                moved = false,
                                from_auto = true,
                                auto_node_id = auto_node_id
                            }
                        end
                    else
                        push_undo(comp, "handle-down")
                        log_taxi(
                            string.format(
                                "TaxiEdit: handle-down kind=%s wp=%s seg=%s node=%s",
                                tostring(handle and handle.kind or "nil"),
                                tostring(handle and handle.wp_idx or "nil"),
                                tostring(handle and handle.segment_idx or "nil"),
                                tostring(handle and handle.node_id or "nil")
                            )
                        )
                        comp._wpDrag = {
                            handle_idx = best.handle_idx,
                            kind = handle.kind,
                            wp_idx = handle.wp_idx,
                            segment_idx = handle.segment_idx,
                            node_id = handle.node_id,
                            startX = x,
                            startY = y,
                            moved = false
                        }
                    end
                else
                    push_undo(comp, "handle-down")
                    log_taxi(
                        string.format(
                            "TaxiEdit: handle-down kind=manual wp=%s",
                            tostring(best.idx)
                        )
                    )
                    comp._wpDrag = {
                        kind = "manual",
                        wp_idx = best.idx,
                        startX = x,
                        startY = y,
                        moved = false
                    }
                end
                return true
            end
        end
        if layout.dep_entries and comp.mode == 0 then
            local hitRadius = 8
            local hitD2 = hitRadius * hitRadius
            local best = nil
            local bestDist = nil
            for _, hit in ipairs(layout.dep_entries) do
                local dx = x - hit.x
                local dy = y - hit.y
                local d2 = dx * dx + dy * dy
                if d2 <= hitD2 and (not bestDist or d2 < bestDist) then
                    best = hit
                    bestDist = d2
                end
            end
            if best then
                if comp._selectedDepEntryId == best.id then
                    comp._selectedDepEntryId = nil
                    log_taxi("TaxiEdit: dep-entry cleared")
                else
                    comp._selectedDepEntryId = best.id
                    log_taxi("TaxiEdit: dep-entry selected id=" .. tostring(best.id))
                end
                comp._lastEndKey = nil
                comp._route = nil
                comp._routeErr = nil
                comp._lastUpdate = nil
                return true
            end
        end
        if layout.map then
            local m = layout.map
            if x >= m.x and x <= (m.x + m.w) and y >= m.y and y <= (m.y + m.h) then
                if comp._editRoute and comp._mapTransform then
                    local t = comp._mapTransform
                    local function project(east, north)
                        local dx = (east or 0) - t.centerEast
                        local dy = (north or 0) - t.centerNorth
                        dx, dy = rotate_point(dx, dy, t.rot)
                        local sx = t.mapX + t.mapW * 0.5 + dx * t.scale + (t.panX or 0)
                        local sy = t.mapY + t.mapH * 0.5 + dy * t.scale + (t.panY or 0)
                        return sx, sy
                    end
                    local function screen_to_world(sx, sy)
                        local dx = (sx - (t.mapX + t.mapW * 0.5) - (t.panX or 0)) / (t.scale or 1)
                        local dy = (sy - (t.mapY + t.mapH * 0.5) - (t.panY or 0)) / (t.scale or 1)
                        dx, dy = rotate_point(dx, dy, -t.rot)
                        return t.centerEast + dx, t.centerNorth + dy
                    end
                if comp._drawRoute then
                    local function add_waypoint_freehand()
                        local we, wn = screen_to_world(x, y)
                        local wlat, wlon = sasl.localToWorld(we, 0, -wn)
                        if is_valid_latlon(wlat, wlon) then
                            if not comp._routeWaypoints then
                                comp._routeWaypoints = {}
                            end
                            push_undo(comp, "draw-add")
                            table.insert(comp._routeWaypoints, {
                                lat = wlat,
                                lon = wlon,
                                east = we,
                                north = wn,
                                segment_idx = nil
                            })
                            mark_edit_dirty(comp)
                            log_taxi(
                                string.format(
                                    "TaxiDraw: add-waypoint-free lat=%.6f lon=%.6f total=%d",
                                    wlat,
                                    wlon,
                                    #comp._routeWaypoints
                                )
                            )
                            return true
                        end
                        return false
                    end

                    local function add_waypoint_nearest_edge()
                        local we, wn = screen_to_world(x, y)
                        local proj = find_nearest_edge_projection(comp._data, we, wn, { disallow_runway_edges = false })
                        if proj and proj.edge then
                                local wlat, wlon = sasl.localToWorld(proj.proj_east, 0, -proj.proj_north)
                                if is_valid_latlon(wlat, wlon) then
                                    if not comp._routeWaypoints then
                                        comp._routeWaypoints = {}
                                    end
                                    push_undo(comp, "draw-add")
                                    table.insert(comp._routeWaypoints, {
                                        lat = wlat,
                                        lon = wlon,
                                        east = proj.proj_east,
                                        north = proj.proj_north,
                                        segment_idx = nil
                                    })
                                    mark_edit_dirty(comp)
                                    log_taxi(
                                        string.format(
                                            "TaxiDraw: add-waypoint lat=%.6f lon=%.6f total=%d",
                                            wlat,
                                            wlon,
                                            #comp._routeWaypoints
                                        )
                                    )
                                    return true
                                end
                        end
                        return false
                    end

                    if comp._drawFreehand then
                        return add_waypoint_freehand()
                    end

                    if comp._route and comp._route.path and comp._route.data then
                        local routeData = comp._route.data
                        local path = comp._route.path
                            local best_idx = nil
                            local best_d2 = nil
                            local best_t = 0
                            for i = 1, #path - 1 do
                                local n1 = routeData.nodes[path[i]]
                                local n2 = routeData.nodes[path[i + 1]]
                                if n1 and n2 then
                                    local x1, y1 = project(n1.east, n1.north)
                                    local x2, y2 = project(n2.east, n2.north)
                                    local px, py, tt = project_point_to_segment(x, y, x1, y1, x2, y2)
                                    local d2 = distance_sq(x, y, px, py)
                                    if not best_d2 or d2 < best_d2 then
                                        best_d2 = d2
                                        best_idx = i
                                        best_t = tt
                                    end
                                end
                            end
                            if best_idx and best_d2 and best_d2 <= 100 then
                                local n1 = routeData.nodes[path[best_idx]]
                                local n2 = routeData.nodes[path[best_idx + 1]]
                                if n1 and n2 then
                                    local we = n1.east + (n2.east - n1.east) * best_t
                                    local wn = n1.north + (n2.north - n1.north) * best_t
                                    local wlat, wlon = sasl.localToWorld(we, 0, -wn)
                                    if is_valid_latlon(wlat, wlon) then
                                        if not comp._routeWaypoints then
                                            comp._routeWaypoints = {}
                                        end
                                        push_undo(comp, "draw-insert")
                                        table.insert(comp._routeWaypoints, {
                                            lat = wlat,
                                            lon = wlon,
                                            east = we,
                                            north = wn,
                                            segment_idx = nil
                                        })
                                        mark_edit_dirty(comp)
                                        log_taxi(
                                            string.format(
                                                "TaxiDraw: insert-waypoint seg=%s lat=%.6f lon=%.6f total=%d",
                                                tostring(best_idx),
                                                wlat,
                                                wlon,
                                                #comp._routeWaypoints
                                            )
                                        )
                                        return true
                                    end
                                end
                            end
                        end
                        return add_waypoint_nearest_edge()
                    elseif comp._route and comp._route.path and comp._route.data then
                        local routeData = comp._route.data
                        local path = comp._route.path
                        local best_idx = nil
                        local best_d2 = nil
                        local best_t = 0
                        for i = 1, #path - 1 do
                            local n1 = routeData.nodes[path[i]]
                            local n2 = routeData.nodes[path[i + 1]]
                            if n1 and n2 then
                                local x1, y1 = project(n1.east, n1.north)
                                local x2, y2 = project(n2.east, n2.north)
                                local px, py, tt = project_point_to_segment(x, y, x1, y1, x2, y2)
                                local d2 = distance_sq(x, y, px, py)
                                if not best_d2 or d2 < best_d2 then
                                    best_d2 = d2
                                    best_idx = i
                                    best_t = tt
                                end
                            end
                        end
                        if best_idx and best_d2 and best_d2 <= 100 then
                            local n1 = routeData.nodes[path[best_idx]]
                            local n2 = routeData.nodes[path[best_idx + 1]]
                            if n1 and n2 then
                                local we = n1.east + (n2.east - n1.east) * best_t
                                local wn = n1.north + (n2.north - n1.north) * best_t
                                local wlat, wlon = sasl.localToWorld(we, 0, -wn)
                                if is_valid_latlon(wlat, wlon) then
                                    if not comp._routeWaypoints then
                                        comp._routeWaypoints = {}
                                    end
                                    push_undo(comp, "edit-insert")
                                    insert_waypoint_sorted(comp._routeWaypoints, {
                                        lat = wlat,
                                        lon = wlon,
                                        east = we,
                                        north = wn,
                                        segment_idx = best_idx
                                    })
                                    mark_edit_dirty(comp)
                                    log_taxi(
                                        string.format(
                                            "TaxiEdit: insert-waypoint seg=%s lat=%.6f lon=%.6f total=%d",
                                            tostring(best_idx),
                                            wlat,
                                            wlon,
                                            #comp._routeWaypoints
                                        )
                                    )
                                    return true
                                end
                            end
                        end
                    end
                end
                local resizeMargin = 12
                local dragX1 = m.x + resizeMargin
                local dragY1 = m.y + resizeMargin
                local dragX2 = m.x + m.w - resizeMargin
                local dragY2 = m.y + m.h - resizeMargin
                if dragX2 <= dragX1 or dragY2 <= dragY1 then
                    dragX1 = m.x
                    dragY1 = m.y
                    dragX2 = m.x + m.w
                    dragY2 = m.y + m.h
                end
                if x >= dragX1 and x <= dragX2 and y >= dragY1 and y <= dragY2 then
                    comp.drag = { startX = x, startY = y, panX = comp.panX, panY = comp.panY }
                    return true
                end
                return false
            end
        end
        return false
    end

    function comp:onMouseMove(x, y, _, _, _)
        if comp._wpDrag then
            local drag = comp._wpDrag
            local dx = x - drag.startX
            local dy = y - drag.startY
            if (dx * dx + dy * dy) >= (waypointDragPixels * waypointDragPixels) then
                drag.moved = true
            end
            if drag.moved and comp._mapTransform and comp._data then
                local t = comp._mapTransform
                local function screen_to_world(sx, sy)
                    local ddx = (sx - (t.mapX + t.mapW * 0.5) - (t.panX or 0)) / (t.scale or 1)
                    local ddy = (sy - (t.mapY + t.mapH * 0.5) - (t.panY or 0)) / (t.scale or 1)
                    ddx, ddy = rotate_point(ddx, ddy, -t.rot)
                    return t.centerEast + ddx, t.centerNorth + ddy
                end
                local we, wn = screen_to_world(x, y)
                local is_start_end = (drag.kind == "start" or drag.kind == "end")
                local use_freehand = (comp._drawFreehand == true)
                local proj = nil
                if not use_freehand then
                    proj = find_nearest_edge_projection(comp._data, we, wn, { disallow_runway_edges = false })
                end
                local target_east = nil
                local target_north = nil
                if use_freehand then
                    target_east = we
                    target_north = wn
                elseif is_start_end then
                    local snap_ok = (proj and proj.edge and proj.d2 and proj.d2 <= (startEndSnapMeters * startEndSnapMeters))
                    if snap_ok then
                        target_east = proj.proj_east
                        target_north = proj.proj_north
                    else
                        target_east = we
                        target_north = wn
                    end
                else
                    if not (proj and proj.edge) then
                        return true
                    end
                    target_east = proj.proj_east
                    target_north = proj.proj_north
                end
                if target_east ~= nil and target_north ~= nil then
                    local wlat, wlon = sasl.localToWorld(target_east, 0, -target_north)
                    if (not is_valid_latlon(wlat, wlon)) and (not use_freehand) and proj and proj.edge then
                        target_east = proj.proj_east
                        target_north = proj.proj_north
                        wlat, wlon = sasl.localToWorld(target_east, 0, -target_north)
                    end
                    if is_valid_latlon(wlat, wlon) then
                        drag.lastLat = wlat
                        drag.lastLon = wlon
                        drag.lastEast = target_east
                        drag.lastNorth = target_north
                        local handle = (drag.handle_idx and comp._editHandles) and comp._editHandles[drag.handle_idx] or nil
                        if handle then
                            handle.east = target_east
                            handle.north = target_north
                            handle.lat = wlat
                            handle.lon = wlon
                        end
                        if drag.kind == "start" then
                            local prev_start = comp._editStartOverride
                            comp._editStartOverride = { lat = wlat, lon = wlon, mode = comp.mode, icao = comp._lastIcao }
                            local sync_start = comp._drawRoute
                            if not sync_start and prev_start and comp._routeWaypoints and #comp._routeWaypoints > 0 then
                                sync_start = waypoint_matches_override(comp._routeWaypoints[1], prev_start)
                            end
                            if sync_start and comp._routeWaypoints and #comp._routeWaypoints > 0 then
                                local wp = comp._routeWaypoints[1]
                                if wp then
                                    wp.lat = wlat
                                    wp.lon = wlon
                                    wp.east = target_east
                                    wp.north = target_north
                                    wp.segment_idx = nil
                                end
                            end
                        elseif drag.kind == "end" then
                            local prev_end = comp._editEndOverride
                            comp._editEndOverride = { lat = wlat, lon = wlon, mode = comp.mode, icao = comp._lastIcao }
                            local sync_end = comp._drawRoute
                            if not sync_end and prev_end and comp._routeWaypoints and #comp._routeWaypoints > 0 then
                                sync_end = waypoint_matches_override(comp._routeWaypoints[#comp._routeWaypoints], prev_end)
                            end
                            if sync_end and comp._routeWaypoints and #comp._routeWaypoints > 0 then
                                local wp = comp._routeWaypoints[#comp._routeWaypoints]
                                if wp then
                                    wp.lat = wlat
                                    wp.lon = wlon
                                    wp.east = target_east
                                    wp.north = target_north
                                    wp.segment_idx = nil
                                end
                            end
                        else
                            if drag.kind == "auto" and not drag.wp_idx then
                                if not comp._routeWaypoints then
                                    comp._routeWaypoints = {}
                                end
                                local wp = {
                                    lat = wlat,
                                    lon = wlon,
                                    east = target_east,
                                    north = target_north,
                                    segment_idx = drag.segment_idx
                                }
                                local new_idx = insert_waypoint_sorted(comp._routeWaypoints, wp)
                                drag.wp_idx = new_idx
                                drag.kind = "manual"
                                if handle then
                                    handle.kind = "manual"
                                    handle.wp_idx = new_idx
                                    handle.node_id = nil
                                end
                                if drag.node_id then
                                    comp._editSuppressedNodes = comp._editSuppressedNodes or {}
                                    comp._editSuppressedNodes[drag.node_id] = true
                                end
                            end
                            if drag.wp_idx and comp._routeWaypoints and comp._routeWaypoints[drag.wp_idx] then
                                local wp = comp._routeWaypoints[drag.wp_idx]
                                wp.lat = wlat
                                wp.lon = wlon
                                wp.east = target_east
                                wp.north = target_north
                                wp.segment_idx = nil
                            end
                        end
                        mark_edit_dirty(comp)
                        if drag.from_auto and drag.auto_node_id and not drag.suppressed then
                            comp._editSuppressedNodes = comp._editSuppressedNodes or {}
                            if not comp._editSuppressedNodes[drag.auto_node_id] then
                                log_taxi("TaxiEdit: suppress-auto node=" .. tostring(drag.auto_node_id))
                            end
                            comp._editSuppressedNodes[drag.auto_node_id] = true
                            drag.suppressed = true
                        end
                    end
                end
            end
            return true
        end
        if comp.drag then
            local dx = x - comp.drag.startX
            local dy = y - comp.drag.startY
            comp.panX = comp.drag.panX + dx
            comp.panY = comp.drag.panY + dy
            return true
        end
        return false
    end

    function comp:onMouseUp(_, _, button, _, _)
        if (button == MB_LEFT or button == 1) and comp._wpDrag then
            local drag = comp._wpDrag
            comp._wpDrag = nil
            if not drag.moved then
                if drag.from_auto and drag.auto_node_id then
                    if drag.wp_idx and comp._routeWaypoints and comp._routeWaypoints[drag.wp_idx] then
                        table.remove(comp._routeWaypoints, drag.wp_idx)
                    end
                    comp._editSuppressedNodes = comp._editSuppressedNodes or {}
                    comp._editSuppressedNodes[drag.auto_node_id] = true
                    mark_edit_dirty(comp)
                    log_taxi(
                        string.format(
                            "TaxiEdit: auto-handle suppressed node=%s",
                            tostring(drag.auto_node_id)
                        )
                    )
                elseif drag.kind == "manual" and drag.wp_idx then
                    if comp._routeWaypoints and comp._routeWaypoints[drag.wp_idx] then
                        table.remove(comp._routeWaypoints, drag.wp_idx)
                        mark_edit_dirty(comp)
                        log_taxi(
                            string.format(
                                "TaxiEdit: waypoint deleted wp=%s",
                                tostring(drag.wp_idx)
                            )
                        )
                    end
                end
            else
                if drag.from_auto and drag.auto_node_id then
                    comp._editSuppressedNodes = comp._editSuppressedNodes or {}
                    if not comp._editSuppressedNodes[drag.auto_node_id] then
                        log_taxi("TaxiEdit: suppress-auto node=" .. tostring(drag.auto_node_id))
                    end
                    comp._editSuppressedNodes[drag.auto_node_id] = true
                end
                if drag.kind == "start" then
                    log_taxi(
                        string.format(
                            "TaxiEdit: start-move lat=%.6f lon=%.6f",
                            tonumber(drag.lastLat or 0),
                            tonumber(drag.lastLon or 0)
                        )
                    )
                elseif drag.kind == "end" then
                    log_taxi(
                        string.format(
                            "TaxiEdit: end-move lat=%.6f lon=%.6f",
                            tonumber(drag.lastLat or 0),
                            tonumber(drag.lastLon or 0)
                        )
                    )
                else
                    log_taxi(
                        string.format(
                            "TaxiEdit: waypoint moved kind=%s wp=%s lat=%.6f lon=%.6f",
                            tostring(drag.kind),
                            tostring(drag.wp_idx),
                            tonumber(drag.lastLat or 0),
                            tonumber(drag.lastLon or 0)
                        )
                    )
                end
            end
            return true
        end
        if (button == MB_LEFT or button == 1) and comp.drag then
            comp.drag = nil
            return true
        end
        return false
    end

    function comp:onMouseWheel(x, y, _, _, _, clicks)
        if clicks == nil or clicks == 0 then
            return false
        end
        local layout = self._layout
        if layout and layout.map then
            local m = layout.map
            if x >= m.x and x <= (m.x + m.w) and y >= m.y and y <= (m.y + m.h) then
                if clicks > 0 then
                    comp.zoom = clamp(comp.zoom * zoomStep, minZoom, maxZoom)
                else
                    comp.zoom = clamp(comp.zoom / zoomStep, minZoom, maxZoom)
                end
                commitSettings()
                return true
            end
        end
        return false
    end

    function comp:update()
        return
    end

    function comp:onKeyDown(_, _, _, _, _, _)
        return false
    end

    function comp:onKeyUp(_, _, _, _, _, _)
        return false
    end

    function comp:updateTaxiState(map)
        local comp = self
        local U = comp._U or {}
        local C = comp._C or {}
        local def = comp._def
        local helpers = comp._helpers
        local log_taxi = comp._logTaxi
        local normalize_icao = U.normalize_icao
        local is_valid_latlon = U.is_valid_latlon
        local latlon_to_local = U.latlon_to_local
        local distance_meters_latlon = U.distance_meters_latlon
        local ramp_key = U.ramp_key
        local short_ramp_label = U.short_ramp_label
        local compute_runway_landing_profile = U.compute_runway_landing_profile
        local find_runway_entry = U.find_runway_entry
        local find_holdshort_node_near = U.find_holdshort_node_near
        local nearest_node_info = U.nearest_node_info
        local nearest_non_runway_node = U.nearest_non_runway_node
        local find_nearest_edge_projection = U.find_nearest_edge_projection
        local find_heading_edge_projection = U.find_heading_edge_projection
        local find_preferred_edge_projection = U.find_preferred_edge_projection
        local build_projected_data = U.build_projected_data
        local distance_to_route = U.distance_to_route
        local distance_to_segments = U.distance_to_segments
        local build_runway_backtrack_segments = U.build_runway_backtrack_segments
        local select_runway_exit_node = U.select_runway_exit_node
        local route_with_waypoints = U.route_with_waypoints
        local try_route_from_candidates = U.try_route_from_candidates
        local try_route_to_candidates = U.try_route_to_candidates
        local collect_nearest_nodes = U.collect_nearest_nodes
        local compute_along_perp = U.compute_along_perp
        local build_route_labels = U.build_route_labels
        local find_runway_entry_label = U.find_runway_entry_label
        local get_edge_label = U.get_edge_label
        local find_nearest_segment = U.find_nearest_segment
        local normalize_runway_name = U.normalize_runway_name
        local parse_runway_parts = U.parse_runway_parts
        local copy_opts = U.copy_opts
        local log_full_route_state = U.log_full_route_state
        local normalize_words = U.normalize_words
        local guidance_distance_for_speed = U.guidance_distance_for_speed
        local get_node_degree = U.get_node_degree
        local emit_guidance = U.emit_guidance
        local arrival_grace_active = U.arrival_grace_active
        local runway_label_voice = U.runway_label_voice
        local build_visual_label = U.build_visual_label
        local is_auto_taxi_guidance_enabled = U.is_auto_taxi_guidance_enabled
        local clear_visual_guidance = U.clear_visual_guidance
        local update_visual_guidance = U.update_visual_guidance
        local maybe_force_global_for_quality = U.maybe_force_global_for_quality
        local maybe_speak_guidance = U.maybe_speak_guidance
        local updateInterval = C.updateInterval or 1.0
        local startRampMaxMeters = C.startRampMaxMeters or 80
        local rerouteCooldown = C.rerouteCooldown or 6
        local rerouteDriftMeters = C.rerouteDriftMeters or 40
        local guidanceMinSpeed = C.guidanceMinSpeed or 1
        local guidanceTurnDistance = C.guidanceTurnDistance or 80
        local guidanceTurnAngle = C.guidanceTurnAngle or 20
        local guidanceLeadTimeSec = C.guidanceLeadTimeSec or 12
        local guidanceMaxDistance = C.guidanceMaxDistance or 180
        local guidanceStraightAngle = C.guidanceStraightAngle or 10
        local runwayRouteMaxSpeed = 45
        local depThresholdGateMeters = 60
        local depThresholdHeadingLimit = 25
        local depTakeoffLatchSpeed = 25
        local depTakeoffLatchHoldSec = 2.0
        local depRunwayCorridorMin = 25
        local depRunwayCorridorMax = 80
        local depRunwayCorridorBuffer = 10
        local arrStartNodeMaxMeters = 180
        local tuning = comp._tuning or {}
        local now = 0
        if comp._timer then
            now = sasl.getElapsedSeconds(comp._timer) or 0
        end
        local in_edit = comp._editRoute or comp._drawRoute
        if comp._lastUpdate and (now - comp._lastUpdate) < updateInterval then
            return
        end
        comp._lastUpdate = now

        -- Always refresh aircraft position for display, even in edit/draw mode.
        local yal = comp.yal or _G.yal
        if yal and yal.aircraftlatpos and yal.aircraftlonpos then
            local alat = get(yal.aircraftlatpos)
            local alon = get(yal.aircraftlonpos)
            if is_valid_latlon(alat, alon) then
                local ae, an = latlon_to_local(alat, alon)
                if ae and an then
                    comp._aircraftPoint = { east = ae, north = an }
                end
            end
        end

        if in_edit then
            clear_visual_guidance(comp, "edit")
            comp._visualGuidanceQueue = {}
        end

        if not yal then
            comp._dataErr = "yal-not-ready"
            return
        end

        local depIcao = nil
        if yal.depicao then
            depIcao = normalize_icao(get(yal.depicao) or "")
            if not helpers.isvalidicao(depIcao) then
                depIcao = nil
            end
        end
        local desIcao = nil
        if yal.desicao then
            desIcao = normalize_icao(get(yal.desicao) or "")
            if not helpers.isvalidicao(desIcao) then
                desIcao = nil
            end
        end
        if desIcao and desIcao ~= comp._lastArrivalIcao then
            comp._lastArrivalRunwayName = nil
            comp._lastArrivalRunwayLat = nil
            comp._lastArrivalRunwayLon = nil
        end
        if desIcao then
            comp._lastArrivalIcao = desIcao
        end
        local onGroundSensor = yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
        local airborne = yal.airgroundsensor and (get(yal.airgroundsensor) == def.OFF)
        if yal.flightstate == def.FLIGHTSTATEPREFLIGHT and depIcao then
            comp._lastArrivalIcao = nil
            comp._lastArrivalRunwayName = nil
            comp._lastArrivalRunwayLat = nil
            comp._lastArrivalRunwayLon = nil
        end

        local autoMode = comp.mode or 0
        if yal.flightstate ~= nil then
            if yal.flightstate == def.FLIGHTSTATEPREFLIGHT then
                autoMode = 0
                if not depIcao and comp._lastArrivalIcao and onGroundSensor then
                    autoMode = 1
                end
            else
                autoMode = 1
            end
        end
        -- After takeoff, force ARR mode and suppress DEP routing.
        if airborne then
            autoMode = 1
            if comp.mode == 0 then
                comp.modeOverride = false
                comp.mode = 1
            end
        end
        comp.autoMode = autoMode
        if not comp.modeOverride then
            comp.mode = autoMode
        elseif comp.mode == autoMode then
            comp.modeOverride = false
        end

        local mode = comp.mode or autoMode
        if mode == 1 and onGroundSensor then
            if not comp._arrOnGroundSince then
                comp._arrOnGroundSince = now
                if comp._quality then
                    comp._quality.rerouteEvents = {}
                    comp._quality.badSince = nil
                    comp._quality.distBadSince = nil
                end
            end
        else
            comp._arrOnGroundSince = nil
        end
        local nearestIcao = nil
        if yal.nearesticao then
            local nearest = normalize_icao(get(yal.nearesticao) or "")
            if helpers.isvalidicao(nearest) then
                nearestIcao = nearest
            end
        end
        local icao = nil
        if mode == 0 then
            icao = depIcao
            if not helpers.isvalidicao(icao or "") and nearestIcao then
                icao = nearestIcao
            end
        else
            icao = desIcao
            if not helpers.isvalidicao(icao or "") and comp._lastArrivalIcao then
                icao = comp._lastArrivalIcao
            end
            if not helpers.isvalidicao(icao or "") and onGroundSensor and nearestIcao then
                icao = nearestIcao
            end
        end

        if not helpers.isvalidicao(icao or "") then
            comp._data = nil
            comp._route = nil
            comp._dataErr = "invalid-icao"
            comp._routeErr = nil
            comp._lastIcao = nil
            comp._fitBounds = nil
            comp._runwayName = nil
            clear_visual_guidance(comp, "invalid-icao")
            comp._visualGuidanceQueue = {}
            comp._drawFreehand = false
            comp._arrOffRunwayHandled = false
            log_taxi("TaxiRoute: abort invalid-icao")
            return
        end

        local prev_icao_valid = helpers.isvalidicao(comp._lastIcao or "")
        local prev_start_override = comp._editStartOverride
        local prev_end_override = comp._editEndOverride
        local prev_waypoints = comp._routeWaypoints
        local prev_draw_freehand = comp._drawFreehand
        local icao_changed = (comp._lastIcao ~= icao)
        local mode_changed = (comp._lastMode ~= mode)
        if icao_changed or mode_changed then
            comp._needsCenter = true
            comp._route = nil
            comp._routeErr = nil
            comp._routeLabels = nil
            comp._routeLabelStats = nil
            comp._lastRouteDist = nil
            comp._startPoint = nil
            comp._endPoint = nil
            comp._startRamp = nil
            comp._endRamp = nil
            comp._lastStartKey = nil
            comp._lastEndKey = nil
            comp._routeStartAnchor = nil
            comp._routeExtraSegments = nil
            comp._lastGuidanceNodeId = nil
            comp._lastGuidanceLabel = nil
            comp._lastGuidanceTime = nil
            clear_visual_guidance(comp, "reset")
            comp._visualGuidanceQueue = {}
            comp._editHandles = nil
            comp._editSuppressedNodes = nil
            comp._editDirty = false
            comp._editStartOverride = nil
            comp._editEndOverride = nil
            comp._drawFreehand = false
            comp._arrOffRunwayHandled = false
            comp._depRunwayEntryAnnounced = false
            comp._depTaxiCompleteAnnounced = false
            comp._arrTaxiCompleteAnnounced = false
            log_taxi(
                string.format(
                    "TaxiRoute: reset icao_changed=%s mode_changed=%s",
                    tostring(icao_changed),
                    tostring(mode_changed)
                )
            )
            if comp._quality then
                comp._quality.distBadSince = nil
                comp._quality.badSince = nil
                comp._quality.rerouteEvents = {}
            end
            comp._routeWaypoints = {}
            comp._rerouteOverride = nil
            comp._depThresholdLatched = false
            comp._takeoffLatchSince = nil
            comp._autoEndRampLowSpeedSince = nil
            comp._autoEndRampSwitchTime = nil
            if icao_changed or mode_changed then
                comp._autoEndRampKey = nil
            end
            if icao_changed then
                comp._selectedEndRampKey = nil
                comp._selectedDepEntryId = nil
                comp._data = nil
                comp._dataErr = nil
            end
            if icao_changed and (not prev_icao_valid) and (not mode_changed) then
                comp._editStartOverride = prev_start_override
                comp._editEndOverride = prev_end_override
                comp._routeWaypoints = prev_waypoints or {}
                comp._drawFreehand = prev_draw_freehand
            end
        end

        comp._lastIcao = icao
        comp._lastMode = mode

        local data = comp._data
        local derr = comp._dataErr
        local pending = (derr == "global-index-pending")
        if data and comp._taxiGlobalPending and comp._taxiGlobalPending[icao]
            and helpers.isGlobalAptIndexReady and helpers.isGlobalAptIndexReady() then
            comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
            comp._taxiSourceByIcao[icao] = "global"
            comp._taxiGlobalPending[icao] = nil
            comp._data = nil
            comp._dataErr = nil
            data = nil
            comp._route = nil
            comp._routeErr = nil
            comp._routeLabels = nil
            comp._routeLabelStats = nil
            comp._routeExtraSegments = nil
            comp._lastStartKey = nil
            comp._lastEndKey = nil
            comp._lastGuidanceNodeId = nil
            comp._lastGuidanceLabel = nil
            comp._lastGuidanceTime = nil
            comp._needsCenter = true
            comp._rerouteOverride = nil
            if comp._quality then
                comp._quality.badSince = nil
                comp._quality.distBadSince = nil
                comp._quality.rerouteEvents = {}
            end
        end
        derr = comp._dataErr
        pending = (derr == "global-index-pending")
        if icao_changed or (not data and (not derr or pending)) then
            local policy = comp._taxiSourceByIcao and comp._taxiSourceByIcao[icao] or nil
            if comp._taxiGlobalPending and comp._taxiGlobalPending[icao] and helpers.isGlobalAptIndexReady and helpers.isGlobalAptIndexReady() then
                policy = "global"
                comp._taxiSourceByIcao[icao] = "global"
                comp._taxiGlobalPending[icao] = nil
            end
            if helpers.getTaxiDataWithPolicy then
                data, derr = helpers.getTaxiDataWithPolicy(icao, policy)
            else
                data, derr = helpers.getTaxiData(icao)
            end
            pending = (derr == "global-index-pending")
        end
        if not data then
            comp._data = nil
            comp._dataErr = pending and "global-index-pending" or (derr or "apt-not-found")
            comp._fitBounds = nil
            comp._runwayName = nil
            comp._routeExtraSegments = nil
            clear_visual_guidance(comp, "no-data")
            comp._visualGuidanceQueue = {}
            return
        end
        comp._data = data
        comp._dataErr = nil
        if data and data.entry and data.entry.source == "addon"
            and data._labelsPatchPending
            and helpers.patchTaxiLabelsFromGlobalForIcao
            and helpers.isGlobalAptIndexReady
            and helpers.isGlobalAptIndexReady() then
            local patched = helpers.patchTaxiLabelsFromGlobalForIcao(data, icao, { log = true })
            if patched and patched > 0 then
                comp._routeLabels = nil
                comp._routeLabelStats = nil
                if comp._route and comp._route.path and comp._route.data == data then
                    comp._routeLabels = build_route_labels(data, comp._route.path)
                    comp._routeLabelStats = compute_route_label_stats(data, comp._route.path)
                end
                if comp._quality then
                    comp._quality.badSince = nil
                end
            end
        end
        local shifted, shift_dx, shift_dy = align_taxi_data_projection(data)
        if shifted then
            helpers.logInfoTS(
                string.format(
                    "TaxiProj: icao=%s shift=%.1f/%.1f refAlign=true",
                    tostring(icao),
                    shift_dx or 0,
                    shift_dy or 0
                )
            )
            comp._route = nil
            comp._routeErr = nil
            comp._routeLabels = nil
            comp._routeExtraSegments = nil
            comp._lastStartKey = nil
            comp._lastEndKey = nil
            comp._needsCenter = true
        end
        if comp._rampLinkCacheReset ~= data then
            if data.ramps then
                for _, ramp in ipairs(data.ramps) do
                    ramp._draw_link_east = nil
                    ramp._draw_link_north = nil
                end
            end
            comp._rampLinkCacheReset = data
        end
        comp._fitBounds = data.bounds

        local aircraft = nil
        local lat = yal.aircraftlatpos and get(yal.aircraftlatpos) or nil
        local lon = yal.aircraftlonpos and get(yal.aircraftlonpos) or nil
        if is_valid_latlon(lat, lon) then
            local east, north = latlon_to_local(lat, lon)
            if east and north then
                aircraft = { lat = lat, lon = lon, east = east, north = north }
            end
        end
        local nearest_ramp = nil
        local nearest_ramp_dist = nil
        if comp._rerouteOverride and aircraft and is_valid_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) then
            local d_override = distance_meters_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon, aircraft.lat, aircraft.lon)
            if d_override and d_override > 1000 then
                comp._rerouteOverride = nil
            end
        end

        local start_lat = nil
        local start_lon = nil
        local end_lat = nil
        local end_lon = nil
        local runway_lat = nil
        local runway_lon = nil
        local runway_name = ""
        local raw_desrwy = ""
        local touchdown = nil
        local landing_profile = nil
        local dep_profile = nil
        local dep_runway_end_id = nil
        local dep_runway_end_lat = nil
        local dep_runway_end_lon = nil
        local backtrack_required = false
        local dep_holdshort_id = nil
        local dep_end_node_id = nil
        local dep_end_node_dist = nil
        local arr_exit_id = nil
        local allow_runway_route = false

        if mode == 0 then
            if aircraft then
                start_lat = aircraft.lat
                start_lon = aircraft.lon
            end
            runway_lat = yal.deprwylatstartpos and get(yal.deprwylatstartpos) or nil
            runway_lon = yal.deprwylonstartpos and get(yal.deprwylonstartpos) or nil
            if not is_valid_latlon(runway_lat, runway_lon) then
                runway_lat = yal.deprwylatendpos and get(yal.deprwylatendpos) or nil
                runway_lon = yal.deprwylonendpos and get(yal.deprwylonendpos) or nil
            end
            runway_name = yal.deprwy and helpers.forceCleanString(get(yal.deprwy) or "") or ""
            if comp._lastDepRunwayName and comp._lastDepRunwayName ~= runway_name then
                comp._selectedDepEntryId = nil
            end
            comp._lastDepRunwayName = runway_name
            comp._runwayName = runway_name
            if data and comp._runwayName and comp._runwayName ~= "" then
                local rwy, side = find_runway_entry(data, comp._runwayName, runway_lat, runway_lon)
                if rwy then
                    runway_lat = (side == 1) and rwy.lat1 or rwy.lat2
                    runway_lon = (side == 1) and rwy.lon1 or rwy.lon2
                    dep_holdshort_id = find_holdshort_node_near(data, runway_lat, runway_lon)
                    if dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                        local hs = data.nodes[dep_holdshort_id]
                        if is_valid_latlon(hs.lat, hs.lon) then
                            local d_hs = distance_meters_latlon(runway_lat, runway_lon, hs.lat, hs.lon)
                            if d_hs and d_hs > 2000 then
                                dep_holdshort_id = nil
                            else
                                end_lat = hs.lat
                                end_lon = hs.lon
                            end
                        end
                    end
                    if not dep_holdshort_id and is_valid_latlon(runway_lat, runway_lon) then
                        dep_end_node_id, dep_end_node_dist = nearest_non_runway_node(data, runway_lat, runway_lon)
                        if dep_end_node_id and data.nodes and data.nodes[dep_end_node_id] then
                            local dn = data.nodes[dep_end_node_id]
                            if is_valid_latlon(dn.lat, dn.lon) then
                                end_lat = dn.lat
                                end_lon = dn.lon
                            end
                        end
                    end
                end
            end
            if not is_valid_latlon(end_lat, end_lon) then
                end_lat = runway_lat
                end_lon = runway_lon
            end
            if aircraft and comp.yal and comp.yal.aircraftonrwy and is_valid_latlon(runway_lat, runway_lon) then
                local onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, depThresholdHeadingLimit)
                if onRunway then
                    allow_runway_route = true
                end
            end
        else
            runway_lat = yal.desrwylatstartpos and get(yal.desrwylatstartpos) or nil
            runway_lon = yal.desrwylonstartpos and get(yal.desrwylonstartpos) or nil
            if not is_valid_latlon(runway_lat, runway_lon) then
                runway_lat = yal.desrwylatendpos and get(yal.desrwylatendpos) or nil
                runway_lon = yal.desrwylonendpos and get(yal.desrwylonendpos) or nil
            end
            if is_valid_latlon(runway_lat, runway_lon) then
                comp._lastArrivalRunwayLat = runway_lat
                comp._lastArrivalRunwayLon = runway_lon
            elseif comp._lastArrivalRunwayLat and comp._lastArrivalRunwayLon then
                runway_lat = comp._lastArrivalRunwayLat
                runway_lon = comp._lastArrivalRunwayLon
            end
            raw_desrwy = yal.desrwy and helpers.forceCleanString(get(yal.desrwy) or "") or ""
            runway_name = raw_desrwy
            if runway_name ~= "" then
                comp._lastArrivalRunwayName = runway_name
            elseif comp._lastArrivalRunwayName then
                runway_name = comp._lastArrivalRunwayName
            end
            comp._runwayName = runway_name
            if data and comp._runwayName and comp._runwayName ~= "" then
                local ref_lat = runway_lat
                local ref_lon = runway_lon
                -- When we have a runway name, stale lat/lon can bias selection to the wrong runway.
                ref_lat = nil
                ref_lon = nil
                local log_key = tostring(icao) .. "|ARR|" .. tostring(raw_desrwy) .. "|" .. tostring(comp._runwayName)
                if comp._lastRunwayLogKey ~= log_key then
                    comp._lastRunwayLogKey = log_key
                    helpers.logInfoTS(
                        "Taxi: ARR runway input raw=" .. tostring(raw_desrwy) .. " resolved=" .. tostring(comp._runwayName)
                    )
                end
                local rwy, side = find_runway_entry(data, comp._runwayName, ref_lat, ref_lon)
                if rwy then
                    runway_lat = (side == 1) and rwy.lat1 or rwy.lat2
                    runway_lon = (side == 1) and rwy.lon1 or rwy.lon2
                    comp._lastArrivalRunwayLat = runway_lat
                    comp._lastArrivalRunwayLon = runway_lon
                    local sel = tostring(rwy and (side == 1 and rwy.rwy1 or rwy.rwy2) or "?")
                    local sel_key = log_key .. "|SEL|" .. sel
                    if comp._lastRunwaySelLogKey ~= sel_key then
                        comp._lastRunwaySelLogKey = sel_key
                        helpers.logInfoTS("Taxi: ARR runway selected " .. tostring(sel))
                    end
                end
                start_lat = runway_lat
                start_lon = runway_lon
                landing_profile = compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
                touchdown = landing_profile and landing_profile.touchdown or nil
                if landing_profile and touchdown and touchdown.east and touchdown.north then
                    local exit_id = nil
                    exit_id, backtrack_required = select_runway_exit_node(data, landing_profile)
                    arr_exit_id = exit_id
                    if exit_id and data.nodes and data.nodes[exit_id] then
                        local exit_node = data.nodes[exit_id]
                        if is_valid_latlon(exit_node.lat, exit_node.lon) then
                            if not backtrack_required then
                                start_lat = exit_node.lat
                                start_lon = exit_node.lon
                            end
                        end
                    end
                    if arr_exit_id then
                        local exit_log_key = tostring(icao) .. "|ARR-EXIT|" .. tostring(comp._runwayName) .. "|" .. tostring(arr_exit_id) .. "|" .. tostring(backtrack_required)
                        if comp._lastArrExitLogKey ~= exit_log_key then
                            comp._lastArrExitLogKey = exit_log_key
                            local along = nil
                            local perp = nil
                            local rollout = landing_profile and landing_profile.roll or nil
                            local exit_node = data.nodes and data.nodes[arr_exit_id] or nil
                            if exit_node and landing_profile then
                                along, perp = compute_along_perp(landing_profile, exit_node)
                            end
                            helpers.logInfoTS(
                                "Taxi: ARR exit id=" .. tostring(arr_exit_id) ..
                                " backtrack=" .. tostring(backtrack_required) ..
                                " along=" .. tostring(along or "?") ..
                                " perp=" .. tostring(perp or "?") ..
                                " rollout=" .. tostring(rollout or "?")
                            )
                        end
                    end
                    if not is_valid_latlon(start_lat, start_lon) then
                        local tlat, tlon = sasl.localToWorld(touchdown.east, 0, -touchdown.north)
                        if is_valid_latlon(tlat, tlon) then
                            start_lat = tlat
                            start_lon = tlon
                            runway_lat = tlat
                            runway_lon = tlon
                        end
                    end
                end
            end
            if not is_valid_latlon(start_lat, start_lon) then
                start_lat = runway_lat
                start_lon = runway_lon
            end
        end

        if mode == 1 and aircraft and comp.yal and comp.yal.aircraftonrwy and is_valid_latlon(runway_lat, runway_lon) then
            local offRunway = comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
            if not offRunway then
                local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
                if gs <= runwayRouteMaxSpeed then
                    allow_runway_route = true
                    start_lat = aircraft.lat
                    start_lon = aircraft.lon
                end
            end
        end

        local hasRunwayName = (runway_name ~= nil and runway_name ~= "")
        local hasArrivalRunway = (mode == 1 and hasRunwayName) or false
        local canRoute = data and data.can_route and (mode == 1 or hasRunwayName) or false
        if not canRoute then
            helpers.logInfoTS(
                "TaxiDiag: canRoute=false icao=" .. tostring(icao) ..
                " mode=" .. tostring(mode) ..
                " data.can_route=" .. tostring(data and data.can_route) ..
                " hasRunwayName=" .. tostring(hasRunwayName)
            )
        end

        if mode == 0 and data and comp._runwayName and comp._runwayName ~= "" and is_valid_latlon(runway_lat, runway_lon) then
            dep_profile = compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
            if dep_profile and dep_profile.threshold and dep_profile.threshold.east and dep_profile.threshold.north then
                dep_runway_end_id = find_nearest_runway_node(
                    data,
                    dep_profile.threshold.east,
                    dep_profile.threshold.north
                )
                local tlat, tlon = sasl.localToWorld(dep_profile.threshold.east, 0, -dep_profile.threshold.north)
                if is_valid_latlon(tlat, tlon) then
                    dep_runway_end_lat = tlat
                    dep_runway_end_lon = tlon
                end
            end
        end
        if mode == 0 then
            comp._depProfile = dep_profile
        else
            comp._depProfile = nil
        end
        if mode == 0 and allow_runway_route and dep_runway_end_lat and dep_runway_end_lon then
            end_lat = dep_runway_end_lat
            end_lon = dep_runway_end_lon
        end

        local ref_lat = nil
        local ref_lon = nil
        if yal.airportdatatable and yal.airportdatatable[icao] then
            ref_lat = yal.airportdatatable[icao].latitude
            ref_lon = yal.airportdatatable[icao].longitude
        end
        local ramp_ref_lat = ref_lat or runway_lat
        local ramp_ref_lon = ref_lon or runway_lon

        if mode == 0 and (not is_valid_latlon(start_lat, start_lon)) and is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
            start_lat = ramp_ref_lat
            start_lon = ramp_ref_lon
        end
        if mode == 1 and (not is_valid_latlon(start_lat, start_lon)) and is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
            start_lat = ramp_ref_lat
            start_lon = ramp_ref_lon
        end

        local end_ramp = nil
        local user_selected_end = false
        if mode == 1 and (not comp._drawFreehand) and is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
            if comp._selectedEndRampKey and data and data.ramps then
                for _, ramp in ipairs(data.ramps) do
                    if helpers.isRampSuitableFor738(ramp) and ramp_key(ramp) == comp._selectedEndRampKey then
                        end_ramp = ramp
                        user_selected_end = true
                        break
                    end
                end
            end
            if not end_ramp and comp._autoEndRampKey and data and data.ramps then
                for _, ramp in ipairs(data.ramps) do
                    if helpers.isRampSuitableFor738(ramp) and ramp_key(ramp) == comp._autoEndRampKey then
                        end_ramp = ramp
                        break
                    end
                end
                if not end_ramp then
                    comp._autoEndRampKey = nil
                end
            end
            if not end_ramp then
                end_ramp = helpers.getNearestRamp(icao, ramp_ref_lat, ramp_ref_lon, { filter = helpers.isRampSuitableFor738, data = data })
                if end_ramp then
                    comp._autoEndRampKey = ramp_key(end_ramp)
                end
            end
            if end_ramp and is_valid_latlon(end_ramp.lat, end_ramp.lon) then
                end_lat = end_ramp.lat
                end_lon = end_ramp.lon
            end
        end
        if mode == 1 and (not comp._drawFreehand) and (not user_selected_end)
            and data and aircraft and is_valid_latlon(aircraft.lat, aircraft.lon) then
            local yalref = comp.yal or _G.yal
            local onGround = yalref and yalref.airgroundsensor and (get(yalref.airgroundsensor) == def.ON)
            local gs = yalref and yalref.groundspeed and (get(yalref.groundspeed) or 0) or 0
            local gate_speed = tuning.autoGateSwitchSpeed or 5
            local gate_hold = tuning.autoGateSwitchHoldSec or 2.0
            local gate_cooldown = tuning.autoGateSwitchCooldownSec or 10.0
            local gate_dist = tuning.autoGateSwitchDist or 35
            local gate_delta = tuning.autoGateSwitchDelta or 20
            local gate_ratio = tuning.autoGateSwitchRatio or 0.6
            if onGround and gs < gate_speed then
                if not comp._autoEndRampLowSpeedSince then
                    comp._autoEndRampLowSpeedSince = now
                end
                if (now - comp._autoEndRampLowSpeedSince) >= gate_hold then
                    if not nearest_ramp then
                        nearest_ramp = helpers.getNearestRamp(
                            icao,
                            aircraft.lat,
                            aircraft.lon,
                            { filter = helpers.isRampSuitableFor738, data = data }
                        )
                        if nearest_ramp and is_valid_latlon(nearest_ramp.lat, nearest_ramp.lon) then
                            nearest_ramp_dist = distance_meters_latlon(
                                nearest_ramp.lat,
                                nearest_ramp.lon,
                                aircraft.lat,
                                aircraft.lon
                            )
                        end
                    end
                    if nearest_ramp and end_ramp and is_valid_latlon(end_ramp.lat, end_ramp.lon) then
                        local cand_key = ramp_key(nearest_ramp)
                        local planned_key = ramp_key(end_ramp)
                        if cand_key ~= planned_key then
                            local d_cand = nearest_ramp_dist
                            local d_plan = distance_meters_latlon(
                                end_ramp.lat,
                                end_ramp.lon,
                                aircraft.lat,
                                aircraft.lon
                            )
                            local cooldown_ok = (not comp._autoEndRampSwitchTime)
                                or ((now - comp._autoEndRampSwitchTime) >= gate_cooldown)
                            if d_cand and d_plan and cooldown_ok then
                                local close_enough = d_cand <= gate_dist
                                local clearly_closer = (d_plan - d_cand >= gate_delta)
                                    or (d_cand <= (d_plan * gate_ratio))
                                if close_enough and clearly_closer then
                                    comp._autoEndRampKey = cand_key
                                    comp._autoEndRampSwitchTime = now
                                    end_ramp = nearest_ramp
                                    end_lat = end_ramp.lat
                                    end_lon = end_ramp.lon
                                    comp._route = nil
                                    comp._routeErr = nil
                                    comp._routeLabels = nil
                                    comp._routeLabelStats = nil
                                    comp._lastEndKey = nil
                                    comp._lastStartKey = nil
                                    log_taxi(
                                        string.format(
                                            "TaxiRoute: auto end-ramp switch key=%s dist=%.1f plan=%.1f",
                                            tostring(cand_key),
                                            d_cand or -1,
                                            d_plan or -1
                                        )
                                    )
                                end
                            end
                        end
                    end
                end
            else
                comp._autoEndRampLowSpeedSince = nil
            end
        else
            comp._autoEndRampLowSpeedSince = nil
        end
        if mode == 1 and (not comp._drawFreehand)
            and (not is_valid_latlon(end_lat, end_lon)) and is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
            end_lat = ramp_ref_lat
            end_lon = ramp_ref_lon
        end

        local start_ramp = nil
        local start_is_aircraft = false
        if mode == 0 and aircraft and is_valid_latlon(aircraft.lat, aircraft.lon) then
            start_is_aircraft = true
            start_ramp = helpers.getNearestRamp(icao, aircraft.lat, aircraft.lon, { filter = helpers.isRampSuitableFor738, data = data })
            if start_ramp and start_ramp.lat and start_ramp.lon then
                local d_m = distance_meters_latlon(start_ramp.lat, start_ramp.lon, aircraft.lat, aircraft.lon)
                if d_m and d_m > startRampMaxMeters then
                    start_ramp = nil
                end
            end
        end

        comp._startRamp = start_ramp
        comp._startIsAircraft = (start_is_aircraft and not start_ramp) or false
        comp._endRamp = end_ramp

        local override_snap_max_m = 1000
        local function snap_override(lat, lon)
            if not data or not is_valid_latlon(lat, lon) then
                return nil, "invalid"
            end
            local east, north = latlon_to_local(lat, lon)
            if east == nil or north == nil then
                return nil, "no-local"
            end
            local proj = find_nearest_edge_projection(data, east, north, { disallow_runway_edges = false })
            if not proj or not proj.d2 then
                return nil, "no-proj"
            end
            local dist = math.sqrt(proj.d2)
            if dist > override_snap_max_m then
                return nil, "too-far", dist
            end
            local wlat, wlon = sasl.localToWorld(proj.proj_east, 0, -proj.proj_north)
            if not is_valid_latlon(wlat, wlon) then
                return nil, "invalid-proj", dist
            end
            return {
                lat = wlat,
                lon = wlon,
                east = proj.proj_east,
                north = proj.proj_north,
                dist = dist
            }
        end
        if comp._drawRoute and comp._routeWaypoints and #comp._routeWaypoints > 0 and data and (not comp._drawFreehand) then
            local guard = 0
            local changed = true
            while changed and comp._routeWaypoints and #comp._routeWaypoints > 0 and guard < 4 do
                guard = guard + 1
                changed = false
                local first = comp._routeWaypoints[1]
                if first then
                    local snapped, reason, dist = snap_override(first.lat, first.lon)
                    if not snapped and reason == "too-far" then
                        log_taxi(
                            string.format(
                                "TaxiDraw: drop start waypoint off-network dist=%.1f",
                                dist or -1
                            )
                        )
                        table.remove(comp._routeWaypoints, 1)
                        changed = true
                    elseif snapped then
                        if first.lat ~= snapped.lat or first.lon ~= snapped.lon then
                            log_taxi(
                                string.format(
                                    "TaxiDraw: snap start waypoint dist=%.1f",
                                    snapped.dist or 0
                                )
                            )
                        end
                        first.lat = snapped.lat
                        first.lon = snapped.lon
                        first.east = snapped.east
                        first.north = snapped.north
                    end
                end
                local count = comp._routeWaypoints and #comp._routeWaypoints or 0
                if count > 0 then
                    local last = comp._routeWaypoints[count]
                    if last then
                        local snapped, reason, dist = snap_override(last.lat, last.lon)
                        if not snapped and reason == "too-far" then
                            log_taxi(
                                string.format(
                                    "TaxiDraw: drop end waypoint off-network dist=%.1f",
                                    dist or -1
                                )
                            )
                            table.remove(comp._routeWaypoints, count)
                            changed = true
                        elseif snapped then
                            if last.lat ~= snapped.lat or last.lon ~= snapped.lon then
                                log_taxi(
                                    string.format(
                                        "TaxiDraw: snap end waypoint dist=%.1f",
                                        snapped.dist or 0
                                    )
                                )
                            end
                            last.lat = snapped.lat
                            last.lon = snapped.lon
                            last.east = snapped.east
                            last.north = snapped.north
                        end
                    end
                end
            end
        end
        if comp._drawRoute and comp._routeWaypoints and #comp._routeWaypoints > 0 then
            local first_wp = comp._routeWaypoints[1]
            local last_wp = comp._routeWaypoints[#comp._routeWaypoints]
            local slat, slon = ensure_waypoint_latlon(first_wp)
            local elat, elon = ensure_waypoint_latlon(last_wp)
            if slat and slon then
                comp._editStartOverride = { lat = slat, lon = slon, mode = mode, icao = icao }
            end
            if elat and elon then
                comp._editEndOverride = { lat = elat, lon = elon, mode = mode, icao = icao }
            end
        end
        comp._depHoldshortNodeId = dep_holdshort_id
        comp._depEntryCandidates = nil
        comp._depEntryLabels = nil
        if mode == 0 and data and is_valid_latlon(runway_lat, runway_lon) then
            local re, rn = latlon_to_local(runway_lat, runway_lon)
            local candidates = collect_runway_exit_candidates(data, re, rn, 40)
            if candidates and #candidates > 0 then
                comp._depEntryCandidates = candidates
                comp._depEntryLabels = {}
                for _, cand in ipairs(candidates) do
                    if cand.id then
                        comp._depEntryLabels[cand.id] = find_runway_entry_label(data, cand.id)
                    end
                end
            end
        end

        if (not in_edit) and comp._rerouteOverride and is_valid_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) then
            start_lat = comp._rerouteOverride.lat
            start_lon = comp._rerouteOverride.lon
        end

        local base_start_lat = start_lat
        local base_start_lon = start_lon
        local base_end_lat = end_lat
        local base_end_lon = end_lon

        local start_override = comp._editStartOverride
        local has_start_override = false
        if start_override and start_override.mode == mode and is_valid_latlon(start_override.lat, start_override.lon) then
            if not start_override.icao or start_override.icao == "" then
                start_override.icao = icao
            end
            has_start_override = (start_override.icao == icao)
        end
        if has_start_override then
            start_lat = start_override.lat
            start_lon = start_override.lon
        end
        if has_start_override and data and (not comp._drawFreehand) then
            local snapped, reason, dist = snap_override(start_override.lat, start_override.lon)
            if not snapped and reason == "too-far" then
                log_taxi(
                    string.format(
                        "TaxiEdit: clear start override off-network dist=%.1f",
                        dist or -1
                    )
                )
                comp._editStartOverride = nil
                has_start_override = false
                start_lat = base_start_lat
                start_lon = base_start_lon
            elseif snapped then
                if start_override.lat ~= snapped.lat or start_override.lon ~= snapped.lon then
                    log_taxi(
                        string.format(
                            "TaxiEdit: snap start override dist=%.1f",
                            snapped.dist or 0
                        )
                    )
                end
                start_override.lat = snapped.lat
                start_override.lon = snapped.lon
                start_lat = start_override.lat
                start_lon = start_override.lon
            end
        end
        local end_override = comp._editEndOverride
        local has_end_override = false
        if end_override and end_override.mode == mode and is_valid_latlon(end_override.lat, end_override.lon) then
            if not end_override.icao or end_override.icao == "" then
                end_override.icao = icao
            end
            has_end_override = (end_override.icao == icao)
        end
        if has_end_override then
            end_lat = end_override.lat
            end_lon = end_override.lon
        end
        if has_end_override and data and (not comp._drawFreehand) then
            local snapped, reason, dist = snap_override(end_override.lat, end_override.lon)
            if not snapped and reason == "too-far" then
                log_taxi(
                    string.format(
                        "TaxiEdit: clear end override off-network dist=%.1f",
                        dist or -1
                    )
                )
                comp._editEndOverride = nil
                has_end_override = false
                end_lat = base_end_lat
                end_lon = base_end_lon
            elseif snapped then
                if end_override.lat ~= snapped.lat or end_override.lon ~= snapped.lon then
                    log_taxi(
                        string.format(
                            "TaxiEdit: snap end override dist=%.1f",
                            snapped.dist or 0
                        )
                    )
                end
                end_override.lat = snapped.lat
                end_override.lon = snapped.lon
                end_lat = end_override.lat
                end_lon = end_override.lon
            end
        end

        local start_node_id, start_node_dist = nearest_node_info(data, start_lat, start_lon, false)
        local start_non_runway_node_id = nil
        local start_non_runway_node_dist = nil
        if mode == 0 and start_is_aircraft and data and data.runway_nodes then
            start_non_runway_node_id, start_non_runway_node_dist = nearest_non_runway_node(data, start_lat, start_lon)
        end
        if mode == 1 and start_node_dist and start_node_dist > rerouteDriftMeters then
            log_taxi(
                string.format(
                    "TaxiRoute: clear start node dist=%.1f",
                    start_node_dist or -1
                )
            )
            start_node_id = nil
            start_node_dist = nil
        end
        local end_node_id, end_node_dist = nearest_node_info(data, end_lat, end_lon, false)
        if mode == 0 and data and data.runway_nodes then
            dep_end_node_id, dep_end_node_dist = nearest_non_runway_node(data, end_lat, end_lon)
        end
        if mode == 1 and arr_exit_id and (not has_start_override) and (not comp._arrOffRunwayHandled)
            and start_node_dist and start_node_dist > arrStartNodeMaxMeters
            and arrival_grace_active(comp, now)
            and data and data.nodes and data.nodes[arr_exit_id] then
            local exit_node = data.nodes[arr_exit_id]
            if exit_node and is_valid_latlon(exit_node.lat, exit_node.lon) then
                start_lat = exit_node.lat
                start_lon = exit_node.lon
                start_node_id = arr_exit_id
                start_node_dist = 0
                comp._rerouteOverride = nil
            end
        end
        if mode == 0 and (not has_end_override) and (not allow_runway_route)
            and comp._selectedDepEntryId and data and data.nodes and data.nodes[comp._selectedDepEntryId] then
            local sel = data.nodes[comp._selectedDepEntryId]
            end_lat = sel.lat
            end_lon = sel.lon
            end_node_id = comp._selectedDepEntryId
            end_node_dist = 0
        end
        comp._routeDebug = {
            start_lat = start_lat,
            start_lon = start_lon,
            end_lat = end_lat,
            end_lon = end_lon,
            start_node_id = start_node_id,
            start_node_dist = start_node_dist,
            start_non_runway_node_id = start_non_runway_node_id,
            start_non_runway_node_dist = start_non_runway_node_dist,
            end_node_id = end_node_id,
            end_node_dist = end_node_dist,
            dep_end_node_id = dep_end_node_id,
            dep_end_node_dist = dep_end_node_dist
        }

        if mode == 1 and (not hasArrivalRunway)
            and ((not is_valid_latlon(start_lat, start_lon)) or (not is_valid_latlon(end_lat, end_lon))) then
            comp._route = nil
            comp._routeErr = "no-arrival-runway"
            comp._routeExtraSegments = nil
            comp._lastStartKey = nil
            comp._lastEndKey = nil
            log_taxi("TaxiRoute: abort no-arrival-runway")
            return
        end

        if comp.yal and comp.yal.aircraftonrwy and is_valid_latlon(runway_lat, runway_lon) then
            if mode == 1 then
                local offRunway = comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
                if not offRunway and not allow_runway_route then
                    comp._route = nil
                    comp._routeErr = "on-runway"
                    comp._routeExtraSegments = nil
                    comp._lastStartKey = nil
                    comp._lastEndKey = nil
                    log_taxi("TaxiRoute: abort on-runway")
                    return
                end
            end
        end

        if comp._drawRoute and (not comp._routeWaypoints or #comp._routeWaypoints == 0) then
            comp._route = nil
            comp._routeErr = "draw-route-empty"
            comp._routeExtraSegments = nil
            comp._lastStartKey = nil
            comp._lastEndKey = nil
            log_taxi("TaxiDraw: abort draw-route-empty")
            return
        end

        local route_waypoints = comp._routeWaypoints
        if route_waypoints and #route_waypoints > 0 then
            local drop_first = waypoint_matches_override(route_waypoints[1], comp._editStartOverride)
            local drop_last = waypoint_matches_override(route_waypoints[#route_waypoints], comp._editEndOverride)
            if drop_first or drop_last then
                local trimmed = {}
                local s = drop_first and 2 or 1
                local e = drop_last and (#route_waypoints - 1) or #route_waypoints
                for i = s, e do
                    trimmed[#trimmed + 1] = route_waypoints[i]
                end
                route_waypoints = trimmed
            end
        end

        local anchor_lat = start_lat
        local anchor_lon = start_lon
        if not in_edit then
            if comp._rerouteOverride and is_valid_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) then
                anchor_lat = comp._rerouteOverride.lat
                anchor_lon = comp._rerouteOverride.lon
            elseif comp._route and comp._routeStartAnchor
                and is_valid_latlon(comp._routeStartAnchor.lat, comp._routeStartAnchor.lon) then
                anchor_lat = comp._routeStartAnchor.lat
                anchor_lon = comp._routeStartAnchor.lon
            end
        end
        local start_key = string.format("%.6f|%.6f", anchor_lat or 0, anchor_lon or 0)
        local end_key = string.format("%.6f|%.6f", end_lat or 0, end_lon or 0)
        local recompute_reason = nil
        if comp._editDirty then
            recompute_reason = "edit-dirty"
        elseif comp._route == nil then
            recompute_reason = "route-nil"
        elseif comp._lastStartKey ~= start_key or comp._lastEndKey ~= end_key then
            recompute_reason = "start-end-change"
        end
        if recompute_reason then
            local recompute_key = string.format(
                "%s|%s|%s|%d|%s|%s",
                tostring(recompute_reason),
                tostring(start_key),
                tostring(end_key),
                (comp._routeWaypoints and #comp._routeWaypoints) or 0,
                tostring(in_edit),
                tostring(comp._drawRoute)
            )
            if comp._lastRecomputeKey ~= recompute_key then
                comp._lastRecomputeKey = recompute_key
                log_taxi(
                    string.format(
                        "TaxiRoute: recompute reason=%s edit=%s draw=%s wps=%d",
                        tostring(recompute_reason),
                        tostring(in_edit),
                        tostring(comp._drawRoute),
                        (comp._routeWaypoints and #comp._routeWaypoints) or 0
                    )
                )
            end
        end
        if comp._editDirty or comp._lastStartKey ~= start_key or comp._lastEndKey ~= end_key or comp._route == nil then
            comp._lastStartKey = start_key
            comp._lastEndKey = end_key
            comp._initialGuidanceDone = false
            if canRoute and is_valid_latlon(start_lat, start_lon) and is_valid_latlon(end_lat, end_lon) then
                local function fmt_latlon(latv, lonv)
                    if not latv or not lonv then
                        return "nil/nil"
                    end
                    return string.format("%.6f/%.6f", tonumber(latv) or 0, tonumber(lonv) or 0)
                end
                local function fmt_node_latlon(node_id)
                    if not node_id or not data or not data.nodes then
                        return "nil"
                    end
                    local n = data.nodes[node_id]
                    if not n then
                        return tostring(node_id) .. ":?"
                    end
                    return tostring(node_id) .. ":" .. fmt_latlon(n.lat, n.lon)
                end
                local yalref = comp.yal or _G.yal
                local onGround = yalref and yalref.airgroundsensor and (get(yalref.airgroundsensor) == def.ON)
                local groundspeed = yalref and yalref.groundspeed and (get(yalref.groundspeed) or 0) or 0
                local raw_dep = yalref and yalref.deprwy and helpers.forceCleanString(get(yalref.deprwy) or "") or ""
                local raw_arr = yalref and yalref.desrwy and helpers.forceCleanString(get(yalref.desrwy) or "") or ""
                local dep_lat = yalref and yalref.deprwylatstartpos and get(yalref.deprwylatstartpos) or nil
                local dep_lon = yalref and yalref.deprwylonstartpos and get(yalref.deprwylonstartpos) or nil
                local arr_lat = yalref and yalref.desrwylatstartpos and get(yalref.desrwylatstartpos) or nil
                local arr_lon = yalref and yalref.desrwylonstartpos and get(yalref.desrwylonstartpos) or nil
                local src = data and data.route_source or "?"
                helpers.logInfoTS(
                    "TaxiDiag: mode=" .. tostring(mode) ..
                    " icao=" .. tostring(icao) ..
                    " src=" .. tostring(src) ..
                    " runway=" .. tostring(comp._runwayName or "") ..
                    " rawDEP=" .. tostring(raw_dep) ..
                    " rawARR=" .. tostring(raw_arr)
                )
                helpers.logInfoTS(
                    "TaxiDiag: runwayLatLon dep=" .. fmt_latlon(dep_lat, dep_lon) ..
                    " arr=" .. fmt_latlon(arr_lat, arr_lon) ..
                    " chosen=" .. fmt_latlon(runway_lat, runway_lon)
                )
                helpers.logInfoTS(
                    "TaxiDiag: start=" .. fmt_latlon(start_lat, start_lon) ..
                    " end=" .. fmt_latlon(end_lat, end_lon) ..
                    " aircraft=" .. (aircraft and fmt_latlon(aircraft.lat, aircraft.lon) or "nil/nil") ..
                    " reroute=" .. (comp._rerouteOverride and fmt_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) or "nil/nil")
                )
                local dep_end_dbg = ""
                if dep_end_node_id then
                    dep_end_dbg = " depEnd=" .. fmt_node_latlon(dep_end_node_id) .. " d=" .. tostring(dep_end_node_dist or "?")
                end
                helpers.logInfoTS(
                    "TaxiDiag: nodes start=" .. fmt_node_latlon(start_node_id) .. " d=" .. tostring(start_node_dist or "?") ..
                    " end=" .. fmt_node_latlon(end_node_id) .. " d=" .. tostring(end_node_dist or "?") ..
                    dep_end_dbg ..
                    " depHS=" .. fmt_node_latlon(dep_holdshort_id) ..
                    " arrExit=" .. fmt_node_latlon(arr_exit_id)
                )
                helpers.logInfoTS(
                    "TaxiDiag: onGround=" .. tostring(onGround) .. " gs=" .. tostring(groundspeed)
                )
                local tirespeed = yalref and yalref.tirespeed and (get(yalref.tirespeed) or 0) or 0
                local now = 0
                if comp._timer then
                    now = sasl.getElapsedSeconds(comp._timer) or 0
                end
                local log_key = string.format("%d|%s|%s|%s|%.4f|%.4f|%.4f|%.4f",
                    mode or -1,
                    tostring(icao),
                    tostring(comp._runwayName or ""),
                    tostring(raw_dep or raw_arr or ""),
                    tonumber(start_lat or 0),
                    tonumber(start_lon or 0),
                    tonumber(end_lat or 0),
                    tonumber(end_lon or 0)
                )
                local should_log = (comp._lastRouteLogKey ~= log_key)
                if not should_log and comp._lastRouteLogTime then
                    should_log = (now - comp._lastRouteLogTime) > 8
                end
                if should_log then
                    comp._lastRouteLogKey = log_key
                    comp._lastRouteLogTime = now
                    local wtl_e, wtl_n = nil, nil
                    if aircraft and aircraft.lat and aircraft.lon then
                        wtl_e, wtl_n = latlon_to_local(aircraft.lat, aircraft.lon)
                    end
                    local rwy_entry_lat = nil
                    local rwy_entry_lon = nil
                    local rwy_entry_dist_m = nil
                    local rwy1, rwy2, rwy_side = nil, nil, nil
                    if data and comp._runwayName and comp._runwayName ~= "" then
                        local rwy, side = find_runway_entry(data, comp._runwayName, runway_lat, runway_lon)
                        if rwy then
                            rwy1 = rwy.rwy1
                            rwy2 = rwy.rwy2
                            rwy_side = side
                            rwy_entry_lat = (side == 1) and rwy.lat1 or rwy.lat2
                            rwy_entry_lon = (side == 1) and rwy.lon1 or rwy.lon2
                            if is_valid_latlon(runway_lat, runway_lon) and is_valid_latlon(rwy_entry_lat, rwy_entry_lon) then
                                rwy_entry_dist_m = distance_meters_latlon(runway_lat, runway_lon, rwy_entry_lat, rwy_entry_lon)
                            end
                        end
                    end
                    local dep_hs_dist = nil
                    if dep_holdshort_id and data and data.nodes then
                        local hs = data.nodes[dep_holdshort_id]
                        if hs and is_valid_latlon(hs.lat, hs.lon) and is_valid_latlon(runway_lat, runway_lon) then
                            dep_hs_dist = distance_meters_latlon(runway_lat, runway_lon, hs.lat, hs.lon)
                        end
                    end
                    log_full_route_state(comp, data, mode, icao, {
                        raw_dep = raw_dep,
                        raw_arr = raw_arr,
                        runway_name = comp._runwayName,
                        runway_lat = runway_lat,
                        runway_lon = runway_lon,
                        chosen_lat = runway_lat,
                        chosen_lon = runway_lon,
                        rwy1 = rwy1,
                        rwy2 = rwy2,
                        rwy_side = rwy_side,
                        rwy_entry_lat = rwy_entry_lat,
                        rwy_entry_lon = rwy_entry_lon,
                        rwy_entry_dist_m = rwy_entry_dist_m,
                        aircraft_lat = aircraft and aircraft.lat or nil,
                        aircraft_lon = aircraft and aircraft.lon or nil,
                        aircraft_east = aircraft and aircraft.east or nil,
                        aircraft_north = aircraft and aircraft.north or nil,
                        aircraft_wtl_e = wtl_e,
                        aircraft_wtl_n = wtl_n,
                        start_lat = start_lat,
                        start_lon = start_lon,
                        end_lat = end_lat,
                        end_lon = end_lon,
                        start_node_id = start_node_id,
                        start_node_dist = start_node_dist,
                        end_node_id = end_node_id,
                        end_node_dist = end_node_dist,
                        start_non_runway_node_id = start_non_runway_node_id,
                        start_non_runway_node_dist = start_non_runway_node_dist,
                        dep_holdshort_id = dep_holdshort_id,
                        dep_holdshort_dist_m = dep_hs_dist,
                        arr_exit_id = arr_exit_id,
                        reroute_lat = comp._rerouteOverride and comp._rerouteOverride.lat or nil,
                        reroute_lon = comp._rerouteOverride and comp._rerouteOverride.lon or nil,
                        onGround = onGround,
                        groundspeed = groundspeed,
                        tirespeed = tirespeed
                    })
                end
                local proj_data = nil
                local proj_start_id = nil
                local proj_end_id = nil
                local proj_waypoint_ids = nil
                local function compute_projection(opts)
                    if proj_data then
                        return
                    end
                    local start_proj = nil
                    local end_proj = nil
                    local waypoint_projs = nil
                    if not opts.start_node_id and is_valid_latlon(start_lat, start_lon) then
                        local sx, sy = latlon_to_local(start_lat, start_lon)
                        if sx and sy then
                            if start_ramp and start_ramp.east and start_ramp.north then
                                if start_ramp.heading ~= nil then
                                    start_proj = find_heading_edge_projection(
                                        data,
                                        start_ramp.east,
                                        start_ramp.north,
                                        start_ramp.heading,
                                        { disallow_runway_edges = opts.disallow_runway_edges, radius_m = 150, angle_deg = 60 }
                                    )
                                end
                                if not start_proj then
                                    start_proj = find_preferred_edge_projection(
                                        data,
                                        start_ramp.east,
                                        start_ramp.north,
                                        { disallow_runway_edges = opts.disallow_runway_edges }
                                    )
                                end
                            end
                            if not start_proj then
                                start_proj = find_nearest_edge_projection(data, sx, sy, { disallow_runway_edges = opts.disallow_runway_edges })
                            end
                        end
                    end
                    if not opts.end_node_id and is_valid_latlon(end_lat, end_lon) then
                        local ex, ey = latlon_to_local(end_lat, end_lon)
                        if ex and ey then
                            if end_ramp and end_ramp.east and end_ramp.north then
                                if end_ramp.heading ~= nil then
                                    end_proj = find_heading_edge_projection(
                                        data,
                                        end_ramp.east,
                                        end_ramp.north,
                                        end_ramp.heading,
                                        { disallow_runway_edges = opts.disallow_runway_edges, radius_m = 150, angle_deg = 60 }
                                    )
                                end
                                if not end_proj then
                                    end_proj = find_preferred_edge_projection(
                                        data,
                                        end_ramp.east,
                                        end_ramp.north,
                                        { disallow_runway_edges = opts.disallow_runway_edges }
                                    )
                                end
                            end
                            if not end_proj then
                                end_proj = find_nearest_edge_projection(data, ex, ey, { disallow_runway_edges = opts.disallow_runway_edges })
                            end
                        end
                    end
                    if route_waypoints and #route_waypoints > 0 then
                        waypoint_projs = {}
                        for _, wp in ipairs(route_waypoints) do
                            if is_valid_latlon(wp.lat, wp.lon) then
                                local wx, wy = latlon_to_local(wp.lat, wp.lon)
                                if wx and wy then
                                    waypoint_projs[#waypoint_projs + 1] = find_nearest_edge_projection(
                                        data,
                                        wx,
                                        wy,
                                        { disallow_runway_edges = opts.disallow_runway_edges }
                                    )
                                end
                            end
                        end
                    end
                    if start_proj or end_proj or (waypoint_projs and #waypoint_projs > 0) then
                        proj_data, proj_start_id, proj_end_id, proj_waypoint_ids =
                            build_projected_data(data, start_proj, end_proj, waypoint_projs)
                    end
                end
                local function apply_projection(opts)
                    if proj_data then
                        opts.data = proj_data
                        if proj_start_id and not opts.start_node_id then
                            opts.start_node_id = proj_start_id
                        end
                        if proj_end_id and not opts.end_node_id then
                            opts.end_node_id = proj_end_id
                        end
                    else
                        opts.data = data
                    end
                    if not opts.start_node_id and opts._fallback_start_node_id then
                        opts.start_node_id = opts._fallback_start_node_id
                    end
                    if not opts.end_node_id and opts._fallback_end_node_id then
                        opts.end_node_id = opts._fallback_end_node_id
                    end
                end

                local function node_has_non_runway_edge(node_id)
                    if not node_id or not data or not data.adjacency_any or not data.nodes then
                        return false
                    end
                    local edges = data.adjacency_any[node_id]
                    if not edges then
                        return false
                    end
                    for _, edge in ipairs(edges) do
                        local other = data.nodes[edge.to]
                        if other and not other.is_ramp and not (data.runway_nodes and data.runway_nodes[edge.to]) then
                            return true
                        end
                    end
                    return false
                end

                local function set_start_ramp_fallback(opts)
                    if start_ramp and start_ramp.node_id and node_has_non_runway_edge(start_ramp.node_id) then
                        opts._fallback_start_node_id = start_ramp.node_id
                        opts.allow_far_ramp = true
                    end
                end

                local function set_end_ramp_fallback(opts)
                    if user_selected_end and end_ramp and end_ramp.node_id and node_has_non_runway_edge(end_ramp.node_id) then
                        opts._fallback_end_node_id = end_ramp.node_id
                        opts.allow_far_ramp = true
                    end
                end

                local opts = {}
                if mode == 0 then
                    opts.avoid_runway_end = not allow_runway_route
                    opts.runway_penalty = allow_runway_route and 1 or 500
                    opts.disallow_runway_edges = not allow_runway_route
                    opts.avoid_runway_nodes = not allow_runway_route
                    if not has_end_override then
                        if allow_runway_route and dep_runway_end_id and data.nodes and data.nodes[dep_runway_end_id] then
                            opts.end_node_id = dep_runway_end_id
                        elseif comp._selectedDepEntryId and data.nodes and data.nodes[comp._selectedDepEntryId] then
                            opts.end_node_id = comp._selectedDepEntryId
                        elseif dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                            opts.end_node_id = dep_holdshort_id
                        elseif dep_end_node_id and data.nodes and data.nodes[dep_end_node_id] then
                            opts.end_node_id = dep_end_node_id
                        end
                    end
                    set_start_ramp_fallback(opts)
                elseif mode == 1 then
                    if not allow_runway_route then
                        if (not comp._rerouteOverride) and (not has_start_override) and (not comp._arrOffRunwayHandled)
                            and arr_exit_id and data.nodes and data.nodes[arr_exit_id] then
                            opts.start_node_id = arr_exit_id
                        elseif not backtrack_required then
                            opts.avoid_runway_start = true
                        end
                    end
                    opts.runway_penalty = allow_runway_route and 1 or 500
                    set_end_ramp_fallback(opts)
                end
                if not opts.start_node_id and start_node_id and data.nodes and data.nodes[start_node_id] then
                    opts.start_node_id = start_node_id
                end
                if not opts.end_node_id and end_node_id and data.nodes and data.nodes[end_node_id] then
                    opts.end_node_id = end_node_id
                end
                compute_projection(opts)
                apply_projection(opts)
                local route, rerr = route_with_waypoints(
                    icao,
                    start_lat,
                    start_lon,
                    end_lat,
                    end_lon,
                    opts,
                    proj_waypoint_ids,
                    route_waypoints
                )
                if (not route) and rerr == "no-path" and mode == 0 then
                    opts = {
                        ignore_oneway = true,
                        allow_far_ramp = true,
                        disallow_runway_edges = true,
                        avoid_runway_nodes = true
                    }
                    if not has_end_override then
                        if allow_runway_route and dep_runway_end_id and data.nodes and data.nodes[dep_runway_end_id] then
                            opts.end_node_id = dep_runway_end_id
                        elseif comp._selectedDepEntryId and data.nodes and data.nodes[comp._selectedDepEntryId] then
                            opts.end_node_id = comp._selectedDepEntryId
                        elseif dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                            opts.end_node_id = dep_holdshort_id
                        end
                    end
                    set_start_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                end
                if (not route) and rerr == "no-path" and mode == 0 and is_valid_latlon(start_lat, start_lon) then
                    local sx, sy = latlon_to_local(start_lat, start_lon)
                    local candidates = collect_nearest_nodes(data, sx, sy, 18)
                    if #candidates > 0 then
                        opts = {
                            ignore_oneway = true,
                            allow_far_ramp = true,
                            disallow_runway_edges = true,
                            avoid_runway_nodes = true
                        }
                        if not has_end_override then
                            if allow_runway_route and dep_runway_end_id and data.nodes and data.nodes[dep_runway_end_id] then
                                opts.end_node_id = dep_runway_end_id
                            elseif comp._selectedDepEntryId and data.nodes and data.nodes[comp._selectedDepEntryId] then
                                opts.end_node_id = comp._selectedDepEntryId
                            elseif dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                                opts.end_node_id = dep_holdshort_id
                            end
                        end
                        set_start_ramp_fallback(opts)
                        apply_projection(opts)
                        local alt_route = try_route_from_candidates(
                            icao,
                            data,
                            end_lat,
                            end_lon,
                            candidates,
                            opts,
                            proj_waypoint_ids,
                            route_waypoints
                        )
                        if alt_route then
                            route = alt_route
                            rerr = nil
                        end
                    end
                end
                if (not route) and rerr == "no-path" and mode == 0 and is_valid_latlon(end_lat, end_lon) then
                    local ex, ey = latlon_to_local(end_lat, end_lon)
                    local candidates = collect_nearest_nodes(data, ex, ey, 18)
                    if #candidates > 0 then
                        opts = {
                            ignore_oneway = true,
                            allow_far_ramp = true,
                            disallow_runway_edges = true,
                            avoid_runway_nodes = true
                        }
                        if not has_end_override then
                            if allow_runway_route and dep_runway_end_id and data.nodes and data.nodes[dep_runway_end_id] then
                                opts.end_node_id = dep_runway_end_id
                            elseif comp._selectedDepEntryId and data.nodes and data.nodes[comp._selectedDepEntryId] then
                                opts.end_node_id = comp._selectedDepEntryId
                            elseif dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                                opts.end_node_id = dep_holdshort_id
                            end
                        end
                        set_start_ramp_fallback(opts)
                        apply_projection(opts)
                        local alt_route = try_route_to_candidates(
                            icao,
                            data,
                            start_lat,
                            start_lon,
                            candidates,
                            opts,
                            proj_waypoint_ids,
                            route_waypoints
                        )
                        if alt_route then
                            route = alt_route
                            rerr = nil
                        end
                    end
                end
                if (not route) and rerr == "no-path" and mode == 0 then
                    opts = {
                        ignore_oneway = true,
                        allow_far_ramp = true,
                        disallow_runway_edges = true,
                        avoid_runway_nodes = false
                    }
                    if not has_end_override then
                        if allow_runway_route and dep_runway_end_id and data.nodes and data.nodes[dep_runway_end_id] then
                            opts.end_node_id = dep_runway_end_id
                        elseif comp._selectedDepEntryId and data.nodes and data.nodes[comp._selectedDepEntryId] then
                            opts.end_node_id = comp._selectedDepEntryId
                        elseif dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                            opts.end_node_id = dep_holdshort_id
                        end
                    end
                    set_start_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                    if route and helpers and helpers.logInfoTS then
                        helpers.logInfoTS("Taxi: DEP fallback allow runway nodes")
                    end
                end
                if (not route) and rerr == "no-path" and mode == 0 then
                    opts = {
                        ignore_oneway = true,
                        allow_far_ramp = true,
                        disallow_runway_edges = false,
                        avoid_runway_nodes = false,
                        runway_penalty = 50
                    }
                    if not has_end_override then
                        if allow_runway_route and dep_runway_end_id and data.nodes and data.nodes[dep_runway_end_id] then
                            opts.end_node_id = dep_runway_end_id
                        elseif comp._selectedDepEntryId and data.nodes and data.nodes[comp._selectedDepEntryId] then
                            opts.end_node_id = comp._selectedDepEntryId
                        elseif dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                            opts.end_node_id = dep_holdshort_id
                        end
                    end
                    set_start_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                    if route and helpers and helpers.logInfoTS then
                        helpers.logInfoTS("Taxi: DEP fallback allow runway crossing")
                    end
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = {}
                    if (not has_start_override) and (not backtrack_required) then
                        opts.avoid_runway_start = true
                    end
                    set_end_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { ignore_oneway = true }
                    if (not has_start_override) and (not backtrack_required) then
                        opts.avoid_runway_start = true
                    end
                    set_end_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = {}
                    if (not has_start_override) and (not backtrack_required) then
                        opts.runway_penalty = 500
                    end
                    set_end_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { ignore_oneway = true }
                    set_end_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { allow_far_ramp = true }
                    if (not has_start_override) and (not backtrack_required) then
                        opts.avoid_runway_start = true
                        opts.runway_penalty = 500
                    end
                    set_end_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { allow_far_ramp = true, ignore_oneway = true }
                    set_end_ramp_fallback(opts)
                    apply_projection(opts)
                    route, rerr = route_with_waypoints(
                        icao,
                        start_lat,
                        start_lon,
                        end_lat,
                        end_lon,
                        opts,
                        proj_waypoint_ids,
                        route_waypoints
                    )
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    local ref = touchdown
                    if not (ref and ref.east and ref.north) and is_valid_latlon(runway_lat, runway_lon) then
                        local re, rn = latlon_to_local(runway_lat, runway_lon)
                        ref = { east = re, north = rn }
                    end
                    if ref and ref.east and ref.north and data then
                        local candidates = collect_runway_exit_candidates(data, ref.east, ref.north, 12)
                        if #candidates > 0 then
                            opts = { allow_far_ramp = true, ignore_oneway = true }
                            if (not has_start_override) and (not backtrack_required) then
                                opts.runway_penalty = 500
                            end
                            apply_projection(opts)
                            local alt_route, alt_err, alt_lat, alt_lon = try_route_from_candidates(
                                icao,
                                data,
                                end_lat,
                                end_lon,
                                candidates,
                                opts,
                                proj_waypoint_ids,
                                route_waypoints
                            )
                            if alt_route then
                                route = alt_route
                                rerr = alt_err
                                start_lat = alt_lat
                                start_lon = alt_lon
                            end
                        end
                    end
                end
                if (not route) and rerr == "no-path" and mode == 1 and is_valid_latlon(end_lat, end_lon) and (not user_selected_end) then
                    local ee, en = latlon_to_local(end_lat, end_lon)
                    local candidates = collect_nearest_nodes(data, ee, en, 18)
                    if #candidates > 0 then
                        opts = { allow_far_ramp = true, ignore_oneway = true }
                        if (not has_start_override) and (not backtrack_required) then
                            opts.runway_penalty = 500
                        end
                        apply_projection(opts)
                        local alt_route, alt_err, alt_lat, alt_lon = try_route_to_candidates(
                            icao,
                            data,
                            start_lat,
                            start_lon,
                            candidates,
                            opts,
                            proj_waypoint_ids,
                            route_waypoints
                        )
                        if alt_route then
                            route = alt_route
                            rerr = alt_err
                            end_lat = alt_lat
                            end_lon = alt_lon
                        end
                    end
                end
                if (not route) and rerr == "no-path" and mode == 1 and is_valid_latlon(end_lat, end_lon) and user_selected_end then
                    local ee, en = latlon_to_local(end_lat, end_lon)
                    local candidates = collect_nearest_nodes(data, ee, en, 18)
                    if #candidates > 0 then
                        opts = { allow_far_ramp = true, ignore_oneway = true }
                        if not backtrack_required then
                            opts.runway_penalty = 500
                        end
                        apply_projection(opts)
                        local alt_route, alt_err, alt_lat, alt_lon = try_route_to_candidates(
                            icao,
                            data,
                            start_lat,
                            start_lon,
                            candidates,
                            opts,
                            proj_waypoint_ids,
                            route_waypoints
                        )
                        if alt_route then
                            route = alt_route
                            rerr = alt_err
                        end
                    end
                end
                comp._route = route
                comp._lastRouteComputeTime = now
                comp._routeErr = rerr
                comp._routeLabels = route and build_route_labels(route.data, route.path) or nil
                comp._routeLabelStats = route and compute_route_label_stats(route.data, route.path) or nil
                if in_edit and route then
                    if comp._editDirty then
                        log_taxi("TaxiEdit: clean")
                    end
                    comp._editDirty = false
                end
                if route and is_valid_latlon(start_lat, start_lon) then
                    if not in_edit then
                        comp._routeStartAnchor = { lat = start_lat, lon = start_lon }
                        if comp._rerouteOverride then
                            comp._rerouteOverride = nil
                        end
                    else
                        comp._routeStartAnchor = nil
                    end
                end
                if route and route.path then
                    local rlen = #route.path
                    local src = (route.data and route.data.route_source) or "?"
                    helpers.logInfoTS(
                        string.format(
                            "Taxi: route %s %s mode=%d len=%d start=%s end=%s src=%s",
                            tostring(icao),
                            tostring(comp._runwayName or ""),
                            tonumber(mode or -1),
                            tonumber(rlen or 0),
                            tostring(route.start_id or "?"),
                            tostring(route.end_id or "?"),
                            tostring(src)
                        )
                    )
                    local path = route.path
                    local path_parts = {}
                    for i = 1, #path do
                        path_parts[#path_parts + 1] = tostring(path[i])
                    end
                    local path_key = table.concat(path_parts, ",")
                    local fwd_key = path_key
                    if aircraft and aircraft.east and aircraft.north then
                        local seg_idx = find_nearest_segment(route.data, path, aircraft.east, aircraft.north)
                        if seg_idx and seg_idx >= 1 and seg_idx < #path_parts then
                            fwd_key = table.concat(path_parts, ",", seg_idx + 1, #path_parts)
                        end
                    end
                    if comp._lastRoutePathKey ~= path_key then
                        comp._lastRoutePathKey = path_key
                        local max_chunk = 30
                        local idx = 1
                        while idx <= #path_parts do
                            local last = math.min(idx + max_chunk - 1, #path_parts)
                            local chunk = table.concat(path_parts, ",", idx, last)
                            helpers.logInfoTS(
                                string.format(
                                    "TaxiPath: %s %s %d/%d %s",
                                    tostring(icao),
                                    tostring(comp._runwayName or ""),
                                    idx,
                                    #path_parts,
                                    chunk
                                )
                            )
                            idx = last + 1
                        end
                        local labels = comp._routeLabels or build_route_labels(route.data, route.path)
                        if labels and #labels > 0 then
                            helpers.logInfoTS(
                                "TaxiLabels: " .. tostring(icao) .. " " .. tostring(comp._runwayName or "") .. " " .. table.concat(labels, " ")
                            )
                        else
                            helpers.logInfoTS("TaxiLabels: " .. tostring(icao) .. " " .. tostring(comp._runwayName or "") .. " <none>")
                        end
                    end
                    if comp._pendingRerouteEvent then
                        if comp._lastForwardPathKey ~= fwd_key then
                            record_reroute_event(comp, now)
                            comp._lastForwardPathKey = fwd_key
                        end
                        comp._pendingRerouteEvent = nil
                    end
                elseif rerr then
                    helpers.logInfoTS("Taxi: route error " .. tostring(icao) .. " mode=" .. tostring(mode) .. " err=" .. tostring(rerr))
                    log_taxi(
                        string.format(
                            "TaxiRoute: error=%s edit=%s draw=%s",
                            tostring(rerr),
                            tostring(in_edit),
                            tostring(comp._drawRoute)
                        )
                    )
                    comp._pendingRerouteEvent = nil
                end
                if route and route.bounds then
                    comp._fitBounds = route.bounds
                end
                comp._routeExtraSegments = nil
                if route and route.path and data and comp._runwayName and comp._runwayName ~= "" then
                    local profile = compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
                    if profile then
                        local backtrack_node = nil
                        local backtrack_target = nil
                        if mode == 1 and backtrack_required and (not comp._arrOffRunwayHandled) then
                            backtrack_node = arr_exit_id or route.path[1]
                            backtrack_target = profile.touchdown or profile.threshold
                        elseif mode == 0 and not allow_runway_route then
                            backtrack_node = comp._selectedDepEntryId or dep_holdshort_id or dep_end_node_id or route.end_id or route.path[#route.path]
                            backtrack_target = profile.threshold
                        end
                        if backtrack_node then
                            comp._routeExtraSegments = build_runway_backtrack_segments(data, profile, backtrack_node, backtrack_target)
                        end
                    end
                end
                comp._lastGuidanceNodeId = nil
                comp._lastGuidanceLabel = nil
                comp._lastGuidanceTime = nil
            else
                helpers.logInfoTS(
                    "TaxiDiag: route-skip icao=" .. tostring(icao) ..
                    " mode=" .. tostring(mode) ..
                    " canRoute=" .. tostring(canRoute) ..
                    " start_valid=" .. tostring(is_valid_latlon(start_lat, start_lon)) ..
                    " end_valid=" .. tostring(is_valid_latlon(end_lat, end_lon))
                )
                comp._route = nil
                comp._routeErr = canRoute and "route-endpoints-missing" or "no-routes"
                comp._routeLabels = nil
                log_taxi("TaxiRoute: skip err=" .. tostring(comp._routeErr))
            end
        end

        comp._depThresholdState = nil
        comp._depThresholdReached = false
        if mode == 0 and dep_profile and aircraft and aircraft.east ~= nil and aircraft.north ~= nil then
            local state = compute_dep_threshold_state(comp, dep_profile, runway_lat, runway_lon, aircraft)
            comp._depThresholdState = state
            comp._depThresholdReached = state and state.reached or false
            if comp._depThresholdReached then
                comp._depThresholdLatched = true
            end
            if comp._lastDepThresholdReached ~= comp._depThresholdReached then
                comp._lastDepThresholdReached = comp._depThresholdReached
                helpers.logInfoTS(
                    string.format(
                        "TaxiDepThreshold: reached=%s dist=%.1f perp=%.1f hdgDiff=%s corridor=%.1f",
                        tostring(comp._depThresholdReached),
                        state and state.dist or -1,
                        state and state.perp or -1,
                        state and state.heading_diff and string.format("%.1f", state.heading_diff) or "nil",
                        state and state.corridor or -1
                    )
                )
            end
        else
            comp._lastDepThresholdReached = nil
            comp._depThresholdLatched = false
        end

        if mode == 0 and not comp._depThresholdLatched then
            local yal = comp.yal or _G.yal
            local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
            local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
            local onRunway = false
            if onGround and comp.yal and comp.yal.aircraftonrwy then
                onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, depThresholdHeadingLimit)
            end
            if onGround and onRunway and gs >= depTakeoffLatchSpeed then
                if not comp._takeoffLatchSince then
                    comp._takeoffLatchSince = now
                end
                if (now - comp._takeoffLatchSince) >= depTakeoffLatchHoldSec then
                    comp._depThresholdLatched = true
                    comp._takeoffLatchSince = nil
                    helpers.logInfoTS(
                        string.format("TaxiDepThreshold: latched=takeoff-roll gs=%.1f", gs)
                    )
                end
            else
                comp._takeoffLatchSince = nil
            end
        else
            comp._takeoffLatchSince = nil
        end

        if mode ~= 0 then
            comp._depThresholdLatched = false
        elseif comp._depThresholdLatched then
            local yal = comp.yal or _G.yal
            local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
            if not onGround then
                comp._depThresholdLatched = false
            elseif comp.yal and comp.yal.aircraftonrwy and is_valid_latlon(runway_lat, runway_lon) then
                local onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, 20)
                local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
                if (not onRunway) and gs < 5 then
                    comp._depThresholdLatched = false
                end
            end
        end

        if not in_edit then
            if comp._route and aircraft and aircraft.east and aircraft.north then
                local yal = comp.yal or _G.yal
                local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
                local tirespeed = yal and yal.tirespeed and (get(yal.tirespeed) or 0) or 0
                local skip_reroute = false
                if comp._drawFreehand and comp._routeWaypoints and #comp._routeWaypoints > 0 then
                    skip_reroute = true
                end
                if onGround and tirespeed > 1 and not (mode == 0 and comp._depThresholdLatched) and (not skip_reroute) then
                    if mode == 1 and comp.yal and comp.yal.aircraftonrwy and is_valid_latlon(runway_lat, runway_lon) then
                        local offRunway = comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
                        if not offRunway then
                            return
                        end
                    end
                    if mode == 1 and comp.yal and comp.yal.aircraftonrwy and is_valid_latlon(runway_lat, runway_lon) then
                        local offRunway = comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
                        if offRunway and not comp._arrOffRunwayHandled then
                            comp._arrOffRunwayHandled = true
                            if not comp._rerouteOverride then
                                comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
                                if not arrival_grace_active(comp, now) then
                                    comp._pendingRerouteEvent = true
                                end
                                comp._lastRerouteTime = now
                                comp._lastStartKey = nil
                                comp._route = nil
                                comp._routeErr = nil
                                comp._routeLabels = nil
                                comp._routeLabelStats = nil
                            end
                            log_taxi("TaxiRoute: off-runway reroute latch")
                            return
                        end
                    end
                    local routeData = comp._route.data
                    local dist = distance_to_route(routeData, comp._route.path, aircraft.east, aircraft.north)
                    if comp._routeExtraSegments then
                        local extra = distance_to_segments(comp._routeExtraSegments, aircraft.east, aircraft.north)
                        if extra and (not dist or extra < dist) then
                            dist = extra
                        end
                    end
                    comp._lastRouteDist = dist
                    local lastReroute = comp._lastRerouteTime or 0
                    local skipReroute = false
                    if mode == 1 then
                        local lastCompute = comp._lastRouteComputeTime or 0
                        if lastCompute > 0 and (now - lastCompute) < 2 then
                            local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
                            if dist and dist <= (rerouteDriftMeters * 3) and gs < 25 then
                                skipReroute = true
                            end
                        end
                    end
                    if dist and dist > rerouteDriftMeters and (now - lastReroute) > rerouteCooldown then
                        comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
                        if not arrival_grace_active(comp, now) then
                            comp._pendingRerouteEvent = true
                        end
                        comp._lastRerouteTime = now
                        comp._lastStartKey = nil
                        comp._route = nil
                        comp._routeErr = nil
                        comp._routeLabels = nil
                        comp._routeLabelStats = nil
                    end
                end
            end

            if comp._route then
                if maybe_force_global_for_quality(comp, now, icao, mode, data, helpers) then
                    update_visual_guidance(comp, now, aircraft)
                    return
                end
                maybe_speak_guidance(comp, now, aircraft)
            end
            if comp.mode == 0 and not comp._depTaxiCompleteAnnounced and comp._runwayName and comp._runwayName ~= "" then
                local yal = comp.yal or _G.yal
                local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
                if onGround and comp.yal and comp.yal.aircraftonrwy then
                    local onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, depThresholdHeadingLimit)
                    if onRunway then
                        if not comp._depRunwayEntryAnnounced then
                            local rwy_phrase = runway_label_voice(comp._runwayName)
                            local entry_text = "Enter departure " .. rwy_phrase
                            local entry_action = "ENTER RWY"
                            local entry_direction = "straight"
                            local entry_label = build_visual_label("runway", normalize_runway_name(comp._runwayName))
                            local turn_threshold = 15
                            if comp._route and comp._route.path and comp._route.data and dep_profile and dep_profile.axis then
                                local path = comp._route.path
                                local data = comp._route.data
                                if #path >= 2 then
                                    local v1x, v1y = nil, nil
                                    local found = false
                                    local runway_nodes = data.runway_nodes
                                    if runway_nodes then
                                        for i = #path - 1, 1, -1 do
                                            local id1 = path[i]
                                            local id2 = path[i + 1]
                                            local is1 = runway_nodes[id1] and true or false
                                            local is2 = runway_nodes[id2] and true or false
                                            if is1 ~= is2 then
                                                local n1 = data.nodes and data.nodes[id1] or nil
                                                local n2 = data.nodes and data.nodes[id2] or nil
                                                if n1 and n2 and n1.east and n1.north and n2.east and n2.north then
                                                    if is1 and (not is2) then
                                                        v1x = n1.east - n2.east
                                                        v1y = n1.north - n2.north
                                                    else
                                                        v1x = n2.east - n1.east
                                                        v1y = n2.north - n1.north
                                                    end
                                                    found = true
                                                end
                                                break
                                            end
                                        end
                                    end
                                    if not found then
                                        local n1 = data.nodes and data.nodes[path[#path - 1]] or nil
                                        local n2 = data.nodes and data.nodes[path[#path]] or nil
                                        if n1 and n2 and n1.east and n1.north and n2.east and n2.north then
                                            v1x = n2.east - n1.east
                                            v1y = n2.north - n1.north
                                            found = true
                                        end
                                    end
                                    if found then
                                        local len1 = math.sqrt(v1x * v1x + v1y * v1y)
                                        local v2x = dep_profile.axis.x or 0
                                        local v2y = dep_profile.axis.y or 0
                                        local len2 = math.sqrt(v2x * v2x + v2y * v2y)
                                        if len1 > 0.1 and len2 > 0.1 then
                                            local dot = (v1x * v2x + v1y * v2y) / (len1 * len2)
                                            if dot > 1 then dot = 1 end
                                            if dot < -1 then dot = -1 end
                                            local angle = math.deg(math.acos(dot))
                                            if angle >= turn_threshold then
                                                local cross = v1x * v2y - v1y * v2x
                                                local turn = (cross >= 0) and "left" or "right"
                                                entry_text = "Turn " .. turn .. " on departure " .. rwy_phrase
                                                entry_action = (turn == "left") and "TURN LEFT" or "TURN RIGHT"
                                                entry_direction = turn
                                            end
                                        end
                                    end
                                end
                            end
                            emit_guidance(comp, now, {
                                text = entry_text,
                                direction = entry_direction,
                                action = entry_action,
                                label = entry_label,
                                kind = "runway"
                            }, is_auto_taxi_guidance_enabled())
                            comp._depRunwayEntryAnnounced = true
                        end
                        if comp._depThresholdLatched or comp._depThresholdReached then
                            local rwy_phrase = runway_label_voice(comp._runwayName)
                            emit_guidance(comp, now, {
                                text = "On departure " .. rwy_phrase .. ", taxi complete",
                                direction = "straight",
                                action = "TAXI COMPLETE",
                                label = build_visual_label("runway", normalize_runway_name(comp._runwayName)),
                                kind = "runway",
                                queue = true
                            }, is_auto_taxi_guidance_enabled())
                            comp._depTaxiCompleteAnnounced = true
                        end
                    end
                end
            end
            if comp.mode == 1 and not comp._arrTaxiCompleteAnnounced then
                local yalref = comp.yal or _G.yal
                local onGround = yalref and yalref.airgroundsensor and (get(yalref.airgroundsensor) == def.ON)
                local gs = yalref and yalref.groundspeed and (get(yalref.groundspeed) or 0) or 0
                local park = yalref and yalref.parkingbrakepos and get(yalref.parkingbrakepos) or nil
                if onGround and park == def.ON and gs < 1 and aircraft and is_valid_latlon(aircraft.lat, aircraft.lon) then
                    if not nearest_ramp then
                        nearest_ramp = helpers.getNearestRamp(
                            icao,
                            aircraft.lat,
                            aircraft.lon,
                            { filter = helpers.isRampSuitableFor738, data = comp._data }
                        )
                        if nearest_ramp and is_valid_latlon(nearest_ramp.lat, nearest_ramp.lon) then
                            nearest_ramp_dist = distance_meters_latlon(
                                nearest_ramp.lat,
                                nearest_ramp.lon,
                                aircraft.lat,
                                aircraft.lon
                            )
                        end
                    end
                    local pb_dist = tuning.parkingBrakeCompleteDist or 35
                    if nearest_ramp and nearest_ramp_dist and nearest_ramp_dist <= pb_dist then
                        local ramp_label = short_ramp_label(nearest_ramp)
                        emit_guidance(comp, now, {
                            text = "Taxi complete",
                            direction = "straight",
                            action = "TAXI COMPLETE",
                            label = ramp_label,
                            kind = "ramp"
                        }, is_auto_taxi_guidance_enabled())
                        comp._arrTaxiCompleteAnnounced = true
                        comp._route = nil
                        comp._routeErr = "taxi-complete"
                        comp._routeLabels = nil
                        comp._routeLabelStats = nil
                        comp._routeExtraSegments = nil
                        comp._lastStartKey = nil
                        comp._lastEndKey = nil
                        comp._visualGuidanceQueue = {}
                        log_taxi("TaxiRoute: taxi complete parking brake")
                    end
                end
            end
            update_visual_guidance(comp, now, aircraft)
        end

        comp._aircraftPoint = nil
        if aircraft and aircraft.east ~= nil and aircraft.north ~= nil then
            comp._aircraftPoint = { east = aircraft.east, north = aircraft.north }
        end

        if comp._fitBounds and comp._aircraftPoint then
            local b = comp._fitBounds
            local outside = false
            if b.minX and b.maxX and b.minY and b.maxY then
                outside = (comp._aircraftPoint.east < b.minX) or (comp._aircraftPoint.east > b.maxX)
                    or (comp._aircraftPoint.north < b.minY) or (comp._aircraftPoint.north > b.maxY)
            end
            local log_key = tostring(comp._lastIcao or "") .. "|" .. tostring(comp.mode or "") .. "|" .. tostring(outside)
            if comp._lastBoundsLogKey ~= log_key then
                comp._lastBoundsLogKey = log_key
                helpers.logInfoTS(
                    string.format(
                        "TaxiBounds: mode=%s icao=%s outside=%s bounds=[%.1f..%.1f, %.1f..%.1f] aircraft=%.1f/%.1f",
                        tostring(comp.mode),
                        tostring(comp._lastIcao or ""),
                        tostring(outside),
                        b.minX or 0,
                        b.maxX or 0,
                        b.minY or 0,
                        b.maxY or 0,
                        comp._aircraftPoint.east or 0,
                        comp._aircraftPoint.north or 0
                    )
                )
            end
        end

        comp._startPoint = nil
        if is_valid_latlon(start_lat, start_lon) then
            local sx, sy = latlon_to_local(start_lat, start_lon)
            comp._startPoint = { east = sx, north = sy }
        end
        comp._endPoint = nil
        if is_valid_latlon(end_lat, end_lon) then
            local ex, ey = latlon_to_local(end_lat, end_lon)
            comp._endPoint = { east = ex, north = ey }
        end

        if in_edit then
            if comp._route and comp._route.path and comp._route.data then
                build_edit_handles(comp, start_lat, start_lon, end_lat, end_lon)
            else
                comp._editHandles = nil
            end
        else
            comp._editHandles = nil
        end

        local route_state_key = string.format("%s|%s", tostring(comp._route ~= nil), tostring(comp._routeErr or ""))
        if comp._lastRouteStateKey ~= route_state_key then
            comp._lastRouteStateKey = route_state_key
            log_taxi(
                string.format(
                    "TaxiRoute: state route=%s err=%s edit=%s draw=%s",
                    tostring(comp._route ~= nil),
                    tostring(comp._routeErr),
                    tostring(in_edit),
                    tostring(comp._drawRoute)
                )
            )
        end

        if comp._needsCenter and comp._fitBounds then
            local cx, cy = compute_bounds_center(comp._fitBounds)
            set_center(cx, cy)
            comp._needsCenter = false
        end
    end

    function comp:getPushbackHint()
        if comp.mode ~= 0 then
            return nil
        end
        local path = comp._route and comp._route.path or nil
        local data = comp._route and comp._route.data or nil
        local n1 = nil
        local n2 = nil
        local label = ""
        if path and data and #path >= 2 then
            for i = 1, #path - 1 do
                local a = data.nodes and data.nodes[path[i]] or nil
                local b = data.nodes and data.nodes[path[i + 1]] or nil
                if a and b and a.east and a.north and b.east and b.north then
                    if a.is_ramp or b.is_ramp then
                        goto continue
                    end
                    local raw_label = get_edge_label(data, path[i], path[i + 1])
                    if raw_label == "RAMP" or (raw_label and is_runway_label(raw_label)) then
                        goto continue
                    end
                    local dx = b.east - a.east
                    local dy = b.north - a.north
                    if dx ~= 0 or dy ~= 0 then
                        n1 = a
                        n2 = b
                        label = raw_label or ""
                        break
                    end
                end
                ::continue::
            end
        end
        if not n1 or not n2 then
            if comp._aircraftPoint and comp._data then
                local proj = find_nearest_edge_projection(
                    comp._data,
                    comp._aircraftPoint.east,
                    comp._aircraftPoint.north,
                    { disallow_runway_edges = true }
                )
                if proj and proj.edge and proj.edge.a and proj.edge.b then
                    local a = comp._data.nodes and comp._data.nodes[proj.edge.a] or nil
                    local b = comp._data.nodes and comp._data.nodes[proj.edge.b] or nil
                    if a and b and a.east and a.north and b.east and b.north then
                        n1 = a
                        n2 = b
                        label = proj.edge.label or ""
                    end
                end
            end
        end
        if not n1 or not n2 or n1.east == nil or n1.north == nil or n2.east == nil or n2.north == nil then
            return nil
        end
        local dx = n2.east - n1.east
        local dy = n2.north - n1.north
        if dx == 0 and dy == 0 then
            return nil
        end
        local heading = math.deg(math.atan2(dx, dy))
        if heading < 0 then
            heading = heading + 360
        end
        heading = helpers.roundnumber(heading, 0)
        local compass = heading_to_compass(heading)
        label = normalize_taxiway_label(label)
        if label and label ~= "" then
            return "nose toward Taxiway " .. taxiway_label_voice(label) .. " heading " .. tostring(compass)
        end
        return "nose toward heading " .. tostring(compass)
    end

    function comp:clearVisualGuidance()
        clear_visual_guidance(comp, "manual-clear")
    end

    function comp:clearVisualGuidanceQueue()
        comp._visualGuidanceQueue = {}
    end

    function comp:tick()
        local ww = defaultW
        local hh = defaultH
        if comp._window and comp._window.getPosition then
            local _, _, wpos, hpos = comp._window:getPosition()
            ww = tonumber(wpos) or ww
            hh = tonumber(hpos) or hh
        end
        local now = 0
        if comp._timer then
            now = sasl.getElapsedSeconds(comp._timer) or 0
        end
        local vis = comp._window and comp._window.isVisible and comp._window:isVisible() or false
        if vis and not comp._lastVisible then
            if comp._data and comp._data.bounds then
                comp._fitBounds = comp._data.bounds
            end
            comp._needsCenter = true
        end
        if vis ~= comp._lastVisible then
            log_taxi(
                string.format(
                    "TaxiWindow: visible=%s route=%s err=%s edit=%s draw=%s",
                    tostring(vis),
                    tostring(comp._route ~= nil),
                    tostring(comp._routeErr),
                    tostring(comp._editRoute),
                    tostring(comp._drawRoute)
                )
            )
        end
        comp._lastVisible = vis

        if comp._visualGuidance then
            local U = comp._U or {}
            local update_visual_guidance = U.update_visual_guidance
            if update_visual_guidance then
                local aircraft = nil
                local yal = comp.yal or _G.yal
                if yal and yal.aircraftlatpos and yal.aircraftlonpos and U.is_valid_latlon and U.latlon_to_local then
                    local lat = get(yal.aircraftlatpos)
                    local lon = get(yal.aircraftlonpos)
                    if U.is_valid_latlon(lat, lon) then
                        local ae, an = U.latlon_to_local(lat, lon)
                        if ae and an then
                            aircraft = { east = ae, north = an, lat = lat, lon = lon }
                        end
                    end
                end
                update_visual_guidance(comp, now, aircraft)
            end
        end
    end

    return comp
end

function M.newComponent(ctx)
    return newComponentImpl(ctx, def, settings, helpers, C, U)
end
return M
