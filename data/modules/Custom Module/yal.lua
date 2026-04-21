local P = {}
yal = P

local def = require("definitions")
require("settings")
local PD = require("proceduredata")
local VR = require("voicereadback")

--------------------------------------------------------------------------------------------------------------

local menu_master = sasl.appendMenuItem(PLUGINS_MENU_ID, def.APPNAMEPREFIXLONG)
P.menu_main = sasl.createMenu("", PLUGINS_MENU_ID, menu_master)

--------------------------------------------------------------------------------------------------------------
-- Flags & Global Variables

local function anyProcedureRunning()
    if not P.loopStateTables then
        return false
    end
    for _, loop in pairs(P.loopStateTables) do
        if loop and loop.lock and loop.lock ~= def.NOPROCEDURE then
            return true
        end
    end
    return false
end

local function autoRestartEnabled()
    if not P.configvalues then
        return false
    end
    return (tonumber(P.configvalues[def.CONFIGAUTORESTARTDEV] or 0) == def.ON)
end

local function devReloadEnabled()
    if not P.configvalues then
        return false
    end
    if tonumber(P.configvalues[def.CONFIGDEBUGOVERLAY] or 0) ~= def.ON then
        return false
    end
    if P.YalMaintenanceExecutorIsInstalled then
        return P.YalMaintenanceExecutorIsInstalled()
    end
    return false
end

local function hoppieVoiceEnabled()
    if not P.configvalues then
        return false
    end
    return (tonumber(P.configvalues[def.CONFIGHOPPIEVOICE] or 0) == def.ON)
end

local function gearProtectionEnabled()
    if settings and settings.appSettings and settings.appSettings[def.CONFIGGEARPROTECTION] ~= nil then
        return (tonumber(settings.appSettings[def.CONFIGGEARPROTECTION] or 0) == def.ON)
    end
    if not P.configvalues then
        return false
    end
    return (tonumber(P.configvalues[def.CONFIGGEARPROTECTION] or 0) == def.ON)
end

local function clearGearProtectionState()
    P.gearProtectionWasAirborne = false
    P.gearProtectionArmedUntil = nil
    P.gearProtectionActiveUntil = nil
    P.gearProtectionLastOnGround = nil
    P.gearProtectionObservedFailures = nil
end

local function clearGearProtectionFailure(dataref, neutralValue, label)
    if not dataref or not isProperty(dataref) then
        return false
    end
    local currentValue = tonumber(get(dataref))
    if currentValue == nil or currentValue == neutralValue then
        return false
    end
    set(dataref, neutralValue)
    helpers.logInfoTS("GearProtection: cleared " .. label .. " (" .. tostring(currentValue) .. " -> " .. tostring(neutralValue) .. ")")
    return true
end

local function logGearProtectionObservedFailure(label, dataref)
    if not dataref or not isProperty(dataref) then
        return
    end
    local currentValue = tonumber(get(dataref))
    if currentValue == nil then
        return
    end
    local observed = P.gearProtectionObservedFailures
    if not observed then
        observed = {}
        P.gearProtectionObservedFailures = observed
    end
    if observed[label] == currentValue then
        return
    end
    observed[label] = currentValue
    helpers.logInfoTS("GearProtection: observed " .. label .. "=" .. tostring(currentValue))
end

local function logGearProtectionObservedFailures()
    logGearProtectionObservedFailure("rel_collapse1", P.rel_collapse1)
    logGearProtectionObservedFailure("rel_collapse2", P.rel_collapse2)
    logGearProtectionObservedFailure("rel_collapse3", P.rel_collapse3)
    logGearProtectionObservedFailure("rel_tire1", P.rel_tire1)
    logGearProtectionObservedFailure("rel_tire2", P.rel_tire2)
    logGearProtectionObservedFailure("rel_tire3", P.rel_tire3)
    logGearProtectionObservedFailure("rel_gear_act", P.rel_gear_act)
end

function P.updateGearProtectionFast()
    if not gearProtectionEnabled() then
        clearGearProtectionState()
        return
    end

    local now = os.time() or 0
    local onGround = (get(P.airgroundsensor) == def.ON)
    local groundspeed = tonumber(get(P.groundspeed)) or 0
    local radioAlt = tonumber(get(P.radioaltitude)) or 99999
    local verticalSpeed = tonumber(get(P.verticalspeed)) or 0

    if not onGround and groundspeed > 80 then
        P.gearProtectionWasAirborne = true
    end

    if (not onGround)
        and P.gearProtectionWasAirborne
        and (groundspeed > 80)
        and (radioAlt > 0)
        and (radioAlt < 1200)
        and (verticalSpeed < -150) then
        local shouldLogArm = (P.gearProtectionArmedUntil == nil) or (P.gearProtectionArmedUntil < now)
        P.gearProtectionArmedUntil = now + 20
        if shouldLogArm then
            helpers.logInfoTS("GearProtection: touchdown armed ra=" .. tostring(math.floor(radioAlt + 0.5)) .. " gs=" .. tostring(math.floor(groundspeed + 0.5)) .. " vs=" .. tostring(math.floor(verticalSpeed + 0.5)))
        end
    end

    if onGround
        and (P.gearProtectionLastOnGround == false)
        and P.gearProtectionWasAirborne
        and P.gearProtectionArmedUntil
        and (P.gearProtectionArmedUntil >= now)
        and (groundspeed > 40) then
        P.gearProtectionActiveUntil = now + 20
        helpers.logInfoTS("GearProtection: active gs=" .. tostring(math.floor(groundspeed + 0.5)))
    end

    if P.gearProtectionActiveUntil and (P.gearProtectionActiveUntil >= now) then
        logGearProtectionObservedFailures()
        clearGearProtectionFailure(P.rel_collapse1, def.FAILURE_HEALTHY, "rel_collapse1")
        clearGearProtectionFailure(P.rel_collapse2, def.FAILURE_HEALTHY, "rel_collapse2")
        clearGearProtectionFailure(P.rel_collapse3, def.FAILURE_HEALTHY, "rel_collapse3")
        clearGearProtectionFailure(P.rel_tire1, def.FAILURE_HEALTHY, "rel_tire1")
        clearGearProtectionFailure(P.rel_tire2, def.FAILURE_HEALTHY, "rel_tire2")
        clearGearProtectionFailure(P.rel_tire3, def.FAILURE_HEALTHY, "rel_tire3")
        if onGround and groundspeed < 40 then
            helpers.logInfoTS("GearProtection: window closed slow-taxi gs=" .. tostring(math.floor(groundspeed + 0.5)))
            P.gearProtectionActiveUntil = nil
            P.gearProtectionArmedUntil = nil
            P.gearProtectionWasAirborne = false
        end
    elseif P.gearProtectionActiveUntil and (P.gearProtectionActiveUntil < now) then
        helpers.logInfoTS("GearProtection: window closed timeout")
        P.gearProtectionActiveUntil = nil
    end

    if onGround and (not P.gearProtectionActiveUntil) and groundspeed < 40 then
        P.gearProtectionArmedUntil = nil
        P.gearProtectionWasAirborne = false
    end

    P.gearProtectionLastOnGround = onGround
end

local function clearTrimAdvicePopupState()
    P.trimAdvicePopupState = nil
end

local function getTrimPopupNowSec()
    return os.time() or 0
end

local function setTrimAdvicePopupState(target, pinned)
    local value = tonumber(target)
    if not value or value <= 0 then
        P.trimAdvicePopupState = nil
        return
    end
    local prev = P.trimAdvicePopupState
    local requestOpenId = prev and tonumber(prev.requestOpenId) or 0
    local holdUntilTs = prev and tonumber(prev.holdUntilTs) or nil
    P.trimAdvicePopupState = {
        active = true,
        target = value,
        pinned = (pinned == true),
        requestOpenId = requestOpenId,
        holdUntilTs = holdUntilTs
    }
end

local function requestTrimAdvicePopupOpen(target, pinned)
    local value = tonumber(target)
    if not value or value <= 0 then
        P.trimAdvicePopupState = nil
        return
    end
    local prev = P.trimAdvicePopupState
    local requestOpenId = (prev and tonumber(prev.requestOpenId) or 0) + 1
    local holdUntilTs = nil
    if pinned == true then
        holdUntilTs = prev and tonumber(prev.holdUntilTs) or nil
    else
        holdUntilTs = getTrimPopupNowSec() + 5
    end
    P.trimAdvicePopupState = {
        active = true,
        target = value,
        pinned = (pinned == true),
        requestOpenId = requestOpenId,
        holdUntilTs = holdUntilTs
    }
end

local function maybeRequestTrimAdvicePopupForSpeech(entry_type, entry_text)
    if entry_type ~= def.TEXT or type(entry_text) ~= "string" then
        return
    end
    if string.sub(entry_text, 1, 9) ~= "Set Trim " then
        return
    end
    if (P.configvalues[def.CONFIGTRIMADVICEPOPUP] ~= def.ON)
        or (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
        return
    end

    local target = tonumber(string.sub(entry_text, 10))
    if (not target or target <= 0) and P.trimAdvicePopupState and P.trimAdvicePopupState.active == true then
        target = tonumber(P.trimAdvicePopupState.target)
    end
    if target and target > 0 then
        requestTrimAdvicePopupOpen(target, P._trimAdvicePopupPinned == true)
    end
end

local TAKEOFF_N1_40_MESSAGE = "Both Engine N 1 at 40 Percent"

local function isTakeoffN1CalloutProcedureContext()
    if not P.procedureloop1 then
        return false
    end
    return (P.procedureloop1.lock == def.NOPROCEDURE)
        or (P.procedureloop1.lock == def.BEFORETAKEOFFPROCEDURE)
end

local function isTakeoffAutothrottleActiveNow()
    local throttleHold = (P.atthrottlehold and get(P.atthrottlehold)) or 0
    local throttleLock = (P.atthrottlelock and get(P.atthrottlelock)) or 0
    return (tonumber(throttleHold) or 0) > 0
        or (tonumber(throttleLock) or 0) > 0
end

local function isTakeoffN140CalloutEligible()
    if not isTakeoffN1CalloutProcedureContext() then
        return false
    end

    local atArmPos = get(P.atarmpos)
    local eng1N1 = get(P.eng1n1percent)
    local eng2N1 = get(P.eng2n1percent)

    if atArmPos ~= def.ARMED then
        return false
    end
    if get(P.airgroundsensor) ~= def.ON then
        return false
    end
    if eng1N1 == nil or eng2N1 == nil then
        return false
    end
    if eng1N1 <= 40 or eng2N1 <= 40 then
        return false
    end
    if isTakeoffAutothrottleActiveNow() then
        return false
    end
    return true
end

local function shouldResetTakeoffN140CalloutLatch()
    if not P._takeoffN140CalloutLatched then
        return false
    end

    local atArmPos = get(P.atarmpos)
    local eng1N1 = get(P.eng1n1percent) or 0
    local eng2N1 = get(P.eng2n1percent) or 0

    if atArmPos ~= def.ARMED then
        return true
    end
    if get(P.airgroundsensor) ~= def.ON then
        return true
    end
    if not isTakeoffN1CalloutProcedureContext() then
        return true
    end
    if eng1N1 < 35 and eng2N1 < 35 then
        return true
    end
    return false
end

local function resetTakeoffN140CalloutState()
    P._takeoffN140CalloutLatched = false
end

local function maybeQueueTakeoffN140Callout()
    if shouldResetTakeoffN140CalloutLatch() then
        resetTakeoffN140CalloutState()
    end
    if P._takeoffN140CalloutLatched then
        return
    end
    if not isTakeoffN140CalloutEligible() then
        return
    end
    P.commandtableentry(def.TEXT, TAKEOFF_N1_40_MESSAGE)
    P._takeoffN140CalloutLatched = true
end

local function clearTrimTargetLatch()
    P._ongoingTrimTargetLatched = nil
end

local function getLatchedTrimTarget()
    local latched = tonumber(P._ongoingTrimTargetLatched)
    if latched and latched > 0 then
        return latched
    end
    local trimCalcRaw = tonumber(get(P.trimcalc)) or 0
    local trimTarget = helpers.round_to_step(trimCalcRaw, 0.25) or trimCalcRaw
    if trimTarget and trimTarget > 0 then
        P._ongoingTrimTargetLatched = trimTarget
        return trimTarget
    end
    return nil
end

local function isTrimPopupContextActive()
    local onGround = (get(P.airgroundsensor) == def.ON)
    local noProcedure = (P.procedureloop1.lock == def.NOPROCEDURE)
    local powered = (get(P.battery) == def.ON) and (get(P.mainbus) ~= def.OFF)
    local preflight = (P.flightstate == def.FLIGHTSTATEPREFLIGHT)
    local noTaxi = (get(P.taxilight) == def.OFF)
    local slow = (get(P.groundspeed) < 45)
    local trimTarget = getLatchedTrimTarget() or 0
    return onGround and noProcedure and powered and preflight and noTaxi and slow and (trimTarget > 0), trimTarget
end

local function isTrimPopupManualContextActive()
    local onGround = (get(P.airgroundsensor) == def.ON)
    local powered = (get(P.battery) == def.ON) and (get(P.mainbus) ~= def.OFF)
    local trimTarget = getLatchedTrimTarget() or 0
    return onGround and powered and (trimTarget > 0), trimTarget
end

local function isPeriodicAutoSaveDisabled()
    local raw = P.configvalues and tonumber(P.configvalues[def.CONFIGSAVETIME]) or nil
    if raw == nil then
        return false
    end
    return (raw == 0) or (raw == 9999)
end

local function getAutoSaveSlot()
    local raw = P.configvalues and P.configvalues[def.CONFIGSAVENUMBER] or nil
    if raw == 0 or raw == "0" then
        return 1
    end
    local start = 1
    local finish = 1
    if type(raw) == "number" then
        start = math.floor(raw)
        finish = start
    elseif type(raw) == "string" then
        local s = raw:gsub("%s+", "")
        local a, b = s:match("^(%d+)%-(%d+)$")
        if a and b then
            local n1 = tonumber(a)
            local n2 = tonumber(b)
            if n1 and n2 then
                start = n1
                finish = n2
            end
        else
            local n = tonumber(s)
            if n then
                start = n
                finish = n
            end
        end
    end
    if start < 1 then start = 1 end
    if start > 8 then start = 8 end
    if finish < 1 then finish = 1 end
    if finish > 8 then finish = 8 end
    if start > finish then
        start, finish = finish, start
    end
    local range_key = tostring(start) .. "-" .. tostring(finish)
    local last_slot = P.configvalues and tonumber(P.configvalues[def.CONFIGSAVELAST]) or nil
    if last_slot and (last_slot < start or last_slot > finish) then
        last_slot = nil
    end
    if P._autosaveSlotRange ~= range_key then
        P._autosaveSlotRange = range_key
        if last_slot and start ~= finish then
            local next_slot = last_slot + 1
            if next_slot > finish then
                next_slot = start
            end
            P._autosaveSlotCurrent = next_slot
        else
            P._autosaveSlotCurrent = last_slot or start
        end
    elseif not P._autosaveSlotCurrent or P._autosaveSlotCurrent < start or P._autosaveSlotCurrent > finish then
        P._autosaveSlotCurrent = last_slot or start
    end
    local slot = P._autosaveSlotCurrent or start
    if start ~= finish then
        local next_slot = slot + 1
        if next_slot > finish then
            next_slot = start
        end
        P._autosaveSlotCurrent = next_slot
    else
        P._autosaveSlotCurrent = start
    end
    if P.configvalues then
        P.configvalues[def.CONFIGSAVELAST] = slot
        if settings and settings.appSettings then
            settings.appSettings[def.CONFIGSAVELAST] = slot
            if settings.writeSettings then
                settings.writeSettings(settings.appSettings)
            end
        end
    end
    return slot
end

P.autotaxipause = false

local function normalizeHoppieVoiceText(text)
    if type(text) ~= "string" then
        return ""
    end
    local cleaned = text:gsub("\r\n", "\n")
    cleaned = cleaned:gsub("\r", "\n")
    cleaned = cleaned:gsub("\n\n+", ". ")
    cleaned = cleaned:gsub("\n", " ")
    cleaned = cleaned:gsub("[{}%[%]\"]", " ")
    cleaned = cleaned:gsub("%s+", " ")
    cleaned = cleaned:gsub("^%s+", ""):gsub("%s+$", "")
    cleaned = cleaned:gsub("RWY%s*([0-9][0-9]?[LRC]?)", function(code)
        return "runway " .. helpers.addspaces(code)
    end)
    cleaned = cleaned:gsub("FL%s*(%d%d%d?)", function(code)
        return "flight level " .. helpers.addspaces(code)
    end)
    cleaned = cleaned:gsub("QNH%s*(%d%d%d%d?)", function(code)
        return "Q N H " .. helpers.addspaces(code)
    end)
    cleaned = cleaned:gsub("QFE%s*(%d%d%d%d?)", function(code)
        return "Q F E " .. helpers.addspaces(code)
    end)
    cleaned = cleaned:gsub("SQUAWK%s*(%d%d%d%d)", function(code)
        return "squawk " .. helpers.addspaces(code)
    end)
    cleaned = cleaned:gsub("%f[%a][Hh][Dd][Gg]%s*(%d%d%d)", function(code)
        return "heading " .. helpers.addspaces(code)
    end)
    cleaned = cleaned:gsub("%f[%a][Tt][Rr][Kk]%s*(%d%d%d)", function(code)
        return "track " .. helpers.addspaces(code)
    end)
    cleaned = cleaned:gsub("%f[%a][Ss][Pp][Dd]%s*(%d%d%d)", function(code)
        return "speed " .. helpers.addspaces(code)
    end)
    cleaned = cleaned:gsub("(%d%d+)%s*[Kk][Tt][Ss]?", function(code)
        return helpers.addspaces(code) .. " knots"
    end)
    cleaned = cleaned:gsub("(%d%d+)%s*[Ff][Tt]", function(code)
        return helpers.addspaces(code) .. " feet"
    end)
    local wordMap = {
        ATIS = "A T I S",
        CPDLC = "C P D L C",
        PDC = "P D C",
        ACARS = "A C A R S",
        METAR = "M E T A R",
        TAF = "T A F",
        ATC = "A T C",
        AOC = "A O C",
        RVR = "R V R",
        SID = "S I D",
        STAR = "S T A R",
        ILS = "I L S",
        RNAV = "R N A V",
        GLS = "G L S",
        LPV = "L P V",
        LOC = "L O C",
        VOR = "V O R",
        NDB = "N D B",
        DME = "D M E",
        APPR = "approach",
        APP = "approach",
        APCH = "approach",
        DEP = "departure",
        ARR = "arrival",
        CLB = "climb",
        DESC = "descend",
        DES = "descend",
        MAINT = "maintain",
        MAINTAIN = "maintain",
        WX = "weather",
        VIS = "visibility",
        TEMPO = "tempo",
        BECMG = "becoming",
        VRB = "variable",
        NOSIG = "no significant change"
    }
    cleaned = cleaned:gsub("%f[%a]([A-Za-z]+)%f[%A]", function(word)
        local repl = wordMap[string.upper(word)]
        if repl then
            return repl
        end
        return word
    end)
    return cleaned
end

local function tryDecodeHoppieMetar(packet)
    if type(packet) ~= "string" then
        return nil
    end
    local tokens = helpers.splitstring(packet)
    if not tokens or #tokens < 2 then
        return nil
    end
    local function is_icao(token)
        if type(token) ~= "string" or #token ~= 4 then
            return false
        end
        for i = 1, 4 do
            local b = string.byte(token, i)
            if not (b and ((b >= 65 and b <= 90) or (b >= 97 and b <= 122))) then
                return false
            end
        end
        return true
    end
    local function is_metar_time(token)
        if type(token) ~= "string" or #token ~= 7 then
            return false
        end
        if string.sub(token, 7, 7) ~= "Z" then
            return false
        end
        for i = 1, 6 do
            local b = string.byte(token, i)
            if not (b and b >= 48 and b <= 57) then
                return false
            end
        end
        return true
    end
    local idx = 1
    local first = tokens[1] or ""
    local first_up = string.upper(first)
    if first_up == "METAR" or first_up == "SPECI" then
        idx = 2
    end
    if #tokens < (idx + 1) then
        return nil
    end
    local station = tokens[idx]
    local dt = tokens[idx + 1]
    if not (is_icao(station) and is_metar_time(dt)) then
        return nil
    end
    local metar_parts = {}
    for i = idx, #tokens do
        metar_parts[#metar_parts + 1] = tokens[i]
    end
    local metar_text = table.concat(metar_parts, " ")
    if metar_text == "" then
        return nil
    end
    local decoded = helpers.decodemetar(metar_text)
    if not decoded or type(decoded) ~= "table" then
        return nil
    end
    local station_upper = string.upper(station)
    local metar = { icaocode = station_upper, decodedmetar = decoded }
    if decoded.station and decoded.station ~= "" then
        metar.icaocode = decoded.station
        station_upper = string.upper(decoded.station)
    end
    local runway_name = ""
    if P.depicao and isProperty(P.depicao) and P.deprwy and isProperty(P.deprwy) then
        local dep_icao = helpers.cleanstring(get(P.depicao))
        if dep_icao ~= "" and string.upper(dep_icao) == station_upper then
            runway_name = get(P.deprwy) or ""
        end
    end
    if runway_name == "" and P.desicao and isProperty(P.desicao) and P.desrwy and isProperty(P.desrwy) then
        local des_icao = helpers.cleanstring(get(P.desicao))
        if des_icao ~= "" and string.upper(des_icao) == station_upper then
            runway_name = get(P.desrwy) or ""
        end
    end
    local spoken = helpers.formatMetarSpeechSummary(metar, runway_name)
    if spoken and spoken ~= "" then
        if helpers and helpers.logInfoTS then
            helpers.logInfoTS("HoppieVoice: decoded METAR " .. station_upper)
        end
        return spoken
    end
    return nil
end

local function buildHoppieVoiceMessage(from, msg_type, packet)
    local parts = {}
    local from_norm = string.lower(tostring(from or ""))
    local is_acars = (from_norm == "acars")
    if not is_acars then
        local msg_type_norm = string.upper(tostring(msg_type or ""))
        local skip_prefix = (msg_type_norm == "CPDLC" or msg_type_norm == "ATC")
        if not skip_prefix and msg_type and msg_type ~= "" then
            parts[#parts + 1] = helpers.addspaces(msg_type) .. " message"
        end
        if from and from ~= "" then
            parts[#parts + 1] = "from " .. tostring(from)
        end
    end
    if packet and packet ~= "" then
        parts[#parts + 1] = normalizeHoppieVoiceText(packet)
    end
    local text = table.concat(parts, ". ")
    return normalizeHoppieVoiceText(text)
end

local function checkHoppieVoiceMessages()
    if not hoppieVoiceEnabled() then
        return
    end
    local voice_enabled = ((P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) or (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON))
    if not voice_enabled then
        return
    end
    if not P.hoppie then
        return
    end
    local function flushPendingAtisUnavailable()
        local pending = P.pendingAtisUnavailable
        if not pending then
            return
        end
        local now = os.time()
        if (now - (pending.time or now)) < 8 then
            return
        end
        P.pendingAtisUnavailable = nil
        local packet = pending.packet or ""
        if packet == "" then
            return
        end
        local text = tryDecodeHoppieMetar(packet)
        if not text or text == "" then
            text = buildHoppieVoiceMessage(pending.from or "", pending.msg_type or "", packet)
        end
        if text == "" then
            return
        end
        if pending.icao and pending.icao ~= "" then
            P.lastAtisUnavailableIcao = pending.icao
            P.lastAtisUnavailableTime = now
        end
        P.commandtableentry(def.TEXT, text)
    end
    local seq_ref = P.hoppie.voice_seq
    local use_seq = (seq_ref and isProperty(seq_ref))
    local count_ref = use_seq and seq_ref or P.hoppie.poll_count
    if not (count_ref and isProperty(count_ref)) then
        return
    end
    local count = get(count_ref) or 0
    if use_seq then
        if P.lastHoppieVoiceSeq == nil then
            P.lastHoppieVoiceSeq = count
            flushPendingAtisUnavailable()
            return
        end
        if count == P.lastHoppieVoiceSeq then
            flushPendingAtisUnavailable()
            return
        end
        P.lastHoppieVoiceSeq = count
    else
        if P.lastHoppiePollCount == nil then
            P.lastHoppiePollCount = count
            flushPendingAtisUnavailable()
            return
        end
        if count == P.lastHoppiePollCount then
            flushPendingAtisUnavailable()
            return
        end
        P.lastHoppiePollCount = count
    end
    local from = P.hoppie.poll_message_from and helpers.forceCleanString(get(P.hoppie.poll_message_from) or "") or ""
    local msg_type = P.hoppie.poll_message_type and helpers.forceCleanString(get(P.hoppie.poll_message_type) or "") or ""
    local packet = ""
    if use_seq and P.hoppie.voice_text and isProperty(P.hoppie.voice_text) then
        packet = helpers.forceCleanString(get(P.hoppie.voice_text) or "")
    end
    if packet == "" then
        packet = P.hoppie.poll_message_packet and helpers.forceCleanString(get(P.hoppie.poll_message_packet) or "") or ""
    end
    if helpers and helpers.logInfoTS then
        local log_packet = packet
        if type(log_packet) == "string" then
            log_packet = log_packet:gsub("[\r\n]+", " ")
            if #log_packet > 160 then
                log_packet = string.sub(log_packet, 1, 160) .. "..."
            end
        end
        local source = use_seq and "seq" or "poll"
        helpers.logInfoTS("HoppieVoice: " .. source .. "=" .. tostring(count)
            .. " from=" .. tostring(from)
            .. " type=" .. tostring(msg_type)
            .. " packet=" .. tostring(log_packet))
    end
    if packet ~= "" and (from == "" and msg_type == "") then
        local lower = string.lower(packet)
        if lower == "ok" then
            if helpers and helpers.logInfoTS then
                helpers.logInfoTS("HoppieVoice: suppress ok")
            end
            return
        end
    end
    if packet ~= "" then
        local function parseAlphaWords(text)
            local words = {}
            if type(text) ~= "string" then
                return words
            end
            local run = {}
            local run_len = 0
            local function flush_run()
                if run_len > 0 then
                    words[#words + 1] = string.upper(table.concat(run, "", 1, run_len))
                    run = {}
                    run_len = 0
                end
            end
            for i = 1, #text do
                local b = string.byte(text, i)
                local is_alpha = (b >= 65 and b <= 90) or (b >= 97 and b <= 122)
                if is_alpha then
                    run_len = run_len + 1
                    run[run_len] = string.char(b)
                else
                    flush_run()
                end
            end
            flush_run()
            return words
        end

        local words = parseAlphaWords(packet)
        local isAtisUnavailable = false
        for i = 1, #words do
            if words[i] == "ATIS" then
                if words[i + 1] == "IS" and words[i + 2] == "NOT" and words[i + 3] == "AVAILABLE" then
                    isAtisUnavailable = true
                    break
                end
                if words[i + 1] == "NOT" and words[i + 2] == "AVAILABLE" then
                    isAtisUnavailable = true
                    break
                end
            end
        end
        if isAtisUnavailable then
            local ignore = {
                IVAOATIS = true,
                VATATIS = true,
                ATIS = true,
                METAR = true,
                INFO = true,
                ACARS = true,
                CPDLC = true,
                MSG = true,
                MESSAGE = true,
                NOT = true,
                AVAILABLE = true,
                IS = true,
                THIS = true
            }
            local function findAtisIcao(list)
                for i = 1, #list do
                    if list[i] == "IVAOATIS" or list[i] == "VATATIS" then
                        local nextWord = list[i + 1]
                        if nextWord and #nextWord == 4 and not ignore[nextWord] then
                            return nextWord, i + 1
                        end
                    end
                end
                for i = 1, #list do
                    local w = list[i]
                    if #w == 4 and not ignore[w] then
                        return w, i
                    end
                end
                return "", nil
            end
            local icao, icaoIndex = findAtisIcao(words)
            local hasSecondary = false
            for i = 1, #words do
                local w = words[i]
                if w == "GND" or w == "GROUND" or w == "DEP" or w == "DEPARTURE" or w == "TWR" or w == "TOWER" then
                    hasSecondary = true
                    break
                end
            end
            if not hasSecondary and icaoIndex then
                local suffix = words[icaoIndex + 1]
                if suffix and #suffix == 1 and (suffix == "A" or suffix == "D" or suffix == "G") then
                    hasSecondary = true
                end
            end
            if icao ~= "" and hasSecondary then
                local now = os.time()
                local pending = P.pendingAtisUnavailable
                if pending and pending.icao == icao then
                    pending.time = now
                    return
                end
                P.pendingAtisUnavailable = {
                    icao = icao,
                    packet = packet,
                    from = from,
                    msg_type = msg_type,
                    time = now
                }
                if helpers and helpers.logInfoTS then
                    helpers.logInfoTS("HoppieVoice: defer secondary ATIS not available " .. icao)
                end
                return
            end
            if icao ~= "" then
                if P.pendingAtisUnavailable and P.pendingAtisUnavailable.icao == icao then
                    P.pendingAtisUnavailable = nil
                end
                local now = os.time()
                if P.lastAtisUnavailableIcao == icao and P.lastAtisUnavailableTime and (now - P.lastAtisUnavailableTime) < 30 then
                    if helpers and helpers.logInfoTS then
                        helpers.logInfoTS("HoppieVoice: suppress dup ATIS not available " .. icao)
                    end
                    return
                end
                P.lastAtisUnavailableIcao = icao
                P.lastAtisUnavailableTime = now
            end
        end
    end
    local text = nil
    if packet ~= "" then
        text = tryDecodeHoppieMetar(packet)
    end
    if not text or text == "" then
        text = buildHoppieVoiceMessage(from, msg_type, packet)
    end
    if text == "" then
        return
    end
    local now = os.time()
    if P.lastHoppieVoiceMsg == text and P.lastHoppieVoiceTime and (now - P.lastHoppieVoiceTime) < 30 then
        return
    end
    if packet ~= "" then
        local packet_key = string.lower(packet)
        if P.lastHoppiePacket == packet_key and P.lastHoppiePacketTime and (now - P.lastHoppiePacketTime) < 30 then
            if helpers and helpers.logInfoTS then
                helpers.logInfoTS("HoppieVoice: suppress dup packet")
            end
            return
        end
    end
    P.lastHoppieVoiceMsg = text
    P.lastHoppieVoiceTime = now
    if packet ~= "" then
        P.lastHoppiePacket = string.lower(packet)
        P.lastHoppiePacketTime = now
    end
    P.commandtableentry(def.TEXT, text)
end

local function signalReloadDataref(reason)
    if not P.reloadRequestDr or not isProperty(P.reloadRequestDr) then
        helpers.logInfoTS("AutoRestart: reload dataref not available")
        return false
    end
    set(P.reloadRequestDr, 1)
    helpers.logInfoTS("AutoRestart: signaled reload via dataref" .. (reason and (" (" .. reason .. ")") or ""))
    return true
end

local function backupSaslLog()
    if not helpers or not helpers.file_exists_v2 then
        return false
    end
    local src = def.PLUGINOUTPUTPATH .. "SASLLog.txt"
    if not helpers.file_exists_v2(src) then
        return false
    end
    local ts = os.date("%Y%m%d-%H%M%S")
    local dst = def.PLUGINOUTPUTPATH .. "SASLLog_" .. ts .. ".txt"
    local fin = io.open(src, "rb")
    if not fin then
        helpers.logInfoTS("AutoRestart: unable to open SASLLog for backup")
        return false
    end
    local content = fin:read("*a")
    fin:close()
    if not content then
        helpers.logInfoTS("AutoRestart: unable to read SASLLog for backup")
        return false
    end
    local fout = io.open(dst, "wb")
    if not fout then
        helpers.logInfoTS("AutoRestart: unable to write SASLLog backup")
        return false
    end
    fout:write(content)
    fout:close()
    helpers.logInfoTS("AutoRestart: backed up SASLLog to " .. dst)
    return true
end

local function checkAutoRestart()
    if not autoRestartEnabled() then
        return
    end
    local semPath = P.autoRestartSemaphorePath or (def.PLUGINOUTPUTPATH .. "yal_autorestart.sem")
    if not helpers.file_exists_v2(semPath) then
        P.autoRestartDeferred = false
        return
    end
    if anyProcedureRunning() then
        if not P.autoRestartDeferred then
            helpers.logInfoTS("AutoRestart: deferred (procedure running)")
            P.autoRestartDeferred = true
        end
        return
    end
    P.autoRestartDeferred = false
    backupSaslLog()
    os.remove(semPath)
    if not signalReloadDataref("semaphore") then
        helpers.logInfoTS("AutoRestart: reload request skipped (no dataref)")
    end
end

function P.devreload()
    if not devReloadEnabled() then
        helpers.logInfoTS("DevReload: unavailable (missing reload executor or debug overlay off)")
        return false
    end
    backupSaslLog()
    if not signalReloadDataref("command") then
        helpers.logInfoTS("DevReload: reload request skipped (no dataref)")
        return false
    end
    return true
end

function P.devreload_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.devreload()
    end
    return 0
end

function P.initDevReloadControls()
    if P.devReloadInitialized then
        return
    end
    if not devReloadEnabled() then
        return
    end
    if not P.devReloadCommand then
        P.devReloadCommand = sasl.createCommand(def.APPNAMEPREFIX .. "/forcereload", "Force Full Reload (Dev)")
        sasl.registerCommandHandler(P.devReloadCommand, 0, P.devreload_)
    end
    if not P.menu_dev_reload then
        P.menu_dev_reload = sasl.appendMenuItem(P.menu_main, "Force Full Reload (Dev)", P.devreload)
    end
    P.devReloadInitialized = true
end

function P.YalinitGlobal()

    P.needstempinit = true

    P.aircraftwasonground = false

    P.updatemetartimer = nil

    P.altitudetimer = nil

    P.pausetodtimer = nil
    P.pauseTodAutoDisabled = false
    P.pauseTodMonitorActive = false
    P.pauseTodMcpAltAtPrompt = nil
    P.autoRestartDeferred = false
    P.autoRestartSemaphorePath = def.PLUGINOUTPUTPATH .. "yal_autorestart.sem"
    if helpers and helpers.file_exists_v2 and helpers.file_exists_v2(P.autoRestartSemaphorePath) then
        os.remove(P.autoRestartSemaphorePath)
        helpers.logInfoTS("AutoRestart: removed stale semaphore on startup")
    end
    P.lastHoppiePollCount = nil
    P.lastHoppieVoiceMsg = nil
    P.lastHoppieVoiceTime = nil
    P.ziborelease = nil
    P.needsPostStartupDatarefRebind = false
    P.externalDatarefsPostStartupDone = false
    P.initialExternalDatarefMissingCount = 0
    P.gearProtectionWasAirborne = false
    P.gearProtectionArmedUntil = nil
    P.gearProtectionActiveUntil = nil
    P.gearProtectionLastOnGround = nil
    P.gearProtectionObservedFailures = nil
    P.cruiseAltMismatchKey = nil
    P.cruiseAltMismatchFirstSeenAt = nil
    P.cruiseAltMismatchLastWarnAt = nil
    P.cruiseAltMismatchVnavAltWarned = false

    P.savetimer = nil

    P.flightstate = 0

    P.approachCourseMag = nil
    P.approachNavType = nil

    P.xluaLoggingEnabled = nil

    P.centertankoffset = false

    P.depmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}
    P.desmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}
    P.nearmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}
    P.lastDepIcao = ""
    P.lastDesIcao = ""
    P.lastNearIcao = ""

    P.todDiscontinuityWarned30 = false
    P.todDiscontinuityWarned10 = false
    P.routeEndsEarlyWarned = false
    P.todResetMcpAdviceState = { key = nil, count = 0, spoken = 0 }
    P._takeoffN140CalloutLatched = false

    P.windshieldIcingStarted = false
    P.windshieldIcingApplied = false

    P.runwayFrictionAdjusted = nil
    P.runwayFrictionSeen = nil
    P.lastQnhHpaDep = nil
    P.lastQnhHpaArr = nil
    P.lastQnhSourceDep = nil
    P.lastQnhSourceArr = nil


    --------------------------------------------------------------------------------------------------------------

    P.configvalues = {}

    P.commandtable = {}

    -------------------------------------------------------------------------------------------------------------- 

    P.navdatatable = {}

    P.airportdatatable = {}

    P.zibocalctable = {}

    -------------------------------------------------------------------------------------------------------------- 

    P.proceduretable = {}

    --------------------------------------------------------------------------------------------------------------

    P.ongoingcoretaskindex = 4
    P.ongoingtaskstepindex = 7
    P.ongoingpretaskindex = 1

    P.procedurelooptemplate = {
        lock = def.NOPROCEDURE,
        stepindex = 0,
        currentStepName = "",
        steprepeat = false,
        lastActiveTime = 0,
        procedureabort = false,
        procedureskipped = false,
        procedureskipstep = false,
        procedurenotpossible = false,
        triggeredmanually = false,
        triggeredat = 0,
        setonabort = false,
        lastStepName = "",
        skipConfirmForStep = nil,
        adviceRepeatKey = nil,
        adviceRepeatCount = 0,
        adviceRepeatSpoken = 0,
        stepOnceRequested = false,
        stepOnceTargetStep = nil,
        debugPaused = false,
        debugStepOnce = false,
        debugBreakpoints = {}
    }

    P.procedureloop1 = helpers.shallowcopy(P.procedurelooptemplate)
    P.procedureloop2 = helpers.shallowcopy(P.procedurelooptemplate)
    P.procedureloop3 = helpers.shallowcopy(P.procedurelooptemplate)

    P.loopenginekeys = {}
    helpers.logInfoTS("Building engine key ignore-list from template...")
    for key, _ in pairs(P.procedurelooptemplate) do
        P.loopenginekeys[key] = true
        helpers.logInfoTS("... Added engine key: " .. key)
    end

    P.lastExecutedLoopIndex = 0

    P.loopStateTables = {P.procedureloop1, P.procedureloop2, P.procedureloop3}

    P.previousview = -1

    P.XCameraIsInstalled()
    P.YANSHisinstalled()
    P.BPBisinstalled()
    P.IVAOMonitorIsInstalled()
    P.HoppieHelperIsInstalled()

end

--------------------------------------------------------------------------------------------------------------
-- Datarefs

local function probe_external_dataref(name, kind)
    if kind == "fae" then
        return sasl.findDataRef(name, TYPE_FLOAT_ARRAY, true) ~= nil
            or sasl.findDataRef(name, TYPE_INT_ARRAY, true) ~= nil
    elseif kind == "iae" or kind == "ia" then
        return sasl.findDataRef(name, TYPE_INT_ARRAY, true) ~= nil
            or sasl.findDataRef(name, TYPE_FLOAT_ARRAY, true) ~= nil
    end

    local ref = sasl.findDataRef(name, TYPE_UNKNOWN, true)
    if ref then
        return true
    end
    local sname, _ = string.match(name, '(.+)%[(%d+)%]$')
    if sname then
        return sasl.findDataRef(sname, TYPE_UNKNOWN, true) ~= nil
    end
    return false
end

local function bind_external_dataref(name, kind, index, silentMissing)
    if silentMissing and not probe_external_dataref(name, kind) then
        return nil, true
    end
    if kind == "fae" then
        return globalPropertyfae(name, index), false
    elseif kind == "iae" then
        return globalPropertyiae(name, index), false
    elseif kind == "ia" then
        return globalPropertyia(name), false
    end
    return globalProperty(name), false
end

function P.bindExternalDatarefs(silentMissing)
    local missingCount = 0

    local function GP(name)
        local dr, missing = bind_external_dataref(name, nil, nil, silentMissing)
        if missing then missingCount = missingCount + 1 end
        return dr
    end

    local function GPIA(name)
        local dr, missing = bind_external_dataref(name, "ia", nil, silentMissing)
        if missing then missingCount = missingCount + 1 end
        return dr
    end

    local function GPIAE(name, index)
        local dr, missing = bind_external_dataref(name, "iae", index, silentMissing)
        if missing then missingCount = missingCount + 1 end
        return dr
    end

    local function GPFAE(name, index)
        local dr, missing = bind_external_dataref(name, "fae", index, silentMissing)
        if missing then missingCount = missingCount + 1 end
        return dr
    end
    P.simpaused = GP("sim/time/paused")
    P.simfreezed = GPFAE("sim/operation/override/override_planepath", 1)
    P.battery = GP("laminar/B738/electric/battery_pos")
    P.batteryswitchcover = GPFAE("laminar/B738/cover", 3)
    P.emergencylights = GP("laminar/B738/toggle_switch/emer_exit_lights")
    P.emergencylightcover = GPFAE("laminar/B738/cover", 10)
    P.windowiceaddeddelta = GP("sim/flightmodel/failures/window_ice_added_delta")
    P.windowiceunheated = GP("sim/flightmodel/failures/window_ice_unheated")

    P.apgoaround = GP("laminar/B738/autopilot/ap_goaround")

    P.localpositionx = GP("sim/flightmodel/position/local_x")
    P.localpositiony = GP("sim/flightmodel/position/local_y")
    P.localpositionz = GP("sim/flightmodel/position/local_z")
    P.localpositionpsi = GP("sim/flightmodel/position/psi")
    P.acf_cg_z = GP("sim/aircraft/weight/acf_cgZ_original")
    P.gear_znose = GPFAE("sim/aircraft/parts/acf_gear_znodef", 1)
    P.gear_zmain = GPFAE("sim/aircraft/parts/acf_gear_znodef", 2)

    P.fueltank1 = GP("sim/flightmodel/weight/m_fuel1")
    P.fueltank2 = GP("sim/flightmodel/weight/m_fuel2")
    P.fueltank3 = GP("sim/flightmodel/weight/m_fuel3")

    P.mastercautionannunc = GP("sim/cockpit/warnings/annunciators/master_caution")

    P.mainbus = GP("laminar/B738/electric/main_bus")
    P.parkingbrakepos = GP("laminar/B738/parking_brake_pos")
    P.simparkingbrakeratio = GP("sim/cockpit2/controls/parking_brake_ratio")
    P.ziborelease = GP("laminar/B738/release")
    P.lvluprelease = GP("laminar/B738/lvlup/rel")
    P.lvlupfm = GP("laminar/B738/lvlup/fm")
    P.override_throttles = GP("sim/operation/override/override_throttles")
    P.override_wheel_steer = GP("sim/operation/override/override_wheel_steer")
    P.override_toe_brakes = GP("sim/operation/override/override_toe_brakes")
    P.zibo_throttle_override = GP("laminar/B738/throttle_override")
    P.zibo_nosewheel_steer_override = GP("laminar/B738/nosewheel_steer_override")
    P.zibo_toe_brake_override = GP("laminar/B738/toe_brake_override")
    P.yoke_heading_ratio = GP("sim/joystick/yoke_heading_ratio")
    P.yoke_heading_ratio_cockpit = GP("sim/cockpit2/controls/yoke_heading_ratio")
    P.left_brake_ratio = GP("sim/cockpit2/controls/left_brake_ratio")
    P.right_brake_ratio = GP("sim/cockpit2/controls/right_brake_ratio")
    P.throttle_use_1 = GPFAE("sim/flightmodel/engine/ENGN_thro_use", 1)
    P.throttle_use_2 = GPFAE("sim/flightmodel/engine/ENGN_thro_use", 2)
    P.hardware_throttle_1 = GPFAE("sim/cockpit2/engine/actuators/hardware_throttle_ratio", 1)
    P.hardware_throttle_2 = GPFAE("sim/cockpit2/engine/actuators/hardware_throttle_ratio", 2)
    P.tire_steer_cmd = GPFAE("sim/flightmodel2/gear/tire_steer_command_deg", 1)
    P.zibo_axis_throttle1 = GP("laminar/B738/axis/throttle1")
    P.zibo_axis_throttle2 = GP("laminar/B738/axis/throttle2")
    P.zibo_axis_nosewheel = GP("laminar/B738/axis/nosewheel")
    P.zibo_axis_nosewheel2 = GP("laminar/B738/axis/nosewheel2")
    P.zibo_axis_nosewheel3 = GP("laminar/B738/axis/nosewheel3")
    P.zibo_axis_heading = GP("laminar/B738/axis/heading")
    P.zibo_axis_left_toe_brake = GP("laminar/B738/axis/left_toe_brake")
    P.zibo_axis_right_toe_brake = GP("laminar/B738/axis/right_toe_brake")

    P.pausetod = GP("laminar/B738/fms/pause_td")

    P.vnavtoddist = GP("laminar/B738/fms/vnav_td_dist")
    P.distdest = GP("laminar/B738/FMS/dist_dest")
    P.vnavtocdist = GP("laminar/B738/fms/vnav_tc_dist")

    P.hidecptefb = GP("laminar/B738/tab/static")
    P.hidefoefb = GP("laminar/B738/tab/fo_static")

    P.chockstatus = GP("laminar/B738/fms/chock_status")
    P.enginenorunningstate = GP("laminar/B738/fms/engine_no_running_state")

    P.wakeoverride = GP("sim/operation/override/override_wake_turbulence")
    P.runwayfriction = GP("sim/weather/region/runway_friction")

    P.aponstat = GP("laminar/autopilot/ap_on")
    P.apdiscpos = GP("laminar/B738/autopilot/disconnect_pos")

    P.apcmdastat = GP("laminar/B738/autopilot/cmd_a_status")
    P.apcmdbstat = GP("laminar/B738/autopilot/cmd_b_status")

    P.apvnavstat = GP("laminar/B738/autopilot/vnav_status1")
    P.aplnavstat = GP("laminar/B738/autopilot/lnav_status")
    P.apappstat = GP("laminar/B738/autopilot/app_status")
    P.apvorlocstat = GP("laminar/B738/autopilot/vorloc_status")
    P.apalthldstat = GP("laminar/B738/autopilot/alt_hld_status")
    P.aphdgselstat = GP("laminar/B738/autopilot/hdg_sel_status")
    P.apvsstat = GP("laminar/B738/autopilot/vs_status")
    P.aplvlchgstat = GP("laminar/B738/autopilot/lvl_chg_status")
    P.apvnavaltmode = GP("laminar/B738/autopilot/vnav_alt_mode")

    P.mmrinstalled = GP("laminar/B738/fms/mmr")
    P.lpvinstalled = GP("laminar/B738/lpv_install")
    P.mmrcptactmode = GP("laminar/B738/mmr/cpt/act_mode")
    P.mmrcptactvalue = GP("laminar/B738/mmr/cpt/act_value")
    P.mmrcptstdbymode = GP("laminar/B738/mmr/cpt/stby_mode")
    P.mmrcptglsstbyvalue = GPIA("laminar/B738/mmr/cpt/gls_stby_value")
    P.mmrcptilsstbyvalue = GPIA("laminar/B738/mmr/cpt/ils_stby_value")
    P.mmrcptilsstbyvalue2 = GPIA("laminar/B738/mmr/cpt/ils_stby_value2")
    P.mmrcptvorstbyvalue = GPIA("laminar/B738/mmr/cpt/vor_stby_value")
    P.mmrcptvorstbyvalue2 = GPIA("laminar/B738/mmr/cpt/vor_stby_value2")
    P.mmrcptstbyvalue = GPIA("laminar/B738/mmr/cpt/stby_value")
    P.mmrfoactmode = GP("laminar/B738/mmr/fo/act_mode")
    P.mmrfoactvalue = GP("laminar/B738/mmr/fo/act_value")
    P.mmrfostdbymode = GP("laminar/B738/mmr/fo/stby_mode")
    P.mmrfoglsstbyvalue = GPIA("laminar/B738/mmr/fo/gls_stby_value")
    P.mmrfoilsstbyvalue = GPIA("laminar/B738/mmr/fo/ils_stby_value")
    P.mmrfoilsstbyvalue2 = GPIA("laminar/B738/mmr/fo/ils_stby_value2")
    P.mmrfovorstbyvalue = GPIA("laminar/B738/mmr/fo/vor_stby_value")
    P.mmrfovorstbyvalue2 = GPIA("laminar/B738/mmr/fo/vor_stby_value2")
    P.mmrfostbyvalue = GPIA("laminar/B738/mmr/fo/stby_value")

    P.apgscapturedstat = GPFAE("laminar/B738/ap/glideslope_status", 1)
    P.aploccapturedstat = GPFAE("laminar/B738/ap/approach_status", 1)
    P.aprolloutstat = GPFAE("laminar/B738/ap/rollout_status", 1)
    P.apflarestat = GPFAE("laminar/B738/ap/flare_status", 1)

    P.aplpvgscapturedstat = GPFAE("laminar/B738/ap/lpv_gs_status", 1)
    P.aplpvnavcapturedstat = GPFAE("laminar/B738/ap/lpv_nav_status", 1)
    P.aplpvloccapturedstat = GPFAE("laminar/B738/ap/lpv_app_status", 1)

    P.apglsgscapturedstat = GPFAE("laminar/B738/ap/gls_gs_status", 1)
    P.apglsnavcapturedstat = GPFAE("laminar/B738/ap/gls_nav_status", 1)
    P.apglsloccapturedstat = GPFAE("laminar/B738/ap/gls_app_status", 1)

    P.apfacgscapturedstat = GPFAE("laminar/B738/ap/gp_status", 1)
    P.apfacloccapturedstat = GPFAE("laminar/B738/ap/fac_status", 1)
    P.ianinfo = GP("laminar/B738/fms/ian_info")
    P.ianinfofo = GP("laminar/B738/fms/ian_info_fo")
    P.autopilotpfdmode = GP("laminar/B738/autopilot/pfd_mode")
    P.autopilotpfdmodefo = GP("laminar/B738/autopilot/pfd_mode_fo")
    P.scalepfdmode = GP("laminar/B738/autopilot/scale_pfd_mode")
    P.scalepfdmodefo = GP("laminar/B738/autopilot/scale_pfd_mode_fo")
    P.fmsilsdisable = GP("laminar/B738/FMS/ils_disable")
    P.faccrs = GP("laminar/B738/fms/fac_crs")
    P.gppthalt = GP("laminar/B738/fms/gp_pth_alt")
    P.vnavgpactive = GP("laminar/B738/fms/vnav_gp_active")

    P.aphdgmode = GP("laminar/B738/autopilot/heading_mode")
    P.apaltmode = GP("laminar/B738/autopilot/altitude_mode")

    P.atarmpos = GP("laminar/B738/autopilot/autothrottle_arm_pos")
    P.atn1stat = GP("laminar/B738/autopilot/n1_status")
    P.atspeedstat = GP("laminar/B738/autopilot/speed_status1")
    P.atspeedintvstat = GP("laminar/B738/autopilot/spd_interv_status")
    P.atthrottlehold = GP("laminar/autopilot/at_throttle_hold")
    P.atn1mode = GP("laminar/B738/FMS/N1_mode")
    P.atn1modetoselection = GP("laminar/B738/FMS/N1_mode_to_sel")
    P.atthrottlelock = GP("laminar/B738/autopilot/lock_throttle")

    P.atspeedmode = GP("laminar/B738/autopilot/speed_mode")

    P.gearhandlepos = GP("laminar/B738/controls/gear_handle_down")
    P.lgeardeployed = GPFAE("sim/aircraft/parts/acf_gear_deploy", 1)
    P.ngeardeployed = GPFAE("sim/aircraft/parts/acf_gear_deploy", 2)
    P.rgeardeployed = GPFAE("sim/aircraft/parts/acf_gear_deploy", 3)
    P.rel_collapse1 = GP("sim/operation/failures/rel_collapse1")
    P.rel_collapse2 = GP("sim/operation/failures/rel_collapse2")
    P.rel_collapse3 = GP("sim/operation/failures/rel_collapse3")
    P.rel_tire1 = GP("sim/operation/failures/rel_tire1")
    P.rel_tire2 = GP("sim/operation/failures/rel_tire2")
    P.rel_tire3 = GP("sim/operation/failures/rel_tire3")
    P.rel_gear_act = GP("sim/operation/failures/rel_gear_act")

    P.altitude = GP("laminar/B738/autopilot/altitude")
    P.altitude_ft = GP("sim/cockpit2/gauges/indicators/altitude_ft_pilot")
    P.fmccruisealt = GP("laminar/B738/autopilot/fmc_cruise_alt")
    P.radioaltitude = GP("sim/cockpit2/gauges/indicators/radio_altimeter_height_ft_pilot")

    P.groundtrackmag = GP("sim/cockpit2/gauges/indicators/ground_track_mag_pilot")

    P.trimwheel = GP("laminar/B738/flt_ctrls/trim_wheel")
    P.trimcalc = GP("laminar/B738/FMS/trim_calc")

    P.gpuavailable = GP("laminar/B738/gpu_available")
    P.jetwaypoweravailable = GP("laminar/B738/jetway_power")
    P.autogategpu = GP("laminar/B738/autogate_gpu")
    P.gpuon = GP("sim/cockpit/electrical/gpu_on")
    P.engineairstart = GP("laminar/B738/engine/engine_air_start")

    P.apustarterpos = GP("laminar/B738/spring_toggle_switch/APU_start_pos")
    P.apupsi = GP("laminar/B738/air/apu_psi")
    P.apugenoffbus = GP("laminar/B738/annunciator/apu_gen_off_bus")
    P.apupowerbus1 = GP("laminar/B738/electrical/apu_power_bus1")
    P.apupowerbus2 = GP("laminar/B738/electrical/apu_power_bus2")

    P.announcsourceoff1 = GP("laminar/B738/annunciator/source_off1")
    P.announcsourceoff2 = GP("laminar/B738/annunciator/source_off2")

    P.gen1pos = GPIAE("sim/cockpit/electrical/generator_on", 1)
    P.gen2pos = GPIAE("sim/cockpit/electrical/generator_on", 2)

    P.bleedair1pos = GP("laminar/B738/toggle_switch/bleed_air_1_pos")
    P.bleedair2pos = GP("laminar/B738/toggle_switch/bleed_air_2_pos")
    P.bleedairapupos = GP("laminar/B738/toggle_switch/bleed_air_apu_pos")
    P.isolvalvepos = GP("laminar/B738/air/isolation_valve_pos")
    P.packlpos = GP("laminar/B738/air/l_pack_pos")
    P.packrpos = GP("laminar/B738/air/r_pack_pos")
    P.trimairpos = GP("laminar/B738/air/trim_air_pos")
    P.lrecircfanpos = GP("laminar/B738/air/l_recirc_fan_pos")
    P.rrecircfanpos = GP("laminar/B738/air/r_recirc_fan_pos")

    P.starterauto = GP("laminar/B738/engine_start_auto")
    P.starter1pos = GP("laminar/B738/engine/starter1_pos")
    P.starter2pos = GP("laminar/B738/engine/starter2_pos")

    P.mixture1pos = GP("laminar/B738/engine/mixture_ratio1")
    P.mixture2pos = GP("laminar/B738/engine/mixture_ratio2")

    P.reverser1pos = GP("laminar/B738/flt_ctrls/reverse_lever1")
    P.reverser2pos = GP("laminar/B738/flt_ctrls/reverse_lever2")

    P.totalfuellbs = GP("laminar/B738/fuel/total_tank_lbs")
    P.totalfuelkgs = GP("laminar/B738/fuel/total_tank_kgs")
    P.fuelunit = GP("laminar/B738/FMS/fmc_units")

    P.totalweightkgs = GP("sim/flightmodel/weight/m_total")

    P.centertanklbs = GP("laminar/B738/fuel/center_tank_lbs")
    P.centertanklpress = GP("laminar/B738/system/fuel_press_c1")
    P.centertankrpress = GP("laminar/B738/system/fuel_press_c2")
    P.centertanklswitch = GP("laminar/B738/fuel/fuel_tank_pos_ctr1")
    P.centertankrswitch = GP("laminar/B738/fuel/fuel_tank_pos_ctr2")
    P.centertankstat = GP("laminar/B738/fuel/center_status")
    P.lefttanklbs = GP("laminar/B738/fuel/left_tank_lbs")
    P.lefttanklswitch = GP("laminar/B738/fuel/fuel_tank_pos_lft1")
    P.lefttankrswitch = GP("laminar/B738/fuel/fuel_tank_pos_lft2")
    P.righttanklbs = GP("laminar/B738/fuel/right_tank_lbs")
    P.righttanklswitch = GP("laminar/B738/fuel/fuel_tank_pos_rgt2")
    P.righttankrswitch = GP("laminar/B738/fuel/fuel_tank_pos_rgt1")

    P.eng1n1ratio = GP("laminar/B738/FMS/eng1_N1_ratio")
    P.eng2n1ratio = GP("laminar/B738/FMS/eng2_N1_ratio")
    P.eng1n1percent = GPFAE("sim/flightmodel2/engines/N1_percent", 1)
    P.eng2n1percent = GPFAE("sim/flightmodel2/engines/N1_percent", 2)
    P.eng1n2percent = GPFAE("sim/flightmodel2/engines/N2_percent", 1)
    P.eng2n2percent = GPFAE("sim/flightmodel2/engines/N2_percent", 2)
    P.fadec1on = GPFAE("sim/cockpit2/engine/actuators/fadec_on", 1)
    P.fadec2on = GPFAE("sim/cockpit2/engine/actuators/fadec_on", 2)
    P.fuel_flow_kg_sec_1 = GPFAE("laminar/B738/engine/fuel_flow_kg_sec", 1)
    P.fuel_flow_kg_sec_2 = GPFAE("laminar/B738/engine/fuel_flow_kg_sec", 2)

    P.eng1heatpos = GP("laminar/B738/ice/eng1_heat_pos")
    P.eng2heatpos = GP("laminar/B738/ice/eng2_heat_pos")
    P.wingheatpos = GP("laminar/B738/ice/wing_heat_pos")

    P.hydro1pos = GP("laminar/B738/toggle_switch/hydro_pumps1_pos")
    P.hydro2pos = GP("laminar/B738/toggle_switch/hydro_pumps2_pos")
    P.elechydro1pos = GP("laminar/B738/toggle_switch/electric_hydro_pumps1_pos")
    P.elechydro2pos = GP("laminar/B738/toggle_switch/electric_hydro_pumps2_pos")

    P.airgroundsensor = GP("laminar/B738/air_ground_sensor")
    P.autobrakepos = GP("laminar/B738/autobrake/autobrake_pos")
    P.autobrakedisarm = GP("laminar/B738/autobrake/autobrake_disarm")

    P.fmsflightphase = GP("laminar/B738/FMS/flight_phase")
    P.tobiiEyetracker = GP("sim/graphics/view/eq_tobii_eyetracker")

    P.fmctransalt = GP("laminar/B738/FMS/fmc_trans_alt")
    P.fmctranslvl = GP("laminar/B738/FMS/fmc_trans_lvl")

    P.bankanglepos = GP("laminar/B738/autopilot/bank_angle_pos")

    P.baropilot = GP("laminar/B738/EFIS/baro_sel_in_hg_pilot")
    P.barostd = GP("laminar/B738/EFIS/baro_set_std_pilot")
    P.baroinhpa = GP("laminar/B738/EFIS_control/capt/baro_in_hpa")
    P.baroregionpas = GP("sim/weather/region/qnh_pas")

    P.frameice = GP("sim/flightmodel/failures/frm_ice")
    P.tatdegc = GP("laminar/B738/systems/temperature/tat_degc")

    P.cabincruisealt = GP("sim/cockpit/pressure/max_allowable_altitude")
    P.cabinlandingalt = GP("laminar/B738/pressurization/knobs/landing_alt")
    P.missedappalt = GP("laminar/B738/fms/missed_app_alt")

    P.llights1 = GPFAE("sim/cockpit2/switches/landing_lights_switch", 1)
    P.llights2 = GPFAE("sim/cockpit2/switches/landing_lights_switch", 2)
    P.llights3 = GPFAE("sim/cockpit2/switches/landing_lights_switch", 3)
    P.llights4 = GPFAE("sim/cockpit2/switches/landing_lights_switch", 4)
    P.ledlightsvariant = GP("laminar/B738/led_lights")

    P.taxilight = GP("laminar/B738/toggle_switch/taxi_light_brightness_pos")
    P.positionlights = GP("laminar/B738/toggle_switch/position_light_pos")
    P.beaconlights = GP("sim/cockpit/electrical/beacon_lights_on")
    P.rwylightl = GP("laminar/B738/toggle_switch/rwy_light_left")
    P.rwylightr = GP("laminar/B738/toggle_switch/rwy_light_right")
    P.logolighton = GP("laminar/B738/toggle_switch/logo_light")

    P.transponderpos = GP("laminar/B738/knob/transponder_pos")
    P.transpondercode = GP("sim/cockpit/radios/transponder_code")

    P.fdpilotpos = GP("laminar/B738/autopilot/flight_director_pos")
    P.fdfopos = GP("laminar/B738/autopilot/flight_director_fo_pos")

    P.efiswxpilotpos = GP("laminar/B738/EFIS/EFIS_wx_on")
    P.efiswxfopos = GP("laminar/B738/EFIS/fo/EFIS_wx_on")
    P.efisterrpilotpos = GP("laminar/B738/EFIS_control/capt/terr_on")
    P.efisterrfopos = GP("laminar/B738/EFIS_control/fo/terr_on")
    P.efisfixpilotpos = GP("laminar/B738/EFIS/EFIS_fix_on")
    P.efisfixfopos = GP("laminar/B738/EFIS/fo/EFIS_fix_on")
    P.efisdatapilotpos = GP("laminar/B738/EFIS/capt/data_status")
    P.efisdatafopos = GP("laminar/B738/EFIS/fo/data_status")
    P.efisairportpilotpos = GP("laminar/B738/EFIS/EFIS_airport_on")
    P.efisairportfopos = GP("laminar/B738/EFIS/fo/EFIS_airport_on")
    P.efispospilotpos = GP("laminar/B738/pfd/gps1_pos_show")
    P.efisposfopos = GP("laminar/B738/pfd/gps1_pos_fo_show")
    P.efisvorpilotpos = GP("laminar/B738/EFIS/EFIS_vor_on")
    P.efisvorfopos = GP("laminar/B738/EFIS/fo/EFIS_vor_on")

    P.n1setsource = GP("laminar/B738/toggle_switch/n1_set_source")

    P.dhpilot = GP("laminar/B738/pfd/dh_pilot")

    P.elevation = GP("sim/flightmodel/position/elevation")

    P.depicao = GP("laminar/B738/fms/ref_icao")
    P.deprwyheading = GP("laminar/B738/fms/ref_runway_crs_mod")
    P.deprwylen = GP("laminar/B738/fms/ref_runway_len")
    P.deprwylatstartpos = GP("laminar/B738/fms/ref_runway_start_lat_mod")
    P.deprwylonstartpos = GP("laminar/B738/fms/ref_runway_start_lon_mod")
    P.deprwylatendpos = GP("laminar/B738/fms/ref_runway_end_lat_mod")
    P.deprwylonendpos = GP("laminar/B738/fms/ref_runway_end_lon_mod")
    P.deprwy = GP("laminar/B738/fms/ref_runway")

    P.desicao = GP("laminar/B738/fms/dest_icao")
    P.desrwyheading = GP("laminar/B738/fms/dest_runway_crs")
    P.desrwylatstartpos = GP("laminar/B738/fms/dest_runway_start_lat_mod")
    P.desrwylonstartpos = GP("laminar/B738/fms/dest_runway_start_lon_mod")
    P.desrwylatendpos = GP("laminar/B738/fms/dest_runway_end_lat_mod")
    P.desrwylonendpos = GP("laminar/B738/fms/dest_runway_end_lon_mod")
    P.desrwyalt = GP("laminar/B738/pfd/des_rwy_altitude")
    P.desrwylen = GP("laminar/B738/fms/dest_runway_len")
    P.desrwy = GP("laminar/B738/fms/dest_runway")
 
    P.nearesticao = GP("laminar/B738/near_apt_icao")

    P.fmslegs = GP("laminar/B738/fms/legs")
    P.fmslegslat = GP("laminar/B738/fms/legs_lat")
    P.fmslegslon = GP("laminar/B738/fms/legs_lon")

    P.aircraftlatpos = GP("sim/flightmodel/position/latitude")
    P.aircraftlonpos = GP("sim/flightmodel/position/longitude")

    P.sunpitchdegrees = GP("sim/graphics/scenery/sun_pitch_degrees")

    P.flapleverpos = GP("laminar/B738/flt_ctrls/flap_lever")
    P.speedbrakelever = GP("laminar/B738/flt_ctrls/speedbrake_lever")
    P.speedbrakeleveranim = GP("laminar/B738/flt_ctrls/speedbrake_lever_anim")
    P.speedbrakeratio = GP("sim/cockpit2/controls/speedbrake_ratio")

    P.flapsupspeed = GP("laminar/B738/pfd/flaps_up")
    P.flaps1speed = GP("laminar/B738/pfd/flaps_1")
    P.flaps2speed = GP("laminar/B738/pfd/flaps_2")
    P.flaps5speed = GP("laminar/B738/pfd/flaps_5")
    P.flaps10speed = GP("laminar/B738/pfd/flaps_10")
    P.flaps15speed = GP("laminar/B738/pfd/flaps_15")
    P.flaps25speed = GP("laminar/B738/pfd/flaps_25")

    P.toflaps = GP("laminar/B738/FMS/takeoff_flaps")
    P.toflapsset = GP("laminar/B738/FMS/takeoff_flaps_set")
    P.appflaps = GP("laminar/B738/FMS/approach_flaps")
    P.appflapsset = GP("laminar/B738/FMS/approach_flaps_set")

    P.airspeed = GP("laminar/B738/autopilot/airspeed")
    P.ias_kts = GP("sim/cockpit2/gauges/indicators/airspeed_kts_pilot")
    P.tas_kts = GP("sim/flightmodel/position/true_airspeed")
    P.tas_kts_is_ms = true
    P.groundspeed = GP("laminar/b738/fmodpack/real_groundspeed")
    P.tirespeed = GP("laminar/B738/systems/tire_speed0")
    P.verticalspeed = GPFAE("sim/cockpit2/tcas/targets/position/vertical_speed", 1)

    P.v1speed = GP("laminar/B738/FMS/v1")
    P.v2speed = GP("laminar/B738/FMS/v2")
    P.vrspeed = GP("laminar/B738/FMS/vr")

    P.v1calcspeed = GP("laminar/B738/FMS/v1_calc")
    P.v2calcspeed = GP("laminar/B738/FMS/v2_calc")
    P.vrcalcspeed = GP("laminar/B738/FMS/vr_calc")

    P.v1setspeed = GP("laminar/B738/FMS/v1_set")
    P.v2setspeed = GP("laminar/B738/FMS/v2_set")
    P.vrsetspeed = GP("laminar/B738/FMS/vr_set")

    P.fmccg = GP("laminar/B738/FMS/fmc_cg")
    P.tabcg = GP("laminar/B738/tab/cg_pos")
    P.calctakeoffcg = GP("laminar/B738/fms/calc_to_cg")

    P.speedrestr = GP("laminar/B738/autopilot/fmc_descent_r_speed1")

    P.vref = GP("laminar/B738/FMS/vref")
    P.vref15 = GP("laminar/B738/FMS/vref_15")
    P.vref25 = GP("laminar/B738/FMS/vref_25")
    P.vref30 = GP("laminar/B738/FMS/vref_30")
    P.vref40 = GP("laminar/B738/FMS/vref_40")
    P.vrefapproachwindcorr = GP("laminar/B738/FMS/approach_wind_corr")
    P.fmclandinggw = GP("laminar/B738/FMS/fmc_gw_app")
    P.fmctakeoffgw = GP("laminar/B738/FMS/fmc_gw")
    P.fmcseltemp = GP("laminar/B738/FMS/fmc_sel_temp")
    P.fmcoattemp = GP("laminar/B738/FMS/fmc_oat_temp")
    P.b737variant = GP("zibomod/b737_variant")
    P.runwaywinddir = GP("laminar/B738/fms/rw_wind_dir")
    P.runwaywindspd = GP("laminar/B738/fms/rw_wind_spd")
    P.runwayslope = GP("laminar/B738/fms/rw_slope")
    P.runwayheadingfmc = GP("laminar/B738/fms/rw_hdg")
    P.fueltemp = GP("laminar/B738/engine/fuel_temp_real")
    P.glscourse = GP("laminar/B738/nav/gls1_crs")

    P.rain = GP("sim/weather/view/rain_ratio")

    P.lwiperpos = GP("laminar/B738/switches/left_wiper_pos")
    P.rwiperpos = GP("laminar/B738/switches/right_wiper_pos")

    P.mfdsyspos = GP("laminar/B738/buttons/mfd_sys_pos")
    P.lowerdupage = GP("laminar/B738/systems/lowerDU_page")
    P.lowerdupage2 = GP("laminar/B738/systems/lowerDU_page2")

    P.nav1freq = GP("sim/cockpit/radios/nav1_freq_hz")
    P.nav1stdbyfreq = GP("sim/cockpit/radios/nav1_stdby_freq_hz")
    P.nav2freq = GP("sim/cockpit/radios/nav2_freq_hz")
    P.nav2stdbyfreq = GP("sim/cockpit/radios/nav2_stdby_freq_hz")
    P.mcppilotcourse = GP("laminar/B738/autopilot/course_pilot")
    P.mcpcopilotcourse = GP("laminar/B738/autopilot/course_copilot")
    P.mcpheading = GP("laminar/B738/autopilot/mcp_hdg_dial")
    P.mcpspeed = GP("laminar/B738/autopilot/mcp_speed_dial_kts_mach")
    P.mcpaltitude = GP("laminar/B738/autopilot/mcp_alt_dial")
    P.mcpvsspeed = GP("sim/cockpit/autopilot/vertical_velocity")

    P.domelightpos = GP("laminar/B738/toggle_switch/cockpit_dome_pos")

    P.seatbeltsignpos = GP("laminar/B738/toggle_switch/seatbelt_sign_pos")
    P.nosmokingsignpos = GP("laminar/B738/toggle_switch/no_smoking_pos")

    P.brightmainpanel = GPFAE("laminar/B738/electric/panel_brightness", 1)
    P.brightcopilotmainpanel = GPFAE("laminar/B738/electric/panel_brightness", 2)
    P.brightoverhead = GPFAE("laminar/B738/electric/panel_brightness", 3)
    P.brightpedestral = GPFAE("laminar/B738/electric/panel_brightness", 4)

    P.genbrightbackground = GPFAE("laminar/B738/electric/generic_brightness", 7)
    P.genbrightafdsflood = GPFAE("laminar/B738/electric/generic_brightness", 8)
    P.genbrightpedestralflood = GPFAE("laminar/B738/electric/generic_brightness", 9)

    P.instrbrightoutbddu = GPFAE("laminar/B738/electric/instrument_brightness", 1)
    P.instrbrightcopilotoutbddu = GPFAE("laminar/B738/electric/instrument_brightness", 2)
    P.instrbrightinbddu = GPFAE("laminar/B738/electric/instrument_brightness", 3)
    P.instrbrightcopilotinbddu = GPFAE("laminar/B738/electric/instrument_brightness", 4)
    P.instrbrightupperdu = GPFAE("laminar/B738/electric/instrument_brightness", 5)
    P.instrbrightlowdu = GPFAE("laminar/B738/electric/instrument_brightness", 6)
    P.instrbrightinbdduS = GPFAE("laminar/B738/electric/instrument_brightness", 25)
    P.instrbrightlowduS = GPFAE("laminar/B738/electric/instrument_brightness", 26)
    P.instrbrightcopilotinbdduS = GPFAE("laminar/B738/electric/instrument_brightness", 27)

    P.captainprobepos = GP("laminar/B738/toggle_switch/capt_probes_pos")
    P.foprobepos = GP("laminar/B738/toggle_switch/fo_probes_pos")
    P.wheatlfwdpos = GP("laminar/B738/ice/window_heat_l_fwd_pos")
    P.wheatrfwdpos = GP("laminar/B738/ice/window_heat_r_fwd_pos")
    P.wheatlsidepos = GP("laminar/B738/ice/window_heat_l_side_pos")
    P.wheatrsidepos = GP("laminar/B738/ice/window_heat_r_side_pos")

    P.irsleftpos = GP("laminar/B738/toggle_switch/irs_left")
    P.irsrightpos = GP("laminar/B738/toggle_switch/irs_right")
    P.irsalignleft = GP("laminar/B738/annunciator/irs_align_left2")
    P.irsalignright = GP("laminar/B738/annunciator/irs_align_right2")
    P.irsposset = GP("laminar/B738/irs/irs_pos_set")

    P.yawdamperswitch = GP("laminar/B738/toggle_switch/yaw_dumper_pos")
 
    return missingCount
end

function P.initDataref()

    local debug_dataref_path = def.APPNAMEPREFIX .. "/state/debuglevel"
    local handle = globalProperty(debug_dataref_path)
    local xluaLogHandle = globalProperty("xlua/logging_enabled")
    if isProperty(xluaLogHandle) then
        P.xluaLoggingEnabled = xluaLogHandle
    else
        P.xluaLoggingEnabled = nil
    end

    if not isProperty(handle) then
        helpers.logInfoTS("Dataref '" .. debug_dataref_path .. "' not found. Creating it now.")
        local default_level = LOG_INFO
        P.debugLevelDataref = createGlobalPropertyi(debug_dataref_path, default_level, false, true, true)
        set(P.debugLevelDataref, default_level)

    else
        helpers.logInfoTS("Found existing dataref: '" .. debug_dataref_path .. "'")
        P.debugLevelDataref = handle
    end

    helpers.logInfoTS("Restoring Debug Log Level from dataref...")
    local stored_level = get(P.debugLevelDataref)

    if (stored_level ~= LOG_INFO) and (stored_level ~= LOG_DEBUG) then
         sasl.logWarning("Invalid debug level in dataref (" .. stored_level .. "). Resetting to INFO.")
         stored_level = LOG_INFO
         set(P.debugLevelDataref, stored_level)
    end

    sasl.setLogLevel(stored_level)
    P.lastPolledDebugLevel = stored_level
    helpers.logInfoTS("Debug Log Level set to: " .. stored_level)
    if P.xluaLoggingEnabled then
        set(P.xluaLoggingEnabled, stored_level == LOG_DEBUG and 1 or 0)
    end

    local reload_dataref_path = def.YALRELOADDATAREF or (def.APPNAMEPREFIX .. "/command/reload")
    local reload_handle = globalProperty(reload_dataref_path)
    if not isProperty(reload_handle) then
        helpers.logInfoTS("Dataref '" .. reload_dataref_path .. "' not found. Creating it now.")
        P.reloadRequestDr = createGlobalPropertyi(reload_dataref_path, 0, false, true, true)
    else
        helpers.logInfoTS("Found existing dataref: '" .. reload_dataref_path .. "'")
        P.reloadRequestDr = reload_handle
    end
    if P.reloadRequestDr then
        set(P.reloadRequestDr, 0)
    end

    local dataref_path = def.APPNAMEPREFIX .. "/state/procedureset"
    local handle = globalProperty(dataref_path)
    local maxId = 0
    for id, _ in pairs(P.proceduretable) do
        if id > maxId then maxId = id end
    end
    local expectedSize = maxId

    if not isProperty(handle) then
        helpers.logInfoTS("Dataref '" .. dataref_path .. "' not found. Creating it now.")
        P.ProcSetStatusarraydr = createGlobalPropertyia(dataref_path, expectedSize, false, true, true)
    else
        helpers.logInfoTS("Found existing dataref: '" .. dataref_path .. "'")
        P.ProcSetStatusarraydr = handle

        local currentSize = expectedSize
        if P.ProcSetStatusarraydr and P.ProcSetStatusarraydr.size then
            local ok, sizeValue = pcall(function() return P.ProcSetStatusarraydr:size() end)
            if ok and type(sizeValue) == "number" then
                currentSize = sizeValue
            end
        end

        if currentSize < expectedSize then
            helpers.logInfoTS("Expanding '" .. dataref_path .. "' from " .. tostring(currentSize) .. " to " .. tostring(expectedSize) .. " entries.")
            local existingValues = {}
            for idx = 1, currentSize do
                existingValues[idx] = get(P.ProcSetStatusarraydr, idx) or 0
            end

            local migratedValues = {}
            for idx = 1, expectedSize do migratedValues[idx] = 0 end

            local insertIndex = math.min(def.PACKSRESTOREPROCEDURE or (expectedSize - currentSize + 1), expectedSize)

            for idx = 1, expectedSize do
                if idx == insertIndex then
                    migratedValues[idx] = 0
                else
                    local sourceIndex = idx
                    if idx > insertIndex then
                        sourceIndex = idx - 1
                    end
                    if sourceIndex >= 1 and sourceIndex <= currentSize then
                        migratedValues[idx] = existingValues[sourceIndex] or 0
                    else
                        migratedValues[idx] = 0
                    end
                end
            end

            set(P.ProcSetStatusarraydr, migratedValues)

            local resized = currentSize
            if P.ProcSetStatusarraydr and P.ProcSetStatusarraydr.size then
                local ok, sizeValue = pcall(function() return P.ProcSetStatusarraydr:size() end)
                if ok and type(sizeValue) == "number" then
                    resized = sizeValue
                end
            end

            if resized < expectedSize then
                helpers.logInfoTS("Recreating '" .. dataref_path .. "' to ensure expanded size.")
                P.ProcSetStatusarraydr = createGlobalPropertyia(dataref_path, migratedValues, false, true, true)
            end
        elseif currentSize > expectedSize then
            sasl.logWarning("Dataref '" .. dataref_path .. "' has unexpected size " .. tostring(currentSize) .. " (expected " .. tostring(expectedSize) .. "). Extra entries will be ignored.")
        end
    end
    helpers.logInfoTS("Restoring procedure '.set' status from dataref array...")
    for id, proc in pairs(P.proceduretable) do
        local status = get(P.ProcSetStatusarraydr, id)
        proc.set = (status == 1)
    end
    P.LoopHandles = { [1] = {}, [2] = {}, [3] = {} }
    local loopNames = {"loop1", "loop2", "loop3"}

    -- Definiert die 4 Kern-Eigenschaften
    local loopProperties = {
        {name = "lock", type = "int", default = 0},
        {name = "state", type = "int", default = 0},       -- (stepindex)
        {name = "stepname", type = "string", default = ""}, -- (currentStepName)
        {name = "custom", type = "string", default = ""}  -- (Für vref, navindex, etc.)
    }
    for i = 1, #loopNames do
        local loopName = loopNames[i]
        sasl.logDebug("Initializing datarefs for " .. loopName)

        for _, prop in ipairs(loopProperties) do
            local path = def.APPNAMEPREFIX .. "/state/" .. loopName .. "/" .. prop.name
            local handle = globalProperty(path)

            if not isProperty(handle) then
                helpers.logInfoTS("Dataref '" .. path .. "' not found. Creating it now.")
                if prop.type == "int" then
                    handle = createGlobalPropertyi(path, prop.default, false, true, true)
                else -- string
                    handle = createGlobalPropertys(path, prop.default, false, true, true)
                end
            else
                helpers.logInfoTS("Found existing dataref: '" .. path .. "'")
            end

            P.LoopHandles[i][prop.name] = handle
        end
    end
    -- Lade die Zustände mit der neuen Funktion
    P.procedureloop1 = P.loadLoopState(1)
    P.procedureloop2 = P.loadLoopState(2)
    P.procedureloop3 = P.loadLoopState(3)
    P.loopStateTables = { P.procedureloop1, P.procedureloop2, P.procedureloop3 }

    helpers.logInfoTS("Procedure loop states restored from datarefs.")

    local path = def.APPNAMEPREFIX .. "/state/ongoingtaskstepindex"
    local handle = globalProperty(path)
    if not isProperty(handle) then
        helpers.logInfoTS("Dataref '" .. path .. "' not found. Creating it now.")
        P.OngoingTaskIndexdr = createGlobalPropertyi(path, 7, false, true, true)
    else
        helpers.logInfoTS("Found existing dataref: '" .. path .. "'")
        P.OngoingTaskIndexdr = handle
    end
    P.ongoingtaskstepindex = get(P.OngoingTaskIndexdr)
    if P.ongoingtaskstepindex == 0 then
        P.ongoingtaskstepindex = 7
    end
    if P.ongoingtaskstepindex < 7 or P.ongoingtaskstepindex > 11 then
        P.ongoingtaskstepindex = 7
    end
    P.ongoingcoretaskindex = 4
    helpers.logInfoTS("Ongoing task index restored to: " .. P.ongoingtaskstepindex)

    local path = def.APPNAMEPREFIX .. "/state/flightstate"
    local handle = globalProperty(path)
    if not isProperty(handle) then
        helpers.logInfoTS("Dataref '" .. path .. "' not found. Creating it now.")
        P.flightstatedr = createGlobalPropertyi(path, 0, false, true, true)
    else
        helpers.logInfoTS("Found existing dataref: '" .. path .. "'")
        P.flightstatedr = handle
        P.isReloadWithinSession = true
    end
    P.flightstate = get(P.flightstatedr)
    helpers.logInfoTS("Flightstate restored to: " .. P.flightstate)

    P.initialExternalDatarefMissingCount = P.bindExternalDatarefs(true)
    P.needsPostStartupDatarefRebind = true
    P.externalDatarefsPostStartupDone = false
    if P.initialExternalDatarefMissingCount > 0 then
        helpers.logInfoTS("Initial external dataref bind deferred for " .. tostring(P.initialExternalDatarefMissingCount) .. " handles")
    end
    if P.n1setsource and isProperty(P.n1setsource) then
        set(P.n1setsource, 0)
    end

    P.fmsselectedsid = nil
    P.fmsselectedstar = nil
    P.fmsselectedapp = nil

    local function ensureHoppieString(path, defaultVal)
        local handle = globalProperty(path)
        if not isProperty(handle) then
            helpers.logInfoTS("Dataref '" .. path .. "' not found. Creating it now.")
            handle = createGlobalPropertys(path, defaultVal or "", false, true, false)
        else
            helpers.logInfoTS("Found existing dataref: '" .. path .. "'")
        end
        return handle
    end

    local function ensureHoppieNumber(path, defaultVal)
        local handle = globalProperty(path)
        if not isProperty(handle) then
            helpers.logInfoTS("Dataref '" .. path .. "' not found. Creating it now.")
            handle = createGlobalPropertyi(path, defaultVal or 0, false, true, false)
        else
            helpers.logInfoTS("Found existing dataref: '" .. path .. "'")
        end
        return handle
    end
    local function findHoppieOptional(path)
        local handle = globalProperty(path)
        if not isProperty(handle) then
            helpers.logInfoTS("Optional dataref '" .. path .. "' not found.")
            return nil
        end
        helpers.logInfoTS("Found existing dataref: '" .. path .. "'")
        return handle
    end

    P.hoppie = {}
    P.hoppie.send_queue = ensureHoppieString("hoppiebridge/send_queue", "")
    P.hoppie.send_message_to = ensureHoppieString("hoppiebridge/send_message_to", "")
    P.hoppie.send_message_type = ensureHoppieString("hoppiebridge/send_message_type", "")
    P.hoppie.send_message_packet = ensureHoppieString("hoppiebridge/send_message_packet", "")
    P.hoppie.callsign = ensureHoppieString("hoppiebridge/callsign", "")
    P.hoppie.send_callsign = ensureHoppieString("hoppiebridge/send_callsign", "")
    P.hoppie.poll_queue = ensureHoppieString("hoppiebridge/poll_queue", "")
    P.hoppie.poll_message_origin = ensureHoppieString("hoppiebridge/poll_message_origin", "")
    P.hoppie.poll_message_from = ensureHoppieString("hoppiebridge/poll_message_from", "")
    P.hoppie.poll_message_type = ensureHoppieString("hoppiebridge/poll_message_type", "")
    P.hoppie.poll_message_packet = ensureHoppieString("hoppiebridge/poll_message_packet", "")
    P.hoppie.poll_queue_clear = ensureHoppieNumber("hoppiebridge/poll_queue_clear", 0)
    P.hoppie.poll_freq_fast = ensureHoppieNumber("hoppiebridge/poll_frequency_fast", 0)
    P.hoppie.comm_ready = ensureHoppieNumber("hoppiebridge/comm_ready", 0)
    P.hoppie.logon = ensureHoppieString(def.APPNAMEPREFIX .. "/hoppie/logon", "")
    P.hoppie.debug_level = ensureHoppieNumber(def.APPNAMEPREFIX .. "/hoppie/debug_level", 1)
    P.hoppie.status = ensureHoppieString(def.APPNAMEPREFIX .. "/hoppie/status", "")
    P.hoppie.last_error = ensureHoppieString(def.APPNAMEPREFIX .. "/hoppie/last_error", "")
    P.hoppie.last_http = ensureHoppieString(def.APPNAMEPREFIX .. "/hoppie/last_http", "")
    P.hoppie.send_count = ensureHoppieNumber(def.APPNAMEPREFIX .. "/hoppie/send_count", 0)
    P.hoppie.poll_count = ensureHoppieNumber(def.APPNAMEPREFIX .. "/hoppie/poll_count", 0)
    P.hoppie.voice_seq = findHoppieOptional(def.APPNAMEPREFIX .. "/hoppie/voice_seq")
    P.hoppie.voice_text = findHoppieOptional(def.APPNAMEPREFIX .. "/hoppie/voice_text")

    if P.hoppie.debug_level then
        local level = sasl.getLogLevel() == LOG_DEBUG and 3 or 1
        set(P.hoppie.debug_level, level)
    end

    P.needstempinit = true
end

--------------------------------------------------------------------------------------------------------------
function P.initializeSharedVariables()

    helpers.logInfoTS("Initializing SHARED monitoring variables.")

    P.apgoaroundtemp = get(P.apgoaround)

    P.desrwyheadingtemp = get(P.desrwyheading)
    P.desrwylatstartpostemp = get(P.desrwylatstartpos)
    P.desrwylonstartpostemp = get(P.desrwylonstartpos)
    P.desrwylatendpostemp = get(P.desrwylatendpos)
    P.desrwylonendpostemp = get(P.desrwylonendpos)
end

--------------------------------------------------------------------------------------------------------------
function P.buildProcedureLabelMaps()
    helpers.logInfoTS("Initializing procedure step access functions (get_index)...") -- Log message slightly adjusted

    for procKey, procData in pairs(P.proceduretable) do
        -- Only process procedures using the data-driven engine (string keys)
        -- The check for 'startStep' confirms it's the new format.
        if procData.steps and type(procData.steps) == "table" and procData.startStep then

            sasl.logDebug("Setting up get_index for String-Key procedure: " .. procData.name) -- Changed to Debug

            -- Assign the simple get_index function required for string keys.
            -- (Even though Engine A uses names directly, jump steps might still use get_index)
            if not procData.get_index then
                 procData.get_index = function(self, label)
                    -- Check if the requested step name actually exists in the steps table
                    if not self.steps[label] then
                        sasl.logDebug("Procedure " .. self.name .. ": Invalid step label '" .. tostring(label) .. "' requested.")
                        return nil -- Return nil for non-existent string keys (Engine A handles nil)
                    end
                    -- For string keys, the "index" *is* the label itself.
                    return label
                end
            end

        -- else -- Optional: Log procedures that don't seem to fit the pattern (shouldn't happen now)
        --    if procData.steps then 
        --        sasl.logWarning("Procedure " .. procData.name .. " has 'steps' but no 'startStep'. Skipping get_index setup.")
        --    end
        end
    end
    helpers.logInfoTS("Procedure step access functions initialized.") -- Log message slightly adjusted
end

-------------------------------------------------------------------------------------------------------------- 
function P.resetLoopState(loopTable)
    if not loopTable then return end -- Safety check

    local cleanTemplate = P.procedurelooptemplate -- Use the master template

    loopTable.stepindex = cleanTemplate.stepindex          -- Setzt auf 0
    loopTable.steprepeat = cleanTemplate.steprepeat        -- Setzt auf false
    loopTable.procedureabort = cleanTemplate.procedureabort    -- Setzt auf false
    loopTable.procedureskipped = cleanTemplate.procedureskipped -- Setzt auf false
    loopTable.procedureskipstep = cleanTemplate.procedureskipstep -- Setzt auf false
    loopTable.setonabort = cleanTemplate.setonabort        -- Setzt auf false
    loopTable.lastActiveTime = 0                     -- Setzt auf 0
    loopTable.currentStepName = nil                       -- Explizit nil setzen
    loopTable.lastStepName = nil                           -- Explizit nil setzen
    loopTable.procedurenotpossible = cleanTemplate.procedurenotpossible -- Setzt auf false
    loopTable.triggeredmanually = cleanTemplate.triggeredmanually -- Setzt auf false (Standard)
    loopTable.triggeredat = 0
    loopTable.skipConfirmForStep = nil
    loopTable.adviceRepeatKey = nil
    loopTable.adviceRepeatCount = 0
    loopTable.adviceRepeatSpoken = 0
    loopTable.stepOnceRequested = false
    loopTable.stepOnceTargetStep = nil
    loopTable.debugPaused = false
    loopTable.debugStepOnce = false
    loopTable.debugBreakpoints = {}
    loopTable.debugHistory = nil

    P.deleteCustomData(loopTable) -- Entfernt vref, navindex etc.

    sasl.logDebug("... Loop state transient flags and custom data reset.") -- Optional: Debug Log
end

--------------------------------------------------------------------------------------------------------------
function P.XCameraIsInstalled()
    local signature = "SRS.X-Camera"
    local pluginID = sasl.findPluginBySignature(signature)

    if pluginID ~= NO_PLUGIN_ID then
        if P.XCameraPluginID ~= pluginID then
            helpers.logInfoTS("X-Camera plugin detected, integration enabled.")
        end
        P.XCameraPluginID = pluginID
        P.xcamerastatus = globalProperty("SRS/X-Camera/integration/overall_status")
    else
        P.XCameraPluginID = NO_PLUGIN_ID
        P.xcamerastatus = nil
    end
end

--------------------------------------------------------------------------------------------------------------
function P.YANSHisinstalled()
    local signature = "1-sim YANSH"
    local pluginID = sasl.findPluginBySignature(signature)

    if pluginID ~= NO_PLUGIN_ID then
        if P.YANSHPluginID ~= pluginID then
            helpers.logInfoTS("YANSH plugin detected, integration enabled.")
        end
        P.YANSHPluginID = pluginID

        if not P.YANSHFuelPlanRamp then
            P.YANSHFuelAlternateBurn = globalProperty("YANSH/sb/fuel/alternate_burn")
            P.YANSHFuelEnrouteBurn = globalProperty("YANSH/sb/fuel/enroute_burn")
            P.YANSHFuelMinTakeoff = globalProperty("YANSH/sb/fuel/min_takeoff")
            P.YANSHFuelPlanRamp = globalProperty("YANSH/sb/fuel/plan_ramp")
            P.YANSHFuelReserve = globalProperty("YANSH/sb/fuel/reserve")
            P.YANSHGeneralInitialAltitude = globalProperty("YANSH/sb/general/initial_altitude")
            P.YANSHGeneralMaxAltitude = globalProperty("YANSH/sb/general/max_altitude")
            P.YANSHParamsUnitsFlag = globalProperty("YANSH/sb/params/units_flag")
        end

        return true
    end

    P.YANSHPluginID = NO_PLUGIN_ID
    return false
end

-------------------------------------------------------------------------------------------------------------- 
function P.YANSHflightplanloaded()
    if P.YANSHisinstalled() and P.YANSHFuelPlanRamp and P.YANSHGeneralMaxAltitude then
        if ((get(P.YANSHFuelPlanRamp) > 0) and (get(P.YANSHGeneralMaxAltitude) > 0)) then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------------------------------------
function P.checkYANSHFuel()
    if P.YANSHisinstalled() and P.YANSHflightplanloaded() and P.YANSHFuelPlanRamp and P.YANSHParamsUnitsFlag then

        local currentFuelLbs = get(P.totalfuellbs)
        local plannedFuelRaw = get(P.YANSHFuelPlanRamp)

        if type(currentFuelLbs) ~= "number" or type(plannedFuelRaw) ~= "number" or plannedFuelRaw <= 0 then
            return
        end

        local plannedFuelLbs = plannedFuelRaw
        if get(P.YANSHParamsUnitsFlag) == def.YANSHUNITKGS then
            plannedFuelLbs = plannedFuelRaw * def.KGTOLBS
        end

        -- Check against max capacity (temp-scaled)
        local capFactor = helpers.getFuelCapacityFactor(get(P.fueltemp))
        local maxWing = def.MAXWINGTANKLBS * capFactor
        local maxCenter = def.MAXCENTERTANKLBS * capFactor
        local maxTotal = maxCenter + (2 * maxWing)

        if plannedFuelLbs > maxTotal then
            local unitSuffix = (get(P.fuelunit) == def.KG) and "K G" or "L B S"
            local plannedDisplay = (get(P.fuelunit) == def.KG) and helpers.roundnumber(plannedFuelLbs * def.LBSTOKG) or helpers.roundnumber(plannedFuelLbs)
            local maxDisplay = (get(P.fuelunit) == def.KG) and helpers.roundnumber(maxTotal * def.LBSTOKG) or helpers.roundnumber(maxTotal)
            P.commandtableentry(def.TEXT, string.format("Planned fuel %s exceeds max capacity %s %s", tostring(plannedDisplay), tostring(maxDisplay), unitSuffix))
        end

        local plannedForDisplay, currentForDisplay, unitForDisplay
        if (get(P.fuelunit) == def.KG) then
            plannedForDisplay = helpers.roundnumber(plannedFuelLbs * def.LBSTOKG)
            currentForDisplay = helpers.roundnumber(currentFuelLbs * def.LBSTOKG)
            unitForDisplay = "K G"
        else
            plannedForDisplay = helpers.roundnumber(plannedFuelLbs)
            currentForDisplay = helpers.roundnumber(currentFuelLbs)
            unitForDisplay = "L B S"
        end

        local difference = currentFuelLbs - plannedFuelLbs
        local message = ""
        local result = true

        if difference < -200 then
            message = "Underfuel: planned " .. plannedForDisplay .. ", actual " .. currentForDisplay .. " " .. unitForDisplay .. "."
            result = false
        elseif difference > 500 then
            message = "Extra fuel: planned " .. plannedForDisplay .. ", actual " .. currentForDisplay .. " " .. unitForDisplay .. "."
            result = true
        else
            message = "Fuel ok: planned " .. plannedForDisplay .. ", actual " .. currentForDisplay .. " " .. unitForDisplay .. "."
            result = true
        end

        P.commandtableentry(def.TEXT, message)
        return result

    end
end

--------------------------------------------------------------------------------------------------------------
function P.BPBisinstalled()
    local signature = "skiselkov.BetterPushback"
    local pluginID = sasl.findPluginBySignature(signature)

    if pluginID ~= NO_PLUGIN_ID then
        if P.BPBPluginID ~= pluginID then
            helpers.logInfoTS("BetterPushback plugin detected, integration enabled.")
        end
        P.BPBPluginID = pluginID

        if not P.BPBPlanComplete then
            P.BPBPlanComplete = globalProperty("bp/plan_complete")
        end
        if not P.BPBOpComplete then
            P.BPBOpComplete = globalProperty("bp/op_complete")
        end
        if not P.BPBStarted then
            P.BPBStarted = globalProperty("bp/started")
        end
        if not P.BPBConnected then
            local connectedRef = globalProperty("bp/connected")
            if isProperty(connectedRef) then
                P.BPBConnected = connectedRef
            else
                P.BPBConnected = nil
            end
        end

        local plannerref = globalProperty("bp/planner_open")
        if isProperty(plannerref) then
            if not P.BPBPlannerOpen or not isProperty(P.BPBPlannerOpen) then
                P.BPBPlannerOpen = globalProperty("bp/planner_open")
            end
        else
            P.BPBPlannerOpen = nil
        end
        return true
    end

    P.BPBPluginID = NO_PLUGIN_ID
    P.BPBPlanComplete = nil
    P.BPBOpComplete = nil
    P.BPBStarted = nil
    P.BPBPlannerOpen = nil
    P.BPBConnected = nil
    return false
end

--------------------------------------------------------------------------------------------------------------
function P.IVAOMonitorIsInstalled()
    local signature = "wahltho.ivao.monitor"
    local pluginID = sasl.findPluginBySignature(signature)

    if pluginID ~= NO_PLUGIN_ID then
        if P.IVAOMonitorPluginID ~= pluginID then
            helpers.logInfoTS("IVAO monitor plugin detected, integration enabled.")
        end
        P.IVAOMonitorPluginID = pluginID

        if not P.IVAOFlightplanPresent then
            P.IVAOFlightplanPresent = globalProperty("ivao_monitor/flightplan_present")
        end
        if not P.IVAOFlightplanDep then
            P.IVAOFlightplanDep = globalProperty("ivao_monitor/flightplan_dep")
        end
        if not P.IVAOFlightplanArr then
            P.IVAOFlightplanArr = globalProperty("ivao_monitor/flightplan_arr")
        end
        if not P.IVAOFlightplanId then
            P.IVAOFlightplanId = globalProperty("ivao_monitor/flightplan_id")
        end
        if not P.IVAOFlightplanNumber then
            P.IVAOFlightplanNumber = globalProperty("ivao_monitor/flightplan_number")
        end
        if not P.IVAOOnline or not isProperty(P.IVAOOnline) then
            local onlineRef = globalProperty("ivaopilot/online")
            if isProperty(onlineRef) then
                P.IVAOOnline = onlineRef
            else
                P.IVAOOnline = nil
            end
        end

        return true
    end

    P.IVAOMonitorPluginID = NO_PLUGIN_ID
    P.IVAOFlightplanPresent = nil
    P.IVAOFlightplanDep = nil
    P.IVAOFlightplanArr = nil
    P.IVAOFlightplanId = nil
    P.IVAOFlightplanNumber = nil
    P.IVAOOnline = nil
    return false
end

--------------------------------------------------------------------------------------------------------------
function P.HoppieHelperIsInstalled()
    local signature = "yal.hoppiehelper"
    local pluginID = sasl.findPluginBySignature(signature)

    if pluginID ~= NO_PLUGIN_ID then
        if P.HoppieHelperPluginID ~= pluginID then
            helpers.logInfoTS("HoppieHelper plugin detected, integration enabled.")
        end
        P.HoppieHelperPluginID = pluginID
        return true
    end

    P.HoppieHelperPluginID = NO_PLUGIN_ID
    return false
end

--------------------------------------------------------------------------------------------------------------
function P.YalMaintenanceExecutorIsInstalled()
    local hasHoppieHelper = false
    local hasIvaoMonitor = false

    if P.HoppieHelperIsInstalled then
        hasHoppieHelper = P.HoppieHelperIsInstalled()
    end
    if P.IVAOMonitorIsInstalled then
        hasIvaoMonitor = P.IVAOMonitorIsInstalled()
    end

    return hasHoppieHelper or hasIvaoMonitor
end

--------------------------------------------------------------------------------------------------------------
function P.initializeScript()

    P.YalinitGlobal()

    PD.fillProcedureTable()

    P.buildProcedureLabelMaps()

    P.initDataref()

    P.readconfig()

    helpers.checkCgBaselineAtStartup()
    helpers.checkDefaultViewAtStartup()

    helpers.buildnavdatatable(P.navdatatable)
    helpers.buildairportdatatable(P.airportdatatable)
    if P.configvalues[def.CONFIGAUTOTAXIGUIDANCE] == def.ON then
        helpers.requestGlobalAptIndex("startup")
    end
    P.zibocalctable = helpers.loadZiboReferenceTables() or {}
    if (sasl.getLogLevel() == LOG_DEBUG) then
        helpers.writenavdatatable(P.navdatatable)
        helpers.writeairportdatatable(P.airportdatatable)
        helpers.writeZiboCalcTable(P.zibocalctable)
        helpers.writetaxidatatable()
    end

    P.commandtableentry(def.TEXT, "YAL Initialization done")
    helpers.logInfoTS("Initialization and state restored")

    P.lastLoggedFlightstate = P.flightstate
    P.lastLoggedFmsFlightphase = get(P.fmsflightphase)
    P.lastLoggedAircraftwasonground = P.aircraftwasonground
end

--------------------------------------------------------------------------------------------------------------
function P.yalresetForNewFlight()

    if ((P.flightstate < def.FLIGHTSTATESHUTDOWN) or (P.procedureloop1.lock ~= def.NOPROCEDURE)) then
        P.commandtableentry(def.TEXT, "Reset for a New flight only possible at Parking Position")
        return true
    end

    helpers.logInfoTS("Reset for new flight initiated.")

    P.YalinitGlobal()

    PD.fillProcedureTable()
    P.buildProcedureLabelMaps()
    P.initDataref()
    P.readconfig()

    -- Reset locks explicitly for a new flight
    P.procedureloop1.lock = def.NOPROCEDURE
    P.procedureloop2.lock = def.NOPROCEDURE
    P.procedureloop3.lock = def.NOPROCEDURE

    for _, proc in pairs(P.proceduretable) do
        proc.set = false
    end

    if get(P.battery) == def.ON or (P.apurunning() == def.APUONBUS) or (get(P.gpuon) == def.ON) then
        P.proceduretable[def.COLDANDDARKPROCEDURE].set = true
    end

    for idx, loop in ipairs(P.loopStateTables) do
        P.resetLoopState(loop)
        P.saveLoopState(loop, idx)
    end

    local statusArray = {}
    for i = 1, #P.proceduretable do
        if P.proceduretable[i].set == true then
            statusArray[i] = 1
        else
            statusArray[i] = 0
        end
    end
    set( P.ProcSetStatusarraydr, statusArray)

    helpers.buildnavdatatable(P.navdatatable)
    helpers.buildairportdatatable(P.airportdatatable)
    P.zibocalctable = helpers.loadZiboReferenceTables() or {}
    if (sasl.getLogLevel() == LOG_DEBUG) then
        helpers.writenavdatatable(P.navdatatable)
        helpers.writeairportdatatable(P.airportdatatable)
        helpers.writeZiboCalcTable(P.zibocalctable)
    end

    P.commandtableentry(def.TEXT, "Reset for a new flight done.")

    P.lastLoggedFlightstate = P.flightstate
    P.lastLoggedFmsFlightphase = get(P.fmsflightphase)
    P.lastLoggedAircraftwasonground = P.aircraftwasonground

    if P.YANSHisinstalled() then
        local cmdId = sasl.findCommand("sasl/reload/yansh")
        if cmdId then
            sasl.commandOnce(cmdId)
        end
    end
    if P.BPBisinstalled() then
        local cmdId = sasl.findCommand("BetterPushback/reload")
        if cmdId then
            sasl.commandOnce(cmdId)
        end
    end

    return true

end

function P.yalresetForNewFlight_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.yalresetForNewFlight()
    end
    return 0
end

local my_command_yalresetForNewFlight = sasl.createCommand(def.APPNAMEPREFIX .. "/yalresetForNewFlight", "YAL Reset for New Flight")
sasl.registerCommandHandler(my_command_yalresetForNewFlight, 0, P.yalresetForNewFlight_)

--------------------------------------------------------------------------------------------------------------
function P.yalreset()
    helpers.logInfoTS("Manual YAL Reset initiated")

    -- Setzt Speicher zurück, lädt dann Persistenz, liest Config
    P.YalinitGlobal()
    PD.fillProcedureTable()
    P.buildProcedureLabelMaps()
    P.initDataref() -- Lädt .set Flags, Loops und flightstate aus Datarefs
    P.readconfig()

    -- Set loop locks clean for a fresh start
    P.procedureloop1.lock = def.NOPROCEDURE
    P.procedureloop2.lock = def.NOPROCEDURE
    P.procedureloop3.lock = def.NOPROCEDURE

    -- Versucht, .set Flags basierend auf dem Flugzeugzustand zu aktualisieren
    P.syncProceduresOnLoad()

    -- *** NEU: Flight State prüfen und korrigieren ***
    local aircraftIsOnGround = (get(P.airgroundsensor) == def.ON)
    local stateFromProcs = P.determineFlightStateFromProcedures() -- State aus .set Flags ableiten
    local stateIsPlausible = false
    local finalState = stateFromProcs

    -- Plausibilitätscheck
    sasl.logDebug("Reset Plausibility Check: State from Procs = " .. stateFromProcs .. ", On Ground = " .. tostring(aircraftIsOnGround))
    if aircraftIsOnGround then
        if stateFromProcs == def.FLIGHTSTATEPREFLIGHT or
           stateFromProcs == def.FLIGHTSTATETAXITOGATE or
           stateFromProcs == def.FLIGHTSTATESHUTDOWN then
            stateIsPlausible = true
        end
    else
        if stateFromProcs == def.FLIGHTSTATEINITIALCLIMB or
           stateFromProcs == def.FLIGHTSTATECLIMB or
           stateFromProcs == def.FLIGHTSTATECRUISE or
           stateFromProcs == def.FLIGHTSTATEAPPROACH then
            stateIsPlausible = true
        end
    end

    if not stateIsPlausible then
        helpers.logInfoTS("State from procedures ("..stateFromProcs..") implausible after reset sync. Falling back.")
        -- Fallback
        if aircraftIsOnGround then
            if helpers.isParkingBrakeSet() then
                finalState = def.FLIGHTSTATESHUTDOWN
            else
                finalState = def.FLIGHTSTATETAXITOGATE
            end
        else
            local vs = get(P.verticalspeed) or 0
            if vs < -300 then
                finalState = def.FLIGHTSTATEAPPROACH
            else
                finalState = def.FLIGHTSTATECLIMB
            end
        end
        helpers.logInfoTS("State after fallback: " .. finalState)
    else
        sasl.logDebug("State from procedures ("..finalState..") is plausible.")
    end

    -- Update und Speichern, falls nötig
    if finalState ~= P.flightstate then
         helpers.logInfoTS("Correcting flight state during reset. Old: " .. P.flightstate .. ", New: " .. finalState)
         P.flightstate = finalState
         set(P.flightstatedr, P.flightstate) -- Sofort speichern!
    end
    -- *** ENDE NEU ***

    -- Aktualisierte .set Flags speichern
    local statusArray = {}
    for i = 1, #P.proceduretable do
         statusArray[i] = (P.proceduretable[i] and P.proceduretable[i].set and 1) or 0
    end
    set(P.ProcSetStatusarraydr, statusArray)

    -- Aktuellen Loop States speichern (wichtig nach initDataref)
    sasl.logDebug("Saving current loop states after yalreset...")
    for i = 1, #P.loopStateTables do
        P.saveLoopState(P.loopStateTables[i], i)
    end

    -- Rest (NavData bauen etc.)
    helpers.buildnavdatatable(P.navdatatable)
    helpers.buildairportdatatable(P.airportdatatable)
    P.zibocalctable = helpers.loadZiboReferenceTables() or {}
    if (sasl.getLogLevel() == LOG_DEBUG) then
        helpers.writenavdatatable(P.navdatatable)
        helpers.writeairportdatatable(P.airportdatatable)
    end

    P.commandtableentry(def.TEXT, "YAL Reset done")

    -- Logging Vars zurücksetzen
    P.lastLoggedFlightstate = P.flightstate
    P.lastLoggedFmsFlightphase = get(P.fmsflightphase)
    P.lastLoggedAircraftwasonground = aircraftIsOnGround -- Use current value
end

function P.yalreset_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.yalreset()
    end
    return 0
end

local my_command_yalreset = sasl.createCommand(def.APPNAMEPREFIX .. "/yalreset", "YAL Reset")
sasl.registerCommandHandler(my_command_yalreset, 0, P.yalreset_)

--------------------------------------------------------------------------------------------------------------
function P.readconfig()

    local newSettings = settings.getSettings()

    for k in pairs(P.configvalues) do
        P.configvalues[k] = nil
    end

    for k, v in pairs(newSettings) do
        P.configvalues[k] = v
    end

    if P.hoppie and P.hoppie.logon and isProperty(P.hoppie.logon) then
        local logon = tostring(P.configvalues[def.CONFIGHOPPIEID] or "")
        logon = logon:gsub("%s+", "")
        set(P.hoppie.logon, logon)
    end

    if P.wakeoverride and isProperty(P.wakeoverride) then
        if (P.configvalues[def.CONFIGWAKEOVERRIDE] == def.ON) then
            set(P.wakeoverride, def.ON)
        else
            set(P.wakeoverride, def.OFF)
        end
    end

    if sasl.getOS() == 'Windows' and P.configvalues[def.CONFIGJITLUAON] == def.ON then
        local jitDr = globalProperty("xlua/jit_enabled")
        if isProperty(jitDr) then
            set(jitDr, 1)
            helpers.logInfoTS("JITLUAON active: xlua/jit_enabled set to 1")
        else
            helpers.logInfoTS("JITLUAON requested but xlua/jit_enabled not found")
        end
    end

    local fmsSelectedSid = globalProperty("laminar/B738/fms/selected_sid")
    if isProperty(fmsSelectedSid) then
        P.fmsselectedsid = fmsSelectedSid
    else
        P.fmsselectedsid = nil
    end
    local fmsSelectedStar = globalProperty("laminar/B738/fms/selected_star")
    if isProperty(fmsSelectedStar) then
        P.fmsselectedstar = fmsSelectedStar
    else
        P.fmsselectedstar = nil
    end
    local fmsSelectedApp = globalProperty("laminar/B738/fms/selected_app")
    if isProperty(fmsSelectedApp) then
        P.fmsselectedapp = fmsSelectedApp
    else
        P.fmsselectedapp = nil
    end

    P.initDevReloadControls()

    P.needstempinit = true

    return true

end

function P.readconfig_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.readconfig()
    end
    return 0
end

local my_command_readconfig = sasl.createCommand(def.APPNAMEPREFIX .. "/readconfig", "Read Config File")
sasl.registerCommandHandler(my_command_readconfig, 0, P.readconfig_)

--------------------------------------------------------------------------------------------------------------
function P.setview(view, normalizeFirst)

    normalizeFirst = normalizeFirst or false

    local commandIssued = false
    local viewChangesOn = (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON)
    if viewChangesOn and P.tobiiEyetracker and isProperty(P.tobiiEyetracker) then
        if get(P.tobiiEyetracker) == 1 then
            if not P.tobiiViewSuppressLogged then
                helpers.logInfoTS("View change skipped: Tobii active")
                P.tobiiViewSuppressLogged = true
            end
            return false
        elseif P.tobiiViewSuppressLogged then
            P.tobiiViewSuppressLogged = nil
        end
    end

    if (viewChangesOn and ((get(P.tirespeed) < 1) or (get(P.airgroundsensor) == def.OFF))) then
        if ((view == nil) or (type(view) ~= "number") or (view ~= math.floor(view))) then
            sasl.logDebug("Invalid input to setview")
            return false
        end

        if (view ~= P.previousview) then

            if normalizeFirst and (view ~= def.DEFAULTVIEW) then
                sasl.logDebug("Normalizing view to default first...")
                P.commandtableentry(def.COMMAND, "sim/view/default_view")
                commandIssued = true
            end

            if (view == def.DEFAULTVIEW) then
                P.commandtableentry(def.COMMAND, "sim/view/default_view")
            else
                if (P.xcamerastatus ~= nil) then
                    P.commandtableentry(def.COMMAND, "SRS/X-Camera/Select_View_ID_" .. view)
                else
                    P.commandtableentry(def.COMMAND, "sim/view/quick_look_" .. tostring(view - 1))
                end
            end

            sasl.logDebug("Setting View #" .. view)
            P.previousview = view
            commandIssued = true
        else
            sasl.logDebug("View #" .. view .. " already set")
        end
    end

    return commandIssued
end

local function map_runway_friction(value)
    if value <= def.RUNWAY_FRICTION_MAX_WET then
        return def.RUNWAY_FRICTION_WET
    elseif value <= def.RUNWAY_FRICTION_MAX_SNOWY then
        return def.RUNWAY_FRICTION_SNOWY
    elseif value <= def.RUNWAY_FRICTION_MAX_SNOWY_ICY then
        return def.RUNWAY_FRICTION_SNOWY_ICY
    end
    return def.RUNWAY_FRICTION_HEAVY
end

function P.applyRunwayFrictionClamp()
    if not P.runwayfriction or not isProperty(P.runwayfriction) then
        return
    end
    local friction = get(P.runwayfriction)
    if type(friction) ~= "number" then
        return
    end
    if P.runwayFrictionAdjusted ~= nil and math.abs(friction - P.runwayFrictionAdjusted) <= 0.01 then
        return
    end
    if friction < def.RUNWAY_FRICTION_CLAMP_MIN then
        if P.runwayFrictionAdjusted ~= nil then
            P.runwayFrictionAdjusted = nil
            P.runwayFrictionSeen = nil
            helpers.logInfoTS("Runway friction clamp released")
        end
        return
    end

    local desired = map_runway_friction(friction)
    if friction ~= desired then
        set(P.runwayfriction, desired)
        P.runwayFrictionAdjusted = desired
        P.runwayFrictionSeen = friction
        helpers.logInfoTS(string.format("Runway friction clamped: %.1f -> %d", friction, desired))
    end
end

--------------------------------------------------------------------------------------------------------------
function P.commandtableentry(state, text)

    local index = 1
    local duplicateentryfound = false

    if (state ~= def.COMMAND) then
        while (index <= #P.commandtable) do
            if ((P.commandtable[index][1] == state) and (P.commandtable[index][2] == text)) then
                duplicateentryfound = true
            end
            index = index + 1
        end
    end

    if not duplicateentryfound then
        local newentryindex = #P.commandtable + 1
        P.commandtable[newentryindex] = {}
        P.commandtable[newentryindex][1] = state
        P.commandtable[newentryindex][2] = text
    end

end

--------------------------------------------------------------------------------------------------------------
function P.shouldQueueVoiceAdvice(loop, stepName, adviceText)
    if not loop then
        return true, nil
    end

    local skipCount = tonumber(P.configvalues[def.CONFIGVOICEADVICEREPEATSKIP]) or 0
    if skipCount < 0 then
        skipCount = 0
    end

    local maxRepeats = tonumber(P.configvalues[def.CONFIGVOICEADVICEMAXREPEATS]) or 0
    if maxRepeats < 0 then
        maxRepeats = 0
    end
    if maxRepeats >= 99 then
        maxRepeats = 0
    end

    local key = tostring(loop.lock or 0) .. "|" .. tostring(stepName or "") .. "|" .. tostring(adviceText or "")
    if loop.adviceRepeatKey ~= key then
        loop.adviceRepeatKey = key
        loop.adviceRepeatCount = 0
        loop.adviceRepeatSpoken = 1
        return true, nil
    end

    local spokenCount = tonumber(loop.adviceRepeatSpoken) or 0
    if maxRepeats > 0 and spokenCount >= maxRepeats then
        return false, "max-reached"
    end

    local currentCount = tonumber(loop.adviceRepeatCount) or 0
    if skipCount <= 0 then
        loop.adviceRepeatCount = currentCount + 1
        loop.adviceRepeatSpoken = spokenCount + 1
        return true, nil
    end

    if currentCount >= skipCount then
        loop.adviceRepeatCount = 0
        loop.adviceRepeatSpoken = spokenCount + 1
        return true, nil
    end

    loop.adviceRepeatCount = currentCount + 1
    return false, "repeat-skip"
end

--------------------------------------------------------------------------------------------------------------
local function resetVoiceAdviceRepeatState(state)
    if not state then
        return
    end
    state.key = nil
    state.count = 0
    state.spoken = 0
end

--------------------------------------------------------------------------------------------------------------
local function shouldQueueStandaloneVoiceAdvice(state, adviceKey, adviceText)
    if type(adviceText) ~= "string" or adviceText == "" then
        return false, "invalid"
    end

    local key = tostring(adviceKey or adviceText)
    if type(state) ~= "table" then
        return true, nil
    end

    local skipCount = tonumber(P.configvalues[def.CONFIGVOICEADVICEREPEATSKIP]) or 0
    if skipCount < 0 then
        skipCount = 0
    end

    local maxRepeats = tonumber(P.configvalues[def.CONFIGVOICEADVICEMAXREPEATS]) or 0
    if maxRepeats < 0 then
        maxRepeats = 0
    end
    if maxRepeats >= 99 then
        maxRepeats = 0
    end

    if state.key ~= key then
        state.key = key
        state.count = 0
        state.spoken = 1
        return true, nil
    end

    local spokenCount = tonumber(state.spoken) or 0
    if maxRepeats > 0 and spokenCount >= maxRepeats then
        return false, "max-reached"
    end

    local currentCount = tonumber(state.count) or 0
    if skipCount <= 0 then
        state.count = currentCount + 1
        state.spoken = spokenCount + 1
        return true, nil
    end

    if currentCount >= skipCount then
        state.count = 0
        state.spoken = spokenCount + 1
        return true, nil
    end

    state.count = currentCount + 1
    return false, "repeat-skip"
end

--------------------------------------------------------------------------------------------------------------
function P.togglesimfreeze()

    if (get(P.simfreezed) == def.OFF) then
        set(P.simfreezed, def.ON)
    else
        set(P.simfreezed, def.OFF)
    end

end

function P.togglesimfreeze_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglesimfreeze()
    end
    return 0
end

local my_command_togglesimfreeze = sasl.createCommand(def.APPNAMEPREFIX .. "/togglesimfreeze", "Toggle Freeze Sim")
sasl.registerCommandHandler(my_command_togglesimfreeze, 0, P.togglesimfreeze_)


--------------------------------------------------------------------------------------------------------------
function P.timewarptotod()
    if ((P.procedureloop1.lock ~= def.NOPROCEDURE) or (P.procedureloop2.lock ~= def.NOPROCEDURE) or (P.procedureloop3.lock ~= def.NOPROCEDURE)) then
        P.commandtableentry(def.TEXT, "Time Warp not possible when Procedure is Active")
        return true
    end

    if (get(P.fmsflightphase) ~= def.FMSFLIGHTPHASE_CRUISE) then
        P.commandtableentry(def.TEXT, "Time Warp only possible during Cruise")
        return true
    end

    if (get(P.vnavtoddist) < 10) then
        P.commandtableentry(def.TEXT, "Time Warp only possible prior to Top of Descent ")
        return true
    end

    local legstable = helpers.buildlegstable(get(P.fmslegs), get(P.fmslegslat), get(P.fmslegslon))

    if legstable and #legstable > 0 then
        helpers.logInfoTS("WARP: Content of Legs Table:")
        for i, waypoint in ipairs(legstable) do
            helpers.logInfoTS(string.format("WARP: Waypoint %d: %s (Lat: %.4f, Lon: %.4f), Distance to: %.2f NM, T.Heading: %.2f, M.Heading: %.2f", i, waypoint.name, waypoint.latitude, waypoint.longitude, waypoint.distance_to_next, waypoint.true_course, waypoint.magnetic_course))
        end
    else
        helpers.logInfoTS("WARP: Legs table empty")
        return false
    end

    helpers.logInfoTS("WARP: Aircraft Lat Pos " .. get(P.aircraftlatpos))
    helpers.logInfoTS("WARP: Aircraft Lon Pos " .. get(P.aircraftlonpos))
    helpers.logInfoTS("WARP: Distance to TOD " .. get(P.vnavtoddist))

    local warppoint = helpers.getpointonroute(legstable, get(P.aircraftlatpos), get(P.aircraftlonpos), get(P.vnavtoddist))

    helpers.logInfoTS("WARP: Latitude " .. warppoint.latitude)
    helpers.logInfoTS("WARP: Longitude " .. warppoint.longitude)
    helpers.logInfoTS("WARP: True Course " .. warppoint.truecourse)
    helpers.logInfoTS("WARP: Magnetic Course " .. warppoint.magneticcourse)
    helpers.logInfoTS("WARP: Next Waypoint " .. warppoint.nextwaypointname)
    helpers.logInfoTS("WARP: Remaining Distance " .. warppoint.remainingdistance)

    local localpositionx, localpositiony, localpositionz = sasl.worldToLocal(warppoint.latitude, warppoint.longitude, get(P.cabincruisealt) / def.FEETTOMETER)

    helpers.logInfoTS("WARP: Local Position X " .. localpositionx)
    helpers.logInfoTS("WARP: Local Position Y " .. localpositiony)
    helpers.logInfoTS("WARP: Local Position Z " .. localpositionz)

    local distToTod = (get(P.vnavtoddist) or 0) - 10
    local fmsPhase = get(P.fmsflightphase) or 0
    local ffPhase = 1
    if fmsPhase == def.FMSFLIGHTPHASE_TAKEOFF or fmsPhase == def.FMSFLIGHTPHASE_CLIMB or fmsPhase == def.FMSFLIGHTPHASE_CRZ_CLB then
        ffPhase = 0
    elseif fmsPhase == def.FMSFLIGHTPHASE_DESCENT or fmsPhase == def.FMSFLIGHTPHASE_APPROACH or fmsPhase == def.FMSFLIGHTPHASE_CRZ_DES then
        ffPhase = 2
    end
    local fuel_flow_lbs_hr = nil
    do
        local ff1 = get(P.fuel_flow_kg_sec_1) or 0
        local ff2 = get(P.fuel_flow_kg_sec_2) or 0
        local total_kg_sec = ff1 + ff2
        if total_kg_sec > 0 then
            fuel_flow_lbs_hr = total_kg_sec * def.KGTOLBS * 3600
        end
    end
    local tas_kt = get(P.tas_kts)
    if P.tas_kts_is_ms and type(tas_kt) == "number" then
        tas_kt = tas_kt * 1.94384449
    end
    local fuel_opts = {
        phase = ffPhase,
        alt_ft = get(P.altitude_ft) or get(P.altitude),
        ias_kt = get(P.ias_kts),
        tas_kt = tas_kt,
        gs_kt = get(P.groundspeed)
    }
    if fuel_flow_lbs_hr and fuel_flow_lbs_hr > 0 then
        fuel_opts.fuel_flow_lbs_hr = fuel_flow_lbs_hr
    end
    local remainingfuel = helpers.estimatefuelattod(
        get(P.lefttanklbs),
        get(P.righttanklbs),
        get(P.centertanklbs),
        distToTod,
        fuel_opts
    )

    helpers.logInfoTS("WARP: Remaining Fuel Left " .. remainingfuel.left)
    helpers.logInfoTS("WARP: Remaining Fuel Right " .. remainingfuel.right)
    helpers.logInfoTS("WARP: Remaining Fuel Center " .. remainingfuel.center)
    helpers.logInfoTS("WARP: Remaining Fuel Total" .. remainingfuel.total)

end

function P.timewarptotod_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.timewarptotod()
    end
    return 0
end

local my_command_timewarptotod = sasl.createCommand(def.APPNAMEPREFIX .. "/timewarptotod", "Time Warp to TOD")
sasl.registerCommandHandler(my_command_timewarptotod, 0, P.timewarptotod_)

--------------------------------------------------------------------------------------------------------------
function P.toggleautofunctions()

    local newValue = def.ON
    if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) then
        newValue = def.OFF
    end
    P.configvalues[def.CONFIGAUTOFUNCTIONS] = newValue
    if settings and settings.appSettings then
        settings.appSettings[def.CONFIGAUTOFUNCTIONS] = newValue
        if settings.writeSettings then
            settings.writeSettings(settings.appSettings)
        end
    end
    if newValue == def.ON then
        P.commandtableentry(def.TEXT, "Auto Functions On")
    else
        P.commandtableentry(def.TEXT, "Auto Functions Off")
    end

    return true

end

function P.toggleautofunctions_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggleautofunctions()
    end
    return 0
end

local my_command_toggleautofunctions = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleautofunctions", "Toggle Auto Functions")
sasl.registerCommandHandler(my_command_toggleautofunctions, 0, P.toggleautofunctions_)

--------------------------------------------------------------------------------------------------------------
function P.toggleviewchanges()

    local newValue = def.ON
    if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
        newValue = def.OFF
    end
    P.configvalues[def.CONFIGVIEWCHANGES] = newValue
    if settings and settings.appSettings then
        settings.appSettings[def.CONFIGVIEWCHANGES] = newValue
        if settings.writeSettings then
            settings.writeSettings(settings.appSettings)
        end
    end
    if newValue == def.ON then
        P.commandtableentry(def.TEXT, "View Changes On")
    else
        P.commandtableentry(def.TEXT, "View Changes Off")
    end

    return true

end

function P.toggleviewchanges_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggleviewchanges()
    end
    return 0
end

local my_command_toggleviewchanges = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleviewchanges", "Toggle View Changes")
sasl.registerCommandHandler(my_command_toggleviewchanges, 0, P.toggleviewchanges_)

--------------------------------------------------------------------------------------------------------------
function P.toggleadviceonly()

    local newValue = def.ON
    if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
        newValue = def.OFF
    end
    P.configvalues[def.CONFIGVOICEADVICEONLY] = newValue
    if settings and settings.appSettings then
        settings.appSettings[def.CONFIGVOICEADVICEONLY] = newValue
        if settings.writeSettings then
            settings.writeSettings(settings.appSettings)
        end
    end
    if newValue == def.ON then
        P.commandtableentry(def.TEXT, "Voice Advice Only On")
    else
        P.commandtableentry(def.TEXT, "Voice Advice Only Off")
    end

    return true

end

function P.toggleadviceonly_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggleadviceonly()
    end
    return 0
end

local my_command_toggleadviceonly = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleadviceonly", "Toggle Voice Advice Only")
sasl.registerCommandHandler(my_command_toggleadviceonly, 0, P.toggleadviceonly_)

--------------------------------------------------------------------------------------------------------------
function P.toggleautotaxiing()

    local newValue = def.ON
    if (P.configvalues[def.CONFIGAUTOTAXIING] == def.ON) then
        newValue = def.OFF
    end
    P.configvalues[def.CONFIGAUTOTAXIING] = newValue
    if settings and settings.appSettings then
        settings.appSettings[def.CONFIGAUTOTAXIING] = newValue
        if settings.writeSettings then
            settings.writeSettings(settings.appSettings)
        end
    end
    if newValue == def.ON then
        P.commandtableentry(def.TEXT, "Auto Taxiing On")
    else
        P.commandtableentry(def.TEXT, "Auto Taxiing Off")
    end

    return true

end

function P.toggleautotaxiing_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggleautotaxiing()
    end
    return 0
end

local my_command_toggleautotaxiing = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleautotaxiing", "Toggle Auto Taxiing")
sasl.registerCommandHandler(my_command_toggleautotaxiing, 0, P.toggleautotaxiing_)

--------------------------------------------------------------------------------------------------------------
function P.toggleautotaxipause()

    P.autotaxipause = not P.autotaxipause
    if P.autotaxipause then
        P.commandtableentry(def.TEXT, "Auto Taxi Pause On")
    else
        P.commandtableentry(def.TEXT, "Auto Taxi Pause Off")
    end

    return true

end

function P.toggleautotaxipause_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggleautotaxipause()
    end
    return 0
end

local my_command_toggleautotaxipause = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleautotaxipause", "Toggle Auto Taxi Pause")
sasl.registerCommandHandler(my_command_toggleautotaxipause, 0, P.toggleautotaxipause_)

--------------------------------------------------------------------------------------------------------------
function P.findMostRecentLoop()
    local mostRecentLoop = nil
    local latestTime = 0

    for i, loopObj in ipairs(P.loopStateTables) do
        if loopObj.lock ~= def.NOPROCEDURE and loopObj.lastActiveTime > latestTime then
            latestTime = loopObj.lastActiveTime
            mostRecentLoop = loopObj
        end
    end

    return mostRecentLoop
end

--------------------------------------------------------------------------------------------------------------
function P.abortprocedure()
    local loop = P.findMostRecentLoop()
    if loop then
        loop.procedureabort = true
        loop.procedureskipped = false
        loop.procedureskipstep = false
        loop.setonabort = false -- Explizit sicherstellen, dass sie wiederholbar bleibt
    end
    return true
end

function P.abortprocedure_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.abortprocedure()
    end
    return 0
end

local my_command_abortprocedure = sasl.createCommand(def.APPNAMEPREFIX .. "/abortprocedure", "Abort Procedure (Repeatable)")
sasl.registerCommandHandler(my_command_abortprocedure, 0, P.abortprocedure_)

--------------------------------------------------------------------------------------------------------------
function P.skipprocedure()
    local loop = P.findMostRecentLoop()
    if loop then
        loop.procedureabort = true
        loop.procedureskipped = true
        loop.setonabort = true -- Das Signal an die Engine, .set = true zu setzen
        loop.procedureskipstep = false
    end
    return true
end

function P.skipprocedure_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.skipprocedure()
    end
    return 0
end

local my_command_skipprocedure = sasl.createCommand(def.APPNAMEPREFIX .. "/skipprocedure", "Skip Procedure (Mark as Done)")
sasl.registerCommandHandler(my_command_skipprocedure, 0, P.skipprocedure_)

--------------------------------------------------------------------------------------------------------------
function P.skipprocedurestep()
    local loop = P.findMostRecentLoop()
    if loop then
        loop.procedureskipstep = true
        loop.procedureabort = false
    end
    return true
end

function P.skipprocedurestep_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.skipprocedurestep()
    end
    return 0
end

local my_command_skipprocedurestep = sasl.createCommand(def.APPNAMEPREFIX .. "/skipprocedurestep", "Skip Procedure Step")
sasl.registerCommandHandler(my_command_skipprocedurestep, 0, P.skipprocedurestep_)

--------------------------------------------------------------------------------------------------------------
function P.stepprocedureonce()
    local loop = P.findMostRecentLoop()
    if not loop then
        P.commandtableentry(def.TEXT, "No active procedure")
        return false
    end
    if P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON then
        P.commandtableentry(def.TEXT, "Step Once works in Voice Advice Only mode")
        return false
    end
    if not loop.currentStepName or loop.currentStepName == "" then
        P.commandtableentry(def.TEXT, "No active procedure step")
        return false
    end

    loop.stepOnceRequested = true
    loop.stepOnceTargetStep = loop.currentStepName
    helpers.logInfoTS("Step Once armed for step '" .. tostring(loop.currentStepName) .. "'")
    P.commandtableentry(def.TEXT, "Step Once armed")
    return true
end

function P.stepprocedureonce_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.stepprocedureonce()
    end
    return 0
end

local my_command_stepprocedureonce = sasl.createCommand(def.APPNAMEPREFIX .. "/step_once", "Execute Current Procedure Step Once")
sasl.registerCommandHandler(my_command_stepprocedureonce, 0, P.stepprocedureonce_)

--------------------------------------------------------------------------------------------------------------
function P.toggletrimpopup()
    local contextActive, trimTarget = isTrimPopupManualContextActive()

    if P._trimAdvicePopupPinned then
        P._trimAdvicePopupPinned = false
        if (P.configvalues[def.CONFIGTRIMADVICEPOPUP] == def.ON)
            and (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)
            and contextActive and trimTarget and trimTarget > 0 then
            setTrimAdvicePopupState(trimTarget, false)
        else
            clearTrimAdvicePopupState()
        end
        P.commandtableentry(def.TEXT, "Trim Window Off")
        return true
    end

    if not contextActive then
        P.commandtableentry(def.TEXT, "Trim Window unavailable")
        return true
    end

    P._trimAdvicePopupPinned = true
    requestTrimAdvicePopupOpen(trimTarget, true)
    P.commandtableentry(def.TEXT, "Trim Window On")
    return true
end

function P.toggletrimpopup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggletrimpopup()
    end
    return 0
end

local my_command_toggletrimpopup = sasl.createCommand(def.APPNAMEPREFIX .. "/toggletrimpopup", "Toggle Trim Advice Window")
sasl.registerCommandHandler(my_command_toggletrimpopup, 0, P.toggletrimpopup_)

--------------------------------------------------------------------------------------------------------------
local QNH_HYSTERESIS_HPA = 0.3

local function stabilize_qnh_hpa(raw_hpa, last_hpa)
    local raw = tonumber(raw_hpa)
    if not raw then
        return last_hpa
    end
    local rounded = helpers.roundnumber(raw, 0)
    if last_hpa == nil then
        return rounded
    end
    if math.abs(rounded - last_hpa) >= 2 then
        return rounded
    end
    if raw >= (last_hpa + 0.5 + QNH_HYSTERESIS_HPA) then
        return last_hpa + 1
    end
    if raw <= (last_hpa - 0.5 - QNH_HYSTERESIS_HPA) then
        return last_hpa - 1
    end
    return last_hpa
end

function P.getlocalqnh(deparr)

    local region_pas = get(P.baroregionpas)
    local localqnhraw = region_pas and (region_pas / 100) or nil

    local metar_altim_in_hpa_val = nil
    local qnh_source = "region"

    if (deparr == def.DEPARTURE) then
        local depIcaoNow = string.upper(helpers.cleanstring(get(P.depicao) or ""))
        local depIcaoOk = helpers.isvalidicao(depIcaoNow)
        if depIcaoOk
            and P.depmetar and P.depmetar.metarfound
            and P.depmetar.icaocode
            and string.upper(P.depmetar.icaocode) == depIcaoNow
            and P.depmetar.decodedmetar and P.depmetar.decodedmetar.pressure and P.depmetar.decodedmetar.pressure.qnh_hpa then
            metar_altim_in_hpa_val = tonumber(P.depmetar.decodedmetar.pressure.qnh_hpa)
            qnh_source = "depmetar"
        end
        if metar_altim_in_hpa_val == nil then
            local nearestIcao = helpers.extractprimaryicao(get(P.nearesticao) or "")
            if helpers.isvalidicao(nearestIcao)
                and P.nearmetar and P.nearmetar.metarfound
                and P.nearmetar.icaocode
                and string.upper(P.nearmetar.icaocode) == nearestIcao
                and P.nearmetar.decodedmetar and P.nearmetar.decodedmetar.pressure and P.nearmetar.decodedmetar.pressure.qnh_hpa then
                metar_altim_in_hpa_val = tonumber(P.nearmetar.decodedmetar.pressure.qnh_hpa)
                qnh_source = "nearestmetar"
            end
        end
    elseif (deparr == def.ARRIVAL) then
        if P.desmetar.metarfound and P.desmetar.decodedmetar and P.desmetar.decodedmetar.pressure and P.desmetar.decodedmetar.pressure.qnh_hpa then
            metar_altim_in_hpa_val = tonumber(P.desmetar.decodedmetar.pressure.qnh_hpa)
            qnh_source = "desmetar"
        end
    end

    if metar_altim_in_hpa_val ~= nil then
        localqnhraw = metar_altim_in_hpa_val
    end

    local localqnhpas = nil
    if (deparr == def.DEPARTURE) then
        P.lastQnhHpaDep = stabilize_qnh_hpa(localqnhraw, P.lastQnhHpaDep)
        localqnhpas = P.lastQnhHpaDep
    elseif (deparr == def.ARRIVAL) then
        P.lastQnhHpaArr = stabilize_qnh_hpa(localqnhraw, P.lastQnhHpaArr)
        localqnhpas = P.lastQnhHpaArr
    else
        localqnhpas = helpers.roundnumber(localqnhraw or 0, 0)
    end

    local localqnhinch = localqnhpas and helpers.convertpressure(localqnhpas) or nil

    if deparr == def.DEPARTURE then
        if P.lastQnhSourceDep ~= qnh_source then
            P.lastQnhSourceDep = qnh_source
            helpers.logInfoTS("QNH source DEP: " .. tostring(qnh_source))
        end
    elseif deparr == def.ARRIVAL then
        if P.lastQnhSourceArr ~= qnh_source then
            P.lastQnhSourceArr = qnh_source
            helpers.logInfoTS("QNH source ARR: " .. tostring(qnh_source))
        end
    end

    sasl.logDebug("GETLOCALQNH: INCH " .. tostring(localqnhinch) .. " PAS " .. tostring(localqnhpas))

    return localqnhinch, localqnhpas
end

--------------------------------------------------------------------------------------------------------------

function P.mastercaution()

    helpers.command_once("laminar/B738/push_button/master_caution1")
    helpers.command_once("laminar/B738/button/fmc1_clr")
    helpers.command_once("laminar/B738/button/fmc2_clr")
    helpers.command_once("laminar/B738/alert/alt_horn_cutout")
    helpers.command_once("laminar/B738/push_button/ap_light_pilot")
    helpers.command_once("laminar/B738/push_button/at_light_pilot")
    helpers.command_once("laminar/B738/push_button/fms_light_pilot")

end

function P.mastercaution_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.mastercaution()
    end
    return 0
end

local my_command_mastercaution = sasl.createCommand(def.APPNAMEPREFIX .. "/mastercaution", "Master Caution + FMS CLR")
sasl.registerCommandHandler(my_command_mastercaution, 0, P.mastercaution_)


--------------------------------------------------------------------------------------------------------------

function P.speakdesmetar()

    if P.desmetar.metarfound then
            P.commandtableentry(def.TEXT, helpers.formatMetarSpeechSummary(P.desmetar, get(P.desrwy)))
        else
            P.commandtableentry(def.TEXT, "No Metar found for " .. helpers.spellNato(get(P.desicao)))
    end

    return true
end

function P.speakdesmetar_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.speakdesmetar()
    end
    return 0
end

local my_command_speakdesmetar = sasl.createCommand(def.APPNAMEPREFIX .. "/speakdesmetar", "Speak Destination Metar")
sasl.registerCommandHandler(my_command_speakdesmetar, 0, P.speakdesmetar_)

--------------------------------------------------------------------------------------------------------------
function P.speakdepmetar()

    if P.depmetar.metarfound then
            P.commandtableentry(def.TEXT, helpers.formatMetarSpeechSummary(P.depmetar,get(P.deprwy)))
        else
            P.commandtableentry(def.TEXT, "No Metar found for " .. helpers.spellNato(get(P.depicao)))
    end

    return true
end

function P.speakdepmetar_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.speakdepmetar()
    end
    return 0
end

local my_command_speakdepmetar = sasl.createCommand(def.APPNAMEPREFIX .. "/speakdepmetar", "Speak Departure Metar")
sasl.registerCommandHandler(my_command_speakdepmetar, 0, P.speakdepmetar_)


--------------------------------------------------------------------------------------------------------------
function P.canTriggerProcedureForCycle(procedureKey)
    local procedureData = P.proceduretable[procedureKey]
    if not procedureData then
        return false
    end

    local requiredState = procedureData.requiredFlightstate
    if requiredState then
        local currentState = P.flightstate
        local isStateAllowed = false
        if type(requiredState) == "table" then
            for _, allowed in ipairs(requiredState) do
                if currentState == allowed then
                    isStateAllowed = true
                    break
                end
            end
        else
            isStateAllowed = (currentState == requiredState)
        end
        if not isStateAllowed then
            sasl.logDebug("cycleprocedures: skipping '" .. procedureData.name .. "' due to flight state mismatch.")
            return false
        end
    end

    local aircraftIsOnGround = (get(P.airgroundsensor) == def.ON)
    local allowedState = procedureData.allowedState
    if allowedState == def.GROUNDONLY and not aircraftIsOnGround then
        sasl.logDebug("cycleprocedures: skipping '" .. procedureData.name .. "' because aircraft is not on ground.")
        return false
    end
    if allowedState == def.AIRONLY and aircraftIsOnGround then
        sasl.logDebug("cycleprocedures: skipping '" .. procedureData.name .. "' because aircraft is on ground.")
        return false
    end

    local prerequisite = procedureData.prerequisite
    if prerequisite then
        local prerequisiteMet = false
        if type(prerequisite) == "function" then
            prerequisiteMet = prerequisite()
        elseif type(prerequisite) == "number" and P.proceduretable[prerequisite] then
            prerequisiteMet = P.proceduretable[prerequisite].set
        end
        if not prerequisiteMet then
            sasl.logDebug("cycleprocedures: skipping '" .. procedureData.name .. "' due to unmet prerequisite.")
            return false
        end
    end

    if procedureData.prerequisiteChecks then
        local prereqContext = { triggeredmanually = true }
        for i, prereq in ipairs(procedureData.prerequisiteChecks) do
            if not prereq.check(prereqContext) then
                sasl.logDebug("cycleprocedures: skipping '" .. procedureData.name .. "' due to prerequisite check #" .. i .. ".")
                return false
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.triggerprocedure(procedureKey, isManual)
    isManual = isManual or false -- Standardwert, falls isManual nicht übergeben wird

    local procedureData = P.proceduretable[procedureKey]
    if not procedureData then
        sasl.logDebug("Trigger failed. Procedure data not found for key: " .. tostring(procedureKey))
        return false -- Prozedur nicht gefunden
    end

    -- ### 1. FLIGHT STATE CHECK ###
    local requiredState = procedureData.requiredFlightstate
    if requiredState then
        local currentState = P.flightstate
        local isStateAllowed = false
        if type(requiredState) == "table" then -- Wenn mehrere States erlaubt sind
            for _, allowed in ipairs(requiredState) do
                if currentState == allowed then
                    isStateAllowed = true
                    break
                end
            end
        else -- Nur ein State erlaubt
            isStateAllowed = (currentState == requiredState)
        end

        if not isStateAllowed then
            if isManual then
                P.commandtableentry(def.TEXT, procedureData.name .. " Procedure not possible in current flight state.")
            end
            sasl.logDebug("Trigger failed for '" .. procedureData.name .. "'. Required state: " .. helpers.tableToStringOrValue(requiredState) .. ", Current state: " .. currentState)
            return false -- Falscher Flight State
        end
    end

    -- ### 2. AIRCRAFT STATE CHECK (GROUND/AIR) ###
    local aircraftIsOnGround = (get(P.airgroundsensor) == def.ON)
    local allowedState = procedureData.allowedState
    if allowedState then
        if allowedState == def.GROUNDONLY and not aircraftIsOnGround then
            if isManual then
                P.commandtableentry(def.TEXT, procedureData.name .. " Procedure can only be executed on the ground.")
            end
            sasl.logDebug("Trigger failed for '" .. procedureData.name .. "'. Requires GROUNDONLY, but aircraft is in air.")
            return false
        elseif allowedState == def.AIRONLY and aircraftIsOnGround then
            if isManual then
                P.commandtableentry(def.TEXT, procedureData.name .. " Procedure can only be executed in the air.")
            end
            sasl.logDebug("Trigger failed for '" .. procedureData.name .. "'. Requires AIRONLY, but aircraft is on ground.")
            return false
        end
    end

    -- ### 3. PREREQUISITE CHECK (VORHERIGE PROZEDUR ERLEDIGT?) ###
    local prerequisite = procedureData.prerequisite
    if prerequisite then
        local prerequisiteMet = false

        if type(prerequisite) == "function" then
            prerequisiteMet = prerequisite() -- Funktion direkt aufrufen
            sasl.logDebug("Checking functional prerequisite for '" .. procedureData.name .. "'. Result: " .. tostring(prerequisiteMet))
        elseif type(prerequisite) == "number" and P.proceduretable[prerequisite] then
            prerequisiteMet = P.proceduretable[prerequisite].set
            sasl.logDebug("Checking prerequisite procedure ID " .. prerequisite .. " for '" .. procedureData.name .. "'. Result: " .. tostring(prerequisiteMet))
        else
             sasl.logWarning("Invalid prerequisite type (" .. type(prerequisite) .. ") for '" .. procedureData.name .. "'")
        end

        if not prerequisiteMet then
            if isManual then
                local prereqName = "Requirement"
                if type(prerequisite) == "number" and P.proceduretable[prerequisite] then
                    prereqName = P.proceduretable[prerequisite].name .. " procedure"
                end
                P.commandtableentry(def.TEXT, procedureData.name .. " Procedure: Prerequisite (" .. prereqName .. ") not met.")
            end
            sasl.logDebug("Trigger failed for '" .. procedureData.name .. "'. Prerequisite not met.")
            return false
        end
    end

    -- ### 4. BEREITS ERLEDIGT? (Nur relevant für Auto-Trigger) ###
    if not isManual and procedureData.set then
        if procedureData.repeatable then
            -- Wenn wiederholbar, Status zurücksetzen und weitermachen
            helpers.logInfoTS("'" .. procedureData.name .. "' is repeatable. Resetting .set flag to run again.")
            procedureData.set = false
            set(P.ProcSetStatusarraydr, 0, procedureKey) -- 0 für false
            -- Nicht 'return true', damit der Trigger-Vorgang unten fortgesetzt wird
        else
            -- Wenn nicht wiederholbar, Überspringen wie bisher
            sasl.logDebug("Auto-trigger skipped for '" .. procedureData.name .. "'. Already set as complete and not repeatable.")
            return true -- Nicht fehlschlagen, nur nicht erneut triggern
        end
    end

    -- ### 5. ZIEL-LOOP FINDEN UND PRÜFEN ###
    local loopIndex = procedureData.loop
    if not loopIndex or not P.loopStateTables[loopIndex] then
         sasl.logDebug("Procedure '" .. procedureData.name .. "' has invalid or missing loop index: " .. tostring(loopIndex))
         return false
    end
    local targetLoopObject = P.loopStateTables[loopIndex] -- Direkte Referenz

    -- ### 6. LOOP SPERREN UND ZUSTAND ZURÜCKSETZEN ###
    sasl.logDebug("triggerprocedure: Checking lock for loop " .. loopIndex .. ". Current lock ID: " .. tostring(targetLoopObject.lock) .. " (NOPROC = "..tostring(def.NOPROCEDURE)..")")

    if targetLoopObject.lock == def.NOPROCEDURE then
        helpers.logInfoTS("triggerprocedure: Loop " .. loopIndex .. " IS free. Attempting to lock with ProcID: " .. procedureKey .. " ('" .. procedureData.name .. "').")

        sasl.logDebug("triggerprocedure: Loop " .. loopIndex .. " lock supposedly set to: " .. tostring(procedureKey))

        targetLoopObject.lock = procedureKey
        P.resetLoopState(targetLoopObject)
        targetLoopObject.triggeredmanually = isManual
        targetLoopObject.triggeredat = os.time()

        sasl.logDebug("Loop " .. loopIndex .. " state explicitly reset upon trigger.")

        P.saveLoopState(targetLoopObject, loopIndex)
        sasl.logDebug("Saved initial triggered state for loop " .. loopIndex .. " (Lock=" .. targetLoopObject.lock .. ", State=" .. targetLoopObject.stepindex .. ")")

        return true -- Erfolgreich getriggert
    else
        -- Loop ist bereits beschäftigt
        -- *** ADD DETAILED LOGGING INSIDE ELSE ***
        local currentLockingProcKey = targetLoopObject.lock -- Get the ID of the locking procedure
        local currentProcName = (P.proceduretable[currentLockingProcKey] and P.proceduretable[currentLockingProcKey].name) or currentLockingProcKey -- Get its name safely

        if currentLockingProcKey ~= procedureKey then
            helpers.logInfoTS("triggerprocedure: Loop " .. loopIndex .. " IS NOT free. Current lock: '" .. tostring(currentProcName) .. "' (ID: " .. tostring(currentLockingProcKey) .. "). Cannot trigger '" .. procedureData.name .. "'.")
        else
            -- Optional: Debug-Log, wenn der Trigger dieselbe Prozedur erneut aufruft
            sasl.logDebug("triggerprocedure: Loop " .. loopIndex .. " is already running the requested procedure ('" .. procedureData.name .. "'). Trigger ignored.")
        end

        if isManual then
             P.commandtableentry(def.TEXT, "Cannot start " .. procedureData.name .. ". Loop " .. loopIndex .. " is busy with " .. tostring(currentProcName) .. ".")
        end
        -- helpers.logInfoTS Zeile war schon da, ist jetzt redundant wegen obigem Log
        return false -- Loop besetzt
    end -- Ende if targetLoopObject.lock == def.NOPROCEDURE / else
end -- Ende function P.triggerprocedure

--------------------------------------------------------------------------------------------------------------
function P.cycleprocedures()
    if ((P.procedureloop1.lock ~= def.NOPROCEDURE) or (P.procedureloop2.lock ~= def.NOPROCEDURE) or (P.procedureloop3.lock ~= def.NOPROCEDURE)) then
        return true
    end

    helpers.logInfoTS("cycleprocedures: command triggered")

    local proceduresToSort = {}
    for key, value in pairs(P.proceduretable) do
        table.insert(proceduresToSort, { originalKey = key, data = value })
    end
    table.sort(proceduresToSort, function(a, b)
        return a.data.number < b.data.number
    end)

    local firstCompletedIndex = nil
    for i, p in ipairs(proceduresToSort) do
        if p.data.cycable and p.data.set then
            firstCompletedIndex = i
            break
        end
    end
    if firstCompletedIndex then
        for i = 1, firstCompletedIndex - 1 do
            local procedureToUpdate = proceduresToSort[i]
            if procedureToUpdate.data.cycable and not procedureToUpdate.data.set then
                procedureToUpdate.data.set = true
            end
        end
    end

    for _, procedure in ipairs(proceduresToSort) do
        if procedure.data.cycable then
            local skipFunc = procedure.data.skipCondition
            local shouldSkip = false
            if skipFunc then
                shouldSkip = skipFunc()
                if shouldSkip then
                    if not procedure.data.__skipApplied then
                        procedure.data.set = true
                        procedure.data.__skipApplied = true
                        if P.ProcSetStatusarraydr then
                            set(P.ProcSetStatusarraydr, 1, procedure.originalKey)
                        end
                    end
                else
                    if procedure.data.__skipApplied then
                        procedure.data.__skipApplied = nil
                        procedure.data.set = false
                        if P.ProcSetStatusarraydr then
                            set(P.ProcSetStatusarraydr, 0, procedure.originalKey)
                        end
                    end
                end
            end

            if not shouldSkip and not procedure.data.set then
                if P.canTriggerProcedureForCycle(procedure.originalKey) then
                    helpers.logInfoTS("Next Procedure is: " .. procedure.data.name)
                    return P.triggerprocedure(procedure.originalKey, def.TRIGGEREDMANUALLY)
                end
            elseif shouldSkip then
                helpers.logInfoTS("Skipping " .. procedure.data.name .. " Procedure as its skip condition is met.")
            end
        end
    end

    helpers.logInfoTS("All cycable procedures completed")
    return true
end

function P.cycleprocedures_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.cycleprocedures()
    end
    return 0
end

local my_command_cycleprocedures = sasl.createCommand(def.APPNAMEPREFIX .. "/cycleprocedures", "Cycle Through Procedures")
sasl.registerCommandHandler(my_command_cycleprocedures, 0, P.cycleprocedures_)

--------------------------------------------------------------------------------------------------------------
function P.refuelAircraft(totalFuelLbs)

    if type(totalFuelLbs) ~= "number" or totalFuelLbs < 0 then
        P.commandtableentry(def.TEXT, "Fuel load failed: invalid amount.")
        return false
    end

    local currentLeftLbs = get(P.lefttanklbs)
    local currentRightLbs = get(P.righttanklbs)
    local currentCenterLbs = get(P.centertanklbs)
    local currentTotalFuel = currentLeftLbs + currentRightLbs + currentCenterLbs

    local capacityFactor = helpers.getFuelCapacityFactor(get(P.fueltemp))
    local maxWing = def.MAXWINGTANKLBS * capacityFactor
    local maxCenter = def.MAXCENTERTANKLBS * capacityFactor
    local maxTotal = maxCenter + (2 * maxWing)

    if totalFuelLbs > maxTotal then
        P.commandtableentry(def.TEXT, "Fuel request above max, loading maximum.")
        totalFuelLbs = maxTotal
    end

    local leftTank, rightTank, centerTank
    local isDefuel = (totalFuelLbs < currentTotalFuel)

    if totalFuelLbs <= (maxWing * 2) then
        leftTank = totalFuelLbs / 2
        rightTank = totalFuelLbs / 2
        centerTank = 0
    else
        leftTank = maxWing
        rightTank = maxWing
        centerTank = totalFuelLbs - (maxWing * 2)
    end

    if isDefuel and currentCenterLbs > 1000 and centerTank < 1000 then
        local deficit = 1000 - centerTank
        centerTank = 1000
        leftTank = leftTank - (deficit / 2)
        rightTank = rightTank - (deficit / 2)
    end

    set(P.fueltank1, leftTank * def.LBSTOKG)
    set(P.fueltank2, centerTank * def.LBSTOKG)
    set(P.fueltank3, rightTank * def.LBSTOKG)

    local totalSetFuelLbs = helpers.roundnumber(leftTank + rightTank + centerTank)
    local actionText = isDefuel and "Defuel" or "Refuel"

    local fuelForDisplay
    local unitForDisplay

    if (get(P.fuelunit) == def.KG) then
        fuelForDisplay = helpers.roundnumber(totalSetFuelLbs * def.LBSTOKG)
        unitForDisplay = "K G"
    else
        fuelForDisplay = totalSetFuelLbs
        unitForDisplay = "L B S"
    end

    P.commandtableentry(def.TEXT, actionText .. " complete. Total fuel " .. fuelForDisplay .. " " .. unitForDisplay .. ".")


    return true
end

--------------------------------------------------------------------------------------------------------------
function P.aircraftonrwy(runwayType, distMeters, headingLimit)

    headingLimit = headingLimit or 20 -- Standard-Limit von 20 Grad
    -- distMeters is a lateral distance from runway centerline in meters.
    local dist_m = tonumber(distMeters) or 0
    local dist_rad = dist_m / 6371000

    local aircraftlat = get(P.aircraftlatpos)
    local aircraftlon = get(P.aircraftlonpos)

    local rwystartlat, rwystartlon, rwyendlat, rwyendlon
    local runwayHeading

    if runwayType == def.DEPARTURE then
        rwystartlat = get(P.deprwylatstartpos)
        rwystartlon = get(P.deprwylonstartpos)
        rwyendlat = get(P.deprwylatendpos)
        rwyendlon = get(P.deprwylonendpos)
        runwayHeading = get(P.deprwyheading)
    elseif runwayType == def.ARRIVAL then
        rwystartlat = P.desrwylatstartpostemp
        rwystartlon = P.desrwylonstartpostemp
        rwyendlat = P.desrwylatendpostemp
        rwyendlon = P.desrwylonendpostemp
        runwayHeading = P.desrwyheadingtemp
    else
        return false
    end

    if (rwystartlat == 0) then
        if runwayType == def.DEPARTURE then return false end
        if runwayType == def.ARRIVAL then return true end
        return true
    end

    if (rwystartlat == nil) or (rwystartlon == nil) or (rwyendlat == nil) or (rwyendlon == nil) then
        if runwayType == def.DEPARTURE then return false end
        if runwayType == def.ARRIVAL then return false end
        return false
    end
    if (aircraftlat == nil) or (aircraftlon == nil) then
        return false
    end

    local rwystartlatrad = math.rad(rwystartlat)
    local rwystartlonrad = math.rad(rwystartlon)
    local rwyendlatrad = math.rad(rwyendlat)
    local rwyendlonrad = math.rad(rwyendlon)
    local aircraftlatrad = math.rad(aircraftlat)
    local aircraftlonrad = math.rad(aircraftlon)

    local v1 = (rwyendlonrad - rwystartlonrad) * math.cos(rwystartlatrad)
    local v2 = (rwyendlatrad - rwystartlatrad)
    local d1 = (aircraftlatrad - rwystartlatrad)
    local d2 = (aircraftlonrad - rwystartlonrad) * math.cos(rwystartlatrad)

    local v_mag_sq = v1*v1 + v2*v2
    if v_mag_sq == 0 then return false end

    local s = (d2 * v1 + d1 * v2) / v_mag_sq

    local disttorwy_sq

    if s < 0 then
        disttorwy_sq = d1*d1 + d2*d2
    elseif s > 1 then
        local d1_end = (aircraftlatrad - rwyendlatrad)
        local d2_end = (aircraftlonrad - rwyendlonrad) * math.cos(rwyendlatrad)
        disttorwy_sq = d1_end*d1_end + d2_end*d2_end
    else
        local nearest_x = v1 * s
        local nearest_y = v2 * s
        disttorwy_sq = (d1 - nearest_y)^2 + (d2 - nearest_x)^2
    end

    local isOnRunwayProximity = (disttorwy_sq < (dist_rad * dist_rad))

    local aircraftTrack = get(P.groundtrackmag)
    local headingDiff = helpers.headingdiff(aircraftTrack, runwayHeading)
    local isHeadingAligned = (headingDiff < headingLimit) -- True wenn < 20 Grad

    local result
    if runwayType == def.DEPARTURE then
        result = isOnRunwayProximity and isHeadingAligned
    elseif runwayType == def.ARRIVAL then
        result = (not isOnRunwayProximity) or (not isHeadingAligned)
    else
        result = isOnRunwayProximity
    end

    P._aircraftonrwy_state = P._aircraftonrwy_state or {}
    local key = (runwayType == def.DEPARTURE) and "dep" or ((runwayType == def.ARRIVAL) and "arr" or tostring(runwayType))
    if P._aircraftonrwy_state[key] ~= result then
        P._aircraftonrwy_state[key] = result
        local dist_m = math.sqrt(disttorwy_sq) * 6371000
        helpers.logInfoTS(
            string.format(
                "AircraftOnRwy: type=%s result=%s dist=%.1f hdgDiff=%.1f prox=%s aligned=%s",
                tostring(key),
                tostring(result),
                tonumber(dist_m or 0),
                tonumber(headingDiff or -1),
                tostring(isOnRunwayProximity),
                tostring(isHeadingAligned)
            )
        )
    end
    return result
end

--------------------------------------------------------------------------------------------------------------
function P.isArrivalRunwayRadioAltGateOpen(maxThresholdDistanceNm, maxHeadingDiff)

    local aircraftlat = get(P.aircraftlatpos)
    local aircraftlon = get(P.aircraftlonpos)
    local rwystartlat = P.desrwylatstartpostemp
    local rwystartlon = P.desrwylonstartpostemp
    local runwayHeading = P.desrwyheadingtemp

    if not aircraftlat or not aircraftlon or not rwystartlat or not rwystartlon then
        return false
    end
    if aircraftlat == 0 or aircraftlon == 0 or rwystartlat == 0 or rwystartlon == 0 then
        return false
    end

    local runwayDistanceNm = helpers.getdistance(aircraftlat, aircraftlon, rwystartlat, rwystartlon)
    if not runwayDistanceNm or runwayDistanceNm > maxThresholdDistanceNm then
        return false
    end

    if runwayHeading and runwayHeading ~= 0 then
        local aircraftTrack = get(P.groundtrackmag)
        if aircraftTrack and aircraftTrack ~= 0 then
            local headingDiff = helpers.headingdiff(aircraftTrack, runwayHeading)
            if headingDiff > maxHeadingDiff then
                return false
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.syncProceduresOnLoad()
    helpers.logInfoTS("SYNC: Resynchronizing procedure states with aircraft status...")

    for id, proc in pairs(P.proceduretable) do
        proc.set = false
    end

    -- Erstelle eine sortierte Liste der Prozeduren
    local orderedProcedures = {}
    for key, value in pairs(P.proceduretable) do
        table.insert(orderedProcedures, value)
    end
    table.sort(orderedProcedures, function(a, b)
        return a.number < b.number
    end)

    for _, proc in ipairs(orderedProcedures) do
        if proc and proc.skipCondition and proc.skipCondition() == true then
            proc.set = true
            helpers.logInfoTS("SYNC: Procedure '" .. proc.name .. "' skipped (condition met).")
        else
            if proc then
                helpers.logInfoTS("SYNC: Stopping sync at procedure '" .. proc.name .. "'.")
            end
            break
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function P.deleteCustomData(loopTable)
    local parts = {}
    for key, value in pairs(loopTable) do
        if not P.loopenginekeys[key] then
            loopTable[key] = nil
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function P.serializeCustomData(loopTable)
    local parts = {}
    sasl.logDebug("--- Serializing Custom Data ---")
    if P.loopenginekeys == nil then
        sasl.logDebug("!!! P.loopenginekeys is NIL during serialize!")
        return ""
    else
        sasl.logDebug("Engine Keys Ignored: " .. helpers.tableToStringOrValue(P.loopenginekeys))
    end

    for key, value in pairs(loopTable) do
        sasl.logDebug("... Checking key: '" .. tostring(key) .. "'")
        local shouldBeIgnored = P.loopenginekeys[key]
        sasl.logDebug("... Value of P.loopenginekeys['" .. tostring(key) .. "'] is: " .. tostring(shouldBeIgnored))
        -- *** END ADDED LOG ***
        if not P.loopenginekeys[key] and value ~= nil then
             sasl.logDebug("... >>> SAVING Key: '" .. tostring(key) .. "' as Custom Data")
            local valueType = type(value)
            if valueType == "number" then
                table.insert(parts, key .. ":n:" .. tostring(value))
            elseif valueType == "string" then
                value = string.gsub(value, ":", "%%COLON%%")
                value = string.gsub(value, "|", "%%PIPE%%")
                table.insert(parts, key .. ":s:" .. value)
            elseif valueType == "boolean" then
                table.insert(parts, key .. ":b:" .. (value and "1" or "0"))
            end
        end
    end

    if #parts > 0 then
        return table.concat(parts, "|")
    else
        return ""
    end
end

--------------------------------------------------------------------------------------------------------------
function P.deserializeCustomData(loopTable, dataString)
    if dataString == nil or dataString == "" then return end

    sasl.logDebug("Deserializing custom data: " .. dataString)
    for part in string.gmatch(dataString, "([^|]+)") do
        local key, valType, valueStr = string.match(part, "([^:]+):([nsb]):(.*)")

        if key then
            if valType == "n" then
                loopTable[key] = tonumber(valueStr)
            elseif valType == "s" then
                valueStr = string.gsub(valueStr, "%%COLON%%", ":")
                valueStr = string.gsub(valueStr, "%%PIPE%%", "|")
                loopTable[key] = valueStr
            elseif valType == "b" then
                loopTable[key] = (valueStr == "1")
            end
            sasl.logDebug("... Restored " .. key .. " (" .. valType .. ") = " .. tostring(loopTable[key]))
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function P.loadLoopState(loopIndex)
    local loopIdStr = "Loop " .. tostring(loopIndex)
    sasl.logDebug("Loading state for " .. loopIdStr)

    local loop = helpers.shallowcopy(P.procedurelooptemplate) -- Use helpers.shallowcopy if it's there too

    local handles = P.LoopHandles[loopIndex]
    loop.lock = get(handles.lock)
    loop.stepindex = get(handles.state)

    -- Read raw values
    local rawStepName = get(handles.stepname)
    local rawCustomData = get(handles.custom)

    -- *** USE helpers.forceCleanString HERE ***
    local cleanedStepName = helpers.forceCleanString(rawStepName)
    local cleanedCustomData = helpers.forceCleanString(rawCustomData)
    -- *** END CHANGE ***

    if cleanedStepName == def.STRINGDRNONEVALUE then
        loop.currentStepName = nil
    else
        loop.currentStepName = cleanedStepName
    end

    local customDataToDeserialize = "" -- Default to empty if placeholder
    if cleanedCustomData ~= def.STRINGDRNONEVALUE then
        customDataToDeserialize = cleanedCustomData -- Deserialize only if not placeholder
    end
    P.deserializeCustomData(loop, customDataToDeserialize)

    -- Cleanup
    if loop.lock == nil then loop.lock = def.NOPROCEDURE end
    if loop.stepindex == nil then loop.stepindex = 0 end
    -- The check for "" converting to nil is no longer needed here

    -- Validation Logic (includes Save on Reset & Post-Save Check)
    local stateWasCorrectedAndSaved = false
    if loop.lock ~= def.NOPROCEDURE then
        local procData = yal.proceduretable[loop.lock]
        local needsSave = false

        if not procData or not procData.steps then
            sasl.logWarning("" .. loopIdStr .. " - Loaded invalid lock ID " .. loop.lock .. ". Resetting.")
            loop.lock = def.NOPROCEDURE
            loop.stepindex = 0
            loop.currentStepName = nil
            P.deleteCustomData(loop)
            needsSave = true
        elseif loop.stepindex > 0 and loop.currentStepName == nil then
            sasl.logWarning("" .. loopIdStr .. " - Loaded running procedure " .. loop.lock .. " with no step name. Resetting.")
            loop.lock = def.NOPROCEDURE
            loop.stepindex = 0
            P.deleteCustomData(loop)
            needsSave = true
        elseif loop.stepindex > 0 and loop.currentStepName ~= nil then
            if not procData.steps[loop.currentStepName] then
                sasl.logWarning("" .. loopIdStr .. " - Loaded procedure " .. loop.lock .. " with invalid step name '" .. loop.currentStepName .. "'. Resetting.")
                loop.lock = def.NOPROCEDURE
                loop.stepindex = 0
                loop.currentStepName = nil
                P.deleteCustomData(loop)
                needsSave = true
            else
                 helpers.logInfoTS("" .. loopIdStr .. " - Successfully restored procedure " .. loop.lock .. " at step '" .. loop.currentStepName .. "'")
            end
        else
             sasl.logDebug("" .. loopIdStr .. " - Restored procedure " .. loop.lock .. " (pending prerequisites).")
        end

        if needsSave then
             P.saveLoopState(loop, loopIndex)
             stateWasCorrectedAndSaved = true
        end

    else -- loop.lock is 0
        local cleanTemplate = P.procedurelooptemplate
        local nameClean = helpers.forceCleanString(loop.currentStepName)
        if nameClean == "" or nameClean == "[NONE]" then
            loop.currentStepName = nil
            nameClean = ""
        end
        if loop.stepindex ~= cleanTemplate.stepindex or nameClean ~= "" then
             sasl.logWarning("" .. loopIdStr .. " - Loaded NOPROCEDURE lock but inconsistent state/stepname found and cleaned. Saving clean state.")
             loop.stepindex = cleanTemplate.stepindex
             loop.currentStepName = nil -- Explicitly set to nil
             P.deleteCustomData(loop)
             P.saveLoopState(loop, loopIndex)
             stateWasCorrectedAndSaved = true
        else
             sasl.logDebug("" .. loopIdStr .. " - Loaded state is not locked (NOPROCEDURE).")
        end
    end

    -- POST-SAVE CHECK (Uses helpers.forceCleanString for logging consistency)
    if stateWasCorrectedAndSaved then
        local postSaveLock = get(handles.lock)
        local postSaveState = get(handles.state)
        local postSaveNameRaw = get(handles.stepname)
        -- *** USE helpers.forceCleanString HERE ***
        local postSaveNameClean = helpers.forceCleanString(postSaveNameRaw)
        -- *** END CHANGE ***
        local postSaveNameLog = postSaveNameClean == "" and "''" or "'" .. postSaveNameClean .. "'"
        sasl.logDebug("!!! POST-SAVE CHECK (Loop " .. loopIndex .. "): Dataref values are NOW: Lock=" .. tostring(postSaveLock) .. ", State=" .. tostring(postSaveState) .. ", StepName=" .. postSaveNameLog)
    end

    sasl.logDebug("" .. loopIdStr .. " - FINAL state before return: Lock=" .. tostring(loop.lock) .. ", State(stepindex)=" .. tostring(loop.stepindex) .. ", StepName=" .. tostring(loop.currentStepName))
    return loop
end

--------------------------------------------------------------------------------------------------------------
function P.saveLoopState(loopTable, loopIndex)
    if not loopTable or not P.LoopHandles[loopIndex] then
        sasl.logDebug("saveLoopState called with invalid loopTable or loopIndex: " .. tostring(loopIndex))
        return
    end
    local handles = P.LoopHandles[loopIndex]

    -- Werte ermitteln
    local lockToSave = tonumber(loopTable.lock) or 0
    local stateToSave = tonumber(loopTable.stepindex) or 0

    -- *** ÄNDERUNG: Platzhalter für leere Strings ***
    local nameToSave = loopTable.currentStepName
    if nameToSave == nil or nameToSave == "" then
        nameToSave = def.STRINGDRNONEVALUE
    else
        nameToSave = tostring(nameToSave)
    end

    local customDataString = P.serializeCustomData(loopTable)
    local customToSave = customDataString
    if customToSave == nil or customToSave == "" then
        customToSave = def.STRINGDRNONEVALUE
    else
        customToSave = tostring(customToSave)
    end
    -- *** ENDE ÄNDERUNG ***

    if lockToSave == 0 then
         sasl.logDebug("!!! SAVING LOOP " .. loopIndex .. " with LOCK=0: State=" .. stateToSave .. ", StepName='" .. nameToSave .. "'")
    end

    local function safeSet(handle, value, desc)
        if not handle then
            sasl.logWarning("saveLoopState: missing handle for " .. tostring(desc) .. " (loop " .. tostring(loopIndex) .. ")")
            return
        end
        local ok, err = pcall(set, handle, value)
        if not ok then
            sasl.logWarning("saveLoopState: failed to set " .. tostring(desc) .. " with value '" .. tostring(value) .. "' (" .. tostring(err) .. ")")
        end
    end

    -- Speichere die 4 persistenten Werte
    safeSet(handles.lock, lockToSave, "lock")
    safeSet(handles.state, stateToSave, "state")
    safeSet(handles.stepname, nameToSave, "stepname")
    safeSet(handles.custom, customToSave, "custom")
end

--------------------------------------------------------------------------------------------------------------
function P.headingsync()

    set(P.mcpheading, helpers.roundnumber(get(P.groundtrackmag)))

end

function P.headingsync_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.headingsync()
    end
    return 0
end

local my_command_headingsync = sasl.createCommand(def.APPNAMEPREFIX .. "/headingsync", "Sync AP Heading with Ground Track")
sasl.registerCommandHandler(my_command_headingsync, 0, P.headingsync_)

--------------------------------------------------------------------------------------------------------------

function P.wipersup()

    helpers.command_once("laminar/B738/knob/left_wiper_up")
    helpers.command_once("laminar/B738/knob/right_wiper_up")

end

function P.wipersup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.wipersup()
    end
    return 0
end

local my_command_wipersup = sasl.createCommand(def.APPNAMEPREFIX .. "/wipersup", "Both Wipers Up")
sasl.registerCommandHandler(my_command_wipersup, 0, P.wipersup_)

--------------------------------------------------------------------------------------------------------------

function P.wipersdown()

    helpers.command_once("laminar/B738/knob/left_wiper_dn")
    helpers.command_once("laminar/B738/knob/right_wiper_dn")

end

function P.wipersdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.wipersdown()
    end
    return 0
end

local my_command_wipersdown = sasl.createCommand(def.APPNAMEPREFIX .. "/wipersdownn", "Both Wipers Down")
sasl.registerCommandHandler(my_command_wipersdown, 0, P.wipersdown_)

--------------------------------------------------------------------------------------------------------------

function P.toggletaxilights(state)

    if (state == nil) then
        if (get(P.taxilight) == def.OFF) then
            helpers.command_once("laminar/B738/toggle_switch/taxi_light_brigh_toggle")
        elseif (get(P.taxilight) == 2) then
            helpers.command_once("laminar/B738/toggle_switch/taxi_light_brigh_toggle")
        end
    elseif ((state == def.OFF) and (get(P.taxilight) ~= def.OFF)) then
        helpers.command_once("laminar/B738/toggle_switch/taxi_light_brigh_toggle")
    elseif ((state == def.ON) and (get(P.taxilight) == def.OFF)) then
        helpers.command_once("laminar/B738/toggle_switch/taxi_light_brigh_toggle")
    end

    return true

end

function P.toggletaxilights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggletaxilights(nil)
    end
    return 0
end

function P.getTaxiPushbackHint()
    if not P.taxiComponent or not P.taxiComponent.getPushbackHint then
        return nil
    end
    if P.taxiComponent.updateTaxiState then
        P.taxiComponent:updateTaxiState()
    end
    return P.taxiComponent:getPushbackHint()
end

function P.getTaxiPushbackDecision()
    if not P.taxiComponent or not P.taxiComponent.getPushbackDecision then
        return nil
    end
    if P.taxiComponent.updateTaxiState then
        P.taxiComponent:updateTaxiState()
    end
    return P.taxiComponent:getPushbackDecision()
end

function P.getTaxiPushbackDecisionState(requiredDiff, notRequiredDiff)
    local info = P.getTaxiPushbackDecision and P.getTaxiPushbackDecision() or nil
    local diff = info and (tonumber(info.diff) or tonumber(info.join_diff) or tonumber(info.route_diff))
    if not info or not diff then
        return nil, nil, info
    end
    local req = tonumber(requiredDiff) or 120
    local no = tonumber(notRequiredDiff) or 70
    local join_sector = info.join_sector
    local join_dist = tonumber(info.join_dist)
    local route_diff = tonumber(info.route_diff) or diff
    local join_diff = tonumber(info.join_diff) or diff
    local ramp_along = tonumber(info.ramp_link_along)
    local ramp_cross = tonumber(info.ramp_link_cross)
    if ramp_cross ~= nil then
        ramp_cross = math.abs(ramp_cross)
    end
    if info.requires_reverse == true then
        return "required", diff, info
    end
    if ramp_along ~= nil and ramp_cross ~= nil and ramp_along <= -8 and ramp_cross <= 35 then
        return "required", diff, info
    end
    if join_sector == "rear" and join_dist and join_dist > 6 and join_diff >= math.max(100, no + 20) then
        return "required", diff, info
    end
    if info.forward_roll_ok == true then
        if (join_sector == nil or join_sector == "front" or (join_sector == "side" and join_dist and join_dist <= 8))
            and route_diff <= math.max(no, 85) then
            return "not_required", diff, info
        end
    end
    if ramp_along ~= nil and ramp_cross ~= nil and ramp_along >= 0 and ramp_cross <= 20 and diff <= no then
        return "not_required", diff, info
    end
    if diff >= req then
        return "required", diff, info
    end
    if diff <= no and join_sector == "front" and (not join_dist or join_dist <= 25) then
        return "not_required", diff, info
    end
    return "unknown", diff, info
end

local my_command_toggletaxilights = sasl.createCommand(def.APPNAMEPREFIX .. "/toggletaxilights", "Toggle Taxi Lights")
sasl.registerCommandHandler(my_command_toggletaxilights, 0, P.toggletaxilights_)

--------------------------------------------------------------------------------------------------------------

function P.togglecollisionlights(state)

    if (state == nil) then
        if (get(P.beaconlights) == def.OFF) then
            set(P.beaconlights, def.ON)
        elseif (get(P.beaconlights) == def.ON) then
            set(P.beaconlights, def.OFF)
        end
    elseif ((state == def.OFF) and (get(P.beaconlights) ~= def.OFF)) then
        set(P.beaconlights, def.OFF)
    elseif ((state == def.ON) and (get(P.beaconlights) ~= def.ON)) then
        set(P.beaconlights, def.ON)
    end

end

function P.togglecollisionlights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglecollisionlights(nil)
    end
    return 0
end

local my_command_togglecollisionlights = sasl.createCommand(def.APPNAMEPREFIX .. "/togglecollisionlights", "Toggle Collision Lights")
sasl.registerCommandHandler(my_command_togglecollisionlights, 0, P.togglecollisionlights_)

--------------------------------------------------------------------------------------------------------------
function P.togglelandinglights(state)
    local ledVariant = (get(P.ledlightsvariant) == def.ON)
    local ledOffThreshold = def.LEDLLIGHTSOFF or 0

    if state == nil then
        local anyOn = false
        if ledVariant then
            anyOn = (get(P.llights1) > ledOffThreshold) or (get(P.llights4) > ledOffThreshold)
        else
            anyOn = (get(P.llights1) ~= def.OFF) or (get(P.llights2) ~= def.OFF) or
                    (get(P.llights3) ~= def.OFF) or (get(P.llights4) ~= def.OFF)
        end

        if anyOn then
            helpers.command_once("sim/lights/landing_lights_off")
        else
            helpers.command_once("sim/lights/landing_lights_on")
        end
    elseif state == def.OFF then
        helpers.command_once("sim/lights/landing_lights_off")
    elseif state == def.ON then
        helpers.command_once("sim/lights/landing_lights_on")
    end
end

function P.togglelandinglights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglelandinglights(nil)
    end
    return 0
end

local my_command_togglelandinglights = sasl.createCommand(def.APPNAMEPREFIX .. "/togglelandinglights", "Toggle Landing Lights")
sasl.registerCommandHandler(my_command_togglelandinglights, 0, P.togglelandinglights_)

--------------------------------------------------------------------------------------------------------------

function P.togglelogolight(state)

    if (state == nil) then
        if (get(P.logolighton) == def.OFF) then
            helpers.command_once("laminar/B738/switch/logo_light_on")
        else
            helpers.command_once("laminar/B738/switch/logo_light_off")
        end
    elseif ((state == def.OFF) and (get(P.logolighton) ~= def.OFF)) then
        helpers.command_once("laminar/B738/switch/logo_light_off")
    elseif ((state == def.ON) and (get(P.logolighton) ~= def.ON)) then
        helpers.command_once("laminar/B738/switch/logo_light_on")
    end

end

function P.togglelogolight_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglelogolight(nil)
    end
    return 0
end

local my_command_togglelogolight = sasl.createCommand(def.APPNAMEPREFIX .. "/togglelogolight", "Toggle Logo Light")
sasl.registerCommandHandler(my_command_togglelogolight, 0, P.togglelogolight_)

--------------------------------------------------------------------------------------------------------------
function P.togglerwylights(state)

    if (state == nil) then
        if (get(P.rwylightl) == def.ON) then
            set(P.rwylightl, def.OFF)
        else
            set(P.rwylightl, def.ON)
        end
        if (get(P.rwylightr) == def.ON) then
            set(P.rwylightr, def.OFF)
        else
            set(P.rwylightr, def.ON)
        end
    elseif (state == def.OFF) then
        if (get(P.rwylightl) == def.ON) then
            set(P.rwylightl, def.OFF)
        end
        if (get(P.rwylightr) == def.ON) then
            set(P.rwylightr, def.OFF)
        end
    elseif (state == def.ON) then
        if (get(P.rwylightl) == def.OFF) then
            set(P.rwylightl, def.ON)
        end
        if (get(P.rwylightr) == def.OFF) then
            set(P.rwylightr, def.ON)
        end
    end
end

function P.togglerwylights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglerwylights(nil)
    end
    return 0
end

local my_command_togglerwylights = sasl.createCommand(def.APPNAMEPREFIX .. "/togglerwylights", "Toggle Runway Turnoff Lights")
sasl.registerCommandHandler(my_command_togglerwylights, 0, P.togglerwylights_)

--------------------------------------------------------------------------------------------------------------
function P.togglepositionlights(state)

    if (state == nil) then
        if (get(P.positionlights) == def.POSLIGHTSSTEADY) then
            helpers.command_once("laminar/B738/toggle_switch/position_light_strobe")
        else
            helpers.command_once("laminar/B738/toggle_switch/position_light_steady")
        end
    elseif ((state == def.POSLIGHTSSTEADY) and (get(P.positionlights) ~= def.POSLIGHTSSTEADY)) then
        helpers.command_once("laminar/B738/toggle_switch/position_light_steady")
    elseif ((state == def.POSLIGHTSSTROBE) and (get(P.positionlights) ~= def.POSLIGHTSSTROBE)) then
        helpers.command_once("laminar/B738/toggle_switch/position_light_strobe")
    elseif ((state == def.POSLIGHTSOFF) and (get(P.positionlights) ~= def.POSLIGHTSOFF)) then
        helpers.command_once("laminar/B738/toggle_switch/position_light_off")
    end

end

function P.togglepositionlights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglepositionlights(nil)
    end
    return 0
end

local my_command_togglepositionlights = sasl.createCommand(def.APPNAMEPREFIX .. "/togglepositionlights", "Toggle Position Lights")
sasl.registerCommandHandler(my_command_togglepositionlights, 0, P.togglepositionlights_)

--------------------------------------------------------------------------------------------------------------
function P.toggletransponder(state)

    if (state == nil) then
        if (get(P.transponderpos) == def.STANDBY) then
            helpers.command_once("laminar/B738/knob/transponder_tara")
        else
            helpers.command_once("laminar/B738/knob/transponder_stby")
        end
    else
        if ((state == def.STANDBY) and (get(P.transponderpos) ~= def.STANDBY)) then
            helpers.command_once("laminar/B738/knob/transponder_stby")
        elseif ((state == def.TARA) and (get(P.transponderpos) ~= def.TARA)) then
            helpers.command_once("laminar/B738/knob/transponder_tara")
        else
        end
    end

end

function P.toggletransponder_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggletransponder(nil)
    end
    return 0
end

local my_command_toggletransponder = sasl.createCommand(def.APPNAMEPREFIX .. "/toggletransponder", "Toggle Transponder Stdby def.TA/RA")
sasl.registerCommandHandler(my_command_toggletransponder, 0, P.toggletransponder_)

--------------------------------------------------------------------------------------------------------------
function P.togglefds(state)

    if (state == nil) then
        if (get(P.fdpilotpos) == def.OFF) then
            helpers.command_once("laminar/B738/autopilot/flight_director_toggle")
            if (get(P.fdfopos) == def.OFF) then
                helpers.command_once("laminar/B738/autopilot/flight_director_fo_toggle")
            end
        else
            helpers.command_once("laminar/B738/autopilot/flight_director_toggle")
            if (get(P.fdfopos) == def.ON) then
                helpers.command_once("laminar/B738/autopilot/flight_director_fo_toggle")
            end
        end

    elseif (state == def.OFF) then
        if (get(P.fdpilotpos) == def.ON) then
            helpers.command_once("laminar/B738/autopilot/flight_director_toggle")
        end
        if (get(P.fdfopos) == def.ON) then
            helpers.command_once("laminar/B738/autopilot/flight_director_fo_toggle")
        end
    elseif (state == def.ON) then
        if (get(P.fdpilotpos) == def.OFF) then
            helpers.command_once("laminar/B738/autopilot/flight_director_toggle")
        end
        if (get(P.fdfopos) == def.OFF) then
            helpers.command_once("laminar/B738/autopilot/flight_director_fo_toggle")
        end
    end
end

function P.togglefds_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglefds(nil)
    end
    return 0
end

local my_command_togglefds = sasl.createCommand(def.APPNAMEPREFIX .. "/togglefds", "Toggle Both Flight Directors")
sasl.registerCommandHandler(my_command_togglefds, 0, P.togglefds_)

--------------------------------------------------------------------------------------------------------------
function P.togglebothefbs(state)

    local cptHidden = (get(P.hidecptefb) == def.EFBHIDDEN)
    local foHidden = (get(P.hidefoefb) == def.EFBHIDDEN)

    if (state == nil) then
        if cptHidden and foHidden then
            state = def.ON
        else
            state = def.OFF
        end
    end

    if (state == def.OFF) then
        if not cptHidden then
            helpers.command_once("laminar/B738/tab/toggle")
        end
        if not foHidden then
            helpers.command_once("laminar/B738/tab/fo_toggle")
        end
    elseif (state == def.ON) then
        if cptHidden then
            helpers.command_once("laminar/B738/tab/toggle")
        end
        if foHidden then
            helpers.command_once("laminar/B738/tab/fo_toggle")
        end
    end
end

function P.togglebothefbs_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglebothefbs(nil)
    end
    return 0
end

local my_command_togglebothefbs = sasl.createCommand(def.APPNAMEPREFIX .. "/togglebothefbs", "Toggle Both EFBs")
sasl.registerCommandHandler(my_command_togglebothefbs, 0, P.togglebothefbs_)

--------------------------------------------------------------------------------------------------------------
function P.togglewx(state)

    if (state == nil) then
        if (get(P.efiswxpilotpos) == def.OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/wxr_press")
            if (get(P.efiswxfopos) == def.OFF) then
                helpers.command_once("laminar/B738/EFIS_control/fo/push_button/wxr_press")
            end
        else
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/wxr_press")
            if (get(P.efiswxfopos) == def.ON) then
                helpers.command_once("laminar/B738/EFIS_control/fo/push_button/wxr_press")
            end
        end

    elseif (state == def.OFF) then
        if (get(P.efiswxpilotpos) == def.ON) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/wxr_press")
        end
        if (get(P.efiswxfopos) == def.ON) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/wxr_press")
        end
    elseif (state == def.ON) then
        if (get(P.efiswxpilotpos) == def.OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/wxr_press")
        end
        if (get(P.efiswxfopos) == def.OFF) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/wxr_press")
        end
    end
end

function P.togglewx_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglewx(nil)
    end
    return 0
end

local my_command_togglewx = sasl.createCommand(def.APPNAMEPREFIX .. "/togglewx", "Toggle Both Weather Radars")
sasl.registerCommandHandler(my_command_togglewx, 0, P.togglewx_)

--------------------------------------------------------------------------------------------------------------
function P.toggleterr(state)

    if (state == nil) then
        if (get(P.efisterrpilotpos) == def.OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/terr_press")
            if (get(P.efisterrfopos) == def.OFF) then
                helpers.command_once("laminar/B738/EFIS_control/fo/push_button/terr_press")
            end
        else
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/terr_press")
            if (get(P.efisterrfopos) == def.ON) then
                helpers.command_once("laminar/B738/EFIS_control/fo/push_button/terr_press")
            end
        end

    elseif (state == def.OFF) then
        if (get(P.efisterrpilotpos) == def.ON) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/terr_press")
        end
        if (get(P.efisterrfopos) == def.ON) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/terr_press")
        end
    elseif (state == def.ON) then
        if (get(P.efisterrpilotpos) == def.OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/terr_press")
        end
        if (get(P.efisterrfopos) == def.OFF) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/terr_press")
        end
    end
end

function P.toggleterr_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggleterr(nil)
    end
    return 0
end

local my_command_toggleterr = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleterr", "Toggle Both Terrain Radars")
sasl.registerCommandHandler(my_command_toggleterr, 0, P.toggleterr_)

--------------------------------------------------------------------------------------------------------------
function P.togglewindowheat(state)

    if (state == nil) then
        if (get(P.wheatlfwdpos) == def.ON) then
            set(P.wheatlfwdpos, def.OFF)
            set(P.wheatrfwdpos, def.OFF)
            set(P.wheatlsidepos, def.OFF)
            set(P.wheatrsidepos, def.OFF)
        else
            set(P.wheatlfwdpos, def.ON)
            set(P.wheatrfwdpos, def.ON)
            set(P.wheatlsidepos, def.ON)
            set(P.wheatrsidepos, def.ON)
        end
    elseif ((state == def.ON) and (get(P.wheatlfwdpos) == def.OFF)) then
        set(P.wheatlfwdpos, def.ON)
        set(P.wheatrfwdpos, def.ON)
        set(P.wheatlsidepos, def.ON)
        set(P.wheatrsidepos, def.ON)
    elseif ((state == def.OFF) and (get(P.wheatlfwdpos) == def.ON)) then
        set(P.wheatlfwdpos, def.OFF)
        set(P.wheatrfwdpos, def.OFF)
        set(P.wheatlsidepos, def.OFF)
        set(P.wheatrsidepos, def.OFF)
    end

    return true
end

function P.togglewindowheat_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglewindowheat(nil)
    end
    return 0
end

local my_command_togglewindowheat = sasl.createCommand(def.APPNAMEPREFIX .. "/togglewindowheat", "Toggle Window Heat")
sasl.registerCommandHandler(my_command_togglewindowheat, 0, P.togglewindowheat_)

--------------------------------------------------------------------------------------------------------------
function P.toggleprobeheat(state)

    if (state == nil) then
        if (get(P.captainprobepos) == def.ON) then
            set(P.captainprobepos, def.OFF)
            set(P.foprobepos, def.OFF)
        else
            set(P.captainprobepos, def.ON)
            set(P.foprobepos, def.ON)
        end
    elseif ((state == def.ON) and (get(P.captainprobepos) == def.OFF)) then
        set(P.captainprobepos, def.ON)
        set(P.foprobepos, def.ON)
    elseif ((state == def.OFF) and (get(P.captainprobepos) == def.ON)) then
        set(P.captainprobepos, def.OFF)
        set(P.foprobepos, def.OFF)
    end

    return true
end

function P.toggleprobeheat_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggleprobeheat(nil)
    end
    return 0
end

local my_command_toggleprobeheat = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleprobeheat", "Toggle Probe Heat")
sasl.registerCommandHandler(my_command_toggleprobeheat, 0, P.toggleprobeheat_)

--------------------------------------------------------------------------------------------------------------
function P.iceprotection(state)

    local set = 0

    if (state == nil) then
        if (get(P.eng1heatpos) == def.OFF) then
            set = 1
            helpers.command_once("laminar/B738/toggle_switch/eng1_heat")
            if (get(P.eng2heatpos) == def.OFF) then
                helpers.command_once("laminar/B738/toggle_switch/eng2_heat")
            end
            if (get(P.wingheatpos) == def.OFF) then
                helpers.command_once("laminar/B738/toggle_switch/wing_heat")
            end
        else
            set = 2
            helpers.command_once("laminar/B738/toggle_switch/eng1_heat")
            if (get(P.eng2heatpos) == def.ON) then
                helpers.command_once("laminar/B738/toggle_switch/eng2_heat")
            end
            if (get(P.wingheatpos) == def.ON) then
                helpers.command_once("laminar/B738/toggle_switch/wing_heat")
            end
        end
    elseif (state == def.ON) then
        if (get(P.eng1heatpos) == def.OFF) then
            set = 1
            helpers.command_once("laminar/B738/toggle_switch/eng1_heat")
        end

        if (get(P.eng2heatpos) == def.OFF) then
            set = 1
            helpers.command_once("laminar/B738/toggle_switch/eng2_heat")
        end

        if (get(P.wingheatpos) == def.OFF) then
            set = 1
            helpers.command_once("laminar/B738/toggle_switch/wing_heat")
        end
    elseif (state == def.OFF) then
        if (get(P.eng1heatpos) == def.ON) then
            set = 2
            helpers.command_once("laminar/B738/toggle_switch/eng1_heat")
        end

        if (get(P.eng2heatpos) == def.ON) then
            set = 2
            helpers.command_once("laminar/B738/toggle_switch/eng2_heat")
        end

        if (get(P.wingheatpos) == def.ON) then
            set = 2
            helpers.command_once("laminar/B738/toggle_switch/wing_heat")
        end
    end

    if (set == 1) then
        P.commandtableentry(def.TEXT, "Wing and Engine Anti Ice On")
    elseif (set == 2) then
        P.commandtableentry(def.TEXT, "Wing and Engine Anti Ice Off")
    end

    return true

end

function P.iceprotection_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.iceprotection(nil)
    end
    return 0
end

local my_command_iceprotection = sasl.createCommand(def.APPNAMEPREFIX .. "/iceprotection", "Toggle Ice Protection")
sasl.registerCommandHandler(my_command_iceprotection, 0, P.iceprotection_)

 --------------------------------------------------------------------------------------------------------------
function P.setcockpitlights()

    local lightset = false

    if (get(P.brightmainpanel) ~= P.configvalues[def.CONFIGBRIGHTMAINPANEL]) then
        set(P.brightmainpanel, P.configvalues[def.CONFIGBRIGHTMAINPANEL])
        lightset = true
    end
    if (get(P.brightcopilotmainpanel) ~= P.configvalues[def.CONFIGBRIGHTMAINPANEL]) then
        set(P.brightcopilotmainpanel, P.configvalues[def.CONFIGBRIGHTMAINPANEL])
        lightset = true
    end
    if (get(P.brightoverhead) ~= P.configvalues[def.CONFIGBRIGHTOVERHEAD]) then
        set(P.brightoverhead, P.configvalues[def.CONFIGBRIGHTOVERHEAD])
        lightset = true
    end
    if (get(P.brightpedestral) ~= P.configvalues[def.CONFIGBRIGHTPEDESTRAL]) then
        set(P.brightpedestral, P.configvalues[def.CONFIGBRIGHTPEDESTRAL])
    end
    if (get(P.genbrightbackground) ~= P.configvalues[def.CONFIGGENBRIGHTBACKGROUND]) then
        set(P.genbrightbackground, P.configvalues[def.CONFIGGENBRIGHTBACKGROUND])
        lightset = true
    end
    if (get(P.genbrightafdsflood) ~= P.configvalues[def.CONFIGGENBRIGHTAFDSFLOOD]) then
        set(P.genbrightafdsflood, P.configvalues[def.CONFIGGENBRIGHTAFDSFLOOD])
        lightset = true
    end
    if (get(P.genbrightpedestralflood) ~= P.configvalues[def.CONFIGGENBRIGHTPEDESTRALFLOOD]) then
        set(P.genbrightpedestralflood, P.configvalues[def.CONFIGGENBRIGHTPEDESTRALFLOOD])
        lightset = true
    end
    if (get(P.instrbrightoutbddu) ~= P.configvalues[def.CONFIGINSTRBRIGHTOUTBDDU]) then
        set(P.instrbrightoutbddu, P.configvalues[def.CONFIGINSTRBRIGHTOUTBDDU])
        lightset = true
    end
    if (get(P.instrbrightcopilotoutbddu) ~= P.configvalues[def.CONFIGINSTRBRIGHTOUTBDDU]) then
        set(P.instrbrightcopilotoutbddu, P.configvalues[def.CONFIGINSTRBRIGHTOUTBDDU])
        lightset = true
    end
    if (get(P.instrbrightinbddu) ~= P.configvalues[def.CONFIGINSTRBRIGHTINBDDU]) then
        set(P.instrbrightinbddu, P.configvalues[def.CONFIGINSTRBRIGHTINBDDU])
        lightset = true
    end
    if (get(P.instrbrightcopilotinbddu) ~= P.configvalues[def.CONFIGINSTRBRIGHTINBDDU]) then
        set(P.instrbrightcopilotinbddu, P.configvalues[def.CONFIGINSTRBRIGHTINBDDU])
        lightset = true
    end
    if (get(P.instrbrightupperdu) ~= P.configvalues[def.CONFIGINSTRBRIGHTUPPERDU]) then
        set(P.instrbrightupperdu, P.configvalues[def.CONFIGINSTRBRIGHTUPPERDU])
        lightset = true
    end
    if (get(P.instrbrightlowdu) ~= P.configvalues[def.CONFIGINSTRBRIGHTLOWDU]) then
        set(P.instrbrightlowdu, P.configvalues[def.CONFIGINSTRBRIGHTLOWDU])
        lightset = true
    end
    if (get(P.instrbrightinbdduS) ~= P.configvalues[def.CONFIGINSTRBRIGHTINBDDUS]) then
        set(P.instrbrightinbdduS, P.configvalues[def.CONFIGINSTRBRIGHTINBDDUS])
        lightset = true
    end
    if (get(P.instrbrightcopilotinbdduS) ~= P.configvalues[def.CONFIGINSTRBRIGHTINBDDUS]) then
        set(P.instrbrightcopilotinbdduS, P.configvalues[def.CONFIGINSTRBRIGHTINBDDUS])
        lightset = true
    end
    if (get(P.instrbrightlowduS) ~= P.configvalues[def.CONFIGINSTRBRIGHTLOWDUS]) then
        set(P.instrbrightlowduS, P.configvalues[def.CONFIGINSTRBRIGHTLOWDUS])
        lightset = true
    end

    return lightset

end

function P.setcockpitlights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.setcockpitlights()
    end
    return 0
end

local my_command_setcockpitlights = sasl.createCommand(def.APPNAMEPREFIX .. "/setcockpitlights", "Set Cockpit Lights")
sasl.registerCommandHandler(my_command_setcockpitlights, 0, P.setcockpitlights_)


--------------------------------------------------------------------------------------------------------------
function P.togglevoicereadback()

    local newValue = def.ON
    if (P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) then
        newValue = def.OFF
    end
    P.configvalues[def.CONFIGVOICEREADBACK] = newValue
    if settings and settings.appSettings then
        settings.appSettings[def.CONFIGVOICEREADBACK] = newValue
        if settings.writeSettings then
            settings.writeSettings(settings.appSettings)
        end
    end
    if newValue == def.ON then
        P.initDataref()
        P.commandtableentry(def.TEXT, "Voice Readback On")
    else
        P.commandtableentry(def.TEXT, "Voice Readback Off")
    end

    return true

end

function P.togglevoicereadback_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglevoicereadback()
    end
    return 0
end

local my_command_togglevoicereadback = sasl.createCommand(def.APPNAMEPREFIX .. "/togglevoicereadback", "Toggle Voice Readback")
sasl.registerCommandHandler(my_command_togglevoicereadback, 0, P.togglevoicereadback_)

--------------------------------------------------------------------------------------------------------------
function P.flapsuphandling()
    local current_speed = get(P.airspeed)
    local current_flaps = get(P.flapleverpos)
    local speed_buffer = 3

    local target_flaps = current_flaps

    if current_speed > (get(P.flapsupspeed) + speed_buffer) then
        target_flaps = def.FLAPSUP
    elseif current_speed > (get(P.flaps1speed) + speed_buffer) then
        target_flaps = def.FLAPS1
    elseif current_speed > (get(P.flaps5speed) + speed_buffer) then
        target_flaps = def.FLAPS5
    elseif current_speed > (get(P.flaps10speed) + speed_buffer) then
        target_flaps = def.FLAPS10
    elseif current_speed > (get(P.flaps15speed) + speed_buffer) then
        target_flaps = def.FLAPS15
    end

    if current_flaps > target_flaps then
        local command_map = {
            [def.FLAPSUP] = "laminar/B738/push_button/flaps_0",
            [def.FLAPS1] = "laminar/B738/push_button/flaps_1",
            [def.FLAPS5] = "laminar/B738/push_button/flaps_5",
            [def.FLAPS10] = "laminar/B738/push_button/flaps_10",
            [def.FLAPS15] = "laminar/B738/push_button/flaps_15"
        }
        local text_map = {
            [def.FLAPSUP] = "Set Flaps Up",
            [def.FLAPS1] = "Set Flaps 1",
            [def.FLAPS5] = "Set Flaps 5",
            [def.FLAPS10] = "Set Flaps 10",
            [def.FLAPS15] = "Set Flaps 15"
        }

        if P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON then
            P.commandtableentry(def.TEXT, text_map[target_flaps])
        else
            local cmd = command_map[target_flaps]
            if cmd then
                helpers.command_once(cmd)
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.flapsdownhandling()
    local current_speed = get(P.airspeed)
    local current_flaps = get(P.flapleverpos)
    local speed_buffer = 5

    local target_flaps = current_flaps

    if current_speed < (get(P.flapsupspeed) - speed_buffer) then
        target_flaps = def.FLAPS1
    end
    if current_speed < (get(P.flaps1speed) - speed_buffer) then
        target_flaps = def.FLAPS5
    end
    if current_speed < (get(P.flaps5speed) - speed_buffer) then
        target_flaps = def.FLAPS10
    end
    if current_speed < (get(P.flaps10speed) - speed_buffer) then
        target_flaps = def.FLAPS15
    end
    if current_speed < (get(P.flaps15speed) - speed_buffer) then
        target_flaps = def.FLAPS25
    end
    if current_speed < (get(P.flaps25speed) - speed_buffer) then
        target_flaps = def.FLAPS30
    end

    if current_flaps < target_flaps then
        local command_map = {
            [def.FLAPS1] = "laminar/B738/push_button/flaps_1",
            [def.FLAPS5] = "laminar/B738/push_button/flaps_5",
            [def.FLAPS10] = "laminar/B738/push_button/flaps_10",
            [def.FLAPS15] = "laminar/B738/push_button/flaps_15",
            [def.FLAPS25] = "laminar/B738/push_button/flaps_25",
            [def.FLAPS30] = "laminar/B738/push_button/flaps_30"
        }
        local text_map = {
            [def.FLAPS1] = "Set Flaps 1",
            [def.FLAPS5] = "Set Flaps 5",
            [def.FLAPS10] = "Set Flaps 10",
            [def.FLAPS15] = "Set Flaps 15",
            [def.FLAPS25] = "Set Flaps 25",
            [def.FLAPS30] = "Set Flaps 30"
        }

        if P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON then
            P.commandtableentry(def.TEXT, text_map[target_flaps])
        else
            local cmd = command_map[target_flaps]
            if cmd then
                helpers.command_once(cmd)
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.copynav()

    local setnav = false

    if (get(P.mcppilotcourse) ~= get(P.mcpcopilotcourse)) then
        set(P.mcpcopilotcourse, get(P.mcppilotcourse))
        setnav = true
    end

    if (get(P.mmrinstalled) == def.OFF) then
        if (get(P.nav1freq) ~= get(P.nav2freq)) then
            set(P.nav2freq, get(P.nav1freq))
            setnav = true
        end
    elseif (get(P.mmrinstalled) == def.ON) then
        local cptMode = get(P.mmrcptactmode)
        local cptValue = get(P.mmrcptactvalue)
        local foMode = get(P.mmrfoactmode)
        local foValue = get(P.mmrfoactvalue)
        local mmrChanged = (cptMode ~= foMode) or (cptValue ~= foValue)
        local navChanged = false
        if cptMode == def.MMRILS or cptMode == def.MMRLOC then
            navChanged = (get(P.nav2freq) ~= get(P.nav1freq))
        end
        if mmrChanged or navChanged then
            if helpers and helpers.mmrCopyActToStby then
                helpers.mmrCopyActToStby(def.MMRFO)
            end
            set(P.mmrfoactmode, cptMode)
            set(P.mmrfoactvalue, cptValue)
            if cptMode == def.MMRILS or cptMode == def.MMRLOC then
                set(P.nav2stdbyfreq, get(P.nav2freq))
                set(P.nav2freq, get(P.nav1freq))
            end
            setnav = true
        end
    end

    if setnav then
        P.commandtableentry(def.TEXT, "NAV 1 copied to NAV 2")
    else
        P.commandtableentry(def.TEXT, "NAV 1 and NAV 2 already aligned")
    end

    return true

end

function P.copynav_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.copynav()
    end
    return 0
end

local my_command_copynav = sasl.createCommand(def.APPNAMEPREFIX .. "/copynav", "Copy NAV1/MMR1 to NAV2/MMR2")
sasl.registerCommandHandler(my_command_copynav, 0, P.copynav_)

--------------------------------------------------------------------------------------------------------------
function P.setilsproc()

    return P.triggerprocedure(def.SETILSPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.setilsproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.setilsproc()
    end
    return 0
end

local my_command_setils = sasl.createCommand(def.APPNAMEPREFIX .. "/setils", "Set ILS/GLS Frequency and Course")
sasl.registerCommandHandler(my_command_setils, 0, P.setilsproc_)


--------------------------------------------------------------------------------------------------------------
function P.setvrefproc()

    return P.triggerprocedure(def.SETVREFPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.setvrefproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.setvrefproc()
    end
    return 0
end

local my_command_setvref = sasl.createCommand(def.APPNAMEPREFIX .. "/setvref", "Set Landing Flaps/VREF")
sasl.registerCommandHandler(my_command_setvref, 0, P.setvrefproc_)

--------------------------------------------------------------------------------------------------------------
function P.settoflapsproc()

    return P.triggerprocedure(def.SETTOFLAPSPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.settoflapsproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.settoflapsproc()
    end
    return 0
end

local my_command_settoflapsproc = sasl.createCommand(def.APPNAMEPREFIX .. "/settoflapsproc", "Set Takeoff Flaps")
sasl.registerCommandHandler(my_command_settoflapsproc, 0, P.settoflapsproc_)

--------------------------------------------------------------------------------------------------------------
function P.settotrim(trimvalue)

    local targettrim = 0

    local trimwheelrounded = 0
    local trimwheelcalcrounded = 0

    local trimwheeltemp = 0
    local trimwheelold = 0

    if (trimvalue == nil)
    then
        targettrim = get(P.trimcalc)
    else
        targettrim = trimvalue
    end

    trimwheelcalcrounded = helpers.trimvalue_to_trimwheel(targettrim)
    if trimwheelcalcrounded == nil then
        trimwheelcalcrounded = 40
    end

    trimwheeltemp = get(P.trimwheel)
    trimwheelrounded = trimwheeltemp * -100
    local loopguard = 0
    local tolerance = 0.5

    while ((math.abs(trimwheelrounded - trimwheelcalcrounded) > tolerance)
        and (trimwheeltemp ~= trimwheelold) and (loopguard < 200)) do
        sasl.logDebug("while loop settotrim")
        if (trimwheelrounded > trimwheelcalcrounded) then
            helpers.command_once("laminar/B738/flight_controls/pitch_trim_up")
        else
            if (trimwheelrounded < trimwheelcalcrounded) then
                helpers.command_once("laminar/B738/flight_controls/pitch_trim_down")
            end
        end

        trimwheelold = trimwheeltemp
        trimwheeltemp = get(P.trimwheel)
        trimwheelrounded = trimwheeltemp * -100
        loopguard = loopguard + 1

    end

    return true

end

--------------------------------------------------------------------------------------------------------------
function P.updatemetar()
    local depicaotmp = helpers.cleanstring(get(P.depicao))
    local desicaotmp = helpers.cleanstring(get(P.desicao))

    if P.flightstate == def.FLIGHTSTATEPREFLIGHT then
        if helpers.isvalidicao(depicaotmp) then
            helpers.getMetar(depicaotmp, P.depmetar)
        end
    end

    if helpers.isvalidicao(desicaotmp) then
        helpers.getMetar(desicaotmp, P.desmetar)
    end

    return true
end

--------------------------------------------------------------------------------------------------------------

function P.autowiper(state)

    local destwiperpos = 0

    if ((state == nil) or (state == def.ON)) then
        if (get(P.rain) <= 0.03) then
            destwiperpos = def.WIPEROFF
        elseif (get(P.rain) <= 0.25) then
            destwiperpos = def.WIPERINT
        elseif (get(P.rain) <= 0.6) then
            destwiperpos = def.WIPERLOW
        else
            destwiperpos = def.WIPERHIGH
        end
    else
        destwiperpos = state
    end

    local lwiperposdiff = math.abs(get(P.lwiperpos) - destwiperpos)
    local rwiperposdiff = math.abs(get(P.rwiperpos) - destwiperpos)

    if (get(P.lwiperpos) < destwiperpos) then
        while (lwiperposdiff > 0) do
            sasl.logDebug("while loop autowiper l up")
            helpers.command_once("laminar/B738/knob/left_wiper_up")
            lwiperposdiff = lwiperposdiff - 1
        end
    elseif (get(P.lwiperpos) > destwiperpos) then
        while (lwiperposdiff > 0) do
            sasl.logDebug("while loop autowiper l dn")
            helpers.command_once("laminar/B738/knob/left_wiper_dn")
            lwiperposdiff = lwiperposdiff - 1
        end
    end

    if (get(P.rwiperpos) < destwiperpos) then
        while (rwiperposdiff > 0) do
            sasl.logDebug("while loop autowiper r up")
            helpers.command_once("laminar/B738/knob/right_wiper_up")
            rwiperposdiff = rwiperposdiff - 1
        end
    elseif (get(P.rwiperpos) > destwiperpos) then
        while (rwiperposdiff > 0) do
            sasl.logDebug("while loop autowiper r dn")
            helpers.command_once("laminar/B738/knob/right_wiper_dn")
            rwiperposdiff = rwiperposdiff - 1
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------

function P.autocentertanks()

    if ((get(P.centertanklbs) > 1000) and (get(P.centertanklpress) > 0) and (get(P.centertankrpress) > 0) and (get(P.centertankstat) > 0)) then
        if (get(P.centertanklswitch) == def.OFF) then
            set(P.centertanklswitch, def.ON)
        end
        if (get(P.centertankrswitch) == def.OFF) then
            set(P.centertankrswitch, def.ON)
        end
        P.centertankoffset = false
    elseif (((not P.centertankoffset) and (get(P.centertanklbs) <= 1000)) or ((get(P.centertanklpress) == 0) and (get(P.centertankrpress) == 0))) then
        if (get(P.centertanklswitch) == def.ON) then
            set(P.centertanklswitch, def.OFF)
        end
        if (get(P.centertankrswitch) == def.ON) then
            set(P.centertankrswitch, def.OFF)
        end
        P.centertankoffset = true
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.setstarter(starter, state)

    local starter1posdiff = math.abs(get(P.starter1pos) - state)
    local starter2posdiff = math.abs(get(P.starter2pos) - state)

    if ((state ~= nil) and (starter ~= nil)) then
        if ((starter == def.ENGINE1) or (starter == def.BOTH)) then
            if (state > get(P.starter1pos)) then
                while (starter1posdiff > 0) do
                    sasl.logDebug("while loop eng1 start right")
                    helpers.command_once("laminar/B738/knob/eng1_start_right")
                    starter1posdiff = starter1posdiff - 1
                end
            elseif (state < get(P.starter1pos)) then
                while (starter1posdiff > 0) do
                    sasl.logDebug("while loop eng1 start left")
                    helpers.command_once("laminar/B738/knob/eng1_start_left")
                    starter1posdiff = starter1posdiff - 1
                end
            end
        end

        if ((starter == def.ENGINE2) or (starter == def.BOTH)) then
            if (state > get(P.starter2pos)) then
                while (starter2posdiff > 0) do
                    sasl.logDebug("while loop eng2 start right")
                    helpers.command_once("laminar/B738/knob/eng2_start_right")
                    starter2posdiff = starter2posdiff - 1
                end
            elseif (state < get(P.starter2pos)) then
                while (starter2posdiff > 0) do
                    sasl.logDebug("while loop eng2 start left")
                    helpers.command_once("laminar/B738/knob/eng2_start_left")
                    starter2posdiff = starter2posdiff - 1
                end
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------

function P.setirs(irs, state)

    local result = true

    sasl.logDebug("SETIRS IRS LEFT POS: " .. tostring(get(P.irsleftpos)) .. " IRS RIGHT POS: " .. tostring(get(P.irsrightpos)))

    if ((state ~= nil) and (irs ~= nil)) then
        if ((irs == def.LEFTIRS) or (irs == def.BOTHIRS)) then
            if (state > get(P.irsleftpos)) then
                helpers.command_once("laminar/B738/toggle_switch/irs_L_right")
                result = false
            elseif (state < get(P.irsleftpos)) then
                helpers.command_once("laminar/B738/toggle_switch/irs_L_left")
                result = false
            end
        end

        if ((irs == def.RIGHTIRS) or (irs == def.BOTHIRS)) then
            if (state > get(P.irsrightpos)) then
                helpers.command_once("laminar/B738/toggle_switch/irs_R_right")
                result = false
            elseif (state < get(P.irsrightpos)) then
                helpers.command_once("laminar/B738/toggle_switch/irs_R_left")
                result = false
            end
        end
    end

    return result
end

--------------------------------------------------------------------------------------------------------------

function P.enginesrunning(state)

    local running = false

    if ((state == nil) or (state == def.BOTH)) then
        if ((get(P.eng1n1percent) ~= nil) and (get(P.eng2n1percent) ~= nil)) then
            if ((get(P.eng1n1percent) >= 19) and (get(P.eng2n1percent) >= 19)) then
                running = true
            end
        end
    elseif (state == def.ENGINE1) then
        if (get(P.eng1n1percent) ~= nil) then
            if (get(P.eng1n1percent) >= 19) then
                running = true
            end
        end
    elseif (state == def.ENGINE2) then
        if (get(P.eng2n1percent) ~= nil) then
            if (get(P.eng2n1percent) >= 19) then
               running = true
            end
        end
    end

    return running

end

--------------------------------------------------------------------------------------------------------------
function P.apurunning()

    local starter_pos = get(P.apustarterpos)
    if starter_pos == nil then
        return def.APUOFF
    end

    if starter_pos == def.STARTEROFF then
        return def.APUOFF
    end

    local starter_is_engaged = (starter_pos == def.STARTERON) or (starter_pos == def.STARTERPRESSED)

    if starter_is_engaged and (get(P.apugenoffbus) == def.OFF) then
        if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF) and (get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
            return def.APUONBUS
        else
            return def.APUSTARTED
        end
    elseif starter_is_engaged and (get(P.apugenoffbus) ~= def.OFF) then
        if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF) and (get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
            return def.APUONBUS
        else
            return def.APUOFFBUS
        end
    end

    return def.APUOFF
end

--------------------------------------------------------------------------------------------------------------

function P.setdomelight(state)

    local domelightposdiff = math.abs(get(P.domelightpos) - state)

    if (state > get(P.domelightpos)) then
        while (domelightposdiff > 0) do
            sasl.logDebug("while loop dome up")
            helpers.command_once("laminar/B738/toggle_switch/cockpit_dome_up")
            domelightposdiff = domelightposdiff - 1
        end
    elseif (state < get(P.domelightpos)) then
        while (domelightposdiff > 0) do
            sasl.logDebug("while loop dome dn")
            helpers.command_once("laminar/B738/toggle_switch/cockpit_dome_dn")
            domelightposdiff = domelightposdiff - 1
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.setbankanglepos(state)

    local bankangleposdiff = math.abs(get(P.bankanglepos) - state)

    if ((state == nil) or (state > def.BANKANGLEMAX)) then
        return false
    end

    if (state > get(P.bankanglepos)) then
        while (bankangleposdiff > 0) do
            sasl.logDebug("while loop bank ang up")
            helpers.command_once("laminar/B738/autopilot/bank_angle_up")
            bankangleposdiff = bankangleposdiff - 1
        end
    elseif (state < get(P.bankanglepos)) then
        while (bankangleposdiff > 0) do
            sasl.logDebug("while loop bank ang dn")
            helpers.command_once("laminar/B738/autopilot/bank_angle_dn")
            bankangleposdiff = bankangleposdiff - 1
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.setautobrake(state)

    if (state == nil) then
        return false
    end

    if ((state == def.AUTOBRAKERTO) and (get(P.autobrakepos) ~= def.AUTOBRAKERTO)) then
        helpers.command_once("laminar/B738/knob/autobrake_rto")
    elseif ((state == def.AUTOBRAKEOFF) and (get(P.autobrakepos) ~= def.AUTOBRAKEOFF)) then
        helpers.command_once("laminar/B738/knob/autobrake_off")
    elseif ((state == def.AUTOBRAKE1) and (get(P.autobrakepos) ~= def.AUTOBRAKE1)) then
        helpers.command_once("laminar/B738/knob/autobrake_1")
    elseif ((state == def.AUTOBRAKE2) and (get(P.autobrakepos) ~= def.AUTOBRAKE2)) then
        helpers.command_once("laminar/B738/knob/autobrake_2")
    elseif ((state == def.AUTOBRAKE3) and (get(P.autobrakepos) ~= def.AUTOBRAKE3)) then
        helpers.command_once("laminar/B738/knob/autobrake_3")
    elseif ((state == def.AUTOBRAKEMAX) and (get(P.autobrakepos) ~= def.AUTOBRAKEMAX)) then
        helpers.command_once("laminar/B738/knob/autobrake_max")
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.setseatbeltsign(state)

    local seatbeltsignposdiff = math.abs(get(P.seatbeltsignpos) - state)

    if (state > get(P.seatbeltsignpos)) then
        while (seatbeltsignposdiff > 0) do
            sasl.logDebug("while loop seat belt dn")
            helpers.command_once("laminar/B738/toggle_switch/seatbelt_sign_dn")
            seatbeltsignposdiff = seatbeltsignposdiff - 1
        end
    elseif (state < get(P.seatbeltsignpos)) then
        while (seatbeltsignposdiff > 0) do
            sasl.logDebug("while loop seat belt up")
            helpers.command_once("laminar/B738/toggle_switch/seatbelt_sign_up")
            seatbeltsignposdiff = seatbeltsignposdiff - 1
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------

function P.setnosmokingsign(state)

    local nosmokingsignposdiff = math.abs(get(P.nosmokingsignpos) - state)

    if (state > get(P.nosmokingsignpos)) then
        while (nosmokingsignposdiff > 0) do
            sasl.logDebug("while loop no smoking dn")
            helpers.command_once("laminar/B738/toggle_switch/no_smoking_dn")
            nosmokingsignposdiff = nosmokingsignposdiff - 1
        end
    elseif (state < get(P.nosmokingsignpos)) then
        while (nosmokingsignposdiff > 0) do
            sasl.logDebug("while loop no smoke up")
            helpers.command_once("laminar/B738/toggle_switch/no_smoking_up")
            nosmokingsignposdiff = nosmokingsignposdiff - 1
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.setemergencylights(state)

    local emergencylightsdiff = math.abs(get(P.emergencylights) - state)

    if (state > get(P.emergencylights)) then
        while (emergencylightsdiff > 0) do
            sasl.logDebug("while loop exit light dn")
            helpers.command_once("laminar/B738/toggle_switch/emer_exit_lights_dn")
            emergencylightsdiff = emergencylightsdiff - 1
        end
    elseif (state < get(P.emergencylights)) then
        while (emergencylightsdiff > 0) do
            sasl.logDebug("while loop exit light  up")
            helpers.command_once("laminar/B738/toggle_switch/emer_exit_lights_up")
            emergencylightsdiff = emergencylightsdiff - 1
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.test()

   return P.triggerprocedure(def.TESTPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.test_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.test()
    end
    return 0
end

local my_command_test = sasl.createCommand(def.APPNAMEPREFIX .. "/test", "Tests")
sasl.registerCommandHandler(my_command_test, 0, P.test_)

--------------------------------------------------------------------------------------------------------------
function P.coldanddarkstartup()

    return P.triggerprocedure(def.COLDANDDARKPROCEDURE, def.TRIGGEREDMANUALLY)


end

function P.coldanddarkstartup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.coldanddarkstartup()
    end
    return 0
end

local my_command_coldanddarkstartup = sasl.createCommand(def.APPNAMEPREFIX .. "/coldanddarkstartup", "Cold and Dark Startup")
sasl.registerCommandHandler(my_command_coldanddarkstartup, 0, P.coldanddarkstartup_)

--------------------------------------------------------------------------------------------------------------
function P.apustartup()

    return P.triggerprocedure(def.APUSTARTUPPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.apustartup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.apustartup()
    end
    return 0
end

local my_command_apustartup = sasl.createCommand(def.APPNAMEPREFIX .. "/apustartup", "APU Startup")
sasl.registerCommandHandler(my_command_apustartup, 0, P.apustartup_)

--------------------------------------------------------------------------------------------------------------
function P.enginestart()

    return P.triggerprocedure(def.ENGINESTARTPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.enginestart_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.enginestart()
    end
    return 0
end

local my_command_enginestart = sasl.createCommand(def.APPNAMEPREFIX .. "/enginestart", "Engine Startup")
sasl.registerCommandHandler(my_command_enginestart, 0, P.enginestart_)

--------------------------------------------------------------------------------------------------------------

function P.turnaroundengineshutdown()

    return P.triggerprocedure(def.TURNAROUNDENGINESHUTDOWNPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.turnaroundengineshutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.turnaroundengineshutdown()
    end
    return 0
end

local my_command_turnaroundengineshutdown = sasl.createCommand(def.APPNAMEPREFIX .. "/turnaroundengineshutdown", "Engine Shutdown Turnaround")
sasl.registerCommandHandler(my_command_turnaroundengineshutdown, 0, P.turnaroundengineshutdown_)

--------------------------------------------------------------------------------------------------------------
function P.finalengineshutdown()

    return P.triggerprocedure(def.FINALENGINESHUTDOWNPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.finalengineshutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.finalengineshutdown()
    end
    return 0
end

local my_command_finalengineshutdown = sasl.createCommand(def.APPNAMEPREFIX .. "/finalengineshutdown", "Final Engine Shutdown")
sasl.registerCommandHandler(my_command_finalengineshutdown, 0, P.finalengineshutdown_)

--------------------------------------------------------------------------------------------------------------
function P.shutdown()

    return P.triggerprocedure(def.SHUTDOWNPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.shutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.shutdown()
    end
    return 0
end

local my_command_shutdown = sasl.createCommand(def.APPNAMEPREFIX .. "/shutdown", "Shutdown")
sasl.registerCommandHandler(my_command_shutdown, 0, P.shutdown_)

--------------------------------------------------------------------------------------------------------------
function P.cockpitinit()

    return P.triggerprocedure(def.COCKPITINITPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.cockpitinit_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.cockpitinit()
    end
    return 0
end

local my_command_cockpitinit = sasl.createCommand(def.APPNAMEPREFIX .. "/cockpitinit", "Cockpit Initialization")
sasl.registerCommandHandler(my_command_cockpitinit, 0, P.cockpitinit_)

--------------------------------------------------------------------------------------------------------------
function P.beforetaxi()

    return P.triggerprocedure(def.BEFORETAXIPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.beforetaxi_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.beforetaxi()
    end
    return 0
end

local my_command_beforetaxi = sasl.createCommand(def.APPNAMEPREFIX .. "/beforetaxi", "Before Taxi Procedure")
sasl.registerCommandHandler(my_command_beforetaxi, 0, P.beforetaxi_)


--------------------------------------------------------------------------------------------------------------
function P.beforetakeoff()

    return P.triggerprocedure(def.BEFORETAKEOFFPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.beforetakeoff_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.beforetakeoff()
    end
    return 0
end

local my_command_beforetakeoff = sasl.createCommand(def.APPNAMEPREFIX .. "/beforetakeoff", "Before Takeoff Procedure")
sasl.registerCommandHandler(my_command_beforetakeoff, 0, P.beforetakeoff_)

--------------------------------------------------------------------------------------------------------------
function P.afterlanding()

    return P.triggerprocedure(def.AFTERLANDINGPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.afterlanding_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.afterlanding()
    end
    return 0
end

local my_command_afterlanding = sasl.createCommand(def.APPNAMEPREFIX .. "/afterlanding", "After Landing Procedure")
sasl.registerCommandHandler(my_command_afterlanding, 0, P.afterlanding_)

--------------------------------------------------------------------------------------------------------------

function P.atparkingposition()

    return P.triggerprocedure(def.ATPARKINGPOSITIONPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.atparkingposition_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.atparkingposition()
    end
    return 0
end

local my_command_atparkingposition = sasl.createCommand(def.APPNAMEPREFIX .. "/atparkingposition", "At Parking Position")
sasl.registerCommandHandler(my_command_atparkingposition, 0, P.atparkingposition_)


--------------------------------------------------------------------------------------------------------------
function P.altitudea10000()

    return P.triggerprocedure(def.ALTITUDEA10000PROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.altitudea10000_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.altitudea10000()
    end
    return 0
end

local my_command_altitudea10000 = sasl.createCommand(def.APPNAMEPREFIX .. "/altitudea10000", "Above 10000")
sasl.registerCommandHandler(my_command_altitudea10000, 0, P.altitudea10000_)

--------------------------------------------------------------------------------------------------------------
function P.altitudeb10000()

    return P.triggerprocedure(def.ALTITUDEB10000PROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.altitudeb10000_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.altitudeb10000()
    end
    return 0
end

local my_command_altitudeb10000 = sasl.createCommand(def.APPNAMEPREFIX .. "/altitudeb10000", "Below 10000")
sasl.registerCommandHandler(my_command_altitudeb10000, 0, P.altitudeb10000_)

--------------------------------------------------------------------------------------------------------------
function P.goaround()

    return P.triggerprocedure(def.GOAROUNDPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.goaround_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.goaround()
    end
    return 0
end

local my_command_goaround = sasl.createCommand(def.APPNAMEPREFIX .. "/goaround", "Go Around Procedure")
sasl.registerCommandHandler(my_command_goaround, 0, P.goaround_)

--------------------------------------------------------------------------------------------------------------
function P.engineinflightrestart()

    return P.triggerprocedure(def.ENGINEINFLIGHTRESTARTPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.engineinflightrestart_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.engineinflightrestart()
    end
    return 0
end

local my_command_engineinflightrestart = sasl.createCommand(def.APPNAMEPREFIX .. "/engineinflightrestart", "Engine In-Flight Restart")
sasl.registerCommandHandler(my_command_engineinflightrestart, 0, P.engineinflightrestart_)

--------------------------------------------------------------------------------------------------------------
function P.duringclimb()
    local proc_to_check = def.DURINGCLIMBPROCEDURE
    local targetLoopIndex = P.proceduretable[proc_to_check].loop
    local isLoopFree = (P.loopStateTables[targetLoopIndex].lock == def.NOPROCEDURE)
    if isLoopFree then
        sasl.logDebug("Autofunctions triggering DURINGCLIMBPROCEDURE (Loop " .. targetLoopIndex .. " is free).")
        P.triggerprocedure(proc_to_check)
    end

    local lower_airspace_alt = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
    local altitudeTriggerConditions = (get(P.altitude) >= lower_airspace_alt)
    local above10kTargetLoopIndex = P.proceduretable[def.ALTITUDEA10000PROCEDURE].loop
    local isAbove10kLoopFree = (P.loopStateTables[above10kTargetLoopIndex].lock == def.NOPROCEDURE)
    if altitudeTriggerConditions and isAbove10kLoopFree then
        sasl.logDebug("Autofunctions triggering ALTITUDEA10000PROCEDURE (Loop " .. above10kTargetLoopIndex .. " is free).")
        P.triggerprocedure(def.ALTITUDEA10000PROCEDURE)
    end

    if (P.configvalues[def.CONFIGAUTOFLAPS] == def.ON) and (get(P.flapleverpos) > def.FLAPSUP) then
        P.flapsuphandling()
    end
end

--------------------------------------------------------------------------------------------------------------
function P.triggerapproachprep()
    local desIcao = get(P.desicao)
    local desRwy = get(P.desrwy)
    local validDest = helpers.isvalidicao(desIcao) and helpers.isvalidrwy(desRwy)
    local key = validDest and (tostring(desIcao) .. "|" .. tostring(desRwy)) or nil

    if key ~= P.approachPrepTriggerKey then
        P.approachPrepTriggerKey = key
        P.approachPrepCompletedForKey = nil
    end
    if not key or P.approachPrepCompletedForKey == key then
        return
    end

    local distDest = tonumber(get(P.distdest)) or 99999
    local vs = tonumber(get(P.verticalspeed)) or 0
    if distDest > 40 or vs >= -300 then
        return
    end

    local ilsDone = P.proceduretable[def.SETILSPROCEDURE] and P.proceduretable[def.SETILSPROCEDURE].set
    if not ilsDone then
        P.triggerprocedure(def.SETILSPROCEDURE, false)
        return
    end

    local requireVref = (P.configvalues[def.CONFIGVREF30SET] == def.ON)
    if requireVref then
        local vrefProc = P.proceduretable[def.SETVREFPROCEDURE]
        local vrefDone = (vrefProc and vrefProc.set == true) or false
        if not vrefDone then
            P.triggerprocedure(def.SETVREFPROCEDURE, false)
            return
        end

        local windDone = P.proceduretable[def.SETWINDCORRPROCEDURE] and P.proceduretable[def.SETWINDCORRPROCEDURE].set
        if not windDone then
            P.triggerprocedure(def.SETWINDCORRPROCEDURE, false)
            return
        end
    end

    P.approachPrepCompletedForKey = key
    helpers.logInfoTS(string.format("ApproachPrepTrigger: completed key=%s distDest=%.1f vs=%d", key, distDest, helpers.roundnumber(vs)))
end

--------------------------------------------------------------------------------------------------------------
function P.duringdescent()

    if P.pauseTodAutoDisabled then
        if get(P.pausetod) == def.OFF then
            set(P.pausetod, def.ON)
        end
        P.pauseTodAutoDisabled = false
    end
    P.pauseTodMonitorActive = false
    P.pauseTodMcpAltAtPrompt = nil

    local proc_to_check = def.DURINGDESCENTPROCEDURE
    local targetLoopIndex = P.proceduretable[proc_to_check].loop
    local isLoopFree = (P.loopStateTables[targetLoopIndex].lock == def.NOPROCEDURE)
    if isLoopFree then
        sasl.logDebug("Autofunctions triggering DURINGDESCENTPROCEDURE (Loop " .. targetLoopIndex .. " is free).")
        P.triggerprocedure(proc_to_check)
    end

    P.triggerapproachprep()

    local lower_airspace_alt = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
    local altitudeB10kConditions = (get(P.altitude) < lower_airspace_alt)
    local procB10k = def.ALTITUDEB10000PROCEDURE
    local loopB10kIndex = P.proceduretable[procB10k].loop
    local isLoopB10kFree = (P.loopStateTables[loopB10kIndex].lock == def.NOPROCEDURE)
    if altitudeB10kConditions and isLoopB10kFree then
        sasl.logDebug("Autofunctions triggering ALTITUDEB10000PROCEDURE (Loop " .. loopB10kIndex .. " is free).")
        P.triggerprocedure(procB10k)
    end

    local destination_icao = get(P.desicao)
    local destination_altitude = nil
    if P.airportdatatable[destination_icao] and P.airportdatatable[destination_icao].elevation_ft then
        destination_altitude = P.airportdatatable[destination_icao].elevation_ft
    else
        destination_altitude = get(P.desrwyalt)
    end

    local height_above_field = 99999
    if destination_altitude and destination_altitude > -1000 then
        height_above_field = get(P.altitude) - destination_altitude
    end
    local radio_alt = get(P.radioaltitude) or 99999

    local radioAltGateB2500 = P.isArrivalRunwayRadioAltGateOpen(8, 60)
    local radioAltGateB1000 = P.isArrivalRunwayRadioAltGateOpen(4, 40)
    local altitudeB2500Conditions = (height_above_field < 2500) or ((radio_alt < 2500) and radioAltGateB2500)
    local prevAltitudeB2500Conditions = P.prevAltitudeB2500Conditions == true
    if altitudeB2500Conditions and not prevAltitudeB2500Conditions then
        P.pendingAltitudeB2500Trigger = true
    elseif not altitudeB2500Conditions then
        P.pendingAltitudeB2500Trigger = false
    end
    P.prevAltitudeB2500Conditions = altitudeB2500Conditions
    local procB2500 = def.RADIOALTITUDEB2500PROCEDURE
    local loopB2500Index = P.proceduretable[procB2500].loop
    local isLoopB2500Free = (P.loopStateTables[loopB2500Index].lock == def.NOPROCEDURE)
    if P.pendingAltitudeB2500Trigger and isLoopB2500Free then
        sasl.logDebug("Autofunctions triggering RADIOALTITUDEB2500PROCEDURE (Loop " .. loopB2500Index .. " is free).")
        if P.triggerprocedure(procB2500) then
            P.pendingAltitudeB2500Trigger = false
        end
    end

    local altitudeB1000Conditions = (height_above_field < 1000) or ((radio_alt < 1000) and radioAltGateB1000)
    local prevAltitudeB1000Conditions = P.prevAltitudeB1000Conditions == true
    if altitudeB1000Conditions and not prevAltitudeB1000Conditions then
        P.pendingAltitudeB1000Trigger = true
    elseif not altitudeB1000Conditions then
        P.pendingAltitudeB1000Trigger = false
    end
    P.prevAltitudeB1000Conditions = altitudeB1000Conditions
    local procB1000 = def.RADIOALTITUDEB1000PROCEDURE
    local loopB1000Index = P.proceduretable[procB1000].loop
    local isLoopB1000Free = (P.loopStateTables[loopB1000Index].lock == def.NOPROCEDURE)
    if P.pendingAltitudeB1000Trigger and isLoopB1000Free then
        sasl.logDebug("Autofunctions triggering RADIOALTITUDEB1000PROCEDURE (Loop " .. loopB1000Index .. " is free).")
        if P.triggerprocedure(procB1000) then
            P.pendingAltitudeB1000Trigger = false
        end
    end

    if P.configvalues[def.CONFIGAUTOFLAPS] == def.ON then
        P.flapsdownhandling()
    end
end


--------------------------------------------------------------------------------------------------------------
function P.inflightrestoreactions()

    P.readconfig()

    if ((P.configvalues[def.CONFIGAUTOBARO] == def.ON) and (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON)) then
        if ((get(P.altitude) > get(P.fmctransalt)) and (get(P.barostd) == def.OFF)) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
        end

        if ((get(P.altitude) < get(P.fmctranslvl)) and (get(P.barostd) == def.ON)) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
            local baroinchtmp, baropastemp = P.getlocalqnh(def.ARRIVAL)
            set(P.baropilot, baroinchtmp)
        end
    end

end

--------------------------------------------------------------------------------------------------------------
function P.syncProceduresToFlightState()
    local currentFlightState = P.flightstate
    if currentFlightState == 0 then
        return
    end

    local changed = false

    for key, procData in pairs(P.proceduretable) do
        local requiredState = procData.requiredFlightstate
        if requiredState then
            local maxRequiredState = 0
            if type(requiredState) == "table" then
                for _, state in ipairs(requiredState) do
                    if state > maxRequiredState then
                        maxRequiredState = state
                    end
                end
            else
                maxRequiredState = requiredState
            end

            if maxRequiredState < currentFlightState then
                if not procData.set then
                    procData.set = true
                    changed = true
                    sasl.logDebug("SYNC_FS: Marking '" .. procData.name .. "' as set due to flight state advancement.")
                end
            end
        end
    end

    if changed then
        helpers.logInfoTS("Saving updated procedure set status to dataref.")
        local statusArray = {}
        for i = 1, #P.proceduretable do
             if P.proceduretable[i] and P.proceduretable[i].set then
                 statusArray[i] = 1
             else
                 statusArray[i] = 0
             end
        end
        set(P.ProcSetStatusarraydr, statusArray)
    end

end

--------------------------------------------------------------------------------------------------------------
function P.determineStateFromLastSetProc(lastSetKey)
    local state = def.FLIGHTSTATEPREFLIGHT -- Default

    if lastSetKey then
         -- Ground States
         if lastSetKey == def.SHUTDOWNPROCEDURE then state = def.FLIGHTSTATEPREFLIGHT
         elseif lastSetKey == def.FINALENGINESHUTDOWNPROCEDURE then state = def.FLIGHTSTATEPREFLIGHT
         elseif lastSetKey == def.ATPARKINGPOSITIONPROCEDURE then state = def.FLIGHTSTATESHUTDOWN
         elseif lastSetKey == def.TURNAROUNDENGINESHUTDOWNPROCEDURE then state = def.FLIGHTSTATESHUTDOWN
         elseif lastSetKey == def.AFTERLANDINGPROCEDURE then state = def.FLIGHTSTATETAXITOGATE
         -- Pre-Takeoff States
         elseif lastSetKey == def.BEFORETAKEOFFPROCEDURE then state = def.FLIGHTSTATEPREFLIGHT
         elseif lastSetKey == def.BEFORETAXIPROCEDURE then state = def.FLIGHTSTATEPREFLIGHT
         elseif lastSetKey == def.ENGINESTARTPROCEDURE then state = def.FLIGHTSTATEPREFLIGHT
         -- Air States
         elseif lastSetKey == def.DURINGDESCENTPROCEDURE or
                lastSetKey == def.ALTITUDEB10000PROCEDURE or
                lastSetKey == def.RADIOALTITUDEB2500PROCEDURE or
                lastSetKey == def.RADIOALTITUDEB1000PROCEDURE then
                    state = def.FLIGHTSTATEAPPROACH
         elseif lastSetKey == def.ALTITUDEA10000PROCEDURE then
             local fmsPhase = get(P.fmsflightphase) or 0
             if fmsPhase == def.FMSFLIGHTPHASE_CRUISE then
                 state = def.FLIGHTSTATECRUISE
             elseif fmsPhase >= def.FMSFLIGHTPHASE_DESCENT then
                 state = def.FLIGHTSTATEAPPROACH -- Corrected else case
             else
                 state = def.FLIGHTSTATECLIMB
             end
         elseif lastSetKey == def.DURINGCLIMBPROCEDURE then
             state = def.FLIGHTSTATECLIMB
         elseif lastSetKey == def.AFTERTAKEOFFPROCEDURE then
             state = def.FLIGHTSTATEINITIALCLIMB
         end
    end
    sasl.logDebug("...... Derived state from last set proc (".. (P.proceduretable[lastSetKey] and P.proceduretable[lastSetKey].name or "N/A") .."): " .. state)
    return state
end

--------------------------------------------------------------------------------------------------------------
function P.determineFlightStateFromProcedures()
    sasl.logDebug("Determining flight state based on first unset procedure's requirement...")

    -- 1. Sort procedures by number
    local orderedProcs = {}
    for key, value in pairs(P.proceduretable) do
        -- Ensure proc has a number and is valid before adding
        if value and value.number then 
            table.insert(orderedProcs, {key=key, data=value})
        end
    end
    -- Sort ascending by procedure number
    table.sort(orderedProcs, function(a, b) return a.data.number < b.data.number end)

    local firstUnsetProcKey = nil
    local firstUnsetProcName = "None Found (All Set?)"
    local lastSetProcKeyBeforeUnset = nil -- Track the last one that WAS set

    -- 2. Find the first procedure that is NOT set
    for _, procInfo in ipairs(orderedProcs) do
        -- Skip procedures without a defined .set flag if any exist
        if procInfo.data and procInfo.data.set ~= nil then 
            if not procInfo.data.set then
                firstUnsetProcKey = procInfo.key
                firstUnsetProcName = procInfo.data.name or ("ID:"..firstUnsetProcKey)
                break -- Stop at the first unset procedure
            else
                lastSetProcKeyBeforeUnset = procInfo.key -- Remember the last one seen that was set
            end
        end
    end

    sasl.logDebug("... First unset procedure found: " .. firstUnsetProcName)

    -- 3. Determine state based on the required state of the first *unset* procedure
    local stateFromReqs = def.FLIGHTSTATEPREFLIGHT -- Default if none are set or all are set

    if firstUnsetProcKey then
        local reqState = P.proceduretable[firstUnsetProcKey].requiredFlightstate
        if reqState then
            -- If multiple states are allowed, take the *lowest* as the most likely current state
            if type(reqState) == "table" then
                 local minState = 99 -- Start high
                 for _, state in ipairs(reqState) do
                     if state < minState then minState = state end
                 end
                 -- Handle case where table might be empty or contain invalid states
                 if minState ~= 99 then 
                    stateFromReqs = minState
                 else
                     sasl.logWarning("Procedure '"..firstUnsetProcName.."' has an empty/invalid requiredFlightstate table. Falling back.")
                     -- Fallback logic based on the *last set* procedure
                     if lastSetProcKeyBeforeUnset then 
                        sasl.logWarning("... Falling back to state determination based on last SET procedure: " .. P.proceduretable[lastSetProcKeyBeforeUnset].name) 
                        stateFromReqs = P.determineStateFromLastSetProc(lastSetProcKeyBeforeUnset) -- Use helper for fallback
                     else
                         stateFromReqs = def.FLIGHTSTATEPREFLIGHT -- Remain default if nothing was set before
                     end
                 end
            else -- Single required state
                 stateFromReqs = reqState
            end
            sasl.logDebug("... Required state for '"..firstUnsetProcName.."' is ".. helpers.tableToStringOrValue(reqState) .. ". Derived state: " .. stateFromReqs)
        else
            -- If the first unset procedure has *no* required state, 
            -- use the state implied by the *last set* procedure.
            sasl.logDebug("... First unset procedure '"..firstUnsetProcName.."' has no required state. Using state from last SET procedure if available.")
            if lastSetProcKeyBeforeUnset then
                stateFromReqs = P.determineStateFromLastSetProc(lastSetProcKeyBeforeUnset) -- Use helper for fallback
            else
                 -- Nothing set yet, remains PREFLIGHT
                 stateFromReqs = def.FLIGHTSTATEPREFLIGHT
            end
        end
    elseif lastSetProcKeyBeforeUnset then
         -- All procedures are set, or the remaining ones have no .set flag
         -- Determine state based on the VERY last procedure that *was* set
         sasl.logDebug("... All checkable procedures are set. Determining state based on the last one.")
         stateFromReqs = P.determineStateFromLastSetProc(lastSetProcKeyBeforeUnset) -- Use helper for fallback

    end

    sasl.logDebug("... Final State derived from procedure requirements: " .. stateFromReqs)
    return stateFromReqs
end

--------------------------------------------------------------------------------------------------------------
function P.autofunctions()
    local aircraftIsOnGround = (get(P.airgroundsensor) == def.ON)
    local flightStateChanged = false
    local currentFlightState = P.flightstate

    if P.isReloadWithinSession then
        local stateFromProcs = P.determineFlightStateFromProcedures()
        local stateIsPlausible = false
        local finalState = stateFromProcs

        sasl.logDebug("State from Procs = " .. stateFromProcs .. ", On Ground = " .. tostring(aircraftIsOnGround))
        if aircraftIsOnGround then
            if stateFromProcs == def.FLIGHTSTATEPREFLIGHT or
               stateFromProcs == def.FLIGHTSTATETAXITOGATE or
               stateFromProcs == def.FLIGHTSTATESHUTDOWN then
                stateIsPlausible = true
            end
        else
            if stateFromProcs == def.FLIGHTSTATEINITIALCLIMB or
               stateFromProcs == def.FLIGHTSTATECLIMB or
               stateFromProcs == def.FLIGHTSTATECRUISE or
               stateFromProcs == def.FLIGHTSTATEAPPROACH then
                stateIsPlausible = true
            end
        end

        if not stateIsPlausible then
            helpers.logInfoTS("State from procedures ("..stateFromProcs..") is implausible for current ground/air status (" .. (aircraftIsOnGround and "GROUND" or "AIR") .. "). Falling back.")
            if aircraftIsOnGround then
                if helpers.isParkingBrakeSet() then
                    finalState = def.FLIGHTSTATESHUTDOWN
                else
                    finalState = def.FLIGHTSTATETAXITOGATE
                end
            else
                local vs = get(P.verticalspeed) or 0
                if vs < -300 then
                    finalState = def.FLIGHTSTATEAPPROACH
                else
                    finalState = def.FLIGHTSTATECLIMB
                end
            end
            helpers.logInfoTS("State after fallback: " .. finalState)
        else
            sasl.logDebug("State from procedures ("..finalState..") is plausible.")
        end

        if finalState ~= currentFlightState then
             helpers.logInfoTS("Correcting flight state after reload. Old: " .. currentFlightState .. ", New: " .. finalState)
             P.flightstate = finalState
             flightStateChanged = true
        end

        if not aircraftIsOnGround then
             helpers.logInfoTS("Performing inflight restore actions after reload.")
             P.inflightrestoreactions()
        end

        P.isReloadWithinSession = false
    end

    currentFlightState = P.flightstate

    if aircraftIsOnGround then
        local taxiTriggerConditions = ((get(P.taxilight) ~= def.OFF) and P.enginesrunning(def.BOTH) and (get(P.groundspeed) < 45) and P.flightstate == def.FLIGHTSTATEPREFLIGHT)
        if taxiTriggerConditions then
            P.triggerprocedure(def.BEFORETAXIPROCEDURE)
        end

        local triggerConditionsMet_BTO = ((((P.aircraftonrwy(def.DEPARTURE, 40, 20) and (helpers.roundnumber(get(P.groundspeed)) == 0))) or (get(P.positionlights) == def.POSLIGHTSSTROBE)) and P.flightstate == def.FLIGHTSTATEPREFLIGHT)
        if triggerConditionsMet_BTO then
            P.triggerprocedure(def.BEFORETAKEOFFPROCEDURE)
        end
    
        local triggerConditionsMet_AL = (((get(P.groundspeed) < 45) and (P.aircraftonrwy(def.ARRIVAL, 40, 20) or (helpers.roundnumber(get(P.groundspeed)) == 0))) or (get(P.positionlights) == def.POSLIGHTSSTEADY))
        if triggerConditionsMet_AL and currentFlightState >= def.FLIGHTSTATEAPPROACH then
            P.triggerprocedure(def.AFTERLANDINGPROCEDURE)
        end


        local triggerConditionsMet_AP = helpers.isParkingBrakeSet() and (P.flightstate == def.FLIGHTSTATETAXITOGATE or P.flightstate == def.FLIGHTSTATESHUTDOWN)
        if triggerConditionsMet_AP then
            P.triggerprocedure(def.ATPARKINGPOSITIONPROCEDURE)
        end

    else
        local fmsPhase = get(P.fmsflightphase) or 0
        local targetFlightState = P.flightstate

        if ((fmsPhase >= def.FMSFLIGHTPHASE_DESCENT) and (get(P.vnavtoddist) <= 1)) then
            targetFlightState = def.FLIGHTSTATEAPPROACH
        elseif (fmsPhase == def.FMSFLIGHTPHASE_CRUISE) then
            targetFlightState = def.FLIGHTSTATECRUISE
        elseif (fmsPhase == def.FMSFLIGHTPHASE_CLIMB) and P.proceduretable[def.AFTERTAKEOFFPROCEDURE].set then
            targetFlightState = def.FLIGHTSTATECLIMB
        elseif (P.flightstate == def.FLIGHTSTATEPREFLIGHT) then
            targetFlightState = def.FLIGHTSTATEINITIALCLIMB
        end

        if targetFlightState > P.flightstate then
             P.flightstate = targetFlightState
             flightStateChanged = true
        end

        if P.flightstate == def.FLIGHTSTATEINITIALCLIMB then
            P.triggerprocedure(def.AFTERTAKEOFFPROCEDURE)
        elseif P.flightstate == def.FLIGHTSTATECLIMB then
            P.duringclimb()
        elseif P.flightstate == def.FLIGHTSTATEAPPROACH then
            P.duringdescent()
        end
    end

    if flightStateChanged then
        set(P.flightstatedr, P.flightstate)
        P.syncProceduresToFlightState()
        if P.flightstate < def.FLIGHTSTATEAPPROACH then
            P.ongoingpretaskindex = 3
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.updateSharedVariables()

    local depIcaoNow = helpers.cleanstring(get(P.depicao))
    if helpers.isvalidicao(depIcaoNow) and depIcaoNow ~= P.lastDepIcao then
        P.lastDepIcao = depIcaoNow
        helpers.getMetar(depIcaoNow, P.depmetar)
    end
    local desIcaoNow = helpers.cleanstring(get(P.desicao))
    if helpers.isvalidicao(desIcaoNow) and desIcaoNow ~= P.lastDesIcao then
        P.lastDesIcao = desIcaoNow
        helpers.getMetar(desIcaoNow, P.desmetar)
        -- Prioritize cabin landing altitude refresh right after destination changes.
        P.ongoingpretaskindex = 3
    end
    local nearestIcaoNow = helpers.extractprimaryicao(get(P.nearesticao) or "")
    if P.flightstate == def.FLIGHTSTATEPREFLIGHT and helpers.isvalidicao(nearestIcaoNow) then
        if nearestIcaoNow ~= P.lastNearIcao then
            P.lastNearIcao = nearestIcaoNow
            helpers.getMetar(nearestIcaoNow, P.nearmetar)
        end
    else
        P.lastNearIcao = ""
    end

    if ((get(P.desrwyheading) ~= P.desrwyheadingtemp) and (get(P.desrwyheading) ~= 0)) then
        P.desrwyheadingtemp = get(P.desrwyheading)
    end
    if ((get(P.desrwylatstartpos) ~= P.desrwylatstartpostemp) and (get(P.desrwylatstartpos) ~= 0)) then
        P.desrwylatstartpostemp = get(P.desrwylatstartpos)
    end
    if ((get(P.desrwylonstartpos) ~= P.desrwylonstartpostemp) and (get(P.desrwylonstartpos) ~= 0)) then
        P.desrwylonstartpostemp = get(P.desrwylonstartpos)
    end
    if ((get(P.desrwylatendpos) ~= P.desrwylatendpostemp) and (get(P.desrwylatendpos) ~= 0)) then
        P.desrwylatendpostemp = get(P.desrwylatendpos)
    end
    if ((get(P.desrwylonendpos) ~= P.desrwylonendpostemp) and (get(P.desrwylonendpos) ~= 0)) then
        P.desrwylonendpostemp = get(P.desrwylonendpos)
    end
end

--------------------------------------------------------------------------------------------------------------
function P.runOnePreOngoingTask()
    local idx = tonumber(P.ongoingpretaskindex) or 1
    if idx < 1 or idx > 3 then
        idx = 1
    end

    local cockpitInitLoop = P[def.PROCEDURELOOP .. P.proceduretable[def.COCKPITINITPROCEDURE].loop]
    if cockpitInitLoop and cockpitInitLoop.lock == def.COCKPITINITPROCEDURE then
        P.ongoingpretaskindex = idx + 1
        if P.ongoingpretaskindex > 3 then
            P.ongoingpretaskindex = 1
        end
        return
    end

    if idx == 1 then
        if P.enginesrunning(def.BOTH) and (P.configvalues[def.CONFIGAUTOCENTERTANKHANDLING] == def.ON) then
            if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.autocentertanks()
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                if ((get(P.centertanklbs) > 1000) and (get(P.centertanklpress) > 0) and (get(P.centertankrpress) > 0) and (get(P.centertankstat) > 0)) then
                    if ((get(P.centertanklswitch) == def.OFF) or (get(P.centertankrswitch) == def.OFF)) then
                        P.commandtableentry(def.TEXT, "Set Center Tank Fuel Pumps On")
                    end
                elseif ((get(P.centertanklbs) <= 1000)) or ((get(P.centertanklpress) == 0) and (get(P.centertankrpress) == 0)) then
                    if ((get(P.centertanklswitch) == def.ON) or (get(P.centertankrswitch) == def.ON)) then
                        P.commandtableentry(def.TEXT, "Set Center Tank Fuel Pumps Off")
                    end
                end
            end
        end
    elseif idx == 2 then
        if (P.flightstate < def.FLIGHTSTATECRUISE) and (get(P.fmccruisealt) ~= 0) and (get(P.fmccruisealt) ~= 20000) then
            local fmccruisealttmp = helpers.roundnumber(get(P.fmccruisealt) / 500) * 500
            if get(P.cabincruisealt) ~= fmccruisealttmp then
                if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    set(P.cabincruisealt, fmccruisealttmp)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Cabin Cruise Alitude " .. helpers.addspaces(fmccruisealttmp))
                end
            end
        end
    elseif idx == 3 then
        local destination_icao = string.upper(helpers.cleanstring(get(P.desicao) or ""))
        if (P.flightstate < def.FLIGHTSTATEAPPROACH) and helpers.isvalidicao(destination_icao) then
            local deslandingalttmp = 0
            local haslandingalt = false

            if P.airportdatatable[destination_icao] and P.airportdatatable[destination_icao].elevation_ft then
                deslandingalttmp = helpers.roundnumber(P.airportdatatable[destination_icao].elevation_ft / 50) * 50
                haslandingalt = true
            elseif get(P.desrwyalt) > -1000 then
                deslandingalttmp = helpers.roundnumber(get(P.desrwyalt) / 50) * 50
                haslandingalt = true
            end

            if haslandingalt then
                if deslandingalttmp < 0 then
                    deslandingalttmp = 0
                end
                if get(P.cabinlandingalt) ~= deslandingalttmp then
                    if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                        set(P.cabinlandingalt, deslandingalttmp)
                    elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        P.commandtableentry(def.TEXT, "Set Cabin Landing Altitude " .. helpers.addspaces(deslandingalttmp))
                    end
                end
            end
        end
    end

    P.ongoingpretaskindex = idx + 1
    if P.ongoingpretaskindex > 3 then
        P.ongoingpretaskindex = 1
    end
end

--------------------------------------------------------------------------------------------------------------
function P.runOneCoreOngoingTask()
    local idx = tonumber(P.ongoingcoretaskindex) or 4
    if idx < 4 or idx > 6 then
        idx = 4
    end

    if idx == 4 then
        if (P.configvalues[def.CONFIGAUTOANTIICE] == def.ON) then
            if (get(P.airgroundsensor) == def.ON) then
                local apu_bleed_ok = P.apurunning() and (get(P.apubleedpos) == def.ON)
                local eng_bleed_ok = P.enginesrunning() and ((get(P.eng1bleedpos) == def.ON) or (get(P.eng2bleedpos) == def.ON))
                local bleed_ok = apu_bleed_ok or eng_bleed_ok

                local dep_phase = (P.flightstate == def.FLIGHTSTATEPREFLIGHT)
                local arr_afterlanding = (P.flightstate == def.FLIGHTSTATEAFTERLANDING)
                local arr_taxi_to_gate = (P.flightstate == def.FLIGHTSTATETAXITOGATE)

                local wx
                if dep_phase then
                    wx = P.depmetar.decodedmetar
                else
                    wx = P.desmetar.decodedmetar
                end

                local tat_c = get(P.tatdegc)
                local ground_icing = helpers.isGroundIcingCondition(wx, tat_c)
                ground_icing = not not ground_icing

                local function anyAntiIceOn()
                    return (get(P.eng1heatpos) == def.ON) or (get(P.eng2heatpos) == def.ON) or (get(P.wingheatpos) == def.ON)
                end

                local function anyAntiIceOff()
                    return (get(P.eng1heatpos) == def.OFF) or (get(P.eng2heatpos) == def.OFF) or (get(P.wingheatpos) == def.OFF)
                end

                if dep_phase then
                    if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                        if ground_icing and bleed_ok then
                            P.iceprotection(def.ON)
                        else
                            P.iceprotection(def.OFF)
                        end
                    else
                        if ground_icing and bleed_ok then
                            if anyAntiIceOff() then
                                P.commandtableentry(def.TEXT, "Ground Icing Conditions, Switch Anti Icing On")
                            end
                        else
                            if anyAntiIceOn() then
                                P.commandtableentry(def.TEXT, "No Ground Icing Conditions, Switch Anti Icing Off")
                            end
                        end
                    end

                elseif arr_afterlanding then
                    if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                        if ground_icing and bleed_ok then
                            P.iceprotection(def.ON)
                        end
                    else
                        if ground_icing and bleed_ok then
                            if anyAntiIceOff() then
                                P.commandtableentry(def.TEXT, "Icing Conditions After Landing, Switch Anti Icing On")
                            end
                        end
                    end

                elseif arr_taxi_to_gate then
                    if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                        if ground_icing and bleed_ok then
                            P.iceprotection(def.ON)
                        else
                            P.iceprotection(def.OFF)
                        end
                    else
                        if ground_icing and bleed_ok then
                            if anyAntiIceOff() then
                                P.commandtableentry(def.TEXT, "Icing Conditions Taxi In, Switch Anti Icing On")
                            end
                        else
                            if anyAntiIceOn() then
                                P.commandtableentry(def.TEXT, "No Icing Conditions Taxi In, Switch Anti Icing Off")
                            end
                        end
                    end
                end

            else
                if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON)
                and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then

                    if ((get(P.frameice) > 0.01) and (get(P.altitude) < 30000)) then
                        P.iceprotection(def.ON)
                    elseif ((get(P.altitude) > 30000) or (get(P.tatdegc) > 10)) then
                        P.iceprotection(def.OFF)
                    end

                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then

                    if ((get(P.frameice) > 0.01) and (get(P.altitude) < 30000)) then
                        if ((get(P.eng1heatpos) == def.OFF) or (get(P.eng2heatpos) == def.OFF) or (get(P.wingheatpos) == def.OFF)) then
                            P.commandtableentry(def.TEXT, "Caution Icing Detected, Switch Anti Icing On")
                        end
                    elseif (get(P.altitude) > 30000) then
                        if ((get(P.eng1heatpos) == def.ON) or (get(P.eng2heatpos) == def.ON) or (get(P.wingheatpos) == def.ON)) then
                            P.commandtableentry(def.TEXT, "Above 30000 Feet, Switch Anti Icing Off")
                        end
                    elseif (get(P.tatdegc) > 10) then
                        if ((get(P.eng1heatpos) == def.ON) or (get(P.eng2heatpos) == def.ON) or (get(P.wingheatpos) == def.ON)) then
                            P.commandtableentry(def.TEXT, "T A T above 10 degree, Switch Anti Icing Off")
                        end
                    end
                end
            end
        end
    elseif idx == 5 then
        if (P.configvalues[def.CONFIGAUTOWIPER] == def.ON) then
            local groundspeed = get(P.groundspeed)
            local wipersOn = (get(P.lwiperpos) ~= def.WIPEROFF) or (get(P.rwiperpos) ~= def.WIPEROFF)

            if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                if (groundspeed > 250) then
                    P.autowiper(def.OFF)
                elseif ((P.apurunning() == def.APUONBUS) or (get(P.gen1pos) == def.ON) or (get(P.gen2pos) == def.ON)) then
                    P.autowiper(def.ON)
                elseif ((P.apurunning() < def.APUONBUS) and (get(P.gen1pos) == def.OFF) and (get(P.gen2pos) == def.OFF)) then
                    P.autowiper(def.OFF)
                end
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                if (groundspeed > 250) and wipersOn then
                    P.commandtableentry(def.TEXT, "Wipers On above 250 knots - set Off")
                end
            end
        end
    elseif idx == 6 then
        if ((get(P.airgroundsensor) == def.ON) and (P.procedureloop1.lock == def.NOPROCEDURE) and (get(P.battery) == def.ON) and (get(P.mainbus) ~= def.OFF) and (P.flightstate == def.FLIGHTSTATEPREFLIGHT) and (get(P.taxilight) == def.OFF)) then
            if ((P.configvalues[def.CONFIGAUTOBARO] == def.ON) and (get(P.groundspeed) < 45)) then
                local baroinchtmp, baropastmp = P.getlocalqnh(def.DEPARTURE)
                if (helpers.roundnumber(math.abs(helpers.roundnumber(get(P.baropilot), 2) - baroinchtmp), 2) > 0.01) then
                    if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                        set(P.baropilot, baroinchtmp)
                    elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        local qnhText = nil
                        if (get(P.baroinhpa) == def.ON) then
                            qnhText = helpers.formatQnhValue(baropastmp, true)
                        else
                            qnhText = helpers.formatQnhValue(baroinchtmp, false)
                        end
                        if qnhText then
                            P.commandtableentry(def.TEXT, "Set Q N H " .. helpers.addspaces(qnhText))
                        end
                    end
                end
            end
        end
    end

    P.ongoingcoretaskindex = idx + 1
    if P.ongoingcoretaskindex > 6 then
        P.ongoingcoretaskindex = 4
    end
end

--------------------------------------------------------------------------------------------------------------
function P.runOneMainOngoingTask()
    local idx = tonumber(P.ongoingtaskstepindex) or 7
    if idx < 7 or idx > 11 then
        idx = 7
    end
    local holdCurrent = false

    local preflightGateOpen =
        (get(P.airgroundsensor) == def.ON) and
        (P.procedureloop1.lock == def.NOPROCEDURE) and
        (get(P.battery) == def.ON) and
        (get(P.mainbus) ~= def.OFF) and
        (P.flightstate == def.FLIGHTSTATEPREFLIGHT) and
        (get(P.taxilight) == def.OFF)

    local takeoffReadinessGuardOpen =
        (get(P.airgroundsensor) == def.ON) and
        (get(P.battery) == def.ON) and
        (get(P.mainbus) ~= def.OFF) and
        (P.flightstate == def.FLIGHTSTATEPREFLIGHT) and
        (get(P.groundspeed) < 45) and
        (
            (P.procedureloop1.lock == def.BEFORETAKEOFFPROCEDURE)
            or ((P.proceduretable[def.BEFORETAKEOFFPROCEDURE] ~= nil) and P.proceduretable[def.BEFORETAKEOFFPROCEDURE].set)
            or (get(P.positionlights) == def.POSLIGHTSSTROBE)
            or P.aircraftonrwy(def.DEPARTURE, 40, 20)
        )
    local trimAdviceGuardOpen = preflightGateOpen or takeoffReadinessGuardOpen

    if trimAdviceGuardOpen then
        if idx == 7 then
            local trimTarget = getLatchedTrimTarget() or 0
            local trimPopupFeatureEnabled =
                (P.configvalues[def.CONFIGTRIMADVICEPOPUP] == def.ON)
                and (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)
            local trimMismatch = (trimTarget > 0) and (not helpers.trimwheel_matches_trim_step(get(P.trimwheel), trimTarget, 0.25) and (get(P.groundspeed) < 45))
            local trimPopupAutoActive =
                trimPopupFeatureEnabled
                and trimAdviceGuardOpen
                and trimTarget > 0
                and (trimMismatch or (P.trimAdvicePopupState and P.trimAdvicePopupState.active == true and P.trimAdvicePopupState.pinned ~= true))
            if trimAdviceGuardOpen and trimTarget > 0 and (trimPopupAutoActive or P._trimAdvicePopupPinned) then
                setTrimAdvicePopupState(trimTarget, P._trimAdvicePopupPinned == true)
            else
                clearTrimAdvicePopupState()
            end
            if trimMismatch then
                if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                    P.settotrim(trimTarget)
                    local trimText = helpers.format_trim_quarter(trimTarget) or tostring(trimTarget)
                    P.commandtableentry(def.TEXT, "Trim " .. trimText)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    local trimText = helpers.format_trim_quarter(trimTarget) or tostring(trimTarget)
                    P.commandtableentry(def.TEXT, "Set Trim " .. trimText)
                end
            end
        elseif idx == 8 then
            if ((get(P.v2speed) > 0) and (get(P.v2speed) ~= get(P.mcpspeed)) and (get(P.groundspeed) < 45)) then
                if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                    set(P.mcpspeed, get(P.v2speed))
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set M C P Speed " .. helpers.addspaces(get(P.v2speed)))
                end
            end
        elseif idx == 9 then
            local headingrounded = nil
            if (helpers.isvalidicao(get(P.depicao)) and helpers.isvalidrwy(get(P.deprwy)) and tonumber(get(P.deprwyheading))) then
                headingrounded = helpers.roundnumber(get(P.deprwyheading))
            end
            if (headingrounded and (headingrounded ~= get(P.mcpheading)) and (get(P.groundspeed) < 45)) then
                if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                    set(P.mcpheading, headingrounded)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3)))
                end
            end
        end
    elseif idx == 7 then
        idx = 10
    end

    do
        local latchedTrimTarget = tonumber(P._ongoingTrimTargetLatched) or 0
        local trimPopupAllowed =
            (P.configvalues[def.CONFIGTRIMADVICEPOPUP] == def.ON) and
            (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)
        local popupState = P.trimAdvicePopupState
        local popupHoldUntilTs = popupState and tonumber(popupState.holdUntilTs) or 0
        local popupHoldActive = popupHoldUntilTs > getTrimPopupNowSec()
        if ((not trimAdviceGuardOpen) or (latchedTrimTarget <= 0)) and (not popupHoldActive) then
            P._trimAdvicePopupPinned = false
            clearTrimTargetLatch()
            clearTrimAdvicePopupState()
        elseif (not trimPopupAllowed) and (not P._trimAdvicePopupPinned) and (not popupHoldActive) then
            clearTrimAdvicePopupState()
        end
    end

    if idx == 10 then
        local todDistance = get(P.vnavtoddist)
        local aircraftInAir = (get(P.airgroundsensor) == def.OFF)
        local radioAltitude = get(P.radioaltitude)
        local suppressDiscoWarnings =
            (P.flightstate == def.FLIGHTSTATEAPPROACH) and
            radioAltitude and (radioAltitude >= 0) and (radioAltitude < 1000)
        local flightStateEligible =
            (P.flightstate == def.FLIGHTSTATECLIMB) or
            (P.flightstate == def.FLIGHTSTATECRUISE) or
            (P.flightstate == def.FLIGHTSTATEAPPROACH)
        local mcpAlt = get(P.mcpaltitude) or 0

        if P.pauseTodMonitorActive then
            if get(P.pausetod) ~= def.ON then
                P.pauseTodMonitorActive = false
                P.pauseTodMcpAltAtPrompt = nil
            elseif (type(P.pauseTodMcpAltAtPrompt) == "number") and (math.abs(mcpAlt - P.pauseTodMcpAltAtPrompt) >= 100) then
                set(P.pausetod, def.OFF)
                P.pauseTodAutoDisabled = true
                P.pauseTodMonitorActive = false
                P.pauseTodMcpAltAtPrompt = nil
            end
        end

        if aircraftInAir and flightStateEligible and not suppressDiscoWarnings then
            if (not todDistance) or (todDistance <= 0) then
                local remainingDistance, _, onRoute = helpers.getRemainingRouteDistance(
                    get(P.fmslegs),
                    get(P.fmslegslat),
                    get(P.fmslegslon),
                    get(P.aircraftlatpos),
                    get(P.aircraftlonpos)
                )
                local distDest = get(P.distdest)

                if remainingDistance and distDest and (remainingDistance > 0) and (distDest > 0) then
                    if onRoute == true then
                        local diff = distDest - remainingDistance
                        if diff > 50 then
                            if not P.routeEndsEarlyWarned then
                                P.commandtableentry(def.TEXT, "Warning: Route may end too early. Check Arrival / Approach setup.")
                                P.routeEndsEarlyWarned = true
                            end
                        else
                            P.routeEndsEarlyWarned = false
                        end
                    else
                        P.routeEndsEarlyWarned = false
                    end
                end
            else
                P.routeEndsEarlyWarned = false
            end
        else
            P.routeEndsEarlyWarned = false
        end

        if todDistance and todDistance > 0 and aircraftInAir and not suppressDiscoWarnings then
            local discontinuity = helpers.detectFMSDiscontinuity(
                get(P.fmslegs),
                get(P.fmslegslat),
                get(P.fmslegslon),
                get(P.aircraftlatpos),
                get(P.aircraftlonpos),
                { maxAheadNm = 20 }
            )
            if discontinuity then
                local prevLegText = ""
                if discontinuity.previous then
                    prevLegText = " after " .. helpers.replaceRunwayPrefix(discontinuity.previous)
                end

                if (get(P.fmccruisealt) or 0) > 0 then
                    if todDistance <= 10 and not P.todDiscontinuityWarned10 then
                        P.commandtableentry(def.TEXT, "Warning: Route still contains a Discontinuity" .. prevLegText .. " about 10 NM before Top of Descent")
                        P.todDiscontinuityWarned10 = true
                    elseif todDistance <= 30 and not P.todDiscontinuityWarned30 then
                        P.commandtableentry(def.TEXT, "Warning: Route still contains a Discontinuity" .. prevLegText .. " about 30 NM before Top of Descent")
                        P.todDiscontinuityWarned30 = true
                    end
                end
            else
                P.todDiscontinuityWarned30 = false
                P.todDiscontinuityWarned10 = false
            end

            if todDistance > 40 then
                P.todDiscontinuityWarned30 = false
                P.todDiscontinuityWarned10 = false
            end

            local routeCheckEligible =
                (P.flightstate == def.FLIGHTSTATECRUISE) or
                (P.flightstate == def.FLIGHTSTATEAPPROACH)

            local routeWarningTolerance = 5

            if routeCheckEligible and todDistance and todDistance > routeWarningTolerance then
                local remainingDistance, _, onRoute = helpers.getRemainingRouteDistance(
                    get(P.fmslegs),
                    get(P.fmslegslat),
                    get(P.fmslegslon),
                    get(P.aircraftlatpos),
                    get(P.aircraftlonpos)
                )

                local hasRemaining = remainingDistance and remainingDistance > 0 and onRoute == true
                local distDest = get(P.distdest)
                local hasDestDistance = distDest and distDest > 0

                if hasRemaining then
                    if todDistance > (remainingDistance + routeWarningTolerance) then
                        if not P.routeEndsEarlyWarned then
                            P.commandtableentry(def.TEXT, "Warning: Route may end before Top of Descent, check Arrival setup")
                            P.routeEndsEarlyWarned = true
                        end
                    elseif P.routeEndsEarlyWarned and todDistance <= (remainingDistance + routeWarningTolerance * 0.2) then
                        P.routeEndsEarlyWarned = false
                    end
                elseif hasDestDistance then
                    if todDistance > (distDest + routeWarningTolerance) then
                        if not P.routeEndsEarlyWarned then
                            P.commandtableentry(def.TEXT, "Warning: Route may end before Top of Descent, check Arrival setup")
                            P.routeEndsEarlyWarned = true
                        end
                    elseif P.routeEndsEarlyWarned and todDistance <= (distDest + routeWarningTolerance * 0.2) then
                        P.routeEndsEarlyWarned = false
                    end
                else
                    P.routeEndsEarlyWarned = false
                end
            else
                P.routeEndsEarlyWarned = false
            end
        else
            P.todDiscontinuityWarned30 = false
            P.todDiscontinuityWarned10 = false
            P.routeEndsEarlyWarned = false
        end

        if (P.flightstate == def.FLIGHTSTATECRUISE) and (get(P.fmsflightphase) == def.FMSFLIGHTPHASE_CRUISE) and not suppressDiscoWarnings then
            local fmcCruiseAlt = get(P.fmccruisealt) or 0
            local fmcCruiseRounded = helpers.roundnumber(fmcCruiseAlt / 100, 0) * 100
            local withinTolerance = (mcpAlt >= (fmcCruiseRounded - 100))
            if withinTolerance and (get(P.vnavtoddist) < 20) then
                local queueTodAdvice, todAdviceReason = shouldQueueStandaloneVoiceAdvice(
                    P.todResetMcpAdviceState,
                    "TOD_RESET_MCP_ALTITUDE",
                    "Approaching Top of Descent, Reset M C P Altitude"
                )
                if queueTodAdvice then
                    P.commandtableentry(def.TEXT, "Approaching Top of Descent, Reset M C P Altitude")
                    if (get(P.pausetod) == def.ON) and (not P.pauseTodAutoDisabled) and (not P.pauseTodMonitorActive) then
                        P.pauseTodMonitorActive = true
                        P.pauseTodMcpAltAtPrompt = mcpAlt
                    end
                elseif todAdviceReason == "max-reached" then
                    holdCurrent = true
                end
                holdCurrent = true
            else
                resetVoiceAdviceRepeatState(P.todResetMcpAdviceState)
            end
        else
            resetVoiceAdviceRepeatState(P.todResetMcpAdviceState)
        end
    end

    if idx == 11 then
        local skipReason = nil
        if (P.flightstate == def.FLIGHTSTATECRUISE) and (get(P.fmsflightphase) == def.FMSFLIGHTPHASE_CRUISE) and (get(P.totalfuellbs) < 1000) then
            local reservefuelLbs = 5000

            if P.YANSHisinstalled() and P.YANSHflightplanloaded() and P.YANSHFuelReserve and get(P.YANSHFuelReserve) > 0 and P.YANSHFuelAlternateBurn and get(P.YANSHFuelAlternateBurn) > 0 and P.YANSHParamsUnitsFlag then
                local yanshReserveRaw = get(P.YANSHFuelReserve)
                local yanshAlternateRaw = get(P.YANSHFuelAlternateBurn)
                local yanshReserveLbs = yanshReserveRaw
                local yanshAlternateLbs = yanshAlternateRaw

                if get(P.YANSHParamsUnitsFlag) == def.YANSHUNITKGS then
                    yanshReserveLbs = yanshReserveRaw * def.KGTOLBS
                    yanshAlternateLbs = yanshAlternateRaw * def.KGTOLBS
                end
                reservefuelLbs = yanshReserveLbs + yanshAlternateLbs
            end

            local distanceToTODNM = get(P.vnavtoddist)
            if type(distanceToTODNM) ~= "number" or distanceToTODNM <= 0 then
                local distDest = get(P.distdest)
                if type(distDest) == "number" and distDest > 0 then
                    distanceToTODNM = distDest
                else
                    skipReason = "skip (no ToD or destination distance)"
                end
            end

            if not skipReason then
                local requiredfuellbs = P.calculateRequiredFuelNow(distanceToTODNM, reservefuelLbs)
                local currentTotal = get(P.totalfuellbs) or 0
                if type(requiredfuellbs) ~= "number" or requiredfuellbs <= 0 then
                    skipReason = "skip (invalid required fuel)"
                elseif requiredfuellbs <= currentTotal then
                    skipReason = "skip (required <= current)"
                else
                    P.refuelAircraft(requiredfuellbs)
                end
            end
        end

        if skipReason then
            if P.refuelFailsafeReason ~= skipReason then
                helpers.logInfoTS("Refuel failsafe: " .. tostring(skipReason))
                P.refuelFailsafeReason = skipReason
            end
        else
            P.refuelFailsafeReason = nil
        end
    end

    if not holdCurrent then
        idx = idx + 1
    end

    if idx > 11 then
        idx = 7
    end
    P.ongoingtaskstepindex = idx
end

--------------------------------------------------------------------------------------------------------------
function P.ongoingtasks()

    local current_level = sasl.getLogLevel()

    if current_level ~= P.lastPolledDebugLevel then

        set(P.debugLevelDataref, current_level)
        if P.xluaLoggingEnabled then
            set(P.xluaLoggingEnabled, current_level == LOG_DEBUG and 1 or 0)
        end
        if P.hoppie and P.hoppie.debug_level and isProperty(P.hoppie.debug_level) then
            local hop_level = current_level == LOG_DEBUG and 3 or 1
            set(P.hoppie.debug_level, hop_level)
        end
        P.lastPolledDebugLevel = current_level
        sasl.logDebug("Debug level change detected by poll. Saved to dataref: " .. current_level)
    end

    checkAutoRestart()
    checkHoppieVoiceMessages()

    if (P.updatemetartimer == nil) then
        P.updatemetartimer = sasl.createTimer()
        sasl.startTimer(P.updatemetartimer)
        P.updatemetar()
    elseif (sasl.getElapsedSeconds(P.updatemetartimer) > 300) then
        P.updatemetar()
        sasl.startTimer(P.updatemetartimer)
    end

    if (not P.windshieldIcingStarted) then
        local icyCondition = (get(P.windowiceunheated) > 0)
        if icyCondition then
            local coldAndDark = (get(P.battery) == def.OFF) and (get(P.airgroundsensor) == def.ON)
            if coldAndDark then
                if not P.windshieldIcingApplied then
                    set(P.windowiceaddeddelta, def.ZIBOWINDSHIELDICEDELTA)
                    P.windshieldIcingApplied = true
                end
            else
                P.windshieldIcingStarted = true
            end
        end
    end

    if (P.configvalues[def.CONFIGRUNWAYFRICTIONCLAMP] == def.ON) then
        P.applyRunwayFrictionClamp()
    elseif P.runwayFrictionAdjusted ~= nil then
        P.runwayFrictionAdjusted = nil
        P.runwayFrictionSeen = nil
    end

    if ((P.apgoaroundtemp ~= get(P.apgoaround)) and (get(P.apgoaround) == def.ON)) then

        local aircraftOnGround = (get(P.airgroundsensor) == def.ON)
        local radioAlt = get(P.radioaltitude) or 0
        if (P.flightstate == def.FLIGHTSTATEAPPROACH) and not aircraftOnGround and (radioAlt < 2500) then
            -- Trigger dedicated Go-Around procedure if loop is free
            local gaLoopIndex = P.proceduretable[def.GOAROUNDPROCEDURE].loop
            if P.loopStateTables[gaLoopIndex] and P.loopStateTables[gaLoopIndex].lock == def.NOPROCEDURE then
                helpers.logInfoTS("Go Around: triggering Go Around procedure on Loop " .. tostring(gaLoopIndex) .. ".")
                P.triggerprocedure(def.GOAROUNDPROCEDURE)
            else
                helpers.logInfoTS("Go Around: Go Around procedure not triggered (loop busy).")
            end
        else
            sasl.logDebug("Go Around detected but conditions not met (state/air/alt).")
        end

        P.apgoaroundtemp = get(P.apgoaround)
    end

    local todDistanceQuit = get(P.vnavtoddist)
    local todEligibleQuit =
        (P.pauseTodMonitorActive == true) and
        (get(P.airgroundsensor) == def.OFF) and
        (type(todDistanceQuit) == "number") and
        (todDistanceQuit > 0) and
        (todDistanceQuit <= 5)
    if ((get(P.pausetod) == def.ON) and (P.configvalues[def.CONFIGTODPAUSEQUITTIME] ~= 9999) and todEligibleQuit) then
        if (get(P.simpaused) == def.ON) then
            if (P.pausetodtimer == nil) then
                P.pausetodtimer = sasl.createTimer()
                sasl.startTimer(P.pausetodtimer)
            elseif (sasl.getElapsedSeconds(P.pausetodtimer) > P.configvalues[def.CONFIGTODPAUSEQUITTIME]) then
                helpers.command_once("laminar/B738/tab/save_flight" .. tostring(getAutoSaveSlot()))
                helpers.command_once("sim/operation/quit")
            end
        elseif (P.pausetodtimer ~= nil) then
            sasl.stopTimer(P.pausetodtimer)
            P.pausetodtimer = nil
        end
    elseif (P.pausetodtimer ~= nil) then
        sasl.stopTimer(P.pausetodtimer)
        P.pausetodtimer = nil
    end

    if not isPeriodicAutoSaveDisabled() then
        if (P.savetimer == nil) then
            P.savetimer = sasl.createTimer()
            sasl.startTimer(P.savetimer)
        elseif (sasl.getElapsedSeconds(P.savetimer) > P.configvalues[def.CONFIGSAVETIME]) then
            helpers.command_once("laminar/B738/tab/save_flight" .. tostring(getAutoSaveSlot()))
            sasl.startTimer(P.savetimer)
        end
    elseif (P.savetimer ~= nil) then
        sasl.stopTimer(P.savetimer)
        P.savetimer = nil
    end

    local headingSyncInterval = tonumber(P.configvalues[def.CONFIGHEADINGSYNCINTERVAL] or 0) or 0
    if headingSyncInterval > 0 then
        if (P.headingsynctimer == nil) then
            P.headingsynctimer = sasl.createTimer()
            sasl.startTimer(P.headingsynctimer)
        elseif (sasl.getElapsedSeconds(P.headingsynctimer) >= headingSyncInterval) then
            local inAir = (get(P.airgroundsensor) == def.OFF)
            local apOn = (get(P.aponstat) == def.ON)
            local lateralCaptured = (get(P.aploccapturedstat) >= def.CAPTURED)
                or (get(P.aplpvloccapturedstat) >= def.CAPTURED)
                or (get(P.apglsloccapturedstat) >= def.CAPTURED)
                or (get(P.apfacloccapturedstat) >= def.CAPTURED)
            local headingSetByProc = false
            local raProc = P.proceduretable and P.proceduretable[def.RADIOALTITUDEB1000PROCEDURE]
            local raLoopIdx = raProc and raProc.loop
            local raLoop = (raLoopIdx and P.loopStateTables and P.loopStateTables[raLoopIdx]) or nil
            if raLoop and raLoop.mcpHeadingSet == true then
                headingSetByProc = true
            end
            if raLoop and raLoop.mcpHeadingSet ~= nil and (get(P.airgroundsensor) == def.ON) then
                raLoop.mcpHeadingSet = nil
            end
            local blockHeadingSync = headingSetByProc or lateralCaptured
            if inAir and apOn and (get(P.aphdgselstat) == def.OFF) and (not blockHeadingSync) then
                P.headingsync()
            end
            sasl.startTimer(P.headingsynctimer)
        end
    elseif (P.headingsynctimer ~= nil) then
        sasl.stopTimer(P.headingsynctimer)
        P.headingsynctimer = nil
    end

    -- Taxi routing update (runs in ongoingtasks so it is independent of the taxi window)
    if P.taxiComponent and P.taxiComponent.updateTaxiState then
        local onGround = (get(P.airgroundsensor) == def.ON)
        local taxiPhase = (P.flightstate == def.FLIGHTSTATEPREFLIGHT)
            or (P.flightstate == def.FLIGHTSTATETAXITOGATE)
            or (P.flightstate == def.FLIGHTSTATESHUTDOWN)
        local taxiActive = (P.taxiComponent.hasActiveGuidance and P.taxiComponent:hasActiveGuidance()) or false
        local winVisible = (P.taxiComponent.isWindowVisible and P.taxiComponent:isWindowVisible()) or false
        if onGround and (taxiPhase or taxiActive) and (not winVisible) then
            P.taxiComponent:updateTaxiState()
        end
    end

    local groundspeed = get(P.groundspeed) or 0
    local onDepartureRunway = P.aircraftonrwy and P.aircraftonrwy(def.DEPARTURE, 40, 20)
    local onArrivalRunway = P.aircraftonrwy and P.aircraftonrwy(def.ARRIVAL, 40, 20)
    if (get(P.airgroundsensor) == def.ON) and (groundspeed > 45) then
        -- Departure taxi: warn if fast while not yet on the departure runway.
        if (P.flightstate == def.FLIGHTSTATEPREFLIGHT) and (not onDepartureRunway) then
            P.commandtableentry(def.TEXT, "Monitor Taxi Speed")
        end
        -- Arrival taxi: warn if fast after vacating/misaligned from the landing runway.
        if (P.flightstate == def.FLIGHTSTATETAXITOGATE) and onArrivalRunway then
            P.commandtableentry(def.TEXT, "Monitor Taxi Speed")
        end
    end

    if ((P.procedureloop1.lock == def.NOPROCEDURE) and (get(P.airgroundsensor) == def.OFF) and (P.flightstate == def.FLIGHTSTATECLIMB)) then
        if ((math.abs(get(P.altitude) - P.configvalues[def.CONFIGLOWEAIRSPACEALT]) < 100) and (get(P.fmccruisealt) > P.configvalues[def.CONFIGLOWEAIRSPACEALT]) and (get(P.apvnavaltmode) == def.ON)) then
            if (P.altitudetimer == nil) then
                P.altitudetimer = sasl.createTimer()
                sasl.startTimer(P.altitudetimer)
            elseif (sasl.getElapsedSeconds(P.altitudetimer) > 600) then
                local message = "Check M C P Altitude and V N A V Mode"
                local fmcCruiseAlt = get(P.fmccruisealt)
                if P.YANSHisinstalled() and P.YANSHflightplanloaded() and P.YANSHGeneralInitialAltitude and get(P.YANSHGeneralInitialAltitude) > 0 then
                    local initialAlt = get(P.YANSHGeneralInitialAltitude)
                    local additionalInfo = ". Planned initial cruise altitude was " .. initialAlt
                    if fmcCruiseAlt > 0 and fmcCruiseAlt ~= initialAlt then
                        additionalInfo = additionalInfo .. ", current is " .. fmcCruiseAlt
                    end
                    message = message .. additionalInfo .. " feet."
                elseif fmcCruiseAlt > 0 then
                    message = message .. ". Planned cruise altitude is " .. fmcCruiseAlt .. " feet."
                end
                P.commandtableentry(def.TEXT, message)
                sasl.startTimer(P.altitudetimer)
            end
        elseif (P.altitudetimer ~= nil) then
            sasl.stopTimer(P.altitudetimer)
            P.altitudetimer = nil
        end
    elseif (P.altitudetimer ~= nil) then
        sasl.stopTimer(P.altitudetimer)
        P.altitudetimer = nil
    end

    do
        local inAir = (get(P.airgroundsensor) == def.OFF)
        local flightState = P.flightstate or 0
        local fmsPhase = get(P.fmsflightphase) or 0
        local currentAlt = get(P.altitude) or 0
        local lowAirspaceAlt = tonumber(P.configvalues[def.CONFIGLOWEAIRSPACEALT] or 0) or 0
        local fmcCruiseAlt = helpers.roundnumber((get(P.fmccruisealt) or 0) / 100, 0) * 100
        local mcpAlt = helpers.roundnumber((get(P.mcpaltitude) or 0) / 100, 0) * 100
        local cruiseGap = fmcCruiseAlt - mcpAlt
        local likelyTypoMismatch =
            (fmcCruiseAlt > lowAirspaceAlt) and
            (mcpAlt > lowAirspaceAlt) and
            (cruiseGap >= (def.CRUISE_ALT_MISMATCH_FT - def.CRUISE_ALT_MISMATCH_TOLERANCE_FT)) and
            (cruiseGap <= (def.CRUISE_ALT_MISMATCH_FT + def.CRUISE_ALT_MISMATCH_TOLERANCE_FT))
        local climbOrCruise =
            (flightState == def.FLIGHTSTATECLIMB) or
            (flightState == def.FLIGHTSTATECRUISE) or
            (fmsPhase == def.FMSFLIGHTPHASE_CLIMB) or
            (fmsPhase == def.FMSFLIGHTPHASE_CRUISE) or
            (fmsPhase == def.FMSFLIGHTPHASE_CRZ_CLB)
        local nearSelectedLevel = currentAlt >= math.max(lowAirspaceAlt, mcpAlt - def.CRUISE_ALT_MISMATCH_ARM_BAND_FT)
        local vnavAltActive = (get(P.apvnavaltmode) == def.ON)
        local guardEligible = inAir and climbOrCruise and likelyTypoMismatch and nearSelectedLevel

        if guardEligible then
            local mismatchKey = tostring(fmcCruiseAlt) .. ":" .. tostring(mcpAlt)
            local now = os.time()
            if P.cruiseAltMismatchKey ~= mismatchKey then
                P.cruiseAltMismatchKey = mismatchKey
                P.cruiseAltMismatchFirstSeenAt = now
                P.cruiseAltMismatchLastWarnAt = nil
                P.cruiseAltMismatchVnavAltWarned = false
            elseif P.cruiseAltMismatchFirstSeenAt == nil then
                P.cruiseAltMismatchFirstSeenAt = now
            end

            local shouldWarn = false
            local urgentWarn = false
            if vnavAltActive and (not P.cruiseAltMismatchVnavAltWarned) then
                shouldWarn = true
                urgentWarn = true
            elseif (P.cruiseAltMismatchFirstSeenAt ~= nil) and ((now - P.cruiseAltMismatchFirstSeenAt) >= def.CRUISE_ALT_MISMATCH_GRACE_SEC) then
                if (P.cruiseAltMismatchLastWarnAt == nil) or ((now - P.cruiseAltMismatchLastWarnAt) >= def.CRUISE_ALT_MISMATCH_REPEAT_SEC) then
                    shouldWarn = true
                end
            end

            if shouldWarn then
                local message
                if urgentWarn then
                    message = "V N A V Alt active. Check M C P altitude. Planned cruise altitude is " .. helpers.addspaces(fmcCruiseAlt) .. " feet. M C P altitude is " .. helpers.addspaces(mcpAlt) .. " feet."
                    P.cruiseAltMismatchVnavAltWarned = true
                else
                    message = "Check M C P altitude. Planned cruise altitude is " .. helpers.addspaces(fmcCruiseAlt) .. " feet. M C P altitude is " .. helpers.addspaces(mcpAlt) .. " feet."
                end
                helpers.logInfoTS(string.format("CruiseAltGuard: fmc=%d mcp=%d alt=%d vnavAlt=%s", fmcCruiseAlt, mcpAlt, currentAlt, tostring(vnavAltActive)))
                P.commandtableentry(def.TEXT, message)
                P.cruiseAltMismatchLastWarnAt = now
            end
        else
            P.cruiseAltMismatchKey = nil
            P.cruiseAltMismatchFirstSeenAt = nil
            P.cruiseAltMismatchLastWarnAt = nil
            P.cruiseAltMismatchVnavAltWarned = false
        end
    end

    local airGroundSensor = get(P.airgroundsensor)
    if airGroundSensor ~= nil and airGroundSensor == def.ON and P.flightstate == def.FLIGHTSTATEPREFLIGHT then

        if P.procedureloop1 and P.procedureloop1.lock == def.NOPROCEDURE then
            local voiceAdviceSetting = P.configvalues and P.configvalues[def.CONFIGVOICEADVICEONLY]
            if voiceAdviceSetting == def.ON then

                local battery = get(P.battery)
                local posLights = get(P.positionlights)
                local parkBrakeSet = helpers.isParkingBrakeSet()
                local starter1 = get(P.starter1pos)
                local starter2 = get(P.starter2pos)
                local beaconLights = get(P.beaconlights)
                local leftTankL = get(P.lefttanklswitch)
                local leftTankR = get(P.lefttankrswitch)
                local rightTankL = get(P.righttanklswitch)
                local rightTankR = get(P.righttankrswitch)
                local packL = get(P.packlpos)
                local packR = get(P.packrpos)
                local apuBleed = get(P.bleedairapupos)
                local isolValve = get(P.isolvalvepos)
                local eng1N2 = get(P.eng1n2percent)
                local eng2N2 = get(P.eng2n2percent)
                local mixture1 = get(P.mixture1pos)
                local mixture2 = get(P.mixture2pos)
                local apuStatus = P.apurunning()
                local gen1 = get(P.gen1pos)
                local gen2 = get(P.gen2pos)
                local apuPowerBus1 = get(P.apupowerbus1)
                local apuPowerBus2 = get(P.apupowerbus2)
                local sourceOff1 = get(P.announcsourceoff1)
                local sourceOff2 = get(P.announcsourceoff2)
                local enginesRunningBoth = P.enginesrunning(P.BOTH)
                local bleed1 = get(P.bleedair1pos)
                local bleed2 = get(P.bleedair2pos)
                local apuSupplyingPower = ((apuPowerBus1 == def.ON) and (sourceOff1 == def.OFF))
                    or ((apuPowerBus2 == def.ON) and (sourceOff2 == def.OFF))
                local normalBleedConfig = enginesRunningBoth and (bleed1 == def.ON) and (bleed2 == def.ON)
                    and (apuBleed == def.OFF)
                    and (isolValve == def.ISOLVALVEAUTO)
                local engineGenPowerReady = (gen1 == def.ON) and (gen2 == def.ON)

                if battery == def.ON and posLights ~= nil and posLights ~= def.POSLIGHTSSTEADY and parkBrakeSet then
                    P.commandtableentry(def.TEXT, "Set Position Lights Steady")
                elseif ((starter1 == def.GROUND or starter2 == def.GROUND)) and beaconLights == def.OFF then
                    P.commandtableentry(def.TEXT, "Set Collision Lights On")
                elseif (apuStatus ~= nil and apuStatus > def.APUOFF and leftTankL == def.OFF) then
                    P.commandtableentry(def.TEXT, "Set Left After Fuel Pump On for A P U")
                elseif ((starter1 == def.GROUND or starter2 == def.GROUND)) and (leftTankL == def.OFF or leftTankR == def.OFF or rightTankL == def.OFF or rightTankR == def.OFF) then
                    P.commandtableentry(def.TEXT, "Set Wing Tank Fuel Pumps On")
                elseif ((starter1 == def.GROUND or starter2 == def.GROUND)) and (packL ~= nil and packL ~= def.PACKOFF or packR ~= nil and packR ~= def.PACKOFF) then
                    P.commandtableentry(def.TEXT, "Set Both Packs Off")
                elseif ((starter1 == def.GROUND or starter2 == def.GROUND)) and apuBleed ~= nil and apuBleed ~= def.ON then
                    P.commandtableentry(def.TEXT, "Set A P U Bleed Air On")
                elseif starter2 == def.GROUND and isolValve ~= nil and isolValve ~= def.ISOLVALVEOPEN then
                    P.commandtableentry(def.TEXT, "Set Isolation Valve Open")
                elseif starter1 == def.GROUND and eng1N2 ~= nil and eng1N2 > 25 and mixture1 == def.OFF then
                    P.commandtableentry(def.TEXT, "Engine 1 N 2 at 25 Percent")
                elseif starter2 == def.GROUND and eng2N2 ~= nil and eng2N2 > 25 and mixture2 == def.OFF then
                    P.commandtableentry(def.TEXT, "Engine 2 N 2 at 25 Percent")
                elseif apuStatus ~= nil and apuStatus == def.APUOFFBUS and gen1 == def.OFF and gen2 == def.OFF then -- Corrected gen1/gen2 check
                    P.commandtableentry(def.TEXT, "Switch A P U Generator On")
                elseif (apuBleed == def.OFF and apuStatus ~= nil and apuStatus > def.APUSTARTED and enginesRunningBoth ~= nil and ((not enginesRunningBoth) or (enginesRunningBoth and bleed1 == def.OFF and bleed2 == def.OFF))) then
                    P.commandtableentry(def.TEXT, "Set A P U Bleedair On")
                elseif (isolValve ~= nil and isolValve ~= def.ISOLVALVEOPEN and apuStatus ~= nil and apuStatus > def.APUSTARTED and enginesRunningBoth ~= nil and not(enginesRunningBoth and bleed2 == def.ON)) then
                    P.commandtableentry(def.TEXT, "Set Isolation Valve Open")
                elseif (apuBleed == def.ON and enginesRunningBoth and (bleed1 == def.ON or bleed2 == def.ON)) then
                    P.commandtableentry(def.TEXT, "Set A P U Bleedair Off")
                elseif (isolValve ~= nil and isolValve ~= def.ISOLVALVEAUTO and enginesRunningBoth and (bleed1 == def.ON or bleed2 == def.ON)) then
                    P.commandtableentry(def.TEXT, "Set Isolation Valve Auto")
                elseif normalBleedConfig and engineGenPowerReady and apuSupplyingPower then
                    P.commandtableentry(def.TEXT, "Set A P U Generator Off")
                elseif normalBleedConfig and engineGenPowerReady and apuStatus ~= nil and apuStatus > def.APUOFF and not apuSupplyingPower then
                    P.commandtableentry(def.TEXT, "Set A P U Off")
                end
            end
        end

        maybeQueueTakeoffN140Callout()
    end

    P.runOnePreOngoingTask()
    P.runOneCoreOngoingTask()
    P.runOneMainOngoingTask()

    if P.OngoingTaskIndexdr then
        set(P.OngoingTaskIndexdr, P.ongoingtaskstepindex)
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

local function isViewCommandPath(path)
    if type(path) ~= "string" then
        return false
    end
    if path == "sim/view/default_view" then
        return true
    end
    if string.find(path, "sim/view/quick_look_", 1, true) == 1 then
        return true
    end
    if string.find(path, "SRS/X-Camera/Select_View_ID_", 1, true) == 1 then
        return true
    end
    return false
end

local function viewCommandAllowedNow()
    if P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON then
        return false
    end
    if get(P.airgroundsensor) == def.OFF then
        return true
    end
    if get(P.tirespeed) < 1 then
        return true
    end
    if P.BPBStarted and isProperty(P.BPBStarted) and get(P.BPBStarted) == def.ON then
        return true
    end
    return false
end

function P.commandtableloop()

    local next_recommended_wait_step = def.STANDARDWAIT

    local processedentry = false
    P.lastCommandWasSpeech = false
    local voice_enabled = ((P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) or (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON))

    while ((#P.commandtable > 0) and (processedentry == false)) do

        if (P.commandtable[1][1] == def.COMMAND) then
            local command_path = P.commandtable[1][2]
            helpers.logInfoTS("COMMAND: " .. tostring(command_path))

            local suppressViewCommand = isViewCommandPath(command_path) and (not viewCommandAllowedNow())
            if suppressViewCommand then
                helpers.logInfoTS("View command suppressed: " .. tostring(command_path))
            else
                local command_handle = sasl.findCommand(command_path)
                if command_handle then
                    sasl.commandOnce(command_handle)
                else
                    sasl.logWarning("Command not found: " .. tostring(command_path))
                end
            end
            table.remove(P.commandtable, 1)
        else
            local entry_index = 1
            if voice_enabled then
                local last_taxi_index = nil
                for i = 1, #P.commandtable do
                    if P.commandtable[i][1] == def.TAXI then
                        last_taxi_index = i
                    end
                end
                if last_taxi_index then
                    entry_index = last_taxi_index
                    for i = last_taxi_index - 1, 1, -1 do
                        if P.commandtable[i][1] == def.TAXI then
                            table.remove(P.commandtable, i)
                            entry_index = entry_index - 1
                        end
                    end
                end
            end
            local entry_type = P.commandtable[entry_index][1]
            local entry_text = P.commandtable[entry_index][2]
            if (entry_type == def.TEXT) or (entry_type == def.TAXI) then
                if entry_type == def.TEXT and entry_text == TAKEOFF_N1_40_MESSAGE and not isTakeoffN140CalloutEligible() then
                    helpers.logInfoTS("SpeakString TEXT dropped stale: " .. tostring(entry_text))
                    table.remove(P.commandtable, entry_index)
                    processedentry = true
                    goto continue_commandtableloop
                end
                if voice_enabled then
                    maybeRequestTrimAdvicePopupForSpeech(entry_type, entry_text)
                    if entry_type == def.TAXI then
                        helpers.logInfoTS("SpeakString TAXI: " .. tostring(entry_text))
                    else
                        helpers.logInfoTS("SpeakString TEXT: " .. tostring(entry_text))
                    end
                    helpers.speak(entry_text)
                    P.lastCommandWasSpeech = true
                    if (string.len(entry_text) > def.VERYLONGSPEAK) then
                        next_recommended_wait_step = def.LONGWAIT
                    elseif (string.len(entry_text) > def.LONGSPEAK) then
                        next_recommended_wait_step = def.MEDIUMWAIT
                    end
                    processedentry = true
                end
            end
            table.remove(P.commandtable, entry_index)
        end

        ::continue_commandtableloop::

    end

    return next_recommended_wait_step

end

--------------------------------------------------------------------------------------------------------------
function P.runProcedureLoop(loopIndex)
    local P = yal
    local loop = P.loopStateTables[loopIndex]

    sasl.logDebug("!!! START runProcedureLoop(" .. loopIndex .. ") - IN-MEMORY STATE: Lock=" .. tostring(loop.lock) .. ", StepName=" .. tostring(loop.currentStepName) .. ", State=" .. tostring(loop.stepindex))

    -- Sicherstellen, dass loop.lock einen gültigen Index hat oder NOPROCEDURE ist
    if loop.lock == nil then loop.lock = def.NOPROCEDURE end
    local procData = P.proceduretable[loop.lock] -- procData kann nil sein, wenn lock=NOPROCEDURE
    local transition_occurred = false -- Flag für erkannte Zustandsübergänge

    sasl.logDebug("=== runProcedureLoop(" .. loopIndex .. ") - Lock: " .. tostring(loop.lock) .. " ===")

    -- Wenn kein Lock, Zustand zurücksetzen und speichern
    if (loop.lock == def.NOPROCEDURE) then
        sasl.logDebug("Loop " .. loopIndex .. " is not locked. Resetting transient flags and saving clean persistent state.")
        P.resetLoopState(loop)
        P.saveLoopState(loop, loopIndex)
        return true
    end

    -- Update der letzten Aktivitätszeit
    loop.lastActiveTime = os.time()
    local timestring = os.date("%H:%M:%S", loop.lastActiveTime)
    sasl.logDebug("Loop " .. loopIndex .. " locked with ProcID: " .. loop.lock .. ", StepName: " .. tostring(loop.currentStepName) .. ", A-State: " .. loop.stepindex)
    local prevStepName = loop.currentStepName

    -- ## 1. GEMEINSAME CHECKS ##
    if not procData then
        -- Dieser Fall sollte eigentlich durch den NOPROCEDURE-Check oben abgedeckt sein,
        -- aber zur Sicherheit:
        sasl.logDebug("Procedure " .. tostring(loop.lock) .. " not found! Aborting.")
        loop.procedureabort = true
    else
        -- A) Check Allowed State (führt zu hartem Abbruch)
        local aircraftIsOnGround = (get(P.airgroundsensor) == def.ON)
        local allowedState = procData.allowedState
        if (allowedState == def.GROUNDONLY and not aircraftIsOnGround) or
           (allowedState == def.AIRONLY and aircraftIsOnGround) then
            helpers.logInfoTS("Aborting '" .. procData.name .. "' due to invalid aircraft state.")
            loop.procedureabort = true
            -- Hier KEIN goto/return, der Abbruch wird unten behandelt

        -- B) Check Transition Conditions (führt zu "soft skip" mit set=true)
        elseif procData.transitionConditions then
            for _, transCond in ipairs(procData.transitionConditions) do
                if transCond.condition() then
                    helpers.logInfoTS("Skipping '" .. procData.name .. "' due to met transition condition.")

                    local transition_message = procData.name .. " Procedure skipped."
                    P.commandtableentry(def.TEXT, transition_message)

                    -- 1. Prozedur als erledigt markieren
                    P.proceduretable[loop.lock].set = true
                    set(P.ProcSetStatusarraydr, 1, loop.lock)

                    -- 2. Loop zurücksetzen
                    loop.lock = def.NOPROCEDURE

                    -- 3. Flag setzen und Schleife verlassen
                    transition_occurred = true
                    break -- Verlässt die for-Schleife
                end
            end -- Ende for-Schleife (transitionConditions)
        end -- Ende elseif procData.transitionConditions
    end -- Ende if not procData / else Block

    -- ==========================================================
    -- Führe Engine nur aus, wenn weder
    -- ein Abbruch noch ein Übergang stattgefunden hat.
    -- ==========================================================
    if not loop.procedureabort and not transition_occurred then

        -- ## 2. ENGINE LOGIC (Nur noch Engine A) ##
        if procData and procData.steps and type(procData.steps) == "table" then
            sasl.logDebug("Using Engine A (Data-Driven) for ProcID " .. loop.lock)
            local useViewChanges = (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) -- Beibehalten für view step
            local useAdviceOnly = (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)

            -- A1. PREREQUISITE CHECKS (nur beim ersten Schritt)
            if loop.stepindex == 0 then
                sasl.logDebug("Engine A - Running Prerequisite Checks (stepindex == 0)")
                -- *** FIX msg START ***
                if procData.speakname then
                    local proc_name_text = procData.name .. " Procedure"
                    if type(proc_name_text) == "string" then P.commandtableentry(def.TEXT, proc_name_text) end
                end
                 -- *** FIX msg END ***
                helpers.logInfoTS(procData.name .. " Procedure (Data-Driven) started at " .. timestring)

                if procData.prerequisiteChecks then
                    for i, prereq in ipairs(procData.prerequisiteChecks) do
                        sasl.logDebug("Checking Prereq #" .. i)
                        if not prereq.check(P) then
                            sasl.logDebug("Prereq #" .. i .. " FAILED.")
                             -- *** FIX msg START ***
                            if prereq.failMsg and type(prereq.failMsg) == "string" and prereq.failMsg ~= "" then
                                P.commandtableentry(def.TEXT, prereq.failMsg)
                            end
                             -- *** FIX msg END ***
                            loop.procedurenotpossible = true
                            if prereq.setonabort then loop.setonabort = true end
                            break
                        else
                            sasl.logDebug("Prereq #" .. i .. " PASSED.")
                        end
                    end -- Ende for prereq
                end -- Ende if procData.prerequisiteChecks

                if not loop.procedurenotpossible then
                    sasl.logDebug("All Prerequisites PASSED. Setting stepindex=1, currentStepName=" .. tostring(procData.startStep))
                    loop.stepindex = 1
                    loop.currentStepName = procData.startStep
                    loop.lastStepName = nil
                else
                    sasl.logDebug("Prerequisite failed. loop.procedurenotpossible=true")
                end
            end -- Ende if loop.stepindex == 0

            -- A2. ABBRUCH-HANDLING (für interne Fehler oder Prereqs)
            if loop.procedureabort or loop.procedurenotpossible then
                local msg_abort
                if loop.procedurenotpossible then
                    msg_abort = "Procedure Not Possible"
                elseif loop.procedureskipped then
                    msg_abort = "Procedure Skipped"
                else
                    msg_abort = "Procedure Aborted"
                end
                sasl.logDebug("Engine A - Handling Abort/NotPossible. Message: " .. msg_abort)
                if loop.procedureabort then
                      -- *** FIX msg START ***
                    local abort_text = procData.name .. " " .. msg_abort
                    if type(abort_text) == "string" and abort_text ~= "" then
                        P.commandtableentry(def.TEXT, abort_text)
                    end
                     -- *** FIX msg END ***
                end
                helpers.logInfoTS(procData.name .. " " .. msg_abort .. " at " .. timestring)

                if loop.setonabort then
                    sasl.logDebug("Setting procedure " .. loop.lock .. " as completed due to setonabort flag.")
                    P.proceduretable[loop.lock].set = true
                    set(P.ProcSetStatusarraydr, 1, loop.lock)
                end
                sasl.logDebug("Resetting loop lock.")
                loop.lock = def.NOPROCEDURE

            -- A3. SKIP-HANDLING (Benutzeraktion)
            elseif loop.procedureskipstep then
                sasl.logDebug("Engine A - Handling Skip Step.")
                P.commandtableentry(def.TEXT, "Procedure Step Skipped") -- Sicher, da String-Literal
                loop.procedureskipstep = false
                local currentStepData = procData.steps[loop.currentStepName]
                if currentStepData and currentStepData.nextStep then
                    sasl.logDebug("Skipping to nextStep: " .. tostring(currentStepData.nextStep))
                    loop.currentStepName = currentStepData.nextStep
                    loop.lastStepName = nil -- Reset lastStepName damit skipIf/view wieder funktionieren
                else
                    sasl.logDebug("Skipping at end or no nextStep defined. Setting currentStepName=nil.")
                    loop.currentStepName = nil -- Führt zum Prozedur-Ende
                end

            -- A4. PROZEDUR-ENDE (normal)
            elseif loop.currentStepName == nil and loop.stepindex == 1 then
                sasl.logDebug("Engine A - Procedure End detected (currentStepName == nil and stepindex == 1).")
                if procData.speakname then
                      -- *** FIX msg START ***
                    local complete_text = procData.name .. " Procedure Complete"
                    if type(complete_text) == "string" and complete_text ~= "" then
                        P.commandtableentry(def.TEXT, complete_text)
                    end
                     -- *** FIX msg END ***
                end
                helpers.logInfoTS(procData.name .. " Procedure completed at " .. timestring)
                P.proceduretable[loop.lock].set = true
                set(P.ProcSetStatusarraydr, 1, loop.lock)
                sasl.logDebug("Resetting loop lock.")
                loop.lock = def.NOPROCEDURE
                loop.stepindex = 0 -- Zurücksetzen für den nächsten Lauf

            -- A4b. Reload-Fall (ungültiger Zustand)
            elseif loop.currentStepName == nil and loop.stepindex > 0 then
                sasl.logWarning("Engine A - Reload detected (currentStepName == nil and stepindex > 0). Resetting loop.")
                loop.lock = def.NOPROCEDURE
                loop.stepindex = 0

            -- A5. ENGINE-HAUPTTEIL (Schritte abarbeiten)
            elseif loop.stepindex == 1 then
                local stepName = loop.currentStepName
            sasl.logDebug("Engine A - Processing Step: '" .. tostring(stepName) .. "'")
            local step = procData.steps[stepName]
            if loop.stepOnceRequested and loop.stepOnceTargetStep and loop.stepOnceTargetStep ~= stepName then
                helpers.logInfoTS("Step Once cancelled: step changed from '" .. tostring(loop.stepOnceTargetStep) .. "' to '" .. tostring(stepName) .. "'")
                loop.stepOnceRequested = false
                loop.stepOnceTargetStep = nil
            end

            if not step then
                sasl.logDebug("Procedure " .. procData.name .. " failed: Step '" .. tostring(stepName) .. "' is nil! Aborting.")
                loop.procedureabort = true
            else
                -- Debug pause / step-through
                if loop.debugPaused then
                    if loop.debugStepOnce then
                        loop.debugStepOnce = false -- execute this step once
                    else
                        sasl.logDebug("Debug pause active, holding on step '" .. tostring(stepName) .. "'")
                        return true
                    end
                end
                -- Breakpoint hit?
                if loop.debugBreakpoints and loop.debugBreakpoints[stepName] then
                    loop.debugPaused = true
                    loop.debugStepOnce = false
                    helpers.logInfoTS("Debug breakpoint hit at step '" .. tostring(stepName) .. "'")
                    return true
                end

                -- 5a. Step Repeat Logik
                if stepName == loop.lastStepName then loop.steprepeat = true else loop.steprepeat = false end
                loop.lastStepName = stepName
                sasl.logDebug("steprepeat=" .. tostring(loop.steprepeat))

                    -- *** FMC PAGE GRACE-SKIP (FMCAUTOMATION OFF) ***
                    if loop.fmcPageSkipStep and loop.fmcPageSkipStep ~= stepName then
                        loop.fmcPageSkipStep = nil
                        loop.fmcPageSkipAt = nil
                    end
                    local fmcAutomationOn = (P.configvalues[def.CONFIGFMCAUTOMATION] == def.ON)
                    local didFmcSkip = false
                    if step.fmcPage and not fmcAutomationOn then
                        local now = os.time()
                        if loop.fmcPageSkipStep ~= stepName then
                            loop.fmcPageSkipStep = stepName
                            loop.fmcPageSkipAt = now
                        end
                        local elapsed = now - (loop.fmcPageSkipAt or now)
                        if elapsed >= 1 then
                            sasl.logDebug("FMC automation OFF. Skipping FMC page step after grace: " .. tostring(stepName))
                            if step.branch then
                                local nextStepNameFromBranch = step.branch(loop, procData)
                                if type(nextStepNameFromBranch) == "string" then
                                    loop.currentStepName = nextStepNameFromBranch
                                elseif nextStepNameFromBranch == true then
                                    sasl.logDebug("Branch handled progression itself during FMC skip.")
                                elseif nextStepNameFromBranch == nil then
                                    loop.procedurenotpossible = true
                                    loop.currentStepName = nil
                                else
                                    loop.currentStepName = step.nextStep
                                end
                            else
                                loop.currentStepName = step.nextStep
                            end
                            loop.lastStepName = nil
                            loop.fmcPageSkipStep = nil
                            loop.fmcPageSkipAt = nil
                            didFmcSkip = true
                        end
                    end

                    -- *** NEUE VIEW-OPTIMIERUNG START ***

                    -- Definiere die Step-Typen
                    local isPureViewStep = step.view and not step.check and not step.action and not step.branch and step.nextStep
                    local isViewBranchStep = step.view and not step.check and not step.action and step.branch

                    if didFmcSkip then
                        -- FMC skip handled progression; do nothing else this cycle.
                    elseif not useViewChanges and (isPureViewStep or isViewBranchStep) then
                        -- OPTIMIERUNG AKTIV (Views sind AUS und es ist ein reiner View-Step)

                        if isPureViewStep then
                            -- Fall 1: Purer View-Step (view + nextStep)
                            -- Überspringe direkt zum nextStep
                            sasl.logDebug("View changes OFF. Skipping pure view step to: " .. tostring(step.nextStep))
                            loop.currentStepName = step.nextStep
                            loop.lastStepName = nil -- Wichtig für den nächsten Schritt
                            P.viewSkipRequested = true

                        else -- Muss isViewBranchStep sein
                            -- Fall 2: View + Branch Step (view + branch)
                            -- Führe die branch-Funktion aus, um den nächsten Schritt zu ermitteln
                            sasl.logDebug("View changes OFF. Skipping view+branch step. Executing branch...")
                            local nextStepNameFromBranch = step.branch(loop, procData)
                            sasl.logDebug("Branch (during skip) returned: " .. tostring(nextStepNameFromBranch))

                            -- Verarbeite das Ergebnis der branch-Funktion
                            if type(nextStepNameFromBranch) == "string" then
                                loop.currentStepName = nextStepNameFromBranch
                            elseif nextStepNameFromBranch == true then
                                sasl.logDebug("Branch handled progression itself during skip.")
                            elseif nextStepNameFromBranch == nil then
                                loop.procedurenotpossible = true
                                sasl.logDebug("Branch signaled procedure not possible during skip.")
                                loop.currentStepName = nil -- Stellt sicher, dass Prozedur endet
                            else
                                loop.currentStepName = step.nextStep -- Fallback (wird nil sein)
                                sasl.logDebug("Branch returned unexpected value, proceeding to default nextStep (nil).")
                            end
                            loop.lastStepName = nil -- Wichtig für den nächsten Schritt
                            P.viewSkipRequested = true
                        end
                        -- Ende der Optimierungslogik für diesen Zyklus

                    else

                    -- *** ORIGINAL-LOGIK (OHNE View-Skip-Optimierung) WIEDERHERGESTELLT ***
                        if step.skipIf and step.skipIf(loop, procData) then -- 5b. skipIf
                            sasl.logDebug("skipIf condition met. Skipping to step: " .. tostring(step.nextStep))
                            loop.currentStepName = step.nextStep
                            loop.lastStepName = nil -- Damit skipIf/view im nächsten Schritt wieder funktionieren

                        elseif useViewChanges and step.view and P.setview(step.view(loop, procData), (step.normalize == true)) then -- 5d. view (Modifiziert für Normalisierung)
                            sasl.logDebug("View changed. Repeating step '" .. stepName .. "' in next cycle.")
                            loop.lastStepName = nil -- Erzwingt, dass steprepeat = false ist

                        else -- 5e. Kernlogik (mit msg-Fix)
                            sasl.logDebug("Entering core logic (check/branch/action/advice).")
                            if step.check then
                                sasl.logDebug("Step has a check function.")
                                if step.check(loop, procData) then
                                    sasl.logDebug("Check PASSED.")
                                    -- *** FIX FÜR msg-ERROR ANWENDEN (confirm) ***
                                    local skipConfirm = (loop.skipConfirmForStep == stepName)
                                    if skipConfirm then
                                        sasl.logDebug("Skipping confirmation for step '" .. tostring(stepName) .. "' due to auto action.")
                                        loop.skipConfirmForStep = nil
                                    elseif step.confirm and (not useAdviceOnly or not loop.steprepeat or step.ensureConfirmInAdviceMode) then
                                        local confirm_msg_raw
                                        if type(step.confirm) == "function" then
                                            confirm_msg_raw = step.confirm(loop, procData)
                                        else
                                            confirm_msg_raw = step.confirm
                                        end
                                        -- Nur hinzufügen, wenn es ein gültiger String ist
                                        if type(confirm_msg_raw) == "string" and confirm_msg_raw ~= "" then
                                            P.commandtableentry(def.TEXT, confirm_msg_raw)
                                            sasl.logDebug("Confirmation message: " .. confirm_msg_raw)
                                        end
                                    end
                                    -- Ende confirm Fix
                                    if loop.skipConfirmForStep == stepName then
                                        loop.skipConfirmForStep = nil
                                    end

                                    if step.branch then
                                        sasl.logDebug("Executing branch function (after successful check).")
                                        local nextStepName = step.branch(loop, procData)
                                        sasl.logDebug("Branch returned: " .. tostring(nextStepName))
                                        if type(nextStepName) == "string" then loop.currentStepName = nextStepName
                                        elseif nextStepName == true then sasl.logDebug("Branch handled progression.")
                                        elseif nextStepName == nil then loop.procedurenotpossible = true; sasl.logDebug("Branch signaled procedure not possible.")
                                        else loop.currentStepName = step.nextStep; sasl.logDebug("Branch returned unexpected value, proceeding to default nextStep: " .. tostring(step.nextStep))
                                        end
                                    else
                                        sasl.logDebug("No branch function, proceeding to default nextStep: " .. tostring(step.nextStep))
                                        loop.currentStepName = step.nextStep
                                    end
                                else -- Check FAILED
                                    sasl.logDebug("Check FAILED.")
                                    local branchResult = nil
                                    local branchExecuted = false
                                    if step.branch then
                                        sasl.logDebug("Executing branch function (after failed check).")
                                        branchResult = step.branch(loop, procData)
                                        branchExecuted = true
                                        sasl.logDebug("Branch returned: " .. tostring(branchResult))
                                    else
                                        sasl.logDebug("No branch function defined for this step.")
                                    end

                                    if branchExecuted and branchResult == nil then
                                        loop.procedurenotpossible = true;
                                        sasl.logDebug("Branch EXPLICITLY returned nil, signaling procedure not possible.")
                                    elseif branchResult == false then
                                        sasl.logDebug("Branch returned false. Staying on step. Issuing advice/action.")
                                        if useAdviceOnly then
                                            -- *** FIX FÜR msg-ERROR ANWENDEN (advice nach failed check+branch=false) ***
                                            if step.advice then
                                                local advice_msg_raw
                                                if type(step.advice) == "function" then
                                                    advice_msg_raw = step.advice(loop, procData)
                                                else
                                                    advice_msg_raw = step.advice
                                                end
                                                 -- Nur hinzufügen, wenn es ein gültiger String ist
                                                if type(advice_msg_raw) == "string" and advice_msg_raw ~= "" then
                                                    local queueAdvice, adviceReason = P.shouldQueueVoiceAdvice(loop, stepName, advice_msg_raw)
                                                    if queueAdvice then
                                                        P.commandtableentry(def.TEXT, advice_msg_raw)
                                                        sasl.logDebug("Advice message: " .. advice_msg_raw)
                                                    elseif adviceReason == "max-reached" then
                                                        loop.procedureskipstep = true
                                                        helpers.logInfoTS("Voice advice max repeats reached, skipping step '" .. tostring(stepName) .. "'")
                                                    else
                                                        sasl.logDebug("Advice message skipped by repeat throttle: " .. advice_msg_raw)
                                                    end
                                                end
                                            end
                                            local allowStepOnce = loop.stepOnceRequested and (loop.stepOnceTargetStep == stepName)
                                            if step.action and (step.runActionInAdviceMode or allowStepOnce) then
                                                 step.action(loop, procData);
                                                 if allowStepOnce then
                                                    loop.stepOnceRequested = false
                                                    loop.stepOnceTargetStep = nil
                                                    loop.skipConfirmForStep = stepName
                                                    helpers.logInfoTS("Step Once executed for step '" .. tostring(stepName) .. "'")
                                                 else
                                                    sasl.logDebug("Executed 'runActionInAdviceMode' action.")
                                                 end
                                            end
                                            -- Ende advice Fix
                                        else
                                            if step.action then
                                                step.action(loop, procData)
                                                loop.skipConfirmForStep = stepName
                                                sasl.logDebug("Executed action.")
                                            end
                                        end
                                    elseif type(branchResult) == "string" then
                                        sasl.logDebug("Branch returned next step name: " .. branchResult)
                                        loop.currentStepName = branchResult
                                    elseif branchResult == true then
                                        sasl.logDebug("Branch returned true, handled progression.")
                                    else -- Default behavior (No branch or unexpected return)
                                        sasl.logDebug("Default behavior. Staying on step. Issuing advice/action.")

                                        if useAdviceOnly then
                                            -- *** ADVICE ONLY MODE ***

                                            -- 1. Advice sprechen (wenn vorhanden und nicht wiederholt)
                                            if step.advice then
                                                local advice_msg_raw
                                                if type(step.advice) == "function" then
                                                    advice_msg_raw = step.advice(loop, procData)
                                                else
                                                    advice_msg_raw = step.advice
                                                end
                                                if type(advice_msg_raw) == "string" and advice_msg_raw ~= "" then
                                                    local queueAdvice, adviceReason = P.shouldQueueVoiceAdvice(loop, stepName, advice_msg_raw)
                                                    if queueAdvice then
                                                        P.commandtableentry(def.TEXT, advice_msg_raw)
                                                        sasl.logDebug("Advice message: " .. advice_msg_raw)
                                                    elseif adviceReason == "max-reached" then
                                                        loop.procedureskipstep = true
                                                        helpers.logInfoTS("Voice advice max repeats reached, skipping step '" .. tostring(stepName) .. "'")
                                                    else
                                                        sasl.logDebug("Advice message skipped by repeat throttle: " .. advice_msg_raw)
                                                    end
                                                end
                                            end

                                            -- 2. Action AUSNAHMSWEISE ausführen (wenn geflaggt und nicht wiederholt)
                                            local allowStepOnce = loop.stepOnceRequested and (loop.stepOnceTargetStep == stepName)
                                            if step.action and (step.runActionInAdviceMode or allowStepOnce) then
                                                 step.action(loop, procData);
                                                 if allowStepOnce then
                                                    loop.stepOnceRequested = false
                                                    loop.stepOnceTargetStep = nil
                                                    loop.skipConfirmForStep = stepName
                                                    helpers.logInfoTS("Step Once executed for step '" .. tostring(stepName) .. "'")
                                                 else
                                                    sasl.logDebug("Executed 'runActionInAdviceMode' action (on first fail).")
                                                 end
                                            end

                                        else
                                            -- *** AUTO MODE ***
                                            -- Führe Action aus (wie in deiner Original-Logik, bei jedem Fehlschlag)
                                            if step.action then
                                                step.action(loop, procData)
                                                loop.skipConfirmForStep = stepName
                                                sasl.logDebug("Executed action (Auto Mode).")
                                            end
                                        end
                                    end -- Ende Default behavior
                                end -- Ende Check FAILED
                            else -- Step has NO check function
                                sasl.logDebug("Step has NO check function.")
                                if step.branch then
                                    sasl.logDebug("Executing branch function (no check).")
                                    local nextStepName = step.branch(loop, procData)
                                    sasl.logDebug("Branch returned: " .. tostring(nextStepName))
                                    if type(nextStepName) == "string" then loop.currentStepName = nextStepName
                                    elseif nextStepName == true then sasl.logDebug("Branch handled progression.")
                                    elseif nextStepName == nil then loop.procedurenotpossible = true; sasl.logDebug("Branch signaled procedure not possible.")
                                    else loop.currentStepName = step.nextStep; sasl.logDebug("Branch returned unexpected value, proceeding to default nextStep: " .. tostring(step.nextStep))
                                    end
                                else
                                    sasl.logDebug("No branch function. Executing action (if any) and proceeding to default nextStep: " .. tostring(step.nextStep))
                                    if step.action and not loop.steprepeat then step.action(loop, procData); sasl.logDebug("Executed action.") end

                                    if step.confirm and (not useAdviceOnly or not loop.steprepeat or step.ensureConfirmInAdviceMode) then
                                        local confirm_msg_raw
                                        if type(step.confirm) == "function" then
                                            confirm_msg_raw = step.confirm(loop, procData)
                                        else
                                            confirm_msg_raw = step.confirm
                                        end
                                        -- Nur hinzufügen, wenn es ein gültiger String ist
                                        if type(confirm_msg_raw) == "string" and confirm_msg_raw ~= "" then
                                            P.commandtableentry(def.TEXT, confirm_msg_raw)
                                            sasl.logDebug("Confirmation message (no-check step): " .. confirm_msg_raw)
                                        end
                                    end
                                    -- *** ENDE NEU ***
                                    loop.currentStepName = step.nextStep
                                end
                            end -- Ende if step.check / else
                            sasl.logDebug("After core logic, next currentStepName is: " .. tostring(loop.currentStepName))
                        end -- Ende der Kernlogik (5e) / elseif skipIf / elseif view
                        -- *** ENDE DER ORIGINAL-LOGIK ***
                    end
                end -- Ende "if not step"
            end -- Ende "elseif loop.stepindex == 1" (Engine Hauptteil)

        -- Fallback: Ungültige Prozedurdefinition
        elseif procData then
             sasl.logDebug("Procedure " .. tostring(loop.lock) .. " has no valid 'steps' table! Aborting.")
             loop.procedureabort = true
             loop.lock = def.NOPROCEDURE
        end -- Ende if/elseif Engine A / Fallback

    -- ==========================================================
    -- Behandlung für frühe Abbrüche (z.B. durch allowedState ODER manuellen Abort)
    -- ==========================================================
    elseif loop.procedureabort then
        helpers.logInfoTS("Procedure aborted (likely manual or state change before engine). Resetting loop lock.") -- Bleibt Info fürs Log

        -- *** NEU: Meldung für den Benutzer hinzufügen ***
        local abort_label = loop.procedureskipped and "Procedure Skipped" or "Procedure Aborted"
        if procData and procData.name then -- Sicherstellen, dass wir einen Namen haben
             local abort_message = procData.name .. " " .. abort_label
             P.commandtableentry(def.TEXT, abort_message)
        else
             -- Fallback, falls procData aus irgendeinem Grund nil ist
             P.commandtableentry(def.TEXT, abort_label)
        end
        -- *** ENDE NEU ***

        if procData and loop.setonabort then
             sasl.logDebug("Setting procedure " .. loop.lock .. " as completed due to setonabort flag during early abort.")
             P.proceduretable[loop.lock].set = true
             set(P.ProcSetStatusarraydr, 1, loop.lock)
        end
        loop.lock = def.NOPROCEDURE
        -- Flags zurücksetzen, da Abbruch behandelt wurde
        loop.procedureabort = false
        loop.procedureskipped = false
        loop.procedurenotpossible = false
        loop.setonabort = false
    -- Der Fall transition_occurred wird implizit behandelt, da loop.lock bereits NOPROCEDURE ist
    end -- Ende if not loop.procedureabort and not transition_occurred / elseif loop.procedureabort

    -- ## 3. POST-PROCESSING (History + Speichern) ##
    local function pushDebugHistory(loopTbl, fromStep, toStep, reason)
        loopTbl.debugHistory = loopTbl.debugHistory or {}
        loopTbl.debugHistory[#loopTbl.debugHistory + 1] = {
            from = fromStep,
            to = toStep,
            reason = reason
        }
        if #loopTbl.debugHistory > 25 then
            table.remove(loopTbl.debugHistory, 1)
        end
    end
    if loop.lock ~= def.NOPROCEDURE then
        local fromStep = prevStepName
        local toStep = loop.currentStepName
        if fromStep ~= toStep then
            pushDebugHistory(loop, fromStep, toStep, loop.lastTransitionReason or "")
        end
    end

    -- Das Speichern läuft jetzt immer am Ende.
    if loop.lock == def.NOPROCEDURE then
        sasl.logDebug("Loop " .. loopIndex .. " was reset or finished. Resetting transient flags and saving clean persistent state.")
        P.resetLoopState(loop)
    elseif loop.lock ~= def.NOPROCEDURE then
         sasl.logDebug("Saving loop " .. loopIndex .. " state - Lock: " .. loop.lock .. ", StepName: " .. tostring(loop.currentStepName) .. ", State: " .. loop.stepindex)
    end

    P.saveLoopState(loop, loopIndex)

    sasl.logDebug("=== runProcedureLoop(" .. loopIndex .. ") - END ===")

    return true
end -- Ende function P.runProcedureLoop

--------------------------------------------------------------------------------------------------------------
function P.do_yal()

    if settings.newSettingsAvailable then
        P.readconfig()
        helpers.logInfoTS("Loading new settings")
    end

    if P.needstempinit then
        P.initializeSharedVariables()
        if (P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) then
            VR.initialize(P)
        end
        P.needstempinit = false
    end

    if P.needsPostStartupDatarefRebind then
        local missingCount = P.bindExternalDatarefs(true)
        P.needsPostStartupDatarefRebind = false
        P.externalDatarefsPostStartupDone = true
        if missingCount > 0 then
            helpers.logInfoTS("Post-startup external dataref rebind finished with " .. tostring(missingCount) .. " unresolved handles")
        else
            helpers.logInfoTS("Post-startup external dataref rebind finished")
        end
    end

    P.updateSharedVariables()

    local next_recommended_wait_step = def.STANDARDWAIT

    if (P.procedureloop1.lock ~= def.NOPROCEDURE or
        P.procedureloop2.lock ~= def.NOPROCEDURE or
        P.procedureloop3.lock ~= def.NOPROCEDURE or
        P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
        next_recommended_wait_step = def.STANDARDWAIT
    end
    
    sasl.logDebug("----------------------------------------------")
    sasl.logDebug("ONGOINGTASKSTEPINDEX: " .. P.ongoingtaskstepindex)

    if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) or (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)) then
        P.autofunctions()
        P.ongoingtasks()
    end

    if (P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) then
        VR.run(P)
    end

    if (sasl.getLogLevel() == LOG_DEBUG) then
        sasl.logDebug("--- CURRENT PROCEDURELOOP VALUES ---")
        for i = 1, 3 do
            local currentLoop = P.loopStateTables[i]

            if currentLoop then
                local lockId = currentLoop.lock
                local procName

                if lockId == def.NOPROCEDURE then
                    procName = "NOPROCEDURE"
                else
                    procName = (P.proceduretable[lockId] and P.proceduretable[lockId].name) or lockId
                end

                sasl.logDebug(string.format("PROCEDURELOOP%d: LOCK=%s, STEPNAME(A)=%s, STEPINDEX(B)=%d",
                                i, -- Loop number
                                tostring(procName),
                                tostring(currentLoop.currentStepName),
                                currentLoop.stepindex))
            else
                helpers.logInfoTS("Error accessing loop state table for loop index: " .. i)
            end
        end
        sasl.logDebug("--- CURRENT PROCEDURELOOP VALUES ---")
    end

    if (sasl.getLogLevel() == LOG_DEBUG) then
        sasl.logDebug("--- CURRENT DATAREF VALUES ---")
        for i = 1, 3 do
            if P.LoopHandles and P.LoopHandles[i] then
                local handles = P.LoopHandles[i]
                local lockVal = get(handles.lock)
                local stateVal = get(handles.state)
                local nameValRaw = get(handles.stepname) -- Rohwert lesen
                local customValRaw = get(handles.custom) -- Rohwert lesen

                -- Rohwerte loggen (inklusive Länge)
                sasl.logDebug(string.format("RAW Loop %d: StepName='%s' (len:%d), Custom='%s' (len:%d)",
                    i,
                    tostring(nameValRaw), -- Zeigt den Rohstring, wie Lua ihn interpretiert
                    nameValRaw and #nameValRaw or 0, -- Zeigt die Länge des Rohstrings
                    tostring(customValRaw):sub(1, 50) .. (#tostring(customValRaw) > 50 and "..." or ""), -- Kürze Roh-Custom
                    customValRaw and #customValRaw or 0
                ))

                -- Bereinigte Werte (wie vorher)
                local nameValClean = nameValRaw and string.gsub(string.gsub(nameValRaw, "^\0+", ""), "\0+$", "") or ""
                local customValClean = customValRaw and string.gsub(string.gsub(customValRaw, "^\0+", ""), "\0+$", "") or ""

                local procName = "NOPROCEDURE"
                if lockVal ~= def.NOPROCEDURE then
                    procName = (P.proceduretable[lockVal] and P.proceduretable[lockVal].name) or ("ID:" .. tostring(lockVal))
                end

                sasl.logDebug(string.format("CLEANED Loop %d: Lock=%s (%s), State=%s, StepName='%s', Custom='%s'",
                    i,
                    tostring(lockVal),
                    procName,
                    tostring(stateVal),
                    nameValClean,
                    customValClean:sub(1, 100) .. (#customValClean > 100 and "..." or "")
                ))
            else
                sasl.logWarning("Could not read datarefs for Loop " .. i .. ", P.LoopHandles missing.")
            end
        end
    end

    local loops_count = #P.loopStateTables
    local loop_executed_this_cycle = false

    local start_check_index = P.lastExecutedLoopIndex
    if start_check_index == 0 then start_check_index = 1 end

    local last_checked_loop_in_this_cycle = start_check_index

    for i = 1, loops_count do
        local current_loop_idx = ((start_check_index + i - 2) % loops_count) + 1
        local current_loop_state_table = P.loopStateTables[current_loop_idx]

        last_checked_loop_in_this_cycle = current_loop_idx

        if current_loop_state_table.lock ~= def.NOPROCEDURE then
            P.runProcedureLoop(current_loop_idx)
            P.lastExecutedLoopIndex = (current_loop_idx % loops_count) + 1
            loop_executed_this_cycle = true

            local lockId = current_loop_state_table.lock
            local procName = (P.proceduretable[lockId] and P.proceduretable[lockId].name) or lockId

            sasl.logDebug("SCHEDULER: Executing loop " .. tostring(current_loop_idx) .. " (locked: " .. tostring(procName) .. "). Next scan starts at " .. tostring(P.lastExecutedLoopIndex) .. ".")

            break
        else
            sasl.logDebug("SCHEDULER: Skipping loop " .. tostring(current_loop_idx) .. " (not locked).")
        end
    end

    if not loop_executed_this_cycle then
        sasl.logDebug("SCHEDULER: No locked loops found to execute this cycle. Advancing scan pointer for next cycle.")
        P.lastExecutedLoopIndex = (last_checked_loop_in_this_cycle % loops_count) + 1
    end

    next_recommended_wait_step = P.commandtableloop()
    local quickview_step = helpers.stepQuickViewsCgUpdate()
    local defaultview_step = helpers.stepDefaultViewUpdate()
    if quickview_step or defaultview_step then
        next_recommended_wait_step = def.SHORTWAIT
    end
    if P.viewSkipRequested then
        if P.lastCommandWasSpeech then
            -- Keep at least standard wait so speech isn't cut off.
            if next_recommended_wait_step < def.STANDARDWAIT then
                next_recommended_wait_step = def.STANDARDWAIT
            end
        elseif next_recommended_wait_step == def.STANDARDWAIT then
            next_recommended_wait_step = def.VERYSHORTWAIT
        end
        P.viewSkipRequested = nil
    end
    P.lastCommandWasSpeech = false

    local currentFmsPhase = get(P.fmsflightphase)

    if P.flightstate ~= P.lastLoggedFlightstate then
        helpers.logInfoTS(string.format("State Change: Flightstate -> Old: %s, New: %s",
            tostring(P.lastLoggedFlightstate), tostring(P.flightstate)))
        P.lastLoggedFlightstate = P.flightstate
    end

    if currentFmsPhase ~= P.lastLoggedFmsFlightphase then
        helpers.logInfoTS(string.format("State Change: FMS Flightphase -> Old: %s, New: %s",
            tostring(P.lastLoggedFmsFlightphase), tostring(currentFmsPhase)))
        P.lastLoggedFmsFlightphase = currentFmsPhase
    end

    if P.aircraftwasonground ~= P.lastLoggedAircraftwasonground then
        helpers.logInfoTS(string.format("State Change: AircraftWasOnGround -> Old: %s, New: %s",
            tostring(P.lastLoggedAircraftwasonground), tostring(P.aircraftwasonground)))
        P.lastLoggedAircraftwasonground = P.aircraftwasonground
    end

    if (sasl.getLogLevel() == LOG_DEBUG) then
        sasl.logDebug("------------- PROC SET STATUS ----------------")
        for procKey, procInfo in pairs(P.proceduretable) do
            if procInfo and procInfo.name and procInfo.set ~= nil then
                sasl.logDebug(string.format("%-35s = %s", procInfo.name .. " SET:", tostring(procInfo.set)))
            end
        end
        sasl.logDebug("----------------------------------------------")
    end

    return next_recommended_wait_step
end

--------------------------------------------------------------------------------------------------------------

local menu_cycleprocedures = sasl.appendMenuItem(P.menu_main, "Cycle Through Procedures", P.cycleprocedures)
local menu_skip_procedure_step = sasl.appendMenuItem(P.menu_main, "Skip Procedure Step", P.skipprocedurestep)
local menu_step_once = sasl.appendMenuItem(P.menu_main, "Step Once (Advice Only)", P.stepprocedureonce)
local menu_skip_procedure = sasl.appendMenuItem(P.menu_main, "Skip Procedure", P.skipprocedure)
local menu_abort_procedure = sasl.appendMenuItem(P.menu_main, "Abort Procedure", P.abortprocedure)
sasl.appendMenuSeparator ( P.menu_main )
local menu_speak_depmetar = sasl.appendMenuItem(P.menu_main, "Speak Departure Metar", P.speakdepmetar)
local menu_speak_desmetar = sasl.appendMenuItem(P.menu_main, "Speak Destination Metar", P.speakdesmetar)
sasl.appendMenuSeparator ( P.menu_main )
local menu_regular_root = sasl.appendMenuItem(P.menu_main, "Regular Procedures")
local menu_regular = sasl.createMenu("", P.menu_main, menu_regular_root)
local menu_abnormal_root = sasl.appendMenuItem(P.menu_main, "Abnormal Procedures")
local menu_abnormal = sasl.createMenu("", P.menu_main, menu_abnormal_root)
sasl.appendMenuSeparator ( P.menu_main )
local menu_misc_root = sasl.appendMenuItem(P.menu_main, "Miscellaneous")
local menu_misc = sasl.createMenu("", P.menu_main, menu_misc_root)

local menu_cd = sasl.appendMenuItem(menu_regular, "Cold and Dark Startup", P.coldanddarkstartup)
local menu_cockpit_init = sasl.appendMenuItem(menu_regular, "Cockpit Initialization", P.cockpitinit)
local menu_apu_start = sasl.appendMenuItem(menu_regular, "APU Startup", P.apustartup)
local menu_eng_start = sasl.appendMenuItem(menu_regular, "Engine Startup", P.enginestart)
local menu_before_taxi = sasl.appendMenuItem(menu_regular, "Before Taxi Procedure", P.beforetaxi)
local menu_before_takeoff = sasl.appendMenuItem(menu_regular, "Before Takeoff Procedure", P.beforetakeoff)
local menu_after_landing = sasl.appendMenuItem(menu_regular, "After Landing Procedure", P.afterlanding)
local menu_atparkingposition = sasl.appendMenuItem(menu_regular, "At Parking Position Procedure", P.atparkingposition)
local menu_eng_stop_ta = sasl.appendMenuItem(menu_regular, "Turnaround Engine Shutdown", P.turnaroundengineshutdown)
local menu_eng_stop_final = sasl.appendMenuItem(menu_regular, "Final Engine Shutdown", P.finalengineshutdown)
local menu_shutdown = sasl.appendMenuItem(menu_regular, "Shutdown", P.shutdown)
sasl.appendMenuSeparator ( menu_regular )
local menu_above1000 = sasl.appendMenuItem(menu_regular, "Above 10000 Procedure", P.altitudea10000)
local menu_below1000 = sasl.appendMenuItem(menu_regular, "Below 10000 Procedure", P.altitudeb10000)
local menu_ils_freq = sasl.appendMenuItem(menu_regular, "Set ILS/GLS Freq/Course", P.setilsproc)
local menu_copy_nav = sasl.appendMenuItem(menu_regular, "Copy NAV1/MMR1 to NAV2/MMR2", P.copynav)
local menu_set_vref = sasl.appendMenuItem(menu_regular, "Set Landing Flaps/VREF", P.setvrefproc)
local menu_set_toflaps = sasl.appendMenuItem(menu_regular, "Set Takeoff Flaps", P.settoflapsproc)
sasl.appendMenuSeparator ( menu_regular )
local menu_test = sasl.appendMenuItem(menu_regular, "Tests", P.test)

local menu_goaround = sasl.appendMenuItem(menu_abnormal, "Go Around Procedure", P.goaround)
local menu_engine_inflight_restart = sasl.appendMenuItem(menu_abnormal, "Engine In-Flight Restart", P.engineinflightrestart)

local menu_toggle_setcockpitlights = sasl.appendMenuItem(menu_misc, "Set Cockpit Lights", P.setcockpitlights)
local menu_toggle_auto = sasl.appendMenuItem(menu_misc, "Toggle Auto Functions", P.toggleautofunctions)
local menu_toogle_voice = sasl.appendMenuItem(menu_misc, "Toggle Voice Readback", P.togglevoicereadback)
local menu_toogle_adviceonly = sasl.appendMenuItem(menu_misc, "Toggle Voice Advice Only", P.toggleadviceonly)
local menu_toggle_autotaxi = sasl.appendMenuItem(menu_misc, "Toggle Auto Taxiing", P.toggleautotaxiing)
local menu_toggle_autotaxi_pause = sasl.appendMenuItem(menu_misc, "Toggle Auto Taxi Pause", P.toggleautotaxipause)
local menu_toogle_freeze = sasl.appendMenuItem(menu_misc, "Toggle Sim Freeze", P.togglesimfreeze)
local menu_toggle_view = sasl.appendMenuItem(menu_misc, "Toggle View Changes", P.toggleviewchanges)
local menu_timewarptotod = sasl.appendMenuItem(menu_misc, "Time Warp to TOD", P.timewarptotod)
local menu_yalreset = sasl.appendMenuItem(menu_misc, "Reset", P.yalreset)
local menu_yalresetfornewflight = sasl.appendMenuItem(menu_misc, "Reset for New Flight", P.yalresetForNewFlight)

sasl.appendMenuSeparator ( P.menu_main )

--------------------------------------------------------------------------------------------------------------

function P.enableMenus(enableflag)

    sasl.enableMenuItem(PLUGINS_MENU_ID , menu_master , enableflag)

    sasl.enableMenuItem(P.menu_main , menu_cycleprocedures , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_skip_procedure_step , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_step_once , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_skip_procedure , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_abort_procedure , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_speak_depmetar , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_speak_desmetar , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_regular_root , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_abnormal_root , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_misc_root , enableflag)

    sasl.enableMenuItem(menu_regular , menu_cd , enableflag)
    sasl.enableMenuItem(menu_regular , menu_cockpit_init , enableflag)
    sasl.enableMenuItem(menu_regular , menu_apu_start , enableflag)
    sasl.enableMenuItem(menu_regular , menu_eng_start , enableflag)
    sasl.enableMenuItem(menu_regular , menu_before_taxi , enableflag)
    sasl.enableMenuItem(menu_regular , menu_before_takeoff , enableflag)
    sasl.enableMenuItem(menu_regular , menu_after_landing , enableflag)
    sasl.enableMenuItem(menu_regular , menu_atparkingposition , enableflag)
    sasl.enableMenuItem(menu_regular , menu_eng_stop_ta , enableflag)
    sasl.enableMenuItem(menu_regular , menu_eng_stop_final , enableflag)
    sasl.enableMenuItem(menu_regular , menu_shutdown , enableflag)

    sasl.enableMenuItem(menu_regular , menu_above1000 , enableflag)
    sasl.enableMenuItem(menu_regular , menu_below1000 , enableflag)
    sasl.enableMenuItem(menu_regular , menu_ils_freq , enableflag)
    sasl.enableMenuItem(menu_regular , menu_copy_nav , enableflag)
    sasl.enableMenuItem(menu_regular , menu_set_vref , enableflag)
    sasl.enableMenuItem(menu_regular , menu_set_toflaps , enableflag)

    sasl.enableMenuItem(menu_regular , menu_test , enableflag)
    sasl.enableMenuItem(menu_abnormal , menu_goaround , enableflag)
    sasl.enableMenuItem(menu_abnormal , menu_engine_inflight_restart , enableflag)
    sasl.enableMenuItem(menu_misc , menu_toggle_setcockpitlights , enableflag)
    sasl.enableMenuItem(menu_misc , menu_toggle_auto , enableflag)
    sasl.enableMenuItem(menu_misc , menu_toogle_voice , enableflag)
    sasl.enableMenuItem(menu_misc , menu_toogle_adviceonly , enableflag)
    sasl.enableMenuItem(menu_misc , menu_toggle_autotaxi , enableflag)
    sasl.enableMenuItem(menu_misc , menu_toggle_autotaxi_pause , enableflag)
    sasl.enableMenuItem(menu_misc , menu_toogle_freeze , enableflag)
    sasl.enableMenuItem(menu_misc , menu_toggle_view , enableflag)
    sasl.enableMenuItem(menu_misc , menu_timewarptotod , enableflag)
    sasl.enableMenuItem(menu_misc , menu_yalreset , enableflag)
    sasl.enableMenuItem(menu_misc , menu_yalresetfornewflight , enableflag)
    if P.menu_dev_reload then
        sasl.enableMenuItem(P.menu_main, P.menu_dev_reload, enableflag)
    end


end

-- P.YalinitGlobal()

return yal
