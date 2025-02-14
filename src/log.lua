--- @class Logger
local Logger = {}
Logger.__index = Logger

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

-- Define log levels with colors
--- @enum (key) LogLevel
local LEVELS = {
    trace = { level = 1, color = colors.lightGray },
    debug = { level = 2, color = colors.cyan },
    info  = { level = 3, color = colors.white },
    warn  = { level = 4, color = colors.yellow },
    error = { level = 5, color = colors.red },
    fatal = { level = 6, color = colors.magenta }
}


---Returns the formatted message string
---@param ... unknown
---@return string
local function format_log(context,...)
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

-- Deep copy helper function
local function deep_copy(original)
    local copy
    if type(original) == 'table' then
        ---@cast original table
        copy = {}
        for key, value in pairs(original) do
            copy[key] = deep_copy(value)
        end
    else
        copy = original
    end
    return copy
end

local function deep_merge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            -- Recursively merge nested tables
            deep_merge(target[k], v)
        else
            -- Direct assignment for non-table values
            target[k] = v
        end
    end
    return target
end

local function merge_context(base_context, new_context)
    if not base_context and not new_context then return nil end
    local merged = deep_copy(base_context or {})
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

-- Create a child logger class
--- @class ChildLogger
local ChildLogger = {}
ChildLogger.__index = ChildLogger

function ChildLogger.new(parent, context)
    ---@class ChildLogger
    local self = setmetatable({}, ChildLogger)
    self.parent = parent
    self.context = context
    return self
end

-- Forward all log methods to parent with merged context
for level, _ in pairs(LEVELS) do
    ChildLogger[level] = function(self, ...)
        local first, _ = ...
        local new_context = type(first) == "table" and first or nil
        local merged_context = merge_context(self.context, new_context)
        
        if new_context then
            self.parent:log(level, merged_context, select(2, ...))
        else
            self.parent:log(level, merged_context, ...)
        end
    end
end

-- Allow child loggers to create their own children
function ChildLogger:child(context)
    if type(context) ~= "table" then
        error("Context must be a table")
    end
    local merged_context = merge_context(self.context, context)
    return ChildLogger.new(self.parent, merged_context)
end


function Logger.new(config)
    if _instance then
        if config then
            -- Use deep merge for config update
            deep_merge(_instance.config, config)
            -- Reinitialize necessary components with new config
            init_file_logging(_instance)
            _instance:sync_monitors()
        end
        return _instance
    end

    ---@class Logger
    local self = setmetatable({}, Logger)
    -- Start with a deep copy of defaults
    self.config = deep_copy(DEFAULT_CONFIG)

    -- If config is provided, merge it with defaults
    if config and type(config) == "table" then
        deep_merge(self.config, config)
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
        args = {context, ...}
        context = {}
    else
        args = {...}
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
                self.config.colors and LEVELS[level].color
            )
        end
    end

    -- Handle terminal output
    if self.config.outputs.term then
        term.redirect(prev_term) -- Ensure we're on main terminal
        write_to_term(
            output,
            self.config.colors and LEVELS[level].color
        )
    end

    -- Handle file output
    if self.config.outputs.file then
        write_to_file(self, output)
    end
end

-- Create child logger (similar to pino.child())
function Logger:child(context)
    if type(context) ~= "table" then
        error("Context must be a table")
    end
    return ChildLogger.new(self, context)
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
    get = function ()
        return _instance or Logger.new()
    end
}
