local M = {}

local w = 520
local h = 160
local lineHeight = 16

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

function M.newComponent(ctx)
    local comp = {}
    comp.name = "yal_debug_overlay_component"
    comp.components = {}
    comp.position = createProperty({0, 0, w, h})
    comp.size = {w, h}
    comp.fbo = createProperty(false)
    comp.renderTarget = -1
    comp.fpsLimit = createProperty(-1)
    comp.frames = 0
    comp.noRenderSignal = createProperty(false)
    comp.clip = createProperty(false)
    comp.clipSize = createProperty({0, 0, 0, 0})
    comp.visible = createProperty(true)

    function comp:draw()
        local yal = ctx.yal
        local def = ctx.def
        local font = getSafeFont(def)
        local color = getTextColor(def)

        drawRectangle(0, 0, w, h, {0, 0, 0, 0.7})

        local lines = {}
        table.insert(lines, "YAL Debug Overlay (preview)")

        if yal and yal.loopStateTables then
            for i = 1, #yal.loopStateTables do
                local loop = yal.loopStateTables[i]
                if loop then
                    table.insert(lines, formatLoopLine(i, loop, def, yal))
                    local flags = {}
                    if loop.steprepeat then table.insert(flags, "repeat") end
                    if loop.procedureabort then table.insert(flags, "abort") end
                    if loop.procedureskipstep then table.insert(flags, "skipstep") end
                    if loop.procedurenotpossible then table.insert(flags, "notpossible") end
                    if loop.triggeredmanually then table.insert(flags, "manual") end
                    local flagStr = (#flags > 0) and table.concat(flags, ",") or "—"
                    local lastActive = loop.lastActiveTime or 0
                    local ago = ""
                    if lastActive > 0 then
                        ago = string.format(" | last %.0fs ago", os.time() - lastActive)
                    end
                    table.insert(lines, string.format("   flags: %s%s", flagStr, ago))

                    local vars = {}
                    table.insert(vars, string.format("lock=%s", tostring(loop.lock)))
                    table.insert(vars, string.format("stepindex=%s", tostring(loop.stepindex)))
                    table.insert(vars, string.format("current=%s", tostring(loop.currentStepName or "")))
                    table.insert(vars, string.format("last=%s", tostring(loop.lastStepName or "")))
                    table.insert(vars, string.format("skipConfirm=%s", tostring(loop.skipConfirmForStep or "")))
                    table.insert(lines, "   vars: " .. table.concat(vars, " | "))
                end
            end
        else
            table.insert(lines, "Loop state unavailable")
        end

        local ongoing = yal and yal.ongoingtaskstepindex or "-"
        table.insert(lines, string.format("Ongoing task step index: %s", tostring(ongoing)))

        local y = h - 22
        for _, line in ipairs(lines) do
            sasl.gl.drawTextI(font, 12, y, line, TEXT_ALIGN_LEFT, color)
            y = y - lineHeight
        end
    end

    function comp:update()
        -- no-op
    end

    return comp
end

function M.windowSize()
    return w, h
end

return M
