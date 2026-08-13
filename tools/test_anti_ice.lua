package.path = "data/modules/Custom Module/?.lua;" .. package.path

local antiIce = require("anti_ice")

local function fail(message)
    error(message, 2)
end

local function assertEqual(actual, expected, label)
    if actual ~= expected then
        fail(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, label)
    if value ~= true then fail(label .. ": expected true") end
end

local function assertFalse(value, label)
    if value ~= false then fail(label .. ": expected false") end
end

local function copy(source, overrides)
    local result = {}
    for key, value in pairs(source or {}) do result[key] = value end
    for key, value in pairs(overrides or {}) do result[key] = value end
    return result
end

local base = {
    enabled = true,
    airborne = true,
    tat_c = 5,
    sat_c = -10,
    climb_or_cruise = false,
    precipitation_ratio = 0,
    snow_ratio = 0,
    hail_ratio = 0,
    visibility_sm = 10,
    in_cloud_layer = false,
    frame_ice_left = 0,
    frame_ice_right = 0,
    hold_active = false,
    pressure_altitude_ft = 10000
}

local function update(state, now, overrides)
    return antiIce.update(state, copy(base, copy(overrides, { now = now })))
end

assertTrue(antiIce.isInCloudLayer(1500, { 0.6 }, { 1000 }, { 2000 }), "inside cloud layer")
assertFalse(antiIce.isInCloudLayer(2500, { 0.6 }, { 1000 }, { 2000 }), "above cloud layer")
assertFalse(antiIce.isInCloudLayer(1500, { 0.49 }, { 1000 }, { 2000 }), "insufficient cloud coverage")

local moisture, source = antiIce.visibleMoisture(copy(base, { precipitation_ratio = 0.01 }))
assertTrue(moisture, "precipitation is visible moisture")
assertEqual(source, "precipitation", "precipitation source")
moisture = antiIce.visibleMoisture(copy(base, { snow_ratio = 0.01 }))
assertTrue(moisture, "snow is visible moisture")
moisture = antiIce.visibleMoisture(copy(base, { hail_ratio = 0.01 }))
assertTrue(moisture, "hail is visible moisture")
moisture = antiIce.visibleMoisture(copy(base, { visibility_sm = 1 }))
assertTrue(moisture, "fog visibility is visible moisture")
moisture = antiIce.visibleMoisture(copy(base, { in_cloud_layer = true }))
assertTrue(moisture, "cloud layer is visible moisture")
moisture = antiIce.visibleMoisture(copy(base, { frame_ice_right = 0.003 }))
assertTrue(moisture, "right-side structural ice is moisture evidence")
moisture = antiIce.visibleMoisture(base)
assertFalse(moisture, "dry air is not visible moisture")

local state, result = update(nil, 0)
state, result = update(state, 29)
assertEqual(result.engine_demand, nil, "dry startup remains unresolved before clear latch")
state, result = update(state, 30)
assertFalse(result.engine_demand, "dry engine anti-ice demand clears after latch")
assertFalse(result.wing_demand, "dry wing anti-ice demand clears after latch")

state, result = update(nil, 0, { in_cloud_layer = true })
state, result = update(state, 6, { in_cloud_layer = true })
assertTrue(result.engine_demand, "engine anti-ice required in stable cold cloud")
assertEqual(result.engine_reason, "cloud-layer", "engine cloud demand reason")
assertEqual(result.wing_demand, nil, "wing anti-ice not inferred from short cloud encounter")
state, result = update(state, 10)
state, result = update(state, 39)
assertTrue(result.engine_demand, "engine anti-ice remains on before moisture clear latch")
state, result = update(state, 40)
assertFalse(result.engine_demand, "engine anti-ice clears after stable dry period")

state, result = update(nil, 0, { frame_ice_right = 0.02 })
state, result = update(state, 6, { frame_ice_right = 0.02, pressure_altitude_ft = 36000 })
assertTrue(result.engine_demand, "right-side ice requires engine anti-ice")
assertTrue(result.wing_demand, "right-side structural ice requires wing anti-ice")
assertEqual(result.wing_reason, "structural-ice", "structural wing demand reason")
assertTrue(result.high_altitude_wing_caution, "high altitude wing anti-ice caution")

state, result = update(nil, 0, { frame_ice_left = 0.02 })
state, result = update(state, 5)
state, result = update(state, 35)
assertFalse(result.engine_demand, "short ice spike does not latch engine demand")
assertFalse(result.wing_demand, "short ice spike does not latch wing demand")

state, result = update(nil, 0, {
    in_cloud_layer = true,
    climb_or_cruise = true,
    sat_c = -41
})
state, result = update(state, 6, {
    in_cloud_layer = true,
    climb_or_cruise = true,
    sat_c = -41
})
assertFalse(result.engine_demand, "SAT below minus 40 suppresses engine anti-ice in climb or cruise")
assertEqual(result.engine_reason, "sat-below-minus-40", "cold SAT reason")

state, result = update(nil, 0, {
    in_cloud_layer = true,
    climb_or_cruise = false,
    sat_c = -41
})
state, result = update(state, 6, {
    in_cloud_layer = true,
    climb_or_cruise = false,
    sat_c = -41
})
assertTrue(result.engine_demand, "descent keeps engine anti-ice in icing below minus 40 SAT")

state, result = update(nil, 0, { in_cloud_layer = true })
state, result = update(state, 6, { in_cloud_layer = true })
state, result = update(state, 10, { in_cloud_layer = true, tat_c = 11 })
state, result = update(state, 15, { in_cloud_layer = true, tat_c = 11 })
assertTrue(result.engine_demand, "warm transition is latched")
state, result = update(state, 16, { in_cloud_layer = true, tat_c = 11 })
assertFalse(result.engine_demand, "warm TAT clears engine anti-ice after latch")
assertFalse(result.wing_demand, "warm TAT clears wing anti-ice after latch")

state, result = update(nil, 0, { in_cloud_layer = true, hold_active = true })
state, result = update(state, 6, { in_cloud_layer = true, hold_active = true })
state, result = update(state, 65, { in_cloud_layer = true, hold_active = true })
assertFalse(result.wing_demand, "hold wing anti-ice waits for extended icing")
state, result = update(state, 66, { in_cloud_layer = true, hold_active = true })
assertTrue(result.wing_demand, "extended icing in hold requires wing anti-ice")
assertEqual(result.wing_reason, "extended-hold-icing", "hold wing demand reason")
state, result = update(state, 70, { in_cloud_layer = true, hold_active = false })
state, result = update(state, 99, { in_cloud_layer = true, hold_active = false })
assertTrue(result.wing_demand, "hold release is latched")
state, result = update(state, 100, { in_cloud_layer = true, hold_active = false })
assertFalse(result.wing_demand, "hold release clears after stable interval")

state, result = update(nil, 0, { in_cloud_layer = true })
state, result = update(state, 6, { in_cloud_layer = true })
state, result = update(state, 605, { in_cloud_layer = true })
assertFalse(result.wing_demand, "general icing waits ten minutes")
state, result = update(state, 606, { in_cloud_layer = true })
assertTrue(result.wing_demand, "ten minutes of icing requires wing anti-ice")
assertEqual(result.wing_reason, "extended-icing", "extended icing reason")

state, result = update(nil, 0, { frame_ice_left = 0.02 })
state, result = update(state, 6, { frame_ice_left = 0.02 })
state, result = update(state, 10)
state, result = update(state, 39)
assertTrue(result.wing_demand, "structural ice remains latched before clear interval")
state, result = update(state, 40)
assertFalse(result.wing_demand, "structural wing demand clears after one clear latch")

state, result = antiIce.update(state, copy(base, { now = 41, enabled = false }))
assertTrue(result.reset, "disabled feature resets active runtime")
state, result = update(state, 100, { in_cloud_layer = true })
state, result = update(state, 50, { in_cloud_layer = true })
assertEqual(result.engine_demand, nil, "time regression resets latches")

print("test_anti_ice: all checks passed")
