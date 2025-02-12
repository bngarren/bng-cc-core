-- bng-cc-core by bngarren
-- MIT License

-- will only be present in built distro
local version = require('version')

local L = {
    _VERSION = version.VERSION,
    _COMMIT = version.COMMIT,
    _BRANCH = version.BRANCH,
    _BUILD_DATE = version.BUILD_DATE,

    -- -- Expose modules directly
    -- initenv = require("initenv"),
    -- log = require("log"),
    -- util = require("util"),
    -- ppm = require("ppm"),
}

L.initenv = require("initenv")
L.log = require("log")
L.util = require("util")
L.ppm = require("ppm")({log = L.log})

setmetatable(L, {
    __index = function(t, k)
        error(string.format("Module '%s' not found in bng-cc-core", k))
    end
})

local args = {...}
if #args < 1 or type(package.loaded['bng-cc-core']) ~= 'table' then
    print(string.format('bng-cc-core %s (commit: %s, branch: %s)', 
        L._VERSION, 
        L._COMMIT, 
        L._BRANCH
    ))
    print('Use require() to load this module')
end

return L