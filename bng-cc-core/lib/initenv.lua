return {
    run = function()
        local _require, _env = require("cc.require"), setmetatable({}, { __index = _ENV })
        require, package = _require.make(_env, "/")

        -- Add all possible module paths
        local paths = {
            "/bng/lib/?.lua",
            "/bng/lib/?/init.lua",
            "/bng/lib/?/?.lua",
            "/bng/programs/?.lua",
            "/bng/programs/?/?.lua",
            package.path -- Keep original paths as fallback
        }
        package.path = table.concat(paths, ";")

        term.clear()
        term.setCursorPos(1, 1)

        -- Debug output if needed
        -- print("Updated package.path: \n" .. package.path)
    end
}

