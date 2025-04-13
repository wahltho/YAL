require("definitions")
require("windows")
require("settings")
require("messages")


defineProperty(size, { 200, 200 })

size = get(size)

wSize = size[1]
hSize = size[2]

local wTitle = string.format("%s - " .. messages.translation['SETUP'], definitions.APPNAMEPREFIXLONG.. " v"..definitions.VERSION)
local x_col1 = 10
local x_col2 = x_col1 + wSize / 2 + 90
local cb_w = 10 -- definitions.checkBoxWidth
local cb_h = 10 -- definitions.checkBoxHeight

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

wdef = {
    mainWindow = {
        w = wSize,
        h = hSize,
        wtitle = wTitle,
    },
    closeButton = {
        t = "x",
        x = wSize - definitions.closeXWidth,
        y = hSize - definitions.closeXHeight,
        w = definitions.closeXWidth,
        h = definitions.closeXHeight,
        withBorder = false,
        draw_ = function()
            windows.drawButton(wdef.closeButton, true)
        end,
        onMouseDown_ = function()
            register_handler(nil)
            setup_datapanel:setIsVisible(false)
        end
    },
    general = {
        t = messages.translation['GENERAL'],
        x = x_col1,
        y = hSize - 60,
        draw_ = function()
            windows.drawText(wdef.general)
        end
    },
    USEGROUNDPOWER = {
        t = messages.translation['USEGROUNDPOWER'],
        value = toboolean(settings.appSettings.USEGROUNDPOWER),
        x = x_col1 + 60,
        y = hSize - 80,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.USEGROUNDPOWER = not_(settings.appSettings.USEGROUNDPOWER)
            settings.writeSettings(settings.appSettings)
            wdef.USEGROUNDPOWER.value = toboolean(settings.appSettings.USEGROUNDPOWER)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.USEGROUNDPOWER)
        end

    },
    VOICEREADBACK = {
        t = messages.translation['VOICEREADBACK'],
        value = toboolean(settings.appSettings.VOICEREADBACK),
        x = x_col1 + 60,
        y = hSize - 100,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.VOICEREADBACK = not_(settings.appSettings.VOICEREADBACK)
            settings.writeSettings(settings.appSettings)
            wdef.VOICEREADBACK.value = toboolean(settings.appSettings.VOICEREADBACK)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.VOICEREADBACK)
        end

    },
    AUTOFUNCTIONS = {
        t = messages.translation['AUTOFUNCTIONS'],
        value = toboolean(settings.appSettings.AUTOFUNCTIONS),
        x = x_col1 + 60,
        y = hSize - 120,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.AUTOFUNCTIONS = not_(settings.appSettings.AUTOFUNCTIONS)
            settings.writeSettings(settings.appSettings)
            wdef.AUTOFUNCTIONS.value = toboolean(settings.appSettings.AUTOFUNCTIONS)
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.AUTOFUNCTIONS)
        end
    },
    VOICEADVICEONLY = {
        t = messages.translation['VOICEADVICEONLY'],
        value = toboolean(settings.appSettings.VOICEADVICEONLY),
        x = x_col1 + 60,
        y = hSize - 140,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            settings.appSettings.VOICEADVICEONLY = not_(settings.appSettings.VOICEADVICEONLY)
            settings.writeSettings(settings.appSettings)
            wdef.VOICEADVICEONLY.value = toboolean(settings.appSettings.VOICEADVICEONLY)
        end,       
            draw_ = function()
            windows.drawCheckBox(wdef.VOICEADVICEONLY)
        end
    },
    TODPAUSEQUITTIME = {
        t = messages.translation['TODPAUSEQUITTIME'],
        value = tostring(settings.appSettings.TODPAUSEQUITTIME),
        x = x_col1 +20,
        y = hSize - 170,
        w = 50,
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        y = hSize - 200,
        w = 50,
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        y = hSize - 230,
        w = 50,
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        y = hSize - 260,
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
        y = hSize - 280,
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
        y = hSize - 300,
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
        y = hSize - 320,
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
        y = hSize - 340,
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
        y = hSize - 360,
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
        y = hSize - 380,
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
    customize = {
        t = messages.translation['CUSTOMIZE'],
        x = x_col1 ,
        y = hSize - 420,
        draw_ = function()
            windows.drawText(wdef.customize)
        end
    },
    SPEEDRESTR250 = {
        t = messages.translation['SPEEDRESTR250'],
        value = toboolean(settings.appSettings.SPEEDRESTR250),
        x = x_col1 +60,
        y = hSize - 440,
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
        y = hSize - 460,
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
    LOWERAIRSPACEALT = {
        t = messages.translation['LOWERAIRSPACEALT'],
        value = tostring(settings.appSettings.LOWERAIRSPACEALT),
        x = x_col1 + 20,
        y = hSize - 490,
        w = 50,
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
    BANKANGLEMAX = {
        t = messages.translation['BANKANGLEMAX'],
        value = tostring(settings.appSettings.BANKANGLEMAX),
        x = x_col1,
        x2 = x_col1 + 50,
        y = hSize - 530,
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
        y = hSize - 560,
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
        y = hSize - 590,
        w = 50,
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 55, -- '7'
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
        y = hSize - 620,
        w = 50,
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 55, -- '7'
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
        y = hSize - 650,
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
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        h = definitions.lineHeight * 1.5,
        isFocused = false,
        ascii_min = 48, -- '0'
        ascii_max = 57, -- '9'
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
        y = hSize - 630,
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
        y = hSize - 660,
        draw_ = function()
            windows.drawText(wdef.misc)
        end
    },
    debugMode = {
        t = messages.translation['DEBUGMODE'],
        value = false,
        x = x_col2 + 20,
        y = hSize - 680,
        w = cb_w,
        h = cb_h,
        onMouseDown_ = function()
            setFocusOnInput(nil)
            wdef.debugMode.value = not wdef.debugMode.value
            if wdef.debugMode.value then
                sasl.setLogLevel(LOG_DEBUG)
                sasl.logDebug("log mode set to DEBUG")
            else
                sasl.setLogLevel(LOG_INFO)
                sasl.logInfo("log mode set to INFO")
            end
        end,
        draw_ = function()
            windows.drawCheckBox(wdef.debugMode)
        end
    },
}

components = {
    interactive {
        position = getElementInteractive(wdef.debugMode)[1],
        onMouseDown = getElementInteractive(wdef.debugMode)[2]
    }, interactive {
    position = getElementInteractive(wdef.closeButton)[1],
    onMouseDown = getElementInteractive(wdef.closeButton)[2]
    -- cursor = definitions.cursor,
}, interactive {
    position = getElementInteractive(wdef.VOICEREADBACK)[1],
    onMouseDown = getElementInteractive(wdef.VOICEREADBACK)[2]
    -- cursor = definitions.cursor,
}, interactive {
    position = getElementInteractive(wdef.USEGROUNDPOWER)[1],
    onMouseDown = getElementInteractive(wdef.USEGROUNDPOWER)[2]
    -- cursor = definitions.cursor,
}, interactive {
    position = getElementInteractive(wdef.AUTOCENTERTANKHANDLING)[1],
    onMouseDown = getElementInteractive(wdef.AUTOCENTERTANKHANDLING)[2]
    -- cursor = definitions.cursor,
}, interactive {
    position = getElementInteractive(wdef.IGNOREALLBRIGHTHNESSSETTINGS)[1],
    onMouseDown = getElementInteractive(wdef.IGNOREALLBRIGHTHNESSSETTINGS)[2]
    -- cursor = definitions.cursor,
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.AUTOFUNCTIONS)[1],
    onMouseDown = getElementInteractive(wdef.AUTOFUNCTIONS)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VOICEADVICEONLY)[1],
    onMouseDown = getElementInteractive(wdef.VOICEADVICEONLY)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.AUTOFLAPS)[1],
    onMouseDown = getElementInteractive(wdef.AUTOFLAPS)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.HIDEEFBS)[1],
    onMouseDown = getElementInteractive(wdef.HIDEEFBS)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.WAKEOVERRIDE)[1],
    onMouseDown = getElementInteractive(wdef.WAKEOVERRIDE)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.AUTOANTIICE)[1],
    onMouseDown = getElementInteractive(wdef.AUTOANTIICE)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.AUTOWIPER)[1],
    onMouseDown = getElementInteractive(wdef.AUTOWIPER)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.AUTOBARO)[1],
    onMouseDown = getElementInteractive(wdef.AUTOBARO)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VIEWCHANGES)[1],
    onMouseDown = getElementInteractive(wdef.VIEWCHANGES)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.SPEEDRESTR250)[1],
    onMouseDown = getElementInteractive(wdef.SPEEDRESTR250)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VREF30)[1],
    onMouseDown = getElementInteractive(wdef.VREF30)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.LOWERDU)[1],
    onMouseDown = getElementInteractive(wdef.LOWERDU)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.BANKANGLEMAX)[1],
    onMouseDown = getElementInteractive(wdef.BANKANGLEMAX)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.BANKANGLEMAX)[3],
    onMouseDown = getElementInteractive(wdef.BANKANGLEMAX)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.TODPAUSEQUITTIME)[1],
    onMouseDown = getElementInteractive(wdef.TODPAUSEQUITTIME)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.SAVETIME)[1],
    onMouseDown = getElementInteractive(wdef.SAVETIME)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.SAVENUMBER)[1],
    onMouseDown = getElementInteractive(wdef.SAVENUMBER)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.LOWERAIRSPACEALT)[1],
    onMouseDown = getElementInteractive(wdef.LOWERAIRSPACEALT)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.TRANSPONDERCODE)[1],
    onMouseDown = getElementInteractive(wdef.TRANSPONDERCODE)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.GEARDOWNFLAPS)[1],
    onMouseDown = getElementInteractive(wdef.GEARDOWNFLAPS)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VIEWMAINPANEL)[1],
    onMouseDown = getElementInteractive(wdef.VIEWMAINPANEL)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VIEWPEDESTAL)[1],
    onMouseDown = getElementInteractive(wdef.VIEWPEDESTAL)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VIEWOVERHEADPANEL)[1],
    onMouseDown = getElementInteractive(wdef.VIEWOVERHEADPANEL)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VIEWFMS)[1],
    onMouseDown = getElementInteractive(wdef.VIEWFMS)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VIEWTHROTTLE)[1],
    onMouseDown = getElementInteractive(wdef.VIEWTHROTTLE)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.VIEWUPPEROVERHEADPANEL)[1],
    onMouseDown = getElementInteractive(wdef.VIEWUPPEROVERHEADPANEL)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.BRIGHTMAINPANEL)[1],
    onMouseDown = getElementInteractive(wdef.BRIGHTMAINPANEL)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.BRIGHTMAINPANEL)[3],
    onMouseDown = getElementInteractive(wdef.BRIGHTMAINPANEL)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.BRIGHTOVERHEAD)[1],
    onMouseDown = getElementInteractive(wdef.BRIGHTOVERHEAD)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.BRIGHTOVERHEAD)[3],
    onMouseDown = getElementInteractive(wdef.BRIGHTOVERHEAD)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.BRIGHTPEDESTRAL)[1],
    onMouseDown = getElementInteractive(wdef.BRIGHTPEDESTRAL)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.BRIGHTPEDESTRAL)[3],
    onMouseDown = getElementInteractive(wdef.BRIGHTPEDESTRAL)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.GENBRIGHTBACKGROUND)[1],
    onMouseDown = getElementInteractive(wdef.GENBRIGHTBACKGROUND)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.GENBRIGHTBACKGROUND)[3],
    onMouseDown = getElementInteractive(wdef.GENBRIGHTBACKGROUND)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.GENBRIGHTAFDSFLOOD)[1],
    onMouseDown = getElementInteractive(wdef.GENBRIGHTAFDSFLOOD)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.GENBRIGHTAFDSFLOOD)[3],
    onMouseDown = getElementInteractive(wdef.GENBRIGHTAFDSFLOOD)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.GENBRIGHTPEDESTRALFLOOD)[1],
    onMouseDown = getElementInteractive(wdef.GENBRIGHTPEDESTRALFLOOD)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.GENBRIGHTPEDESTRALFLOOD)[3],
    onMouseDown = getElementInteractive(wdef.GENBRIGHTPEDESTRALFLOOD)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTOUTBDDU)[1],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTOUTBDDU)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTOUTBDDU)[3],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTOUTBDDU)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTINBDDU)[1],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTINBDDU)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTINBDDU)[3],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTINBDDU)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTUPPERDU)[1],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTUPPERDU)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTUPPERDU)[3],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTUPPERDU)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTLOWDU)[1],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTLOWDU)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTLOWDU)[3],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTLOWDU)[4]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTINBDDUS)[1],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTINBDDUS)[2]
}, interactive {
    --cursor = definitions.cursor,
    position = getElementInteractive(wdef.INSTRBRIGHTINBDDUS)[3],
    onMouseDown = getElementInteractive(wdef.INSTRBRIGHTINBDDUS)[4]
}
}




function not_(value)
    if value == 0 then
        return 1
    else
        return 0
    end
end

function update()
    -- If any value changes that affects either drawing or perhaps one of the interactive functions, you must
    -- get and evaluate it each flight loop in order to remain current with the state of the simulation.
    -- There are lots of ways to write this sort of thing.  The important thing is to write it in a way that
    -- you can easily understand later.  (Don't forget comments)
end

function draw()
    windows.drawWindowTemplate(wdef.mainWindow)

    for k, v in pairs(wdef) do
        if wdef[k].draw_ ~= nil then
            wdef[k].draw_()
        end
    end



    drawAll(components) -- This line is not always necessary for drawing, but if you want to see your click zones, in X-Plane
    -- include it at the end of your draw function	
end
