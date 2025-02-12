local Logger = {}
Logger.__index = Logger

local DEFAULT_CONFIG = {
    level = "info",
    abbreviate_level = true,
    colors = true,
    timestamp = "%R:%S",
    file = {
        dir_path = "/bng/logs",
        current_path = nil,
        max_logs = 5
    },
    outputs = { term = true, monitors = { "top" } }
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

local function get_new_log_filename()
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local source = debug.getinfo(3, "S").short_src or "unknown"

    -- Remove directory path and extension from source file
    source = source:match("([^/\\]+)%.") or source -- Extract only the filename without extension

    return string.format("%s_%s.log", timestamp, source)
end


local function clean_old_logs(log_dir, max_logs)
    if not fs.exists(log_dir) then fs.makeDir(log_dir) end

    local files = {}
    for _, file in ipairs(fs.list(log_dir)) do
        if file:match("^log_%d+_%d+%.txt$") then
            table.insert(files, file)
        end
    end

    table.sort(files, function(a, b) return a < b end) -- Oldest first

    -- Delete oldest logs if exceeding max_logs
    while #files > max_logs do
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
        string.format("Logger Source: %s", debug.getinfo(3, "S").short_src or "Unknown"),
        string.format("OS Version: %s", os.version()),
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

    -- Merge user config with defaults
    self.config = {}
    for k, v in pairs(DEFAULT_CONFIG) do
        self.config[k] = (config and config[k] ~= nil) and config[k] or v
    end

    if not LEVELS[self.config.level] then
        error("Invalid logging level: " .. tostring(self.config.level))
    end

    -- Use a precomputed level index for fast lookup
    self.current_level_index = LEVELS[self.config.level].level

    -- File logging init
    -- Ensure log directory exists
    if not fs.exists(self.config.file.dir_path) then
        fs.makeDir(self.config.file.dir_path)
    end

    clean_old_logs(self.config.file.dir_path, self.config.file.max_logs) -- Keep max 5 logs

    -- Set up new log file
    self.config.file.current_path = fs.combine(self.config.file.dir_path, get_new_log_filename())

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
                mon,  -- Pass the actual monitor peripheral
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


return Logger
