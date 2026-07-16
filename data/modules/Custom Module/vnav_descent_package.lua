local M = {}

M.TARGET_RELATIVE_PATH = "plugins/xlua/scripts/B738.a_fms/B738.a_fms.lua"

local LEVELUP_ACF_STEMS = {
    ["737_60ng"] = true,
    ["737_70ng"] = true,
    ["737_80ng"] = true,
    ["737_90ng"] = true,
    ["737_9eng"] = true,
}

local ZIBO_ACF_STEMS = {
    ["b738"] = true,
    ["b738_4k"] = true,
}

local function clean_text(value)
    local text = tostring(value or ""):gsub("%z", "")
    return text:match("^%s*(.-)%s*$") or ""
end

local function parse_aircraft_relative_path(raw)
    local text = clean_text(raw):gsub("\\", "/")
    if text == "" then
        return nil, "aircraft path not available"
    end
    if text:sub(1, 1) == "/" or text:match("^%a:") then
        return nil, "aircraft path is not relative"
    end

    local parts = {}
    for part in text:gmatch("[^/]+") do
        if part == "." or part == ".." then
            return nil, "aircraft path contains an unsafe segment"
        end
        parts[#parts + 1] = part
    end
    if #parts < 2 or string.lower(parts[1]) ~= "aircraft" then
        return nil, "aircraft path is outside the X-Plane Aircraft folder"
    end

    local acfName = parts[#parts]
    if #acfName < 5 or string.lower(acfName:sub(-4)) ~= ".acf" then
        return nil, "loaded aircraft file is not an ACF"
    end
    local acfStem = string.lower(acfName:sub(1, -5))
    parts[#parts] = nil

    return {
        normalized = table.concat(parts, "/") .. "/" .. acfName,
        root_relative = table.concat(parts, "/"),
        acf_name = acfName,
        acf_stem = acfStem,
    }
end

local function strip_trailing_separators(path)
    while #path > 1 do
        local last = path:sub(-1)
        if last ~= "/" and last ~= "\\" then break end
        path = path:sub(1, -2)
    end
    return path
end

local function platform_path(path, separator)
    if separator == "\\" then
        return path:gsub("/", "\\")
    end
    return path:gsub("\\", "/")
end

local function join_path(base, relative, separator)
    local root = strip_trailing_separators(clean_text(base))
    if root == "" then return nil end
    return root .. separator .. platform_path(relative, separator)
end

local function default_file_exists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function result_for(status, reason, details)
    details = details or {}
    details.status = status
    details.reason = reason
    details.patchable = status == "supported"
    return details
end

function M.detectLoadedAircraft(input)
    input = input or {}
    local pathInfo, pathError = parse_aircraft_relative_path(input.acf_relative_path)
    if not pathInfo then
        return result_for("invalid_aircraft_path", pathError)
    end

    local separator = input.separator == "\\" and "\\" or "/"
    local aircraftRoot = join_path(input.xplane_path, pathInfo.root_relative, separator)
    if not aircraftRoot then
        return result_for("invalid_aircraft_path", "X-Plane path not available", pathInfo)
    end

    local details = {
        family = nil,
        aircraft_root = aircraftRoot,
        aircraft_relative_path = pathInfo.normalized,
        acf_name = pathInfo.acf_name,
        acf_stem = pathInfo.acf_stem,
        target_relative_path = M.TARGET_RELATIVE_PATH,
        target_path = join_path(aircraftRoot, M.TARGET_RELATIVE_PATH, separator),
        levelup_release = clean_text(input.levelup_release),
        levelup_flight_model = clean_text(input.levelup_flight_model),
        zibo_runtime = input.zibo_runtime == true,
    }

    local levelUpRuntime = details.levelup_release ~= "" or details.levelup_flight_model ~= ""
    local levelUpAcf = LEVELUP_ACF_STEMS[pathInfo.acf_stem] == true
    local ziboAcf = ZIBO_ACF_STEMS[pathInfo.acf_stem] == true

    if levelUpRuntime then
        if not levelUpAcf then
            return result_for(
                "conflicting_family",
                "LevelUp runtime DataRefs do not match the loaded ACF",
                details
            )
        end
        details.family = "levelup_737ng"
    elseif levelUpAcf then
        return result_for(
            "runtime_not_ready",
            "LevelUp ACF detected but LevelUp runtime DataRefs are not ready",
            details
        )
    elseif ziboAcf then
        if not details.zibo_runtime then
            return result_for(
                "runtime_not_ready",
                "Zibo ACF detected but the Zibo runtime is not ready",
                details
            )
        end
        details.family = "zibo_upstream"
    else
        return result_for(
            "unsupported_aircraft",
            "loaded ACF is not a supported Zibo or LevelUp aircraft",
            details
        )
    end

    local fileExists = type(input.file_exists) == "function" and input.file_exists or default_file_exists
    local ok, targetExists = pcall(fileExists, details.target_path)
    details.target_exists = ok and targetExists == true
    if not details.target_exists then
        return result_for(
            "not_applicable_no_lua",
            "B738.a_fms.lua is not present in the loaded aircraft installation",
            details
        )
    end

    return result_for(
        "supported",
        "loaded aircraft has a supported XLua VNAV target",
        details
    )
end

return M
