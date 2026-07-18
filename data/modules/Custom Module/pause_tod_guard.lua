local P = {}

P.ARM_MIN_TOD_NM = 2
P.ARM_MAX_TOD_NM = 8.5
P.MCP_DESCENT_DELTA_FT = 100
P.DESCENT_VS_FPM = -300
P.CONFIRM_WINDOW_SEC = 10

function P.isArmEligible(input)
    input = input or {}
    local todDistance = tonumber(input.tod_distance_nm)

    if input.monitor_active ~= true then return false, "monitor-inactive" end
    if input.pause_setting_on ~= true then return false, "pause-setting-off" end
    if input.airborne ~= true then return false, "not-airborne" end
    if input.in_cruise ~= true then return false, "not-in-cruise" end
    if not todDistance then return false, "tod-invalid" end
    if todDistance <= P.ARM_MIN_TOD_NM or todDistance > P.ARM_MAX_TOD_NM then
        return false, "outside-tod-window"
    end
    return true, "tod-pause"
end

function P.evaluateRelease(input)
    input = input or {}
    local now = tonumber(input.now) or 0
    local confirmUntil = tonumber(input.confirm_until)

    if confirmUntil and now <= confirmUntil then
        return "accept", "confirmed-release"
    end
    if input.pause_setting_on ~= true then return "accept", "pause-setting-off" end
    if input.airborne ~= true then return "accept", "not-airborne" end
    if input.in_cruise ~= true then return "accept", "left-cruise" end

    local todDistance = tonumber(input.tod_distance_nm)
    if not todDistance then return "accept", "tod-invalid" end
    if todDistance <= 0 then return "accept", "tod-passed" end
    if todDistance > P.ARM_MAX_TOD_NM then return "accept", "tod-context-changed" end

    local baselineMcp = tonumber(input.baseline_mcp_ft)
    local currentMcp = tonumber(input.current_mcp_ft)
    if baselineMcp and baselineMcp > 0 and currentMcp and currentMcp > 0
        and (baselineMcp - currentMcp) >= P.MCP_DESCENT_DELTA_FT then
        return "accept", "mcp-lowered"
    end

    local verticalSpeed = tonumber(input.vertical_speed_fpm)
    if verticalSpeed and verticalSpeed <= P.DESCENT_VS_FPM then
        return "accept", "descent-established"
    end

    return "repause", "unchanged-cruise"
end

return P
