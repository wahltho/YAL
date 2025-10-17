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

--------------------------------------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------------------------------------
local function complex_check(P)

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

    return true
end

--------------------------------------------------------------------------------------------------------------
VR.config = {
    { dataref = "pausetod", temp = "pausetodtemp", check = simple_check, format = function(v) return v == def.ON and "Pause at Top of Descent On" or "Pause at Top of Descent Off" end },
    { dataref = "simfreezed", temp = "simfreezedtemp", check = simple_check, format = function(v) return v == def.ON and "Sim Freeze On" or "Sim Freeze Off" end },
    { dataref = "chockstatus", temp = "chockstatustmp", check = simple_check, format = function(v) return v == def.ON and "Chocks Set" or "Chocks Removed" end },
    { dataref = "aponstat", temp = "aponstattemp", check = simple_check, format = function(v, P) if v == def.OFF then return "Autopilot Off" end end },
    { dataref = "atarmpos", temp = "atarmpostemp", check = simple_check, format = function(v) return v == def.ON and "Autothrottle Armed" or "Autothrottle Off" end },
    { dataref = "taxilight", temp = "taxilighttemp", check = simple_check, format = function(v) return v ~= def.OFF and "Taxi Lights On" or "Taxi Lights Off" end },
    { dataref = "beaconlights", temp = "beaconlightstemp", check = simple_check, format = function(v) return v == def.ON and "Collision Lights On" or "Collision Lights Off" end },
    { dataref = "logolighton", temp = "logolightontemp", check = simple_check, format = function(v) return v == def.ON and "Logo Light On" or "Logo Light Off" end },
    { dataref = "transponderpos", temp = "transponderpostemp", check = simple_check, format = function(v) return "Transponder " .. helpers.TransponderPostotring(v) end },
    { dataref = "yawdamperswitch", temp = "yawdamperswitchtemp", check = simple_check, format = function(v) return v == def.ON and "Yaw Damper On" or "Yaw Damper Off" end },
    { dataref = "battery", temp = "batterytemp", check = simple_check, format = function(v) return v == def.ON and "Battery On" or "Battery Off" end },
    { dataref = "gpuon", temp = "gpuontemp", check = simple_check, format = function(v) return v == def.ON and "Ground Power On" or "Ground Power Off" end },
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
    { dataref = "trimairpos", temp = "trimairpostemp", check = simple_check, format = function(v) return v == def.ON and "Trim Air On" or "Trim Air Off" end },
    { dataref = "lrecircfanpos", temp = "lrecircfanpostemp", check = simple_check, format = function(v) return v == def.ON and "Left Recirculating Fan On" or "Left Recirculating Fan Off" end },
    { dataref = "rrecircfanpos", temp = "rrecircfanpostemp", check = simple_check, format = function(v) return v == def.ON and "Right Recirculating Fan On" or "Right Recirculating Fan Off" end },
    { dataref = "bleedairapupos", temp = "bleedairapupostemp", check = simple_check, format = function(v) return v == def.ON and "A P U Bleed Air On" or "A P U Bleed Air Off" end },
    { dataref = "apustarterpos", temp = "apustarterpostemp", check = simple_check, format = function(v, P) if P.apurunning() > def.APUOFF then return "A P U Started" else return "A P U Shutting Down" end end },
    { dataref = "parkingbrakepos", temp = "parkingbrakepostemp", check = simple_check, format = function(v) return v == def.ON and "Parking Brake Set" or "Parking Brake Off" end },

    { dataref = "cabincruisealt", temp1 = "cabincruisealttemp", temp2 = "cabincruisealttemp2", check = debounce_check, format = function(v) return "Cabin Cruise Altitude " .. tostring(v) end },
    { dataref = "cabinlandingalt", temp1 = "cabinlandingalttemp", temp2 = "cabinlandingalttemp2", check = debounce_check, format = function(v) return "Cabin Landing Altitude " .. tostring(v) end },
    { dataref = "mcpheading", temp1 = "mcpheadingtemp", temp2 = "mcpheadingtemp2", check = debounce_check, format = function(v) return "M C P Heading " .. helpers.addspaces(helpers.padNumberWithZerosStrict(v, 3)) end },
    { dataref = "mcpaltitude", temp1 = "mcpaltitudetemp", temp2 = "mcpaltitudetemp2", check = debounce_check, format = function(v, P) 
        if v == get(P.fmccruisealt) then return "M C P set to Cruise Altitude " .. helpers.addspaces(v)
        else return "M C P Altitude " .. helpers.addspaces(v) end
    end },
    { dataref = "mcppilotcourse", temp1 = "mcppilotcoursetemp", temp2 = "mcppilotcoursetemp2", check = debounce_check, format = function(v) return "M C P Pilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(v, 3)) end },
    { dataref = "mcpcopilotcourse", temp1 = "mcpcopilotcoursetemp", temp2 = "mcpcopilotcoursetemp2", check = debounce_check, format = function(v) return "M C P Copilot Course " .. helpers.addspaces(helpers.padNumberWithZerosStrict(v, 3)) end },
    { dataref = "dhpilot", temp1 = "dhpilottemp", temp2 = "dhpilottemp2", check = debounce_check, format = function(v)
        if (v == -1) or (v == -1001) then return "Pilot Decision Altitude Reset" else return "Pilot Decision Altitude " .. tostring(helpers.roundnumber(v)) end
    end },
    { dataref = "transpondercode", temp1 = "transpondercodetemp", temp2 = "transpondercodetemp2", check = debounce_check, format = function(v) return "Transponder Code " .. helpers.addspaces(v) end },
    { dataref = "bankanglepos", temp1 = "bankanglepostemp", temp2 = "bankanglepostemp2", check = debounce_check, format = function(v) return "Bank Angle " .. helpers.getbankanglestring(v) end },
    { dataref = "flapleverpos", temp1 = "flapleverpostemp", temp2 = "flapleverpostemp2", check = debounce_check, format = function(v)
        local pos = helpers.convflaplevertoflappos(v); if pos == 0 then return "Flaps Up" else return "Flaps " .. tostring(pos) end
    end },
    { dataref = "speedbrakelever", temp1 = "speedbrakelevertemp", temp2 = "speedbrakelevertemp2", check = debounce_check, format = function(v)
        if v == def.SPEEDBRAKEDOWN then return "Speedbrake Down"
        elseif v == def.SPEEDBRAKEARMED then return "Speedbrake Armed"
        elseif v >= def.SPEEDBRAKEUP then return "Speedbrake Up" end
    end },
    { dataref = "autobrakepos", temp1 = "autobrakepostemp", temp2 = "autobrakepostemp2", check = debounce_check, format = function(v)
        if v == def.AUTOBRAKERTO then return "Auto Brake R T O"
        elseif v == def.AUTOBRAKEOFF then return "Auto Brake Off"
        elseif v == def.AUTOBRAKE1 then return "Auto Brake 1"
        elseif v == def.AUTOBRAKE2 then return "Auto Brake 2"
        elseif v == def.AUTOBRAKE3 then return "Auto Brake 3"
        elseif v == def.AUTOBRAKEMAX then return "Auto Brake Maximum" end
    end },
    { dataref = "autobrakedisarm", temp1 = "autobrakedisarmtemp", temp2 = "autobrakedisarmtemp2", check = debounce_check, format = function(v) 
        if v == def.ON then return "Auto Brake Disarmed" end 
    end },

    -- Debounce mit Bedingung
    { dataref = "mcpspeed", temp1 = "mcpspeedtemp", temp2 = "mcpspeedtemp2", check = debounce_check,
      condition = function(P) return (get(P.atarmpos) == def.OFF) or (get(P.atspeedstat) == def.ON) or (get(P.atspeedintvstat) == def.ON) end,
      format = function(v, P)
          local speed_str = (v < 1) and helpers.roundnumber(v, 2) or helpers.roundnumber(v)
          if ((P.flightstate > 2) and (v == get(P.vref))) then return "M C P Speed set to V REF " .. tostring(speed_str)
          else return "M C P Speed " .. tostring(speed_str) end
      end
    },
    { dataref = "mcpvsspeed", temp1 = "mcpvsspeedtemp", temp2 = "mcpvsspeedtemp2", check = debounce_check,
      condition = function(P) return (get(P.mcpvsspeed) ~= 0) and (get(P.apalthldstat) ~= def.ON) and (get(P.apvnavstat) ~= def.ON) end,
      format = function(v) return "M C P Vertical Speed " .. tostring(v) end
    }
}

--------------------------------------------------------------------------------------------------------------
function VR.initialize(P)
    -- Initialisiert ALLE temp-Variablen, die in diesem Modul verwendet werden
    sasl.logInfo("YAL: Initializing all variables for voice readback.")
    
    for _, config in ipairs(VR.config) do
        if config.dataref then
            local currentValue
            if config.dataref == "speedbrakelever" then
                currentValue = helpers.roundnumber(get(P[config.dataref]), 1)
            else
                currentValue = get(P[config.dataref])
            end
            
            if config.temp then P[config.temp] = currentValue end
            if config.temp1 then P[config.temp1] = currentValue end
            if config.temp2 then P[config.temp2] = currentValue end
        end
    end
    
    P.totalfuellbstemp = get(P.totalfuellbs); P.totalfuellbstemp2 = get(P.totalfuellbs)
    P.apcmdastattemp = get(P.apcmdastat); P.apcmdbstattemp = get(P.apcmdbstat)
    P.apvnavstattemp = get(P.apvnavstat); P.aplnavstattemp = get(P.aplnavstat); P.apappstattemp = get(P.apappstat)
    P.apvorlocstattemp = get(P.apvorlocstat); P.apalthldstattemp = get(P.apalthldstat); P.aphdgselstattemp = get(P.aphdgselstat)
    P.apvsstattemp = get(P.apvsstat); P.aplvlchgstattemp = get(P.aplvlchgstat)
    P.apgscapturedstattemp = get(P.apgscapturedstat); P.aploccapturedstattemp = get(P.aploccapturedstat)
    P.apflarestattemp = get(P.apflarestat); P.aprolloutstattemp = get(P.aprolloutstat)
    P.aplpvgscapturedstattemp = get(P.aplpvgscapturedstat); P.aplpvloccapturedstattemp = get(P.aplpvloccapturedstat)
    P.apglsgscapturedstattemp = get(P.apglsgscapturedstat); P.apglsloccapturedstattemp = get(P.apglsloccapturedstat)
    P.apfacgscapturedstattemp = get(P.apfacgscapturedstat); P.apfacloccapturedstattemp = get(P.apfacloccapturedstat)
    P.atn1stattemp = get(P.atn1stat); P.atspeedstattemp = get(P.atspeedstat); P.atspeedintvstattemp = get(P.atspeedintvstat)
    P.barostdtemp = get(P.barostd); P.baropilottemp = get(P.baropilot); P.baropilottemp2 = get(P.baropilot)
    P.fdpilotpostemp = get(P.fdpilotpos); P.fdfopostemp = get(P.fdfopos)
    P.efiswxpilotpostemp = get(P.efiswxpilotpos); P.efiswxfopostemp = get(P.efiswxfopos)
    P.efisterrpilotpostemp = get(P.efisterrpilotpos); P.efisterrfopostemp = get(P.efisterrfopos)
    P.efisdatapilotpostemp = get(P.efisdatapilotpos); P.efisdatafopostemp = get(P.efisdatafopos)
    P.efisfixpilotpostemp = get(P.efisfixpilotpos); P.efisfixfopostemp = get(P.efisfixfopos)
    P.efisairportpilotpostemp = get(P.efisairportpilotpos); P.efisairportfopostemp = get(P.efisairportfopos)
    P.efispospilotpostemp = get(P.efispospilotpos); P.efisposfopostemp = get(P.efisposfopos)
    P.efisvorpilotpostemp = get(P.efisvorpilotpos); P.efisvorfopostemp = get(P.efisvorfopos)
    P.mmrcptactmodetemp = get(P.mmrcptactmode); P.mmrcptactvaluetemp = get(P.mmrcptactvalue)
    P.mmrfoactmodetemp = get(P.mmrfoactmode); P.mmrfoactvaluetemp = get(P.mmrfoactvalue)
    P.mmrcptstdbymodetemp = get(P.mmrcptstdbymode); P.mmrcptstdbymodetemp2 = get(P.mmrcptstdbymode)
    P.mmrfostdbymodetemp = get(P.mmrfostdbymode); P.mmrfostdbymodetemp2 = get(P.mmrfostdbymode)
    P.nav1freqtemp = get(P.nav1freq); P.nav2freqtemp = get(P.nav2freq)
    P.centertanklswitchtemp = get(P.centertanklswitch); P.centertankrswitchtemp = get(P.centertankrswitch)
    P.lefttanklswitchtemp = get(P.lefttanklswitch); P.lefttankrswitchtemp = get(P.lefttankrswitch)
    P.righttanklswitchtemp = get(P.righttanklswitch); P.righttankrswitchtemp = get(P.righttankrswitch)
    P.starter1postemp = get(P.starter1pos); P.starter2postemp = get(P.starter2pos)
    P.mixture1postemp = get(P.mixture1pos); P.mixture2postemp = get(P.mixture2pos)
    P.reverser1postemp = get(P.reverser1pos); P.reverser2postemp = get(P.reverser2pos)
    P.announcsourceoff1temp = helpers.roundnumber(get(P.announcsourceoff1), 1); P.announcsourceoff2temp = helpers.roundnumber(get(P.announcsourceoff2), 1)
    P.gen1postemp = get(P.gen1pos); P.gen2postemp = get(P.gen2pos)
    P.captainprobepostemp = get(P.captainprobepos); P.foprobepostemp = get(P.foprobepos)
    P.wheatlfwdpostemp = get(P.wheatlfwdpos); P.wheatlsidepostemp = get(P.wheatlsidepos)
    P.wheatrfwdpostemp = get(P.wheatrfwdpos); P.wheatrsidepostemp = get(P.wheatrsidepos)
    P.packlpostemp = get(P.packlpos); P.packrpostemp = get(P.packrpos)
    P.bleedair1postemp = get(P.bleedair1pos); P.bleedair2postemp = get(P.bleedair2pos)
    P.hydro1postemp = get(P.hydro1pos); P.hydro2postemp = get(P.hydro2pos)
    P.elechydro1postemp = get(P.elechydro1pos); P.elechydro2postemp = get(P.elechydro2pos)
    P.irsleftpostemp = get(P.irsleftpos); P.irsleftpostemp2 = get(P.irsleftpos)
    P.irsrightpostemp = get(P.irsrightpos); P.irsrightpostemp2 = get(P.irsrightpos)
    P.lwiperpostemp = get(P.lwiperpos); P.lwiperpostemp2 = get(P.lwiperpos)
    P.rwiperpostemp = get(P.rwiperpos); P.rwiperpostemp2 = get(P.rwiperpos)
    P.llightsontemp = get(P.llightson); P.llights1temp = get(P.llights1); P.llights2temp = get(P.llights2); P.llights3temp = get(P.llights3); P.llights4temp = get(P.llights4)
    P.rwylightltemp = get(P.rwylightl); P.rwylightrtemp = get(P.rwylightr)
end

--------------------------------------------------------------------------------------------------------------
function VR.run(P)
    for _, config in ipairs(VR.config) do
        local currentValue
        if config.dataref == "speedbrakelever" then
            currentValue = helpers.roundnumber(get(P[config.dataref]), 1)
        else
            currentValue = get(P[config.dataref])
        end
        
        local hasChanged = false
        if (not config.condition or config.condition(P)) then
            if config.check == simple_check then
                hasChanged = simple_check(currentValue, config.temp, P)
            elseif config.check == debounce_check then
                hasChanged = debounce_check(currentValue, config.temp1, config.temp2, P)
            end
        else
            if config.temp then P[config.temp] = currentValue end
            if config.temp1 then P[config.temp1] = currentValue end
            if config.temp2 then P[config.temp2] = currentValue end
        end

        if hasChanged then
            local message = config.format(currentValue, P)
            if message then P.commandtableentry(def.TEXT, message) end
        end
    end

    complex_check(P)

    return true
end

return VR