local sha256 = require("sha256")

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

function M.normalizeDownloadedText(value)
    local text = tostring(value or "")
    local removed = 0
    while #text > 0 and string.byte(text, #text) == 0 do
        text = string.sub(text, 1, #text - 1)
        removed = removed + 1
    end
    return text, removed
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

local REQUIRED_OPERATIONS = { "dofile", "kias", "mach" }
local REQUIRED_PAYLOADS = { "table", "dofile", "kias", "mach" }

local function split_pipe(line)
    local parts = {}
    local start = 1
    while true do
        local separator = line:find("|", start, true)
        if not separator then
            parts[#parts + 1] = line:sub(start)
            break
        end
        parts[#parts + 1] = line:sub(start, separator - 1)
        start = separator + 1
    end
    return parts
end

local function join_pipe(parts, first)
    local values = {}
    for index = first, #parts do values[#values + 1] = parts[index] end
    return table.concat(values, "|")
end

local function set_once(target, key, value, label)
    if target[key] ~= nil then
        return false, "duplicate manifest field: " .. tostring(label or key)
    end
    target[key] = value
    return true
end

local function is_safe_payload_name(name)
    if name == "" or name == "." or name == ".." then return false end
    if name:find("/", 1, true) or name:find("\\", 1, true) or name:find(":", 1, true) then
        return false
    end
    return not name:find("..", 1, true)
end

local function valid_sha256(value)
    return #value == 64 and value:match("^[0-9a-fA-F]+$") ~= nil
end

local function validate_version(value)
    return value ~= "" and #value <= 64 and value:match("^[%w%.%_%-]+$") ~= nil
end

function M.parseManifest(text, expected)
    text = tostring(text or "")
    expected = expected or {}
    if text == "" then return nil, "manifest is empty" end
    if #text > 131072 then return nil, "manifest is too large" end
    if text:find("\0", 1, true) then return nil, "manifest contains a NUL byte" end

    local manifest = {
        payloads = {},
        anchors = {},
        markers = {},
        legacy = {},
    }

    for rawLine in text:gmatch("[^\r\n]+") do
        local line = clean_text(rawLine)
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local parts = split_pipe(line)
            local kind = parts[1]
            local ok, err = true, nil
            if kind == "schema" and #parts == 3 and parts[2] == "package-manifest" then
                ok, err = set_once(manifest, "schema_version", tonumber(parts[3]), "schema")
            elseif kind == "package" and #parts == 3 and parts[2] == "id" then
                ok, err = set_once(manifest, "package_id", parts[3], "package id")
            elseif kind == "package" and #parts == 3 and parts[2] == "version" then
                ok, err = set_once(manifest, "package_version", parts[3], "package version")
            elseif kind == "package" and #parts == 3 and parts[2] == "release_tag" then
                ok, err = set_once(manifest, "release_tag", parts[3], "release tag")
            elseif kind == "aircraft" and #parts == 3 and parts[2] == "family" then
                ok, err = set_once(manifest, "aircraft_family", parts[3], "aircraft family")
            elseif kind == "repository" and #parts == 3 and parts[2] == "url" then
                ok, err = set_once(manifest, "repository_url", parts[3], "repository URL")
            elseif kind == "target" and #parts == 3 and parts[2] == "relative_path" then
                ok, err = set_once(manifest, "target_relative_path", parts[3], "target path")
            elseif kind == "payload" then
                if #parts ~= 7 or parts[4] ~= "size" or parts[6] ~= "sha256" then
                    return nil, "invalid payload manifest line"
                end
                local role = parts[2]
                local size = tonumber(parts[5])
                if manifest.payloads[role] then return nil, "duplicate payload role: " .. tostring(role) end
                if not is_safe_payload_name(parts[3]) then return nil, "unsafe payload filename" end
                if not size or size < 1 or size ~= math.floor(size) then return nil, "invalid payload size" end
                if not valid_sha256(parts[7]) then return nil, "invalid payload SHA-256" end
                manifest.payloads[role] = {
                    role = role,
                    filename = parts[3],
                    size = size,
                    sha256 = string.lower(parts[7]),
                }
            elseif kind == "anchor" and #parts >= 3 then
                local operation = parts[2]
                if manifest.anchors[operation] then return nil, "duplicate anchor: " .. tostring(operation) end
                manifest.anchors[operation] = join_pipe(parts, 3)
            elseif kind == "marker" and #parts >= 4 then
                local operation = parts[2]
                local boundary = parts[3]
                if boundary ~= "begin" and boundary ~= "end" then return nil, "invalid marker boundary" end
                manifest.markers[operation] = manifest.markers[operation] or {}
                if manifest.markers[operation][boundary] then
                    return nil, "duplicate marker: " .. tostring(operation) .. " " .. boundary
                end
                manifest.markers[operation][boundary] = join_pipe(parts, 4)
            elseif kind == "legacy" and #parts >= 4 then
                local operation = parts[3]
                manifest.legacy[operation] = manifest.legacy[operation] or {}
                manifest.legacy[operation][#manifest.legacy[operation] + 1] = join_pipe(parts, 4)
            end
            if not ok then return nil, err end
        end
    end

    if manifest.schema_version ~= 1 then return nil, "unsupported manifest schema" end
    if not validate_version(manifest.package_version or "") then return nil, "invalid package version" end
    if not validate_version(manifest.release_tag or "") then return nil, "invalid release tag" end
    if manifest.package_id == nil or manifest.package_id == "" then return nil, "package id missing" end
    if manifest.aircraft_family == nil or manifest.aircraft_family == "" then return nil, "aircraft family missing" end
    if manifest.repository_url == nil or manifest.repository_url == "" then return nil, "repository URL missing" end
    if manifest.target_relative_path ~= M.TARGET_RELATIVE_PATH then return nil, "unexpected target path" end
    if expected.package_id and manifest.package_id ~= expected.package_id then return nil, "unexpected package id" end
    if expected.aircraft_family and manifest.aircraft_family ~= expected.aircraft_family then
        return nil, "manifest aircraft family does not match the loaded aircraft"
    end
    if expected.repository_url and manifest.repository_url ~= expected.repository_url then
        return nil, "unexpected repository URL"
    end

    for _, role in ipairs(REQUIRED_PAYLOADS) do
        if not manifest.payloads[role] then return nil, "required payload missing: " .. role end
    end
    for role in pairs(manifest.payloads) do
        local known = false
        for _, required in ipairs(REQUIRED_PAYLOADS) do
            if role == required then known = true break end
        end
        if not known then return nil, "unsupported payload role: " .. tostring(role) end
    end
    for _, operation in ipairs(REQUIRED_OPERATIONS) do
        local markers = manifest.markers[operation]
        if not manifest.anchors[operation] or manifest.anchors[operation] == "" then
            return nil, "required anchor missing: " .. operation
        end
        if not markers or not markers.begin or markers.begin == "" or not markers["end"] or markers["end"] == "" then
            return nil, "required markers missing: " .. operation
        end
        if markers.begin == markers["end"] then return nil, "identical begin/end markers" end
    end

    return manifest
end

local function read_binary_file(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err or "open failed" end
    local data = file:read("*a")
    file:close()
    if data == nil then return nil, "read failed" end
    return data
end

local function split_lines(data)
    local normalized = tostring(data or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    local start = 1
    while true do
        local ending = normalized:find("\n", start, true)
        if not ending then
            lines[#lines + 1] = normalized:sub(start)
            break
        end
        lines[#lines + 1] = normalized:sub(start, ending - 1)
        start = ending + 1
    end
    return lines
end

local function line_ending(data)
    local crlf = 0
    local lf = 0
    local cr = 0
    local index = 1
    while index <= #data do
        local byte = data:byte(index)
        if byte == 13 and data:byte(index + 1) == 10 then
            crlf = crlf + 1
            index = index + 2
        elseif byte == 10 then
            lf = lf + 1
            index = index + 1
        elseif byte == 13 then
            cr = cr + 1
            index = index + 1
        else
            index = index + 1
        end
    end
    local kinds = (crlf > 0 and 1 or 0) + (lf > 0 and 1 or 0) + (cr > 0 and 1 or 0)
    if kinds > 1 then return "Mixed" end
    if crlf > 0 then return "CRLF" end
    if lf > 0 then return "LF" end
    if cr > 0 then return "CR" end
    return "None"
end

local function contains_plain(text, needle)
    return needle ~= "" and text:find(needle, 1, true) ~= nil
end

local function is_commented(line)
    local trimmed = line:match("^%s*(.*)$") or line
    return trimmed:sub(1, 2) == "--"
end

local function matching_indices(lines, needle)
    local result = {}
    for index, line in ipairs(lines) do
        if contains_plain(line, needle) then result[#result + 1] = index end
    end
    return result
end

local function count_active(lines, needle)
    local count = 0
    for _, line in ipairs(lines) do
        if contains_plain(line, needle) and not is_commented(line) then count = count + 1 end
    end
    return count
end

local function metadata_in_block(lines, first, last, key)
    local prefix = "-- " .. key .. "|"
    local values = {}
    for index = first, last do
        local trimmed = lines[index]:match("^%s*(.-)%s*$") or ""
        if trimmed:sub(1, #prefix) == prefix then values[#values + 1] = trimmed:sub(#prefix + 1) end
    end
    if #values == 1 then return values[1], 1, values end
    return nil, #values, values
end

local function canonical_block(lines, first, last, expectedSize)
    local content = {}
    for index = first, last do content[#content + 1] = lines[index] end
    local withoutFinal = table.concat(content, "\n")
    local withFinal = withoutFinal .. "\n"
    if #withoutFinal == expectedSize then return withoutFinal end
    return withFinal
end

local function analyze_operation(lines, operation, manifest)
    local markers = manifest.markers[operation]
    local payload = manifest.payloads[operation]
    local beginIndices = matching_indices(lines, markers.begin)
    local endIndices = matching_indices(lines, markers["end"])
    local finding = {
        id = operation,
        begin_count = #beginIndices,
        end_count = #endIndices,
    }

    if #beginIndices > 0 or #endIndices > 0 then
        if #beginIndices ~= 1 or #endIndices ~= 1 or beginIndices[1] >= endIndices[1] then
            finding.state = "marker_conflict"
            finding.detail = operation .. ": marker mismatch, order error or duplicate marker"
            return finding
        end

        local first, last = beginIndices[1], endIndices[1]
        local block = canonical_block(lines, first, last, payload.size)
        local packageId, packageIdCount, packageIds = metadata_in_block(lines, first, last, "package-id")
        local packageVersion, versionCount = metadata_in_block(lines, first, last, "package-version")
        finding.local_package_id = packageId
        finding.local_version = packageVersion
        finding.size = #block
        finding.sha256 = sha256.hex(block)
        finding.marked = true

        local foreignPackageId = false
        for _, value in ipairs(packageIds or {}) do
            if value ~= manifest.package_id then foreignPackageId = true break end
        end
        if foreignPackageId then
            finding.state = "foreign_marker"
            finding.detail = operation .. ": marked block has a foreign package id"
        elseif packageIdCount ~= 1 or versionCount ~= 1 then
            finding.state = "marked_changed"
            finding.detail = operation .. ": marked block metadata is missing or duplicated"
        elseif packageVersion ~= manifest.package_version then
            finding.state = "marked_version_mismatch"
            finding.detail = operation .. ": marked block version is " .. tostring(packageVersion)
        elseif finding.size ~= payload.size or finding.sha256 ~= payload.sha256 then
            finding.state = "marked_changed"
            finding.detail = operation .. ": marked block content differs from the manifest"
        else
            finding.state = "marked_current"
            finding.detail = operation .. ": marked block matches the manifest"
        end
        return finding
    end

    local legacyCount = 0
    for _, signature in ipairs(manifest.legacy[operation] or {}) do
        legacyCount = legacyCount + count_active(lines, signature)
    end
    if legacyCount > 0 then
        finding.state = "legacy"
        finding.legacy_count = legacyCount
        finding.detail = operation .. ": known legacy hook found"
        return finding
    end

    local anchorCount = count_active(lines, manifest.anchors[operation])
    finding.anchor_count = anchorCount
    if anchorCount == 1 then
        finding.state = "not_installed"
        finding.detail = operation .. ": unique insertion anchor found"
    elseif anchorCount == 0 then
        finding.state = "missing_anchor"
        finding.detail = operation .. ": required insertion anchor not found"
    else
        finding.state = "duplicate_anchor"
        finding.detail = operation .. ": insertion anchor found more than once"
    end
    return finding
end

local function parent_path(path)
    for index = #path, 1, -1 do
        local character = path:sub(index, index)
        if character == "/" or character == "\\" then return path:sub(1, index - 1) end
    end
    return nil
end

local function analyze_table_payload(target, manifest, readFile)
    local payload = manifest.payloads.table
    local folder = parent_path(target.target_path)
    local separator = target.target_path:find("\\", 1, true) and "\\" or "/"
    local path = folder and join_path(folder, payload.filename, separator) or nil
    local finding = {
        id = "table",
        filename = payload.filename,
        path = path,
    }
    if not path then
        finding.state = "missing"
        finding.detail = "table: target script folder could not be resolved"
        return finding
    end

    local ok, data, err = pcall(readFile, path)
    if not ok then
        finding.state = "read_failed"
        finding.detail = "table: read failed"
        return finding
    end
    if data == nil then
        finding.state = "missing"
        finding.detail = "table: payload file is not present"
        finding.error = err
        return finding
    end
    data = tostring(data)
    finding.size = #data
    finding.sha256 = sha256.hex(data)
    if finding.size == payload.size and finding.sha256 == payload.sha256 then
        finding.state = "current"
        finding.detail = "table: size and SHA-256 match the manifest"
    else
        finding.state = "changed"
        finding.detail = "table: size or SHA-256 differs from the manifest"
    end
    return finding
end

local function parse_numeric_version(value)
    local major, minor, patch, suffix = tostring(value or ""):match("^v?(%d+)%.(%d+)%.(%d+)(.*)$")
    if not major or (suffix ~= nil and suffix ~= "") then return nil end
    return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function compare_versions(left, right)
    if tostring(left or "") == tostring(right or "") then return 0 end
    local a = parse_numeric_version(left)
    local b = parse_numeric_version(right)
    if not a or not b then return nil end
    for index = 1, 3 do
        if a[index] < b[index] then return -1 end
        if a[index] > b[index] then return 1 end
    end
    return 0
end

local function classify_installation(operations, tableFinding, manifest)
    local counts = {}
    local versions = {}
    local versionCount = 0
    local markedCount = 0
    for _, finding in ipairs(operations) do
        counts[finding.state] = (counts[finding.state] or 0) + 1
        if finding.marked then markedCount = markedCount + 1 end
        if finding.local_version and not versions[finding.local_version] then
            versions[finding.local_version] = true
            versionCount = versionCount + 1
        end
    end

    if counts.foreign_marker then return "unsafe_foreign", false, nil end
    if counts.marker_conflict then return "partial_damaged", false, nil end

    if markedCount == #REQUIRED_OPERATIONS then
        if versionCount > 1 then return "partial_damaged", false, nil end
        local localVersion = next(versions)
        if localVersion then
            local comparison = compare_versions(localVersion, manifest.package_version)
            if comparison == -1 then return "installed_outdated", true, localVersion end
            if comparison == 1 then return "installed_newer", false, localVersion end
            if comparison == nil then return "partial_damaged", false, localVersion end
        end
        if (counts.marked_current or 0) == #REQUIRED_OPERATIONS and tableFinding.state == "current" then
            return "installed_current", true, localVersion
        end
        return "repair_required", true, localVersion
    end

    if markedCount > 0 then return "partial_damaged", false, next(versions) end
    if counts.legacy then
        if (counts.legacy or 0) == #REQUIRED_OPERATIONS then return "installed_legacy", true, "legacy" end
        return "partial_damaged", false, "legacy"
    end
    if counts.missing_anchor or counts.duplicate_anchor then return "target_changed", false, nil end
    if (counts.not_installed or 0) == #REQUIRED_OPERATIONS then
        if tableFinding.state == "missing" then return "not_installed", true, nil end
        if tableFinding.state == "current" then return "aircraft_update_removed", true, nil end
        return "partial_damaged", false, nil
    end
    return "partial_damaged", false, nil
end

local STATUS_REASONS = {
    installed_current = "all installed VNAV package components match the current manifest",
    not_installed = "the loaded aircraft is patchable and the VNAV package is not installed",
    installed_outdated = "a complete older marked VNAV package is installed",
    installed_newer = "the installed marked VNAV package is newer than the published manifest",
    repair_required = "marked hooks exist but one or more owned components differ or are missing",
    aircraft_update_removed = "the current table payload remains but the aircraft hook blocks were removed",
    installed_legacy = "a complete known legacy VNAV package is installed",
    partial_damaged = "the VNAV package is partial, inconsistent or damaged",
    target_changed = "required patch anchors are missing or duplicated",
    unsafe_foreign = "a marked block belongs to a different package",
}

local function inspection_result(status, reason, details)
    details = details or {}
    details.status = status
    details.reason = reason
    return details
end

function M.inspectInstallation(input)
    input = input or {}
    local target = input.target
    if type(target) ~= "table" or target.status ~= "supported" or target.patchable ~= true then
        return inspection_result("target_not_supported", "loaded aircraft target is not patchable", {
            target = target,
            safe_for_future_action = false,
        })
    end

    local manifest, manifestError = M.parseManifest(input.manifest_text, input.expected)
    if not manifest then
        return inspection_result("manifest_invalid", manifestError, {
            target = target,
            safe_for_future_action = false,
        })
    end
    if manifest.aircraft_family ~= target.family then
        return inspection_result("manifest_invalid", "manifest family does not match detected target", {
            target = target,
            manifest = manifest,
            safe_for_future_action = false,
        })
    end

    local readFile = type(input.read_file) == "function" and input.read_file or read_binary_file
    local ok, targetData, targetError = pcall(readFile, target.target_path)
    if not ok or targetData == nil then
        return inspection_result("target_read_failed", tostring(targetError or "target read failed"), {
            target = target,
            manifest = manifest,
            safe_for_future_action = false,
        })
    end
    targetData = tostring(targetData)
    if #targetData > 67108864 then
        return inspection_result("target_read_failed", "target script exceeds the 64 MiB safety limit", {
            target = target,
            manifest = manifest,
            safe_for_future_action = false,
        })
    end
    if targetData:find("\0", 1, true) then
        return inspection_result("target_read_failed", "target script contains a NUL byte", {
            target = target,
            manifest = manifest,
            safe_for_future_action = false,
        })
    end

    local lines = split_lines(targetData)
    local operations = {}
    for _, operation in ipairs(REQUIRED_OPERATIONS) do
        operations[#operations + 1] = analyze_operation(lines, operation, manifest)
    end
    local tableFinding = analyze_table_payload(target, manifest, readFile)
    local status, safe, localVersion = classify_installation(operations, tableFinding, manifest)

    local components = { table = tableFinding }
    for _, finding in ipairs(operations) do components[finding.id] = finding end
    return inspection_result(status, STATUS_REASONS[status] or status, {
        target = target,
        manifest = manifest,
        components = components,
        operations = operations,
        table_payload = tableFinding,
        local_version = localVersion,
        available_version = manifest.package_version,
        line_ending = line_ending(targetData),
        target_size = #targetData,
        safe_for_future_action = safe,
    })
end

return M
