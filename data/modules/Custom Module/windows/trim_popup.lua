local M = {}

local defaultW = 200
local defaultH = 118
local headerH = 18

local def = require("definitions")
local helpers = require("helpers")

local function getSafeFont()
    if def and def.wFont then
        return def.wFont
    end
    return sasl.gl.loadFont("DejaVuSansMono.ttf")
end

local function drawText(font, x, y, text, size, align, color)
    sasl.gl.drawText(font, x, y, tostring(text or ""), size or 12, false, false, align or TEXT_ALIGN_LEFT, color or {1, 1, 1, 1})
end

local function drawArrow(direction, cx, cy, size, color)
    local half = size * 0.5
    local headLen = size * 0.35
    local headW = size * 0.55
    local shaftW = size * 0.18

    if direction == "down" then
        local tipY = cy - half
        local baseY = tipY + headLen
        drawTriangle(cx, tipY, cx - headW * 0.5, baseY, cx + headW * 0.5, baseY, color)
        drawRectangle(cx - shaftW * 0.5, cy - half + headLen, shaftW, size - headLen, color)
        return
    end

    if direction == "up" then
        local tipY = cy + half
        local baseY = tipY - headLen
        drawTriangle(cx, tipY, cx - headW * 0.5, baseY, cx + headW * 0.5, baseY, color)
        drawRectangle(cx - shaftW * 0.5, cy - half, shaftW, size - headLen, color)
        return
    end

    drawRectangle(cx - half * 0.5, cy - shaftW * 0.5, half, shaftW, color)
end

function M.windowSize()
    return defaultW, defaultH
end

function M.newComponent(ctx)
    local comp = {}
    comp.name = "yal_trim_popup_component"
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
    comp._yal = ctx and ctx.yal or _G.yal
    comp._onMoveEnd = ctx and ctx.onMoveEnd or nil
    comp._status = nil
    comp._drag = nil
    comp._lastTrimWheel = nil
    comp._lastInputTs = nil
    comp._targetReachedTs = nil
    comp._lastRequestOpenId = 0

    function comp:setWindow(win)
        self._window = win
    end

    function comp:clearStatus()
        self._status = nil
        self._lastInputTs = nil
        self._targetReachedTs = nil
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

    local function nowSec()
        return os.time() or 0
    end

    local function getGlobalMousePos()
        local mx = sasl.getCSMouseXPos and sasl.getCSMouseXPos() or nil
        local my = sasl.getCSMouseYPos and sasl.getCSMouseYPos() or nil
        if mx == nil or my == nil then
            return nil, nil
        end
        return mx, my
    end

    function comp:tick()
        local yalref = self._yal or _G.yal
        local state = yalref and yalref.trimAdvicePopupState or nil
        local trimwheel = yalref and yalref.trimwheel and tonumber(get(yalref.trimwheel) or 0) or nil
        local now = nowSec()
        local wheelMoved = false

        if trimwheel ~= nil and self._lastTrimWheel ~= nil then
            wheelMoved = math.abs(trimwheel - self._lastTrimWheel) > 0.0001
        end
        self._lastTrimWheel = trimwheel

        if not state or state.active ~= true or not state.target then
            self:clearStatus()
            return
        end

        local target = tonumber(state.target)
        if not target or target <= 0 or trimwheel == nil then
            self:clearStatus()
            return
        end
        local pinned = (state.pinned == true)
        local requestOpenId = tonumber(state.requestOpenId) or 0
        local requestOpen = (requestOpenId > 0) and (requestOpenId ~= self._lastRequestOpenId)

        if wheelMoved then
            self._lastInputTs = now
        end
        if requestOpen then
            self._lastInputTs = now
        end

        local currentTrim = helpers.gettrim(trimwheel)
        currentTrim = helpers.round_to_step(currentTrim, 0.25) or currentTrim
        local matched = helpers.trimwheel_matches_trim_step(trimwheel, target, 0.25)
        if matched then
            if not self._targetReachedTs then
                self._targetReachedTs = now
            end
        else
            self._targetReachedTs = nil
        end

        local direction = "center"
        if currentTrim ~= nil and target ~= nil then
            if math.abs(currentTrim - target) > 0.01 then
                direction = (currentTrim < target) and "up" or "down"
            end
        end

        if self._window and self._window.isVisible and not self._window:isVisible() and (pinned or requestOpen) then
            self._window:setIsVisible(true)
        end
        if requestOpen then
            self._lastRequestOpenId = requestOpenId
        end

        self._status = {
            currentText = helpers.format_trim_quarter(currentTrim) or tostring(currentTrim or ""),
            targetText = helpers.format_trim_quarter(target) or tostring(target),
            direction = direction,
            matched = matched,
            pinned = pinned
        }

        if self._window and self._window.isVisible and self._window:isVisible() then
            if self._drag then
                return
            end
            if pinned then
                return
            end
            if matched and self._targetReachedTs and (now - self._targetReachedTs) >= 5 then
                self:clearStatus()
                return
            end
            if self._lastInputTs and (now - self._lastInputTs) >= 5 then
                self:clearStatus()
                return
            end
        end
    end

    function comp:draw()
        if not self._status then
            return
        end
        local w, h = getSize()
        local font = getSafeFont()
        local matched = self._status.matched == true
        local arrowColor = matched and {0.35, 0.9, 0.45, 0.95} or {0.95, 0.82, 0.2, 0.95}

        drawRectangle(0, 0, w, h, {0.0, 0.0, 0.0, 0.68})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.72, 0.72, 0.72, 0.8})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 0.92})
        drawText(font, w * 0.5, h - headerH + 3, "TRIM", 12, TEXT_ALIGN_CENTER, {0.95, 0.95, 0.95, 1})

        drawArrow(self._status.direction or "center", 34, h * 0.5 - 2, 42, arrowColor)

        drawText(font, 66, h - 42, "CURRENT", 11, TEXT_ALIGN_LEFT, {0.82, 0.82, 0.86, 0.95})
        drawText(font, 66, h - 58, tostring(self._status.currentText or ""), 16, TEXT_ALIGN_LEFT, {0.98, 0.98, 0.98, 1})
        drawText(font, 66, h - 82, "TARGET", 11, TEXT_ALIGN_LEFT, {0.82, 0.82, 0.86, 0.95})
        drawText(font, 66, h - 98, tostring(self._status.targetText or ""), 16, TEXT_ALIGN_LEFT, matched and {0.35, 0.95, 0.45, 1} or {0.98, 0.98, 0.98, 1})
    end

    function comp:onMouseDown(x, y, button)
        if not (button == MB_LEFT or button == 1) then
            return false
        end
        local _, h = getSize()
        if y < (h - headerH) then
            return false
        end
        if not self._window or not self._window.getPosition then
            return false
        end
        local wx, wy, ww, hh = self._window:getPosition()
        local startMouseX, startMouseY = getGlobalMousePos()
        self._drag = {
            startMouseX = startMouseX,
            startMouseY = startMouseY,
            fallbackX = x,
            fallbackY = y,
            winX = wx,
            winY = wy,
            winW = ww,
            winH = hh
        }
        self._lastInputTs = nowSec()
        return true
    end

    function comp:onMouseMove(x, y)
        if not self._drag or not self._window then
            return false
        end
        local mouseX, mouseY = getGlobalMousePos()
        local dx = nil
        local dy = nil
        if mouseX ~= nil and mouseY ~= nil and self._drag.startMouseX ~= nil and self._drag.startMouseY ~= nil then
            dx = mouseX - self._drag.startMouseX
            dy = mouseY - self._drag.startMouseY
        else
            dx = x - (self._drag.fallbackX or x)
            dy = y - (self._drag.fallbackY or y)
        end
        local newX = math.floor((self._drag.winX + dx) + 0.5)
        local newY = math.floor((self._drag.winY + dy) + 0.5)
        self._window:setPosition(newX, newY, self._drag.winW, self._drag.winH)
        self._lastInputTs = nowSec()
        return true
    end

    function comp:onMouseUp(_, _, button)
        if (button == MB_LEFT or button == 1) and self._drag then
            self._lastInputTs = nowSec()
            if self._window and self._window.getPosition and self._onMoveEnd then
                local wx, wy = self._window:getPosition()
                pcall(self._onMoveEnd, wx, wy)
            end
            self._drag = nil
            return true
        end
        return false
    end

    function comp:update()
        -- no-op
    end

    return comp
end

return M
