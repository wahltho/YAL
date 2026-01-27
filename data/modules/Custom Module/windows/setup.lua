-- Setup window implemented as a clone of the debug overlay component.
local M = {}

local defaultW = 750
local defaultH = 700
local lineHeight = 16
local headerH = 22
local controlAreaH = 0 -- no control rows like debug

local def = require("definitions")
local settings = require("settings")
local messages = require("messages")
local helpers = require("helpers")
local showBetaUpdates = toboolean(settings.appSettings.SHOWBETAUPDATES)
local updateAvailable, newVersion = helpers.checkForUpdate(showBetaUpdates)
local stableAvailable, stableVersion = helpers.checkForUpdate(false)
local wTitle = string.format("%s v%s", def.APPNAMEPREFIXLONG, def.VERSION)
if updateAvailable then
    wTitle = wTitle .. "   " .. (messages.translation['UPDATEAVAILABLE'] or "Update") .. " v" .. (newVersion or "")
end
local isBeta = tostring(def.VERSION or ""):lower():find("b") or tostring(def.VERSION or ""):lower():find("beta")
if isBeta and stableVersion and stableVersion ~= "" then
    wTitle = wTitle .. "  •  Last Stable v" .. stableVersion
end

local function getSafeFont()
    if def and def.wFont then
        return def.wFont
    end
    return sasl.gl.loadFont("DejaVuSansMono.ttf")
end

-- Build items list (flattened) ------------------------------------------------
local items = {}
local function addCheckbox(labelKey, key)
    items[#items + 1] = {type = "checkbox", label = messages.translation[labelKey] or labelKey, key = key}
end
local function addNumber(labelKey, key, minLen, maxLen)
    items[#items + 1] = {
        type = "number",
        label = messages.translation[labelKey] or labelKey,
        key = key,
        minLen = minLen or 1,
        maxLen = maxLen or 5
    }
end
local function addText(labelKey, key, minLen, maxLen)
    items[#items + 1] = {
        type = "text",
        label = messages.translation[labelKey] or labelKey,
        key = key,
        minLen = minLen or 0,
        maxLen = maxLen or 16
    }
end
local function addSlider(labelKey, key, minVal, maxVal, step)
    items[#items + 1] = {type = "slider", label = messages.translation[labelKey] or labelKey, key = key, minVal = minVal, maxVal = maxVal, step = step}
end

-- Left column (all settings up to Gear Down Flaps)
addCheckbox('USEGROUNDPOWER','USEGROUNDPOWER')
addCheckbox('VOICEREADBACK','VOICEREADBACK')
addCheckbox('AUTOFUNCTIONS','AUTOFUNCTIONS')
addCheckbox('FMCAUTOMATION','FMCAUTOMATION')
addCheckbox('VOICEADVICEONLY','VOICEADVICEONLY')
addCheckbox('WAKEOVERRIDE','WAKEOVERRIDE')
addCheckbox('RUNWAYFRICTIONCLAMP','RUNWAYFRICTIONCLAMP')
addCheckbox('AUTOANTIICE','AUTOANTIICE')
addCheckbox('AUTOWIPER','AUTOWIPER')
addCheckbox('AUTOCENTERTANKHANDLING','AUTOCENTERTANKHANDLING')
addCheckbox('AUTOFLAPS','AUTOFLAPS')
addCheckbox('AUTOBARO','AUTOBARO')
addCheckbox('VIEWCHANGES','VIEWCHANGES')
addCheckbox('AUTOTAXIGUIDANCE','AUTOTAXIGUIDANCE')
addCheckbox('AUTOCHOCKSPB','AUTOCHOCKSPB')
addCheckbox('SPEEDRESTR250','SPEEDRESTR250')
addCheckbox('VREF30','VREF30')
addCheckbox('CUSTOMAPPROACHCALC','CUSTOMAPPROACHCALC')
addCheckbox('LOWERDU','LOWERDU')
addCheckbox('HIDEEFBS','HIDEEFBS')
addNumber('HEADINGSYNCINTERVAL','HEADINGSYNCINTERVAL',1,4)
addNumber('TODPAUSEQUITTIME','TODPAUSEQUITTIME',1,5)
addNumber('SAVETIME','SAVETIME',1,5)
addNumber('SAVENUMBER','SAVENUMBER',1,5)
addNumber('LOWERAIRSPACEALT','LOWERAIRSPACEALT',1,5)
addNumber('PACKSRESTOREALT','PACKSRESTOREALT',1,5)
addSlider('BANKANGLEMAX','BANKANGLEMAX',1,4,1)
addNumber('TRANSPONDERCODE','TRANSPONDERCODE',4,4)
addNumber('GEARDOWNFLAPS','GEARDOWNFLAPS',1,2)

-- Right column (views, brightness, misc)
addNumber('VIEWMAINPANEL','VIEWMAINPANEL')
addNumber('VIEWPEDESTAL','VIEWPEDESTAL')
addNumber('VIEWOVERHEADPANEL','VIEWOVERHEADPANEL')
addNumber('VIEWFMS','VIEWFMS')
addNumber('VIEWTHROTTLE','VIEWTHROTTLE')
addNumber('VIEWUPPEROVERHEADPANEL','VIEWUPPEROVERHEADPANEL')
addSlider('BRIGHTMAINPANEL','BRIGHTMAINPANEL',0,1,0.1)
addSlider('BRIGHTOVERHEAD','BRIGHTOVERHEAD',0,1,0.1)
addSlider('BRIGHTPEDESTRAL','BRIGHTPEDESTRAL',0,1,0.1)
addSlider('GENBRIGHTBACKGROUND','GENBRIGHTBACKGROUND',0,1,0.1)
addSlider('GENBRIGHTAFDSFLOOD','GENBRIGHTAFDSFLOOD',0,1,0.1)
addSlider('GENBRIGHTPEDESTRALFLOOD','GENBRIGHTPEDESTRALFLOOD',0,1,0.1)
addSlider('INSTRBRIGHTOUTBDDU','INSTRBRIGHTOUTBDDU',0,1,0.1)
addSlider('INSTRBRIGHTINBDDU','INSTRBRIGHTINBDDU',0,1,0.1)
addSlider('INSTRBRIGHTUPPERDU','INSTRBRIGHTUPPERDU',0,1,0.1)
addSlider('INSTRBRIGHTLOWDU','INSTRBRIGHTLOWDU',0,1,0.1)
addSlider('INSTRBRIGHTINBDDUS','INSTRBRIGHTINBDDUS',0,1,0.1)
addCheckbox('IGNOREALLBRIGHTHNESSSETTINGS','IGNOREALLBRIGHTHNESSSETTINGS')
addCheckbox('BPBINTEGRATION','BPBINTEGRATION')
addCheckbox('YANSHINTEGRATION','YANSHINTEGRATION')
addCheckbox('AUTOFUELING','AUTOFUELING')
addText('HOPPIEID','HOPPIEID',0,16)
addCheckbox('SHOWBETAUPDATES','SHOWBETAUPDATES')
addCheckbox('DEBUGMODE','DEBUGMODE')

-- Helpers --------------------------------------------------------------------
local function not_(v) return (v == 0 or v == false) and 1 or 0 end

local function drawTextLine(font, x, y, text, color)
    sasl.gl.drawTextI(font, x, y, tostring(text or ""), TEXT_ALIGN_LEFT, color)
end

local function drawCheckbox(font, x, y, label, checked)
    local boxSize = 12
    sasl.gl.drawRectangle(x, y, boxSize, boxSize, {0.2,0.2,0.2,0.8})
    sasl.gl.drawFrame(x, y, boxSize, boxSize, {0.8,0.8,0.8,1})
    if checked then
        sasl.gl.drawLine(x+2, y+2, x+boxSize-2, y+boxSize-2, {0.9,0.9,0.9,1})
        sasl.gl.drawLine(x+boxSize-2, y+2, x+2, y+boxSize-2, {0.9,0.9,0.9,1})
    end
    drawTextLine(font, x + boxSize + 6, y + 2, label, {0.9,0.9,0.95,1})
end

-- Component ------------------------------------------------------------------
function M.newComponent(ctx)
    local comp = {}
    comp.name = "yal_setup_component"
    comp.components = {}
    comp.position = createProperty({0, 0, defaultW, defaultH})
    comp.size = {defaultW, defaultH}
    comp.fbo = createProperty(false)
    comp.renderTarget = -1
    comp.fpsLimit = createProperty(-1)
    comp.frames = 0
    comp.noRenderSignal = createProperty(false)
    comp.clip = createProperty(false)
    comp.clipSize = createProperty({0, 0, 0, 0})
    comp.visible = createProperty(true)
    comp._window = nil
    comp.scrollOffset = 0
    comp.scrollDrag = nil

    function comp:setWindow(win)
        self._window = win
    end

    local function getSize()
        if comp._window and comp._window.getPosition then
            local _, _, ww, hh = comp._window:getPosition()
            return ww or defaultW, hh or defaultH
        end
        local p = get(comp.position)
        return p[3] or defaultW, p[4] or defaultH
    end

    function comp:draw()
        local w, h = getSize()
        local font = getSafeFont()
        local color = {0.9, 0.9, 0.95, 1}
        local leftLabelWidth = 290 -- nudge left column number boxes to the right
        local rightLabelWidth = 190
        local numberBoxWidthLeft = 50
        local numberBoxWidthRight = 30
        local textBoxWidthLeft = 90
        local colHitW = w / 2 - 20
        local textBoxWidthRight = math.max(80, colHitW - rightLabelWidth - 12)
        local buttonH = lineHeight + 2
        local buttonW = math.max(240, colHitW - 40)
        local layout = {
            hits = {},
            close = { x = w - 80, y = h - headerH - 4, w = 80, h = headerH + 8 },
            scroll = nil,
            buttons = {}
        }

        drawRectangle(0, 0, w, h, {0, 0, 0, 0.75})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.6, 0.6, 0.6, 0.8})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 0.95})

        -- Layout: two columns, with a fixed split (leftCount items on the left)
        local leftCount = 27
        local half = leftCount
        local spacing = lineHeight + 6
        local leftX = 16
        local rightX = w/2 + 16
        local startY = h - headerH - 16

        local totalRows = math.max(half, #items - half)
        local scrollHeight = h - headerH - controlAreaH - 16
        local availableLines = math.max(1, math.floor(scrollHeight / spacing))
        local maxOffset = math.max(0, totalRows - availableLines)
        comp._lastMaxOffset = maxOffset
        if comp.scrollOffset > maxOffset then comp.scrollOffset = maxOffset end
        if comp.scrollOffset < 0 then comp.scrollOffset = 0 end

        local startRow = 1 + comp.scrollOffset
        local endRow = math.min(totalRows, startRow + availableLines - 1)

        drawTextLine(font, leftX, startY, "General / Procedures", color)
        drawTextLine(font, rightX, startY, "Views / Brightness / Misc", color)
        startY = startY - spacing

        for row = startRow, endRow do
            local yRow = startY - spacing * (row - startRow)
            local leftIdx = row
            local rightIdx = half + row
            if items[leftIdx] then
                local item = items[leftIdx]
                local x = leftX
                if item.type == "checkbox" then
                    local checked = toboolean(settings.appSettings[item.key])
                    if item.key == "DEBUGMODE" then
                        checked = sasl.getLogLevel() == LOG_DEBUG
                    end
                    drawCheckbox(font, x, yRow, item.label, checked)
                    layout.hits[#layout.hits + 1] = {
                        kind = "checkbox",
                        item = item,
                        x = x,
                        y = yRow,
                        w = colHitW,
                        h = lineHeight
                    }
                elseif item.type == "number" then
                    local isFocus = (comp._focus and comp._focus.key == item.key)
                    local val = isFocus and (comp._editText or "") or tostring(settings.appSettings[item.key] or "")
                    local labelText = (item.label or "") .. ":"
                    local boxX = x + leftLabelWidth
                    local boxW = numberBoxWidthLeft
                    drawTextLine(font, x, yRow, labelText, color)
                    drawRectangle(boxX, yRow - 2, boxW, lineHeight, {0.08,0.08,0.08,0.8})
                    drawFrame(boxX, yRow - 2, boxW, lineHeight, isFocus and {0.95,0.95,0.3,1} or {0.8,0.8,0.8,0.9})
                    drawTextLine(font, boxX + 4, yRow, val, isFocus and {0.95,0.95,0.3,1} or color)
                    layout.hits[#layout.hits + 1] = {
                        kind = "number",
                        item = item,
                        x = x,
                        y = yRow - 2,
                        w = colHitW,
                        h = lineHeight
                    }
                elseif item.type == "text" then
                    local isFocus = (comp._focus and comp._focus.key == item.key)
                    local val = isFocus and (comp._editText or "") or tostring(settings.appSettings[item.key] or "")
                    local labelText = (item.label or "") .. ":"
                    local boxX = x + leftLabelWidth
                    local boxW = textBoxWidthLeft
                    drawTextLine(font, x, yRow, labelText, color)
                    drawRectangle(boxX, yRow - 2, boxW, lineHeight, {0.08,0.08,0.08,0.8})
                    drawFrame(boxX, yRow - 2, boxW, lineHeight, isFocus and {0.95,0.95,0.3,1} or {0.8,0.8,0.8,0.9})
                    drawTextLine(font, boxX + 4, yRow, val, isFocus and {0.95,0.95,0.3,1} or color)
                    layout.hits[#layout.hits + 1] = {
                        kind = "text",
                        item = item,
                        x = x,
                        y = yRow - 2,
                        w = colHitW,
                        h = lineHeight
                    }
                elseif item.type == "slider" then
                    local val = tonumber(settings.appSettings[item.key]) or item.minVal or ""
                    local btnW = 12
                    drawRectangle(x, yRow, btnW, lineHeight, {0.2,0.2,0.2,0.8})
                    drawFrame(x, yRow, btnW, lineHeight, {0.8,0.8,0.8,1})
                    drawTextLine(font, x + 3, yRow + 2, "-", color)
                    drawTextLine(font, x + btnW + 4, yRow + 2, tostring(val), color)
                    drawRectangle(x + btnW + 36, yRow, btnW, lineHeight, {0.2,0.2,0.2,0.8})
                    drawFrame(x + btnW + 36, yRow, btnW, lineHeight, {0.8,0.8,0.8,1})
                    drawTextLine(font, x + btnW + 39, yRow + 2, "+", color)
                    drawTextLine(font, x + btnW*2 + 48, yRow + 2, item.label, color)
                    layout.hits[#layout.hits + 1] = {
                        kind = "slider_minus",
                        item = item,
                        x = x,
                        y = yRow,
                        w = btnW,
                        h = lineHeight
                    }
                    layout.hits[#layout.hits + 1] = {
                        kind = "slider_plus",
                        item = item,
                        x = x + btnW + 36,
                        y = yRow,
                        w = btnW,
                        h = lineHeight
                    }
                else
                    drawTextLine(font, x, yRow, string.format("%s: %s", item.label, tostring(settings.appSettings[item.key] or "")), color)
                end
            end
            if items[rightIdx] then
                local item = items[rightIdx]
                local x = rightX
                if item.type == "checkbox" then
                    local checked = toboolean(settings.appSettings[item.key])
                    if item.key == "DEBUGMODE" then
                        checked = sasl.getLogLevel() == LOG_DEBUG
                    end
                    drawCheckbox(font, x, yRow, item.label, checked)
                    layout.hits[#layout.hits + 1] = {
                        kind = "checkbox",
                        item = item,
                        x = x,
                        y = yRow,
                        w = colHitW,
                        h = lineHeight
                    }
                elseif item.type == "number" then
                    local isFocus = (comp._focus and comp._focus.key == item.key)
                    local val = isFocus and (comp._editText or "") or tostring(settings.appSettings[item.key] or "")
                    local labelText = (item.label or "") .. ":"
                    local boxX = x + rightLabelWidth
                    local boxW = numberBoxWidthRight
                    drawTextLine(font, x, yRow, labelText, color)
                    drawRectangle(boxX, yRow - 2, boxW, lineHeight, {0.08,0.08,0.08,0.8})
                    drawFrame(boxX, yRow - 2, boxW, lineHeight, isFocus and {0.95,0.95,0.3,1} or {0.8,0.8,0.8,0.9})
                    drawTextLine(font, boxX + 4, yRow, val, isFocus and {0.95,0.95,0.3,1} or color)
                    layout.hits[#layout.hits + 1] = {
                        kind = "number",
                        item = item,
                        x = x,
                        y = yRow - 2,
                        w = colHitW,
                        h = lineHeight
                    }
                elseif item.type == "text" then
                    local isFocus = (comp._focus and comp._focus.key == item.key)
                    local val = isFocus and (comp._editText or "") or tostring(settings.appSettings[item.key] or "")
                    local labelText = (item.label or "") .. ":"
                    local boxX = x + rightLabelWidth
                    local boxW = textBoxWidthRight
                    drawTextLine(font, x, yRow, labelText, color)
                    drawRectangle(boxX, yRow - 2, boxW, lineHeight, {0.08,0.08,0.08,0.8})
                    drawFrame(boxX, yRow - 2, boxW, lineHeight, isFocus and {0.95,0.95,0.3,1} or {0.8,0.8,0.8,0.9})
                    drawTextLine(font, boxX + 4, yRow, val, isFocus and {0.95,0.95,0.3,1} or color)
                    layout.hits[#layout.hits + 1] = {
                        kind = "text",
                        item = item,
                        x = x,
                        y = yRow - 2,
                        w = colHitW,
                        h = lineHeight
                    }
                elseif item.type == "slider" then
                    local val = tonumber(settings.appSettings[item.key]) or item.minVal or ""
                    local btnW = 12
                    drawRectangle(x, yRow, btnW, lineHeight, {0.2,0.2,0.2,0.8})
                    drawFrame(x, yRow, btnW, lineHeight, {0.8,0.8,0.8,1})
                    drawTextLine(font, x + 3, yRow + 2, "-", color)
                    drawTextLine(font, x + btnW + 4, yRow + 2, tostring(val), color)
                    drawRectangle(x + btnW + 36, yRow, btnW, lineHeight, {0.2,0.2,0.2,0.8})
                    drawFrame(x + btnW + 36, yRow, btnW, lineHeight, {0.8,0.8,0.8,1})
                    drawTextLine(font, x + btnW + 39, yRow + 2, "+", color)
                    drawTextLine(font, x + btnW*2 + 48, yRow + 2, item.label, color)
                    layout.hits[#layout.hits + 1] = {
                        kind = "slider_minus",
                        item = item,
                        x = x,
                        y = yRow,
                        w = btnW,
                        h = lineHeight
                    }
                    layout.hits[#layout.hits + 1] = {
                        kind = "slider_plus",
                        item = item,
                        x = x + btnW + 36,
                        y = yRow,
                        w = btnW,
                        h = lineHeight
                    }
                else
                    drawTextLine(font, x, yRow, string.format("%s: %s", item.label, tostring(settings.appSettings[item.key] or "")), color)
                end
            end
        end

        -- Header with status and close
        drawTextLine(font, 10, h - headerH + 4, wTitle, color)
        drawTextLine(font, w - 18, h - headerH + 4, "X", color)

        -- Buttons (anchored bottom-right, do not affect list layout)
        local btnX = rightX
        local btnY = 6
        layout.buttons = {
            {
                id = "adjust_qv_xcam_cg",
                label = "Adjust QVs + X-Camera after CG shift",
                x = btnX,
                y = btnY + buttonH + 6,
                w = buttonW,
                h = buttonH
            },
            {
                id = "apply_qv0",
                label = "Apply QV0 to Default View",
                x = btnX,
                y = btnY,
                w = buttonW,
                h = buttonH
            },
        }
        for _, btn in ipairs(layout.buttons) do
            drawRectangle(btn.x, btn.y, btn.w, btn.h, {0.12, 0.12, 0.12, 0.95})
            drawFrame(btn.x, btn.y, btn.w, btn.h, {0.8, 0.8, 0.8, 0.9})
            drawTextLine(font, btn.x + 6, btn.y + 2, btn.label, color)
        end

        -- Draw scrollbar if needed
        if maxOffset > 0 then
            local trackHeight = scrollHeight
            local thumbHeight = math.max(12, trackHeight * (availableLines / (availableLines + maxOffset)))
            local travel = trackHeight - thumbHeight
            local rel = (maxOffset == 0) and 0 or (comp.scrollOffset / maxOffset)
            local thumbY = (h - headerH - controlAreaH - 12) - (rel * travel) - thumbHeight
            local trackX = w - 10
            local trackTop = h - headerH - controlAreaH - 12
            drawRectangle(trackX, (h - headerH - controlAreaH - 12) - trackHeight, 6, trackHeight, {0.3, 0.3, 0.3, 0.5})
            drawRectangle(trackX, thumbY, 6, thumbHeight, {0.8, 0.8, 0.8, 0.9})
            layout.scroll = {
                x = trackX,
                w = 6,
                top = trackTop,
                bottom = trackTop - trackHeight,
                trackHeight = trackHeight,
                thumbHeight = thumbHeight,
                maxOffset = maxOffset,
                availableLines = availableLines
            }
        end
        comp._layout = layout
    end

    function comp:onMouseDown(x, y, button)
        local layout = self._layout
        if not layout then return false end

        if button == MB_LEFT then
            -- Close
            if layout.close and x >= layout.close.x and x <= (layout.close.x + layout.close.w) and y >= layout.close.y and y <= (layout.close.y + layout.close.h) then
                if self._window then self._window:setIsVisible(false) end
                return true
            end
            -- scrollbar drag
            if layout.scroll and layout.scroll.maxOffset > 0 then
                local scroll = layout.scroll
                if x >= scroll.x and x <= (scroll.x + scroll.w) and y >= scroll.bottom and y <= scroll.top then
                    local travel = scroll.trackHeight - scroll.thumbHeight
                    local rel = (travel == 0) and 0 or (scroll.top - y - (scroll.thumbHeight / 2)) / travel
                    rel = math.max(0, math.min(1, rel))
                    self.scrollOffset = math.floor(rel * scroll.maxOffset + 0.5)
                    self.scrollDrag = {
                        startY = y,
                        startOffset = self.scrollOffset,
                        trackHeight = scroll.trackHeight,
                        thumbHeight = scroll.thumbHeight,
                        maxOffset = scroll.maxOffset
                    }
                    return true
                end
            end
            for _, btn in ipairs(layout.buttons or {}) do
                if x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
                    if btn.id == "adjust_qv_xcam_cg" then
                        helpers.adjustQuickViewsAndXCameraForCgChange()
                        return true
                    elseif btn.id == "apply_qv0" then
                        helpers.applyDefaultViewFromQV0()
                        return true
                    end
                end
            end
            for _, hit in ipairs(layout.hits or {}) do
                if x >= hit.x and x <= (hit.x + hit.w) and y >= hit.y and y <= (hit.y + hit.h) then
                    local item = hit.item
                    if hit.kind == "checkbox" then
                        if item.key == "DEBUGMODE" then
                            local nowDebug = sasl.getLogLevel() == LOG_DEBUG
                            if nowDebug then
                                sasl.setLogLevel(LOG_INFO)
                                helpers.logInfoTS("log mode set to INFO")
                            else
                                sasl.setLogLevel(LOG_DEBUG)
                                sasl.logDebug("log mode set to DEBUG")
                            end
                        else
                            settings.appSettings[item.key] = not_(settings.appSettings[item.key])
                            settings.writeSettings(settings.appSettings)
                        end
                        return true
                    elseif hit.kind == "number" then
                        self._focus = { key = item.key, minLen = item.minLen or 1, maxLen = item.maxLen or 10, kind = "number" }
                        self._editText = tostring(settings.appSettings[item.key] or "")
                        return true
                    elseif hit.kind == "text" then
                        self._focus = { key = item.key, minLen = item.minLen or 0, maxLen = item.maxLen or 16, kind = "text" }
                        self._editText = tostring(settings.appSettings[item.key] or "")
                        return true
                    elseif hit.kind == "slider_minus" then
                        local val = tonumber(settings.appSettings[item.key]) or item.minVal or 0
                        val = math.max(item.minVal or val, val - (item.step or 1))
                        settings.appSettings[item.key] = tostring(val)
                        settings.writeSettings(settings.appSettings)
                        return true
                    elseif hit.kind == "slider_plus" then
                        local val = tonumber(settings.appSettings[item.key]) or item.minVal or 0
                        val = math.min(item.maxVal or val, val + (item.step or 1))
                        settings.appSettings[item.key] = tostring(val)
                        settings.writeSettings(settings.appSettings)
                        return true
                    end
                end
            end
        end
        return false
    end

    function comp:onMouseWheel(_, _, _, clicks)
        if clicks == nil then return false end
        self.scrollOffset = self.scrollOffset + (-clicks)
        if self._lastMaxOffset then
            if self.scrollOffset < 0 then self.scrollOffset = 0 end
            if self.scrollOffset > self._lastMaxOffset then self.scrollOffset = self._lastMaxOffset end
        end
        return true
    end

    function comp:onMouseUp(_, _, button)
        if button == MB_LEFT and self.scrollDrag then
            self.scrollDrag = nil
            return true
        end
        return false
    end

    function comp:onMouseMove(_, y)
        if self.scrollDrag then
            local drag = self.scrollDrag
            local dy = drag.startY - y
            local travel = math.max(1, drag.trackHeight - drag.thumbHeight)
            local rel = dy / travel
            self.scrollOffset = math.floor(drag.startOffset + rel * drag.maxOffset + 0.5)
            if self.scrollOffset < 0 then self.scrollOffset = 0 end
            if self.scrollOffset > drag.maxOffset then self.scrollOffset = drag.maxOffset end
            return true
        end
        return false
    end

    local function getClipboardText()
        if sasl.getClipboardText then
            return sasl.getClipboardText()
        end
        if sasl.getClipboardString then
            return sasl.getClipboardString()
        end
        if sasl.getClipboard then
            return sasl.getClipboard()
        end
        return nil
    end

    local function filterTextInput(raw, maxLen)
        if not raw or raw == "" then return "" end
        local filtered = tostring(raw):gsub("[^%w%-]", "")
        if maxLen and #filtered > maxLen then
            filtered = string.sub(filtered, 1, maxLen)
        end
        return filtered
    end

    function comp:onKeyDown(char, vkey, shift, ctrl, alt)
        if not self._focus then return false end
        local kind = self._focus.kind or "number"
        if char == SASL_KEY_ESCAPE then
            self._focus = nil
            self._editText = nil
            return true
        elseif char == SASL_KEY_RETURN then
            local txt = self._editText or ""
            local minL = self._focus.minLen or (kind == "number" and 1 or 0)
            local maxL = self._focus.maxLen or 10
            if #txt >= minL and #txt <= maxL then
                settings.appSettings[self._focus.key] = txt
                settings.writeSettings(settings.appSettings)
            end
            self._focus = nil
            self._editText = nil
            return true
        elseif char == 8 then -- backspace
            if self._editText and #self._editText > 0 then
                self._editText = string.sub(self._editText, 1, #self._editText - 1)
            end
            return true
        elseif kind == "text" and ctrl and (char == 22 or char == 86 or char == 118 or vkey == 86) then
            local clip = getClipboardText()
            if clip then
                local maxL = self._focus.maxLen or 16
                self._editText = filterTextInput(clip, maxL)
            end
            return true
        elseif kind == "number" and char and char >= 48 and char <= 57 then
            if not self._editText then self._editText = "" end
            local maxL = self._focus.maxLen or 10
            if #self._editText < maxL then
                self._editText = self._editText .. string.char(char)
            end
            return true
        elseif kind == "text" and char then
            local isAlphaNum = (char >= 48 and char <= 57) or (char >= 65 and char <= 90) or (char >= 97 and char <= 122)
            local isExtra = (char == 45 or char == 95)
            if isAlphaNum or isExtra then
                if not self._editText then self._editText = "" end
                local maxL = self._focus.maxLen or 16
                if #self._editText < maxL then
                    self._editText = self._editText .. string.char(char)
                end
                return true
            end
        end
        return false
    end
    function comp:onKeyUp(...) return false end
    function comp:update() end

    return comp
end

function M.windowSize()
    return defaultW, defaultH
end

return M
