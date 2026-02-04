local M = {}

local defaultW = 240
local defaultH = 140
local headerH = 16
local padding = 10
local arrowSize = 52
local actionFont = 14
local labelFont = 12

local def = require("definitions")

local function getSafeFont()
    if def and def.wFont then
        return def.wFont
    end
    return sasl.gl.loadFont("DejaVuSansMono.ttf")
end

local function drawText(font, x, y, text, size, align, color)
    sasl.gl.drawText(font, x, y, tostring(text or ""), size, false, false, align or TEXT_ALIGN_LEFT, color or {1, 1, 1, 1})
end

local function drawArrow(direction, cx, cy, size, color)
    local half = size * 0.5
    local headLen = size * 0.35
    local headW = size * 0.55
    local shaftH = size * 0.18

    if direction == "left" then
        local tipX = cx - half
        local baseX = tipX + headLen
        drawTriangle(tipX, cy, baseX, cy + headW * 0.5, baseX, cy - headW * 0.5, color)
        drawRectangle(baseX, cy - shaftH * 0.5, size - headLen, shaftH, color)
        return
    end

    if direction == "right" then
        local tipX = cx + half
        local baseX = tipX - headLen
        drawTriangle(tipX, cy, baseX, cy + headW * 0.5, baseX, cy - headW * 0.5, color)
        drawRectangle(cx - half, cy - shaftH * 0.5, size - headLen, shaftH, color)
        return
    end

    -- straight / default
    local tipY = cy + half
    local baseY = tipY - headLen
    drawTriangle(cx, tipY, cx - headW * 0.5, baseY, cx + headW * 0.5, baseY, color)
    drawRectangle(cx - shaftH * 0.5, cy - half, shaftH, size - headLen, color)
end

function M.windowSize()
    return defaultW, defaultH
end

function M.newComponent(ctx)
    local comp = {}
    comp.name = "yal_taxi_popup_component"
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
    comp._instruction = nil
    comp._drag = nil

    function comp:setWindow(win)
        self._window = win
    end

    function comp:setInstruction(info)
        if not info then
            return
        end
        self._instruction = info
        if self._window and self._window.isVisible and not self._window:isVisible() then
            self._window:setIsVisible(true)
        end
    end

    function comp:clearInstruction()
        self._instruction = nil
        if self._window and self._window.isVisible and self._window:isVisible() then
            self._window:setIsVisible(false)
        end
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
        if not self._instruction then
            return
        end
        local w, h = getSize()
        local font = getSafeFont()
        local arrowColor = {0.95, 0.85, 0.2, 0.95}

        drawRectangle(0, 0, w, h, {0.0, 0.0, 0.0, 0.65})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.7, 0.7, 0.7, 0.7})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 0.9})
        drawText(font, w * 0.5, h - headerH + 3, "TAXI", 12, TEXT_ALIGN_CENTER, {0.9, 0.9, 0.9, 0.9})

        local direction = tostring(self._instruction.direction or "straight")
        drawArrow(direction, w * 0.5, h - headerH - arrowSize * 0.5 - 6, arrowSize, arrowColor)

        local action = tostring(self._instruction.action or "")
        local label = tostring(self._instruction.label or "")
        action = string.upper(action)
        label = string.upper(label)

        if label == "" then
            drawText(font, w * 0.5, padding + 12, action, actionFont, TEXT_ALIGN_CENTER, {1, 1, 1, 0.95})
        else
            drawText(font, w * 0.5, padding + 28, action, actionFont, TEXT_ALIGN_CENTER, {1, 1, 1, 0.95})
            drawText(font, w * 0.5, padding + 10, label, labelFont, TEXT_ALIGN_CENTER, {0.85, 0.85, 0.85, 0.95})
        end
    end

    function comp:onMouseDown(x, y, button, _, _)
        if not (button == MB_LEFT or button == 1) then
            return false
        end
        if not self._window or not self._window.getPosition then
            return false
        end
        local wx, wy, ww, hh = self._window:getPosition()
        self._drag = { startX = x, startY = y, winX = wx, winY = wy, winW = ww, winH = hh }
        return true
    end

    function comp:onMouseMove(x, y, _, _, _)
        if not self._drag or not self._window then
            return false
        end
        local dx = x - self._drag.startX
        local dy = y - self._drag.startY
        self._window:setPosition(self._drag.winX + dx, self._drag.winY + dy, self._drag.winW, self._drag.winH)
        return true
    end

    function comp:onMouseUp(_, _, button, _, _)
        if (button == MB_LEFT or button == 1) and self._drag then
            self._drag = nil
            return true
        end
        return false
    end

    function comp:update()
        -- no-op to satisfy SASL updateAll()
    end

    return comp
end

return M
