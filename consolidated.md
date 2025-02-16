## src/init.lua

```lua
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
    if type(deps) ~= "table" then
        error("deps must be a table")
    end
    for name, value in pairs(deps) do
        if type(name) ~= "string" then
            error("dependency name must be a string")
        end
        if value == nil then
            error(string.format("dependency '%s' cannot be nil", name))
        end
        self._deps[name] = { value = value }
    end
    return self
end

function DI:transform(fn)
    if not self._current_dep then
        error("No dependency selected. Use for_dep() first")
    end
    self._deps[self._current_dep].transform = fn
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

-- Explicitly specify public modules and inject dependencies

L.util = require("util")()

-- Build logger singleton
L.log = require("log")(DI.new()
    :with({ util = L.util })
    :build())
L.log.new({
    level = "info",
    outputs = { term = true, file = true },
    file = {
        write_banner = false
    }
})


L.initenv = require("initenv")
L.error = require("error")(DI.new()
    :with({ log = L.log })
    :for_dep("log")
    :transform(function(m) return m.get() end)
    :build())
L.ppm = require("ppm")(DI.new()
    :with({ log = L.log })
    :for_dep("log")
    :transform(function(m) return m.get() end)
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
```


## src/ppm.lua

```lua
-- ppm.lua
-- Simple Peripheral Manager

---@class PPM
local M = {}

---@type table<string, any>
local peripherals = {}

local function init(deps)

    local log = deps.log:child({module="ppm"})

    -- [[ Private methods ]]

    -- Wrap a peripheral safely
    ---@private
    ---@return any?: The wrapped peripheral or nil
    local function safe_wrap(side)
        if peripheral.isPresent(side) then
            return peripheral.wrap(side)
        else
            return nil
        end
    end

    -- [[ Public API ]]

    -- Mount all peripherals
    function M.mount_all()
        peripherals = {} -- Clear existing mounts
        for _, side in ipairs(peripheral.getNames()) do
            peripherals[side] = safe_wrap(side)
            log:success("PPM: Mounted %s on %s", peripheral.getType(side), side)
        end
    end

    -- Get a peripheral
    function M.get(side)
        if peripherals[side] then
            return peripherals[side]
        else
            peripherals[side] = safe_wrap(side)
            return peripherals[side]
        end
    end

    ---Returns the monitor if the side contains a valid monitor, otherwise returns false with an error message
    ---@param side string
    ---@return boolean
    ---@return string|any
    function M.validate_monitor(side)
        if not peripheral.isPresent(side) then
            return false, "peripheral not present on " .. side
        end
    
        local type = peripheral.getType(side)
        if type ~= "monitor" then
            return false, "not a monitor, found: " .. type
        end
    
        local mon = peripheral.wrap(side)
        if not mon or type(mon.setTextScale) ~= "function" then
            return false, "failed function check"
        end
    
        return true, mon
    end

    -- Handle peripheral detach event
    function M.handle_unmount(side)
        if peripherals[side] then
            print("PPM: Unmounted " .. side)
            peripherals[side] = nil
        end
    end

    return M
end

return init
```


## src/initenv.lua

```lua
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

```


## src/error.lua

```lua
-- error.lua
-- Error and Crash handling

local M = {}

local crash = {}
crash.app = "unknown"
crash.error = ""

local function init(deps)
    local log = deps.log

    function M.crash_set_env(application)
        crash.app = application
    end

    function M.crash_handler(error)
        crash.error = error
        if error == "Terminated" then
            crash.error = nil
            return
        end
        log:fatal(error)
        log:info("---------------------------")
        log:info("App: %s", crash.app)
        log:info(debug.traceback("----- begin debug trace -----", 2))
        log:info("----- end debug trace -----")
    end

    function M.crash_exit()
        if crash.error then
            print("fatal error occured in main application:")
            error(crash.error, 0)
        end
        log:close()
    end

    return M
end

return init
```


## src/log.lua

```lua
--- @class Logger
local Logger = {}
Logger.__index = Logger

---@type Logger|nil
local _instance = nil

local DEFAULT_CONFIG = {
    --- Name of the source file/program this log is logging
    --- @type string?
    source = nil,
    --- Log level: all log() calls at this level and above will be logged
    --- @type LogLevel
    level = "info",
    --- If true, will abbreviate the log level, e.g. [D] instead of [DEBUG]
    --- @type boolean
    abbreviate_level = true,
    --- If true, will use colorized output to terminal and monitors
    --- @type boolean
    colors = true,
    --- Date format string. See https://cplusplus.com/reference/ctime/strftime/
    --- @type string
    timestamp = "%Y-%m-%dT%H:%M:%S", --ISO 8601 format
    --- Options for file logging.
    file = {
        --- Base path for all log files. Typically the actual log path will be the programName/filename.log appended on to the base_path.
        --- @type string
        base_path = "/bng/logs",
        --- This points to the current log file path during runtime
        --- @type string?
        current_path = nil,
        --- The open file handle
        --- The ReadWriteHandle or nil
        handle = nil,
        --- The max number of log files to keep within the program's log_dir (a subdirectory of base_path)
        --- @type integer
        max_logs = 3,
        --- If true, will append the banner info to the log file
        write_banner = false,
    },
    --- Determines which outputs should be attempted during logging. Defaults to true for 'term' (terminal output).<br>
    -- Example:
    -- `outputs.monitors = {"top"}` -- will attempt to log to a monitor peripheral on the 'top' side
    --- @type table
    outputs = { term = true, file = true },
}

--- @alias LogLevel "debug" | "info" | "success" | "warn" | "error" | "fatal"
--- @alias Color string|integer

-- Define log levels with colors
--- @class LevelInfo
--- @field level integer The numeric level value
--- @field color Color The color value for this level

--- @class Levels
--- @field debug LevelInfo
--- @field info LevelInfo
--- @field success LevelInfo
--- @field warn LevelInfo
--- @field error LevelInfo
--- @field fatal LevelInfo
local LEVELS = {
    debug = { level = 1, color = colors.cyan },
    info  = { level = 2, color = colors.white },
    success = {level = 3, color = colors.green},
    warn  = { level = 4, color = colors.yellow },
    error = { level = 5, color = colors.red },
    fatal = { level = 6, color = colors.magenta }
}

---@module 'util'

---@param deps {util: util}
---@return {new: Logger, get: fun(): Logger}
local function init(deps)
    local util = deps.util

    -- --------------------------- Private Helpers ---------------------------

    ---Returns the formatted message string
    ---@param ... unknown
    ---@return string
    local function format_log(context, ...)
        local args = { ... }
        if #args == 0 then return "" end

        local parts = {}

        -- Add context prefix if present
        if context and next(context) then
            local ctx_parts = {}
            for k, v in pairs(context) do
                table.insert(ctx_parts, string.format("%s=%s", k, tostring(v)))
            end
            if #ctx_parts > 0 then
                table.insert(parts, string.format("[%s]", table.concat(ctx_parts, ",")))
            end
        end

        local firstArg = args[1]

        -- Check if first argument is a format string
        if type(firstArg) == "string" and firstArg:find("%%") then
            --- @cast firstArg string
            --- Function to count format specifiers correctly
            --- @return integer
            local function count_format_specifiers(fmt)
                local count = 0
                for _ in fmt:gmatch("%%[cdieEfgGosuxXpq]") do
                    count = count + 1
                end
                return count
            end

            -- Count required format arguments
            local expectedArgs = count_format_specifiers(firstArg)

            -- Try formatting the string safely
            local success, formattedString = pcall(string.format, table.unpack(args, 1, expectedArgs + 1))

            if success then
                table.insert(parts, formattedString)
                -- Append any extra arguments beyond those used for formatting
                for i = expectedArgs + 2, #args do
                    table.insert(parts, type(args[i]) == "table" and textutils.serialize(args[i]) or tostring(args[i]))
                end
            else
                -- If formatting fails, just concatenate raw arguments
                table.insert(parts, firstArg)
                for i = 2, #args do
                    table.insert(parts, type(args[i]) == "table" and textutils.serialize(args[i]) or tostring(args[i]))
                end
            end
        else
            -- No format string, just serialize all arguments normally
            for _, v in ipairs(args) do
                table.insert(parts, type(v) == "table" and textutils.serialize(v) or tostring(v))
            end
        end

        return table.concat(parts, " ")
    end

    local function merge_context(base_context, new_context)
        if not base_context and not new_context then return nil end
        local merged = util.deep_copy(base_context or {})
        if new_context then
            for k, v in pairs(new_context) do
                merged[k] = v
            end
        end
        return merged
    end

    local function get_new_log_filename(source)
        -- Use epoch time as prefix - guaranteed to be sortable and unique
        local timestamp = os.epoch("utc")
        return string.format("%d_%s.log", timestamp, source or "unknown")
    end

    ---Removes log files that exceed max_logs (keep newest)
    ---@param log_dir string
    ---@param max_logs integer
    local function clean_old_logs(log_dir, max_logs)
        local files = {}
        for _, file in ipairs(fs.list(log_dir)) do
            if file:match("%.log$") then
                table.insert(files, file)
            end
        end

        -- Simple string sort will work since timestamps are at start of filename
        table.sort(files)

        -- Delete oldest logs if exceeding max_logs
        while #files >= max_logs do
            fs.delete(fs.combine(log_dir, table.remove(files, 1)))
        end
    end

    --- Writes the banner info to the log file
    ---@param logger Logger
    local function write_log_banner(logger)
        local handle = logger.config.file.handle
        if not handle then return end

        local banner = {
            "==================== Logger Initialized ====================",
            string.format("Date: %s", os.date("%c")),
            string.format("Computer ID: %d", os.getComputerID()),
            string.format("Computer Label: %s", os.getComputerLabel() or "N/A"),
            string.format("Logger Source: %s (%s)", logger.config.source, shell.getRunningProgram()),
            string.format("OS Version: %s", os.version()),
            string.format("Log level: %s", string.upper(logger.config.level)),
            "==========================================================="
        }

        handle.writeLine(table.concat(banner, "\n") .. "\n")
        handle.flush()
    end

    ---@param side string
    ---@return boolean
    ---@return any
    local function validate_monitor(side)
        if not peripheral.isPresent(side) then
            return false, "peripheral not present on " .. side
        end

        local peripheral_type = peripheral.getType(side)
        if peripheral_type ~= "monitor" then
            return false, "not a monitor, found: " .. peripheral_type
        end

        local mon = peripheral.wrap(side)
        if not mon or type(mon.setTextScale) ~= "function" then
            return false, "failed function check"
        end

        return true, mon
    end

    local function write_to_monitor(mon, output, color)
        local orig_color = mon.getTextColor()
        local prev_term = term.current()

        term.redirect(mon)
        if color then mon.setTextColor(color) end
        print(output)
        mon.setTextColor(orig_color)
        term.redirect(prev_term)
    end

    local function write_to_term(output, color)
        local orig_color = term.getTextColor()
        if color then term.setTextColor(color) end
        print(output)
        term.setTextColor(orig_color)
    end

    local function write_to_file(logger, output)
        local handle = logger.config.file.handle
        if not logger.config.file.handle then
            -- avoid a loop
            logger.config.outputs.file = false
            logger:error("attempt to write to file but no open handle")
            logger.config.outputs.file = true
            return
        end
        local success, err = pcall(handle.writeLine, output)
        if not success then
            logger.config.outputs.file = false
            logger:warn("Log file write failed: %s", err)
            logger.config.outputs.file = true
        else
            handle.flush()
        end
    end

    -- Extract file initialization into a separate function
    local function init_file_logging(self)
        -- close any previous handle
        if self.config.file.handle then
            self.config.file.handle.close()
        end

        if self.config.outputs.file then
            local program_path = shell.getRunningProgram()
            local program_name = program_path:match("bng/programs/([^/]+)/") or "unknown"

            self.config.source = program_name

            -- Set up log directory
            local log_dir = fs.combine(self.config.file.base_path, program_name)
            if not fs.exists(log_dir) then
                fs.makeDir(log_dir)
            end

            -- Clean old logs and set up new log file
            clean_old_logs(log_dir, self.config.file.max_logs)
            self.config.file.current_path = fs.combine(log_dir,
                get_new_log_filename(program_name))

            -- open new file handle
            local success, handle = pcall(fs.open, self.config.file.current_path, "a")
            if not success or not handle then
                self:error("could not open log file: %s", self.config.file.current_path)
            else
                self.config.file.handle = handle
                -- Write initial banner - only for new files AND when write_banner is true
                if fs.getSize(self.config.file.current_path) == 0 and self.config.file.write_banner then
                    write_log_banner(self)
                end
            end
        end
    end

    -- --------------------------- Logger methods ---------------------------

    function Logger.new(config)
        if _instance then
            if config then
                -- Use deep merge for config update
                util.deep_merge(_instance.config, config)
                -- Reinitialize necessary components with new config
                init_file_logging(_instance)
                _instance:sync_monitors()
            end
            return _instance
        end

        ---@class Logger
        local self = setmetatable({}, Logger)
        -- Start with a deep copy of defaults
        self.config = util.deep_copy(DEFAULT_CONFIG)

        -- If config is provided, merge it with defaults
        if config and type(config) == "table" then
            util.deep_merge(self.config, config)
        end

        -- print(textutils.serialize(self.config, {compact = true}))

        if not LEVELS[self.config.level] then
            error("Invalid logging level: " .. tostring(self.config.level))
        end

        -- Use a precomputed level index for fast lookup
        self.current_level_index = LEVELS[self.config.level].level

        init_file_logging(self)

        -- Initialize active monitors table
        self.active_monitors = {}
        self:sync_monitors()

        _instance = self

        return self
    end

    function Logger:configure(config)
        Logger.new(config)
    end

    function Logger:sync_monitors()
        -- Clear current active monitors
        self.active_monitors = {}

        -- Skip if no monitor output configured
        if not self.config.outputs.monitors then return end

        -- Validate each configured monitor
        for _, monitor_name in ipairs(self.config.outputs.monitors) do
            local success, result = validate_monitor(monitor_name)
            if success then
                self.active_monitors[#self.active_monitors + 1] = result
            else
                -- Only log warning if we're not in initialization
                if self.initialized then
                    self:warn("Monitor '%s' validation failed: %s", monitor_name, result)
                end
            end
        end

        -- Set initialization flag after first sync
        self.initialized = true
    end

    function Logger:log(level, context, ...)
        local level_info = LEVELS[level]
        if not level_info then
            error("Invalid log level function: " .. tostring(level))
        end

        if level_info.level < self.current_level_index then
            return
        end

        -- Parameter shifting based on context being a table
        -- If context is not a table, we pass it as a regular arg
        local args
        if type(context) ~= "table" then
            args = { context, ... }
            context = {}
        else
            args = { ... }
        end

        -- Merge inherited context from child loggers
        local merged_context = merge_context(self.context, context)

        -- Format the log message
        local msg = format_log(merged_context, table.unpack(args))
        local timestamp = os.date(self.config.timestamp)
        local levelText = self.config.abbreviate_level and string.sub(level:upper(), 1, 1) or level:upper()
        local output = string.format("[%s] [%s] %s", levelText, timestamp, msg)

        -- Save terminal state once
        local prev_term = term.current()

        -- Handle monitor output
        if self.config.outputs.monitors then
            for _, mon in pairs(self.active_monitors) do
                write_to_monitor(
                    mon, -- Pass the actual monitor peripheral
                    output,
                    self.config.colors and level_info.color or nil
                )
            end
        end

        -- Handle terminal output
        if self.config.outputs.term then
            term.redirect(prev_term) -- Ensure we're on main terminal
            write_to_term(
                output,
                self.config.colors and level_info.color or nil
            )
        end

        -- Handle file output
        if self.config.outputs.file then
            write_to_file(self, output)
        end
    end

    --- Returns a logger instance with added context
    ---@param context table|nil If nil, will attempt to set context as `{module = filename}`. Otherwise, will merge the context with any parent context
    ---@return Logger
    function Logger:child(context)
        if context == nil then
            -- Get the script name of the caller
            local info = debug.getinfo(2, "S")
            local source = info and info.source

            -- Extract filename from `@filename` format
            if source and source:sub(1, 1) == "@" then
                source = source:sub(2) -- Remove the "@" prefix
            else
                source = "unknown"
            end

            context = { module = fs.getName(source) }
        elseif type(context) ~= "table" then
            error("Context must be a table")
        end

        -- Merge the existing context with the new child context
        local merged_context = merge_context(self.context, context)

        -- Create a new lightweight child logger that inherits from the parent
        local child = setmetatable({ context = merged_context, parent = self }, { __index = self })

        return child
    end

    function Logger:close()
        if self.config.file.handle then
            self.config.file.handle.flush()
            self.config.file.handle.close()
            self.config.file.handle = nil
        end
    end

    -- Create level-specific methods
    for level, _ in pairs(LEVELS) do
        Logger[level] = function(self, ...)
            self:log(level, ...)
        end
    end



    return {
        new = Logger.new,
        get = function()
            return _instance or Logger.new()
        end
    }
end

return init
```


## src/util.lua

```lua
---@class util
local M = {}

local function init(deps)
    function M.round(number, digit_position)
        local precision = math.pow(10, digit_position)
        number = number + (precision / 2);
        return math.floor(number / precision) * precision
    end

    ---Get a deep copy of the original. Handles recursive references to avoid a stack overflow.
    ---@generic T
    ---@param original T
    ---@param copy_metatables? boolean If true, will copy metatables of any tables in the original
    ---@return T
    function M.deep_copy(original, copy_metatables)
        if original == nil then return nil end
        if type(original) ~= 'table' then return original end

        -- Default copy_metatables to true if not specified
        if copy_metatables == nil then
            copy_metatables = true
        end

        -- Handle recursive references to avoid stack overflow
        local seen = {}

        local function copy_table(tbl)
            -- Check if we've seen this table before
            if seen[tbl] then return seen[tbl] end

            local tbl_copy = {}

            -- Copy metatable if it exists
            local mt = getmetatable(tbl)
            if copy_metatables and mt then
                setmetatable(tbl_copy, M.deep_copy(mt))
            end

            -- Copy all key/value pairs
            for k, v in pairs(tbl) do
                if type(k) == 'table' then
                    k = copy_table(k)
                end
                if type(v) == 'table' then
                    v = copy_table(v)
                end
                tbl_copy[k] = v
            end

            seen[tbl] = tbl_copy
            return tbl_copy
        end

        return copy_table(original)
    end

    --- Recursively merges two tables, handling both arrays and associative tables.
    --- Arrays are appended, while associative tables are merged by key.
    ---
    --- ### Example
    --- ```lua
    --- local target = {
    ---     arr = {1, 2},           -- Array
    ---     dict = {                -- Associative table
    ---         name = "test",
    ---         config = {
    ---             x = 1,
    ---             y = 2
    ---         }
    ---     }
    --- }
    ---
    --- local source = {
    ---     arr = {3, 4},           -- Array to append
    ---     dict = {                -- Associative table to merge
    ---         config = {
    ---             y = 3,          -- Overwrites y
    ---             z = 4           -- Adds new key
    ---         }
    ---     }
    --- }
    ---
    --- local result = deep_merge(target, source)
    --- -- Result will be:
    --- -- {
    --- --     arr = {1, 2, 3, 4},       -- Arrays are appended
    --- --     dict = {                   -- Tables are merged recursively
    --- --         name = "test",         -- Untouched
    --- --         config = {
    --- --             x = 1,             -- Untouched
    --- --             y = 3,             -- Updated
    --- --             z = 4              -- Added
    --- --         }
    --- --     }
    --- -- }
    --- ```
    --- @param target table: The target table to merge into
    --- @param source table: The source table to merge from. Keys in the source table will **overwrite** keys in the target table.
    --- @return table: The merged table (modified target)
    function M.deep_merge(target, source)
        -- Handle nil cases
        if source == nil then return target end
        if target == nil then return M.deep_copy(source) end

        -- Type check for tables
        if type(target) ~= "table" then error("Target must be a table") end
        if type(source) ~= "table" then error("Source must be a table") end

        -- Handle arrays/sequences differently from associative tables
        -- i.e. checks if there are any keys after the last numeric index
        local is_array = #source > 0 and next(source, #source) == nil

        for k, v in pairs(source) do
            if is_array then
                -- For arrays, append values
                table.insert(target, M.deep_copy(v))
            else
                -- For associative tables, merge recursively
                if type(v) == "table" and type(target[k]) == "table"
                    and not (getmetatable(v) or getmetatable(target[k])) then
                    target[k] = M.deep_merge(target[k], v)
                else
                    -- Handle non-table values and tables with metatables
                    target[k] = M.deep_copy(v)
                end
            end
        end

        return target
    end

    function M.stringify_table(o)
        if type(o) == 'table' then
            local s = '{ '
            for k, v in pairs(o) do
                if type(k) ~= 'number' then k = '"' .. k .. '"' end
                s = s .. '[' .. k .. '] = ' .. M.stringify_table(v) .. ','
            end
            return s .. '} '
        else
            return tostring(o)
        end
    end

    return M
end

return init
```


