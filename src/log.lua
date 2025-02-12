local Logger = {}
Logger.__index = Logger

local DEFAULT_CONFIG = {
    source = nil, -- This will be populated dynamically
    level = "info",
    abbreviate_level = true,
    colors = true,
    timestamp = "%R:%S",
    file = {
        base_path = "/bng/logs",
        current_path = nil,
        max_logs = 3
    },
    outputs = { term = true }
}

-- Define log levels with colors
local LEVELS = {
    trace = { level = 1, color = colors.lightGray },
    debug = { level = 2, color = colors.cyan },
    info  = { level = 3, color = colors.lime },
    warn  = { level = 4, color = colors.yellow },
    error = { level = 5, color = colors.red },
    fatal = { level = 6, color = colors.magenta }
}


local function format_log(...)
    local args = { ... }
    if #args == 0 then return "" end

    local firstArg = args[1]
    local parts = {}

    -- Check if first argument is a format string
    if type(firstArg) == "string" and firstArg:find("%%") then
        -- Function to count format specifiers correctly
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
        copy = {}
        for key, value in pairs(original) do
            copy[key] = deep_copy(value)
        end
    else
        copy = original
    end
    return copy
end

local function get_new_log_filename(source)
    -- Use epoch time as prefix - guaranteed to be sortable and unique
    local timestamp = os.epoch("utc")
    return string.format("%d_%s.log", timestamp, source or "unknown")
end

-- Helper function to get the caller's source file
local function get_caller_source()
    -- Walk up the stack to find the first non-Logger caller
    local level = 3 -- Start at 3 to skip immediate caller and logger methods
    local info = debug.getinfo(level, "S")

    if info and info.source then
        -- Clean up the source path - remove @ prefix if present
        local source = info.source:match("^@?(.+)$")
        if source then
            -- Get the full filename including dots but excluding .lua extension
            local filename = source:match("[^/\\]+$"):gsub("%.lua$", "")
            return filename
        end
    end
    return "unknown"
end

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

local function write_log_banner(logger)
    local file = fs.open(logger.config.file.current_path, "w")
    if not file then return end

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

    file.write(table.concat(banner, "\n") .. "\n\n")
    file.close()
end

local function validate_monitor(monitor_name)
    if not peripheral.isPresent(monitor_name) then
        return false, "Monitor not present"
    end

    if peripheral.getType(monitor_name) ~= "monitor" then
        return false, "Not a monitor"
    end

    local mon = peripheral.wrap(monitor_name)
    if not mon or type(mon.setTextColor) ~= "function" then
        return false, "Invalid monitor instance"
    end

    return true, mon
end

local function write_to_monitor(mon, output, color)
    local orig_color = mon.getTextColor()
    local prev_term = term.current()

    term.redirect(mon)
    if color then mon.setTextColor(color) end
    print(output)
    if color then mon.setTextColor(orig_color) end
    term.redirect(prev_term)
end

local function write_to_term(output, color)
    local orig_color = term.getTextColor()
    if color then term.setTextColor(color) end
    print(output)
    if color then term.setTextColor(orig_color) end
end

local function write_to_file(logger, output)
    local filepath = logger.config.file.current_path
    local success, file = pcall(fs.open, filepath, "a")

    if not success or not file then
        return logger:error("Could not open log file: %s", filepath)
    end

    file.write(output .. "\n")
    file.close()
end


function Logger.new(config)
    local self = setmetatable({}, Logger)

    -- Start with a deep copy of defaults
    self.config = deep_copy(DEFAULT_CONFIG)

    -- If config is provided, merge it with defaults
    if config and type(config) == "table" then
        for k, v in pairs(config) do
            if type(v) == "table" and type(self.config[k]) == "table" then
                -- For nested tables, merge recursively
                for subk, subv in pairs(v) do
                    self.config[k][subk] = subv
                end
            else
                -- For non-table values, simply overwrite
                self.config[k] = v
            end
        end
    end

    -- print(textutils.serialize(self.config, {compact = true}))

    if not LEVELS[self.config.level] then
        error("Invalid logging level: " .. tostring(self.config.level))
    end

    -- Use a precomputed level index for fast lookup
    self.current_level_index = LEVELS[self.config.level].level

    -- [[[[[[ File logging init ]]]]]]

    -- Set source if not explicitly provided
    if not self.config.source then
        self.config.source = get_caller_source()
    end

    -- Ensure log directory exists

    local log_dir = fs.combine(self.config.file.base_path, self.config.source)
    if not fs.exists(log_dir) then
        fs.makeDir(log_dir)
    end

    clean_old_logs(log_dir, self.config.file.max_logs) -- Keep max # logs

    -- Set up new log file
    local new_log_filename = get_new_log_filename(self.config.source)
    self.config.file.current_path = fs.combine(log_dir, new_log_filename)

    -- Initialize active monitors table
    self.active_monitors = {}
    self:sync_monitors()

    -- Write log banner
    write_log_banner(self)

    return self
end

function Logger:set_level(level)
    if not LEVELS[level] then
        error("Invalid logging level: " .. tostring(level))
    end
    self.config.level = level
    self.current_level_index = LEVELS[level].level
    return self
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

function Logger:log(level, ...)
    local level_info = LEVELS[level]
    if not level_info then
        error("Invalid log level function: " .. tostring(level))
    end

    if level_info.level < self.current_level_index then
        return
    end

    local msg = format_log(...)
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
    if self.config.file then
        write_to_file(self, output)
    end
end

-- Create level-specific methods
for level, _ in pairs(LEVELS) do
    Logger[level] = function(self, ...)
        self:log(level, ...)
    end
end

-- ***** Logger Builder

local LoggerBuilder = {}
LoggerBuilder.__index = LoggerBuilder

function LoggerBuilder.new()
    local self = setmetatable({}, LoggerBuilder)
    -- Initialize with empty config
    self.config = deep_copy(DEFAULT_CONFIG)

    return self
end

function LoggerBuilder:with_level(level)
    self.config.level = level
    return self
end

function LoggerBuilder:with_source(source)
    self.config.source = source
    return self
end

function LoggerBuilder:with_colors(enabled)
    self.config.colors = enabled
    return self
end

function LoggerBuilder:with_timestamp_format(format)
    self.config.timestamp = format
    return self
end

function LoggerBuilder:with_abbreviated_level(enabled)
    self.config.abbreviate_level = enabled
    return self
end

function LoggerBuilder:with_max_log_files(max)
    self.config.file.max_logs = max
    return self
end

function LoggerBuilder:with_terminal_output(enabled)
    self.config.outputs.term = enabled
    return self
end

function LoggerBuilder:with_monitor_output(monitor_names)
    if type(monitor_names) == "string" then
        monitor_names = { monitor_names }
    end
    self.config.outputs.monitors = monitor_names
    return self
end

function LoggerBuilder:build()
    -- If source wasn't explicitly set via with_source(), get it here
    if not self.config.source then
        self.config.source = get_caller_source()
    end

    local instance = Logger.new(self.config)
    setmetatable(instance, Logger)
    return instance
end

return LoggerBuilder


-- return Logger
