local def = require("definitions")
local settings = require("settings")
require("helpers")
require("yal")

local debugOverlayWindow
local debugOverlayInitialized = false
local setupWindow
local setupInitialized = false
local taxiWindow
local taxiInitialized = false
local taxiComponent
local taxiPopupWindow
local taxiPopupInitialized = false
local taxiPopupComponent
local trimPopupWindow
local trimPopupInitialized = false
local trimPopupComponent
local updatePopupWindow
local updatePopupInitialized = false
local updatePopupComponent
local startupUpdateCheckDone = false
local startupUpdateCheckEarliest = 0
local startupUpdateCheckPerformed = false
local menu_taxi = nil
local taxiGateLastLogTime = 0

local function normalize_zibo_release(raw)
    local s = helpers.forceCleanString(tostring(raw or ""))
    local full = s:match("(%d+%.%d+%.%d+)")
    if full then
        return full
    end
    local short = s:match("(%d+%.%d+)")
    if short then
        return short
    end
    return s
end

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
    local cmdPathAlias = def.APPNAMEPREFIX .. "/toggle_debug_window"
    local cmdAlias = sasl.createCommand(cmdPathAlias, "Toggle YAL Debug Window")
    sasl.registerCommandHandler(cmdAlias, 0, function(phase)
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

local function taxi_map_allowed()
    if not helpers.isGlobalAptIndexReady() then
        helpers.requestGlobalAptIndex("taxi-map")
        local now = os.time()
        if now and (now - (taxiGateLastLogTime or 0)) >= 3 then
            taxiGateLastLogTime = now
            helpers.logInfoTS("Taxi map indexing global apt.dat...")
        end
    end
    return true
end

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
        resizeCallback = function(_, rw, rh, _, _)
            if comp and comp.position then set(comp.position, {0, 0, rw, rh}) end
            if comp and comp.size then comp.size = {rw, rh} end
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
    local cmdPathAlias = def.APPNAMEPREFIX .. "/toggle_settings_window"
    local cmdAlias = sasl.createCommand(cmdPathAlias, "Toggle YAL Settings Window")
    sasl.registerCommandHandler(cmdAlias, 0, function(phase)
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

local function maybeInitTaxiWindow()
    if taxiInitialized then
        if not menu_taxi and yal.menu_main then
            local function toggleTaxi()
                if taxiWindow then
                    local target = not taxiWindow:isVisible()
                    if target then taxi_map_allowed() end
                    taxiWindow:setIsVisible(target)
                end
            end
            menu_taxi = sasl.appendMenuItem(yal.menu_main, "Taxi Map", toggleTaxi)
        end
        return
    end

    local ok, modOrErr = pcall(require, "windows.taxi")
    if not ok then
        sasl.logWarning("Taxi map window failed to load: " .. tostring(modOrErr))
        taxiInitialized = true
        return
    end

    local mod = modOrErr
    if not mod or not mod.newComponent then
        taxiInitialized = true
        sasl.logWarning("Taxi map module missing newComponent.")
        return
    end

    local comp = mod.newComponent({ yal = yal, def = def, helpers = helpers })
    taxiComponent = comp
    yal.taxiComponent = comp
    local w, h = mod.windowSize()
    local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)
    local posX = xRoot + math.max(0, (wRoot - w) / 2)
    local posY = yRoot + math.max(0, (hRoot - h) / 2)

    taxiWindow = contextWindow {
        name = "YAL Taxi Map",
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
        comp:setWindow(taxiWindow)
    end
    yal.taxiWindow = taxiWindow

    local function toggleTaxi()
        if taxiWindow then
            local target = not taxiWindow:isVisible()
            if target then taxi_map_allowed() end
            taxiWindow:setIsVisible(target)
        end
    end

    local cmdPath = def.APPNAMEPREFIX .. "/toggle_taxi_map"
    local cmd = sasl.createCommand(cmdPath, "Toggle YAL Taxi Map")
    sasl.registerCommandHandler(cmd, 0, function(phase)
        if phase == SASL_COMMAND_BEGIN then
            toggleTaxi()
        end
        return 0
    end)

    if yal.menu_main and not menu_taxi then
        menu_taxi = sasl.appendMenuItem(yal.menu_main, "Taxi Map", toggleTaxi)
    end

    taxiInitialized = true
    helpers.logInfoTS("Taxi map window initialized")
end

local function maybeInitTaxiPopupWindow()
    if taxiPopupInitialized then
        return
    end

    local ok, modOrErr = pcall(require, "windows.taxi_popup")
    if not ok then
        sasl.logWarning("Taxi guidance popup failed to load: " .. tostring(modOrErr))
        taxiPopupInitialized = true
        return
    end

    local mod = modOrErr
    if not mod or not mod.newComponent then
        taxiPopupInitialized = true
        sasl.logWarning("Taxi guidance popup module missing newComponent.")
        return
    end

    local comp = mod.newComponent({ yal = yal, def = def, helpers = helpers })
    taxiPopupComponent = comp
    yal.taxiPopup = comp
    local w, h = mod.windowSize()
    local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)
    local posX = xRoot + math.max(0, (wRoot - w) / 2)
    local posY = yRoot + math.max(0, (hRoot - h) * 0.18)

    taxiPopupWindow = contextWindow {
        name = "YAL Taxi Guidance",
        position = { posX, posY, w, h },
        saveState = true,
        visible = false,
        noResize = true,
        vrAuto = true,
        noBackground = true,
        noDecore = true,
        proportional = false,
        components = { comp }
    }

    if comp.setWindow then
        comp:setWindow(taxiPopupWindow)
    end

    taxiPopupInitialized = true
    helpers.logInfoTS("Taxi guidance popup initialized")
end

local function maybeInitUpdatePopupWindow()
    if updatePopupInitialized then
        return
    end

    local ok, modOrErr = pcall(require, "windows.update_popup")
    if not ok then
        sasl.logWarning("Update popup failed to load: " .. tostring(modOrErr))
        updatePopupInitialized = true
        return
    end

    local mod = modOrErr
    if not mod or not mod.newComponent then
        updatePopupInitialized = true
        sasl.logWarning("Update popup module missing newComponent.")
        return
    end

    local comp = mod.newComponent({
        yal = yal,
        def = def,
        helpers = helpers,
        onAcknowledge = function()
            helpers.logInfoTS("Startup update popup acknowledged")
        end
    })
    updatePopupComponent = comp
    local w, h = mod.windowSize()
    local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)
    local posX = xRoot + math.max(0, (wRoot - w) / 2)
    local posY = yRoot + math.max(0, (hRoot - h) * 0.25)

    updatePopupWindow = contextWindow {
        name = "YAL Updates",
        position = { posX, posY, w, h },
        saveState = true,
        visible = false,
        noResize = true,
        vrAuto = true,
        noBackground = true,
        noDecore = true,
        proportional = false,
        components = { comp }
    }

    if comp.setWindow then
        comp:setWindow(updatePopupWindow)
    end

    updatePopupInitialized = true
    helpers.logInfoTS("Update popup initialized")
end

local function saveTrimPopupPosition(x, y)
    if not settings or not settings.appSettings then
        return
    end
    settings.appSettings[def.CONFIGTRIMADVICEPOPUPX] = tonumber(x) or -1
    settings.appSettings[def.CONFIGTRIMADVICEPOPUPY] = tonumber(y) or -1
    settings.writeSettings(settings.appSettings)
end

local function maybeInitTrimPopupWindow()
    if trimPopupInitialized then
        return
    end

    local ok, modOrErr = pcall(require, "windows.trim_popup")
    if not ok then
        sasl.logWarning("Trim popup failed to load: " .. tostring(modOrErr))
        trimPopupInitialized = true
        return
    end

    local mod = modOrErr
    if not mod or not mod.newComponent then
        trimPopupInitialized = true
        sasl.logWarning("Trim popup module missing newComponent.")
        return
    end

    local comp = mod.newComponent({
        yal = yal,
        def = def,
        helpers = helpers,
        onMoveEnd = saveTrimPopupPosition
    })
    trimPopupComponent = comp
    yal.trimAdvicePopup = comp
    local w, h = mod.windowSize()
    local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)
    local posX = settings.getSettingNumber(def.CONFIGTRIMADVICEPOPUPX, -1)
    local posY = settings.getSettingNumber(def.CONFIGTRIMADVICEPOPUPY, -1)
    if posX == nil or posX < 0 then
        posX = xRoot + math.max(0, (wRoot - w) * 0.62)
    end
    if posY == nil or posY < 0 then
        posY = yRoot + math.max(0, (hRoot - h) * 0.28)
    end

    trimPopupWindow = contextWindow {
        name = "YAL Trim Advice",
        position = { posX, posY, w, h },
        saveState = false,
        visible = false,
        noResize = true,
        vrAuto = true,
        noBackground = true,
        noDecore = true,
        proportional = false,
        components = { comp }
    }

    if comp.setWindow then
        comp:setWindow(trimPopupWindow)
    end

    trimPopupInitialized = true
    helpers.logInfoTS("Trim popup initialized")
end

local function armStartupUpdateCheck()
    if startupUpdateCheckPerformed then
        return
    end
    startupUpdateCheckDone = false
    startupUpdateCheckEarliest = (os.time() or 0) + math.max(2, (def.LONGWAIT or 0) + 1)
end

local function is_yal_beta_version()
    return helpers.isPrereleaseVersion(def.VERSION)
end

local function maybeRunStartupUpdateCheck()
    if startupUpdateCheckDone then
        return
    end
    if not settings or not settings.appSettings then
        return
    end
    if not (yal and yal.externalDatarefsPostStartupDone) then
        return
    end
    local now = os.time() or 0
    if startupUpdateCheckEarliest > 0 and now < startupUpdateCheckEarliest then
        return
    end
    local ziboRelease = helpers.getLatchedZiboRelease()
    helpers.logInfoTS(string.format(
        "Zibo installed version: v%s",
        tostring((normalize_zibo_release(ziboRelease) ~= "") and normalize_zibo_release(ziboRelease) or "?")
    ))
    if tonumber(settings.appSettings[def.CONFIGAUTOUPDATECHECK] or 0) ~= def.ON then
        startupUpdateCheckDone = true
        startupUpdateCheckPerformed = true
        helpers.logInfoTS("Startup update check skipped (setting OFF)")
        return
    end
    if not helpers.isZibo() then
        return
    end
    if yal and yal.isReloadWithinSession then
        startupUpdateCheckDone = true
        startupUpdateCheckPerformed = true
        helpers.logInfoTS("Startup update check skipped (SASL reload within session)")
        return
    end

    startupUpdateCheckDone = true
    startupUpdateCheckPerformed = true

    local showBetaUpdates = tonumber(settings.appSettings[def.CONFIGSHOWBETAUPDATES] or 0) == def.ON
    local checkBeta = showBetaUpdates or is_yal_beta_version()
    local yalAvailable, yalLatest = helpers.checkForUpdate(checkBeta)
    local _, yalStable = helpers.checkForUpdate(false)
    local _, yalBeta = helpers.checkForUpdate(true)

    local ziboAvailable, ziboLatest, ziboLocal = helpers.checkForZiboUpdate(ziboRelease)
    helpers.logInfoTS(string.format(
        "Zibo feed latest version: v%s",
        tostring((ziboLatest and ziboLatest ~= "") and ziboLatest or "?")
    ))

    helpers.startupUpdateInfo = {
        ts = now,
        yal = {
            checkBeta = checkBeta,
            available = yalAvailable,
            latest = yalLatest,
            latestStable = yalStable,
            latestBeta = yalBeta,
            current = tostring(def.VERSION or ""),
        },
        zibo = {
            available = ziboAvailable,
            latest = ziboLatest,
            current = ziboLocal,
        },
    }

    if not yalAvailable and not ziboAvailable then
        helpers.logInfoTS("Startup update check: no updates available")
        return
    end

    local lines = {}
    if yalAvailable then
        lines[#lines + 1] = string.format("YAL update available: v%s (installed v%s)", tostring(yalLatest or "?"), tostring(def.VERSION or "?"))
    end
    if checkBeta and yalStable and yalStable ~= "" then
        lines[#lines + 1] = string.format("Latest stable YAL: v%s", tostring(yalStable))
    elseif (not checkBeta) and yalBeta and yalBeta ~= "" then
        lines[#lines + 1] = string.format("Latest beta YAL: v%s", tostring(yalBeta))
    end
    if ziboAvailable then
        lines[#lines + 1] = string.format("Zibo update available: v%s (installed v%s)", tostring(ziboLatest or "?"), tostring(ziboLocal or "?"))
    end

    maybeInitUpdatePopupWindow()
    if updatePopupComponent and updatePopupComponent.setPayload then
        updatePopupComponent:setPayload({
            title = "Update available",
            lines = lines,
            okLabel = "OK",
        })
    end
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

function show_hide_taxi_map()
    if not helpers.isZibo() then
        helpers.logInfoTS("Taxi map is only available for Zibo Mod. Current aircraft is not Zibo.")
        return
    end
    maybeInitTaxiWindow()
    if taxiWindow then
        local target = not taxiWindow:isVisible()
        if target then taxi_map_allowed() end
        taxiWindow:setIsVisible(target)
    end
end

if helpers.isZibo() then
    helpers.logInfoTS("Zibo Mod detected on initial plugin load")
    yal.enableMenus(def.ON)
    maybeInitSetupWindow()
    maybeInitTaxiWindow()
    if menu_settings then sasl.enableMenuItem(yal.menu_main , menu_settings , def.ON) end
    yal.initializeScript()
    armStartupUpdateCheck()
    maybeInitDebugOverlay()
    sasl.startTimer(oneSecTimer)
    waitstep = def.LONGWAIT
else
    helpers.logInfoTS("No Zibo Mod detected on initial plugin load. Plugin functionality currently inactive.")
    if menu_settings then sasl.enableMenuItem(yal.menu_main , menu_settings , def.OFF) end
    yal.enableMenus(def.OFF)
    sasl.stopTimer(oneSecTimer)
    if setupWindow then setupWindow:setIsVisible(false) end
    if taxiWindow then taxiWindow:setIsVisible(false) end
    if taxiPopupWindow then taxiPopupWindow:setIsVisible(false) end
    if trimPopupWindow then trimPopupWindow:setIsVisible(false) end
    if updatePopupWindow then updatePopupWindow:setIsVisible(false) end
end

function onAirportLoaded(flightNumber)
    helpers.logInfoTS(string.format("Airport loaded: Flight #%s, Aircraft: %s", flightNumber, sasl.getAircraft()))

    if helpers.isZibo() then
        helpers.logInfoTS("Zibo Mod detected after airport load.")
        yal.enableMenus(def.ON)  
        maybeInitSetupWindow()
        maybeInitTaxiWindow()
        if menu_settings then sasl.enableMenuItem(yal.menu_main , menu_settings , def.ON) end
        yal.initializeScript()
        armStartupUpdateCheck()
        maybeInitDebugOverlay()
        sasl.startTimer(oneSecTimer)
        waitstep = def.LONGWAIT
    else
        helpers.logInfoTS("No Zibo Mod detected after airport load. Plugin functionality will remain inactive.")
        if menu_settings then sasl.enableMenuItem(yal.menu_main, menu_settings, def.OFF) end
        sasl.stopTimer(oneSecTimer)
        yal.enableMenus(def.OFF)  
        if setupWindow then setupWindow:setIsVisible(false) end
        if taxiWindow then taxiWindow:setIsVisible(false) end
        if taxiPopupWindow then taxiPopupWindow:setIsVisible(false) end
        if trimPopupWindow then trimPopupWindow:setIsVisible(false) end
        if updatePopupWindow then updatePopupWindow:setIsVisible(false) end
    end
end

function update()
    if helpers.isZibo() then
        maybeInitDebugOverlay()
        if yal and yal.updateGearProtectionFast then
            yal.updateGearProtectionFast()
        end
        maybeRunStartupUpdateCheck()
        local autoTaxiEnabled = false
        local autoTaxiingEnabled = false
        local visualTaxiEnabled = false
        local trimPopupEnabled = false
        if settings and settings.appSettings then
            autoTaxiEnabled = (settings.appSettings[def.CONFIGAUTOTAXIGUIDANCE] == def.ON)
            visualTaxiEnabled = (settings.appSettings[def.CONFIGVISUALTAXIGUIDANCE] == def.ON)
            autoTaxiingEnabled = (settings.appSettings[def.CONFIGAUTOTAXIING] == def.ON)
            trimPopupEnabled = (settings.appSettings[def.CONFIGTRIMADVICEPOPUP] == def.ON)
        end
        if visualTaxiEnabled then
            maybeInitTaxiPopupWindow()
        else
            if taxiComponent and taxiComponent.clearVisualGuidance then
                taxiComponent:clearVisualGuidance()
            end
            if taxiPopupWindow and taxiPopupWindow.isVisible and taxiPopupWindow:isVisible() then
                taxiPopupWindow:setIsVisible(false)
                if taxiPopupComponent and taxiPopupComponent.clearInstruction then
                    taxiPopupComponent:clearInstruction()
                end
            end
        end
        if trimPopupEnabled then
            maybeInitTrimPopupWindow()
        else
            if trimPopupComponent and trimPopupComponent.clearStatus then
                trimPopupComponent:clearStatus()
            end
            if trimPopupWindow and trimPopupWindow.isVisible and trimPopupWindow:isVisible() then
                trimPopupWindow:setIsVisible(false)
            end
        end
        local taxiVisible = taxiWindow and taxiWindow.isVisible and taxiWindow:isVisible()
        if helpers.isGlobalAptIndexRunning() then
            helpers.updateGlobalAptIndex(nil, false)
        elseif not helpers.isGlobalAptIndexReady() then
            helpers.requestGlobalAptIndex("update-loop")
            helpers.updateGlobalAptIndex(nil, false)
        end
        if taxiComponent and (autoTaxiEnabled or taxiVisible or visualTaxiEnabled) then
            taxiComponent:tick()
        end
        if taxiComponent and autoTaxiEnabled and autoTaxiingEnabled and taxiComponent.autoTaxiTick then
            taxiComponent:autoTaxiTick()
        end
        if trimPopupComponent and trimPopupComponent.tick then
            trimPopupComponent:tick()
        end
        local current_elapsed_time = sasl.getElapsedSeconds(oneSecTimer)

        if current_elapsed_time >= waitstep then
            sasl.startTimer(oneSecTimer)

            local next_recommended_wait_step = yal.do_yal()

            if type(next_recommended_wait_step) ~= "number" or
               (next_recommended_wait_step ~= def.STANDARDWAIT and
                next_recommended_wait_step ~= def.SHORTWAIT and
                next_recommended_wait_step ~= def.VERYSHORTWAIT and
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
