package.path = "data/modules/Custom Module/?.lua;" .. package.path

local packageDetector = require("vnav_descent_package")
local transaction = require("vnav_descent_transaction")
local sha256 = require("sha256")

local function fail(message)
    error(message, 2)
end

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        fail(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)))
    end
end

local function assert_true(value, label)
    if value ~= true then fail(label .. ": expected true") end
end

local function assert_false(value, label)
    if value ~= false then fail(label .. ": expected false") end
end

local function detect(overrides)
    local input = {
        xplane_path = "/X-Plane 12/",
        acf_relative_path = "Aircraft/B737-800X/b738.acf",
        separator = "/",
        levelup_release = "",
        levelup_flight_model = "",
        zibo_runtime = true,
        file_exists = function() return true end,
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return packageDetector.detectLoadedAircraft(input)
end

local zibo = detect()
assert_equal(zibo.status, "supported", "Zibo status")
assert_equal(zibo.family, "zibo_upstream", "Zibo family")
assert_equal(zibo.aircraft_root, "/X-Plane 12/Aircraft/B737-800X", "Zibo root")
assert_equal(
    zibo.target_path,
    "/X-Plane 12/Aircraft/B737-800X/plugins/xlua/scripts/B738.a_fms/B738.a_fms.lua",
    "Zibo target"
)
assert_true(zibo.patchable, "Zibo patchable")

local zibo4k = detect({ acf_relative_path = "Aircraft/B737-800X/b738_4k.acf" })
assert_equal(zibo4k.status, "supported", "Zibo 4K status")

local levelUp = detect({
    acf_relative_path = "Aircraft/LevelUp/737NG-Series/737_70NG.acf",
    levelup_release = "1.0.0",
    levelup_flight_model = "2.1",
})
assert_equal(levelUp.status, "supported", "LevelUp status")
assert_equal(levelUp.family, "levelup_737ng", "LevelUp family")
assert_equal(levelUp.aircraft_root, "/X-Plane 12/Aircraft/LevelUp/737NG-Series", "LevelUp root")
assert_true(levelUp.patchable, "LevelUp patchable")

local windowsLevelUp = detect({
    xplane_path = "C:\\X-Plane 12\\",
    acf_relative_path = "Aircraft\\LevelUp\\737NG-Series\\737_9ENG.acf",
    separator = "\\",
    levelup_release = "1.0.0",
})
assert_equal(
    windowsLevelUp.target_path,
    "C:\\X-Plane 12\\Aircraft\\LevelUp\\737NG-Series\\plugins\\xlua\\scripts\\B738.a_fms\\B738.a_fms.lua",
    "Windows LevelUp target"
)

local ziboPort = detect({ file_exists = function() return false end })
assert_equal(ziboPort.status, "not_applicable_no_lua", "Zibo port status")
assert_false(ziboPort.patchable, "Zibo port patchable")

local levelUpPort = detect({
    acf_relative_path = "Aircraft/LevelUp/737NG-Series/737_80NG.acf",
    levelup_release = "1.0.0",
    file_exists = function() return false end,
})
assert_equal(levelUpPort.status, "not_applicable_no_lua", "LevelUp port status")

local levelUpNotReady = detect({
    acf_relative_path = "Aircraft/LevelUp/737NG-Series/737_60NG.acf",
})
assert_equal(levelUpNotReady.status, "runtime_not_ready", "LevelUp readiness")

local ziboNotReady = detect({ zibo_runtime = false })
assert_equal(ziboNotReady.status, "runtime_not_ready", "Zibo readiness")

local conflict = detect({ levelup_release = "1.0.0" })
assert_equal(conflict.status, "conflicting_family", "Conflicting family")
assert_false(conflict.patchable, "Conflicting target patchable")

local unsupported = detect({ acf_relative_path = "Aircraft/Laminar/Cessna_172SP.acf" })
assert_equal(unsupported.status, "unsupported_aircraft", "Unsupported aircraft")

local traversal = detect({ acf_relative_path = "Aircraft/../B737-800X/b738.acf" })
assert_equal(traversal.status, "invalid_aircraft_path", "Unsafe relative path")

assert_equal(
    sha256.hex(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "SHA-256 empty vector"
)
assert_equal(
    sha256.hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    "SHA-256 abc vector"
)

local packageId = "test-zibo-vnav-package"
local packageVersion = "v0.2.0"
local repositoryUrl = "https://example.invalid/test-zibo-vnav-package"
local tableFile = "B738.a_fms_test_tables.lua"
local tableContent = "return { test = true }\n"
local dofileFragment = table.concat({
    "-- BEGIN TEST_VNAV DOFILE",
    "-- package-id|" .. packageId,
    "-- package-version|" .. packageVersion,
    "dofile(\"" .. tableFile .. "\")",
    "-- END TEST_VNAV DOFILE",
    "",
}, "\n")
local kiasFragment = table.concat({
    "\t-- BEGIN TEST_VNAV KIAS",
    "\t-- package-id|" .. packageId,
    "\t-- package-version|" .. packageVersion,
    "\treturn B738_variant_test_take_alt_dist()",
    "\t-- END TEST_VNAV KIAS",
    "",
}, "\n")
local machFragment = table.concat({
    "\t-- BEGIN TEST_VNAV MACH",
    "\t-- package-id|" .. packageId,
    "\t-- package-version|" .. packageVersion,
    "\treturn B738_variant_test_take_alt_dist_mach()",
    "\t-- END TEST_VNAV MACH",
    "",
}, "\n")

local function payload_line(role, filename, content)
    return string.format(
        "payload|%s|%s|size|%d|sha256|%s",
        role,
        filename,
        #content,
        sha256.hex(content)
    )
end

local manifestText = table.concat({
    "schema|package-manifest|1",
    "package|id|" .. packageId,
    "package|version|" .. packageVersion,
    "package|release_tag|" .. packageVersion,
    "aircraft|family|zibo_upstream",
    "repository|url|" .. repositoryUrl,
    "target|relative_path|" .. packageDetector.TARGET_RELATIVE_PATH,
    payload_line("table", tableFile, tableContent),
    payload_line("dofile", "Add_dofile.txt", dofileFragment),
    payload_line("kias", "Add_to_take_alt_dist.txt", kiasFragment),
    payload_line("mach", "Add_to_take_alt_dist_mach.txt", machFragment),
    "anchor|dofile|jit.off()",
    "anchor|kias|function take_alt_dist(x)",
    "anchor|mach|function take_alt_dist_mach(x)",
    "marker|dofile|begin|-- BEGIN TEST_VNAV DOFILE",
    "marker|dofile|end|-- END TEST_VNAV DOFILE",
    "marker|kias|begin|-- BEGIN TEST_VNAV KIAS",
    "marker|kias|end|-- END TEST_VNAV KIAS",
    "marker|mach|begin|-- BEGIN TEST_VNAV MACH",
    "marker|mach|end|-- END TEST_VNAV MACH",
    "legacy|v0.1.0|dofile|dofile(\"" .. tableFile .. "\")",
    "legacy|v0.1.0|kias|pcall(B738_variant_test_take_alt_dist,",
    "legacy|v0.1.0|mach|pcall(B738_variant_test_take_alt_dist_mach,",
    "",
}, "\n")

local manifestExpected = {
    package_id = packageId,
    aircraft_family = "zibo_upstream",
    repository_url = repositoryUrl,
}
local targetPath = zibo.target_path
local tablePath = targetPath:match("^(.*)/[^/]+$") .. "/" .. tableFile
local baseTarget = table.concat({
    "jit.off()",
    "function take_alt_dist(x)",
    "function take_alt_dist_mach(x)",
    "",
}, "\n")
local currentTarget = table.concat({
    "jit.off()",
    dofileFragment:sub(1, -2),
    "function take_alt_dist(x)",
    kiasFragment:sub(1, -2),
    "function take_alt_dist_mach(x)",
    machFragment:sub(1, -2),
    "",
}, "\n")

local function inspect(targetData, payloadData, overrides)
    local files = { [targetPath] = targetData }
    if payloadData ~= nil then files[tablePath] = payloadData end
    local input = {
        target = zibo,
        manifest_text = manifestText,
        expected = manifestExpected,
        read_file = function(path) return files[path] end,
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return packageDetector.inspectInstallation(input)
end

local current = inspect(currentTarget, tableContent)
assert_equal(current.status, "installed_current", "Current package state")
assert_equal(current.local_version, packageVersion, "Current package version")
assert_equal(current.components.table.state, "current", "Current table component")
assert_equal(current.components.dofile.state, "marked_current", "Current dofile component")
assert_true(current.safe_for_future_action, "Current package future action safety")

local absent = inspect(baseTarget, nil)
assert_equal(absent.status, "not_installed", "Absent package state")

local overwritten = inspect(baseTarget, tableContent)
assert_equal(overwritten.status, "aircraft_update_removed", "Aircraft update removed hooks")

local missingTable = inspect(currentTarget, nil)
assert_equal(missingTable.status, "repair_required", "Missing table repair state")

local outdatedTarget = currentTarget:gsub("package%-version|v0%.2%.0", "package-version|v0.1.0")
local outdated = inspect(outdatedTarget, "old table\n")
assert_equal(outdated.status, "installed_outdated", "Outdated package state")
assert_equal(outdated.local_version, "v0.1.0", "Outdated local version")

local partialTarget = currentTarget:gsub("\t%-%- BEGIN TEST_VNAV MACH.-%-%- END TEST_VNAV MACH\n", "")
local partial = inspect(partialTarget, tableContent)
assert_equal(partial.status, "partial_damaged", "Partial package state")
assert_false(partial.safe_for_future_action, "Partial package future action safety")

local anchorMismatch = inspect("jit.off()\n", nil)
assert_equal(anchorMismatch.status, "target_changed", "Anchor mismatch state")

local invalidManifest = packageDetector.inspectInstallation({
    target = zibo,
    manifest_text = manifestText:gsub("aircraft|family|zibo_upstream", "aircraft|family|levelup_737ng"),
    expected = manifestExpected,
    read_file = function() return currentTarget end,
})
assert_equal(invalidManifest.status, "manifest_invalid", "Manifest family guard")

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function ensure_directory(path)
    local result = os.execute("mkdir -p " .. shell_quote(path))
    return result == true or result == 0
end

local function remove_directory(path)
    os.execute("rm -rf " .. shell_quote(path))
end

local function write_file(path, data)
    local parent = path:match("^(.*)/[^/]+$")
    if parent then ensure_directory(parent) end
    local file = assert(io.open(path, "wb"))
    file:write(data)
    file:close()
end

local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("*a")
    file:close()
    return data
end

local tempRoot = "/tmp/yal-vnav-transaction-test-" .. tostring(os.time()) .. "-" .. tostring(math.floor(os.clock() * 100000))
local aircraftRoot = tempRoot .. "/Aircraft/B737-800X"
local liveTargetPath = aircraftRoot .. "/" .. packageDetector.TARGET_RELATIVE_PATH
local liveTablePath = liveTargetPath:match("^(.*)/[^/]+$") .. "/" .. tableFile
local cacheRoot = tempRoot .. "/Output/caches/YAL.cache"
remove_directory(tempRoot)
ensure_directory(liveTargetPath:match("^(.*)/[^/]+$"))

local transactionTarget = {}
for key, value in pairs(zibo) do transactionTarget[key] = value end
transactionTarget.aircraft_root = aircraftRoot
transactionTarget.aircraft_relative_path = "Aircraft/B737-800X/b738.acf"
transactionTarget.target_path = liveTargetPath

local payloadByName = {
    [tableFile] = tableContent,
    ["Add_dofile.txt"] = dofileFragment,
    ["Add_to_take_alt_dist.txt"] = kiasFragment,
    ["Add_to_take_alt_dist_mach.txt"] = machFragment,
}
local function download_fixture(url)
    local filename = tostring(url):match("([^/]+)$")
    return payloadByName[filename]
end
local function execute_action(action, overrides)
    local input = {
        action = action,
        target = transactionTarget,
        manifest_text = manifestText,
        expected = manifestExpected,
        cache_root = cacheRoot,
        download = download_fixture,
        ensure_directory = ensure_directory,
        remove_directory = remove_directory,
        yal_version = "test",
        now = 1234567890,
    }
    for key, value in pairs(overrides or {}) do input[key] = value end
    return transaction.execute(input)
end
local function inspect_live()
    return packageDetector.inspectInstallation({
        target = transactionTarget,
        manifest_text = manifestText,
        expected = manifestExpected,
    })
end

local crlfBase = "\239\187\191" .. baseTarget:gsub("\n", "\r\n")
write_file(liveTargetPath, crlfBase)
local install = execute_action("install")
assert_true(install.ok, "Transactional install")
assert_equal(inspect_live().status, "installed_current", "Installed live state")
local installedTarget = read_file(liveTargetPath)
assert_equal(installedTarget:sub(1, 3), "\239\187\191", "Target BOM preserved")
assert_true(installedTarget:find("\r\n", 1, true) ~= nil, "Target CRLF preserved")
assert_true(installedTarget:gsub("\r\n", ""):find("\n", 1, true) == nil, "No bare LF introduced")

local restoreAfterInstall = transaction.inspectRestore({ target = transactionTarget, cache_root = cacheRoot })
assert_true(restoreAfterInstall.available, "Install backup restorable")

local uninstall = execute_action("uninstall")
assert_true(uninstall.ok, "Transactional uninstall")
assert_equal(inspect_live().status, "not_installed", "Uninstalled live state")
assert_equal(read_file(liveTablePath), nil, "Uninstall removes verified table")

local restore = execute_action("restore")
assert_true(restore.ok, "Transactional restore")
assert_equal(inspect_live().status, "installed_current", "Restored live state")

write_file(liveTargetPath, read_file(liveTargetPath):gsub("package%-version|v0%.2%.0", "package-version|v0.1.0"))
write_file(liveTablePath, "unknown old table\n")
assert_equal(inspect_live().status, "installed_outdated", "Pre-update live state")
local unsafeUpdate = execute_action("update")
assert_false(unsafeUpdate.ok, "Unknown outdated table is not overwritten")
assert_equal(read_file(liveTablePath), "unknown old table\n", "Unknown outdated table preserved")
write_file(liveTablePath, "-- package-id|" .. packageId .. "\n-- package-version|v0.1.0\nold table\n")
local updateResult = execute_action("update")
assert_true(updateResult.ok, "Transactional update")
assert_equal(inspect_live().status, "installed_current", "Updated live state")

os.remove(liveTablePath)
assert_equal(inspect_live().status, "repair_required", "Pre-repair live state")
local repair = execute_action("repair")
assert_true(repair.ok, "Transactional repair")
assert_equal(inspect_live().status, "installed_current", "Repaired live state")

remove_directory(tempRoot)
ensure_directory(liveTargetPath:match("^(.*)/[^/]+$"))
write_file(liveTargetPath, crlfBase)
local originalRename = os.rename
local rollbackResult = execute_action("install", {
    rename_file = function(source, destination)
        if destination == liveTargetPath and tostring(source):find(".yal-vnav-stage-", 1, true) then
            return nil, "injected target commit failure"
        end
        return originalRename(source, destination)
    end,
})
assert_false(rollbackResult.ok, "Injected commit failure")
assert_equal(read_file(liveTargetPath), crlfBase, "Rollback restores exact target")
assert_equal(read_file(liveTablePath), nil, "Rollback removes newly installed table")

remove_directory(tempRoot)

print("VNAV descent package tests passed")
