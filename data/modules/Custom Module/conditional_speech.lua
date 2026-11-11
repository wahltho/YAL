-- Conditional speech owns validity, not flight-phase detection or repetition.
local M = {}

function M.new(io)
    local state = { records = {}, modes = {}, cancellations = {}, stopped = false }

    function state:valid(record)
        if self.stopped or self.records[record.key] ~= record then return false end
        local ok, pending = pcall(record.pending)
        return ok and pending == true
    end

    function state:cancel(key)
        local active = self.records[key] ~= nil or self.cancellations[key] ~= nil
        self.records[key] = nil
        io.remove(key)
        local mode = self.modes[key]
        if active and mode then
            self.cancellations[key] = mode
            if io.cancel(key, mode) then self.cancellations[key] = nil end
        end
    end

    function state:cancelWhere(matches)
        local keys = {}
        for key, record in pairs(self.records) do
            if matches(record) then keys[#keys + 1] = key end
        end
        for _, key in ipairs(keys) do self:cancel(key) end
    end

    function state:clear()
        self:cancelWhere(function() return true end)
    end

    function state:offer(key, text, pending, entryType, priority, owner)
        if self.stopped or type(key) ~= "string" or key == ""
            or type(text) ~= "string" or text == "" or type(pending) ~= "function" then
            return false
        end
        local ok, relevant = pcall(pending)
        if not ok or relevant ~= true then self:cancel(key); return false end
        -- Cancellation wins before a replacement enters any local mailbox.
        if self.records[key] then self:cancel(key) end
        if self.cancellations[key] then return false end
        self.modes[key] = self.modes[key] or io.mode()
        local record = { key = key, pending = pending, mode = self.modes[key], priority = priority, owner = owner }
        self.records[key] = record
        io.enqueue(entryType, text, key, record)
        return true
    end

    function state:sweep()
        for key, mode in pairs(self.cancellations) do
            if io.cancel(key, mode) then self.cancellations[key] = nil end
        end
        local invalid = {}
        for key, record in pairs(self.records) do
            if not self:valid(record) then invalid[#invalid + 1] = key end
        end
        for _, key in ipairs(invalid) do self:cancel(key) end
    end

    function state:dispatch(record, text, priority)
        -- A removed generation must not cancel a newer offer of the same key.
        if self.records[record.key] ~= record then io.remove(record.key, record); return false end
        if not self:valid(record) then self:cancel(record.key); return false end
        -- Remove the local copy before the synchronous mailbox commit; never wait for TTS.
        io.remove(record.key)
        record.external = true
        local accepted, reason = io.send(text, record.priority or priority, record.key, record.mode)
        record.accepted, record.result = accepted == true, reason
        return accepted, reason
    end

    function state:shutdown()
        self.stopped = true
        self:clear()
        self:sweep()
    end

    return state
end

function M.ownerWithin(owner, ancestor)
    local seen = {}
    while owner and not seen[owner] do
        if owner == ancestor then return true end
        seen[owner] = true
        owner = owner.parent
    end
    return false
end

function M.ownerCancelled(owner)
    if not owner then return false end
    if owner.cancelled or not owner.parent then return owner.cancelled == true end
    local seen = {}
    while owner and not seen[owner] do
        if owner.cancelled then return true end
        seen[owner] = true
        owner = owner.parent
    end
    return false
end

function M.attach(P, def, helpers, settings)
    local function enabled(index)
        local values = settings and settings.appSettings or P.configvalues or {}
        return values[index] == def.ON
    end

    function P.conditionalSpeechModeAllowed(mode)
        if mode == "always" then return true end
        local voice = enabled(def.CONFIGVOICEREADBACK) or enabled(def.CONFIGVOICEADVICEONLY)
        if mode == "voice" then return voice end
        if mode == "advice" then return enabled(def.CONFIGVOICEADVICEONLY) end
        return voice and (enabled(def.CONFIGAUTOFUNCTIONS) or enabled(def.CONFIGVOICEADVICEONLY))
    end

    function P.removeConditionalSpeechEntries(key, record)
        for i = #(P.commandtable or {}), 1, -1 do
            local entry = P.commandtable[i]
            if entry.conditional and entry[3] == key and (not record or entry.conditional == record) then
                table.remove(P.commandtable, i)
            end
        end
    end

    P.conditionalSpeech = M.new({
        remove = P.removeConditionalSpeechEntries,
        mode = helpers.conditionalSpeakStringMode,
        cancel = function(key, mode)
            if mode == "managed" then return helpers.clearSpeakStringSink(key, 1) end
            -- Legacy/XPLM cannot recall speech after backend handoff.
            helpers.clearSpeakStringSink(key, 0)
            return true
        end,
        send = helpers.speakConditional,
        enqueue = function(entryType, text, key, record)
            P.commandtableentry(entryType or def.TEXT, text, key, nil, record)
        end
    })

    P.procedureSpeechOwners = P.procedureSpeechOwners or {}

    function P.cancelProcedureSpeechOwner(owner, descendants, invalidate)
        if not owner then return end
        if invalidate then owner.cancelled = true end
        P.conditionalSpeech:cancelWhere(function(record)
            return record.owner == owner or (descendants and M.ownerWithin(record.owner, owner))
        end)
    end

    function P.getProcedureSpeechOwner(loop)
        if not loop or not loop.lock or loop.lock == def.NOPROCEDURE then return nil end
        local owner = P.procedureSpeechOwners[loop]
        if owner and owner.procId == loop.lock and owner.epoch == loop.speechEpoch then return owner end
        -- Loop-slot reuse must not cancel confirmations from a completed run.
        -- Existing records retain that run's owner, including its parent link.
        owner = { loop = loop, procId = loop.lock, epoch = loop.speechEpoch }
        P.procedureSpeechOwners[loop] = owner
        local parent = P.loopStateTables and P.loopStateTables[loop.parentLoopIndex]
        if parent and parent ~= loop and parent.lock == loop.parentProcId then
            owner.parent = P.getProcedureSpeechOwner(parent)
        end
        return owner
    end

    function P.clearProcedureQueuedSpeech(loop, scope)
        local owner = P.getProcedureSpeechOwner(loop)
        if not owner then return end
        if scope == "family" then
            local seen = {}
            while owner.parent and not seen[owner.parent] do
                seen[owner] = true
                owner = owner.parent
            end
        end
        -- Skip-step removes the current backlog, but does not stop the next step.
        P.cancelProcedureSpeechOwner(owner, scope ~= "step", scope ~= "step")
    end

    function P.queueConditionalSpeech(key, text, pending, mode, entryType, priority, owner)
        if P.speechProbeActive then return false end
        owner = owner or (P.procedureSpeechContext and P.procedureSpeechContext.owner)
        return P.conditionalSpeech:offer(key, text, function()
            return not M.ownerCancelled(owner) and P.conditionalSpeechModeAllowed(mode) and pending() == true
        end, entryType, priority, owner)
    end

    function P.queueProcedureContent(entryType, text, key)
        local context = P.procedureSpeechContext
        if not context then return false end
        local owner, loop = context.owner, context.loop
        if not key then
            local stepName = loop.currentStepName or "start"
            context.slots[stepName] = (context.slots[stepName] or 0) + 1
            key = P.procedureSpeechKey(owner.procId, stepName, "text" .. tostring(context.slots[stepName]))
        end
        return P.queueConditionalSpeech(key, text, function()
            -- Successful confirmations survive ordinary advance and completion.
            -- Only cancellation, not a later step/loop reset, invalidates them.
            local current = P.procedureSpeechOwners[loop] == owner
                and loop.lock == owner.procId and loop.speechEpoch == owner.epoch
            return not current or not (loop.procedureabort or loop.procedureskipped or loop.procedureskipstep)
        end, "voice", entryType, nil, owner)
    end

    function P.speakConditionalNow(key, text, pending, priority)
        if P.queueConditionalSpeech(key, text, pending, "always", def.TEXT, priority) then
            return P.conditionalSpeech:dispatch(P.conditionalSpeech.records[key], text, priority)
        end
        return false
    end

    function P.refreshConditionalSpeech()
        P.conditionalSpeech:sweep()
    end

    function P.shutdownConditionalSpeech()
        P.conditionalSpeech:shutdown()
    end

    function P.procedureSpeechPending(loop, stepName, pending, adviceOnly, procedureWide)
        local procId, epoch = loop.lock, loop.speechEpoch
        local procData = P.proceduretable[procId]
        local selection = P.procedureSpeechSelection()
        return function()
            if loop.lock ~= procId or loop.speechEpoch ~= epoch or loop.procedureabort
                or loop.procedureskipped or loop.procedureskipstep or loop.procedurenotpossible then return false end
            if not procedureWide and loop.currentStepName ~= stepName then return false end
            if P.procedureSpeechSelection() ~= selection then return false end
            if not P.conditionalSpeechModeAllowed(adviceOnly and "advice" or "voice") then return false end
            local ground = get(P.airgroundsensor) == def.ON
            if not procData or (procData.allowedState == def.GROUNDONLY and not ground)
                or (procData.allowedState == def.AIRONLY and ground) then return false end
            for _, transition in ipairs(procData.transitionConditions or {}) do
                if transition.condition() then return false end
            end
            return pending() == true
        end
    end

    function P.procedureSpeechSelection()
        local values = {}
        for _, name in ipairs({ "depicao", "deprwy", "fmsselectedsid", "desicao", "desrwy", "fmsselectedstar", "fmsselectedapp" }) do
            local ref = P[name]
            values[#values + 1] = ref and isProperty(ref) and tostring(get(ref) or "") or ""
        end
        return table.concat(values, "|")
    end

    function P.probeProcedureStep(loop, step, procData, expectedText)
        -- Checks with latch/log/speech side effects receive an isolated loop.
        -- Explicit advicePending overrides cover commands and TA/TL acceptance.
        local copy = {}
        for k, value in pairs(loop) do copy[k] = value end
        copy.speechProbe = true
        local previous = P.speechProbeActive
        P.speechProbeActive = true
        local ok, pending = pcall(function()
            if step.skipIf and step.skipIf(copy, procData) then return false end
            local unmet
            if step.advicePending then unmet = step.advicePending(copy, procData) == true
            else unmet = step.check and not step.check(copy, procData) or false end
            if not unmet then return false end
            if expectedText == nil then return true end
            local current = type(step.advice) == "function" and step.advice(copy, procData) or step.advice
            return current == expectedText
        end)
        P.speechProbeActive = previous
        return ok and pending == true
    end

    function P.queueProcedureAdvice(loop, procId, stepName, step, text)
        local procData = P.proceduretable[procId]
        local pending = P.procedureSpeechPending(loop, stepName, function()
            return P.probeProcedureStep(loop, step, procData, text)
        end, true)
        return P.queueConditionalSpeech(P.procedureSpeechKey(procId, stepName, "advice"), text, pending,
            "advice", nil, nil, P.getProcedureSpeechOwner(loop))
    end

    function P.queueProcedureInstruction(loop, kind, text, pending, procedureWide)
        if P.speechProbeActive then return false end
        local stepName = loop.currentStepName
        return P.queueConditionalSpeech(P.procedureSpeechKey(loop.lock, stepName, kind), text,
            P.procedureSpeechPending(loop, stepName, pending, false, procedureWide), "voice", nil, nil,
            P.getProcedureSpeechOwner(loop))
    end

    -- All text emitted synchronously by procedure checks/actions shares the
    -- existing run identity. Readbacks and background callouts run outside it.
    if P.runProcedureLoop then
        local runProcedureLoop = P.runProcedureLoop
        function P.runProcedureLoop(loopIndex)
            local previous = P.procedureSpeechContext
            local loop = P.loopStateTables[loopIndex]
            local owner = P.getProcedureSpeechOwner(loop)
            P.procedureSpeechContext = owner and { owner = owner, loop = loop, slots = {} } or nil
            local ok, result = pcall(runProcedureLoop, loopIndex)
            P.procedureSpeechContext = previous
            if not ok then error(result, 0) end
            return result
        end
    end

    require("conditional_advice").attach(P, def, helpers, settings)
end

return M
