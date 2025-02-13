-- error.lua
-- Error and Crash handling

local M = {}

local crash = {}
crash.app = "unknown"
crash.version = "v0.0.0"
crash.error = ""

local function init(deps)
    local log = deps.log

    function M.crash_set_env(application, version)
        crash.app = application
        crash.version = version
    end

    function M.crash_handler(error)
        crash.error = error
        if error == "Terminated" then
            crash.error = nil
            return
        end
        log:fatal(error)
        log:info(debug.traceback("----- begin debug trace -----", 2))
        log:info("----- end debug trace -----")
    end

    function M.crash_exit()
        if crash.error then
            print("fatal error occured in main application:")
            error(crash.error, 0)
        end
    end

    return M
end

return init
