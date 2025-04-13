require("definitions")
require("helpers")
require("yal")
sasl.logInfo(string.format("Starting %s v%s on Xp %d", definitions.APPNAMEPREFIX, definitions.VERSION, helpers.xpVersion))
sasl.setLogLevel(LOG_INFO)


sasl.options.setAircraftPanelRendering(false)
sasl.options.set3DRendering(false)
sasl.options.setInteractivity(true)

if helpers.check_create_path(definitions.XPCACHESPATH) then
    if not helpers.check_create_path(definitions.YALCACHEPATH) then
        sasl.logWarning("Fail to create cache folder, reverting to legacy folder")
        definitions.YALCACHESPATH = definitions.XPOUTPUTPATH
    end
else
    sasl.logWarning("Fail to create cache folder, reverting to legacy folder")
    definitions.YALCACHESPATH = definitions.XPOUTPUTPATH
end

include "keyboard_handler"

helpers.initTailNum()

oneSecTimer = sasl.createTimer()

waitstep = LONGWAIT

yal.enableMenus()


if helpers.isZibo then
    yal.YalinitGlobal()
    yal.initDataref()
    sasl.startTimer(oneSecTimer)
end


local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)

local st_height = 700
local st_width = 750
local st_x_org = xRoot + (wRoot - st_width) / 2
local st_y_org = yRoot + (hRoot - st_height) / 2
setup_datapanel = contextWindow {
    name = "setup window",
    position = {st_x_org, st_y_org, st_width, st_height},
    visible = false,
    noResize = true,
    vrAuto = true,
    noBackground = true,
    noDecore = true,
    proportional = true,
    components = {setup_datapanel {
        position = {0, 0, st_width, st_height},
        size = {st_width, st_height}
    }}
}

function show_hide_setup()
    setup_datapanel:setIsVisible(not setup_datapanel:isVisible())
end

setup_datapanel:setIsVisible(false)

menu_settings = sasl.appendMenuItem(yal.menu_main, "Settings", show_hide_setup)
local enable = 0
    if helpers.isZibo then
        enable = 1
    end
sasl.enableMenuItem(yal.menu_main , menu_settings , enable)

function onAirportLoaded(flightNumber)
    sasl.logInfo("Starting Flight #" .. flightNumber .. " " .. sasl.getAircraftPath() .. " " .. sasl.getAircraft())
    helpers.initTailNum()
    yal.enableMenus()
    enable = 0
    if helpers.isZibo then
        enable = 1
    end
    sasl.enableMenuItem(yal.menu_main , menu_settings , enable)
    if helpers.isZibo then
        yal.YalinitGlobal()
        yal.initDataref()
        sasl.startTimer(oneSecTimer)
    end
    
end

function update()
    if helpers.isZibo then
        if ((sasl.getElapsedSeconds(oneSecTimer) >= STANDARDWAIT) and (waitstep == STANDARDWAIT)) then
            yal.do_yal()
            waitstep = STANDARDWAIT
            sasl.startTimer(oneSecTimer)
        elseif ((sasl.getElapsedSeconds(oneSecTimer) >= LONGWAIT) and (waitstep == LONGWAIT)) then
            waitstep = STANDARDWAIT
            sasl.startTimer(oneSecTimer)
        end
    end
end