-- Live withdrawal predicates for the existing advice owners. No event detector,
-- timer, cadence or flight-state transition is owned by this module.
local M = {}

function M.attach(P, def, helpers, settings)
    local function n(name)
        local ref = P[name]
        if not ref or not isProperty(ref) then return nil end
        return tonumber(get(ref))
    end
    local function s(name)
        local ref = P[name]
        return ref and isProperty(ref) and tostring(get(ref) or "") or ""
    end
    local function cfg(index)
        return (settings and settings.appSettings or P.configvalues or {})[index]
    end
    local function air() return n("airgroundsensor") == def.OFF end
    local function preflight() return n("airgroundsensor") == def.ON and P.flightstate == def.FLIGHTSTATEPREFLIGHT end
    local function idle() return P.procedureloop1 and P.procedureloop1.lock == def.NOPROCEDURE end
    local function preOwner()
        local proc = P.proceduretable[def.COCKPITINITPROCEDURE]
        local loop = proc and P[def.PROCEDURELOOP .. proc.loop]
        return not loop or loop.lock ~= def.COCKPITINITPROCEDURE
    end
    local function cruise()
        return air() and P.flightstate == def.FLIGHTSTATECRUISE
            and n("fmsflightphase") == def.FMSFLIGHTPHASE_CRUISE
    end
    local function departure()
        return s("depicao") .. "|" .. s("deprwy") .. "|" .. s("fmsselectedsid")
    end
    local function arrival()
        return s("desicao") .. "|" .. s("desrwy") .. "|" .. s("fmsselectedapp")
    end

    function P.conditionalRouteContext()
        return arrival() .. "|" .. s("fmslegs")
    end

    function P.conditionalTakeoffReadinessPending(kind, target, signature)
        local beforeTaxi = P.proceduretable[def.BEFORETAXIPROCEDURE]
        local beforeTakeoff = P.proceduretable[def.BEFORETAKEOFFPROCEDURE]
        local context = P.takeoffReadinessGuard.evaluateContext({
            on_ground = n("airgroundsensor") == def.ON,
            powered = n("battery") == def.ON and n("mainbus") ~= def.OFF,
            preflight = P.flightstate == def.FLIGHTSTATEPREFLIGHT,
            slow = (n("groundspeed") or 0) < 45,
            no_main_procedure = idle(),
            before_taxi_done = beforeTaxi and beforeTaxi.set == true,
            before_takeoff_done = beforeTakeoff and beforeTakeoff.set == true,
            taxi_light_off = n("taxilight") == def.OFF,
            takeoff_context = beforeTakeoff and beforeTakeoff.set == true and
                (n("positionlights") == def.POSLIGHTSSTROBE or P.aircraftonrwy(def.DEPARTURE, 40, 20))
        })
        if not context.open then return false end
        local mismatch = false
        if kind == "trim" then
            local live = P.getTakeoffTrimAdviceTarget() or 0
            local latched = tonumber(P._ongoingTrimTargetLatched) or 0
            if (latched > 0 and latched or live) ~= target then return false end
            mismatch = target > 0 and not helpers.trimwheel_matches_trim_step(n("trimwheel") or 0, target, 0.25)
        elseif kind == "mcp_speed" then
            if P.getDepartureMcpSpeedTarget() ~= target or P.isDepartureMcpSpeedSelectionPending() then return false end
            mismatch = target > 0 and helpers.roundnumber(n("mcpspeed") or 0, 0) ~= target
        elseif kind == "mcp_heading" then
            if not helpers.isvalidicao(s("depicao")) or not helpers.isvalidrwy(s("deprwy")) then return false end
            local currentTarget = P.getDepartureRunwayHeadingMag()
            if not currentTarget or helpers.roundnumber(currentTarget) ~= target then return false end
            mismatch = helpers.roundnumber(n("mcpheading") or 0, 0) ~= target
        end
        return P.takeoffReadinessGuard.allowMismatch(context.mode, P.takeoffReadinessPostState, kind, signature, mismatch)
    end

    function P.conditionalCenterTankTarget()
        if not preOwner() or cfg(def.CONFIGAUTOCENTERTANKHANDLING) ~= def.ON or not P.enginesrunning(def.BOTH) then return nil end
        if (n("centertanklbs") or 0) > 1000 and (n("centertanklpress") or 0) > 0
            and (n("centertankrpress") or 0) > 0 and (n("centertankstat") or 0) > 0 then
            if n("centertanklswitch") == def.OFF or n("centertankrswitch") == def.OFF then return def.ON end
        elseif (n("centertanklbs") or 0) <= 1000 or
            (n("centertanklpress") == 0 and n("centertankrpress") == 0) then
            if n("centertanklswitch") == def.ON or n("centertankrswitch") == def.ON then return def.OFF end
        end
        return nil
    end

    function P.conditionalSpeedbrakesExtended()
        return (n("speedbrakelever") or 0) > def.SPEEDBRAKE_FORGOTTEN_LEVER_MIN
            or (n("speedbrakeratio") or 0) > def.SPEEDBRAKE_FORGOTTEN_RATIO_MIN
    end

    function P.getFlapsHandlingTarget(direction)
        local speed, target = n("airspeed") or 0, n("flapleverpos") or def.FLAPSUP
        if direction == "up" then
            if speed > (n("flapsupspeed") or 0) + 3 then return def.FLAPSUP end
            if speed > (n("flaps1speed") or 0) + 3 then return def.FLAPS1 end
            if speed > (n("flaps5speed") or 0) + 3 then return def.FLAPS5 end
            if speed > (n("flaps10speed") or 0) + 3 then return def.FLAPS10 end
            if speed > (n("flaps15speed") or 0) + 3 then return def.FLAPS15 end
            return target
        end
        if speed < (n("flapsupspeed") or 0) - 5 then target = def.FLAPS1 end
        if speed < (n("flaps1speed") or 0) - 5 then target = def.FLAPS5 end
        if speed < (n("flaps5speed") or 0) - 5 then target = def.FLAPS10 end
        if speed < (n("flaps10speed") or 0) - 5 then target = def.FLAPS15 end
        if speed < (n("flaps15speed") or 0) - 5 then target = def.FLAPS25 end
        if speed < (n("flaps25speed") or 0) - 5 then target = def.FLAPS30 end
        return target
    end

    function P.getGroundStartupAdvice()
        if not preflight() or not idle() then return nil end
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
        local beforeTaxiDone = (P.proceduretable[def.BEFORETAXIPROCEDURE] ~= nil) and P.proceduretable[def.BEFORETAXIPROCEDURE].set

        if battery == def.ON and posLights ~= nil and posLights ~= def.POSLIGHTSSTEADY and parkBrakeSet and (not beforeTaxiDone) then
            return "position_lights", "Set Position Lights Steady"
        elseif ((starter1 == def.GROUND or starter2 == def.GROUND)) and beaconLights == def.OFF then
            return "beacon", "Set Collision Lights On"
        elseif (apuStatus ~= nil and apuStatus > def.APUOFF and leftTankL == def.OFF) then
            return "apu_fuel_pump", "Set Left After Fuel Pump On for A P U"
        elseif ((starter1 == def.GROUND or starter2 == def.GROUND)) and (leftTankL == def.OFF or leftTankR == def.OFF or rightTankL == def.OFF or rightTankR == def.OFF) then
            return "wing_fuel_pumps", "Set Wing Tank Fuel Pumps On"
        elseif ((starter1 == def.GROUND or starter2 == def.GROUND)) and (packL ~= nil and packL ~= def.PACKOFF or packR ~= nil and packR ~= def.PACKOFF) then
            return "packs_off", "Set Both Packs Off"
        elseif ((starter1 == def.GROUND or starter2 == def.GROUND)) and apuBleed ~= nil and apuBleed ~= def.ON then
            return "apu_bleed_start", "Set A P U Bleed Air On"
        elseif starter2 == def.GROUND and isolValve ~= nil and isolValve ~= def.ISOLVALVEOPEN then
            return "isolation_start", "Set Isolation Valve Open"
        elseif starter1 == def.GROUND and eng1N2 ~= nil and eng1N2 > 25 and mixture1 == def.OFF then
            return "engine1_fuel", "Engine 1 N 2 at 25 Percent"
        elseif starter2 == def.GROUND and eng2N2 ~= nil and eng2N2 > 25 and mixture2 == def.OFF then
            return "engine2_fuel", "Engine 2 N 2 at 25 Percent"
        elseif apuStatus ~= nil and apuStatus == def.APUOFFBUS and gen1 == def.OFF and gen2 == def.OFF then -- Corrected gen1/gen2 check
            return "apu_generator_on", "Switch A P U Generator On"
        elseif (apuBleed == def.OFF and apuStatus ~= nil and apuStatus > def.APUSTARTED and enginesRunningBoth ~= nil and ((not enginesRunningBoth) or (enginesRunningBoth and bleed1 == def.OFF and bleed2 == def.OFF))) then
            return "apu_bleed_on", "Set A P U Bleedair On"
        elseif (isolValve ~= nil and isolValve ~= def.ISOLVALVEOPEN and apuStatus ~= nil and apuStatus > def.APUSTARTED and enginesRunningBoth ~= nil and not(enginesRunningBoth and bleed2 == def.ON)) then
            return "isolation_open", "Set Isolation Valve Open"
        elseif (apuBleed == def.ON and enginesRunningBoth and (bleed1 == def.ON or bleed2 == def.ON)) then
            return "apu_bleed_off", "Set A P U Bleedair Off"
        elseif (isolValve ~= nil and isolValve ~= def.ISOLVALVEAUTO and enginesRunningBoth and (bleed1 == def.ON or bleed2 == def.ON)) then
            return "isolation_auto", "Set Isolation Valve Auto"
        elseif normalBleedConfig and engineGenPowerReady and apuSupplyingPower then
            return "apu_generator_off", "Set A P U Generator Off"
        elseif normalBleedConfig and engineGenPowerReady and apuStatus ~= nil and apuStatus > def.APUOFF and not apuSupplyingPower then
            return "apu_off", "Set A P U Off"
        end
    end

    local guards = {}
    guards.center_tank = function(c) return P.conditionalCenterTankTarget() == c.target end
    guards.cabin_cruise_altitude = function(c)
        local target = n("fmccruisealt")
        return preOwner() and P.flightstate < def.FLIGHTSTATECRUISE and target and target ~= 0 and target ~= 20000
            and helpers.roundnumber(target / 500) * 500 == c.target and n("cabincruisealt") ~= c.target
    end
    guards.cabin_landing_altitude = function(c)
        if not preOwner() or P.flightstate >= def.FLIGHTSTATEAPPROACH or arrival() ~= c.arrival then return false end
        local elevation = P.getDestinationAirportElevationFt()
        if elevation == nil then return false end
        return math.max(0, helpers.roundnumber(elevation / 50) * 50) == c.target and n("cabinlandingalt") ~= c.target
    end
    guards.wipers = function()
        return cfg(def.CONFIGAUTOWIPER) == def.ON and (n("groundspeed") or 0) > 250
            and (n("lwiperpos") ~= def.WIPEROFF or n("rwiperpos") ~= def.WIPEROFF)
    end
    guards.ground_qnh = function(c)
        if not (preflight() and idle() and n("battery") == def.ON and n("mainbus") ~= def.OFF
            and n("taxilight") == def.OFF and cfg(def.CONFIGAUTOBARO) == def.ON and (n("groundspeed") or 0) < 45) then return false end
        local _, target = P.getlocalqnh(def.DEPARTURE, true)
        return target == c.target and n("baroinhpa") == c.units and not P.isbarolocalqnhset(target)
    end
    guards.tod_mcp_altitude = function(c)
        local tod, fmc, mcp = n("vnavtoddist"), n("fmccruisealt"), n("mcpaltitude")
        return cruise() and tod and tod > 0 and tod < 20 and fmc and fmc > 0 and fmc == c.target
            and P.pauseTodGuard.needsMcpDescentReset(mcp, fmc,
                P.pauseTodMcpAltAtPrompt or P.pauseTodAutoDisableMcpBaseline)
    end
    guards.arrival_setup = function(c)
        if not air() or arrival() ~= c.arrival or not P.fmsselectedapp or not isProperty(P.fmsselectedapp) then return false end
        local missing = not helpers.isvalidicao(s("desicao")) or not helpers.isvalidrwy(s("desrwy"))
            or helpers.normalizeRawSelectedApproachId(s("fmsselectedapp")) == nil
        return missing and P.arrivalSetupWarningActive == true and not P.isArrivalBelow1000Gate()
    end
    guards.drag_required = function()
        return air() and not P.isZiboSpeedbrakeAssistEnabled() and n("ziboDragRequiredUnhandled") == 1
            and not P.conditionalSpeedbrakesExtended()
    end
    guards.drag_no_longer_required = function()
        return air() and not P.isZiboSpeedbrakeAssistEnabled() and n("ziboDragRequired") == 0
            and P.conditionalSpeedbrakesExtended()
    end
    guards.speedbrake_forgotten = function()
        if not air() or P.isZiboSpeedbrakeAssistEnabled() or not P.conditionalSpeedbrakesExtended() then return false end
        local phase = n("fmsflightphase") or 0
        if P.flightstate ~= def.FLIGHTSTATECRUISE and P.flightstate ~= def.FLIGHTSTATEAPPROACH
            and phase ~= def.FMSFLIGHTPHASE_CRZ_DES and phase ~= def.FMSFLIGHTPHASE_DESCENT
            and phase ~= def.FMSFLIGHTPHASE_APPROACH then return false end
        local ra = n("radioaltitude") or 99999
        local urgent = ra >= 0 and ra < def.SPEEDBRAKE_FORGOTTEN_URGENT_RA_FT
        if not P.speedbrakeForgottenUseLatched and not urgent then return false end
        local altitude, mcp = n("altitude_ft") or 0, n("mcpaltitude") or 0
        return urgent or (ra >= 0 and ra < def.SPEEDBRAKE_FORGOTTEN_LOW_RA_FT)
            or (n("flapleverpos") or 0) > def.FLAPSUP or n("gearhandlepos") == def.GEARDOWN
            or (n("verticalspeed") or 0) > def.SPEEDBRAKE_FORGOTTEN_LEVEL_VS_FPM
            or (altitude > 0 and mcp > 0 and math.abs(altitude - mcp) <= def.SPEEDBRAKE_FORGOTTEN_ALT_CAPTURE_BAND_FT)
    end
    guards.taxi_speed = function()
        if n("airgroundsensor") ~= def.ON or (n("groundspeed") or 0) <= 45
            or P.isZiboRaasFeatureActive("taxiway_takeoff") then return false end
        return (P.flightstate == def.FLIGHTSTATEPREFLIGHT and not P.aircraftonrwy(def.DEPARTURE, 40, 20))
            or (P.flightstate == def.FLIGHTSTATETAXITOGATE and P.aircraftonrwy(def.ARRIVAL, 40, 20))
    end
    guards.climb_leveloff = function(c)
        return idle() and air() and P.flightstate == def.FLIGHTSTATECLIMB
            and math.abs((n("altitude") or 0) - cfg(def.CONFIGLOWEAIRSPACEALT)) < 100
            and n("fmccruisealt") == c.target and c.target > cfg(def.CONFIGLOWEAIRSPACEALT)
            and n("apvnavaltmode") == def.ON
    end
    guards.cruise_altitude = function(c)
        if cfg(def.CONFIGAUTOFUNCTIONS) ~= def.ON and cfg(def.CONFIGVOICEADVICEONLY) ~= def.ON then return false end
        local current, mcp, fmc, vs = n("altitude"), n("mcpaltitude"), n("fmccruisealt"), n("verticalspeed")
        local low, phase = cfg(def.CONFIGLOWEAIRSPACEALT), n("fmsflightphase") or 0
        if not (current and mcp and fmc and vs and low) then return false end
        fmc, mcp = helpers.roundnumber(fmc / 100, 0) * 100, helpers.roundnumber(mcp / 100, 0) * 100
        local climbCruise = P.flightstate == def.FLIGHTSTATECLIMB or P.flightstate == def.FLIGHTSTATECRUISE
            or phase == def.FMSFLIGHTPHASE_CLIMB or phase == def.FMSFLIGHTPHASE_CRUISE or phase == def.FMSFLIGHTPHASE_CRZ_CLB
        return air() and climbCruise and P.flightstate < def.FLIGHTSTATEAPPROACH and phase < def.FMSFLIGHTPHASE_CRZ_DES
            and fmc == c.target and mcp == c.mcp and fmc > low and mcp > low and current > low
            and fmc - mcp >= def.CRUISE_ALT_MISMATCH_MIN_GAP_FT
            and helpers.roundnumber(current / 100, 0) * 100 < fmc
            and math.abs(current - mcp) <= def.CRUISE_ALT_MISMATCH_LEVEL_BAND_FT
            and math.abs(vs) <= def.CRUISE_ALT_MISMATCH_MAX_VS_FPM
    end
    guards.anti_ice = function(c)
        local result = P.antiIceSpeechResult
        if not result or cfg(def.CONFIGAUTOANTIICE) ~= def.ON then return false end
        if c.system == "engine" then
            if not P.enginesrunning(def.BOTH) then return false end
            if result.engine_demand ~= c.demand or result.engine_reason ~= c.reason then return false end
            return c.demand == true and (n("eng1heatpos") == def.OFF or n("eng2heatpos") == def.OFF)
                or c.demand == false and (n("eng1heatpos") == def.ON or n("eng2heatpos") == def.ON)
        end
        return air() and result.wing_demand == c.demand and result.wing_reason == c.reason
            and (c.demand == true and n("wingheatpos") == def.OFF or c.demand == false and n("wingheatpos") == def.ON)
    end
    guards.wing_inhibit = function(c)
        local result = P.antiIceSpeechResult
        return air() and cfg(def.CONFIGAUTOANTIICE) == def.ON and result and result.wing_ice_inhibited == true
            and result.wing_inhibit_reason == c.reason
    end
    guards.flaps = function(c)
        if not air() or cfg(def.CONFIGAUTOFLAPS) ~= def.ON then return false end
        local phase = P.flightstate
        if c.direction == "up" and phase ~= def.FLIGHTSTATEINITIALCLIMB and phase ~= def.FLIGHTSTATECLIMB
            then return false end
        if c.direction == "up" and phase == def.FLIGHTSTATEINITIALCLIMB
            and ((n("radioaltitude") or 0) <= 200 or n("gearhandlepos") == def.GEARDOWN) then return false end
        if c.direction == "down" and phase ~= def.FLIGHTSTATEAPPROACH then return false end
        local target = P.getFlapsHandlingTarget(c.direction)
        local current = n("flapleverpos") or 0
        return target == c.target and (c.direction == "up" and current > target or c.direction == "down" and current < target)
    end
    guards.route = function(c)
        if not air() or P.conditionalRouteContext() ~= c.route or P.isArrivalBelow1000Gate() then return false end
        if P.arrivalSetupWarningActive then return false end
        local tod, phase = n("vnavtoddist"), n("fmsflightphase")
        if c.kind == "discontinuity" then
            if not tod or tod <= 0 or tod > c.limit or (n("fmccruisealt") or 0) <= 0 then return false end
            local options = helpers.withMissedApproachDiscontinuitySuppression({ maxAheadNm = 20 }, n("missedappwptidx"), n("missedappwptidx2"))
            local disco = helpers.detectFMSDiscontinuity(s("fmslegs"), get(P.fmslegslat), get(P.fmslegslon),
                get(P.aircraftlatpos), get(P.aircraftlonpos), options)
            return disco ~= nil and tostring(disco.previous or "") == c.previous
        end
        local remaining, _, onRoute = helpers.getRemainingRouteDistance(s("fmslegs"), get(P.fmslegslat), get(P.fmslegslon),
            get(P.aircraftlatpos), get(P.aircraftlonpos))
        local distance = n("distdest")
        if c.kind == "early" then
            local eligible = cruise() or (P.flightstate == def.FLIGHTSTATEAPPROACH
                and (phase == def.FMSFLIGHTPHASE_DESCENT or phase == def.FMSFLIGHTPHASE_APPROACH)
                and (n("radioaltitude") or 0) > def.ROUTE_ENDS_EARLY_APPROACH_MIN_RA_FT)
            return eligible and tod and tod <= 0 and onRoute == true and remaining and remaining > 0
                and distance and distance > 0 and distance - remaining > def.ROUTE_ENDS_EARLY_DIFF_NM
        end
        return P.routeWarningGuard.evaluatePositiveTodSample({
            eligible = cruise(), tod_distance_nm = tod, destination_distance_nm = distance,
            remaining_distance_nm = remaining, on_route = onRoute == true,
            previous_tod_distance_nm = P.routeEndsBeforeTodLastTod,
            previous_destination_distance_nm = P.routeEndsBeforeTodLastDistDest,
            previous_reference_distance_nm = P.routeEndsBeforeTodLastReference,
            warning_diff_nm = def.ROUTE_ENDS_BEFORE_TOD_DIFF_NM, reset_diff_nm = def.ROUTE_ENDS_BEFORE_TOD_RESET_DIFF_NM,
            max_rise_nm = def.ROUTE_ENDS_BEFORE_TOD_MAX_RISE_NM
        }).status == "candidate"
    end
    guards.ground_start = function(c)
        local key = P.getGroundStartupAdvice()
        return key == c.action
    end

    function P.queueOngoingAdvice(name, text, context, key, mode)
        context = context or {}
        context.departure = context.departure or departure()
        context.arrival = context.arrival or arrival()
        return P.queueConditionalSpeech(key or "advice:" .. name, text, function()
            return (cfg(def.CONFIGAUTOFUNCTIONS) == def.ON or cfg(def.CONFIGVOICEADVICEONLY) == def.ON)
                and guards[name] and guards[name](context) == true
        end, mode or "voice")
    end
end

return M
