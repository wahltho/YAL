local M = {}

local defaultW = 720
local defaultH = 320
local lineHeight = 16
local headerH = 22
local controlRowH = lineHeight + 6
local controlAreaH = controlRowH * 3 + 6

local function getSafeFont(def)
    if def and def.wFont then
        return def.wFont
    end
    return sasl.gl.loadFont("DejaVuSansMono.ttf")
end

local function getTextColor(def)
    if def and def.textColor then
        return def.textColor
    end
    return {1, 1, 1, 1}
end

local function formatLoopLine(i, loop, def, yal)
    local lock = loop.lock or def.NOPROCEDURE
    local procName = "NOPROCEDURE"
    if lock ~= def.NOPROCEDURE and yal and yal.proceduretable and yal.proceduretable[lock] then
        procName = yal.proceduretable[lock].name or tostring(lock)
    end
    local stepName = loop.currentStepName or "-"
    local state = loop.stepindex or 0
    return string.format("Loop %d | %s | Step: %s (state:%s)", i, tostring(procName), tostring(stepName), tostring(state))
end

local function collectLoopExtras(loop)
    local reserved = {
        lock = true,
        stepindex = true,
        currentStepName = true,
        steprepeat = true,
        lastActiveTime = true,
        procedureabort = true,
        procedureskipstep = true,
        procedurenotpossible = true,
        triggeredmanually = true,
        setonabort = true,
        lastStepName = true,
        skipConfirmForStep = true
    }
    local parts = {}
    for k, v in pairs(loop) do
        if not reserved[k] then
            local t = type(v)
            if t == "number" or t == "string" or t == "boolean" then
                parts[#parts + 1] = string.format("%s=%s", tostring(k), tostring(v))
            end
        end
    end
    table.sort(parts)
    return parts
end

local function firstAvailable(loop, keys)
    for _, k in ipairs(keys) do
        local v = loop[k]
        if v ~= nil then return v end
    end
    return nil
end

function M.newComponent(ctx)
    local comp = {}
    comp.name = "yal_debug_overlay_component"
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
    comp._buttons = {}

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

    local function addButton(tbl, x, y, w_, h_, label, action, loopIdx)
        tbl[#tbl + 1] = { x = x, y = y, w = w_, h = h_, label = label, action = action, loop = loopIdx }
    end

    function comp:draw()
        local w, h = getSize()
        local yal = ctx.yal
        local def = ctx.def
        local font = getSafeFont(def)
        local color = {0.9, 0.9, 0.95, 1}

        drawRectangle(0, 0, w, h, {0, 0, 0, 0.75})
        drawRectangle(0, h - headerH, w, headerH, {0.12, 0.12, 0.12, 0.95})

        local lines = {}
        comp._buttons = {}
        local activeLoops = 0

        if yal and yal.loopStateTables then
            -- Controls area (top, below header)
            local btnW = 70
            local btnH = controlRowH - 6
            for i = 1, math.min(3, #yal.loopStateTables) do
                local loop = yal.loopStateTables[i]
                local rowY = h - headerH - 4 - (i - 1) * controlRowH - btnH
                local rowX = 10
                local status = (loop and loop.lock ~= def.NOPROCEDURE) and "RUN" or "IDLE"
                local paused = loop and loop.debugPaused
                local statusLabel = string.format("L%d %s", i, status)
                sasl.gl.drawTextI(font, rowX, rowY + 2, statusLabel, TEXT_ALIGN_LEFT, color)
                if paused then
                    sasl.gl.drawTextI(font, rowX + 70, rowY + 2, "(Paused)", TEXT_ALIGN_LEFT, {1, 0.7, 0.3, 1})
                end
                rowX = rowX + 140
                addButton(comp._buttons, rowX, rowY, btnW, btnH, paused and "Resume" or "Pause", "pause", i)
                rowX = rowX + btnW + 6
                addButton(comp._buttons, rowX, rowY, btnW, btnH, "Step +", "step", i)
                rowX = rowX + btnW + 6
                addButton(comp._buttons, rowX, rowY, btnW, btnH, "BP cur", "bp_cur", i)
                rowX = rowX + btnW + 6
                addButton(comp._buttons, rowX, rowY, btnW, btnH, "BP clear", "bp_clear", i)
            end
            -- Draw buttons
            for _, b in ipairs(comp._buttons) do
                drawRectangle(b.x, b.y, b.w, b.h, {0.2, 0.2, 0.2, 0.9})
                sasl.gl.drawFrame(b.x, b.y, b.w, b.h, {0.6, 0.6, 0.6, 1})
                sasl.gl.drawTextI(font, b.x + 4, b.y + 2, b.label, TEXT_ALIGN_LEFT, color)
            end

            for i = 1, #yal.loopStateTables do
                local loop = yal.loopStateTables[i]
                if loop then
                    local flags = {}
                    if loop.steprepeat then table.insert(flags, "repeat") end
                    if loop.procedureabort then table.insert(flags, "abort") end
                    if loop.procedureskipstep then table.insert(flags, "skipstep") end
                    if loop.procedurenotpossible then table.insert(flags, "notpossible") end
                    if loop.triggeredmanually then table.insert(flags, "manual") end
                    local flagStr = (#flags > 0) and table.concat(flags, ",") or "—"
                    local guardRemaining = firstAvailable(loop, {"guardRemaining", "guardTimer", "guardRest", "guard"})
                    local waitReason = firstAvailable(loop, {"waitReason", "wait_status", "waitReasonText"})
                    local guardStr = guardRemaining and string.format("%.1fs", tonumber(guardRemaining) or guardRemaining) or "—"
                    local waitStr = waitReason and tostring(waitReason) or "—"
                    local status = loop.lock ~= def.NOPROCEDURE and "RUN" or "IDLE"
                    if status == "RUN" then activeLoops = activeLoops + 1 end
                    table.insert(lines, string.format("Loop %-2d %-5s %-20s Guard:%-7s Wait:%s%s", i, status, tostring(loop.currentStepName or "-"), guardStr, waitStr, loop.debugPaused and " [PAUSED]" or ""))

                    local vars = {}
                    table.insert(vars, string.format("lock=%s", tostring(loop.lock)))
                    table.insert(vars, string.format("idx=%s", tostring(loop.stepindex)))
                    table.insert(vars, string.format("cur=%s", tostring(loop.currentStepName or "")))
                    table.insert(vars, string.format("last=%s", tostring(loop.lastStepName or "")))
                    table.insert(vars, string.format("skipC=%s", tostring(loop.skipConfirmForStep or "")))
                    table.insert(vars, string.format("flags=%s", flagStr))
                    table.insert(lines, "   " .. table.concat(vars, " | "))

                    local fromStep = firstAvailable(loop, {"lastTransitionFrom", "lastStepName"})
                    local toStep = firstAvailable(loop, {"lastTransitionTo", "currentStepName"})
                    local reason = firstAvailable(loop, {"lastTransitionReason"})
                    local transitionStr = string.format("   transition: %s -> %s", tostring(fromStep or "?"), tostring(toStep or "?"))
                    if reason then
                        transitionStr = transitionStr .. string.format(" (%s)", tostring(reason))
                    end
                    table.insert(lines, transitionStr)

                    local extras = collectLoopExtras(loop)
                    if #extras > 0 then
                        table.insert(lines, "   data: " .. table.concat(extras, " | "))
                    end
                end
            end
        else
            table.insert(lines, "Loop state unavailable")
        end

        local ongoing = yal and yal.ongoingtaskstepindex or "-"
        table.insert(lines, string.format("Ongoing task step index: %s", tostring(ongoing)))

        -- Header with status and close
        local headerStatus = string.format("YAL Debug Overlay | Loops RUN:%d", activeLoops)
        sasl.gl.drawTextI(font, 10, h - headerH + 4, headerStatus, TEXT_ALIGN_LEFT, color)
        sasl.gl.drawTextI(font, w - 18, h - headerH + 4, "X", TEXT_ALIGN_LEFT, color)

        local scrollHeight = h - headerH - controlAreaH - 16
        local availableLines = math.max(1, math.floor(scrollHeight / lineHeight))
        local maxOffset = math.max(0, #lines - availableLines)
        comp._lastMaxOffset = maxOffset
        if comp.scrollOffset > maxOffset then comp.scrollOffset = maxOffset end
        if comp.scrollOffset < 0 then comp.scrollOffset = 0 end

        local startIdx = 1 + comp.scrollOffset
        local endIdx = math.min(#lines, startIdx + availableLines - 1)
        local y = h - headerH - controlAreaH - 12
        for idx = startIdx, endIdx do
            sasl.gl.drawTextI(font, 12, y, lines[idx], TEXT_ALIGN_LEFT, color)
            y = y - lineHeight
        end

        -- Draw scrollbar if needed
        if #lines > availableLines then
            local trackHeight = scrollHeight
            local thumbHeight = math.max(12, trackHeight * (availableLines / #lines))
            local travel = trackHeight - thumbHeight
            local rel = (maxOffset == 0) and 0 or (comp.scrollOffset / maxOffset)
            local thumbY = (h - headerH - controlAreaH - 12) - (rel * travel) - thumbHeight
            local trackX = w - 10
            drawRectangle(trackX, (h - headerH - controlAreaH - 12) - trackHeight, 6, trackHeight, {0.3, 0.3, 0.3, 0.5})
            drawRectangle(trackX, thumbY, 6, thumbHeight, {0.8, 0.8, 0.8, 0.9})
        end
    end

    function comp:onMouseDown(x, y, button)
        local wCur, hCur = getSize()
        if button == MB_LEFT then
            -- Buttons
            for _, b in ipairs(self._buttons or {}) do
                if x >= b.x and x <= (b.x + b.w) and y >= b.y and y <= (b.y + b.h) then
                    self:handleButton(b)
                    return true
                end
            end
            -- Close
            if y >= (hCur - headerH) and x >= (wCur - 30) then
                if self._window then
                    self._window:setIsVisible(false)
                end
                return true
            end
            -- scrollbar drag
            local trackX = wCur - 10
            local trackHeight = hCur - headerH - controlAreaH - 16
            local availableLines = math.max(1, math.floor(trackHeight / lineHeight))
            local maxOffset = math.max(0, self._lastMaxOffset or 0)
            if maxOffset > 0 and x >= trackX and x <= (trackX + 6) and y >= (hCur - headerH - controlAreaH - 12 - trackHeight) and y <= (hCur - headerH - controlAreaH - 12) then
                self.scrollDrag = {
                    startY = y,
                    startOffset = self.scrollOffset,
                    trackHeight = trackHeight,
                    thumbHeight = math.max(12, trackHeight * (availableLines / (availableLines + maxOffset))),
                    maxOffset = maxOffset
                }
                return true
            end
        end
        return false
    end

    function comp:onMouseWheel(_, _, _, clicks)
        if clicks == nil then return false end
        local delta = -clicks -- wheel up should scroll up
        comp.scrollOffset = comp.scrollOffset + delta
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
            return true
        end
        return false
    end

    function comp:handleButton(btn)
        if not ctx or not ctx.yal or not ctx.yal.loopStateTables then return end
        local loop = ctx.yal.loopStateTables[btn.loop]
        if not loop then return end
        loop.debugBreakpoints = loop.debugBreakpoints or {}
        if btn.action == "pause" then
            loop.debugPaused = not loop.debugPaused
        elseif btn.action == "step" then
            loop.debugPaused = true
            loop.debugStepOnce = true
        elseif btn.action == "bp_cur" then
            local name = loop.currentStepName
            if type(name) == "string" and name ~= "" then
                loop.debugBreakpoints[name] = not loop.debugBreakpoints[name]
            end
        elseif btn.action == "bp_clear" then
            loop.debugBreakpoints = {}
        end
    end

    function comp:update()
        -- no-op
    end

    return comp
end

function M.windowSize()
    return defaultW, defaultH
end

return M
