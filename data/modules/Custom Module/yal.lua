local P = {}
yal = P

local def = require("definitions")
require("settings")
local VR = require("voicereadback")

--------------------------------------------------------------------------------------------------------------

local menu_master = sasl.appendMenuItem(PLUGINS_MENU_ID, def.APPNAMEPREFIXLONG)
P.menu_main = sasl.createMenu("", PLUGINS_MENU_ID, menu_master)

--------------------------------------------------------------------------------------------------------------
-- Flags & Global Variables

function P.YalinitGlobal()

    P.needstempinit = true

    P.aircraftwasonground = false

    P.updatemetartimer = nil

    P.altitudetimer = nil

    P.pausetodtimer = nil

    P.savetimer = nil

    P.flightstate = 0

    P.xluaLoggingEnabled = nil

    P.centertankoffset = false

    P.depmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}
    P.desmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}

    P.todDiscontinuityWarned30 = false
    P.todDiscontinuityWarned10 = false
    P.routeEndsEarlyWarned = false


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

    P.ongoingtaskstepindex = 1

    P.procedurelooptemplate = {
        lock = def.NOPROCEDURE,
        stepindex = 0,
        currentStepName = "",
        steprepeat = false,
        lastActiveTime = 0,
        procedureabort = false,
        procedureskipstep = false,
        procedurenotpossible = false,
        triggeredmanually = false,
        setonabort = false,
        lastStepName = "",
        skipConfirmForStep = nil
    }

    P.procedureloop1 = helpers.shallowcopy(P.procedurelooptemplate)
    P.procedureloop2 = helpers.shallowcopy(P.procedurelooptemplate)
    P.procedureloop3 = helpers.shallowcopy(P.procedurelooptemplate)

    P.loopenginekeys = {}
    sasl.logInfo("Building engine key ignore-list from template...")
    for key, _ in pairs(P.procedurelooptemplate) do
        P.loopenginekeys[key] = true
        sasl.logInfo("... Added engine key: " .. key)
    end

    P.lastExecutedLoopIndex = 0

    P.loopStateTables = {P.procedureloop1, P.procedureloop2, P.procedureloop3}

    P.previousview = -1

    P.XCameraIsInstalled()
    P.YANSHisinstalled()
    P.BPBisinstalled()

end

--------------------------------------------------------------------------------------------------------------
-- Datarefs

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
        sasl.logInfo("Dataref '" .. debug_dataref_path .. "' not found. Creating it now.")
        local default_level = LOG_INFO
        P.debugLevelDataref = createGlobalPropertyi(debug_dataref_path, default_level, false, true, true)
        set(P.debugLevelDataref, default_level)

    else
        sasl.logInfo("Found existing dataref: '" .. debug_dataref_path .. "'")
        P.debugLevelDataref = handle
    end

    sasl.logInfo("Restoring Debug Log Level from dataref...")
    local stored_level = get(P.debugLevelDataref)

    if (stored_level ~= LOG_INFO) and (stored_level ~= LOG_DEBUG) then
         sasl.logWarning("Invalid debug level in dataref (" .. stored_level .. "). Resetting to INFO.")
         stored_level = LOG_INFO
         set(P.debugLevelDataref, stored_level)
    end

    sasl.setLogLevel(stored_level)
    P.lastPolledDebugLevel = stored_level
    sasl.logInfo("Debug Log Level set to: " .. stored_level)
    if P.xluaLoggingEnabled then
        set(P.xluaLoggingEnabled, stored_level == LOG_DEBUG and 1 or 0)
    end

    local dataref_path = def.APPNAMEPREFIX .. "/state/procedureset"
    local handle = globalProperty(dataref_path)
    local maxId = 0
    for id, _ in pairs(P.proceduretable) do
        if id > maxId then maxId = id end
    end
    local expectedSize = maxId

    if not isProperty(handle) then
        sasl.logInfo("Dataref '" .. dataref_path .. "' not found. Creating it now.")
        P.ProcSetStatusarraydr = createGlobalPropertyia(dataref_path, expectedSize, false, true, true)
    else
        sasl.logInfo("Found existing dataref: '" .. dataref_path .. "'")
        P.ProcSetStatusarraydr = handle

        local currentSize = expectedSize
        if P.ProcSetStatusarraydr and P.ProcSetStatusarraydr.size then
            local ok, sizeValue = pcall(function() return P.ProcSetStatusarraydr:size() end)
            if ok and type(sizeValue) == "number" then
                currentSize = sizeValue
            end
        end

        if currentSize < expectedSize then
            sasl.logInfo("Expanding '" .. dataref_path .. "' from " .. tostring(currentSize) .. " to " .. tostring(expectedSize) .. " entries.")
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
                sasl.logInfo("Recreating '" .. dataref_path .. "' to ensure expanded size.")
                P.ProcSetStatusarraydr = createGlobalPropertyia(dataref_path, migratedValues, false, true, true)
            end
        elseif currentSize > expectedSize then
            sasl.logWarning("Dataref '" .. dataref_path .. "' has unexpected size " .. tostring(currentSize) .. " (expected " .. tostring(expectedSize) .. "). Extra entries will be ignored.")
        end
    end
    sasl.logInfo("Restoring procedure '.set' status from dataref array...")
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
                sasl.logInfo("Dataref '" .. path .. "' not found. Creating it now.")
                if prop.type == "int" then
                    handle = createGlobalPropertyi(path, prop.default, false, true, true)
                else -- string
                    handle = createGlobalPropertys(path, prop.default, false, true, true)
                end
            else
                sasl.logInfo("Found existing dataref: '" .. path .. "'")
            end

            P.LoopHandles[i][prop.name] = handle
        end
    end
    -- Lade die Zustände mit der neuen Funktion
    P.procedureloop1 = P.loadLoopState(1)
    P.procedureloop2 = P.loadLoopState(2)
    P.procedureloop3 = P.loadLoopState(3)
    P.loopStateTables = { P.procedureloop1, P.procedureloop2, P.procedureloop3 }

    sasl.logInfo("Procedure loop states restored from datarefs.")

    local path = def.APPNAMEPREFIX .. "/state/ongoingtaskstepindex"
    local handle = globalProperty(path)
    if not isProperty(handle) then
        sasl.logInfo("Dataref '" .. path .. "' not found. Creating it now.")
        P.OngoingTaskIndexdr = createGlobalPropertyi(path, 1, false, true, true)
    else
        sasl.logInfo("Found existing dataref: '" .. path .. "'")
        P.OngoingTaskIndexdr = handle
    end
    P.ongoingtaskstepindex = get(P.OngoingTaskIndexdr)
    if P.ongoingtaskstepindex == 0 then
        P.ongoingtaskstepindex = 1
    end
    sasl.logInfo("Ongoing task index restored to: " .. P.ongoingtaskstepindex)

    local path = def.APPNAMEPREFIX .. "/state/flightstate"
    local handle = globalProperty(path)
    if not isProperty(handle) then
        sasl.logInfo("Dataref '" .. path .. "' not found. Creating it now.")
        P.flightstatedr = createGlobalPropertyi(path, 0, false, true, true)
    else
        sasl.logInfo("Found existing dataref: '" .. path .. "'")
        P.flightstatedr = handle
        P.isReloadWithinSession = true
    end
    P.flightstate = get(P.flightstatedr)
    sasl.logInfo("Flightstate restored to: " .. P.flightstate)

    P.simpaused = globalProperty("sim/time/paused")
    P.simfreezed = globalPropertyfae("sim/operation/override/override_planepath", 1)
    P.battery = globalProperty("laminar/B738/electric/battery_pos")
    P.batteryswitchcover = globalPropertyfae("laminar/B738/cover", 3)
    P.emergencylights = globalProperty("laminar/B738/toggle_switch/emer_exit_lights")
    P.emergencylightcover = globalPropertyfae("laminar/B738/cover", 10)

    P.apgoaround = globalProperty("laminar/B738/autopilot/ap_goaround")

    P.localpositionx = globalProperty("sim/flightmodel/position/local_x")
    P.localpositiony = globalProperty("sim/flightmodel/position/local_y")
    P.localpositionz = globalProperty("sim/flightmodel/position/local_z")
    P.localpositionpsi = globalProperty("sim/flightmodel/position/psi")

    P.fueltank1 = globalProperty("sim/flightmodel/weight/m_fuel1")
    P.fueltank2 = globalProperty("sim/flightmodel/weight/m_fuel2")
    P.fueltank3 = globalProperty("sim/flightmodel/weight/m_fuel3")

    P.mastercautionannunc = globalProperty("sim/cockpit/warnings/annunciators/master_caution")

    P.mainbus = globalProperty("laminar/B738/electric/main_bus")
    P.parkingbrakepos = globalProperty("laminar/B738/parking_brake_pos")

    P.pausetod = globalProperty("laminar/B738/fms/pause_td")

    P.vnavtoddist = globalProperty("laminar/B738/fms/vnav_td_dist")
    P.distdest = globalProperty("laminar/B738/FMS/dist_dest")
    P.vnavtocdist = globalProperty("laminar/B738/fms/vnav_tc_dist")


    P.hidecptefb = globalProperty("laminar/B738/tab/static")
    P.hidefoefb = globalProperty("laminar/B738/tab/fo_static")

    P.chockstatus = globalProperty("laminar/B738/fms/chock_status")

    P.wakeoverride = globalProperty("sim/operation/override/override_wake_turbulence")

    P.aponstat = globalProperty("laminar/autopilot/ap_on")
    P.apdiscpos = globalProperty("laminar/B738/autopilot/disconnect_pos")

    P.apcmdastat = globalProperty("laminar/B738/autopilot/cmd_a_status")
    P.apcmdbstat = globalProperty("laminar/B738/autopilot/cmd_b_status")

    P.apvnavstat = globalProperty("laminar/B738/autopilot/vnav_status1")
    P.aplnavstat = globalProperty("laminar/B738/autopilot/lnav_status")
    P.apappstat = globalProperty("laminar/B738/autopilot/app_status")
    P.apvorlocstat = globalProperty("laminar/B738/autopilot/vorloc_status")
    P.apalthldstat = globalProperty("laminar/B738/autopilot/alt_hld_status")
    P.aphdgselstat = globalProperty("laminar/B738/autopilot/hdg_sel_status")
    P.apvsstat = globalProperty("laminar/B738/autopilot/vs_status")
    P.aplvlchgstat = globalProperty("laminar/B738/autopilot/lvl_chg_status")
    P.apvnavaltmode = globalProperty("laminar/B738/autopilot/vnav_alt_mode")

    P.mmrinstalled = globalProperty("laminar/B738/fms/mmr")
    P.lpvinstalled = globalProperty("laminar/B738/lpv_install")
    P.mmrcptactmode = globalProperty("laminar/B738/mmr/cpt/act_mode")
    P.mmrcptactvalue = globalProperty("laminar/B738/mmr/cpt/act_value")
    P.mmrcptstdbymode = globalProperty("laminar/B738/mmr/cpt/stby_mode")
    P.mmrfoactmode = globalProperty("laminar/B738/mmr/fo/act_mode")
    P.mmrfoactvalue = globalProperty("laminar/B738/mmr/fo/act_value")
    P.mmrfostdbymode = globalProperty("laminar/B738/mmr/fo/stby_mode")

    P.apgscapturedstat = globalPropertyfae("laminar/B738/ap/glideslope_status", 1)
    P.aploccapturedstat = globalPropertyfae("laminar/B738/ap/approach_status", 1)
    P.aprolloutstat = globalPropertyfae("laminar/B738/ap/rollout_status", 1)
    P.apflarestat = globalPropertyfae("laminar/B738/ap/flare_status", 1)

    P.aplpvgscapturedstat = globalPropertyfae("laminar/B738/ap/lpv_gs_status", 1)
    P.aplpvloccapturedstat = globalPropertyfae("laminar/B738/ap/lpv_app_status", 1)

    P.apglsgscapturedstat = globalPropertyfae("laminar/B738/ap/gls_gs_status", 1)
    P.apglsloccapturedstat = globalPropertyfae("laminar/B738/ap/gls_app_status", 1)

    P.apfacgscapturedstat = globalPropertyfae("laminar/B738/ap/gp_status", 1)
    P.apfacloccapturedstat = globalPropertyfae("laminar/B738/ap/fac_status", 1)

    P.aphdgmode = globalProperty("laminar/B738/autopilot/heading_mode")
    P.apaltmode = globalProperty("laminar/B738/autopilot/altitude_mode")

    P.atarmpos = globalProperty("laminar/B738/autopilot/autothrottle_arm_pos")
    P.atn1stat = globalProperty("laminar/B738/autopilot/n1_status")
    P.atspeedstat = globalProperty("laminar/B738/autopilot/speed_status1")
    P.atspeedintvstat = globalProperty("laminar/B738/autopilot/spd_interv_status")
    P.atn1mode = globalProperty("laminar/B738/FMS/N1_mode")
    P.atn1modetoselection = globalProperty("laminar/B738/FMS/N1_mode_to_sel")
    P.atthrottlelock = globalProperty("laminar/B738/autopilot/lock_throttle")

    P.atspeedmode = globalProperty("laminar/B738/autopilot/speed_mode")

    P.gearhandlepos = globalProperty("laminar/B738/controls/gear_handle_down")
    P.lgeardeployed = globalPropertyfae("sim/aircraft/parts/acf_gear_deploy", 1)
    P.ngeardeployed = globalPropertyfae("sim/aircraft/parts/acf_gear_deploy", 2)
    P.rgeardeployed = globalPropertyfae("sim/aircraft/parts/acf_gear_deploy", 3)

    P.altitude = globalProperty("laminar/B738/autopilot/altitude")
    P.fmccruisealt = globalProperty("laminar/B738/autopilot/fmc_cruise_alt")
    P.radioaltitude = globalProperty("sim/cockpit2/gauges/indicators/radio_altimeter_height_ft_pilot")

    P.groundtrackmag = globalProperty("sim/cockpit2/gauges/indicators/ground_track_mag_pilot")

    P.trimwheel = globalProperty("laminar/B738/flt_ctrls/trim_wheel")
    P.trimcalc = globalProperty("laminar/B738/FMS/trim_calc")

    P.gpuavailable = globalProperty("laminar/B738/gpu_available")
    P.jetwaypoweravailable = globalProperty("laminar/B738/jetway_power")
    P.autogategpu = globalProperty("laminar/B738/autogate_gpu")
    P.gpuon = globalProperty("sim/cockpit/electrical/gpu_on")

    P.apustarterpos = globalProperty("laminar/B738/spring_toggle_switch/APU_start_pos")
    P.apupsi = globalProperty("laminar/B738/air/apu_psi")
    P.apugenoffbus = globalProperty("laminar/B738/annunciator/apu_gen_off_bus")
    P.apupowerbus1 = globalProperty("laminar/B738/electrical/apu_power_bus1")
    P.apupowerbus2 = globalProperty("laminar/B738/electrical/apu_power_bus2")

    P.announcsourceoff1 = globalProperty("laminar/B738/annunciator/source_off1")
    P.announcsourceoff2 = globalProperty("laminar/B738/annunciator/source_off2")

    P.gen1pos = globalPropertyiae("sim/cockpit/electrical/generator_on", 1)
    P.gen2pos = globalPropertyiae("sim/cockpit/electrical/generator_on", 2)

    P.bleedair1pos = globalProperty("laminar/B738/toggle_switch/bleed_air_1_pos")
    P.bleedair2pos = globalProperty("laminar/B738/toggle_switch/bleed_air_2_pos")
    P.bleedairapupos = globalProperty("laminar/B738/toggle_switch/bleed_air_apu_pos")
    P.isolvalvepos = globalProperty("laminar/B738/air/isolation_valve_pos")
    P.packlpos = globalProperty("laminar/B738/air/l_pack_pos")
    P.packrpos = globalProperty("laminar/B738/air/r_pack_pos")
    P.trimairpos = globalProperty("laminar/B738/air/trim_air_pos")
    P.lrecircfanpos = globalProperty("laminar/B738/air/l_recirc_fan_pos")
    P.rrecircfanpos = globalProperty("laminar/B738/air/r_recirc_fan_pos")

    P.starterauto = globalProperty("laminar/B738/engine_start_auto")
    P.starter1pos = globalProperty("laminar/B738/engine/starter1_pos")
    P.starter2pos = globalProperty("laminar/B738/engine/starter2_pos")

    P.mixture1pos = globalProperty("laminar/B738/engine/mixture_ratio1")
    P.mixture2pos = globalProperty("laminar/B738/engine/mixture_ratio2")

    P.reverser1pos = globalProperty("laminar/B738/flt_ctrls/reverse_lever1")
    P.reverser2pos = globalProperty("laminar/B738/flt_ctrls/reverse_lever2")

    P.totalfuellbs = globalProperty("laminar/B738/fuel/total_tank_lbs")
    P.totalfuelkgs = globalProperty("laminar/B738/fuel/total_tank_kgs")
    P.fuelunit = globalProperty("laminar/B738/FMS/fmc_units")

    P.totalweightkgs = globalProperty("sim/flightmodel/weight/m_total")

    P.centertanklbs = globalProperty("laminar/B738/fuel/center_tank_lbs")
    P.centertanklpress = globalProperty("laminar/B738/system/fuel_press_c1")
    P.centertankrpress = globalProperty("laminar/B738/system/fuel_press_c2")
    P.centertanklswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_ctr1")
    P.centertankrswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_ctr2")
    P.centertankstat = globalProperty("laminar/B738/fuel/center_status")
    P.lefttanklbs = globalProperty("laminar/B738/fuel/left_tank_lbs")
    P.lefttanklswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_lft1")
    P.lefttankrswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_lft2")
    P.righttanklbs = globalProperty("laminar/B738/fuel/right_tank_lbs")
    P.righttanklswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_rgt2")
    P.righttankrswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_rgt1")

    P.eng1n1ratio = globalProperty("laminar/B738/FMS/eng1_N1_ratio")
    P.eng2n1ratio = globalProperty("laminar/B738/FMS/eng2_N1_ratio")
    P.eng1n1percent = globalPropertyfae("sim/flightmodel2/engines/N1_percent", 1)
    P.eng2n1percent = globalPropertyfae("sim/flightmodel2/engines/N1_percent", 2)
    P.eng1n2percent = globalPropertyfae("sim/flightmodel2/engines/N2_percent", 1)
    P.eng2n2percent = globalPropertyfae("sim/flightmodel2/engines/N2_percent", 2)

    P.eng1heatpos = globalProperty("laminar/B738/ice/eng1_heat_pos")
    P.eng2heatpos = globalProperty("laminar/B738/ice/eng2_heat_pos")
    P.wingheatpos = globalProperty("laminar/B738/ice/wing_heat_pos")

    P.hydro1pos = globalProperty("laminar/B738/toggle_switch/hydro_pumps1_pos")
    P.hydro2pos = globalProperty("laminar/B738/toggle_switch/hydro_pumps2_pos")
    P.elechydro1pos = globalProperty("laminar/B738/toggle_switch/electric_hydro_pumps1_pos")
    P.elechydro2pos = globalProperty("laminar/B738/toggle_switch/electric_hydro_pumps2_pos")

    P.airgroundsensor = globalProperty("laminar/B738/air_ground_sensor")
    P.autobrakepos = globalProperty("laminar/B738/autobrake/autobrake_pos")
    P.autobrakedisarm = globalProperty("laminar/B738/autobrake/autobrake_disarm")

    P.fmsflightphase = globalProperty("laminar/B738/FMS/flight_phase")

    P.fmctransalt = globalProperty("laminar/B738/FMS/fmc_trans_alt")
    P.fmctranslvl = globalProperty("laminar/B738/FMS/fmc_trans_lvl")

    P.bankanglepos = globalProperty("laminar/B738/autopilot/bank_angle_pos")

    P.baropilot = globalProperty("laminar/B738/EFIS/baro_sel_in_hg_pilot")
    P.barostd = globalProperty("laminar/B738/EFIS/baro_set_std_pilot")
    P.baroinhpa = globalProperty("laminar/B738/EFIS_control/capt/baro_in_hpa")
    P.baroregionpas = globalProperty("sim/weather/region/qnh_pas")

    P.frameice = globalProperty("sim/flightmodel/failures/frm_ice")
    P.tatdegc = globalProperty("laminar/B738/systems/temperature/tat_degc")

    P.cabincruisealt = globalProperty("sim/cockpit/pressure/max_allowable_altitude")
    P.cabinlandingalt = globalProperty("laminar/B738/pressurization/knobs/landing_alt")
    P.missedappalt = globalProperty("laminar/B738/fms/missed_app_alt")

    P.llightson = globalProperty("sim/cockpit/electrical/landing_lights_on")
    P.llights1 = globalPropertyfae("sim/cockpit2/switches/landing_lights_switch", 1)
    P.llights2 = globalPropertyfae("sim/cockpit2/switches/landing_lights_switch", 2)
    P.llights3 = globalPropertyfae("sim/cockpit2/switches/landing_lights_switch", 3)
    P.llights4 = globalPropertyfae("sim/cockpit2/switches/landing_lights_switch", 4)
    P.ledlightsvariant = globalProperty("laminar/B738/led_lights")

    P.taxilight = globalProperty("laminar/B738/toggle_switch/taxi_light_brightness_pos")
    P.positionlights = globalProperty("laminar/B738/toggle_switch/position_light_pos")
    P.beaconlights = globalProperty("sim/cockpit/electrical/beacon_lights_on")
    P.rwylightl = globalProperty("laminar/B738/toggle_switch/rwy_light_left")
    P.rwylightr = globalProperty("laminar/B738/toggle_switch/rwy_light_right")
    P.logolighton = globalProperty("laminar/B738/toggle_switch/logo_light")

    P.transponderpos = globalProperty("laminar/B738/knob/transponder_pos")
    P.transpondercode = globalProperty("sim/cockpit/radios/transponder_code")

    P.fdpilotpos = globalProperty("laminar/B738/autopilot/flight_director_pos")
    P.fdfopos = globalProperty("laminar/B738/autopilot/flight_director_fo_pos")

    P.efiswxpilotpos = globalProperty("laminar/B738/EFIS/EFIS_wx_on")
    P.efiswxfopos = globalProperty("laminar/B738/EFIS/fo/EFIS_wx_on")
    P.efisterrpilotpos = globalProperty("laminar/B738/EFIS_control/capt/terr_on")
    P.efisterrfopos = globalProperty("laminar/B738/EFIS_control/fo/terr_on")
    P.efisfixpilotpos = globalProperty("laminar/B738/EFIS/EFIS_fix_on")
    P.efisfixfopos = globalProperty("laminar/B738/EFIS/fo/EFIS_fix_on")
    P.efisdatapilotpos = globalProperty("laminar/B738/EFIS/capt/data_status")
    P.efisdatafopos = globalProperty("laminar/B738/EFIS/fo/data_status")
    P.efisairportpilotpos = globalProperty("laminar/B738/EFIS/EFIS_airport_on")
    P.efisairportfopos = globalProperty("laminar/B738/EFIS/fo/EFIS_airport_on")
    P.efispospilotpos = globalProperty("laminar/B738/pfd/gps1_pos_show")
    P.efisposfopos = globalProperty("laminar/B738/pfd/gps1_pos_fo_show")
    P.efisvorpilotpos = globalProperty("laminar/B738/EFIS/EFIS_vor_on")
    P.efisvorfopos = globalProperty("laminar/B738/EFIS/fo/EFIS_vor_on")

    P.n1setsource = globalProperty("laminar/B738/toggle_switch/n1_set_source")

    P.dhpilot = globalProperty("laminar/B738/pfd/dh_pilot")

    P.elevation = globalProperty("sim/flightmodel/position/elevation")

    P.depicao = globalProperty("laminar/B738/fms/ref_icao")
    P.deprwyheading = globalProperty("laminar/B738/fms/ref_runway_crs_mod")
    P.deprwylen = globalProperty("laminar/B738/fms/ref_runway_len")
    P.deprwylatstartpos = globalProperty("laminar/B738/fms/ref_runway_start_lat_mod")
    P.deprwylonstartpos = globalProperty("laminar/B738/fms/ref_runway_start_lon_mod")
    P.deprwylatendpos = globalProperty("laminar/B738/fms/ref_runway_end_lat_mod")
    P.deprwylonendpos = globalProperty("laminar/B738/fms/ref_runway_end_lon_mod")
    P.deprwy = globalProperty("laminar/B738/fms/ref_runway")

    P.desicao = globalProperty("laminar/B738/fms/dest_icao")
    P.desrwyheading = globalProperty("laminar/B738/fms/dest_runway_crs")
    P.desrwylatstartpos = globalProperty("laminar/B738/fms/dest_runway_start_lat_mod")
    P.desrwylonstartpos = globalProperty("laminar/B738/fms/dest_runway_start_lon_mod")
    P.desrwylatendpos = globalProperty("laminar/B738/fms/dest_runway_end_lat_mod")
    P.desrwylonendpos = globalProperty("laminar/B738/fms/dest_runway_end_lon_mod")
    P.desrwyalt = globalProperty("laminar/B738/pfd/des_rwy_altitude")
    P.desrwylen = globalProperty("laminar/B738/fms/dest_runway_len")
    P.desrwy = globalProperty("laminar/B738/fms/dest_runway")
 
    P.nearesticao = globalProperty("laminar/B738/near_apt_icao")

    P.fmslegs = globalProperty("laminar/B738/fms/legs")
    P.fmslegslat = globalProperty("laminar/B738/fms/legs_lat")
    P.fmslegslon = globalProperty("laminar/B738/fms/legs_lon")

    P.aircraftlatpos = globalPropertyfae("laminar/B738/latlon", 23)
    P.aircraftlonpos = globalPropertyfae("laminar/B738/latlon", 24)

    P.sunpitchdegrees = globalProperty("sim/graphics/scenery/sun_pitch_degrees")

    P.flapleverpos = globalProperty("laminar/B738/flt_ctrls/flap_lever")
    P.speedbrakelever = globalProperty("laminar/B738/flt_ctrls/speedbrake_lever")

    P.flapsupspeed = globalProperty("laminar/B738/pfd/flaps_up")
    P.flaps1speed = globalProperty("laminar/B738/pfd/flaps_1")
    P.flaps2speed = globalProperty("laminar/B738/pfd/flaps_2")
    P.flaps5speed = globalProperty("laminar/B738/pfd/flaps_5")
    P.flaps10speed = globalProperty("laminar/B738/pfd/flaps_10")
    P.flaps15speed = globalProperty("laminar/B738/pfd/flaps_15")
    P.flaps25speed = globalProperty("laminar/B738/pfd/flaps_25")

    P.toflaps = globalProperty("laminar/B738/FMS/takeoff_flaps")
    P.toflapsset = globalProperty("laminar/B738/FMS/takeoff_flaps_set")
    P.appflaps = globalProperty("laminar/B738/FMS/approach_flaps")
    P.appflapsset = globalProperty("laminar/B738/FMS/approach_flaps_set")

    P.airspeed = globalProperty("laminar/B738/autopilot/airspeed")
    P.groundspeed = globalProperty("laminar/b738/fmodpack/real_groundspeed")
    P.tirespeed = globalProperty("laminar/B738/systems/tire_speed0")
    P.verticalspeed = globalPropertyfae("sim/cockpit2/tcas/targets/position/vertical_speed", 1)

    P.v1speed = globalProperty("laminar/B738/FMS/v1")
    P.v2speed = globalProperty("laminar/B738/FMS/v2")
    P.vrspeed = globalProperty("laminar/B738/FMS/vr")

    P.v1setspeed = globalProperty("laminar/B738/FMS/v1_set")
    P.v2setspeed = globalProperty("laminar/B738/FMS/v2_set")
    P.vrsetspeed = globalProperty("laminar/B738/FMS/vr_set")

    P.fmccg = globalProperty("laminar/B738/FMS/fmc_cg")
    P.tabcg = globalProperty("laminar/B738/tab/cg_pos")
    P.calctakeoffcg = globalProperty("laminar/B738/fms/calc_to_cg")

    P.speedrestr = globalProperty("laminar/B738/autopilot/fmc_descent_r_speed1")

    P.vref = globalProperty("laminar/B738/FMS/vref")
    P.vref15 = globalProperty("laminar/B738/FMS/vref_15")
    P.vref25 = globalProperty("laminar/B738/FMS/vref_25")
    P.vref30 = globalProperty("laminar/B738/FMS/vref_30")
    P.vref40 = globalProperty("laminar/B738/FMS/vref_40")
    P.vrefapproachwindcorr = globalProperty("laminar/B738/FMS/approach_wind_corr")
    P.fmclandinggw = globalProperty("laminar/B738/FMS/fmc_gw_app")
    P.fmctakeoffgw = globalProperty("laminar/B738/FMS/fmc_gw")
    P.fmcseltemp = globalProperty("laminar/B738/FMS/fmc_sel_temp")
    P.fmcoattemp = globalProperty("laminar/B738/FMS/fmc_oat_temp")
    P.b737variant = globalProperty("zibomod/b737_variant")
    P.runwaywinddir = globalProperty("laminar/B738/fms/rw_wind_dir")
    P.runwaywindspd = globalProperty("laminar/B738/fms/rw_wind_spd")
    P.runwayslope = globalProperty("laminar/B738/fms/rw_slope")
    P.runwayheadingfmc = globalProperty("laminar/B738/fms/rw_hdg")
    P.fueltemp = globalProperty("laminar/B738/engine/fuel_temp_real")

    P.rain = globalProperty("sim/weather/view/rain_ratio")

    P.lwiperpos = globalProperty("laminar/B738/switches/left_wiper_pos")
    P.rwiperpos = globalProperty("laminar/B738/switches/right_wiper_pos")

    P.mfdsyspos = globalProperty("laminar/B738/buttons/mfd_sys_pos")
    P.lowerdupage = globalProperty("laminar/B738/systems/lowerDU_page")
    P.lowerdupage2 = globalProperty("laminar/B738/systems/lowerDU_page2")

    P.nav1freq = globalProperty("sim/cockpit/radios/nav1_freq_hz")
    P.nav1stdbyfreq = globalProperty("sim/cockpit/radios/nav1_stdby_freq_hz")
    P.nav2freq = globalProperty("sim/cockpit/radios/nav2_freq_hz")
    P.nav2stdbyfreq = globalProperty("sim/cockpit/radios/nav2_stdby_freq_hz")
    P.mcppilotcourse = globalProperty("laminar/B738/autopilot/course_pilot")
    P.mcpcopilotcourse = globalProperty("laminar/B738/autopilot/course_copilot")
    P.mcpheading = globalProperty("laminar/B738/autopilot/mcp_hdg_dial")
    P.mcpspeed = globalProperty("laminar/B738/autopilot/mcp_speed_dial_kts_mach")
    P.mcpaltitude = globalProperty("laminar/B738/autopilot/mcp_alt_dial")
    P.mcpvsspeed = globalProperty("sim/cockpit/autopilot/vertical_velocity")

    P.domelightpos = globalProperty("laminar/B738/toggle_switch/cockpit_dome_pos")

    P.seatbeltsignpos = globalProperty("laminar/B738/toggle_switch/seatbelt_sign_pos")
    P.nosmokingsignpos = globalProperty("laminar/B738/toggle_switch/no_smoking_pos")

    P.brightmainpanel = globalPropertyfae("laminar/B738/electric/panel_brightness", 1)
    P.brightcopilotmainpanel = globalPropertyfae("laminar/B738/electric/panel_brightness", 2)
    P.brightoverhead = globalPropertyfae("laminar/B738/electric/panel_brightness", 3)
    P.brightpedestral = globalPropertyfae("laminar/B738/electric/panel_brightness", 4)

    P.genbrightbackground = globalPropertyfae("laminar/B738/electric/generic_brightness", 7)
    P.genbrightafdsflood = globalPropertyfae("laminar/B738/electric/generic_brightness", 8)
    P.genbrightpedestralflood = globalPropertyfae("laminar/B738/electric/generic_brightness", 9)

    P.instrbrightoutbddu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 1)
    P.instrbrightcopilotoutbddu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 2)
    P.instrbrightinbddu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 3)
    P.instrbrightcopilotinbddu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 4)
    P.instrbrightupperdu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 5)
    P.instrbrightlowdu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 6)
    P.instrbrightinbdduS = globalPropertyfae("laminar/B738/electric/instrument_brightness", 25)
    P.instrbrightlowduS = globalPropertyfae("laminar/B738/electric/instrument_brightness", 26)
    P.instrbrightcopilotinbdduS = globalPropertyfae("laminar/B738/electric/instrument_brightness", 27)

    P.captainprobepos = globalProperty("laminar/B738/toggle_switch/capt_probes_pos")
    P.foprobepos = globalProperty("laminar/B738/toggle_switch/fo_probes_pos")
    P.wheatlfwdpos = globalProperty("laminar/B738/ice/window_heat_l_fwd_pos")
    P.wheatrfwdpos = globalProperty("laminar/B738/ice/window_heat_r_fwd_pos")
    P.wheatlsidepos = globalProperty("laminar/B738/ice/window_heat_l_side_pos")
    P.wheatrsidepos = globalProperty("laminar/B738/ice/window_heat_r_side_pos")

    P.irsleftpos = globalProperty("laminar/B738/toggle_switch/irs_left")
    P.irsrightpos = globalProperty("laminar/B738/toggle_switch/irs_right")
    P.irsalignleft = globalProperty("laminar/B738/annunciator/irs_align_left2")
    P.irsalignright = globalProperty("laminar/B738/annunciator/irs_align_right2")
    P.irsposset = globalProperty("laminar/B738/irs/irs_pos_set")

    P.yawdamperswitch = globalProperty("laminar/B738/toggle_switch/yaw_dumper_pos")
 
    set(P.n1setsource, 0)

    P.fmsselectedsid = nil
    P.fmsselectedstar = nil
    P.fmsselectedapp = nil

    P.needstempinit = true
end

--------------------------------------------------------------------------------------------------------------
function P.initializeSharedVariables()

    sasl.logInfo("Initializing SHARED monitoring variables.")

    P.apgoaroundtemp = get(P.apgoaround)

    P.desrwyheadingtemp = get(P.desrwyheading)
    P.desrwylatstartpostemp = get(P.desrwylatstartpos)
    P.desrwylonstartpostemp = get(P.desrwylonstartpos)
    P.desrwylatendpostemp = get(P.desrwylatendpos)
    P.desrwylonendpostemp = get(P.desrwylonendpos)
end

--------------------------------------------------------------------------------------------------------------
function P.buildProcedureLabelMaps()
    sasl.logInfo("Initializing procedure step access functions (get_index)...") -- Log message slightly adjusted

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
    sasl.logInfo("Procedure step access functions initialized.") -- Log message slightly adjusted
end

-------------------------------------------------------------------------------------------------------------- 
function P.resetLoopState(loopTable)
    if not loopTable then return end -- Safety check

    local cleanTemplate = P.procedurelooptemplate -- Use the master template

    loopTable.stepindex = cleanTemplate.stepindex          -- Setzt auf 0
    loopTable.steprepeat = cleanTemplate.steprepeat        -- Setzt auf false
    loopTable.procedureabort = cleanTemplate.procedureabort    -- Setzt auf false
    loopTable.procedureskipstep = cleanTemplate.procedureskipstep -- Setzt auf false
    loopTable.setonabort = cleanTemplate.setonabort        -- Setzt auf false
    loopTable.lastActiveTime = 0                     -- Setzt auf 0
    loopTable.currentStepName = nil                       -- Explizit nil setzen
    loopTable.lastStepName = nil                           -- Explizit nil setzen
    loopTable.procedurenotpossible = cleanTemplate.procedurenotpossible -- Setzt auf false
    loopTable.triggeredmanually = cleanTemplate.triggeredmanually -- Setzt auf false (Standard)
    loopTable.skipConfirmForStep = nil

    P.deleteCustomData(loopTable) -- Entfernt vref, navindex etc.

    sasl.logDebug("... Loop state transient flags and custom data reset.") -- Optional: Debug Log
end

--------------------------------------------------------------------------------------------------------------
function P.XCameraIsInstalled()
    local signature = "SRS.X-Camera"
    local pluginID = sasl.findPluginBySignature(signature)

    if pluginID ~= NO_PLUGIN_ID then
        if P.XCameraPluginID ~= pluginID then
            sasl.logInfo("X-Camera plugin detected, integration enabled.")
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
            sasl.logInfo("YANSH plugin detected, integration enabled.")
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
            sasl.logInfo("BetterPushback plugin detected, integration enabled.")
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
    return false
end

--------------------------------------------------------------------------------------------------------------
function P.initializeScript()

    P.YalinitGlobal()

    local PD = require("proceduredata")

    PD.fillProcedureTable()

    P.buildProcedureLabelMaps()

    P.initDataref()

    P.readconfig()

    helpers.buildnavdatatable(P.navdatatable)
    helpers.buildairportdatatable(P.airportdatatable)
    P.zibocalctable = helpers.loadZiboReferenceTables() or {}
    if (sasl.getLogLevel() == LOG_DEBUG) then
        helpers.writenavdatatable(P.navdatatable)
        helpers.writeairportdatatable(P.airportdatatable)
        helpers.writeZiboCalcTable(P.zibocalctable)
    end

    P.commandtableentry(def.TEXT, "YAL Initialization done")
    sasl.logInfo("Initialization and state restored")

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

    sasl.logInfo("Reset for new flight initiated.")

    P.YalinitGlobal()

    if get(P.battery) == def.ON or (P.apurunning() == def.APUONBUS) or (get(P.gpuon) == def.ON) then
        P.proceduretable[def.COLDANDDARKPROCEDURE].set = true
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

    sasl.logDebug("Saving reset loop states to datarefs...")
    for i = 1, #P.loopStateTables do
        P.saveLoopState(P.loopStateTables[i], i)
    end

    P.readconfig()

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
        helpers.command_once("/sasl/reload/yansh")
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
    sasl.logInfo("Manual YAL Reset initiated")

    -- Setzt Speicher zurück, lädt dann Persistenz, liest Config
    P.YalinitGlobal()
    P.initDataref() -- Lädt .set Flags, Loops und flightstate aus Datarefs
    P.readconfig()

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
        sasl.logInfo("State from procedures ("..stateFromProcs..") implausible after reset sync. Falling back.")
        -- Fallback
        if aircraftIsOnGround then
            if get(P.parkingbrakepos) == def.ON then
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
        sasl.logInfo("State after fallback: " .. finalState)
    else
        sasl.logDebug("State from procedures ("..finalState..") is plausible.")
    end

    -- Update und Speichern, falls nötig
    if finalState ~= P.flightstate then
         sasl.logInfo("Correcting flight state during reset. Old: " .. P.flightstate .. ", New: " .. finalState)
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
            sasl.logInfo("JITLUAON active: xlua/jit_enabled set to 1")
        else
            sasl.logInfo("JITLUAON requested but xlua/jit_enabled not found")
        end
    end

    if P.configvalues[def.CONFIGZIBOISMODDED] == def.ON then
        sasl.logInfo("ZIBOISMODDED active: FMS SID/STAR/APPROACH datarefs enabled")
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
    else
        P.fmsselectedsid = nil
        P.fmsselectedstar = nil
        P.fmsselectedapp = nil
    end

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

    if ((P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) and ((get(P.tirespeed) < 1) or (get(P.airgroundsensor) == def.OFF))) then
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

    if (get(P.fmsflightphase) ~= def.FMSPHASECRUISE) then
        P.commandtableentry(def.TEXT, "Time Warp only possible during Cruise")
        return true
    end

    if (get(P.vnavtoddist) < 10) then
        P.commandtableentry(def.TEXT, "Time Warp only possible prior to Top of Descent ")
        return true
    end

    local legstable = helpers.buildlegstable(get(P.fmslegs), get(P.fmslegslat), get(P.fmslegslon))

    if legstable and #legstable > 0 then
        sasl.logInfo("WARP: Content of Legs Table:")
        for i, waypoint in ipairs(legstable) do
            sasl.logInfo(string.format("WARP: Waypoint %d: %s (Lat: %.4f, Lon: %.4f), Distance to: %.2f NM, T.Heading: %.2f, M.Heading: %.2f", i, waypoint.name, waypoint.latitude, waypoint.longitude, waypoint.distance_to_next, waypoint.true_course, waypoint.magnetic_course))
        end
    else
        sasl.logInfo("WARP: Legs table empty")
        return false
    end

    sasl.logInfo("WARP: Aircraft Lat Pos " .. get(P.aircraftlatpos))
    sasl.logInfo("WARP: Aircraft Lon Pos " .. get(P.aircraftlonpos))
    sasl.logInfo("WARP: Distance to TOD " .. get(P.vnavtoddist))

    local warppoint = helpers.getpointonroute(legstable, get(P.aircraftlatpos), get(P.aircraftlonpos), get(P.vnavtoddist))

    sasl.logInfo("WARP: Latitude " .. warppoint.latitude)
    sasl.logInfo("WARP: Longitude " .. warppoint.longitude)
    sasl.logInfo("WARP: True Course " .. warppoint.truecourse)
    sasl.logInfo("WARP: Magnetic Course " .. warppoint.magneticcourse)
    sasl.logInfo("WARP: Next Waypoint " .. warppoint.nextwaypointname)
    sasl.logInfo("WARP: Remaining Distance " .. warppoint.remainingdistance)

    local localpositionx, localpositiony, localpositionz = sasl.worldToLocal(warppoint.latitude, warppoint.longitude, get(P.cabincruisealt) / def.FEETTOMETER)

    sasl.logInfo("WARP: Local Position X " .. localpositionx)
    sasl.logInfo("WARP: Local Position Y " .. localpositiony)
    sasl.logInfo("WARP: Local Position Z " .. localpositionz)

    local remainingfuel =  helpers.estimatefuelattod(get(P.lefttanklbs), get(P.righttanklbs), get(P.centertanklbs), get( P.vnavtoddist) - 10)

    sasl.logInfo("WARP: Remaining Fuel Left " .. remainingfuel.left)
    sasl.logInfo("WARP: Remaining Fuel Right " .. remainingfuel.right)
    sasl.logInfo("WARP: Remaining Fuel Center " .. remainingfuel.center)
    sasl.logInfo("WARP: Remaining Fuel Total" .. remainingfuel.total)

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

    if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) then
        P.configvalues[def.CONFIGAUTOFUNCTIONS] = def.OFF
        P.commandtableentry(def.TEXT, "Auto Functions Off")
    else
        P.configvalues[def.CONFIGAUTOFUNCTIONS] = def.ON
        P.commandtableentry(def.TEXT, "Auto Functions On")
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

    if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
        P.configvalues[def.CONFIGVIEWCHANGES] = def.OFF
        P.commandtableentry(def.TEXT, "View Changes Off")
    else
        P.configvalues[def.CONFIGVIEWCHANGES] = def.ON
        P.commandtableentry(def.TEXT, "View Changes On")
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

    if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
        P.configvalues[def.CONFIGVOICEADVICEONLY] = def.OFF
        P.commandtableentry(def.TEXT, "def.TEXT Only Off")
    else
        P.configvalues[def.CONFIGVOICEADVICEONLY] = def.ON
        P.commandtableentry(def.TEXT, "def.TEXT Only On")
    end

    return true

end

function P.toggleadviceonly_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.toggleadviceonly()
    end
    return 0
end

local my_command_toggleadviceonly = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleadviceonly", "Toggle def.TEXT Only")
sasl.registerCommandHandler(my_command_toggleadviceonly, 0, P.toggleadviceonly_)

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
function P.getlocalqnh(deparr)

    local localqnhpas = helpers.roundnumber(get(P.baroregionpas) / 100)
    local localqnhinch = helpers.convertpressure(localqnhpas)

    local metar_altim_in_hpa_val = nil

    if (deparr == def.DEPARTURE) then
        if P.depmetar.metarfound and P.depmetar.decodedmetar and P.depmetar.decodedmetar.pressure and P.depmetar.decodedmetar.pressure.qnh_hpa then
            metar_altim_in_hpa_val = tonumber(P.depmetar.decodedmetar.pressure.qnh_hpa)
        end
    elseif (deparr == def.ARRIVAL) then
        if P.desmetar.metarfound and P.desmetar.decodedmetar and P.desmetar.decodedmetar.pressure and P.desmetar.decodedmetar.pressure.qnh_hpa then
            metar_altim_in_hpa_val = tonumber(P.desmetar.decodedmetar.pressure.qnh_hpa)
        end
    end

    if metar_altim_in_hpa_val ~= nil then
        localqnhinch = helpers.convertpressure(metar_altim_in_hpa_val)
        localqnhpas = metar_altim_in_hpa_val
    end

    sasl.logDebug("GETLOCALQNH: INCH " .. tostring(localqnhinch) .. " PAS " .. tostring(localqnhpas))

    return localqnhinch, localqnhpas
end

--------------------------------------------------------------------------------------------------------------

function P.mastercaution()

    if (((P.procedureloop1.lock ~= def.NOPROCEDURE) or (P.procedureloop2.lock ~= def.NOPROCEDURE) or (P.procedureloop3.lock ~= def.NOPROCEDURE)) and (get(P.mastercautionannunc) == def.OFF)) then
        P.skipprocedurestep()
    end

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
            P.commandtableentry(def.TEXT, "No Metar found for " .. helpers.addspaces(get(P.desicao)))
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
            P.commandtableentry(def.TEXT, "No Metar found for " .. helpers.addspaces(get(P.depicao)))
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
            sasl.logInfo("'" .. procedureData.name .. "' is repeatable. Resetting .set flag to run again.")
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
        sasl.logInfo("triggerprocedure: Loop " .. loopIndex .. " IS free. Attempting to lock with ProcID: " .. procedureKey .. " ('" .. procedureData.name .. "').")

        sasl.logDebug("triggerprocedure: Loop " .. loopIndex .. " lock supposedly set to: " .. tostring(procedureKey))

        targetLoopObject.lock = procedureKey
        P.resetLoopState(targetLoopObject)
        targetLoopObject.triggeredmanually = isManual

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
            sasl.logInfo("triggerprocedure: Loop " .. loopIndex .. " IS NOT free. Current lock: '" .. tostring(currentProcName) .. "' (ID: " .. tostring(currentLockingProcKey) .. "). Cannot trigger '" .. procedureData.name .. "'.")
        else
            -- Optional: Debug-Log, wenn der Trigger dieselbe Prozedur erneut aufruft
            sasl.logDebug("triggerprocedure: Loop " .. loopIndex .. " is already running the requested procedure ('" .. procedureData.name .. "'). Trigger ignored.")
        end

        if isManual then
             P.commandtableentry(def.TEXT, "Cannot start " .. procedureData.name .. ". Loop " .. loopIndex .. " is busy with " .. tostring(currentProcName) .. ".")
        end
        -- sasl.logInfo Zeile war schon da, ist jetzt redundant wegen obigem Log
        return false -- Loop besetzt
    end -- Ende if targetLoopObject.lock == def.NOPROCEDURE / else
end -- Ende function P.triggerprocedure

--------------------------------------------------------------------------------------------------------------
function P.cycleprocedures()
    if ((P.procedureloop1.lock ~= def.NOPROCEDURE) or (P.procedureloop2.lock ~= def.NOPROCEDURE) or (P.procedureloop3.lock ~= def.NOPROCEDURE)) then
        return true
    end

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
                sasl.logInfo("Next Procedure is: " .. procedure.data.name)
                P.procedureloop1.lock = procedure.originalKey
                return true
            elseif shouldSkip then
                sasl.logInfo("Skipping " .. procedure.data.name .. " Procedure as its skip condition is met.")
            end
        end
    end

    sasl.logInfo("All cycable procedures completed")
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
function P.aircraftonrwy(runwayType, dist, headingLimit)

    headingLimit = headingLimit or 20 -- Standard-Limit von 20 Grad

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

    local s = (d1 * v1 + d2 * v2) / v_mag_sq

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

    local isOnRunwayProximity = (disttorwy_sq < (dist*dist))

    local aircraftTrack = get(P.groundtrackmag)
    local headingDiff = helpers.headingdiff(aircraftTrack, runwayHeading)
    local isHeadingAligned = (headingDiff < headingLimit) -- True wenn < 20 Grad

    if runwayType == def.DEPARTURE then
        return isOnRunwayProximity and isHeadingAligned

    elseif runwayType == def.ARRIVAL then
        return (not isOnRunwayProximity) or (not isHeadingAligned)

    else
        return isOnRunwayProximity
    end
end
--------------------------------------------------------------------------------------------------------------
function P.syncProceduresOnLoad()
    sasl.logInfo("SYNC: Resynchronizing procedure states with aircraft status...")

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
            sasl.logInfo("SYNC: Procedure '" .. proc.name .. "' skipped (condition met).")
        else
            if proc then
                sasl.logInfo("SYNC: Stopping sync at procedure '" .. proc.name .. "'.")
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
                 sasl.logInfo("" .. loopIdStr .. " - Successfully restored procedure " .. loop.lock .. " at step '" .. loop.currentStepName .. "'")
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
    local lockToSave = loopTable.lock or 0
    local stateToSave = loopTable.stepindex or 0

    -- *** ÄNDERUNG: Platzhalter für leere Strings ***
    local nameToSave = loopTable.currentStepName
    if nameToSave == nil or nameToSave == "" then
        nameToSave = def.STRINGDRNONEVALUE
    end

    local customDataString = P.serializeCustomData(loopTable)
    local customToSave = customDataString
    if customToSave == nil or customToSave == "" then
        customToSave = def.STRINGDRNONEVALUE
    end
    -- *** ENDE ÄNDERUNG ***

    if lockToSave == 0 then
         sasl.logDebug("!!! SAVING LOOP " .. loopIndex .. " with LOCK=0: State=" .. stateToSave .. ", StepName='" .. nameToSave .. "'")
    end

    -- Speichere die 4 persistenten Werte
    set(handles.lock, lockToSave)
    set(handles.state, stateToSave)
    set(handles.stepname, nameToSave)
    set(handles.custom, customToSave)
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

    if state == nil then
        local anyOn = false
        if ledVariant then
            anyOn = (get(P.llights1) ~= def.OFF) or (get(P.llights4) ~= def.OFF)
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

    if (P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) then
        P.configvalues[def.CONFIGVOICEREADBACK] = def.OFF
        P.commandtableentry(def.TEXT, "Voice Readback Off")
    else
        P.configvalues[def.CONFIGVOICEREADBACK] = def.ON
        P.initDataref()
        P.commandtableentry(def.TEXT, "Voice Readback On")
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
function P.setmmrils(mmr, freq)

    local ilsfreq = tostring(freq)

    if (get(P.mmrinstalled) == def.OFF) then
        return false
    end

    sasl.logInfo("SETMMRILS: " .. mmr .. freq)

    P.setmmrmode(mmr, def.MMRILS)

    if ((mmr == def.MMRBOTH) or (mmr == def.MMRCAPTAIN)) then
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 1, 1))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 2, 2))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 3, 3))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 4, 4))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 5, 5))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_act_stby")
    end

    if ((mmr == def.MMRBOTH) or (mmr == def.MMRFO)) then
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 1, 1))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 2, 2))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 3, 3))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 4, 4))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 5, 5))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_act_stby")
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
function P.setmmrgls(mmr, freq)

    local glsfreq = tostring(freq)

    if (get(P.mmrinstalled) == def.OFF) then
        return false
    end

    P.setmmrmode(mmr, def.MMRGLS)

    if ((mmr == def.MMRBOTH) or (mmr == def.MMRCAPTAIN)) then
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 1, 1))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 2, 2))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 3, 3))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 4, 4))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 5, 5))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr1_act_stby")
    end

    if ((mmr == def.MMRBOTH) or (mmr == def.MMRFO)) then
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 1, 1))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 2, 2))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 3, 3))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 4, 4))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 5, 5))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_act_stby")
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
    elseif (get(P.mmrcptactvalue) ~= get(P.mmrfoactvalue)) then
        if (get(P.mmrcptactmode) ~= get(P.mmrfostdbymode)) then
            P.setmmrmode(def.MMRFO, get(P.mmrcptactmode))
        end

        local mmrvalue = tostring(get(P.mmrcptactvalue))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 1, 1))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 2, 2))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 3, 3))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 4, 4))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 5, 5))
        P.commandtableentry(def.COMMAND, "laminar/B738/push_button/mmr2_act_stby")

        setnav = true
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

    if (targettrim == 3.0) then
        trimwheelcalcrounded = 65
    elseif (targettrim == 3.25) then
        trimwheelcalcrounded = 61
    elseif (targettrim == 3.5) then
        trimwheelcalcrounded = 58
    elseif (targettrim == 3.75) then
        trimwheelcalcrounded = 55
    elseif (targettrim == 4.0) then
        trimwheelcalcrounded = 52
    elseif (targettrim == 4.25) then
        trimwheelcalcrounded = 48
    elseif (targettrim == 4.5) then
        trimwheelcalcrounded = 45
    elseif (targettrim == 4.75) then
        trimwheelcalcrounded = 42
    elseif (targettrim == 5.0) then
        trimwheelcalcrounded = 40
    elseif (targettrim == 5.25) then
        trimwheelcalcrounded = 34
    elseif (targettrim == 5.5) then
        trimwheelcalcrounded = 32
    elseif (targettrim == 5.75) then
        trimwheelcalcrounded = 30
    elseif (targettrim == 6.00) then
        trimwheelcalcrounded = 27
    elseif (targettrim == 6.25) then
        trimwheelcalcrounded = 24
       elseif (targettrim == 6.50) then
        trimwheelcalcrounded = 21
    else
        trimwheelcalcrounded = 40
    end

    trimwheeltemp = get(P.trimwheel)
    trimwheelrounded = helpers.roundnumber(trimwheeltemp * -100)

    while ((trimwheelrounded ~= trimwheelcalcrounded) and (trimwheeltemp ~= trimwheelold)) do
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
        trimwheelrounded = helpers.roundnumber(trimwheeltemp * -100)

    end

    return true

end

--------------------------------------------------------------------------------------------------------------
function P.updatemetar()
    local depicaotmp = helpers.cleanstring(get(P.depicao))
    local desicaotmp = helpers.cleanstring(get(P.desicao))

    if P.flightstate <= def.FLIGHTSTATEINITIALCLIMB then
        if helpers.isvalidicao(depicaotmp) and depicaotmp ~= P.depmetar.icaocode then
            helpers.getMetar(depicaotmp, P.depmetar)
        end
    end

    if helpers.isvalidicao(desicaotmp) and desicaotmp ~= P.desmetar.icaocode then
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

function P.setmmrmode(mmr, state)

    if ((mmr == nil) or (state == nil)) then
        return false
    end

    if ((get(P.mmrinstalled) == def.OFF) or ((get(P.lpvinstalled) == def.OFF) and ((state == def.MMRLPV) or (state == def.MMRGLS)))) then
        return false
    end

    if ((mmr == def.MMRCAPTAIN) or (mmr == def.MMRBOTH)) then
        local mmrcptstdbymodediff = math.abs(get(P.mmrcptstdbymode) - state)

        if ((state == def.MMRLPV) or (get(P.mmrcptstdbymode) == def.MMRLPV)) then
            mmrcptstdbymodediff = mmrcptstdbymodediff - 1
        end

        if (state >= get(P.mmrcptstdbymode)) then
            while (mmrcptstdbymodediff > 0) do
                sasl.logDebug("while loop mmr1 up")
                helpers.command_once("laminar/B738/push_button/mmr1_mode_up")
                mmrcptstdbymodediff = mmrcptstdbymodediff - 1
            end
        elseif (state < get(P.mmrcptstdbymode)) then
            while (mmrcptstdbymodediff > 0) do
                sasl.logDebug("while loop mmr1 dn")
                helpers.command_once("laminar/B738/push_button/mmr1_mode_dn")
                mmrcptstdbymodediff = mmrcptstdbymodediff - 1
            end
        end
    end

    if ((mmr == def.MMRFO) or (mmr == def.MMRBOTH)) then
        local mmrfostdbymodediff = math.abs(get(P.mmrfostdbymode) - state)

        if ((state == def.MMRLPV) or (get(P.mmrfostdbymode) == def.MMRLPV)) then
            mmrfostdbymodediff = mmrfostdbymodediff - 1
        end

        if (state >= get(P.mmrfostdbymode)) then
            while (mmrfostdbymodediff > 0) do
                sasl.logDebug("while loop mmr2 up")
                helpers.command_once("laminar/B738/push_button/mmr2_mode_up")
                mmrfostdbymodediff = mmrfostdbymodediff - 1
            end
        elseif (state < get(P.mmrfostdbymode)) then
            while (mmrfostdbymodediff > 0) do
                sasl.logDebug("while loop mmr2 dn")
                helpers.command_once("laminar/B738/push_button/mmr2_mode_dn")
                mmrfostdbymodediff = mmrfostdbymodediff - 1
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
function P.duringclimb()
    local proc_to_check = def.DURINGCLIMBPROCEDURE
    local targetLoopIndex = P.proceduretable[proc_to_check].loop
    local isLoopFree = (P.loopStateTables[targetLoopIndex].lock == def.NOPROCEDURE)
    if isLoopFree then
        sasl.logDebug("Autofunctions triggering DURINGCLIMBPROCEDURE (Loop " .. targetLoopIndex .. " is free).")
        P.triggerprocedure(proc_to_check)
    end

    local departure_icao = get(P.depicao)
    local departure_altitude = nil
    if P.airportdatatable[departure_icao] and P.airportdatatable[departure_icao].elevation_ft then
        departure_altitude = P.airportdatatable[departure_icao].elevation_ft
    end

    local height_above_field = get(P.altitude) - departure_altitude
    local lower_airspace_alt = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
    local altitudeTriggerConditions = (height_above_field >= lower_airspace_alt) or (get(P.altitude) >= lower_airspace_alt)
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
function P.duringdescent()

    local proc_to_check = def.DURINGDESCENTPROCEDURE
    local targetLoopIndex = P.proceduretable[proc_to_check].loop
    local isLoopFree = (P.loopStateTables[targetLoopIndex].lock == def.NOPROCEDURE)
    if isLoopFree then
        sasl.logDebug("Autofunctions triggering DURINGDESCENTPROCEDURE (Loop " .. targetLoopIndex .. " is free).")
        P.triggerprocedure(proc_to_check)
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

    local radio_alt = get(P.radioaltitude)
    local lower_airspace_alt = P.configvalues[def.CONFIGLOWEAIRSPACEALT]
    local altitudeB10kConditions = (height_above_field < lower_airspace_alt) or (radio_alt < lower_airspace_alt)
    local procB10k = def.ALTITUDEB10000PROCEDURE
    local loopB10kIndex = P.proceduretable[procB10k].loop
    local isLoopB10kFree = (P.loopStateTables[loopB10kIndex].lock == def.NOPROCEDURE)
    if altitudeB10kConditions and isLoopB10kFree then
        sasl.logDebug("Autofunctions triggering ALTITUDEB10000PROCEDURE (Loop " .. loopB10kIndex .. " is free).")
        P.triggerprocedure(procB10k)
    end

    local altitudeB2500Conditions = (height_above_field < 2500) or (radio_alt < 2500)
    local procB2500 = def.RADIOALTITUDEB2500PROCEDURE
    local loopB2500Index = P.proceduretable[procB2500].loop
    local isLoopB2500Free = (P.loopStateTables[loopB2500Index].lock == def.NOPROCEDURE)
    if altitudeB2500Conditions and isLoopB2500Free then
        sasl.logDebug("Autofunctions triggering RADIOALTITUDEB2500PROCEDURE (Loop " .. loopB2500Index .. " is free).")
        P.triggerprocedure(procB2500)
    end

    local altitudeB1000Conditions = (height_above_field < 1000) or (radio_alt < 1000)
    local procB1000 = def.RADIOALTITUDEB1000PROCEDURE
    local loopB1000Index = P.proceduretable[procB1000].loop
    local isLoopB1000Free = (P.loopStateTables[loopB1000Index].lock == def.NOPROCEDURE)
    if altitudeB1000Conditions and isLoopB1000Free then
        sasl.logDebug("Autofunctions triggering RADIOALTITUDEB1000PROCEDURE (Loop " .. loopB1000Index .. " is free).")
        P.triggerprocedure(procB1000)
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
        sasl.logInfo("Saving updated procedure set status to dataref.")
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
             if fmsPhase == def.FMSPHASECRUISE then
                 state = def.FLIGHTSTATECRUISE
             elseif fmsPhase >= def.FMSPHASEDESCENT then
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
            sasl.logInfo("State from procedures ("..stateFromProcs..") is implausible for current ground/air status (" .. (aircraftIsOnGround and "GROUND" or "AIR") .. "). Falling back.")
            if aircraftIsOnGround then
                if get(P.parkingbrakepos) == def.ON then
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
            sasl.logInfo("State after fallback: " .. finalState)
        else
            sasl.logDebug("State from procedures ("..finalState..") is plausible.")
        end

        if finalState ~= currentFlightState then
             sasl.logInfo("Correcting flight state after reload. Old: " .. currentFlightState .. ", New: " .. finalState)
             P.flightstate = finalState
             flightStateChanged = true
        end

        if not aircraftIsOnGround then
             sasl.logInfo("Performing inflight restore actions after reload.")
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

        local triggerConditionsMet_BTO = (((((P.aircraftonrwy(def.DEPARTURE, 0.0003, 20) and (helpers.roundnumber(get(P.groundspeed)) == 0)) and (get(P.transponderpos) == def.TARA))) or (get(P.positionlights) == def.POSLIGHTSSTROBE)) and P.flightstate == def.FLIGHTSTATEPREFLIGHT)
        if triggerConditionsMet_BTO then
            P.triggerprocedure(def.BEFORETAKEOFFPROCEDURE)
        end
    
        local triggerConditionsMet_AL = (((get(P.groundspeed) < 45) and (P.aircraftonrwy(def.ARRIVAL, 0.0001, 20) or (helpers.roundnumber(get(P.groundspeed)) == 0))) or (get(P.positionlights) == def.POSLIGHTSSTEADY))
        if triggerConditionsMet_AL and currentFlightState >= def.FLIGHTSTATEAPPROACH then
            P.triggerprocedure(def.AFTERLANDINGPROCEDURE)
        end


        local triggerConditionsMet_AP = (get(P.parkingbrakepos) == def.ON) and (P.flightstate == def.FLIGHTSTATETAXITOGATE or P.flightstate == def.FLIGHTSTATESHUTDOWN)
        if triggerConditionsMet_AP then
            P.triggerprocedure(def.ATPARKINGPOSITIONPROCEDURE)
        end

    else
        local fmsPhase = get(P.fmsflightphase) or 0
        local targetFlightState = P.flightstate

        if ((fmsPhase >= def.FMSPHASEDESCENT) and (get(P.vnavtoddist) <= 1)) then
            targetFlightState = def.FLIGHTSTATEAPPROACH
        elseif (fmsPhase == def.FMSPHASECRUISE) then
            targetFlightState = def.FLIGHTSTATECRUISE
        elseif (fmsPhase == def.FMSPHASECLIMB) and P.proceduretable[def.AFTERTAKEOFFPROCEDURE].set then
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
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function P.updateSharedVariables()

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
function P.ongoingtasks()

    local current_level = sasl.getLogLevel()

    if current_level ~= P.lastPolledDebugLevel then

        set(P.debugLevelDataref, current_level)
        if P.xluaLoggingEnabled then
            set(P.xluaLoggingEnabled, current_level == LOG_DEBUG and 1 or 0)
        end
        P.lastPolledDebugLevel = current_level
        sasl.logDebug("Debug level change detected by poll. Saved to dataref: " .. current_level)
    end

    if (P.updatemetartimer == nil) then
        P.updatemetartimer = sasl.createTimer()
        sasl.startTimer(P.updatemetartimer)
        P.updatemetar()
    elseif (sasl.getElapsedSeconds(P.updatemetartimer) > 300) then
        P.updatemetar()
        sasl.startTimer(P.updatemetartimer)
    end

    if ((P.apgoaroundtemp ~= get(P.apgoaround)) and (get(P.apgoaround) == def.ON)) then

        local aircraftOnGround = (get(P.airgroundsensor) == def.ON)
        local radioAlt = get(P.radioaltitude) or 0
        if (P.flightstate == def.FLIGHTSTATEAPPROACH) and not aircraftOnGround and (radioAlt < 2500) then
            -- Trigger dedicated Go-Around procedure if loop is free
            local gaLoopIndex = P.proceduretable[def.GOAROUNDPROCEDURE].loop
            if P.loopStateTables[gaLoopIndex] and P.loopStateTables[gaLoopIndex].lock == def.NOPROCEDURE then
                sasl.logInfo("Go Around: triggering Go Around procedure on Loop " .. tostring(gaLoopIndex) .. ".")
                P.triggerprocedure(def.GOAROUNDPROCEDURE)
            else
                sasl.logInfo("Go Around: Go Around procedure not triggered (loop busy).")
            end
        else
            sasl.logDebug("Go Around detected but conditions not met (state/air/alt).")
        end

        P.apgoaroundtemp = get(P.apgoaround)
    end

    if ((get(P.pausetod) == def.ON) and (P.configvalues[def.CONFIGTODPAUSEQUITTIME] ~= 9999)) then
        if (get(P.simpaused) == def.ON) then
            if (P.pausetodtimer == nil) then
                P.pausetodtimer = sasl.createTimer()
                sasl.startTimer(P.pausetodtimer)
            elseif (sasl.getElapsedSeconds(P.pausetodtimer) > P.configvalues[def.CONFIGTODPAUSEQUITTIME]) then
                helpers.command_once("laminar/B738/tab/save_flight" .. tonumber(P.configvalues[def.CONFIGSAVENUMBER]))
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

    if (P.configvalues[def.CONFIGSAVETIME] ~= 9999) then
        if (P.savetimer == nil) then
            P.savetimer = sasl.createTimer()
            sasl.startTimer(P.savetimer)
        elseif (sasl.getElapsedSeconds(P.savetimer) > P.configvalues[def.CONFIGSAVETIME]) then
            helpers.command_once("laminar/B738/tab/save_flight" .. tonumber(P.configvalues[def.CONFIGSAVENUMBER]))
            sasl.startTimer(P.savetimer)
        end
    elseif (P.savetimer ~= nil) then
        sasl.stopTimer(P.savetimer)
        P.savetimer = nil
    end

    local groundspeed = get(P.groundspeed) or 0
    local onDepartureRunway = P.aircraftonrwy and P.aircraftonrwy(def.DEPARTURE, 0.02, 25)
    local onArrivalRunway = P.aircraftonrwy and P.aircraftonrwy(def.ARRIVAL, 0.02, 25)
    if (get(P.airgroundsensor) == def.ON)
        and (P.flightstate == def.FLIGHTSTATEPREFLIGHT or P.flightstate == def.FLIGHTSTATETAXITOGATE)
        and (groundspeed > 45)
        and not onDepartureRunway and not onArrivalRunway then
            P.commandtableentry(def.TEXT, "Monitor Taxi Speed")
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

    local airGroundSensor = get(P.airgroundsensor)
    if airGroundSensor ~= nil and airGroundSensor == def.ON and P.flightstate == def.FLIGHTSTATEPREFLIGHT then

        if P.procedureloop1 and P.procedureloop1.lock == def.NOPROCEDURE then
            local voiceAdviceSetting = P.configvalues and P.configvalues[def.CONFIGVOICEADVICEONLY]
            if voiceAdviceSetting == def.ON then

                local battery = get(P.battery)
                local posLights = get(P.positionlights)
                local parkBrake = get(P.parkingbrakepos)
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
                local enginesRunningBoth = P.enginesrunning(P.BOTH)
                local bleed1 = get(P.bleedair1pos)
                local bleed2 = get(P.bleedair2pos)

                if battery == def.ON and posLights ~= nil and posLights ~= def.POSLIGHTSSTEADY and parkBrake == def.ON then
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
                end
            end
        end

        if P.procedureloop1 and (P.procedureloop1.lock == def.NOPROCEDURE or P.procedureloop1.lock == def.BEFORETAKEOFFPROCEDURE) then
            local atArmPos = get(P.atarmpos)
            local atN1Stat = get(P.atn1stat)
            local atThrottleLock = get(P.atthrottlelock)
            local eng1N1 = get(P.eng1n1percent)
            local eng2N1 = get(P.eng2n1percent)


            if (atArmPos == def.ARMED and atN1Stat == def.OFF and atThrottleLock == def.OFF and eng1N1 ~= nil and eng1N1 > 40 and eng2N1 ~= nil and eng2N1 > 40) then
                P.commandtableentry(def.TEXT, "Both Engine N 1 at 40 Percent")
            end
        end
    end

    if (P[def.PROCEDURELOOP .. P.proceduretable[def.COCKPITINITPROCEDURE].loop].lock ~= def.COCKPITINITPROCEDURE) then
        if (P.ongoingtaskstepindex == 1) then
            if (P.enginesrunning(def.BOTH) and (P.configvalues[def.CONFIGAUTOCENTERTANKHANDLING] == def.ON)) then
                if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                    P.autocentertanks()
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    if ((get(P.centertanklbs) > 1000) and (get(P.centertanklpress) > 0) and (get(P.centertankrpress) > 0) and (get(P.centertankstat) > 0)) then
                        if ((get(P.centertanklswitch) == def.OFF) or (get(P.centertankrswitch) == def.OFF)) then
                            P.commandtableentry(def.TEXT, "Set Center Tank Fuel Pumps On")
                            P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                        end
                    elseif ((get(P.centertanklbs) <= 1000)) or ((get(P.centertanklpress) == 0) and (get(P.centertankrpress) == 0)) then
                        if ((get(P.centertanklswitch) == def.ON) or (get(P.centertankrswitch) == def.ON)) then
                            P.commandtableentry(def.TEXT, "Set Center Tank Fuel Pumps Off")
                            P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                        end
                    end
                end
            end
        elseif (P.ongoingtaskstepindex == 2) then
            if ( (P.flightstate < def.FLIGHTSTATECRUISE) and (get(P.fmccruisealt) ~= 0) and (get(P.fmccruisealt) ~= 20000)) then
                local fmccruisealttmp = helpers.roundnumber(get(P.fmccruisealt) / 500) * 500
                if (get(P.cabincruisealt)  ~= fmccruisealttmp) then
                    if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                        set(P.cabincruisealt, fmccruisealttmp)
                    elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        P.commandtableentry(def.TEXT, "Set Cabin Cruise Alitude " .. helpers.addspaces(fmccruisealttmp))
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                end
            end
        elseif (P.ongoingtaskstepindex == 3) then
            if ((P.flightstate < 4) and helpers.isvalidicao(get(P.desicao))) then
                local deslandingalttmp = 0
                local destination_icao = get(P.desicao)

                if (P.airportdatatable[destination_icao] and P.airportdatatable[destination_icao].elevation_ft) then
                    deslandingalttmp = helpers.roundnumber(P.airportdatatable[destination_icao].elevation_ft / 50) * 50
                elseif (get(P.desrwyalt) > -1000) then
                     deslandingalttmp = helpers.roundnumber(get(P.desrwyalt) / 50) * 50
                end

                if (deslandingalttmp > 0 and get(P.cabinlandingalt) ~= deslandingalttmp) then
                    if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                        set(P.cabinlandingalt, deslandingalttmp)
                    elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        P.commandtableentry(def.TEXT, "Set Cabin Landing Altitude " .. helpers.addspaces(deslandingalttmp))
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                end
            end
        end
    elseif (P.ongoingtaskstepindex == 1) then
        P.ongoingtaskstepindex = 4
    end

    if (P.ongoingtaskstepindex == 4) then
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

                local ground_icing
                if wx ~= nil then
                    ground_icing = helpers.isGroundIcingCondition(wx)
                else
                    local tat_c = get(P.tatdegc)
                    ground_icing = (tat_c ~= nil) and (tat_c <= 5)
                end
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
                                P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                            end
                        else
                            if anyAntiIceOn() then
                                P.commandtableentry(def.TEXT, "No Ground Icing Conditions, Switch Anti Icing Off")
                                P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
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
                                P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
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
                                P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                            end
                        else
                            if anyAntiIceOn() then
                                P.commandtableentry(def.TEXT, "No Icing Conditions Taxi In, Switch Anti Icing Off")
                                P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
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
                            P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                        end
                    elseif (get(P.altitude) > 30000) then
                        if ((get(P.eng1heatpos) == def.ON) or (get(P.eng2heatpos) == def.ON) or (get(P.wingheatpos) == def.ON)) then
                            P.commandtableentry(def.TEXT, "Above 30000 Feet, Switch Anti Icing Off")
                            P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                        end
                    elseif (get(P.tatdegc) > 10) then
                        if ((get(P.eng1heatpos) == def.ON) or (get(P.eng2heatpos) == def.ON) or (get(P.wingheatpos) == def.ON)) then
                            P.commandtableentry(def.TEXT, "T A T above 10 degree, Switch Anti Icing Off")
                            P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                        end
                    end
                end
            end
        end
    end

    if (P.ongoingtaskstepindex == 5) then
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
    end

    if (((get(P.airgroundsensor) == def.ON) and (P.procedureloop1.lock == def.NOPROCEDURE) and (get(P.battery) == def.ON) and (get(P.mainbus) ~= def.OFF) and (P.flightstate == def.FLIGHTSTATEPREFLIGHT) and (get(P.taxilight) == def.OFF))) then
        if (P.ongoingtaskstepindex == 6) then
            if ((P.configvalues[def.CONFIGAUTOBARO] == def.ON) and (get(P.groundspeed) < 45)) then
                local baroinchtmp, baropastmp = P.getlocalqnh(def.DEPARTURE)
                if (helpers.roundnumber(math.abs(helpers.roundnumber(get(P.baropilot),2) - baroinchtmp),2) > 0.01) then
                    if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                        set(P.baropilot, baroinchtmp)
                    elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        if (get(P.baroinhpa) == def.ON) then
                            P.commandtableentry(def.TEXT, "Set Q N H " .. helpers.addspaces(baropastmp))
                        else
                            P.commandtableentry(def.TEXT, "Set Q N H " .. helpers.addspaces(baroinchtmp))
                        end
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                end
            end
        elseif (P.ongoingtaskstepindex == 7) then
            if (get(P.trimcalc) > 0) and (get(P.trimcalc) ~= helpers.gettrim(get(P.trimwheel)) and (get(P.groundspeed) < 45)) then
                if (((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON))) then
                    P.settotrim()
                    P.commandtableentry(def.TEXT, "Trim " .. tostring(get(P.trimcalc)))
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Trim " .. tostring(get(P.trimcalc)))
                    P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                end
            end
        elseif (P.ongoingtaskstepindex == 8) then
            if ((get(P.v2speed) > 0) and (get(P.v2speed) ~= get(P.mcpspeed)) and (get(P.groundspeed) < 45)) then
                if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                    set(P.mcpspeed, get(P.v2speed))
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set M C P Speed " .. helpers.addspaces(get(P.v2speed)))
                    P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                end
            end
        elseif (P.ongoingtaskstepindex == 9) then
            local headingrounded = nil
            if (helpers.isvalidicao(get(P.depicao)) and helpers.isvalidrwy(get(P.deprwy)) and tonumber(get(P.deprwyheading))) then
                headingrounded = helpers.roundnumber(get(P.deprwyheading))
            end
            local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.depicao), get(P.deprwy))
            if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
                headingrounded = navrwyheading
            end
            if (headingrounded and (headingrounded ~= get(P.mcpheading)) and (get(P.groundspeed) < 45)) then
                if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                    set(P.mcpheading, headingrounded)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded,3)))
                    P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                end
            end
        end
    elseif (P.ongoingtaskstepindex == 6) then
        P.ongoingtaskstepindex = 10
    end

    if (P.ongoingtaskstepindex == 10) then
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

        if aircraftInAir and flightStateEligible and not suppressDiscoWarnings then
            -- Additional guard: ToD missing but route still long
            if (not todDistance) or (todDistance <= 0) then
                local remainingDistance = helpers.getRemainingRouteDistance(
                    get(P.fmslegs),
                    get(P.fmslegslat),
                    get(P.fmslegslon),
                    get(P.aircraftlatpos),
                    get(P.aircraftlonpos)
                )
                local distDest = get(P.distdest)

                if remainingDistance and distDest and (remainingDistance > 0) and (distDest > 0) then
                    local diff = distDest - remainingDistance
                    if diff > 50 then -- significant gap -> route likely incomplete
                        if not P.routeEndsEarlyWarned then
                            P.commandtableentry(def.TEXT, "Warning: Route may end too early. Check Arrival / Approach setup.")
                            P.routeEndsEarlyWarned = true
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
                local remainingDistance = helpers.getRemainingRouteDistance(
                    get(P.fmslegs),
                    get(P.fmslegslat),
                    get(P.fmslegslon),
                    get(P.aircraftlatpos),
                    get(P.aircraftlonpos)
                )

                local hasRemaining = remainingDistance and remainingDistance > 0
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

        if (P.flightstate == def.FLIGHTSTATECRUISE) and (get(P.fmsflightphase) == def.FMSPHASECRUISE) and not suppressDiscoWarnings then
            local fmcCruiseAlt = get(P.fmccruisealt) or 0
            local mcpAlt = get(P.mcpaltitude) or 0
            -- FMC Cruise kann "ungerade" sein (z.B. 39100); MCP ist in 100-ft-Schritten.
            local fmcCruiseRounded = helpers.roundnumber(fmcCruiseAlt / 100, 0) * 100
            local withinTolerance = (mcpAlt >= (fmcCruiseRounded - 100))
            if withinTolerance and (get(P.vnavtoddist) < 20) then
                P.commandtableentry(def.TEXT, "Approaching Top of Descent, Reset M C P Altitude")
                P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
            end
        end
    end

     if (P.ongoingtaskstepindex == 11) then
        if (P.flightstate == def.FLIGHTSTATECRUISE) and (get(P.fmsflightphase) == def.FMSPHASECRUISE) and (get(P.totalfuellbs) < 1000) then

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
            local requiredfuellbs = P.calculateRequiredFuelNow(distanceToTODNM, reservefuelLbs)

            P.refuelAircraft(requiredfuellbs)
        end
    end

    P.ongoingtaskstepindex = P.ongoingtaskstepindex + 1

    if (P.ongoingtaskstepindex > 11) then
        P.ongoingtaskstepindex = 1
    end

    if P.OngoingTaskIndexdr then
        set(P.OngoingTaskIndexdr, P.ongoingtaskstepindex)
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.commandtableloop()

    local next_recommended_wait_step = def.STANDARDWAIT

    local processedentry = false

    while ((#P.commandtable > 0) and (processedentry == false)) do

        if (P.commandtable[1][1] == def.COMMAND) then
            local command_path = P.commandtable[1][2]
            sasl.logInfo("COMMAND: " .. tostring(command_path))

            local command_handle = sasl.findCommand(command_path)
            if command_handle then
                sasl.commandOnce(command_handle)
            else
                sasl.logWarning("Command not found: " .. tostring(command_path))
            end
        elseif (P.commandtable[1][1] == def.TEXT) then
            if ((P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) or (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)) then
                sasl.logInfo("SpeakString TEXT: " .. P.commandtable[1][2])
                helpers.speak(P.commandtable[1][2])
                if (string.len(P.commandtable[1][2]) > def.VERYLONGSPEAK) then
                    next_recommended_wait_step = def.LONGWAIT
                elseif (string.len(P.commandtable[1][2]) > def.LONGSPEAK) then
                    next_recommended_wait_step = def.MEDIUMWAIT
                end
                processedentry = true
            end
        end

        table.remove(P.commandtable, 1)

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
            sasl.logInfo("Aborting '" .. procData.name .. "' due to invalid aircraft state.")
            loop.procedureabort = true
            -- Hier KEIN goto/return, der Abbruch wird unten behandelt

        -- B) Check Transition Conditions (führt zu "soft skip" mit set=true)
        elseif procData.transitionConditions then
            for _, transCond in ipairs(procData.transitionConditions) do
                if transCond.condition() then
                    sasl.logInfo("Skipping '" .. procData.name .. "' due to met transition condition.")

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
                sasl.logInfo(procData.name .. " Procedure (Data-Driven) started at " .. timestring)

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
                local msg_abort = loop.procedureabort and "Procedure Aborted" or "Procedure Not Possible"
                sasl.logDebug("Engine A - Handling Abort/NotPossible. Message: " .. msg_abort)
                if loop.procedureabort then
                      -- *** FIX msg START ***
                    local abort_text = procData.name .. " " .. msg_abort
                    if type(abort_text) == "string" and abort_text ~= "" then
                        P.commandtableentry(def.TEXT, abort_text)
                    end
                     -- *** FIX msg END ***
                end
                sasl.logInfo(procData.name .. " " .. msg_abort .. " at " .. timestring)

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
                sasl.logInfo(procData.name .. " Procedure completed at " .. timestring)
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

                if not step then
                    sasl.logDebug("Procedure " .. procData.name .. " failed: Step '" .. tostring(stepName) .. "' is nil! Aborting.")
                    loop.procedureabort = true
                else
                    -- 5a. Step Repeat Logik
                    if stepName == loop.lastStepName then loop.steprepeat = true else loop.steprepeat = false end
                    loop.lastStepName = stepName
                    sasl.logDebug("steprepeat=" .. tostring(loop.steprepeat))

                    -- *** NEUE VIEW-OPTIMIERUNG START ***

                    -- Definiere die Step-Typen
                    local isPureViewStep = step.view and not step.check and not step.action and not step.branch and step.nextStep
                    local isViewBranchStep = step.view and not step.check and not step.action and step.branch

                    if not useViewChanges and (isPureViewStep or isViewBranchStep) then
                        -- OPTIMIERUNG AKTIV (Views sind AUS und es ist ein reiner View-Step)

                        if isPureViewStep then
                            -- Fall 1: Purer View-Step (view + nextStep)
                            -- Überspringe direkt zum nextStep
                            sasl.logDebug("View changes OFF. Skipping pure view step to: " .. tostring(step.nextStep))
                            loop.currentStepName = step.nextStep
                            loop.lastStepName = nil -- Wichtig für den nächsten Schritt

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
                                                    P.commandtableentry(def.TEXT, advice_msg_raw)
                                                    sasl.logDebug("Advice message: " .. advice_msg_raw)
                                                end
                                            end
                                            if step.action and step.runActionInAdviceMode then
                                                 step.action(loop, procData);
                                                 sasl.logDebug("Executed 'runActionInAdviceMode' action.")
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
                                                    P.commandtableentry(def.TEXT, advice_msg_raw)
                                                    sasl.logDebug("Advice message: " .. advice_msg_raw)
                                                end
                                            end

                                            -- 2. Action AUSNAHMSWEISE ausführen (wenn geflaggt und nicht wiederholt)
                                            if step.action and step.runActionInAdviceMode then
                                                 step.action(loop, procData);
                                                 sasl.logDebug("Executed 'runActionInAdviceMode' action (on first fail).")
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
        sasl.logInfo("Procedure aborted (likely manual or state change before engine). Resetting loop lock.") -- Bleibt Info fürs Log

        -- *** NEU: Meldung für den Benutzer hinzufügen ***
        if procData and procData.name then -- Sicherstellen, dass wir einen Namen haben
             local abort_message = procData.name .. " Procedure Aborted"
             P.commandtableentry(def.TEXT, abort_message)
        else
             -- Fallback, falls procData aus irgendeinem Grund nil ist
             P.commandtableentry(def.TEXT, "Procedure Aborted")
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
        loop.procedurenotpossible = false
        loop.setonabort = false
    -- Der Fall transition_occurred wird implizit behandelt, da loop.lock bereits NOPROCEDURE ist
    end -- Ende if not loop.procedureabort and not transition_occurred / elseif loop.procedureabort

    -- ## 3. POST-PROCESSING (Speichern) ##
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
        sasl.logInfo("Loading new settings")
    end

    if P.needstempinit then
        P.initializeSharedVariables()
        if (P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) then
            VR.initialize(P)
        end
        P.needstempinit = false
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
                sasl.logInfo("Error accessing loop state table for loop index: " .. i)
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

    local currentFmsPhase = get(P.fmsflightphase)
    local timestamp = string.format("[%s]", os.date("%H:%M:%S"))

    if P.flightstate ~= P.lastLoggedFlightstate then
        sasl.logInfo(string.format("%s State Change: Flightstate -> Old: %s, New: %s",
            timestamp, tostring(P.lastLoggedFlightstate), tostring(P.flightstate)))
        P.lastLoggedFlightstate = P.flightstate
    end

    if currentFmsPhase ~= P.lastLoggedFmsFlightphase then
        sasl.logInfo(string.format("%s State Change: FMS Flightphase -> Old: %s, New: %s",
            timestamp, tostring(P.lastLoggedFmsFlightphase), tostring(currentFmsPhase)))
        P.lastLoggedFmsFlightphase = currentFmsPhase
    end

    if P.aircraftwasonground ~= P.lastLoggedAircraftwasonground then
        sasl.logInfo(string.format("%s State Change: AircraftWasOnGround -> Old: %s, New: %s",
            timestamp, tostring(P.lastLoggedAircraftwasonground), tostring(P.aircraftwasonground)))
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
local menu_skip_procedure = sasl.appendMenuItem(P.menu_main, "Skip Procedure", P.skipprocedure)
local menu_abort_procedure = sasl.appendMenuItem(P.menu_main, "Abort Procedure", P.abortprocedure)
sasl.appendMenuSeparator ( P.menu_main )
local menu_speak_depmetar = sasl.appendMenuItem(P.menu_main, "Speak Departure Metar", P.speakdepmetar)
local menu_speak_desmetar = sasl.appendMenuItem(P.menu_main, "Speak Destination Metar", P.speakdesmetar)
sasl.appendMenuSeparator ( P.menu_main )
local menu_cd = sasl.appendMenuItem(P.menu_main, "Cold and Dark Startup", P.coldanddarkstartup)
local menu_cockpit_init = sasl.appendMenuItem(P.menu_main, "Cockpit Initialization", P.cockpitinit)
local menu_apu_start = sasl.appendMenuItem(P.menu_main, "APU Startup", P.apustartup)
local menu_eng_start = sasl.appendMenuItem(P.menu_main, "Engine Startup", P.enginestart)
local menu_before_taxi = sasl.appendMenuItem(P.menu_main, "Before Taxi Procedure", P.beforetaxi)
local menu_before_takeoff = sasl.appendMenuItem(P.menu_main, "Before Takeoff Procedure", P.beforetakeoff)
local menu_after_landing = sasl.appendMenuItem(P.menu_main, "After Landing Procedure", P.afterlanding)
local menu_atparkingposition = sasl.appendMenuItem(P.menu_main, "At Parking Position Procedure", P.atparkingposition)
local menu_eng_stop_ta = sasl.appendMenuItem(P.menu_main, "Turnaround Engine Shutdown", P.turnaroundengineshutdown)
local menu_eng_stop_final = sasl.appendMenuItem(P.menu_main, "Final Engine Shutdown", P.finalengineshutdown)
local menu_shutdown = sasl.appendMenuItem(P.menu_main, "Shutdown", P.shutdown)
sasl.appendMenuSeparator ( P.menu_main )
local menu_above1000 = sasl.appendMenuItem(P.menu_main, "Above 10000", P.altitudea10000)
local menu_below1000 = sasl.appendMenuItem(P.menu_main, "Below 10000", P.altitudeb10000)
local menu_ils_freq = sasl.appendMenuItem(P.menu_main, "Set ILS/GLS Freq/Course", P.setilsproc)
local menu_copy_nav = sasl.appendMenuItem(P.menu_main, "Copy NAV1/MMR1 to NAV2/MMR2", P.copynav)
local menu_set_vref = sasl.appendMenuItem(P.menu_main, "Set Landing Flaps/VREF", P.setvrefproc)
local menu_set_toflaps = sasl.appendMenuItem(P.menu_main, "Set Takeoff Flaps", P.settoflapsproc)

sasl.appendMenuSeparator ( P.menu_main )
local menu_test = sasl.appendMenuItem(P.menu_main, "Tests", P.test)
sasl.appendMenuSeparator ( P.menu_main )
local menu_toggle_setcockpitlights = sasl.appendMenuItem(P.menu_main, "Set Cockpit Lights", P.setcockpitlights)
local menu_toggle_auto = sasl.appendMenuItem(P.menu_main, "Toggle Auto Functions", P.toggleautofunctions)
local menu_toogle_voice = sasl.appendMenuItem(P.menu_main, "Toggle Voice Readback", P.togglevoicereadback)
local menu_toogle_adviceonly = sasl.appendMenuItem(P.menu_main, "Toggle Voice Advice Only", P.toggleadviceonly)
local menu_toogle_freeze = sasl.appendMenuItem(P.menu_main, "Toggle Sim Freeze", P.togglesimfreeze)
local menu_toggle_view = sasl.appendMenuItem(P.menu_main, "Toggle View Changes", P.toggleviewchanges)
local menu_timewarptotod = sasl.appendMenuItem(P.menu_main, "Time Warp to TOD", P.timewarptotod)
local menu_yalreset = sasl.appendMenuItem(P.menu_main, "Reset", P.yalreset)
local menu_yalresetfornewflight = sasl.appendMenuItem(P.menu_main, "Reset for New Flight", P.yalresetForNewFlight)

sasl.appendMenuSeparator ( P.menu_main )

--------------------------------------------------------------------------------------------------------------

function P.enableMenus(enableflag)

    sasl.enableMenuItem(PLUGINS_MENU_ID , menu_master , enableflag)

    sasl.enableMenuItem(P.menu_main , menu_cycleprocedures , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_skip_procedure_step , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_skip_procedure , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_abort_procedure , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_speak_depmetar , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_speak_desmetar , enableflag)

    sasl.enableMenuItem(P.menu_main , menu_cd , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_cockpit_init , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_apu_start , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_eng_start , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_before_taxi , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_before_takeoff , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_after_landing , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_atparkingposition , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_eng_stop_ta , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_eng_stop_final , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_shutdown , enableflag)

    sasl.enableMenuItem(P.menu_main , menu_above1000 , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_below1000 , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_ils_freq , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_copy_nav , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_set_vref , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_set_toflaps , enableflag)

    sasl.enableMenuItem(P.menu_main , menu_test , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_toggle_setcockpitlights , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_toggle_auto , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_toogle_voice , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_toogle_adviceonly , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_toogle_freeze , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_toggle_view , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_timewarptotod , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_yalreset , enableflag)
    sasl.enableMenuItem(P.menu_main , menu_yalresetfornewflight , enableflag)


end

-- P.YalinitGlobal()

return yal
