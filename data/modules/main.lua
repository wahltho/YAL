
local def = require("definitions")
require("helpers")
require("yal")


sasl.logInfo(string.format("Starting %s v%s on Xp %d", def.APPNAMEPREFIXLONG, def.VERSION, helpers.xpVersion))
sasl.setLogLevel(LOG_INFO)

if not helpers.isXp12 then
    sasl.logWarning("X-Plane 12 required, exiting plugin")
    return
end

sasl.options.setAircraftPanelRendering(false)
sasl.options.set3DRendering(false)
sasl.options.setInteractivity(true)

YALupdateAvailable, YALnewVersion = helpers.checkForUpdate()

if helpers.check_create_path(def.XPCACHESPATH) then
    if not helpers.check_create_path(def.YALCACHEPATH) then
        sasl.logWarning("Fail to create cache folder, reverting to legacy folder")
        def.YALCACHESPATH = def.XPOUTPUTPATH
    end
else
    sasl.logWarning("Fail to create cache folder, reverting to legacy folder")
    def.YALCACHESPATH = def.XPOUTPUTPATH
end

include "keyboard_handler"

helpers.initTailNum() 

local oneSecTimer = sasl.createTimer()
local waitstep = def.LONGWAIT

yal.enableMenus()

if helpers.isZibo then
    sasl.logInfo("Zibo Mod detected on initial plugin load. Initializing plugin functionality.")
    yal.YalinitGlobal()
    yal.initDataref()
    sasl.startTimer(oneSecTimer)
else
    sasl.logInfo("No Zibo Mod detected on initial plugin load. Plugin functionality currently inactive.")
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
    if helpers.isZibo then
        setup_datapanel:setIsVisible(not setup_datapanel:isVisible())
    else
        sasl.logInfo("Setup window is only available for Zibo Mod. Current aircraft is not Zibo.")
    end
end

setup_datapanel:setIsVisible(false)

menu_settings = sasl.appendMenuItem(yal.menu_main, "Settings", show_hide_setup)

local enable_settings_menu = 0
if helpers.isZibo then
    enable_settings_menu = 1
end
sasl.enableMenuItem(yal.menu_main , menu_settings , enable_settings_menu)

function onAirportLoaded(flightNumber)
    sasl.logInfo(string.format("Airport loaded: Flight #%s, Aircraft: %s", flightNumber, sasl.getAircraft()))
    
    helpers.initTailNum()
    yal.enableMenus()    

    local enable_settings_menu_on_load = 0
    if helpers.isZibo then
        enable_settings_menu_on_load = 1
    end
    sasl.enableMenuItem(yal.menu_main , menu_settings , enable_settings_menu_on_load)

    if helpers.isZibo then
        sasl.logInfo("Zibo Mod detected after airport load. Re-initializing plugin functionality.")
        yal.YalinitGlobal()
        yal.initDataref()
        sasl.startTimer(oneSecTimer)
        waitstep = def.LONGWAIT
    else
        sasl.logInfo("No Zibo Mod detected after airport load. Plugin functionality will remain inactive.")
        sasl.enableMenuItem(yal.menu_main, menu_settings, def.OFF)
        sasl.stopTimer(oneSecTimer)
        setup_datapanel:setIsVisible(false)
    end
end

function update()
    if helpers.isZibo then
        local current_elapsed_time = sasl.getElapsedSeconds(oneSecTimer)

        if current_elapsed_time >= waitstep then
            sasl.startTimer(oneSecTimer)

            local next_recommended_wait_step = yal.do_yal()

            if type(next_recommended_wait_step) ~= "number" or
               (next_recommended_wait_step ~= def.STANDARDWAIT and
                next_recommended_wait_step ~= def.SHORTWAIT and
                next_recommended_wait_step ~= def.LONGSPEAKWAIT and
                next_recommended_wait_step ~= def.LONGWAIT) then
                
                sasl.logInfo(string.format("yal.do_yal() returned an invalid wait step (%.2f). Falling back to STANDARDWAIT.", next_recommended_wait_step or -1))
                next_recommended_wait_step = def.STANDARDWAIT
            end

            waitstep = next_recommended_wait_step
            sasl.logDebug(string.format("UPDATE: Next do_yal() cycle will wait for %.1f seconds.", waitstep))
        end
    end
        
    return 0
end