package.path = "data/modules/Custom Module/?.lua;" .. package.path

local packageDetector = require("vnav_descent_package")

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

print("VNAV descent package detection tests passed")
