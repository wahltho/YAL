local P = {}
yal = P -- package name

local def = require("definitions")
require("settings")

--------------------------------------------------------------------------------------------------------------

menu_master = sasl.appendMenuItem(PLUGINS_MENU_ID, def.APPNAMEPREFIXLONG)
P.menu_main = sasl.createMenu("", PLUGINS_MENU_ID, menu_master)

--------------------------------------------------------------------------------------------------------------
-- Flags & Global Variables

function P.YalinitGlobal()

    P.aircraftwasonground = false

    P.updatemetartimer = nil

    P.altitudetimer = nil

    P.pausetodtimer = nil

    P.savetimer = nil

    P.flightstate = 0

    P.apphasils = false

    P.centertankoffset = false

    P.depmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}
    P.desmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}


    --------------------------------------------------------------------------------------------------------------

    P.configvalues = {}

    --------------------------------------------------------------------------------------------------------------

    P.vrefcmdtable = {"del", "clr", "X", "X", "slash", "X", "X", "X", "4R", "exec", "end"}

    P.toflapscmdtable = {"del", "clr", "X", "X", "1L", "exec", "end"}

    --------------------------------------------------------------------------------------------------------------

    P.commandtable = {}

    -------------------------------------------------------------------------------------------------------------- 

    P.navdatatable = {}
    P.navdatatableindex = 0

    P.airportdatatable = {}

    --------------------------------------------------------------------------------------------------------------

    P.ongoingtaskstepindex = 1

    P.procedureloop1 = { lock = def.NOPROCEDURE, stepindex = 0, stepindexprevious = 0, steprepeat = false, lastActiveTime = 0, procedureabort = false, procedureskipstep = false, procedurenotpossible = false, triggeredmanually = false, setonabort = false }
    P.procedureloop2 = { lock = def.NOPROCEDURE, stepindex = 0, stepindexprevious = 0, steprepeat = false, lastActiveTime = 0, procedureabort = false, procedureskipstep = false, procedurenotpossible = false, triggeredmanually = false, setonabort = false }
    P.procedureloop3 = { lock = def.NOPROCEDURE, stepindex = 0, stepindexprevious = 0, steprepeat = false, lastActiveTime = 0, procedureabort = false, procedureskipstep = false, procedurenotpossible = false, triggeredmanually = false, setonabort = false }

    P.proceduretable = {
        [def.COLDANDDARKPROCEDURE] = { number = 1, name = "Cold and Dark Startup", cycable = true, speakname = true, steps = 29, set = false, procedurefunction = P.coldanddarkstartupsteps, loop = 1, prerequisite = nil, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = function() return (get(P.battery) == def.ON) end },
        [def.COCKPITINITPROCEDURE] = { number = 2, name = "Cockpit Initialization", cycable = true, speakname = true, steps = 34, set = false, procedurefunction = P.cockpitinitsteps, loop = 1, prerequisite = def.COLDANDDARKPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = nil },
        [def.APUSTARTUPPROCEDURE] = { number = 3, name = "A P U Startup", cycable = true, speakname = true, steps = 7, set = false, procedurefunction = P.apustartupsteps, loop = 1, prerequisite = def.COCKPITINITPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = function() return (P.apurunning() == def.APUONBUS) end },
        [def.ENGINESTARTPROCEDURE] = { number = 4, name = "Engine Start", cycable = true, speakname = true, steps = 33, set = false , procedurefunction = P.enginestartsteps, loop = 1, prerequisite = def.COCKPITINITPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = function() return P.enginesrunning(def.BOTH) end },
        [def.BEFORETAXIPROCEDURE] = { number = 5, name = "Before Taxi", cycable = true, speakname = true, steps = 30, set = false, procedurefunction = P.beforetaxisteps, loop = 1, prerequisite = def.ENGINESTARTPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = nil },
        [def.BEFORETAKEOFFPROCEDURE] = { number = 6, name = "Before Takeoff", cycable = true, speakname = true, steps = 14, set = false, procedurefunction = P.beforetakeoffsteps, loop = 1, prerequisite = def.BEFORETAXIPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = nil },
        [def.AFTERTAKEOFFPROCEDURE] = { number = 7, name = "After Takeoff", cycable = false, speakname = false, steps = 3, set = false, procedurefunction = P.aftertakeoffsteps, loop = 2, prerequisite = def.BEFORETAKEOFFPROCEDURE, allowedState = def.AIRONLY, requiredFlightstate = def.FLIGHTSTATEINITIALCLIMB, skipCondition = nil },
        [def.DURINGCLIMBPROCEDURE] = { number = 8, name = "During Climb", cycable = false, speakname = false, steps = 13, set = false, procedurefunction = P.duringclimbsteps, loop = 2, prerequisite = nil, allowedState = def.AIRONLY, requiredFlightstate = def.FLIGHTSTATECLIMB, skipCondition = nil },
        [def.ALTITUDEA10000PROCEDURE] = { number = 9, name = "Altitude Above 10000", cycable = true, speakname = false, steps = 7, set = false, procedurefunction = P.altitudea10000steps, loop = 1, prerequisite = nil, allowedState = def.AIRONLY, requiredFlightstate = def.FLIGHTSTATECLIMB, skipCondition = nil },
        [def.DURINGDESCENTPROCEDURE] = { number = 10, name = "During Descent", cycable = false, speakname = false, steps = 10, set = false, procedurefunction = P.duringdescentsteps, loop = 2, prerequisite = nil, allowedState = def.AIRONLY, requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH }, skipCondition = nil },
        [def.ALTITUDEB10000PROCEDURE] = { number = 11, name = "Altitude Below 10000", cycable = true, speakname = false, steps = 12, set = false, procedurefunction = P.altitudeb10000steps, loop = 1, prerequisite = nil, allowedState = def.AIRONLY, requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH }, skipCondition = nil },
        [def.RADIOALTITUDEB2500PROCEDURE] = { number = 12, name = "Altitude Below 2500", cycable = false, speakname = false, steps = 1, set = false, procedurefunction = P.radioaltitudeb2500steps, loop = 1, prerequisite = def.ALTITUDEB10000PROCEDURE, allowedState = def.AIRONLY, requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH }, skipCondition = nil },
        [def.RADIOALTITUDEB1000PROCEDURE] = { number = 13, name = "Altitude Belowe 1000 ", cycable = false, speakname = false, steps = 8, set = false, procedurefunction = P.radioaltitudeb1000steps, loop = 1, prerequisite = def.RADIOALTITUDEB2500PROCEDURE, allowedState = def.AIRONLY, requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH }, skipCondition = nil },
        [def.AFTERLANDINGPROCEDURE] = { number = 14, name = "After Landing", cycable = true, speakname = true, steps = 19, set = false, procedurefunction = P.afterlandingsteps, loop = 1, prerequisite = nil, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEAPPROACH, skipCondition = nil },
        [def.ATPARKINGPOSITIONPROCEDURE] = { number = 15, name = "At Parking Position", cycable = true, speakname = true, steps = 12, set = false, procedurefunction = P.atparkingpositionsteps, loop = 1, prerequisite = def.AFTERLANDINGPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = { def.FLIGHTSTATETAXITOGATE, def.FLIGHTSTATESHUTDOWN }, skipCondition = nil },
        [def.TURNAROUNDENGINESHUTDOWNPROCEDURE] = { number = 16, name = "Turnaround Engine Shutdown", cycable = true, speakname = true, steps = 18, set = false, procedurefunction = P.engineshutdownsteps, loop = 1, prerequisite = def.ATPARKINGPOSITIONPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = nil, skipCondition = function() return not P.enginesrunning(def.BOTH) end },
        [def.FINALENGINESHUTDOWNPROCEDURE] = { number = 17, name = "Final Engine Shutdown", cycable = false, speakname = true, steps = 18, set = false, procedurefunction = P.engineshutdownsteps, loop = 1, prerequisite = def.ATPARKINGPOSITIONPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATESHUTDOWN, skipCondition = function() return not P.enginesrunning(def.BOTH) end },
        [def.SHUTDOWNPROCEDURE] = { number = 18, name = "Shutdown", cycable = true, speakname = true, steps = 24, set = false, procedurefunction = P.shutdownsteps, loop = 1, prerequisite = def.FINALENGINESHUTDOWNPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATESHUTDOWN, skipCondition = nil },
        [def.SETILSPROCEDURE] = { number = 19, name = "Set ILS", cycable = false, speakname = false, steps = 11, set = false, procedurefunction = P.setilssteps, loop = 3, prerequisite = def.ALTITUDEB10000PROCEDURE, allowedState = nil, requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH }, skipCondition = nil },
        [def.SETVREFPROCEDURE] = { number = 20, name = "Set V Ref", cycable = false, speakname = false, steps = 4, set = false, procedurefunction = P.setvrefsteps, loop = 3, prerequisite = def.ALTITUDEB10000PROCEDURE, allowedState = nil, requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH }, skipCondition = nil },
        [def.SETTOFLAPSPROCEDURE] = { number = 21, name = "Set Takeoff Flaps", cycable = false, speakname = false, steps = 4, set = false, procedurefunction = P.settoflapssteps, loop = 3, prerequisite = def.COCKPITINITPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = nil },
        [def.TESTPROCEDURE] = { number = 22, name = "Test", cycable = false, speakname = false, steps = 47, set = false, procedurefunction = P.teststeps, loop = 1, prerequisite = nil, allowedState = nil, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = nil },
    }

    P.lastExecutedLoopIndex = 0
    
    P.loopStateTables = {P.procedureloop1, P.procedureloop2, P.procedureloop3}

    P.previousview = -1

end

--------------------------------------------------------------------------------------------------------------
-- Datarefs

function P.initDataref()

   local dataref_path = def.APPNAMEPREFIX .. "/state/procedureset"

    local handle = globalProperty(dataref_path)

    if not isProperty(handle) then
        sasl.logInfo("Dataref '" .. dataref_path .. "' not found. Creating it now.")
        
        local maxId = 0
        for id, _ in pairs(P.proceduretable) do
            if id > maxId then maxId = id end
        end
        
        P.ProcSetStatusarraydr = createGlobalPropertyia(dataref_path, maxId, false, true, true)
    else
        sasl.logInfo("Found existing dataref: '" .. dataref_path .. "'")
        P.ProcSetStatusarraydr = handle
    end

    sasl.logInfo("Restoring procedure '.set' status from dataref array...")
    for id, proc in pairs(P.proceduretable) do
        local status = get(P.ProcSetStatusarraydr, id)
        proc.set = (status == 1)
    end



    local loopDatarefPaths = { def.APPNAMEPREFIX .. "/state/loop1", def.APPNAMEPREFIX .. "/state/loop2", def.APPNAMEPREFIX .. "/state/loop3"}
    
    P.ProcLoopHandlesdr = {}

    for i = 1, #loopDatarefPaths do
        local path = loopDatarefPaths[i]
        local handle = globalProperty(path)

        if not isProperty(handle) then
            sasl.logInfo("Dataref '" .. path .. "' not found. Creating it now.")
            P.ProcLoopHandlesdr[i] = createGlobalPropertyia(path, 5, false, true, true)
        else
            sasl.logInfo("Found existing dataref: '" .. path .. "'")
            P.ProcLoopHandlesdr[i] = handle
        end
    end

    P.procedureloop1 = P.decodeArrayToLoop(get(P.ProcLoopHandlesdr[1]))
    P.procedureloop2 = P.decodeArrayToLoop(get(P.ProcLoopHandlesdr[2]))
    P.procedureloop3 = P.decodeArrayToLoop(get(P.ProcLoopHandlesdr[3]))

    P.loopStateTables = { P.procedureloop1, P.procedureloop2, P.procedureloop3 }

    sasl.logInfo("YAL: Procedure loop states restored from datarefs.")

    local path = def.APPNAMEPREFIX .. "/state/ongoingtaskstepindex"
    local handle = globalProperty(path)

    if not isProperty(handle) then
        sasl.logInfo("Dataref '" .. path .. "' not found. Creating it now.")
        P.drOngoingTaskIndex = createGlobalPropertyi(path, 1, false, true, true)
    else
        sasl.logInfo("Found existing dataref: '" .. path .. "'")
        P.drOngoingTaskIndex = handle
    end

    P.ongoingtaskstepindex = get(P.drOngoingTaskIndex)
    if P.ongoingtaskstepindex == 0 then
        P.ongoingtaskstepindex = 1
    end

    sasl.logInfo("YAL: Ongoing task index restored to: " .. P.ongoingtaskstepindex)

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

    P.speedrestr = globalProperty("laminar/B738/autopilot/fmc_descent_r_speed1")

    P.vref = globalProperty("laminar/B738/FMS/vref")
    P.vref15 = globalProperty("laminar/B738/FMS/vref_15")
    P.vref25 = globalProperty("laminar/B738/FMS/vref_25")
    P.vref30 = globalProperty("laminar/B738/FMS/vref_30")
    P.vref40 = globalProperty("laminar/B738/FMS/vref_40")

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

    if sasl.findPluginBySignature("SRS.X-Camera") == NO_PLUGIN_ID then
        P.xcamerastatus = nil
        sasl.logInfo("X-Camera not installed")
    else
        P.xcamerastatus = globalProperty("SRS/X-Camera/integration/overall_status")
        sasl.logInfo("X-Camera installed")
    end

    if P.YANSHisinstalled() then
        P.YANSHFuelAlternateBurn = globalProperty("YANSH/sb/fuel/alternate_burn")
        P.YANSHFuelEnrouteBurn = globalProperty("YANSH/sb/fuel/enroute_burn")
        P.YANSHFuelMinTakeoff = globalProperty("YANSH/sb/fuel/min_takeoff")
        P.YANSHFuelPlanRamp = globalProperty("YANSH/sb/fuel/plan_ramp")
        P.YANSHFuelReserve = globalProperty("YANSH/sb/fuel/reserve")
        P.YANSHGeneralInitialAltitude = globalProperty("YANSH/sb/general/initial_altitude")
        P.YANSHGeneralMaxAltitude = globalProperty("YANSH/sb/general/max_altitude")
        P.YANSHParamsUnitsFlag = globalProperty("YANSH/sb/params/units_flag")
    end

    --------------------------------------------------------------------------------------------------------------
    -- Variables for Monitor Switches Function, etc.

    set(P.n1setsource, 0)

    P.apgoaroundtemp = get(P.apgoaround)

    P.cabincruisealttemp = get(P.cabincruisealt)
    P.cabincruisealttemp2 = get(P.cabincruisealt)
    P.cabinlandingalttemp = get(P.cabinlandingalt)
    P.cabinlandingalttemp2 = get(P.cabinlandingalt)

    P.mcpspeedtemp = get(P.mcpspeed)
    P.mcpspeedtemp2 = get(P.mcpspeed)

    P.mcpheadingtemp = get(P.mcpheading)
    P.mcpheadingtemp2 = get(P.mcpheading)

    P.mcpaltitudetemp = get(P.mcpaltitude)
    P.mcpaltitudetemp2 = get(P.mcpaltitude)

    P.mcpvsspeedtemp = get(P.mcpvsspeed)
    P.mcpvsspeedtemp2 = get(P.mcpvsspeed)

    P.desrwyheadingtemp = get(P.desrwyheading)
    P.desrwylatstartpostemp = get(P.desrwylatstartpos)
    P.desrwylonstartpostemp = get(P.desrwylonstartpos)
    P.desrwylatendpostemp = get(P.desrwylatendpos)
    P.desrwylonendpostemp = get(P.desrwylonendpos)

    P.flapleverpostemp = get(P.flapleverpos)
    P.flapleverpostemp2 = get(P.flapleverpos)
    P.gearhandlepostemp = get(P.gearhandlepos)
    P.speedbrakelevertemp = get(P.speedbrakelever)
    P.speedbrakelevertemp2 = get(P.speedbrakelever)
    P.parkingbrakepostemp = get(P.parkingbrakepos)
    P.autobrakepostemp = get(P.autobrakepos)
    P.autobrakedisarmtemp = get(P.autobrakedisarm)
    P.autobrakedisarmtemp2 = get(P.autobrakedisarm)

    P.aponstattemp = get(P.aponstat)

    P.apcmdastattemp = get(P.apcmdastat)
    P.apcmdbstattemp = get(P.apcmdbstat)

    P.apvnavstattemp = get(P.apvnavstat)
    P.aplnavstattemp = get(P.aplnavstat)
    P.apappstattemp = get(P.apappstat)
    P.apvorlocstattemp = get(P.apvorlocstat)
    P.apalthldstattemp = get(P.apalthldstat)
    P.aphdgselstattemp = get(P.aphdgselstat)
    P.apvsstattemp = get(P.apvsstat)
    P.aplvlchgstattemp = get(P.aplvlchgstat)

    P.apgscapturedstattemp = get(P.apgscapturedstat)
    P.aploccapturedstattemp = get(P.aploccapturedstat)
    P.apflarestattemp = get(P.apflarestat)
    P.aprolloutstattemp = get(P.aprolloutstat)

    P.aplpvgscapturedstattemp = get(P.aplpvgscapturedstat)
    P.aplpvloccapturedstattemp = get(P.aplpvloccapturedstat)

    P.apglsgscapturedstattemp = get(P.apglsgscapturedstat)
    P.apglsloccapturedstattemp = get(P.apglsloccapturedstat)

    P.apfacgscapturedstattemp = get(P.apfacgscapturedstat)
    P.apfacloccapturedstattemp = get(P.apfacloccapturedstat)

    P.atarmpostemp = get(P.atarmpos)
    P.atn1stattemp = get(P.atn1stat)
    P.atspeedstattemp = get(P.atspeedstat)
    P.atspeedintvstattemp = get(P.atspeedintvstat)

    P.nav1freqtemp = get(P.nav1freq)
    P.nav2freqtemp = get(P.nav2freq)

    P.mcppilotcoursetemp = get(P.mcppilotcourse)
    P.mcppilotcoursetemp2 = get(P.mcppilotcourse)
    P.mcpcopilotcoursetemp = get(P.mcpcopilotcourse)
    P.mcpcopilotcoursetemp2 = get(P.mcpcopilotcourse)

    P.mmrcptactmodetemp = get(P.mmrcptactmode)
    P.mmrcptactvaluetemp = get(P.mmrcptactvalue)
    P.mmrcptstdbymodetemp = get(P.mmrcptstdbymode)
    P.mmrcptstdbymodetemp2 = get(P.mmrcptstdbymode)
    P.mmrfoactmodetemp = get(P.mmrfoactmode)
    P.mmrfoactvaluetemp = get(P.mmrfoactvalue)
    P.mmrfostdbymodetemp = get(P.mmrfostdbymode)
    P.mmrfostdbymodetemp2 = get(P.mmrfostdbymode)

    P.bankanglepostemp = get(P.bankanglepos)
    P.bankanglepostemp2 = get(P.bankanglepos)

    P.barostdtemp = get(P.barostd)
    P.baropilottemp = get(P.baropilot)
    P.baropilottemp2 = get(P.baropilot)

    P.fdpilotpostemp = get(P.fdpilotpos)
    P.fdfopostemp = get(P.fdfopos)

    P.efiswxpilotpostemp = get(P.efiswxpilotpos)
    P.efiswxfopostemp = get(P.efiswxfopos)
    P.efisterrpilotpostemp = get(P.efisterrpilotpos)
    P.efisterrfopostemp = get(P.efisterrfopos)
    P.efisdatapilotpostemp = get(P.efisdatapilotpos)
    P.efisdatafopostemp = get(P.efisdatafopos)
    P.efisfixpilotpostemp = get(P.efisfixpilotpos)
    P.efisfixfopostemp = get(P.efisfixfopos)
    P.efisairportpilotpostemp = get(P.efisairportpilotpos)
    P.efisairportfopostemp = get(P.efisairportfopos)
    P.efispospilotpostemp = get(P.efispospilotpos)
    P.efisposfopostemp = get(P.efisposfopos)
    P.efisvorpilotpostemp = get(P.efisvorpilotpos)
    P.efisvorfopostemp = get(P.efisvorfopos)

    P.dhpilottemp = get(P.dhpilot)
    P.dhpilottemp2 = get(P.dhpilot)

    P.batterytemp = get(P.battery)
    P.emergencylightstemp = get(P.emergencylights)

    P.starter1postemp = get(P.starter1pos)
    P.starter2postemp = get(P.starter2pos)

    P.mixture1postemp = get(P.mixture1pos)
    P.mixture2postemp = get(P.mixture2pos)

    P.reverser1postemp = get(P.reverser1pos)
    P.reverser2postemp = get(P.reverser2pos)

    P.packlpostemp = get(P.packlpos)
    P.packrpostemp = get(P.packrpos)
    P.bleedair1postemp = get(P.bleedair1pos)
    P.bleedair2postemp = get(P.bleedair2pos)
    P.bleedairapupostemp = get(P.bleedairapupos)
    P.trimairpostemp = get(P.trimairpos)
    P.isolvalvepostemp = get(P.isolvalvepos)
    P.lrecircfanpostemp = get(P.lrecircfanpos)
    P.rrecircfanpostemp = get(P.rrecircfanpos)

    P.gpuontemp = get(P.gpuon)

    P.apustarterpostemp = get(P.apustarterpos)
    P.announcsourceoff1temp = get(P.announcsourceoff1)
    P.announcsourceoff2temp = get(P.announcsourceoff2)

    P.gen1postemp = get(P.gen1pos)
    P.gen2postemp = get(P.gen2pos)

    P.hydro1postemp = get(P.hydro1pos)
    P.hydro2postemp = get(P.hydro2pos)
    P.elechydro1postemp = get(P.elechydro1pos)
    P.elechydro2postemp = get(P.elechydro2pos)

    P.totalfuellbstemp = get(P.totalfuellbs)
    P.totalfuellbstemp2 = get(P.totalfuellbs)

    P.centertanklswitchtemp = get(P.centertanklswitch)
    P.centertankrswitchtemp = get(P.centertankrswitch)
    P.lefttanklswitchtemp = get(P.lefttanklswitch)
    P.lefttankrswitchtemp = get(P.lefttankrswitch)
    P.righttanklswitchtemp = get(P.righttanklswitch)
    P.righttankrswitchtemp = get(P.righttankrswitch)

    P.taxilighttemp = get(P.taxilight)
    P.beaconlightstemp = get(P.beaconlights)
    P.llightsontemp = get(P.llightson)
    P.llights1temp = get(P.llights1)
    P.llights2temp = get(P.llights2)
    P.llights3temp = get(P.llights3)
    P.llights4temp = get(P.llights4)
    P.rwylightltemp = get(P.rwylightl)
    P.rwylightrtemp = get(P.rwylightr)
    P.positionlightstemp = get(P.positionlights)
    P.logolightontemp = get(P.logolighton)

    P.transponderpostemp = get(P.transponderpos)

    P.captainprobepostemp = get(P.captainprobepos)
    P.foprobepostemp = get(P.foprobepos)

    P.wheatlfwdpostemp = get(P.wheatlfwdpos)
    P.wheatrfwdpostemp = get(P.wheatrfwdpos)
    P.wheatlsidepostemp = get(P.wheatlsidepos)
    P.wheatrsidepostemp = get(P.wheatrsidepos)

    P.yawdamperswitchtemp = get(P.yawdamperswitch)

    P.domelightpostemp = get(P.domelightpos)
    P.seatbeltsignpostemp = get(P.seatbeltsignpos)
    P.nosmokingsignpostemp = get(P.nosmokingsignpos)

    P.irsleftpostemp = get(P.irsleftpos)
    P.irsleftpostemp2 = get(P.irsleftpos)
    P.irsrightpostemp = get(P.irsrightpos)
    P.irsrightpostemp2 = get(P.irsrightpos)

    P.lwiperpostemp = get(P.lwiperpos)
    P.lwiperpostemp2 = get(P.lwiperpos)
    P.rwiperpostemp = get(P.rwiperpos)
    P.rwiperpostemp2 = get(P.rwiperpos)

    P.transpondercodetemp = get(P.transpondercode)
    P.transpondercodetemp2 = get(P.transpondercode)

    P.pausetodtemp = get(P.pausetod)
    P.simfreezedtemp = get(P.simfreezed)

    P.chockstatustmp = get(P.chockstatus)

end

-------------------------------------------------------------------------------------------------------------- 
function P.YANSHisinstalled()
    if P.YANSHPluginID == nil then
        local yanshSignature = "1-sim YANSH"
        P.YANSHPluginID = sasl.findPluginBySignature(yanshSignature)
        
        if P.YANSHPluginID ~= NO_PLUGIN_ID then
            sasl.logInfo("YANSH plugin found, integration enabled.")
        end
    end
    
    return (P.YANSHPluginID ~= NO_PLUGIN_ID)
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

        local difference = math.abs(currentFuelLbs - plannedFuelLbs)

        if difference > 200 then
            local plannedForDisplay
            local currentForDisplay
            local unitForDisplay

            if (get(P.fuelunit) == def.KG) then
                plannedForDisplay = helpers.roundnumber(plannedFuelLbs * def.LBSTOKG)
                currentForDisplay = helpers.roundnumber(currentFuelLbs * def.LBSTOKG)
                unitForDisplay = "K G"
            else
                plannedForDisplay = helpers.roundnumber(plannedFuelLbs)
                currentForDisplay = helpers.roundnumber(currentFuelLbs)
                unitForDisplay = "L B S"
            end

            local message = "Warning: Fuel discrepancy. Planned " .. plannedForDisplay .. ", actual " .. currentForDisplay .. " " .. unitForDisplay .. "."
            P.commandtableentry(def.TEXT, message)
            
            return false
        end

        return true
    end
end

--------------------------------------------------------------------------------------------------------------
function P.initializeScript()

    P.YalinitGlobal()
    P.initDataref()
    P.readconfig()
    helpers.buildnavdatatable(P.navdatatable)

    if (sasl.getLogLevel() == LOG_DEBUG) then
        helpers.writenavdatatable(P.navdatatable)
    end

    P.commandtableentry(def.TEXT, "YAL Initialization done")

    sasl.logInfo("Initialization and state restored")

    P.lastLoggedFlightstate = P.flightstate
    P.lastLoggedFmsFlightphase = get(P.fmsflightphase)
    P.lastLoggedAircraftwasonground = P.aircraftwasonground
end

--------------------------------------------------------------------------------------------------------------
function P.yalreset()
    
    P.YalinitGlobal() 
    P.initDataref()
    P.readconfig()

    P.synchronizeProcedureStates() 
    
    local statusArray = P.encodeProcedureSetStatusToArray()
    set(P.drProcSetStatus_array, statusArray)

    helpers.buildnavdatatable(P.navdatatable)

    if (sasl.getLogLevel() == LOG_DEBUG) then
        helpers.writenavdatatable(P.navdatatable)
    end

    P.commandtableentry(def.TEXT, "Reset and Synchronization with aircraft done")

    sasl.logInfo("Manual YAL Reset initiated")

    P.lastLoggedFlightstate = P.flightstate
    P.lastLoggedFmsFlightphase = get(P.fmsflightphase)
    P.lastLoggedAircraftwasonground = P.aircraftwasonground
end

function P.yalreset_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.yalreset()
    end
    return 0
end

my_command_yalreset = sasl.createCommand(def.APPNAMEPREFIX .. "/yalreset", "Reset YAL")
sasl.registerCommandHandler(my_command_yalreset, 0, P.yalreset_)

--------------------------------------------------------------------------------------------------------------
function P.readconfig()

    P.configvalues = settings.getSettings()

    P.remainingtimetoquit = P.configvalues[def.CONFIGTODPAUSEQUITTIME]
    P.remainingtimetosave = P.configvalues[def.CONFIGSAVETIME]
    if (P.configvalues[def.CONFIGWAKEOVERRIDE] == def.ON) then
        set(P.wakeoverride, def.ON)
    else
        set(P.wakeoverride, def.OFF)
    end
    P.lowerairspacealt = P.configvalues[def.CONFIGLOWEAIRSPACEALT]

    return true

end

function P.readconfig_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.readconfig()
    end
    return 0
end

my_command_readconfig = sasl.createCommand(def.APPNAMEPREFIX .. "/readconfig", "Read Config File")
sasl.registerCommandHandler(my_command_readconfig, 0, P.readconfig_)

--------------------------------------------------------------------------------------------------------------
function P.setview(view)

    if ((P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) and ((get(P.tirespeed) < 1) or (get(P.airgroundsensor == def.OFF)))) then
        if ((view == nil) or (type(view) ~= "number") or (view ~= math.floor(view))) then
            sasl.logError("Invalid input to setview")
            return false
        end

        if (view ~= P.previousview) then
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
        else
            sasl.logDebug("View #" .. view .. " already set")
        end
    end

    return true
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
        newentryindex = #P.commandtable + 1
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

my_command_togglesimfreeze = sasl.createCommand(def.APPNAMEPREFIX .. "/togglesimfreeze", "Toggle Freeze Sim")
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

    local localpositionx, localpositiony, localpositionz = helpers.worldtolocal(warppoint.latitude, warppoint.longitude, get(P.cabincruisealt) / def.FEETTOMETER)

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

my_command_timewarptotod = sasl.createCommand(def.APPNAMEPREFIX .. "/timewarptotod", "Time Warp to TOD")
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

my_command_toggleautofunctions = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleautofunctions", "Toggle Auto Functions")
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

my_command_toggleviewchanges = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleviewchanges", "Toggle View Changes")
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

my_command_toggleadviceonly = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleadviceonly", "Toggle def.TEXT Only")
sasl.registerCommandHandler(my_command_toggleadviceonly, 0, P.toggleadviceonly_)

--------------------------------------------------------------------------------------------------------------
function P.abortprocedure()
    local mostRecentLoop = nil
    local latestTime = 0

    for i, loopObj in ipairs(P.loopStateTables) do
        if loopObj.lock ~= def.NOPROCEDURE and loopObj.lastActiveTime > latestTime then
            latestTime = loopObj.lastActiveTime
            mostRecentLoop = loopObj
        end
    end

    if mostRecentLoop then
        mostRecentLoop.procedureabort = true
        mostRecentLoop.procedureskipstep = false
    end

    return true
end

function P.abortprocedure_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.abortprocedure()
    end
    return 0
end

my_command_abortprocedure = sasl.createCommand(def.APPNAMEPREFIX .. "/abortprocedure", "Abort Procedure")
sasl.registerCommandHandler(my_command_abortprocedure, 0, P.abortprocedure_)

--------------------------------------------------------------------------------------------------------------
function P.skipprocedurestep()
    local mostRecentLoop = nil
    local latestTime = 0

    for i, loopObj in ipairs(P.loopStateTables) do
        if loopObj.lock ~= def.NOPROCEDURE and loopObj.lastActiveTime > latestTime then
            latestTime = loopObj.lastActiveTime
            mostRecentLoop = loopObj
        end
    end

    if mostRecentLoop then
        mostRecentLoop.procedureskipstep = true
        mostRecentLoop.procedureabort = false
    end

    return true
end

function P.skipprocedurestep_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.skipprocedurestep()
    end
    return 0
end

my_command_skipprocedurestep = sasl.createCommand(def.APPNAMEPREFIX .. "/skipprocedurestep", "Skip Procedure Step")
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

my_command_mastercaution = sasl.createCommand(def.APPNAMEPREFIX .. "/mastercaution", "Master Caution + FMS CLR")
sasl.registerCommandHandler(my_command_mastercaution, 0, P.mastercaution_)


--------------------------------------------------------------------------------------------------------------

function P.speakdesmetar()

    if P.desmetar.metarfound then
            P.commandtableentry(def.TEXT, helpers.formatMetarSpeechSummary(P.desmetar))
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

my_command_speakdesmetar = sasl.createCommand(def.APPNAMEPREFIX .. "/speakdesmetar", "Speak Destination Metar")
sasl.registerCommandHandler(my_command_speakdesmetar, 0, P.speakdesmetar_)
 
--------------------------------------------------------------------------------------------------------------
function P.speakdepmetar()

    if P.depmetar.metarfound then
            P.commandtableentry(def.TEXT, helpers.formatMetarSpeechSummary(P.depmetar))
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

my_command_speakdepmetar = sasl.createCommand(def.APPNAMEPREFIX .. "/speakdepmetar", "Speak Departure Metar")
sasl.registerCommandHandler(my_command_speakdepmetar, 0, P.speakdepmetar_)


--------------------------------------------------------------------------------------------------------------
function P.triggerprocedure(procedureKey, isManual)
    isManual = isManual or false

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
            if isManual then
                P.commandtableentry(def.TEXT, procedureData.name .. " Procedure not possible in current flight state.")
            end
            return false
        end
    end

    local aircraftIsOnGround = (get(P.airgroundsensor) == def.ON)
    local allowedState = procedureData.allowedState
    if allowedState then
        if allowedState == def.GROUNDONLY and not aircraftIsOnGround then
            if isManual then
                P.commandtableentry(def.TEXT, procedureData.name .. " Procedure can only be executed on the ground.")
            end
            return false
        elseif allowedState == def.AIRONLY and aircraftIsOnGround then
            if isManual then
                P.commandtableentry(def.TEXT, procedureData.name .. " Procedure can only be executed in the air.")
            end
            return false
        end
    end

    local prerequisiteKey = procedureData.prerequisite
    if prerequisiteKey then
        local prerequisiteData = P.proceduretable[prerequisiteKey]
        if not prerequisiteData.set then
            if isManual then
                local message = procedureData.name .. " Procedure not possible, execute " .. prerequisiteData.name .. " Procedure first."
                P.commandtableentry(def.TEXT, message)
            end
            return false
        end
    end

    if not isManual and procedureData.set then
        return true
    end

    local loopIndex = procedureData.loop
    local targetLoopObject = P[def.PROCEDURELOOP .. loopIndex]

    if not targetLoopObject then
        return false
    end
    
    if targetLoopObject.lock == def.NOPROCEDURE then
        targetLoopObject.lock = procedureKey
        targetLoopObject.triggeredmanually = isManual 
        return true
    else
        return false
    end
end

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
        if procedure.data.cycable and not procedure.data.set then
            local skipFunc = procedure.data.skipCondition
            if skipFunc and skipFunc() then
                procedure.data.set = true
                sasl.logInfo("Skipping " .. procedure.data.name .. " Procedure as its skip condition is met.")
            else
                sasl.logInfo("Next Procedure is: " .. procedure.data.name)
                P.procedureloop1.lock = procedure.originalKey
                return true
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

my_command_cycleprocedures = sasl.createCommand(def.APPNAMEPREFIX .. "/cycleprocedures", "Cycle Through Procedures")
sasl.registerCommandHandler(my_command_cycleprocedures, 0, P.cycleprocedures_)

--------------------------------------------------------------------------------------------------------------
function P.refuelAircraft(totalFuelLbs)

    if type(totalFuelLbs) ~= "number" or totalFuelLbs < 0 then
        P.commandtableentry(def.TEXT, "Refueling failed: Invalid fuel amount specified.")
        return false
    end

    local currentLeftLbs = get(P.lefttanklbs)
    local currentRightLbs = get(P.righttanklbs)
    local currentCenterLbs = get(P.centertanklbs)
    local currentTotalFuel = currentLeftLbs + currentRightLbs + currentCenterLbs

    if totalFuelLbs > def.MAXTOTALLBS then
        P.commandtableentry(def.TEXT, "Requested fuel exceeds maximum capacity. Fueling to max.")
        totalFuelLbs = def.MAXTOTALLBS
    end

    local leftTank, rightTank, centerTank
    local isDefueling = (totalFuelLbs < currentTotalFuel)

    if totalFuelLbs <= (def.MAXWINGTANKLBS * 2) then
        leftTank = totalFuelLbs / 2
        rightTank = totalFuelLbs / 2
        centerTank = 0
    else
        leftTank = def.MAXWINGTANKLBS
        rightTank = def.MAXWINGTANKLBS
        centerTank = totalFuelLbs - (def.MAXWINGTANKLBS * 2)
    end

    if isDefueling and currentCenterLbs > 1000 and centerTank < 1000 then
        local deficit = 1000 - centerTank
        centerTank = 1000
        leftTank = leftTank - (deficit / 2)
        rightTank = rightTank - (deficit / 2)
    end

    set(P.fueltank1, leftTank * def.LBSTOKG)
    set(P.fueltank2, centerTank * def.LBSTOKG)
    set(P.fueltank3, rightTank * def.LBSTOKG)

    local totalSetFuelLbs = helpers.roundnumber(leftTank + rightTank + centerTank)
    local actionText = isDefueling and "Defueling" or "Refueling"
    
    local fuelForDisplay
    local unitForDisplay

    if (get(P.fuelunit) == def.KG) then
        fuelForDisplay = helpers.roundnumber(totalSetFuelLbs * def.LBSTOKG)
        unitForDisplay = "K G"
    else
        fuelForDisplay = totalSetFuelLbs
        unitForDisplay = "L B S"
    end
    
    P.commandtableentry(def.TEXT, actionText .. " complete. Total fuel: " .. fuelForDisplay .. " " .. unitForDisplay .. ".")
    
    return true
end

--------------------------------------------------------------------------------------------------------------
function P.synchronizeProcedureStates()
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
function P.encodeLoopToArray(loopTable)
    if not loopTable then return {0, 0, 0, 0, 0} end

    local repeatNum = loopTable.steprepeat and 1 or 0
    local abortNum = loopTable.procedureabort and 1 or 0
    local skipNum = loopTable.procedureskipstep and 1 or 0

    return {
        loopTable.lock or 0,
        loopTable.stepindex or 0,
        repeatNum,
        abortNum,
        skipNum
    }
end

--------------------------------------------------------------------------------------------------------------
function P.decodeArrayToLoop(loadedArray)
    local loop = {
        lock = def.NOPROCEDURE, stepindex = 0, previousstepindex = 0,
        steprepeat = false, procedureabort = false, procedureskipstep = false,
        lastActiveTime = 0, procedurenotpossible = false, setonabort = false
    }

    if type(loadedArray) == "table" and #loadedArray >= 5 then
        loop.lock = loadedArray[1]
        loop.stepindex = loadedArray[2]
        loop.steprepeat = (loadedArray[3] == 1)
        loop.procedureabort = (loadedArray[4] == 1)
        loop.procedureskipstep = (loadedArray[5] == 1)
        loop.previousstepindex = loop.stepindex
    end

    return loop
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

my_command_headingsync = sasl.createCommand(def.APPNAMEPREFIX .. "/headingsync", "Sync AP Heading with Ground Track")
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

my_command_wipersup = sasl.createCommand(def.APPNAMEPREFIX .. "/wipersup", "Both Wipers Up")
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

my_command_wipersdown = sasl.createCommand(def.APPNAMEPREFIX .. "/wipersdownn", "Both Wipers Down")
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

my_command_toggletaxilights = sasl.createCommand(def.APPNAMEPREFIX .. "/toggletaxilights", "Toggle Taxi Lights")
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

my_command_togglecollisionlights = sasl.createCommand(def.APPNAMEPREFIX .. "/togglecollisionlights", "Toggle Collision Lights")
sasl.registerCommandHandler(my_command_togglecollisionlights, 0, P.togglecollisionlights_)

--------------------------------------------------------------------------------------------------------------
function P.togglelandinglights(state)
    if (state == nil) then
        if (get(P.llightson) == def.OFF) then
            if ((get(P.llights1) ~= def.OFF) or (get(P.llights2) ~= def.OFF) or (get(P.llights3) ~= def.OFF) or (get(P.llights4) ~= def.OFF)) then
                helpers.command_once("sim/lights/landing_lights_off")
            else
                helpers.command_once("sim/lights/landing_lights_on")
            end
        else
            helpers.command_once("sim/lights/landing_lights_off")
        end
    elseif (state == def.OFF) then
        helpers.command_once("sim/lights/landing_lights_off")
    elseif (state == def.ON) then
        helpers.command_once("sim/lights/landing_lights_on")
    end

end

function P.togglelandinglights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.togglelandinglights(nil)
    end
    return 0
end

my_command_togglelandinglights = sasl.createCommand(def.APPNAMEPREFIX .. "/togglelandinglights", "Toggle Landing Lights")
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

my_command_togglelogolight = sasl.createCommand(def.APPNAMEPREFIX .. "/togglelogolight", "Toggle Logo Light")
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

my_command_togglerwylights = sasl.createCommand(def.APPNAMEPREFIX .. "/togglerwylights", "Toggle Runway Turnoff Lights")
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

my_command_togglepositionlights = sasl.createCommand(def.APPNAMEPREFIX .. "/togglepositionlights", "Toggle Position Lights")
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

my_command_toggletransponder = sasl.createCommand(def.APPNAMEPREFIX .. "/toggletransponder", "Toggle Transponder Stdby def.TA/RA")
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

my_command_togglefds = sasl.createCommand(def.APPNAMEPREFIX .. "/togglefds", "Toggle Both Flight Directors")
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

my_command_togglewx = sasl.createCommand(def.APPNAMEPREFIX .. "/togglewx", "Toggle Both Weather Radars")
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

my_command_toggleterr = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleterr", "Toggle Both Terrain Radars")
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

my_command_togglewindowheat = sasl.createCommand(def.APPNAMEPREFIX .. "/togglewindowheat", "Toggle Window Heat")
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

my_command_toggleprobeheat = sasl.createCommand(def.APPNAMEPREFIX .. "/toggleprobeheat", "Toggle Probe Heat")
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

my_command_iceprotection = sasl.createCommand(def.APPNAMEPREFIX .. "/iceprotection", "Toggle Ice Protection")
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

my_command_setcockpitlights = sasl.createCommand(def.APPNAMEPREFIX .. "/setcockpitlights", "Set Cockpit Lights")
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

my_command_togglevoicereadback = sasl.createCommand(def.APPNAMEPREFIX .. "/togglevoicereadback", "Toggle Voice Readback")
sasl.registerCommandHandler(my_command_togglevoicereadback, 0, P.togglevoicereadback_)

--------------------------------------------------------------------------------------------------------------
function P.flapsuphandling()

    if ((get(P.airspeed) > get(P.flaps15speed)) and (get(P.airspeed) <= get(P.flaps10speed)) and (get(P.flapleverpos) > def.FLAPS15)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 15")
        else
            helpers.command_once("laminar/B738/push_button/flaps_15")
        end
    elseif ((get(P.airspeed) > get(P.flaps10speed)) and (get(P.airspeed) <= get(P.flaps5speed)) and (get(P.flapleverpos) > def.FLAPS10)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 10")
        else
            helpers.command_once("laminar/B738/push_button/flaps_10")
        end
    elseif ((get(P.airspeed) > get(P.flaps5speed)) and (get(P.airspeed) <= get(P.flaps1speed)) and (get(P.flapleverpos) > def.FLAPS5)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 5")
        else
            helpers.command_once("laminar/B738/push_button/flaps_5")
      end
    elseif ((get(P.airspeed) > get(P.flaps1speed)) and (get(P.airspeed) <= get(P.flapsupspeed)) and (get(P.flapleverpos) > def.FLAPS1)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 1")
        else
            helpers.command_once("laminar/B738/push_button/flaps_1")
        end
    elseif ((get(P.airspeed) > get(P.flapsupspeed)) and (get(P.flapleverpos) > def.FLAPSUP)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps Up")
        else
            helpers.command_once("laminar/B738/push_button/flaps_0")
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
function P.flapsdownhandling()

    if ((get(P.airspeed) < get(P.flapsupspeed)) and (get(P.airspeed) >= get(P.flaps1speed)) and (get(P.flapleverpos) < def.FLAPS1)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 1")
        else
            helpers.command_once("laminar/B738/push_button/flaps_1")
        end
    elseif ((get(P.airspeed) < get(P.flaps1speed)) and (get(P.airspeed) >= get(P.flaps5speed)) and (get(P.flapleverpos) < def.FLAPS5)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 5")
        else
            helpers.command_once("laminar/B738/push_button/flaps_5")
        end
    elseif ((get(P.airspeed) < get(P.flaps5speed)) and (get(P.airspeed) >= get(P.flaps10speed)) and (get(P.flapleverpos) < def.FLAPS10)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 10")
        else
            helpers.command_once("laminar/B738/push_button/flaps_10")
        end
    elseif ((get(P.airspeed) < get(P.flaps10speed)) and (get(P.airspeed) >= get(P.flaps15speed)) and (get(P.flapleverpos) < def.FLAPS15)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 15")
        else
            helpers.command_once("laminar/B738/push_button/flaps_15")
        end
    elseif ((get(P.airspeed) < get(P.flaps15speed)) and (get(P.airspeed) >= get(P.flaps25speed)) and (get(P.flapleverpos) < def.FLAPS25)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 25")
        else
            helpers.command_once("laminar/B738/push_button/flaps_25")
        end
    elseif ((get(P.airspeed) < get(P.flaps25speed)) and (get(P.flapleverpos) < def.FLAPS30)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Set Flaps 30")
        else
            helpers.command_once("laminar/B738/push_button/flaps_30")
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

my_command_copynav = sasl.createCommand(def.APPNAMEPREFIX .. "/copynav", "Copy NAV1/MMR1 to NAV2/MMR2")
sasl.registerCommandHandler(my_command_copynav, 0, P.copynav_)

--------------------------------------------------------------------------------------------------------------
function P.setilssteps(procedureloop)

    local FMC1Line00L = helpers.get("laminar/B738/fmc1/Line00_L")
    local FMC1Line04X = helpers.get("laminar/B738/fmc1/Line04_X")
    local FMC1Line04L = helpers.get("laminar/B738/fmc1/Line04_L")

    local apptype
    local dmestring

    if (procedureloop.stepindex == 1) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWFMS])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if ((string.len(FMC1Line00L) < 9) or (string.sub(FMC1Line00L, 7, 9) ~= "APP")) then
            helpers.command_once("laminar/B738/button/fmc1_init_ref")
            procedureloop.stepindex = procedureloop.stepindex - 1
        end
    end

    if (procedureloop.stepindex == 3) then
        P.navdatatableindex = nil
        if ((string.len(FMC1Line04X) == 24) and (string.len(FMC1Line04L) == 24)) then
            apptype = string.sub(FMC1Line04X, 2, 4)

            if ((apptype == def.NAVTYPEILS) or (apptype == def.NAVTYPEGLS)) then
                P.navdatatableindex = helpers.getnavdataindex(P.navdatatable, get(P.desicao), get(P.desrwy), apptype)
            else
                P.navdatatableindex = helpers.getnavdataindex(P.navdatatable, get(P.desicao), get(P.desrwy), def.NAVTYPELPV)
            end
        else
            P.navdatatableindex = helpers.getnavdataindex(P.navdatatable, get(P.desicao), get(P.desrwy), def.NAVTYPELPV)
        end

        if ((P.navdatatableindex ~= nil) and (P.navdatatable[P.navdatatableindex] ~= nil)) then
            if (get(P.desrwy) ~= P.navdatatable[P.navdatatableindex][def.DESTRWY]) then
                sasl.logInfo("Destination Runway Diff FMC: " .. tostring(get(P.desrwy)) .. " Navdata: " .. totring(P.navdatatable[P.navdatatableindex][def.DESTRWY]))
            end

            if ((P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE] == def.NAVTYPEILS) and P.navdatatable[P.navdatatableindex][def.DESTNAVDME]) then
                dmestring = "with DME"
            else
                dmestring = ""
            end
            P.commandtableentry(def.TEXT, "Runway " .. helpers.formatRunwayDesignator(P.navdatatable[P.navdatatableindex][def.DESTRWY]) .. " has " .. helpers.addspaces(P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE]) .. " Approach " .. dmestring)
            procedureloop.stepindex = 5
            return true
        else
            P.commandtableentry(def.TEXT, "Runway " .. helpers.formatRunwayDesignator(get(P.desrwy)) .. " has no Precision Approach")
            if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
                P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
            end
        end
    end

    if ((procedureloop.stepindex == 4) and (P.navdatatableindex == nil)) then
        local nearestvor = nil
        if (P.airportdatatable[get(P.desicao)] and P.airportdatatable[get(P.desicao)].latitude and P.airportdatatable[get(P.desicao)].longitude) then
            nearestvor = helpers.findnearestvor(P.navdatatable, P.airportdatatable[get(P.desicao)].latitude, P.airportdatatable[get(P.desicao)].longitude)
        elseif helpers.isvalidrwy(get(P.desrwy)) then
            nearestvor = helpers.findnearestvor(P.navdatatable, get(P.desrwylatstartpos), get(P.desrwylonstartpos))
        end          
        if (nearestvor == nil) then
            P.commandtableentry(def.TEXT, "No V O R near " .. helpers.addspaces(get(P.desicao)) .. " found")
        else
            P.commandtableentry(def.TEXT, "Nearest V O R for " .. helpers.addspaces(get(P.desicao)) .. " is " .. helpers.addspaces(nearestvor.navid) .. " with frequency " .. helpers.addspaces(helpers.formatILSFrequency(nearestvor.frequency)))
        end
    end

    if ((procedureloop.stepindex == 5) and (P.navdatatableindex == nil)) then            
        P.commandtableentry(def.TEXT, "Runway " .. helpers.formatRunwayDesignator(get(P.desrwy)) .. " has heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(helpers.roundnumber(get(P.desrwyheading)), 3)))
        procedureloop.stepindex = 11
        return true
    end

    if ((procedureloop.stepindex == 6) and (P.navdatatableindex ~= nil)) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWPEDESTAL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if ((procedureloop.stepindex == 7) and (P.navdatatableindex ~= nil)) then
        if (P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE] == def.NAVTYPEILS) then
            if ((get(P.nav1freq) ~= P.navdatatable[P.navdatatableindex][def.DESTFREQ]) or ((get(P.mmrinstalled) == def.ON) and ((get(P.mmrcptactvalue) ~= P.navdatatable[P.navdatatableindex][def.DESTFREQ]) or (get(P.mmrcptactmode) ~= def.MMRILS)))) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Captain Frequency " .. helpers.addspaces(helpers.formatILSFrequency(P.navdatatable[P.navdatatableindex][def.DESTFREQ])))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    if (get(P.mmrinstalled) == def.ON) then
                        P.setmmrils(def.MMRCAPTAIN, P.navdatatable[P.navdatatableindex][def.DESTFREQ])
                    else
                        set(P.nav1stdbyfreq, get(P.nav1freq))
                        set(P.nav1freq, P.navdatatable[P.navdatatableindex][def.DESTFREQ])
                    end
                end
            elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)  and (not procedureloop.steprepeat)) then
                P.commandtableentry(def.TEXT, "Captain Frequency checked and " .. helpers.addspaces(helpers.formatILSFrequency(P.navdatatable[P.navdatatableindex][def.DESTFREQ])))
            end
        end

        if (((P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE] == def.NAVTYPEGLS) or (P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE] == def.NAVTYPELPV)) and (get(P.mmrinstalled) == def.ON)) then
            if ((get(P.mmrcptactvalue) ~= P.navdatatable[P.navdatatableindex][def.DESTFREQ]) or not ((get(P.mmrcptactmode) ~= def.MMRGLS) or (get(P.mmrcptactmode) ~= def.MMRLPV))) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Captain Channel " .. helpers.addspaces(P.navdatatable[P.navdatatableindex][def.DESTFREQ]))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    P.setmmrgls(def.MMRCAPTAIN, P.navdatatable[P.navdatatableindex][def.DESTFREQ])
                end
            elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)  and (not procedureloop.steprepeat)) then
                P.commandtableentry(def.TEXT, "Captain Channel checked and " .. helpers.addspaces(P.navdatatable[P.navdatatableindex][def.DESTFREQ]))
            end
        end
    end

    if ((procedureloop.stepindex == 8)  and (P.navdatatableindex ~= nil)) then
        if ((P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE] == def.NAVTYPEILS) and P.navdatatable[P.navdatatableindex][def.DESTNAVDME]) then
            if ((get(P.nav2freq) ~= P.navdatatable[P.navdatatableindex][def.DESTFREQ]) or ((get(P.mmrinstalled) == def.ON) and ((get(P.mmrfoactvalue) ~= (P.navdatatable[P.navdatatableindex][def.DESTFREQ])) or (get(P.mmrfoactmode) ~= def.MMRILS)))) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Copilot Frequency " .. helpers.addspaces(helpers.formatILSFrequency(P.navdatatable[P.navdatatableindex][def.DESTFREQ])))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    if (get(P.mmrinstalled) == def.ON) then
                        P.setmmrils(def.MMRFO, P.navdatatable[P.navdatatableindex][def.DESTFREQ])
                    else
                        set(P.nav2stdbyfreq, get(P.nav2freq))
                        set(P.nav2freq, P.navdatatable[P.navdatatableindex][def.DESTFREQ])
                    end
                end
            elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)  and (not procedureloop.steprepeat)) then
                P.commandtableentry(def.TEXT, "Copilot Frequency checked and " .. helpers.addspaces(helpers.formatILSFrequency(P.navdatatable[P.navdatatableindex][def.DESTFREQ])))
            end
        end

        if ((P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE] == def.NAVTYPEGLS) and (get(P.mmrinstalled) == def.ON)) then
            if ((get(P.mmrfoactvalue) ~= P.navdatatable[P.navdatatableindex][def.DESTFREQ]) or (get(P.mmrfoactmode) ~= def.MMRGLS)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Copilot Channel " .. helpers.addspaces(P.navdatatable[P.navdatatableindex][def.DESTFREQ]))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    P.setmmrgls(def.MMRFO, P.navdatatable[P.navdatatableindex][def.DESTFREQ])
                end
            elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)  and (not procedureloop.steprepeat)) then
                P.commandtableentry(def.TEXT, "Copilot Channel checked and " .. helpers.addspaces(P.navdatatable[P.navdatatableindex][def.DESTFREQ]))
            end
        end
    end

    if ((procedureloop.stepindex == 9)  and (P.navdatatableindex ~= nil)) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if ((procedureloop.stepindex == 10)  and (P.navdatatableindex ~= nil)) then
        pilotcoursenew = P.navdatatable[P.navdatatableindex][def.DESTCOURSE]

        if (get(P.mcppilotcourse) ~= pilotcoursenew) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Captain Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(pilotcoursenew, 3)))
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.mcppilotcourse, pilotcoursenew)
            end
        elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)  and (not procedureloop.steprepeat)) then
            P.commandtableentry(def.TEXT, "Captain Course checked and " .. helpers.addspaces(helpers.padNumberWithZerosStrict(pilotcoursenew, 3)))
        end
    end

    if ((procedureloop.stepindex == 11)  and (P.navdatatableindex ~= nil)) then
        if ((P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE] == def.NAVTYPEILS) and P.navdatatable[P.navdatatableindex][def.DESTNAVDME]) then
            if (get(P.mcpcopilotcourse) ~= get(P.mcppilotcourse)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Copilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcppilotcourse), 3)))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    set(P.mcpcopilotcourse, get(P.mcppilotcourse))
                end
            elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)  and (not procedureloop.steprepeat)) then
                P.commandtableentry(def.TEXT, "Copilot Course checked and " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcppilotcourse), 3)))
            end
        end

        if ((P.navdatatable[P.navdatatableindex][def.DESTNAVTYPE] == def.NAVTYPEGLS) and (get(P.mmrinstalled) == def.ON)) then
            if (get(P.mcpcopilotcourse) ~= get(P.mcppilotcourse)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Copilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcppilotcourse), 3)))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    set(P.mcpcopilotcourse, get(P.mcppilotcourse))
                end
            elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)  and (not procedureloop.steprepeat)) then
                P.commandtableentry(def.TEXT, "Copilot Course checked and " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcppilotcourse), 3)))
            end
        end
    end

    return true

end

function P.setilsproc()

    return P.triggerprocedure(def.SETILSPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.setilsproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.setilsproc()
    end
    return 0
end

my_command_setils = sasl.createCommand(def.APPNAMEPREFIX .. "/setils", "Set ILS/GLS Frequency and Course")
sasl.registerCommandHandler(my_command_setils, 0, P.setilsproc_)


--------------------------------------------------------------------------------------------------------------
function P.setvrefsteps(procedureloop)

    local FMC1Line00L = helpers.get("laminar/B738/fmc1/Line00_L")

    local appflapscalc, appvrefcalc = helpers.calcappflapsvref(get(P.totalweightkgs), get(P.desrwylen), get(P.desrwyheading), get(P.vref30), P.desmetar)
    local appflapscalcstring = tostring(appflapscalc)
    local appvrefcalcstring = tostring(appvrefcalc)

    if (procedureloop.stepindex == 1) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWFMS])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if ((string.len(FMC1Line00L) < 9) or (string.sub(FMC1Line00L, 7, 9) ~= "APP")) then
            helpers.command_once("laminar/B738/button/fmc1_init_ref")
            procedureloop.stepindex = procedureloop.stepindex - 1
        end
    end

    if (procedureloop.stepindex == 3) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            if (get(P.vref) ~= appvrefcalc) then
                P.vrefcmdtable[3] = string.sub(appflapscalcstring, 1, 1)
                P.vrefcmdtable[4] = string.sub(appflapscalcstring, 2, 2)
                P.vrefcmdtable[6] = string.sub(appvrefcalcstring, 1, 1)
                P.vrefcmdtable[7] = string.sub(appvrefcalcstring, 2, 2)
                P.vrefcmdtable[8] = string.sub(appvrefcalcstring, 3, 3)

                local tableindex = 1
                while (P.vrefcmdtable[tableindex] ~= "end") do
                    sasl.logDebug("while loop setvref")
                    P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. P.vrefcmdtable[tableindex])
                    tableindex = tableindex + 1
                end

                P.commandtableentry(def.TEXT, "V REF " .. appflapscalc .. " " .. appvrefcalc .. " Knots set")
            end
        end

        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.vref) ~= appvrefcalc) then
                P.commandtableentry(def.TEXT, "Set V REF " .. appflapscalc .. " " .. appvrefcalc)
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif not procedureloop.steprepeat then
                P.commandtableentry(def.TEXT, "V REF " .. appflapscalc .. " checked and " .. appvrefcalc)
            end
        end
    end

    if (procedureloop.stepindex == 4) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true
end

function P.setvrefproc()

    return P.triggerprocedure(def.SETVREFPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.setvrefproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.setvrefproc()
    end
    return 0
end

my_command_setvref = sasl.createCommand(def.APPNAMEPREFIX .. "/setvref", "Set Landing Flaps/VREF")
sasl.registerCommandHandler(my_command_setvref, 0, P.setvrefproc_)

--------------------------------------------------------------------------------------------------------------
function P.settoflapssteps(procedureloop)

    local FMC1Line00L = helpers.get("laminar/B738/fmc1/Line00_L")

    local toflapscalc = helpers.determineTakeoffFlapsSetting(get(P.totalweightkgs), get(P.deprwylen), get(P.deprwyheading), get(P.elevation), P.depmetar)
    local toflapscalcstring = tostring(toflapscalc)

    if (procedureloop.stepindex == 1) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWFMS])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if ((string.len(FMC1Line00L) < 9) or (string.sub(FMC1Line00L, 7, 13) ~= "TAKEOFF")) then
            helpers.command_once("laminar/B738/button/fmc1_init_ref")
            procedureloop.stepindex = procedureloop.stepindex - 1
        end
    end

    if (procedureloop.stepindex == 3) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            if (get(P.toflapsset) == def.OFF) then
                P.toflapscmdtable[3] = string.sub(toflapscalcstring, 1, 1)
                P.toflapscmdtable[4] = string.sub(toflapscalcstring, 2, 2)

                local tableindex = 1
                while (P.toflapscmdtable[tableindex] ~= "end") do
                    sasl.logDebug("while loop toflaps")
                    P.commandtableentry(def.COMMAND, "laminar/B738/button/fmc1_" .. P.toflapscmdtable[tableindex])
                    tableindex = tableindex + 1
                end

                P.commandtableentry(def.TEXT, "Takeoff Flaps " .. toflapscalcstring .. "set")
            end
        else
            if (get(P.toflaps) ~= toflapscalc) then
                P.commandtableentry(def.TEXT, "Enter Takeoff Flaps " .. toflapscalcstring)
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Takeoff Flaps Entered and " .. toflapscalcstring)
            end
        end
    end

    if (procedureloop.stepindex == 4) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true
end

function P.settoflapsproc()

    return P.triggerprocedure(def.SETTOFLAPSPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.settoflapsproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.settoflapsproc()
    end
    return 0
end

my_command_settoflapsproc = sasl.createCommand(def.APPNAMEPREFIX .. "/settoflapsproc", "Set Takeoff Flaps")
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

    local nearesticaotmp = helpers.cleanstring(get(P.nearesticao))
    local depicaotmp = helpers.cleanstring(get(P.depicao))
    local desicaotmp = helpers.cleanstring(get(P.desicao))

    if (helpers.isvalidicao(depicaotmp)) then
        P.depmetar.metar = helpers.getMetar(depicaotmp)
        if P.depmetar.metar then
            P.depmetar.icaocode = depicaotmp
            P.depmetar.metarfound = true
            P.depmetar.decodedmetar = helpers.decodemetar(P.depmetar.metar)
        else
            P.depmetar.icaocode = "XXXX"
            P.depmetar.metarfound = false
            P.depmetar.decodedmetar = {}
        end
    elseif (helpers.isvalidicao(nearesticaotmp)) then
        P.depmetar.metar = helpers.getMetar(nearesticaotmp)
        if P.depmetar.metar then
            P.depmetar.icaocode = nearesticaotmp
            P.depmetar.metarfound = true
            P.depmetar.decodedmetar = helpers.decodemetar(P.depmetar.metar)
        else
            P.depmetar.icaocode = "XXXX"
            P.depmetar.metarfound = false
            P.depmetar.decodedmetar = {}
        end
    end

    if (helpers.isvalidicao(desicaotmp)) then
        P.desmetar.metar = helpers.getMetar(desicaotmp)
        if P.desmetar.metar then
            P.desmetar.icaocode = desicaotmp
            P.desmetar.metarfound = true
            P.desmetar.decodedmetar = helpers.decodemetar(P.desmetar.metar)
        else
            P.desmetar.icaocode = "XXXX"
            P.desmetar.metarfound = false
            P.desmetar.decodedmetar = {}
        end
    end

    if (P.depmetar.metarfound and P.depmetar.decodedmetar) then
        if (sasl.getLogLevel() == LOG_DEBUG) then
            helpers.logtable(P.depmetar, "P.depmetar")
        end
    end

    if (P.desmetar.metarfound and P.desmetar.decodedmetar) then
        if (sasl.getLogLevel() == LOG_DEBUG) then
            helpers.logtable(P.desmetar, "P.desmetar")
        end
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

    result = true

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

    if (get(P.apustarterpos) == def.OFF) then
        return def.APUOFF
    elseif ((get(P.apustarterpos) == def.ON) and (get(P.apugenoffbus) == def.OFF)) then
        if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF) and (get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
            return def.APUONBUS
        else
            return def.APUSTARTED
        end
    elseif ((get(P.apustarterpos) == def.ON) and (get(P.apugenoffbus) ~= def.OFF)) then
        if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF) and (get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
            return def.APUONBUS
        else
            return def.APUOFFBUS
        end
    end
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

function P.coldanddarkstartupsteps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if (get(P.airgroundsensor) == def.OFF) then
            procedureloop.procedurenotpossible = true
            procedureloop.setonabort = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.COLDANDDARKPROCEDURE].name .. " Procedure not Possible Inflight")
            return true
        end

        if ((get(P.battery) == def.ON) and (get(P.mainbus) == def.ON)) then
            procedureloop.procedurenotpossible = true
            procedureloop.setonabort = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.COLDANDDARKPROCEDURE].name .. " Procedure aborted")
            return true
        end

        if (P.apurunning() == def.APUONBUS) then
            procedureloop.procedurenotpossible = true
            procedureloop.setonabort = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.COLDANDDARKPROCEDURE].name .. " Procedure aborted, A P U already running")
            return true
        end

        if P.enginesrunning(def.BOTH) then
            procedureloop.procedurenotpossible = true
            procedureloop.setonabort = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.COLDANDDARKPROCEDURE].name .. " Procedure aborted, Engines already running")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if (get(P.battery) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Battery On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/switch/battery_dn")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Battery checked and On")
        end
    end

    if (procedureloop.stepindex == 3) then
        if (get(P.batteryswitchcover) == def.OPEN) then
            helpers.command_once("laminar/B738/button_switch_cover02")
        end
    end

    if (procedureloop.stepindex == 4) then
        if ((P.configvalues[def.CONFIGVIEWCHANGES] == def.ON)and (get(P.sunpitchdegrees) < 0)) then
            P.setview(P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL])
        elseif ((P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON) and (get(P.sunpitchdegrees) < 0)) then
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 5) then
        if (get(P.sunpitchdegrees) < 0) then
            if (get(P.domelightpos) == def.DOMELIGHTOFF) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Domelight On")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    P.setdomelight(def.DOMELIGHTDIM)
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Domelight checked and On")
            end
        end
    end

    if (procedureloop.stepindex == 6) then
        if ((P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) and (get(P.sunpitchdegrees) < 0)) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        elseif ((P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON) and (get(P.sunpitchdegrees) < 0)) then
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 7) then
        if (get(P.emergencylights) ~= def.EMERGLIGHTSARMED) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Arm Emergency Lights")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.setemergencylights(def.EMERGLIGHTSARMED)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Emergency Lights checked and Armed")
        end
    end

    if (procedureloop.stepindex == 8) then
        if (get(P.emergencylightcover) == def.OPEN) then
            helpers.command_once("laminar/B738/button_switch_cover09")
        end
    end

    if (procedureloop.stepindex == 9) then
        if (get(P.positionlights) ~= def.POSLIGHTSSTEADY) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Position Lights Steady")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/position_light_steady")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Position Lights checked and Steady")
        end
    end

    if (procedureloop.stepindex == 10) then
        if ((P.configvalues[def.CONFIGUSEGROUNDPOWER] == def.ON) and (get(P.gpuavailable) == def.ON)) then
            if (get(P.gpuon) == def.OFF) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Switch Ground Power On")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    helpers.command_once("laminar/B738/toggle_switch/gpu_dn")
                    procedureloop.stepindex = 19
                    return true
                end
            else
                if (not procedureloop.steprepeat) then
                    P.commandtableentry(def.TEXT, "G P U checked and On")
                end
                procedureloop.stepindex = 19
                return true
            end
        end
    end

    if (procedureloop.stepindex == 11) then
        if (get(P.apustarterpos) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Start A P U")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U checked and Started")
        end
    end

    if (procedureloop.stepindex == 12) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            P.commandtableentry(def.TEXT, "A P U Started")
        end
    end

    if (procedureloop.stepindex == 13) then
        if (P.apurunning() < def.APUOFFBUS) then
            procedureloop.stepindex = procedureloop.stepindex - 1
        else
            P.commandtableentry(def.TEXT, "A P U Running")
        end
    end

    if (procedureloop.stepindex == 14) then
        if (not((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) or not((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF))) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Generator On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if not((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Generator checked and On")
        end
    end

    if (procedureloop.stepindex == 15) then
        if (get(P.bleedairapupos) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Bleed Air On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Bleed Air checked and On")
        end
    end

    if (procedureloop.stepindex == 16) then
        if (get(P.isolvalvepos) ~= def.ISOLVALVEOPEN) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Open")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.isolvalvepos, def.ISOLVALVEOPEN)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Isolation Valve checked and Open")
        end
    end

    if (procedureloop.stepindex == 17) then
        if ((get(P.packlpos) ~= def.PACKAUTO) or (get(P.packrpos) ~= def.PACKAUTO)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Packs Auto")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.packlpos, def.PACKAUTO)
                set(P.packrpos, def.PACKAUTO)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Packs checked and Auto")
        end
    end

    if (procedureloop.stepindex == 18) then
        if (get(P.trimairpos) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Trim Air On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.trimairpos, def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Trim Air checked and On")
        end
    end

    if (procedureloop.stepindex == 19) then
        P.proceduretable[def.APUSTARTUPPROCEDURE].set = true
    end

    if (procedureloop.stepindex == 20) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 21) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            if not P.setirs(def.BOTHIRS, def.IRSNAV) then
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        end
    end

    if (procedureloop.stepindex == 22) then
        if ((get(P.irsalignleft) == def.OFF) or (get(P.irsalignright) == def.OFF)) then
            if ((get(P.irsleftpos) ~= def.IRSNAV) or (get(P.irsrightpos) ~= def.IRSNAV)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Both I R S to Nav")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Both I R S checked and Nav")
            end
        else
            P.commandtableentry(def.TEXT, "I R S Alignment Started")
        end
    end

    if (procedureloop.stepindex == 23) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWFMS])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 24) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.irsposset) == "*****.*******.*") then
                P.commandtableentry(def.TEXT, "Initialize I R S Position")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if (not procedureloop.steprepeat) then
                    P.commandtableentry(def.TEXT, "I R S Position Initialized")
                end
                procedureloop.stepindex = 28
                return true
            end
        end
        helpers.command_once("laminar/B738/button/fmc1_init_ref")
    end

    if (procedureloop.stepindex == 25) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            helpers.command_once("laminar/B738/button/fmc1_next_page")
        end
    end

    if (procedureloop.stepindex == 26) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            helpers.command_once("laminar/B738/button/fmc1_4L")
        end
    end

    if (procedureloop.stepindex == 27) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            helpers.command_once("laminar/B738/button/fmc1_prev_page")
        end
    end

    if (procedureloop.stepindex == 28) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            helpers.command_once("laminar/B738/button/fmc1_4R")
            P.commandtableentry(def.TEXT, "I R S Position Initialization Complete")
        end
    end

    if (procedureloop.stepindex == 29) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true

end

function P.coldanddarkstartup()

    return P.triggerprocedure(def.COLDANDDARKPROCEDURE, def.TRIGGEREDMANUALLY)


end

function P.coldanddarkstartup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.coldanddarkstartup()
    end
    return 0
end

my_command_coldanddarkstartup = sasl.createCommand(def.APPNAMEPREFIX .. "/coldanddarkstartup", "Cold and Dark Startup")
sasl.registerCommandHandler(my_command_coldanddarkstartup, 0, P.coldanddarkstartup_)

--------------------------------------------------------------------------------------------------------------

function P.apustartupsteps(procedureloop)

    if (procedureloop.stepindex == 1) then

        if ((get(P.battery) == def.OFF) and (get(P.mainbus) == def.OFF)) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.APUSTARTUPPROCEDURE].name .. " Procedure aborted, Battery is Off")
            return true
        end

        if (P.apurunning() == def.APUONBUS) then
            procedureloop.procedurenotpossible = true
            procedureloop.setonabort = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.APUSTARTUPPROCEDURE].name .. " Procedure aborted, A P U already running")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if (P.apurunning() == def.APUOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Start A P U")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif not procedureloop.steprepeat then
            P.commandtableentry(def.TEXT, "A P U checked and Started")
        end
    end

    if (procedureloop.stepindex == 3) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            P.commandtableentry(def.TEXT, "A P U Running Up")
        else
            P.commandtableentry(def.TEXT, "A P U Running Up")
        end
    end

    if (procedureloop.stepindex == 4) then
        if (P.apurunning() < def.APUOFFBUS) then
            procedureloop.stepindex = procedureloop.stepindex - 1
        else
            P.commandtableentry(def.TEXT, "A P U Running")
        end
    end

    if (procedureloop.stepindex == 5) then
        if (P.apurunning() ~= def.APUONBUS) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Generator On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if not((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Generator checked and On")
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.gpuon) == def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Ground Power Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/gpu_up")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Ground Power checked and Off")
        end
    end

    if (procedureloop.stepindex == 7) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true

end

function P.apustartup()

    return P.triggerprocedure(def.APUSTARTUPPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.apustartup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.apustartup()
    end
    return 0
end

my_command_apustartup = sasl.createCommand(def.APPNAMEPREFIX .. "/apustartup", "APU Startup")
sasl.registerCommandHandler(my_command_apustartup, 0, P.apustartup_)

--------------------------------------------------------------------------------------------------------------
-- Engine Start

function P.enginestartsteps(procedureloop)

    if (procedureloop.stepindex == 1) then

        if (P.apurunning() ~= def.APUONBUS) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.ENGINESTARTPROCEDURE].name .. " Procedure not possible, A P U not running")
            return true
        end

        if P.enginesrunning(def.BOTH) then
            procedureloop.procedurenotpossible = true
            procedureloop.setonabort = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.ENGINESTARTPROCEDURE].name .. " Procedure aborted, Engines already running")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if (get(P.beaconlights) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Collision Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.togglecollisionlights(def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Collision lightset checked and On")
        end
    end

    if (procedureloop.stepindex == 3) then
        if ((get(P.lefttanklswitch) == def.OFF) or (get(P.lefttankrswitch) == def.OFF) or (get(P.righttanklswitch) == def.OFF) or (get(P.righttankrswitch) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Wing Tank Fuel Pumps On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.lefttanklswitch, def.ON)
                set(P.lefttankrswitch, def.ON)
                set(P.righttanklswitch, def.ON)
                set(P.righttankrswitch, def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Wing Fuel Tanks checked and On")
        end
    end

    if (procedureloop.stepindex == 4) then
        if ((get(P.packlpos) ~= def.PACKOFF) or (get(P.packrpos) ~= def.PACKOFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Packs Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.packlpos, def.PACKOFF)
                set(P.packrpos, def.PACKOFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Packs checked and Off")
        end
    end

    if (procedureloop.stepindex == 5) then
        if (get(P.bleedairapupos) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set A P U Bleed Air On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Bleed Air checked and On")
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.isolvalvepos) ~= def.ISOLVALVEOPEN) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Open")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.isolvalvepos, def.ISOLVALVEOPEN)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Isolation Valve checked and Open")
        end
    end

    if (procedureloop.stepindex == 7) then
        if (get(P.starter2pos) ~= def.GROUND) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Starter 2 Ground")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.setstarter(def.ENGINE2, def.GROUND)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Engine 2 Starter checked and On")
        end
    end

    if (procedureloop.stepindex == 8) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 9) then
        if (get(P.eng2n2percent) < 25) then
            procedureloop.stepindex = procedureloop.stepindex - 1
        else
            P.commandtableentry(def.TEXT, "Engine 2 N 2 at 25 Percent")
        end
    end

    if (procedureloop.stepindex == 10) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWTHROTTLE])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 11) then
        if (get(P.mixture2pos) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Engine 2 Fuel Lever Idle")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/engine/mixture2_idle")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Engine 2 Fuel Lever checked and Idle")
        end
    end

    if (procedureloop.stepindex == 12) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 13) then
        if not P.enginesrunning(def.ENGINE2) then
            procedureloop.stepindex = procedureloop.stepindex - 1
        else
            P.commandtableentry(def.TEXT, "Engine 2 Running")
        end
    end

    if (procedureloop.stepindex == 14) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 15) then
        if (get(P.starter1pos) ~= def.GROUND) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Starter 1 Ground")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.setstarter(def.ENGINE1, def.GROUND)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Engine 1 Starter checked and Ground")
        end
    end

    if (procedureloop.stepindex == 16) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 17) then
        if (get(P.eng1n2percent) < 25) then
            procedureloop.stepindex = procedureloop.stepindex - 1
        else
            P.commandtableentry(def.TEXT, "Engine 1 N 2 at 25 Percent")
        end
    end

    if (procedureloop.stepindex == 18) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWTHROTTLE])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 19) then
        if (get(P.mixture1pos) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Engine 1 Fuel Lever Idle")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/engine/mixture1_idle")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Engine 1 Fuel Lever checked and Idle")
        end
    end

    if (procedureloop.stepindex == 20) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 21) then
        if not P.enginesrunning(def.ENGINE1) then
            procedureloop.stepindex = procedureloop.stepindex - 1
        else
            P.commandtableentry(def.TEXT, "Engine 1 Running")
        end
    end

    if (procedureloop.stepindex == 22) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 23) then
        if ((get(P.gen1pos) ~= def.ON) or (get(P.gen2pos) ~= def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Both Generators On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if (get(P.gen1pos) ~= def.ON) then
                    helpers.command_once("laminar/B738/toggle_switch/gen1_dn")
                end
                if (get(P.gen2pos) ~= def.ON) then
                    helpers.command_once("laminar/B738/toggle_switch/gen2_dn")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Generators checked and On")
        end
    end

    if (procedureloop.stepindex == 24) then
        if ((get(P.hydro1pos) ~= def.ON) or (get(P.hydro2pos) ~= def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Both Hydraulic Pumps On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.hydro1pos, def.ON)
                set(P.hydro2pos, def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Hydraulic Pumps checked and On")
        end
    end

    if (procedureloop.stepindex == 25) then
        if ((get(P.elechydro1pos) ~= def.ON) or (get(P.elechydro2pos) ~= def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Both Electrical Hydraulic Pumps On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.elechydro1pos, def.ON)
                set(P.elechydro2pos, def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Electrical Hydraulic Pumps checked and On")
        end
    end

    if (procedureloop.stepindex == 26) then
        if ((get(P.bleedair1pos) == def.OFF) or (get(P.bleedair2pos) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Engine Bleed Air On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if (get(P.bleedair1pos) == def.OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(P.bleedair2pos) == def.OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Engine Bleed Air checked and On")
        end
    end

    if (procedureloop.stepindex == 27) then
        if ((get(P.packlpos) ~= def.PACKAUTO) or (get(P.packrpos) ~= def.PACKAUTO)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Packs Auto")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.packlpos, def.PACKAUTO)
                set(P.packrpos, def.PACKAUTO)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Packs checked and Auto")
        end
    end

    if (procedureloop.stepindex == 28) then
        if (get(P.isolvalvepos) ~= def.ISOLVALVEAUTO) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Auto")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.isolvalvepos, def.ISOLVALVEAUTO)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Isolation Valvechecked and Auto")
        end
    end

    if (procedureloop.stepindex == 29) then
        if (get(P.trimairpos) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Trim Air On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.trimairpos, def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Trim Air checked and On")
        end
    end

    if (procedureloop.stepindex == 30) then
        if (get(P.bleedairapupos) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Bleed Air Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Bleed Air checked and Off")
        end
    end

    if (procedureloop.stepindex == 31) then
        if (P.apurunning() ~= def.APUOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch APU Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U checked and Off")
        end
    end

    if (procedureloop.stepindex == 32) then
        if (get(P.yawdamperswitch) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Yaw Damper On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.yawdamperswitch, def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Yaw Damper checked and On")
        end
    end

    if (procedureloop.stepindex == 33) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true

end

function P.enginestart()

    return P.triggerprocedure(def.ENGINESTARTPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.enginestart_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.enginestart()
    end
    return 0
end

my_command_enginestart = sasl.createCommand(def.APPNAMEPREFIX .. "/enginestart", "Engine Startup")
sasl.registerCommandHandler(my_command_enginestart, 0, P.enginestart_)

--------------------------------------------------------------------------------------------------------------

function P.engineshutdownsteps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if (get(P.airgroundsensor) == def.OFF) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, "Engine Shutdown Procedure not possible Inflight")
            return true
        end

        if not P.enginesrunning(def.BOTH) then
            procedureloop.procedurenotpossible = true
            procedureloop.setonabort = true
            P.commandtableentry(def.TEXT, " Engine Shutdown Procedure aborted, Engines not running")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if (procedureloop.lock == def.TURNAROUNDENGINESHUTDOWNPROCEDURE) then
            if ((P.configvalues[def.CONFIGUSEGROUNDPOWER] == def.ON) and (get(P.gpuavailable) == def.ON)) then
                if (get(P.gpuon) == def.OFF) then
                    if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        P.commandtableentry(def.TEXT, "Switch Ground Power On")
                        procedureloop.stepindex = procedureloop.stepindex - 1
                    else
                        helpers.command_once("laminar/B738/toggle_switch/gpu_dn")
                        procedureloop.stepindex = 8
                        return true
                    end
                elseif (not procedureloop.steprepeat) then
                    P.commandtableentry(def.TEXT, "Ground Power checked and On")
                    procedureloop.stepindex = 8
                    return true
                end
            end
        elseif (procedureloop.lock == def.FINALENGINESHUTDOWNPROCEDURE) then
            procedureloop.stepindex = 9
        end
    end

    if (procedureloop.stepindex == 3) then
        if (P.apurunning() == def.APUOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Start A P U")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U checked and Started")
        end
    end

    if (procedureloop.stepindex == 4) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            P.commandtableentry(def.TEXT, "A P U Running Up")
        else
            P.commandtableentry(def.TEXT, "A P U Running Up")
        end
    end

    if (procedureloop.stepindex == 5) then
        if (P.apurunning() == def.APUOFFBUS) then
            P.commandtableentry(def.TEXT, "A P U Running")
        else
            procedureloop.stepindex = procedureloop.stepindex - 1
        end
    end

    if (procedureloop.stepindex == 6) then
        if (not((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) or not((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF))) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Generator On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if not((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Generator checked and On")
        end
    end

    if (procedureloop.stepindex == 7) then
        if (get(P.bleedairapupos) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Bleed Air On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Bleed Air checked and On")
        end
    end

    if (procedureloop.stepindex == 8) then
        if (get(P.isolvalvepos) ~= def.ISOLVALVEOPEN) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Open")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.isolvalvepos, def.ISOLVALVEOPEN)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Isolation Valve checked and Open")
        end
    end

    if (procedureloop.stepindex == 9) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWTHROTTLE])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 10) then
        if ((get(P.mixture1pos) ~= def.OFF) or (get(P.mixture2pos) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Engine Fuel Levers Cutoff")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if (get(P.mixture2pos) ~= def.OFF) then
                    helpers.command_once("laminar/B738/engine/mixture2_cutoff")
                end
                if (get(P.mixture1pos) ~= def.OFF) then
                    helpers.command_once("laminar/B738/engine/mixture1_cutoff")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Fuel Levers checked and Cutoff")
        end
    end

    if (procedureloop.stepindex == 11) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 12) then
        if ((get(P.centertanklswitch) == def.ON) or (get(P.centertankrswitch) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Center Tank Fuel Pumps Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.centertanklswitch, def.OFF)
                set(P.centertankrswitch, def.OFF)
            end
        end
    end

    if (procedureloop.stepindex == 13) then
        if ((get(P.lefttanklswitch) == def.ON) or (get(P.lefttankrswitch) == def.ON) or (get(P.righttanklswitch) == def.ON) or (get(P.righttankrswitch) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Wing Tank Fuel Pumps Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.lefttanklswitch, def.OFF)
                set(P.leftttankrswitch, def.OFF)
                set(P.righttanklswitch, def.OFF)
                set(P.righttankrswitch, def.OFF)
            end
        end
    end

    if (procedureloop.stepindex == 14) then
        if ((get(P.hydro1pos) ~= def.OFF) or (get(P.hydro2pos) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Both Hydraulic Pumps Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.hydro1pos, def.OFF)
                set(P.hydro2pos, def.OFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Hydraulic Pumps checked and Off")
        end
    end

    if (procedureloop.stepindex == 15) then
        if ((get(P.elechydro1pos) ~= def.OFF) or (get(P.elechydro2pos) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Both Electrical Hydraulic Pumps Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.elechydro1pos, def.OFF)
                set(P.elechydro2pos, def.OFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Electrical Hydraulic Pumps checked and Off")
        end
    end

    if (procedureloop.stepindex == 16) then
        if (get(P.beaconlights) == def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Collision Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.togglecollisionlights(def.OFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Collision lightset checked and Off")
        end
    end

    if (procedureloop.stepindex == 17) then
        if (procedureloop.lock == def.TURNAROUNDENGINESHUTDOWNPROCEDURE) then
            if (get(P.nosmokingsignpos) ~= def.NOSMOKINGSIGNOFF) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    P.setnosmokingsign(def.NOSMOKINGSIGNOFF)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set No Smoking Signs Off")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "NO Smoking Signs checked and Off")
            end
        end
    end

    if (procedureloop.stepindex == 18) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true

end

function P.turnaroundengineshutdown()

    return P.triggerprocedure(def.TURNAROUNDENGINESHUTDOWNPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.turnaroundengineshutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.turnaroundengineshutdown()
    end
    return 0
end

my_command_turnaroundengineshutdown = sasl.createCommand(def.APPNAMEPREFIX .. "/turnaroundengineshutdown", "Engine Shutdown Turnaround")
sasl.registerCommandHandler(my_command_turnaroundengineshutdown, 0, P.turnaroundengineshutdown_)

function P.finalengineshutdown()

    return P.triggerprocedure(def.FINALENGINESHUTDOWNPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.finalengineshutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.finalengineshutdown()
    end
    return 0
end

my_command_finalengineshutdown = sasl.createCommand(def.APPNAMEPREFIX .. "/finalengineshutdown", "Final Engine Shutdown")
sasl.registerCommandHandler(my_command_finalengineshutdown, 0, P.finalengineshutdown_)

--------------------------------------------------------------------------------------------------------------
-- Shutdown

function P.shutdownsteps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if (get(P.airgroundsensor) == def.OFF) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.SHUTDOWNPROCEDURE].name .. " Procedure not possible Inflight")
            return true
        end

        if ((get(P.battery) == def.OFF) and (get(P.mainbus) == def.OFF)) then
            procedureloop.procedurenotpossible = true
            procedureloop.setonabort = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.SHUTDOWNPROCEDURE].name .. " Procedure aborted")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if ((get(P.irsleftpos) ~= def.IRSOFF) or (get(P.irsrightpos) ~= def.IRSOFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both I R S Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if not P.setirs(def.BOTHIRS, def.IRSNAV) then
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both I R S checked and Off")
        end
    end

    if (procedureloop.stepindex == 3) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 4) then
        if (get(P.yawdamperswitch) == def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Yaw Damper Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.yawdamperswitch, def.OFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Yaw Damper checked and Off")
        end
    end

    if (procedureloop.stepindex == 5) then
        if (get(P.bleedairapupos) == def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Bleed Air Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Bleed Air checked and Off")
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.isolvalvepos) ~= def.ISOLVALVEAUTO) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Auto")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.isolvalvepos, def.ISOLVALVEAUTO)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Isolation Valve checked and Auto")
        end
    end

    if (procedureloop.stepindex == 7) then
        if ((get(P.packlpos) ~= def.PACKOFF) or (get(P.packrpos) ~= def.PACKOFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Packs Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.packlpos, def.PACKOFF)
                set(P.packrpos, def.PACKOFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Packs checked and Off")
        end
    end

    if (procedureloop.stepindex == 8) then
        if ((get(P.bleedair1pos) == def.ON) or (get(P.bleedair2pos) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Engine Bleed Air Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if (get(P.bleedair1pos) == def.ON) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(P.bleedair2pos) == def.ON) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Engine Bleed Air checked and Off")
        end
    end

    if (procedureloop.stepindex == 9) then
        if (get(P.trimairpos) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Trim Air Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.trimairpos, def.OFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Trim Air checked and Off")
        end
    end

    if (procedureloop.stepindex == 10) then
        if ((get(P.wheatlfwdpos) ~= def.OFF) or (get(P.wheatrfwdpos) ~= def.OFF) or (get(P.wheatlsidepos) ~= def.OFF) or (get(P.wheatrsidepos) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglewindowheat(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Window Heat Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Window Heat checked and Off")
        end
    end

    if (procedureloop.stepindex == 11) then
        if (P.configvalues[def.CONFIGUSEGROUNDPOWER] == def.ON) then
            if (get(P.gpuon) == def.ON) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Switch Ground Power Off")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    helpers.command_once("laminar/B738/toggle_switch/gpu_up")
                    procedureloop.stepindex = 13
                    return true
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Ground Power checked and Off")
                procedureloop.stepindex = 13
                return true
            end
        end
    end

    if (procedureloop.stepindex == 12) then
        if (((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) or ((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF))) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Generator Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_up")
                end
                if ((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_up")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Generator checked and Off")
        end
    end

    if (procedureloop.stepindex == 13) then
        if (P.apurunning() ~= def.APUOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U checked and Off")
        end
    end

    if (procedureloop.stepindex == 14) then
        if (get(P.positionlights) ~= def.POSLIGHTSOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Position Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.togglepositionlights(def.POSLIGHTSOFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Position LIghts checked and Off")
        end
    end

    if (procedureloop.stepindex == 15) then
        if (get(P.seatbeltsignpos) ~= def.SEATBELTSIGNOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setseatbeltsign(def.SEATBELTSIGNOFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Seatbeltsigns Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Seatbeltsigns checked and Off")
        end
    end

    if (procedureloop.stepindex == 16) then
        if (get(P.nosmokingsignpos) ~= def.NOSMOKINGSIGNOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setnosmokingsign(def.NOSMOKINGSIGNOFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set No Smoking Signs Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "NO Smoking Signs checked and Off")
        end
    end

    if (procedureloop.stepindex == 17) then
        if (get(P.emergencylightcover) == def.CLOSED) then
            helpers.command_once("laminar/B738/button_switch_cover09")
        end
    end

    if (procedureloop.stepindex == 18) then
        if (get(P.emergencylights) ~= def.EMERGLIGHTSOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Emergency Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.setemergencylights(def.EMERGLIGHTSOFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Emergency Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 19) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 20) then
        if (get(P.domelightpos) ~= def.DOMELIGHTOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setdomelight(def.DOMELIGHTOFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Domelight Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Domelight checked and Off")
        end
    end

    if (procedureloop.stepindex == 21) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 22) then
        if (get(P.batteryswitchcover) == def.CLOSED) then
            helpers.command_once("laminar/B738/button_switch_cover02")
        end
    end

    if (procedureloop.stepindex == 23) then
        if (get(P.battery) == def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Battery Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/switch/battery_up")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Battery checked and Off")
        end
    end

    if (procedureloop.stepindex == 24) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true

end

function P.shutdown()

    return P.triggerprocedure(def.SHUTDOWNPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.shutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.shutdown()
    end
    return 0
end

my_command_shutdown = sasl.createCommand(def.APPNAMEPREFIX .. "/shutdown", "Shutdown")
sasl.registerCommandHandler(my_command_shutdown, 0, P.shutdown_)

--------------------------------------------------------------------------------------------------------------

function P.teststeps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if ((get(P.battery) == def.OFF) and (get(P.mainbus) == def.OFF)) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.TESTPROCEDURE].name .. " Procedure aborted, Battery is Off")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWTHROTTLE])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        helpers.command_begin("laminar/B738/toggle_switch/fire_test_lft")
    end

    if (procedureloop.stepindex == 4) then
        helpers.command_end("laminar/B738/toggle_switch/fire_test_lft")
    end

    if (procedureloop.stepindex == 5) then
        helpers.command_begin("laminar/B738/toggle_switch/fire_test_rgt")
    end

    if (procedureloop.stepindex == 6) then
        helpers.command_end("laminar/B738/toggle_switch/fire_test_rgt")
    end

    if (procedureloop.stepindex == 7) then
        helpers.command_begin("laminar/B738/toggle_switch/exting_test_lft")
    end

    if (procedureloop.stepindex == 8) then
        helpers.command_end("laminar/B738/toggle_switch/exting_test_lft")
    end

    if (procedureloop.stepindex == 9) then
        helpers.command_begin("laminar/B738/toggle_switch/exting_test_rgt")
    end

    if (procedureloop.stepindex == 10) then
        helpers.command_end("laminar/B738/toggle_switch/exting_test_rgt")
    end

    if (procedureloop.stepindex == 11) then
        helpers.command_begin("laminar/B738/push_button/cargo_fire_test_push")
    end

    if (procedureloop.stepindex == 12) then
        helpers.command_end("laminar/B738/push_button/cargo_fire_test_push")
    end

    if (procedureloop.stepindex == 13) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 14) then
        helpers.command_begin("laminar/B738/push_button/flaps_test")
    end

    if (procedureloop.stepindex == 15) then
        helpers.command_end("laminar/B738/push_button/flaps_test")
    end

    if (procedureloop.stepindex == 16) then
        helpers.command_begin("laminar/B738/push_button/mach_warn1_test")
    end

    if (procedureloop.stepindex == 17) then
        helpers.command_end("laminar/B738/push_button/mach_warn1_test")
    end

    if (procedureloop.stepindex == 18) then
        helpers.command_begin("laminar/B738/push_button/mach_warn2_test")
    end

    if (procedureloop.stepindex == 19) then
        helpers.command_end("laminar/B738/push_button/mach_warn2_test")
    end

    if (procedureloop.stepindex == 20) then
        helpers.command_begin("laminar/B738/push_button/stall_test1_press")
    end

    if (procedureloop.stepindex == 21) then
        helpers.command_end("laminar/B738/push_button/stall_test1_press")
    end

    if (procedureloop.stepindex == 22) then
        helpers.command_begin("laminar/B738/push_button/stall_test2_press")
    end

    if (procedureloop.stepindex == 23) then
        helpers.command_end("laminar/B738/push_button/stall_test1_press")
    end

    if (procedureloop.stepindex == 24) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 25) then
        helpers.command_begin("laminar/B738/toggle_switch/window_ovht_test_up")
    end

    if (procedureloop.stepindex == 26) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_up")
    end

    if (procedureloop.stepindex == 27) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_up")
    end

    if (procedureloop.stepindex == 28) then
        helpers.command_begin("laminar/B738/toggle_switch/window_ovht_test_dn")
    end

    if (procedureloop.stepindex == 29) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_dn")
    end

    if (procedureloop.stepindex == 30) then
        helpers.command_begin("laminar/B738/push_button/tat_test")
    end

    if (procedureloop.stepindex == 31) then
        helpers.command_end("laminar/B738/push_button/tat_test")
    end

    if (procedureloop.stepindex == 32) then
        helpers.command_begin("laminar/B738/push_button/duct_ovht_test")
    end

    if (procedureloop.stepindex == 33) then
        helpers.command_end("laminar/B738/push_button/duct_ovht_test")
    end

    if (procedureloop.stepindex == 34) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 35) then
        helpers.command_once("laminar/B738/toggle_switch/bright_test_up")
    end

    if (procedureloop.stepindex == 36) then
        helpers.command_once("laminar/B738/toggle_switch/bright_test_dn")
    end

    if (procedureloop.stepindex == 37) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test1_up")
    end

    if (procedureloop.stepindex == 38) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test1_up")
    end

    if (procedureloop.stepindex == 39) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test1_dn")
    end

    if (procedureloop.stepindex == 40) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test1_dn")
    end

    if (procedureloop.stepindex == 41) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test2_up")
    end

    if (procedureloop.stepindex == 42) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test2_up")
    end

    if (procedureloop.stepindex == 43) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test2_dn")
    end

    if (procedureloop.stepindex == 44) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test2_dn")
    end

    if (procedureloop.stepindex == 45) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWPEDESTAL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 46) then
        helpers.command_once("laminar/B738/knob/transponder_tcas_test")
    end

    if (procedureloop.stepindex == 47) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true

end

function P.test()

   return P.triggerprocedure(def.TESTPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.test_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.test()
    end
    return 0
end

my_command_test = sasl.createCommand(def.APPNAMEPREFIX .. "/test", "Tests")
sasl.registerCommandHandler(my_command_test, 0, P.test_)

--------------------------------------------------------------------------------------------------------------

function P.cockpitinitsteps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if ((get(P.battery) == def.OFF) and (get(P.mainbus) == def.OFF)) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.COCKPITINITPROCEDURE].name .. " Procedure aborted, Cockpit is Cold and Dark")
            return true
        end

        if (get(P.parkingbrakepos) == def.OFF) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.COCKPITINITPROCEDURE].name .. " Procedure not possible, Parking brake must be set")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
        end
        if (get(P.sunpitchdegrees) < 0) then
            procedureloop.stepindex = 2
        else
            procedureloop.stepindex = 4
        end
    end

    if (procedureloop.stepindex == 2) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 3) then
        if (get(P.domelightpos) == def.DOMELIGHTOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Dome Light On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.setdomelight(def.DOMELIGHTDIM)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Dome light checked and On")
        end
    end

    if (procedureloop.stepindex == 4) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 5) then
        if (P.configvalues[def.CONFIGHIDEEFBS] == def.ON) then
            hideefb = false
            if (get(P.hidecptefb) == def.OFF) then
                helpers.command_once("laminar/B738/tab/toggle")
                hideefb = true
            end
            if (get(P.hidefoefb) == def.OFF) then
                helpers.command_once("laminar/B738/tab/fo_toggle")
                hideefb = true
            end
            if hideefb then
                P.commandtableentry(def.TEXT, "E F B S Hidden")
            end
        end
    end

    if ((procedureloop.stepindex == 6) and ((P.configvalues[def.CONFIGIGNOREALLBRIGHTHNESSSETTINGS] == def.OFF))) then
        if P.setcockpitlights() then
            P.commandtableentry(def.TEXT, "Instrument Lights set")
        end
    end

    if (procedureloop.stepindex == 7) then
        if (P.configvalues[def.CONFIGLOWERDU] == def.ON) then
            local lowerduset = def.OFF
            if (get(P.lowerdupage) == 0) then
                lowerduset = def.ON
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
            else
                if (get(P.lowerdupage) == 1) then
                    lowerduset = def.ON
                    helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
                end
            end

            if (get(P.lowerdupage2) ~= 1) then
                lowerduset = def.ON
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_SYS")
            end

            if (lowerduset == def.ON) then
                P.commandtableentry(def.TEXT, "Lower Display Unit Pages Set")
                lowerduset = def.OFF
            end
        end
    end

    if (procedureloop.stepindex == 8) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWFMS])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 9) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            P.commandtableentry(def.TEXT, "Reset F M C")
        else
            helpers.command_once("laminar/B738/button/reset_fmc")
            P.commandtableentry(def.TEXT, "F M C Reset Done")
        end
    end

    
    if (procedureloop.stepindex == 10) then
         if P. YANSHisinstalled() and P.YANSHflightplanloaded() and P.YANSHFuelPlanRamp and get(P.YANSHFuelPlanRamp) > 0 and P.YANSHParamsUnitsFlag then
            if (P.configvalues[def.CONFIGAUTOFUELING] == def.ON) then
                if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) then
                    local plannedFuelRaw = get(P.YANSHFuelPlanRamp)   
                    local plannedFuelLbs = plannedFuelRaw
            
                    if get(P.YANSHParamsUnitsFlag) == def.YANSHUNITKGS then
                        plannedFuelLbs = plannedFuelRaw * def.KGTOLBS
                    end
          
                    P.refuelAircraft(plannedFuelLbs)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.checkYANSHFuel()
                end
            end
        else
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Load YANSH Flight Plan")
            else
                helpers.command_once("YANSH/fetchOFP")
            end
            procedureloop.stepindex = procedureloop.stepindex - 1
            return true
        end
    end

    if (procedureloop.stepindex == 11) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWPEDESTAL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 12) then
        if (P.configvalues[def.CONFIGTRANSPONDER] ~= 0) then
            if (get(P.transpondercode) ~= P.configvalues[def.CONFIGTRANSPONDER]) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    set(P.transpondercode, P.configvalues[def.CONFIGTRANSPONDER])
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Transponder Code " .. helpers.addspaces(P.configvalues[def.CONFIGTRANSPONDER]))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Transponder Code checked and " .. helpers.addspaces(P.configvalues[def.CONFIGTRANSPONDER]))
            end
        end
    end

    if (procedureloop.stepindex == 13) then
        if (get(P.transponderpos) ~= def.STANDBY) then
            if (P.configvalues[def.CONFIGTRANSPONDER] ~= 0) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    P.toggletransponder(def.STANDBY)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Transponder Standby")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Transponder checked and Standby")
        end
    end

    if (procedureloop.stepindex == 14) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 15) then
        if ((get(P.captainprobepos) ~= def.OFF) or (get(P.foprobepos) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggleprobeheat(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Probe Heat Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Probe Heat checked and Off")
        end
    end

    if (procedureloop.stepindex == 16) then
        if (get(P.seatbeltsignpos) ~= def.SEATBELTSIGNOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setseatbeltsign(def.SEATBELTSIGNOFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Seatbelt Signs Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Seatbelt Signs checked and Off")
        end
    end

    if (procedureloop.stepindex == 17) then
        if (get(P.nosmokingsignpos) ~= def.NOSMOKINGSIGNON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setnosmokingsign(def.NOSMOKINGSIGNON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set No Smoking Signs On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "No Smoking Signs checked and On")
        end
    end

    if (procedureloop.stepindex == 18) then
        if(get(P.positionlights) ~= def.POSLIGHTSSTEADY) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglepositionlights(def.POSLIGHTSSTEADY)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Position Lights Steady")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Position Lights checked and Steady")
        end
    end

    if (procedureloop.stepindex == 19) then
        if ((get(P.llights1) ~= def.OFF) or (get(P.llights2) ~= def.OFF) or (get(P.llights3) ~= def.OFF) or (get(P.llights4) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelandinglights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Landing Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Landing Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 20) then
        if ((get(P.rwylightl) == def.ON) or (get(P.rwylightl) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglerwylights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Runway Turnoff Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Runway Turnoff Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 21) then
        if (get(P.taxilight) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggletaxilights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Taxi Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Taxi Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 22) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end


    if (procedureloop.stepindex == 23) then
        if (get(P.apdiscpos) == def.ON) then
            helpers.command_once("laminar/B738/autopilot/disconnect_toggle")
        end
    end

    if (procedureloop.stepindex == 24) then
        if ((get(P.fdpilotpos) == def.ON) or (get(P.fdfopos) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglefds(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Flight Directors Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Flight Directors checked and Off")
        end
    end

    if (procedureloop.stepindex == 25) then
        if (get(P.mcpaltitude) ~= P.configvalues[def.CONFIGLOWEAIRSPACEALT]) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                set(P.mcpaltitude, P.configvalues[def.CONFIGLOWEAIRSPACEALT])
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set M C P ALtitude " .. tostring(P.configvalues[def.CONFIGLOWEAIRSPACEALT]))
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "M C P ALtitude checked and " .. tostring(P.configvalues[def.CONFIGLOWEAIRSPACEALT]))
        end
    end

    if (procedureloop.stepindex == 26) then
        if (get(P.bankanglepos) ~= P.configvalues[def.CONFIGBANKANGLEMAX]) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setbankanglepos(P.configvalues[def.CONFIGBANKANGLEMAX])
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Bank Angle " .. helpers.getbankanglestring(P.configvalues[def.CONFIGBANKANGLEMAX]))
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Bank Angle checked and " .. helpers.getbankanglestring(P.configvalues[def.CONFIGBANKANGLEMAX]))
        end
    end

    if (procedureloop.stepindex == 27) then
        if (get(P.efisdatapilotpos) == def.OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/data_press")
        end
        if (get(P.efisdatafopos) == def.OFF) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/data_press")
        end
    end

    if (procedureloop.stepindex == 28) then
        if (get(P.autobrakepos) ~= def.AUTOBRAKEOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Auto Brake Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.setautobrake(def.AUTOBRAKEOFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Auto Brake checked and Off")
        end
    end


    if (procedureloop.stepindex == 29) then
        if (get(P.aponstat) == def.ON) then
            set(P.aponstat, def.OFF)
        end
    end

    if (((not P.enginesrunning(BOTH)) and ((get(P.mixture1pos) ~= def.OFF) or (get(P.mixture2pos) ~= def.OFF))) or (speedbrakeleverrounded ~= def.SPEEDBRAKEDOWN)) then
        if (procedureloop.stepindex == 30) then
            if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
                P.setview(P.configvalues[def.CONFIGVIEWTHROTTLE])
            else
                procedureloop.stepindex = procedureloop.stepindex + 1
                procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
            end
        end

        if (procedureloop.stepindex == 31) then
            if ((not P.enginesrunning(BOTH)) and ((get(P.mixture1pos) ~= def.OFF) or (get(P.mixture2pos) ~= def.OFF))) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Both Engine Fuel Levers Cutoff")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    if (get(P.mixture2pos) ~= def.OFF) then
                        helpers.command_once("laminar/B738/engine/mixture2_cutoff")
                    end
                    if (get(P.mixture1pos) ~= def.OFF) then
                        helpers.command_once("laminar/B738/engine/mixture1_cutoff")
                    end
                end
            else
                procedureloop.stepindex = procedureloop.stepindex + 1
                procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
            end
        end

        if (procedureloop.stepindex == 32) then
            speedbrakeleverrounded = helpers.roundnumber(get(P.speedbrakelever), 1)
            if (speedbrakeleverrounded ~= def.SPEEDBRAKEDOWN) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    set(P.speedbrakelever, def.OFF)
                elseif (not procedureloop.steprepeat) then
                    P.commandtableentry(def.TEXT, "Retract Speed Brakes")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            else
                procedureloop.stepindex = procedureloop.stepindex + 1
                procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
            end
        end

        if (procedureloop.stepindex == 33) then
            if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
                P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
            else
                procedureloop.stepindex = procedureloop.stepindex + 1
                procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
            end
        end
    elseif (procedureloop.stepindex == 30) then
        procedureloop.stepindex = 34
    end

    if (procedureloop.stepindex == 34) then
        helpers.command_once("laminar/B738/push_button/master_caution1")
        helpers.command_once("laminar/B738/button/fmc1_clr")
    end

    return true

end

function P.cockpitinit()

    return P.triggerprocedure(def.COCKPITINITPROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.cockpitinit_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.cockpitinit()
    end
    return 0
end

my_command_cockpitinit = sasl.createCommand(def.APPNAMEPREFIX .. "/cockpitinit", "Cockpit Initialization")
sasl.registerCommandHandler(my_command_cockpitinit, 0, P.cockpitinit_)

--------------------------------------------------------------------------------------------------------------

function P.aftertakeoffsteps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if (get(P.radioaltitude) > 200) then
            if (get(P.gearhandlepos) == def.GEARDOWN) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Gear Up")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    set(P.gearhandlepos, def.GEARUP)
                end
            elseif ((get(P.gearhandlepos) == def.GEARDOWN) and (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) and not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Gear checked and Up")
            end
        else
            procedureloop.stepindex = procedureloop.stepindex - 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if ((get(P.gearhandlepos) == def.GEARUP) and (get(P.lgeardeployed) == 0) and (get(P.ngeardeployed) == 0) and (get(P.rgeardeployed) == 0)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Gear Lever Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.gearhandlepos, def.GEAROFF)
            end
        elseif ((get(P.gearhandlepos) == def.GEAROFF) and (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) and not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Gear Lever checked and Off")
        elseif (get(P.gearhandlepos) ~= def.GEAROFF) then
            procedureloop.stepindex = procedureloop.stepindex - 1
        end
    end

    if (procedureloop.stepindex == 3) then
        if (get(P.autobrakepos) ~= def.AUTOBRAKEOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Auto Brake Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.setautobrake(def.AUTOBRAKEOFF)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Auto Brake checked and Off")
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------

function P.altitudea10000steps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if (get(P.altitude) < P.configvalues[def.CONFIGLOWEAIRSPACEALT]) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.ALTITUDEA10000PROCEDURE].name .. " Procedure only possible above lower Airspace Altitude")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if (get(P.fmccruisealt) > P.configvalues[def.CONFIGLOWEAIRSPACEALT]) then
            if (get(P.altitude) < (P.configvalues[def.CONFIGLOWEAIRSPACEALT] + 1000)) then
                P.commandtableentry(def.TEXT, "Passing " .. P.configvalues[def.CONFIGLOWEAIRSPACEALT] .. " Feet")
            end
        end
    end

    if (procedureloop.stepindex == 3) then
        if ((get(P.llights1) ~= def.OFF) or (get(P.llights2) ~= def.OFF) or (get(P.llights3) ~= def.OFF) or (get(P.llights4) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelandinglights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Landing Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Landing Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 4) then
        if (get(P.logolighton) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelogolight(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Logo Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Logo Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 5) then
        if (get(P.seatbeltsignpos) ~= def.SEATBELTSIGNOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setseatbeltsign(def.SEATBELTSIGNOFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Seatbeltsigns Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Seatbelt Signs checked and Off")
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.starterauto) == def.ON) then
            if ((get(P.starter1pos) ~= def.AUTO) or (get(P.starter2pos) ~= def.AUTO)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    P.setstarter(def.BOTH, def.AUTO)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Both Starters Auto")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Both Starters checked and Auto")
            end
        else
            if ((get(P.starter1pos) ~= def.CONT) or (get(P.starter2pos) ~= def.CONT)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    P.setstarter(def.BOTH, def.CONT)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Both Starters Continuous")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Both Starters checked and Continuous")
            end
        end
    end

    if (procedureloop.stepindex == 7) then
        P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
    end

    return false

end

function P.altitudea10000()

    return P.triggerprocedure(def.ALTITUDEA10000PROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.altitudea10000_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.altitudea10000()
    end
    return 0
end

my_command_altitudea10000 = sasl.createCommand(def.APPNAMEPREFIX .. "/altitudea10000", "Above 10000")
sasl.registerCommandHandler(my_command_altitudea10000, 0, P.altitudea10000_)

--------------------------------------------------------------------------------------------------------------

function P.duringclimbsteps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            P.setdomelight(def.DOMELIGHTOFF)
        end
    end

    if (procedureloop.stepindex == 2) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            if (get(P.altitude) < P.configvalues[def.CONFIGLOWEAIRSPACEALT]) then
                P.togglelandinglights(def.ON)
            end
        end
    end

    if (procedureloop.stepindex == 3) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            P.togglepositionlights(def.POSLIGHTSSTROBE)
        end
    end

    if (procedureloop.stepindex == 4) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            P.togglerwylights(def.OFF)
        end
    end

    if (procedureloop.stepindex == 5) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            P.toggletaxilights(def.OFF)
        end
    end

    if (procedureloop.stepindex == 6) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
            if (P.configvalues[def.CONFIGTRANSPONDER] ~= 0) then
                P.toggletransponder(def.TARA)
            end
        end
    end

    if (procedureloop.stepindex == 7) then
        if (get(P.altitude) > get(P.fmctransalt)) then
            P.commandtableentry(def.TEXT, "Passing Transition Altitude")
        else
            procedureloop.stepindex = procedureloop.stepindex - 1
        end
    end

    if (procedureloop.stepindex == 8) then
        if (P.configvalues[def.CONFIGAUTOBARO] == def.ON) then
            if (get(P.altitude) > get(P.fmctransalt)) then
                if (get(P.barostd) == def.OFF) then
                    if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                        helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
                    elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        P.commandtableentry(def.TEXT, "Set Q N H to Standard")
                        procedureloop.stepindex = procedureloop.stepindex - 1
                    end
                elseif (not procedureloop.steprepeat) then
                    P.commandtableentry(def.TEXT, "Q N H checked and Standard")
                end
            else
                if (get(P.fmccruisealt) > get(P.fmctransalt)) then
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            end
        end
    end

    if (procedureloop.stepindex == 9) then
        if ((get(P.bleedair1pos) == def.OFF) or (get(P.bleedair2pos) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Engine Bleed Air On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                if (get(P.bleedair1pos) == def.OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(P.bleedair2pos) == def.OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Engine Bleed Air checked and On")
        end
    end

    if (procedureloop.stepindex == 10) then
        if ((get(P.packlpos) == def.PACKOFF) or (get(P.packrpos) == def.PACKOFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Packs Auto")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.packlpos, def.PACKAUTO)
                set(P.packrpos, def.PACKAUTO)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Packs checked and On")
        end
    end

    if (procedureloop.stepindex == 11) then
        if (get(P.isolvalvepos) == def.ISOLVALVEOPEN) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Auto")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.isolvalvepos, def.ISOLVALVEAUTO)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Isolation Valve checked and Auto")
        end
    end

    if (procedureloop.stepindex == 12) then
        if (get(P.bleedairapupos) == def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Bleed Air Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U Bleed Air checked and Off")
        end
    end

    if (procedureloop.stepindex == 13) then
        if (P.apurunning() ~= def.APUOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch A P U Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "A P U checked and Off")
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.duringclimb()

    P.triggerprocedure(def.DURINGCLIMBPROCEDURE)

    if (get(P.altitude) >= P.configvalues[def.CONFIGLOWEAIRSPACEALT]) or (get(P.fmccruisealt) < P.configvalues[def.CONFIGLOWEAIRSPACEALT]) then
        P.triggerprocedure(def.ALTITUDEA10000PROCEDURE)
    end

    if (P.configvalues[def.CONFIGAUTOFLAPS] == def.ON) and (get(P.flapleverpos) > def.FLAPSUP) then
        P.flapsuphandling()
    end

end

--------------------------------------------------------------------------------------------------------------

function P.altitudeb10000steps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if (get(P.altitude) > P.configvalues[def.CONFIGLOWEAIRSPACEALT]) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.ALTITUDEB10000PROCEDURE].name .. " Procedure only possible below lower Airspace Altitude")
            return true
        end

        P.commandtableentry(def.TEXT, "Below " .. P.configvalues[def.CONFIGLOWEAIRSPACEALT] .. " Feet")
    end

    if (procedureloop.stepindex == 2) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 3) then
        if (get(P.seatbeltsignpos) ~= def.SEATBELTSIGNON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setseatbeltsign(def.SEATBELTSIGNON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Seatbeltsigns On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Seatbeltsigns checked and On")
        end
    end

    if (procedureloop.stepindex == 4) then
        if ((get(P.llights1) == def.OFF) or (get(P.llights2) == def.OFF) or (get(P.llights3) == def.OFF) or (get(P.llights4) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelandinglights(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Landing Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Landing Lights checked and On")
        end
    end

    if (procedureloop.stepindex == 5) then
        if ((get(P.starter1pos) ~= def.FLIGHT) or (get(P.starter2pos) ~= def.FLIGHT)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setstarter(def.BOTH, def.FLIGHT)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Starters Flight")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        else
            if (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Both Starters checked and Flight")
            end
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.logolighton) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelogolight(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Logo Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Logo Lights checked and On")
        end
    end

    if (procedureloop.stepindex == 7) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 8) then
        local procedureKey = def.SETILSPROCEDURE
        local procedureData = P.proceduretable[procedureKey]
        local targetLoopObject = P[def.PROCEDURELOOP .. procedureData.loop]

        if (not procedureData.set) and (targetLoopObject.lock == def.NOPROCEDURE or targetLoopObject.lock == procedureKey) then
            targetLoopObject.lock = procedureKey
            procedureloop.stepindex = procedureloop.stepindex - 1
        end
    end

    if (procedureloop.stepindex == 9) then
        if (get(P.vref) == 0) then
            if (P.configvalues[def.CONFIGVREF30SET] == def.ON) then
                local procedureKey = def.SETVREFPROCEDURE
                local procedureData = P.proceduretable[procedureKey]
                local targetLoopObject = P[def.PROCEDURELOOP .. procedureData.loop]

                if (not procedureData.set) and (targetLoopObject.lock == def.NOPROCEDURE or targetLoopObject.lock == procedureKey) then
                    targetLoopObject.lock = procedureKey
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            end
        elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) and not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "V REF " .. get(P.appflaps) .. " checked and " .. get(P.vref))
        end
    end

    if (procedureloop.stepindex == 10) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 11) then
        if (get(P.autobrakepos) <= def.AUTOBRAKEOFF) then
            if (P.configvalues[def.CONFIGVREF30SET] == def.ON) then
                local autobrake = helpers.calcautobrake(get(P.vref), get(P.totalweightkgs), get(P.desrwylen), P.desmetar)
                sasl.logDebug("AUTOBRAKE AUTOBRAKEPOS: " .. tostring(get(P.autobrakepos)) .. " AUTOBRAKE " .. tostring(autobrake))
                if (get(P.autobrakepos) ~= autobrake) then
                    if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                        P.setautobrake(autobrake)
                    elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        if (autobrake < def.AUTOBRAKEMAX) then
                            P.commandtableentry(def.TEXT, "Set Auto Brake " .. tostring(autobrake - 1))
                        else
                            P.commandtableentry(def.TEXT, "Set Auto Brake Maximum")
                        end
                        procedureloop.stepindex = procedureloop.stepindex - 1
                    end
                elseif (not procedureloop.steprepeat) then
                    if (autobrake < def.AUTOBRAKEMAX) then
                        P.commandtableentry(def.TEXT, "Auto Brake checked and " .. tostring(autobrake - 1))
                    else
                        P.commandtableentry(def.TEXT, "Auto Brake checked and Maximum")
                    end
                end
            end
        elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.autobrakepos) < def.AUTOBRAKEMAX) then
                P.commandtableentry(def.TEXT, "Auto Brake checked and " .. tostring(get(P.autobrakepos) - 1))
            else
                P.commandtableentry(def.TEXT, "Auto Brake checked and Maximum")
            end
        end
   end

    if (procedureloop.stepindex == 12) then
        P.speakdesmetar()
    end

    return true

end

function P.altitudeb10000()

    return P.triggerprocedure(def.ALTITUDEB10000PROCEDURE, def.TRIGGEREDMANUALLY)

end

function P.altitudeb10000_(phase)
    if phase == SASL_COMMAND_BEGIN then
        P.altitudeb10000()
    end
    return 0
end

my_command_altitudeb10000 = sasl.createCommand(def.APPNAMEPREFIX .. "/altitudeb10000", "Below 10000")
sasl.registerCommandHandler(my_command_altitudeb10000, 0, P.altitudeb10000_)

--------------------------------------------------------------------------------------------------------------

function P.radioaltitudeb2500steps(procedureloop)

    if (procedureloop.stepindex == 1) then
        if ((helpers.convflaplevertoflappos(get(P.flapleverpos)) >= P.configvalues[def.CONFIGGEARDOWNFLAPS]) and (get(P.gearhandlepos) < def.GEARDOWN)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                set(P.gearhandlepos, def.GEARDOWN)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Gear Down")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (get(P.gearhandlepos) == def.GEARDOWN) then
            if (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Gear checked and Down")
            end
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.radioaltitudeb1000steps(procedureloop)

    if (procedureloop.stepindex == 1) then
        speedbrakeleverrounded = helpers.roundnumber(get(P.speedbrakelever), 1)
        if (speedbrakeleverrounded ~= def.SPEEDBRAKEARMED) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                set(P.speedbrakelever, def.SPEEDBRAKEARMED)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Arm Speed Brakes")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        else
            if (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Speedbrakes checked and Armed")
            end
        end
    end

    if (procedureloop.stepindex == 2) then
        if (get(P.taxilight) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggletaxilights(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Taxi Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        else
            if (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Taxi Lights checked and On")
            end
        end
    end

    if (procedureloop.stepindex == 3) then
        if ((get(P.rwylightl) == def.OFF) or (get(P.rwylightl) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglerwylights(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Runway Turnoff Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        else
            if (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Runway Turnoff Lights checked and On")
            end
        end
    end

    if (procedureloop.stepindex == 4) then
        local missedappalttmp = helpers.roundnumber((get(P.missedappalt) / 100)) * 100
        if (missedappalttmp > 1000) then
            if (missedappalttmp ~= get(P.mcpaltitude)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set M C P Altitude " .. helpers.addspaces(missedappalttmp))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    set(P.mcpaltitude, missedappalttmp)
                end
            else
                if (not procedureloop.steprepeat) then
                    P.commandtableentry(def.TEXT, "M C P Altitude checked and " .. helpers.addspaces(missedappalttmp))
                end
            end
        else
            P.commandtableentry(def.TEXT, "Set Missed Approach Altitude")
        end
    end
    
    if (procedureloop.stepindex == 5) then
        local headingrounded = nil
        if (helpers.isvalidicao(get(P.desicao)) and helpers.isvalidrwy(get(P.desrwy)) and tonumber(get(P.desrwyheading))) then
            headingrounded = helpers.roundnumber(get(P.desrwyheading))
        end
        local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.desicao), get(P.desrwy))
        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
            headingrounded = navrwyheading
        end

        if (headingrounded and (get(P.aphdgselstat) == def.OFF)) then
            if (headingrounded ~= get(P.mcpheading)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3)))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    set(P.mcpheading, headingrounded)
                end
            else
                if (not procedureloop.steprepeat) then
                    P.commandtableentry(def.TEXT, "M C P Heading checked and " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3)))
                end
            end
        elseif not headingrounded then
            P.commandtableentry(def.TEXT, "Set Missed Approach Heading")
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.gearhandlepos) < def.GEARDOWN) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                set(P.gearhandlepos, def.GEARDOWN)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Gear Down")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        else
            if (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Gear checked and Down")
            end
        end
    end
    
    if (procedureloop.stepindex == 7) then
        if (((get(P.appflapsset) == def.OFF) and get(P.appflaps) ~= 0)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then            
                helpers.command_once("laminar/B738/push_button/flaps_" .. tostring(get(P.appflaps)))
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Flaps " .. tostring(get(P.appflaps)))
                procedureloop.stepindex = procedureloop.stepindex - 1 
            end
        else
            if (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Flaps checked and " .. tostring(get(P.appflaps)))
            end
        end
    end

      if (procedureloop.stepindex == 8) then
        local windreport = nil

        if (P.desmetar and P.airportdatatable[get(P.desicao)] and P.airportdatatable[get(P.desicao)].latitude and P.airportdatatable[get(P.desicao)].longitude) then
            windreport = helpers.formatWindSpeechSummary(P.desmetar, P.airportdatatable[get(P.desicao)].latitude, P.airportdatatable[get(P.desicao)].longitude)
        elseif (P.desmetar and helpers.isvalidrwy(get(P.desrwy))) then
            windreport = helpers.formatWindSpeechSummary(P.desmetar, get(P.desrwylatstartpos), get(P.desrwylonstartpos))
        end
        if (windreport ~= nil) then
            P.commandtableentry(def.TEXT, windreport)
        end
    end

    return true


end

--------------------------------------------------------------------------------------------------------------

function P.duringdescentsteps(procedureloop)

    if (procedureloop.stepindex == 1) then
        P.commandtableentry(def.TEXT, "Descent Started")
    end

    if (procedureloop.stepindex == 2) then
        if ((P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) and (P.configvalues[def.CONFIGSPDRESTR250] == def.ON)) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWFMS])
        elseif (P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON) then
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 3) then
        if (P.configvalues[def.CONFIGSPDRESTR250] == def.ON) then
            helpers.command_once("laminar/B738/button/fmc1_des")
        end
    end

    if (procedureloop.stepindex == 4) then
        if (P.configvalues[def.CONFIGSPDRESTR250] == def.ON) then
            if (get(P.speedrestr) ~= 250) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Speed below 10000 Feet to 250")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    set(P.speedrestr, 250)
                    P.commandtableentry(def.TEXT, "Speed 250 below 10000 Feet set")
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Speed 250 below 10000 Feet checked and set")
            end
        end
    end

    if (procedureloop.stepindex == 5) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 6) then
        P.speakdesmetar()
    end

    if (procedureloop.stepindex == 7) then
        if (get(P.fmccruisealt) > get(P.fmctranslvl)) then
            if (get(P.altitude) < get(P.fmctranslvl)) then
                P.commandtableentry(def.TEXT, "Passing Transition Level")
            else
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        end
    end

    if (procedureloop.stepindex == 8) then
        if (P.configvalues[def.CONFIGAUTOBARO] == def.ON) then
            if (get(P.altitude) < get(P.fmctranslvl)) then
                local baroinchtmp, baropastmp = P.getlocalqnh(ARRIVAL)
                sasl.logDebug("QNHARRIVAL: BAROPILOT "..tostring(helpers.roundnumber(get(P.baropilot), 2)) .. " BAROINCHTMP " .. baroinchtmp .. " " .. tostring(helpers.roundnumber(math.abs(helpers.roundnumber(get(P.baropilot), 2) - baroinchtmp), 2)))
                if ((get(P.barostd) == def.ON) or (helpers.roundnumber(math.abs(helpers.roundnumber(get(P.baropilot), 2) - baroinchtmp), 2) > 0.01)) then
                    if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                        helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
                        set(P.baropilot, baroinchtmp)
                    elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                        if (get(P.baroinhpa) == def.ON) then
                            P.commandtableentry(def.TEXT, "Set Q N H " .. helpers.addspaces(baropastmp))
                        else
                            P.commandtableentry(def.TEXT, "Set Q N H " .. helpers.addspaces(baroinchtmp))
                        end
                        procedureloop.stepindex = procedureloop.stepindex - 1
                    end
                elseif ((get(P.barostd) == def.OFF) and (helpers.roundnumber(math.abs(helpers.roundnumber(get(P.baropilot), 2) - baroinchtmp), 2) <= 0.01)) then
                    if (not procedureloop.steprepeat) then
                        if (get(P.baroinhpa) == def.ON) then
                            P.commandtableentry(def.TEXT, "Q N H checked and " .. helpers.addspaces(baropastmp))
                        else
                            P.commandtableentry(def.TEXT, "Q N H checked and " .. helpers.addspaces(baroinchtmp))
                        end
                    end
                end
            else
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        end
    end

    if (procedureloop.stepindex == 9) then
        if (get(P.desrwy) == "") then
            P.commandtableentry(def.TEXT, "Set Destination Runway for " .. helpers.addspaces(get(P.desicao)))
        end
    end

    if (procedureloop.stepindex == 10) then
        if P.desmetar.metarfound then
            if not helpers.shouldCheckRunwaySuitability(P.desmetar, get(P.desrwy)) then
                P.commandtableentry(def.TEXT, "Check Destination Runway " .. helpers.addspaces(get(P.desrwy)))
            end
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
function P.duringdescent()

    P.triggerprocedure(def.DURINGDESCENTPROCEDURE)

    if get(P.altitude) < P.configvalues[def.CONFIGLOWEAIRSPACEALT] then
        P.triggerprocedure(def.ALTITUDEB10000PROCEDURE)
    end

    if get(P.radioaltitude) < 2500 then
        P.triggerprocedure(def.RADIOALTITUDEB2500PROCEDURE)
    end

    if get(P.radioaltitude) < 1000 then
        P.triggerprocedure(def.RADIOALTITUDEB1000PROCEDURE)
    end

    if P.configvalues[def.CONFIGAUTOFLAPS] == def.ON then
        P.flapsdownhandling()
    end
end

--------------------------------------------------------------------------------------------------------------

function P.afterlandingsteps(procedureloop)

    if (get(P.battery) ~= def.ON) then
        procedureloop.procedureabort = true
        return true
    end

    if (procedureloop.stepindex == 1) then
        P.flightstate = def.FLIGHTSTATETAXITOGATE
        if P.YANSHisinstalled() and P.YANSHFuelPlanRamp and P.YANSHGeneralMaxAltitude then
            set(P.YANSHFuelPlanRamp, 0)
            set(P.YANSHGeneralMaxAltitude, 0)
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if ((get(P.llights1) ~= def.OFF) or (get(P.llights2) ~= def.OFF) or (get(P.llights3) ~= def.OFF) or (get(P.llights4) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelandinglights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Landing Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Landing Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 3) then
        if (get(P.taxilight) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggletaxilights(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Taxi Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Taxi Lights checked and On")
        end
    end

    if (procedureloop.stepindex == 4) then
        if ((get(P.rwylightl) == def.ON) or (get(P.rwylightl) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglerwylights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Runway Turnoff Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Runway Turnoff Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 5) then
        if(get(P.positionlights) ~= def.POSLIGHTSSTEADY) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglepositionlights(def.POSLIGHTSSTEADY)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Position Lights Steady")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Position Lights checked and Steady")
        end
    end

    if (procedureloop.stepindex == 6) then
        if ((get(P.captainprobepos) ~= def.OFF) or (get(P.foprobepos) ~= def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggleprobeheat(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Probe Heat Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Probe Heat checked and Off")
        end
    end

    if (procedureloop.stepindex == 7) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWPEDESTAL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 8) then
        if (get(P.transponderpos) == def.TARA) then
            if (P.configvalues[def.CONFIGTRANSPONDER] ~= 0) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    P.toggletransponder(def.STANDBY)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Transponder Off")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Transponder checked and " .. helpers.TransponderPostotring(get(P.transponderpos)))
        end
    end

    if (procedureloop.stepindex == 9) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWTHROTTLE])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 10) then
        if (get(P.flapleverpos) > def.FLAPSUP) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                helpers.command_once("laminar/B738/push_button/flaps_0")
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Flaps Up")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Flaps checked and Up")
        end
    end

    if (procedureloop.stepindex == 11) then
        speedbrakeleverrounded = helpers.roundnumber(get(P.speedbrakelever), 1)
        if (speedbrakeleverrounded ~= def.SPEEDBRAKEDOWN) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                set(P.speedbrakelever, def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Retract Speed Brakes")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Speedbrakes Up and Retracted")
        end
    end

    if (procedureloop.stepindex == 12) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 13) then
        if ((get(P.fdpilotpos) == def.ON) or (get(P.fdfopos) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglefds(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Flight Directors Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Flight Directors checked and Off")
        end
    end

    if (procedureloop.stepindex == 14) then
        if ((get(P.efiswxpilotpos) == def.ON) or (get(P.efiswxfopos) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglewx(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Weather Radars Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Weather Radars checked and Off")
        end
    end

    if (procedureloop.stepindex == 15) then
        if ((get(P.efisterrpilotpos) == def.ON) or (get(P.efisterrfopos) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggleterr(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Terrain Radars Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Terrain Radars checked and Off")
        end
    end

    if (procedureloop.stepindex == 16) then
        if (get(P.autobrakepos) ~= def.AUTOBRAKEOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setautobrake(def.AUTOBRAKEOFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Auto Brake Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Auto Brake checked and Off")
        end
    end

    if (procedureloop.stepindex == 17) then
        if (get(P.aponstat) == def.ON) then
            set(P.aponstat, def.OFF)
        end
    end

    if (procedureloop.stepindex == 18) then
        P.iceprotection(def.OFF)
    end

    if (procedureloop.stepindex == 19) then
        helpers.command_once("laminar/B738/push_button/master_caution1")
    end

    return true

end

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

my_command_afterlanding = sasl.createCommand(def.APPNAMEPREFIX .. "/afterlanding", "After Landing Procedure")
sasl.registerCommandHandler(my_command_afterlanding, 0, P.afterlanding_)

--------------------------------------------------------------------------------------------------------------

function P.beforetaxisteps(procedureloop)


    if (procedureloop.stepindex == 1) then

        if not P.enginesrunning(BOTH) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.BEFORETAXIPROCEDURE].name .. " Procedure aborted, Engines not running")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if (get(P.chockstatus) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                helpers.command_once("laminar/B738/toggle_switch/chock")
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Remove Chocks")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) and (get(P.groundspeed) < 1) and not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Chocks checked and Removed")
        end
    end

    if ((procedureloop.stepindex == 3) and (get(P.domelightpos) == def.DOMELIGHTOFF)) then
        procedureloop.stepindex = 5
    end

    if (procedureloop.stepindex == 3) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 4) then
        if (get(P.domelightpos) ~= def.DOMELIGHTOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setdomelight(def.DOMELIGHTOFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Domelight Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Domelight checked and Off")
        end
    end

    if (procedureloop.stepindex == 5) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.taxilight) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggletaxilights(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Taxi Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Taxi Lights checked and On")
        end
    end

    if (procedureloop.stepindex == 7) then
        if(get(P.positionlights) ~= def.POSLIGHTSSTEADY) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglepositionlights(def.POSLIGHTSSTEADY)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Position Lights Steady")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Position Lights checked and Steady")
        end
    end

    if (procedureloop.stepindex == 8) then
        if (get(P.beaconlights) == def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Collision Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                P.togglecollisionlights(def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Collision Lights checked and On")
        end
    end

    if (procedureloop.stepindex == 9) then
        if (get(P.seatbeltsignpos) ~= def.SEATBELTSIGNON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setseatbeltsign(def.SEATBELTSIGNON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Seatbeltsigns On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Seatbeltsigns checked and On")
        end
    end

    if (procedureloop.stepindex == 10) then
        if (get(P.logolighton) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelogolight(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Logo Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Logo Lights checked and On")
        end
    end

    if (procedureloop.stepindex == 11) then
        if (get(P.yawdamperswitch) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Yaw Damper On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.yawdamperswitch, def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Yaw Damper checked and On")
        end
    end

    if (procedureloop.stepindex == 12) then
        if ((get(P.hydro1pos) ~= def.ON) or (get(P.hydro2pos) ~= def.ON) or (get(P.elechydro1pos) ~= def.ON) or (get(P.elechydro2pos) ~= def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Switch Hydraulic Pumps On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            else
                set(P.hydro1pos, def.ON)
                set(P.hydro2pos, def.ON)
                set(P.elechydro1pos, def.ON)
                set(P.elechydro2pos, def.ON)
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Hydraulic Pumps checked and On")
        end
    end

    if (procedureloop.stepindex == 13) then
        if ((get(P.wheatlfwdpos) == def.OFF) or (get(P.wheatrfwdpos) == def.OFF) or (get(P.wheatlsidepos) == def.OFF) or (get(P.wheatrsidepos) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglewindowheat(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Window Heat On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Window Heat checked and On")
        end
    end

    if (procedureloop.stepindex == 14) then
        if ((get(P.captainprobepos) == def.OFF) or (get(P.foprobepos) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggleprobeheat(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Probe Heat On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Probe Heat checked and On")
        end
    end

    if (procedureloop.stepindex == 15) then
        if ((get(P.starter1pos) ~= def.FLIGHT) or (get(P.starter2pos) ~= def.FLIGHT)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setstarter(def.BOTH, def.FLIGHT)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Starters Flight")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Both Starters checked and FLight")
        end
    end

    if (procedureloop.stepindex == 16) then
        if (P.apurunning() < def.APUOFFBUS) then
            if (get(P.bleedairapupos) == def.ON) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    set(P.bleedairapupos, def.OFF)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set A P U Bleed Air Off")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "A P U Bleed Air checked and Off")
            end
        end
    end

    if (procedureloop.stepindex == 17) then
        if ((get(P.bleedairapupos) == def.OFF) and (get(P.bleedair1pos) == def.ON) and (get(P.bleedair2pos) == def.ON)) then
            if (get(P.isolvalvepos) == def.ISOLVALVEOPEN) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    set(P.isolvalvepos, def.ISOLVALVEAUTO)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Isolation Valve Auto")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Isolation Valve checked and Auto")
            end
        end
    end

    if (procedureloop.stepindex == 18) then
        if ((get(P.bleedairapupos) == def.ON) or ((get(P.bleedair1pos) == def.ON) and (get(P.bleedair2pos) == def.ON))) then
            if ((get(P.packlpos) ~= def.PACKAUTO) or (get(P.packrpos) ~= def.PACKAUTO)) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Both Packs Auto")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    set(P.packlpos, def.PACKAUTO)
                    set(P.packrpos, def.PACKAUTO)
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Both Packs checked and Auto")
            end
        end
    end

    if (procedureloop.stepindex == 19) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWFMS])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 20) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.toflaps) == 0) then
                local toflapscalc = helpers.determineTakeoffFlapsSetting(get(P.totalweightkgs), get(P.deprwylen), get(P.deprwyheading), get(P.elevation), P.depmetar)
                if (get(P.toflaps) ~= toflapscalc) then                
                    P.commandtableentry(def.TEXT, "Set Takeoff Flaps " .. tostring(toflapscalc))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                elseif not procedureloop.steprepeat then
                    P.commandtableentry(def.TEXT, "Takeoff Flaps set and " .. tostring(get(P.toflaps)))
                end
            else
                P.commandtableentry(def.TEXT, "Takeoff Flaps set and " .. tostring(get(P.toflaps)))
            end
        end
    end

    if (procedureloop.stepindex == 21) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.fmccg) == 0) then
                P.commandtableentry(def.TEXT, "Set C G " .. tostring(helpers.roundnumber(get(P.tabcg),1)))
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif not procedureloop.steprepeat then
                P.commandtableentry(def.TEXT, "C G checked and " .. tostring(get(P.fmccg)))
            end
        end
    end

    if (procedureloop.stepindex == 22) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if ((get(P.v1setspeed) == 0) or (get(P.v2setspeed) == 0) or (get(P.vrsetspeed) == 0)) then
                P.commandtableentry(def.TEXT, "Enter V Speeds")
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif not procedureloop.steprepeat then
                P.commandtableentry(def.TEXT, "V Speeds checked and Set")
            end
        end
    end

    if (procedureloop.stepindex == 23) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 24) then
        if ((get(P.fdpilotpos) == def.OFF) or (get(P.fdfopos) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglefds(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Both Flight Directors On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Flight Directors checked and On")
        end
    end

    if (procedureloop.stepindex == 25) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.aplnavstat) ~= def.ON) then
                P.commandtableentry(def.TEXT, "Arm L NAV")
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif not procedureloop.steprepeat then
                P.commandtableentry(def.TEXT, "L NAV checked and Armed")
            end
        end
    end

    if (procedureloop.stepindex == 26) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.apvnavstat) ~= def.ON) then
                P.commandtableentry(def.TEXT, "Arm V NAV")
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif not procedureloop.steprepeat then
                P.commandtableentry(def.TEXT, "V NAV checked and Armed")
            end
        end
    end

    if (procedureloop.stepindex == 27) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWTHROTTLE])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 28) then
        if ((helpers.convflaplevertoflappos(get(P.flapleverpos)) ~= get(P.toflaps))) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                local toflapscmd = "laminar/B738/push_button/flaps_" .. get(P.toflaps)
                helpers.command_once(toflapscmd)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                toflapscmd = "Set Flap Lever " .. tostring(get(P.toflaps))
                P.commandtableentry(def.TEXT, toflapscmd)
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Flaps checked and " .. get(P.toflaps))
        end
    end

    if (procedureloop.stepindex == 29) then
        if (get(P.parkingbrakepos) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                set(P.parkingbrakepos, def.OFF)
            else
                P.commandtableentry(def.TEXT, "Release Parking Brake")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif ((not procedureloop.steprepeat) and (get(P.tirespeed) < 1)) then
            P.commandtableentry(def.TEXT, "Parking Brake checked and Released")
        end
    end

    if (procedureloop.stepindex == 30) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end

    end

    return true

end

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

my_command_beforetaxi = sasl.createCommand(def.APPNAMEPREFIX .. "/beforetaxi", "Before Taxi Procedure")
sasl.registerCommandHandler(my_command_beforetaxi, 0, P.beforetaxi_)

--------------------------------------------------------------------------------------------------------------

function P.beforetakeoffsteps(procedureloop)

    if (get(P.groundspeed) > 45) then
        procedureloop.procedureabort = true
        procedureloop.setonabort = true
        return true
    end

    if (procedureloop.stepindex == 1) then
        if (get(P.airgroundsensor) == def.OFF) then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.BEFORETAKEOFFPROCEDURE].name .. " Procedure not possible Inflight")
            return true
        end

        if not P.proceduretable[def.BEFORETAXIPROCEDURE].set then
            procedureloop.procedurenotpossible = true
            P.commandtableentry(def.TEXT, P.proceduretable[def.BEFORETAKEOFFPROCEDURE].name .. " Procedure Not Possible, before Taxi Procedure")
            return true
        end

        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWPEDESTAL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if (get(P.transponderpos) ~= def.TARA) then
            if (P.configvalues[def.CONFIGTRANSPONDER] ~= 0) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    P.toggletransponder(def.TARA)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Transponder T A R A")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Transponder checked and T A R A")
        end
    end

    if (procedureloop.stepindex == 3) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 4) then
        if(get(P.positionlights) ~= def.POSLIGHTSSTROBE) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglepositionlights(def.POSLIGHTSSTROBE)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Position Lights Strobe")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Position Lights checked and Strobe")
        end
    end

    if (procedureloop.stepindex == 5) then
        if ((get(P.llights1) == def.OFF) or (get(P.llights2) == def.OFF) or (get(P.llights3) == def.OFF) or (get(P.llights4) == def.OFF)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelandinglights(def.ON)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Landing Lights On")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Landing Lights checked and On")
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.taxilight) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggletaxilights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Taxi Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Taxi Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 7) then
        if ((get(P.rwylightl) == def.ON) or (get(P.rwylightl) == def.ON)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglerwylights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF) then
                P.commandtableentry(def.TEXT, "Set Runway Turnoff Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Runway Turnoff Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 8) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 9) then
        if (get(P.autobrakepos) ~= def.AUTOBRAKERTO) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setautobrake(def.AUTOBRAKERTO)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Auto Brake R T O")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Auto Brake checked and R T O")
        end
    end

    if (procedureloop.stepindex == 10) then
        local headingrounded = nil
        if (helpers.isvalidicao(get(P.depicao)) and helpers.isvalidrwy(get(P.deprwy)) and tonumber(get(P.deprwyheading))) then
            headingrounded = helpers.roundnumber(get(P.deprwyheading))
        end
        local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.depicao), get(P.deprwy))
        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
            headingrounded = navrwyheading
        end
        if headingrounded then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                if (get(P.mcpheading) ~= headingrounded) then
                    P.commandtableentry(def.TEXT, "Set M C P Heading" .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3)))
                    procedureloop.stepindex = procedureloop.stepindex - 1
                elseif not procedureloop.steprepeat then
                    P.commandtableentry(def.TEXT, "M C P Heading checked" .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3)))
                end
            end
        end
    end

    if (procedureloop.stepindex == 11) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.aplnavstat) ~= def.ON) then
                P.commandtableentry(def.TEXT, "Arm L NAV")
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif not procedureloop.steprepeat then
                P.commandtableentry(def.TEXT, "L NAV checked and Armed")
            end
        end
    end

    if (procedureloop.stepindex == 12) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.apvnavstat) ~= def.ON) then
                P.commandtableentry(def.TEXT, "Arm V NAV")
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif not procedureloop.steprepeat then
                P.commandtableentry(def.TEXT, "V NAV checked and Armed")
            end
        end
    end

    if (procedureloop.stepindex == 13) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if (get(P.atarmpos) ~= def.ON) then
                P.commandtableentry(def.TEXT, "Arm Autothrottle")
                procedureloop.stepindex = procedureloop.stepindex - 1
            elseif not procedureloop.steprepeat then
                P.commandtableentry(def.TEXT, "Autothrottle checked and Armed")
            end
        end
    end

    if (procedureloop.stepindex == 14) then
        local windreport = nil

        if (P.depmetar and P.airportdatatable[get(P.depicao)] and P.airportdatatable[get(P.depicao)].latitude and P.airportdatatable[get(P.depicao)].longitude) then
            windreport = helpers.formatWindSpeechSummary(P.depmetar, P.airportdatatable[get(P.depicao)].latitude, P.airportdatatable[get(P.depicao)].longitude)
        elseif (P.depmetar and helpers.isvalidrwy(get(P.deprwy))) then
            windreport = helpers.formatWindSpeechSummary(P.depmetar, get(P.deprwylatstartpos), get(P.deprwylonstartpos))
        end

        if (windreport  ~= nil) then
            P.commandtableentry(def.TEXT, windreport)
        end
    end


    return true

end

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

my_command_beforetakeoff = sasl.createCommand(def.APPNAMEPREFIX .. "/beforetakeoff", "Before Takeoff Procedure")
sasl.registerCommandHandler(my_command_beforetakeoff, 0, P.beforetakeoff_)

--------------------------------------------------------------------------------------------------------------

function P.atparkingpositionsteps(procedureloop)

    if (get(P.battery) ~= def.ON) then
        procedureloop.procedureabort = true
        return true
    end

    if (procedureloop.stepindex == 1) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(def.DEFAULTVIEW)
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 2) then
        if (get(P.chockstatus) ~= def.ON) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                helpers.command_once("laminar/B738/toggle_switch/chock")
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Chocks")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Chocks checked and Set")
        end
    end

    if ((procedureloop.stepindex == 3) and (get(P.sunpitchdegrees) > 0)) then
        procedureloop.stepindex = 5
    end

    if (procedureloop.stepindex == 3) then
        if ((P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) and (get(P.sunpitchdegrees) < 0)) then
            P.setview(P.configvalues[def.CONFIGVIEWUPPEROVERHEADPANEL])
        elseif ((P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON) and (get(P.sunpitchdegrees) < 0)) then
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 4) then
        if (get(P.sunpitchdegrees) < 0) then
            if (get(P.domelightpos) == def.DOMELIGHTOFF) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Dome Light On")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                else
                    P.setdomelight(def.DOMELIGHTDIM)
                end
            elseif (not procedureloop.steprepeat) then
                P.commandtableentry(def.TEXT, "Dome light checked and On")
            end
        end
    end

    if (procedureloop.stepindex == 5) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWPEDESTAL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 6) then
        if (get(P.transponderpos) ~= def.STANDBY) then
            if (P.configvalues[def.CONFIGTRANSPONDER] ~= 0) then
                if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                    P.toggletransponder(def.STANDBY)
                elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Transponder Standby")
                    procedureloop.stepindex = procedureloop.stepindex - 1
                end
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Transponder checked and Standby")
        end
    end

    if (procedureloop.stepindex == 7) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    if (procedureloop.stepindex == 8) then
        if (get(P.taxilight) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.toggletaxilights(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Taxi Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Taxi Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 9) then
        if (get(P.logolighton) ~= def.OFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.togglelogolight(def.OFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Logo Lights Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Logo Lights checked and Off")
        end
    end

    if (procedureloop.stepindex == 10) then
        if (get(P.seatbeltsignpos) ~= def.SEATBELTSIGNOFF) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setseatbeltsign(def.SEATBELTSIGNOFF)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                P.commandtableentry(def.TEXT, "Set Seatbeltsigns Off")
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            P.commandtableentry(def.TEXT, "Seatbeltsigns checked and Off")
        end
    end

    if (procedureloop.stepindex == 11) then
        if ((get(P.starter1pos) ~= def.AUTO) or (get(P.starter2pos) ~= def.AUTO)) then
            if (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON) then
                P.setstarter(def.BOTH, def.AUTO)
            elseif (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
                if (get(P.starterauto) == def.ON) then
                    P.commandtableentry(def.TEXT, "Set Both Starters Auto")
                else
                    P.commandtableentry(def.TEXT, "Set Both Starters Off")
                end
                procedureloop.stepindex = procedureloop.stepindex - 1
            end
        elseif (not procedureloop.steprepeat) then
            if (get(P.starterauto) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Starters checked and Auto")
            else
                P.commandtableentry(def.TEXT, "Both Starters checked and Off")
            end
        end
    end

    if (procedureloop.stepindex == 12) then
        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
            P.setview(P.configvalues[def.CONFIGVIEWMAINPANEL])
        else
            procedureloop.stepindex = procedureloop.stepindex + 1
            procedureloop.stepindexprevious = procedureloop.stepindexprevious + 1
        end
    end

    return true

end

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

my_command_atparkingposition = sasl.createCommand(def.APPNAMEPREFIX .. "/atparkingposition", "At Parking Position")
sasl.registerCommandHandler(my_command_atparkingposition, 0, P.atparkingposition_)

--------------------------------------------------------------------------------------------------------------
function P.inflightrestoreactions()

    P.readconfig()

    if ((P.configvalues[def.CONFIGAUTOBARO] == def.ON) and (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON)) then
        if ((get(P.altitude) > get(P.fmctransalt)) and (get(P.barostd) == def.OFF)) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
        end

        if ((get(P.altitude) < get(P.fmctranslvl)) and (get(P.barostd) == def.ON)) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
            local baroinchtmp, baropastemp = P.getlocalqnh(ARRIVAL)
            set(P.baropilot, baroinchtmp)
        end
    end

end

--------------------------------------------------------------------------------------------------------------
function P.synchronizeProcedureStates()
    local currentFlightState = P.flightstate
    if currentFlightState == 0 then
        return
    end

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
                end
            end
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function P.autofunctions()
    local aircraftIsOnGround = (get(P.airgroundsensor) == def.ON)

    if aircraftIsOnGround then
        P.aircraftwasonground = true

        if (get(P.taxilight) ~= def.OFF) and P.enginesrunning(BOTH) and (get(P.groundspeed) < 45) then
            P.triggerprocedure(def.BEFORETAXIPROCEDURE)
        end

        if (((helpers.aircraftonrwy(get(P.aircraftlatpos), get(P.aircraftlonpos), get(P.deprwylatstartpos), get(P.deprwylonstartpos), get(P.deprwylatendpos), get(P.deprwylonendpos), 0.0003) and
             (helpers.headingdiff(get(P.groundtrackmag), get(P.deprwyheading)) < 20) and (helpers.roundnumber(get(P.groundspeed)) == 0))) or (get(P.positionlights) == def.POSLIGHTSSTROBE)) then
            P.triggerprocedure(def.BEFORETAKEOFFPROCEDURE)
        end
        
        if (get(P.groundspeed) < 45) and 
           (((not helpers.aircraftonrwy(get(P.aircraftlatpos), get(P.aircraftlonpos), P.desrwylatstartpostemp, P.desrwylonstartpostemp, P.desrwylatendpostemp, P.desrwylonendpostemp, 0.0001)) and
             (helpers.headingdiff(get(P.groundtrackmag), P.desrwyheadingtemp) > 20)) or (helpers.roundnumber(get(P.groundspeed)) == 0) or (get(P.positionlights) == def.POSLIGHTSSTEADY)) then
            
            if P.triggerprocedure(def.AFTERLANDINGPROCEDURE) then
                P.flightstate = def.FLIGHTSTATETAXITOGATE
            end
        end

        if (get(P.parkingbrakepos) == def.ON) then
            if P.triggerprocedure(def.ATPARKINGPOSITIONPROCEDURE) then
                P.flightstate = def.FLIGHTSTATESHUTDOWN
            end
        end

    else
        if not P.aircraftwasonground then
            P.inflightrestoreactions()

            local fmsPhase = get(P.fmsflightphase)
            if (fmsPhase >= def.FMSPHASEDESCENT) then
                P.flightstate = def.FLIGHTSTATEAPPROACH
            elseif (fmsPhase == def.FMSPHASECRUISE) then
                P.flightstate = def.FLIGHTSTATECRUISE
            else
                P.flightstate = def.FLIGHTSTATECLIMB
            end

            P.synchronizeProcedureStates()

            P.aircraftwasonground = true
        end

        local fmsPhase = get(P.fmsflightphase)
        if (fmsPhase >= def.FMSPHASEDESCENT) then
            P.flightstate = def.FLIGHTSTATEAPPROACH
        elseif (fmsPhase == def.FMSPHASECRUISE) and (P.flightstate < def.FLIGHTSTATECRUISE) then
            P.flightstate = def.FLIGHTSTATECRUISE
        elseif (fmsPhase == def.FMSPHASECLIMB) and P.proceduretable[def.AFTERTAKEOFFPROCEDURE].set and (P.flightstate < def.FLIGHTSTATECLIMB) then
            P.flightstate = def.FLIGHTSTATECLIMB
        elseif (P.flightstate == def.FLIGHTSTATEPREFLIGHT) then
            P.flightstate = def.FLIGHTSTATEINITIALCLIMB
        end

        if P.flightstate == def.FLIGHTSTATEINITIALCLIMB then
            P.triggerprocedure(def.AFTERTAKEOFFPROCEDURE)
        elseif P.flightstate == def.FLIGHTSTATECLIMB then
            P.duringclimb()
        elseif P.flightstate == def.FLIGHTSTATEAPPROACH then
            P.duringdescent()
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------

function P.voicereadback()


    if (get(P.pausetod) ~= P.pausetodtemp) then
        if (get(P.pausetod) == def.ON) then
            P.commandtableentry(def.TEXT, "Pause at Top of Descent On")
        else
            P.commandtableentry(def.TEXT, "Pause at Top of Descent Off")
        end

        P.pausetodtemp = get(P.pausetod)
    end

    if (get(P.simfreezed) ~= P.simfreezedtemp) then
        if (get(P.simfreezed) == def.ON) then
            P.commandtableentry(def.TEXT, "Sim Freeze On")
        else
            P.commandtableentry(def.TEXT, "Sim Freeze Off")
        end

        P.simfreezedtemp = get(P.simfreezed)
    end

    if (get(P.chockstatus) ~= P.chockstatustmp) then
        if (get(P.chockstatus) == def.ON) then
            P.commandtableentry(def.TEXT, "Chocks Set")
        else
            P.commandtableentry(def.TEXT, "Chocks Removed")
        end

        P.chockstatustmp = get(P.chockstatus)
    end


    if (math.abs(get(P.totalfuellbs) - P.totalfuellbstemp) > 200) then
        if (get(P.totalfuellbs) ~= P.totalfuellbstemp2) then
            P.totalfuellbstemp2 = get(P.totalfuellbs)
        else
            if (get(P.fuelunit) == def.LBS) then
                P.commandtableentry(def.TEXT, "Fuel quantity " .. tostring(get(P.totalfuellbs)) .. "L B S")
            else
                P.commandtableentry(def.TEXT, "Fuel quantity " .. tostring(get(P.totalfuelkgs)) .. "K G")
            end
            P.totalfuellbstemp = get(P.totalfuellbs)
        end
    else
        P.totalfuellbstemp = get(P.totalfuellbs)
    end

    if (get(P.cabincruisealt) ~= P.cabincruisealttemp) then
        if (get(P.cabincruisealt) ~= P.cabincruisealttemp2) then
            P.cabincruisealttemp2 = get(P.cabincruisealt)
        else
            P.commandtableentry(def.TEXT, "Cabin Cruise Altitude " .. tostring(get(P.cabincruisealt)))
            P.cabincruisealttemp = get(P.cabincruisealt)
            P.cabincruisealttemp2 = get(P.cabincruisealt)
        end
    end

    if (get(P.cabinlandingalt) ~= P.cabinlandingalttemp) then
        if (get(P.cabinlandingalt) ~= P.cabinlandingalttemp2) then
            P.cabinlandingalttemp2 = get(P.cabinlandingalt)
        else
            P.commandtableentry(def.TEXT, "Cabin Landing Altitude " .. tostring(get(P.cabinlandingalt)))
            P.cabinlandingalttemp = get(P.cabinlandingalt)
            P.cabinlandingalttemp2 = get(P.cabinlandingalt)
        end
    end

    if (get(P.mcpspeed) ~= P.mcpspeedtemp) then
        if ((get(P.atarmpos) == def.OFF) or (get(P.atspeedstat) == def.ON) or (get(P.atspeedintvstat) == def.ON)) then
            if (get(P.mcpspeed) ~= P.mcpspeedtemp2) then
                P.mcpspeedtemp2 = get(P.mcpspeed)
            else
                P.mcpspeedtemp = get(P.mcpspeed)
                P.mcpspeedtemp2 = get(P.mcpspeed)

                if (get(P.mcpspeed) < 1) then
                    speed = helpers.roundnumber(get(P.mcpspeed), 2)
                else
                    speed = helpers.roundnumber(get(P.mcpspeed))
                end

                if ((P.flightstate > def.FLIGHTSTATECRUISE) and (get(P.mcpspeed) == get(P.vref))) then
                    P.commandtableentry(def.TEXT, "M C P Speed set to V REF " .. tostring(speed))
                else
                    P.commandtableentry(def.TEXT, "M C P Speed " .. tostring(speed))
                end
            end
        end
    end

    if (get(P.mcpheading) ~= P.mcpheadingtemp) then
        if (get(P.mcpheading) ~= P.mcpheadingtemp2) then
            P.mcpheadingtemp2 = get(P.mcpheading)
        else
            P.mcpheadingtemp = get(P.mcpheading)
            P.mcpheadingtemp2 = get(P.mcpheading)

            P.commandtableentry(def.TEXT, "M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcpheading), 3)))
        end
    end

    if (get(P.mcpaltitude) ~= P.mcpaltitudetemp) then
        if (get(P.mcpaltitude) ~= P.mcpaltitudetemp2) then
            P.mcpaltitudetemp2 = get(P.mcpaltitude)
        else
            P.mcpaltitudetemp = get(P.mcpaltitude)
            P.mcpaltitudetemp2 = get(P.mcpaltitude)

            if (get(P.mcpaltitude) == get(P.fmccruisealt)) then
                P.commandtableentry(def.TEXT, "M C P set to Cruise Altitude " .. helpers.addspaces(get(P.mcpaltitude)))
            else
                P.commandtableentry(def.TEXT, "M C P Altitude " .. helpers.addspaces(get(P.mcpaltitude)))
            end
        end
    end

    if (get(P.mcpvsspeed) ~= P.mcpvsspeedtemp) then
        if (get(P.mcpvsspeed) ~= P.mcpvsspeedtemp2) then
            P.mcpvsspeedtemp2 = get(P.mcpvsspeed)
        else
            P.mcpvsspeedtemp = get(P.mcpvsspeed)
            P.mcpaltitudetemp2 = get(P.mcpvsspeed)

            if ((get(P.mcpvsspeed) ~= 0) and (get(P.apalthldstat) ~= def.ON) and (get(P.apvnavstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "M C P Vertical Speed " .. tostring(get(P.mcpvsspeed)))
            end
        end
    end

    if (get(P.mcppilotcourse) ~= P.mcppilotcoursetemp) then
        if (get(P.mcppilotcourse) ~= P.mcppilotcoursetemp2) then
            P.mcppilotcoursetemp2 = get(P.mcppilotcourse)
        else
            P.mcppilotcoursetemp = get(P.mcppilotcourse)
            P.mcppilotcoursetemp2 = get(P.mcppilotcourse)

            P.commandtableentry(def.TEXT, "M C P Pilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcppilotcourse), 3)))
        end
    end

    if (get(P.mcpcopilotcourse) ~= P.mcpcopilotcoursetemp) then
        if (get(P.mcpcopilotcourse) ~= P.mcpcopilotcoursetemp2) then
            P.mcpcopilotcoursetemp2 = get(P.mcpcopilotcourse)
        else
            P.mcpcopilotcoursetemp = get(P.mcpcopilotcourse)
            P.mcpcopilotcoursetemp2 = get(P.mcpcopilotcourse)

            P.commandtableentry(def.TEXT, "M C P Copilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(get(P.mcpcopilotcourse), 3)))
        end
    end

    if (get(P.dhpilot) ~= P.dhpilottemp) then
        if (get(P.dhpilot) ~= P.dhpilottemp2) then
            P.dhpilottemp2 = get(P.dhpilot)
        else
            P.dhpilottemp = get(P.dhpilot)
            P.dhpilottemp2 = get(P.dhpilot)

            if ((get(P.dhpilot) == -1) or (get(P.dhpilot) == -1001)) then
                P.commandtableentry(def.TEXT, "Pilot Decision Altitude Reset")
            else
                P.commandtableentry(def.TEXT, "Pilot Decision Altitude " .. tostring(helpers.roundnumber(get(P.dhpilot))))
            end
        end
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

    if (get(P.aponstat) ~= P.aponstattemp) then
        if (get(P.aponstat) == def.OFF) then
            P.commandtableentry(def.TEXT, "Autopilot Off")
        end
        P.aponstattemp = get(P.aponstat)

    end

    if (get(P.apcmdastat) ~= P.apcmdastattemp) then
        if (get(P.apcmdastat) == def.ON) then
            P.commandtableentry(def.TEXT, "Command A On")
        else
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "Command A Off")
            end
        end
        P.apcmdastattemp = get(P.apcmdastat)
    end

    if (get(P.apcmdbstat) ~= P.apcmdbstattemp) then
        if (get(P.apcmdbstat) == def.ON) then
            P.commandtableentry(def.TEXT, "Command B On")

            if ((get(P.apcmdastat) == def.ON) and ((get(P.apgscapturedstat) ~= def.OFF) or (get(P.aploccapturedstat) ~= def.OFF))) then
                if (get(P.mmrinstalled) == def.ON) then
                    if ((get(P.mmrcptactvalue) ~= get(P.mmrfoactvalue)) or (get(P.mmrcptactmode) ~= get(P.mmrfoactmode)) or (get(P.mcppilotcourse) ~= get(P.mcpcopilotcourse))) then
                        P.commandtableentry(def.TEXT, "Warning Pilot and Copilot M M R Disagree")
                    end
                else
                    if ((get(P.nav1freq) ~= get(P.nav2freq)) or (get(P.mcppilotcourse) ~= get(P.mcpcopilotcourse))) then
                        P.commandtableentry(def.TEXT, "Warning Pilot and Copilot NAV Disagree")
                    end
                end
            end
        else
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "Command B Off")
            end
        end
        P.apcmdbstattemp = get(P.apcmdbstat)
    end

    if (get(P.apvnavstat) ~= P.apvnavstattemp) then
        if (get(P.apvnavstat) == def.ON) then
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "V NAV On")
            else
                P.commandtableentry(def.TEXT, "V NAV Armed")
            end
        else
            if ((get(P.aponstat) == def.ON) and (get(P.apgscapturedstat) ~= def.CAPTURED) and (get(P.aploccapturedstat) ~= def.CAPTURED) and (get(P.aplpvgscapturedstat) ~= def.CAPTURED) and
                (get(P.aplpvloccapturedstat) ~= def.CAPTURED) and (get(P.apglsgscapturedstat) ~= def.CAPTURED) and (get(P.apglsloccapturedstat) ~= def.CAPTURED) and
                (get(P.apfacgscapturedstat) ~= def.CAPTURED) and (get(P.apfacloccapturedstat) ~= def.CAPTURED) and (get(P.apalthldstat) ~= def.ON) and (get(P.apvsstat) ~= def.ON) and (get(P.aplvlchgstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "V NAV Off")
            end
        end
        P.apvnavstattemp = get(P.apvnavstat)
    end

    if (get(P.aplnavstat) ~= P.aplnavstattemp) then
        if (get(P.aplnavstat) == def.ON) then
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "L NAV On")
            else
                P.commandtableentry(def.TEXT, "L NAV Armed")
            end
        else
            if ((get(P.aponstat) == def.ON) and (get(P.aploccapturedstat) ~= def.CAPTURED) and (get(P.apgscapturedstat) ~= def.CAPTURED) and (get(P.aplpvloccapturedstat) ~= def.CAPTURED) and
                (get(P.aplpvgscapturedstat) ~= def.CAPTURED) and (get(P.apglsgscapturedstat) ~= def.CAPTURED) and (get(P.apglsloccapturedstat) ~= def.CAPTURED) and
                (get(P.apfacgscapturedstat) ~= def.CAPTURED) and (get(P.apfacloccapturedstat) ~= def.CAPTURED) and (get(P.aphdgselstat) ~= def.ON) and (get(P.apappstat) ~= def.ON) and
                (get(P.apvorlocstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "L NAV Off")
            end
        end
        P.aplnavstattemp = get(P.aplnavstat)
    end

    if (get(P.apappstat) ~= P.apappstattemp) then
        if (get(P.apappstat) == def.ON) then
            if (get(P.aponstat) == def.ON) then
                if ((get(P.apgscapturedstat) == def.ARMED) and (get(P.aploccapturedstat) == def.ARMED)) then
                    P.commandtableentry(def.TEXT, "Approach Armed")
                elseif ((get(P.aplpvgscapturedstat) == def.ARMED) and (get(P.aplpvloccapturedstat) == def.ARMED)) then
                    P.commandtableentry(def.TEXT, "L P V Approach Armed")
                elseif ((get(P.apglsgscapturedstat) == def.ARMED) and (get(P.apglsloccapturedstat) == def.ARMED)) then
                    P.commandtableentry(def.TEXT, "G L S Approach Armed")
                elseif ((get(P.apfacgscapturedstat) == def.ARMED) and (get(P.apfacloccapturedstat) == def.ARMED)) then
                    P.commandtableentry(def.TEXT, "F A C Approach Armed")
                end
            else
                P.commandtableentry(def.TEXT, "Approach Armed")
            end
        else
            if ((get(P.aponstat) == def.ON) and (get(P.apgscapturedstat) ~= def.CAPTURED) and (get(P.aploccapturedstat) ~= def.CAPTURED) and (get(P.aplpvgscapturedstat) ~= def.CAPTURED) and
                (get(P.aplpvloccapturedstat) ~= def.CAPTURED) and (get(P.apglsgscapturedstat) ~= def.CAPTURED) and (get(P.apglsloccapturedstat) ~= def.CAPTURED) and
                (get(P.apfacgscapturedstat) ~= def.CAPTURED) and (get(P.apfacloccapturedstat) ~= def.CAPTURED) and (get(P.aphdgselstat) ~= def.ON) and (get(P.aplnavstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "Approach Off")
            end
        end
        P.apappstattemp = get(P.apappstat)
    end

    if (get(P.apgscapturedstat) ~= P.apgscapturedstattemp) then
        if (get(P.apgscapturedstat) == def.CAPTURED) then
            P.commandtableentry(def.TEXT, "Glide Slope Captured")
        end
        P.apgscapturedstattemp = get(P.apgscapturedstat)
    end

    if (get(P.aploccapturedstat) ~= P.aploccapturedstattemp) then
        if (get(P.aploccapturedstat) == def.CAPTURED) then
            P.commandtableentry(def.TEXT, "Localizer Captured")
        end
        P.aploccapturedstattemp = get(P.aploccapturedstat)
    end

    if ((get(P.apflarestat) ~= P.apflarestattemp) or (get(P.aprolloutstat) ~= P.aprolloutstattemp)) then
        if ((get(P.apflarestat) == def.ON) and (get(P.aprolloutstat) == def.ON)) then
            P.commandtableentry(def.TEXT, "Autoland Armed")
            P.apflarestattemp = get(P.apflarestat)
            P.aprolloutstattemp = get(P.aprolloutstat)
        end
    end

    if (get(P.apvorlocstat) ~= P.apvorlocstattemp) then
        if (get(P.apvorlocstat) == def.ON) then
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "V O R Localizer On")
            else
                P.commandtableentry(def.TEXT, "V O R Localizer Armed")
            end
        else
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "V O R Localizer Off")
            end
        end
        P.apvorlocstattemp = get(P.apvorlocstat)
    end

    if (get(P.apfacgscapturedstat) ~= P.apfacgscapturedstattemp) then
        if (get(P.apfacgscapturedstat) == def.CAPTURED) then
            P.commandtableentry(def.TEXT, "Glide Path Captured")
        end
        P.apfacgscapturedstattemp = get(P.apfacgscapturedstat)
    end

    if (get(P.apfacloccapturedstat) ~= P.apfacloccapturedstattemp) then
        if (get(P.apfacloccapturedstat) == def.CAPTURED) then
            P.commandtableentry(def.TEXT, "F A C Localizer Captured")
        end
        P.apfacloccapturedstattemp = get(P.apfacloccapturedstat)
    end

    if (get(P.lpvinstalled) == def.ON) then
        if (get(P.aplpvgscapturedstat) ~= P.aplpvgscapturedstattemp) then
            if (get(P.aplpvgscapturedstat) == def.CAPTURED) then
                P.commandtableentry(def.TEXT, "L P V Glide Slope Captured")
            end
            P.aplpvgscapturedstattemp = get(P.aplpvgscapturedstat)
        end

        if (get(P.aplpvloccapturedstat) ~= P.aplpvloccapturedstattemp) then
            if (get(P.aplpvloccapturedstat) == def.CAPTURED) then
                P.commandtableentry(def.TEXT, "L P V Localizer Captured")
            end
            P.aplpvloccapturedstattemp = get(P.aplpvloccapturedstat)
        end

        if (get(P.apglsgscapturedstat) ~= P.apglsgscapturedstattemp) then
            if (get(P.apglsgscapturedstat) == def.CAPTURED) then
                P.commandtableentry(def.TEXT, "G L S Glide Slope Captured")
            end
            P.apglsgscapturedstattemp = get(P.apglsgscapturedstat)
        end

        if (get(P.apglsloccapturedstat) ~= P.apglsloccapturedstattemp) then
            if (get(P.apglsloccapturedstat) == def.CAPTURED) then
                P.commandtableentry(def.TEXT, "G L S Localizer Captured")
            end
            P.apglsloccapturedstattemp = get(P.apglsloccapturedstat)
        end
    end

    if (get(P.apalthldstat) ~= P.apalthldstattemp) then
        if (get(P.apalthldstat) == def.ON) then
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "Altitude Hold On, Altitude " .. tostring(get(P.mcpaltitude)))
            else
                P.commandtableentry(def.TEXT, "Altitude Hold Armed")
            end
        else
            if ((get(P.aponstat) == def.ON) and (get(P.apvsstat) ~= def.ON) and (get(P.aplvlchgstat) ~= def.ON) and (get(P.apgscapturedstat) ~= def.CAPTURED) and (get(P.aplpvgscapturedstat) ~= def.CAPTURED) and
                (get(P.apglsgscapturedstat) ~= def.CAPTURED) and (get(P.apfacgscapturedstat) ~= def.CAPTURED) and (get(P.apvnavstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "Altitude Hold Off")
            end
        end
        P.apalthldstattemp = get(P.apalthldstat)
    end

    if (get(P.aphdgselstat) ~= P.aphdgselstattemp) then
        if (get(P.aphdgselstat) == def.ON) then
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "Heading Select On, Heading " .. tostring(helpers.padNumberWithZerosStrict(get(P.mcpheading),3)))
            else
                P.commandtableentry(def.TEXT, "Heading Select Armed")
            end
        else
            if ((get(P.aponstat) == def.ON) and (get(P.aplnavstat) ~= def.ON) and (get(P.apvorlocstat) ~= def.ON) and (get(P.aploccapturedstat) ~= def.CAPTURED)) then
                P.commandtableentry(def.TEXT, "Heading Select Off")
            end
        end
        P.aphdgselstattemp = get(P.aphdgselstat)
    end

    if (get(P.apvsstat) ~= P.apvsstattemp) then
        if (get(P.apvsstat) == def.ON) then
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "Vertical Speed On")
            else
                P.commandtableentry(def.TEXT, "Vertical Speed Armed")
            end
        else
            if ((get(P.aponstat) == def.ON) and (get(P.mcpvsspeed) ~= 0) and (get(P.apalthldstat) ~= def.ON) and (get(P.apvnavstat) ~= def.ON) and (get(P.aplvlchgstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "Vertical Speed Off")
            end
        end
        P.apvsstattemp = get(P.apvsstat)
    end

    if (get(P.aplvlchgstat) ~= P.aplvlchgstattemp) then
        if (get(P.aplvlchgstat) == def.ON) then
            if (get(P.aponstat) == def.ON) then
                P.commandtableentry(def.TEXT, "Level Change On")
            else
                P.commandtableentry(def.TEXT, "Level Change Armed")
            end
        else
            if ((get(P.aponstat) == def.ON) and (get(P.mcpvsspeed) ~= 0) and (get(P.apalthldstat) ~= def.ON) and (get(P.apvnavstat) ~= def.ON) and (get(P.apvsstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "Level Change Off")
            end
        end
        P.aplvlchgstattemp = get(P.aplvlchgstat)
    end

    if (get(P.atarmpos) ~= P.atarmpostemp) then
        if (get(P.atarmpos) == def.ON) then
            P.commandtableentry(def.TEXT, "Autothrottle Armed")

        else
            P.commandtableentry(def.TEXT, "Autothrottle Off")
        end
        P.atarmpostemp = get(P.atarmpos)
    end

    if (get(P.atn1stat) ~= P.atn1stattemp) then
        if ((get(P.atn1stat) == def.ON) and (get(P.airgroundsensor) == def.ON)) then
            if (get(P.atarmpos) == def.ON) then
                P.commandtableentry(def.TEXT, "N 1 On")
            else
                P.commandtableentry(def.TEXT, "N 1 Armed")
            end
        else
            if ((get(P.atn1stat) == def.OFF) and (get(P.airgroundsensor) == def.ON)) then
                P.commandtableentry(def.TEXT, "N 1 Off")
            end
        end
        P.atn1stattemp = get(P.atn1stat)
    end

    if (get(P.atspeedstat) ~= P.atspeedstattemp) then
        if ((get(P.atspeedstat) == def.ON) and (get(P.apgscapturedstat) ~= def.CAPTURED) and (get(P.aplpvgscapturedstat) ~= def.CAPTURED) and (get(P.apglsgscapturedstat) ~= def.CAPTURED) and
            (get(P.apfacgscapturedstat) ~= def.CAPTURED) and (get(P.apvsstat) ~= def.ON)  and (get(P.aplvlchgstat) ~= def.ON)) then
            if (get(P.atarmpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Speed On")
            else
                P.commandtableentry(def.TEXT, "Speed Armed")
            end
        else
            if ((get(P.atspeedstat) == def.OFF) and (get(P.atarmpos) == def.ON) and (get(P.atn1stat) ~= def.ON) and (get(P.apvnavstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "Speed Off")
            end
        end
        P.atspeedstattemp = get(P.atspeedstat)
    end

    if (get(P.atspeedintvstat) ~= P.atspeedintvstattemp) then
        if (get(P.atspeedintvstat) == def.ON) then
            if (get(P.atarmpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Speed Intervention On")
            else
                P.commandtableentry(def.TEXT, "Speed Intervention Armed")
            end
        else
            if ((get(P.atarmpos) == def.ON) and (get(P.atn1stat) ~= def.ON) and (get(P.atspeedstat) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "Speed Intervention Off")
            end
        end
        P.atspeedintvstattemp = get(P.atspeedintvstat)
    end

    if ((get(P.baropilot) ~= P.baropilottemp) or (get(P.barostd) ~= P.barostdtemp)) then
        if (get(P.baropilot) ~= P.baropilottemp2) then
            P.baropilottemp2 = get(P.baropilot)
        else
            if ((get(P.barostd) == def.ON) and (get(P.barostd) ~= P.barostdtemp)) then
                P.commandtableentry(def.TEXT, "Q N H Standard")
            else
                if (get(P.baroinhpa) == def.ON) then
                    P.commandtableentry(def.TEXT, "Q N H " .. tostring(helpers.convertpressure(get(P.baropilot))))
                else
                    P.commandtableentry(def.TEXT, "Q N H " .. tostring(get(P.baropilot)))
                end
            end

            P.baropilottemp = get(P.baropilot)
            P.baropilottemp2 = get(P.baropilot)
            P.barostdtemp = get(P.barostd)
        end
    end

    if (get(P.taxilight) ~= P.taxilighttemp) then
        if (get(P.taxilight) ~= def.OFF) then
            P.commandtableentry(def.TEXT, "Taxi Lights On")
        else
            P.commandtableentry(def.TEXT, "Taxi Lights Off")
        end
        P.taxilighttemp = get(P.taxilight)
    end

    if (get(P.beaconlights) ~= P.beaconlightstemp) then
        if (get(P.beaconlights) == def.ON) then
            P.commandtableentry(def.TEXT, "Collision Lights On")
        else
            P.commandtableentry(def.TEXT, "Collision Lights Off")
        end
        P.beaconlightstemp = get(P.beaconlights)
    end

    if ((get(P.llightson) ~= P.llightsontemp) or (get(P.llights1) ~= P.llights1temp) or (get(P.llights2) ~= P.llights2temp) or (get(P.llights3) ~= P.llights3temp) or
        (get(P.llights4) ~= P.llights4temp)) then
        if ((get(P.llightson) == def.OFF) and (get(P.llights1) == def.OFF) and (get(P.llights2) == def.OFF) and (get(P.llights3) == def.OFF) and (get(P.llights4) == def.OFF)) then
            P.commandtableentry(def.TEXT, "Landing Lights Off")
        else
            if ((P.llightsontemp == def.OFF) and (P.llights1temp == def.OFF) and (P.llights2temp == def.OFF) and (P.llights3temp == def.OFF) and (P.llights4temp == def.OFF)) then
                P.commandtableentry(def.TEXT, "Landing Lights On")
            end
        end
        P.llightsontemp = get(P.llightson)
        P.llights1temp = get(P.llights1)
        P.llights2temp = get(P.llights2)
        P.llights3temp = get(P.llights3)
        P.llights4temp = get(P.llights4)
    end

    if ((get(P.rwylightl) ~= P.rwylightltemp) or (get(P.rwylightr) ~= P.rwylightrtemp)) then
        if (((get(P.rwylightl) ~= P.rwylightltemp) and (get(P.rwylightr) ~= P.rwylightrtemp)) and (get(P.rwylightl) == get(P.rwylightr))) then
            if ((get(P.rwylightl) == def.ON) and (get(P.rwylightr) == def.ON)) then
                P.commandtableentry(def.TEXT, "Both Runway Turnoff Lights On")
            else
                P.commandtableentry(def.TEXT, "Both Runway Turnoff Lights Off")
            end
            P.rwylightltemp = get(P.rwylightl)
            P.rwylightrtemp = get(P.rwylightr)
        else
            if (get(P.rwylightl) ~= P.rwylightltemp) then
                if (get(P.rwylightl) == def.ON) then
                    P.commandtableentry(def.TEXT, "Left Runway Turnoff Light On")
                else
                    P.commandtableentry(def.TEXT, "Left Runway Turnoff Light Off")
                end
                P.rwylightltemp = get(P.rwylightl)
            end

            if (get(P.rwylightr) ~= P.rwylightrtemp) then
                if (get(P.rwylightr) == def.ON) then
                    P.commandtableentry(def.TEXT, "Right Runway Turnoff Light On")
                else
                    P.commandtableentry(def.TEXT, "Right Runway Turnoff Light Off")
                end
                P.rwylightrtemp = get(P.rwylightr)
            end
        end
    end

    if (get(P.positionlights) ~= P.positionlightstemp) then
        if (get(P.positionlights) == def.POSLIGHTSOFF) then
            P.commandtableentry(def.TEXT, "Position Lights Off")
        elseif (get(P.positionlights) == def.POSLIGHTSSTEADY) then
            P.commandtableentry(def.TEXT, "Position Lights Steady")
        elseif (get(P.positionlights) == def.POSLIGHTSSTROBE) then
            P.commandtableentry(def.TEXT, "Position Lights Strobe")
        end
        P.positionlightstemp = get(P.positionlights)
    end

    if (get(P.logolighton) ~= P.logolightontemp) then

        if (get(P.logolighton) == def.ON) then
            P.commandtableentry(def.TEXT, "Logo Light On")
        else
            P.commandtableentry(def.TEXT, "Logo Light Off")
        end
        P.logolightontemp = get(P.logolighton)
    end

    if (get(P.transponderpos) ~= P.transponderpostemp) then
        P.commandtableentry(def.TEXT, "Transponder " .. helpers.TransponderPostotring(get(P.transponderpos)))
        P.transponderpostemp = get(P.transponderpos)
    end

    if (P.yawdamperswitchtemp ~= get(P.yawdamperswitch)) then
        if (get(P.yawdamperswitch) == def.ON) then
            P.commandtableentry(def.TEXT, "Yaw Damper On")
        else
            P.commandtableentry(def.TEXT, "Yaw Damper Off")
        end
        P.yawdamperswitchtemp = get(P.yawdamperswitch)
    end

    if ((get(P.fdpilotpos) ~= P.fdpilotpostemp) or (get(P.fdfopos) ~= P.fdfopostemp)) then
        if ((get(P.fdpilotpos) ~= P.fdpilotpostemp) and (get(P.fdfopos) ~= P.fdfopostemp) and (get(P.fdpilotpos) == get(P.fdfopos))) then
            if (get(P.fdpilotpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Flightdirectors On")
            else
                P.commandtableentry(def.TEXT, "Both Flightdirectors Off")
            end
            P.fdpilotpostemp = get(P.fdpilotpos)
            P.fdfopostemp = get(P.fdfopos)
        else
            if (get(P.fdpilotpos) ~= P.fdpilotpostemp) then
                if (get(P.fdpilotpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot Flightdirector On")
                else
                    P.commandtableentry(def.TEXT, "Pilot Flightdirector Off")
                end
                P.fdpilotpostemp = get(P.fdpilotpos)
            end

            if (get(P.fdfopos) ~= P.fdfopostemp) then
                if (get(P.fdfopos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot Flightdirector On")
                else
                    P.commandtableentry(def.TEXT, "Copilot Flightdirector Off")
                end
                P.fdfopostemp = get(P.fdfopos)
            end
        end
    end

    if ((get(P.efiswxpilotpos) ~= P.efiswxpilotpostemp) or (get(P.efiswxfopos) ~= P.efiswxfopostemp)) then
        if ((get(P.efiswxpilotpos) ~= P.efiswxpilotpostemp) and (get(P.efiswxfopos) ~= P.efiswxfopostemp) and (get(P.efiswxpilotpos) == get(P.efiswxfopos))) then
            if (get(P.efiswxpilotpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Weather Radars On")
            elseif (get(P.efisterrpilotpos) == def.OFF) then
                P.commandtableentry(def.TEXT, "Both Weather Radars Off")
            end
            P.efiswxpilotpostemp = get(P.efiswxpilotpos)
            P.efiswxfopostemp = get(P.efiswxfopos)
        else
            if (get(P.efiswxpilotpos) ~= P.efiswxpilotpostemp) then
                if (get(P.efiswxpilotpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot Weather Radar On")
                elseif (get(P.efisterrpilotpos) == def.OFF) then
                    P.commandtableentry(def.TEXT, "Pilot Weather Radar Off")
                end
                P.efiswxpilotpostemp = get(P.efiswxpilotpos)
            end

            if (get(P.efiswxfopos) ~= P.efiswxfopostemp) then
                if (get(P.efiswxfopos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot Weather Radar On")

                elseif (get(P.efisterrfopos) == def.OFF) then
                    P.commandtableentry(def.TEXT, "Copilot Weather Radar Off")
                end
                P.efiswxfopostemp = get(P.efiswxfopos)
            end
        end
    end

    if ((get(P.efisterrpilotpos) ~= P.efisterrpilotpostemp) or (get(P.efisterrfopos) ~= P.efisterrfopostemp)) then
        if ((get(P.efisterrpilotpos) ~= P.efisterrpilotpostemp) and (get(P.efisterrfopos) ~= P.efisterrfopostemp) and (get(P.efisterrpilotpos) == get(P.efisterrfopos))) then
            if (get(P.efisterrpilotpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Terrain Radars On")
            elseif (get(P.efiswxpilotpos) == def.OFF) then
                P.commandtableentry(def.TEXT, "Both Terrain Radars Off")
            end
            P.efisterrpilotpostemp = get(P.efisterrpilotpos)
            P.efisterrfopostemp = get(P.efisterrfopos)
        else
            if (get(P.efisterrpilotpos) ~= P.efisterrpilotpostemp) then
                if (get(P.efisterrpilotpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot Terrain Radar On")
                elseif (get(P.efiswxpilotpos) == def.OFF) then
                    P.commandtableentry(def.TEXT, "Pilot Terrain Radar Off")
                end
                P.efisterrpilotpostemp = get(P.efisterrpilotpos)
            end

            if (get(P.efisterrfopos) ~= P.efisterrfopostemp) then
                if (get(P.efisterrfopos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot Terrain Radar On")
                elseif (get(P.efiswxfopos) == def.OFF) then
                    P.commandtableentry(def.TEXT, "Copilot Terrain Radar Off")
                end
                P.efisterrfopostemp = get(P.efisterrfopos)
            end
        end
    end

    if ((get(P.efisdatapilotpos) ~= P.efisdatapilotpostemp) or (get(P.efisdatafopos) ~= P.efisdatafopostemp)) then
        if ((get(P.efisdatapilotpos) ~= P.efisdatapilotpostemp) and (get(P.efisdatafopos) ~= P.efisdatafopostemp) and (get(P.efisdatafopos) == get(P.efisdatafopos))) then
            if (get(P.efisdatapilotpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both E F I S Data On")
            else
                P.commandtableentry(def.TEXT, "Both E F I S DATA Off")
            end
            P.efisdatapilotpostemp = get(P.efisdatapilotpos)
            P.efisdatafopostemp = get(P.efisdatafopos)
        else
            if (get(P.efisdatapilotpos) ~= P.efisdatapilotpostemp) then
                if (get(P.efisdatapilotpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot E F I S Data On")
                else
                    P.commandtableentry(def.TEXT, "Pilot E F I S Data Off")
                end
                P.efisdatapilotpostemp = get(P.efisdatapilotpos)
            end

            if (get(P.efisdatafopos) ~= P.efisdatafopostemp) then
                if (get(P.efisdatafopos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot E F I S Data On")
                else
                    P.commandtableentry(def.TEXT, "Copilot E F I S Data Off")
                end
                P.efisdatafopostemp = get(P.efisdatafopos)
            end
        end
    end

       if ((get(P.efisfixpilotpos) ~= P.efisfixpilotpostemp) or (get(P.efisfixfopos) ~= P.efisfixfopostemp)) then
        if ((get(P.efisfixpilotpos) ~= P.efisfixpilotpostemp) and (get(P.efisfixfopos) ~= P.efisfixfopostemp) and (get(P.efisfixfopos) == get(P.efisfixfopos))) then
            if (get(P.efisfixpilotpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both E F I S Waypoint On")
            else
                P.commandtableentry(def.TEXT, "Both E F I S Waypoint Off")
            end
            P.efisfixpilotpostemp = get(P.efisfixpilotpos)
            P.efisfixfopostemp = get(P.efisfixfopos)
        else
            if (get(P.efisfixpilotpos) ~= P.efisfixpilotpostemp) then
                if (get(P.efisfixpilotpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot E F I S Waypoint On")
                else
                    P.commandtableentry(def.TEXT, "Pilot E F I S Waypoint Off")
                end
                P.efisfixpilotpostemp = get(P.efisfixpilotpos)
            end

            if (get(P.efisfixfopos) ~= P.efisfixfopostemp) then
                if (get(P.efisfixfopos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot E F I S Waypoint On")
                else
                    P.commandtableentry(def.TEXT, "Copilot E F I S Waypoint Off")
                end
                P.efisfixfopostemp = get(P.efisfixfopos)
            end
        end
    end

    if ((get(P.efisairportpilotpos) ~= P.efisairportpilotpostemp) or (get(P.efisairportfopos) ~= P.efisairportfopostemp)) then
        if ((get(P.efisairportpilotpos) ~= P.efisairportpilotpostemp) and (get(P.efisairportfopos) ~= P.efisairportfopostemp) and (get(P.efisairportpilotpos) == get(P.efisairportfopos))) then
            if (get(P.efisairportpilotpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both E F I S Airport On")
            else
                P.commandtableentry(def.TEXT, "Both E F I S Airport Off")
            end
            P.efisairportpilotpostemp = get(P.efisairportpilotpos)
            P.efisairportfopostemp = get(P.efisairportfopos)
        else
            if (get(P.efisairportpilotpos) ~= P.efisairportpilotpostemp) then
                if (get(P.efisairportpilotpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot E F I S Airport On")
                else
                    P.commandtableentry(def.TEXT, "Pilot E F I S Airport Off")
                end
                P.efisairportpilotpostemp = get(P.efisairportpilotpos)
            end

            if (get(P.efisairportfopos) ~= P.efisairportfopostemp) then
                if (get(P.efisairportfopos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot E F I S Airport On")
                else
                    P.commandtableentry(def.TEXT, "Copilot E F I S Airport Off")
                end
                P.efisairportfopostemp = get(P.efisairportfopos)
            end
        end
    end

    if ((get(P.efispospilotpos) ~= P.efispospilotpostemp) or (get(P.efisposfopos) ~= P.efisposfopostemp)) then
        if ((get(P.efispospilotpos) ~= P.efispospilotpostemp) and (get(P.efisposfopos) ~= P.efisposfopostemp) and (get(P.efispospilotpos) == get(P.efisposfopos))) then
            if (get(P.efispospilotpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both E F I S Position On")
            else
                P.commandtableentry(def.TEXT, "Both E F I S Position Off")
            end
            P.efispospilotpostemp = get(P.efispospilotpos)
            P.efisposfopostemp = get(P.efisposfopos)
        else
            if (get(P.efispospilotpos) ~= P.efispospilotpostemp) then
                if (get(P.efispospilotpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot E F I S Position On")
                else
                    P.commandtableentry(def.TEXT, "Pilot E F I S Position Off")
                end
                P.efispospilotpostemp = get(P.efispospilotpos)
            end

            if (get(P.efisposfopos) ~= P.efisposfopostemp) then
                if (get(P.efisposfopos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot E F I S Position On")
                else
                    P.commandtableentry(def.TEXT, "Copilot E F I S Position Off")
                end
                P.efisposfopostemp = get(P.efisposfopos)
            end
        end
    end

    if ((get(P.efisvorpilotpos) ~= P.efisvorpilotpostemp) or (get(P.efisvorfopos) ~= P.efisvorfopostemp)) then
        if ((get(P.efisvorpilotpos) ~= P.efisvorpilotpostemp) and (get(P.efisvorfopos) ~= P.efisvorfopostemp) and (get(P.efisvorpilotpos) == get(P.efisvorfopos))) then
            if (get(P.efisvorpilotpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both E F I S Station On")
            else
                P.commandtableentry(def.TEXT, "Both E F I S Station Off")
            end
            P.efisvorpilotpostemp = get(P.efisvorpilotpos)
            P.efisvorfopostemp = get(P.efisvorfopos)
        else
            if (get(P.efisvorpilotpos) ~= P.efisvorpilotpostemp) then
                if (get(P.efisvorpilotpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot E F I S Station On")
                else
                    P.commandtableentry(def.TEXT, "Pilot E F I S Station Off")
                end
                P.efisvorpilotpostemp = get(P.efisvorpilotpos)
            end

            if (get(P.efisvorfopos) ~= P.efisvorfopostemp) then
                if (get(P.efisvorfopos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot E F I S Station On")
                else
                    P.commandtableentry(def.TEXT, "Copilot E F I S Station Off")
                end
                P.efisvorfopostemp = get(P.efisvorfopos)
            end
        end
    end

    if (get(P.mmrinstalled) == def.ON) then
        if ((get(P.mmrcptactmode) ~= P.mmrcptactmodetemp) or (get(P.mmrcptactvalue) ~= P.mmrcptactvaluetemp) or (get(P.mmrfoactmode) ~= P.mmrfoactmodetemp) or
            (get(P.mmrfoactvalue) ~= P.mmrfoactvaluetemp)) then
            local mmrstring = ""
            local mmrchannel = 0
            if (((get(P.mmrcptactmode) ~= P.mmrcptactmodetemp) or (get(P.mmrcptactvalue) ~= P.mmrcptactvaluetemp)) and
                ((get(P.mmrfoactmode) ~= P.mmrfoactmodetemp) or (get(P.mmrfoactvalue) ~= P.mmrfoactvaluetemp)) and (get(P.mmrcptactmode) == get(P.mmrfoactmode)) and
                (get(P.mmrcptactvalue) == get(P.mmrfoactvalue))) then
                if (get(P.mmrcptactmode) == def.MMRLOC) then
                    mmrstring = "Both M M R V O R "
                    mmrchannel = get(P.mmrcptactvalue) / 100
                elseif (get(P.mmrcptactmode) == def.MMRILS) then
                    mmrstring = "Both M M R I L S "
                    mmrchannel = get(P.mmrcptactvalue) / 100
                elseif (get(P.mmrcptactmode) == def.MMRGLS) then
                    mmrstring = "Both M M R G L S "
                    mmrchannel = get(P.mmrcptactvalue)
                elseif (get(P.mmrcptactmode) == def.MMRLPV) then
                    mmrstring = "Both M M R L P V "
                    mmrchannel = get(P.mmrcptactvalue)
                end
            else
                if ((get(P.mmrcptactmode) ~= get(P.mmrcptactmode)) or (get(P.mmrcptactvalue) ~= P.mmrcptactvaluetemp)) then
                    if (get(P.mmrcptactmode) == def.MMRLOC) then
                        mmrstring = "Pilot M M R V O R "
                        mmrchannel = get(P.mmrcptactvalue) / 100
                    elseif (get(P.mmrcptactmode) == def.MMRILS) then
                        mmrstring = "Pilot M M R I L S "
                        mmrchannel = get(P.mmrcptactvalue) / 100
                    elseif (get(P.mmrcptactmode) == def.MMRGLS) then
                        mmrstring = "Pilot M M R G L S "
                        mmrchannel = get(P.mmrcptactvalue)
                    elseif (get(P.mmrcptactmode) == def.MMRLPV) then
                        mmrstring = "Pilot M M R L P V "
                        mmrchannel = get(P.mmrcptactvalue)
                    end
                end

                if ((get(P.mmrfoactmode) ~= P.mmrfoactmodetemp) or (get(P.mmrfoactvalue) ~= P.mmrfoactvaluetemp)) then
                    if (get(P.mmrfoactmode) == def.MMRLOC) then
                        mmrstring = "Copilot M M R V O R "
                        mmrchannel = get(P.mmrfoactvalue) / 100
                    elseif (get(P.mmrfoactmode) == def.MMRILS) then
                        mmrstring = "Copilot M M R I L S "
                        mmrchannel = get(P.mmrfoactvalue) / 100
                    elseif (get(P.mmrfoactmode) == def.MMRGLS) then
                        mmrstring = "Copilot M M R G L S "
                        mmrchannel = get(P.mmrfoactvalue)
                    elseif (get(P.mmrfoactmode) == def.MMRLPV) then
                        mmrstring = "Copilot M M R L P V "
                        mmrchannel = get(P.mmrfoactvalue)
                    end
                end
            end

            P.commandtableentry(def.TEXT, mmrstring .. tostring(mmrchannel))

            P.mmrcptactmodetemp = get(P.mmrcptactmode)
            P.mmrcptactvaluetemp = get(P.mmrcptactvalue)
            P.mmrfoactmodetemp = get(P.mmrfoactmode)
            P.mmrfoactvaluetemp = get(P.mmrfoactvalue)
            P.mmrcptstdbymodetemp = get(P.mmrcptstdbymode)
            P.mmrfostdbymodetemp = get(P.mmrfostdbymode)
        else
            if ((get(P.mmrcptstdbymode) ~= P.mmrcptstdbymodetemp) or (get(P.mmrfostdbymode) ~= P.mmrfostdbymodetemp)) then
                if ((get(P.mmrcptstdbymode) ~= P.mmrcptstdbymodetemp2) or (get(P.mmrfostdbymode) ~= P.mmrfostdbymodetemp2)) then
                    P.mmrcptstdbymodetemp2 = get(P.mmrcptstdbymode)
                    P.mmrfostdbymodetemp2 = get(P.mmrfostdbymode)
                else
                    if (get(P.mmrcptstdbymode) == get(P.mmrfostdbymode)) then
                        if (get(P.mmrcptstdbymode) == def.MMRLOC) then
                            P.commandtableentry(def.TEXT, "Both M M R Standby V O R")
                        elseif (get(P.mmrcptstdbymode) == def.MMRILS) then
                            P.commandtableentry(def.TEXT, "Both M M R Standby I L S")
                        elseif (get(P.mmrcptstdbymode) == def.MMRGLS) then
                            P.commandtableentry(def.TEXT, "Both M M R Standby G L S")
                        elseif (get(P.mmrcptstdbymode) == def.MMRLPV) then
                            P.commandtableentry(def.TEXT, "Both M M R Standby L P V")
                        end
                    else
                        if (get(P.mmrcptstdbymode) ~= P.mmrcptstdbymodetemp) then
                            if (get(P.mmrcptstdbymode) == def.MMRLOC) then
                                P.commandtableentry(def.TEXT, "Pilot M M R Standby V O R")
                            elseif (get(P.mmrcptstdbymode) == def.MMRILS) then
                                P.commandtableentry(def.TEXT, "Pilot M M R Standby I L S")
                            elseif (get(P.mmrcptstdbymode) == def.MMRGLS) then
                                P.commandtableentry(def.TEXT, "Pilot M M R Standby G L S")
                            elseif (get(P.mmrcptstdbymode) == def.MMRLPV) then
                                P.commandtableentry(def.TEXT, "Pilot M M R Standby L P V")
                            end
                        end

                        if (get(P.mmrfostdbymode) ~= P.mmrfostdbymodetemp) then
                            if (get(P.mmrfostdbymode) == def.MMRLOC) then
                                P.commandtableentry(def.TEXT, "Copilot M M R Standby V O R")
                            elseif (get(P.mmrfostdbymode) == def.MMRILS) then
                                P.commandtableentry(def.TEXT, "Copilot M M R Standby I L S")
                            elseif (get(P.mmrfostdbymode) == def.MMRGLS) then
                                P.commandtableentry(def.TEXT, "Copilot M M R Standby G L S")
                            elseif (get(P.mmrfostdbymode) == def.MMRLPV) then
                                P.commandtableentry(def.TEXT, "Copilot M M R Standby L P V")
                            end

                            P.mmrfostdbymodetemp = get(P.mmrfostdbymode)
                        end
                    end

                    P.mmrcptactmodetemp = get(P.mmrcptactmode)
                    P.mmrcptactvaluetemp = get(P.mmrcptactvalue)
                    P.mmrfoactmodetemp = get(P.mmrfoactmode)
                    P.mmrfoactvaluetemp = get(P.mmrfoactvalue)
                    P.mmrcptstdbymodetemp = get(P.mmrcptstdbymode)
                    P.mmrcptstdbymodetemp2 = get(P.mmrcptstdbymode)
                    P.mmrfostdbymodetemp = get(P.mmrfostdbymode)
                    P.mmrfostdbymodetemp2 = get(P.mmrfostdbymode)
                end
            end
        end
    else
        if ((get(P.nav1freq) ~= P.nav1freqtemp) or (get(P.nav2freq) ~= P.nav2freqtemp)) then
            if (get(P.nav1freq) == get(P.nav2freq)) then
                P.commandtableentry(def.TEXT, "Both N A V " .. helpers.addspaces(helpers.formatILSFrequency(get(P.nav1freq))))

                P.nav1freqtemp = get(P.nav1freq)
                P.nav2freqtemp = get(P.nav2freq)
            else
                if (get(P.nav1freq) ~= P.nav1freqtemp) then
                    P.commandtableentry(def.TEXT, "N A V 1 " .. helpers.addspaces(helpers.formatILSFrequency(get(P.nav1freq))))

                    P.nav1freqtemp = get(P.nav1freq)
                end

                if (get(P.nav2freq) ~= P.nav2freqtemp) then
                    P.commandtableentry(def.TEXT, "N A V 2 " .. helpers.addspaces(helpers.formatILSFrequency(get(P.nav1freq))))

                    P.nav2freqtemp = get(P.nav2freq)
                end
            end
        end
    end

    if ((get(P.centertanklswitch) ~= P.centertanklswitchtemp) or (get(P.centertankrswitch) ~= P.centertankrswitchtemp)) then
        if ((get(P.centertanklswitch) ~= P.centertanklswitchtemp) and (get(P.centertankrswitch) ~= P.centertankrswitchtemp) and (get(P.centertanklswitch) == get(P.centertankrswitch))) then
            if (get(P.centertanklswitch) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Center Tank Fuel Pumps On")
            else
                P.commandtableentry(def.TEXT, "Both Center Tank Fuel Pumps Off")
            end
            P.centertanklswitchtemp = get(P.centertanklswitch)
            P.centertankrswitchtemp = get(P.centertankrswitch)
        else
            if (get(P.centertanklswitch) ~= P.centertanklswitchtemp) then
                if (get(P.centertanklswitch) == def.ON) then
                    P.commandtableentry(def.TEXT, "Left Center Tank Fuel Pump On")
                else
                    P.commandtableentry(def.TEXT, "Left Center Tank Fuel Pump Off")
                end
                P.centertanklswitchtemp = get(P.centertanklswitch)
            end

            if (get(P.centertankrswitch) ~= P.centertankrswitchtemp) then
                if (get(P.centertankrswitch) == def.ON) then
                    P.commandtableentry(def.TEXT, "Right Center Tank Fuel Pump On")
                else
                    P.commandtableentry(def.TEXT, "Right Center Tank Fuel Pump Off")
                end
                P.centertankrswitchtemp = get(P.centertankrswitch)
            end
        end
    end

    if ((get(P.lefttanklswitch) ~= P.lefttanklswitchtemp) or (get(P.lefttankrswitch) ~= P.lefttankrswitchtemp)) then
        if ((get(P.lefttanklswitch) ~= P.lefttanklswitchtemp) and (get(P.lefttankrswitch) ~= P.lefttankrswitchtemp) and (get(P.lefttanklswitch) == get(P.lefttankrswitch))) then
            if (get(P.lefttanklswitch) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Left Wing Tank Fuel Pumps On")
            else
                P.commandtableentry(def.TEXT, "Both Left Wing Tank Fuel Pumps Off")
            end
            P.lefttanklswitchtemp = get(P.lefttanklswitch)
            P.lefttankrswitchtemp = get(P.lefttankrswitch)
        else
            if (get(P.lefttanklswitch) ~= P.lefttanklswitchtemp) then
                if (get(P.lefttanklswitch) == def.ON) then
                    P.commandtableentry(def.TEXT, "Left Wing Tank After Fuel Pump On")
                else
                    P.commandtableentry(def.TEXT, "Left Wing Tank After Fuel Pump Off")
                end
                P.lefttanklswitchtemp = get(P.lefttanklswitch)
            end

            if (get(P.lefttankrswitch) ~= P.lefttankrswitchtemp) then
                if (get(P.lefttankrswitch) == def.ON) then
                    P.commandtableentry(def.TEXT, "Right Wing Tank Forward Fuel Pump On")
                else
                    P.commandtableentry(def.TEXT, "Right Wing Tank Forward Fuel Pump Off")
                end
                P.lefttankrswitchtemp = get(P.lefttankrswitch)
            end
        end
    end

    if ((get(P.righttanklswitch) ~= P.righttanklswitchtemp) or (get(P.righttankrswitch) ~= P.righttankrswitchtemp)) then
        if ((get(P.righttanklswitch) ~= P.righttanklswitchtemp) and (get(P.righttankrswitch) ~= P.righttankrswitchtemp) and (get(P.righttanklswitch) == get(P.righttankrswitch))) then
            if (get(P.righttanklswitch) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Right Wing Tank Fuel Pumps On")
            else
                P.commandtableentry(def.TEXT, "Both Right Wing Tank Fuel Pumps Off")
            end
            P.righttanklswitchtemp = get(P.righttanklswitch)
            P.righttankrswitchtemp = get(P.righttankrswitch)
        else
            if (get(P.righttanklswitch) ~= P.righttanklswitchtemp) then
                if (get(P.righttanklswitch) == def.ON) then
                    P.commandtableentry(def.TEXT, "Right Wing Tank Forward Fuel Pump On")
                else
                    P.commandtableentry(def.TEXT, "Right Wing Tank Forward Fuel Pump Off")
                end
                P.righttanklswitchtemp = get(P.righttanklswitch)
            end

            if (get(P.righttankrswitch) ~= P.righttankrswitchtemp) then
                if (get(P.righttankrswitch) == def.ON) then
                    P.commandtableentry(def.TEXT, "Right Wing Tank After Fuel Pump On")
                else
                    P.commandtableentry(def.TEXT, "Right Wing Tank After Fuel Pump Off")
                end
                P.righttankrswitchtemp = get(P.righttankrswitch)
            end
        end
    end

    if ((get(P.starter1pos) ~= P.starter1postemp) or (get(P.starter2pos) ~= P.starter2postemp)) then
        local starterstring = ""
        local statestring = ""
        if (((get(P.starter1pos) ~= P.starter1postemp) and (get(P.starter2pos) ~= P.starter2postemp)) and (get(P.starter1pos) == get(P.starter2pos))) then
            starterstring = "Both Starters "
            if (get(P.starter1pos) == def.GROUND) then
                statestring = "Ground"
            elseif (get(P.starter1pos) == def.AUTO) then
                if (get(P.starterauto) == def.ON) then
                    statestring = "Auto"
                else
                    statestring = "Off"
                end
            elseif (get(P.starter1pos) == def.CONT) then
                statestring = "Continuous"
            elseif (get(P.starter1pos) == def.FLIGHT) then
                statestring = "Flight"
            end

            P.starter1postemp = get(P.starter1pos)
            P.starter2postemp = get(P.starter2pos)
        else
            if (get(P.starter1pos) ~= P.starter1postemp) then
                starterstring = "Engine 1 Starter "
                if (get(P.starter1pos) == def.GROUND) then
                    statestring = "Ground"
                elseif (get(P.starter1pos) == def.AUTO) then
                    if (get(P.starterauto) == def.ON) then
                        statestring = "Auto"
                    else
                        statestring = "Off"
                    end
                elseif (get(P.starter1pos) == def.CONT) then
                    statestring = "Continuous"
                elseif (get(P.starter1pos) == def.FLIGHT) then
                    statestring = "Flight"
                end

                P.starter1postemp = get(P.starter1pos)
            end

            if (get(P.starter2pos) ~= P.starter2postemp) then
                starterstring = "Engine 2 Starter "
                if (get(P.starter2pos) == def.GROUND) then
                    statestring = "Ground"
                elseif (get(P.starter2pos) == def.AUTO) then
                    if (get(P.starterauto) == def.ON) then
                        statestring = "Auto"
                    else
                        statestring = "Off"
                    end
                elseif (get(P.starter2pos) == def.CONT) then
                    statestring = "Continuous"
                elseif (get(P.starter2pos) == def.FLIGHT) then
                    statestring = "Flight"
                end

                P.starter2postemp = get(P.starter2pos)
            end
        end

        P.commandtableentry(def.TEXT, starterstring .. statestring)
    end

    if ((get(P.mixture1pos) ~= P.mixture1postemp) or (get(P.mixture2pos) ~= P.mixture2postemp)) then
        if ((get(P.mixture1pos) ~= P.mixture1postemp) and (get(P.mixture2pos) ~= P.mixture2postemp) and (get(P.mixture1pos) == get(P.mixture2pos))) then
            mixturestring = "Both Engine Fuel Levers "
            if (get(P.mixture1pos) == def.ON) then
                statestring = "Idle"
            elseif (get(P.mixture1pos) == def.OFF) then
                statestring = "Cutoff"
            end

            P.mixture1postemp = get(P.mixture1pos)
            P.mixture2postemp = get(P.mixture2pos)
        else
            if (get(P.mixture1pos) ~= P.mixture1postemp) then
                mixturestring = "Engine 1 Fuel Lever "
                if (get(P.mixture1pos) == def.ON) then
                    statestring = "Idle"
                elseif (get(P.mixture1pos) == def.OFF) then
                    statestring = "Cutoff"
                end

                P.mixture1postemp = get(P.mixture1pos)
            end

            if (get(P.mixture2pos) ~= P.mixture2postemp) then
                mixturestring = "Engine 2 Fuel Lever "
                if (get(P.mixture2pos) == def.ON) then
                    statestring = "Idle"
                elseif (get(P.mixture2pos) == def.OFF) then
                    statestring = "Cutoff"
                end

                P.mixture2postemp = get(P.mixture2pos)
            end
        end

        P.commandtableentry(def.TEXT, mixturestring .. statestring)
    end

    if ((get(P.reverser1pos) ~= P.reverser1postemp) or (get(P.reverser2pos) ~= P.reverser2postemp)) then
        if ((get(P.reverser1pos) ~= P.reverser1postemp) and (get(P.reverser2pos) ~= P.reverser2postemp) and (get(P.reverser1pos) == get(P.reverser2pos))) then
            if (((get(P.reverser1pos) == def.OFF) and (P.reverser1postemp ~= def.OFF)) or ((get(P.reverser2pos) == def.OFF) and (P.reverser2postemp ~= def.OFF))) then
                P.commandtableentry(def.TEXT, "Both Reversers Off")
            elseif (((get(P.reverser1pos) ~= def.OFF) and (P.reverser1postemp == def.OFF)) or ((get(P.reverser2pos) ~= def.OFF) and (P.reverser2postemp == def.OFF))) then
                P.commandtableentry(def.TEXT, "Both Reversers On")
            end

            P.reverser1postemp = get(P.reverser1pos)
            P.reverser2postemp = get(P.reverser2pos)
        else
            if (get(P.reverser1pos) ~= P.reverser1postemp) then
                if ((get(P.reverser1pos) == def.OFF) and (P.reverser1postemp ~= def.OFF)) then
                    P.commandtableentry(def.TEXT, "Reverser 1 Off")
                elseif ((get(P.reverser1pos) ~= def.OFF) and (P.reverser1postemp == def.OFF)) then
                    P.commandtableentry(def.TEXT, "Reverser 1 On")
                end

                P.reverser1postemp = get(P.reverser1pos)
            end

            if (get(P.reverser2pos) ~= P.reverser2postemp) then
                if ((get(P.reverser2pos) == def.OFF) and (P.reverser2postemp ~= def.OFF)) then
                    P.commandtableentry(def.TEXT, "Reverser 2 Off")
                elseif ((get(P.reverser2pos) ~= def.OFF) and (P.reverser2postemp == def.OFF)) then
                    P.commandtableentry(def.TEXT, "Reverser 2 On")
                end

                P.reverser2postemp = get(P.reverser2pos)
            end
        end
    end

    if (get(P.gpuon) ~= P.gpuontemp) then
        if (get(P.gpuon) == def.ON) then
            P.commandtableentry(def.TEXT, "Ground Power On")
        else
            P.commandtableentry(def.TEXT, "Ground Power Off")
        end
        P.gpuontemp = get(P.gpuon)
    end

    if ((helpers.roundnumber(get(P.announcsourceoff1),1) ~= P.announcsourceoff1temp) or (helpers.roundnumber(get(P.announcsourceoff2),1) ~= P.announcsourceoff2temp)) then
        if (P.apurunning() > def.APUSTARTED) then
            if ((get(P.apupowerbus1) == get(P.apupowerbus2)) and (get(P.announcsourceoff1) == get(P.announcsourceoff2)) and (get(P.announcsourceoff1) ~= P.announcsourceoff1temp) and (get(P.announcsourceoff2) ~= P.announcsourceoff2temp)) then
                if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                    P.commandtableentry(def.TEXT, "A P U Generator On")
                elseif not ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                    P.commandtableentry(def.TEXT, "A P U Generator Off")
                end
            else
                if (get(P.announcsourceoff1) ~= P.announcsourceoff1temp) then
                    if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                        P.commandtableentry(def.TEXT, "A P U Generator 1 On")
                    elseif not ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then
                        P.commandtableentry(def.TEXT, "A P U Generator 1 Off")
                    end
                end

                if (get(P.announcsourceoff2) ~= P.announcsourceoff2temp) then
                    if ((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                        P.commandtableentry(def.TEXT, "A P U Generator 2 On")
                    elseif not ((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then
                        P.commandtableentry(def.TEXT, "A P U Generator 2 Off")
                    end
                end
            end
        end
        P.announcsourceoff1temp = helpers.roundnumber(get(P.announcsourceoff1),1)
        P.announcsourceoff2temp = helpers.roundnumber(get(P.announcsourceoff2),1)
    end

    if ((get(P.gen1pos) ~= P.gen1postemp) or (get(P.gen2pos) ~= P.gen2postemp)) then
        if ((get(P.gen1pos) ~= P.gen1postemp) and (get(P.gen2pos) ~= P.gen2postemp) and (get(P.gen1pos) == get(P.gen2pos))) then
            if (get(P.gen1pos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Generators On")
            else
                P.commandtableentry(def.TEXT, "Both Generators Off")
            end
            P.gen1postemp = get(P.gen1pos)
            P.gen2postemp = get(P.gen2pos)
        else
            if (get(P.gen1pos) ~= P.gen1postemp) then
                if (get(P.gen1pos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Generator 1 On")
                else
                    P.commandtableentry(def.TEXT, "Generator 1 Off")
                end
                P.gen1postemp = get(P.gen1pos)
            end

            if (get(P.gen2pos) ~= P.gen2postemp) then
                if (get(P.gen2pos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Generator 2 On")
                else
                    P.commandtableentry(def.TEXT, "Generator 2 Off")
                end
                P.gen2postemp = get(P.gen2pos)
            end
        end
    end

    if ((get(P.captainprobepos) ~= P.captainprobepostemp) or (get(P.foprobepos) ~= P.foprobepostemp)) then
        if ((get(P.captainprobepos) ~= P.captainprobepostemp) and (get(P.foprobepos) ~= P.foprobepostemp) and (get(P.captainprobepos) == get(P.foprobepos))) then
            if (get(P.captainprobepos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Probe Heat On")
            else
                P.commandtableentry(def.TEXT, "Both Probe Heat Off")
            end
            P.captainprobepostemp = get(P.captainprobepos)
            P.foprobepostemp = get(P.foprobepos)
        else
            if (get(P.captainprobepos) ~= P.captainprobepostemp) then
                if (get(P.captainprobepos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Left Probe Heat On")
                else
                    P.commandtableentry(def.TEXT, "Left Probe Heat Off")
                end
                P.captainprobepostemp = get(P.captainprobepos)
            end

            if (get(P.foprobepos) ~= P.foprobepostemp) then
                if (get(P.foprobepos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Right Probe Heat On")
                else
                    P.commandtableentry(def.TEXT, "Right Probe Heat Off")
                end
                P.foprobepostemp = get(P.foprobepos)
            end
        end
    end

    if ((get(P.wheatlfwdpos) ~= P.wheatlfwdpostemp) or (get(P.wheatlsidepos) ~= P.wheatlsidepostemp)) then
        if ((get(P.wheatlfwdpos) ~= P.wheatlfwdpostemp) and (get(P.wheatlsidepos) ~= P.wheatlsidepostemp) and (get(P.wheatlfwdpos) == get(P.wheatlsidepos))) then
            if (get(P.wheatlfwdpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Pilot Window Heat On")
            else
                P.commandtableentry(def.TEXT, "Pilot Window Heat Off")
            end
            P.wheatlfwdpostemp = get(P.wheatlfwdpos)
            P.wheatlsidepostemp = get(P.wheatlsidepos)
        else
            if (get(P.wheatlfwdpos) ~= P.wheatlfwdpostemp) then
                if (get(P.wheatlfwdpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot Forward Window Heat On")
                else
                    P.commandtableentry(def.TEXT, "Pilot Forward Window Heat Off")
                end
                P.wheatlfwdpostemp = get(P.wheatlfwdpos)
            end

            if (get(P.wheatlsidepos) ~= P.wheatlsidepostemp) then
                if (get(P.wheatlsidepos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Pilot Side Window Heat On")
                else
                    P.commandtableentry(def.TEXT, "Pilot Side Window Heat Off")
                end
                P.wheatlsidepostemp = get(P.wheatlsidepos)
            end
        end
    end

    if ((get(P.wheatrfwdpos) ~= P.wheatrfwdpostemp) or (get(P.wheatrsidepos) ~= P.wheatrsidepostemp)) then
        if ((get(P.wheatrfwdpos) ~= P.wheatrfwdpostemp) and (get(P.wheatrsidepos) ~= P.wheatrsidepostemp) and (get(P.wheatrfwdpos) == get(P.wheatrsidepos))) then
            if (get(P.wheatrfwdpos) == def.ON) then
                P.commandtableentry(def.TEXT, "Copilot Window Heat On")
            else
                P.commandtableentry(def.TEXT, "Copilot Window Heat Off")
            end
            P.wheatrfwdpostemp = get(P.wheatrfwdpos)
            P.wheatrsidepostemp = get(P.wheatrsidepos)
        else
            if (get(P.wheatrfwdpos) ~= P.wheatrfwdpostemp) then
                if (get(P.wheatrfwdpos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot Forward Window Heat On")
                else
                    P.commandtableentry(def.TEXT, "Copilot Forward Window Heat Off")
                end
                P.wheatrfwdpostemp = get(P.wheatrfwdpos)
            end

            if (get(P.wheatrsidepos) ~= P.wheatrsidepostemp) then
                if (get(P.wheatrsidepos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Copilot Side Window Heat On")
                else
                    P.commandtableentry(def.TEXT, "Copilot Side Window Heat Off")
                end
                P.wheatrsidepostemp = get(P.wheatrsidepos)
            end
        end
    end

    if (get(P.flapleverpos) ~= P.flapleverpostemp) then
        if (get(P.flapleverpos) ~= P.flapleverpostemp2) then
            P.flapleverpostemp2 = get(P.flapleverpos)
        else
            if (get(P.flapleverpos) == def.FLAPSUP) then
                P.commandtableentry(def.TEXT, "Flaps Up")
            elseif (get(P.flapleverpos) == def.FLAPS1) then
                P.commandtableentry(def.TEXT, "Flaps 1")
            elseif (get(P.flapleverpos) == def.FLAPS2) then
                P.commandtableentry(def.TEXT, "Flaps 2")
            elseif (get(P.flapleverpos) == def.FLAPS5) then
                P.commandtableentry(def.TEXT, "Flaps 5")
            elseif (get(P.flapleverpos) == def.FLAPS10) then
                P.commandtableentry(def.TEXT, "Flaps 10")
            elseif (get(P.flapleverpos) == def.FLAPS15) then
                P.commandtableentry(def.TEXT, "Flaps 15")
            elseif (get(P.flapleverpos) == def.FLAPS25) then
                P.commandtableentry(def.TEXT, "Flaps 25")
            elseif (get(P.flapleverpos) == def.FLAPS30) then
                P.commandtableentry(def.TEXT, "Flaps 30")
            elseif (get(P.flapleverpos) == def.FLAPS40) then
                P.commandtableentry(def.TEXT, "Flaps 40")
            end

            P.flapleverpostemp = get(P.flapleverpos)
            P.flapleverpostemp2 = get(P.flapleverpos)
        end
    end

    if (get(P.bankanglepos) ~= P.bankanglepostemp) then
        if (get(P.bankanglepos) ~= P.bankanglepostemp2) then
            P.bankanglepostemp2 = get(P.bankanglepos)
        else
            P.commandtableentry(def.TEXT, "Bank Angle " .. helpers.getbankanglestring(get(P.bankanglepos)))
            P.bankanglepostemp = get(P.bankanglepos)
            P.bankanglepostemp2 = get(P.bankanglepos)
        end
    end

    if (get(P.gearhandlepos) ~= P.gearhandlepostemp) then
        if (get(P.gearhandlepos) == def.GEARUP) then
            P.commandtableentry(def.TEXT, "Landing Gear Up")
        elseif (get(P.gearhandlepos) == def.GEAROFF) then
            P.commandtableentry(def.TEXT, "Landing Gear Lever Off")
        elseif (get(P.gearhandlepos) == def.GEARDOWN) then
            P.commandtableentry(def.TEXT, "Landing Gear Down")
        end

        P.gearhandlepostemp = get(P.gearhandlepos)
    end

    if (get(P.parkingbrakepos) ~= P.parkingbrakepostemp) then
        if (get(P.parkingbrakepos) == def.ON) then
            P.commandtableentry(def.TEXT, "Parking Brake Set")
        else
            P.commandtableentry(def.TEXT, "Parking Brake Off")
        end

        P.parkingbrakepostemp = get(P.parkingbrakepos)
    end

    speedbrakeleverrounded = helpers.roundnumber(get(P.speedbrakelever), 1)

    if (speedbrakeleverrounded ~= P.speedbrakelevertemp) then
        if (speedbrakeleverrounded ~= P.speedbrakelevertemp2) then
            P.speedbrakelevertemp2 = speedbrakeleverrounded
        else
            if (speedbrakeleverrounded == def.SPEEDBRAKEDOWN) then
                P.commandtableentry(def.TEXT, "Speedbrake Down")
            elseif (speedbrakeleverrounded == def.SPEEDBRAKEARMED) then
                P.commandtableentry(def.TEXT, "Speedbrake Armed")
            elseif (speedbrakeleverrounded >= def.SPEEDBRAKEUP) then
                P.commandtableentry(def.TEXT, "Speedbrake Up")
            end

            P.speedbrakelevertemp = speedbrakeleverrounded
            P.speedbrakelevertemp2 = speedbrakeleverrounded
        end
    end

    if (get(P.autobrakepos) ~= P.autobrakepostemp) then
        if (get(P.autobrakepos) == def.AUTOBRAKERTO) then
            P.commandtableentry(def.TEXT, "Auto Brake R T O")
        elseif (get(P.autobrakepos) == def.AUTOBRAKEOFF) then
            P.commandtableentry(def.TEXT, "Auto Brake Off")
        elseif (get(P.autobrakepos) == def.AUTOBRAKE1) then
            P.commandtableentry(def.TEXT, "Auto Brake 1")
        elseif (get(P.autobrakepos) == def.AUTOBRAKE2) then
            P.commandtableentry(def.TEXT, "Auto Brake 2")
        elseif (get(P.autobrakepos) == def.AUTOBRAKE3) then
            P.commandtableentry(def.TEXT, "Auto Brake 3")
        elseif (get(P.autobrakepos) == def.AUTOBRAKEMAX) then
            P.commandtableentry(def.TEXT, "Auto Brake Maximum")
        end

        P.autobrakepostemp = get(P.autobrakepos)
    end

    if (get(P.autobrakedisarm) ~= P.autobrakedisarmtemp) then
        if (get(P.autobrakedisarm) ~= P.autobrakedisarmtemp2) then
            P.autobrakedisarmtemp2 = get(P.autobrakedisarm)
        else
            if (get(P.autobrakedisarm) == def.ON) then
                P.commandtableentry(def.TEXT, "Auto Brake Disarmed")
            end

            P.autobrakedisarmtemp = get(P.autobrakedisarm)
            P.autobrakedisarmtemp2 = get(P.autobrakedisarm)
        end
    end

    if ((get(P.packlpos) ~= P.packlpostemp) or (get(P.packrpos) ~= P.packrpostemp)) then
        local packstring = ""
        local statestring = ""
        if (((get(P.packlpos) ~= P.packlpostemp) and (get(P.packrpos) ~= P.packrpostemp)) and (get(P.packlpos) == get(P.packrpos))) then
            packstring = "Both Packs "
            if (get(P.packlpos) == def.PACKOFF) then
                statestring = "Off"
            elseif (get(P.packlpos) == def.PACKAUTO) then
                    statestring = "Auto"
            elseif (get(P.packlpos) == def.PACKHIGH) then
                statestring = "High"
            end

            P.packlpostemp = get(P.packlpos)
            P.packrpostemp = get(P.packrpos)
        else
            if (get(P.packlpos) ~= P.packlpostemp) then
                packstring = "Left Pack "
                if (get(P.packlpos) == def.PACKOFF) then
                    statestring = "Off"
                elseif (get(P.packlpos) == def.PACKAUTO) then
                    statestring = "Auto"
                elseif (get(P.packlpos) == def.PACKHIGH) then
                    statestring = "High"
                end

                P.packlpostemp = get(P.packlpos)
            end

            if (get(P.packrpos) ~= P.packrpostemp) then
                packstring = "Right Pack "
                if (get(P.packrpos) == def.PACKOFF) then
                    statestring = "Off"
                elseif (get(P.packrpos) == def.PACKAUTO) then
                    statestring = "Auto"
                elseif (get(P.packrpos) == def.PACKHIGH) then
                    statestring = "High"
                end

                P.packrpostemp = get(P.packrpos)
            end
        end

        P.commandtableentry(def.TEXT, packstring .. statestring)
    end

    if (get(P.isolvalvepos) ~= P.isolvalvepostemp) then
        if (get(P.isolvalvepos) == def.ISOLVALVECLOSE) then
            P.commandtableentry(def.TEXT, "Isolation Valve Closed")
        elseif (get(P.isolvalvepos) == def.ISOLVALVEAUTO) then
            P.commandtableentry(def.TEXT, "Isolation Valve Auto")
        elseif (get(P.isolvalvepos) == def.ISOLVALVEOPEN) then
            P.commandtableentry(def.TEXT, "Isolation Valve Open")
        end

        P.isolvalvepostemp = get(P.isolvalvepos)
    end

   if ((get(P.bleedair1pos) ~= P.bleedair1postemp) or (get(P.bleedair2pos) ~= P.bleedair2postemp)) then
        if (((get(P.bleedair1pos) ~= P.bleedair1postemp) and (get(P.bleedair2pos) ~= P.bleedair2postemp)) and (get(P.hydropos1) == get(P.hydropos2))) then
            if (get(P.bleedair1pos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Engine Bleed Air On")
            else
                P.commandtableentry(def.TEXT, "Both Engine Bleed Air Off")
            end

            P.bleedair1postemp = get(P.bleedair1pos)
            P.bleedair2postemp = get(P.bleedair2pos)
        else
            if (get(P.bleedair1pos) ~= P.bleedair1postemp) then
                if (get(P.bleedair1pos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Engine 1 Bleed Air On")
                else
                    P.commandtableentry(def.TEXT, "Engine 1 Bleed Air Off")
                end
                P.bleedair1postemp = get(P.bleedair1pos)
            end

            if (get(P.bleedair2pos) ~= P.bleedair2postemp) then
                if (get(P.bleedair2pos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Engine 2 Bleed Air On")
                else
                    P.commandtableentry(def.TEXT, "Engine 2 Bleed Air Off")
                end
                P.bleedair2postemp = get(P.bleedair2pos)
            end
        end
    end

    if (get(P.trimairpos) ~= P.trimairpostemp) then
        if (get(P.trimairpos) == def.ON) then
            P.commandtableentry(def.TEXT, "Trim Air On")
        else
            P.commandtableentry(def.TEXT, "Trim Air Off")
        end

        P.trimairpostemp = get(P.trimairpos)
    end

    if (get(P.lrecircfanpos) ~= P.lrecircfanpostemp) then
        if (get(P.lrecircfanpos) == def.ON) then
            P.commandtableentry(def.TEXT, "Left Recircling Fan On")
        else
            P.commandtableentry(def.TEXT, "Left Recircling Fan Off")
        end

        P.lrecircfanpostemp = get(P.lrecircfanpos)
    end

    if (get(P.rrecircfanpos) ~= P.rrecircfanpostemp) then
        if (get(P.rrecircfanpos) == def.ON) then
            P.commandtableentry(def.TEXT, "Right Recircling Fan On")
        else
            P.commandtableentry(def.TEXT, "Right Recircling Fan Off")
        end

        P.rrecircfanpostemp = get(P.rrecircfanpos)
    end

    if (get(P.bleedairapupos) ~= P.bleedairapupostemp) then
        if (get(P.bleedairapupos) == def.ON) then
            P.commandtableentry(def.TEXT, "A P U Bleed Air On")
        else
            P.commandtableentry(def.TEXT, "A P U Bleed Air Off")
        end

        P.bleedairapupostemp = get(P.bleedairapupos)
    end

    if (get(P.battery) ~= P.batterytemp) then
        if (get(P.battery) == def.ON) then
            P.commandtableentry(def.TEXT, "Battery On")
        else
            P.commandtableentry(def.TEXT, "Battery Off")
        end

        P.batterytemp = get(P.battery)
    end

    if (get(P.apustarterpos) ~= P.apustarterpostemp) then
        if (P.apurunning() > def.APUOFF) then
            P.commandtableentry(def.TEXT, "A P U Started")
        else
            P.commandtableentry(def.TEXT, "A P U Shutting Down")
        end

        P.apustarterpostemp = get(P.apustarterpos)
    end

    if (get(P.emergencylights) ~= P.emergencylightstemp) then
        if (get(P.emergencylights) == def.EMERGLIGHTSOFF) then
            P.commandtableentry(def.TEXT, "Emergengy Lights Off")
        elseif (get(P.emergencylights) == def.EMERGLIGHTSARMED) then
            P.commandtableentry(def.TEXT, "Emergency Lights Armed")
        elseif (get(P.emergencylights) == def.EMERGLIGHTSON) then
            P.commandtableentry(def.TEXT, "Emergency Lights On")
        end
        P.emergencylightstemp = get(P.emergencylights)
    end

    if ((get(P.hydro1pos) ~= P.hydro1postemp) or (get(P.hydro2pos) ~= P.hydro2postemp)) then
        if (((get(P.hydro1pos) ~= P.hydro1postemp) and (get(P.hydro2pos) ~= P.hydro2postemp)) and (get(P.hydropos1) == get(P.hydropos2))) then
            if (get(P.hydro1pos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Hydraulic Pumps On")
            else
                P.commandtableentry(def.TEXT, "Both Hydraulic Pumps Off")
            end

            P.hydro1postemp = get(P.hydro1pos)
            P.hydro2postemp = get(P.hydro2pos)
        else
            if (get(P.hydro1pos) ~= P.hydro1postemp) then
                if (get(P.hydro1pos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Hydraulic Pump 1 On")
                else
                    P.commandtableentry(def.TEXT, "Hydraulic Pump 1 Off")
                end
                P.hydro1postemp = get(P.hydro1pos)
            end

            if (get(P.hydro2pos) ~= P.hydro2postemp) then
                if (get(P.hydro2pos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Hydraulic Pump 2 On")
                else
                    P.commandtableentry(def.TEXT, "Hydraulic Pump 2 Off")
                end
                P.hydro2postemp = get(P.hydro2pos)
            end
        end
    end

    if ((get(P.elechydro1pos) ~= P.elechydro1postemp) or (get(P.elechydro2pos) ~= P.elechydro2postemp)) then
        if ((get(P.elechydro1pos) ~= P.elechydro1postemp) and (get(P.elechydro2pos) ~= P.elechydro2postemp) and (get(P.elechydro1pos) == get(P.elechydro2pos))) then
            if (get(P.elechydro1pos) == def.ON) then
                P.commandtableentry(def.TEXT, "Both Electrical Hydraulic Pumps On")
            else
                P.commandtableentry(def.TEXT, "Both Electrical Hydraulic Pumps Off")
            end

            P.elechydro1postemp = get(P.elechydro1pos)
            P.elechydro2postemp = get(P.elechydro2pos)
        else
            if (get(P.elechydro1pos) ~= P.elechydro1postemp) then
                if (get(P.elechydro1pos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Electrical Hydraulic Pump 2 On")
                else
                    P.commandtableentry(def.TEXT, "Electrical Hydraulic Pump 2 Off")
                end
                P.elechydro1postemp = get(P.elechydro1pos)
            end

            if (get(P.elechydro2pos) ~= P.elechydro2postemp) then
                if (get(P.elechydro2pos) == def.ON) then
                    P.commandtableentry(def.TEXT, "Electrical Hydraulic Pump 1 On")
                else
                    P.commandtableentry(def.TEXT, "Electrical Hydraulic Pump 1 Off")
                end
                P.elechydro2postemp = get(P.elechydro2pos)
            end
        end
    end

    if (get(P.seatbeltsignpos) ~= P.seatbeltsignpostemp) then
        if (get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF) then
            P.commandtableentry(def.TEXT, "Seatbelt Sign Off")
        elseif (get(P.seatbeltsignpos) == def.SEATBELTSIGNAUTO) then
            P.commandtableentry(def.TEXT, "Seatbelt Sign Auto")
        elseif (get(P.seatbeltsignpos) == def.SEATBELTSIGNON) then
            P.commandtableentry(def.TEXT, "Seatbelt Sign On")
        end

        P.seatbeltsignpostemp = get(P.seatbeltsignpos)
    end

    if (get(P.nosmokingsignpos) ~= P.nosmokingsignpostemp) then
        if (get(P.nosmokingsignpos) == def.NOSMOKINGSIGNOFF) then
            P.commandtableentry(def.TEXT, "No Smoking Sign Off")
        elseif (get(P.nosmokingsignpos) == def.NOSMOKINGSIGNAUTO) then
            P.commandtableentry(def.TEXT, "No Smoking Sign Auto")
        elseif (get(P.nosmokingsignpos) == def.NOSMOKINGSIGNON) then
            P.commandtableentry(def.TEXT, "No Smoking Sign On")
        end

        P.nosmokingsignpostemp = get(P.nosmokingsignpos)
    end

    if (get(P.domelightpos) ~= P.domelightpostemp) then
        if (get(P.domelightpos) == def.DOMELIGHTOFF) then
            P.commandtableentry(def.TEXT, "Dome Light Off")
        elseif (get(P.domelightpos) == def.DOMELIGHTDIM) then
            P.commandtableentry(def.TEXT, "Dome Light Dim")
        elseif (get(P.domelightpos) == def.DOMELIGHTBRIGHT) then
            P.commandtableentry(def.TEXT, "Dome Light Bright")
        end

        P.domelightpostemp = get(P.domelightpos)
    end

    if ((get(P.irsleftpos) ~= P.irsleftpostemp) or (get(P.irsrightpos) ~= P.irsrightpostemp)) then
        if ((get(P.irsleftpos) ~= P.irsleftpostemp2) or (get(P.irsrightpos) ~= P.irsrightpostemp2)) then
                P.irsleftpostemp2 = get(P.irsleftpos)
                P.irsrightpostemp2 = get(P.irsrightpos)
        else
            local irsstring = ""
            local statestring = ""
            if ((get(P.irsleftpos) ~= P.irsleftpostemp) and (get(P.irsrightpos) ~= P.irsrightpostemp) and (get(P.irsleftpos) == get(P.irsrightpos))) then
                irsstring = "Both I R S "
                if (get(P.irsleftpos) == def.IRSOFF) then
                    statestring = "Off"
                elseif (get(P.irsleftpos) == def.IRSALIGN) then
                    statestring = "Align"
                elseif (get(P.irsleftpos) == def.IRSNAV) then
                    statestring = "Nav"
                elseif (get(P.irsleftpos) == def.IRSATT) then
                    statestring = "Attention"
                end

                P.irsleftpostemp = get(P.irsleftpos)
                P.irsleftpostemp2 = get(P.irsleftpos)
                P.irsrightpostemp = get(P.irsrightpos)
                P.irsrightpostemp2 = get(P.irsrightpos)
            else
                if (get(P.irsleftpos) ~= P.irsleftpostemp) then
                    irsstring = "Left I R S "
                    if (get(P.irsleftpos) == def.IRSOFF) then
                        statestring = "Off"
                    elseif (get(P.irsleftpos) == def.IRSALIGN) then
                        statestring = "Align"
                    elseif (get(P.irsleftpos) == def.IRSNAV) then
                        statestring = "Nav"
                    elseif (get(P.irsleftpos) == def.IRSATT) then
                        statestring = "Attention"
                    end

                    P.irsleftpostemp = get(P.irsleftpos)
                    P.irsleftpostemp2 = get(P.irsleftpos)
                end

                if (get(P.irsrightpos) ~= P.irsrightpostemp) then
                    irsstring = "Right I R S "
                    if (get(P.irsrightpos) == def.IRSOFF) then
                        statestring = "Off"
                    elseif (get(P.irsrightpos) == def.IRSALIGN) then
                        statestring = "Align"
                    elseif (get(P.irsrightpos) == def.IRSNAV) then
                        statestring = "Nav"
                    elseif (get(P.irsrightpos) == def.IRSATT) then
                        statestring = "Attention"
                    end

                    P.irsrightpostemp = get(P.irsrightpos)
                    P.irsrightpostemp2 = get(P.irsrightpos)
                end
            end

            P.commandtableentry(def.TEXT, irsstring .. statestring)
        end
    end

    if (get(P.transpondercode) ~= P.transpondercodetemp) then
        if (get(P.transpondercode) ~= P.transpondercodetemp2) then
            P.transpondercodetemp2 = get(P.transpondercode)
        else
            P.commandtableentry(def.TEXT, "Transponder Code " .. helpers.addspaces(get(P.transpondercode)))
            P.transpondercodetemp = get(P.transpondercode)
            P.transpondercodetemp2 = get(P.transpondercode)
        end

    end

    if (P.configvalues[def.CONFIGAUTOWIPER] ~= def.ON) then
        if ((get(P.lwiperpos) ~= P.lwiperpostemp) or (get(P.rwiperpos) ~= P.rwiperpostemp)) then
            if ((get(P.lwiperpos) ~= P.lwiperpostemp2) or (get(P.rwiperpos) ~= P.rwiperpostemp2)) then
                P.lwiperpostemp2 = get(P.lwiperpos)
                P.rwiperpostemp2 = get(P.rwiperpos)
            else
                local wiperstring = ""
                local statestring = ""
                if (((get(P.lwiperpos) ~= P.lwiperpostemp) and (get(P.rwiperpos) ~= P.rwiperpostemp)) and (get(P.lwiperpos) == get(P.rwiperpos))) then
                    wiperstring = "Both Wipers "
                    if (get(P.lwiperpos) == def.WIPEROFF) then
                        statestring = "Off"
                    elseif (get(P.lwiperpos) == def.WIPERINT) then
                        statestring = "Interval"
                    elseif (get(P.lwiperpos) == def.WIPERLOW) then
                        statestring = "Low"
                    elseif (get(P.lwiperpos) == def.WIPERHIGH) then
                        statestring = "High"
                    end

                    P.lwiperpostemp = get(P.lwiperpos)
                    P.lwiperpostemp2 = get(P.lwiperpos)
                    P.rwiperpostemp = get(P.rwiperpos)
                    P.rwiperpostemp2 = get(P.rwiperpos)
                else
                    if (get(P.lwiperpos) ~= P.lwiperpostemp) then
                        wiperstring = "Left Wiper "
                        if (get(P.lwiperpos) == def.WIPEROFF) then
                            statestring = "Off"
                        elseif (get(P.lwiperpos) == def.WIPERINT) then
                            statestring = "Interval"
                        elseif (get(P.lwiperpos) == def.WIPERLOW) then
                            statestring = "Low"
                        elseif (get(P.lwiperpos) == def.WIPERHIGH) then
                            statestring = "High"
                        end

                        P.lwiperpostemp = get(P.lwiperpos)
                        P.lwiperpostemp2 = get(P.lwiperpos)
                    end

                    if (get(P.rwiperpos) ~= P.rwiperpostemp) then
                        wiperstring = "Right Wiper "
                        if (get(P.rwiperpos) == def.WIPEROFF) then
                            statestring = "Off"
                        elseif (get(P.rwiperpos) == def.WIPERINT) then
                            statestring = "Interval"
                        elseif (get(P.rwiperpos) == def.WIPERLOW) then
                            statestring = "Low"
                        elseif (get(P.rwiperpos) == def.WIPERHIGH) then
                            statestring = "High"
                        end

                        P.rwiperpostemp = get(P.rwiperpos)
                        P.rwiperpostemp2 = get(P.rwiperpos)
                    end
                end

                P.commandtableentry(def.TEXT, wiperstring .. statestring)
            end
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.ongoingtasks()

    if (P.updatemetartimer == nil) then
        P.updatemetartimer = sasl.createTimer()
        sasl.startTimer(P.updatemetartimer)
        P.updatemetar()
    elseif (sasl.getElapsedSeconds(P.updatemetartimer) > 300) then
        P.updatemetar()
        sasl.startTimer(P.updatemetartimer)
    end

    if ((P.apgoaroundtemp ~= get(P.apgoaround)) and (get(P.apgoaround) == def.ON)) then
        
        local voice_on = (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)
        local auto_on = (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON)

        if (voice_on and auto_on) then
            P.commandtableentry(def.TEXT, "Goaround: Voice Readback and Autofunctions switched off.")
            P.configvalues[def.CONFIGVOICEADVICEONLY] = def.OFF
            P.configvalues[def.CONFIGAUTOFUNCTIONS] = def.OFF

        elseif (voice_on) then
            P.commandtableentry(def.TEXT, "Goaround: Voice Readback switched off.")
            P.configvalues[def.CONFIGVOICEADVICEONLY] = def.OFF

        elseif (auto_on) then
            P.commandtableentry(def.TEXT, "Goaround: Autofunctions switched off.")
            P.configvalues[def.CONFIGAUTOFUNCTIONS] = def.OFF
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

    if ((P.procedureloop1.lock == def.NOPROCEDURE) and (get(P.airgroundsensor) == def.ON) and (P.flightstate == def.FLIGHTSTATEPREFLIGHT)) then
        if (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
            if ((get(P.battery) == def.ON) and (get(P.positionlights) ~= def.POSLIGHTSSTEADY) and (get(P.parkingbrakepos) == def.ON)) then
                P.commandtableentry(def.TEXT, "Set Position Lights Steady") 
            elseif (((get(P.starter1pos) == def.GROUND) or (get(P.starter2pos) == def.GROUND)) and (get(P.beaconlights) == def.OFF)) then
                P.commandtableentry(def.TEXT, "Set Collision Lights On")      
            elseif (((get(P.starter1pos) == def.GROUND) or (get(P.starter2pos) == def.GROUND)) and ((get(P.lefttanklswitch) == def.OFF) or (get(P.lefttankrswitch) == def.OFF) or (get(P.righttanklswitch) == def.OFF) or (get(P.righttankrswitch) == def.OFF))) then
                P.commandtableentry(def.TEXT, "Set Wing Tank Fuel Pumps On")
            elseif (((get(P.starter1pos) == def.GROUND) or (get(P.starter2pos) == def.GROUND)) and ((get(P.packlpos) ~= def.PACKOFF) or (get(P.packrpos) ~= def.PACKOFF))) then
                P.commandtableentry(def.TEXT, "Set Both Packs Off")
            elseif (((get(P.starter1pos) == def.GROUND) or (get(P.starter2pos) == def.GROUND)) and (get(P.bleedairapupos) ~= def.ON)) then
                P.commandtableentry(def.TEXT, "Set A P U Bleed Air On")
            elseif ((get(P.starter2pos) == def.GROUND) and (get(P.isolvalvepos) ~= def.ISOLVALVEOPEN)) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Open")
            elseif ((get(P.starter1pos) == def.GROUND) and (get(P.eng1n2percent) > 25) and (get(P.mixture1pos) == def.OFF)) then 
                P.commandtableentry(def.TEXT, "Engine 1 N 2 at 25 Percent")        
            elseif ((get(P.starter2pos) == def.GROUND) and (get(P.eng2n2percent) > 25) and (get(P.mixture2pos) == def.OFF)) then 
                P.commandtableentry(def.TEXT, "Engine 2 N 2 at 25 Percent")
            elseif ((P.apurunning() == def.APUOFFBUS) and (get(P.gen1pos) == def.OFF) and (get(P.gen1pos) == def.OFF)) then
                P.commandtableentry(def.TEXT, "Switch A P U Generator On")
            elseif ((get(P.bleedairapupos) == def.OFF) and (P.apurunning() > def.APUSTARTED) and ((not P.enginesrunning(P.BOTH)) or (P.enginesrunning(P.BOTH) and get(P.bleedair1pos) == def.OFF and get(P.bleedair2pos) == def.OFF))) then
                P.commandtableentry(def.TEXT, "Set A P U Bleedair On")
            elseif ((get(P.isolvalvepos) ~= def.ISOLVALVEOPEN) and (P.apurunning() > def.APUSTARTED) and not(P.enginesrunning(P.BOTH) and get(P.bleedair2pos) == def.ON)) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Open")
            elseif ((get(P.bleedairapupos) == def.ON) and P.enginesrunning(P.BOTH) and (get(P.bleedair1pos) == def.ON or get(P.bleedair2pos) == def.ON)) then
                P.commandtableentry(def.TEXT, "Set A P U Bleedair Off")
            elseif ((get(P.isolvalvepos) ~= def.ISOLVALVEAUTO) and P.enginesrunning(P.BOTH) and (get(P.bleedair1pos) == def.ON or get(P.bleedair2pos) == def.ON)) then
                P.commandtableentry(def.TEXT, "Set Isolation Valve Auto")
            end
        end

        if ((get(P.atarmpos) == def.ARMED) and (get(P.atn1stat) == def.OFF) and (get(P.atthrottlelock) == def.OFF) and (get(P.eng1n1percent) > 40) and (get(P.eng2n1percent) > 40)) then 
            P.commandtableentry(def.TEXT, "Both Engine N 1 at 40 Percent")
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
             if ((P.flightstate < def.FLIGHTSTATEAPPROACH) and helpers.isvalidicao(get(P.desicao))) then
                local deslandingalttmp = 0
                if (P.airportdatatable[get(P.desicao)] and P.airportdatatable[get(P.desicao)].elevation_ft) then
                    deslandingalttmp = helpers.roundnumber(get(P.airportdatatable[get(P.desicao)].elevation_ft) / 50) * 50
                elseif helpers.isvalidrwy(get(P.desrwy)) then
                    deslandingalttmp = helpers.roundnumber(get(P.desrwyalt) / 50) * 50
                end
                if (get(P.cabinlandingalt) ~= deslandingalttmp) then
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
            if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then
                if ((P.flightstate < def.FLIGHTSTATETAXITOGATE) and P.proceduretable[def.BEFORETAXIPROCEDURE].set) then
                    if ((get(P.frameice) > 0.01) and (get(P.altitude) < 30000)) then
                        P.iceprotection(def.ON)
                    elseif ((get(P.altitude) > 30000) or (get(P.tatdegc) > 10)) then
                        P.iceprotection(def.OFF)
                    end
                end
            elseif ((P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) and (get(P.airgroundsensor) == def.OFF)) then
                if ((get(P.frameice) > 0.01) and (get(P.altitude) < 30000)) then                   
                    if ((get(P.eng1heatpos) == def.OFF) or (get(P.eng2heatpos) == def.OFF) or (get(P.wingheatpos) == def.OFF)) then
                        P.commandtableentry(def.TEXT, "Caution Icing Detected, Switch Anti Icing On")
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                elseif (get(P.altitude) > 30000) then
                    if ((get(P.eng1heatpos) == def.ON) or (get(P.eng2heatpos) == def.ON) or (get(P.wingheatpos) == def.ON)) then                      
                        P.commandtableentry(def.TEXT, "Above 30.000 Feet, Switch Anti Icing Off")
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
    elseif (P.ongoingtaskstepindex == 5) then
        if (P.configvalues[def.CONFIGAUTOWIPER] == def.ON) then
            if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) and (P.configvalues[def.CONFIGVOICEADVICEONLY] ~= def.ON)) then               
                if (get(P.groundspeed) > 250) then
                    P.autowiper(def.OFF)
                elseif ((P.apurunning() == def.APUONBUS) or (get(P.gen1pos) == def.ON) or (get(P.gen2pos) == def.ON)) then
                    P.autowiper(def.ON)
                elseif ((P.apurunning() < def.APUONBUS) and (get(P.gen1pos) == def.OFF) and (get(P.gen2pos) == def.OFF)) then
                    P.autowiper(def.OFF)
                end
            end
        end
    end

    if (((get(P.airgroundsensor) == def.ON) and (P.procedureloop1.lock == def.NOPROCEDURE) and (get(P.battery) == def.ON) and (get(P.mainbus) ~= def.OFF) and (P.flightstate == def.FLIGHTSTATEPREFLIGHT) and (get(P.taxilight) == def.OFF))) then
        if (P.ongoingtaskstepindex == 6) then
            if ((P.configvalues[def.CONFIGAUTOBARO] == def.ON) and (get(P.groundspeed) < 45)) then
                local baroinchtmp, baropastmp = P.getlocalqnh(DEPARTURE)
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
        if ((P.flightstate == def.FLIGHTSTATECRUISE) and (get(P.fmsflightphase) == def.FMSPHASECRUISE) and (get(P.mcpaltitude) >= get(P.fmccruisealt)) and (get(P.vnavtoddist) < 20)) then
            P.commandtableentry(def.TEXT, "Approaching Top of Descent, Reset M C P Altitude")
            P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
        end
    end

     if (P.ongoingtaskstepindex == 11) then
        if (P.flightstate == def.FLIGHTSTATECRUISE) and (get(P.fmsflightphase) == def.FMSPHASECRUISE) and (get(P.totalfuellbs) < 1000) then
            
            local reservefuelLbs = 5000
            
            if P.YANSHisinstalled() and P.YANSHflightplanloaded() and P.YANSHFuelReserve and P.YANSHFuelAlternateBurn and P.YANSHParamsUnitsFlag then
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

    if P.drOngoingTaskIndex then
        set(P.drOngoingTaskIndex, P.ongoingtaskstepindex)
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function P.commandtableloop()

    local next_recommended_wait_step = def.STANDARDWAIT

    local processedentry = false

    while ((#P.commandtable > 0) and (processedentry == false)) do

        if (P.commandtable[1][1] == def.COMMAND) then
            sasl.logInfo("YAL COMMAND: " .. P.commandtable[1][2])
            helpers.command_once(P.commandtable[1][2])
            processedentry = true
        elseif (P.commandtable[1][1] == def.TEXT) then
            if ((P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) or (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)) then
                sasl.logInfo("YAL SpeakString TEXT: " .. P.commandtable[1][2])
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
    local loop = P.loopStateTables[loopIndex]

    if (loop.lock ~= def.NOPROCEDURE) then
        loop.lastActiveTime = os.time()
        local timestring = os.date("%H:%M:%S", loop.lastActiveTime)

        if ((loop.stepindex == 0) and not loop.procedureabort and not loop.procedureskipstep and not loop.procedurenotpossible) then
            if (P.proceduretable[loop.lock].speakname == true) then
                P.commandtableentry(def.TEXT, P.proceduretable[loop.lock].name .. " Procedure")
            end
            sasl.logInfo(P.proceduretable[loop.lock].name .. " Procedure started at ".. timestring .. " at " .. helpers.roundnumber(get(P.altitude)) .. " feet")
        elseif ((loop.stepindex <= P.proceduretable[loop.lock].steps) and not loop.procedureabort and not loop.procedureskipstep and not loop.procedurenotpossible) then
            P.proceduretable[loop.lock].procedurefunction(loop)
        elseif (((loop.stepindex > P.proceduretable[loop.lock].steps) or loop.procedureabort or loop.procedurenotpossible) and not loop.procedureskipstep) then
            
            local wasSetStatusChanged = false

            if (loop.stepindex > P.proceduretable[loop.lock].steps) then
                if (P.proceduretable[loop.lock].speakname == true) then
                    P.commandtableentry(def.TEXT, P.proceduretable[loop.lock].name .. " Procedure Complete")
                end
                sasl.logInfo(P.proceduretable[loop.lock].name .. " Procedure completed at " .. timestring .. " at " .. helpers.roundnumber(get(P.altitude)) .. " feet")
                P.proceduretable[loop.lock].set = true
                wasSetStatusChanged = true
            elseif loop.procedureabort then
                P.commandtableentry(def.TEXT, P.proceduretable[loop.lock].name .. " Procedure Aborted")
                sasl.logInfo(P.proceduretable[loop.lock].name .. " Procedure aborted at " .. timestring .. " at " .. helpers.roundnumber(get(P.altitude)) .. " feet")
                loop.procedureabort = false
                P.proceduretable[loop.lock].set = true
                wasSetStatusChanged = true
            elseif loop.procedurenotpossible then
                if loop.setonabort then
                    P.proceduretable[loop.lock].set = true
                    wasSetStatusChanged = true
                end
                loop.procedurenotpossible = false
            end
            
            if wasSetStatusChanged then
                local procId = loop.lock
                set(P.ProcSetStatusarraydr, 1, procId)
            end

            loop.lock = def.NOPROCEDURE
        end

        if (loop.lock == def.NOPROCEDURE) then
            loop.stepindex = 0
            loop.lastActiveTime = 0
            loop.setonabort = false
        else
            loop.stepindex = loop.stepindex + 1
        end

        if (loop.stepindex == loop.stepindexprevious) then
            loop.steprepeat = true
        else
            loop.steprepeat = false
            loop.stepindexprevious = loop.stepindex
        end

        if loop.procedureskipstep then
            P.commandtableentry(def.TEXT, "Procedure Step Skipped")
            loop.procedureskipstep = false
            loop.stepindex = loop.stepindex + 1
        end
    else
        loop.stepindex = 0
        loop.stepindexprevious = 0
        loop.steprepeat = false
        loop.lastActiveTime = 0
        loop.procedureabort = false
        loop.procedureskipstep = false
        loop.setonabort = false
    end

    local datarefHandle = P.ProcLoopHandlesdr[loopIndex]

    if datarefHandle then
        local stateArray = P.encodeLoopToArray(loop)
        set(datarefHandle, stateArray)
    end

    return true
end

--------------------------------------------------------------------------------------------------------------

function P.do_yal()

    if settings.newSettingsAvailable then
        P.readconfig()
        sasl.logInfo("Loading new settings")
    end

    local next_recommended_wait_step = def.STANDARDWAIT 

    if (P.procedureloop1.lock ~= def.NOPROCEDURE or
        P.procedureloop2.lock ~= def.NOPROCEDURE or
        P.procedureloop3.lock ~= def.NOPROCEDURE or
        P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) then
        next_recommended_wait_step = def.STANDARDWAIT
    end

    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("ONGOINGTASKSTEPINDEX: " .. P.ongoingtaskstepindex)

    if ((P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) or (P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON)) then
        P.autofunctions()
        P.ongoingtasks()
    end

    if (P.configvalues[def.CONFIGVOICEREADBACK] == def.ON) then
        P.voicereadback()
    end

    local lockId1 = P.procedureloop1.lock
    local procName1
    if lockId1 == def.NOPROCEDURE then
        procName1 = "NOPROCEDURE"
    else
        procName1 = (P.proceduretable[lockId1] and P.proceduretable[lockId1].name) or lockId1
    end
    sasl.logDebug("PROCEDURELOOP1: LOCK " .. tostring(procName1) .. " STEPINDEX " .. P.procedureloop1.stepindex)

    local lockId2 = P.procedureloop2.lock
    local procName2
    if lockId2 == def.NOPROCEDURE then
        procName2 = "NOPROCEDURE"
    else
        procName2 = (P.proceduretable[lockId2] and P.proceduretable[lockId2].name) or lockId2
    end
    sasl.logDebug("PROCEDURELOOP2: LOCK " .. tostring(procName2) .. " STEPINDEX " .. P.procedureloop2.stepindex)

    local lockId3 = P.procedureloop3.lock
    local procName3
    if lockId3 == def.NOPROCEDURE then
        procName3 = "NOPROCEDURE"
    else
        procName3 = (P.proceduretable[lockId3] and P.proceduretable[lockId3].name) or lockId3
    end
    sasl.logDebug("PROCEDURELOOP3: LOCK " .. tostring(procName3) .. " STEPINDEX " .. P.procedureloop3.stepindex)

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
            
            -- NEU: Hole den Prozedur-Namen für die Log-Ausgabe
            local lockId = current_loop_state_table.lock
            local procName = (P.proceduretable[lockId] and P.proceduretable[lockId].name) or lockId
            
            -- GEÄNDERT: Gib den Namen statt der Nummer aus
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

    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("BEFORETAXISET: " .. tostring(P.proceduretable[def.BEFORETAXIPROCEDURE].set))
    sasl.logDebug("BEFORETAKEOFFSET: " .. tostring(P.proceduretable[def.BEFORETAKEOFFPROCEDURE].set))
    sasl.logDebug("AFTERTAKEOFFSET: " .. tostring(P.proceduretable[def.AFTERTAKEOFFPROCEDURE].set))
    sasl.logDebug("DURINGCLIMBSET: " .. tostring(P.proceduretable[def.DURINGCLIMBPROCEDURE].set))
    sasl.logDebug("ALTITUDEA10000SET: " .. tostring(P.proceduretable[def.ALTITUDEA10000PROCEDURE].set))
    sasl.logDebug("DURINGDESCENTSET: " .. tostring(P.proceduretable[def.DURINGDESCENTPROCEDURE].set))
    sasl.logDebug("ALTITUDEB10000SET: " .. tostring(P.proceduretable[def.ALTITUDEB10000PROCEDURE].set))
    sasl.logDebug("RADIOALTITUDE2500SET: " .. tostring(P.proceduretable[def.RADIOALTITUDEB2500PROCEDURE].set))
    sasl.logDebug("RADIOALTITUDE1000SET: " .. tostring(P.proceduretable[def.RADIOALTITUDEB1000PROCEDURE].set))
    sasl.logDebug("AFTERLANDINGSET: " .. tostring(P.proceduretable[def.AFTERLANDINGPROCEDURE].set))
    sasl.logDebug("ATPARKINGPOSITIONSET: " .. tostring(P.proceduretable[def.ATPARKINGPOSITIONPROCEDURE].set))
    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("FLIGHTSTATE: " .. tostring(P.flightstate) .. " FMSFLIGHTPHASE: " .. tostring(get(P.fmsflightphase)) .. " AIRCRAFTWASONGROUND: " .. tostring(P.aircraftwasonground))
    sasl.logDebug("Raw METAR Departure: " .. tostring(P.depmetar.metar))
    sasl.logDebug("Raw METAR Destination: " .. tostring(P.desmetar.metar))

    return next_recommended_wait_step
end

--------------------------------------------------------------------------------------------------------------

menu_procedure_step = sasl.appendMenuItem(P.menu_main, "Skip Procedure Step", P.skipprocedurestep)
menu_abort_procedure = sasl.appendMenuItem(P.menu_main, "Abort Procedure", P.abortprocedure)
menu_cycleprocedures = sasl.appendMenuItem(P.menu_main, "Cycle Through Procedures", P.cycleprocedures)
menu_speak_depmetar = sasl.appendMenuItem(P.menu_main, "Speak Departure Metar", P.speakdepmetar)
menu_speak_desmetar = sasl.appendMenuItem(P.menu_main, "Speak Destination Metar", P.speakdesmetar)
sasl.appendMenuSeparator ( P.menu_main )
menu_cd = sasl.appendMenuItem(P.menu_main, "Cold and Dark Startup", P.coldanddarkstartup)
menu_cockpit_init = sasl.appendMenuItem(P.menu_main, "Cockpit Initialization", P.cockpitinit)
menu_apu_start = sasl.appendMenuItem(P.menu_main, "APU Startup", P.apustartup)
menu_eng_start = sasl.appendMenuItem(P.menu_main, "Engine Startup", P.enginestart)
menu_before_taxi = sasl.appendMenuItem(P.menu_main, "Before Taxi Procedure", P.beforetaxi)
menu_before_takeoff = sasl.appendMenuItem(P.menu_main, "Before Takeoff Procedure", P.beforetakeoff)
menu_after_landing = sasl.appendMenuItem(P.menu_main, "After Landing Procedure", P.afterlanding)
menu_atparkingposition = sasl.appendMenuItem(P.menu_main, "At Parking Position Procedure", P.atparkingposition)
menu_eng_stop_ta = sasl.appendMenuItem(P.menu_main, "Turnaround Engine Shutdown", P.turnaroundengineshutdown)
menu_eng_stop_final = sasl.appendMenuItem(P.menu_main, "Final Engine Shutdown", P.finalengineshutdown)
menu_shutdown = sasl.appendMenuItem(P.menu_main, "Shutdown", P.shutdown)
sasl.appendMenuSeparator ( P.menu_main )
menu_above1000 = sasl.appendMenuItem(P.menu_main, "Above 10000", P.altitudea10000)
menu_below1000 = sasl.appendMenuItem(P.menu_main, "Below 10000", P.altitudeb10000)
menu_ils_freq = sasl.appendMenuItem(P.menu_main, "Set ILS/GLS Freq/Course", P.setilsproc)
menu_copy_nav = sasl.appendMenuItem(P.menu_main, "Copy NAV1/MMR1 to NAV2/MMR2", P.copynav)
menu_set_vref = sasl.appendMenuItem(P.menu_main, "Set Landing Flaps/VREF", P.setvrefproc)
menu_set_toflaps = sasl.appendMenuItem(P.menu_main, "Set Takeoff Flaps", P.settoflapsproc)
sasl.appendMenuSeparator ( P.menu_main )
menu_test = sasl.appendMenuItem(P.menu_main, "Tests", P.test)
sasl.appendMenuSeparator ( P.menu_main )
menu_toggle_setcockpitlights = sasl.appendMenuItem(P.menu_main, "Set Cockpit Lights", P.setcockpitlights)
menu_toggle_auto = sasl.appendMenuItem(P.menu_main, "Toggle Auto Functions", P.toggleautofunctions)
menu_toogle_voice = sasl.appendMenuItem(P.menu_main, "Toggle Voice Readback", P.togglevoicereadback)
menu_toogle_adviceonly = sasl.appendMenuItem(P.menu_main, "Toggle Voice Advice Only", P.toggleadviceonly)
menu_toogle_freeze = sasl.appendMenuItem(P.menu_main, "Toggle Sim Freeze", P.togglesimfreeze)
menu_toggle_view = sasl.appendMenuItem(P.menu_main, "Toggle View Changes", P.toggleviewchanges)
menu_timewarptotod = sasl.appendMenuItem(P.menu_main, "Time Warp to TOD", P.timewarptotod)
menu_yal_reset = sasl.appendMenuItem(P.menu_main, "Reset YAL", P.yalreset)
sasl.appendMenuSeparator ( P.menu_main )

--------------------------------------------------------------------------------------------------------------

function P.enableMenus()
    local enable = 0
    if helpers.isZibo then
        enable = 1
    end
    sasl.enableMenuItem(PLUGINS_MENU_ID , menu_master , enable)

    sasl.enableMenuItem(P.menu_main , menu_procedure_step , enable)
    sasl.enableMenuItem(P.menu_main , menu_abort_procedure , enable)
    sasl.enableMenuItem(P.menu_main , menu_cycleprocedures , enable)
    sasl.enableMenuItem(P.menu_main , menu_speak_depmetar , enable)
    sasl.enableMenuItem(P.menu_main , menu_speak_desmetar , enable)

    sasl.enableMenuItem(P.menu_main , menu_cd , enable)
    sasl.enableMenuItem(P.menu_main , menu_cockpit_init , enable)
    sasl.enableMenuItem(P.menu_main , menu_apu_start , enable)
    sasl.enableMenuItem(P.menu_main , menu_eng_start , enable)
    sasl.enableMenuItem(P.menu_main , menu_before_taxi , enable)
    sasl.enableMenuItem(P.menu_main , menu_before_takeoff , enable)
    sasl.enableMenuItem(P.menu_main , menu_after_landing , enable)
    sasl.enableMenuItem(P.menu_main , menu_atparkingposition , enable)
    sasl.enableMenuItem(P.menu_main , menu_eng_stop_ta , enable)
    sasl.enableMenuItem(P.menu_main , menu_eng_stop_final , enable)
    sasl.enableMenuItem(P.menu_main , menu_shutdown , enable)

    sasl.enableMenuItem(P.menu_main , menu_above1000 , enable)
    sasl.enableMenuItem(P.menu_main , menu_below1000 , enable)
    sasl.enableMenuItem(P.menu_main , menu_ils_freq , enable)
    sasl.enableMenuItem(P.menu_main , menu_copy_nav , enable)
    sasl.enableMenuItem(P.menu_main , menu_set_vref , enable)
    sasl.enableMenuItem(P.menu_main , menu_set_toflaps , enable)

    sasl.enableMenuItem(P.menu_main , menu_test , enable)
    sasl.enableMenuItem(P.menu_main , menu_toggle_setcockpitlights , enable)
    sasl.enableMenuItem(P.menu_main , menu_toggle_auto , enable)
    sasl.enableMenuItem(P.menu_main , menu_toogle_voice , enable)
    sasl.enableMenuItem(P.menu_main , menu_toogle_adviceonly , enable)
    sasl.enableMenuItem(P.menu_main , menu_toogle_freeze , enable)
    sasl.enableMenuItem(P.menu_main , menu_toggle_view , enable)
    sasl.enableMenuItem(P.menu_main , menu_timewarptotod , enable)
    sasl.enableMenuItem(P.menu_main , menu_yal_reset , enable)

end

P.YalinitGlobal()

return yal