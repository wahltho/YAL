local M = {}

local RNAV_ROUTE_TYPES = { ["4"] = true, ["5"] = true, ["6"] = true }
local CONVENTIONAL_ROUTE_TYPES = { ["1"] = true, ["2"] = true, ["3"] = true }
local FMS_ROUTE_TYPES = { F = true, M = true, S = true }
local VECTOR_ROUTE_TYPES = { T = true, V = true }

local function clean(value)
    local text = tostring(value or "")
    text = text:gsub("%z", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return string.upper(text)
end

local function splitCsv(line)
    local fields = {}
    local startIndex = 1
    for index = 1, #line do
        if string.byte(line, index) == 44 then
            fields[#fields + 1] = string.sub(line, startIndex, index - 1)
            startIndex = index + 1
        end
    end
    fields[#fields + 1] = string.sub(line, startIndex)
    return fields
end

local function normalizeRunway(value)
    local runway = clean(value):gsub("^RW", "")
    local numberText, suffix = runway:match("^(%d%d?)([LRC]?)$")
    local number = tonumber(numberText)
    if not number or number < 1 or number > 36 then
        return ""
    end
    return string.format("RW%02d%s", number, suffix or "")
end

local function normalizeSelection(value)
    local selection = clean(value)
    if selection == "" or selection == "------" or selection == "NONE" then
        return ""
    end
    return selection
end

local function hashText(value)
    local hash = 0
    for index = 1, #value do
        hash = (hash * 131 + string.byte(value, index)) % 2147483647
    end
    return string.format("%08x", hash)
end

function M.contextSignature(context)
    context = context or {}
    local identity = table.concat({
        clean(context.icao),
        normalizeRunway(context.runway),
        normalizeSelection(context.sid),
        normalizeSelection(context.transition),
        clean(context.legs)
    }, "|")
    return hashText(identity)
end

local function routeFamily(routeType)
    if RNAV_ROUTE_TYPES[routeType] then return "rnav" end
    if CONVENTIONAL_ROUTE_TYPES[routeType] then return "conventional" end
    if FMS_ROUTE_TYPES[routeType] then return "fms" end
    if VECTOR_ROUTE_TYPES[routeType] then return "vector" end
    return "other"
end

local function rowApplies(fields, runway, transition)
    local routeType = clean(fields[2])
    local routeTransition = clean(fields[4])

    if routeType == "3" then
        return transition ~= "" and routeTransition == transition
    end
    if routeTransition == "" or routeTransition == "ALL" or routeTransition == "RWY" then
        return true
    end
    return normalizeRunway(routeTransition) == runway
end

local function roundedCourse(raw)
    local value = tonumber(clean(raw))
    if not value then return nil end
    local course = math.floor((value / 10) + 0.5) % 360
    return course
end

local function candidateKey(candidate)
    return table.concat({
        candidate.ident,
        tostring(candidate.frequency),
        tostring(candidate.course)
    }, "|")
end

function M.resolve(context)
    context = context or {}
    local signature = M.contextSignature(context)
    local icao = clean(context.icao)
    local runway = normalizeRunway(context.runway)
    local sid = normalizeSelection(context.sid)
    local transition = normalizeSelection(context.transition)
    local lines = context.cifpLines

    if #icao ~= 4 or runway == "" or sid == "" then
        return { status = "no_selection", signature = signature }
    end
    if type(lines) ~= "table" or type(context.lookupNavaid) ~= "function" then
        return { status = "data_unavailable", signature = signature }
    end

    local matchingRows = {}
    local families = {}
    for _, line in ipairs(lines) do
        if type(line) == "string" and string.sub(line, 1, 4) == "SID:" then
            local fields = splitCsv(line)
            if clean(fields[3]) == sid then
                matchingRows[#matchingRows + 1] = fields
                families[routeFamily(clean(fields[2]))] = true
            end
        end
    end

    if #matchingRows == 0 then
        return { status = "sid_not_found", signature = signature }
    end

    local familyCount = 0
    local selectedFamily = nil
    for family in pairs(families) do
        if family ~= "other" then
            familyCount = familyCount + 1
            selectedFamily = family
        end
    end
    if familyCount ~= 1 then
        return { status = "ambiguous_family", signature = signature }
    end
    if selectedFamily ~= "conventional" then
        return { status = selectedFamily, signature = signature }
    end

    local candidates = {}
    local candidateKeys = {}
    for _, fields in ipairs(matchingRows) do
        if CONVENTIONAL_ROUTE_TYPES[clean(fields[2])] and rowApplies(fields, runway, transition) then
            local ident = clean(fields[14])
            local region = clean(fields[15])
            local section = clean(fields[16])
            local course = roundedCourse(fields[21])
            if ident ~= "" and section == "D" and course ~= nil then
                local navaid = context.lookupNavaid(ident, region)
                local navType = navaid and tonumber(navaid.type) or nil
                local frequency = navaid and tonumber(navaid.frequency) or nil
                if navaid and (navType == 1 or navType == 2)
                    and frequency and frequency >= 10800 and frequency <= 11795 then
                    local candidate = {
                        ident = ident,
                        region = region,
                        frequency = math.floor(frequency + 0.5),
                        course = course,
                        navType = navType,
                        source = navaid._source
                    }
                    local key = candidateKey(candidate)
                    if not candidateKeys[key] then
                        candidateKeys[key] = true
                        candidates[#candidates + 1] = candidate
                    end
                end
            end
        end
    end

    if #candidates == 0 then
        return { status = "no_explicit_raw_data", signature = signature }
    end
    if #candidates ~= 1 then
        return { status = "ambiguous_raw_data", signature = signature }
    end

    return {
        status = "actionable",
        signature = signature,
        icao = icao,
        runway = runway,
        sid = sid,
        transition = transition,
        captain = candidates[1]
    }
end

return M
