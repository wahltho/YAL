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

    initialstartup = true

    aircraftwasonground = false

    remainingtimetoquit = 9999

    remainingtimetosave = 9999

    flightstate = 0

    apphasils = false

    lowerduset = OFF

    centertankoffset = false

    getmetarcounter = 0

    depmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}
    desmetar = {icaocode = "XXXX", metarfound = false, metar = {}, decodedmetar = {}}


    --------------------------------------------------------------------------------------------------------------
    -- Config Table

    configvalues = {}

    --------------------------------------------------------------------------------------------------------------
    -- Variables for FMS commands

    vrefcmdtable = {"del", "clr", "3", "0", "slash", "X", "X", "X", "4R", "exec", "end"}

    --------------------------------------------------------------------------------------------------------------
    -- Command Table Table

    commandtable = {}

    --------------------------------------------------------------------------------------------------------------
    -- Nav Data Table 

    navdatatable = {}
    navdatatableindex = 0

    --------------------------------------------------------------------------------------------------------------
    -- Variables for Procedures

    beforetaxiset = false
    beforetakeoffset = false
    aftertakeoffset = false
    duringclimbset = false
    altitudea10000set = false
    duringdescentset = false
    altitudeb10000set = false
    radioaltitude2500set = false
    radioaltitude1000set = false
    afterlandingset = false   
    atparkingpositionset = false

    ongoingtaskstepindex = 1

    procedureabort = false
    procedureskipstep = false

    procedureloop1 = {lock = NOPROCEDURE, stepindex = 1, previousstepindex = 1, steprepeat = false}

    procedureloop2 = {lock = NOPROCEDURE, stepindex = 1, previousstepindex = 1, steprepeat = false}

    setils = {stepindex = 1, previousstepindex = 1, steprepeat = false}

    previousview = -1
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

    mainbus = globalProperty("laminar/B738/electric/main_bus")
    parkingbrakepos = globalProperty("laminar/B738/parking_brake_pos")

    pausetod = globalProperty("laminar/B738/fms/pause_td")

    hidecptefb = globalProperty("laminar/B738/tab/static")
    hidefoefb = globalProperty("laminar/B738/tab/fo_static")

    chockstatus = globalProperty("laminar/B738/fms/chock_status")

    if helpers.isXp12 then
        wakeoverride = globalProperty("sim/operation/override/override_wake_turbulence")
    end

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

    nosewheel = globalProperty("laminar/B738/axis/nosewheel")

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

    if helpers.isXp11 then
        baroregioninhg = globalProperty("sim/weather/barometer_sealevel_inhg")
    end
    if helpers.isXp12 then
        baroregionpas = globalProperty("sim/weather/region/qnh_pas")
    end

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


    depicao = globalProperty("laminar/B738/fms/ref_icao")
    deprwyheading = globalProperty("laminar/B738/fms/ref_runway_crs_mod")
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

    speedrestr = globalProperty("laminar/B738/autopilot/fmc_descent_r_speed1")

    vref = globalProperty("laminar/B738/FMS/vref")
    vref15 = globalProperty("laminar/B738/FMS/vref_15")
    vref25 = globalProperty("laminar/B738/FMS/vref_25")
    vref30 = globalProperty("laminar/B738/FMS/vref_30")
    vref40 = globalProperty("laminar/B738/FMS/vref_40")

    if helpers.isXp12 then
        rain = globalProperty("sim/weather/view/rain_ratio")
    end
    if helpers.isXp11 then
        rain = globalProperty("sim/weather/rain_percent")
    end

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
        xcamerastatus = nil
        sasl.logInfo("X-Camera not installed")
    else
        xcamerastatus = globalProperty("SRS/X-Camera/integration/overall_status")
        sasl.logInfo("X-Camera installed")
    end

    --------------------------------------------------------------------------------------------------------------
    -- Variables for Monitor Switches Function, etc.

    set(n1setsource, 0)

    cabincruisealttemp = get(cabincruisealt)
    cabincruisealttemp2 = get(cabincruisealt)
    cabinlandingalttemp = get(cabinlandingalt)
    cabinlandingalttemp2 = get(cabinlandingalt)

    mcpspeedtemp = get(mcpspeed)
    mcpspeedtemp2 = get(mcpspeed)

    mcpheadingtemp = get(mcpheading)
    mcpheadingtemp2 = get(mcpheading)

    mcpaltitudetemp = get(mcpaltitude)
    mcpaltitudetemp2 = get(mcpaltitude)

    mcpvsspeedtemp = get(mcpvsspeed)
    mcpvsspeedtemp2 = get(mcpvsspeed)

    desrwyheadingtemp = get(desrwyheading)
    desrwylatstartpostemp = get(desrwylatstartpos)
    desrwylonstartpostemp = get(desrwylonstartpos)
    desrwylatendpostemp = get(desrwylatendpos)
    desrwylonendpostemp = get(desrwylonendpos)

    flapleverpostemp = get(flapleverpos)
    flapleverpostemp2 = get(flapleverpos)
    gearhandlepostemp = get(gearhandlepos)
    speedbrakelevertemp = get(speedbrakelever)
    speedbrakelevertemp2 = get(speedbrakelever)
    parkingbrakepostemp = get(parkingbrakepos)
    autobrakepostemp = get(autobrakepos)
    autobrakedisarmtemp = get(autobrakedisarm)
    autobrakedisarmtemp2 = get(autobrakedisarm)

    aponstattemp = get(aponstat)

    apcmdastattemp = get(apcmdastat)
    apcmdbstattemp = get(apcmdbstat)

    apvnavstattemp = get(apvnavstat)
    aplnavstattemp = get(aplnavstat)
    apappstattemp = get(apappstat)
    apvorlocstattemp = get(apvorlocstat)
    apalthldstattemp = get(apalthldstat)
    aphdgselstattemp = get(aphdgselstat)
    apvsstattemp = get(apvsstat)
    aplvlchgstattemp = get(aplvlchgstat)

    apgscapturedstattemp = get(apgscapturedstat)
    aploccapturedstattemp = get(aploccapturedstat)
    apflarestattemp = get(apflarestat)
    aprolloutstattemp = get(aprolloutstat)

    aplpvgscapturedstattemp = get(aplpvgscapturedstat)
    aplpvloccapturedstattemp = get(aplpvloccapturedstat)

    apglsgscapturedstattemp = get(apglsgscapturedstat)
    apglsloccapturedstattemp = get(apglsloccapturedstat)

    apfacgscapturedstattemp = get(apfacgscapturedstat)
    apfacloccapturedstattemp = get(apfacloccapturedstat)

    atarmpostemp = get(atarmpos)
    atn1stattemp = get(atn1stat)
    atspeedstattemp = get(atspeedstat)
    atspeedintvstattemp = get(atspeedintvstat)

    nav1freqtemp = get(nav1freq)
    nav2freqtemp = get(nav2freq)

    mcppilotcoursetemp = get(mcppilotcourse)
    mcppilotcoursetemp2 = get(mcppilotcourse)
    mcpcopilotcoursetemp = get(mcpcopilotcourse)
    mcpcopilotcoursetemp2 = get(mcpcopilotcourse)

    mmrcptactmodetemp = get(mmrcptactmode)
    mmrcptactvaluetemp = get(mmrcptactvalue)
    mmrcptstdbymodetemp = get(mmrcptstdbymode)
    mmrcptstdbymodetemp2 = get(mmrcptstdbymode)
    mmrfoactmodetemp = get(mmrfoactmode)
    mmrfoactvaluetemp = get(mmrfoactvalue)
    mmrfostdbymodetemp = get(mmrfostdbymode)
    mmrfostdbymodetemp2 = get(mmrfostdbymode)

    bankanglepostemp = get(bankanglepos)
    bankanglepostemp2 = get(bankanglepos)

    barostdtemp = get(barostd)
    baropilottemp = get(baropilot)
    baropilottemp2 = get(baropilot)

    fdpilotpostemp = get(fdpilotpos)
    fdfopostemp = get(fdfopos)

    efiswxpilotpostemp = get(efiswxpilotpos)
    efiswxfopostemp = get(efiswxfopos)
    efisterrpilotpostemp = get(efisterrpilotpos)
    efisterrfopostemp = get(efisterrfopos)
    efisdatapilotpostemp = get(efisdatapilotpos)
    efisdatafopostemp = get(efisdatafopos)
    efisfixpilotpostemp = get(efisfixpilotpos)
    efisfixfopostemp = get(efisfixfopos)
    efisairportpilotpostemp = get(efisairportpilotpos)
    efisairportfopostemp = get(efisairportfopos)
    efispospilotpostemp = get(efispospilotpos)
    efisposfopostemp = get(efisposfopos)
    efisvorpilotpostemp = get(efisvorpilotpos)
    efisvorfopostemp = get(efisvorfopos)

    dhpilottemp = get(dhpilot)
    dhpilottemp2 = get(dhpilot)

    batterytemp = get(battery)
    emergencylightstemp = get(emergencylights)

    starter1postemp = get(starter1pos)
    starter2postemp = get(starter2pos)

    mixture1postemp = get(mixture1pos)
    mixture2postemp = get(mixture2pos)

    reverser1postemp = get(reverser1pos)
    reverser2postemp = get(reverser2pos)

    packlpostemp = get(packlpos)
    packrpostemp = get(packrpos)
    bleedair1postemp = get(bleedair1pos)
    bleedair2postemp = get(bleedair2pos)
    bleedairapupostemp = get(bleedairapupos)
    trimairpostemp = get(trimairpos)
    isolvalvepostemp = get(isolvalvepos)
    lrecircfanpostemp = get(lrecircfanpos)
    rrecircfanpostemp = get(rrecircfanpos)

    gpuontemp = get(gpuon)

    apustarterpostemp = get(apustarterpos)
    apurunningtemp = get(apurunning)
    announcsourceoff1temp = get(announcsourceoff1)
    announcsourceoff2temp = get(announcsourceoff2)

    gen1postemp = get(gen1pos)
    gen2postemp = get(gen2pos)

    hydro1postemp = get(hydro1pos)
    hydro2postemp = get(hydro2pos)
    elechydro1postemp = get(elechydro1pos)
    elechydro2postemp = get(elechydro2pos)

    totalfuellbstemp = get(totalfuellbs)
    totalfuellbstemp2 = get(totalfuellbs)

    centertanklswitchtemp = get(centertanklswitch)
    centertankrswitchtemp = get(centertankrswitch)
    lefttanklswitchtemp = get(lefttanklswitch)
    lefttankrswitchtemp = get(lefttankrswitch)
    righttanklswitchtemp = get(righttanklswitch)
    righttankrswitchtemp = get(righttankrswitch)

    taxilighttemp = get(taxilight)
    beaconlightstemp = get(beaconlights)
    llightsontemp = get(llightson)
    llights1temp = get(llights1)
    llights2temp = get(llights2)
    llights3temp = get(llights3)
    llights4temp = get(llights4)
    rwylightltemp = get(rwylightl)
    rwylightrtemp = get(rwylightr)
    positionlightstemp = get(positionlights)
    logolightontemp = get(logolighton)

    transponderpostemp = get(transponderpos)

    captainprobepostemp = get(captainprobepos)
    foprobepostemp = get(foprobepos)

    wheatlfwdpostemp = get(wheatlfwdpos)
    wheatrfwdpostemp = get(wheatrfwdpos)
    wheatlsidepostemp = get(wheatlsidepos)
    wheatrsidepostemp = get(wheatrsidepos)

    yawdamperswitchtemp = get(yawdamperswitch)

    domelightpostemp = get(domelightpos)
    seatbeltsignpostemp = get(seatbeltsignpos)
    nosmokingsignpostemp = get(nosmokingsignpos)

    irsleftpostemp = get(irsleftpos)
    irsleftpostemp2 = get(irsleftpos)
    irsrightpostemp = get(irsrightpos)
    irsrightpostemp2 = get(irsrightpos)

    lwiperpostemp = get(lwiperpos)
    lwiperpostemp2 = get(lwiperpos)
    rwiperpostemp = get(rwiperpos)
    rwiperpostemp2 = get(rwiperpos)

    transpondercodetemp = get(transpondercode)
    transpondercodetemp2 = get(transpondercode)

    pausetodtemp = get(pausetod)
    simfreezedtemp = get(simfreezed)

    chockstatustmp = get(chockstatus)

end

--------------------------------------------------------------------------------------------------------------

function searchnavdatatable(col1_value, col2_value, col3_value, col1_index, col2_index, col3_index)
    for row_key, row in pairs(navdatatable) do
        if ((row[col1_index] == col1_value) and (row[col2_index] == col2_value) and (row[col3_index] == col3_value)) then

            return row_key
        end
    end
    return nil
end

function calccourse(in_crs)
    local result = (in_crs + 360) % 360
    result = math.floor(result + 0.5)
    if (result >= 359.5) then
        result = 0
    end
    
    return result
end

function P.buildnavdatatable()

    srcnavdatafile = io.open("Custom Data/earth_nav.dat", "r")

    if not srcnavdatafile then
        sasl.logDebug("Could not open Custom Data/earth_nav.dat")
        return false
    end


    navdatarecord = srcnavdatafile:read()

    while navdatarecord do

        navdataitems = {}
        for navdataitem in navdatarecord:gmatch("%S+") do
            table.insert(navdataitems, navdataitem)
        end
            
        if (#navdataitems > 11) then            

            if (navdataitems[SRCTYPECODE] == NAVDATARECTYPEILS) then
                destnavtypetmp = string.sub(navdataitems[SRCNAVTYPE], 1, 3)
       
                navdatatableindex = navdataitems[SRCICAO] .. navdataitems[SRCRWY] .. destnavtypetmp
                navdatatable[navdatatableindex] = {true, true, true, true, true, true, true}

                navdatatable[navdatatableindex][DESTICAO] = navdataitems[SRCICAO]
                navdatatable[navdatatableindex][DESTRWY] = navdataitems[SRCRWY]
                navdatatable[navdatatableindex][DESTNAVTYPE] = destnavtypetmp
                navdatatable[navdatatableindex][DESTNAVID] = navdataitems[SRCNAVID]
                navdatatable[navdatatableindex][DESTFREQ] = tonumber(navdataitems[SRCFREQ])
                ilstmp = tonumber(navdataitems[SRCCOURSE])
                if (ilstmp > 360) then
                    navdatatable[navdatatableindex][DESTCOURSE] = calccourse(math.floor(ilstmp / 360))
                else
                    navdatatable[navdatatableindex][DESTCOURSE] = calccourse((ilstmp + xplm.XPLMGetMagneticVariation(tonumber(navdataitems[SRCLATPOS]), tonumber(navdataitems[SRCLONPOS])) + 360) % 360)
                end
                navdatatable[navdatatableindex][DESTNAVDME] = false       
            elseif (navdataitems[SRCTYPECODE] == NAVDATARECTYPEVOR) then
                destnavtypetmp = string.sub(navdataitems[SRCNAVTYPE], 1, 3)
          
                navdatatableindex = navdataitems[SRCICAO] .. navdataitems[SRCRWY] .. destnavtypetmp
                navdatatable[navdatatableindex] = {true, true, true, true, true, true, true}

                navdatatable[navdatatableindex][DESTICAO] = navdataitems[SRCICAO]
                navdatatable[navdatatableindex][DESTRWY] = navdataitems[SRCRWY]
                navdatatable[navdatatableindex][DESTNAVTYPE] = destnavtypetmp
                navdatatable[navdatatableindex][DESTNAVID] = navdataitems[SRCNAVID]
                navdatatable[navdatatableindex][DESTFREQ] = tonumber(navdataitems[SRCFREQ])
                ilstmp = tonumber(navdataitems[SRCCOURSE])
                if (ilstmp > 360) then
                    navdatatable[navdatatableindex][DESTCOURSE] = calccourse(math.floor(ilstmp / 360))
                else
                    navdatatable[navdatatableindex][DESTCOURSE] = calccourse((ilstmp + xplm.XPLMGetMagneticVariation(tonumber(navdataitems[SRCLATPOS]), tonumber(navdataitems[SRCLONPOS])) + 360) % 360)
                end
                navdatatable[navdatatableindex][DESTNAVDME] = false
            elseif (navdataitems[SRCTYPECODE] == NAVDATARECTYPEDME) then
                navdatatableindextmp = searchnavdatatable(navdataitems[SRCICAO], navdataitems[SRCNAVID], NAVTYPEILS, DESTICAO, DESTNAVID, DESTNAVTYPE)
                if (navdatatableindextmp  ~= nil) then
                    navdatatable[navdatatableindextmp][DESTNAVDME] = true
                else
                    navdatatableindextmp = searchnavdatatable(navdatatable, navdataitems[SRCICAO], navdataitems[SRCNAVID], NAVTYPEIGS, DESTICAO, DESTNAVID, DESTNAVTYPE)
                    if (navdatatableindextmp  ~= nil) then
                        navdatatable[navdatatableindextmp][DESTNAVDME] = true
                    else
                        navdatatableindextmp = searchnavdatatable(navdatatable, navdataitems[SRCICAO], navdataitems[SRCNAVID], NAVTYPELOC, DESTICAO, DESTNAVID, DESTNAVTYPE)
                        if (navdatatableindextmp  ~= nil) then
                            navdatatable[navdatatableindextmp][DESTNAVDME] = true
                        end
                    end
                end
            elseif ((navdataitems[SRCTYPECODE] == NAVDATARECTYPELPV) or (navdataitems[SRCTYPECODE] == NAVDATARECTYPEGLS)) then
                if (navdataitems[SRCTYPECODE] == NAVDATARECTYPELPV) then
                    destnavidtmp = navdataitems[SRCNAVTYPE]
                    destnavtypetmp = NAVTYPELPV
                else
                    destnavidtmp = navdataitems[SRCNAVID]
                    destnavtypetmp = NAVTYPEGLS
                end
 
                navdatatableindex = navdataitems[SRCICAO] .. navdataitems[SRCRWY] .. destnavtypetmp
                navdatatable[navdatatableindex] = {true, true, true, true, true, true, true}

                navdatatable[navdatatableindex][DESTICAO] = navdataitems[SRCICAO]
                navdatatable[navdatatableindex][DESTRWY] = navdataitems[SRCRWY]
                navdatatable[navdatatableindex][DESTNAVTYPE] = destnavtypetmp
                navdatatable[navdatatableindex][DESTNAVID] = destnavidtmp
                navdatatable[navdatatableindex][DESTFREQ] = tonumber(navdataitems[SRCFREQ])
                navdatatable[navdatatableindex][DESTCOURSE] = calccourse((tonumber(string.sub(navdataitems[SRCCOURSE], 4, -1)) + xplm.XPLMGetMagneticVariation(tonumber(navdataitems[SRCLATPOS]), tonumber(navdataitems[SRCLONPOS])) + 360) % 360)
                navdatatable[navdatatableindex][DESTNAVDME] = true
            end
        end

        navdatarecord = srcnavdatafile:read()
    end
    srcnavdatafile:close()


    for key, value in pairs(navdatatable) do
        local icaocode = key:sub(1, 4)
        local rwy = key:sub(5, -4)
        local navtype = key:sub(-3)
  
        if ((navtype == NAVTYPEGLS) or (navtype == NAVTYPELPV)) then
            if (navdatatable[icaocode .. rwy .. NAVTYPEILS] ~= nil) then
                if (getheadingdiff(navdatatable[key][DESTCOURSE], navdatatable[icaocode .. rwy .. NAVTYPEILS][DESTCOURSE]) == 1) then
                    navdatatable[key][DESTCOURSE] = navdatatable[icaocode .. rwy .. NAVTYPEILS][DESTCOURSE]
                end
            else
                local opprwy = getoppositerwy(rwy)
                if (navdatatable[icaocode .. opprwy .. NAVTYPEILS] ~= nil) then
                    local oppcourse = getoppositeheading(navdatatable[icaocode .. opprwy .. NAVTYPEILS][DESTCOURSE])
                     if (getheadingdiff(navdatatable[key][DESTCOURSE], oppcourse) == 1) then
                        navdatatable[key][DESTCOURSE] = oppcourse
                    end
                end
            end
        end
    end
    
    return results
end

--------------------------------------------------------------------------------------------------------------
function P.writenavdatatable()

    destnavdatafile = io.open("Custom Data/yal_nav.dat", "w")

    if not destnavdatafile then
        sasl.logDebug("Could not open Custom Data/yal_nav.dat")
        return false
    end

    for row_key, row in pairs(navdatatable) do
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

    remainingtimetoquit = configvalues[CONFIGTODPAUSEQUITTIME]
    remainingtimetosave = configvalues[CONFIGSAVETIME]
    if (configvalues[CONFIGWAKEOVERRIDE] == ON) then
        if helpers.isXp12 then
            set(wakeoverride, ON)
        end
    end

    lowerairspacealt = configvalues[CONFIGLOWEAIRSPACEALT]

    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
        commandtableentry(ADVICE, "YAL Reset Done")
    else
        commandtableentry(TEXT, "YAL Reset Done")
    end

    initialstartup = false

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

    configvalues = settings.getSettings()

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

    if (#commandtable == 0) then
        if ((configvalues[CONFIGVIEWCHANGES] == ON) and (view ~= nil)) then
            if view ~= previousview then
                if (xcamerastatus ~= nil) then
                    helpers.command_once("SRS/X-Camera/Select_View_ID_" .. view)
                else
                    helpers.command_once("sim/view/quick_look_" .. tostring(view - 1))
                end
                sasl.logDebug("Setting View #" .. view)
                previousview = view
            else
                sasl.logDebug("View #" .. view .. " already set")
            end
        end
    else
        return false
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
    local start = 1
    local done = false

    while not done do
        -- Finde das nächste Leerzeichen
        local nextSpace = string.find(input, "%s", start)

        if nextSpace then
            -- Füge den Teilstring zwischen start und nextSpace-1 hinzu
            table.insert(parts, string.sub(input, start, nextSpace - 1))
            start = nextSpace + 1
        else
            -- Füge den letzten Teilstring hinzu
            table.insert(parts, string.sub(input, start))
            done = true
        end
    end

    return parts
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
function getnavdataindex(icao, rwy, navtype)

    if not (isvalidicao(icao) and isvalidrwy(rwy)) then
        return nil
    end

    local result = nil
    local navdatatableindex = icao .. rwy .. navtype
    
    if (navdatatable[navdatatableindex] ~= nil) then
        result = navdatatableindex
    else
        navdatatableindex = icao .. adjustrwy(rwy, 1) .. navtype
        if (navdatatable[navdatatableindex]  ~= nil) then
           result = navdatatableindex
        else
            navdatatableindex = icao .. adjustrwy(rwy, -1) .. navtype
            if (navdatatable[navdatatableindex]  ~= nil) then
               result = navdatatableindex
            else
                navdatatableindex = icao .. adjustrwy(rwy, 2) .. navtype
                if (navdatatable[navdatatableindex]  ~= nil) then
                   result = navdatatableindex
                else
                    navdatatableindex = icao .. adjustrwy(rwy, -2) .. navtype
                    if (navdatatable[navdatatableindex]  ~= nil) then
                       result = navdatatableindex
                    else
                        navdatatableindex = icao .. adjustrwy(rwy, 3) .. navtype
                        if (navdatatable[navdatatableindex]  ~= nil) then
                           result = navdatatableindex
                        else
                            navdatatableindex = icao .. adjustrwy(rwy, -3) .. navtype
                            if (navdatatable[navdatatableindex]  ~= nil) then
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
        result = navdatatable[navdatatableindex][DESTCOURSE]
    else
        navdatatableindex = getnavdataindex(icao, rwy, NAVTYPEGLS)
        if (navdatatableindex ~= nil) then
            result = navdatatable[navdatatableindex][DESTCOURSE]
        else
            navdatatableindex = getnavdataindex(icao, rwy, NAVTYPELPV)
            if (navdatatableindex ~= nil) then
                result = navdatatable[navdatatableindex][DESTCOURSE]
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


    if helpers.isXp11 then
        localqnhinch = get(baroregioninhg)
        localqhnhpas = convertpressure(localqnhinch / 100)
    end

    if helpers.isXp12 then
        localqnhpas = roundnumber(get(baroregionpas) / 100)
        localqnhinch = convertpressure(localqnhpas)
    end

    if ((deparr == DEPARTURE) and depmetar.metarfound and tonumber(depmetar.metar.altim_in_hg)) then
        localqnhinch = depmetar.metar.altim_in_hg
        localqnhpas = convertpressure(localqnhinch)
    elseif ((deparr == ARRIVAL) and desmetar.metarfound and tonumber(desmetar.metar.altim_in_hg)) then
        localqnhinch = desmetar.metar.altim_in_hg
        localqnhpas = convertpressure(localqnhinch)
    end

    sasl.logDebug("GETLOCALQNH: INCH "  .. tostring(localqnhinch) .. " PAS " .. tostring(localqnhpas))

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
function commandtableentry(state, text)

    local index = 1
    local duplicateentryfound = false

    if (state ~= COMMAND) then
        while (index <= #commandtable) do
            if ((commandtable[index][1] == state) and (commandtable[index][2] == text)) then
                duplicateentryfound = true
            end
            index = index + 1
        end
    end

    if not duplicateentryfound then
        newentryindex = #commandtable + 1
        commandtable[newentryindex] = {}
        commandtable[newentryindex][1] = state
        commandtable[newentryindex][2] = text
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

    if ((procedureloop1.lock ~= NOPROCEDURE) and (configvalues[CONFIGVOICEADVICEONLY] == ON)) then
        commandtableentry(ADVICE, "Procedure Step Skipped")
        procedureskipstep = true
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
            if (efisefisterrfopostemp == ON) then
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
        commandtableentry(TEXT, "Wing and Engine Anti Ice ON")
    elseif (set == 2) then
        commandtableentry(TEXT, "Wing and Engine Anti Ice OFF")
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

    if (configvalues[CONFIGAUTOFUNCTIONS] == ON) then
        configvalues[CONFIGAUTOFUNCTIONS] = OFF
        commandtableentry(TEXT, "Auto Functions Off")
    else
        configvalues[CONFIGAUTOFUNCTIONS] = ON
        commandtableentry(TEXT, "Auto Functions On")
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

function setcockpitlights()

    local lightset = false

    if (get(brightmainpanel) ~= configvalues[CONFIGBRIGHTMAINPANEL]) then
        set(brightmainpanel, configvalues[CONFIGBRIGHTMAINPANEL])
        lightset = true
    end
    if (get(brightcopilotmainpanel) ~= configvalues[CONFIGBRIGHTMAINPANEL]) then
        set(brightcopilotmainpanel, configvalues[CONFIGBRIGHTMAINPANEL])
        lightset = true
    end
    if (get(brightoverhead) ~= configvalues[CONFIGBRIGHTOVERHEAD]) then
        set(brightoverhead, configvalues[CONFIGBRIGHTOVERHEAD])
        lightset = true
    end
    if (get(brightpedestral) ~= configvalues[CONFIGBRIGHTPEDESTRAL]) then
        set(brightpedestral, configvalues[CONFIGBRIGHTPEDESTRAL])
    end
    if (get(genbrightbackground) ~= configvalues[CONFIGGENBRIGHTBACKGROUND]) then
        set(genbrightbackground, configvalues[CONFIGGENBRIGHTBACKGROUND])
        lightset = true
    end
    if (get(genbrightafdsflood) ~= configvalues[CONFIGGENBRIGHTAFDSFLOOD]) then
        set(genbrightafdsflood, configvalues[CONFIGGENBRIGHTAFDSFLOOD])
        lightset = true
    end
    if (get(genbrightpedestralflood) ~= configvalues[CONFDIGGENBRIGHTPEDESTRALFLOOD]) then
        set(genbrightpedestralflood, configvalues[CONFDIGGENBRIGHTPEDESTRALFLOOD])
        lightset = true
    end
    if (get(instrbrightoutbddu) ~= configvalues[CONFIGINSTRBRIGHTOUTBDDU]) then
        set(instrbrightoutbddu, configvalues[CONFIGINSTRBRIGHTOUTBDDU])
        lightset = true
    end
    if (get(instrbrightcopilotoutbddu) ~= configvalues[CONFIGINSTRBRIGHTOUTBDDU]) then
        set(instrbrightcopilotoutbddu, configvalues[CONFIGINSTRBRIGHTOUTBDDU])
        lightset = true
    end
    if (get(instrbrightinbddu) ~= configvalues[CONFIGINSTRBRIGHTINBDDU]) then
        set(instrbrightinbddu, configvalues[CONFIGINSTRBRIGHTINBDDU])
        lightset = true
    end
    if (get(instrbrightcopilotinbddu) ~= configvalues[CONFIGINSTRBRIGHTINBDDU]) then
        set(instrbrightcopilotinbddu, configvalues[CONFIGINSTRBRIGHTINBDDU])
        lightset = true
    end
    if (get(instrbrightupperdu) ~= configvalues[CONFIGINSTRBRIGHTUPPERDU]) then
        set(instrbrightupperdu, configvalues[CONFIGINSTRBRIGHTUPPERDU])
        lightset = true
    end
    if (get(instrbrightlowdu) ~= configvalues[CONFIGINSTRBRIGHTLOWDU]) then
        set(instrbrightlowdu, configvalues[CONFIGINSTRBRIGHTLOWDU])
        lightset = true
    end
    if (get(instrbrightinbdduS) ~= configvalues[CONFIGINSTRBRIGHTINBDDUS]) then
        set(instrbrightinbdduS, configvalues[CONFIGINSTRBRIGHTINBDDUS])
        lightset = true
    end
    if (get(instrbrightcopilotinbdduS) ~= configvalues[CONFIGINSTRBRIGHTINBDDUS]) then
        set(instrbrightcopilotinbdduS, configvalues[CONFIGINSTRBRIGHTINBDDUS])
        lightset = true
    end
    if (get(instrbrightlowduS) ~= configvalues[CONFIGINSTRBRIGHTLOWDUS]) then
        set(instrbrightlowduS, configvalues[CONFIGINSTRBRIGHTLOWDUS])
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

    if (configvalues[CONFIGVOICEREADBACK] == ON) then
        configvalues[CONFIGVOICEREADBACK] = OFF
    else
        configvalues[CONFIGVOICEREADBACK] = ON
        commandtableentry(TEXT, "Voice Read back On")
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
-- sasl.appendMenuItem(P.menu_main, "Toggle Voice Readback", togglevoicereadback)

--------------------------------------------------------------------------------------------------------------

function toggleadviceonly()

    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
        configvalues[CONFIGVOICEADVICEONLY] = OFF
        commandtableentry(ADVICE, "Advice Only Off")
    else
        configvalues[CONFIGVOICEADVICEONLY] = ON
        commandtableentry(ADVICE, "Advice Only On")
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

    if not procedureabort then

        procedureabort = true

        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Procedure Aborted")
        else
            commandtableentry(Text, "Procedure Aborted")
        end
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

    if ((procedureloop1.lock ~= NOPROCEDURE) and (configvalues[CONFIGVOICEADVICEONLY] == ON)) then
        commandtableentry(ADVICE, "Procedure Step Skipped")
        procedureskipstep = true
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
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 15")
        else
            helpers.command_once("laminar/B738/push_button/flaps_15")
        end
    elseif ((get(airspeed) > get(flaps10speed)) and (get(airspeed) <= get(flaps5speed)) and (get(flapleverpos) > FLAPS10)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 10")
        else
            helpers.command_once("laminar/B738/push_button/flaps_10")
        end
    elseif ((get(airspeed) > get(flaps5speed)) and (get(airspeed) <= get(flaps1speed)) and (get(flapleverpos) > FLAPS5)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 5")
        else
            helpers.command_once("laminar/B738/push_button/flaps_5")
      end
    elseif ((get(airspeed) > get(flaps1speed)) and (get(airspeed) <= get(flapsupspeed)) and (get(flapleverpos) > FLAPS1)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 1")
        else
            helpers.command_once("laminar/B738/push_button/flaps_1")
        end
    elseif ((get(airspeed) > get(flapsupspeed)) and (get(flapleverpos) > FLAPSUP)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps Up")
        else
            helpers.command_once("laminar/B738/push_button/flaps_0")
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------

function flapsdownhandling()

    if ((get(airspeed) < get(flapsupspeed)) and (get(airspeed) >= get(flaps1speed)) and (get(flapleverpos) < FLAPS1)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 1")
        else
            helpers.command_once("laminar/B738/push_button/flaps_1")
        end
    elseif ((get(airspeed) < get(flaps1speed)) and (get(airspeed) >= get(flaps5speed)) and (get(flapleverpos) < FLAPS5)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 5")
        else
            helpers.command_once("laminar/B738/push_button/flaps_5")
        end
    elseif ((get(airspeed) < get(flaps5speed)) and (get(airspeed) >= get(flaps10speed)) and (get(flapleverpos) < FLAPS10)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 10")
        else
            helpers.command_once("laminar/B738/push_button/flaps_10")
        end
    elseif ((get(airspeed) < get(flaps10speed)) and (get(airspeed) >= get(flaps15speed)) and (get(flapleverpos) < FLAPS15)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 15")
        else
            helpers.command_once("laminar/B738/push_button/flaps_15")
        end
    elseif ((get(airspeed) < get(flaps15speed)) and (get(airspeed) >= get(flaps25speed)) and (get(flapleverpos) < FLAPS25)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 25")
        else
            helpers.command_once("laminar/B738/push_button/flaps_25")
        end
    elseif ((get(airspeed) < get(flaps25speed)) and (get(flapleverpos) < FLAPS30)) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Set Flaps 30")
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
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 1, 1))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 2, 2))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 3, 3))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 4, 4))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(ilsfreq, 5, 5))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_act_stby")
    end

    if ((mmr == MMRBOTH) or (mmr == MMRFO)) then
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 1, 1))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 2, 2))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 3, 3))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 4, 4))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(ilsfreq, 5, 5))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_act_stby")
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
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 1, 1))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 2, 2))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 3, 3))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 4, 4))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_" .. string.sub(glsfreq, 5, 5))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr1_act_stby")
    end

    if ((mmr == MMRBOTH) or (mmr == MMRFO)) then
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 1, 1))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 2, 2))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 3, 3))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 4, 4))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(glsfreq, 5, 5))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_act_stby")
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
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 1, 1))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 2, 2))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 3, 3))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 4, 4))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_" .. string.sub(mmrvalue, 5, 5))
        commandtableentry(COMMAND, "laminar/B738/push_button/mmr2_act_stby")

        setnav = true
    end

    if setnav then
        commandtableentry(TEXT, "NAV 1 copied to NAV 2")
    else
        commandtableentry(TEXT, "NAV 1 and NAV 2 already aligned")
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

    if (setils.stepindex > 5) then
        setils.stepindex = 1
        setils.previousstepindex = 1
        setils.steprepeat = false
        return true
    end

    if (setils.stepindex == 1) then
        if ((string.len(FMC1Line00L) < 9) or (string.sub(FMC1Line00L, 7, 9) ~= "APP")) then
            helpers.command_once("laminar/B738/button/fmc1_init_ref")
            setils.stepindex = setils.stepindex - 1
        else
            if ((string.len(FMC1Line04X) == 24) and (string.len(FMC1Line04L) == 24)) then
                apptype = string.sub(FMC1Line04X, 2, 4)

                navdatatableindex = 0

                if ((apptype == NAVTYPEILS) or (apptype == NAVTYPEGLS)) then
                    navdatatableindex = getnavdataindex(get(desicao), get(desrwy), apptype)
                else
                    navdatatableindex = getnavdataindex(get(desicao), get(desrwy), NAVTYPELPV)
                end

                if (navdatatable[navdatatableindex] ~= nil) then
                    if ((navdatatable[navdatatableindex][DESTNAVTYPE] == NAVTYPEILS) and navdatatable[navdatatableindex][DESTNAVDME]) then
                        dmestring = "with DME"
                    else
                        dmestring = ""
                    end
                    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        commandtableentry(ADVICE, addspaces(navdatatable[navdatatableindex][DESTNAVTYPE]) .. " Approach " .. dmestring)
                    else
                        commandtableentry(TEXT, addspaces(navdatatable[navdatatableindex][DESTNAVTYPE]) .. " Approach " .. dmestring)
                    end
                else               
                    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        commandtableentry(ADVICE, "No Approach Frequency and Course found")
                    else
                        commandtableentry(TEXT, "No Approach Frequency and Course Found")
                    end
                    setils.stepindex = 6
                    return false
                end
            end
        end
    end

    if (setils.stepindex == 2) then
        if (navdatatable[navdatatableindex][DESTNAVTYPE] == NAVTYPEILS) then
            if ((navdatatable[navdatatableindex][DESTFREQ] ~= get(nav1freq)) or ((get(mmrinstalled) == ON) and ((get(mmrcptactvalue) ~= navdatatable[navdatatableindex][DESTFREQ]) or (get(mmrcptactmode) ~= MMRILS)))) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Frequency " .. addspaces(formatILSFrequency(navdatatable[navdatatableindex][DESTFREQ])))
                    setils.stepindex = setils.stepindex - 1
                else
                    if (get(mmrinstalled) == ON) then
                        setmmrils(MMRCAPTAIN, navdatatable[navdatatableindex][DESTFREQ])
                    else
                        set(nav1stdbyfreq, get(nav1freq))
                        set(nav1freq, navdatatable[navdatatableindex][DESTFREQ])
                    end
                end
            elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not setils.steprepeat) then
                commandtableentry(ADVICE, "Frequency checked and " .. addspaces(formatILSFrequency(navdatatable[navdatatableindex][DESTFREQ])))
            end
        elseif (((navdatatable[navdatatableindex][DESTNAVTYPE] == NAVTYPEGLS) or (navdatatable[navdatatableindex][DESTNAVTYPE] == NAVTYPELPV)) and (get(mmrinstalled) == ON)) then
            if ((get(mmrcptactvalue) ~= navdatatable[navdatatableindex][DESTFREQ]) or not ((get(mmrcptactmode) ~= MMRGLS) or (get(mmrcptactmode) ~= MMRLPV))) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Channel " .. addspaces(navdatatable[navdatatableindex][DESTFREQ]))
                    setils.stepindex = setils.stepindex - 1
                else
                    setmmrgls(MMRCAPTAIN, navdatatable[navdatatableindex][DESTFREQ])
                end
            elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not setils.steprepeat) then
                commandtableentry(ADVICE, "Channel checked and " .. addspaces(navdatatable[navdatatableindex][DESTFREQ]))
            end
        end
    end

    if (setils.stepindex == 3) then
        pilotcoursenew = navdatatable[navdatatableindex][DESTCOURSE]

        if (get(mcppilotcourse) ~= pilotcoursenew) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Course " .. addspaces(padNumberWithZerosStrict(pilotcoursenew, 3)))
                setils.stepindex = setils.stepindex - 1
            else   
                set(mcppilotcourse, pilotcoursenew)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not setils.steprepeat) then
            commandtableentry(ADVICE, "Course checked and " ..  addspaces(padNumberWithZerosStrict(pilotcoursenew, 3)))
        end   
    end

    if (setils.stepindex == 4) then
        if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) or (procedureloop1.lock == SETILSPROCEDURE)) then
            if ((navdatatable[navdatatableindex][DESTNAVTYPE] == NAVTYPEILS) and navdatatable[navdatatableindex][DESTNAVDME]) then
                if ((get(nav2freq) ~= get(nav1freq)) or ((get(mmrinstalled) == ON) and ((get(mmrfoactvalue) ~= get(nav1freq)) or (get(mmrfoactmode) ~= MMRILS)))) then
                    if (get(mmrinstalled) == ON) then
                        setmmrils(MMRFO, get(nav1freq))
                    else
                        set(nav2stdbyfreq, get(nav2freq))
                        set(nav2freq, get(nav1freq))
                    end
                end
            elseif ((navdatatable[navdatatableindex][DESTNAVTYPE] == NAVTYPEGLS) and (get(mmrinstalled) == ON)) then
                if ((get(mmrfoactvalue) ~= (get(mmrcptactvalue)) or (get(mmrfoactmode) ~= MMRGLS))) then
                    setmmrgls(MMRFO, get(mmrcptactvalue))
                end
            end
        end
    end

    if (setils.stepindex == 5) then
        if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) or (procedureloop1.lock == SETILSPROCEDURE)) then
            if ((navdatatable[navdatatableindex][DESTNAVTYPE] == NAVTYPEILS) and navdatatable[navdatatableindex][DESTNAVDME]) then
                if (get(mcpcopilotcourse) ~= get(mcppilotcourse)) then
                    set(mcpcopilotcourse, get(mcppilotcourse))
                end
            elseif ((navdatatable[navdatatableindex][DESTNAVTYPE]  == NAVTYPEGLS) and (get(mmrinstalled) == ON)) then
                if (get(mcpcopilotcourse) ~= get(mcppilotcourse)) then
                    set(mcpcopilotcourse, get(mcppilotcourse))
                end
            end
        end      
    end

    setils.stepindex = setils.stepindex + 1

    if (setils.stepindex == setils.previousstepindex) then
        setils.steprepeat = true
    else
        setils.steprepeat = false
        setils.previousstepindex = setils.stepindex
    end

   return false

end

function setilsproc()

    if (procedureloop1.lock == NOPROCEDURE) then
        procedureloop1.lock = SETILSPROCEDURE
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
    for idx, part in ipairs(parts) do
        sasl.logDebug(string.format("  [%d] = %s", idx, part))
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
            local time = dt:sub(3,6)
            if (day and time) then
                result.date_time = { day = day, time = time, timezone = "Z" }
                sasl.logDebug(string.format("Parsed datetime: day=%d, time=%s", result.date_time.day, result.date_time.time))
            else
                sasl.logDebug("Warning: Could not parse day or time")
            end
        end
    end

    local i = 3
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
        for _, code in ipairs(weather_codes) do
            if (s:find(code, 1, true)) then
                return true
            end
        end
        return false
    end

    while (i <= #parts and parsing_main_data) do
        local part = parts[i]
        sasl.logDebug(string.format("Processing part %d: %s", i, part))
        local parsed = false

        if (part == "TEMPO" or part == "BECMG" or part:sub(1,4) == "PROB" or part == "TREND") then
            parsing_main_data = false
            sasl.logDebug("Skipping trend/change group: "..part)
        else
            -- CAVOK
            if (part == "CAVOK") then
                result.cavok = true
                result.visibility = { value = 10000 }
                sasl.logDebug("Parsed CAVOK: visibility >= 10km")
                parsed = true
            elseif ((not result.wind) and (#part >= 5)) then
                local dir_str = part:sub(1,3)
                local direction = (dir_str == "VRB") and "VRB" or tonumber(dir_str)

                local var_dir_match = nil
                if ((#part >= 9) and (part:sub(6,6) == "V")) then
                    local dir1_str = part:sub(4,5)
                    local dir2_str = part:sub(7,9)
                    local dir1 = tonumber(dir1_str)
                    local dir2 = tonumber(dir2_str)
                    if (dir1 and dir2) then
                        var_dir_match = { dir1 = dir1, dir2 = dir2 }
                        sasl.logDebug(string.format("Parsed variable wind direction: %d-%d", dir1, dir2))
                    end
                end

                local unit = ((part:sub(-2) == "KT") and "KT") or
                             ((part:sub(-3) == "MPS") and "MPS") or
                             ((part:sub(-3) == "KMH") and "KMH") or nil

                if (direction and unit) then
                    local speed_str = ""
                    local gust_str = nil
                    local g_pos = nil

                    for char_index = 4, #part - #unit do
                        if (part:sub(char_index, char_index) == "G") then
                            g_pos = char_index
                            break
                        end
                    end

                    if (g_pos) then
                        speed_str = part:sub(4, g_pos - 1)
                        gust_str = part:sub(g_pos + 1, #part - #unit)
                    else
                        speed_str = part:sub(4, #part - #unit)
                    end

                    local speed = tonumber(speed_str)
                    local gust = (gust_str and tonumber(gust_str)) or 0

                    if (speed) then
                        if (unit == "MPS") then
                            speed = math.floor(speed * 1.94384 + 0.5)
                            if (gust ~= nil) then gust = math.floor(gust * 1.94384 + 0.5) end
                            sasl.logDebug(string.format("Converted %s m/s to %d kt", speed_str, speed))
                        elseif ((unit == "KMH") or (unit == "KMT")) then
                            speed = math.floor(speed * 0.539957 + 0.5)
                            if (gust ~= nil) then gust = math.floor(gust * 0.539957 + 0.5) end
                            sasl.logDebug(string.format("Converted %s km/h to %d kt", speed_str, speed))
                        end

                        result.wind = {
                            direction = direction,
                            speed = speed,
                            gust = gust,
                            variable_direction = var_dir_match
                        }
                        sasl.logDebug(string.format("Parsed wind: dir=%s, speed=%d kt, gust=%d kt%s",
                            direction, speed, gust, (var_dir_match and string.format(", var=%d-%d", var_dir_match.dir1, var_dir_match.dir2)) or ""))
                        parsed = true
                    else
                        sasl.logDebug("Warning: Could not parse wind speed")
                    end
                else
                    sasl.logDebug("Warning: Could not parse wind direction or unit")
                end
            elseif (not result.visibility) then
                if ((#part == 4)) then
                    local vis_value = tonumber(part)
                    if (vis_value) then
                        result.visibility = { value = vis_value }
                        sasl.logDebug(string.format("Parsed visibility: %d meters", result.visibility.value))
                        parsed = true
                    elseif (part == "9999") then
                        result.visibility = { value = 10000 }
                        sasl.logDebug("Parsed visibility: 10000+ meters (9999)")
                        parsed = true
                    end
                elseif ((string.sub(part, -2) == "SM")) then
                    local sm_value_str = string.sub(part, 1, #part - 2)
                    local sm_value = tonumber(sm_value_str)
                    if (sm_value) then
                        local meters = math.floor(sm_value * 1609.34 + 0.5)
                        result.visibility = { value = math.min(meters, 10000) }
                        sasl.logDebug(string.format("Parsed visibility: %d SM, converted to %d meters (limited to 10000)", sm_value, result.visibility.value))
                        parsed = true
                    end
                end
            elseif (#part >= 6) then
                local coverage = part:sub(1,3)
                if (((coverage == "FEW") or (coverage == "SCT") or (coverage == "BKN") or (coverage == "OVC"))) then
                    local altitude_str = part:sub(4,6)
                    local altitude = tonumber(altitude_str)
                    if ((#altitude_str == 3) and altitude) then
                        result.clouds = result.clouds or {}
                        local cloud_type = part:sub(7) or ""
                        table.insert(result.clouds, {
                            coverage = coverage,
                            altitude = altitude * 100,
                            type = cloud_type
                        })
                        sasl.logDebug(string.format("Parsed cloud: %s at %d ft%s",
                            coverage, altitude * 100,
                            (cloud_type ~= "" and (" ("..cloud_type..")")) or ""))
                        parsed = true
                    else
                        sasl.logDebug("Warning: Could not parse cloud altitude")
                    end
                end
            elseif ((#part == 5) or (#part == 6)) then
                local slash_pos = nil
                for char_index = 1, #part do
                    if (part:sub(char_index, char_index) == "/") then
                        slash_pos = char_index
                        break
                    end
                end
                if (slash_pos and ((slash_pos == 3) or (slash_pos == 4))) then
                    local temp_str = part:sub(1, slash_pos-1)
                    local dew_str = part:sub(slash_pos+1)

                    local temp_str_modified = temp_str:gsub("M", "-")
                    local temp = tonumber(temp_str_modified)

                    local dew_str_modified = dew_str:gsub("M", "-")
                    local dew = tonumber(dew_str_modified)

                    if ((temp ~= nil) and (dew ~= nil)) then
                        result.temperature = { value = temp }
                        result.dew_point = { value = dew }
                        sasl.logDebug(string.format("Parsed temp/dew: %d°C/%d°C", temp, dew))
                        parsed = true
                    else
                        sasl.logDebug("Warning: Could not parse temperature or dew point")
                    end
                end
            elseif ((#part == 5) and ((part:sub(1,1) == "Q") or (part:sub(1,1) == "A"))) then
                local value_str = part:sub(2)
                local value = tonumber(value_str)
                local pressure_hpa = nil

                if (value) then
                    if (part:sub(1,1) == "Q") then
                        pressure_hpa = math.floor(value + 0.5)
                        sasl.logDebug(string.format("Parsed pressure: %d hPa (raw: %s)", pressure_hpa, part))
                        parsed = true
                    elseif (part:sub(1,1) == "A") then
                        local inHg = tonumber(string.format("%d.%02d", math.floor(value / 100), value % 100))
                        if (inHg) then
                            pressure_hpa = math.floor(inHg * 33.8639 + 0.5)
                            sasl.logDebug(string.format("Parsed pressure: %d hPa (raw: %s)", pressure_hpa, part))
                            parsed = true
                        end
                    else
                        sasl.logDebug("Warning: Could not convert pressure to hPa")
                    end
                else
                    sasl.logDebug("Warning: Could not parse pressure value")
                end
            elseif (is_weather_code(part)) then
                result.weather = result.weather or {}
                local intensity = (part:sub(1,1) == "-") and "light" or (part:sub(1,1) == "+") and "heavy" or "moderate"
                local phenomenon = (intensity ~= "moderate") and part:sub(2) or part

                table.insert(result.weather, {
                    intensity = intensity,
                    phenomenon = phenomenon
                })
                sasl.logDebug(string.format("Parsed weather: %s (%s)", phenomenon, intensity))
                parsed = true
            elseif ((#part >= 6) and (part:sub(1,1) == "R") and (part:sub(4,4) == "/")) then
                result.runway_reports = result.runway_reports or {}
                table.insert(result.runway_reports, part)
                sasl.logDebug("Parsed runway report: "..part)
                parsed = true
            elseif (part == "NOSIG") then
                result.nosig = true
                sasl.logDebug("Parsed NOSIG: no significant change expected")
                parsed = true
            elseif (part == "RMK") then
                result.remarks = {}
                i = i + 1
                while (i <= #parts) do
                    table.insert(result.remarks, parts[i])
                    sasl.logDebug("Parsed remark: "..parts[i])
                    i = i + 1
                end
                break
            end

            if (not parsed) then
                sasl.logDebug("Unknown element: "..part)
            end
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
function calculateAirDensity(weatherData)
    local pressureIn, pressureHPa = getlocalqnh(ARRIVAL)
    local temperatureKelvin = weatherData.temperature.value + 273.15  -- Umrechnung von Celsius in Kelvin

    -- Spezifische Gaskonstante für trockene Luft (J/(kg·K))
    local specificGasConstant = 287.05

    -- Luftdichte berechnen (kg/m³)
    local airDensity = (pressureHPa * 100) / (specificGasConstant * temperatureKelvin)

    sasl.logDebug("AIRDENSITY: PRESSUREINCH "  .. tostring(pressureIn) .. " PRESSUREPA "  .. tostring(pressurePa) .. " TEMPERATURE" .. tostring(weatherData.temperature.value) .. " AIRDENSITY " .. tostring(airDensity))

    return airDensity
end

--------------------------------------------------------------------------------------------------------------
function calculateStallSpeed(weightKg, weatherData,flapsSetting)
    local gravity = 9.80665
    local wingArea = 124.6

    local maxLiftCoefficientValues = {
        [0] = 1.6,  -- Flaps 0
        [5] = 1.8,  -- Flaps 5
        [10] = 2.0, -- Flaps 10
        [15] = 2.2, -- Flaps 15
        [20] = 2.4, -- Flaps 20
        [25] = 2.6, -- Flaps 25
        [30] = 2.8, -- Flaps 30
        [40] = 3.0  -- Flaps 40
    }

    local maxLiftCoefficient = maxLiftCoefficientValues[flapsSetting] or 2.5

    local airDensity = calculateAirDensity(weatherData)

    local stallSpeedMps = math.sqrt((2 * weightKg * gravity) / (airDensity * wingArea * maxLiftCoefficient))

    local stallSpeedKnots = stallSpeedMps * 1.94384

    sasl.logDebug("STALLDSPEED: AIRDENSITY " .. tostring(airDensity) .. " WEIGHTKG " .. tostring(weightKg) .. " WEIGHTKG " .. tostring(flapsSetting) .. " STALLSPEEDKNOTS " .. tostring(stallSpeedKnots))


    return stallSpeedKnots
end

--------------------------------------------------------------------------------------------------------------
function calculateCrosswind(windDirection, runwayHeading, windSpeed)
    if tonumber(windDirection) then
        local angleDifference = math.rad(math.abs(windDirection - runwayHeading))
        local crosswind = math.abs(math.sin(angleDifference) * windSpeed)
        return crosswind
    else
        return 0
    end
end

--------------------------------------------------------------------------------------------------------------
function determineFlapsSetting(runwayLengthMeters, windSpeedKnots, crosswindKnots, isBadWeather, weightKg)
    local shortRunwayThreshold = 2000
    local highWindThreshold = 20
    local highCrosswindThreshold = 15
    local highWeightThreshold = 55000

    if runwayLengthMeters < shortRunwayThreshold or
       windSpeedKnots > highWindThreshold or
       crosswindKnots > highCrosswindThreshold or
       isBadWeather or
       weightKg > highWeightThreshold then
        return 40
    else
        return 30
    end
end

--------------------------------------------------------------------------------------------------------------
function calculateVref(weightKg, flapsSetting, weatherData, crosswindKnots)
    local stallSpeedKnots = calculateStallSpeed(weightKg, weatherData,flapsSetting)
    local vrefKnots = stallSpeedKnots * 1.37

    if weatherData.wind.speed and weatherData.wind.speed > 20 then
        vrefKnots = vrefKnots + 5  -- Erhöhung der Vref bei starkem Wind
    end
    if containsvalue(weatherData, "RA") or containsvalue(weatherData, "SN") then
        vrefKnots = vrefKnots + 5  -- Erhöhung der Vref bei Niederschlag
    end
    if crosswindKnots > 15 then
        vrefKnots = vrefKnots + 5  -- Erhöhung der Vref bei starkem Seitenwind
    end

    return vrefKnots
end

--------------------------------------------------------------------------------------------------------------
function calcappflapsvref(weatherData)

    if not (fieldexists(weatherData, "wind.direction") and fieldexists(weatherData, "wind.speed") and fieldexists(weatherData, "temperature.value")) then
        sasl.logDebug("CALCAPPFLAPSVREF: WEATHER DATA MISSING, USING STANDARD VREF30")
        return 30, get(vref30)
    end

    local runwayHeading = get(desrwyheading)

    local crosswindKnots = calculateCrosswind(weatherData.wind.direction, runwayHeading, weatherData.wind.speed)

    sasl.logDebug("CALCAPPFLAPSVREF: CROSSWINDKNOTS "  .. tostring(crosswindKnots) .. " WINDDIRECTION" .. tostring(weatherData.wind.direction) .. " WINDSPEED " .. tostring(weatherData.wind.speed) ..  " RWY HEADING " ..  tostring(runwayHeading))

    local runwayLength = get(desrwylen)
    local weightKg = get(totalweightkgs)

    local isBadWeather = (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "RA") or containsvalue(weatherData.weather, "SN")) or (fieldexists(weatherData, "visibility.value") and (weatherData.visibility.value < 5000)) or (fieldexists(weatherData, "clouds[1].altitude") and weatherData.clouds[1].altitude and (weatherData.clouds[1].altitude < 1000)))

    sasl.logDebug("CALCAPPFLAPSVREF: ISBADWEATHER " .. tostring(isBadWeather) .. "WEATHER" .. tostring((fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "RA") or containsvalue(weatherData.weather, "SN"))))
                    .. " VISIBILITY " .. tostring(fieldexists(weatherData, "visibility.value") and (weatherData.visibility.value < 5000)) ..  " CLOUDS " ..  tostring(fieldexists(weatherData, "clouds[1].altitude") and (weatherData.clouds[1].altitude < 1000)))

    local flapsSetting = determineFlapsSetting(runwayLength, weatherData.wind.speed, crosswindKnots, isBadWeather, weightKg)

    local airportHeightMeters = roundnumber(get(desrwyalt) / FEETTOMETER)  -- Höhe des Flughafens über Meereshöhe
 
    local vrefKnots = roundnumber(calculateVref(weightKg, flapsSetting, weatherData, crosswindKnots))
  
    sasl.logDebug("CALCAPPFLAPSVREF: FLAPS " .. flapsSetting .. " SPEED " .. vrefKnots .. "  WEIGHTKG "  .. tostring(weightKg))

    return flapsSetting, vrefKnots

end

--------------------------------------------------------------------------------------------------------------
function setvref(appflapscalc, appvrefcalc)

    local FMC1Line00L = helpers.get("laminar/B738/fmc1/Line00_L")
    local FMC1Line02S = helpers.get("laminar/B738/fmc1/Line02_S")
    local FMC1Line04L = helpers.get("laminar/B738/fmc1/Line04_L")

    helpers.command_once("laminar/B738/button/fmc1_init_ref")

    if ((string.len(FMC1Line00L) < 9) or (string.sub(FMC1Line00L, 7, 9) ~= "APP")) then
        return false
    else
        if ((string.sub(FMC1Line04L, 19, 19) == "-") and (string.sub(FMC1Line02S, 20, 20) ~= "-")) then
            vrefcmdtable[6] = string.sub(FMC1Line02S, 20, 20)
            vrefcmdtable[7] = string.sub(FMC1Line02S, 21, 21)
            vrefcmdtable[8] = string.sub(FMC1Line02S, 22, 22)

            tableindex = 1
            while (vrefcmdtable[tableindex] ~= "end") do
                sasl.logDebug("while loop setvref")
                commandtableentry(COMMAND, "laminar/B738/button/fmc1_" .. vrefcmdtable[tableindex])
                tableindex = tableindex + 1
            end

            commandtableentry(TEXT, "V REF 30 " .. string.sub(FMC1Line02S, 20, 20) .. string.sub(FMC1Line02S, 21, 21) .. string.sub(FMC1Line02S, 22, 22) .. " Knots")
        end

        return true
    end
end

function setvrefproc()

    if (procedureloop1.lock == NOPROCEDURE) then
        procedureloop1.lock = SETVREF30PROCEDURE
    end

    if (flightstate <= 2) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Set V R E F 30 aborted")
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

my_command_setvref = sasl.createCommand(definitions.APPNAMEPREFIX .. "/setvref", "Set VREF 30")
sasl.registerCommandHandler(my_command_setvref, 0, setvrefproc_)

--------------------------------------------------------------------------------------------------------------
function calcautobrake(landingSpeed, weatherData)

    local autobrakeSettings = {
        {maxDeceleration = 1.5, setting = AUTOBRAKE1},
        {maxDeceleration = 2.0, setting = AUTOBRAKE2},
        {maxDeceleration = 3.0, setting = AUTOBRAKE3},
        {maxDeceleration = 4.0, setting = AUTOBRAKEMAX}
    }

    local runwayLength = get(desrwylen)
    local aircraftWeight = get(totalweightkgs)

    local requiredDeceleration = (landingSpeed^2) / (2 * runwayLength)

    if ((fieldexists(weatherData, "weather") and ((containsvalue(weatherData.weather, "FZRA")) or (containsvalue(weatherData.weather, "FZDZ")) or (containsvalue(weatherData.weather, "FZFG"))))
        or (fieldexists(weatherData, "temperature.value") and (weatherData.temperature.value < 1))) then
        requiredDeceleration = requiredDeceleration * 1.5
    elseif (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "SN")))  then
        requiredDeceleration = requiredDeceleration * 1.3
    elseif (fieldexists(weatherData, "weather") and (containsvalue(weatherData.weather, "RA"))) then
        requiredDeceleration = requiredDeceleration * 1.2
    end

    local weightFactor = aircraftWeight / 70000
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
        centertankoffset = false
    elseif (((not centertankoffset) and (get(centertanklbs) <= 1000)) or ((get(centertanklpress) == 0) and (get(centertankrpress) == 0))) then
        if (get(centertanklswitch) == ON) then
            set(centertanklswitch, OFF)
        end
        if (get(centertankrswitch) == ON) then
            set(centertankrswitch, OFF)
        end
        centertankoffset = true
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

    if ((procedureloop1.stepindex > 30) or procedureabort) then
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVIEWCHANGES] == ON) then
            helpers.command_once("sim/view/default_view")
            if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (get(battery) == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Battery On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/switch/battery_dn")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Battery Checked and On")
        end
    end

    if (procedureloop1.stepindex == 3) then
        if (get(batteryswitchcover) == OPEN) then
            helpers.command_once("laminar/B738/button_switch_cover02")
        end
    end

    if (procedureloop1.stepindex == 4) then
        if not setview(configvalues[CONFIGVIEWUPPEROVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 5) then
        if (get(domelightpos) == DOMELIGHTOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Domelight On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                setdomelight(DOMELIGHTDIM)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Domelight Checked and On")
        end
    end

    if (procedureloop1.stepindex == 6) then
        if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 7) then
        if (get(emergencylights) ~= EMERGLIGHTSARMED) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Arm Emergency Lights")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                setemergencylights(EMERGLIGHTSARMED)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Emergency Lights Checked and Armed")
        end
    end

    if (procedureloop1.stepindex == 8) then
        if (get(emergencylightcover) == OPEN) then
            helpers.command_once("laminar/B738/button_switch_cover09")
        end
    end

    if (procedureloop1.stepindex == 9) then
        if (get(positionlights) ~= POSLIGHTSSTEADY) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Position Lights Steady")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/position_light_steady")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Position Lights Checked and Steady")
        end
    end

     if (procedureloop1.stepindex == 10) then
        if (get(nosmokingsignpos) ~= NOSMOKINGSIGNON) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setnosmokingsign(NOSMOKINGSIGNON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set No Smoking Signs On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "No Smoking Signs Checked and On")
        end
    end

    if (procedureloop1.stepindex == 11) then
        if ((configvalues[CONFIGUSEGROUNDPOWER] == ON) and (get(gpuavailable) == ON)) then
            if (get(gpuon) == OFF) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Switch Ground Power On")
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                else
                    helpers.command_once("laminar/B738/toggle_switch/gpu_dn")
                    procedureloop1.stepindex = 19
                    return true
                end
            else
                if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                    commandtableentry(ADVICE, "G P U Checked and On")
                end
                procedureloop1.stepindex = 19
                return true
            end
        end
    end

    if (procedureloop1.stepindex == 12) then
        if (get(apustarterpos) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Start A P U")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Checked and Started")
        end
    end  

    if (procedureloop1.stepindex == 13) then
        if (configvalues[CONFIGVOICEADVICEONLY]  ~= ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            commandtableentry(TEXT, "A P U Started")
        end
    end

    if (procedureloop1.stepindex == 14) then
        if (get(apugenoffbus) == OFF) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        else
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "A P U Running")
            else
                commandtableentry(TEXT, "A P U Running")
            end
        end
    end

    if (procedureloop1.stepindex == 15) then
        if (not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF))) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Generator On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Generator Checked and On")
        end
    end

    if (procedureloop1.stepindex == 16) then
        if (get(bleedairapupos) == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Bleed Air On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                 helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Bleed Air Checked and On")    
        end
    end

    if (procedureloop1.stepindex == 17) then
        if (get(isolvalvepos)  ~= ISOLVALVEOPEN) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Isolation Valve Open")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEOPEN)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Isolation Valve Checked and Open")    
        end
    end

    if (procedureloop1.stepindex == 18) then
        if ((get(packlpos) ~= PACKAUTO) or (get(packrpos) ~= PACKAUTO)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Packs Auto")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(packlpos, PACKAUTO)
                set(packrpos, PACKAUTO)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Packs Checked and Auto")    
        end
    end

    if (procedureloop1.stepindex == 19) then
        if (get(trimairpos) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Trim Air On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(trimairpos, ON)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Trim Air Checked and On")    
        end
    end

    if (procedureloop1.stepindex == 20) then
        if not setview(configvalues[CONFIGVIEWUPPEROVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 21) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            if not setirs(BOTHIRS, IRSNAV) then 
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        end
    end

    if (procedureloop1.stepindex == 22) then
        if ((get(irsalignleft) == OFF) or (get(irsalignright) == OFF)) then
            if ((get(irsleftpos) ~= IRSNAV) or (get(irsrightpos) ~= IRSNAV)) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Both I R S to Nav")
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                end
            elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                commandtableentry(ADVICE, "Both I R S Checked and Nav")
            end
        else
            commandtableentry(TEXT, "I R S Alignment Started")
        end
    end

    if (procedureloop1.stepindex == 23) then
        if not setview(configvalues[CONFIGVIEWFMS]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 24) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Initialize I R S Position")
        end
        helpers.command_once("laminar/B738/button/fmc1_init_ref")
    end

    if (procedureloop1.stepindex == 25) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            helpers.command_once("laminar/B738/button/fmc1_next_page")
        end
    end

    if (procedureloop1.stepindex == 26) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            helpers.command_once("laminar/B738/button/fmc1_4L")
        end
    end

    if (procedureloop1.stepindex == 27) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            helpers.command_once("laminar/B738/button/fmc1_prev_page")
        end
    end

    if (procedureloop1.stepindex == 28) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            helpers.command_once("laminar/B738/button/fmc1_4R")
            commandtableentry(TEXT, "I R S Position Initialization Complete")
        end
    end

    if (procedureloop1.stepindex == 29) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 30) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cold and Dark Startup Procedure Complete")
        else
            commandtableentry(TEXT, "Cold and Dark Startup Procedure Complete")
        end
    end

    return true

end

function coldanddarkstartup()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = COLDANDDARKPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cold and Dark Startup Not Possible Inflight")
        else
            commandtableentry(TEXT, "Cold and Dark Startup Not Possible Inflight")
        end
        return true
    end

    if ((get(battery) == ON) and (get(mainbus) == ON)) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cold and Dark Startup Aborted")
        else
            commandtableentry(TEXT, "Cold and Dark Startup Aborted")
        end
        return true
    end

    if (get(apurunning) == ON) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cold and Dark Startup Aborted, A P U already running")
        else
            commandtableentry(TEXT, "Cold and Dark Startup Aborted, A P U already running")
        end
        return true
    end

    if enginesrunning(BOTH) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE,  "Cold and Dark Startup Aborted, Engines already running")
        else
            commandtableentry(TEXT,  "Cold and Dark Startup Aborted, Engines already running")
        end
        return true
    end

    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
        commandtableentry(ADVICE, "Cold and Dark Startup Procedure")
    else
        commandtableentry(TEXT, "Cold and Dark Startup Procedure")
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

    if ((procedureloop1.stepindex > 8) or procedureabort) then
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVIEWCHANGES] == ON) then
            helpers.command_once("sim/view/default_view")
            if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (get(apustarterpos) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Start A P U")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Checked and Started")
        end
    end


    if (procedureloop1.stepindex == 3) then
        if (configvalues[CONFIGVOICEADVICEONLY]  ~= ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            commandtableentry(TEXT, "A P U Running Up")
        else
            commandtableentry(ADVICE, "A P U Running Up")
        end
    end

    if (procedureloop1.stepindex == 4) then
        if (get(apugenoffbus) == OFF) then 
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        else
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "A P U Running")
            else
                commandtableentry(TEXT, "A P U Running")
            end
        end
    end

    if (procedureloop1.stepindex == 5) then
        if (not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF))) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Generator On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Generator Checked and On")
        end
    end

    if (procedureloop1.stepindex == 6) then
        if (get(gpuon) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Ground Power Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/gpu_up")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Ground Power Checked and Off")    
        end
    end
   
    if (procedureloop1.stepindex == 7) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 8) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "A P U Startup Procedure Complete")
        else
            commandtableentry(TEXT, "A P U Startup Procedure Complete")
        end
    end

    return true

end

function apustartup()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = APUSTARTUPPROCEDURE
    end

    if ((get(battery) == OFF) and (get(mainbus) == OFF)) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "A P U Startup Aborted")
        else
            commandtableentry(TEXT, "A P U Startup Aborted")
        end
        return true
    end

    if (get(apurunning) == ON) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "A P U already running")
        else
            commandtableentry(TEXT, "A P U already running")
        end
        return true
    end

    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
        commandtableentry(ADVICE, "A P U Startup Procedure")
    else
        commandtableentry(TEXT, "A P U Startup Procedure")
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
-- sasl.appendMenuItem(P.menu_main, "APU Startup", apustartup)

--------------------------------------------------------------------------------------------------------------
-- Engine Start

function enginestartsteps()

    if ((procedureloop1.stepindex > 34) or procedureabort) then
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVIEWCHANGES] == ON) then
            helpers.command_once("sim/view/default_view")
            if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (get(beaconlights) == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Collision Lights On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                togglecollisionlights(ON)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Collision lightset Checked and On")
        end     
    end

    if (procedureloop1.stepindex == 3) then
        if ((get(lefttanklswitch) == OFF) or (get(lefttankrswitch) == OFF) or (get(righttanklswitch) == OFF) or (get(righttankrswitch) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Wing Tank Fuel Pumps On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(lefttanklswitch, ON)
                set(lefttankrswitch, ON)
                set(righttanklswitch, ON)
                set(righttankrswitch, ON)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Wing Fuel Tanks Checked and On")
        end
    end

    if (procedureloop1.stepindex == 4) then
        if ((get(packlpos) ~= PACKOFF) or (get(packrpos) ~= PACKOFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Packs Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(packlpos, PACKOFF)
                set(packrpos, PACKOFF)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Packs Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 5) then
        if (get(bleedairapupos) == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set A P U Bleed Air On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Bleed Air Checked and On")
        end 
    end

    if (procedureloop1.stepindex == 6) then
        if (get(isolvalvepos)  ~= ISOLVALVEOPEN) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Isolation Valve Open")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEOPEN)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Isolation Valve Checked and Open")
        end 
    end

    if (procedureloop1.stepindex == 7) then
        if (get(starter2pos)  ~= GROUND) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Starter 2 Ground")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                setstarter(ENGINE2, GROUND)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Engine 2 Starter Checked and On")
        end
    end

    if (procedureloop1.stepindex == 8) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 9) then
        if (get(eng2n2percent) < 25) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        else
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Engine 2 N 2 at 25 Percent")
            else
                commandtableentry(TEXT, "Engine 2 N 2 at 25 Percent")
            end
        end
    end 

    if (procedureloop1.stepindex == 10) then
        if not setview(configvalues[CONFIGVIEWTHROTTLE]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 11) then
        if (get(mixture2pos) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Engine 2 Fuel Lever Idle")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
               helpers.command_once("laminar/B738/engine/mixture2_idle")
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Engine 2 Fuel Lever Checked and Idle")
        end
    end

    if (procedureloop1.stepindex == 12) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 13) then
        if not enginesrunning(ENGINE2) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        else
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Engine 2 Running")
            else
                commandtableentry(TEXT, "Engine 2 Running")
            end
        end
    end

    if (procedureloop1.stepindex == 14) then
        if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 15) then
        if (get(starter1pos)  ~= GROUND) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Starter 1 Ground")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                setstarter(ENGINE1, GROUND)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Engine 1 Starter Checked and On")
        end
    end

    if (procedureloop1.stepindex == 16) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 17) then
        if (get(eng1n2percent) < 25) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        else
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Engine 1 N 2 at 25 Percent")
            else
                commandtableentry(TEXT, "Engine 1 N 2 at 25 Percent")
            end
        end
    end

    if (procedureloop1.stepindex == 18) then
        if not setview(configvalues[CONFIGVIEWTHROTTLE]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 19) then
        if (get(mixture1pos) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Engine 1 Fuel Lever Idle")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
               helpers.command_once("laminar/B738/engine/mixture1_idle")
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Engine 1 Fuel Lever Checked and Idle")
        end
    end

    if (procedureloop1.stepindex == 20) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 21) then
        if not enginesrunning(ENGINE1) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        else
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Engine 1 Running")
            else
                commandtableentry(TEXT, "Engine 1 Running")
            end
        end
    end

    if (procedureloop1.stepindex == 22) then
        if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 23) then
        if ((get(gen1pos) ~= ON) or (get(gen2pos) ~= ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Both Generators On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if (get(gen1pos) ~= ON) then
                    helpers.command_once("laminar/B738/toggle_switch/gen1_dn")
                end
                if (get(gen2pos) ~= ON) then
                    helpers.command_once("laminar/B738/toggle_switch/gen2_dn")
                end
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Generators Checked and On")
        end
    end

    if (procedureloop1.stepindex == 24) then
        if ((get(hydro1pos) ~= ON) or (get(hydro2pos) ~= ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Both Hydraulic Pumps On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(hydro1pos, ON)
                set(hydro2pos, ON)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Hydraulic Pumps Checked and On")
        end
    end

    if (procedureloop1.stepindex == 25) then
        if ((get(elechydro1pos) ~= ON) or (get(elechydro2pos) ~= ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Both Electrical Hydraulic Pumps On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(elechydro1pos, ON)
                set(elechydro2pos, ON)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Electrical Hydraulic Pumps Checked and On")
        end
    end

    if (procedureloop1.stepindex == 26) then
        if ((get(bleedair1pos) == OFF) or (get(bleedair2pos) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Engine Bleed Air On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if (get(bleedair1pos) == OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(bleedair2pos) == OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Engine Bleed Air Checked and On")
        end
    end

    if (procedureloop1.stepindex == 27) then
        if ((get(packlpos) ~= PACKAUTO) or (get(packrpos) ~= PACKAUTO)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Packs Auto")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(packlpos, PACKAUTO)
                set(packrpos, PACKAUTO)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Packs Checked and Auto")
        end
    end
 
    if (procedureloop1.stepindex == 28) then
         if (get(isolvalvepos)  ~= ISOLVALVEAUTO) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Isolation Valve Auto")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEAUTO)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Isolation ValveChecked and Auto")
        end 
    end

    if (procedureloop1.stepindex == 29) then
         if (get(trimairpos) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Trim Air On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(trimairpos, ON)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Trim Air Checked and On")
        end 
    end 

    if (procedureloop1.stepindex == 30) then
        if (get(bleedairapupos) ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Bleed Air Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                 helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Bleed Air Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 31) then
        if (get(apustarterpos) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch APU Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 32) then
        if (get(yawdamperswitch) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Yaw Damper On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(yawdamperswitch, ON)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Yaw Damper Checked and On")
        end 
    end

    if (procedureloop1.stepindex == 33) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 34) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Engine Start Procedure Complete")
        else
            commandtableentry(TEXT, "Engine Start Procedure Complete")
        end
    end

    return true


end

function enginestart()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = ENGINESTARTPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Engine Start Not Possible Inflight")
        else
            commandtableentry(TEXT, "Engine Start Not Possible Inflight")
        end
        return true
    end

    if (get(apurunning) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Engine Start Not Possible, A P U not running")
        else
            commandtableentry(TEXT, "Engine Start Not Possible, A P U not running")
        end
        return true
    end

    if enginesrunning(BOTH) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Engine Start Aborted, Engines already running")
        else
            commandtableentry(TEXT, "Engine Start Aborted, Engines already running")
        end
        return true
    end

    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
        commandtableentry(ADVICE, "Engine Start Procedure")
    else
        commandtableentry(TEXT, "Engine Start Procedure")
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
-- sasl.appendMenuItem(P.menu_main, "Engine Startup", enginestart)

--------------------------------------------------------------------------------------------------------------
-- Engine Shutdown

function engineshutdownsteps()

    if ((procedureloop1.stepindex > 18) or procedureabort) then
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        procedureabort = false
        return true
    end


    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVIEWCHANGES] == ON) then
            helpers.command_once("sim/view/default_view")
            if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (procedureloop1.lock == TURNAROUNDENGINESHUTDOWNPROCEDURE) then
            if ((configvalues[CONFIGUSEGROUNDPOWER] == ON) and (get(gpuavailable) == ON)) then
                if (get(gpuon) == OFF) then
                    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        commandtableentry(ADVICE, "Switch Ground Power On")
                        procedureloop1.stepindex = procedureloop1.stepindex - 1
                    else
                        helpers.command_once("laminar/B738/toggle_switch/gpu_dn")
                        procedureloop1.stepindex = 9
                        return true
                    end
                else
                    if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                        commandtableentry(ADVICE, "Ground Power Checked and On")
                    end 
                    procedureloop1.stepindex = 9
                    return true
                end
            end
        elseif (procedureloop1.lock == FINALENGINESHUTDOWNPROCEDURE) then
            procedureloop1.stepindex = 9
            return true
        end
    end

    if (procedureloop1.stepindex == 3) then
        if (get(apustarterpos)~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Start A P U")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Checked and Started")
        end
    end


    if (procedureloop1.stepindex == 4) then
        if (configvalues[CONFIGVOICEADVICEONLY]  ~= ON) then
            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
            commandtableentry(TEXT, "A P U Running Up")
        else
            commandtableentry(ADVICE, "A P U Running Up")
        end
    end

    if (procedureloop1.stepindex == 5) then
        if (get(apugenoffbus) == OFF) then 
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        else
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "A P U Running")
            else
                commandtableentry(TEXT, "A P U Running")
            end
        end
    end

    if (procedureloop1.stepindex == 6) then
        if (not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF))) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Generator On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_dn")
                end
                if not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen2_dn")
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Generator Checked and On")
        end
    end

    if (procedureloop1.stepindex == 7) then
        if (get(bleedairapupos) == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Bleed Air On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                 helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Bleed Air Checked and On")    
        end
    end

    if (procedureloop1.stepindex == 8) then
        if (get(isolvalvepos)  ~= ISOLVALVEOPEN) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Isolation Valve Open")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEOPEN)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Isolation Valve Checked and Open")    
        end
    end

    if (procedureloop1.stepindex == 9) then
        if not setview(configvalues[CONFIGVIEWTHROTTLE]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 10) then
        if ((get(mixture1pos) ~= OFF) or (get(mixture2pos) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Engine Fuel Levers Cutoff")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if (get(mixture2pos) ~= OFF) then
                    helpers.command_once("laminar/B738/engine/mixture2_cutoff")
                end
                if (get(mixture1pos) ~= OFF) then
                    helpers.command_once("laminar/B738/engine/mixture1_cutoff")
                end
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Fuel Levers Checked and Cutoff")
        end
    end

    if (procedureloop1.stepindex == 11) then
        if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 12) then
        if ((get(centertanklswitch) == ON) or (get(centertankrswitch) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Center Tank Fuel Pumps Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(centertanklswitch, OFF)
                set(centertankrswitch, OFF)
            end      
        end
    end

    if (procedureloop1.stepindex == 13) then
        if ((get(lefttanklswitch) == ON) or (get(lefttankrswitch) == ON)  or (get(righttanklswitch) == ON) or (get(righttankrswitch) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Wing Tank Fuel Pumps Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(lefttanklswitch, OFF)
                set(leftttankrswitch, OFF)
                set(righttanklswitch, OFF)
                set(righttankrswitch, OFF)
            end
        end
    end

    if (procedureloop1.stepindex == 14) then
        if ((get(hydro1pos) ~= OFF) or (get(hydro2pos) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Both Hydraulic Pumps Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(hydro1pos, OFF)
                set(hydro2pos, OFF)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Hydraulic Pumps Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 15) then
        if ((get(elechydro1pos) ~= OFF) or (get(elechydro2pos) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Both Electrical Hydraulic Pumps Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(elechydro1pos, OFF)
                set(elechydro2pos, OFF)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Electrical Hydraulic Pumps Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 16) then
      if (get(beaconlights) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Collision Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                togglecollisionlights(OFF)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Collision lightset Checked and Off")
        end    
    end

    if (procedureloop1.stepindex == 17) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 18) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Engine Shutdown Procedure Complete")
        else
            helpers.command_once("laminar/B738/push_button/master_caution1")
            commandtableentry(TEXT, "Engine Shutdown Procedure Complete")
        end
    end

    return true

end

function turnaroundengineshutdown()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = TURNAROUNDENGINESHUTDOWNPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Engine Shutdown Not Possible Inflight")
        else
            commandtableentry(TEXT, "Engine Shutdown Not Possible Inflight")
        end
        return true
    end

    if not enginesrunning(BOTH) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Engine Start Aborted, Engines not running")
        else
            commandtableentry(TEXT, "Engine Start Aborted, Engines not running")
        end
        return true
    end

    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
        commandtableentry(ADVICE, "Turnaround Engine Shutdown Procedure")
    else
        commandtableentry(TEXT, "Turnaround Engine Shutdown Procedure")
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

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = FINALENGINESHUTDOWNPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Engine Shutdown Not Possible Inflight")
        return true
    end

    if not enginesrunning(BOTH) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Engine Shutdown Aborted, Engines not Running")
        return true
    end

    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
        commandtableentry(ADVICE, "Final Engine Shutdown Procedure")
    else
        commandtableentry(TEXT, "Final Engine Shutdown Procedure")
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

    if ((procedureloop1.stepindex > 25) or procedureabort) then
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVIEWCHANGES] == ON) then
            helpers.command_once("sim/view/default_view")
            if not setview(configvalues[CONFIGVIEWUPPEROVERHEADPANEL]) then
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        end
    end

    if (procedureloop1.stepindex == 2) then
        if ((get(irsleftpos) ~= IRSOFF) or (get(irsrightpos) ~= IRSOFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON)  then
                commandtableentry(ADVICE, "Set Both I R S Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if not setirs(BOTHIRS, IRSNAV) then 
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both I R S Checked and Off")
        end 
    end


    if (procedureloop1.stepindex == 3) then
        if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 4) then
        if (get(yawdamperswitch) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Yaw Damper Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(yawdamperswitch, OFF)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Yaw Damper Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 5) then
        if (get(bleedairapupos) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Bleed Air Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                 helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Bleed Air Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 6) then
        if (get(isolvalvepos)  ~= ISOLVALVEAUTO) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Isolation Valve Auto")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEAUTO)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Isolation Valve Checked and Auto")
        end 
    end

    if (procedureloop1.stepindex == 7) then
        if ((get(packlpos) ~= PACKOFF) or (get(packrpos) ~= PACKOFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Packs Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(packlpos, PACKOFF)
                set(packrpos, PACKOFF)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Packs Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 8) then
        if ((get(bleedair1pos) == ON) or (get(bleedair2pos) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Engine Bleed Air Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if (get(bleedair1pos) == ON) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(bleedair2pos) == ON) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Engine Bleed Air Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 9) then
        if (get(trimairpos) ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Trim Air Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(trimairpos, OFF) 
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Trim Air Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 10) then
        if ((get(wheatlfwdpos) ~= OFF) or (get(wheatrfwdpos) ~= OFF) or (get(wheatlsidepos) ~= OFF) or (get(wheatrsidepos) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglewindowheat(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Window Heat Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Window Heat Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 11) then
        if (configvalues[CONFIGUSEGROUNDPOWER] == ON) then
            if (get(gpuon) == ON) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Switch Ground Power Off")
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                else
                    helpers.command_once("laminar/B738/toggle_switch/gpu_up")
                    procedureloop1.stepindex = 13
                    return true
                end
            elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                commandtableentry(ADVICE, "Ground Power Checked and Off")
                procedureloop1.stepindex = 13
                return true
            end
        end
    end

    if (procedureloop1.stepindex == 12) then
        if (((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or ((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF))) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Generator Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    helpers.command_once("laminar/B738/toggle_switch/apu_gen1_up")
                end
                if ((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                    elpers.command_once("laminar/B738/toggle_switch/apu_gen2_up")
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Generator Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 13) then
        if (get(apustarterpos) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "A P U Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 14) then
        if (get(positionlights) ~= POSLIGHTSOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Position Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                togglepositionlights(POSLIGHTSOFF)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Position LIghts Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 15) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNOFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Seatbeltsigns Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Seatbeltsigns Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 16) then
        if (get(nosmokingsignpos) ~= NOSMOKINGSIGNOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setnosmokingsign(NOSMOKINGSIGNOFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set No Smoking Signs Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "NO Smoking Signs Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 17) then
        if (get(emergencylightcover) == CLOSED) then
            helpers.command_once("laminar/B738/button_switch_cover09")
        end
    end

    if (procedureloop1.stepindex == 18) then
        if (get(emergencylights) ~= EMERGLIGHTSOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Emergency Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                setemergencylights(EMERGLIGHTSOFF)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Emergency Lights Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 19) then
        if not setview(configvalues[CONFIGVIEWUPPEROVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 20) then
        if (get(domelightpos) ~= DOMELIGHTOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setdomelight(DOMELIGHTOFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Domelight OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Domelight Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 21) then
        if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 22) then
        if (get(batteryswitchcover) == CLOSED) then
            helpers.command_once("laminar/B738/button_switch_cover02")
        end
    end

    if (procedureloop1.stepindex == 23) then
        if (get(battery) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Battery OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                helpers.command_once("laminar/B738/switch/battery_up")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Battery Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 24) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 25) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Shutdown Procedure Complete")
        else
            commandtableentry(TEXT, "Shutdown Procedure Complete")
        end      
    end

    return true

end

function shutdown()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = SHUTDOWNPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = SHUTDOWNPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Shutdown Not Possible Inflight")
        else
            commandtableentry(TEXT, "Shutdown Not Possible Inflight")
        end
        return true
    end

    if ((get(battery) == OFF) and (get(mainbus) == OFF)) then
        procedureloop1.lock = SHUTDOWNPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Shutdown Aborted")
        else
            commandtableentry(TEXT, "Shutdown Aborted")
        end
        return true
    end

    if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
        commandtableentry(ADVICE, "Shutdown Procedure")
    else
        commandtableentry(TEXT, "Shutdown Procedure")
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
-- sasl.appendMenuItem(P.menu_main, "Shutdown", shutdown)

--------------------------------------------------------------------------------------------------------------
-- teststeps

function teststeps()

    if ((procedureloop1.stepindex > 48) or procedureabort) then
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVIEWCHANGES] == ON) then
            helpers.command_once("sim/view/default_view")
            if not setview(configvalues[CONFIGVIEWTHROTTLE]) then
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        end
    end

    if (procedureloop1.stepindex == 2) then
        helpers.command_begin("laminar/B738/toggle_switch/fire_test_lft")
    end

    if (procedureloop1.stepindex == 4) then
        helpers.command_end("laminar/B738/toggle_switch/fire_test_lft")
    end

    if (procedureloop1.stepindex == 5) then
        helpers.command_begin("laminar/B738/toggle_switch/fire_test_rgt")
    end

    if (procedureloop1.stepindex == 6) then
        helpers.command_end("laminar/B738/toggle_switch/fire_test_rgt")
    end

    if (procedureloop1.stepindex == 7) then
        helpers.command_begin("laminar/B738/toggle_switch/exting_test_lft")
    end

    if (procedureloop1.stepindex == 8) then
        helpers.command_end("laminar/B738/toggle_switch/exting_test_lft")
    end

    if (procedureloop1.stepindex == 9) then
        helpers.command_begin("laminar/B738/toggle_switch/exting_test_rgt")

    end

    if (procedureloop1.stepindex == 10) then
        helpers.command_end("laminar/B738/toggle_switch/exting_test_rgt")
    end

    if (procedureloop1.stepindex == 11) then
        helpers.command_begin("laminar/B738/push_button/cargo_fire_test_push")
    end

    if (procedureloop1.stepindex == 12) then
        helpers.command_end("laminar/B738/push_button/cargo_fire_test_push")
    end

    if (procedureloop1.stepindex == 13) then
        if not setview(configvalues[CONFIGVIEWUPPEROVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 14) then
        helpers.command_begin("laminar/B738/push_button/flaps_test")
    end

    if (procedureloop1.stepindex == 15) then
        helpers.command_end("laminar/B738/push_button/flaps_test")
    end

    if (procedureloop1.stepindex == 16) then
        helpers.command_begin("laminar/B738/push_button/mach_warn1_test")
    end

    if (procedureloop1.stepindex == 17) then
        helpers.command_end("laminar/B738/push_button/mach_warn1_test")
    end

    if (procedureloop1.stepindex == 18) then
        helpers.command_begin("laminar/B738/push_button/mach_warn2_test")
    end

    if (procedureloop1.stepindex == 19) then
        helpers.command_end("laminar/B738/push_button/mach_warn2_test")
    end

    if (procedureloop1.stepindex == 20) then
        helpers.command_begin("laminar/B738/push_button/stall_test1_press")
    end

    if (procedureloop1.stepindex == 21) then
        helpers.command_end("laminar/B738/push_button/stall_test1_press")
    end

    if (procedureloop1.stepindex == 22) then
        helpers.command_begin("laminar/B738/push_button/stall_test2_press")
    end

    if (procedureloop1.stepindex == 23) then
        helpers.command_end("laminar/B738/push_button/stall_test1_press")
    end

    if (procedureloop1.stepindex == 24) then
        if not setview(configvalues[CONFIGVIEWOVERHEADPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 25) then
        helpers.command_begin("laminar/B738/toggle_switch/window_ovht_test_up")
    end

    if (procedureloop1.stepindex == 26) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_up")
    end

    if (procedureloop1.stepindex == 27) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_up")
    end

    if (procedureloop1.stepindex == 28) then
        helpers.command_begin("laminar/B738/toggle_switch/window_ovht_test_dn")
    end

    if (procedureloop1.stepindex == 29) then
        helpers.command_end("laminar/B738/toggle_switch/window_ovht_test_dn")
    end

    if (procedureloop1.stepindex == 30) then
        helpers.command_begin("laminar/B738/push_button/tat_test")
    end

    if (procedureloop1.stepindex == 31) then
        helpers.command_end("laminar/B738/push_button/tat_test")
    end

    if (procedureloop1.stepindex == 32) then
        helpers.command_begin("laminar/B738/push_button/duct_ovht_test")
    end

    if (procedureloop1.stepindex == 33) then
        helpers.command_end("laminar/B738/push_button/duct_ovht_test")
    end

    if (procedureloop1.stepindex == 34) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 35) then
        helpers.command_once("laminar/B738/toggle_switch/bright_test_up")
    end

    if (procedureloop1.stepindex == 36) then
        helpers.command_once("laminar/B738/toggle_switch/bright_test_dn")
    end

    if (procedureloop1.stepindex == 37) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test1_up")
    end

    if (procedureloop1.stepindex == 38) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test1_up")
    end

    if (procedureloop1.stepindex == 39) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test1_dn")
    end

    if (procedureloop1.stepindex == 40) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test1_dn")
    end

    if (procedureloop1.stepindex == 41) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test2_up")
    end

    if (procedureloop1.stepindex == 42) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test2_up")
    end

    if (procedureloop1.stepindex == 43) then
        helpers.command_begin("laminar/B738/toggle_switch/ap_disconnect_test2_dn")
    end

    if (procedureloop1.stepindex == 44) then
        helpers.command_end("laminar/B738/toggle_switch/ap_disconnect_test2_dn")
    end

    if (procedureloop1.stepindex == 45) then
        if not setview(configvalues[CONFIGVIEWPEDESTAL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 46) then
        helpers.command_once("laminar/B738/knob/transponder_tcas_test")
    end

    if (procedureloop1.stepindex == 47) then
        if not setview(configvalues[CONFIGVIEWMAINPANEL]) then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 48) then
        commandtableentry(TEXT, "Test Complete")
    end

    return true

end

function test()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = TESTPROCEDURE
    end

    if ((get(battery) == OFF) and (get(mainbus) == OFF)) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Test Aborted Battery is Off")
        return true
    end

    commandtableentry(TEXT, "Test")

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
-- sasl.appendMenuItem(P.menu_main, "Tests", test)

--------------------------------------------------------------------------------------------------------------
-- cockpitinitsteps function

function cockpitinitsteps()

    if ((procedureloop1.stepindex > 24) or procedureabort) then
        procedureloop1.lock = NOPROCEDURE
        procedureabort = false
        procedureloop1.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cockpit Initialization")
        else
            commandtableentry(TEXT, "Cockpit Initialization")
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (get(domelightpos) == DOMELIGHTOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Dome Light On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                setdomelight(DOMELIGHTDIM)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Dome light Checked and On")
        end
    end

    if (procedureloop1.stepindex == 3) then
        if (configvalues[CONFIGHIDEEFBS] == ON) then
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
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "E F B S Hidden")
                else
                    commandtableentry(TEXT, "E F B S Hidden")
                end
            end
        end
    end

    if ((procedureloop1.stepindex == 4) and ((configvalues[CONFIGIGNOREALLBRIGHTHNESSSETTINGS] == OFF))) then
        
        if setcockpitlights() then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Instrument Lights set")
            else
                commandtableentry(TEXT, "Instrument Lights set")
            end
        end
    end

    if (procedureloop1.stepindex == 5) then
        if (configvalues[CONFIGLOWERDU] == ON) then
            local lowerduset = OFF
            if (get(lowerdupage) == 0) then
                lowerduset = ON
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
            else
                if (get(lowerdupage) == 1) then
                    lowerduset = ON
                    helpers.command_once("laminar/B738/LDU_control/push_button/MFD_ENG")
                end
            end

            if (get(lowerdupage2) ~= 1) then
                lowerduset = ON
                helpers.command_once("laminar/B738/LDU_control/push_button/MFD_SYS")
            end

            if (lowerduset == ON) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Lower Display Unit Pages Set")
                else
                    commandtableentry(TEXT, "Lower Display Unit Pages Set")
                end
                lowerduset = OFF
            end
        end
    end

    if (procedureloop1.stepindex == 6) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Reset F M C")
        else
            helpers.command_once("laminar/B738/button/reset_fmc")
            commandtableentry(TEXT, "F M C Reset Done")
        end
    end

    
    if (procedureloop1.stepindex == 7) then
        if (configvalues[CONFIGTRANSPONDER] ~= 0) then
            if (get(transpondercode) ~= configvalues[CONFIGTRANSPONDER]) then
                set(transpondercode, configvalues[CONFIGTRANSPONDER])
            end
        end
    end

    if (procedureloop1.stepindex == 8) then
        if ((get(captainprobepos) ~= OFF) or (get(foprobepos) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggleprobeheat(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Probe Heat OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Probe Heat Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 9) then
        setnosmokingsign(NOSMOKINGSIGNON)
    end

    if (procedureloop1.stepindex == 10) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNOFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Seatbelt Signs Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Seatbelt Signs Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 11) then
        if (get(nosmokingsignpos) ~= NOSMOKINGSIGNON) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setnosmokingsign(NOSMOKINGSIGNON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set No Smoking Signs On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "No Smoking Signs Checked and On")
        end
    end

    if (procedureloop1.stepindex == 12) then
        if ((get(llights1) ~= OFF) or (get(llights2) ~= OFF) or (get(llights3) ~= OFF) or (get(llights4) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Landing Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Landing Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 13) then
        if ((get(rwylightl) == ON) or (get(rwylightl) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglerwylights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Runway Turnoff Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Runway Turnoff Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 14) then
        if (get(taxilight)  ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Taxi Lights OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Taxi Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 15) then
        if (get(apdiscpos) == ON) then
            helpers.command_once("laminar/B738/autopilot/disconnect_toggle")
        end
    end

    if (procedureloop1.stepindex == 16) then
        if ((get(fdpilotpos) == ON) or (get(fdfopos) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglefds(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Flight Directors OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Flight Directors Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 17) then
        if (get(mcpaltitude) ~= lowerairspacealt) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(mcpaltitude, lowerairspacealt)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set M C P ALtitude " .. tostring(lowerairspacealt))
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "M C P ALtitude Checked and " .. tostring(lowerairspacealt))
        end
    end

    if (procedureloop1.stepindex == 18) then
        if (get(bankanglepos) ~= configvalues[CONFIGBANKANGLEMAX]) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setbankanglepos(configvalues[CONFIGBANKANGLEMAX])
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Bank Angle " .. getbankanglestring(configvalues[CONFIGBANKANGLEMAX]))
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Bank Angle Checked and " .. getbankanglestring(configvalues[CONFIGBANKANGLEMAX]))
        end
    end

    if (procedureloop1.stepindex == 19) then
        if (get(efisdatapilotpos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/capt/push_button/data_press")
        end
        if (get(efisdatafopos) == OFF) then
            helpers.command_once("laminar/B738/EFIS_control/fo/push_button/data_press")
        end
    end

    if (procedureloop1.stepindex == 20) then
        if (get(aponstat) == ON) then
            set(aponstat, OFF)
        end
    end

     if (procedureloop1.stepindex == 21) then
        if ((not enginesrunning(BOTH)) and ((get(mixture1pos) ~= OFF) or (get(mixture2pos) ~= OFF))) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Engine Fuel Levers Cutoff")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                if (get(mixture2pos) ~= OFF) then
                    helpers.command_once("laminar/B738/engine/mixture2_cutoff")
                end
                if (get(mixture1pos) ~= OFF) then
                    helpers.command_once("laminar/B738/engine/mixture1_cutoff")
                end
            end
        end
    end

    if (procedureloop1.stepindex == 22) then
        speedbrakeleverrounded = roundnumber(get(speedbrakelever), 1)
        if (speedbrakeleverrounded ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(speedbrakelever, OFF)
            elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                commandtableentry(ADVICE, "Retract Speed Brakes")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end 
        end
    end

    if (procedureloop1.stepindex == 23) then
        helpers.command_once("laminar/B738/push_button/master_caution1")
        helpers.command_once("laminar/B738/button/fmc1_clr")
    end

    if (procedureloop1.stepindex == 24) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cockpit Initialization Complete")
        else
            commandtableentry(TEXT, "Cockpit Initialization Complete")
        end
    end

    return true

end

function cockpitinit()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = COCKPITINITPROCEDURE
    end

    if ((get(battery) == OFF) and (get(mainbus) == OFF)) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cockpit Initialization Aborted, Cockpit is Cold and Dark")
        else
            commandtableentry(TEXT, "Cockpit Initialization Aborted, Cockpit is Cold and Dark")
        end
        return true
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cockpit Initialization Not Possible Inflight")
        else
            commandtableentry(TEXT, "Cockpit Initialization Not Possible Inflight")
        end
        return true
    end

    if (get(parkingbrakepos) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Cockpit Initialization Not Possible, Parking brake must be set")
        else
            commandtableentry(TEXT, "Cockpit Initialization Not Possible, Parking brake must be set")
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
-- sasl.appendMenuItem(P.menu_main, "Cockpit Initialization", cockpitinitsteps)

--------------------------------------------------------------------------------------------------------------
-- aftertakeoffsteps function

function aftertakeoffsteps()

    if ((procedureloop2.stepindex > 3) or procedureabort) then
        aftertakeoffset = true
        procedureloop2.lock = NOPROCEDURE
        procedureabort = false
        procedureloop2.stepindex = 1
        return true
    end
 
    if (procedureloop2.stepindex == 1) then
        if (get(radioaltitude) > 200) then
            if (get(gearhandlepos) == GEARDOWN) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Gear Up")
                    procedureloop2.stepindex = procedureloop2.stepindex - 1
                else
                    set(gearhandlepos, GEARUP)
                    set(nosewheel, OFF)
                end
            elseif ((get(gearhandlepos) == GEARDOWN) and (configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Gear Checked and Up")
            end  
        else
            procedureloop2.stepindex = procedureloop2.stepindex - 1
        end
    end

    if (procedureloop2.stepindex == 2) then
        if ((get(gearhandlepos) == GEARUP) and (get(lgeardeployed) == 0) and (get(ngeardeployed) == 0) and (get(rgeardeployed) == 0)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Gear Lever Off")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            else
                set(gearhandlepos, GEAROFF)
            end
        elseif ((get(gearhandlepos) == GEAROFF) and (configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Gear Lever Checked and Off")
        elseif (get(gearhandlepos) ~= GEAROFF) then
            procedureloop2.stepindex = procedureloop2.stepindex - 1
        end
    end

    if (procedureloop2.stepindex == 3) then
        if (get(autobrakepos) ~= AUTOBRAKEOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Auto Brake Off")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            else
                setautobrake(AUTOBRAKEOFF)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
            commandtableentry(ADVICE, "Auto Brake Checked and Off")
        end  
    end

    return false
end

--------------------------------------------------------------------------------------------------------------
-- altituedea10000steps function

function altitudea10000steps()

    if ((procedureloop1.stepindex > 5) or procedureabort) then
        altitudea10000set = true
        procedureloop1.lock = NOPROCEDURE
        procedureloop2.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (get(altitude) < (lowerairspacealt + 1000)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Passing " .. lowerairspacealt .. " Feet")
            else
                commandtableentry(TEXT, "Passing " .. lowerairspacealt .. " Feet")
            end
        end
    end

    if (procedureloop1.stepindex == 2) then
        if ((get(llights1) ~= OFF) or (get(llights2) ~= OFF) or (get(llights3) ~= OFF) or (get(llights4) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Landing Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Landing Lights Checked and Off")
        end  
    end

    if (procedureloop1.stepindex == 3) then
        if (get(logolighton) ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelogolight(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Logo Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Logo Lights Checked and Off")
        end 
    end

    if (procedureloop1.stepindex == 4) then
        if ((get(starter1pos)  ~= AUTO) or (get(starter2pos)  ~= AUTO)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setstarter(BOTH, AUTO)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                if (get(starterauto) == ON) then
                    commandtableentry(ADVICE, "Set Both Starters Auto")
                else
                    commandtableentry(ADVICE, "Set Both Starters Off")
                end
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end   
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            if (get(starterauto) == ON) then
                    commandtableentry(ADVICE, "Both Starters Checked and Auto")
            else
                    commandtableentry(ADVICE, "Both Starters Checked and Off")
            end
        end 
    end

    if (procedureloop1.stepindex == 5) then     
        if (get(seatbeltsignpos) ~= SEATBELTSIGNOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNOFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Seatbeltsigns Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Seatbelt Signs Checked and Off")
        end
    end

    return false

end

function altitudea10000()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = ALTITUDEA10000PROCEDURE
    end

    if (get(airgroundsensor) == ON) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Above 10000 Procedure not possible on Ground")
        return true
    end

    if altitudea10000set then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Above 10000 Procedure already done")
        return true
    end

    if (get(altitude) < lowerairspacealt) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Above 10000 Procedure only possible above lower Airspace Altitude")
        return true
    end

    if (flightstate > 2) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Above 10000 Procedure only possible during Climb")
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
-- sasl.appendMenuItem(P.menu_main, "Above 10000", altitudea10000)

--------------------------------------------------------------------------------------------------------------
-- duringclimbsteps function

function duringclimbsteps()

    if ((procedureloop2.stepindex > 13) or procedureabort) then
        duringclimbset = true
       procedureloop2.lock = NOPROCEDURE
        procedureloop2.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop2.stepindex == 1) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            setdomelight(DOMELIGHTOFF)
        end
    end

    if (procedureloop2.stepindex == 2) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            if (get(altitude) < lowerairspacealt) then
                togglelandinglights(ON)
            end
        end
    end

    if (procedureloop2.stepindex == 3) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            togglepositionlights(POSLIGHTSSTROBE)
        end
    end

    if (procedureloop2.stepindex == 4) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            togglerwylights(OFF)
        end
    end

    if (procedureloop2.stepindex == 5) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            toggletaxilights(OFF)
        end
    end

    if (procedureloop2.stepindex == 6) then
        if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
            if (configvalues[CONFIGTRANSPONDER] ~= 0) then
                toggletransponder(TARA)
            end
        end
    end

    if (procedureloop2.stepindex == 7) then
        if (get(altitude) > get(fmctransalt)) then
            if (get(barostd) == OFF) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Passing Transition Altitude")
                else
                    commandtableentry(TEXT, "Passing Transition Altitude")
                end
            end
        else
            procedureloop2.stepindex = procedureloop2.stepindex - 1
        end
    end

    if (procedureloop2.stepindex == 8) then
        if (configvalues[CONFIGAUTOBARO] == ON) then
            if (get(altitude) > get(fmctransalt)) then 
                if (get(barostd) == OFF) then
                    if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                        helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
                    elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        commandtableentry(ADVICE, "Set Q N H to Standard")
                        procedureloop2.stepindex = procedureloop2.stepindex - 1
                    end
                elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                    commandtableentry(ADVICE, "Q N H Checked and Standard")
                end
            else
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            end
        end
    end

    if (procedureloop2.stepindex == 9) then
        if ((get(bleedair1pos) == OFF) or (get(bleedair2pos) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Engine Bleed Air On")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            else
                if (get(bleedair1pos) == OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_1")
                end
                if (get(bleedair2pos) == OFF) then
                    helpers.command_once("laminar/B738/toggle_switch/bleed_air_2")
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
            commandtableentry(ADVICE, "Both Engine Bleed Air Checked and On")
        end 
    end

    if (procedureloop2.stepindex == 10) then
        if ((get(packlpos) == PACKOFF) or (get(packrpos) == PACKOFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Packs Auto")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            else
                set(packlpos, PACKAUTO)
                set(packrpos, PACKAUTO)
            end      
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
            commandtableentry(ADVICE, "Both Packs Checked and On")
        end  
    end

    if (procedureloop2.stepindex == 11) then
        if (get(isolvalvepos)  == ISOLVALVEOPEN) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Isolation Valve Auto")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            else
                set(isolvalvepos, ISOLVALVEAUTO)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
            commandtableentry(ADVICE, "Isolation Valve Checked and Auto")
        end  
    end


    if (procedureloop2.stepindex == 12) then
        if (get(bleedairapupos) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Bleed Air Off")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            else
             helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
            commandtableentry(ADVICE, "A P U Bleed Air Checked and Off")
        end  
    end

    if (procedureloop2.stepindex == 13) then
        if (get(apustarterpos) == ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch A P U Off")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            else
                helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up")
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
            commandtableentry(ADVICE, "A P U Checked and Off")
        end  
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- duringclimb function

function duringclimb()

    if ((not duringclimbset) and (procedureloop2.lock == NOPROCEDURE)) then
       procedureloop2.lock = DURINGCLIMBPROCEDURE
    end

    if ((get(altitude) >= lowerairspacealt) and (not altitudea10000set) and (procedureloop1.lock == NOPROCEDURE)) then
        procedureloop1.lock = ALTITUDEA10000PROCEDURE
    end

    if ((configvalues[CONFIGAUTOFLAPS] == ON) and (get(flapleverpos) > FLAPSUP)) then
        flapsuphandling()
    end

end

--------------------------------------------------------------------------------------------------------------
-- altitudeb10000steps function

function altitudeb10000steps()

    if ((procedureloop1.stepindex > 7) or procedureabort) then
        altitudeb10000set = true
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Below " .. lowerairspacealt .. " Feet")
        else
            commandtableentry(TEXT, "Below " .. lowerairspacealt .. " Feet")
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNON) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Seatbeltsigns On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Seatbeltsigns Checked and On")
        end  
    end

    if (procedureloop1.stepindex == 3) then
        if ((get(llights1) == OFF) or (get(llights2) == OFF) or (get(llights3) == OFF) or (get(llights4) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Landing Lights On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Landing Lights Checked and On")
        end  
    end

    if (procedureloop1.stepindex == 4) then
        if (get(logolighton) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelogolight(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Logo Lights On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Logo Lights Checked and On")
        end  
    end

    if (procedureloop1.stepindex == 5) then
        if not setilssteps() then
            procedureloop1.stepindex = procedureloop1.stepindex - 1
        end
    end

    if (procedureloop1.stepindex == 6) then
        if (configvalues[CONFIGVREF30SET] == ON) then
           local appflapscalc, appvrefcalc = calcappflapsvref(desmetar.decodedmetar)
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                if not setvref(appflapscalc, appvrefcalc) then
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                end
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                if (get(vref) ~= appvrefcalc) then
                    commandtableentry(ADVICE, "Set V REF " .. appflapscalc .. " " .. appvrefcalc)
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                    commandtableentry(ADVICE, "V REF " .. appflapscalc .. " Checked and " .. appvrefcalc)
                end
            end
        end
    end

    if (procedureloop1.stepindex == 7) then
        if (configvalues[CONFIGVREF30SET] == ON) then
            local autobrake = calcautobrake(get(vref), desmetar.decodedmetar)
            sasl.logDebug("AUTOBRAKE AUTOBRAKEPOS: " .. tostring(get(autobrakepos)) .. " AUTOBRAKE " .. tostring(autobrake))
            if (get(autobrakepos) ~= autobrake) then
                if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    setautobrake(autobrake)
                elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    if (autobrake < AUTOBRAKEMAX) then
                        commandtableentry(ADVICE, "Set Auto Brake " .. tostring(autobrake - 1))
                    else
                        commandtableentry(ADVICE, "Set Auto Brake Maximum")
                    end
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                end
            elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                if (autobrake < AUTOBRAKEMAX) then
                    commandtableentry(ADVICE, "Auto Brake Checked and " .. tostring(autobrake - 1))
                else
                    commandtableentry(ADVICE, "Auto Brake Checked and Maximum")
                end
            end
        end
    end

    return true

end

function altitudeb10000()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = ALTITUDEB10000PROCEDURE
    end

    if (get(airgroundsensor) == ON) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Below 10000 Procedure not possible on Ground")
        return true
    end

    if altitudeb10000set then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Below 10000 Procedure already done")
        return true
    end

    if (get(altitude) > lowerairspacealt) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Below 10000 Procedure only possible below lower Airspace Altitude")
        return true
    end

    if (flightstate <= 2) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Altitude below 10000 Procedure only possible during Descent")
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

    if ((procedureloop2.stepindex > 2) or procedureabort) then
        radioaltitude2500set = true
       procedureloop2.lock = NOPROCEDURE
        procedureloop2.stepindex = 1
        procedureabort = false
        return true
    end

    if (procedureloop2.stepindex == 1) then
        if ((convflaplevertoflappos(get(flapleverpos)) >= configvalues[CONFIGGEARDOWNFLAPS]) and (get(gearhandlepos) < GEARDOWN)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(gearhandlepos, GEARDOWN)
                set(nosewheel, OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Gear Down")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            end
        elseif (get(gearhandlepos) == GEARDOWN) then
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Gear Checked and Down")
            end
        end
    end

    if (procedureloop2.stepindex == 2) then
        if ((get(starter1pos)  ~= CONT) or (get(starter2pos)  ~= CONT)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setstarter(BOTH, CONT)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Starters Continuous")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            end
        else
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Both Starters Checked and Continuous")
            end
        end
    end

    return false

end

--------------------------------------------------------------------------------------------------------------
-- radioaltitudeb1000steps function

function radioaltitudeb1000steps()

    if ((procedureloop2.stepindex > 7) or prodedureabort) then
        radioaltitude1000set = true
        procedureabort = false
       procedureloop2.lock = NOPROCEDURE
        procedureloop2.stepindex = 1
        return true
    end

    if (procedureloop2.stepindex == 1) then
        speedbrakeleverrounded = roundnumber(get(speedbrakelever), 1)
        if (speedbrakeleverrounded == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(speedbrakelever, 0.1)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Arm Speed Brakes")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            end
        else
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Speedbrakes Checked and Armed")
            end
        end
    end

    if (procedureloop2.stepindex == 2) then
        if (get(taxilight) == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Taxi Lights On")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            end
        else
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Taxi Lights Checked and On")
            end
        end
    end

    if (procedureloop2.stepindex == 3) then
        if ((get(rwylightl) == OFF) or (get(rwylightl) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglerwylights(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Runway Turnoff Lights On")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            end
        else
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Runway Turnoff Lights Checked and On")
            end
        end
    end

    if (procedureloop2.stepindex == 4) then
        if (get(missedappalt) ~= 0) then
            missedappalttmp = roundnumber((get(missedappalt) / 100) * 100)
            if (missedappalttmp ~= get(mcpaltitude)) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set M C P Altitude " .. addspaces(missedappalttmp))
                    procedureloop2.stepindex = procedureloop2.stepindex - 1
                else
                    set(mcpaltitude,  missedappalttmp)
                end
            else
                if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                    commandtableentry(ADVICE, "MCP Altitude Checked and " .. addspaces(missedappalttmp))
                end
            end
        else
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Missed Approach Altitude")
            else
                commandtableentry(TEXT, "Set Missed Approach Altitude")
            end
        end
    end

    if (procedureloop2.stepindex == 5) then
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
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set M C P Heading " .. addspaces(padNumberWithZerosStrict(headingrounded, 3)))
                    procedureloop2.stepindex = procedureloop2.stepindex - 1
                else
                    set(mcpheading, headingrounded)
                end
            else
                if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                    commandtableentry(ADVICE, "MCP Heading Checked and " .. addspaces(padNumberWithZerosStrict(headingrounded, 3)))
                end
            end
        elseif not headingrounded then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Missed Approach Heading")
            else
                commandtableentry(TEXT, "Set Missed Approach Heading")
            end
        end
    end

    if (procedureloop2.stepindex == 6) then
        if (get(gearhandlepos) < GEARDOWN) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(gearhandlepos, GEARDOWN)
                set(nosewheel, OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Gear Down")
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            end
        else
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Gear Checked and Down")
            end
        end
    end

    if (procedureloop2.stepindex == 7) then
        if (((get(appflapsset) == OFF) and get(appflaps) ~= 0)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then            
                helpers.command_once("laminar/B738/push_button/flaps_" .. tostring(get(appflaps)))
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Flaps " .. tostring(get(appflaps)))
                procedureloop2.stepindex = procedureloop2.stepindex - 1 
            end
        else
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Flaps Checked and " .. tostring(get(appflaps)))
            end
        end
    end

    return false

end

--------------------------------------------------------------------------------------------------------------
-- duringdescentsteps function

function duringdescentsteps()

    if ((procedureloop2.stepindex > 4) or procedureabort) then
        duringdescentset = true
        procedureabort = false
       procedureloop2.lock = NOPROCEDURE
        procedureloop2.stepindex = 1
        return true
    end

    
    if (procedureloop2.stepindex == 1) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Descent Started")
        else
            commandtableentry(TEXT, "Descent Started")  
        end
    end

    if (procedureloop2.stepindex == 2) then
        if (configvalues[CONFIGSPDRESTR250] == ON) then
            if (get(speedrestr) ~= 250) then
                if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Speed below 10000 Feet to 250")
                    procedureloop2.stepindex = procedureloop2.stepindex - 1
                else
                    set(speedrestr, 250)
                    commandtableentry(TEXT, "Speed 250 below 10000 set")
                end
            elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                commandtableentry(ADVICE, "Speed 250 below 10000 Feet checked and set")
            end
        end
    end

    if (procedureloop2.stepindex == 3) then
        if (get(altitude) < get(fmctranslvl)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Passing Transition Level")
            else
                commandtableentry(TEXT, "Passing Transition Level")
            end
        else
            procedureloop2.stepindex = procedureloop2.stepindex - 1
        end
    end

    if (procedureloop2.stepindex == 4) then
        if (configvalues[CONFIGAUTOBARO] == ON) then
            if (get(altitude) < get(fmctranslvl)) then
                local baroinchtmp, baropastmp = getlocalqnh(ARRIVAL)
                sasl.logDebug("QNHARRIVAL: BAROPILOT "..tostring(roundnumber(get(baropilot), 2)) .. " BAROINCHTMP " .. baroinchtmp .. " " .. tostring(roundnumber(math.abs(roundnumber(get(baropilot), 2) - baroinchtmp), 2)))
                if ((get(barostd) == ON) or (roundnumber(math.abs(roundnumber(get(baropilot), 2) - baroinchtmp), 2) > 0.01)) then
                    if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                        helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
                        set(baropilot, baroinchtmp)
                    elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        if (get(baroinhpa) == ON) then
                            commandtableentry(ADVICE, "Set Q N H " .. addspaces(baropastmp))
                        else
                            commandtableentry(ADVICE, "Set Q N H " .. addspaces(baroinchtmp))
                        end
                        procedureloop2.stepindex = procedureloop2.stepindex - 1
                    end
                elseif ((get(barostd) == OFF) and (roundnumber(math.abs(roundnumber(get(baropilot), 2) - baroinchtmp), 2) <= 0.01)) then
                    if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop2.steprepeat) then
                        if (get(baroinhpa) == ON) then
                            commandtableentry(ADVICE, "Q N H Checked and " .. addspaces(baropastmp))
                        else
                            commandtableentry(ADVICE, "Q N H Checked and " .. addspaces(baroinchtmp))
                        end
                    end
                end
            else
                procedureloop2.stepindex = procedureloop2.stepindex - 1
            end
        end
    end

    return false

end

--------------------------------------------------------------------------------------------------------------
-- duringdescent function

function duringdescent()

    if ((not duringdescentset) and (procedureloop2.lock == NOPROCEDURE)) then
       procedureloop2.lock = DURINGDESCENTPROCEDURE
    end

    if ((get(altitude) < lowerairspacealt) and (not altitudeb10000set) and (procedureloop1.lock == NOPROCEDURE)) then
        procedureloop1.lock = ALTITUDEB10000PROCEDURE
    end

    if ((get(radioaltitude) < 2500) and (not radioaltitude2500set) and (procedureloop2.lock == NOPROCEDURE)) then
       procedureloop2.lock = RADIOALTITUDEB2500PROCEDURE
    end

    if ((get(radioaltitude) < 1000) and (not radioaltitude1000set)  and (procedureloop2.lock == NOPROCEDURE)) then
       procedureloop2.lock = RADIOALTITUDEB1000PROCEDURE
    end

    if (configvalues[CONFIGAUTOFLAPS] == ON) then
        flapsdownhandling()
    end
end

--------------------------------------------------------------------------------------------------------------
-- afterlandingsteps function

function afterlandingsteps()

    if ((procedureloop1.stepindex > 18) or procedureabort) then
        afterlandingset = true
        procedureabort = false
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        return true
    end

    if (procedureloop1.stepindex == 1) then
       if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "After Landing Procedure")
        else
            commandtableentry(TEXT, "After Landing Procedure")
        end
    end

    if (procedureloop1.stepindex == 2) then
       if ((get(llights1) ~= OFF) or (get(llights2) ~= OFF) or (get(llights3) ~= OFF) or (get(llights4) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Landing Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Landing Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 3) then
        if (get(taxilight) == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Taxi Lights On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Taxi Lights Checked and On")
        end
    end

    if (procedureloop1.stepindex == 4) then
        if ((get(rwylightl) == ON) or (get(rwylightl) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglerwylights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Runway Turnoff Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Runway Turnoff Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 5) then
        if(get(positionlights) ~= POSLIGHTSSTEADY) then 
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglepositionlights(POSLIGHTSSTEADY)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Position Lights Steady")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Position Lights Checked and Steady")
        end
    end

    if (procedureloop1.stepindex == 6) then
        if (get(transponderpos) == TARA) then
            if (configvalues[CONFIGTRANSPONDER] ~= 0) then
                if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    toggletransponder(STANDBY)
                elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Transponder Off")
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Transponder Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 7) then
        if (get(aponstat) == ON) then
            set(aponstat, OFF)
        end
    end

    if (procedureloop1.stepindex == 8) then
        iceprotection(OFF)
    end

    if (procedureloop1.stepindex == 9) then
        if ((get(starter1pos)  ~= AUTO) or (get(starter2pos)  ~= AUTO)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setstarter(BOTH, AUTO)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                if (get(starterauto) == ON) then
                    commandtableentry(ADVICE, "Set Both Starters Auto")
                else
                    commandtableentry(ADVICE, "Set Both Starters Off")
                end
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end   
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            if (get(starterauto) == ON) then
                commandtableentry(ADVICE, "Both Starters Checked and Auto")
            else
                commandtableentry(ADVICE, "Both Starters Checked and Off")
            end
        end
    end

    if (procedureloop1.stepindex == 10) then
        if ((get(fdpilotpos) == ON) or (get(fdfopos) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglefds(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Flight Directors OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Flight Directors Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 11) then
         if ((get(efiswxpilotpos) == ON) or (get(efiswxfopos) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglewx(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Weather Radars OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Weather Radars Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 12) then
         if ((get(efisterrpilotpos) == ON) or (get(efisterrfopos) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggleterr(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Terrain Radars OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Terrain Radars Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 13) then
        if (get(flapleverpos) > FLAPSUP) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                helpers.command_once("laminar/B738/push_button/flaps_0")
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Flaps Up")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end        
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Flaps Checked and Up")
        end
    end

    if (procedureloop1.stepindex == 14) then
        speedbrakeleverrounded = roundnumber(get(speedbrakelever), 1)
        if (speedbrakeleverrounded ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                set(speedbrakelever, OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Retract Speed Brakes")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end 
        else
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                commandtableentry(ADVICE, "Speedbrakes Up and Retracted")
            end
        end
    end

    if (procedureloop1.stepindex == 15) then
        if ((get(captainprobepos) ~= OFF) or (get(foprobepos) ~= OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggleprobeheat(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Probe Heat Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Probe Heat Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 16) then
        if (get(autobrakepos) ~= AUTOBRAKEOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setautobrake(AUTOBRAKEOFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Auto Brake Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Auto Brake Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 17) then
        helpers.command_once("laminar/B738/push_button/master_caution1")
    end

    if (procedureloop1.stepindex == 18) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "After Landing Procedure Complete")
        else
            commandtableentry(TEXT, "After Landing Procedure Complete")
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- afterlanding function

function afterlanding()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = AFTERLANDINGPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "After Landing Procedure Not Possible Inflight")
        return true
    end

    if afterlandingset then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "After Landing Procedure already done")
        return true
    end

    if (flightstate < 4)
    then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "After Landing Procedure only possible after Landing")
        return true
    end

    flightstate = 5

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

    if ((procedureloop1.stepindex > 18) or procedureabort) then
        beforetaxiset = true
        procedureabort = false
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Before Taxi Procedure")
        else
            commandtableentry(TEXT, "Before Taxi Procedure")
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (get(chockstatus) ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                helpers.command_once("laminar/B738/toggle_switch/chock")
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Remove Chocks")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Chocks Checked and Removed")
        end
    end

    if (procedureloop1.stepindex == 3) then
        if (get(beaconlights) == OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Collision Lights On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                togglecollisionlights(ON)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Collision Lights Checked and On")
        end  
    end

     if (procedureloop1.stepindex == 4) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNON) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Seatbeltsigns On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Seatbeltsigns Checked and On")
        end
    end

   if (procedureloop1.stepindex == 5) then
        if (get(logolighton) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelogolight(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Logo Lights On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Logo Lights Checked and On")
        end
    end

    if (procedureloop1.stepindex == 6) then
        if ((get(wheatlfwdpos) == OFF) or (get(wheatrfwdpos) == OFF) or (get(wheatlsidepos) == OFF) or (get(wheatrsidepos) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglewindowheat(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Window Heat On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON)  and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Window Heat Checked and On")
        end
    end

    if (procedureloop1.stepindex == 7) then
        if ((get(captainprobepos) == OFF) or (get(foprobepos) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggleprobeheat(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Probe Heat On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Probe Heat Checked and On")
        end
    end

    if (procedureloop1.stepindex == 8) then
        if ((get(starter1pos)  ~= CONT) or (get(starter2pos)  ~= CONT)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setstarter(BOTH, CONT)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Starters Continuous")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end 
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Both Starters Checked and Continuous")
        end
    end

    if (procedureloop1.stepindex == 9) then
        if ((get(fdpilotpos) == OFF) or (get(fdfopos) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglefds(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Both Flight Directors On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Flight Directors Checked and On")
        end
    end

    if (procedureloop1.stepindex == 10) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(fmccg) == 0) then
                commandtableentry(ADVICE, "Set C G")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            elseif not procedureloop1.steprepeat then
                commandtableentry(ADVICE, "C G Checked and Set")
            end
        end
    end

    if (procedureloop1.stepindex == 11) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if ((get(v1setspeed) == 0) or (get(v2setspeed) == 0) or (get(vrsetspeed) == 0)) then
                commandtableentry(ADVICE, "Set V Speeds")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            elseif not procedureloop1.steprepeat then
                commandtableentry(ADVICE, "V Speeds Checked and Set")
            end
        end
    end

    if (procedureloop1.stepindex == 12) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(aplnavstat) ~= ON) then
                commandtableentry(ADVICE, "Arm L NAV")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            elseif not procedureloop1.steprepeat then
                commandtableentry(ADVICE, "L NAV Checked and ARMED")
            end
        end
    end

    if (procedureloop1.stepindex == 13) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(apvnavstat) ~= ON) then
                commandtableentry(ADVICE, "Arm V NAV")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            elseif not procedureloop1.steprepeat then
                commandtableentry(ADVICE, "V NAV checked and ARMED")
            end
        end
    end

    if (procedureloop1.stepindex == 14) then
        if ((get(toflaps) > 0) and (get(toflapsset) == OFF)) then  
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toflapscmd = "laminar/B738/push_button/flaps_" .. tostring(get(toflaps))
                helpers.command_once(toflapscmd)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                toflapscmd = "Set Flaps " .. tostring(get(toflaps))
                commandtableentry(ADVICE, toflapscmd)
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif (get(toflaps) > 0) then
            if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                commandtableentry(ADVICE, "Takeoff Flaps Checked and Set")
            end
        end
    end

    if (procedureloop1.stepindex == 15) then
        if (get(yawdamperswitch) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Yaw Damper On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(yawdamperswitch, ON)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
                commandtableentry(ADVICE, "Yaw Damper Checked and On") 
        end
    end

    if (procedureloop1.stepindex == 16) then
        if ((get(hydro1pos) ~= ON) or (get(hydro2pos) ~= ON) or (get(elechydro1pos) ~= ON) or (get(elechydro2pos) ~= ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Switch Hydraulic Pumps On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            else
                set(hydro1pos, ON)
                set(hydro2pos, ON)
                set(elechydro1pos, ON)
                set(elechydro2pos, ON)
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Hydraulic Pumps Checked and On") 
        end
    end

    if (procedureloop1.stepindex == 17) then
        if (get(domelightpos) ~= DOMELIGHTOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setdomelight(DOMELIGHTOFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Domelight OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Domelight Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 18) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Before Taxi Procedure Complete")
        else
            commandtableentry(TEXT, "Before Taxi Procedure Complete")
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- beforetaxi function

function beforetaxi()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = BEFORETAXIPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Before Taxi Procedure Not Possible Inflight")
        return true
    end

    if not enginesrunning(BOTH) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Before Taxi Procedure Aborted, Engines not running")
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

    if ((procedureloop1.stepindex > 12) or procedureabort) then
        beforetakeoffset = true
        procedureabort = false
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Before Takeoff Procedure")
        else
            commandtableentry(TEXT, "Before Takeoff Procedure")
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (get(transponderpos) ~= TARA) then
            if (configvalues[CONFIGTRANSPONDER] ~= 0) then
                if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    toggletransponder(TARA)
                elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Transponder T A R A")
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Transponder Checked and T A R A")
        end
    end

    if (procedureloop1.stepindex == 3) then
        if(get(positionlights) ~= POSLIGHTSSTROBE) then 
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglepositionlights(POSLIGHTSSTROBE)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Position Lights Strobe")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Position Lights Checked and Strobe")
        end
    end

    if (procedureloop1.stepindex == 4) then
        if ((get(llights1) == OFF) or (get(llights2) == OFF) or (get(llights3) == OFF) or (get(llights4) == OFF)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelandinglights(ON)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Landing Lights On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Landing Lights Checked and On")
        end
    end

    if (procedureloop1.stepindex == 5) then
        if (get(taxilight)  ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Taxi Lights OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Taxi Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 6) then
        if ((get(rwylightl) == ON) or (get(rwylightl) == ON)) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglerwylights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == OFF) then
                commandtableentry(ADVICE, "Set Runway Turnoff Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Runway Turnoff Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 7) then
        if (get(autobrakepos)  ~= AUTOBRAKERTO) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setautobrake(AUTOBRAKERTO)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Auto Brake R T O")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Auto Brake Checked and R T O")
        end
    end

    if (procedureloop1.stepindex == 8) then
        local headingrounded = nil
        if (isvalidicao(get(depicao)) and isvalidrwy(get(deprwy)) and tonumber(get(deprwyheading))) then
            headingrounded = roundnumber(get(deprwyheading))
        end
        local navrwyheading = getrwyheadingfromnavdata(get(depicao), get(deprwy))
        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
            headingrounded = navrwyheading
        end
        if headingrounded then
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                if (get(mcpheading) ~= headingrounded) then
                    commandtableentry(ADVICE, "Set M C P Heading" .. addspaces(padNumberWithZerosStrict(headingrounded, 3)))
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                elseif not procedureloop1.steprepeat then
                    commandtableentry(ADVICE, "M C P Heading Checked" .. addspaces(padNumberWithZerosStrict(headingrounded, 3)))
                end
            end
        end
    end

    if (procedureloop1.stepindex == 9) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(aplnavstat) ~= ON) then
                commandtableentry(ADVICE, "Arm L NAV")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            elseif not procedureloop1.steprepeat then
                commandtableentry(ADVICE, "L NAV Checked and ARMED")
            end
        end
    end

    if (procedureloop1.stepindex == 10) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(apvnavstat) ~= ON) then
                commandtableentry(ADVICE, "Arm VNAV")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            elseif not procedureloop1.steprepeat then
                commandtableentry(ADVICE, "V NAV Checked and ARMED")
            end
        end
    end

    if (procedureloop1.stepindex == 11) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            if (get(atarmpos) ~= ON) then
                commandtableentry(ADVICE, "Arm Autothrottle")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            elseif not procedureloop1.steprepeat then
                commandtableentry(ADVICE, "Autothrottle Checked and Armed")
            end
        end
    end

    if (procedureloop1.stepindex == 12) then
         if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Before Takeoff Procedure Complete")
        else
            commandtableentry(TEXT, "Before Takeoff Procedure Complete")
        end
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- beforetakeoff() function

function beforetakeoff()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        return true
    else
        procedureloop1.lock = BEFORETAKEOFFPROCEDURE
    end

    if (get(airgroundsensor) == OFF) then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Before Takeoff Procedure Not Possible Inflight")
        return true
    end

    if not beforetaxiset then
        procedureloop1.lock = NOPROCEDURE
        commandtableentry(TEXT, "Before Takeoff Procedure Not Possible, before Taxi Procedure")
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
-- sasl.appendMenuItem(P.menu_main, "Before Takeoff Procedure", beforetakeoff)


--------------------------------------------------------------------------------------------------------------
-- atparkingpositionsteps function

function atparkingpositionsteps()

    if ((procedureloop1.stepindex > 8) or procedureabort) then
        atparkingpositionset = true
        procedureabort = false
        procedureloop1.lock = NOPROCEDURE
        procedureloop1.stepindex = 1
        return true
    end

    if (procedureloop1.stepindex == 1) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "At Parking Position")
        else
            commandtableentry(TEXT, "At Parking Position")
        end
    end

    if (procedureloop1.stepindex == 2) then
        if (get(taxilight)  ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                toggletaxilights(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Taxi Lights OFF")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Taxi Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 3) then
        if (get(chockstatus) ~= ON) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                helpers.command_once("laminar/B738/toggle_switch/chock")
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Chocks")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Chocks Checked and Set")
        end
    end


    if (procedureloop1.stepindex == 4) then
        if (get(domelightpos) == DOMELIGHTOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setdomelight(DOMELIGHTDIM)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Domelight On")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        end
    end

    if (procedureloop1.stepindex == 5) then
        if (get(transponderpos) ~= STANDBY) then
            if (configvalues[CONFIGTRANSPONDER] ~= 0) then
                if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                    toggletransponder(STANDBY)
                elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Transponder Standby")
                    procedureloop1.stepindex = procedureloop1.stepindex - 1
                end
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Transponder Checked and Standby")
        end
    end

    if (procedureloop1.stepindex == 6) then
        if (get(logolighton) ~= OFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                togglelogolight(OFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Logo Lights Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Logo Lights Checked and Off")
        end
    end

    if (procedureloop1.stepindex == 7) then
        if (get(seatbeltsignpos) ~= SEATBELTSIGNOFF) then
            if (configvalues[CONFIGVOICEADVICEONLY] ~= ON) then
                setseatbeltsign(SEATBELTSIGNOFF)
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                commandtableentry(ADVICE, "Set Seatbeltsigns Off")
                procedureloop1.stepindex = procedureloop1.stepindex - 1
            end
        elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and not procedureloop1.steprepeat) then
            commandtableentry(ADVICE, "Seatbeltsigns checked and Off")
        end
    end

    if (procedureloop1.stepindex == 8) then
        if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
            commandtableentry(ADVICE, "Flight Complete, Ready for Engine Shutdown")
        else
            commandtableentry(TEXT, "Flight Complete, Ready for Engine Shutdown")
        end
    end

    return false

end

--------------------------------------------------------------------------------------------------------------
-- inflightrestoreactions function

function inflightrestoreactions()

    readconfig()

    if ((configvalues[CONFIGAUTOBARO] == ON) and (configvalues[CONFIGAUTOFUNCTIONS] == ON)) then
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
        aircraftwasonground = true

        if (flightstate == 0) then
            if ((not beforetaxiset) and (get(taxilight) ~= OFF) and enginesrunning(BOTH) and (get(groundspeed) < 45) and (procedureloop1.lock == NOPROCEDURE)) then
                procedureloop1.lock = BEFORETAXIPROCEDURE
            end

            if (beforetaxiset and (not beforetakeoffset) and (procedureloop1.lock == NOPROCEDURE)) then
                if ((aircraftonrwy(get(aircraftlatpos), get(aircraftlonpos), get(deprwylatstartpos), get(deprwylonstartpos), get(deprwylatendpos), get(deprwylonendpos), 0.0003) and
                     (headingdiff(get(groundtrackmag), get(deprwyheading)) < 20) and (roundnumber(get(groundspeed)) == 0))) then
                    procedureloop1.lock = BEFORETAKEOFFPROCEDURE
                end            
            end
        else
            if ((not afterlandingset) and (get(groundspeed) < 45) and (procedureloop1.lock == NOPROCEDURE)) then
                if (((not aircraftonrwy(get(aircraftlatpos), get(aircraftlonpos), desrwylatstartpostemp, desrwylonstartpostemp, desrwylatendpostemp, desrwylonendpostemp, 0.0001)) and
                    (headingdiff(get(groundtrackmag), desrwyheadingtemp) > 20)) or (roundnumber(get(groundspeed)) == 0)) then
                    flightstate = 5
                    procedureloop1.lock = AFTERLANDINGPROCEDURE
                end
            end

            if ((get(parkingbrakepos) == ON) and (flightstate >= 5) and afterlandingset and (not atparkingpositionset) and (procedureloop1.lock == NOPROCEDURE)) then
                flightstate = 6
                procedureloop1.lock = ATPARKINGPOSITIONPROCEDURE
            end
        end
    else -- aircraft in the air

        if not aircraftwasonground then
            inflightrestoreactions()
            aircraftwasonground = true
        end

        if ((flightstate <= 4) and (get(fmsflightphase) > 6)) then
            flightstate = 4
        elseif ((flightstate <= 3) and (get(fmsflightphase) > 2)) then
            flightstate = 3
        elseif ((flightstate <= 2) and (get(fmsflightphase) <= 2) and aftertakeoffset) then
            flightstate = 2
        elseif (flightstate == 0) then
            flightstate = 1
        end

        if ((flightstate == 1) and (not aftertakeoffset)  and (procedureloop2.lock == NOPROCEDURE)) then
           procedureloop2.lock = AFTERTAKEOFFPROCEDURE
        elseif (flightstate == 2) then
            duringclimb()
        elseif (flightstate > 2) then
            duringdescent()
        end
    end

    return true
end

--------------------------------------------------------------------------------------------------------------
-- voicereadback() function

function voicereadback()


    if (get(pausetod) ~= pausetodtemp) then
        if (get(pausetod) == ON) then
            commandtableentry(TEXT, "Pause at Top of Descent On")
        else
            commandtableentry(TEXT, "Pause at Top of Descent Off")
        end

        pausetodtemp = get(pausetod)
    end

    if (get(simfreezed) ~= simfreezedtemp) then
        if (get(simfreezed) == ON) then
            commandtableentry(TEXT, "Sim Freeze On")
        else
            commandtableentry(TEXT, "Sim Freeze Off")
        end

        simfreezedtemp = get(simfreezed)
    end

    if (get(chockstatus) ~= chockstatustmp) then
        if (get(chockstatus) == ON) then
            commandtableentry(TEXT, "Chocks Set")
        else
            commandtableentry(TEXT, "Chocks Removed")
        end

        chockstatustmp = get(chockstatus)
    end


    if (math.abs(get(totalfuellbs) - totalfuellbstemp) > 200) then
        if (get(totalfuellbs) ~= totalfuellbstemp2) then
            totalfuellbstemp2 = get(totalfuellbs)
        else
            if (get(fuelunit) == LBS) then
                commandtableentry(TEXT, "Fuel quantity " .. tostring(get(totalfuellbs)) .. "L B S")
            else
                commandtableentry(TEXT, "Fuel quantity " .. tostring(get(totalfuellbs)) .. "K G")
            end
            totalfuellbstemp = get(totalfuellbs)
        end
    else
        totalfuellbstemp = get(totalfuellbs)
    end

    if (get(cabincruisealt) ~= cabincruisealttemp) then
        if (get(cabincruisealt) ~= cabincruisealttemp2) then
            cabincruisealttemp2 = get(cabincruisealt)
        else
            commandtableentry(TEXT, "Cabin Cruise Altitude " .. tostring(get(cabincruisealt)))
            cabincruisealttemp = get(cabincruisealt)
            cabincruisealttemp2 = get(cabincruisealt)
        end
    end

    if (get(cabinlandingalt) ~= cabinlandingalttemp) then
        if (get(cabinlandingalt) ~= cabinlandingalttemp2) then
            cabinlandingalttemp2 = get(cabinlandingalt)
        else
            commandtableentry(TEXT, "Cabin Landing Altitude " .. tostring(get(cabinlandingalt)))
            cabinlandingalttemp = get(cabinlandingalt)
            cabinlandingalttemp2 = get(cabinlandingalt)
        end
    end

    if (get(mcpspeed) ~= mcpspeedtemp) then
        if ((get(atarmpos) == OFF) or (get(atspeedstat) == ON) or (get(atspeedintvstat) == ON)) then
            if (get(mcpspeed) ~= mcpspeedtemp2) then
                mcpspeedtemp2 = get(mcpspeed)
            else
                mcpspeedtemp = get(mcpspeed)
                mcpspeedtemp2 = get(mcpspeed)

                if (get(mcpspeed) < 1) then
                    speed = roundnumber(get(mcpspeed), 2)
                else
                    speed = roundnumber(get(mcpspeed))
                end

                if ((flightstate > 2) and (get(mcpspeed) == get(vref))) then
                    commandtableentry(TEXT, "M C P Speed set to V REF " .. tostring(speed))
                else
                    commandtableentry(TEXT, "M C P Speed " .. tostring(speed))
                end
            end
        end
    end

    if (get(mcpheading) ~= mcpheadingtemp) then
        if (get(mcpheading) ~= mcpheadingtemp2) then
            mcpheadingtemp2 = get(mcpheading)
        else
            mcpheadingtemp = get(mcpheading)
            mcpheadingtemp2 = get(mcpheading)

            commandtableentry(TEXT, "M C P Heading " .. addspaces(padNumberWithZerosStrict(get(mcpheading), 3)))
        end
    end

    if (get(mcpaltitude) ~= mcpaltitudetemp) then
        if (get(mcpaltitude) ~= mcpaltitudetemp2) then
            mcpaltitudetemp2 = get(mcpaltitude)
        else
            mcpaltitudetemp = get(mcpaltitude)
            mcpaltitudetemp2 = get(mcpaltitude)

            if (get(mcpaltitude) == get(fmccruisealt)) then
                commandtableentry(TEXT, "M C P set to Cruise Altitude " .. addspaces(get(mcpaltitude)))
            else
                commandtableentry(TEXT, "M C P Altitude " .. addspaces(get(mcpaltitude)))
            end
        end
    end

    if (get(mcpvsspeed) ~= mcpvsspeedtemp) then
        if (get(mcpvsspeed) ~= mcpvsspeedtemp2) then
            mcpvsspeedtemp2 = get(mcpvsspeed)
        else
            mcpvsspeedtemp = get(mcpvsspeed)
            mcpaltitudetemp2 = get(mcpvsspeed)

            if ((get(mcpvsspeed) ~= 0) and (get(apalthldstat) ~= ON) and (get(apvnavstat) ~= ON)) then
                commandtableentry(TEXT, "M C P Vertical Speed " .. tostring(get(mcpvsspeed)))
            end
        end
    end

    if (get(mcppilotcourse) ~= mcppilotcoursetemp) then
        if (get(mcppilotcourse) ~= mcppilotcoursetemp2) then
            mcppilotcoursetemp2 = get(mcppilotcourse)
        else
            mcppilotcoursetemp = get(mcppilotcourse)
            mcppilotcoursetemp2 = get(mcppilotcourse)

            commandtableentry(TEXT, "M C P Pilot Course " .. addspaces(padNumberWithZerosStrict(get(mcppilotcourse), 3)))
        end
    end

    if (get(mcpcopilotcourse) ~= mcpcopilotcoursetemp) then
        if (get(mcpcopilotcourse) ~= mcpcopilotcoursetemp2) then
            mcpcopilotcoursetemp2 = get(mcpcopilotcourse)
        else
            mcpcopilotcoursetemp = get(mcpcopilotcourse)
            mcpcopilotcoursetemp2 = get(mcpcopilotcourse)

            commandtableentry(TEXT, "M C P Copilot Course " .. addspaces(padNumberWithZerosStrict(get(mcpcopilotcourse), 3)))
        end
    end

    if (get(dhpilot) ~= dhpilottemp) then
        if (get(dhpilot) ~= dhpilottemp2) then
            dhpilottemp2 = get(dhpilot)
        else
            dhpilottemp = get(dhpilot)
            dhpilottemp2 = get(dhpilot)

            if ((get(dhpilot) == -1) or (get(dhpilot) == -1001)) then
                commandtableentry(TEXT, "Pilot Decision Altitude Reset")
            else
                commandtableentry(TEXT, "Pilot Decision Altitude " .. tostring(roundnumber(get(dhpilot))))
            end
        end
    end

    if ((get(desrwyheading) ~= desrwyheadingtemp) and (get(desrwyheading) ~= 0)) then
        desrwyheadingtemp = get(desrwyheading)
    end

    if ((get(desrwylatstartpos) ~= desrwylatstartpostemp) and (get(desrwylatstartpos) ~= 0)) then
        desrwylatstartpostemp = get(desrwylatstartpos)
    end

    if ((get(desrwylonstartpos) ~= desrwylonstartpostemp) and (get(desrwylonstartpos) ~= 0)) then
        desrwylonstartpostemp = get(desrwylonstartpos)
    end

    if ((get(desrwylatendpos) ~= desrwylatendpostemp) and (get(desrwylatendpos) ~= 0)) then
        desrwylatendpostemp = get(desrwylatendpos)
    end

    if ((get(desrwylonendpos) ~= desrwylonendpostemp) and (get(desrwylonendpos) ~= 0)) then
        desrwylonendpostemp = get(desrwylonendpos)
    end

    if (get(aponstat) ~= aponstattemp) then
        if (get(aponstat) == OFF) then
            commandtableentry(TEXT, "Autopilot OFF")
        end
        aponstattemp = get(aponstat)

    end

    if (get(apcmdastat) ~= apcmdastattemp) then
        if (get(apcmdastat) == ON) then
            commandtableentry(TEXT, "Command A On")
        else
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "Command A OFF")
            end
        end
        apcmdastattemp = get(apcmdastat)
    end

    if (get(apcmdbstat) ~= apcmdbstattemp) then
        if (get(apcmdbstat) == ON) then
            commandtableentry(TEXT, "Command B On")

            if ((get(apcmdastat) == ON) and ((get(apgscapturedstat) ~= OFF) or (get(aploccapturedstat) ~= OFF))) then
                if (get(mmrinstalled) == ON) then
                    if ((get(mmrcptactvalue) ~= get(mmrfoactvalue)) or (get(mmrcptactmode) ~= get(mmrfoactmode)) or (get(mcppilotcourse) ~= get(mcpcopilotcourse))) then
                        commandtableentry(TEXT, "Warning Pilot and Copilot M M R Disagree")
                    end
                else
                    if ((get(nav1freq) ~= get(nav2freq)) or (get(mcppilotcourse) ~= get(mcpcopilotcourse))) then
                        commandtableentry(TEXT, "Warning Pilot and Copilot NAV Disagree")
                    end
                end
            end
        else
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "Command B OFF")
            end
        end
        apcmdbstattemp = get(apcmdbstat)
    end

    if (get(apvnavstat) ~= apvnavstattemp) then
        if (get(apvnavstat) == ON) then
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "V NAV On")
            else
                commandtableentry(TEXT, "V NAV Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(apgscapturedstat) ~= CAPTURED) and (get(aploccapturedstat) ~= CAPTURED) and (get(aplpvgscapturedstat) ~= CAPTURED) and
                (get(aplpvloccapturedstat) ~= CAPTURED) and (get(apglsgscapturedstat) ~= CAPTURED) and (get(apglsloccapturedstat) ~= CAPTURED) and
                (get(apfacgscapturedstat) ~= CAPTURED) and (get(apfacloccapturedstat) ~= CAPTURED) and (get(apalthldstat) ~= ON) and (get(apvsstat) ~= ON) and (get(aplvlchgstat) ~= ON)) then
                commandtableentry(TEXT, "V NAV OFF")
            end
        end
        apvnavstattemp = get(apvnavstat)
    end

    if (get(aplnavstat) ~= aplnavstattemp) then
        if (get(aplnavstat) == ON) then
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "L NAV On")
            else
                commandtableentry(TEXT, "L NAV Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(aploccapturedstat) ~= CAPTURED) and (get(apgscapturedstat) ~= CAPTURED) and (get(aplpvloccapturedstat) ~= CAPTURED) and
                (get(aplpvgscapturedstat) ~= CAPTURED) and (get(apglsgscapturedstat) ~= CAPTURED) and (get(apglsloccapturedstat) ~= CAPTURED) and
                (get(apfacgscapturedstat) ~= CAPTURED) and (get(apfacloccapturedstat) ~= CAPTURED) and (get(aphdgselstat) ~= ON) and (get(apappstat) ~= ON) and
                (get(apvorlocstat) ~= ON)) then
                commandtableentry(TEXT, "L NAV OFF")
            end
        end
        aplnavstattemp = get(aplnavstat)
    end

    if (get(apappstat) ~= apappstattemp) then
        if (get(apappstat) == ON) then
            if (get(aponstat) == ON) then
                if ((get(apgscapturedstat) == ARMED) and (get(aploccapturedstat) == ARMED)) then
                    commandtableentry(TEXT, "Approach Armed")
                elseif ((get(aplpvgscapturedstat) == ARMED) and (get(aplpvloccapturedstat) == ARMED)) then
                    commandtableentry(TEXT, "L P V Approach Armed")
                elseif ((get(apglsgscapturedstat) == ARMED) and (get(apglsloccapturedstat) == ARMED)) then
                    commandtableentry(TEXT, "G L S Approach Armed")
                elseif ((get(apfacgscapturedstat) == ARMED) and (get(apfacloccapturedstat) == ARMED)) then
                    commandtableentry(TEXT, "F A C Approach Armed")
                end
            else
                commandtableentry(TEXT, "Approach Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(apgscapturedstat) ~= CAPTURED) and (aplocgcapturedstat ~= CAPTURED) and (get(aplpvgscapturedstat) ~= CAPTURED) and
                (get(aplpvloccapturedstat) ~= CAPTURED) and (get(apglsgscapturedstat) ~= CAPTURED) and (get(apglsloccapturedstat) ~= CAPTURED) and
                (get(apfacgscapturedstat) ~= CAPTURED) and (get(apfacloccapturedstat) ~= CAPTURED) and (get(aphdgselstat) ~= ON) and (get(aplnavstat) ~= ON)) then
                commandtableentry(TEXT, "Approach OFF")
            end
        end
        apappstattemp = get(apappstat)
    end

    if (get(apgscapturedstat) ~= apgscapturedstattemp) then
        if (get(apgscapturedstat) == CAPTURED) then
            commandtableentry(TEXT, "Glide Slope Captured")
        end
        apgscapturedstattemp = get(apgscapturedstat)
    end

    if (get(aploccapturedstat) ~= aploccapturedstattemp) then
        if (get(aploccapturedstat) == CAPTURED) then
            commandtableentry(TEXT, "Localizer Captured")
        end
        aploccapturedstattemp = get(aploccapturedstat)
    end

    if ((get(apflarestat) ~= apflarestattemp) or (get(aprolloutstat) ~= aprolloutstattemp)) then
        if ((get(apflarestat) == ON) and (get(aprolloutstat) == ON)) then
            commandtableentry(TEXT, "Autoland Armed")
            apflarestattemp = get(apflarestat)
            aprolloutstattemp = get(aprolloutstat)
        end
    end

    if (get(apvorlocstat) ~= apvorlocstattemp) then
        if (get(apvorlocstat) == ON) then
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "V O R Localizer On")
            else
                commandtableentry(TEXT, "V O R Localizer Armed")
            end
        else
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "V O R Localizer OFF")
            end
        end
        apvorlocstattemp = get(apvorlocstat)
    end

    if (get(apfacgscapturedstat) ~= apfacgscapturedstattemp) then
        if (get(apfacgscapturedstat) == CAPTURED) then
            commandtableentry(TEXT, "Glide Path Captured")
        end
        apfacgscapturedstattemp = get(apfacgscapturedstat)
    end

    if (get(apfacloccapturedstat) ~= apfacloccapturedstattemp) then
        if (get(apfacloccapturedstat) == CAPTURED) then
            commandtableentry(TEXT, "F A C Localizer Captured")
        end
        apfacloccapturedstattemp = get(apfacloccapturedstat)
    end

    if (get(lpvinstalled) == ON) then
        if (get(aplpvgscapturedstat) ~= aplpvgscapturedstattemp) then
            if (get(aplpvgscapturedstat) == CAPTURED) then
                commandtableentry(TEXT, "L P V Glide Slope Captured")
            end
            aplpvgscapturedstattemp = get(aplpvgscapturedstat)
        end

        if (get(aplpvloccapturedstat) ~= aplpvloccapturedstattemp) then
            if (get(aplpvloccapturedstat) == CAPTURED) then
                commandtableentry(TEXT, "L P V Localizer Captured")
            end
            aplpvloccapturedstattemp = get(aplpvloccapturedstat)
        end

        if (get(apglsgscapturedstat) ~= apglsgscapturedstattemp) then
            if (get(apglsgscapturedstat) == CAPTURED) then
                commandtableentry(TEXT, "G L S Glide Slope Captured")
            end
            apglsgscapturedstattemp = get(apglsgscapturedstat)
        end

        if (get(apglsloccapturedstat) ~= apglsloccapturedstattemp) then
            if (get(apglsloccapturedstat) == CAPTURED) then
                commandtableentry(TEXT, "G L S Localizer Captured")
            end
            apglsloccapturedstattemp = get(apglsloccapturedstat)
        end
    end

    if (get(apalthldstat) ~= apalthldstattemp) then
        if (get(apalthldstat) == ON) then
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "Altitude Hold On, Altitude " .. tostring(get(mcpaltitude)))
            else
                commandtableentry(TEXT, "Altitude Hold Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(apvsstat) ~= ON) and (get(aplvlchgstat) ~= ON) and (get(apgscapturedstat) ~= CAPTURED) and (get(aplpvgscapturedstat) ~= CAPTURED) and
                (get(apglsgscapturedstat) ~= CAPTURED) and (get(apfacgscapturedstat) ~= CAPTURED) and (get(apvnavstat) ~= ON)) then
                commandtableentry(TEXT, "Altitude Hold OFF")
            end
        end
        apalthldstattemp = get(apalthldstat)
    end

    if (get(aphdgselstat) ~= aphdgselstattemp) then
        if (get(aphdgselstat) == ON) then
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "Heading Select On, Heading " .. tostring(get(mcpheading)))
            else
                commandtableentry(TEXT, "Heading Select Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(aplnavstat) ~= ON) and (get(apvorlocstat) ~= ON) and (get(aploccapturedstat) ~= CAPTURED)) then
                commandtableentry(TEXT, "Heading Select OFF")
            end
        end
        aphdgselstattemp = get(aphdgselstat)
    end

    if (get(apvsstat) ~= apvsstattemp) then
        if (get(apvsstat) == ON) then
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "Vertical Speed On")
            else
                commandtableentry(TEXT, "Vertical Speed Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(mcpvsspeed) ~= 0) and (get(apalthldstat) ~= ON) and (get(apvnavstat) ~= ON) and (get(aplvlchgstat) ~= ON)) then
                commandtableentry(TEXT, "Vertical Speed OFF")
            end
        end
        apvsstattemp = get(apvsstat)
    end

    if (get(aplvlchgstat) ~= aplvlchgstattemp) then
        if (get(aplvlchgstat) == ON) then
            if (get(aponstat) == ON) then
                commandtableentry(TEXT, "Level Change On")
            else
                commandtableentry(TEXT, "Level Change Armed")
            end
        else
            if ((get(aponstat) == ON) and (get(mcpvsspeed) ~= 0) and (get(apalthldstat) ~= ON) and (get(apvnavstat) ~= ON) and (get(apvsstat) ~= ON)) then
                commandtableentry(TEXT, "Level Change OFF")
            end
        end
        aplvlchgstattemp = get(aplvlchgstat)
    end

    if (get(atarmpos) ~= atarmpostemp) then
        if (get(atarmpos) == ON) then
            commandtableentry(TEXT, "Autothrottle Armed")

        else
            commandtableentry(TEXT, "Autothrottle OFF")
        end
        atarmpostemp = get(atarmpos)
    end

    if (get(atn1stat) ~= atn1stattemp) then
        if ((get(atn1stat) == ON) and (get(airgroundsensor) == ON)) then
            if (get(atarmpos) == ON) then
                commandtableentry(TEXT, "N 1 On")
            else
                commandtableentry(TEXT, "N 1 Armed")
            end
        else
            if ((get(atn1stat) == OFF) and (get(airgroundsensor) == ON)) then
                commandtableentry(TEXT, "N 1 OFF")
            end
        end
        atn1stattemp = get(atn1stat)
    end

    if (get(atspeedstat) ~= atspeedstattemp) then
        if ((get(atspeedstat) == ON) and (get(apgscapturedstat) ~= CAPTURED) and (get(aplpvgscapturedstat) ~= CAPTURED) and (get(apglsgscapturedstat) ~= CAPTURED) and
            (get(apfacgscapturedstat) ~= CAPTURED) and (get(apvsstat) ~= ON)  and (get(aplvlchgstat) ~= ON)) then
            if (get(atarmpos) == ON) then
                commandtableentry(TEXT, "Speed On")
            else
                commandtableentry(TEXT, "Speed Armed")
            end
        else
            if ((get(atspeedstat) == OFF) and (get(atarmpos) == ON) and (get(atn1stat) ~= ON) and (get(apvnavstat) ~= ON)) then
                commandtableentry(TEXT, "Speed OFF")
            end
        end
        atspeedstattemp = get(atspeedstat)
    end

    if (get(atspeedintvstat) ~= atspeedintvstattemp) then
        if (get(atspeedintvstat) == ON) then
            if (get(atarmpos) == ON) then
                commandtableentry(TEXT, "Speed Intervention On")
            else
                commandtableentry(TEXT, "Speed Intervention Armed")
            end
        else
            if ((get(atarmpos) == ON) and (get(atn1stat) ~= ON) and (get(atspeedstat) ~= ON)) then
                commandtableentry(TEXT, "Speed Intervention OFF")
            end
        end
        atspeedintvstattemp = get(atspeedintvstat)
    end

    if ((get(baropilot) ~= baropilottemp) or (get(barostd) ~= barostdtemp)) then
        if (get(baropilot) ~= baropilottemp2) then
            baropilottemp2 = get(baropilot)
        else
            if ((get(barostd) == ON) and (get(barostd) ~= barostdtemp)) then
                commandtableentry(TEXT, "Q N H Standard")
            else
                if (get(baroinhpa) == ON) then
                    commandtableentry(TEXT, "Q N H " .. tostring(convertpressure(get(baropilot))))
                else
                    commandtableentry(TEXT, "Q N H " .. tostring(get(baropilot)))
                end
            end

            baropilottemp = get(baropilot)
            baropilottemp2 = get(baropilot)
            barostdtemp = get(barostd)
        end
    end

    if (get(taxilight) ~= taxilighttemp) then
        if (get(taxilight) ~= OFF) then
            commandtableentry(TEXT, "Taxi Lights On")
        else
            commandtableentry(TEXT, "Taxi Lights Off")
        end
        taxilighttemp = get(taxilight)
    end

    if (get(beaconlights) ~= beaconlightstemp) then
        if (get(beaconlights) == ON) then
            commandtableentry(TEXT, "Collision Lights On")
        else
            commandtableentry(TEXT, "Collision Lights Off")
        end
        beaconlightstemp = get(beaconlights)
    end

    if ((get(llightson) ~= llightsontemp) or (get(llights1) ~= llights1temp) or (get(llights2) ~= llights2temp) or (get(llights3) ~= llights3temp) or
        (get(llights4) ~= llights4temp)) then
        if ((get(llightson) == OFF) and (get(llights1) == OFF) and (get(llights2) == OFF) and (get(llights3) == OFF) and (get(llights4) == OFF)) then
            commandtableentry(TEXT, "Landing Lights Off")
        else
            if ((llightsontemp == OFF) and (llights1temp == OFF) and (llights2temp == OFF) and (llights3temp == OFF) and (llights4temp == OFF)) then
                commandtableentry(TEXT, "Landing Lights ON")
            end
        end
        llightsontemp = get(llightson)
        llights1temp = get(llights1)
        llights2temp = get(llights2)
        llights3temp = get(llights3)
        llights4temp = get(llights4)
    end

    if ((get(rwylightl) ~= rwylightltemp) or (get(rwylightr) ~= rwylightrtemp)) then
        if (((get(rwylightl) ~= rwylightltemp) and (get(rwylightr) ~= rwylightrtemp)) and (get(rwylightl) == get(rwylightr))) then
            if ((get(rwylightl) == ON) and (get(rwylightr) == ON)) then
                commandtableentry(TEXT, "Both Runway Turnoff Lights ON")
            else
                commandtableentry(TEXT, "Both Runway Turnoff Lights OFF")
            end
            rwylightltemp = get(rwylightl)
            rwylightrtemp = get(rwylightr)
        else
            if (get(rwylightl) ~= rwylightltemp) then
                if (get(rwylightl) == ON) then
                    commandtableentry(TEXT, "Left Runway Turnoff Light On")
                else
                    commandtableentry(TEXT, "Left Runway Turnoff Light Off")
                end
                rwylightltemp = get(rwylightl)
            end

            if (get(rwylightr) ~= rwylightrtemp) then
                if (get(rwylightr) == ON) then
                    commandtableentry(TEXT, "Right Runway Turnoff Light On")
                else
                    commandtableentry(TEXT, "Right Runway Turnoff Light Off")
                end
                rwylightrtemp = get(rwylightr)
            end
        end
    end

    if (get(positionlights) ~= positionlightstemp) then
        if (get(positionlights) == POSLIGHTSOFF) then
            commandtableentry(TEXT, "Position Lights OFF")
        elseif (get(positionlights) == POSLIGHTSSTEADY) then
            commandtableentry(TEXT, "Position Lights Steady")
        elseif (get(positionlights) == POSLIGHTSSTROBE) then
            commandtableentry(TEXT, "Position Lights Strobe")
        end
        positionlightstemp = get(positionlights)
    end

    if (get(logolighton) ~= logolightontemp) then

        if (get(logolighton) == ON) then
            commandtableentry(TEXT, "Logo Light ON")
        else
            commandtableentry(TEXT, "Logo Light Off")
        end
        logolightontemp = get(logolighton)
    end

    if (get(transponderpos) ~= transponderpostemp) then
        if (get(transponderpos) == STANDBY) then
            commandtableentry(TEXT, "Transponder Standby")
        elseif (get(transponderpos) == ALTOFF) then
            commandtableentry(TEXT, "Transponder Altitude Off")
        elseif (get(transponderpos) == ALTON) then
            commandtableentry(TEXT, "Transponder Altitude ON")
        elseif (get(transponderpos) == TA) then
            commandtableentry(TEXT, "Transponder Altitude T A")
        elseif (get(transponderpos) == TARA) then
            commandtableentry(TEXT, "Transponder T A R A")
        end
        transponderpostemp = get(transponderpos)
    end

    if (yawdamperswitchtemp ~= get(yawdamperswitch)) then
        if (get(yawdamperswitch) == ON) then
            commandtableentry(TEXT, "Yaw Damper ON")
        else
            commandtableentry(TEXT, "Yaw Damper Off")
        end
        yawdamperswitchtemp = get(yawdamperswitch)
    end

    if ((get(fdpilotpos) ~= fdpilotpostemp) or (get(fdfopos) ~= fdfopostemp)) then
        if ((get(fdpilotpos) ~= fdpilotpostemp) and (get(fdfopos) ~= fdfopostemp) and (get(fdpilotpos) == get(fdfopos))) then
            if (get(fdpilotpos) == ON) then
                commandtableentry(TEXT, "Both Flightdirectors On")
            else
                commandtableentry(TEXT, "Both Flightdirectors Off")
            end
            fdpilotpostemp = get(fdpilotpos)
            fdfopostemp = get(fdfopos)
        else
            if (get(fdpilotpos) ~= fdpilotpostemp) then
                if (get(fdpilotpos) == ON) then
                    commandtableentry(TEXT, "Pilot Flightdirector On")
                else
                    commandtableentry(TEXT, "Pilot Flightdirector Off")
                end
                fdpilotpostemp = get(fdpilotpos)
            end

            if (get(fdfopos) ~= fdfopostemp) then
                if (get(fdfopos) == ON) then
                    commandtableentry(TEXT, "Copilot Flightdirector On")
                else
                    commandtableentry(TEXT, "Copilot Flightdirector Off")
                end
                fdfopostemp = get(fdfopos)
            end
        end
    end

    if ((get(efiswxpilotpos) ~= efiswxpilotpostemp) or (get(efiswxfopos) ~= efiswxfopostemp)) then
        if ((get(efiswxpilotpos) ~= efiswxpilotpostemp) and (get(efiswxfopos) ~= efiswxfopostemp) and (get(efiswxpilotpos) == get(efiswxfopos))) then
            if (get(efiswxpilotpos) == ON) then
                commandtableentry(TEXT, "Both Weather Radars On")
            elseif (get(efisterrpilotpos) == OFF) then
                commandtableentry(TEXT, "Both Weather Radars Off")
            end
            efiswxpilotpostemp = get(efiswxpilotpos)
            efiswxfopostemp = get(efiswxfopos)
        else
            if (get(efiswxpilotpos) ~= efiswxpilotpostemp) then
                if (get(efiswxpilotpos) == ON) then
                    commandtableentry(TEXT, "Pilot Weather Radar On")
                elseif (get(efisterrpilotpos) == OFF) then
                    commandtableentry(TEXT, "Pilot Weather Radar Off")
                end
                efiswxpilotpostemp = get(efiswxpilotpos)
            end

            if (get(efiswxfopos) ~= efiswxfopostemp) then
                if (get(efiswxfopos) == ON) then
                    commandtableentry(TEXT, "Copilot Weather Radar On")

                elseif (get(efisterrfopos) == OFF) then
                    commandtableentry(TEXT, "Copilot Weather Radar Off")
                end
                efiswxfopostemp = get(efiswxfopos)
            end
        end
    end

    if ((get(efisterrpilotpos) ~= efisterrpilotpostemp) or (get(efisterrfopos) ~= efisterrfopostemp)) then
        if ((get(efisterrpilotpos) ~= efisterrpilotpostemp) and (get(efisterrfopos) ~= efisterrfopostemp) and (get(efisterrpilotpos) == get(efisterrfopos))) then
            if (get(efisterrpilotpos) == ON) then
                commandtableentry(TEXT, "Both Terrain Radars On")
            elseif (get(efiswxpilotpos) == OFF) then
                commandtableentry(TEXT, "Both Terrain Radars Off")
            end
            efisterrpilotpostemp = get(efisterrpilotpos)
            efisterrfopostemp = get(efisterrfopos)
        else
            if (get(efisterrpilotpos) ~= efisterrpilotpostemp) then
                if (get(efisterrpilotpos) == ON) then
                    commandtableentry(TEXT, "Pilot Terrain Radar On")
                elseif (get(efiswxpilotpos) == OFF) then
                    commandtableentry(TEXT, "Pilot Terrain Radar Off")
                end
                efisterrpilotpostemp = get(efisterrpilotpos)
            end

            if (get(efisterrfopos) ~= efisterrfopostemp) then
                if (get(efisterrfopos) == ON) then
                    commandtableentry(TEXT, "Copilot Terrain Radar On")
                elseif (get(efiswxfopos) == OFF) then
                    commandtableentry(TEXT, "Copilot Terrain Radar Off")
                end
                efisterrfopostemp = get(efisterrfopos)
            end
        end
    end

    if ((get(efisdatapilotpos) ~= efisdatapilotpostemp) or (get(efisdatafopos) ~= efisdatafopostemp)) then
        if ((get(efisdatapilotpos) ~= efisdatapilotpostemp) and (get(efisdatafopos) ~= efisdatafopostemp) and (get(efisdatafopos) == get(efisdatafopos))) then
            if (get(efisdatapilotpos) == ON) then
                commandtableentry(TEXT, "Both E F I S Data On")
            else
                commandtableentry(TEXT, "Both E F I S DATA Off")
            end
            efisdatapilotpostemp = get(efisdatapilotpos)
            efisdatafopostemp = get(efisdatafopos)
        else
            if (get(efisdatapilotpos) ~= efisdatapilotpostemp) then
                if (get(efisdatapilotpos) == ON) then
                    commandtableentry(TEXT, "Pilot E F I S Data On")
                else
                    commandtableentry(TEXT, "Pilot E F I S Data Off")
                end
                efisdatapilotpostemp = get(efisdatapilotpos)
            end

            if (get(efisdatafopos) ~= efisdatafopostemp) then
                if (get(efisdatafopos) == ON) then
                    commandtableentry(TEXT, "Copilot E F I S Data On")
                else
                    commandtableentry(TEXT, "Copilot E F I S Data Off")
                end
                efisdatafopostemp = get(efisdatafopos)
            end
        end
    end

       if ((get(efisfixpilotpos) ~= efisfixpilotpostemp) or (get(efisfixfopos) ~= efisfixfopostemp)) then
        if ((get(efisfixpilotpos) ~= efisfixpilotpostemp) and (get(efisfixfopos) ~= efisfixfopostemp) and (get(efisfixfopos) == get(efisfixfopos))) then
            if (get(efisfixpilotpos) == ON) then
                commandtableentry(TEXT, "Both E F I S Waypoint On")
            else
                commandtableentry(TEXT, "Both E F I S Waypoint Off")
            end
            efisfixpilotpostemp = get(efisfixpilotpos)
            efisfixfopostemp = get(efisfixfopos)
        else
            if (get(efisfixpilotpos) ~= efisfixpilotpostemp) then
                if (get(efisfixpilotpos) == ON) then
                    commandtableentry(TEXT, "Pilot E F I S Waypoint On")
                else
                    commandtableentry(TEXT, "Pilot E F I S Waypoint Off")
                end
                efisfixpilotpostemp = get(efisfixpilotpos)
            end

            if (get(efisfixfopos) ~= efisfixfopostemp) then
                if (get(efisfixfopos) == ON) then
                    commandtableentry(TEXT, "Copilot E F I S Waypoint On")
                else
                    commandtableentry(TEXT, "Copilot E F I S Waypoint Off")
                end
                efisfixfopostemp = get(efisfixfopos)
            end
        end
    end

    if ((get(efisairportpilotpos) ~= efisairportpilotpostemp) or (get(efisairportfopos) ~= efisairportfopostemp)) then
        if ((get(efisairportpilotpos) ~= efisairportpilotpostemp) and (get(efisairportfopos) ~= efisairportfopostemp) and (get(efisairportpilotpos) == get(efisairportfopos))) then
            if (get(efisairportpilotpos) == ON) then
                commandtableentry(TEXT, "Both E F I S Airport On")
            else
                commandtableentry(TEXT, "Both E F I S Airport Off")
            end
            efisairportpilotpostemp = get(efisairportpilotpos)
            efisairportfopostemp = get(efisairportfopos)
        else
            if (get(efisairportpilotpos) ~= efisairportpilotpostemp) then
                if (get(efisairportpilotpos) == ON) then
                    commandtableentry(TEXT, "Pilot E F I S Airport On")
                else
                    commandtableentry(TEXT, "Pilot E F I S Airport Off")
                end
                efisairportpilotpostemp = get(efisairportpilotpos)
            end

            if (get(efisairportfopos) ~= efisairportfopostemp) then
                if (get(efisairportfopos) == ON) then
                    commandtableentry(TEXT, "Copilot E F I S Airport On")
                else
                    commandtableentry(TEXT, "Copilot E F I S Airport Off")
                end
                efisairportfopostemp = get(efisairportfopos)
            end
        end
    end

    if ((get(efispospilotpos) ~= efispospilotpostemp) or (get(efisposfopos) ~= efisposfopostemp)) then
        if ((get(efispospilotpos) ~= efispospilotpostemp) and (get(efisposfopos) ~= efisposfopostemp) and (get(efispospilotpos) == get(efisposfopos))) then
            if (get(efispospilotpos) == ON) then
                commandtableentry(TEXT, "Both E F I S Position On")
            else
                commandtableentry(TEXT, "Both E F I S Position Off")
            end
            efispospilotpostemp = get(efispospilotpos)
            efisposfopostemp = get(efisposfopos)
        else
            if (get(efispospilotpos) ~= efispospilotpostemp) then
                if (get(efispospilotpos) == ON) then
                    commandtableentry(TEXT, "Pilot E F I S Position On")
                else
                    commandtableentry(TEXT, "Pilot E F I S Position Off")
                end
                efispospilotpostemp = get(efispospilotpos)
            end

            if (get(efisposfopos) ~= efisposfopostemp) then
                if (get(efisposfopos) == ON) then
                    commandtableentry(TEXT, "Copilot E F I S Position On")
                else
                    commandtableentry(TEXT, "Copilot E F I S Position Off")
                end
                efisposfopostemp = get(efisposfopos)
            end
        end
    end

    if ((get(efisvorpilotpos) ~= efisvorpilotpostemp) or (get(efisvorfopos) ~= efisvorfopostemp)) then
        if ((get(efisvorpilotpos) ~= efisvorpilotpostemp) and (get(efisvorfopos) ~= efisvorfopostemp) and (get(efisvorpilotpos) == get(efisvorfopos))) then
            if (get(efisvorpilotpos) == ON) then
                commandtableentry(TEXT, "Both E F I S Station On")
            else
                commandtableentry(TEXT, "Both E F I S Station Off")
            end
            efisvorpilotpostemp = get(efisvorpilotpos)
            efisvorfopostemp = get(efisvorfopos)
        else
            if (get(efisvorpilotpos) ~= efisvorpilotpostemp) then
                if (get(efisvorpilotpos) == ON) then
                    commandtableentry(TEXT, "Pilot E F I S Station On")
                else
                    commandtableentry(TEXT, "Pilot E F I S Station Off")
                end
                efisvorpilotpostemp = get(efisvorpilotpos)
            end

            if (get(efisvorfopos) ~= efisvorfopostemp) then
                if (get(efisvorfopos) == ON) then
                    commandtableentry(TEXT, "Copilot E F I S Station On")
                else
                    commandtableentry(TEXT, "Copilot E F I S Station Off")
                end
                efisvorfopostemp = get(efisvorfopos)
            end
        end
    end

    if (get(mmrinstalled) == ON) then
        if ((get(mmrcptactmode) ~= mmrcptactmodetemp) or (get(mmrcptactvalue) ~= mmrcptactvaluetemp) or (get(mmrfoactmode) ~= mmrfoactmodetemp) or
            (get(mmrfoactvalue) ~= mmrfoactvaluetemp)) then
            local mmrstring = ""
            local mmrchannel = 0
            if (((get(mmrcptactmode) ~= mmrcptactmodetemp) or (get(mmrcptactvalue) ~= mmrcptactvaluetemp)) and
                ((get(mmrfoactmode) ~= mmrfoactmodetemp) or (get(mmrfoactvalue) ~= mmrfoactvaluetemp)) and (get(mmrcptactmode) == get(mmrfoactmode)) and
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
                if ((get(mmrcptactmode) ~= get(mmrcptactmode)) or (get(mmrcptactvalue) ~= mmrcptactvaluetemp)) then
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

                if ((get(mmrfoactmode) ~= mmrfoactmodetemp) or (get(mmrfoactvalue) ~= mmrfoactvaluetemp)) then
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

            commandtableentry(TEXT, mmrstring .. tostring(mmrchannel))

            mmrcptactmodetemp = get(mmrcptactmode)
            mmrcptactvaluetemp = get(mmrcptactvalue)
            mmrfoactmodetemp = get(mmrfoactmode)
            mmrfoactvaluetemp = get(mmrfoactvalue)
            mmrcptstdbymodetemp = get(mmrcptstdbymode)
            mmrfostdbymodetemp = get(mmrfostdbymode)
        else
            if ((get(mmrcptstdbymode) ~= mmrcptstdbymodetemp) or (get(mmrfostdbymode) ~= mmrfostdbymodetemp)) then
                if ((get(mmrcptstdbymode) ~= mmrcptstdbymodetemp2) or (get(mmrfostdbymode) ~= mmrfostdbymodetemp2)) then
                    mmrcptstdbymodetemp2 = get(mmrcptstdbymode)
                    mmrfostdbymodetemp2 = get(mmrfostdbymode)
                else
                    if (get(mmrcptstdbymode) == get(mmrfostdbymode)) then
                        if (get(mmrcptstdbymode) == MMRLOC) then
                            commandtableentry(TEXT, "Both M M R Standby V O R")
                        elseif (get(mmrcptstdbymode) == MMRILS) then
                            commandtableentry(TEXT, "Both M M R Standby I L S")
                        elseif (get(mmrcptstdbymode) == MMRGLS) then
                            commandtableentry(TEXT, "Both M M R Standby G L S")
                        elseif (get(mmrcptstdbymode) == MMRLPV) then
                            commandtableentry(TEXT, "Both M M R Standby L P V")
                        end
                    else
                        if (get(mmrcptstdbymode) ~= mmrcptstdbymodetemp) then
                            if (get(mmrcptstdbymode) == MMRLOC) then
                                commandtableentry(TEXT, "Pilot M M R Standby V O R")
                            elseif (get(mmrcptstdbymode) == MMRILS) then
                                commandtableentry(TEXT, "Pilot M M R Standby I L S")
                            elseif (get(mmrcptstdbymode) == MMRGLS) then
                                commandtableentry(TEXT, "Pilot M M R Standby G L S")
                            elseif (get(mmrcptstdbymode) == MMRLPV) then
                                commandtableentry(TEXT, "Pilot M M R Standby L P V")
                            end
                        end

                        if (get(mmrfostdbymode) ~= mmrfostdbymodetemp) then
                            if (get(mmrfostdbymode) == MMRLOC) then
                                commandtableentry(TEXT, "Copilot M M R Standby V O R")
                            elseif (get(mmrfostdbymode) == MMRILS) then
                                commandtableentry(TEXT, "Copilot M M R Standby I L S")
                            elseif (get(mmrfostdbymode) == MMRGLS) then
                                commandtableentry(TEXT, "Copilot M M R Standby G L S")
                            elseif (get(mmrfostdbymode) == MMRLPV) then
                                commandtableentry(TEXT, "Copilot M M R Standby L P V")
                            end

                            mmrfostdbymodetemp = get(mmrfostdbymode)
                        end
                    end

                    mmrcptactmodetemp = get(mmrcptactmode)
                    mmrcptactvaluetemp = get(mmrcptactvalue)
                    mmrfoactmodetemp = get(mmrfoactmode)
                    mmrfoactvaluetemp = get(mmrfoactvalue)
                    mmrcptstdbymodetemp = get(mmrcptstdbymode)
                    mmrcptstdbymodetemp2 = get(mmrcptstdbymode)
                    mmrfostdbymodetemp = get(mmrfostdbymode)
                    mmrfostdbymodetemp2 = get(mmrfostdbymode)
                end
            end
        end
    else
        if ((get(nav1freq) ~= nav1freqtemp) or (get(nav2freq) ~= nav2freqtemp)) then
            if (get(nav1freq) == get(nav2freq)) then
                commandtableentry(TEXT, "Both N A V " .. addspaces(formatILSFrequency(get(nav1freq))))

                nav1freqtemp = get(nav1freq)
                nav2freqtemp = get(nav2freq)
            else
                if (get(nav1freq) ~= nav1freqtemp) then
                    commandtableentry(TEXT, "N A V 1 " .. addspaces(formatILSFrequency(get(nav1freq))))

                    nav1freqtemp = get(nav1freq)
                end

                if (get(nav2freq) ~= nav2freqtemp) then
                    commandtableentry(TEXT, "N A V 2 " .. addspaces(formatILSFrequency(get(nav1freq))))

                    nav2freqtemp = get(nav2freq)
                end
            end
        end
    end

    if ((get(centertanklswitch) ~= centertanklswitchtemp) or (get(centertankrswitch) ~= centertankrswitchtemp)) then
        if ((get(centertanklswitch) ~= centertanklswitchtemp) and (get(centertankrswitch) ~= centertankrswitchtemp) and (get(centertanklswitch) == get(centertankrswitch))) then
            if (get(centertanklswitch) == ON) then
                commandtableentry(TEXT, "Both Center Tank Fuel Pumps On")
            else
                commandtableentry(TEXT, "Both Center Tank Fuel Pumps Off")
            end
            centertanklswitchtemp = get(centertanklswitch)
            centertankrswitchtemp = get(centertankrswitch)
        else
            if (get(centertanklswitch) ~= centertanklswitchtemp) then
                if (get(centertanklswitch) == ON) then
                    commandtableentry(TEXT, "Left Center Tank Fuel Pump On")
                else
                    commandtableentry(TEXT, "Left Center Tank Fuel Pump Off")
                end
                centertanklswitchtemp = get(centertanklswitch)
            end

            if (get(centertankrswitch) ~= centertankrswitchtemp) then
                if (get(centertankrswitch) == ON) then
                    commandtableentry(TEXT, "Right Center Tank Fuel Pump On")
                else
                    commandtableentry(TEXT, "Right Center Tank Fuel Pump Off")
                end
                centertankrswitchtemp = get(centertankrswitch)
            end
        end
    end

    if ((get(lefttanklswitch) ~= lefttanklswitchtemp) or (get(lefttankrswitch) ~= lefttankrswitchtemp)) then
        if ((get(lefttanklswitch) ~= lefttanklswitchtemp) and (get(lefttankrswitch) ~= lefttankrswitchtemp) and (get(lefttanklswitch) == get(lefttankrswitch))) then
            if (get(lefttanklswitch) == ON) then
                commandtableentry(TEXT, "Both Left Wing Tank Fuel Pumps On")
            else
                commandtableentry(TEXT, "Both Left Wing Tank Fuel Pumps Off")
            end
            lefttanklswitchtemp = get(lefttanklswitch)
            lefttankrswitchtemp = get(lefttankrswitch)
        else
            if (get(lefttanklswitch) ~= lefttanklswitchtemp) then
                if (get(lefttanklswitch) == ON) then
                    commandtableentry(TEXT, "Left Wing Tank After Fuel Pump On")
                else
                    commandtableentry(TEXT, "Left Wing Tank After Fuel Pump Off")
                end
                lefttanklswitchtemp = get(lefttanklswitch)
            end

            if (get(lefttankrswitch) ~= lefttankrswitchtemp) then
                if (get(lefttankrswitch) == ON) then
                    commandtableentry(TEXT, "Right Wing Tank Forward Fuel Pump On")
                else
                    commandtableentry(TEXT, "Right Wing Tank Forward Fuel Pump Off")
                end
                lefttankrswitchtemp = get(lefttankrswitch)
            end
        end
    end

    if ((get(righttanklswitch) ~= righttanklswitchtemp) or (get(righttankrswitch) ~= righttankrswitchtemp)) then
        if ((get(righttanklswitch) ~= righttanklswitchtemp) and (get(righttankrswitch) ~= righttankrswitchtemp) and (get(righttanklswitch) == get(righttankrswitch))) then
            if (get(righttanklswitch) == ON) then
                commandtableentry(TEXT, "Both Right Wing Tank Fuel Pumps On")
            else
                commandtableentry(TEXT, "Both Right Wing Tank Fuel Pumps Off")
            end
            righttanklswitchtemp = get(righttanklswitch)
            righttankrswitchtemp = get(righttankrswitch)
        else
            if (get(righttanklswitch) ~= righttanklswitchtemp) then
                if (get(righttanklswitch) == ON) then
                    commandtableentry(TEXT, "Right Wing Tank Forward Fuel Pump On")
                else
                    commandtableentry(TEXT, "Right Wing Tank Forward Fuel Pump Off")
                end
                righttanklswitchtemp = get(righttanklswitch)
            end

            if (get(righttankrswitch) ~= righttankrswitchtemp) then
                if (get(righttankrswitch) == ON) then
                    commandtableentry(TEXT, "Right Wing Tank After Fuel Pump On")
                else
                    commandtableentry(TEXT, "Right Wing Tank After Fuel Pump Off")
                end
                righttankrswitchtemp = get(righttankrswitch)
            end
        end
    end

    if ((get(starter1pos) ~= starter1postemp) or (get(starter2pos) ~= starter2postemp)) then
        local starterstring = ""
        local statestring = ""
        if (((get(starter1pos) ~= starter1postemp) and (get(starter2pos) ~= starter2postemp)) and (get(starter1pos) == get(starter2pos))) then
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

            starter1postemp = get(starter1pos)
            starter2postemp = get(starter2pos)
        else
            if (get(starter1pos) ~= starter1postemp) then
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

                starter1postemp = get(starter1pos)
            end

            if (get(starter2pos) ~= starter2postemp) then
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

                starter2postemp = get(starter2pos)
            end
        end

        commandtableentry(TEXT, starterstring .. statestring)
    end

    if ((get(mixture1pos) ~= mixture1postemp) or (get(mixture2pos) ~= mixture2postemp)) then
        if ((get(mixture1pos) ~= mixture1postemp) and (get(mixture2pos) ~= mixture2postemp) and (get(mixture1pos) == get(mixture2pos))) then
            mixturestring = "Both Engine Fuel Levers "
            if (get(mixture1pos) == ON) then
                statestring = "Idle"
            elseif (get(mixture1pos) == OFF) then
                statestring = "Cutoff"
            end

            mixture1postemp = get(mixture1pos)
            mixture2postemp = get(mixture2pos)
        else
            if (get(mixture1pos) ~= mixture1postemp) then
                mixturestring = "Engine 1 Fuel Lever "
                if (get(mixture1pos) == ON) then
                    statestring = "Idle"
                elseif (get(mixture1pos) == OFF) then
                    statestring = "Cutoff"
                end

                mixture1postemp = get(mixture1pos)
            end

            if (get(mixture2pos) ~= mixture2postemp) then
                mixturestring = "Engine 2 Fuel Lever "
                if (get(mixture2pos) == ON) then
                    statestring = "Idle"
                elseif (get(mixture2pos) == OFF) then
                    statestring = "Cutoff"
                end

                mixture2postemp = get(mixture2pos)
            end
        end

        commandtableentry(TEXT, mixturestring .. statestring)
    end

    if ((get(reverser1pos) ~= reverser1postemp) or (get(reverser2pos) ~= reverser2postemp)) then
        if ((get(reverser1pos) ~= reverser1postemp) and (get(reverser2pos) ~= reverser2postemp) and (get(reverser1pos) == get(reverser2pos))) then
            if (((get(reverser1pos) == OFF) and (reverser1postemp ~= OFF)) or ((get(reverser2pos) == OFF) and (reverser2postemp ~= OFF))) then
                commandtableentry(TEXT, "Both Reversers Off")
            elseif (((get(reverser1pos) ~= OFF) and (reverser1postemp == OFF)) or ((get(reverser2pos) ~= OFF) and (reverser2postemp == OFF))) then
                commandtableentry(TEXT, "Both Reversers On")
            end

            reverser1postemp = get(reverser1pos)
            reverser2postemp = get(reverser2pos)
        else
            if (get(reverser1pos) ~= reverser1postemp) then
                if ((get(reverser1pos) == OFF) and (reverser1postemp ~= OFF)) then
                    commandtableentry(TEXT, "Reverser 1 Off")
                elseif ((get(reverser1pos) ~= OFF) and (reverser1postemp == OFF)) then
                    commandtableentry(TEXT, "Reverser 1 On")
                end

                reverser1postemp = get(reverser1pos)
            end

            if (get(reverser2pos) ~= reverser2postemp) then
                if ((get(reverser2pos) == OFF) and (reverser2postemp ~= OFF)) then
                    commandtableentry(TEXT, "Reverser 2 Off")
                elseif ((get(reverser2pos) ~= OFF) and (reverser2postemp == OFF)) then
                    commandtableentry(TEXT, "Reverser 2 On")
                end

                reverser2postemp = get(reverser2pos)
            end
        end
    end

    if (get(gpuon) ~= gpuontemp) then
        if (get(gpuon) == ON) then
            commandtableentry(TEXT, "Ground Power ON")
        else
            commandtableentry(TEXT, "Ground Power Off")
        end
        gpuontemp = get(gpuon)
    end

    if ((roundnumber(get(announcsourceoff1),1) ~= announcsourceoff1temp) or (roundnumber(get(announcsourceoff2),1) ~= announcsourceoff2temp)) then
        if (get(apurunning) == ON) then
            if ((get(apupowerbus1) == get(apupowerbus2)) and (get(announcsourceoff1) == get(announcsourceoff2)) and (get(announcsourceoff1) ~= announcsourceoff1temp) and (get(announcsourceoff2) ~= announcsourceoff2temp)) then
                if ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    commandtableentry(TEXT, "A P U Generator ON")
                elseif not ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                    commandtableentry(TEXT, "A P U Generators OFF")
                end
            else
                if (get(announcsourceoff1) ~= announcsourceoff1temp) then
                    if ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                        commandtableentry(TEXT, "A P U Generator 1 On")
                    elseif not ((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) then
                        commandtableentry(TEXT, "A P U Generator 1 Off")
                    end
                end

                if (get(announcsourceoff2) ~= announcsourceoff2temp) then
                    if ((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                        commandtableentry(TEXT, "A P U Generator 2 On")
                    elseif not ((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)) then
                        commandtableentry(TEXT, "A P U Generator 2 Off")
                    end
                end
            end
        end
        announcsourceoff1temp = roundnumber(get(announcsourceoff1),1)
        announcsourceoff2temp = roundnumber(get(announcsourceoff2),1)
    end

    if ((get(gen1pos) ~= gen1postemp) or (get(gen2pos) ~= gen2postemp)) then
        if ((get(gen1pos) ~= gen1postemp) and (get(gen2pos) ~= gen2postemp) and (get(gen1pos) == get(gen2pos))) then
            if (get(gen1pos) == ON) then
                commandtableentry(TEXT, "Both Generators ON")
            else
                commandtableentry(TEXT, "Both Generators OFF")
            end
            gen1postemp = get(gen1pos)
            gen2postemp = get(gen2pos)
        else
            if (get(gen1pos) ~= gen1postemp) then
                if (get(gen1pos) == ON) then
                    commandtableentry(TEXT, "Generator 1 On")
                else
                    commandtableentry(TEXT, "Generator 1 Off")
                end
                gen1postemp = get(gen1pos)
            end

            if (get(gen2pos) ~= gen2postemp) then
                if (get(gen2pos) == ON) then
                    commandtableentry(TEXT, "Generator 2 On")
                else
                    commandtableentry(TEXT, "Generator 2 Off")
                end
                gen2postemp = get(gen2pos)
            end
        end
    end

    if ((get(captainprobepos) ~= captainprobepostemp) or (get(foprobepos) ~= foprobepostemp)) then
        if ((get(captainprobepos) ~= captainprobepostemp) and (get(foprobepos) ~= foprobepostemp) and (get(captainprobepos) == get(foprobepos))) then
            if (get(captainprobepos) == ON) then
                commandtableentry(TEXT, "Both Probe Heat ON")
            else
                commandtableentry(TEXT, "Both Probe Heat OFF")
            end
            captainprobepostemp = get(captainprobepos)
            foprobepostemp = get(foprobepos)
        else
            if (get(captainprobepos) ~= captainprobepostemp) then
                if (get(captainprobepos) == ON) then
                    commandtableentry(TEXT, "Left Probe Heat On")
                else
                    commandtableentry(TEXT, "Left Probe Heat Off")
                end
                captainprobepostemp = get(captainprobepos)
            end

            if (get(foprobepos) ~= foprobepostemp) then
                if (get(foprobepos) == ON) then
                    commandtableentry(TEXT, "Right Probe Heat On")
                else
                    commandtableentry(TEXT, "Right Probe Heat Off")
                end
                foprobepostemp = get(foprobepos)
            end
        end
    end

    if ((get(wheatlfwdpos) ~= wheatlfwdpostemp) or (get(wheatlsidepos) ~= wheatlsidepostemp)) then
        if ((get(wheatlfwdpos) ~= wheatlfwdpostemp) and (get(wheatlsidepos) ~= wheatlsidepostemp) and (get(wheatlfwdpos) == get(wheatlsidepos))) then
            if (get(wheatlfwdpos) == ON) then
                commandtableentry(TEXT, "Pilot Window Heat ON")
            else
                commandtableentry(TEXT, "Pilot Window Heat OFF")
            end
            wheatlfwdpostemp = get(wheatlfwdpos)
            wheatlsidepostemp = get(wheatlsidepos)
        else
            if (get(wheatlfwdpos) ~= wheatlfwdpostemp) then
                if (get(wheatlfwdpos) == ON) then
                    commandtableentry(TEXT, "Pilot Forward Window Heat On")
                else
                    commandtableentry(TEXT, "Pilot Forward Window Heat Off")
                end
                wheatlfwdpostemp = get(wheatlfwdpos)
            end

            if (get(wheatlsidepos) ~= wheatlsidepostemp) then
                if (get(wheatlsidepos) == ON) then
                    commandtableentry(TEXT, "Pilot Side Window Heat On")
                else
                    commandtableentry(TEXT, "Pilot Side Window Heat Off")
                end
                wheatlsidepostemp = get(wheatlsidepos)
            end
        end
    end

    if ((get(wheatrfwdpos) ~= wheatrfwdpostemp) or (get(wheatrsidepos) ~= wheatrsidepostemp)) then
        if ((get(wheatrfwdpos) ~= wheatrfwdpostemp) and (get(wheatrsidepos) ~= wheatrsidepostemp) and (get(wheatrfwdpos) == get(wheatrsidepos))) then
            if (get(wheatrfwdpos) == ON) then
                commandtableentry(TEXT, "Copilot Window Heat ON")
            else
                commandtableentry(TEXT, "Copilot Window Heat OFF")
            end
            wheatrfwdpostemp = get(wheatrfwdpos)
            wheatrsidepostemp = get(wheatrsidepos)
        else
            if (get(wheatrfwdpos) ~= wheatrfwdpostemp) then
                if (get(wheatrfwdpos) == ON) then
                    commandtableentry(TEXT, "Copilot Forward Window Heat On")
                else
                    commandtableentry(TEXT, "Copilot Forward Window Heat Off")
                end
                wheatrfwdpostemp = get(wheatrfwdpos)
            end

            if (get(wheatrsidepos) ~= wheatrsidepostemp) then
                if (get(wheatrsidepos) == ON) then
                    commandtableentry(TEXT, "Copilot Side Window Heat On")
                else
                    commandtableentry(TEXT, "Copilot Side Window Heat Off")
                end
                wheatrsidepostemp = get(wheatrsidepos)
            end
        end
    end

    if (get(flapleverpos) ~= flapleverpostemp) then
        if (get(flapleverpos) ~= flapleverpostemp2) then
            flapleverpostemp2 = get(flapleverpos)
        else
            if (get(flapleverpos) == FLAPSUP) then
                commandtableentry(TEXT, "Flaps Up")
            elseif (get(flapleverpos) == FLAPS1) then
                commandtableentry(TEXT, "Flaps 1")
            elseif (get(flapleverpos) == FLAPS2) then
                commandtableentry(TEXT, "Flaps 2")
            elseif (get(flapleverpos) == FLAPS5) then
                commandtableentry(TEXT, "Flaps 5")
            elseif (get(flapleverpos) == FLAPS10) then
                commandtableentry(TEXT, "Flaps 10")
            elseif (get(flapleverpos) == FLAPS15) then
                commandtableentry(TEXT, "Flaps 15")
            elseif (get(flapleverpos) == FLAPS25) then
                commandtableentry(TEXT, "Flaps 25")
            elseif (get(flapleverpos) == FLAPS30) then
                commandtableentry(TEXT, "Flaps 30")
            elseif (get(flapleverpos) == FLAPS40) then
                commandtableentry(TEXT, "Flaps 40")
            end

            flapleverpostemp = get(flapleverpos)
            flapleverpostemp2 = get(flapleverpos)
        end
    end

    if (get(bankanglepos) ~= bankanglepostemp) then
        if (get(bankanglepos) ~= bankanglepostemp2) then
            bankanglepostemp2 = get(bankanglepos)
        else
            commandtableentry(TEXT, "Bank Angle " .. getbankanglestring(get(bankanglepos)))
            bankanglepostemp = get(bankanglepos)
            bankanglepostemp2 = get(bankanglepos)
        end
    end

    if (get(gearhandlepos) ~= gearhandlepostemp) then
        if (get(gearhandlepos) == GEARUP) then
            commandtableentry(TEXT, "Landing Gear Up")
        elseif (get(gearhandlepos) == GEAROFF) then
            commandtableentry(TEXT, "Landing Gear Lever Off")
        elseif (get(gearhandlepos) == GEARDOWN) then
            commandtableentry(TEXT, "Landing Gear Down")
        end

        gearhandlepostemp = get(gearhandlepos)
    end

    if (get(parkingbrakepos) ~= parkingbrakepostemp) then
        if (get(parkingbrakepos) == ON) then
            commandtableentry(TEXT, "Parking Brake Set")
        else
            commandtableentry(TEXT, "Parking Brake Off")
        end

        parkingbrakepostemp = get(parkingbrakepos)
    end

    speedbrakeleverrounded = roundnumber(get(speedbrakelever), 1)

    if (speedbrakeleverrounded ~= speedbrakelevertemp) then
        if (speedbrakeleverrounded ~= speedbrakelevertemp2) then
            speedbrakelevertemp2 = speedbrakeleverrounded
        else
            if (speedbrakeleverrounded == OFF) then
                commandtableentry(TEXT, "Speedbrake Down")
            elseif (speedbrakeleverrounded == 0.1) then
                commandtableentry(TEXT, "Speedbrake Armed")
            elseif (speedbrakeleverrounded >= 0.5) then
                commandtableentry(TEXT, "Speedbrake Up")
            end

            speedbrakelevertemp = speedbrakeleverrounded
            speedbrakelevertemp2 = speedbrakeleverrounded
        end
    end

    if (get(autobrakepos) ~= autobrakepostemp) then
        if (get(autobrakepos) == AUTOBRAKERTO) then
            commandtableentry(TEXT, "Auto Brake R T O")
        elseif (get(autobrakepos) == AUTOBRAKEOFF) then
            commandtableentry(TEXT, "Auto Brake Off")
        elseif (get(autobrakepos) == AUTOBRAKE1) then
            commandtableentry(TEXT, "Auto Brake 1")
        elseif (get(autobrakepos) == AUTOBRAKE2) then
            commandtableentry(TEXT, "Auto Brake 2")
        elseif (get(autobrakepos) == AUTOBRAKE3) then
            commandtableentry(TEXT, "Auto Brake 3")
        elseif (get(autobrakepos) == AUTOBRAKEMAX) then
            commandtableentry(TEXT, "Auto Brake Maximum")
        end

        autobrakepostemp = get(autobrakepos)
    end

    if (get(autobrakedisarm) ~= autobrakedisarmtemp) then
        if (get(autobrakedisarm) ~= autobrakedisarmtemp2) then
            autobrakedisarmtemp2 = get(autobrakedisarm)
        else
            if (get(autobrakedisarm) == ON) then
                commandtableentry(TEXT, "Auto Brake Disarmed")
            end

            autobrakedisarmtemp = get(autobrakedisarm)
            autobrakedisarmtemp2 = get(autobrakedisarm)
        end
    end

    if ((get(packlpos) ~= packlpostemp) or (get(packrpos) ~= packrpostemp)) then
        local packstring = ""
        local statestring = ""
        if (((get(packlpos) ~= packlpostemp) and (get(packrpos) ~= packrpostemp)) and (get(packlpos) == get(packrpos))) then
            packstring = "Both Packs "
            if (get(packlpos) == PACKOFF) then
                statestring = "Off"
            elseif (get(packlpos) == PACKAUTO) then
                    statestring = "Auto"
            elseif (get(packlpos) == PACKHIGH) then
                statestring = "High"
            end

            packlpostemp = get(packlpos)
            packrpostemp = get(packrpos)
        else
            if (get(packlpos) ~= packlpostemp) then
                packstring = "Left Pack "
                if (get(packlpos) == PACKOFF) then
                    statestring = "Off"
                elseif (get(packlpos) == PACKAUTO) then
                    statestring = "Auto"
                elseif (get(packlpos) == PACKHIGH) then
                    statestring = "High"
                end

                packlpostemp = get(packlpos)
            end

            if (get(packrpos) ~= packrpostemp) then
                packstring = "Right Pack "
                if (get(packrpos) == PACKOFF) then
                    statestring = "Off"
                elseif (get(packrpos) == PACKAUTO) then
                    statestring = "Auto"
                elseif (get(packrpos) == PACKHIGH) then
                    statestring = "High"
                end

                packrpostemp = get(packrpos)
            end
        end

        commandtableentry(TEXT, packstring .. statestring)
    end

    if (get(isolvalvepos) ~= isolvalvepostemp) then
        if (get(isolvalvepos) == ISOLVALVECLOSE) then
            commandtableentry(TEXT, "Isolation Valve Closed")
        elseif (get(isolvalvepos) == ISOLVALVEAUTO) then
            commandtableentry(TEXT, "Isolation Valve Auto")
        elseif (get(isolvalvepos) == ISOLVALVEOPEN) then
            commandtableentry(TEXT, "Isolation Valve Open")
        end

        isolvalvepostemp = get(isolvalvepos)
    end

   if ((get(bleedair1pos) ~= bleedair1postemp) or (get(bleedair2pos) ~= bleedair2postemp)) then
        if (((get(bleedair1pos) ~= bleedair1postemp) and (get(bleedair2pos) ~= bleedair2postemp)) and (hydropos1 == hydropos2)) then
            if (get(bleedair1pos) == ON) then
                commandtableentry(TEXT, "Both Engine Bleed Air On")
            else
                commandtableentry(TEXT, "Both Engine Bleed Air Off")
            end

            bleedair1postemp = get(bleedair1pos)
            bleedair2postemp = get(bleedair2pos)
        else
            if (get(bleedair1pos) ~= bleedair1postemp) then
                if (get(bleedair1pos) == ON) then
                    commandtableentry(TEXT, "Engine 1 Bleed Air On")
                else
                    commandtableentry(TEXT, "Engine 1 Bleed Air Off")
                end
                bleedair1postemp = get(bleedair1pos)
            end

            if (get(bleedair2pos) ~= bleedair2postemp) then
                if (get(bleedair2pos) == ON) then
                    commandtableentry(TEXT, "Engine 2 Bleed Air On")
                else
                    commandtableentry(TEXT, "Engine 2 Bleed Air Off")
                end
                bleedair2postemp = get(bleedair2pos)
            end
        end
    end

    if (get(trimairpos) ~= trimairpostemp) then
        if (get(trimairpos) == ON) then
            commandtableentry(TEXT, "Trim Air On")
        else
            commandtableentry(TEXT, "Trim Air Off")
        end

        trimairpostemp = get(trimairpos)
    end

    if (get(lrecircfanpos) ~= lrecircfanpostemp) then
        if (get(lrecircfanpos) == ON) then
            commandtableentry(TEXT, "Left Recircling Fan On")
        else
            commandtableentry(TEXT, "Left Recircling Fan Off")
        end

        lrecircfanpostemp = get(lrecircfanpos)
    end

    if (get(rrecircfanpos) ~= rrecircfanpostemp) then
        if (get(rrecircfanpos) == ON) then
            commandtableentry(TEXT, "Right Recircling Fan On")
        else
            commandtableentry(TEXT, "Right Recircling Fan Off")
        end

        rrecircfanpostemp = get(rrecircfanpos)
    end

    if (get(bleedairapupos) ~= bleedairapupostemp) then
        if (get(bleedairapupos) == ON) then
            commandtableentry(TEXT, "A P U Bleed Air On")
        else
            commandtableentry(TEXT, "A P U Bleed Air Off")
        end

        bleedairapupostemp = get(bleedairapupos)
    end

    if (get(battery) ~= batterytemp) then
        if (get(battery) == ON) then
            commandtableentry(TEXT, "Battery On")
        else
            commandtableentry(TEXT, "Battery Off")
        end

        batterytemp = get(battery)
    end

    if ((get(apustarterpos) ~= apustarterpostemp) or (get(apurunning) ~= apurunningtemp)) then
        if ((get(apustarterpos) == ON) and (get(apurunning) == ON)) then
            commandtableentry(TEXT, "A P U Started")
        else
            if ((get(apustarterpos) ~= apustarterpostemp) and (get(apustarterpos) == OFF)) then
                commandtableentry(TEXT, "A P U Shutting Down")
            end
        end

        apustarterpostemp = get(apustarterpos)
        apurunningtemp = get(apurunning)
    end

    if (get(emergencylights) ~= emergencylightstemp) then
        if (get(emergencylights) == EMERGLIGHTSOFF) then
            commandtableentry(TEXT, "Emergengy Lights OFF")
        elseif (get(emergencylights) == EMERGLIGHTSARMED) then
            commandtableentry(TEXT, "Emergency Lights Armed")
        elseif (get(emergencylights) == EMERGLIGHTSON) then
            commandtableentry(TEXT, "Emergency Lights ON")
        end
        emergencylightstemp = get(emergencylights)
    end

    if ((get(hydro1pos) ~= hydro1postemp) or (get(hydro2pos) ~= hydro2postemp)) then
        if (((get(hydro1pos) ~= hydro1postemp) and (get(hydro2pos) ~= hydro2postemp)) and (hydropos1 == hydropos2)) then
            if (get(hydro1pos) == ON) then
                commandtableentry(TEXT, "Both Hydraulic Pumps On")
            else
                commandtableentry(TEXT, "Both Hydraulic Pumps Off")
            end

            hydro1postemp = get(hydro1pos)
            hydro2postemp = get(hydro2pos)
        else
            if (get(hydro1pos) ~= hydro1postemp) then
                if (get(hydro1pos) == ON) then
                    commandtableentry(TEXT, "Hydraulic Pump 1 On")
                else
                    commandtableentry(TEXT, "Hydraulic Pump 1 Off")
                end
                hydro1postemp = get(hydro1pos)
            end

            if (get(hydro2pos) ~= hydro2postemp) then
                if (get(hydro2pos) == ON) then
                    commandtableentry(TEXT, "Hydraulic Pump 2 On")
                else
                    commandtableentry(TEXT, "Hydraulic Pump 2 Off")
                end
                hydro2postemp = get(hydro2pos)
            end
        end
    end

    if ((get(elechydro1pos) ~= elechydro1postemp) or (get(elechydro2pos) ~= elechydro2postemp)) then
        if ((get(elechydro1pos) ~= elechydro1postemp) and (get(elechydro2pos) ~= elechydro2postemp) and (get(elechydro1pos) == get(elechydro2pos))) then
            if (get(elechydro1pos) == ON) then
                commandtableentry(TEXT, "Both Electrical Hydraulic Pumps On")
            else
                commandtableentry(TEXT, "Both Electrical Hydraulic Pumps Off")
            end

            elechydro1postemp = get(elechydro1pos)
            elechydro2postemp = get(elechydro2pos)
        else
            if (get(elechydro1pos) ~= elechydro1postemp) then
                if (get(elechydro1pos) == ON) then
                    commandtableentry(TEXT, "Electrical Hydraulic Pump 2 On")
                else
                    commandtableentry(TEXT, "Electrical Hydraulic Pump 2 Off")
                end
                elechydro1postemp = get(elechydro1pos)
            end

            if (get(elechydro2pos) ~= elechydro2postemp) then
                if (get(elechydro2pos) == ON) then
                    commandtableentry(TEXT, "Electrical Hydraulic Pump 1 On")
                else
                    commandtableentry(TEXT, "Electrical Hydraulic Pump 1 Off")
                end
                elechydro2postemp = get(elechydro2pos)
            end
        end
    end

    if (get(seatbeltsignpos) ~= seatbeltsignpostemp) then
        if (get(seatbeltsignpos) == SEATBELTSIGNOFF) then
            commandtableentry(TEXT, "Seatbelt Sign Off")
        elseif (get(seatbeltsignpos) == SEATBELTSIGNAUTO) then
            commandtableentry(TEXT, "Seatbelt Sign Auto")
        elseif (get(seatbeltsignpos) == SEATBELTSIGNON) then
            commandtableentry(TEXT, "Seatbelt Sign On")
        end

        seatbeltsignpostemp = get(seatbeltsignpos)
    end

    if (get(nosmokingsignpos) ~= nosmokingsignpostemp) then
        if (get(nosmokingsignpos) == NOSMOKINGSIGNOFF) then
            commandtableentry(TEXT, "No Smoking Sign Off")
        elseif (get(nosmokingsignpos) == NOSMOKINGSIGNAUTO) then
            commandtableentry(TEXT, "No Smoking Sign Auto")
        elseif (get(nosmokingsignpos) == NOSMOKINGSIGNON) then
            commandtableentry(TEXT, "No Smoking Sign On")
        end

        nosmokingsignpostemp = get(nosmokingsignpos)
    end

    if (get(domelightpos) ~= domelightpostemp) then
        if (get(domelightpos) == DOMELIGHTOFF) then
            commandtableentry(TEXT, "Dome Light Off")
        elseif (get(domelightpos) == DOMELIGHTDIM) then
            commandtableentry(TEXT, "Dome Light Dim")
        elseif (get(domelightpos) == DOMELIGHTBRIGHT) then
            commandtableentry(TEXT, "Dome Light Bright")
        end

        domelightpostemp = get(domelightpos)
    end

    if ((get(irsleftpos) ~= irsleftpostemp) or (get(irsrightpos) ~= irsrightpostemp)) then
        if ((get(irsleftpos) ~= irsleftpostemp2) or (get(irsrightpos) ~= irsrightpostemp2)) then
                irsleftpostemp2 = get(irsleftpos)
                irsrightpostemp2 = get(irsrightpos)
        else
            local irsstring = ""
            local statestring = ""
            if ((get(irsleftpos) ~= irsleftpostemp) and (get(irsrightpos) ~= irsrightpostemp) and (get(irsleftpos) == get(irsrightpos))) then
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

                irsleftpostemp = get(irsleftpos)
                irsleftpostemp2 = get(irsleftpos)
                irsrightpostemp = get(irsrightpos)
                irsrightpostemp2 = get(irsrightpos)
            else
                if (get(irsleftpos) ~= irsleftpostemp) then
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

                    irsleftpostemp = get(irsleftpos)
                    irsleftpostemp2 = get(irsleftpos)
                end

                if (get(irsrightpos) ~= irsrightpostemp) then
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

                    irsrightpostemp = get(irsrightpos)
                    irsrightpostemp2 = get(irsrightpos)
                end
            end

            commandtableentry(TEXT, irsstring .. statestring)
        end
    end

    if (get(transpondercode) ~= transpondercodetemp) then
        if (get(transpondercode) ~= transpondercodetemp2) then
            transpondercodetemp2 = get(transpondercode)
        else
            commandtableentry(TEXT, "Transpondercode " .. get(transpondercode))
            transpondercodetemp = get(transpondercode)
            transpondercodetemp2 = get(transpondercode)
        end

    end

    if (configvalues[CONFIGAUTOWIPER] ~= ON) then
        if ((get(lwiperpos) ~= lwiperpostemp) or (get(rwiperpos) ~= rwiperpostemp)) then
            if ((get(lwiperpos) ~= lwiperpostemp2) or (get(rwiperpos) ~= rwiperpostemp2)) then
                lwiperpostemp2 = get(lwiperpos)
                rwiperpostemp2 = get(rwiperpos)
            else
                local wiperstring = ""
                local statestring = ""
                if (((get(lwiperpos) ~= lwiperpostemp) and (get(rwiperpos) ~= rwiperpostemp)) and (get(lwiperpos) == get(rwiperpos))) then
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

                    lwiperpostemp = get(lwiperpos)
                    lwiperpostemp2 = get(lwiperpos)
                    rwiperpostemp = get(rwiperpos)
                    rwiperpostemp2 = get(rwiperpos)
                else
                    if (get(lwiperpos) ~= lwiperpostemp) then
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

                        lwiperpostemp = get(lwiperpos)
                        lwiperpostemp2 = get(lwiperpos)
                    end

                    if (get(rwiperpos) ~= rwiperpostemp) then
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

                        rwiperpostemp = get(rwiperpos)
                        rwiperpostemp2 = get(rwiperpos)
                    end
                end

                commandtableentry(TEXT, wiperstring .. statestring)
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

    if (getmetarcounter == 0) then
        if ((depicaotmp ~= depmetar.icaocode) and isvalidicao(depicaotmp)) then
            depmetar.metar = getMetar(depicaotmp)
            if #depmetar.metar then
                depmetar.icaocode = depicaotmp
                depmetar.metarfound = true
                depmetar.decodedmetar = decodemetar(depmetar.metar.raw_text)
            else
                depmetar.icaocode = "XXXX"
                depmetar.metarfound = false
            end
        elseif (not isvalidicao(depicaotmp) and (nearesticaotmp ~= depmetar.icaocode) and isvalidicao(nearesticaotmp)) then
            depmetar.metar = getMetar(nearesticaotmp)
            if #depmetar.metar then
                depmetar.icaocode = nearesticaotmp
                depmetar.metarfound = true
                depmetar.decodedmetar = decodemetar(depmetar.metar.raw_text)
            else
                depmetar.icaocode = "XXXX"
                depmetar.metarfound = false
            end
        end

        if (desicaotmp ~= desmetar.icaocode) and isvalidicao(desicaotmp) then
            desmetar.metar = getMetar(desicaotmp)
            if #desmetar.metar then
                desmetar.icaocode = desicaotmp
                desmetar.metarfound = true
                desmetar.decodedmetar = decodemetar(desmetar.metar.raw_text)
            else
                desmetar.icaocode = "XXXX"
                desmetar.metarfound = false
            end
        end
   
        if #desmetar.decodedmetar then
            logtable(desmetar.decodedmetar, "DESMETAR")
        end

        if #desmetar.decodedmetar then
            logtable(depmetar.decodedmetar, "DEPMETAR")
        end

        getmetarcounter = 5
    else
        getmetarcounter = getmetarcounter - 1
    end

    if ((get(pausetod) == ON) and (remainingtimetoquit ~= 9999)) then
        if (get(simpaused) == ON) then
            if (remainingtimetoquit == 0) then
                remainingtimetoquit = configvalues[CONFIGTODPAUSEQUITTIME]
                helpers.command_once("laminar/B738/tab/save_flight" .. tonumber(configvalues[CONFIGSAVENUMBER]))
                helpers.command_once("sim/operation/quit")
            else
                remainingtimetoquit = remainingtimetoquit - 1
            end
        else
            remainingtimetoquit = configvalues[CONFIGTODPAUSEQUITTIME]
        end
    end

    if (remainingtimetosave ~= 9999) then
        if (remainingtimetosave == 0) then
            remainingtimetosave = configvalues[CONFIGSAVETIME]
            helpers.command_once("laminar/B738/tab/save_flight" .. tonumber(configvalues[CONFIGSAVENUMBER]))
        else
            remainingtimetosave = remainingtimetosave - 1
        end
    end

    if ((procedureloop1.lock == NOPROCEDURE) and (configvalues[CONFIGVOICEADVICEONLY] == ON)  and (get(airgroundsensor) == ON)) then
        if ((get(starter1pos) == GROUND) and ((get(lefttanklswitch) == OFF) or (get(lefttankrswitch) == OFF) or (get(righttanklswitch) == OFF) or (get(righttankrswitch) == OFF))) then
            commandtableentry(ADVICE, "Set Wing Tank Fuel Pumps On")
        elseif ((get(starter2pos) == GROUND) and ((get(lefttanklswitch) == OFF) or (get(lefttankrswitch) == OFF) or (get(righttanklswitch) == OFF) or (get(righttankrswitch) == OFF))) then
            commandtableentry(ADVICE, "Set Wing Tank Fuel Pumps On")
        elseif ((get(starter1pos) == GROUND) and ((get(packlpos) ~= PACKOFF) or (get(packrpos) ~= PACKOFF))) then
            commandtableentry(ADVICE, "Set Both Packs Off")
        elseif ((get(starter2pos) == GROUND) and ((get(packlpos) ~= PACKOFF) or (get(packrpos) ~= PACKOFF))) then
            commandtableentry(ADVICE, "Set Both Packs Off")
        elseif ((get(starter1pos) == GROUND) and (get(bleedairapupos) ~= ON)) then
            commandtableentry(ADVICE, "Set A P U Bleed Air On")
        elseif ((get(starter2pos) == GROUND) and (get(bleedairapupos) ~= ON)) then
            commandtableentry(ADVICE, "Set A P U Bleed Air On")
        elseif ((get(starter2pos) == GROUND) and (get(isolvalvepos) ~= ISOLVALVEOPEN)) then
            commandtableentry(ADVICE, "Set Isolation Valve Open")
        elseif ((get(starter1pos) == GROUND) and (get(eng1n2percent) > 25) and (get(mixture1pos) == OFF)) then 
            commandtableentry(ADVICE, "Engine 1 N 2 at 25 Percent")        
        elseif ((get(starter2pos) == GROUND) and (get(eng2n2percent) > 25) and (get(mixture2pos) == OFF)) then 
            commandtableentry(ADVICE, "Engine 2 N 2 at 25 Percent")
        elseif ((get(atarmpos) == ARMED) and (get(atn1stat) == OFF) and (get(groundspeed) < 45) and (get(eng1n1percent) > 40) and (get(eng1n1percent) > 40)) then 
            commandtableentry(ADVICE, "Both Engine N 1 at 40 Percent")
        elseif ((get(apustarterpos) == ON) and (get(apugenoffbus) ~= OFF) and (get(gen1pos) == OFF) and (get(gen1pos) == OFF) and (not((get(apupowerbus1) == ON) and (get(announcsourceoff1) == OFF)) or not((get(apupowerbus2) == ON) and (get(announcsourceoff2) == OFF)))) then
            commandtableentry(ADVICE, "A P U Running")
        end
    end

    if (ongoingtaskstepindex > 9) then
        ongoingtaskstepindex = 1
    end

    if (ongoingtaskstepindex == 1) then
        if (enginesrunning(BOTH) and (configvalues[CONFIGAUTOCENTERTANKHANDLING] == ON)) then
            if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                autocentertanks()
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                if ((get(centertanklbs) > 1000) and (get(centertanklpress) > 0) and (get(centertankrpress) > 0) and (get(centertankstat) > 0)) then
                    if ((get(centertanklswitch) == OFF) or (get(centertankrswitch) == OFF)) then
                        commandtableentry(ADVICE, "Set Center Tank Fuel Pumps On")
                        ongoingtaskstepindex = ongoingtaskstepindex - 1
                    end
                elseif ((get(centertanklbs) <= 1000)) or ((get(centertanklpress) == 0) and (get(centertankrpress) == 0)) then
                    if ((get(centertanklswitch) == ON) or (get(centertankrswitch) == ON)) then
                        commandtableentry(ADVICE, "Set Center Tank Fuel Pumps Off")
                        ongoingtaskstepindex = ongoingtaskstepindex - 1
                    end
                end
            end
        end
    end

    if (ongoingtaskstepindex == 2) then
        if ( (flightstate < 3) and (get(fmccruisealt) ~= 0) and (get(fmccruisealt) ~= 20000) and (get(cabincruisealt)  ~= get(fmccruisealt))) then
            if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then 
                set(cabincruisealt, get(fmccruisealt))
            elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then 
                commandtableentry(ADVICE, "Set Cabin Cruise Alitude " .. addspaces(get(fmccruisealt)))
                ongoingtaskstepindex = ongoingtaskstepindex - 1
            end
        end
    end

    if (ongoingtaskstepindex == 3) then
         if ((flightstate < 4) and desmetar.metarfound) then
            if tonumber(desmetar.metar.elevation_m) then
                deslandingalttmp = roundnumber((desmetar.metar.elevation_m * FEETTOMETER) / 50) * 50
            else
                deslandingalttmp = roundnumber(get(desrwyalt) / 50) * 50
            end
            if (get(cabinlandingalt) ~= deslandingalttmp) then
                if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                    set(cabinlandingalt, deslandingalttmp)
                elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then 
                    commandtableentry(ADVICE, "Set Cabin Landing Alitude " .. addspaces(deslandingalttmp))
                    ongoingtaskstepindex = ongoingtaskstepindex - 1
                end
            end
        end
    end

    
    if (ongoingtaskstepindex == 4) then
        if (configvalues[CONFIGAUTOANTIICE] == ON) then
            if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                if ((flightstate < 5) and beforetaxiset) then
                    if ((get(frameice) > 0.01) and (get(altitude) < 30000)) then
                        iceprotection(ON)
                    elseif ((get(altitude) > 30000) or (get(tatdegc) > 10)) then
                        iceprotection(OFF)
                    end
                end
            elseif ((configvalues[CONFIGVOICEADVICEONLY] == ON) and (get(airgroundsensor) == OFF)) then
                if ((get(frameice) > 0.01) and (get(altitude) < 30000)) then                   
                    if ((get(eng1heatpos) == OFF) or (get(eng2heatpos) == OFF) or (get(wingheatpos) == OFF)) then
                        commandtableentry(ADVICE, "Caution Icing Detected, Switch Anti Icing On")
                        ongoingtaskstepindex = ongoingtaskstepindex - 1
                    end
                elseif (get(altitude) > 30000) then
                    if ((get(eng1heatpos) == ON) or (get(eng2heatpos) == ON) or (get(wingheatpos) == ON)) then                      
                        commandtableentry(ADVICE, "Above 30.000 feet, Switch Anti Icing Off")
                        ongoingtaskstepindex = ongoingtaskstepindex - 1
                    end
                elseif (get(tatdegc) > 10) then
                    if ((get(eng1heatpos) == ON) or (get(eng2heatpos) == ON) or (get(wingheatpos) == ON)) then
                        commandtableentry(ADVICE, "T A T above 10 degree, Switch Anti Icing Off")
                        ongoingtaskstepindex = ongoingtaskstepindex - 1
                    end 
                end
            end
        end
    end

    if (ongoingtaskstepindex == 5) then
        if (configvalues[CONFIGAUTOWIPER] == ON) then
            if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then               
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

    if (((get(airgroundsensor) == ON) and (procedureloop1.lock == NOPROCEDURE) and (get(battery) == ON) and (get(mainbus) ~= OFF) and (flightstate == 0) and (get(taxilight) == OFF))) then

        if (ongoingtaskstepindex == 6) then
            if (configvalues[CONFIGAUTOBARO] == ON) then
                local baroinchtmp, baropastmp = getlocalqnh(DEPARTURE)
                if (roundnumber(math.abs(roundnumber(get(baropilot),2) - baroinchtmp),2) > 0.01) then
                    if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                        set(baropilot, baroinchtmp)
                    elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                        if (get(baroinhpa) == ON) then
                            commandtableentry(ADVICE, "Set Q N H " .. addspaces(baropastmp))
                        else
                            commandtableentry(ADVICE, "Set Q N H " .. addspaces(baroinchtmp))
                        end
                        ongoingtaskstepindex = ongoingtaskstepindex - 1
                    end
                end
            end
        end
    

        if (ongoingtaskstepindex == 7) then
            if (get(trimcalc) > 0) and (get(trimcalc) ~= gettrim() and (get(groundspeed) < 45)) then
                if (((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON))) then
                    settotrim()
                    commandtableentry(TEXT, "Trim " .. tostring(get(trimcalc)))
                elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set Trim " .. tostring(get(trimcalc)))
                    ongoingtaskstepindex = ongoingtaskstepindex - 1
                end
            end
        end
    

        if (ongoingtaskstepindex == 8) then
            if ((get(v2speed) > 0) and (get(v2speed) ~= get(mcpspeed)) and (get(groundspeed) < 45)) then
                if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                    set(mcpspeed, get(v2speed))
                elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set M C P Speed " .. addspaces(get(v2speed)))
                    ongoingtaskstepindex = ongoingtaskstepindex - 1         
                end
            end
        end

        if (ongoingtaskstepindex == 9) then
            local headingrounded = nil
        if (isvalidicao(get(depicao)) and isvalidrwy(get(deprwy)) and tonumber(get(deprwyheading))) then
                headingrounded = roundnumber(get(deprwyheading))
            end
            local navrwyheading = getrwyheadingfromnavdata(get(depicao), get(deprwy))
            if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 2)))) then
                headingrounded = navrwyheading
            end
            if (headingrounded and (headingrounded ~= get(mcpheading)) and (get(groundspeed) < 45)) then
                if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) and (configvalues[CONFIGVOICEADVICEONLY] ~= ON)) then
                    set(mcpheading, headingrounded)
                elseif (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                    commandtableentry(ADVICE, "Set M C P Heading " .. addspaces(headingrounded))
                    ongoingtaskstepindex = ongoingtaskstepindex - 1
                end
            end
        end
    end

    ongoingtaskstepindex = ongoingtaskstepindex + 1

    return true

end

--------------------------------------------------------------------------------------------------------------
-- commandtableloop() function

function commandtableloop()

    if (#commandtable > 0) then

        if (commandtable[1][1] == COMMAND) then
            sasl.logInfo("YAL COMMAND: " .. commandtable[1][2])
            helpers.command_once(commandtable[1][2])
        elseif (commandtable[1][1] == TEXT) then
            sasl.logInfo("YAL XPLMSpeakString TEXT: " .. commandtable[1][2])
            if (configvalues[CONFIGVOICEREADBACK] == ON) then
                speak(commandtable[1][2])
            end
        elseif (commandtable[1][1] == ADVICE) then
            sasl.logInfo("YAL XPLMSpeakString ADVICE: " .. commandtable[1][2])
            if (configvalues[CONFIGVOICEADVICEONLY] == ON) then
                speak(commandtable[1][2])
            end
        end

        table.remove(commandtable, 1)

    end

    return true

end

function speak(text)

    local c_str = ffi.new("char[?]", #text + 1)
    ffi.copy(c_str, text)
    xplm.XPLMSpeakString(c_str)
end

--------------------------------------------------------------------------------------------------------------
-- procedureloop_1() function

function procedureloop_1()

    if (procedureloop1.lock ~= NOPROCEDURE) then
        if (procedureloop1.lock == COCKPITINITPROCEDURE) then
            cockpitinitsteps()
        elseif (procedureloop1.lock == COLDANDDARKPROCEDURE) then
            coldanddarksteps()
        elseif (procedureloop1.lock == APUSTARTUPPROCEDURE) then
            apustartupsteps()
        elseif (procedureloop1.lock == ENGINESTARTPROCEDURE) then
            enginestartsteps()
        elseif (procedureloop1.lock == BEFORETAXIPROCEDURE) then
            beforetaxisteps()
        elseif (procedureloop1.lock == BEFORETAKEOFFPROCEDURE) then
            beforetakeoffsteps() 
        elseif (procedureloop1.lock == AFTERLANDINGPROCEDURE) then
            afterlandingsteps() 
        elseif (procedureloop1.lock == TURNAROUNDENGINESHUTDOWNPROCEDURE) then
            engineshutdownsteps()
        elseif (procedureloop1.lock == FINALENGINESHUTDOWNPROCEDURE) then
            engineshutdownsteps()
        elseif (procedureloop1.lock == SHUTDOWNPROCEDURE) then
            shutdownsteps()
        elseif (procedureloop1.lock == TESTPROCEDURE) then
            teststeps()
        elseif (procedureloop1.lock == ALTITUDEA10000PROCEDURE) then
            altitudea10000steps()
        elseif (procedureloop1.lock == ALTITUDEB10000PROCEDURE) then
            altitudeb10000steps()
        elseif (procedureloop1.lock == ATPARKINGPOSITIONPROCEDURE) then
            atparkingpositionsteps()
        elseif (procedureloop1.lock == SETILSPROCEDURE) then
            if setilssteps() then
                procedureloop1.lock = NOPROCEDURE
            end
        elseif (procedureloop1.lock == SETVREF30PROCEDURE) then
            appflapscalc, appvrefcalc = calcappflapsvref()
            if setvref(appflapscalc, appvrefcalc) then
                procedureloop1.lock = NOPROCEDURE
            end
        else
            procedureloop1.lock = NOPROCEDURE
        end

        procedureloop1.stepindex = procedureloop1.stepindex + 1

        if (procedureloop1.stepindex == procedureloop1.stepindexprevious) then
            procedureloop1.steprepeat = true
        else
            procedureloop1.steprepeat = false
            procedureloop1.stepindexprevious = procedureloop1.stepindex
        end

        if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and procedureskipstep) then
            procedureskipstep = false
            procedureloop1.stepindex = procedureloop1.stepindex + 1
        end
    else
        procedureloop1.stepindex = 1
        procedureloop1.stepindexprevious = 1
        procedureloop1.steprepeat = false
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- procedureloop_2() function

function procedureloop_2()

    if (procedureloop2.lock ~= NOPROCEDURE) then
        if (procedureloop2.lock == AFTERTAKEOFFPROCEDURE) then
            aftertakeoffsteps()
        elseif (procedureloop2.lock == DURINGCLIMBPROCEDURE) then
            duringclimbsteps()
        elseif (procedureloop2.lock == DURINGDESCENTPROCEDURE) then
            duringdescentsteps()
        elseif (procedureloop2.lock == RADIOALTITUDEB2500PROCEDURE) then
            radioaltitudeb2500steps()
        elseif (procedureloop2.lock == RADIOALTITUDEB1000PROCEDURE) then
            radioaltitudeb1000steps()
        else
           procedureloop2.lock = NOPROCEDURE
        end

        procedureloop2.stepindex = procedureloop2.stepindex + 1

        if (procedureloop2.stepindex == procedureloop2.previousstepindex) then
            procedureloop2.steprepeat = true
        else
            procedureloop2.steprepeat = false
            procedureloop2.previousstepindex = procedureloop2.stepindex
        end

        if ((configvalues[CONFIGVOICEADVICEONLY] == ON) and procedureskipstep2) then
            procedureskipstep2 = false
            procedureloop2.stepindex = procedureloop2.stepindex + 1
        end
    else
        procedureloop2.stepindex = 1
        procedureloop2.previousstepindex = 1
        procedureloop2.steprepeat = false
    end

    return true

end

--------------------------------------------------------------------------------------------------------------
-- do_yal()

function P.do_yal()

    if initialstartup then
        yalreset()
        initialstartup = false
    end

    if settings.newSettingsAvailable then
        readconfig()
        P.initDataref()
        sasl.logInfo("new settings detected... loading")
    end

    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("ONGOINGTASKSTEPINDEX: " .. ongoingtaskstepindex)

    if ((configvalues[CONFIGAUTOFUNCTIONS] == ON) or (configvalues[CONFIGVOICEADVICEONLY] == ON)) then
        autofunctions()
        ongoingtasks()
    end

    if (configvalues[CONFIGVOICEREADBACK] == ON) then
        voicereadback()
    end

    sasl.logDebug("PROCEDURELOOP1: LOCK ".. procedureloop1.lock .. " STEPINDEX " .. procedureloop1.stepindex)
    sasl.logDebug("PROCEDURELOOP2: LOCK "..procedureloop2.lock .. " STEPINDEX " .. procedureloop2.stepindex)

    procedureloop_1()
    procedureloop_2()

    commandtableloop()

    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("BEFORETAXISET: " .. tostring(beforetaxiset))
    sasl.logDebug("BEFORETAKEOFFSET: " .. tostring(beforetakeoffset))
    sasl.logDebug("AFTERTAKEOFFSET: " .. tostring(aftertakeoffset))
    sasl.logDebug("DURINGCLIMBSET: " .. tostring(duringclimbset))
    sasl.logDebug("ALTITUDEA10000SET: " .. tostring(altitudea10000set))
    sasl.logDebug("DURINGDESCENTSET: " .. tostring(duringdescentset))
    sasl.logDebug("ALTITUDEB10000SET: " .. tostring(altitudeb10000set))
    sasl.logDebug("RADIOALTITUDE2500SET: " .. tostring(radioaltitude2500set))
    sasl.logDebug("RADIOALTITUDE1000SET: " .. tostring(radioaltitude1000set))
    sasl.logDebug("AFTERLANDINGSET: " .. tostring(afterlandingset))
    sasl.logDebug("ATPARKINGPOSITIONSET: " .. tostring(atparkingpositionset))
    sasl.logDebug("--------------------------------------------")
    sasl.logDebug("FLIGHTSTATE: " .. tostring(flightstate))
    sasl.logDebug("FMSFLIGHTPHASE:" .. tostring(get(fmsflightphase)))
    sasl.logDebug("AIRCRAFTWASONGROUND: " .. tostring(aircraftwasonground))
    sasl.logDebug("Raw Departure METAR: " .. tostring(depmetar.metar.raw_text))
    sasl.logDebug("Altitude METAR: " .. tostring(depmetar.metar.elevation_m))
    sasl.logDebug("Raw METAR: " .. tostring(desmetar.metar.raw_text))
    sasl.logDebug("Altitude METAR: " .. tostring(desmetar.metar.elevation_m))

    return true

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
menu_set_vref = sasl.appendMenuItem(P.menu_main, "Set VREF 30", setvrefproc)
sasl.appendMenuSeparator ( P.menu_main )
menu_test = sasl.appendMenuItem(P.menu_main, "Tests", test)
sasl.appendMenuSeparator ( P.menu_main )
menu_toggle_setcockpitlights = sasl.appendMenuItem(P.menu_main, "Set Cockpit Lights", setcockpitlights)
menu_toggle_auto = sasl.appendMenuItem(P.menu_main, "Toggle Auto Functions", toggleautofunctions)
menu_toogle_voice = sasl.appendMenuItem(P.menu_main, "Toggle Voice Readback", togglevoicereadback)
menu_toogle_adviceonly = sasl.appendMenuItem(P.menu_main, "Toggle Advice Only", toggleadviceonly)
menu_toogle_freeze = sasl.appendMenuItem(P.menu_main, "Toggle Sim Freeze", togglesimfreeze)
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

    sasl.enableMenuItem(P.menu_main , menu_test , enable)
    sasl.enableMenuItem(P.menu_main , menu_toggle_setcockpitlights , enable)
    sasl.enableMenuItem(P.menu_main , menu_toggle_auto , enable)
    sasl.enableMenuItem(P.menu_main , menu_toogle_voice , enable)
    sasl.enableMenuItem(P.menu_main , menu_toogle_adviceonly , enable)
    sasl.enableMenuItem(P.menu_main , menu_toogle_freeze , enable)
    sasl.enableMenuItem(P.menu_main , menu_yal_reset , enable)

end

P.YalinitGlobal()

return yal