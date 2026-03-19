local M = {}
local C = require("windows.taxi_constants")
local U
local guidance_distance_for_speed
local speak_guidance_text
local build_visual_label
local is_taxi_complete_info
local set_visual_guidance
local queue_visual_guidance
local clear_visual_guidance
local set_guidance_state
local update_visual_guidance
local emit_guidance

local def = require("definitions")
local settings = require("settings")
local helpers = require("helpers")

local function log_taxi(message)
    if helpers and helpers.logInfoTS then
        helpers.logInfoTS(message)
    end
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
        half = (width * 0.5) + C.depRunwayCorridorBuffer
    else
        half = 35
    end
    if half < C.depRunwayCorridorMin then
        half = C.depRunwayCorridorMin
    end
    if C.depRunwayCorridorMax and half > C.depRunwayCorridorMax then
        half = C.depRunwayCorridorMax
    end
    return half
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

local taxi_ref_lat = nil
local taxi_ref_lon = nil
local taxi_ref_mlat = nil
local taxi_ref_mlon = nil

local function set_taxi_ref(data)
    taxi_ref_lat = data and data.ref_lat or nil
    taxi_ref_lon = data and data.ref_lon or nil
    taxi_ref_mlat = data and data.ref_mlat or nil
    taxi_ref_mlon = data and data.ref_mlon or nil
end

local function ensure_ref_scale()
    if taxi_ref_lat and (not taxi_ref_mlat or not taxi_ref_mlon) then
        if helpers and helpers.geoScale then
            taxi_ref_mlat, taxi_ref_mlon = helpers.geoScale(taxi_ref_lat)
        end
    end
end

local function latlon_to_local(lat, lon)
    if taxi_ref_lat and taxi_ref_lon and lat and lon then
        ensure_ref_scale()
        if taxi_ref_mlat and taxi_ref_mlon then
            local east = (lon - taxi_ref_lon) * taxi_ref_mlon
            local north = (lat - taxi_ref_lat) * taxi_ref_mlat
            return east, north
        end
    end
    local x, _, z = sasl.worldToLocal(lat, lon, 0)
    return x, -z
end

local function screen_to_world_from_transform(t, sx, sy)
    if not t or not sx or not sy then
        return nil, nil
    end
    local dx = (sx - (t.mapX + t.mapW * 0.5) - (t.panX or 0)) / (t.scale or 1)
    local dy = (sy - (t.mapY + t.mapH * 0.5) - (t.panY or 0)) / (t.scale or 1)
    dx, dy = rotate_point(dx, dy, -t.rot)
    return t.centerEast + dx, t.centerNorth + dy
end

local function local_to_latlon(east, north)
    if taxi_ref_lat and taxi_ref_lon and east ~= nil and north ~= nil then
        ensure_ref_scale()
        if taxi_ref_mlat and taxi_ref_mlon then
            local lat = taxi_ref_lat + (north / taxi_ref_mlat)
            local lon = taxi_ref_lon + (east / taxi_ref_mlon)
            return lat, lon
        end
    end
    local lat, lon = sasl.localToWorld(east or 0, 0, -(north or 0))
    return lat, lon
end

local function ensure_waypoint_latlon(wp)
    if not wp then
        return nil, nil
    end
    if is_valid_latlon(wp.lat, wp.lon) then
        return wp.lat, wp.lon
    end
    if wp.east ~= nil and wp.north ~= nil then
        local lat, lon = local_to_latlon(wp.east, wp.north)
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
        if helpers and helpers.logInfoTS then
            helpers.logInfoTS("TaxiProj: skip no-ref")
        end
        return false, 0, 0
    end
    local cur_east, cur_north = latlon_to_local(ref.lat, ref.lon)
    if cur_east == nil or cur_north == nil then
        if helpers and helpers.logInfoTS then
            helpers.logInfoTS("TaxiProj: skip ref->local failed")
        end
        return false, 0, 0
    end
    local dx = cur_east - (ref_east or 0)
    local dy = cur_north - (ref_north or 0)
    local ax = math.abs(dx)
    local ay = math.abs(dy)
    if ax < 1 and ay < 1 then
        if helpers and helpers.logInfoTS then
            helpers.logInfoTS(string.format("TaxiProj: skip tiny shift dx=%.2f dy=%.2f", dx, dy))
        end
        return false, dx, dy
    end
    if ax > C.projectionShiftThreshold or ay > C.projectionShiftThreshold then
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
            local before_far = d2_before > (C.projectionShiftThreshold * C.projectionShiftThreshold)
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
                            "TaxiProj: skip large shift reason=large dx=%.1f dy=%.1f d2_before=%s d2_after=%s",
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
        local second_has_alpha = false
        for i = 1, #parts[2] do
            local b = string.byte(parts[2], i)
            if b and b >= 65 and b <= 90 then
                second_has_alpha = true
                break
            end
        end
        if second_has_alpha then
            clean = parts[2]
        end
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
    return helpers.spellNato(clean)
end

local function format_runway_designator_text(label)
    if not label or label == "" then
        return ""
    end
    local clean = string.upper(tostring(label))
    if string.sub(clean, 1, 3) == "RWY" then
        clean = trim_spaces(string.gsub(clean, "^RWY[%s_%-/]*", ""))
    end
    clean = string.gsub(clean, "%s+", "")
    if clean == "" then
        return ""
    end
    local parts = {}
    for part in string.gmatch(clean, "[^/]+") do
        part = trim_spaces(part)
        if part ~= "" then
            local formatted = part
            if helpers and helpers.formatRunwayDesignator then
                formatted = helpers.formatRunwayDesignator(part)
            end
            parts[#parts + 1] = formatted
        end
    end
    return table.concat(parts, " / ")
end

local function clean_runway_label_keep_slash(label)
    local s = string.upper(tostring(label or ""))
    if string.sub(s, 1, 3) == "RWY" then
        s = trim_spaces(string.gsub(s, "^RWY[%s_%-/]*", ""))
    end
    s = string.gsub(s, "[%s_%-]+", "")
    return s
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

local function normalize_runway_pair_label(label)
    if not label or label == "" then
        return ""
    end
    local raw = clean_runway_label_keep_slash(label)
    if raw == "" then
        return ""
    end
    local parts = {}
    if raw:find("/") then
        for part in string.gmatch(raw, "[^/]+") do
            part = trim_spaces(part)
            if part ~= "" then
                parts[#parts + 1] = part
            end
        end
    else
        local len = #raw
        if len < 4 then
            return raw
        end
        local i = 1
        while i <= len do
            local num = raw:sub(i, i + 1)
            if #num < 2 then
                break
            end
            local suffix = ""
            local j = i + 2
            if j <= len then
                local ch = raw:sub(j, j)
                if ch:match("%a") then
                    suffix = ch
                    j = j + 1
                end
            end
            parts[#parts + 1] = num .. suffix
            i = j
        end
    end
    if #parts >= 2 then
        local n1, s1 = parse_runway_parts(parts[1])
        local n2, s2 = parse_runway_parts(parts[2])
        if n1 and n2 then
            local opp = n1 + 18
            if opp > 36 then
                opp = opp - 36
            end
            local function opposite_suffix(s)
                if s == "L" then
                    return "R"
                elseif s == "R" then
                    return "L"
                elseif s == "C" then
                    return "C"
                end
                return ""
            end
            if opp == n2 then
                if s1 ~= "" and s2 == "" then
                    s2 = opposite_suffix(s1)
                elseif s2 ~= "" and s1 == "" then
                    s1 = opposite_suffix(s2)
                end
            end
            if s1 and s1 ~= "" then
                parts[1] = string.format("%02d%s", n1, s1)
            else
                parts[1] = string.format("%02d", n1)
            end
            if s2 and s2 ~= "" then
                parts[2] = string.format("%02d%s", n2, s2)
            else
                parts[2] = string.format("%02d", n2)
            end
        end
    end
    return table.concat(parts, "/")
end

local function runway_label_voice(label)
    if not label or label == "" then
        return "Runway"
    end
    local normalized = normalize_runway_pair_label(label)
    local formatted = format_runway_designator_text(normalized)
    if formatted == "" then
        return "Runway"
    end
    return "Runway " .. formatted
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
                    local dot = (vx * dir_e + vy * dir_n) * inv_len
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
        local lat, lon = local_to_latlon(ex, ny)
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

local function find_nearest_runway_entry_by_latlon(data, runway_lat, runway_lon)
    if not data or not data.runways or not runway_lat or not runway_lon then
        return nil
    end
    local best_rwy = nil
    local best_side = nil
    local best_d2 = nil
    for _, rwy in ipairs(data.runways) do
        if rwy.lat1 and rwy.lon1 then
            local dlat = rwy.lat1 - runway_lat
            local dlon = rwy.lon1 - runway_lon
            local d2 = dlat * dlat + dlon * dlon
            if (not best_d2) or d2 < best_d2 then
                best_d2 = d2
                best_rwy = rwy
                best_side = 1
            end
        end
        if rwy.lat2 and rwy.lon2 then
            local dlat = rwy.lat2 - runway_lat
            local dlon = rwy.lon2 - runway_lon
            local d2 = dlat * dlat + dlon * dlon
            if (not best_d2) or d2 < best_d2 then
                best_d2 = d2
                best_rwy = rwy
                best_side = 2
            end
        end
    end
    return best_rwy, best_side
end

local function compute_runway_landing_profile(data, runway_name, runway_lat, runway_lon)
    local rwy, side = find_runway_entry(data, runway_name, runway_lat, runway_lon)
    if not rwy and runway_lat and runway_lon then
        rwy, side = find_nearest_runway_entry_by_latlon(data, runway_lat, runway_lon)
    end
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

local function infer_arrival_runway_from_aircraft(data, aircraft)
    if not data or not data.runways or not aircraft then
        return nil
    end
    if aircraft.east == nil or aircraft.north == nil then
        return nil
    end
    local yalref = _G.yal
    local track_mag = yalref and yalref.groundtrackmag and get(yalref.groundtrackmag) or nil
    local hdg_true = yalref and yalref.localpositionpsi and get(yalref.localpositionpsi) or nil
    local best = nil
    for _, rwy in ipairs(data.runways) do
        for side = 1, 2 do
            local name = (side == 1) and rwy.rwy1 or rwy.rwy2
            local lat = (side == 1) and rwy.lat1 or rwy.lat2
            local lon = (side == 1) and rwy.lon1 or rwy.lon2
            if name and name ~= "" and lat and lon then
                local profile = compute_runway_landing_profile(data, name, lat, lon)
                if profile then
                    local along, perp = compute_along_perp(profile, aircraft)
                    local corridor = runway_corridor_half_width(profile) + 10
                    local len = tonumber(profile.length) or 0
                    if along and perp and perp <= corridor and along >= -120 and along <= (len + 120) then
                        local axis_heading_true = math.deg(math.atan2(profile.axis.x, profile.axis.y))
                        if axis_heading_true < 0 then
                            axis_heading_true = axis_heading_true + 360
                        end
                        local mag_var = nil
                        if aircraft.lat and aircraft.lon then
                            mag_var = sasl.getMagneticVariation(aircraft.lat, aircraft.lon)
                        end
                        if mag_var == nil then
                            mag_var = sasl.getMagneticVariation(lat, lon)
                        end
                        mag_var = mag_var or 0
                        local axis_heading_mag = (axis_heading_true - mag_var + 360) % 360
                        local heading_diff = nil
                        if track_mag ~= nil then
                            heading_diff = helpers.headingdiff(track_mag, axis_heading_mag)
                        end
                        if hdg_true ~= nil then
                            local hdg_mag = (hdg_true - mag_var + 360) % 360
                            local diff = helpers.headingdiff(hdg_mag, axis_heading_mag)
                            if heading_diff == nil or diff < heading_diff then
                                heading_diff = diff
                            end
                        end
                        local score = perp
                        if heading_diff ~= nil then
                            score = score + (heading_diff * 2)
                        end
                        if along < -30 or along > (len + 60) then
                            score = score + 200
                        end
                        if (not best) or score < best.score then
                            best = {
                                name = name,
                                lat = lat,
                                lon = lon,
                                profile = profile,
                                side = side,
                                heading_diff = heading_diff,
                                along = along,
                                perp = perp,
                                score = score
                            }
                        end
                    end
                end
            end
        end
    end
    if best and best.heading_diff ~= nil and best.heading_diff > 90 then
        return nil
    end
    return best
end

local function find_nearest_runway_node(data, east, north)
    if not data or not data.nodes or not data.runway_nodes then
        return nil
    end
    local best_id = nil
    local best_d2 = nil
    local tie_eps = 0.000001
    for id, node in pairs(data.nodes) do
        if data.runway_nodes[id] and node.east and node.north then
            local dx = node.east - east
            local dy = node.north - north
            local d2 = dx * dx + dy * dy
            local better = false
            if not best_d2 or d2 < (best_d2 - tie_eps) then
                better = true
            elseif best_d2 and math.abs(d2 - best_d2) <= tie_eps and best_id ~= nil then
                local id_num = tonumber(id)
                local best_num = tonumber(best_id)
                if id_num and best_num then
                    better = id_num < best_num
                else
                    better = tostring(id) < tostring(best_id)
                end
            end
            if better then
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

local function clear_temp_route_overlay(comp, data)
    if not comp or not data then
        return
    end
    if comp._tempRouteNodes and data.nodes then
        for _, id in ipairs(comp._tempRouteNodes) do
            data.nodes[id] = nil
        end
    end
    if comp._tempRouteNodes and data.runway_nodes then
        for _, id in ipairs(comp._tempRouteNodes) do
            data.runway_nodes[id] = nil
        end
    end
    if data._tempEdgeLabels and comp._tempRouteEdgeKeys then
        for _, key in ipairs(comp._tempRouteEdgeKeys) do
            data._tempEdgeLabels[key] = nil
        end
        if next(data._tempEdgeLabels) == nil then
            data._tempEdgeLabels = nil
        end
    end
    comp._tempRouteNodes = nil
    comp._tempRouteEdgeKeys = nil
    comp._tempRouteNodeSeq = nil
end

local function add_temp_route_node(comp, data, east, north)
    if not comp or not data or not data.nodes then
        return nil
    end
    if east == nil or north == nil then
        return nil
    end
    comp._tempRouteNodeSeq = (comp._tempRouteNodeSeq or 0) + 1
    local node_id = -comp._tempRouteNodeSeq
    local node = { east = east, north = north, is_temp = true }
    local lat, lon = local_to_latlon(east, north)
    if is_valid_latlon(lat, lon) then
        node.lat = lat
        node.lon = lon
    end
    data.nodes[node_id] = node
    comp._tempRouteNodes = comp._tempRouteNodes or {}
    comp._tempRouteNodes[#comp._tempRouteNodes + 1] = node_id
    return node_id
end

local function add_temp_edge_label(comp, data, from_id, to_id, label)
    if not comp or not data or not from_id or not to_id then
        return
    end
    if label == nil then
        return
    end
    local key = tostring(from_id) .. ":" .. tostring(to_id)
    data._tempEdgeLabels = data._tempEdgeLabels or {}
    data._tempEdgeLabels[key] = label
    comp._tempRouteEdgeKeys = comp._tempRouteEdgeKeys or {}
    comp._tempRouteEdgeKeys[#comp._tempRouteEdgeKeys + 1] = key
end

local function apply_backtrack_segments_to_route(comp, route, data, backtrack_node_id, segments, runway_label)
    if not comp or not route or not data or not segments or #segments == 0 then
        return false
    end
    if not route.path or #route.path < 1 then
        return false
    end
    if not data.nodes then
        return false
    end
    local path = route.path
    local at_start = (path[1] == backtrack_node_id)
    local at_end = (path[#path] == backtrack_node_id)
    if not at_start and not at_end then
        return false
    end
    local last_seg = segments[#segments]
    if not last_seg or last_seg.east1 == nil or last_seg.north1 == nil or last_seg.east2 == nil or last_seg.north2 == nil then
        return false
    end
    local entry_e = last_seg.east1
    local entry_n = last_seg.north1
    local target_e = last_seg.east2
    local target_n = last_seg.north2
    if entry_e == nil or entry_n == nil or target_e == nil or target_n == nil then
        return false
    end
    local entry_id = add_temp_route_node(comp, data, entry_e, entry_n)
    local target_id = add_temp_route_node(comp, data, target_e, target_n)
    if not entry_id or not target_id then
        return false
    end
    if data.runway_nodes then
        data.runway_nodes[entry_id] = true
        data.runway_nodes[target_id] = true
    end
    if runway_label and runway_label ~= "" then
        add_temp_edge_label(comp, data, target_id, entry_id, runway_label)
        add_temp_edge_label(comp, data, entry_id, target_id, runway_label)
    end
    local new_path = {}
    local function add_unique(id)
        if id and (#new_path == 0 or new_path[#new_path] ~= id) then
            new_path[#new_path + 1] = id
        end
    end
    if at_start then
        add_unique(target_id)
        add_unique(entry_id)
        add_unique(backtrack_node_id)
        for _, id in ipairs(path) do
            add_unique(id)
        end
    else
        for _, id in ipairs(path) do
            add_unique(id)
        end
        add_unique(entry_id)
        add_unique(target_id)
    end
    route.path = new_path
    route.start_id = new_path[1]
    route.end_id = new_path[#new_path]
    if route.bounds then
        update_bounds(route.bounds, entry_e, entry_n)
        update_bounds(route.bounds, target_e, target_n)
    end
    return true
end

local function apply_dep_turnaround_stub(comp, route, data, profile, runway_label)
    if not comp or not route or not data or not profile or not route.path or #route.path < 1 then
        return false
    end
    if comp._depTurnaroundApplied then
        return false
    end
    if not data.nodes or not profile.threshold or not profile.axis then
        return false
    end
    local last_id = route.path[#route.path]
    local last_node = data.nodes[last_id]
    if not last_node or last_node.east == nil or last_node.north == nil then
        return false
    end
    local threshold = profile.threshold
    local dist2 = distance_sq(last_node.east, last_node.north, threshold.east, threshold.north)
    if dist2 > (35 * 35) then
        local along, perp = compute_along_perp(profile, last_node)
        if not along or not perp then
            return false
        end
        local corridor = runway_corridor_half_width(profile)
        local max_along = math.max(120, C.depThresholdGateMeters * 2.5)
        if perp > (corridor + 8) then
            return false
        end
        if along < -10 or along > max_along then
            return false
        end
    end
    local half = runway_corridor_half_width(profile)
    local offset = half - 5
    if offset > 12 then
        offset = 12
    elseif offset < 6 then
        offset = 6
    end
    local axis = profile.axis
    local px = -axis.y
    local py = axis.x
    local turn_e = threshold.east + px * offset
    local turn_n = threshold.north + py * offset
    local lineup_dist = 25
    local lineup_e = threshold.east + axis.x * lineup_dist
    local lineup_n = threshold.north + axis.y * lineup_dist
    local turn_id = add_temp_route_node(comp, data, turn_e, turn_n)
    local lineup_id = add_temp_route_node(comp, data, lineup_e, lineup_n)
    if not turn_id or not lineup_id then
        return false
    end
    if data.runway_nodes then
        data.runway_nodes[turn_id] = true
        data.runway_nodes[lineup_id] = true
    end
    if runway_label and runway_label ~= "" then
        add_temp_edge_label(comp, data, last_id, turn_id, runway_label)
        add_temp_edge_label(comp, data, turn_id, lineup_id, runway_label)
        add_temp_edge_label(comp, data, turn_id, last_id, runway_label)
        add_temp_edge_label(comp, data, lineup_id, turn_id, runway_label)
    end
    route.path[#route.path + 1] = turn_id
    route.path[#route.path + 1] = lineup_id
    route.end_id = lineup_id
    if route.bounds then
        update_bounds(route.bounds, turn_e, turn_n)
        update_bounds(route.bounds, lineup_e, lineup_n)
    end
    comp._depTurnaroundApplied = true
    return true
end

local collect_runway_exit_candidates

local function runway_pair_label(rwy)
    if not rwy then
        return ""
    end
    local a = normalize_runway_name(rwy.rwy1 or "")
    local b = normalize_runway_name(rwy.rwy2 or "")
    if a ~= "" and b ~= "" then
        return a .. "/" .. b
    end
    return a ~= "" and a or b
end

local function runway_end_label(rwy, prefer_side)
    if not rwy then
        return ""
    end
    local a = normalize_runway_name(rwy.rwy1 or "")
    local b = normalize_runway_name(rwy.rwy2 or "")
    if prefer_side == 1 then
        return a ~= "" and a or b
    end
    if prefer_side == 2 then
        return b ~= "" and b or a
    end
    return a ~= "" and a or b
end

local function runway_crossing_label(rwy, x1, y1, x2, y2)
    if not rwy or not rwy.east1 or not rwy.north1 or not rwy.east2 or not rwy.north2 then
        return runway_pair_label(rwy)
    end
    local rx1, ry1 = rwy.east1, rwy.north1
    local rx2, ry2 = rwy.east2, rwy.north2
    local dx = rx2 - rx1
    local dy = ry2 - ry1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 1 then
        return runway_pair_label(rwy)
    end
    local ux = dx / len
    local uy = dy / len
    local mx = (x1 + x2) * 0.5
    local my = (y1 + y2) * 0.5
    local along = (mx - rx1) * ux + (my - ry1) * uy
    local side = 1
    if along >= len * 0.5 then
        side = 2
    end
    local label = runway_end_label(rwy, side)
    if label == "" then
        label = runway_pair_label(rwy)
    end
    return label
end

local function segment_crosses_runway(rwy, x1, y1, x2, y2)
    if not rwy or not rwy.east1 or not rwy.north1 or not rwy.east2 or not rwy.north2 then
        return false
    end
    local rx1, ry1 = rwy.east1, rwy.north1
    local rx2, ry2 = rwy.east2, rwy.north2
    local dx = rx2 - rx1
    local dy = ry2 - ry1
    local len = math.sqrt(dx * dx + dy * dy)
    if len <= 1 then
        return false
    end
    local ux = dx / len
    local uy = dy / len
    local px = -uy
    local py = ux
    local function along_cross(x, y)
        local vx = x - rx1
        local vy = y - ry1
        local along = vx * ux + vy * uy
        local cross = vx * px + vy * py
        return along, cross
    end
    local a1, c1 = along_cross(x1, y1)
    local a2, c2 = along_cross(x2, y2)
    local pad = 5
    if math.max(a1, a2) < -pad or math.min(a1, a2) > (len + pad) then
        return false
    end
    local width = tonumber(rwy.width) or 0
    if width <= 0 then
        width = 45
    end
    local half = (width * 0.5) + 3
    if math.abs(c1) <= half and math.abs(c2) <= half then
        return false
    end
    local denom = (c1 - c2)
    if denom ~= 0 then
        local t = c1 / denom
        if t >= 0 and t <= 1 then
            local along = a1 + (a2 - a1) * t
            if along >= 0 and along <= len then
                return true
            end
        end
    end
    return false
end

local function find_runway_crossing(data, n1, n2)
    if not data or not data.runways or not n1 or not n2 then
        return nil, ""
    end
    if n1.east == nil or n1.north == nil or n2.east == nil or n2.north == nil then
        return nil, ""
    end
    for _, rwy in ipairs(data.runways) do
        if segment_crosses_runway(rwy, n1.east, n1.north, n2.east, n2.north) then
            return rwy, runway_crossing_label(rwy, n1.east, n1.north, n2.east, n2.north)
        end
    end
    return nil, ""
end

local function is_on_runway_profile(profile, aircraft, along_pad, perp_pad)
    if not profile or not aircraft or aircraft.east == nil or aircraft.north == nil then
        return false
    end
    local along, perp = compute_along_perp(profile, aircraft)
    if along == nil or perp == nil then
        return false
    end
    local len = tonumber(profile.length) or 0
    local pad = tonumber(along_pad) or 50
    if along < -pad or along > (len + pad) then
        return false
    end
    local half = runway_corridor_half_width(profile)
    if perp_pad then
        half = half + tonumber(perp_pad)
    end
    return perp <= half
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
    local heading_src = nil
    local heading_ok = false
    if track_mag ~= nil then
        heading_diff = helpers.headingdiff(track_mag, axis_heading_mag)
        heading_src = "track"
    end
    local hdg_true = yal and yal.localpositionpsi and get(yal.localpositionpsi) or nil
    if hdg_true ~= nil then
        local hdg_mag = (hdg_true - mag_var + 360) % 360
        local diff = helpers.headingdiff(hdg_mag, axis_heading_mag)
        if heading_diff == nil or diff < heading_diff then
            heading_diff = diff
            heading_src = "heading"
        end
    end
    if heading_diff ~= nil then
        heading_ok = heading_diff <= C.depThresholdHeadingLimit
    end
    local reached = (perp <= corridor) and heading_ok and (dist <= C.depThresholdGateMeters)
    return {
        reached = reached,
        dist = dist,
        along = along,
        along_to_threshold = along,
        perp = perp,
        corridor = corridor,
        heading_diff = heading_diff,
        heading_ok = heading_ok,
        heading_src = heading_src,
        axis_heading_mag = axis_heading_mag
    }
end

local function select_runway_exit_node(data, profile, preferred_side, airborne)
    if not data or not profile or not profile.touchdown or not profile.axis then
        return nil, false
    end
    local function side_sign(node)
        if not node or node.east == nil or node.north == nil then
            return nil
        end
        if not profile.threshold or profile.threshold.east == nil or profile.threshold.north == nil then
            return nil
        end
        local dx = node.east - profile.threshold.east
        local dy = node.north - profile.threshold.north
        local cross = dx * profile.axis.y - dy * profile.axis.x
        if math.abs(cross) < 1 then
            return 0
        end
        return (cross >= 0) and 1 or -1
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
        local best_runway_angle = nil
        local neighbors = data.adjacency_any[node_id] or {}
        for _, edge in ipairs(neighbors) do
            local to_id = edge.to
            if to_id and data.nodes[to_id] and data.runway_nodes and data.runway_nodes[to_id] then
                local n2 = data.nodes[to_id]
                if n2.east and n2.north then
                    local vx = n2.east - node.east
                    local vy = n2.north - node.north
                    local vlen = math.sqrt(vx * vx + vy * vy)
                    if vlen > 0.1 then
                        local dot = (axis.x * vx + axis.y * vy) / vlen
                        if dot > 1 then dot = 1 elseif dot < -1 then dot = -1 end
                        local angle = math.deg(math.acos(dot))
                        if not best_runway_angle or angle < best_runway_angle then
                            best_runway_angle = angle
                        end
                    end
                end
            end
        end
        if best_runway_angle and best_runway_angle > max_turn then
            return false
        end
        local best_angle = nil
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
    local td_along = nil
    if td and td.east and td.north and profile.threshold and profile.threshold.east and profile.threshold.north then
        local dx = td.east - profile.threshold.east
        local dy = td.north - profile.threshold.north
        td_along = dx * profile.axis.x + dy * profile.axis.y
    end
    local max_candidates = 32
    local candidates = collect_runway_exit_candidates(data, td.east, td.north, max_candidates)
    if #candidates == 0 then
        return find_nearest_runway_node(data, td.east, td.north), true
    end
    local rollout = profile.roll or 0
    local tol = 80
    local length = profile.length or 0
    local width = profile.width or 0
    local perp_limit = math.max(180, width * 4)
    local function pick(require_side)
        local best_forward = nil
        local best_forward_cost = nil
        local best_back = nil
        local best_back_along = nil
        local best_any = nil
        local best_any_along = nil
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
                if require_side and preferred_side and preferred_side ~= 0 then
                    local side = side_sign(node)
                    if side and side ~= 0 and side ~= preferred_side then
                        goto continue
                    end
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
                if (not best_any_along) or along > best_any_along then
                    best_any_along = along
                    best_any = cand.id
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
        return best_forward, best_back, best_back_along, best_any, best_any_along
    end

    if preferred_side and preferred_side ~= 0 then
        local bf, bb, bb_along, best_any, best_any_along = pick(true)
        if not bf and bb and max_candidates and #candidates >= max_candidates then
            candidates = collect_runway_exit_candidates(data, td.east, td.north, nil)
            bf, bb, bb_along, best_any, best_any_along = pick(true)
        end
        if bf then
            return bf, false
        end
        if (not bf) and bb and airborne and best_any then
            return best_any, false
        end
        if bb then
            local backtrack = true
            if td_along ~= nil and bb_along ~= nil and bb_along >= (td_along - tol) then
                backtrack = false
            end
            return bb, backtrack
        end
    end

    local bf, bb, bb_along, best_any, best_any_along = pick(false)
    if not bf and bb and max_candidates and #candidates >= max_candidates then
        candidates = collect_runway_exit_candidates(data, td.east, td.north, nil)
        bf, bb, bb_along, best_any, best_any_along = pick(false)
    end
    if bf then
        return bf, false
    end
    if (not bf) and bb and airborne and best_any then
        return best_any, false
    end
    if bb then
        local backtrack = true
        if td_along ~= nil and bb_along ~= nil and bb_along >= (td_along - tol) then
            backtrack = false
        end
        return bb, backtrack
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
    if #full_path >= 3 then
        local cleaned = {}
        local i = 1
        while i <= #full_path do
            local node_id = full_path[i]
            local prev_id = cleaned[#cleaned]
            local next_id = full_path[i + 1]
            if prev_id and next_id and prev_id == next_id
                and type(node_id) == "string"
                and string.sub(node_id, 1, 10) == "__taxi_wp_" then
                i = i + 2
            else
                if node_id ~= prev_id then
                    cleaned[#cleaned + 1] = node_id
                end
                i = i + 1
            end
        end
        full_path = cleaned
    end
    return {
        data = data,
        start_id = full_path[1],
        end_id = full_path[#full_path],
        path = full_path,
        bounds = bounds
    }
end

local function build_freehand_route(waypoints, data)
    if not waypoints or #waypoints == 0 then
        return nil, "no-waypoints"
    end
    local nodes = {}
    local path = {}
    local minX, maxX, minY, maxY = nil, nil, nil, nil
    for i = 1, #waypoints do
        local wp = waypoints[i]
        local lat, lon = ensure_waypoint_latlon(wp)
        if is_valid_latlon(lat, lon) then
            local east = wp.east
            local north = wp.north
            if east == nil or north == nil then
                east, north = latlon_to_local(lat, lon)
            end
            if east ~= nil and north ~= nil then
                nodes[i] = {
                    id = i,
                    lat = lat,
                    lon = lon,
                    east = east,
                    north = north
                }
                path[#path + 1] = i
                minX = (minX == nil or east < minX) and east or minX
                maxX = (maxX == nil or east > maxX) and east or maxX
                minY = (minY == nil or north < minY) and north or minY
                maxY = (maxY == nil or north > maxY) and north or maxY
            end
        end
    end
    if #path == 0 then
        return nil, "no-waypoints"
    end
    local adjacency = {}
    local adjacency_any = {}
    for i = 1, #path - 1 do
        local a = path[i]
        local b = path[i + 1]
        adjacency[a] = adjacency[a] or {}
        adjacency_any[a] = adjacency_any[a] or {}
        table.insert(adjacency[a], { to = b, label = "" })
        table.insert(adjacency_any[a], { to = b, label = "" })
        -- bidirectional for label lookup/segment traversal
        adjacency[b] = adjacency[b] or {}
        adjacency_any[b] = adjacency_any[b] or {}
        table.insert(adjacency[b], { to = a, label = "" })
        table.insert(adjacency_any[b], { to = a, label = "" })
    end
    local bounds = nil
    if minX ~= nil and maxX ~= nil and minY ~= nil and maxY ~= nil then
        bounds = { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
    end
    local route_data = {
        nodes = nodes,
        adjacency = adjacency,
        adjacency_any = adjacency_any,
        bounds = (data and data.bounds) or bounds,
        runways = data and data.runways or nil,
        ramps = data and data.ramps or nil,
        can_route = true,
        route_source = "freehand"
    }
    return {
        data = route_data,
        path = path,
        start_id = path[1],
        end_id = path[#path],
        bounds = route_data.bounds
    }, nil
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

local function heading_diff_signed(target, current)
    if target == nil or current == nil then
        return 0
    end
    local diff = (target - current + 540) % 360 - 180
    return diff
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
        local has_segment = false
        for idx, existing in ipairs(route_waypoints) do
            if existing.segment_idx ~= nil then
                has_segment = true
                if existing.segment_idx > wp.segment_idx then
                    insert_at = idx
                    break
                end
            end
        end
        if not has_segment then
            local fallback_idx = wp.segment_idx + 1
            if fallback_idx < 1 then
                fallback_idx = 1
            elseif fallback_idx > (#route_waypoints + 1) then
                fallback_idx = #route_waypoints + 1
            end
            insert_at = fallback_idx
        end
    end
    table.insert(route_waypoints, insert_at, wp)
    return insert_at
end

local function log_draw_endpoints(comp, tag)
    if not comp or not comp._routeWaypoints or #comp._routeWaypoints == 0 then
        return
    end
    local first = comp._routeWaypoints[1]
    local last = comp._routeWaypoints[#comp._routeWaypoints]
    log_taxi(
        string.format(
            "TaxiDraw: endpoints %s first=%s/%s last=%s/%s count=%d",
            tag or "",
            tostring(first and first.lat),
            tostring(first and first.lon),
            tostring(last and last.lat),
            tostring(last and last.lon),
            #comp._routeWaypoints
        )
    )
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
    local merge_d2 = C.editHandleMergeMeters * C.editHandleMergeMeters

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
                        if heading_diff_deg(h1, h2) >= C.editDecisionAngle then
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

local function find_ramp_by_key(data, key, filter_fn)
    if not data or not data.ramps or not key or key == "" then
        return nil
    end
    for _, ramp in ipairs(data.ramps) do
        if (not filter_fn or filter_fn(ramp)) and ramp_key(ramp) == key then
            return ramp
        end
    end
    return nil
end

local function ramp_debug_suffix(ramp)
    if not ramp then
        return ""
    end
    local parts = {}
    if ramp.node_id then
        parts[#parts + 1] = "display=" .. tostring(ramp.node_id)
    end
    if ramp.route_anchor_node_id and ramp.route_anchor_node_id ~= ramp.node_id then
        parts[#parts + 1] = "anchor=" .. tostring(ramp.route_anchor_node_id)
    end
    if ramp.link_mode and ramp.link_mode ~= "" then
        parts[#parts + 1] = "mode=" .. tostring(ramp.link_mode)
    end
    if ramp.link_node_id then
        parts[#parts + 1] = "to=" .. tostring(ramp.link_node_id)
    end
    if ramp.link_edge_label and ramp.link_edge_label ~= "" then
        parts[#parts + 1] = "label=" .. tostring(normalize_taxiway_label(ramp.link_edge_label))
    end
    if ramp.link_distance_m then
        parts[#parts + 1] = string.format("dist=%.1f", tonumber(ramp.link_distance_m) or -1)
    end
    if ramp.link_along ~= nil then
        parts[#parts + 1] = string.format("along=%.1f", tonumber(ramp.link_along) or -1)
    end
    if ramp.link_cross ~= nil then
        parts[#parts + 1] = string.format("cross=%.1f", tonumber(ramp.link_cross) or -1)
    end
    if #parts == 0 then
        return ""
    end
    return " link[" .. table.concat(parts, " ") .. "]"
end

local function ramp_route_node_id(ramp)
    if not ramp then
        return nil
    end
    return ramp.route_anchor_node_id or ramp.link_node_id or ramp.node_id
end

local function ramp_route_node(data, ramp)
    local node_id = ramp_route_node_id(ramp)
    if not (data and data.nodes and node_id) then
        return nil
    end
    return data.nodes[node_id]
end

local function departure_start_ramp_validity(data, ramp, aircraft, max_dist)
    if not ramp or not data or not aircraft or aircraft.east == nil or aircraft.north == nil then
        return false, "invalid", nil
    end
    local anchor = ramp_route_node(data, ramp)
    if not anchor or anchor.east == nil or anchor.north == nil then
        return false, "no-anchor", nil
    end
    local anchor_dist = math.sqrt(distance_sq(aircraft.east, aircraft.north, anchor.east, anchor.north))
    local dist_base = tonumber(max_dist or 80) or 80
    local anchor_limit = math.max(dist_base * 2.0, 140)
    if anchor_dist > anchor_limit then
        return false, "anchor-too-far", anchor_dist
    end
    local link_dist = tonumber(ramp.link_distance_m or 0) or 0
    local cross = math.abs(tonumber(ramp.link_cross or 0) or 0)
    local link_limit = math.max(dist_base * 2.0, 160)
    local cross_limit = math.max(dist_base * 1.5, 120)
    if link_dist > link_limit and cross > cross_limit then
        return false, "link-geometry", anchor_dist
    end
    return true, nil, anchor_dist
end

local function log_rejected_start_ramp(comp, source, ramp, ramp_dist, anchor_dist, reason)
    if not ramp then
        return
    end
    local reject_key = tostring(source or "")
        .. "|" .. tostring(ramp_key(ramp))
        .. "|" .. tostring(reason or "")
    if comp and comp._startRampRejectKey == reject_key then
        return
    end
    log_taxi(
        string.format(
            "TaxiRoute: reject start ramp %s key=%s label=%s node=%s dist=%.1f anchor=%.1f reason=%s%s",
            tostring(source or ""),
            tostring(ramp_key(ramp)),
            tostring(short_ramp_label(ramp)),
            tostring(ramp_route_node_id(ramp) or ""),
            tonumber(ramp_dist) or -1,
            tonumber(anchor_dist) or -1,
            tostring(reason or ""),
            ramp_debug_suffix(ramp)
        )
    )
    if comp then
        comp._startRampRejectKey = reject_key
    end
end

local function choose_departure_start_ramp(comp, data, icao, aircraft, heading_deg)
    if not data or not aircraft or not is_valid_latlon(aircraft.lat, aircraft.lon) then
        comp._startRampKey = nil
        comp._startRampChoiceSource = nil
        return nil, false
    end
    local filter_fn = helpers.isRampSuitableFor738
    local max_dist = (C and C.startRampMaxMeters) or 80
    local hold_dist = math.max(max_dist * 1.5, max_dist + 20)
    local start_ramp = nil
    local start_ramp_dist = nil
    local source = nil
    local latched = find_ramp_by_key(data, comp._startRampKey, filter_fn)
    if latched and latched.lat and latched.lon then
        local latched_dist = distance_meters_latlon(latched.lat, latched.lon, aircraft.lat, aircraft.lon)
        if latched_dist and latched_dist <= hold_dist then
            local ok, reason, anchor_dist = departure_start_ramp_validity(data, latched, aircraft, max_dist)
            if ok then
                start_ramp = latched
                start_ramp_dist = latched_dist
                source = "latched"
            else
                log_rejected_start_ramp(comp, "latched", latched, latched_dist, anchor_dist, reason)
            end
        end
    end
    if not start_ramp and U and U.select_best_ramp_for_aircraft then
        start_ramp, start_ramp_dist = U.select_best_ramp_for_aircraft(
            data,
            aircraft,
            {
                filter = filter_fn,
                heading_deg = heading_deg,
                radius_m = math.max(max_dist, (C and C.gateSelectRadius) or max_dist)
            }
        )
        if start_ramp and start_ramp_dist and start_ramp_dist > max_dist then
            start_ramp = nil
            start_ramp_dist = nil
        end
        if start_ramp then
            local ok, reason, anchor_dist = departure_start_ramp_validity(data, start_ramp, aircraft, max_dist)
            if ok then
                source = "best"
            else
                log_rejected_start_ramp(comp, "best", start_ramp, start_ramp_dist, anchor_dist, reason)
                start_ramp = nil
                start_ramp_dist = nil
            end
        end
    end
    if not start_ramp then
        local nearest, nearest_d2 = helpers.getNearestRamp(
            icao,
            aircraft.lat,
            aircraft.lon,
            { filter = filter_fn, data = data }
        )
        if nearest then
            local nearest_dist = nearest_d2 and math.sqrt(nearest_d2)
                or (nearest.lat and nearest.lon and distance_meters_latlon(nearest.lat, nearest.lon, aircraft.lat, aircraft.lon))
                or nil
            if nearest_dist and nearest_dist <= max_dist then
                local ok, reason, anchor_dist = departure_start_ramp_validity(data, nearest, aircraft, max_dist)
                if ok then
                    start_ramp = nearest
                    start_ramp_dist = nearest_dist
                    source = "nearest"
                else
                    log_rejected_start_ramp(comp, "nearest", nearest, nearest_dist, anchor_dist, reason)
                end
            end
        end
    end
    local key = start_ramp and ramp_key(start_ramp) or nil
    if start_ramp then
        comp._startRampRejectKey = nil
        comp._startRampKey = key
        if comp._startRampChoiceKey ~= key or comp._startRampChoiceSource ~= source then
            log_taxi(
                string.format(
                    "TaxiRoute: start ramp %s key=%s label=%s node=%s dist=%.1f%s",
                    tostring(source),
                    tostring(key),
                    tostring(short_ramp_label(start_ramp)),
                    tostring(ramp_route_node_id(start_ramp) or ""),
                    tonumber(start_ramp_dist) or -1,
                    ramp_debug_suffix(start_ramp)
                )
            )
        end
        comp._startRampChoiceKey = key
        comp._startRampChoiceSource = source
    else
        if comp._startRampChoiceKey or comp._startRampChoiceSource then
            log_taxi("TaxiRoute: start ramp released")
        end
        comp._startRampRejectKey = nil
        comp._startRampKey = nil
        comp._startRampChoiceKey = nil
        comp._startRampChoiceSource = nil
    end
    return start_ramp, source == "latched"
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
    if data._tempEdgeLabels then
        local key = tostring(from_id) .. ":" .. tostring(to_id)
        local label = data._tempEdgeLabels[key]
        if label ~= nil then
            return label
        end
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

local function infer_arrival_exit_from_route(route, data)
    if not route or not route.path or not data then
        return nil
    end
    local path = route.path
    if #path == 0 then
        return nil
    end
    local function next_non_temp(start_idx)
        if not data.nodes then
            return nil
        end
        for idx = start_idx, #path do
            local node_id = path[idx]
            local node = data.nodes[node_id]
            if not (node and node.is_temp) then
                return node_id
            end
        end
        return nil
    end
    local saw_runway = false
    for i = 1, (#path - 1) do
        local label = get_edge_label(data, path[i], path[i + 1])
        local is_rwy = label and is_runway_label(label)
        if is_rwy then
            saw_runway = true
            if i + 1 <= (#path - 1) then
                local next_label = get_edge_label(data, path[i + 1], path[i + 2])
                local next_is_rwy = next_label and is_runway_label(next_label)
                if not next_is_rwy then
                    local cand = next_non_temp(i + 1)
                    return cand or path[i + 1]
                end
            else
                local cand = next_non_temp(i + 1)
                return cand or path[i + 1]
            end
        elseif saw_runway then
            local cand = next_non_temp(i)
            return cand or path[i]
        end
    end
    if not saw_runway then
        local cand = next_non_temp(1)
        return cand or path[1]
    end
    return nil
end

local function route_first_taxi_angle(route, data, profile)
    if not route or not data or not profile or not profile.axis then
        return nil
    end
    local path = route.path
    if not path or #path < 2 then
        return nil
    end
    local axis_heading = math.deg(math.atan2(profile.axis.x, profile.axis.y))
    if axis_heading < 0 then
        axis_heading = axis_heading + 360
    end
    local saw_runway = false
    for i = 1, (#path - 1) do
        local label = get_edge_label(data, path[i], path[i + 1])
        local is_rwy = label and is_runway_label(label)
        if is_rwy then
            saw_runway = true
        else
            if saw_runway or i == 1 then
                local n1 = data.nodes and data.nodes[path[i]] or nil
                local n2 = data.nodes and data.nodes[path[i + 1]] or nil
                if n1 and n2 and n1.east and n1.north and n2.east and n2.north then
                    local seg_heading = heading_deg_from_to(n1.east, n1.north, n2.east, n2.north)
                    if seg_heading then
                        return heading_diff_deg(axis_heading, seg_heading)
                    end
                end
            end
        end
    end
    return nil
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

local function next_numeric_node_id(nodes)
    local max_id = 0
    if not nodes then
        return 1
    end
    for id, _ in pairs(nodes) do
        if type(id) == "number" and id > max_id then
            max_id = id
        end
    end
    return max_id + 1
end

local function resolve_dep_runway_latlon(comp)
    local yal = comp and (comp.yal or _G.yal) or nil
    if not yal then
        return nil, nil
    end
    local lat = yal.deprwylatstartpos and get(yal.deprwylatstartpos) or nil
    local lon = yal.deprwylonstartpos and get(yal.deprwylonstartpos) or nil
    if not is_valid_latlon(lat, lon) then
        lat = yal.deprwylatendpos and get(yal.deprwylatendpos) or nil
        lon = yal.deprwylonendpos and get(yal.deprwylonendpos) or nil
    end
    if not is_valid_latlon(lat, lon) then
        return nil, nil
    end
    return lat, lon
end

local function ensure_manual_dep_runway_anchor(comp)
    if not comp or comp.mode ~= 0 then
        return false
    end
    local route = comp._route
    if not route or not route.path or #route.path < 2 or not route.data then
        return false
    end
    if route.data.route_source ~= "freehand" then
        return false
    end
    local route_data = route.data
    if not route_data.nodes then
        return false
    end
    local runway_name = comp._runwayName or ""
    if runway_name == "" then
        local yal = comp.yal or _G.yal
        if yal and yal.deprwy then
            runway_name = helpers.forceCleanString(get(yal.deprwy) or "")
        end
    end
    if runway_name == "" then
        return false
    end
    local runway_lat, runway_lon = resolve_dep_runway_latlon(comp)
    local profile = compute_runway_landing_profile(comp._data or route_data, runway_name, runway_lat, runway_lon)
    if not profile or not profile.threshold or not profile.axis then
        return false
    end

    local last_id = route.path[#route.path]
    local prev_id = route.path[#route.path - 1]
    local last_node = route_data.nodes[last_id]
    local prev_node = route_data.nodes[prev_id]
    if not last_node or not prev_node then
        return false
    end
    if last_node.east == nil or last_node.north == nil or prev_node.east == nil or prev_node.north == nil then
        return false
    end

    local along, perp = compute_along_perp(profile, last_node)
    if along == nil or perp == nil then
        return false
    end
    local corridor = runway_corridor_half_width(profile)
    if perp > (corridor + 35) then
        return false
    end
    local dist_to_threshold = math.sqrt(distance_sq(
        last_node.east,
        last_node.north,
        profile.threshold.east,
        profile.threshold.north
    ))
    local max_dist = math.max(120, (C.depThresholdGateMeters or 45) * 3)
    if dist_to_threshold > max_dist then
        return false
    end
    if along >= 20 then
        return false
    end

    local axis_heading = heading_deg_from_to(
        profile.threshold.east,
        profile.threshold.north,
        profile.threshold.east + profile.axis.x * 10,
        profile.threshold.north + profile.axis.y * 10
    )
    local inbound_heading = heading_deg_from_to(prev_node.east, prev_node.north, last_node.east, last_node.north)
    if axis_heading and inbound_heading and along >= 5 then
        local diff = heading_diff_deg(axis_heading, inbound_heading)
        if diff <= 12 then
            return false
        end
    end

    local lineup_dist = math.max(15, math.min((C.depThresholdGateMeters or 45) * 0.8, 30))
    local target_east = profile.threshold.east + profile.axis.x * lineup_dist
    local target_north = profile.threshold.north + profile.axis.y * lineup_dist
    local tail_dist = math.sqrt(distance_sq(last_node.east, last_node.north, target_east, target_north))
    if tail_dist < 6 or tail_dist > 160 then
        return false
    end

    local target_lat, target_lon = local_to_latlon(target_east, target_north)
    local node_id = next_numeric_node_id(route_data.nodes)
    route_data.nodes[node_id] = {
        id = node_id,
        east = target_east,
        north = target_north,
        lat = target_lat,
        lon = target_lon,
        is_temp = true
    }
    route_data.adjacency = route_data.adjacency or {}
    route_data.adjacency_any = route_data.adjacency_any or {}
    route_data.adjacency[last_id] = route_data.adjacency[last_id] or {}
    route_data.adjacency_any[last_id] = route_data.adjacency_any[last_id] or {}
    route_data.adjacency[node_id] = route_data.adjacency[node_id] or {}
    route_data.adjacency_any[node_id] = route_data.adjacency_any[node_id] or {}
    local label = normalize_runway_name(runway_name)
    table.insert(route_data.adjacency[last_id], { to = node_id, label = label })
    table.insert(route_data.adjacency_any[last_id], { to = node_id, label = label })
    table.insert(route_data.adjacency[node_id], { to = last_id, label = label })
    table.insert(route_data.adjacency_any[node_id], { to = last_id, label = label })
    route_data.runway_nodes = route_data.runway_nodes or {}
    route_data.runway_nodes[node_id] = true
    route.path[#route.path + 1] = node_id
    route.end_id = node_id
    if route.bounds then
        update_bounds(route.bounds, target_east, target_north)
    end
    if comp._routeWaypoints and #comp._routeWaypoints > 0 and is_valid_latlon(target_lat, target_lon) then
        local last_wp = comp._routeWaypoints[#comp._routeWaypoints]
        local wp_lat, wp_lon = ensure_waypoint_latlon(last_wp)
        local append_wp = true
        if is_valid_latlon(wp_lat, wp_lon) then
            local d_wp = distance_meters_latlon(wp_lat, wp_lon, target_lat, target_lon)
            if d_wp and d_wp < 6 then
                append_wp = false
            end
        end
        if append_wp then
            comp._routeWaypoints[#comp._routeWaypoints + 1] = {
                lat = target_lat,
                lon = target_lon,
                east = target_east,
                north = target_north
            }
        end
    end
    comp._routeLabels = build_route_labels(route_data, route.path)
    comp._routeLabelStats = compute_route_label_stats(route_data, route.path)
    log_taxi(
        string.format(
            "TaxiEdit: manual dep anchor appended runway=%s dist=%.1f along=%.1f perp=%.1f",
            tostring(runway_name),
            tail_dist or -1,
            along or -1,
            perp or -1
        )
    )
    return true
end

local function arrival_grace_active(comp, now)
    if not comp or not now then
        return false
    end
    local t0 = comp._arrOnGroundSince
    return t0 ~= nil and (now - t0) < C.qualityArrGraceSec
end

local function manual_end_ramp_retarget_hold_active(comp, now)
    if not comp or comp.mode ~= 1 or not comp._selectedEndRampKey then
        return false
    end
    local hold_until = comp._manualEndRampRetargetUntil
    if not hold_until or not now then
        return false
    end
    if now > hold_until then
        comp._manualEndRampRetargetUntil = nil
        return false
    end
    return true
end

local function after_landing_started(comp)
    local yal = comp and (comp.yal or _G.yal) or nil
    if not yal then
        return false
    end
    local proc = yal.proceduretable and yal.proceduretable[def.AFTERLANDINGPROCEDURE]
    if proc and proc.set then
        return true
    end
    if yal.loopStateTables then
        for _, loop in ipairs(yal.loopStateTables) do
            if loop and loop.lock == def.AFTERLANDINGPROCEDURE then
                return true
            end
        end
    else
        local l1 = yal.procedureloop1
        local l2 = yal.procedureloop2
        local l3 = yal.procedureloop3
        if (l1 and l1.lock == def.AFTERLANDINGPROCEDURE)
            or (l2 and l2.lock == def.AFTERLANDINGPROCEDURE)
            or (l3 and l3.lock == def.AFTERLANDINGPROCEDURE) then
            return true
        end
    end
    return false
end

local function runway_exit_along(profile, data, exit_id)
    if not profile or not data or not data.nodes or not exit_id then
        return nil
    end
    local node = data.nodes[exit_id]
    if not node then
        return nil
    end
    local along = U.compute_along_perp(profile, node)
    return along
end

local function node_distance_to_aircraft(data, node_id, aircraft)
    if not data or not data.nodes or not node_id or not aircraft then
        return nil
    end
    if aircraft.east == nil or aircraft.north == nil then
        return nil
    end
    local node = data.nodes[node_id]
    if not node or node.east == nil or node.north == nil then
        return nil
    end
    return math.sqrt(distance_sq(node.east, node.north, aircraft.east, aircraft.north))
end

local function evaluate_arrival_route_validity(route, data, aircraft, landing_profile, arr_exit_id, drift_meters, off_runway)
    local info = {
        valid = true,
        severe = false,
        reason = "ok",
        route_dist = nil,
        start_gap = nil,
        exit_gap = nil,
        future_exit_gap = nil
    }
    if not route or not data or not aircraft or aircraft.east == nil or aircraft.north == nil then
        return info
    end
    local route_data = route.data or data
    if route.path and #route.path > 1 then
        info.route_dist = distance_to_route(route_data, route.path, aircraft.east, aircraft.north)
    end
    local start_id = route.start_id or (route.path and route.path[1]) or nil
    info.start_gap = node_distance_to_aircraft(route_data, start_id, aircraft)
    info.exit_gap = node_distance_to_aircraft(route_data, arr_exit_id, aircraft)
    local on_runway = (off_runway == false)
    local route_limit = on_runway and math.max(220, drift_meters * 4) or math.max(180, drift_meters * 3)
    local severe_limit = on_runway and math.max(320, drift_meters * 6) or math.max(260, drift_meters * 4.5)
    local node_limit = on_runway and math.max(120, drift_meters * 2.5) or math.max(90, drift_meters * 2)
    if on_runway and landing_profile and arr_exit_id then
        local aircraft_along = U.compute_along_perp(landing_profile, aircraft)
        local exit_along = runway_exit_along(landing_profile, route_data, arr_exit_id)
        if aircraft_along and exit_along then
            local forward_gap = exit_along - aircraft_along
            if forward_gap > 25 then
                info.future_exit_gap = forward_gap
                local route_slack = math.max(90, drift_meters * 1.8)
                local node_slack = math.max(60, drift_meters * 1.2)
                route_limit = math.max(route_limit, forward_gap + route_slack)
                severe_limit = math.max(severe_limit, forward_gap + route_slack + math.max(120, drift_meters * 2.5))
                node_limit = math.max(node_limit, forward_gap + node_slack)
            end
        end
    end
    local start_bad = info.start_gap and info.start_gap > node_limit
    local exit_bad = info.exit_gap and info.exit_gap > node_limit
    if info.route_dist and info.route_dist > route_limit then
        if start_bad or exit_bad then
            info.valid = false
            info.reason = (start_bad and exit_bad) and "route-detached" or (start_bad and "start-detached" or "exit-detached")
            info.severe = info.route_dist > severe_limit
        end
    elseif start_bad and info.route_dist and info.route_dist > math.max(120, drift_meters * 2.2) then
        info.valid = false
        info.reason = "start-detached"
    end
    return info
end

local function choose_or_keep_arrival_exit(comp, landing_profile, data, proposed_exit_id, proposed_backtrack, aircraft, off_runway, start_lat, start_lon, log_taxi)
    local exit_id = proposed_exit_id
    local backtrack_required = proposed_backtrack and true or false
    local exit_along = nil
    if landing_profile and exit_id then
        exit_along = runway_exit_along(landing_profile, data, exit_id)
    end

    local function apply_exit_start(node_id)
        if backtrack_required or not node_id or not data or not data.nodes or not data.nodes[node_id] then
            return start_lat, start_lon
        end
        local node = data.nodes[node_id]
        if U.is_valid_latlon(node.lat, node.lon) then
            return node.lat, node.lon
        end
        return start_lat, start_lon
    end

    if off_runway == false and comp._arrExitLockedId and exit_id and exit_id ~= comp._arrExitLockedId then
        local locked_exit = comp._arrExitLockedId
        local locked_along = comp._arrExitLockedAlong
        exit_id = locked_exit
        if locked_along ~= nil then
            exit_along = locked_along
        elseif landing_profile and data and locked_exit then
            exit_along = runway_exit_along(landing_profile, data, locked_exit)
        end
        backtrack_required = comp._arrBacktrackRequired and true or false
        start_lat, start_lon = apply_exit_start(locked_exit)
        log_taxi("TaxiRoute: ARR exit lock keep=" .. tostring(locked_exit))
        return exit_id, exit_along, backtrack_required, start_lat, start_lon
    end

    if off_runway == false and comp._arrExitId and exit_id
        and exit_id ~= comp._arrExitId
        and comp._arrExitAlong ~= nil and exit_along ~= nil
        and (not backtrack_required) and (not comp._arrBacktrackRequired)
        and exit_along < comp._arrExitAlong then
        local aircraft_along = nil
        if landing_profile and aircraft then
            aircraft_along = U.compute_along_perp(landing_profile, aircraft)
        end
        local prev_exit = comp._arrExitId
        local prev_along = comp._arrExitAlong
        local prev_gap = node_distance_to_aircraft(data, prev_exit, aircraft)
        local new_gap = node_distance_to_aircraft(data, exit_id, aircraft)
        local keep_prev = true
        if aircraft_along and aircraft_along >= (prev_along - 40) then
            keep_prev = false
        elseif prev_gap and new_gap and (new_gap + 30) < prev_gap then
            keep_prev = false
        end
        if keep_prev then
            local new_along = exit_along
            exit_id = prev_exit
            exit_along = prev_along
            backtrack_required = comp._arrBacktrackRequired and true or false
            start_lat, start_lon = apply_exit_start(prev_exit)
            log_taxi(
                string.format(
                    "TaxiRoute: ARR exit ownership keep=%s oldAlong=%.1f newAlong=%.1f oldGap=%.1f newGap=%.1f",
                    tostring(prev_exit),
                    prev_along or -1,
                    new_along or -1,
                    prev_gap or -1,
                    new_gap or -1
                )
            )
            return exit_id, exit_along, backtrack_required, start_lat, start_lon
        end
    end

    start_lat, start_lon = apply_exit_start(exit_id)
    return exit_id, exit_along, backtrack_required, start_lat, start_lon
end

local function set_reroute_override_from_aircraft(comp, data, aircraft, disallow_runway_edges)
    if not comp or not aircraft or not is_valid_latlon(aircraft.lat, aircraft.lon) then
        return false
    end
    comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
    if data and aircraft.east ~= nil and aircraft.north ~= nil then
        local proj = U.find_nearest_edge_projection(
            data,
            aircraft.east,
            aircraft.north,
            { disallow_runway_edges = disallow_runway_edges and true or false }
        )
        if proj and proj.proj_east and proj.proj_north then
            local plat, plon = local_to_latlon(proj.proj_east, proj.proj_north)
            if is_valid_latlon(plat, plon) then
                comp._rerouteOverride = { lat = plat, lon = plon }
            end
        end
    end
    return true
end

local function force_arrival_recompute(comp, data, aircraft, now, reason, log_taxi)
    if not comp then
        return
    end
    set_reroute_override_from_aircraft(comp, data, aircraft, false)
    comp._routeStartAnchor = nil
    comp._lastStartKey = nil
    comp._route = nil
    comp._routeErr = nil
    comp._routeLabels = nil
    comp._routeLabelStats = nil
    comp._routeExtraSegments = nil
    comp._autoTaxiPath = nil
    comp._autoTaxiPathRoute = nil
    comp._pendingRerouteEvent = true
    comp._lastRerouteTime = now
    if log_taxi then
        log_taxi("TaxiRoute: reroute reason=" .. tostring(reason))
    end
end

local function record_reroute_event(comp, now)
    if not comp then
        return
    end
    comp._quality = comp._quality or {}
    local events = comp._quality.rerouteEvents or {}
    events[#events + 1] = now
    local cutoff = now - C.qualityRerouteWindowSec
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
    if dist and dist > C.qualityDistanceMeters then
        if not quality.distBadSince then
            quality.distBadSince = now
        end
        if (now - quality.distBadSince) >= C.qualityDistanceSeconds then
            reasons[#reasons + 1] = "dist"
        end
    else
        quality.distBadSince = nil
    end
    local events = quality.rerouteEvents or {}
    if #events >= C.qualityRerouteLimit then
        reasons[#reasons + 1] = "reroute"
    end
    local stats = comp._routeLabelStats
    if stats and (stats.taxi_edges or 0) >= C.qualityMinLabelEdges then
        if (stats.bad_ratio or 0) >= C.qualityBadLabelRatio then
            reasons[#reasons + 1] = "labels"
        elseif (stats.none_ratio or 0) >= C.qualityNoneLabelRatio then
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

local function reset_guidance_tracking(comp, reset_state)
    if not comp then
        return
    end
    comp._lastGuidanceNodeId = nil
    comp._lastGuidanceLabel = nil
    comp._lastGuidanceTime = nil
    comp._lastGuidanceSegment = nil
    comp._lastGuidanceAction = nil
    comp._lastGuidanceVoiceText = nil
    comp._lastGuidanceVoiceTime = nil
    comp._terminalGuidanceKey = nil
    comp._terminalGuidanceTime = nil
    comp._guidanceMoveAnchor = nil
    comp._guidanceLastPos = nil
    comp._guidanceActiveSegIdx = nil
    comp._guidanceMonotonicSegIdx = nil
    comp._guidanceTurnLockLabel = nil
    comp._guidanceTurnLockUntilSeg = nil
    comp._guidanceInstruction = nil
    comp._guidanceInstructionIssuedSeg = nil
    comp._guidanceInstructionCommitSeg = nil
    comp._guidanceInstructionCommitLabel = nil
    if reset_state then
        comp._guidanceState = "idle"
    end
end

local function clear_pushback_join_hold(comp)
    if not comp then
        return
    end
    comp._pushbackJoinHoldUntil = nil
    comp._pushbackJoinHoldSeg = nil
end

local function arm_pushback_join_hold(comp, now, seg_idx)
    if not comp or not now then
        return
    end
    local cooldown = (C and C.rerouteCooldown) or 6
    comp._pushbackJoinHoldUntil = now + math.max(cooldown * 2, 12)
    comp._pushbackJoinHoldSeg = (tonumber(seg_idx or 0) or 0) + 2
end

local function dep_terminal_sequence_locked(comp)
    if not comp or comp.mode ~= 0 then
        return false
    end
    return comp._depTerminalSequenceLock == true
        or comp._depThresholdLatched == true
        or comp._depThresholdReached == true
        or comp._depRunwayEntryLock == true
end

local function pushback_join_hold_active(comp, now, dist, driftMeters, seg_idx)
    if not comp or not comp._pushbackJoinHoldUntil then
        return false
    end
    if not now or comp._pushbackJoinHoldUntil <= now then
        clear_pushback_join_hold(comp)
        return false
    end
    local hold_seg = tonumber(comp._pushbackJoinHoldSeg or 0) or 0
    local current_seg = tonumber(seg_idx or 0) or 0
    if hold_seg > 0 and current_seg > hold_seg then
        clear_pushback_join_hold(comp)
        return false
    end
    if dist and driftMeters and dist > (driftMeters * 2) then
        return false
    end
    return true
end

local function dep_source_lock_active(comp, icao)
    if not comp or not icao or icao == "" then
        return false
    end
    return comp._depSourceLock == true and comp._depSourceLockIcao == icao
end

local function normalize_source_tag(source)
    local src = tostring(source or "")
    if src == "global-index" or src == "global" then
        return "global"
    end
    if src == "addon" then
        return "addon"
    end
    if src == "" then
        return "unknown"
    end
    return src
end

local function mark_source_switch_pending(comp, icao, mode, reason)
    if not comp or not icao or icao == "" then
        return
    end
    comp._sourceSwitchPending = {
        icao = icao,
        mode = mode,
        reason = reason or "auto"
    }
end

local function set_dep_source_lock(comp, icao, data, log_taxi)
    if not comp or not icao or icao == "" then
        return false
    end
    local src = data and data.entry and data.entry.source or nil
    if src ~= "addon" then
        return false
    end
    if dep_source_lock_active(comp, icao) then
        return true
    end
    comp._depSourceLock = true
    comp._depSourceLockIcao = icao
    if log_taxi then
        log_taxi("TaxiSource: lock addon icao=" .. tostring(icao))
    end
    return true
end

local function clear_dep_source_lock(comp, reason, log_taxi)
    if not comp or not comp._depSourceLock then
        return
    end
    if log_taxi then
        log_taxi("TaxiSource: unlock addon reason=" .. tostring(reason or ""))
    end
    comp._depSourceLock = false
    comp._depSourceLockIcao = nil
end

local function get_taxi_source_mode(comp, icao)
    if not comp or not icao or icao == "" then
        return "auto"
    end
    if comp._taxiSourceManualByIcao and comp._taxiSourceManualByIcao[icao] then
        local policy = comp._taxiSourceByIcao and comp._taxiSourceByIcao[icao] or "addon"
        if policy == "global" then
            return "global"
        end
        return "addon"
    end
    return "auto"
end

local function force_global_source(comp, icao, mode, reason, log_taxi)
    if not comp or not icao or icao == "" then
        return false
    end
    mark_source_switch_pending(comp, icao, mode, reason or "source-fallback")
    comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
    comp._taxiSourceByIcao[icao] = "global"
    comp._taxiGlobalPending = comp._taxiGlobalPending or {}
    comp._taxiGlobalPending[icao] = nil
    clear_dep_source_lock(comp, reason or "source-fallback", log_taxi)
    comp._data = nil
    comp._dataErr = nil
    comp._route = nil
    comp._routeErr = nil
    comp._routeLabels = nil
    comp._routeLabelStats = nil
    comp._routeExtraSegments = nil
    comp._autoTaxiPath = nil
    comp._autoTaxiPathRoute = nil
    comp._lastStartKey = nil
    comp._lastEndKey = nil
    comp._routeStartAnchor = nil
    comp._rerouteOverride = nil
    comp._rerouteOverrideHoldUntil = nil
    comp._pendingRerouteEvent = nil
    comp._sCurveSkipNodeId = nil
    comp._needsCenter = true
    reset_guidance_tracking(comp, true)
    clear_visual_guidance(comp, reason or "source-fallback")
    comp._visualGuidanceQueue = {}
    if U and U.set_taxi_ref then
        U.set_taxi_ref(nil)
    end
    if log_taxi then
        log_taxi(
            "TaxiSource: force global icao="
                .. tostring(icao)
                .. " mode="
                .. tostring(mode)
                .. " reason="
                .. tostring(reason or "source-fallback")
        )
    end
    return true
end

local function set_taxi_source_mode(comp, icao, mode, reason, log_taxi)
    if not comp or not icao or icao == "" then
        return false
    end
    if mode ~= "auto" and mode ~= "addon" and mode ~= "global" then
        return false
    end
    comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
    comp._taxiSourceManualByIcao = comp._taxiSourceManualByIcao or {}
    comp._taxiGlobalPending = comp._taxiGlobalPending or {}
    if mode == "auto" then
        comp._taxiSourceByIcao[icao] = nil
        comp._taxiSourceManualByIcao[icao] = nil
        comp._taxiGlobalPending[icao] = nil
    else
        comp._taxiSourceByIcao[icao] = (mode == "global") and "global" or "addon"
        comp._taxiSourceManualByIcao[icao] = true
        if mode ~= "global" then
            comp._taxiGlobalPending[icao] = nil
        elseif helpers and helpers.isGlobalAptIndexReady and (not helpers.isGlobalAptIndexReady()) then
            comp._taxiGlobalPending[icao] = true
            if helpers.requestGlobalAptIndex then
                helpers.requestGlobalAptIndex("manual-source-switch")
            end
        end
    end
    mark_source_switch_pending(comp, icao, comp.mode, reason or "manual")
    if mode ~= "auto" then
        clear_dep_source_lock(comp, "source-switch", log_taxi)
    end
    comp._data = nil
    comp._dataErr = nil
    comp._route = nil
    comp._routeErr = nil
    comp._routeLabels = nil
    comp._routeLabelStats = nil
    comp._routeExtraSegments = nil
    comp._autoTaxiPath = nil
    comp._autoTaxiPathRoute = nil
    comp._lastStartKey = nil
    comp._lastEndKey = nil
    comp._routeStartAnchor = nil
    comp._rerouteOverride = nil
    comp._rerouteOverrideHoldUntil = nil
    comp._sCurveSkipNodeId = nil
    comp._pendingRerouteEvent = nil
    comp._lastUpdate = nil
    comp._needsCenter = true
    if U and U.set_taxi_ref then
        U.set_taxi_ref(nil)
    end
    reset_guidance_tracking(comp, true)
    clear_visual_guidance(comp, "source-switch")
    comp._visualGuidanceQueue = {}
    if log_taxi then
        log_taxi(
            "TaxiSource: mode=" .. tostring(mode)
            .. " icao=" .. tostring(icao)
            .. " reason=" .. tostring(reason or "manual")
        )
    end
    return true
end

local function reroute_from_current_aircraft(comp, data, reason, disallow_runway_edges, log_taxi)
    if not comp then
        return false
    end
    local yal = comp.yal or _G.yal
    if not yal then
        return false
    end
    local lat = yal.aircraftlatpos and get(yal.aircraftlatpos) or nil
    local lon = yal.aircraftlonpos and get(yal.aircraftlonpos) or nil
    if not is_valid_latlon(lat, lon) then
        return false
    end
    local east, north = latlon_to_local(lat, lon)
    if east == nil or north == nil then
        return false
    end
    local aircraft = { lat = lat, lon = lon, east = east, north = north }
    if not set_reroute_override_from_aircraft(comp, data, aircraft, disallow_runway_edges and true or false) then
        return false
    end
    comp._routeStartAnchor = nil
    comp._lastStartKey = nil
    comp._route = nil
    comp._routeErr = nil
    comp._routeLabels = nil
    comp._routeLabelStats = nil
    comp._routeExtraSegments = nil
    comp._autoTaxiPath = nil
    comp._autoTaxiPathRoute = nil
    comp._pendingRerouteEvent = true
    comp._lastRerouteTime = comp._timer and (sasl.getElapsedSeconds(comp._timer) or 0) or comp._lastRerouteTime
    comp._rerouteOverrideHoldUntil = (comp._lastRerouteTime or 0) + ((C and C.rerouteCooldown) or 6)
    comp._sCurveSkipNodeId = nil
    reset_guidance_tracking(comp, true)
    clear_visual_guidance(comp, "reroute-aircraft")
    comp._visualGuidanceQueue = {}
    if log_taxi then
        log_taxi(
            "TaxiRoute: reroute reason=" .. tostring(reason or "manual")
            .. " start=aircraft"
        )
    end
    return true
end

local function maybe_reselect_dep_entry(comp, data, aircraft, force, log_taxi)
    if not comp or not data or not data.nodes or not aircraft then
        return false
    end
    if aircraft.east == nil or aircraft.north == nil then
        return false
    end
    local candidates = comp._depEntryCandidates
    if not candidates or #candidates == 0 then
        return false
    end
    local selected = comp._selectedDepEntryId
    local best_id = nil
    local best_d2 = nil
    local current_d2 = nil
    for _, cand in ipairs(candidates) do
        local node = data.nodes[cand.id]
        if node and node.east ~= nil and node.north ~= nil then
            local dx = node.east - aircraft.east
            local dy = node.north - aircraft.north
            local d2 = dx * dx + dy * dy
            if selected and cand.id == selected then
                current_d2 = d2
            end
            if (not best_d2) or d2 < best_d2 then
                best_d2 = d2
                best_id = cand.id
            end
        end
    end
    if not best_id then
        return false
    end
    local should_switch = false
    if force then
        should_switch = true
    elseif not selected then
        should_switch = true
    elseif selected ~= best_id then
        local min_delta = (C and C.rerouteDriftMeters) or 40
        local min_delta_sq = min_delta * min_delta
        if (not current_d2) or ((current_d2 - best_d2) > min_delta_sq) then
            should_switch = true
        end
    end
    if not should_switch then
        return false
    end
    comp._selectedDepEntryId = best_id
    comp._selectedDepEntryManual = false
    if log_taxi then
        log_taxi(
            string.format(
                "TaxiRoute: dep entry reselect id=%s force=%s d=%.1f",
                tostring(best_id),
                tostring(force == true),
                math.sqrt(best_d2 or 0)
            )
        )
    end
    return true
end

local function maybe_force_global_for_quality(comp, now, icao, mode, data, helpers, aircraft)
    if not comp or not data or not icao or not now then
        return false
    end
    if get_taxi_source_mode(comp, icao) ~= "auto" then
        return false
    end
    if mode == 0 and dep_source_lock_active(comp, icao) then
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
    if (now - comp._quality.badSince) < C.qualityBadHoldSec then
        return false
    end

    if mode == 1 and reasons and #reasons == 1 and reasons[1] == "dist"
        and aircraft and is_valid_latlon(aircraft.lat, aircraft.lon)
        and not comp._editRoute and not comp._drawRoute then
        if comp._selectedEndRampKey then
            return false
        end
        local gate_radius = (comp._tuning and comp._tuning.gateSelectRadius) or (C and C.gateSelectRadius) or 120
        local nearest_ramp = helpers.getNearestRamp(
            icao,
            aircraft.lat,
            aircraft.lon,
            { filter = helpers.isRampSuitableFor738, data = data }
        )
        if nearest_ramp and is_valid_latlon(nearest_ramp.lat, nearest_ramp.lon) then
            local d = distance_meters_latlon(nearest_ramp.lat, nearest_ramp.lon, aircraft.lat, aircraft.lon)
            if d and d <= gate_radius then
                local cand_key = ramp_key(nearest_ramp)
                local planned_key = comp._autoEndRampKey or (comp._endRamp and ramp_key(comp._endRamp)) or nil
                if cand_key and planned_key and cand_key == planned_key then
                    if comp._quality then
                        comp._quality.badSince = nil
                        comp._quality.distBadSince = nil
                        comp._quality.rerouteEvents = {}
                    end
                    if helpers and helpers.logInfoTS then
                        helpers.logInfoTS(
                            string.format(
                                "TaxiQuality: dist-only near ramp keep key=%s dist=%.1f",
                                tostring(cand_key),
                                d or -1
                            )
                        )
                    end
                    return false
                end
                if cand_key then
                    comp._autoEndRampKey = cand_key
                    comp._autoEndRampSwitchTime = now
                    comp._endRamp = nearest_ramp
                    set_reroute_override_from_aircraft(comp, data, aircraft, true)
                    comp._routeStartAnchor = nil
                    comp._route = nil
                    comp._routeErr = nil
                    comp._routeLabels = nil
                    comp._routeLabelStats = nil
                    comp._lastEndKey = nil
                    comp._lastStartKey = nil
                    comp._pendingRerouteEvent = true
                    reset_guidance_tracking(comp, true)
                    comp._sCurveSkipNodeId = nil
                    clear_visual_guidance(comp, "end-ramp-switch-quality")
                    comp._visualGuidanceQueue = {}
                    comp._gateGuidanceLastDir = nil
                    comp._gateGuidanceLastAction = nil
                    comp._gateGuidanceLastTime = nil
                    comp._gateGuidanceStop = false
                    comp._gateGuidanceActive = false
                    comp._gateFinalTurnUntil = nil
                    comp._gateFinalTurnKey = nil
                    comp._gateFinalTurnPending = false
                    U.reset_gate_callouts(comp, cand_key)
                    if comp._quality then
                        comp._quality.badSince = nil
                        comp._quality.distBadSince = nil
                        comp._quality.rerouteEvents = {}
                    end
                    if helpers and helpers.logInfoTS then
                        helpers.logInfoTS(
                            string.format(
                                "TaxiQuality: dist-only retarget end-ramp key=%s dist=%.1f",
                                tostring(cand_key),
                                d or -1
                            )
                        )
                    end
                    return false
                end
            end
        end
    end

    local log_info = build_quality_log(comp, data, icao, mode, reasons)
    if helpers and helpers.isGlobalAptIndexReady and helpers.isGlobalAptIndexReady() then
        mark_source_switch_pending(comp, icao, mode, "quality-fallback")
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
        comp._autoTaxiPath = nil
        comp._autoTaxiPathRoute = nil
        comp._lastStartKey = nil
        comp._lastEndKey = nil
        comp._startRampLabel = nil
        reset_guidance_tracking(comp, true)
        comp._sCurveSkipNodeId = nil
        comp._rerouteOverride = nil
        comp._rerouteOverrideHoldUntil = nil
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
    mark_source_switch_pending(comp, icao, mode, "quality-fallback-pending")
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

U = {
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
    normalize_runway_pair_label = normalize_runway_pair_label,
    format_runway_designator_text = format_runway_designator_text,
    parse_runway_parts = parse_runway_parts,
    find_runway_entry = find_runway_entry,
    find_nearest_runway_entry_by_latlon = find_nearest_runway_entry_by_latlon,
    compute_runway_landing_profile = compute_runway_landing_profile,
    find_runway_crossing = find_runway_crossing,
    runway_pair_label = runway_pair_label,
    runway_end_label = runway_end_label,
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
    clear_temp_route_overlay = clear_temp_route_overlay,
    set_taxi_ref = set_taxi_ref,
    align_taxi_data_projection = align_taxi_data_projection,
    compute_route_label_stats = compute_route_label_stats,
    build_edit_handles = build_edit_handles,
    heading_deg_from_to = heading_deg_from_to,
    heading_diff_deg = heading_diff_deg,
    heading_diff_signed = heading_diff_signed,
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
    is_visual_taxi_guidance_enabled = is_visual_taxi_guidance_enabled,
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
    getSettingNumber = settings.getSettingNumber,
    emit_guidance = emit_guidance,
    arrival_grace_active = arrival_grace_active,
    is_on_runway_profile = is_on_runway_profile,
    runway_label_voice = runway_label_voice,
    build_visual_label = build_visual_label
}

do
    local ok, mod = pcall(require, "windows.taxi_guidance")
    if ok and mod and mod.attach then
        mod.attach(U, C, def, helpers, settings)
    elseif helpers and helpers.logInfoTS then
        helpers.logInfoTS("TaxiGuidance: module load failed")
    end
    local function noop()
    end
    if not U.guidance_distance_for_speed then
        U.guidance_distance_for_speed = function()
            return (C and C.guidanceTurnDistance) or 90
        end
    end
    if not U.speak_guidance_text then
        U.speak_guidance_text = function(_, text)
            if helpers and helpers.speak then
                helpers.speak(text)
            end
        end
    end
    if not U.build_visual_label then
        U.build_visual_label = function(_, display)
            return display or ""
        end
    end
    if not U.is_taxi_complete_info then
        U.is_taxi_complete_info = function()
            return false
        end
    end
    if not U.set_visual_guidance then
        U.set_visual_guidance = noop
    end
    if not U.queue_visual_guidance then
        U.queue_visual_guidance = noop
    end
    if not U.clear_visual_guidance then
        U.clear_visual_guidance = noop
    end
    if not U.set_guidance_state then
        U.set_guidance_state = noop
    end
    if not U.update_visual_guidance then
        U.update_visual_guidance = noop
    end
    if not U.maybe_speak_guidance then
        U.maybe_speak_guidance = noop
    end
    if not U.emit_guidance then
        U.emit_guidance = noop
    end
    guidance_distance_for_speed = U.guidance_distance_for_speed
    speak_guidance_text = U.speak_guidance_text
    build_visual_label = U.build_visual_label
    is_taxi_complete_info = U.is_taxi_complete_info
    set_visual_guidance = U.set_visual_guidance
    queue_visual_guidance = U.queue_visual_guidance
    clear_visual_guidance = U.clear_visual_guidance
    set_guidance_state = U.set_guidance_state
    update_visual_guidance = U.update_visual_guidance
    emit_guidance = U.emit_guidance
end

do
    local ok, mod = pcall(require, "windows.taxi_gate")
    if ok and mod and mod.attach then
        mod.attach(U, C, def, helpers)
    elseif helpers and helpers.logInfoTS then
        helpers.logInfoTS("TaxiGate: module load failed")
    end
end

do
    local ok, mod = pcall(require, "windows.taxi_autotaxi")
    if ok and mod and mod.attach then
        mod.attach(U, C, def, helpers, settings)
    elseif helpers and helpers.logInfoTS then
        helpers.logInfoTS("AutoTaxi: module load failed")
    end
end

U.update_pushback_state = function(comp, now, yal, aircraft)
    if not comp or not yal or comp.mode ~= 0 then
        if comp then
            comp._pushbackStartedEver = false
            comp._pushbackActive = false
            comp._pushbackCompleted = false
            comp._pushbackPlanSeen = false
            comp._guidancePushbackReleased = nil
            comp._pushbackReleaseAnchor = nil
            comp._pushbackReanchorPending = nil
            comp._pushbackReanchorDone = nil
            comp._pushbackReanchorTime = nil
        end
        return false
    end

    local planRef = yal.BPBPlanComplete
    local startedRef = yal.BPBStarted
    local connectedRef = yal.BPBConnected
    local plannerRef = yal.BPBPlannerOpen
    if not ((planRef and isProperty(planRef)) or (startedRef and isProperty(startedRef))) then
        comp._pushbackStartedEver = false
        comp._pushbackActive = false
        comp._pushbackCompleted = false
        comp._pushbackPlanSeen = false
        comp._guidancePushbackReleased = nil
        comp._pushbackReleaseAnchor = nil
        comp._pushbackReanchorPending = nil
        comp._pushbackReanchorDone = nil
        comp._pushbackReanchorTime = nil
        return false
    end

    local planOn = (planRef and isProperty(planRef) and get(planRef) == def.ON) or false
    local startedOn = (startedRef and isProperty(startedRef) and get(startedRef) == def.ON) or false
    local connectedOn = (connectedRef and isProperty(connectedRef) and get(connectedRef) == def.ON) or false
    local plannerOpen = (plannerRef and isProperty(plannerRef) and get(plannerRef) == def.ON) or false

    if startedOn then
        comp._pushbackStartedEver = true
        comp._pushbackActive = true
        comp._pushbackCompleted = false
        comp._pushbackPlanSeen = planOn or comp._pushbackPlanSeen
        comp._guidancePushbackReleased = nil
        comp._pushbackReleaseAnchor = nil
        comp._pushbackReanchorPending = false
        comp._pushbackReanchorDone = false
        comp._pushbackReanchorTime = nil
        return true
    end

    if comp._pushbackStartedEver then
        if connectedRef and isProperty(connectedRef) and connectedOn then
            local speed_thresh = (C and C.pushbackReleaseSpeed) or 1.0
            local secs_thresh = (C and C.pushbackReleaseSeconds) or 2.0
            local meters_thresh = (C and C.pushbackReleaseMeters) or 5
            local driftMeters = (C and C.rerouteDriftMeters) or 40
            local gs = (yal.groundspeed and (get(yal.groundspeed) or 0)) or 0
            local ts = (yal.tirespeed and (get(yal.tirespeed) or 0)) or 0
            local moving = (gs >= speed_thresh or ts >= speed_thresh)
            local joined_route = false
            if moving and comp._route and (not comp._routeErr) and aircraft
                and aircraft.east ~= nil and aircraft.north ~= nil
                and comp._route.data and comp._route.path and #comp._route.path > 1 then
                local _, dist = U.find_nearest_segment(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
                if dist and dist <= driftMeters then
                    joined_route = true
                end
            end
            if moving and joined_route and aircraft and aircraft.east ~= nil and aircraft.north ~= nil then
                local anchor = comp._pushbackReleaseAnchor
                if not anchor then
                    comp._pushbackReleaseAnchor = { east = aircraft.east, north = aircraft.north, time = now }
                else
                    local dx = aircraft.east - anchor.east
                    local dy = aircraft.north - anchor.north
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist >= meters_thresh and (now - (anchor.time or now)) >= secs_thresh then
                        comp._pushbackStartedEver = false
                        comp._pushbackActive = false
                        comp._pushbackCompleted = true
                        comp._pushbackPlanSeen = false
                        comp._guidancePushbackReleased = nil
                        comp._pushbackReleaseAnchor = nil
                        if not comp._pushbackReanchorDone and not comp._pushbackReanchorPending then
                            comp._pushbackReanchorPending = true
                            comp._pushbackReanchorTime = now or 0
                        end
                        if helpers and helpers.logInfoTS then
                            helpers.logInfoTS(
                                string.format(
                                    "TaxiRoute: pushback release by route join gs=%.1f ts=%.1f",
                                    gs or -1,
                                    ts or -1
                                )
                            )
                        end
                        return false
                    end
                end
            else
                comp._pushbackReleaseAnchor = nil
            end
            comp._pushbackActive = true
            comp._pushbackCompleted = false
            return true
        end
        comp._pushbackActive = false
        comp._pushbackCompleted = true
        comp._guidancePushbackReleased = nil
        if not comp._pushbackReanchorDone and not comp._pushbackReanchorPending then
            comp._pushbackReanchorPending = true
            comp._pushbackReanchorTime = now or 0
        end
        return false
    end

    comp._pushbackActive = false
    comp._pushbackCompleted = false
    comp._pushbackPlanSeen = planOn or comp._pushbackPlanSeen
    comp._guidancePushbackReleased = nil
    if planOn then
        if plannerOpen then
            comp._pushbackReleaseAnchor = nil
            return true
        end
        local speed_thresh = (C and C.pushbackReleaseSpeed) or 1.0
        local secs_thresh = (C and C.pushbackReleaseSeconds) or 2.0
        local meters_thresh = (C and C.pushbackReleaseMeters) or 5
        local gs = (yal.groundspeed and (get(yal.groundspeed) or 0)) or 0
        local ts = (yal.tirespeed and (get(yal.tirespeed) or 0)) or 0
        local moving = (gs >= speed_thresh or ts >= speed_thresh)
        if moving and aircraft and aircraft.east ~= nil and aircraft.north ~= nil then
            local anchor = comp._pushbackReleaseAnchor
            if not anchor then
                comp._pushbackReleaseAnchor = { east = aircraft.east, north = aircraft.north, time = now }
                return true
            end
            local dx = aircraft.east - anchor.east
            local dy = aircraft.north - anchor.north
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist >= meters_thresh and (now - (anchor.time or now)) >= secs_thresh then
                comp._pushbackCompleted = true
                comp._pushbackPlanSeen = false
                comp._guidancePushbackReleased = nil
                comp._pushbackReleaseAnchor = nil
                if not comp._pushbackReanchorDone then
                    comp._pushbackReanchorPending = true
                    comp._pushbackReanchorTime = now or 0
                end
                return false
            end
            return true
        end
        comp._pushbackReleaseAnchor = nil
        return true
    end

    comp._pushbackReleaseAnchor = nil
    return false
end

U.copy_waypoints = function(src)
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

U.copy_set = function(src)
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

U.snapshot_edit_state = function(comp)
    return {
        routeWaypoints = U.copy_waypoints(comp._routeWaypoints),
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
        editSuppressedNodes = U.copy_set(comp._editSuppressedNodes),
        selectedEndRampKey = comp._selectedEndRampKey,
        selectedDepEntryId = comp._selectedDepEntryId,
        selectedDepEntryManual = comp._selectedDepEntryManual
    }
end

U.restore_edit_state = function(comp, state)
    if not state then
        return
    end
    comp._routeWaypoints = U.copy_waypoints(state.routeWaypoints)
    comp._editStartOverride = state.editStartOverride
    comp._editEndOverride = state.editEndOverride
    if state.drawFreehand ~= nil then
        comp._drawFreehand = state.drawFreehand
    end
    comp._editSuppressedNodes = U.copy_set(state.editSuppressedNodes)
    comp._selectedEndRampKey = state.selectedEndRampKey
    comp._selectedDepEntryId = state.selectedDepEntryId
    comp._selectedDepEntryManual = state.selectedDepEntryManual
end

U.push_undo = function(comp, reason)
    comp._undoState = U.snapshot_edit_state(comp)
    comp._undoReason = reason or "edit"
    log_taxi("TaxiEdit: undo-push reason=" .. tostring(comp._undoReason))
end

U.gate_distance_meters = function(comp, aircraft, route, data)
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
        local east = ramp.east
        local north = ramp.north
        if (east == nil or north == nil) and is_valid_latlon(ramp.lat, ramp.lon) then
            east, north = latlon_to_local(ramp.lat, ramp.lon)
        end
        local ramp_dist = nil
        if east ~= nil and north ~= nil then
            ramp_dist = math.sqrt(distance_sq(ax, ay, east, north))
        end
        local dgs = U.ramp_dgs_values(ramp, aircraft)
        local use_dgs = dgs ~= nil
        if ramp_dist ~= nil then
            local dgs_max = (comp._tuning and comp._tuning.gateGuidanceRadius) or (C and C.gateGuidanceRadius) or 60
            dgs_max = dgs_max * 1.6
            if ramp_dist > dgs_max then
                use_dgs = false
            end
        end
        comp._gateUseDgs = use_dgs
        if use_dgs and dgs and dgs.nw_z ~= nil then
            local good_x = dgs.dgs_good_x or ((C and C.gateDgsGoodX) or 2.0)
            local good_z_pos = dgs.dgs_good_z_pos or ((C and C.gateDgsGoodZPos) or 0.2)
            local good_z_neg = dgs.dgs_good_z_neg or ((C and C.gateDgsGoodZNeg) or -0.5)
            local locgood = (math.abs(dgs.mw_x or 0) <= good_x)
                and dgs.nw_z >= good_z_neg
                and dgs.nw_z <= good_z_pos
            if locgood or dgs.nw_z < good_z_neg then
                best = 0
            else
                best = dgs.nw_z
            end
        elseif ramp_dist ~= nil then
            best = ramp_dist
        end
    else
        comp._gateUseDgs = false
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

U.gate_note_text = function(dist, use_dgs)
    if not dist then
        return nil
    end
    local stop_dist = use_dgs and ((C and C.gateDgsGoodZPos) or 0.2) or C.gateStopDistance
    if dist <= stop_dist then
        return "Stop"
    end
    if dist <= 80 then
        return string.format("Gate in %d m", math.floor(dist + 0.5))
    end
    return nil
end

U.reset_gate_callouts = function(comp, key)
    if not comp then
        return
    end
    comp._gateCalloutKey = key
    comp._gateCalloutStage = 0
    comp._gateCalloutStop = false
end

U.maybe_gate_voice_callouts = function(comp, dist, allow_voice, use_dgs, allow_stop)
    if not comp or not dist then
        return
    end
    if not allow_voice or not is_voice_enabled() then
        return
    end
    local stop_dist = use_dgs and ((C and C.gateDgsGoodZPos) or 0.2) or C.gateStopDistance
    if dist <= stop_dist then
        if allow_stop == false then
            return
        end
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

U.reset_dep_threshold_callouts = function(comp, key)
    if not comp then
        return
    end
    comp._depThresholdCalloutKey = key
    comp._depThresholdCalloutStage = 0
    comp._depThresholdBlockedLog = 0
end

U.maybe_dep_threshold_voice_callouts = function(comp, state, allow_voice)
    if not comp or not state then
        return
    end
    if not allow_voice or not is_voice_enabled() then
        return
    end
    local along_to_threshold = state.along_to_threshold or state.along
    if not along_to_threshold then
        return
    end
    -- Departure threshold callouts are only valid when threshold is ahead.
    if along_to_threshold >= 0 then
        return
    end
    local dist = math.abs(along_to_threshold)
    local stage = comp._depThresholdCalloutStage or 0
    local thresholds = { 300, 150, 50, 20 }
    for i, threshold in ipairs(thresholds) do
        if dist <= threshold and stage < i then
            comp._depTerminalSequenceLock = true
            speak_guidance_text(comp, "Threshold ahead in " .. tostring(threshold) .. " meters")
            comp._depThresholdCalloutStage = i
        end
    end
end

local function maybe_warn_before_taxi_not_started(comp, now, mode, on_ground, in_edit, yal)
    if not comp then
        return
    end
    if mode ~= 0 or not on_ground or not yal then
        comp._beforeTaxiVoiceWarned = false
        comp._beforeTaxiVoiceWarnAt = nil
        return
    end
    if comp._beforeTaxiStarted then
        comp._beforeTaxiVoiceWarned = false
        comp._beforeTaxiVoiceWarnAt = nil
        return
    end
    if not is_voice_enabled() then
        return
    end
    if in_edit or comp._drawRoute then
        return
    end
    if comp._pushbackActive then
        return
    end
    if yal.parkingbrakepos and get(yal.parkingbrakepos) == def.ON then
        return
    end
    local gs = yal.groundspeed and (get(yal.groundspeed) or 0) or 0
    local ts = yal.tirespeed and (get(yal.tirespeed) or 0) or 0
    if math.abs(gs) < 3 and math.abs(ts) < 3 then
        return
    end
    if comp._beforeTaxiVoiceWarned then
        return
    end
    comp._beforeTaxiVoiceWarned = true
    comp._beforeTaxiVoiceWarnAt = now or 0
    if comp._helpers and comp._helpers.logInfoTS then
        comp._helpers.logInfoTS(
            string.format(
                "TaxiVoice: before-taxi-missing gs=%.1f ts=%.1f",
                gs or 0,
                ts or 0
            )
        )
    end
    if comp._helpers and comp._helpers.speak then
        comp._helpers.speak("Warning, before taxi procedure not started")
    end
end

local function updateTaxiState(comp, map)
    local U = comp._U or {}
    local C = comp._C or {}
    local def = comp._def
    local helpers = comp._helpers
    local log_taxi = comp._logTaxi
    local tuning = comp._tuning or {}
    local now = 0
    if comp._timer then
        now = sasl.getElapsedSeconds(comp._timer) or 0
    end
    local in_edit = comp._editRoute or comp._drawRoute
    if comp._lastUpdate and (now - comp._lastUpdate) < C.updateInterval then
        return
    end
    comp._lastUpdate = now

    -- Rebind to the latest global YAL context after SASL reloads.
    if _G.yal and comp.yal ~= _G.yal then
        comp.yal = _G.yal
        if log_taxi then
            log_taxi("TaxiCtx: rebind global yal")
        end
    end

    -- Always refresh aircraft position for display, even in edit/draw mode.
    local yal = comp.yal or _G.yal
    if yal and yal.aircraftlatpos and yal.aircraftlonpos then
        local alat = get(yal.aircraftlatpos)
        local alon = get(yal.aircraftlonpos)
        if U.is_valid_latlon(alat, alon) then
            local ae, an = U.latlon_to_local(alat, alon)
            if ae and an then
                comp._aircraftPoint = { east = ae, north = an }
            end
        end
    end

    if in_edit then
        U.clear_visual_guidance(comp, "edit")
        comp._visualGuidanceQueue = {}
    end

    if not yal then
        comp._dataErr = "yal-not-ready"
        return
    end

    local depIcao = nil
    if yal.depicao then
        depIcao = U.normalize_icao(get(yal.depicao) or "")
        if not helpers.isvalidicao(depIcao) then
            depIcao = nil
        end
    end
    local desIcao = nil
    if yal.desicao then
        desIcao = U.normalize_icao(get(yal.desicao) or "")
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
            comp._arrGroundRecomputePending = true
            if comp._quality then
                comp._quality.rerouteEvents = {}
                comp._quality.badSince = nil
                comp._quality.distBadSince = nil
            end
        end
    else
        comp._arrOnGroundSince = nil
        comp._arrGroundRecomputePending = nil
    end
    if comp._arrTaxiCompleteFreeze then
        local release = false
        if mode ~= 1 or (not onGroundSensor) then
            release = true
        elseif in_edit or comp._drawRoute then
            release = true
        elseif (comp._manualRouteActive and comp._manualRouteActive == true) then
            release = true
        else
            local gs_now = yal.groundspeed and (get(yal.groundspeed) or 0) or 0
            local park_now = yal.parkingbrakepos and get(yal.parkingbrakepos) or nil
            if park_now ~= def.ON and gs_now > 2 then
                release = true
            end
        end
        if release then
            comp._arrTaxiCompleteFreeze = false
            if comp._routeErr == "taxi-complete" then
                comp._routeErr = nil
            end
            log_taxi("TaxiRoute: taxi-complete freeze released")
        end
    end
    local nearestIcao = nil
    if yal.nearesticao then
        local nearest = U.normalize_icao(get(yal.nearesticao) or "")
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
        U.clear_temp_route_overlay(comp, comp._data)
        comp._data = nil
        comp._route = nil
        comp._dataErr = "invalid-icao"
        comp._routeErr = nil
        comp._lastIcao = nil
        comp._fitBounds = nil
        comp._runwayName = nil
        U.clear_visual_guidance(comp, "invalid-icao")
        comp._visualGuidanceQueue = {}
        comp._drawFreehand = false
        comp._arrOffRunwayHandled = false
        comp._arrExitLockedId = nil
        comp._arrExitLockedAlong = nil
        comp._arrExitId = nil
        comp._arrExitAlong = nil
        comp._arrProfile = nil
        comp._arrBacktrackRequired = nil
        comp._arrRunwayStartNodeLatched = nil
        comp._arrRunwayStartNodeIcao = nil
        comp._arrRunwayStartNodeRunway = nil
        comp._arrGroundRecomputePending = nil
        comp._arrTaxiCompleteFreeze = false
        comp._arrRunwayExitAnnounced = false
        comp._arrRunwayCrossWarned = nil
        comp._runwayCrossWarnedKey = nil
        comp._initialMoveAnchor = nil
        comp._guidanceMoveAnchor = nil
        comp._depEntryIssuedAt = nil
        comp._depRunwayEntryLock = false
        comp._depTerminalSequenceLock = false
        comp._depHoldshortLatchedId = nil
        comp._depHoldshortLatchIcao = nil
        comp._depHoldshortLatchRunway = nil
        comp._beforeTaxiVoiceWarned = false
        comp._beforeTaxiVoiceWarnAt = nil
        clear_pushback_join_hold(comp)
        comp._lastPushbackJoinHoldLog = nil
        comp._offrouteDivergenceCount = 0
        comp._editTailSegments = nil
        comp._activeDataSource = nil
        comp._activeSourceIcao = nil
        comp._activeSourceMode = nil
        comp._sourceSwitchPending = nil
        comp._startRamp = nil
        comp._startRampLabel = nil
        comp._startRampKey = nil
        comp._startRampRejectKey = nil
        comp._startRampChoiceKey = nil
        comp._startRampChoiceSource = nil
        U.set_taxi_ref(nil)
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
        comp._startRampLabel = nil
        comp._startRampKey = nil
        comp._startRampRejectKey = nil
        comp._startRampChoiceKey = nil
        comp._startRampChoiceSource = nil
        comp._endRamp = nil
        comp._lastStartKey = nil
        comp._lastEndKey = nil
        comp._routeStartAnchor = nil
        comp._routeExtraSegments = nil
        U.clear_temp_route_overlay(comp, comp._data)
        comp._editTailSegments = nil
        comp._lastGuidanceNodeId = nil
        comp._lastGuidanceLabel = nil
        comp._lastGuidanceTime = nil
        comp._sCurveSkipNodeId = nil
        U.clear_visual_guidance(comp, "reset")
        comp._visualGuidanceQueue = {}
        comp._editHandles = nil
        comp._editSuppressedNodes = nil
        comp._editDirty = false
        comp._editStartOverride = nil
        comp._editEndOverride = nil
        comp._lastOffNetworkStartKey = nil
        comp._lastOffNetworkEndKey = nil
        comp._lastAutoRouteLogKey = nil
        comp._drawFreehand = false
        comp._arrOffRunwayHandled = false
        comp._arrExitLockedId = nil
        comp._arrExitLockedAlong = nil
        comp._arrExitId = nil
        comp._arrExitAlong = nil
        comp._arrProfile = nil
        comp._arrBacktrackRequired = nil
        comp._arrRunwayStartNodeLatched = nil
        comp._arrRunwayStartNodeIcao = nil
        comp._arrRunwayStartNodeRunway = nil
        comp._arrGroundRecomputePending = nil
        comp._arrTaxiCompleteFreeze = false
        comp._arrRunwayExitAnnounced = false
        comp._arrRunwayCrossWarned = nil
        comp._depRunwayEntryAnnounced = false
        comp._depTaxiCompleteAnnounced = false
        comp._arrTaxiCompleteAnnounced = false
        comp._initialGuidanceDone = false
        comp._initialMoveAnchor = nil
        comp._guidanceMoveAnchor = nil
        comp._runwayCrossWarnedKey = nil
        comp._depEntryIssuedAt = nil
        comp._depRunwayEntryLock = false
        comp._depTerminalSequenceLock = false
        comp._beforeTaxiVoiceWarned = false
        comp._beforeTaxiVoiceWarnAt = nil
        clear_pushback_join_hold(comp)
        comp._lastPushbackJoinHoldLog = nil
        comp._offrouteDivergenceCount = 0
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
        comp._manualRouteLock = false
        comp._manualRouteSnapshot = nil
        comp._rerouteOverride = nil
        comp._rerouteOverrideHoldUntil = nil
        comp._depThresholdLatched = false
        comp._depRunwayEntryLock = false
        comp._depTerminalSequenceLock = false
        comp._depSegmentReanchorDone = false
        comp._takeoffLatchSince = nil
        comp._autoEndRampLowSpeedSince = nil
        comp._autoEndRampSwitchTime = nil
        if icao_changed or mode_changed then
            comp._autoEndRampKey = nil
            comp._activeDataSource = nil
            comp._activeSourceIcao = nil
            comp._activeSourceMode = nil
            comp._sourceSwitchPending = nil
            clear_dep_source_lock(comp, "reset", log_taxi)
            if mode == 0 and icao and icao ~= "" then
                if get_taxi_source_mode(comp, icao) == "auto" then
                    comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
                    comp._taxiSourceByIcao[icao] = nil
                    if comp._taxiGlobalPending then
                        comp._taxiGlobalPending[icao] = nil
                    end
                end
            end
        end
        if icao_changed then
            comp._selectedEndRampKey = nil
            comp._selectedDepEntryId = nil
            comp._selectedDepEntryManual = nil
            comp._data = nil
            comp._dataErr = nil
        end
        if icao_changed and (not prev_icao_valid) and (not mode_changed) then
            comp._editStartOverride = prev_start_override
            comp._editEndOverride = prev_end_override
            comp._routeWaypoints = prev_waypoints or {}
            comp._drawFreehand = prev_draw_freehand
            comp._manualRouteLock = (prev_waypoints and #prev_waypoints > 0) or false
            comp._manualRouteSnapshot = nil
        end
    end

    comp._lastIcao = icao
    comp._lastMode = mode

    local data = comp._data
    local derr = comp._dataErr
    local pending = (derr == "global-index-pending")
    if data and comp._taxiGlobalPending and comp._taxiGlobalPending[icao]
        and helpers.isGlobalAptIndexReady and helpers.isGlobalAptIndexReady() then
        if get_taxi_source_mode(comp, icao) == "addon" then
            comp._taxiGlobalPending[icao] = nil
            if log_taxi then
                log_taxi("TaxiSource: skip pending-global (manual addon) icao=" .. tostring(icao))
            end
        elseif not (mode == 0 and dep_source_lock_active(comp, icao) and get_taxi_source_mode(comp, icao) == "auto") then
            mark_source_switch_pending(comp, icao, mode, "global-ready")
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
            comp._sCurveSkipNodeId = nil
            comp._needsCenter = true
            comp._rerouteOverride = nil
            comp._rerouteOverrideHoldUntil = nil
            if comp._quality then
                comp._quality.badSince = nil
                comp._quality.distBadSince = nil
                comp._quality.rerouteEvents = {}
            end
        else
            comp._taxiGlobalPending[icao] = nil
            if log_taxi then
                log_taxi("TaxiSource: skip pending-global (addon lock) icao=" .. tostring(icao))
            end
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
        if mode == 0 and dep_source_lock_active(comp, icao) and get_taxi_source_mode(comp, icao) == "auto" then
            policy = "addon"
        end
        if helpers.getTaxiDataWithPolicy then
            data, derr = helpers.getTaxiDataWithPolicy(icao, policy)
        else
            data, derr = helpers.getTaxiData(icao)
        end
        pending = (derr == "global-index-pending")
    end
    if not data then
        U.clear_temp_route_overlay(comp, comp._data)
        comp._data = nil
        comp._dataErr = pending and "global-index-pending" or (derr or "apt-not-found")
        comp._fitBounds = nil
        comp._runwayName = nil
        comp._routeExtraSegments = nil
        comp._editTailSegments = nil
        comp._arrExitId = nil
        comp._arrExitAlong = nil
        comp._arrProfile = nil
        comp._arrBacktrackRequired = nil
        comp._arrRunwayStartNodeLatched = nil
        comp._arrRunwayStartNodeIcao = nil
        comp._arrRunwayStartNodeRunway = nil
        comp._arrGroundRecomputePending = nil
        comp._arrTaxiCompleteFreeze = false
        comp._arrRunwayExitAnnounced = false
        comp._arrRunwayCrossWarned = nil
        U.clear_visual_guidance(comp, "no-data")
        comp._visualGuidanceQueue = {}
        U.set_taxi_ref(nil)
        return
    end
    comp._data = data
    if mode == 0 and get_taxi_source_mode(comp, icao) == "auto" then
        set_dep_source_lock(comp, icao, data, log_taxi)
    end
    U.set_taxi_ref(data)
    comp._dataErr = nil
    if comp._manualRouteLock and (not in_edit) and (not comp._drawRoute) and data then
        local snap = comp._manualRouteSnapshot
        if snap and snap.data == data and snap.icao == icao and snap.mode == mode then
            if not comp._route and snap.route then
                comp._route = snap.route
                comp._routeLabels = snap.routeLabels
                comp._routeLabelStats = snap.routeLabelStats
                comp._routeExtraSegments = snap.routeExtraSegments
                comp._lastStartKey = snap.lastStartKey
                comp._lastEndKey = snap.lastEndKey
                log_taxi("TaxiRoute: manual-snapshot restore")
            end
        elseif comp._route then
            comp._manualRouteSnapshot = {
                route = comp._route,
                routeLabels = comp._routeLabels,
                routeLabelStats = comp._routeLabelStats,
                routeExtraSegments = comp._routeExtraSegments,
                lastStartKey = comp._lastStartKey,
                lastEndKey = comp._lastEndKey,
                data = data,
                icao = icao,
                mode = mode
            }
            log_taxi("TaxiRoute: manual-snapshot store")
        end
    end
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
                comp._routeLabels = U.build_route_labels(data, comp._route.path)
                comp._routeLabelStats = U.compute_route_label_stats(data, comp._route.path)
            end
            if comp._quality then
                comp._quality.badSince = nil
            end
        end
    end
    local shifted, shift_dx, shift_dy = U.align_taxi_data_projection(data)
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
    if U.is_valid_latlon(lat, lon) then
        local east, north = U.latlon_to_local(lat, lon)
        if east and north then
            local heading = yal and yal.groundtrackmag and get(yal.groundtrackmag) or nil
            local nose_offset = nil
            local main_offset = nil
            if yal and yal.gear_znose then
                local gear_z = get(yal.gear_znose)
                if type(gear_z) == "number" and gear_z ~= 0 then
                    nose_offset = -gear_z
                end
            end
            if yal and yal.gear_zmain then
                local gear_z = get(yal.gear_zmain)
                if type(gear_z) == "number" and gear_z ~= 0 then
                    main_offset = -gear_z
                end
            end
            if (nose_offset == nil or nose_offset == 0) and yal and yal.acf_cg_z then
                local cg_z = get(yal.acf_cg_z)
                if type(cg_z) == "number" and cg_z ~= 0 then
                    nose_offset = math.abs(cg_z) * 0.3048
                end
            end
            if main_offset == nil or main_offset == 0 then
                main_offset = nose_offset
            end
            aircraft = {
                lat = lat,
                lon = lon,
                east = east,
                north = north,
                heading = heading,
                nose_offset = nose_offset,
                main_offset = main_offset
            }
        end
    end
    if mode == 0 and U.update_pushback_state then
        U.update_pushback_state(comp, now, yal, aircraft)
    end
    local nearest_ramp = nil
    local nearest_ramp_dist = nil
    local active_source = normalize_source_tag(data and data.entry and data.entry.source)
    if comp._activeSourceIcao ~= icao or comp._activeSourceMode ~= mode then
        comp._activeSourceIcao = icao
        comp._activeSourceMode = mode
        comp._activeDataSource = active_source
        comp._sourceSwitchPending = nil
    elseif comp._activeDataSource and active_source ~= comp._activeDataSource then
        local pending = comp._sourceSwitchPending
        local reason = "auto"
        if pending and pending.icao == icao and pending.mode == mode and pending.reason and pending.reason ~= "" then
            reason = pending.reason
        end
        log_taxi(
            "TaxiSource: active="
            .. tostring(comp._activeDataSource)
            .. " -> "
            .. tostring(active_source)
            .. " icao="
            .. tostring(icao)
            .. " mode="
            .. tostring(mode)
            .. " reason="
            .. tostring(reason)
        )
        local has_manual_route = comp._manualRouteLock
            and (
                (comp._routeWaypoints and #comp._routeWaypoints > 0)
                or (comp._route and comp._route.path and #comp._route.path > 1)
            )
        local switched = false
        if onGroundSensor and aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon)
            and (not in_edit) and (not comp._drawRoute) and (not comp._drawFreehand)
            and (not has_manual_route) then
            switched = reroute_from_current_aircraft(comp, data, "source-switch", true, log_taxi)
            if switched and mode == 0 then
                comp._depEntryReselectPending = true
            end
        end
        if not switched then
            log_taxi(
                "TaxiSource: migrate skipped onGround="
                .. tostring(onGroundSensor == true)
                .. " edit="
                .. tostring(in_edit == true)
                .. " draw="
                .. tostring((comp._drawRoute or comp._drawFreehand) == true)
                .. " manual="
                .. tostring(has_manual_route == true)
            )
        end
        comp._sourceSwitchPending = nil
        comp._activeDataSource = active_source
    end
    if comp._rerouteOverrideHoldUntil and now and now > comp._rerouteOverrideHoldUntil then
        comp._rerouteOverrideHoldUntil = nil
    end
    if comp._rerouteOverride and aircraft and U.is_valid_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) then
        local d_override = U.distance_meters_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon, aircraft.lat, aircraft.lon)
        if d_override and d_override > 1000 then
            comp._rerouteOverride = nil
            comp._rerouteOverrideHoldUntil = nil
        end
    end
    if mode == 0 and comp._pushbackReanchorPending and aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon) then
        if not in_edit then
            local seg_idx = nil
            local dist = nil
            if comp._route and (not comp._routeErr) and comp._route.data and comp._route.path and #comp._route.path > 1 then
                seg_idx, dist = U.find_nearest_segment(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
            end
            local driftMeters = (mode == 1 and C.arrRerouteDriftMeters) or C.rerouteDriftMeters
            if seg_idx and dist and driftMeters and dist <= driftMeters then
                comp._pushbackReanchorPending = false
                comp._pushbackReanchorDone = true
                comp._pushbackReanchorTime = nil
                arm_pushback_join_hold(comp, now, seg_idx)
                comp._rerouteOverride = nil
                comp._rerouteOverrideHoldUntil = nil
                comp._pendingRerouteEvent = nil
                comp._depSegmentReanchorDone = true
                comp._lastRerouteTime = now
                reset_guidance_tracking(comp, false)
                comp._autoTaxiActiveRoute = comp._route
                comp._autoTaxiActiveSegIdx = seg_idx
                comp._autoTaxiLastSegIdx = seg_idx
                comp._autoTaxiRunwaySegIdx = nil
                comp._guidanceRoute = comp._route
                comp._guidanceActiveSegIdx = seg_idx
                comp._guidanceMonotonicSegIdx = seg_idx
                comp._guidanceForceInitial = true
                if log_taxi then
                    log_taxi(string.format("TaxiRoute: pushback reattach seg=%s dist=%.1f", tostring(seg_idx), dist or 0))
                elseif helpers and helpers.logInfoTS then
                    helpers.logInfoTS(
                        string.format("TaxiRoute: pushback reattach seg=%s dist=%.1f", tostring(seg_idx), dist or 0)
                    )
                end
            else
                clear_pushback_join_hold(comp)
                comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
                if data and aircraft.east ~= nil and aircraft.north ~= nil then
                    local proj = U.find_nearest_edge_projection(data, aircraft.east, aircraft.north, { disallow_runway_edges = true })
                    if proj and proj.proj_east and proj.proj_north then
                        local plat, plon = local_to_latlon(proj.proj_east, proj.proj_north)
                        if U.is_valid_latlon(plat, plon) then
                            comp._rerouteOverride = { lat = plat, lon = plon }
                        end
                    end
                end
                comp._routeStartAnchor = nil
                comp._lastStartKey = nil
                comp._route = nil
                comp._routeErr = nil
                comp._routeLabels = nil
                comp._routeLabelStats = nil
                comp._autoTaxiPath = nil
                comp._autoTaxiPathRoute = nil
                comp._pendingRerouteEvent = true
                comp._pushbackReanchorPending = false
                comp._pushbackReanchorDone = true
                comp._pushbackReanchorTime = nil
                comp._depEntryReselectPending = true
                if log_taxi then
                    log_taxi("TaxiRoute: pushback reanchor")
                elseif helpers and helpers.logInfoTS then
                    helpers.logInfoTS("TaxiRoute: pushback reanchor")
                end
            end
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
    local dep_entry_candidate_id = nil
    local dep_entry_candidate_dist = nil
    local dep_entry_candidate_lat = nil
    local dep_entry_candidate_lon = nil
    local dep_backtrack_required = false
    local arr_exit_id = nil
    local allow_runway_route = false
    local manual_active = false
    if comp._manualRouteLock then
        if (comp._routeWaypoints and #comp._routeWaypoints > 0) or comp._route then
            manual_active = true
        end
    end
    if comp._editRoute or comp._drawRoute then
        manual_active = true
    end
    if comp._manualRouteActive ~= manual_active then
        comp._manualRouteActive = manual_active
        log_taxi("TaxiEdit: manual-route=" .. tostring(manual_active))
    end
    if mode == 1 and comp._arrGroundRecomputePending
        and onGroundSensor and aircraft and (not in_edit)
        and (not manual_active) and (not comp._drawFreehand)
        and (not comp._editStartOverride) and (not comp._editEndOverride)
        and after_landing_started(comp) then
        comp._arrGroundRecomputePending = nil
        force_arrival_recompute(comp, data, aircraft, now, "arr-taxi-start", log_taxi)
    end

    if mode == 0 then
        comp._arrRawRunwayMissing = false
        if aircraft then
            start_lat = aircraft.lat
            start_lon = aircraft.lon
        end
        runway_lat = yal.deprwylatstartpos and get(yal.deprwylatstartpos) or nil
        runway_lon = yal.deprwylonstartpos and get(yal.deprwylonstartpos) or nil
        if not U.is_valid_latlon(runway_lat, runway_lon) then
            runway_lat = yal.deprwylatendpos and get(yal.deprwylatendpos) or nil
            runway_lon = yal.deprwylonendpos and get(yal.deprwylonendpos) or nil
        end
        runway_name = yal.deprwy and helpers.forceCleanString(get(yal.deprwy) or "") or ""
        if comp._lastDepRunwayName and comp._lastDepRunwayName ~= runway_name then
            comp._selectedDepEntryId = nil
            comp._selectedDepEntryManual = nil
            comp._depHoldshortLatchedId = nil
            comp._depHoldshortLatchIcao = nil
            comp._depHoldshortLatchRunway = nil
        end
        comp._lastDepRunwayName = runway_name
        comp._runwayName = runway_name
        if comp._depHoldshortLatchIcao ~= icao or comp._depHoldshortLatchRunway ~= runway_name then
            comp._depHoldshortLatchedId = nil
            comp._depHoldshortLatchIcao = icao
            comp._depHoldshortLatchRunway = runway_name
        end
        if data and comp._runwayName and comp._runwayName ~= "" then
            local rwy, side = U.find_runway_entry(data, comp._runwayName, runway_lat, runway_lon)
            if rwy then
                runway_lat = (side == 1) and rwy.lat1 or rwy.lat2
                runway_lon = (side == 1) and rwy.lon1 or rwy.lon2
                dep_holdshort_id = U.find_holdshort_node_near(data, runway_lat, runway_lon)
                if (not dep_holdshort_id) and comp._depHoldshortLatchedId
                    and data.nodes and data.nodes[comp._depHoldshortLatchedId] then
                    local ln = data.nodes[comp._depHoldshortLatchedId]
                    if U.is_valid_latlon(ln.lat, ln.lon) then
                        local d_lh = U.distance_meters_latlon(runway_lat, runway_lon, ln.lat, ln.lon)
                        if d_lh and d_lh <= 2000 then
                            dep_holdshort_id = comp._depHoldshortLatchedId
                        else
                            comp._depHoldshortLatchedId = nil
                        end
                    else
                        comp._depHoldshortLatchedId = nil
                    end
                end
                if dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                    local hs = data.nodes[dep_holdshort_id]
                    if U.is_valid_latlon(hs.lat, hs.lon) then
                        local d_hs = U.distance_meters_latlon(runway_lat, runway_lon, hs.lat, hs.lon)
                        if d_hs and d_hs > 2000 then
                            dep_holdshort_id = nil
                            comp._depHoldshortLatchedId = nil
                        else
                            comp._depHoldshortLatchedId = dep_holdshort_id
                            end_lat = hs.lat
                            end_lon = hs.lon
                        end
                    end
                elseif dep_holdshort_id and (not data.nodes or not data.nodes[dep_holdshort_id]) then
                    comp._depHoldshortLatchedId = nil
                end
                if not dep_holdshort_id and U.is_valid_latlon(runway_lat, runway_lon) then
                    dep_end_node_id, dep_end_node_dist = U.nearest_non_runway_node(data, runway_lat, runway_lon)
                    if dep_end_node_id and data.nodes and data.nodes[dep_end_node_id] then
                        local dn = data.nodes[dep_end_node_id]
                        if U.is_valid_latlon(dn.lat, dn.lon) then
                            end_lat = dn.lat
                            end_lon = dn.lon
                        end
                    end
                end
                if not dep_holdshort_id
                    and not manual_active
                    and not comp._selectedDepEntryId
                    and dep_end_node_dist and dep_end_node_dist > C.depEntryFallbackMaxDist
                    and data and data.nodes
                    and aircraft and aircraft.east ~= nil and aircraft.north ~= nil then
                    local re, rn = U.latlon_to_local(runway_lat, runway_lon)
                    if re and rn then
                        local candidates = collect_runway_exit_candidates(data, re, rn, 18)
                        if candidates and #candidates > 0 then
                            local best_id = nil
                            local best_d2 = nil
                            for _, cand in ipairs(candidates) do
                                local node = data.nodes[cand.id]
                                if node and node.east and node.north then
                                    local dx = node.east - aircraft.east
                                    local dy = node.north - aircraft.north
                                    local d2 = dx * dx + dy * dy
                                    if not best_d2 or d2 < best_d2 then
                                        best_d2 = d2
                                        best_id = cand.id
                                    end
                                end
                            end
                            if best_id then
                                local dn = data.nodes[best_id]
                                if dn and U.is_valid_latlon(dn.lat, dn.lon) then
                                    dep_entry_candidate_id = best_id
                                    dep_entry_candidate_dist = math.sqrt(best_d2 or 0)
                                    dep_entry_candidate_lat = dn.lat
                                    dep_entry_candidate_lon = dn.lon
                                    log_taxi(
                                        string.format(
                                            "TaxiRoute: dep entry candidate id=%s dist=%.1f",
                                            tostring(best_id),
                                            dep_entry_candidate_dist or -1
                                        )
                                    )
                                end
                            end
                        end
                    end
                end
            end
        end
        if not U.is_valid_latlon(end_lat, end_lon) then
            end_lat = runway_lat
            end_lon = runway_lon
        end
        if aircraft and comp.yal and comp.yal.aircraftonrwy and U.is_valid_latlon(runway_lat, runway_lon) then
            local onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, C.depThresholdHeadingLimit)
            if onRunway then
                allow_runway_route = true
            end
        end
    else
        local arr_runway_inferred = false
        runway_lat = yal.desrwylatstartpos and get(yal.desrwylatstartpos) or nil
        runway_lon = yal.desrwylonstartpos and get(yal.desrwylonstartpos) or nil
        if not U.is_valid_latlon(runway_lat, runway_lon) then
            runway_lat = yal.desrwylatendpos and get(yal.desrwylatendpos) or nil
            runway_lon = yal.desrwylonendpos and get(yal.desrwylonendpos) or nil
        end
        if U.is_valid_latlon(runway_lat, runway_lon) then
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
        if data and onGroundSensor and raw_desrwy == "" and aircraft then
            local inferred = infer_arrival_runway_from_aircraft(data, aircraft)
            if inferred and inferred.name and inferred.name ~= "" then
                if runway_name ~= inferred.name or (not U.is_valid_latlon(runway_lat, runway_lon)) then
                    local infer_key = tostring(icao) .. "|ARR-INFER|" .. tostring(inferred.name)
                        .. "|" .. tostring(math.floor((inferred.along or 0) + 0.5))
                        .. "|" .. tostring(math.floor((inferred.perp or 0) + 0.5))
                    if comp._lastArrInferLogKey ~= infer_key then
                        comp._lastArrInferLogKey = infer_key
                        helpers.logInfoTS(
                            "Taxi: ARR runway inferred " .. tostring(inferred.name) ..
                            " along=" .. string.format("%.1f", inferred.along or -1) ..
                            " perp=" .. string.format("%.1f", inferred.perp or -1) ..
                            " hdgDiff=" .. string.format("%.1f", inferred.heading_diff or -1)
                        )
                    end
                end
                runway_name = inferred.name
                runway_lat = inferred.lat
                runway_lon = inferred.lon
                landing_profile = inferred.profile
                comp._lastArrivalRunwayName = runway_name
                comp._lastArrivalRunwayLat = runway_lat
                comp._lastArrivalRunwayLon = runway_lon
                arr_runway_inferred = true
            end
        end
        comp._arrRawRunwayMissing = (mode == 1 and onGroundSensor and raw_desrwy == "" and runway_name ~= "" and (not arr_runway_inferred))
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
            local rwy, side = U.find_runway_entry(data, comp._runwayName, ref_lat, ref_lon)
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
            landing_profile = landing_profile or U.compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
            touchdown = landing_profile and landing_profile.touchdown or nil
            if landing_profile and touchdown and touchdown.east and touchdown.north then
                if onGroundSensor and aircraft and aircraft.east ~= nil and aircraft.north ~= nil then
                    local on_rwy_now = is_on_runway_profile(landing_profile, aircraft, 60, 5)
                    if on_rwy_now then
                        local along = U.compute_along_perp(landing_profile, aircraft)
                        if along then
                            if (not landing_profile.roll) or along > landing_profile.roll then
                                landing_profile.roll = along
                            end
                        end
                    end
                end
                local exit_id = nil
                exit_id, backtrack_required = U.select_runway_exit_node(data, landing_profile, nil, airborne)
                arr_exit_id = exit_id
                if exit_id and data.nodes and data.nodes[exit_id] then
                    local exit_node = data.nodes[exit_id]
                    if U.is_valid_latlon(exit_node.lat, exit_node.lon) then
                        if (yal and yal.airgroundsensor and (get(yal.airgroundsensor) ~= def.ON)) then
                            start_lat = exit_node.lat
                            start_lon = exit_node.lon
                        elseif not backtrack_required then
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
                            along, perp = U.compute_along_perp(landing_profile, exit_node)
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
                if not U.is_valid_latlon(start_lat, start_lon) then
                    local tlat, tlon = local_to_latlon(touchdown.east, touchdown.north)
                    if U.is_valid_latlon(tlat, tlon) then
                        start_lat = tlat
                        start_lon = tlon
                        runway_lat = tlat
                        runway_lon = tlon
                    end
                end
            end
        end
        if not U.is_valid_latlon(start_lat, start_lon) then
            start_lat = runway_lat
            start_lon = runway_lon
        end
    end

    if mode == 1 and aircraft and U.is_valid_latlon(runway_lat, runway_lon) then
        local offRunway = nil
        if landing_profile then
            offRunway = not is_on_runway_profile(landing_profile, aircraft, 60, 5)
        elseif comp.yal and comp.yal.aircraftonrwy then
            offRunway = not comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
        end
        comp._arrOffRunway = offRunway
        if offRunway == false then
            allow_runway_route = true
            start_lat = aircraft.lat
            start_lon = aircraft.lon
        else
            comp._arrRunwayStartNodeLatched = nil
            comp._arrRunwayStartNodeIcao = nil
            comp._arrRunwayStartNodeRunway = nil
        end
    else
        comp._arrOffRunway = nil
        comp._arrRunwayStartNodeLatched = nil
        comp._arrRunwayStartNodeIcao = nil
        comp._arrRunwayStartNodeRunway = nil
    end

    if mode == 0 and helpers and helpers.before_taxi_started then
        comp._beforeTaxiStarted = helpers.before_taxi_started(yal)
    else
        comp._beforeTaxiStarted = false
    end
    if not comp._beforeTaxiStarted then
        comp._beforeTaxiReanchorDone = nil
        comp._beforeTaxiReanchorIcao = nil
        comp._beforeTaxiReanchorRunway = nil
    elseif mode == 0 and aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon)
        and (not in_edit) and (not manual_active) and (not comp._drawFreehand)
        and (not comp._editStartOverride) and (not comp._editEndOverride) then
        if comp._beforeTaxiReanchorIcao ~= icao or comp._beforeTaxiReanchorRunway ~= runway_name then
            comp._beforeTaxiReanchorDone = nil
        end
        if not comp._beforeTaxiReanchorDone then
            comp._beforeTaxiReanchorDone = true
            comp._beforeTaxiReanchorIcao = icao
            comp._beforeTaxiReanchorRunway = runway_name
            comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
            comp._routeStartAnchor = nil
            comp._lastStartKey = nil
            comp._route = nil
            comp._routeErr = nil
            comp._routeLabels = nil
            comp._routeLabelStats = nil
            comp._autoTaxiPath = nil
            comp._autoTaxiPathRoute = nil
            comp._pendingRerouteEvent = true
            log_taxi("TaxiRoute: before-taxi reanchor")
        end
    end
    maybe_warn_before_taxi_not_started(comp, now, mode, onGroundSensor, in_edit, yal)

    local hasRunwayName = (runway_name ~= nil and runway_name ~= "")
    local hasRunwayLatLon = U.is_valid_latlon(runway_lat, runway_lon)
    local hasArrivalRunway = (mode == 1 and hasRunwayName) or false
    local freehand_active = comp._drawFreehand and comp._routeWaypoints and (#comp._routeWaypoints > 0)
    local canRoute = data and data.can_route and (mode == 1 or hasRunwayName or freehand_active) or false
    if not canRoute and not freehand_active then
        helpers.logInfoTS(
            "TaxiDiag: canRoute=false icao=" .. tostring(icao) ..
            " mode=" .. tostring(mode) ..
            " data.can_route=" .. tostring(data and data.can_route) ..
            " hasRunwayName=" .. tostring(hasRunwayName)
        )
    end

    if mode == 0 and data and U.is_valid_latlon(runway_lat, runway_lon) and hasRunwayName then
        local dep_rwy = nil
        local dep_side = nil
        if comp._runwayName and comp._runwayName ~= "" then
            dep_rwy, dep_side = U.find_runway_entry(data, comp._runwayName, runway_lat, runway_lon)
            if (not dep_rwy)
                and data.entry and data.entry.source == "addon"
                and get_taxi_source_mode(comp, icao) == "auto" then
                if helpers and helpers.requestGlobalAptIndex then
                    helpers.requestGlobalAptIndex("addon-runway-mismatch")
                end
                log_taxi(
                    "TaxiSource: addon runway mismatch icao="
                        .. tostring(icao)
                        .. " dep="
                        .. tostring(comp._runwayName)
                )
                if force_global_source(comp, icao, mode, "addon-runway-mismatch", log_taxi) then
                    return
                end
            end
        end
        if not dep_rwy then
            dep_rwy, dep_side = U.find_nearest_runway_entry_by_latlon(data, runway_lat, runway_lon)
        end
        if dep_rwy then
            dep_profile = U.compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
            if dep_profile and dep_profile.threshold and dep_profile.threshold.east and dep_profile.threshold.north then
                dep_runway_end_id = U.find_nearest_runway_node(
                    data,
                    dep_profile.threshold.east,
                    dep_profile.threshold.north
                )
                local tlat, tlon = local_to_latlon(dep_profile.threshold.east, dep_profile.threshold.north)
                if U.is_valid_latlon(tlat, tlon) then
                    dep_runway_end_lat = tlat
                    dep_runway_end_lon = tlon
                end
            end
            local dep_label = U.runway_end_label(dep_rwy, dep_side)
            if dep_label == "" then
                dep_label = U.runway_pair_label(dep_rwy)
            end
            comp._depProfileLabel = dep_label
        else
            comp._depProfileLabel = nil
        end
    else
        comp._depProfileLabel = nil
    end
    if mode == 0 and dep_profile and (not dep_holdshort_id)
        and dep_end_node_dist and dep_end_node_dist > C.depEntryFallbackMaxDist then
        dep_backtrack_required = true
        if not manual_active then
            allow_runway_route = true
        end
    end
    if mode == 0 then
        if comp._depBacktrackRequired ~= dep_backtrack_required then
            comp._depBacktrackRequired = dep_backtrack_required
            if dep_backtrack_required then
                log_taxi(
                    string.format(
                        "TaxiRoute: dep backtrack required dist=%.1f",
                        dep_end_node_dist or -1
                    )
                )
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

    if mode == 0 and (not U.is_valid_latlon(start_lat, start_lon)) and U.is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
        start_lat = ramp_ref_lat
        start_lon = ramp_ref_lon
    end
    if mode == 1 and (not U.is_valid_latlon(start_lat, start_lon)) and U.is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
        start_lat = ramp_ref_lat
        start_lon = ramp_ref_lon
    end

    local end_ramp = nil
    local user_selected_end = false
    if mode == 1 and (not comp._drawFreehand) and U.is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
        if comp._selectedEndRampKey and data and data.ramps then
            for _, ramp in ipairs(data.ramps) do
                if helpers.isRampSuitableFor738(ramp) and U.ramp_key(ramp) == comp._selectedEndRampKey then
                    end_ramp = ramp
                    user_selected_end = true
                    break
                end
            end
        end
        if not end_ramp and comp._autoEndRampKey and data and data.ramps then
            for _, ramp in ipairs(data.ramps) do
                if helpers.isRampSuitableFor738(ramp) and U.ramp_key(ramp) == comp._autoEndRampKey then
                    end_ramp = ramp
                    break
                end
            end
            if not end_ramp then
                comp._autoEndRampKey = nil
            end
        end
        if not end_ramp and onGroundSensor and aircraft then
            local gate_heading = yal and yal.groundtrackmag and get(yal.groundtrackmag) or nil
            local gate_radius = tuning.gateSelectRadius or (C and C.gateSelectRadius) or 120
            end_ramp = U.select_best_ramp_for_aircraft(
                data,
                aircraft,
                { filter = helpers.isRampSuitableFor738, heading_deg = gate_heading, radius_m = gate_radius }
            )
            if end_ramp then
                comp._autoEndRampKey = U.ramp_key(end_ramp)
            end
        end
        if not end_ramp then
            end_ramp = helpers.getNearestRamp(icao, ramp_ref_lat, ramp_ref_lon, { filter = helpers.isRampSuitableFor738, data = data })
            if end_ramp then
                comp._autoEndRampKey = U.ramp_key(end_ramp)
            end
        end
        if end_ramp and U.is_valid_latlon(end_ramp.lat, end_ramp.lon) then
            end_lat = end_ramp.lat
            end_lon = end_ramp.lon
        end
    end
    if mode == 1 and (not comp._drawFreehand) and (not user_selected_end) and (not comp._manualRouteActive)
        and data and aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon) then
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
                    local gate_heading = yalref and yalref.groundtrackmag and get(yalref.groundtrackmag) or nil
                    local gate_radius = tuning.gateSelectRadius or (C and C.gateSelectRadius) or 120
                    nearest_ramp, nearest_ramp_dist = U.select_best_ramp_for_aircraft(
                        data,
                        aircraft,
                        { filter = helpers.isRampSuitableFor738, heading_deg = gate_heading, radius_m = gate_radius }
                    )
                    if nearest_ramp_dist == nil and nearest_ramp and U.is_valid_latlon(nearest_ramp.lat, nearest_ramp.lon) then
                        nearest_ramp_dist = U.distance_meters_latlon(
                            nearest_ramp.lat,
                            nearest_ramp.lon,
                            aircraft.lat,
                            aircraft.lon
                        )
                    end
                end
                if nearest_ramp and end_ramp and U.is_valid_latlon(end_ramp.lat, end_ramp.lon) then
                    local cand_key = U.ramp_key(nearest_ramp)
                    local planned_key = U.ramp_key(end_ramp)
                    if cand_key ~= planned_key then
                        local d_cand = nearest_ramp_dist
                        local d_plan = U.distance_meters_latlon(
                            end_ramp.lat,
                            end_ramp.lon,
                            aircraft.lat,
                            aircraft.lon
                        )
                        local cooldown_ok = ((not comp._autoEndRampSwitchTime)
                                or ((now - comp._autoEndRampSwitchTime) >= gate_cooldown))
                            and (not comp._pendingRerouteEvent)
                            and ((not comp._lastRerouteTime)
                                or ((now - comp._lastRerouteTime) >= gate_cooldown))
                        if d_cand and d_plan and cooldown_ok then
                            local gate_radius = (tuning.gateGuidanceRadius or (C and C.gateGuidanceRadius) or 60)
                            local gate_final_locked = (comp._gateGuidanceActive == true)
                                or (comp._gateFinalTurnPending == true)
                                or (comp._gateFinalTurnUntil and now and now <= comp._gateFinalTurnUntil)
                                or (d_plan <= gate_radius)
                            local route_tail_ok = false
                            if comp._route and comp._route.path and #comp._route.path > 2
                                and comp._route.data == data
                                and aircraft.east ~= nil and aircraft.north ~= nil then
                                local seg_idx = U.find_nearest_segment(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
                                if seg_idx then
                                    route_tail_ok = seg_idx >= math.max(1, #comp._route.path - 2)
                                end
                            end
                            local gate_switch_plan_max = ((tuning.gateGuidanceRadius or (C and C.gateGuidanceRadius) or 60) * 2)
                            local switch_context_ok = route_tail_ok or (d_plan <= gate_switch_plan_max)
                            local close_enough = d_cand <= gate_dist
                            local clearly_closer = (d_plan - d_cand >= gate_delta)
                                or (d_cand <= (d_plan * gate_ratio))
                            local moving_switch_ok = (gs < math.max(gate_speed * 4, 12))
                            local should_switch = (not gate_final_locked) and switch_context_ok and ((close_enough and clearly_closer)
                                or (moving_switch_ok and (d_plan - d_cand >= (gate_delta * 1.5)))
                            )
                            if should_switch then
                                comp._autoEndRampKey = cand_key
                                comp._autoEndRampSwitchTime = now
                                end_ramp = nearest_ramp
                                end_lat = end_ramp.lat
                                end_lon = end_ramp.lon
                                set_reroute_override_from_aircraft(comp, data, aircraft, true)
                                comp._rerouteOverrideHoldUntil = now + math.max(gate_cooldown, ((C and C.rerouteCooldown) or 6))
                                comp._routeStartAnchor = nil
                                comp._route = nil
                                comp._routeErr = nil
                                comp._routeLabels = nil
                                comp._routeLabelStats = nil
                                comp._lastEndKey = nil
                                comp._lastStartKey = nil
                                comp._pendingRerouteEvent = true
                                comp._lastGuidanceNodeId = nil
                                comp._lastGuidanceLabel = nil
                                comp._lastGuidanceTime = nil
                                comp._sCurveSkipNodeId = nil
                                U.clear_visual_guidance(comp, "end-ramp-switch")
                                comp._visualGuidanceQueue = {}
                                comp._gateGuidanceLastDir = nil
                                comp._gateGuidanceLastAction = nil
                                comp._gateGuidanceLastTime = nil
                                comp._gateGuidanceStop = false
                                comp._gateFinalTurnUntil = nil
                                comp._gateFinalTurnKey = nil
                                comp._gateFinalTurnPending = false
                                U.reset_gate_callouts(comp, cand_key)
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

    if mode == 1 and landing_profile and end_ramp and U.is_valid_latlon(end_ramp.lat, end_ramp.lon) then
        local pref_east = end_ramp.east
        local pref_north = end_ramp.north
        if (pref_east == nil or pref_north == nil) and U.is_valid_latlon(end_ramp.lat, end_ramp.lon) then
            pref_east, pref_north = U.latlon_to_local(end_ramp.lat, end_ramp.lon)
        end
        if pref_east ~= nil and pref_north ~= nil
            and landing_profile.threshold and landing_profile.threshold.east ~= nil and landing_profile.threshold.north ~= nil
            and landing_profile.axis then
            local dx = pref_east - landing_profile.threshold.east
            local dy = pref_north - landing_profile.threshold.north
            local cross = dx * landing_profile.axis.y - dy * landing_profile.axis.x
            if math.abs(cross) > 1 then
                local pref_side = (cross >= 0) and 1 or -1
                local exit_id, backtrack = U.select_runway_exit_node(data, landing_profile, pref_side, airborne)
                if exit_id and (exit_id ~= arr_exit_id or backtrack ~= backtrack_required) then
                    arr_exit_id = exit_id
                    backtrack_required = backtrack
                    comp._lastArrExitLogKey = nil
                    if backtrack_required then
                        if U.is_valid_latlon(runway_lat, runway_lon) then
                            start_lat = runway_lat
                            start_lon = runway_lon
                        elseif touchdown and touchdown.east and touchdown.north then
                            local tlat, tlon = local_to_latlon(touchdown.east, touchdown.north)
                            if U.is_valid_latlon(tlat, tlon) then
                                start_lat = tlat
                                start_lon = tlon
                            end
                        end
                    elseif exit_id and data.nodes and data.nodes[exit_id] then
                        local exit_node = data.nodes[exit_id]
                        if U.is_valid_latlon(exit_node.lat, exit_node.lon) then
                            start_lat = exit_node.lat
                            start_lon = exit_node.lon
                        end
                    end
                end
            end
        end
    end
    local arr_exit_along = nil
    if mode == 1 then
        arr_exit_id, arr_exit_along, backtrack_required, start_lat, start_lon =
            choose_or_keep_arrival_exit(
                comp,
                landing_profile,
                data,
                arr_exit_id,
                backtrack_required,
                aircraft,
                comp._arrOffRunway,
                start_lat,
                start_lon,
                log_taxi
            )
    end
    if mode == 1 then
        comp._arrProfile = landing_profile
        comp._arrBacktrackRequired = backtrack_required
        if comp._arrOffRunwayHandled and comp._arrOffRunway == false
            and (not comp._arrExitLockedId) and comp._arrExitId then
            comp._arrExitLockedId = comp._arrExitId
            comp._arrExitLockedAlong = comp._arrExitAlong
            comp._arrExitLockReleasedLogged = nil
        elseif comp._arrOffRunway and comp._arrExitLockedId then
            if not comp._arrExitLockReleasedLogged then
                log_taxi("TaxiRoute: ARR exit lock released off-runway")
                comp._arrExitLockReleasedLogged = true
            end
            comp._arrExitLockedId = nil
            comp._arrExitLockedAlong = nil
        end
        if comp._arrExitId ~= arr_exit_id then
            comp._arrExitId = arr_exit_id
            comp._arrRunwayExitAnnounced = false
            comp._arrRunwayCrossWarned = nil
        end
        if arr_exit_id then
            if arr_exit_along ~= nil then
                comp._arrExitAlong = arr_exit_along
            end
        else
            comp._arrExitAlong = nil
        end
    else
        comp._arrProfile = nil
        comp._arrBacktrackRequired = nil
        comp._arrExitLockedId = nil
        comp._arrExitLockedAlong = nil
        comp._arrExitLockReleasedLogged = nil
        comp._arrExitId = nil
        comp._arrExitAlong = nil
        comp._arrRunwayExitAnnounced = false
        comp._arrRunwayCrossWarned = nil
        comp._offrouteDivergenceCount = 0
    end
    if mode == 1 and (not comp._drawFreehand)
        and (not U.is_valid_latlon(end_lat, end_lon)) and U.is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
        end_lat = ramp_ref_lat
        end_lon = ramp_ref_lon
    end

    local start_ramp = nil
    local start_is_aircraft = false
    if mode == 0 and aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon) then
        start_is_aircraft = true
        local gate_heading = nil
        if yal and yal.localpositionpsi then
            gate_heading = get(yal.localpositionpsi)
        end
        if type(gate_heading) ~= "number" then
            gate_heading = aircraft.heading
        end
        start_ramp = choose_departure_start_ramp(comp, data, icao, aircraft, gate_heading)
    end

    if mode == 0 then
        if start_ramp and not comp._startRampLabel then
            comp._startRampLabel = start_ramp
        end
    else
        comp._startRampLabel = nil
        comp._startRampKey = nil
        comp._startRampRejectKey = nil
        comp._startRampChoiceKey = nil
        comp._startRampChoiceSource = nil
    end

    comp._startRamp = start_ramp
    comp._startIsAircraft = (start_is_aircraft and not start_ramp) or false
    comp._endRamp = end_ramp

    local override_snap_max_m = 1000
    local function snap_override(lat, lon)
        if not data or not U.is_valid_latlon(lat, lon) then
            return nil, "invalid"
        end
        local east, north = U.latlon_to_local(lat, lon)
        if east == nil or north == nil then
            return nil, "no-local"
        end
        local proj = U.find_nearest_edge_projection(data, east, north, { disallow_runway_edges = false })
        if not proj or not proj.d2 then
            return nil, "no-proj"
        end
        local dist = math.sqrt(proj.d2)
        if dist > override_snap_max_m then
            return nil, "too-far", dist
        end
        local wlat, wlon = local_to_latlon(proj.proj_east, proj.proj_north)
        if not U.is_valid_latlon(wlat, wlon) then
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
    if mode == 0 and data and U.is_valid_latlon(runway_lat, runway_lon) then
        local re, rn = U.latlon_to_local(runway_lat, runway_lon)
        local max_candidates = 40
        local zoom = comp.zoom or 1
        if zoom >= 2.0 then
            max_candidates = 200
        elseif zoom >= 1.5 then
            max_candidates = 80
        end
        local candidates = collect_runway_exit_candidates(data, re, rn, max_candidates)
        local cand_count = (candidates and #candidates) or 0
        if cand_count > 0 then
            comp._depEntryCandidates = candidates
            comp._depEntryLabels = {}
            for _, cand in ipairs(candidates) do
                if cand.id then
                    comp._depEntryLabels[cand.id] = U.find_runway_entry_label(data, cand.id)
                end
            end
        end
        if log_taxi then
            local src = (data.entry and data.entry.source) or "?"
            local key = tostring(icao) .. "|" .. tostring(comp._runwayName or "") .. "|" .. tostring(src)
                .. "|" .. tostring(max_candidates) .. "|" .. tostring(cand_count)
            if comp._lastDepEntriesLogKey ~= key then
                comp._lastDepEntriesLogKey = key
                log_taxi(
                    "TaxiDepEntries: icao=" .. tostring(icao)
                    .. " rwy=" .. tostring(comp._runwayName or "")
                    .. " src=" .. tostring(src)
                    .. " cand=" .. tostring(cand_count)
                    .. " max=" .. tostring(max_candidates)
                )
            end
        end
        if cand_count == 0 and data.entry and data.entry.source == "addon" then
            if get_taxi_source_mode(comp, icao) == "addon" then
                if helpers and helpers.logInfoTS then
                    helpers.logInfoTS(
                        "TaxiDepEntries: keep addon (manual) cand=0 icao="
                        .. tostring(icao) .. " rwy=" .. tostring(comp._runwayName or "")
                    )
                end
                comp._taxiGlobalPending = comp._taxiGlobalPending or {}
                comp._taxiGlobalPending[icao] = nil
                comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
                comp._taxiSourceByIcao[icao] = "addon"
            elseif dep_source_lock_active(comp, icao) then
                if helpers and helpers.logInfoTS then
                    helpers.logInfoTS(
                        "TaxiDepEntries: keep addon (lock) cand=0 icao="
                        .. tostring(icao) .. " rwy=" .. tostring(comp._runwayName or "")
                    )
                end
                comp._taxiGlobalPending = comp._taxiGlobalPending or {}
                comp._taxiGlobalPending[icao] = nil
                comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
                comp._taxiSourceByIcao[icao] = "addon"
            else
            local src = data.entry.source
            local fallback_key = tostring(icao) .. "|" .. tostring(comp._runwayName or "") .. "|" .. tostring(src)
            if helpers and helpers.isGlobalAptIndexReady and helpers.isGlobalAptIndexReady() then
                mark_source_switch_pending(comp, icao, mode, "dep-entry-fallback")
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
                comp._sCurveSkipNodeId = nil
                comp._needsCenter = true
                comp._rerouteOverride = nil
                comp._rerouteOverrideHoldUntil = nil
                comp._depEntryCandidates = nil
                comp._depEntryLabels = nil
                comp._lastDepEntriesLogKey = nil
                U.clear_visual_guidance(comp, "dep-entry-fallback")
                comp._visualGuidanceQueue = {}
                U.set_taxi_ref(nil)
                if helpers and helpers.logInfoTS then
                    helpers.logInfoTS(
                        "TaxiDepEntries: forcing global (cand=0) icao="
                        .. tostring(icao) .. " rwy=" .. tostring(comp._runwayName or "")
                    )
                end
                return
            end
            comp._taxiGlobalPending = comp._taxiGlobalPending or {}
            comp._taxiGlobalPending[icao] = true
            mark_source_switch_pending(comp, icao, mode, "dep-entry-fallback-pending")
            comp._taxiSourceByIcao = comp._taxiSourceByIcao or {}
            comp._taxiSourceByIcao[icao] = "global"
            if helpers and helpers.requestGlobalAptIndex then
                helpers.requestGlobalAptIndex("dep-entry-fallback")
            end
            if helpers and helpers.logInfoTS and comp._lastDepEntriesFallbackKey ~= fallback_key then
                comp._lastDepEntriesFallbackKey = fallback_key
                helpers.logInfoTS(
                    "TaxiDepEntries: global pending (cand=0) icao="
                    .. tostring(icao) .. " rwy=" .. tostring(comp._runwayName or "")
                )
            end
            end
        end
    end

    if (not in_edit) and comp._rerouteOverride and U.is_valid_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) then
        start_lat = comp._rerouteOverride.lat
        start_lon = comp._rerouteOverride.lon
    end

    local base_start_lat = start_lat
    local base_start_lon = start_lon
    local base_end_lat = end_lat
    local base_end_lon = end_lon
    local start_vis_lat = start_lat
    local start_vis_lon = start_lon
    local end_vis_lat = end_lat
    local end_vis_lon = end_lon

    local yalref = comp.yal or _G.yal
    local onGround = yalref and yalref.airgroundsensor and (get(yalref.airgroundsensor) == def.ON)

    local start_override = comp._editStartOverride
    local has_start_override = false
    if start_override and start_override.mode == mode and U.is_valid_latlon(start_override.lat, start_override.lon) then
        if not start_override.icao or start_override.icao == "" then
            start_override.icao = icao
        end
        has_start_override = (start_override.icao == icao)
    end
    if has_start_override then
        start_lat = start_override.lat
        start_lon = start_override.lon
        start_vis_lat = start_override.lat
        start_vis_lon = start_override.lon
    end
    if has_start_override and data and (not comp._drawFreehand) then
        local snapped, reason, dist = snap_override(start_override.lat, start_override.lon)
        if not snapped and reason == "too-far" then
            if onGround then
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
                start_vis_lat = start_lat
                start_vis_lon = start_lon
            else
                local key = tostring(icao) .. "|" .. tostring(mode) .. "|start"
                if comp._lastOffNetworkStartKey ~= key then
                    comp._lastOffNetworkStartKey = key
                    log_taxi(
                        string.format(
                            "TaxiEdit: keep start override off-network (air) dist=%.1f",
                            dist or -1
                        )
                    )
                end
            end
        elseif snapped then
            if in_edit then
                local snap_key = string.format(
                    "%s|%s|%.6f|%.6f",
                    tostring(icao),
                    tostring(mode),
                    tonumber(snapped.lat or 0),
                    tonumber(snapped.lon or 0)
                )
                if comp._lastSnapStartKey ~= snap_key then
                    comp._lastSnapStartKey = snap_key
                    log_taxi(
                        string.format(
                            "TaxiEdit: snap start override dist=%.1f",
                            snapped.dist or 0
                        )
                    )
                end
                start_lat = snapped.lat
                start_lon = snapped.lon
            else
                comp._lastSnapStartKey = nil
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
    else
        comp._lastSnapStartKey = nil
    end
    local end_override = comp._editEndOverride
    local has_end_override = false
    if end_override and end_override.mode == mode and U.is_valid_latlon(end_override.lat, end_override.lon) then
        if not end_override.icao or end_override.icao == "" then
            end_override.icao = icao
        end
        has_end_override = (end_override.icao == icao)
    end
    if has_end_override then
        end_lat = end_override.lat
        end_lon = end_override.lon
        end_vis_lat = end_override.lat
        end_vis_lon = end_override.lon
    end
    if has_end_override and data and (not comp._drawFreehand) then
        local snapped, reason, dist = snap_override(end_override.lat, end_override.lon)
        if not snapped and reason == "too-far" then
            if onGround then
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
                end_vis_lat = end_lat
                end_vis_lon = end_lon
            else
                local key = tostring(icao) .. "|" .. tostring(mode) .. "|end"
                if comp._lastOffNetworkEndKey ~= key then
                    comp._lastOffNetworkEndKey = key
                    log_taxi(
                        string.format(
                            "TaxiEdit: keep end override off-network (air) dist=%.1f",
                            dist or -1
                        )
                    )
                end
            end
        elseif snapped then
            if in_edit then
                local snap_key = string.format(
                    "%s|%s|%.6f|%.6f",
                    tostring(icao),
                    tostring(mode),
                    tonumber(snapped.lat or 0),
                    tonumber(snapped.lon or 0)
                )
                if comp._lastSnapEndKey ~= snap_key then
                    comp._lastSnapEndKey = snap_key
                    log_taxi(
                        string.format(
                            "TaxiEdit: snap end override dist=%.1f",
                            snapped.dist or 0
                        )
                    )
                end
                end_lat = snapped.lat
                end_lon = snapped.lon
            else
                comp._lastSnapEndKey = nil
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
    else
        comp._lastSnapEndKey = nil
    end
    local auto_dep_entry_allowed = true
    if mode == 0 and hasRunwayName and data and data.runway_nodes and U.is_valid_latlon(end_lat, end_lon) then
        local dep_probe_id = U.nearest_non_runway_node(data, end_lat, end_lon)
        if dep_probe_id then
            auto_dep_entry_allowed = false
        end
    end
    if mode == 0 and hasRunwayName and (not allow_runway_route)
        and (not dep_holdshort_id)
        and (not has_end_override) and (not manual_active)
        and (not comp._drawFreehand) and aircraft
        and (comp._selectedDepEntryManual ~= true)
        and auto_dep_entry_allowed
        and maybe_reselect_dep_entry(
            comp,
            data,
            aircraft,
            (comp._depEntryReselectPending == true) or (comp._rerouteOverride ~= nil),
            log_taxi
        ) then
        if data and data.nodes and comp._selectedDepEntryId and data.nodes[comp._selectedDepEntryId]
            and U.is_valid_latlon(data.nodes[comp._selectedDepEntryId].lat, data.nodes[comp._selectedDepEntryId].lon) then
            end_lat = data.nodes[comp._selectedDepEntryId].lat
            end_lon = data.nodes[comp._selectedDepEntryId].lon
            if not has_end_override then
                end_vis_lat = end_lat
                end_vis_lon = end_lon
                base_end_lat = end_lat
                base_end_lon = end_lon
            end
        end
    end
    if mode == 0 and dep_holdshort_id
        and comp._runwayName and comp._runwayName ~= ""
        and comp._selectedDepEntryId
        and (comp._selectedDepEntryManual ~= true) then
        log_taxi(
            string.format(
                "TaxiRoute: dep entry auto-clear id=%s holdshort=%s",
                tostring(comp._selectedDepEntryId),
                tostring(dep_holdshort_id)
            )
        )
        comp._selectedDepEntryId = nil
        comp._selectedDepEntryManual = nil
    end
    comp._depEntryReselectPending = nil

    local start_node_id, start_node_dist = U.nearest_node_info(data, start_lat, start_lon, false)
    local start_non_runway_node_id = nil
    local start_non_runway_node_dist = nil
    if mode == 0 and start_is_aircraft and data and data.runway_nodes then
        start_non_runway_node_id, start_non_runway_node_dist = U.nearest_non_runway_node(data, start_lat, start_lon)
    end
    local driftMeters = (mode == 1 and C.arrRerouteDriftMeters) or C.rerouteDriftMeters
    if mode == 1 and arrival_grace_active(comp, now)
        and onGround and aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon)
        and (not has_start_override) and (not in_edit) and (not manual_active)
        and start_node_dist and start_node_dist > C.arrStartNodeMaxMeters then
        start_lat = aircraft.lat
        start_lon = aircraft.lon
        if not has_start_override then
            start_vis_lat = start_lat
            start_vis_lon = start_lon
        end
        start_node_id, start_node_dist = U.nearest_node_info(data, start_lat, start_lon, false)
        comp._rerouteOverride = nil
        comp._rerouteOverrideHoldUntil = nil
        log_taxi(
            string.format(
                "TaxiRoute: arr grace start->aircraft dist=%.1f",
                start_node_dist or -1
            )
        )
    end
    if mode == 1 and allow_runway_route and comp._arrOffRunway == false and start_node_id and start_node_dist and data and data.runway_nodes then
        if comp._arrRunwayStartNodeLatched
            and comp._arrRunwayStartNodeIcao == icao
            and comp._arrRunwayStartNodeRunway == (comp._runwayName or "")
            and data.nodes and data.nodes[comp._arrRunwayStartNodeLatched] then
            start_node_id = comp._arrRunwayStartNodeLatched
            start_node_dist = 0
        elseif not data.runway_nodes[start_node_id] then
            local sx, sy = U.latlon_to_local(start_lat, start_lon)
            if sx and sy then
                local rwy_id = U.find_nearest_runway_node(data, sx, sy)
                local rwy_dist = nil
                if rwy_id and data.nodes and data.nodes[rwy_id] then
                    local rn = data.nodes[rwy_id]
                    if rn.east and rn.north then
                        local dx = rn.east - sx
                        local dy = rn.north - sy
                        rwy_dist = math.sqrt(dx * dx + dy * dy)
                    end
                end
                if rwy_id and rwy_dist and rwy_dist <= driftMeters then
                    if comp._arrRunwayStartNodeLatched ~= rwy_id then
                        log_taxi(
                            string.format(
                                "TaxiRoute: on-runway start node swap dist=%.1f rwy_dist=%.1f",
                                start_node_dist or -1,
                                rwy_dist or -1
                            )
                        )
                    end
                    comp._arrRunwayStartNodeLatched = rwy_id
                    comp._arrRunwayStartNodeIcao = icao
                    comp._arrRunwayStartNodeRunway = comp._runwayName or ""
                    start_node_id = rwy_id
                    start_node_dist = rwy_dist
                elseif rwy_id and rwy_dist then
                    if comp._lastOnRunwayReanchorId ~= rwy_id then
                        comp._lastOnRunwayReanchorId = rwy_id
                        log_taxi(
                            string.format(
                                "TaxiRoute: on-runway start node reanchor dist=%.1f rwy_dist=%.1f",
                                start_node_dist or -1,
                                rwy_dist or -1
                            )
                        )
                    end
                    comp._arrRunwayStartNodeLatched = rwy_id
                    comp._arrRunwayStartNodeIcao = icao
                    comp._arrRunwayStartNodeRunway = comp._runwayName or ""
                    start_node_id = rwy_id
                    start_node_dist = rwy_dist
                elseif start_node_dist > driftMeters then
                    log_taxi(
                        string.format(
                            "TaxiRoute: on-runway start node drop dist=%.1f",
                            start_node_dist or -1
                        )
                    )
                    start_node_id = nil
                    start_node_dist = nil
                end
            end
        elseif start_node_id then
            comp._arrRunwayStartNodeLatched = start_node_id
            comp._arrRunwayStartNodeIcao = icao
            comp._arrRunwayStartNodeRunway = comp._runwayName or ""
        end
    end
    if mode == 1 and (not allow_runway_route) and start_node_dist and start_node_dist > driftMeters then
        if onGround and (not has_start_override) and (not in_edit) and (not manual_active) then
            if comp._arrOffRunway ~= false then
                if aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon)
                    and set_reroute_override_from_aircraft(comp, data, aircraft, true) then
                    if comp._rerouteOverride and U.is_valid_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) then
                        start_lat = comp._rerouteOverride.lat
                        start_lon = comp._rerouteOverride.lon
                        if not has_start_override then
                            start_vis_lat = start_lat
                            start_vis_lon = start_lon
                        end
                        start_node_id, start_node_dist = U.nearest_node_info(data, start_lat, start_lon, false)
                    end
                end
                if not start_node_dist or start_node_dist > driftMeters then
                    if not comp._arrStartClearLogAt or (now - comp._arrStartClearLogAt) >= 3 then
                        log_taxi(
                            string.format(
                                "TaxiRoute: clear start node dist=%.1f",
                                start_node_dist or -1
                            )
                        )
                        comp._arrStartClearLogAt = now
                    end
                    start_node_id = nil
                    start_node_dist = nil
                else
                    comp._arrStartClearLogAt = nil
                    log_taxi(
                        string.format(
                            "TaxiRoute: arr start reanchor dist=%.1f",
                            start_node_dist or -1
                        )
                    )
                end
            end
        end
    end
    local end_node_id, end_node_dist = U.nearest_node_info(data, end_lat, end_lon, false)
    if mode == 0 and data and data.runway_nodes then
        dep_end_node_id, dep_end_node_dist = U.nearest_non_runway_node(data, end_lat, end_lon)
    end
    if comp._rerouteOverride and start_node_id and end_node_id and start_node_id == end_node_id then
        local kept = false
        if comp._route and (not comp._routeErr) and comp._route.data == data and comp._route.path and #comp._route.path > 1 then
            local seg_idx = nil
            if aircraft and aircraft.east ~= nil and aircraft.north ~= nil then
                seg_idx = U.find_nearest_segment(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
            end
            comp._rerouteOverride = nil
            comp._rerouteOverrideHoldUntil = nil
            comp._routeCollapseHold = true
            if seg_idx then
                reset_guidance_tracking(comp, false)
                comp._autoTaxiActiveRoute = comp._route
                comp._autoTaxiActiveSegIdx = seg_idx
                comp._autoTaxiLastSegIdx = seg_idx
                comp._autoTaxiRunwaySegIdx = nil
                comp._guidanceRoute = comp._route
                comp._guidanceActiveSegIdx = seg_idx
                comp._guidanceMonotonicSegIdx = seg_idx
                comp._guidanceForceInitial = true
                log_taxi(
                    string.format(
                        "TaxiRoute: reroute override collapsed start=end id=%s keep-route seg=%s dist=%.1f",
                        tostring(start_node_id),
                        tostring(seg_idx),
                        start_node_dist or -1
                    )
                )
            else
                log_taxi(
                    string.format(
                        "TaxiRoute: reroute override collapsed start=end id=%s keep-route dist=%.1f",
                        tostring(start_node_id),
                        start_node_dist or -1
                    )
                )
            end
            comp._lastRerouteTime = now
            kept = true
        end
        if not kept then
            log_taxi(
                string.format(
                    "TaxiRoute: reroute override collapsed start=end id=%s dist=%.1f",
                    tostring(start_node_id),
                    start_node_dist or -1
                )
            )
            comp._rerouteOverride = nil
            comp._rerouteOverrideHoldUntil = nil
            if aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon) then
                start_lat = aircraft.lat
                start_lon = aircraft.lon
                if not has_start_override then
                    start_vis_lat = start_lat
                    start_vis_lon = start_lon
                end
                start_node_id, start_node_dist = U.nearest_node_info(data, start_lat, start_lon, false)
                if mode == 0 and start_is_aircraft and data and data.runway_nodes then
                    start_non_runway_node_id, start_non_runway_node_dist = U.nearest_non_runway_node(data, start_lat, start_lon)
                end
            end
            if mode == 0 then
                comp._depEntryReselectPending = true
            end
        end
    end
    if mode == 1 and arr_exit_id and (not has_start_override) and (not comp._arrOffRunwayHandled)
        and start_node_dist and start_node_dist > C.arrStartNodeMaxMeters
        and arrival_grace_active(comp, now)
        and data and data.nodes and data.nodes[arr_exit_id] then
        local exit_node = data.nodes[arr_exit_id]
        if exit_node and U.is_valid_latlon(exit_node.lat, exit_node.lon) then
            start_lat = exit_node.lat
            start_lon = exit_node.lon
            start_node_id = arr_exit_id
            start_node_dist = 0
            comp._rerouteOverride = nil
            comp._rerouteOverrideHoldUntil = nil
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
        and ((not U.is_valid_latlon(start_lat, start_lon)) or (not U.is_valid_latlon(end_lat, end_lon))) then
        comp._route = nil
        comp._routeErr = "no-arrival-runway"
        comp._routeExtraSegments = nil
        comp._editTailSegments = nil
        comp._lastStartKey = nil
        comp._lastEndKey = nil
        log_taxi("TaxiRoute: abort no-arrival-runway")
        return
    end

    if U.is_valid_latlon(runway_lat, runway_lon) then
        if mode == 1 then
            local offRunway = nil
                if landing_profile and aircraft then
                    offRunway = not is_on_runway_profile(landing_profile, aircraft, 60, 5)
                elseif comp.yal and comp.yal.aircraftonrwy then
                    offRunway = not comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
                end
            if offRunway == false and not allow_runway_route and not backtrack_required then
                comp._route = nil
                comp._routeErr = "on-runway"
                comp._routeExtraSegments = nil
                comp._editTailSegments = nil
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
        comp._editTailSegments = nil
        comp._lastStartKey = nil
        comp._lastEndKey = nil
        log_taxi("TaxiDraw: abort draw-route-empty")
        return
    end

    local route_waypoints = comp._routeWaypoints
    if route_waypoints and #route_waypoints > 0 and (not comp._manualRouteActive) then
        route_waypoints = nil
    end
    if route_waypoints and #route_waypoints > 0 then
        local drop_first = waypoint_matches_override(route_waypoints[1], comp._editStartOverride)
        local drop_last = waypoint_matches_override(route_waypoints[#route_waypoints], comp._editEndOverride)
        if comp._drawFreehand then
            drop_first = false
            drop_last = false
        end
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
    if freehand_active and route_waypoints and #route_waypoints > 0 then
        local first = route_waypoints[1]
        local last = route_waypoints[#route_waypoints]
        if first then
            ensure_waypoint_latlon(first)
            if U.is_valid_latlon(first.lat, first.lon) then
                start_lat = first.lat
                start_lon = first.lon
            end
        end
        if last then
            ensure_waypoint_latlon(last)
            if U.is_valid_latlon(last.lat, last.lon) then
                end_lat = last.lat
                end_lon = last.lon
            end
        end
    end

    local anchor_lat = start_lat
    local anchor_lon = start_lon
    if not in_edit and (not comp._manualRouteActive) then
        if comp._rerouteOverride and U.is_valid_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) then
            anchor_lat = comp._rerouteOverride.lat
            anchor_lon = comp._rerouteOverride.lon
        elseif comp._route and comp._routeStartAnchor
            and U.is_valid_latlon(comp._routeStartAnchor.lat, comp._routeStartAnchor.lon) then
            anchor_lat = comp._routeStartAnchor.lat
            anchor_lon = comp._routeStartAnchor.lon
        end
    end
    local start_key = string.format("%.6f|%.6f", anchor_lat or 0, anchor_lon or 0)
    local end_key = string.format("%.6f|%.6f|%s", end_lat or 0, end_lon or 0, tostring(comp._runwayName or ""))
    local taxi_complete_freeze = (mode == 1 and comp._arrTaxiCompleteFreeze and comp._routeErr == "taxi-complete"
        and (not in_edit) and (not comp._drawRoute) and (not comp._manualRouteActive))
    local recompute_reason = nil
    local suppress_edit_recompute = false
    local manual_end_ramp_hold = manual_end_ramp_retarget_hold_active(comp, now)
    if comp._editDirty and in_edit and (not comp._drawRoute) and (not comp._wpDrag)
        and (not comp._manualRouteActive)
        and (not has_start_override) and (not has_end_override)
        and (not comp._editSuppressedNodes or next(comp._editSuppressedNodes) == nil)
        and (not route_waypoints or #route_waypoints == 0) then
        comp._editDirty = false
        suppress_edit_recompute = true
    end
    if comp._editDirty and (not suppress_edit_recompute) then
        recompute_reason = "edit-dirty"
    elseif comp._route == nil then
        if not taxi_complete_freeze then
            recompute_reason = "route-nil"
        end
    elseif comp._lastStartKey ~= start_key or comp._lastEndKey ~= end_key then
        if comp._manualRouteActive and (not in_edit) and (not comp._drawRoute) and comp._route then
            comp._lastStartKey = start_key
            comp._lastEndKey = end_key
        elseif mode == 1 and manual_end_ramp_hold and comp._route and (not in_edit) and (not comp._drawRoute) then
            comp._lastStartKey = start_key
            comp._lastEndKey = end_key
        elseif not (
            mode == 0
            and dep_terminal_sequence_locked(comp)
            and comp._route
            and (not in_edit)
            and (not comp._drawRoute)
        ) then
            recompute_reason = "start-end-change"
        else
            comp._lastStartKey = start_key
            comp._lastEndKey = end_key
        end
    end
    if comp._manualRouteLock and (not in_edit) and (not comp._drawRoute) then
        if comp._route then
            comp._editDirty = false
            recompute_reason = nil
        end
    end
    if mode == 0 and dep_terminal_sequence_locked(comp) and comp._route and (not in_edit) and (not comp._drawRoute) then
        comp._editDirty = false
        recompute_reason = nil
    end
    if comp._routeCollapseHold and comp._route and (not comp._routeErr) then
        comp._lastStartKey = start_key
        comp._lastEndKey = end_key
        comp._editDirty = false
        recompute_reason = nil
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
                    "TaxiRoute: recompute reason=%s edit=%s draw=%s wps=%d manual=%s lock=%s",
                    tostring(recompute_reason),
                    tostring(in_edit),
                    tostring(comp._drawRoute),
                    (comp._routeWaypoints and #comp._routeWaypoints) or 0,
                    tostring(comp._manualRouteActive),
                    tostring(comp._manualRouteLock)
                )
            )
        end
    end
    local route_refresh_needed = comp._editDirty
        or comp._lastStartKey ~= start_key
        or comp._lastEndKey ~= end_key
        or comp._route == nil
    if comp._routeCollapseHold and comp._route and (not comp._routeErr) then
        route_refresh_needed = false
        comp._routeCollapseHold = nil
    end
    if taxi_complete_freeze then
        route_refresh_needed = comp._editDirty
    end
    if mode == 0 and dep_terminal_sequence_locked(comp) and comp._route and (not in_edit) and (not comp._drawRoute) then
        route_refresh_needed = comp._editDirty
    end
    if route_refresh_needed then
        comp._lastStartKey = start_key
        comp._lastEndKey = end_key
        if data then
            U.clear_temp_route_overlay(comp, data)
        end
        comp._depTurnaroundApplied = false
        comp._initialGuidanceDone = false
        comp._initialMoveAnchor = nil
        comp._guidanceMoveAnchor = nil
        comp._runwayCrossWarnedKey = nil
        comp._depEntryIssuedAt = nil
        if (canRoute or freehand_active)
            and (freehand_active or (U.is_valid_latlon(start_lat, start_lon) and U.is_valid_latlon(end_lat, end_lon))) then
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
                    wtl_e, wtl_n = U.latlon_to_local(aircraft.lat, aircraft.lon)
                end
                local rwy_entry_lat = nil
                local rwy_entry_lon = nil
                local rwy_entry_dist_m = nil
                local rwy1, rwy2, rwy_side = nil, nil, nil
                if data and comp._runwayName and comp._runwayName ~= "" then
                    local rwy, side = U.find_runway_entry(data, comp._runwayName, runway_lat, runway_lon)
                    if rwy then
                        rwy1 = rwy.rwy1
                        rwy2 = rwy.rwy2
                        rwy_side = side
                        rwy_entry_lat = (side == 1) and rwy.lat1 or rwy.lat2
                        rwy_entry_lon = (side == 1) and rwy.lon1 or rwy.lon2
                        if U.is_valid_latlon(runway_lat, runway_lon) and U.is_valid_latlon(rwy_entry_lat, rwy_entry_lon) then
                            rwy_entry_dist_m = U.distance_meters_latlon(runway_lat, runway_lon, rwy_entry_lat, rwy_entry_lon)
                        end
                    end
                end
                local dep_hs_dist = nil
                if dep_holdshort_id and data and data.nodes then
                    local hs = data.nodes[dep_holdshort_id]
                    if hs and U.is_valid_latlon(hs.lat, hs.lon) and U.is_valid_latlon(runway_lat, runway_lon) then
                        dep_hs_dist = U.distance_meters_latlon(runway_lat, runway_lon, hs.lat, hs.lon)
                    end
                end
                U.log_full_route_state(comp, data, mode, icao, {
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
            local proj_disallow_runway_edges = nil
            local proj_start_id = nil
            local proj_end_id = nil
            local proj_waypoint_ids = nil
            local function compute_projection(opts)
                local disallow = opts and opts.disallow_runway_edges or nil
                if proj_data and proj_disallow_runway_edges == disallow then
                    return
                end
                proj_data = nil
                proj_start_id = nil
                proj_end_id = nil
                proj_waypoint_ids = nil
                proj_disallow_runway_edges = disallow
                local start_proj = nil
                local end_proj = nil
                local waypoint_projs = nil
                if not opts.start_node_id and U.is_valid_latlon(start_lat, start_lon) then
                    local sx, sy = U.latlon_to_local(start_lat, start_lon)
                    if sx and sy then
                        if start_ramp and start_ramp.east and start_ramp.north then
                            if start_ramp.heading ~= nil then
                                start_proj = U.find_heading_edge_projection(
                                    data,
                                    start_ramp.east,
                                    start_ramp.north,
                                    start_ramp.heading,
                                    { disallow_runway_edges = opts.disallow_runway_edges, radius_m = 150, angle_deg = 60 }
                                )
                            end
                            if not start_proj then
                                start_proj = U.find_preferred_edge_projection(
                                    data,
                                    start_ramp.east,
                                    start_ramp.north,
                                    { disallow_runway_edges = opts.disallow_runway_edges }
                                )
                            end
                        end
                        if not start_proj then
                            start_proj = U.find_nearest_edge_projection(data, sx, sy, { disallow_runway_edges = opts.disallow_runway_edges })
                        end
                    end
                end
                if not opts.end_node_id and U.is_valid_latlon(end_lat, end_lon) then
                    local ex, ey = U.latlon_to_local(end_lat, end_lon)
                    if ex and ey then
                        if end_ramp and end_ramp.east and end_ramp.north then
                            if end_ramp.heading ~= nil then
                                end_proj = U.find_heading_edge_projection(
                                    data,
                                    end_ramp.east,
                                    end_ramp.north,
                                    end_ramp.heading,
                                    { disallow_runway_edges = opts.disallow_runway_edges, radius_m = 150, angle_deg = 60 }
                                )
                            end
                            if not end_proj then
                                end_proj = U.find_preferred_edge_projection(
                                    data,
                                    end_ramp.east,
                                    end_ramp.north,
                                    { disallow_runway_edges = opts.disallow_runway_edges }
                                )
                            end
                        end
                        if not end_proj then
                            end_proj = U.find_nearest_edge_projection(data, ex, ey, { disallow_runway_edges = opts.disallow_runway_edges })
                        end
                    end
                end
                if route_waypoints and #route_waypoints > 0 then
                    waypoint_projs = {}
                    for _, wp in ipairs(route_waypoints) do
                        if U.is_valid_latlon(wp.lat, wp.lon) then
                            local wx, wy = U.latlon_to_local(wp.lat, wp.lon)
                            if wx and wy then
                                waypoint_projs[#waypoint_projs + 1] = U.find_nearest_edge_projection(
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
                        U.build_projected_data(data, start_proj, end_proj, waypoint_projs)
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

            local function ramp_node_ok(ramp)
                local node_id = ramp_route_node_id(ramp)
                if not node_id then
                    return false
                end
                return node_has_non_runway_edge(node_id)
            end

            local function set_start_ramp_fallback(opts)
                local node_id = ramp_route_node_id(start_ramp)
                if node_id and node_has_non_runway_edge(node_id) then
                    opts._fallback_start_node_id = node_id
                    opts.allow_far_ramp = true
                end
            end

            local function set_end_ramp_fallback(opts)
                local node_id = ramp_route_node_id(end_ramp)
                if user_selected_end and node_id and node_has_non_runway_edge(node_id) then
                    opts._fallback_end_node_id = node_id
                    opts.allow_far_ramp = true
                end
            end

            local function set_dep_end_node(opts)
                if not opts or mode ~= 0 or has_end_override then
                    return
                end
                if allow_runway_route and dep_runway_end_id and data.nodes and data.nodes[dep_runway_end_id] then
                    opts.end_node_id = dep_runway_end_id
                    return
                end
                if comp._selectedDepEntryManual == true
                    and comp._selectedDepEntryId
                    and data.nodes and data.nodes[comp._selectedDepEntryId] then
                    opts.end_node_id = comp._selectedDepEntryId
                    return
                end
                if dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                    opts.end_node_id = dep_holdshort_id
                    return
                end
                if dep_end_node_id and data.nodes and data.nodes[dep_end_node_id] then
                    opts.end_node_id = dep_end_node_id
                    return
                end
                if comp._selectedDepEntryId and data.nodes and data.nodes[comp._selectedDepEntryId] then
                    opts.end_node_id = comp._selectedDepEntryId
                end
            end

            local opts = {}
            if mode == 0 then
                opts.avoid_runway_end = not allow_runway_route
                opts.runway_penalty = allow_runway_route and 1 or 500
                opts.disallow_runway_edges = not allow_runway_route
                opts.avoid_runway_nodes = not allow_runway_route
                if not has_start_override and ramp_node_ok(start_ramp) then
                    opts.start_node_id = ramp_route_node_id(start_ramp)
                    opts.allow_far_ramp = true
                    log_taxi(
                        string.format(
                            "TaxiRoute: start from ramp node id=%s label=%s%s",
                            tostring(ramp_route_node_id(start_ramp)),
                            tostring(short_ramp_label(start_ramp)),
                            ramp_debug_suffix(start_ramp)
                        )
                    )
                end
                set_dep_end_node(opts)
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
                opts.disallow_runway_edges = (not allow_runway_route) and (not backtrack_required)
                opts.runway_penalty = allow_runway_route and 1 or 500
                if not has_end_override and ramp_node_ok(end_ramp) then
                    opts.end_node_id = ramp_route_node_id(end_ramp)
                    opts.allow_far_ramp = true
                    log_taxi(
                        string.format(
                            "TaxiRoute: end at ramp node id=%s label=%s%s",
                            tostring(ramp_route_node_id(end_ramp)),
                            tostring(short_ramp_label(end_ramp)),
                            ramp_debug_suffix(end_ramp)
                        )
                    )
                end
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
            local route, rerr = nil, nil
            if comp._drawFreehand and route_waypoints and #route_waypoints > 0 then
                if #route_waypoints < 2 then
                    route = nil
                    rerr = nil
                else
                    route, rerr = build_freehand_route(route_waypoints, data)
                end
            else
                route, rerr = U.route_with_waypoints(
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
            if (not route) and rerr == "no-path" and comp._rerouteOverride and opts and opts.disallow_runway_edges then
                opts.disallow_runway_edges = false
                opts.avoid_runway_nodes = false
                if opts.runway_penalty == nil then
                    opts.runway_penalty = 500
                end
                compute_projection(opts)
                apply_projection(opts)
                route, rerr = U.route_with_waypoints(
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
            if (not route) and rerr == "no-path" and mode == 1 and opts and opts.disallow_runway_edges then
                opts = U.copy_opts(opts) or {}
                opts.disallow_runway_edges = false
                if (not has_start_override) and (not backtrack_required) then
                    opts.runway_penalty = 500
                end
                set_end_ramp_fallback(opts)
                apply_projection(opts)
                route, rerr = U.route_with_waypoints(
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
            if (not route) and rerr == "no-path" and mode == 0 then
                if hasRunwayName
                    and (not comp._selectedDepEntryId)
                    and (not has_end_override)
                    and (not manual_active)
                    and dep_entry_candidate_id
                    and data and data.nodes and data.nodes[dep_entry_candidate_id]
                    and (not start_node_id or dep_entry_candidate_id ~= start_node_id) then
                    comp._selectedDepEntryId = dep_entry_candidate_id
                    comp._selectedDepEntryManual = false
                    local dn = data.nodes[dep_entry_candidate_id]
                    if dn and U.is_valid_latlon(dn.lat, dn.lon) then
                        end_lat = dn.lat
                        end_lon = dn.lon
                        end_node_id = dep_entry_candidate_id
                        end_node_dist = 0
                    end
                    log_taxi(
                        string.format(
                            "TaxiRoute: dep entry fallback id=%s dist=%.1f",
                            tostring(dep_entry_candidate_id),
                            dep_entry_candidate_dist or -1
                        )
                    )
                end
                opts = {
                    ignore_oneway = true,
                    allow_far_ramp = true,
                    disallow_runway_edges = true,
                    avoid_runway_nodes = true
                }
                set_dep_end_node(opts)
                set_start_ramp_fallback(opts)
                apply_projection(opts)
                route, rerr = U.route_with_waypoints(
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
            if (not route) and rerr == "no-path" and mode == 0 then
                opts = {
                    ignore_oneway = true,
                    allow_far_ramp = true,
                    disallow_runway_edges = false,
                    avoid_runway_nodes = false,
                    runway_penalty = 500
                }
                set_dep_end_node(opts)
                set_start_ramp_fallback(opts)
                apply_projection(opts)
                route, rerr = U.route_with_waypoints(
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
            if (not route) and rerr == "no-path" and mode == 0 and U.is_valid_latlon(start_lat, start_lon) then
                local sx, sy = U.latlon_to_local(start_lat, start_lon)
                local candidates = U.collect_nearest_nodes(data, sx, sy, 18)
                if #candidates > 0 then
                    opts = {
                        ignore_oneway = true,
                        allow_far_ramp = true,
                        disallow_runway_edges = true,
                        avoid_runway_nodes = true
                    }
                    set_dep_end_node(opts)
                    set_start_ramp_fallback(opts)
                    apply_projection(opts)
                    local alt_route = U.try_route_from_candidates(
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
            if (not route) and rerr == "no-path" and mode == 0 then
                opts = {
                    ignore_oneway = true,
                    allow_far_ramp = true,
                    disallow_runway_edges = true,
                    avoid_runway_nodes = false
                }
                set_dep_end_node(opts)
                set_start_ramp_fallback(opts)
                apply_projection(opts)
                route, rerr = U.route_with_waypoints(
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
                set_dep_end_node(opts)
                set_start_ramp_fallback(opts)
                apply_projection(opts)
                route, rerr = U.route_with_waypoints(
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
            if (not route) and rerr == "no-path" and mode == 0 and U.is_valid_latlon(end_lat, end_lon) then
                local ex, ey = U.latlon_to_local(end_lat, end_lon)
                local candidates = U.collect_nearest_nodes(data, ex, ey, 18)
                if #candidates > 0 then
                    opts = {
                        ignore_oneway = true,
                        allow_far_ramp = true,
                        disallow_runway_edges = true,
                        avoid_runway_nodes = true
                    }
                    set_dep_end_node(opts)
                    set_start_ramp_fallback(opts)
                    apply_projection(opts)
                    local alt_route = U.try_route_to_candidates(
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
            if (not route) and rerr == "no-path" and mode == 1 then
                opts = {}
                if (not has_start_override) and (not backtrack_required) then
                    opts.avoid_runway_start = true
                end
                set_end_ramp_fallback(opts)
                apply_projection(opts)
                route, rerr = U.route_with_waypoints(
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
                route, rerr = U.route_with_waypoints(
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
                route, rerr = U.route_with_waypoints(
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
                route, rerr = U.route_with_waypoints(
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
                route, rerr = U.route_with_waypoints(
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
                route, rerr = U.route_with_waypoints(
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
                if not (ref and ref.east and ref.north) and U.is_valid_latlon(runway_lat, runway_lon) then
                    local re, rn = U.latlon_to_local(runway_lat, runway_lon)
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
                        local alt_route, alt_err, alt_lat, alt_lon = U.try_route_from_candidates(
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
            if (not route) and rerr == "no-path" and mode == 1 and U.is_valid_latlon(end_lat, end_lon) and (not user_selected_end) then
                local ee, en = U.latlon_to_local(end_lat, end_lon)
                local candidates = U.collect_nearest_nodes(data, ee, en, 18)
                if #candidates > 0 then
                    opts = { allow_far_ramp = true, ignore_oneway = true }
                    if (not has_start_override) and (not backtrack_required) then
                        opts.runway_penalty = 500
                    end
                    apply_projection(opts)
                    local alt_route, alt_err, alt_lat, alt_lon = U.try_route_to_candidates(
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
            if (not route) and rerr == "no-path" and mode == 1 and U.is_valid_latlon(end_lat, end_lon) and user_selected_end then
                local ee, en = U.latlon_to_local(end_lat, end_lon)
                local candidates = U.collect_nearest_nodes(data, ee, en, 18)
                if #candidates > 0 then
                    opts = { allow_far_ramp = true, ignore_oneway = true }
                    if not backtrack_required then
                        opts.runway_penalty = 500
                    end
                    apply_projection(opts)
                    local alt_route, alt_err, alt_lat, alt_lon = U.try_route_to_candidates(
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
            if (not route) and rerr == "no-path" and mode == 1
                and start_node_id and end_node_id and start_node_id == end_node_id
                and (not comp._manualRouteActive)
                and comp._route and (not comp._routeErr) and comp._route.data == data
                and comp._route.path and #comp._route.path > 1 then
                route = comp._route
                rerr = nil
                local keep_key = "arr:" .. tostring(start_node_id)
                if comp._lastStartEndKeepKey ~= keep_key then
                    comp._lastStartEndKeepKey = keep_key
                    log_taxi("TaxiRoute: keep last-good (arr start=end) id=" .. tostring(start_node_id))
                end
            end
            if (not route) and rerr == "no-path" and mode == 1
                and (not in_edit) and (not comp._drawRoute)
                and comp._route and (not comp._routeErr) and comp._route.data == data
                and comp._route.path and #comp._route.path > 1 then
                local gate_keep_limit = (((comp._tuning and comp._tuning.gateGuidanceRadius) or (C and C.gateGuidanceRadius) or 60) * 2)
                local keep_gate = comp._gateGuidanceActive == true
                if (not keep_gate) and comp._gateActivationDist and comp._gateActivationDist <= gate_keep_limit then
                    keep_gate = true
                end
                if keep_gate then
                    route = comp._route
                    rerr = nil
                    log_taxi("TaxiRoute: keep last-good (arr-gate)")
                end
            end
            if route and route.path and #route.path < 2 then
                route = nil
                rerr = "no-path"
            end
            if route and mode == 1 and landing_profile and data and arr_exit_id
                and (not comp._drawFreehand) and (not comp._manualRouteActive)
                and (not backtrack_required)
                and (not manual_end_ramp_retarget_hold_active(comp, now)) then
                local angle = route_first_taxi_angle(route, data, landing_profile)
                if angle and angle > 120 then
                    local ref = landing_profile.touchdown
                    if not (ref and ref.east and ref.north) and landing_profile.threshold then
                        ref = landing_profile.threshold
                    end
                    if (not ref or ref.east == nil or ref.north == nil) and U.is_valid_latlon(start_lat, start_lon) then
                        local re, rn = U.latlon_to_local(start_lat, start_lon)
                        ref = (re and rn) and { east = re, north = rn } or nil
                    end
                    if ref and ref.east and ref.north then
                        local candidates = collect_runway_exit_candidates(data, ref.east, ref.north, 12)
                        local best_route = nil
                        local best_exit = nil
                        local best_angle = nil
                        local current_route_dist = nil
                        if aircraft and aircraft.east and aircraft.north then
                            current_route_dist = U.distance_to_route(data, route.path, aircraft.east, aircraft.north)
                        end
                        for _, cand in ipairs(candidates) do
                            local cid = cand.id
                            if cid and cid ~= arr_exit_id and data.nodes and data.nodes[cid] then
                                local alt_opts = U.copy_opts(opts) or {}
                                alt_opts.start_node_id = cid
                                alt_opts.allow_far_ramp = true
                                apply_projection(alt_opts)
                                local alt_route, alt_err = U.route_with_waypoints(
                                    icao,
                                    start_lat,
                                    start_lon,
                                    end_lat,
                                    end_lon,
                                    alt_opts,
                                    proj_waypoint_ids,
                                    route_waypoints
                                )
                                if alt_route and alt_route.path and #alt_route.path >= 2 then
                                    local alt_route_dist = nil
                                    if aircraft and aircraft.east and aircraft.north then
                                        alt_route_dist = U.distance_to_route(data, alt_route.path, aircraft.east, aircraft.north)
                                    end
                                    local alt_angle = route_first_taxi_angle(alt_route, data, landing_profile)
                                    if alt_angle and alt_angle <= 120 then
                                        local accept_alt = true
                                        if alt_route_dist then
                                            local dist_limit = math.max(180, driftMeters * 2.5)
                                            if current_route_dist then
                                                dist_limit = math.max(dist_limit, current_route_dist + 25)
                                            end
                                            if alt_route_dist > dist_limit then
                                                accept_alt = false
                                                log_taxi(
                                                    "TaxiRoute: ARR exit angle reject exit=" .. tostring(cid)
                                                        .. " dist=" .. string.format("%.1f", alt_route_dist)
                                                        .. " limit=" .. string.format("%.1f", dist_limit)
                                                )
                                            end
                                        end
                                        if accept_alt and ((not best_angle) or alt_angle < best_angle) then
                                            best_angle = alt_angle
                                            best_route = alt_route
                                            best_exit = cid
                                            rerr = alt_err
                                        end
                                    end
                                end
                            end
                        end
                        if best_route and best_exit then
                            route = best_route
                            arr_exit_id = best_exit
                            start_node_id = best_exit
                            start_node_dist = 0
                            local exit_node = data.nodes and data.nodes[best_exit] or nil
                            if exit_node and U.is_valid_latlon(exit_node.lat, exit_node.lon) then
                                start_lat = exit_node.lat
                                start_lon = exit_node.lon
                            end
                            log_taxi(
                                "TaxiRoute: ARR exit angle reroute exit=" .. tostring(best_exit)
                                    .. " angle=" .. string.format("%.1f", best_angle or -1)
                            )
                        else
                            log_taxi(
                                "TaxiRoute: ARR exit angle steep angle=" .. string.format("%.1f", angle)
                            )
                        end
                    end
                end
            end
            if route and mode == 1 and onGroundSensor and aircraft
                and (not in_edit) and (not comp._drawRoute) and (not comp._manualRouteActive) then
                local arr_validity = evaluate_arrival_route_validity(
                    route,
                    data,
                    aircraft,
                    landing_profile,
                    arr_exit_id,
                    driftMeters,
                    comp._arrOffRunway
                )
                if not arr_validity.valid then
                    local kept_prev = false
                    local prev_validity = nil
                    if comp._route and (not comp._routeErr) and comp._route.data == data
                        and comp._route.path and #comp._route.path > 1 then
                        prev_validity = evaluate_arrival_route_validity(
                            comp._route,
                            data,
                            aircraft,
                            landing_profile,
                            comp._arrExitId,
                            driftMeters,
                            comp._arrOffRunway
                        )
                        if prev_validity.valid
                            and prev_validity.route_dist
                            and arr_validity.route_dist
                            and prev_validity.route_dist + 25 < arr_validity.route_dist then
                            route = comp._route
                            rerr = nil
                            arr_validity = prev_validity
                            kept_prev = true
                            log_taxi(
                                string.format(
                                    "TaxiRoute: keep last-good (arr validity) reason=%s dist=%.1f prev=%.1f",
                                    tostring(arr_validity.reason or "?"),
                                    arr_validity.route_dist or -1,
                                    prev_validity.route_dist or -1
                                )
                            )
                        end
                    end
                    if not kept_prev then
                        log_taxi(
                            string.format(
                                "TaxiRoute: reject invalid arrival route reason=%s route=%.1f start=%.1f exit=%.1f",
                                tostring(arr_validity.reason or "?"),
                                arr_validity.route_dist or -1,
                                arr_validity.start_gap or -1,
                                arr_validity.exit_gap or -1
                            )
                        )
                        if set_reroute_override_from_aircraft(comp, data, aircraft, true) then
                            comp._routeStartAnchor = nil
                        end
                        if (not arrival_grace_active(comp, now)) or arr_validity.severe then
                            comp._pendingRerouteEvent = true
                        end
                        comp._lastRerouteTime = now
                        comp._lastStartKey = nil
                        route = nil
                        rerr = nil
                    end
                end
                comp._arrRouteValidity = arr_validity
            elseif mode ~= 1 then
                comp._arrRouteValidity = nil
            else
                comp._arrRouteValidity = nil
            end
            if (not route) and rerr == "no-path" and mode == 0
                and start_node_id and end_node_id and start_node_id == end_node_id
                and (not comp._manualRouteActive)
                and comp._route and (not comp._routeErr) and comp._route.data == data
                and comp._route.path and #comp._route.path > 1 then
                route = comp._route
                rerr = nil
                local keep_key = tostring(start_node_id)
                if comp._lastStartEndKeepKey ~= keep_key then
                    comp._lastStartEndKeepKey = keep_key
                    log_taxi("TaxiRoute: keep last-good (start=end) id=" .. tostring(start_node_id))
                end
            end
            if (not route) and rerr == "no-path" and mode == 0
                and comp._depRunwayEntryLock
                and comp._route and (not comp._routeErr) and comp._route.data == data
                and comp._route.path and #comp._route.path > 1 then
                route = comp._route
                rerr = nil
                log_taxi("TaxiRoute: keep last-good (dep-entry-lock)")
            end
            if (not route) and (not in_edit) and (not comp._drawRoute)
                and comp._route and (not comp._routeErr) and comp._route.data == data
                and comp._route.path and aircraft and aircraft.east and aircraft.north then
                local keep_dist = U.distance_to_route(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
                if keep_dist and keep_dist <= driftMeters then
                    route = comp._route
                    rerr = nil
                    log_taxi(
                        string.format(
                            "TaxiRoute: keep last-good dist=%.1f drift=%.1f",
                            keep_dist or -1,
                            driftMeters or -1
                        )
                    )
                end
            end
            comp._route = route
            comp._lastRouteComputeTime = now
            comp._routeErr = rerr
            comp._routeLabels = nil
            comp._routeLabelStats = nil
            if in_edit and route then
                if comp._editDirty then
                    log_taxi("TaxiEdit: clean")
                end
                comp._editDirty = false
            end
            if recompute_reason == "edit-dirty" and comp._editDirty then
                -- Avoid edit-dirty recompute loops when routing cannot resolve.
                comp._editDirty = false
            end
            local backtrack_applied = false
            comp._routeExtraSegments = nil
            if (not comp._drawFreehand) and (not comp._manualRouteActive)
                and route and route.path and data then
                local profile = nil
                local runway_label = nil
                if comp._runwayName and comp._runwayName ~= "" then
                    profile = U.compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
                    runway_label = U.normalize_runway_name(comp._runwayName)
                else
                    if mode == 0 then
                        profile = dep_profile or U.compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
                        runway_label = comp._depProfileLabel or ""
                    else
                        profile = landing_profile or U.compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
                    end
                    if (not runway_label or runway_label == "") and U.is_valid_latlon(runway_lat, runway_lon) then
                        local rwy, side = U.find_nearest_runway_entry_by_latlon(data, runway_lat, runway_lon)
                        runway_label = U.runway_end_label(rwy, side)
                        if runway_label == "" then
                            runway_label = U.runway_pair_label(rwy)
                        end
                    end
                end
                if profile then
                    local backtrack_node = nil
                    local backtrack_target = nil
                    if mode == 1 and backtrack_required and (not comp._arrOffRunwayHandled) then
                        backtrack_node = arr_exit_id or route.path[1]
                        if aircraft and is_on_runway_profile(profile, aircraft, 60, 5) then
                            backtrack_target = { east = aircraft.east, north = aircraft.north }
                        else
                            backtrack_target = profile.touchdown or profile.threshold
                        end
                    elseif mode == 0 and not allow_runway_route then
                        backtrack_node = comp._selectedDepEntryId or dep_holdshort_id or dep_end_node_id or route.end_id or route.path[#route.path]
                        backtrack_target = profile.threshold
                    end
                    if backtrack_node then
                        local segments = U.build_runway_backtrack_segments(data, profile, backtrack_node, backtrack_target)
                        if segments and #segments > 0 then
                            if apply_backtrack_segments_to_route(comp, route, data, backtrack_node, segments, runway_label) then
                                backtrack_applied = true
                            else
                                comp._routeExtraSegments = segments
                            end
                        end
                    end
                end
            end
            if mode == 0 and dep_backtrack_required and route and data then
                local profile = dep_profile or U.compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
                if profile then
                    local runway_label = (comp._runwayName and comp._runwayName ~= "" and U.normalize_runway_name(comp._runwayName)) or (comp._depProfileLabel or "")
                    if runway_label == "" and U.is_valid_latlon(runway_lat, runway_lon) then
                        local rwy, side = U.find_nearest_runway_entry_by_latlon(data, runway_lat, runway_lon)
                        runway_label = U.runway_end_label(rwy, side)
                        if runway_label == "" then
                            runway_label = U.runway_pair_label(rwy)
                        end
                    end
                    if apply_dep_turnaround_stub(comp, route, data, profile, runway_label) then
                        log_taxi("TaxiRoute: dep turnaround stub applied")
                    end
                end
            end
            if route then
                comp._routeLabels = U.build_route_labels(route.data, route.path)
                comp._routeLabelStats = U.compute_route_label_stats(route.data, route.path)
            end
            comp._autoTaxiPath = nil
            comp._autoTaxiPathRoute = nil
            if route and U.is_valid_latlon(start_lat, start_lon) then
                if not in_edit then
                    comp._routeStartAnchor = { lat = start_lat, lon = start_lon }
                    if comp._rerouteOverride then
                        local keep_override = comp._rerouteOverrideHoldUntil
                            and now
                            and (now <= comp._rerouteOverrideHoldUntil)
                        if not keep_override then
                            comp._rerouteOverride = nil
                            comp._rerouteOverrideHoldUntil = nil
                        end
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
                local same_path = (comp._lastRoutePathKey == path_key)
                local fwd_key = path_key
                if aircraft and aircraft.east and aircraft.north then
                    local seg_idx = U.find_nearest_segment(route.data, path, aircraft.east, aircraft.north)
                    if seg_idx and seg_idx >= 1 and seg_idx < #path_parts then
                        fwd_key = table.concat(path_parts, ",", seg_idx + 1, #path_parts)
                    end
                end
                if comp._lastRoutePathKey ~= path_key then
                    comp._lastRoutePathKey = path_key
                    -- New route geometry: reset guidance/autotaxi segment anchors so
                    -- callouts restart from the current aircraft position.
                    comp._guidanceRoute = route
                    comp._guidanceActiveSegIdx = nil
                    comp._guidanceMonotonicSegIdx = nil
                    comp._guidanceMoveAnchor = nil
                    comp._guidanceForceInitial = true
                    comp._lastGuidanceSegment = nil
                    comp._lastGuidanceAction = nil
                    comp._lastGuidanceVoiceText = nil
                    comp._lastGuidanceVoiceTime = nil
                    comp._guidanceInstruction = nil
                    comp._guidanceInstructionIssuedSeg = nil
                    comp._guidanceInstructionCommitSeg = nil
                    comp._guidanceInstructionCommitLabel = nil
                    U.clear_visual_guidance(comp, "route-recompute")
                    comp._visualGuidanceQueue = {}
                    comp._autoTaxiActiveRoute = route
                    comp._autoTaxiActiveSegIdx = nil
                    comp._autoTaxiLastSegIdx = nil
                    comp._autoTaxiRunwaySegIdx = nil
                    comp._autoTaxiTargetSegIdx = nil
                    comp._autoTaxiTargetAction = nil
                    comp._autoTaxiTargetLabel = nil
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
                    local labels = comp._routeLabels or U.build_route_labels(route.data, route.path)
                    if labels and #labels > 0 then
                        helpers.logInfoTS(
                            "TaxiLabels: " .. tostring(icao) .. " " .. tostring(comp._runwayName or "") .. " " .. table.concat(labels, " ")
                        )
                    else
                        helpers.logInfoTS("TaxiLabels: " .. tostring(icao) .. " " .. tostring(comp._runwayName or "") .. " <none>")
                    end
                end
                if same_path then
                    if comp._autoTaxiActiveSegIdx or comp._autoTaxiLastSegIdx then
                        comp._autoTaxiActiveRoute = route
                    end
                    if comp._guidanceActiveSegIdx or comp._guidanceMonotonicSegIdx then
                        comp._guidanceRoute = route
                    end
                end
                if backtrack_applied then
                    helpers.logInfoTS(
                        "TaxiRoute: backtrack applied mode=" .. tostring(mode) ..
                        " runway=" .. tostring(comp._runwayName or "") ..
                        " node=" .. tostring((mode == 1 and arr_exit_id) or comp._selectedDepEntryId or dep_holdshort_id or dep_end_node_id or "")
                    )
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
                helpers.logInfoTS(
                    string.format(
                        "TaxiRoute: fail-details err=%s start=%s end=%s allow_runway=%s disallow_runway_edges=%s ignore_oneway=%s avoid_runway_nodes=%s runway_penalty=%s",
                        tostring(rerr),
                        tostring((opts and opts.start_node_id) or start_node_id),
                        tostring((opts and opts.end_node_id) or end_node_id),
                        tostring(allow_runway_route),
                        tostring(opts and opts.disallow_runway_edges),
                        tostring(opts and opts.ignore_oneway),
                        tostring(opts and opts.avoid_runway_nodes),
                        tostring(opts and opts.runway_penalty)
                    )
                )
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
            if mode == 1 and route and route.path and route.data and route.data ~= nil then
                local exit_id = infer_arrival_exit_from_route(route, route.data)
                if exit_id and exit_id ~= comp._arrExitId then
                    comp._arrExitId = exit_id
                    if comp._arrProfile then
                        comp._arrExitAlong = runway_exit_along(comp._arrProfile, route.data, exit_id)
                    end
                    local on_runway_now = false
                    if comp._arrProfile and aircraft then
                        on_runway_now = is_on_runway_profile(comp._arrProfile, aircraft, 60, 5)
                    elseif comp.yal and comp.yal.aircraftonrwy then
                        on_runway_now = not comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
                    end
                    if not on_runway_now or (not comp._arrRunwayExitAnnounced) then
                        comp._arrRunwayExitAnnounced = false
                    end
                    comp._arrRunwayCrossWarned = nil
                end
            end
            if route and route.data and route.data.route_source == "freehand" then
                comp._freehandLabelCache = nil
            end
            comp._lastGuidanceNodeId = nil
            comp._lastGuidanceLabel = nil
            comp._lastGuidanceTime = nil
            comp._sCurveSkipNodeId = nil
        else
            helpers.logInfoTS(
                "TaxiDiag: route-skip icao=" .. tostring(icao) ..
                " mode=" .. tostring(mode) ..
                " canRoute=" .. tostring(canRoute) ..
                " start_valid=" .. tostring(U.is_valid_latlon(start_lat, start_lon)) ..
                " end_valid=" .. tostring(U.is_valid_latlon(end_lat, end_lon))
            )
            helpers.logInfoTS(
                string.format(
                    "TaxiRoute: skip-details start=%s end=%s allow_runway=%s disallow_runway_edges=%s ignore_oneway=%s avoid_runway_nodes=%s runway_penalty=%s",
                    tostring(start_node_id),
                    tostring(end_node_id),
                    tostring(allow_runway_route),
                    tostring((mode == 0 and (not allow_runway_route)) or (mode == 1 and (not allow_runway_route) and (not backtrack_required))),
                    tostring(false),
                    tostring(mode == 0 and (not allow_runway_route) or nil),
                    tostring((allow_runway_route and 1) or 500)
                )
            )
            comp._route = nil
            comp._routeErr = canRoute and "route-endpoints-missing" or "no-routes"
            comp._routeLabels = nil
            comp._autoTaxiPath = nil
            comp._autoTaxiPathRoute = nil
            log_taxi("TaxiRoute: skip err=" .. tostring(comp._routeErr))
        end
    end

    comp._depThresholdState = nil
    comp._depThresholdReached = false
    if mode == 0 and dep_profile and aircraft and aircraft.east ~= nil and aircraft.north ~= nil then
        local state = compute_dep_threshold_state(comp, dep_profile, runway_lat, runway_lon, aircraft)
        comp._depThresholdState = state
        comp._depThresholdReached = state and state.reached or false
        local callout_key = tostring(icao) .. "|" .. tostring(comp._runwayName or "")
        if comp._depThresholdCalloutKey ~= callout_key then
            U.reset_dep_threshold_callouts(comp, callout_key)
        end
        local threshold_ahead = nil
        if state then
            threshold_ahead = state.along_to_threshold or state.along
        end
        if state and threshold_ahead and threshold_ahead < 0
            and state.perp and state.corridor and state.perp <= state.corridor
            and (not comp._depThresholdReached) and (not comp._depThresholdLatched) then
            U.maybe_dep_threshold_voice_callouts(comp, state, U.is_auto_taxi_guidance_enabled())
        else
            comp._depThresholdCalloutStage = 0
            if state and state.dist and state.dist <= 400
                and (not comp._depThresholdReached) and (not comp._depThresholdLatched) then
                local blocked = (state.heading_ok == false)
                    or (state.perp and state.corridor and state.perp > state.corridor)
                if blocked then
                    local last_block = comp._depThresholdBlockedLog or 0
                    if (now - last_block) >= 5 then
                        comp._depThresholdBlockedLog = now
                        helpers.logInfoTS(
                            string.format(
                                "TaxiDepThreshold: blocked dist=%.1f along=%.1f perp=%.1f hdgDiff=%s src=%s",
                                state.dist or -1,
                                state.along or -1,
                                state.perp or -1,
                                state.heading_diff and string.format("%.1f", state.heading_diff) or "nil",
                                tostring(state.heading_src or "?")
                            )
                        )
                    end
                end
            end
        end
        if comp._depThresholdReached then
            comp._depThresholdLatched = true
        end
        if comp._lastDepThresholdReached ~= comp._depThresholdReached then
            comp._lastDepThresholdReached = comp._depThresholdReached
            helpers.logInfoTS(
                string.format(
                    "TaxiDepThreshold: reached=%s dist=%.1f along=%.1f perp=%.1f hdgDiff=%s hdgOk=%s src=%s corridor=%.1f",
                    tostring(comp._depThresholdReached),
                    state and state.dist or -1,
                    state and state.along or -1,
                    state and state.perp or -1,
                    state and state.heading_diff and string.format("%.1f", state.heading_diff) or "nil",
                    tostring(state and state.heading_ok),
                    tostring(state and state.heading_src or "?"),
                    state and state.corridor or -1
                )
            )
        end
    else
        comp._lastDepThresholdReached = nil
        comp._depThresholdLatched = false
        comp._depThresholdCalloutKey = nil
        comp._depThresholdCalloutStage = 0
    end

    if mode == 0 and not comp._depThresholdLatched then
        local yal = comp.yal or _G.yal
        local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
        local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
        local onRunway = false
        if onGround and comp.yal and comp.yal.aircraftonrwy then
            onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, C.depThresholdHeadingLimit)
        end
        if onGround and onRunway and gs < 5 and (not comp._depThresholdReached) then
            if not comp._depOnRunwayLatchSince then
                comp._depOnRunwayLatchSince = now
            end
            if (now - comp._depOnRunwayLatchSince) >= C.depTakeoffLatchHoldSec then
                comp._depThresholdLatched = true
                comp._depOnRunwayLatchSince = nil
                helpers.logInfoTS(
                    string.format("TaxiDepThreshold: latched=on-runway-aligned gs=%.1f", gs)
                )
            end
        else
            comp._depOnRunwayLatchSince = nil
        end
        if onGround and onRunway and gs >= C.depTakeoffLatchSpeed then
            if not comp._takeoffLatchSince then
                comp._takeoffLatchSince = now
            end
            if (now - comp._takeoffLatchSince) >= C.depTakeoffLatchHoldSec then
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
        comp._depOnRunwayLatchSince = nil
    end

    if mode ~= 0 then
        comp._depThresholdLatched = false
        comp._depRunwayEntryLock = false
        comp._depTerminalSequenceLock = false
        clear_pushback_join_hold(comp)
    elseif comp._depThresholdLatched then
        local yal = comp.yal or _G.yal
        local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
        if not onGround then
            comp._depThresholdLatched = false
            comp._depRunwayEntryLock = false
            comp._depTerminalSequenceLock = false
        elseif comp.yal and comp.yal.aircraftonrwy and U.is_valid_latlon(runway_lat, runway_lon) then
            local onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, 20)
            local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
            if (not onRunway) and gs < 5 then
                comp._depThresholdLatched = false
                comp._depTerminalSequenceLock = false
            end
        end
    elseif comp._depRunwayEntryLock then
        local yal = comp.yal or _G.yal
        local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
        if not onGround then
            comp._depRunwayEntryLock = false
            comp._depTerminalSequenceLock = false
        elseif comp.yal and comp.yal.aircraftonrwy and U.is_valid_latlon(runway_lat, runway_lon) then
            local onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, 20)
            local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
            if (not onRunway) and gs < 5 then
                comp._depRunwayEntryLock = false
                comp._depTerminalSequenceLock = false
            end
        end
    end

    if not in_edit then
        if comp._route and aircraft and aircraft.east and aircraft.north then
            local yal = comp.yal or _G.yal
            local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
            local tirespeed = yal and yal.tirespeed and (get(yal.tirespeed) or 0) or 0
            local skip_reroute = false
            if comp._manualRouteActive then
                skip_reroute = true
            end
            if comp._drawFreehand and comp._routeWaypoints and #comp._routeWaypoints > 0 then
                skip_reroute = true
            end
            if mode == 0 and dep_terminal_sequence_locked(comp) then
                skip_reroute = true
            end
            if onGround and tirespeed > 1 and not (mode == 0 and dep_terminal_sequence_locked(comp)) and (not skip_reroute) then
                local lastReroute = comp._lastRerouteTime or 0
                local offRunway = nil
                if mode == 1 and U.is_valid_latlon(runway_lat, runway_lon) then
                    if landing_profile and aircraft then
                        offRunway = not is_on_runway_profile(landing_profile, aircraft, 60, 5)
                    elseif comp.yal and comp.yal.aircraftonrwy then
                        offRunway = not comp.yal.aircraftonrwy(def.ARRIVAL, 40, 20)
                    end
                end
                if mode == 1 and offRunway == false then
                    if landing_profile and comp._arrExitId and data and data.nodes
                        and (now - lastReroute) > C.rerouteCooldown then
                        local along_now = U.compute_along_perp(landing_profile, aircraft)
                        local along_exit = comp._arrExitAlong
                        if along_exit == nil then
                            along_exit = runway_exit_along(landing_profile, data, comp._arrExitId)
                        end
                        if along_now and along_exit and (along_now - along_exit) > driftMeters then
                            comp._arrGroundRecomputePending = nil
                            comp._arrRunwayExitAnnounced = false
                            comp._arrRunwayCrossWarned = nil
                            force_arrival_recompute(
                                comp,
                                data,
                                aircraft,
                                now,
                                string.format("arr-exit-missed along=%.1f exit=%.1f", along_now, along_exit),
                                log_taxi
                            )
                            return
                        end
                    end
                    return
                end
                if mode == 1 and offRunway and not comp._arrOffRunwayHandled and not comp._arrRawRunwayMissing then
                    comp._arrOffRunwayHandled = true
                    comp._arrExitLockedId = comp._arrExitId
                    comp._arrExitLockedAlong = comp._arrExitAlong
                    comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
                    comp._routeStartAnchor = nil
                    if not arrival_grace_active(comp, now) then
                        comp._pendingRerouteEvent = true
                    end
                    comp._lastRerouteTime = now
                    comp._lastStartKey = nil
                    comp._route = nil
                    comp._routeErr = nil
                    comp._routeLabels = nil
                    comp._routeLabelStats = nil
                    log_taxi("TaxiRoute: off-runway reroute latch")
                    log_taxi(
                        string.format(
                            "TaxiRoute: reroute reason=offrunway mode=%s manual=%s",
                            tostring(mode),
                            tostring(comp._manualRouteActive)
                        )
                    )
                    return
                end
                local routeData = comp._route.data
                local prev_dist = comp._lastRouteDist
                local dist = U.distance_to_route(routeData, comp._route.path, aircraft.east, aircraft.north)
                if comp._routeExtraSegments then
                    local extra = U.distance_to_segments(comp._routeExtraSegments, aircraft.east, aircraft.north)
                    if extra and (not dist or extra < dist) then
                        dist = extra
                    end
                end
                comp._lastRouteDist = dist
                local driftMeters = (mode == 1 and C.arrRerouteDriftMeters) or C.rerouteDriftMeters
                local skipReroute = false
                local reroute_seg_idx = nil
                if mode == 0 and dist and comp._route and comp._route.data and comp._route.path and #comp._route.path > 1 then
                    reroute_seg_idx = U.find_nearest_segment(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
                    if pushback_join_hold_active(comp, now, dist, driftMeters, reroute_seg_idx) then
                        skipReroute = true
                        if (not comp._lastPushbackJoinHoldLog) or ((now - comp._lastPushbackJoinHoldLog) >= 3) then
                            comp._lastPushbackJoinHoldLog = now
                            log_taxi(
                                string.format(
                                    "TaxiRoute: reroute hold post-pushback seg=%s dist=%.1f",
                                    tostring(reroute_seg_idx),
                                    dist or -1
                                )
                            )
                        end
                    end
                else
                    clear_pushback_join_hold(comp)
                end
                if mode == 1 then
                    local lastCompute = comp._lastRouteComputeTime or 0
                    if lastCompute > 0 and (now - lastCompute) < 2 then
                        local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
                        if dist and dist <= (driftMeters * 3) and gs < 25 then
                            skipReroute = true
                        end
                    end
                    if manual_end_ramp_hold and dist and dist <= (driftMeters * 3) then
                        skipReroute = true
                    end
                end
                if mode == 0 and dist and dist <= driftMeters and (not skipReroute)
                    and (not comp._depThresholdLatched) and (not comp._depThresholdReached)
                    and (now - lastReroute) > C.rerouteCooldown
                    and (not comp._depSegmentReanchorDone)
                    and comp._route and comp._route.path and #comp._route.path > 6 then
                    local seg_idx = reroute_seg_idx or U.find_nearest_segment(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
                    if seg_idx and seg_idx >= 2 then
                        comp._depSegmentReanchorDone = true
                        set_reroute_override_from_aircraft(comp, data, aircraft, true)
                        comp._routeStartAnchor = nil
                        comp._pendingRerouteEvent = true
                        comp._lastRerouteTime = now
                        comp._lastStartKey = nil
                        comp._route = nil
                        comp._routeErr = nil
                        comp._routeLabels = nil
                        comp._routeLabelStats = nil
                        comp._depEntryReselectPending = true
                        log_taxi(
                            string.format(
                                "TaxiRoute: dep segment reanchor seg=%s dist=%.1f",
                                tostring(seg_idx),
                                dist or -1
                            )
                        )
                        return
                    end
                end
                if mode == 0 and dep_profile and comp._depThresholdState and comp._depThresholdState.heading_diff then
                    local on_dep_runway = is_on_runway_profile(dep_profile, aircraft, 60, 5)
                    local reverse_hdg = 180 - (C.depThresholdHeadingLimit or 25)
                    if on_dep_runway and comp._depThresholdState.heading_diff >= reverse_hdg then
                        skipReroute = true
                        if (not comp._lastBacktrackHoldLog) or ((now - comp._lastBacktrackHoldLog) >= 3) then
                            comp._lastBacktrackHoldLog = now
                            log_taxi(
                                string.format(
                                    "TaxiRoute: offroute hold backtrack dist=%.1f hdgDiff=%.1f",
                                    dist or -1,
                                    comp._depThresholdState.heading_diff or -1
                                )
                            )
                        end
                    end
                end
                if dist and dist > driftMeters and (not skipReroute) and (now - lastReroute) > C.rerouteCooldown then
                    local sustained_offroute = prev_dist and prev_dist > driftMeters
                    local divergence_trigger = false
                    if prev_dist and dist > prev_dist then
                        comp._offrouteDivergenceCount = (comp._offrouteDivergenceCount or 0) + 1
                    else
                        comp._offrouteDivergenceCount = 0
                    end
                    if dist > (driftMeters * 0.7) and (comp._offrouteDivergenceCount or 0) >= 2 then
                        divergence_trigger = true
                    end
                    if (comp._guidanceState == "complete") or sustained_offroute or divergence_trigger then
                        local seg_idx = nil
                        if comp._route and comp._route.data and comp._route.path and #comp._route.path > 1 then
                            seg_idx = U.find_nearest_segment(comp._route.data, comp._route.path, aircraft.east, aircraft.north)
                        end
                        if seg_idx then
                            if comp._guidanceMonotonicSegIdx and comp._guidanceMonotonicSegIdx > seg_idx then
                                seg_idx = comp._guidanceMonotonicSegIdx
                            end
                            reset_guidance_tracking(comp, false)
                            comp._autoTaxiActiveRoute = comp._route
                            comp._autoTaxiActiveSegIdx = seg_idx
                            comp._autoTaxiLastSegIdx = seg_idx
                            comp._autoTaxiRunwaySegIdx = nil
                            comp._guidanceRoute = comp._route
                            comp._guidanceActiveSegIdx = seg_idx
                            comp._guidanceMonotonicSegIdx = seg_idx
                            comp._guidanceForceInitial = true
                            U.clear_visual_guidance(comp, "offroute-reanchor")
                            comp._visualGuidanceQueue = {}
                            log_taxi(
                                string.format(
                                    "TaxiRoute: offroute reanchor seg=%s dist=%.1f",
                                    tostring(seg_idx),
                                    dist or -1
                                )
                            )
                            do
                                local path_len = comp._route and comp._route.path and #comp._route.path or 0
                                if mode == 0 and dep_terminal_sequence_locked(comp) then
                                    comp._lastRerouteTime = now
                                    log_taxi(
                                        string.format(
                                            "TaxiRoute: offroute hold terminal seg=%s dist=%.1f",
                                            tostring(seg_idx),
                                            dist or -1
                                        )
                                    )
                                    return
                                end
                                if mode == 0 and path_len > 1 and seg_idx >= (path_len - 1) then
                                    comp._lastRerouteTime = now
                                    log_taxi(
                                        string.format(
                                            "TaxiRoute: offroute reanchor only (near end) seg=%s dist=%.1f",
                                            tostring(seg_idx),
                                            dist or -1
                                        )
                                    )
                                    return
                                end
                                if mode == 0 and (allow_runway_route or comp._depBacktrackRequired)
                                    and path_len > 2 and seg_idx >= (path_len - 2) then
                                    comp._lastRerouteTime = now
                                    log_taxi(
                                        string.format(
                                            "TaxiRoute: offroute reanchor only (dep runway near end) seg=%s dist=%.1f",
                                            tostring(seg_idx),
                                            dist or -1
                                        )
                                    )
                                    return
                                end
                                if mode == 1 and path_len > 2 and comp._endRamp and seg_idx >= (path_len - 2) then
                                    local arr_validity = comp._arrRouteValidity
                                    local route_plausible = true
                                    if arr_validity then
                                        if arr_validity.valid == false then
                                            route_plausible = false
                                        elseif arr_validity.route_dist
                                            and arr_validity.route_dist > math.max(driftMeters * 2.5, 180) then
                                            route_plausible = false
                                        end
                                    end
                                    if route_plausible then
                                        comp._lastRerouteTime = now
                                        log_taxi(
                                            string.format(
                                                "TaxiRoute: offroute reanchor only (arr near end) seg=%s dist=%.1f",
                                                tostring(seg_idx),
                                                dist or -1
                                            )
                                        )
                                        return
                                    end
                                end
                            end
                        end
                        set_reroute_override_from_aircraft(comp, data, aircraft, (mode == 0 and (not allow_runway_route)))
                        comp._routeStartAnchor = nil
                        if not arrival_grace_active(comp, now) then
                            comp._pendingRerouteEvent = true
                        end
                        comp._lastRerouteTime = now
                        comp._lastStartKey = nil
                        comp._route = nil
                        comp._routeErr = nil
                        comp._routeLabels = nil
                        comp._routeLabelStats = nil
                        if mode == 0 then
                            comp._depEntryReselectPending = true
                        end
                        log_taxi(
                            string.format(
                                "TaxiRoute: reroute reason=offroute dist=%.1f drift=%.1f prev=%.1f div=%s manual=%s",
                                dist or -1,
                                driftMeters or -1,
                                prev_dist or -1,
                                tostring(divergence_trigger),
                                tostring(comp._manualRouteActive)
                            )
                        )
                    end
                else
                    comp._offrouteDivergenceCount = 0
                end
            end
        end

        if comp._route and not comp._routeErr then
            if U.maybe_force_global_for_quality(comp, now, icao, mode, data, helpers, aircraft) then
                U.update_visual_guidance(comp, now, aircraft)
                return
            end
            U.maybe_speak_guidance(comp, now, aircraft)
        end
        if comp.mode == 0 and not comp._depTaxiCompleteAnnounced and comp._runwayName and comp._runwayName ~= "" then
            if comp._routeErr then
                return
            end
            local yal = comp.yal or _G.yal
            local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
            if onGround and comp.yal and comp.yal.aircraftonrwy then
                local onRunway = comp.yal.aircraftonrwy(def.DEPARTURE, 40, C.depThresholdHeadingLimit)
                local nearRunwayEntry = false
                if (not onRunway) and comp._depThresholdState then
                    local st = comp._depThresholdState
                    local gate = (C.depThresholdGateMeters or 45)
                    local hdg_limit = (C.depThresholdHeadingLimit or 25) + 30
                    if st.dist and st.perp and st.corridor and st.heading_diff then
                        nearRunwayEntry = (st.dist <= (gate * 2.0))
                            and (st.perp <= (st.corridor * 2.0))
                            and (st.heading_diff <= hdg_limit)
                    end
                end
                if (not onRunway) and (not nearRunwayEntry) and comp._route and comp._route.path and comp._route.data
                    and comp._route.data.nodes and #comp._route.path >= 3 then
                    local path = comp._route.path
                    local data = comp._route.data
                    local dep_runway = U.normalize_runway_name(comp._runwayName or "")
                    local final_idx = #path - 1
                    for i = final_idx, math.max(1, final_idx - 6), -1 do
                        local node = data.nodes[path[i + 1]]
                        local node_label = tostring(node and node.label or "")
                        local pair = U.normalize_runway_pair_label(node_label)
                        if dep_runway ~= "" and pair ~= "" then
                            local a, b = pair:match("^([^/]+)/([^/]+)$")
                            if a == dep_runway or b == dep_runway then
                                local prev = data.nodes[path[i]]
                                local hold = node
                                if prev and hold and prev.east and prev.north and hold.east and hold.north then
                                    local dist_hold = math.sqrt(distance_sq(aircraft.east, aircraft.north, hold.east, hold.north))
                                    local dist_prev = math.sqrt(distance_sq(aircraft.east, aircraft.north, prev.east, prev.north))
                                    if dist_hold <= math.max(90, (C.depThresholdGateMeters or 45) * 2.5)
                                        and dist_prev <= math.max(120, (C.depThresholdGateMeters or 45) * 3.0) then
                                        nearRunwayEntry = true
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
                if onRunway or nearRunwayEntry then
                    local gs = yal and yal.groundspeed and (get(yal.groundspeed) or 0) or 0
                    local takeoff_roll = gs >= ((C and C.depTakeoffLatchSpeed) or 25)
                        and (comp._depThresholdLatched or comp._depThresholdReached)
                    if not takeoff_roll then
                        if not comp._depRunwayEntryAnnounced then
                            local rwy_phrase = runway_label_voice(comp._runwayName)
                            local entry_text = "Enter departure " .. rwy_phrase
                            local entry_action = "ENTER RWY"
                            local entry_direction = "straight"
                            local entry_label = build_visual_label("runway", U.normalize_runway_name(comp._runwayName))
                            if comp._route and dep_profile and dep_profile.axis and U.dep_entry_turn_from_route then
                                local turn = U.dep_entry_turn_from_route(comp._route, dep_profile, aircraft)
                                if turn == "left" or turn == "right" then
                                    entry_text = "Turn " .. turn .. " on departure " .. rwy_phrase
                                    entry_action = (turn == "left") and "TURN LEFT" or "TURN RIGHT"
                                    entry_direction = turn
                                end
                            end
                            emit_guidance(comp, now, {
                                text = entry_text,
                                direction = entry_direction,
                                action = entry_action,
                                label = entry_label,
                                kind = "runway"
                            }, U.is_auto_taxi_guidance_enabled())
                            comp._depRunwayEntryAnnounced = true
                            comp._depEntryIssuedAt = now
                            comp._depRunwayEntryLock = true
                            comp._depTerminalSequenceLock = true
                        end
                        if comp._depThresholdLatched or comp._depThresholdReached then
                            local entryIssuedAt = comp._depEntryIssuedAt or 0
                            if (not entryIssuedAt) or (not now) or (now - entryIssuedAt) >= 2 then
                                local align_needed = nil
                                if dep_profile and aircraft then
                                    align_needed = compute_dep_threshold_state(comp, dep_profile, runway_lat, runway_lon, aircraft)
                                end
                                if align_needed and align_needed.heading_diff ~= nil
                                    and align_needed.heading_diff > ((comp._tuning and comp._tuning.autoTaxiAlignHeadingDeg)
                                    or (C and C.autoTaxiAlignHeadingDeg) or 8) then
                                    align_needed = true
                                else
                                    align_needed = false
                                end
                                if align_needed then
                                    local last = comp._depAlignLastAt or 0
                                    local cooldown = (C and C.autoTaxiAlignCooldownSec) or 3
                                    if (not now) or (now - last) >= cooldown then
                                        local rwy_phrase = runway_label_voice(comp._runwayName)
                                        emit_guidance(comp, now, {
                                            text = "Align with departure " .. rwy_phrase,
                                            direction = "straight",
                                            action = "ALIGN RWY",
                                            label = build_visual_label("runway", U.normalize_runway_name(comp._runwayName)),
                                            kind = "runway"
                                        }, U.is_auto_taxi_guidance_enabled())
                                        comp._depAlignLastAt = now
                                    end
                                    comp._depAlignPending = true
                                else
                                    local rwy_phrase = runway_label_voice(comp._runwayName)
                                    emit_guidance(comp, now, {
                                        text = "On departure " .. rwy_phrase .. ", taxi complete",
                                        direction = "straight",
                                        action = "TAXI COMPLETE",
                                        label = build_visual_label("runway", U.normalize_runway_name(comp._runwayName)),
                                        kind = "runway",
                                        queue = true
                                    }, U.is_auto_taxi_guidance_enabled())
                                    comp._depTaxiCompleteAnnounced = true
                                    comp._depAlignPending = nil
                                    comp._autoTaxiForceRelease = "taxi-complete"
                                    comp._depRunwayEntryLock = false
                                    comp._depTerminalSequenceLock = false
                                end
                            end
                        end
                    end
                end
            end
        end
        if comp.mode == 1 and not comp._arrTaxiCompleteAnnounced then
            local yalref = comp.yal or _G.yal
            local onGround = yalref and yalref.airgroundsensor and (get(yalref.airgroundsensor) == def.ON)
            local gs = yalref and yalref.groundspeed and (get(yalref.groundspeed) or 0) or 0
            local park = yalref and yalref.parkingbrakepos and get(yalref.parkingbrakepos) or nil
            if onGround and park == def.ON and gs < 1 and aircraft and U.is_valid_latlon(aircraft.lat, aircraft.lon) then
                local on_runway = false
                if comp._arrProfile and aircraft then
                    on_runway = is_on_runway_profile(comp._arrProfile, aircraft, 60, 5)
                end
                if on_runway then
                    if not comp._arrTaxiCompleteRunwaySkip then
                        log_taxi("TaxiRoute: parking brake on runway, skip taxi complete")
                        comp._arrTaxiCompleteRunwaySkip = true
                    end
                else
                    comp._arrTaxiCompleteRunwaySkip = nil
                    local planned_ramp = comp._endRamp
                    local planned_ramp_dist = nil
                    if planned_ramp and U.is_valid_latlon(planned_ramp.lat, planned_ramp.lon) then
                        planned_ramp_dist = U.distance_meters_latlon(
                            planned_ramp.lat,
                            planned_ramp.lon,
                            aircraft.lat,
                            aircraft.lon
                        )
                    end
                    if not nearest_ramp then
                        nearest_ramp = helpers.getNearestRamp(
                            icao,
                            aircraft.lat,
                            aircraft.lon,
                            { filter = helpers.isRampSuitableFor738, data = comp._data }
                        )
                        if nearest_ramp and U.is_valid_latlon(nearest_ramp.lat, nearest_ramp.lon) then
                            nearest_ramp_dist = U.distance_meters_latlon(
                                nearest_ramp.lat,
                                nearest_ramp.lon,
                                aircraft.lat,
                                aircraft.lon
                            )
                        end
                    end
                    local pb_dist = tuning.parkingBrakeCompleteDist or 35
                    local final_gate_dist = U.gate_distance_meters and U.gate_distance_meters(comp, aircraft, comp._route, comp._data) or nil
                    local final_gate_limit = math.max(10, pb_dist * 0.4)
                    local complete_ok = false
                    local complete_ramp = nil
                    if planned_ramp and planned_ramp_dist then
                        if planned_ramp_dist <= pb_dist and (final_gate_dist == nil or final_gate_dist <= final_gate_limit) then
                            complete_ok = true
                            complete_ramp = planned_ramp
                        end
                    elseif nearest_ramp and nearest_ramp_dist and nearest_ramp_dist <= pb_dist
                        and (final_gate_dist == nil or final_gate_dist <= final_gate_limit) then
                        complete_ok = true
                        complete_ramp = nearest_ramp
                    end
                    if complete_ok and complete_ramp then
                        local ramp_label = U.short_ramp_label(complete_ramp)
                        U.clear_visual_guidance(comp, "taxi-complete")
                        comp._visualGuidanceQueue = {}
                        emit_guidance(comp, now, {
                            text = "Taxi complete",
                            direction = "straight",
                            action = "TAXI COMPLETE",
                            label = ramp_label,
                            kind = "ramp"
                        }, U.is_auto_taxi_guidance_enabled())
                        comp._arrTaxiCompleteAnnounced = true
                        comp._arrTaxiCompleteFreeze = true
                        set_guidance_state(comp, "complete", "taxi-complete", log_taxi)
                        comp._route = nil
                        comp._routeErr = "taxi-complete"
                        comp._routeLabels = nil
                        comp._routeLabelStats = nil
                        comp._routeExtraSegments = nil
                        comp._lastStartKey = nil
                        comp._lastEndKey = nil
                        comp._visualGuidanceQueue = {}
                        log_taxi("TaxiRoute: taxi complete parking brake")
                    elseif log_taxi and now then
                        local last_block = comp._arrParkCompleteBlockedLogAt or 0
                        if (now - last_block) >= 5 then
                            comp._arrParkCompleteBlockedLogAt = now
                            log_taxi(
                                string.format(
                                    "TaxiRoute: parking brake complete blocked planned=%.1f nearest=%.1f gate=%.1f gateLimit=%.1f limit=%.1f hasEnd=%s",
                                    planned_ramp_dist or -1,
                                    nearest_ramp_dist or -1,
                                    final_gate_dist or -1,
                                    final_gate_limit or -1,
                                    pb_dist or -1,
                                    tostring(planned_ramp ~= nil)
                                )
                            )
                        end
                    end
                end
            end
        end
        U.update_visual_guidance(comp, now, aircraft)
    end

    comp._editTailSegments = nil
    if comp._route and comp._route.path and (not comp._drawFreehand)
        and (in_edit or has_start_override or has_end_override) then
        local routeData = comp._route.data or comp._data
        if routeData and routeData.nodes then
            local segs = {}
            local first_id = comp._route.path[1]
            local last_id = comp._route.path[#comp._route.path]
            if has_start_override and U.is_valid_latlon(start_vis_lat, start_vis_lon) and first_id then
                local n1 = routeData.nodes[first_id]
                if n1 and n1.east and n1.north then
                    local se, sn = U.latlon_to_local(start_vis_lat, start_vis_lon)
                    if se and sn then
                        local dx = n1.east - se
                        local dy = n1.north - sn
                        if (dx * dx + dy * dy) > 1 then
                            segs[#segs + 1] = {
                                east1 = se,
                                north1 = sn,
                                east2 = n1.east,
                                north2 = n1.north
                            }
                        end
                    end
                end
            end
            if has_end_override and U.is_valid_latlon(end_vis_lat, end_vis_lon) and last_id then
                local n2 = routeData.nodes[last_id]
                if n2 and n2.east and n2.north then
                    local ee, en = U.latlon_to_local(end_vis_lat, end_vis_lon)
                    if ee and en then
                        local dx = n2.east - ee
                        local dy = n2.north - en
                        if (dx * dx + dy * dy) > 1 then
                            segs[#segs + 1] = {
                                east1 = n2.east,
                                north1 = n2.north,
                                east2 = ee,
                                north2 = en
                            }
                        end
                    end
                end
            end
            if #segs > 0 then
                comp._editTailSegments = segs
            end
        end
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
    local sp_lat = (in_edit and start_vis_lat) or start_lat
    local sp_lon = (in_edit and start_vis_lon) or start_lon
    if U.is_valid_latlon(sp_lat, sp_lon) then
        local sx, sy = U.latlon_to_local(sp_lat, sp_lon)
        comp._startPoint = { east = sx, north = sy }
    end
    comp._endPoint = nil
    local ep_lat = (in_edit and end_vis_lat) or end_lat
    local ep_lon = (in_edit and end_vis_lon) or end_lon
    if U.is_valid_latlon(ep_lat, ep_lon) then
        local ex, ey = U.latlon_to_local(ep_lat, ep_lon)
        comp._endPoint = { east = ex, north = ey }
    end

    if in_edit then
        if comp._route and comp._route.path and comp._route.data then
            U.build_edit_handles(comp, start_vis_lat, start_vis_lon, end_vis_lat, end_vis_lon)
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
    if comp._route and comp._route.path and (not in_edit) and (not comp._drawRoute) then
        local rlen = #comp._route.path
        local src = (comp._route.data and comp._route.data.route_source) or "?"
        local auto_key = table.concat({
            tostring(comp._lastIcao or ""),
            tostring(comp._runwayName or ""),
            tostring(rlen),
            tostring(comp._route.start_id or ""),
            tostring(comp._route.end_id or ""),
            tostring(src)
        }, "|")
        if comp._lastAutoRouteLogKey ~= auto_key then
            comp._lastAutoRouteLogKey = auto_key
            helpers.logInfoTS(
                string.format(
                    "TaxiAuto: route %s %s mode=%d len=%d start=%s end=%s src=%s",
                    tostring(comp._lastIcao or ""),
                    tostring(comp._runwayName or ""),
                    tonumber(comp.mode or -1),
                    tonumber(rlen or 0),
                    tostring(comp._route.start_id or "?"),
                    tostring(comp._route.end_id or "?"),
                    tostring(src)
                )
            )
        end
    end

    if comp._planCenterPending then
        if (not in_edit) and comp.mode == 1 and onGround == false then
            local b = comp._fitBounds
            if b then
                local cx, cy = U.compute_bounds_center(b)
                if cx and cy then
                    comp._setCenter(cx, cy)
                    log_taxi("TaxiPlan: center on route bounds (open)")
                    comp._planCenterPending = false
                end
            end
        elseif onGround or comp.mode ~= 1 then
            comp._planCenterPending = false
        end
    end
    if comp._needsCenter and comp._fitBounds and not in_edit then
        local cx, cy = U.compute_bounds_center(comp._fitBounds)
        comp._setCenter(cx, cy)
        comp._needsCenter = false
    end
end


function M.windowSize()
    return C.defaultW, C.defaultH
end

local function newComponentImpl(ctx, def, settings, helpers, C, U)
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
    comp.position = createProperty({0, 0, C.defaultW, C.defaultH})
    comp.size = {C.defaultW, C.defaultH}
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
    comp.zoom = clamp(getSettingNumber(def.CONFIGTAXIMAPZOOM, 1.0), C.minZoom, C.maxZoom)
    comp.fontSize = clamp(getSettingNumber(def.CONFIGTAXIMAPFONTSIZE, 12), C.minFont, C.maxFont)
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
    comp._startRampLabel = nil
    comp._startRampKey = nil
    comp._startRampRejectKey = nil
    comp._startRampChoiceKey = nil
    comp._startRampChoiceSource = nil
    comp._endRamp = nil
    comp._startIsAircraft = false
    comp._selectedEndRampKey = nil
    comp._selectedDepEntryId = nil
    comp._selectedDepEntryManual = nil
    comp._runwayName = nil
    comp._fitBounds = nil
    comp._lastUpdate = nil
    comp._lastIcao = nil
    comp._lastMode = nil
    comp._lastStartKey = nil
    comp._lastEndKey = nil
    comp._routeStartAnchor = nil
    comp._routeExtraSegments = nil
    comp._followAircraft = true
    comp._lastArrivalIcao = nil
    comp._lastArrivalRunwayName = nil
    comp._lastArrivalRunwayLat = nil
    comp._lastArrivalRunwayLon = nil
    comp._lastDepRunwayName = nil
    comp._depHoldshortLatchedId = nil
    comp._depHoldshortLatchIcao = nil
    comp._depHoldshortLatchRunway = nil
    comp._needsCenter = true
    comp._lastGuidanceNodeId = nil
    comp._lastGuidanceLabel = nil
    comp._lastGuidanceTime = nil
    comp._sCurveSkipNodeId = nil
    comp._visualGuidance = nil
    comp._manualRouteActive = false
    comp._manualRouteLock = false
    comp._manualRouteSnapshot = nil
    comp._gateNote = nil
    comp._gateCalloutKey = nil
    comp._gateCalloutStage = 0
    comp._gateCalloutStop = false
    comp._gateGuidanceLastDir = nil
    comp._gateGuidanceLastAction = nil
    comp._gateGuidanceLastTime = nil
    comp._gateGuidanceStop = false
    comp._gateGuidanceActive = false
    comp._gateFinalTurnUntil = nil
    comp._gateFinalTurnKey = nil
    comp._gateFinalTurnPending = false
    comp._gateGuidanceLastDist = nil
    comp._gateActivationDist = nil
    comp._gateCalloutDist = nil
    comp._guidanceState = "idle"
    comp._terminalGuidanceTime = nil
    comp._depRunwayEntryAnnounced = false
    comp._depTaxiCompleteAnnounced = false
    comp._arrTaxiCompleteAnnounced = false
    comp._arrTaxiCompleteFreeze = false
    comp._arrExitLockedId = nil
    comp._arrExitLockedAlong = nil
    comp._arrExitId = nil
    comp._arrExitAlong = nil
    comp._arrRunwayStartNodeLatched = nil
    comp._arrRunwayStartNodeIcao = nil
    comp._arrRunwayStartNodeRunway = nil
    comp._arrGroundRecomputePending = nil
    comp._offrouteDivergenceCount = 0
    comp._initialGuidanceDone = false
    comp._initialMoveAnchor = nil
    comp._guidanceMoveAnchor = nil
    comp._runwayCrossWarnedKey = nil
    comp._depEntryIssuedAt = nil
    comp._pushbackStartedEver = false
    comp._pushbackActive = false
    comp._pushbackCompleted = false
    comp._pushbackPlanSeen = false
    comp._guidancePushbackReleased = nil
    comp._pushbackReleaseAnchor = nil
    comp._pushbackReanchorPending = nil
    comp._pushbackReanchorDone = nil
    comp._pushbackReanchorTime = nil
    comp._beforeTaxiVoiceWarned = false
    comp._beforeTaxiVoiceWarnAt = nil
    clear_pushback_join_hold(comp)
    comp._lastPushbackJoinHoldLog = nil
    comp._autoTaxiNext = nil
    comp._autoTaxiReady = false
    comp._lastRecomputeKey = nil
    comp._lastRerouteTime = nil
    comp._rerouteOverride = nil
    comp._rerouteOverrideHoldUntil = nil
    comp._depThresholdLatched = false
    comp._depRunwayEntryLock = false
    comp._depTerminalSequenceLock = false
    comp._depSegmentReanchorDone = false
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
        parkingBrakeCompleteDist = C.parkingBrakeCompleteDist,
        gateSelectRadius = C.gateSelectRadius,
        gateGuidanceRadius = C.gateGuidanceRadius,
        gateGuidanceMaxSpeed = C.gateGuidanceMaxSpeed,
        gateGuidanceDeadzone = C.gateGuidanceDeadzone,
        gateGuidanceBehindLimit = C.gateGuidanceBehindLimit,
        gateGuidanceCooldownSec = C.gateGuidanceCooldownSec,
        gatePopupHoldDist = C.gatePopupHoldDist
    }
    comp._U = U
    comp._C = C
    comp._def = def
    comp._helpers = helpers
    comp._logTaxi = log_taxi
    comp._autoEndRampKey = nil
    comp._quality = { rerouteEvents = {} }
    comp._taxiSourceByIcao = {}
    comp._taxiSourceManualByIcao = {}
    comp._taxiGlobalPending = {}
    comp._depSourceLock = false
    comp._depSourceLockIcao = nil
    comp.yal = ctx and ctx.yal or _G.yal
    comp._timer = sasl.createTimer()
    sasl.startTimer(comp._timer)

    function comp:setWindow(win)
        self._window = win
        log_taxi("TaxiWindow: setWindow")
    end

    function comp:isWindowVisible()
        if self._window and self._window.isVisible then
            return self._window:isVisible()
        end
        return false
    end

    function comp:hasActiveGuidance()
        if self._route or self._visualGuidance then
            return true
        end
        if self._visualGuidanceQueue and #self._visualGuidanceQueue > 0 then
            return true
        end
        if self._routeErr == "taxi-complete" then
            return true
        end
        return false
    end

    local function getSize()
        local p = get(comp.position)
        local w = (p and p[3] and p[3] > 0) and p[3] or C.defaultW
        local h = (p and p[4] and p[4] > 0) and p[4] or C.defaultH
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
    comp._setCenter = set_center

    local function center_on_aircraft()
        local yal = comp.yal or _G.yal
        if not yal or not yal.aircraftlatpos or not yal.aircraftlonpos then
            return false
        end
        if yal.airgroundsensor and get(yal.airgroundsensor) ~= def.ON then
            comp._followAircraft = false
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
        comp.zoom = clamp(fitScale / baseScale, C.minZoom, C.maxZoom)
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
            close = { x = w - 24, y = h - C.headerH, w = 24, h = C.headerH },
            buttons = {},
            ramps = {},
            dep_entries = {},
            waypoints = {},
            map = {
                x = C.mapPadding,
                y = C.mapPadding,
                w = w - C.mapPadding * 2,
                h = h - C.headerH - C.toolbarH - C.mapPadding * 2
            }
        }
        layout.map.y = C.mapPadding

        drawRectangle(0, 0, w, h, {0, 0, 0, 0.78})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.6, 0.6, 0.6, 0.8})
        drawRectangle(0, h - C.headerH, w, C.headerH, {0.12, 0.12, 0.12, 1})
        drawRectangle(0, h - C.headerH - C.toolbarH, w, C.toolbarH, {0.08, 0.08, 0.08, 1})

        local uiFontSize = def and def.wFontSize or 12
        local mapFontSize = comp.fontSize or 12
        drawText(font, 8, h - C.headerH + 4, "Taxi Map", uiFontSize, TEXT_ALIGN_LEFT, {0.9, 0.9, 0.95, 1})
        drawText(font, w - 18, h - C.headerH + 4, "X", uiFontSize, TEXT_ALIGN_LEFT, {0.9, 0.5, 0.5, 1})

        -- taxi state updates run in component update / background loop

        local btnW = 78
        local btnH = C.toolbarH - 6
        local y = h - C.headerH - C.toolbarH + 3
        local x = 8

        if comp._followAircraft and (comp._editRoute or comp._drawRoute or comp.drag) then
            comp._followAircraft = false
        end

        local modeLabel = (comp.mode == 1) and "ARR" or "DEP"
        addButton(layout.buttons, x, y, 64, btnH, modeLabel, "toggle_mode")
        x = x + 70
        local srcMode = get_taxi_source_mode(comp, comp._lastIcao or "")
        local srcLabel = "SRC AUTO"
        if srcMode == "addon" then
            srcLabel = "SRC SCN"
        elseif srcMode == "global" then
            srcLabel = "SRC GLB"
        end
        addButton(layout.buttons, x, y, btnW + 8, btnH, srcLabel, "cycle_source")
        x = x + btnW + 14

        local orientLabel = (comp.orientation == 1) and "HDG UP" or "NORTH UP"
        addButton(layout.buttons, x, y, btnW + 10, btnH, orientLabel, "toggle_orient")
        x = x + btnW + 16
        addButton(layout.buttons, x, y, btnW, btnH, "ZOOM -", "zoom_out")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "ZOOM +", "zoom_in")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "FIT", "fit")
        x = x + btnW + 6
        local centerLabel = comp._followAircraft and "FOLLOW" or "CENTER"
        addButton(layout.buttons, x, y, btnW, btnH, centerLabel, "center")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "AUTO", "auto_route")
        x = x + btnW + 10
        local manualLabel = "MANUAL"
        addButton(layout.buttons, x, y, btnW, btnH, manualLabel, "toggle_manual")
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
            elseif b.action == "toggle_manual" then
                active = comp._manualRouteLock == true
            elseif b.action == "center" then
                active = comp._followAircraft == true
            elseif b.action == "cycle_source" then
                active = (get_taxi_source_mode(comp, comp._lastIcao or "") ~= "auto")
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

        if comp._followAircraft and (not comp._editRoute) and (not comp._drawRoute) then
            center_on_aircraft()
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
        if comp._editTailSegments then
            for _, seg in ipairs(comp._editTailSegments) do
                local x1, y1 = project(seg.east1, seg.north1)
                local x2, y2 = project(seg.east2, seg.north2)
                sasl.gl.drawLine(x1, y1, x2, y2, routeShadow)
                sasl.gl.drawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1, routeColor)
            end
        end
        if comp._drawRoute and comp._drawFreehand
            and comp._mouseInMap
            and comp._routeWaypoints and #comp._routeWaypoints > 0
            and comp._mouseX and comp._mouseY then
            local last = comp._routeWaypoints[#comp._routeWaypoints]
            local le = last and last.east or nil
            local ln = last and last.north or nil
            if (le == nil or ln == nil) and last and is_valid_latlon(last.lat, last.lon) then
                le, ln = latlon_to_local(last.lat, last.lon)
            end
            local we, wn = screen_to_world_from_transform(comp._mapTransform, comp._mouseX, comp._mouseY)
            if le ~= nil and ln ~= nil and we ~= nil and wn ~= nil then
                local x1, y1 = project(le, ln)
                local x2, y2 = project(we, wn)
                sasl.gl.drawLine(x1, y1, x2, y2, {0.0, 0.0, 0.0, 0.35})
                sasl.gl.drawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1, {1.0, 1.0, 1.0, 0.35})
            end
        end
        if (not comp._drawFreehand) and routeData and routeData.nodes
            and comp._endRamp and comp._endRamp.east and comp._endRamp.north then
            local endNode = ramp_route_node(routeData, comp._endRamp)
            if (not endNode) and comp._route and comp._route.path then
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
                        local anchor = ramp_route_node(comp._data, ramp)
                        if anchor and anchor.east ~= nil and anchor.north ~= nil then
                            ramp._draw_link_east = anchor.east
                            ramp._draw_link_north = anchor.north
                        else
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
            if comp._startPoint then
                local sx, sy = project(comp._startPoint.east, comp._startPoint.north)
                drawRectangle(sx - 3, sy - 3, 6, 6, startColor)
                drawText(font, sx + 5, sy + 2, "S", mapFontSize, TEXT_ALIGN_LEFT, {0, 0, 0, 0.9})
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
            local ramp = comp._startRampLabel or comp._startRamp
            if ramp and ramp.name and ramp.name ~= "" then
                gateLabel = short_ramp_label(ramp)
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
        drawRectangle(0, h - C.headerH, w, C.headerH, {0.12, 0.12, 0.12, 1})
        drawRectangle(0, h - C.headerH - C.toolbarH, w, C.toolbarH, {0.08, 0.08, 0.08, 1})
        drawText(font, 8, h - C.headerH + 4, "Taxi Map", uiFontSize, TEXT_ALIGN_LEFT, {0.9, 0.9, 0.95, 1})
        drawText(font, w - 18, h - C.headerH + 4, "X", uiFontSize, TEXT_ALIGN_LEFT, {0.9, 0.5, 0.5, 1})
        for _, b in ipairs(layout.buttons) do
            local active = (b.action == "toggle_orient") and (comp.orientation == 1)
            if b.action == "toggle_edit" then
                active = comp._editRoute == true
            elseif b.action == "toggle_draw" then
                active = comp._drawRoute == true
            elseif b.action == "toggle_manual" then
                active = comp._manualRouteLock == true
            elseif b.action == "cycle_source" then
                active = (get_taxi_source_mode(comp, comp._lastIcao or "") ~= "auto")
            end
            drawButton(font, b, active, uiFontSize)
        end

        comp._layout = layout
    end

    function comp:onMouseDown(x, y, button, shift, _, _)
        local layout = self._layout
        if not layout then
            return false
        end
        local has_left = (MB_LEFT ~= nil)
        local has_right = (MB_RIGHT ~= nil)
        local is_left = (has_left and button == MB_LEFT) or ((not has_left) and (button == 0 or button == 1))
        local is_right = (has_right and button == MB_RIGHT) or ((not has_right) and (button == 2 or button == 3))
        if is_left then
            is_right = false
        end
        if not (is_left or is_right) then
            return false
        end
        if comp._mapTransform then
            local t = comp._mapTransform
            comp._mouseX = x
            comp._mouseY = y
            comp._mouseInMap = (x >= t.mapX and x <= (t.mapX + t.mapW) and y >= t.mapY and y <= (t.mapY + t.mapH))
        end
        if layout.close then
            local c = layout.close
            if x >= c.x and x <= (c.x + c.w) and y >= c.y and y <= (c.y + c.h) then
                if not is_left then
                    return false
                end
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
                if not is_left then
                    return false
                end
                if b.action == "toggle_mode" then
                    comp.mode = (comp.mode == 1) and 0 or 1
                    comp.modeOverride = true
                    comp._needsCenter = true
                    comp._lastUpdate = nil
                elseif b.action == "cycle_source" then
                    local icao = comp._lastIcao
                    if not helpers.isvalidicao(icao or "") then
                        log_taxi("TaxiSource: ignored (invalid ICAO)")
                        return true
                    end
                    local mode = get_taxi_source_mode(comp, icao)
                    local next_mode = "addon"
                    if mode == "addon" then
                        next_mode = "global"
                    elseif mode == "global" then
                        next_mode = "auto"
                    end
                    set_taxi_source_mode(comp, icao, next_mode, "button", log_taxi)
                elseif b.action == "toggle_orient" then
                    comp.orientation = (comp.orientation == 1) and 0 or 1
                    commitSettings()
                elseif b.action == "zoom_in" then
                    comp.zoom = clamp(comp.zoom * C.zoomStep, C.minZoom, C.maxZoom)
                    commitSettings()
                elseif b.action == "zoom_out" then
                    comp.zoom = clamp(comp.zoom / C.zoomStep, C.minZoom, C.maxZoom)
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
                    if not (comp.yal and comp.yal.airgroundsensor and get(comp.yal.airgroundsensor) == def.ON) then
                        comp._followAircraft = false
                        log_taxi("TaxiMap: center ignored (airborne)")
                        return true
                    end
                    comp._followAircraft = true
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
                    comp._manualRouteActive = false
                    comp._manualRouteLock = false
                    comp._manualRouteSnapshot = nil
                    log_taxi("TaxiRoute: auto-reset")
                elseif b.action == "toggle_manual" then
                    if comp._manualRouteLock then
                        comp._manualRouteLock = false
                        comp._manualRouteSnapshot = nil
                        log_taxi("TaxiEdit: manual-lock=false")
                    else
                        if (comp._routeWaypoints and #comp._routeWaypoints > 0) or comp._route then
                            comp._manualRouteLock = true
                            log_taxi(
                                string.format(
                                    "TaxiEdit: manual-lock=true wps=%d route=%s",
                                    (comp._routeWaypoints and #comp._routeWaypoints) or 0,
                                    tostring(comp._route ~= nil)
                                )
                            )
                            ensure_manual_dep_runway_anchor(comp)
                        else
                            comp._manualRouteLock = false
                            log_taxi("TaxiEdit: manual-lock ignored (no-waypoints/no-route)")
                        end
                    end
                elseif b.action == "font_down" then
                    comp.fontSize = clamp(comp.fontSize - 1, C.minFont, C.maxFont)
                    comp._fontHandle = nil
                    commitSettings()
                elseif b.action == "font_up" then
                    comp.fontSize = clamp(comp.fontSize + 1, C.minFont, C.maxFont)
                    comp._fontHandle = nil
                    commitSettings()
                elseif b.action == "toggle_edit" then
                    comp._editRoute = not comp._editRoute
                    if not comp._editRoute then
                        comp._drawRoute = false
                        comp._wpDrag = nil
                        comp._editHandles = nil
                        comp._editSuppressedNodes = nil
                        if not comp._manualRouteLock then
                            comp._drawFreehand = false
                            if comp._routeWaypoints and #comp._routeWaypoints > 0 then
                                comp._routeWaypoints = {}
                                comp._route = nil
                                comp._routeErr = nil
                                comp._lastStartKey = nil
                                comp._lastEndKey = nil
                                comp._lastUpdate = nil
                                log_taxi("TaxiEdit: cleared waypoints on edit off")
                            end
                            comp._manualRouteActive = false
                        end
                    end
                    if comp._editRoute then
                        comp._editDirty = false
                        comp._editSuppressedNodes = {}
                        comp._editHandles = nil
                        clear_visual_guidance(comp, "edit-toggle")
                        comp._followAircraft = false
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
                        U.push_undo(comp, "draw-start")
                        comp._drawFreehand = true
                        comp._manualRouteActive = true
                        comp._routeWaypoints = {}
                        comp._route = nil
                        comp._routeErr = nil
                        comp._lastUpdate = nil
                        comp._editDirty = false
                        comp._editSuppressedNodes = {}
                        comp._editHandles = nil
                        comp._editStartOverride = nil
                        comp._editEndOverride = nil
                        comp._followAircraft = false
                    elseif not comp._routeWaypoints or #comp._routeWaypoints == 0 then
                        comp._drawFreehand = false
                        comp._manualRouteActive = false
                        comp._manualRouteLock = false
                        comp._manualRouteSnapshot = nil
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
                        U.restore_edit_state(comp, comp._undoState)
                        mark_edit_dirty(comp)
                        log_taxi("TaxiEdit: undo reason=" .. tostring(comp._undoReason))
                    else
                        log_taxi("TaxiEdit: undo empty")
                    end
                elseif b.action == "clear_route" then
                    U.push_undo(comp, "clear-route")
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
                    comp._manualRouteActive = false
                    comp._manualRouteLock = false
                    comp._manualRouteSnapshot = nil
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
                    comp._manualEndRampRetargetUntil = nil
                    log_taxi("TaxiEdit: end-ramp cleared")
                else
                    comp._selectedEndRampKey = best.key
                    comp._autoEndRampKey = nil
                    log_taxi("TaxiEdit: end-ramp selected key=" .. tostring(best.key))
                    if comp.mode == 1 and comp._data then
                        reroute_from_current_aircraft(comp, comp._data, "end-ramp-manual", true, log_taxi)
                        local now = comp._timer and (sasl.getElapsedSeconds(comp._timer) or 0) or nil
                        if now then
                            local gate_cooldown = (comp._tuning and comp._tuning.autoGateSwitchCooldownSec) or 10.0
                            local hold = math.max(gate_cooldown * 2, ((C and C.rerouteCooldown) or 6) * 3)
                            comp._manualEndRampRetargetUntil = now + hold
                            comp._rerouteOverrideHoldUntil = now + hold
                        end
                    end
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
            local function radius_for_hit(hit)
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
                return radius
            end

            local function consider_hit(hit, radius_override)
                local radius = radius_override or radius_for_hit(hit)
                local hitD2 = radius * radius
                local dx = x - hit.x
                local dy = y - hit.y
                local d2 = dx * dx + dy * dy
                if d2 <= hitD2 and (not bestDist or d2 < bestDist) then
                    best = hit
                    bestDist = d2
                end
            end

            if comp._drawRoute and comp._drawFreehand then
                -- In freehand draw, only allow start/end/manual handles.
                for _, hit in ipairs(layout.waypoints) do
                    if hit.handle_idx and comp._editHandles and comp._editHandles[hit.handle_idx] then
                        local h = comp._editHandles[hit.handle_idx]
                        if h and (h.kind == "start" or h.kind == "end") then
                            consider_hit(hit, hitRadiusSE)
                        end
                    end
                end
                if not best then
                    for _, hit in ipairs(layout.waypoints) do
                        if hit.handle_idx and comp._editHandles and comp._editHandles[hit.handle_idx] then
                            local h = comp._editHandles[hit.handle_idx]
                            if h and h.kind == "manual" then
                                consider_hit(hit, hitRadiusManual)
                            end
                        elseif hit.idx then
                            consider_hit(hit, hitRadiusManual)
                        end
                    end
                end
            else
                -- Pass 1: prefer start/end handles to avoid grabbing nearby manual handles.
                for _, hit in ipairs(layout.waypoints) do
                    if hit.handle_idx and comp._editHandles and comp._editHandles[hit.handle_idx] then
                        local h = comp._editHandles[hit.handle_idx]
                        if h and (h.kind == "start" or h.kind == "end") then
                            consider_hit(hit, hitRadiusSE)
                        end
                    end
                end

                -- Pass 2: fallback to the closest handle of any kind.
                if not best then
                    for _, hit in ipairs(layout.waypoints) do
                        consider_hit(hit, nil)
                    end
                end
            end
            if best then
                if is_right and best.idx and comp._routeWaypoints and comp._routeWaypoints[best.idx] then
                    U.push_undo(comp, "manual-delete")
                    table.remove(comp._routeWaypoints, best.idx)
                    mark_edit_dirty(comp)
                    log_taxi("TaxiEdit: waypoint deleted wp=" .. tostring(best.idx))
                    return true
                end
                if best.handle_idx and comp._editHandles and comp._editHandles[best.handle_idx] then
                    local handle = comp._editHandles[best.handle_idx]
                    if is_right and handle then
                        if handle.kind == "manual" and handle.wp_idx then
                            U.push_undo(comp, "manual-delete")
                            if comp._routeWaypoints and comp._routeWaypoints[handle.wp_idx] then
                                table.remove(comp._routeWaypoints, handle.wp_idx)
                            end
                            mark_edit_dirty(comp)
                            log_taxi("TaxiEdit: waypoint deleted wp=" .. tostring(handle.wp_idx))
                            return true
                        end
                        if comp._drawFreehand and (handle.kind == "start" or handle.kind == "end") then
                            U.push_undo(comp, "endpoint-delete")
                            if comp._routeWaypoints and #comp._routeWaypoints > 0 then
                                if handle.kind == "start" then
                                    table.remove(comp._routeWaypoints, 1)
                                else
                                    table.remove(comp._routeWaypoints, #comp._routeWaypoints)
                                end
                                mark_edit_dirty(comp)
                                log_draw_endpoints(comp, "endpoint-delete")
                                log_taxi("TaxiEdit: endpoint deleted kind=" .. tostring(handle.kind))
                            end
                            return true
                        end
                        return false
                    end
                    if handle and handle.kind == "auto" then
                        U.push_undo(comp, "auto-handle")
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
                            wlat, wlon = local_to_latlon(handle.east, handle.north)
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
                        U.push_undo(comp, "handle-down")
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
                    U.push_undo(comp, "handle-down")
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
                    comp._selectedDepEntryManual = nil
                    log_taxi("TaxiEdit: dep-entry cleared")
                else
                    comp._selectedDepEntryId = best.id
                    comp._selectedDepEntryManual = true
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
                if comp._drawRoute and is_left then
                        local function add_waypoint_freehand()
                            local we, wn = screen_to_world(x, y)
                            local wlat, wlon = local_to_latlon(we, wn)
                            if is_valid_latlon(wlat, wlon) then
                                if not comp._routeWaypoints then
                                    comp._routeWaypoints = {}
                                end
                                U.push_undo(comp, "draw-add")
                            local insert_idx = nil
                            local best_idx = nil
                            local best_d2 = nil
                            if shift and comp._routeWaypoints and #comp._routeWaypoints >= 2 then
                                local max_d2 = C.freehandInsertMaxPixels * C.freehandInsertMaxPixels
                                for i = 1, #comp._routeWaypoints - 1 do
                                    local wp1 = comp._routeWaypoints[i]
                                    local wp2 = comp._routeWaypoints[i + 1]
                                    local e1, n1 = wp1 and wp1.east, wp1 and wp1.north
                                    if (e1 == nil or n1 == nil) and wp1 and is_valid_latlon(wp1.lat, wp1.lon) then
                                        e1, n1 = latlon_to_local(wp1.lat, wp1.lon)
                                    end
                                    local e2, n2 = wp2 and wp2.east, wp2 and wp2.north
                                    if (e2 == nil or n2 == nil) and wp2 and is_valid_latlon(wp2.lat, wp2.lon) then
                                        e2, n2 = latlon_to_local(wp2.lat, wp2.lon)
                                    end
                                    if e1 ~= nil and n1 ~= nil and e2 ~= nil and n2 ~= nil then
                                        local x1, y1 = project(e1, n1)
                                        local x2, y2 = project(e2, n2)
                                        local px, py = project_point_to_segment(x, y, x1, y1, x2, y2)
                                        local d2 = distance_sq(x, y, px, py)
                                        if not best_d2 or d2 < best_d2 then
                                            best_d2 = d2
                                            best_idx = i
                                        end
                                    end
                                end
                                if best_idx and best_d2 and best_d2 <= max_d2 then
                                    insert_idx = best_idx + 1
                                end
                            end
                            local wp = {
                                lat = wlat,
                                lon = wlon,
                                east = we,
                                north = wn,
                                segment_idx = nil
                            }
                            if insert_idx and insert_idx >= 1 and insert_idx <= (#comp._routeWaypoints + 1) then
                                table.insert(comp._routeWaypoints, insert_idx, wp)
                                log_taxi(
                                    string.format(
                                        "TaxiDraw: insert-waypoint-free idx=%d after=%s d=%.1fpx lat=%.6f lon=%.6f total=%d",
                                        insert_idx,
                                        tostring(best_idx),
                                        best_d2 and math.sqrt(best_d2) or -1,
                                        wlat,
                                        wlon,
                                        #comp._routeWaypoints
                                    )
                                )
                            else
                                table.insert(comp._routeWaypoints, wp)
                                log_taxi(
                                    string.format(
                                        "TaxiDraw: add-waypoint-free idx=%d lat=%.6f lon=%.6f total=%d",
                                        #comp._routeWaypoints,
                                        wlat,
                                        wlon,
                                        #comp._routeWaypoints
                                    )
                                )
                            end
                            mark_edit_dirty(comp)
                            log_draw_endpoints(comp, "freehand")
                            return true
                        end
                        return false
                    end

                    local function add_waypoint_nearest_edge()
                        local we, wn = screen_to_world(x, y)
                        local proj = find_nearest_edge_projection(comp._data, we, wn, { disallow_runway_edges = false })
                        if proj and proj.edge then
                                local wlat, wlon = local_to_latlon(proj.proj_east, proj.proj_north)
                                if is_valid_latlon(wlat, wlon) then
                                    if not comp._routeWaypoints then
                                        comp._routeWaypoints = {}
                                    end
                                    U.push_undo(comp, "draw-add")
                                    table.insert(comp._routeWaypoints, {
                                        lat = wlat,
                                        lon = wlon,
                                        east = proj.proj_east,
                                        north = proj.proj_north,
                                        segment_idx = nil
                                    })
                                    mark_edit_dirty(comp)
                                    log_draw_endpoints(comp, "edge")
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
                                    local wlat, wlon = local_to_latlon(we, wn)
                                    if is_valid_latlon(wlat, wlon) then
                                        if not comp._routeWaypoints then
                                            comp._routeWaypoints = {}
                                        end
                                        U.push_undo(comp, "draw-insert")
                                        table.insert(comp._routeWaypoints, {
                                            lat = wlat,
                                            lon = wlon,
                                            east = we,
                                            north = wn,
                                            segment_idx = nil
                                        })
                                        mark_edit_dirty(comp)
                                        log_draw_endpoints(comp, "route")
                                        log_taxi(
                                            string.format(
                                                "TaxiDraw: insert-waypoint seg=%s d=%.1fpx lat=%.6f lon=%.6f total=%d",
                                                tostring(best_idx),
                                                best_d2 and math.sqrt(best_d2) or -1,
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
                                local wlat, wlon = local_to_latlon(we, wn)
                                if is_valid_latlon(wlat, wlon) then
                                    if not comp._routeWaypoints then
                                        comp._routeWaypoints = {}
                                    end
                                    U.push_undo(comp, "edit-insert")
                                    local new_idx = insert_waypoint_sorted(comp._routeWaypoints, {
                                        lat = wlat,
                                        lon = wlon,
                                        east = we,
                                        north = wn,
                                        segment_idx = best_idx
                                    })
                                    mark_edit_dirty(comp)
                                    log_taxi(
                                        string.format(
                                            "TaxiEdit: insert-waypoint seg=%s idx=%s d=%.1fpx lat=%.6f lon=%.6f total=%d",
                                            tostring(best_idx),
                                            tostring(new_idx),
                                            best_d2 and math.sqrt(best_d2) or -1,
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
                if is_left and x >= dragX1 and x <= dragX2 and y >= dragY1 and y <= dragY2 then
                    comp.drag = { startX = x, startY = y, panX = comp.panX, panY = comp.panY }
                    comp._followAircraft = false
                    return true
                end
                return false
            end
        end
        return false
    end

    function comp:onMouseMove(x, y, _, _, _)
        comp._mouseX = x
        comp._mouseY = y
        if comp._mapTransform then
            local t = comp._mapTransform
            comp._mouseInMap = (x >= t.mapX and x <= (t.mapX + t.mapW) and y >= t.mapY and y <= (t.mapY + t.mapH))
        else
            comp._mouseInMap = false
        end
        if comp._wpDrag then
            local drag = comp._wpDrag
            local dx = x - drag.startX
            local dy = y - drag.startY
            if (dx * dx + dy * dy) >= (C.waypointDragPixels * C.waypointDragPixels) then
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
                    local snap_ok = (proj and proj.edge and proj.d2 and proj.d2 <= (C.startEndSnapMeters * C.startEndSnapMeters))
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
                    local wlat, wlon = local_to_latlon(target_east, target_north)
                    if (not is_valid_latlon(wlat, wlon)) and (not use_freehand) and proj and proj.edge then
                        target_east = proj.proj_east
                        target_north = proj.proj_north
                        wlat, wlon = local_to_latlon(target_east, target_north)
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
                    comp.zoom = clamp(comp.zoom * C.zoomStep, C.minZoom, C.maxZoom)
                else
                    comp.zoom = clamp(comp.zoom / C.zoomStep, C.minZoom, C.maxZoom)
                end
                commitSettings()
                return true
            end
        end
        return false
    end

    function comp:update()
        local visible = self:isWindowVisible()
        if visible and not self._lastWindowVisible then
            self._planCenterPending = true
        end
        self._lastWindowVisible = visible
        if visible then
            self:updateTaxiState()
        end
        return
    end

    function comp:onKeyDown(_, _, _, _, _, _)
        return false
    end

    function comp:onKeyUp(_, _, _, _, _, _)
        return false
    end

    function comp:updateTaxiState(map)
        return updateTaxiState(self, map)
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

    function comp:getPushbackDecision()
        if comp.mode ~= 0 then
            return nil
        end
        local path = comp._route and comp._route.path or nil
        local data = comp._route and comp._route.data or nil
        local n1 = nil
        local n2 = nil
        local target_label = nil
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
                        target_label = raw_label or ""
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
                        target_label = proj.edge.label or ""
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
        local join_heading = nil
        local join_dist = nil
        local join_east = nil
        local join_north = nil
        local join_relative = nil
        local join_diff = nil
        local join_sector = nil
        local route_diff = nil
        local forward_roll_ok = nil
        local requires_reverse = nil
        local start_ramp = comp._startRamp
        local ramp_heading = tonumber(start_ramp and start_ramp.heading) or nil
        local ramp_link_along = tonumber(start_ramp and start_ramp.link_along) or nil
        local ramp_link_cross = tonumber(start_ramp and start_ramp.link_cross) or nil
        if ramp_link_cross ~= nil then
            ramp_link_cross = math.abs(ramp_link_cross)
        end
        local ramp_link_mode = start_ramp and start_ramp.link_mode or nil
        local ramp_link_dist = tonumber(start_ramp and start_ramp.link_distance_m) or nil
        local ramp_link_label = start_ramp and start_ramp.link_edge_label or nil
        local release_m = ((C and C.pushbackReleaseMeters) or 5)
        if comp._aircraftPoint and comp._aircraftPoint.east and comp._aircraftPoint.north then
            local px, py = project_point_to_segment(
                comp._aircraftPoint.east,
                comp._aircraftPoint.north,
                n1.east,
                n1.north,
                n2.east,
                n2.north
            )
            if px ~= nil and py ~= nil then
                join_east = px
                join_north = py
            else
                join_east = n1.east
                join_north = n1.north
            end
            local jdx = join_east - comp._aircraftPoint.east
            local jdy = join_north - comp._aircraftPoint.north
            if jdx ~= 0 or jdy ~= 0 then
                join_dist = math.sqrt(jdx * jdx + jdy * jdy)
                join_heading = math.deg(math.atan2(jdx, jdy))
                if join_heading < 0 then
                    join_heading = join_heading + 360
                end
            end
        end
        local heading_use = heading
        if join_heading and join_dist and join_dist > ((C and C.pushbackReleaseMeters) or 5) then
            heading_use = join_heading
        end
        local yal = comp.yal or _G.yal
        local ac_heading = nil
        if yal and yal.localpositionpsi and isProperty(yal.localpositionpsi) then
            ac_heading = get(yal.localpositionpsi)
        elseif yal and yal.groundtrackmag and isProperty(yal.groundtrackmag) then
            ac_heading = get(yal.groundtrackmag)
        end
        if ac_heading == nil then
            return {
                heading = heading,
                route_heading = heading,
                join_heading = join_heading,
                join_dist = join_dist,
                join_east = join_east,
                join_north = join_north,
                label = target_label,
                ramp_heading = ramp_heading,
                ramp_link_along = ramp_link_along,
                ramp_link_cross = ramp_link_cross,
                ramp_link_mode = ramp_link_mode,
                ramp_link_dist = ramp_link_dist,
                ramp_link_label = ramp_link_label
            }
        end
        route_diff = math.abs(((heading - ac_heading + 540) % 360) - 180)
        if join_heading ~= nil then
            join_relative = ((join_heading - ac_heading + 540) % 360) - 180
            join_diff = math.abs(join_relative)
            if join_diff <= 75 then
                join_sector = "front"
            elseif join_diff >= 115 then
                join_sector = "rear"
            else
                join_sector = "side"
            end
        end
        local ramp_forward = nil
        if ramp_link_along ~= nil and ramp_link_cross ~= nil then
            if ramp_link_along <= -6 and ramp_link_cross <= 35 then
                ramp_forward = false
            elseif ramp_link_along >= -2 and ramp_link_cross <= 25 then
                ramp_forward = true
            end
        end
        if join_sector == "rear" and join_dist and join_dist > (release_m + 1) then
            requires_reverse = true
        elseif ramp_forward == false then
            requires_reverse = true
        end
        if requires_reverse ~= true then
            if ramp_forward == true and (join_sector == nil or join_sector ~= "rear") and route_diff <= 110 then
                forward_roll_ok = true
            elseif join_sector == "front" and (not join_dist or join_dist <= 30) and route_diff <= 95 then
                forward_roll_ok = true
            else
                forward_roll_ok = false
            end
        else
            forward_roll_ok = false
        end
        local diff = math.abs(((heading_use - ac_heading + 540) % 360) - 180)
        return {
            heading = heading_use,
            route_heading = heading,
            join_heading = join_heading,
            join_dist = join_dist,
            join_east = join_east,
            join_north = join_north,
            join_relative = join_relative,
            join_diff = join_diff,
            join_sector = join_sector,
            route_diff = route_diff,
            aircraft = ac_heading,
            diff = diff,
            label = target_label,
            ramp_heading = ramp_heading,
            ramp_link_along = ramp_link_along,
            ramp_link_cross = ramp_link_cross,
            ramp_link_mode = ramp_link_mode,
            ramp_link_dist = ramp_link_dist,
            ramp_link_label = ramp_link_label,
            requires_reverse = requires_reverse,
            forward_roll_ok = forward_roll_ok
        }
    end

    function comp:clearVisualGuidance()
        clear_visual_guidance(comp, "manual-clear")
    end

    function comp:clearVisualGuidanceQueue()
        comp._visualGuidanceQueue = {}
    end

    function comp:autoTaxiTick()
        local U = comp._U or {}
        local auto_tick = U.auto_taxi_tick
        if not auto_tick then
            return
        end
        local now = 0
        if comp._timer then
            now = sasl.getElapsedSeconds(comp._timer) or 0
        end
        auto_tick(comp, now)
    end

    function comp:tick()
        local ww = C.defaultW
        local hh = C.defaultH
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
