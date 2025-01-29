return {
    -- initialize booted environment
    init_env = function()
        local _require, _env = require("cc.require"), setmetatable({}, { __index = _ENV })
        require, package = _require.make(_env, "/")

        -- Add custom module paths
        local module_folder = "/bng/common/?.lua;/bng/programs/?.lua"
        package.path = module_folder .. ";" .. package.path

        term.clear(); term.setCursorPos(1, 1)

        print("Updated package.path: \n" .. package.path)
    end
}
