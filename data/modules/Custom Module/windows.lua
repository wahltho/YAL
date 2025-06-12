local P = {}
windows = P -- package name

local def = require("definitions")

local function htmlColorToSasl(strColor)
    if string.sub(strColor, 1, 1) == '#' then
        local R = tonumber(string.sub(strColor, 2, 3), 16) / 255
        local G = tonumber(string.sub(strColor, 4, 5), 16) / 255
        local B = tonumber(string.sub(strColor, 6, 7), 16) / 255
        local A = tonumber(string.sub(strColor, 8, 9), 16)
        if A == nil then
            A = 1
        else
            A = A / 255
        end
        return { R, G, B, A }
    end
    return { 0, 0, 0, 1 }
end

function P.drawButton(button, active)
    local t = button.t
    if t == nil then
        t = ""
    end
    local bg = button.bg
    if bg == nil then
        bg = def.buttonColor
    end
    local linePadding = button.linePadding
    if linePadding == nil then
        linePadding = def.linePaddingBottom
    end

    local dcolor = button.dcolor
    if dcolor == nil then
        dcolor = def.disableButtonColor
    end

    local acolor = button.acolor
    if acolor == nil then
        acolor = def.activeButtonColor
    end

    local font = button.font
    if font == nil then
        font = def.wFont
    end

    local color = dcolor
    if active then
        color = acolor
    end

    local border = button.withBorder
    if border == nil then
        border = true
    end

    drawRectangle(button.x, button.y, button.w, button.h, bg)
    if border then
        sasl.gl.drawFrame(button.x, button.y, button.w, button.h, color)
    end
    sasl.gl.drawTextI(font, button.x + button.w / 2, button.y + linePadding, t, TEXT_ALIGN_CENTER, color)
end

function P.slider(button)
    local t = button.t
    if t == nil then
        t = ""
    end
    local bg = button.bg
    if bg == nil then
        bg = def.buttonColor
    end
    local linePadding = button.linePadding
    if linePadding == nil then
        linePadding = def.linePaddingBottom
    end

    local dcolor = button.dcolor
    if dcolor == nil then
        dcolor = def.disableButtonColor
    end

    local acolor = button.acolor
    if acolor == nil then
        acolor = def.activeButtonColor
    end

    local font = button.font
    if font == nil then
        font = def.wFont
    end


    local border = button.withBorder
    if border == nil then
        border = true
    end

    drawRectangle(button.x, button.y, button.w, button.h, bg)
    if border then
        sasl.gl.drawFrame(button.x, button.y, button.w, button.h, acolor)
    end
    sasl.gl.drawTextI(font, button.x + button.w / 2, button.y + linePadding, '-', TEXT_ALIGN_CENTER, acolor)

    sasl.gl.drawTextI(font, button.x + button.w + 10, button.y + linePadding, button.value, TEXT_ALIGN_LEFT, acolor)

    drawRectangle(button.x2, button.y, button.w, button.h, bg)
    if border then
        sasl.gl.drawFrame(button.x2, button.y, button.w, button.h, acolor)
    end
    sasl.gl.drawTextI(font, button.x2 + button.w / 2, button.y + linePadding, '+', TEXT_ALIGN_CENTER, acolor)

    sasl.gl.drawTextI(font, button.x2 + button.w + 10, button.y + linePadding, t, TEXT_ALIGN_LEFT, acolor)
end

function P.drawBlockTexts(sBlock, sTable)
    local bg = sBlock.bg
    if bg == nil then
        bg = def.buttonColor
    end
    local dcolor = sBlock.dcolor
    if dcolor == nil then
        dcolor = def.disableButtonColor
    end

    local acolor = sBlock.acolor
    if acolor == nil then
        acolor = def.textColor
    end

    local font = sBlock.font
    if font == nil then
        font = def.wFont
    end

    local lh = sBlock.lh
    if lh == nil then
        lh = def.lineHeight
    end

    local y = sBlock.y
    for i = 1, #sTable, 1 do
        if string.sub(sTable[i], 1, 2) == "##" then
            acolor = htmlColorToSasl(string.sub(sTable[i], 2))
        else
            sasl.gl.drawTextI(font, sBlock.x, y, sTable[i], TEXT_ALIGN_LEFT, acolor)
            y = y - lh
        end
    end
end

function P.drawText(textValue)
    local bg = textValue.bg
    if bg == nil then
        bg = def.buttonColor
    end
    local dcolor = textValue.dcolor
    if dcolor == nil then
        dcolor = def.disableButtonColor
    end

    local acolor = textValue.acolor
    if acolor == nil then
        acolor = def.textColor
    end

    local font = textValue.font
    if font == nil then
        font = def.wFont
    end

    local text_w, text_h = sasl.gl.measureTextI(font, textValue.t)


    sasl.gl.drawTextI(font, textValue.x, textValue.y, textValue.t, TEXT_ALIGN_LEFT, acolor)
end

function P.drawCheckBox(checkBox)
    local bg = checkBox.bg
    if bg == nil then
        bg = def.buttonColor
    end
    local dcolor = checkBox.dcolor
    if dcolor == nil then
        dcolor = def.disableButtonColor
    end

    local acolor = checkBox.acolor
    if acolor == nil then
        acolor = def.textColor
    end

    local font = checkBox.font
    if font == nil then
        font = def.wFont
    end



    local text_w, text_h = sasl.gl.measureTextI(font, checkBox.t)
    local org_x_cb = checkBox.x
    local org_y_cb = checkBox.y
    local h_cb = checkBox.h --text_h
    local w_cb = checkBox.w -- h_cb

    sasl.gl.drawFrame(org_x_cb, org_y_cb, w_cb, h_cb, acolor)
    if toboolean(checkBox.value) then
        sasl.gl.drawLine(org_x_cb, org_y_cb, org_x_cb + w_cb, org_y_cb + h_cb, acolor)
        sasl.gl.drawLine(org_x_cb, org_y_cb + h_cb, org_x_cb + w_cb, org_y_cb, acolor)
    end

    sasl.gl.drawTextI(font, checkBox.x + w_cb + 10, checkBox.y, checkBox.t, TEXT_ALIGN_LEFT, acolor)
end

function P.inputTextBox(inputText)
    local bg = inputText.bg
    if bg == nil then
        bg = def.inputBackgroundColor
    end
    local dcolor = inputText.dcolor
    if dcolor == nil then
        dcolor = def.disableInputText
    end

    local acolor = inputText.acolor
    if acolor == nil then
        acolor = def.activeInputText
    end

    local font = inputText.font
    if font == nil then
        font = def.wFont
    end

    local lh = inputText.lh
    if lh == nil then
        lh = def.lineHeight
    end

    local text_h = inputText.h
    local text_w = inputText.w
    local org_x_cb = inputText.x
    local org_y_cb = inputText.y


    local color = dcolor

    sasl.gl.drawRectangle(org_x_cb, org_y_cb, text_w, text_h, bg)
    if inputText.isFocused then
        sasl.gl.drawFrame(org_x_cb, org_y_cb, text_w, text_h, def.activeInputText)
        color = acolor
    end
    sasl.gl.drawTextI(font, inputText.x + 5, inputText.y + def.linePaddingBottom, inputText.value,
        TEXT_ALIGN_LEFT, acolor)
    sasl.gl.drawTextI(font, inputText.x + text_w + 10, inputText.y + def.linePaddingBottom, inputText.t,
        TEXT_ALIGN_LEFT, acolor)
end

function P.drawWindowTemplate(windowDefinition)
    local bg = windowDefinition.bg
    if bg == nil then
        bg = def.backgroundColor
    end

    local bannerbg = windowDefinition.bannerbg
    if bannerbg == nil then
        bannerbg = def.bannerBackgroundColor
    end

    local bcolor = windowDefinition.bannerTextColor
    if bcolor == nil then
        bcolor = def.bannerTextColor
    end

    local bannerheight = windowDefinition.bannerheight
    if bannerheight == nil then
        bannerheight = def.bannerHeight
    end

    local closewidth = windowDefinition.closewidth
    if closewidth == nil then
        closewidth = def.closeXWidth
    end

    local font = windowDefinition.font
    if font == nil then
        font = def.wFont
    end

    local fontSize = windowDefinition.fontSize
    if fontSize == nil then
        fontSize = def.wFontSize
    end

    local linePadding = windowDefinition.linePadding
    if linePadding == nil then
        linePadding = def.linePaddingBottom
    end

    drawRectangle(0, 0, windowDefinition.w, windowDefinition.h, bg)
    drawRectangle(0, windowDefinition.h - bannerheight, windowDefinition.w - closewidth, windowDefinition.w, bannerbg)

    sasl.gl.setFontSize(font, fontSize)
    sasl.gl.drawTextI(font, windowDefinition.w / 2, windowDefinition.h - bannerheight + linePadding,
        windowDefinition.wtitle, TEXT_ALIGN_CENTER, bcolor)
end

return windows