local M = {}

local ctx = {}
local overlayWindow
local overlayVisible = false

local w = 520
local h = 160
local lineHeight = 16

local function getSafeFont()
    if ctx.def and ctx.def.wFont then
        return ctx.def.wFont
    end
    return sasl.gl.loadFont("DejaVuSansMono.ttf")
end

local function getTextColor()
    if ctx.def and ctx.def.textColor then
        return ctx.def.textColor
    end
    return {1, 1, 1, 1}
end

local function formatLoopLine(i, loop)
    local def = ctx.def
    local yal = ctx.yal
    local lock = loop.lock or def.NOPROCEDURE
    local procName = "NOPROCEDURE"
    if lock ~= def.NOPROCEDURE and yal and yal.proceduretable and yal.proceduretable[lock] then
        procName = yal.proceduretable[lock].name or tostring(lock)
    end
    local stepName = loop.currentStepName or "-"
    local state = loop.stepindex or 0
    return string.format("Loop %d | %s | Step: %s (state:%s)", i, tostring(procName), tostring(stepName), tostring(state))
end

local function gatherLines()
    local lines = {}
    local yal = ctx.yal
    local def = ctx.def

    table.insert(lines, "YAL Debug Overlay (preview)")

    if yal and yal.loopStateTables then
        for i = 1, #yal.loopStateTables do
            local loop = yal.loopStateTables[i]
            if loop then
                table.insert(lines, formatLoopLine(i, loop))
            end
        end
    else
        table.insert(lines, "Loop state unavailable")
    end

    local ongoing = yal and yal.ongoingtaskstepindex or "-"
    table.insert(lines, string.format("Ongoing task step index: %s", tostring(ongoing)))

    return lines
end

local function drawOverlay()
    if not overlayWindow or not overlayVisible then return end

    drawRectangle(0, 0, w, h, {0, 0, 0, 0.7})
    local font = getSafeFont()
    local color = getTextColor()

    local lines = gatherLines()
    local y = h - 22
    for _, line in ipairs(lines) do
        sasl.gl.drawTextI(font, 12, y, line, TEXT_ALIGN_LEFT, color)
        y = y - lineHeight
    end
end

local function toggleOverlay()
    overlayVisible = not overlayVisible
    if overlayWindow then
        overlayWindow:setIsVisible(overlayVisible)
    end
end

function M.init(initCtx)
    ctx = initCtx or {}

    local xRoot, yRoot, wRoot, hRoot = sasl.windows.getMonitorBoundsOS(0)
    local posX = xRoot + wRoot - w - 30
    local posY = yRoot + hRoot - h - 80

    overlayWindow = contextWindow {
        name = "YAL Debug",
        position = { posX, posY, w, h },
        visible = false,
        noResize = true,
        vrAuto = true,
        noBackground = true,
        noDecore = true,
        proportional = true,
        drawCallback = drawOverlay
    }

    local cmdPath = ctx.def and (ctx.def.APPNAMEPREFIX .. "/toggle_debug_overlay") or "yal/toggle_debug_overlay"
    local cmd = sasl.createCommand(cmdPath, "Toggle YAL Debug Overlay")
    sasl.registerCommandHandler(cmd, 0, function(phase)
        if phase == SASL_COMMAND_BEGIN then
            toggleOverlay()
        end
        return 0
    end)

    if ctx.yal and ctx.yal.menu_main then
        M.menu_item = sasl.appendMenuItem(ctx.yal.menu_main, "Toggle Debug Overlay", toggleOverlay)
    end

    M.toggle = toggleOverlay
    M.show = function()
        overlayVisible = true
        if overlayWindow then overlayWindow:setIsVisible(true) end
    end
    M.hide = function()
        overlayVisible = false
        if overlayWindow then overlayWindow:setIsVisible(false) end
    end
end

return M
