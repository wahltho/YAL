local M = {}

local defaultW = 560
local defaultH = 220
local headerH = 18
local padding = 12

local def = require("definitions")

local function getSafeFont()
    if def and def.wFont then
        return def.wFont
    end
    return sasl.gl.loadFont("DejaVuSansMono.ttf")
end

local function drawText(font, x, y, text, size, align, color)
    sasl.gl.drawText(font, x, y, tostring(text or ""), size or 12, false, false, align or TEXT_ALIGN_LEFT, color or {1, 1, 1, 1})
end

local function wrap_line(text, maxChars)
    local out = {}
    local s = tostring(text or "")
    if s == "" then
        out[1] = ""
        return out
    end
    while #s > maxChars do
        local cut = maxChars
        local i = maxChars
        while i > 1 do
            local ch = string.sub(s, i, i)
            if ch == " " then
                cut = i - 1
                break
            end
            i = i - 1
        end
        if cut < 1 then
            cut = maxChars
        end
        out[#out + 1] = string.sub(s, 1, cut)
        s = string.sub(s, cut + 1)
        s = (s:gsub("^%s+", ""))
    end
    if s ~= "" then
        out[#out + 1] = s
    end
    return out
end

function M.windowSize()
    return defaultW, defaultH
end

function M.newComponent(ctx)
    local comp = {}
    comp.name = "yal_update_popup_component"
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
    comp._payload = nil
    comp._okRect = nil
    comp._drag = nil
    comp._onAcknowledge = ctx and ctx.onAcknowledge or nil

    function comp:setWindow(win)
        self._window = win
    end

    function comp:setPayload(payload)
        self._payload = payload or {}
        if self._window and self._window.isVisible and not self._window:isVisible() then
            self._window:setIsVisible(true)
        end
    end

    function comp:clearPayload()
        self._payload = nil
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
        if not self._payload then
            return
        end
        local w, h = getSize()
        local font = getSafeFont()
        local title = tostring(self._payload.title or "Update available")
        local okLabel = tostring(self._payload.okLabel or "OK")
        local lines = self._payload.lines or {}

        drawRectangle(0, 0, w, h, {0, 0, 0, 0.72})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.72, 0.72, 0.72, 0.9})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 0.95})
        drawText(font, 8, h - headerH + 3, title, 12, TEXT_ALIGN_LEFT, {0.95, 0.95, 0.95, 1})

        local y = h - headerH - 12
        for _, line in ipairs(lines) do
            local wrapped = wrap_line(line, 70)
            for _, part in ipairs(wrapped) do
                drawText(font, padding, y, part, 12, TEXT_ALIGN_LEFT, {0.92, 0.92, 0.96, 1})
                y = y - 16
                if y < 48 then
                    break
                end
            end
            if y < 48 then
                break
            end
            y = y - 2
        end

        local btnW = 90
        local btnH = 20
        local btnX = math.floor((w - btnW) * 0.5)
        local btnY = 12
        self._okRect = { x = btnX, y = btnY, w = btnW, h = btnH }
        drawRectangle(btnX, btnY, btnW, btnH, {0.15, 0.15, 0.15, 0.95})
        drawFrame(btnX, btnY, btnW, btnH, {0.85, 0.85, 0.85, 0.95})
        drawText(font, btnX + math.floor(btnW * 0.5), btnY + 4, okLabel, 12, TEXT_ALIGN_CENTER, {0.95, 0.95, 0.95, 1})
    end

    function comp:onMouseDown(x, y, button)
        if not (button == MB_LEFT or button == 1) then
            return false
        end
        local btn = self._okRect
        if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
            if self._onAcknowledge then
                pcall(self._onAcknowledge, self._payload)
            end
            self:clearPayload()
            return true
        end
        if self._window and self._window.getPosition then
            local wx, wy, ww, hh = self._window:getPosition()
            self._drag = { startX = x, startY = y, winX = wx, winY = wy, winW = ww, winH = hh }
            return true
        end
        return false
    end

    function comp:onMouseMove(x, y)
        if not self._drag or not self._window then
            return false
        end
        local dx = x - self._drag.startX
        local dy = y - self._drag.startY
        self._window:setPosition(self._drag.winX + dx, self._drag.winY + dy, self._drag.winW, self._drag.winH)
        return true
    end

    function comp:onMouseUp(_, _, button)
        if (button == MB_LEFT or button == 1) and self._drag then
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
