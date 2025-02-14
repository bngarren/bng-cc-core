-- ppm.lua
-- Simple Peripheral Manager

---@class PPM
local M = {}

---@type table<string, any>
local peripherals = {}

local function init(deps)

    local log = deps.log

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
            -- print("PPM: Mounted " ..peripheral.getType(side).." on " .. side)
            log:info("PPM: Mounted %s on %s", peripheral.getType(side), side)
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
