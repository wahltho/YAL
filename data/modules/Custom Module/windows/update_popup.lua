local M = {}

local defaultW = 660
local defaultH = 340
local headerH = 22
local padding = 14

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

local function safeText(value, fallback)
    if value == nil or value == "" then
        return fallback or "?"
    end
    return tostring(value)
end

local function versionText(value)
    local text = safeText(value, "?")
    if text == "?" then
        return "v?"
    end
    local first = string.sub(text, 1, 1)
    if first == "v" or first == "V" then
        return text
    end
    return "v" .. text
end

local function checkedAtText(ts)
    local n = tonumber(ts or 0) or 0
    if n > 0 then
        local ok, value = pcall(os.date, "%Y-%m-%d %H:%M", n)
        if ok and value then
            return tostring(value) .. " local"
        end
    end
    return "unknown"
end

local function channelTitle(channel)
    if channel and channel.active == "beta" then
        return "Beta / RC"
    end
    return "Stable"
end

local function channelStatusText(channel)
    if channel and channel.active == "beta" then
        return "You are on beta channel"
    end
    return "You are on stable channel"
end

local function channelReasonText(channel)
    local reason = channel and channel.reason or ""
    if reason == "setting enabled" then
        return "Beta setting ON"
    end
    if reason == "installed prerelease" then
        return "Prerelease installed"
    end
    return "Stable setting"
end

local function feedComparisonText(channel)
    local cmp = channel and channel.stableVsBeta or ""
    if cmp == "same" then
        return "Stable = beta"
    end
    if cmp == "beta-newer" then
        return "Beta newer than stable"
    end
    if cmp == "stable-newer" then
        return "Stable newer than beta"
    end
    return "Compare unavailable"
end

local function statusText(available, skipped)
    if skipped then
        return "Skipped"
    end
    if available then
        return "Update available"
    end
    return "Up to date"
end

local function statusColor(available, skipped)
    if skipped then
        return {0.78, 0.78, 0.82, 1}
    end
    if available then
        return {1.0, 0.78, 0.32, 1}
    end
    return {0.62, 0.88, 0.66, 1}
end

local function feedVersionText(version, available)
    local text = versionText(version)
    if available then
        return text .. " available"
    end
    return text
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

local function drawButton(font, rect, label, primary)
    local bg = primary and {0.24, 0.31, 0.44, 0.95} or {0.15, 0.15, 0.17, 0.95}
    local frame = primary and {0.72, 0.80, 0.95, 0.95} or {0.72, 0.72, 0.76, 0.95}
    drawRectangle(rect.x, rect.y, rect.w, rect.h, bg)
    drawFrame(rect.x, rect.y, rect.w, rect.h, frame)
    drawText(font, rect.x + math.floor(rect.w * 0.5), rect.y + 5, label, 12, TEXT_ALIGN_CENTER, {0.96, 0.96, 0.98, 1})
end

local function drawRows(font, x, y, rows)
    local yy = y
    for _, row in ipairs(rows or {}) do
        drawText(font, x, yy, row[1], 11, TEXT_ALIGN_LEFT, {0.68, 0.70, 0.76, 1})
        drawText(font, x + 116, yy, row[2], 11, TEXT_ALIGN_LEFT, row[3] or {0.92, 0.92, 0.96, 1})
        yy = yy - 15
    end
end

local function drawSection(font, x, top, w, h, title, status, statusClr, rows)
    drawRectangle(x, top - h, w, h, {0.06, 0.065, 0.075, 0.92})
    drawFrame(x, top - h, w, h, {0.34, 0.35, 0.40, 0.88})
    drawText(font, x + 10, top - 20, title, 13, TEXT_ALIGN_LEFT, {0.96, 0.96, 0.98, 1})
    if status and status ~= "" then
        drawText(font, x + w - 10, top - 19, status, 11, TEXT_ALIGN_RIGHT, statusClr or {0.92, 0.92, 0.96, 1})
    end
    drawRows(font, x + 10, top - 42, rows)
end

local function legacyRows(payload)
    local rows = {}
    for _, line in ipairs(payload.lines or {}) do
        rows[#rows + 1] = {"", tostring(line or "")}
    end
    return rows
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
    comp._buttons = {}
    comp._drag = nil
    comp._onAcknowledge = ctx and ctx.onAcknowledge or nil
    comp._onSettings = ctx and ctx.onSettings or nil

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
        local settingsLabel = tostring(self._payload.settingsLabel or "Settings")
        local yalInfo = self._payload.yal
        local ziboInfo = self._payload.zibo
        local channelInfo = self._payload.channel
        local hasStructuredPayload = yalInfo or ziboInfo or channelInfo

        drawRectangle(0, 0, w, h, {0, 0, 0, 0.78})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.72, 0.72, 0.72, 0.9})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.13, 0.96})
        drawText(font, 9, h - headerH + 5, title, 13, TEXT_ALIGN_LEFT, {0.96, 0.96, 0.98, 1})

        local checked = "Checked: " .. checkedAtText(self._payload.checkedAt)
        local activeChannel = "Channel: " .. channelTitle(channelInfo)
        drawText(font, padding, h - 48, checked .. " | " .. activeChannel, 12, TEXT_ALIGN_LEFT, {0.78, 0.80, 0.86, 1})

        if hasStructuredPayload then
            local colW = math.floor((w - padding * 3) / 2)
            local leftX = padding
            local rightX = padding * 2 + colW
            local top = h - 66
            local sectionH = 108
            local yalRows = {
                {"Installed", versionText(yalInfo and yalInfo.current)},
                {"Current feed", feedVersionText(yalInfo and yalInfo.latest, yalInfo and yalInfo.channelAvailable)},
                {"Latest stable", feedVersionText(yalInfo and yalInfo.latestStable, yalInfo and yalInfo.stableAvailable)},
                {"Latest beta/RC", feedVersionText(yalInfo and yalInfo.latestBeta, yalInfo and yalInfo.betaAvailable)},
            }
            local channelRows = {
                {"Current", channelTitle(channelInfo)},
                {"Reason", channelReasonText(channelInfo)},
                {"Stable vs beta", feedComparisonText(channelInfo)},
            }
            local ziboRows = {}
            if ziboInfo and ziboInfo.skipped then
                ziboRows = {
                    {"Status", safeText(ziboInfo.skippedReason, "Skipped")},
                    {"Release", versionText(ziboInfo.levelUpRelease or ziboInfo.current)},
                    {"Flight model", versionText(ziboInfo.levelUpFlightModel)},
                }
            else
                ziboRows = {
                    {"Installed", versionText(ziboInfo and ziboInfo.current)},
                    {"Latest", versionText(ziboInfo and ziboInfo.latest)},
                }
            end

            drawSection(
                font, leftX, top, colW, sectionH, "YAL",
                statusText(yalInfo and yalInfo.available, false),
                statusColor(yalInfo and yalInfo.available, false),
                yalRows
            )
            drawSection(
                font, rightX, top, colW, sectionH, "Channel",
                channelStatusText(channelInfo),
                {0.84, 0.86, 0.92, 1},
                channelRows
            )
            drawSection(
                font, leftX, top - sectionH - 12, w - padding * 2, 76, "Zibo / LevelUp",
                statusText(ziboInfo and ziboInfo.available, ziboInfo and ziboInfo.skipped),
                statusColor(ziboInfo and ziboInfo.available, ziboInfo and ziboInfo.skipped),
                ziboRows
            )
        else
            local y = h - headerH - 12
            for _, row in ipairs(legacyRows(self._payload)) do
                local wrapped = wrap_line(row[2], 70)
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
        end

        local btnW = 92
        local btnH = 20
        local gap = 10
        local settingsW = 112
        local totalW = btnW + gap + settingsW
        local btnX = math.floor((w - totalW) * 0.5)
        local btnY = 12
        self._buttons = {
            ok = { x = btnX, y = btnY, w = btnW, h = btnH },
            settings = { x = btnX + btnW + gap, y = btnY, w = settingsW, h = btnH },
        }
        drawButton(font, self._buttons.ok, okLabel, true)
        drawButton(font, self._buttons.settings, settingsLabel, false)
    end

    function comp:onMouseDown(x, y, button)
        if not (button == MB_LEFT or button == 1) then
            return false
        end
        local btn = self._buttons and self._buttons.ok or nil
        if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
            if self._onAcknowledge then
                pcall(self._onAcknowledge, self._payload)
            end
            self:clearPayload()
            return true
        end
        btn = self._buttons and self._buttons.settings or nil
        if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
            if self._onSettings then
                pcall(self._onSettings, self._payload)
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
