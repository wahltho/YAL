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
local guidanceMinSpeed = 2
local guidanceTurnDistance = 70
local guidanceTurnAngle = 30
local startRampMaxMeters = 80

local minZoom = 0.2
local maxZoom = 5
local zoomStep = 1.2
local minFont = 8
local maxFont = 24

local def = require("definitions")
local settings = require("settings")
local helpers = require("helpers")

-- Forward declaration: used by nearest_node_info before definition below.
local latlon_to_local

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

local function nearest_node_info(data, lat, lon)
    if not data or not data.nodes or not is_valid_latlon(lat, lon) then
        return nil, nil
    end
    local x, y = latlon_to_local(lat, lon)
    local best_id = nil
    local best_d2 = nil
    for id, node in pairs(data.nodes) do
        if node and node.east and node.north then
            local dx = node.east - x
            local dy = node.north - y
            local d2 = dx * dx + dy * dy
            if not best_d2 or d2 < best_d2 then
                best_d2 = d2
                best_id = id
            end
        end
    end
    if not best_id or not best_d2 then
        return nil, nil
    end
    return best_id, math.sqrt(best_d2)
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

latlon_to_local = function(lat, lon)
    local x, _, z = sasl.worldToLocal(lat, lon, 0)
    return x, -z
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

local function build_runway_backtrack_segments(data, profile, node_id)
    if not data or not profile or not node_id then
        return nil
    end
    local node = data.nodes and data.nodes[node_id]
    if not node or not node.east or not node.north then
        return nil
    end
    local axis = profile.axis
    local threshold = profile.threshold
    if not axis or not threshold then
        return nil
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
        east2 = threshold.east,
        north2 = threshold.north
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

local function select_runway_exit_node(data, profile)
    if not data or not profile or not profile.touchdown or not profile.axis then
        return nil, false
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

local function try_route_from_candidates(icao, data, end_lat, end_lon, candidates, opts)
    for _, cand in ipairs(candidates or {}) do
        local node = data.nodes[cand.id]
        if node and is_valid_latlon(node.lat, node.lon) then
            local route, rerr = helpers.getTaxiRoute(icao, node.lat, node.lon, end_lat, end_lon, opts)
            if route then
                return route, nil, node.lat, node.lon
            end
        end
    end
    return nil, "no-path"
end

local function try_route_to_candidates(icao, data, start_lat, start_lon, candidates, opts)
    for _, cand in ipairs(candidates or {}) do
        local node = data.nodes[cand.id]
        if node and is_valid_latlon(node.lat, node.lon) then
            local route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, node.lat, node.lon, opts)
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

local function trim_spaces(text)
    if not text then
        return ""
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    text = string.gsub(text, "%s+", " ")
    return text
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

local function normalize_taxiway_label(label)
    if not label or label == "" then
        return ""
    end
    local clean = helpers.forceCleanString(label)
    clean = helpers.cleanstring(clean)
    clean = string.upper(clean)
    if string.sub(clean, 1, 3) == "RWY" then
        return ""
    end
    if clean == "RAMP" then
        return ""
    end
    clean = string.gsub(clean, "^TAXIWAY[%s_-]*", "")
    clean = string.gsub(clean, "^TWY[%s_-]*", "")
    clean = trim_spaces(clean)
    return clean
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

local function speak_guidance_text(comp, text)
    local yal = comp.yal or _G.yal
    if yal and yal.commandtableentry then
        yal.commandtableentry(def.TEXT, text)
        return
    end
    helpers.speak(text)
end

local function maybe_speak_guidance(comp, now, aircraft)
    if not is_auto_taxi_guidance_enabled() then
        return
    end
    local function diag(reason, extra)
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
    if not is_voice_enabled() then
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
    local yal = comp.yal or _G.yal
    if not (yal and yal.airgroundsensor and get(yal.airgroundsensor) == def.ON) then
        diag("not-on-ground")
        return
    end
    local tirespeed = yal and yal.tirespeed and (get(yal.tirespeed) or 0) or 0
    if tirespeed <= 0 then
        diag("non-forward-speed", "ts=" .. tostring(tirespeed))
        return
    end
    if tirespeed < guidanceMinSpeed then
        diag("too-slow", "ts=" .. tostring(tirespeed))
        return
    end
    local data = comp._route.data or comp._data
    local path = comp._route.path
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
    local curr_label = normalize_taxiway_label(get_edge_label(data, path[seg_idx], path[seg_idx + 1]))
    local next_label = normalize_taxiway_label(get_edge_label(data, path[seg_idx + 1], path[seg_idx + 2]))
    if next_label == "" then
        diag("next-label-empty")
        return
    end
    if next_label == curr_label then
        diag("same-label", "label=" .. tostring(next_label))
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
    if angle < guidanceTurnAngle then
        diag("angle-too-small", string.format("angle=%.1f", angle))
        return
    end
    local ahead_dot = (aircraft.east - n2.east) * v1x + (aircraft.north - n2.north) * v1y
    if ahead_dot > 0 then
        diag("already-passed-turn")
        return
    end
    local dist_to_node = math.sqrt(distance_sq(aircraft.east, aircraft.north, n2.east, n2.north))
    if dist_to_node > guidanceTurnDistance then
        diag("too-far", string.format("dist=%.1f", dist_to_node))
        return
    end
    local last_time = comp._lastGuidanceTime or 0
    if comp._lastGuidanceNodeId == path[seg_idx + 1]
        and comp._lastGuidanceLabel == next_label
        and (now - last_time) < guidanceCooldown then
        diag("cooldown")
        return
    end
    local cross = v1x * v2y - v1y * v2x
    local turn = (cross >= 0) and "left" or "right"
    local text = "Turn " .. turn .. " on Taxiway " .. helpers.addspaces(next_label)
    speak_guidance_text(comp, text)
    comp._lastGuidanceNodeId = path[seg_idx + 1]
    comp._lastGuidanceLabel = next_label
    comp._lastGuidanceTime = now
end

local function getSettingNumber(key, fallback)
    local val = tonumber(settings.appSettings[key])
    if val == nil then
        return fallback
    end
    return val
end

function M.windowSize()
    return defaultW, defaultH
end

function M.newComponent(ctx)
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
    comp._runwayName = nil
    comp._fitBounds = nil
    comp._lastUpdate = nil
    comp._lastIcao = nil
    comp._lastMode = nil
    comp._lastStartKey = nil
    comp._lastEndKey = nil
    comp._routeExtraSegments = nil
    comp._lastArrivalIcao = nil
    comp._lastArrivalRunwayName = nil
    comp._lastArrivalRunwayLat = nil
    comp._lastArrivalRunwayLon = nil
    comp._needsCenter = true
    comp._lastGuidanceNodeId = nil
    comp._lastGuidanceLabel = nil
    comp._lastGuidanceTime = nil
    comp._lastRerouteTime = nil
    comp._rerouteOverride = nil
    comp.yal = ctx and ctx.yal or _G.yal
    comp._timer = sasl.createTimer()
    sasl.startTimer(comp._timer)

    function comp:setWindow(win)
        self._window = win
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
        if not yal or not yal.localpositionx or not yal.localpositionz then
            return false
        end
        local x = get(yal.localpositionx)
        local z = get(yal.localpositionz)
        if x == nil or z == nil then
            return false
        end
        set_center(x, -z)
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
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 0.95})
        drawRectangle(0, h - headerH - toolbarH, w, toolbarH, {0.08, 0.08, 0.08, 0.92})

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
        x = x + btnW + 10
        addButton(layout.buttons, x, y, btnW, btnH, "A -", "font_down")
        x = x + btnW + 6
        addButton(layout.buttons, x, y, btnW, btnH, "A +", "font_up")

        for _, b in ipairs(layout.buttons) do
            local active = (b.action == "toggle_orient") and (comp.orientation == 1)
            drawButton(font, b, active, uiFontSize)
        end
        comp._buttons = layout.buttons

        local map = layout.map
        drawRectangle(map.x, map.y, map.w, map.h, {0.05, 0.05, 0.07, 0.95})
        sasl.gl.drawFrame(map.x, map.y, map.w, map.h, {0.4, 0.4, 0.4, 0.8})
        comp._baseScale = compute_bounds_scale((comp._data and comp._data.bounds), map.w, map.h)

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

        local edgeColor = {0.35, 0.35, 0.42, 0.9}
        local polyColor = {0.2, 0.22, 0.28, 0.5}
        local runwayColor = {0.75, 0.75, 0.8, 1}
        local routeColor = {0.2, 0.8, 0.35, 1}
        local routeShadow = {0.05, 0.2, 0.08, 0.9}
        local rampColor = {0.85, 0.75, 0.25, 0.9}
        local rampGateColor = {0.35, 0.7, 1, 0.95}
        local startColor = {0.2, 0.85, 0.35, 1}
        local endColor = {1, 0.6, 0.2, 1}
        local aircraftColor = {0.95, 0.95, 0.98, 1}

        if comp._data and comp._data.polygons then
            for _, poly in ipairs(comp._data.polygons) do
                local pts = poly.points or {}
                for i = 1, #pts - 1 do
                    local p1 = pts[i]
                    local p2 = pts[i + 1]
                    local x1, y1 = project(p1.east, p1.north)
                    local x2, y2 = project(p2.east, p2.north)
                    sasl.gl.drawLine(x1, y1, x2, y2, polyColor)
                end
                if #pts > 2 then
                    local p1 = pts[#pts]
                    local p2 = pts[1]
                    local x1, y1 = project(p1.east, p1.north)
                    local x2, y2 = project(p2.east, p2.north)
                    sasl.gl.drawLine(x1, y1, x2, y2, polyColor)
                end
            end
        end

        if comp._data and comp._data.edges then
            for _, edge in ipairs(comp._data.edges) do
                local n1 = comp._data.nodes[edge.from]
                local n2 = comp._data.nodes[edge.to]
                if n1 and n2 then
                    local x1, y1 = project(n1.east, n1.north)
                    local x2, y2 = project(n2.east, n2.north)
                    local color = edgeColor
                    if edge.label and string.sub(edge.label, 1, 3) == "RWY" then
                        color = runwayColor
                    end
                    sasl.gl.drawLine(x1, y1, x2, y2, color)
                end
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
                    local left1x = ex1 + ux * halfW
                    local left1y = ny1 + uy * halfW
                    local left2x = ex2 + ux * halfW
                    local left2y = ny2 + uy * halfW
                    local right1x = ex1 - ux * halfW
                    local right1y = ny1 - uy * halfW
                    local right2x = ex2 - ux * halfW
                    local right2y = ny2 - uy * halfW
                    local x1, y1 = project(left1x, left1y)
                    local x2, y2 = project(left2x, left2y)
                    local x3, y3 = project(right1x, right1y)
                    local x4, y4 = project(right2x, right2y)
                    sasl.gl.drawLine(x1, y1, x2, y2, runwayColor)
                    sasl.gl.drawLine(x3, y3, x4, y4, runwayColor)
                    local mx = (left1x + right1x) * 0.5
                    local my = (left1y + right1y) * 0.5
                    local mx2 = (left2x + right2x) * 0.5
                    local my2 = (left2y + right2y) * 0.5
                    local cx1, cy1 = project(mx, my)
                    local cx2, cy2 = project(mx2, my2)
                    sasl.gl.drawLine(cx1, cy1, cx2, cy2, runwayColor)

                    local labelOff = halfW + 12
                    local headOff = 18
                    local l1x = ex1 - ax * headOff + ux * labelOff
                    local l1y = ny1 - ay * headOff + uy * labelOff
                    local l2x = ex2 + ax * headOff - ux * labelOff
                    local l2y = ny2 + ay * headOff - uy * labelOff
                    local sx1, sy1 = project(l1x, l1y)
                    local sx2, sy2 = project(l2x, l2y)
                    if rwy.rwy1 and rwy.rwy1 ~= "" then
                        drawText(font, sx1 + 2, sy1 + 2, rwy.rwy1, mapFontSize, TEXT_ALIGN_LEFT, {0.85, 0.85, 0.92, 0.95})
                    end
                    if rwy.rwy2 and rwy.rwy2 ~= "" then
                        drawText(font, sx2 + 2, sy2 + 2, rwy.rwy2, mapFontSize, TEXT_ALIGN_LEFT, {0.85, 0.85, 0.92, 0.95})
                    end
                else
                    local x1, y1 = project(ex1, ny1)
                    local x2, y2 = project(ex2, ny2)
                    sasl.gl.drawLine(x1, y1, x2, y2, runwayColor)
                    if rwy.rwy1 and rwy.rwy1 ~= "" then
                        drawText(font, x1 + 2, y1 + 2, rwy.rwy1, mapFontSize, TEXT_ALIGN_LEFT, {0.85, 0.85, 0.92, 0.95})
                    end
                    if rwy.rwy2 and rwy.rwy2 ~= "" then
                        drawText(font, x2 + 2, y2 + 2, rwy.rwy2, mapFontSize, TEXT_ALIGN_LEFT, {0.85, 0.85, 0.92, 0.95})
                    end
                end
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
                    sasl.gl.drawLine(x1, y1, x2, y2, routeShadow)
                    sasl.gl.drawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1, routeColor)
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
        if comp._selectedEndRampKey and routeData and routeData.nodes then
            for _, ramp in ipairs(routeData.ramps or {}) do
                if helpers.isRampSuitableFor738(ramp) and ramp_key(ramp) == comp._selectedEndRampKey then
                    local rx, ry = project(ramp.east, ramp.north)
                    local endNode = nil
                    if comp._route and comp._route.path then
                        local last_id = comp._route.path[#comp._route.path]
                        endNode = routeData.nodes[last_id]
                    end
                    if endNode and endNode.east and endNode.north then
                        local nx, ny = project(endNode.east, endNode.north)
                        sasl.gl.drawLine(nx, ny, rx, ry, routeShadow)
                        sasl.gl.drawLine(nx + 1, ny + 1, rx + 1, ry + 1, {1.0, 0.6, 0.25, 1})
                    end
                    break
                end
            end
        end

        if comp._data and comp._data.ramps then
            local ramp_filter = helpers.isRampSuitableFor738
            local showLabels = (comp.zoom or 1) >= 1.5
            for _, ramp in ipairs(comp._data.ramps) do
                if ramp_filter and not ramp_filter(ramp) then
                    goto continue
                end
                local key = ramp_key(ramp)
                local isSelected = (comp._selectedEndRampKey ~= nil) and (key == comp._selectedEndRampKey)
                local x, y = project(ramp.east, ramp.north)
                local color = rampColor
                local size = 4
                local rtype = string.lower(ramp.ramp_type or "")
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
                        drawText(font, x + 4, y + 2, label, mapFontSize, TEXT_ALIGN_LEFT, {0.75, 0.75, 0.8, 1})
                    end
                end
                if comp.mode == 1 then
                    layout.ramps[#layout.ramps + 1] = { x = x, y = y, key = key }
                end
                ::continue::
            end
        end

        if comp._startPoint then
            local sx, sy = project(comp._startPoint.east, comp._startPoint.north)
            drawRectangle(sx - 3, sy - 3, 6, 6, startColor)
            drawText(font, sx + 5, sy + 2, "S", mapFontSize, TEXT_ALIGN_LEFT, startColor)
        end
        if comp._selectedEndRampKey and comp._endRamp and comp._endRamp.east and comp._endRamp.north then
            local ex, ey = project(comp._endRamp.east, comp._endRamp.north)
            drawRectangle(ex - 4, ey - 4, 8, 8, endColor)
            drawText(font, ex + 6, ey + 2, "E", mapFontSize, TEXT_ALIGN_LEFT, endColor)
        elseif comp._endPoint then
            local ex, ey = project(comp._endPoint.east, comp._endPoint.north)
            drawRectangle(ex - 3, ey - 3, 6, 6, endColor)
            drawText(font, ex + 5, ey + 2, "E", mapFontSize, TEXT_ALIGN_LEFT, endColor)
        end

        local yal = comp.yal or _G.yal
        if yal and yal.localpositionx and yal.localpositionz then
            local ax = get(yal.localpositionx)
            local az = get(yal.localpositionz)
            if ax and az then
                local axp, ayp = project(ax, -az)
                sasl.gl.drawLine(axp - 5, ayp, axp + 5, ayp, aircraftColor)
                sasl.gl.drawLine(axp, ayp - 5, axp, ayp + 5, aircraftColor)
            end
        end

        local lineHeight = math.floor((mapFontSize or 12) * 1.25)
        local lineY = map.y + map.h - lineHeight - 2
        local lines = {}
        local modeLabelText = (comp.mode == 1) and "ARRIVAL" or "DEPARTURE"
        if comp._lastIcao then
            lines[#lines + 1] = comp._lastIcao .. " | " .. modeLabelText
        else
            lines[#lines + 1] = "ICAO not available"
        end
        if comp._dataErr then
            if comp._dataErr == "global-index-pending" then
                lines[#lines + 1] = "Taxi data: indexing global apt.dat..."
            else
                lines[#lines + 1] = "Taxi data: " .. tostring(comp._dataErr)
            end
        elseif comp._data then
            local hasNodes = (comp._data.nodes and next(comp._data.nodes) ~= nil) or false
            if comp._data.route_source == "fallback" then
                lines[#lines + 1] = "Fallback taxiway graph in use"
            elseif (not comp._data.has_routes) or (not hasNodes) then
                lines[#lines + 1] = "Taxi routes missing in apt.dat"
            end
            if comp._data.entry and comp._data.entry.path then
                local src = basename(comp._data.entry.path)
                local label = "APT: " .. src
                if comp._data.route_source and comp._data.route_source ~= "" then
                    label = label .. " (" .. comp._data.route_source .. ")"
                end
                lines[#lines + 1] = label
            end
        end
        if comp._runwayName and comp._runwayName ~= "" then
            lines[#lines + 1] = "Runway " .. comp._runwayName
        end
        if comp._data and comp._data.runways then
            lines[#lines + 1] = "Runways " .. tostring(#comp._data.runways)
        end
        if comp._startRamp and comp._startRamp.name and comp._startRamp.name ~= "" then
            local label = short_ramp_label(comp._startRamp)
            if label ~= "" then
                lines[#lines + 1] = "Start " .. label
            end
        elseif comp._startIsAircraft then
            lines[#lines + 1] = "Start Aircraft"
        end
        if comp._endRamp and comp._endRamp.name and comp._endRamp.name ~= "" then
            local label = short_ramp_label(comp._endRamp)
            if label ~= "" then
                lines[#lines + 1] = "End " .. label
            end
        end
        if comp._route then
            lines[#lines + 1] = "Route OK"
        elseif comp._routeErr then
            lines[#lines + 1] = "Route: " .. tostring(comp._routeErr)
        else
            lines[#lines + 1] = "Route: n/a"
        end
        if (comp._routeErr or comp._dataErr) and comp._routeDebug then
            local dbg = comp._routeDebug
            if dbg.start_lat and dbg.start_lon then
                lines[#lines + 1] = string.format("Start LL %.5f %.5f", dbg.start_lat, dbg.start_lon)
            end
            if dbg.start_node_id then
                lines[#lines + 1] = string.format("Start node %s (%.0fm)", tostring(dbg.start_node_id), dbg.start_node_dist or 0)
            end
            if dbg.end_lat and dbg.end_lon then
                lines[#lines + 1] = string.format("End LL %.5f %.5f", dbg.end_lat, dbg.end_lon)
            end
            if dbg.end_node_id then
                lines[#lines + 1] = string.format("End node %s (%.0fm)", tostring(dbg.end_node_id), dbg.end_node_dist or 0)
            end
        end
        local info = string.format("Zoom %.2fx | Font %d | %s",
            comp.zoom or 1.0,
            math.floor(comp.fontSize + 0.5),
            (comp.orientation == 1) and "Heading Up" or "North Up")
        lines[#lines + 1] = info

        for i = 1, #lines do
            drawText(font, map.x + 8, lineY - (i - 1) * lineHeight, lines[i], mapFontSize, TEXT_ALIGN_LEFT, {0.7, 0.7, 0.8, 1})
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
                elseif b.action == "center" then
                    if not center_on_aircraft() then
                        if comp._fitBounds then
                            local cx, cy = compute_bounds_center(comp._fitBounds)
                            set_center(cx, cy)
                        end
                    end
                    commitSettings()
                elseif b.action == "font_down" then
                    comp.fontSize = clamp(comp.fontSize - 1, minFont, maxFont)
                    comp._fontHandle = nil
                    commitSettings()
                elseif b.action == "font_up" then
                    comp.fontSize = clamp(comp.fontSize + 1, minFont, maxFont)
                    comp._fontHandle = nil
                    commitSettings()
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
                else
                    comp._selectedEndRampKey = best.key
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
        local now = 0
        if comp._timer then
            now = sasl.getElapsedSeconds(comp._timer) or 0
        end
        if comp._lastUpdate and (now - comp._lastUpdate) < updateInterval then
            return
        end
        comp._lastUpdate = now

        local yal = comp.yal or _G.yal
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
        local icao = nil
        if mode == 0 then
            icao = depIcao
            if not helpers.isvalidicao(icao or "") and yal.nearesticao then
                local nearest = normalize_icao(get(yal.nearesticao) or "")
                if helpers.isvalidicao(nearest) then
                    icao = nearest
                end
            end
        else
            icao = desIcao
            if not helpers.isvalidicao(icao or "") and comp._lastArrivalIcao then
                icao = comp._lastArrivalIcao
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
            return
        end

        local icao_changed = (comp._lastIcao ~= icao)
        local mode_changed = (comp._lastMode ~= mode)
        if icao_changed or mode_changed then
            comp._needsCenter = true
            comp._route = nil
            comp._routeErr = nil
            comp._routeLabels = nil
            comp._startPoint = nil
            comp._endPoint = nil
            comp._startRamp = nil
            comp._endRamp = nil
            comp._lastStartKey = nil
            comp._lastEndKey = nil
            comp._routeExtraSegments = nil
            comp._lastGuidanceNodeId = nil
            comp._lastGuidanceLabel = nil
            comp._lastGuidanceTime = nil
            if icao_changed then
                comp._selectedEndRampKey = nil
                comp._data = nil
                comp._dataErr = nil
            end
        end

        comp._lastIcao = icao
        comp._lastMode = mode

        local data = comp._data
        local derr = comp._dataErr
        local pending = (derr == "global-index-pending")
        if icao_changed or (not data and (not derr or pending)) then
            data, derr = helpers.getTaxiData(icao)
            pending = (derr == "global-index-pending")
        end
        if not data then
            comp._data = nil
            comp._dataErr = pending and "global-index-pending" or (derr or "apt-not-found")
            comp._fitBounds = nil
            comp._runwayName = nil
            comp._routeExtraSegments = nil
            return
        end
        comp._data = data
        comp._dataErr = nil
        comp._fitBounds = data.bounds
        local hasNodes = (data.nodes and next(data.nodes) ~= nil) or false
        local canRoute = data.can_route and hasNodes

        local aircraft = nil
        local lat = yal.aircraftlatpos and get(yal.aircraftlatpos) or nil
        local lon = yal.aircraftlonpos and get(yal.aircraftlonpos) or nil
        if is_valid_latlon(lat, lon) then
            local east, north = latlon_to_local(lat, lon)
            if east and north then
                aircraft = { lat = lat, lon = lon, east = east, north = north }
            end
        end

        local start_lat = nil
        local start_lon = nil
        local end_lat = nil
        local end_lon = nil
        local runway_lat = nil
        local runway_lon = nil
        local runway_name = ""
        local touchdown = nil
        local landing_profile = nil
        local backtrack_required = false
        local dep_holdshort_id = nil
        local arr_exit_id = nil

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
                            end_lat = hs.lat
                            end_lon = hs.lon
                        end
                    end
                end
            end
            if not is_valid_latlon(end_lat, end_lon) then
                end_lat = runway_lat
                end_lon = runway_lon
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
            runway_name = yal.desrwy and helpers.forceCleanString(get(yal.desrwy) or "") or ""
            if runway_name ~= "" then
                comp._lastArrivalRunwayName = runway_name
            elseif comp._lastArrivalRunwayName then
                runway_name = comp._lastArrivalRunwayName
            end
            comp._runwayName = runway_name
            local raw_desrwy = yal.desrwy and helpers.forceCleanString(get(yal.desrwy) or "") or ""
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
        if mode == 1 and is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
            if comp._selectedEndRampKey and data and data.ramps then
                for _, ramp in ipairs(data.ramps) do
                    if helpers.isRampSuitableFor738(ramp) and ramp_key(ramp) == comp._selectedEndRampKey then
                        end_ramp = ramp
                        user_selected_end = true
                        break
                    end
                end
            end
            if not end_ramp then
                end_ramp = helpers.getNearestRamp(icao, ramp_ref_lat, ramp_ref_lon, { filter = helpers.isRampSuitableFor738, data = data })
            end
            if end_ramp and is_valid_latlon(end_ramp.lat, end_ramp.lon) then
                end_lat = end_ramp.lat
                end_lon = end_ramp.lon
            end
        end
        if mode == 1 and (not is_valid_latlon(end_lat, end_lon)) and is_valid_latlon(ramp_ref_lat, ramp_ref_lon) then
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
        comp._depHoldshortNodeId = dep_holdshort_id

        local start_node_id, start_node_dist = nearest_node_info(data, start_lat, start_lon)
        local end_node_id, end_node_dist = nearest_node_info(data, end_lat, end_lon)
        comp._routeDebug = {
            start_lat = start_lat,
            start_lon = start_lon,
            end_lat = end_lat,
            end_lon = end_lon,
            start_node_id = start_node_id,
            start_node_dist = start_node_dist,
            end_node_id = end_node_id,
            end_node_dist = end_node_dist
        }

        if comp._rerouteOverride and is_valid_latlon(comp._rerouteOverride.lat, comp._rerouteOverride.lon) then
            start_lat = comp._rerouteOverride.lat
            start_lon = comp._rerouteOverride.lon
        end

        local start_key = string.format("%.6f|%.6f", start_lat or 0, start_lon or 0)
        local end_key = string.format("%.6f|%.6f", end_lat or 0, end_lon or 0)
        if comp._lastStartKey ~= start_key or comp._lastEndKey ~= end_key or comp._route == nil then
            comp._lastStartKey = start_key
            comp._lastEndKey = end_key
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
                helpers.logInfoTS(
                    "TaxiDiag: nodes start=" .. fmt_node_latlon(start_node_id) .. " d=" .. tostring(start_node_dist or "?") ..
                    " end=" .. fmt_node_latlon(end_node_id) .. " d=" .. tostring(end_node_dist or "?") ..
                    " depHS=" .. fmt_node_latlon(dep_holdshort_id) ..
                    " arrExit=" .. fmt_node_latlon(arr_exit_id)
                )
                helpers.logInfoTS(
                    "TaxiDiag: onGround=" .. tostring(onGround) .. " gs=" .. tostring(groundspeed)
                )
                local opts = { data = data }
                if mode == 0 then
                    opts.avoid_runway_end = true
                    opts.runway_penalty = 500
                    opts.disallow_runway_edges = true
                    opts.avoid_runway_nodes = true
                    if dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                        opts.end_node_id = dep_holdshort_id
                    end
                    if start_ramp and start_ramp.node_id then
                        opts.start_node_id = start_ramp.node_id
                        opts.allow_far_ramp = true
                    end
                elseif mode == 1 then
                    if arr_exit_id and data.nodes and data.nodes[arr_exit_id] then
                        opts.start_node_id = arr_exit_id
                    elseif not backtrack_required then
                        opts.avoid_runway_start = true
                    end
                    opts.runway_penalty = 500
                    if user_selected_end and end_ramp and end_ramp.node_id then
                        opts.end_node_id = end_ramp.node_id
                        opts.allow_far_ramp = true
                    end
                end
                local route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
                if (not route) and rerr == "no-path" and mode == 0 then
                    opts = {
                        ignore_oneway = true,
                        allow_far_ramp = true,
                        disallow_runway_edges = true,
                        avoid_runway_nodes = true,
                        data = data
                    }
                    if dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                        opts.end_node_id = dep_holdshort_id
                    end
                    if start_ramp and start_ramp.node_id then
                        opts.start_node_id = start_ramp.node_id
                    end
                    route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
                end
                if (not route) and rerr == "no-path" and mode == 0 and is_valid_latlon(start_lat, start_lon) then
                    local sx, sy = latlon_to_local(start_lat, start_lon)
                    local candidates = collect_nearest_nodes(data, sx, sy, 18)
                    if #candidates > 0 then
                        opts = {
                            ignore_oneway = true,
                            allow_far_ramp = true,
                            disallow_runway_edges = true,
                            avoid_runway_nodes = true,
                            data = data
                        }
                        if dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                            opts.end_node_id = dep_holdshort_id
                        end
                        local alt_route = try_route_from_candidates(icao, data, end_lat, end_lon, candidates, opts)
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
                            avoid_runway_nodes = true,
                            data = data
                        }
                        if dep_holdshort_id and data.nodes and data.nodes[dep_holdshort_id] then
                            opts.end_node_id = dep_holdshort_id
                        end
                        local alt_route = try_route_to_candidates(icao, data, start_lat, start_lon, candidates, opts)
                        if alt_route then
                            route = alt_route
                            rerr = nil
                        end
                    end
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { data = data }
                    if not backtrack_required then
                        opts.avoid_runway_start = true
                    end
                    if user_selected_end and end_ramp and end_ramp.node_id then
                        opts.end_node_id = end_ramp.node_id
                        opts.allow_far_ramp = true
                    end
                    route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { ignore_oneway = true, data = data }
                    if not backtrack_required then
                        opts.avoid_runway_start = true
                    end
                    if user_selected_end and end_ramp and end_ramp.node_id then
                        opts.end_node_id = end_ramp.node_id
                        opts.allow_far_ramp = true
                    end
                    route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { data = data }
                    if not backtrack_required then
                        opts.runway_penalty = 500
                    end
                    if user_selected_end and end_ramp and end_ramp.node_id then
                        opts.end_node_id = end_ramp.node_id
                        opts.allow_far_ramp = true
                    end
                    route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { ignore_oneway = true, data = data }
                    if user_selected_end and end_ramp and end_ramp.node_id then
                        opts.end_node_id = end_ramp.node_id
                        opts.allow_far_ramp = true
                    end
                    route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { allow_far_ramp = true, data = data }
                    if not backtrack_required then
                        opts.avoid_runway_start = true
                        opts.runway_penalty = 500
                    end
                    if user_selected_end and end_ramp and end_ramp.node_id then
                        opts.end_node_id = end_ramp.node_id
                    end
                    route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
                end
                if (not route) and rerr == "no-path" and mode == 1 then
                    opts = { allow_far_ramp = true, ignore_oneway = true, data = data }
                    if user_selected_end and end_ramp and end_ramp.node_id then
                        opts.end_node_id = end_ramp.node_id
                    end
                    route, rerr = helpers.getTaxiRoute(icao, start_lat, start_lon, end_lat, end_lon, opts)
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
                            opts = { allow_far_ramp = true, ignore_oneway = true, data = data }
                            if not backtrack_required then
                                opts.runway_penalty = 500
                            end
                            local alt_route, alt_err, alt_lat, alt_lon = try_route_from_candidates(icao, data, end_lat, end_lon, candidates, opts)
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
                        opts = { allow_far_ramp = true, ignore_oneway = true, data = data }
                        if not backtrack_required then
                            opts.runway_penalty = 500
                        end
                        local alt_route, alt_err, alt_lat, alt_lon = try_route_to_candidates(icao, data, start_lat, start_lon, candidates, opts)
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
                        opts = { allow_far_ramp = true, ignore_oneway = true, data = data }
                        if not backtrack_required then
                            opts.runway_penalty = 500
                        end
                        local alt_route, alt_err, alt_lat, alt_lon = try_route_to_candidates(icao, data, start_lat, start_lon, candidates, opts)
                        if alt_route then
                            route = alt_route
                            rerr = alt_err
                        end
                    end
                end
                comp._route = route
                comp._routeErr = rerr
                comp._routeLabels = route and build_route_labels(route.data, route.path) or nil
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
                elseif rerr then
                    helpers.logInfoTS("Taxi: route error " .. tostring(icao) .. " mode=" .. tostring(mode) .. " err=" .. tostring(rerr))
                end
                if route and route.bounds then
                    comp._fitBounds = route.bounds
                end
                comp._routeExtraSegments = nil
                if route and route.path and data and comp._runwayName and comp._runwayName ~= "" then
                    local profile = compute_runway_landing_profile(data, comp._runwayName, runway_lat, runway_lon)
                    if profile then
                        local end_node = route.path[#route.path]
                        if end_node then
                            comp._routeExtraSegments = build_runway_backtrack_segments(data, profile, end_node)
                        end
                    end
                end
                comp._lastGuidanceNodeId = nil
                comp._lastGuidanceLabel = nil
                comp._lastGuidanceTime = nil
            else
                comp._route = nil
                comp._routeErr = canRoute and "route-endpoints-missing" or "no-routes"
                comp._routeLabels = nil
            end
        end

        if comp._route and aircraft and aircraft.east and aircraft.north then
            local yal = comp.yal or _G.yal
            local onGround = yal and yal.airgroundsensor and (get(yal.airgroundsensor) == def.ON)
            local tirespeed = yal and yal.tirespeed and (get(yal.tirespeed) or 0) or 0
            if onGround and tirespeed > 1 then
                local routeData = comp._route.data
                local dist = distance_to_route(routeData, comp._route.path, aircraft.east, aircraft.north)
                if comp._routeExtraSegments then
                    local extra = distance_to_segments(comp._routeExtraSegments, aircraft.east, aircraft.north)
                    if extra and (not dist or extra < dist) then
                        dist = extra
                    end
                end
                local lastReroute = comp._lastRerouteTime or 0
                if dist and dist > rerouteDriftMeters and (now - lastReroute) > rerouteCooldown then
                    comp._rerouteOverride = { lat = aircraft.lat, lon = aircraft.lon }
                    comp._lastRerouteTime = now
                    comp._lastStartKey = nil
                    comp._route = nil
                    comp._routeErr = nil
                    comp._routeLabels = nil
                end
            end
        end

        if comp._route then
            maybe_speak_guidance(comp, now, aircraft)
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

        if comp._needsCenter and comp._fitBounds then
            local cx, cy = compute_bounds_center(comp._fitBounds)
            set_center(cx, cy)
            comp._needsCenter = false
        end
    end

    function comp:tick()
        local ww = defaultW
        local hh = defaultH
        if comp._window and comp._window.getPosition then
            local _, _, wpos, hpos = comp._window:getPosition()
            ww = tonumber(wpos) or ww
            hh = tonumber(hpos) or hh
        end
        local vis = comp._window and comp._window.isVisible and comp._window:isVisible() or false
        if vis and not comp._lastVisible then
            if comp._data and comp._data.bounds then
                comp._fitBounds = comp._data.bounds
            end
            comp._needsCenter = true
        end
        comp._lastVisible = vis
        local mapW = math.max(120, ww - mapPadding * 2)
        local mapH = math.max(120, hh - headerH - toolbarH - mapPadding * 2)
        local map = {
            x = mapPadding,
            y = mapPadding,
            w = mapW,
            h = mapH
        }
        self:updateTaxiState(map)
    end

    return comp
end

return M
