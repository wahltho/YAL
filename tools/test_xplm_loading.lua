package.path = "data/modules/Custom Module/?.lua;" .. package.path

function globalProperty(name) return name end

local cases = {
    {
        os = "OSX",
        root = "/Volumes/Macintosh HD 2/X-Plane 12",
        library = "/Volumes/Macintosh HD 2/X-Plane 12/Resources/plugins/XPLM.framework/XPLM"
    },
    {
        os = "Linux",
        root = "/home/pilot/X-Plane 12",
        library = "/home/pilot/X-Plane 12/Resources/plugins/XPLM_64.so"
    },
    {
        os = "Windows",
        root = "D:\\X-Plane 12",
        library = "XPLM_64"
    }
}

for _, case in ipairs(cases) do
    sasl = {
        getOS = function() return case.os end,
        getProjectName = function() return "YAL" end,
        getXPlanePath = function() return case.root end,
        getProjectPath = function() return "/tmp/YAL" end,
        getXPVersion = function() return 124412 end,
        gl = { loadFont = function() return 1 end }
    }

    local loads, spoken = 0, {}
    package.loaded.ffi = {
        os = case.os,
        load = function(path)
            if case.os ~= "Windows" then
                assert(path:sub(1, 1) == "/",
                    "relative path not allowed in hardened program: " .. path)
            end
            assert(path == case.library, case.os .. " must load XPLM from the simulator path")
            loads = loads + 1
            return {
                XPLMSpeakString = function(buffer)
                    assert(buffer.size == #buffer.text + 1, "direct speech retains its NUL byte")
                    spoken[#spoken + 1] = buffer.text
                end
            }
        end,
        cdef = function() end,
        new = function(_, size) return { size = size } end,
        copy = function(buffer, text) buffer.text = text end
    }
    package.loaded.definitions = nil
    package.loaded.helpers = nil

    local realHelpers = require("helpers")
    assert(loads == 1, case.os .. " loads XPLM exactly once")
    realHelpers.speak("QNH checked Standard")
    assert(#spoken == 1 and spoken[1] == "QNH checked Standard",
        case.os .. " preserves direct XPLMSpeakString without a Zibo sink")
end

print("test_xplm_loading: all checks passed")
