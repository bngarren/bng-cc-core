local Logger = {}
Logger.__index = Logger

local DEFAULT_CONFIG = {
    level = "info",
    abbreviate_level = true,
    colors = true,
    timestamp = "%Y-%m-%d %H:%M:%S",
    file = nil,
    outputs = { term = true, monitors = {"top"} }
}

-- Define log levels with colors
local LEVELS = {
    trace = { color = colors.lightGray },
    debug = { color = colors.cyan },  
    info  = { color = colors.lime },  
    warn  = { color = colors.yellow },
    error = { color = colors.red },
    fatal = { color = colors.magenta }
}

-- Order matters for level comparison
local LEVEL_ORDER = {"trace", "debug", "info", "warn", "error", "fatal"}
local level_map = {}
for i, level in ipairs(LEVEL_ORDER) do
    level_map[level] = i
end

local function format_log(...)
    local args = { ... }
    local formatted_parts = {}
    for _, v in ipairs(args) do
        if type(v) == "table" then
            table.insert(formatted_parts, textutils.serialize(v))
        else
            table.insert(formatted_parts, tostring(v))
        end
    end
    return table.concat(formatted_parts, " ")
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

function Logger.new(config)
    local self = setmetatable({}, Logger)
    
    -- Create a deep copy of defaults
    local settings = deep_copy(DEFAULT_CONFIG)
    
    -- Override with user config if provided
    if config then
        for k, v in pairs(config) do
            settings[k] = v
        end
    end

    -- Apply settings to instance
    for k, v in pairs(settings) do
        self[k] = v
    end

    -- Validate level
    if not self.level or not level_map[self.level] then
        error("Invalid log level: " .. tostring(self.level))
    end

    return self
end

function Logger:log(level, ...)
    -- Validate both levels exist before comparing
    if not level_map[level] then
        error("Invalid log level: " .. tostring(level))
    end
    
    if not level_map[self.level] then
        error("Logger instance has invalid level: " .. tostring(self.level))
    end

    -- Now we can safely compare them
    if level_map[level] < level_map[self.level] then
        return
    end

    local msg = format_log(...)
    local timestamp = os.date(self.timestamp)
    local levelText = self.abbreviate_level and string.sub(level:upper(), 1, 1) or level:upper()
    local output = string.format("[%s] [%s] %s", timestamp, levelText, msg)

    if self.outputs.term then
        if self.colors then
            local originalColor = term.getTextColor()
            term.setTextColor(LEVELS[level].color)
            print(output)
            term.setTextColor(originalColor)
        else
            print(output)
        end
    end

    if self.file then
        local file = fs.open(self.file, "a")
        if file then
            file.write(output .. "\n")
            file.close()
        else
            error("Could not open log file: " .. self.file)
        end
    end
end

-- Create level-specific methods
for _, level in ipairs(LEVEL_ORDER) do
    Logger[level] = function(self, ...)
        self:log(level, ...)
    end
end

function Logger:set_level(level)
    if not level_map[level] then
        error("Invalid log level: " .. tostring(level))
    end
    self.level = level
    return self
end

return Logger
