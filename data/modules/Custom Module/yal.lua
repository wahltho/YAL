local P = {}
yal = P -- package name

require("definitions")
require("settings")

local ffi = require("ffi")
local xplm_lib = {
    Linux = "Resources/plugins/XPLM_64.so",
    Windows = "XPLM_64",
    OSX = "Resources/plugins/XPLM.framework/XPLM"
}
local xplm = ffi.load(xplm_lib[ffi.os])

ffi.cdef [[
    void XPLMSpeakString(char *);
    float XPLMGetMagneticVariation(double, double);
    void XPLMGetMETARForAirport(char *, char *);
    ]]

--------------------------------------------------------------------------------------------------------------

menu_master = sasl.appendMenuItem(PLUGINS_MENU_ID, definitions.APPNAMEPREFIXLONG)
P.menu_main = sasl.createMenu("", PLUGINS_MENU_ID, menu_master)

--------------------------------------------------------------------------------------------------------------
-- Flags & Global Variables

function P.YalinitGlobal()

    P.initialstartup = true

    P.aircraftwasonground = false

    P.remainingtimetoquit = 9999

    P.remainingtimetosave = 9999

    P.flightstate = 0

    P.apphasils = false

    P.lowerduset = OFF

    P.centertankoffset = false

    P.lowerairspacealt = 10000

    P.getmetarcounter = 0

    P.depmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}
    P.desmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}


    --------------------------------------------------------------------------------------------------------------
    -- Config Table

    P.configvalues = {}

    --------------------------------------------------------------------------------------------------------------
    -- Variables for FMS commands

    P.vrefcmdtable = {"del", "clr", "X", "X", "slash", "X", "X", "X", "4R", "exec", "end"}

    P.toflapscmdtable = {"del", "clr", "X", "X", "1L", "exec", "end"}

    --------------------------------------------------------------------------------------------------------------
    -- Command Table Table

    P.commandtable = {}

    --------------------------------------------------------------------------------------------------------------
    -- Nav Data Table 

    P.navdatatable = {}
    P.navdatatableindex = 0

    --------------------------------------------------------------------------------------------------------------
    -- Variables for Procedures

    P.ongoingtaskstepindex = 1

    P.procedureabort = false
    P.procedureskipstep = false

    -- HIER IST DIE WICHTIGE ÄNDERUNG: P.procedureloop1, 2, 3 werden nun Teil von P
    P.procedureloop1 = { lock = NOPROCEDURE, stepindex = 0, previousstepindex = 0, steprepeat = false }
    P.procedureloop2 = { lock = NOPROCEDURE, stepindex = 0, previousstepindex = 0, steprepeat = false }
    P.procedureloop3 = { lock = NOPROCEDURE, stepindex = 0, previousstepindex = 0, steprepeat = false }

    P.proceduretable = {
    [COCKPITINITPROCEDURE] = { name = "Cockpit Initialization", steps = 24, set = false, procedurefunction = cockpitinitsteps, loop = 1 },
    [COLDANDDARKPROCEDURE] = { name = "Cold and Dark Startup", steps = 29, set = false, procedurefunction = coldanddarksteps, loop = 1 },
    [ENGINESTARTPROCEDURE] = { name = "Engine Start", steps = 33, set = false , procedurefunction = enginestartsteps, loop = 1 },
    [TURNAROUNDENGINESHUTDOWNPROCEDURE] = { name = "Turnaround Engine Shutdown", steps = 17, set = false, procedurefunction = engineshutdownsteps, loop = 1 },
    [FINALENGINESHUTDOWNPROCEDURE] = { name = "Final Engine Shutdown", steps = 17, set = false, procedurefunction = engineshutdownsteps, loop = 1 },
    [SHUTDOWNPROCEDURE] = { name = "Shutdown", steps = 24, set = false, procedurefunction = shutdownsteps, loop = 1 },
    [TESTPROCEDURE] = { name = "Test", steps = 47, set = false, procedurefunction = teststeps, loop = 1 },
    [APUSTARTUPPROCEDURE] = { name = "A P U Startup", steps = 7, set = false, procedurefunction = apustartupsteps, loop = 1 },
    [BEFORETAXIPROCEDURE] = { name = "Before Taxi", steps = 24, set = false, procedurefunction = beforetaxisteps, loop = 1 },
    [BEFORETAKEOFFPROCEDURE] = { name = "Before Takeoff", steps = 13, set = false, procedurefunction = beforetakeoffsteps, loop = 1 },
    [AFTERLANDINGPROCEDURE] = { name = "After Landing", steps = 19, set = false, procedurefunction = afterlandingsteps, loop = 1 },
    [SETILSPROCEDURE] = { name = "", steps = 8, set = false, procedurefunction = setilssteps, loop = 3 },
    [SETVREFPROCEDURE] = { name = "", steps = 4, set = false, procedurefunction = setvrefsteps, loop = 3 },
    [SETTOFLAPSPROCEDURE] = { name = "", steps = 4, set = false, procedurefunction = settoflapssteps, loop = 3 },
    [ALTITUDEA10000PROCEDURE] = { name = "", steps = 7, set = false, procedurefunction = altitudea10000steps, loop = 1 },
    [ALTITUDEB10000PROCEDURE] = { name = "", steps = 12, set = false, procedurefunction = altitudeb10000steps, loop = 1 },
    [AFTERTAKEOFFPROCEDURE] = { name = "", steps = 3, set = false, procedurefunction = aftertakeoffsteps, loop = 2 },
    [DURINGCLIMBPROCEDURE] = { name = "", steps = 13, set = false, procedurefunction = duringclimbsteps, loop = 2 },
    [DURINGDESCENTPROCEDURE] = { name = "", steps = 8, set = false, procedurefunction = duringdescentsteps, loop = 2 },
    [RADIOALTITUDEB2500PROCEDURE] = { name = "", steps = 1, set = false, procedurefunction = radioaltitudeb2500steps, loop = 2 },
    [RADIOALTITUDEB1000PROCEDURE] = { name = "", steps = 7, set = false, procedurefunction = radioaltitudeb1000steps, loop = 2 },
    [ATPARKINGPOSITIONPROCEDURE] = { name = "At Parking Position", steps = 12, set = false, procedurefunction = atparkingpositionsteps, loop = 1 }
    }

    P.previousview = -1

    -- NEU: Variablen für den Prozedur-Scheduler (wie in den letzten Versionen)
    P.lastExecutedLoopIndex = 0 
    P.loopfunctions = {          
        P.procedureloop_1,
        P.procedureloop_2,
        P.procedureloop_3
    }
    P.loopStateTables = {        
        P.procedureloop1,          -- HIER WICHTIG: Referenz auf P.procedureloop1 etc.
        P.procedureloop2,          
        P.procedureloop3           
    }

end

--------------------------------------------------------------------------------------------------------------
-- Datarefs

function P.initDataref()
    simpaused = globalProperty("sim/time/paused")
    simfreezed = globalPropertyfae("sim/operation/override/override_planepath", 1)
    battery = globalProperty("laminar/B738/electric/battery_pos")
    batteryswitchcover = globalPropertyfae("laminar/B738/cover", 3)
    emergencylights = globalProperty("laminar/B738/toggle_switch/emer_exit_lights")
    emergencylightcover = globalPropertyfae("laminar/B738/cover", 10)

    mastercautionannunc = globalProperty("sim/cockpit/warnings/annunciators/master_caution")

    mainbus = globalProperty("laminar/B738/electric/main_bus")
    parkingbrakepos = globalProperty("laminar/B738/parking_brake_pos")

    pausetod = globalProperty("laminar/B738/fms/pause_td")

    hidecptefb = globalProperty("laminar/B738/tab/static")
    hidefoefb = globalProperty("laminar/B738/tab/fo_static")

    chockstatus = globalProperty("laminar/B738/fms/chock_status")

    wakeoverride = globalProperty("sim/operation/override/override_wake_turbulence")

    aponstat = globalProperty("laminar/autopilot/ap_on")
    apdiscpos = globalProperty("laminar/B738/autopilot/disconnect_pos")

    apcmdastat = globalProperty("laminar/B738/autopilot/cmd_a_status")
    apcmdbstat = globalProperty("laminar/B738/autopilot/cmd_b_status")

    apvnavstat = globalProperty("laminar/B738/autopilot/vnav_status1")
    aplnavstat = globalProperty("laminar/B738/autopilot/lnav_status")
    apappstat = globalProperty("laminar/B738/autopilot/app_status")
    apvorlocstat = globalProperty("laminar/B738/autopilot/vorloc_status")
    apalthldstat = globalProperty("laminar/B738/autopilot/alt_hld_status")
    aphdgselstat = globalProperty("laminar/B738/autopilot/hdg_sel_status")
    apvsstat = globalProperty("laminar/B738/autopilot/vs_status")
    aplvlchgstat = globalProperty("laminar/B738/autopilot/lvl_chg_status")

    mmrinstalled = globalProperty("laminar/B738/fms/mmr")
    lpvinstalled = globalProperty("laminar/B738/lpv_install")
    mmrcptactmode = globalProperty("laminar/B738/mmr/cpt/act_mode")
    mmrcptactvalue = globalProperty("laminar/B738/mmr/cpt/act_value")
    mmrcptstdbymode = globalProperty("laminar/B738/mmr/cpt/stby_mode")
    mmrfoactmode = globalProperty("laminar/B738/mmr/fo/act_mode")
    mmrfoactvalue = globalProperty("laminar/B738/mmr/fo/act_value")
    mmrfostdbymode = globalProperty("laminar/B738/mmr/fo/stby_mode")

    apgscapturedstat = globalPropertyfae("laminar/B738/ap/glideslope_status", 1)
    aploccapturedstat = globalPropertyfae("laminar/B738/ap/approach_status", 1)
    aprolloutstat = globalPropertyfae("laminar/B738/ap/rollout_status", 1)
    apflarestat = globalPropertyfae("laminar/B738/ap/flare_status", 1)

    aplpvgscapturedstat = globalPropertyfae("laminar/B738/ap/lpv_gs_status", 1)
    aplpvloccapturedstat = globalPropertyfae("laminar/B738/ap/lpv_app_status", 1)

    apglsgscapturedstat = globalPropertyfae("laminar/B738/ap/gls_gs_status", 1)
    apglsloccapturedstat = globalPropertyfae("laminar/B738/ap/gls_app_status", 1)

    apfacgscapturedstat = globalPropertyfae("laminar/B738/ap/gp_status", 1)
    apfacloccapturedstat = globalPropertyfae("laminar/B738/ap/fac_status", 1)

    aphdgmode = globalProperty("laminar/B738/autopilot/heading_mode")
    apaltmode = globalProperty("laminar/B738/autopilot/altitude_mode")

    atarmpos = globalProperty("laminar/B738/autopilot/autothrottle_arm_pos")
    atn1stat = globalProperty("laminar/B738/autopilot/n1_status")
    atspeedstat = globalProperty("laminar/B738/autopilot/speed_status1")
    atspeedintvstat = globalProperty("laminar/B738/autopilot/spd_interv_status")
    atn1mode = globalProperty("laminar/B738/FMS/N1_mode")

    atspeedmode = globalProperty("laminar/B738/autopilot/speed_mode")

    gearhandlepos = globalProperty("laminar/B738/controls/gear_handle_down")
    lgeardeployed = globalPropertyfae("sim/aircraft/parts/acf_gear_deploy", 1)
    ngeardeployed = globalPropertyfae("sim/aircraft/parts/acf_gear_deploy", 2)
    rgeardeployed = globalPropertyfae("sim/aircraft/parts/acf_gear_deploy", 3)

    altitude = globalProperty("laminar/B738/autopilot/altitude")
    fmccruisealt = globalProperty("laminar/B738/autopilot/fmc_cruise_alt")
    radioaltitude = globalProperty("sim/cockpit2/gauges/indicators/radio_altimeter_height_ft_pilot")

    groundtrackmag = globalProperty("sim/cockpit2/gauges/indicators/ground_track_mag_pilot")

    trimwheel = globalProperty("laminar/B738/flt_ctrls/trim_wheel")
    trimcalc = globalProperty("laminar/B738/FMS/trim_calc")

    gpuavailable = globalProperty("laminar/B738/gpu_available")
    jetwaypoweravailable = globalProperty("laminar/B738/jetway_power")
    autogategpu = globalProperty("laminar/B738/autogate_gpu")
    gpuon = globalProperty("sim/cockpit/electrical/gpu_on")

    apustarterpos = globalProperty("laminar/B738/spring_toggle_switch/APU_start_pos")
    apurunning = globalProperty("sim/cockpit/engine/APU_running")
    apupsi = globalProperty("laminar/B738/air/apu_psi")
    apugenoffbus = globalProperty("laminar/B738/annunciator/apu_gen_off_bus")
    apupowerbus1 = globalProperty("laminar/B738/electrical/apu_power_bus1")
    apupowerbus2 = globalProperty("laminar/B738/electrical/apu_power_bus2")

    announcsourceoff1 = globalProperty("laminar/B738/annunciator/source_off1")
    announcsourceoff2 = globalProperty("laminar/B738/annunciator/source_off2")

    gen1pos = globalPropertyiae("sim/cockpit/electrical/generator_on", 1)
    gen2pos = globalPropertyiae("sim/cockpit/electrical/generator_on", 2)

    bleedair1pos = globalProperty("laminar/B738/toggle_switch/bleed_air_1_pos")
    bleedair2pos = globalProperty("laminar/B738/toggle_switch/bleed_air_2_pos")
    bleedairapupos = globalProperty("laminar/B738/toggle_switch/bleed_air_apu_pos")
    isolvalvepos = globalProperty("laminar/B738/air/isolation_valve_pos")
    packlpos = globalProperty("laminar/B738/air/l_pack_pos")
    packrpos = globalProperty("laminar/B738/air/r_pack_pos")
    trimairpos = globalProperty("laminar/B738/air/trim_air_pos")
    lrecircfanpos = globalProperty("laminar/B738/air/l_recirc_fan_pos")
    rrecircfanpos = globalProperty("laminar/B738/air/r_recirc_fan_pos")

    starterauto = globalProperty("laminar/B738/engine_start_auto")
    starter1pos = globalProperty("laminar/B738/engine/starter1_pos")
    starter2pos = globalProperty("laminar/B738/engine/starter2_pos")

    mixture1pos = globalProperty("laminar/B738/engine/mixture_ratio1")
    mixture2pos = globalProperty("laminar/B738/engine/mixture_ratio2")

    reverser1pos = globalProperty("laminar/B738/flt_ctrls/reverse_lever1")
    reverser2pos = globalProperty("laminar/B738/flt_ctrls/reverse_lever2")

    totalfuellbs = globalProperty("laminar/B738/fuel/total_tank_lbs")
    totalfuelkgs = globalProperty("laminar/B738/fuel/total_tank_kgs")
    fuelunit = globalProperty("laminar/B738/FMS/fmc_units")

    totalweightkgs = globalProperty("sim/flightmodel/weight/m_total")

    centertanklbs = globalProperty("laminar/B738/fuel/center_tank_lbs")
    centertanklpress = globalProperty("laminar/B738/system/fuel_press_c1")
    centertankrpress = globalProperty("laminar/B738/system/fuel_press_c2")
    centertanklswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_ctr1")
    centertankrswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_ctr2")
    centertankstat = globalProperty("laminar/B738/fuel/center_status")
    lefttanklswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_lft1")
    lefttankrswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_lft2")
    righttanklswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_rgt2")
    righttankrswitch = globalProperty("laminar/B738/fuel/fuel_tank_pos_rgt1")

    eng1n1ratio = globalProperty("laminar/B738/FMS/eng1_N1_ratio")
    eng2n1ratio = globalProperty("laminar/B738/FMS/eng2_N1_ratio")
    eng1n1percent = globalPropertyfae("sim/flightmodel2/engines/N1_percent", 1)
    eng2n1percent = globalPropertyfae("sim/flightmodel2/engines/N1_percent", 2)
    eng1n2percent = globalPropertyfae("sim/flightmodel2/engines/N2_percent", 1)
    eng2n2percent = globalPropertyfae("sim/flightmodel2/engines/N2_percent", 2)

    eng1heatpos = globalProperty("laminar/B738/ice/eng1_heat_pos")
    eng2heatpos = globalProperty("laminar/B738/ice/eng2_heat_pos")
    wingheatpos = globalProperty("laminar/B738/ice/wing_heat_pos")

    hydro1pos = globalProperty("laminar/B738/toggle_switch/hydro_pumps1_pos")
    hydro2pos = globalProperty("laminar/B738/toggle_switch/hydro_pumps2_pos")
    elechydro1pos = globalProperty("laminar/B738/toggle_switch/electric_hydro_pumps1_pos")
    elechydro2pos = globalProperty("laminar/B738/toggle_switch/electric_hydro_pumps2_pos")

    airgroundsensor = globalProperty("laminar/B738/air_ground_sensor")
    autobrakepos = globalProperty("laminar/B738/autobrake/autobrake_pos")
    autobrakedisarm = globalProperty("laminar/B738/autobrake/autobrake_disarm")

    fmsflightphase = globalProperty("laminar/B738/FMS/flight_phase")

    fmctransalt = globalProperty("laminar/B738/FMS/fmc_trans_alt")
    fmctranslvl = globalProperty("laminar/B738/FMS/fmc_trans_lvl")

    bankanglepos = globalProperty("laminar/B738/autopilot/bank_angle_pos")

    baropilot = globalProperty("laminar/B738/EFIS/baro_sel_in_hg_pilot")
    barostd = globalProperty("laminar/B738/EFIS/baro_set_std_pilot")
    baroinhpa = globalProperty("laminar/B738/EFIS_control/capt/baro_in_hpa")
    baroregionpas = globalProperty("sim/weather/region/qnh_pas")

    frameice = globalProperty("sim/flightmodel/failures/frm_ice")
    tatdegc = globalProperty("laminar/B738/systems/temperature/tat_degc")

    cabincruisealt = globalProperty("sim/cockpit/pressure/max_allowable_altitude")
    cabinlandingalt = globalProperty("laminar/B738/pressurization/knobs/landing_alt")
    missedappalt = globalProperty("laminar/B738/fms/missed_app_alt")

    llightson = globalProperty("sim/cockpit/electrical/landing_lights_on")
    llights1 = globalPropertyfae("sim/cockpit2/switches/landing_lights_switch", 1)
    llights2 = globalPropertyfae("sim/cockpit2/switches/landing_lights_switch", 2)
    llights3 = globalPropertyfae("sim/cockpit2/switches/landing_lights_switch", 3)
    llights4 = globalPropertyfae("sim/cockpit2/switches/landing_lights_switch", 4)

    taxilight = globalProperty("laminar/B738/toggle_switch/taxi_light_brightness_pos")
    positionlights = globalProperty("laminar/B738/toggle_switch/position_light_pos")
    beaconlights = globalProperty("sim/cockpit/electrical/beacon_lights_on")
    rwylightl = globalProperty("laminar/B738/toggle_switch/rwy_light_left")
    rwylightr = globalProperty("laminar/B738/toggle_switch/rwy_light_right")
    logolighton = globalProperty("laminar/B738/toggle_switch/logo_light")

    transponderpos = globalProperty("laminar/B738/knob/transponder_pos")
    transpondercode = globalProperty("sim/cockpit/radios/transponder_code")

    fdpilotpos = globalProperty("laminar/B738/autopilot/flight_director_pos")
    fdfopos = globalProperty("laminar/B738/autopilot/flight_director_fo_pos")

    efiswxpilotpos = globalProperty("laminar/B738/EFIS/EFIS_wx_on")
    efiswxfopos = globalProperty("laminar/B738/EFIS/fo/EFIS_wx_on")
    efisterrpilotpos = globalProperty("laminar/B738/EFIS_control/capt/terr_on")
    efisterrfopos = globalProperty("laminar/B738/EFIS_control/fo/terr_on")
    efisfixpilotpos = globalProperty("laminar/B738/EFIS/EFIS_fix_on")
    efisfixfopos = globalProperty("laminar/B738/EFIS/fo/EFIS_fix_on")
    efisdatapilotpos = globalProperty("laminar/B738/EFIS/capt/data_status")
    efisdatafopos = globalProperty("laminar/B738/EFIS/fo/data_status")
    efisairportpilotpos = globalProperty("laminar/B738/EFIS/EFIS_airport_on")
    efisairportfopos = globalProperty("laminar/B738/EFIS/fo/EFIS_airport_on")
    efispospilotpos = globalProperty("laminar/B738/pfd/gps1_pos_show")
    efisposfopos = globalProperty("laminar/B738/pfd/gps1_pos_fo_show")
    efisvorpilotpos = globalProperty("laminar/B738/EFIS/EFIS_vor_on")
    efisvorfopos = globalProperty("laminar/B738/EFIS/fo/EFIS_vor_on")

    n1setsource = globalProperty("laminar/B738/toggle_switch/n1_set_source")

    dhpilot = globalProperty("laminar/B738/pfd/dh_pilot")

    elevation = globalProperty("sim/flightmodel/position/elevation")

    depicao = globalProperty("laminar/B738/fms/ref_icao")
    deprwyheading = globalProperty("laminar/B738/fms/ref_runway_crs_mod")
    deprwylen = globalProperty("laminar/B738/fms/ref_runway_len")
    deprwylatstartpos = globalProperty("laminar/B738/fms/ref_runway_start_lat_mod")
    deprwylonstartpos = globalProperty("laminar/B738/fms/ref_runway_start_lon_mod")
    deprwylatendpos = globalProperty("laminar/B738/fms/ref_runway_end_lat_mod")
    deprwylonendpos = globalProperty("laminar/B738/fms/ref_runway_end_lon_mod")
    deprwy = globalProperty("laminar/B738/fms/ref_runway")

    desicao = globalProperty("laminar/B738/fms/dest_icao")
    desrwyheading = globalProperty("laminar/B738/fms/dest_runway_crs")
    desrwylatstartpos = globalProperty("laminar/B738/fms/dest_runway_start_lat_mod")
    desrwylonstartpos = globalProperty("laminar/B738/fms/dest_runway_start_lon_mod")
    desrwylatendpos = globalProperty("laminar/B738/fms/dest_runway_end_lat_mod")
    desrwylonendpos = globalProperty("laminar/B738/fms/dest_runway_end_lon_mod")
    desrwyalt = globalProperty("laminar/B738/pfd/des_rwy_altitude")
    desrwylen = globalProperty("laminar/B738/fms/dest_runway_len")
    desrwy = globalProperty("laminar/B738/fms/dest_runway")

    nearesticao = globalProperty("laminar/B738/near_apt_icao")

    aircraftlatpos = globalPropertyfae("laminar/B738/latlon", 23)
    aircraftlonpos = globalPropertyfae("laminar/B738/latlon", 24)

    sunpitchdegrees = globalProperty("sim/graphics/scenery/sun_pitch_degrees")

    flapleverpos = globalProperty("laminar/B738/flt_ctrls/flap_lever")
    speedbrakelever = globalProperty("laminar/B738/flt_ctrls/speedbrake_lever")

    flapsupspeed = globalProperty("laminar/B738/pfd/flaps_up")
    flaps1speed = globalProperty("laminar/B738/pfd/flaps_1")
    flaps2speed = globalProperty("laminar/B738/pfd/flaps_2")
    flaps5speed = globalProperty("laminar/B738/pfd/flaps_5")
    flaps10speed = globalProperty("laminar/B738/pfd/flaps_10")
    flaps15speed = globalProperty("laminar/B738/pfd/flaps_15")
    flaps25speed = globalProperty("laminar/B738/pfd/flaps_25")

    toflaps = globalProperty("laminar/B738/FMS/takeoff_flaps")
    toflapsset = globalProperty("laminar/B738/FMS/takeoff_flaps_set")
    appflaps = globalProperty("laminar/B738/FMS/approach_flaps")
    appflapsset = globalProperty("laminar/B738/FMS/approach_flaps_set")

    airspeed = globalProperty("laminar/B738/autopilot/airspeed")
    groundspeed = globalProperty("laminar/b738/fmodpack/real_groundspeed")
    verticalspeed = globalPropertyfae("sim/cockpit2/tcas/targets/position/vertical_speed", 1)

    v1speed = globalProperty("laminar/B738/FMS/v1")
    v2speed = globalProperty("laminar/B738/FMS/v2")
    vrspeed = globalProperty("laminar/B738/FMS/vr")

    v1setspeed = globalProperty("laminar/B738/FMS/v1_set")
    v2setspeed = globalProperty("laminar/B738/FMS/v2_set")
    vrsetspeed = globalProperty("laminar/B738/FMS/vr_set")

    fmccg = globalProperty("laminar/B738/FMS/fmc_cg")
    tabcg = globalProperty("laminar/B738/tab/cg_pos")

    speedrestr = globalProperty("laminar/B738/autopilot/fmc_descent_r_speed1")

    vref = globalProperty("laminar/B738/FMS/vref")
    vref15 = globalProperty("laminar/B738/FMS/vref_15")
    vref25 = globalProperty("laminar/B738/FMS/vref_25")
    vref30 = globalProperty("laminar/B738/FMS/vref_30")
    vref40 = globalProperty("laminar/B738/FMS/vref_40")

    rain = globalProperty("sim/weather/view/rain_ratio")

    lwiperpos = globalProperty("laminar/B738/switches/left_wiper_pos")
    rwiperpos = globalProperty("laminar/B738/switches/right_wiper_pos")

    mfdsyspos = globalProperty("laminar/B738/buttons/mfd_sys_pos")
    lowerdupage = globalProperty("laminar/B738/systems/lowerDU_page")
    lowerdupage2 = globalProperty("laminar/B738/systems/lowerDU_page2")

    nav1freq = globalProperty("sim/cockpit/radios/nav1_freq_hz")
    nav1stdbyfreq = globalProperty("sim/cockpit/radios/nav1_stdby_freq_hz")
    nav2freq = globalProperty("sim/cockpit/radios/nav2_freq_hz")
    nav2stdbyfreq = globalProperty("sim/cockpit/radios/nav2_stdby_freq_hz")
    mcppilotcourse = globalProperty("laminar/B738/autopilot/course_pilot")
    mcpcopilotcourse = globalProperty("laminar/B738/autopilot/course_copilot")
    mcpheading = globalProperty("laminar/B738/autopilot/mcp_hdg_dial")
    mcpspeed = globalProperty("laminar/B738/autopilot/mcp_speed_dial_kts_mach")
    mcpaltitude = globalProperty("laminar/B738/autopilot/mcp_alt_dial")
    mcpvsspeed = globalProperty("sim/cockpit/autopilot/vertical_velocity")

    domelightpos = globalProperty("laminar/B738/toggle_switch/cockpit_dome_pos")

    seatbeltsignpos = globalProperty("laminar/B738/toggle_switch/seatbelt_sign_pos")
    nosmokingsignpos = globalProperty("laminar/B738/toggle_switch/no_smoking_pos")

    brightmainpanel = globalPropertyfae("laminar/B738/electric/panel_brightness", 1)
    brightcopilotmainpanel = globalPropertyfae("laminar/B738/electric/panel_brightness", 2)
    brightoverhead = globalPropertyfae("laminar/B738/electric/panel_brightness", 3)
    brightpedestral = globalPropertyfae("laminar/B738/electric/panel_brightness", 4)

    genbrightbackground = globalPropertyfae("laminar/B738/electric/generic_brightness", 7)
    genbrightafdsflood = globalPropertyfae("laminar/B738/electric/generic_brightness", 8)
    genbrightpedestralflood = globalPropertyfae("laminar/B738/electric/generic_brightness", 9)

    instrbrightoutbddu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 1)
    instrbrightcopilotoutbddu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 2)
    instrbrightinbddu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 3)
    instrbrightcopilotinbddu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 4)
    instrbrightupperdu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 5)
    instrbrightlowdu = globalPropertyfae("laminar/B738/electric/instrument_brightness", 6)
    instrbrightinbdduS = globalPropertyfae("laminar/B738/electric/instrument_brightness", 25)
    instrbrightlowduS = globalPropertyfae("laminar/B738/electric/instrument_brightness", 26)
    instrbrightcopilotinbdduS = globalPropertyfae("laminar/B738/electric/instrument_brightness", 27)

    captainprobepos = globalProperty("laminar/B738/toggle_switch/capt_probes_pos")
    foprobepos = globalProperty("laminar/B738/toggle_switch/fo_probes_pos")
    wheatlfwdpos = globalProperty("laminar/B738/ice/window_heat_l_fwd_pos")
    wheatrfwdpos = globalProperty("laminar/B738/ice/window_heat_r_fwd_pos")
    wheatlsidepos = globalProperty("laminar/B738/ice/window_heat_l_side_pos")
    wheatrsidepos = globalProperty("laminar/B738/ice/window_heat_r_side_pos")

    irsleftpos = globalProperty("laminar/B738/toggle_switch/irs_left")
    irsrightpos = globalProperty("laminar/B738/toggle_switch/irs_right")
    irsalignleft = globalProperty("laminar/B738/annunciator/irs_align_left2")
    irsalignright = globalProperty("laminar/B738/annunciator/irs_align_right2")

    yawdamperswitch = globalProperty("laminar/B738/toggle_switch/yaw_dumper_pos")

    if sasl.findPluginBySignature("SRS.X-Camera") == NO_PLUGIN_ID then
        P.xcamerastatus = nil
        sasl.logInfo("X-Camera not installed")
    else
        P.xcamerastatus = globalProperty("SRS/X-Camera/integration/overall_status")
        sasl.logInfo("X-Camera installed")
    end

    --------------------------------------------------------------------------------------------------------------
    -- Variables for Monitor Switches Function, etc.

    set(n1setsource, 0)

    P.cabincruisealttemp = get(cabincruisealt)
    P.cabincruisealttemp2 = get(cabincruisealt)
    P.cabinlandingalttemp = get(cabinlandingalt)
    P.cabinlandingalttemp2 = get(cabinlandingalt)

    P.mcpspeedtemp = get(mcpspeed)
    P.mcpspeedtemp2 = get(mcpspeed)

    P.mcpheadingtemp = get(mcpheading)
    P.mcpheadingtemp2 = get(mcpheading)

    P.mcpaltitudetemp = get(mcpaltitude)
    P.mcpaltitudetemp2 = get(mcpaltitude)

    P.mcpvsspeedtemp = get(mcpvsspeed)
    P.mcpvsspeedtemp2 = get(mcpvsspeed)

    P.desrwyheadingtemp = get(desrwyheading)
    P.desrwylatstartpostemp = get(desrwylatstartpos)
    P.desrwylonstartpostemp = get(desrwylonstartpos)
    P.desrwylatendpostemp = get(desrwylatendpos)
    P.desrwylonendpostemp = get(desrwylonendpos)

    P.flapleverpostemp = get(flapleverpos)
    P.flapleverpostemp2 = get(flapleverpos)
    P.gearhandlepostemp = get(gearhandlepos)
    P.speedbrakelevertemp = get(speedbrakelever)
    P.speedbrakelevertemp2 = get(speedbrakelever)
    P.parkingbrakepostemp = get(parkingbrakepos)
    P.autobrakepostemp = get(autobrakepos)
    P.autobrakedisarmtemp = get(autobrakedisarm)
    P.autobrakedisarmtemp2 = get(autobrakedisarm)

    P.aponstattemp = get(aponstat)

    P.apcmdastattemp = get(apcmdastat)
    P.apcmdbstattemp = get(apcmdbstat)

    P.apvnavstattemp = get(apvnavstat)
    P.aplnavstattemp = get(aplnavstat)
    P.apappstattemp = get(apappstat)
    P.apvorlocstattemp = get(apvorlocstat)
    P.apalthldstattemp = get(apalthldstat)
    P.aphdgselstattemp = get(aphdgselstat)
    P.apvsstattemp = get(apvsstat)
    P.aplvlchgstattemp = get(aplvlchgstat)

    P.apgscapturedstattemp = get(apgscapturedstat)
    P.aploccapturedstattemp = get(aploccapturedstat)
    P.apflarestattemp = get(apflarestat)
    P.aprolloutstattemp = get(aprolloutstat)

    P.aplpvgscapturedstattemp = get(aplpvgscapturedstat)
    P.aplpvloccapturedstattemp = get(aplpvloccapturedstat)

    P.apglsgscapturedstattemp = get(apglsgscapturedstat)
    P.apglsloccapturedstattemp = get(apglsloccapturedstat)

    P.apfacgscapturedstattemp = get(apfacgscapturedstat)
    P.apfacloccapturedstattemp = get(apfacloccapturedstat)

    P.atarmpostemp = get(atarmpos)
    P.atn1stattemp = get(atn1stat)
    P.atspeedstattemp = get(atspeedstat)
    P.atspeedintvstattemp = get(atspeedintvstat)

    P.nav1freqtemp = get(nav1freq)
    P.nav2freqtemp = get(nav2freq)

    P.mcppilotcoursetemp = get(mcppilotcourse)
    P.mcppilotcoursetemp2 = get(mcppilotcourse)
    P.mcpcopilotcoursetemp = get(mcpcopilotcourse)
    P.mcpcopilotcoursetemp2 = get(mcpcopilotcourse)

    P.mmrcptactmodetemp = get(mmrcptactmode)
    P.mmrcptactvaluetemp = get(mmrcptactvalue)
    P.mmrcptstdbymodetemp = get(mmrcptstdbymode)
    P.mmrcptstdbymodetemp2 = get(mmrcptstdbymode)
    P.mmrfoactmodetemp = get(mmrfoactmode)
    P.mmrfoactvaluetemp = get(mmrfoactvalue)
    P.mmrfostdbymodetemp = get(mmrfostdbymode)
    P.mmrfostdbymodetemp2 = get(mmrfostdbymode)

    P.bankanglepostemp = get(bankanglepos)
    P.bankanglepostemp2 = get(bankanglepos)

    P.barostdtemp = get(barostd)
    P.baropilottemp = get(baropilot)
    P.baropilottemp2 = get(baropilot)

    P.fdpilotpostemp = get(fdpilotpos)
    P.fdfopostemp = get(fdfopos)

    P.efiswxpilotpostemp = get(efiswxpilotpos)
    P.efiswxfopostemp = get(efiswxfopos)
    P.efisterrpilotpostemp = get(efisterrpilotpos)
    P.efisterrfopostemp = get(efisterrfopos)
    P.efisdatapilotpostemp = get(efisdatapilotpos)
    P.efisdatafopostemp = get(efisdatafopos)
    P.efisfixpilotpostemp = get(efisfixpilotpos)
    P.efisfixfopostemp = get(efisfixfopos)
    P.efisairportpilotpostemp = get(efisairportpilotpos)
    P.efisairportfopostemp = get(efisairportfopos)
    P.efispospilotpostemp = get(efispospilotpos)
    P.efisposfopostemp = get(efisposfopos)
    P.efisvorpilotpostemp = get(efisvorpilotpos)
    P.efisvorfopostemp = get(efisvorfopos)

    P.dhpilottemp = get(dhpilot)
    P.dhpilottemp2 = get(dhpilot)

    P.batterytemp = get(battery)
    P.emergencylightstemp = get(emergencylights)

    P.starter1postemp = get(starter1pos)
    P.starter2postemp = get(starter2pos)

    P.mixture1postemp = get(mixture1pos)
    P.mixture2postemp = get(mixture2pos)

    P.reverser1postemp = get(reverser1pos)
    P.reverser2postemp = get(reverser2pos)

    P.packlpostemp = get(packlpos)
    P.packrpostemp = get(packrpos)
    P.bleedair1postemp = get(bleedair1pos)
    P.bleedair2postemp = get(bleedair2pos)
    P.bleedairapupostemp = get(bleedairapupos)
    P.trimairpostemp = get(trimairpos)
    P.isolvalvepostemp = get(isolvalvepos)
    P.lrecircfanpostemp = get(lrecircfanpos)
    P.rrecircfanpostemp = get(rrecircfanpos)

    P.gpuontemp = get(gpuon)

    P.apustarterpostemp = get(apustarterpos)
    P.apurunningtemp = get(apurunning)
    P.announcsourceoff1temp = get(announcsourceoff1)
    P.announcsourceoff2temp = get(announcsourceoff2)

    P.gen1postemp = get(gen1pos)
    P.gen2postemp = get(gen2pos)

    P.hydro1postemp = get(hydro1pos)
    P.hydro2postemp = get(hydro2pos)
    P.elechydro1postemp = get(elechydro1pos)
    P.elechydro2postemp = get(elechydro2pos)

    P.totalfuellbstemp = get(totalfuellbs)
    P.totalfuellbstemp2 = get(totalfuellbs)

    P.centertanklswitchtemp = get(centertanklswitch)
    P.centertankrswitchtemp = get(centertankrswitch)
    P.lefttanklswitchtemp = get(lefttanklswitch)
    P.lefttankrswitchtemp = get(lefttankrswitch)
    P.righttanklswitchtemp = get(righttanklswitch)
    P.righttankrswitchtemp = get(righttankrswitch)

    P.taxilighttemp = get(taxilight)
    P.beaconlightstemp = get(beaconlights)
    P.llightsontemp = get(llightson)
    P.llights1temp = get(llights1)
    P.llights2temp = get(llights2)
    P.llights3temp = get(llights3)
    P.llights4temp = get(llights4)
    P.rwylightltemp = get(rwylightl)
    P.rwylightrtemp = get(rwylightr)
    P.positionlightstemp = get(positionlights)
    P.logolightontemp = get(logolighton)

    P.transponderpostemp = get(transponderpos)

    P.captainprobepostemp = get(captainprobepos)
    P.foprobepostemp = get(foprobepos)

    P.wheatlfwdpostemp = get(wheatlfwdpos)
    P.wheatrfwdpostemp = get(wheatrfwdpos)
    P.wheatlsidepostemp = get(wheatlsidepos)
    P.wheatrsidepostemp = get(wheatrsidepos)

    P.yawdamperswitchtemp = get(yawdamperswitch)

    P.domelightpostemp = get(domelightpos)
    P.seatbeltsignpostemp = get(seatbeltsignpos)
    P.nosmokingsignpostemp = get(nosmokingsignpos)

    P.irsleftpostemp = get(irsleftpos)
    P.irsleftpostemp2 = get(irsleftpos)
    P.irsrightpostemp = get(irsrightpos)
    P.irsrightpostemp2 = get(irsrightpos)

    P.lwiperpostemp = get(lwiperpos)
    P.lwiperpostemp2 = get(lwiperpos)
    P.rwiperpostemp = get(rwiperpos)
    P.rwiperpostemp2 = get(rwiperpos)

    P.transpondercodetemp = get(transpondercode)
    P.transpondercodetemp2 = get(transpondercode)

    P.pausetodtemp = get(pausetod)
    P.simfreezedtemp = get(simfreezed)

    P.chockstatustmp = get(chockstatus)

end

--------------------------------------------------------------------------------------------------------------
function P.searchnavdatatable(col1_value, col2_value, col3_value, col1_index, col2_index, col3_index)
    for row_key, row in pairs(P.navdatatable) do
        if ((row[col1_index] == col1_value) and (row[col2_index] == col2_value) and (row[col3_index] == col3_value)) then

            return row_key
        end
    end
    return nil
end

--------------------------------------------------------------------------------------------------------------
function calccourse(in_crs)
    local result = (in_crs + 360) % 360
    result = math.floor(result + 0.5)
    if (result >= 359.5) then
        result = 0
    end
    
    return result
end

--------------------------------------------------------------------------------------------------------------
function P.buildnavdatatable()
    local srcnavdatafile = io.open("Custom Data/earth_nav.dat", "r")

    if not srcnavdatafile then
        sasl.logError("Could not open Custom Data/earth_nav.dat! Please ensure the file exists in 'Custom Data/'.")
        return false
    end

    -- NEU: Header-Zeilen überspringen (die ersten 3 Zeilen)
    for i = 1, 3 do
        local header_line = srcnavdatafile:read()
        if not header_line then -- Falls die Datei kürzer als erwartet ist
            sasl.logError("Error reading navdata file header. File might be too short.")
            srcnavdatafile:close()
            return false
        end
        sasl.logDebug("Skipping header line: '" .. header_line .. "'")
    end

    local navdatarecord = srcnavdatafile:read()
    local record_count = 0 -- Für bessere Debug-Meldungen

    while navdatarecord do
        -- NEU: Datenverarbeitung stoppen, wenn die Endemarkierung (Zeile beginnt mit '99') erreicht ist
        if navdatarecord:sub(1, 2) == "99" then
            sasl.logDebug("End-of-data marker '99' found. Stopping navdata parsing.")
            break
        end

        record_count = record_count + 1
        local process_current_record = true 
        local navdataitems = {}
        
        for navdataitem in navdatarecord:gmatch("%S+") do
            table.insert(navdataitems, navdataitem)
        end

        sasl.logDebug("--- DEBUG: Processing Navdata Record #" .. tostring(record_count) .. " ---")
        sasl.logDebug("Full Record: '" .. navdatarecord .. "'")
        sasl.logDebug("Parsed items count: " .. #navdataitems)
        for idx, val in ipairs(navdataitems) do
            sasl.logDebug(string.format("Item [%d]: '%s'", idx, val))
        end

        -- Überprüfen, ob die Zeile lang genug ist, um auf die kritischen Längen- und Breitengrad-Indizes zuzugreifen.
        -- SRCLONPOS sollte der höchste Index sein, der für diese Prüfung relevant ist.
        if #navdataitems <= SRCLONPOS or #navdataitems <= SRCLATPOS then 
            sasl.logWarning("Record #" .. tostring(record_count) .. ": '" .. navdatarecord .. "' is too short (" .. #navdataitems .. " items). Expected at least " .. (SRCLONPOS + 1) .. " items for LAT/LON data. Skipping record.")
            process_current_record = false
        end

        local lat_val, lon_val = nil, nil
        if process_current_record then
            local lat_str = navdataitems[SRCLATPOS]
            local lon_str = navdataitems[SRCLONPOS]
            
            sasl.logDebug("Value at SRCLATPOS (" .. tostring(SRCLATPOS) .. "): '" .. tostring(lat_str) .. "'")
            sasl.logDebug("Value at SRCLONPOS (" .. tostring(SRCLONPOS) .. "): '" .. tostring(lon_str) .. "'")

            lat_val = tonumber(lat_str)
            lon_val = tonumber(lon_str)

            sasl.logDebug("tonumber(lat_str) result: " .. tostring(lat_val))
            sasl.logDebug("tonumber(lon_str) result: " .. tostring(lon_val))

            if lat_val == nil or lon_val == nil then
                sasl.logInfo("Record #" .. tostring(record_count) .. ": Magnetic Variation received NIL for LAT/LON during tonumber conversion!")
                sasl.logInfo("Problematic Line: '" .. navdatarecord .. "'")
                sasl.logInfo("String for Latitude: '" .. tostring(lat_str) .. "' (tonumber result: " .. tostring(lat_val) .. ")")
                sasl.logInfo("String for Longitude: '" .. tostring(lon_str) .. "' (tonumber result: " .. tostring(lon_val) .. ")")
                process_current_record = false
            end
        end

        if process_current_record then
            -- Dein bestehender IF-ELSEIF-Blöcke für SRCTYPECODE
            if (navdataitems[SRCTYPECODE] == NAVDATARECTYPEILS) then
                local destnavtypetmp = string.sub(navdataitems[SRCNAVTYPE], 1, 3)
                local navdatatableindex = navdataitems[SRCICAO] .. navdataitems[SRCRWY] .. destnavtypetmp
                P.navdatatable[navdatatableindex] = {true, true, true, true, true, true, true} 
                P.navdatatable[navdatatableindex][DESTICAO] = navdataitems[SRCICAO]
                P.navdatatable[navdatatableindex][DESTRWY] = navdataitems[SRCRWY]
                P.navdatatable[navdatatableindex][DESTNAVTYPE] = destnavtypetmp
                P.navdatatable[navdatatableindex][DESTNAVID] = navdataitems[SRCNAVID]
                P.navdatatable[navdatatableindex][DESTFREQ] = tonumber(navdataitems[SRCFREQ]) 
                
                local course_str = navdataitems[SRCCOURSE] 
                local course_val = tonumber(course_str)

                if (course_val == nil) then
                    sasl.logWarning("Record #" .. tostring(record_count) .. ": NIL course value for ILS record: '" .. navdatarecord .. "'. Setting course to 0.") 
                    P.navdatatable[navdatatableindex][DESTCOURSE] = 0 
                elseif (course_val > 360) then
                    P.navdatatable[navdatatableindex][DESTCOURSE] = calccourse(math.floor(course_val / 360))
                else
                    P.navdatatable[navdatatableindex][DESTCOURSE] = calccourse((course_val + xplm.XPLMGetMagneticVariation(lat_val, lon_val) + 360) % 360)
                end
                P.navdatatable[navdatatableindex][DESTNAVDME] = false 
            elseif (navdataitems[SRCTYPECODE] == NAVDATARECTYPEVOR) then
                local destnavtypetmp = string.sub(navdataitems[SRCNAVTYPE], 1, 3)
                local navdatatableindex = navdataitems[SRCICAO] .. navdataitems[SRCRWY] .. destnavtypetmp
                P.navdatatable[navdatatableindex] = {true, true, true, true, true, true, true}
                P.navdatatable[navdatatableindex][DESTICAO] = navdataitems[SRCICAO]
                P.navdatatable[navdatatableindex][DESTRWY] = navdataitems[SRCRWY]
                P.navdatatable[navdatatableindex][DESTNAVTYPE] = destnavtypetmp
                P.navdatatable[navdatatableindex][DESTNAVID] = navdataitems[SRCNAVID]
                P.navdatatable[navdatatableindex][DESTFREQ] = tonumber(navdataitems[SRCFREQ]) 
                
                local course_str = navdataitems[SRCCOURSE]
                local course_val = tonumber(course_str)

                if (course_val == nil) then
                    sasl.logWarning("Record #" .. tostring(record_count) .. ": NIL course value for VOR record: '" .. navdatarecord .. "'. Setting course to 0.") 
                    P.navdatatable[navdatatableindex][DESTCOURSE] = 0 
                elseif (course_val > 360) then
                    P.navdatatable[navdatatableindex][DESTCOURSE] = calccourse(math.floor(course_val / 360))
                else
                    P.navdatatable[navdatatableindex][DESTCOURSE] = calccourse((course_val + xplm.XPLMGetMagneticVariation(lat_val, lon_val) + 360) % 360)
                end
                P.navdatatable[navdatatableindex][DESTNAVDME] = false
            elseif (navdataitems[SRCTYPECODE] == NAVDATARECTYPEDME) then
                local navdatatableindextmp = P.searchnavdatatable(navdataitems[SRCICAO], navdataitems[SRCNAVID], NAVTYPEILS, DESTICAO, DESTNAVID, DESTNAVTYPE)
                if (navdatatableindextmp ~= nil) then
                    P.navdatatable[navdatatableindextmp][DESTNAVDME] = true
                else
                    navdatatableindextmp = P.searchnavdatatable(P.navdatatable, navdataitems[SRCICAO], navdataitems[SRCNAVID], NAVTYPEIGS, DESTICAO, DESTNAVID, DESTNAVTYPE)
                    if (navdatatableindextmp ~= nil) then
                        P.navdatatable[navdatatableindextmp][DESTNAVDME] = true
                    else
                        navdatatableindextmp = P.searchnavdatatable(P.navdatatable, navdataitems[SRCICAO], navdataitems[SRCNAVID], NAVTYPELOC, DESTICAO, DESTNAVID, DESTNAVTYPE)
                        if (navdatatableindextmp ~= nil) then
                            P.navdatatable[navdatatableindextmp][DESTNAVDME] = true
                        end
                    end
                end
            elseif ((navdataitems[SRCTYPECODE] == NAVDATARECTYPELPV) or (navdataitems[SRCTYPECODE] == NAVDATARECTYPEGLS)) then
                local destnavidtmp
                local destnavtypetmp
                if (navdataitems[SRCTYPECODE] == NAVDATARECTYPELPV) then
                    destnavidtmp = navdataitems[SRCNAVTYPE]
                    destnavtypetmp = NAVTYPELPV
                else
                    destnavidtmp = navdataitems[SRCNAVID]
                    destnavtypetmp = NAVTYPEGLS
                end
                local navdatatableindex = navdataitems[SRCICAO] .. navdataitems[SRCRWY] .. destnavtypetmp
                P.navdatatable[navdatatableindex] = {true, true, true, true, true, true, true}
                P.navdatatable[navdatatableindex][DESTICAO] = navdataitems[SRCICAO]
                P.navdatatable[navdatatableindex][DESTRWY] = navdataitems[SRCRWY]
                P.navdatatable[navdatatableindex][DESTNAVTYPE] = destnavtypetmp
                P.navdatatable[navdatatableindex][DESTNAVID] = destnavidtmp
                P.navdatatable[navdatatableindex][DESTFREQ] = tonumber(navdataitems[SRCFREQ]) 
                
                local course_str = navdataitems[SRCCOURSE] 
                if #course_str >= 4 and course_str:sub(1,3) == "CRS" then
                   course_str = string.sub(course_str, 4, -1)
                end
                local course_val = tonumber(course_str)

                if (course_val == nil) then
                    sasl.logWarning("Record #" .. tostring(record_count) .. ": NIL course value for LPV/GLS record: '" .. navdatarecord .. "'. Setting course to 0.") 
                    P.navdatatable[navdatatableindex][DESTCOURSE] = 0 
                else
                    P.navdatatable[navdatatableindex][DESTCOURSE] = calccourse((course_val + xplm.XPLMGetMagneticVariation(lat_val, lon_val) + 360) % 360)
                end
                P.navdatatable[navdatatableindex][DESTNAVDME] = true
            end
        end

        navdatarecord = srcnavdatafile:read()
    end
    srcnavdatafile:close()

    for key, value in pairs(P.navdatatable) do
        local icaocode = key:sub(1, 4)
        local rwy = key:sub(5, -4)
        local navtype = key:sub(-3)
        
        if ((navtype == NAVTYPEGLS) or (navtype == NAVTYPELPV)) then
            if (P.navdatatable[icaocode .. rwy .. NAVTYPEILS] ~= nil) then
                if (getheadingdiff(P.navdatatable[key][DESTCOURSE], P.navdatatable[icaocode .. rwy .. NAVTYPEILS][DESTCOURSE]) == 1) then
                    P.navdatatable[key][DESTCOURSE] = P.navdatatable[icaocode .. rwy .. NAVTYPEILS][DESTCOURSE]
                end
            else
                local opprwy = getoppositerwy(rwy)
                if (P.navdatatable[icaocode .. opprwy .. NAVTYPEILS] ~= nil) then
                    local oppcourse = getoppositeheading(P.navdatatable[icaocode .. opprwy .. NAVTYPEILS][DESTCOURSE])
                        if (getheadingdiff(P.navdatatable[key][DESTCOURSE], oppcourse) == 1) then
                            P.navdatatable[key][DESTCOURSE] = oppcourse
                        end
                end
            end
        end
    end
    
    return true
end

--------------------------------------------------------------------------------------------------------------
function P.writenavdatatable()

    destnavdatafile = io.open("Custom Data/yal_nav.dat", "w")

    if not destnavdatafile then
        sasl.logDebug("Could not open Custom Data/yal_nav.dat")
        return false
    end

    for row_key, row in pairs(P.navdatatable) do
        destnavdatafile:write(row_key .. ": ")
        for col_index, value in ipairs(row) do
            destnavdatafile:write(tostring(value) .. " ")
        end
        destnavdatafile:write("\n")
    end

    destnavdatafile:close()

    return true
end

--------------------------------------------------------------------------------------------------------------
-- Custom Commands

function yalreset()

    P.YalinitGlobal()
    P.initDataref()

    readconfig()

    P.buildnavdatatable()
    P.writenavdatatable()

    P.remainingtimetoquit = P.configvalues[CONFIGTODPAUSEQUITTIME]
    P.remainingtimetosave = P.configvalues[CONFIGSAVETIME]
    if (P.configvalues[CONFIGWAKEOVERRIDE] == ON) then
        set(wakeoverride, ON)
    end

    P.lowerairspacealt = P.configvalues[CONFIGLOWEAIRSPACEALT]

    if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
        P.commandtableentry(ADVICE, "YAL Reset Done")
    else
        P.commandtableentry(TEXT, "YAL Reset Done")
    end

    P.initialstartup = false

    return true

end

function yalreset_(phase)
    if phase == SASL_COMMAND_BEGIN then
        yalreset()
    end
    return 0
end

my_command_yalreset = sasl.createCommand(definitions.APPNAMEPREFIX .. "/yalreset", "Reset YAL")
sasl.registerCommandHandler(my_command_yalreset, 0, yalreset_)

--------------------------------------------------------------------------------------------------------------

function readconfig()

    P.configvalues = settings.getSettings()

    return true

end

function readconfig_(phase)
    if phase == SASL_COMMAND_BEGIN then
        readconfig()
    end
    return 0
end

my_command_readconfig = sasl.createCommand(definitions.APPNAMEPREFIX .. "/readconfig", "Read Config File")
sasl.registerCommandHandler(my_command_readconfig, 0, readconfig_)

--------------------------------------------------------------------------------------------------------------
function setview(view)

    if (P.configvalues[CONFIGVIEWCHANGES] == ON) then
        if (view == nil) then
            return false
        end

        if (view ~= P.previousview) then
            if (view == DEFAULTVIEW) then
                P.commandtableentry(COMMAND, "sim/view/default_view")
            else
                if (P.xcamerastatus ~= nil) then
                    P.commandtableentry(COMMAND, "SRS/X-Camera/Select_View_ID_" .. view)
                else
                    P.commandtableentry(COMMAND, "sim/view/quick_look_" .. tostring(view - 1))
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
function logtable(table, prefix)
    prefix = prefix or ""  -- Standardpräfix (leer, falls nicht angegeben)
    for key, value in pairs(table) do
        if type(value) == "table" then
            -- Wenn der Wert eine Tabelle ist, rufe die Funktion rekursiv auf
            sasl.logDebug(prefix .. tostring(key) .. " {")
            logtable(value, prefix .. "  ")  -- Erhöhe den Präfix für die Einrückung
            sasl.logDebug(prefix .. "}")
        else
            -- Wenn der Wert kein Table ist, logge den Schlüssel und den Wert
            sasl.logDebug(prefix .. tostring(key) .. " = " .. tostring(value))
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function fieldexists(tbl, path)
    local keys = {}
    local buffer = ""
    local inBrackets = false

    -- Manuelle Zerlegung des Pfads
    for i = 1, #path do
        local char = path:sub(i, i)

        if char == "[" then
            inBrackets = true
            if buffer ~= "" then
                table.insert(keys, buffer)
                buffer = ""
            end
        elseif char == "]" then
            inBrackets = false
            if buffer ~= "" then
                table.insert(keys, buffer)
                buffer = ""
            end
        elseif char == "." and not inBrackets then
            if buffer ~= "" then
                table.insert(keys, buffer)
                buffer = ""
            end
        else
            buffer = buffer .. char
        end
    end

    -- Füge den letzten Puffer hinzu
    if buffer ~= "" then
        table.insert(keys, buffer)
    end

    -- Rekursive Überprüfung des Pfads
    local function recurse(tbl, keys, index)
        index = index or 1
        if index > #keys then
            return true
        end
        local key = keys[index]
        if type(tbl) == "table" and tbl[key] ~= nil then
            return recurse(tbl[key], keys, index + 1)
        else
            return false
        end
    end

    return recurse(tbl, keys)
end

--------------------------------------------------------------------------------------------------------------
function containsvalue(tbl, target_value)
    -- Überprüfe, ob die Tabelle den Zielwert direkt enthält
    for key, value in pairs(tbl) do
        if value == target_value then
            return true
        elseif type(value) == "table" then
            -- Wenn der Wert eine Tabelle ist, rufe die Funktion rekursiv auf
            if containsvalue(value, target_value) then
                return true
            end
        end
    end
    return false
end

--------------------------------------------------------------------------------------------------------------
function addspaces(input)
    local result = ""
    
    local inputstr = tostring(input)

    for i = 1, #inputstr do
        result = result .. inputstr:sub(i, i) .. " "
    end

    return result:sub(1, -2)
end

--------------------------------------------------------------------------------------------------------------

function padNumberWithZerosStrict(number, length)
    local str = tostring(number)
    if #str > length then
        error("Eingabe ist länger als die gewünschte Länge!")
    end
    return string.rep("0", length - #str) .. str
end

--------------------------------------------------------------------------------------------------------------
function cleanstring(str)
    local result = ""
    for i = 1, #str do
        local char = str:sub(i, i)
        if char:match("%a") or char:match("%d") then
            result = result .. char
        end
    end
    return result
end

--------------------------------------------------------------------------------------------------------------
function splitstring(input)
    local parts = {}
    local current_pos = 1

    while true do
        -- Finde den Start des nächsten Nicht-Leerzeichen-Blocks (des "Wortes")
        local start_word = string.find(input, "%S", current_pos)

        if not start_word then
            -- Keine weiteren Nicht-Leerzeichen gefunden, Ende der Zeile
            break
        end

        -- Finde das Ende des aktuellen Wortes (entweder ein Leerzeichen oder das Ende des Strings)
        local end_word = string.find(input, "%s", start_word)

        if end_word then
            -- Füge das Wort hinzu (von start_word bis end_word-1)
            table.insert(parts, string.sub(input, start_word, end_word - 1))
            current_pos = end_word + 1 -- Setze die Position nach dem Leerzeichen
        else
            -- Das ist das letzte Wort in der Zeile
            table.insert(parts, string.sub(input, start_word))
            break -- Fertig
        end
    end
    return parts
end

--------------------------------------------------------------------------------------------------------------
function TransponderPostotring(transponderposition)

    if (transponderposition == STANDBY) then
        return "Standby"
    elseif (transponderposition == ALTOFF) then
        return "Altitude Off"
    elseif (transponderposition == ALTON) then
        return "Altitude ON"
    elseif (transponderposition == TA) then
        return "T A"
    elseif (transponderposition == TARA) then
        return "T A R A"
    end
end

--------------------------------------------------------------------------------------------------------------
function formatILSFrequency(freq)
    local freqStr = tostring(freq)
    
    -- Mindestens 1 Ziffer vor dem Komma, maximal 3
    local beforeComma = freqStr:sub(1, 3)
    local afterComma = freqStr:sub(4)
    
    -- Fülle nach dem Komma auf 2 Stellen
    if #afterComma < 2 then
        afterComma = afterComma .. string.rep("0", 2 - #afterComma)
    elseif #afterComma > 2 then
        afterComma = afterComma:sub(1, 2)
    end
    
    return beforeComma .. "," .. afterComma
end

--------------------------------------------------------------------------------------------------------------
function isvalidicao(icao)
    -- Überprüfe, ob die Eingabe ein String ist und genau 4 Zeichen lang ist
    if type(icao) ~= "string" or #icao ~= 4 then
        return false
    end

    -- Überprüfe jedes Zeichen, ob es ein Großbuchstabe ist
    for i = 1, 4 do
        local char = icao:sub(i, i)  -- Extrahiere das i-te Zeichen
        if char < "A" or char > "Z" then  -- Überprüfe, ob es ein Großbuchstabe ist
            return false
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
function isvalidrwy(runway)
    -- Überprüfen, ob der Wert ein String ist
    if type(runway) ~= "string" then
        return false
    end

    -- Muster für eine gültige Runway-Bezeichnung
    local pattern = "^(%d?%d)([LRC]?)$"

    -- Überprüfen, ob der String dem Muster entspricht
    local number, suffix = runway:match(pattern)

    -- Wenn keine Zahl gefunden wurde, ist die Runway ungültig
    if not number then
        return false
    end

    -- Überprüfen, ob die Zahl zwischen 01 und 36 liegt
    local num = tonumber(number)
    if num < 1 or num > 36 then
        return false
    end

    -- Wenn alles in Ordnung ist, ist die Runway gültig
    return true
end

--------------------------------------------------------------------------------------------------------------
function adjustrwy(runway, increment)
    -- Extract the numeric part and the optional letter suffix
 
    if not isvalidrwy(runway) then
        return nil
    end

    local number, suffix = runway:match("^(%d+)(%a*)$")

    -- Convert the numeric part to a number
    number = tonumber(number)

    -- Adjust the number by the increment (default is +1)
    increment = increment or 1
    number = number + increment

    -- Handle runway number wrapping (e.g., 36 -> 1, 1 -> 36)
    if (number > 36) then
        number = number - 36
    elseif (number < 1) then
        number = number + 36
    end

    -- Format the number to two digits (e.g., 1 -> "01")
    local formatted_number = string.format("%02d", number)

    -- Combine the formatted number and suffix
    return formatted_number .. suffix
end

--------------------------------------------------------------------------------------------------------------
function formatRunwayDesignator(runwayDesignator)

    if type(runwayDesignator) ~= "string" or runwayDesignator == "" then
        return ""
    end

    local parts = {}
    
    local mapping = {
        L = "Left",
        R = "Right",
        C = "Center"
    }

    local len = string.len(runwayDesignator)


    for i = 1, len do
        local char = runwayDesignator:sub(i, i)

        if i == 3 and mapping[char] then
            table.insert(parts, mapping[char])
        else
            table.insert(parts, char)
        end
    end

    return table.concat(parts, " ")
end

--------------------------------------------------------------------------------------------------------------
function getnavdataindex(icao, rwy, navtype)

    if not (isvalidicao(icao) and isvalidrwy(rwy)) then
        return nil
    end

    local result = nil
    local navdatatableindex = icao .. rwy .. navtype
    
    if (P.navdatatable[navdatatableindex] ~= nil) then
        result = navdatatableindex
    else
        navdatatableindex = icao .. adjustrwy(rwy, 1) .. navtype
        if (P.navdatatable[navdatatableindex]  ~= nil) then
           result = navdatatableindex
        else
            navdatatableindex = icao .. adjustrwy(rwy, -1) .. navtype
            if (P.navdatatable[navdatatableindex]  ~= nil) then
               result = navdatatableindex
            else
                navdatatableindex = icao .. adjustrwy(rwy, 2) .. navtype
                if (P.navdatatable[navdatatableindex]  ~= nil) then
                   result = navdatatableindex
                else
                    navdatatableindex = icao .. adjustrwy(rwy, -2) .. navtype
                    if (P.navdatatable[navdatatableindex]  ~= nil) then
                       result = navdatatableindex
                    else
                        navdatatableindex = icao .. adjustrwy(rwy, 3) .. navtype
                        if (P.navdatatable[navdatatableindex]  ~= nil) then
                           result = navdatatableindex
                        else
                            navdatatableindex = icao .. adjustrwy(rwy, -3) .. navtype
                            if (P.navdatatable[navdatatableindex]  ~= nil) then
                               result = navdatatableindex
                            end
                        end
                    end
                end
            end
        end
    end

    return result

end

--------------------------------------------------------------------------------------------------------------
function getrwyheadingfromnavdata(icao, rwy)

    if not (isvalidicao(icao) and isvalidrwy(rwy)) then
        return nil
    end

    local result = nil
    local navdatatableindex = getnavdataindex(icao, rwy, NAVTYPEILS)

    if (navdatatableindex ~= nil) then
        result = P.navdatatable[navdatatableindex][DESTCOURSE]
    else
        navdatatableindex = getnavdataindex(icao, rwy, NAVTYPEGLS)
        if (navdatatableindex ~= nil) then
            result = P.navdatatable[navdatatableindex][DESTCOURSE]
        else
            navdatatableindex = getnavdataindex(icao, rwy, NAVTYPELPV)
            if (navdatatableindex ~= nil) then
                result = P.navdatatable[navdatatableindex][DESTCOURSE]
            end
        end
    end

    return result

end 

--------------------------------------------------------------------------------------------------------------
function getoppositerwy(runway)
    -- Extrahiere die Zahl und den optionalen Buchstaben
    local number = tonumber(runway:match("%d+"))
    local letter = runway:match("%a") or ""

    -- Berechne die entgegengesetzte Runway-Zahl
    local oppositeNumber = (number + 18) % 36
    if (oppositeNumber == 0) then
        oppositeNumber = 36
    end

    -- Füge den Buchstaben hinzu, falls vorhanden
    local oppositeRunway = string.format("%02d", oppositeNumber) .. letter

    return oppositeRunway
end

--------------------------------------------------------------------------------------------------------------
function getoppositeheading(heading)
    local oppositeHeading = (heading + 180) % 360
    return oppositeHeading
end

--------------------------------------------------------------------------------------------------------------
function getheadingdiff(heading1, heading2)
    -- Berechne die absolute Differenz
    local diff = math.abs(heading1 - heading2)
    
    -- Berücksichtige die Zirkularität der Kurse (360-Grad-Wrap)
    if (diff > 180) then
        diff = 360 - diff
    end
    
    return diff
end


--------------------------------------------------------------------------------------------------------------
function aircraftonrwy(aircraftlat, aircraftlon, rwystartlat, rwystartlon, rwyendlat, rwyendlon, dist)

    if (rwystartlat == 0) then
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
    local s = d1 * v1 + d2 * v2

    local disttorwy = math.sqrt(math.abs(d1 ^ 2 + d2 ^ 2 - 2 * s))

    if (disttorwy < dist) then
        return true
    else
        return false
    end
end

--------------------------------------------------------------------------------------------------------------

function roundnumber(num, decimalPlaces)

    decimalPlaces = decimalPlaces or 0

    local power = 10^decimalPlaces

    if num >= 0 then
        return (math.floor(num * power + 0.5) / power)
    else
        return (math.ceil(num * power - 0.5) / power)
    end
end

--------------------------------------------------------------------------------------------------------------
function headingdiff(heading1, heading2)

    local headingdifftemp = math.abs(heading1 - heading2)

    if (headingdifftemp > 180) then
        return (360 - headingdifftemp)
    else
        return (headingdifftemp)
    end
end

--------------------------------------------------------------------------------------------------------------

function convertpressure(value)

    value = tonumber(value)
    if value then
        if (value > 100) then
            local inches = value / INCHTOPAS
            return roundnumber(inches, 2)
        else
            local hpa = value * INCHTOPAS
            return roundnumber(hpa, 0)
        end
    end
end

--------------------------------------------------------------------------------------------------------------
function getlocalqnh(deparr)

    local localqnhpas = roundnumber(get(baroregionpas) / 100) -- Default from X-Plane dataref
    local localqnhinch = convertpressure(localqnhpas) -- Convert default hPa to inches (using existing convertpressure)

    -- Variable für den Altimeter-Wert aus dem METAR
    local metar_altim_in_hg_val = nil

    if (deparr == DEPARTURE) then
        if P.depmetar.metarfound and P.depmetar.metar and P.depmetar.metar.altim_in_hg then -- Check if metar and altim_in_hg exist
            metar_altim_in_hg_val = tonumber(P.depmetar.metar.altim_in_hg)
        end
    elseif (deparr == ARRIVAL) then
        if P.desmetar.metarfound and P.desmetar.metar and P.desmetar.metar.altim_in_hg then -- Check if metar and altim_in_hg exist
            metar_altim_in_hg_val = tonumber(P.desmetar.metar.altim_in_hg)
        end
    end

    -- Wenn ein gültiger Wert aus dem METAR gefunden wurde, diesen verwenden
    if metar_altim_in_hg_val ~= nil then
        localqnhinch = metar_altim_in_hg_val -- Der Wert ist bereits in inHg
        localqnhpas = convertpressure(localqnhinch) -- Diesmal von inHg zu hPa konvertieren
    end

    sasl.logDebug("GETLOCALQNH: INCH " .. tostring(localqnhinch) .. " PAS " .. tostring(localqnhpas))

    return localqnhinch, localqnhpas
end

--------------------------------------------------------------------------------------------------------------
function convflaplevertoflappos(flaplever)

    local returnvalue = 0

    if (flaplever == FLAPSUP) then
        returnvalue = 0
    elseif (flaplever == FLAPS1) then
        returnvalue = 1
    elseif (flaplever == FLAPS2) then
        returnvalue = 2
    elseif (flaplever == FLAPS5) then
        returnvalue = 5
    elseif (flaplever == FLAPS10) then
        returnvalue = 10
    elseif (flaplever == FLAPS15) then
        returnvalue = 15
    elseif (flaplever == FLAPS25) then
        returnvalue = 25
    elseif (flaplever == FLAPS30) then
        returnvalue = 30
    elseif (flaplever == FLAPS40) then
        returnvalue = 40
    end

    return (returnvalue)

end

--------------------------------------------------------------------------------------------------------------
function getbankanglestring(bankangle)

    local bankanglestring = ""

    if (bankangle == BANKANGLEMIN) then
        bankanglestring = "Minimum"
    elseif (bankangle == BANKANGLE15) then
        bankanglestring = "15"
    elseif (bankangle == BANKANGLE20) then
        bankanglestring = "20"
    elseif (bankangle == BANKANGLE25) then
        bankanglestring = "25"
    elseif (bankangle == BANKANGLEMAX) then
        bankanglestring = "Maximum"
    end

    return bankanglestring
end

--------------------------------------------------------------------------------------------------------------
function P.commandtableentry(state, text)

    local index = 1
    local duplicateentryfound = false

    if (state ~= COMMAND) then
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

function togglesimfreeze()

    if (get(simfreezed) == OFF) then
        set(simfreezed, ON)
    else
        set(simfreezed, OFF)
    end

end

function togglesimfreeze_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglesimfreeze()
    end
    return 0
end

my_command_togglesimfreeze = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglesimfreeze", "Toggle Freeze Sim")
sasl.registerCommandHandler(my_command_togglesimfreeze, 0, togglesimfreeze_)

--------------------------------------------------------------------------------------------------------------

function mastercaution()

    if (((P.procedureloop1.lock ~= NOPROCEDURE) or (P.procedureloop2.lock ~= NOPROCEDURE)) and (get(mastercautionannunc) ~= ON)) then
        P.procedureskipstep = true
    end

    helpers.command_once("laminar/B738/push_button/master_caution1")
    helpers.command_once("laminar/B738/button/fmc1_clr")
    helpers.command_once("laminar/B738/button/fmc2_clr")
    helpers.command_once("laminar/B738/alert/alt_horn_cutout")
    helpers.command_once("laminar/B738/push_button/ap_light_pilot")
    helpers.command_once("laminar/B738/push_button/at_light_pilot")
    helpers.command_once("laminar/B738/push_button/fms_light_pilot")

end

function mastercaution_(phase)
    if phase == SASL_COMMAND_BEGIN then
        mastercaution()
    end
    return 0
end

my_command_mastercaution = sasl.createCommand(definitions.APPNAMEPREFIX .. "/mastercaution", "Master Caution + FMS CLR")
sasl.registerCommandHandler(my_command_mastercaution, 0, mastercaution_)

--------------------------------------------------------------------------------------------------------------

function headingsync()

    set(mcpheading, roundnumber(get(groundtrackmag)))

end

function headingsync_(phase)
    if phase == SASL_COMMAND_BEGIN then
        headingsync()
    end
    return 0
end

my_command_headingsync = sasl.createCommand(definitions.APPNAMEPREFIX .. "/headingsync", "Sync AP Heading with Ground Track")
sasl.registerCommandHandler(my_command_headingsync, 0, headingsync_)

--------------------------------------------------------------------------------------------------------------

function wipersup()

    helpers.command_once("laminar/B738/knob/left_wiper_up")
    helpers.command_once("laminar/B738/knob/right_wiper_up")

end

function wipersup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        wipersup()
    end
    return 0
end

my_command_wipersup = sasl.createCommand(definitions.APPNAMEPREFIX .. "/wipersup", "Both Wipers Up")
sasl.registerCommandHandler(my_command_wipersup, 0, wipersup_)

--------------------------------------------------------------------------------------------------------------

function wipersdown()

    helpers.command_once("laminar/B738/knob/left_wiper_dn")
    helpers.command_once("laminar/B738/knob/right_wiper_dn")

end

function wipersdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        wipersdown()
    end
    return 0
end

my_command_wipersdown = sasl.createCommand(definitions.APPNAMEPREFIX .. "/wipersdownn", "Both Wipers Down")
sasl.registerCommandHandler(my_command_wipersdown, 0, wipersdown_)

--------------------------------------------------------------------------------------------------------------

function toggletaxilights(state)

    if (state == nil) then
        if (get(taxilight) == OFF) then
            helpers.command_once("laminar/B738/toggle_switch/taxi_light_brigh_toggle")
        elseif (get(taxilight) == 2) then
            helpers.command_once("laminar/B738/toggle_switch/taxi_light_brigh_toggle")
        end
    elseif ((state == OFF) and (get(taxilight) ~= OFF)) then
        helpers.command_once("laminar/B738/toggle_switch/taxi_light_brigh_toggle")
    elseif ((state == ON) and (get(taxilight) == OFF)) then
        helpers.command_once("laminar/B738/toggle_switch/taxi_light_brigh_toggle")
    end

end

function toggletaxilights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        toggletaxilights(nil)
    end
    return 0
end

my_command_toggletaxilights = sasl.createCommand(definitions.APPNAMEPREFIX .. "/toggletaxilights", "Toggle Taxi Lights")
sasl.registerCommandHandler(my_command_toggletaxilights, 0, toggletaxilights_)

--------------------------------------------------------------------------------------------------------------

function togglecollisionlights(state)

    if (state == nil) then
        if (get(beaconlights) == OFF) then
            set(beaconlights, ON)
        elseif (get(beaconlights) == ON) then
            set(beaconlights, OFF)
        end
    elseif ((state == OFF) and (get(beaconlights) ~= OFF)) then
        set(beaconlights, OFF)
    elseif ((state == ON) and (get(beaconlights) ~= ON)) then
        set(beaconlights, ON)
    end

end

function togglecollisionlights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglecollisionlights(nil)
    end
    return 0
end

my_command_togglecollisionlights = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglecollisionlights", "Toggle Collision Lights")
sasl.registerCommandHandler(my_command_togglecollisionlights, 0, togglecollisionlights_)

--------------------------------------------------------------------------------------------------------------

function togglelandinglights(state)
    if (state == nil) then
        if (get(llightson) == OFF) then
            if ((get(llights1) ~= OFF) or (get(llights2) ~= OFF) or (get(llights3) ~= OFF) or (get(llights4) ~= OFF)) then
                helpers.command_once("sim/lights/landing_lights_off")
            else
                helpers.command_once("sim/lights/landing_lights_on")
            end
        else
            helpers.command_once("sim/lights/landing_lights_off")
        end
    elseif (state == OFF) then
        helpers.command_once("sim/lights/landing_lights_off")
    elseif (state == ON) then
        helpers.command_once("sim/lights/landing_lights_on")
    end

end

function togglelandinglights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglelandinglights(nil)
    end
    return 0
end

my_command_togglelandinglights = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglelandinglights", "Toggle Landing Lights")
sasl.registerCommandHandler(my_command_togglelandinglights, 0, togglelandinglights_)
--------------------------------------------------------------------------------------------------------------

function togglelogolight(state)

    if (state == nil) then
        if (get(logolighton) == OFF) then
            helpers.command_once("laminar/B738/switch/logo_light_on")
        else
            helpers.command_once("laminar/B738/switch/logo_light_off")
        end
    elseif ((state == OFF) and (get(logolighton) ~= OFF)) then
        helpers.command_once("laminar/B738/switch/logo_light_off")
    elseif ((state == ON) and (get(logolighton) ~= ON)) then
        helpers.command_once("laminar/B738/switch/logo_light_on")
    end

end

function togglelogolight_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglelogolight(nil)
    end
    return 0
end

my_command_togglelogolight = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglelogolight", "Toggle Logo Light")
sasl.registerCommandHandler(my_command_togglelogolight, 0, togglelogolight_)

--------------------------------------------------------------------------------------------------------------

function togglerwylights(state)

    if (state == nil) then
        if (get(rwylightl) == ON) then
            set(rwylightl, OFF)
        else
            set(rwylightl, ON)
        end
        if (get(rwylightr) == ON) then
            set(rwylightr, OFF)
        else
            set(rwylightr, ON)
        end
    elseif (state == OFF) then
        if (get(rwylightl) == ON) then
            set(rwylightl, OFF)
        end
        if (get(rwylightr) == ON) then
            set(rwylightr, OFF)
        end
    elseif (state == ON) then
        if (get(rwylightl) == OFF) then
            set(rwylightl, ON)
        end
        if (get(rwylightr) == OFF) then
            set(rwylightr, ON)
        end
    end
end

function togglerwylights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglerwylights(nil)
    end
    return 0
end

my_command_togglerwylights = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglerwylights", "Toggle Runway Turnoff Lights")
sasl.registerCommandHandler(my_command_togglerwylights, 0, togglerwylights_)

--------------------------------------------------------------------------------------------------------------

function togglepositionlights(state)

    if (state == nil) then
        if (get(positionlights) == POSLIGHTSSTEADY) then
            helpers.command_once("laminar/B738/toggle_switch/position_light_strobe")
        else
            helpers.command_once("laminar/B738/toggle_switch/position_light_steady")
        end
    elseif ((state == POSLIGHTSSTEADY) and (get(positionlights) ~= POSLIGHTSSTEADY)) then
        helpers.command_once("laminar/B738/toggle_switch/position_light_steady")
    elseif ((state == POSLIGHTSSTROBE) and (get(positionlights) ~= POSLIGHTSSTROBE)) then
        helpers.command_once("laminar/B738/toggle_switch/position_light_strobe")
    elseif ((state == POSLIGHTSOFF) and (get(positionlights) ~= POSLIGHTSOFF)) then
        helpers.command_once("laminar/B738/toggle_switch/position_light_off")
    end

end

function togglepositionlights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglepositionlights(nil)
    end
    return 0
end

my_command_togglerwylights = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglepositionlights", "Toggle Position Lights")
sasl.registerCommandHandler(my_command_togglerwylights, 0, togglepositionlights_)

--------------------------------------------------------------------------------------------------------------

function toggletransponder(state)

    if (state == nil) then
        if (get(transponderpos) == STANDBY) then
            helpers.command_once("laminar/B738/knob/transponder_tara")
        else
            helpers.command_once("laminar/B738/knob/transponder_stby")
        end
    else
        if ((state == STANDBY) and (get(transponderpos) ~= STANDBY)) then
            helpers.command_once("laminar/B738/knob/transponder_stby")
        elseif ((state == TARA) and (get(transponderpos) ~= TARA)) then
            helpers.command_once("laminar/B738/knob/transponder_tara")
        else
        end
    end

end

function toggletransponder_(phase)
    if phase == SASL_COMMAND_BEGIN then
        toggletransponder(nil)
    end
    return 0
end

my_command_toggletransponder = sasl.createCommand(definitions.APPNAMEPREFIX .. "/toggletransponder", "Toggle Transponder Stdby TA/RA")
sasl.registerCommandHandler(my_command_toggletransponder, 0, toggletransponder_)

--------------------------------------------------------------------------------------------------------------

function togglefds(state)

    if (state == nil) then
        if (get(fdpilotpos) == OFF) then
            helpers.command_once("laminar/B738/autopilot/flight_director_toggle")
            if (get(fdfopos) == OFF) then
                helpers.command_once("laminar/B738/autopilot/flight_director_fo_toggle")
            end
        else
            helpers.command_once("laminar/B738/autopilot/flight_director_toggle")
            if (get(fdfopos) == ON) then
                helpers.command_once("laminar/B738/autopilot/flight_director_fo_toggle")
            end
        end

    elseif (state == OFF) then
        if (get(fdpilotpos) == ON) then
            helpers.command_once("laminar/B738/autopilot/flight_director_toggle")
        end
        if (get(fdfopos) == ON) then
            helpers.command_once("laminar/B738/autopilot/flight_director_fo_toggle")
        end
    elseif (state == ON) then
        if (get(fdpilotpos) == OFF) then
            helpers.command_once("laminar/B738/autopilot/flight_director_toggle")
        end
        if (get(fdfopos) == OFF) then
            helpers.command_once("laminar/B738/autopilot/flight_director_fo_toggle")
        end
    end
end

function togglefds_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglefds(nil)
    end
    return 0
end

my_command_togglefds = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglefds", "Toggle Both Flight Directors")
sasl.registerCommandHandler(my_command_togglefds, 0, togglefds_)

--------------------------------------------------------------------------------------------------------------

function togglewx(state)

    if (state == nil) then
        if (get(efiswxpilotpos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/wxr_press")
            if (get(efiswxfopos) == OFF) then
                helpers.command_once("laminar/B738/EFIS_control/fo/push_button/wxr_press")
            end
        else
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/wxr_press")
            if (get(efiswxfopos) == ON) then
                helpers.command_once("laminar/B738/EFIS_control/fo/push_button/wxr_press")
            end
        end

    elseif (state == OFF) then
        if (get(efiswxpilotpos) == ON) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/wxr_press")
        end
        if (get(efiswxfopos) == ON) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/wxr_press")
        end
    elseif (state == ON) then
        if (get(efiswxpilotpos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/wxr_press")
        end
        if (get(efiswxfopos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/wxr_press")
        end
    end
end

function togglewx_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglewx(nil)
    end
    return 0
end

my_command_togglewx = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglewx", "Toggle Both Weather Radars")
sasl.registerCommandHandler(my_command_togglewx, 0, togglewx_)

--------------------------------------------------------------------------------------------------------------

function toggleterr(state)

    if (state == nil) then
        if (get(efisterrpilotpos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/terr_press")
            if (get(efisterrfopos) == OFF) then
                helpers.command_once("laminar/B738/EFIS_control/fo/push_button/terr_press")
            end
        else
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/terr_press")
            if (get(efisterrfopos) == ON) then
                helpers.command_once("laminar/B738/EFIS_control/fo/push_button/terr_press")
            end
        end

    elseif (state == OFF) then
        if (get(efisterrpilotpos) == ON) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/terr_press")
        end
        if (get(efisterrfopos) == ON) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/terr_press")
        end
    elseif (state == ON) then
        if (get(efisterrpilotpos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/terr_press")
        end
        if (get(efisterrfopos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/terr_press")
        end
    end
end

function toggleterr_(phase)
    if phase == SASL_COMMAND_BEGIN then
        toggleterr(nil)
    end
    return 0
end

my_command_toggleterr = sasl.createCommand(definitions.APPNAMEPREFIX .. "/toggleterr", "Toggle Both Terrain Radars")
sasl.registerCommandHandler(my_command_toggleterr, 0, toggleterr_)

--------------------------------------------------------------------------------------------------------------

function togglewindowheat(state)

    if (state == nil) then
        if (get(wheatlfwdpos) == ON) then
            set(wheatlfwdpos, OFF)
            set(wheatrfwdpos, OFF)
            set(wheatlsidepos, OFF)
            set(wheatrsidepos, OFF)
        else
            set(wheatlfwdpos, ON)
            set(wheatrfwdpos, ON)
            set(wheatlsidepos, ON)
            set(wheatrsidepos, ON)
        end
    elseif ((state == ON) and (get(wheatlfwdpos) == OFF)) then
        set(wheatlfwdpos, ON)
        set(wheatrfwdpos, ON)
        set(wheatlsidepos, ON)
        set(wheatrsidepos, ON)
    elseif ((state == OFF) and (get(wheatlfwdpos) == ON)) then
        set(wheatlfwdpos, OFF)
        set(wheatrfwdpos, OFF)
        set(wheatlsidepos, OFF)
        set(wheatrsidepos, OFF)
    end

    return true
end

function togglewindowheat_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglewindowheat(nil)
    end
    return 0
end

my_command_togglewindowheat = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglewindowheat", "Toggle Window Heat")
sasl.registerCommandHandler(my_command_togglewindowheat, 0, togglewindowheat_)

--------------------------------------------------------------------------------------------------------------

function toggleprobeheat(state)

    if (state == nil) then
        if (get(captainprobepos) == ON) then
            set(captainprobepos, OFF)
            set(foprobepos, OFF)
        else
            set(captainprobepos, ON)
            set(foprobepos, ON)
        end
    elseif ((state == ON) and (get(captainprobepos) == OFF)) then
        set(captainprobepos, ON)
        set(foprobepos, ON)
    elseif ((state == OFF) and (get(captainprobepos) == ON)) then
        set(captainprobepos, OFF)
        set(foprobepos, OFF)
    end

    return true
end

function toggleprobeheat_(phase)
    if phase == SASL_COMMAND_BEGIN then
        toggleprobeheat(nil)
    end
    return 0
end

my_command_toggleprobeheat = sasl.createCommand(definitions.APPNAMEPREFIX .. "/toggleprobeheat", "Toggle Probe Heat")
sasl.registerCommandHandler(my_command_toggleprobeheat, 0, toggleprobeheat_)

--------------------------------------------------------------------------------------------------------------

function iceprotection(state)

    local set = 0

    if (state == nil) then
        if (get(eng1heatpos) == OFF) then
            set = 1
            helpers.command_once("laminar/B738/toggle_switch/eng1_heat")
            if (get(eng2heatpos) == OFF) then
                helpers.command_once("laminar/B738/toggle_switch/eng2_heat")
            end
            if (get(wingheatpos) == OFF) then
                helpers.command_once("laminar/B738/toggle_switch/wing_heat")
            end
        else
            set = 2
            helpers.command_once("laminar/B738/toggle_switch/eng1_heat")
            if (get(eng2heatpos) == ON) then
                helpers.command_once("laminar/B738/toggle_switch/eng2_heat")
            end
            if (get(wingheatpos) == ON) then
                helpers.command_once("laminar/B738/toggle_switch/wing_heat")
            end
        end
    elseif (state == ON) then
        if (get(eng1heatpos) == OFF) then
            set = 1
            helpers.command_once("laminar/B738/toggle_switch/eng1_heat")
        end

        if (get(eng2heatpos) == OFF) then
            set = 1
            helpers.command_once("laminar/B738/toggle_switch/eng2_heat")
        end

        if (get(wingheatpos) == OFF) then
            set = 1
            helpers.command_once("laminar/B738/toggle_switch/wing_heat")
        end
    elseif (state == OFF) then
        if (get(eng1heatpos) == ON) then
            set = 2
            helpers.command_once("laminar/B738/toggle_switch/eng1_heat")
        end

        if (get(eng2heatpos) == ON) then
            set = 2
            helpers.command_once("laminar/B738/toggle_switch/eng2_heat")
        end

        if (get(wingheatpos) == ON) then
            set = 2
            helpers.command_once("laminar/B738/toggle_switch/wing_heat")
        end
    end

    if (set == 1) then
        P.commandtableentry(TEXT, "Wing and Engine Anti Ice ON")
    elseif (set == 2) then
        P.commandtableentry(TEXT, "Wing and Engine Anti Ice OFF")
    end

    return true

end

function iceprotection_(phase)
    if phase == SASL_COMMAND_BEGIN then
        iceprotection(nil)
    end
    return 0
end

my_command_iceprotection = sasl.createCommand(definitions.APPNAMEPREFIX .. "/iceprotection", "Toggle Ice Protection")
sasl.registerCommandHandler(my_command_iceprotection, 0, iceprotection_)

--------------------------------------------------------------------------------------------------------------

function toggleautofunctions()

    if (P.configvalues[CONFIGAUTOFUNCTIONS] == ON) then
        P.configvalues[CONFIGAUTOFUNCTIONS] = OFF
        P.commandtableentry(TEXT, "Auto Functions Off")
    else
        P.configvalues[CONFIGAUTOFUNCTIONS] = ON
        P.commandtableentry(TEXT, "Auto Functions On")
    end

    return true

end

function toggleautofunctions_(phase)
    if phase == SASL_COMMAND_BEGIN then
        toggleautofunctions()
    end
    return 0
end

my_command_toggleautofunctions = sasl.createCommand(definitions.APPNAMEPREFIX .. "/toggleautofunctions", "Toggle Auto Functions")
sasl.registerCommandHandler(my_command_toggleautofunctions, 0, toggleautofunctions_)

--------------------------------------------------------------------------------------------------------------

function toggleviewchanges()

    if (P.configvalues[CONFIGVIEWCHANGES] == ON) then
        P.configvalues[CONFIGVIEWCHANGES] = OFF
        P.commandtableentry(TEXT, "View Changes Off")
    else
        P.configvalues[CONFIGVIEWCHANGES] = ON
        P.commandtableentry(TEXT, "View Changes On")
    end

    return true

end

function toggleviewchanges_(phase)
    if phase == SASL_COMMAND_BEGIN then
        toggleviewchanges()
    end
    return 0
end

my_command_toggleviewchanges = sasl.createCommand(definitions.APPNAMEPREFIX .. "/toggleviewchanges", "Toggle View Changes")
sasl.registerCommandHandler(my_command_toggleviewchanges, 0, toggleviewchanges_)

 --------------------------------------------------------------------------------------------------------------

function setcockpitlights()

    local lightset = false

    if (get(brightmainpanel) ~= P.configvalues[CONFIGBRIGHTMAINPANEL]) then
        set(brightmainpanel, P.configvalues[CONFIGBRIGHTMAINPANEL])
        lightset = true
    end
    if (get(brightcopilotmainpanel) ~= P.configvalues[CONFIGBRIGHTMAINPANEL]) then
        set(brightcopilotmainpanel, P.configvalues[CONFIGBRIGHTMAINPANEL])
        lightset = true
    end
    if (get(brightoverhead) ~= P.configvalues[CONFIGBRIGHTOVERHEAD]) then
        set(brightoverhead, P.configvalues[CONFIGBRIGHTOVERHEAD])
        lightset = true
    end
    if (get(brightpedestral) ~= P.configvalues[CONFIGBRIGHTPEDESTRAL]) then
        set(brightpedestral, P.configvalues[CONFIGBRIGHTPEDESTRAL])
    end
    if (get(genbrightbackground) ~= P.configvalues[CONFIGGENBRIGHTBACKGROUND]) then
        set(genbrightbackground, P.configvalues[CONFIGGENBRIGHTBACKGROUND])
        lightset = true
    end
    if (get(genbrightafdsflood) ~= P.configvalues[CONFIGGENBRIGHTAFDSFLOOD]) then
        set(genbrightafdsflood, P.configvalues[CONFIGGENBRIGHTAFDSFLOOD])
        lightset = true
    end
    if (get(genbrightpedestralflood) ~= P.configvalues[CONFDIGGENBRIGHTPEDESTRALFLOOD]) then
        set(genbrightpedestralflood, P.configvalues[CONFDIGGENBRIGHTPEDESTRALFLOOD])
        lightset = true
    end
    if (get(instrbrightoutbddu) ~= P.configvalues[CONFIGINSTRBRIGHTOUTBDDU]) then
        set(instrbrightoutbddu, P.configvalues[CONFIGINSTRBRIGHTOUTBDDU])
        lightset = true
    end
    if (get(instrbrightcopilotoutbddu) ~= P.configvalues[CONFIGINSTRBRIGHTOUTBDDU]) then
        set(instrbrightcopilotoutbddu, P.configvalues[CONFIGINSTRBRIGHTOUTBDDU])
        lightset = true
    end
    if (get(instrbrightinbddu) ~= P.configvalues[CONFIGINSTRBRIGHTINBDDU]) then
        set(instrbrightinbddu, P.configvalues[CONFIGINSTRBRIGHTINBDDU])
        lightset = true
    end
    if (get(instrbrightcopilotinbddu) ~= P.configvalues[CONFIGINSTRBRIGHTINBDDU]) then
        set(instrbrightcopilotinbddu, P.configvalues[CONFIGINSTRBRIGHTINBDDU])
        lightset = true
    end
    if (get(instrbrightupperdu) ~= P.configvalues[CONFIGINSTRBRIGHTUPPERDU]) then
        set(instrbrightupperdu, P.configvalues[CONFIGINSTRBRIGHTUPPERDU])
        lightset = true
    end
    if (get(instrbrightlowdu) ~= P.configvalues[CONFIGINSTRBRIGHTLOWDU]) then
        set(instrbrightlowdu, P.configvalues[CONFIGINSTRBRIGHTLOWDU])
        lightset = true
    end
    if (get(instrbrightinbdduS) ~= P.configvalues[CONFIGINSTRBRIGHTINBDDUS]) then
        set(instrbrightinbdduS, P.configvalues[CONFIGINSTRBRIGHTINBDDUS])
        lightset = true
    end
    if (get(instrbrightcopilotinbdduS) ~= P.configvalues[CONFIGINSTRBRIGHTINBDDUS]) then
        set(instrbrightcopilotinbdduS, P.configvalues[CONFIGINSTRBRIGHTINBDDUS])
        lightset = true
    end
    if (get(instrbrightlowduS) ~= P.configvalues[CONFIGINSTRBRIGHTLOWDUS]) then
        set(instrbrightlowduS, P.configvalues[CONFIGINSTRBRIGHTLOWDUS])
        lightset = true
    end

    return lightset

end

function setcockpitlights_(phase)
    if phase == SASL_COMMAND_BEGIN then
        setcockpitlights()
    end
    return 0
end

my_command_setcockpitlights = sasl.createCommand(definitions.APPNAMEPREFIX .. "/setcockpitlights", "Set Cockpit Lights")
sasl.registerCommandHandler(my_command_setcockpitlights, 0, setcockpitlights_)


--------------------------------------------------------------------------------------------------------------

function togglevoicereadback()

    if (P.configvalues[CONFIGVOICEREADBACK] == ON) then
        P.configvalues[CONFIGVOICEREADBACK] = OFF
    else
        P.configvalues[CONFIGVOICEREADBACK] = ON
        P.commandtableentry(TEXT, "Voice Read back On")
    end

    return true

end

function togglevoicereadback_(phase)
    if phase == SASL_COMMAND_BEGIN then
        togglevoicereadback()
    end
    return 0
end

my_command_togglevoicereadback = sasl.createCommand(definitions.APPNAMEPREFIX .. "/togglevoicereadback", "Toggle Voice Readback")
sasl.registerCommandHandler(my_command_togglevoicereadback, 0, togglevoicereadback_)

--------------------------------------------------------------------------------------------------------------

function toggleadviceonly()

    if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
        P.configvalues[CONFIGVOICEADVICEONLY] = OFF
        P.commandtableentry(ADVICE, "Advice Only Off")
    else
        P.configvalues[CONFIGVOICEADVICEONLY] = ON
        P.commandtableentry(ADVICE, "Advice Only On")
    end

    return true

end

function toggleadviceonly_(phase)
    if phase == SASL_COMMAND_BEGIN then
        toggleadviceonly()
    end
    return 0
end

my_command_toggleadviceonly = sasl.createCommand(definitions.APPNAMEPREFIX .. "/toggleadviceonly", "Toggle Advice Only")
sasl.registerCommandHandler(my_command_toggleadviceonly, 0, toggleadviceonly_)

--------------------------------------------------------------------------------------------------------------

function abortprocedure()

    if ((P.procedureloop1.lock ~= NOPROCEDURE) or (P.procedureloop2.lock ~= NOPROCEDURE)) then

        P.procedureabort = true

    end

    return true

end

function abortprocedure_(phase)
    if phase == SASL_COMMAND_BEGIN then
        abortprocedure()
    end
    return 0
end

my_command_abortprocedure = sasl.createCommand(definitions.APPNAMEPREFIX .. "/abortprocedure", "Abort Procedure")
sasl.registerCommandHandler(my_command_abortprocedure, 0, abortprocedure_)

--------------------------------------------------------------------------------------------------------------

function skipprocedurestep()

    if ((P.procedureloop1.lock ~= NOPROCEDURE) or (P.procedureloop2.lock ~= NOPROCEDURE)) then

        P.procedureskipstep = true

    end

    return true

end

function skipprocedurestep_(phase)
    if phase == SASL_COMMAND_BEGIN then
        skipprocedurestep()
    end
    return 0
end

my_command_skipprocedurestep = sasl.createCommand(definitions.APPNAMEPREFIX .. "/skipprocedurestep", "Skip Procedure Step")
sasl.registerCommandHandler(my_command_skipprocedurestep, 0, skipprocedurestep_)


--------------------------------------------------------------------------------------------------------------

function flapsuphandling()

    if ((get(airspeed) > get(flaps15speed)) and (get(airspeed) <= get(flaps10speed)) and (get(flapleverpos) > FLAPS15)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 15")
        else
            helpers.command_once("laminar/B738/push_button/flaps_15")
        end
    elseif ((get(airspeed) > get(flaps10speed)) and (get(airspeed) <= get(flaps5speed)) and (get(flapleverpos) > FLAPS10)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 10")
        else
            helpers.command_once("laminar/B738/push_button/flaps_10")
        end
    elseif ((get(airspeed) > get(flaps5speed)) and (get(airspeed) <= get(flaps1speed)) and (get(flapleverpos) > FLAPS5)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 5")
        else
            helpers.command_once("laminar/B738/push_button/flaps_5")
      end
    elseif ((get(airspeed) > get(flaps1speed)) and (get(airspeed) <= get(flapsupspeed)) and (get(flapleverpos) > FLAPS1)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 1")
        else
            helpers.command_once("laminar/B738/push_button/flaps_1")
        end
    elseif ((get(airspeed) > get(flapsupspeed)) and (get(flapleverpos) > FLAPSUP)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps Up")
        else
            helpers.command_once("laminar/B738/push_button/flaps_0")
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function flapsdownhandling()

    if ((get(airspeed) < get(flapsupspeed)) and (get(airspeed) >= get(flaps1speed)) and (get(flapleverpos) < FLAPS1)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 1")
        else
            helpers.command_once("laminar/B738/push_button/flaps_1")
        end
    elseif ((get(airspeed) < get(flaps1speed)) and (get(airspeed) >= get(flaps5speed)) and (get(flapleverpos) < FLAPS5)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 5")
        else
            helpers.command_once("laminar/B738/push_button/flaps_5")
        end
    elseif ((get(airspeed) < get(flaps5speed)) and (get(airspeed) >= get(flaps10speed)) and (get(flapleverpos) < FLAPS10)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 10")
        else
            helpers.command_once("laminar/B738/push_button/flaps_10")
        end
    elseif ((get(airspeed) < get(flaps10speed)) and (get(airspeed) >= get(flaps15speed)) and (get(flapleverpos) < FLAPS15)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 15")
        else
            helpers.command_once("laminar/B738/push_button/flaps_15")
        end
    elseif ((get(airspeed) < get(flaps15speed)) and (get(airspeed) >= get(flaps25speed)) and (get(flapleverpos) < FLAPS25)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 25")
        else
            helpers.command_once("laminar/B738/push_button/flaps_25")
        end
    elseif ((get(airspeed) < get(flaps25speed)) and (get(flapleverpos) < FLAPS30)) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Set Flaps 30")
        else
            helpers.command_once("laminar/B738/push_button/flaps_30")
        end
    end
 
    return true

end

--------------------------------------------------------------------------------------------------------------

function setmmrils(mmr, freq)

    local ilsfreq = tostring(freq)

    if (get(mmrinstalled) == OFF) then
        return false
    end

    setmmrmode(mmr, MMRILS)

    if ((mmr == MMRBOTH) or (mmr == MMRCAPTAIN)) then
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 1, 1))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 2, 2))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 3, 3))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 4, 4))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 5, 5))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_act_stby")
    end

    if ((mmr == MMRBOTH) or (mmr == MMRFO)) then
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 1, 1))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 2, 2))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 3, 3))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 4, 4))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 5, 5))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_act_stby")
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function setmmrgls(mmr, freq)

    local glsfreq = tostring(freq)

    if (get(mmrinstalled) == OFF) then
        return false
    end

    setmmrmode(mmr, MMRGLS)

    if ((mmr == MMRBOTH) or (mmr == MMRCAPTAIN)) then
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 1, 1))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 2, 2))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 3, 3))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 4, 4))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 5, 5))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_act_stby")
    end

    if ((mmr == MMRBOTH) or (mmr == MMRFO)) then
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 1, 1))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 2, 2))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 3, 3))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 4, 4))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 5, 5))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_act_stby")
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function copynav()

    local setnav = false

    if (get(mcppilotcourse) ~= get(mcpcopilotcourse)) then
        set(mcpcopilotcourse, get(mcppilotcourse))
        setnav = true
    end

    if (get(mmrinstalled) == OFF) then
        if (get(nav1freq) ~= get(nav2freq)) then
            set(nav2freq, get(nav1freq))
            setnav = true
        end
    elseif (get(mmrcptactvalue) ~= get(mmrfoactvalue)) then
        if (get(mmrcptactmode) ~= get(mmrfostdbymode)) then
            setmmrmode(MMRFO, get(mmrcptactmode))
        end

        local mmrvalue = tostring(get(mmrcptactvalue))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 1, 1))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 2, 2))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 3, 3))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 4, 4))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 5, 5))
        P.commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_act_stby")

        setnav = true
    end

    if setnav then
        P.commandtableentry(TEXT, "NAV 1 copied to NAV 2")
    else
        P.commandtableentry(TEXT, "NAV 1 and NAV 2 already aligned")
    end

    return true

end

function copynav_(phase)
    if phase == SASL_COMMAND_BEGIN then
        copynav()
    end
    return 0
end

my_command_copynav = sasl.createCommand(definitions.APPNAMEPREFIX .. "/copynav", "Copy NAV1/MMR1 to NAV2/MMR2")
sasl.registerCommandHandler(my_command_copynav, 0, copynav_)

--------------------------------------------------------------------------------------------------------------

function setilssteps()

    local FMC1Line00L = helpers.get("laminar/B738/fmc1/Line00_L")
    local FMC1Line04X = helpers.get("laminar/B738/fmc1/Line04_X")
    local FMC1Line04L = helpers.get("laminar/B738/fmc1/Line04_L")


    if (P.procedureloop3.stepindex == 1) then
        setview(CONFIGVIEWFMS)
    elseif (P.procedureloop3.stepindex == 2) then
        if ((string.len(FMC1Line00L) < 9) or (string.sub(FMC1Line00L, 7, 9) ~= "APP")) then
            helpers.command_once("laminar/B738/button/fmc1_init_ref")
            P.procedureloop3.stepindex = P.procedureloop3.stepindex - 1
        else
            if ((string.len(FMC1Line04X) == 24) and (string.len(FMC1Line04L) == 24)) then
                apptype = string.sub(FMC1Line04X, 2, 4)

                P.navdatatableindex = 0

                if ((apptype == NAVTYPEILS) or (apptype == NAVTYPEGLS)) then
                    P.navdatatableindex = getnavdataindex(get(desicao), get(desrwy), apptype)
                else
                    P.navdatatableindex = getnavdataindex(get(desicao), get(desrwy), NAVTYPELPV)
                end

                if (P.navdatatable[P.navdatatableindex] ~= nil) then
                    if (get(desrwy) ~= P.navdatatable[P.navdatatableindex][DESTRWY]) then
                        sasl.logInfo("Destination Runway Diff FMC: " .. tostring(get(desrwy)) .. " Navdata: " .. totring(P.navdatatable[P.navdatatableindex][DESTRWY]))
                    end

                    if ((P.navdatatable[P.navdatatableindex][DESTNAVTYPE] == NAVTYPEILS) and P.navdatatable[P.navdatatableindex][DESTNAVDME]) then
                        dmestring = "with DME"
                    else
                        dmestring = ""
                    end
                    if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        P.commandtableentry(ADVICE, "Runway " .. formatRunwayDesignator(P.navdatatable[P.navdatatableindex][DESTRWY]) .. " has " .. addspaces(P.navdatatable[P.navdatatableindex][DESTNAVTYPE]) .. " Approach " .. dmestring)
                    else
                        P.commandtableentry(TEXT, "Runway " .. formatRunwayDesignator(P.navdatatable[P.navdatatableindex][DESTRWY]) .. " has " .. addspaces(P.navdatatable[P.navdatatableindex][DESTNAVTYPE]) .. " Approach " .. dmestring)
                    end
                else               
                    if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        P.commandtableentry(ADVICE, "Runway " .. formatRunwayDesignator(get(desrwy)) .. " has no Approach")
                    else
                        P.commandtableentry(TEXT, "Runway " .. formatRunwayDesignator(get(desrwy)) .. " has no Approach")
                    end
                    setview(CONFIGVIEWMAINPANEL)
                    P.procedureloop3.stepindex = 8
                end
            end
        end
    elseif (P.procedureloop3.stepindex == 3) then
        setview(CONFIGVIEWPEDESTAL)
    elseif (P.procedureloop3.stepindex == 4) then
        if (P.navdatatable[P.navdatatableindex][DESTNAVTYPE] == NAVTYPEILS) then
            if ((P.navdatatable[P.navdatatableindex][DESTFREQ] ~= get(nav1freq)) or ((get(mmrinstalled) == ON) and ((get(mmrcptactvalue) ~= P.navdatatable[P.navdatatableindex][DESTFREQ]) or (get(mmrcptactmode) ~= MMRILS)))) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Frequency " .. addspaces(formatILSFrequency(P.navdatatable[P.navdatatableindex][DESTFREQ])))
                    P.procedureloop3.stepindex = P.procedureloop3.stepindex - 1
                else
                    if (get(mmrinstalled) == ON) then
                        setmmrils(MMRCAPTAIN, P.navdatatable[P.navdatatableindex][DESTFREQ])
                    else
                        set(nav1stdbyfreq, get(nav1freq))
                        set(nav1freq, P.navdatatable[P.navdatatableindex][DESTFREQ])
                    end
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop3.steprepeat) then
                P.commandtableentry(ADVICE, "Frequency checked and " .. addspaces(formatILSFrequency(P.navdatatable[P.navdatatableindex][DESTFREQ])))
            end
        elseif (((P.navdatatable[P.navdatatableindex][DESTNAVTYPE] == NAVTYPEGLS) or (P.navdatatable[P.navdatatableindex][DESTNAVTYPE] == NAVTYPELPV)) and (get(mmrinstalled) == ON)) then
            if ((get(mmrcptactvalue) ~= P.navdatatable[P.navdatatableindex][DESTFREQ]) or not ((get(mmrcptactmode) ~= MMRGLS) or (get(mmrcptactmode) ~= MMRLPV))) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Channel " .. addspaces(P.navdatatable[P.navdatatableindex][DESTFREQ]))
                    P.procedureloop3.stepindex = P.procedureloop3.stepindex - 1
                else
                    setmmrgls(MMRCAPTAIN, P.navdatatable[P.navdatatableindex][DESTFREQ])
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop3.steprepeat) then
                P.commandtableentry(ADVICE, "Channel checked and " .. addspaces(P.navdatatable[P.navdatatableindex][DESTFREQ]))
            end
        end
    elseif (P.procedureloop3.stepindex == 5) then
        if (P.configvalues[CONFIGAUTOFUNCTIONS] == ON) then
            if ((P.navdatatable[P.navdatatableindex][DESTNAVTYPE] == NAVTYPEILS) and P.navdatatable[P.navdatatableindex][DESTNAVDME]) then
                if ((get(nav2freq) ~= get(nav1freq)) or ((get(mmrinstalled) == ON) and ((get(mmrfoactvalue) ~= get(nav1freq)) or (get(mmrfoactmode) ~= MMRILS)))) then
                    if (get(mmrinstalled) == ON) then
                        setmmrils(MMRFO, get(nav1freq))
                    else
                        set(nav2stdbyfreq, get(nav2freq))
                        set(nav2freq, get(nav1freq))
                    end
                end
            elseif ((P.navdatatable[P.navdatatableindex][DESTNAVTYPE] == NAVTYPEGLS) and (get(mmrinstalled) == ON)) then
                if ((get(mmrfoactvalue) ~= (get(mmrcptactvalue)) or (get(mmrfoactmode) ~= MMRGLS))) then
                    setmmrgls(MMRFO, get(mmrcptactvalue))
                end
            end
        end
    elseif (P.procedureloop3.stepindex == 6) then
        setview(CONFIGVIEWMAINPANEL)
    elseif (P.procedureloop3.stepindex == 7) then
        pilotcoursenew = P.navdatatable[P.navdatatableindex][DESTCOURSE]

        if (get(mcppilotcourse) ~= pilotcoursenew) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Course " .. addspaces(padNumberWithZerosStrict(pilotcoursenew, 3)))
                P.procedureloop3.stepindex = P.procedureloop3.stepindex - 1
            else   
                set(mcppilotcourse, pilotcoursenew)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop3.steprepeat) then
            P.commandtableentry(ADVICE, "Course checked and " ..  addspaces(padNumberWithZerosStrict(pilotcoursenew, 3)))
        end   
    elseif (P.procedureloop3.stepindex == 8) then
        if (P.configvalues[CONFIGAUTOFUNCTIONS] == ON) then
            if ((P.navdatatable[P.navdatatableindex][DESTNAVTYPE] == NAVTYPEILS) and P.navdatatable[P.navdatatableindex][DESTNAVDME]) then
                if (get(mcpcopilotcourse) ~= get(mcppilotcourse)) then
                    set(mcpcopilotcourse, get(mcppilotcourse))
                end
            elseif ((P.navdatatable[P.navdatatableindex][DESTNAVTYPE]  == NAVTYPEGLS) and (get(mmrinstalled) == ON)) then
                if (get(mcpcopilotcourse) ~= get(mcppilotcourse)) then
                    set(mcpcopilotcourse, get(mcppilotcourse))
                end
            end
        end      
    end

   return true

end

function setilsproc()

    if (P.procedureloop3.lock == NOPROCEDURE) then
        P.procedureloop3.lock = SETILSPROCEDURE
    end

    return true

end

function setilsproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        setilsproc()
    end
    return 0
end

my_command_setils = sasl.createCommand(definitions.APPNAMEPREFIX .. "/setils", "Set ILS/GLS Frequency and Course")
sasl.registerCommandHandler(my_command_setils, 0, setilsproc_)

--------------------------------------------------------------------------------------------------------------
function decodemetar(metar)
    local result = {}
    local parts = {}

    -- String-Split
    sasl.logDebug("Starting METAR parsing")
    local current_part = ""
    for i = 1, #metar do
        local c = metar:sub(i,i)
        if (c == " ") then
            if (#current_part > 0) then
                table.insert(parts, current_part)
                current_part = ""
            end
        else
            current_part = current_part .. c
        end
    end
    if (#current_part > 0) then
        table.insert(parts, current_part)
    end

    sasl.logDebug("METAR parts:")
    for idx, part_val in ipairs(parts) do
        sasl.logDebug(string.format("  [%d] = %s", idx, part_val))
    end

    -- Station
    if (#parts >= 1) then
        result.station = parts[1]
        sasl.logDebug("Parsed station: "..result.station)
    end

    -- Date/Time
    if (#parts >= 2) then
        local dt = parts[2]
        if ((#dt == 7) and (dt:sub(7) == "Z")) then
            local day = tonumber(dt:sub(1,2))
            local time_str = dt:sub(3,6)
            if (day and time_str) then
                result.date_time = { day = day, time = time_str, timezone = "Z" }
                sasl.logDebug(string.format("Parsed datetime: day=%d, time=%s", result.date_time.day, result.date_time.time))
            else
                sasl.logDebug("Warning: Could not parse day or time from: " .. dt)
            end
        else
            sasl.logDebug("Warning: Date/Time part not in expected format: " .. dt)
        end
    end

    local i = 3 -- Start index for main METAR parts
    local parsing_main_data = true

    -- AUTO
    if (i <= #parts and parts[i] == "AUTO") then
        result.auto = true
        sasl.logDebug("Parsed AUTO: true")
        i = i + 1
    else
        result.auto = false
    end

    local weather_codes = {
        "RA","SN","DZ","SG","PL","GR","GS","IC","UP","FG","BR","SA",
        "DU","HZ","FU","VA","PY","PO","SQ","FC","SS","DS","SH","TS",
        "FZ","MI","PR","BC","DR","BL","VC","NSW"
    }

    local function is_weather_code(s)
        local code_to_check = s
        if s:sub(1,1) == "-" or s:sub(1,1) == "+" then
            code_to_check = s:sub(2)
        end
        if #code_to_check < 2 then return false end

        for _, code in ipairs(weather_codes) do
            if code_to_check:find(code, 1, true) then
                if code_to_check == code then return true end
            end
        end
        for _, code in ipairs(weather_codes) do
            if s:find(code, 1, true) then
                return true
            end
        end
        return false
    end

    while (i <= #parts and parsing_main_data) do
        local part = parts[i]
        sasl.logDebug(string.format("Processing part %d: %s", i, part))
        local parsed = false

        if (part == "TEMPO" or part == "BECMG" or (string.len(part) >= 4 and part:sub(1,4) == "PROB") or part == "TREND") then
            parsing_main_data = false
            sasl.logDebug("Trend/change group found, METAR main data parsing stopped: " .. part)
            break

        elseif (part == "CAVOK") then
            result.cavok = true
            result.visibility = { value = 10000 }
            result.clouds = result.clouds or {}
            table.insert(result.clouds, {coverage="NSC", altitude=nil, type=""})
            sasl.logDebug("Parsed CAVOK: visibility >= 10km, no significant clouds/weather")
            parsed = true

        elseif (not result.wind and
                ( (part:sub(1,3) == "VRB") or (tonumber(part:sub(1,3)) ~= nil) ) and
                (#part >= 5) and
                (part:sub(-2) == "KT" or part:sub(-3) == "MPS" or part:sub(-3) == "KMH")
               ) then
            local dir_str = part:sub(1,3)
            local direction = (dir_str == "VRB") and "VRB" or tonumber(dir_str)
            local var_dir_match = nil
            if ((#part >= 9) and (part:sub(6,6) == "V")) then
                local d1_str = part:sub(4,5)
                local d2_str = part:sub(7,9)
                local d1 = tonumber(d1_str)
                local d2 = tonumber(d2_str)
                if (d1 and d2) then
                    var_dir_match = { dir1 = d1, dir2 = d2 }
                    sasl.logDebug(string.format("Parsed variable wind direction (within main wind group): %d-%d", d1, d2))
                end
            end

            local unit_str = (part:sub(-2) == "KT" and "KT") or
                             (part:sub(-3) == "MPS" and "MPS") or
                             (part:sub(-3) == "KMH" and "KMH") or nil

            if (direction and unit_str) then
                local speed_part_end = #part - #unit_str
                local speed_str_val = ""
                local gust_str_val = nil
                local g_pos = part:find("G", 4)

                if (g_pos and g_pos < speed_part_end) then
                    speed_str_val = part:sub(4, g_pos - 1)
                    gust_str_val = part:sub(g_pos + 1, speed_part_end)
                else
                    speed_str_val = part:sub(4, speed_part_end)
                end

                local speed = tonumber(speed_str_val)
                local gust = (gust_str_val and tonumber(gust_str_val)) or 0

                if (speed ~= nil) then
                    local original_speed_for_log = speed
                    local original_gust_for_log = gust
                    local original_unit_for_log = unit_str

                    if (unit_str == "MPS") then
                        speed = math.floor(speed * 1.94384 + 0.5)
                        if (gust_str_val) then gust = math.floor(gust * 1.94384 + 0.5) end
                    elseif (unit_str == "KMH") then
                        speed = math.floor(speed * 0.539957 + 0.5)
                        if (gust_str_val) then gust = math.floor(gust * 0.539957 + 0.5) end
                    end

                    result.wind = {
                        direction = direction,
                        speed = speed,
                        gust = gust,
                        variable_direction = var_dir_match
                    }
                    if unit_str ~= "KT" then
                        sasl.logDebug(string.format("Converted %s %s (gust %s) to %d kt (gust %d kt)", speed_str_val, original_unit_for_log, gust_str_val or "N/A", speed, gust))
                    end
                    sasl.logDebug(string.format("Parsed wind: dir=%s, speed=%d kt, gust=%d kt%s",
                        tostring(direction), speed, gust, (var_dir_match and string.format(", var=%d-%d", var_dir_match.dir1, var_dir_match.dir2)) or ""))
                    parsed = true
                else
                    sasl.logDebug("Warning: Could not parse wind speed from: " .. part)
                end
            else
                sasl.logDebug("Warning: Could not parse wind direction or unit from: " .. part)
            end

        elseif (not result.visibility and #part > 1 and #part <= 5 and string.sub(part, -2) == "SM") then
            local sm_val_str = string.sub(part, 1, #part - 2)
            local sm_value = tonumber(sm_val_str)
            if (sm_value) then
                local meters = math.floor(sm_value * 1609.34 + 0.5)
                result.visibility = { value = math.min(meters, 10000) }
                sasl.logDebug(string.format("Parsed visibility: %sSM, converted to %d meters (limited to 10000)", sm_val_str, result.visibility.value))
                parsed = true
            else
                if sm_val_str == "P6" then
                    result.visibility = { value = math.min(math.floor(7 * 1609.34 + 0.5), 10000) }
                    sasl.logDebug(string.format("Parsed visibility: P6SM, interpreted as >6SM (~%d meters)", result.visibility.value))
                    parsed = true
                else
                    sasl.logDebug("Warning: Could not parse SM visibility value from: " .. part)
                end
            end

        elseif (not result.visibility and #part == 4 and (tonumber(part) or part == "9999")) then
            if (part == "9999") then
                result.visibility = { value = 10000 }
                sasl.logDebug("Parsed visibility: 10000+ meters (from 9999)")
                parsed = true
            else
                local vis_value = tonumber(part)
                if vis_value then
                    result.visibility = { value = vis_value }
                    sasl.logDebug(string.format("Parsed visibility: %d meters", result.visibility.value))
                    parsed = true
                else
                    sasl.logDebug("Warning: Numeric visibility part #4 failed tonumber unexpectedly: " .. part)
                end
            end
            
        elseif (part:sub(1,1) == "R" and part:find("/", 1, true) and #part >= 5) then
            result.runway_reports = result.runway_reports or {}
            table.insert(result.runway_reports, part)
            sasl.logDebug("Parsed runway report: "..part)
            parsed = true

        elseif (is_weather_code(part)) then
            result.weather = result.weather or {}
            local intensity = "moderate"
            local phenomenon = part
            if part:sub(1,1) == "-" then
                intensity = "light"
                phenomenon = part:sub(2)
            elseif part:sub(1,1) == "+" then
                intensity = "heavy"
                phenomenon = part:sub(2)
            end
            
            local valid_phenomenon = false
            if #phenomenon >= 2 then
                for _, wc_entry in ipairs(weather_codes) do
                    if phenomenon == wc_entry or phenomenon:find(wc_entry, 1, true) then
                        valid_phenomenon = true
                        break
                    end
                end
            end

            if valid_phenomenon then
                table.insert(result.weather, {
                    intensity = intensity,
                    phenomenon = phenomenon
                })
                sasl.logDebug(string.format("Parsed weather: %s (%s)", phenomenon, intensity))
                parsed = true
            else
                sasl.logDebug("Warning: Part looked like weather but phenomenon not matched or invalid: " .. part .. " (phenomenon checked: " .. phenomenon .. ")")
            end

        elseif ( (string.sub(part,1,3) == "FEW" or string.sub(part,1,3) == "SCT" or string.sub(part,1,3) == "BKN" or string.sub(part,1,3) == "OVC") and
                     #part >= 6 and tonumber(part:sub(4,6)) ~= nil ) or
                     ( string.sub(part,1,2) == "VV" and #part >= 5 and tonumber(part:sub(3,5)) ~= nil ) or
                     ( part == "SKC" or part == "CLR" or part == "NSC" )
        then
            result.clouds = result.clouds or {}
            if (part == "SKC" or part == "CLR" or part == "NSC") then
                table.insert(result.clouds, { coverage = part, altitude = nil, type = "" })
                sasl.logDebug("Parsed cloud: " .. part)
                parsed = true
            else
                local coverage_code
                local altitude_str_val
                local altitude_idx_start

                if part:sub(1,2) == "VV" then
                    coverage_code = "VV"
                    altitude_idx_start = 3
                else
                    coverage_code = part:sub(1,3)
                    altitude_idx_start = 4
                end
                altitude_str_val = part:sub(altitude_idx_start, altitude_idx_start + 2)
                local altitude_val = tonumber(altitude_str_val)

                if altitude_val then
                    local cloud_significant_type = ""
                    if #part > (altitude_idx_start + 2) then
                        cloud_significant_type = part:sub(altitude_idx_start + 3)
                    end
                    table.insert(result.clouds, {
                        coverage = coverage_code,
                        altitude = altitude_val * 100,
                        type = cloud_significant_type
                    })
                    sasl.logDebug(string.format("Parsed cloud: %s at %d ft%s",
                        coverage_code, altitude_val * 100,
                        (cloud_significant_type ~= "" and (" ("..cloud_significant_type..")")) or ""))
                    parsed = true
                else
                    sasl.logDebug("Warning: Could not parse cloud altitude for: " .. part .. " (altitude_str: '" .. altitude_str_val .. "')")
                end
            end

        elseif ( part:find("/",1,true) and (#part >= 5 and #part <= 7) and
                     (part:sub(1,1) == "M" or tonumber(part:sub(1,1)) ~= nil) ) then
            local slash_pos = part:find("/",2,true)
            if slash_pos and slash_pos > 1 and slash_pos < #part then
                local temp_str_val = part:sub(1, slash_pos-1)
                local dew_str_val = part:sub(slash_pos+1)

                local temp_val = tonumber((temp_str_val:gsub("M","-")))
                local dew_val = tonumber((dew_str_val:gsub("M","-")))

                if ((temp_val ~= nil) and (dew_val ~= nil)) then
                    result.temperature = { value = temp_val }
                    result.dew_point = { value = dew_val }
                    sasl.logDebug(string.format("Parsed temp/dew: %d°C/%d°C", temp_val, dew_val))
                    parsed = true
                else
                    sasl.logDebug("Warning: Could not parse temperature or dew point values from: " .. part .. " (temp_str="..temp_str_val..", dew_str="..dew_str_val..")")
                end
            else
                sasl.logDebug("Warning: Temp/Dew part malformed (slash position or content): " .. part)
            end

        elseif ((#part == 5) and (part:sub(1,1) == "Q" or part:sub(1,1) == "A") and tonumber(part:sub(2))) then
            local val_str = part:sub(2)
            local value_num = tonumber(val_str)
            local pressure_hpa = nil

            if (part:sub(1,1) == "Q") then
                pressure_hpa = math.floor(value_num + 0.5)
            elseif (part:sub(1,1) == "A") then
                local inHg = value_num / 100
                pressure_hpa = math.floor(inHg * 33.8639 + 0.5)
            end

            if pressure_hpa then
                result.pressure = { qnh_hpa = pressure_hpa } -- KORRIGIERTE ZUWEISUNG HIER
                sasl.logDebug(string.format("Parsed pressure: %d hPa (raw: %s)", pressure_hpa, part))
                parsed = true
            else
                sasl.logDebug("Warning: Could not calculate hPa pressure from: " .. part)
            end

        elseif (part == "NOSIG") then
            result.nosig = true
            sasl.logDebug("Parsed NOSIG: no significant change expected")
            parsed = true
            
        elseif (part == "RMK") then
            result.remarks = {}
            sasl.logDebug("Entered RMK block.")
            local remark_idx = i + 1
            while(remark_idx <= #parts) do
                local current_remark = parts[remark_idx]
                if (current_remark == "TEMPO" or current_remark == "BECMG" or (string.len(current_remark) >=4 and current_remark:sub(1,4) == "PROB") or current_remark == "TREND") then
                    sasl.logDebug("Remark parsing stopped; trend/change group encountered: " .. current_remark)
                    break
                end

                table.insert(result.remarks, current_remark)
                sasl.logDebug("Parsed remark: " .. current_remark)

                if current_remark == "$" then
                    result.maintenance_indicator = true
                    sasl.logDebug("Maintenance indicator '$' found and included in remarks.")
                    remark_idx = remark_idx + 1
                    break
                end
                remark_idx = remark_idx + 1
            end
            i = remark_idx -1
            parsed = true
            parsing_main_data = false
            sasl.logDebug("Finished RMK section. Main data parsing will stop.")
        end

        if (not parsed and parsing_main_data) then
            sasl.logDebug("Unknown element: "..part)
        end
        i = i + 1
    end

    sasl.logDebug("METAR parsing complete")
    return result
end

--------------------------------------------------------------------------------------------------------------
function parseCSVToTable(csvData)
    -- Teile die CSV-Daten in Zeilen auf
    local lines = {}
    local startPos = 1
    while true do
        local endPos = csvData:find("\n", startPos)
        if not endPos then
            table.insert(lines, csvData:sub(startPos))
            break
        end
        table.insert(lines, csvData:sub(startPos, endPos - 1))
        startPos = endPos + 1
    end

    -- Finde die Header-Zeile und die Datenzeile
    local headerLine, dataLine
    for i = #lines, 1, -1 do
        if lines[i]:find("raw_text") then
            headerLine = lines[i]
            dataLine = lines[i + 1]
            break
        end
    end

    -- Überprüfen, ob Header und Daten gefunden wurden
    if not headerLine or not dataLine then
        return nil
    end

    -- Header extrahieren
    local headers = {}
    local startPosHeader = 1
    while true do
        local endPosHeader = headerLine:find(",", startPosHeader)
        if not endPosHeader then
            table.insert(headers, headerLine:sub(startPosHeader))
            break
        end
        table.insert(headers, headerLine:sub(startPosHeader, endPosHeader - 1))
        startPosHeader = endPosHeader + 1
    end

    -- Daten extrahieren
    local values = {}
    local startPosData = 1
    while true do
        local endPosData = dataLine:find(",", startPosData)
        if not endPosData then
            table.insert(values, dataLine:sub(startPosData))
            break
        end
        table.insert(values, dataLine:sub(startPosData, endPosData - 1))
        startPosData = endPosData + 1
    end

    -- Kombiniere Header und Werte in einer Tabelle
    local resultTable = {}
    for i = 1, #headers do
        resultTable[headers[i]] = values[i] or ""  -- Leere Werte durch "" ersetzen
    end

    return resultTable
end

--------------------------------------------------------------------------------------------------------------
function getMetar(icaocode)

    local metarTable = {}
    local metarUrl = definitions.AVWEATHERFURLCSV .. icaocode
    local tempFilePath = definitions.YALCACHEPATH .. icaocode .. "_metar.csv"  -- CSV-Datei

    sasl.logDebug("URL " .. metarUrl)
        sasl.logDebug("Path " .. tempFilePath)

    if sasl.net.downloadFileSync(metarUrl, tempFilePath) then
        sasl.logInfo("METAR for " .. icaocode .. " successfully loaded")

        -- Datei öffnen und lesen
        local file = io.open(tempFilePath, "r")
        if file then
            local csvData = file:read("*a")  -- Lese den gesamten Inhalt der Datei als String
            file:close()

            -- Temporäre Datei löschen
            os.remove(tempFilePath)

            -- CSV-Daten in eine Lua-Tabelle umwandeln
             
            metarTable = parseCSVToTable(csvData)
            if metarTable then
                -- Tabelle ausgeben
                sasl.logDebug("METAR-Data for " .. icaocode .. ":")
                for key, value in pairs(metarTable) do
                    sasl.logDebug(key .. ": " .. value)
                end
            else
                sasl.logDebug("Error Parsing CSV-Data.")
            end
        else
            sasl.logDebug("Error Opening Temp File.")
        end
    else
        -- Fehler beim Herunterladen
        sasl.logInfo("Error Downloading METAR for " .. icaocode .. ".")
    end

    return metarTable
end

--------------------------------------------------------------------------------------------------------------
function getRunwayHeadingFromDesignator(runwayDesignator)
    if not runwayDesignator or #runwayDesignator < 2 then
        sasl.logDebug("Error: Invalid runway designator provided: " .. tostring(runwayDesignator))
        return nil
    end

    local rwyNumberStr = runwayDesignator:sub(1,2)
    local rwyNumber = tonumber(rwyNumberStr)

    if not rwyNumber then
        sasl.logDebug("Error: Could not parse runway number from designator: " .. runwayDesignator)
        return nil
    end

    -- Runway Heading ist die Nummer * 10
    local heading = rwyNumber * 10
    return heading
end

--------------------------------------------------------------------------------------------------------------
function shouldCheckRunwaySuitability(weatherData, runwayDesignator)
    -- --- Schwellenwerte anpassbar ---
    local MAX_TAILWIND_KN = 10     -- Maximal erlaubter Rückenwind für normale Landung
    local MAX_CROSSWIND_KN = 20    -- Maximal erlaubter Seitenwind (oft Flugzeug-spezifisch)
    local MIN_WIND_SPEED_FOR_CHECK = 5 -- Mindestwindstärke, ab der Windkomponenten relevant werden

    sasl.logDebug("Checking suitability for runway: " .. tostring(runwayDesignator))

    -- 1. Grundlegende Wetterdaten prüfen
    if not (weatherData and weatherData.wind and weatherData.wind.direction ~= nil and weatherData.wind.speed ~= nil) then
        sasl.logDebug("Warning: Insufficient wind data to check runway suitability. Returning true (default safe).")
        return true -- Wenn keine Winddaten vorhanden sind, können wir nicht prüfen. Annahme: Landebahn ist standardmäßig ok.
    end

    local windDirection = weatherData.wind.direction
    local windSpeed = weatherData.wind.speed

    -- Wenn Wind "calm" ist, ist die Landebahn in Bezug auf Wind immer geeignet
    if windSpeed == 0 then
        sasl.logDebug("Wind is calm. Runway is suitable based on wind.")
        return true
    end

    -- Wenn der Wind sehr schwach ist, sind die Komponenteneffekte minimal
    if windSpeed < MIN_WIND_SPEED_FOR_CHECK then
         sasl.logDebug(string.format("Wind speed (%d kt) is below check threshold (%d kt). Runway is suitable based on wind.", windSpeed, MIN_WIND_SPEED_FOR_CHECK))
         return true
    end

    -- 2. Landebahn-Richtung ableiten
    local runwayHeading = getRunwayHeadingFromDesignator(runwayDesignator)
    if not runwayHeading then
        sasl.logDebug("Error: Could not determine runway heading from designator. Returning true (default safe).")
        return true -- Kann Landebahn nicht ableiten, kann nicht prüfen.
    end

    -- 3. Windkomponenten berechnen
    local headwindComponent, crosswindKnots = calculateWindComponents(windDirection, runwayHeading, windSpeed)

    sasl.logDebug(string.format("Calculated for RWY %s (Heading %d): Headwind %.1f kt, Crosswind %.1f kt (from Wind %d@%dkt)",
                                runwayDesignator, runwayHeading, headwindComponent, crosswindKnots, windDirection, windSpeed))


    -- 4. Überprüfung der Schwellenwerte
    -- Rückenwind (HeadwindComponent ist negativ bei Rückenwind)
    if headwindComponent < -MAX_TAILWIND_KN then
        sasl.logDebug(string.format("Runway %s: Tailwnd (%.1f kt) exceeds max allowed (%.1f kt). Check recommended.", runwayDesignator, math.abs(headwindComponent), MAX_TAILWIND_KN))
        return false -- Rückenwind zu stark
    end

    -- Seitenwind
    if crosswindKnots > MAX_CROSSWIND_KN then
        sasl.logDebug(string.format("Runway %s: Crosswind (%.1f kt) exceeds max allowed (%.1f kt). Check recommended.", runwayDesignator, crosswindKnots, MAX_CROSSWIND_KN))
        return false -- Seitenwind zu stark
    end

    sasl.logDebug(string.format("Runway %s is suitable based on current wind conditions.", runwayDesignator))
    return true -- Landebahn ist innerhalb der Schwellenwerte geeignet
end

--------------------------------------------------------------------------------------------------------------
function formatMetarSpeechSummary(metar)
    local parts = {}

    -- Extract necessary data from the metar table
    local icaocode = metar.icaocode
    local metar_data = metar.decodedmetar

    -- Add airport ICAO code to the beginning of the summary
    if icaocode and #icaocode > 0 then
        table.insert(parts, addspaces(icaocode))
    end

    -- Wind
    if metar_data.wind then
        local dir = metar_data.wind.direction
        local speed = metar_data.wind.speed
        local gust = metar_data.wind.gust

        local wind_part = ""
        if speed == 0 then -- Handle calm condition
            wind_part = "Wind calm"
        elseif dir == "VRB" then
            wind_part = "Wind variable at "
            wind_part = wind_part .. string.format("%d knots", speed)
            if gust and gust > 0 then
                wind_part = wind_part .. string.format(" gusting %d", gust)
            end
        else
            wind_part = string.format("Wind %d at ", dir)
            wind_part = wind_part .. string.format("%d knots", speed)
            if gust and gust > 0 then
                wind_part = wind_part .. string.format(" gusting %d", gust)
            end
        end
        table.insert(parts, wind_part)
    end

    -- Visibility
    if metar_data.visibility then
        local vis_val = metar_data.visibility.value
        local vis_part = "Visibility "
        if metar_data.cavok then -- Prioritize CAVOK if present
            vis_part = "Visibility 10 kilometers or more"
        elseif vis_val >= 10000 then
            vis_part = vis_part .. "10 kilometers or more"
        elseif vis_val >= 1609 then -- Convert to miles if close to a mile (1609m = 1 mile)
            vis_part = vis_part .. string.format("%d statute miles", math.floor(vis_val / 1609.34 + 0.5))
        elseif vis_val >= 1000 then -- Convert to kilometers if 1km or more
            vis_part = vis_part .. string.format("%d kilometers", math.floor(vis_val / 1000 + 0.5))
        else
            vis_part = vis_part .. string.format("%d meters", vis_val)
        end
        table.insert(parts, vis_part)
    end

    -- General Weather (simplified)
    if metar_data.weather and #metar_data.weather > 0 then
        local weather_desc = {}
        for _, wx_entry in ipairs(metar_data.weather) do
            local intensity = ""
            if wx_entry.intensity == "light" then intensity = "light "
            elseif wx_entry.intensity == "heavy" then intensity = "heavy " end
            -- Map common phenomena to more speech-friendly terms
            local phenomenon = wx_entry.phenomenon
            if phenomenon == "RA" then phenomenon = "rain"
            elseif phenomenon == "SN" then phenomenon = "snow"
            elseif phenomenon == "DZ" then phenomenon = "drizzle"
            elseif phenomenon == "FG" then phenomenon = "fog"
            elseif phenomenon == "BR" then phenomenon = "mist"
            elseif phenomenon == "HZ" then phenomenon = "haze"
            elseif phenomenon == "TS" then phenomenon = "thunderstorm"
            -- Add more mappings for other weather codes if necessary
            end
            table.insert(weather_desc, intensity .. phenomenon)
        end
        if #weather_desc > 0 then
            table.insert(parts, "Currently " .. table.concat(weather_desc, " and "))
        end
    end

    -- Clouds (simplified, only highest significant cloud layer or broken/overcast)
    if metar_data.clouds and #metar_data.clouds > 0 then
        local cloud_part = ""
        local significant_cloud = nil

        -- Find the lowest broken/overcast layer or highest significant cloud
        for _, cloud in ipairs(metar_data.clouds) do
            if cloud.coverage == "OVC" or cloud.coverage == "BKN" or cloud.coverage == "VV" then
                significant_cloud = cloud
                break -- Found a ceiling, which is usually the most important
            elseif (not significant_cloud and cloud.altitude) then
                -- If no ceiling found yet, keep track of the highest cloud for "scattered/few" case
                if not significant_cloud or cloud.altitude > significant_cloud.altitude then
                    significant_cloud = cloud
                end
            end
        end

        if metar_data.cavok then
            -- CAVOK implies "no significant clouds" and visibility >= 10km, handled by visibility
        elseif significant_cloud then
            local coverage_str = significant_cloud.coverage
            local altitude_ft = significant_cloud.altitude

            -- Expanded cloud coverage abbreviations for speech
            local readable_coverage = coverage_str
            if coverage_str == "FEW" then readable_coverage = "few"
            elseif coverage_str == "SCT" then readable_coverage = "scattered"
            elseif coverage_str == "BKN" then readable_coverage = "broken"
            elseif coverage_str == "OVC" then readable_coverage = "overcast"
            elseif coverage_str == "SKC" or coverage_str == "CLR" then readable_coverage = "sky clear"
            elseif coverage_str == "NSC" then readable_coverage = "no significant clouds"
            elseif coverage_str == "VV" then readable_coverage = "vertical visibility"
            end

            if readable_coverage == "sky clear" or readable_coverage == "no significant clouds" then
                cloud_part = readable_coverage
            elseif readable_coverage == "vertical visibility" then
                cloud_part = string.format("%s %d feet", readable_coverage, altitude_ft)
            else
                cloud_part = string.format("%s clouds at %d feet", readable_coverage, altitude_ft)
            end
            table.insert(parts, cloud_part)
        end
    end

    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------------------------------------
function calculateAirDensity(weatherData)
    local SPECIFIC_GAS_CONSTANT_DRY_AIR = 287.05
    
    if not (weatherData and weatherData.pressure and weatherData.pressure.qnh_hpa and
            weatherData.temperature and weatherData.temperature.value ~= nil) then
        return 1.225
    end

    local pressureHPa = weatherData.pressure.qnh_hpa
    local temperatureKelvin = weatherData.temperature.value + 273.15

    local airDensity = (pressureHPa * 100) / (SPECIFIC_GAS_CONSTANT_DRY_AIR * temperatureKelvin)

    return airDensity
end

--------------------------------------------------------------------------------------------------------------
function calculateDensityAltitude(fieldElevationMeters, temperatureCelsius, pressureHPa)
    local STANDARD_PRESSURE_HPA = 1013.25
    local STANDARD_TEMPERATURE_CELSIUS = 15
    local METERS_TO_FEET = 3.28084

    local fieldElevationFt = fieldElevationMeters * METERS_TO_FEET

    if type(fieldElevationFt) ~= "number" or type(temperatureCelsius) ~= "number" or type(pressureHPa) ~= "number" then
        return 0
    end

    local temperatureDeviation = temperatureCelsius - STANDARD_TEMPERATURE_CELSIUS
    local pressureAltitude = fieldElevationFt + (STANDARD_PRESSURE_HPA - pressureHPa) * 30

    local densityAltitude = pressureAltitude + (temperatureDeviation * 120)
    return densityAltitude
end

--------------------------------------------------------------------------------------------------------------
function calculateWindComponents(windDirectionDegrees, runwayHeadingDegrees, windSpeedKnots)
    if type(windDirectionDegrees) ~= "number" or type(runwayHeadingDegrees) ~= "number" or type(windSpeedKnots) ~= "number" then
        return 0, 0
    end

    local angleDifference = math.abs(windDirectionDegrees - runwayHeadingDegrees)
    if angleDifference > 180 then
        angleDifference = 360 - angleDifference
    end
    local angleRad = math.rad(angleDifference)

    local headwindComponent = math.cos(angleRad) * windSpeedKnots
    local crosswindComponent = math.abs(math.sin(angleRad) * windSpeedKnots)

    return headwindComponent, crosswindComponent
end

--------------------------------------------------------------------------------------------------------------
function calculateStallSpeed(weightKg, weatherData, flapsSetting)
    local GRAVITY = 9.80665
    local WING_AREA_737 = 124.6
    local METER_PER_SECOND_TO_KNOTS = 1.94384
    
    local MAX_LIFT_COEFFICIENT_VALUES = {
        [0] = 1.6, [1] = 1.7, [5] = 1.8, [10] = 2.0,
        [15] = 2.2, [20] = 2.4, [25] = 2.6, [30] = 2.8, [40] = 3.0
    }
    local DEFAULT_MAX_LIFT_COEFFICIENT = 2.5

    local maxLiftCoefficient = MAX_LIFT_COEFFICIENT_VALUES[flapsSetting] or DEFAULT_MAX_LIFT_COEFFICIENT
    local airDensity = calculateAirDensity(weatherData)

    if airDensity <= 0 or maxLiftCoefficient <= 0 or WING_AREA_737 <= 0 or weightKg <= 0 then
        return 0
    end

    local stallSpeedMps = math.sqrt((2 * weightKg * GRAVITY) / (airDensity * WING_AREA_737 * maxLiftCoefficient))
    local stallSpeedKnots = stallSpeedMps * METER_PER_SECOND_TO_KNOTS

    return stallSpeedKnots
end

--------------------------------------------------------------------------------------------------------------
function determineLandingFlapsSetting(runwayLengthMeters, windSpeedKnots, crosswindKnots, isBadWeather, weightKg)
    local LANDING_SHORT_RUNWAY_THRESHOLD = 2000
    local LANDING_HIGH_WIND_THRESHOLD = 20
    local LANDING_HIGH_CROSSWIND_THRESHOLD = 15
    local LANDING_HIGH_WEIGHT_THRESHOLD = 55000

    if runwayLengthMeters < LANDING_SHORT_RUNWAY_THRESHOLD or
       windSpeedKnots > LANDING_HIGH_WIND_THRESHOLD or
       crosswindKnots > LANDING_HIGH_CROSSWIND_THRESHOLD or
       isBadWeather or
       weightKg > LANDING_HIGH_WEIGHT_THRESHOLD then
        return 40
    else
        return 30
    end
end

--------------------------------------------------------------------------------------------------------------
function calculateVref(weightKg, flapsSetting, weatherData, crosswindKnots)
    local VREF_STALL_SPEED_FACTOR = 1.37
    local VREF_WIND_ADDITION = 5
    local VREF_PRECIPITATION_ADDITION = 5
    local VREF_CROSSWIND_ADDITION = 5
    local LANDING_HIGH_WIND_THRESHOLD_FOR_VREF = 20

    local stallSpeedKnots = calculateStallSpeed(weightKg, weatherData, flapsSetting)
    local vrefKnots = stallSpeedKnots * VREF_STALL_SPEED_FACTOR

    if weatherData.wind and weatherData.wind.speed and weatherData.wind.speed > LANDING_HIGH_WIND_THRESHOLD_FOR_VREF then
        vrefKnots = vrefKnots + VREF_WIND_ADDITION
    end

    -- --- CORRECTION START ---
    -- Check if precipitation is present by iterating through the weather table
    local hasPrecipitation = false
    if weatherData.weather then
        for _, wx_entry in ipairs(weatherData.weather) do
            if wx_entry.phenomenon == "RA" or wx_entry.phenomenon == "SN" then
                hasPrecipitation = true
                break -- Found precipitation, no need to check further
            end
        end
    end

    if hasPrecipitation then
        vrefKnots = vrefKnots + VREF_PRECIPITATION_ADDITION
    end
    -- --- CORRECTION END ---

    if crosswindKnots > VREF_CROSSWIND_ADDITION then
        vrefKnots = vrefKnots + VREF_CROSSWIND_ADDITION
    end

    return vrefKnots
end

--------------------------------------------------------------------------------------------------------------
function calcappflapsvref(weatherData)
    if not (weatherData and weatherData.wind and weatherData.wind.direction ~= nil and weatherData.wind.speed ~= nil and
            weatherData.temperature and weatherData.temperature.value ~= nil and
            weatherData.pressure and weatherData.pressure.qnh_hpa ~= nil) then
        return 30, get(vref30)
    end

    if not (get(totalweightkgs) and type(get(totalweightkgs)) == "number" and get(totalweightkgs) > 0 and
            get(desrwylen) and type(get(desrwylen)) == "number" and get(desrwylen) > 0 and
            get(desrwyheading) and type(get(desrwyheading)) == "number" and
            get(desrwyalt) and type(get(desrwyalt)) == "number") then
        return 30, get(vref30)
    end

    local headwindComponent, crosswindKnots = calculateWindComponents(
        weatherData.wind.direction,
        get(desrwyheading),
        weatherData.wind.speed
    )

    local isBadWeather = false

    -- KORRIGIERTER BEREICH: Durch die weatherData.weather Tabelle iterieren
    if weatherData.weather then
        for _, wx_entry in ipairs(weatherData.weather) do
            if wx_entry.phenomenon == "RA" or wx_entry.phenomenon == "SN" then
                isBadWeather = true
                break -- Einmal schlechtes Wetter gefunden, reicht
            end
        end
    end
    -- ENDE DES KORRIGIERTEN BEREICHS

    if weatherData.visibility and weatherData.visibility.value and (weatherData.visibility.value < 5000) then
        isBadWeather = true
    end
    if weatherData.clouds and weatherData.clouds[1] and weatherData.clouds[1].altitude and (weatherData.clouds[1].altitude < 1000) then
        isBadWeather = true
    end

    local flapsSetting = determineLandingFlapsSetting(get(desrwylen), weatherData.wind.speed, crosswindKnots, isBadWeather, get(totalweightkgs))
    local vrefKnots = calculateVref(get(totalweightkgs), flapsSetting, weatherData, crosswindKnots)

    flapsSetting = math.floor(flapsSetting + 0.5)
    vrefKnots = math.floor(vrefKnots + 0.5)

    return flapsSetting, vrefKnots
end

--------------------------------------------------------------------------------------------------------------
function calcautobrake(landingSpeed, weatherData)
    local autobrakeSettings = {
        {maxDeceleration = 1.5, setting = AUTOBRAKE1},
        {maxDeceleration = 2.0, setting = AUTOBRAKE2},
        {maxDeceleration = 3.0, setting = AUTOBRAKE3},
        {maxDeceleration = 4.0, setting = AUTOBRAKEMAX}
    }

    local requiredDeceleration = (landingSpeed^2) / (2 * get(desrwylen))

    if ((fieldexists(weatherData, "weather") and ((containsvalue(weatherData.weather, "FZRA")) or (containsvalue(weatherData.weather, "FZDZ")) or (containsvalue(weatherData.weather, "FZFG"))))
        or (fieldexists(weatherData, "temperature.value") and (weatherData.temperature.value < 1))) then
        requiredDeceleration = requiredDeceleration * 1.5
    elseif (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "SN")))  then
        requiredDeceleration = requiredDeceleration * 1.3
    elseif (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "RA"))) then
        requiredDeceleration = requiredDeceleration * 1.2
    end

    local weightFactor = get(totalweightkgs) / 70000
    requiredDeceleration = requiredDeceleration * weightFactor

    for _, setting in ipairs(autobrakeSettings) do
        if requiredDeceleration <= setting.maxDeceleration then
            return setting.setting
        end
    end

    return AUTOBRAKE1
end

--------------------------------------------------------------------------------------------------------------
function determineTakeoffFlapsSetting(weatherData)
    local STANDARD_TAKEOFF_FLAPS = 5
    local TAKEOFF_WEIGHT_THRESHOLD_HIGH = 65000
    local TAKEOFF_WEIGHT_THRESHOLD_VERY_HIGH = 70000

    local TAKEOFF_RUNWAY_LENGTH_SHORT_THRESHOLD = 2000
    local TAKEOFF_RUNWAY_LENGTH_VERY_SHORT_THRESHOLD = 1600

    local TAKEOFF_DENSITY_ALTITUDE_THRESHOLD_HIGH = 3000

    local TAKEOFF_TAILWIND_CONSIDERATION_THRESHOLD = 5
    local TAKEOFF_WET_RUNWAY_PENALTY_FLAPS = 1

    if not (weatherData and weatherData.wind and weatherData.wind.direction ~= nil and weatherData.wind.speed ~= nil and
            weatherData.temperature and weatherData.temperature.value ~= nil and
            weatherData.pressure and weatherData.pressure.qnh_hpa ~= nil) then
        return STANDARD_TAKEOFF_FLAPS
    end

    local isRunwayWet = false
    if ((fieldexists(weatherData, "weather") and ((containsvalue(weatherData.weather, "FZRA")) or (containsvalue(weatherData.weather, "FZDZ")) or (containsvalue(weatherData.weather, "FZFG"))))
        or (fieldexists(weatherData, "temperature.value") and (weatherData.temperature.value < 1))) then
        isRunwayWet = true
    elseif (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "SN")))  then
        isRunwayWet = true
    elseif (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "RA"))) then
        isRunwayWet = true
    end

    if not (get(totalweightkgs) and type(get(totalweightkgs)) == "number" and get(totalweightkgs) > 0 and
            get(deprwylen) and type(get(deprwylen)) == "number" and get(deprwylen) > 0 and
            get(elevation) and type(get(elevation)) == "number" and
            get(deprwyheading) and type(get(deprwyheading)) == "number") then
        return STANDARD_TAKEOFF_FLAPS
    end

    local recommendedFlaps = STANDARD_TAKEOFF_FLAPS

    local headwindComponent, crosswindComponent = calculateWindComponents(
        weatherData.wind.direction,
        get(deprwyheading),
        weatherData.wind.speed
    )

    if get(totalweightkgs) > TAKEOFF_WEIGHT_THRESHOLD_VERY_HIGH then
        recommendedFlaps = 15
    elseif get(totalweightkgs) > TAKEOFF_WEIGHT_THRESHOLD_HIGH then
        recommendedFlaps = 10
    end

    if get(deprwylen) < TAKEOFF_RUNWAY_LENGTH_VERY_SHORT_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 15)
    elseif get(deprwylen) < TAKEOFF_RUNWAY_LENGTH_SHORT_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 10)
    end

    local deprwyalt = 0

    if (P.depmetar.metar and tonumber(P.depmetar.metar.elevation_m)) then
        deprwyalt = P.depmetar.metar.elevation_m
    else
        deprwyalt = get(elevation)
    end

    local densityAltitude = calculateDensityAltitude(
        deprwyalt,
        weatherData.temperature.value,
        weatherData.pressure.qnh_hpa
    )
    if densityAltitude > TAKEOFF_DENSITY_ALTITUDE_THRESHOLD_HIGH then
        recommendedFlaps = math.max(recommendedFlaps, 10)
    end

    if headwindComponent < -TAKEOFF_TAILWIND_CONSIDERATION_THRESHOLD then
        recommendedFlaps = math.max(recommendedFlaps, 10)
    end

    if isRunwayWet then
        recommendedFlaps = recommendedFlaps + TAKEOFF_WET_RUNWAY_PENALTY_FLAPS
    end

    if recommendedFlaps > 15 then
        recommendedFlaps = 15
    elseif recommendedFlaps < 5 then
        recommendedFlaps = 5
    end

    return recommendedFlaps
end

--------------------------------------------------------------------------------------------------------------
function setvrefsteps()

    local FMC1Line00L = helpers.get("laminar/B738/fmc1/Line00_L")

    local appflapscalc, appvrefcalc = calcappflapsvref(P.desmetar.decodedmetar)
    local appflapscalcstring = tostring(appflapscalc)
    local appvrefcalcstring = tostring(appvrefcalc)

    if (P.procedureloop3.stepindex == 1) then
        setview(P.configvalues[CONFIGVIEWFMS])
    elseif (P.procedureloop3.stepindex == 2) then
        if ((string.len(FMC1Line00L) < 9) or (string.sub(FMC1Line00L, 7, 9) ~= "APP")) then
            helpers.command_once("laminar/B738/button/fmc1_init_ref")
            P.procedureloop3.stepindex = P.procedureloop3.stepindex - 1
        end
    elseif (P.procedureloop3.stepindex == 3) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            if (get(vref) ~= appvrefcalc) then
                P.vrefcmdtable[3] = string.sub(appflapscalcstring, 1, 1)
                P.vrefcmdtable[4] = string.sub(appflapscalcstring, 2, 2)
                P.vrefcmdtable[6] = string.sub(appvrefcalcstring, 1, 1)
                P.vrefcmdtable[7] = string.sub(appvrefcalcstring, 2, 2)
                P.vrefcmdtable[8] = string.sub(appvrefcalcstring, 3, 3)

                local tableindex = 1
                while (P.vrefcmdtable[tableindex] ~= "end") do
                    sasl.logDebug("while loop setvref")
                    P.commandtableentry(COMMAND, "laminar/B738/button/fmc1_" .. P.vrefcmdtable[tableindex])
                    tableindex = tableindex + 1
                end

                P.commandtableentry(TEXT, "V REF " .. appflapscalc .. " " .. appvrefcalc .. " Knots set")
            end
        elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(vref) ~= appvrefcalc) then
                P.commandtableentry(ADVICE, "Set V REF " .. appflapscalc .. " " .. appvrefcalc)
                P.procedureloop3.stepindex = P.procedureloop3.stepindex - 1
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop3.steprepeat) then
                P.commandtableentry(ADVICE, "V REF " .. appflapscalc .. " checked and " .. appvrefcalc)
            end
        end
    elseif (P.procedureloop3.stepindex == 4) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true
end

function setvrefproc()

    if (P.procedureloop3.lock == NOPROCEDURE) then
        P.procedureloop3.lock = SETVREFPROCEDURE
    end

    if (P.flightstate <= 2) then
        P.procedureloop3.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Set V R E F Procedure aborted")
        return true
    end

    return true

end

function setvrefproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        setvrefproc()
    end
    return 0
end

my_command_setvref = sasl.createCommand(definitions.APPNAMEPREFIX .. "/setvref", "Set Landing Flaps/VREF")
sasl.registerCommandHandler(my_command_setvref, 0, setvrefproc_)

--------------------------------------------------------------------------------------------------------------
function settoflapssteps()

    local FMC1Line00L = helpers.get("laminar/B738/fmc1/Line00_L")

    local toflapscalc = determineTakeoffFlapsSetting(P.depmetar.decodedmetar)
    local toflapscalcstring = tostring(toflapscalc)

    if (P.procedureloop3.stepindex == 1) then
        setview(P.configvalues[CONFIGVIEWFMS])
    elseif (P.procedureloop3.stepindex == 2) then
        if ((string.len(FMC1Line00L) < 9) or (string.sub(FMC1Line00L, 7, 13) ~= "TAKEOFF")) then
            helpers.command_once("laminar/B738/button/fmc1_init_ref")
            P.procedureloop3.stepindex = P.procedureloop3.stepindex - 1
        end
    elseif (P.procedureloop3.stepindex == 3) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            if (get(toflapsset) == OFF) then
                P.toflapscmdtable[3] = string.sub(toflapscalcstring, 1, 1)
                P.toflapscmdtable[4] = string.sub(toflapscalcstring, 2, 2)
 
                local tableindex = 1
                while (P.toflapscmdtable[tableindex] ~= "end") do
                    sasl.logDebug("while loop toflaps")
                    P.commandtableentry(COMMAND, "laminar/B738/button/fmc1_" .. P.toflapscmdtable[tableindex])
                    tableindex = tableindex + 1
                end

                P.commandtableentry(TEXT, "Takeoff Flaps " .. toflapscalcstring .. "set")
            end
        elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(toflapsset) == OFF) then
                P.commandtableentry(ADVICE, "Enter Takeoff Flaps " .. toflapscalcstring)
                P.procedureloop3.stepindex = P.procedureloop3.stepindex - 1
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop3.steprepeat) then
                P.commandtableentry(ADVICE, "Takeoff Flaps Entered and " .. toflapscalcstring)
            end
        end
    elseif (P.procedureloop3.stepindex == 4) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true
end

function settoflapsproc()

    if (P.procedureloop3.lock == NOPROCEDURE) then
        P.procedureloop3.lock = SETTOFLAPSPROCEDURE
    end

    if (P.flightstate > 0) then
        P.procedureloop3.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Set Takeoff Flaps Procedure aborted")
        return true
    end

    return true

end

function settoflapsproc_(phase)
    if phase == SASL_COMMAND_BEGIN then
        settoflapsproc()
    end
    return 0
end

my_command_settoflapsproc = sasl.createCommand(definitions.APPNAMEPREFIX .. "/settoflapsproc", "Set Takeoff Flaps")
sasl.registerCommandHandler(my_command_settoflapsproc, 0, settoflapsproc_)

--------------------------------------------------------------------------------------------------------------
function calcautobrake(landingSpeed, weatherData)

    local autobrakeSettings = {
        {maxDeceleration = 1.5, setting = AUTOBRAKE1},
        {maxDeceleration = 2.0, setting = AUTOBRAKE2},
        {maxDeceleration = 3.0, setting = AUTOBRAKE3},
        {maxDeceleration = 4.0, setting = AUTOBRAKEMAX}
    }

    local requiredDeceleration = (landingSpeed^2) / (2 * get(desrwylen))

    if ((fieldexists(weatherData, "weather") and ((containsvalue(weatherData.weather, "FZRA")) or (containsvalue(weatherData.weather, "FZDZ")) or (containsvalue(weatherData.weather, "FZFG"))))
        or (fieldexists(weatherData, "temperature.value") and (weatherData.temperature.value < 1))) then
        requiredDeceleration = requiredDeceleration * 1.5
    elseif (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "SN")))  then
        requiredDeceleration = requiredDeceleration * 1.3
    elseif (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "RA"))) then
        requiredDeceleration = requiredDeceleration * 1.2
    end

    local weightFactor = get(totalweightkgs) / 70000
    requiredDeceleration = requiredDeceleration * weightFactor

    for _, setting in ipairs(autobrakeSettings) do
        if requiredDeceleration <= setting.maxDeceleration then
            return setting.setting
        end
    end

    return AUTOBRAKE1
end

--------------------------------------------------------------------------------------------------------------
function gettrim()

    local trim = 0

    local trimwwheeltemp = get(trimwheel)
    local trimwheelrounded = roundnumber(trimwwheeltemp * -100)

    if (trimwheelrounded <= 21) then
        trim = 6.50
    elseif (trimwheelrounded <= 24) then
        trim = 6.25
    elseif (trimwheelrounded <= 27) then
        trim = 6.0
    elseif (trimwheelrounded <= 30) then
        trim = 5.75
    elseif (trimwheelrounded <= 32) then
        trim = 5.5
    elseif (trimwheelrounded <= 34) then
        trim = 5.25
    elseif (trimwheelrounded <= 40) then
        trim = 5.0
    elseif (trimwheelrounded <= 42) then
        trim = 4.75
    elseif (trimwheelrounded <= 45) then
        trim = 4.5
    elseif (trimwheelrounded <= 48) then
        trim = 4.25
    elseif (trimwheelrounded <= 52) then
        trim = 4.0
    elseif (trimwheelrounded <= 55) then
        trim = 3.75
    elseif (trimwheelrounded <= 58) then
        trim = 3.5
    elseif (trimwheelrounded <= 61) then
        trim = 3.25
    elseif (trimwheelrounded <= 65) then
        trim = 3.0
    else
        trim = 5.0
    end

    return (trim)

end

--------------------------------------------------------------------------------------------------------------

function settotrim(trimvalue)

    local targettrim = 0

    local trimwheelrounded = 0
    local trimwheelcalcrounded = 0

    local trimwwheeltemp = 0
    local trimwheelold = 0

    if (trimvalue == nil)
    then
        targettrim = get(trimcalc)
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

    trimwwheeltemp = get(trimwheel)
    trimwheelrounded = roundnumber(trimwwheeltemp * -100)

    while ((trimwheelrounded ~= trimwheelcalcrounded) and (trimwwheeltemp ~= trimwheelold)) do
        sasl.logDebug("while loop settotrim")
        if (trimwheelrounded > trimwheelcalcrounded) then
            helpers.command_once("laminar/B738/flight_controls/pitch_trim_up")
        else
            if (trimwheelrounded < trimwheelcalcrounded) then
                helpers.command_once("laminar/B738/flight_controls/pitch_trim_down")
            end
        end

        trimwheelold = trimwheeltemp
        trimwwheeltemp = get(trimwheel)
        trimwheelrounded = roundnumber(trimwwheeltemp * -100)

    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function autowiper(state)

    local destwiperpos = 0

    if ((state == nil) or (state == ON)) then
        if (get(rain) <= 0.03) then
            destwiperpos = WIPEROFF
        elseif (get(rain) <= 0.25) then
            destwiperpos = WIPERINT
        elseif (get(rain) <= 0.6) then
            destwiperpos = WIPERLOW
        else
            destwiperpos = WIPERHIGH
        end
    else
        destwiperpos = state
    end

    local lwiperposdiff = math.abs(get(lwiperpos) - destwiperpos)
    local rwiperposdiff = math.abs(get(rwiperpos) - destwiperpos)

    if (get(lwiperpos) < destwiperpos) then
        while (lwiperposdiff > 0) do
            sasl.logDebug("while loop autowiper l up")
            helpers.command_once("laminar/B738/knob/left_wiper_up")
            lwiperposdiff = lwiperposdiff - 1
        end
    elseif (get(lwiperpos) > destwiperpos) then
        while (lwiperposdiff > 0) do
            sasl.logDebug("while loop autowiper l dn")
            helpers.command_once("laminar/B738/knob/left_wiper_dn")
            lwiperposdiff = lwiperposdiff - 1
        end
    end

    if (get(rwiperpos) < destwiperpos) then
        while (rwiperposdiff > 0) do
            sasl.logDebug("while loop autowiper r up")
            helpers.command_once("laminar/B738/knob/right_wiper_up")
            rwiperposdiff = rwiperposdiff - 1
        end
    elseif (get(rwiperpos) > destwiperpos) then
        while (rwiperposdiff > 0) do
            sasl.logDebug("while loop autowiper r dn")
            helpers.command_once("laminar/B738/knob/right_wiper_dn")
            rwiperposdiff = rwiperposdiff - 1
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------

function autocentertanks()

    if ((get(centertanklbs) > 1000) and (get(centertanklpress) > 0) and (get(centertankrpress) > 0) and (get(centertankstat) > 0)) then
        if (get(centertanklswitch) == OFF) then
            set(centertanklswitch, ON)
        end
        if (get(centertankrswitch) == OFF) then
            set(centertankrswitch, ON)
        end
        P.centertankoffset = false
    elseif (((not P.centertankoffset) and (get(centertanklbs) <= 1000)) or ((get(centertanklpress) == 0) and (get(centertankrpress) == 0))) then
        if (get(centertanklswitch) == ON) then
            set(centertanklswitch, OFF)
        end
        if (get(centertankrswitch) == ON) then
            set(centertankrswitch, OFF)
        end
        P.centertankoffset = true
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function setstarter(starter, state)

    local starter1posdiff = math.abs(get(starter1pos) - state)
    local starter2posdiff = math.abs(get(starter2pos) - state)

    if ((state ~= nil) and (starter ~= nil)) then
        if ((starter == ENGINE1) or (starter == BOTH)) then
            if (state > get(starter1pos)) then
                while (starter1posdiff > 0) do
                    sasl.logDebug("while loop eng1 start right")
                    helpers.command_once("laminar/B738/knob/eng1_start_right")
                    starter1posdiff = starter1posdiff - 1
                end
            elseif (state < get(starter1pos)) then
                while (starter1posdiff > 0) do
                    sasl.logDebug("while loop eng1 start left")
                    helpers.command_once("laminar/B738/knob/eng1_start_left")
                    starter1posdiff = starter1posdiff - 1
                end
            end
        end

        if ((starter == ENGINE2) or (starter == BOTH)) then
            if (state > get(starter2pos)) then
                while (starter2posdiff > 0) do
                    sasl.logDebug("while loop eng2 start right")
                    helpers.command_once("laminar/B738/knob/eng2_start_right")
                    starter2posdiff = starter2posdiff - 1
                end
            elseif (state < get(starter2pos)) then
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

function setmmrmode(mmr, state)

    if ((mmr == nil) or (state == nil)) then
        return false
    end

    if ((get(mmrinstalled) == OFF) or ((get(lpvinstalled) == OFF) and ((state == MMRLPV) or (state == MMRGLS)))) then
        return false
    end

    if ((mmr == MMRCAPTAIN) or (mmr == MMRBOTH)) then
        local mmrcptstdbymodediff = math.abs(get(mmrcptstdbymode) - state)

        if ((state == MMRLPV) or (get(mmrcptstdbymode) == MMRLPV)) then
            mmrcptstdbymodediff = mmrcptstdbymodediff - 1
        end

        if (state >= get(mmrcptstdbymode)) then
            while (mmrcptstdbymodediff > 0) do
                sasl.logDebug("while loop mmr1 up")
                helpers.command_once("laminar/B738/push_button/mmr1_mode_up")
                mmrcptstdbymodediff = mmrcptstdbymodediff - 1
            end
        elseif (state < get(mmrcptstdbymode)) then
            while (mmrcptstdbymodediff > 0) do
                sasl.logDebug("while loop mmr1 dn")
                helpers.command_once("laminar/B738/push_button/mmr1_mode_dn")
                mmrcptstdbymodediff = mmrcptstdbymodediff - 1
            end
        end
    end

    if ((mmr == MMRFO) or (mmr == MMRBOTH)) then
        local mmrfostdbymodediff = math.abs(get(mmrfostdbymode) - state)

        if ((state == MMRLPV) or (get(mmrfostdbymode) == MMRLPV)) then
            mmrfostdbymodediff = mmrfostdbymodediff - 1
        end

        if (state >= get(mmrfostdbymode)) then
            while (mmrfostdbymodediff > 0) do
                sasl.logDebug("while loop mmr2 up")
                helpers.command_once("laminar/B738/push_button/mmr2_mode_up")
                mmrfostdbymodediff = mmrfostdbymodediff - 1
            end
        elseif (state < get(mmrfostdbymode)) then
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

function setirs(irs, state)

    result = true

    sasl.logDebug("SETIRS IRS LEFT POS: " .. tostring(get(irsleftpos)) .. " IRS RIGHT POS: " .. tostring(get(irsrightpos)))

    if ((state ~= nil) and (irs ~= nil)) then
        if ((irs == LEFTIRS) or (irs == BOTHIRS)) then
            if (state > get(irsleftpos)) then
                helpers.command_once("laminar/B738/toggle_switch/irs_L_right")
                result = false
            elseif (state < get(irsleftpos)) then
                helpers.command_once("laminar/B738/toggle_switch/irs_L_left")
                result = false
            end
        end

        if ((irs == RIGHTIRS) or (irs == BOTHIRS)) then
            if (state > get(irsrightpos)) then
                helpers.command_once("laminar/B738/toggle_switch/irs_R_right")
                result = false
            elseif (state < get(irsrightpos)) then
                helpers.command_once("laminar/B738/toggle_switch/irs_R_left")
                result = false
            end
        end
    end

    return result
end

--------------------------------------------------------------------------------------------------------------

function enginesrunning(state)

    local running = false

    if ((state == nil) or (state == BOTH)) then
        if ((get(eng1n1percent) ~= nil) and (get(eng2n1percent) ~= nil)) then
            if ((get(eng1n1percent) >= 19) and (get(eng2n1percent) >= 19)) then
                running = true
            end
        end
    elseif (state == ENGINE1) then
        if (get(eng1n1percent) ~= nil) then
            if (get(eng1n1percent) >= 19) then
                running = true
            end
        end
    elseif (state == ENGINE2) then
        if (get(eng2n1percent) ~= nil) then
            if (get(eng2n1percent) >= 19) then
               running = true
            end
        end
    end

    return running

end

--------------------------------------------------------------------------------------------------------------

function setdomelight(state)

    local domelightposdiff = math.abs(get(domelightpos) - state)

    if (state > get(domelightpos)) then
        while (domelightposdiff > 0) do
            sasl.logDebug("while loop dome up")
            helpers.command_once("laminar/B738/toggle_switch/cockpit_dome_up")
            domelightposdiff = domelightposdiff - 1
        end
    elseif (state < get(domelightpos)) then
        while (domelightposdiff > 0) do
            sasl.logDebug("while loop dome dn")
            helpers.command_once("laminar/B738/toggle_switch/cockpit_dome_dn")
            domelightposdiff = domelightposdiff - 1
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function setbankanglepos(state)

    local bankangleposdiff = math.abs(get(bankanglepos) - state)

    if ((state == nil) or (state > BANKANGLEMAX)) then
        return false
    end

    if (state > get(bankanglepos)) then
        while (bankangleposdiff > 0) do
            sasl.logDebug("while loop bank ang up")
            helpers.command_once("laminar/B738/autopilot/bank_angle_up")
            bankangleposdiff = bankangleposdiff - 1
        end
    elseif (state < get(bankanglepos)) then
        while (bankangleposdiff > 0) do
            sasl.logDebug("while loop bank ang dn")
            helpers.command_once("laminar/B738/autopilot/bank_angle_dn")
            bankangleposdiff = bankangleposdiff - 1
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function setautobrake(state)

    if (state == nil) then
        return false
    end

    if ((state == AUTOBRAKERTO) and (get(autobrakepos) ~= AUTOBRAKERTO)) then
        helpers.command_once("laminar/B738/knob/autobrake_rto")
    elseif ((state == AUTOBRAKEOFF) and (get(autobrakepos) ~= AUTOBRAKEOFF)) then
        helpers.command_once("laminar/B738/knob/autobrake_off")
    elseif ((state == AUTOBRAKE1) and (get(autobrakepos) ~= AUTOBRAKE1)) then
        helpers.command_once("laminar/B738/knob/autobrake_1")
    elseif ((state == AUTOBRAKE2) and (get(autobrakepos) ~= AUTOBRAKE2)) then
        helpers.command_once("laminar/B738/knob/autobrake_2")
    elseif ((state == AUTOBRAKE3) and (get(autobrakepos) ~= AUTOBRAKE3)) then
        helpers.command_once("laminar/B738/knob/autobrake_3")
    elseif ((state == AUTOBRAKEMAX) and (get(autobrakepos) ~= AUTOBRAKEMAX)) then
        helpers.command_once("laminar/B738/knob/autobrake_max")
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- setseatbeltsign

function setseatbeltsign(state)

    local seatbeltsignposdiff = math.abs(get(seatbeltsignpos) - state)

    if (state > get(seatbeltsignpos)) then
        while (seatbeltsignposdiff > 0) do
            sasl.logDebug("while loop seat belt dn")
            helpers.command_once("laminar/B738/toggle_switch/seatbelt_sign_dn")
            seatbeltsignposdiff = seatbeltsignposdiff - 1
        end
    elseif (state < get(seatbeltsignpos)) then
        while (seatbeltsignposdiff > 0) do
            sasl.logDebug("while loop seat belt up")
            helpers.command_once("laminar/B738/toggle_switch/seatbelt_sign_up")
            seatbeltsignposdiff = seatbeltsignposdiff - 1
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
-- setnosmokingsign

function setnosmokingsign(state)

    local nosmokingsignposdiff = math.abs(get(nosmokingsignpos) - state)

    if (state > get(nosmokingsignpos)) then
        while (nosmokingsignposdiff > 0) do
            sasl.logDebug("while loop no smoking dn")
            helpers.command_once("laminar/B738/toggle_switch/no_smoking_dn")
            nosmokingsignposdiff = nosmokingsignposdiff - 1
        end
    elseif (state < get(nosmokingsignpos)) then
        while (nosmokingsignposdiff > 0) do
            sasl.logDebug("while loop no smoke up")
            helpers.command_once("laminar/B738/toggle_switch/no_smoking_up")
            nosmokingsignposdiff = nosmokingsignposdiff - 1
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
-- setemergencylights function

function setemergencylights(state)

    local emergencylightsdiff = math.abs(get(emergencylights) - state)

    if (state > get(emergencylights)) then
        while (emergencylightsdiff > 0) do
            sasl.logDebug("while loop exit light dn")
            helpers.command_once("laminar/B738/toggle_switch/emer_exit_lights_dn")
            emergencylightsdiff = emergencylightsdiff - 1
        end
    elseif (state < get(emergencylights)) then
        while (emergencylightsdiff > 0) do
            sasl.logDebug("while loop exit light  up")
            helpers.command_once("laminar/B738/toggle_switch/emer_exit_lights_up")
            emergencylightsdiff = emergencylightsdiff - 1
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
-- Cold and Dark Startup

function coldanddarksteps()

    if (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 2) then
        if (get(battery) == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Battery On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/switch/battery_dn")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Battery checked and On")
        end
    elseif (P.procedureloop1.stepindex == 3) then
        if (get(batteryswitchcover) == OPEN) then
            helpers.command_once("laminar/B738/button_switch_cover02")
        end
    elseif ((P.procedureloop1.stepindex == 4)  and (get(sunpitchdegrees) < 0)) then
        setview(P.configvalues[CONFIGVIEWUPPEROVERHEADPANEL])
    elseif ((P.procedureloop1.stepindex == 5) and (get(sunpitchdegrees) < 0)) then
        if (get(domelightpos) == DOMELIGHTOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Domelight On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                setdomelight(DOMELIGHTDIM)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Domelight checked and On")
        end
    elseif ((P.procedureloop1.stepindex == 6) and (get(sunpitchdegrees) < 0)) then
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 7) then
        if (get(emergencylights) ~= EMERGLIGHTSARMED) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Arm Emergency Lights")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                setemergencylights(EMERGLIGHTSARMED)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Emergency Lights checked and Armed")
        end
    elseif (P.procedureloop1.stepindex == 8) then
        if (get(emergencylightcover) == OPEN) then
            helpers.command_once("laminar/B738/button_switch_cover09")
        end
    elseif (P.procedureloop1.stepindex == 9) then
        if (get(positionlights) ~= POSLIGHTSSTEADY) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Position Lights Steady")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/position_light_steady")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Position Lights checked and Steady")
        end
    elseif (P.procedureloop1.stepindex == 10) then
        if (get(nosmokingsignpos) ~= NOSMOKINGSIGNON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setnosmokingsign(NOSMOKINGSIGNON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set No Smoking Signs On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "No Smoking Signs checked and On")
        end
    elseif (P.procedureloop1.stepindex == 11) then
        if ((P.configvalues[CONFIGUSEGROUNDPOWER] == ON) and (get(gpuavailable) == ON)) then
            if (get(gpuon) == OFF) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Switch Ground Power On")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                else
                    helpers.command_once("laminar/B738/toggle_switch/gpu_dn")
                    P.procedureloop1.stepindex = 19
                    return true
                end
            else
                if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                    P.commandtableentry(ADVICE, "G P U checked and On")
                end
                P.procedureloop1.stepindex = 19
                return true
            end
        end
    elseif (P.procedureloop1.stepindex == 12) then
        if (get(apustarterpos) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Start A P U")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U checked and Started")
        end
    elseif (P.procedureloop1.stepindex == 13) then
        if (P.configvalues[CONFIGVOICEADVICEONLY]  ~= ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            P.commandtableentry(TEXT, "A P U Started")
        end
    elseif (P.procedureloop1.stepindex == 14) then
        if (get(apugenoffbus) == OFF) then
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "A P U Running")
            else
                P.commandtableentry(TEXT, "A P U Running")
            end
        end
    elseif (P.procedureloop1.stepindex == 15) then
        if (not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF))) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Generator On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Generator checked and On")
        end
    elseif (P.procedureloop1.stepindex == 16) then
        if (get(bleedairapupos) == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Bleed Air On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                 helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Bleed Air checked and On")    
        end
    elseif (P.procedureloop1.stepindex == 17) then
        if (get(isolvalvepos)  ~= ISOLVALVEOPEN) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Isolation Valve Open")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEOPEN)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Isolation Valve checked and Open")    
        end
    elseif (P.procedureloop1.stepindex == 18) then
        if ((get(packlpos) ~= PACKAUTO) or (get(packrpos) ~= PACKAUTO)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Packs Auto")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(packlpos, PACKAUTO)
                set(packrpos, PACKAUTO)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Packs checked and Auto")    
        end
    elseif (P.procedureloop1.stepindex == 19) then
        if (get(trimairpos) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Trim Air On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(trimairpos, ON)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Trim Air checked and On")    
        end
    elseif (P.procedureloop1.stepindex == 20) then
        setview(P.configvalues[CONFIGVIEWUPPEROVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 21) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            if not setirs(BOTHIRS, IRSNAV) then 
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        end
    elseif (P.procedureloop1.stepindex == 22) then
        if ((get(irsalignleft) == OFF) or (get(irsalignright) == OFF)) then
            if ((get(irsleftpos) ~= IRSNAV) or (get(irsrightpos) ~= IRSNAV)) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Both I R S to Nav")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Both I R S checked and Nav")
            end
        else
            P.commandtableentry(TEXT, "I R S Alignment Started")
        end
    elseif (P.procedureloop1.stepindex == 23) then
        setview(P.configvalues[CONFIGVIEWFMS])
    elseif (P.procedureloop1.stepindex == 24) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Initialize I R S Position")
        end
        helpers.command_once("laminar/B738/button/fmc1_init_ref")
    elseif (P.procedureloop1.stepindex == 25) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            helpers.command_once("laminar/B738/button/fmc1_next_page")
        end
    elseif (P.procedureloop1.stepindex == 26) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            helpers.command_once("laminar/B738/button/fmc1_4L")
        end
    elseif (P.procedureloop1.stepindex == 27) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            helpers.command_once("laminar/B738/button/fmc1_prev_page")
        end
    elseif (P.procedureloop1.stepindex == 28) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            helpers.command_once("laminar/B738/button/fmc1_4R")
            P.commandtableentry(TEXT, "I R S Position Initialization Complete")
        end
    elseif (P.procedureloop1.stepindex == 29) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true

end

function coldanddarkstartup()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = COLDANDDARKPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Cold and Dark Startup Not Possible Inflight")
        else
            P.commandtableentry(TEXT, "Cold and Dark Startup Not Possible Inflight")
        end
        return true
    end

    if ((get(battery) == ON) and (get(mainbus) == ON)) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Cold and Dark Startup Aborted")
        else
            P.commandtableentry(TEXT, "Cold and Dark Startup Aborted")
        end
        return true
    end

    if (get(apurunning) == ON) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Cold and Dark Startup Aborted, A P U already running")
        else
            P.commandtableentry(TEXT, "Cold and Dark Startup Aborted, A P U already running")
        end
        return true
    end

    if enginesrunning(BOTH) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE,  "Cold and Dark Startup Aborted, Engines already running")
        else
            P.commandtableentry(TEXT,  "Cold and Dark Startup Aborted, Engines already running")
        end
        return true
    end

    return true

end

function coldanddarkstartup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        coldanddarkstartup()
    end
    return 0
end

my_command_coldanddarkstartup = sasl.createCommand(definitions.APPNAMEPREFIX .. "/coldanddarkstartup", "Cold and Dark Startup")
sasl.registerCommandHandler(my_command_coldanddarkstartup, 0, coldanddarkstartup_)
--sasl.appendMenuItem(P.menu_main, "Cold and Dark Startup", coldanddarkstartup)

--------------------------------------------------------------------------------------------------------------
-- APU Startup

function apustartupsteps()

    if (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 2) then
        if (get(apustarterpos) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Start A P U")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U checked and Started")
        end
    elseif (P.procedureloop1.stepindex == 3) then
        if (P.configvalues[CONFIGVOICEADVICEONLY]  ~= ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            P.commandtableentry(TEXT, "A P U Running Up")
        else
            P.commandtableentry(ADVICE, "A P U Running Up")
        end
    elseif (P.procedureloop1.stepindex == 4) then
        if (get(apugenoffbus) == OFF) then 
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "A P U Running")
            else
                P.commandtableentry(TEXT, "A P U Running")
            end
        end
    elseif (P.procedureloop1.stepindex == 5) then
        if (not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF))) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Generator On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Generator checked and On")
        end
    elseif (P.procedureloop1.stepindex == 6) then
        if (get(gpuon) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Ground Power Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/gpu_up")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Ground Power checked and Off")    
        end
    elseif (P.procedureloop1.stepindex == 7) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true

end

function apustartup()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = APUSTARTUPPROCEDURE
    end

    if ((get(battery) == OFF) and (get(mainbus) == OFF)) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "A P U Startup Aborted")
        else
            P.commandtableentry(TEXT, "A P U Startup Aborted")
        end
        return true
    end

    if (get(apurunning) == ON) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "A P U already running")
        else
            P.commandtableentry(TEXT, "A P U already running")
        end
        return true
    end

    return true

end

function apustartup_(phase)
    if phase == SASL_COMMAND_BEGIN then
        apustartup()
    end
    return 0
end

my_command_apustartup = sasl.createCommand(definitions.APPNAMEPREFIX .. "/apustartup", "APU Startup")
sasl.registerCommandHandler(my_command_apustartup, 0, apustartup_)

--------------------------------------------------------------------------------------------------------------
-- Engine Start

function enginestartsteps()

    if (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 2) then
        if (get(beaconlights) == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Collision Lights On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                togglecollisionlights(ON)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Collision lightset checked and On")
        end     
    elseif (P.procedureloop1.stepindex == 3) then
        if ((get(lefttanklswitch) == OFF) or (get(lefttankrswitch) == OFF) or (get(righttanklswitch) == OFF) or (get(righttankrswitch) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Wing Tank Fuel Pumps On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(lefttanklswitch, ON)
                set(lefttankrswitch, ON)
                set(righttanklswitch, ON)
                set(righttankrswitch, ON)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Wing Fuel Tanks checked and On")
        end
    elseif (P.procedureloop1.stepindex == 4) then
        if ((get(packlpos) ~= PACKOFF) or (get(packrpos) ~= PACKOFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Packs Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(packlpos, PACKOFF)
                set(packrpos, PACKOFF)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Packs checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 5) then
        if (get(bleedairapupos) == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set A P U Bleed Air On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Bleed Air checked and On")
        end 
    elseif (P.procedureloop1.stepindex == 6) then
        if (get(isolvalvepos)  ~= ISOLVALVEOPEN) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Isolation Valve Open")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEOPEN)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Isolation Valve checked and Open")
        end 
    elseif (P.procedureloop1.stepindex == 7) then
        if (get(starter2pos) ~= GROUND) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Starter 2 Ground")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                setstarter(ENGINE2, GROUND)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Engine 2 Starter checked and On")
        end
    elseif (P.procedureloop1.stepindex == 8) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 9) then
        if (get(eng2n2percent) < 25) then
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Engine 2 N 2 at 25 Percent")
            else
                P.commandtableentry(TEXT, "Engine 2 N 2 at 25 Percent")
            end
        end
    elseif (P.procedureloop1.stepindex == 10) then
        setview(P.configvalues[CONFIGVIEWTHROTTLE])
    elseif (P.procedureloop1.stepindex == 11) then
        if (get(mixture2pos) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Engine 2 Fuel Lever Idle")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
               helpers.command_once("laminar/B738/engine/mixture2_idle")
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Engine 2 Fuel Lever checked and Idle")
        end
    elseif (P.procedureloop1.stepindex == 12) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 13) then
        if not enginesrunning(ENGINE2) then
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Engine 2 Running")
            else
                P.commandtableentry(TEXT, "Engine 2 Running")
            end
        end
    elseif (P.procedureloop1.stepindex == 14) then
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 15) then
        if (get(starter1pos) ~= GROUND) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Starter 1 Ground")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                setstarter(ENGINE1, GROUND)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Engine 1 Starter checked and Ground")
        end
    elseif (P.procedureloop1.stepindex == 16) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 17) then
        if (get(eng1n2percent) < 25) then
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Engine 1 N 2 at 25 Percent")
            else
                P.commandtableentry(TEXT, "Engine 1 N 2 at 25 Percent")
            end
        end
    elseif (P.procedureloop1.stepindex == 18) then
        setview(P.configvalues[CONFIGVIEWTHROTTLE])
    elseif (P.procedureloop1.stepindex == 19) then
        if (get(mixture1pos) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Engine 1 Fuel Lever Idle")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
               helpers.command_once("laminar/B738/engine/mixture1_idle")
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Engine 1 Fuel Lever checked and Idle")
        end
    elseif (P.procedureloop1.stepindex == 20) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 21) then
        if not enginesrunning(ENGINE1) then
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Engine 1 Running")
            else
                P.commandtableentry(TEXT, "Engine 1 Running")
            end
        end
    elseif (P.procedureloop1.stepindex == 22) then
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 23) then
        if ((get(gen1pos) ~= ON) or (get(gen2pos) ~= ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Both Generators On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if (get(gen1pos) ~= ON) then
                    helpers.command_once("laminar/B738/toggle_switch/gen1_dn")
                end
                if (get(gen2pos) ~= ON) then
                    helpers.command_once("laminar/B738/toggle_switch/gen2_dn")
                end
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Generators checked and Ground")
        end
    elseif (P.procedureloop1.stepindex == 24) then
        if ((get(hydro1pos) ~= ON) or (get(hydro2pos) ~= ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Both Hydraulic Pumps On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(hydro1pos, ON)
                set(hydro2pos, ON)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Hydraulic Pumps checked and On")
        end
    elseif (P.procedureloop1.stepindex == 25) then
        if ((get(elechydro1pos) ~= ON) or (get(elechydro2pos) ~= ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Both Electrical Hydraulic Pumps On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(elechydro1pos, ON)
                set(elechydro2pos, ON)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Electrical Hydraulic Pumps checked and On")
        end
    elseif (P.procedureloop1.stepindex == 26) then
        if ((get(bleedair1pos) == OFF) or (get(bleedair2pos) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Engine Bleed Air On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if (get(bleedair1pos) == OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(bleedair2pos) == OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Engine Bleed Air checked and On")
        end
    elseif (P.procedureloop1.stepindex == 27) then
        if ((get(packlpos) ~= PACKAUTO) or (get(packrpos) ~= PACKAUTO)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Packs Auto")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(packlpos, PACKAUTO)
                set(packrpos, PACKAUTO)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Packs checked and Auto")
        end
    elseif (P.procedureloop1.stepindex == 28) then
         if (get(isolvalvepos)  ~= ISOLVALVEAUTO) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Isolation Valve Auto")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEAUTO)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Isolation Valvechecked and Auto")
        end 
    elseif (P.procedureloop1.stepindex == 29) then
         if (get(trimairpos) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Trim Air On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(trimairpos, ON)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Trim Air checked and On")
        end 
    elseif (P.procedureloop1.stepindex == 30) then
        if (get(bleedairapupos) ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Bleed Air Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                 helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Bleed Air checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 31) then
        if (get(apustarterpos) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch APU Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 32) then
        if (get(yawdamperswitch) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Yaw Damper On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(yawdamperswitch, ON)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Yaw Damper checked and On")
        end 
    elseif (P.procedureloop1.stepindex == 33) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true

end

function enginestart()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = ENGINESTARTPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Engine Start Not Possible Inflight")
        else
            P.commandtableentry(TEXT, "Engine Start Not Possible Inflight")
        end
        return true
    end

    if (get(apurunning) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Engine Start Not Possible, A P U not running")
        else
            P.commandtableentry(TEXT, "Engine Start Not Possible, A P U not running")
        end
        return true
    end

    if enginesrunning(BOTH) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Engine Start Aborted, Engines already running")
        else
            P.commandtableentry(TEXT, "Engine Start Aborted, Engines already running")
        end
        return true
    end

    return true

end

function enginestart_(phase)
    if phase == SASL_COMMAND_BEGIN then
        enginestart()
    end
    return 0
end

my_command_enginestart = sasl.createCommand(definitions.APPNAMEPREFIX .. "/enginestart", "Engine Startup")
sasl.registerCommandHandler(my_command_enginestart, 0, enginestart_)

--------------------------------------------------------------------------------------------------------------
-- Engine Shutdown

function engineshutdownsteps()

    if (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 2) then
        if (P.procedureloop1.lock == TURNAROUNDENGINESHUTDOWNPROCEDURE) then
            if ((P.configvalues[CONFIGUSEGROUNDPOWER] == ON) and (get(gpuavailable) == ON)) then
                if (get(gpuon) == OFF) then
                    if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        P.commandtableentry(ADVICE, "Switch Ground Power On")
                        P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                    else
                        helpers.command_once("laminar/B738/toggle_switch/gpu_dn")
                        P.procedureloop1.stepindex = 9
                        return true
                    end
                else
                    if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                        P.commandtableentry(ADVICE, "Ground Power checked and On")
                    end 
                    P.procedureloop1.stepindex = 9
                    return true
                end
            end
        elseif (P.procedureloop1.lock == FINALENGINESHUTDOWNPROCEDURE) then
            P.procedureloop1.stepindex = 9
            return true
        end
    elseif (P.procedureloop1.stepindex == 3) then
        if (get(apustarterpos)~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Start A P U")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U checked and Started")
        end
    elseif (P.procedureloop1.stepindex == 4) then
        if (P.configvalues[CONFIGVOICEADVICEONLY]  ~= ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            P.commandtableentry(TEXT, "A P U Running Up")
        else
            P.commandtableentry(ADVICE, "A P U Running Up")
        end
    elseif (P.procedureloop1.stepindex == 5) then
        if (get(apugenoffbus) == OFF) then 
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "A P U Running")
            else
                P.commandtableentry(TEXT, "A P U Running")
            end
        end
    elseif (P.procedureloop1.stepindex == 6) then
        if (not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF))) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Generator On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Generator checked and On")
        end
    elseif (P.procedureloop1.stepindex == 7) then
        if (get(bleedairapupos) == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Bleed Air On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                 helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Bleed Air checked and On")    
        end
    elseif (P.procedureloop1.stepindex == 8) then
        if (get(isolvalvepos)  ~= ISOLVALVEOPEN) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Isolation Valve Open")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEOPEN)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Isolation Valve checked and Open")    
        end
    elseif (P.procedureloop1.stepindex == 9) then
        setview(P.configvalues[CONFIGVIEWTHROTTLE])
    elseif (P.procedureloop1.stepindex == 10) then
        if ((get(mixture1pos) ~= OFF) or (get(mixture2pos) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Engine Fuel Levers Cutoff")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if (get(mixture2pos) ~= OFF) then
                    helpers.command_once("laminar/B738/engine/mixture2_cutoff")
                end
                if (get(mixture1pos) ~= OFF) then
                    helpers.command_once("laminar/B738/engine/mixture1_cutoff")
                end
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Fuel Levers checked and Cutoff")
        end
    elseif (P.procedureloop1.stepindex == 11) then
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 12) then
        if ((get(centertanklswitch) == ON) or (get(centertankrswitch) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Center Tank Fuel Pumps Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(centertanklswitch, OFF)
                set(centertankrswitch, OFF)
            end      
        end
    elseif (P.procedureloop1.stepindex == 13) then
        if ((get(lefttanklswitch) == ON) or (get(lefttankrswitch) == ON)  or (get(righttanklswitch) == ON) or (get(righttankrswitch) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Wing Tank Fuel Pumps Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(lefttanklswitch, OFF)
                set(leftttankrswitch, OFF)
                set(righttanklswitch, OFF)
                set(righttankrswitch, OFF)
            end
        end
    elseif (P.procedureloop1.stepindex == 14) then
        if ((get(hydro1pos) ~= OFF) or (get(hydro2pos) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Both Hydraulic Pumps Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(hydro1pos, OFF)
                set(hydro2pos, OFF)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Hydraulic Pumps checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 15) then
        if ((get(elechydro1pos) ~= OFF) or (get(elechydro2pos) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Both Electrical Hydraulic Pumps Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(elechydro1pos, OFF)
                set(elechydro2pos, OFF)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Electrical Hydraulic Pumps checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 16) then
      if (get(beaconlights) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Collision Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                togglecollisionlights(OFF)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Collision lightset checked and Off")
        end    
    elseif (P.procedureloop1.stepindex == 17) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true

end

function turnaroundengineshutdown()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = TURNAROUNDENGINESHUTDOWNPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Engine Shutdown Not Possible Inflight")
        else
            P.commandtableentry(TEXT, "Engine Shutdown Not Possible Inflight")
        end
        return true
    end

    if not enginesrunning(BOTH) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Engine Start Aborted, Engines not running")
        else
            P.commandtableentry(TEXT, "Engine Start Aborted, Engines not running")
        end
        return true
    end

    return true

end

function turnaroundengineshutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        turnaroundengineshutdown()
    end
    return 0
end

my_command_turnaroundengineshutdown = sasl.createCommand(definitions.APPNAMEPREFIX .. "/turnaroundengineshutdown", "Engine Shutdown Turnaround")
sasl.registerCommandHandler(my_command_turnaroundengineshutdown, 0, turnaroundengineshutdown_)

function finalengineshutdown()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = FINALENGINESHUTDOWNPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Engine Shutdown Not Possible Inflight")
        return true
    end

    if not enginesrunning(BOTH) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Engine Shutdown Aborted, Engines not Running")
        return true
    end

    return true

end

function finalengineshutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        finalengineshutdown()
    end
    return 0
end

my_command_finalengineshutdown = sasl.createCommand(definitions.APPNAMEPREFIX .. "/finalengineshutdown", "Final Engine Shutdown")
sasl.registerCommandHandler(my_command_finalengineshutdown, 0, finalengineshutdown_)

--------------------------------------------------------------------------------------------------------------
-- Shutdown

function shutdownsteps()

    if (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWUPPEROVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 2) then
        if ((get(irsleftpos) ~= IRSOFF) or (get(irsrightpos) ~= IRSOFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON)  then
                P.commandtableentry(ADVICE, "Set Both I R S Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if not setirs(BOTHIRS, IRSNAV) then 
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both I R S checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 3) then
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 4) then
        if (get(yawdamperswitch) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Yaw Damper Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(yawdamperswitch, OFF)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Yaw Damper checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 5) then
        if (get(bleedairapupos) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Bleed Air Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                 helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Bleed Air checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 6) then
        if (get(isolvalvepos)  ~= ISOLVALVEAUTO) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Isolation Valve Auto")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEAUTO)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Isolation Valve checked and Auto")
        end 
    elseif (P.procedureloop1.stepindex == 7) then
        if ((get(packlpos) ~= PACKOFF) or (get(packrpos) ~= PACKOFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Packs Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(packlpos, PACKOFF)
                set(packrpos, PACKOFF)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Packs checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 8) then
        if ((get(bleedair1pos) == ON) or (get(bleedair2pos) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Engine Bleed Air Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if (get(bleedair1pos) == ON) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(bleedair2pos) == ON) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Engine Bleed Air checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 9) then
        if (get(trimairpos) ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Trim Air Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(trimairpos, OFF) 
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Trim Air checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 10) then
        if ((get(wheatlfwdpos) ~= OFF) or (get(wheatrfwdpos) ~= OFF) or (get(wheatlsidepos) ~= OFF) or (get(wheatrsidepos) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglewindowheat(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Window Heat Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Window Heat checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 11) then
        if (P.configvalues[CONFIGUSEGROUNDPOWER] == ON) then
            if (get(gpuon) == ON) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Switch Ground Power Off")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                else
                    helpers.command_once("laminar/B738/toggle_switch/gpu_up")
                    P.procedureloop1.stepindex = 13
                    return true
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Ground Power checked and Off")
                P.procedureloop1.stepindex = 13
                return true
            end
        end
    elseif (P.procedureloop1.stepindex == 12) then
        if (((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or ((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF))) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Generator Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_up")
                end
                if ((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_up")
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Generator checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 13) then
        if (get(apustarterpos) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "A P U checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 14) then
        if (get(positionlights) ~= POSLIGHTSOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Position Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                togglepositionlights(POSLIGHTSOFF)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Position LIghts checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 15) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNOFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Seatbeltsigns Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Seatbeltsigns checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 16) then
        if (get(nosmokingsignpos) ~= NOSMOKINGSIGNOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setnosmokingsign(NOSMOKINGSIGNOFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set No Smoking Signs Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "NO Smoking Signs checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 17) then
        if (get(emergencylightcover) == CLOSED) then
            helpers.command_once("laminar/B738/button_switch_cover09")
        end
    elseif (P.procedureloop1.stepindex == 18) then
        if (get(emergencylights) ~= EMERGLIGHTSOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Emergency Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                setemergencylights(EMERGLIGHTSOFF)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Emergency Lights checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 19) then
        setview(P.configvalues[CONFIGVIEWUPPEROVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 20) then
        if (get(domelightpos) ~= DOMELIGHTOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setdomelight(DOMELIGHTOFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Domelight OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Domelight checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 21) then
       setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 22) then
        if (get(batteryswitchcover) == CLOSED) then
            helpers.command_once("laminar/B738/button_switch_cover02")
        end
    elseif (P.procedureloop1.stepindex == 23) then
        if (get(battery) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Battery OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/switch/battery_up")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Battery checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 24) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true

end

function shutdown()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = SHUTDOWNPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = SHUTDOWNPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Shutdown Not Possible Inflight")
        else
            P.commandtableentry(TEXT, "Shutdown Not Possible Inflight")
        end
        return true
    end

    if ((get(battery) == OFF) and (get(mainbus) == OFF)) then
        P.procedureloop1.lock = SHUTDOWNPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Shutdown Aborted")
        else
            P.commandtableentry(TEXT, "Shutdown Aborted")
        end
        return true
    end

    return true

end

function shutdown_(phase)
    if phase == SASL_COMMAND_BEGIN then
        shutdown()
    end
    return 0
end

my_command_shutdown = sasl.createCommand(definitions.APPNAMEPREFIX .. "/shutdown", "Shutdown")
sasl.registerCommandHandler(my_command_shutdown, 0, shutdown_)

--------------------------------------------------------------------------------------------------------------
-- teststeps

function teststeps()

    if (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWTHROTTLE])
    elseif (P.procedureloop1.stepindex == 2) then
        helpers.command_begin("laminar/B738/toggle_switch/fire_test_lft")
    elseif (P.procedureloop1.stepindex == 4) then
        helpers.command_end("laminar/B738/toggle_switch/fire_test_lft")
    elseif (P.procedureloop1.stepindex == 5) then
        helpers.command_begin("laminar/B738/toggle_switch/fire_test_rgt")
    elseif (P.procedureloop1.stepindex == 6) then
        helpers.command_end("laminar/B738/toggle_switch/fire_test_rgt")
    elseif (P.procedureloop1.stepindex == 7) then
        helpers.command_begin("laminar/B738/toggle_switch/exting_test_lft")
    elseif (P.procedureloop1.stepindex == 8) then
        helpers.command_end("laminar/B738/toggle_switch/exting_test_lft")
    elseif (P.procedureloop1.stepindex == 9) then
        helpers.command_begin("laminar/B738/toggle_switch/exting_test_rgt")
    elseif (P.procedureloop1.stepindex == 10) then
        helpers.command_end("laminar/B738/toggle_switch/exting_test_rgt")
    elseif (P.procedureloop1.stepindex == 11) then
        helpers.command_begin("laminar/B738/push_button/cargo_fire_test_push")
    elseif (P.procedureloop1.stepindex == 12) then
        helpers.command_end("laminar/B738/push_button/cargo_fire_test_push")
    elseif (P.procedureloop1.stepindex == 13) then
        setview(P.configvalues[CONFIGVIEWUPPEROVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 14) then
        helpers.command_begin("laminar/B738/push_button/flaps_test")
    elseif (P.procedureloop1.stepindex == 15) then
        helpers.command_end("laminar/B738/push_button/flaps_test")
    elseif (P.procedureloop1.stepindex == 16) then
        helpers.command_begin("laminar/B738/push_button/mach_warn1_test")
    elseif (P.procedureloop1.stepindex == 17) then
        helpers.command_end("laminar/B738/push_button/mach_warn1_test")
    elseif (P.procedureloop1.stepindex == 18) then
        helpers.command_begin("laminar/B738/push_button/mach_warn2_test")
    elseif (P.procedureloop1.stepindex == 19) then
        helpers.command_end("laminar/B738/push_button/mach_warn2_test")
    elseif (P.procedureloop1.stepindex == 20) then
        helpers.command_begin("laminar/B738/push_button/stall_test1_press")
    elseif (P.procedureloop1.stepindex == 21) then
        helpers.command_end("laminar/B738/push_button/stall_test1_press")
    elseif (P.procedureloop1.stepindex == 22) then
        helpers.command_begin("laminar/B738/push_button/stall_test2_press")
    elseif (P.procedureloop1.stepindex == 23) then
        helpers.command_end("laminar/B738/push_button/stall_test1_press")
    elseif (P.procedureloop1.stepindex == 24) then
       setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 25) then
        helpers.command_begin("laminar/B738/toggle_switch/window_ovht_test_up")
    elseif (P.procedureloop1.stepindex == 26) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_up")
    elseif (P.procedureloop1.stepindex == 27) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_up")
    elseif (P.procedureloop1.stepindex == 28) then
        helpers.command_begin("laminar/B738/toggle_switch/window_ovht_test_dn")
    elseif (P.procedureloop1.stepindex == 29) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_dn")
    elseif (P.procedureloop1.stepindex == 30) then
        helpers.command_begin("laminar/B738/push_button/tat_test")
    elseif (P.procedureloop1.stepindex == 31) then
        helpers.command_end("laminar/B738/push_button/tat_test")
    elseif (P.procedureloop1.stepindex == 32) then
        helpers.command_begin("laminar/B738/push_button/duct_ovht_test")
    elseif (P.procedureloop1.stepindex == 33) then
        helpers.command_end("laminar/B738/push_button/duct_ovht_test")
    elseif (P.procedureloop1.stepindex == 34) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 35) then
        helpers.command_once("laminar/B738/toggle_switch/bright_test_up")
    elseif (P.procedureloop1.stepindex == 36) then
        helpers.command_once("laminar/B738/toggle_switch/bright_test_dn")
    elseif (P.procedureloop1.stepindex == 37) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test1_up")
    elseif (P.procedureloop1.stepindex == 38) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test1_up")
    elseif (P.procedureloop1.stepindex == 39) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test1_dn")
    elseif (P.procedureloop1.stepindex == 40) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test1_dn")
    elseif (P.procedureloop1.stepindex == 41) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test2_up")
    elseif (P.procedureloop1.stepindex == 42) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test2_up")
    elseif (P.procedureloop1.stepindex == 43) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test2_dn")
    elseif (P.procedureloop1.stepindex == 44) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test2_dn")
    elseif (P.procedureloop1.stepindex == 45) then
        setview(P.configvalues[CONFIGVIEWPEDESTAL])
    elseif (P.procedureloop1.stepindex == 46) then
        helpers.command_once("laminar/B738/knob/transponder_tcas_test")
    elseif (P.procedureloop1.stepindex == 47) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true

end

function test()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = TESTPROCEDURE
    end

    if ((get(battery) == OFF) and (get(mainbus) == OFF)) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Test Aborted Battery is Off")
        return true
    end

    P.commandtableentry(TEXT, "Test")

    return true

end

function test_(phase)
    if phase == SASL_COMMAND_BEGIN then
        test()
    end
    return 0
end

my_command_test = sasl.createCommand(definitions.APPNAMEPREFIX .. "/test", "Tests")
sasl.registerCommandHandler(my_command_test, 0, test_)

--------------------------------------------------------------------------------------------------------------
-- cockpitinitsteps function

function cockpitinitsteps()

    if (P.procedureloop1.stepindex == 1) then
        if (get(sunpitchdegrees) < 0) then
            if (get(domelightpos) == DOMELIGHTOFF) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Dome Light On")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                else
                    setdomelight(DOMELIGHTDIM)
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Dome light checked and On")
            end
        end
    elseif (P.procedureloop1.stepindex == 2) then
        if (P.configvalues[CONFIGHIDEEFBS] == ON) then
            hideefb = false
            if (get(hidecptefb) == OFF) then
                helpers.command_once("laminar/B738/tab/toggle")
                hideefb = true
            end
            if (get(hidefoefb) == OFF) then
                helpers.command_once("laminar/B738/tab/fo_toggle")
                hideefb = true
            end
            if hideefb then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "E F B S Hidden")
                else
                    P.commandtableentry(TEXT, "E F B S Hidden")
                end
            end
        end
    elseif ((P.procedureloop1.stepindex == 3) and ((P.configvalues[CONFIGIGNOREALLBRIGHTHNESSSETTINGS] == OFF))) then      
        if setcockpitlights() then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Instrument Lights set")
            else
                P.commandtableentry(TEXT, "Instrument Lights set")
            end
        end
    elseif (P.procedureloop1.stepindex == 4) then
        if (P.configvalues[CONFIGLOWERDU] == ON) then
            local lowerduset = OFF
            if (get(lowerdupage) == 0) then
                lowerduset = ON
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
            else
                if (get(lowerdupage) == 1) then
                    P.lowerduset = ON
                    helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
                end
            end

            if (get(lowerdupage2) ~= 1) then
                lowerduset = ON
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_SYS")
            end

            if (lowerduset == ON) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Lower Display Unit Pages Set")
                else
                    P.commandtableentry(TEXT, "Lower Display Unit Pages Set")
                end
                lowerduset = OFF
            end
        end
    elseif (P.procedureloop1.stepindex == 5) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Reset F M C")
        else
            helpers.command_once("laminar/B738/button/reset_fmc")
            P.commandtableentry(TEXT, "F M C Reset Done")
        end
    elseif (P.procedureloop1.stepindex == 6) then
        if (P.configvalues[CONFIGTRANSPONDER] ~= 0) then
            if (get(transpondercode) ~= P.configvalues[CONFIGTRANSPONDER]) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    set(transpondercode, P.configvalues[CONFIGTRANSPONDER])
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Transponder Code " .. addspaces(P.configvalues[CONFIGTRANSPONDER]))
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Transponder Code checked and " .. addspaces(P.configvalues[CONFIGTRANSPONDER]))
            end
        end
    elseif (P.procedureloop1.stepindex == 7) then
        if (get(transponderpos) ~= STANDBY) then
            if (P.configvalues[CONFIGTRANSPONDER] ~= 0) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    toggletransponder(STANDBY)
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Transponder Standby")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Transponder checked and Standby")
        end
    elseif (P.procedureloop1.stepindex == 8) then
        if ((get(captainprobepos) ~= OFF) or (get(foprobepos) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggleprobeheat(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Probe Heat OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Probe Heat checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 9) then
        setnosmokingsign(NOSMOKINGSIGNON)
    elseif (P.procedureloop1.stepindex == 10) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNOFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Seatbelt Signs Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Seatbelt Signs checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 11) then
        if (get(nosmokingsignpos) ~= NOSMOKINGSIGNON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setnosmokingsign(NOSMOKINGSIGNON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set No Smoking Signs On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "No Smoking Signs checked and On")
        end
    elseif (P.procedureloop1.stepindex == 12) then
        if(get(positionlights) ~= POSLIGHTSSTEADY) then 
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglepositionlights(POSLIGHTSSTEADY)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Position Lights Steady")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Position Lights checked and Steady")
        end
    elseif (P.procedureloop1.stepindex == 13) then
        if ((get(llights1) ~= OFF) or (get(llights2) ~= OFF) or (get(llights3) ~= OFF) or (get(llights4) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Landing Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Landing Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 14) then
        if ((get(rwylightl) == ON) or (get(rwylightl) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglerwylights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Runway Turnoff Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Runway Turnoff Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 15) then
        if (get(taxilight)  ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Taxi Lights OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Taxi Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 16) then
        if (get(apdiscpos) == ON) then
            helpers.command_once("laminar/B738/autopilot/disconnect_toggle")
        end
    elseif (P.procedureloop1.stepindex == 17) then
        if ((get(fdpilotpos) == ON) or (get(fdfopos) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglefds(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Flight Directors OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Flight Directors checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 18) then
        if (get(mcpaltitude) ~= P.lowerairspacealt) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(mcpaltitude, P.lowerairspacealt)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set M C P ALtitude " .. tostring(P.lowerairspacealt))
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "M C P ALtitude checked and " .. tostring(P.lowerairspacealt))
        end
    elseif (P.procedureloop1.stepindex == 19) then
        if (get(bankanglepos) ~= P.configvalues[CONFIGBANKANGLEMAX]) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setbankanglepos(P.configvalues[CONFIGBANKANGLEMAX])
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Bank Angle " .. getbankanglestring(P.configvalues[CONFIGBANKANGLEMAX]))
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Bank Angle checked and " .. getbankanglestring(P.configvalues[CONFIGBANKANGLEMAX]))
        end
    elseif (P.procedureloop1.stepindex == 20) then
        if (get(efisdatapilotpos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/data_press")
        end
        if (get(efisdatafopos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/data_press")
        end
    elseif (P.procedureloop1.stepindex == 21) then
        if (get(aponstat) == ON) then
            set(aponstat, OFF)
        end
    elseif (P.procedureloop1.stepindex == 22) then
        if ((not enginesrunning(BOTH)) and ((get(mixture1pos) ~= OFF) or (get(mixture2pos) ~= OFF))) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Engine Fuel Levers Cutoff")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                if (get(mixture2pos) ~= OFF) then
                    helpers.command_once("laminar/B738/engine/mixture2_cutoff")
                end
                if (get(mixture1pos) ~= OFF) then
                    helpers.command_once("laminar/B738/engine/mixture1_cutoff")
                end
            end
        end
    elseif (P.procedureloop1.stepindex == 23) then
        speedbrakeleverrounded = roundnumber(get(speedbrakelever), 1)
        if (speedbrakeleverrounded ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(speedbrakelever, OFF)
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Retract Speed Brakes")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end 
        end
    elseif (P.procedureloop1.stepindex == 24) then
        helpers.command_once("laminar/B738/push_button/master_caution1")
        helpers.command_once("laminar/B738/button/fmc1_clr")
    end

    return true

end

function cockpitinit()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = COCKPITINITPROCEDURE
    end

    if ((get(battery) == OFF) and (get(mainbus) == OFF)) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Cockpit Initialization Aborted, Cockpit is Cold and Dark")
        else
            P.commandtableentry(TEXT, "Cockpit Initialization Aborted, Cockpit is Cold and Dark")
        end
        return true
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Cockpit Initialization Not Possible Inflight")
        else
            P.commandtableentry(TEXT, "Cockpit Initialization Not Possible Inflight")
        end
        return true
    end

    if (get(parkingbrakepos) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Cockpit Initialization Not Possible, Parking brake must be set")
        else
            P.commandtableentry(TEXT, "Cockpit Initialization Not Possible, Parking brake must be set")
        end
        return true
    end

    return true

end

function cockpitinit_(phase)
    if phase == SASL_COMMAND_BEGIN then
        cockpitinit()
    end
    return 0
end

my_command_cockpitinit = sasl.createCommand(definitions.APPNAMEPREFIX .. "/cockpitinit", "Cockpit Initialization")
sasl.registerCommandHandler(my_command_cockpitinit, 0, cockpitinit_)

--------------------------------------------------------------------------------------------------------------
-- aftertakeoffsteps function

function aftertakeoffsteps()

    if (P.procedureloop2.stepindex == 1) then
        if (get(radioaltitude) > 200) then
            if (get(gearhandlepos) == GEARDOWN) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Gear Up")
                    P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
                else
                    set(gearhandlepos, GEARUP)
                end
            elseif ((get(gearhandlepos) == GEARDOWN) and (P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Gear checked and Up")
            end  
        else
            P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
        end
    elseif (P.procedureloop2.stepindex == 2) then
        if ((get(gearhandlepos) == GEARUP) and (get(lgeardeployed) == 0) and (get(ngeardeployed) == 0) and (get(rgeardeployed) == 0)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Gear Lever Off")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            else
                set(gearhandlepos, GEAROFF)
            end
        elseif ((get(gearhandlepos) == GEAROFF) and (P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Gear Lever checked and Off")
        elseif (get(gearhandlepos) ~= GEAROFF) then
            P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
        end
    elseif (P.procedureloop2.stepindex == 3) then
        if (get(autobrakepos) ~= AUTOBRAKEOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Auto Brake Off")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            else
                setautobrake(AUTOBRAKEOFF)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
            P.commandtableentry(ADVICE, "Auto Brake checked and Off")
        end  
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
-- altituedea10000steps function

function altitudea10000steps()

   if (P.procedureloop1.stepindex == 1) then
        if (get(altitude) < (P.lowerairspacealt + 1000)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Passing " .. P.lowerairspacealt .. " Feet")
            else
                P.commandtableentry(TEXT, "Passing " .. P.lowerairspacealt .. " Feet")
            end
        end
    elseif (P.procedureloop1.stepindex == 2) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 3) then
        if ((get(llights1) ~= OFF) or (get(llights2) ~= OFF) or (get(llights3) ~= OFF) or (get(llights4) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Landing Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Landing Lights checked and Off")
        end  
    elseif (P.procedureloop1.stepindex == 4) then
        if (get(logolighton) ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelogolight(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Logo Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Logo Lights checked and Off")
        end 
    elseif (P.procedureloop1.stepindex == 5) then     
        if (get(seatbeltsignpos) ~= SEATBELTSIGNOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNOFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Seatbeltsigns Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Seatbelt Signs checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 6) then
        if (get(starterauto) == ON) then
            if ((get(starter1pos) ~= AUTO) or (get(starter2pos) ~= AUTO)) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    setstarter(BOTH, AUTO)
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Both Starters Auto")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end 
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Both Starters checked and Auto")
            end
        else
            if ((get(starter1pos) ~= CONT) or (get(starter2pos) ~= CONT)) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    setstarter(BOTH, CONT)
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Both Starters Continuous")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end 
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Both Starters checked and Continuous")
            end
        end
    elseif (P.procedureloop1.stepindex == 7) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return false

end

function altitudea10000()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = ALTITUDEA10000PROCEDURE
    end

    if (get(airgroundsensor) == ON) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Above 10000 Procedure not possible on Ground")
        return true
    end

    if P.proceduretable[ALTITUDEA10000PROCEDURE].set then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Above 10000 Procedure already done")
        return true
    end

    if (get(altitude) < P.lowerairspacealt) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Above 10000 Procedure only possible above lower Airspace Altitude")
        return true
    end

    if (P.flightstate > 2) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Above 10000 Procedure only possible during Climb")
        return true
    end

    return true

end

function altitudea10000_(phase)
    if phase == SASL_COMMAND_BEGIN then
        altitudea10000()
    end
    return 0
end

my_command_altitudea10000 = sasl.createCommand(definitions.APPNAMEPREFIX .. "/altitudea10000", "Above 10000")
sasl.registerCommandHandler(my_command_altitudea10000, 0, altitudea10000_)

--------------------------------------------------------------------------------------------------------------
-- duringclimbsteps function

function duringclimbsteps()

    if (P.procedureloop2.stepindex == 1) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            setdomelight(DOMELIGHTOFF)
        end
    elseif (P.procedureloop2.stepindex == 2) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            if (get(altitude) < P.lowerairspacealt) then
                togglelandinglights(ON)
            end
        end
    elseif (P.procedureloop2.stepindex == 3) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            togglepositionlights(POSLIGHTSSTROBE)
        end
    elseif (P.procedureloop2.stepindex == 4) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            togglerwylights(OFF)
        end
    elseif (P.procedureloop2.stepindex == 5) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            toggletaxilights(OFF)
        end
    elseif (P.procedureloop2.stepindex == 6) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            if (P.configvalues[CONFIGTRANSPONDER] ~= 0) then
                toggletransponder(TARA)
            end
        end
    elseif (P.procedureloop2.stepindex == 7) then
        if (get(altitude) > get(fmctransalt)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Passing Transition Altitude")
            else
                P.commandtableentry(TEXT, "Passing Transition Altitude")
            end
        else
            P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
        end
    elseif (P.procedureloop2.stepindex == 8) then
        if (P.configvalues[CONFIGAUTOBARO] == ON) then
            if (get(altitude) > get(fmctransalt)) then 
                if (get(barostd) == OFF) then
                    if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                        helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
                    elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        P.commandtableentry(ADVICE, "Set Q N H to Standard")
                        P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
                    end
                elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                    P.commandtableentry(ADVICE, "Q N H checked and Standard")
                end
            else
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            end
        end
    elseif (P.procedureloop2.stepindex == 9) then
        if ((get(bleedair1pos) == OFF) or (get(bleedair2pos) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Engine Bleed Air On")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            else
                if (get(bleedair1pos) == OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(bleedair2pos) == OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
            P.commandtableentry(ADVICE, "Both Engine Bleed Air checked and On")
        end 
    elseif (P.procedureloop2.stepindex == 10) then
        if ((get(packlpos) == PACKOFF) or (get(packrpos) == PACKOFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Packs Auto")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            else
                set(packlpos, PACKAUTO)
                set(packrpos, PACKAUTO)
            end      
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
            P.commandtableentry(ADVICE, "Both Packs checked and On")
        end  
    elseif (P.procedureloop2.stepindex == 11) then
        if (get(isolvalvepos)  == ISOLVALVEOPEN) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Isolation Valve Auto")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEAUTO)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
            P.commandtableentry(ADVICE, "Isolation Valve checked and Auto")
        end  
    elseif (P.procedureloop2.stepindex == 12) then
        if (get(bleedairapupos) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Bleed Air Off")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            else
             helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
            P.commandtableentry(ADVICE, "A P U Bleed Air checked and Off")
        end  
    elseif (P.procedureloop2.stepindex == 13) then
        if (get(apustarterpos) == ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch A P U Off")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
            P.commandtableentry(ADVICE, "A P U checked and Off")
        end  
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- duringclimb function

function duringclimb()

    if ((not P.proceduretable[DURINGCLIMBPROCEDURE].set) and (P.procedureloop2.lock == NOPROCEDURE)) then
       P.procedureloop2.lock = DURINGCLIMBPROCEDURE
    end

    if ((get(altitude) >= P.lowerairspacealt) and (not P.proceduretable[ALTITUDEA10000PROCEDURE].set) and (P.procedureloop1.lock == NOPROCEDURE)) then
        P.procedureloop1.lock = ALTITUDEA10000PROCEDURE
    end

    if ((P.configvalues[CONFIGAUTOFLAPS] == ON) and (get(flapleverpos) > FLAPSUP)) then
        flapsuphandling()
    end

end

--------------------------------------------------------------------------------------------------------------
-- altitudeb10000steps function

function altitudeb10000steps()

    if (P.procedureloop1.stepindex == 1) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Below " .. P.lowerairspacealt .. " Feet")
        else
            P.commandtableentry(TEXT, "Below " .. P.lowerairspacealt .. " Feet")
        end
    elseif (P.procedureloop1.stepindex == 2) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 3) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Seatbeltsigns On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Seatbeltsigns checked and On")
        end  
    elseif (P.procedureloop1.stepindex == 4) then
        if ((get(llights1) == OFF) or (get(llights2) == OFF) or (get(llights3) == OFF) or (get(llights4) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Landing Lights On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Landing Lights checked and On")
        end  
    elseif (P.procedureloop1.stepindex == 5) then
        if ((get(starter1pos) ~= FLIGHT) or (get(starter2pos) ~= FLIGHT)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setstarter(BOTH, FLIGHT)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Starters Flight")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        else
            if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Both Starters checked and Flight")
            end
        end
    elseif (P.procedureloop1.stepindex == 6) then
        if (get(logolighton) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelogolight(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Logo Lights On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Logo Lights checked and On")
        end  
    elseif (P.procedureloop1.stepindex == 7) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 8) then
        if ((not P.proceduretable[SETILSPROCEDURE].set) and ((P.procedureloop3.lock == NOPROCEDURE) or (P.procedureloop3.lock == SETILSPROCEDURE))) then
            P.procedureloop3.lock = SETILSPROCEDURE
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        end
    elseif (P.procedureloop1.stepindex == 9) then
        if (P.configvalues[CONFIGVREF30SET] == ON) then
            if ((not P.proceduretable[SETVREFPROCEDURE].set) and ((P.procedureloop3.lock == NOPROCEDURE) or (P.procedureloop3.lock == SETVREFPROCEDURE))) then
                P.procedureloop3.lock = SETVREFPROCEDURE
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        end
    elseif (P.procedureloop1.stepindex == 10) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 11) then
        if (P.configvalues[CONFIGVREF30SET] == ON) then
            local autobrake = calcautobrake(get(vref), P.desmetar.decodedmetar)
            sasl.logDebug("AUTOBRAKE AUTOBRAKEPOS: " .. tostring(get(autobrakepos)) .. " AUTOBRAKE " .. tostring(autobrake))
            if (get(autobrakepos) ~= autobrake) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    setautobrake(autobrake)
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    if (autobrake < AUTOBRAKEMAX) then
                        P.commandtableentry(ADVICE, "Set Auto Brake " .. tostring(autobrake - 1))
                    else
                        P.commandtableentry(ADVICE, "Set Auto Brake Maximum")
                    end
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                if (autobrake < AUTOBRAKEMAX) then
                    P.commandtableentry(ADVICE, "Auto Brake checked and " .. tostring(autobrake - 1))
                else
                    P.commandtableentry(ADVICE, "Auto Brake checked and Maximum")
                end
            end
        end
    elseif (P.procedureloop1.stepindex == 12) then
        if P.desmetar.metarfound then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, formatMetarSpeechSummary(P.desmetar))
            else
                P.commandtableentry(TEXT, formatMetarSpeechSummary(P.desmetar))
            end
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "No Metar found for " .. addspaces(desicao))
            else
                P.commandtableentry(TEXT, "No Metar found for " .. addspaces(desicao))
            end
        end
    end

    return true

end

function altitudeb10000()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = ALTITUDEB10000PROCEDURE
    end

    if (get(airgroundsensor) == ON) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Below 10000 Procedure not possible on Ground")
        return true
    end

    if P.proceduretable[ALTITUDEB10000PROCEDURE].set then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Below 10000 Procedure already done")
        return true
    end

    if (get(altitude) > P.lowerairspacealt) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Below 10000 Procedure only possible below lower Airspace Altitude")
        return true
    end

    if (P.flightstate <= 2) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Altitude below 10000 Procedure only possible during Descent")
        return true
    end

    return true

end

function altitudeb10000_(phase)
    if phase == SASL_COMMAND_BEGIN then
        altitudeb10000()
    end
    return 0
end

my_command_altitudeb10000 = sasl.createCommand(definitions.APPNAMEPREFIX .. "/altitudeb10000", "Below 10000")
sasl.registerCommandHandler(my_command_altitudeb10000, 0, altitudeb10000_)
--sasl.appendMenuItem(P.menu_main, "Below 10000", altitudeb10000)

--------------------------------------------------------------------------------------------------------------
-- radioaltitudeb2500steps function

function radioaltitudeb2500steps()

    if (P.procedureloop2.stepindex == 1) then
        if ((convflaplevertoflappos(get(flapleverpos)) >= P.configvalues[CONFIGGEARDOWNFLAPS]) and (get(gearhandlepos) < GEARDOWN)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(gearhandlepos, GEARDOWN)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Gear Down")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            end
        elseif (get(gearhandlepos) == GEARDOWN) then
            if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Gear checked and Down")
            end
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- radioaltitudeb1000steps function

function radioaltitudeb1000steps()

    if (P.procedureloop2.stepindex == 1) then
        local speedbrakeleverrounded = roundnumber(get(speedbrakelever), 1)
        if (speedbrakeleverrounded == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(speedbrakelever, 0.1)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Arm Speed Brakes")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            end
        else
            if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Speedbrakes checked and Armed")
            end
        end
    elseif (P.procedureloop2.stepindex == 2) then
        if (get(taxilight) == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Taxi Lights On")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            end
        else
            if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Taxi Lights checked and On")
            end
        end
    elseif (P.procedureloop2.stepindex == 3) then
        if ((get(rwylightl) == OFF) or (get(rwylightl) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglerwylights(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Runway Turnoff Lights On")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            end
        else
            if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Runway Turnoff Lights checked and On")
            end
        end
    elseif (P.procedureloop2.stepindex == 4) then
        local missedappalttmp = roundnumber((get(missedappalt) / 100)) * 100
        if (missedappalttmp > 1000) then
            if (missedappalttmp ~= get(mcpaltitude)) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set M C P Altitude " .. addspaces(missedappalttmp))
                    P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
                else
                    set(mcpaltitude,  missedappalttmp)
                end
            else
                if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                    P.commandtableentry(ADVICE, "MCP Altitude checked and " .. addspaces(missedappalttmp))
                end
            end
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Missed Approach Altitude")
            else
                P.commandtableentry(TEXT, "Set Missed Approach Altitude")
            end
        end
    elseif (P.procedureloop2.stepindex == 5) then
        local headingrounded = nil
        if (isvalidicao(get(desicao)) and isvalidrwy(get(desrwy)) and tonumber(get(desrwyheading))) then
            headingrounded = roundnumber(get(desrwyheading))
        end
        local navrwyheading = getrwyheadingfromnavdata(get(desicao), get(desrwy))
        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
            headingrounded = navrwyheading
        end

        if (headingrounded and (get(aphdgselstat) == OFF)) then
            if (headingrounded ~= get(mcpheading)) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set M C P Heading " .. addspaces(padNumberWithZerosStrict(headingrounded, 3)))
                    P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
                else
                    set(mcpheading, headingrounded)
                end
            else
                if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                    P.commandtableentry(ADVICE, "MCP Heading checked and " .. addspaces(padNumberWithZerosStrict(headingrounded, 3)))
                end
            end
        elseif not headingrounded then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Missed Approach Heading")
            else
                P.commandtableentry(TEXT, "Set Missed Approach Heading")
            end
        end
    elseif (P.procedureloop2.stepindex == 6) then
        if (get(gearhandlepos) < GEARDOWN) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(gearhandlepos, GEARDOWN)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Gear Down")
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            end
        else
            if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Gear checked and Down")
            end
        end
    elseif (P.procedureloop2.stepindex == 7) then
        if (((get(appflapsset) == OFF) and get(appflaps) ~= 0)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then            
                helpers.command_once("laminar/B738/push_button/flaps_" .. tostring(get(appflaps)))
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Flaps " .. tostring(get(appflaps)))
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1 
            end
        else
            if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Flaps checked and " .. tostring(get(appflaps)))
            end
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- duringdescentsteps function

function duringdescentsteps()

   if (P.procedureloop2.stepindex == 1) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            P.commandtableentry(ADVICE, "Descent Started")
        else
            P.commandtableentry(TEXT, "Descent Started")  
        end
    elseif ((P.procedureloop2.stepindex == 2) and (P.configvalues[CONFIGSPDRESTR250] == ON)) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWFMS])
    elseif ((P.procedureloop2.stepindex == 3) and (P.configvalues[CONFIGSPDRESTR250] == ON)) then
        helpers.command_once("laminar/B738/button/fmc1_des")
    elseif (P.procedureloop2.stepindex == 4) then
        if (P.configvalues[CONFIGSPDRESTR250] == ON) then
            if (get(speedrestr) ~= 250) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Speed below 10000 Feet to 250")
                    P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
                else
                    set(speedrestr, 250)
                    P.commandtableentry(TEXT, "Speed 250 below 10000 Feet set")
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                P.commandtableentry(ADVICE, "Speed 250 below 10000 Feet checked and set")
            end
        end
    elseif (P.procedureloop2.stepindex == 5) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
        elseif (P.procedureloop2.stepindex == 6) then
        if P.desmetar.metarfound then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, formatMetarSpeechSummary(P.desmetar))
            else
                P.commandtableentry(TEXT, formatMetarSpeechSummary(P.desmetar))
            end
        else
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "No Metar found for " .. addspaces(desicao))
            else
                P.commandtableentry(TEXT, "No Metar found for " .. addspaces(desicao))
            end
        end
    elseif (P.procedureloop2.stepindex == 7) then
        if (get(altitude) < get(fmctranslvl)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Passing Transition Level")
            else
                P.commandtableentry(TEXT, "Passing Transition Level")
            end
        else
            P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
        end
    elseif (P.procedureloop2.stepindex == 8) then
        if (P.configvalues[CONFIGAUTOBARO] == ON) then
            if (get(altitude) < get(fmctranslvl)) then
                local baroinchtmp, baropastmp = getlocalqnh(ARRIVAL)
                sasl.logDebug("QNHARRIVAL: BAROPILOT "..tostring(roundnumber(get(baropilot), 2)) .. " BAROINCHTMP " .. baroinchtmp .. " " .. tostring(roundnumber(math.abs(roundnumber(get(baropilot), 2) - baroinchtmp), 2)))
                if ((get(barostd) == ON) or (roundnumber(math.abs(roundnumber(get(baropilot), 2) - baroinchtmp), 2) > 0.01)) then
                    if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                        helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
                        set(baropilot, baroinchtmp)
                    elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        if (get(baroinhpa) == ON) then
                            P.commandtableentry(ADVICE, "Set Q N H " .. addspaces(baropastmp))
                        else
                            P.commandtableentry(ADVICE, "Set Q N H " .. addspaces(baroinchtmp))
                        end
                        P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
                    end
                elseif ((get(barostd) == OFF) and (roundnumber(math.abs(roundnumber(get(baropilot), 2) - baroinchtmp), 2) <= 0.01)) then
                    if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop2.steprepeat) then
                        if (get(baroinhpa) == ON) then
                            P.commandtableentry(ADVICE, "Q N H checked and " .. addspaces(baropastmp))
                        else
                            P.commandtableentry(ADVICE, "Q N H checked and " .. addspaces(baroinchtmp))
                        end
                    end
                end
            else
                P.procedureloop2.stepindex = P.procedureloop2.stepindex - 1
            end
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- duringdescent function

function duringdescent()

    if ((not P.proceduretable[DURINGDESCENTPROCEDURE].set) and (P.procedureloop2.lock == NOPROCEDURE)) then
       P.procedureloop2.lock = DURINGDESCENTPROCEDURE
    end

    if ((get(altitude) < P.lowerairspacealt) and (not P.proceduretable[ALTITUDEB10000PROCEDURE].set) and (P.procedureloop1.lock == NOPROCEDURE)) then
        P.procedureloop1.lock = ALTITUDEB10000PROCEDURE
    end

    if ((get(radioaltitude) < 2500) and (not P.proceduretable[RADIOALTITUDEB2500PROCEDURE].set) and (P.procedureloop2.lock == NOPROCEDURE)) then
       P.procedureloop2.lock = RADIOALTITUDEB2500PROCEDURE
    end

    if ((get(radioaltitude) < 1000) and (not P.proceduretable[RADIOALTITUDEB1000PROCEDURE].set)  and (P.procedureloop2.lock == NOPROCEDURE)) then
       P.procedureloop2.lock = RADIOALTITUDEB1000PROCEDURE
    end

    if (P.configvalues[CONFIGAUTOFLAPS] == ON) then
        flapsdownhandling()
    end
end

--------------------------------------------------------------------------------------------------------------
-- afterlandingsteps function

function afterlandingsteps()

    if (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 2) then
       if ((get(llights1) ~= OFF) or (get(llights2) ~= OFF) or (get(llights3) ~= OFF) or (get(llights4) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Landing Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Landing Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 3) then
        if (get(taxilight) == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Taxi Lights On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Taxi Lights checked and On")
        end
    elseif (P.procedureloop1.stepindex == 4) then
        if ((get(rwylightl) == ON) or (get(rwylightl) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglerwylights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Runway Turnoff Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Runway Turnoff Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 5) then
        if(get(positionlights) ~= POSLIGHTSSTEADY) then 
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglepositionlights(POSLIGHTSSTEADY)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Position Lights Steady")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Position Lights checked and Steady")
        end
    elseif (P.procedureloop1.stepindex == 6) then
        if ((get(captainprobepos) ~= OFF) or (get(foprobepos) ~= OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggleprobeheat(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Probe Heat Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Probe Heat checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 7) then
        setview(P.configvalues[CONFIGVIEWPEDESTAL])
    elseif (P.procedureloop1.stepindex == 8) then
        if (get(transponderpos) == TARA) then
            if (P.configvalues[CONFIGTRANSPONDER] ~= 0) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    toggletransponder(STANDBY)
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Transponder Off")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Transponder checked and " .. TransponderPostotring(get(transponderpos)))
        end
    elseif (P.procedureloop1.stepindex == 9) then
        setview(P.configvalues[CONFIGVIEWTHROTTLE])
    elseif (P.procedureloop1.stepindex == 10) then
        if (get(flapleverpos) > FLAPSUP) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                helpers.command_once("laminar/B738/push_button/flaps_0")
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Flaps Up")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end        
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Flaps checked and Up")
        end
    elseif (P.procedureloop1.stepindex == 11) then
        speedbrakeleverrounded = roundnumber(get(speedbrakelever), 1)
        if (speedbrakeleverrounded ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(speedbrakelever, OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Retract Speed Brakes")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end 
        else
            if ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Speedbrakes Up and Retracted")
            end
        end
    elseif (P.procedureloop1.stepindex == 12) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 13) then
        if ((get(fdpilotpos) == ON) or (get(fdfopos) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglefds(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Flight Directors OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Flight Directors checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 14) then
         if ((get(efiswxpilotpos) == ON) or (get(efiswxfopos) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglewx(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Weather Radars OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Weather Radars checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 15) then
         if ((get(efisterrpilotpos) == ON) or (get(efisterrfopos) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggleterr(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Terrain Radars OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Terrain Radars checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 16) then
        if (get(autobrakepos) ~= AUTOBRAKEOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setautobrake(AUTOBRAKEOFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Auto Brake Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Auto Brake checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 17) then
        if (get(aponstat) == ON) then
            set(aponstat, OFF)
        end
    elseif (P.procedureloop1.stepindex == 18) then
        iceprotection(OFF)
    elseif (P.procedureloop1.stepindex == 19) then
        helpers.command_once("laminar/B738/push_button/master_caution1")
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- afterlanding function

function afterlanding()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = AFTERLANDINGPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "After Landing Procedure Not Possible Inflight")
        return true
    end

    if P.proceduretable[AFTERLANDINGPROCEDURE].set then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "After Landing Procedure already done")
        return true
    end

    if (P.flightstate < 4)
    then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "After Landing Procedure only possible after Landing")
        return true
    end

    P.flightstate = 5

    return true

end

function afterlanding_(phase)
    if phase == SASL_COMMAND_BEGIN then
        afterlanding()
    end
    return 0
end

my_command_afterlanding = sasl.createCommand(definitions.APPNAMEPREFIX .. "/afterlanding", "After Landing Procedure")
sasl.registerCommandHandler(my_command_afterlanding, 0, afterlanding_)
--sasl.appendMenuItem(P.menu_main, "After Landing Procedure", afterlanding)

--------------------------------------------------------------------------------------------------------------
-- beforetaxisteps function

function beforetaxisteps()

    if (P.procedureloop1.stepindex == 1) then
        if (get(chockstatus) ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                helpers.command_once("laminar/B738/toggle_switch/chock")
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Remove Chocks")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and (get(groundspeed) < 1) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Chocks checked and Removed")
        end
    elseif (P.procedureloop1.stepindex == 2) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWUPPEROVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 3) then
        if (get(domelightpos) ~= DOMELIGHTOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setdomelight(DOMELIGHTOFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Domelight OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Domelight checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 4) then
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 5) then
        if(get(positionlights) ~= POSLIGHTSSTEADY) then 
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglepositionlights(POSLIGHTSSTEADY)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Position Lights Steady")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Position Lights checked and Steady")
        end
    elseif (P.procedureloop1.stepindex == 6) then
        if (get(beaconlights) == OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Collision Lights On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                togglecollisionlights(ON)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Collision Lights checked and On")
        end  
    elseif (P.procedureloop1.stepindex == 7) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Seatbeltsigns On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Seatbeltsigns checked and On")
        end
    elseif (P.procedureloop1.stepindex == 8) then
        if (get(logolighton) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelogolight(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Logo Lights On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Logo Lights checked and On")
        end
    elseif (P.procedureloop1.stepindex == 9) then
        if (get(yawdamperswitch) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Yaw Damper On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(yawdamperswitch, ON)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Yaw Damper checked and On") 
        end
    elseif (P.procedureloop1.stepindex == 10) then
        if ((get(hydro1pos) ~= ON) or (get(hydro2pos) ~= ON) or (get(elechydro1pos) ~= ON) or (get(elechydro2pos) ~= ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Switch Hydraulic Pumps On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                set(hydro1pos, ON)
                set(hydro2pos, ON)
                set(elechydro1pos, ON)
                set(elechydro2pos, ON)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Hydraulic Pumps checked and On") 
        end
    elseif (P.procedureloop1.stepindex == 11) then
        if ((get(wheatlfwdpos) == OFF) or (get(wheatrfwdpos) == OFF) or (get(wheatlsidepos) == OFF) or (get(wheatrsidepos) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglewindowheat(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Window Heat On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON)  and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Window Heat checked and On")
        end
    elseif (P.procedureloop1.stepindex == 12) then
        if ((get(captainprobepos) == OFF) or (get(foprobepos) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggleprobeheat(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Probe Heat On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Probe Heat checked and On")
        end
    elseif (P.procedureloop1.stepindex == 13) then
        if ((get(starter1pos) ~= FLIGHT) or (get(starter2pos) ~= FLIGHT)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setstarter(BOTH, FLIGHT)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Starters Flight")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end 
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Both Starters checked and FLight")
        end
    elseif (P.procedureloop1.stepindex == 14) then
        setview(P.configvalues[CONFIGVIEWFMS])
    elseif (P.procedureloop1.stepindex == 15) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(toflaps) == 0) then
                local toflapscalc = determineTakeoffFlapsSetting(P.depmetar.decodedmetar)
                P.commandtableentry(ADVICE, "Set Takeoff Flaps " .. tostring(toflapscalc))
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            elseif not P.procedureloop1.steprepeat then
                P.commandtableentry(ADVICE, "Takeoff Flaps set and " .. tostring(get(toflaps)))
            end
        end
    elseif (P.procedureloop1.stepindex == 16) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(fmccg) == 0) then
                P.commandtableentry(ADVICE, "Set C G " .. tostring(roundnumber(get(tabcg),1)))
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            elseif not P.procedureloop1.steprepeat then
                P.commandtableentry(ADVICE, "C G checked and " .. tostring(get(fmccg)))
            end
        end
    elseif (P.procedureloop1.stepindex == 17) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if ((get(v1setspeed) == 0) or (get(v2setspeed) == 0) or (get(vrsetspeed) == 0)) then
                P.commandtableentry(ADVICE, "Enter V Speeds")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            elseif not P.procedureloop1.steprepeat then
                P.commandtableentry(ADVICE, "V Speeds checked and Set")
            end
        end
    elseif (P.procedureloop1.stepindex == 18) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 19) then
        if ((get(fdpilotpos) == OFF) or (get(fdfopos) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglefds(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Both Flight Directors On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Flight Directors checked and On")
        end
    elseif (P.procedureloop1.stepindex == 20) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(aplnavstat) ~= ON) then
                P.commandtableentry(ADVICE, "Arm L NAV")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            elseif not P.procedureloop1.steprepeat then
                P.commandtableentry(ADVICE, "L NAV checked and ARMED")
            end
        end
    elseif (P.procedureloop1.stepindex == 21) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(apvnavstat) ~= ON) then
                P.commandtableentry(ADVICE, "Arm V NAV")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            elseif not P.procedureloop1.steprepeat then
                P.commandtableentry(ADVICE, "V NAV checked and ARMED")
            end
        end
    elseif (P.procedureloop1.stepindex == 22) then
        setview(P.configvalues[CONFIGVIEWTHROTTLE])
    elseif (P.procedureloop1.stepindex == 23) then
        local toflapscalc = determineTakeoffFlapsSetting(P.depmetar.decodedmetar)
        if ((convflaplevertoflappos(get(flapleverpos)) ~= get(toflaps)))  then  
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                local toflapscmd = "laminar/B738/push_button/flaps_" .. get(toflaps)
                helpers.command_once(toflapscmd)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                toflapscmd = "Set Flap Lever " .. tostring(get(toflaps))
                P.commandtableentry(ADVICE, toflapscmd)
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
                P.commandtableentry(ADVICE, "Takeoff Flaps checked and " .. get(toflaps))
        end
    elseif ((P.procedureloop1.stepindex == 24) and (P.configvalues[CONFIGVOICEADVICEONLY] == ON))then
        if (get(parkingbrakepos) ~= OFF) then
            P.commandtableentry(ADVICE, "Release Parking Brake")
            P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
        elseif ((get(groundspeed) < 1) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Parking Brake checked and Released")
        end
    elseif (P.procedureloop1.stepindex == 24) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- beforetaxi function

function beforetaxi()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = BEFORETAXIPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Before Taxi Procedure Not Possible Inflight")
        return true
    end

    if not enginesrunning(BOTH) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Before Taxi Procedure Aborted, Engines not running")
        return true
    end

    return true
end

function beforetaxi_(phase)
    if phase == SASL_COMMAND_BEGIN then
        beforetaxi()
    end
    return 0
end

my_command_beforetaxi = sasl.createCommand(definitions.APPNAMEPREFIX .. "/beforetaxi", "Before Taxi Procedure")
sasl.registerCommandHandler(my_command_beforetaxi, 0, beforetaxi_)
--sasl.appendMenuItem(P.menu_main, "Before Taxi Procedure", beforetaxi)

--------------------------------------------------------------------------------------------------------------
-- beforetakeoffsteps function

function beforetakeoffsteps()

    if (get(groundspeed) > 45) then
        P.procedureabort = true
        return true
    elseif (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWPEDESTAL])
    elseif (P.procedureloop1.stepindex == 2) then
        if (get(transponderpos) ~= TARA) then
            if (P.configvalues[CONFIGTRANSPONDER] ~= 0) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    toggletransponder(TARA)
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Transponder T A R A")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Transponder checked and T A R A")
        end
    elseif (P.procedureloop1.stepindex == 3) then
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 4) then
        if(get(positionlights) ~= POSLIGHTSSTROBE) then 
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglepositionlights(POSLIGHTSSTROBE)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Position Lights Strobe")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Position Lights checked and Strobe")
        end
    elseif (P.procedureloop1.stepindex == 5) then
        if ((get(llights1) == OFF) or (get(llights2) == OFF) or (get(llights3) == OFF) or (get(llights4) == OFF)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(ON)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Landing Lights On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Landing Lights checked and On")
        end
    elseif (P.procedureloop1.stepindex == 6) then
        if (get(taxilight)  ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Taxi Lights OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Taxi Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 7) then
        if ((get(rwylightl) == ON) or (get(rwylightl) == ON)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglerwylights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == OFF) then
                P.commandtableentry(ADVICE, "Set Runway Turnoff Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Runway Turnoff Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 8) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    if (P.procedureloop1.stepindex == 9) then
        if (get(autobrakepos)  ~= AUTOBRAKERTO) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setautobrake(AUTOBRAKERTO)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Auto Brake R T O")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Auto Brake checked and R T O")
        end
    elseif (P.procedureloop1.stepindex == 10) then
        local headingrounded = nil
        if (isvalidicao(get(depicao)) and isvalidrwy(get(deprwy)) and tonumber(get(deprwyheading))) then
            headingrounded = roundnumber(get(deprwyheading))
        end
        local navrwyheading = getrwyheadingfromnavdata(get(depicao), get(deprwy))
        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
            headingrounded = navrwyheading
        end
        if headingrounded then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                if (get(mcpheading) ~= headingrounded) then
                    P.commandtableentry(ADVICE, "Set M C P Heading" .. addspaces(padNumberWithZerosStrict(headingrounded, 3)))
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                elseif not P.procedureloop1.steprepeat then
                    P.commandtableentry(ADVICE, "M C P Heading checked" .. addspaces(padNumberWithZerosStrict(headingrounded, 3)))
                end
            end
        end
    elseif (P.procedureloop1.stepindex == 11) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(aplnavstat) ~= ON) then
                P.commandtableentry(ADVICE, "Arm L NAV")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            elseif not P.procedureloop1.steprepeat then
                P.commandtableentry(ADVICE, "L NAV checked and ARMED")
            end
        end
    elseif (P.procedureloop1.stepindex == 12) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(apvnavstat) ~= ON) then
                P.commandtableentry(ADVICE, "Arm VNAV")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            elseif not P.procedureloop1.steprepeat then
                P.commandtableentry(ADVICE, "V NAV checked and ARMED")
            end
        end
    elseif (P.procedureloop1.stepindex == 13) then
        if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(atarmpos) ~= ON) then
                P.commandtableentry(ADVICE, "Arm Autothrottle")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            elseif not P.procedureloop1.steprepeat then
                P.commandtableentry(ADVICE, "Autothrottle checked and Armed")
            end
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- beforetakeoff() function

function beforetakeoff()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        P.procedureloop1.lock = BEFORETAKEOFFPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Before Takeoff Procedure Not Possible Inflight")
        return true
    end

    if not P.proceduretable[BEFORETAXIPROCEDURE].set then
        P.procedureloop1.lock = NOPROCEDURE
        P.commandtableentry(TEXT, "Before Takeoff Procedure Not Possible, before Taxi Procedure")
        return true
    end

    return true

end

function beforetakeoff_(phase)
    if phase == SASL_COMMAND_BEGIN then
        beforetakeoff()
    end
    return 0
end

my_command_beforetakeoff = sasl.createCommand(definitions.APPNAMEPREFIX .. "/beforetakeoff", "Before Takeoff Procedure")
sasl.registerCommandHandler(my_command_beforetakeoff, 0, beforetakeoff_)

--------------------------------------------------------------------------------------------------------------
-- atparkingpositionsteps function

function atparkingpositionsteps()

    if (get(battery) ~= ON) then
        P.procedureabort = true
        return true
    elseif (P.procedureloop1.stepindex == 1) then
        setview(DEFAULTVIEW)
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    elseif (P.procedureloop1.stepindex == 2) then
        if (get(chockstatus) ~= ON) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                helpers.command_once("laminar/B738/toggle_switch/chock")
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Chocks")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Chocks checked and Set")
        end
    elseif ((P.procedureloop1.stepindex == 3) and (get(sunpitchdegrees) < 0)) then
        setview(P.configvalues[CONFIGVIEWUPPEROVERHEADPANEL])
    elseif ((P.procedureloop1.stepindex == 4) and (get(sunpitchdegrees) < 0)) then
        if (get(domelightpos) == DOMELIGHTOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Dome Light On")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            else
                setdomelight(DOMELIGHTDIM)
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Dome light checked and On")
        end
    elseif (P.procedureloop1.stepindex == 5) then
        setview(P.configvalues[CONFIGVIEWPEDESTAL])
    elseif (P.procedureloop1.stepindex == 6) then
        if (get(transponderpos) ~= STANDBY) then
            if (P.configvalues[CONFIGTRANSPONDER] ~= 0) then
                if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    toggletransponder(STANDBY)
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Transponder Standby")
                    P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
                end
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Transponder checked and Standby")
        end
    elseif (P.procedureloop1.stepindex == 7) then
        setview(P.configvalues[CONFIGVIEWOVERHEADPANEL])
    elseif (P.procedureloop1.stepindex == 8) then
        if (get(taxilight)  ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Taxi Lights OFF")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Taxi Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 9) then
        if (get(logolighton) ~= OFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelogolight(OFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Logo Lights Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Logo Lights checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 10) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNOFF) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNOFF)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Set Seatbeltsigns Off")
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            P.commandtableentry(ADVICE, "Seatbeltsigns checked and Off")
        end
    elseif (P.procedureloop1.stepindex == 11) then
        if ((get(starter1pos) ~= AUTO) or (get(starter2pos) ~= AUTO)) then
            if (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setstarter(BOTH, AUTO)
            elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                if (get(starterauto) == ON) then
                    P.commandtableentry(ADVICE, "Set Both Starters Auto")
                else
                    P.commandtableentry(ADVICE, "Set Both Starters Off")
                end
                P.procedureloop1.stepindex = P.procedureloop1.stepindex - 1
            end   
        elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and not P.procedureloop1.steprepeat) then
            if (get(starterauto) == ON) then
                P.commandtableentry(ADVICE, "Both Starters checked and Auto")
            else
                P.commandtableentry(ADVICE, "Both Starters checked and Off")
            end
        end
    elseif (P.procedureloop1.stepindex == 12) then
        setview(P.configvalues[CONFIGVIEWMAINPANEL])
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- inflightrestoreactions function

function inflightrestoreactions()

    readconfig()

    if ((P.configvalues[CONFIGAUTOBARO] == ON) and (P.configvalues[CONFIGAUTOFUNCTIONS] == ON)) then
        if ((get(altitude) > get(fmctransalt)) and (get(barostd) == OFF)) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
        end

        if ((get(altitude) < get(fmctranslvl)) and (get(barostd) == ON)) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
            local baroinchtmp, baropastemp = getlocalqnh(ARRIVAL)
            set(baropilot, baroinchtmp)
        end
    end

end

--------------------------------------------------------------------------------------------------------------
-- auto functions

function autofunctions()


    if (get(airgroundsensor) == ON)  then -- aircraft on the ground
        P.aircraftwasonground = true

        if (P.flightstate == 0) then
            if ((not P.proceduretable[BEFORETAXIPROCEDURE].set) and (get(taxilight) ~= OFF) and enginesrunning(BOTH) and (get(groundspeed) < 45) and (P.procedureloop1.lock == NOPROCEDURE)) then
                P.procedureloop1.lock = BEFORETAXIPROCEDURE
            end

            if (P.proceduretable[BEFORETAXIPROCEDURE].set and (not P.proceduretable[BEFORETAKEOFFPROCEDURE].set) and (P.procedureloop1.lock == NOPROCEDURE)) then
                if ((aircraftonrwy(get(aircraftlatpos), get(aircraftlonpos), get(deprwylatstartpos), get(deprwylonstartpos), get(deprwylatendpos), get(deprwylonendpos), 0.0003) and
                     (headingdiff(get(groundtrackmag), get(deprwyheading)) < 20) and (roundnumber(get(groundspeed)) == 0))) then
                    P.procedureloop1.lock = BEFORETAKEOFFPROCEDURE
                end            
            end
        else
            if ((not P.proceduretable[AFTERLANDINGPROCEDURE].set) and (get(groundspeed) < 45) and (P.procedureloop1.lock == NOPROCEDURE)) then
                if (((not aircraftonrwy(get(aircraftlatpos), get(aircraftlonpos), P.desrwylatstartpostemp, P.desrwylonstartpostemp, P.desrwylatendpostemp, P.desrwylonendpostemp, 0.0001)) and
                    (headingdiff(get(groundtrackmag), P.desrwyheadingtemp) > 20)) or (roundnumber(get(groundspeed)) == 0)) then
                    P.flightstate = 5
                    P.procedureloop1.lock = AFTERLANDINGPROCEDURE
                end
            end

            if ((get(parkingbrakepos) == ON) and (P.flightstate >= 5) and P.proceduretable[AFTERLANDINGPROCEDURE].set and (not P.proceduretable[ATPARKINGPOSITIONPROCEDURE].set) and (P.procedureloop1.lock == NOPROCEDURE)) then
                P.flightstate = 6
                P.procedureloop1.lock = ATPARKINGPOSITIONPROCEDURE
            end
        end
    else -- aircraft in the air

        if not P.aircraftwasonground then
            inflightrestoreactions()
            P.aircraftwasonground = true
        end

        if ((P.flightstate <= 4) and (get(fmsflightphase) > 6)) then
            P.flightstate = 4
        elseif ((P.flightstate <= 3) and (get(fmsflightphase) > 2)) then
            P.flightstate = 3
        elseif ((P.flightstate <= 2) and (get(fmsflightphase) <= 2) and P.proceduretable[AFTERTAKEOFFPROCEDURE].set) then
            P.flightstate = 2
        elseif (P.flightstate == 0) then
            P.flightstate = 1
        end

        if ((P.flightstate == 1) and (not P.proceduretable[AFTERTAKEOFFPROCEDURE].set)  and (P.procedureloop2.lock == NOPROCEDURE)) then
           P.procedureloop2.lock = AFTERTAKEOFFPROCEDURE
        elseif (P.flightstate == 2) then
            duringclimb()
        elseif (P.flightstate > 2) then
            duringdescent()
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
-- voicereadback() function

function voicereadback()


    if (get(pausetod) ~= P.pausetodtemp) then
        if (get(pausetod) == ON) then
            P.commandtableentry(TEXT, "Pause at Top of Descent On")
        else
            P.commandtableentry(TEXT, "Pause at Top of Descent Off")
        end

        P.pausetodtemp = get(pausetod)
    end

    if (get(simfreezed) ~= P.simfreezedtemp) then
        if (get(simfreezed) == ON) then
            P.commandtableentry(TEXT, "Sim Freeze On")
        else
            P.commandtableentry(TEXT, "Sim Freeze Off")
        end

        P.simfreezedtemp = get(simfreezed)
    end

    if (get(chockstatus) ~= P.chockstatustmp) then
        if (get(chockstatus) == ON) then
            P.commandtableentry(TEXT, "Chocks Set")
        else
            P.commandtableentry(TEXT, "Chocks Removed")
        end

        P.chockstatustmp = get(chockstatus)
    end


    if (math.abs(get(totalfuellbs) - P.totalfuellbstemp) > 200) then
        if (get(totalfuellbs) ~= P.totalfuellbstemp2) then
            P.totalfuellbstemp2 = get(totalfuellbs)
        else
            if (get(fuelunit) == LBS) then
                P.commandtableentry(TEXT, "Fuel quantity " .. tostring(get(totalfuellbs)) .. "L B S")
            else
                P.commandtableentry(TEXT, "Fuel quantity " .. tostring(get(totalfuellbs)) .. "K G")
            end
            P.totalfuellbstemp = get(totalfuellbs)
        end
    else
        P.totalfuellbstemp = get(totalfuellbs)
    end

    if (get(cabincruisealt) ~= P.cabincruisealttemp) then
        if (get(cabincruisealt) ~= P.cabincruisealttemp2) then
            P.cabincruisealttemp2 = get(cabincruisealt)
        else
            P.commandtableentry(TEXT, "Cabin Cruise Altitude " .. tostring(get(cabincruisealt)))
            P.cabincruisealttemp = get(cabincruisealt)
            P.cabincruisealttemp2 = get(cabincruisealt)
        end
    end

    if (get(cabinlandingalt) ~= P.cabinlandingalttemp) then
        if (get(cabinlandingalt) ~= P.cabinlandingalttemp2) then
            P.cabinlandingalttemp2 = get(cabinlandingalt)
        else
            P.commandtableentry(TEXT, "Cabin Landing Altitude " .. tostring(get(cabinlandingalt)))
            P.cabinlandingalttemp = get(cabinlandingalt)
            P.cabinlandingalttemp2 = get(cabinlandingalt)
        end
    end

    if (get(mcpspeed) ~= P.mcpspeedtemp) then
        if ((get(atarmpos) == OFF) or (get(atspeedstat) == ON) or (get(atspeedintvstat) == ON)) then
            if (get(mcpspeed) ~= P.mcpspeedtemp2) then
                P.mcpspeedtemp2 = get(mcpspeed)
            else
                P.mcpspeedtemp = get(mcpspeed)
                P.mcpspeedtemp2 = get(mcpspeed)

                if (get(mcpspeed) < 1) then
                    speed = roundnumber(get(mcpspeed), 2)
                else
                    speed = roundnumber(get(mcpspeed))
                end

                if ((P.flightstate > 2) and (get(mcpspeed) == get(vref))) then
                    P.commandtableentry(TEXT, "M C P Speed set to V REF " .. tostring(speed))
                else
                    P.commandtableentry(TEXT, "M C P Speed " .. tostring(speed))
                end
            end
        end
    end

    if (get(mcpheading) ~= P.mcpheadingtemp) then
        if (get(mcpheading) ~= P.mcpheadingtemp2) then
            P.mcpheadingtemp2 = get(mcpheading)
        else
            P.mcpheadingtemp = get(mcpheading)
            P.mcpheadingtemp2 = get(mcpheading)

            P.commandtableentry(TEXT, "M C P Heading " .. addspaces(padNumberWithZerosStrict(get(mcpheading), 3)))
        end
    end

    if (get(mcpaltitude) ~= P.mcpaltitudetemp) then
        if (get(mcpaltitude) ~= P.mcpaltitudetemp2) then
            P.mcpaltitudetemp2 = get(mcpaltitude)
        else
            P.mcpaltitudetemp = get(mcpaltitude)
            P.mcpaltitudetemp2 = get(mcpaltitude)

            if (get(mcpaltitude) == get(fmccruisealt)) then
                P.commandtableentry(TEXT, "M C P set to Cruise Altitude " .. addspaces(get(mcpaltitude)))
            else
                P.commandtableentry(TEXT, "M C P Altitude " .. addspaces(get(mcpaltitude)))
            end
        end
    end

    if (get(mcpvsspeed) ~= P.mcpvsspeedtemp) then
        if (get(mcpvsspeed) ~= P.mcpvsspeedtemp2) then
            P.mcpvsspeedtemp2 = get(mcpvsspeed)
        else
            P.mcpvsspeedtemp = get(mcpvsspeed)
            P.mcpaltitudetemp2 = get(mcpvsspeed)

            if ((get(mcpvsspeed) ~= 0) and (get(apalthldstat) ~= ON) and (get(apvnavstat) ~= ON)) then
                P.commandtableentry(TEXT, "M C P Vertical Speed " .. tostring(get(mcpvsspeed)))
            end
        end
    end

    if (get(mcppilotcourse) ~= P.mcppilotcoursetemp) then
        if (get(mcppilotcourse) ~= P.mcppilotcoursetemp2) then
            P.mcppilotcoursetemp2 = get(mcppilotcourse)
        else
            P.mcppilotcoursetemp = get(mcppilotcourse)
            P.mcppilotcoursetemp2 = get(mcppilotcourse)

            P.commandtableentry(TEXT, "M C P Pilot Course " .. addspaces(padNumberWithZerosStrict(get(mcppilotcourse), 3)))
        end
    end

    if (get(mcpcopilotcourse) ~= P.mcpcopilotcoursetemp) then
        if (get(mcpcopilotcourse) ~= P.mcpcopilotcoursetemp2) then
            P.mcpcopilotcoursetemp2 = get(mcpcopilotcourse)
        else
            P.mcpcopilotcoursetemp = get(mcpcopilotcourse)
            P.mcpcopilotcoursetemp2 = get(mcpcopilotcourse)

            P.commandtableentry(TEXT, "M C P Copilot Course " .. addspaces(padNumberWithZerosStrict(get(mcpcopilotcourse), 3)))
        end
    end

    if (get(dhpilot) ~= P.dhpilottemp) then
        if (get(dhpilot) ~= P.dhpilottemp2) then
            P.dhpilottemp2 = get(dhpilot)
        else
            P.dhpilottemp = get(dhpilot)
            P.dhpilottemp2 = get(dhpilot)

            if ((get(dhpilot) == -1) or (get(dhpilot) == -1001)) then
                P.commandtableentry(TEXT, "Pilot Decision Altitude Reset")
            else
                P.commandtableentry(TEXT, "Pilot Decision Altitude " .. tostring(roundnumber(get(dhpilot))))
            end
        end
    end

    if ((get(desrwyheading) ~= P.desrwyheadingtemp) and (get(desrwyheading) ~= 0)) then
        P.desrwyheadingtemp = get(desrwyheading)
    end

    if ((get(desrwylatstartpos) ~= P.desrwylatstartpostemp) and (get(desrwylatstartpos) ~= 0)) then
        P.desrwylatstartpostemp = get(desrwylatstartpos)
    end

    if ((get(desrwylonstartpos) ~= P.desrwylonstartpostemp) and (get(desrwylonstartpos) ~= 0)) then
        P.desrwylonstartpostemp = get(desrwylonstartpos)
    end

    if ((get(desrwylatendpos) ~= P.desrwylatendpostemp) and (get(desrwylatendpos) ~= 0)) then
        P.desrwylatendpostemp = get(desrwylatendpos)
    end

    if ((get(desrwylonendpos) ~= P.desrwylonendpostemp) and (get(desrwylonendpos) ~= 0)) then
        P.desrwylonendpostemp = get(desrwylonendpos)
    end

    if (get(aponstat) ~= P.aponstattemp) then
        if (get(aponstat) == OFF) then
            P.commandtableentry(TEXT, "Autopilot OFF")
        end
        P.aponstattemp = get(aponstat)

    end

    if (get(apcmdastat) ~= P.apcmdastattemp) then
        if (get(apcmdastat) == ON) then
            P.commandtableentry(TEXT, "Command A On")
        else
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "Command A OFF")
            end
        end
        P.apcmdastattemp = get(apcmdastat)
    end

    if (get(apcmdbstat) ~= P.apcmdbstattemp) then
        if (get(apcmdbstat) == ON) then
            P.commandtableentry(TEXT, "Command B On")

            if ((get(apcmdastat) == ON) and ((get(apgscapturedstat) ~= OFF) or (get(aploccapturedstat) ~= OFF))) then
                if (get(mmrinstalled) == ON) then
                    if ((get(mmrcptactvalue) ~= get(mmrfoactvalue)) or (get(mmrcptactmode) ~= get(mmrfoactmode)) or (get(mcppilotcourse) ~= get(mcpcopilotcourse))) then
                        P.commandtableentry(TEXT, "Warning Pilot and Copilot M M R Disagree")
                    end
                else
                    if ((get(nav1freq) ~= get(nav2freq)) or (get(mcppilotcourse) ~= get(mcpcopilotcourse))) then
                        P.commandtableentry(TEXT, "Warning Pilot and Copilot NAV Disagree")
                    end
                end
            end
        else
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "Command B OFF")
            end
        end
        P.apcmdbstattemp = get(apcmdbstat)
    end

    if (get(apvnavstat) ~= P.apvnavstattemp) then
        if (get(apvnavstat) == ON) then
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "V NAV On")
            else
                P.commandtableentry(TEXT, "V NAV Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(apgscapturedstat) ~= CAPTURED) and (get(aploccapturedstat) ~= CAPTURED) and (get(aplpvgscapturedstat) ~= CAPTURED) and
                (get(aplpvloccapturedstat) ~= CAPTURED) and (get(apglsgscapturedstat) ~= CAPTURED) and (get(apglsloccapturedstat) ~= CAPTURED) and
                (get(apfacgscapturedstat) ~= CAPTURED) and (get(apfacloccapturedstat) ~= CAPTURED) and (get(apalthldstat) ~= ON) and (get(apvsstat) ~= ON) and (get(aplvlchgstat) ~= ON)) then
                P.commandtableentry(TEXT, "V NAV OFF")
            end
        end
        P.apvnavstattemp = get(apvnavstat)
    end

    if (get(aplnavstat) ~= P.aplnavstattemp) then
        if (get(aplnavstat) == ON) then
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "L NAV On")
            else
                P.commandtableentry(TEXT, "L NAV Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(aploccapturedstat) ~= CAPTURED) and (get(apgscapturedstat) ~= CAPTURED) and (get(aplpvloccapturedstat) ~= CAPTURED) and
                (get(aplpvgscapturedstat) ~= CAPTURED) and (get(apglsgscapturedstat) ~= CAPTURED) and (get(apglsloccapturedstat) ~= CAPTURED) and
                (get(apfacgscapturedstat) ~= CAPTURED) and (get(apfacloccapturedstat) ~= CAPTURED) and (get(aphdgselstat) ~= ON) and (get(apappstat) ~= ON) and
                (get(apvorlocstat) ~= ON)) then
                P.commandtableentry(TEXT, "L NAV OFF")
            end
        end
        P.aplnavstattemp = get(aplnavstat)
    end

    if (get(apappstat) ~= P.apappstattemp) then
        if (get(apappstat) == ON) then
            if (get(aponstat) == ON) then
                if ((get(apgscapturedstat) == ARMED) and (get(aploccapturedstat) == ARMED)) then
                    P.commandtableentry(TEXT, "Approach Armed")
                elseif ((get(aplpvgscapturedstat) == ARMED) and (get(aplpvloccapturedstat) == ARMED)) then
                    P.commandtableentry(TEXT, "L P V Approach Armed")
                elseif ((get(apglsgscapturedstat) == ARMED) and (get(apglsloccapturedstat) == ARMED)) then
                    P.commandtableentry(TEXT, "G L S Approach Armed")
                elseif ((get(apfacgscapturedstat) == ARMED) and (get(apfacloccapturedstat) == ARMED)) then
                    P.commandtableentry(TEXT, "F A C Approach Armed")
                end
            else
                P.commandtableentry(TEXT, "Approach Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(apgscapturedstat) ~= CAPTURED) and (get(aploccapturedstat) ~= CAPTURED) and (get(aplpvgscapturedstat) ~= CAPTURED) and
                (get(aplpvloccapturedstat) ~= CAPTURED) and (get(apglsgscapturedstat) ~= CAPTURED) and (get(apglsloccapturedstat) ~= CAPTURED) and
                (get(apfacgscapturedstat) ~= CAPTURED) and (get(apfacloccapturedstat) ~= CAPTURED) and (get(aphdgselstat) ~= ON) and (get(aplnavstat) ~= ON)) then
                P.commandtableentry(TEXT, "Approach OFF")
            end
        end
        P.apappstattemp = get(apappstat)
    end

    if (get(apgscapturedstat) ~= P.apgscapturedstattemp) then
        if (get(apgscapturedstat) == CAPTURED) then
            P.commandtableentry(TEXT, "Glide Slope Captured")
        end
        P.apgscapturedstattemp = get(apgscapturedstat)
    end

    if (get(aploccapturedstat) ~= P.aploccapturedstattemp) then
        if (get(aploccapturedstat) == CAPTURED) then
            P.commandtableentry(TEXT, "Localizer Captured")
        end
        P.aploccapturedstattemp = get(aploccapturedstat)
    end

    if ((get(apflarestat) ~= P.apflarestattemp) or (get(aprolloutstat) ~= P.aprolloutstattemp)) then
        if ((get(apflarestat) == ON) and (get(aprolloutstat) == ON)) then
            P.commandtableentry(TEXT, "Autoland Armed")
            P.apflarestattemp = get(apflarestat)
            P.aprolloutstattemp = get(aprolloutstat)
        end
    end

    if (get(apvorlocstat) ~= P.apvorlocstattemp) then
        if (get(apvorlocstat) == ON) then
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "V O R Localizer On")
            else
                P.commandtableentry(TEXT, "V O R Localizer Armed")
            end
        else
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "V O R Localizer OFF")
            end
        end
        P.apvorlocstattemp = get(apvorlocstat)
    end

    if (get(apfacgscapturedstat) ~= P.apfacgscapturedstattemp) then
        if (get(apfacgscapturedstat) == CAPTURED) then
            P.commandtableentry(TEXT, "Glide Path Captured")
        end
        P.apfacgscapturedstattemp = get(apfacgscapturedstat)
    end

    if (get(apfacloccapturedstat) ~= P.apfacloccapturedstattemp) then
        if (get(apfacloccapturedstat) == CAPTURED) then
            P.commandtableentry(TEXT, "F A C Localizer Captured")
        end
        P.apfacloccapturedstattemp = get(apfacloccapturedstat)
    end

    if (get(lpvinstalled) == ON) then
        if (get(aplpvgscapturedstat) ~= P.aplpvgscapturedstattemp) then
            if (get(aplpvgscapturedstat) == CAPTURED) then
                P.commandtableentry(TEXT, "L P V Glide Slope Captured")
            end
            P.aplpvgscapturedstattemp = get(aplpvgscapturedstat)
        end

        if (get(aplpvloccapturedstat) ~= P.aplpvloccapturedstattemp) then
            if (get(aplpvloccapturedstat) == CAPTURED) then
                P.commandtableentry(TEXT, "L P V Localizer Captured")
            end
            P.aplpvloccapturedstattemp = get(aplpvloccapturedstat)
        end

        if (get(apglsgscapturedstat) ~= P.apglsgscapturedstattemp) then
            if (get(apglsgscapturedstat) == CAPTURED) then
                P.commandtableentry(TEXT, "G L S Glide Slope Captured")
            end
            P.apglsgscapturedstattemp = get(apglsgscapturedstat)
        end

        if (get(apglsloccapturedstat) ~= P.apglsloccapturedstattemp) then
            if (get(apglsloccapturedstat) == CAPTURED) then
                P.commandtableentry(TEXT, "G L S Localizer Captured")
            end
            P.apglsloccapturedstattemp = get(apglsloccapturedstat)
        end
    end

    if (get(apalthldstat) ~= P.apalthldstattemp) then
        if (get(apalthldstat) == ON) then
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "Altitude Hold On, Altitude " .. tostring(get(mcpaltitude)))
            else
                P.commandtableentry(TEXT, "Altitude Hold Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(apvsstat) ~= ON) and (get(aplvlchgstat) ~= ON) and (get(apgscapturedstat) ~= CAPTURED) and (get(aplpvgscapturedstat) ~= CAPTURED) and
                (get(apglsgscapturedstat) ~= CAPTURED) and (get(apfacgscapturedstat) ~= CAPTURED) and (get(apvnavstat) ~= ON)) then
                P.commandtableentry(TEXT, "Altitude Hold OFF")
            end
        end
        P.apalthldstattemp = get(apalthldstat)
    end

    if (get(aphdgselstat) ~= P.aphdgselstattemp) then
        if (get(aphdgselstat) == ON) then
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "Heading Select On, Heading " .. tostring(get(mcpheading)))
            else
                P.commandtableentry(TEXT, "Heading Select Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(aplnavstat) ~= ON) and (get(apvorlocstat) ~= ON) and (get(aploccapturedstat) ~= CAPTURED)) then
                P.commandtableentry(TEXT, "Heading Select OFF")
            end
        end
        P.aphdgselstattemp = get(aphdgselstat)
    end

    if (get(apvsstat) ~= P.apvsstattemp) then
        if (get(apvsstat) == ON) then
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "Vertical Speed On")
            else
                P.commandtableentry(TEXT, "Vertical Speed Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(mcpvsspeed) ~= 0) and (get(apalthldstat) ~= ON) and (get(apvnavstat) ~= ON) and (get(aplvlchgstat) ~= ON)) then
                P.commandtableentry(TEXT, "Vertical Speed OFF")
            end
        end
        P.apvsstattemp = get(apvsstat)
    end

    if (get(aplvlchgstat) ~= P.aplvlchgstattemp) then
        if (get(aplvlchgstat) == ON) then
            if (get(aponstat) == ON) then
                P.commandtableentry(TEXT, "Level Change On")
            else
                P.commandtableentry(TEXT, "Level Change Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(mcpvsspeed) ~= 0) and (get(apalthldstat) ~= ON) and (get(apvnavstat) ~= ON) and (get(apvsstat) ~= ON)) then
                P.commandtableentry(TEXT, "Level Change OFF")
            end
        end
        P.aplvlchgstattemp = get(aplvlchgstat)
    end

    if (get(atarmpos) ~= P.atarmpostemp) then
        if (get(atarmpos) == ON) then
            P.commandtableentry(TEXT, "Autothrottle Armed")

        else
            P.commandtableentry(TEXT, "Autothrottle OFF")
        end
        P.atarmpostemp = get(atarmpos)
    end

    if (get(atn1stat) ~= P.atn1stattemp) then
        if ((get(atn1stat) == ON) and (get(airgroundsensor) == ON)) then
            if (get(atarmpos) == ON) then
                P.commandtableentry(TEXT, "N 1 On")
            else
                P.commandtableentry(TEXT, "N 1 Armed")
            end
        else
            if ((get(atn1stat) == OFF) and (get(airgroundsensor) == ON)) then
                P.commandtableentry(TEXT, "N 1 OFF")
            end
        end
        P.atn1stattemp = get(atn1stat)
    end

    if (get(atspeedstat) ~= P.atspeedstattemp) then
        if ((get(atspeedstat) == ON) and (get(apgscapturedstat) ~= CAPTURED) and (get(aplpvgscapturedstat) ~= CAPTURED) and (get(apglsgscapturedstat) ~= CAPTURED) and
            (get(apfacgscapturedstat) ~= CAPTURED) and (get(apvsstat) ~= ON)  and (get(aplvlchgstat) ~= ON)) then
            if (get(atarmpos) == ON) then
                P.commandtableentry(TEXT, "Speed On")
            else
                P.commandtableentry(TEXT, "Speed Armed")
            end
        else
            if ((get(atspeedstat) == OFF) and (get(atarmpos) == ON) and (get(atn1stat) ~= ON) and (get(apvnavstat) ~= ON)) then
                P.commandtableentry(TEXT, "Speed OFF")
            end
        end
        P.atspeedstattemp = get(atspeedstat)
    end

    if (get(atspeedintvstat) ~= P.atspeedintvstattemp) then
        if (get(atspeedintvstat) == ON) then
            if (get(atarmpos) == ON) then
                P.commandtableentry(TEXT, "Speed Intervention On")
            else
                P.commandtableentry(TEXT, "Speed Intervention Armed")
            end
        else
            if ((get(atarmpos) == ON) and (get(atn1stat) ~= ON) and (get(atspeedstat) ~= ON)) then
                P.commandtableentry(TEXT, "Speed Intervention OFF")
            end
        end
        P.atspeedintvstattemp = get(atspeedintvstat)
    end

    if ((get(baropilot) ~= P.baropilottemp) or (get(barostd) ~= P.barostdtemp)) then
        if (get(baropilot) ~= P.baropilottemp2) then
            P.baropilottemp2 = get(baropilot)
        else
            if ((get(barostd) == ON) and (get(barostd) ~= P.barostdtemp)) then
                P.commandtableentry(TEXT, "Q N H Standard")
            else
                if (get(baroinhpa) == ON) then
                    P.commandtableentry(TEXT, "Q N H " .. tostring(convertpressure(get(baropilot))))
                else
                    P.commandtableentry(TEXT, "Q N H " .. tostring(get(baropilot)))
                end
            end

            P.baropilottemp = get(baropilot)
            P.baropilottemp2 = get(baropilot)
            P.barostdtemp = get(barostd)
        end
    end

    if (get(taxilight) ~= P.taxilighttemp) then
        if (get(taxilight) ~= OFF) then
            P.commandtableentry(TEXT, "Taxi Lights On")
        else
            P.commandtableentry(TEXT, "Taxi Lights Off")
        end
        P.taxilighttemp = get(taxilight)
    end

    if (get(beaconlights) ~= P.beaconlightstemp) then
        if (get(beaconlights) == ON) then
            P.commandtableentry(TEXT, "Collision Lights On")
        else
            P.commandtableentry(TEXT, "Collision Lights Off")
        end
        P.beaconlightstemp = get(beaconlights)
    end

    if ((get(llightson) ~= P.llightsontemp) or (get(llights1) ~= P.llights1temp) or (get(llights2) ~= P.llights2temp) or (get(llights3) ~= P.llights3temp) or
        (get(llights4) ~= P.llights4temp)) then
        if ((get(llightson) == OFF) and (get(llights1) == OFF) and (get(llights2) == OFF) and (get(llights3) == OFF) and (get(llights4) == OFF)) then
            P.commandtableentry(TEXT, "Landing Lights Off")
        else
            if ((P.llightsontemp == OFF) and (P.llights1temp == OFF) and (P.llights2temp == OFF) and (P.llights3temp == OFF) and (P.llights4temp == OFF)) then
                P.commandtableentry(TEXT, "Landing Lights ON")
            end
        end
        P.llightsontemp = get(llightson)
        P.llights1temp = get(llights1)
        P.llights2temp = get(llights2)
        P.llights3temp = get(llights3)
        P.llights4temp = get(llights4)
    end

    if ((get(rwylightl) ~= P.rwylightltemp) or (get(rwylightr) ~= P.rwylightrtemp)) then
        if (((get(rwylightl) ~= P.rwylightltemp) and (get(rwylightr) ~= P.rwylightrtemp)) and (get(rwylightl) == get(rwylightr))) then
            if ((get(rwylightl) == ON) and (get(rwylightr) == ON)) then
                P.commandtableentry(TEXT, "Both Runway Turnoff Lights ON")
            else
                P.commandtableentry(TEXT, "Both Runway Turnoff Lights OFF")
            end
            P.rwylightltemp = get(rwylightl)
            P.rwylightrtemp = get(rwylightr)
        else
            if (get(rwylightl) ~= P.rwylightltemp) then
                if (get(rwylightl) == ON) then
                    P.commandtableentry(TEXT, "Left Runway Turnoff Light On")
                else
                    P.commandtableentry(TEXT, "Left Runway Turnoff Light Off")
                end
                P.rwylightltemp = get(rwylightl)
            end

            if (get(rwylightr) ~= P.rwylightrtemp) then
                if (get(rwylightr) == ON) then
                    P.commandtableentry(TEXT, "Right Runway Turnoff Light On")
                else
                    P.commandtableentry(TEXT, "Right Runway Turnoff Light Off")
                end
                P.rwylightrtemp = get(rwylightr)
            end
        end
    end

    if (get(positionlights) ~= P.positionlightstemp) then
        if (get(positionlights) == POSLIGHTSOFF) then
            P.commandtableentry(TEXT, "Position Lights OFF")
        elseif (get(positionlights) == POSLIGHTSSTEADY) then
            P.commandtableentry(TEXT, "Position Lights Steady")
        elseif (get(positionlights) == POSLIGHTSSTROBE) then
            P.commandtableentry(TEXT, "Position Lights Strobe")
        end
        P.positionlightstemp = get(positionlights)
    end

    if (get(logolighton) ~= P.logolightontemp) then

        if (get(logolighton) == ON) then
            P.commandtableentry(TEXT, "Logo Light ON")
        else
            P.commandtableentry(TEXT, "Logo Light Off")
        end
        P.logolightontemp = get(logolighton)
    end

    if (get(transponderpos) ~= P.transponderpostemp) then
        P.commandtableentry(TEXT, "Transponder " .. TransponderPostotring(get(transponderpos)))
        P.transponderpostemp = get(transponderpos)
    end

    if (P.yawdamperswitchtemp ~= get(yawdamperswitch)) then
        if (get(yawdamperswitch) == ON) then
            P.commandtableentry(TEXT, "Yaw Damper ON")
        else
            P.commandtableentry(TEXT, "Yaw Damper Off")
        end
        P.yawdamperswitchtemp = get(yawdamperswitch)
    end

    if ((get(fdpilotpos) ~= P.fdpilotpostemp) or (get(fdfopos) ~= P.fdfopostemp)) then
        if ((get(fdpilotpos) ~= P.fdpilotpostemp) and (get(fdfopos) ~= P.fdfopostemp) and (get(fdpilotpos) == get(fdfopos))) then
            if (get(fdpilotpos) == ON) then
                P.commandtableentry(TEXT, "Both Flightdirectors On")
            else
                P.commandtableentry(TEXT, "Both Flightdirectors Off")
            end
            P.fdpilotpostemp = get(fdpilotpos)
            P.fdfopostemp = get(fdfopos)
        else
            if (get(fdpilotpos) ~= P.fdpilotpostemp) then
                if (get(fdpilotpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot Flightdirector On")
                else
                    P.commandtableentry(TEXT, "Pilot Flightdirector Off")
                end
                P.fdpilotpostemp = get(fdpilotpos)
            end

            if (get(fdfopos) ~= P.fdfopostemp) then
                if (get(fdfopos) == ON) then
                    P.commandtableentry(TEXT, "Copilot Flightdirector On")
                else
                    P.commandtableentry(TEXT, "Copilot Flightdirector Off")
                end
                P.fdfopostemp = get(fdfopos)
            end
        end
    end

    if ((get(efiswxpilotpos) ~= P.efiswxpilotpostemp) or (get(efiswxfopos) ~= P.efiswxfopostemp)) then
        if ((get(efiswxpilotpos) ~= P.efiswxpilotpostemp) and (get(efiswxfopos) ~= P.efiswxfopostemp) and (get(efiswxpilotpos) == get(efiswxfopos))) then
            if (get(efiswxpilotpos) == ON) then
                P.commandtableentry(TEXT, "Both Weather Radars On")
            elseif (get(efisterrpilotpos) == OFF) then
                P.commandtableentry(TEXT, "Both Weather Radars Off")
            end
            P.efiswxpilotpostemp = get(efiswxpilotpos)
            P.efiswxfopostemp = get(efiswxfopos)
        else
            if (get(efiswxpilotpos) ~= P.efiswxpilotpostemp) then
                if (get(efiswxpilotpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot Weather Radar On")
                elseif (get(efisterrpilotpos) == OFF) then
                    P.commandtableentry(TEXT, "Pilot Weather Radar Off")
                end
                P.efiswxpilotpostemp = get(efiswxpilotpos)
            end

            if (get(efiswxfopos) ~= P.efiswxfopostemp) then
                if (get(efiswxfopos) == ON) then
                    P.commandtableentry(TEXT, "Copilot Weather Radar On")

                elseif (get(efisterrfopos) == OFF) then
                    P.commandtableentry(TEXT, "Copilot Weather Radar Off")
                end
                P.efiswxfopostemp = get(efiswxfopos)
            end
        end
    end

    if ((get(efisterrpilotpos) ~= P.efisterrpilotpostemp) or (get(efisterrfopos) ~= P.efisterrfopostemp)) then
        if ((get(efisterrpilotpos) ~= P.efisterrpilotpostemp) and (get(efisterrfopos) ~= P.efisterrfopostemp) and (get(efisterrpilotpos) == get(efisterrfopos))) then
            if (get(efisterrpilotpos) == ON) then
                P.commandtableentry(TEXT, "Both Terrain Radars On")
            elseif (get(efiswxpilotpos) == OFF) then
                P.commandtableentry(TEXT, "Both Terrain Radars Off")
            end
            P.efisterrpilotpostemp = get(efisterrpilotpos)
            P.efisterrfopostemp = get(efisterrfopos)
        else
            if (get(efisterrpilotpos) ~= P.efisterrpilotpostemp) then
                if (get(efisterrpilotpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot Terrain Radar On")
                elseif (get(efiswxpilotpos) == OFF) then
                    P.commandtableentry(TEXT, "Pilot Terrain Radar Off")
                end
                P.efisterrpilotpostemp = get(efisterrpilotpos)
            end

            if (get(efisterrfopos) ~= P.efisterrfopostemp) then
                if (get(efisterrfopos) == ON) then
                    P.commandtableentry(TEXT, "Copilot Terrain Radar On")
                elseif (get(efiswxfopos) == OFF) then
                    P.commandtableentry(TEXT, "Copilot Terrain Radar Off")
                end
                P.efisterrfopostemp = get(efisterrfopos)
            end
        end
    end

    if ((get(efisdatapilotpos) ~= P.efisdatapilotpostemp) or (get(efisdatafopos) ~= P.efisdatafopostemp)) then
        if ((get(efisdatapilotpos) ~= P.efisdatapilotpostemp) and (get(efisdatafopos) ~= P.efisdatafopostemp) and (get(efisdatafopos) == get(efisdatafopos))) then
            if (get(efisdatapilotpos) == ON) then
                P.commandtableentry(TEXT, "Both E F I S Data On")
            else
                P.commandtableentry(TEXT, "Both E F I S DATA Off")
            end
            P.efisdatapilotpostemp = get(efisdatapilotpos)
            P.efisdatafopostemp = get(efisdatafopos)
        else
            if (get(efisdatapilotpos) ~= P.efisdatapilotpostemp) then
                if (get(efisdatapilotpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot E F I S Data On")
                else
                    P.commandtableentry(TEXT, "Pilot E F I S Data Off")
                end
                P.efisdatapilotpostemp = get(efisdatapilotpos)
            end

            if (get(efisdatafopos) ~= P.efisdatafopostemp) then
                if (get(efisdatafopos) == ON) then
                    P.commandtableentry(TEXT, "Copilot E F I S Data On")
                else
                    P.commandtableentry(TEXT, "Copilot E F I S Data Off")
                end
                P.efisdatafopostemp = get(efisdatafopos)
            end
        end
    end

       if ((get(efisfixpilotpos) ~= P.efisfixpilotpostemp) or (get(efisfixfopos) ~= P.efisfixfopostemp)) then
        if ((get(efisfixpilotpos) ~= P.efisfixpilotpostemp) and (get(efisfixfopos) ~= P.efisfixfopostemp) and (get(efisfixfopos) == get(efisfixfopos))) then
            if (get(efisfixpilotpos) == ON) then
                P.commandtableentry(TEXT, "Both E F I S Waypoint On")
            else
                P.commandtableentry(TEXT, "Both E F I S Waypoint Off")
            end
            P.efisfixpilotpostemp = get(efisfixpilotpos)
            P.efisfixfopostemp = get(efisfixfopos)
        else
            if (get(efisfixpilotpos) ~= P.efisfixpilotpostemp) then
                if (get(efisfixpilotpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot E F I S Waypoint On")
                else
                    P.commandtableentry(TEXT, "Pilot E F I S Waypoint Off")
                end
                P.efisfixpilotpostemp = get(efisfixpilotpos)
            end

            if (get(efisfixfopos) ~= P.efisfixfopostemp) then
                if (get(efisfixfopos) == ON) then
                    P.commandtableentry(TEXT, "Copilot E F I S Waypoint On")
                else
                    P.commandtableentry(TEXT, "Copilot E F I S Waypoint Off")
                end
                P.efisfixfopostemp = get(efisfixfopos)
            end
        end
    end

    if ((get(efisairportpilotpos) ~= P.efisairportpilotpostemp) or (get(efisairportfopos) ~= P.efisairportfopostemp)) then
        if ((get(efisairportpilotpos) ~= P.efisairportpilotpostemp) and (get(efisairportfopos) ~= P.efisairportfopostemp) and (get(efisairportpilotpos) == get(efisairportfopos))) then
            if (get(efisairportpilotpos) == ON) then
                P.commandtableentry(TEXT, "Both E F I S Airport On")
            else
                P.commandtableentry(TEXT, "Both E F I S Airport Off")
            end
            P.efisairportpilotpostemp = get(efisairportpilotpos)
            P.efisairportfopostemp = get(efisairportfopos)
        else
            if (get(efisairportpilotpos) ~= P.efisairportpilotpostemp) then
                if (get(efisairportpilotpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot E F I S Airport On")
                else
                    P.commandtableentry(TEXT, "Pilot E F I S Airport Off")
                end
                P.efisairportpilotpostemp = get(efisairportpilotpos)
            end

            if (get(efisairportfopos) ~= P.efisairportfopostemp) then
                if (get(efisairportfopos) == ON) then
                    P.commandtableentry(TEXT, "Copilot E F I S Airport On")
                else
                    P.commandtableentry(TEXT, "Copilot E F I S Airport Off")
                end
                P.efisairportfopostemp = get(efisairportfopos)
            end
        end
    end

    if ((get(efispospilotpos) ~= P.efispospilotpostemp) or (get(efisposfopos) ~= P.efisposfopostemp)) then
        if ((get(efispospilotpos) ~= P.efispospilotpostemp) and (get(efisposfopos) ~= P.efisposfopostemp) and (get(efispospilotpos) == get(efisposfopos))) then
            if (get(efispospilotpos) == ON) then
                P.commandtableentry(TEXT, "Both E F I S Position On")
            else
                P.commandtableentry(TEXT, "Both E F I S Position Off")
            end
            P.efispospilotpostemp = get(efispospilotpos)
            P.efisposfopostemp = get(efisposfopos)
        else
            if (get(efispospilotpos) ~= P.efispospilotpostemp) then
                if (get(efispospilotpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot E F I S Position On")
                else
                    P.commandtableentry(TEXT, "Pilot E F I S Position Off")
                end
                P.efispospilotpostemp = get(efispospilotpos)
            end

            if (get(efisposfopos) ~= P.efisposfopostemp) then
                if (get(efisposfopos) == ON) then
                    P.commandtableentry(TEXT, "Copilot E F I S Position On")
                else
                    P.commandtableentry(TEXT, "Copilot E F I S Position Off")
                end
                P.efisposfopostemp = get(efisposfopos)
            end
        end
    end

    if ((get(efisvorpilotpos) ~= P.efisvorpilotpostemp) or (get(efisvorfopos) ~= P.efisvorfopostemp)) then
        if ((get(efisvorpilotpos) ~= P.efisvorpilotpostemp) and (get(efisvorfopos) ~= P.efisvorfopostemp) and (get(efisvorpilotpos) == get(efisvorfopos))) then
            if (get(efisvorpilotpos) == ON) then
                P.commandtableentry(TEXT, "Both E F I S Station On")
            else
                P.commandtableentry(TEXT, "Both E F I S Station Off")
            end
            P.efisvorpilotpostemp = get(efisvorpilotpos)
            P.efisvorfopostemp = get(efisvorfopos)
        else
            if (get(efisvorpilotpos) ~= P.efisvorpilotpostemp) then
                if (get(efisvorpilotpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot E F I S Station On")
                else
                    P.commandtableentry(TEXT, "Pilot E F I S Station Off")
                end
                P.efisvorpilotpostemp = get(efisvorpilotpos)
            end

            if (get(efisvorfopos) ~= P.efisvorfopostemp) then
                if (get(efisvorfopos) == ON) then
                    P.commandtableentry(TEXT, "Copilot E F I S Station On")
                else
                    P.commandtableentry(TEXT, "Copilot E F I S Station Off")
                end
                P.efisvorfopostemp = get(efisvorfopos)
            end
        end
    end

    if (get(mmrinstalled) == ON) then
        if ((get(mmrcptactmode) ~= P.mmrcptactmodetemp) or (get(mmrcptactvalue) ~= P.mmrcptactvaluetemp) or (get(mmrfoactmode) ~= P.mmrfoactmodetemp) or
            (get(mmrfoactvalue) ~= P.mmrfoactvaluetemp)) then
            local mmrstring = ""
            local mmrchannel = 0
            if (((get(mmrcptactmode) ~= P.mmrcptactmodetemp) or (get(mmrcptactvalue) ~= P.mmrcptactvaluetemp)) and
                ((get(mmrfoactmode) ~= P.mmrfoactmodetemp) or (get(mmrfoactvalue) ~= P.mmrfoactvaluetemp)) and (get(mmrcptactmode) == get(mmrfoactmode)) and
                (get(mmrcptactvalue) == get(mmrfoactvalue))) then
                if (get(mmrcptactmode) == MMRLOC) then
                    mmrstring = "Both M M R V O R "
                    mmrchannel = get(mmrcptactvalue) / 100
                elseif (get(mmrcptactmode) == MMRILS) then
                    mmrstring = "Both M M R I L S "
                    mmrchannel = get(mmrcptactvalue) / 100
                elseif (get(mmrcptactmode) == MMRGLS) then
                    mmrstring = "Both M M R G L S "
                    mmrchannel = get(mmrcptactvalue)
                elseif (get(mmrcptactmode) == MMRLPV) then
                    mmrstring = "Both M M R L P V "
                    mmrchannel = get(mmrcptactvalue)
                end
            else
                if ((get(mmrcptactmode) ~= get(mmrcptactmode)) or (get(mmrcptactvalue) ~= P.mmrcptactvaluetemp)) then
                    if (get(mmrcptactmode) == MMRLOC) then
                        mmrstring = "Pilot M M R V O R "
                        mmrchannel = get(mmrcptactvalue) / 100
                    elseif (get(mmrcptactmode) == MMRILS) then
                        mmrstring = "Pilot M M R I L S "
                        mmrchannel = get(mmrcptactvalue) / 100
                    elseif (get(mmrcptactmode) == MMRGLS) then
                        mmrstring = "Pilot M M R G L S "
                        mmrchannel = get(mmrcptactvalue)
                    elseif (get(mmrcptactmode) == MMRLPV) then
                        mmrstring = "Pilot M M R L P V "
                        mmrchannel = get(mmrcptactvalue)
                    end
                end

                if ((get(mmrfoactmode) ~= P.mmrfoactmodetemp) or (get(mmrfoactvalue) ~= P.mmrfoactvaluetemp)) then
                    if (get(mmrfoactmode) == MMRLOC) then
                        mmrstring = "Copilot M M R V O R "
                        mmrchannel = get(mmrfoactvalue) / 100
                    elseif (get(mmrfoactmode) == MMRILS) then
                        mmrstring = "Copilot M M R I L S "
                        mmrchannel = get(mmrfoactvalue) / 100
                    elseif (get(mmrfoactmode) == MMRGLS) then
                        mmrstring = "Copilot M M R G L S "
                        mmrchannel = get(mmrfoactvalue)
                    elseif (get(mmrfoactmode) == MMRLPV) then
                        mmrstring = "Copilot M M R L P V "
                        mmrchannel = get(mmrfoactvalue)
                    end
                end
            end

            P.commandtableentry(TEXT, mmrstring .. tostring(mmrchannel))

            P.mmrcptactmodetemp = get(mmrcptactmode)
            P.mmrcptactvaluetemp = get(mmrcptactvalue)
            P.mmrfoactmodetemp = get(mmrfoactmode)
            P.mmrfoactvaluetemp = get(mmrfoactvalue)
            P.mmrcptstdbymodetemp = get(mmrcptstdbymode)
            P.mmrfostdbymodetemp = get(mmrfostdbymode)
        else
            if ((get(mmrcptstdbymode) ~= P.mmrcptstdbymodetemp) or (get(mmrfostdbymode) ~= P.mmrfostdbymodetemp)) then
                if ((get(mmrcptstdbymode) ~= P.mmrcptstdbymodetemp2) or (get(mmrfostdbymode) ~= P.mmrfostdbymodetemp2)) then
                    P.mmrcptstdbymodetemp2 = get(mmrcptstdbymode)
                    P.mmrfostdbymodetemp2 = get(mmrfostdbymode)
                else
                    if (get(mmrcptstdbymode) == get(mmrfostdbymode)) then
                        if (get(mmrcptstdbymode) == MMRLOC) then
                            P.commandtableentry(TEXT, "Both M M R Standby V O R")
                        elseif (get(mmrcptstdbymode) == MMRILS) then
                            P.commandtableentry(TEXT, "Both M M R Standby I L S")
                        elseif (get(mmrcptstdbymode) == MMRGLS) then
                            P.commandtableentry(TEXT, "Both M M R Standby G L S")
                        elseif (get(mmrcptstdbymode) == MMRLPV) then
                            P.commandtableentry(TEXT, "Both M M R Standby L P V")
                        end
                    else
                        if (get(mmrcptstdbymode) ~= P.mmrcptstdbymodetemp) then
                            if (get(mmrcptstdbymode) == MMRLOC) then
                                P.commandtableentry(TEXT, "Pilot M M R Standby V O R")
                            elseif (get(mmrcptstdbymode) == MMRILS) then
                                P.commandtableentry(TEXT, "Pilot M M R Standby I L S")
                            elseif (get(mmrcptstdbymode) == MMRGLS) then
                                P.commandtableentry(TEXT, "Pilot M M R Standby G L S")
                            elseif (get(mmrcptstdbymode) == MMRLPV) then
                                P.commandtableentry(TEXT, "Pilot M M R Standby L P V")
                            end
                        end

                        if (get(mmrfostdbymode) ~= P.mmrfostdbymodetemp) then
                            if (get(mmrfostdbymode) == MMRLOC) then
                                P.commandtableentry(TEXT, "Copilot M M R Standby V O R")
                            elseif (get(mmrfostdbymode) == MMRILS) then
                                P.commandtableentry(TEXT, "Copilot M M R Standby I L S")
                            elseif (get(mmrfostdbymode) == MMRGLS) then
                                P.commandtableentry(TEXT, "Copilot M M R Standby G L S")
                            elseif (get(mmrfostdbymode) == MMRLPV) then
                                P.commandtableentry(TEXT, "Copilot M M R Standby L P V")
                            end

                            P.mmrfostdbymodetemp = get(mmrfostdbymode)
                        end
                    end

                    P.mmrcptactmodetemp = get(mmrcptactmode)
                    P.mmrcptactvaluetemp = get(mmrcptactvalue)
                    P.mmrfoactmodetemp = get(mmrfoactmode)
                    P.mmrfoactvaluetemp = get(mmrfoactvalue)
                    P.mmrcptstdbymodetemp = get(mmrcptstdbymode)
                    P.mmrcptstdbymodetemp2 = get(mmrcptstdbymode)
                    P.mmrfostdbymodetemp = get(mmrfostdbymode)
                    P.mmrfostdbymodetemp2 = get(mmrfostdbymode)
                end
            end
        end
    else
        if ((get(nav1freq) ~= P.nav1freqtemp) or (get(nav2freq) ~= P.nav2freqtemp)) then
            if (get(nav1freq) == get(nav2freq)) then
                P.commandtableentry(TEXT, "Both N A V " .. addspaces(formatILSFrequency(get(nav1freq))))

                P.nav1freqtemp = get(nav1freq)
                P.nav2freqtemp = get(nav2freq)
            else
                if (get(nav1freq) ~= P.nav1freqtemp) then
                    P.commandtableentry(TEXT, "N A V 1 " .. addspaces(formatILSFrequency(get(nav1freq))))

                    P.nav1freqtemp = get(nav1freq)
                end

                if (get(nav2freq) ~= P.nav2freqtemp) then
                    P.commandtableentry(TEXT, "N A V 2 " .. addspaces(formatILSFrequency(get(nav1freq))))

                    P.nav2freqtemp = get(nav2freq)
                end
            end
        end
    end

    if ((get(centertanklswitch) ~= P.centertanklswitchtemp) or (get(centertankrswitch) ~= P.centertankrswitchtemp)) then
        if ((get(centertanklswitch) ~= P.centertanklswitchtemp) and (get(centertankrswitch) ~= P.centertankrswitchtemp) and (get(centertanklswitch) == get(centertankrswitch))) then
            if (get(centertanklswitch) == ON) then
                P.commandtableentry(TEXT, "Both Center Tank Fuel Pumps On")
            else
                P.commandtableentry(TEXT, "Both Center Tank Fuel Pumps Off")
            end
            P.centertanklswitchtemp = get(centertanklswitch)
            P.centertankrswitchtemp = get(centertankrswitch)
        else
            if (get(centertanklswitch) ~= P.centertanklswitchtemp) then
                if (get(centertanklswitch) == ON) then
                    P.commandtableentry(TEXT, "Left Center Tank Fuel Pump On")
                else
                    P.commandtableentry(TEXT, "Left Center Tank Fuel Pump Off")
                end
                P.centertanklswitchtemp = get(centertanklswitch)
            end

            if (get(centertankrswitch) ~= P.centertankrswitchtemp) then
                if (get(centertankrswitch) == ON) then
                    P.commandtableentry(TEXT, "Right Center Tank Fuel Pump On")
                else
                    P.commandtableentry(TEXT, "Right Center Tank Fuel Pump Off")
                end
                P.centertankrswitchtemp = get(centertankrswitch)
            end
        end
    end

    if ((get(lefttanklswitch) ~= P.lefttanklswitchtemp) or (get(lefttankrswitch) ~= P.lefttankrswitchtemp)) then
        if ((get(lefttanklswitch) ~= P.lefttanklswitchtemp) and (get(lefttankrswitch) ~= P.lefttankrswitchtemp) and (get(lefttanklswitch) == get(lefttankrswitch))) then
            if (get(lefttanklswitch) == ON) then
                P.commandtableentry(TEXT, "Both Left Wing Tank Fuel Pumps On")
            else
                P.commandtableentry(TEXT, "Both Left Wing Tank Fuel Pumps Off")
            end
            P.lefttanklswitchtemp = get(lefttanklswitch)
            P.lefttankrswitchtemp = get(lefttankrswitch)
        else
            if (get(lefttanklswitch) ~= P.lefttanklswitchtemp) then
                if (get(lefttanklswitch) == ON) then
                    P.commandtableentry(TEXT, "Left Wing Tank After Fuel Pump On")
                else
                    P.commandtableentry(TEXT, "Left Wing Tank After Fuel Pump Off")
                end
                P.lefttanklswitchtemp = get(lefttanklswitch)
            end

            if (get(lefttankrswitch) ~= P.lefttankrswitchtemp) then
                if (get(lefttankrswitch) == ON) then
                    P.commandtableentry(TEXT, "Right Wing Tank Forward Fuel Pump On")
                else
                    P.commandtableentry(TEXT, "Right Wing Tank Forward Fuel Pump Off")
                end
                P.lefttankrswitchtemp = get(lefttankrswitch)
            end
        end
    end

    if ((get(righttanklswitch) ~= P.righttanklswitchtemp) or (get(righttankrswitch) ~= P.righttankrswitchtemp)) then
        if ((get(righttanklswitch) ~= P.righttanklswitchtemp) and (get(righttankrswitch) ~= P.righttankrswitchtemp) and (get(righttanklswitch) == get(righttankrswitch))) then
            if (get(righttanklswitch) == ON) then
                P.commandtableentry(TEXT, "Both Right Wing Tank Fuel Pumps On")
            else
                P.commandtableentry(TEXT, "Both Right Wing Tank Fuel Pumps Off")
            end
            P.righttanklswitchtemp = get(righttanklswitch)
            P.righttankrswitchtemp = get(righttankrswitch)
        else
            if (get(righttanklswitch) ~= P.righttanklswitchtemp) then
                if (get(righttanklswitch) == ON) then
                    P.commandtableentry(TEXT, "Right Wing Tank Forward Fuel Pump On")
                else
                    P.commandtableentry(TEXT, "Right Wing Tank Forward Fuel Pump Off")
                end
                P.righttanklswitchtemp = get(righttanklswitch)
            end

            if (get(righttankrswitch) ~= P.righttankrswitchtemp) then
                if (get(righttankrswitch) == ON) then
                    P.commandtableentry(TEXT, "Right Wing Tank After Fuel Pump On")
                else
                    P.commandtableentry(TEXT, "Right Wing Tank After Fuel Pump Off")
                end
                P.righttankrswitchtemp = get(righttankrswitch)
            end
        end
    end

    if ((get(starter1pos) ~= P.starter1postemp) or (get(starter2pos) ~= P.starter2postemp)) then
        local starterstring = ""
        local statestring = ""
        if (((get(starter1pos) ~= P.starter1postemp) and (get(starter2pos) ~= P.starter2postemp)) and (get(starter1pos) == get(starter2pos))) then
            starterstring = "Both Starters "
            if (get(starter1pos) == GROUND) then
                statestring = "Ground"
            elseif (get(starter1pos) == AUTO) then
                if (get(starterauto) == ON) then
                    statestring = "Auto"
                else
                    statestring = "Off"
                end
            elseif (get(starter1pos) == CONT) then
                statestring = "Continuous"
            elseif (get(starter1pos) == FLIGHT) then
                statestring = "Flight"
            end

            P.starter1postemp = get(starter1pos)
            P.starter2postemp = get(starter2pos)
        else
            if (get(starter1pos) ~= P.starter1postemp) then
                starterstring = "Engine 1 Starter "
                if (get(starter1pos) == GROUND) then
                    statestring = "Ground"
                elseif (get(starter1pos) == AUTO) then
                    if (get(starterauto) == ON) then
                        statestring = "Auto"
                    else
                        statestring = "Off"
                    end
                elseif (get(starter1pos) == CONT) then
                    statestring = "Continuous"
                elseif (get(starter1pos) == FLIGHT) then
                    statestring = "Flight"
                end

                P.starter1postemp = get(starter1pos)
            end

            if (get(starter2pos) ~= P.starter2postemp) then
                starterstring = "Engine 2 Starter "
                if (get(starter2pos) == GROUND) then
                    statestring = "Ground"
                elseif (get(starter2pos) == AUTO) then
                    if (get(starterauto) == ON) then
                        statestring = "Auto"
                    else
                        statestring = "Off"
                    end
                elseif (get(starter2pos) == CONT) then
                    statestring = "Continuous"
                elseif (get(starter2pos) == FLIGHT) then
                    statestring = "Flight"
                end

                P.starter2postemp = get(starter2pos)
            end
        end

        P.commandtableentry(TEXT, starterstring .. statestring)
    end

    if ((get(mixture1pos) ~= P.mixture1postemp) or (get(mixture2pos) ~= P.mixture2postemp)) then
        if ((get(mixture1pos) ~= P.mixture1postemp) and (get(mixture2pos) ~= P.mixture2postemp) and (get(mixture1pos) == get(mixture2pos))) then
            mixturestring = "Both Engine Fuel Levers "
            if (get(mixture1pos) == ON) then
                statestring = "Idle"
            elseif (get(mixture1pos) == OFF) then
                statestring = "Cutoff"
            end

            P.mixture1postemp = get(mixture1pos)
            P.mixture2postemp = get(mixture2pos)
        else
            if (get(mixture1pos) ~= P.mixture1postemp) then
                mixturestring = "Engine 1 Fuel Lever "
                if (get(mixture1pos) == ON) then
                    statestring = "Idle"
                elseif (get(mixture1pos) == OFF) then
                    statestring = "Cutoff"
                end

                P.mixture1postemp = get(mixture1pos)
            end

            if (get(mixture2pos) ~= P.mixture2postemp) then
                mixturestring = "Engine 2 Fuel Lever "
                if (get(mixture2pos) == ON) then
                    statestring = "Idle"
                elseif (get(mixture2pos) == OFF) then
                    statestring = "Cutoff"
                end

                P.mixture2postemp = get(mixture2pos)
            end
        end

        P.commandtableentry(TEXT, mixturestring .. statestring)
    end

    if ((get(reverser1pos) ~= P.reverser1postemp) or (get(reverser2pos) ~= P.reverser2postemp)) then
        if ((get(reverser1pos) ~= P.reverser1postemp) and (get(reverser2pos) ~= P.reverser2postemp) and (get(reverser1pos) == get(reverser2pos))) then
            if (((get(reverser1pos) == OFF) and (P.reverser1postemp ~= OFF)) or ((get(reverser2pos) == OFF) and (P.reverser2postemp ~= OFF))) then
                P.commandtableentry(TEXT, "Both Reversers Off")
            elseif (((get(reverser1pos) ~= OFF) and (P.reverser1postemp == OFF)) or ((get(reverser2pos) ~= OFF) and (P.reverser2postemp == OFF))) then
                P.commandtableentry(TEXT, "Both Reversers On")
            end

            P.reverser1postemp = get(reverser1pos)
            P.reverser2postemp = get(reverser2pos)
        else
            if (get(reverser1pos) ~= P.reverser1postemp) then
                if ((get(reverser1pos) == OFF) and (P.reverser1postemp ~= OFF)) then
                    P.commandtableentry(TEXT, "Reverser 1 Off")
                elseif ((get(reverser1pos) ~= OFF) and (P.reverser1postemp == OFF)) then
                    P.commandtableentry(TEXT, "Reverser 1 On")
                end

                P.reverser1postemp = get(reverser1pos)
            end

            if (get(reverser2pos) ~= P.reverser2postemp) then
                if ((get(reverser2pos) == OFF) and (P.reverser2postemp ~= OFF)) then
                    P.commandtableentry(TEXT, "Reverser 2 Off")
                elseif ((get(reverser2pos) ~= OFF) and (P.reverser2postemp == OFF)) then
                    P.commandtableentry(TEXT, "Reverser 2 On")
                end

                P.reverser2postemp = get(reverser2pos)
            end
        end
    end

    if (get(gpuon) ~= P.gpuontemp) then
        if (get(gpuon) == ON) then
            P.commandtableentry(TEXT, "Ground Power ON")
        else
            P.commandtableentry(TEXT, "Ground Power Off")
        end
        P.gpuontemp = get(gpuon)
    end

    if ((roundnumber(get(announcsourceoff1),1) ~= P.announcsourceoff1temp) or (roundnumber(get(announcsourceoff2),1) ~= P.announcsourceoff2temp)) then
        if (get(apurunning) == ON) then
            if ((get(apupowerbus1) == get(apupowerbus2)) and (get(announcsourceoff1) == get(announcsourceoff2)) and (get(announcsourceoff1) ~= P.announcsourceoff1temp) and (get(announcsourceoff2) ~= P.announcsourceoff2temp)) then
                if ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    P.commandtableentry(TEXT, "A P U Generator ON")
                elseif not ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    P.commandtableentry(TEXT, "A P U Generators OFF")
                end
            else
                if (get(announcsourceoff1) ~= P.announcsourceoff1temp) then
                    if ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                        P.commandtableentry(TEXT, "A P U Generator 1 On")
                    elseif not ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                        P.commandtableentry(TEXT, "A P U Generator 1 Off")
                    end
                end

                if (get(announcsourceoff2) ~= P.announcsourceoff2temp) then
                    if ((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                        P.commandtableentry(TEXT, "A P U Generator 2 On")
                    elseif not ((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                        P.commandtableentry(TEXT, "A P U Generator 2 Off")
                    end
                end
            end
        end
        P.announcsourceoff1temp = roundnumber(get(announcsourceoff1),1)
        P.announcsourceoff2temp = roundnumber(get(announcsourceoff2),1)
    end

    if ((get(gen1pos) ~= P.gen1postemp) or (get(gen2pos) ~= P.gen2postemp)) then
        if ((get(gen1pos) ~= P.gen1postemp) and (get(gen2pos) ~= P.gen2postemp) and (get(gen1pos) == get(gen2pos))) then
            if (get(gen1pos) == ON) then
                P.commandtableentry(TEXT, "Both Generators ON")
            else
                P.commandtableentry(TEXT, "Both Generators OFF")
            end
            P.gen1postemp = get(gen1pos)
            P.gen2postemp = get(gen2pos)
        else
            if (get(gen1pos) ~= P.gen1postemp) then
                if (get(gen1pos) == ON) then
                    P.commandtableentry(TEXT, "Generator 1 On")
                else
                    P.commandtableentry(TEXT, "Generator 1 Off")
                end
                P.gen1postemp = get(gen1pos)
            end

            if (get(gen2pos) ~= P.gen2postemp) then
                if (get(gen2pos) == ON) then
                    P.commandtableentry(TEXT, "Generator 2 On")
                else
                    P.commandtableentry(TEXT, "Generator 2 Off")
                end
                P.gen2postemp = get(gen2pos)
            end
        end
    end

    if ((get(captainprobepos) ~= P.captainprobepostemp) or (get(foprobepos) ~= P.foprobepostemp)) then
        if ((get(captainprobepos) ~= P.captainprobepostemp) and (get(foprobepos) ~= P.foprobepostemp) and (get(captainprobepos) == get(foprobepos))) then
            if (get(captainprobepos) == ON) then
                P.commandtableentry(TEXT, "Both Probe Heat ON")
            else
                P.commandtableentry(TEXT, "Both Probe Heat OFF")
            end
            P.captainprobepostemp = get(captainprobepos)
            P.foprobepostemp = get(foprobepos)
        else
            if (get(captainprobepos) ~= P.captainprobepostemp) then
                if (get(captainprobepos) == ON) then
                    P.commandtableentry(TEXT, "Left Probe Heat On")
                else
                    P.commandtableentry(TEXT, "Left Probe Heat Off")
                end
                P.captainprobepostemp = get(captainprobepos)
            end

            if (get(foprobepos) ~= P.foprobepostemp) then
                if (get(foprobepos) == ON) then
                    P.commandtableentry(TEXT, "Right Probe Heat On")
                else
                    P.commandtableentry(TEXT, "Right Probe Heat Off")
                end
                P.foprobepostemp = get(foprobepos)
            end
        end
    end

    if ((get(wheatlfwdpos) ~= P.wheatlfwdpostemp) or (get(wheatlsidepos) ~= P.wheatlsidepostemp)) then
        if ((get(wheatlfwdpos) ~= P.wheatlfwdpostemp) and (get(wheatlsidepos) ~= P.wheatlsidepostemp) and (get(wheatlfwdpos) == get(wheatlsidepos))) then
            if (get(wheatlfwdpos) == ON) then
                P.commandtableentry(TEXT, "Pilot Window Heat ON")
            else
                P.commandtableentry(TEXT, "Pilot Window Heat OFF")
            end
            P.wheatlfwdpostemp = get(wheatlfwdpos)
            P.wheatlsidepostemp = get(wheatlsidepos)
        else
            if (get(wheatlfwdpos) ~= P.wheatlfwdpostemp) then
                if (get(wheatlfwdpos) == ON) then
                    P.commandtableentry(TEXT, "Pilot Forward Window Heat On")
                else
                    P.commandtableentry(TEXT, "Pilot Forward Window Heat Off")
                end
                P.wheatlfwdpostemp = get(wheatlfwdpos)
            end

            if (get(wheatlsidepos) ~= P.wheatlsidepostemp) then
                if (get(wheatlsidepos) == ON) then
                    P.commandtableentry(TEXT, "Pilot Side Window Heat On")
                else
                    P.commandtableentry(TEXT, "Pilot Side Window Heat Off")
                end
                P.wheatlsidepostemp = get(wheatlsidepos)
            end
        end
    end

    if ((get(wheatrfwdpos) ~= P.wheatrfwdpostemp) or (get(wheatrsidepos) ~= P.wheatrsidepostemp)) then
        if ((get(wheatrfwdpos) ~= P.wheatrfwdpostemp) and (get(wheatrsidepos) ~= P.wheatrsidepostemp) and (get(wheatrfwdpos) == get(wheatrsidepos))) then
            if (get(wheatrfwdpos) == ON) then
                P.commandtableentry(TEXT, "Copilot Window Heat ON")
            else
                P.commandtableentry(TEXT, "Copilot Window Heat OFF")
            end
            P.wheatrfwdpostemp = get(wheatrfwdpos)
            P.wheatrsidepostemp = get(wheatrsidepos)
        else
            if (get(wheatrfwdpos) ~= P.wheatrfwdpostemp) then
                if (get(wheatrfwdpos) == ON) then
                    P.commandtableentry(TEXT, "Copilot Forward Window Heat On")
                else
                    P.commandtableentry(TEXT, "Copilot Forward Window Heat Off")
                end
                P.wheatrfwdpostemp = get(wheatrfwdpos)
            end

            if (get(wheatrsidepos) ~= P.wheatrsidepostemp) then
                if (get(wheatrsidepos) == ON) then
                    P.commandtableentry(TEXT, "Copilot Side Window Heat On")
                else
                    P.commandtableentry(TEXT, "Copilot Side Window Heat Off")
                end
                P.wheatrsidepostemp = get(wheatrsidepos)
            end
        end
    end

    if (get(flapleverpos) ~= P.flapleverpostemp) then
        if (get(flapleverpos) ~= P.flapleverpostemp2) then
            P.flapleverpostemp2 = get(flapleverpos)
        else
            if (get(flapleverpos) == FLAPSUP) then
                P.commandtableentry(TEXT, "Flaps Up")
            elseif (get(flapleverpos) == FLAPS1) then
                P.commandtableentry(TEXT, "Flaps 1")
            elseif (get(flapleverpos) == FLAPS2) then
                P.commandtableentry(TEXT, "Flaps 2")
            elseif (get(flapleverpos) == FLAPS5) then
                P.commandtableentry(TEXT, "Flaps 5")
            elseif (get(flapleverpos) == FLAPS10) then
                P.commandtableentry(TEXT, "Flaps 10")
            elseif (get(flapleverpos) == FLAPS15) then
                P.commandtableentry(TEXT, "Flaps 15")
            elseif (get(flapleverpos) == FLAPS25) then
                P.commandtableentry(TEXT, "Flaps 25")
            elseif (get(flapleverpos) == FLAPS30) then
                P.commandtableentry(TEXT, "Flaps 30")
            elseif (get(flapleverpos) == FLAPS40) then
                P.commandtableentry(TEXT, "Flaps 40")
            end

            P.flapleverpostemp = get(flapleverpos)
            P.flapleverpostemp2 = get(flapleverpos)
        end
    end

    if (get(bankanglepos) ~= P.bankanglepostemp) then
        if (get(bankanglepos) ~= P.bankanglepostemp2) then
            P.bankanglepostemp2 = get(bankanglepos)
        else
            P.commandtableentry(TEXT, "Bank Angle " .. getbankanglestring(get(bankanglepos)))
            P.bankanglepostemp = get(bankanglepos)
            P.bankanglepostemp2 = get(bankanglepos)
        end
    end

    if (get(gearhandlepos) ~= P.gearhandlepostemp) then
        if (get(gearhandlepos) == GEARUP) then
            P.commandtableentry(TEXT, "Landing Gear Up")
        elseif (get(gearhandlepos) == GEAROFF) then
            P.commandtableentry(TEXT, "Landing Gear Lever Off")
        elseif (get(gearhandlepos) == GEARDOWN) then
            P.commandtableentry(TEXT, "Landing Gear Down")
        end

        P.gearhandlepostemp = get(gearhandlepos)
    end

    if (get(parkingbrakepos) ~= P.parkingbrakepostemp) then
        if (get(parkingbrakepos) == ON) then
            P.commandtableentry(TEXT, "Parking Brake Set")
        else
            P.commandtableentry(TEXT, "Parking Brake Off")
        end

        P.parkingbrakepostemp = get(parkingbrakepos)
    end

    speedbrakeleverrounded = roundnumber(get(speedbrakelever), 1)

    if (speedbrakeleverrounded ~= P.speedbrakelevertemp) then
        if (speedbrakeleverrounded ~= P.speedbrakelevertemp2) then
            P.speedbrakelevertemp2 = speedbrakeleverrounded
        else
            if (speedbrakeleverrounded == OFF) then
                P.commandtableentry(TEXT, "Speedbrake Down")
            elseif (speedbrakeleverrounded == 0.1) then
                P.commandtableentry(TEXT, "Speedbrake Armed")
            elseif (speedbrakeleverrounded >= 0.5) then
                P.commandtableentry(TEXT, "Speedbrake Up")
            end

            P.speedbrakelevertemp = speedbrakeleverrounded
            P.speedbrakelevertemp2 = speedbrakeleverrounded
        end
    end

    if (get(autobrakepos) ~= P.autobrakepostemp) then
        if (get(autobrakepos) == AUTOBRAKERTO) then
            P.commandtableentry(TEXT, "Auto Brake R T O")
        elseif (get(autobrakepos) == AUTOBRAKEOFF) then
            P.commandtableentry(TEXT, "Auto Brake Off")
        elseif (get(autobrakepos) == AUTOBRAKE1) then
            P.commandtableentry(TEXT, "Auto Brake 1")
        elseif (get(autobrakepos) == AUTOBRAKE2) then
            P.commandtableentry(TEXT, "Auto Brake 2")
        elseif (get(autobrakepos) == AUTOBRAKE3) then
            P.commandtableentry(TEXT, "Auto Brake 3")
        elseif (get(autobrakepos) == AUTOBRAKEMAX) then
            P.commandtableentry(TEXT, "Auto Brake Maximum")
        end

        P.autobrakepostemp = get(autobrakepos)
    end

    if (get(autobrakedisarm) ~= P.autobrakedisarmtemp) then
        if (get(autobrakedisarm) ~= P.autobrakedisarmtemp2) then
            P.autobrakedisarmtemp2 = get(autobrakedisarm)
        else
            if (get(autobrakedisarm) == ON) then
                P.commandtableentry(TEXT, "Auto Brake Disarmed")
            end

            P.autobrakedisarmtemp = get(autobrakedisarm)
            P.autobrakedisarmtemp2 = get(autobrakedisarm)
        end
    end

    if ((get(packlpos) ~= P.packlpostemp) or (get(packrpos) ~= P.packrpostemp)) then
        local packstring = ""
        local statestring = ""
        if (((get(packlpos) ~= P.packlpostemp) and (get(packrpos) ~= P.packrpostemp)) and (get(packlpos) == get(packrpos))) then
            packstring = "Both Packs "
            if (get(packlpos) == PACKOFF) then
                statestring = "Off"
            elseif (get(packlpos) == PACKAUTO) then
                    statestring = "Auto"
            elseif (get(packlpos) == PACKHIGH) then
                statestring = "High"
            end

            P.packlpostemp = get(packlpos)
            P.packrpostemp = get(packrpos)
        else
            if (get(packlpos) ~= P.packlpostemp) then
                packstring = "Left Pack "
                if (get(packlpos) == PACKOFF) then
                    statestring = "Off"
                elseif (get(packlpos) == PACKAUTO) then
                    statestring = "Auto"
                elseif (get(packlpos) == PACKHIGH) then
                    statestring = "High"
                end

                P.packlpostemp = get(packlpos)
            end

            if (get(packrpos) ~= P.packrpostemp) then
                packstring = "Right Pack "
                if (get(packrpos) == PACKOFF) then
                    statestring = "Off"
                elseif (get(packrpos) == PACKAUTO) then
                    statestring = "Auto"
                elseif (get(packrpos) == PACKHIGH) then
                    statestring = "High"
                end

                P.packrpostemp = get(packrpos)
            end
        end

        P.commandtableentry(TEXT, packstring .. statestring)
    end

    if (get(isolvalvepos) ~= P.isolvalvepostemp) then
        if (get(isolvalvepos) == ISOLVALVECLOSE) then
            P.commandtableentry(TEXT, "Isolation Valve Closed")
        elseif (get(isolvalvepos) == ISOLVALVEAUTO) then
            P.commandtableentry(TEXT, "Isolation Valve Auto")
        elseif (get(isolvalvepos) == ISOLVALVEOPEN) then
            P.commandtableentry(TEXT, "Isolation Valve Open")
        end

        P.isolvalvepostemp = get(isolvalvepos)
    end

   if ((get(bleedair1pos) ~= P.bleedair1postemp) or (get(bleedair2pos) ~= P.bleedair2postemp)) then
        if (((get(bleedair1pos) ~= P.bleedair1postemp) and (get(bleedair2pos) ~= P.bleedair2postemp)) and (get(hydropos1) == get(hydropos2))) then
            if (get(bleedair1pos) == ON) then
                P.commandtableentry(TEXT, "Both Engine Bleed Air On")
            else
                P.commandtableentry(TEXT, "Both Engine Bleed Air Off")
            end

            P.bleedair1postemp = get(bleedair1pos)
            P.bleedair2postemp = get(bleedair2pos)
        else
            if (get(bleedair1pos) ~= P.bleedair1postemp) then
                if (get(bleedair1pos) == ON) then
                    P.commandtableentry(TEXT, "Engine 1 Bleed Air On")
                else
                    P.commandtableentry(TEXT, "Engine 1 Bleed Air Off")
                end
                P.bleedair1postemp = get(bleedair1pos)
            end

            if (get(bleedair2pos) ~= P.bleedair2postemp) then
                if (get(bleedair2pos) == ON) then
                    P.commandtableentry(TEXT, "Engine 2 Bleed Air On")
                else
                    P.commandtableentry(TEXT, "Engine 2 Bleed Air Off")
                end
                P.bleedair2postemp = get(bleedair2pos)
            end
        end
    end

    if (get(trimairpos) ~= P.trimairpostemp) then
        if (get(trimairpos) == ON) then
            P.commandtableentry(TEXT, "Trim Air On")
        else
            P.commandtableentry(TEXT, "Trim Air Off")
        end

        P.trimairpostemp = get(trimairpos)
    end

    if (get(lrecircfanpos) ~= P.lrecircfanpostemp) then
        if (get(lrecircfanpos) == ON) then
            P.commandtableentry(TEXT, "Left Recircling Fan On")
        else
            P.commandtableentry(TEXT, "Left Recircling Fan Off")
        end

        P.lrecircfanpostemp = get(lrecircfanpos)
    end

    if (get(rrecircfanpos) ~= P.rrecircfanpostemp) then
        if (get(rrecircfanpos) == ON) then
            P.commandtableentry(TEXT, "Right Recircling Fan On")
        else
            P.commandtableentry(TEXT, "Right Recircling Fan Off")
        end

        P.rrecircfanpostemp = get(rrecircfanpos)
    end

    if (get(bleedairapupos) ~= P.bleedairapupostemp) then
        if (get(bleedairapupos) == ON) then
            P.commandtableentry(TEXT, "A P U Bleed Air On")
        else
            P.commandtableentry(TEXT, "A P U Bleed Air Off")
        end

        P.bleedairapupostemp = get(bleedairapupos)
    end

    if (get(battery) ~= P.batterytemp) then
        if (get(battery) == ON) then
            P.commandtableentry(TEXT, "Battery On")
        else
            P.commandtableentry(TEXT, "Battery Off")
        end

        P.batterytemp = get(battery)
    end

    if ((get(apustarterpos) ~= P.apustarterpostemp) or (get(apurunning) ~= P.apurunningtemp)) then
        if ((get(apustarterpos) == ON) and (get(apurunning) == ON)) then
            P.commandtableentry(TEXT, "A P U Started")
        else
            if ((get(apustarterpos) ~= P.apustarterpostemp) and (get(apustarterpos) == OFF)) then
                P.commandtableentry(TEXT, "A P U Shutting Down")
            end
        end

        P.apustarterpostemp = get(apustarterpos)
        P.apurunningtemp = get(apurunning)
    end

    if (get(emergencylights) ~= P.emergencylightstemp) then
        if (get(emergencylights) == EMERGLIGHTSOFF) then
            P.commandtableentry(TEXT, "Emergengy Lights OFF")
        elseif (get(emergencylights) == EMERGLIGHTSARMED) then
            P.commandtableentry(TEXT, "Emergency Lights Armed")
        elseif (get(emergencylights) == EMERGLIGHTSON) then
            P.commandtableentry(TEXT, "Emergency Lights ON")
        end
        P.emergencylightstemp = get(emergencylights)
    end

    if ((get(hydro1pos) ~= P.hydro1postemp) or (get(hydro2pos) ~= P.hydro2postemp)) then
        if (((get(hydro1pos) ~= P.hydro1postemp) and (get(hydro2pos) ~= P.hydro2postemp)) and (get(hydropos1) == get(hydropos2))) then
            if (get(hydro1pos) == ON) then
                P.commandtableentry(TEXT, "Both Hydraulic Pumps On")
            else
                P.commandtableentry(TEXT, "Both Hydraulic Pumps Off")
            end

            P.hydro1postemp = get(hydro1pos)
            P.hydro2postemp = get(hydro2pos)
        else
            if (get(hydro1pos) ~= P.hydro1postemp) then
                if (get(hydro1pos) == ON) then
                    P.commandtableentry(TEXT, "Hydraulic Pump 1 On")
                else
                    P.commandtableentry(TEXT, "Hydraulic Pump 1 Off")
                end
                P.hydro1postemp = get(hydro1pos)
            end

            if (get(hydro2pos) ~= P.hydro2postemp) then
                if (get(hydro2pos) == ON) then
                    P.commandtableentry(TEXT, "Hydraulic Pump 2 On")
                else
                    P.commandtableentry(TEXT, "Hydraulic Pump 2 Off")
                end
                P.hydro2postemp = get(hydro2pos)
            end
        end
    end

    if ((get(elechydro1pos) ~= P.elechydro1postemp) or (get(elechydro2pos) ~= P.elechydro2postemp)) then
        if ((get(elechydro1pos) ~= P.elechydro1postemp) and (get(elechydro2pos) ~= P.elechydro2postemp) and (get(elechydro1pos) == get(elechydro2pos))) then
            if (get(elechydro1pos) == ON) then
                P.commandtableentry(TEXT, "Both Electrical Hydraulic Pumps On")
            else
                P.commandtableentry(TEXT, "Both Electrical Hydraulic Pumps Off")
            end

            P.elechydro1postemp = get(elechydro1pos)
            P.elechydro2postemp = get(elechydro2pos)
        else
            if (get(elechydro1pos) ~= P.elechydro1postemp) then
                if (get(elechydro1pos) == ON) then
                    P.commandtableentry(TEXT, "Electrical Hydraulic Pump 2 On")
                else
                    P.commandtableentry(TEXT, "Electrical Hydraulic Pump 2 Off")
                end
                P.elechydro1postemp = get(elechydro1pos)
            end

            if (get(elechydro2pos) ~= P.elechydro2postemp) then
                if (get(elechydro2pos) == ON) then
                    P.commandtableentry(TEXT, "Electrical Hydraulic Pump 1 On")
                else
                    P.commandtableentry(TEXT, "Electrical Hydraulic Pump 1 Off")
                end
                P.elechydro2postemp = get(elechydro2pos)
            end
        end
    end

    if (get(seatbeltsignpos) ~= P.seatbeltsignpostemp) then
        if (get(seatbeltsignpos) == SEATBELTSIGNOFF) then
            P.commandtableentry(TEXT, "Seatbelt Sign Off")
        elseif (get(seatbeltsignpos) == SEATBELTSIGNAUTO) then
            P.commandtableentry(TEXT, "Seatbelt Sign Auto")
        elseif (get(seatbeltsignpos) == SEATBELTSIGNON) then
            P.commandtableentry(TEXT, "Seatbelt Sign On")
        end

        P.seatbeltsignpostemp = get(seatbeltsignpos)
    end

    if (get(nosmokingsignpos) ~= P.nosmokingsignpostemp) then
        if (get(nosmokingsignpos) == NOSMOKINGSIGNOFF) then
            P.commandtableentry(TEXT, "No Smoking Sign Off")
        elseif (get(nosmokingsignpos) == NOSMOKINGSIGNAUTO) then
            P.commandtableentry(TEXT, "No Smoking Sign Auto")
        elseif (get(nosmokingsignpos) == NOSMOKINGSIGNON) then
            P.commandtableentry(TEXT, "No Smoking Sign On")
        end

        P.nosmokingsignpostemp = get(nosmokingsignpos)
    end

    if (get(domelightpos) ~= P.domelightpostemp) then
        if (get(domelightpos) == DOMELIGHTOFF) then
            P.commandtableentry(TEXT, "Dome Light Off")
        elseif (get(domelightpos) == DOMELIGHTDIM) then
            P.commandtableentry(TEXT, "Dome Light Dim")
        elseif (get(domelightpos) == DOMELIGHTBRIGHT) then
            P.commandtableentry(TEXT, "Dome Light Bright")
        end

        P.domelightpostemp = get(domelightpos)
    end

    if ((get(irsleftpos) ~= P.irsleftpostemp) or (get(irsrightpos) ~= P.irsrightpostemp)) then
        if ((get(irsleftpos) ~= P.irsleftpostemp2) or (get(irsrightpos) ~= P.irsrightpostemp2)) then
                P.irsleftpostemp2 = get(irsleftpos)
                P.irsrightpostemp2 = get(irsrightpos)
        else
            local irsstring = ""
            local statestring = ""
            if ((get(irsleftpos) ~= P.irsleftpostemp) and (get(irsrightpos) ~= P.irsrightpostemp) and (get(irsleftpos) == get(irsrightpos))) then
                irsstring = "Both I R S "
                if (get(irsleftpos) == IRSOFF) then
                    statestring = "Off"
                elseif (get(irsleftpos) == IRSALIGN) then
                    statestring = "Align"
                elseif (get(irsleftpos) == IRSNAV) then
                    statestring = "Nav"
                elseif (get(irsleftpos) == IRSATT) then
                    statestring = "Attention"
                end

                P.irsleftpostemp = get(irsleftpos)
                P.irsleftpostemp2 = get(irsleftpos)
                P.irsrightpostemp = get(irsrightpos)
                P.irsrightpostemp2 = get(irsrightpos)
            else
                if (get(irsleftpos) ~= P.irsleftpostemp) then
                    irsstring = "Left I R S "
                    if (get(irsleftpos) == IRSOFF) then
                        statestring = "Off"
                    elseif (get(irsleftpos) == IRSALIGN) then
                        statestring = "Align"
                    elseif (get(irsleftpos) == IRSNAV) then
                        statestring = "Nav"
                    elseif (get(irsleftpos) == IRSATT) then
                        statestring = "Attention"
                    end

                    P.irsleftpostemp = get(irsleftpos)
                    P.irsleftpostemp2 = get(irsleftpos)
                end

                if (get(irsrightpos) ~= P.irsrightpostemp) then
                    irsstring = "Right I R S "
                    if (get(irsrightpos) == IRSOFF) then
                        statestring = "Off"
                    elseif (get(irsrightpos) == IRSALIGN) then
                        statestring = "Align"
                    elseif (get(irsrightpos) == IRSNAV) then
                        statestring = "Nav"
                    elseif (get(irsrightpos) == IRSATT) then
                        statestring = "Attention"
                    end

                    P.irsrightpostemp = get(irsrightpos)
                    P.irsrightpostemp2 = get(irsrightpos)
                end
            end

            P.commandtableentry(TEXT, irsstring .. statestring)
        end
    end

    if (get(transpondercode) ~= P.transpondercodetemp) then
        if (get(transpondercode) ~= P.transpondercodetemp2) then
            P.transpondercodetemp2 = get(transpondercode)
        else
            P.commandtableentry(TEXT, "Transponder Code " .. addspaces(get(transpondercode)))
            P.transpondercodetemp = get(transpondercode)
            P.transpondercodetemp2 = get(transpondercode)
        end

    end

    if (P.configvalues[CONFIGAUTOWIPER] ~= ON) then
        if ((get(lwiperpos) ~= P.lwiperpostemp) or (get(rwiperpos) ~= P.rwiperpostemp)) then
            if ((get(lwiperpos) ~= P.lwiperpostemp2) or (get(rwiperpos) ~= P.rwiperpostemp2)) then
                P.lwiperpostemp2 = get(lwiperpos)
                P.rwiperpostemp2 = get(rwiperpos)
            else
                local wiperstring = ""
                local statestring = ""
                if (((get(lwiperpos) ~= P.lwiperpostemp) and (get(rwiperpos) ~= P.rwiperpostemp)) and (get(lwiperpos) == get(rwiperpos))) then
                    wiperstring = "Both Wipers "
                    if (get(lwiperpos) == WIPEROFF) then
                        statestring = "Off"
                    elseif (get(lwiperpos) == WIPERINT) then
                        statestring = "Interval"
                    elseif (get(lwiperpos) == WIPERLOW) then
                        statestring = "Low"
                    elseif (get(lwiperpos) == WIPERHIGH) then
                        statestring = "High"
                    end

                    P.lwiperpostemp = get(lwiperpos)
                    P.lwiperpostemp2 = get(lwiperpos)
                    P.rwiperpostemp = get(rwiperpos)
                    P.rwiperpostemp2 = get(rwiperpos)
                else
                    if (get(lwiperpos) ~= P.lwiperpostemp) then
                        wiperstring = "Left Wiper "
                        if (get(lwiperpos) == WIPEROFF) then
                            statestring = "Off"
                        elseif (get(lwiperpos) == WIPERINT) then
                            statestring = "Interval"
                        elseif (get(lwiperpos) == WIPERLOW) then
                            statestring = "Low"
                        elseif (get(lwiperpos) == WIPERHIGH) then
                            statestring = "High"
                        end

                        P.lwiperpostemp = get(lwiperpos)
                        P.lwiperpostemp2 = get(lwiperpos)
                    end

                    if (get(rwiperpos) ~= P.rwiperpostemp) then
                        wiperstring = "Right Wiper "
                        if (get(rwiperpos) == WIPEROFF) then
                            statestring = "Off"
                        elseif (get(rwiperpos) == WIPERINT) then
                            statestring = "Interval"
                        elseif (get(rwiperpos) == WIPERLOW) then
                            statestring = "Low"
                        elseif (get(rwiperpos) == WIPERHIGH) then
                            statestring = "High"
                        end

                        P.rwiperpostemp = get(rwiperpos)
                        P.rwiperpostemp2 = get(rwiperpos)
                    end
                end

                P.commandtableentry(TEXT, wiperstring .. statestring)
            end
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- ongoingtasks() function

function ongoingtasks()

    local nearesticaotmp = cleanstring(get(nearesticao))
    local depicaotmp = cleanstring(get(depicao))
    local desicaotmp = cleanstring(get(desicao))
    local deslandingalttmp = 0

if (P.getmetarcounter == 0) then
        if ((depicaotmp ~= P.depmetar.icaocode) and isvalidicao(depicaotmp)) then
            P.depmetar.metar = getMetar(depicaotmp)
            if P.depmetar.metar and P.depmetar.metar.raw_text and #P.depmetar.metar.raw_text > 0 then
                P.depmetar.icaocode = depicaotmp
                P.depmetar.metarfound = true
                P.depmetar.decodedmetar = decodemetar(P.depmetar.metar.raw_text)
            else
                P.depmetar.icaocode = "XXXX"
                P.depmetar.metarfound = false
                P.depmetar.decodedmetar = {}
            end
        elseif (not isvalidicao(depicaotmp) and (nearesticaotmp ~= P.depmetar.icaocode) and isvalidicao(nearesticaotmp)) then
            P.depmetar.metar = getMetar(nearesticaotmp)
            if P.depmetar.metar and P.depmetar.metar.raw_text and #P.depmetar.metar.raw_text > 0 then
                P.depmetar.icaocode = nearesticaotmp
                P.depmetar.metarfound = true
                P.depmetar.decodedmetar = decodemetar(P.depmetar.metar.raw_text)
            else
                P.depmetar.icaocode = "XXXX"
                P.depmetar.metarfound = false
                P.depmetar.decodedmetar = {}
            end
        end

        if (desicaotmp ~= P.desmetar.icaocode) and isvalidicao(desicaotmp) then
            P.desmetar.metar = getMetar(desicaotmp)
            if P.desmetar.metar and P.desmetar.metar.raw_text and #P.desmetar.metar.raw_text > 0 then
                P.desmetar.icaocode = desicaotmp
                P.desmetar.metarfound = true
                P.desmetar.decodedmetar = decodemetar(P.desmetar.metar.raw_text)
            else
                P.desmetar.icaocode = "XXXX"
                P.desmetar.metarfound = false
                P.desmetar.decodedmetar = {}
            end
        end

        if P.desmetar.metarfound and P.desmetar.decodedmetar then
            logtable(P.desmetar.decodedmetar, "DESMETAR")
        else
            sasl.logDebug("DESMETAR not found or not decoded for logging.")
        end

        if P.depmetar.metarfound and P.depmetar.decodedmetar then
            logtable(P.depmetar.decodedmetar, "DEPMETAR")
        else
            sasl.logDebug("DEPMETAR not found or not decoded for logging.")
        end

        P.getmetarcounter = 5
    else
        P.getmetarcounter = P.getmetarcounter - 1
    end

    if ((get(pausetod) == ON) and (P.remainingtimetoquit ~= 9999)) then
        if (get(simpaused) == ON) then
            if (P.remainingtimetoquit == 0) then
                P.remainingtimetoquit = P.configvalues[CONFIGTODPAUSEQUITTIME]
                helpers.command_once("laminar/B738/tab/save_flight" .. tonumber(P.configvalues[CONFIGSAVENUMBER]))
                helpers.command_once("sim/operation/quit")
            else
                P.remainingtimetoquit = P.remainingtimetoquit - 1
            end
        else
            P.remainingtimetoquit = P.configvalues[CONFIGTODPAUSEQUITTIME]
        end
    end

    if (P.remainingtimetosave ~= 9999) then
        if (P.remainingtimetosave == 0) then
            P.remainingtimetosave = P.configvalues[CONFIGSAVETIME]
            helpers.command_once("laminar/B738/tab/save_flight" .. tonumber(P.configvalues[CONFIGSAVENUMBER]))
        else
            P.remainingtimetosave = P.remainingtimetosave - 1
        end
    end

    if ((P.procedureloop1.lock == NOPROCEDURE) and (P.configvalues[CONFIGVOICEADVICEONLY] == ON)  and (get(airgroundsensor) == ON)) then
        if (((get(starter1pos) == GROUND) or (get(starter2pos) == GROUND)) and (get(beaconlights) == OFF)) then
            P.commandtableentry(ADVICE, "Set Collision Lights On")      
        elseif (((get(starter1pos) == GROUND) or (get(starter2pos) == GROUND)) and ((get(lefttanklswitch) == OFF) or (get(lefttankrswitch) == OFF) or (get(righttanklswitch) == OFF) or (get(righttankrswitch) == OFF))) then
            P.commandtableentry(ADVICE, "Set Wing Tank Fuel Pumps On")
        elseif (((get(starter1pos) == GROUND) or (get(starter2pos) == GROUND)) and ((get(packlpos) ~= PACKOFF) or (get(packrpos) ~= PACKOFF))) then
            P.commandtableentry(ADVICE, "Set Both Packs Off")
        elseif (((get(starter1pos) == GROUND) or (get(starter2pos) == GROUND)) and (get(bleedairapupos) ~= ON)) then
            P.commandtableentry(ADVICE, "Set A P U Bleed Air On")
        elseif ((get(starter2pos) == GROUND) and (get(isolvalvepos) ~= ISOLVALVEOPEN)) then
            P.commandtableentry(ADVICE, "Set Isolation Valve Open")
        elseif ((get(starter1pos) == GROUND) and (get(eng1n2percent) > 25) and (get(mixture1pos) == OFF)) then 
            P.commandtableentry(ADVICE, "Engine 1 N 2 at 25 Percent")        
        elseif ((get(starter2pos) == GROUND) and (get(eng2n2percent) > 25) and (get(mixture2pos) == OFF)) then 
            P.commandtableentry(ADVICE, "Engine 2 N 2 at 25 Percent")
        elseif ((get(atarmpos) == ARMED) and (get(atn1stat) == OFF) and (get(groundspeed) < 45) and (get(eng1n1percent) > 40) and (get(eng1n1percent) > 40)) then 
            P.commandtableentry(ADVICE, "Both Engine N 1 at 40 Percent")
        elseif ((get(apustarterpos) == ON) and (get(apugenoffbus) ~= OFF) and (get(gen1pos) == OFF) and (get(gen2pos) == OFF) and (not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)))) then
            P.commandtableentry(ADVICE, "A P U Running")
        end
    end

    if (P.procedureloop1.lock ~= COCKPITINITPROCEDURE) then
        if (P.ongoingtaskstepindex == 1) then
            if (enginesrunning(BOTH) and (P.configvalues[CONFIGAUTOCENTERTANKHANDLING] == ON)) then
                if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                    autocentertanks()
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    if ((get(centertanklbs) > 1000) and (get(centertanklpress) > 0) and (get(centertankrpress) > 0) and (get(centertankstat) > 0)) then
                        if ((get(centertanklswitch) == OFF) or (get(centertankrswitch) == OFF)) then
                            P.commandtableentry(ADVICE, "Set Center Tank Fuel Pumps On")
                            P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                        end
                    elseif ((get(centertanklbs) <= 1000)) or ((get(centertanklpress) == 0) and (get(centertankrpress) == 0)) then
                        if ((get(centertanklswitch) == ON) or (get(centertankrswitch) == ON)) then
                            P.commandtableentry(ADVICE, "Set Center Tank Fuel Pumps Off")
                            P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                        end
                    end
                end
            end
        elseif (P.ongoingtaskstepindex == 2) then
            if ( (P.flightstate < 3) and (get(fmccruisealt) ~= 0) and (get(fmccruisealt) ~= 20000)) then
                local fmccruisealttmp = roundnumber(get(fmccruisealt) / 500) * 500
                if (get(cabincruisealt)  ~= fmccruisealttmp) then
                    if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then 
                        set(cabincruisealt, get(fmccruisealttmp))
                    elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then 
                        P.commandtableentry(ADVICE, "Set Cabin Cruise Alitude " .. addspaces(fmccruisealttmp))
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                end
            end
        elseif (P.ongoingtaskstepindex == 3) then
             if ((P.flightstate < 4) and P.desmetar.metarfound) then
                local deslandingalttmp = 0
                if tonumber(P.desmetar.metar.elevation_m) then
                    deslandingalttmp = roundnumber((P.desmetar.metar.elevation_m * FEETTOMETER) / 50) * 50
                else
                    deslandingalttmp = roundnumber(get(desrwyalt) / 50) * 50
                end
                if (get(cabinlandingalt) ~= deslandingalttmp) then
                    if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                        set(cabinlandingalt, deslandingalttmp)
                    elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then 
                        P.commandtableentry(ADVICE, "Set Cabin Landing Alitude " .. addspaces(deslandingalttmp))
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                end
            end
        end
    elseif (P.ongoingtaskstepindex == 1) then
        P.ongoingtaskstepindex = 3
    end
    
    if (P.ongoingtaskstepindex == 4) then
        if (P.configvalues[CONFIGAUTOANTIICE] == ON) then
            if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                if ((P.flightstate < 5) and P.proceduretable[BEFORETAXIPROCEDURE].set) then
                    if ((get(frameice) > 0.01) and (get(altitude) < 30000)) then
                        iceprotection(ON)
                    elseif ((get(altitude) > 30000) or (get(tatdegc) > 10)) then
                        iceprotection(OFF)
                    end
                end
            elseif ((P.configvalues[CONFIGVOICEADVICEONLY] == ON) and (get(airgroundsensor) == OFF)) then
                if ((get(frameice) > 0.01) and (get(altitude) < 30000)) then                   
                    if ((get(eng1heatpos) == OFF) or (get(eng2heatpos) == OFF) or (get(wingheatpos) == OFF)) then
                        P.commandtableentry(ADVICE, "Caution Icing Detected, Switch Anti Icing On")
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                elseif (get(altitude) > 30000) then
                    if ((get(eng1heatpos) == ON) or (get(eng2heatpos) == ON) or (get(wingheatpos) == ON)) then                      
                        P.commandtableentry(ADVICE, "Above 30.000 feet, Switch Anti Icing Off")
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                elseif (get(tatdegc) > 10) then
                    if ((get(eng1heatpos) == ON) or (get(eng2heatpos) == ON) or (get(wingheatpos) == ON)) then
                        P.commandtableentry(ADVICE, "T A T above 10 degree, Switch Anti Icing Off")
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end 
                end
            end
        end
    elseif (P.ongoingtaskstepindex == 5) then
        if (P.configvalues[CONFIGAUTOWIPER] == ON) then
            if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then               
                if (get(groundspeed) > 250) then
                    autowiper(OFF)
                elseif ((get(apuon) == ON) or (get(apurunning) == ON) or enginesrunning(ENGINE1) or enginesrunning(ENGINE2)) then
                    autowiper(ON)
                elseif ((get(apuon) == OFF) and (get(apurunning) == OFF) and not enginesrunning(ENGINE1) and not enginesrunning(ENGINE2)) then
                    autowiper(OFF)
                end
            end
        end
    end

    if (((get(airgroundsensor) == ON) and (P.procedureloop1.lock == NOPROCEDURE) and (get(battery) == ON) and (get(mainbus) ~= OFF) and (P.flightstate == 0) and (get(taxilight) == OFF))) then
        if (P.ongoingtaskstepindex == 6) then
            if (P.configvalues[CONFIGAUTOBARO] == ON) then
                local baroinchtmp, baropastmp = getlocalqnh(DEPARTURE)
                if (roundnumber(math.abs(roundnumber(get(baropilot),2) - baroinchtmp),2) > 0.01) then
                    if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                        set(baropilot, baroinchtmp)
                    elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        if (get(baroinhpa) == ON) then
                            P.commandtableentry(ADVICE, "Set Q N H " .. addspaces(baropastmp))
                        else
                            P.commandtableentry(ADVICE, "Set Q N H " .. addspaces(baroinchtmp))
                        end
                        P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                    end
                end
            end
        elseif (P.ongoingtaskstepindex == 7) then
            if (get(trimcalc) > 0) and (get(trimcalc) ~= gettrim() and (get(groundspeed) < 45)) then
                if (((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON))) then
                    settotrim()
                    P.commandtableentry(TEXT, "Trim " .. tostring(get(trimcalc)))
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set Trim " .. tostring(get(trimcalc)))
                    P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                end
            end
        elseif (P.ongoingtaskstepindex == 8) then
            if ((get(v2speed) > 0) and (get(v2speed) ~= get(mcpspeed)) and (get(groundspeed) < 45)) then
                if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                    set(mcpspeed, get(v2speed))
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set M C P Speed " .. addspaces(get(v2speed)))
                    P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1         
                end
            end
        elseif (P.ongoingtaskstepindex == 9) then
            local headingrounded = nil
            if (isvalidicao(get(depicao)) and isvalidrwy(get(deprwy)) and tonumber(get(deprwyheading))) then
                headingrounded = roundnumber(get(deprwyheading))
            end
            local navrwyheading = getrwyheadingfromnavdata(get(depicao), get(deprwy))
            if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 2)))) then
                headingrounded = navrwyheading
            end
            if (headingrounded and (headingrounded ~= get(mcpheading)) and (get(groundspeed) < 45)) then
                if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) and (P.configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                    set(mcpheading, headingrounded)
                elseif (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, "Set M C P Heading " .. addspaces(headingrounded))
                    P.ongoingtaskstepindex = P.ongoingtaskstepindex - 1
                end
            end
        end
    elseif (P.ongoingtaskstepindex >= 5) then
        P.ongoingtaskstepindex = 9
    end

    if (P.ongoingtaskstepindex >= 9) then
        P.ongoingtaskstepindex = 1
    else
        P.ongoingtaskstepindex = P.ongoingtaskstepindex + 1
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- P.commandtableloop() function

function P.commandtableloop()

    if (#P.commandtable > 0) then

        if (P.commandtable[1][1] == COMMAND) then
            sasl.logInfo("YAL COMMAND: " .. P.commandtable[1][2])
            helpers.command_once(P.commandtable[1][2])
        elseif (P.commandtable[1][1] == TEXT) then
            sasl.logInfo("YAL XPLMSpeakString TEXT: " .. P.commandtable[1][2])
            if (P.configvalues[CONFIGVOICEREADBACK] == ON) then
                speak(P.commandtable[1][2])
            end
        elseif (P.commandtable[1][1] == ADVICE) then
            sasl.logInfo("YAL XPLMSpeakString ADVICE: " .. P.commandtable[1][2])
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                speak(P.commandtable[1][2])
            end
        end

        table.remove(P.commandtable, 1)

    end

    return true

end

function speak(text)

    local c_str = ffi.new("char[?]", #text + 1)
    ffi.copy(c_str, text)
    xplm.XPLMSpeakString(c_str)
end

--------------------------------------------------------------------------------------------------------------
-- P.procedureloop_1() function

function P.procedureloop_1()

    if (P.procedureloop1.lock ~= NOPROCEDURE) then
        if ((P.procedureloop1.stepindex == 0) and not P.procedureabort and not P.procedureskipstep) then
            if (P.proceduretable[P.procedureloop1.lock].name  ~= "") then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop1.lock].name .. " Procedure")
                else
                    P.commandtableentry(TEXT, P.proceduretable[P.procedureloop1.lock].name .. " Procedure")
                end
            end
        elseif ((P.procedureloop1.stepindex <= P.proceduretable[P.procedureloop1.lock].steps) and not P.procedureabort and not proceduskipstep) then
                P.proceduretable[P.procedureloop1.lock].procedurefunction()
        elseif ((((P.procedureloop1.stepindex > P.proceduretable[P.procedureloop1.lock].steps) or P.procedureabort)) and not P.procedureskipstep) then
            if (P.procedureloop1.stepindex > P.proceduretable[P.procedureloop1.lock].steps) then
                if (P.proceduretable[P.procedureloop1.lock].name  ~= "") then
                    if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop1.lock].name .. " Procedure Complete")
                    else
                        P.commandtableentry(TEXT, P.proceduretable[P.procedureloop1.lock].name .. " Procedure Complete")
                    end
                end
            elseif P.procedureabort then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop1.lock].name .. " Procedure Aborted")
                else
                    P.commandtableentry(TEXT, P.proceduretable[P.procedureloop1.lock].name .. " Procedure Aborted")
                end
                P.procedureabort = false
            end
            P.proceduretable[P.procedureloop1.lock].set = true
            P.procedureloop1.lock = NOPROCEDURE
        end
        
        if (P.procedureloop1.lock == NOPROCEDURE) then
            P.procedureloop1.stepindex = 0
        else
            P.procedureloop1.stepindex = P.procedureloop1.stepindex + 1
        end

        if (P.procedureloop1.stepindex == P.procedureloop1.stepindexprevious) then
            P.procedureloop1.steprepeat = true
        else
            P.procedureloop1.steprepeat = false
            P.procedureloop1.stepindexprevious = P.procedureloop1.stepindex
        end

        if P.procedureskipstep then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Procedure Step Skipped")
            else
                P.commandtableentry(TEXT, "Procedure Step Skipped")
            end
            P.procedureskipstep = false
            P.procedureloop1.stepindex = P.procedureloop1.stepindex + 1
        end
    else
        P.procedureloop1.stepindex = 0
        P.procedureloop1.stepindexprevious = 0
        P.procedureloop1.steprepeat = false
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- P.procedureloop_2() function

function P.procedureloop_2()

    if (P.procedureloop2.lock ~= NOPROCEDURE) then
        if ((P.procedureloop2.stepindex == 0) and not P.procedureabort and not P.procedureskipstep) then
            if (P.proceduretable[P.procedureloop2.lock].name  ~= "") then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop2.lock].name .. " Procedure")
                else
                    P.commandtableentry(TEXT, P.proceduretable[P.procedureloop2.lock].name .. " Procedure")
                end
            end
        elseif ((P.procedureloop2.stepindex <= P.proceduretable[P.procedureloop2.lock].steps) and not P.procedureabort and not proceduskipstep) then
                P.proceduretable[P.procedureloop2.lock].procedurefunction()
        elseif ((((P.procedureloop2.stepindex > P.proceduretable[P.procedureloop2.lock].steps) or P.procedureabort)) and not P.procedureskipstep) then
            if (P.procedureloop2.stepindex > P.proceduretable[P.procedureloop2.lock].steps) then
                if (P.proceduretable[P.procedureloop2.lock].name  ~= "") then
                    if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop2.lock].name .. " Procedure Complete")
                    else
                        P.commandtableentry(TEXT, P.proceduretable[P.procedureloop2.lock].name .. " Procedure Complete")
                    end
                end
            elseif P.procedureabort then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop2.lock].name .. " Procedure Aborted")
                else
                    P.commandtableentry(TEXT, P.proceduretable[P.procedureloop2.lock].name .. " Procedure Aborted")
                end
                P.procedureabort = false
            end
            P.proceduretable[P.procedureloop2.lock].set = true
            P.procedureloop2.lock = NOPROCEDURE
        end
        
        if (P.procedureloop2.lock == NOPROCEDURE) then
            P.procedureloop2.stepindex = 0
        else
            P.procedureloop2.stepindex = P.procedureloop2.stepindex + 1
        end

        if (P.procedureloop2.stepindex == P.procedureloop2.stepindexprevious) then
            P.procedureloop2.steprepeat = true
        else
            P.procedureloop2.steprepeat = false
            P.procedureloop2.stepindexprevious = P.procedureloop2.stepindex
        end

        if P.procedureskipstep then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Procedure Step Skipped")
            else
                P.commandtableentry(TEXT, "Procedure Step Skipped")
            end
            P.procedureskipstep = false
            P.procedureloop2.stepindex = P.procedureloop2.stepindex + 1
        end
    else
        P.procedureloop2.stepindex = 0
        P.procedureloop2.stepindexprevious = 0
        P.procedureloop2.steprepeat = false
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- P.procedureloop_3() function

function P.procedureloop_3()

    if (P.procedureloop3.lock ~= NOPROCEDURE) then
        if ((P.procedureloop3.stepindex == 0) and not P.procedureabort and not P.procedureskipstep) then
            if (P.proceduretable[P.procedureloop3.lock].name  ~= "") then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop3.lock].name .. " Procedure")
                else
                    P.commandtableentry(TEXT, P.proceduretable[P.procedureloop3.lock].name .. " Procedure")
                end
            end
        elseif ((P.procedureloop3.stepindex <= P.proceduretable[P.procedureloop3.lock].steps) and not P.procedureabort and not proceduskipstep) then
                P.proceduretable[P.procedureloop3.lock].procedurefunction()
        elseif ((((P.procedureloop3.stepindex > P.proceduretable[P.procedureloop3.lock].steps) or P.procedureabort)) and not P.procedureskipstep) then
            if (P.procedureloop3.stepindex > P.proceduretable[P.procedureloop3.lock].steps) then
                if (P.proceduretable[P.procedureloop3.lock].name  ~= "") then
                    if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop3.lock].name .. " Procedure Complete")
                    else
                        P.commandtableentry(TEXT, P.proceduretable[P.procedureloop3.lock].name .. " Procedure Complete")
                    end
                end
            elseif P.procedureabort then
                if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    P.commandtableentry(ADVICE, P.proceduretable[P.procedureloop3.lock].name .. " Procedure Aborted")
                else
                    P.commandtableentry(TEXT, P.proceduretable[P.procedureloop3.lock].name .. " Procedure Aborted")
                end
                P.procedureabort = false
            end
            P.proceduretable[P.procedureloop3.lock].set = true
            P.procedureloop3.lock = NOPROCEDURE
        end
        
        if (P.procedureloop3.lock == NOPROCEDURE) then
            P.procedureloop3.stepindex = 0
        else
            P.procedureloop3.stepindex = P.procedureloop3.stepindex + 1
        end

        if (P.procedureloop3.stepindex == P.procedureloop3.stepindexprevious) then
            P.procedureloop3.steprepeat = true
        else
            P.procedureloop3.steprepeat = false
            P.procedureloop3.stepindexprevious = P.procedureloop3.stepindex
        end

        if P.procedureskipstep then
            if (P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
                P.commandtableentry(ADVICE, "Procedure Step Skipped")
            else
                P.commandtableentry(TEXT, "Procedure Step Skipped")
            end
            P.procedureskipstep = false
            P.procedureloop3.stepindex = P.procedureloop3.stepindex + 1
        end
    else
        P.procedureloop3.stepindex = 0
        P.procedureloop3.stepindexprevious = 0
        P.procedureloop3.steprepeat = false
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- do_yal()

function P.do_yal()

    if P.initialstartup then
        yalreset()
        P.initialstartup = false
    end

    if settings.newSettingsAvailable then
        readconfig()
        P.initDataref()
        sasl.logInfo("new settings detected... loading")
    end

    local next_recommended_wait_step = STANDARDWAIT 

    if (P.procedureloop1.lock ~= NOPROCEDURE or
        P.procedureloop2.lock ~= NOPROCEDURE or
        P.procedureloop3.lock ~= NOPROCEDURE or
        P.configvalues[CONFIGVOICEADVICEONLY] == ON) then
        next_recommended_wait_step = STANDARDWAIT
    end

    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("ONGOINGTASKSTEPINDEX: " .. P.ongoingtaskstepindex)

    if ((P.configvalues[CONFIGAUTOFUNCTIONS] == ON) or (P.configvalues[CONFIGVOICEADVICEONLY] == ON)) then
        autofunctions()
        ongoingtasks()
    end

    if (P.configvalues[CONFIGVOICEREADBACK] == ON) then
        voicereadback()
    end

    sasl.logDebug("PROCEDURELOOP1: LOCK ".. P.procedureloop1.lock .. " STEPINDEX " .. P.procedureloop1.stepindex)
    sasl.logDebug("PROCEDURELOOP2: LOCK ".. P.procedureloop2.lock .. " STEPINDEX " .. P.procedureloop2.stepindex)
    sasl.logDebug("PROCEDURELOOP3: LOCK ".. P.procedureloop3.lock .. " STEPINDEX " .. P.procedureloop3.stepindex)

    -- --- NEU: Scheduler für Prozedur-Loops (findet und führt EINE aktive Schleife aus, wenn vorhanden) ---
    local loops_count = #P.loopfunctions
    local loop_executed_this_cycle = false -- Flag, um zu verfolgen, ob in diesem Zyklus eine Schleife ausgeführt wurde

    -- Bestimme den Startpunkt für die Suche in der zirkulären Liste der Schleifen.
    -- Beginne immer nach dem Index der zuletzt *versuchten* oder ausgeführten Schleife.
    local start_check_index = P.lastExecutedLoopIndex
    if start_check_index == 0 then start_check_index = 1 end -- Falls noch nie gelaufen, starte bei Loop 1

    -- Durchlaufe alle Schleifen kandidaten, bis eine aktive gefunden und ausgeführt wird
    for i = 1, loops_count do
        -- Berechne den aktuellen Index in der zirkulären Liste (1-basiert: 1, 2, 3, 1, 2, 3...)
        local current_loop_idx = ((start_check_index + i - 2) % loops_count) + 1

        local current_loop_state_table = P.loopStateTables[current_loop_idx]
        local current_loop_function = P.loopfunctions[current_loop_idx]

        if current_loop_state_table.lock ~= NOPROCEDURE then
            -- Gefunden: Eine gelockte Schleife, die ausgeführt werden soll
            current_loop_function()
            P.lastExecutedLoopIndex = current_loop_idx -- Merke dir, welche Schleife in diesem Zyklus ausgeführt wurde
            loop_executed_this_cycle = true
            sasl.logDebug("SCHEDULER: Executing loop " .. tostring(current_loop_idx) .. " (locked: " .. current_loop_state_table.lock .. ").")
            break -- Eine aktive Schleife wurde ausgeführt, breche die Suche für diesen do_yal-Aufruf ab
        else
            sasl.logDebug("SCHEDULER: Skipping loop " .. tostring(current_loop_idx) .. " (not locked).")
        end
    end

    if not loop_executed_this_cycle then
        sasl.logDebug("SCHEDULER: No locked loops found to execute this cycle. Advancing scan pointer for next cycle.")
        -- Wenn keine Schleife ausgeführt wurde, muss P.lastExecutedLoopIndex trotzdem vorrücken,
        -- um sicherzustellen, dass die Suche im nächsten do_yal-Aufruf an der nächsten Position beginnt.
        P.lastExecutedLoopIndex = (P.lastExecutedLoopIndex % loops_count) + 1 
    end
    -- --- ENDE NEU: Scheduler für Prozedur-Loops ---

    P.commandtableloop() 

    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("BEFORETAXISET: " .. tostring(P.proceduretable[BEFORETAXIPROCEDURE].set))
    sasl.logDebug("BEFORETAKEOFFSET: " .. tostring(P.proceduretable[BEFORETAKEOFFPROCEDURE].set))
    sasl.logDebug("AFTERTAKEOFFSET: " .. tostring(P.proceduretable[AFTERTAKEOFFPROCEDURE].set))
    sasl.logDebug("DURINGCLIMBSET: " .. tostring(P.proceduretable[DURINGCLIMBPROCEDURE].set))
    sasl.logDebug("ALTITUDEA10000SET: " .. tostring(P.proceduretable[ALTITUDEA10000PROCEDURE].set))
    sasl.logDebug("DURINGDESCENTSET: " .. tostring(P.proceduretable[DURINGDESCENTPROCEDURE].set))
    sasl.logDebug("ALTITUDEB10000SET: " .. tostring(P.proceduretable[ALTITUDEB10000PROCEDURE].set))
    sasl.logDebug("RADIOALTITUDE2500SET: " .. tostring(P.proceduretable[RADIOALTITUDEB2500PROCEDURE].set))
    sasl.logDebug("RADIOALTITUDE1000SET: " .. tostring(P.proceduretable[RADIOALTITUDEB1000PROCEDURE].set))
    sasl.logDebug("AFTERLANDINGSET: " .. tostring(P.proceduretable[AFTERLANDINGPROCEDURE].set))
    sasl.logDebug("ATPARKINGPOSITIONSET: " .. tostring(P.proceduretable[ATPARKINGPOSITIONPROCEDURE].set))
    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("FLIGHTSTATE: " .. tostring(P.flightstate))
    sasl.logDebug("FMSFLIGHTPHASE:" .. tostring(get(fmsflightphase)))
    sasl.logDebug("AIRCRAFTWASONGROUND: " .. tostring(P.aircraftwasonground))
    sasl.logDebug("Raw Departure METAR: " .. tostring(P.depmetar.metar.raw_text))
    sasl.logDebug("Altitude METAR: " .. tostring(P.depmetar.metar.elevation_m))
    sasl.logDebug("Raw METAR: " .. tostring(P.desmetar.metar.raw_text))
    sasl.logDebug("Altitude METAR: " .. tostring(P.desmetar.metar.elevation_m))

    return next_recommended_wait_step
end

--------------------------------------------------------------------------------------------------------------
-- Order is important

menu_procedure_step = sasl.appendMenuItem(P.menu_main, "Skip Procedure Step", skipprocedurestep)
menu_abort_procedure = sasl.appendMenuItem(P.menu_main, "Abort Procedure", abortprocedure)
sasl.appendMenuSeparator ( P.menu_main )
menu_cd = sasl.appendMenuItem(P.menu_main, "Cold and Dark Startup", coldanddarkstartup)
menu_cockpit_init = sasl.appendMenuItem(P.menu_main, "Cockpit Initialization", cockpitinit)
menu_apu_start = sasl.appendMenuItem(P.menu_main, "APU Startup", apustartup)
menu_eng_start = sasl.appendMenuItem(P.menu_main, "Engine Startup", enginestart)
menu_before_taxi = sasl.appendMenuItem(P.menu_main, "Before Taxi Procedure", beforetaxi)
menu_before_takeoff = sasl.appendMenuItem(P.menu_main, "Before Takeoff Procedure", beforetakeoff)
menu_after_landing = sasl.appendMenuItem(P.menu_main, "After Landing Procedure", afterlanding)
menu_eng_stop_ta = sasl.appendMenuItem(P.menu_main, "Turnaround Engine Shutdown", turnaroundengineshutdown)
menu_eng_stop_final = sasl.appendMenuItem(P.menu_main, "Final Engine Shutdown", finalengineshutdown)
menu_shutdown = sasl.appendMenuItem(P.menu_main, "Shutdown", shutdown)
sasl.appendMenuSeparator ( P.menu_main )
menu_above1000 = sasl.appendMenuItem(P.menu_main, "Above 10000", altitudea10000)
menu_below1000 = sasl.appendMenuItem(P.menu_main, "Below 10000", altitudeb10000)
menu_ils_freq = sasl.appendMenuItem(P.menu_main, "Set ILS/GLS Freq/Course", setilsproc)
menu_copy_nav = sasl.appendMenuItem(P.menu_main, "Copy NAV1/MMR1 to NAV2/MMR2", copynav)
menu_set_vref = sasl.appendMenuItem(P.menu_main, "Set Landing Flaps/VREF", setvrefproc)
menu_set_toflaps = sasl.appendMenuItem(P.menu_main, "Set Takeoff Flaps", settoflapsproc)
sasl.appendMenuSeparator ( P.menu_main )
menu_test = sasl.appendMenuItem(P.menu_main, "Tests", test)
sasl.appendMenuSeparator ( P.menu_main )
menu_toggle_setcockpitlights = sasl.appendMenuItem(P.menu_main, "Set Cockpit Lights", setcockpitlights)
menu_toggle_auto = sasl.appendMenuItem(P.menu_main, "Toggle Auto Functions", toggleautofunctions)
menu_toogle_voice = sasl.appendMenuItem(P.menu_main, "Toggle Voice Readback", togglevoicereadback)
menu_toogle_adviceonly = sasl.appendMenuItem(P.menu_main, "Toggle Advice Only", toggleadviceonly)
menu_toogle_freeze = sasl.appendMenuItem(P.menu_main, "Toggle Sim Freeze", togglesimfreeze)
menu_toggle_view = sasl.appendMenuItem(P.menu_main, "Toggle View Changes", toggleviewchanges)
menu_yal_reset = sasl.appendMenuItem(P.menu_main, "Reset YAL", yalreset)
sasl.appendMenuSeparator ( P.menu_main )

--------------------------------------------------------------------------------------------------------------
-- enableMenus()

function P.enableMenus()
    local enable = 0
    if helpers.isZibo then
        enable = 1
    end
    sasl.enableMenuItem(PLUGINS_MENU_ID , menu_master , enable)

    sasl.enableMenuItem(P.menu_main , menu_procedure_step , enable)
    sasl.enableMenuItem(P.menu_main , menu_abort_procedure , enable)

    sasl.enableMenuItem(P.menu_main , menu_cd , enable)
    sasl.enableMenuItem(P.menu_main , menu_cockpit_init , enable)
    sasl.enableMenuItem(P.menu_main , menu_apu_start , enable)
    sasl.enableMenuItem(P.menu_main , menu_eng_start , enable)
    sasl.enableMenuItem(P.menu_main , menu_before_taxi , enable)
    sasl.enableMenuItem(P.menu_main , menu_before_takeoff , enable)
    sasl.enableMenuItem(P.menu_main , menu_after_landing , enable)
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
    sasl.enableMenuItem(P.menu_main , menu_yal_reset , enable)

end

P.YalinitGlobal()

return yal