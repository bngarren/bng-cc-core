-- bng-cc-core by bngarren
-- MIT License

-- will only be present in built distro
local version = require('version')

-- DI class
local DI = {}
DI.__index = DI

function DI.new()
    local self = setmetatable({
        _deps = {},
        _current_dep = nil
    }, DI)
    return self
end

function DI:with(deps)
    if type(deps) ~= "table" then error("deps must be a table") end
    for name, value in pairs(deps) do
        self._deps[name] = { value = value }
    end
    return self
end

function DI:transform(fn)
    if not self._current_dep then
        -- Apply transform to last added dep if no current one
        local last_dep_name = next(self._deps, nil)
        if last_dep_name then
            self._deps[last_dep_name].transform = fn
        end
    else
        self._deps[self._current_dep].transform = fn
    end
    return self
end

function DI:for_dep(name)
    if not self._deps[name] then
        error(string.format("Dependency %s not found", name))
    end
    self._current_dep = name
    return self
end

function DI:build()
    -- Create deps object with transformations applied
    local result = {}
    for name, config in pairs(self._deps) do
        local value = config.value
        if value == nil then
            error(string.format("Missing required dependency: %s", name))
        end
        if config.transform then
            value = config.transform(value)
        end
        result[name] = value
    end
    return result
end

local L = {
    _VERSION = version.VERSION,
    _COMMIT = version.COMMIT,
    _BRANCH = version.BRANCH,
    _BUILD_DATE = version.BUILD_DATE,
}

L.initenv = require("initenv")
L.log = require("log")
L.util = require("util")
L.ppm = require("ppm")(DI.new()
    :with({ log = L.log })
    :transform(function(m) return m.instance() end)
    :build())

setmetatable(L, {
    __index = function(t, k)
        error(string.format("Module '%s' not found in bng-cc-core", k))
    end
})

local args = { ... }
if #args < 1 or type(package.loaded['bng-cc-core']) ~= 'table' then
    print(string.format('bng-cc-core %s (commit: %s, branch: %s)',
        L._VERSION,
        L._COMMIT,
        L._BRANCH
    ))
    print('Use require() to load this module')
end

return L
