-- ppm.lua
-- Simple Peripheral Manager


local ppm = {}

local function init(deps)

    local log = deps.log

    local peripherals = {}

    -- Wrap a peripheral safely
    local function safe_wrap(side)
        if peripheral.isPresent(side) then
            return peripheral.wrap(side)
        else
            return nil
        end
    end

    -- Mount all peripherals
    function ppm.mount_all()
        peripherals = {} -- Clear existing mounts
        for _, side in ipairs(peripheral.getNames()) do
            peripherals[side] = safe_wrap(side)
            -- print("PPM: Mounted " ..peripheral.getType(side).." on " .. side)
            log:info("PPM: Mounted %s on %s", peripheral.getType(side), side)
        end
    end

    -- Get a peripheral
    function ppm.get(side)
        if peripherals[side] then
            return peripherals[side]
        else
            peripherals[side] = safe_wrap(side)
            return peripherals[side]
        end
    end

    -- Handle peripheral detach event
    function ppm.handle_unmount(side)
        if peripherals[side] then
            print("PPM: Unmounted " .. side)
            peripherals[side] = nil
        end
    end

    return ppm
end

return init
