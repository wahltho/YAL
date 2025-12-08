local def = require("definitions")
local settings = require("settings")
require("helpers")
require("yal")

local debugOverlay
local debugOverlayInitialized = false

local function maybeInitDebugOverlay()
    if debugOverlayInitialized then return end
    if not settings.appSettings then return end

    local requested = tonumber(settings.appSettings[def.CONFIGDEBUGOVERLAY]) == def.ON
    if not requested then return end
    if sasl.getLogLevel() ~= LOG_DEBUG then return end

    local ok, modOrErr = pcall(require, "yal_debug.overlay")
    if not ok then
        sasl.logWarning("Debug overlay requested but failed to load: " .. tostring(modOrErr))
        debugOverlayInitialized = true
        return
    end

    local mod = modOrErr
    if mod and mod.init then
        local initOk, initErr = pcall(mod.init, { yal = yal, def = def, helpers = helpers })
        if not initOk then
            sasl.logWarning("Debug overlay init failed: " .. tostring(initErr))
            debugOverlayInitialized = true
            return
        end
        debugOverlay = mod
        yal.debugOverlay = mod
        debugOverlayInitialized = true
        sasl.logInfo("Debug overlay enabled (hidden setting + DEBUG log level).")
    else
        debugOverlayInitialized = true
    end
end


sasl.logInfo(string.format("Starting %s v%s on X-Plane v%d", def.APPNAMEPREFIXLONG, def.VERSION, helpers.xpVersion))
sasl.setLogLevel(LOG_INFO)

if not helpers.isXp12 then
    sasl.logWarning("X-Plane 12 required, exiting plugin")
    return
end

sasl.options.setAircraftPanelRendering(false)
sasl.options.set3DRendering(false)
sasl.options.setInteractivity(true)

if helpers.check_create_path(def.XPCACHESPATH) then
    if not helpers.check_create_path(def.YALCACHEPATH) then
        sasl.logWarning("Failed to create cache folder, reverting to legacy folder")
        def.YALCACHESPATH = def.XPOUTPUTPATH
    end
else
    sasl.logWarning("Failed to create cache folder, reverting to legacy folder")
    def.YALCACHESPATH = def.XPOUTPUTPATH
end

include "keyboard_handler"

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

local oneSecTimer = sasl.createTimer()
local waitstep = def.LONGWAIT

function show_hide_setup()
    if helpers.isZibo() then
        setup_datapanel:setIsVisible(not setup_datapanel:isVisible())
    else
        sasl.logInfo("Setup window is only available for Zibo Mod. Current aircraft is not Zibo.")
    end
end

setup_datapanel:setIsVisible(false)

menu_settings = sasl.appendMenuItem(yal.menu_main, "Settings", show_hide_setup)

if helpers.isZibo() then
    sasl.logInfo("Zibo Mod detected on initial plugin load")
    yal.enableMenus(def.ON)
    sasl.enableMenuItem(yal.menu_main , menu_settings , def.ON)
    yal.initializeScript()
    maybeInitDebugOverlay()
    sasl.startTimer(oneSecTimer)
    waitstep = def.LONGWAIT
else
    sasl.logInfo("No Zibo Mod detected on initial plugin load. Plugin functionality currently inactive.")
    sasl.enableMenuItem(yal.menu_main , menu_settings , def.OFF)
    yal.enableMenus(def.OFF)
    sasl.stopTimer(oneSecTimer)
    setup_datapanel:setIsVisible(false)
end

function onAirportLoaded(flightNumber)
    sasl.logInfo(string.format("Airport loaded: Flight #%s, Aircraft: %s", flightNumber, sasl.getAircraft()))

    if helpers.isZibo() then
        sasl.logInfo("Zibo Mod detected after airport load.")
        yal.enableMenus(def.ON)  
        sasl.enableMenuItem(yal.menu_main , menu_settings , def.ON)
        yal.initializeScript()
        maybeInitDebugOverlay()
        sasl.startTimer(oneSecTimer)
        waitstep = def.LONGWAIT
    else
        sasl.logInfo("No Zibo Mod detected after airport load. Plugin functionality will remain inactive.")
        sasl.enableMenuItem(yal.menu_main, menu_settings, def.OFF)
        sasl.stopTimer(oneSecTimer)
        yal.enableMenus(def.OFF)  
        setup_datapanel:setIsVisible(false)
    end
end

function update()
    if helpers.isZibo() then
        maybeInitDebugOverlay()
        local current_elapsed_time = sasl.getElapsedSeconds(oneSecTimer)

        if current_elapsed_time >= waitstep then
            sasl.startTimer(oneSecTimer)

            local next_recommended_wait_step = yal.do_yal()

            if type(next_recommended_wait_step) ~= "number" or
               (next_recommended_wait_step ~= def.STANDARDWAIT and
                next_recommended_wait_step ~= def.SHORTWAIT and
                next_recommended_wait_step ~= def.MEDIUMWAIT and
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
