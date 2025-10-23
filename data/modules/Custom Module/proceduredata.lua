local def = require("definitions")
local helpers = require("helpers")

local M = {}


function M.fillProcedureTable()

    local P = yal 

    P.proceduretable = {
        [def.COLDANDDARKPROCEDURE] = { 
            number = 1, 
            name = "Cold and Dark Startup", 
            cycable = true, 
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
                    branch = function(loop, procData)
                        P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
                        return 'set_battery_on' 
                    end
                },
                ['set_battery_on'] = {
                    check = function() return get(P.battery) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/switch/battery_dn") end,
                    advice = "Switch Battery On",
                    confirm = "Battery checked and On",
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
                    confirm = "Domelight checked and On",
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
                    confirm = "Emergency Lights checked and Armed",
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
                    confirm = "Position Lights checked and Steady",
                    nextStep = 'check_power_source'
                },
                ['check_power_source'] = {
                    branch = function(loop, procData)
                        if (P.configvalues[def.CONFIGUSEGROUNDPOWER] == def.ON) and (get(P.gpuavailable) == def.ON) then
                            return 'check_gpu_power'
                        else
                            return 'start_apu'
                        end
                    end
                },
                ['check_gpu_power'] = {
                    check = function() return get(P.gpuon) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/gpu_dn") end,
                    advice = "Switch Ground Power On",
                    confirm = "G P U checked and On",
                    nextStep = 'start_irs_align'
                },
                ['start_apu'] = {
                    check = function() return get(P.apustarterpos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    advice = "Start A P U",
                    confirm = "A P U checked and Started",
                    nextStep = 'start_apu_2'
                },                
                ['start_apu_2'] = {
                    action = function() 
                        if P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF then
                            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") 
                            P.commandtableentry(def.TEXT, "A P U Started")
                        end
                    end,
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
                    advice = "Switch A P U Generator On",
                    confirm = "A P U Generator checked and On",
                    nextStep = 'set_apu_bleed'
                },
                ['set_apu_bleed'] = {
                    check = function() return get(P.bleedairapupos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Switch A P U Bleed Air On",
                    confirm = "A P U Bleed Air checked and On",
                    nextStep = 'set_isol_valve'
                },
                ['set_isol_valve'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEOPEN end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEOPEN) end,
                    advice = "Set Isolation Valve Open",
                    confirm = "Isolation Valve checked and Open",
                    nextStep = 'set_packs_auto'
                },
                ['set_packs_auto'] = {
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    action = function() set(P.packlpos, def.PACKAUTO); set(P.packrpos, def.PACKAUTO) end,
                    advice = "Set Both Packs Auto",
                    confirm = "Both Packs checked and Auto",
                    nextStep = 'set_trim_air'
                },
                ['set_trim_air'] = {
                    check = function() return get(P.trimairpos) == def.ON end,
                    action = function() set(P.trimairpos, def.ON) end,
                    advice = "Set Trim Air On",
                    confirm = "Trim Air checked and On",
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
                    nextStep = 'fmc_init_ref'
                },
                ['fmc_init_ref'] = {
                    action = function() helpers.command_once("laminar/B738/button/fmc1_init_ref") end,
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
            prerequisite = def.COLDANDDARKPROCEDURE, 
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
                        
                        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
                            P.setview(def.DEFAULTVIEW) 
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
                    nextStep = 'set_dome_light'
                },

                ['set_dome_light'] = { 
                    check = function() return get(P.domelightpos) ~= def.DOMELIGHTOFF end,
                    action = function() P.setdomelight(def.DOMELIGHTDIM) end,
                    advice = "Set Dome Light On",
                    confirm = "Dome light checked and On",
                    nextStep = 'view_main_panel'
                },
                
                ['view_main_panel'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'hide_efbs'
                },
                
                ['hide_efbs'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGHIDEEFBS] == def.OFF end,
                    
                    -- NEU: Prüft, ob die EFBs versteckt sind (Annahme: ON = versteckt)
                    check = function() 
                        return (get(P.hidecptefb) == def.ON) and (get(P.hidefoefb) == def.ON) 
                    end,
                    
                    -- Aktion (wird in beiden Modi ausgeführt, dank Flag unten)
                    action = function() 
                        -- Verstecke EFBs, falls sie noch sichtbar sind
                        if (get(P.hidecptefb) == def.OFF) then helpers.command_once("laminar/B738/tab/toggle") end
                        if (get(P.hidefoefb) == def.OFF) then helpers.command_once("laminar/B738/tab/fo_toggle") end
                    end,
                    
                    -- NEU: Standard-Aufforderung für Advice-Modus
                    advice = "Hide E F Bs", 
                    
                    -- NEU: Bestätigung (statt Text in der Action)
                    confirm = "E F B S checked and hidden", 
                    
                    nextStep = 'set_cockpit_lights',
                    
                    -- WICHTIG: Stellt sicher, dass die 'action' auch im Advice-Modus läuft
                    runActionInAdviceMode = true 
                },
                
                ['set_cockpit_lights'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGIGNOREALLBRIGHTHNESSSETTINGS] == def.ON end,
                    action = function() 
                        if P.setcockpitlights() then
                            P.commandtableentry(def.TEXT, "Instrument Lights set")
                        end
                    end,
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
                            -- Im Advice-Modus nur die Anweisung geben
                            P.commandtableentry(def.TEXT, "Reset F M C")
                        else
                            helpers.command_once("laminar/B738/button/reset_fmc")
                            P.commandtableentry(def.TEXT, "F M C Reset Done")
                        end
                    end,
                    -- 'advice' wird nicht mehr benötigt, da es in 'action' integriert ist
                    nextStep = 'load_yansh_ofp'
                },
                
                ['load_yansh_ofp'] = { 
                    skipIf = function() return not P.YANSHisinstalled() end,
                    check = function() return P.YANSHflightplanloaded() end,
                    action = function() helpers.command_once("YANSH/fetchOFP") end,
                    advice = "Load Simbrief Flight Plan",
                    confirm = "Simbrief Flight Plan Loaded",
                    nextStep = 'auto_fueling'
                },

                ['auto_fueling'] = { 
                    skipIf = function() return not (P.YANSHisinstalled() and P.YANSHflightplanloaded() and get(P.YANSHFuelPlanRamp) > 0 and P.configvalues[def.CONFIGAUTOFUELING] == def.ON) end,
                    action = function() 
                        if (P.configvalues[def.CONFIGAUTOFUNCTIONS] == def.ON) then
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
                    skipIf = function() return not (P.YANSHisinstalled() and P.YANSHflightplanloaded() and P.configvalues[def.CONFIGVOICEADVICEONLY] == def.ON) end,
                    check = function() return (helpers.isvalidicao(get(P.depicao)) and helpers.isvalidicao(get(P.desicao))) end,
                    advice = "Activate Flight Plan in F M C",
                    confirm = "Flight Plan in F M C Checked and Activated",
                    nextStep = 'set_fmc_to_flaps'
                },

                ['set_fmc_to_flaps'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return get(P.toflaps) ~= 0 end, 
                    advice = function() return "Set Takeoff Flaps " .. tostring(helpers.determineTakeoffFlapsSetting(get(P.totalweightkgs), get(P.deprwylen), get(P.deprwyheading), get(P.elevation), P.depmetar)) end,
                    confirm = function() return "Takeoff Flaps set and " .. tostring(get(P.toflaps)) end,
                    nextStep = 'set_fmc_cg'
                },

                ['set_fmc_cg'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return get(P.fmccg) ~= 0 end,
                    advice = function() return "Set C G " .. tostring(helpers.roundnumber(get(P.tabcg),1)) end,
                    confirm = function() return "C G checked and " .. tostring(get(P.fmccg)) end,
                    nextStep = 'set_fmc_vspeeds'
                },

                ['set_fmc_vspeeds'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return (get(P.v1setspeed) > 0) and (get(P.v2setspeed) > 0) and (get(P.vrsetspeed) > 0) end,
                    advice = "Enter V Speeds",
                    confirm = "V Speeds checked and Set",
                    nextStep = 'view_pedestal'
                },

                ['view_pedestal'] = { 
                    view = function() return P.configvalues[def.CONFIGVIEWPEDESTAL] end,
                    nextStep = 'set_transponder_code'
                },

                ['set_transponder_code'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGTRANSPONDER] == 0 end,
                    check = function() return get(P.transpondercode) == P.configvalues[def.CONFIGTRANSPONDER] end,
                    action = function() set(P.transpondercode, P.configvalues[def.CONFIGTRANSPONDER]) end,
                    advice = function() return "Set Transponder Code " .. helpers.addspaces(P.configvalues[def.CONFIGTRANSPONDER]) end,
                    confirm = function() return "Transponder Code checked and " .. helpers.addspaces(P.configvalues[def.CONFIGTRANSPONDER]) end,
                    nextStep = 'set_transponder_stby'
                },

                ['set_transponder_stby'] = { 
                    skipIf = function() return P.configvalues[def.CONFIGTRANSPONDER] == 0 end,
                    check = function() return get(P.transponderpos) == def.STANDBY end,
                    action = function() P.toggletransponder(def.STANDBY) end,
                    advice = "Set Transponder Standby",
                    confirm = "Transponder checked and Standby",
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
                    confirm = "Probe Heat checked and Off",
                    nextStep = 'set_seatbelts_off'
                },
                
                ['set_seatbelts_off'] = { 
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF end,
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNOFF) end,
                    advice = "Set Seatbelt Signs Off",
                    confirm = "Seatbelt Signs checked and Off",
                    nextStep = 'set_nosmoking_on'
                },
                
                ['set_nosmoking_on'] = { 
                    check = function() return get(P.nosmokingsignpos) == def.NOSMOKINGSIGNON end,
                    action = function() P.setnosmokingsign(def.NOSMOKINGSIGNON) end,
                    advice = "Set No Smoking Signs On",
                    confirm = "No Smoking Signs checked and On",
                    nextStep = 'set_poslights_steady'
                },

                ['set_poslights_steady'] = { 
                    check = function() return get(P.positionlights) == def.POSLIGHTSSTEADY end,
                    action = function() P.togglepositionlights(def.POSLIGHTSSTEADY) end,
                    advice = "Set Position Lights Steady",
                    confirm = "Position Lights checked and Steady",
                    nextStep = 'set_landinglights_off'
                },

                ['set_landinglights_off'] = { 
                    check = function() return (get(P.llights1)==def.OFF) and (get(P.llights2)==def.OFF) and (get(P.llights3)==def.OFF) and (get(P.llights4)==def.OFF) end,
                    action = function() P.togglelandinglights(def.OFF) end,
                    advice = "Set Landing Lights Off",
                    confirm = "Landing Lights checked and Off",
                    nextStep = 'set_rwy_lights_off'
                },

                ['set_rwy_lights_off'] = { 
                    check = function() return (get(P.rwylightl) == def.OFF) and (get(P.rwylightr) == def.OFF) end,
                    action = function() P.togglerwylights(def.OFF) end,
                    advice = "Set Runway Turnoff Lights Off",
                    confirm = "Runway Turnoff Lights checked and Off",
                    nextStep = 'set_taxilight_off'
                },
                
                ['set_taxilight_off'] = { 
                    check = function() return get(P.taxilight) == def.OFF end,
                    action = function() P.toggletaxilights(def.OFF) end,
                    advice = "Set Taxi Lights Off",
                    confirm = "Taxi Lights checked and Off",
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
                    confirm = "Both Flight Directors checked and Off",
                    nextStep = 'set_mcp_altitude'
                },

                ['set_mcp_altitude'] = { 
                    check = function() return get(P.mcpaltitude) == P.configvalues[def.CONFIGLOWEAIRSPACEALT] end,
                    action = function() set(P.mcpaltitude, P.configvalues[def.CONFIGLOWEAIRSPACEALT]) end,
                    advice = function() return "Set M C P ALtitude " .. tostring(P.configvalues[def.CONFIGLOWEAIRSPACEALT]) end,
                    confirm = function() return "M C P ALtitude checked and " .. tostring(P.configvalues[def.CONFIGLOWEAIRSPACEALT]) end,
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
                    confirm = "Auto Brake checked and Off",
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
                        helpers.command_once("laminar/B738/button/fmc1_clr")
                    end,
                    nextStep = nil
                }
            }
        },
        [def.APUSTARTUPPROCEDURE] = { 
            number = 3, 
            name = "A P U Startup", 
            cycable = true, 
            speakname = true,
            set = false, 
            loop = 1, 
            prerequisite = def.COCKPITINITPROCEDURE, 
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
                    nextStep = 'start_apu'
                },
                ['start_apu'] = {
                    check = function() return get(P.apustarterpos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    advice = "Start A P U",
                    confirm = nil,
                    nextStep = 'wait_initial_apu_spoolup'
                },
                ['wait_initial_apu_spoolup'] = {
                    check = function() return P.apurunning() > def.APUOFF end,
                    action = function()
                        if P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF then
                            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
                        end
                    end,
                    advice = nil,
                    confirm = "A P U Started, Running Up",
                    nextStep = 'wait_apu_ready'
                },
                ['wait_apu_ready'] = {
                    check = function() return P.apurunning() >= def.APUOFFBUS end,
                    advice = nil,
                    confirm = "A P U Running",
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
                    advice = "Switch A P U Generator On",
                    confirm = "A P U Generator checked and On",
                    nextStep = 'set_apu_bleed'
                },
                ['gpu_off'] = {
                    skipIf = function() return get(P.gpuon) == def.OFF end,
                    check = function() return get(P.gpuon) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/gpu_up") end,
                    advice = "Switch Ground Power Off",
                    confirm = "Ground Power checked and Off",
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
                    nextStep = 'set_beacon_on'
                },
                ['set_beacon_on'] = {
                    check = function() return get(P.beaconlights) == def.ON end,
                    action = function() P.togglecollisionlights(def.ON) end,
                    advice = "Set Collision Lights On",
                    confirm = "Collision lightset checked and On",
                    nextStep = 'set_fuel_pumps_on'
                },
                ['set_fuel_pumps_on'] = {
                    check = function() return (get(P.lefttanklswitch) == def.ON) and (get(P.lefttankrswitch) == def.ON) and (get(P.righttanklswitch) == def.ON) and (get(P.righttankrswitch) == def.ON) end,
                    action = function() 
                        set(P.lefttanklswitch, def.ON); set(P.lefttankrswitch, def.ON)
                        set(P.righttanklswitch, def.ON); set(P.righttankrswitch, def.ON)
                    end,
                    advice = "Set Wing Tank Fuel Pumps On",
                    confirm = "Wing Fuel Tanks checked and On",
                    nextStep = 'set_packs_off'
                },
                ['set_packs_off'] = {
                    check = function() return (get(P.packlpos) == def.PACKOFF) and (get(P.packrpos) == def.PACKOFF) end,
                    action = function() set(P.packlpos, def.PACKOFF); set(P.packrpos, def.PACKOFF) end,
                    advice = "Set Both Packs Off",
                    confirm = "Both Packs checked and Off",
                    nextStep = 'set_apu_bleed_on'
                },
                ['set_apu_bleed_on'] = {
                    check = function() return get(P.bleedairapupos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Set A P U Bleed Air On",
                    confirm = "A P U Bleed Air checked and On",
                    nextStep = 'set_isol_valve_open'
                },
                ['set_isol_valve_open'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEOPEN end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEOPEN) end,
                    advice = "Set Isolation Valve Open",
                    confirm = "Isolation Valve checked and Open",
                    nextStep = 'set_starter2_gnd'
                },
                ['set_starter2_gnd'] = {
                    check = function() return get(P.starter2pos) == def.GROUND end,
                    action = function() P.setstarter(def.ENGINE2, def.GROUND) end,
                    advice = "Set Starter 2 Ground",
                    confirm = "Engine 2 Starter checked and Ground",
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
                    confirm = "Engine 2 Fuel Lever checked and Idle",
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
                    confirm = "Engine 1 Starter checked and Ground",
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
                    confirm = "Engine 1 Fuel Lever checked and Idle",
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
                    confirm = "Both Generators checked and On",
                    nextStep = 'set_hyd_on'
                },
                ['set_hyd_on'] = {
                    check = function() return (get(P.hydro1pos) == def.ON) and (get(P.hydro2pos) == def.ON) end,
                    action = function() set(P.hydro1pos, def.ON); set(P.hydro2pos, def.ON) end,
                    advice = "Switch Both Hydraulic Pumps On",
                    confirm = "Both Hydraulic Pumps checked and On",
                    nextStep = 'set_elec_hyd_on'
                },
                ['set_elec_hyd_on'] = {
                    check = function() return (get(P.elechydro1pos) == def.ON) and (get(P.elechydro2pos) == def.ON) end,
                    action = function() set(P.elechydro1pos, def.ON); set(P.elechydro2pos, def.ON) end,
                    advice = "Switch Both Electrical Hydraulic Pumps On",
                    confirm = "Both Electrical Hydraulic Pumps checked and On",
                    nextStep = 'set_eng_bleed_on'
                },
                ['set_eng_bleed_on'] = {
                    check = function() return (get(P.bleedair1pos) == def.ON) and (get(P.bleedair2pos) == def.ON) end,
                    action = function() 
                        if (get(P.bleedair1pos) == def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_1") end
                        if (get(P.bleedair2pos) == def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_2") end
                    end,
                    advice = "Set Both Engine Bleed Air On",
                    confirm = "Both Engine Bleed Air checked and On",
                    nextStep = 'set_packs_auto'
                },
                ['set_packs_auto'] = {
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    action = function() set(P.packlpos, def.PACKAUTO); set(P.packrpos, def.PACKAUTO) end,
                    advice = "Set Both Packs Auto",
                    confirm = "Both Packs checked and Auto",
                    nextStep = 'set_isol_valve_auto'
                },
                ['set_isol_valve_auto'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEAUTO end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEAUTO) end,
                    advice = "Set Isolation Valve Auto",
                    confirm = "Isolation Valve checked and Auto",
                    nextStep = 'set_trim_air_on'
                },
                ['set_trim_air_on'] = {
                    check = function() return get(P.trimairpos) == def.ON end,
                    action = function() set(P.trimairpos, def.ON) end,
                    advice = "Set Trim Air On",
                    confirm = "Trim Air checked and On",
                    nextStep = 'set_apu_bleed_off'
                },
                ['set_apu_bleed_off'] = {
                    check = function() return get(P.bleedairapupos) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Switch A P U Bleed Air Off",
                    confirm = "A P U Bleed Air checked and Off",
                    nextStep = 'set_apu_off'
                },
                ['set_apu_off'] = {
                    check = function() return P.apurunning() == def.APUOFF end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up") end,
                    advice = "Switch APU Off",
                    confirm = "A P U checked and Off",
                    nextStep = 'set_yaw_damper_on'
                },
                ['set_yaw_damper_on'] = {
                    check = function() return get(P.yawdamperswitch) == def.ON end,
                    action = function() set(P.yawdamperswitch, def.ON) end,
                    advice = "Set Yaw Damper On",
                    confirm = "Yaw Damper checked and On",
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
                    nextStep = 'remove_chocks'
                },
                ['remove_chocks'] = {
                    check = function() return get(P.chockstatus) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/chock") end,
                    advice = "Remove Chocks",
                    confirm = "Chocks checked and Removed",
                    nextStep = 'check_night_view'
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
                    confirm = "Domelight checked and Off",
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
                    confirm = "Taxi Lights checked and On",
                    nextStep = 'pos_lights_steady'
                },
                ['pos_lights_steady'] = {
                    check = function() return get(P.positionlights) == def.POSLIGHTSSTEADY end,
                    action = function() P.togglepositionlights(def.POSLIGHTSSTEADY) end,
                    advice = "Set Position Lights Steady",
                    confirm = "Position Lights checked and Steady",
                    nextStep = 'beacon_on'
                },
                ['beacon_on'] = {
                    check = function() return get(P.beaconlights) == def.ON end,
                    action = function() P.togglecollisionlights(def.ON) end,
                    advice = "Set Collision Lights On",
                    confirm = "Collision Lights checked and On",
                    nextStep = 'seatbelts_on'
                },
                ['seatbelts_on'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNON end,
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNON) end,
                    advice = "Set Seatbeltsigns On",
                    confirm = "Seatbeltsigns checked and On",
                    nextStep = 'logo_light_on'
                },
                ['logo_light_on'] = {
                    check = function() return get(P.logolighton) == def.ON end,
                    action = function() P.togglelogolight(def.ON) end,
                    advice = "Set Logo Lights On",
                    confirm = "Logo Lights checked and On",
                    nextStep = 'yaw_damper_on'
                },
                ['yaw_damper_on'] = {
                    check = function() return get(P.yawdamperswitch) == def.ON end,
                    action = function() set(P.yawdamperswitch, def.ON) end,
                    advice = "Set Yaw Damper On",
                    confirm = "Yaw Damper checked and On",
                    nextStep = 'hyd_pumps_on'
                },
                ['hyd_pumps_on'] = {
                    check = function() return (get(P.hydro1pos) == def.ON) and (get(P.hydro2pos) == def.ON) and (get(P.elechydro1pos) == def.ON) and (get(P.elechydro2pos) == def.ON) end,
                    action = function() 
                        set(P.hydro1pos, def.ON); set(P.hydro2pos, def.ON)
                        set(P.elechydro1pos, def.ON); set(P.elechydro2pos, def.ON)
                    end,
                    advice = "Switch Hydraulic Pumps On",
                    confirm = "Hydraulic Pumps checked and On",
                    nextStep = 'window_heat_on'
                },
                ['window_heat_on'] = {
                    check = function() return (get(P.wheatlfwdpos) == def.ON) and (get(P.wheatrfwdpos) == def.ON) and (get(P.wheatlsidepos) == def.ON) and (get(P.wheatrsidepos) == def.ON) end,
                    action = function() P.togglewindowheat(def.ON) end,
                    advice = "Set Window Heat On",
                    confirm = "Window Heat checked and On",
                    nextStep = 'probe_heat_on'
                },
                ['probe_heat_on'] = {
                    check = function() return (get(P.captainprobepos) == def.ON) and (get(P.foprobepos) == def.ON) end,
                    action = function() P.toggleprobeheat(def.ON) end,
                    advice = "Set Probe Heat On",
                    confirm = "Probe Heat checked and On",
                    nextStep = 'starters_flight'
                },
                ['starters_flight'] = {
                    check = function() return (get(P.starter1pos) == def.FLIGHT) and (get(P.starter2pos) == def.FLIGHT) end,
                    action = function() P.setstarter(def.BOTH, def.FLIGHT) end,
                    advice = "Set Both Starters Flight",
                    confirm = "Both Starters checked and FLight",
                    nextStep = 'apu_bleed_off'
                },
                ['apu_bleed_off'] = {
                    skipIf = function() return P.apurunning() >= def.APUOFFBUS end,
                    check = function() return get(P.bleedairapupos) == def.OFF end,
                    action = function() set(P.bleedairapupos, def.OFF) end,
                    advice = "Set A P U Bleed Air Off",
                    confirm = "A P U Bleed Air checked and Off",
                    nextStep = 'isol_valve_auto'
                },
                ['isol_valve_auto'] = {
                    skipIf = function() return get(P.bleedairapupos) == def.ON end,
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEAUTO end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEAUTO) end,
                    advice = "Set Isolation Valve Auto",
                    confirm = "Isolation Valve checked and Auto",
                    nextStep = 'packs_auto'
                },
                ['packs_auto'] = {
                    skipIf = function() return not (get(P.bleedairapupos) == def.ON or (get(P.bleedair1pos) == def.ON and get(P.bleedair2pos) == def.ON)) end,
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    action = function() set(P.packlpos, def.PACKAUTO); set(P.packrpos, def.PACKAUTO) end,
                    advice = "Set Both Packs Auto",
                    confirm = "Both Packs checked and Auto",
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
                    confirm = "Flight Directors checked and On",
                    nextStep = 'arm_lnav'
                },
                ['arm_lnav'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return get(P.aplnavstat) == def.ON end,
                    advice = "Arm L NAV",
                    confirm = "L NAV checked and Armed",
                    nextStep = 'arm_vnav'
                },
                ['arm_vnav'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return get(P.apvnavstat) == def.ON end,
                    advice = "Arm V NAV",
                    confirm = "V NAV checked and Armed",
                    nextStep = 'view_throttle'
                },
                ['view_throttle'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWTHROTTLE] end,
                    nextStep = 'set_flaps_takeoff'
                },
                ['set_flaps_takeoff'] = {
                    check = function() return (helpers.convflaplevertoflappos(get(P.flapleverpos)) == get(P.toflaps)) end,
                    action = function() helpers.command_once("laminar/B738/push_button/flaps_" .. get(P.toflaps)) end,
                    advice = function() return "Set Flap Lever " .. tostring(get(P.toflaps)) end,
                    confirm = function() return "Flap Lever checked and " .. get(P.toflaps) end,
                    nextStep = 'release_parking_brake'
                },
                ['release_parking_brake'] = {
                    check = function() return get(P.parkingbrakepos) == def.OFF end,
                    action = function() set(P.parkingbrakepos, def.OFF) end,
                    advice = "Release Parking Brake",
                    confirm = "Parking Brake checked and Released",
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
                    confirm = "Position Lights checked and Strobe",
                    nextStep = 'landing_lights_on'
                },
                ['landing_lights_on'] = {
                    check = function() return (not (get(P.llights1) == def.OFF) or (get(P.llights2) == def.OFF) or (get(P.llights3) == def.OFF) or (get(P.llights4) == def.OFF)) end,
                    action = function() P.togglelandinglights(def.ON) end,
                    advice = "Set Landing Lights On",
                    confirm = "Landing Lights checked and On",
                    nextStep = 'taxi_light_off'
                },
                ['taxi_light_off'] = {
                    check = function() return get(P.taxilight) == def.OFF end,
                    action = function() P.toggletaxilights(def.OFF) end,
                    advice = "Set Taxi Lights Off",
                    confirm = "Taxi Lights checked and Off",
                    nextStep = 'rwy_lights_off'
                },
                ['rwy_lights_off'] = {
                    check = function() return (get(P.rwylightl) == def.OFF) and (get(P.rwylightr) == def.OFF) end,
                    action = function() P.togglerwylights(def.OFF) end,
                    advice = "Set Runway Turnoff Lights Off",
                    confirm = "Runway Turnoff Lights checked and Off",
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
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return get(P.aplnavstat) == def.ON end,
                    advice = "Arm L NAV",
                    confirm = "L NAV checked and Armed",
                    nextStep = 'arm_vnav'
                },
                ['arm_vnav'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return get(P.apvnavstat) == def.ON end,
                    advice = "Arm V NAV",
                    confirm = "V NAV checked and Armed",
                    nextStep = 'arm_at'
                },
                ['arm_at'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF end,
                    check = function() return get(P.atarmpos) == def.ON end,
                    advice = "Arm Autothrottle",
                    confirm = "Autothrottle checked and Armed",
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
                    confirm = "Gear checked and Up",
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
                    confirm = "Gear Lever checked and Off",
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
                    confirm = "Auto Brake checked and Off",
                    nextStep = nil
                }
            }
        },
        [def.DURINGCLIMBPROCEDURE] = {
            number = 8,
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
                    check = function() 
                        return get(P.altitude) > get(P.fmctransalt) 
                    end,
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
                    nextStep = 'set_eng_bleed_on'
                },
                
                ['set_eng_bleed_on'] = {
                    check = function() return (get(P.bleedair1pos) == def.ON) and (get(P.bleedair2pos) == def.ON) end,
                    advice = "Set Both Engine Bleed Air On",
                    action = function() 
                        if (get(P.bleedair1pos) == def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_1") end
                        if (get(P.bleedair2pos) == def.OFF) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_2") end
                    end,
                    confirm = "Both Engine Bleed Air checked and On",
                    nextStep = 'set_packs_auto'
                },
                
                ['set_packs_auto'] = {
                    check = function() return (get(P.packlpos) == def.PACKAUTO) and (get(P.packrpos) == def.PACKAUTO) end,
                    advice = "Set Both Packs Auto",
                    action = function() 
                        set(P.packlpos, def.PACKAUTO)
                        set(P.packrpos, def.PACKAUTO) 
                    end,
                    confirm = "Both Packs checked and On",
                    nextStep = 'set_isol_valve_auto'
                },
                
                ['set_isol_valve_auto'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEAUTO end,
                    advice = "Set Isolation Valve Auto",
                    action = function() set(P.isolvalvepos, def.ISOLVALVEAUTO) end,
                    confirm = "Isolation Valve checked and Auto",
                    nextStep = 'set_apu_bleed_off'
                },
                
                ['set_apu_bleed_off'] = {
                    check = function() return get(P.bleedairapupos) == def.OFF end,
                    advice = "Switch A P U Bleed Air Off",
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    confirm = "A P U Bleed Air checked and Off",
                    nextStep = 'set_apu_off'
                },
                
                ['set_apu_off'] = {
                    check = function() return P.apurunning() == def.APUOFF end,
                    advice = "Switch A P U Off",
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up") end,
                    confirm = "A P U checked and Off",
                    nextStep = nil
                }
            }
        },
        [def.ALTITUDEA10000PROCEDURE] = {
            number = 9,
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
                    nextStep = 'announce_altitude'
                },
                
                ['announce_altitude'] = {
                    skipIf = function() 
                        return (get(P.fmccruisealt) <= P.configvalues[def.CONFIGLOWEAIRSPACEALT])
                    end,
                    action = function() 
                        if (get(P.altitude) < (P.configvalues[def.CONFIGLOWEAIRSPACEALT] + 1000)) then
                            P.commandtableentry(def.TEXT, "Passing " .. P.configvalues[def.CONFIGLOWEAIRSPACEALT] .. " Feet")
                        end
                    end,
                    nextStep = 'set_landing_lights_off'
                },
                
                ['set_landing_lights_off'] = {
                    check = function() 
                        return (get(P.llights1) == def.OFF) and (get(P.llights2) == def.OFF) and (get(P.llights3) == def.OFF) and (get(P.llights4) == def.OFF) 
                    end,
                    advice = "Set Landing Lights Off",
                    action = function() P.togglelandinglights(def.OFF) end,
                    confirm = "Landing Lights checked and Off",
                    nextStep = 'set_logo_lights_off'
                },
                
                ['set_logo_lights_off'] = {
                    check = function() return get(P.logolighton) == def.OFF end,
                    advice = "Set Logo Lights Off",
                    action = function() P.togglelogolight(def.OFF) end,
                    confirm = "Logo Lights checked and Off",
                    nextStep = 'set_seatbelts_off'
                },
                
                ['set_seatbelts_off'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF end,
                    advice = "Set Seatbeltsigns Off",
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNOFF) end,
                    confirm = "Seatbelt Signs checked and Off",
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
                        if (get(P.starterauto) == def.ON) then return "Both Starters checked and Auto"
                        else return "Both Starters checked and Continuous" end
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
            number = 10,
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
                        helpers.command_once("laminar/B738/button/fmc1_des")
                        set(P.speedrestr, 250) 
                    end,
                    confirm = "Speed 250 below 10000 Feet checked and set",
                    nextStep = 'speak_des_metar'
                },
                
                ['speak_des_metar'] = {
                    action = function() P.speakdesmetar() end,
                    nextStep = 'check_des_rwy'
                },
                
                ['check_des_rwy'] = {
                    action = function() 
                        if (get(P.desrwy) == "") then
                            P.commandtableentry(def.TEXT, "Set Destination Runway for " .. helpers.addspaces(get(P.desicao)))
                        end
                    end,
                    nextStep = 'check_rwy_suitability'
                },
                
                ['check_rwy_suitability'] = {
                    action = function()
                        if P.desmetar.metarfound then
                            if not helpers.shouldCheckRunwaySuitability(P.desmetar, get(P.desrwy)) then
                                P.commandtableentry(def.TEXT, "Check Destination Runway " .. helpers.addspaces(get(P.desrwy)))
                            end
                        end
                    end,
                    nextStep = 'wait_for_transition'
                },
                
                ['wait_for_transition'] = {
                    skipIf = function() return get(P.fmccruisealt) <= get(P.fmctranslvl) end,
                    check = function() 
                        local tl = get(P.fmctranslvl)
                        if (tl == nil) or (tl <= 0) or (tl > 25000) then return false end 
                        return (get(P.altitude) < tl) 
                    end,
                    confirm = "Passing Transition Level",
                    nextStep = 'set_qnh_local'
                },
                
                ['set_qnh_local'] = {
                    skipIf = function() return P.configvalues[def.CONFIGAUTOBARO] == def.OFF end,
                    check = function()
                        local tl = get(P.fmctranslvl)
                        if (tl == nil) or (tl <= 0) or (tl > 25000) then return false end 
                        if (get(P.altitude) >= tl) then return false end 

                        local baroinchtmp, _ = P.getlocalqnh(ARRIVAL)
                        if (get(P.barostd) == def.ON) then return false end 
                        if (helpers.roundnumber(math.abs(helpers.roundnumber(get(P.baropilot), 2) - baroinchtmp), 2) > 0.01) then return false end 
                        
                        return true 
                    end,
                    advice = function()
                        local tl = get(P.fmctranslvl)
                        if (tl == nil) or (tl <= 0) or (tl > 25000) then return false end 
                        if (get(P.altitude) >= tl) then return false end 
                        
                        local baroinchtmp, baropastmp = P.getlocalqnh(ARRIVAL)
                        if (get(P.baroinhpa) == def.ON) then
                            return "Set Q N H " .. helpers.addspaces(baropastmp)
                        else
                            return "Set Q N H " .. helpers.addspaces(baroinchtmp)
                        end
                    end,
                    action = function()
                        local tl = get(P.fmctranslvl)
                        if (tl == nil) or (tl <= 0) or (tl > 25000) then return end 
                        if (get(P.altitude) >= tl) then return end 
                        
                        local baroinchtmp, _ = P.getlocalqnh(ARRIVAL)
                        helpers.command_once("laminar/B738/EFIS_control/capt/push_button/std_press")
                        set(P.baropilot, baroinchtmp)
                    end,
                    confirm = function()
                        local baroinchtmp, baropastmp = P.getlocalqnh(ARRIVAL)
                        if (get(P.baroinhpa) == def.ON) then
                            return "Q N H checked and " .. helpers.addspaces(baropastmp)
                        else
                            return "Q N H checked and " .. helpers.addspaces(baroinchtmp)
                        end
                    end,
                    nextStep = nil
                }
            }
        },
        [def.ALTITUDEB10000PROCEDURE] = {
            number = 11,
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
                    nextStep = 'set_view_overhead'
                },
                
                ['set_view_overhead'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON end,
                    view = function() return P.configvalues[def.CONFIGVIEWOVERHEADPANEL] end,
                    nextStep = 'set_seatbelts_on'
                },
                
                ['set_seatbelts_on'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNON end,
                    advice = "Set Seatbeltsigns On",
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNON) end,
                    confirm = "Seatbeltsigns checked and On",
                    nextStep = 'set_landing_lights_on'
                },
                
                ['set_landing_lights_on'] = {
                    check = function() return (get(P.llights1) ~= def.OFF) and (get(P.llights2) ~= def.OFF) and (get(P.llights3) ~= def.OFF) and (get(P.llights4) ~= def.OFF) end,
                    advice = "Set Landing Lights On",
                    action = function() P.togglelandinglights(def.ON) end,
                    confirm = "Landing Lights checked and On",
                    nextStep = 'set_starters_flight'
                },
                
                ['set_starters_flight'] = {
                    check = function() return (get(P.starter1pos) == def.FLIGHT) and (get(P.starter2pos) == def.FLIGHT) end,
                    advice = "Set Both Starters Flight",
                    action = function() P.setstarter(def.BOTH, def.FLIGHT) end,
                    confirm = "Both Starters checked and Flight",
                    nextStep = 'set_logo_lights_on'
                },
                
                ['set_logo_lights_on'] = {
                    check = function() return get(P.logolighton) == def.ON end,
                    advice = "Set Logo Lights On",
                    action = function() P.togglelogolight(def.ON) end,
                    confirm = "Logo Lights checked and On",
                    nextStep = 'set_view_main_1'
                },
                
                ['set_view_main_1'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVIEWCHANGES] ~= def.ON end,
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'trigger_ils_proc'
                },

                ['trigger_ils_proc'] = {
                    action = function()
                        sasl.logDebug("ALTITUDEB10000: Attempting to trigger SETILSPROCEDURE.")
                        P.triggerprocedure(def.SETILSPROCEDURE, false) -- Trigger ILS setup
                    end,
                    check = function()
                        local procKey = def.SETILSPROCEDURE
                        local procData = P.proceduretable[procKey]
                        
                        if procData.set then 
                            sasl.logDebug("ALTITUDEB10000: Check PASSED for " .. procData.name .. " (.set is true)")
                            return true 
                        else
                            local targetLoop = P.loopStateTables[procData.loop]
                            local current_lock_name -- Variable für den Namen
                            
                            if targetLoop.lock == procKey then -- Ist die Zielprozedur aktiv?
                                 sasl.logDebug("ALTITUDEB10000: Waiting for " .. procData.name .. " (running in loop " .. procData.loop .. ")")
                            else -- Die Zielprozedur läuft nicht
                                 -- Sicherer Abruf des Namens
                                 if targetLoop.lock == def.NOPROCEDURE then
                                     current_lock_name = "NOPROCEDURE"
                                 else
                                     local locking_proc_data = P.proceduretable[targetLoop.lock]
                                     if locking_proc_data and locking_proc_data.name then
                                         current_lock_name = locking_proc_data.name
                                     else
                                         current_lock_name = "Unknown Procedure (" .. tostring(targetLoop.lock) .. ")"
                                     end
                                 end
                                 -- Jetzt die Log-Nachricht sicher erstellen
                                 sasl.logInfo("ALTITUDEB10000: Waiting for " .. procData.name .. ", but it is NOT running in loop " .. procData.loop .. " (Current lock: " .. current_lock_name .. "). Trigger might have failed.")
                            end
                            return false -- Weiter warten
                        end
                    end,
                    advice = nil, 
                    confirm = nil,
                    runActionInAdviceMode = true, -- WICHTIG: Flag für Trigger-Steps
                    nextStep = 'trigger_vref_proc' 
                },
                
                ['trigger_vref_proc'] = {
                    skipIf = function() return P.configvalues[def.CONFIGVREF30SET] == def.OFF end,
                    action = function()
                        if get(P.vref) == 0 then 
                            sasl.logDebug("ALTITUDEB10000: Attempting to trigger SETVREFPROCEDURE.")
                            P.triggerprocedure(def.SETVREFPROCEDURE, false) -- Trigger VREF setup
                        end
                    end,
                    check = function()
                        local procKey = def.SETVREFPROCEDURE 
                        local procData = P.proceduretable[procKey]
                        
                        if get(P.vref) ~= 0 then 
                            sasl.logDebug("ALTITUDEB10000: Check PASSED for VREF (Vref dataref is non-zero: " .. get(P.vref) .. ")")
                            return true 
                        end

                        if procData.set then 
                            sasl.logDebug("ALTITUDEB10000: Check PASSED for VREF (.set is true)")
                            return true 
                        else
                            local targetLoop = P.loopStateTables[procData.loop]
                            local current_lock_name -- Variable für den Namen

                            if targetLoop.lock == procKey then -- Ist die Zielprozedur aktiv?
                                 sasl.logDebug("ALTITUDEB10000: Waiting for " .. procData.name .. " (running in loop " .. procData.loop .. ")")
                            else -- Die Zielprozedur läuft nicht
                                 -- Sicherer Abruf des Namens
                                 if targetLoop.lock == def.NOPROCEDURE then
                                     current_lock_name = "NOPROCEDURE"
                                 else
                                     local locking_proc_data = P.proceduretable[targetLoop.lock]
                                     if locking_proc_data and locking_proc_data.name then
                                         current_lock_name = locking_proc_data.name
                                     else
                                         current_lock_name = "Unknown Procedure (" .. tostring(targetLoop.lock) .. ")"
                                     end
                                 end
                                 -- Jetzt die Log-Nachricht sicher erstellen
                                 sasl.logInfo("ALTITUDEB10000: Waiting for " .. procData.name .. ", but it is NOT running in loop " .. procData.loop .. " (Current lock: " .. current_lock_name .. "). Vref still 0. Trigger might have failed.")
                            end
                            return false -- Weiter warten
                        end
                    end,
                    advice = nil,
                    confirm = function() 
                        if get(P.vref) ~= 0 then 
                            return "V REF flaps " .. get(P.appflaps) .. " checked and " .. get(P.vref) 
                        else 
                            return false 
                        end
                    end,
                    runActionInAdviceMode = true, -- WICHTIG: Flag für Trigger-Steps
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
                        if get(P.autobrakepos) > def.AUTOBRAKEOFF then return true end
                        local autobrake = helpers.calcautobrake(get(P.vref), get(P.totalweightkgs), get(P.desrwylen), P.desmetar)
                        return get(P.autobrakepos) == autobrake
                    end,
                    advice = function()
                        if get(P.autobrakepos) > def.AUTOBRAKEOFF then return false end
                        local autobrake = helpers.calcautobrake(get(P.vref), get(P.totalweightkgs), get(P.desrwylen), P.desmetar)
                        if (autobrake < def.AUTOBRAKEMAX) then return "Set Auto Brake " .. tostring(autobrake - 1)
                        else return "Set Auto Brake Maximum" end
                    end,
                    action = function()
                        if get(P.autobrakepos) > def.AUTOBRAKEOFF then return end
                        local autobrake = helpers.calcautobrake(get(P.vref), get(P.totalweightkgs), get(P.desrwylen), P.desmetar)
                        P.setautobrake(autobrake)
                    end,
                    confirm = function()
                        local autobrake
                        if get(P.autobrakepos) > def.AUTOBRAKEOFF then autobrake = get(P.autobrakepos)
                        else autobrake = helpers.calcautobrake(get(P.vref), get(P.totalweightkgs), get(P.desrwylen), P.desmetar) end
                        
                        if (autobrake < def.AUTOBRAKEMAX) then return "Auto Brake checked and " .. tostring(autobrake - 1)
                        else return "Auto Brake checked and Maximum" end
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
            number = 12,
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
                    confirm = "Gear checked and Down",
                    nextStep = nil
                }
            }
        },
        [def.RADIOALTITUDEB1000PROCEDURE] = {
            number = 13,
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
                    confirm = "Speedbrakes checked and Armed",
                    nextStep = 'set_taxi_lights_on'
                },
                
                ['set_taxi_lights_on'] = {
                    check = function() return get(P.taxilight) ~= def.OFF end,
                    advice = "Set Taxi Lights On",
                    action = function() P.toggletaxilights(def.ON) end,
                    confirm = "Taxi Lights checked and On",
                    nextStep = 'set_rwy_lights_on'
                },
                
                ['set_rwy_lights_on'] = {
                    check = function() return (get(P.rwylightl) ~= def.OFF) and (get(P.rwylightr) ~= def.OFF) end,
                    advice = "Set Runway Turnoff Lights On",
                    action = function() P.togglerwylights(def.ON) end,
                    confirm = "Runway Turnoff Lights checked and On",
                    nextStep = 'set_mcp_altitude'
                },
                
                ['set_mcp_altitude'] = {
                    check = function()
                        local missedappalttmp = helpers.roundnumber((get(P.missedappalt) / 100)) * 100
                        if (missedappalttmp > 1000) then
                            return (missedappalttmp == get(P.mcpaltitude))
                        else
                            return false 
                        end
                    end,
                    advice = function()
                        local missedappalttmp = helpers.roundnumber((get(P.missedappalt) / 100)) * 100
                        if (missedappalttmp > 1000) then
                            return "Set M C P Altitude " .. helpers.addspaces(missedappalttmp)
                        else
                            return "Set Missed Approach Altitude"
                        end
                    end,
                    action = function()
                        local missedappalttmp = helpers.roundnumber((get(P.missedappalt) / 100)) * 100
                        if (missedappalttmp > 1000) then
                            set(P.mcpaltitude, missedappalttmp)
                        end
                    end,
                    confirm = function()
                        local missedappalttmp = helpers.roundnumber((get(P.missedappalt) / 100)) * 100
                        if (missedappalttmp > 1000) then
                            return "M C P Altitude checked and " .. helpers.addspaces(missedappalttmp)
                        end
                        return false
                    end,
                    nextStep = 'set_mcp_heading'
                },
                
                ['set_mcp_heading'] = {
                    check = function()
                        local headingrounded = nil
                        if (helpers.isvalidicao(get(P.desicao)) and helpers.isvalidrwy(get(P.desrwy)) and tonumber(get(P.desrwyheading))) then
                            headingrounded = helpers.roundnumber(get(P.desrwyheading))
                        end
                        local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.desicao), get(P.desrwy))
                        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
                            headingrounded = navrwyheading
                        end
                        
                        if (headingrounded and (get(P.aphdgselstat) == def.OFF)) then
                            return (headingrounded == get(P.mcpheading))
                        elseif not headingrounded then
                            return false
                        end
                        return true
                    end,
                    advice = function()
                        local headingrounded = nil
                        if (helpers.isvalidicao(get(P.desicao)) and helpers.isvalidrwy(get(P.desrwy)) and tonumber(get(P.desrwyheading))) then
                            headingrounded = helpers.roundnumber(get(P.desrwyheading))
                        end
                        local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.desicao), get(P.desrwy))
                        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
                            headingrounded = navrwyheading
                        end

                        if (headingrounded and (get(P.aphdgselstat) == def.OFF)) then
                            return "Set M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3))
                        elseif not headingrounded then
                            return "Set Missed Approach Heading"
                        end
                        return false
                    end,
                    action = function()
                        local headingrounded = nil
                        if (helpers.isvalidicao(get(P.desicao)) and helpers.isvalidrwy(get(P.desrwy)) and tonumber(get(P.desrwyheading))) then
                            headingrounded = helpers.roundnumber(get(P.desrwyheading))
                        end
                        local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.desicao), get(P.desrwy))
                        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
                            headingrounded = navrwyheading
                        end
                        
                        if (headingrounded and (get(P.aphdgselstat) == def.OFF)) then
                            set(P.mcpheading, headingrounded)
                        end
                    end,
                    confirm = function()
                        local headingrounded = nil
                        if (helpers.isvalidicao(get(P.desicao)) and helpers.isvalidrwy(get(P.desrwy)) and tonumber(get(P.desrwyheading))) then
                            headingrounded = helpers.roundnumber(get(P.desrwyheading))
                        end
                        local navrwyheading = helpers.getrwyheadingfromnavdata(P.navdatatable, get(P.desicao), get(P.desrwy))
                        if (navrwyheading and ((not headingrounded) or (headingrounded and (math.abs(headingrounded - navrwyheading) <= 3)))) then
                            headingrounded = navrwyheading
                        end
                        
                        if (headingrounded and (get(P.aphdgselstat) == def.OFF)) then
                            return "M C P Heading checked and " .. helpers.addspaces(helpers.padNumberWithZerosStrict(headingrounded, 3))
                        end
                        return false
                    end,
                    nextStep = 'set_gear_down'
                },
                
                ['set_gear_down'] = {
                    check = function() return get(P.gearhandlepos) == def.GEARDOWN end,
                    advice = "Set Gear Down",
                    action = function() set(P.gearhandlepos, def.GEARDOWN) end,
                    confirm = "Gear checked and Down",
                    nextStep = 'set_app_flaps'
                },
                
                ['set_app_flaps'] = {
                    check = function() return (get(P.appflapsset) == def.ON) or (get(P.appflaps) == 0) end,
                    advice = function() return "Set Flaps " .. tostring(get(P.appflaps)) end,
                    action = function() helpers.command_once("laminar/B738/push_button/flaps_" .. tostring(get(P.appflaps))) end,
                    confirm = function() return "Flaps checked and " .. tostring(get(P.appflaps)) end,
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
        [def.AFTERLANDINGPROCEDURE] = { 
            number = 14, 
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
                    sasl.logInfo("Flight state changed to TAXITOGATE.")
                    end,
                    nextStep = 'set_flightstate'
                },
                ['set_flightstate'] = {
                    action = function() 
                        P.flightstate = def.FLIGHTSTATETAXITOGATE
                        set(P.flightstatedr, P.flightstate)
                        if (P.configvalues[def.CONFIGVIEWCHANGES] == def.ON) then
                            P.setview(def.DEFAULTVIEW)
                            P.setview(P.configvalues[def.CONFIGVIEWOVERHEADPANEL])
                        end
                    end,
                    nextStep = 'landing_lights_off'
                },
                ['landing_lights_off'] = {
                    check = function() return (get(P.llights1) == def.OFF) and (get(P.llights2) == def.OFF) and (get(P.llights3) == def.OFF) and (get(P.llights4) == def.OFF) end,
                    action = function() P.togglelandinglights(def.OFF) end,
                    advice = "Set Landing Lights Off",
                    confirm = "Landing Lights checked and Off",
                    nextStep = 'taxi_lights_on'
                },
                ['taxi_lights_on'] = {
                    check = function() return get(P.taxilight) ~= def.OFF end,
                    action = function() P.toggletaxilights(def.ON) end,
                    advice = "Set Taxi Lights On",
                    confirm = "Taxi Lights checked and On",
                    nextStep = 'rwy_lights_off'
                },
                ['rwy_lights_off'] = {
                    check = function() return (get(P.rwylightl) == def.OFF) and (get(P.rwylightr) == def.OFF) end,
                    action = function() P.togglerwylights(def.OFF) end,
                    advice = "Set Runway Turnoff Lights Off",
                    confirm = "Runway Turnoff Lights checked and Off",
                    nextStep = 'pos_lights_steady'
                },
                ['pos_lights_steady'] = {
                    check = function() return get(P.positionlights) == def.POSLIGHTSSTEADY end,
                    action = function() P.togglepositionlights(def.POSLIGHTSSTEADY) end,
                    advice = "Set Position Lights Steady",
                    confirm = "Position Lights checked and Steady",
                    nextStep = 'probe_heat_off'
                },
                ['probe_heat_off'] = {
                    check = function() return (get(P.captainprobepos) == def.OFF) and (get(P.foprobepos) == def.OFF) end,
                    action = function() P.toggleprobeheat(def.OFF) end,
                    advice = "Set Probe Heat Off",
                    confirm = "Probe Heat checked and Off",
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
                    confirm = function() return "Transponder checked and " .. helpers.TransponderPostotring(get(P.transponderpos)) end,
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
                    confirm = "Flaps checked and Up",
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
                    confirm = "Both Flight Directors checked and Off",
                    nextStep = 'wx_off'
                },
                ['wx_off'] = {
                    check = function() return (get(P.efiswxpilotpos) == def.OFF) and (get(P.efiswxfopos) == def.OFF) end,
                    action = function() P.togglewx(def.OFF) end,
                    advice = "Set Both Weather Radars Off",
                    confirm = "Both Weather Radars checked and Off",
                    nextStep = 'terr_off'
                },
                ['terr_off'] = {
                    check = function() return (get(P.efisterrpilotpos) == def.OFF) and (get(P.efisterrfopos) == def.OFF) end,
                    action = function() P.toggleterr(def.OFF) end,
                    advice = "Set Both Terrain Radars Off",
                    confirm = "Both Terrain Radars checked and Off",
                    nextStep = 'autobrake_off'
                },
                ['autobrake_off'] = {
                    check = function() return get(P.autobrakepos) == def.AUTOBRAKEOFF end,
                    action = function() P.setautobrake(def.AUTOBRAKEOFF) end,
                    advice = "Set Auto Brake Off",
                    confirm = "Auto Brake checked and Off",
                    nextStep = 'ap_off'
                },
                ['ap_off'] = {
                    check = function() return get(P.aponstat) == def.OFF end,
                    action = function() set(P.aponstat, def.OFF) end,
                    advice = "Set Autopilot Off",
                    nextStep = 'ice_off'
                },
                ['ice_off'] = {
                    check = function() return (get(P.eng1heatpos) == def.OFF) and (get(P.eng2heatpos) == def.OFF) and (get(P.wingheatpos) == def.OFF) end,
                    action = function() P.iceprotection(def.OFF) end,
                    advice = "Set Anti Ice Off",
                    nextStep = 'master_caution'
                },
                ['master_caution'] = {
                    action = function() helpers.command_once("laminar/B738/push_button/master_caution1") end,
                    nextStep = nil
                }
            }
        },
        [def.ATPARKINGPOSITIONPROCEDURE] = { 
            number = 15, 
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
                        sasl.logInfo("Flight state changed to SHUTDOWN.")
                    end,
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = 'set_chocks'
                },
                ['set_chocks'] = {
                    check = function() return get(P.chockstatus) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/chock") end,
                    advice = "Set Chocks",
                    confirm = "Chocks checked and Set",
                    nextStep = 'check_night'
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
                    confirm = "Dome light checked and On",
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
                    advice = "Set Transponder Standby",
                    confirm = "Transponder checked and Standby",
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
                    confirm = "Taxi Lights checked and Off",
                    nextStep = 'logo_light_off'
                },
                ['logo_light_off'] = {
                    check = function() return get(P.logolighton) == def.OFF end,
                    action = function() P.togglelogolight(def.OFF) end,
                    advice = "Set Logo Lights Off",
                    confirm = "Logo Lights checked and Off",
                    nextStep = 'seatbelts_off'
                },
                ['seatbelts_off'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF end,
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNOFF) end,
                    advice = "Set Seatbeltsigns Off",
                    confirm = "Seatbeltsigns checked and Off",
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
                        if (get(P.starterauto) == def.ON) then return "Both Starters checked and Auto"
                        else return "Both Starters checked and Off" end
                    end,
                    nextStep = 'view_main_panel_final'
                },
                ['view_main_panel_final'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.TURNAROUNDENGINESHUTDOWNPROCEDURE] = { 
            number = 16, 
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
                    nextStep = 'check_power_source'
                },
                ['check_power_source'] = {
                    branch = function(loop, procData)
                        if (P.configvalues[def.CONFIGUSEGROUNDPOWER] == def.ON) and (get(P.gpuavailable) == def.ON) then
                            return 'check_gpu_power'
                        else
                            return 'start_apu'
                        end
                    end
                },
                ['check_gpu_power'] = {
                    check = function() return get(P.gpuon) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/gpu_dn") end,
                    advice = "Switch Ground Power On",
                    confirm = "G P U checked and On",
                    nextStep = 'view_throttle'
                },
                ['start_apu'] = {
                    check = function() return get(P.apustarterpos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn") end,
                    advice = "Start A P U",
                    confirm = nil,
                    nextStep = 'wait_initial_apu_spoolup'
                },
                ['wait_initial_apu_spoolup'] = {
                    check = function() return P.apurunning() > def.APUOFF end,
                    action = function()
                        if P.configvalues[def.CONFIGVOICEADVICEONLY] == def.OFF then
                            helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_dn")
                        end
                    end,
                    advice = nil,
                    confirm = "A P U Started, Running Up",
                    nextStep = 'wait_apu_ready'
                },
                ['wait_apu_ready'] = {
                    check = function() return P.apurunning() >= def.APUOFFBUS end,
                    advice = nil,
                    confirm = "A P U Running",
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
                    advice = "Switch A P U Generator On",
                    confirm = "A P U Generator checked and On",
                    nextStep = 'set_apu_bleed'
                },
                ['set_apu_bleed'] = {
                    check = function() return get(P.bleedairapupos) == def.ON end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Switch A P U Bleed Air On",
                    confirm = "A P U Bleed Air checked and On",
                    nextStep = 'set_isol_valve'
                },
                ['set_isol_valve'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEOPEN end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEOPEN) end,
                    advice = "Set Isolation Valve Open",
                    confirm = "Isolation Valve checked and Open",
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
                    nextStep = 'center_pumps_off'
                },
                ['center_pumps_off'] = {
                    check = function() return (get(P.centertanklswitch) == def.OFF) and (get(P.centertankrswitch) == def.OFF) end,
                    action = function() set(P.centertanklswitch, def.OFF); set(P.centertankrswitch, def.OFF) end,
                    advice = "Set Center Tank Fuel Pumps Off",
                    confirm = "Center Tank Fuel Pumps checked and Off",
                    nextStep = 'wing_pumps_off'
                },
                ['wing_pumps_off'] = {
                    check = function() return (get(P.lefttanklswitch) == def.OFF) and (get(P.lefttankrswitch) == def.OFF) and (get(P.righttanklswitch) == def.OFF) and (get(P.righttankrswitch) == def.OFF) end,
                    action = function() 
                        set(P.lefttanklswitch, def.OFF); set(P.lefttankrswitch, def.OFF)
                        set(P.righttanklswitch, def.OFF); set(P.righttankrswitch, def.OFF)
                    end,
                    advice = "Set Wing Tank Fuel Pumps Off",
                    confirm = "Wing Tank Fuel Pumps checked and Off",
                    nextStep = 'hyd_pumps_off'
                },
                ['hyd_pumps_off'] = {
                    check = function() return (get(P.hydro1pos) == def.OFF) and (get(P.hydro2pos) == def.OFF) end,
                    action = function() set(P.hydro1pos, def.OFF); set(P.hydro2pos, def.OFF) end,
                    advice = "Switch Both Hydraulic Pumps Off",
                    confirm = "Both Hydraulic Pumps checked and Off",
                    nextStep = 'elec_hyd_pumps_off'
                },
                ['elec_hyd_pumps_off'] = {
                    check = function() return (get(P.elechydro1pos) == def.OFF) and (get(P.elechydro2pos) == def.OFF) end,
                    action = function() set(P.elechydro1pos, def.OFF); set(P.elechydro2pos, def.OFF) end,
                    advice = "Switch Both Electrical Hydraulic Pumps Off",
                    confirm = "Both Electrical Hydraulic Pumps checked and Off",
                    nextStep = 'beacon_off'
                },
                ['beacon_off'] = {
                    check = function() return get(P.beaconlights) == def.OFF end,
                    action = function() P.togglecollisionlights(def.OFF) end,
                    advice = "Set Collision Lights Off",
                    confirm = "Collision lightset checked and Off",
                    nextStep = 'no_smoking_off'
                },
                ['no_smoking_off'] = {
                    check = function() return get(P.nosmokingsignpos) == def.NOSMOKINGSIGNOFF end,
                    action = function() P.setnosmokingsign(def.NOSMOKINGSIGNOFF) end,
                    advice = "Set No Smoking Signs Off",
                    confirm = "NO Smoking Signs checked and Off",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.FINALENGINESHUTDOWNPROCEDURE] = { 
            number = 17, 
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
                    nextStep = 'center_pumps_off'
                },
                ['center_pumps_off'] = {
                    check = function() return (get(P.centertanklswitch) == def.OFF) and (get(P.centertankrswitch) == def.OFF) end,
                    action = function() set(P.centertanklswitch, def.OFF); set(P.centertankrswitch, def.OFF) end,
                    advice = "Set Center Tank Fuel Pumps Off",
                    confirm = "Center Tank Fuel Pumps checked and Off",
                    nextStep = 'wing_pumps_off'
                },
                ['wing_pumps_off'] = {
                    check = function() return (get(P.lefttanklswitch) == def.OFF) and (get(P.lefttankrswitch) == def.OFF) and (get(P.righttanklswitch) == def.OFF) and (get(P.righttankrswitch) == def.OFF) end,
                    action = function() 
                        set(P.lefttanklswitch, def.OFF); set(P.lefttankrswitch, def.OFF)
                        set(P.righttanklswitch, def.OFF); set(P.righttankrswitch, def.OFF)
                    end,
                    advice = "Set Wing Tank Fuel Pumps Off",
                    confirm = "Wing Tank Fuel Pumps checked and Off",
                    nextStep = 'hyd_pumps_off'
                },
                ['hyd_pumps_off'] = {
                    check = function() return (get(P.hydro1pos) == def.OFF) and (get(P.hydro2pos) == def.OFF) end,
                    action = function() set(P.hydro1pos, def.OFF); set(P.hydro2pos, def.OFF) end,
                    advice = "Switch Both Hydraulic Pumps Off",
                    confirm = "Both Hydraulic Pumps checked and Off",
                    nextStep = 'elec_hyd_pumps_off'
                },
                ['elec_hyd_pumps_off'] = {
                    check = function() return (get(P.elechydro1pos) == def.OFF) and (get(P.elechydro2pos) == def.OFF) end,
                    action = function() set(P.elechydro1pos, def.OFF); set(P.elechydro2pos, def.OFF) end,
                    advice = "Switch Both Electrical Hydraulic Pumps Off",
                    confirm = "Both Electrical Hydraulic Pumps checked and Off",
                    nextStep = 'beacon_off'
                },
                ['beacon_off'] = {
                    check = function() return get(P.beaconlights) == def.OFF end,
                    action = function() P.togglecollisionlights(def.OFF) end,
                    advice = "Set Collision Lights Off",
                    confirm = "Collision lightset checked and Off",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.SHUTDOWNPROCEDURE] = { 
            number = 18, 
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
                    nextStep = 'irs_off'
                },
                ['irs_off'] = {
                    check = function() return (get(P.irsleftpos) == def.IRSOFF) and (get(P.irsrightpos) == def.IRSOFF) end,
                    action = function() P.setirs(def.BOTHIRS, def.IRSOFF) end,
                    advice = "Set Both I R S Off",
                    confirm = "Both I R S checked and Off",
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
                    confirm = "Yaw Damper checked and Off",
                    nextStep = 'apu_bleed_off'
                },
                ['apu_bleed_off'] = {
                    check = function() return get(P.bleedairapupos) == def.OFF end,
                    action = function() helpers.command_once("laminar/B738/toggle_switch/bleed_air_apu") end,
                    advice = "Switch A P U Bleed Air Off",
                    confirm = "A P U Bleed Air checked and Off",
                    nextStep = 'isol_valve_auto'
                },
                ['isol_valve_auto'] = {
                    check = function() return get(P.isolvalvepos) == def.ISOLVALVEAUTO end,
                    action = function() set(P.isolvalvepos, def.ISOLVALVEAUTO) end,
                    advice = "Set Isolation Valve Auto",
                    confirm = "Isolation Valve checked and Auto",
                    nextStep = 'packs_off'
                },
                ['packs_off'] = {
                    check = function() return (get(P.packlpos) == def.PACKOFF) and (get(P.packrpos) == def.PACKOFF) end,
                    action = function() set(P.packlpos, def.PACKOFF); set(P.packrpos, def.PACKOFF) end,
                    advice = "Set Both Packs Off",
                    confirm = "Both Packs checked and Off",
                    nextStep = 'eng_bleed_off'
                },
                ['eng_bleed_off'] = {
                    check = function() return (get(P.bleedair1pos) == def.OFF) and (get(P.bleedair2pos) == def.OFF) end,
                    action = function() 
                        if (get(P.bleedair1pos) == def.ON) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_1") end
                        if (get(P.bleedair2pos) == def.ON) then helpers.command_once("laminar/B738/toggle_switch/bleed_air_2") end
                    end,
                    advice = "Set Both Engine Bleed Air Off",
                    confirm = "Both Engine Bleed Air checked and Off",
                    nextStep = 'trim_air_off'
                },
                ['trim_air_off'] = {
                    check = function() return get(P.trimairpos) == def.OFF end,
                    action = function() set(P.trimairpos, def.OFF) end,
                    advice = "Set Trim Air Off",
                    confirm = "Trim Air checked and Off",
                    nextStep = 'window_heat_off'
                },
                ['window_heat_off'] = {
                    check = function() return (get(P.wheatlfwdpos) == def.OFF) and (get(P.wheatrfwdpos) == def.OFF) and (get(P.wheatlsidepos) == def.OFF) and (get(P.wheatrsidepos) == def.OFF) end,
                    action = function() P.togglewindowheat(def.OFF) end,
                    advice = "Set Window Heat Off",
                    confirm = "Window Heat checked and Off",
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
                    advice = "Switch Ground Power Off",
                    confirm = "Ground Power checked and Off",
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
                    advice = "Switch A P U Generator Off",
                    confirm = "A P U Generator checked and Off",
                    nextStep = 'apu_off'
                },
                ['apu_off'] = {
                    check = function() return P.apurunning() == def.APUOFF end,
                    action = function() helpers.command_once("laminar/B738/spring_toggle_switch/APU_start_pos_up") end,
                    advice = "Switch A P U Off",
                    confirm = "A P U checked and Off",
                    nextStep = 'pos_lights_off'
                },
                ['pos_lights_off'] = {
                    check = function() return get(P.positionlights) == def.POSLIGHTSOFF end,
                    action = function() P.togglepositionlights(def.POSLIGHTSOFF) end,
                    advice = "Set Position Lights Off",
                    confirm = "Position LIghts checked and Off",
                    nextStep = 'seatbelts_off'
                },
                ['seatbelts_off'] = {
                    check = function() return get(P.seatbeltsignpos) == def.SEATBELTSIGNOFF end,
                    action = function() P.setseatbeltsign(def.SEATBELTSIGNOFF) end,
                    advice = "Set Seatbeltsigns Off",
                    confirm = "Seatbeltsigns checked and Off",
                    nextStep = 'no_smoking_off'
                },
                ['no_smoking_off'] = {
                    check = function() return get(P.nosmokingsignpos) == def.NOSMOKINGSIGNOFF end,
                    action = function() P.setnosmokingsign(def.NOSMOKINGSIGNOFF) end,
                    advice = "Set No Smoking Signs Off",
                    confirm = "NO Smoking Signs checked and Off",
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
                    confirm = "Emergency Lights checked and Off",
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
                    confirm = "Domelight checked and Off",
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
                    confirm = "Battery checked and Off",
                    nextStep = 'view_main_panel'
                },
                ['view_main_panel'] = {
                    view = function() return P.configvalues[def.CONFIGVIEWMAINPANEL] end,
                    nextStep = nil
                }
            }
        },
        [def.SETILSPROCEDURE] = { number = 19, name = "Set ILS", cycable = false, speakname = false, steps = 11, set = false, procedurefunction = P.setilssteps, loop = 3, prerequisite = nil, allowedState = nil, requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH }, skipCondition = nil, repeatable = true },
        [def.SETVREFPROCEDURE] = { number = 20, name = "Set V Ref", cycable = false, speakname = false, steps = 4, set = false, procedurefunction = P.setvrefsteps, loop = 3, prerequisite = nil, allowedState = nil, requiredFlightstate = { def.FLIGHTSTATECRUISE, def.FLIGHTSTATEAPPROACH }, skipCondition = nil, repeatable = true },
        [def.SETTOFLAPSPROCEDURE] = { number = 21, name = "Set Takeoff Flaps", cycable = false, speakname = false, steps = 4, set = false, procedurefunction = P.settoflapssteps, loop = 3, prerequisite = def.COCKPITINITPROCEDURE, allowedState = def.GROUNDONLY, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = nil },
        [def.TESTPROCEDURE] = { number = 22, name = "Test", cycable = false, speakname = false, steps = 47, set = false, procedurefunction = P.teststeps, loop = 1, prerequisite = nil, allowedState = nil, requiredFlightstate = def.FLIGHTSTATEPREFLIGHT, skipCondition = nil }
    }

    return true
end

return M