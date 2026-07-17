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
    if reason == "stable selected on prerelease" then
        return "Stable setting"
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

local function statusText(available, skipped, ignored)
    if skipped then
        return "Skipped"
    end
    if ignored then
        return "Ignored"
    end
    if available then
        return "Update available"
    end
    return "Up to date"
end

local function statusColor(available, skipped, ignored)
    if skipped then
        return {0.78, 0.78, 0.82, 1}
    end
    if ignored then
        return {0.72, 0.76, 0.88, 1}
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

local function hasActionableUpdate(payload)
    local yalInfo = payload and payload.yal or nil
    local ziboInfo = payload and payload.zibo or nil
    return (yalInfo and yalInfo.available) or (ziboInfo and ziboInfo.available)
end

local function getIgnoreLabel(payload)
    local yalInfo = payload and payload.yal or nil
    local ziboInfo = payload and payload.zibo or nil
    local count = 0
    if yalInfo and yalInfo.available then count = count + 1 end
    if ziboInfo and ziboInfo.available then count = count + 1 end
    if count > 1 then
        return "Ignore versions"
    end
    if yalInfo and yalInfo.available then
        return "Ignore YAL"
    end
    if ziboInfo and ziboInfo.available then
        return "Ignore Zibo"
    end
    return "Ignore"
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
    comp._onIgnore = ctx and ctx.onIgnore or nil
    comp._onInstall = ctx and ctx.onInstall or nil
    comp._onConfirm = ctx and ctx.onConfirm or nil
    comp._onCancel = ctx and ctx.onCancel or nil
    comp._onAction = ctx and ctx.onAction or nil
    comp._onMaintenanceAction = ctx and ctx.onMaintenanceAction or nil

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
        local laterLabel = tostring(self._payload.laterLabel or self._payload.okLabel or "Later")
        local installLabel = tostring(self._payload.installLabel or "Install YAL Update")
        local yalInfo = self._payload.yal
        local ziboInfo = self._payload.zibo
        local channelInfo = self._payload.channel
        local hasStructuredPayload = yalInfo or ziboInfo or channelInfo
        local mode = tostring(self._payload.mode or "")
        self._buttons = {}

        drawRectangle(0, 0, w, h, {0, 0, 0, 0.78})
        drawFrame(0.5, 0.5, w - 1, h - 1, {0.72, 0.72, 0.72, 0.9})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.13, 0.96})
        drawText(font, 9, h - headerH + 5, title, 13, TEXT_ALIGN_LEFT, {0.96, 0.96, 0.98, 1})

        if mode == "confirm" or mode == "status" then
            local lines = self._payload.lines or {}
            local y = h - 58
            for _, line in ipairs(lines) do
                local wrapped = wrap_line(line, 76)
                for _, part in ipairs(wrapped) do
                    drawText(font, padding, y, part, 12, TEXT_ALIGN_LEFT, {0.92, 0.92, 0.96, 1})
                    y = y - 17
                end
                y = y - 3
            end

            local btnH = 20
            local gap = 10
            local okW = 82
            local cancelW = 92
            local btnY = 12
            self._buttons = {}
            if mode == "confirm" then
                local totalW = cancelW + gap + okW
                local btnX = math.floor((w - totalW) * 0.5)
                self._buttons.cancel = { x = btnX, y = btnY, w = cancelW, h = btnH }
                self._buttons.ok = { x = btnX + cancelW + gap, y = btnY, w = okW, h = btnH }
                drawButton(font, self._buttons.cancel, tostring(self._payload.cancelLabel or "Cancel"), false)
                drawButton(font, self._buttons.ok, tostring(self._payload.okLabel or "OK"), true)
            else
                local btnX = math.floor((w - okW) * 0.5)
                self._buttons.ok = { x = btnX, y = btnY, w = okW, h = btnH }
                drawButton(font, self._buttons.ok, tostring(self._payload.okLabel or "OK"), true)
            end
            return
        end

        if mode == "vnav" then
            local lines = self._payload.lines or {}
            local y = h - 50
            for _, line in ipairs(lines) do
                local wrapped = wrap_line(line, 78)
                for _, part in ipairs(wrapped) do
                    drawText(font, padding, y, part, 12, TEXT_ALIGN_LEFT, {0.92, 0.92, 0.96, 1})
                    y = y - 17
                end
                y = y - 2
                if y < 52 then break end
            end

            local btnH = 20
            local gap = 8
            local buttonSpecs = {
                { id = "later", label = tostring(self._payload.laterLabel or "Later"), width = 82, primary = false },
            }
            if self._payload.showIgnore then
                buttonSpecs[#buttonSpecs + 1] = {
                    id = "ignore",
                    label = tostring(self._payload.ignoreLabel or "Ignore this version"),
                    width = 142,
                    primary = false,
                }
            end
            for _, action in ipairs(self._payload.actions or {}) do
                local label = tostring(action.label or action.id or "Action")
                buttonSpecs[#buttonSpecs + 1] = {
                    id = "action",
                    actionId = tostring(action.id or ""),
                    label = label,
                    width = math.max(82, math.min(132, #label * 7 + 22)),
                    primary = action.primary == true,
                }
            end
            local totalW = 0
            for _, spec in ipairs(buttonSpecs) do totalW = totalW + spec.width end
            totalW = totalW + math.max(0, #buttonSpecs - 1) * gap
            local x = math.floor((w - totalW) * 0.5)
            local btnY = 12
            self._buttons = { actions = {} }
            for _, spec in ipairs(buttonSpecs) do
                local rect = { x = x, y = btnY, w = spec.width, h = btnH }
                drawButton(font, rect, spec.label, spec.primary)
                if spec.id == "action" then
                    self._buttons.actions[#self._buttons.actions + 1] = { rect = rect, id = spec.actionId }
                else
                    self._buttons[spec.id] = rect
                end
                x = x + spec.width + gap
            end
            return
        end

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
                statusText(yalInfo and yalInfo.available, false, yalInfo and yalInfo.ignored),
                statusColor(yalInfo and yalInfo.available, false, yalInfo and yalInfo.ignored),
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
                statusText(ziboInfo and ziboInfo.available, ziboInfo and ziboInfo.skipped, ziboInfo and ziboInfo.ignored),
                statusColor(ziboInfo and ziboInfo.available, ziboInfo and ziboInfo.skipped, ziboInfo and ziboInfo.ignored),
                ziboRows
            )

            if mode == "maintenance" then
                drawText(
                    font,
                    padding,
                    68,
                    tostring(self._payload.vnavSummary or "VNAV Descent Tables: status unavailable"),
                    11,
                    TEXT_ALIGN_LEFT,
                    {0.78, 0.80, 0.86, 1}
                )
                local actionY = 40
                local actionGap = 8
                local actionSpecs = {
                    { id = "vnav", label = "VNAV Descent Tables...", width = 165 },
                    { id = "adjust_qv", label = "Adjust QVs + X-Camera after CG shift", width = 270 },
                    { id = "apply_qv0", label = "Apply QV0 to Default View", width = 180 },
                }
                local actionTotal = actionGap * (#actionSpecs - 1)
                for _, spec in ipairs(actionSpecs) do actionTotal = actionTotal + spec.width end
                local actionX = math.floor((w - actionTotal) * 0.5)
                self._buttons.maintenance = {}
                for _, spec in ipairs(actionSpecs) do
                    local rect = { x = actionX, y = actionY, w = spec.width, h = 20 }
                    drawButton(font, rect, spec.label, false)
                    self._buttons.maintenance[#self._buttons.maintenance + 1] = { rect = rect, id = spec.id }
                    actionX = actionX + spec.width + actionGap
                end
            end
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

        local btnH = 20
        local gap = 10
        local laterW = 82
        local ignoreW = 126
        local installW = 160
        local showIgnore = hasActionableUpdate(self._payload)
        local showInstall = yalInfo and (yalInfo.available or (mode == "maintenance" and yalInfo.detectedAvailable))
        local totalW = laterW
        if showIgnore then
            totalW = totalW + gap + ignoreW
        end
        if showInstall then
            totalW = totalW + gap + installW
        end
        local btnX = math.floor((w - totalW) * 0.5)
        local btnY = 12
        self._buttons.later = { x = btnX, y = btnY, w = laterW, h = btnH }
        local nextX = btnX + laterW + gap
        if showIgnore then
            self._buttons.ignore = { x = nextX, y = btnY, w = ignoreW, h = btnH }
            nextX = nextX + ignoreW + gap
        end
        if showInstall then
            self._buttons.install = { x = nextX, y = btnY, w = installW, h = btnH }
        end
        drawButton(font, self._buttons.later, laterLabel, not showInstall)
        if showIgnore then
            drawButton(font, self._buttons.ignore, tostring(self._payload.ignoreLabel or getIgnoreLabel(self._payload)), false)
        end
        if showInstall then
            drawButton(font, self._buttons.install, installLabel, true)
        end
    end

    function comp:onMouseDown(x, y, button)
        if not (button == MB_LEFT or button == 1) then
            return false
        end
        local function runCallback(callback)
            if callback then
                local ok, result = pcall(callback, self._payload)
                if not ok then
                    sasl.logWarning("Update popup callback failed: " .. tostring(result))
                elseif result == false then
                    return false
                end
            end
            return true
        end
        for _, action in ipairs((self._buttons and self._buttons.maintenance) or {}) do
            local rect = action.rect
            if rect and x >= rect.x and x <= (rect.x + rect.w) and y >= rect.y and y <= (rect.y + rect.h) then
                if self._onMaintenanceAction then
                    local ok, err = pcall(self._onMaintenanceAction, self._payload, action.id)
                    if not ok then
                        sasl.logWarning("Maintenance action callback failed: " .. tostring(err))
                    end
                end
                return true
            end
        end
        local btn = self._buttons and self._buttons.later or nil
        if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
            if runCallback(self._onAcknowledge) then
                self:clearPayload()
            end
            return true
        end
        btn = self._buttons and self._buttons.ignore or nil
        if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
            if runCallback(self._onIgnore) then
                self:clearPayload()
            end
            return true
        end
        btn = self._buttons and self._buttons.install or nil
        if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
            if runCallback(self._onInstall) then
                self:clearPayload()
            end
            return true
        end
        for _, action in ipairs((self._buttons and self._buttons.actions) or {}) do
            btn = action.rect
            if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
                local ok, result = true, nil
                if self._onAction then ok, result = pcall(self._onAction, self._payload, action.id) end
                if not ok then
                    sasl.logWarning("Update popup action callback failed: " .. tostring(result))
                elseif result ~= false then
                    self:clearPayload()
                end
                return true
            end
        end
        btn = self._buttons and self._buttons.cancel or nil
        if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
            if runCallback(self._onCancel) then
                self:clearPayload()
            end
            return true
        end
        btn = self._buttons and self._buttons.ok or nil
        if btn and x >= btn.x and x <= (btn.x + btn.w) and y >= btn.y and y <= (btn.y + btn.h) then
            if tostring(self._payload and self._payload.mode or "") == "confirm" then
                if runCallback(self._onConfirm) then
                    self:clearPayload()
                end
            else
                if runCallback(self._onAcknowledge) then
                    self:clearPayload()
                end
            end
            return true
        end
        local _, h = getSize()
        if y < (h - headerH) or not self._window or not self._window.getPosition then return false end
        local wx, wy, ww, hh = self._window:getPosition()
        self._drag = {
            startPointerX = wx + x,
            startPointerY = wy + y,
            winX = wx,
            winY = wy,
            winW = ww,
            winH = hh,
        }
        return true
    end

    function comp:onMouseMove(x, y)
        if not self._drag or not self._window then
            return false
        end
        local currentWinX, currentWinY = self._window:getPosition()
        local pointerX = currentWinX + x
        local pointerY = currentWinY + y
        local dx = pointerX - self._drag.startPointerX
        local dy = pointerY - self._drag.startPointerY
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
