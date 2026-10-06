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
    height_agl_ft = 10000,
    in_cloud_layer = false,
    frame_ice_left = 0,
    frame_ice_right = 0,
    ice_delta = 0,
    pressure_altitude_ft = 10000
}

local function update(state, now, overrides)
    return antiIce.update(state, copy(base, copy(overrides, { now = now })))
end

assertTrue(antiIce.isInCloudLayer(1500, { 0.6 }, { 1000 }, { 2000 }), "inside cloud layer")
assertFalse(antiIce.isInCloudLayer(2500, { 0.6 }, { 1000 }, { 2000 }), "above cloud layer")
assertFalse(antiIce.isInCloudLayer(1500, { 0.49 }, { 1000 }, { 2000 }), "insufficient cloud coverage")

local forecastInput = {
    elevation_m = 3000,
    vertical_speed_fpm = -1200,
    tat_c = 5,
    sat_c = -5,
    climb_or_cruise = false,
    cloud_coverage = { 0.8 },
    cloud_bases_m = { 1800 },
    cloud_tops_m = { 2800 },
    temperature_altitudes_m = { 0, 1000, 2000, 3000, 4000, 5000 },
    temperatures_aloft_c = { 10, 5, 0, -5, -10, -15 }
}
local forecast = antiIce.analyzeVerticalIcingCorridor(forecastInput)
assertTrue(forecast.valid, "vertical icing forecast is valid")
assertTrue(forecast.entry_sec > 0 and forecast.entry_sec <= 60,
    "descent forecast finds the layer before entry")
assertTrue(forecast.qualifying_duration_sec >= 120,
    "descent forecast resolves a sustained cold-moisture corridor")

local earlyDescent = copy(forecastInput, {
    elevation_m = 1600,
    cloud_bases_m = { 200 },
    cloud_tops_m = { 1050 },
    temperatures_aloft_c = { -5, -5, -5, -5, -5, -5 }
})
local earlyForecast = antiIce.analyzeVerticalIcingCorridor(earlyDescent)
assertTrue(earlyForecast.valid and earlyForecast.entry_sec > 60
    and earlyForecast.entry_sec <= 120,
    "descent sees a sustained layer before the former sixty-second limit")

local layeredDescent = copy(earlyDescent, {
    elevation_m = 2000,
    cloud_coverage = { 0.8, 0.8 },
    cloud_bases_m = { 1900, 900 },
    cloud_tops_m = { 2000, 1700 }
})
local layeredForecast = antiIce.analyzeVerticalIcingCorridor(layeredDescent)
assertTrue(layeredForecast.corridors[1].qualifying_duration_sec < 45,
    "first cloud layer is too short")
assertTrue(layeredForecast.entry_sec > 0
    and layeredForecast.qualifying_duration_sec >= 45,
    "a later sustained layer is selected beyond the short layer")

local moisture, source = antiIce.visibleMoisture(copy(base, { precipitation_ratio = 0.01 }))
assertTrue(moisture, "precipitation is visible moisture")
assertEqual(source, "precipitation", "precipitation source")
moisture = antiIce.visibleMoisture(copy(base, { snow_ratio = 0.01 }))
assertTrue(moisture, "snow is visible moisture")
moisture = antiIce.visibleMoisture(copy(base, { hail_ratio = 0.01 }))
assertTrue(moisture, "hail is visible moisture")
moisture = antiIce.visibleMoisture(copy(base, { visibility_sm = 1 }))
assertFalse(moisture, "low visibility aloft is not fog evidence")
moisture, source = antiIce.visibleMoisture(copy(base, { visibility_sm = 1, height_agl_ft = 1500 }))
assertTrue(moisture, "low visibility near terrain is fog evidence")
assertEqual(source, "fog", "fog source")
moisture, source = antiIce.visibleMoisture(copy(base, {
    visibility_sm = 1,
    height_agl_ft = 1000,
    in_cloud_layer = true
}))
assertTrue(moisture, "cloud remains visible moisture in low visibility")
assertEqual(source, "cloud-layer", "cloud source takes priority over fog")
moisture = antiIce.visibleMoisture(copy(base, { in_cloud_layer = true }))
assertTrue(moisture, "cloud layer is visible moisture")
moisture, source = antiIce.visibleMoisture(copy(base, { ice_delta = 0.0001 }))
assertTrue(moisture, "positive ice delta is active icing evidence")
assertEqual(source, "active-icing", "active icing source")
moisture = antiIce.visibleMoisture(copy(base, { ice_delta = -0.0001 }))
assertFalse(moisture, "negative ice delta is removal, not moisture evidence")
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

state, result = update(nil, 0, { visibility_sm = 0.5, height_agl_ft = 18000 })
state, result = update(state, 6, { visibility_sm = 0.5, height_agl_ft = 18000 })
assertEqual(result.engine_demand, nil, "low reported visibility aloft does not demand engine anti-ice")
state, result = update(nil, 0, { visibility_sm = 0.5, height_agl_ft = 1000 })
state, result = update(state, 6, { visibility_sm = 0.5, height_agl_ft = 1000 })
assertEqual(result.engine_demand, nil, "fog waits for complete engine anti-ice ON stability")
state, result = update(state, 15, { visibility_sm = 0.5, height_agl_ft = 1000 })
assertTrue(result.engine_demand, "stable low-altitude fog requires engine anti-ice")
assertEqual(result.engine_reason, "fog", "low-altitude fog demand reason")

state, result = update(nil, 0, { in_cloud_layer = true })
state, result = update(state, 6, { in_cloud_layer = true })
assertEqual(result.engine_demand, nil, "cloud waits for complete engine anti-ice ON stability")
state, result = update(state, 15, { in_cloud_layer = true })
assertTrue(result.engine_demand, "engine anti-ice required in stable cold cloud")
assertEqual(result.engine_reason, "cloud-layer", "engine cloud demand reason")
assertEqual(result.wing_demand, nil, "wing anti-ice not inferred from short cloud encounter")
state, result = update(state, 20)
state, result = update(state, 49)
assertTrue(result.engine_demand, "engine anti-ice remains on before moisture clear latch")
state, result = update(state, 50)
state, result = update(state, 79)
assertTrue(result.engine_demand, "engine anti-ice remains on before combined clear latch")
state, result = update(state, 80)
assertFalse(result.engine_demand, "engine anti-ice clears after sixty stable dry seconds")

state, result = update(nil, 0, { frame_ice_right = 0.02 })
state, result = update(state, 6, { frame_ice_right = 0.02 })
assertEqual(result.engine_demand, nil, "structural icing waits for engine ON stability")
state, result = update(state, 15, { frame_ice_right = 0.02 })
assertTrue(result.engine_demand, "right-side ice requires engine anti-ice")
assertTrue(result.wing_demand, "right-side structural ice requires wing anti-ice")
assertEqual(result.wing_reason, "structural-ice", "structural wing demand reason")

state, result = update(nil, 0, { frame_ice_right = 0.02, pressure_altitude_ft = 36000 })
state, result = update(state, 6, { frame_ice_right = 0.02, pressure_altitude_ft = 36000 })
assertFalse(result.wing_demand, "high altitude inhibits wing anti-ice")
assertEqual(result.wing_reason, "altitude-above-fl350", "high altitude inhibit reason")
assertTrue(result.wing_ice_inhibited, "structural ice remains visible while high-altitude inhibited")

state, result = update(nil, 0, { frame_ice_right = 0.02, pressure_altitude_ft = 34000 })
state, result = update(state, 6, { frame_ice_right = 0.02, pressure_altitude_ft = 34000 })
assertTrue(result.wing_demand, "structural ice below FL350 requires wing anti-ice")
state, result = update(state, 7, { frame_ice_right = 0.02, pressure_altitude_ft = 35000 })
assertFalse(result.wing_demand, "climbing through FL350 immediately inhibits wing anti-ice")
assertTrue(result.wing_changed, "FL350 crossing publishes the wing demand transition")
state, result = update(state, 8, { frame_ice_right = 0.02, pressure_altitude_ft = 34999 })
assertTrue(result.wing_demand, "descending below FL350 restores structural wing demand")

state, result = update(nil, 0, { frame_ice_right = 0.02, tat_c = 11 })
state, result = update(state, 6, { frame_ice_right = 0.02, tat_c = 11 })
assertFalse(result.wing_demand, "warm TAT inhibits wing anti-ice")
assertEqual(result.wing_reason, "tat-above-10", "warm TAT wing inhibit reason")
assertTrue(result.wing_ice_inhibited, "structural ice remains visible while warm-TAT inhibited")

state, result = update(nil, 0, { frame_ice_right = 0.02, height_agl_ft = 300 })
state, result = update(state, 6, { frame_ice_right = 0.02, height_agl_ft = 300 })
assertFalse(result.wing_demand, "below 400 feet inhibits wing anti-ice")
assertEqual(result.wing_reason, "below-400-feet-agl", "low-AGL wing inhibit reason")
assertTrue(result.wing_ice_inhibited, "structural ice remains visible while low-AGL inhibited")
state, result = update(state, 7, { frame_ice_right = 0.02, height_agl_ft = 400 })
assertTrue(result.wing_demand, "at 400 feet structural wing anti-ice demand is permitted")

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
assertEqual(result.engine_demand, nil, "descent cold cloud waits for engine ON stability")
state, result = update(state, 15, {
    in_cloud_layer = true,
    climb_or_cruise = false,
    sat_c = -41
})
assertTrue(result.engine_demand, "descent keeps engine anti-ice in icing below minus 40 SAT")

state, result = update(nil, 0, { in_cloud_layer = true })
state, result = update(state, 15, { in_cloud_layer = true })
state, result = update(state, 20, { in_cloud_layer = true, tat_c = 11 })
state, result = update(state, 25, { in_cloud_layer = true, tat_c = 11 })
assertTrue(result.engine_demand, "warm transition is latched")
state, result = update(state, 26, { in_cloud_layer = true, tat_c = 11 })
assertFalse(result.engine_demand, "warm TAT clears engine anti-ice after latch")
assertFalse(result.wing_demand, "warm TAT clears wing anti-ice after latch")
state, result = update(state, 27, { in_cloud_layer = true, tat_c = 9 })
assertEqual(result.engine_demand, nil, "engine anti-ice re-enable enters confirming state")
state, result = update(state, 41, { in_cloud_layer = true, tat_c = 9 })
assertEqual(result.engine_demand, nil, "engine anti-ice re-enable remains pending before fifteen seconds")
state, result = update(state, 42, { in_cloud_layer = true, tat_c = 9 })
assertTrue(result.engine_demand, "engine anti-ice re-enables after stable eligible conditions")

state, result = update(nil, 0, { in_cloud_layer = true, tat_c = 9.6 })
state, result = update(state, 14, { in_cloud_layer = true, tat_c = 9.6 })
assertEqual(result.engine_demand, nil, "brief near-limit icing does not enable early")
state, result = update(state, 15, { in_cloud_layer = true, tat_c = 10.1 })
state, result = update(state, 21, { in_cloud_layer = true, tat_c = 10.4 })
assertEqual(result.engine_demand, nil, "warming through ten degrees never creates a short ON cycle")

local forecastBase = copy(base, forecastInput)
state, result = antiIce.update(nil, copy(forecastBase, { now = 0 }))
state, result = antiIce.update(state, copy(forecastBase, { now = 15 }))
assertTrue(result.engine_demand, "sustained descent layer is anticipated before entry")
assertEqual(result.engine_reason, "icing-layer-ahead", "anticipated layer reason")

state, result = antiIce.update(nil, copy(base, copy(earlyDescent, { now = 0 })))
state, result = antiIce.update(state, copy(base, copy(earlyDescent, { now = 15 })))
assertTrue(result.engine_demand, "descent starts anti-ice before the former sixty-second entry window")

state, result = antiIce.update(nil, copy(base, copy(layeredDescent, { now = 0 })))
state, result = antiIce.update(state, copy(base, copy(layeredDescent, { now = 15 })))
assertTrue(result.engine_demand, "short cloud layer does not hide the sustained layer behind it")

state, result = update(nil, 0, { in_cloud_layer = true, height_agl_ft = 2000 })
state, result = update(state, 15, { in_cloud_layer = true, height_agl_ft = 2000 })
assertTrue(result.engine_demand, "actual icing on final remains actionable below 2500 feet")

local shortLayer = copy(base, {
    elevation_m = 2500,
    vertical_speed_fpm = -1000,
    tat_c = 5,
    sat_c = -5,
    in_cloud_layer = true,
    cloud_coverage = { 0.8 },
    cloud_bases_m = { 2400 },
    cloud_tops_m = { 2600 },
    temperature_altitudes_m = { 0, 1000, 2000, 3000, 4000, 5000 },
    temperatures_aloft_c = { 0, -2, -4, -6, -8, -10 }
})
state, result = antiIce.update(nil, copy(shortLayer, { now = 0 }))
state, result = antiIce.update(state, copy(shortLayer, { now = 15 }))
assertEqual(result.engine_demand, nil, "short layer does not create a pointless new ON demand")
assertEqual(result.engine_reason, "icing-corridor-short", "short layer suppression reason")

local sustainedLayer = copy(base, {
    elevation_m = 3000,
    vertical_speed_fpm = -1000,
    tat_c = 5,
    sat_c = -5,
    in_cloud_layer = true,
    cloud_coverage = { 0.8 },
    cloud_bases_m = { 0 },
    cloud_tops_m = { 5000 },
    temperature_altitudes_m = { 0, 1000, 2000, 3000, 4000, 5000 },
    temperatures_aloft_c = { -5, -5, -5, -5, -5, -5 }
})
state, result = antiIce.update(nil, copy(sustainedLayer, { now = 0 }))
state, result = antiIce.update(state, copy(sustainedLayer, { now = 15 }))
assertTrue(result.engine_demand, "sustained same-layer fixture starts ON")
state, result = antiIce.update(state, copy(sustainedLayer, { now = 20, tat_c = 11 }))
state, result = antiIce.update(state, copy(sustainedLayer, { now = 26, tat_c = 11 }))
assertFalse(result.engine_demand, "stable cockpit TAT above ten turns demand OFF")

local marginalRearm = copy(sustainedLayer, {
    tat_c = 9,
    sat_c = 0,
    temperatures_aloft_c = { 5, 4, 2, 0, -5, -10 }
})
state, result = antiIce.update(state, copy(marginalRearm, { now = 27 }))
state, result = antiIce.update(state, copy(marginalRearm, { now = 160 }))
assertEqual(result.engine_demand, nil, "short cold pocket in same layer stays neutral after warm OFF")
assertEqual(result.engine_reason, "icing-corridor-short", "same-layer rearm suppression reason")

state, result = antiIce.update(state, copy(sustainedLayer, { now = 161 }))
state, result = antiIce.update(state, copy(sustainedLayer, { now = 176 }))
assertTrue(result.engine_demand, "sustained cold corridor re-arms after confirmation")

state, result = antiIce.update(nil, copy(sustainedLayer, { now = 0 }))
state, result = antiIce.update(state, copy(sustainedLayer, { now = 15 }))
state, result = antiIce.update(state, copy(sustainedLayer, { now = 20, tat_c = 11 }))
state, result = antiIce.update(state, copy(sustainedLayer, { now = 26, tat_c = 11 }))
state, result = antiIce.update(state, copy(marginalRearm, { now = 27, precipitation_ratio = 0.02 }))
state, result = antiIce.update(state, copy(marginalRearm, { now = 42, precipitation_ratio = 0.02 }))
assertTrue(result.engine_demand, "strong precipitation evidence bypasses layer-only rearm suppression")

state, result = update(nil, 0, { in_cloud_layer = true })
state, result = update(state, 15, { in_cloud_layer = true })
assertTrue(result.engine_demand, "reason-only transition fixture starts ON")
state, result = update(state, 16, { snow_ratio = 0.02 })
assertTrue(result.engine_demand, "snow source keeps engine demand ON")
assertFalse(result.engine_changed, "source-only transition does not publish a demand change")
assertTrue(result.engine_reason_changed, "source-only transition remains diagnostic")
assertEqual(result.engine_reason, "snow", "source-only transition updates reason")

state, result = update(nil, 0, { in_cloud_layer = true })
state, result = update(state, 6, { in_cloud_layer = true })
state, result = update(state, 3606, { in_cloud_layer = true })
assertFalse(result.wing_demand, "visible moisture alone never infers wing anti-ice demand")

state, result = update(nil, 0, { frame_ice_left = 0.02 })
state, result = update(state, 6, { frame_ice_left = 0.02 })
state, result = update(state, 10)
state, result = update(state, 39)
assertTrue(result.wing_demand, "structural ice remains latched before clear interval")
state, result = update(state, 40)
assertFalse(result.structural_active, "structural sensor clears after thirty dry seconds")
assertTrue(result.wing_demand, "cleared sensor alone does not release active wing protection")
assertFalse(result.wing_changed, "sensor clearing does not reset wing advice or command state")
state, result = update(state, 129)
assertTrue(result.wing_demand, "wing protection holds until 120 continuous clear seconds")
state, result = update(state, 130)
assertFalse(result.wing_demand, "wing protection clears at 120 continuous clear seconds")
assertTrue(result.wing_changed, "complete clear interval publishes a wing OFF transition")

state, result = update(nil, 0, { frame_ice_left = 0.02, ice_delta = 0.0001 })
state, result = update(state, 15, { frame_ice_left = 0.02, ice_delta = 0.0001 })
assertTrue(result.engine_demand, "active structural icing requires engine anti-ice")
assertTrue(result.wing_demand, "active structural icing requires wing anti-ice")
state, result = update(state, 20, { frame_ice_left = 0.002, ice_delta = -0.0001 })
state, result = update(state, 49, { frame_ice_left = 0, ice_delta = -0.0001 })
assertTrue(result.engine_demand, "negative ice delta remains latched only before clear interval")
assertTrue(result.wing_demand, "structural ice remains latched before clear interval")
state, result = update(state, 50, { frame_ice_left = 0, ice_delta = -0.0001 })
assertTrue(result.engine_demand, "engine demand starts its combined clear latch")
assertTrue(result.wing_demand, "cleared structural ice does not release wing demand early")
state, result = update(state, 79, { frame_ice_left = 0, ice_delta = -0.0001 })
assertTrue(result.engine_demand, "negative ice delta remains latched before combined clear interval")
state, result = update(state, 80, { frame_ice_left = 0, ice_delta = -0.0001 })
assertFalse(result.engine_demand, "negative ice delta cannot hold engine demand indefinitely")
assertTrue(result.wing_demand, "wing clear interval is independent of engine demand")
state, result = update(state, 140, { frame_ice_left = 0, ice_delta = -0.0001 })
assertFalse(result.wing_demand, "negative ice delta does not hold wing protection indefinitely")

for _, ongoing in ipairs({
    { in_cloud_layer = true },
    { precipitation_ratio = 0.02 },
    { snow_ratio = 0.02 },
    { hail_ratio = 0.02 },
    { visibility_sm = 0.5, height_agl_ft = 1000 },
    { ice_delta = 0.0001402 }
}) do
    state, result = update(nil, 0, { frame_ice_right = 0.0141 })
    state, result = update(state, 6, { frame_ice_right = 0.0141 })
    state, result = update(state, 7, ongoing)
    state, result = update(state, 37, ongoing)
    assertFalse(result.structural_active, "protection may clear the measured ice")
    state, result = update(state, 367, ongoing)
    assertTrue(result.wing_demand, "ongoing icing keeps wing protection after measured ice is removed")
    assertFalse(result.wing_changed, "ongoing icing never publishes a premature Wing OFF")
    assertEqual(state.wing_clear_since, nil, "ongoing icing prevents clear timer accumulation")
end

state, result = update(nil, 0, { frame_ice_left = 0.0141, in_cloud_layer = true })
state, result = update(state, 6, { frame_ice_left = 0.0141, in_cloud_layer = true })
state, result = update(state, 10)
state, result = update(state, 100, { ice_delta = 0.0001402 })
state, result = update(state, 101)
state, result = update(state, 220)
assertTrue(result.wing_demand, "renewed icing restarts the complete clear interval")
state, result = update(state, 221)
assertFalse(result.wing_demand, "wing clears only after a new uninterrupted 120-second interval")

state, result = update(nil, 0, { frame_ice_left = 0.0141 })
state, result = update(state, 6, { frame_ice_left = 0.0141 })
state, result = update(state, 10)
state, result = antiIce.update(state, copy(base, copy(earlyDescent, { now = 100 })))
state, result = antiIce.update(state, copy(base, copy(earlyDescent, { now = 300 })))
assertTrue(result.wing_demand, "sustained upcoming descent layer bridges an ice-free gap")
assertEqual(state.wing_clear_since, nil, "qualifying forecast resets the wing clear interval")
state, result = update(state, 301)
state, result = update(state, 420)
assertTrue(result.wing_demand, "wing remains ON before the post-corridor clear interval completes")
state, result = update(state, 421)
assertFalse(result.wing_demand, "wing clears once the corridor and current icing stay absent")

state, result = antiIce.update(nil, copy(base, copy(earlyDescent, { now = 0 })))
state, result = antiIce.update(state, copy(base, copy(earlyDescent, { now = 360 })))
assertFalse(result.wing_demand, "forecast alone never starts wing protection without structural ice")

for _, inhibit in ipairs({
    { pressure_altitude_ft = 35000 },
    { tat_c = 11 },
    { height_agl_ft = 399 }
}) do
    state, result = update(nil, 0, { frame_ice_left = 0.0141 })
    state, result = update(state, 6, { frame_ice_left = 0.0141 })
    state, result = update(state, 10)
    state, result = update(state, 40, inhibit)
    assertFalse(result.wing_demand, "safety inhibit overrides the active wing clear latch immediately")
    assertEqual(state.wing_clear_since, nil, "inhibit discards the pending clear timer")
    state, result = update(state, 41, { in_cloud_layer = true })
    assertFalse(result.wing_demand, "old latch cannot re-enable wing without structural ice after an inhibit")
end

state, result = update(nil, 0, { frame_ice_left = 0.0141 })
state, result = update(state, 6, { frame_ice_left = 0.0141 })
state, result = update(state, 10)
local missingTemperature = copy(base, { now = 100 })
missingTemperature.tat_c = nil
state, result = antiIce.update(state, missingTemperature)
assertTrue(result.wing_demand, "missing TAT preserves protection instead of releasing it")
assertEqual(state.wing_clear_since, nil, "unknown temperature does not count as clear time")
state, result = update(state, 101)
state, result = update(state, 220)
assertTrue(result.wing_demand, "valid conditions must complete a fresh interval after missing TAT")
state, result = update(state, 221)
assertFalse(result.wing_demand, "valid clear conditions eventually release wing protection")

for _, reset in ipairs({ { enabled = false }, { airborne = false }, { now = 5 } }) do
    state, result = update(nil, 0, { frame_ice_left = 0.0141 })
    state, result = update(state, 6, { frame_ice_left = 0.0141 })
    state, result = update(state, 10)
    state, result = antiIce.update(state, copy(base, copy({ now = 100 }, reset)))
    assertEqual(state.wing_clear_since, nil, "runtime reset discards the active wing clear interval")
    assertEqual(result.wing_demand, nil, "runtime reset cannot carry an old wing ON demand")
end

state, result = update(nil, 0, { in_cloud_layer = true })
state, result = update(state, 6, { in_cloud_layer = true })
state, result = update(state, 606, { ice_delta = -0.0001, pressure_altitude_ft = 39000 })
assertFalse(result.wing_demand, "stale moisture cannot create cruise wing anti-ice demand")
assertEqual(result.wing_reason, "altitude-above-fl350", "cruise altitude remains hard-inhibited")
assertFalse(result.wing_ice_inhibited, "no structural ice means no high-altitude icing warning")

state, result = antiIce.update(state, copy(base, { now = 41, enabled = false }))
assertTrue(result.reset, "disabled feature resets active runtime")
state, result = update(state, 100, { in_cloud_layer = true })
state, result = update(state, 50, { in_cloud_layer = true })
assertEqual(result.engine_demand, nil, "time regression resets latches")

print("test_anti_ice: all checks passed")
