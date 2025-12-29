local def = require("definitions")
local settings = require("settings")
require("helpers")
require("yal")

local debugOverlayWindow
local debugOverlayInitialized = false
local setupWindow
local setupInitialized = false

local function maybeInitDebugOverlay()
    if debugOverlayInitialized then return end
    if not settings.appSettings then return end

    local requested = tonumber(settings.appSettings[def.CONFIGDEBUGOVERLAY]) == def.ON
    if not requested then return end

    local ok, modOrErr = pcall(require, "windows.debug")
    if not ok then
        sasl.logWarning("Debug overlay requested but failed to load: " .. tostring(modOrErr))
        debugOverlayInitialized = true
        return
    end

    local mod = modOrErr
    if not mod or not mod.newComponent then
        debugOverlayInitialized = true
        sasl.logWarning("Debug overlay module missing newComponent.")
        return
    end

    local comp = mod.newComponent({ yal = yal, def = def, helpers = helpers })
    local w, h = mod.windowSize()
    local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)
    local posX = xRoot + math.max(0, (wRoot - w) / 2)
    local posY = yRoot + math.max(0, (hRoot - h) / 2)

    debugOverlayWindow = contextWindow {
        name = "YAL Debug",
        position = { posX, posY, w, h },
        saveState = true,
        visible = false,
        noResize = false,
        vrAuto = true,
        noBackground = true,
        noDecore = true,
        proportional = false,
        resizeCallback = function(c, rw, rh, _, _)
            if c and c.position then set(c.position, {0, 0, rw, rh}) end
            if c and c.size then c.size = {rw, rh} end
            return 0, 0, rw, rh
        end,
        components = { comp }
    }
    if comp.setWindow then
        comp:setWindow(debugOverlayWindow)
    end

    local function toggleDebugOverlay()
        if debugOverlayWindow then
            local target = not debugOverlayWindow:isVisible()
            debugOverlayWindow:setIsVisible(target)
        end
    end

    local cmdPath = def.APPNAMEPREFIX .. "/toggle_debug_overlay"
    local cmd = sasl.createCommand(cmdPath, "Toggle YAL Debug Overlay")
    sasl.registerCommandHandler(cmd, 0, function(phase)
        if phase == SASL_COMMAND_BEGIN then
            toggleDebugOverlay()
        end
        return 0
    end)

    if yal.menu_main then
        sasl.appendMenuItem(yal.menu_main, "Debug", toggleDebugOverlay)
    end

    debugOverlayInitialized = true
    helpers.logInfoTS("Debug overlay enabled")
end


helpers.logInfoTS(string.format("Starting %s v%s on X-Plane v%d", def.APPNAMEPREFIXLONG, def.VERSION, helpers.xpVersion))
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
local menu_settings = nil

local function maybeInitSetupWindow()
    -- If already initialized but menu not added yet, try to add it now.
    if setupInitialized then
        if not menu_settings and yal.menu_main then
            local function toggleSetup()
                if setupWindow then
                    local target = not setupWindow:isVisible()
                    setupWindow:setIsVisible(target)
                end
            end
            menu_settings = sasl.appendMenuItem(yal.menu_main, "Settings", toggleSetup)
        end
        return
    end

    local ok, modOrErr = pcall(require, "windows.setup")
    if not ok then
        sasl.logWarning("Settings window failed to load: " .. tostring(modOrErr))
        setupInitialized = true
        return
    end

    local mod = modOrErr
    if not mod or not mod.newComponent then
        setupInitialized = true
        sasl.logWarning("Settings module missing newComponent.")
        return
    end

    local comp = mod.newComponent({ yal = yal, def = def, helpers = helpers })
    local w, h = mod.windowSize()
    local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)
    local posX = xRoot + math.max(0, (wRoot - w) / 2)
    local posY = yRoot + math.max(0, (hRoot - h) / 2)

    setupWindow = contextWindow {
        name = "setup window",
        position = { posX, posY, w, h },
        saveState = true,
        visible = false,
        noResize = false,
        vrAuto = true,
        noBackground = true,
        noDecore = true,
        proportional = false,
        resizeCallback = function(c, rw, rh, _, _)
            if c and c.position then set(c.position, {0, 0, rw, rh}) end
            if c and c.size then c.size = {rw, rh} end
            return 0, 0, rw, rh
        end,
        components = { comp }
    }
    _G.setupWindow = setupWindow

    if comp.setWindow then
        comp:setWindow(setupWindow)
    end

    local function toggleSetup()
        if setupWindow then
            local target = not setupWindow:isVisible()
            setupWindow:setIsVisible(target)
        end
    end

    local cmdPath = def.APPNAMEPREFIX .. "/toggle_setup_window"
    local cmd = sasl.createCommand(cmdPath, "Toggle YAL Settings")
    sasl.registerCommandHandler(cmd, 0, function(phase)
        if phase == SASL_COMMAND_BEGIN then
            toggleSetup()
        end
        return 0
    end)

    if yal.menu_main and not menu_settings then
        menu_settings = sasl.appendMenuItem(yal.menu_main, "Settings", toggleSetup)
    end

    setupInitialized = true
    helpers.logInfoTS("Settings window initialized")
end

-- ensure setup window (and its command/menu) is constructed early
maybeInitSetupWindow()

local oneSecTimer = sasl.createTimer()
local waitstep = def.LONGWAIT

function show_hide_setup()
    if not helpers.isZibo() then
        helpers.logInfoTS("Setup window is only available for Zibo Mod. Current aircraft is not Zibo.")
        return
    end
    maybeInitSetupWindow()
    if setupWindow then
        setupWindow:setIsVisible(not setupWindow:isVisible())
    end
end

if helpers.isZibo() then
    helpers.logInfoTS("Zibo Mod detected on initial plugin load")
    yal.enableMenus(def.ON)
    maybeInitSetupWindow()
    if menu_settings then sasl.enableMenuItem(yal.menu_main , menu_settings , def.ON) end
    yal.initializeScript()
    maybeInitDebugOverlay()
    sasl.startTimer(oneSecTimer)
    waitstep = def.LONGWAIT
else
    helpers.logInfoTS("No Zibo Mod detected on initial plugin load. Plugin functionality currently inactive.")
    if menu_settings then sasl.enableMenuItem(yal.menu_main , menu_settings , def.OFF) end
    yal.enableMenus(def.OFF)
    sasl.stopTimer(oneSecTimer)
    if setupWindow then setupWindow:setIsVisible(false) end
end

function onAirportLoaded(flightNumber)
    helpers.logInfoTS(string.format("Airport loaded: Flight #%s, Aircraft: %s", flightNumber, sasl.getAircraft()))

    if helpers.isZibo() then
        helpers.logInfoTS("Zibo Mod detected after airport load.")
        yal.enableMenus(def.ON)  
        maybeInitSetupWindow()
        if menu_settings then sasl.enableMenuItem(yal.menu_main , menu_settings , def.ON) end
        yal.initializeScript()
        maybeInitDebugOverlay()
        sasl.startTimer(oneSecTimer)
        waitstep = def.LONGWAIT
    else
        helpers.logInfoTS("No Zibo Mod detected after airport load. Plugin functionality will remain inactive.")
        if menu_settings then sasl.enableMenuItem(yal.menu_main, menu_settings, def.OFF) end
        sasl.stopTimer(oneSecTimer)
        yal.enableMenus(def.OFF)  
        if setupWindow then setupWindow:setIsVisible(false) end
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
                
                helpers.logInfoTS(string.format("yal.do_yal() returned an invalid wait step (%.2f). Falling back to STANDARDWAIT.", next_recommended_wait_step or -1))
                next_recommended_wait_step = def.STANDARDWAIT
            end

            waitstep = next_recommended_wait_step
            sasl.logDebug(string.format("UPDATE: Next do_yal() cycle will wait for %.1f seconds.", waitstep))
        end
    end
        
    return 0
end
