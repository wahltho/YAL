local VR = {}

local def = require("definitions")
local helpers = require("helpers")

--------------------------------------------------------------------------------------------------------------
local function simple_check(current, temp_name, P)
    if current ~= P[temp_name] then
        P[temp_name] = current
        return true
    end
    return false
end

local function debounce_check(current, temp1_name, temp2_name, P)
    if current ~= P[temp1_name] then
        if current ~= P[temp2_name] then
            P[temp2_name] = current
        else
            P[temp1_name] = current
            return true
        end
    end
    return false
end

local function paired_check(c1, t1, c2, t2, P, isDebounced)
    local changed1, changed2 = false, false
    if isDebounced then
        local t1_2, t2_2 = t1 .. "2", t2 .. "2"
        if c1 ~= P[t1] then
            if c1 ~= P[t1_2] then P[t1_2] = c1 else changed1 = true end
        end
        if c2 ~= P[t2] then
            if c2 ~= P[t2_2] then P[t2_2] = c2 else changed2 = true end
        end
    else
        if c1 ~= P[t1] then changed1 = true end
        if c2 ~= P[t2] then changed2 = true end
    end

    if not changed1 and not changed2 then return "none" end
    if changed1 and changed2 and (c1 == c2) then return "both" end
    if changed1 and not changed2 then return "one" end
    if not changed1 and changed2 then return "two" end
    if changed1 and changed2 then return "one_and_two" end
    return "none"
end

local unpack = table.unpack or unpack
local function call_format(format_fn, args)
    local ok, result = pcall(function() return format_fn(unpack(args)) end)
    if ok then return result end
    if #args > 1 then
        ok, result = pcall(function() return format_fn(args[1]) end)
        if ok then return result end
    end
    return nil
end

--------------------------------------------------------------------------------------------------------------
VR.config = {
    -- ## Simple Checks ##
    { dataref = "pausetod", temp = "pausetodtemp", check = simple_check, format = function(v) return v == def.ON and "Pause at Top of Descent On" or "Pause at Top of Descent Off" end },
    { dataref = "simfreezed", temp = "simfreezedtemp", check = simple_check, format = function(v) return v == def.ON and "Sim Freeze On" or "Sim Freeze Off" end },
    { dataref = "chockstatus", temp = "chockstatustmp", check = simple_check, format = function(v) return v == def.ON and "Chocks Set" or "Chocks Removed" end },
    { dataref = "aponstat", temp = "aponstattemp", check = simple_check, format = function(v) if v == def.OFF then return "Autopilot Off" end end },
    { dataref = "taxilight", temp = "taxilighttemp", check = simple_check, format = function(v) return v ~= def.OFF and "Taxi Lights On" or "Taxi Lights Off" end },
    { dataref = "beaconlights", temp = "beaconlightstemp", check = simple_check, format = function(v) return v == def.ON and "Collision Lights On" or "Collision Lights Off" end },
    { dataref = "logolighton", temp = "logolightontemp", check = simple_check, format = function(v) return v == def.ON and "Logo Light On" or "Logo Light Off" end },
    { dataref = "transponderpos", temp = "transponderpostemp", check = simple_check, format = function(v) return "Transponder " .. helpers.TransponderPostotring(v) end },
    { dataref = "yawdamperswitch", temp = "yawdamperswitchtemp", check = simple_check, format = function(v) return v == def.ON and "Yaw Damper On" or "Yaw Damper Off" end },
    { dataref = "battery", temp = "batterytemp", check = simple_check, format = function(v) return v == def.ON and "Battery On" or "Battery Off" end },
    { dataref = "gpuon", temp = "gpuontemp", check = simple_check, format = function(v) return v == def.ON and "Ground Power On" or "Ground Power Off" end },
    { dataref = "parkingbrakepos", temp = "parkingbrakepostemp", check = simple_check, format = function(v) return v == def.ON and "Parking Brake Set" or "Parking Brake Off" end },
    { dataref = "trimairpos", temp = "trimairpostemp", check = simple_check, format = function(v) return v == def.ON and "Trim Air On" or "Trim Air Off" end },
    { dataref = "lrecircfanpos", temp = "lrecircfanpostemp", check = simple_check, format = function(v) return v == def.ON and "Left Recirculating Fan On" or "Left Recirculating Fan Off" end },
    { dataref = "rrecircfanpos", temp = "rrecircfanpostemp", check = simple_check, format = function(v) return v == def.ON and "Right Recirculating Fan On" or "Right Recirculating Fan Off" end },
    { dataref = "bleedairapupos", temp = "bleedairapupostemp", check = simple_check, format = function(v) return v == def.ON and "A P U Bleed Air On" or "A P U Bleed Air Off" end },
    { dataref = "apustarterpos", temp = "apustarterpostemp", check = simple_check, format = function(v, P) if P.apurunning() > def.APUOFF then return "A P U Started" else return "A P U Shutting Down" end end },
    { dataref = "gearhandlepos", temp = "gearhandlepostemp", check = simple_check, format = function(v)
        if v == def.GEARUP then return "Landing Gear Up" elseif v == def.GEAROFF then return "Landing Gear Lever Off" elseif v == def.GEARDOWN then return "Landing Gear Down" end
    end },
    { dataref = "positionlights", temp = "positionlightstemp", check = simple_check, format = function(v)
        if v == def.POSLIGHTSOFF then return "Position Lights Off" elseif v == def.POSLIGHTSSTEADY then return "Position Lights Steady" elseif v == def.POSLIGHTSSTROBE then return "Position Lights Strobe" end
    end },
    { dataref = "emergencylights", temp = "emergencylightstemp", check = simple_check, format = function(v)
        if v == def.EMERGLIGHTSOFF then return "Emergency Lights Off" elseif v == def.EMERGLIGHTSARMED then return "Emergency Lights Armed" elseif v == def.EMERGLIGHTSON then return "Emergency Lights On" end
    end },
    { dataref = "seatbeltsignpos", temp = "seatbeltsignpostemp", check = simple_check, format = function(v)
        if v == def.SEATBELTSIGNOFF then return "Seatbelt Sign Off" elseif v == def.SEATBELTSIGNAUTO then return "Seatbelt Sign Auto" elseif v == def.SEATBELTSIGNON then return "Seatbelt Sign On" end
    end },
    { dataref = "nosmokingsignpos", temp = "nosmokingsignpostemp", check = simple_check, format = function(v)
        if v == def.NOSMOKINGSIGNOFF then return "No Smoking Sign Off" elseif v == def.NOSMOKINGSIGNAUTO then return "No Smoking Sign Auto" elseif v == def.NOSMOKINGSIGNON then return "No Smoking Sign On" end
    end },
    { dataref = "domelightpos", temp = "domelightpostemp", check = simple_check, format = function(v)
        if v == def.DOMELIGHTOFF then return "Dome Light Off" elseif v == def.DOMELIGHTDIM then return "Dome Light Dim" elseif v == def.DOMELIGHTBRIGHT then return "Dome Light Bright" end
    end },
    { dataref = "isolvalvepos", temp = "isolvalvepostemp", check = simple_check, format = function(v)
        if v == def.ISOLVALVECLOSE then return "Isolation Valve Closed" elseif v == def.ISOLVALVEAUTO then return "Isolation Valve Auto" elseif v == def.ISOLVALVEOPEN then return "Isolation Valve Open" end
    end },
    { dataref = "apgscapturedstat", temp = "apgscapturedstattemp", check = simple_check, format = function(v) if v == def.CAPTURED then return "Glide Slope Captured" end end },
    { dataref = "aploccapturedstat", temp = "aploccapturedstattemp", check = simple_check, format = function(v) if v == def.CAPTURED then return "Localizer Captured" end end },
    { dataref = "apfacgscapturedstat", temp = "apfacgscapturedstattemp", check = simple_check, format = function(v) if v == def.CAPTURED then return "Glide Path Captured" end end },
    { dataref = "apfacloccapturedstat", temp = "apfacloccapturedstattemp", check = simple_check, format = function(v) if v == def.CAPTURED then return "F A C Localizer Captured" end end },
    { dataref = "aplpvgscapturedstat", temp = "aplpvgscapturedstattemp", check = simple_check, condition = function(P) return get(P.lpvinstalled) == def.ON end, format = function(v) if v == def.CAPTURED then return "L P V Glide Slope Captured" end end },
    { dataref = "aplpvloccapturedstat", temp = "aplpvloccapturedstattemp", check = simple_check, condition = function(P) return get(P.lpvinstalled) == def.ON end, format = function(v) if v == def.CAPTURED then return "L P V Localizer Captured" end end },
    { dataref = "apglsgscapturedstat", temp = "apglsgscapturedstattemp", check = simple_check, condition = function(P) return get(P.lpvinstalled) == def.ON end, format = function(v) if v == def.CAPTURED then return "G L S Glide Slope Captured" end end },
    { dataref = "apglsloccapturedstat", temp = "apglsloccapturedstattemp", check = simple_check, condition = function(P) return get(P.lpvinstalled) == def.ON end, format = function(v) if v == def.CAPTURED then return "G L S Localizer Captured" end end },

    -- ## Debounce Checks ##
    { dataref = "cabincruisealt", temp1 = "cabincruisealttemp", temp2 = "cabincruisealttemp2", check = debounce_check, format = function(v) return "Cabin Cruise Altitude " .. tostring(v) end },
    { dataref = "cabinlandingalt", temp1 = "cabinlandingalttemp", temp2 = "cabinlandingalttemp2", check = debounce_check, format = function(v) return "Cabin Landing Altitude " .. tostring(v) end },
    { dataref = "mcpheading", temp1 = "mcpheadingtemp", temp2 = "mcpheadingtemp2", check = debounce_check, format = function(v) return "M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(v, 3)) end },
    { dataref = "mcppilotcourse", temp1 = "mcppilotcoursetemp", temp2 = "mcppilotcoursetemp2", check = debounce_check, format = function(v) return "M C P Pilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(v, 3)) end },
    { dataref = "mcpcopilotcourse", temp1 = "mcpcopilotcoursetemp", temp2 = "mcpcopilotcoursetemp2", check = debounce_check, format = function(v) return "M C P Copilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(v, 3)) end },
    { dataref = "transpondercode", temp1 = "transpondercodetemp", temp2 = "transpondercodetemp2", check = debounce_check, format = function(v) return "Transponder Code " .. helpers.addspaces(v) end },
    { dataref = "bankanglepos", temp1 = "bankanglepostemp", temp2 = "bankanglepostemp2", check = debounce_check, format = function(v) return "Bank Angle " .. helpers.getbankanglestring(v) end },
    { dataref = "flapleverpos", temp1 = "flapleverpostemp", temp2 = "flapleverpostemp2", check = debounce_check, format = function(v)
        local pos_map = { [def.FLAPSUP]=0, [def.FLAPS1]=1, [def.FLAPS2]=2, [def.FLAPS5]=5, [def.FLAPS10]=10, [def.FLAPS15]=15, [def.FLAPS25]=25, [def.FLAPS30]=30, [def.FLAPS40]=40 }
        local pos = pos_map[v]
        if pos == 0 then return "Flaps Up" else return "Flaps " .. tostring(pos) end
    end },
    { dataref = "speedbrakelever", temp1 = "speedbrakelevertemp", temp2 = "speedbrakelevertemp2", check = debounce_check, format = function(v)
        if v == def.SPEEDBRAKEDOWN then return "Speedbrake Down"
        elseif v == def.SPEEDBRAKEARMED then return "Speedbrake Armed"
        elseif v >= def.SPEEDBRAKEUP then return "Speedbrake Up" end
    end },
    { dataref = "autobrakepos", temp1 = "autobrakepostemp", temp2 = "autobrakepostemp2", check = debounce_check, format = function(v)
        if v == def.AUTOBRAKERTO then return "Auto Brake R T O" elseif v == def.AUTOBRAKEOFF then return "Auto Brake Off" elseif v == def.AUTOBRAKE1 then return "Auto Brake 1"
        elseif v == def.AUTOBRAKE2 then return "Auto Brake 2" elseif v == def.AUTOBRAKE3 then return "Auto Brake 3" elseif v == def.AUTOBRAKEMAX then return "Auto Brake Maximum" end
    end },
    { dataref = "autobrakedisarm", temp1 = "autobrakedisarmtemp", temp2 = "autobrakedisarmtemp2", check = debounce_check, format = function(v) if v == def.ON then return "Auto Brake Disarmed" end end },
    { dataref = "dhpilot", temp1 = "dhpilottemp", temp2 = "dhpilottemp2", check = debounce_check, format = function(v)
        if (v == -1) or (v == -1001) then return "Pilot Decision Altitude Reset" else return "Pilot Decision Altitude " .. tostring(helpers.roundnumber(v)) end
    end },
    { dataref = "mcpaltitude", temp1 = "mcpaltitudetemp", temp2 = "mcpaltitudetemp2", check = debounce_check, format = function(v, P) 
        if v == get(P.fmccruisealt) then return "M C P set to Cruise Altitude " .. helpers.addspaces(v)
        else return "M C P Altitude " .. helpers.addspaces(v) end
    end },
    { dataref = "mcpspeed", temp1 = "mcpspeedtemp", temp2 = "mcpspeedtemp2", check = debounce_check,
      condition = function(P) return (get(P.atarmpos) == def.OFF) or (get(P.atspeedstat) == def.ON) or (get(P.atspeedintvstat) == def.ON) end,
      format = function(v, P)
          local speed_str = (v < 1) and helpers.roundnumber(v, 2) or helpers.roundnumber(v)
          if ((P.flightstate > def.FLIGHTSTATECRUISE) and (v == get(P.vref))) then return "M C P Speed set to V REF " .. tostring(speed_str)
          else return "M C P Speed " .. tostring(speed_str) end
      end
    },
    { dataref = "mcpvsspeed", temp1 = "mcpvsspeedtemp", temp2 = "mcpvsspeedtemp2", check = debounce_check,
      condition = function(P) return (get(P.mcpvsspeed) ~= 0) and (get(P.apalthldstat) ~= def.ON) and (get(P.apvnavstat) ~= def.ON) end,
      format = function(v) return "M C P Vertical Speed " .. tostring(v) end
    },

    -- ## Paired Switch Checks (Simple) ##
    { dr1 = "fdpilotpos", t1 = "fdpilotpostemp", dr2 = "fdfopos", t2 = "fdfopostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Flightdirectors "..s elseif type=="one"then return "Pilot Flightdirector "..s elseif type=="two"then return "Copilot Flightdirector "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "centertanklswitch", t1 = "centertanklswitchtemp", dr2 = "centertankrswitch", t2 = "centertankrswitchtemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Center Tank Fuel Pumps "..s elseif type=="one"then return "Left Center Tank Fuel Pump "..s elseif type=="two"then return "Right Center Tank Fuel Pump "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "lefttanklswitch", t1 = "lefttanklswitchtemp", dr2 = "lefttankrswitch", t2 = "lefttankrswitchtemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Left Wing Tank Fuel Pumps "..s elseif type=="one"then return "Left Wing Tank After Fuel Pump "..s elseif type=="two"then return "Left Wing Tank Forward Fuel Pump "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "righttanklswitch", t1 = "righttanklswitchtemp", dr2 = "righttankrswitch", t2 = "righttankrswitchtemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Right Wing Tank Fuel Pumps "..s elseif type=="one"then return "Right Wing Tank Forward Fuel Pump "..s elseif type=="two"then return "Right Wing Tank After Fuel Pump "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "mixture1pos", t1 = "mixture1postemp", dr2 = "mixture2pos", t2 = "mixture2postemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"Idle"or"Cutoff" if type=="both"then return "Both Engine Fuel Levers "..s elseif type=="one"then return "Engine 1 Fuel Lever "..s elseif type=="two"then return "Engine 2 Fuel Lever "..((v2==def.ON)and"Idle"or"Cutoff")end end },
    { dr1 = "gen1pos", t1 = "gen1postemp", dr2 = "gen2pos", t2 = "gen2postemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Generators "..s elseif type=="one"then return "Generator 1 "..s elseif type=="two"then return "Generator 2 "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "captainprobepos", t1 = "captainprobepostemp", dr2 = "foprobepos", t2 = "foprobepostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Probe Heat "..s elseif type=="one"then return "Left Probe Heat "..s elseif type=="two"then return "Right Probe Heat "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "wheatlfwdpos", t1 = "wheatlfwdpostemp", dr2 = "wheatlsidepos", t2 = "wheatlsidepostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Pilot Window Heat "..s elseif type=="one"then return "Pilot Forward Window Heat "..s elseif type=="two"then return "Pilot Side Window Heat "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "wheatrfwdpos", t1 = "wheatrfwdpostemp", dr2 = "wheatrsidepos", t2 = "wheatrsidepostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Copilot Window Heat "..s elseif type=="one"then return "Copilot Forward Window Heat "..s elseif type=="two"then return "Copilot Side Window Heat "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "packlpos", t1 = "packlpostemp", dr2 = "packrpos", t2 = "packrpostemp", check = paired_check,
      format = function(type, v1, v2)
          local state_map={[def.PACKOFF]="Off",[def.PACKAUTO]="Auto",[def.PACKHIGH]="High"}
          if type=="both"then return "Both Packs "..state_map[v1] elseif type=="one"then return "Left Pack "..state_map[v1] elseif type=="two"then return "Right Pack "..state_map[v2] end
      end },
    { dr1 = "bleedair1pos", t1 = "bleedair1postemp", dr2 = "bleedair2pos", t2 = "bleedair2postemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Engine Bleed Air "..s elseif type=="one"then return "Engine 1 Bleed Air "..s elseif type=="two"then return "Engine 2 Bleed Air "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "hydro1pos", t1 = "hydro1postemp", dr2 = "hydro2pos", t2 = "hydro2postemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Hydraulic Pumps "..s elseif type=="one"then return "Hydraulic Pump 1 "..s elseif type=="two"then return "Hydraulic Pump 2 "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "elechydro1pos", t1 = "elechydro1postemp", dr2 = "elechydro2pos", t2 = "elechydro2postemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Electrical Hydraulic Pumps "..s elseif type=="one"then return "Electrical Hydraulic Pump 2 "..s elseif type=="two"then return "Electrical Hydraulic Pump 1 "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "rwylightl", t1 = "rwylightltemp", dr2 = "rwylightr", t2 = "rwylightrtemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both Runway Turnoff Lights "..s elseif type=="one"then return "Left Runway Turnoff Light "..s elseif type=="two"then return "Right Runway Turnoff Light "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "starter1pos", t1 = "starter1postemp", dr2 = "starter2pos", t2 = "starter2postemp", check = paired_check,
      format = function(type, v1, v2, P)
          local function get_state(v) if v==def.GROUND then return "Ground" elseif v==def.AUTO then return(get(P.starterauto)==def.ON)and "Auto"or"Off" elseif v==def.CONT then return "Continuous" elseif v==def.FLIGHT then return "Flight"end;return""end
          if type=="both"then return "Both Starters "..get_state(v1)elseif type=="one"then return "Engine 1 Starter "..get_state(v1)elseif type=="two"then return"Engine 2 Starter "..get_state(v2)end
      end },
    { dr1 = "efisdatapilotpos", t1 = "efisdatapilotpostemp", dr2 = "efisdatafopos", t2 = "efisdatafopostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both E F I S Data "..s elseif type=="one"then return "Pilot E F I S Data "..s elseif type=="two"then return "Copilot E F I S Data "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "efisfixpilotpos", t1 = "efisfixpilotpostemp", dr2 = "efisfixfopos", t2 = "efisfixfopostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both E F I S Waypoint "..s elseif type=="one"then return "Pilot E F I S Waypoint "..s elseif type=="two"then return"Copilot E F I S Waypoint "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "efisairportpilotpos", t1 = "efisairportpilotpostemp", dr2 = "efisairportfopos", t2 = "efisairportfopostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both E F I S Airport "..s elseif type=="one"then return "Pilot E F I S Airport "..s elseif type=="two"then return"Copilot E F I S Airport "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "efispospilotpos", t1 = "efispospilotpostemp", dr2 = "efisposfopos", t2 = "efisposfopostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both E F I S Position "..s elseif type=="one"then return "Pilot E F I S Position "..s elseif type=="two"then return"Copilot E F I S Position "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "efisvorpilotpos", t1 = "efisvorpilotpostemp", dr2 = "efisvorfopos", t2 = "efisvorfopostemp", check = paired_check,
      format = function(type, v1, v2) local s=(v1==def.ON)and"On"or"Off" if type=="both"then return "Both E F I S Station "..s elseif type=="one"then return "Pilot E F I S Station "..s elseif type=="two"then return"Copilot E F I S Station "..((v2==def.ON)and"On"or"Off")end end },
    { dr1 = "efiswxpilotpos", t1 = "efiswxpilotpostemp", dr2 = "efiswxfopos", t2 = "efiswxfopostemp", check = paired_check,
      format = function(type, v1, v2, P)
          if type=="both"then if v1==def.ON then P.commandtableentry(def.TEXT,"Both Weather Radars On")elseif get(P.efisterrpilotpos)==def.OFF then P.commandtableentry(def.TEXT,"Both Weather Radars Off")end
          elseif type=="one"then if v1==def.ON then P.commandtableentry(def.TEXT,"Pilot Weather Radar On")elseif get(P.efisterrpilotpos)==def.OFF then P.commandtableentry(def.TEXT,"Pilot Weather Radar Off")end
          elseif type=="two"then if v2==def.ON then P.commandtableentry(def.TEXT,"Copilot Weather Radar On")elseif get(P.efisterrfopos)==def.OFF then P.commandtableentry(def.TEXT,"Copilot Weather Radar Off")end end
      end },
    { dr1 = "efisterrpilotpos", t1 = "efisterrpilotpostemp", dr2 = "efisterrfopos", t2 = "efisterrfopostemp", check = paired_check,
      format = function(type, v1, v2, P)
          if type=="both"then if v1==def.ON then P.commandtableentry(def.TEXT,"Both Terrain Radars On")elseif get(P.efiswxpilotpos)==def.OFF then P.commandtableentry(def.TEXT,"Both Terrain Radars Off")end
          elseif type=="one"then if v1==def.ON then P.commandtableentry(def.TEXT,"Pilot Terrain Radar On")elseif get(P.efiswxpilotpos)==def.OFF then P.commandtableentry(def.TEXT,"Pilot Terrain Radar Off")end
          elseif type=="two"then if v2==def.ON then P.commandtableentry(def.TEXT,"Copilot Terrain Radar On")elseif get(P.efiswxfopos)==def.OFF then P.commandtableentry(def.TEXT,"Copilot Terrain Radar Off")end end
      end },
    { dr1 = "fadec1on", t1 = "fadec1ontemp", dr2 = "fadec2on", t2 = "fadec2ontemp", check = paired_check,
      format = function(type, v1, v2)
          local function state(v) return (v == def.ON) and "On" or "Off" end
          if type=="both"then return "Both E E C " .. state(v1)
          elseif type=="one"then return "Engine 1 E E C " .. state(v1)
          elseif type=="two"then return "Engine 2 E E C " .. state(v2) end
      end },

    -- ## Paired Switch Checks (Debounced) ##
    { dr1 = "irsleftpos", t1 = "irsleftpostemp", dr2 = "irsrightpos", t2 = "irsrightpostemp", check = paired_check, isDebounced = true,
      format = function(type, v1, v2)
          local function get_state(v) if v==def.IRSOFF then return"Off"elseif v==def.IRSALIGN then return"Align"elseif v==def.IRSNAV then return"Nav"elseif v==def.IRSATT then return"Attention"end;return""end
          if type=="both"then return"Both I R S "..get_state(v1)elseif type=="one"then return"Left I R S "..get_state(v1)elseif type=="two"then return"Right I R S "..get_state(v2)end
      end },
    { dr1 = "lwiperpos", t1 = "lwiperpostemp", dr2 = "rwiperpos", t2 = "rwiperpostemp", check = paired_check, isDebounced = true,
      condition = function(P) return P.configvalues[def.CONFIGAUTOWIPER] ~= def.ON end,
      format = function(type, v1, v2)
          local function get_state(v) if v==def.WIPEROFF then return"Off"elseif v==def.WIPERINT then return"Interval"elseif v==def.WIPERLOW then return"Low"elseif v==def.WIPERHIGH then return"High"end;return""end
          if type=="both"then return"Both Wipers "..get_state(v1)elseif type=="one"then return"Left Wiper "..get_state(v1)elseif type=="two"then return"Right Wiper "..get_state(v2)end
      end },
}

--------------------------------------------------------------------------------------------------------------
local function complex_check(P)
    -- Fuel Check (with threshold)
    if (math.abs(get(P.totalfuellbs) - P.totalfuellbstemp) > 200) then
        if (get(P.totalfuellbs) ~= P.totalfuellbstemp2) then P.totalfuellbstemp2 = get(P.totalfuellbs)
        else
            if (get(P.fuelunit) == def.LBS) then P.commandtableentry(def.TEXT, "Fuel quantity " .. tostring(get(P.totalfuellbs)) .. "L B S")
            else P.commandtableentry(def.TEXT, "Fuel quantity " .. tostring(get(P.totalfuelkgs)) .. "K G") end
            P.totalfuellbstemp = get(P.totalfuellbs)
        end
    else P.totalfuellbstemp = get(P.totalfuellbs) end

    -- Baro Check (multiple dataref dependencies)
    if ((get(P.baropilot) ~= P.baropilottemp) or (get(P.barostd) ~= P.barostdtemp)) then
        if (get(P.baropilot) ~= P.baropilottemp2) then P.baropilottemp2 = get(P.baropilot)
        else
            if ((get(P.barostd) == def.ON) and (get(P.barostd) ~= P.barostdtemp)) then P.commandtableentry(def.TEXT, "Q N H Standard")
            else
                if (get(P.baroinhpa) == def.ON) then
                    local qnhValue = helpers.convertpressure(get(P.baropilot))
                    local qnhText = helpers.formatQnhValue(qnhValue, true)
                    if qnhText then
                        P.commandtableentry(def.TEXT, "Q N H " .. helpers.addspaces(qnhText))
                    end
                else
                    local qnhText = helpers.formatQnhValue(get(P.baropilot), false)
                    if qnhText then
                        P.commandtableentry(def.TEXT, "Q N H " .. helpers.addspaces(qnhText))
                    end
                end
            end
            P.baropilottemp = get(P.baropilot); P.baropilottemp2 = get(P.baropilot); P.barostdtemp = get(P.barostd)
        end
    end
    
    -- Landing Lights (variant-aware check)
    local ledVariant = (get(P.ledlightsvariant) == def.ON)
    local threshold = def.LEDLLIGHTSOFF or 0
    local current1 = get(P.llights1)
    local current2 = get(P.llights2)
    local current3 = get(P.llights3)
    local current4 = get(P.llights4)

    local temp1 = P.llights1temp
    local temp2 = P.llights2temp
    local temp3 = P.llights3temp
    local temp4 = P.llights4temp

    local changed = (current1 ~= temp1) or (current2 ~= temp2) or (current3 ~= temp3) or (current4 ~= temp4)
    if changed then
        if ledVariant then
            -- LED: nur 1 und 4 relevant
            if (current1 <= threshold and current4 <= threshold) then
                P.commandtableentry(def.TEXT, "Landing Lights Off")
            elseif (temp1 <= threshold and temp4 <= threshold) and (current1 > threshold and current4 > threshold) then
                P.commandtableentry(def.TEXT, "Landing Lights On")
            end
        else
            -- Halogen: alle vier relevant
            if (current1 == def.OFF and current2 == def.OFF and current3 == def.OFF and current4 == def.OFF) then
                P.commandtableentry(def.TEXT, "Landing Lights Off")
            elseif (temp1 == def.OFF and temp2 == def.OFF and temp3 == def.OFF and temp4 == def.OFF)
                and (current1 ~= def.OFF and current2 ~= def.OFF and current3 ~= def.OFF and current4 ~= def.OFF) then
                P.commandtableentry(def.TEXT, "Landing Lights On")
            end
        end
        P.llights1temp = current1
        P.llights2temp = current2
        P.llights3temp = current3
        P.llights4temp = current4
    end
    
    -- Reversers Check (state transition)
    if ((get(P.reverser1pos) ~= P.reverser1postemp) or (get(P.reverser2pos) ~= P.reverser2postemp)) then
        if ((get(P.reverser1pos) ~= P.reverser1postemp) and (get(P.reverser2pos) ~= P.reverser2postemp) and (get(P.reverser1pos) == get(P.reverser2pos))) then
            if get(P.reverser1pos) == def.OFF and P.reverser1postemp ~= def.OFF then P.commandtableentry(def.TEXT, "Both Reversers Off")
            elseif get(P.reverser1pos) ~= def.OFF and P.reverser1postemp == def.OFF then P.commandtableentry(def.TEXT, "Both Reversers On") end
        else
            if get(P.reverser1pos) ~= P.reverser1postemp then
                if get(P.reverser1pos) == def.OFF and P.reverser1postemp ~= def.OFF then P.commandtableentry(def.TEXT, "Reverser 1 Off")
                elseif get(P.reverser1pos) ~= def.OFF and P.reverser1postemp == def.OFF then P.commandtableentry(def.TEXT, "Reverser 1 On") end
            end
            if get(P.reverser2pos) ~= P.reverser2postemp then
                if get(P.reverser2pos) == def.OFF and P.reverser2postemp ~= def.OFF then P.commandtableentry(def.TEXT, "Reverser 2 Off")
                elseif get(P.reverser2pos) ~= def.OFF and P.reverser2postemp == def.OFF then P.commandtableentry(def.TEXT, "Reverser 2 On") end
            end
        end
        P.reverser1postemp = get(P.reverser1pos); P.reverser2postemp = get(P.reverser2pos)
    end

    -- APU Generator Check (complex condition)
    if ((helpers.roundnumber(get(P.announcsourceoff1),1) ~= P.announcsourceoff1temp) or (helpers.roundnumber(get(P.announcsourceoff2),1) ~= P.announcsourceoff2temp)) then
        if (P.apurunning() > def.APUSTARTED) then
            if ((get(P.apupowerbus1) == get(P.apupowerbus2)) and (get(P.announcsourceoff1) == get(P.announcsourceoff2)) and (get(P.announcsourceoff1) ~= P.announcsourceoff1temp) and (get(P.announcsourceoff2) ~= P.announcsourceoff2temp)) then
                if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then P.commandtableentry(def.TEXT, "A P U Generator On")
                elseif not ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then P.commandtableentry(def.TEXT, "A P U Generator Off") end
            else
                if (get(P.announcsourceoff1) ~= P.announcsourceoff1temp) then
                    if ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then P.commandtableentry(def.TEXT, "A P U Generator 1 On")
                    elseif not ((get(P.apupowerbus1) == def.ON) and (get(P.announcsourceoff1) == def.OFF)) then P.commandtableentry(def.TEXT, "A P U Generator 1 Off") end
                end
                if (get(P.announcsourceoff2) ~= P.announcsourceoff2temp) then
                    if ((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then P.commandtableentry(def.TEXT, "A P U Generator 2 On")
                    elseif not ((get(P.apupowerbus2) == def.ON) and (get(P.announcsourceoff2) == def.OFF)) then P.commandtableentry(def.TEXT, "A P U Generator 2 Off") end
                end
            end
        end
        P.announcsourceoff1temp = helpers.roundnumber(get(P.announcsourceoff1),1); P.announcsourceoff2temp = helpers.roundnumber(get(P.announcsourceoff2),1)
    end

    -- MMR / NAV Frequency Check
    if (get(P.mmrinstalled) == def.ON) then
        local cptMode = get(P.mmrcptactmode)
        local foMode = get(P.mmrfoactmode)
        local cptVal = get(P.mmrcptactvalue)
        local foVal = get(P.mmrfoactvalue)

        local function formatMMR(mode, val)
            if mode == def.MMRILS or mode == def.MMRLOC or mode == def.MMRVOR then
                return helpers.addspaces(helpers.formatILSFrequency(val))
            else
                return tostring(val)
            end
        end

        -- Mode/Freq change announcements
        if (cptMode ~= P.mmrcptactmodetemp) or (cptVal ~= P.mmrcptactvaluetemp) or
           (foMode ~= P.mmrfoactmodetemp) or (foVal ~= P.mmrfoactvaluetemp) then

            local sameMode = (cptMode == foMode)
            local sameVal = (cptVal == foVal)

            if sameMode and sameVal then
                if cptMode == def.MMRILS then
                    P.commandtableentry(def.TEXT, "Both M M R I L S " .. formatMMR(cptMode, cptVal))
                elseif cptMode == def.MMRGLS then
                    P.commandtableentry(def.TEXT, "Both M M R G L S Channel " .. formatMMR(cptMode, cptVal))
                elseif cptMode == def.MMRLPV then
                    P.commandtableentry(def.TEXT, "Both M M R L P V Channel " .. formatMMR(cptMode, cptVal))
                else
                    P.commandtableentry(def.TEXT, "Both M M R " .. formatMMR(cptMode, cptVal))
                end
            else
                -- Captain
                if (cptMode ~= P.mmrcptactmodetemp) or (cptVal ~= P.mmrcptactvaluetemp) then
                    if cptMode == def.MMRILS then
                        P.commandtableentry(def.TEXT, "Captain M M R I L S " .. formatMMR(cptMode, cptVal))
                    elseif cptMode == def.MMRGLS then
                        P.commandtableentry(def.TEXT, "Captain M M R G L S Channel " .. formatMMR(cptMode, cptVal))
                    elseif cptMode == def.MMRLPV then
                        P.commandtableentry(def.TEXT, "Captain M M R L P V Channel " .. formatMMR(cptMode, cptVal))
                    elseif cptMode == def.MMRVOR then
                        P.commandtableentry(def.TEXT, "Captain M M R V O R " .. formatMMR(cptMode, cptVal))
                    end
                end
                -- Copilot
                if (foMode ~= P.mmrfoactmodetemp) or (foVal ~= P.mmrfoactvaluetemp) then
                    if foMode == def.MMRILS then
                        P.commandtableentry(def.TEXT, "Copilot M M R I L S " .. formatMMR(foMode, foVal))
                    elseif foMode == def.MMRGLS then
                        P.commandtableentry(def.TEXT, "Copilot M M R G L S Channel " .. formatMMR(foMode, foVal))
                    elseif foMode == def.MMRLPV then
                        P.commandtableentry(def.TEXT, "Copilot M M R L P V Channel " .. formatMMR(foMode, foVal))
                    elseif foMode == def.MMRVOR then
                        P.commandtableentry(def.TEXT, "Copilot M M R V O R " .. formatMMR(foMode, foVal))
                    end
                end
            end

            P.mmrcptactmodetemp = cptMode
            P.mmrcptactvaluetemp = cptVal
            P.mmrfoactmodetemp = foMode
            P.mmrfoactvaluetemp = foVal
        end
    else
        if ((get(P.nav1freq) ~= P.nav1freqtemp) or (get(P.nav2freq) ~= P.nav2freqtemp)) then
            if (get(P.nav1freq) == get(P.nav2freq)) then
                P.commandtableentry(def.TEXT, "Both N A V " .. helpers.addspaces(helpers.formatILSFrequency(get(P.nav1freq))))
                P.nav1freqtemp = get(P.nav1freq); P.nav2freqtemp = get(P.nav2freq)
            else
                if (get(P.nav1freq) ~= P.nav1freqtemp) then
                    P.commandtableentry(def.TEXT, "N A V 1 " .. helpers.addspaces(helpers.formatILSFrequency(get(P.nav1freq)))); P.nav1freqtemp = get(P.nav1freq)
                end
                if (get(P.nav2freq) ~= P.nav2freqtemp) then
                    P.commandtableentry(def.TEXT, "N A V 2 " .. helpers.addspaces(helpers.formatILSFrequency(get(P.nav2freq)))); P.nav2freqtemp = get(P.nav2freq)
                end
            end
        end
    end

    -- Autopilot & Autothrottle Mode Logic (highly conditional)
    if simple_check(get(P.apcmdastat), "apcmdastattemp", P) then
        if get(P.apcmdastat) == def.ON then P.commandtableentry(def.TEXT, "Command A On")
        elseif get(P.aponstat) == def.ON then P.commandtableentry(def.TEXT, "Command A Off") end
    end
    if simple_check(get(P.apcmdbstat), "apcmdbstattemp", P) then
        if get(P.apcmdbstat) == def.ON then
            P.commandtableentry(def.TEXT, "Command B On")
            if get(P.apcmdastat) == def.ON and (get(P.apgscapturedstat) ~= def.OFF or get(P.aploccapturedstat) ~= def.OFF) then
                if get(P.mmrinstalled) == def.ON then
                    if (get(P.mmrcptactvalue) ~= get(P.mmrfoactvalue)) or (get(P.mmrcptactmode) ~= get(P.mmrfoactmode)) or (get(P.mcppilotcourse) ~= get(P.mcpcopilotcourse)) then
                        P.commandtableentry(def.TEXT, "Warning Pilot and Copilot M M R Disagree")
                    end
                elseif (get(P.nav1freq) ~= get(P.nav2freq)) or (get(P.mcppilotcourse) ~= get(P.mcpcopilotcourse)) then
                    P.commandtableentry(def.TEXT, "Warning Pilot and Copilot NAV Disagree")
                end
            end
        elseif get(P.aponstat) == def.ON then P.commandtableentry(def.TEXT, "Command B Off") end
    end
    if simple_check(get(P.apvnavstat), "apvnavstattemp", P) then
        if get(P.apvnavstat) == def.ON then P.commandtableentry(def.TEXT, get(P.aponstat) == def.ON and "V NAV On" or "V NAV Armed")
        elseif (get(P.aponstat) == def.ON and get(P.apgscapturedstat) ~= def.CAPTURED and get(P.aploccapturedstat) ~= def.CAPTURED and get(P.apalthldstat) ~= def.ON and get(P.apvsstat) ~= def.ON and get(P.aplvlchgstat) ~= def.ON) then P.commandtableentry(def.TEXT, "V NAV Off") end
    end
    if simple_check(get(P.aplnavstat), "aplnavstattemp", P) then
        if get(P.aplnavstat) == def.ON then P.commandtableentry(def.TEXT, get(P.aponstat) == def.ON and "L NAV On" or "L NAV Armed")
        elseif (get(P.aponstat) == def.ON and get(P.aploccapturedstat) ~= def.CAPTURED and get(P.aphdgselstat) ~= def.ON and get(P.apappstat) ~= def.ON and get(P.apvorlocstat) ~= def.ON) then P.commandtableentry(def.TEXT, "L NAV Off") end
    end
    if simple_check(get(P.apappstat), "apappstattemp", P) then
        if get(P.apappstat) == def.ON then
             if (get(P.aponstat) == def.ON) then
                if ((get(P.apgscapturedstat) == def.ARMED) and (get(P.aploccapturedstat) == def.ARMED)) then P.commandtableentry(def.TEXT, "Approach Armed")
                elseif ((get(P.aplpvgscapturedstat) == def.ARMED) and (get(P.aplpvloccapturedstat) == def.ARMED)) then P.commandtableentry(def.TEXT, "L P V Approach Armed")
                elseif ((get(P.apglsgscapturedstat) == def.ARMED) and (get(P.apglsloccapturedstat) == def.ARMED)) then P.commandtableentry(def.TEXT, "G L S Approach Armed")
                elseif ((get(P.apfacgscapturedstat) == def.ARMED) and (get(P.apfacloccapturedstat) == def.ARMED)) then P.commandtableentry(def.TEXT, "F A C Approach Armed") end
             else P.commandtableentry(def.TEXT, "Approach Armed") end
        elseif (get(P.aponstat) == def.ON and get(P.apgscapturedstat) ~= def.CAPTURED and get(P.aploccapturedstat) ~= def.CAPTURED and get(P.aphdgselstat) ~= def.ON and get(P.aplnavstat) ~= def.ON) then P.commandtableentry(def.TEXT, "Approach Off") end
    end
    if simple_check(get(P.apvorlocstat), "apvorlocstattemp", P) then
        if get(P.apvorlocstat) == def.ON then P.commandtableentry(def.TEXT, get(P.aponstat) == def.ON and "V O R Localizer On" or "V O R Localizer Armed")
        elseif get(P.aponstat) == def.ON then P.commandtableentry(def.TEXT, "V O R Localizer Off") end
    end
    if simple_check(get(P.apalthldstat), "apalthldstattemp", P) then
        if get(P.apalthldstat) == def.ON then
            if get(P.aponstat) == def.ON then P.commandtableentry(def.TEXT, "Altitude Hold On, Altitude " .. tostring(get(P.mcpaltitude)))
            else P.commandtableentry(def.TEXT, "Altitude Hold Armed") end
        elseif (get(P.aponstat) == def.ON and get(P.apvsstat) ~= def.ON and get(P.aplvlchgstat) ~= def.ON and get(P.apgscapturedstat) ~= def.CAPTURED and get(P.apvnavstat) ~= def.ON) then P.commandtableentry(def.TEXT, "Altitude Hold Off") end
    end
    if simple_check(get(P.aphdgselstat), "aphdgselstattemp", P) then
        if get(P.aphdgselstat) == def.ON then
            if get(P.aponstat) == def.ON then P.commandtableentry(def.TEXT, "Heading Select On, Heading " .. tostring(helpers.padNumberWithZerosStrict(get(P.mcpheading),3)))
            else P.commandtableentry(def.TEXT, "Heading Select Armed") end
        elseif (get(P.aponstat) == def.ON and get(P.aplnavstat) ~= def.ON and get(P.apvorlocstat) ~= def.ON and get(P.aploccapturedstat) ~= def.CAPTURED) then P.commandtableentry(def.TEXT, "Heading Select Off") end
    end
    if simple_check(get(P.apvsstat), "apvsstattemp", P) then
        if get(P.apvsstat) == def.ON then P.commandtableentry(def.TEXT, get(P.aponstat) == def.ON and "Vertical Speed On" or "Vertical Speed Armed")
        elseif (get(P.aponstat) == def.ON and get(P.mcpvsspeed) ~= 0 and get(P.apalthldstat) ~= def.ON and get(P.apvnavstat) ~= def.ON and get(P.aplvlchgstat) ~= def.ON) then P.commandtableentry(def.TEXT, "Vertical Speed Off") end
    end
    if simple_check(get(P.aplvlchgstat), "aplvlchgstattemp", P) then
        if get(P.aplvlchgstat) == def.ON then P.commandtableentry(def.TEXT, get(P.aponstat) == def.ON and "Level Change On" or "Level Change Armed")
        elseif (get(P.aponstat) == def.ON and get(P.mcpvsspeed) ~= 0 and get(P.apalthldstat) ~= def.ON and get(P.apvnavstat) ~= def.ON and get(P.apvsstat) ~= def.ON) then P.commandtableentry(def.TEXT, "Level Change Off") end
    end
    if simple_check(get(P.atn1stat), "atn1stattemp", P) then
        if get(P.atn1stat) == def.ON and get(P.airgroundsensor) == def.ON then P.commandtableentry(def.TEXT, get(P.atarmpos) == def.ON and "N 1 On" or "N 1 Armed")
        elseif get(P.atn1stat) == def.OFF and get(P.airgroundsensor) == def.ON then P.commandtableentry(def.TEXT, "N 1 Off") end
    end
    if simple_check(get(P.atspeedstat), "atspeedstattemp", P) then
        if (get(P.atspeedstat) == def.ON and get(P.apgscapturedstat) ~= def.CAPTURED and get(P.apvsstat) ~= def.ON and get(P.aplvlchgstat) ~= def.ON) then
            P.commandtableentry(def.TEXT, get(P.atarmpos) == def.ON and "Speed On" or "Speed Armed")
        elseif (get(P.atspeedstat) == def.OFF and get(P.atarmpos) == def.ON and get(P.atn1stat) ~= def.ON and get(P.apvnavstat) ~= def.ON) then P.commandtableentry(def.TEXT, "Speed Off") end
    end
    if simple_check(get(P.atspeedintvstat), "atspeedintvstattemp", P) then
        if get(P.atspeedintvstat) == def.ON then P.commandtableentry(def.TEXT, get(P.atarmpos) == def.ON and "Speed Intervention On" or "Speed Intervention Armed")
        elseif (get(P.atarmpos) == def.ON and get(P.atn1stat) ~= def.ON and get(P.atspeedstat) ~= def.ON) then P.commandtableentry(def.TEXT, "Speed Intervention Off") end
    end
    if simple_check(get(P.apflarestat), "apflarestattemp", P) or simple_check(get(P.aprolloutstat), "aprolloutstattemp", P) then
        if get(P.apflarestat) == def.ON and get(P.aprolloutstat) == def.ON then P.commandtableentry(def.TEXT, "Autoland Armed") end
    end
    
end

--------------------------------------------------------------------------------------------------------------
function VR.initialize(P)
    helpers.logInfoTS("YAL: Initializing all variables for voice readback.")
    
    -- Initialize all variables from the config table
    for _, config in ipairs(VR.config) do
        if config.dataref then
            local val = get(P[config.dataref])
            if config.dataref == "speedbrakelever" then val = helpers.roundnumber(val, 1) end
            if config.temp then P[config.temp] = val end
            if config.temp1 then P[config.temp1] = val; P[config.temp2] = val end
        end
        if config.dr1 then
            local val1, val2 = get(P[config.dr1]), get(P[config.dr2])
            P[config.t1], P[config.t2] = val1, val2
            if config.isDebounced then P[config.t1 .. "2"], P[config.t2 .. "2"] = val1, val2 end
        end
    end

    -- Initialize temp vars for the legacy complex_check function
    -- Fuel & Baro
    P.totalfuellbstemp = get(P.totalfuellbs); P.totalfuellbstemp2 = get(P.totalfuellbs)
    P.barostdtemp = get(P.barostd); P.baropilottemp = get(P.baropilot); P.baropilottemp2 = get(P.baropilot)

    -- Lights
    P.llights1temp = get(P.llights1); P.llights2temp = get(P.llights2); P.llights3temp = get(P.llights3); P.llights4temp = get(P.llights4)

    -- Systems
    P.reverser1postemp = get(P.reverser1pos); P.reverser2postemp = get(P.reverser2pos)
    P.announcsourceoff1temp = helpers.roundnumber(get(P.announcsourceoff1), 1); P.announcsourceoff2temp = helpers.roundnumber(get(P.announcsourceoff2), 1)

    -- Navigation (NAV / MMR)
    P.nav1freqtemp = get(P.nav1freq); P.nav2freqtemp = get(P.nav2freq)
    P.mmrcptactmodetemp = get(P.mmrcptactmode); P.mmrcptactvaluetemp = get(P.mmrcptactvalue)
    P.mmrfoactmodetemp = get(P.mmrfoactmode); P.mmrfoactvaluetemp = get(P.mmrfoactvalue)
    P.mmrcptstdbymodetemp = get(P.mmrcptstdbymode); P.mmrcptstdbymodetemp2 = get(P.mmrcptstdbymode)
    P.mmrfostdbymodetemp = get(P.mmrfostdbymode); P.mmrfostdbymodetemp2 = get(P.mmrfostdbymode)

    -- Autopilot Modes
    P.apcmdastattemp = get(P.apcmdastat); P.apcmdbstattemp = get(P.apcmdbstat)
    P.apvnavstattemp = get(P.apvnavstat); P.aplnavstattemp = get(P.aplnavstat); P.apappstattemp = get(P.apappstat)
    P.apvorlocstattemp = get(P.apvorlocstat); P.apalthldstattemp = get(P.apalthldstat); P.aphdgselstattemp = get(P.aphdgselstat)
    P.apvsstattemp = get(P.apvsstat); P.aplvlchgstattemp = get(P.aplvlchgstat)
    P.apflarestattemp = get(P.apflarestat); P.aprolloutstattemp = get(P.aprolloutstat)

    -- Autothrottle Modes
    P.atn1stattemp = get(P.atn1stat); P.atspeedstattemp = get(P.atspeedstat); P.atspeedintvstattemp = get(P.atspeedintvstat)
end

--------------------------------------------------------------------------------------------------------------
function VR.run(P)
    for _, config in ipairs(VR.config) do
        if not (config.condition and not config.condition(P)) then
            if config.check == simple_check then
                local current = get(P[config.dataref])
                if simple_check(current, config.temp, P) then
                    local msg = call_format(config.format, { current, P })
                    if msg then P.commandtableentry(def.TEXT, msg) end
                end
            elseif config.check == debounce_check then
                local current = get(P[config.dataref]); if config.dataref == "speedbrakelever" then current = helpers.roundnumber(current, 1) end
                if debounce_check(current, config.temp1, config.temp2, P) then
                    local msg = call_format(config.format, { current, P })
                    if msg then P.commandtableentry(def.TEXT, msg) end
                end
            elseif config.check == paired_check then
                local c1, c2 = get(P[config.dr1]), get(P[config.dr2])
                local type = paired_check(c1, config.t1, c2, config.t2, P, config.isDebounced)
                if type ~= "none" then
                    local msg = call_format(config.format, { type, c1, c2, P })
                    if msg then P.commandtableentry(def.TEXT, msg) end
                    if type=="both"or type=="one"or type=="one_and_two"then P[config.t1]=c1;if config.isDebounced then P[config.t1.."2"]=c1 end end
                    if type=="both"or type=="two"or type=="one_and_two"then P[config.t2]=c2;if config.isDebounced then P[config.t2.."2"]=c2 end end
                end
            end
        else -- Condition not met, update temps
            if config.dataref then local c=get(P[config.dataref]);if config.temp then P[config.temp]=c end;if config.temp1 then P[config.temp1]=c;P[config.temp2]=c end end
        end
    end
    complex_check(P)
    return true
end

return VR
