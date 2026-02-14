local def = require("definitions")
local helpers = require("helpers")
local P = yal

local function cleanLegToken(token)
    if type(token) ~= "string" then
        return ""
    end
    return token:gsub("[%(%)]", ""):gsub("%s+", "")
end

local function isRunwayLeg(token)
    local clean = cleanLegToken(token)
    return clean:upper():match("^RW%d%d?[LRC]?") ~= nil
end

local function matchesDestRunway(token, destRunway)
    if not token or not destRunway then
        return false
    end
    local cleanToken = cleanLegToken(token):upper():gsub("^RW", "")
    local cleanDest = cleanLegToken(destRunway):upper():gsub("^RW", "")
    return cleanToken == cleanDest
end

local function get_inflight_restart_context(loop)
    local engine = (loop and loop.engine == def.ENGINE2) and def.ENGINE2 or def.ENGINE1
    local isEng2 = engine == def.ENGINE2
    return {
        engine = engine,
        engineLabel = isEng2 and "2" or "1",
        sideLabel = isEng2 and "Right" or "Left",
        mixturePos = isEng2 and P.mixture2pos or P.mixture1pos,
        mixtureIdleCmd = isEng2 and "laminar/B738/engine/mixture2_idle" or "laminar/B738/engine/mixture1_idle",
        mixtureCutoffCmd = isEng2 and "laminar/B738/engine/mixture2_cutoff" or "laminar/B738/engine/mixture1_cutoff",
        starterPos = isEng2 and P.starter2pos or P.starter1pos,
        packPos = isEng2 and P.packrpos or P.packlpos,
        genPos = isEng2 and P.gen2pos or P.gen1pos,
        n2Percent = isEng2 and P.eng2n2percent or P.eng1n2percent
    }
end

local function inflight_restart_auto_enabled()
    return (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)
end

local function isMissedApproachLeg(token)
    local clean = cleanLegToken(token)
    return clean:upper():match("^MISSED") ~= nil
end

local function isRunwayToMissedDiscontinuity(prevLeg, nextLeg)
    return isRunwayLeg(prevLeg) and isMissedApproachLeg(nextLeg)
end

local function runwayUsesTrue(runway)
    if type(runway) ~= "string" then
        return false
    end
    local rwy = runway:upper():gsub("^RW", "")
    return rwy:sub(-1) == "T"
end

local function getEntryMagVar(entry)
    local magVar = entry and entry[def.DESTMAGVAR]
    if magVar == nil then
        local lat = entry and entry[def.DESTLATPOS]
        local lon = entry and entry[def.DESTLONPOS]
        if lat and lon and lat ~= 0 and lon ~= 0 then
            magVar = sasl.getMagneticVariation(lat, lon)
        end
    end
    return tonumber(magVar) or 0
end

local function getRunwayTrueFromEndpoints()
    local latStart = get(P.desrwylatstartpos)
    local lonStart = get(P.desrwylonstartpos)
    local latEnd = get(P.desrwylatendpos)
    local lonEnd = get(P.desrwylonendpos)
    if latStart and lonStart and latEnd and lonEnd
        and latStart ~= 0 and lonStart ~= 0 and latEnd ~= 0 and lonEnd ~= 0 then
        return helpers.getbearing(latStart, lonStart, latEnd, lonEnd)
    end
    return nil
end

local function isLocalizerNavType(navType)
    return navType == def.NAVTYPEILS
        or navType == def.NAVTYPELOC
        or navType == def.NAVTYPELDA
        or navType == def.NAVTYPEIGS
end

local function getFmcApproachRefData()
    if not helpers.fmcHeaderContains("APPROACH REF") then
        return nil
    end

    local lineX = helpers.get("laminar/B738/fmc1/Line04_X") or ""
    local lineL = helpers.get("laminar/B738/fmc1/Line04_L") or ""
    if lineL == "" then
        return nil
    end

    local upperX = lineX:upper()
    if not upperX:find("/CRS", 1, true) then
        return nil
    end
    local navType = nil
    if upperX:find("ILS", 1, true) then
        navType = def.NAVTYPEILS
    elseif upperX:find("LDA", 1, true) then
        navType = def.NAVTYPELDA
    elseif upperX:find("LOC", 1, true) then
        navType = def.NAVTYPELOC
    elseif upperX:find("IGS", 1, true) then
        navType = def.NAVTYPEIGS
    elseif upperX:find("GLS", 1, true) then
        navType = def.NAVTYPEGLS
    elseif upperX:find("LPV", 1, true) then
        navType = def.NAVTYPELPV
    elseif upperX:find("RNAV", 1, true) or upperX:find("RNV", 1, true) or upperX:find("RNP", 1, true) then
        navType = def.NAVTYPERNAV
    else
        return nil
    end

    local clean = lineL:gsub("[`]", "")
    local left, courseStr = clean:match("^(.-)/%s*(%d%d%d)")
    if not courseStr then
        return nil
    end
    local course = tonumber(courseStr)
    if not course then
        return nil
    end
    local freqValue = nil
    if left then
        left = left:gsub("[^%d%.]", "")
        if left ~= "" then
            if isLocalizerNavType(navType) then
                local freqFloat = tonumber(left)
                if not freqFloat or freqFloat < 108.0 or freqFloat > 117.95 then
                    return nil
                end
                freqValue = math.floor(freqFloat * 100 + 0.5)
            else
                local channel = tonumber(left)
                if not channel or channel < 1000 then
                    return nil
                end
                freqValue = math.floor(channel + 0.5)
            end
        end
    end

    return {
        navType = navType,
        course = course,
        freq = freqValue
    }
end

local function getFmcApproachRefCourse(entryNavType)
    local fmc = getFmcApproachRefData()
    if not fmc or not fmc.course then
        return nil
    end
    if isLocalizerNavType(entryNavType) then
        if not isLocalizerNavType(fmc.navType) then
            return nil
        end
    elseif entryNavType == def.NAVTYPEGLS then
        if fmc.navType ~= def.NAVTYPEGLS then
            return nil
        end
    elseif entryNavType == def.NAVTYPELPV or entryNavType == def.NAVTYPERNAV then
        if isLocalizerNavType(fmc.navType) then
            return nil
        end
    end
    return fmc.course
end

local function getFmcApproachRefFrequency(entryNavType)
    local fmc = getFmcApproachRefData()
    if not fmc or not fmc.freq then
        return nil
    end
    if isLocalizerNavType(entryNavType) then
        return isLocalizerNavType(fmc.navType) and fmc.freq or nil
    end
    if entryNavType == def.NAVTYPEGLS or entryNavType == def.NAVTYPELPV then
        if isLocalizerNavType(fmc.navType) then
            return nil
        end
        return fmc.freq
    end
    return nil
end

local function getNavEntryCourse(entry)
    if not entry then
        return nil
    end

    local navType = entry[def.DESTNAVTYPE]
    local icao = entry[def.DESTICAO]
    local runway = entry[def.DESTRWY] or get(P.desrwy)
    local announceTrue = runwayUsesTrue(runway) or runwayUsesTrue(get(P.desrwy))
    local isRnavNav = (navType == def.NAVTYPELPV)
        or (navType == def.NAVTYPERNAV)
        or (navType == def.NAVTYPEGLS)
    local magVar = getEntryMagVar(entry)

    local runwayMag = tonumber(get(P.desrwyheading))
    local runwayTrue = getRunwayTrueFromEndpoints()
    if not runwayTrue and runwayMag and magVar then
        runwayTrue = helpers.calccourse(runwayMag + magVar)
    end
    local runwayRef = nil
    if announceTrue then
        runwayRef = runwayTrue
    else
        runwayRef = runwayMag and helpers.calccourse(runwayMag) or nil
        if not runwayRef and runwayTrue then
            runwayRef = helpers.calccourse(runwayTrue - magVar)
        end
    end
    if isRnavNav then
        runwayRef = nil
    end
    local sanityRunwayRef = nil
    if announceTrue then
        if runwayTrue then
            sanityRunwayRef = helpers.calccourse(runwayTrue)
        elseif runwayMag then
            sanityRunwayRef = helpers.calccourse(runwayMag + magVar)
        end
    else
        if runwayMag then
            sanityRunwayRef = helpers.calccourse(runwayMag)
        elseif runwayTrue then
            sanityRunwayRef = helpers.calccourse(runwayTrue - magVar)
        end
    end
    local function isPlausible(course)
        if not course then return false end
        if runwayRef then
            local diff = math.abs(course - runwayRef)
            if diff > 180 then diff = 360 - diff end
            return diff <= 10
        end
        return true
    end
    local function normalizeCourse(course, courseIsTrue)
        if course == nil then
            return nil
        end

        local function normalizeKnown(valueIsTrue)
            if announceTrue then
                if valueIsTrue then
                    return helpers.calccourse(course)
                end
                return helpers.calccourse(course + magVar)
            end
            if valueIsTrue then
                return helpers.calccourse(course - magVar)
            end
            return helpers.calccourse(course)
        end

        local function score(candidate)
            if not candidate or not runwayRef then
                return nil
            end
            local diff = math.abs(candidate - runwayRef)
            if diff > 180 then diff = 360 - diff end
            return diff
        end

        if courseIsTrue == true then
            local normalized = normalizeKnown(true)
            return isPlausible(normalized) and normalized or nil
        elseif courseIsTrue == false then
            local normalized = normalizeKnown(false)
            return isPlausible(normalized) and normalized or nil
        end

        local candA = normalizeKnown(announceTrue)
        local candB = normalizeKnown(not announceTrue)
        local scoreA = score(candA)
        local scoreB = score(candB)
        local pick = nil
        if scoreA and scoreB then
            pick = (scoreA <= scoreB) and candA or candB
        else
            pick = candA or candB
        end
        return isPlausible(pick) and pick or nil
    end

    local sanityRefs = nil
    local function buildSanityRefs()
        if sanityRefs then return sanityRefs end
        sanityRefs = {}
        if sanityRunwayRef then
            table.insert(sanityRefs, sanityRunwayRef)
        end
        if type(icao) == "string" and type(navType) == "string" and type(runway) == "string" then
            local candidateTypes = { navType }
            if navType == def.NAVTYPELPV or navType == def.NAVTYPEGLS then
                table.insert(candidateTypes, def.NAVTYPERNAV)
            end
            for _, candidateType in ipairs(candidateTypes) do
                local cifpCourse = helpers.getCIFPApproachCourse(icao, candidateType, runway)
                if cifpCourse then
                    local cifpRef = normalizeCourse(cifpCourse, nil)
                    if cifpRef then
                        table.insert(sanityRefs, cifpRef)
                    end
                    break
                end
            end
        end
        return sanityRefs
    end

    local function sanityCheck(candidate, source)
        if not candidate then return nil end
        local refs = buildSanityRefs()
        if not refs or #refs == 0 then return candidate end
        local minDiff = 360
        for _, ref in ipairs(refs) do
            local diff = math.abs(candidate - ref)
            if diff > 180 then diff = 360 - diff end
            if diff < minDiff then minDiff = diff end
        end
        if minDiff > 30 then
            helpers.logInfoTS(string.format(
                "Approach course sanity check failed (source=%s, course=%s, minDiff=%d, runway=%s).",
                tostring(source), tostring(candidate), math.floor(minDiff + 0.5), tostring(runway)
            ))
            return nil
        end
        return candidate
    end

    local fmcCourse = getFmcApproachRefCourse(navType)
    if fmcCourse then
        local normalized = sanityCheck(normalizeCourse(fmcCourse, false), "FMC")
        if normalized then
            return normalized
        end
    end

    local function getFMSFinalMagCourse()
        if not (P and P.fmslegs and P.fmslegslat and P.fmslegslon) then return nil end
        local legsStr = get(P.fmslegs)
        local latArr = get(P.fmslegslat)
        local lonArr = get(P.fmslegslon)
        local waypoints = helpers.buildlegstable(legsStr, latArr, lonArr)
        if not waypoints or #waypoints < 2 then return nil end

        local destRunway = get(P.desrwy)
        local selectedCourse = nil

        if helpers.isvalidrwy(destRunway) then
            for i = #waypoints - 1, 1, -1 do
                local nxt = waypoints[i + 1]
                if nxt and nxt.name and matchesDestRunway(nxt.name, destRunway) then
                    selectedCourse = waypoints[i].magnetic_course
                    break
                end
            end
        else
            for i = #waypoints - 1, 1, -1 do
                local nxt = waypoints[i + 1]
                if nxt and nxt.name and isRunwayLeg(nxt.name) then
                    selectedCourse = waypoints[i].magnetic_course
                    break
                end
            end
        end

        if selectedCourse and selectedCourse ~= 0 then
            return helpers.calccourse(selectedCourse)
        end
        return nil
    end

    local function getFMSFinalMagCourseForRunway(destRunway)
        if not (P and P.fmslegs and P.fmslegslat and P.fmslegslon) then return nil end
        if not helpers.isvalidrwy(destRunway) then return nil end
        local legsStr = get(P.fmslegs)
        local latArr = get(P.fmslegslat)
        local lonArr = get(P.fmslegslon)
        local waypoints = helpers.buildlegstable(legsStr, latArr, lonArr)
        if not waypoints or #waypoints < 2 then return nil end

        local selectedCourse = nil
        for i = #waypoints - 1, 1, -1 do
            local nxt = waypoints[i + 1]
            if nxt and nxt.name and matchesDestRunway(nxt.name, destRunway) then
                selectedCourse = waypoints[i].magnetic_course
                break
            end
        end

        if selectedCourse and selectedCourse ~= 0 then
            return helpers.calccourse(selectedCourse)
        end
        return nil
    end

    -- RNAV/LPV/GLS: prefer FMC final-leg course only when it matches CIFP within tolerance
    local fmsMag = getFMSFinalMagCourse()
    if isRnavNav and fmsMag then
        local normalized = sanityCheck(normalizeCourse(fmsMag, false), "FMS")
        if normalized then
            local cifpCourse = nil
            if type(icao) == "string" and type(runway) == "string" and type(navType) == "string" then
                local candidateTypes = { navType }
                if navType == def.NAVTYPELPV or navType == def.NAVTYPEGLS then
                    table.insert(candidateTypes, def.NAVTYPERNAV)
                end
                for _, candidateType in ipairs(candidateTypes) do
                    cifpCourse = helpers.getCIFPApproachCourse(icao, candidateType, runway)
                    if cifpCourse then break end
                end
            end
            if cifpCourse then
                local diff = math.abs(helpers.headingdiff(fmsMag, cifpCourse))
                if diff <= 10 then
                    return normalized
                end
            else
                return normalized
            end
        end
    end

    -- GLS: use GLS course if available
    if navType == def.NAVTYPEGLS then
        local glsCourse = get(P.glscourse)
        if glsCourse and glsCourse >= 0 and glsCourse < 360 then
            local normalized = sanityCheck(normalizeCourse(glsCourse, nil), "GLS")
            if normalized then
                return normalized
            end
        end
    end

    if type(icao) == "string" and type(navType) == "string" and type(runway) == "string" then
        local candidateTypes = { navType }
        if navType == def.NAVTYPELPV or navType == def.NAVTYPEGLS then
            table.insert(candidateTypes, def.NAVTYPERNAV)
        end
        for _, candidateType in ipairs(candidateTypes) do
            local cifpCourse = helpers.getCIFPApproachCourse(icao, candidateType, runway)
            if cifpCourse then
                local normalized = sanityCheck(normalizeCourse(cifpCourse, nil), "CIFP")
                if normalized then
                    return normalized
                end
            end
        end
    end

    -- Prefer FMC-provided final-leg course when modded Zibo is enabled (fallback after CIFP)
    if fmsMag and not isRnavNav then
        local expected = nil
        if type(icao) == "string" and type(runway) == "string" then
            local cifpCourse = helpers.getCIFPApproachCourse(icao, navType, runway)
            if not cifpCourse and (navType == def.NAVTYPELPV or navType == def.NAVTYPEGLS) then
                cifpCourse = helpers.getCIFPApproachCourse(icao, def.NAVTYPERNAV, runway)
            end
            if cifpCourse then
                expected = helpers.calccourse(cifpCourse)
            end
        end
        local normalized = normalizeCourse(fmsMag, false)
        normalized = sanityCheck(normalized, "FMS")
        if normalized then
            if expected and not announceTrue then
                local diff = math.abs(fmsMag - expected)
                if diff > 180 then diff = 360 - diff end
                if diff <= 10 then
                    return normalized
                end
            else
                return normalized
            end
        end
    end

    if entry.isTrueCourse and entry.truecourse then
        local normalized = sanityCheck(normalizeCourse(entry.truecourse, true), "NAVTRUE")
        if normalized then
            return normalized
        end
    end
    local navCourse = entry[def.DESTCOURSE]
    if navCourse then
        local normalized = sanityCheck(normalizeCourse(navCourse, false), "NAV")
        if normalized then
            return normalized
        end
    end

    -- Fallback: runway heading if available
    if announceTrue then
        if runwayTrue then
            return helpers.calccourse(runwayTrue)
        end
        if runwayMag then
            return helpers.calccourse(runwayMag + magVar)
        end
    else
        if runwayMag then
            return helpers.calccourse(runwayMag)
        end
    end

    return navCourse
end

local function cacheApproachCourse(loop, entry, course)
    if loop then
        loop.approachCourseMag = course
        loop.approachNavType = entry and entry[def.DESTNAVTYPE] or nil
    end
    P.approachCourseMag = course
    P.approachNavType = entry and entry[def.DESTNAVTYPE] or nil
end

local function getCachedApproachCourse(loop)
    if loop and loop.approachCourseMag then
        return loop.approachCourseMag
    end
    local entry = loop and loop.navdatatableindex and P.navdatatable[loop.navdatatableindex] or nil
    local course = entry and getNavEntryCourse(entry) or nil
    cacheApproachCourse(loop, entry, course)
    return course
end

local function getCachedApproachCourseForHeading(runwayHeading)
    local navType = P.approachNavType
    if navType ~= def.NAVTYPERNAV and navType ~= def.NAVTYPELPV and navType ~= def.NAVTYPEGLS then
        return nil
    end
    local course = P.approachCourseMag
    if not course then
        return nil
    end
    if runwayHeading then
        local diff = helpers.headingdiff(course, runwayHeading)
        if diff <= 10 then
            return helpers.roundnumber(course)
        end
        return nil
    end
    return helpers.roundnumber(course)
end

local function getMcpHeadingTarget()
    local headingrounded = nil
    if (helpers.isvalidicao(get(P.desicao)) and helpers.isvalidrwy(get(P.desrwy)) and tonumber(get(P.desrwyheading))) then
        headingrounded = helpers.roundnumber(get(P.desrwyheading))
    end
    local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.desicao), get(P.desrwy))
    if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
        headingrounded = navrwyheading
    end
    local cached = getCachedApproachCourseForHeading(headingrounded)
    if cached then
        headingrounded = cached
    end
    return headingrounded
end

local function getMissedApproachAlt(loop)
    local raw = get(P.missedappalt) or 0
    local alt = helpers.roundnumber((raw / 100)) * 100
    if alt > 1000 then
        return alt
    end
    local cifpAlt = helpers.getCIFPMissedApproachAltitude(
        get(P.desicao),
        P.approachNavType,
        get(P.desrwy),
        loop and loop.detectedApproach or nil
    )
    if cifpAlt and cifpAlt > 0 then
        local rounded = helpers.roundnumber((cifpAlt / 100)) * 100
        if rounded > 0 then
            return rounded
        end
    end
    return alt
end

local function getTakeoffFlapsTarget(autoMode)
    local target = get(P.toflaps)
    if target and target > 0 then
        return target
    end
    if not autoMode then
        return nil
    end
    local computed = helpers.determineTakeoffFlapsSetting(
        get(P.totalweightkgs),
        get(P.deprwylen),
        get(P.deprwyheading),
        get(P.elevation),
        P.depmetar,
        get(P.toflapsset) or target
    )
    local candidate = computed
    if not candidate or candidate <= 0 then
        candidate = get(P.toflapsset)
    end
    if not candidate or candidate <= 0 then
        candidate = 5
    end
    return candidate
end

local function isQrhOff()
    local lineL = tostring(helpers.get("laminar/B738/fmc1/Line06_L") or "")
    local normalized = lineL:gsub("[<>]", ""):upper():gsub("%s+", " ")
    return normalized:find("QRH OFF", 1, true) ~= nil
end

local function isFmcAutomationOn()
    return P.configvalues and (P.configvalues[def.CONFIGFMCAUTOMATION] == def.ON)
end

local function shouldSkipFmcSteps()
    return (P.configvalues and (P.configvalues[def.CONFIGFMCAUTOMATION] ~= def.ON))
        and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)
end

local function getCalcSpeedString(value)
    local num = tonumber(value or 0) or 0
    if num <= 0 then
        return nil
    end
    return helpers.padNumberWithZerosStrict(math.floor(num + 0.5), 3)
end

local M = {}
function M.fillProcedureTable()
    local P = yal 
    P.proceduretable = {
        [def.COLDANDDARKPROCEDURE] = { 
            number = 1, 
            name = "Cold and Dark Startup", 
            cycable = true,
            repeatable = true, 
            speakname = true,
            set = false,
            loop = 1, 
            prerequisite = nil, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, 
            skipCondition = function() return (get(P.battery) == def.ON) end,         
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.ON end, 
                  failMsg = "Procedure not Possible Inflight" },
                { check = function() return (get(P.battery) == def.OFF) or (get(P.mainbus) == def.OFF) end, 
                  failMsg = "Procedure aborted, Cockpit is not Cold and Dark" },
                { check = function() return P.apurunning() ~= def.APUONBUS end, 
                  failMsg = "Procedure aborted, A P U already running" },
                { check = function() return not P.enginesrunning(def.BOTH) end, 
                  failMsg = "Procedure aborted, Engines already running" }
            },  
            startStep = 'set_view_overhead',
            steps = {
                ['set_view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'set_battery_on'
                },
                ['set_battery_on'] = {
                    check = function() return get(P.battery) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/switch/battery_dn") end,
                    advice = "Switch Battery On",
                    confirm = "Battery checked On",
                    nextStep = 'close_battery_cover'
                },
                ['close_battery_cover'] = {
                    check = function() return get(P.batteryswitchcover) == def.CLOSED end,
                    action = function() helpers.command_once("laminar/B738/button_switch_cover02") end,
                    advice = "Close Battery Cover",
                    nextStep = 'check_night_view'
                },
                ['check_night_view'] = {
                    skipIf = function() return get(P.sunpitchdegrees) >= 0 end,
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    nextStep = 'set_dome_light'
                },
                ['set_dome_light'] = {
                    skipIf = function() return get(P.sunpitchdegrees) >= 0 end,
                    check = function() return get(P.domelightpos) ~= def.DOMELIGHTOFF end,
                    action = function() P.setdomelight(def.DOMELIGHTDIM) end,
                    advice = "Set Domelight On",
                    confirm = "Domelight checked On",
                    nextStep = 'view_overhead_2'
                },
                ['view_overhead_2'] = {
                    skipIf = function() return get(P.sunpitchdegrees) >= 0 end,
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'arm_emerg_lights'
                },
                ['arm_emerg_lights'] = {
                    check = function() return get(P.emergencylights) == def.EMERGLIGHTSARMED end,
                    action = function() P.setemergencylights(def.EMERGLIGHTSARMED) end,
                    advice = "Arm Emergency Lights",
                    confirm = "Emergency Lights checked Armed",
                    nextStep = 'close_emerg_light_cover'
                },
                ['close_emerg_light_cover'] = {
                    check = function() return get(P.emergencylightcover) == def.CLOSED end,
                    action = function() helpers.command_once("laminar/B738/button_switch_cover09") end,
                    advice = "Close Emergency Lights Cover",
                    nextStep = 'set_pos_lights'
                },
                ['set_pos_lights'] = {
                    check = function() return get(P.positionlights) == def.POSLIGHTSSTEADY end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/position_light_steady") end,
                    advice = "Set Position Lights Steady",
                    confirm = "Position Lights checked Steady",
                    nextStep = 'check_power_source'
                },
                ['check_power_source'] = {
                    branch = function(loop, procData)
                        if (P.configvalues[def.CONFIGUSEGROUNDPOWER] == def.ON) and (get(P.gpuavailable) == def.ON) then
                            loop.power_source = 'gpu'
                            return 'check_gpu_power'
                        else
                            loop.power_source = 'apu'
                            return 'set_apu_fuel_pump_on'
                        end
                    end
                },
                ['check_gpu_power'] = {
                    check = function() return get(P.gpuon) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/gpu_dn") end,
                    advice = "Set Ground Power On",
                    confirm = "G P U checked On",
                    nextStep = 'start_irs_align'
                },
                ['set_apu_fuel_pump_on'] = {
                    check = function() return get(P.lefttanklswitch) == def.ON end,
                    action = function() set(P.lefttanklswitch, def.ON) end,
                    advice = "Set Left After Fuel Pump On",
                    confirm = "Left After Fuel Pump checked On",
                    nextStep = 'start_apu'
                },
                ['start_apu'] = {
                    check = function() return get(P.apustarterpos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    advice = "Start A P U",
                    confirm = "A P U checked and Started",
                    nextStep = 'start_apu_2'
                },                
                ['start_apu_2'] = {
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    nextStep = 'wait_apu_runup'
                },          
                ['wait_apu_runup'] = {
                    check = function() return P.apurunning() >= def.APUOFFBUS end,
                    confirm = "A P U Running Up",
                    nextStep = 'set_apu_gen'
                },
                ['set_apu_gen'] = {
                    check = function() return P.apurunning() == def.APUONBUS end,
                    action = function() 
                        if not((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                            helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                        end
                        if not((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                            helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                        end
                    end,
                    advice = "Set A P U Generator On",
                    confirm = "A P U Generator checked On",
                    nextStep = 'set_apu_bleed'
                },
                ['set_apu_bleed'] = {
                    check = function() return get(P.bleedairapupos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Set A P U Bleed On",
                    confirm = "A P U Bleed checked On",
                    nextStep = 'set_isol_valve'
                },
                ['set_isol_valve'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEOPEN end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEOPEN) end,
                    advice = "Set Isolation Valve Open",
                    confirm = "Isolation Valve checked Open",
                    nextStep = 'set_packs_auto'
                },
                ['set_packs_auto'] = {
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    action = function() set(P.packlpos, def.PACKAUTO); set(P.packrpos, def.PACKAUTO) end,
                    advice = "Set Packs Auto",
                    confirm = "Packs checked Auto",
                    nextStep = 'set_trim_air'
                },
                ['set_trim_air'] = {
                    check = function()
                        return (get(P.trimairpos) == def.ON)
                            and (get(P.lrecircfanpos) == def.ON)
                            and (get(P.rrecircfanpos) == def.ON)
                    end,
                    action = function()
                        set(P.trimairpos, def.ON)
                        set(P.lrecircfanpos, def.ON)
                        set(P.rrecircfanpos, def.ON)
                    end,
                    advice = "Set Trim Air and Recirc Fans On",
                    confirm = "Trim Air and Recirc Fans checked On",
                    nextStep = 'set_apu_proc_done'
                },
                ['set_apu_proc_done'] = {
                    action = function() P.proceduretable[def.APUSTARTUPPROCEDURE].set = true end,
                    nextStep = 'start_irs_align'
                },
                ['start_irs_align'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    nextStep = 'set_irs_nav'
                },
                ['set_irs_nav'] = {
                    check = function() return (get(P.irsleftpos) == def.IRSNAV) and (get(P.irsrightpos) == def.IRSNAV) end,
                    action = function() P.setirs(def.BOTHIRS, def.IRSNAV) end,
                    advice = "Set Both I R S to Nav",
                    confirm = "I R S Alignment Started", 
                    nextStep = 'view_fms' 
                },
                ['view_fms'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWFMS] end,
                    nextStep = 'branch_fmc_pos_init'
                },
                ['branch_fmc_pos_init'] = {
                    branch = function()
                        if shouldSkipFmcSteps() then
                            return 'end_fms_pos_init'
                        end
                        return 'fmc_init_ref'
                    end
                },
                ['fmc_init_ref'] = {
                    check = function()
                        return helpers.fmcHeaderContains("POS INIT")
                    end,
                    fmcPage = true,
                    action = function()
                        if isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/fmc1_init_ref")
                        end
                    end,
                    advice = "Open F M C Position Init Page",
                    runActionInAdviceMode = true,
                    nextStep = 'check_fms_pos'
                },
                ['check_fms_pos'] = {
                    check = function() return get(P.irsposset) ~= "*****.*******.*" end,
                    action = function() end, 
                    advice = "Initialize I R S Position",
                    confirm = "I R S Position Initialized",
                    branch = function(loop, procData)
                        if P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF then
                            return 'auto_init_fms_pos_1'
                        elseif get(P.irsposset) ~= "*****.*******.*" then
                            return 'end_fms_pos_init' 
                        end
                        return false 
                    end
                },
                ['auto_init_fms_pos_1'] = {
                    action = function() helpers.command_once("laminar/B738/button/fmc1_next_page") end,
                    nextStep = 'auto_init_fms_pos_2'
                },
                ['auto_init_fms_pos_2'] = {
                    action = function() helpers.command_once("laminar/B738/button/fmc1_4L") end,
                    nextStep = 'auto_init_fms_pos_3'
                },
                ['auto_init_fms_pos_3'] = {
                    action = function() helpers.command_once("laminar/B738/button/fmc1_prev_page") end,
                    nextStep = 'auto_init_fms_pos_4'
                },
                ['auto_init_fms_pos_4'] = {
                    action = function() 
                        helpers.command_once("laminar/B738/button/fmc1_4R") 
                        P.commandtableentry(def.TEXT, "I R S Position Initialization Complete")
                    end,
                    nextStep = 'end_fms_pos_init'
                },
                ['end_fms_pos_init'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.COCKPITINITPROCEDURE] = { 
            number = 2,
            name = "Cockpit Initialization",
            cycable = true,
            speakname = true,
            set = false,
            loop = 1,
            prerequisite = nil,
            allowedState = def.GROUNDONLY,
            requiredFlightstate = def.FLIGHTSTATEPREFLIGHT,
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return (get(P.battery) == def.ON) or (get(P.mainbus) == def.ON) end, 
                  failMsg = "Procedure aborted, Cockpit is Cold and Dark" },
                { check = function() return (get(P.parkingbrakepos) == def.ON) end, 
                  failMsg = "Procedure not possible, Parking brake must be set" }
            },
            startStep = 'check_prerequisites',
            steps = {
                ['check_prerequisites'] = { 
                    branch = function(loop) 
                        if (get(P.battery) == def.OFF) and (get(P.mainbus) == def.OFF) then
                            loop.procedurenotpossible = true
                            P.commandtableentry(def.TEXT, P.proceduretable[def.COCKPITINITPROCEDURE].name .. " Procedure aborted, Cockpit is Cold and Dark")
                            return nil 
                        elseif (get(P.parkingbrakepos) == def.OFF) then
                            loop.procedurenotpossible = true
                            P.commandtableentry(def.TEXT, P.proceduretable[def.COCKPITINITPROCEDURE].name .. " Procedure not possible, Parking brake must be set")
                            return nil 
                        end
                        if (get(P.sunpitchdegrees) < 0) then
                            return 'view_upper_overhead' 
                        else
                            return 'view_main_panel' 
                        end
                    end
                },
                ['view_upper_overhead'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'set_dome_light'
                },
                ['set_dome_light'] = { 
                    check = function() return get(P.domelightpos) ~= def.DOMELIGHTOFF end,
                    action = function() P.setdomelight(def.DOMELIGHTDIM) end,
                    advice = "Set Dome Light On",
                    confirm = "Dome light checked On",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'hide_efbs'
                },
                ['hide_efbs'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGHIDEEFBS] == def.OFF end,
                    check = function() 
                        return (get(P.hidecptefb) == def.EFBHIDDEN) and (get(P.hidefoefb) == def.EFBHIDDEN) 
                    end,
                    action = function() 
                        if (get(P.hidecptefb) == def.EFBSHOWN) then helpers.command_once("laminar/B738/tab/toggle") end
                        if (get(P.hidefoefb) == def.EFBSHOWN) then helpers.command_once("laminar/B738/tab/fo_toggle") end
                    end,
                    advice = "Hide E F Bs", 
                    confirm = "E F B S checked hidden", 
                    nextStep = 'set_cockpit_lights',
                    runActionInAdviceMode = true 
                },
                ['set_cockpit_lights'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGIGNOREALLBRIGHTHNESSSETTINGS] == def.ON end,
                    action = function() 
                        if P.setcockpitlights() then
                            P.commandtableentry(def.TEXT, "Instrument Lights set")
                        end
                    end,
                    nextStep = 'view_overhead_window_heat'
                },
                ['view_overhead_window_heat'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'window_heat_on_init'
                },
                ['window_heat_on_init'] = {
                    check = function()
                        return  (get(P.wheatlfwdpos) == def.ON)
                            and (get(P.wheatrfwdpos) == def.ON)
                            and (get(P.wheatlsidepos) == def.ON)
                            and (get(P.wheatrsidepos) == def.ON)
                    end,
                    action = function()
                        P.togglewindowheat(def.ON)
                    end,
                    advice = "Set Window Heat On",
                    confirm = "Window Heat checked On",
                    nextStep = 'set_nosmoking_on'
                },
                ['set_nosmoking_on'] = {
                    check = function() return get(P.nosmokingsignpos) == def.NOSMOKINGSIGNON end,
                    action = function() P.setnosmokingsign(def.NOSMOKINGSIGNON) end,
                    advice = "Set No Smoking Signs On",
                    confirm = "No Smoking Signs checked On",
                    nextStep = 'view_main_before_lower_du'
                },
                ['view_main_before_lower_du'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'set_lower_du'
                },
                ['set_lower_du'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGLOWERDU] == def.OFF end,
                    action = function()
                        local lowerduset = false
                        if (get(P.lowerdupage) == 0) then lowerduset=true; helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG"); helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
                        elseif (get(P.lowerdupage) == 1) then lowerduset=true; helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG") end
                        if (get(P.lowerdupage2) ~= 1) then lowerduset=true; helpers.command_once("laminar/B738/LDU_control/push_button/MFD_SYS") end
                        if lowerduset then P.commandtableentry(def.TEXT, "Lower Display Unit Pages Set") end
                    end,
                    nextStep = 'view_fms'
                },
                ['view_fms'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWFMS] end,
                    nextStep = 'reset_fmc'
                },
                ['reset_fmc'] = {
                    action = function()
                        if P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON then
                            P.commandtableentry(def.TEXT, "Reset F M C")
                        elseif isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/reset_fmc")
                            P.commandtableentry(def.TEXT, "F M C Reset Done")
                        end
                    end,
                    nextStep = 'load_yansh_ofp'
                },
                ['load_yansh_ofp'] = { 
                    skipIf = function()
                        if P.configvalues[def.CONFIGYANSHINTEGRATION] ~= def.ON then
                            return true
                        end
                        return not P.YANSHisinstalled()
                    end,
                    check = function() return P.YANSHflightplanloaded() end,
                    action = function() helpers.command_once("YANSH/fetchOFP") end,
                    advice = "Load Simbrief Flight Plan",
                    confirm = "Simbrief Flight Plan Loaded",
                    nextStep = 'auto_fueling'
                },
                ['auto_fueling'] = { 
                    skipIf = function()
                        if P.configvalues[def.CONFIGYANSHINTEGRATION] ~= def.ON then
                            return true
                        end
                        return not (P.YANSHisinstalled() and P.YANSHflightplanloaded() and get(P.YANSHFuelPlanRamp) > 0 and P.configvalues[def.CONFIGAUTOFUELING] == def.ON)
                    end,
                    action = function() 
                        if (P.configvalues[def.CONFIGAUTOFUELING] == def.ON) then
                            local plannedFuelLbs = get(P.YANSHFuelPlanRamp)
                            if get(P.YANSHParamsUnitsFlag) == def.YANSHUNITKGS then plannedFuelLbs = plannedFuelLbs * def.KGTOLBS end
                            P.refuelAircraft(plannedFuelLbs)
                        elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                            P.checkYANSHFuel()
                        end
                    end,
                    nextStep = 'activate_fmc_plan'
                },
                ['activate_fmc_plan'] = { 
                    check = function()
                        return helpers.isFMSPlanLoaded(
                            get(P.depicao),
                            get(P.desicao),
                            get(P.fmslegs)
                        )
                    end,
                    advice = "Activate Flight Plan in F M C",
                    confirm = "Flight Plan in F M C Checked Activated",
                    nextStep = 'check_ivao_flightplan'
                },
                ['check_ivao_flightplan'] = {
                    branch = function(loop)
                        if not P.IVAOMonitorIsInstalled() then
                            return 'check_departure_airport_match'
                        end

                        local planRef = P.IVAOFlightplanPresent
                        if not (planRef and isProperty(planRef)) then
                            return 'check_departure_airport_match'
                        end

                        local planPresent = (get(planRef) == 1)
                        local onlineRef = P.IVAOOnline
                        local onlineKnown = (onlineRef and isProperty(onlineRef))
                        local online = onlineKnown and (get(onlineRef) == 1) or false

                        if not planPresent then
                            if onlineKnown and online then
                                P.commandtableentry(def.TEXT, "Online but no IVAO flightplan filed")
                            end
                            if not onlineKnown or not online then
                                return 'check_departure_airport_match'
                            end
                            return 'check_departure_airport_match'
                        end

                        if onlineKnown and not online then
                            P.commandtableentry(def.TEXT, "IVAO flightplan filed but you are offline")
                        end

                        local ivaoDep = ""
                        if P.IVAOFlightplanDep and isProperty(P.IVAOFlightplanDep) then
                            ivaoDep = string.upper(helpers.forceCleanString(get(P.IVAOFlightplanDep) or "")):sub(1, 4)
                        end
                        local ivaoArr = ""
                        if P.IVAOFlightplanArr and isProperty(P.IVAOFlightplanArr) then
                            ivaoArr = string.upper(helpers.forceCleanString(get(P.IVAOFlightplanArr) or "")):sub(1, 4)
                        end
                        local depIcao = string.upper(helpers.forceCleanString(get(P.depicao) or "")):sub(1, 4)
                        local desIcao = string.upper(helpers.forceCleanString(get(P.desicao) or "")):sub(1, 4)

                        if helpers.isvalidicao(ivaoDep) and helpers.isvalidicao(depIcao) and ivaoDep ~= depIcao then
                            P.commandtableentry(def.TEXT, "IVAO flightplan departure " .. helpers.spellNato(ivaoDep) .. " differs from FMC departure " .. helpers.spellNato(depIcao))
                        end
                        if helpers.isvalidicao(ivaoArr) and helpers.isvalidicao(desIcao) and ivaoArr ~= desIcao then
                            P.commandtableentry(def.TEXT, "IVAO flightplan destination " .. helpers.spellNato(ivaoArr) .. " differs from FMC destination " .. helpers.spellNato(desIcao))
                        end

                        local nearestIcao = string.upper((helpers.forceCleanString(get(P.nearesticao) or "")):sub(1, 4))
                        if helpers.isvalidicao(ivaoDep) and helpers.isvalidicao(nearestIcao) and ivaoDep ~= nearestIcao then
                            P.commandtableentry(def.TEXT, "Nearest airport " .. helpers.spellNato(nearestIcao) .. " differs from IVAO departure " .. helpers.spellNato(ivaoDep))
                        end

                        local ivaoNumber = ""
                        if P.IVAOFlightplanNumber and isProperty(P.IVAOFlightplanNumber) then
                            ivaoNumber = string.upper(helpers.forceCleanString(get(P.IVAOFlightplanNumber) or ""))
                        end
                        local fmcCallsign = ""
                        if P.hoppie and P.hoppie.callsign and isProperty(P.hoppie.callsign) then
                            fmcCallsign = string.upper(helpers.forceCleanString(get(P.hoppie.callsign) or ""))
                        end
                        if ivaoNumber ~= "" and fmcCallsign ~= "" and ivaoNumber ~= fmcCallsign then
                            P.commandtableentry(def.TEXT, "IVAO flightplan number " .. ivaoNumber .. " differs from FMC callsign " .. fmcCallsign)
                        end

                        return 'check_departure_airport_match'
                    end
                },
                ['check_departure_airport_match'] = {
                    runActionInAdviceMode = true,
                    action = function(loop)
                        local depIcao = string.upper(helpers.forceCleanString(get(P.depicao) or ""))
                        local nearestIcao = string.upper((helpers.forceCleanString(get(P.nearesticao) or "")):sub(1, 4))
                        if helpers.isvalidicao(depIcao) and helpers.isvalidicao(nearestIcao) then
                            if depIcao ~= nearestIcao then
                                if not (loop and loop.nearestAirportWarned) then
                                    P.commandtableentry(def.TEXT, "Nearest airport " .. helpers.spellNato(nearestIcao) .. " differs from departure " .. helpers.spellNato(depIcao))
                                    if loop then loop.nearestAirportWarned = true end
                                end
                            end
                        end
                    end,
                    confirm = function()
                        local depIcao = string.upper(helpers.forceCleanString(get(P.depicao) or ""))
                        local nearestIcao = string.upper((helpers.forceCleanString(get(P.nearesticao) or "")):sub(1, 4))
                        if helpers.isvalidicao(depIcao) and helpers.isvalidicao(nearestIcao) then
                            if depIcao == nearestIcao then
                                return nil -- silent when values match
                            else
                                return "Nearest airport differs from departure " .. helpers.spellNato(depIcao)
                            end
                        end
                        return nil
                    end,
                    nextStep = 'check_fmc_route_continuity'
                },
                ['check_fmc_route_continuity'] = {
                    check = function()
                        local discoOptions = { maxAheadNm = 100 }
                        local depIcao = get(P.depicao)
                        local aircraftLat = get(P.aircraftlatpos)
                        local aircraftLon = get(P.aircraftlonpos)
                        if depIcao and P.airportdatatable and P.airportdatatable[depIcao] then
                            local originData = P.airportdatatable[depIcao]
                            local originLat = originData.latitude
                            local originLon = originData.longitude
                            if originLat and originLon and aircraftLat and aircraftLon then
                                local distanceToOrigin = helpers.getdistance(aircraftLat, aircraftLon, originLat, originLon)
                                if distanceToOrigin and distanceToOrigin <= 5 then
                                    discoOptions.maxAheadNm = 60
                                    discoOptions.forceDistanceFromStart = 0
                                    discoOptions.forcePositionFilter = true
                                end
                            end
                        end

                        local discontinuity = helpers.detectFMSDiscontinuity(
                            get(P.fmslegs),
                            get(P.fmslegslat),
                            get(P.fmslegslon),
                            get(P.aircraftlatpos),
                            get(P.aircraftlonpos),
                            discoOptions
                        )
                        if not discontinuity then
                            return true
                        end
                        local prevLegRaw = discontinuity.previous or ""
                        local nextLegRaw = discontinuity.next or ""
                        if isRunwayToMissedDiscontinuity(prevLegRaw, nextLegRaw) then
                            return true
                        end
                        local message
                        if prevLegRaw ~= "" and prevLegRaw:match("^RW") and nextLegRaw ~= "" and nextLegRaw:upper():match("^MISSED") then
                            message = "Discontinuity between " .. helpers.replaceRunwayPrefix(prevLegRaw) .. " and missed approach"
                        elseif prevLegRaw ~= "" or nextLegRaw ~= "" then
                            local parts = {}
                            if prevLegRaw ~= "" then
                                table.insert(parts, "after " .. helpers.replaceRunwayPrefix(prevLegRaw))
                            end
                            if nextLegRaw ~= "" then
                                table.insert(parts, "before " .. helpers.replaceRunwayPrefix(nextLegRaw))
                            end
                            message = "Discontinuity " .. table.concat(parts, " ")
                        else
                            message = "Discontinuity in flight plan"
                        end
                        P.commandtableentry(def.TEXT, message)
                        return false
                    end,
                    advice = "Resolve F M C Discontinuity before continuing",
                    confirm = "F M C Route checked Continuous",
                    nextStep = 'trigger_settoflaps'
                },
                ['trigger_settoflaps'] = {
                    skipIf = function()
                        local legs = get(P.fmslegs)
                        return not helpers.isFMSPlanLoaded(get(P.depicao), get(P.desicao), legs)
                    end,
                    action = function()
                        local procId = def.SETTOFLAPSPROCEDURE
                        local loopIndex = P.proceduretable[procId].loop
                        local loopInfo = P.loopStateTables[loopIndex]

                        if P.proceduretable[procId].set then
                            P.proceduretable[procId].set = false
                            if P.ProcSetStatusarraydr then
                                set(P.ProcSetStatusarraydr, 0, procId)
                            end
                        end

                        if loopInfo and loopInfo.lock == def.NOPROCEDURE then
                            P.triggerprocedure(procId)
                        end
                    end,
                    nextStep = 'wait_settoflaps_done'
                },
                ['wait_settoflaps_done'] = {
                    skipIf = function()
                        local legs = get(P.fmslegs)
                        return not helpers.isFMSPlanLoaded(get(P.depicao), get(P.desicao), legs)
                    end,
                    check = function()
                        local procId = def.SETTOFLAPSPROCEDURE
                        local loopIndex = P.proceduretable[procId].loop
                        local loopInfo = P.loopStateTables[loopIndex]
                        return P.proceduretable[procId].set == true and loopInfo and loopInfo.lock == def.NOPROCEDURE
                    end,
                    nextStep = 'view_pedestal'
                },
                ['view_pedestal'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWPEDESTAL] end,
                    nextStep = 'set_transponder_code'
                },
                ['set_transponder_code'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGTRANSPONDER] == def.OFF end,
                    check = function() return get(P.transpondercode) == P.configvalues[def.CONFIGTRANSPONDER] end,
                    action = function() set(P.transpondercode, P.configvalues[def.CONFIGTRANSPONDER]) end,
                    advice = function() return "Set Transponder Code " .. helpers.addspaces(P.configvalues[def.CONFIGTRANSPONDER]) end,
                    confirm = function() return "Transponder Code checked and " .. helpers.addspaces(P.configvalues[def.CONFIGTRANSPONDER]) end,
                    nextStep = 'set_transponder_stby'
                },
                ['set_transponder_stby'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGTRANSPONDER] == def.OFF end,
                    check = function() return get(P.transponderpos) == def.STANDBY end,
                    action = function() P.toggletransponder(def.STANDBY) end,
                    advice = "Set Transponder Standby",
                    confirm = "Transponder checked Standby",
                    nextStep = 'view_overhead_2'
                },
                ['view_overhead_2'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'set_probe_heat_off'
                },
                ['set_probe_heat_off'] = { 
                    check = function() return get(P.captainprobepos) == def.OFF and get(P.foprobepos) == def.OFF end,
                    action = function() P.toggleprobeheat(def.OFF) end,
                    advice = "Set Probe Heat Off",
                    confirm = "Probe Heat checked Off",
                    nextStep = 'set_seatbelts_off'
                },
                ['set_seatbelts_off'] = { 
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF end,
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNOFF) end,
                    advice = "Set Seatbelt Signs Off",
                    confirm = "Seatbelt Signs checked Off",
                    nextStep = 'set_poslights_steady'
                },
                ['set_poslights_steady'] = { 
                    check = function() return get(P.positionlights) == def.POSLIGHTSSTEADY end,
                    action = function() P.togglepositionlights(def.POSLIGHTSSTEADY) end,
                    advice = "Set Position Lights Steady",
                    confirm = "Position Lights checked Steady",
                    nextStep = 'set_landing_lights_off'
                },
                ['set_landing_lights_off'] = {
                    check = function()
                        local ledVariant = (get(P.ledlightsvariant) == def.ON)
                        local thr = def.LEDLLIGHTSOFF or 0
                        if ledVariant then
                            return (get(P.llights1) <= thr) and (get(P.llights4) <= thr)
                        else
                            return (get(P.llights1) == def.OFF)
                                and (get(P.llights2) == def.OFF)
                                and (get(P.llights3) == def.OFF)
                                and (get(P.llights4) == def.OFF)
                        end
                    end,
                    advice = "Set Landing Lights Off",
                    action = function() P.togglelandinglights(def.OFF) end,
                    confirm = "Landing Lights checked Off",
                    nextStep = 'set_rwy_lights_off'
                },
                ['set_rwy_lights_off'] = { 
                    check = function() return (get(P.rwylightl) == def.OFF) and (get(P.rwylightr) == def.OFF) end,
                    action = function() P.togglerwylights(def.OFF) end,
                    advice = "Set Runway Turnoff Lights Off",
                    confirm = "Runway Turnoff Lights checked Off",
                    nextStep = 'set_taxilight_off'
                },
                ['set_taxilight_off'] = { 
                    check = function() return get(P.taxilight) == def.OFF end,
                    action = function() P.toggletaxilights(def.OFF) end,
                    advice = "Set Taxi Lights Off",
                    confirm = "Taxi Lights checked Off",
                    nextStep = 'view_main_panel_2'
                },
                ['view_main_panel_2'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'reset_ap_disconnect'
                },
                ['reset_ap_disconnect'] = { 
                    check = function() return get(P.apdiscpos) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/autopilot/disconnect_toggle") end,
                    advice = "Reset Autopilot Disconnect Bar",
                    nextStep = 'set_fds_off'
                },
                ['set_fds_off'] = { 
                    check = function() return get(P.fdpilotpos) == def.OFF and get(P.fdfopos) == def.OFF end,
                    action = function() P.togglefds(def.OFF) end,
                    advice = "Set Both Flight Directors Off",
                    confirm = "Both Flight Directors checked Off",
                    nextStep = 'set_mcp_altitude'
                },
                ['set_mcp_altitude'] = { 
                    check = function()
                        local target = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
                        local fmcAlt = get(P.fmccruisealt) or 0
                        if fmcAlt > 0 then
                            target = math.min(target, fmcAlt)
                        end
                        return get(P.mcpaltitude) == target
                    end,
                    action = function()
                        local target = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
                        local fmcAlt = get(P.fmccruisealt) or 0
                        if fmcAlt > 0 then
                            target = math.min(target, fmcAlt)
                        end
                        set(P.mcpaltitude, target)
                    end,
                    advice = function()
                        local target = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
                        local fmcAlt = get(P.fmccruisealt) or 0
                        if fmcAlt > 0 then
                            target = math.min(target, fmcAlt)
                        end
                        return "Set M C P ALtitude " .. tostring(target)
                    end,
                    confirm = function()
                        local target = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
                        local fmcAlt = get(P.fmccruisealt) or 0
                        if fmcAlt > 0 then
                            target = math.min(target, fmcAlt)
                        end
                        if get(P.mcpaltitude) ~= target then return false end
                        return "M C P ALtitude checked and " .. tostring(target)
                    end,
                    nextStep = 'set_bank_angle'
                },
                ['set_bank_angle'] = { 
                    check = function() return get(P.bankanglepos) == P.configvalues[def.CONFIGBANKANGLEMAX] end,
                    action = function() P.setbankanglepos(P.configvalues[def.CONFIGBANKANGLEMAX]) end,
                    advice = function() return "Set Bank Angle " .. helpers.getbankanglestring(P.configvalues[def.CONFIGBANKANGLEMAX]) end,
                    confirm = function() return "Bank Angle checked and " .. helpers.getbankanglestring(P.configvalues[def.CONFIGBANKANGLEMAX]) end,
                    nextStep = 'set_efis_data'
                },
                ['set_efis_data'] = { 
                    action = function() 
                        if (get(P.efisdatapilotpos) == def.OFF) then helpers.command_once("laminar/B738/EFIS_control/capt/push_button/data_press") end
                        if (get(P.efisdatafopos) == def.OFF) then helpers.command_once("laminar/B738/EFIS_control/fo/push_button/data_press") end
                    end,
                    nextStep = 'set_autobrake_off'
                },
                ['set_autobrake_off'] = { 
                    check = function() return get(P.autobrakepos) == def.AUTOBRAKEOFF end,
                    action = function() P.setautobrake(def.AUTOBRAKEOFF) end,
                    advice = "Set Auto Brake Off",
                    confirm = "Auto Brake checked Off",
                    nextStep = 'set_ap_off'
                },
                ['set_ap_off'] = { 
                    check = function() return get(P.aponstat) == def.OFF end,
                    action = function() set(P.aponstat, def.OFF) end,
                    advice = "Set Autopilot Off",
                    nextStep = 'check_throttle_quadrant'
                },
                ['check_throttle_quadrant'] = { 
                    branch = function(loop, procData)
                        local speedbrakeleverrounded = helpers.roundnumber(get(P.speedbrakelever), 1)
                        local engines_not_running = not P.enginesrunning(def.BOTH)
                        local mixture_not_cutoff = (get(P.mixture1pos) ~= def.OFF or get(P.mixture2pos) ~= def.OFF)
                        local speedbrake_not_down = (speedbrakeleverrounded ~= def.SPEEDBRAKEDOWN)
                        if (engines_not_running and mixture_not_cutoff) or speedbrake_not_down then
                            return 'view_throttle' 
                        else
                            return 'reset_master_caution'
                        end
                    end
                },
                ['view_throttle'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'set_fuel_levers_cutoff'
                },
                ['set_fuel_levers_cutoff'] = { 
                    skipIf = function() return P.enginesrunning(def.BOTH) end,
                    check = function() return get(P.mixture1pos) == def.OFF and get(P.mixture2pos) == def.OFF end,
                    action = function() 
                        if (get(P.mixture2pos) ~= def.OFF) then helpers.command_once("laminar/B738/engine/mixture2_cutoff") end
                        if (get(P.mixture1pos) ~= def.OFF) then helpers.command_once("laminar/B738/engine/mixture1_cutoff") end
                    end,
                    advice = "Set Both Engine Fuel Levers Cutoff",
                    nextStep = 'retract_speedbrake'
                },
                ['retract_speedbrake'] = { 
                    skipIf = function() return helpers.roundnumber(get(P.speedbrakelever), 1) == def.SPEEDBRAKEDOWN end,
                    check = function() return helpers.roundnumber(get(P.speedbrakelever), 1) == def.SPEEDBRAKEDOWN end,
                    action = function() set(P.speedbrakelever, def.OFF) end,
                    advice = "Retract Speed Brakes",
                    nextStep = 'view_main_panel_3'
                },
                ['view_main_panel_3'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'reset_master_caution'
                },
                ['reset_master_caution'] = { 
                    action = function() 
                        helpers.command_once("laminar/B738/push_button/master_caution1")
                        if isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/fmc1_clr")
                        end
                    end,
                    branch = function()
                        if not P.enginesrunning(def.BOTH) then
                            return 'plan_pushback'
                        end
                        local eec_ok = (get(P.fadec1on) > 0.5) and (get(P.fadec2on) > 0.5)
                        if eec_ok then
                            return 'plan_pushback'
                        end
                        return 'check_eec_on'
                    end,
                    nextStep = 'check_eec_on'
                },
                ['check_eec_on'] = {
                    skipIf = function() return not P.enginesrunning(def.BOTH) end,
                    check = function()
                        return (get(P.fadec1on) > 0.5) and (get(P.fadec2on) > 0.5)
                    end,
                    action = function(loop)
                        if loop and loop.eecAutoCommandIssued then
                            return
                        end
                        if get(P.fadec1on) <= 0.5 then
                            helpers.command_once("sim/fadec/fadec_1_on")
                        end
                        if get(P.fadec2on) <= 0.5 then
                            helpers.command_once("sim/fadec/fadec_2_on")
                        end
                        if loop then
                            loop.eecAutoCommandIssued = true
                        end
                    end,
                    branch = function(loop)
                        local eec_ok = (get(P.fadec1on) > 0.5) and (get(P.fadec2on) > 0.5)
                        if not eec_ok then
                            if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON)
                                and (P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] ~= def.OFF)
                                and (not loop or not loop.eecOverheadShown) then
                                if loop then
                                    loop.eecOverheadShown = true
                                    loop.eecReturnStep = 'plan_pushback'
                                end
                                return 'view_overhead_eec'
                            end
                            return false
                        end
                        local returnStep = loop and loop.eecReturnStep or nil
                        if loop then
                            loop.eecReturnStep = nil
                            loop.eecOverheadShown = nil
                        end
                        if returnStep and (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON)
                            and (P.configvalues[def.CONFIGVIEWMAINPANEL] ~= def.OFF) then
                            if loop then
                                loop.eecReturnStep = returnStep
                            end
                            return 'view_main_panel_after_eec'
                        end
                        return returnStep or 'plan_pushback'
                    end,
                    advice = "Check E E C Switches On",
                    nextStep = 'plan_pushback'
                },
                ['view_overhead_eec'] = {
                    skipIf = function()
                        if P.configvalues[def.CONFIGVIEWCHANGES] == def.OFF then
                            return true
                        end
                        return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] == def.OFF
                    end,
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    nextStep = 'check_eec_on'
                },
                ['view_main_panel_after_eec'] = {
                    skipIf = function(loop)
                        return P.configvalues[def.CONFIGVIEWMAINPANEL] == def.OFF
                    end,
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    branch = function(loop)
                        local returnStep = loop and loop.eecReturnStep or nil
                        if loop then
                            loop.eecReturnStep = nil
                            loop.eecOverheadShown = nil
                        end
                        return returnStep or 'plan_pushback'
                    end,
                    nextStep = 'plan_pushback'
                },
                ['plan_pushback'] = {
                    skipIf = function()
                        if P.configvalues[def.CONFIGBPBINTEGRATION] ~= def.ON then
                            return true
                        end
                        if not P.BPBisinstalled() then
                            return true
                        end
                        return P.BPBPlanComplete and (get(P.BPBPlanComplete) == 1)
                    end,
                    action = function(loop)
                        if not loop.bpbPlannerAttempted then
                            helpers.command_once("BetterPushback/start_planner")
                            loop.bpbPlannerAttempted = true
                        end
                    end,
                    check = function(loop)
                        if P.BPBPlannerOpen and isProperty(P.BPBPlannerOpen) then
                            if get(P.BPBPlannerOpen) == def.ON then
                                return true
                            end
                        end
                        if loop and loop.bpbPlannerAttempted then
                            return true
                        end
                        return false
                    end,
                    runActionInAdviceMode = true,
                    advice = function()
                        local hint = P.getTaxiPushbackHint and P.getTaxiPushbackHint() or nil
                        if hint and hint ~= "" then
                            return "Plan Pushback (" .. hint .. ")"
                        end
                        return "Plan Pushback"
                    end,
                    confirm = "Plan Pushback",
                    nextStep = 'wait_for_pushback_planner'
                },
                ['wait_for_pushback_planner'] = {
                    skipIf = function()
                        if P.configvalues[def.CONFIGBPBINTEGRATION] ~= def.ON then
                            return true
                        end
                        if not P.BPBisinstalled() then
                            return true
                        end
                        return P.BPBPlanComplete and (get(P.BPBPlanComplete) == 1)
                    end,
                    check = function(loop)
                        if P.BPBPlannerOpen and isProperty(P.BPBPlannerOpen) then
                            if get(P.BPBPlannerOpen) == def.ON then
                                return false
                            end
                        end
                        if P.BPBPlanComplete and get(P.BPBPlanComplete) ~= 1 then
                            if loop and not loop.bpbNoPlanWarned then
                                P.commandtableentry(def.TEXT, "No Plan available, Pushback Skipped")
                                loop.bpbNoPlanWarned = true
                            end
                        end
                        return true
                    end,
                    nextStep = 'start_planned_pushback'
                },
                ['start_planned_pushback'] = {
                    skipIf = function()
                        if P.configvalues[def.CONFIGBPBINTEGRATION] ~= def.ON then
                            return true
                        end
                        if not P.BPBisinstalled() then
                            return true
                        end
                        if not (P.BPBPlanComplete and P.BPBStarted and P.BPBOpComplete) then
                            return true
                        end
                        local planComplete = (get(P.BPBPlanComplete) == def.ON)
                        local opComplete = (get(P.BPBOpComplete) == def.ON)
                        local started = (get(P.BPBStarted) == def.ON)
                        if not planComplete then
                            return true
                        end
                        if opComplete then
                            return true
                        end
                        if started then
                            return true
                        end
                        return false
                    end,
                    action = function() helpers.command_once("BetterPushback/start") end,
                    runActionInAdviceMode = true,
                    nextStep = nil
                },
            }
        },
        [def.APUSTARTUPPROCEDURE] = { 
            number = 3, 
            name = "A P U Startup", 
            cycable = true, 
            speakname = true,
            set = false, 
            loop = 1, 
            prerequisite = function()
                local state = def.ENG_NO_RUN_COLD_DARK
                if P.enginenorunningstate then
                    local raw = get(P.enginenorunningstate)
                    if raw ~= nil then
                        state = raw
                    end
                end
                if state == def.ENG_NO_RUN_TURNAROUND then
                    return P.proceduretable[def.COCKPITINITPROCEDURE]
                        and P.proceduretable[def.COCKPITINITPROCEDURE].set
                end
                return P.proceduretable[def.COLDANDDARKPROCEDURE]
                    and P.proceduretable[def.COLDANDDARKPROCEDURE].set
            end,
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, 
            skipCondition = function() return (P.apurunning() == def.APUONBUS) or P.enginesrunning(def.BOTH) end,
            prerequisiteChecks = {
                { check = function() return (get(P.battery) == def.ON) or (get(P.mainbus) == def.ON) end, 
                  failMsg = "Procedure aborted, Battery is Off" },
                { check = function() return P.apurunning() ~= def.APUONBUS end, 
                  failMsg = "Procedure aborted, A P U already running" }
            },
            startStep = 'view_overhead',
            steps = {
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'ensure_battery_on'
                },
                ['ensure_battery_on'] = {
                    check = function() return get(P.battery) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/switch/battery_dn") end,
                    advice = "Switch Battery On",
                    confirm = "Battery checked On",
                    nextStep = 'set_apu_fuel_pump_on'
                },
                ['set_apu_fuel_pump_on'] = {
                    check = function() return get(P.lefttanklswitch) == def.ON end,
                    action = function() set(P.lefttanklswitch, def.ON) end,
                    advice = "Set Left After Fuel Pump On",
                    confirm = "Left After Fuel Pump checked On",
                    nextStep = 'start_apu'
                },
                ['start_apu'] = {
                    check = function() return get(P.apustarterpos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    advice = "Start A P U",
                    confirm = "A P U checked and Started",
                    nextStep = 'start_apu_2'
                },                
                ['start_apu_2'] = {
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    nextStep = 'wait_apu_runup'
                },
                ['wait_apu_runup'] = {
                    check = function() return P.apurunning() >= def.APUOFFBUS end,
                    confirm = "A P U Running Up",
                    nextStep = 'set_apu_gen'
                },
                ['set_apu_gen'] = {
                    check = function() return P.apurunning() == def.APUONBUS end,
                    action = function() 
                        if not((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                            helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                        end
                        if not((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                            helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                        end
                    end,
                    advice = "Set A P U Generator On",
                    confirm = "A P U Generator checked On",
                    nextStep = 'gpu_off'
                },
                ['gpu_off'] = {
                    skipIf = function() return get(P.gpuon) == def.OFF end,
                    check = function() return get(P.gpuon) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/gpu_up") end,
                    advice = "Set Ground Power Off",
                    confirm = "Ground Power checked Off",
                    nextStep = 'set_apu_bleed'
                },
                ['set_apu_bleed'] = {
                    check = function() return get(P.bleedairapupos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Set A P U Bleed On",
                    confirm = "A P U Bleed checked On",
                    nextStep = 'set_isol_valve'
                },
                ['set_isol_valve'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEOPEN end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEOPEN) end,
                    advice = "Set Isolation Valve Open",
                    confirm = "Isolation Valve checked Open",
                    nextStep = 'set_packs_auto'
                },
                ['set_packs_auto'] = {
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    action = function() set(P.packlpos, def.PACKAUTO); set(P.packrpos, def.PACKAUTO) end,
                    advice = "Set Packs Auto",
                    confirm = "Packs checked Auto",
                    nextStep = 'set_trim_air'
                },
                ['set_trim_air'] = {
                    check = function()
                        return (get(P.trimairpos) == def.ON)
                            and (get(P.lrecircfanpos) == def.ON)
                            and (get(P.rrecircfanpos) == def.ON)
                    end,
                    action = function()
                        set(P.trimairpos, def.ON)
                        set(P.lrecircfanpos, def.ON)
                        set(P.rrecircfanpos, def.ON)
                    end,
                    advice = "Set Trim Air and Recirc Fans On",
                    confirm = "Trim Air and Recirc Fans checked On",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.ENGINESTARTPROCEDURE] = { 
            number = 4, 
            name = "Engine Start", 
            cycable = true, 
            speakname = true,
            set = false,
            loop = 1, 
            prerequisite = def.COCKPITINITPROCEDURE, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, 
            skipCondition = function() return P.enginesrunning(def.BOTH) end,
            prerequisiteChecks = {
                { check = function() return P.apurunning() == def.APUONBUS end, 
                  failMsg = "Procedure not possible, A P U not running" },
                { check = function() return not P.enginesrunning(def.BOTH) end, 
                  failMsg = "Procedure aborted, Engines already running", setonabort = true }
            },
            startStep = 'view_overhead',
            steps = {
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'set_beacon_on'
                },
                ['set_beacon_on'] = {
                    check = function() return get(P.beaconlights) == def.ON end,
                    action = function() P.togglecollisionlights(def.ON) end,
                    advice = "Set Collision Lights On",
                    confirm = "Collision Lights checked On",
                    nextStep = 'set_fuel_pumps_on'
                },
                ['set_fuel_pumps_on'] = {
                    check = function() return (get(P.lefttanklswitch) == def.ON) and (get(P.lefttankrswitch) == def.ON) and (get(P.righttanklswitch) == def.ON) and (get(P.righttankrswitch) == def.ON) end,
                    action = function() 
                        set(P.lefttanklswitch, def.ON); set(P.lefttankrswitch, def.ON)
                        set(P.righttanklswitch, def.ON); set(P.righttankrswitch, def.ON)
                    end,
                    advice = "Set Wing Tank Pumps On",
                    confirm = "Wing Tank Pumps checked On",
                    nextStep = 'set_packs_off'
                },
                ['set_packs_off'] = {
                    check = function() return (get(P.packlpos) == def.PACKOFF) and (get(P.packrpos) == def.PACKOFF) end,
                    action = function() set(P.packlpos, def.PACKOFF); set(P.packrpos, def.PACKOFF) end,
                    advice = "Set Packs Off",
                    confirm = "Packs checked Off",
                    nextStep = 'set_apu_bleed_on'
                },
                ['set_apu_bleed_on'] = {
                    check = function() return get(P.bleedairapupos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Set A P U Bleed On",
                    confirm = "A P U Bleed checked On",
                    nextStep = 'set_isol_valve_open'
                },
                ['set_isol_valve_open'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEOPEN end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEOPEN) end,
                    advice = "Set Isolation Valve Open",
                    confirm = "Isolation Valve checked Open",
                    nextStep = 'set_starter2_gnd'
                },
                ['set_starter2_gnd'] = {
                    check = function() return get(P.starter2pos) == def.GROUND end,
                    action = function() P.setstarter(def.ENGINE2, def.GROUND) end,
                    advice = "Set Starter 2 Ground",
                    confirm = "Engine 2 Starter checked Ground",
                    nextStep = 'view_main_panel_1'
                },
                ['view_main_panel_1'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'wait_eng2_n2'
                },
                ['wait_eng2_n2'] = {
                    check = function() return get(P.eng2n2percent) >= 25 end,
                    confirm = "Engine 2 N 2 at 25 Percent",
                    nextStep = 'view_throttle_1'
                },
                ['view_throttle_1'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'set_eng2_fuel'
                },
                ['set_eng2_fuel'] = {
                    check = function() return get(P.mixture2pos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/engine/mixture2_idle") end,
                    advice = "Set Engine 2 Fuel Lever Idle",
                    confirm = "Engine 2 Fuel Lever checked Idle",
                    nextStep = 'view_main_panel_2'
                },
                ['view_main_panel_2'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'wait_eng2_run'
                },
                ['wait_eng2_run'] = {
                    check = function() return P.enginesrunning(def.ENGINE2) end,
                    confirm = "Engine 2 Running",
                    nextStep = 'view_overhead_2'
                },
                ['view_overhead_2'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'set_starter1_gnd'
                },
                ['set_starter1_gnd'] = {
                    check = function() return get(P.starter1pos) == def.GROUND end,
                    action = function() P.setstarter(def.ENGINE1, def.GROUND) end,
                    advice = "Set Starter 1 Ground",
                    confirm = "Engine 1 Starter checked Ground",
                    nextStep = 'view_main_panel_3'
                },
                ['view_main_panel_3'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'wait_eng1_n2'
                },
                ['wait_eng1_n2'] = {
                    check = function() return get(P.eng1n2percent) >= 25 end,
                    confirm = "Engine 1 N 2 at 25 Percent",
                    nextStep = 'view_throttle_2'
                },
                ['view_throttle_2'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'set_eng1_fuel'
                },
                ['set_eng1_fuel'] = {
                    check = function() return get(P.mixture1pos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/engine/mixture1_idle") end,
                    advice = "Set Engine 1 Fuel Lever Idle",
                    confirm = "Engine 1 Fuel Lever checked Idle",
                    nextStep = 'view_main_panel_4'
                },
                ['view_main_panel_4'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'wait_eng1_run'
                },
                ['wait_eng1_run'] = {
                    check = function() return P.enginesrunning(def.ENGINE1) end,
                    confirm = "Engine 1 Running",
                    nextStep = 'view_overhead_3'
                },
                ['view_overhead_3'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'set_gens_on'
                },
                ['set_gens_on'] = {
                    check = function() return (get(P.gen1pos) == def.ON) and (get(P.gen2pos) == def.ON) end,
                    action = function() 
                        if (get(P.gen1pos) ~= def.ON) then helpers.command_once("laminar/B738/toggle_switch/gen1_dn") end
                        if (get(P.gen2pos) ~= def.ON) then helpers.command_once("laminar/B738/toggle_switch/gen2_dn") end
                    end,
                    advice = "Switch Both Generators On",
                    confirm = "Both Generators checked On",
                    nextStep = 'set_hyd_on'
                },
                ['set_hyd_on'] = {
                    check = function() return (get(P.hydro1pos) == def.ON) and (get(P.hydro2pos) == def.ON) end,
                    action = function() set(P.hydro1pos, def.ON); set(P.hydro2pos, def.ON) end,
                    advice = "Switch Both Hydraulic Pumps On",
                    confirm = "Both Hydraulic Pumps checked On",
                    nextStep = 'set_elec_hyd_on'
                },
                ['set_elec_hyd_on'] = {
                    check = function() return (get(P.elechydro1pos) == def.ON) and (get(P.elechydro2pos) == def.ON) end,
                    action = function() set(P.elechydro1pos, def.ON); set(P.elechydro2pos, def.ON) end,
                    advice = "Switch Both Electrical Hydraulic Pumps On",
                    confirm = "Both Electrical Hydraulic Pumps checked On",
                    nextStep = 'set_eng_bleed_on'
                },
                ['set_eng_bleed_on'] = {
                    check = function() return (get(P.bleedair1pos) == def.ON) and (get(P.bleedair2pos) == def.ON) end,
                    action = function() 
                        if (get(P.bleedair1pos) == def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_1") end
                        if (get(P.bleedair2pos) == def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_2") end
                    end,
                    advice = "Engine Bleeds On",
                    confirm = "Engine Bleeds checked On",
                    nextStep = 'set_packs_auto'
                },
                ['set_packs_auto'] = {
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    action = function() set(P.packlpos, def.PACKAUTO); set(P.packrpos, def.PACKAUTO) end,
                    advice = "Set Packs Auto",
                    confirm = "Packs checked Auto",
                    nextStep = 'set_isol_valve_auto'
                },
                ['set_isol_valve_auto'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEAUTO end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEAUTO) end,
                    advice = "Set Isolation Valve Auto",
                    confirm = "Isolation Valve checked Auto",
                    nextStep = 'set_trim_air_on'
                },
                ['set_trim_air_on'] = {
                    check = function()
                        return (get(P.trimairpos) == def.ON)
                            and (get(P.lrecircfanpos) == def.ON)
                            and (get(P.rrecircfanpos) == def.ON)
                    end,
                    action = function()
                        set(P.trimairpos, def.ON)
                        set(P.lrecircfanpos, def.ON)
                        set(P.rrecircfanpos, def.ON)
                    end,
                    advice = "Set Trim Air and Recirc Fans On",
                    confirm = "Trim Air and Recirc Fans checked On",
                    nextStep = 'set_apu_bleed_off'
                },
                ['set_apu_bleed_off'] = {
                    check = function() return get(P.bleedairapupos) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Set A P U Bleed Off",
                    confirm = "A P U Bleed checked Off",
                    nextStep = 'set_apu_off'
                },
                ['set_apu_off'] = {
                    check = function() return P.apurunning() == def.APUOFF end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up") end,
                    advice = "Switch APU Off",
                    confirm = "A P U checked Off",
                    nextStep = 'set_yaw_damper_on'
                },
                ['set_yaw_damper_on'] = {
                    check = function() return get(P.yawdamperswitch) == def.ON end,
                    action = function() set(P.yawdamperswitch, def.ON) end,
                    advice = "Set Yaw Damper On",
                    confirm = "Yaw Damper checked On",
                    branch = function(loop)
                        if not P.enginesrunning(def.BOTH) then
                            return 'view_main_panel_final'
                        end
                        local eec_ok = (get(P.fadec1on) > 0.5) and (get(P.fadec2on) > 0.5)
                        if eec_ok then
                            return 'view_main_panel_final'
                        end
                        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON)
                            and (P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] ~= def.OFF) then
                            if loop then
                                loop.eecReturnStep = 'view_main_panel_final'
                            end
                            return 'view_overhead_eec'
                        end
                        return 'check_eec_on'
                    end,
                    nextStep = 'view_main_panel_final'
                },
                ['view_overhead_eec'] = {
                    skipIf = function()
                        if P.configvalues[def.CONFIGVIEWCHANGES] == def.OFF then
                            return true
                        end
                        return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] == def.OFF
                    end,
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    nextStep = 'check_eec_on'
                },
                ['check_eec_on'] = {
                    skipIf = function() return not P.enginesrunning(def.BOTH) end,
                    check = function()
                        return (get(P.fadec1on) > 0.5) and (get(P.fadec2on) > 0.5)
                    end,
                    action = function(loop)
                        if loop and loop.eecAutoCommandIssued then
                            return
                        end
                        if get(P.fadec1on) <= 0.5 then
                            helpers.command_once("sim/fadec/fadec_1_on")
                        end
                        if get(P.fadec2on) <= 0.5 then
                            helpers.command_once("sim/fadec/fadec_2_on")
                        end
                        if loop then
                            loop.eecAutoCommandIssued = true
                        end
                    end,
                    branch = function(loop)
                        local eec_ok = (get(P.fadec1on) > 0.5) and (get(P.fadec2on) > 0.5)
                        if not eec_ok then
                            return false
                        end
                        local returnStep = loop and loop.eecReturnStep or nil
                        if loop then
                            loop.eecReturnStep = nil
                        end
                        if returnStep and (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON)
                            and (P.configvalues[def.CONFIGVIEWMAINPANEL] ~= def.OFF) then
                            if loop then
                                loop.eecReturnStep = returnStep
                            end
                            return 'view_main_panel_after_eec'
                        end
                        return returnStep or 'view_main_panel_final'
                    end,
                    advice = "Check E E C Switches On",
                    nextStep = 'view_main_panel_final'
                },
                ['view_main_panel_after_eec'] = {
                    skipIf = function(loop)
                        if P.configvalues[def.CONFIGVIEWMAINPANEL] == def.OFF then
                            return true
                        end
                        return not (loop and loop.eecReturnStep)
                    end,
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    branch = function(loop)
                        local returnStep = loop and loop.eecReturnStep or nil
                        if loop then
                            loop.eecReturnStep = nil
                        end
                        return returnStep or 'view_main_panel_final'
                    end,
                    nextStep = 'view_main_panel_final'
                },
                ['view_main_panel_final'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.BEFORETAXIPROCEDURE] = { 
            number = 5, 
            name = "Before Taxi", 
            cycable = true, 
            speakname = true,
            set = false,
            loop = 1, 
            prerequisite = function() return P.enginesrunning(def.BOTH) end, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, 
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return P.enginesrunning(def.BOTH) end, 
                  failMsg = "Procedure aborted, Engines not running" }
            },
            startStep = 'view_main_panel',
            steps = {
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    normalize = true,
                    nextStep = 'remove_chocks'
                },
                ['remove_chocks'] = {
                    skipIf = function() return P.configvalues[def.CONFIGAUTOCHOCKSPB] == def.OFF end,
                    check = function() return get(P.chockstatus) == def.OFF end,
                    action = function()
                        helpers.command_once("laminar/B738/toggle_switch/chock")
                    end,
                    advice = "Remove Chocks",
                    confirm = "Chocks checked and Removed",
                    nextStep = 'check_night_view',
                    runActionInAdviceMode = true
                },
                ['check_night_view'] = {
                    view = function() return def.DEFAULTVIEW end,
                    branch = function(loop, procData)
                        if (get(P.domelightpos) == def.DOMELIGHTOFF) then
                            return 'view_overhead'
                        else
                            return 'view_upper_overhead'
                        end
                    end
                },
                ['view_upper_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    nextStep = 'set_dome_light_off'
                },
                ['set_dome_light_off'] = {
                    check = function() return get(P.domelightpos) == def.DOMELIGHTOFF end,
                    action = function() P.setdomelight(def.DOMELIGHTOFF) end,
                    advice = "Set Domelight Off",
                    confirm = "Domelight checked Off",
                    nextStep = 'view_overhead'
                },
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'taxi_light_on'
                },
                ['taxi_light_on'] = {
                    check = function() return get(P.taxilight) ~= def.OFF end,
                    action = function() P.toggletaxilights(def.ON) end,
                    advice = "Set Taxi Lights On",
                    confirm = "Taxi Lights checked On",
                    nextStep = 'pos_lights_steady'
                },
                ['pos_lights_steady'] = {
                    check = function() return get(P.positionlights) == def.POSLIGHTSSTEADY end,
                    action = function() P.togglepositionlights(def.POSLIGHTSSTEADY) end,
                    advice = "Set Position Lights Steady",
                    confirm = "Position Lights checked Steady",
                    nextStep = 'beacon_on'
                },
                ['beacon_on'] = {
                    check = function() return get(P.beaconlights) == def.ON end,
                    action = function() P.togglecollisionlights(def.ON) end,
                    advice = "Set Collision Lights On",
                    confirm = "Collision Lights checked On",
                    nextStep = 'seatbelts_on'
                },
                ['seatbelts_on'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNON end,
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNON) end,
                    advice = "Set Seatbeltsigns On",
                    confirm = "Seatbelt Signs checked On",
                    nextStep = 'logo_light_on'
                },
                ['logo_light_on'] = {
                    check = function() return get(P.logolighton) == def.ON end,
                    action = function() P.togglelogolight(def.ON) end,
                    advice = "Set Logo Lights On",
                    confirm = "Logo Lights checked On",
                    nextStep = 'yaw_damper_on'
                },
                ['yaw_damper_on'] = {
                    check = function() return get(P.yawdamperswitch) == def.ON end,
                    action = function() set(P.yawdamperswitch, def.ON) end,
                    advice = "Set Yaw Damper On",
                    confirm = "Yaw Damper checked On",
                    nextStep = 'hyd_pumps_on'
                },
                ['hyd_pumps_on'] = {
                    check = function() return (get(P.hydro1pos) == def.ON) and (get(P.hydro2pos) == def.ON) and (get(P.elechydro1pos) == def.ON) and (get(P.elechydro2pos) == def.ON) end,
                    action = function() 
                        set(P.hydro1pos, def.ON); set(P.hydro2pos, def.ON)
                        set(P.elechydro1pos, def.ON); set(P.elechydro2pos, def.ON)
                    end,
                    advice = "Switch Hydraulic Pumps On",
                    confirm = "Hydraulic Pumps checked On",
                    nextStep = 'probe_heat_on'
                },
                ['probe_heat_on'] = {
                    check = function()
                        return (get(P.captainprobepos) == def.ON) and (get(P.foprobepos) == def.ON)
                    end,
                    action = function()
                        P.toggleprobeheat(def.ON)
                    end,
                    advice = "Set Probe Heat On",
                    confirm = "Probe Heat checked On",
                    nextStep = 'starters_flight'
                },
                ['starters_flight'] = {
                    check = function() return (get(P.starter1pos) == def.FLIGHT) and (get(P.starter2pos) == def.FLIGHT) end,
                    action = function() P.setstarter(def.BOTH, def.FLIGHT) end,
                    advice = "Set Both Starters Flight",
                    confirm = "Both Starters checked Flight",
                    nextStep = 'apu_bleed_off'
                },
                ['apu_bleed_off'] = {
                    skipIf = function() return P.apurunning() >= def.APUOFFBUS end,
                    check = function() return get(P.bleedairapupos) == def.OFF end,
                    action = function() set(P.bleedairapupos, def.OFF) end,
                    advice = "Set A P U Bleed Off",
                    confirm = "A P U Bleed checked Off",
                    nextStep = 'isol_valve_auto'
                },
                ['isol_valve_auto'] = {
                    skipIf = function() return get(P.bleedairapupos) == def.ON end,
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEAUTO end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEAUTO) end,
                    advice = "Set Isolation Valve Auto",
                    confirm = "Isolation Valve checked Auto",
                    nextStep = 'packs_auto'
                },
                ['packs_auto'] = {
                    skipIf = function() return not (get(P.bleedairapupos) == def.ON or (get(P.bleedair1pos) == def.ON and get(P.bleedair2pos) == def.ON)) end,
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    action = function() set(P.packlpos, def.PACKAUTO); set(P.packrpos, def.PACKAUTO) end,
                    advice = "Set Packs Auto",
                    confirm = "Packs checked Auto",
                    nextStep = 'view_main_panel_2'
                },
                ['view_main_panel_2'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'fds_on'
                },
                ['fds_on'] = {
                    check = function() return (get(P.fdpilotpos) == def.ON) and (get(P.fdfopos) == def.ON) end,
                    action = function() P.togglefds(def.ON) end,
                    advice = "Set Both Flight Directors On",
                    confirm = "Flight Directors checked On",
                    nextStep = 'arm_lnav'
                },
                ['arm_lnav'] = {
                    check = function()
                        if get(P.aplnavstat) == def.ON then return true end
                        -- Accept HDG SEL as an alternative if vectors expected
                        return get(P.aphdgselstat) ~= def.OFF
                    end,
                    branch = function(loop, procData)
                        local autoMode = P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON
                        if not autoMode then return false end
                        if (get(P.aplnavstat) == def.ON) or (get(P.aphdgselstat) ~= def.OFF) then
                            loop.lnavAutoCycle = nil
                            return false
                        end
                        if not loop.lnavAutoCycle then
                            loop.lnavAutoCycle = 1
                            helpers.command_once("laminar/B738/autopilot/lnav_press")
                            return true
                        end
                        loop.lnavAutoCycle = nil
                        if get(P.aphdgselstat) == def.OFF then
                            helpers.command_once("laminar/B738/autopilot/hdg_sel_press")
                        end
                        return (procData.steps and procData.steps['arm_lnav'] and procData.steps['arm_lnav'].nextStep) or 'arm_vnav'
                    end,
                    advice = function()
                        if get(P.aplnavstat) == def.ON then
                            return "L NAV checked Armed"
                        end
                        if get(P.aphdgselstat) ~= def.OFF then
                            return "Heading Select checked Armed"
                        end
                        return "Arm L NAV or Heading Select"
                    end,
                    confirm = function()
                        if get(P.aplnavstat) == def.ON then
                            return "L NAV checked Armed"
                        end
                        if get(P.aphdgselstat) ~= def.OFF then
                            return "Heading Select checked Armed"
                        end
                        return false
                    end,
                    nextStep = 'arm_vnav'
                },
                ['arm_vnav'] = {
                    check = function() return get(P.apvnavstat) == def.ON end,
                    branch = function(loop, procData)
                        local autoMode = P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON
                        if not autoMode then return false end
                        if get(P.apvnavstat) == def.ON then
                            loop.vnavAutoCycle = nil
                            return false
                        end
                        if not loop.vnavAutoCycle then
                            loop.vnavAutoCycle = 1
                            helpers.command_once("laminar/B738/autopilot/vnav_press")
                            return true
                        end
                        loop.vnavAutoCycle = nil
                        return (procData.steps and procData.steps['arm_vnav'] and procData.steps['arm_vnav'].nextStep) or 'view_throttle'
                    end,
                    advice = "Arm V NAV",
                    confirm = "V NAV checked Armed",
                    nextStep = 'view_throttle'
                },
                ['view_throttle'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'set_flaps_takeoff'
                },
                ['set_flaps_takeoff'] = {
                    check = function()
                        local autoMode = P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON
                        local target = getTakeoffFlapsTarget(autoMode)
                        local current = helpers.convflaplevertoflappos(get(P.flapleverpos))
                        if target and target > 0 then
                            return current == target
                        else
                            return current > def.FLAPSUP -- any takeoff flap > 0 accepted
                        end
                    end,
                    action = function()
                        local autoMode = P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON
                        if not autoMode then return end
                        local target = getTakeoffFlapsTarget(true)
                        if target and target > 0 then
                            helpers.command_once("laminar/B738/push_button/flaps_" .. target)
                        end
                    end,
                    advice = function()
                        local target = get(P.toflaps)
                        if target and target > 0 then
                            return "Set Flap Lever " .. tostring(target)
                        else
                            return "Set Takeoff Flaps"
                        end
                    end,
                    confirm = function()
                        local autoMode = P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON
                        local target = getTakeoffFlapsTarget(autoMode)
                        local current = helpers.convflaplevertoflappos(get(P.flapleverpos))
                        if target and target > 0 then
                            if current == target then
                                return "Flap Lever checked and " .. tostring(target)
                            end
                            return false
                        else
                            if current > def.FLAPSUP then
                                return "Takeoff Flaps checked"
                            end
                            return false
                        end
                    end,
                    nextStep = 'release_parking_brake'
                },
                ['release_parking_brake'] = {
                    skipIf = function() return P.configvalues[def.CONFIGAUTOCHOCKSPB] == def.OFF end,
                    check = function()
                        local pbPos = get(P.parkingbrakepos)
                        local simRatio = P.simparkingbrakeratio and get(P.simparkingbrakeratio) or 0
                        return (pbPos == def.OFF) and (simRatio <= 0.05)
                    end,
                    action = function(loop)
                        local pbPos = get(P.parkingbrakepos)
                        local simRatio = P.simparkingbrakeratio and get(P.simparkingbrakeratio) or 0
                        if (pbPos == def.OFF) and (simRatio <= 0.05) then return end

                        local now = os.time()
                        if loop.pbReleaseLast and (now - loop.pbReleaseLast) < 1 then return end
                        loop.pbReleaseLast = now

                        helpers.command_once("laminar/B738/push_button/park_brake_on_off")
                    end,
                    advice = "Release Parking Brake",
                    confirm = "Parking Brake checked Released",
                    nextStep = 'view_main_panel_final'
                },
                ['view_main_panel_final'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.BEFORETAKEOFFPROCEDURE] = { 
            number = 6, 
            name = "Before Takeoff", 
            cycable = true, 
            speakname = true,
            set = false,
            loop = 1, 
            prerequisite = def.BEFORETAXIPROCEDURE, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, 
            skipCondition = nil,          
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.ON end, 
                  failMsg = "Procedure not possible Inflight" },
                { check = function() return P.proceduretable[def.BEFORETAXIPROCEDURE].set end, 
                  failMsg = "Procedure Not Possible, before Taxi Procedure" }
            },
            transitionConditions = {
                { condition = function() return get(P.airgroundsensor) == def.OFF end },
                { condition = function() return get(P.groundspeed) > 45 end } 
            },
            startStep = 'view_pedestal',
            label_to_index = {},
            get_index = function(self, label) return nil end,
            steps = {
                ['view_pedestal'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWPEDESTAL] end,
                    normalize = true,
                    nextStep = 'transponder_tara'
                },
                ['transponder_tara'] = {
                    skipIf = function() return P.configvalues[def.CONFIGTRANSPONDER] == 0 end,
                    check = function() return get(P.transponderpos) == def.TARA end,
                    action = function() P.toggletransponder(def.TARA) end,
                    advice = "Set Transponder T A R A",
                    confirm = "Transponder checked and T A R A",
                    nextStep = 'view_overhead'
                },
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'pos_lights_strobe'
                },
                ['pos_lights_strobe'] = {
                    check = function() return get(P.positionlights) == def.POSLIGHTSSTROBE end,
                    action = function() P.togglepositionlights(def.POSLIGHTSSTROBE) end,
                    advice = "Set Position Lights Strobe",
                    confirm = "Position Lights checked Strobe",
                    nextStep = 'landing_lights_on'
                },
                ['landing_lights_on'] = {
                    check = function()
                        local ledVariant = (get(P.ledlightsvariant) == def.ON)
                        local thr = def.LEDLLIGHTSOFF or 0
                        if ledVariant then
                            return (get(P.llights1) > thr)
                                and (get(P.llights4) > thr)
                        else
                            return  (get(P.llights1) ~= def.OFF)
                                and (get(P.llights2) ~= def.OFF)
                                and (get(P.llights3) ~= def.OFF)
                                and (get(P.llights4) ~= def.OFF)
                        end
                    end,
                    action = function() P.togglelandinglights(def.ON) end,
                    advice = "Set Landing Lights On",
                    confirm = "Landing Lights checked On",
                    nextStep = 'taxi_light_off'
                },
                ['taxi_light_off'] = {
                    check = function() return get(P.taxilight) == def.OFF end,
                    action = function() P.toggletaxilights(def.OFF) end,
                    advice = "Set Taxi Lights Off",
                    confirm = "Taxi Lights checked Off",
                    nextStep = 'rwy_lights_off'
                },
                ['rwy_lights_off'] = {
                    check = function() return (get(P.rwylightl) == def.OFF) and (get(P.rwylightr) == def.OFF) end,
                    action = function() P.togglerwylights(def.OFF) end,
                    advice = "Set Runway Turnoff Lights Off",
                    confirm = "Runway Turnoff Lights checked Off",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'autobrake_rto'
                },
                ['autobrake_rto'] = {
                    check = function() return get(P.autobrakepos) == def.AUTOBRAKERTO end,
                    action = function() P.setautobrake(def.AUTOBRAKERTO) end,
                    advice = "Set Auto Brake R T O",
                    confirm = "Auto Brake checked and R T O",
                    nextStep = 'check_mcp_heading'
                },
                ['check_mcp_heading'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() 
                        local headingrounded = nil
                        if (helpers.isvalidicao(get(P.depicao)) and helpers.isvalidrwy(get(P.deprwy)) and tonumber(get(P.deprwyheading))) then
                            headingrounded = helpers.roundnumber(get(P.deprwyheading))
                        end
                        local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.depicao), get(P.deprwy))
                        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
                            headingrounded = navrwyheading
                        end
                        if headingrounded then
                            return get(P.mcpheading) == headingrounded
                        end
                        return true 
                    end,
                    advice = function() 
                        local headingrounded = nil
                        if (helpers.isvalidicao(get(P.depicao)) and helpers.isvalidrwy(get(P.deprwy)) and tonumber(get(P.deprwyheading))) then
                            headingrounded = helpers.roundnumber(get(P.deprwyheading))
                        end
                        local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.depicao), get(P.deprwy))
                        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
                            headingrounded = navrwyheading
                        end
                        if headingrounded then
                            return "Set M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3))
                        end
                        return nil
                    end,
                    confirm = function() 
                        return "M C P Heading checked " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcpheading), 3))
                    end,
                    nextStep = 'arm_lnav'
                },
                ['arm_lnav'] = {
                    check = function()
                        if get(P.aplnavstat) == def.ON then return true end
                        -- Allow HDG SEL when vectors after departure are planned
                        return get(P.aphdgselstat) ~= def.OFF
                    end,
                    branch = function(loop, procData)
                        local autoMode = P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON
                        if not autoMode then return false end
                        if (get(P.aplnavstat) == def.ON) or (get(P.aphdgselstat) ~= def.OFF) then
                            loop.lnavAutoCycle = nil
                            return false
                        end
                        if not loop.lnavAutoCycle then
                            loop.lnavAutoCycle = 1
                            helpers.command_once("laminar/B738/autopilot/lnav_press")
                            return true
                        end
                        loop.lnavAutoCycle = nil
                        if get(P.aphdgselstat) == def.OFF then
                            helpers.command_once("laminar/B738/autopilot/hdg_sel_press")
                        end
                        return (procData.steps and procData.steps['arm_lnav'] and procData.steps['arm_lnav'].nextStep) or 'arm_vnav'
                    end,
                    advice = function()
                        if get(P.aplnavstat) == def.ON then
                            return "L NAV checked Armed"
                        end
                        if get(P.aphdgselstat) ~= def.OFF then
                            return "Heading Select checked Armed"
                        end
                        return "Arm L NAV or Heading Select"
                    end,
                    confirm = function()
                        if get(P.aplnavstat) == def.ON then
                            return "L NAV checked Armed"
                        end
                        if get(P.aphdgselstat) ~= def.OFF then
                            return "Heading Select checked Armed"
                        end
                        return false
                    end,
                    nextStep = 'arm_vnav'
                },
                ['arm_vnav'] = {
                    check = function() return get(P.apvnavstat) == def.ON end,
                    branch = function(loop, procData)
                        local autoMode = P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON
                        if not autoMode then return false end
                        if get(P.apvnavstat) == def.ON then
                            loop.vnavAutoCycle = nil
                            return false
                        end
                        if not loop.vnavAutoCycle then
                            loop.vnavAutoCycle = 1
                            helpers.command_once("laminar/B738/autopilot/vnav_press")
                            return true
                        end
                        loop.vnavAutoCycle = nil
                        return (procData.steps and procData.steps['arm_vnav'] and procData.steps['arm_vnav'].nextStep) or 'arm_at'
                    end,
                    advice = "Arm V NAV",
                    confirm = "V NAV checked Armed",
                    nextStep = 'arm_at'
                },
                ['arm_at'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return get(P.atarmpos) == def.ON end,
                    advice = "Arm Autothrottle",
                    confirm = "Autothrottle checked Armed",
                    nextStep = 'speak_wind'
                },
                ['speak_wind'] = {
                    action = function() 
                        local windreport = nil
                        if (P.depmetar and P.airportdatatable[get(P.depicao)] and P.airportdatatable[get(P.depicao)].latitude and P.airportdatatable[get(P.depicao)].longitude) then
                            windreport = helpers.formatWindSpeechSummary(P.depmetar, P.airportdatatable[get(P.depicao)].latitude, P.airportdatatable[get(P.depicao)].longitude)
                        elseif (P.depmetar and helpers.isvalidrwy(get(P.deprwy))) then
                            windreport = helpers.formatWindSpeechSummary(P.depmetar, get(P.deprwylatstartpos), get(P.deprwylonstartpos))
                        end
                        if (windreport ~= nil) then
                            P.commandtableentry(def.TEXT, windreport)
                        end
                    end,
                    nextStep = nil
                }
            }
        },
        [def.AFTERTAKEOFFPROCEDURE] = { 
            number = 7,
            name = "After Takeoff",
            cycable = false,
            speakname = false,
            set = false,
            loop = 2,
            prerequisite = def.BEFORETAKEOFFPROCEDURE,
            allowedState = def.AIRONLY,
            requiredFlightstate = def.FLIGHTSTATEINITIALCLIMB,
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end, 
                  failMsg = "Procedure only available Inflight" }
            },
            startStep = 'wait_for_altitude',
            steps = {
                ['wait_for_altitude'] = {
                    check = function() 
                        return get(P.radioaltitude) > 200 
                    end,
                    advice = nil,
                    action = nil,
                    nextStep = 'set_gear_up'
                },
                ['set_gear_up'] = {
                    check = function() 
                        return get(P.gearhandlepos) == def.GEARUP 
                    end,
                    advice = "Set Gear Up",
                    action = function() 
                        set(P.gearhandlepos, def.GEARUP) 
                    end,
                    confirm = "Gear checked Up",
                    nextStep = 'set_gear_lever_off'
                },
                ['set_gear_lever_off'] = {
                    check = function()
                        return get(P.gearhandlepos) == def.GEAROFF
                    end,
                    advice = function()
                        local gear_is_stowed = (get(P.lgeardeployed) == 0) and
                                               (get(P.ngeardeployed) == 0) and
                                               (get(P.rgeardeployed) == 0)
                        if (get(P.gearhandlepos) == def.GEARUP) and gear_is_stowed then
                            return "Set Gear Lever Off"
                        end
                        return false
                    end,
                    action = function()
                        local gear_is_stowed = (get(P.lgeardeployed) == 0) and
                                               (get(P.ngeardeployed) == 0) and
                                               (get(P.rgeardeployed) == 0)
                        if (get(P.gearhandlepos) == def.GEARUP) and gear_is_stowed then
                            set(P.gearhandlepos, def.GEAROFF)
                        end
                    end,
                    confirm = "Gear Lever checked Off",
                    nextStep = 'set_autobrake_off'
                },
                ['set_autobrake_off'] = {
                    check = function()
                        return get(P.autobrakepos) == def.AUTOBRAKEOFF
                    end,
                    advice = "Set Auto Brake Off",
                    action = function()
                        P.setautobrake(def.AUTOBRAKEOFF)
                    end,
                    confirm = "Auto Brake checked Off",
                    nextStep = 'trigger_packs_restore'
                },
                ['trigger_packs_restore'] = {
                    action = function()
                        local loopInfo = P.loopStateTables[3]
                        if loopInfo and loopInfo.lock == def.NOPROCEDURE and not P.proceduretable[def.PACKSRESTOREPROCEDURE].set then
                            P.triggerprocedure(def.PACKSRESTOREPROCEDURE)
                        end
                    end,
                    nextStep = nil
                }
            }
        },
        [def.PACKSRESTOREPROCEDURE] = {
            number = 8,
            name = "Packs Restore",
            cycable = false,
            speakname = false,
            set = false,
            loop = 3,
            allowedState = def.AIRONLY,
            requiredFlightstate = { def.FLIGHTSTATEINITIALCLIMB, def.FLIGHTSTATECLIMB },
            skipCondition = nil,
            startStep = 'wait_packs_restore_altitude',
            steps = {
                ['wait_packs_restore_altitude'] = {
                    check = function()
                        local restore_alt = P.configvalues[def.CONFIGPACKSRESTOREALT] or 0
                        if restore_alt <= 0 then
                            return get(P.flapleverpos) <= def.FLAPSUP
                        end

                        local departure_altitude = 0
                        local dep_icao = get(P.depicao)
                        if dep_icao ~= "" and P.airportdatatable[dep_icao] and P.airportdatatable[dep_icao].elevation_ft then
                            departure_altitude = P.airportdatatable[dep_icao].elevation_ft
                        end

                        local height_above_field = get(P.altitude) - departure_altitude
                        if height_above_field < 0 then
                            height_above_field = 0
                        end

                        local flaps_up = get(P.flapleverpos) <= def.FLAPSUP

                        return height_above_field >= restore_alt and flaps_up
                    end,
                    advice = nil,
                    action = nil,
                    nextStep = 'set_eng_bleed_on'
                },
                ['set_eng_bleed_on'] = {
                    check = function() return (get(P.bleedair1pos) == def.ON) and (get(P.bleedair2pos) == def.ON) end,
                    advice = "Engine Bleeds On",
                    action = function()
                        if (get(P.bleedair1pos) == def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_1") end
                        if (get(P.bleedair2pos) == def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_2") end
                    end,
                    confirm = "Engine Bleeds checked On",
                    nextStep = 'set_packs_auto'
                },
                ['set_packs_auto'] = {
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    advice = "Set Packs Auto",
                    action = function()
                        set(P.packlpos, def.PACKAUTO)
                        set(P.packrpos, def.PACKAUTO)
                    end,
                    confirm = "Both Packs checked On",
                    nextStep = 'set_isol_valve_auto'
                },
                ['set_isol_valve_auto'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEAUTO end,
                    advice = "Set Isolation Valve Auto",
                    action = function() set(P.isolvalvepos, def.ISOLVALVEAUTO) end,
                    confirm = "Isolation Valve checked Auto",
                    nextStep = 'set_apu_bleed_off'
                },
                ['set_apu_bleed_off'] = {
                    check = function() return get(P.bleedairapupos) == def.OFF end,
                    advice = "Set A P U Bleed Off",
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    confirm = "A P U Bleed checked Off",
                    nextStep = 'set_apu_off'
                },
                ['set_apu_off'] = {
                    check = function() return P.apurunning() == def.APUOFF end,
                    advice = "Set A P U Off",
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up") end,
                    confirm = "A P U checked Off",
                    nextStep = nil
                }
            }
        },
        [def.DURINGCLIMBPROCEDURE] = {
            number = 9,
            name = "During Climb",
            cycable = false,
            speakname = false,
            set = false,
            loop = 2,
            prerequisite = nil,
            allowedState = def.AIRONLY,
            requiredFlightstate = def.FLIGHTSTATECLIMB,
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end, 
                  failMsg = "Procedure only available Inflight" }
            },
            startStep = 'set_dome_light_off',
            steps = {
                ['set_dome_light_off'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON end,
                    action = function() P.setdomelight(def.DOMELIGHTOFF) end,
                    nextStep = 'check_landing_lights'
                },
                ['check_landing_lights'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON end,
                    action = function() 
                        if (get(P.altitude) < P.configvalues[def.CONFIGLOWEAIRSPACEALT]) then
                            P.togglelandinglights(def.ON)
                        end
                    end,
                    nextStep = 'set_pos_lights_strobe'
                },
                ['set_pos_lights_strobe'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON end,
                    action = function() P.togglepositionlights(def.POSLIGHTSSTROBE) end,
                    nextStep = 'set_rwy_lights_off'
                },
                ['set_rwy_lights_off'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON end,
                    action = function() P.togglerwylights(def.OFF) end,
                    nextStep = 'set_taxi_lights_off'
                },
                ['set_taxi_lights_off'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON end,
                    action = function() P.toggletaxilights(def.OFF) end,
                    nextStep = 'set_transponder_tara'
                },
                ['set_transponder_tara'] = {
                    skipIf = function() 
                        return (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) or (P.configvalues[def.CONFIGTRANSPONDER] == 0) 
                    end,
                    action = function() P.toggletransponder(def.TARA) end,
                    nextStep = 'wait_for_transition'
                },
                ['wait_for_transition'] = {
                    check = function(loop) 
                        local trans_alt = get(P.fmctransalt)
                        if (trans_alt == nil) or (trans_alt <= 0) then
                            loop.altAbove10kTransitionAnnounced = false
                            return false
                        end

                        local above = get(P.altitude) > trans_alt
                        if above then
                            if not loop.altAbove10kTransitionAnnounced then
                                loop.altAbove10kTransitionAnnounced = true
                                return true
                            end
                        else
                            loop.altAbove10kTransitionAnnounced = false
                        end
                        return false
                    end,
                    ensureConfirmInAdviceMode = true,
                    confirm = "Passing Transition Altitude",
                    nextStep = 'set_qnh_standard'
                },
                ['set_qnh_standard'] = {
                    skipIf = function() 
                        return (P.configvalues[def.CONFIGAUTOBARO] == def.OFF) or (get(P.fmccruisealt) <= get(P.fmctransalt))
                    end,
                    check = function() return get(P.barostd) == def.ON end,
                    advice = "Set Q N H to Standard",
                    action = function() helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press") end,
                    confirm = "Q N H checked and Standard",
                    nextStep = nil
                }
            }
        },
        [def.ALTITUDEA10000PROCEDURE] = {
            number = 10,
            name = "Altitude Above 10000",
            cycable = true,
            speakname = false,
            set = false,
            loop = 1,
            prerequisite = nil,
            allowedState = def.AIRONLY,
            requiredFlightstate = def.FLIGHTSTATECLIMB,
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end, 
                  failMsg = "Procedure only available Inflight" },
                { 
                  check = function(loop) 
                      if not loop.triggeredmanually then return true end
                      local departure_altitude = 0
                      if P.airportdatatable[get(P.depicao)] and P.airportdatatable[get(P.depicao)].elevation_ft then
                          departure_altitude = P.airportdatatable[get(P.depicao)].elevation_ft
                      end
                      local height_above_field = get(P.altitude) - departure_altitude
                      local lower_airspace_alt = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
                      return (height_above_field >= lower_airspace_alt) or (get(P.altitude) >= lower_airspace_alt)
                  end, 
                  failMsg = "Procedure only possible above lower Airspace Altitude" 
                }
            },
            startStep = 'set_view_overhead',
            steps = {
                ['set_view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'announce_altitude'
                },
                ['announce_altitude'] = {
                    skipIf = function() 
                        return (get(P.fmccruisealt) <= P.configvalues[def.CONFIGLOWEAIRSPACEALT])
                    end,
                    action = function() 
                        if (get(P.altitude) < (P.configvalues[def.CONFIGLOWEAIRSPACEALT] + 1000)) then
                            P.commandtableentry(def.TEXT, "Above " .. P.configvalues[def.CONFIGLOWEAIRSPACEALT] .. " Feet")
                        end
                    end,
                    runActionInAdviceMode = true,
                    nextStep = 'set_landing_lights_off'
                },
                ['set_landing_lights_off'] = {
                    check = function()
                        local ledVariant = (get(P.ledlightsvariant) == def.ON)
                        local thr = def.LEDLLIGHTSOFF or 0
                        if ledVariant then
                            return (get(P.llights1) <= thr) and (get(P.llights4) <= thr)
                        else
                            return (get(P.llights1) == def.OFF)
                                and (get(P.llights2) == def.OFF)
                                and (get(P.llights3) == def.OFF)
                                and (get(P.llights4) == def.OFF)
                        end
                    end,
                    advice = "Set Landing Lights Off",
                    action = function() P.togglelandinglights(def.OFF) end,
                    confirm = "Landing Lights checked Off",
                    nextStep = 'set_logo_lights_off'
                },
                ['set_logo_lights_off'] = {
                    check = function() return get(P.logolighton) == def.OFF end,
                    advice = "Set Logo Lights Off",
                    action = function() P.togglelogolight(def.OFF) end,
                    confirm = "Logo Lights checked Off",
                    nextStep = 'set_seatbelts_off'
                },
                ['set_seatbelts_off'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF end,
                    advice = "Set Seatbeltsigns Off",
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNOFF) end,
                    confirm = "Seatbelt Signs checked Off",
                    nextStep = 'set_starters'
                },
                ['set_starters'] = {
                    check = function() 
                        if (get(P.starterauto) == def.ON) then
                            return (get(P.starter1pos) == def.AUTO) and (get(P.starter2pos) == def.AUTO)
                        else
                            return (get(P.starter1pos) == def.CONT) and (get(P.starter2pos) == def.CONT)
                        end
                    end,
                    advice = function()
                        if (get(P.starterauto) == def.ON) then return "Set Both Starters Auto"
                        else return "Set Both Starters Continuous" end
                    end,
                    action = function()
                        if (get(P.starterauto) == def.ON) then P.setstarter(def.BOTH, def.AUTO)
                        else P.setstarter(def.BOTH, def.CONT) end
                    end,
                    confirm = function()
                        if (get(P.starterauto) == def.ON) then return "Both Starters checked Auto"
                        else return "Both Starters checked Continuous" end
                    end,
                    nextStep = 'set_view_main'
                },
                ['set_view_main'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.DURINGDESCENTPROCEDURE] = {
            number = 11,
            name = "During Descent",
            cycable = false,
            speakname = false,
            set = false,
            loop = 2,
            prerequisite = nil,
            allowedState = def.AIRONLY,
            requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH },
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end, 
                  failMsg = "Procedure only available Inflight" }
            },
            startStep = 'announce_descent',
            steps = {
                ['announce_descent'] = {
                    confirm = "Descent Started",
                    nextStep = 'check_fms_page'
                },
                ['check_fms_page'] = {
                    skipIf = function()
                        return P.configvalues[def.CONFIGSPDRESTR250] ~= def.ON or shouldSkipFmcSteps()
                    end,
                    check = function(loop, procData)
                        return helpers.fmcHeaderContains("DES")
                    end,
                    fmcPage = true,
                    action = function(loop, procData)
                        if isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/fmc1_des")
                        end
                    end,
                    advice = "Open Descent Page",
                    runActionInAdviceMode = true,
                    nextStep = 'set_speed_restriction'
                },
                ['set_speed_restriction'] = {
                    skipIf = function() return P.configvalues[def.CONFIGSPDRESTR250] ~= def.ON end,
                    check = function() 
                        local spd_num = tonumber(get(P.speedrestr))
                        return spd_num == 250 
                    end,
                    advice = "Set Speed below 10000 Feet to 250",
                    action = function() 
                        set(P.speedrestr, 250) 
                    end,
                    confirm = "Speed 250 below 10000 Feet checked",
                    nextStep = 'speak_des_metar'
                },
                ['speak_des_metar'] = {
                    action = function() P.speakdesmetar() end,
                    nextStep = 'check_des_rwy'
                },
                ['check_des_rwy'] = {
                    check = function()
                        return helpers.isvalidicao(get(P.desicao)) and helpers.isvalidrwy(get(P.desrwy))
                    end,
                    advice = function()
                        if helpers.isvalidicao(get(P.desicao)) then
                            return "Set Destination Runway for " .. helpers.spellNato(get(P.desicao))
                        end
                        return "Set Destination Airport and Runway in F M C"
                    end,
                    confirm = function()
                        return "Destination Runway checked " .. helpers.addspaces(get(P.desrwy))
                    end,
                    nextStep = 'check_rwy_suitability'
                },
                ['check_rwy_suitability'] = {
                    action = function()
                        if P.desmetar.metarfound then
                            if not helpers.shouldCheckRunwaySuitability(P.desmetar, get(P.desrwy), P.approachNavType) then
                                P.commandtableentry(def.TEXT, "Check Destination Runway " .. helpers.addspaces(get(P.desrwy)))
                            end
                        end
                    end,
                    nextStep = 'check_route_continuity_before_approach'
                },
                ['check_route_continuity_before_approach'] = {
                    check = function(loop)
                        local legs = get(P.fmslegs)
                        if type(legs) ~= "string" or legs == "" then
                            return true
                        end

                        local destIcao = get(P.desicao)
                        local destRunway = get(P.desrwy)
                        if not helpers.isvalidicao(destIcao) then
                            return false
                        end

                        local hasRunwayLeg = false
                        for token in legs:gmatch("([^%s]+)") do
                            local upperToken = string.upper(token)
                            if upperToken:match("^RW%d%d?[LRC]?$") then
                                hasRunwayLeg = true
                                break
                            end
                        end

                        local runwayValid = helpers.isvalidrwy(destRunway)
                        if not runwayValid and not hasRunwayLeg then
                            if loop and not loop.approachReminderIssued then
                                local runwayDisplay = helpers.addspaces(destRunway)
                                P.commandtableentry(def.TEXT, "Select Approach for Runway " .. runwayDisplay .. " at " .. helpers.spellNato(destIcao))
                                loop.approachReminderIssued = true
                            end
                            return false
                        elseif loop and loop.approachReminderIssued then
                            loop.approachReminderIssued = nil
                        end

                        local discontinuity = helpers.detectFMSDiscontinuity(
                            legs,
                            get(P.fmslegslat),
                            get(P.fmslegslon),
                            get(P.aircraftlatpos),
                            get(P.aircraftlonpos)
                        )
                        if discontinuity then
                            local prevLegRaw = discontinuity.previous
                            if isRunwayToMissedDiscontinuity(prevLegRaw, discontinuity.next) then
                                return true
                            end
                            if matchesDestRunway(prevLegRaw, destRunway) then
                                return true
                            end
                            local prevLeg = prevLegRaw and helpers.replaceRunwayPrefix(prevLegRaw) or ""
                            local suffix = (prevLeg ~= "") and (" after " .. prevLeg) or ""
                            P.commandtableentry(def.TEXT, "Discontinuity" .. suffix .. " before approach")
                            return false
                        end

                        local remainingDistance = helpers.getRemainingRouteDistance(
                            legs,
                            get(P.fmslegslat),
                            get(P.fmslegslon),
                            get(P.aircraftlatpos),
                            get(P.aircraftlonpos)
                        )

                        local todDistance = get(P.vnavtoddist)
                        local cruiseAlt = get(P.fmccruisealt)
                        local tolerance = 5

                        if cruiseAlt and cruiseAlt > 0 and remainingDistance and remainingDistance > 0 and todDistance and todDistance > 0 then
                            if todDistance > (remainingDistance + tolerance) then
                                P.commandtableentry(def.TEXT, "Verify F M C route extends beyond Top of Descent")
                                return false
                            end
                        end

                        return true
                    end,
                    advice = "Ensure F M C route is continuous and extends beyond Top of Descent",
                    confirm = "F M C route continuity checked",
                    nextStep = 'wait_for_transition'
                },
                ['wait_for_transition'] = {
                    skipIf = function() return get(P.fmccruisealt) <= get(P.fmctranslvl) end,
                    check = function(loop) 
                        local transition_level = get(P.fmctranslvl)
                        if (transition_level == nil) or (transition_level <= 0) or (transition_level > 25000) then
                            loop.descentTransitionLevelAnnounced = false
                            return false
                        end

                        local below = (get(P.altitude) < transition_level)
                        if below then
                            if not loop.descentTransitionLevelAnnounced then
                                loop.descentTransitionLevelAnnounced = true
                                return true
                            end
                        else
                            loop.descentTransitionLevelAnnounced = false
                        end
                        return false
                    end,
                    ensureConfirmInAdviceMode = true,
                    confirm = "Passing Transition Level",
                    nextStep = 'set_qnh_local'
                },
                ['set_qnh_local'] = {
                    skipIf = function() return P.configvalues[def.CONFIGAUTOBARO] == def.OFF end,
                    check = function()
                        local tl = get(P.fmctranslvl)
                        if (tl == nil) or (tl <= 0) or (tl > 25000) then return false end 
                        if (get(P.altitude) >= tl) then return false end 
                        local baroinchtmp, _ = P.getlocalqnh(def.ARRIVAL)
                        if (get(P.barostd) == def.ON) then return false end 
                        if (helpers.roundnumber(math.abs(helpers.roundnumber(get(P.baropilot), 2) - baroinchtmp), 2) > 0.01) then return false end 
                        return true
                    end,
                    advice = function()
                        local tl = get(P.fmctranslvl)
                        if (tl == nil) or (tl <= 0) or (tl > 25000) then return false end 
                        if (get(P.altitude) >= tl) then return false end 
                        local baroinchtmp, baropastmp = P.getlocalqnh(def.ARRIVAL)
                        if (get(P.baroinhpa) == def.ON) then
                            return "Set Q N H " .. helpers.addspaces(helpers.formatQnhValue(baropastmp, true))
                        else
                            return "Set Q N H " .. helpers.addspaces(helpers.formatQnhValue(baroinchtmp, false))
                        end
                    end,
                    action = function()
                        local tl = get(P.fmctranslvl)
                        if (tl == nil) or (tl <= 0) or (tl > 25000) then return end 
                        if (get(P.altitude) >= tl) then return end 
                        local baroinchtmp, _ = P.getlocalqnh(def.ARRIVAL)
                        helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
                        set(P.baropilot, baroinchtmp)
                    end,
                    confirm = function()
                        local baroinchtmp, baropastmp = P.getlocalqnh(def.ARRIVAL)
                        if (get(P.baroinhpa) == def.ON) then
                            return "Q N H checked and " .. helpers.addspaces(helpers.formatQnhValue(baropastmp, true))
                        else
                            return "Q N H checked and " .. helpers.addspaces(helpers.formatQnhValue(baroinchtmp, false))
                        end
                    end,
                    nextStep = nil
                }
            }
        },
        [def.ALTITUDEB10000PROCEDURE] = {
            number = 12,
            name = "Altitude Below 10000",
            cycable = true,
            speakname = false,
            set = false,
            loop = 1,
            prerequisite = nil,
            allowedState = def.AIRONLY,
            requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH },
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end, 
                  failMsg = "Procedure only available Inflight" },
                { 
                  check = function(loop) 
                      if not loop.triggeredmanually then return true end
                      local destination_altitude = get(P.desrwyalt)
                      if P.airportdatatable[get(P.desicao)] and P.airportdatatable[get(P.desicao)].elevation_ft then
                          destination_altitude = P.airportdatatable[get(P.desicao)].elevation_ft
                      end
                      local height_above_field = 99999
                      if destination_altitude and destination_altitude > -1000 then
                          height_above_field = get(P.altitude) - destination_altitude
                      end
                      local radio_alt = get(P.radioaltitude)
                      local lower_airspace_alt = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
                      return (height_above_field < lower_airspace_alt) or (radio_alt < lower_airspace_alt)
                  end, 
                  failMsg = "Procedure only possible below lower Airspace Altitude" 
                }
            },
            startStep = 'announce_below_10000',
            steps = {
                ['announce_below_10000'] = {
                    action = function() P.commandtableentry(def.TEXT, "Below " .. P.configvalues[def.CONFIGLOWEAIRSPACEALT] .. " Feet") end,
                    runActionInAdviceMode = true;
                    nextStep = 'set_view_overhead'
                },
                ['set_view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'set_seatbelts_on'
                },
                ['set_seatbelts_on'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNON end,
                    advice = "Set Seatbeltsigns On",
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNON) end,
                    confirm = "Seatbelt Signs checked On",
                    nextStep = 'set_landing_lights_on'
                },
                ['set_landing_lights_on'] = {
                    check = function()
                        local ledVariant = (get(P.ledlightsvariant) == def.ON)
                        local thr = def.LEDLLIGHTSOFF or 0
                        if ledVariant then
                            return (get(P.llights1) > thr) and (get(P.llights4) > thr)
                        else
                            return (get(P.llights1) ~= def.OFF) and (get(P.llights2) ~= def.OFF)
                                and (get(P.llights3) ~= def.OFF) and (get(P.llights4) ~= def.OFF)
                        end
                    end,
                    advice = "Set Landing Lights On",
                    action = function() P.togglelandinglights(def.ON) end,
                    confirm = "Landing Lights checked On",
                    nextStep = 'set_starters_flight'
                },
                ['set_starters_flight'] = {
                    check = function() return (get(P.starter1pos) == def.FLIGHT) and (get(P.starter2pos) == def.FLIGHT) end,
                    advice = "Set Both Starters Flight",
                    action = function() P.setstarter(def.BOTH, def.FLIGHT) end,
                    confirm = "Both Starters checked Flight",
                    nextStep = 'set_logo_lights_on'
                },
                ['set_logo_lights_on'] = {
                    check = function() return get(P.logolighton) == def.ON end,
                    advice = "Set Logo Lights On",
                    action = function() P.togglelogolight(def.ON) end,
                    confirm = "Logo Lights checked On",
                    nextStep = 'set_view_main_1'
                },
                ['set_view_main_1'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON end,
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'trigger_ils_proc'
                },
                ['trigger_ils_proc'] = {
                    action = function()
                        P.triggerprocedure(def.SETILSPROCEDURE, false) 
                    end,
                    check = function()
                        local procKey = def.SETILSPROCEDURE
                        local procData = P.proceduretable[procKey]
                        if procData.set then
                            return true
                        else
                            return false
                        end
                    end,
                    advice = nil, 
                    confirm = nil,
                    runActionInAdviceMode = true,
                    nextStep = 'trigger_vref_proc' 
                },
                ['trigger_vref_proc'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVREF30SET] == def.OFF end,
                    action = function(loop)
                        if not loop then return end
                        local procData = P.proceduretable[def.SETVREFPROCEDURE]
                        if procData and procData.set then
                            loop.vrefproctriggered = nil
                            return
                        end

                        -- Only trigger SetVref if VREF is still empty and we haven't started waiting yet.
                        if get(P.vref) == 0 and not loop.vrefproctriggered then
                            local ok = P.triggerprocedure(def.SETVREFPROCEDURE, false)
                            -- Mark as waiting if we successfully triggered OR if the target loop is now running SetVref.
                            local loop3 = P.loopStateTables and P.loopStateTables[3]
                            local running = loop3 and (loop3.lock == def.SETVREFPROCEDURE)
                            if ok or running then
                                loop.vrefproctriggered = true
                            end
                        end
                    end,
                    check = function(loop)
                        local procKey = def.SETVREFPROCEDURE 
                        local procData = P.proceduretable[procKey]
                        if procData and procData.set then
                            if loop then loop.vrefproctriggered = nil end
                            return true
                        end

                        -- If we triggered SetVref from this step, wait until it completes.
                        if loop and loop.vrefproctriggered then
                            local loop3 = P.loopStateTables and P.loopStateTables[3]
                            local running = loop3 and (loop3.lock == def.SETVREFPROCEDURE)
                            -- If SetVref is no longer running but VREF is set, assume it was completed/aborted after manual input and continue.
                            if not running and get(P.vref) ~= 0 then
                                loop.vrefproctriggered = nil
                                return true
                            end
                            return false
                        end

                        -- If we didn't trigger SetVref here, treat "VREF already set" as sufficient to proceed.
                        return get(P.vref) ~= 0
                    end,
                    advice = nil,
                    confirm = function() 
                        if get(P.vref) ~= 0 then 
                            return "V REF flaps " .. get(P.appflaps) .. " checked and " .. get(P.vref) 
                        else 
                            return false 
                        end
                    end,
                    runActionInAdviceMode = true, 
                    nextStep = 'trigger_windcorr_proc' 
                },
                ['trigger_windcorr_proc'] = {
                    skipIf = function(loop)
                        local skip = P.configvalues[def.CONFIGVREF30SET] == def.OFF
                        return skip
                    end,
                    action = function(loop)
                        if not loop then return end
                        local procData = P.proceduretable[def.SETWINDCORRPROCEDURE]
                        if procData and procData.set then
                            loop.windcorrproctriggered = nil
                            return
                        end

                        if not loop.windcorrproctriggered then
                            local ok = P.triggerprocedure(def.SETWINDCORRPROCEDURE, false)
                            local loop3 = P.loopStateTables and P.loopStateTables[3]
                            local running = loop3 and (loop3.lock == def.SETWINDCORRPROCEDURE)
                            if ok or running then
                                loop.windcorrproctriggered = true
                            end
                        end
                    end,
                    check = function(loop)
                        local procKey = def.SETWINDCORRPROCEDURE
                        local procData = P.proceduretable[procKey]
                        if procData and procData.set then
                            if loop then loop.windcorrproctriggered = nil end
                            return true
                        end

                        if loop and loop.windcorrproctriggered then
                            local loop3 = P.loopStateTables and P.loopStateTables[3]
                            local running = loop3 and (loop3.lock == def.SETWINDCORRPROCEDURE)
                            if not running then
                                loop.windcorrproctriggered = nil
                                return true
                            end
                            return false
                        end

                        return false
                    end,
                    advice = nil,
                    confirm = nil,
                    runActionInAdviceMode = true,
                    nextStep = 'set_view_main_2'
                },
                ['set_view_main_2'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON end,
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'set_autobrake'
                },
                ['set_autobrake'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVREF30SET] ~= def.ON end,
                    check = function()
                        local current = get(P.autobrakepos)
                        if P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] ~= def.ON then
                            return current > def.AUTOBRAKEOFF
                        end
                        if current > def.AUTOBRAKEOFF then return true end
                        local autobrake = helpers.calcautobrake(get(P.vref), get(P.totalweightkgs), get(P.desrwylen), P.desmetar, true)
                        return current == autobrake
                    end,
                    advice = function()
                        if get(P.autobrakepos) > def.AUTOBRAKEOFF then return false end
                        if P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] ~= def.ON then
                            return "Set Auto Brake"
                        end
                        local autobrake = helpers.calcautobrake(get(P.vref), get(P.totalweightkgs), get(P.desrwylen), P.desmetar, true)
                        if (autobrake < def.AUTOBRAKEMAX) then return "Set Auto Brake " .. tostring(autobrake - 1)
                        else return "Set Auto Brake Maximum" end
                    end,
                    action = function()
                        if get(P.autobrakepos) > def.AUTOBRAKEOFF then return end
                        if P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] ~= def.ON then
                            return
                        end
                        local autobrake = helpers.calcautobrake(get(P.vref), get(P.totalweightkgs), get(P.desrwylen), P.desmetar, true)
                        P.setautobrake(autobrake)
                    end,
                    confirm = function()
                        local current = get(P.autobrakepos)
                        if current <= def.AUTOBRAKEOFF then
                            return false
                        end
                        if (current < def.AUTOBRAKEMAX) then return "Auto Brake checked " .. tostring(current - 1)
                        else return "Auto Brake checked Maximum" end
                    end,
                    nextStep = 'speak_des_metar_2'
                },
                ['speak_des_metar_2'] = {
                    action = function() P.speakdesmetar() end,
                    nextStep = nil
                }
            }
        },
        [def.RADIOALTITUDEB2500PROCEDURE] = {
            number = 13,
            name = "Altitude Below 2500",
            cycable = false,
            speakname = false,
            set = false,
            loop = 1,
            prerequisite = def.ALTITUDEB10000PROCEDURE,
            allowedState = def.AIRONLY,
            requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH },
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end, 
                  failMsg = "Procedure only available Inflight" }
            },
            startStep = 'check_gear_down',
            steps = {
                ['check_gear_down'] = {
                    skipIf = function()
                        return (helpers.convflaplevertoflappos(get(P.flapleverpos)) < P.configvalues[def.CONFIGGEARDOWNFLAPS])
                    end,
                    check = function() 
                        return get(P.gearhandlepos) == def.GEARDOWN 
                    end,
                    advice = "Set Gear Down",
                    action = function() 
                        set(P.gearhandlepos, def.GEARDOWN) 
                    end,
                    confirm = "Gear checked Down",
                    nextStep = nil
                }
            }
        },
        [def.RADIOALTITUDEB1000PROCEDURE] = {
            number = 14,
            name = "Altitude Belowe 1000 ",
            cycable = false,
            speakname = false,
            set = false,
            loop = 1,
            prerequisite = def.RADIOALTITUDEB2500PROCEDURE,
            allowedState = def.AIRONLY,
            requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH },
            skipCondition = nil,           
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end, 
                  failMsg = "Procedure only available Inflight" }
            },
            transitionConditions = {
                { condition = function() return get(P.airgroundsensor) == def.ON end }
            }, 
            startStep = 'arm_speedbrakes',
            steps = {
                ['arm_speedbrakes'] = {
                    check = function() return helpers.roundnumber(get(P.speedbrakelever), 1) == def.SPEEDBRAKEARMED end,
                    advice = "Arm Speed Brakes",
                    action = function() set(P.speedbrakelever, def.SPEEDBRAKEARMED) end,
                    confirm = "Speedbrakes checked Armed",
                    nextStep = 'set_taxi_lights_on'
                },
                ['set_taxi_lights_on'] = {
                    check = function() return get(P.taxilight) ~= def.OFF end,
                    advice = "Set Taxi Lights On",
                    action = function() P.toggletaxilights(def.ON) end,
                    confirm = "Taxi Lights checked On",
                    nextStep = 'set_rwy_lights_on'
                },
                ['set_rwy_lights_on'] = {
                    check = function() return (get(P.rwylightl) ~= def.OFF) and (get(P.rwylightr) ~= def.OFF) end,
                    advice = "Set Runway Turnoff Lights On",
                    action = function() P.togglerwylights(def.ON) end,
                    confirm = "Runway Turnoff Lights checked On",
                    nextStep = 'set_gear_down'
                },
                ['set_gear_down'] = {
                    check = function() return get(P.gearhandlepos) == def.GEARDOWN end,
                    advice = "Set Gear Down",
                    action = function() set(P.gearhandlepos, def.GEARDOWN) end,
                    confirm = "Gear checked Down",
                    nextStep = 'set_app_flaps'
                },
                ['set_app_flaps'] = {
                    check = function() return (get(P.appflapsset) == def.ON) or (get(P.appflaps) == 0) end,
                    advice = function() return "Set Flaps " .. tostring(get(P.appflaps)) end,
                    action = function() helpers.command_once("laminar/B738/push_button/flaps_" .. tostring(get(P.appflaps))) end,
                    confirm = function() return "Flaps checked and " .. tostring(get(P.appflaps)) end,
                    nextStep = 'check_mcp_speed_vapp'
                },
                ['check_mcp_speed_vapp'] = {
                    check = function(loop)
                        local vref = loop and loop.appvrefcalc or get(P.vref) or 0
                        local customCalcOn = P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] == def.ON
                        local windcorr = customCalcOn and 0 or ((loop and loop.appwindcorr) or get(P.vrefapproachwindcorr) or 0)
                        local target = tonumber(vref) or 0
                        target = target + (tonumber(windcorr) or 0)
                        if target <= 0 then return true end -- nichts bekannt, weiter

                        local mcp = get(P.mcpspeed) or 0
                        local tol = 5 -- kts oberhalb VAPP
                        if mcp <= 0 then return false end

                        if mcp >= target and mcp <= (target + tol) then
                            return true
                        end

                        if P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON then
                            set(P.mcpspeed, target)
                            return true
                        end

                        return false
                    end,
                    advice = function(loop)
                        local vref = loop and loop.appvrefcalc or get(P.vref) or 0
                        local customCalcOn = P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] == def.ON
                        local windcorr = customCalcOn and 0 or ((loop and loop.appwindcorr) or get(P.vrefapproachwindcorr) or 0)
                        local target = tonumber(vref) or 0
                        target = target + (tonumber(windcorr) or 0)
                        if target <= 0 then return "Check M C P Speed" end
                        return "Set M C P Speed " .. helpers.addspaces(helpers.roundnumber(target))
                    end,
                    confirm = function(loop)
                        local vref = loop and loop.appvrefcalc or get(P.vref) or 0
                        local customCalcOn = P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] == def.ON
                        local windcorr = customCalcOn and 0 or ((loop and loop.appwindcorr) or get(P.vrefapproachwindcorr) or 0)
                        local target = tonumber(vref) or 0
                        target = target + (tonumber(windcorr) or 0)
                        if target <= 0 then return "M C P Speed check skipped" end
                        local mcp = get(P.mcpspeed) or 0
                        local tol = 5
                        if mcp >= target and mcp <= (target + tol) then
                            return "M C P Speed checked " .. helpers.addspaces(helpers.roundnumber(mcp))
                        end
                        return false
                    end,
                    nextStep = 'set_mcp_heading'
                },
                ['set_mcp_heading'] = {
                    check = function()
                        local headingrounded = getMcpHeadingTarget()
                        if not headingrounded then
                            helpers.logInfoTS("set_mcp_heading: Skipping, no valid runway heading found to check against.")
                            return true
                        end
                        if get(P.aphdgselstat) ~= def.OFF then
                            helpers.logInfoTS("set_mcp_heading: Skipping, HDG SEL mode is active.")
                            return true
                        end
                        return (headingrounded == get(P.mcpheading))
                    end,
                    advice = function()
                        local headingrounded = getMcpHeadingTarget()
                        if headingrounded then
                            return "Set M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3))
                        else
                            return "Set M C P Heading"
                        end
                    end,
                    action = function()
                        local headingrounded = getMcpHeadingTarget()
                        if (headingrounded and (get(P.aphdgselstat) == def.OFF)) then
                            set(P.mcpheading, headingrounded)
                        end
                    end,
                    confirm = function(loop)
                        local headingrounded = getMcpHeadingTarget()
                        if (headingrounded and (get(P.aphdgselstat) == def.OFF) and (headingrounded == get(P.mcpheading))) then
                            if loop then
                                loop.mcpHeadingSet = true
                            end
                            return "M C P Heading checked " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3))
                        end
                        return false
                    end,
                    nextStep = 'set_mcp_altitude'
                },
                ['set_mcp_altitude'] = {
                    check = function(loop)
                        local missedappalttmp = getMissedApproachAlt(loop)
                        if (missedappalttmp > 1000) then
                            local current = get(P.mcpaltitude)
                            return math.abs(current - missedappalttmp) <= 100
                        else
                            if loop and not loop.missedAppAltInvalidWarned then
                                P.commandtableentry(def.TEXT, "Missed Approach Altitude missing or invalid")
                                loop.missedAppAltInvalidWarned = true
                            end
                            return true
                        end
                    end,
                    advice = function(loop)
                        local missedappalttmp = getMissedApproachAlt(loop)
                        if (missedappalttmp > 1000) then
                            return "Set M C P Altitude " .. helpers.addspaces(missedappalttmp)
                        else
                            return "Set Missed Approach Altitude"
                        end
                    end,
                    action = function(loop)
                        local missedappalttmp = getMissedApproachAlt(loop)
                        if (missedappalttmp > 1000) then
                            set(P.mcpaltitude, missedappalttmp)
                        end
                    end,
                    confirm = function(loop)
                        local missedappalttmp = getMissedApproachAlt(loop)
                        if (missedappalttmp > 1000) then
                            local current = get(P.mcpaltitude)
                            if math.abs(current - missedappalttmp) <= 100 then
                                return "M C P Altitude checked " .. helpers.addspaces(missedappalttmp)
                            end
                            return false
                        end
                        if loop and loop.missedAppAltInvalidWarned then
                            return "Missed Approach Altitude invalid, step acknowledged"
                        end
                        return false
                    end,
                    nextStep = 'announce_wind'
                },
                ['announce_wind'] = {
                    action = function()
                        local windreport = nil
                        if (P.desmetar and P.airportdatatable[get(P.desicao)] and P.airportdatatable[get(P.desicao)].latitude and P.airportdatatable[get(P.desicao)].longitude) then
                            windreport = helpers.formatWindSpeechSummary(P.desmetar, P.airportdatatable[get(P.desicao)].latitude, P.airportdatatable[get(P.desicao)].longitude)
                        elseif (P.desmetar and helpers.isvalidrwy(get(P.desrwy))) then
                            windreport = helpers.formatWindSpeechSummary(P.desmetar, get(P.desrwylatstartpos), get(P.desrwylonstartpos))
                        end
                        if (windreport ~= nil) then
                            P.commandtableentry(def.TEXT, windreport)
                        end
                    end,
                    nextStep = nil
                }
            }
        },
        [def.GOAROUNDPROCEDURE] = {
            number = 24,
            name = "Go Around",
            cycable = false,
            speakname = true,
            set = false,
            loop = 2,
            prerequisite = nil,
            allowedState = def.AIRONLY,
            requiredFlightstate = def.FLIGHTSTATEAPPROACH,
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end,
                  failMsg = "Procedure only available Inflight" },
                { check = function()
                      local radioAlt = get(P.radioaltitude) or 0
                      return radioAlt < 2500
                  end,
                  failMsg = "Procedure only available below 2500 A G L" }
            },
            startStep = 'announce_goaround',
            steps = {
                ['announce_goaround'] = {
                    action = function()
                        local loop1 = P.loopStateTables and P.loopStateTables[1]
                        if loop1 and loop1.lock ~= def.NOPROCEDURE then
                            helpers.logInfoTS("Go Around: aborting active procedure on Loop 1 (ID: " .. tostring(loop1.lock) .. ").")
                            loop1.procedureabort = true
                            loop1.procedureskipstep = false
                            loop1.setonabort = false
                        end
                        if P.proceduretable[def.RADIOALTITUDEB2500PROCEDURE] then
                            P.proceduretable[def.RADIOALTITUDEB2500PROCEDURE].set = false
                        end
                        if P.proceduretable[def.RADIOALTITUDEB1000PROCEDURE] then
                            P.proceduretable[def.RADIOALTITUDEB1000PROCEDURE].set = false
                        end
                        P.commandtableentry(def.TEXT, "Go Around")
                    end,
                    confirm = "Go Around acknowledged",
                    nextStep = 'set_goaround_speed'
                },
                ['set_goaround_speed'] = {
                    action = function()
                        local vref = get(P.vref) or 0
                        local gaSpeed = vref + 20
                        if gaSpeed > 0 then
                            if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                                set(P.mcpspeed, gaSpeed)
                            end
                            P.commandtableentry(def.TEXT, "Set M C P Speed " .. tostring(gaSpeed))
                        end
                    end,
                    confirm = function()
                        local vref = get(P.vref) or 0
                        local gaSpeed = vref + 20
                        if gaSpeed > 0 and get(P.mcpspeed) == gaSpeed then
                            return "M C P Speed checked " .. tostring(gaSpeed)
                        end
                        return false
                    end,
                    nextStep = 'gear_up'
                },
                ['gear_up'] = {
                    check = function()
                        return get(P.gearhandlepos) == def.GEARUP
                    end,
                    advice = "Set Gear Up",
                    action = function()
                        if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                            set(P.gearhandlepos, def.GEARUP)
                        end
                    end,
                    confirm = "Gear checked Up",
                    nextStep = 'set_missed_altitude'
                },
                ['set_missed_altitude'] = {
                    check = function(loop)
                        local missedappalttmp = getMissedApproachAlt(loop)
                        if (missedappalttmp > 1000) then
                            local current = get(P.mcpaltitude)
                            return math.abs(current - missedappalttmp) <= 100
                        else
                            if loop and not loop.missedAppAltInvalidWarned then
                                P.commandtableentry(def.TEXT, "Missed Approach Altitude missing or invalid")
                                loop.missedAppAltInvalidWarned = true
                            end
                            return true
                        end
                    end,
                    advice = function(loop)
                        local missedappalttmp = getMissedApproachAlt(loop)
                        if (missedappalttmp > 1000) then
                            return "Set M C P Altitude " .. helpers.addspaces(missedappalttmp)
                        else
                            return "Set Missed Approach Altitude"
                        end
                    end,
                    action = function(loop)
                        local missedappalttmp = getMissedApproachAlt(loop)
                        if (missedappalttmp > 1000) then
                            set(P.mcpaltitude, missedappalttmp)
                        end
                    end,
                    confirm = function(loop)
                        local missedappalttmp = getMissedApproachAlt(loop)
                        if (missedappalttmp > 1000) then
                            local current = get(P.mcpaltitude)
                            if math.abs(current - missedappalttmp) <= 100 then
                                return "M C P Altitude checked and " .. helpers.addspaces(missedappalttmp)
                            end
                            return false
                        end
                        if loop and loop.missedAppAltInvalidWarned then
                            return "Missed Approach Altitude invalid, step acknowledged"
                        end
                        return false
                    end,
                    nextStep = 'check_missed_route_discontinuity'
                },
                               ['check_missed_route_discontinuity'] = {
                    action = function()
                        local legs = get(P.fmslegs)
                        local destRunway = get(P.desrwy)
                        if type(legs) ~= "string" or legs == "" or not helpers.isvalidrwy(destRunway) then
                            return
                        end

                        local prevToken = nil
                        local discoAfterRunway = false
                        for token in legs:gmatch("([^%s]+)") do
                            if token:upper() == "DISCONTINUITY" then
                                if matchesDestRunway(prevToken, destRunway) then
                                    discoAfterRunway = true
                                    break
                                end
                            elseif token and token ~= "" then
                                prevToken = token
                            end
                        end

                        if discoAfterRunway then
                            P.commandtableentry(def.TEXT, "Discontinuity after runway before missed approach")
                        end
                    end,
                    nextStep = 'set_flaps_15'
                },
                ['set_flaps_15'] = {
                    check = function()
                        local flaps = get(P.flapleverpos)
                        return flaps and flaps >= def.FLAPS15
                    end,
                    advice = nil,
                    confirm = "Flaps checked 15",
                    nextStep = 'accelerate_and_cleanup'
                },
                ['accelerate_and_cleanup'] = {
                    advice = "Accelerate, retract flaps on schedule, select L N A V/V N A V or Heading/Altitude",
                    confirm = "Go Around profile established",
                    nextStep = nil
                }
            }
        },
        [def.ENGINEINFLIGHTRESTARTPROCEDURE] = {
            number = 26,
            name = "Engine In-Flight Restart",
            cycable = false,
            speakname = true,
            set = false,
            loop = 1,
            prerequisite = nil,
            allowedState = def.AIRONLY,
            requiredFlightstate = nil,
            skipCondition = function() return P.enginesrunning(def.BOTH) end,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.OFF end,
                  failMsg = "Procedure only available Inflight" },
                { check = function() return not P.enginesrunning(def.BOTH) end,
                  failMsg = "Procedure not possible, both engines running" }
            },
            startStep = 'preconditions_note',
            steps = {
                ['preconditions_note'] = {
                    confirm = "Verify no engine fire, N 1 rotation, no abnormal vibration. Check In-Flight Start Envelope",
                    nextStep = 'select_engine'
                },
                ['select_engine'] = {
                    branch = function(loop)
                        local eng1_running = P.enginesrunning(def.ENGINE1)
                        local eng2_running = P.enginesrunning(def.ENGINE2)
                        if (not eng1_running) and eng2_running then
                            loop.engine = def.ENGINE1
                            loop.bothEngines = false
                        elseif (not eng2_running) and eng1_running then
                            loop.engine = def.ENGINE2
                            loop.bothEngines = false
                        elseif (not eng1_running) and (not eng2_running) then
                            loop.engine = def.ENGINE1
                            loop.bothEngines = true
                        else
                            return nil
                        end
                        return 'view_throttle'
                    end
                },
                ['view_throttle'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'thrust_lever_close'
                },
                ['thrust_lever_close'] = {
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Close Thrust Lever (Engine " .. ctx.engineLabel .. ")"
                    end,
                    nextStep = 'start_lever_cutoff'
                },
                ['start_lever_cutoff'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return get(ctx.mixturePos) == def.OFF
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Set Engine Start Lever (Engine " .. ctx.engineLabel .. ") Cutoff"
                    end,
                    action = function(loop)
                        if inflight_restart_auto_enabled() then
                            local ctx = get_inflight_restart_context(loop)
                            helpers.command_once(ctx.mixtureCutoffCmd)
                        end
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine Start Lever " .. ctx.engineLabel .. " checked Cutoff"
                    end,
                    nextStep = 'view_overhead'
                },
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'select_start_method'
                },
                ['select_start_method'] = {
                    branch = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        local n2 = get(ctx.n2Percent) or 0
                        if n2 >= 15 then
                            return 'start_switch_flt'
                        end
                        return 'crossbleed_pack_off'
                    end
                },
                ['start_switch_flt'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return get(ctx.starterPos) == def.FLIGHT
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine Start Switch (Engine " .. ctx.engineLabel .. ") Flight"
                    end,
                    action = function(loop)
                        if inflight_restart_auto_enabled() then
                            local ctx = get_inflight_restart_context(loop)
                            P.setstarter(ctx.engine, def.FLIGHT)
                        end
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine Start Switch " .. ctx.engineLabel .. " checked Flight"
                    end,
                    nextStep = 'view_throttle_for_idle'
                },
                ['crossbleed_pack_off'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return get(ctx.packPos) == def.PACKOFF
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Set Pack " .. ctx.sideLabel .. " Off"
                    end,
                    action = function(loop)
                        if inflight_restart_auto_enabled() then
                            local ctx = get_inflight_restart_context(loop)
                            set(ctx.packPos, def.PACKOFF)
                        end
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Pack " .. ctx.sideLabel .. " checked Off"
                    end,
                    nextStep = 'crossbleed_duct_pressure'
                },
                ['crossbleed_duct_pressure'] = {
                    confirm = "Confirm Duct Pressure minimum 30 P S I, advance thrust lever as needed",
                    nextStep = 'crossbleed_start_switch_grd'
                },
                ['crossbleed_start_switch_grd'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return get(ctx.starterPos) == def.GROUND
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine Start Switch (Engine " .. ctx.engineLabel .. ") Ground"
                    end,
                    action = function(loop)
                        if inflight_restart_auto_enabled() then
                            local ctx = get_inflight_restart_context(loop)
                            P.setstarter(ctx.engine, def.GROUND)
                        end
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine Start Switch " .. ctx.engineLabel .. " checked Ground"
                    end,
                    nextStep = 'view_throttle_for_idle'
                },
                ['view_throttle_for_idle'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'wait_n2_11'
                },
                ['wait_n2_11'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return (get(ctx.n2Percent) or 0) >= 11
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine " .. ctx.engineLabel .. " N 2 at 11 Percent"
                    end,
                    nextStep = 'start_lever_idle'
                },
                ['start_lever_idle'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return get(ctx.mixturePos) == def.ON
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Set Engine Start Lever (Engine " .. ctx.engineLabel .. ") Idle"
                    end,
                    action = function(loop)
                        if inflight_restart_auto_enabled() then
                            local ctx = get_inflight_restart_context(loop)
                            helpers.command_once(ctx.mixtureIdleCmd)
                        end
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine Start Lever " .. ctx.engineLabel .. " checked Idle"
                    end,
                    nextStep = 'monitor_egt'
                },
                ['monitor_egt'] = {
                    confirm = "Monitor E G T, abort if no rise within 30 seconds",
                    nextStep = 'wait_engine_run'
                },
                ['wait_engine_run'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return P.enginesrunning(ctx.engine)
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Waiting for Engine " .. ctx.engineLabel .. " to start"
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine " .. ctx.engineLabel .. " running"
                    end,
                    nextStep = 'view_overhead_post'
                },
                ['view_overhead_post'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'set_gen_on'
                },
                ['set_gen_on'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return get(ctx.genPos) == def.ON
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Switch Engine " .. ctx.engineLabel .. " Generator On"
                    end,
                    action = function(loop)
                        if inflight_restart_auto_enabled() then
                            local ctx = get_inflight_restart_context(loop)
                            if ctx.engine == def.ENGINE1 and get(P.gen1pos) ~= def.ON then
                                helpers.command_once("laminar/B738/toggle_switch/gen1_dn")
                            elseif ctx.engine == def.ENGINE2 and get(P.gen2pos) ~= def.ON then
                                helpers.command_once("laminar/B738/toggle_switch/gen2_dn")
                            end
                        end
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine " .. ctx.engineLabel .. " Generator checked On"
                    end,
                    nextStep = 'set_pack_auto'
                },
                ['set_pack_auto'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return get(ctx.packPos) == def.PACKAUTO
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Set Pack " .. ctx.sideLabel .. " Auto"
                    end,
                    action = function(loop)
                        if inflight_restart_auto_enabled() then
                            local ctx = get_inflight_restart_context(loop)
                            set(ctx.packPos, def.PACKAUTO)
                        end
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Pack " .. ctx.sideLabel .. " checked Auto"
                    end,
                    nextStep = 'set_start_switch_auto'
                },
                ['set_start_switch_auto'] = {
                    check = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return get(ctx.starterPos) == def.AUTO
                    end,
                    advice = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine Start Switch (Engine " .. ctx.engineLabel .. ") Auto"
                    end,
                    action = function(loop)
                        if inflight_restart_auto_enabled() then
                            local ctx = get_inflight_restart_context(loop)
                            P.setstarter(ctx.engine, def.AUTO)
                        end
                    end,
                    confirm = function(loop)
                        local ctx = get_inflight_restart_context(loop)
                        return "Engine Start Switch " .. ctx.engineLabel .. " checked Auto"
                    end,
                    nextStep = 'apu_as_needed'
                },
                ['apu_as_needed'] = {
                    confirm = "A P U as needed",
                    nextStep = 'set_transponder_tara'
                },
                ['set_transponder_tara'] = {
                    check = function()
                        return get(P.transponderpos) == def.TARA
                    end,
                    advice = "Set Transponder T A / R A",
                    action = function()
                        if inflight_restart_auto_enabled() then
                            P.toggletransponder(def.TARA)
                        end
                    end,
                    confirm = "Transponder checked T A / R A",
                    nextStep = 'restart_complete'
                },
                ['restart_complete'] = {
                    confirm = function(loop)
                        if loop and loop.bothEngines then
                            return "Engine restart complete. Repeat for the other engine if required"
                        end
                        return "Engine restart complete"
                    end,
                    nextStep = nil
                }
            }
        },
        [def.AFTERLANDINGPROCEDURE] = {
            number = 15, 
            name = "After Landing", 
            cycable = true, 
            speakname = true,
            set = false, 
            loop = 1, 
            prerequisite = function() return (get(P.airgroundsensor) == def.ON) end, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATEAPPROACH, 
            skipCondition = nil,            
            prerequisiteChecks = {
                { check = function() return get(P.battery) == def.ON end, 
                  failMsg = "Procedure aborted, Battery is Off" }
            },
            transitionConditions = {
                { condition = function() return get(P.battery) ~= def.ON end } 
            },
            startStep = 'set_flightstate_taxitogate', 
            steps = {
                ['set_flightstate_taxitogate'] = {
                    action = function()
                    P.flightstate = def.FLIGHTSTATETAXITOGATE
                    set(P.flightstatedr, P.flightstate)
                    end,
                    nextStep = 'view_overhead'
                },
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'set_landing_lights_off'
                },
                ['set_landing_lights_off'] = {
                    check = function()
                        local ledVariant = (get(P.ledlightsvariant) == def.ON)
                        local thr = def.LEDLLIGHTSOFF or 0
                        if ledVariant then
                            return (get(P.llights1) <= thr) and (get(P.llights4) <= thr)
                        else
                            return (get(P.llights1) == def.OFF)
                                and (get(P.llights2) == def.OFF)
                                and (get(P.llights3) == def.OFF)
                                and (get(P.llights4) == def.OFF)
                        end
                    end,
                    advice = "Set Landing Lights Off",
                    action = function() P.togglelandinglights(def.OFF) end,
                    confirm = "Landing Lights checked Off",
                    nextStep = 'taxi_lights_on'
                },
                ['taxi_lights_on'] = {
                    check = function() return get(P.taxilight) ~= def.OFF end,
                    action = function() P.toggletaxilights(def.ON) end,
                    advice = "Set Taxi Lights On",
                    confirm = "Taxi Lights checked On",
                    nextStep = 'rwy_lights_off'
                },
                ['rwy_lights_off'] = {
                    check = function() return (get(P.rwylightl) == def.OFF) and (get(P.rwylightr) == def.OFF) end,
                    action = function() P.togglerwylights(def.OFF) end,
                    advice = "Set Runway Turnoff Lights Off",
                    confirm = "Runway Turnoff Lights checked Off",
                    nextStep = 'pos_lights_steady'
                },
                ['pos_lights_steady'] = {
                    check = function() return get(P.positionlights) == def.POSLIGHTSSTEADY end,
                    action = function() P.togglepositionlights(def.POSLIGHTSSTEADY) end,
                    advice = "Set Position Lights Steady",
                    confirm = "Position Lights checked Steady",
                    nextStep = 'view_pedestal'
                },
                ['view_pedestal'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWPEDESTAL] end,
                    nextStep = 'transponder_stby'
                },
                ['transponder_stby'] = {
                    skipIf = function() return P.configvalues[def.CONFIGTRANSPONDER] == 0 end,
                    check = function() return get(P.transponderpos) ~= def.TARA end,
                    action = function() P.toggletransponder(def.STANDBY) end,
                    advice = "Set Transponder Off",
                    confirm = function() return "Transponder checked Off" end,
                    nextStep = 'view_throttle'
                },
                ['view_throttle'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'flaps_up'
                },
                ['flaps_up'] = {
                    check = function() return get(P.flapleverpos) == def.FLAPSUP end,
                    action = function() helpers.command_once("laminar/B738/push_button/flaps_0") end,
                    advice = "Set Flaps Up",
                    confirm = "Flaps checked Up",
                    nextStep = 'speedbrake_down'
                },
                ['speedbrake_down'] = {
                    check = function() return helpers.roundnumber(get(P.speedbrakelever), 1) == def.SPEEDBRAKEDOWN end,
                    action = function() set(P.speedbrakelever, def.OFF) end,
                    advice = "Retract Speed Brakes",
                    confirm = "Speedbrakes Up and Retracted",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'fds_off'
                },
                ['fds_off'] = {
                    check = function() return (get(P.fdpilotpos) == def.OFF) and (get(P.fdfopos) == def.OFF) end,
                    action = function() P.togglefds(def.OFF) end,
                    advice = "Set Both Flight Directors Off",
                    confirm = "Both Flight Directors checked Off",
                    nextStep = 'wx_off'
                },
                ['wx_off'] = {
                    check = function() return (get(P.efiswxpilotpos) == def.OFF) and (get(P.efiswxfopos) == def.OFF) end,
                    action = function() P.togglewx(def.OFF) end,
                    advice = "Set Both Weather Radars Off",
                    confirm = "Both Weather Radars checked Off",
                    nextStep = 'terr_off'
                },
                ['terr_off'] = {
                    check = function() return (get(P.efisterrpilotpos) == def.OFF) and (get(P.efisterrfopos) == def.OFF) end,
                    action = function() P.toggleterr(def.OFF) end,
                    advice = "Set Both Terrain Radars Off",
                    confirm = "Both Terrain Radars checked Off",
                    nextStep = 'autobrake_off'
                },
                ['autobrake_off'] = {
                    check = function() return get(P.autobrakepos) == def.AUTOBRAKEOFF end,
                    action = function() P.setautobrake(def.AUTOBRAKEOFF) end,
                    advice = "Set Auto Brake Off",
                    confirm = "Auto Brake checked Off",
                    nextStep = 'ap_off'
                },
                ['ap_off'] = {
                    check = function() return get(P.aponstat) == def.OFF end,
                    action = function() set(P.aponstat, def.OFF) end,
                    advice = "Set Autopilot Off",
                    nextStep = 'master_caution'
                },
                ['master_caution'] = {
                    action = function() helpers.command_once("laminar/B738/push_button/master_caution1") end,
                    nextStep = nil
                }
            }
        },
        [def.ATPARKINGPOSITIONPROCEDURE] = {
            number = 16, 
            name = "At Parking Position", 
            cycable = true, 
            speakname = true,
            set = false, 
            loop = 1, 
            prerequisite = def.AFTERLANDINGPROCEDURE, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = { def.FLIGHTSTATETAXITOGATE, def.FLIGHTSTATESHUTDOWN }, 
            skipCondition = nil,           
            prerequisiteChecks = {
                { check = function() return get(P.battery) == def.ON end, 
                  failMsg = "Procedure aborted, Battery is Off" }
            },
            transitionConditions = {
                { condition = function() return get(P.battery) ~= def.ON end } 
            },
            startStep = 'set_flightstate_shutdown', 
            label_to_index = {},
            get_index = function(self, label) return nil end,
            steps = {
                ['set_flightstate_shutdown'] = {
                    action = function()
                        P.flightstate = def.FLIGHTSTATESHUTDOWN
                        set(P.flightstatedr, P.flightstate)
                    end,
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    normalize = true,
                    nextStep = 'set_chocks'
                },
                ['set_chocks'] = {
                    skipIf = function() return P.configvalues[def.CONFIGAUTOCHOCKSPB] == def.OFF end,
                    check = function() return get(P.chockstatus) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/chock") end,
                    advice = "Set Chocks",
                    confirm = "Chocks checked and Set",
                    nextStep = 'check_night',
                    runActionInAdviceMode = true
                },
                ['check_night'] = {
                    skipIf = function() return get(P.sunpitchdegrees) > 0 end,
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    nextStep = 'dome_light_on'
                },
                ['dome_light_on'] = {
                    skipIf = function() return get(P.sunpitchdegrees) > 0 end,
                    check = function() return get(P.domelightpos) ~= def.DOMELIGHTOFF end,
                    action = function() P.setdomelight(def.DOMELIGHTDIM) end,
                    advice = "Set Dome Light On",
                    confirm = "Dome light checked On",
                    nextStep = 'view_pedestal'
                },
                ['view_pedestal'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWPEDESTAL] end,
                    nextStep = 'transponder_stby'
                },
                ['transponder_stby'] = {
                    skipIf = function() return P.configvalues[def.CONFIGTRANSPONDER] == 0 end,
                    check = function() return get(P.transponderpos) == def.STANDBY end,
                    action = function() P.toggletransponder(def.STANDBY) end,
                    advice = "Set Transponder Standby",
                    confirm = "Transponder checked Standby",
                    nextStep = 'view_overhead'
                },
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'taxi_light_off'
                },
                ['taxi_light_off'] = {
                    check = function() return get(P.taxilight) == def.OFF end,
                    action = function() P.toggletaxilights(def.OFF) end,
                    advice = "Set Taxi Lights Off",
                    confirm = "Taxi Lights checked Off",
                    nextStep = 'logo_light_off'
                },
                ['logo_light_off'] = {
                    check = function() return get(P.logolighton) == def.OFF end,
                    action = function() P.togglelogolight(def.OFF) end,
                    advice = "Set Logo Lights Off",
                    confirm = "Logo Lights checked Off",
                    nextStep = 'seatbelts_off'
                },
                ['seatbelts_off'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF end,
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNOFF) end,
                    advice = "Set Seatbeltsigns Off",
                    confirm = "Seatbeltsigns checked Off",
                    nextStep = 'starters_auto'
                },
                ['starters_auto'] = {
                    check = function() return (get(P.starter1pos) == def.AUTO) and (get(P.starter2pos) == def.AUTO) end,
                    action = function() P.setstarter(def.BOTH, def.AUTO) end,
                    advice = function() 
                        if (get(P.starterauto) == def.ON) then return "Set Both Starters Auto"
                        else return "Set Both Starters Off" end
                    end,
                    confirm = function()
                        if (get(P.starterauto) == def.ON) then return "Both Starters checked Auto"
                        else return "Both Starters checked Off" end
                    end,
                    nextStep = 'set_wipers_off'
                },
                ['set_wipers_off'] = {
                    check = function() 
                        return (get(P.lwiperpos) == def.WIPEROFF) and (get(P.rwiperpos) == def.WIPEROFF) 
                    end,
                    action = function() 
                        P.autowiper(def.WIPEROFF)
                    end,
                    advice = "Set Both Wipers Off",
                    confirm = "Wipers checked Off",
                    nextStep = 'view_main_panel_final'
                },
                ['view_main_panel_final'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.TURNAROUNDENGINESHUTDOWNPROCEDURE] = {
            number = 17, 
            name = "Turnaround Engine Shutdown", 
            cycable = true, 
            speakname = true,
            set = false, 
            loop = 1, 
            prerequisite = function() return (get(P.parkingbrakepos) == def.ON) end, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = nil, 
            skipCondition = function() return not P.enginesrunning(def.BOTH) end,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.ON end, 
                  failMsg = "Procedure not possible Inflight" },
                { check = function() return P.enginesrunning(def.BOTH) end, 
                  failMsg = "Procedure aborted, Engines not running", setonabort = true }
            },
            startStep = 'view_overhead',
            steps = {
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'check_power_source'
                },
                ['check_power_source'] = {
                    branch = function(loop, procData)
                        if (P.configvalues[def.CONFIGUSEGROUNDPOWER] == def.ON) and (get(P.gpuavailable) == def.ON) then
                            loop.power_source = 'gpu'
                            return 'check_gpu_power'
                        else
                            loop.power_source = 'apu'
                            return 'start_apu'
                        end
                    end
                },
                ['check_gpu_power'] = {
                    check = function() return get(P.gpuon) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/gpu_dn") end,
                    advice = "Set Ground Power On",
                    confirm = "G P U checked On",
                    nextStep = 'verify_power_source_ready'
                },
                ['start_apu'] = {
                    check = function() return get(P.apustarterpos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    advice = "Start A P U",
                    confirm = "A P U checked and Started",
                    nextStep = 'start_apu_2'
                },                
                ['start_apu_2'] = {
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    nextStep = 'wait_apu_runup'
                },          
                ['wait_apu_runup'] = {
                    check = function() return P.apurunning() >= def.APUOFFBUS end,
                    confirm = "A P U Running Up",
                    nextStep = 'set_apu_gen'
                },
                ['set_apu_gen'] = {
                    check = function() return P.apurunning() == def.APUONBUS end,
                    action = function() 
                        if not((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                            helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                        end
                        if not((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                            helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                        end
                    end,
                    advice = "Set A P U Generator On",
                    confirm = "A P U Generator checked On",
                    nextStep = 'set_apu_bleed'
                },
                ['set_apu_bleed'] = {
                    check = function() return get(P.bleedairapupos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Set A P U Bleed On",
                    confirm = "A P U Bleed checked On",
                    nextStep = 'set_isol_valve'
                },
                ['set_isol_valve'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEOPEN end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEOPEN) end,
                    advice = "Set Isolation Valve Open",
                    confirm = "Isolation Valve checked Open",
                    nextStep = 'verify_power_source_ready'
                },
                ['verify_power_source_ready'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    check = function(loop)
                        local gpu_on = (get(P.gpuon) == def.ON)
                        local apu_ready = (P.apurunning() == def.APUONBUS) and (get(P.bleedairapupos) == def.ON)
                        if loop.power_source == 'gpu' then
                            return gpu_on
                        end
                        return apu_ready
                    end,
                    advice = function(loop)
                        if loop.power_source == 'gpu' then
                            return "Set Ground Power On Bus"
                        end
                        return "Set A P U Power On Bus"
                    end,
                    confirm = function(loop)
                        if loop.power_source == 'gpu' then
                            if (get(P.gpuon) == def.ON) then
                                return "Ground Power checked On"
                            end
                            return false
                        end
                        if (P.apurunning() == def.APUONBUS) and (get(P.bleedairapupos) == def.ON) then
                            return "A P U Power and Bleed checked On"
                        end
                        return false
                    end,
                    nextStep = 'set_engine_bleeds_off'
                },
                ['set_engine_bleeds_off'] = {
                    check = function()
                        return (get(P.bleedair1pos) == def.OFF) and (get(P.bleedair2pos) == def.OFF)
                    end,
                    action = function()
                        if (get(P.bleedair1pos) ~= def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_1") end
                        if (get(P.bleedair2pos) ~= def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_2") end
                    end,
                    advice = "Set Both Engine Bleeds Off",
                    confirm = "Both Engine Bleeds checked Off",
                    nextStep = 'view_throttle'
                },
                ['view_throttle'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'set_fuel_levers_cutoff'
                },
                ['set_fuel_levers_cutoff'] = {
                    check = function() return (get(P.mixture1pos) == def.OFF) and (get(P.mixture2pos) == def.OFF) end,
                    action = function() 
                        if (get(P.mixture2pos) ~= def.OFF) then helpers.command_once("laminar/B738/engine/mixture2_cutoff") end
                        if (get(P.mixture1pos) ~= def.OFF) then helpers.command_once("laminar/B738/engine/mixture1_cutoff") end
                    end,
                    advice = "Set Both Engine Fuel Levers Cutoff",
                    confirm = "Both Fuel Levers checked and Cutoff",
                    nextStep = 'view_overhead_2'
                },
                ['view_overhead_2'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'probe_heat_off'
                },
                ['probe_heat_off'] = {
                    check = function() return (get(P.captainprobepos) == def.OFF) and (get(P.foprobepos) == def.OFF) end,
                    action = function() P.toggleprobeheat(def.OFF) end,
                    advice = "Set Probe Heat Off",
                    confirm = "Probe Heat checked Off",
                    nextStep = 'ice_off'
                },
                ['ice_off'] = {
                    skipIf = function()
                        local wx = P.desmetar.decodedmetar
                        return helpers.isGroundIcingCondition(wx)
                    end,
                    check = function()
                        return (get(P.eng1heatpos) == def.OFF)
                        and (get(P.eng2heatpos) == def.OFF)
                        and (get(P.wingheatpos) == def.OFF)
                    end,
                    action = function() P.iceprotection(def.OFF) end,
                    advice = "Set Anti Ice Off",
                    nextStep = 'set_engine_bleeds_off_final'
                },
                ['set_engine_bleeds_off_final'] = {
                    check = function()
                        return (get(P.bleedair1pos) == def.OFF) and (get(P.bleedair2pos) == def.OFF)
                    end,
                    action = function()
                        if (get(P.bleedair1pos) ~= def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_1") end
                        if (get(P.bleedair2pos) ~= def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_2") end
                    end,
                    advice = "Set Both Engine Bleeds Off",
                    confirm = "Both Engine Bleeds checked Off",
                    nextStep = 'center_pumps_off'
                },
                ['center_pumps_off'] = {
                    check = function() return (get(P.centertanklswitch) == def.OFF) and (get(P.centertankrswitch) == def.OFF) end,
                    action = function() set(P.centertanklswitch, def.OFF); set(P.centertankrswitch, def.OFF) end,
                    advice = "Set Center Tank Fuel Pumps Off",
                    confirm = "Center Tank Fuel Pumps checked Off",
                    nextStep = 'wing_pumps_off'
                },
                ['wing_pumps_off'] = {
                    check = function(loop)
                        local keep_left_fwd = (loop and loop.power_source == 'apu') and (P.apurunning() == def.APUONBUS)
                        if keep_left_fwd then
                            return  (get(P.lefttanklswitch) == def.ON)
                                and (get(P.lefttankrswitch) == def.OFF)
                                and (get(P.righttanklswitch) == def.OFF)
                                and (get(P.righttankrswitch) == def.OFF)
                        end
                        return  (get(P.lefttanklswitch) == def.OFF)
                            and (get(P.lefttankrswitch) == def.OFF)
                            and (get(P.righttanklswitch) == def.OFF)
                            and (get(P.righttankrswitch) == def.OFF)
                    end,
                    action = function(loop) 
                        local keep_left_fwd = (loop and loop.power_source == 'apu') and (P.apurunning() == def.APUONBUS)
                        if keep_left_fwd then
                            set(P.lefttanklswitch, def.ON)
                        else
                            set(P.lefttanklswitch, def.OFF)
                        end
                        set(P.lefttankrswitch, def.OFF)
                        set(P.righttanklswitch, def.OFF)
                        set(P.righttankrswitch, def.OFF)
                    end,
                    advice = function(loop)
                        if (loop and loop.power_source == 'apu') and (P.apurunning() == def.APUONBUS) then
                            return "Leave Left After Fuel Pump On, switch remaining Wing Pumps Off"
                        end
                        return "Set Wing Tank Fuel Pumps Off"
                    end,
                    confirm = function(loop)
                        if (loop and loop.power_source == 'apu') and (P.apurunning() == def.APUONBUS) then
                            return "Left After Fuel Pump On, remaining Wing Pumps Off"
                        end
                        return "Wing Tank Fuel Pumps checked Off"
                    end,
                    nextStep = 'hyd_pumps_off'
                },
                ['hyd_pumps_off'] = {
                    check = function() return (get(P.hydro1pos) == def.OFF) and (get(P.hydro2pos) == def.OFF) end,
                    action = function() set(P.hydro1pos, def.OFF); set(P.hydro2pos, def.OFF) end,
                    advice = "Switch Both Hydraulic Pumps Off",
                    confirm = "Both Hydraulic Pumps checked Off",
                    nextStep = 'elec_hyd_pumps_off'
                },
                ['elec_hyd_pumps_off'] = {
                    check = function() return (get(P.elechydro1pos) == def.OFF) and (get(P.elechydro2pos) == def.OFF) end,
                    action = function() set(P.elechydro1pos, def.OFF); set(P.elechydro2pos, def.OFF) end,
                    advice = "Switch Both Electrical Hydraulic Pumps Off",
                    confirm = "Both Electrical Hydraulic Pumps checked Off",
                    nextStep = 'beacon_off'
                },
                ['beacon_off'] = {
                    check = function() return get(P.beaconlights) == def.OFF end,
                    action = function() P.togglecollisionlights(def.OFF) end,
                    advice = "Set Collision Lights Off",
                    confirm = "Collision lightset checked Off",
                    nextStep = 'no_smoking_off'
                },
                ['no_smoking_off'] = {
                    check = function() return get(P.nosmokingsignpos) == def.NOSMOKINGSIGNOFF end,
                    action = function() P.setnosmokingsign(def.NOSMOKINGSIGNOFF) end,
                    advice = "Set No Smoking Signs Off",
                    confirm = "NO Smoking Signs checked Off",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.FINALENGINESHUTDOWNPROCEDURE] = {
            number = 18, 
            name = "Final Engine Shutdown", 
            cycable = false, 
            speakname = true,
            set = false,  
            loop = 1, 
            prerequisite = def.ATPARKINGPOSITIONPROCEDURE, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATESHUTDOWN, 
            skipCondition = function() return not P.enginesrunning(def.BOTH) end,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.ON end, 
                  failMsg = "Procedure not possible Inflight" },
                { check = function() return P.enginesrunning(def.BOTH) end, 
                  failMsg = "Procedure aborted, Engines not running", setonabort = true }
            },
            startStep = 'view_overhead',
            label_to_index = {},
            get_index = function(self, label) return nil end,
            steps = {
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    normalize = true,
                    branch = function(loop, procData)
                        return 'view_throttle'
                    end
                },
                ['view_throttle'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'set_fuel_levers_cutoff'
                },
                ['set_fuel_levers_cutoff'] = {
                    check = function() return (get(P.mixture1pos) == def.OFF) and (get(P.mixture2pos) == def.OFF) end,
                    action = function() 
                        if (get(P.mixture2pos) ~= def.OFF) then helpers.command_once("laminar/B738/engine/mixture2_cutoff") end
                        if (get(P.mixture1pos) ~= def.OFF) then helpers.command_once("laminar/B738/engine/mixture1_cutoff") end
                    end,
                    advice = "Set Both Engine Fuel Levers Cutoff",
                    confirm = "Both Fuel Levers checked and Cutoff",
                    nextStep = 'view_overhead_2'
                },
                ['view_overhead_2'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'probe_heat_off'
                },
                ['probe_heat_off'] = {
                    check = function() return (get(P.captainprobepos) == def.OFF) and (get(P.foprobepos) == def.OFF) end,
                    action = function() P.toggleprobeheat(def.OFF) end,
                    advice = "Set Probe Heat Off",
                    confirm = "Probe Heat checked Off",
                    nextStep = 'ice_off'
                },
                ['ice_off'] = {
                    skipIf = function()
                        local wx = P.desmetar.decodedmetar
                        return helpers.isGroundIcingCondition(wx)
                    end,
                    check = function()
                        return (get(P.eng1heatpos) == def.OFF)
                        and (get(P.eng2heatpos) == def.OFF)
                        and (get(P.wingheatpos) == def.OFF)
                    end,
                    action = function() P.iceprotection(def.OFF) end,
                    advice = "Set Anti Ice Off",
                    nextStep = 'center_pumps_off'
                },
                ['center_pumps_off'] = {
                    check = function() return (get(P.centertanklswitch) == def.OFF) and (get(P.centertankrswitch) == def.OFF) end,
                    action = function() set(P.centertanklswitch, def.OFF); set(P.centertankrswitch, def.OFF) end,
                    advice = "Set Center Tank Fuel Pumps Off",
                    confirm = "Center Tank Fuel Pumps checked Off",
                    nextStep = 'wing_pumps_off'
                },
                ['wing_pumps_off'] = {
                    check = function()
                        return  (get(P.lefttanklswitch) == def.OFF)
                            and (get(P.lefttankrswitch) == def.OFF)
                            and (get(P.righttanklswitch) == def.OFF)
                            and (get(P.righttankrswitch) == def.OFF)
                    end,
                    action = function() 
                        set(P.lefttanklswitch, def.OFF)
                        set(P.lefttankrswitch, def.OFF)
                        set(P.righttanklswitch, def.OFF)
                        set(P.righttankrswitch, def.OFF)
                    end,
                    advice = "Set Wing Tank Pumps Off",
                    confirm = "Wing Tank Pumps checked Off",
                    nextStep = 'hyd_pumps_off'
                },
                ['hyd_pumps_off'] = {
                    check = function() return (get(P.hydro1pos) == def.OFF) and (get(P.hydro2pos) == def.OFF) end,
                    action = function() set(P.hydro1pos, def.OFF); set(P.hydro2pos, def.OFF) end,
                    advice = "Switch Both Hydraulic Pumps Off",
                    confirm = "Both Hydraulic Pumps checked Off",
                    nextStep = 'elec_hyd_pumps_off'
                },
                ['elec_hyd_pumps_off'] = {
                    check = function() return (get(P.elechydro1pos) == def.OFF) and (get(P.elechydro2pos) == def.OFF) end,
                    action = function() set(P.elechydro1pos, def.OFF); set(P.elechydro2pos, def.OFF) end,
                    advice = "Switch Both Electrical Hydraulic Pumps Off",
                    confirm = "Both Electrical Hydraulic Pumps checked Off",
                    nextStep = 'beacon_off'
                },
                ['beacon_off'] = {
                    check = function() return get(P.beaconlights) == def.OFF end,
                    action = function() P.togglecollisionlights(def.OFF) end,
                    advice = "Set Collision Lights Off",
                    confirm = "Collision lightset checked Off",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.SHUTDOWNPROCEDURE] = {
            number = 19, 
            name = "Shutdown", 
            cycable = true, 
            speakname = true, 
            set = false,  
            loop = 1, 
            prerequisite = function() return not P.enginesrunning(def.BOTH) end, 
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATESHUTDOWN, 
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return get(P.airgroundsensor) == def.ON end, 
                  failMsg = "Procedure not possible Inflight" },
                { check = function() return (get(P.battery) == def.ON) or (get(P.mainbus) == def.ON) end, 
                  failMsg = "Procedure aborted, Cockpit is not Cold and Dark", setonabort = true }
            },
            startStep = 'view_upper_overhead',
            label_to_index = {},
            get_index = function(self, label) return nil end,
            steps = {
                ['view_upper_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    normalize = true,
                    nextStep = 'irs_off'
                },
                ['irs_off'] = {
                    check = function() return (get(P.irsleftpos) == def.IRSOFF) and (get(P.irsrightpos) == def.IRSOFF) end,
                    action = function() P.setirs(def.BOTHIRS, def.IRSOFF) end,
                    advice = "Set Both I R S Off",
                    confirm = "Both I R S checked Off",
                    nextStep = 'view_overhead'
                },
                ['view_overhead'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'yaw_damper_off'
                },
                ['yaw_damper_off'] = {
                    check = function() return get(P.yawdamperswitch) == def.OFF end,
                    action = function() set(P.yawdamperswitch, def.OFF) end,
                    advice = "Set Yaw Damper Off",
                    confirm = "Yaw Damper checked Off",
                    nextStep = 'apu_bleed_off'
                },
                ['apu_bleed_off'] = {
                    check = function() return get(P.bleedairapupos) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Set A P U Bleed Off",
                    confirm = "A P U Bleed checked Off",
                    nextStep = 'isol_valve_auto'
                },
                ['isol_valve_auto'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEAUTO end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEAUTO) end,
                    advice = "Set Isolation Valve Auto",
                    confirm = "Isolation Valve checked Auto",
                    nextStep = 'packs_off'
                },
                ['packs_off'] = {
                    check = function() return (get(P.packlpos) == def.PACKOFF) and (get(P.packrpos) == def.PACKOFF) end,
                    action = function() set(P.packlpos, def.PACKOFF); set(P.packrpos, def.PACKOFF) end,
                    advice = "Set Packs Off",
                    confirm = "Packs checked Off",
                    nextStep = 'eng_bleed_off'
                },
                ['eng_bleed_off'] = {
                    check = function() return (get(P.bleedair1pos) == def.OFF) and (get(P.bleedair2pos) == def.OFF) end,
                    action = function() 
                        if (get(P.bleedair1pos) == def.ON) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_1") end
                        if (get(P.bleedair2pos) == def.ON) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_2") end
                    end,
                    advice = "Engine Bleeds Off",
                    confirm = "Engine Bleeds checked Off",
                    nextStep = 'trim_air_off'
                },
                ['trim_air_off'] = {
                    check = function()
                        return (get(P.trimairpos) == def.OFF)
                            and (get(P.lrecircfanpos) == def.OFF)
                            and (get(P.rrecircfanpos) == def.OFF)
                    end,
                    action = function()
                        set(P.trimairpos, def.OFF)
                        set(P.lrecircfanpos, def.OFF)
                        set(P.rrecircfanpos, def.OFF)
                    end,
                    advice = "Set Trim Air and Recirc Fans Off",
                    confirm = "Trim Air and Recirc Fans checked Off",
                    nextStep = 'window_heat_off'
                },
                ['window_heat_off'] = {
                    check = function() return (get(P.wheatlfwdpos) == def.OFF) and (get(P.wheatrfwdpos) == def.OFF) and (get(P.wheatlsidepos) == def.OFF) and (get(P.wheatrsidepos) == def.OFF) end,
                    action = function() P.togglewindowheat(def.OFF) end,
                    advice = "Set Window Heat Off",
                    confirm = "Window Heat checked Off",
                    nextStep = 'check_power_source'
                },
                ['check_power_source'] = {
                    branch = function(loop, procData)
                        if (P.configvalues[def.CONFIGUSEGROUNDPOWER] == def.ON) then
                            return 'check_gpu_power'
                        else
                            return 'check_apu_gen_off'
                        end
                    end
                },
                ['check_gpu_power'] = {
                    check = function() return get(P.gpuon) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/gpu_up") end,
                    advice = "Set Ground Power Off",
                    confirm = "Ground Power checked Off",
                    nextStep = 'apu_off'
                },
                ['check_apu_gen_off'] = {
                    check = function() return not ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) and not ((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) end,
                    action = function() 
                        if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                            helpers.command_once("laminar/B738/toggle_switch/apu_gen1_up")
                        end
                        if ((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                            helpers.command_once("laminar/B738/toggle_switch/apu_gen2_up")
                        end
                    end,
                    advice = "Set A P U Generator Off",
                    confirm = "A P U Generator checked Off",
                    nextStep = 'apu_off'
                },
                ['apu_off'] = {
                    check = function() return P.apurunning() == def.APUOFF end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up") end,
                    advice = "Set A P U Off",
                    confirm = "A P U checked Off",
                    nextStep = 'pos_lights_off'
                },
                ['pos_lights_off'] = {
                    check = function() return get(P.positionlights) == def.POSLIGHTSOFF end,
                    action = function() P.togglepositionlights(def.POSLIGHTSOFF) end,
                    advice = "Set Position Lights Off",
                    confirm = "Position LIghts checked Off",
                    nextStep = 'seatbelts_off'
                },
                ['seatbelts_off'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF end,
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNOFF) end,
                    advice = "Set Seatbeltsigns Off",
                    confirm = "Seatbeltsigns checked Off",
                    nextStep = 'no_smoking_off'
                },
                ['no_smoking_off'] = {
                    check = function() return get(P.nosmokingsignpos) == def.NOSMOKINGSIGNOFF end,
                    action = function() P.setnosmokingsign(def.NOSMOKINGSIGNOFF) end,
                    advice = "Set No Smoking Signs Off",
                    confirm = "NO Smoking Signs checked Off",
                    nextStep = 'open_emerg_cover'
                },
                ['open_emerg_cover'] = {
                    check = function() return get(P.emergencylightcover) == def.OPEN end,
                    action = function() helpers.command_once("laminar/B738/button_switch_cover09") end,
                    advice = "Open Emergency Lights Cover",
                    nextStep = 'emerg_lights_off'
                },
                ['emerg_lights_off'] = {
                    check = function() return get(P.emergencylights) == def.EMERGLIGHTSOFF end,
                    action = function() P.setemergencylights(def.EMERGLIGHTSOFF) end,
                    advice = "Set Emergency Lights Off",
                    confirm = "Emergency Lights checked Off",
                    nextStep = 'view_upper_overhead_2'
                },
                ['view_upper_overhead_2'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    nextStep = 'dome_light_off'
                },
                ['dome_light_off'] = {
                    check = function() return get(P.domelightpos) == def.DOMELIGHTOFF end,
                    action = function() P.setdomelight(def.DOMELIGHTOFF) end,
                    advice = "Set Domelight Off",
                    confirm = "Domelight checked Off",
                    nextStep = 'view_overhead_2'
                },
                ['view_overhead_2'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'open_battery_cover'
                },
                ['open_battery_cover'] = {
                    check = function() return get(P.batteryswitchcover) == def.OPEN end,
                    action = function() helpers.command_once("laminar/B738/button_switch_cover02") end,
                    advice = "Open Battery Cover",
                    nextStep = 'battery_off'
                },
                ['battery_off'] = {
                    check = function() return get(P.battery) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/switch/battery_up") end,
                    advice = "Switch Battery Off",
                    confirm = "Battery checked Off",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.SETILSPROCEDURE] = {
            number = 20, 
            name = "Set ILS", 
            cycable = false, 
            speakname = false, 
            set = false, 
            loop = 3, 
            prerequisite = nil, 
            allowedState = nil, 
            requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH, def.FLIGHTSTATEINITIALCLIMB }, 
            skipCondition = nil,
            repeatable = true, 
            startStep = 'view_fms',
            steps = {
                ['view_fms'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWFMS] end,
                    normalize = true, 
                    nextStep = 'check_fms_page'
                },
                ['check_fms_page'] = {
                    check = function(loop, procData)
                        return helpers.fmcHeaderContains("APPROACH REF")
                    end,
                    action = function(loop, procData) helpers.command_once("laminar/B738/button/fmc1_init_ref") end,
                    advice = "Open F M C Approach Reference Page",
                    runActionInAdviceMode = true,
                    nextStep = 'find_navdata'
                },
                ['find_navdata'] = {
                    branch = function(loop, procData)
                        local FMC1Line04X = helpers.get("laminar/B738/fmc1/Line04_X")
                        local FMC1Line04L = helpers.get("laminar/B738/fmc1/Line04_L")
                        local apptype
                        local candidateTypes = {}
                        local hasLPV = false
                        if ((string.len(FMC1Line04X) == 24) and (string.len(FMC1Line04L) == 24)) then
                            apptype = string.sub(FMC1Line04X, 2, 4)
                            if ((apptype == def.NAVTYPEILS)
                                or (apptype == def.NAVTYPEGLS)
                                or (apptype == def.NAVTYPELDA)
                                or (apptype == def.NAVTYPELOC)
                                or (apptype == def.NAVTYPEIGS)) then
                                table.insert(candidateTypes, apptype)
                            else
                                table.insert(candidateTypes, def.NAVTYPELPV)
                                hasLPV = true
                            end
                        else
                            table.insert(candidateTypes, def.NAVTYPELPV)
                            hasLPV = true
                        end

                        local navIndices = helpers.getnavdataindices(P.navdatatable, get(P.desicao), get(P.desrwy), candidateTypes)
                        navIndices = navIndices or {}
                        if (#navIndices == 0) and not hasLPV then
                            navIndices = helpers.getnavdataindices(P.navdatatable, get(P.desicao), get(P.desrwy), { def.NAVTYPELPV })
                            navIndices = navIndices or {}
                            hasLPV = true
                        end

                        loop.navdatatableindices = navIndices
                        loop.navdatatableindex = (navIndices and navIndices[1]) or nil

                        local selectedAppId = nil
                        if P.fmsselectedapp then
                            local val = get(P.fmsselectedapp)
                            if val and val ~= "" and val ~= "------" then
                                selectedAppId = val
                            end
                        end

                        local detectedVariant = helpers.detectCIFPApproachVariant(
                            get(P.desicao),
                            get(P.desrwy),
                            get(P.fmslegs),
                            get(P.fmslegslat),
                            get(P.fmslegslon),
                            selectedAppId
                        )
                        loop.detectedApproach = detectedVariant
                        if detectedVariant and detectedVariant.navType then
                            local navType = detectedVariant.navType
                            local targetCourse = detectedVariant.entry and detectedVariant.entry.course
                            local filtered = {}
                            if loop.navdatatableindices then
                                for _, idx in ipairs(loop.navdatatableindices) do
                                    local entry = P.navdatatable[idx]
                                    if entry and entry[def.DESTNAVTYPE] == navType then
                                        table.insert(filtered, idx)
                                    end
                                end
                            end

                            if #filtered == 0 then
                                loop.detectedApproach = detectedVariant
                            else
                                local function courseDiff(idx)
                                    if not targetCourse then return math.huge end
                                    local entry = P.navdatatable[idx]
                                    if not entry then return math.huge end
                                    local entryCourse = entry[def.DESTCOURSE]
                                    if entry.isTrueCourse and entry.truecourse then
                                        local magVar = getEntryMagVar(entry)
                                        entryCourse = helpers.calccourse(entry.truecourse - magVar)
                                    end
                                    if not entryCourse then return math.huge end
                                    return math.abs(helpers.headingdiff(entryCourse, targetCourse))
                                end
                                table.sort(filtered, function(a, b)
                                    local diffA = courseDiff(a)
                                    local diffB = courseDiff(b)
                                    if diffA ~= diffB then
                                        return diffA < diffB
                                    end
                                    return a < b
                                end)
                                loop.navdatatableindices = filtered
                                loop.navdatatableindex = filtered[1]
                            end
                        else
                            loop.detectedApproach = nil
                        end

                        if loop.navdatatableindex ~= nil and P.navdatatable[loop.navdatatableindex] ~= nil then
                            return 'announce_approach_type' 
                        else
                            return 'announce_no_approach'
                        end
                    end
                },
                ['announce_no_approach'] = {
                    action = function(loop, procData) 
                        local runwayFormatted = helpers.formatRunwayDesignator(get(P.desrwy))
                        P.commandtableentry(def.TEXT, "Runway " .. runwayFormatted .. " has no Precision Approach")

                        local destinationIcao = get(P.desicao)
                        local runwayRaw = get(P.desrwy)
                        local runwayKey = ""
                        if type(runwayRaw) == "string" then
                            runwayKey = runwayRaw:upper():gsub("%s+", "")
                        elseif type(runwayRaw) == "number" then
                            runwayKey = string.format("%02d", runwayRaw)
                        end

                        if helpers.isvalidicao(destinationIcao) and runwayKey ~= "" then
                            local cifpData = helpers.loadCIFP(destinationIcao)
                            if cifpData then
                                local rnEntries = cifpData[def.NAVTYPERNAV]
                                local list = rnEntries and rnEntries[runwayKey]
                                if list and #list > 0 then
                                    local entry = list[1]
                                    local descriptor = entry.displayName or ("RNAV " .. runwayFormatted)
                                    P.commandtableentry(def.TEXT, "Best alternative: " .. descriptor .. " Approach")
                                end
                            end
                        end
                    end,
                    runActionInAdviceMode = true, 
                    nextStep = 'find_nearest_vor'
                },
                ['find_nearest_vor'] = {
                    action = function(loop, procData)
                        local nearestvor = nil
                        if (P.airportdatatable[get(P.desicao)] and P.airportdatatable[get(P.desicao)].latitude and P.airportdatatable[get(P.desicao)].longitude) then
                            nearestvor = helpers.findnearestvor(P.navdatatable, P.airportdatatable[get(P.desicao)].latitude, P.airportdatatable[get(P.desicao)].longitude)
                        elseif helpers.isvalidrwy(get(P.desrwy)) then
                            nearestvor = helpers.findnearestvor(P.navdatatable, get(P.desrwylatstartpos), get(P.desrwylonstartpos))
                        end       
                        if (nearestvor == nil) then
                            P.commandtableentry(def.TEXT, "No V O R near " .. helpers.spellNato(get(P.desicao)) .. " found")
                        else
                            P.commandtableentry(def.TEXT, "Nearest V O R for " .. helpers.spellNato(get(P.desicao)) .. " is " .. helpers.spellNato(nearestvor.navid) .. " with frequency " .. helpers.addspaces(helpers.formatILSFrequency(nearestvor.frequency)))
                        end
                    end,
                    runActionInAdviceMode = true, 
                    nextStep = 'announce_heading_only'
                },
                ['announce_heading_only'] = {
                    action = function(loop, procData)
                        local runway = get(P.desrwy)
                        local runwayFormatted = helpers.formatRunwayDesignator(runway)
                        local course = nil

                        local navEntry = nil
                        if loop and loop.navdatatableindex and P.navdatatable[loop.navdatatableindex] then
                            navEntry = P.navdatatable[loop.navdatatableindex]
                        end
                        local runwayToken = runway
                        if navEntry and type(navEntry[def.DESTRWY]) == "string" then
                            runwayToken = navEntry[def.DESTRWY]
                        end
                        local announceTrue = runwayUsesTrue(runwayToken) or runwayUsesTrue(runway)
                        local magVar = nil
                        if navEntry then
                            magVar = getEntryMagVar(navEntry)
                        else
                            local latVar = get(P.desrwylatstartpos)
                            local lonVar = get(P.desrwylonstartpos)
                            if latVar and lonVar and latVar ~= 0 and lonVar ~= 0 then
                                magVar = sasl.getMagneticVariation(latVar, lonVar)
                            else
                                local apt = P.airportdatatable[get(P.desicao)]
                                if apt and apt.latitude and apt.longitude then
                                    magVar = sasl.getMagneticVariation(apt.latitude, apt.longitude)
                                end
                            end
                        end
                        magVar = tonumber(magVar) or 0
                        local runwayMag = tonumber(get(P.desrwyheading))
                        local runwayTrue = getRunwayTrueFromEndpoints()
                        if not runwayTrue and runwayMag then
                            runwayTrue = helpers.calccourse(runwayMag + magVar)
                        end
                        local runwayRef = nil
                        if announceTrue then
                            runwayRef = runwayTrue
                        else
                            runwayRef = runwayMag and helpers.calccourse(runwayMag) or nil
                            if not runwayRef and runwayTrue then
                                runwayRef = helpers.calccourse(runwayTrue - magVar)
                            end
                        end
                        local navType = navEntry and navEntry[def.DESTNAVTYPE]
                        local isRnavNav = navType == def.NAVTYPELPV
                            or navType == def.NAVTYPERNAV
                            or navType == def.NAVTYPEGLS
                        if isRnavNav then
                            runwayRef = nil
                        end
                        local function isPlausible(value)
                            if not value then return false end
                            if runwayRef then
                                local diff = math.abs(value - runwayRef)
                                if diff > 180 then diff = 360 - diff end
                                return diff <= 10
                            end
                            return true
                        end
                        local sanityRunwayRef = nil
                        if announceTrue then
                            if runwayTrue then
                                sanityRunwayRef = helpers.calccourse(runwayTrue)
                            elseif runwayMag then
                                sanityRunwayRef = helpers.calccourse(runwayMag + magVar)
                            end
                        else
                            if runwayMag then
                                sanityRunwayRef = helpers.calccourse(runwayMag)
                            elseif runwayTrue then
                                sanityRunwayRef = helpers.calccourse(runwayTrue - magVar)
                            end
                        end
                        local sanityRefs = nil
                        local function buildSanityRefs()
                            if sanityRefs then return sanityRefs end
                            sanityRefs = {}
                            if sanityRunwayRef then
                                table.insert(sanityRefs, sanityRunwayRef)
                            end
                            local navTypeForCifp = navType
                            if type(navTypeForCifp) == "string" and type(runway) == "string" then
                                local candidateTypes = { navTypeForCifp }
                                if navTypeForCifp == def.NAVTYPELPV or navTypeForCifp == def.NAVTYPEGLS then
                                    table.insert(candidateTypes, def.NAVTYPERNAV)
                                end
                                for _, candidateType in ipairs(candidateTypes) do
                                    local cifpCourse = helpers.getCIFPApproachCourse(get(P.desicao), candidateType, runway)
                                    if cifpCourse then
                                        local cifpRef = normalizeCourse(cifpCourse, nil)
                                        if cifpRef then
                                            table.insert(sanityRefs, cifpRef)
                                        end
                                        break
                                    end
                                end
                            end
                            return sanityRefs
                        end
                        local function sanityCheck(candidate, source)
                            if not candidate then return nil end
                            local refs = buildSanityRefs()
                            if not refs or #refs == 0 then return candidate end
                            local minDiff = 360
                            for _, ref in ipairs(refs) do
                                local diff = math.abs(candidate - ref)
                                if diff > 180 then diff = 360 - diff end
                                if diff < minDiff then minDiff = diff end
                            end
                            if minDiff > 30 then
                                helpers.logInfoTS(string.format(
                                    "Runway course sanity check failed (source=%s, course=%s, minDiff=%d, runway=%s).",
                                    tostring(source), tostring(candidate), math.floor(minDiff + 0.5), tostring(runway)
                                ))
                                return nil
                            end
                            return candidate
                        end
                        local function normalizeCourse(value, valueIsTrue)
                            if value == nil then
                                return nil
                            end

                            local function normalizeKnown(isTrue)
                                if announceTrue then
                                    if isTrue then
                                        return helpers.calccourse(value)
                                    end
                                    return helpers.calccourse(value + magVar)
                                end
                                if isTrue then
                                    return helpers.calccourse(value - magVar)
                                end
                                return helpers.calccourse(value)
                            end

                            local function score(candidate)
                                if not candidate or not runwayRef then
                                    return nil
                                end
                                local diff = math.abs(candidate - runwayRef)
                                if diff > 180 then diff = 360 - diff end
                                return diff
                            end

                            if valueIsTrue == true then
                                local normalized = normalizeKnown(true)
                                return isPlausible(normalized) and normalized or nil
                            elseif valueIsTrue == false then
                                local normalized = normalizeKnown(false)
                                return isPlausible(normalized) and normalized or nil
                            end

                            local candA = normalizeKnown(announceTrue)
                            local candB = normalizeKnown(not announceTrue)
                            local scoreA = score(candA)
                            local scoreB = score(candB)
                            local pick = nil
                            if scoreA and scoreB then
                                pick = (scoreA <= scoreB) and candA or candB
                            else
                                pick = candA or candB
                            end
                            return isPlausible(pick) and pick or nil
                        end

                        local function getFMSFinalMagCourse()
                            if not (P and P.fmslegs and P.fmslegslat and P.fmslegslon) then return nil end
                            local legsStr = get(P.fmslegs)
                            local latArr = get(P.fmslegslat)
                            local lonArr = get(P.fmslegslon)
                            local waypoints = helpers.buildlegstable(legsStr, latArr, lonArr)
                            if not waypoints or #waypoints < 2 then return nil end

                            local destRunway = get(P.desrwy)
                            local selectedCourse = nil

                            if helpers.isvalidrwy(destRunway) then
                                for i = #waypoints - 1, 1, -1 do
                                    local nxt = waypoints[i + 1]
                                    if nxt and nxt.name and matchesDestRunway(nxt.name, destRunway) then
                                        selectedCourse = waypoints[i].magnetic_course
                                        break
                                    end
                                end
                            else
                                for i = #waypoints - 1, 1, -1 do
                                    local nxt = waypoints[i + 1]
                                    if nxt and nxt.name and isRunwayLeg(nxt.name) then
                                        selectedCourse = waypoints[i].magnetic_course
                                        break
                                    end
                                end
                            end

                            if selectedCourse and selectedCourse ~= 0 then
                                return helpers.calccourse(selectedCourse)
                            end
                            return nil
                        end

                        -- Attempt to derive final-leg course from FMC (only if Runway-Leg found)
                        if not course then
                            local fmsCourse = getFMSFinalMagCourse()
                            course = sanityCheck(normalizeCourse(fmsCourse, false), "FMS")
                        end

                        -- Prefer detected CIFP approach course
                        if loop and loop.detectedApproach and loop.detectedApproach.entry and loop.detectedApproach.entry.course then
                            course = sanityCheck(normalizeCourse(loop.detectedApproach.entry.course, nil), "CIFP")
                        end

                        -- Fallback to CIFP course for runway/nav type when no variant detected
                        if not course and navType then
                            local candidateTypes = { navType }
                            if navType == def.NAVTYPELPV or navType == def.NAVTYPEGLS then
                                table.insert(candidateTypes, def.NAVTYPERNAV)
                            end
                            for _, candidate in ipairs(candidateTypes) do
                                local cifpCourse = helpers.getCIFPApproachCourse(get(P.desicao), candidate, runway)
                                if cifpCourse then
                                    course = sanityCheck(normalizeCourse(cifpCourse, nil), "CIFP")
                                    if course then break end
                                end
                            end
                        end

                        -- Fall back to navdata-derived runway heading
                        if not course then
                            local navCourse = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.desicao), runway)
                            course = sanityCheck(normalizeCourse(navCourse, nil), "NAV")
                        end

                        -- Fallback to FMC runway heading
                        if not course and tonumber(get(P.desrwyheading)) then
                            course = sanityCheck(normalizeCourse(helpers.roundnumber(get(P.desrwyheading)), false), "RUNWAY")
                        end

                        -- Compute bearing from runway endpoints if available
                        if not course then
                            if runwayTrue then
                                course = sanityCheck(normalizeCourse(runwayTrue, true), "RUNWAYTRUE")
                            end
                        end

                        if course then
                            P.commandtableentry(def.TEXT, "Runway " .. runwayFormatted .. " course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(course, 3)))
                        else
                            P.commandtableentry(def.TEXT, "Runway " .. runwayFormatted .. " course unavailable")
                        end
                    end,
                    runActionInAdviceMode = true, 
                    nextStep = nil 
                },
                ['announce_approach_type'] = {
                    action = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if not navdata then
                            return
                        end
                        if (get(P.desrwy) ~= navdata[def.DESTRWY]) then
                            helpers.logInfoTS("Destination Runway Diff FMC: " .. tostring(get(P.desrwy)) .. " Navdata: " .. tostring(navdata[def.DESTRWY]))
                        end
                        local navtype = navdata[def.DESTNAVTYPE] or ""
                        local ident = navdata[def.DESTNAVID] or ""
                        local runwayDesignator = navdata[def.DESTRWY] or ""
                        local approachDescriptor = helpers.addspaces(navtype) .. " Approach"
                        local destinationIcao = get(P.desicao)
                        local detectedVariant = loop.detectedApproach
                        local useDetected = detectedVariant
                            and detectedVariant.navType
                            and (navdata[def.DESTNAVTYPE] == detectedVariant.navType)
                        if useDetected then
                            navtype = detectedVariant.navType
                        end

                        if destinationIcao and destinationIcao ~= "" then
                            local cifpName
                            if useDetected and detectedVariant.entry and detectedVariant.entry.displayName then
                                cifpName = detectedVariant.entry.displayName
                            else
                                cifpName = helpers.getCIFPApproachName(destinationIcao, navtype, runwayDesignator)
                            end
                            if cifpName and cifpName ~= "" then
                                approachDescriptor = cifpName .. " Approach"
                            end
                        end
                        if isLocalizerNavType(navtype) and navdata[def.DESTNAVDME] then
                            approachDescriptor = approachDescriptor .. " with DME"
                        end
                        local freqMsg
                        if isLocalizerNavType(navtype) then
                            freqMsg = "Frequency " .. helpers.addspaces(helpers.formatILSFrequency(navdata[def.DESTFREQ] or 0))
                        else
                            freqMsg = "Channel " .. helpers.addspaces(navdata[def.DESTFREQ] or "")
                        end
                        local message = "Runway " .. helpers.formatRunwayDesignator(navdata[def.DESTRWY])
                            .. " has " .. approachDescriptor .. " (Ident " .. helpers.spellNato(ident) .. ") "
                            .. freqMsg
                        P.commandtableentry(def.TEXT, message)
                    end,
                    runActionInAdviceMode = true, 
                    nextStep = 'announce_additional_variants' 
                },
                ['announce_additional_variants'] = {
                    skipIf = function(loop, procData)
                        return not (loop.navdatatableindices and (#loop.navdatatableindices > 1))
                    end,
                    action = function(loop, procData)
                        local function navRank(navtype)
                            if navtype == def.NAVTYPEILS then return 1 end
                            if navtype == def.NAVTYPEGLS then return 2 end
                            if navtype == def.NAVTYPELPV then return 3 end
                            if navtype == def.NAVTYPERNAV or navtype == def.NAVTYPELOC or navtype == def.NAVTYPELDA or navtype == def.NAVTYPEIGS then return 4 end
                            return 99
                        end

                        local primary = P.navdatatable[loop.navdatatableindex]
                        local primaryRank = primary and navRank(primary[def.DESTNAVTYPE]) or 99

                        local primaryRunway = primary and primary[def.DESTRWY] or nil

                        -- Collect alternates that are strictly better than the primary and on the same runway
                        local candidates = {}
                        for idx = 2, #loop.navdatatableindices do
                            local navdata = P.navdatatable[loop.navdatatableindices[idx]]
                            if navdata then
                                local rank = navRank(navdata[def.DESTNAVTYPE])
                                if rank < primaryRank and navdata[def.DESTRWY] == primaryRunway then
                                    table.insert(candidates, { data = navdata, rank = rank, idx = idx })
                                end
                            end
                        end

                        if #candidates == 0 then return end

                        table.sort(candidates, function(a, b)
                            if a.rank ~= b.rank then return a.rank < b.rank end
                            return a.idx < b.idx
                        end)

                        for _, entry in ipairs(candidates) do
                            local navdata = entry.data
                            local navtype = navdata[def.DESTNAVTYPE] or ""
                            local ident = navdata[def.DESTNAVID] or ""
                            local runwayDesignator = navdata[def.DESTRWY] or ""
                            local descriptor = helpers.addspaces(navtype) .. " Approach"
                            local destinationIcao = get(P.desicao)
                            if destinationIcao and destinationIcao ~= "" then
                                local cifpName = helpers.getCIFPApproachName(destinationIcao, navtype, runwayDesignator)
                                if cifpName and cifpName ~= "" then
                                    descriptor = cifpName .. " Approach"
                                end
                            end
                            if isLocalizerNavType(navtype) and navdata[def.DESTNAVDME] then
                                descriptor = descriptor .. " with DME"
                            end
                            local freqMsg
                            if isLocalizerNavType(navtype) then
                                freqMsg = "Frequency " .. helpers.addspaces(helpers.formatILSFrequency(navdata[def.DESTFREQ] or 0))
                            else
                                freqMsg = "Channel " .. helpers.addspaces(navdata[def.DESTFREQ] or "")
                            end
                            local altMessage = "Alternate option: " .. descriptor
                                .. " (Ident " .. helpers.spellNato(ident) .. ") " .. freqMsg
                            P.commandtableentry(def.TEXT, altMessage)
                        end
                    end,
                    runActionInAdviceMode = true,
                    nextStep = 'view_pedestal'
                },
                ['view_pedestal'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWPEDESTAL] end,
                    nextStep = 'set_capt_freq'
                },
                ['set_capt_freq'] = {
                    check = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                        if isLocalizerNavType(navdata[def.DESTNAVTYPE]) then
                            if (get(P.mmrinstalled) == def.ON) then
                                return (get(P.mmrcptactvalue) == freqValue) and (get(P.mmrcptactmode) == def.MMRILS)
                            else
                                return (get(P.nav1freq) == freqValue)
                            end
                        elseif ((navdata[def.DESTNAVTYPE] == def.NAVTYPEGLS) or (navdata[def.DESTNAVTYPE] == def.NAVTYPELPV)) and (get(P.mmrinstalled) == def.ON) then
                            return (get(P.mmrcptactvalue) == freqValue) and ((get(P.mmrcptactmode) == def.MMRGLS) or (get(P.mmrcptactmode) == def.MMRLPV))
                        end
                        return true 
                    end,
                    action = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        local navType = navdata[def.DESTNAVTYPE]
                        local freqValue = getFmcApproachRefFrequency(navType) or navdata[def.DESTFREQ]
                        if isLocalizerNavType(navType) then
                            if (get(P.mmrinstalled) == def.ON) then
                                helpers.mmrCopyActToStby(def.MMRCAPTAIN)
                                set(P.mmrcptactmode, def.MMRILS)
                                set(P.mmrcptactvalue, freqValue)
                                set(P.nav1stdbyfreq, get(P.nav1freq))
                                set(P.nav1freq, freqValue)
                            else
                                set(P.nav1stdbyfreq, get(P.nav1freq))
                                set(P.nav1freq, freqValue)
                            end
                        elseif (navType == def.NAVTYPEGLS or navType == def.NAVTYPELPV) and (get(P.mmrinstalled) == def.ON) then
                            helpers.mmrCopyActToStby(def.MMRCAPTAIN)
                            if navType == def.NAVTYPEGLS then
                                set(P.mmrcptactmode, def.MMRGLS)
                            else
                                set(P.mmrcptactmode, def.MMRLPV)
                            end
                            set(P.mmrcptactvalue, freqValue)
                        end
                    end,
                    advice = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if isLocalizerNavType(navdata[def.DESTNAVTYPE]) then
                            local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                            return "Set Captain Frequency " .. helpers.addspaces(helpers.formatILSFrequency(freqValue))
                        else
                            local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                            return "Set Captain Channel " .. helpers.addspaces(freqValue)
                        end
                    end,
                    confirm = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if isLocalizerNavType(navdata[def.DESTNAVTYPE]) then
                            local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                            return "Captain Frequency checked and " .. helpers.addspaces(helpers.formatILSFrequency(freqValue))
                        else
                            local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                            return "Captain Channel checked and " .. helpers.addspaces(freqValue)
                        end
                    end,
                    nextStep = 'set_fo_freq'
                },
                ['set_fo_freq'] = {
                    skipIf = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if not navdata then return true end
                        local navtype = navdata[def.DESTNAVTYPE]

                        local function prepareApproachDME()
                            local dmeInfo = helpers.findApproachDME(
                                P.navdatatable,
                                get(P.desicao),
                                get(P.desrwy),
                                navdata[def.DESTLATPOS],
                                navdata[def.DESTLONPOS],
                                navdata[def.DESTNAVID]
                            )
                            loop.approachDME = dmeInfo
                            return dmeInfo
                        end

                        if navtype == def.NAVTYPELPV then
                            local dme = prepareApproachDME()
                            if not dme then
                                if loop and not loop.noFODmeWarned then
                                    P.commandtableentry(def.TEXT, "No suitable D M E found for Copilot")
                                    loop.noFODmeWarned = true
                                end
                                return true
                            end
                            return false
                        end

                        if isLocalizerNavType(navtype) then
                            if navdata[def.DESTNAVDME] then
                                loop.approachDME = nil
                                return false
                            end
                            local dme = prepareApproachDME()
                            if not dme then
                                if loop and not loop.noFODmeWarned then
                                    P.commandtableentry(def.TEXT, "No suitable D M E found for Copilot")
                                    loop.noFODmeWarned = true
                                end
                                return true
                            end
                            return false
                        end

                        loop.approachDME = nil
                        return false 
                    end,
                    check = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if not navdata then return true end
                        if isLocalizerNavType(navdata[def.DESTNAVTYPE]) then 
                            if navdata[def.DESTNAVDME] then
                                local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                                if (get(P.mmrinstalled) == def.ON) then
                                    return (get(P.mmrfoactvalue) == freqValue) and (get(P.mmrfoactmode) == def.MMRILS)
                                else
                                    return (get(P.nav2freq) == freqValue)
                                end
                            else
                                local dmeInfo = loop.approachDME or helpers.findApproachDME(P.navdatatable, get(P.desicao), get(P.desrwy), navdata[def.DESTLATPOS], navdata[def.DESTLONPOS], navdata[def.DESTNAVID])
                                loop.approachDME = dmeInfo
                                if not dmeInfo then return true end
                                local freqValue = dmeInfo[def.DESTDMEFREQ] ~= 0 and dmeInfo[def.DESTDMEFREQ] or dmeInfo[def.DESTFREQ]
                                return (get(P.nav2freq) == freqValue)
                            end
                        elseif (navdata[def.DESTNAVTYPE] == def.NAVTYPELPV) then
                            local dmeInfo = loop.approachDME or helpers.findApproachDME(P.navdatatable, get(P.desicao), get(P.desrwy), navdata[def.DESTLATPOS], navdata[def.DESTLONPOS], navdata[def.DESTNAVID])
                            loop.approachDME = dmeInfo
                            if not dmeInfo then return true end
                            local freqValue = dmeInfo[def.DESTDMEFREQ] ~= 0 and dmeInfo[def.DESTDMEFREQ] or dmeInfo[def.DESTFREQ]
                            return (get(P.nav2freq) == freqValue)
                        elseif (navdata[def.DESTNAVTYPE] == def.NAVTYPEGLS) and (get(P.mmrinstalled) == def.ON) then
                            local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                            return (get(P.mmrfoactvalue) == freqValue) and (get(P.mmrfoactmode) == def.MMRGLS)
                        end
                        return true 
                    end,
                    action = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if not navdata then return end
                        if isLocalizerNavType(navdata[def.DESTNAVTYPE]) then
                            if navdata[def.DESTNAVDME] then
                                local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                                if (get(P.mmrinstalled) == def.ON) then
                                    helpers.mmrCopyActToStby(def.MMRFO)
                                    set(P.mmrfoactmode, def.MMRILS)
                                    set(P.mmrfoactvalue, freqValue)
                                    set(P.nav2stdbyfreq, get(P.nav2freq))
                                    set(P.nav2freq, freqValue)
                                else
                                    set(P.nav2stdbyfreq, get(P.nav2freq))
                                    set(P.nav2freq, freqValue)
                                end
                            else
                                local dmeInfo = loop.approachDME or helpers.findApproachDME(P.navdatatable, get(P.desicao), get(P.desrwy), navdata[def.DESTLATPOS], navdata[def.DESTLONPOS], navdata[def.DESTNAVID])
                                loop.approachDME = dmeInfo
                                if dmeInfo then
                                    local freqValue = dmeInfo[def.DESTDMEFREQ] ~= 0 and dmeInfo[def.DESTDMEFREQ] or dmeInfo[def.DESTFREQ]
                                    set(P.nav2stdbyfreq, get(P.nav2freq))
                                    set(P.nav2freq, freqValue)
                                end
                            end
                        elseif (navdata[def.DESTNAVTYPE] == def.NAVTYPELPV) then
                            local dmeInfo = loop.approachDME or helpers.findApproachDME(P.navdatatable, get(P.desicao), get(P.desrwy), navdata[def.DESTLATPOS], navdata[def.DESTLONPOS], navdata[def.DESTNAVID])
                            loop.approachDME = dmeInfo
                            if dmeInfo then
                                local freqValue = dmeInfo[def.DESTDMEFREQ] ~= 0 and dmeInfo[def.DESTDMEFREQ] or dmeInfo[def.DESTFREQ]
                                set(P.nav2stdbyfreq, get(P.nav2freq))
                                set(P.nav2freq, freqValue)
                            end
                        elseif (navdata[def.DESTNAVTYPE] == def.NAVTYPEGLS) and (get(P.mmrinstalled) == def.ON) then
                            helpers.mmrCopyActToStby(def.MMRFO)
                            set(P.mmrfoactmode, def.MMRGLS)
                            local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                            set(P.mmrfoactvalue, freqValue)
                        end
                    end,
                    advice = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if not navdata then return "" end
                        if isLocalizerNavType(navdata[def.DESTNAVTYPE]) then
                            if navdata[def.DESTNAVDME] then
                                local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                                return "Set Copilot Frequency " .. helpers.addspaces(helpers.formatILSFrequency(freqValue))
                            else
                                local dmeInfo = loop.approachDME or helpers.findApproachDME(P.navdatatable, get(P.desicao), get(P.desrwy), navdata[def.DESTLATPOS], navdata[def.DESTLONPOS], navdata[def.DESTNAVID])
                                loop.approachDME = dmeInfo
                                if dmeInfo then
                                    local freqValue = dmeInfo[def.DESTDMEFREQ] ~= 0 and dmeInfo[def.DESTDMEFREQ] or dmeInfo[def.DESTFREQ]
                                    local ident = dmeInfo[def.DESTDMEIDENT] or dmeInfo[def.DESTNAVID] or ""
                                    local identText = (ident ~= "" and (" (" .. helpers.spellNato(ident) .. ")")) or ""
                                    return "Set Copilot D M E Frequency " .. helpers.addspaces(helpers.formatILSFrequency(freqValue)) .. identText
                                end
                            end
                        elseif (navdata[def.DESTNAVTYPE] == def.NAVTYPELPV) then
                            local dmeInfo = loop.approachDME or helpers.findApproachDME(P.navdatatable, get(P.desicao), get(P.desrwy), navdata[def.DESTLATPOS], navdata[def.DESTLONPOS], navdata[def.DESTNAVID])
                            loop.approachDME = dmeInfo
                            if dmeInfo then
                                local freqValue = dmeInfo[def.DESTDMEFREQ] ~= 0 and dmeInfo[def.DESTDMEFREQ] or dmeInfo[def.DESTFREQ]
                                local ident = dmeInfo[def.DESTDMEIDENT] or dmeInfo[def.DESTNAVID] or ""
                                local identText = (ident ~= "" and (" (" .. helpers.spellNato(ident) .. ")")) or ""
                                return "Set Copilot D M E Frequency " .. helpers.addspaces(helpers.formatILSFrequency(freqValue)) .. identText
                            end
                        else
                            local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                            return "Set Copilot Channel " .. helpers.addspaces(freqValue)
                        end
                        return ""
                    end,
                    confirm = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if not navdata then
                            loop.approachDME = nil
                            return ""
                        end

                        local message = ""

                        if isLocalizerNavType(navdata[def.DESTNAVTYPE]) then
                            if navdata[def.DESTNAVDME] then
                                local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                                message = "Copilot Frequency checked and " .. helpers.addspaces(helpers.formatILSFrequency(freqValue))
                            else
                                local dmeInfo = loop.approachDME or helpers.findApproachDME(P.navdatatable, get(P.desicao), get(P.desrwy), navdata[def.DESTLATPOS], navdata[def.DESTLONPOS], navdata[def.DESTNAVID])
                                loop.approachDME = dmeInfo
                                if dmeInfo then
                                    local freqValue = dmeInfo[def.DESTDMEFREQ] ~= 0 and dmeInfo[def.DESTDMEFREQ] or dmeInfo[def.DESTFREQ]
                                    local ident = dmeInfo[def.DESTDMEIDENT] or dmeInfo[def.DESTNAVID] or ""
                                    local identText = (ident ~= "" and (" (" .. helpers.spellNato(ident) .. ")")) or ""
                                    message = "Copilot D M E Frequency checked and " .. helpers.addspaces(helpers.formatILSFrequency(freqValue)) .. identText
                                end
                            end
                        elseif (navdata[def.DESTNAVTYPE] == def.NAVTYPELPV) then
                            local dmeInfo = loop.approachDME or helpers.findApproachDME(P.navdatatable, get(P.desicao), get(P.desrwy), navdata[def.DESTLATPOS], navdata[def.DESTLONPOS], navdata[def.DESTNAVID])
                            loop.approachDME = dmeInfo
                            if dmeInfo then
                                local freqValue = dmeInfo[def.DESTDMEFREQ] ~= 0 and dmeInfo[def.DESTDMEFREQ] or dmeInfo[def.DESTFREQ]
                                local ident = dmeInfo[def.DESTDMEIDENT] or dmeInfo[def.DESTNAVID] or ""
                                local identText = (ident ~= "" and (" (" .. helpers.spellNato(ident) .. ")")) or ""
                                message = "Copilot D M E Frequency checked and " .. helpers.addspaces(helpers.formatILSFrequency(freqValue)) .. identText
                            end
                        else
                            local freqValue = getFmcApproachRefFrequency(navdata[def.DESTNAVTYPE]) or navdata[def.DESTFREQ]
                            message = "Copilot Channel checked and " .. helpers.addspaces(freqValue)
                        end
                        loop.approachDME = nil
                        return message
                    end,
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'set_capt_course'
                },
                ['set_capt_course'] = {
                    check = function(loop, procData)
                        local pilotcoursenew = getCachedApproachCourse(loop)
                        return get(P.mcppilotcourse) == pilotcoursenew
                    end,
                    action = function(loop, procData)
                        local pilotcoursenew = getCachedApproachCourse(loop)
                        set(P.mcppilotcourse, pilotcoursenew)
                    end,
                    advice = function(loop, procData)
                        local pilotcoursenew = getCachedApproachCourse(loop)
                        return "Set Captain Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(pilotcoursenew, 3))
                    end,
                    confirm = function(loop, procData)
                        local pilotcoursenew = getCachedApproachCourse(loop)
                        return "Captain Course checked and " .. helpers.addspaces(helpers.padNumberWithZerosStrict(pilotcoursenew, 3))
                    end,
                    nextStep = 'set_fo_course'
                },
                ['set_fo_course'] = {
                    skipIf = function(loop, procData)
                        local navdata = P.navdatatable[loop.navdatatableindex]
                        if navdata[def.DESTNAVTYPE] == def.NAVTYPELPV then return true end
                        if isLocalizerNavType(navdata[def.DESTNAVTYPE]) and not navdata[def.DESTNAVDME] then return true end
                        return false 
                    end,
                    check = function(loop, procData)
                        return get(P.mcpcopilotcourse) == get(P.mcppilotcourse)
                    end,
                    action = function(loop, procData)
                        set(P.mcpcopilotcourse, get(P.mcppilotcourse))
                    end,
                    advice = function(loop, procData)
                        return "Set Copilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcppilotcourse), 3))
                    end,
                    confirm = function(loop, procData)
                        return "Copilot Course checked and " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcppilotcourse), 3))
                    end,
                    nextStep = nil 
                }
            } 
        },
        [def.SETVREFPROCEDURE] = {
            number = 21, 
            name = "Set V Ref", 
            cycable = false, 
            speakname = false, 
            set = false, 
            loop = 3, 
            prerequisite = nil, 
            allowedState = nil, 
            requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH, def.FLIGHTSTATEINITIALCLIMB }, 
            skipCondition = nil,
            repeatable = true, 
            startStep = 'view_fms',
            steps = {
                ['view_fms'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWFMS] end,
                    normalize = true, 
                    nextStep = 'calculate_vref'
                },
                ['calculate_vref'] = {
                    action = function(loop, procData)
                        local customCalcOn = (P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] == def.ON)
                        if customCalcOn then
                            local baseFlaps = get(P.appflaps)
                            if not baseFlaps or baseFlaps <= 0 then baseFlaps = 30 end
                            local baseVref = get(P.vref)
                            local ziboVref = nil
                            local variant = get(P.b737variant)
                            local landingGwFmc = get(P.fmclandinggw)
                            local landingGwKg = get(P.totalweightkgs)
                            local fmcUnits = get(P.fuelunit) or 0
                            if landingGwFmc and landingGwFmc > 0 then
                                if fmcUnits == def.LBS or fmcUnits == 0 then
                                    landingGwKg = landingGwFmc * 1000 * def.LBSTOKG
                                else
                                    landingGwKg = landingGwFmc * 1000
                                end
                            end
                            if P.zibocalctable then
                                ziboVref = helpers.getZiboVref(
                                    P.zibocalctable,
                                    variant,
                                    baseFlaps,
                                    landingGwKg
                                )
                            end
                            local vrefInput = ziboVref or baseVref
                            local appflapscalc, appvrefcalc = helpers.calcappflapsvref(
                                get(P.totalweightkgs),
                                get(P.desrwylen),
                                get(P.desrwyheading),
                                vrefInput,
                                P.desmetar,
                                baseFlaps
                            )
                            loop.appflapscalc = appflapscalc
                            loop.appvrefcalc = appvrefcalc
                            loop.appflapscalcstring = tostring(appflapscalc)
                            loop.appvrefcalcstring = tostring(appvrefcalc)
                        else
                            local fallbackFlaps = get(P.appflaps)
                            if not fallbackFlaps or fallbackFlaps <= 0 then
                                fallbackFlaps = 30
                            end
                            local fallbackVref = get(P.vref)
                            if not fallbackVref or fallbackVref <= 0 then
                                fallbackVref = get(P.vref30)
                            end
                            loop.appflapscalc = fallbackFlaps
                            loop.appvrefcalc = fallbackVref
                            loop.appflapscalcstring = helpers.padNumberWithZerosStrict(math.floor(fallbackFlaps + 0.5), 2)
                            loop.appvrefcalcstring = tostring(math.floor(fallbackVref + 0.5))
                        end
                    end,
                    runActionInAdviceMode = true, 
                    nextStep = 'branch_fmc_vref'
                },
                ['branch_fmc_vref'] = {
                    branch = function()
                        if shouldSkipFmcSteps() then
                            return 'view_main_panel'
                        end
                        return 'check_fms_page'
                    end
                },
                ['check_fms_page'] = {
                    check = function(loop, procData)
                        return helpers.fmcHeaderContains("APPROACH REF")
                    end,
                    fmcPage = true,
                    action = function(loop, procData)
                        if isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/fmc1_init_ref")
                        end
                    end,
                    advice = "Open F M C Approach Reference Page",
                    runActionInAdviceMode = true,
                    branch = function(loop, procData)
                        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                            sasl.logDebug("SetVref: VoiceAdviceOnly mode. Skipping auto-input steps.")
                            return 'voice_vref_advice'
                        else
                            sasl.logDebug("SetVref: Auto mode. Starting FMC input sequence.")
                            return 'fmc_press_del' 
                        end
                    end
                },
                ['fmc_press_del'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_del") end,
                    runActionInAdviceMode = false, 
                    nextStep = 'fmc_press_clr'
                },
                ['fmc_press_clr'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_clr") end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_flap_1'
                },
                ['fmc_enter_flap_1'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.appflapscalcstring, 1, 1)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_flap_2'
                },
                ['fmc_enter_flap_2'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.appflapscalcstring, 2, 2)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_press_slash'
                },
                ['fmc_press_slash'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_slash") end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_vref_1'
                },
                ['fmc_enter_vref_1'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.appvrefcalcstring, 1, 1)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_vref_2'
                },
                ['fmc_enter_vref_2'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.appvrefcalcstring, 2, 2)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_vref_3'
                },
                ['fmc_enter_vref_3'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.appvrefcalcstring, 3, 3)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_press_4R'
                },
                ['fmc_press_4R'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_4R") end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_press_exec'
                },
                ['voice_vref_advice'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON end,
                    check = function(loop)
                        local target = tonumber(loop and loop.appvrefcalc) or 0
                        if target <= 0 then return false end
                        return (get(P.vref) == target)
                    end,
                    advice = function(loop)
                        local flaps = tostring(loop.appflapscalcstring or get(P.appflaps) or "")
                        local vref = tostring(loop.appvrefcalcstring or get(P.vref) or "")
                        return "Set V REF flaps " .. flaps .. " " .. vref
                    end,
                    confirm = function(loop)
                        local target = tonumber(loop and loop.appvrefcalc)
                        if target and target > 0 and get(P.vref) == target then
                            return "V REF flaps " .. tostring(loop.appflapscalcstring or "") .. " checked and " .. tostring(loop.appvrefcalcstring or target)
                        end
                        return false
                    end,
                    runActionInAdviceMode = true,
                    nextStep = 'view_main_panel'
                },
                ['fmc_press_exec'] = {
                    action = function(loop, procData) 
                        P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_exec") 
                        P.commandtableentry(def.TEXT, "V REF " .. loop.appflapscalcstring .. " " .. loop.appvrefcalcstring .. " Knots set")
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'check_vref_set'
                },
                ['check_vref_set'] = {
                    check = function(loop, procData)
                        return (get(P.vref) == loop.appvrefcalc)
                    end,
                    advice = function(loop, procData)
                        return "Set V REF " .. loop.appflapscalcstring .. " " .. loop.appvrefcalcstring
                    end,
                    confirm = function(loop, procData)
                        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                            return "V REF " .. loop.appflapscalcstring .. " checked and " .. loop.appvrefcalcstring
                        else
                            return false 
                        end
                    end,
                    branch = function(loop) return 'view_main_panel' end,
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil 
                }
            }
        },
        [def.SETWINDCORRPROCEDURE] = {
            number = 25,
            name = "Set Wind Correction",
            cycable = false,
            speakname = false,
            set = false,
            loop = 3,
            prerequisite = nil,
            allowedState = nil,
            requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH, def.FLIGHTSTATEINITIALCLIMB },
            skipCondition = nil,
            repeatable = true,
            startStep = 'view_fms',
            steps = {
                ['view_fms'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWFMS] end,
                    normalize = true,
                    nextStep = 'calculate_windcorr'
                },
                ['calculate_windcorr'] = {
                    action = function(loop, procData)
                        local customCalcOn = (P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] == def.ON)
                        loop.appwindcorr = nil
                        loop.appwindcorrstring = nil
                        if not customCalcOn then
                            local windcorr = helpers.calculateApproachWindCorrection(get(P.desrwyheading), P.desmetar)
                            if windcorr ~= nil then
                                if windcorr <= 0 then
                                    loop.appwindcorr = nil
                                    loop.appwindcorrstring = nil
                                else
                                    if windcorr < 5 then
                                        windcorr = 5
                                    end
                                    loop.appwindcorr = windcorr
                                    loop.appwindcorrstring = helpers.padNumberWithZerosStrict(math.floor(windcorr + 0.5), 2)
                                end
                            end
                        end
                    end,
                    runActionInAdviceMode = true,
                    nextStep = 'branch_fmc_windcorr'
                },
                ['branch_fmc_windcorr'] = {
                    branch = function()
                        if shouldSkipFmcSteps() then
                            return 'view_main_panel'
                        end
                        return 'check_fms_page'
                    end
                },
                ['check_fms_page'] = {
                    check = function(loop, procData)
                        return helpers.fmcHeaderContains("APPROACH REF")
                    end,
                    fmcPage = true,
                    action = function(loop, procData)
                        if isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/fmc1_init_ref")
                        end
                    end,
                    advice = "Open F M C Approach Reference Page",
                    runActionInAdviceMode = true,
                    branch = function(loop, procData)
                        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                            return 'voice_wind_advice'
                        end
                        if loop and loop.appwindcorrstring then
                            return 'fmc_press_del'
                        end
                        return 'check_windcorr_set'
                    end
                },
                ['fmc_press_del'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_del") end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_press_clr'
                },
                ['fmc_press_clr'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_clr") end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_windcorr_1'
                },
                ['fmc_enter_windcorr_1'] = {
                    skipIf = function(loop) return not (loop and loop.appwindcorrstring) end,
                    action = function(loop, procData)
                        local char = string.sub(loop.appwindcorrstring, 1, 1)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_windcorr_2'
                },
                ['fmc_enter_windcorr_2'] = {
                    skipIf = function(loop) return not (loop and loop.appwindcorrstring) end,
                    action = function(loop, procData)
                        local char = string.sub(loop.appwindcorrstring, 2, 2)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_windcorr_3'
                },
                ['fmc_enter_windcorr_3'] = {
                    skipIf = function(loop) return not (loop and loop.appwindcorrstring) end,
                    action = function(loop, procData)
                        local char = string.sub(loop.appwindcorrstring, 3, 3)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_press_5R'
                },
                ['fmc_press_5R'] = {
                    skipIf = function(loop) return not (loop and loop.appwindcorrstring) end,
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_5R") end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_press_exec'
                },
                ['fmc_press_exec'] = {
                    action = function(loop, procData)
                        P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_exec")
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'check_windcorr_set'
                },
                ['check_windcorr_set'] = {
                    check = function(loop)
                        local fmcWind = tonumber(get(P.vrefapproachwindcorr))
                        local target = tonumber(loop and loop.appwindcorr)
                            or tonumber(loop and loop.appwindcorrstring)
                            or fmcWind
                            or 5
                        local current = fmcWind or 0
                        return math.abs(current - target) < 0.5
                    end,
                    advice = function(loop)
                        local fmcWind = tonumber(get(P.vrefapproachwindcorr))
                        local target = tonumber(loop and loop.appwindcorr)
                            or tonumber(loop and loop.appwindcorrstring)
                            or fmcWind
                            or 5
                        local targetStr = loop and loop.appwindcorrstring
                        if not targetStr or targetStr == "" then
                            targetStr = tostring(target)
                        end
                        return "Set F M C Wind Correction +" .. targetStr .. " in F M C"
                    end,
                    confirm = function(loop)
                        local fmcWind = tonumber(get(P.vrefapproachwindcorr))
                        local target = tonumber(loop and loop.appwindcorr)
                            or tonumber(loop and loop.appwindcorrstring)
                            or fmcWind
                            or 5
                        local targetStr = loop and loop.appwindcorrstring
                        if not targetStr or targetStr == "" then
                            targetStr = tostring(target)
                        end
                        local current = fmcWind or 0
                        if math.abs(current - target) < 0.5 then
                            return "F M C Wind Correction checked +" .. targetStr
                        end
                        return false
                    end,
                    nextStep = 'view_main_panel'
                },
                ['voice_wind_advice'] = {
                    skipIf = function(loop)
                        return P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON
                    end,
                    check = function(loop)
                        local fmcWind = tonumber(get(P.vrefapproachwindcorr))
                        local target = tonumber(loop and loop.appwindcorr)
                            or tonumber(loop and loop.appwindcorrstring)
                            or fmcWind
                            or 5
                        local current = fmcWind or 0
                        return math.abs(current - target) < 0.5
                    end,
                    advice = function(loop)
                        local fmcWind = tonumber(get(P.vrefapproachwindcorr))
                        local target = tonumber(loop and loop.appwindcorr)
                            or tonumber(loop and loop.appwindcorrstring)
                            or fmcWind
                            or 5
                        local targetStr = loop and loop.appwindcorrstring
                        if not targetStr or targetStr == "" then
                            targetStr = tostring(target)
                        end
                        return "Set F M C Wind Correction +" .. targetStr .. " in F M C"
                    end,
                    confirm = function(loop)
                        local fmcWind = tonumber(get(P.vrefapproachwindcorr))
                        local target = tonumber(loop and loop.appwindcorr)
                            or tonumber(loop and loop.appwindcorrstring)
                            or fmcWind
                            or 5
                        local targetStr = loop and loop.appwindcorrstring
                        if not targetStr or targetStr == "" then
                            targetStr = tostring(target)
                        end
                        local current = fmcWind or 0
                        if math.abs(current - target) < 0.5 then
                            return "F M C Wind Correction checked +" .. targetStr
                        end
                        return false
                    end,
                    runActionInAdviceMode = true,
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.SETTOFLAPSPROCEDURE] = {
            number = 22, 
            name = "Set Takeoff Flaps", 
            cycable = false, 
            speakname = false, 
            set = false, 
            loop = 3, 
            prerequisite = function()
                if P.proceduretable[def.COCKPITINITPROCEDURE].set then
                    return true
                end
                if P.loopStateTables and P.loopStateTables[1] then
                    return P.loopStateTables[1].lock == def.COCKPITINITPROCEDURE
                end
                return false
            end,
            allowedState = def.GROUNDONLY, 
            requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, 
            skipCondition = nil,
            repeatable = true, 
            startStep = 'view_fms',
            steps = {
                ['view_fms'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWFMS] end,
                    normalize = true, 
                    nextStep = 'calculate_flaps'
                },
                ['calculate_flaps'] = {
                    action = function(loop, procData)
                        local useCustomCalc = (P.configvalues[def.CONFIGCUSTOMAPPROACHCALC] == def.ON)
                        local computedFlaps = nil
                        if useCustomCalc then
                            computedFlaps = helpers.determineTakeoffFlapsSetting(
                                get(P.totalweightkgs),
                                get(P.deprwylen),
                                get(P.deprwyheading),
                                get(P.elevation),
                                P.depmetar,
                                get(P.toflaps) or get(P.toflapsset)
                            )
                        end
                        local existingFlaps = get(P.toflaps)
                        if existingFlaps and existingFlaps > 0 then
                            if useCustomCalc and computedFlaps then
                                loop.toflapscalc = computedFlaps
                                loop.flapsPreSet = false
                            else
                                loop.toflapscalc = existingFlaps
                                loop.flapsPreSet = true
                            end
                        else
                            local candidate = computedFlaps
                            if not candidate or candidate <= 0 then
                                candidate = get(P.toflapsset)
                            end
                            if not candidate or candidate <= 0 then
                                candidate = 5
                            end
                            loop.toflapscalc = candidate
                            loop.flapsPreSet = not useCustomCalc
                        end
                        loop.toflapscalcstring = tostring(loop.toflapscalc)

                        local tabletCg = helpers.formatcgvalue(get(P.tabcg))
                        local calculatedCg = helpers.formatcgvalue(get(P.calctakeoffcg))
                        loop.calculatedCgString = tabletCg or calculatedCg

                        local existingCg = helpers.formatcgvalue(get(P.fmccg))
                        if existingCg then
                            loop.targetCgString = existingCg
                            loop.cgPreSet = true
                        else
                            loop.targetCgString = loop.calculatedCgString
                            loop.cgPreSet = false
                        end

                    end,
                    runActionInAdviceMode = true, 
                    nextStep = 'branch_fmc_takeoff'
                },
                ['branch_fmc_takeoff'] = {
                    branch = function()
                        if shouldSkipFmcSteps() then
                            return 'view_main_panel'
                        end
                        return 'check_fms_page'
                    end
                },
                ['check_fms_page'] = {
                    skipIf = function() return helpers.fmcHeaderContains("N1 LIMIT") or helpers.fmcHeaderContains("TAKEOFF REF") end,
                    check = function(loop, procData)
                        return helpers.fmcHeaderContains("PERF INIT")
                    end,
                    fmcPage = true,
                    action = function(loop, procData)
                        if isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/fmc1_init_ref")
                        end
                    end,
                    advice = "Open F M C Init Reference Page",
                    runActionInAdviceMode = true,
                    nextStep = 'ensure_n1_limit_page'
                },
                ['ensure_n1_limit_page'] = {
                    skipIf = function() return helpers.fmcHeaderContains("TAKEOFF REF") end,
                    check = function(loop, procData)
                        return helpers.fmcHeaderContains("N1 LIMIT")
                    end,
                    fmcPage = true,
                    action = function(loop, procData)
                        if isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/fmc1_6R")
                        end
                    end,
                    advice = "Open F M C N 1 Limit Page",
                    runActionInAdviceMode = true,
                    nextStep = 'ensure_takeoff_ref_page'
                },
                ['ensure_takeoff_ref_page'] = {
                    check = function(loop, procData)
                        return helpers.fmcHeaderContains("TAKEOFF REF")
                    end,
                    fmcPage = true,
                    action = function(loop, procData)
                        if isFmcAutomationOn() then
                            helpers.command_once("laminar/B738/button/fmc1_6R")
                        end
                    end,
                    advice = "Open F M C Takeoff Reference Page",
                    runActionInAdviceMode = true,
                    nextStep = 'branch_after_takeoff_ref'
                },
                ['branch_after_takeoff_ref'] = {
                    branch = function(loop, procData)
                        if loop.flapsPreSet and loop.cgPreSet then
                            sasl.logDebug("SetTakeoffFlaps: Flaps/CG already present, skipping FMC input.")
                            return 'check_flaps_set'
                        end
                        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                            sasl.logDebug("SetTakeoffFlaps: VoiceAdviceOnly mode. Skipping auto-input steps.")
                            return 'check_flaps_set'
                        else
                            sasl.logDebug("SetTakeoffFlaps: Auto mode. Starting FMC input sequence.")
                            return 'fmc_press_del'
                        end
                    end
                },
                ['fmc_press_del'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_del") end,
                    runActionInAdviceMode = false, 
                    nextStep = 'fmc_press_clr'
                },
                ['fmc_press_clr'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_clr") end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_flap_1'
                },
                ['fmc_enter_flap_1'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.toflapscalcstring, 1, 1)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_enter_flap_2'
                },
                ['fmc_enter_flap_2'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.toflapscalcstring, 2, 2)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_press_1L'
                },
                ['fmc_press_1L'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_1L") end,
                    runActionInAdviceMode = false,
                    nextStep = 'fmc_flaps_set'
                },
                ['fmc_flaps_set'] = {
                    action = function(loop, procData) 
                        P.commandtableentry(def.TEXT, "Takeoff Flaps " .. loop.toflapscalcstring .. " set")
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'check_flaps_set'
                },
                ['check_flaps_set'] = {
                    check = function(loop, procData)
                        local currentFlaps = get(P.toflaps)
                        if currentFlaps and currentFlaps > 0 then
                            if currentFlaps ~= loop.toflapscalc then
                                loop.toflapscalc = currentFlaps
                                loop.toflapscalcstring = tostring(currentFlaps)
                            end
                            return true
                        end
                        return false
                    end,
                    advice = function(loop, procData)
                        if (get(P.toflaps) or 0) == 0 then
                            return "Enter Takeoff Flaps " .. loop.toflapscalcstring
                        end
                        return nil
                    end,
                    confirm = function(loop, procData)
                        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                            return "Takeoff Flaps " .. loop.toflapscalcstring .. " checked"
                        else
                            return false 
                        end
                    end,
                    nextStep = 'check_cg_set'
                },
                ['check_cg_set'] = {
                    check = function(loop, procData)
                        local currentCg = helpers.formatcgvalue(get(P.fmccg))
                        if currentCg then
                            loop.targetCgString = currentCg
                            return true
                        end
                        return false
                    end,
                    advice = function(loop, procData)
                        local currentCg = helpers.formatcgvalue(get(P.fmccg))
                        if currentCg then
                            return "C G already set " .. tostring(currentCg)
                        end
                        local targetCg = loop.calculatedCgString or loop.targetCgString
                        if targetCg then
                            return "Set C G " .. tostring(targetCg)
                        end
                        return "Set C G according to Tablet"
                    end,
                    confirm = function(loop, procData)
                        local setCg = helpers.formatcgvalue(get(P.fmccg))
                        if setCg then
                            return "C G checked and " .. tostring(setCg)
                        end
                        return "C G checked"
                    end,
                    nextStep = 'branch_vspeeds'
                },
                ['branch_vspeeds'] = {
                    branch = function(loop, procData)
                        if not isQrhOff() then
                            return 'view_main_panel'
                        end
                        loop.v1calcstring = getCalcSpeedString(get(P.v1calcspeed))
                        loop.vrcalcstring = getCalcSpeedString(get(P.vrcalcspeed))
                        loop.v2calcstring = getCalcSpeedString(get(P.v2calcspeed))
                        if not loop.v1calcstring or not loop.vrcalcstring or not loop.v2calcstring then
                            return 'view_main_panel'
                        end
                        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                            return 'voice_v1_advice'
                        end
                        if (get(P.v1setspeed) or 0) > 0 and (get(P.vrsetspeed) or 0) > 0 and (get(P.v2setspeed) or 0) > 0 then
                            return 'check_vspeeds_set'
                        end
                        return 'v1_press_del'
                    end
                },
                ['voice_v1_advice'] = {
                    check = function()
                        return (get(P.v1setspeed) or 0) > 0
                    end,
                    advice = function(loop)
                        local target = loop and loop.v1calcstring or getCalcSpeedString(get(P.v1calcspeed))
                        if target then
                            return "Set V 1 " .. helpers.addspaces(target)
                        end
                        return "Set V 1"
                    end,
                    confirm = function()
                        local set = get(P.v1setspeed) or 0
                        if set > 0 then
                            local setStr = helpers.padNumberWithZerosStrict(math.floor(set + 0.5), 3)
                            return "V 1 checked " .. helpers.addspaces(setStr)
                        end
                        return false
                    end,
                    nextStep = 'voice_vr_advice'
                },
                ['voice_vr_advice'] = {
                    check = function()
                        return (get(P.vrsetspeed) or 0) > 0
                    end,
                    advice = function(loop)
                        local target = loop and loop.vrcalcstring or getCalcSpeedString(get(P.vrcalcspeed))
                        if target then
                            return "Set V R " .. helpers.addspaces(target)
                        end
                        return "Set V R"
                    end,
                    confirm = function()
                        local set = get(P.vrsetspeed) or 0
                        if set > 0 then
                            local setStr = helpers.padNumberWithZerosStrict(math.floor(set + 0.5), 3)
                            return "V R checked " .. helpers.addspaces(setStr)
                        end
                        return false
                    end,
                    nextStep = 'voice_v2_advice'
                },
                ['voice_v2_advice'] = {
                    check = function()
                        return (get(P.v2setspeed) or 0) > 0
                    end,
                    advice = function(loop)
                        local target = loop and loop.v2calcstring or getCalcSpeedString(get(P.v2calcspeed))
                        if target then
                            return "Set V 2 " .. helpers.addspaces(target)
                        end
                        return "Set V 2"
                    end,
                    confirm = function()
                        local set = get(P.v2setspeed) or 0
                        if set > 0 then
                            local setStr = helpers.padNumberWithZerosStrict(math.floor(set + 0.5), 3)
                            return "V 2 checked " .. helpers.addspaces(setStr)
                        end
                        return false
                    end,
                    nextStep = 'check_vspeeds_set'
                },
                ['v1_press_del'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_del") end,
                    runActionInAdviceMode = false,
                    nextStep = 'v1_press_clr'
                },
                ['v1_press_clr'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_clr") end,
                    runActionInAdviceMode = false,
                    nextStep = 'v1_enter_1'
                },
                ['v1_enter_1'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.v1calcstring or "", 1, 1)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'v1_enter_2'
                },
                ['v1_enter_2'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.v1calcstring or "", 2, 2)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'v1_enter_3'
                },
                ['v1_enter_3'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.v1calcstring or "", 3, 3)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'v1_press_1R'
                },
                ['v1_press_1R'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_1R") end,
                    runActionInAdviceMode = false,
                    nextStep = 'vr_press_del'
                },
                ['vr_press_del'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_del") end,
                    runActionInAdviceMode = false,
                    nextStep = 'vr_press_clr'
                },
                ['vr_press_clr'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_clr") end,
                    runActionInAdviceMode = false,
                    nextStep = 'vr_enter_1'
                },
                ['vr_enter_1'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.vrcalcstring or "", 1, 1)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'vr_enter_2'
                },
                ['vr_enter_2'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.vrcalcstring or "", 2, 2)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'vr_enter_3'
                },
                ['vr_enter_3'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.vrcalcstring or "", 3, 3)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'vr_press_2R'
                },
                ['vr_press_2R'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_2R") end,
                    runActionInAdviceMode = false,
                    nextStep = 'v2_press_del'
                },
                ['v2_press_del'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_del") end,
                    runActionInAdviceMode = false,
                    nextStep = 'v2_press_clr'
                },
                ['v2_press_clr'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_clr") end,
                    runActionInAdviceMode = false,
                    nextStep = 'v2_enter_1'
                },
                ['v2_enter_1'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.v2calcstring or "", 1, 1)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'v2_enter_2'
                },
                ['v2_enter_2'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.v2calcstring or "", 2, 2)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'v2_enter_3'
                },
                ['v2_enter_3'] = {
                    action = function(loop, procData)
                        local char = string.sub(loop.v2calcstring or "", 3, 3)
                        if char and char ~= "" then P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. char) end
                    end,
                    runActionInAdviceMode = false,
                    nextStep = 'v2_press_3R'
                },
                ['v2_press_3R'] = {
                    action = function(loop, procData) P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_3R") end,
                    runActionInAdviceMode = false,
                    nextStep = 'check_vspeeds_set'
                },
                ['check_vspeeds_set'] = {
                    check = function(loop, procData)
                        return (get(P.v1setspeed) > 0) and (get(P.v2setspeed) > 0) and (get(P.vrsetspeed) > 0)
                    end,
                    advice = "Enter V Speeds",
                    confirm = "V Speeds checked and Set",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil 
                }
            }
        },
        [def.TESTPROCEDURE] = {
            number = 23,
            name = "Test",
            cycable = true,
            speakname = true,
            set = false,
            loop = 1, -- (Annahme: Läuft in Loop 1)
            prerequisite = nil,
            allowedState = def.GROUNDONLY,
            requiredFlightstate = def.FLIGHTSTATEPREFLIGHT,
            skipCondition = nil,
            prerequisiteChecks = {
                { check = function() return (get(P.battery) == def.ON) or (get(P.mainbus) == def.ON) end, 
                failMsg = "Procedure aborted, Battery is Off" }
            },
            
            startStep = 'view_throttle',
            
            steps = {
                ['view_throttle'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    normalize = true, -- (Ersetzt P.setview(def.DEFAULTVIEW) aus altem Step 1)
                    nextStep = 'fire_test_lft_begin'
                },
                ['fire_test_lft_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/fire_test_lft") end,
                    nextStep = 'fire_test_lft_end'
                },
                ['fire_test_lft_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/fire_test_lft") end,
                    nextStep = 'fire_test_rgt_begin'
                },
                ['fire_test_rgt_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/fire_test_rgt") end,
                    nextStep = 'fire_test_rgt_end'
                },
                ['fire_test_rgt_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/fire_test_rgt") end,
                    nextStep = 'exting_test_lft_begin'
                },
                ['exting_test_lft_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/exting_test_lft") end,
                    nextStep = 'exting_test_lft_end'
                },
                ['exting_test_lft_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/exting_test_lft") end,
                    nextStep = 'exting_test_rgt_begin'
                },
                ['exting_test_rgt_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/exting_test_rgt") end,
                    nextStep = 'exting_test_rgt_end'
                },
                ['exting_test_rgt_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/exting_test_rgt") end,
                    nextStep = 'cargo_fire_test_begin'
                },
                ['cargo_fire_test_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/push_button/cargo_fire_test_push") end,
                    nextStep = 'cargo_fire_test_end'
                },
                ['cargo_fire_test_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/push_button/cargo_fire_test_push") end,
                    nextStep = 'view_upper_overhead'
                },
                ['view_upper_overhead'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL] end,
                    nextStep = 'flaps_test_begin'
                },
                ['flaps_test_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/push_button/flaps_test") end,
                    nextStep = 'flaps_test_end'
                },
                ['flaps_test_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/push_button/flaps_test") end,
                    nextStep = 'mach_warn1_test_begin'
                },
                ['mach_warn1_test_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/push_button/mach_warn1_test") end,
                    nextStep = 'mach_warn1_test_end'
                },
                ['mach_warn1_test_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/push_button/mach_warn1_test") end,
                    nextStep = 'mach_warn2_test_begin'
                },
                ['mach_warn2_test_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/push_button/mach_warn2_test") end,
                    nextStep = 'mach_warn2_test_end'
                },
                ['mach_warn2_test_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/push_button/mach_warn2_test") end,
                    nextStep = 'stall_test1_begin'
                },
                ['stall_test1_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/push_button/stall_test1_press") end,
                    nextStep = 'stall_test1_end'
                },
                ['stall_test1_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/push_button/stall_test1_press") end,
                    nextStep = 'stall_test2_begin'
                },
                ['stall_test2_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/push_button/stall_test2_press") end,
                    nextStep = 'stall_test2_end'
                },
                ['stall_test2_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/push_button/stall_test2_press") end, -- Korrigiert (annahme: war ein Tippfehler im Original)
                    nextStep = 'view_overhead'
                },
                ['view_overhead'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'window_ovht_test_up_begin'
                },
                ['window_ovht_test_up_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/window_ovht_test_up") end,
                    nextStep = 'window_ovht_test_up_end1'
                },
                ['window_ovht_test_up_end1'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_up") end,
                    nextStep = 'window_ovht_test_up_end2'
                },
                ['window_ovht_test_up_end2'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_up") end,
                    nextStep = 'window_ovht_test_dn_begin'
                },
                ['window_ovht_test_dn_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/window_ovht_test_dn") end,
                    nextStep = 'window_ovht_test_dn_end'
                },
                ['window_ovht_test_dn_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_dn") end,
                    nextStep = 'tat_test_begin'
                },
                ['tat_test_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/push_button/tat_test") end,
                    nextStep = 'tat_test_end'
                },
                ['tat_test_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/push_button/tat_test") end,
                    nextStep = 'duct_ovht_test_begin'
                },
                ['duct_ovht_test_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/push_button/duct_ovht_test") end,
                    nextStep = 'duct_ovht_test_end'
                },
                ['duct_ovht_test_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/push_button/duct_ovht_test") end,
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'bright_test_up'
                },
                ['bright_test_up'] = {
                    action = function(loop, procData) helpers.command_once("laminar/B738/toggle_switch/bright_test_up") end,
                    nextStep = 'bright_test_dn'
                },
                ['bright_test_dn'] = {
                    action = function(loop, procData) helpers.command_once("laminar/B738/toggle_switch/bright_test_dn") end,
                    nextStep = 'ap_disconnect_test1_up_begin'
                },
                ['ap_disconnect_test1_up_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test1_up") end,
                    nextStep = 'ap_disconnect_test1_up_end'
                },
                ['ap_disconnect_test1_up_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test1_up") end,
                    nextStep = 'ap_disconnect_test1_dn_begin'
                },
                ['ap_disconnect_test1_dn_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test1_dn") end,
                    nextStep = 'ap_disconnect_test1_dn_end'
                },
                ['ap_disconnect_test1_dn_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test1_dn") end,
                    nextStep = 'ap_disconnect_test2_up_begin'
                },
                ['ap_disconnect_test2_up_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test2_up") end,
                    nextStep = 'ap_disconnect_test2_up_end'
                },
                ['ap_disconnect_test2_up_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test2_up") end,
                    nextStep = 'ap_disconnect_test2_dn_begin'
                },
                ['ap_disconnect_test2_dn_begin'] = {
                    action = function(loop, procData) helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test2_dn") end,
                    nextStep = 'ap_disconnect_test2_dn_end'
                },
                ['ap_disconnect_test2_dn_end'] = {
                    action = function(loop, procData) helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test2_dn") end,
                    nextStep = 'view_pedestal'
                },
                ['view_pedestal'] = {
                view = function(loop, procData) return P.configvalues[def.CONFIGVIEWPEDESTAL] end,
                nextStep = 'transponder_tcas_test'
                },
                ['transponder_tcas_test'] = {
                    action = function(loop, procData) helpers.command_once("laminar/B738/knob/transponder_tcas_test") end,
                    nextStep = 'view_main_panel_final'
                },
                ['view_main_panel_final'] = {
                    view = function(loop, procData) return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        }
    }
    
    return true
end
return M
