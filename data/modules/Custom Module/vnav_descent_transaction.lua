local sha256 = require("sha256")
local packageModel = require("vnav_descent_package")

local M = {}

local REQUIRED_OPERATIONS = { "dofile", "kias", "mach" }
local MAX_TARGET_SIZE = 67108864

local function clean_text(value)
    return tostring(value or ""):gsub("%z", ""):match("^%s*(.-)%s*$") or ""
end

local function separator_for(path)
    return tostring(path or ""):find("\\", 1, true) and "\\" or "/"
end

local function strip_trailing_separators(path)
    local value = tostring(path or "")
    while #value > 1 do
        local last = value:sub(-1)
        if last ~= "/" and last ~= "\\" then break end
        value = value:sub(1, -2)
    end
    return value
end

local function platform_path(path, separator)
    if separator == "\\" then return tostring(path or ""):gsub("/", "\\") end
    return tostring(path or ""):gsub("\\", "/")
end

local function join_path(root, relative, separator)
    local base = strip_trailing_separators(root)
    if base == "" then return nil end
    return base .. separator .. platform_path(relative, separator)
end

local function parent_path(path)
    local value = tostring(path or "")
    for index = #value, 1, -1 do
        local character = value:sub(index, index)
        if character == "/" or character == "\\" then return value:sub(1, index - 1) end
    end
    return nil
end

local function is_safe_filename(name)
    local value = tostring(name or "")
    if value == "" or value == "." or value == ".." then return false end
    if value:find("/", 1, true) or value:find("\\", 1, true) or value:find(":", 1, true) then return false end
    return value:find("..", 1, true) == nil
end

local function read_binary_file(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err or "open failed" end
    local data = file:read("*a")
    file:close()
    if data == nil then return nil, "read failed" end
    return data
end

local function write_binary_file(path, data)
    local file, err = io.open(path, "wb")
    if not file then return false, err or "open failed" end
    local ok, writeError = pcall(function() file:write(data or "") end)
    file:close()
    if not ok then return false, tostring(writeError or "write failed") end
    local verify, verifyError = read_binary_file(path)
    if verify == nil then return false, verifyError or "verification read failed" end
    if verify ~= (data or "") then return false, "written content differs" end
    return true
end

local function remove_if_present(path, readFile, removeFile)
    local data = readFile(path)
    if data == nil then return true end
    local ok, err = removeFile(path)
    if ok == nil or ok == false then return false, err or "remove failed" end
    return true
end

local function valid_utf8(data)
    local index = 1
    while index <= #data do
        local first = data:byte(index)
        if first < 0x80 then
            index = index + 1
        else
            local needed, minimum
            if first >= 0xC2 and first <= 0xDF then
                needed, minimum = 1, 0x80
            elseif first >= 0xE0 and first <= 0xEF then
                needed, minimum = 2, 0x800
            elseif first >= 0xF0 and first <= 0xF4 then
                needed, minimum = 3, 0x10000
            else
                return false
            end
            if index + needed > #data then return false end
            local codepoint = first % (2 ^ (6 - needed))
            for offset = 1, needed do
                local byte = data:byte(index + offset)
                if byte < 0x80 or byte > 0xBF then return false end
                codepoint = codepoint * 64 + (byte - 0x80)
            end
            if codepoint < minimum or codepoint > 0x10FFFF or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then
                return false
            end
            index = index + needed + 1
        end
    end
    return true
end

local function detect_line_ending(data)
    local crlf, lf, cr = 0, 0, 0
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
    if kinds > 1 then return nil, "mixed line endings are not safe to patch" end
    if crlf > 0 then return "\r\n", "CRLF" end
    if lf > 0 then return "\n", "LF" end
    if cr > 0 then return "\r", "CR" end
    return "\n", "None"
end

local function decode_text(data)
    data = tostring(data or "")
    if #data > MAX_TARGET_SIZE then return nil, "text exceeds the 64 MiB safety limit" end
    if data:find("\0", 1, true) then return nil, "text contains a NUL byte" end
    local bom = data:sub(1, 3) == "\239\187\191"
    local body = bom and data:sub(4) or data
    if not valid_utf8(body) then return nil, "text is not valid UTF-8" end
    local eol, eolName = detect_line_ending(body)
    if not eol then return nil, eolName end
    local normalized = body:gsub("\r\n", "\n"):gsub("\r", "\n")
    local finalEol = normalized:sub(-1) == "\n"
    if finalEol then normalized = normalized:sub(1, -2) end
    local lines = {}
    if normalized ~= "" then
        for line in (normalized .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    end
    return {
        bom = bom,
        eol = eol,
        eol_name = eolName,
        final_eol = finalEol,
        lines = lines,
    }
end

local function encode_text(document)
    local body = table.concat(document.lines or {}, document.eol or "\n")
    if document.final_eol then body = body .. (document.eol or "\n") end
    if document.bom then body = "\239\187\191" .. body end
    return body
end

local function fragment_lines(data)
    local document, err = decode_text(data)
    if not document then return nil, err end
    if document.bom then return nil, "patch fragment unexpectedly contains a UTF-8 BOM" end
    return document.lines
end

local function is_commented(line)
    local trimmed = tostring(line or ""):match("^%s*(.*)$") or ""
    return trimmed:sub(1, 2) == "--"
end

local function matching_indices(lines, needle, activeOnly)
    local result = {}
    for index, line in ipairs(lines) do
        if line:find(needle, 1, true) and (not activeOnly or not is_commented(line)) then
            result[#result + 1] = index
        end
    end
    return result
end

local function marked_range(lines, markers)
    local begins = matching_indices(lines, markers.begin, false)
    local endings = matching_indices(lines, markers["end"], false)
    if #begins == 0 and #endings == 0 then return nil end
    if #begins ~= 1 or #endings ~= 1 or begins[1] >= endings[1] then
        return nil, "marked block is missing, duplicated or out of order"
    end
    return { first = begins[1], last = endings[1] }
end

local function block_has_package_id(lines, range, packageId)
    local needle = "-- package-id|" .. tostring(packageId or "")
    local count = 0
    for index = range.first, range.last do
        if clean_text(lines[index]) == needle then count = count + 1 end
    end
    return count == 1
end

local function legacy_range(lines, operation, signatures)
    local matches = {}
    for _, signature in ipairs(signatures or {}) do
        for _, index in ipairs(matching_indices(lines, signature, true)) do matches[#matches + 1] = index end
    end
    if #matches == 0 then return nil end
    if #matches ~= 1 then return nil, "legacy hook is duplicated" end
    local first = matches[1]
    if operation == "dofile" then return { first = first, last = first } end
    for index = first + 1, math.min(first + 7, #lines) do
        if clean_text(lines[index]) == "end" then return { first = first, last = index } end
    end
    return nil, "legacy hook end was not found"
end

local function ranges_overlap(left, right)
    if left.last < left.first or right.last < right.first then return false end
    return left.first <= right.last and right.first <= left.last
end

local function apply_changes(lines, changes)
    for leftIndex = 1, #changes do
        for rightIndex = leftIndex + 1, #changes do
            if ranges_overlap(changes[leftIndex], changes[rightIndex]) then
                return nil, "planned patch blocks overlap"
            end
        end
    end
    table.sort(changes, function(left, right)
        if left.first == right.first then return left.last > right.last end
        return left.first > right.first
    end)
    for _, change in ipairs(changes) do
        for index = change.last, change.first, -1 do table.remove(lines, index) end
        for index = #(change.replacement or {}), 1, -1 do
            table.insert(lines, change.first, change.replacement[index])
        end
    end
    return lines
end

local function build_install_target(targetData, manifest, payloads)
    local document, decodeError = decode_text(targetData)
    if not document then return nil, decodeError end
    local changes = {}
    for _, operation in ipairs(REQUIRED_OPERATIONS) do
        local replacement, fragmentError = fragment_lines(payloads[operation])
        if not replacement then return nil, operation .. " fragment: " .. tostring(fragmentError) end
        local range, markerError = marked_range(document.lines, manifest.markers[operation])
        if markerError then return nil, operation .. ": " .. markerError end
        if range then
            if not block_has_package_id(document.lines, range, manifest.package_id) then
                return nil, operation .. ": marked block is not owned by this package"
            end
            range.replacement = replacement
            changes[#changes + 1] = range
        else
            local legacy, legacyError = legacy_range(document.lines, operation, manifest.legacy[operation])
            if legacyError then return nil, operation .. ": " .. legacyError end
            if legacy then
                legacy.replacement = replacement
                changes[#changes + 1] = legacy
            else
                local anchors = matching_indices(document.lines, manifest.anchors[operation], true)
                if #anchors ~= 1 then return nil, operation .. ": required insertion anchor is not unique" end
                changes[#changes + 1] = {
                    first = anchors[1] + 1,
                    last = anchors[1],
                    replacement = replacement,
                }
            end
        end
    end
    local patched, patchError = apply_changes(document.lines, changes)
    if not patched then return nil, patchError end
    document.lines = patched
    return encode_text(document), {
        line_ending = document.eol_name,
        bom = document.bom,
        final_eol = document.final_eol,
    }
end

local function build_uninstall_target(targetData, manifest)
    local document, decodeError = decode_text(targetData)
    if not document then return nil, decodeError end
    local changes = {}
    for _, operation in ipairs(REQUIRED_OPERATIONS) do
        local range, markerError = marked_range(document.lines, manifest.markers[operation])
        if markerError then return nil, operation .. ": " .. markerError end
        if range then
            if not block_has_package_id(document.lines, range, manifest.package_id) then
                return nil, operation .. ": marked block is not owned by this package"
            end
            range.replacement = {}
            changes[#changes + 1] = range
        end
    end
    local patched, patchError = apply_changes(document.lines, changes)
    if not patched then return nil, patchError end
    document.lines = patched
    return encode_text(document), {
        line_ending = document.eol_name,
        bom = document.bom,
        final_eol = document.final_eol,
    }
end

function M.buildPatchedTarget(input)
    input = input or {}
    if input.action == "uninstall" then
        return build_uninstall_target(input.target_data, input.manifest)
    end
    return build_install_target(input.target_data, input.manifest, input.payloads or {})
end

local function receipt_escape(value)
    return tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
end

local function receipt_unescape(value)
    return tostring(value or ""):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

local function serialize_receipt(values)
    local keys = {}
    for key in pairs(values or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local lines = { "schema|yal-vnav-transaction|1" }
    for _, key in ipairs(keys) do
        if key ~= "schema" then lines[#lines + 1] = tostring(key) .. "|" .. receipt_escape(values[key]) end
    end
    return table.concat(lines, "\n") .. "\n"
end

local function parse_receipt(text)
    local values = {}
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        local separator = line:find("|", 1, true)
        if not separator then return nil, "invalid receipt line" end
        local key = line:sub(1, separator - 1)
        local value = receipt_unescape(line:sub(separator + 1))
        if values[key] ~= nil then return nil, "duplicate receipt field" end
        values[key] = value
    end
    if values.schema ~= "yal-vnav-transaction|1" then return nil, "unsupported receipt schema" end
    return values
end

local function install_id(target)
    local identity = tostring(target.aircraft_relative_path or target.aircraft_root or "")
        .. "|" .. tostring(target.target_relative_path or packageModel.TARGET_RELATIVE_PATH)
    return sha256.hex(identity):sub(1, 20)
end

local function backup_paths(cacheRoot, target, action, timestamp, readFile)
    local separator = separator_for(target.target_path)
    local root = join_path(cacheRoot, "vnav_descent_tables/backups/" .. install_id(target), separator)
    local baseName = tostring(timestamp) .. "-" .. tostring(action)
    local generation = baseName
    local suffix = 0
    while readFile(join_path(root, generation .. "/receipt.txt", separator)) ~= nil
        or readFile(join_path(root, generation .. "/B738.a_fms.before", separator)) ~= nil do
        suffix = suffix + 1
        generation = baseName .. "-" .. tostring(suffix)
    end
    return {
        separator = separator,
        root = root,
        generation = generation,
        generation_dir = join_path(root, generation, separator),
        target_backup = join_path(root, generation .. "/B738.a_fms.before", separator),
        table_backup = join_path(root, generation .. "/table.before", separator),
        receipt = join_path(root, generation .. "/receipt.txt", separator),
        pointer = join_path(root, "latest-receipt.txt", separator),
    }
end

local function timestamp_text(now)
    local ok, value = pcall(os.date, "%Y%m%d-%H%M%S", now)
    if ok and value then return value end
    return tostring(now)
end

local function action_allowed(inspection, action)
    local status = inspection and inspection.status or ""
    if action == "install" then return status == "not_installed" end
    if action == "update" then return status == "installed_outdated" or status == "installed_legacy" end
    if action == "repair" then return status == "repair_required" or status == "aircraft_update_removed" end
    if action == "uninstall" then
        if status == "installed_current" or status == "aircraft_update_removed" then return true end
        return status == "repair_required"
            and inspection.components
            and inspection.components.table
            and inspection.components.table.state == "current"
    end
    return false
end

function M.availableActions(inspection, restoreInspection)
    local actions = {}
    local order = { "install", "update", "repair", "uninstall" }
    local labels = { install = "Install", update = "Update", repair = "Repair", uninstall = "Uninstall" }
    for _, action in ipairs(order) do
        if action_allowed(inspection, action) then
            actions[#actions + 1] = { id = action, label = labels[action], primary = action ~= "uninstall" }
        end
    end
    if restoreInspection and restoreInspection.available == true then
        actions[#actions + 1] = { id = "restore", label = "Restore Backup", primary = false }
    end
    return actions
end

local function verify_payloads(manifest, payloads)
    for role, expected in pairs(manifest.payloads or {}) do
        local data = payloads[role]
        if data == nil then return false, "payload missing: " .. tostring(role) end
        if #data ~= expected.size or sha256.hex(data) ~= expected.sha256 then
            return false, "payload verification failed: " .. tostring(expected.filename)
        end
    end
    return true
end

local function table_metadata(data)
    local packageId, packageVersion = nil, nil
    local packageIdCount, packageVersionCount = 0, 0
    for line in tostring(data or ""):gmatch("[^\r\n]+") do
        local trimmed = clean_text(line)
        local id = trimmed:match("^%-%- package%-id|(.+)$")
        local version = trimmed:match("^%-%- package%-version|(.+)$")
        if id then packageId, packageIdCount = id, packageIdCount + 1 end
        if version then packageVersion, packageVersionCount = version, packageVersionCount + 1 end
    end
    return packageId, packageVersion, packageIdCount, packageVersionCount
end

local function encode_url_segment(value)
    return (tostring(value or ""):gsub("([^%w%-%._~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end))
end

local function tagged_payload_url(manifest, filename)
    local owner, repository = tostring(manifest.repository_url or ""):match(
        "^https://github%.com/([%w%._%-]+)/([%w%._%-]+)$"
    )
    if not owner or not repository then return nil, "unsupported GitHub repository URL" end
    return "https://raw.githubusercontent.com/"
        .. owner .. "/" .. repository .. "/"
        .. encode_url_segment(manifest.release_tag) .. "/"
        .. encode_url_segment(filename)
end

local function download_payloads(manifest, download)
    local payloads = {}
    for _, role in ipairs({ "table", "dofile", "kias", "mach" }) do
        local entry = manifest.payloads[role]
        local url, urlError = tagged_payload_url(manifest, entry.filename)
        if not url then return nil, urlError end
        local data, err = download(url)
        if data == nil then return nil, "could not download " .. entry.filename .. ": " .. tostring(err or "download failed") end
        payloads[role] = tostring(data)
    end
    local ok, verifyError = verify_payloads(manifest, payloads)
    if not ok then return nil, verifyError end
    return payloads
end

local function verify_staged_install(stageTarget, stageTable, manifest, expected)
    local stagedTarget = {
        status = "supported",
        patchable = true,
        family = manifest.aircraft_family,
        target_path = stageTarget,
    }
    local result = packageModel.inspectInstallation({
        target = stagedTarget,
        manifest_text = expected.manifest_text,
        expected = expected.source,
    })
    if result.status ~= expected.status then
        return false, "staged package state is " .. tostring(result.status) .. ", expected " .. tostring(expected.status)
    end
    if expected.status == "installed_current" and result.table_payload.path ~= stageTable then
        return false, "staged table path differs from the planned path"
    end
    return true
end

local function write_transaction_receipt(path, receipt, writeFile)
    return writeFile(path, serialize_receipt(receipt))
end

local function perform_live_commit(input)
    local readFile = input.read_file
    local writeFile = input.write_file
    local removeFile = input.remove_file
    local renameFile = input.rename_file
    local targetPath = input.target_path
    local tablePath = input.table_path
    local nonce = tostring(input.nonce)
    local targetTemp = targetPath .. ".yal-vnav-stage-" .. nonce
    local targetRollback = targetPath .. ".yal-vnav-rollback-" .. nonce
    local tableTemp = tablePath .. ".yal-vnav-stage-" .. nonce
    local tableRollback = tablePath .. ".yal-vnav-rollback-" .. nonce

    for _, path in ipairs({ targetTemp, targetRollback, tableTemp, tableRollback }) do
        local ok, err = remove_if_present(path, readFile, removeFile)
        if not ok then return false, "could not clear transaction file: " .. tostring(err) end
    end
    local ok, err = writeFile(targetTemp, input.post_target)
    if not ok then return false, "could not write adjacent target staging file: " .. tostring(err) end
    if input.post_table ~= nil then
        ok, err = writeFile(tableTemp, input.post_table)
        if not ok then
            remove_if_present(targetTemp, readFile, removeFile)
            return false, "could not write adjacent table staging file: " .. tostring(err)
        end
    end

    local tableMoved, tableInstalled = false, false
    local targetMoved, targetInstalled = false, false
    local function rollback(reason)
        local rollbackErrors = {}
        if targetInstalled then remove_if_present(targetPath, readFile, removeFile) end
        if targetMoved then
            local restored, restoreError = renameFile(targetRollback, targetPath)
            if not restored then
                restored, restoreError = writeFile(targetPath, input.pre_target)
            end
            if not restored then rollbackErrors[#rollbackErrors + 1] = "target restore failed: " .. tostring(restoreError) end
        end
        if tableInstalled then remove_if_present(tablePath, readFile, removeFile) end
        if tableMoved then
            local restored, restoreError = renameFile(tableRollback, tablePath)
            if not restored then restored, restoreError = writeFile(tablePath, input.pre_table) end
            if not restored then rollbackErrors[#rollbackErrors + 1] = "table restore failed: " .. tostring(restoreError) end
        end
        remove_if_present(targetTemp, readFile, removeFile)
        remove_if_present(tableTemp, readFile, removeFile)
        if readFile(targetPath) ~= input.pre_target then rollbackErrors[#rollbackErrors + 1] = "target verification failed" end
        if readFile(tablePath) ~= input.pre_table then rollbackErrors[#rollbackErrors + 1] = "table verification failed" end
        if #rollbackErrors > 0 then reason = tostring(reason) .. "; rollback error: " .. table.concat(rollbackErrors, "; ") end
        return false, reason
    end

    if input.pre_table ~= nil then
        ok, err = renameFile(tablePath, tableRollback)
        if not ok then return rollback("could not preserve live table before replacement: " .. tostring(err)) end
        tableMoved = true
    end
    if input.post_table ~= nil then
        ok, err = renameFile(tableTemp, tablePath)
        if not ok then return rollback("could not install table payload: " .. tostring(err)) end
        tableInstalled = true
    end
    ok, err = renameFile(targetPath, targetRollback)
    if not ok then return rollback("could not preserve live target before replacement: " .. tostring(err)) end
    targetMoved = true
    ok, err = renameFile(targetTemp, targetPath)
    if not ok then return rollback("could not install patched target: " .. tostring(err)) end
    targetInstalled = true

    local liveTarget = readFile(targetPath)
    local liveTable = readFile(tablePath)
    if liveTarget ~= input.post_target or liveTable ~= input.post_table then
        return rollback("post-install verification failed")
    end

    remove_if_present(targetRollback, readFile, removeFile)
    remove_if_present(tableRollback, readFile, removeFile)
    remove_if_present(targetTemp, readFile, removeFile)
    remove_if_present(tableTemp, readFile, removeFile)
    return true
end

local function execute_content_transaction(input)
    local readFile = input.read_file or read_binary_file
    local writeFile = input.write_file or write_binary_file
    local removeFile = input.remove_file or os.remove
    local renameFile = input.rename_file or os.rename
    local ensureDirectory = input.ensure_directory
    if type(ensureDirectory) ~= "function" then return nil, "directory creation is unavailable" end
    local now = tonumber(input.now) or os.time() or 0
    local stamp = timestamp_text(now)
    local paths = backup_paths(input.cache_root, input.target, input.action, stamp, readFile)
    if not ensureDirectory(paths.generation_dir) then return nil, "could not create transaction backup folder" end

    local ok, err = writeFile(paths.target_backup, input.pre_target)
    if not ok then return nil, "could not back up target: " .. tostring(err) end
    if input.pre_table ~= nil then
        ok, err = writeFile(paths.table_backup, input.pre_table)
        if not ok then return nil, "could not back up existing table: " .. tostring(err) end
    end

    local receipt = {
        action = input.action,
        aircraft_relative_path = input.target.aircraft_relative_path or "",
        aircraft_root = input.target.aircraft_root or "",
        backup_table_path = input.pre_table ~= nil and paths.table_backup or "",
        backup_target_path = paths.target_backup,
        bom = input.text_info and tostring(input.text_info.bom == true) or "false",
        dofile_payload_sha256 = input.dofile_payload_sha256 or "",
        final_eol = input.text_info and tostring(input.text_info.final_eol == true) or "false",
        installation_id = install_id(input.target),
        kias_payload_sha256 = input.kias_payload_sha256 or "",
        line_ending = input.text_info and input.text_info.line_ending or "unknown",
        mach_payload_sha256 = input.mach_payload_sha256 or "",
        manifest_sha256 = input.manifest_sha256 or "",
        package_id = input.package_id or "",
        package_version = input.package_version or "",
        previous_package_version = input.previous_package_version or "",
        receipt_path = paths.receipt,
        status = "prepared",
        table_filename = input.table_filename,
        table_post_present = input.post_table ~= nil and "1" or "0",
        table_post_sha256 = input.post_table and sha256.hex(input.post_table) or "",
        table_pre_present = input.pre_table ~= nil and "1" or "0",
        table_pre_sha256 = input.pre_table and sha256.hex(input.pre_table) or "",
        target_path = input.target.target_path,
        target_relative_path = input.target.target_relative_path or packageModel.TARGET_RELATIVE_PATH,
        target_post_sha256 = sha256.hex(input.post_target),
        target_pre_sha256 = sha256.hex(input.pre_target),
        timestamp = tostring(now),
        yal_version = input.yal_version or "",
    }
    ok, err = write_transaction_receipt(paths.receipt, receipt, writeFile)
    if not ok then return nil, "could not write prepared transaction receipt: " .. tostring(err) end

    local tablePath = join_path(parent_path(input.target.target_path), input.table_filename, paths.separator)
    local commitOk, commitError = perform_live_commit({
        read_file = readFile,
        write_file = writeFile,
        remove_file = removeFile,
        rename_file = renameFile,
        target_path = input.target.target_path,
        table_path = tablePath,
        pre_target = input.pre_target,
        pre_table = input.pre_table,
        post_target = input.post_target,
        post_table = input.post_table,
        nonce = paths.generation,
    })
    if not commitOk then
        receipt.status = "rolled_back"
        receipt.error = tostring(commitError or "commit failed")
        write_transaction_receipt(paths.receipt, receipt, writeFile)
        return nil, receipt.error
    end

    receipt.status = "committed"
    ok, err = write_transaction_receipt(paths.receipt, receipt, writeFile)
    if not ok then
        perform_live_commit({
            read_file = readFile,
            write_file = writeFile,
            remove_file = removeFile,
            rename_file = renameFile,
            target_path = input.target.target_path,
            table_path = tablePath,
            pre_target = input.post_target,
            pre_table = input.post_table,
            post_target = input.pre_target,
            post_table = input.pre_table,
            nonce = paths.generation .. "-receipt-rollback",
        })
        return nil, "could not finalize transaction receipt: " .. tostring(err)
    end
    local previousPointer = readFile(paths.pointer)
    ok, err = writeFile(paths.pointer, serialize_receipt({ receipt_path = paths.receipt }))
    if not ok then
        perform_live_commit({
            read_file = readFile,
            write_file = writeFile,
            remove_file = removeFile,
            rename_file = renameFile,
            target_path = input.target.target_path,
            table_path = tablePath,
            pre_target = input.post_target,
            pre_table = input.post_table,
            post_target = input.pre_target,
            post_table = input.pre_table,
            nonce = paths.generation .. "-pointer-rollback",
        })
        receipt.status = "rolled_back"
        receipt.error = "could not update latest-backup pointer"
        write_transaction_receipt(paths.receipt, receipt, writeFile)
        if previousPointer ~= nil then writeFile(paths.pointer, previousPointer) else remove_if_present(paths.pointer, readFile, removeFile) end
        return nil, receipt.error .. ": " .. tostring(err)
    end
    return {
        ok = true,
        action = input.action,
        receipt_path = paths.receipt,
        backup_path = paths.generation_dir,
        target_sha256 = receipt.target_post_sha256,
        table_sha256 = receipt.table_post_sha256,
    }
end

local function stage_path(cacheRoot, target, action)
    local separator = separator_for(target.target_path)
    local path = join_path(cacheRoot, "vnav_descent_tables/staging/" .. install_id(target) .. "/" .. action, separator)
    return path, separator
end

local function action_result(ok, code, title, lines, details)
    details = details or {}
    details.ok = ok
    details.code = code
    details.title = title
    details.lines = lines
    return details
end

function M.execute(input)
    input = input or {}
    if input.action == "restore" then return M.executeRestore(input) end
    local target = input.target
    if type(target) ~= "table" or target.status ~= "supported" or target.patchable ~= true then
        return action_result(false, "target_not_supported", "VNAV Descent Tables", { "The loaded aircraft target is not supported." })
    end
    local manifest, manifestError = packageModel.parseManifest(input.manifest_text, input.expected)
    if not manifest then
        return action_result(false, "manifest_invalid", "VNAV Descent Tables", { "The release manifest is invalid.", tostring(manifestError) })
    end
    local inspection = packageModel.inspectInstallation({
        target = target,
        manifest_text = input.manifest_text,
        expected = input.expected,
    })
    if not action_allowed(inspection, input.action) then
        return action_result(false, "state_changed", "VNAV Descent Tables", {
            "The aircraft package state changed before the operation started.",
            "Current state: " .. tostring(inspection.status),
            "No aircraft file was changed.",
        }, { inspection = inspection })
    end

    local targetData, targetError = read_binary_file(target.target_path)
    if targetData == nil then
        return action_result(false, "target_read_failed", "VNAV Descent Tables", { "Could not read B738.a_fms.lua.", tostring(targetError) })
    end
    local tablePath = join_path(parent_path(target.target_path), manifest.payloads.table.filename, separator_for(target.target_path))
    local preTable = read_binary_file(tablePath)
    if input.action == "update" and inspection.status == "installed_outdated" and preTable ~= nil then
        local tablePackageId, tableVersion, idCount, versionCount = table_metadata(preTable)
        if idCount ~= 1 or versionCount ~= 1 or tablePackageId ~= manifest.package_id or tableVersion ~= inspection.local_version then
            return action_result(false, "table_not_owned", "VNAV Descent Tables", {
                "The existing table payload cannot be attributed to the installed package version.",
                "YAL will not overwrite a modified or unknown file.",
                "No aircraft file was changed.",
            })
        end
    end
    local payloads = {}
    if input.action ~= "uninstall" then
        if type(input.download) ~= "function" then
            return action_result(false, "download_unavailable", "VNAV Descent Tables", { "Release download is unavailable." })
        end
        local downloadError
        payloads, downloadError = download_payloads(manifest, input.download)
        if not payloads then
            return action_result(false, "download_failed", "VNAV Descent Tables", { "Could not stage the release package.", tostring(downloadError) })
        end
    elseif preTable == nil or #preTable ~= manifest.payloads.table.size or sha256.hex(preTable) ~= manifest.payloads.table.sha256 then
        return action_result(false, "table_not_owned", "VNAV Descent Tables", {
            "The table payload no longer matches the published package.",
            "YAL will not remove a modified or unknown file.",
            "No aircraft file was changed.",
        })
    end

    local postTarget, textInfoOrError = M.buildPatchedTarget({
        action = input.action,
        target_data = targetData,
        manifest = manifest,
        payloads = payloads,
    })
    if not postTarget then
        return action_result(false, "patch_failed", "VNAV Descent Tables", { "Could not build a safe patch plan.", tostring(textInfoOrError) })
    end
    local postTable = input.action == "uninstall" and nil or payloads.table

    local stageDir, separator = stage_path(input.cache_root, target, input.action)
    if type(input.remove_directory) == "function" then input.remove_directory(stageDir) end
    if type(input.ensure_directory) ~= "function" or not input.ensure_directory(stageDir) then
        return action_result(false, "staging_failed", "VNAV Descent Tables", { "Could not create the VNAV package staging folder." })
    end
    local stageTarget = join_path(stageDir, "B738.a_fms.lua", separator)
    local stageTable = join_path(stageDir, manifest.payloads.table.filename, separator)
    local ok, writeError = write_binary_file(stageTarget, postTarget)
    if not ok then return action_result(false, "staging_failed", "VNAV Descent Tables", { "Could not stage B738.a_fms.lua.", tostring(writeError) }) end
    if postTable ~= nil then
        ok, writeError = write_binary_file(stageTable, postTable)
        if not ok then return action_result(false, "staging_failed", "VNAV Descent Tables", { "Could not stage the table payload.", tostring(writeError) }) end
    end
    local expectedStageStatus = input.action == "uninstall" and "not_installed" or "installed_current"
    local stagedOk, stagedError = verify_staged_install(stageTarget, stageTable, manifest, {
        manifest_text = input.manifest_text,
        source = input.expected,
        status = expectedStageStatus,
    })
    if not stagedOk then
        return action_result(false, "staging_verify_failed", "VNAV Descent Tables", { "The staged aircraft patch failed structural verification.", tostring(stagedError) })
    end

    local transaction, transactionError = execute_content_transaction({
        action = input.action,
        cache_root = input.cache_root,
        ensure_directory = input.ensure_directory,
        read_file = input.read_file,
        write_file = input.write_file,
        remove_file = input.remove_file,
        rename_file = input.rename_file,
        manifest_sha256 = sha256.hex(input.manifest_text or ""),
        now = input.now,
        dofile_payload_sha256 = manifest.payloads.dofile.sha256,
        kias_payload_sha256 = manifest.payloads.kias.sha256,
        mach_payload_sha256 = manifest.payloads.mach.sha256,
        package_id = manifest.package_id,
        package_version = manifest.package_version,
        previous_package_version = inspection.local_version or "",
        post_table = postTable,
        post_target = postTarget,
        pre_table = preTable,
        pre_target = targetData,
        table_filename = manifest.payloads.table.filename,
        target = target,
        text_info = textInfoOrError,
        yal_version = input.yal_version,
    })
    if not transaction then
        return action_result(false, "transaction_failed", "VNAV Descent Tables", {
            "The aircraft update failed and the live files were preserved or rolled back.",
            tostring(transactionError),
        })
    end
    local verb = ({ install = "installed", update = "updated", repair = "repaired", uninstall = "uninstalled" })[input.action] or "changed"
    local resultCodes = { install = "installed", update = "updated", repair = "repaired", uninstall = "uninstalled" }
    return action_result(true, resultCodes[input.action] or "changed", "VNAV Descent Tables", {
        "VNAV Descent Tables were " .. verb .. " successfully.",
        "A generation backup and transaction receipt were created.",
        "Please restart X-Plane before using this aircraft.",
    }, transaction)
end

function M.inspectRestore(input)
    input = input or {}
    local target = input.target
    if type(target) ~= "table" or target.status ~= "supported" or target.patchable ~= true then
        return { available = false, reason = "loaded aircraft target is not supported" }
    end
    local readFile = input.read_file or read_binary_file
    local paths = backup_paths(input.cache_root, target, "restore-probe", "probe", readFile)
    local pointerText = readFile(paths.pointer)
    if pointerText == nil then return { available = false, reason = "no YAL transaction backup is recorded" } end
    local pointer, pointerError = parse_receipt(pointerText)
    if not pointer then return { available = false, reason = pointerError } end
    local receiptPath = pointer.receipt_path
    local normalizedRoot = platform_path(paths.root, "/") .. "/"
    local normalizedReceipt = platform_path(receiptPath, "/")
    if normalizedReceipt:sub(1, #normalizedRoot) ~= normalizedRoot or normalizedReceipt:find("..", 1, true) then
        return { available = false, reason = "backup receipt path is unsafe" }
    end
    local receiptText = readFile(receiptPath)
    local receipt, receiptError = parse_receipt(receiptText)
    if not receipt then return { available = false, reason = receiptError or "backup receipt is unreadable" } end
    if receipt.status ~= "committed" then return { available = false, reason = "latest transaction did not commit" } end
    if receipt.target_path ~= target.target_path or receipt.installation_id ~= install_id(target) then
        return { available = false, reason = "backup belongs to a different aircraft installation" }
    end
    if not is_safe_filename(receipt.table_filename) then return { available = false, reason = "backup table filename is unsafe" } end
    local currentTarget = readFile(target.target_path)
    if currentTarget == nil or sha256.hex(currentTarget) ~= receipt.target_post_sha256 then
        return { available = false, reason = "B738.a_fms.lua changed after the recorded transaction" }
    end
    local tablePath = join_path(parent_path(target.target_path), receipt.table_filename, paths.separator)
    local currentTable = readFile(tablePath)
    local postPresent = receipt.table_post_present == "1"
    if postPresent then
        if currentTable == nil or sha256.hex(currentTable) ~= receipt.table_post_sha256 then
            return { available = false, reason = "table payload changed after the recorded transaction" }
        end
    elseif currentTable ~= nil then
        return { available = false, reason = "a table payload appeared after the recorded transaction" }
    end
    local receiptDir = parent_path(receiptPath)
    local backupTargetPath = join_path(receiptDir, "B738.a_fms.before", paths.separator)
    local backupTarget = readFile(backupTargetPath)
    if backupTarget == nil or sha256.hex(backupTarget) ~= receipt.target_pre_sha256 then
        return { available = false, reason = "target backup verification failed" }
    end
    local backupTable = nil
    if receipt.table_pre_present == "1" then
        local backupTablePath = join_path(receiptDir, "table.before", paths.separator)
        backupTable = readFile(backupTablePath)
        if backupTable == nil or sha256.hex(backupTable) ~= receipt.table_pre_sha256 then
            return { available = false, reason = "table backup verification failed" }
        end
    end
    return {
        available = true,
        reason = "latest transaction backup matches the current aircraft files",
        receipt = receipt,
        receipt_path = receiptPath,
        target_backup = backupTarget,
        table_backup = backupTable,
        current_target = currentTarget,
        current_table = currentTable,
        table_path = tablePath,
    }
end

function M.executeRestore(input)
    input = input or {}
    local restore = M.inspectRestore(input)
    if not restore.available then
        return action_result(false, "restore_not_safe", "VNAV Descent Tables", {
            "Restore Backup is not safe for the current aircraft state.",
            tostring(restore.reason or "backup verification failed"),
            "No aircraft file was changed.",
        })
    end
    local document, documentError = decode_text(restore.target_backup)
    if not document then
        return action_result(false, "restore_invalid", "VNAV Descent Tables", { "The target backup is not valid UTF-8 text.", tostring(documentError) })
    end
    local receipt = restore.receipt
    local transaction, transactionError = execute_content_transaction({
        action = "restore",
        cache_root = input.cache_root,
        ensure_directory = input.ensure_directory,
        read_file = input.read_file,
        write_file = input.write_file,
        remove_file = input.remove_file,
        rename_file = input.rename_file,
        manifest_sha256 = receipt.manifest_sha256,
        now = input.now,
        dofile_payload_sha256 = receipt.dofile_payload_sha256,
        kias_payload_sha256 = receipt.kias_payload_sha256,
        mach_payload_sha256 = receipt.mach_payload_sha256,
        package_id = receipt.package_id,
        package_version = receipt.package_version,
        previous_package_version = receipt.package_version,
        post_table = restore.table_backup,
        post_target = restore.target_backup,
        pre_table = restore.current_table,
        pre_target = restore.current_target,
        table_filename = receipt.table_filename,
        target = input.target,
        text_info = { line_ending = document.eol_name, bom = document.bom, final_eol = document.final_eol },
        yal_version = input.yal_version,
    })
    if not transaction then
        return action_result(false, "restore_failed", "VNAV Descent Tables", {
            "Restore Backup failed and the live files were preserved or rolled back.",
            tostring(transactionError),
        })
    end
    return action_result(true, "restored", "VNAV Descent Tables", {
        "The previous aircraft file generation was restored successfully.",
        "The replaced state was backed up as a new generation.",
        "Please restart X-Plane before using this aircraft.",
    }, transaction)
end

return M
