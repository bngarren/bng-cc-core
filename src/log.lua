local Logger = {}
Logger.__index = Logger

local DEFAULT_CONFIG = {
    level = "info",
    abbreviate_level = true,
    colors = true,
    timestamp = "%R:%S",
    file = "log.txt",
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
    local args = {...}
    if #args == 0 then return "" end
    
    local parts = {}
    
    -- If first arg is string and contains formatting patterns, handle initial formatting
    if type(args[1]) == "string" and args[1]:find("%%") then
        -- Find number of format specifiers in the pattern
        local specifiers = 0
        for _ in args[1]:gmatch("%%") do
            specifiers = specifiers + 1
        end
        
        -- Format the pattern with its arguments
        local success, result = pcall(string.format, table.unpack(args, 1, specifiers + 1))
        if success then
            parts[1] = result
            -- Add any remaining arguments
            for i = specifiers + 2, #args do
                if type(args[i]) == "table" then
                    parts[#parts + 1] = textutils.serialize(args[i])
                else
                    parts[#parts + 1] = tostring(args[i])
                end
            end
        end
    end
    
    -- If format handling failed or wasn't attempted, process normally
    if #parts == 0 then
        for i, v in ipairs(args) do
            if type(v) == "table" then
                parts[i] = textutils.serialize(v)
            else
                parts[i] = tostring(v)
            end
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

function Logger.new(config)
    local self = setmetatable({}, Logger)
    
    -- Initialize config with defaults
    self.config = deep_copy(DEFAULT_CONFIG)
    
    -- Override with user config if provided
    if config then
        for k, v in pairs(config) do
            self.config[k] = v
        end
    end

    if not LEVELS[self.config.level] then
        error("Invalid logging level: " .. tostring(self.config.level))
    end

    return self
end

function Logger:set_level(level)
    if not LEVELS[level] then
        error("Invalid logging level: " .. tostring(level))
    end
    self.config.level = level
    return self
end

function Logger:log(level, ...)
    local level_info = LEVELS[level]
    if not level_info then
        error("Invalid log level function: " .. tostring(level))
    end
    
    if level_info.level < LEVELS[self.config.level].level then
        return
    end

    local msg = format_log(...)
    local timestamp = os.date(self.config.timestamp)
    local levelText = self.config.abbreviate_level and string.sub(level:upper(), 1, 1) or level:upper()
    local output = string.format("[%s] [%s] %s", levelText, timestamp, msg)

    if self.config.outputs.term then
        if self.config.colors then
            local originalColor = term.getTextColor()
            term.setTextColor(LEVELS[level].color)
            print(output)
            term.setTextColor(originalColor)
        else
            print(output)
        end
    end

    if self.config.file then
        local file = fs.open(self.config.file, "a")
        if file then
            file.write(output .. "\n")
            file.close()
        else
            error("Could not open log file: " .. self.config.file)
        end
    end
end

-- Create level-specific methods
for level, _ in pairs(LEVELS) do
    Logger[level] = function(self, ...)
        self:log(level, ...)
    end
end


return Logger
