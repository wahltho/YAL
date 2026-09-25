local M = {}

local defaultW = 720
local defaultH = 250
local headerH = 24

local def = require("definitions")
local helpers = require("helpers")

local XPLANE_ORG_URL = "https://forums.x-plane.org/files/file/91049-yet-another-linda-yal-for-zibo-mod-level-up/"
local DISCORD_URL = "https://discord.gg/FGAyes97M"

local function getSafeFont()
    if def and def.wFont then
        return def.wFont
    end
    return sasl.gl.loadFont("DejaVuSansMono.ttf")
end

local function drawText(font, x, y, text, size, align, color)
    sasl.gl.drawText(font, x, y, tostring(text or ""), size or 12, false, false,
        align or TEXT_ALIGN_LEFT, color or {1, 1, 1, 1})
end

local function drawButton(font, rect, label, primary)
    local bg = primary and {0.24, 0.31, 0.44, 0.95} or {0.15, 0.15, 0.17, 0.95}
    local frame = primary and {0.72, 0.80, 0.95, 0.95} or {0.72, 0.72, 0.76, 0.95}
    drawRectangle(rect.x, rect.y, rect.w, rect.h, bg)
    drawFrame(rect.x, rect.y, rect.w, rect.h, frame)
    drawText(font, rect.x + math.floor(rect.w * 0.5), rect.y + 7, label, 11,
        TEXT_ALIGN_CENTER, {0.96, 0.96, 0.98, 1})
end

local function isInside(rect, x, y)
    return rect and x >= rect.x and x <= (rect.x + rect.w)
        and y >= rect.y and y <= (rect.y + rect.h)
end

function M.windowSize()
    return defaultW, defaultH
end

function M.newComponent()
    local comp = {}
    comp.name = "yal_support_component"
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
    comp._buttons = {}
    comp._drag = nil
    comp._status = ""
    comp._statusOk = true

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

    local function getGlobalMousePos()
        local mx = sasl.getCSMouseXPos and sasl.getCSMouseXPos() or nil
        local my = sasl.getCSMouseYPos and sasl.getCSMouseYPos() or nil
        if mx == nil or my == nil then
            return nil, nil
        end
        return mx, my
    end

    local function copyLink(label, url)
        if type(sasl.setClipboardText) ~= "function" then
            comp._status = "Clipboard access is not available."
            comp._statusOk = false
            sasl.logWarning("YAL Support: clipboard access is not available")
            return
        end
        local ok, err = pcall(sasl.setClipboardText, url)
        if not ok then
            comp._status = "Could not copy link to clipboard."
            comp._statusOk = false
            sasl.logWarning("YAL Support: clipboard write failed: " .. tostring(err))
            return
        end
        comp._status = label .. " copied to clipboard."
        comp._statusOk = true
        helpers.logInfoTS("Support link copied: " .. label)
    end

    function comp:draw()
        local w, h = getSize()
        local font = getSafeFont()

        drawRectangle(0, 0, w, h, {0.0, 0.0, 0.0, 0.76})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.72, 0.72, 0.72, 0.84})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 0.96})
        drawText(font, 12, h - headerH + 5, "YAL Support", 12, TEXT_ALIGN_LEFT,
            {0.96, 0.96, 0.98, 1})

        drawText(font, 16, h - 50, "Support, questions and bug reports", 13, TEXT_ALIGN_LEFT,
            {0.96, 0.96, 0.98, 1})
        drawText(font, 16, h - 78, "X-Plane.org download and support page", 11, TEXT_ALIGN_LEFT,
            {0.76, 0.80, 0.90, 1})
        drawText(font, 16, h - 95, XPLANE_ORG_URL, 9, TEXT_ALIGN_LEFT,
            {0.92, 0.92, 0.96, 1})
        drawText(font, 16, h - 122, "YAL Discord community", 11, TEXT_ALIGN_LEFT,
            {0.76, 0.80, 0.90, 1})
        drawText(font, 16, h - 139, DISCORD_URL, 10, TEXT_ALIGN_LEFT,
            {0.92, 0.92, 0.96, 1})
        drawText(font, 16, h - 168,
            "For technical issues, include X-Plane Log.txt and YAL SASLLog.txt.", 10,
            TEXT_ALIGN_LEFT, {0.78, 0.78, 0.82, 1})

        if self._status ~= "" then
            local color = self._statusOk and {0.62, 0.88, 0.66, 1} or {1.0, 0.58, 0.48, 1}
            drawText(font, 16, 51, self._status, 10, TEXT_ALIGN_LEFT, color)
        end

        local buttonY = 14
        local buttonH = 30
        self._buttons.xplane = {x = 16, y = buttonY, w = 220, h = buttonH}
        self._buttons.discord = {x = 248, y = buttonY, w = 190, h = buttonH}
        self._buttons.close = {x = w - 98, y = buttonY, w = 82, h = buttonH}
        drawButton(font, self._buttons.xplane, "Copy X-Plane.org link", true)
        drawButton(font, self._buttons.discord, "Copy Discord invite", false)
        drawButton(font, self._buttons.close, "Close", false)
    end

    function comp:onMouseDown(x, y, button)
        if not (button == MB_LEFT or button == 1) then
            return false
        end
        if isInside(self._buttons.xplane, x, y) then
            copyLink("X-Plane.org link", XPLANE_ORG_URL)
            return true
        end
        if isInside(self._buttons.discord, x, y) then
            copyLink("Discord invite", DISCORD_URL)
            return true
        end
        if isInside(self._buttons.close, x, y) then
            self._status = ""
            if self._window then
                self._window:setIsVisible(false)
            end
            return true
        end

        local _, h = getSize()
        if y < (h - headerH) or not self._window or not self._window.getPosition then
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
        return true
    end

    function comp:onMouseMove(x, y)
        if not self._drag or not self._window then
            return false
        end
        local mouseX, mouseY = getGlobalMousePos()
        local dx
        local dy
        if mouseX ~= nil and mouseY ~= nil and self._drag.startMouseX ~= nil
                and self._drag.startMouseY ~= nil then
            dx = mouseX - self._drag.startMouseX
            dy = mouseY - self._drag.startMouseY
        else
            dx = x - (self._drag.fallbackX or x)
            dy = y - (self._drag.fallbackY or y)
        end
        local newX = math.floor((self._drag.winX + dx) + 0.5)
        local newY = math.floor((self._drag.winY + dy) + 0.5)
        self._window:setPosition(newX, newY, self._drag.winW, self._drag.winH)
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
