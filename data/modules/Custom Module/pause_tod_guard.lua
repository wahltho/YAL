local P = {}

local function finiteNumber(value)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    return number
end

P.ARM_MIN_TOD_NM = 2
P.ARM_MAX_TOD_NM = 8.5
P.MCP_DESCENT_DELTA_FT = 100
P.DESCENT_VS_FPM = -300
P.RELEASE_GRACE_SEC = 10
P.CONFIRM_WINDOW_SEC = 10

function P.isMcpDescentSelected(currentMcpFt, cruiseAltitudeFt)
    local currentMcp = finiteNumber(currentMcpFt)
    local cruiseAltitude = finiteNumber(cruiseAltitudeFt)
    if not currentMcp or currentMcp <= 0 or not cruiseAltitude or cruiseAltitude <= 0 then
        return false
    end

    local cruiseRounded = math.floor((cruiseAltitude / 100) + 0.5) * 100
    return (cruiseRounded - currentMcp) >= P.MCP_DESCENT_DELTA_FT
end

function P.autoDisableOwnershipAction(input)
    input = input or {}
    if input.owned ~= true then return "none" end
    if input.pause_setting_on == true then return "clear" end
    if input.airborne ~= true then return "restore" end
    if input.flightstate ~= input.cruise_flightstate
        or input.fms_phase ~= input.cruise_fms_phase then
        return "restore"
    end
    return "hold"
end

function P.isArmEligible(input)
    input = input or {}
    local todDistance = finiteNumber(input.tod_distance_nm)

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

    local todDistance = finiteNumber(input.tod_distance_nm)
    if not todDistance then return "accept", "tod-invalid" end
    if todDistance <= 0 then return "accept", "tod-passed" end
    if todDistance <= P.ARM_MIN_TOD_NM then return "accept", "tod-context-changed" end
    if todDistance > P.ARM_MAX_TOD_NM then return "accept", "tod-context-changed" end

    local baselineMcp = tonumber(input.baseline_mcp_ft)
    local currentMcp = tonumber(input.current_mcp_ft)
    if baselineMcp and baselineMcp > 0 and currentMcp and currentMcp > 0
        and (baselineMcp - currentMcp) >= P.MCP_DESCENT_DELTA_FT then
        return "accept", "mcp-lowered"
    end
    if P.isMcpDescentSelected(currentMcp, input.cruise_altitude_ft) then
        return "accept", "mcp-below-cruise"
    end

    local verticalSpeed = tonumber(input.vertical_speed_fpm)
    if verticalSpeed and verticalSpeed <= P.DESCENT_VS_FPM then
        return "accept", "descent-established"
    end

    return "repause", "unchanged-cruise"
end

function P.evaluateReleaseWithGrace(input)
    input = input or {}
    local action, reason = P.evaluateRelease(input)
    if action == "accept" then return action, reason end

    local now = tonumber(input.now) or 0
    local graceUntil = tonumber(input.grace_until)
    if not graceUntil or now < graceUntil then
        return "grace", reason
    end
    return "repause", reason
end

function P.isNativeSaveLatched(input)
    input = input or {}
    local slot = tonumber(input.expected_slot)
    return slot ~= nil
        and tonumber(input.load_save) == 1
        and tonumber(input.load_save2) == slot
end

function P.evaluateNativeSave(input)
    input = input or {}
    local slot = tonumber(input.expected_slot)
    local loadSave = tonumber(input.load_save)
    local loadSave2 = tonumber(input.load_save2)
    local status = tonumber(input.status)
    local statusSlot = tonumber(input.status_slot)
    local errorCode = tonumber(input.error_code)
    local now = tonumber(input.now) or 0
    local requestedAt = tonumber(input.requested_at) or now
    local timeoutSec = tonumber(input.timeout_sec) or 10

    if not slot then
        return "failed", "save-slot-invalid"
    end
    if loadSave == 0 and status == 2 and statusSlot == slot and errorCode == 0 then
        return "success", "save-complete"
    end
    if (now - requestedAt) >= timeoutSec then
        return "failed", "save-timeout"
    end
    if loadSave == 1 and loadSave2 == slot then
        return "wait", "save-pending"
    end
    if loadSave == 0 then
        return "failed", "save-status-mismatch"
    end
    return "failed", "save-latch-lost"
end

return P
