package.path = "data/modules/Custom Module/?.lua;" .. package.path

package.loaded.definitions = { CONFIGDEBUGOVERLAY = 1, ON = 1 }
package.loaded.settings = { appSettings = {} }
package.loaded.helpers = {}

local taxi = require("windows.taxi")

local function fail(message)
    error(message, 2)
end

local function assert_equal(actual, expected, label)
    if actual ~= expected then
        fail(string.format("%s: expected %q, got %q", label, tostring(expected), tostring(actual)))
    end
end

local function assert_near(actual, expected, tolerance, label)
    if actual == nil or math.abs(actual - expected) > tolerance then
        fail(string.format("%s: expected %.3f, got %s", label, expected, tostring(actual)))
    end
end

local function taxi_utils()
    for i = 1, 20 do
        local name, value = debug.getupvalue(taxi.newComponent, i)
        if name == "U" then
            return value
        end
        if not name then
            break
        end
    end
    fail("taxi utility table not found")
end

local U = taxi_utils()
local profile = {
    threshold = { east = 0, north = 0 },
    axis = { x = 1, y = 0 },
    length = 3000,
    width = 45
}

local data = {
    nodes = {
        rwy_threshold = { east = 0, north = 0 },
        threshold_entry = { east = 0, north = 85 },
        rwy_mid = { east = 1500, north = 0 },
        mid_entry = { east = 1500, north = 90 },
        parallel_rwy = { east = 1500, north = 200 },
        parallel_entry = { east = 1500, north = 125 }
    },
    runway_nodes = {
        rwy_threshold = true,
        rwy_mid = true,
        parallel_rwy = true
    },
    adjacency_any = {
        rwy_threshold = { { to = "threshold_entry" } },
        rwy_mid = { { to = "mid_entry" } },
        parallel_rwy = { { to = "parallel_entry" } }
    }
}

local id, distance = U.find_holdshort_node_near(
    data, nil, nil, { east = 0, north = 90 }, profile, 60
)
assert_equal(id, "threshold_entry", "threshold entry")
assert_near(distance, 5, 0.001, "threshold entry distance")

id, distance = U.find_holdshort_node_near(
    data, nil, nil, { east = 1500, north = 100 }, profile, 60
)
assert_equal(id, "mid_entry", "mid-runway entry")
assert_near(distance, 10, 0.001, "mid-runway entry distance")

id = U.find_holdshort_node_near(
    data, nil, nil, { east = 1500, north = 125 }, profile, 20
)
assert_equal(id, nil, "parallel runway rejected")

id, distance = U.find_holdshort_node_near(
    data, nil, nil, { east = 0, north = 165 }, profile, 90
)
assert_equal(id, "threshold_entry", "expanded Auto-Unicom hold-short radius")
assert_near(distance, 80, 0.001, "expanded Auto-Unicom hold-short distance")

id = U.find_holdshort_node_near(
    data, nil, nil, { east = 0, north = 165 }, profile, 60
)
assert_equal(id, nil, "shared departure threshold radius remains smaller")

assert_equal(
    U.is_meaningful_departure_intersection(profile, { east = 100, north = 0 }, 20, 90),
    false,
    "near-threshold runway entry is not reported as intersection"
)
assert_equal(
    U.is_meaningful_departure_intersection(profile, { east = 170, north = 0 }, 20, 90),
    true,
    "meaningful runway reduction with nearby labeled entry is reported"
)
assert_equal(
    U.is_meaningful_departure_intersection(profile, { east = 1500, north = 0 }, 100, 90),
    false,
    "runway position without nearby labeled entry is not reported"
)
assert_equal(
    U.is_meaningful_departure_intersection(profile, { east = 1500, north = 100 }, 20, 90),
    false,
    "off-runway position is not reported as intersection"
)

print("taxi hold-short geometry tests passed")
