local def = require("definitions")
local settings = require("settings")
require("helpers")
require("yal")
local autoUnicom = require("auto_unicom")

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
local remember_ignored_updates
local show_yal_update_confirm
local run_yal_update_install
local startupUpdateCheckDone = false
local startupUpdateCheckEarliest = 0
local startupUpdateCheckPerformed = false
local menu_taxi = nil
local taxiGateLastLogTime = 0
local autoUnicomRuntime = {
    refs = nil,
    nextBindAt = 0,
    unavailableLogged = false,
    sources = {
        pressure_altitude = globalProperty("sim/flightmodel2/position/pressure_altitude"),
        aircraft_icao = globalPropertys("sim/aircraft/view/acf_ICAO")
    }
}

local function auto_unicom_refs_valid(refs)
    if type(refs) ~= "table" then return false end
    for _, prop in pairs(refs) do
        if not prop or not isProperty(prop) then return false end
    end
    return true
end

local function bind_auto_unicom_datarefs()
    if auto_unicom_refs_valid(autoUnicomRuntime.refs) then return true end
    autoUnicomRuntime.refs = nil

    local now = os.time() or 0
    if now < autoUnicomRuntime.nextBindAt then return false end
    autoUnicomRuntime.nextBindAt = now + 5

    local pluginId = sasl.findPluginBySignature("wahltho.ivao.monitor")
    if pluginId == NO_PLUGIN_ID then
        if not autoUnicomRuntime.unavailableLogged then
            autoUnicomRuntime.unavailableLogged = true
            helpers.logInfoTS("IVAO Auto-Unicom enabled but IVAO Monitor is not available")
        end
        return false
    end

    local base = "ivao_monitor/autounicom/"
    local bound = {
        api_version = globalProperty(base .. "api_version"),
        ready = globalProperty(base .. "ready"),
        mode = globalProperty(base .. "mode"),
        transport_state = globalProperty(base .. "transport_state"),
        request_text = globalPropertys(base .. "request_text"),
        request_seq = globalProperty(base .. "request_seq"),
        result_seq = globalProperty(base .. "result_seq"),
        result_code = globalProperty(base .. "result_code"),
        result_detail = globalPropertys(base .. "result_detail")
    }
    if not auto_unicom_refs_valid(bound) then
        if not autoUnicomRuntime.unavailableLogged then
            autoUnicomRuntime.unavailableLogged = true
            helpers.logInfoTS("IVAO Auto-Unicom enabled but API DataRefs are not ready")
        end
        return false
    end

    autoUnicomRuntime.refs = bound
    autoUnicomRuntime.unavailableLogged = false
    helpers.logInfoTS("IVAO Auto-Unicom DataRefs bound")
    return true
end

autoUnicom.configure({
    yal = yal,
    def = def,
    helpers = helpers,
    sources = autoUnicomRuntime.sources,
    getRefs = function() return autoUnicomRuntime.refs end
})

autoUnicomRuntime.repeatCommand = sasl.createCommand(
    def.APPNAMEPREFIX .. "/autounicom/repeat_last",
    "Repeat Last IVAO Auto-Unicom Message"
)
sasl.registerCommandHandler(autoUnicomRuntime.repeatCommand, 0, function(phase)
    if phase == SASL_COMMAND_BEGIN then
        local enabled = settings and settings.appSettings
            and tonumber(settings.appSettings[def.CONFIGIVAOAUTOUNICOM] or 0) == def.ON
        if enabled then bind_auto_unicom_datarefs() end
        autoUnicom.repeatLastMessage(enabled == true)
    end
    return 0
end)

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
            helpers.logInfoTS("Startup update popup snoozed")
        end,
        onIgnore = function(payload)
            remember_ignored_updates(payload)
        end,
        onInstall = function(payload)
            return show_yal_update_confirm(payload)
        end,
        onConfirm = function(payload)
            return run_yal_update_install(payload)
        end,
        onCancel = function()
            helpers.logInfoTS("YAL update confirmation cancelled")
        end
    })
    updatePopupComponent = comp
    local w, h = mod.windowSize()
    local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)
    local posX = xRoot + math.max(0, (wRoot - w) / 2)
    local posY = yRoot + math.max(0, (hRoot - h) * 0.25)

    updatePopupWindow = contextWindow {
        name = "YAL Update Status",
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

local function get_yal_feed_comparison(stableVersion, betaVersion)
    if not stableVersion or stableVersion == "" or not betaVersion or betaVersion == "" then
        return "unknown"
    end
    if tostring(stableVersion) == tostring(betaVersion) then
        return "same"
    end
    if helpers.isVersionNewer and helpers.isVersionNewer(betaVersion, stableVersion) then
        return "beta-newer"
    end
    if helpers.isVersionNewer and helpers.isVersionNewer(stableVersion, betaVersion) then
        return "stable-newer"
    end
    return "unknown"
end

local function get_update_popup_title(yalAvailable, ziboAvailable, betaUpdateAvailable, yalInstallKind)
    if yalAvailable and ziboAvailable then
        return "YAL and Zibo Updates Available"
    end
    if yalAvailable then
        if yalInstallKind == "stable" then
            return "YAL Stable Version Available"
        end
        if betaUpdateAvailable then
            return "YAL Beta Update Available"
        end
        return "YAL Update Available"
    end
    if ziboAvailable then
        return "Zibo Update Available"
    end
    return "Update Status"
end

local function choose_yal_ignore_version(yalInfo)
    if not yalInfo or not yalInfo.detectedAvailable then
        return ""
    end
    if yalInfo.installVersion and yalInfo.installVersion ~= "" then
        return tostring(yalInfo.installVersion)
    end
    local candidate = ""
    if yalInfo.channelAvailable and yalInfo.latest and yalInfo.latest ~= "" then
        candidate = tostring(yalInfo.latest)
    end
    if yalInfo.checkBeta and yalInfo.stableAvailable and yalInfo.latestStable and yalInfo.latestStable ~= "" then
        if candidate == "" or (helpers.isVersionNewer and helpers.isVersionNewer(yalInfo.latestStable, candidate)) then
            candidate = tostring(yalInfo.latestStable)
        end
    end
    return candidate
end

local function is_ignored_update(version, ignoredVersion)
    return version and version ~= "" and ignoredVersion and ignoredVersion ~= "" and tostring(version) == tostring(ignoredVersion)
end

remember_ignored_updates = function(payload)
    if not settings or not settings.appSettings or not payload then
        return
    end
    local changed = false
    local yalInfo = payload.yal
    if yalInfo and yalInfo.available and yalInfo.ignoreVersion and yalInfo.ignoreVersion ~= "" then
        settings.appSettings[def.CONFIGIGNOREDYALUPDATEVERSION] = tostring(yalInfo.ignoreVersion)
        changed = true
        helpers.logInfoTS("Ignored YAL update version v" .. tostring(yalInfo.ignoreVersion))
    end
    local ziboInfo = payload.zibo
    if ziboInfo and ziboInfo.available and ziboInfo.ignoreVersion and ziboInfo.ignoreVersion ~= "" then
        settings.appSettings[def.CONFIGIGNOREDZIBOUPDATEVERSION] = tostring(ziboInfo.ignoreVersion)
        changed = true
        helpers.logInfoTS("Ignored Zibo update version v" .. tostring(ziboInfo.ignoreVersion))
    end
    if changed and settings.writeSettings then
        settings.writeSettings(settings.appSettings)
    end
end

show_yal_update_confirm = function(payload)
    local yalInfo = payload and payload.yal or nil
    if not yalInfo or not updatePopupComponent or not updatePopupComponent.setPayload then
        return true
    end
    local current = tostring(yalInfo.current or def.VERSION or "?")
    local target = tostring(yalInfo.installVersion or yalInfo.latest or "?")
    local verb = "update"
    if helpers.isVersionNewer and helpers.isVersionNewer(current, target) then
        verb = "replace"
    end
    updatePopupComponent:setPayload({
        mode = "confirm",
        title = "Confirm YAL Update",
        lines = {
            string.format("Do you really want to %s YAL from v%s to v%s?", verb, current, target),
            "The update will be installed from the selected YAL depot.",
        },
        okLabel = "OK",
        cancelLabel = "Cancel",
        yal = yalInfo,
    })
    return false
end

run_yal_update_install = function(payload)
    local yalInfo = payload and payload.yal or nil
    if not yalInfo or not helpers.installYalUpdateFromDepot then
        return true
    end
    local result = helpers.installYalUpdateFromDepot(yalInfo.installBeta == true)
    if updatePopupComponent and updatePopupComponent.setPayload then
        updatePopupComponent:setPayload({
            mode = "status",
            title = result and result.title or "YAL Update",
            lines = (result and result.lines) or { "YAL update finished." },
            okLabel = "OK",
        })
    end
    return false
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
    local lvlupRelease = helpers.getLatchedLevelUpRelease()
    local lvlupFm = helpers.getLatchedLevelUpFm()
    local isLevelUp = helpers.isLevelUp()
    if isLevelUp then
        helpers.logInfoTS(string.format(
            "LevelUp detected (release %s, flight model %s)",
            tostring(lvlupRelease ~= "" and lvlupRelease or "?"),
            tostring(lvlupFm ~= "" and lvlupFm or "?")
        ))
    else
        helpers.logInfoTS(string.format(
            "Zibo installed version: v%s",
            tostring((normalize_zibo_release(ziboRelease) ~= "") and normalize_zibo_release(ziboRelease) or "?")
        ))
    end
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
    local installedPrerelease = is_yal_beta_version()
    local checkBeta = showBetaUpdates
    local _, yalLatestRaw = helpers.checkForUpdate(checkBeta)
    local yalStableAvailable, yalStable = helpers.checkForUpdate(false)
    local yalBetaAvailable, yalBeta = helpers.checkForUpdate(true)
    local yalSelectedVersion = checkBeta and yalBeta or yalStable
    if not yalSelectedVersion or yalSelectedVersion == "" then
        yalSelectedVersion = yalLatestRaw
    end
    local yalSelectedDepotDiffers = yalSelectedVersion and yalSelectedVersion ~= "" and tostring(yalSelectedVersion) ~= tostring(def.VERSION or "")
    local yalSelectedUpdateAvailable = checkBeta and yalBetaAvailable or yalStableAvailable
    local yalStableDowngradeAvailable = installedPrerelease and not showBetaUpdates and yalSelectedDepotDiffers
    local yalDetectedAvailable = yalSelectedUpdateAvailable or yalStableDowngradeAvailable
    local feedComparison = get_yal_feed_comparison(yalStable, yalBeta)
    local channelReason = "stable setting"
    if showBetaUpdates then
        channelReason = "setting enabled"
    elseif installedPrerelease then
        channelReason = "stable selected on prerelease"
    end

    local ziboDetectedAvailable, ziboLatest, ziboLocal = false, "", ""
    if isLevelUp then
        helpers.logInfoTS("Zibo update check skipped (LevelUp detected)")
    else
        ziboDetectedAvailable, ziboLatest, ziboLocal = helpers.checkForZiboUpdate(ziboRelease)
        helpers.logInfoTS(string.format(
            "Zibo feed latest version: v%s",
            tostring((ziboLatest and ziboLatest ~= "") and ziboLatest or "?")
        ))
    end

    local ignoredYalVersion = tostring(settings.appSettings[def.CONFIGIGNOREDYALUPDATEVERSION] or "")
    local ignoredZiboVersion = tostring(settings.appSettings[def.CONFIGIGNOREDZIBOUPDATEVERSION] or "")
    local yalInfo = {
        checkBeta = checkBeta,
        detectedAvailable = yalDetectedAvailable,
        channelAvailable = yalDetectedAvailable,
        stableAvailable = yalStableAvailable,
        betaAvailable = yalBetaAvailable,
        latest = yalSelectedVersion,
        latestStable = yalStable,
        latestBeta = yalBeta,
        current = tostring(def.VERSION or ""),
        installBeta = checkBeta,
        installKind = checkBeta and "beta" or "stable",
        installVersion = yalSelectedVersion,
        installLabel = checkBeta and "Install YAL Beta" or "Install YAL Stable",
    }
    yalInfo.ignoreVersion = choose_yal_ignore_version(yalInfo)
    yalInfo.ignored = is_ignored_update(yalInfo.ignoreVersion, ignoredYalVersion)
    yalInfo.available = yalDetectedAvailable and not yalInfo.ignored

    local ziboInfo = {
        detectedAvailable = ziboDetectedAvailable,
        latest = ziboLatest,
        current = isLevelUp and tostring(lvlupRelease or "") or ziboLocal,
        skipped = isLevelUp,
        skippedReason = isLevelUp and "LevelUp detected" or "",
        levelUpRelease = lvlupRelease,
        levelUpFlightModel = lvlupFm,
        ignoreVersion = ziboLatest,
    }
    ziboInfo.ignored = is_ignored_update(ziboInfo.ignoreVersion, ignoredZiboVersion)
    ziboInfo.available = ziboDetectedAvailable and not ziboInfo.ignored

    if yalInfo.ignored then
        helpers.logInfoTS("Startup update check: ignored YAL update v" .. tostring(yalInfo.ignoreVersion))
    end
    if ziboInfo.ignored then
        helpers.logInfoTS("Startup update check: ignored Zibo update v" .. tostring(ziboInfo.ignoreVersion))
    end

    helpers.startupUpdateInfo = {
        ts = now,
        channel = {
            active = checkBeta and "beta" or "stable",
            reason = channelReason,
            stableVsBeta = feedComparison,
            showBetaUpdates = showBetaUpdates,
            installedPrerelease = installedPrerelease,
        },
        yal = yalInfo,
        zibo = ziboInfo,
    }

    if not yalInfo.available and not ziboInfo.available then
        if yalInfo.ignored or ziboInfo.ignored then
            helpers.logInfoTS("Startup update check: all available updates ignored")
        else
            helpers.logInfoTS("Startup update check: no updates available")
        end
        return
    end

    maybeInitUpdatePopupWindow()
    if updatePopupComponent and updatePopupComponent.setPayload then
        updatePopupComponent:setPayload({
            title = get_update_popup_title(yalInfo.available, ziboInfo.available, checkBeta and yalInfo.available, yalInfo.installKind),
            checkedAt = now,
            channel = helpers.startupUpdateInfo.channel,
            yal = helpers.startupUpdateInfo.yal,
            zibo = helpers.startupUpdateInfo.zibo,
            laterLabel = "Later",
            installLabel = yalInfo.installLabel,
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
    if autoUnicom and autoUnicom.rebaseline then
        autoUnicom.rebaseline()
    end

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
        local autoUnicomEnabled = settings and settings.appSettings
            and tonumber(settings.appSettings[def.CONFIGIVAOAUTOUNICOM] or 0) == def.ON
        if autoUnicomEnabled then
            bind_auto_unicom_datarefs()
        end
        autoUnicom.tick(autoUnicomEnabled == true)
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
        local forceImmediateCycle = yal and yal.forceImmediateCycle == true

        if current_elapsed_time >= waitstep or forceImmediateCycle then
            if forceImmediateCycle then
                yal.forceImmediateCycle = false
                sasl.logDebug("UPDATE: Immediate do_yal() cycle requested.")
            end
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
