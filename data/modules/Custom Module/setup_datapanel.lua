require("windows")
require("settings")
require("messages")
require("helpers")

local def = require("definitions")

defineProperty(size, { 200, 200 })

local sizeProp = size
local initialSize = get(sizeProp)
local wSize = initialSize[1]
local hSize = initialSize[2]

local showBetaUpdates = toboolean(settings.appSettings.SHOWBETAUPDATES)
local YALupdateavailable, YALnewversion = helpers.checkForUpdate(showBetaUpdates)

local wTitle = string.format("%s v%s", def.APPNAMEPREFIXLONG, def.VERSION)
if YALupdateavailable then
    wTitle = wTitle .. "   " .. messages.translation['UPDATEAVAILABLE'] .. " v" .. YALnewversion
end

local x_col1 = 10
local x_col2 = x_col1 + wSize / 2 + 90
local cb_w = 10
local cb_h = 10
local scrollOffset = 0
local scrollMax = 0
local scrollDrag = nil

local generalControls = {
    "USEGROUNDPOWER",
    "VOICEREADBACK",
    "AUTOFUNCTIONS",
    "VOICEADVICEONLY",
    "BPBINTEGRATION",
    "YANSHINTEGRATION",
    "AUTOFUELING",
    "WAKEOVERRIDE",
    "AUTOANTIICE",
    "AUTOWIPER",
    "AUTOCENTERTANKHANDLING",
    "AUTOFLAPS",
    "AUTOBARO",
    "VIEWCHANGES",
    "AUTOCHOCKSPB",
    "SPEEDRESTR250",
    "VREF30",
    "CUSTOMAPPROACHCALC",
    "LOWERDU",
    "HIDEEFBS",
}

local viewControls = {
    "VIEWMAINPANEL",
    "VIEWPEDESTAL",
    "VIEWOVERHEADPANEL",
    "VIEWFMS",
    "VIEWTHROTTLE",
    "VIEWUPPEROVERHEADPANEL",
}

local brightnessControls = {
    "BRIGHTMAINPANEL",
    "BRIGHTOVERHEAD",
    "BRIGHTPEDESTRAL",
    "GENBRIGHTBACKGROUND",
    "GENBRIGHTAFDSFLOOD",
    "GENBRIGHTPEDESTRALFLOOD",
    "INSTRBRIGHTOUTBDDU",
    "INSTRBRIGHTINBDDU",
    "INSTRBRIGHTUPPERDU",
    "INSTRBRIGHTLOWDU",
    "INSTRBRIGHTINBDDUS",
}

local generalRowStartY = hSize - 80
local generalRowStep = def.lineHeight + 4
local generalHeaderY = generalRowStartY + 20
local generalBottomY = generalRowStartY - (generalRowStep * (#generalControls - 1))
local postGeneralStartY = generalBottomY - 40
local postGeneralGap = def.lineHeight * 1.5 + 10
local lowerBlockStartY = postGeneralStartY - (2 * postGeneralGap) - 30
local lowerBlockGap = def.lineHeight + 12
local generalRowStartYAdj = generalRowStartY
local generalHeaderYAdj = generalHeaderY

local viewHeaderY = 0
local viewStartY = 0
local viewStep = 0
local brightnessHeaderY = 0
local brightnessStartY = 0
local brightnessStep = 0
local ignoreBrightY = 0
local miscHeaderY = 0
local showBetaY = 0
local debugY = 0

local function updateLayoutConstants()
    local currentSize = get(size)
    wSize = currentSize[1]
    hSize = currentSize[2]

    x_col1 = 10
    x_col2 = x_col1 + wSize / 2 + 90

    generalRowStartY = hSize - 80
    generalRowStep = def.lineHeight + 4
    generalHeaderY = generalRowStartY + 20
    generalBottomY = generalRowStartY - (generalRowStep * (#generalControls - 1))
    postGeneralStartY = generalBottomY - 40
    postGeneralGap = def.lineHeight * 1.5 + 10
    lowerBlockStartY = postGeneralStartY - (2 * postGeneralGap) - 30
    lowerBlockGap = def.lineHeight + 12

    viewHeaderY = hSize - 60
    viewStartY = hSize - 90
    viewStep = def.lineHeight * 1.8

    brightnessHeaderY = viewStartY - (viewStep * #viewControls) - 4
    brightnessStartY = brightnessHeaderY - 28
    brightnessStep = def.lineHeight * 1.8

    ignoreBrightY = brightnessStartY - (brightnessStep * #brightnessControls) - 8
    miscHeaderY = ignoreBrightY - 24
    showBetaY = miscHeaderY - 18
    debugY = showBetaY - 18
end

local skipDraw = {}
for _, key in ipairs(generalControls) do
    skipDraw[key] = true
end
skipDraw.general = true
components = {}

local current_input_field = nil

local function process_key(char, vkey, shift, ctrl, alt, event)
    if event == KB_DOWN_EVENT and current_input_field ~= nil then
        if char == SASL_KEY_ESCAPE then
            wdef[current_input_field].isFocused = false
            wdef[current_input_field].value = settings.appSettings[current_input_field]
            current_input_field = nil
            return true
        end
        if char == SASL_KEY_RETURN and #wdef[current_input_field].value >= wdef[current_input_field].value_min_len then
            settings.appSettings[current_input_field] = wdef[current_input_field].value
            settings.writeSettings(settings.appSettings)
            wdef[current_input_field].isFocused = false
            current_input_field = nil
            return true
        end
        if char == 8 or (char >= wdef[current_input_field].ascii_min and char <= wdef[current_input_field].ascii_max) then
            local current_input = wdef[current_input_field].value
            if char ~= 8 and #current_input < wdef[current_input_field].value_max_len then
                current_input = current_input .. string.char(char)
            end
            if char == 8 and #current_input > 0 then
                ---@diagnostic disable-next-line: param-type-mismatch
                current_input = string.sub(current_input, 1, #current_input - 1)
            end
            wdef[current_input_field].value = current_input
        end
    end
    return false
end

function setFocusOnInput(element)
    if current_input_field ~= nil then
        wdef[current_input_field].isFocused = false
        wdef[current_input_field].value = settings.appSettings[current_input_field]
    end
    if element ~= nil then
        current_input_field = element
        wdef[element].value = ""
        wdef[element].isFocused = true
    else    
        current_input_field = element      
        register_handler(nil)
    end
end

function decrIncrElement(element, incr)
    local value = tonumber(settings.appSettings[element])
    if incr == true then
        if (value + wdef[element].val_incr) <= wdef[element].val_max then
            settings.appSettings[element] = tostring(value + wdef[element].val_incr)
            settings.writeSettings(settings.appSettings)
            wdef[element].value = settings.appSettings[element]
        end
    else
        if (value - wdef[element].val_incr) >= wdef[element].val_min then
            settings.appSettings[element] = tostring(value - wdef[element].val_incr)
            settings.writeSettings(settings.appSettings)
            wdef[element].value = settings.appSettings[element]
        end
    end
end

function getElementInteractive(element)
    if element.x2 == nil then
        return {
            { element.x, element.y, element.w, element.h },
            element.onMouseDown_
        }
    else
        return {
            { element.x,  element.y, element.w, element.h },
            element.onMouseDown_M_,
            { element.x2, element.y, element.w, element.h },
            element.onMouseDown_P_,
        }
    end
end

local function drawGeneralDynamic()
    local baseX = x_col1
    windows.drawText({ t = messages.translation['GENERAL'], x = baseX, y = generalHeaderYAdj, font = def.wFont })
    local rowY = generalRowStartYAdj
    for _, key in ipairs(generalControls) do
        local label = messages.translation[key] or key
        local box = {
            t = label,
            value = toboolean(settings.appSettings[key]),
            x = baseX + 60,
            y = rowY,
            w = cb_w,
            h = cb_h,
        }
        windows.drawCheckBox(box)
        rowY = rowY - generalRowStep
    end
end

local function buildGeneralInteractives()
    local interactives = {}
    local baseX = x_col1
    local rowY = generalRowStartYAdj
    for _, key in ipairs(generalControls) do
        local pos = { baseX + 60, rowY, cb_w, cb_h }
        table.insert(interactives, interactive {
            position = pos,
            onMouseDown = function()
                setFocusOnInput(nil)
                settings.appSettings[key] = not_(settings.appSettings[key])
                settings.writeSettings(settings.appSettings)
                return true
            end
        })
        rowY = rowY - generalRowStep
    end
    return interactives
end

wdef = {
    mainWindow = {
        w = wSize,
        h = hSize,
        wtitle = wTitle,
    },
    closeButton = {
        t = "x",
        x = wSize - def.closeXWidth,
        y = hSize - def.closeXHeight,
        w = def.closeXWidth,
        h = def.closeXHeight,
        withBorder = false,
        draw_ = function()
            windows.drawButton(wdef.closeButton, true)
        end,
        onMouseDown_ = function()
            register_handler(nil)
            setup_datapanel:setIsVisible(false)
        end
    },
    TODPAUSEQUITTIME = {
        t = messages.translation['TODPAUSEQUITTIME'],
        value = tostring(settings.appSettings.TODPAUSEQUITTIME),
        x = x_col1 +20,
        y = postGeneralStartY,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 5,
        draw_ = function()
            windows.inputTextBox(wdef.TODPAUSEQUITTIME)
        end,
        onMouseDown_ = function()
            setFocusOnInput("TODPAUSEQUITTIME")
            register_handler(process_key)
            return true
        end

    },
    SAVETIME = {
        t = messages.translation['SAVETIME'],
        value = tostring(settings.appSettings.SAVETIME),
        x = x_col1 +20,
        y = postGeneralStartY - postGeneralGap,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 5,
        draw_ = function()
            windows.inputTextBox(wdef.SAVETIME)
        end,
        onMouseDown_ = function()
            setFocusOnInput("SAVETIME")
            register_handler(process_key)
            return true
        end

    },
    SAVENUMBER = {
        t = messages.translation['SAVENUMBER'],
        value = tostring(settings.appSettings.SAVENUMBER),
        x = x_col1 +20,
        y = postGeneralStartY - (2 * postGeneralGap),
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 5,
        draw_ = function()
            windows.inputTextBox(wdef.SAVENUMBER)
        end,
        onMouseDown_ = function()
            setFocusOnInput("SAVENUMBER")
            register_handler(process_key)
            return true
        end

    },
    WAKEOVERRIDE = {
        t = messages.translation['WAKEOVERRIDE'],
        value = toboolean(settings.appSettings.WAKEOVERRIDE),
        x = x_col1 + 60,
        y = hSize - 315,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.WAKEOVERRIDE = not_(settings.appSettings.WAKEOVERRIDE)
            settings.writeSettings(settings.appSettings)
            wdef.WAKEOVERRIDE.value = toboolean(settings.appSettings.WAKEOVERRIDE)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.WAKEOVERRIDE)
        end
    },
    AUTOANTIICE = {
        t = messages.translation['AUTOANTIICE'],
        value = toboolean(settings.appSettings.AUTOANTIICE),
        x = x_col1 + 60,
        y = hSize - 335,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.AUTOANTIICE = not_(settings.appSettings.AUTOANTIICE)
            settings.writeSettings(settings.appSettings)
            wdef.AUTOANTIICE.value = toboolean(settings.appSettings.AUTOANTIICE)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.AUTOANTIICE)
        end
    },
    AUTOWIPER = {
        t = messages.translation['AUTOWIPER'],
        value = toboolean(settings.appSettings.AUTOWIPER),
        x = x_col1 + 60,
        y = hSize - 355,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.AUTOWIPER = not_(settings.appSettings.AUTOWIPER)
            settings.writeSettings(settings.appSettings)
            wdef.AUTOWIPER.value = toboolean(settings.appSettings.AUTOWIPER)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.AUTOWIPER)
        end
    },
    AUTOCENTERTANKHANDLING = {
        t = messages.translation['AUTOCENTERTANKHANDLING'],
        value = toboolean(settings.appSettings.AUTOCENTERTANKHANDLING),
        x = x_col1 + 60,
        y = hSize - 375,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.AUTOCENTERTANKHANDLING = not_(settings.appSettings.AUTOCENTERTANKHANDLING)
            settings.writeSettings(settings.appSettings)
            wdef.AUTOCENTERTANKHANDLING.value = toboolean(settings.appSettings.AUTOCENTERTANKHANDLING)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.AUTOCENTERTANKHANDLING)
        end
    },
    AUTOFLAPS = {
        t = messages.translation['AUTOFLAPS'],
        value = toboolean(settings.appSettings.AUTOFLAPS),
        x = x_col1 + 60,
        y = hSize - 395,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.AUTOFLAPS = not_(settings.appSettings.AUTOFLAPS)
            settings.writeSettings(settings.appSettings)
            wdef.AUTOFLAPS.value = toboolean(settings.appSettings.AUTOFLAPS)
        end,      
            draw_ = function()
            windows.drawCheckBox(wdef.AUTOFLAPS)
        end
    },
    AUTOBARO = {
        t = messages.translation['AUTOBARO'],
        value = toboolean(settings.appSettings.AUTOBARO),
        x = x_col1 + 60,
        y = hSize - 415,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.AUTOBARO = not_(settings.appSettings.AUTOBARO)
            settings.writeSettings(settings.appSettings)
            wdef.AUTOBARO.value = toboolean(settings.appSettings.AUTOBARO)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.AUTOBARO)
        end
    },
    VIEWCHANGES = {
        t = messages.translation['VIEWCHANGES'],
        value = toboolean(settings.appSettings.VIEWCHANGES),
        x = x_col1 + 60,
        y = hSize - 435,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.VIEWCHANGES = not_(settings.appSettings.VIEWCHANGES)
            settings.writeSettings(settings.appSettings)
            wdef.VIEWCHANGES.value = toboolean(settings.appSettings.VIEWCHANGES)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.VIEWCHANGES)
        end
    },
    AUTOCHOCKSPB = {
        t = messages.translation['AUTOCHOCKSPB'],
        value = toboolean(settings.appSettings.AUTOCHOCKSPB),
        x = x_col1 + 60,
        y = hSize - 455,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.AUTOCHOCKSPB = not_(settings.appSettings.AUTOCHOCKSPB)
            settings.writeSettings(settings.appSettings)
            wdef.AUTOCHOCKSPB.value = toboolean(settings.appSettings.AUTOCHOCKSPB)
            if yal and yal.configvalues then
                yal.configvalues[def.CONFIGAUTOCHOCKSPB] = settings.appSettings.AUTOCHOCKSPB
            end
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.AUTOCHOCKSPB)
        end
    },
    SPEEDRESTR250 = {
        t = messages.translation['SPEEDRESTR250'],
        value = toboolean(settings.appSettings.SPEEDRESTR250),
        x = x_col1 +60,
        y = hSize - 475,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.SPEEDRESTR250 = not_(settings.appSettings.SPEEDRESTR250)
            settings.writeSettings(settings.appSettings)
            wdef.SPEEDRESTR250.value = toboolean(settings.appSettings.SPEEDRESTR250)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.SPEEDRESTR250)
        end
    },
    VREF30 = {
        t = messages.translation['VREF30'],
        value = toboolean(settings.appSettings.VREF30),
        x = x_col1 + 60,
        y = hSize - 495,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.VREF30 = not_(settings.appSettings.VREF30)
            settings.writeSettings(settings.appSettings)
            wdef.VREF30.value = toboolean(settings.appSettings.VREF30)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.VREF30)
        end
    },
    CUSTOMAPPROACHCALC = {
        t = messages.translation['CUSTOMAPPROACHCALC'],
        value = toboolean(settings.appSettings.CUSTOMAPPROACHCALC),
        x = x_col1 + 60,
        y = hSize - 515,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.CUSTOMAPPROACHCALC = not_(settings.appSettings.CUSTOMAPPROACHCALC)
            settings.writeSettings(settings.appSettings)
            wdef.CUSTOMAPPROACHCALC.value = toboolean(settings.appSettings.CUSTOMAPPROACHCALC)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.CUSTOMAPPROACHCALC)
        end
    },
    LOWERAIRSPACEALT = {
        t = messages.translation['LOWERAIRSPACEALT'],
        value = tostring(settings.appSettings.LOWERAIRSPACEALT),
        x = x_col1 + 20,
        y = lowerBlockStartY,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 5,
        draw_ = function()
            windows.inputTextBox(wdef.LOWERAIRSPACEALT)
        end,
        onMouseDown_ = function()
            setFocusOnInput("LOWERAIRSPACEALT")
            register_handler(process_key)
            return true
        end
    },
    PACKSRESTOREALT = {
        t = messages.translation['PACKSRESTOREALT'],
        value = tostring(settings.appSettings.PACKSRESTOREALT),
        x = x_col1 + 20,
        y = lowerBlockStartY - lowerBlockGap,
        w = 60,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 5,
        draw_ = function()
            windows.inputTextBox(wdef.PACKSRESTOREALT)
        end,
        onMouseDown_ = function()
            setFocusOnInput("PACKSRESTOREALT")
            register_handler(process_key)
            return true
        end
    },
    BANKANGLEMAX = {
        t = messages.translation['BANKANGLEMAX'],
        value = tostring(settings.appSettings.BANKANGLEMAX),
        x = x_col1,
        x2 = x_col1 + 50,
        y = lowerBlockStartY - (2 * lowerBlockGap),
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 1,
        val_max = 4,
        val_incr = 1,
        draw_ = function()
            windows.slider(wdef.BANKANGLEMAX)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("BANKANGLEMAX", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("BANKANGLEMAX", true)
        end,

    },
    LOWERDU = {
        t = messages.translation['LOWERDU'],
        value = toboolean(settings.appSettings.LOWERDU),
        x = x_col1 + 60,
        y = hSize - 620,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.LOWERDU = not_(settings.appSettings.LOWERDU)
            settings.writeSettings(settings.appSettings)
            wdef.LOWERDU.value = toboolean(settings.appSettings.LOWERDU)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.LOWERDU)
        end
    },
    TRANSPONDERCODE = {
        t = messages.translation['TRANSPONDERCODE'],
        value = tostring(settings.appSettings.TRANSPONDERCODE),
        x = x_col1 + 20,
        y = lowerBlockStartY - (3 * lowerBlockGap),
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 55,
        value_min_len = 4,
        value_max_len = 4,
        draw_ = function()
            windows.inputTextBox(wdef.TRANSPONDERCODE)
        end,
        onMouseDown_ = function()
            setFocusOnInput("TRANSPONDERCODE")
            register_handler(process_key)
            return true
        end
    },
    GEARDOWNFLAPS = {
        t = messages.translation['GEARDOWNFLAPS'],
        value = tostring(settings.appSettings.GEARDOWNFLAPS),
        x = x_col1 + 20,
        y = lowerBlockStartY - (4 * lowerBlockGap),
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 55,
        value_min_len = 1,
        value_max_len = 2,
        draw_ = function()
            windows.inputTextBox(wdef.GEARDOWNFLAPS)
        end,
        onMouseDown_ = function()
            setFocusOnInput("GEARDOWNFLAPS")
            register_handler(process_key)
            return true
        end
    },
    HIDEEFBS = {
        t = messages.translation['HIDEEFBS'],
        value = toboolean(settings.appSettings.HIDEEFBS),
        x = x_col1 + 60,
        y = hSize - 690,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.HIDEEFBS = not_(settings.appSettings.HIDEEFBS)
            settings.writeSettings(settings.appSettings)
            wdef.HIDEEFBS.value = toboolean(settings.appSettings.HIDEEFBS)
        end,      
            draw_ = function()
            windows.drawCheckBox(wdef.HIDEEFBS)
        end
    },

    -- Column 2
    views = {
        t = messages.translation['VIEWS'],
        x = x_col2,
        y = hSize - 60,
        draw_ = function()
            windows.drawText(wdef.views)
        end
    },
    VIEWMAINPANEL = {
        t = messages.translation['VIEWMAINPANEL'],
        value = tostring(settings.appSettings.VIEWMAINPANEL),
        x = x_col2 + 20,
        y = hSize - 90,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 2,
        draw_ = function()
            windows.inputTextBox(wdef.VIEWMAINPANEL)
        end,
        onMouseDown_ = function()
            setFocusOnInput("VIEWMAINPANEL")
            register_handler(process_key)
            return true
        end
    },
    VIEWPEDESTAL = {
        t = messages.translation['VIEWPEDESTAL'],
        value = tostring(settings.appSettings.VIEWPEDESTAL),
        x = x_col2 + 20,
        y = hSize - 120,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 2,
        draw_ = function()
            windows.inputTextBox(wdef.VIEWPEDESTAL)
        end,
        onMouseDown_ = function()
            setFocusOnInput("VIEWPEDESTAL")
            register_handler(process_key)
            return true
        end
    },
    VIEWOVERHEADPANEL = {
        t = messages.translation['VIEWOVERHEADPANEL'],
        value = tostring(settings.appSettings.VIEWOVERHEADPANEL),
        x = x_col2 + 20,
        y = hSize - 150,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 2,
        draw_ = function()
            windows.inputTextBox(wdef.VIEWOVERHEADPANEL)
        end,
        onMouseDown_ = function()
            setFocusOnInput("VIEWOVERHEADPANEL")
            register_handler(process_key)
            return true
        end
    },
    VIEWFMS = {
        t = messages.translation['VIEWFMS'],
        value = tostring(settings.appSettings.VIEWFMS),
        x = x_col2 + 20,
        y = hSize - 180,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 2,
        draw_ = function()
            windows.inputTextBox(wdef.VIEWFMS)
        end,
        onMouseDown_ = function()
            setFocusOnInput("VIEWFMS")
            register_handler(process_key)
            return true
        end
    },
    VIEWTHROTTLE = {
        t = messages.translation['VIEWTHROTTLE'],
        value = tostring(settings.appSettings.VIEWTHROTTLE),
        x = x_col2 + 20,
        y = hSize - 210,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 2,
        draw_ = function()
            windows.inputTextBox(wdef.VIEWTHROTTLE)
        end,
        onMouseDown_ = function()
            setFocusOnInput("VIEWTHROTTLE")
            register_handler(process_key)
            return true
        end
    },
    VIEWUPPEROVERHEADPANEL = {
        t = messages.translation['VIEWUPPEROVERHEADPANEL'],
        value = tostring(settings.appSettings.VIEWUPPEROVERHEADPANEL),
        x = x_col2 + 20,
        y = hSize - 240,
        w = 50,
        h = def.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48,
        ascii_max = 57,
        value_min_len = 1,
        value_max_len = 2,
        draw_ = function()
            windows.inputTextBox(wdef.VIEWUPPEROVERHEADPANEL)
        end,
        onMouseDown_ = function()
            setFocusOnInput("VIEWUPPEROVERHEADPANEL")
            register_handler(process_key)
            return true
        end
    },
    brightness = {
        t = messages.translation['BRIGHTNESS'],
        x = x_col2,
        y = hSize - 270,
        draw_ = function()
            windows.drawText(wdef.brightness)
        end
    },
    BRIGHTMAINPANEL = {
        t = messages.translation['BRIGHTMAINPANEL'],
        value = tostring(settings.appSettings.BRIGHTMAINPANEL),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 300,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.BRIGHTMAINPANEL)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("BRIGHTMAINPANEL", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("BRIGHTMAINPANEL", true)
        end,

    },
    BRIGHTOVERHEAD = {
        t = messages.translation['BRIGHTOVERHEAD'],
        value = tostring(settings.appSettings.BRIGHTOVERHEAD),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 330,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.BRIGHTOVERHEAD)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("BRIGHTOVERHEAD", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("BRIGHTOVERHEAD", true)
        end,

    },
    BRIGHTPEDESTRAL = {
        t = messages.translation['BRIGHTPEDESTRAL'],
        value = tostring(settings.appSettings.BRIGHTPEDESTRAL),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 360,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.BRIGHTPEDESTRAL)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("BRIGHTPEDESTRAL", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("BRIGHTPEDESTRAL", true)
        end,

    },
    GENBRIGHTBACKGROUND = {
        t = messages.translation['GENBRIGHTBACKGROUND'],
        value = tostring(settings.appSettings.GENBRIGHTBACKGROUND),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 390,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.GENBRIGHTBACKGROUND)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("GENBRIGHTBACKGROUND", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("GENBRIGHTBACKGROUND", true)
        end,


    },
    GENBRIGHTAFDSFLOOD = {
        t = messages.translation['GENBRIGHTAFDSFLOOD'],
        value = tostring(settings.appSettings.GENBRIGHTAFDSFLOOD),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 420,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.GENBRIGHTAFDSFLOOD)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("GENBRIGHTAFDSFLOOD", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("GENBRIGHTAFDSFLOOD", true)
        end,

    },
    GENBRIGHTPEDESTRALFLOOD = {
        t = messages.translation['GENBRIGHTPEDESTRALFLOOD'],
        value = tostring(settings.appSettings.GENBRIGHTPEDESTRALFLOOD),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 450,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.GENBRIGHTPEDESTRALFLOOD)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("GENBRIGHTPEDESTRALFLOOD", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("GENBRIGHTPEDESTRALFLOOD", true)
        end,
    },
    INSTRBRIGHTOUTBDDU = {
        t = messages.translation['INSTRBRIGHTOUTBDDU'],
        value = tostring(settings.appSettings.INSTRBRIGHTOUTBDDU),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 480,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.INSTRBRIGHTOUTBDDU)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTOUTBDDU", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTOUTBDDU", true)
        end,
    },
    INSTRBRIGHTINBDDU = {
        t = messages.translation['INSTRBRIGHTINBDDU'],
        value = tostring(settings.appSettings.INSTRBRIGHTINBDDU),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 510,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.INSTRBRIGHTINBDDU)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTINBDDU", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTINBDDU", true)
        end,
    },
    INSTRBRIGHTUPPERDU = {
        t = messages.translation['INSTRBRIGHTUPPERDU'],
        value = tostring(settings.appSettings.INSTRBRIGHTUPPERDU),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 540,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.INSTRBRIGHTUPPERDU)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTUPPERDU", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTUPPERDU", true)
        end,
    },
    INSTRBRIGHTLOWDU = {
        t = messages.translation['INSTRBRIGHTLOWDU'],
        value = tostring(settings.appSettings.INSTRBRIGHTLOWDU),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 570,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.INSTRBRIGHTLOWDU)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTLOWDU", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTLOWDU", true)
        end,
    },
    INSTRBRIGHTINBDDUS = {
        t = messages.translation['INSTRBRIGHTINBDDUS'],
        value = tostring(settings.appSettings.INSTRBRIGHTINBDDUS),
        x = x_col2,
        x2 = x_col2 + 65,
        y = hSize - 600,
        w = 20,
        h = 20,
        linePadding = 6,
        isFocused = true,
        val_min = 0,
        val_max = 1,
        val_incr = 0.1,
        draw_ = function()
            windows.slider(wdef.INSTRBRIGHTINBDDUS)
        end,
        onMouseDown_M_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTINBDDUS", false)
        end,
        onMouseDown_P_ = function()
            setFocusOnInput(nil)
            decrIncrElement("INSTRBRIGHTINBDDUS", true)
        end,
    },
    IGNOREALLBRIGHTHNESSSETTINGS = {
        t = messages.translation['IGNOREALLBRIGHTHNESSSETTINGS'],
        value = false,
        x = x_col2 ,
        y = hSize - 625,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.IGNOREALLBRIGHTHNESSSETTINGS = not_(settings.appSettings.IGNOREALLBRIGHTHNESSSETTINGS)
            settings.writeSettings(settings.appSettings)
            wdef.IGNOREALLBRIGHTHNESSSETTINGS.value = toboolean(settings.appSettings.IGNOREALLBRIGHTHNESSSETTINGS)
        end,      
            draw_ = function()
            windows.drawCheckBox(wdef.IGNOREALLBRIGHTHNESSSETTINGS)
        end
    },
    misc = {
        t = messages.translation['MISC'],
        x = x_col2,
        y = hSize - 650,
        draw_ = function()
            windows.drawText(wdef.misc)
        end
    },
    SHOWBETAUPDATES = {
        t = messages.translation['SHOWBETAUPDATES'],
        value = toboolean(settings.appSettings.SHOWBETAUPDATES),
        x = x_col2 + 20,
        y = hSize - 670,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.SHOWBETAUPDATES = not_(settings.appSettings.SHOWBETAUPDATES)
            settings.writeSettings(settings.appSettings)
            wdef.SHOWBETAUPDATES.value = toboolean(settings.appSettings.SHOWBETAUPDATES)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.SHOWBETAUPDATES)
        end
    },
    debugMode = {
        t = messages.translation['DEBUGMODE'],
        value = (sasl.getLogLevel() == LOG_DEBUG),
        x = x_col2 + 20,
        y = hSize - 690,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            wdef.debugMode.value = not wdef.debugMode.value
            if wdef.debugMode.value then
                sasl.setLogLevel(LOG_DEBUG)
                sasl.logDebug("log mode set to DEBUG")
                if yal.xluaLoggingEnabled then
                    set(yal.xluaLoggingEnabled, 1)
                end
            else
                sasl.setLogLevel(LOG_INFO)
                sasl.logInfo("log mode set to INFO")
                if yal.xluaLoggingEnabled then
                    set(yal.xluaLoggingEnabled, 0)
                end
            end
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.debugMode)
        end
    },
}

local function addInteractiveAreas(element)
    if not element then
        return
    end
    local areas = getElementInteractive(element)
    if areas[1] and areas[2] then
        table.insert(components, interactive {
            position = areas[1],
            onMouseDown = areas[2]
        })
    end
    if areas[3] and areas[4] then
        table.insert(components, interactive {
            position = areas[3],
            onMouseDown = areas[4]
        })
    end
end

local function rebuildComponents()
    components = {}
    for _, handler in ipairs(buildGeneralInteractives()) do
        table.insert(components, handler)
    end
    for key, element in pairs(wdef) do
        if not skipDraw[key] and (element.onMouseDown_ or element.onMouseDown_M_ or element.onMouseDown_P_) then
            addInteractiveAreas(element)
        end
    end
end

local function applyLayout()
    updateLayoutConstants()
    local contentTop = generalHeaderY
    local contentBottom = contentTop

    if wdef.mainWindow then
        wdef.mainWindow.w = wSize
        wdef.mainWindow.h = hSize
    end
    if wdef.closeButton then
        wdef.closeButton.x = wSize - def.closeXWidth
        wdef.closeButton.y = hSize - def.closeXHeight
    end

    if wdef.TODPAUSEQUITTIME then
        wdef.TODPAUSEQUITTIME.y = postGeneralStartY
    end
    if wdef.SAVETIME then
        wdef.SAVETIME.y = postGeneralStartY - postGeneralGap
    end
    if wdef.SAVENUMBER then
        wdef.SAVENUMBER.y = postGeneralStartY - (2 * postGeneralGap)
    end
    if wdef.LOWERAIRSPACEALT then
        wdef.LOWERAIRSPACEALT.y = lowerBlockStartY
    end
    if wdef.PACKSRESTOREALT then
        wdef.PACKSRESTOREALT.y = lowerBlockStartY - lowerBlockGap
    end
    if wdef.BANKANGLEMAX then
        wdef.BANKANGLEMAX.y = lowerBlockStartY - (2 * lowerBlockGap)
    end
    if wdef.TRANSPONDERCODE then
        wdef.TRANSPONDERCODE.y = lowerBlockStartY - (3 * lowerBlockGap)
    end
    if wdef.GEARDOWNFLAPS then
        wdef.GEARDOWNFLAPS.y = lowerBlockStartY - (4 * lowerBlockGap)
    end

    if wdef.views then
        wdef.views.x = x_col2
        wdef.views.y = viewHeaderY
    end
    for idx, key in ipairs(viewControls) do
        local elem = wdef[key]
        if elem then
            elem.x = x_col2 + 10
            elem.y = viewStartY - ((idx - 1) * viewStep)
        end
    end

    if wdef.brightness then
        wdef.brightness.x = x_col2
        wdef.brightness.y = brightnessHeaderY
    end
    for idx, key in ipairs(brightnessControls) do
        local elem = wdef[key]
        if elem then
            elem.x = x_col2
            elem.x2 = x_col2 + 65
            elem.y = brightnessStartY - ((idx - 1) * brightnessStep)
        end
    end
    if wdef.IGNOREALLBRIGHTHNESSSETTINGS then
        wdef.IGNOREALLBRIGHTHNESSSETTINGS.x = x_col2
        wdef.IGNOREALLBRIGHTHNESSSETTINGS.y = ignoreBrightY
    end

    if wdef.misc then
        wdef.misc.x = x_col2
        wdef.misc.y = miscHeaderY
    end
    if wdef.SHOWBETAUPDATES then
        wdef.SHOWBETAUPDATES.x = x_col2 + 20
        wdef.SHOWBETAUPDATES.y = showBetaY
    end
    if wdef.debugMode then
        wdef.debugMode.x = x_col2 + 20
        wdef.debugMode.y = debugY
    end

    -- content bounds (before offset)
    for key, element in pairs(wdef) do
        if key ~= "mainWindow" and key ~= "closeButton" and element.y then
            local bottom = element.y
            if element.h then bottom = element.y - element.h end
            contentBottom = math.min(contentBottom, bottom)
        end
    end

    local contentHeight = contentTop - contentBottom
    local availableHeight = hSize - def.bannerHeight - 16
    scrollMax = math.max(0, contentHeight - availableHeight)
    if scrollOffset > scrollMax then scrollOffset = scrollMax end
    if scrollOffset < 0 then scrollOffset = 0 end

    generalRowStartYAdj = generalRowStartY - scrollOffset
    generalHeaderYAdj = generalHeaderY - scrollOffset

    for key, element in pairs(wdef) do
        if key ~= "mainWindow" and key ~= "closeButton" and element.y then
            element.y = element.y - scrollOffset
        end
    end

    rebuildComponents()
end


-- initial layout
applyLayout()

function not_(value)
    if value == 0 then
        return 1
    else
        return 0
    end
end

function update()
end

function draw()
    applyLayout()
    windows.drawWindowTemplate(wdef.mainWindow)

    for k, v in pairs(wdef) do
        if skipDraw[k] then
            -- skip, rendered dynamically
        elseif wdef[k].draw_ ~= nil then
            wdef[k].draw_()
        end
    end

    drawGeneralDynamic()

    drawAll(components)

    if scrollMax > 0 then
        local trackX = wSize - 10
        local trackW = 6
        local trackHeight = hSize - def.bannerHeight - 16
        local trackTop = hSize - def.bannerHeight - 8
        local travel = trackHeight
        local thumbHeight = math.max(20, trackHeight * (trackHeight / (trackHeight + scrollMax)))
        travel = trackHeight - thumbHeight
        local rel = (scrollMax == 0) and 0 or (scrollOffset / scrollMax)
        local thumbY = trackTop - (rel * travel) - thumbHeight
        sasl.gl.drawRectangle(trackX, trackTop - trackHeight, trackW, trackHeight, {0.3, 0.3, 0.3, 0.4})
        sasl.gl.drawRectangle(trackX, thumbY, trackW, thumbHeight, {0.8, 0.8, 0.8, 0.9})
    end
end

function onMouseWheel(_, _, _, clicks)
    if clicks == nil or type(clicks) ~= "number" or scrollMax == 0 then return false end
    scrollOffset = scrollOffset + (-clicks * (def.lineHeight * 2))
    if scrollOffset < 0 then scrollOffset = 0 end
    if scrollOffset > scrollMax then scrollOffset = scrollMax end
    return true
end

function onMouseDown(x, y, button)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    if button == MB_LEFT and scrollMax > 0 then
        local trackX = wSize - 10
        local trackW = 6
        local trackHeight = hSize - def.bannerHeight - 16
        local trackTop = hSize - def.bannerHeight - 8
        local trackBottom = trackTop - trackHeight
        if x >= trackX and x <= (trackX + trackW) and y >= trackBottom and y <= trackTop then
            local thumbHeight = math.max(20, trackHeight * (trackHeight / (trackHeight + scrollMax)))
            local travel = trackHeight - thumbHeight
            local rel = (travel == 0) and 0 or (trackTop - y - (thumbHeight / 2)) / travel
            rel = math.max(0, math.min(1, rel))
            scrollOffset = rel * scrollMax
            scrollDrag = { startY = y, startOffset = scrollOffset, travel = travel }
            return true
        end
    end
    return false
end

function onMouseUp(_, _, button)
    if button == MB_LEFT and scrollDrag then
        scrollDrag = nil
        return true
    end
    return false
end

function onMouseMove(_, y)
    if type(y) ~= "number" then return false end
    if scrollDrag then
        local dy = scrollDrag.startY - y
        local rel = (scrollDrag.travel == 0) and 0 or (dy / scrollDrag.travel)
        scrollOffset = scrollDrag.startOffset + (rel * scrollMax)
        if scrollOffset < 0 then scrollOffset = 0 end
        if scrollOffset > scrollMax then scrollOffset = scrollMax end
        return true
    end
    return false
end
